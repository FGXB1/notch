// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "NotchKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "Activities", targets: ["Activities"]),
        .library(name: "NotchCore", targets: ["NotchCore"]),
        .library(name: "MediaKit", targets: ["MediaKit"]),
        .library(name: "CalendarKit", targets: ["CalendarKit"]),
        .library(name: "SystemKit", targets: ["SystemKit"]),
        .library(name: "AudioTap", targets: ["AudioTap"]),
        .library(name: "WeatherLite", targets: ["WeatherLite"]),
        .library(name: "FileTray", targets: ["FileTray"]),
        .library(name: "NotchUI", targets: ["NotchUI"]),
        .library(name: "NotchShell", targets: ["NotchShell"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/Defaults", from: "9.0.0"),
    ],
    targets: [
        // Undocumented system calls (CGS spaces, DisplayServices, ...). Nothing else may declare them.
        .target(name: "PrivateAPI"),
        // What competes for the notch and the rules that pick one. Pure, no UI.
        .target(name: "Activities"),
        // State, settings, motion and geometry. No windows, no views.
        .target(name: "NotchCore", dependencies: ["Activities", "Defaults"]),
        // Now Playing: mediaremote-adapter stream, playback commands, artwork palette.
        .target(name: "MediaKit", dependencies: ["Activities", "NotchCore", "Defaults"]),
        // Calendar: EventKit store, scheduling rules, meeting links, time to leave.
        .target(name: "CalendarKit", dependencies: ["Activities", "NotchCore", "Defaults"]),
        // HUDs and status: media-key tap, volume, brightness, battery, headphones, Focus.
        .target(name: "SystemKit", dependencies: ["Activities", "NotchCore", "PrivateAPI", "Defaults"]),
        // Live waveform: Core Audio process tap and FFT band levels.
        .target(name: "AudioTap", dependencies: ["NotchCore", "MediaKit", "PrivateAPI", "Defaults"]),
        // Weather: location (or a chosen city) and the Open-Meteo forecast.
        .target(name: "WeatherLite", dependencies: ["NotchCore", "Defaults"]),
        // File tray: dropped files, thumbnails, Quick Look and AirDrop.
        .target(name: "FileTray", dependencies: ["NotchCore"]),
        // SwiftUI views rendered inside the notch and the settings window.
        .target(name: "NotchUI",
                dependencies: ["NotchCore", "Activities", "MediaKit", "CalendarKit", "SystemKit", "AudioTap",
                               "WeatherLite", "FileTray", "PrivateAPI", "Defaults"]),
        // AppKit windows, screens and the private space that host NotchUI.
        .target(name: "NotchShell",
                dependencies: ["NotchCore", "NotchUI", "MediaKit", "FileTray", "PrivateAPI", "Defaults"]),
        .testTarget(name: "NotchCoreTests", dependencies: ["NotchCore"]),
        .testTarget(name: "ActivitiesTests", dependencies: ["Activities"]),
        .testTarget(name: "MediaKitTests", dependencies: ["MediaKit"]),
        .testTarget(name: "CalendarKitTests", dependencies: ["CalendarKit", "Activities"]),
        .testTarget(name: "SystemKitTests", dependencies: ["SystemKit", "Activities"]),
        .testTarget(name: "AudioTapTests", dependencies: ["AudioTap"]),
        .testTarget(name: "WeatherLiteTests", dependencies: ["WeatherLite"]),
        .testTarget(name: "FileTrayTests", dependencies: ["FileTray"]),
    ]
)
