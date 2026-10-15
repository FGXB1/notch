import AppKit
import FileTray
import SwiftUI
import UniformTypeIdentifiers

/// The tray page: parked files in a sideways-scrolling row, with AirDrop and Clear beside them.
/// Finder's rules: click selects (⌘ adds, ⇧ extends), dragging a selected file takes the whole selection,
/// double-click opens.
struct TrayView: View {
    let store: TrayStore
    /// A drag is over the expanded notch.
    let isTargeted: Bool
    /// False once the notch closes; the selection is let go then.
    let isActive: Bool

    @State private var selection = TraySelection()

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if store.items.isEmpty {
                    EmptyTray(isTargeted: isTargeted)
                        .transition(.blurReplace)
                } else {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 2) {
                            ForEach(store.items) { item in
                                TrayTile(item: item, store: store, selection: $selection)
                                    .transition(.scale(scale: 0.5).combined(with: .opacity))
                            }
                        }
                    }
                    .scrollIndicators(.never)
                    .contentMargins(.horizontal, 6, for: .scrollContent)
                    .scrollClipDisabled()
                    .mask(EdgeFade())
                    // A click between tiles deselects (and, unlike elsewhere on the notch, doesn't close it).
                    .contentShape(.rect)
                    .onTapGesture { selection.clear() }
                    .background(.white.opacity(isTargeted ? 0.08 : 0), in: .rect(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(isTargeted ? 0.5 : 0), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    }
                    .transition(.blurReplace)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            TraySidebar(store: store, selection: $selection)
                .frame(width: 92)
        }
        .animation(.spring(duration: 0.4, bounce: 0.25), value: store.items.map(\.id))
        .animation(.smooth(duration: 0.2), value: isTargeted)
        .onChange(of: store.items.map(\.id)) { selection.prune(keeping: store.items.map(\.id)) }
        .onChange(of: isActive) {
            if !isActive { selection.clear() }
        }
    }
}

/// Fades the row's ends so tiles scroll under the edge instead of being cut off.
private struct EdgeFade: View {
    var body: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: 8)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 16)
        }
    }
}

private struct EmptyTray: View {
    let isTargeted: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 22, weight: .semibold))
                .symbolEffect(.bounce, value: isTargeted)
            Text(isTargeted ? "Drop to keep it here" : "Drop files here")
                .font(.system(size: 12.5, weight: .semibold))
                .contentTransition(.opacity)
            Text("Text, images and links work too")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
        .foregroundStyle(.white.opacity(isTargeted ? 1 : 0.8))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white.opacity(isTargeted ? 0.08 : 0.03), in: .rect(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(isTargeted ? 0.55 : 0.18), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        }
        .scaleEffect(isTargeted ? 1.015 : 1)
    }
}

private struct TrayTile: View {
    let item: TrayItem
    let store: TrayStore
    @Binding var selection: TraySelection

    @State private var thumbnail: NSImage?
    @State private var isHovering = false
    /// This press turned into a drag out of the notch.
    @State private var isDraggingOut = false

    static let side: CGFloat = 54

    init(item: TrayItem, store: TrayStore, selection: Binding<TraySelection>) {
        self.item = item
        self.store = store
        _selection = selection
        _thumbnail = State(initialValue: Thumbnails.shared.cached(for: item.url))
    }

