import SwiftUI

/// SwiftUI card view for rendering iMessage share preview images.
/// Replicates the visual design of MessageCardRenderer using SwiftUI for consistency
/// with the main app's styling. Rendered to a UIImage via ImageRenderer.
struct NodeCardView: View {
    let payload: MessageSharePayload

    // MARK: - Intent Colors (dark-mode values from IntentType.backgroundTint)

    private static func intentBackground(_ intent: String?) -> Color {
        switch intent {
        case "idea":     return Color(red: 0.10, green: 0.15, blue: 0.25)
        case "question": return Color(red: 0.20, green: 0.18, blue: 0.10)
        case "task":     return Color(red: 0.10, green: 0.20, blue: 0.15)
        case "evidence": return Color(red: 0.18, green: 0.12, blue: 0.22)
        default:         return Color(red: 0.10, green: 0.15, blue: 0.25)
        }
    }

    private static func intentAccent(_ intent: String?) -> Color {
        switch intent {
        case "question": return .yellow
        case "task":     return .green
        case "evidence": return .purple
        default:         return .blue // "idea" or nil
        }
    }

    private var accentColor: Color {
        payload.shareType == "commit" ? .purple : .blue
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            // Background
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.12))

            VStack(alignment: .leading, spacing: 0) {
                // Top accent bar
                accentColor
                    .frame(height: 3)
                    .clipShape(UnevenRoundedRectangle(
                        topLeadingRadius: 12,
                        topTrailingRadius: 12
                    ))

                VStack(alignment: .leading, spacing: 8) {
                    // Header: logo + brand + badge
                    headerRow

                    // Section previews (up to 2)
                    ForEach(Array(payload.sectionPreviews.prefix(2).enumerated()), id: \.offset) { _, preview in
                        sectionPreviewRow(preview)
                    }

                    // Handle badges
                    if !payload.handleNames.isEmpty {
                        handleBadges
                    }

                    Spacer(minLength: 0)

                    // Bottom row: commit ID + creator
                    bottomRow
                }
                .padding(.horizontal, 14)
                .padding(.top, 9)
                .padding(.bottom, 10)
            }
        }
        .frame(width: 300, height: 200)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .center) {
            // "O" logo
            Text("O")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .kerning(-0.5)

            // "obius" brand
            Text("obius")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(white: 0.50))
                .kerning(1.5)

            Spacer()

            // Share type badge
            Text(payload.shareType == "commit" ? "SNAPSHOT" : "LIVE")
                .font(.system(size: 10, weight: .bold))
                .kerning(0.5)
                .foregroundStyle(accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(accentColor.opacity(0.15))
                )
        }
    }

    // MARK: - Section Preview

    private func sectionPreviewRow(_ preview: MessageSharePayload.SectionPreview) -> some View {
        let intentBg = Self.intentBackground(preview.intent)
        let intentColor = Self.intentAccent(preview.intent)

        return HStack(spacing: 0) {
            // Left accent rail
            intentColor.opacity(0.6)
                .frame(width: 3)
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: 6,
                    bottomLeadingRadius: 6
                ))

            VStack(alignment: .leading, spacing: 2) {
                // Intent label
                Text((preview.intent ?? "idea").uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .kerning(0.8)
                    .foregroundStyle(intentColor.opacity(0.7))

                // Content preview
                Text(displayContent(for: preview))
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.82))
                    .lineLimit(1)
            }
            .padding(.leading, 7)
            .padding(.trailing, 8)
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(intentBg.opacity(0.8))
        )
    }

    private func displayContent(for preview: MessageSharePayload.SectionPreview) -> String {
        switch preview.contentType {
        case "image": return "Image"
        case "audio": return "Audio"
        default:      return String(preview.content.prefix(60))
        }
    }

    // MARK: - Handle Badges

    private var handleBadges: some View {
        HStack(spacing: 6) {
            ForEach(Array(payload.handleNames.prefix(3).enumerated()), id: \.offset) { _, name in
                Text("@\(name)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(Color.purple.opacity(0.15))
                    )
            }
        }
    }

    // MARK: - Bottom Row

    private var bottomRow: some View {
        HStack {
            if let commitId = payload.commitShortId {
                Text("#\(commitId)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(white: 0.45))
            }

            Spacer()

            if let creator = payload.creatorName {
                Text("by \(creator)")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(white: 0.45))
            }
        }
    }
}
