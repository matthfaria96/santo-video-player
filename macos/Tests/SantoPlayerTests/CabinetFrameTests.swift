import XCTest
@testable import SantoPlayer

final class CabinetFrameTests: XCTestCase {
    private let window = CGSize(width: 1600, height: 900)

    func testFourByThreeLeavesWideSidePanels() {
        let layout = CRTUniforms.framedLayout(video: CGSize(width: 640, height: 480), viewport: window)
        XCTAssertEqual(layout.glass, layout.content)                        // the glass is the picture
        XCTAssertEqual(layout.glass.width / layout.glass.height, 4.0 / 3.0, accuracy: 0.001)
        XCTAssertGreaterThan(layout.glass.minX, window.width * 0.07)        // room for grille and knobs
        XCTAssertEqual(layout.glass.midX, window.width / 2, accuracy: 0.5)
    }

    func testSixteenByNineGlassEndsExactlyAtThePicture() {
        // Full-screen-like windows: the bezel must sit on the picture's edges,
        // never leave black screen at the sides inside the tube.
        for viewport in [window, CGSize(width: 2541, height: 1430), CGSize(width: 1440, height: 900),
                         CGSize(width: 1800, height: 940)] {
            let layout = CRTUniforms.framedLayout(video: CGSize(width: 1920, height: 1080), viewport: viewport)
            XCTAssertEqual(layout.glass, layout.content, "\(viewport)")
            XCTAssertFalse(layout.panels)
            let thin = min(viewport.width, viewport.height) * 0.025
            XCTAssertGreaterThanOrEqual(layout.glass.minX, thin - 0.5)
            XCTAssertGreaterThan(viewport.height - layout.glass.maxY, layout.glass.minY - 0.5)  // chin ≥ top
        }
    }

    /// A 2.35:1 film in a 16:9 window keeps a bigger tube with black inside it.
    func testCinemaScopeLetterboxesInsideTheTube() {
        let layout = CRTUniforms.framedLayout(video: CGSize(width: 2350, height: 1000), viewport: window)
        let thin = min(window.width, window.height) * 0.025
        XCTAssertNotEqual(layout.glass, layout.content)
        XCTAssertEqual(layout.glass.minY, thin, accuracy: 0.5)
        XCTAssertTrue(layout.glass.insetBy(dx: -0.5, dy: -0.5).contains(layout.content))
    }

    func testFourByThreeUsesPanels() {
        XCTAssertTrue(CRTUniforms.framedLayout(video: CGSize(width: 640, height: 480), viewport: window).panels)
    }

    /// Swift's CRTUniforms must match the Metal struct byte for byte.
    func testUniformLayoutMatchesShader() {
        // 5 float2 (40 bytes) + 14 floats (56 bytes), no padding
        XCTAssertEqual(MemoryLayout<CRTUniforms>.stride, 96)
    }

    func testCabinetPresetTurnsTheFrameOn() {
        XCTAssertTrue(CRTPreset.cabinet.settings.frame)
        XCTAssertTrue(CRTPreset.cabinet.settings.tube)
        XCTAssertFalse(CRTPreset.trinitron.settings.frame)
    }

    /// Settings saved before the frame existed must keep loading.
    func testDecodesSettingsWithoutFrameKey() throws {
        let old = #"{"enabled":true,"scanlines":0.4,"mask":0.2,"maskType":1,"curvature":0.3,"glow":0.1,"vignette":0.2,"noise":0,"brightness":1.1,"tube":true}"#
        let settings = try JSONDecoder().decode(CRTSettings.self, from: Data(old.utf8))
        XCTAssertFalse(settings.frame)
        XCTAssertEqual(settings.scanlines, 0.4)
        XCTAssertEqual(settings.maskType, .slot)
    }
}
