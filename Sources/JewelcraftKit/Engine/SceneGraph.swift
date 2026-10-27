//
//  SceneGraph.swift
//  JewelcraftKit
//
//  The addressable scene graph and its undo history.
//
//  The recovered CAD contract was full of identity operations that only make
//  sense if geometry is addressable: highlight this graph item, highlight the
//  items under this block instance GUID, remove a user-data value from an item,
//  undo a change to the graph. A ring built as one anonymous blob cannot support
//  any of that, so the graph exists as a first-class model rather than as a
//  renderer detail.
//
//  Undo is snapshotted rather than journaled. A configuration is a small value,
//  and snapshots cannot drift out of sync with the model they undo — which is
//  the failure mode that makes a configurator untrustworthy.
//

import Foundation

// MARK: - Graph identity

public struct GraphItemID: StringIdentifiable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public enum GraphItemKind: String, Codable, CaseIterable, Sendable {
    case root
    case design
    case partGroup
    case shank
    case head
    case prong
    case gem
    case curve
    case railGuide
    case value

    public var displayName: String {
        switch self {
        case .root: return "Model"
        case .design: return "Design"
        case .partGroup: return "Part group"
        case .shank: return "Shank"
        case .head: return "Head"
        case .prong: return "Prong"
        case .gem: return "Stone"
        case .curve: return "Curve"
        case .railGuide: return "Rail guide"
        case .value: return "Value"
        }
    }
}

/// One addressable item in the model.
public struct GraphItem: Codable, Hashable, Identifiable, Sendable {
    public var id: GraphItemID
    public var name: String
    public var kind: GraphItemKind
    public var parentID: GraphItemID?
    /// Free-form data the CAD side attaches to an item, mirroring the recovered
    /// graph user data.
    public var userData: [String: String]
    /// The assembled part this item stands for, when it maps to geometry.
    public var partGroupID: String?
    public var gemSlotIndex: Int?
    public var isVisible: Bool

    public init(
        id: GraphItemID,
        name: String,
        kind: GraphItemKind,
        parentID: GraphItemID? = nil,
        userData: [String: String] = [:],
        partGroupID: String? = nil,
        gemSlotIndex: Int? = nil,
        isVisible: Bool = true
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.parentID = parentID
        self.userData = userData
        self.partGroupID = partGroupID
        self.gemSlotIndex = gemSlotIndex
        self.isVisible = isVisible
    }
}

/// The model, as a tree of addressable items.
public struct SceneGraph: Equatable, Sendable {
    public var rootID: GraphItemID
    /// Ordered; the root is always first.
    public var items: [GraphItem]
    /// Highlighted items, which is what the recovered highlight round trip
    /// carried between the client and the CAD service.
    public private(set) var highlightedIDs: Set<GraphItemID>

    public init(root: GraphItem) {
        self.rootID = root.id
        self.items = [root]
        self.highlightedIDs = []
    }

    public init(rootID: GraphItemID, items: [GraphItem], highlightedIDs: Set<GraphItemID> = []) {
        self.rootID = rootID
        self.items = items
        self.highlightedIDs = highlightedIDs
    }

    // MARK: - Access

    public var root: GraphItem? {
        items.first { $0.id == rootID }
    }

    public var count: Int { items.count }

    public func item(id: GraphItemID) -> GraphItem? {
        items.first { $0.id == id }
    }

    public func items(ofKind kind: GraphItemKind) -> [GraphItem] {
        items.filter { $0.kind == kind }
    }

    public func items(withPartGroupID partGroupID: String) -> [GraphItem] {
        items.filter { $0.partGroupID == partGroupID }
    }

    public func items(forGemSlot slotIndex: Int) -> [GraphItem] {
        items.filter { $0.gemSlotIndex == slotIndex }
    }

    public func children(of parentID: GraphItemID) -> [GraphItem] {
        items.filter { $0.parentID == parentID }
    }

    /// Every descendant of an item, breadth-first.
    public func descendants(of parentID: GraphItemID) -> [GraphItem] {
        var result: [GraphItem] = []
        var queue = children(of: parentID)
        while let next = queue.first {
            queue.removeFirst()
            result.append(next)
            queue.append(contentsOf: children(of: next.id))
        }
        return result
    }

    public var highlightedItems: [GraphItem] {
        items.filter { highlightedIDs.contains($0.id) }
    }

    public func isHighlighted(_ id: GraphItemID) -> Bool {
        highlightedIDs.contains(id)
    }

    // MARK: - Mutation

    public mutating func append(_ item: GraphItem) {
        guard !items.contains(where: { $0.id == item.id }) else { return }
        items.append(item)
    }

    public mutating func append(contentsOf newItems: [GraphItem]) {
        for item in newItems {
            append(item)
        }
    }

