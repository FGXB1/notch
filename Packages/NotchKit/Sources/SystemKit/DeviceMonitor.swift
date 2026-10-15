import Activities
import AppKit
import CoreBluetooth
import Defaults
import IOBluetooth
import NotchCore

/// SF Symbol for an audio accessory: by Apple product ID first (so renamed AirPods still look like AirPods),
/// then by name.
public enum DeviceSymbol {
    static let appleVendorID = 0x004C

    /// AirPods and Beats product IDs (Bluetooth vendor 0x004C).
    static let appleProducts: [Int: String] = [
        0x2002: "airpods", 0x200F: "airpods", 0x2013: "airpods.gen3", 0x2019: "airpods.gen4", 0x201B: "airpods.gen4",
        0x200E: "airpods.pro", 0x2014: "airpods.pro", 0x2024: "airpods.pro", 0x2027: "airpods.pro",
        0x200A: "airpods.max", 0x201F: "airpods.max",
        0x2006: "beats.headphones", 0x2009: "beats.headphones", 0x200C: "beats.headphones", 0x2017: "beats.headphones",
        0x2025: "beats.headphones",
        0x200B: "beats.powerbeats.pro", 0x201D: "beats.powerbeats.pro",
        0x2003: "earbuds", 0x2005: "earbuds", 0x200D: "earbuds", 0x2010: "earbuds", 0x2011: "earbuds", 0x2012: "earbuds",
        0x2016: "earbuds",
    ]

    public static func symbol(name: String, productID: Int? = nil, vendorID: Int? = nil) -> String? {
        if let productID, vendorID == nil || vendorID == appleVendorID, let symbol = appleProducts[productID] {
            return symbol
        }
        let lowered = name.lowercased()
        if lowered.contains("airpods max") { return "airpods.max" }
        if lowered.contains("airpods pro") { return "airpods.pro" }
        if lowered.contains("airpods") { return "airpods" }
        if lowered.contains("powerbeats") { return "beats.powerbeats.pro" }
        if lowered.contains("beats") { return "beats.headphones" }
        return nil
    }

    /// The lower bud, so the notice warns about whichever runs out first. Values are percentages; 0 means
    /// "not reported" (case closed, bud in the case).
    public static func battery(left: Int?, right: Int?, single: Int?) -> Double? {
        let buds = [left, right].compactMap(\.self).filter { $0 > 0 }
        if let lowest = buds.min() { return Double(lowest) / 100 }
        if let single, single > 0 { return Double(single) / 100 }
        return nil
    }
}

/// The most recently connected audio accessory, for the lock-screen widget.
public struct ConnectedDevice: Equatable, Sendable {
    public var address: String
    public var name: String
    public var symbol: String
    /// 0...1
    public var battery: Double?
}

/// Bluetooth audio accessories: a notice when one connects (battery included), and a warning when its
/// battery runs low. Battery levels come from IOBluetoothDevice's undocumented `batteryPercent*`
/// properties.
@MainActor
@Observable
public final class DeviceMonitor: NSObject {
    public static let shared = DeviceMonitor()

    public private(set) var current: ConnectedDevice?

    @ObservationIgnored private let activities: ActivityCenter
    @ObservationIgnored private var connectNotification: IOBluetoothUserNotification?
    /// Addresses of connected audio devices.
    @ObservationIgnored private var connected: Set<String> = []
    @ObservationIgnored private var warnedLow: Set<String> = []
    @ObservationIgnored private var startedAt = Date.distantFuture
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    /// Only exists to ask for Bluetooth access without blocking.
    @ObservationIgnored private var authorizer: BluetoothAuthorizer?

    /// Battery reports settle a moment after the link comes up.
    private static let settleDelay: Duration = .seconds(2)
    private static let pollInterval: Duration = .seconds(120)

    public init(activities: ActivityCenter = .shared) {
        self.activities = activities
    }

    public func start() {
        // IOBluetooth asks for Bluetooth access synchronously, freezing the main thread for as long as the
        // prompt is up. CoreBluetooth asks asynchronously, so it goes first.
        switch CBManager.authorization {
        case .allowedAlways:
            registerForConnections()
        case .notDetermined:
            // Before the welcome window, it asks there instead.
            if Defaults[.hasCompletedOnboarding] { requestAccess() }
        default:
            Log.system.info("Bluetooth access denied; headphone notices are off")
        }
    }

    /// Shows the Bluetooth prompt (asynchronously, via CoreBluetooth), then starts watching for headphones.
    public func requestAccess() {
        guard authorizer == nil, CBManager.authorization == .notDetermined else { return }
        authorizer = BluetoothAuthorizer { [weak self] allowed in
            self?.authorizer = nil
            if allowed { self?.registerForConnections() }
        }
    }

    private func registerForConnections() {
        guard connectNotification == nil else { return }
        startedAt = .now
        // Fires for devices that are already connected too; those are recorded silently.
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self,
                                                         selector: #selector(deviceConnected(_:device:)))
        logPairedDevices()
    }

