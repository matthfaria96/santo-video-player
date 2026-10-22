import MetalKit
import SwiftUI

struct VideoMetalView: NSViewRepresentable {
    let renderer: CRTRenderer

    func makeNSView(context: Context) -> VideoView {
        let view = VideoView(frame: .zero, device: renderer.device)
        view.renderer = renderer
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.framebufferOnly = true
        // Drawing is driven by our own display link (see VideoView), not MTKView's timer.
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.delegate = renderer
        return view
    }

    func updateNSView(_ nsView: VideoView, context: Context) {}
}

/// MTKView paced by the screen's display link, so each video frame is shown on
/// the refresh it belongs to, and nothing is drawn when nothing changed.
final class VideoView: MTKView {
    weak var renderer: CRTRenderer?
    private var link: CADisplayLink?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        link?.invalidate()
        link = nil
        guard window != nil else { return }
        let link = displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func step(_ link: CADisplayLink) {
        renderer?.displayTick(self, targetTime: link.targetTimestamp)
    }

    deinit { link?.invalidate() }
}

/// Transparent strip that drags the window (the title bar is hidden).
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 { window?.zoom(nil) } else { window?.performDrag(with: event) }
        }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Hosts the PiP sample-buffer layer behind the Metal view (AVKit needs it in
/// the window to float it) and tells PiP which window to restore.
struct PiPHostView: NSViewRepresentable {
    let pip: PictureInPicture

    final class HostView: NSView {
        weak var pip: PictureInPicture?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            MainActor.assumeIsolated { pip?.window = window }
        }

        override func layout() {
            super.layout()
            layer?.sublayers?.forEach { $0.frame = bounds }
        }
    }

    func makeNSView(context: Context) -> HostView {
        let view = HostView()
        view.wantsLayer = true
        view.pip = pip
        view.layer?.addSublayer(pip.displayLayer)
        return view
    }

    func updateNSView(_ nsView: HostView, context: Context) {}
}
