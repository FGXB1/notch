import Foundation
import Testing
@testable import FileTray

struct TrayFileNameTests {
    @Test func namesTextAfterItsFirstWords() {
        #expect(TrayFileName.forText("Meeting notes for Friday\nsecond line") == "Meeting notes for Friday.txt")
        let long = TrayFileName.forText(String(repeating: "word ", count: 30))
        #expect(long.count <= 44 && long.hasSuffix(".txt"))
        #expect(TrayFileName.forText("   \n").hasPrefix("Text "))
    }

    @Test func sanitizesPathCharacters() {
        #expect(TrayFileName.sanitize("a/b:c\\d") == "a-b-c-d")
        #expect(TrayFileName.sanitize("..hidden  name") == "hidden name")
    }

    @Test func namesLinksAfterTheirSite() {
        #expect(TrayFileName.forLink(URL(string: "https://www.apple.com/mac/")!) == "apple.com.webloc")
    }

    @Test func numbersCollisions() throws {
        let directory = try temporaryDirectory()
        try Data().write(to: directory.appending(path: "Note.txt"))
        #expect(TrayFileName.unique("Note.txt", in: directory).lastPathComponent == "Note 2.txt")
        #expect(TrayFileName.unique("Other.txt", in: directory).lastPathComponent == "Other.txt")
    }
}

@MainActor
struct TrayStoreTests {
    @Test func addsFilesNewestFirstWithoutDuplicates() throws {
        let (store, files) = try makeStore(fileCount: 2)
        store.add(urls: [files[0]])
        store.add(urls: [files[1]])
        store.add(urls: [files[0]])
        #expect(store.items.count == 2)
        // Re-adding moves it to the front.
        #expect(store.items.first?.url.lastPathComponent == files[0].lastPathComponent)
    }

    @Test func persistsAcrossLaunches() throws {
        let (store, files) = try makeStore(fileCount: 2)
        store.add(urls: files)
        let reopened = TrayStore(directory: store.directory)
        #expect(reopened.items.map(\.url.lastPathComponent) == store.items.map(\.url.lastPathComponent))
    }

    @Test func followsRenamedFiles() throws {
        let (store, files) = try makeStore(fileCount: 1)
        store.add(urls: files)
        let renamed = files[0].deletingLastPathComponent().appending(path: "Renamed.txt")
        try FileManager.default.moveItem(at: files[0], to: renamed)
        let reopened = TrayStore(directory: store.directory)
        #expect(reopened.items.first?.url.lastPathComponent == "Renamed.txt")
    }

    @Test func forgetsDeletedFiles() throws {
        let (store, files) = try makeStore(fileCount: 2)
        store.add(urls: files)
        try FileManager.default.removeItem(at: files[0])
        store.prune()
        #expect(store.items.count == 1)
        #expect(TrayStore(directory: store.directory).items.count == 1)
    }

    @Test func clearingNeverDeletesOriginals() throws {
        let (store, files) = try makeStore(fileCount: 1)
        store.add(urls: files)
        store.removeAll()
        #expect(store.items.isEmpty)
        #expect(FileManager.default.fileExists(atPath: files[0].path))
    }

    @Test func removingDroppedTextDeletesItsFile() async throws {
        let (store, _) = try makeStore(fileCount: 0)
        let provider = NSItemProvider(object: "Shopping list\nmilk" as NSString)
        #expect(await store.add([provider]) == 1)
        let item = try #require(store.items.first)
        #expect(item.isOwned)
        #expect(item.url.lastPathComponent == "Shopping list.txt")
        #expect(try String(contentsOf: item.url, encoding: .utf8) == "Shopping list\nmilk")
        store.remove(item)
        #expect(!FileManager.default.fileExists(atPath: item.url.path))
    }

    /// How SwiftUI hands over a file dragged from Finder: its own type, opened in place, no file URL.
    @Test func droppedFilesAreReferencedNotCopied() async throws {
        let (store, files) = try makeStore(fileCount: 1)
        let provider = NSItemProvider()
        let original = files[0]
        provider.registerFileRepresentation(forTypeIdentifier: "public.plain-text", fileOptions: [.openInPlace],
                                            visibility: .all) { completion in
            completion(original, false, nil)
            return nil
        }
        #expect(await store.add([provider]) == 1)
        let item = try #require(store.items.first)
        #expect(!item.isOwned)
        #expect(item.url.standardizedFileURL == original.standardizedFileURL)
    }

