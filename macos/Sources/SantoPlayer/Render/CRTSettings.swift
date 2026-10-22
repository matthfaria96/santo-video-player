import Foundation

enum CRTMaskType: Int, Codable, CaseIterable, Identifiable {
    case aperture   // Trinitron-style vertical RGB stripes
    case slot       // staggered slot mask (most consumer TVs)
    case shadow     // dot-triad shadow mask (PC monitors)

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .aperture: return String(localized: "Grade")
        case .slot: return String(localized: "Slot")
        case .shadow: return String(localized: "Pontos")
        }
    }

    var detail: String {
        switch self {
        case .aperture:
            return String(localized: "Listras verticais contínuas, como nas TVs Trinitron. Imagem mais clara e nítida.")
        case .slot:
            return String(localized: "Fendas desencontradas, como na maioria das TVs comuns. O visual mais típico de TV antiga.")
        case .shadow:
            return String(localized: "Pontinhos em triângulo, como nos monitores de computador. Textura fina e granulada.")
        }
    }
}

/// Everything the CRT shader needs. Values are normalised to 0...1 unless noted.
struct CRTSettings: Codable, Equatable {
    var enabled = true
    var scanlines: Float = 0.55
    var mask: Float = 0.3
    var maskType: CRTMaskType = .aperture
    var curvature: Float = 0
    var glow: Float = 0.3
    var vignette: Float = 0.25
    var noise: Float = 0
    /// Brightness compensation for the darkening of scanlines + mask (0.8...1.6).
    var brightness: Float = 1.15
    /// Draws the picture tube: rounded glass, bezel, reflections and screen bleed.
    var tube = false
    /// Whole-set cabinet around the screen: wide panels with grille and knobs
    /// for 4:3, a thin frame for 16:9.
    var frame = false

    static let off = CRTSettings(enabled: false)

    /// What actually gets drawn for a video of this shape: with the automatic
    /// cabinet on, any CRT preset puts a 4:3-ish picture in the full set.
    func adapted(toVideo video: CGSize, autoCabinet: Bool) -> CRTSettings {
        guard autoCabinet, enabled, video.height > 0, video.width / video.height < 1.55 else { return self }
        var s = self
        s.frame = true
        s.tube = true
        s.curvature = max(s.curvature, 0.35)
        return s
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, scanlines, mask, maskType, curvature, glow, vignette, noise, brightness, tube, frame
    }

    init(enabled: Bool = true, scanlines: Float = 0.55, mask: Float = 0.3, maskType: CRTMaskType = .aperture,
         curvature: Float = 0, glow: Float = 0.3, vignette: Float = 0.25, noise: Float = 0,
         brightness: Float = 1.15, tube: Bool = false, frame: Bool = false) {
        self.enabled = enabled
        self.scanlines = scanlines
        self.mask = mask
        self.maskType = maskType
        self.curvature = curvature
        self.glow = glow
        self.vignette = vignette
        self.noise = noise
        self.brightness = brightness
        self.tube = tube
        self.frame = frame
    }

    /// Missing keys keep their defaults, so settings saved by older versions still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CRTSettings()
        self.init(enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled,
                  scanlines: try c.decodeIfPresent(Float.self, forKey: .scanlines) ?? d.scanlines,
                  mask: try c.decodeIfPresent(Float.self, forKey: .mask) ?? d.mask,
                  maskType: try c.decodeIfPresent(CRTMaskType.self, forKey: .maskType) ?? d.maskType,
                  curvature: try c.decodeIfPresent(Float.self, forKey: .curvature) ?? d.curvature,
                  glow: try c.decodeIfPresent(Float.self, forKey: .glow) ?? d.glow,
                  vignette: try c.decodeIfPresent(Float.self, forKey: .vignette) ?? d.vignette,
                  noise: try c.decodeIfPresent(Float.self, forKey: .noise) ?? d.noise,
                  brightness: try c.decodeIfPresent(Float.self, forKey: .brightness) ?? d.brightness,
                  tube: try c.decodeIfPresent(Bool.self, forKey: .tube) ?? d.tube,
                  frame: try c.decodeIfPresent(Bool.self, forKey: .frame) ?? d.frame)
    }
}

enum CRTPreset: String, CaseIterable, Identifiable {
    // Display order: the TVs first, then the flat effects.
    case off, cabinet, trinitron, oldTV, classic, soft, arcade, pvm

    var id: String { rawValue }

    var name: String {
        switch self {
        case .off: return String(localized: "Sem efeito")
        case .classic: return String(localized: "CRT Clássico")
        case .soft: return String(localized: "CRT Suave")
        case .arcade: return String(localized: "Arcade")
        case .trinitron: return String(localized: "TV de Tubo")
        case .cabinet: return String(localized: "TV com Gabinete")
        case .oldTV: return String(localized: "TV Antiga")
        case .pvm: return String(localized: "Monitor PVM")
        }
    }

    var detail: String {
        switch self {
        case .off: return String(localized: "Imagem original")
        case .classic: return String(localized: "Scanlines + grade RGB")
        case .soft: return String(localized: "Leve, para assistir horas")
        case .arcade: return String(localized: "Scanlines fortes e brilho")
        case .trinitron: return String(localized: "Tubo curvo, vidro e moldura")
        case .cabinet: return String(localized: "A TV inteira em volta da tela")
        case .oldTV: return String(localized: "Tubo gasto, ruído e cantos")
        case .pvm: return String(localized: "Estúdio: nítido e plano")
        }
    }

    var symbol: String {
        switch self {
        case .off: return "rectangle"
        case .classic: return "line.3.horizontal"
        case .soft: return "circle.lefthalf.filled"
        case .arcade: return "gamecontroller"
        case .trinitron: return "tv"
        case .cabinet: return "tv.fill"
        case .oldTV: return "tv.badge.wifi"
        case .pvm: return "display"
        }
    }

    var settings: CRTSettings {
        switch self {
        case .off:
            return .off
        case .classic:
            return CRTSettings()
        case .soft:
            return CRTSettings(scanlines: 0.3, mask: 0.15, glow: 0.2, vignette: 0.15, brightness: 1.05)
        case .arcade:
            return CRTSettings(scanlines: 0.85, mask: 0.45, glow: 0.55, vignette: 0.3, brightness: 1.35)
        case .cabinet:
            return CRTSettings(scanlines: 0.55, mask: 0.35, maskType: .slot, curvature: 0.45,
                               glow: 0.45, vignette: 0.4, noise: 0.05, brightness: 1.25, tube: true, frame: true)
        case .trinitron:
            return CRTSettings(scanlines: 0.55, mask: 0.35, maskType: .aperture, curvature: 0.5,
                               glow: 0.45, vignette: 0.45, noise: 0.05, brightness: 1.25, tube: true)
        case .oldTV:
            return CRTSettings(scanlines: 0.6, mask: 0.4, maskType: .slot, curvature: 0.85,
                               glow: 0.4, vignette: 0.7, noise: 0.35, brightness: 1.12, tube: true)
        case .pvm:
            return CRTSettings(scanlines: 0.75, mask: 0.3, maskType: .shadow, glow: 0.15,
                               vignette: 0.05, brightness: 1.25)
        }
    }

    static func matching(_ settings: CRTSettings) -> CRTPreset? {
        allCases.first { $0.settings == settings }
    }
}
