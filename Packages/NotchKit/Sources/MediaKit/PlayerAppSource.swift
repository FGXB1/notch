import AppKit
import Foundation
import NotchCore

/// Fallback when the adapter can't read MediaRemote: Music and Spotify announce their state through
/// distributed notifications, and accept commands over Apple Events. Covers only those two apps.
@MainActor
final class PlayerAppSource {
    private enum Player: String, CaseIterable {
        case music = "com.apple.Music"
        case spotify = "com.spotify.client"

        var notification: String {
            switch self {
            case .music: "com.apple.Music.playerInfo"
            case .spotify: "com.spotify.client.PlaybackStateChanged"
            }
        }
    }

    private let onUpdate: @MainActor (NowPlaying?) -> Void
    private var observers: [NSObjectProtocol] = []
    private var current: Player?

    init(onUpdate: @escaping @MainActor (NowPlaying?) -> Void) {
        self.onUpdate = onUpdate
    }

    func start() {
        let center = DistributedNotificationCenter.default()
        for player in Player.allCases {
            observers.append(center.addObserver(forName: .init(player.notification), object: nil, queue: .main) {
                [weak self] notification in
                let info = notification.userInfo ?? [:]
                let state = info["Player State"] as? String
                let title = info["Name"] as? String
                let artist = info["Artist"] as? String
                let album = info["Album"] as? String
                // Music reports milliseconds in "Total Time"; Spotify reports milliseconds in "Duration".
                let durationMillis = (info["Total Time"] ?? info["Duration"]) as? Double
                let position = info["Playback Position"] as? Double
                MainActor.assumeIsolated {
                    self?.handle(player: player, state: state, title: title, artist: artist, album: album,
                                 duration: durationMillis.map { $0 / 1000 }, position: position)
                }
            })
        }
        Log.media.info("Using Music/Spotify fallback for Now Playing")
    }

    func togglePlayPause() { tell("playpause") }
    func next() { tell("next track") }
    func previous() { tell("previous track") }
    func seek(to seconds: TimeInterval) { tell("set player position to \(Int(seconds))") }

    private func handle(player: Player, state: String?, title: String?, artist: String?, album: String?,
                        duration: TimeInterval?, position: TimeInterval?) {
        guard state != "Stopped", let title, !title.isEmpty else {
            if current == player {
                current = nil
                onUpdate(nil)
            }
            return
        }
        current = player
        onUpdate(NowPlaying(bundleIdentifier: player.rawValue, title: title, artist: artist, album: album,
                            duration: duration, elapsedTime: position, timestamp: position.map { _ in .now },
                            isPlaying: state == "Playing"))
    }

    private func tell(_ command: String) {
        guard let player = current else { return }
        let script = "tell application id \"\(player.rawValue)\" to \(command)"
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            try? process.run()
        }
    }
}
