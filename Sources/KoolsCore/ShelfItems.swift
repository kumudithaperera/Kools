import Foundation

/// Something parked on the shelf. Files are kept by reference, never copied.
public enum ShelfItem: Hashable, Identifiable, Sendable {
    case file(URL)
    case link(URL)
    case text(String)

    public var id: Self { self }

    public var title: String {
        switch self {
        case .file(let url): url.lastPathComponent
        case .link(let url): url.host() ?? url.absoluteString
        case .text(let text): Self.firstLine(of: text)
        }
    }

    static func firstLine(of text: String, limit: Int = 60) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count > limit ? String(trimmed.prefix(limit)) + "…" : trimmed
    }
}

/// The shelf's contents, newest last.
public struct ShelfItems: Sendable, Equatable {
    public private(set) var items: [ShelfItem] = []

    public init(_ items: [ShelfItem] = []) {
        self.items = []
        add(items)
    }

    public var isEmpty: Bool { items.isEmpty }

    /// Adds new items and skips ones already on the shelf. Empty text is ignored.
    public mutating func add(_ new: [ShelfItem]) {
        for item in new {
            if case .text(let text) = item, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            if !items.contains(item) { items.append(item) }
        }
    }

    public mutating func remove(_ item: ShelfItem) {
        items.removeAll { $0 == item }
    }

    public mutating func removeAll() {
        items.removeAll()
    }

    /// Drops files that no longer exist at their path, for example after
    /// they were dragged off the shelf and moved.
    public mutating func pruneMissingFiles(exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) {
        items.removeAll { item in
            if case .file(let url) = item { return !exists(url) }
            return false
        }
    }
}
