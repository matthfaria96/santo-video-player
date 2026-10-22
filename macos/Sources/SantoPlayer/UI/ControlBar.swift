import SwiftUI

struct ControlBar: View {
    @Bindable var model: PlayerModel
    let pip: PictureInPicture
    @Binding var panel: SidePanel?
    /// Classic layout: full-width bar fixed under the video instead of a floating card.
    var docked = false

    var body: some View {
        VStack(spacing: 6) {
            Scrubber(model: model)
            HStack(spacing: 4) {
                transport
                VolumeControl(model: model).padding(.leading, 6)
                Text("\(Formatting.time(model.currentTime))  /  \(Formatting.time(model.duration))")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.leading, 10)
                    .fixedSize()
                Spacer(minLength: 8)
                SpeedMenu(model: model)
                AudioMenu(model: model)
                SubtitleMenu(model: model)
                Button { model.cycleLoop() } label: {
                    Image(systemName: model.loopMode.symbol)
                        .foregroundStyle(model.loopMode == .off ? Color.white : Color.phosphor)
                }
                .buttonStyle(IconButtonStyle()).help(model.loopMode.label).accessibilityLabel(model.loopMode.label)
                panelButton(.effects, symbol: "tv", help: String(localized: "Efeitos CRT (⌘E)"))
                    .keyboardShortcut("e", modifiers: .command)
                panelButton(.playlist, symbol: "list.bullet", help: String(localized: "Playlist"))
                Button { pip.toggle() } label: {
                    Image(systemName: pip.isActive ? "pip.exit" : "pip.enter")
                        .foregroundStyle(pip.isActive ? Color.phosphor : Color.white)
                }
                .buttonStyle(IconButtonStyle()).help("Picture in Picture (⌥⌘P)").accessibilityLabel("Picture in Picture")
                .disabled(!model.hasMedia || model.isAudioOnly)
                Button { NSApp.keyWindow?.toggleFullScreen(nil) } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(IconButtonStyle()).help("Tela cheia (F)").accessibilityLabel("Tela cheia")
            }
        }
        .padding(.horizontal, docked ? 16 : 14)
        .padding(.vertical, 10)
        .modifier(BarBackground(docked: docked))
    }

    private var skip: Double { AppSettings.shared.skipInterval }

    private var transport: some View {
        HStack(spacing: 2) {
            Button { model.previous() } label: { Image(systemName: "backward.fill") }
                .buttonStyle(IconButtonStyle()).help("Anterior (⌘←)").accessibilityLabel("Anterior")
            Button { model.skip(-skip) } label: { Image(systemName: "gobackward.\(Int(skip))") }
                .buttonStyle(IconButtonStyle()).help("Voltar (←)").accessibilityLabel("Voltar")
            Button { model.hasMedia ? model.togglePlay() : FilePanels.openMedia(model) } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(IconButtonStyle(size: 40, prominent: true)).help("Reproduzir/Pausar (espaço)").accessibilityLabel("Reproduzir / Pausar")
            Button { model.skip(skip) } label: { Image(systemName: "goforward.\(Int(skip))") }
                .buttonStyle(IconButtonStyle()).help("Avançar (→)").accessibilityLabel("Avançar")
            Button { model.next() } label: { Image(systemName: "forward.fill") }
                .buttonStyle(IconButtonStyle()).help("Próximo (⌘→)").accessibilityLabel("Próximo")
        }
    }

    private func panelButton(_ kind: SidePanel, symbol: String, help: String) -> some View {
        Button {
            withAnimation(.snappy) { panel = panel == kind ? nil : kind }
        } label: {
            Image(systemName: symbol).foregroundStyle(panel == kind ? Color.phosphor : Color.white)
        }
        .buttonStyle(IconButtonStyle())
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Floating glass card (modern) or a solid strip with a hairline on top (classic).
private struct BarBackground: ViewModifier {
    let docked: Bool

    func body(content: Content) -> some View {
        if docked {
            content
                .frame(maxWidth: .infinity)
                .background(Color(white: 0.085))
                .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
        } else {
            content
                .compatGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .frame(maxWidth: 980)
        }
    }
}

private struct VolumeControl: View {
    @Bindable var model: PlayerModel

    var body: some View {
        HStack(spacing: 2) {
            Button { model.isMuted.toggle() } label: {
                Image(systemName: model.volumeSymbol).contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(IconButtonStyle()).help("Silenciar (M)").accessibilityLabel("Silenciar / Ativar som")
            MiniSlider(value: Binding(get: { Double(model.isMuted ? 0 : model.volume) },
                                      set: { model.volume = Float($0); model.isMuted = false }))
                .frame(width: 86)
        }
    }
}

private struct SpeedMenu: View {
    let model: PlayerModel

    var body: some View {
        Menu {
            ForEach(PlayerModel.rates, id: \.self) { rate in
                Button { model.setRate(rate) } label: {
                    if rate == model.rate { Label(Formatting.rate(rate), systemImage: "checkmark") } else { Text(Formatting.rate(rate)) }
                }
            }
        } label: {
            Text(Formatting.rate(model.rate))
                .font(.system(size: 12, weight: .bold).monospacedDigit())
                .foregroundStyle(model.rate == 1 ? Color.white : Color.black)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(Capsule().fill(model.rate == 1 ? Color.white.opacity(0.14) : Color.phosphor))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Velocidade ([ e ])")
    }
}

private struct SubtitleMenu: View {
    @Bindable var model: PlayerModel

    var body: some View {
        let subs = model.subtitles
        Menu {
            Button { subs.select(nil) } label: { checked(String(localized: "Desligada"), subs.selectedID == nil) }
            if !subs.tracks.isEmpty { Divider() }
            ForEach(subs.tracks) { track in
                Button { subs.select(track.id) } label: { checked(track.displayName, subs.selectedID == track.id) }
            }
            Divider()
            Button("Carregar legenda…") { FilePanels.openSubtitle(model) }
            Toggle("Dentro da tela (estilo original, com efeito CRT)", isOn: Binding(
                get: { subs.insideScreen }, set: { subs.insideScreen = $0 }))
            Menu("Tamanho do texto") {
                ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { scale in
                    Button { subs.fontScale = scale } label: {
                        checked("\(Int(scale * 100))%", abs(subs.fontScale - scale) < 0.01)
                    }
                }
            }
            .disabled(subs.insideScreen)
            Toggle("Fundo escuro", isOn: Binding(get: { subs.showBackground }, set: { subs.showBackground = $0 }))
                .disabled(subs.insideScreen)
            Divider()
            Text(String(localized: "Atraso: \(String(format: "%+.1f", subs.delay)) s  (G / H)"))
            Button("Zerar atraso") { subs.resetDelay() }.disabled(subs.delay == 0)
        } label: {
            Image(systemName: subs.selectedID == nil ? "captions.bubble" : "captions.bubble.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(subs.selectedID == nil ? Color.white : Color.phosphor)
                .frame(width: 32, height: 32)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Legendas (V)").accessibilityLabel("Legendas")
    }
}

struct AudioMenu: View {
    let model: PlayerModel

    var body: some View {
        Menu {
            if model.audioTracks.isEmpty { Text("Sem faixas de áudio") }
            ForEach(model.audioTracks) { track in
                Button { model.selectAudio(track.id) } label: { checked(track.displayName, model.audioID == track.id) }
            }
        } label: {
            Image(systemName: "waveform")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(model.audioTracks.count > 1 ? Color.phosphor : Color.white)
                .frame(width: 32, height: 32)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Faixa de áudio (B)").accessibilityLabel("Faixa de áudio")
        .disabled(model.audioTracks.count < 2)
        .opacity(model.audioTracks.count < 2 ? 0.45 : 1)
    }
}

@ViewBuilder
private func checked(_ title: String, _ on: Bool) -> some View {
    if on { Label(title, systemImage: "checkmark") } else { Text(title) }
}
