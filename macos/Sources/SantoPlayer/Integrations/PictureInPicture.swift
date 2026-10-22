import AVKit
import CoreMedia
import CoreVideo
import Metal
import QuartzCore

/// A texture to draw into plus whatever the consumer needs to ship it.
struct CRTSecondaryTarget {
    let texture: MTLTexture
    let pixelBuffer: CVPixelBuffer
    let cvTexture: CVMetalTexture
}

protocol CRTSecondaryOutput: AnyObject {
    func nextTarget(aspect: CGSize) -> CRTSecondaryTarget?
    func frameReady(_ target: CRTSecondaryTarget)
}

/// Picture in Picture with the CRT effect: each processed frame is drawn into
/// a pixel buffer and enqueued on an AVSampleBufferDisplayLayer, the content
/// source AVKit floats.
@MainActor @Observable
final class PictureInPicture: NSObject {
    static let width = 960

    let displayLayer = AVSampleBufferDisplayLayer()
    private(set) var isActive = false
    private(set) var isPossible = false

    @ObservationIgnored private let model: PlayerModel
    @ObservationIgnored private var controller: AVPictureInPictureController?
    @ObservationIgnored private var pool: CVPixelBufferPool?
    @ObservationIgnored private var poolSize = CGSize.zero
    @ObservationIgnored private var textureCache: CVMetalTextureCache?
    @ObservationIgnored private var formatDescription: CMVideoFormatDescription?
    @ObservationIgnored private var timebase: CMTimebase?
    @ObservationIgnored private var offscreenTimer: Timer?
    @ObservationIgnored private var possibleObservation: NSKeyValueObservation?
    @ObservationIgnored weak var window: NSWindow?
    // Read by AVKit's playback delegate (may be off the main thread).
    @ObservationIgnored nonisolated(unsafe) private var snapshotPaused = true
    @ObservationIgnored nonisolated(unsafe) private var snapshotDuration: Double = 0

    init(model: PlayerModel) {
        self.model = model
        super.init()
        displayLayer.videoGravity = .resizeAspect
        if let device = model.renderer?.device {
            CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        }
        var tb: CMTimebase?
        CMTimebaseCreateWithSourceClock(allocator: nil, sourceClock: CMClockGetHostTimeClock(), timebaseOut: &tb)
        timebase = tb
        displayLayer.controlTimebase = tb
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: displayLayer,
                                                                playbackDelegate: self)
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        self.controller = controller
        possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] c, _ in
            let possible = c.isPictureInPicturePossible
            Task { @MainActor in self?.isPossible = possible }
        }
    }

    /// Mirrors play state / position into the PiP clock and controls.
    func syncState() {
        snapshotPaused = !model.isPlaying
        snapshotDuration = model.duration
        if let timebase {
            CMTimebaseSetTime(timebase, time: CMTime(seconds: model.currentTime, preferredTimescale: 600))
            CMTimebaseSetRate(timebase, rate: model.isPlaying ? Double(model.rate) : 0)
        }
        controller?.invalidatePlaybackState()
    }

    func toggle() {
        guard let controller else { return }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
            return
        }
        guard model.hasMedia, !model.isAudioOnly else {
            return model.flash(String(localized: "Abra um vídeo para usar o Picture in Picture"), symbol: "pip")
        }
        attach()
        syncState()
        model.renderer?.offscreenTick()
        controller.startPictureInPicture()
    }

    private func attach() {
        model.renderer?.secondaryOutput = self
    }

    private func detach() {
        model.subtitles.forceInside = false
        model.renderer?.secondaryOutput = nil
        offscreenTimer?.invalidate()
        offscreenTimer = nil
        displayLayer.flush()
    }

    /// The window's display link stops when it is minimised; keep PiP fed.
    private func startOffscreenTimer() {
        offscreenTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isActive else { return }
                let visible = self.window?.occlusionState.contains(.visible) ?? false
                if !visible || self.window?.isMiniaturized == true { self.model.renderer?.offscreenTick() }
            }
        }
        // Common modes: keeps firing during live resize, menus and drags.
        RunLoop.main.add(timer, forMode: .common)
        offscreenTimer = timer
    }

    private func makePool(for size: CGSize) -> CVPixelBufferPool? {
        if let pool, poolSize == size { return pool }
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        var newPool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(nil, [kCVPixelBufferPoolMinimumBufferCountKey: 4] as CFDictionary,
                                attributes as CFDictionary, &newPool)
        pool = newPool
        poolSize = size
        formatDescription = nil
        return newPool
    }
}

extension PictureInPicture: CRTSecondaryOutput {
    nonisolated func nextTarget(aspect: CGSize) -> CRTSecondaryTarget? {
        MainActor.assumeIsolated {
            guard aspect.width > 0, aspect.height > 0, let cache = textureCache else { return nil }
            let height = (Int(Double(Self.width) * aspect.height / aspect.width) / 2) * 2
            guard let pool = makePool(for: CGSize(width: Self.width, height: max(height, 2))) else { return nil }
            var buffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { return nil }
            var cvTexture: CVMetalTexture?
            CVMetalTextureCacheCreateTextureFromImage(nil, cache, buffer, nil, .bgra8Unorm,
                                                      CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer),
                                                      0, &cvTexture)
            guard let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture) else { return nil }
            return CRTSecondaryTarget(texture: texture, pixelBuffer: buffer, cvTexture: cvTexture)
        }
    }

    nonisolated func frameReady(_ target: CRTSecondaryTarget) {
        MainActor.assumeIsolated { enqueue(target.pixelBuffer) }
    }

    private func enqueue(_ pixelBuffer: CVPixelBuffer) {
        if formatDescription == nil {
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixelBuffer,
                                                         formatDescriptionOut: &formatDescription)
        }
        guard let formatDescription else { return }
        let now = timebase.map { CMTimebaseGetTime($0) } ?? .zero
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: now, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixelBuffer,
                                                 formatDescription: formatDescription, sampleTiming: &timing,
                                                 sampleBufferOut: &sample)
        guard let sample else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) as? [NSMutableDictionary] {
            attachments.first?[kCMSampleAttachmentKey_DisplayImmediately] = true
        }
        if displayLayer.sampleBufferRenderer.status == .failed { displayLayer.sampleBufferRenderer.flush() }
        displayLayer.sampleBufferRenderer.enqueue(sample)
    }
}

extension PictureInPicture: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in
            self.isActive = true
            self.model.subtitles.forceInside = true
            self.attach()
            self.startOffscreenTimer()
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in
            self.isActive = false
            self.detach()
        }
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor in
            self.isActive = false
            self.detach()
            self.model.flash(String(localized: "Picture in Picture indisponível"), symbol: "pip")
        }
    }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        Task { @MainActor in
            NSApp.activate()
            self.window?.deminiaturize(nil)
            self.window?.makeKeyAndOrderFront(nil)
            completionHandler(true)
        }
    }
}

extension PictureInPicture: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, setPlaying playing: Bool) {
        Task { @MainActor in self.model.setPaused(!playing) }
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ controller: AVPictureInPictureController) -> CMTimeRange {
        let duration = snapshotDuration > 0 ? snapshotDuration : .infinity
        return CMTimeRange(start: .zero, duration: duration.isFinite
                           ? CMTime(seconds: duration, preferredTimescale: 600) : .positiveInfinity)
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ controller: AVPictureInPictureController) -> Bool {
        snapshotPaused
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                skipByInterval skipInterval: CMTime,
                                                completion completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            self.model.skip(skipInterval.seconds)
            completionHandler()
        }
    }
}
