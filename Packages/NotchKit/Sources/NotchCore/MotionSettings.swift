import Defaults
import SwiftUI

/// A spring expressed the way SwiftUI's modern API (`Spring(duration:bounce:)`) does.
public struct SpringSpec: Codable, Hashable, Sendable {
    public var duration: Double
    public var bounce: Double

    public init(duration: Double, bounce: Double) {
        self.duration = duration
        self.bounce = bounce
    }

    public var animation: Animation { .spring(duration: duration, bounce: bounce) }
}

/// Every timing that shapes how the notch feels. Tuned live from the Motion Lab settings pane.
public struct MotionSettings: Codable, Hashable, Sendable, Defaults.Serializable {
    /// Pointer enters: the closed notch swells slightly, with a little bounce.
    public var hoverBump = SpringSpec(duration: 0.35, bounce: 0.45)
    /// Pointer leaves: the swell settles.
    public var hoverRelease = SpringSpec(duration: 0.35, bounce: 0.05)
    /// Closed → expanded shell morph.
    public var open = SpringSpec(duration: 0.45, bounce: 0.22)
    /// Expanded → closed shell morph.
    public var close = SpringSpec(duration: 0.32, bounce: 0)
    /// Expanded content arrives this long after the shell starts opening.
    public var contentDelay: Double = 0.07
    public var contentIn = SpringSpec(duration: 0.32, bounce: 0)
    /// Expanded content leaves quickly so the shell never collapses over visible content.
    public var contentOutDuration: Double = 0.12
    /// How long the pointer can wander outside an expanded notch before it closes.
    public var exitGrace: Double = 0.12
    /// Closed notch changing between idle, wings, quick peek and HUD.
    public var activity = SpringSpec(duration: 0.42, bounce: 0.28)
    /// A swipe that didn't commit snapping back.
    public var gestureRelease = SpringSpec(duration: 0.38, bounce: 0.35)

    public init() {}

    public static let standard = MotionSettings()

    // Tolerant decoding: settings saved by an older build keep their tuned values, new fields get defaults.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = MotionSettings()
        hoverBump = try container.decodeIfPresent(SpringSpec.self, forKey: .hoverBump) ?? fallback.hoverBump
        hoverRelease = try container.decodeIfPresent(SpringSpec.self, forKey: .hoverRelease) ?? fallback.hoverRelease
        open = try container.decodeIfPresent(SpringSpec.self, forKey: .open) ?? fallback.open
        close = try container.decodeIfPresent(SpringSpec.self, forKey: .close) ?? fallback.close
        contentDelay = try container.decodeIfPresent(Double.self, forKey: .contentDelay) ?? fallback.contentDelay
        contentIn = try container.decodeIfPresent(SpringSpec.self, forKey: .contentIn) ?? fallback.contentIn
        contentOutDuration = try container.decodeIfPresent(Double.self, forKey: .contentOutDuration)
            ?? fallback.contentOutDuration
        exitGrace = try container.decodeIfPresent(Double.self, forKey: .exitGrace) ?? fallback.exitGrace
        activity = try container.decodeIfPresent(SpringSpec.self, forKey: .activity) ?? fallback.activity
        gestureRelease = try container.decodeIfPresent(SpringSpec.self, forKey: .gestureRelease)
            ?? fallback.gestureRelease
    }
}
