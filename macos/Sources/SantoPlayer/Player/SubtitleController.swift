import Foundation
import Observation

/// Subtitle state backed by mpv: tracks (embedded + files), selection, delay
/// and the current text. Text is drawn by our overlay (crisp, above the tube)
/// unless `insideScreen` is on, where mpv draws it with its original ASS style
/// into the picture, so it gets the CRT treatment too.
@MainActor @Observable
final class SubtitleController {
    static let fileExtensions: Set<String> = ["srt", "vtt", "ass", "ssa", "sub", "idx", "sup", "smi"]

    private(set) var tracks: [MediaTrack] = []
    private(set) var selectedID: Int?
    private(set) var text = ""
    private(set) var delay: Double = 0
    var fontScale: Double = UserDefaults.standard.object(forKey: "subtitleScale") as? Double ?? 1 {
        didSet { UserDefaults.standard.set(fontScale, forKey: "subtitleScale") }
    }
    var showBackground: Bool = UserDefaults.standard.object(forKey: "subtitleBackground") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showBackground, forKey: "subtitleBackground") }
    }
    var insideScreen: Bool = UserDefaults.standard.bool(forKey: "subtitleInside") {
        didSet {
            UserDefaults.standard.set(insideScreen, forKey: "subtitleInside")
            applyVisibility()
        }
    }
    /// Picture in Picture only shows the rendered picture, so subtitles must
    /// be drawn into it while it is open.
    var forceInside = false { didSet { applyVisibility() } }

    private func applyVisibility() {
        mpv?.set("sub-visibility", insideScreen || forceInside)
    }

    @ObservationIgnored private weak var mpv: MPVClient?

    var selectedTrack: MediaTrack? { tracks.first { $0.id == selectedID } }
    /// Overlay text, empty when mpv draws subtitles itself.
    var overlayText: String { insideScreen ? "" : text }

    func bind(_ client: MPVClient) {
        mpv = client
        applyVisibility()
    }

    func update(tracks all: [MediaTrack]) { tracks = all.filter { $0.kind == .sub } }
    func update(selection raw: String?) { selectedID = raw.flatMap(Int.init) }
    func update(text newText: String?) { text = newText ?? "" }
    func update(delay newDelay: Double) { delay = newDelay }

    func reset() {
        tracks = []
        selectedID = nil
        text = ""
        delay = 0
    }

    func select(_ id: Int?) {
        mpv?.set("sid", id.map(String.init) ?? "no")
    }

    func addFile(_ url: URL) {
        mpv?.command("sub-add", url.path, "select")
    }

    func shift(by seconds: Double) {
        mpv?.set("sub-delay", delay + seconds)
    }

    func resetDelay() { mpv?.set("sub-delay", 0.0) }

    /// Cycles off → track 1 → … → off and returns the message to show.
    func cycle() -> String {
        guard !tracks.isEmpty else { return String(localized: "Sem legendas") }
        let index = tracks.firstIndex { $0.id == selectedID }.map { $0 + 1 } ?? 0
        let next = index < tracks.count ? tracks[index] : nil
        select(next?.id)
        return next.map { String(localized: "Legenda: \($0.displayName)") } ?? String(localized: "Legenda desligada")
    }
}
