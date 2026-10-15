import CoreGraphics
import Darwin

/// Built-in display brightness via the private DisplayServices framework (what the brightness keys call).
/// Loaded at runtime: it isn't in the SDK, and a missing symbol must degrade, not crash at launch.
public enum DisplayServices {
    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias CanChangeBrightness = @convention(c) (CGDirectDisplayID) -> Bool

    nonisolated(unsafe) private static let handle = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)

    private static let getBrightness = symbol("DisplayServicesGetBrightness", as: GetBrightness.self)
    private static let setBrightness = symbol("DisplayServicesSetBrightness", as: SetBrightness.self)
    private static let canChange = symbol("DisplayServicesCanChangeBrightness", as: CanChangeBrightness.self)

    public static var isAvailable: Bool {
        getBrightness != nil && setBrightness != nil && canChange != nil
    }

    public static func canChangeBrightness(_ display: CGDirectDisplayID) -> Bool {
        canChange?(display) ?? false
    }

    /// 0...1, nil when unreadable.
    public static func brightness(_ display: CGDirectDisplayID) -> Float? {
        var value: Float = 0
        guard let getBrightness, getBrightness(display, &value) == 0 else { return nil }
        return value
    }

    @discardableResult
    public static func setBrightness(_ value: Float, for display: CGDirectDisplayID) -> Bool {
        setBrightness?(display, min(1, max(0, value))) == 0
    }

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }
}
