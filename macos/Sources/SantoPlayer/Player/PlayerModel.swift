import AppKit
import Libmpv
import Observation

enum LoopMode: Int, CaseIterable {
    case off, one, all

    var label: String {
        switch self {
        case .off: return String(localized: "Repetição desligada")
        case .one: return String(localized: "Repetir este vídeo")
        case .all: return String(localized: "Repetir a playlist")
        }
    }

    var symbol: String { self == .one ? "repeat.1" : "repeat" }
}

struct OSDMessage: Equatable {
    let id = UUID()
    let text: String
    let symbol: String?
}

/// The player: libmpv for decoding (every common format), Metal for the CRT.
@MainActor @Observable
final class PlayerModel {
    static let rates: [Float] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3]

    @ObservationIgnored let renderer: CRTRenderer?
    @ObservationIgnored private(set) var mpv: MPVClient?
    let subtitles = SubtitleController()
    let library = LibraryStore()

    private(set) var playlist: [URL] = []
    private(set) var index = -1
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var isAudioOnly = false
    private(set) var isBuffering = false
    private(set) var audioTracks: [MediaTrack] = []
    private(set) var audioID: Int?
    private(set) var osd: OSDMessage?
    private(set) var startupError: String?
    /// Bumped when a cover is written, so the recents shelf reloads images.
    private(set) var artworkVersion = 0
    var isScrubbing = false
    var showStats = false

    private(set) var rate: Float = 1
    var volume: Float { didSet { applyVolume(); UserDefaults.standard.set(volume, forKey: "volume") } }
    var isMuted = false { didSet { applyVolume() } }
    var loopMode: LoopMode { didSet { UserDefaults.standard.set(loopMode.rawValue, forKey: "loop") } }
    var fillScreen = false { didSet { renderer?.fill = fillScreen } }
    var crt: CRTSettings { didSet { renderer?.settings = crt; persistCRT() } }

    var currentURL: URL? { playlist.indices.contains(index) ? playlist[index] : nil }
    var title: String {
        guard let url = currentURL else { return "Santo Video Player" }
        if url.isFileURL { return url.deletingPathExtension().lastPathComponent }
        let name = url.deletingPathExtension().lastPathComponent
        return name.isEmpty || name == "/" ? (url.host ?? url.absoluteString) : "\(url.host ?? "") · \(name)"
    }
    /// Network streams: no resume, covers or thumbnails.
    var isStream: Bool { currentURL.map { !MediaInput.isTrackable($0) } ?? false }
    var hasMedia: Bool { currentURL != nil }
    var crtPreset: CRTPreset? { CRTPreset.matching(crt) }
    /// Frames mpv dropped or decoded late (for the diagnostics overlay).
    var droppedFrames: Int {
        Int((mpv?.int("frame-drop-count") ?? 0) + (mpv?.int("decoder-frame-drop-count") ?? 0))
    }

    @ObservationIgnored private var paused = true
    @ObservationIgnored private var eof = false
    @ObservationIgnored private var pendingResume: Double?
    @ObservationIgnored private var lastSaved: Double = 0
    @ObservationIgnored private var osdTask: Task<Void, Never>?
    @ObservationIgnored private var videoWidth: Int64 = 0
    @ObservationIgnored private var videoHeight: Int64 = 0
    /// Hooks for the integrations (now playing, PiP) that follow the model.
    @ObservationIgnored var onFileLoaded: (() -> Void)?
    @ObservationIgnored var onStateChange: (() -> Void)?

    init() {
        let defaults = UserDefaults.standard
        volume = defaults.object(forKey: "volume") as? Float ?? 1
        loopMode = LoopMode(rawValue: defaults.integer(forKey: "loop")) ?? .off
        crt = defaults.data(forKey: "crt").flatMap { try? JSONDecoder().decode(CRTSettings.self, from: $0) }
            ?? CRTPreset.trinitron.settings
        renderer = try? CRTRenderer()
        renderer?.settings = crt
        do {
            let client = try MPVClient(options: Self.mpvOptions)
            mpv = client
            subtitles.bind(client)
            if let renderer { renderer.bridge = try MPVVideoBridge(client: client, device: renderer.device) }
            observe(client)
            applyVolume()
            applySettings()
            observeSettings()
        } catch {
            startupError = error.localizedDescription
        }
    }

    static let mpvOptions: [String: String] = [
        "vo": "libmpv",
        "hwdec": "auto-safe",
        "keep-open": "yes",
        "idle": "yes",
        "sub-auto": "fuzzy",
        "audio-file-auto": "fuzzy",
        "input-default-bindings": "no",
        "input-vo-keyboard": "no",
        "osc": "no",
        "ytdl": "no",
        "volume-max": "100",
        "audio-pitch-correction": "yes",
        "hr-seek": "yes",
        "terminal": "no",
    ]

    /// Re-applies Ajustes whenever one of the mpv-facing values changes, so no
    /// settings view can forget to.
    private func observeSettings() {
        withObservationTracking {
            let settings = AppSettings.shared
            _ = (settings.hardwareDecoding, settings.subtitleLanguage, settings.audioLanguage,
                 settings.deinterlace, settings.nativeScanlines, settings.autoCabinet)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applySettings()
                self?.observeSettings()
            }
        }
    }

    /// Pushes Ajustes into mpv (decoding, preferred track languages).
    func applySettings() {
        let settings = AppSettings.shared
        mpv?.set("hwdec", settings.hardwareDecoding ? "auto-safe" : "no")
        mpv?.set("slang", settings.subtitleLanguage.mpvList)
        mpv?.set("alang", settings.audioLanguage.mpvList)
        // "auto": only frames flagged as interlaced (DVD, TV recordings) are deinterlaced.
        mpv?.set("deinterlace", settings.deinterlace ? "auto" : "no")
        renderer?.nativeScanlines = settings.nativeScanlines
        renderer?.autoCabinet = settings.autoCabinet
    }

    func shutdown() {
        saveProgress(force: true)
        renderer?.bridge?.shutdown()
        renderer?.bridge = nil
        mpv = nil
    }

    // MARK: mpv state

    private func observe(_ client: MPVClient) {
        client.observe("time-pos", MPV_FORMAT_DOUBLE)
        client.observe("duration", MPV_FORMAT_DOUBLE)
        client.observe("pause", MPV_FORMAT_FLAG)
        client.observe("eof-reached", MPV_FORMAT_FLAG)
        client.observe("paused-for-cache", MPV_FORMAT_FLAG)
        client.observe("dwidth", MPV_FORMAT_INT64)
        client.observe("dheight", MPV_FORMAT_INT64)
        client.observe("track-list", MPV_FORMAT_NONE)
        client.observe("sid", MPV_FORMAT_STRING)
        client.observe("aid", MPV_FORMAT_STRING)
        client.observe("sub-text", MPV_FORMAT_STRING)
        client.observe("sub-delay", MPV_FORMAT_DOUBLE)
        client.onProperty = { [weak self] name, value in self?.propertyChanged(name, value) }
        client.onEvent = { [weak self] event, reason in self?.event(event, reason: reason) }
    }

    private func propertyChanged(_ name: String, _ value: MPVValue) {
        switch (name, value) {
        case ("time-pos", .double(let t)):
            if !isScrubbing, abs(t - currentTime) >= 0.1 { currentTime = t }
            saveProgress()
        case ("duration", .double(let d)): duration = d; onStateChange?()
        case ("pause", .flag(let p)): paused = p; refreshPlaying()
        case ("eof-reached", .flag(let e)):
            eof = e
            refreshPlaying()
            if e { itemEnded() }
        case ("paused-for-cache", .flag(let b)): isBuffering = b
        case ("dwidth", .int(let w)): updateVideoSize(width: w, height: nil)
        case ("dheight", .int(let h)): updateVideoSize(width: nil, height: h)
        case ("track-list", _): refreshTracks()
        case ("sid", .string(let s)): subtitles.update(selection: s)
        case ("sid", .none): subtitles.update(selection: nil)
        case ("aid", .string(let a)): audioID = Int(a)
        case ("sub-text", .string(let t)): subtitles.update(text: t)
        case ("sub-text", .none): subtitles.update(text: nil)
        case ("sub-delay", .double(let d)): subtitles.update(delay: d)
        default: break
        }
    }

    private func event(_ event: mpv_event_id, reason: mpv_end_file_reason?) {
        switch event {
        case MPV_EVENT_FILE_LOADED:
            mpv?.set("speed", Double(rate))
            if let resume = pendingResume {
                mpv?.command("seek", String(resume), "absolute+exact")
                flash(String(localized: "Continuando de \(Formatting.time(resume))  ·  ⇧⌘← volta ao início"),
                      symbol: "clock.arrow.circlepath", seconds: 3.5)
            }
            pendingResume = nil
            eof = false
            refreshPlaying()
            addSymlinkSidecars()
            refreshTracks()
            // A subtitle file next to the video means the viewer wants it on.
            if AppSettings.shared.autoSidecarSubtitles, subtitles.selectedID == nil,
               let sidecar = subtitles.tracks.first(where: \.isExternal) {
                subtitles.select(sidecar.id)
            }
            if let url = currentURL, MediaInput.isTrackable(url), !FileManager.default.fileExists(atPath: ArtworkCache.url(for: url).path) {
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(1))
                    guard let self, self.currentURL == url else { return }
                    self.refreshArtwork(for: url, at: 0)
                }
            }
            onFileLoaded?()
        case MPV_EVENT_PLAYBACK_RESTART:
            onStateChange?()            // seeks, frame steps and loops: resync external clocks
        case MPV_EVENT_END_FILE where reason == MPV_END_FILE_REASON_ERROR:
            let ext = currentURL?.pathExtension.uppercased() ?? ""
            flash(String(localized: "Não foi possível reproduzir este arquivo \(ext)."),
                  symbol: "exclamationmark.triangle", seconds: 4)
        default:
            break
        }
    }

    /// mpv looks for sidecar subtitles next to the link's target; a link's
    /// own folder is where the viewer put them, so add those too.
    private func addSymlinkSidecars() {
        guard AppSettings.shared.autoSidecarSubtitles, let url = currentURL, url.isFileURL,
              (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true else { return }
        let base = url.deletingPathExtension().lastPathComponent.lowercased()
        let siblings = (try? FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(),
                                                                     includingPropertiesForKeys: nil)) ?? []
        for file in siblings where Self.isSubtitle(file) {
            let name = file.deletingPathExtension().lastPathComponent.lowercased()
            if name == base || name.hasPrefix(base + ".") { mpv?.command("sub-add", file.path, "auto") }
        }
    }

    private func refreshPlaying() {
        let playing = hasMedia && !paused && !eof
        if playing != isPlaying { isPlaying = playing }
        onStateChange?()
    }

    private func updateVideoSize(width: Int64?, height: Int64?) {
        if let width { videoWidth = width }
        if let height { videoHeight = height }
        renderer?.displaySize = CGSize(width: Int(videoWidth), height: Int(videoHeight))
    }

    private func refreshTracks() {
        guard let mpv else { return }
        let count = Int(mpv.int("track-list/count") ?? 0)
        let tracks = MediaTrack.parse(count: count) { mpv.string("track-list/\($0)/\($1)") }
        audioTracks = tracks.filter { $0.kind == .audio }
        subtitles.update(tracks: tracks)
        let hasPicture = tracks.contains { $0.kind == .video && !["mjpeg", "png"].contains($0.codec ?? "") }
        isAudioOnly = hasMedia && count > 0 && !hasPicture
    }

    // MARK: Opening

    static func isSubtitle(_ url: URL) -> Bool {
        SubtitleController.fileExtensions.contains(url.pathExtension.lowercased())
    }

    /// Folders and playlists are expanded off the main thread (a big drive
    /// or a slow network share would otherwise freeze the window).
    func open(_ urls: [URL]) {
        let subs = urls.filter(Self.isSubtitle)
        let inputs = urls.filter { !Self.isSubtitle($0) }
        if inputs.contains(where: Self.needsScan) { flash(String(localized: "Lendo pasta…"), symbol: "folder") }
        Task {
            let media = await Task.detached(priority: .userInitiated) { MediaInput.expand(inputs) }.value
            finishOpen(media: media, subs: subs, requested: !urls.isEmpty)
        }
    }

    private static func needsScan(_ url: URL) -> Bool {
        url.hasDirectoryPath || MediaInput.playlistExtensions.contains(url.pathExtension.lowercased())
    }

    private func finishOpen(media: [URL], subs: [URL], requested: Bool) {
        if media.isEmpty, subs.isEmpty, requested {
            return flash(String(localized: "Nenhum vídeo encontrado aqui"), symbol: "questionmark.folder")
        }
        if !media.isEmpty {
            playlist = media
            load(at: 0)
        }
        for sub in subs where hasMedia { loadSubtitle(sub) }
    }

    func enqueue(_ urls: [URL]) {
        guard hasMedia else { return open(urls) }
        let inputs = urls.filter { !Self.isSubtitle($0) }
        Task {
            let media = await Task.detached(priority: .userInitiated) { MediaInput.expand(inputs) }.value
            playlist += media
            flash(String(localized: "\(media.count) adicionado(s) à playlist"), symbol: "text.badge.plus")
        }
    }

    func loadSubtitle(_ url: URL) {
        subtitles.addFile(url)
        flash(String(localized: "Legenda: \(url.lastPathComponent)"), symbol: "captions.bubble")
    }

    func play(at newIndex: Int) {
        guard playlist.indices.contains(newIndex) else { return }
        load(at: newIndex)
    }

    func remove(at offsets: IndexSet) {
        saveProgress(force: true)   // before the array changes, while currentURL is still right
        let removedBefore = offsets.filter { $0 < index }.count
        let removedCurrent = offsets.contains(index)
        playlist = playlist.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        if !removedCurrent {
            index -= removedBefore
        } else if playlist.isEmpty {
            closeMedia()
        } else {
            let next = min(index - removedBefore, playlist.count - 1)
            index = -1                  // already saved above; keep load() from saving to the wrong file
            load(at: next)
        }
    }

    private func load(at newIndex: Int) {
        saveProgress(force: true)
        index = newIndex
        let url = playlist[newIndex]
        currentTime = 0
        duration = 0
        isAudioOnly = false
        eof = false
        subtitles.reset()
        audioTracks = []
        renderer?.resetFrame()
        renderer?.acceptsFrames = true
        let trackable = MediaInput.isTrackable(url)
        pendingResume = AppSettings.shared.resumePlayback && trackable ? library.resumePosition(for: url) : nil
        lastSaved = 0
        applySettings()
        mpv?.command("loadfile", url.isFileURL ? url.path : url.absoluteString, "replace")
        mpv?.set("pause", false)
        paused = false
        refreshPlaying()
        guard trackable else { return }
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        let known = library.items.first { $0.path == url.path }
        library.record(url, position: pendingResume ?? known?.position ?? 0, duration: known?.duration ?? 0)
    }

    func closeMedia() {
        saveProgress(force: true)
        mpv?.command("stop")
        renderer?.acceptsFrames = false
        renderer?.resetFrame()
        subtitles.reset()
        audioTracks = []
        playlist = []
        index = -1
        currentTime = 0
        duration = 0
        pendingResume = nil
        eof = false
        isAudioOnly = false
        updateVideoSize(width: 0, height: 0)
        refreshPlaying()
    }

    private func saveProgress(force: Bool = false) {
        guard let url = currentURL, MediaInput.isTrackable(url), duration > 0 else { return }
        guard force || abs(currentTime - lastSaved) >= 5 else { return }
        lastSaved = currentTime
        library.record(url, position: currentTime, duration: duration)
        if force { refreshArtwork(for: url, at: currentTime) }
    }

    /// Cover for the recents shelf: the frame where the viewer stopped, or a
    /// representative one (10% in) for files that were barely started.
    private func refreshArtwork(for url: URL, at seconds: Double) {
        let position = seconds > 5 ? seconds : min(max(duration * 0.1, 1), 60)
        Task {
            guard let image = await Thumbnailer.shared.image(for: url, at: position, width: 480) else { return }
            ArtworkCache.save(image, for: url)
            artworkVersion += 1
        }
    }

    private func itemEnded() {
        switch loopMode {
        case .one:
            seek(to: 0)
            mpv?.set("pause", false)
        case .all:
            load(at: (index + 1) % max(playlist.count, 1))
        case .off:
            saveProgress(force: true)
            if index + 1 < playlist.count { load(at: index + 1) }
        }
    }

    // MARK: Transport

    func togglePlay() {
        guard hasMedia else { return }
        if eof { seek(to: 0) }
        mpv?.set("pause", isPlaying)
    }

    func setPaused(_ value: Bool) {
        guard hasMedia else { return }
        mpv?.set("pause", value)
    }

    func seek(to seconds: Double) {
        let target = max(0, duration > 0 ? min(seconds, duration) : seconds)
        currentTime = target
        mpv?.command("seek", String(target), "absolute+exact")
        onStateChange?()
    }

    /// Fast keyframe seek while the scrubber is dragged.
    func scrub(to seconds: Double) {
        currentTime = seconds
        mpv?.command("seek", String(seconds), "absolute+keyframes")
    }

    func skip(_ delta: Double) {
        guard hasMedia else { return }
        seek(to: currentTime + delta)
        flash(delta > 0 ? "+\(Int(delta))s" : "\(Int(delta))s", symbol: delta > 0 ? "goforward" : "gobackward")
    }

    func restartFromBeginning() {
        guard hasMedia else { return }
        seek(to: 0)
        flash(String(localized: "Do início"), symbol: "backward.end")
    }

    func next() { if index + 1 < playlist.count { load(at: index + 1) } }
    func previous() {
        if currentTime > 3 || index == 0 { seek(to: 0) } else if index > 0 { load(at: index - 1) }
    }

    func step(frames: Int) {
        guard hasMedia else { return }
        mpv?.command(frames < 0 ? "frame-back-step" : "frame-step")
    }

    // MARK: Speed, volume, audio

    func setRate(_ newRate: Float) {
        rate = min(max(newRate, 0.25), 3)
        mpv?.set("speed", Double(rate))
        flash(String(localized: "Velocidade \(Formatting.rate(rate))"), symbol: "gauge.with.dots.needle.67percent")
        onStateChange?()
    }

    func faster() { setRate(Self.rates.first { $0 > rate + 0.001 } ?? rate) }
    func slower() { setRate(Self.rates.last { $0 < rate - 0.001 } ?? rate) }

    func nudgeVolume(_ delta: Float) {
        volume = min(max(volume + delta, 0), 1)
        isMuted = false
        flash(String(localized: "Volume \(Int((volume * 100).rounded()))%"), symbol: volumeSymbol)
    }

    var volumeSymbol: String {
        if isMuted || volume == 0 { return "speaker.slash.fill" }
        return volume < 0.34 ? "speaker.wave.1.fill" : volume < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
    }

    private func applyVolume() {
        mpv?.set("volume", Double(volume * 100))
        mpv?.set("mute", isMuted)
    }

    func selectAudio(_ id: Int) {
        mpv?.set("aid", String(id))
        if let track = audioTracks.first(where: { $0.id == id }) {
            flash(String(localized: "Áudio: \(track.displayName)"), symbol: "waveform")
        }
    }

    func cycleAudio() {
        guard audioTracks.count > 1 else {
            return flash(String(localized: "Só uma faixa de áudio"), symbol: "waveform")
        }
        let current = audioTracks.firstIndex { $0.id == audioID } ?? -1
        selectAudio(audioTracks[(current + 1) % audioTracks.count].id)
    }

    // MARK: Effects, subtitles, misc

    func apply(_ preset: CRTPreset) {
        crt = preset.settings
        flash(preset.name, symbol: preset.symbol)
    }

    func cycleSubtitles() { flash(subtitles.cycle(), symbol: "captions.bubble") }

    func shiftSubtitles(_ delta: Double) {
        subtitles.shift(by: delta)
        let next = subtitles.delay + delta
        flash(String(localized: "Atraso da legenda \(String(format: "%+.1f", next)) s"),
              symbol: "clock.arrow.2.circlepath")
    }

    func cycleLoop() {
        loopMode = LoopMode(rawValue: (loopMode.rawValue + 1) % LoopMode.allCases.count) ?? .off
        flash(loopMode.label, symbol: loopMode.symbol)
    }

    func toggleFill() {
        fillScreen.toggle()
        flash(fillScreen ? String(localized: "Preencher tela") : String(localized: "Ajustar à tela"),
              symbol: fillScreen ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
    }

    func snapshot() {
        guard let image = renderer?.renderImage() else {
            return flash(String(localized: "Nada para capturar"), symbol: "camera")
        }
        do {
            let url = try Snapshot.save(image, name: title)
            flash(String(localized: "Captura salva em Imagens"), symbol: "camera.fill")
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            flash(error.localizedDescription, symbol: "exclamationmark.triangle")
        }
    }

    func flash(_ text: String, symbol: String? = nil, seconds: Double = 1.4) {
        osd = OSDMessage(text: text, symbol: symbol)
        osdTask?.cancel()
        osdTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.osd = nil
        }
    }

    private func persistCRT() {
        if let data = try? JSONEncoder().encode(crt) { UserDefaults.standard.set(data, forKey: "crt") }
    }
}
