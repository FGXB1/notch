import Activities
import AppKit
import Defaults
import NotchCore
import Observation
import SwiftUI

/// Now Playing for the whole app: reads the system's now-playing state, controls playback, and keeps the
/// `.nowPlaying` live activity in sync (wings while playing, a quick peek on track change, idle hiding).
@MainActor
@Observable
public final class MediaController {
    public enum Source: Equatable, Sendable {
        case starting
        /// mediaremote-adapter: every app that reports to MediaRemote (browsers, podcasts, ...).
        case adapter
        /// Only Music and Spotify, via their distributed notifications.
        case playerApps
        case disabled
    }

    public static let shared = MediaController()

    public private(set) var source: Source = .starting
    public private(set) var nowPlaying: NowPlaying?
    public private(set) var artwork: NSImage?
    /// Changes whenever the artwork image changes, for transitions.
    public private(set) var artworkRevision = 0
    public private(set) var palette: ArtworkPalette = .neutral
    public private(set) var appIcon: NSImage?

    @ObservationIgnored private let activities: ActivityCenter
    @ObservationIgnored private var stream = AdapterStream()
    @ObservationIgnored private var adapter: AdapterClient?
    @ObservationIgnored private var playerApps: PlayerAppSource?
    @ObservationIgnored private var lastArtworkBase64: String?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var idleTask: Task<Void, Never>?
    @ObservationIgnored private var hasReceivedFirstUpdate = false
    @ObservationIgnored private var frontmostBundleIdentifier: String?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    public init(activities: ActivityCenter = .shared) {
        self.activities = activities
    }

    // MARK: Lifecycle

    public func start() {
        frontmostBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let bundle = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                .bundleIdentifier
            MainActor.assumeIsolated {
                self?.frontmostBundleIdentifier = bundle
                self?.syncActivity(trackChanged: false)
            }
        })

        Task { [weak self] in
            for await enabled in Defaults.updates(.enableNowPlaying) {
                await self?.setEnabled(enabled)
            }
        }
    }

    /// Ends the adapter's child process (it would otherwise linger until its next write).
    public func stop() {
        adapter?.stop()
    }

    private func setEnabled(_ enabled: Bool) async {
        if !enabled {
            adapter?.stop()
            adapter = nil
            playerApps = nil
            source = .disabled
            update(nowPlaying: nil)
            return
        }
        guard adapter == nil, playerApps == nil else { return }
        source = .starting
        if let paths = AdapterClient.Paths.bundled, await AdapterClient.isFunctional(paths) {
            let adapter = AdapterClient(paths: paths) { [weak self] message in self?.receive(message) }
            adapter.start()
            self.adapter = adapter
            source = .adapter
        } else {
            Log.media.error("mediaremote-adapter unavailable; falling back to Music/Spotify")
            let playerApps = PlayerAppSource { [weak self] nowPlaying in self?.update(nowPlaying: nowPlaying) }
            playerApps.start()
            self.playerApps = playerApps
            source = .playerApps
        }
    }

    // MARK: Commands

    public func togglePlayPause() {
        guard var item = nowPlaying else { return }
        // Optimistic: the UI flips immediately; the adapter's echo confirms a moment later.
        let now = Date()
        item.elapsedTime = item.elapsed(at: now)
        item.timestamp = now
        item.isPlaying.toggle()
        withAnimation(.snappy(duration: 0.25)) { nowPlaying = item }
        adapter?.send(.togglePlayPause)
        playerApps?.togglePlayPause()
        syncActivity(trackChanged: false)
    }

    public func next() {
        adapter?.send(.nextTrack)
        playerApps?.next()
    }

    public func previous() {
        adapter?.send(.previousTrack)
        playerApps?.previous()
    }

    public func seek(to seconds: TimeInterval) {
        guard var item = nowPlaying else { return }
        item.elapsedTime = seconds
        item.timestamp = .now
        nowPlaying = item
        adapter?.seek(to: seconds)
        playerApps?.seek(to: seconds)
    }

    /// Horizontal swipe on the notch: left skips forward, right goes back. Returns false when nothing plays.
    public func handleSwipe(_ action: SwipeTracker.Action) -> Bool {
        guard nowPlaying != nil else { return false }
        switch action {
        case .swipeLeft: next()
        case .swipeRight: previous()
        case .pullDown, .pushUp: return false
        }
        return true
    }

    public func openSourceApp() {
        guard let bundle = nowPlaying?.appBundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: Updates

    private func receive(_ message: AdapterMessage) {
        stream.apply(message)
        update(nowPlaying: stream.nowPlaying)

        let base64 = stream.nowPlaying == nil ? nil : stream.artworkBase64
        if base64 != lastArtworkBase64 {
            lastArtworkBase64 = base64
            decodeArtwork(base64)
        }
    }

    private func update(nowPlaying new: NowPlaying?) {
        let old = nowPlaying
        let trackChanged = new?.trackIdentity != old?.trackIdentity
        guard new != old else { return }

        if trackChanged || new?.isPlaying != old?.isPlaying {
            withAnimation(.snappy(duration: 0.3)) { nowPlaying = new }
        } else {
            nowPlaying = new // elapsed-time resync: nothing visible should animate
        }
        if new?.appBundleIdentifier != old?.appBundleIdentifier {
            appIcon = new.flatMap { item in
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.appBundleIdentifier)
                    .map { NSWorkspace.shared.icon(forFile: $0.path) }
            }
        }
        if source == .playerApps, trackChanged {
            // The fallback has no artwork; show the player's icon in its place.
            setArtwork(nil, palette: .neutral)
        }
        syncActivity(trackChanged: trackChanged)
    }

    private func decodeArtwork(_ base64: String?) {
        artworkTask?.cancel()
        guard let base64 else {
            setArtwork(nil, palette: .neutral)
            return
        }
        artworkTask = Task { [weak self] in
            let decoded = await Task.detached(priority: .userInitiated) { DecodedArtwork.decode(base64: base64) }.value
            guard !Task.isCancelled, let self else { return }
            let image = decoded.map { NSImage(cgImage: $0.image, size: NSSize(width: $0.image.width, height: $0.image.height)) }
            self.setArtwork(image, palette: decoded?.palette ?? .neutral)
        }
    }

    private func setArtwork(_ image: NSImage?, palette: ArtworkPalette) {
        withAnimation(.smooth(duration: 0.4)) {
            artwork = image
            artworkRevision += 1
            self.palette = palette
        }
    }

    // MARK: Activity

    private func syncActivity(trackChanged: Bool) {
        let isFirstUpdate = !hasReceivedFirstUpdate
        hasReceivedFirstUpdate = true

        guard let item = nowPlaying else {
            idleTask?.cancel()
            idleTask = nil
            activities.end(.nowPlaying)
            return
        }
        if Defaults[.hideWhileSourceIsActive], frontmostBundleIdentifier == item.appBundleIdentifier {
            activities.end(.nowPlaying)
            return
        }

        if item.isPlaying {
            idleTask?.cancel()
            idleTask = nil
            if trackChanged || !activities.isLive(.nowPlaying) {
                activities.upsert(.nowPlaying)
            }
            if trackChanged, !isFirstUpdate, Defaults[.peekOnTrackChange] {
                activities.post(.nowPlaying(title: item.title, artist: item.artist))
            }
        } else if activities.isLive(.nowPlaying), idleTask == nil {
            let delay = Defaults[.hideIdleDuration]
            idleTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                self.idleTask = nil
                if self.nowPlaying?.isPlaying != true {
                    self.activities.end(.nowPlaying)
                }
            }
        }
    }
}
