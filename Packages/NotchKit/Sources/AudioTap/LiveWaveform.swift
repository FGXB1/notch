import Defaults
import MediaKit
import NotchCore
import Observation
import PrivateAPI

public extension Defaults.Keys {
    /// Drive the equalizer from the audio actually playing, instead of the procedural animation.
    static let liveWaveform = Key<Bool>("liveWaveform", default: true)
}

/// Runs the system audio tap only while something plays (and the setting is on), and hands its levels to
/// the equalizer. Stopping waits a few seconds so pausing between tracks doesn't rebuild the tap.
@MainActor
@Observable
public final class LiveWaveform {
    public static let shared = LiveWaveform()

    public private(set) var isCapturing = false

    private let tap = SystemAudioTap()
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    @ObservationIgnored private var settingsTask: Task<Void, Never>?

    public init() {}

    public func start() {
        settingsTask = Task { [weak self] in
            for await _ in Defaults.updates([.liveWaveform, .hasCompletedOnboarding]) {
                self?.update()
            }
        }
        observePlayback()
    }

    /// Live band levels (0...1, bass first), or nil to use the procedural bars: not capturing, no
    /// permission, or nothing audible lately. Cheap and thread-safe; call it every frame.
    public nonisolated func levels() -> [Float]? {
        tap.levels()
    }

    /// System Audio Recording permission; nil if it can't be checked.
    public var permission: TCC.Status? {
        TCC.status(TCC.audioCapture)
    }

    /// Shows the System Audio Recording prompt by starting the tap briefly (creating it is what asks).
    public func requestAccess() {
        guard !isCapturing else { return }
        tap.start()
        // Queued behind the start, which waits for the answer.
        tap.stop()
    }

    private func observePlayback() {
        withObservationTracking {
            _ = MediaController.shared.nowPlaying?.isPlaying
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.update()
                self?.observePlayback()
            }
        }
    }

    private func update() {
        // Capturing asks for System Audio Recording; before the welcome window, it asks there instead.
        let enabled = Defaults[.liveWaveform] && Defaults[.hasCompletedOnboarding]
        let wanted = enabled && MediaController.shared.nowPlaying?.isPlaying == true
        if wanted {
            stopTask?.cancel()
            stopTask = nil
            if !isCapturing {
                tap.start()
                isCapturing = true
            }
        } else if isCapturing, !enabled {
            stopCapturing()
        } else if isCapturing, stopTask == nil {
            stopTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                self?.stopCapturing()
            }
        }
    }

    private func stopCapturing() {
        stopTask?.cancel()
        stopTask = nil
        tap.stop()
        isCapturing = false
    }
}
