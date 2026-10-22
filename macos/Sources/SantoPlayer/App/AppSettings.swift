import Foundation
import Observation

/// The single source of truth for preferences. Both the player window and the
/// Settings window observe this one object (two @AppStorage copies in separate
/// scenes fell out of sync), and every change is written to UserDefaults.
@MainActor @Observable
final class AppSettings {
    static let shared = AppSettings()

    enum Tab: String, CaseIterable, Identifiable {
        case general, playback, subtitles, about
        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return String(localized: "Geral")
            case .playback: return String(localized: "Reprodução")
            case .subtitles: return String(localized: "Legendas")
            case .about: return String(localized: "Sobre")
            }
        }
    }

    /// Interface language; nil follows the system. Applied on the next launch.
    enum Language: String, CaseIterable, Identifiable {
        case system, portuguese = "pt-BR", english = "en"
        var id: String { rawValue }

        var title: String {
            switch self {
            case .system: return String(localized: "Igual ao sistema")
            case .portuguese: return "Português (Brasil)"
            case .english: return "English"
            }
        }
    }

    /// Preferred subtitle / audio language for embedded tracks.
    enum TrackLanguage: String, CaseIterable, Identifiable {
        case system, portuguese = "pt", english = "en", spanish = "es", japanese = "ja"
        var id: String { rawValue }

        var title: String {
            switch self {
            case .system: return String(localized: "Igual ao sistema")
            case .portuguese: return String(localized: "Português")
            case .english: return String(localized: "Inglês")
            case .spanish: return String(localized: "Espanhol")
            case .japanese: return String(localized: "Japonês")
            }
        }

        /// mpv language list (ISO 639-1 and -2 codes), best first.
        var mpvList: String {
            let codes: [String: String] = ["pt": "pt,por,pob", "en": "en,eng", "es": "es,spa", "ja": "ja,jpn"]
            if let list = codes[rawValue] { return list }
            let system = Locale.current.language.languageCode?.identifier ?? "pt"
            return codes[system] ?? system
        }
    }

    static let skipIntervals: [Double] = [5, 10, 15, 30]

    /// Which Settings tab is showing (the About menu item jumps to `.about`).
    var tab: Tab = .general

    var layout: PlayerLayout { didSet { save(layout.rawValue, PlayerLayout.storageKey) } }
    var resumePlayback: Bool { didSet { save(resumePlayback, "resumePlayback") } }
    var showRecents: Bool { didSet { save(showRecents, "showRecents") } }
    var hardwareDecoding: Bool { didSet { save(hardwareDecoding, "hardwareDecoding") } }
    var skipInterval: Double { didSet { save(skipInterval, "skipInterval") } }
    var subtitleLanguage: TrackLanguage { didSet { save(subtitleLanguage.rawValue, "subtitleLanguage") } }
    var audioLanguage: TrackLanguage { didSet { save(audioLanguage.rawValue, "audioLanguage") } }
    var autoSidecarSubtitles: Bool { didSet { save(autoSidecarSubtitles, "autoSidecarSubtitles") } }
    var language: Language {
        didSet {
            save(language.rawValue, "appLanguage")
            if language == .system {
                defaults.removeObject(forKey: "AppleLanguages")
            } else {
                defaults.set([language.rawValue], forKey: "AppleLanguages")
            }
        }
    }
    /// The language the app launched with, to tell when a relaunch is needed.
    let launchLanguage: Language

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        layout = PlayerLayout(rawValue: defaults.string(forKey: PlayerLayout.storageKey) ?? "") ?? .modern
        resumePlayback = defaults.object(forKey: "resumePlayback") as? Bool ?? true
        showRecents = defaults.object(forKey: "showRecents") as? Bool ?? true
        hardwareDecoding = defaults.object(forKey: "hardwareDecoding") as? Bool ?? true
        let skip = defaults.double(forKey: "skipInterval")
        skipInterval = Self.skipIntervals.contains(skip) ? skip : 10
        subtitleLanguage = TrackLanguage(rawValue: defaults.string(forKey: "subtitleLanguage") ?? "") ?? .system
        audioLanguage = TrackLanguage(rawValue: defaults.string(forKey: "audioLanguage") ?? "") ?? .system
        autoSidecarSubtitles = defaults.object(forKey: "autoSidecarSubtitles") as? Bool ?? true
        let lang = Language(rawValue: defaults.string(forKey: "appLanguage") ?? "") ?? .system
        language = lang
        launchLanguage = lang
    }

    var needsRelaunchForLanguage: Bool { language != launchLanguage }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }
}
