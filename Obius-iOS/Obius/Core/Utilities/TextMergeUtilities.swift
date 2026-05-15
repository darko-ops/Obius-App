import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Pure text-merge helpers used when collapsing two interstitial slots into
/// one during a section delete. Kept free of GRDB / view-model state so the
/// merge can run inside a `database.write { ... }` block.
enum TextMergeUtilities {
    static func mergePlain(base: String, appended: String) -> String {
        if base.isEmpty { return appended }
        if appended.isEmpty { return base }
        return base + "\n" + appended
    }

    /// Merge two rich-text payloads (base64 RTF) with a newline separator.
    /// Returns nil when neither side carries rich formatting — callers should
    /// fall back to dropping the rich slot and writing only the plain merge.
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
