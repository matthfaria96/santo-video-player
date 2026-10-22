import XCTest
@testable import SantoPlayer

final class MediaInputTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("MediaInputTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Season 1"), withIntermediateDirectories: true)
        for name in ["Season 1/ep10.mkv", "Season 1/ep2.mkv", "Season 1/ep1.mkv", "notes.txt", "cover.jpg", "song.flac"] {
            FileManager.default.createFile(atPath: folder.appendingPathComponent(name).path, contents: Data())
        }
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: folder) }

    func testFolderExpandsToMediaInNaturalOrder() {
        let names = MediaInput.expand([folder]).map { $0.lastPathComponent }
        XCTAssertEqual(names, ["ep1.mkv", "ep2.mkv", "ep10.mkv", "song.flac"])
    }

    func testParsesM3UWithRelativeAbsoluteAndRemoteEntries() {
        let text = "#EXTM3U\n#EXTINF:10,One\nSeason 1/ep1.mkv\n/abs/movie.mp4\nhttps://example.com/live.m3u8\n\n"
        let urls = MediaInput.parseM3U(text, relativeTo: folder)
        XCTAssertEqual(urls.count, 3)
        XCTAssertEqual(urls[0].path, folder.appendingPathComponent("Season 1/ep1.mkv").path)
        XCTAssertEqual(urls[1].path, "/abs/movie.mp4")
        XCTAssertEqual(urls[2].absoluteString, "https://example.com/live.m3u8")
    }

    func testHLSManifestIsKeptAsAStream() throws {
        let manifest = folder.appendingPathComponent("stream.m3u8")
        try "#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:6\nseg0.ts\n".write(to: manifest, atomically: true, encoding: .utf8)
        XCTAssertEqual(MediaInput.expand([manifest]), [manifest])
    }

    func testStreamURLParsing() {
        XCTAssertEqual(MediaInput.streamURL(from: " https://a.com/x.m3u8 ")?.absoluteString, "https://a.com/x.m3u8")
        XCTAssertEqual(MediaInput.streamURL(from: "a.com/video.mp4")?.absoluteString, "https://a.com/video.mp4")
        XCTAssertEqual(MediaInput.streamURL(from: "rtsp://cam.local/live")?.scheme, "rtsp")
        XCTAssertNil(MediaInput.streamURL(from: "not a url"))
        XCTAssertNil(MediaInput.streamURL(from: "file:///etc/passwd"))
        XCTAssertNil(MediaInput.streamURL(from: ""))
    }

    func testRecognisesCommonFormats() {
        for ext in ["mkv", "webm", "avi", "mp4", "mov", "ts", "flac", "opus"] {
            XCTAssertTrue(MediaInput.isMedia(URL(fileURLWithPath: "/x.\(ext)")), ext)
        }
        XCTAssertFalse(MediaInput.isMedia(URL(fileURLWithPath: "/x.txt")))
    }
}

final class PlaylistEdgeCaseTests: XCTestCase {
    private let base = URL(fileURLWithPath: "/music")

    func testWindowsPathsPercentEncodingAndBOM() {
        let text = "\u{FEFF}#EXTM3U\r\nArtist\\a.mp3\r\nMy%20Video.mp4\r\nC:\\Music\\b.mp3\r\n"
        let paths = MediaInput.parseM3U(text, relativeTo: base).map(\.path)
        XCTAssertEqual(paths, ["/music/Artist/a.mp3", "/music/My Video.mp4"])
    }

    func testDecodesCP1252Playlist() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("cp1252-\(UUID().uuidString).m3u")
        try Data([0x41, 0xE7, 0xE3, 0x6F, 0x2E, 0x6D, 0x70, 0x33]).write(to: file)   // "Ação.mp3"
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual(MediaInput.readText(file), "Ação.mp3")
    }

    func testMissingEntriesAreDroppedAndUnreadableListsYieldNothing() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        FileManager.default.createFile(atPath: folder.appendingPathComponent("real.mp4").path, contents: Data())
        let list = folder.appendingPathComponent("list.m3u")
        try "real.mp4\nmissing.mp4\nhttps://a.com/x.mp4\n".write(to: list, atomically: true, encoding: .utf8)
        XCTAssertEqual(MediaInput.expand([list]).map(\.lastPathComponent), ["real.mp4", "x.mp4"])
        XCTAssertTrue(MediaInput.expand([folder.appendingPathComponent("nope.m3u")]).isEmpty)
    }

    func testTrackability() {
        XCTAssertTrue(MediaInput.isTrackable(URL(fileURLWithPath: "/m.mkv")))
        XCTAssertFalse(MediaInput.isTrackable(URL(fileURLWithPath: "/stream/index.m3u8")))
        XCTAssertFalse(MediaInput.isTrackable(URL(string: "https://a.com/v.mp4")!))
    }
}
