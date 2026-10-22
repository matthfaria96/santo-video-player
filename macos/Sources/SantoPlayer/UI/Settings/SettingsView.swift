import SwiftUI

/// Ajustes (⌘,): Geral, Reprodução, Legendas e Sobre, in MacDash's style.
struct SettingsView: View {
    @Bindable var settings: AppSettings
    let model: PlayerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("Ajustes", selection: $settings.tab) {
                ForEach(AppSettings.Tab.allCases) { tab in Text(tab.title).tag(tab) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .frame(maxWidth: .infinity)

            Group {
                switch settings.tab {
                case .general: GeneralSettingsView(settings: settings)
                case .playback: PlaybackSettingsView(settings: settings, model: model)
                case .subtitles: SubtitleSettingsView(settings: settings, subtitles: model.subtitles)
                case .about: AboutSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .frame(width: 680, height: 600)
        .background(SettingsBackdrop())
        .tint(.phosphor)
        .preferredColorScheme(.dark)
    }
}

/// A faint warm phosphor glow behind the pages.
private struct SettingsBackdrop: View {
    var body: some View {
        ZStack {
            Color(white: 0.07)
            RadialGradient(colors: [Color.phosphor.opacity(0.12), .clear], center: .top, startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}
