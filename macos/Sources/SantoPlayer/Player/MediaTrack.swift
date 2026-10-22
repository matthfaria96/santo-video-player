import Foundation

/// An audio or subtitle track reported by mpv's `track-list`.
struct MediaTrack: Identifiable, Hashable {
    enum Kind: String { case audio, sub, video }

    let id: Int
    let kind: Kind
    let title: String?
    let language: String?
    let codec: String?
    let isExternal: Bool
    let isDefault: Bool
    let channels: Int?

    /// "Português (AC3 5.1)", "English — Commentary", "Faixa 2"…
    var displayName: String {
        var parts: [String] = []
        if let language, let name = Self.languageName(language) { parts.append(name) }
        if let title, !title.isEmpty, title != language { parts.append(title) }
        if parts.isEmpty { parts.append(String(localized: "Faixa \(String(id))")) }
        var details: [String] = []
        if let codec, !codec.isEmpty { details.append(codec.uppercased()) }
        if let channels, kind == .audio { details.append(Self.channelLabel(channels)) }
        if isExternal { details.append(String(localized: "arquivo")) }
        let name = parts.joined(separator: " — ")
        return details.isEmpty ? name : "\(name) (\(details.joined(separator: " ")))"
    }

    static func languageName(_ code: String) -> String? {
        let normalized = code.lowercased()
        guard normalized != "und", !normalized.isEmpty else { return nil }
        return Locale.current.localizedString(forLanguageCode: normalized)?.localizedCapitalized ?? code
    }

    static func channelLabel(_ channels: Int) -> String {
        switch channels {
        case 1: return "mono"
        case 2: return "2.0"
        case 6: return "5.1"
        case 8: return "7.1"
        default: return "\(channels)ch"
        }
    }

    /// Builds the list from flat `track-list/N/...` lookups.
    static func parse(count: Int, lookup: (Int, String) -> String?) -> [MediaTrack] {
        (0..<count).compactMap { index in
            guard let type = lookup(index, "type").flatMap(Kind.init(rawValue:)),
                  let id = lookup(index, "id").flatMap(Int.init) else { return nil }
            return MediaTrack(id: id, kind: type, title: lookup(index, "title"), language: lookup(index, "lang"),
                              codec: lookup(index, "codec"), isExternal: lookup(index, "external") == "yes",
                              isDefault: lookup(index, "default") == "yes",
                              channels: lookup(index, "demux-channel-count").flatMap(Int.init))
        }
    }
}
