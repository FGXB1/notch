import Foundation
import NotchCore

/// Runs `ungive/mediaremote-adapter` through Apple's `/usr/bin/perl`. Since macOS 15.4 only processes with
/// a `com.apple.` bundle identifier may read MediaRemote's now-playing state; perl qualifies, this app doesn't.
@MainActor
final class AdapterClient {
    struct Paths: Sendable {
        var script: URL
        var framework: URL
        /// Plays a silent dummy track for `test` when nothing else is playing; without it the test can only
        /// pass while something is.
        var testClient: URL

        /// Copied into `Contents/Resources/MediaRemoteAdapter` by `Scripts/build-adapter.sh`.
        static var bundled: Paths? {
            guard let directory = Bundle.main.url(forResource: "MediaRemoteAdapter", withExtension: nil) else {
                return nil
            }
            let paths = Paths(script: directory.appendingPathComponent("mediaremote-adapter.pl"),
                              framework: directory.appendingPathComponent("MediaRemoteAdapter.framework"),
                              testClient: directory.appendingPathComponent("MediaRemoteAdapterTestClient"))
            return FileManager.default.fileExists(atPath: paths.script.path) ? paths : nil
        }
    }

    /// MediaRemote command IDs accepted by `send`.
    enum Command: Int {
        case play = 0, pause = 1, togglePlayPause = 2, nextTrack = 4, previousTrack = 5
        case skipBackward15 = 12, skipForward15 = 13
    }

    nonisolated private static let perl = URL(fileURLWithPath: "/usr/bin/perl")

    private let paths: Paths
    private let onMessage: @MainActor (AdapterMessage) -> Void
    private var process: Process?
    private var isRunning = false
    private var restartDelay: Duration = .seconds(1)

    init(paths: Paths, onMessage: @escaping @MainActor (AdapterMessage) -> Void) {
        self.paths = paths
        self.onMessage = onMessage
    }

    /// The adapter's own self-test: exit status 0 means MediaRemote is readable on this macOS version.
    /// The script takes the test client's path as the argument after the framework's.
    static func selfTest(_ paths: Paths) async -> Int32 {
        await run(paths, [paths.testClient.path, "test"])
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        launchStream()
    }

    func stop() {
        isRunning = false
        process?.terminate()
        process = nil
    }

    func send(_ command: Command) {
        fire(["send", String(command.rawValue)])
    }

    func seek(to seconds: TimeInterval) {
        fire(["seek", String(Int64(max(0, seconds) * 1_000_000))])
    }

    // MARK: Private

    private func launchStream() {
        let process = Process()
        process.executableURL = Self.perl
        process.arguments = [paths.script.path, paths.framework.path, "stream", "--micros", "--debounce=40"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        let reader = LineReader { [weak self] line in
            // Parsing (including base64 artwork) stays on the pipe's background queue.
            guard let message = AdapterMessage.parse(line) else { return }
            Task { @MainActor in self?.receive(message) }
        }
        let readHandle = output.fileHandleForReading
        readHandle.readabilityHandler = { handle in
            reader.consume(handle.availableData)
        }
        process.terminationHandler = { [weak self] _ in
            readHandle.readabilityHandler = nil
            Task { @MainActor in self?.streamDidExit() }
        }

        do {
            try process.run()
            self.process = process
            Log.media.info("Adapter stream started")
        } catch {
            Log.media.error("Adapter stream failed to launch: \(error.localizedDescription)")
            streamDidExit()
        }
    }

    private func receive(_ message: AdapterMessage) {
        restartDelay = .seconds(1)
        onMessage(message)
    }

    private func streamDidExit() {
        process = nil
        guard isRunning else { return }
        let delay = restartDelay
        restartDelay = min(restartDelay * 2, .seconds(30))
        Log.media.error("Adapter stream exited; restarting in \(delay)")
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, self.isRunning, self.process == nil else { return }
            self.launchStream()
        }
    }

    private func fire(_ arguments: [String]) {
        let paths = paths
        Task.detached(priority: .userInitiated) {
            _ = await Self.run(paths, arguments)
        }
    }

    @discardableResult
    nonisolated private static func run(_ paths: Paths, _ arguments: [String]) async -> Int32 {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = perl
            process.arguments = [paths.script.path, paths.framework.path] + arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: -1)
            }
        }
    }
}

/// Splits a byte stream into newline-terminated lines. Only touched from the pipe's serial handler queue.
