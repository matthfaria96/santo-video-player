import XCTest

/// Every English string must keep the placeholders of its Portuguese key,
/// or String(format:) would read the wrong arguments at runtime.
final class LocalizationTests: XCTestCase {
    private var english: [String: String] {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Support/Localizations/en.lproj/Localizable.strings")
        return NSDictionary(contentsOf: file) as? [String: String] ?? [:]
    }

    private func placeholders(_ text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: "%(lld|@|%)")
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .map { (text as NSString).substring(with: $0.range) }
    }

    func testEnglishFileLoads() {
        XCTAssertGreaterThan(english.count, 100)
    }

    func testPlaceholdersMatch() {
        for (key, value) in english {
            XCTAssertEqual(placeholders(key), placeholders(value), "\(key) → \(value)")
        }
    }

    func testNoEmptyTranslations() {
        for (key, value) in english { XCTAssertFalse(value.isEmpty, key) }
    }
}
