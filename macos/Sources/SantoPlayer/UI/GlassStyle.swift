import SwiftUI

extension Color {
    /// Warm phosphor amber, the app's accent.
    static let phosphor = Color(red: 1.0, green: 0.62, blue: 0.2)
}

extension View {
    /// Liquid Glass on macOS 26+, a dark material on older systems.
    @ViewBuilder
    func compatGlass<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.08), lineWidth: 1))
        }
    }
}

/// Round, borderless icon button used across the control bar.
struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 32
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: prominent ? 20 : 15, weight: .semibold))
            .foregroundStyle(prominent ? Color.black : Color.white)
            .frame(width: size, height: size)
            .background(Circle().fill(prominent ? Color.phosphor : Color.white.opacity(configuration.isPressed ? 0.18 : 0.0001)))
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
