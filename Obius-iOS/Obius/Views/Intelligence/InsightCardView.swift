import SwiftUI

// MARK: - Category Card (Summary for one insight category)

struct CategoryCardView: View {
    let insightType: InsightType
    let insights: [Insight]
    let onTap: () -> Void

    private var summaryLine: String {
        var counts: [String: Int] = [:]
        for insight in insights {
            counts[insight.displayLabel, default: 0] += 1
        }
        return counts.sorted { $0.key < $1.key }
            .map { "\($0.value) \($0.key.lowercased())" }
            .joined(separator: " · ")
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(insightType.label)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    if !summaryLine.isEmpty {
                        Text(summaryLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Text("\(insights.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Insight Row (for use in CategoryDetailSheet)

struct InsightRowView: View {
    let insight: Insight
    let onTrack: () -> Void
    let onDismiss: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(insight.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if !insight.body.isEmpty {
                    Text(insight.body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 16) {
                Button {
                    onTrack()
                } label: {
                    Image(systemName: "star")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// MARK: - Category Detail Sheet

/// Full-screen sheet listing individual insights within a single category.
struct CategoryDetailSheet: View {
    let insightType: InsightType
    let insights: [Insight]
    let onTrack: (Insight) -> Void
    let onDismiss: (Insight) -> Void
    let onSelectInsight: (Insight) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(insights) { insight in
                        InsightRowView(
                            insight: insight,
                            onTrack: { onTrack(insight) },
                            onDismiss: { onDismiss(insight) },
                            onTap: { onSelectInsight(insight) }
                        )
                        .padding(.horizontal)

                        if insight.id != insights.last?.id {
                            Divider()
                                .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(insightType.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Tracked Insight Card (Compact, horizontal scroll)

struct TrackedInsightChip: View {
    let insight: Insight
    let onTap: () -> Void
    let onUntrack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Image(systemName: insight.displayIcon)
                    .font(.system(size: 8))
                Text(insight.displayLabel)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(insight.displayTint.color)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(insight.displayTint.color.opacity(0.15))
            .clipShape(Capsule())

            Text(insight.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)

            if !insight.body.isEmpty {
                Text(insight.body)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(8)
        .frame(width: 150, height: 110, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.06, green: 0.06, blue: 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(insight.displayTint.color.opacity(0.3), lineWidth: 1)
        )
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            Button {
                onUntrack()
            } label: {
                Label("Untrack", systemImage: "star.slash")
            }

            Button(role: .destructive) {
                onUntrack()
            } label: {
                Label("Dismiss", systemImage: "xmark")
            }
        }
        .onTapGesture { onTap() }
    }
}

// MARK: - Echo Card (Compact, horizontal scroll)

struct UpcomingEchoCard: View {
    let insight: Insight
    let onTap: () -> Void
    let onLongPress: () -> Void

    private var isFiring: Bool {
        insight.body == "Firing now"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Type badge
            HStack(spacing: 4) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 9))
                Text(isFiring ? "Firing" : "Echo")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.orange)

            // Title
            Text(insight.title.replacingOccurrences(of: "Echo: ", with: ""))
                .font(.caption.weight(.medium))
                .lineLimit(2)

            // Body preview
            Text(insight.body.isEmpty ? " " : insight.body)
                .font(.system(size: 11))
                .foregroundStyle(isFiring ? .orange : .secondary)
                .lineLimit(3)
                .truncationMode(.tail)
        }
        .frame(width: 130, height: 50, alignment: .topLeading)
        .padding(5)
        .background(Color(red: 0.1, green: 0.1, blue: 0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            if isFiring {
                FiringEchoOutline()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onLongPressGesture { onLongPress() }
    }
}

/// Separate view so SwiftUI destroys animation state when removed.
private struct FiringEchoOutline: View {
    @State private var isAnimating = false

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .stroke(Color.orange, lineWidth: 2)
            .opacity(isAnimating ? 1 : 0.2)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isAnimating)
            .onAppear { isAnimating = true }
    }
}

// MARK: - Insight Reference

struct InsightReference: Identifiable {
    var id: String { noteId + (sectionId ?? "") }
    let noteId: String
    let title: String
    let sectionId: String?
}

// MARK: - Insight Detail Sheet

struct InsightDetailSheet: View {
    let insight: Insight
    let onTrack: (() -> Void)?
    let onDismiss: (() -> Void)?
    let onUntrack: (() -> Void)?
    var onDeleteNote: (() -> Void)? = nil
    var onCreateBlock: ((String) -> Void)? = nil
    var references: [InsightReference] = []
    var onNavigate: ((InsightReference) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var showBlockPicker = false
    @State private var showNewBlockDialog = false
    @State private var blockName = ""

    private var isDormantLoop: Bool {
        insight.insightType == .cleanup && insight.sourceSectionId == "dormant_loop"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Type badge
                    HStack(spacing: 6) {
                        Image(systemName: insight.displayIcon)
                            .font(.subheadline)
                        Text(insight.displayLabel)
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(insight.displayTint.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(insight.displayTint.color.opacity(0.15))
                    .clipShape(Capsule())

                    // Title
                    Text(insight.title)
                        .font(.title3.weight(.semibold))

                    // Body
                    if !insight.body.isEmpty {
                        Text(insight.body)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    // Timestamp
                    Text(formattedDate)
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    // References
                    if !references.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("REFERENCED")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            ForEach(references) { ref in
                                Button {
                                    onNavigate?(ref)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "doc.text")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        Text(ref.title)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 12)
                                    .background(Color(UIColor.tertiarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }

                    Divider()

                    // Actions
                    if insight.status == .surfaced {
                        HStack(spacing: 12) {
                            Button {
                                onTrack?()
                                dismiss()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "star")
                                    Text("Track")
                                }
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(insight.displayTint.color)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(insight.displayTint.color.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }

                            Button {
                                onDismiss?()
                                dismiss()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "xmark")
                                    Text("Dismiss")
                                }
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.gray.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    } else if insight.status == .tracked {
                        HStack(spacing: 12) {
                            Button {
                                onUntrack?()
                                dismiss()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "star.slash")
                                    Text("Untrack")
                                }
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.orange)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.orange.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }

                            Button {
                                onDismiss?()
                                dismiss()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "xmark")
                                    Text("Dismiss")
                                }
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.gray.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }

                    // Delete page button for nonsense cleanup insights
                    if insight.insightType == .cleanup && insight.sourceSectionId == "nonsense",
                       let onDeleteNote {
                        Button(role: .destructive) {
                            onDeleteNote()
                            dismiss()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                Text("Delete Page")
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    // Move to Block button for dormant loop insights
                    if isDormantLoop, onCreateBlock != nil {
                        Button {
                            showBlockPicker = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "cube.transparent")
                                Text("Move to Block")
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.blue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Insight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .sheet(isPresented: $showBlockPicker) {
            BlockPickerSheet(
                onSelectBlock: { name in
                    onCreateBlock?(name)
                    dismiss()
                },
                onCreateNew: {
                    showBlockPicker = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        showNewBlockDialog = true
                    }
                }
            )
        }
        .alert("New Block", isPresented: $showNewBlockDialog) {
            TextField("Block name", text: $blockName)
            Button("Create") {
                let name = blockName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                onCreateBlock?(name)
                blockName = ""
                dismiss()
            }
            Button("Cancel", role: .cancel) { blockName = "" }
        } message: {
            Text("Enter a name for the new block")
        }
    }

    private var formattedDate: String {
        let date = Date(timeIntervalSince1970: Double(insight.createdAt) / 1000)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Create Insight Sheet

struct CreateInsightSheet: View {
    let onCreate: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var details = ""

    var body: some View {
        NavigationStack {
            Form {
                SwiftUI.Section("Title") {
                    TextField("What are you tracking?", text: $title)
                }

                SwiftUI.Section("Details") {
                    TextField("Add details...", text: $details, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("New Insight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        onCreate(title, details)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Block Picker Sheet

struct BlockPickerSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("selectedModuleId") private var selectedModuleId: String?
    let onSelectBlock: (String) -> Void
    let onCreateNew: () -> Void

    private var existingBlocks: [String] {
        let moduleNotes = appState.noteRepository.notes.filter { $0.moduleId == selectedModuleId }
        return Array(Set(moduleNotes.compactMap { $0.groupName })).sorted()
    }

    var body: some View {
        NavigationStack {
            List {
                if !existingBlocks.isEmpty {
                    SwiftUI.Section {
                        ForEach(existingBlocks, id: \.self) { blockName in
                            Button {
                                onSelectBlock(blockName)
                                dismiss()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "cube.transparent")
                                        .foregroundStyle(Color.white.opacity(0.85))
                                    Text(blockName)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                            }
                        }
                    }
                }

                SwiftUI.Section {
                    Button {
                        dismiss()
                        onCreateNew()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "plus")
                                .foregroundStyle(.blue)
                            Text("New Block")
                                .foregroundStyle(.blue)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Move to Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
