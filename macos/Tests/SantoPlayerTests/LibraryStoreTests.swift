import XCTest
@testable import SantoPlayer

@MainActor
final class LibraryStoreTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "LibraryStoreTests-\(UUID().uuidString)")
    }

    private func makeStore() -> LibraryStore { LibraryStore(defaults: defaults, key: "library") }
    private let movie = URL(fileURLWithPath: "/tmp/movie.mkv")

    func testResumesFromSavedPosition() {
        let store = makeStore()
        store.record(movie, position: 600, duration: 3600)
        XCTAssertEqual(store.resumePosition(for: movie), 600)
    }

    func testDoesNotResumeNearStartOrEnd() {
        let store = makeStore()
        store.record(movie, position: 5, duration: 3600)
        XCTAssertNil(store.resumePosition(for: movie))
        store.record(movie, position: 3590, duration: 3600)
        XCTAssertNil(store.resumePosition(for: movie))
        XCTAssertTrue(store.items[0].isFinished)
    }

    func testMostRecentFirstWithoutDuplicates() {
        let store = makeStore()
        let other = URL(fileURLWithPath: "/tmp/other.mp4")
        store.record(movie, position: 100, duration: 1000)
        store.record(other, position: 100, duration: 1000)
        store.record(movie, position: 200, duration: 1000)
        XCTAssertEqual(store.items.map(\.path), [movie.path, other.path])
        XCTAssertEqual(store.items[0].position, 200)
    }

    func testPersistsAcrossInstances() {
        makeStore().record(movie, position: 300, duration: 1000)
        XCTAssertEqual(makeStore().resumePosition(for: movie), 300)
    }

    func testCapsTheList() {
        let store = makeStore()
        for i in 0..<(LibraryStore.maxItems + 5) {
            store.record(URL(fileURLWithPath: "/tmp/\(i).mp4"), position: 50, duration: 100)
        }
        XCTAssertEqual(store.items.count, LibraryStore.maxItems)
    }

    func testRemoveAndClear() {
        let store = makeStore()
        store.record(movie, position: 100, duration: 1000)
        store.remove(store.items[0])
        XCTAssertTrue(store.items.isEmpty)
        store.record(movie, position: 100, duration: 1000)
        store.clear()
        XCTAssertTrue(store.items.isEmpty)
    }

    func testIgnoresNonFiniteValues() {
        let store = makeStore()
        store.record(movie, position: .nan, duration: 100)
        XCTAssertTrue(store.items.isEmpty)
    }

    func testCacheKeyIsStableAndDistinct() {
        XCTAssertEqual(LibraryStore.cacheKey(for: movie), LibraryStore.cacheKey(for: movie))
        XCTAssertNotEqual(LibraryStore.cacheKey(for: movie), LibraryStore.cacheKey(for: URL(fileURLWithPath: "/tmp/x")))
    }
}
