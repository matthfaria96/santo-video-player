import XCTest
@testable import SantoPlayer

final class MediaTrackTests: XCTestCase {
    private func parse(_ rows: [[String: String]]) -> [MediaTrack] {
        MediaTrack.parse(count: rows.count) { index, field in rows[index][field] }
    }

    func testParsesAudioSubtitleAndVideoTracks() {
        let tracks = parse([
            ["type": "video", "id": "1", "codec": "h264"],
            ["type": "audio", "id": "1", "lang": "por", "codec": "aac", "demux-channel-count": "2", "default": "yes"],
            ["type": "audio", "id": "2", "lang": "eng", "title": "Commentary", "codec": "ac3", "demux-channel-count": "6"],
            ["type": "sub", "id": "3", "lang": "por", "external": "yes", "codec": "subrip"],
        ])
        XCTAssertEqual(tracks.map(\.kind), [.video, .audio, .audio, .sub])
        XCTAssertTrue(tracks[1].isDefault)
        XCTAssertEqual(tracks[2].channels, 6)
        XCTAssertTrue(tracks[3].isExternal)
    }

    func testSkipsRowsWithoutTypeOrID() {
        XCTAssertTrue(parse([["type": "audio"], ["id": "2"], ["type": "bogus", "id": "3"]]).isEmpty)
    }

    func testDisplayNameIncludesTitleCodecAndChannels() {
        let track = parse([["type": "audio", "id": "2", "title": "Commentary", "codec": "ac3",
                            "demux-channel-count": "6"]])[0]
        XCTAssertEqual(track.displayName, "Commentary (AC3 5.1)")
    }

    func testDisplayNameFallsBackToTrackNumber() {
        let track = parse([["type": "sub", "id": "4", "lang": "und"]])[0]
        XCTAssertTrue(track.displayName.contains("4"))
    }

    func testChannelLabels() {
        XCTAssertEqual(MediaTrack.channelLabel(1), "mono")
        XCTAssertEqual(MediaTrack.channelLabel(2), "2.0")
        XCTAssertEqual(MediaTrack.channelLabel(8), "7.1")
        XCTAssertEqual(MediaTrack.channelLabel(3), "3ch")
    }
}
