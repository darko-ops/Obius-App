import Foundation

/// Utility for generating fractional index strings for ordering.
/// Allows inserting items between any two existing items without renumbering.
enum FractionalIndex {
    private static let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    private static let midChar: Character = "N"

    /// Generate an order key between two existing keys.
    /// - Parameters:
    ///   - before: The key before the insertion point (nil for beginning)
    ///   - after: The key after the insertion point (nil for end)
    /// - Returns: A string key that sorts between `before` and `after`
    static func between(_ before: String?, _ after: String?) -> String {
        let a = before ?? ""
        let b = after ?? String(repeating: "z", count: (a.count > 0 ? a.count : 1) + 1)

        var result = ""
        var i = 0

        while true {
            let aChar = i < a.count ? a[a.index(a.startIndex, offsetBy: i)] : Character("A")
            let bChar = i < b.count ? b[b.index(b.startIndex, offsetBy: i)] : Character("z")

            if aChar == bChar {
                result.append(aChar)
                i += 1
                continue
            }

            // Find midpoint between aChar and bChar
            guard let aVal = aChar.asciiValue, let bVal = bChar.asciiValue else {
                result.append(midChar)
                return result
            }

            let mid = (Int(aVal) + Int(bVal)) / 2
            if mid > Int(aVal) && mid < Int(bVal) {
                result.append(Character(UnicodeScalar(UInt8(mid))))
                return result
            }

            // Can't find midpoint, append aChar and continue
            result.append(aChar)
            i += 1

            // Safety: prevent infinite loop
            if i > 100 {
                result.append(midChar)
                return result
            }
        }
    }

    /// Generate initial order keys for a list of items.
    /// - Parameter count: Number of items
    /// - Returns: Array of evenly spaced order keys
    static func generateInitialKeys(count: Int) -> [String] {
        guard count > 0 else { return [] }

        if count <= 26 {
            // Use single uppercase letters
            return (0..<count).map { String(alphabet[alphabet.index(alphabet.startIndex, offsetBy: $0)]) }
        }

        // Generate evenly spaced keys
        var keys: [String] = []
        for i in 0..<count {
            var key = ""
            var remaining = i
            repeat {
                let charIndex = remaining % alphabet.count
                key = String(alphabet[alphabet.index(alphabet.startIndex, offsetBy: charIndex)]) + key
                remaining = remaining / alphabet.count - 1
            } while remaining >= 0
            keys.append(key)
        }
        return keys
    }

    /// Generate a key for appending to the end of a list.
    /// - Parameter lastKey: The current last key in the list (nil if empty)
    /// - Returns: A key that sorts after `lastKey`
    static func after(_ lastKey: String?) -> String {
        between(lastKey, nil)
    }

    /// Generate a key for prepending to the beginning of a list.
    /// - Parameter firstKey: The current first key in the list (nil if empty)
    /// - Returns: A key that sorts before `firstKey`
    static func before(_ firstKey: String?) -> String {
        between(nil, firstKey)
    }
}
