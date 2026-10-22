import SwiftUI

/// One preset in the effects grid: live preview, name and a short description.
/// Fixed preview and text heights keep every card the same size.
struct PresetCard: View {
    let preset: CRTPreset
    let selected: Bool
    let edited: Bool
    let preview: CGImage?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                thumbnail
                HStack(spacing: 4) {
                    Text(preset.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    if edited {
                        Circle().fill(Color.phosphor).frame(width: 5, height: 5).help("Editado")
                    }
                }
                Text(preset.detail)
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Color.phosphor.opacity(0.16) : Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? Color.phosphor : Color.white.opacity(0.08), lineWidth: selected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var thumbnail: some View {
        Color.black
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                if let preview {
                    Image(decorative: preview, scale: 1).resizable().scaledToFill()
                } else {
                    Image(systemName: preset.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(selected ? Color.phosphor : .white.opacity(0.8))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
