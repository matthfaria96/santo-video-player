import CoreGraphics
import Foundation
import ImageIO
import Libmpv

/// Small still frames of any file mpv can open, from a second, silent mpv
/// instance on its own thread (scrubber preview, recents, Now Playing art).
final class Thumbnailer: @unchecked Sendable {
    static let shared = Thumbnailer()

    private let queue = DispatchQueue(label: "santo.thumbnailer", qos: .userInitiated)
    private let cache = NSCache<NSString, CGImage>()
    private let latest = NSLock()
    private var latestToken = 0
    // Touched only on `queue`.
    private var handle: OpaquePointer?
    private var renderContext: OpaquePointer?
    private var loadedPath: String?

    private init() { cache.countLimit = 400 }

    /// Frame of `url` near `seconds`, `width` pixels wide. When `coalesce` is
    /// set, an older pending request is skipped once a newer one arrives
    /// (hovering the scrubber fires many).
    func image(for url: URL, at seconds: Double, width: Int = 320, coalesce: Bool = false) async -> CGImage? {
        let key = "\(url.path)#\(Int(seconds.rounded()))#\(width)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let token = coalesce ? nextToken() : 0
        return await withCheckedContinuation { continuation in
            queue.async {
                if coalesce, self.isStale(token) { return continuation.resume(returning: nil) }
                let image = self.capture(url: url, seconds: seconds, width: width)
                if let image { self.cache.setObject(image, forKey: key) }
                continuation.resume(returning: image)
            }
        }
    }

    private func nextToken() -> Int {
        latest.lock(); defer { latest.unlock() }
        latestToken += 1
        return latestToken
    }

    private func isStale(_ token: Int) -> Bool {
        latest.lock(); defer { latest.unlock() }
        return token != latestToken
    }

    // MARK: mpv (queue only)

    private func ensureMPV() -> Bool {
        if handle != nil { return renderContext != nil }
        guard let handle = mpv_create() else { return false }
        let options = ["vo": "libmpv", "ao": "null", "aid": "no", "sid": "no", "pause": "yes", "idle": "yes",
                       "keep-open": "always", "hr-seek": "no", "hwdec": "auto-safe", "terminal": "no",
                       "ytdl": "no", "load-scripts": "no", "sub-auto": "no", "audio-file-auto": "no",
                       "vd-lavc-skiploopfilter": "all", "vd-lavc-fast": "yes", "demuxer-max-bytes": "8MiB"]
        for (key, value) in options { mpv_set_option_string(handle, key, value) }
        guard mpv_initialize(handle) >= 0 else { mpv_terminate_destroy(handle); return false }
        self.handle = handle
        let apiType = UnsafeMutableRawPointer(mutating: (MPV_RENDER_API_TYPE_SW as NSString).utf8String)
        var params = [
            mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: apiType),
            mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
        ]
        var context: OpaquePointer?
        guard mpv_render_context_create(&context, handle, &params) >= 0 else { return false }
        renderContext = context
        return true
    }

    private func command(_ args: [String]) {
        guard let handle else { return }
        var cStrings: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) } + [nil]
        defer { cStrings.forEach { free($0) } }
        cStrings.withUnsafeMutableBufferPointer { buffer in
            buffer.baseAddress!.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buffer.count) {
                _ = mpv_command(handle, $0)
            }
        }
    }

    /// Waits up to `timeout` for `event`; false on timeout or a failed load.
    private func wait(for event: mpv_event_id, timeout: Double) -> Bool {
        guard let handle else { return false }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            guard let e = mpv_wait_event(handle, 0.05) else { continue }
            if e.pointee.event_id == event { return true }
            // "replace" first ends the previous file (reason STOP); only an error is a failed load.
            if e.pointee.event_id == MPV_EVENT_END_FILE, event == MPV_EVENT_FILE_LOADED,
               e.pointee.data?.assumingMemoryBound(to: mpv_event_end_file.self).pointee.reason == MPV_END_FILE_REASON_ERROR {
                return false
            }
        }
        return false
    }

    private func capture(url: URL, seconds: Double, width: Int) -> CGImage? {
        guard ensureMPV(), let handle, let renderContext else { return nil }
        if loadedPath != url.path {
            loadedPath = nil
            while let e = mpv_wait_event(handle, 0), e.pointee.event_id != MPV_EVENT_NONE {}
            command(["loadfile", url.path, "replace"])
            guard wait(for: MPV_EVENT_FILE_LOADED, timeout: 6) else { return nil }
            loadedPath = url.path
        }
        while mpv_render_context_update(renderContext) & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) != 0 {
            renderFrame(width: 8, height: 8)   // drain a stale frame from the previous seek
        }
        command(["seek", String(max(seconds, 0)), "absolute+keyframes"])

        var w: Int64 = 0, h: Int64 = 0
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline {
            _ = mpv_wait_event(handle, 0.02)
            guard mpv_render_context_update(renderContext) & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) != 0 else { continue }
            mpv_get_property(handle, "dwidth", MPV_FORMAT_INT64, &w)
            mpv_get_property(handle, "dheight", MPV_FORMAT_INT64, &h)
            guard w > 0, h > 0 else { return nil }
            let height = max(2, Int((Double(width) * Double(h) / Double(w)).rounded()) & ~1)
            return renderFrame(width: width, height: height)
        }
        return nil
    }

    @discardableResult
    private func renderFrame(width: Int, height: Int) -> CGImage? {
        guard let renderContext else { return nil }
        let stride = width * 4
        var pixels = [UInt8](repeating: 0, count: stride * height)
        var size: [Int32] = [Int32(width), Int32(height)]
        var strideValue = stride
        let format = UnsafeMutableRawPointer(mutating: ("bgr0" as NSString).utf8String)
        let status: Int32 = pixels.withUnsafeMutableBytes { buffer in
            size.withUnsafeMutableBytes { sizePointer in
                withUnsafeMutablePointer(to: &strideValue) { stridePointer in
                    var params = [
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_SIZE, data: sizePointer.baseAddress),
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_FORMAT, data: format),
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_STRIDE, data: UnsafeMutableRawPointer(stridePointer)),
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_POINTER, data: buffer.baseAddress),
                        mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
                    ]
                    return mpv_render_context_render(renderContext, &params)
                }
            }
        }
        guard status >= 0, let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: stride,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info, provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// JPEG covers for the recents shelf, in ~/Library/Caches.
enum ArtworkCache {
    static var folder: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("com.witchmymac.santovideoplayer/artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func url(for media: URL) -> URL {
        folder.appendingPathComponent(LibraryStore.cacheKey(for: media) + ".jpg")
    }

    static func save(_ image: CGImage, for media: URL) {
        guard let destination = CGImageDestinationCreateWithURL(url(for: media) as CFURL, "public.jpeg" as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        CGImageDestinationFinalize(destination)
    }
}
