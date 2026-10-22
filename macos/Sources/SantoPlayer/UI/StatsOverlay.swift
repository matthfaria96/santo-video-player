import SwiftUI

/// Diagnostics (⌥⌘I): video fps, redraws, dropped frames and GPU time.
struct StatsOverlay: View {
    let renderer: CRTRenderer
    let dropped: () -> Int
    let decoder: () -> String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let s = renderer.stats
            VStack(alignment: .leading, spacing: 3) {
                row("Vídeo", "\(s.videoSize)  ·  \(Int(s.videoFPS)) fps")
                row("Desenhos", "\(Int(s.drawsPerSecond))/s  ·  \(s.drawableSize)")
                row("GPU (CRT)", String(format: "%.2f ms", s.gpuMilliseconds))
                row("Perdidos", "\(dropped())")
                row("Decodificação", decoder())
            }
            .font(.system(size: 11, weight: .medium).monospaced())
            .padding(10)
            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        }
        .allowsHitTesting(false)
    }

    private func row(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(title).foregroundStyle(.secondary).frame(width: 96, alignment: .leading)
            Text(value).foregroundStyle(.white)
        }
    }
}
