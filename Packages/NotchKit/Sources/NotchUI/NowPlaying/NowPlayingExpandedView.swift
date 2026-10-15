import MediaKit
import SwiftUI

/// The expanded player. The artwork itself is drawn by `ArtworkLayer`; this view leaves a slot for it.
struct NowPlayingExpandedView: View {
    let item: NowPlaying
    let media: MediaController
    let isActive: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 16) {
                Color.clear
                    .frame(width: NowPlayingLayout.expandedArtwork, height: NowPlayingLayout.expandedArtwork)

                VStack(alignment: .leading, spacing: 2) {
                    MarqueeText(text: item.title, font: .system(size: 15, weight: .semibold), isActive: isActive)
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(media.palette.accent.opacity(0.9))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    ScrubberView(item: item, tint: media.palette.accent, isActive: isActive, onSeek: media.seek)
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .frame(height: NowPlayingLayout.expandedArtwork)
            }

            controls
        }
    }

    private var subtitle: String {
        [item.artist, item.album].compactMap(\.self).joined(separator: " — ")
    }

    private var controls: some View {
        HStack {
            Button(action: media.openSourceApp) {
                Label {
                    Text("Open Player")
                } icon: {
                    if let icon = media.appIcon {
                        Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                    } else {
                        Image(systemName: "app.fill")
                    }
                }
            }
            .buttonStyle(NotchButtonStyle(size: 28))
            .help("Open the player")

            Spacer()

            Button("Previous", systemImage: "backward.fill", action: media.previous)
                .buttonStyle(NotchButtonStyle(size: 34, fontSize: 16))
            Button(item.isPlaying ? "Pause" : "Play", systemImage: item.isPlaying ? "pause.fill" : "play.fill",
                   action: media.togglePlayPause)
                .contentTransition(.symbolEffect(.replace))
                .buttonStyle(NotchButtonStyle(size: 40, fontSize: 22))
            Button("Next", systemImage: "forward.fill", action: media.next)
                .buttonStyle(NotchButtonStyle(size: 34, fontSize: 16))

            Spacer()

            Color.clear.frame(width: 28, height: 28)
        }
    }
}
