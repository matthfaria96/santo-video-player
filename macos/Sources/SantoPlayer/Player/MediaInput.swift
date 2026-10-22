import Foundation

/// Turns whatever the user hands us (files, folders, .m3u playlists, URLs)
/// into the flat list of items the playlist plays.
enum MediaInput {
    static let videoExtensions: Set<String> = [
        "mp4", "m4v", "mov", "qt", "mkv", "webm", "avi", "wmv", "asf", "flv", "f4v", "ts", "m2ts", "mts", "mpg",
        "mpeg", "m2v", "vob", "ogv", "3gp", "3g2", "rm", "rmvb", "divx", "xvid", "mxf", "dv", "y4m", "hevc", "h264",
    ]
    static let audioExtensions: Set<String> = [
        "mp3", "m4a", "aac", "flac", "wav", "aiff", "aif", "alac", "ogg", "oga", "opus", "wma", "ape", "wv",
        "mka", "ac3", "eac3", "dts", "mpc", "tta",
    ]
    static let playlistExtensions: Set<String> = ["m3u", "m3u8"]
    static var mediaExtensions: Set<String> { videoExtensions.union(audioExtensions) }

    static func isMedia(_ url: URL) -> Bool { mediaExtensions.contains(url.pathExtension.lowercased()) }

    /// A local media file: worth resume, the recents shelf and covers.
    /// Network URLs and local stream manifests (.m3u8) are not.
    static func isTrackable(_ url: URL) -> Bool {
        url.isFileURL && !playlistExtensions.contains(url.pathExtension.lowercased())
    }

    /// Playlists from old players are often CP1252, not UTF-8.
    static func readText(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252)
        return text.map { $0.hasPrefix("\u{FEFF}") ? String($0.dropFirst()) : $0 }
    }

    /// Expands folders (recursively, natural order) and local .m3u files.
    static func expand(_ urls: [URL], fileManager: FileManager = .default) -> [URL] {
        urls.flatMap { url -> [URL] in
            guard url.isFileURL else { return [url] }
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return folderContents(url, fileManager: fileManager)
            }
            if playlistExtensions.contains(url.pathExtension.lowercased()) {
                // Unreadable lists yield nothing (never the list itself as a "video").
                guard let text = readText(url) else { return [] }
                if isHLS(text) { return [url] }
                return parseM3U(text, relativeTo: url.deletingLastPathComponent()).filter {
                    !$0.isFileURL || fileManager.fileExists(atPath: $0.path)
                }
            }
            return [url]
        }
    }

    static func folderContents(_ folder: URL, fileManager: FileManager = .default) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let walker = fileManager.enumerator(at: folder, includingPropertiesForKeys: keys,
                                                  options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        let files = walker.compactMap { $0 as? URL }.filter(isMedia)
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// HLS manifests are streams for mpv, not lists of files.
    static func isHLS(_ text: String) -> Bool {
        text.contains("#EXT-X-")
    }

    static func parseM3U(_ text: String, relativeTo base: URL) -> [URL] {
        let trimSet = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\u{FEFF}"))
        return text.split(whereSeparator: \.isNewline).compactMap { raw in
            let line = raw.trimmingCharacters(in: trimSet)
            guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
            if let url = URL(string: line), let scheme = url.scheme, scheme.count > 1 { return url }
            // Windows-made lists: backslashes; drive letters can't exist on this Mac.
            var path = line.replacingOccurrences(of: "\\", with: "/")
            if path.range(of: "^[A-Za-z]:/", options: .regularExpression) != nil { return nil }
            if path.range(of: "%[0-9A-Fa-f]{2}", options: .regularExpression) != nil {
                path = path.removingPercentEncoding ?? path
            }
            return path.hasPrefix("/")
                ? URL(fileURLWithPath: path)
                : base.appendingPathComponent(path).standardizedFileURL
        }
    }

    /// Accepts "http://…", "rtsp://…", "www.site.com/x.m3u8" and similar typed text.
    static func streamURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: withScheme), let scheme = url.scheme?.lowercased(),
              ["http", "https", "rtsp", "rtmp", "rtmps", "srt", "udp", "rtp", "mms", "ftp"].contains(scheme),
              url.host != nil else { return nil }
        return url
    }
}
