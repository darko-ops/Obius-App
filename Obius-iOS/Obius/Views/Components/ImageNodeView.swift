import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Renders an image node's content: empty state, single image, or swipeable images.
/// Feathered edges blend into whatever background the parent provides.
struct ImageNodeView: View {
    let imageHashes: [String]
    let mediaRepository: MediaRepository
    let onTap: () -> Void
    var onDominantColorChanged: ((Color) -> Void)? = nil
    var onPageChanged: ((Int) -> Void)? = nil
    var onCurrentImageChanged: ((PlatformImage?) -> Void)? = nil

    @State private var loadedImages: [String: PlatformImage] = [:]
    @State private var currentPage = 0
    @State private var showDots = false
    @State private var dotsHideTask: Task<Void, Never>?
    @State private var dominantColor: Color?

    var body: some View {
        Group {
            if imageHashes.isEmpty {
                emptyState
            } else if imageHashes.count == 1 {
                singleImageView
            } else {
                multiImageView
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onAppear { loadImages() }
        .onChange(of: imageHashes) { _, _ in loadImages() }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.15))
            .frame(height: 160)
            .overlay {
                Image(systemName: "photo")
                    .font(.system(size: 36))
                    .foregroundStyle(.gray)
            }
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
    }

    // MARK: - Single Image

