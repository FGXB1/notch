import Foundation

/// The system's current now-playing item, as reported by MediaRemote.
public struct NowPlaying: Equatable, Sendable {
    public var bundleIdentifier: String
    /// Set when the player is a helper process (e.g. a browser's WebKit GPU process).
    public var parentBundleIdentifier: String?
    public var processIdentifier: Int32?
    public var title: String
    public var artist: String?
    public var album: String?
    public var duration: TimeInterval?
    /// Elapsed time as of `timestamp`; extrapolate with `elapsed(at:)` instead of polling.
    public var elapsedTime: TimeInterval?
    public var timestamp: Date?
    public var playbackRate: Double
    public var isPlaying: Bool

    public init(bundleIdentifier: String, parentBundleIdentifier: String? = nil, processIdentifier: Int32? = nil,
                title: String, artist: String? = nil, album: String? = nil, duration: TimeInterval? = nil,
                elapsedTime: TimeInterval? = nil, timestamp: Date? = nil, playbackRate: Double = 1,
                isPlaying: Bool) {
        self.bundleIdentifier = bundleIdentifier
        self.parentBundleIdentifier = parentBundleIdentifier
        self.processIdentifier = processIdentifier
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsedTime = elapsedTime
        self.timestamp = timestamp
        self.playbackRate = playbackRate
        self.isPlaying = isPlaying
    }

    /// The app the user thinks of as the player.
    public var appBundleIdentifier: String { parentBundleIdentifier ?? bundleIdentifier }

    /// Identifies the track, ignoring playback state, so a pause doesn't look like a track change.
    public var trackIdentity: String {
        [appBundleIdentifier, title, artist ?? "", album ?? ""].joined(separator: "\u{1F}")
    }

    public func elapsed(at date: Date) -> TimeInterval? {
        guard let elapsedTime else { return nil }
        var elapsed = elapsedTime
        if isPlaying, let timestamp {
            elapsed += date.timeIntervalSince(timestamp) * playbackRate
        }
        elapsed = max(0, elapsed)
        if let duration, duration > 0 {
            elapsed = min(elapsed, duration)
        }
        return elapsed
    }

    public func progress(at date: Date) -> Double? {
        guard let duration, duration > 0, let elapsed = elapsed(at: date) else { return nil }
        return elapsed / duration
    }
}