    @discardableResult
    public mutating func remove(id: GraphItemID) -> Bool {
        guard id != rootID else { return false }
        let doomed = Set(descendants(of: id).map(\.id) + [id])
        let before = items.count
        items.removeAll { doomed.contains($0.id) }
        highlightedIDs.subtract(doomed)
        return items.count != before
    }

    public mutating func setUserData(_ value: String?, forKey key: String, on id: GraphItemID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        if let value {
            items[index].userData[key] = value
        } else {
            items[index].userData.removeValue(forKey: key)
        }
    }

    /// The recovered `GraphItemRemoveUserDataValue` operation.
    public mutating func removeUserDataValue(_ key: String, on id: GraphItemID) {
        setUserData(nil, forKey: key, on: id)
    }

    public mutating func setVisibility(_ isVisible: Bool, on id: GraphItemID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isVisible = isVisible
    }

    // MARK: - Highlighting

    public mutating func highlight(_ id: GraphItemID, enabled: Bool = true) {
        if enabled {
            highlightedIDs.insert(id)
        } else {
            highlightedIDs.remove(id)
        }
    }

    /// Highlighting by block instance GUID, the recovered
    /// `HighlightItemsByBlockInstanceGuid` operation.
    public mutating func highlightItems(byBlockInstanceGUID guid: String, enabled: Bool = true) {
        for item in items where item.userData["blockInstanceGUID"] == guid {
            highlight(item.id, enabled: enabled)
        }
    }

    public mutating func highlightGemSlot(_ slotIndex: Int, enabled: Bool = true) {
        for item in items(forGemSlot: slotIndex) {
            highlight(item.id, enabled: enabled)
        }
    }

    public mutating func highlightItems(inPartGroup partGroupID: String, enabled: Bool = true) {
        for item in items(withPartGroupID: partGroupID) {
            highlight(item.id, enabled: enabled)
        }
    }

    /// Highlights every accent stone, the recovered `HighlightAccentGems`.
    public mutating func highlightAccentGems(enabled: Bool = true) {
        for item in items where item.kind == .gem && item.userData["role"] == GemRole.accent.rawValue {
            highlight(item.id, enabled: enabled)
        }
    }

    public mutating func clearHighlights() {
        highlightedIDs.removeAll()
    }

    // MARK: - Integrity

    public func integrityIssues() -> [String] {
        var issues: [String] = []
        let ids = Set(items.map(\.id))
        if items.isEmpty {
            issues.append("scene graph is empty")
        }
        if !ids.contains(rootID) {
            issues.append("scene graph has no item matching its root id")
        }
        if items.first?.id != rootID {
            issues.append("scene graph root is not the first item")
        }
        for item in items {
            if let parentID = item.parentID, !ids.contains(parentID) {
                issues.append("item \(item.id.rawValue) has a missing parent \(parentID.rawValue)")
            }
        }
        if Set(items.map(\.id)).count != items.count {
            issues.append("scene graph contains duplicate item ids")
        }
        for id in highlightedIDs where !ids.contains(id) {
            issues.append("highlighted item \(id.rawValue) is not in the graph")
        }
        return issues
    }
}

// MARK: - Undo

/// A snapshot undo history.
///
/// `record` ignores a state identical to the current one, so re-applying the
/// same value does not fill the history with no-ops and make the undo button
/// look broken.
public struct UndoStack<State: Equatable> {

    public private(set) var states: [State]
    public private(set) var cursor: Int
    public let limit: Int

    public init(initial: State, limit: Int = 64) {
        self.states = [initial]
        self.cursor = 0
        self.limit = Swift.max(2, limit)
    }

    public var current: State {
        states[cursor]
    }

    public var canUndo: Bool { cursor > 0 }
    public var canRedo: Bool { cursor < states.count - 1 }
    /// Total states held, including the current one.
    public var depth: Int { states.count }

    public mutating func record(_ state: State) {
        guard state != current else { return }
        // Recording after an undo discards the redo branch, which is what every
        // editor does and what users expect.
        if cursor < states.count - 1 {
            states.removeSubrange((cursor + 1)...)
        }
        states.append(state)
        if states.count > limit {
            let overflow = states.count - limit
            states.removeFirst(overflow)
        }
        cursor = states.count - 1
    }

    /// Steps back one state, or returns nil at the beginning of history.
    public mutating func undo() -> State? {
        guard canUndo else { return nil }
        cursor -= 1
        return states[cursor]
    }

    /// Steps forward one state, or returns nil at the end of history.
    public mutating func redo() -> State? {
        guard canRedo else { return nil }
        cursor += 1
        return states[cursor]
    }

    /// Clears the history and starts again from `state`.
    public mutating func reset(to state: State) {
        states = [state]
        cursor = 0
    }

    public var summary: String {
        "\(cursor + 1) of \(states.count), \(canUndo ? "can undo" : "at start"), \(canRedo ? "can redo" : "at end")"
    }
}
