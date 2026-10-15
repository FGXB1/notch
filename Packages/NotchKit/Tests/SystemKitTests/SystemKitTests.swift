import Activities
import Foundation
import Testing
@testable import SystemKit

struct VolumeStepTests {
    @Test func stepsBySixteenthsAndClamps() {
        #expect(VolumeStep.next(from: 0.5, up: true, fine: false) == Float(9) / 16)
        #expect(VolumeStep.next(from: 0.5, up: false, fine: false) == Float(7) / 16)
        #expect(VolumeStep.next(from: 1, up: true, fine: false) == 1)
        #expect(VolumeStep.next(from: 0, up: false, fine: false) == 0)
    }

    @Test func fineStepsAreSixtyFourths() {
        #expect(VolumeStep.next(from: 0.5, up: true, fine: true) == Float(33) / 64)
    }

    @Test func offGridLevelsSnapOntoTheGrid() {
        // 0.37 is closest to 6/16; one step up lands on 7/16, not 0.37 + 1/16.
        #expect(VolumeStep.next(from: 0.37, up: true, fine: false) == Float(7) / 16)
    }
}

struct BatteryAlertsTests {
    private let rules = BatteryAlerts.Rules(notifyOnCharging: true, warnOnLow: true, lowThreshold: 0.2,
                                            notifyOnLowPowerMode: true)

    private func status(_ level: Double, plugged: Bool = false, lowPower: Bool = false) -> BatteryStatus {
        BatteryStatus(level: level, isPluggedIn: plugged, isCharging: plugged, isLowPowerMode: lowPower)
    }

    @Test func launchOnlyWarnsWhenAlreadyLowOnBattery() {
        #expect(BatteryAlerts.events(from: nil, to: status(0.12), rules: rules) == [.low])
        #expect(BatteryAlerts.events(from: nil, to: status(0.12, plugged: true), rules: rules).isEmpty)
        #expect(BatteryAlerts.events(from: nil, to: status(0.5, lowPower: true), rules: rules).isEmpty)
    }

    @Test func pluggingInAnnouncesCharging() {
        #expect(BatteryAlerts.events(from: status(0.5), to: status(0.5, plugged: true), rules: rules) == [.charging])
        #expect(BatteryAlerts.events(from: status(0.5, plugged: true), to: status(0.51, plugged: true), rules: rules).isEmpty)
    }

    @Test func lowBatteryWarnsOnceWhenCrossing() {
        #expect(BatteryAlerts.events(from: status(0.21), to: status(0.2), rules: rules) == [.low])
        #expect(BatteryAlerts.events(from: status(0.2), to: status(0.19), rules: rules).isEmpty)
    }

    @Test func unpluggingWhileLowWarns() {
        #expect(BatteryAlerts.events(from: status(0.15, plugged: true), to: status(0.15), rules: rules) == [.low])
    }

    @Test func lowPowerModeTurningOn() {
        #expect(BatteryAlerts.events(from: status(0.5), to: status(0.5, lowPower: true), rules: rules) == [.lowPowerMode])
        #expect(BatteryAlerts.events(from: status(0.5, lowPower: true), to: status(0.5), rules: rules).isEmpty)
    }
}

struct DeviceTests {
    @Test func symbolsFromNamesAndProductIDs() {
        #expect(DeviceSymbol.symbol(name: "Ishan's AirPods Pro") == "airpods.pro")
        #expect(DeviceSymbol.symbol(name: "AirPods Max") == "airpods.max")
        #expect(DeviceSymbol.symbol(name: "AirPods", productID: 0x2013) == "airpods.gen3")
        #expect(DeviceSymbol.symbol(name: "Beats Studio Pro") == "beats.headphones")
        #expect(DeviceSymbol.symbol(name: "JBL Flip 6") == nil)
    }

    @Test func renamedAirPodsAreRecognisedByProductID() {
        // This Mac's AirPods Pro 2 (USB-C) are called "airpood".
        #expect(DeviceSymbol.symbol(name: "airpood", productID: 0x2024, vendorID: 0x004C) == "airpods.pro")
        #expect(DeviceSymbol.symbol(name: "airpood", productID: 0x2024, vendorID: 0x0A12) == nil)
    }

    @Test func bluetoothAddressFromAudioDeviceUID() {
        #expect(OutputSymbol.bluetoothAddress(fromUID: "68-3E-C0-AF-8B-3B:output") == "68-3E-C0-AF-8B-3B")
        #expect(OutputSymbol.bluetoothAddress(fromUID: "BuiltInSpeakerDevice") == nil)
    }

    @Test func batteryIsTheLowerBudAndIgnoresUnreported() {
        #expect(DeviceSymbol.battery(left: 80, right: 60, single: nil) == 0.6)
        #expect(DeviceSymbol.battery(left: 0, right: 70, single: nil) == 0.7)
        #expect(DeviceSymbol.battery(left: nil, right: nil, single: 45) == 0.45)
        #expect(DeviceSymbol.battery(left: 0, right: 0, single: 0) == nil)
    }
}

struct FocusLogTests {
    @Test func activeModeUpdates() {
        let on = "Delivering active mode update: pid=798, activeModeIdentifier=com.apple.donotdisturb.mode.default, "
            + "connection=<BSXPC(com.apple.donotdisturb.service.non-launching)>"
        #expect(FocusLog.parse(on) == .activeMode("com.apple.donotdisturb.mode.default"))

        let off = "Delivering active mode update: pid=798, activeModeIdentifier=(null), connection=<BSXPC>"
        #expect(FocusLog.parse(off) == .activeMode(nil))
    }

    @Test func modeDetailsFromStateDumps() {
        let state = "update.state: <DNDState: 0x1; suppressionState: while UI locked; activeModeConfiguration: "
            + "<DNDMutableModeConfiguration: 0x2; mode: <DNDMode: 0x3; name: Deep Work; modeIdentifier: "
            + "com.apple.focus.custom.ABC; symbolImageName: brain.head.profile; tintColorName: systemPurpleColor; "
            + "semanticType: -1>>"
        #expect(FocusLog.parse(state) == .modeInfo(FocusMode(id: "com.apple.focus.custom.ABC", name: "Deep Work",
                                                             symbol: "brain.head.profile", tint: "purple")))
    }

    @Test func unknownModesFallBack() {
        #expect(FocusLog.mode("com.apple.focus.work", known: [:]).name == "Work")
        #expect(FocusLog.mode("com.apple.focus.custom.XYZ", known: [:]).name == "Focus")
    }

    @Test func unrelatedLinesAreIgnored() {
        #expect(FocusLog.parse("Did receive state update, will handle") == nil)
    }
}
