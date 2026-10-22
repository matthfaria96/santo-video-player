import SwiftUI

struct SubtitleSettingsView: View {
    @Bindable var settings: AppSettings
    @Bindable var subtitles: SubtitleController

    var body: some View {
        SettingsPage {
            SettingsSection(title: "Escolha automática") {
                SettingsRow(title: "Idioma preferido",
                            detail: "Ativa a legenda embutida nesse idioma, se houver.") {
                    Picker("Idioma preferido", selection: $settings.subtitleLanguage) {
                        ForEach(AppSettings.TrackLanguage.allCases) { Text($0.title).tag($0) }
                    }
                    .settingsMenu()
                }
                SettingsSeparator()
                SettingsRow(title: "Ativar legenda ao lado do vídeo",
                            detail: "Arquivos .srt, .ass… com o mesmo nome do vídeo.") {
                    Toggle("", isOn: $settings.autoSidecarSubtitles).settingsSwitch()
                }
            }

            SettingsSection(title: "Aparência", footer: "“Dentro da tela” mantém cores e posições das legendas ASS e aplica o efeito CRT nelas.") {
                SettingsRow(title: "Dentro da tela (estilo original)") {
                    Toggle("", isOn: $subtitles.insideScreen).settingsSwitch()
                }
                SettingsSeparator()
                SettingsRow(title: "Tamanho do texto") {
                    Picker("Tamanho do texto", selection: $subtitles.fontScale) {
                        ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { Text("\(Int($0 * 100))%").tag($0) }
                    }
                    .settingsMenu()
                    .disabled(subtitles.insideScreen)
                }
                SettingsSeparator()
                SettingsRow(title: "Fundo escuro atrás do texto") {
                    Toggle("", isOn: $subtitles.showBackground).settingsSwitch().disabled(subtitles.insideScreen)
                }
                SettingsSeparator()
                SubtitleSample(scale: subtitles.fontScale, background: subtitles.showBackground)
                    .opacity(subtitles.insideScreen ? 0.35 : 1)
            }
        }
    }
}

/// Live sample of the overlay style over a little CRT-tinted frame.
private struct SubtitleSample: View {
    let scale: Double
    let background: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Color(red: 0.25, green: 0.18, blue: 0.45), Color(red: 0.85, green: 0.42, blue: 0.22)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Text("Assim fica a legenda")
                .font(.system(size: 15 * scale, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black, radius: 1.5, y: 1)
                .padding(.horizontal, background ? 10 : 0)
                .padding(.vertical, background ? 4 : 0)
                .background(background ? Color.black.opacity(0.5) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .padding(.bottom, 12)
        }
        .frame(height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(12)
        .animation(.easeOut(duration: 0.15), value: scale)
    }
}
