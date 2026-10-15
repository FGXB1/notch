import AppKit
import UniformTypeIdentifiers

/// One dropped thing, in the richest form the tray can keep: a file beats a link beats an image beats text.
enum DropContent: Sendable {
    /// A file where it already lives.
    case file(URL)
    /// A file the sender only lent us a temporary copy of; the tray has to keep its own.
    case copiedFile(URL)
    case link(URL)
    case image(Data, fileExtension: String)
    case text(String)

    @MainActor static func load(from provider: NSItemProvider) async -> DropContent? {
        let types = provider.registeredTypeIdentifiers.compactMap(UTType.init)

        if types.contains(where: { $0.conforms(to: .fileURL) }),
           let data = await data(from: provider, type: .fileURL),
           let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL {
            return .file(url)
        }
        // SwiftUI hands a dragged file over as a file representation of its own type (a .txt arrives as
        // public.plain-text), not as a file URL. Opening it in place gives back the original.
        if let type = provider.registeredTypeIdentifiers(fileOptions: [.openInPlace]).first,
           let file = await file(from: provider, type: type) {
            return file
        }
        if types.contains(where: { $0.conforms(to: .url) }),
           let data = await data(from: provider, type: .url),
           let url = URL(dataRepresentation: data, relativeTo: nil), let scheme = url.scheme,
           ["http", "https"].contains(scheme.lowercased()) {
            return .link(url)
        }
        for type in [UTType.png, .jpeg, .gif, .heic, .tiff] where types.contains(where: { $0.conforms(to: type) }) {
            guard let data = await data(from: provider, type: type) else { continue }
            // TIFF is how AppKit pastes images; PNG is what anyone wants to receive.
            if type == .tiff, let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) {
                return .image(png, fileExtension: "png")
            }
            return .image(data, fileExtension: type.preferredFilenameExtension ?? "png")
        }
        if types.contains(where: { $0.conforms(to: .plainText) }) {
            var data = await data(from: provider, type: .utf8PlainText)
            if data == nil { data = await self.data(from: provider, type: .plainText) }
            if let data, let text = String(data: data, encoding: .utf8),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .text(text)
            }
        }
        return nil
    }

    @MainActor private static func file(from provider: NSItemProvider, type: String) async -> DropContent? {
        await withCheckedContinuation { continuation in
            _ = provider.loadInPlaceFileRepresentation(forTypeIdentifier: type) { url, isInPlace, _ in
                guard let url else { return continuation.resume(returning: nil) }
                if isInPlace { return continuation.resume(returning: .file(url)) }
                // A temporary copy, deleted once this handler returns: move it somewhere that lasts.
                let staging = FileManager.default.temporaryDirectory.appending(path: "NotchTray-\(UUID().uuidString)")
                let kept = staging.appending(path: url.lastPathComponent)
                do {
                    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: url, to: kept)
                    continuation.resume(returning: .copiedFile(kept))
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    @MainActor private static func data(from provider: NSItemProvider, type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}
