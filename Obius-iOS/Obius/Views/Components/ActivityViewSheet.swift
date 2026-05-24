import SwiftUI
import LinkPresentation

#if os(iOS)

// MARK: - Activity View Sheet

/// Presents a UIActivityViewController from a transparent host controller.
struct ActivityViewSheet: UIViewControllerRepresentable {
    let items: [Any]
    var activities: [UIActivity]? = nil
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard !context.coordinator.presented else { return }
        context.coordinator.presented = true

        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: activities)
        activityVC.completionWithItemsHandler = { _, _, _, _ in
            dismiss()
        }

        DispatchQueue.main.async {
            uiViewController.present(activityVC, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var presented = false
    }
}

// MARK: - Obius Share Card Renderer

/// Renders full node content as a branded Obius card image for sharing.
enum ObiusCardRenderer {

    /// Renders a branded card showing the full node content.
    /// The card height is dynamic based on how much text there is.
    static func renderNodeCard(content: String, pageTitle: String, shareURL: URL?) -> UIImage {
        let width: CGFloat = 300
        let padding: CGFloat = 16
        let contentWidth = width - padding * 2

        // Measure text height
        let contentFont = UIFont.systemFont(ofSize: 14, weight: .regular)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        let contentAttrs: [NSAttributedString.Key: Any] = [
            .font: contentFont,
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraphStyle
        ]
        let contentBounds = (content as NSString).boundingRect(
            with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: contentAttrs,
            context: nil
        )

        // Header (40) + title (22) + content + footer (28) + padding
        let headerHeight: CGFloat = 40
        let titleHeight: CGFloat = 22
        let footerHeight: CGFloat = 32
        let contentHeight = min(ceil(contentBounds.height) + 8, 600) // Cap at ~600pt
        let totalHeight = headerHeight + titleHeight + contentHeight + footerHeight + padding

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: totalHeight))
        return renderer.image { ctx in
            let rect = CGRect(x: 0, y: 0, width: width, height: totalHeight)

            // Background
            UIColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 16).fill()

            // Blue accent bar at top
            let accentRect = CGRect(x: 0, y: 0, width: width, height: 4)
            let accentPath = UIBezierPath(
                roundedRect: accentRect,
                byRoundingCorners: [.topLeft, .topRight],
                cornerRadii: CGSize(width: 16, height: 16)
            )
            UIColor.systemBlue.setFill()
            accentPath.fill()

            var yOffset: CGFloat = 14

            // Header: "O obius" + "Live" badge
            let logoFont = UIFont.systemFont(ofSize: 16, weight: .bold)
            ("O" as NSString).draw(at: CGPoint(x: padding, y: yOffset), withAttributes: [
                .font: logoFont,
                .foregroundColor: UIColor.white
            ])
            let brandFont = UIFont.systemFont(ofSize: 12, weight: .medium)
            ("obius" as NSString).draw(at: CGPoint(x: padding + 18, y: yOffset + 2), withAttributes: [
                .font: brandFont,
                .foregroundColor: UIColor(white: 0.5, alpha: 1.0)
            ])

            // "Live" badge
            let badgeFont = UIFont.systemFont(ofSize: 10, weight: .semibold)
            let badgeText = "Live"
            let badgeSize = (badgeText as NSString).size(withAttributes: [.font: badgeFont])
            let badgeRect = CGRect(
                x: width - padding - badgeSize.width - 12,
                y: yOffset + 1,
                width: badgeSize.width + 12,
                height: badgeSize.height + 6
            )
            UIColor.systemBlue.withAlphaComponent(0.15).setFill()
            UIBezierPath(roundedRect: badgeRect, cornerRadius: badgeRect.height / 2).fill()
            (badgeText as NSString).draw(
                at: CGPoint(x: badgeRect.minX + 6, y: badgeRect.minY + 3),
                withAttributes: [.font: badgeFont, .foregroundColor: UIColor.systemBlue]
            )

            yOffset += headerHeight

            // Page title (subtle, secondary)
            let titleFont = UIFont.systemFont(ofSize: 11, weight: .medium)
            let titleStr = String(pageTitle.prefix(60))
            (titleStr as NSString).draw(
                at: CGPoint(x: padding, y: yOffset),
                withAttributes: [
                    .font: titleFont,
                    .foregroundColor: UIColor(white: 0.45, alpha: 1.0)
                ]
            )

            yOffset += titleHeight

            // Separator line
            UIColor(white: 0.25, alpha: 1.0).setFill()
            UIRectFill(CGRect(x: padding, y: yOffset - 6, width: contentWidth, height: 0.5))

            // Full node content
            let contentRect = CGRect(x: padding, y: yOffset, width: contentWidth, height: contentHeight)
            (content as NSString).draw(in: contentRect, withAttributes: contentAttrs)

            yOffset += contentHeight + 4

            // Footer: share link
            if let shareURL = shareURL {
                let linkFont = UIFont.systemFont(ofSize: 10, weight: .regular)
                let linkStr = shareURL.absoluteString
                let linkAttrs: [NSAttributedString.Key: Any] = [
                    .font: linkFont,
                    .foregroundColor: UIColor(white: 0.35, alpha: 1.0)
                ]
                (linkStr as NSString).draw(
                    at: CGPoint(x: padding, y: yOffset),
                    withAttributes: linkAttrs
                )
            }
        }
    }
}