    private var singleImageView: some View {
        Group {
            if let hash = imageHashes.first, let image = loadedImages[hash] {
                platformImage(image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .clipped()
                    .mask(edgeFeatherGradient)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    // MARK: - Multi Image (Swipeable)

    private var multiImageView: some View {
        TabView(selection: $currentPage) {
            ForEach(Array(imageHashes.enumerated()), id: \.element) { index, hash in
                Group {
                    if let image = loadedImages[hash] {
                        platformImage(image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .clipped()
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { onTap() }
                .tag(index)
            }
        }
        #if os(iOS)
        .tabViewStyle(.page(indexDisplayMode: .never))
        #endif
        .frame(height: 240)
        .mask(edgeFeatherGradient)
        .overlay(alignment: .bottom) {
            if imageHashes.count > 1 && showDots {
                pageDotsView
                    .transition(.opacity)
            }
        }
        .onChange(of: currentPage) { _, newPage in
            flashDots()
            onPageChanged?(newPage)
            notifyCurrentImage()
        }
    }

    /// Custom page indicator dots
    private var pageDotsView: some View {
        HStack(spacing: 6) {
            ForEach(0..<imageHashes.count, id: \.self) { index in
                Circle()
                    .fill(index == currentPage ? Color.white : Color.white.opacity(0.4))
                    .frame(width: 7, height: 7)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.black.opacity(0.35)))
        .padding(.bottom, 8)
    }

    /// Show dots briefly then fade them out
    private func flashDots() {
        dotsHideTask?.cancel()
        withAnimation(.easeIn(duration: 0.15)) { showDots = true }
        dotsHideTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.4)) { showDots = false }
        }
    }

    // MARK: - Edge Feather Mask

    private var edgeFeatherGradient: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .white, location: 0.02),
                .init(color: .white, location: 0.98),
                .init(color: .clear, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white, location: 0.03),
                    .init(color: .white, location: 0.97),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // MARK: - Helpers

    private func platformImage(_ image: PlatformImage) -> Image {
        #if os(iOS)
        Image(uiImage: image)
        #else
        Image(nsImage: image)
        #endif
    }

    // MARK: - Image Loading

    private func loadImages() {
        var didLoadNew = false
        var missingHashes: [String] = []
        for hash in imageHashes where loadedImages[hash] == nil {
            if let data = try? mediaRepository.getMediaData(hash: hash),
               let image = PlatformImage(data: data) {
                loadedImages[hash] = image
                didLoadNew = true
            } else {
                missingHashes.append(hash)
            }
        }
        if didLoadNew {
            computeDominantColor()
            notifyCurrentImage()
        }
        // Try cloud download for any missing images
        if !missingHashes.isEmpty {
            let repo = mediaRepository
            Task {
                for hash in missingHashes {
                    if let data = await repo.getMediaDataWithCloudFallback(hash: hash),
                       let image = PlatformImage(data: data) {
                        await MainActor.run {
                            loadedImages[hash] = image
                            computeDominantColor()
                            notifyCurrentImage()
                        }
                    }
                }
            }
        }
    }

    private func computeDominantColor() {
        let colors: [PlatformColor] = imageHashes.compactMap { hash in
            loadedImages[hash]?.averageColor
        }
        guard !colors.isEmpty else { return }

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        for color in colors {
            var cr: CGFloat = 0, cg: CGFloat = 0, cb: CGFloat = 0, ca: CGFloat = 0
            #if os(macOS)
            let rgbColor = color.usingColorSpace(.sRGB) ?? color
            rgbColor.getRed(&cr, green: &cg, blue: &cb, alpha: &ca)
            #else
            color.getRed(&cr, green: &cg, blue: &cb, alpha: &ca)
            #endif
            r += cr; g += cg; b += cb
        }
        let count = CGFloat(colors.count)
        let avgColor = Color(red: Double(r / count), green: Double(g / count), blue: Double(b / count))
        dominantColor = avgColor
        onDominantColorChanged?(avgColor)
    }

    private func notifyCurrentImage() {
        let hash = imageHashes.indices.contains(currentPage) ? imageHashes[currentPage] : imageHashes.first
        if let hash, let image = loadedImages[hash] {
            onCurrentImageChanged?(image)
        }
    }
}

// MARK: - Fullscreen Image Viewer

/// Identifiable wrapper for presenting the fullscreen viewer via `.fullScreenCover(item:)`.
struct FullscreenImageItem: Identifiable {
    let id = UUID()
    let sectionId: String
}

/// Fullscreen swipeable image viewer with close and edit buttons.
struct FullscreenImageViewer: View {
    let imageEntries: [(hash: String, assetId: String)]
    let mediaRepository: MediaRepository
    let onEditSave: (_ keptEntries: [(hash: String, assetId: String)], _ newPicks: [(PlatformImage, String?)]) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var currentPage: Int
    @State private var loadedImages: [String: PlatformImage] = [:]
    @State private var showingEditSheet = false
    @State private var dragOffset: CGFloat = 0

    private var dragProgress: Double {
        Double(min(abs(dragOffset) / 300.0, 1.0))
    }

    private var imageHashes: [String] { imageEntries.map(\.hash) }

    init(imageEntries: [(hash: String, assetId: String)], mediaRepository: MediaRepository, startPage: Int = 0, onEditSave: @escaping (_ keptEntries: [(hash: String, assetId: String)], _ newPicks: [(PlatformImage, String?)]) -> Void) {
        self.imageEntries = imageEntries
        self.mediaRepository = mediaRepository
        self.onEditSave = onEditSave
        _currentPage = State(initialValue: startPage)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(1.0 - dragProgress * 0.5)
                .ignoresSafeArea()

            Group {
                if imageHashes.isEmpty {
                    Text("No images")
                        .foregroundStyle(.white.opacity(0.5))
                } else if imageHashes.count == 1 {
                    singleImage
                } else {
                    swipeableImages
                }
            }
            .offset(y: dragOffset)
            .scaleEffect(1.0 - dragProgress * 0.1)
        }
        .overlay(alignment: .topLeading) {
            if imageHashes.count > 1 {
                Text("\(currentPage + 1) / \(imageHashes.count)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.15)))
                    .padding()
                    .opacity(1.0 - dragProgress * 2)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Circle().fill(Color.white.opacity(0.15)))
            }
            .padding()
            .opacity(1.0 - dragProgress * 2)
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                showingEditSheet = true
            } label: {
                Text("Edit")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(0.15)))
            }
            .padding()
            .opacity(1.0 - dragProgress * 2)
        }
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    if abs(value.translation.height) > abs(value.translation.width) {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if abs(value.translation.height) > 150 {
                        dismiss()
                    } else {
                        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .sheet(isPresented: $showingEditSheet) {
            ImageEditSheet(
                entries: imageEntries,
                mediaRepository: mediaRepository,
                onSave: { keptEntries, newPicks in
                    onEditSave(keptEntries, newPicks)
                    dismiss()
                }
            )
        }
        .onAppear { loadImages() }
        #if os(iOS)
        .statusBarHidden()
        #endif
    }

    private func platformImage(_ image: PlatformImage) -> Image {
        #if os(iOS)
        Image(uiImage: image)
        #else
        Image(nsImage: image)
        #endif
    }

    private var singleImage: some View {
        Group {
            if let hash = imageHashes.first, let image = loadedImages[hash] {
                platformImage(image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().tint(.white)
            }
        }
    }

    private var swipeableImages: some View {
        TabView(selection: $currentPage) {
            ForEach(Array(imageHashes.enumerated()), id: \.element) { index, hash in
                Group {
                    if let image = loadedImages[hash] {
                        platformImage(image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ProgressView().tint(.white)
                    }
                }
                .tag(index)
            }
        }
        #if os(iOS)
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        #endif
    }

    private func loadImages() {
        for hash in imageHashes where loadedImages[hash] == nil {
            if let data = try? mediaRepository.getMediaData(hash: hash),
               let image = PlatformImage(data: data) {
                loadedImages[hash] = image
            }
        }
    }
}

// MARK: - Image Edit Sheet

/// Grid sheet for managing node images — toggle selection to remove, add new from library.
struct ImageEditSheet: View {
    let entries: [(hash: String, assetId: String)]
    let mediaRepository: MediaRepository
    let onSave: (_ keptEntries: [(hash: String, assetId: String)], _ newPicks: [(PlatformImage, String?)]) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectionOrder: [SelectionItem]
    @State private var loadedImages: [String: PlatformImage] = [:]
    @State private var newPicks: [NewPick] = []
    @State private var showingPicker = false
    @State private var pickerID = UUID()

    enum SelectionItem: Equatable, Hashable {
        case existing(hash: String)
        case newPick(id: UUID)
    }

    struct NewPick: Identifiable {
        let id = UUID()
        let image: PlatformImage
        let assetId: String?
    }

    init(entries: [(hash: String, assetId: String)], mediaRepository: MediaRepository, onSave: @escaping (_ keptEntries: [(hash: String, assetId: String)], _ newPicks: [(PlatformImage, String?)]) -> Void) {
        self.entries = entries
        self.mediaRepository = mediaRepository
        self.onSave = onSave
        _selectionOrder = State(initialValue: entries.map { .existing(hash: $0.hash) })
    }

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(entries, id: \.hash) { entry in
                        existingCell(entry: entry)
                    }
                    ForEach(newPicks) { pick in
                        newPickCell(pick: pick)
                    }
                    addCell
                }
                .padding(2)
            }
            .navigationTitle("Edit Photos")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }
                        .fontWeight(.semibold)
                }
            }
        }
        .sheet(isPresented: $showingPicker) {
            ImagePickerView(
                preselectedAssetIdentifiers: allPreselectedAssetIds(),
                onImagesPicked: { results in
                    reconcilePickerResults(results)
                }
            )
            .id(pickerID)
        }
        .onAppear { loadImages() }
    }

    // MARK: - Cells

    private func platformImage(_ image: PlatformImage) -> Image {
        #if os(iOS)
        Image(uiImage: image)
        #else
        Image(nsImage: image)
        #endif
    }

    @ViewBuilder
    private func existingCell(entry: (hash: String, assetId: String)) -> some View {
        let item = SelectionItem.existing(hash: entry.hash)
        let orderIndex = selectionOrder.firstIndex(of: item)
        let isSelected = orderIndex != nil

        if let image = loadedImages[entry.hash] {
            Color.gray.opacity(0.1)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    platformImage(image)
                        .resizable()
                        .scaledToFit()
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(alignment: .topTrailing) {
                    selectionBadge(isSelected: isSelected, orderNumber: orderIndex.map { $0 + 1 })
                }
                .opacity(isSelected ? 1.0 : 0.4)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if isSelected {
                            selectionOrder.removeAll { $0 == item }
                        } else {
                            selectionOrder.append(item)
                        }
                    }
                }
        } else {
            Color.gray.opacity(0.15)
                .aspectRatio(1, contentMode: .fit)
        }
    }

    @ViewBuilder
    private func newPickCell(pick: NewPick) -> some View {
        let item = SelectionItem.newPick(id: pick.id)
        let orderIndex = selectionOrder.firstIndex(of: item)
        let isSelected = orderIndex != nil

        Color.gray.opacity(0.1)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                platformImage(pick.image)
                    .resizable()
                    .scaledToFit()
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(alignment: .topTrailing) {
                selectionBadge(isSelected: isSelected, orderNumber: orderIndex.map { $0 + 1 })
            }
            .opacity(isSelected ? 1.0 : 0.4)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isSelected {
                        selectionOrder.removeAll { $0 == item }
                    } else {
                        selectionOrder.append(item)
                    }
                }
            }
    }

    private func selectionBadge(isSelected: Bool, orderNumber: Int?) -> some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.blue : Color.black.opacity(0.3))
                .frame(width: 26, height: 26)
            Circle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: 26, height: 26)
            if isSelected, let number = orderNumber {
                Text("\(number)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .padding(6)
    }

    private var addCell: some View {
        Button {
            pickerID = UUID()
            showingPicker = true
        } label: {
            Color.gray.opacity(0.15)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay {
                    VStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.title3)
                        Text("Add")
                            .font(.caption)
                    }
                    .foregroundStyle(.gray)
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func allPreselectedAssetIds() -> [String] {
        var ids: [String] = []
        for item in selectionOrder {
            switch item {
            case .existing(let hash):
                if let entry = entries.first(where: { $0.hash == hash }), !entry.assetId.isEmpty {
                    ids.append(entry.assetId)
                }
            case .newPick(let id):
                if let pick = newPicks.first(where: { $0.id == id }),
                   let assetId = pick.assetId, !assetId.isEmpty {
                    ids.append(assetId)
                }
            }
        }
        return ids
    }

    private func reconcilePickerResults(_ results: [(PlatformImage, String?)]) {
        let allKnownAssetIds = Set(
            entries.map(\.assetId).filter { !$0.isEmpty } +
            newPicks.compactMap(\.assetId)
        )

        for (image, pickedAssetId) in results {
            if let pickedAssetId, allKnownAssetIds.contains(pickedAssetId) {
                continue
            }
            let pick = NewPick(image: image, assetId: pickedAssetId)
            newPicks.append(pick)
            selectionOrder.append(.newPick(id: pick.id))
        }
    }

    private func loadImages() {
        for entry in entries where loadedImages[entry.hash] == nil {
            if let data = try? mediaRepository.getMediaData(hash: entry.hash),
               let image = PlatformImage(data: data) {
                loadedImages[entry.hash] = image
            }
        }
    }

    private func save() {
        var keptEntries: [(hash: String, assetId: String)] = []
        var keptNewPicks: [(PlatformImage, String?)] = []

        for item in selectionOrder {
            switch item {
            case .existing(let hash):
                if let entry = entries.first(where: { $0.hash == hash }) {
                    keptEntries.append(entry)
                }
            case .newPick(let id):
                if let pick = newPicks.first(where: { $0.id == id }) {
                    keptNewPicks.append((pick.image, pick.assetId))
                }
            }
        }

        onSave(keptEntries, keptNewPicks)
        dismiss()
    }
}

// MARK: - PlatformImage Average Color

#if os(iOS)
extension UIImage {
    var averageColor: UIColor? {
        guard let ciImage = CIImage(image: self) else { return nil }
        let extent = ciImage.extent
        let extentVector = CIVector(x: extent.origin.x, y: extent.origin.y,
                                     z: extent.size.width, w: extent.size.height)
        guard let filter = CIFilter(name: "CIAreaAverage",
                                     parameters: [kCIInputImageKey: ciImage,
                                                  kCIInputExtentKey: extentVector]),
              let outputImage = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
        context.render(outputImage, toBitmap: &bitmap, rowBytes: 4,
                      bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                      format: .RGBA8, colorSpace: nil)

        return UIColor(red: CGFloat(bitmap[0]) / 255.0,
                       green: CGFloat(bitmap[1]) / 255.0,
                       blue: CGFloat(bitmap[2]) / 255.0,
                       alpha: 1.0)
    }
}
#elseif os(macOS)
extension NSImage {
    var averageColor: NSColor? {
        guard let tiffData = tiffRepresentation,
              let ciImage = CIImage(data: tiffData) else { return nil }
        let extent = ciImage.extent
        let extentVector = CIVector(x: extent.origin.x, y: extent.origin.y,
                                     z: extent.size.width, w: extent.size.height)
        guard let filter = CIFilter(name: "CIAreaAverage",
                                     parameters: [kCIInputImageKey: ciImage,
                                                  kCIInputExtentKey: extentVector]),
              let outputImage = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
        context.render(outputImage, toBitmap: &bitmap, rowBytes: 4,
                      bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                      format: .RGBA8, colorSpace: nil)

        return NSColor(red: CGFloat(bitmap[0]) / 255.0,
                       green: CGFloat(bitmap[1]) / 255.0,
                       blue: CGFloat(bitmap[2]) / 255.0,
                       alpha: 1.0)
    }
}
#endif
