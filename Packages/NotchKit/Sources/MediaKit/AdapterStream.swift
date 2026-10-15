import Foundation

/// A scalar from the adapter's JSON payload.
public enum JSONValue: Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init?(_ object: Any) {
        switch object {
        case is NSNull:
            self = .null
        case let number as NSNumber:
            self = CFGetTypeID(number) == CFBooleanGetTypeID() ? .bool(number.boolValue) : .number(number.doubleValue)
        case let string as String:
            self = .string(string)
        default:
            return nil
        }
    }

    var string: String? { if case let .string(value) = self { value } else { nil } }
    var number: Double? { if case let .number(value) = self { value } else { nil } }
    var bool: Bool? { if case let .bool(value) = self { value } else { nil } }
}

/// One line of `mediaremote-adapter stream --micros`.
public struct AdapterMessage: Equatable, Sendable {
    public var isDiff: Bool
    public var payload: [String: JSONValue]

    /// Returns nil for anything that isn't a well-formed `data` message.
    public static func parse(_ line: Data) -> AdapterMessage? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "data",
              let payload = object["payload"] as? [String: Any] else { return nil }
        return AdapterMessage(isDiff: object["diff"] as? Bool ?? false,
                              payload: payload.compactMapValues(JSONValue.init))
    }
}

/// Accumulates the adapter's stream: full payloads replace the state, diffs merge into it and a `null`
/// value removes a key (per the adapter's README).
public struct AdapterStream: Equatable, Sendable {
    public private(set) var payload: [String: JSONValue] = [:]

    public init() {}

    public mutating func apply(_ message: AdapterMessage) {
        guard message.isDiff else {
            payload = message.payload.filter { $0.value != .null }
            return
        }
        for (key, value) in message.payload {
            if value == .null {
                payload.removeValue(forKey: key)
            } else {
                payload[key] = value
            }
        }
    }

    public var nowPlaying: NowPlaying? {
        guard let bundle = payload["bundleIdentifier"]?.string,
              let title = payload["title"]?.string, !title.isEmpty else { return nil }
        let micros = { (key: String) in self.payload[key]?.number.map { $0 / 1_000_000 } }
        return NowPlaying(
            bundleIdentifier: bundle,
            parentBundleIdentifier: payload["parentApplicationBundleIdentifier"]?.string,
            processIdentifier: payload["processIdentifier"]?.number.map { Int32($0) },
            title: title,
            artist: payload["artist"]?.string.flatMap { $0.isEmpty ? nil : $0 },
            album: payload["album"]?.string.flatMap { $0.isEmpty ? nil : $0 },
            duration: micros("durationMicros"),
            elapsedTime: micros("elapsedTimeMicros"),
            timestamp: micros("timestampEpochMicros").map { Date(timeIntervalSince1970: $0) },
            playbackRate: payload["playbackRate"]?.number ?? 1,
            isPlaying: payload["playing"]?.bool ?? false)
    }

    /// Base64 artwork; compare it to detect artwork changes without decoding.
    public var artworkBase64: String? { payload["artworkData"]?.string }
}
