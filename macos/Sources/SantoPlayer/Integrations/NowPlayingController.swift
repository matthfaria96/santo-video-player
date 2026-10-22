import AppKit
import MediaPlayer

/// Media keys, AirPods/Touch Bar controls and the Control Center "Now Playing" card.
@MainActor
final class NowPlayingController {
    private let model: PlayerModel
    private var artworkURL: URL?
    private var artwork: MPMediaItemArtwork?

    init(model: PlayerModel) {
        self.model = model
        registerCommands()
        let previous = model.onStateChange
        model.onStateChange = { [weak self] in
            previous?()
            self?.update()
        }
        let previousLoaded = model.onFileLoaded
        model.onFileLoaded = { [weak self] in
            previousLoaded?()
            self?.artwork = nil
            self?.artworkURL = nil
            self?.update()
        }
    }

    private func registerCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in self?.run { $0.setPaused(false) } ?? .commandFailed }
        center.pauseCommand.addTarget { [weak self] _ in self?.run { $0.setPaused(true) } ?? .commandFailed }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in self?.run { $0.togglePlay() } ?? .commandFailed }
        center.nextTrackCommand.addTarget { [weak self] _ in self?.run { $0.next() } ?? .commandFailed }
        center.previousTrackCommand.addTarget { [weak self] _ in self?.run { $0.previous() } ?? .commandFailed }
        center.skipForwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.preferredIntervals = [10]
        center.skipForwardCommand.addTarget { [weak self] _ in self?.run { $0.skip(10) } ?? .commandFailed }
        center.skipBackwardCommand.addTarget { [weak self] _ in self?.run { $0.skip(-10) } ?? .commandFailed }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            return self?.run { $0.seek(to: event.positionTime) } ?? .commandFailed
        }
        center.changePlaybackRateCommand.supportedPlaybackRates = PlayerModel.rates.map { NSNumber(value: $0) }
        center.changePlaybackRateCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }
            return self?.run { $0.setRate(event.playbackRate) } ?? .commandFailed
        }
    }

    private func run(_ action: (PlayerModel) -> Void) -> MPRemoteCommandHandlerStatus {
        guard model.hasMedia else { return .noActionableNowPlayingItem }
        action(model)
        update()
        return .success
    }

    /// Elapsed time + rate let the system extrapolate the progress bar itself.
    func update() {
        let center = MPNowPlayingInfoCenter.default()
        guard let url = model.currentURL else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: model.title,
            MPMediaItemPropertyPlaybackDuration: model.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: model.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: model.isPlaying ? Double(model.rate) : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: model.isAudioOnly
                ? MPNowPlayingInfoMediaType.audio.rawValue : MPNowPlayingInfoMediaType.video.rawValue,
        ]
        if model.playlist.count > 1 {
            info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = model.index
            info[MPNowPlayingInfoPropertyPlaybackQueueCount] = model.playlist.count
        }
        if let artwork, artworkURL == url { info[MPMediaItemPropertyArtwork] = artwork } else { loadArtwork(for: url) }
        center.nowPlayingInfo = info
        center.playbackState = model.isPlaying ? .playing : .paused
    }

    private func loadArtwork(for url: URL) {
        artworkURL = url
        Task { [weak self] in
            let file = ArtworkCache.url(for: url)
            var image = NSImage(contentsOf: file)
            if image == nil, let cg = await Thumbnailer.shared.image(for: url, at: 10, width: 480) {
                image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
            guard let self, let image, self.artworkURL == url else { return }
            self.artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self.update()
        }
    }
}
