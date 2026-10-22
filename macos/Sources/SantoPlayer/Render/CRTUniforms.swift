import CoreGraphics
import simd

/// Mirrors `struct Uniforms` in CRTShaderSource (same order and padding).
struct CRTUniforms {
    var viewport: SIMD2<Float>
    var rectOrigin: SIMD2<Float>
    var rectSize: SIMD2<Float>
    var contentOrigin: SIMD2<Float>
    var contentSize: SIMD2<Float>
    var time: Float
    var enabled: Float
    var scanlines: Float
    var mask: Float
    var maskType: Float
    var curvature: Float
    var glow: Float
    var vignette: Float
    var noise: Float
    var brightness: Float
    var tube: Float
    var lines: Float
    var pixelScale: Float
    var frame: Float

    /// `videoRect` is the glass; `contentRect` the picture inside it (defaults to the same).
    /// `sourceHeight` (the video's own line count) enables native scanlines.
    init(settings s: CRTSettings, viewport: CGSize, videoRect: CGRect, contentRect: CGRect? = nil,
         panels: Bool = false, sourceHeight: CGFloat? = nil, time: Double, pixelScale: CGFloat) {
        self.viewport = SIMD2(Float(viewport.width), Float(viewport.height))
        rectOrigin = SIMD2(Float(videoRect.minX), Float(videoRect.minY))
        rectSize = SIMD2(Float(max(videoRect.width, 1)), Float(max(videoRect.height, 1)))
        let content = contentRect ?? videoRect
        contentOrigin = SIMD2(Float(content.minX), Float(content.minY))
        contentSize = SIMD2(Float(max(content.width, 1)), Float(max(content.height, 1)))
        self.time = Float(time.truncatingRemainder(dividingBy: 3600))
        enabled = s.enabled ? 1 : 0
        scanlines = s.scanlines
        mask = s.mask
        maskType = Float(s.maskType.rawValue)
        curvature = s.curvature
        glow = s.glow
        vignette = s.vignette
        noise = s.noise
        brightness = s.brightness
        tube = s.tube ? 1 : 0
        lines = Self.scanlineCount(rectHeightPixels: videoRect.height, pixelScale: pixelScale)
        if let sourceHeight, let native = Self.nativeScanlineCount(sourceHeight: sourceHeight,
                                                                   contentHeightPixels: content.height,
                                                                   glassHeightPixels: videoRect.height) {
            lines = native
        }
        self.pixelScale = Float(max(pixelScale, 1))
        frame = s.frame ? (panels ? 2 : 1) : 0
    }

    /// About one beam line per 2 points, but never under 3 device pixels per
    /// line: a 2-pixel period aliases into moiré rings once the tube bends it.
    static func scanlineCount(rectHeightPixels: CGFloat, pixelScale: CGFloat) -> Float {
        let scale = max(pixelScale, 1)
        let pixelsPerLine = max(3, 2 * scale)
        return Float(min(max(rectHeightPixels / pixelsPerLine, 120), 540))
    }

    /// Glass (tube) and picture inside the "TV com Gabinete".
    /// - 4:3-ish video with room to spare: the glass is the picture and the
    ///   side panels become the cabinet (`panels`).
    /// - Otherwise the glass hugs the picture, so the bezel always ends right
    ///   at the picture's edges; a small mismatch just makes the lacquer a few
    ///   pixels thicker. Only a big mismatch (a 2.35:1 film) keeps a larger
    ///   tube with black screen inside it, as a real set would.
    static func framedLayout(video: CGSize, viewport: CGSize) -> (glass: CGRect, content: CGRect, panels: Bool) {
        let t = min(viewport.width, viewport.height) * 0.025
        let inner = CGRect(x: t, y: t, width: viewport.width - 2 * t, height: viewport.height - 2.4 * t)
        let fit = videoRect(video: video, viewport: inner.size, fill: false).offsetBy(dx: inner.minX, dy: inner.minY)
        let squarish = video.height > 0 && video.width / video.height < 1.55   // 4:3, 5:4, 3:2
        if squarish && fit.minX > viewport.width * 0.07 { return (fit, fit, true) }
        let gapX = (inner.width - fit.width) / max(inner.width, 1)
        let gapY = (inner.height - fit.height) / max(inner.height, 1)
        if max(gapX, gapY) < 0.12 { return (fit, fit, false) }
        return (inner, fit, false)
    }

    /// Scanlines that match the video's own lines, like a real set: an SD
    /// picture (≤ 576 lines) shows one beam line per video line, or one per
    /// field (half) when the screen is too small to draw them 3 px apart.
    /// HD sources return nil and keep the window-based density.
    /// Counted over the glass, which can be taller than a letterboxed picture.
    static func nativeScanlineCount(sourceHeight: CGFloat, contentHeightPixels: CGFloat,
                                    glassHeightPixels: CGFloat) -> Float? {
        guard sourceHeight >= 144, sourceHeight <= 576, contentHeightPixels > 0 else { return nil }
        var perPicture = sourceHeight
        if contentHeightPixels / perPicture < 3 { perPicture /= 2 }
        if contentHeightPixels / perPicture < 3 { return nil }
        return Float(perPicture * glassHeightPixels / contentHeightPixels)
    }

    /// Aspect-fit (or aspect-fill) rectangle of the video inside the viewport.
    static func videoRect(video: CGSize, viewport: CGSize, fill: Bool) -> CGRect {
        guard video.width > 0, video.height > 0 else { return CGRect(origin: .zero, size: viewport) }
        let sx = viewport.width / video.width
        let sy = viewport.height / video.height
        let scale = fill ? max(sx, sy) : min(sx, sy)
        let size = CGSize(width: video.width * scale, height: video.height * scale)
        return CGRect(x: (viewport.width - size.width) / 2, y: (viewport.height - size.height) / 2,
                      width: size.width, height: size.height)
    }
}
