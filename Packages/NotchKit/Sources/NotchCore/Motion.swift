import Defaults
import SwiftUI

/// Resolves the animations the notch uses, applying the Motion Lab settings and the slow-motion toggle.
@MainActor
public enum Motion {
    private static var settings: MotionSettings { Defaults[.motion] }
    private static var speed: Double { Defaults[.slowAnimations] ? 0.2 : 1 }

    public static var hoverBump: Animation { settings.hoverBump.animation.speed(speed) }
    public static var hoverRelease: Animation { settings.hoverRelease.animation.speed(speed) }
    public static var open: Animation { settings.open.animation.speed(speed) }
    public static var close: Animation { settings.close.animation.speed(speed) }
    public static var activity: Animation { settings.activity.animation.speed(speed) }
    public static var gestureRelease: Animation { settings.gestureRelease.animation.speed(speed) }

    /// Level changes inside an already-visible HUD: quick and undamped so held keys feel continuous.
    public static var hudLevel: Animation {
        switch Defaults[.hudSpeed] {
        case .instant: .linear(duration: 0)
        case .fast: .snappy(duration: 0.1).speed(speed)
        case .smooth: .smooth(duration: 0.2).speed(speed)
        }
    }

    public static var contentIn: Animation {
        settings.contentIn.animation.delay(settings.contentDelay).speed(speed)
    }

    public static var contentOut: Animation {
        .smooth(duration: settings.contentOutDuration).speed(speed)
    }

    public static var exitGrace: Duration { .seconds(settings.exitGrace / speed) }

    /// Switching pages inside the expanded notch.
    public static var tabSwitch: Animation { .spring(duration: 0.4, bounce: 0.12).speed(speed) }
}
