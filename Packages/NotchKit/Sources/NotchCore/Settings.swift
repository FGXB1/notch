import Defaults
import Foundation

/// Which displays get a notch.
public enum DisplayTarget: String, CaseIterable, Codable, Sendable, Defaults.Serializable {
    case builtIn
    case main
    case all
}

/// How a HUD draws its level.
public enum HUDProgressStyle: String, CaseIterable, Sendable, Defaults.Serializable {
    case white
    /// The system accent color.
    case accent
    /// An accent gradient with a soft glow.
    case stylized
}

/// A hairline around the open notch, so the black shape doesn't vanish into a dark background.
public enum ContrastOutline: String, CaseIterable, Sendable, Defaults.Serializable {
    /// When the wallpaper under the notch is dark, or in Dark Mode.
    case automatic
    case always
    case never
}

/// How fast a HUD's level follows key presses.
public enum HUDSpeed: String, CaseIterable, Sendable, Defaults.Serializable {
    case instant
    case fast
    case smooth
}

/// The expanded notch's pages.
public enum NotchTab: String, Sendable {
    /// Now Playing and the calendar.
    case home
    /// Files parked for later.
    case tray
}

public extension Defaults.Keys {
    /// The welcome window was finished. Until then, nothing asks for a permission on its own: the welcome
    /// asks for each one in turn, with an explanation.
    static let hasCompletedOnboarding = Key<Bool>("hasCompletedOnboarding", default: false)

    static let expandNotchOnHover = Key<Bool>("expandNotchOnHover", default: true)
    /// Seconds the pointer must rest on the notch before it expands.
    static let hoverDuration = Key<Double>("hoverDuration", default: 0.15)
    static let enableHaptics = Key<Bool>("enableHaptics", default: true)

    static let displayTarget = Key<DisplayTarget>("displayTarget", default: .builtIn)
    /// Draw a notch on displays that don't have one.
    static let forceSimulatedNotch = Key<Bool>("forceSimulatedNotch", default: false)
    /// Fine-tuning added to the measured hardware notch, in points.
    static let notchAdjustedWidth = Key<Double>("notchAdjustedWidth", default: 0)
    static let notchAdjustedHeight = Key<Double>("notchAdjustedHeight", default: 0)

    // Gestures (two-finger swipes on the notch)
    static let swipeToToggle = Key<Bool>("swipeToToggle", default: true)
    static let swipeToDismiss = Key<Bool>("swipeToDismiss", default: true)
    static let swipeToSkip = Key<Bool>("swipeToSkip", default: true)
    static let swipeToCycleActivity = Key<Bool>("swipeToCycleActivity", default: true)
    /// Gestures follow the fingers even when "natural scrolling" is off.
    static let naturalMovement = Key<Bool>("naturalMovement", default: true)

    /// Seconds a quick peek stays up.
    static let peekDuration = Key<Double>("peekDuration", default: 2.5)
    static let hudDuration = Key<Double>("hudDuration", default: 1.5)
    static let hudSpeed = Key<HUDSpeed>("hudSpeed", default: .smooth)
    static let volumeProgressStyle = Key<HUDProgressStyle>("volumeProgressStyle", default: .white)
    static let brightnessProgressStyle = Key<HUDProgressStyle>("brightnessProgressStyle", default: .white)
    static let showVolumePercentage = Key<Bool>("showVolumePercentage", default: false)
    static let showBrightnessPercentage = Key<Bool>("showBrightnessPercentage", default: false)

    static let contrastOutline = Key<ContrastOutline>("contrastOutline", default: .automatic)
    /// A blur around the open notch that fades out with distance.
    static let progressiveBlur = Key<Bool>("progressiveBlur", default: true)

    // Hiding
    /// Hide the notch on a display while an app is full screen there.
    static let hideInFullScreen = Key<Bool>("hideInFullScreen", default: false)
    /// ...but still show volume and brightness changes.
    static let showHUDsInFullScreen = Key<Bool>("showHUDsInFullScreen", default: true)
    /// Leave Notch's windows out of screenshots and screen recordings.
    static let hideFromScreenCapture = Key<Bool>("hideFromScreenCapture", default: false)

    // File tray
    static let enableFileTray = Key<Bool>("enableFileTray", default: true)
    /// Dragging a file onto the notch opens it on the tray.
    static let openTrayOnDrag = Key<Bool>("openTrayOnDrag", default: true)
    /// Reopen on whichever page was showing last, instead of always Home.
    static let rememberLastTab = Key<Bool>("rememberLastTab", default: true)

    static let motion = Key<MotionSettings>("motion", default: .standard)
    /// Debug: play every notch animation at 1/5 speed.
    static let slowAnimations = Key<Bool>("slowAnimations", default: false)
}
