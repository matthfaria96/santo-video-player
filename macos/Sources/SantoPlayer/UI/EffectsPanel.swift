import SwiftUI

struct EffectsPanel: View {
    @Bindable var model: PlayerModel
    @State private var previews: [CRTPreset: CGImage] = [:]

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(CRTPreset.allCases) { preset in
                        PresetCard(preset: preset, selected: model.crtPreset == preset, preview: previews[preset]) {
                            model.apply(preset)
                        }
                    }
                }
                if model.crt.enabled { adjustments }
            }
            .padding(16)
        }
        .scrollIndicators(.never)
        .task(id: model.index) { await renderPreviews() }
        .frame(width: 320)
        .compatGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Efeitos CRT").font(.system(size: 17, weight: .bold))
                Text(model.crtPreset?.name ?? "Personalizado")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $model.crt.enabled).toggleStyle(.switch).tint(.phosphor).labelsHidden()
        }
    }

    private var adjustments: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $model.crt.tube) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("TV de tubo").font(.system(size: 13, weight: .semibold))
                    Text("Vidro curvo, reflexo e moldura").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch).tint(.phosphor)

            Toggle(isOn: $model.crt.frame) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Moldura completa").font(.system(size: 13, weight: .semibold))
                    Text("Gabinete inteiro no 4:3, borda fina no 16:9").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch).tint(.phosphor)

            Divider().opacity(0.4)
            EffectSlider(title: "Scanlines", value: $model.crt.scanlines)
            EffectSlider(title: "Máscara de fósforo", value: $model.crt.mask)
            Picker("", selection: $model.crt.maskType) {
                ForEach(CRTMaskType.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            EffectSlider(title: "Curvatura", value: $model.crt.curvature)
            EffectSlider(title: "Brilho do fósforo", value: $model.crt.glow)
            EffectSlider(title: "Vinheta", value: $model.crt.vignette)
            EffectSlider(title: "Ruído e interferência", value: $model.crt.noise)
            EffectSlider(title: "Brilho", value: $model.crt.brightness, range: 0.8...1.6)

            if let preset = model.crtPreset ?? lastPresetGuess {
                Button(String(localized: "Restaurar “\(preset.name)”")) { model.apply(preset) }
                    .buttonStyle(.borderless).foregroundStyle(Color.phosphor).font(.system(size: 12, weight: .semibold))
                    .disabled(model.crtPreset == preset)
            }
        }
    }

    private var lastPresetGuess: CRTPreset? { model.crt.tube ? .trinitron : .classic }

    /// Renders the current frame through every preset (at 2× and shown
    /// smaller, so the scanlines stay legible), refreshed every few seconds.
    private func renderPreviews() async {
        while !Task.isCancelled {
            if let renderer = model.renderer, !model.isAudioOnly, renderer.texture != nil {
                var images: [CRTPreset: CGImage] = [:]
                for preset in CRTPreset.allCases {
                    images[preset] = renderer.renderImage(size: CGSize(width: 512, height: 288), pixelScale: 2,
                                                          settings: preset.settings)
                }
                previews = images
            } else {
                previews = [:]
            }
            try? await Task.sleep(for: .seconds(4))
        }
    }
}

private struct PresetCard: View {
    let preset: CRTPreset
    let selected: Bool
    let preview: CGImage?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                if let preview {
                    Image(decorative: preview, scale: 1)
                        .resizable()
                        .aspectRatio(16 / 9, contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                } else {
                    Image(systemName: preset.symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(selected ? Color.phosphor : .white)
                }
                Text(preset.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(preset.detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Color.phosphor.opacity(0.16) : Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? Color.phosphor : Color.white.opacity(0.08), lineWidth: selected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

private struct EffectSlider: View {
    let title: LocalizedStringKey
    @Binding var value: Float
    var range: ClosedRange<Float> = 0...1

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(Int((value * 100).rounded()))%")
                    .font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range).tint(.phosphor).controlSize(.small)
        }
    }
}
