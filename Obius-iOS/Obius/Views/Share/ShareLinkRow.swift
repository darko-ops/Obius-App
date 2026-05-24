import SwiftUI

struct ShareLinkRow: View {
    let shareLink: ShareLink
    let onDeactivate: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Type icon
            Image(systemName: shareLink.shareType == .live
                  ? "antenna.radiowaves.left.and.right"
                  : "doc.zipper")
                .foregroundStyle(shareLink.shareType == .live ? .blue : .purple)
                .frame(width: 24)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(shareLink.shareType == .live ? "Live Link" : "Version Link")
                    .font(.subheadline.weight(.medium))

                if let name = shareLink.commitName {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(shareLink.slug)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // View count
            if shareLink.viewCount > 0 {
                Label("\(shareLink.viewCount)", systemImage: "eye")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Actions
            Menu {
                if let url = URL(string: shareLink.url) {
                    SwiftUI.ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }

                Button {
                    ClipboardHelper.copy(shareLink.deepLink)
                } label: {
                    Label("Copy Link", systemImage: "doc.on.doc")
                }

                Divider()

                Button(role: .destructive) {
                    onDeactivate()
                } label: {
                    Label("Deactivate", systemImage: "xmark.circle")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
