import SwiftUI

/// Menu titles are fixed: SwiftUI does not re-evaluate Commands when the
/// observed model changes, so state-dependent titles would go stale.
struct PlayerCommands: Commands {
    let model: PlayerModel
    let pip: PictureInPicture
    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("Sobre o Santo Video Player") {
                AppSettings.shared.tab = .about
                openSettings()
            }
        }
        CommandGroup(replacing: .newItem) {
            Button("Abrir…") { FilePanels.openMedia(model) }.keyboardShortcut("o")
            Button("Abrir URL…") { FilePanels.openURL(model) }.keyboardShortcut("u")
            Button("Adicionar à playlist…") { FilePanels.enqueueMedia(model) }.keyboardShortcut("o", modifiers: [.command, .option])
            Button("Carregar legenda…") { FilePanels.openSubtitle(model) }.keyboardShortcut("o", modifiers: [.command, .shift])
            Button("Fechar vídeo") { model.closeMedia() }.keyboardShortcut("w", modifiers: [.command, .option])
            Divider()
            Button("Salvar captura") { model.snapshot() }.keyboardShortcut("s", modifiers: [.command, .shift])
        }
        CommandMenu("Reprodução") {
            Button("Reproduzir / Pausar") { model.togglePlay() }.keyboardShortcut(.space, modifiers: [])
            Divider()
            Button("Voltar") { model.skip(-AppSettings.shared.skipInterval) }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("Avançar") { model.skip(AppSettings.shared.skipInterval) }.keyboardShortcut(.rightArrow, modifiers: [])
            Button("Voltar 1 min") { model.skip(-60) }.keyboardShortcut(.leftArrow, modifiers: [.shift])
            Button("Avançar 1 min") { model.skip(60) }.keyboardShortcut(.rightArrow, modifiers: [.shift])
            Button("Quadro anterior") { model.step(frames: -1) }.keyboardShortcut(",", modifiers: [])
            Button("Próximo quadro") { model.step(frames: 1) }.keyboardShortcut(".", modifiers: [])
            Divider()
            Button("Voltar ao início") { model.restartFromBeginning() }.keyboardShortcut(.leftArrow, modifiers: [.command, .shift])
            Button("Anterior") { model.previous() }.keyboardShortcut(.leftArrow, modifiers: [.command])
            Button("Próximo") { model.next() }.keyboardShortcut(.rightArrow, modifiers: [.command])
            Button("Alternar repetição") { model.cycleLoop() }.keyboardShortcut("l", modifiers: [])
            Divider()
            Menu("Velocidade") {
                ForEach(PlayerModel.rates, id: \.self) { rate in
                    Toggle(Formatting.rate(rate), isOn: Binding(get: { model.rate == rate }, set: { _ in model.setRate(rate) }))
                }
            }
            Button("Mais rápido") { model.faster() }.keyboardShortcut("]", modifiers: [])
            Button("Mais devagar") { model.slower() }.keyboardShortcut("[", modifiers: [])
            Button("Velocidade normal") { model.setRate(1) }.keyboardShortcut("=", modifiers: [])
            Divider()
            Button("Aumentar volume") { model.nudgeVolume(0.05) }.keyboardShortcut(.upArrow, modifiers: [])
            Button("Diminuir volume") { model.nudgeVolume(-0.05) }.keyboardShortcut(.downArrow, modifiers: [])
            Button("Silenciar / Ativar som") { model.isMuted.toggle() }.keyboardShortcut("m", modifiers: [])
        }
        CommandMenu("Vídeo") {
            Button("Tela cheia") { NSApp.keyWindow?.toggleFullScreen(nil) }.keyboardShortcut("f", modifiers: [])
            Button("Picture in Picture") { pip.toggle() }.keyboardShortcut("p", modifiers: [.command, .option])
            Button("Preencher / Ajustar à tela") { model.toggleFill() }.keyboardShortcut("a", modifiers: [])
            Button("Diagnóstico de desempenho") { model.showStats.toggle() }.keyboardShortcut("i", modifiers: [.command, .option])
            Divider()
            Text("Efeitos CRT")
            ForEach(Array(CRTPreset.allCases.enumerated()), id: \.element) { index, preset in
                Toggle(preset.name, isOn: Binding(get: { model.crtPreset == preset && !model.crtEdited }, set: { _ in model.apply(preset) }))
                    .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: [.command])
            }
        }
        CommandMenu("Áudio") {
            Button("Alternar faixa de áudio") { model.cycleAudio() }.keyboardShortcut("b", modifiers: [])
        }
        CommandMenu("Legendas") {
            Button("Alternar legenda") { model.cycleSubtitles() }.keyboardShortcut("v", modifiers: [])
            Button("Carregar legenda…") { FilePanels.openSubtitle(model) }
            Divider()
            Button("Atrasar legenda (+0,1 s)") { model.shiftSubtitles(0.1) }.keyboardShortcut("h", modifiers: [])
            Button("Adiantar legenda (−0,1 s)") { model.shiftSubtitles(-0.1) }.keyboardShortcut("g", modifiers: [])
            Button("Zerar atraso") { model.subtitles.resetDelay() }
            Divider()
            Button("Aumentar texto") { model.subtitles.fontScale = min(model.subtitles.fontScale + 0.1, 2.5) }.keyboardShortcut("+", modifiers: [.command])
            Button("Diminuir texto") { model.subtitles.fontScale = max(model.subtitles.fontScale - 0.1, 0.5) }.keyboardShortcut("-", modifiers: [.command])
        }
    }
}
