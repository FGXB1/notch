import Activities
import AppKit
import Defaults
import NotchCore
import SwiftUI

/// Replacement for the system volume/brightness HUD, drawn in the notch's wings: the symbol hugs the
/// leading edge, the level bar (and optional percentage) the trailing edge, with equal insets.
struct HUDView: View {
    let event: HUDEvent
    let metrics: NotchMetrics

    @Default(.volumeProgressStyle) private var volumeStyle
    @Default(.brightnessProgressStyle) private var brightnessStyle

    var body: some View {
        let inset = (metrics.compactWing - metrics.wingGlyph) / 2
        let level = event.isMuted ? 0 : event.level
        WingsLayout(metrics: metrics, wing: event.showsPercentage ? metrics.wideWing : metrics.hudWing) {
            symbol
                .font(.system(size: metrics.wingGlyph * 0.7, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: metrics.wingGlyph)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, inset)
        } trailing: {
            HStack(spacing: 7) {
                LevelBar(level: level, style: event.kind == .brightness ? brightnessStyle : volumeStyle)
                if event.showsPercentage {
                    Text("\(Int((level * 100).rounded()))")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(value: level))
                        .frame(width: 24, alignment: .trailing)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, inset)
        }
    }

    @ViewBuilder private var symbol: some View {
        if let custom = event.symbol {
            Image(systemName: event.isMuted ? "speaker.slash.fill" : custom)
        } else {
            switch event.kind {
            case .volume:
                Image(systemName: event.isMuted ? "speaker.slash.fill" : "speaker.wave.3.fill",
                      variableValue: event.isMuted ? 0 : event.level)
            case .brightness:
                Image(systemName: event.level < 0.5 ? "sun.min.fill" : "sun.max.fill")
            case .keyboardBacklight:
                Image(systemName: "light.max")
            }
        }
    }
}

private struct LevelBar: View {
    let level: Double
    let style: HUDProgressStyle

    var body: some View {
        Capsule()
            .fill(.white.opacity(0.2))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(fill)
                        .frame(width: max(proxy.size.height, proxy.size.width * level))
                        .shadow(color: style == .stylized ? glow.opacity(0.8) : .clear, radius: 4)
                        .opacity(level > 0 ? 1 : 0)
                }
            }
            .frame(width: 38, height: style == .stylized ? 6 : 5)
    }

    private var accent: Color { Color(nsColor: .controlAccentColor) }
    private var glow: Color { accent.mix(with: .white, by: 0.3) }

    private var fill: AnyShapeStyle {
        switch style {
        case .white: AnyShapeStyle(.white)
        case .accent: AnyShapeStyle(accent)
        case .stylized:
            AnyShapeStyle(LinearGradient(colors: [accent, accent.mix(with: .white, by: 0.55)],
                                         startPoint: .leading, endPoint: .trailing))
        }
    }
}
