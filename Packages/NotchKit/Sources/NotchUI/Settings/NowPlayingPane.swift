import AudioTap
import Defaults
import MediaKit
import SwiftUI

struct NowPlayingPane: View {
    @Default(.enableNowPlaying) private var enabled
    @Default(.peekOnTrackChange) private var peekOnTrackChange
    @Default(.hideWhileSourceIsActive) private var hideWhileSourceIsActive
    @Default(.hideIdleDuration) private var hideIdleDuration
    @Default(.liveWaveform) private var liveWaveform
    private let media = MediaController.shared

    var body: some View {
        Form {
            Section {
                Toggle("Now Playing", isOn: $enabled)
                LabeledContent("Source", value: sourceDescription)
                if let item = media.nowPlaying {
                    LabeledContent("Playing", value: [item.title, item.artist].compactMap(\.self).joined(separator: " — "))
                    LabeledContent("Player", value: item.appBundleIdentifier)
                }
            }
            Section {
                Toggle("Live waveform", isOn: $liveWaveform)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    LabeledContent("Status", value: waveformStatus)
                }
            } header: {
                Text("Waveform")
            } footer: {
                Text("Listens to what your Mac is playing to animate the bars beside the notch. "
                    + "Needs System Audio Recording permission (Privacy & Security › Screen & System Audio Recording); "
                    + "without it the bars animate on their own.")
                    .foregroundStyle(.secondary)
            }
            Section("Behaviour") {
                Toggle("Quick peek when the track changes", isOn: $peekOnTrackChange)
                Toggle("Hide while the player is frontmost", isOn: $hideWhileSourceIsActive)
                LabeledSlider(title: "Hide after pausing", value: $hideIdleDuration, range: 3...120, format: "%.0f s")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Now Playing")
    }

    private var waveformStatus: String {
        if !liveWaveform { return "Off" }
        if !LiveWaveform.shared.isCapturing { return "Starts when something plays" }
        return LiveWaveform.shared.levels() != nil ? "Live" : "Waiting for audio (or permission)"
    }

    private var sourceDescription: String {
        switch media.source {
        case .starting: "Starting…"
        case .adapter: "System (every app)"
        case .playerApps: "Music & Spotify only (adapter unavailable)"
        case .disabled: "Off"
        }
    }
}
