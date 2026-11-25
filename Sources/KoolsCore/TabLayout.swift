import Foundation

/// Something the user can put in priority order.
public protocol PriorityItem: RawRepresentable, CaseIterable, Hashable, Identifiable, Sendable
    where RawValue == String, AllCases == [Self] {
    var title: String { get }
    var symbol: String { get }
    /// An item that always stays last, whatever the saved order or a move says.
    static var pinnedLast: Self? { get }
}

extension PriorityItem {
    public var id: String { rawValue }
    public static var pinnedLast: Self? { nil }
}

/// The tabs of the menu bar panel. Each main feature gets its own tab; small
/// features share the Tools tab.
public enum PanelTab: String, PriorityItem {
    case repoRadar, tools

    /// Tools holds the small features, so it closes the tab bar.
    public static var pinnedLast: PanelTab? { .tools }

    public var title: String {
        switch self {
        case .repoRadar: "Repo Radar"
        case .tools: "Tools"
        }
    }

    public var symbol: String {
        switch self {
        case .repoRadar: "arrow.triangle.branch"
        case .tools: "square.grid.2x2"
        }
    }
}

/// The small features inside the Tools tab.
public enum ToolItem: String, PriorityItem {
    case shelf, quitOnClose, cutPaste, clipboard

    public var title: String {
        switch self {
        case .shelf: "Shelf"
        case .quitOnClose: "Quit on Close"
        case .cutPaste: "Cut & Paste"
        case .clipboard: "Clipboard"
        }
    }

    public var symbol: String {
        switch self {
        case .shelf: "tray.full"
        case .quitOnClose: "xmark.app"
        case .cutPaste: "scissors"
        case .clipboard: "doc.on.clipboard"
        }
    }
}

/// The user's priority for a set of items: an order over all of them, plus
/// which ones are hidden. The first visible item is the top priority.
public struct PriorityOrder<Item: PriorityItem>: Equatable, Sendable {
    public private(set) var order: [Item]
    public private(set) var hidden: Set<Item>

    /// Builds the order from saved raw values. Unknown names are dropped and
    /// items missing from the saved order are appended in their default place,
    /// so adding a feature later never loses the user's order.
    public init(order savedOrder: [String] = [], hidden savedHidden: [String] = []) {
        var order: [Item] = []
        for item in savedOrder.compactMap(Item.init(rawValue:)) where !order.contains(item) {
            order.append(item)
        }
        order += Item.allCases.filter { !order.contains($0) }
        self.order = Self.pinning(order)
        hidden = Set(savedHidden.compactMap(Item.init(rawValue:)))
        if visible.isEmpty { hidden.remove(order[0]) }
    }

    public static var `default`: Self { Self() }

    public var visible: [Item] { order.filter { !hidden.contains($0) } }

    private static func pinning(_ order: [Item]) -> [Item] {
        guard let last = Item.pinnedLast else { return order }
        return order.filter { $0 != last } + [last]
    }

    public var savedOrder: [String] { order.map(\.rawValue) }
    public var savedHidden: [String] { order.filter(hidden.contains).map(\.rawValue) }

    /// Same contract as SwiftUI's `onMove`.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.map { order[$0] }
        var rest = order.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        rest.insert(contentsOf: moving, at: min(max(insertAt, 0), rest.count))
        order = Self.pinning(rest)
    }

    /// Hiding the last visible item is refused, so nothing is ever empty.
    public mutating func setHidden(_ item: Item, _ isHidden: Bool) {
        if isHidden {
            guard visible != [item] else { return }
            hidden.insert(item)
        } else {
            hidden.remove(item)
        }
    }

    /// What to open on: the last one used while it's still shown, otherwise
    /// the top priority.
    public func opening(lastUsed: String?) -> Item {
        if let item = lastUsed.flatMap(Item.init(rawValue:)), !hidden.contains(item) { return item }
        return visible[0]
    }
}

public typealias TabLayout = PriorityOrder<PanelTab>
public typealias ToolLayout = PriorityOrder<ToolItem>