    /// Diagnostics: what IOBluetooth reports for each paired audio device (stream with `--level debug`).
    private func logPairedDevices() {
        for case let device as IOBluetoothDevice in IOBluetoothDevice.pairedDevices() ?? []
        where device.deviceClassMajor == kBluetoothDeviceClassMajorAudio {
            let id = Self.integer("productID", of: device).map { String($0, radix: 16) } ?? "?"
            let battery = Self.battery(of: device).map { "\(Int($0 * 100))%" } ?? "none"
            Log.system.debug(
                "Paired audio device \(Self.symbol(of: device) ?? "headphones", privacy: .public) product 0x\(id, privacy: .public) battery \(battery, privacy: .public) connected \(device.isConnected())")
        }
    }

    // MARK: IOBluetooth callbacks

    // IOBluetooth is a shim over CoreBluetooth on current macOS and calls these on its own coordinator queue,
    // never the main thread. They must stay nonisolated (a main-actor thunk traps there): take the address
    // and hop over.

    @objc nonisolated private func deviceConnected(_ notification: IOBluetoothUserNotification,
                                                   device: IOBluetoothDevice) {
        guard device.deviceClassMajor == kBluetoothDeviceClassMajorAudio, let address = device.addressString else { return }
        Task { @MainActor [weak self] in self?.didConnect(address) }
    }

    @objc nonisolated private func deviceDisconnected(_ notification: IOBluetoothUserNotification,
                                                      device: IOBluetoothDevice) {
        notification.unregister()
        guard let address = device.addressString else { return }
        Task { @MainActor [weak self] in self?.didDisconnect(address) }
    }

    // MARK: State

    private func didConnect(_ address: String) {
        // CoreBluetooth reports a connection per profile; one device, one notice.
        guard !connected.contains(address), let device = IOBluetoothDevice(addressString: address) else { return }
        connected.insert(address)
        device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
        let isAtLaunch = Date().timeIntervalSince(startedAt) < 3
        Log.system.info("Audio device connected\(isAtLaunch ? " (at launch)" : "", privacy: .public)")
        Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            self?.check(address, justConnected: !isAtLaunch)
        }
        startPolling()
    }

    private func didDisconnect(_ address: String) {
        connected.remove(address)
        if current?.address == address {
            current = nil
        }
        warnedLow.remove(address)
        if connected.isEmpty {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    private func check(_ address: String, justConnected: Bool) {
        guard connected.contains(address), let device = IOBluetoothDevice(addressString: address) else { return }
        let name = device.name ?? "Headphones"
        let battery = Self.battery(of: device)
        let isLow = battery.map { $0 <= Defaults[.lowConnectBatteryThreshold] / 100 } ?? false
        let symbol = Self.symbol(of: device) ?? "headphones"
        Log.system.info("Audio device \(symbol, privacy: .public): battery \(battery.map { Int($0 * 100) } ?? -1)%")
        let snapshot = ConnectedDevice(address: address, name: name, symbol: symbol, battery: battery)
        if current != snapshot, current == nil || current?.address == address || justConnected {
            current = snapshot
        }
        guard LockMonitor.allows(.allowConnectivityWhenLocked) else { return }

        if justConnected, Defaults[.notifyOnDeviceConnect] {
            activities.post(.device(name: name, symbol: symbol, battery: battery, event: .connected))
            if isLow { warnedLow.insert(address) } // the connect notice already shows it in red
        } else if isLow, Defaults[.warnOnLowConnectBattery], !warnedLow.contains(address) {
            warnedLow.insert(address)
            activities.post(.device(name: name, symbol: symbol, battery: battery, event: .lowBattery))
            if Defaults[.playSoundOnLowConnectBattery] {
                NSSound(named: "Funk")?.play()
            }
        } else if !isLow {
            warnedLow.remove(address)
        }
    }

    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard let self, !Task.isCancelled else { return }
                for address in connected {
                    check(address, justConnected: false)
                }
            }
        }
    }

    /// Symbol for the Bluetooth device at `address` ("68-3e-c0-af-8b-3b" or with colons), without ever
    /// triggering IOBluetooth's blocking permission prompt.
    static func symbol(forAddress address: String) -> String? {
        guard CBManager.authorization == .allowedAlways,
              let device = IOBluetoothDevice(addressString: address) else { return nil }
        return symbol(of: device)
    }

    // MARK: Private properties

    private static func symbol(of device: IOBluetoothDevice) -> String? {
        DeviceSymbol.symbol(name: device.name ?? "", productID: integer("productID", of: device),
                            vendorID: integer("vendorID", of: device))
    }

    private static func battery(of device: IOBluetoothDevice) -> Double? {
        DeviceSymbol.battery(left: integer("batteryPercentLeft", of: device),
                             right: integer("batteryPercentRight", of: device),
                             single: integer("batteryPercentSingle", of: device))
    }

    /// KVC on an undocumented property; checked first, since a missing key would throw.
    private static func integer(_ key: String, of device: IOBluetoothDevice) -> Int? {
        guard device.responds(to: NSSelectorFromString(key)) else { return nil }
        return (device.value(forKey: key) as? NSNumber)?.intValue
    }
}

/// Creating a central manager shows the Bluetooth prompt; its first state update arrives once it's answered.
@MainActor
private final class BluetoothAuthorizer: NSObject, CBCentralManagerDelegate {
    private var manager: CBCentralManager?
    private let completion: (Bool) -> Void

    init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
        super.init()
        manager = CBCentralManager(delegate: self, queue: .main)
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated { finish() }
    }

    private func finish() {
        let authorization = CBManager.authorization
        guard authorization != .notDetermined else { return }
        completion(authorization == .allowedAlways)
    }
}