// MARK: - Obius Link Share Item

/// Shares an Obius deep link URL with a rich link preview card.
class ObiusShareItem: NSObject, UIActivityItemSource {
    let url: URL
    let title: String
    let preview: String
    private let cardImage: UIImage

    init(url: URL, title: String, preview: String) {
        self.url = url
        self.title = title
        self.preview = preview
        self.cardImage = ObiusCardRenderer.renderNodeCard(content: preview, pageTitle: title, shareURL: url)
        super.init()
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return url
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return url
    }

    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return "\(title) — Obius"
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.originalURL = url
        metadata.url = url
        metadata.title = title
        metadata.iconProvider = NSItemProvider(object: cardImage)
        return metadata
    }
}

// MARK: - Node Share Sheet

/// Custom share sheet that offers iMessage rich card sharing alongside generic sharing.
struct NodeShareSheet: View {
    let url: URL
    let title: String
    let preview: String
    @Environment(\.dismiss) private var dismiss
    @State private var showingActivitySheet = false
    @State private var copied = false

    private var shareableLink: String {
        if let slug = url.pathComponents.last, url.pathComponents.contains("s") {
            return "obius://share/\(slug)"
        }
        return url.absoluteString
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Preview card
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(2)

                    if !preview.isEmpty {
                        Text(preview)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }

                    Text(url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .padding(.top, 8)

                // Share options
                VStack(spacing: 0) {
                    // iMessage option
                    Button {
                        openMessages()
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "message.fill")
                                .font(.title3)
                                .foregroundStyle(.green)
                                .frame(width: 36, height: 36)
                                .background(Color.green.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Send in iMessage")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text("Rich card with comments")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                    }

                    Divider().padding(.leading, 64)

                    // Copy link (same link as iMessage)
                    Button {
                        ClipboardHelper.copy(shareableLink)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            copied = false
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.title3)
                                .foregroundStyle(.blue)
                                .frame(width: 36, height: 36)
                                .background(Color.blue.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(copied ? "Copied!" : "Copy Link")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text("Paste anywhere")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                    }

                    Divider().padding(.leading, 64)

                    // More sharing options
                    Button {
                        showingActivitySheet = true
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.title3)
                                .foregroundStyle(.orange)
                                .frame(width: 36, height: 36)
                                .background(Color.orange.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("More Options")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text("Share link to other apps")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                    }
                }
                .background(Color(UIColor.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .padding(.top, 16)

                Spacer()
            }
            .navigationTitle("Share")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingActivitySheet) {
                let item = ObiusShareItem(url: url, title: title, preview: preview)
                ActivityViewSheet(items: [item])
            }
        }
        .presentationDetents([.medium])
    }

    private func openMessages() {
        let deepLink = shareableLink
        let encoded = deepLink.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? deepLink
        if let messagesURL = URL(string: "sms:&body=\(encoded)") {
            UIApplication.shared.open(messagesURL)
        }
        dismiss()
    }
}

#elseif os(macOS)
import AppKit

// MARK: - macOS Share Sheet

/// macOS sharing using NSSharingServicePicker
struct NodeShareSheet: View {
    let url: URL
    let title: String
    let preview: String
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var shareableLink: String {
        if let slug = url.pathComponents.last, url.pathComponents.contains("s") {
            return "obius://share/\(slug)"
        }
        return url.absoluteString
    }

    var body: some View {
        VStack(spacing: 0) {
            // Preview card
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .lineLimit(2)

                if !preview.isEmpty {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                Text(url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .padding(.top, 8)

            // Share options
            VStack(spacing: 0) {
                // Copy link
                Button {
                    ClipboardHelper.copy(shareableLink)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copied = false
                    }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.title3)
                            .foregroundStyle(.blue)
                            .frame(width: 36, height: 36)
                            .background(Color.blue.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(copied ? "Copied!" : "Copy Link")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                            Text("Paste anywhere")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                Divider().padding(.leading, 64)

                // System share
                Button {
                    shareViaSystemPicker()
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title3)
                            .foregroundStyle(.orange)
                            .frame(width: 36, height: 36)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Share…")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                            Text("Share link via system services")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .padding(.top, 16)

            Spacer()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 400, height: 350)
        .navigationTitle("Share")
    }

    private func shareViaSystemPicker() {
        let items: [Any] = [url]
        let picker = NSSharingServicePicker(items: items)
        if let window = NSApp.keyWindow, let contentView = window.contentView {
            picker.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
        }
    }
}
#endif
