import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Extracts hashtags from text and applies yellow highlighting to text views.
enum HashtagHelper {

    /// Regex matching `#word` — must not be preceded by a word character (used for highlighting).
    private static let pattern = try! NSRegularExpression(pattern: "(?<!\\w)#(\\w+)", options: [])

    /// Regex matching `#word` only when followed by whitespace (completed hashtag).
    private static let completedPattern = try! NSRegularExpression(pattern: "(?<!\\w)#(\\w+)(?=\\s)", options: [])

    /// Return all completed hashtag words (followed by a space) without the `#`.
    static func extractTags(from text: String) -> [String] {
        let nsText = text as NSString
        let matches = completedPattern.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        return matches.compactMap { match -> String? in
            guard match.numberOfRanges >= 2 else { return nil }
            return nsText.substring(with: match.range(at: 1))
        }
    }

    #if os(iOS)
    /// Walk the text view's attributed text, reset foreground color to `.label`,
    /// then apply `.systemYellow` to every hashtag match.  Saves / restores
    /// `selectedRange` so the cursor does not jump.
    static func applyHighlighting(to textView: UITextView) {
        guard let attributed = textView.attributedText, attributed.length > 0 else { return }

        let fullRange = NSRange(location: 0, length: attributed.length)
        let mutable = NSMutableAttributedString(attributedString: attributed)

        // Reset any previous hashtag coloring back to label
        mutable.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { value, range, _ in
            if let color = value as? UIColor, color == .systemYellow {
                mutable.addAttribute(.foregroundColor, value: UIColor.label, range: range)
            }
        }

        // Apply yellow to each hashtag match (including the `#`)
        let text = mutable.string
        let matches = pattern.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))

        for match in matches {
            mutable.addAttribute(.foregroundColor, value: UIColor.systemYellow, range: match.range)
        }

        // Only apply if something actually changed
        if mutable.isEqual(to: attributed) { return }

        let savedRange = textView.selectedRange
        textView.attributedText = mutable
        textView.selectedRange = savedRange
    }
    #elseif os(macOS)
    /// Walk the text view's attributed text, reset foreground color to `.labelColor`,
    /// then apply `.systemYellow` to every hashtag match.
    static func applyHighlighting(to textView: NSTextView) {
        guard let textStorage = textView.textStorage, textStorage.length > 0 else { return }

        let fullRange = NSRange(location: 0, length: textStorage.length)

        textStorage.beginEditing()

        // Reset any previous hashtag coloring back to label
        textStorage.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { value, range, _ in
            if let color = value as? NSColor, color == .systemYellow {
                textStorage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
            }
        }

        // Apply yellow to each hashtag match (including the `#`)
        let text = textStorage.string
        let matches = pattern.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))

        for match in matches {
            textStorage.addAttribute(.foregroundColor, value: NSColor.systemYellow, range: match.range)
        }

        textStorage.endEditing()
    }
    #endif
}
