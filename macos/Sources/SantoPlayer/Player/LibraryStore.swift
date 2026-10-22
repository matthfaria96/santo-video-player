import CryptoKit
import Foundation
import Observation

struct RecentItem: Codable, Identifiable, Equatable {
    var path: String
    var position: Double
    var duration: Double
    var date: Date

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
    var title: String { url.deletingPathExtension().lastPathComponent }
    var progress: Double { duration > 0 ? min(max(position / duration, 0), 1) : 0 }
    var isFinished: Bool { duration > 0 && (progress > 0.95 || duration - position < 20) }
}

/// Recently played files and where each one stopped ("continue watching").
@MainActor @Observable
final class LibraryStore {
    static let maxItems = 40
    /// Below this the start is not worth resuming.
    static let minimumResume: Double = 10

    private(set) var items: [RecentItem]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key: String

    init(defaults: UserDefaults = .standard, key: String = "library") {
        self.defaults = defaults
        self.key = key
        items = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([RecentItem].self, from: $0) } ?? []
    }

    /// Position to continue from, or nil to start at the beginning.
    func resumePosition(for url: URL) -> Double? {
        guard let item = items.first(where: { $0.path == url.path }),
              item.position >= Self.minimumResume, !item.isFinished else { return nil }
        return item.position
    }

    func record(_ url: URL, position: Double, duration: Double) {
        guard position.isFinite, duration.isFinite else { return }
        let item = RecentItem(path: url.path, position: max(position, 0), duration: max(duration, 0), date: Date())
        items = Array(([item] + items.filter { $0.path != url.path }).prefix(Self.maxItems))
        save()
    }

    func remove(_ item: RecentItem) {
        items.removeAll { $0.path == item.path }
        save()
    }

    func clear() {
        items = []
        save()
    }

    /// Existing files only (moved or deleted ones are hidden, not forgotten).
    var available: [RecentItem] { items.filter { FileManager.default.fileExists(atPath: $0.path) } }

    private func save() {
        if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: key) }
    }

    /// Stable cache file name for per-file artwork.
    nonisolated static func cacheKey(for url: URL) -> String {
        SHA256.hash(data: Data(url.path.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}
