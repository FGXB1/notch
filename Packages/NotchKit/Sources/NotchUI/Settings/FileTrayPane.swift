import AppKit
import Defaults
import FileTray
import NotchCore
import SwiftUI

struct FileTrayPane: View {
    @Default(.enableFileTray) private var enabled
    @Default(.openTrayOnDrag) private var openOnDrag
    @Default(.rememberLastTab) private var rememberLastTab
    private let store = TrayStore.shared

    var body: some View {
        Form {
            Section {
                Toggle("File Tray", isOn: $enabled)
            } footer: {
                Text("Park files in the notch to use later: drag them out again, preview them, or AirDrop them.")
                    .foregroundStyle(.secondary)
            }

            Section("Behaviour") {
                Toggle("Open the tray when dragging files to the notch", isOn: $openOnDrag)
                Toggle("Reopen on the last page used", isOn: $rememberLastTab)
            }
            .disabled(!enabled)

            Section {
                LabeledContent("In the tray", value: store.items.count == 1 ? "1 item" : "\(store.items.count) items")
                LabeledContent("Saved drops") {
                    Button("Show in Finder") {
                        try? FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
                        NSWorkspace.shared.activateFileViewerSelecting([store.directory])
                    }
                }
                LabeledContent("Empty the tray") {
                    Button("Clear", role: .destructive, action: store.removeAll)
                        .disabled(store.items.isEmpty)
                }
            } header: {
                Text("Contents")
            } footer: {
                Text("Files stay where they are; the tray only remembers them, and follows them if they're renamed or moved. Dropped text, images and links are saved in the tray's own folder and deleted when removed.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("File Tray")
    }
}