    @Test func droppedTextGoesBackOutAsText() async throws {
        let (store, _) = try makeStore(fileCount: 0)
        let text = "Dinner at 8?\nI'll book the table."
        #expect(await store.add([NSItemProvider(object: text as NSString)]) == 1)
        let item = try #require(store.items.first)
        #expect(item.kind == .text)
        #expect(item.displayName == "Dinner at 8?")
        #expect(item.pasteboardWriter as? String == text)
    }

    @Test func droppedLinksGoBackOutAsLinks() async throws {
        let (store, _) = try makeStore(fileCount: 0)
        let link = URL(string: "https://www.apple.com/mac/")!
        #expect(await store.add([NSItemProvider(object: link as NSURL)]) == 1)
        let item = try #require(store.items.first)
        #expect(item.kind == .link)
        #expect(item.displayName == "apple.com")
        #expect((item.pasteboardWriter as? URL) == link)
    }

    @Test func filesGoBackOutAsFiles() throws {
        let (store, files) = try makeStore(fileCount: 1)
        store.add(urls: files)
        let item = try #require(store.items.first)
        #expect(item.kind == .file)
        #expect((item.pasteboardWriter as? URL)?.standardizedFileURL == files[0].standardizedFileURL)
    }

    @Test func kindsSurviveRelaunch() async throws {
        let (store, _) = try makeStore(fileCount: 0)
        await store.add([NSItemProvider(object: "Remember me" as NSString)])
        #expect(TrayStore(directory: store.directory).items.first?.kind == .text)
    }

    @Test func entriesSavedBeforeKindsGetOneFromTheirExtension() {
        #expect(StoredTrayItem.legacyKind(path: "/a/Note.txt", isOwned: true) == .text)
        #expect(StoredTrayItem.legacyKind(path: "/a/apple.com.webloc", isOwned: true) == .link)
        #expect(StoredTrayItem.legacyKind(path: "/a/Image.png", isOwned: true) == .image)
        #expect(StoredTrayItem.legacyKind(path: "/a/Report.txt", isOwned: false) == .file)
    }

    private func makeStore(fileCount: Int) throws -> (TrayStore, [URL]) {
        let root = try temporaryDirectory()
        let documents = root.appending(path: "Documents")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let files = try (0..<fileCount).map { index in
            let url = documents.appending(path: "File \(index).txt")
            try Data("file \(index)".utf8).write(to: url)
            return url
        }
        return (TrayStore(directory: root.appending(path: "Tray")), files)
    }
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "FileTrayTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

struct TraySelectionTests {
    let order = (0..<5).map { _ in UUID() }

    @Test func plainPressSelectsOnlyThatItem() {
        var selection = TraySelection()
        selection.press(order[1], in: order, command: false, shift: false)
        selection.press(order[3], in: order, command: false, shift: false)
        #expect(selection.ids == [order[3]])
    }

    @Test func commandTogglesAndShiftExtends() {
        var selection = TraySelection()
        selection.press(order[0], in: order, command: false, shift: false)
        selection.press(order[2], in: order, command: true, shift: false)
        #expect(selection.ids == [order[0], order[2]])
        selection.press(order[0], in: order, command: true, shift: false)
        #expect(selection.ids == [order[2]])
        selection.press(order[4], in: order, command: false, shift: true)
        #expect(selection.ids == Set(order[2...4]))
    }

    @Test func pressingASelectedItemKeepsTheSelectionForDragging() {
        var selection = TraySelection()
        selection.selectAll(order)
        selection.press(order[2], in: order, command: false, shift: false)
        #expect(selection.count == 5)
        #expect(selection.targets(for: order[2], in: order) == order)
        // Released without dragging: narrows to the clicked item, as in Finder.
        selection.click(order[2], command: false, shift: false)
        #expect(selection.ids == [order[2]])
    }

    @Test func actionsOnAnUnselectedItemApplyToItAlone() {
        var selection = TraySelection()
        selection.press(order[0], in: order, command: false, shift: false)
        selection.press(order[1], in: order, command: true, shift: false)
        #expect(selection.targets(for: order[3], in: order) == [order[3]])
        // Selected targets come back in tray order, not selection order.
        #expect(selection.targets(for: order[1], in: order) == [order[0], order[1]])
    }

    @Test func forgetsItemsThatLeftTheTray() {
        var selection = TraySelection()
        selection.selectAll(order)
        selection.prune(keeping: Array(order.prefix(2)))
        #expect(selection.ids == Set(order.prefix(2)))
    }
}
