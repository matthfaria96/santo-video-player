import XCTest
@testable import SantoPlayer

final class FormattingTests: XCTestCase {
    func testTime() {
        XCTAssertEqual(Formatting.time(0), "0:00")
        XCTAssertEqual(Formatting.time(65.9), "1:05")
        XCTAssertEqual(Formatting.time(3725), "1:02:05")
        XCTAssertEqual(Formatting.time(.nan), "0:00")
    }

    func testRate() {
        XCTAssertEqual(Formatting.rate(1), "1×")
        XCTAssertEqual(Formatting.rate(1.25), "1,25×")
        XCTAssertEqual(Formatting.rate(0.5), "0,5×")
    }
}
