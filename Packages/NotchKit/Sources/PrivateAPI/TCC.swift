import Foundation
import Darwin

/// Privacy permission status from the private TCC framework, for permissions with no public way to ask
/// (System Audio Recording). Reads only: it never shows a prompt. Loaded at runtime like DisplayServices.
public enum TCC {
    public enum Status: Sendable {
        case granted
        case denied
        case notDetermined
    }

    public static let audioCapture = "kTCCServiceAudioCapture"

    private typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int32

    nonisolated(unsafe) private static let handle = dlopen("/System/Library/PrivateFrameworks/TCC.framework/TCC",
                                                           RTLD_LAZY)
    private static let preflight: Preflight? = dlsym(handle, "TCCAccessPreflight")
        .map { unsafeBitCast($0, to: Preflight.self) }

    /// This app's status for `service`; nil if TCC can't be asked.
    public static func status(_ service: String) -> Status? {
        guard let preflight else { return nil }
        return switch preflight(service as CFString, nil) {
        case 0: .granted
        case 1: .denied
        default: .notDetermined
        }
    }
}
