import SwiftUI

struct PlaybackSettingsView: View {
    @Bindable var settings: AppSettings
    let model: PlayerModel

    var body: some View {
        SettingsPage {
            SettingsSection(title: "Reprodução") {
                SettingsRow(title: "Continuar de onde parou",
                            detail: "Reabre cada vídeo no ponto em que você saiu.") {
                    Toggle("", isOn: $settings.resumePlayback).settingsSwitch()
                }
                SettingsSeparator()
                SettingsRow(title: "Avançar e voltar", detail: "Setas ← → e botões da barra.") {
                    Picker("Avançar e voltar", selection: $settings.skipInterval) {
                        ForEach(AppSettings.skipIntervals, id: \.self) { Text("\(Int($0)) s").tag($0) }
                    }
                    .settingsMenu()
                }
            }

            SettingsSection(title: "Áudio") {
                SettingsRow(title: "Idioma preferido do áudio",
                            detail: "Escolhido automaticamente em arquivos com várias faixas.") {
                    Picker("Idioma preferido do áudio", selection: $settings.audioLanguage) {
                        ForEach(AppSettings.TrackLanguage.allCases) { Text($0.title).tag($0) }
                    }
                    .settingsMenu()
                }
            }

            SettingsSection(title: "Desempenho",
                            footer: "Desligue só se algum vídeo aparecer com cores ou blocos errados.") {
                SettingsRow(title: "Decodificação por hardware",
                            detail: "Usa a GPU (VideoToolbox): menos CPU e bateria.") {
                    Toggle("", isOn: $settings.hardwareDecoding).settingsSwitch()
                }
                SettingsSeparator()
                SettingsRow(title: "Diagnóstico de desempenho", detail: "fps, GPU e frames perdidos sobre o vídeo (⌥⌘I).") {
                    Toggle("", isOn: Binding(get: { model.showStats }, set: { model.showStats = $0 })).settingsSwitch()
                }
            }
        }
    }
}
