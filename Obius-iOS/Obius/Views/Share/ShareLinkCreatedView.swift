import SwiftUI

struct ShareLinkCreatedView: View {
    @Environment(\.dismiss) private var dismiss

    let shareLink: ShareLink

    @State private var copied = false

    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding(.horizontal)
            .padding(.top, 16)

            Spacer()

            // Icon
            Image(systemName: shareLink.shareType == .live
                  ? "antenna.radiowaves.left.and.right"
                  : "doc.zipper")
                .font(.system(size: 48))
                .foregroundStyle(shareLink.shareType == .live ? .blue : .purple)

            // Title
            Text(shareLink.shareType == .live ? "Live Link Created" : "Version Link Created")
                .font(.title2.weight(.semibold))

            // URL display
            VStack(spacing: 12) {
                Text(shareLink.url)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    .lineLimit(1)

                HStack(spacing: 16) {
                    // Copy button
                    Button {
                        ClipboardHelper.copy(shareLink.url)
                        withAnimation { copied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { copied = false }
                        }
                    } label: {
                        Label(copied ? "Copied!" : "Copy Link",
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)

                    // System share
                    if let url = URL(string: shareLink.url) {
                        SwiftUI.ShareLink(item: url) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(.horizontal, 24)

            // Explainer
            Text(shareLink.shareType == .live
                 ? "Anyone with this link can view your note. Changes you make will appear in real-time."
                 : "This is a permanent snapshot. The content will never change, even if you edit the original.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
        }
        .presentationDetents([.medium])
    }
}
