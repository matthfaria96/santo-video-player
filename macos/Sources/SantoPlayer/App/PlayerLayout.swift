import Foundation

/// How the window arranges video and controls (Ajustes → Aparência).
enum PlayerLayout: String, CaseIterable, Identifiable {
    /// Video fills the window; glass controls float over it and auto-hide.
    case modern
    /// Title strip on top, video in the middle, controls docked below, always visible.
    case classic

    static let storageKey = "playerLayout"
    var id: String { rawValue }

    var name: String {
        switch self {
        case .modern: return String(localized: "Moderno")
        case .classic: return String(localized: "Clássico")
        }
    }

    var detail: String {
        switch self {
        case .modern: return String(localized: "Vídeo em tela inteira, controles flutuantes que somem sozinhos.")
        case .classic: return String(localized: "Vídeo em cima, barra de controles fixa embaixo, sempre visível.")
        }
    }
}
