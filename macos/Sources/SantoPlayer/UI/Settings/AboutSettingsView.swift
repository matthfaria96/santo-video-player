import SwiftUI

/// About page, following MacDash's AboutSettingsView.
struct AboutSettingsView: View {
    @State private var showLicenses = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return String(localized: "Versão \(marketing)") + " (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                    .padding(.bottom, 18)
                Text("Santo Video Player")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(SettingsStyle.primary)
                Text(version)
                    .font(.system(size: 12)).monospacedDigit()
                    .foregroundStyle(SettingsStyle.secondary)
                    .textSelection(.enabled)
                    .padding(.top, 4)

                Text("Santo Video Player toca praticamente qualquer vídeo com um efeito de TV de tubo aplicado só sobre a imagem: scanlines, máscara de fósforo, vidro curvo e moldura. Tem faixas de áudio e legendas, Picture in Picture e continua de onde você parou.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 460)
                    .padding(.top, 26)

                Text("Santo Video Player é software livre sob a GNU GPL v2 ou posterior. Usa os projetos de código aberto listados nas licenças.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(SettingsStyle.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                    .padding(.top, 14)

                HStack(spacing: 18) {
                    Link("witchmymac.com", destination: URL(string: "http://witchmymac.com")!)
                        .font(.system(size: 12))
                    Button("Licenças de código aberto") { showLicenses = true }
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                }
                .padding(.top, 10)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 36)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.never)
        .sheet(isPresented: $showLicenses) { OpenSourceLicensesView() }
    }
}
