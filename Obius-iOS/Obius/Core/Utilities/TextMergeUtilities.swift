import Foundation

enum TextMergeUtilities {
    /// Concatenate an orphaned interstitial onto a base rich-text run without
    /// losing the base's existing per-character formatting. Used during section
    /// deletion to merge the deleted section's interstitial into the previous
    /// interstitial (or the note body).
    ///
    /// Returns nil when the base has no rich text AND the appended chunk has no
    /// rich text — callers interpret nil as "no rich text; store plain text only".
    static func appendPlainToRichText(
        base: String?,
        basePlain: String,
        appendedPlain: String,
        appendedRich: String?
    ) -> String? {
        if base == nil && appendedRich == nil { return nil }

        let bodyAttrs = RichTextHelper.bodyAttributes()
        let result = NSMutableAttributedString()
        if let base = base, let baseAttr = RichTextHelper.deserialize(base) {
            result.append(baseAttr)
        } else if !basePlain.isEmpty {
            result.append(NSAttributedString(string: basePlain, attributes: bodyAttrs))
        }
        // Inherit the trailing run's attributes for the separator and any plain
        // appended text; otherwise RTF round-trip renders them in a default
        // serif font at the wrong size and in black.
        let trailingAttrs: [NSAttributedString.Key: Any] = result.length > 0
            ? result.attributes(at: result.length - 1, effectiveRange: nil)
            : bodyAttrs
        if result.length > 0 {
            result.append(NSAttributedString(string: "\n", attributes: trailingAttrs))
        }
        if let appendedRich = appendedRich,
           let appendedAttr = RichTextHelper.deserialize(appendedRich) {
            result.append(appendedAttr)
        } else {
            result.append(NSAttributedString(string: appendedPlain, attributes: trailingAttrs))
        }
        return RichTextHelper.serialize(result)
    }
}