    var body: some View {
        let isSelected = selection.contains(item.id)
        VStack(spacing: 5) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                } else {
                    Color.clear
                }
            }
            .frame(width: Self.side, height: Self.side)

            Text(item.displayName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(isSelected ? 1 : 0.85))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(width: 78, height: 26, alignment: .top)
        }
        .padding(.vertical, 6)
        .frame(width: 84)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.32) : .white.opacity(isHovering ? 0.1 : 0))
                .strokeBorder(Color.accentColor.opacity(isSelected ? 0.7 : 0), lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button("Remove", systemImage: "xmark.circle.fill") {
                    store.remove(item)
                }
                .labelStyle(.iconOnly)
                .font(.system(size: 14))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.black, .white.opacity(0.85))
                .buttonStyle(.plain)
                .offset(x: -3, y: 3)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .contentShape(.rect(cornerRadius: 12))
        .animation(.smooth(duration: 0.15), value: isSelected)
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.15)) { isHovering = hovering }
        }
        .gesture(pressAndDrag)
        .simultaneousGesture(TapGesture(count: 2).onEnded { targetURLs.forEach(FileActions.open) })
        .contextMenu { menu }
        .help(item.url.path)
        .task(id: item.url) {
            let image = await Thumbnails.shared.thumbnail(for: item.url, side: Self.side)
            if thumbnail == nil {
                withAnimation(.smooth(duration: 0.2)) { thumbnail = image }
            } else {
                thumbnail = image
            }
        }
    }

    /// Select on mouse down, like Finder; a few points of movement turns it into a drag out of the notch,
    /// carrying every selected file (as files, not their contents).
    private var pressAndDrag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if value.translation == .zero {
                    // The first event of a new press. (An AppKit drag swallows the previous press's mouse-up,
                    // so this, not onEnded, is where per-press state resets.)
                    isDraggingOut = false
                    let modifiers = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
                    selection.press(item.id, in: order, command: modifiers.contains(.command),
                                    shift: modifiers.contains(.shift))
                    return
                }
                guard !isDraggingOut, hypot(value.translation.width, value.translation.height) > 4 else { return }
                isDraggingOut = TrayDrag.begin(targets)
            }
            .onEnded { _ in
                guard !isDraggingOut else { return }
                let modifiers = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
                selection.click(item.id, command: modifiers.contains(.command), shift: modifiers.contains(.shift))
            }
    }

    @ViewBuilder private var menu: some View {
        let urls = targetURLs
        let count = urls.count == 1 ? "" : " \(urls.count) Items"
        Button("Open\(count)") { urls.forEach(FileActions.open) }
        Button("Quick Look\(count)") { QuickLook.shared.toggle(urls, index: 0) }
        Button("Show in Finder") { FileActions.reveal(urls) }
        Divider()
        Button("Copy\(count)") { FileActions.copy(targets) }
        if FileActions.canAirDrop {
            Button("AirDrop\(count)…") { FileActions.airDrop(urls) }
        }
        Divider()
        Button("Select All") { selection.selectAll(order) }
        Divider()
        Button("Remove\(count) from Tray") {
            store.remove(ids: Set(selection.targets(for: item.id, in: order)))
        }
    }

    private var order: [UUID] { store.items.map(\.id) }

    /// What an action on this tile applies to: the selection if this tile is in it, otherwise just this tile.
    private var targets: [TrayItem] {
        let ids = selection.targets(for: item.id, in: order)
        return ids.compactMap { id in store.items.first { $0.id == id } }
    }

    private var targetURLs: [URL] { targets.map(\.url) }
}

/// AirDrop, Quick Look and Clear. Each acts on the selection, or on everything when nothing is selected;
/// files dropped on AirDrop are sent straight away instead of joining the tray.
private struct TraySidebar: View {
    let store: TrayStore
    @Binding var selection: TraySelection
    @State private var isAirDropTargeted = false

    var body: some View {
        let urls = targetURLs
        VStack(spacing: 6) {
            Button {
                FileActions.airDrop(urls)
            } label: {
                VStack(spacing: 5) {
                    Group {
                        if let icon = FileActions.airDropIcon {
                            Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit)
                        } else {
                            Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 20, weight: .semibold))
                        }
                    }
                    .frame(width: 28, height: 28)
                    .scaleEffect(isAirDropTargeted ? 1.12 : 1)
                    Text("AirDrop")
                        .font(.system(size: 10.5, weight: .semibold))
                    if !selection.isEmpty {
                        Text("\(selection.count) selected")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                            .transition(.blurReplace)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(isAirDropTargeted ? Color.accentColor.opacity(0.55) : .white.opacity(0.08),
                            in: .rect(cornerRadius: 14, style: .continuous))
                .contentShape(.rect(cornerRadius: 14))
            }
            .buttonStyle(PressableStyle())
            .opacity(store.items.isEmpty && !isAirDropTargeted ? 0.5 : 1)
            .onDrop(of: [.fileURL], isTargeted: $isAirDropTargeted) { providers in
                Task { FileActions.airDrop(await FileActions.fileURLs(from: providers)) }
                return true
            }
            .help(selection.isEmpty ? "AirDrop everything in the tray, or drop files here to AirDrop just those"
                : "AirDrop the selected files")

            HStack(spacing: 6) {
                Button {
                    QuickLook.shared.toggle(urls, index: 0)
                } label: {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .background(.white.opacity(0.08), in: .circle)
                        .contentShape(.circle)
                }
                .help(selection.isEmpty ? "Quick Look everything" : "Quick Look the selected files")

                Button {
                    if selection.isEmpty { store.removeAll() } else { store.remove(ids: selection.ids) }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "trash")
                            .font(.system(size: 9.5, weight: .semibold))
                        Text(selection.isEmpty ? "Clear" : "Remove")
                            .contentTransition(.opacity)
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background(.white.opacity(0.08), in: .capsule)
                        .contentShape(.capsule)
                }
                .help(selection.isEmpty ? "Remove everything from the tray" : "Remove the selected files from the tray")
            }
            .buttonStyle(PressableStyle())
            .foregroundStyle(.white.opacity(0.8))
            .disabled(store.items.isEmpty)
            .opacity(store.items.isEmpty ? 0.4 : 1)
        }
        .animation(.smooth(duration: 0.2), value: isAirDropTargeted)
        .animation(.smooth(duration: 0.2), value: selection.isEmpty)
    }

    private var targetURLs: [URL] {
        selection.isEmpty ? store.urls : store.items.filter { selection.contains($0.id) }.map(\.url)
    }
}

private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}
