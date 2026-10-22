import XCTest
@testable import SantoPlayer

@MainActor
final class AppSettingsTests: XCTestCase {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "AppSettingsTests-\(UUID().uuidString)")! }

    func testDefaults() {
        let settings = AppSettings(defaults: defaults())
        XCTAssertEqual(settings.layout, .modern)
        XCTAssertTrue(settings.resumePlayback)
        XCTAssertTrue(settings.hardwareDecoding)
        XCTAssertEqual(settings.skipInterval, 10)
        XCTAssertEqual(settings.language, .system)
    }

    /// Regression: switching layout back and forth must stick (the old
    /// per-scene @AppStorage copies went out of sync).
    func testLayoutRoundTripsAndPersists() {
        let store = defaults()
        let settings = AppSettings(defaults: store)
        for layout in [PlayerLayout.classic, .modern, .classic, .modern] {
            settings.layout = layout
            XCTAssertEqual(settings.layout, layout)
            XCTAssertEqual(AppSettings(defaults: store).layout, layout)
        }
    }

    func testInvalidSkipIntervalFallsBack() {
        let store = defaults()
        store.set(7.0, forKey: "skipInterval")
        XCTAssertEqual(AppSettings(defaults: store).skipInterval, 10)
    }

    func testLanguageWritesAppleLanguagesAndNeedsRelaunch() {
        let store = defaults()
        let settings = AppSettings(defaults: store)
        settings.language = .english
        XCTAssertEqual(store.stringArray(forKey: "AppleLanguages"), ["en"])
        XCTAssertTrue(settings.needsRelaunchForLanguage)
        settings.language = .system
        // Removed from the app domain; reads now fall through to the system's list.
        XCTAssertNotEqual(store.stringArray(forKey: "AppleLanguages"), ["en"])
        XCTAssertFalse(settings.needsRelaunchForLanguage)
    }

    func testTrackLanguageListsForMPV() {
        XCTAssertEqual(AppSettings.TrackLanguage.portuguese.mpvList, "pt,por,pob")
        XCTAssertEqual(AppSettings.TrackLanguage.english.mpvList, "en,eng")
        XCTAssertFalse(AppSettings.TrackLanguage.system.mpvList.isEmpty)
    }
}
