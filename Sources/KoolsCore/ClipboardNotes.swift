import Foundation

/// A short note typed by hand.
public struct ClipboardNote: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var text: String
    public let createdAt: Date
}

/// Notes the user keeps for text they paste often. Unlike the history they
/// never expire: they stay until deleted, in the order the user sets.
public struct ClipboardNotes: Equatable, Codable, Sendable {
    public static let maxNotes = 100
    public static let maxLength = 2_000

    public private(set) var notes: [ClipboardNote]

    public init(_ notes: [ClipboardNote] = []) {
        self.notes = notes
    }

    /// Loads saved notes. Missing or unreadable data gives an empty list.
    public init(data: Data?) {
        self = data.flatMap { try? JSONDecoder().decode(Self.self, from: $0) } ?? Self()
    }

    public func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    public var isEmpty: Bool { notes.isEmpty }

    /// Adds a note at the end. Returns false for blank text or a full list.
    /// Text over `maxLength` is cut off.
    @discardableResult
    public mutating func add(_ text: String, at date: Date = .now) -> Bool {
        guard notes.count < Self.maxNotes, let clean = Self.clean(text) else { return false }
        notes.append(ClipboardNote(id: UUID(), text: clean, createdAt: date))
        return true
    }

    /// Replaces a note's text. Returns false for blank text or an unknown note.
    @discardableResult
    public mutating func update(_ id: UUID, text: String) -> Bool {
        guard let index = notes.firstIndex(where: { $0.id == id }), let clean = Self.clean(text) else { return false }
        notes[index].text = clean
        return true
    }

    public mutating func remove(_ id: UUID) {
        notes.removeAll { $0.id == id }
    }

    /// Same contract as SwiftUI's `onMove`.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.map { notes[$0] }
        var rest = notes.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        rest.insert(contentsOf: moving, at: min(max(insertAt, 0), rest.count))
        notes = rest
    }

    private static func clean(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(maxLength))
    }
}
