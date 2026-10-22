import Foundation
import CoreVideo
import IOSurface
import Libmpv
import Metal
import OpenGL.GL3
import os

enum MPVBridgeError: LocalizedError {
    case openGL
    case renderContext(Int32)

    var errorDescription: String? {
        switch self {
        case .openGL: return String(localized: "OpenGL indisponível para o mpv.")
        case .renderContext(let code):
            return String(localized: "Falha no render do mpv (\(String(cString: mpv_error_string(code)))).")
        }
    }
}

/// mpv renders each frame with OpenGL into an IOSurface; Metal reads the same
/// IOSurface as a texture (no copy), so the CRT pass stays in Metal.
final class MPVVideoBridge {
    private struct Target {
        let surface: IOSurfaceRef
        let glTexture: GLuint
        let framebuffer: GLuint
        let metal: MTLTexture
        let width: Int
        let height: Int
    }

    private let device: MTLDevice
    private let cgl: CGLContextObj
    private var renderContext: OpaquePointer?
    /// Three surfaces: mpv writes one while Metal may still sample the others.
    private var targets: [Target] = []
    private var nextTarget = 0
    private let pending = OSAllocatedUnfairLock(initialState: false)

    init(client: MPVClient, device: MTLDevice) throws {
        self.device = device
        let attributes: [CGLPixelFormatAttribute] = [
            kCGLPFAOpenGLProfile, CGLPixelFormatAttribute(UInt32(kCGLOGLPVersion_3_2_Core.rawValue)),
            kCGLPFAAccelerated, kCGLPFAAllowOfflineRenderers, CGLPixelFormatAttribute(0),
        ]
        var pixelFormat: CGLPixelFormatObj?
        var count: GLint = 0
        CGLChoosePixelFormat(attributes, &pixelFormat, &count)
        var context: CGLContextObj?
        guard let pixelFormat, CGLCreateContext(pixelFormat, nil, &context) == kCGLNoError, let context else {
            throw MPVBridgeError.openGL
        }
        CGLDestroyPixelFormat(pixelFormat)
        cgl = context
        CGLSetCurrentContext(cgl)

        var initParams = mpv_opengl_init_params(get_proc_address: { _, name in
            guard let name else { return nil }
            let symbol = CFStringCreateWithCString(kCFAllocatorDefault, name, CFStringBuiltInEncodings.ASCII.rawValue)
            let bundle = CFBundleGetBundleWithIdentifier("com.apple.opengl" as CFString)
            return CFBundleGetFunctionPointerForName(bundle, symbol)
        }, get_proc_address_ctx: nil)
        let apiType = UnsafeMutableRawPointer(mutating: (MPV_RENDER_API_TYPE_OPENGL as NSString).utf8String)
        var renderContext: OpaquePointer?
        let status = withUnsafeMutablePointer(to: &initParams) { initPointer in
            var params = [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: apiType),
                mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: UnsafeMutableRawPointer(initPointer)),
                mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
            ]
            return mpv_render_context_create(&renderContext, client.handle, &params)
        }
        guard status >= 0, let renderContext else {
            CGLSetCurrentContext(nil)
            CGLDestroyContext(context)
            throw MPVBridgeError.renderContext(status)
        }
        self.renderContext = renderContext
        mpv_render_context_set_update_callback(renderContext, { context in
            guard let context else { return }
            let bridge = Unmanaged<MPVVideoBridge>.fromOpaque(context).takeUnretainedValue()
            bridge.pending.withLock { $0 = true }
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    deinit { shutdown() }

    /// Must run before the mpv handle is destroyed.
    func shutdown() {
        guard let renderContext else { return }
        CGLSetCurrentContext(cgl)
        mpv_render_context_set_update_callback(renderContext, nil, nil)
        mpv_render_context_free(renderContext)
        self.renderContext = nil
        releaseTargets()
        CGLSetCurrentContext(nil)
        CGLDestroyContext(cgl)
    }

    /// Renders mpv's next frame at `width`×`height` if one is due; returns its texture.
    func renderIfNeeded(width: Int, height: Int) -> MTLTexture? {
        guard let renderContext, width > 0, height > 0 else { return nil }
        let due = pending.withLock { flag -> Bool in
            defer { flag = false }
            return flag
        }
        guard due else { return nil }
        let flags = mpv_render_context_update(renderContext)
        guard flags & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) != 0 else { return nil }

        CGLSetCurrentContext(cgl)
        if targets.first.map({ $0.width != width || $0.height != height }) ?? true {
            releaseTargets()
            targets = (0..<3).compactMap { _ in makeTarget(width: width, height: height) }
        }
        guard !targets.isEmpty else { return nil }
        let target = targets[nextTarget % targets.count]
        nextTarget += 1

        var fbo = mpv_opengl_fbo(fbo: Int32(target.framebuffer), w: Int32(width), h: Int32(height), internal_format: 0)
        // The FBO already stores rows top-down for Metal; flipping turns the picture over.
        var flip: Int32 = 0
        withUnsafeMutablePointer(to: &fbo) { fboPointer in
            withUnsafeMutablePointer(to: &flip) { flipPointer in
                var params = [
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: UnsafeMutableRawPointer(fboPointer)),
                    mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: UnsafeMutableRawPointer(flipPointer)),
                    mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
                ]
                _ = mpv_render_context_render(renderContext, &params)
            }
        }
        // Metal samples this surface right after; wait until the GPU finished it.
        if let fence = glFenceSync(GLenum(GL_SYNC_GPU_COMMANDS_COMPLETE), 0) {
            glClientWaitSync(fence, GLbitfield(GL_SYNC_FLUSH_COMMANDS_BIT), 100_000_000)
            glDeleteSync(fence)
        }
        return target.metal
    }

    private func makeTarget(width: Int, height: Int) -> Target? {
        let properties: [IOSurfacePropertyKey: Any] = [
            .width: width, .height: height, .bytesPerElement: 4,
            .pixelFormat: kCVPixelFormatType_32BGRA,
        ]
        guard let surface = IOSurfaceCreate(properties as CFDictionary) else { return nil }
        var texture: GLuint = 0
        glGenTextures(1, &texture)
        glBindTexture(GLenum(GL_TEXTURE_RECTANGLE), texture)
        CGLTexImageIOSurface2D(cgl, GLenum(GL_TEXTURE_RECTANGLE), GLenum(GL_RGBA), GLsizei(width), GLsizei(height),
                               GLenum(GL_BGRA), GLenum(GL_UNSIGNED_INT_8_8_8_8_REV), surface, 0)
        var framebuffer: GLuint = 0
        glGenFramebuffers(1, &framebuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)
        glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0),
                               GLenum(GL_TEXTURE_RECTANGLE), texture, 0)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)

        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width,
                                                            height: height, mipmapped: false)
        desc.usage = [.shaderRead]
        guard let metal = device.makeTexture(descriptor: desc, iosurface: surface, plane: 0) else {
            glDeleteFramebuffers(1, &framebuffer)
            glDeleteTextures(1, &texture)
            return nil
        }
        return Target(surface: surface, glTexture: texture, framebuffer: framebuffer, metal: metal,
                      width: width, height: height)
    }

    private func releaseTargets() {
        for target in targets {
            var fbo = target.framebuffer, tex = target.glTexture
            glDeleteFramebuffers(1, &fbo)
            glDeleteTextures(1, &tex)
        }
        targets = []
    }
}
