import SwiftUI

/// Single-line text that scrolls when it doesn't fit: rests, glides one full length, rests again.
struct MarqueeText: View {
    let text: String
    let font: Font
    /// Pauses the scroll (e.g. while the notch is closed) so it costs nothing when invisible.
    var isActive = true
    var speed: Double = 32
    var gap: CGFloat = 36
    var pause: Double = 1.8

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var start = Date.now

    var body: some View {
        let overflows = textWidth > containerWidth + 1
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !overflows || !isActive)) { context in
            HStack(spacing: gap) {
                label
                if overflows { label }
            }
            .offset(x: overflows ? -offset(at: context.date) : 0)
            // minWidth 0: without it the frame is never narrower than the title, which then pushes the
            // whole row wider than the notch instead of scrolling.
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .clipped()
        .mask {
            LinearGradient(stops: [
                .init(color: overflows ? .clear : .black, location: 0),
                .init(color: .black, location: 0.05),
                .init(color: .black, location: 0.9),
                .init(color: overflows ? .clear : .black, location: 1),
            ], startPoint: .leading, endPoint: .trailing)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
        .onChange(of: text) { start = .now }
        .onChange(of: isActive) { start = .now }
    }

    private var label: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
    }

    private func offset(at date: Date) -> CGFloat {
        let distance = Double(textWidth + gap)
        let cycle = pause + distance / speed
        let phase = date.timeIntervalSince(start).truncatingRemainder(dividingBy: cycle)
        return phase < pause ? 0 : CGFloat((phase - pause) * speed)
    }
}
