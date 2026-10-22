import SwiftUI

struct Scrubber: View {
    @Bindable var model: PlayerModel
    @State private var hoverX: CGFloat?
    @State private var preview: CGImage?
    @State private var previewTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let progress = model.duration > 0 ? min(max(model.currentTime / model.duration, 0), 1) : 0
            let active = hoverX != nil || model.isScrubbing
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                    .frame(height: active ? 7 : 4)
                Capsule().fill(Color.phosphor)
                    .frame(width: width * progress, height: active ? 7 : 4)
                    .shadow(color: .phosphor.opacity(0.6), radius: 6)
                Circle().fill(.white)
                    .frame(width: 13, height: 13)
                    .shadow(radius: 3)
                    .offset(x: width * progress - 6.5)
                    .opacity(active ? 1 : 0)
            }
            .frame(maxHeight: .infinity)
            .overlay(alignment: .bottomLeading) {
                // Overlay, so the preview floats above without resizing the bar.
                if let hoverX, model.duration > 0 {
                    HoverPreview(image: model.isAudioOnly ? nil : preview,
                                 time: Formatting.time(Double(hoverX / width) * model.duration))
                        .offset(x: min(max(hoverX - HoverPreview.width / 2, 0), width - HoverPreview.width),
                                y: -24)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                if case .active(let point) = phase {
                    hoverX = point.x
                    requestPreview(at: Double(point.x / width) * model.duration)
                } else {
                    hoverX = nil
                    previewTask?.cancel()
                    preview = nil
                }
            }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    model.isScrubbing = true
                    model.scrub(to: Double(min(max(value.location.x / width, 0), 1)) * model.duration)
                }
                .onEnded { value in
                    model.seek(to: Double(min(max(value.location.x / width, 0), 1)) * model.duration)
                    model.isScrubbing = false
                })
            .animation(.easeOut(duration: 0.15), value: active)
        }
        .frame(height: 18)
        .disabled(!model.hasMedia)
    }
}

extension Scrubber {
    /// Coalesced, keyframe-quantised thumbnail for the hovered time.
    private func requestPreview(at seconds: Double) {
        guard let url = model.currentURL, MediaInput.isTrackable(url), model.duration > 0, !model.isAudioOnly else { return }
        let step = max(1, model.duration / 240)
        let quantised = (seconds / step).rounded() * step
        previewTask?.cancel()
        previewTask = Task {
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else { return }
            let image = await Thumbnailer.shared.image(for: url, at: quantised, width: 240, coalesce: true)
            if !Task.isCancelled, let image { preview = image }
        }
    }
}

private struct HoverPreview: View {
    static let width: CGFloat = 160
    let image: CGImage?
    let time: String

    var body: some View {
        VStack(spacing: 4) {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: Self.width)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.25)))
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 3)
            }
            Text(time)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(.black.opacity(0.75), in: Capsule())
        }
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        .allowsHitTesting(false)
    }
}

struct MiniSlider: View {
    @Binding var value: Double

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18)).frame(height: 4)
                Capsule().fill(.white).frame(width: width * value, height: 4)
                Circle().fill(.white).frame(width: 11, height: 11).offset(x: width * value - 5.5)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                value = Double(min(max(drag.location.x / width, 0), 1))
            })
        }
        .frame(height: 20)
    }
}
