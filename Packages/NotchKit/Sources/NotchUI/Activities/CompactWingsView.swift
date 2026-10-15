import Activities
import CalendarKit
import Defaults
import MediaKit
import NotchCore
import SwiftUI
import SystemKit

/// A live activity rendered in the two wings either side of the hardware notch.
struct CompactWingsView: View {
    let activity: LiveActivity
    let metrics: NotchMetrics
    let media: MediaController
    let calendar: CalendarController
    private let focus = FocusMonitor.shared
    @Default(.replaceWaveformDuringFocus) private var replaceWaveformDuringFocus

    var body: some View {
        switch activity.id {
        case let .calendarEvent(id):
            CalendarWings(event: calendar.event(id: id), metrics: metrics)
        case .lock:
            LockChin(metrics: metrics)
        default:
            WingsLayout(metrics: metrics, wing: metrics.compactWing) {
                leading
            } trailing: {
                trailing
            }
        }
    }

    @ViewBuilder private var leading: some View {
        switch activity.id {
        case .nowPlaying:
            Color.clear // ArtworkLayer draws the artwork here
        case let .demo(symbol):
            Image(systemName: symbol)
                .font(.system(size: metrics.wingGlyph * 0.68, weight: .semibold))
                .foregroundStyle(DemoPalette.tint(for: symbol))
                .symbolEffect(.bounce, value: activity.updatedAt)
        default:
            Image(systemName: activity.id.placeholderSymbol)
                .font(.system(size: metrics.wingGlyph * 0.68, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder private var trailing: some View {
        switch activity.id {
        case .nowPlaying:
            if replaceWaveformDuringFocus, let mode = focus.active {
                Image(systemName: mode.symbol)
                    .font(.system(size: metrics.wingGlyph * 0.68, weight: .semibold))
                    .foregroundStyle(FocusTint.color(mode.tint))
                    .transition(.blurReplace)
            } else {
                EqualizerView(isPlaying: media.nowPlaying?.isPlaying ?? false, tint: media.palette.accent,
                              size: CGSize(width: metrics.wingGlyph, height: metrics.wingGlyph * 0.64))
                    .transition(.blurReplace)
            }
        default:
            // Elapsed time proves the wings update live without re-layout of the shell.
            Text(activity.startedAt, style: .timer)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

/// Places content in the wings of a closed-height notch, leaving the camera housing in the middle empty.
struct WingsLayout<Leading: View, Trailing: View>: View {
    let metrics: NotchMetrics
    let wing: CGFloat
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 0) {
            leading.frame(width: wing)
            Color.clear.frame(width: metrics.closed.width)
            trailing.frame(width: wing)
        }
        .frame(height: metrics.closed.height)
    }
}

enum DemoPalette {
    static func tint(for symbol: String) -> Color {
        let palette: [Color] = [.orange, .pink, .mint, .cyan, .yellow, .purple]
        let index = symbol.unicodeScalars.reduce(0) { $0 &+ Int($1.value) } % palette.count
        return palette[index]
    }
}

extension ActivityKind {
    var placeholderSymbol: String {
        switch self {
        case .nowPlaying: "music.note"
        case .calendarEvent: "calendar"
        case .battery: "battery.100percent"
        case .connectivity: "airpods"
        case .focus: "moon.fill"
        case .lock: "lock.fill"
        case let .demo(symbol): symbol
        }
    }
}

/// The padlock in a short chin under the camera, like Face ID on the iPhone's Dynamic Island. It morphs open
/// when the Mac unlocks, just before the chin retracts.
private struct LockChin: View {
    let metrics: NotchMetrics
    private let lock = LockMonitor.shared

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: metrics.closed.height)
            Image(systemName: lock.isIndicatorOpen ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace.magic(fallback: .downUp.byLayer)))
                .frame(maxHeight: .infinity)
        }
        .frame(width: metrics.lock.width, height: metrics.lock.height)
    }
}
