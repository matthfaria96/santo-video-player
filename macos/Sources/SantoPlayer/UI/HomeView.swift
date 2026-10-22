import SwiftUI

/// Shown when nothing is playing: open button plus "continue watching".
struct HomeView: View {
    let model: PlayerModel

    var body: some View {
        let recents = AppSettings.shared.showRecents ? model.library.available : []
        VStack(spacing: 26) {
            header(compact: !recents.isEmpty)
            if !recents.isEmpty { RecentsShelf(model: model, items: recents) }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 30)
        .frame(maxWidth: 1000)
    }

    private func header(compact: Bool) -> some View {
        VStack(spacing: compact ? 12 : 18) {
            Image(systemName: "tv")
                .font(.system(size: compact ? 40 : 64, weight: .light))
                .foregroundStyle(Color.phosphor)
                .shadow(color: .phosphor.opacity(0.7), radius: 18)
            VStack(spacing: 6) {
                Text("Santo Video Player").font(.system(size: compact ? 22 : 26, weight: .bold))
                Text("Arraste um vídeo (e a legenda, se quiser) para esta janela")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
            }
            Button { FilePanels.openMedia(model) } label: {
                Label("Abrir vídeo…", systemImage: "folder")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 18).padding(.vertical, 9)
                    .foregroundStyle(.black)
                    .background(Capsule().fill(Color.phosphor))
            }
            .buttonStyle(.plain)
            if !compact {
                Text("⌘O abrir  ·  espaço play/pausa  ·  ⌘E efeitos CRT  ·  V legendas  ·  B áudio  ·  [ ] velocidade")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
    }
}

private struct RecentsShelf: View {
    let model: PlayerModel
    let items: [RecentItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Continuar assistindo").font(.system(size: 15, weight: .bold))
                Spacer()
                Button("Limpar") { model.library.clear() }
                    .buttonStyle(.borderless).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) {
                    ForEach(items.prefix(20)) { item in
                        RecentCard(item: item, version: model.artworkVersion) { model.open([item.url]) }
                            .contextMenu {
                                Button("Reproduzir") { model.open([item.url]) }
                                Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                                Button("Remover dos recentes", role: .destructive) { model.library.remove(item) }
                            }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.never)
            .frame(height: 186)
        }
    }
}

private struct RecentCard: View {
    let item: RecentItem
    let version: Int
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomLeading) {
                    artwork
                        .frame(width: 220, height: 124)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    if item.progress > 0.01 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.black.opacity(0.5))
                                Capsule().fill(Color.phosphor)
                                    .frame(width: geo.size.width * (item.isFinished ? 1 : item.progress))
                            }
                        }
                        .frame(height: 4)
                        .padding(8)
                    }
                    if hovering {
                        Image(systemName: "play.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 48, height: 48)
                            .background(Circle().fill(Color.phosphor))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: 220, height: 124)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(hovering ? Color.phosphor : .white.opacity(0.1), lineWidth: hovering ? 2 : 1))
                Text(item.title).font(.system(size: 12, weight: .semibold)).lineLimit(1).frame(width: 220, alignment: .leading)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    private var subtitle: String {
        if item.isFinished { return String(localized: "Assistido") }
        if item.duration > 0, item.position > 1 {
            return String(localized: "Faltam \(Formatting.time(item.duration - item.position))")
        }
        return item.url.pathExtension.uppercased()
    }

    @ViewBuilder
    private var artwork: some View {
        let url = ArtworkCache.url(for: item.url)
        if let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).id(version)
        } else {
            ZStack {
                LinearGradient(colors: [Color(white: 0.16), Color(white: 0.08)], startPoint: .top, endPoint: .bottom)
                Image(systemName: "film").font(.system(size: 26)).foregroundStyle(.tertiary)
            }
        }
    }
}
