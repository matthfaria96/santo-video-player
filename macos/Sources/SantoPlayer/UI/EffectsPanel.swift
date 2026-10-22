import SwiftUI

struct EffectsPanel: View {
    @Bindable var model: PlayerModel
    @State private var previews: [CRTPreset: CGImage] = [:]
    @State private var showMaskInfo = false

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(CRTPreset.allCases) { preset in
                        let selected = model.crtPreset == preset
                        PresetCard(preset: preset, selected: selected, edited: selected && model.crtEdited,
                                   preview: previews[preset]) { model.apply(preset) }
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
                HStack(spacing: 6) {
                    Text(model.crtPreset.name)
                    if model.crtEdited {
                        Text("editado")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(Color.phosphor.opacity(0.2)))
                            .foregroundStyle(Color.phosphor)
                    }
                }
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
            EffectSlider(title: "Máscara de fósforo", value: $model.crt.mask) {
                Button { showMaskInfo.toggle() } label: { Image(systemName: "info.circle") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("O que é a máscara de fósforo?")
                    .accessibilityLabel("Sobre os tipos de máscara")
                    .popover(isPresented: $showMaskInfo, arrowEdge: .leading) { MaskInfoView() }
            }
            Picker("", selection: $model.crt.maskType) {
                ForEach(CRTMaskType.allCases) { Text($0.label).tag($0).help($0.detail) }
            }
            .pickerStyle(.segmented).labelsHidden()
            EffectSlider(title: "Curvatura", value: $model.crt.curvature)
            EffectSlider(title: "Brilho do fósforo", value: $model.crt.glow)
            EffectSlider(title: "Vinheta", value: $model.crt.vignette)
            EffectSlider(title: "Ruído e interferência", value: $model.crt.noise)
            EffectSlider(title: "Brilho", value: $model.crt.brightness, range: 0.8...1.6)

            Button(String(localized: "Restaurar “\(model.crtPreset.name)”")) { model.apply(model.crtPreset) }
                .buttonStyle(.borderless).foregroundStyle(Color.phosphor).font(.system(size: 12, weight: .semibold))
                .disabled(!model.crtEdited)
        }
    }

    /// Renders the current frame through every preset (at 2× and shown
    /// smaller, so the scanlines stay legible), refreshed every few seconds.
    private func renderPreviews() async {
        while !Task.isCancelled {
            if let renderer = model.renderer, !model.isAudioOnly, renderer.texture != nil {
                var images: [CRTPreset: CGImage] = [:]
                for preset in CRTPreset.allCases {
                    images[preset] = await renderer.renderImageAsync(size: CGSize(width: 512, height: 288),
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

private struct EffectSlider<Accessory: View>: View {
    let title: LocalizedStringKey
    @Binding var value: Float
    var range: ClosedRange<Float> = 0...1
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(title).font(.system(size: 12, weight: .medium))
                accessory
                Spacer()
                Text("\(Int((value * 100).rounded()))%")
                    .font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range).tint(.phosphor).controlSize(.small)
        }
    }
}

private extension EffectSlider where Accessory == EmptyView {
    init(title: LocalizedStringKey, value: Binding<Float>, range: ClosedRange<Float> = 0...1) {
        self.init(title: title, value: value, range: range) { EmptyView() }
    }
}
