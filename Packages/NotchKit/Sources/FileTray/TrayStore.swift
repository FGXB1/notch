import AppKit
import NotchCore
import Observation
import UniformTypeIdentifiers

/// The tray's contents, newest first, persisted in Application Support so they survive relaunches.
@MainActor
@Observable
public final class TrayStore {
    public static let shared = TrayStore()

    public private(set) var items: [TrayItem] = []

    /// `~/Library/Application Support/Notch/Tray`: `items.json`, plus `Files/` for files the tray wrote.
    public let directory: URL
    private var indexURL: URL { directory.appending(path: "items.json") }
    var filesDirectory: URL { directory.appending(path: "Files") }

    /// Types `add(_:)` understands, for drop targets.
    public static let acceptedTypes: [UTType] = [.fileURL, .url, .image, .plainText]

    public init(directory: URL? = nil) {
        self.directory = directory ?? URL.applicationSupportDirectory.appending(path: "Notch/Tray")
        load()
    }

    public var urls: [URL] { items.map(\.url) }

    // MARK: Adding

    /// Adds whatever was dropped. Returns how many items arrived.
    @discardableResult
    public func add(_ providers: [NSItemProvider]) async -> Int {
        var added = 0
        for provider in providers {
            guard let content = await DropContent.load(from: provider) else { continue }
            if insert(content) { added += 1 }
        }
        if added > 0 { save() }
        return added
    }

    public func add(urls: [URL]) {
        let inserted = urls.filter { insert(.file($0)) }
        if !inserted.isEmpty { save() }
    }

    /// False if it was already there (it moves to the front instead) or couldn't be written.
    private func insert(_ content: DropContent) -> Bool {
        let item: TrayItem
        switch content {
        case let .file(url):
            let url = url.standardizedFileURL
            if let index = items.firstIndex(where: { $0.url.standardizedFileURL == url }) {
                items.insert(items.remove(at: index), at: 0)
                return false
            }
            item = TrayItem(url: url, kind: .file)
        case let .copiedFile(staged):
            do {
                try FileManager.default.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
                let url = TrayFileName.unique(staged.lastPathComponent, in: filesDirectory)
                try FileManager.default.moveItem(at: staged, to: url)
                try? FileManager.default.removeItem(at: staged.deletingLastPathComponent())
                item = TrayItem(url: url, kind: .copiedFile)
            } catch {
                Log.tray.error("Tray: couldn't keep a dropped file: \(error.localizedDescription, privacy: .public)")
                return false
            }
        case let .link(url):
            let plist: [String: String] = ["URL": url.absoluteString]
            guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0),
                  let file = write(data, named: TrayFileName.forLink(url)) else { return false }
            item = TrayItem(url: file, kind: .link)
        case let .image(data, fileExtension):
            guard let file = write(data, named: TrayFileName.forImage(type: fileExtension)) else { return false }
            item = TrayItem(url: file, kind: .image)
        case let .text(text):
            guard let file = write(Data(text.utf8), named: TrayFileName.forText(text)) else { return false }
            item = TrayItem(url: file, kind: .text)
        }
        items.insert(item, at: 0)
        Log.tray.info("Tray: added \(item.url.lastPathComponent, privacy: .private) (\(self.items.count) items)")
        return true
    }

    private func write(_ data: Data, named name: String) -> URL? {
        do {
            try FileManager.default.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
            let url = TrayFileName.unique(name, in: filesDirectory)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            Log.tray.error("Tray: couldn't write \(name, privacy: .private): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: Removing

    public func remove(_ item: TrayItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        deleteIfOwned(items.remove(at: index))
        save()
    }

    public func remove(ids: Set<UUID>) {
        let removed = items.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return }
        removed.forEach(deleteIfOwned)
        items.removeAll { ids.contains($0.id) }
        save()
    }

    public func removeAll() {
        items.forEach(deleteIfOwned)
        items.removeAll()
        save()
    }

    /// Forgets items whose files were deleted or moved somewhere unreachable since they were added.
    public func prune() {
        let kept = items.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        guard kept.count != items.count else { return }
        items = kept
        save()
    }

    private func deleteIfOwned(_ item: TrayItem) {
        // Only files the tray wrote into its own folder; never the user's originals.
        guard item.isOwned, item.url.standardizedFileURL.path.hasPrefix(filesDirectory.standardizedFileURL.path) else {
            return
        }
        try? FileManager.default.removeItem(at: item.url)
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let stored = try? JSONDecoder().decode([StoredTrayItem].self, from: data) else { return }
        items = stored.compactMap { $0.resolve() }
        if items.count != stored.count { save() }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(items.map(StoredTrayItem.init))
            try data.write(to: indexURL, options: .atomic)
        } catch {
            Log.tray.error("Tray: couldn't save: \(error.localizedDescription, privacy: .public)")
        }
    }
}
