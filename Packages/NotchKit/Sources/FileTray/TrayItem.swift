import Foundation

/// A file parked in the tray. Most are references to files where they already live; dropped text, images
/// and links have no file, so the tray writes one and owns it (deleting it when the item is removed).
public struct TrayItem: Identifiable, Equatable, Sendable {
    /// How the item arrived, which decides how it leaves: text and links go back out as what they were.
    public enum Kind: String, Codable, Sendable {
        /// A file where it already lives.
        case file
        /// A file the sender only lent a temporary copy of; the tray keeps its own.
        case copiedFile
        /// Dropped text, kept as a .txt.
        case text
        /// A dropped web link, kept as a .webloc.
        case link
        /// Dropped image data.
        case image
    }

    public let id: UUID
    public var url: URL
    public var kind: Kind
    public var addedAt: Date

    public init(id: UUID = UUID(), url: URL, kind: Kind, addedAt: Date = .now) {
        self.id = id
        self.url = url
        self.kind = kind
        self.addedAt = addedAt
    }

    /// The tray wrote this file and deletes it with the item.
    public var isOwned: Bool { kind != .file }

    /// As Finder shows it (honours "Show all filename extensions"); text and links without their
    /// .txt/.webloc, since they aren't really files to the person who dropped them.
    public var displayName: String {
        switch kind {
        case .text, .link: url.deletingPathExtension().lastPathComponent
        default: FileManager.default.displayName(atPath: url.path)
        }
    }
}

/// On-disk form: a bookmark follows the file if it's renamed or moved; the path is the fallback.
struct StoredTrayItem: Codable, Equatable {
    var id: UUID
    var bookmark: Data?
    var path: String
    /// Missing in entries saved before kinds existed.
    var kind: TrayItem.Kind?
    var isOwned: Bool
    var addedAt: Date

    init(_ item: TrayItem) {
        id = item.id
        bookmark = try? item.url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        path = item.url.path
        kind = item.kind
        isOwned = item.isOwned
        addedAt = item.addedAt
    }

    /// nil when the file is gone.
    func resolve() -> TrayItem? {
        var url = URL(filePath: path)
        if let bookmark {
            var isStale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                                       relativeTo: nil, bookmarkDataIsStale: &isStale) {
                url = resolved
            }
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return TrayItem(id: id, url: url, kind: kind ?? Self.legacyKind(path: path, isOwned: isOwned),
                        addedAt: addedAt)
    }

    /// Older entries only recorded ownership; the tray's own files tell their kind by extension.
    static func legacyKind(path: String, isOwned: Bool) -> TrayItem.Kind {
        guard isOwned else { return .file }
        switch (path as NSString).pathExtension.lowercased() {
        case "txt": return .text
        case "webloc": return .link
        case "png", "jpg", "jpeg", "gif", "heic", "tiff": return .image
        default: return .copiedFile
        }
    }
}

/// Names for files the tray writes itself.
enum TrayFileName {
    /// The first few words of the text, so the file reads as what it is ("Meeting notes for Friday.txt").
    static func forText(_ text: String, now: Date = .now) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let cleaned = sanitize(firstLine)
        let words = cleaned.split(separator: " ")
        var name = ""
        for word in words {
            let candidate = name.isEmpty ? String(word) : name + " " + word
            if candidate.count > 40 { break }
            name = candidate
        }
        if name.isEmpty { name = "Text \(timestamp(now))" }
        return name + ".txt"
    }

    static func forImage(type fileExtension: String, now: Date = .now) -> String {
        "Image \(timestamp(now)).\(fileExtension)"
    }

    static func forLink(_ url: URL) -> String {
        let host = url.host(percentEncoded: false).map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
        return sanitize(host ?? "Link") + ".webloc"
    }

    /// No slashes or colons (Finder shows ":" as "/"), no leading dots, collapsed whitespace.
    static func sanitize(_ name: String) -> String {
        let replaced = name.map { "/:\\".contains($0) ? "-" : $0 }
        let collapsed = String(replaced).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(collapsed.drop { $0 == "." })
    }

    /// "Name.txt", then "Name 2.txt", ... until it doesn't collide.
    static func unique(_ name: String, in directory: URL, fileManager: FileManager = .default) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = directory.appending(path: name)
        var counter = 2
        while fileManager.fileExists(atPath: candidate.path) {
            let numbered = "\(base) \(counter)"
            candidate = directory.appending(path: ext.isEmpty ? numbered : "\(numbered).\(ext)")
            counter += 1
        }
        return candidate
    }

    private static func timestamp(_ date: Date) -> String {
        date.formatted(.verbatim("\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) at \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)).\(minute: .twoDigits).\(second: .twoDigits)",
                                 locale: Locale(identifier: "en_US_POSIX"), timeZone: .current, calendar: Calendar(identifier: .gregorian)))
    }
}
