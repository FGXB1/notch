import AppKit
import Defaults

/// Trackpad feedback. Only perceptible while a finger is resting on a Force Touch trackpad.
@MainActor
public enum Haptics {
    public static func tick() {
        perform(.alignment)
    }

    public static func levelChange() {
        perform(.levelChange)
    }

    private static func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        guard Defaults[.enableHaptics] else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}
