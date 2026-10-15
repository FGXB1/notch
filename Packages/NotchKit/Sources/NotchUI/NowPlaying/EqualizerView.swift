import AudioTap
import SwiftUI

/// Bars beside the notch while media plays: the live spectrum from the system audio tap when it's
/// delivering, otherwise a procedural animation; frozen and dimmed when paused.
struct EqualizerView: View {
    let isPlaying: Bool
    let tint: Color
    var size = CGSize(width: 20, height: 14)

    private static let speeds: [Double] = [5.3, 7.1, 4.4, 6.2]
    private static let phases: [Double] = [0, 1.7, 3.1, 0.9]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !isPlaying)) { context in
            // Read straight from the tap each frame (not observed), so audio never invalidates the view tree.
            let live = isPlaying ? LiveWaveform.shared.levels() : nil
            Canvas { canvas, size in
                let time = context.date.timeIntervalSinceReferenceDate
                let count = Self.speeds.count
                let spacing: CGFloat = 2.5
                let width = (size.width - spacing * CGFloat(count - 1)) / CGFloat(count)
                for index in 0..<count {
                    let level: Double = if let live, index < live.count {
                        0.14 + 0.86 * Double(live[index])
                    } else if isPlaying {
                        0.3 + 0.7 * abs(sin(time * Self.speeds[index] + Self.phases[index])
                            * cos(time * Self.speeds[index] * 0.37))
                    } else {
                        0.22
                    }
                    let height = max(width, size.height * level)
                    let rect = CGRect(x: CGFloat(index) * (width + spacing), y: (size.height - height) / 2,
                                      width: width, height: height)
                    canvas.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .color(tint))
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .opacity(isPlaying ? 1 : 0.55)
        .animation(.smooth(duration: 0.3), value: isPlaying)
    }
}
