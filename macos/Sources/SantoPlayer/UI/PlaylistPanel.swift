import SwiftUI

struct PlaylistPanel: View {
    let model: PlayerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Playlist").font(.system(size: 17, weight: .bold))
                Spacer()
                Button { FilePanels.enqueueMedia(model) } label: { Image(systemName: "plus") }
                    .buttonStyle(IconButtonStyle(size: 28)).help("Adicionar vídeos")
            }
            if model.playlist.isEmpty {
                Text("Arraste vídeos para a janela ou use ⌥⌘O para adicionar.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(Array(model.playlist.enumerated()), id: \.offset) { index, url in
                            row(index: index, url: url)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .padding(16)
        .frame(width: 320)
        .frame(maxHeight: 460)
        .compatGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func row(index: Int, url: URL) -> some View {
        let current = index == model.index
        return Button { model.play(at: index) } label: {
            HStack(spacing: 10) {
                Image(systemName: current ? "waveform" : "film")
                    .foregroundStyle(current ? Color.phosphor : .secondary)
                    .frame(width: 18)
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(.system(size: 12, weight: current ? .semibold : .regular))
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9).fill(current ? Color.phosphor.opacity(0.15) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Reproduzir") { model.play(at: index) }
            Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button("Remover da playlist", role: .destructive) { model.remove(at: IndexSet(integer: index)) }
        }
    }
}
