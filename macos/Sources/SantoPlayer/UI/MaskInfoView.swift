import SwiftUI

/// Explains the three phosphor masks, each with a magnified drawing of it.
struct MaskInfoView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Máscara de fósforo").font(.system(size: 14, weight: .bold))
            Text("A tela de um CRT é feita de pontinhos vermelhos, verdes e azuis. O desenho desses pontos muda conforme o tipo de tubo — e muda a textura da imagem.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(CRTMaskType.allCases) { type in
                HStack(alignment: .top, spacing: 12) {
                    MaskSwatch(type: type).frame(width: 64, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(type.label).font(.system(size: 12, weight: .semibold))
                        Text(type.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}

/// The mask pattern, magnified (same layout the shader uses).
private struct MaskSwatch: View {
    let type: CRTMaskType

    var body: some View {
        Canvas { context, size in
            let w: CGFloat = 4
            let colors: [Color] = [Color(red: 1, green: 0.2, blue: 0.15), Color(red: 0.2, green: 1, blue: 0.3),
                                   Color(red: 0.25, green: 0.4, blue: 1)]
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = 0
                var col = 0
                let shift = type == .slot && row % 2 == 1 ? 1 : 0
                let diagonal = type == .shadow ? row : 0
                let rowHeight = type == .slot ? 4 * w : w
                while x < size.width {
                    let index = (col + shift + diagonal) % 3
                    var rect = CGRect(x: x + 0.5, y: y + 0.5, width: w - 1, height: rowHeight - 1)
                    if type == .slot { rect.size.height -= w * 0.6 }
                    context.fill(Path(roundedRect: rect, cornerRadius: type == .shadow ? 1.5 : 0.8),
                                 with: .color(colors[index]))
                    x += w
                    col += 1
                }
                y += rowHeight
                row += 1
            }
        }
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.15)))
    }
}
