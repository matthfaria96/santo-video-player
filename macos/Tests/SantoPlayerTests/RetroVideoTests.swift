import XCTest
@testable import SantoPlayer

final class RetroVideoTests: XCTestCase {
    // MARK: Native scanlines

    func testDVDOnABigScreenGetsOneLinePerVideoLine() {
        // 480 lines drawn 1440 px tall: 3 px each.
        XCTAssertEqual(CRTUniforms.nativeScanlineCount(sourceHeight: 480, contentHeightPixels: 1440,
                                                       glassHeightPixels: 1440), 480)
    }

    func testSmallWindowFallsBackToOneLinePerField() {
        // 480 lines in 900 px would be under 3 px apart: draw the 240 field lines.
        XCTAssertEqual(CRTUniforms.nativeScanlineCount(sourceHeight: 480, contentHeightPixels: 900,
                                                       glassHeightPixels: 900), 240)
    }

    func testHDSourcesKeepWindowDensity() {
        XCTAssertNil(CRTUniforms.nativeScanlineCount(sourceHeight: 1080, contentHeightPixels: 1440,
                                                     glassHeightPixels: 1440))
        XCTAssertNil(CRTUniforms.nativeScanlineCount(sourceHeight: 720, contentHeightPixels: 1440,
                                                     glassHeightPixels: 1440))
    }

    func testTinyPreviewsKeepWindowDensity() {
        XCTAssertNil(CRTUniforms.nativeScanlineCount(sourceHeight: 480, contentHeightPixels: 300,
                                                     glassHeightPixels: 300))
    }

    func testLetterboxedPictureCountsLinesOverTheTallerGlass() {
        // Picture 1000 px inside a 1200 px glass: the beam keeps the picture's pitch.
        let lines = CRTUniforms.nativeScanlineCount(sourceHeight: 240, contentHeightPixels: 1000,
                                                    glassHeightPixels: 1200)
        XCTAssertEqual(lines!, 288, accuracy: 0.01)
    }

    func testUniformsUseNativeCountForSD() {
        let rect = CGRect(x: 0, y: 0, width: 1920, height: 1440)
        let u = CRTUniforms(settings: CRTSettings(), viewport: rect.size, videoRect: rect,
                            sourceHeight: 480, time: 0, pixelScale: 1)
        XCTAssertEqual(u.lines, 480)
        let hd = CRTUniforms(settings: CRTSettings(), viewport: rect.size, videoRect: rect,
                             sourceHeight: 1080, time: 0, pixelScale: 1)
        XCTAssertEqual(hd.lines, CRTUniforms.scanlineCount(rectHeightPixels: 1440, pixelScale: 1))
    }

    // MARK: Automatic cabinet

    func testAutoCabinetDressesFourByThree() {
        let s = CRTPreset.classic.settings.adapted(toVideo: CGSize(width: 640, height: 480), autoCabinet: true)
        XCTAssertTrue(s.frame)
        XCTAssertTrue(s.tube)
        XCTAssertGreaterThanOrEqual(s.curvature, 0.35)
    }

    func testAutoCabinetLeavesWidescreenAndOffAlone() {
        let classic = CRTPreset.classic.settings
        XCTAssertEqual(classic.adapted(toVideo: CGSize(width: 1920, height: 1080), autoCabinet: true), classic)
        XCTAssertEqual(classic.adapted(toVideo: CGSize(width: 640, height: 480), autoCabinet: false), classic)
        XCTAssertEqual(CRTSettings.off.adapted(toVideo: CGSize(width: 640, height: 480), autoCabinet: true), .off)
    }

    @MainActor
    func testRetroSettingsDefaults() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "RetroVideoTests-\(UUID().uuidString)")!)
        XCTAssertTrue(settings.deinterlace)
        XCTAssertTrue(settings.nativeScanlines)
        XCTAssertFalse(settings.autoCabinet)
    }
}
