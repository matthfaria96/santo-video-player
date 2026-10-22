import MetalKit

enum CRTRendererError: LocalizedError {
    case noDevice
    case pipeline(String)

    var errorDescription: String? {
        switch self {
        case .noDevice: return String(localized: "Nenhuma GPU Metal disponível.")
        case .pipeline(let reason): return String(localized: "Falha ao compilar o shader CRT: \(reason)")
        }
    }
}

/// Pulls frames from mpv and draws them through the CRT shader.
final class CRTRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    /// Source of decoded frames (mpv rendering into IOSurfaces).
    var bridge: MPVVideoBridge?
    private(set) var texture: MTLTexture?
    private let startTime = CACurrentMediaTime()
    /// Second destination for each new frame (Picture in Picture).
    weak var secondaryOutput: CRTSecondaryOutput?

    var settings = CRTSettings() { didSet { needsRedraw = true } }
    var fill = false { didSet { needsRedraw = true } }
    /// Ajustes: scanlines at the source's own line count (SD video).
    var nativeScanlines = true { didSet { needsRedraw = true } }
    /// Ajustes: 4:3 videos automatically get the full "TV com Gabinete".
    var autoCabinet = false { didSet { needsRedraw = true } }
    /// Display size (accounts for anamorphic pixels); falls back to the frame size.
    var displaySize: CGSize = .zero { didSet { needsRedraw = true } }

    /// Set when something other than a new video frame changes the picture.
    private var needsRedraw = true
    private var lastDrawTime: CFTimeInterval = 0
    /// Read by the diagnostics overlay; computed on demand so it decays while idle.
    var stats: PlaybackStats { statsWindow.snapshot(size: lastDrawableSize) }
    private var lastDrawableSize: CGSize = .zero
    private var statsWindow = StatsWindow()

    init(device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws {
        guard let device, let queue = device.makeCommandQueue() else { throw CRTRendererError.noDevice }
        self.device = device
        self.queue = queue
        do {
            let library = try device.makeLibrary(source: CRTShaderSource.metal, options: nil)
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = library.makeFunction(name: "crt_vertex")
            desc.fragmentFunction = library.makeFunction(name: "crt_fragment")
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            throw CRTRendererError.pipeline(error.localizedDescription)
        }
        super.init()
    }

    /// False while nothing is open: frames mpv emits after "stop" are ignored.
    var acceptsFrames = false

    /// Drops the current picture (new file or closed media).
    func resetFrame() {
        texture = nil
        statsWindow = StatsWindow()
        needsRedraw = true
    }

    /// Called by the display link once per screen refresh. Pulls the frame that
    /// will be on screen at `targetTime` (the next vsync, not "now", so frames
    /// land on the right refresh) and draws only when the picture changes:
    /// a new video frame, a settings/size change, or the animated noise.
    func displayTick(_ view: MTKView, targetTime: CFTimeInterval) {
        let newFrame = pullFrame()
        // Noise only needs ~30 redraws a second; more just burns GPU and battery.
        let animating = settings.enabled && settings.noise > 0.001 && texture != nil
            && targetTime - lastDrawTime >= 1.0 / 30
        guard newFrame || needsRedraw || animating else { return }
        needsRedraw = false
        lastDrawTime = targetTime
        view.draw()
    }

    // MARK: MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { needsRedraw = true }

    func draw(in view: MTKView) {
        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let buffer = queue.makeCommandBuffer() else { return }
        let scale = view.window?.backingScaleFactor ?? 2
        encode(into: buffer, pass: pass, viewport: view.drawableSize, pixelScale: scale)
        encodeSecondary(into: buffer)
        buffer.present(drawable)
        buffer.addCompletedHandler { [weak self] done in
            let ms = (done.gpuEndTime - done.gpuStartTime) * 1000
            DispatchQueue.main.async { self?.statsWindow.gpu(ms) }
        }
        buffer.commit()
        statsWindow.draw()
        lastDrawableSize = view.drawableSize
    }

    /// Keeps the secondary output fed when the window cannot draw (minimised
    /// or hidden while Picture in Picture is on).
    func offscreenTick() {
        let newFrame = pullFrame()
        let animating = settings.enabled && settings.noise > 0.001 && texture != nil
            && CACurrentMediaTime() - lastDrawTime >= 1.0 / 30
        guard newFrame || animating, let buffer = queue.makeCommandBuffer() else { return }
        lastDrawTime = CACurrentMediaTime()
        encodeSecondary(into: buffer)
        buffer.commit()
    }

    private func encodeSecondary(into buffer: MTLCommandBuffer) {
        guard let output = secondaryOutput, let tex = texture,
              let target = output.nextTarget(aspect: videoSize(for: tex)) else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target.texture
        pass.colorAttachments[0].storeAction = .store
        let size = CGSize(width: target.texture.width, height: target.texture.height)
        encode(into: buffer, pass: pass, viewport: size, pixelScale: 1, source: tex)
        buffer.addCompletedHandler { _ in
            DispatchQueue.main.async { output.frameReady(target) }
        }
    }

    // MARK: Frames

    /// mpv decides when a frame is due (it paces against the audio clock);
    /// we render it at the video's display size, once per due frame.
    private func pullFrame() -> Bool {
        guard acceptsFrames, let bridge, displaySize.width > 0, displaySize.height > 0,
              let tex = bridge.renderIfNeeded(width: Int(displaySize.width), height: Int(displaySize.height))
        else { return false }
        texture = tex
        statsWindow.videoFrame(width: tex.width, height: tex.height)
        return true
    }

    /// Where the picture goes: inside the cabinet when the frame is on (fill
    /// is ignored then, it would push the set off screen), else fit/fill.
    private func screenLayout(for tex: MTLTexture, viewport: CGSize, settings s: CRTSettings) -> (CGRect, CGRect, Bool) {
        let video = videoSize(for: tex)
        if s.enabled && s.frame {
            let layout = CRTUniforms.framedLayout(video: video, viewport: viewport)
            return (layout.glass, layout.content, layout.panels)
        }
        let rect = CRTUniforms.videoRect(video: video, viewport: viewport, fill: fill)
        return (rect, rect, false)
    }

    private func videoSize(for tex: MTLTexture) -> CGSize {
        displaySize.width > 0 ? displaySize : CGSize(width: tex.width, height: tex.height)
    }

    private func encode(into buffer: MTLCommandBuffer, pass: MTLRenderPassDescriptor,
                        viewport: CGSize, pixelScale: CGFloat, source: MTLTexture? = nil,
                        overrideRect: CGRect? = nil, settings override: CRTSettings? = nil) {
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].loadAction = .clear
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        if let tex = source ?? texture {
            let video = videoSize(for: tex)
            let effective = (override ?? settings).adapted(toVideo: video, autoCabinet: autoCabinet)
            let layout = overrideRect.map { ($0, $0, false) } ?? screenLayout(for: tex, viewport: viewport, settings: effective)
            let rect = layout.0
            var uniforms = CRTUniforms(settings: effective, viewport: viewport, videoRect: rect,
                                       contentRect: layout.1, panels: layout.2,
                                       sourceHeight: nativeScanlines ? video.height : nil,
                                       time: CACurrentMediaTime() - startTime, pixelScale: pixelScale)
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentTexture(tex, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<CRTUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        encoder.endEncoding()
    }

    // MARK: Offscreen (snapshots, visual checks, benchmark)

    /// Average GPU milliseconds per frame for `source` drawn at `size`.
    func benchmark(source: MTLTexture, size: CGSize, frames: Int = 120) -> Double {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: Int(size.width),
                                                            height: Int(size.height), mipmapped: false)
        desc.usage = [.renderTarget]
        desc.storageMode = .private
        guard let target = device.makeTexture(descriptor: desc) else { return 0 }
        var total = 0.0
        for frame in 0..<(frames + 10) {
            guard let buffer = queue.makeCommandBuffer() else { return 0 }
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].storeAction = .store
            encode(into: buffer, pass: pass, viewport: size, pixelScale: 2, source: source)
            buffer.commit()
            buffer.waitUntilCompleted()
            if frame >= 10 { total += buffer.gpuEndTime - buffer.gpuStartTime }
        }
        return total / Double(frames) * 1000
    }

    /// Renders `source` (or the current frame) with the CRT effect into a CGImage.
    func renderImage(source: MTLTexture? = nil, size: CGSize? = nil, pixelScale: CGFloat = 2,
                     settings override: CRTSettings? = nil) -> CGImage? {
        guard let tex = source ?? texture else { return nil }
        let target = size ?? videoSize(for: tex)
        let width = Int(target.width.rounded()), height = Int(target.height.rounded())
        guard width > 0, height > 0 else { return nil }

        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width,
                                                            height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .shared
        guard let targetTex = device.makeTexture(descriptor: desc),
              let buffer = queue.makeCommandBuffer() else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = targetTex
        pass.colorAttachments[0].storeAction = .store
        let viewport = CGSize(width: width, height: height)
        encode(into: buffer, pass: pass, viewport: viewport, pixelScale: pixelScale, source: tex,
               overrideRect: nil,
               settings: override)
        buffer.commit()
        buffer.waitUntilCompleted()
        return Self.cgImage(from: targetTex)
    }

    private static func cgImage(from tex: MTLTexture) -> CGImage? {
        let bytesPerRow = tex.width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * tex.height)
        tex.getBytes(&bytes, bytesPerRow: bytesPerRow,
                     from: MTLRegionMake2D(0, 0, tex.width, tex.height), mipmapLevel: 0)
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue
                                | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: tex.width, height: tex.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: bytesPerRow, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }
}
