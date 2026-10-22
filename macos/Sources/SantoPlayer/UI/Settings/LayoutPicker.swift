import SwiftUI

/// The two layout cards with animated previews (Ajustes → Geral).
struct LayoutPicker: View {
    @Bindable var settings: AppSettings

    var body: some View {
        HStack(spacing: 14) {
            ForEach(PlayerLayout.allCases) { option in
                LayoutOptionCard(option: option, selected: settings.layout == option) {
                    withAnimation(.snappy) { settings.layout = option }
                }
            }
        }
    }
}

struct LayoutOptionCard: View {
    let option: PlayerLayout
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                LayoutPreview(layout: option)
                    .frame(height: 158)
                    .overlay(alignment: .topTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.black, Color.phosphor)
                                .padding(8)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(option.name).font(.system(size: 13, weight: .semibold))
                    Text(option.detail)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(selected ? Color.phosphor.opacity(0.1) : Color.white.opacity(hovering ? 0.07 : 0.04)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(selected ? Color.phosphor : Color.white.opacity(0.1), lineWidth: selected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .scaleEffect(hovering && !selected ? 1.015 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .accessibilityLabel(option.name)
        .accessibilityValue(option.detail)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A miniature, animated window: the modern controls fade in and out like
/// the real auto-hide; the classic bar stays put under the picture.
private struct LayoutPreview: View {
    let layout: PlayerLayout

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let progress = (t / 12).truncatingRemainder(dividingBy: 1)
            // Modern: visible ~2.4 s, fading out, hidden ~1.6 s, fading in (5 s cycle).
            let cycle = t.truncatingRemainder(dividingBy: 5)
            let modernOpacity = cycle < 2.4 ? 1 : cycle < 2.8 ? (2.8 - cycle) / 0.4 : cycle < 4.6 ? 0 : (cycle - 4.6) / 0.4
            window(progress: progress, controlsOpacity: layout == .modern ? modernOpacity : 1)
        }
    }

    private func window(progress: Double, controlsOpacity: Double) -> some View {
        VStack(spacing: 0) {
            if layout == .classic { titleStrip }
            ZStack {
                screen
                if layout == .modern {
                    VStack {
                        trafficLights.frame(maxWidth: .infinity, alignment: .leading).padding(7)
                        Spacer()
                        MiniControls(progress: progress, floating: true)
                            .padding(.horizontal, 12).padding(.bottom, 9)
                            .opacity(controlsOpacity)
                    }
                }
            }
            if layout == .classic { MiniControls(progress: progress, floating: false) }
        }
        .background(Color(white: 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.14)))
        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
    }

    private var titleStrip: some View {
        HStack {
            trafficLights
            Spacer()
        }
        .padding(.horizontal, 7)
        .frame(height: 16)
        .background(Color(white: 0.11))
        .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5) }
    }

    private var trafficLights: some View {
        HStack(spacing: 3.5) {
            Circle().fill(Color(red: 1, green: 0.37, blue: 0.34))
            Circle().fill(Color(red: 1, green: 0.74, blue: 0.18))
            Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25))
        }
        .frame(height: 6)
    }

    /// The "tube": warm picture, scanlines, vignette and a glass highlight.
    private var screen: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.32, green: 0.18, blue: 0.55), Color(red: 0.95, green: 0.45, blue: 0.25)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Canvas { context, size in
                var y: CGFloat = 0
                while y < size.height {
                    context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(0.2)))
                    y += 2.5
                }
            }
            RadialGradient(colors: [.clear, .black.opacity(0.35)], center: .center, startRadius: 45, endRadius: 150)
            Ellipse().fill(.white.opacity(0.12)).frame(width: 70, height: 22).offset(x: -40, y: -28).blur(radius: 6)
        }
        .clipShape(RoundedRectangle(cornerRadius: layout == .modern ? 0 : 3, style: .continuous))
    }
}

/// Tiny control bar: progress line, play button and a row of icons.
private struct MiniControls: View {
    let progress: Double
    let floating: Bool

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule().fill(Color.phosphor).frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 2.5)
            HStack(spacing: 4) {
                ForEach(0..<2) { _ in dot }
                Circle().fill(Color.phosphor).frame(width: 9, height: 9)
                ForEach(0..<2) { _ in dot }
                Capsule().fill(.white.opacity(0.35)).frame(width: 18, height: 2.5)
                Spacer()
                ForEach(0..<4) { _ in dot }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background {
            if floating {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
            } else {
                Rectangle().fill(Color(white: 0.11))
                    .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5) }
            }
        }
    }

    private var dot: some View {
        RoundedRectangle(cornerRadius: 1.5).fill(.white.opacity(0.65)).frame(width: 5, height: 5)
    }
}
