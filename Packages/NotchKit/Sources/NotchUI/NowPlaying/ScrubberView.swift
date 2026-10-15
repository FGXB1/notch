import MediaKit
import SwiftUI

/// Playback progress with elapsed/remaining times. Drag anywhere on it to seek.
struct ScrubberView: View {
    let item: NowPlaying
    let tint: Color
    var isActive = true
    let onSeek: (TimeInterval) -> Void

    @State private var dragProgress: Double?

    var body: some View {
        if let duration = item.duration, duration > 0 {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !isActive || !item.isPlaying || dragProgress != nil)) {
                context in
                let progress = dragProgress ?? item.progress(at: context.date) ?? 0
                VStack(spacing: 5) {
                    track(progress: progress, duration: duration)
                    HStack {
                        Text(Self.format(progress * duration))
                        Spacer()
                        Text("-" + Self.format(duration * (1 - progress)))
                    }
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.5))
                }
            }
        } else {
            Label("Live", systemImage: "dot.radiowaves.left.and.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
        }
    }

    private func track(progress: Double, duration: TimeInterval) -> some View {
        GeometryReader { proxy in
            let isDragging = dragProgress != nil
            Capsule()
                .fill(.white.opacity(0.16))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(tint)
                        .frame(width: max(proxy.size.height, proxy.size.width * progress))
                }
                .frame(height: isDragging ? 7 : 4)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            withAnimation(.snappy(duration: 0.15)) {
                                dragProgress = min(1, max(0, value.location.x / proxy.size.width))
                            }
                        }
                        .onEnded { _ in
                            if let dragProgress { onSeek(dragProgress * duration) }
                            withAnimation(.snappy(duration: 0.2)) { dragProgress = nil }
                        }
                )
                .animation(.snappy(duration: 0.2), value: isDragging)
        }
        .frame(height: 12)
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}
