import SwiftUI

/// Round icon button for the dark notch: soft highlight on hover, a quick squish on press.
struct NotchButtonStyle: ButtonStyle {
    var size: CGFloat = 30
    var fontSize: CGFloat = 15

    func makeBody(configuration: Configuration) -> some View {
        HoverHighlight(configuration: configuration, size: size, fontSize: fontSize)
    }

    private struct HoverHighlight: View {
        let configuration: Configuration
        let size: CGFloat
        let fontSize: CGFloat
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .labelStyle(.iconOnly)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(.white.opacity(isHovering ? 0.12 : 0), in: .circle)
                .contentShape(.circle)
                .scaleEffect(configuration.isPressed ? 0.86 : 1)
                .animation(.snappy(duration: 0.2), value: configuration.isPressed)
                .animation(.smooth(duration: 0.15), value: isHovering)
                .onHover { isHovering = $0 }
        }
    }
}
