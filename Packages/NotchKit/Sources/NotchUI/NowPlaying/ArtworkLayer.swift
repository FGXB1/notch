import Activities
import MediaKit
import NotchCore
import SwiftUI

/// Where artwork sits in each presentation. Shared by the artwork layer and the views that leave a slot
/// for it, so they can't drift apart.
enum NowPlayingLayout {
    static let expandedArtwork: CGFloat = 84
    static let expandedPadding: CGFloat = 22
    static let expandedTopGap: CGFloat = 8
    static let peekArtwork: CGFloat = 30
    static let peekPadding: CGFloat = 20
    static let calendarColumnWidth: CGFloat = 196
    static let columnSpacing: CGFloat = 20
    /// How far a page slides while switching between Home and the tray.
    static let pageShift: CGFloat = 36
}

/// One artwork view for every presentation. It never re-lays out: moving between the wing, the quick
/// peek and the expanded player is a scale + offset, so it rides the same spring as the shell.
struct ArtworkLayer: View {
    let controller: NotchController
    let media: MediaController

    private struct Placement {
        /// Center, relative to the top-center of the notch.
        var center: CGPoint
        var side: CGFloat
        var cornerRadius: CGFloat
        var isVisible: Bool
    }

    var body: some View {
        let placement = placement
        let base = NowPlayingLayout.expandedArtwork

        ArtworkImage(media: media)
            .frame(width: base, height: base)
            .clipShape(.rect(cornerRadius: placement.cornerRadius * base / placement.side, style: .continuous))
            .scaleEffect(placement.side / base)
            .offset(x: placement.center.x, y: placement.center.y - base / 2)
            .opacity(placement.isVisible ? 1 : 0)
            .allowsHitTesting(false)
    }

    private var placement: Placement {
        let metrics = controller.metrics
        let layout = NowPlayingLayout.self
        let hidden = Placement(center: CGPoint(x: 0, y: metrics.closed.height / 2), side: 12, cornerRadius: 3,
                               isVisible: false)
        guard media.nowPlaying != nil else { return hidden }

        switch controller.presentation {
        case .expanded:
            let side = layout.expandedArtwork
            // On the tray page the artwork leaves with the rest of Home, sliding the same way.
            let onHome = controller.tab == .home
            return Placement(center: CGPoint(x: -metrics.expanded.width / 2 + layout.expandedPadding + side / 2
                                                 - (onHome ? 0 : layout.pageShift),
                                             y: metrics.closed.height + layout.expandedTopGap + side / 2),
                             side: side, cornerRadius: 16, isVisible: onHome)
        case let .compact(activity) where activity.id == .nowPlaying:
            return Placement(center: CGPoint(x: -(metrics.closed.width + metrics.compactWing) / 2,
                                             y: metrics.closed.height / 2),
                             side: metrics.wingGlyph, cornerRadius: metrics.wingGlyph * 0.27, isVisible: true)
        case let .peek(notice):
            guard case .nowPlaying = notice.kind else { return hidden }
            let side = layout.peekArtwork
            return Placement(center: CGPoint(x: -metrics.peek.width / 2 + layout.peekPadding + side / 2,
                                             y: (metrics.closed.height + metrics.peek.height) / 2),
                             side: side, cornerRadius: 8, isVisible: true)
        default:
            return hidden
        }
    }
}

/// The artwork itself, or the player's app icon when there's none. Cross-fades on change.
struct ArtworkImage: View {
    let media: MediaController

    var body: some View {
        ZStack {
            Group {
                if let artwork = media.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else if let icon = media.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(10)
                        .background(.white.opacity(0.1))
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.white.opacity(0.1))
                }
            }
            .id(media.artworkRevision)
            .transition(.blurReplace)
        }
    }
}
