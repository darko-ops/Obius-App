import UIKit

/// Renders a branded card image for iMessage share previews.
/// Uses SF Pro weight/tracking combinations for Obius brand consistency.
enum MessageCardRenderer {

    // MARK: - Brand Typography

    /// Bold rounded logo "O"
    private static var logoFont: UIFont {
        UIFont.systemFont(ofSize: 20, weight: .heavy, width: .expanded)
    }

    /// "obius" brand wordmark — medium weight with wider tracking
    private static var brandFont: UIFont {
        let descriptor = UIFont.systemFont(ofSize: 13, weight: .medium)
            .fontDescriptor
            .addingAttributes([
                .init(rawValue: "NSCTFontUIUsageAttribute"): "UICTFontTextStyleBody"
            ])
        return UIFont(descriptor: descriptor, size: 13)
    }

    /// Badge labels (Live, Snapshot)
    private static var badgeFont: UIFont {
        UIFont.systemFont(ofSize: 10, weight: .bold)
    }

    /// Intent labels on section preview rows
    private static var intentLabelFont: UIFont {
        UIFont.systemFont(ofSize: 9, weight: .bold)
    }

    /// Content preview text
    private static var contentFont: UIFont {
        UIFont.systemFont(ofSize: 11, weight: .regular)
    }

    /// Handle badge text
    private static var handleFont: UIFont {
        UIFont.systemFont(ofSize: 10, weight: .semibold)
    }

    /// Commit ID (monospaced)
    private static var commitIdFont: UIFont {
        UIFont.monospacedSystemFont(ofSize: 10, weight: .medium)
    }

    /// Creator name
    private static var creatorFont: UIFont {
        UIFont.systemFont(ofSize: 10, weight: .regular)
    }

    // MARK: - Render

