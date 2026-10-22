import SwiftUI

enum SidePanel { case effects, playlist }

struct ContentView: View {
    @Bindable var model: PlayerModel
    let pip: PictureInPicture
    private let settings = AppSettings.shared
    @State private var controlsVisible = true
    @State private var lastActivity = Date()
    @State private var hoveringControls = false
    @State private var panel: SidePanel?
    @State private var dropTargeted = false
    @State private var isFullScreen = false

    private var layout: PlayerLayout { settings.layout }
    /// Classic docks its title strip and bar only in a window; full screen is
    /// all picture, with the modern floating controls that hide on their own.
    private var classic: Bool { layout == .classic && !isFullScreen }

    var body: some View {
        VStack(spacing: 0) {
            if classic { ClassicTitleBar(title: model.hasMedia ? model.title : "Santo Video Player") }
            stage
            if classic {
                ControlBar(model: model, pip: pip, panel: $panel, docked: true)
                    .disabled(!model.hasMedia)
                    .opacity(model.hasMedia ? 1 : 0.55)
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .onContinuousHover { _ in registerActivity() }
        .dropDestination(for: URL.self) { urls, _ in
            model.open(urls)
            return !urls.isEmpty
        } isTargeted: { dropTargeted = $0 }
        .onChange(of: model.isPlaying) { _, playing in if !playing { reveal() } }
        .onChange(of: layout) { _, _ in reveal() }
        // The panels belong to a playing video; the home screen can't close them (no bar).
        .onChange(of: model.hasMedia) { _, has in if !has { panel = nil } }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willEnterFullScreenNotification)) { _ in
            isFullScreen = true
            reveal()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willExitFullScreenNotification)) { _ in
            isFullScreen = false
            reveal()
        }
        .task { await autoHideLoop() }
        .navigationTitle(model.title)
        .animation(.easeInOut(duration: 0.25), value: layout)
    }

    /// Everything drawn over the picture.
    private var stage: some View {
        ZStack {
            Color.black
            PiPHostView(pip: pip)
            if let renderer = model.renderer {
                VideoMetalView(renderer: renderer)
                    .opacity(pip.isActive ? 0 : 1)
            } else {
                Text("Metal indisponível: o efeito CRT não pode ser exibido.").foregroundStyle(.secondary)
            }
            if model.isAudioOnly { AudioOnlyView(title: model.title) }
            clickCatcher
            if !model.hasMedia { HomeView(model: model) }
            if !pip.isActive {
                SubtitleOverlay(subtitles: model.subtitles, bottomInset: subtitleInset)
            }
            OSDView(message: model.osd, topInset: classic ? 16 : 58)
            if model.showStats, model.hasMedia, let renderer = model.renderer {
                StatsOverlay(renderer: renderer, dropped: { model.droppedFrames }, decoder: { model.decoderInfo })
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, classic ? 14 : 56).padding(.leading, 18)
            }
            if classic { classicPanels } else { modernChrome }
            if dropTargeted { DropHighlight() }
        }
        .clipped()
    }

    private var subtitleInset: CGFloat {
        if classic { return 28 }
        return controlsVisible ? 128 : 44
    }

    private var clickCatcher: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { NSApp.keyWindow?.toggleFullScreen(nil) }
            .onTapGesture {
                if panel != nil { withAnimation(.snappy) { panel = nil } } else { model.togglePlay() }
            }
    }

    // MARK: Modern: floating chrome over the video

    private var modernChrome: some View {
        ZStack {
            VStack(spacing: 0) {
                TopBar(title: model.hasMedia ? model.title : "")
                Spacer(minLength: 0)
                ControlBar(model: model, pip: pip, panel: $panel)
                    .onHover { hoveringControls = $0 }
                    .opacity(model.hasMedia ? 1 : 0)
                    .allowsHitTesting(model.hasMedia)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 16)
            }
            .opacity(controlsVisible ? 1 : 0)
            .allowsHitTesting(controlsVisible)

            sidePanelColumn
                .padding(.top, 52)
                .padding(.bottom, 128)
        }
        .animation(.easeInOut(duration: 0.3), value: controlsVisible)
    }

    // MARK: Classic: only the side panels sit over the video

    private var classicPanels: some View {
        sidePanelColumn.padding(.vertical, 14)
    }

    private var sidePanelColumn: some View {
        HStack {
            Spacer()
            sidePanel
        }
        .padding(.trailing, 18)
    }

    @ViewBuilder
    private var sidePanel: some View {
        switch panel {
        case .effects?:
            EffectsPanel(model: model).transition(.move(edge: .trailing).combined(with: .opacity))
        case .playlist?:
            PlaylistPanel(model: model).transition(.move(edge: .trailing).combined(with: .opacity))
        case nil:
            EmptyView()
        }
    }

    // MARK: Auto-hide (modern only)

    private func registerActivity() {
        lastActivity = Date()
        reveal()
    }

    private func reveal() {
        if !controlsVisible { controlsVisible = true }
    }

    private func autoHideLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(400))
            let idle = Date().timeIntervalSince(lastActivity) > 2.5
            if !classic, idle, controlsVisible, model.isPlaying, panel == nil, !hoveringControls {
                controlsVisible = false
                NSCursor.setHiddenUntilMouseMoves(true)
            }
        }
    }
}

private struct TopBar: View {
    let title: String

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom)
            WindowDragArea()
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .padding(.horizontal, 90)
                .allowsHitTesting(false)
        }
        .frame(height: 52)
    }
}

/// Classic layout: a solid title strip above the video (holds the traffic lights).
private struct ClassicTitleBar: View {
    let title: String

    var body: some View {
        ZStack {
            Color(white: 0.085)
            WindowDragArea()
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .padding(.horizontal, 90)
                .allowsHitTesting(false)
        }
        .frame(height: 34)
        .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
    }
}

private struct DropHighlight: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 18)
            .strokeBorder(Color.phosphor, style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
            .background(Color.phosphor.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
            .padding(14)
            .allowsHitTesting(false)
    }
}
