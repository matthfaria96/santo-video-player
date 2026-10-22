import AppKit
import UniformTypeIdentifiers

@MainActor
enum FilePanels {
    static var mediaTypes: [UTType] {
        [.movie, .audiovisualContent, .audio, .m3uPlaylist]
            + MediaInput.mediaExtensions.compactMap { UTType(filenameExtension: $0) }
    }

    static func openMedia(_ model: PlayerModel) {
        if let urls = pick(types: mediaTypes, multiple: true, folders: true) { model.open(urls) }
    }

    /// "Abrir URL…": a stream or a file on the web (HTTP, HLS, RTSP…).
    static func openURL(_ model: PlayerModel) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Abrir URL")
        alert.informativeText = String(localized: "Endereço de um vídeo ou transmissão (HTTP, HLS .m3u8, RTSP…).")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.placeholderString = "https://"
        if let clip = NSPasteboard.general.string(forType: .string), MediaInput.streamURL(from: clip) != nil {
            field.stringValue = clip
        }
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Abrir"))
        alert.addButton(withTitle: String(localized: "Cancelar"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if let url = MediaInput.streamURL(from: field.stringValue) {
            model.open([url])
        } else {
            model.flash(String(localized: "Endereço inválido"), symbol: "link.badge.plus")
        }
    }

    static func enqueueMedia(_ model: PlayerModel) {
        if let urls = pick(types: mediaTypes, multiple: true, folders: true) { model.enqueue(urls) }
    }

    static func openSubtitle(_ model: PlayerModel) {
        let types = SubtitleController.fileExtensions.compactMap { UTType(filenameExtension: $0) }
        if let url = pick(types: types, multiple: false)?.first { model.loadSubtitle(url) }
    }

    private static func pick(types: [UTType], multiple: Bool, folders: Bool = false) -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types
        panel.allowsOtherFileTypes = true
        panel.allowsMultipleSelection = multiple
        panel.canChooseDirectories = folders
        return panel.runModal() == .OK ? panel.urls : nil
    }
}
