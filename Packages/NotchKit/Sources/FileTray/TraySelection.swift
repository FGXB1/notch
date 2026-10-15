import Foundation

/// Which tray items are selected, following Finder's mouse rules: a press selects (⌘ toggles, ⇧ extends
/// from the last plain pick), a press on an already selected item keeps the selection so all of it can be
/// dragged, and only a click (mouse-up without dragging) narrows it back to the one item.
public struct TraySelection: Equatable, Sendable {
    public private(set) var ids: Set<UUID> = []
    /// Where ⇧ ranges start from.
    private var anchor: UUID?

    public init() {}

    public var isEmpty: Bool { ids.isEmpty }
    public var count: Int { ids.count }

    public func contains(_ id: UUID) -> Bool {
        ids.contains(id)
    }

    /// Mouse down on `id`. `order` is the tray's order, for ranges.
    public mutating func press(_ id: UUID, in order: [UUID], command: Bool, shift: Bool) {
        if command {
            if ids.contains(id) {
                ids.remove(id)
                if anchor == id { anchor = nil }
            } else {
                ids.insert(id)
                anchor = id
            }
        } else if shift, let anchor, let from = order.firstIndex(of: anchor), let to = order.firstIndex(of: id) {
            ids = Set(order[min(from, to)...max(from, to)])
        } else if !ids.contains(id) {
            ids = [id]
            anchor = id
        }
    }

    /// Mouse up on `id` without a drag in between.
    public mutating func click(_ id: UUID, command: Bool, shift: Bool) {
        guard !command, !shift, ids.contains(id), ids.count > 1 else { return }
        ids = [id]
        anchor = id
    }

    public mutating func selectAll(_ order: [UUID]) {
        ids = Set(order)
        anchor = order.first
    }

    public mutating func clear() {
        ids.removeAll()
        anchor = nil
    }

    /// Drops ids of items that left the tray.
    public mutating func prune(keeping order: [UUID]) {
        let present = Set(order)
        ids.formIntersection(present)
        if let anchor, !present.contains(anchor) { self.anchor = nil }
    }

    /// What an action on `id` applies to: the whole selection if `id` is part of it, otherwise just `id`.
    /// In tray order.
    public func targets(for id: UUID, in order: [UUID]) -> [UUID] {
        ids.contains(id) ? order.filter(ids.contains) : [id]
    }
}
