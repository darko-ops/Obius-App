import XCTest
@testable import Obius

final class FractionalIndexTests: XCTestCase {

    // MARK: - Between Tests

    func testBetween_nilAndNil() {
        let key = FractionalIndex.between(nil, nil)
        XCTAssertFalse(key.isEmpty)
    }

    func testBetween_nilAndValue() {
        let key = FractionalIndex.between(nil, "M")
        XCTAssertTrue(key < "M")
    }

    func testBetween_valueAndNil() {
        let key = FractionalIndex.between("M", nil)
        XCTAssertTrue(key > "M")
    }

    func testBetween_twoValues() {
        let key = FractionalIndex.between("A", "C")
        XCTAssertTrue(key > "A")
        XCTAssertTrue(key < "C")
    }

    func testBetween_adjacentValues() {
        let key = FractionalIndex.between("A", "B")
        XCTAssertTrue(key > "A")
        XCTAssertTrue(key < "B")
    }

    func testBetween_sameValue() {
        let key = FractionalIndex.between("M", "M")
        // When same, should append to create unique key
        XCTAssertTrue(key.hasPrefix("M"))
    }

    func testBetween_maintainsOrder() {
        // Generate many keys between A and Z
        var keys: [String] = ["A"]

        for _ in 0..<20 {
            let newKey = FractionalIndex.between(keys.last, "Z")
            XCTAssertTrue(newKey > keys.last!)
            XCTAssertTrue(newKey < "Z")
            keys.append(newKey)
        }

        // Verify all keys are in order
        let sorted = keys.sorted()
        XCTAssertEqual(keys, sorted)
    }

    func testBetween_insertion() {
        // Simulate inserting between existing items
        let first = "B"
        let third = "D"

        let second = FractionalIndex.between(first, third)

        XCTAssertTrue(second > first)
        XCTAssertTrue(second < third)
    }

    // MARK: - Generate Initial Keys Tests

    func testGenerateInitialKeys_empty() {
        let keys = FractionalIndex.generateInitialKeys(count: 0)
        XCTAssertTrue(keys.isEmpty)
    }

    func testGenerateInitialKeys_single() {
        let keys = FractionalIndex.generateInitialKeys(count: 1)
        XCTAssertEqual(keys.count, 1)
    }

    func testGenerateInitialKeys_multiple() {
        let keys = FractionalIndex.generateInitialKeys(count: 5)

        XCTAssertEqual(keys.count, 5)

        // Verify keys are in order
        let sorted = keys.sorted()
        XCTAssertEqual(keys, sorted)
    }

    func testGenerateInitialKeys_manyItems() {
        let keys = FractionalIndex.generateInitialKeys(count: 100)

        XCTAssertEqual(keys.count, 100)

        // Verify all unique
        let uniqueKeys = Set(keys)
        XCTAssertEqual(uniqueKeys.count, keys.count)

        // Verify in order
        let sorted = keys.sorted()
        XCTAssertEqual(keys, sorted)
    }

    // MARK: - After/Before Tests

    func testAfter_nil() {
        let key = FractionalIndex.after(nil)
        XCTAssertFalse(key.isEmpty)
    }

    func testAfter_existingKey() {
        let key = FractionalIndex.after("M")
        XCTAssertTrue(key > "M")
    }

    func testBefore_nil() {
        let key = FractionalIndex.before(nil)
        XCTAssertFalse(key.isEmpty)
    }

    func testBefore_existingKey() {
        let key = FractionalIndex.before("M")
        XCTAssertTrue(key < "M")
    }

    // MARK: - Edge Cases

    func testBetween_veryCloseValues() {
        // Test when values are very close together
        var key = "A"
        for _ in 0..<50 {
            let newKey = FractionalIndex.between(key, key + "Z")
            XCTAssertTrue(newKey > key)
            key = newKey
        }
    }

    func testBetween_longKeys() {
        let longKey = String(repeating: "M", count: 50)
        let key = FractionalIndex.between(longKey, nil)
        XCTAssertTrue(key > longKey)
    }
}
