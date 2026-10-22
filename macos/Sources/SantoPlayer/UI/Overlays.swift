import SwiftUI

struct SubtitleOverlay: View {
    let subtitles: SubtitleController
    let bottomInset: CGFloat

    var body: some View {
        GeometryReader { geo in
            let size = max(15, min(geo.size.height * 0.045, 54)) * subtitles.fontScale
            VStack {
                Spacer()
                if !subtitles.overlayText.isEmpty {
                    Text(subtitles.overlayText)
                        .font(.system(size: size, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .shadow(color: .black, radius: 1.5, x: 0, y: 1)
                        .shadow(color: .black.opacity(0.7), radius: 6)
                        .padding(.horizontal, subtitles.showBackground ? 14 : 0)
                        .padding(.vertical, subtitles.showBackground ? 5 : 0)
                        .background(subtitles.showBackground ? Color.black.opacity(0.5) : .clear,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(.horizontal, geo.size.width * 0.08)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, bottomInset)
            .animation(.easeOut(duration: 0.3), value: bottomInset)
        }
        .allowsHitTesting(false)
    }
}

struct OSDView: View {
    let message: OSDMessage?
    var topInset: CGFloat = 58

    var body: some View {
        VStack {
            if let message {
                HStack(spacing: 8) {
                    if let symbol = message.symbol { Image(systemName: symbol).foregroundStyle(Color.phosphor) }
                    Text(message.text).lineLimit(2)
                }
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .compatGlass(in: Capsule())
                .id(message.id)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .padding(.top, topInset)
        .padding(.horizontal, 40)
        .animation(.spring(duration: 0.3), value: message)
        .allowsHitTesting(false)
    }
}

struct AudioOnlyView: View {
    let title: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Color.phosphor)
            Text(title).font(.system(size: 18, weight: .semibold)).lineLimit(1)
        }
        .allowsHitTesting(false)
    }
}
