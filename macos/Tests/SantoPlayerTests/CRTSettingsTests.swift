import XCTest
@testable import SantoPlayer

final class CRTSettingsTests: XCTestCase {
    func testEveryPresetRoundTripsThroughMatching() {
        for preset in CRTPreset.allCases {
            XCTAssertEqual(CRTPreset.matching(preset.settings), preset, preset.name)
        }
    }

    func testEditedSettingsAreCustom() {
        var settings = CRTPreset.classic.settings
        settings.glow = 0.99
        XCTAssertNil(CRTPreset.matching(settings))
    }

    func testTubePresetsKeepEffectOn() {
        for preset in [CRTPreset.trinitron, .oldTV] {
            XCTAssertTrue(preset.settings.tube)
            XCTAssertTrue(preset.settings.enabled)
            XCTAssertGreaterThan(preset.settings.curvature, 0)
        }
    }

    func testCodableRoundTrip() throws {
        let original = CRTPreset.oldTV.settings
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(CRTSettings.self, from: data), original)
    }

    func testUniformsFitVideoInsideViewport() {
        let rect = CRTUniforms.videoRect(video: CGSize(width: 1920, height: 1080),
                                         viewport: CGSize(width: 1000, height: 1000), fill: false)
        XCTAssertEqual(rect.width, 1000, accuracy: 0.01)
        XCTAssertEqual(rect.height, 562.5, accuracy: 0.01)
        XCTAssertEqual(rect.minY, 218.75, accuracy: 0.01)
    }

    func testUniformsFillCoversViewport() {
        let rect = CRTUniforms.videoRect(video: CGSize(width: 1920, height: 1080),
                                         viewport: CGSize(width: 1000, height: 1000), fill: true)
        XCTAssertEqual(rect.height, 1000, accuracy: 0.01)
        XCTAssertLessThan(rect.minX, 0)
    }
}

final class ScanlineDensityTests: XCTestCase {
    func testNeverFewerThanThreePixelsPerLine() {
        for (height, scale) in [(660.0, 1.0), (1440.0, 1.0), (1320.0, 2.0), (2160.0, 2.0), (400.0, 1.0)] {
            let lines = CRTUniforms.scanlineCount(rectHeightPixels: height, pixelScale: scale)
            XCTAssertGreaterThanOrEqual(height / Double(lines), min(3, height / 120) - 0.001, "\(height)@\(scale)x")
        }
    }

    func testRetinaKeepsTwoPointsPerLine() {
        XCTAssertEqual(CRTUniforms.scanlineCount(rectHeightPixels: 1600, pixelScale: 2), 400)
    }
}

final class PresetOrderTests: XCTestCase {
    /// The TVs come right after "Sem efeito", then the flat effects.
    func testTVsComeFirst() {
        XCTAssertEqual(Array(CRTPreset.allCases.prefix(4)), [.off, .cabinet, .trinitron, .oldTV])
        XCTAssertEqual(CRTPreset.allCases.count, 8)
    }

    func testEveryMaskTypeIsExplained() {
        for type in CRTMaskType.allCases { XCTAssertFalse(type.detail.isEmpty, type.label) }
    }
}