    /// Renders a 300x200pt @2x card image from a MessageSharePayload.
    static func renderCard(from payload: MessageSharePayload) -> UIImage {
        let width: CGFloat = 300
        let height: CGFloat = 200
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))

        return renderer.image { ctx in
            let rect = CGRect(x: 0, y: 0, width: width, height: height)

            // Background
            UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 12).fill()

            // Accent bar — intent-colored for personality
            let accentColor: UIColor = payload.shareType == "commit" ? .systemPurple : .systemBlue
            let accentRect = CGRect(x: 0, y: 0, width: width, height: 3)
            let accentPath = UIBezierPath(
                roundedRect: accentRect,
                byRoundingCorners: [.topLeft, .topRight],
                cornerRadii: CGSize(width: 12, height: 12)
            )
            accentColor.setFill()
            accentPath.fill()

            // Header row: "O obius" on left, badge on right
            var yOffset: CGFloat = 12

            // "O" logo — bold white
            let logoAttrs: [NSAttributedString.Key: Any] = [
                .font: logoFont,
                .foregroundColor: UIColor.white,
                .kern: -0.5
            ]
            ("O" as NSString).draw(at: CGPoint(x: 14, y: yOffset - 1), withAttributes: logoAttrs)

            // "obius" brand — tracked out, subtle gray
            let brandAttrs: [NSAttributedString.Key: Any] = [
                .font: brandFont,
                .foregroundColor: UIColor(white: 0.50, alpha: 1.0),
                .kern: 1.5
            ]
            ("obius" as NSString).draw(at: CGPoint(x: 38, y: yOffset + 3), withAttributes: brandAttrs)

            // Share type badge on right
            let badgeText = payload.shareType == "commit" ? "SNAPSHOT" : "LIVE"
            let badgeColor = payload.shareType == "commit" ? UIColor.systemPurple : UIColor.systemBlue
            drawBadge(badgeText, color: badgeColor, at: CGPoint(x: width - 14, y: yOffset + 2), alignRight: true)

            yOffset += 32

            // Section previews (up to 2)
            let maxPreviews = min(payload.sectionPreviews.count, 2)
            for i in 0..<maxPreviews {
                let preview = payload.sectionPreviews[i]
                let previewHeight: CGFloat = 34
                let previewRect = CGRect(x: 14, y: yOffset, width: width - 28, height: previewHeight)

                // Intent-colored background
                let intentColor = colorForIntent(preview.intent)
                intentColor.withAlphaComponent(0.12).setFill()
                UIBezierPath(roundedRect: previewRect, cornerRadius: 6).fill()

                // Left accent bar on each preview
                let accentBar = CGRect(x: 14, y: yOffset, width: 3, height: previewHeight)
                intentColor.withAlphaComponent(0.6).setFill()
                UIBezierPath(roundedRect: accentBar, byRoundingCorners: [.topLeft, .bottomLeft], cornerRadii: CGSize(width: 6, height: 6)).fill()

                // Intent label — uppercase bold
                let intentAttrs: [NSAttributedString.Key: Any] = [
                    .font: intentLabelFont,
                    .foregroundColor: intentColor.withAlphaComponent(0.7),
                    .kern: 0.8
                ]
                let intentLabel = (preview.intent ?? "idea").uppercased()
                (intentLabel as NSString).draw(
                    at: CGPoint(x: 24, y: yOffset + 3),
                    withAttributes: intentAttrs
                )

                // Content preview
                let contentAttrs: [NSAttributedString.Key: Any] = [
                    .font: contentFont,
                    .foregroundColor: UIColor(white: 0.82, alpha: 1.0)
                ]
                let displayContent: String
                if preview.contentType == "image" {
                    displayContent = "Image"
                } else if preview.contentType == "audio" {
                    displayContent = "Audio"
                } else {
                    displayContent = String(preview.content.prefix(60))
                }

                let contentRect = CGRect(x: 24, y: yOffset + 16, width: width - 48, height: 14)
                (displayContent as NSString).draw(
                    in: contentRect,
                    withAttributes: contentAttrs
                )

                yOffset += previewHeight + 6
            }

            // Handle badges (purple capsules)
            if !payload.handleNames.isEmpty {
                yOffset += 4
                var xOffset: CGFloat = 14
                for name in payload.handleNames.prefix(3) {
                    let badgeWidth = drawHandleBadge("@\(name)", at: CGPoint(x: xOffset, y: yOffset))
                    xOffset += badgeWidth + 6
                    if xOffset > width - 30 { break }
                }
                yOffset += 22
            }

            // Bottom row: commit ID on left, creator on right
            let bottomY = height - 24

            if let commitId = payload.commitShortId {
                let commitAttrs: [NSAttributedString.Key: Any] = [
                    .font: commitIdFont,
                    .foregroundColor: UIColor(white: 0.45, alpha: 1.0)
                ]
                ("#\(commitId)" as NSString).draw(
                    at: CGPoint(x: 14, y: bottomY),
                    withAttributes: commitAttrs
                )
            }

            if let creator = payload.creatorName {
                let creatorAttrs: [NSAttributedString.Key: Any] = [
                    .font: creatorFont,
                    .foregroundColor: UIColor(white: 0.45, alpha: 1.0)
                ]
                let creatorText = "by \(creator)"
                let creatorSize = (creatorText as NSString).size(withAttributes: creatorAttrs)
                (creatorText as NSString).draw(
                    at: CGPoint(x: width - 14 - creatorSize.width, y: bottomY),
                    withAttributes: creatorAttrs
                )
            }
        }
    }

    // MARK: - Drawing Helpers

    private static func colorForIntent(_ intent: String?) -> UIColor {
        switch intent {
        case "question": return .systemYellow
        case "task": return .systemGreen
        case "evidence": return .systemPurple
        default: return .systemBlue   // "idea" or nil
        }
    }

    @discardableResult
    private static func drawBadge(_ text: String, color: UIColor, at point: CGPoint, alignRight: Bool) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: badgeFont,
            .foregroundColor: color,
            .kern: 0.5
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let badgePadH: CGFloat = 8
        let badgePadV: CGFloat = 3
        let badgeWidth = size.width + badgePadH * 2
        let badgeHeight = size.height + badgePadV * 2

        let x = alignRight ? point.x - badgeWidth : point.x
        let badgeRect = CGRect(x: x, y: point.y, width: badgeWidth, height: badgeHeight)

        color.withAlphaComponent(0.15).setFill()
        UIBezierPath(roundedRect: badgeRect, cornerRadius: badgeHeight / 2).fill()

        (text as NSString).draw(
            at: CGPoint(x: x + badgePadH, y: point.y + badgePadV),
            withAttributes: attrs
        )

        return badgeWidth
    }

    @discardableResult
    private static func drawHandleBadge(_ text: String, at point: CGPoint) -> CGFloat {
        return drawBadge(text, color: .systemPurple, at: point, alignRight: false)
    }
}
