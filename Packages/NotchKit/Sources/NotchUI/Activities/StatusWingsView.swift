import Activities
import Defaults
import NotchCore
import SwiftUI

/// Status notices (battery, headphones, Focus) shown HUD-style in the wings, like the Dynamic Island's
/// charging and AirPods indicators, instead of dropping the notch down.
struct StatusWingsView: View {
    let notice: Notice
    let metrics: NotchMetrics

    @Default(.hideBatteryPercentage) private var hideBatteryPercentage

    var body: some View {
        let inset = (metrics.compactWing - metrics.wingGlyph) / 2
        WingsLayout(metrics: metrics, wing: notice.kind.wingWidth == .wide ? metrics.wideWing : metrics.hudWing) {
            leading
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, inset)
        } trailing: {
            trailing
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, inset)
        }
    }

    @ViewBuilder private var leading: some View {
        switch notice.kind {
        case let .battery(_, _, event):
            Text(Self.title(for: event))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Self.tint(for: event))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        case let .device(_, symbol, _, _):
            Image(systemName: symbol)
                .font(.system(size: metrics.wingGlyph * 0.72, weight: .medium))
                .foregroundStyle(.white)
                .symbolEffect(.bounce, value: notice.id)
        case let .focus(_, symbol, tint, isOn):
            Image(systemName: symbol)
                .font(.system(size: metrics.wingGlyph * 0.68, weight: .semibold))
                .foregroundStyle(isOn ? FocusTint.color(tint) : .white.opacity(0.5))
                .symbolEffect(.bounce, value: notice.id)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var trailing: some View {
        switch notice.kind {
        case let .battery(level, isCharging, event):
            HStack(spacing: 5) {
                if !hideBatteryPercentage {
                    Text(level, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                BatteryGlyph(level: level, tint: Self.tint(for: event), isCharging: isCharging)
            }
        case let .device(_, _, battery, event):
            if let battery {
                let isLow = event == .lowBattery || battery <= Defaults[.lowConnectBatteryThreshold] / 100
                HStack(spacing: 5) {
                    Text(battery, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    ProgressRing(progress: battery, tint: isLow ? .red : .green, size: metrics.wingGlyph * 0.72,
                                 lineWidth: 2.5)
                }
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: metrics.wingGlyph * 0.7))
                    .foregroundStyle(.green)
            }
        case let .focus(_, _, tint, isOn):
            Text(isOn ? "On" : "Off")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isOn ? FocusTint.color(tint) : .white.opacity(0.5))
        default:
            EmptyView()
        }
    }

    private static func title(for event: BatteryEvent) -> String {
        switch event {
        case .charging: "Charging"
        case .low: "Low Battery"
        case .lowPowerMode: "Low Power"
        }
    }

    private static func tint(for event: BatteryEvent) -> Color {
        switch event {
        case .charging: .green
        case .low: .red
        case .lowPowerMode: .yellow
        }
    }
}

/// A battery drawn to the exact level (SF Symbols only have quarter steps).
struct BatteryGlyph: View {
    let level: Double
    let tint: Color
    let isCharging: Bool

    var body: some View {
        HStack(spacing: 1) {
            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                .strokeBorder(.white.opacity(0.4), lineWidth: 1)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.75, style: .continuous)
                        .fill(tint)
                        .frame(width: max(2, 21 * min(1, max(0, level))))
                        .padding(2)
                }
                .overlay {
                    if isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 1)
                    }
                }
                .frame(width: 25, height: 12)
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(.white.opacity(0.4))
                .frame(width: 1.5, height: 4)
        }
    }
}

enum FocusTint {
    static func color(_ name: String) -> Color {
        switch name {
        case "mint": .mint
        case "blue": .blue
        case "teal": .teal
        case "purple": .purple
        case "green": .green
        case "cyan": .cyan
        case "orange": .orange
        case "pink": .pink
        case "red": .red
        case "yellow": .yellow
        case "brown": .brown
        case "gray", "grey": .gray
        default: .indigo
        }
    }
}
