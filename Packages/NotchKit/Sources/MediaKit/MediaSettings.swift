import Defaults

public extension Defaults.Keys {
    static let enableNowPlaying = Key<Bool>("enableNowPlaying", default: true)
    /// Briefly drop the notch down with the new title whenever the track changes.
    static let peekOnTrackChange = Key<Bool>("peekOnTrackChange", default: true)
    /// Don't show the player while its own app is frontmost.
    static let hideWhileSourceIsActive = Key<Bool>("hideWhileSourceIsActive", default: false)
    /// Seconds a paused player keeps its wings before the notch goes idle.
    static let hideIdleDuration = Key<Double>("hideIdleDuration", default: 15)
}
