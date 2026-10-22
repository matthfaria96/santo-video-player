import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        SettingsPage {
            SettingsSection(title: "Layout do player",
                            footer: "Escolha como o vídeo e os controles ficam na janela. Muda na hora.",
                            plain: true) {
                LayoutPicker(settings: settings)
            }

            SettingsSection(title: "Idioma") {
                SettingsRow(title: "Idioma do app") {
                    Picker("Idioma do app", selection: $settings.language) {
                        ForEach(AppSettings.Language.allCases) { Text($0.title).tag($0) }
                    }
                    .settingsMenu()
                }
                if settings.needsRelaunchForLanguage {
                    SettingsSeparator()
                    SettingsRow(title: "Reabra o app para aplicar o idioma.") {
                        Button("Reabrir agora") { relaunch() }.buttonStyle(.borderedProminent)
                    }
                    .transition(.opacity)
                }
            }

            SettingsSection(title: "Tela inicial") {
                SettingsRow(title: "Mostrar “Continuar assistindo”",
                            detail: "Os vídeos recentes, com capa e progresso.") {
                    Toggle("", isOn: $settings.showRecents).settingsSwitch()
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: settings.needsRelaunchForLanguage)
    }

    /// Waits for this process to finish saving and exit, then reopens the app.
    private func relaunch() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; open \"$0\"",
                          Bundle.main.bundleURL.path]
        try? task.run()
        NSApp.terminate(nil)
    }
}
