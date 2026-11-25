@testable import KoolsCore
import XCTest

final class ClipboardHistoryTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)
    private let hour: TimeInterval = 3600

    func testNewestFirst() {
        var history = ClipboardHistory()
        history.add("one", at: start)
        history.add("two", at: start + 1)
        XCTAssertEqual(history.entries.map(\.text), ["two", "one"])
    }

    func testEntryExpiresAfterTwelveHours() {
        var history = ClipboardHistory()
        history.add("old", at: start)
        history.add("new", at: start + 11 * hour)

        XCTAssertFalse(history.prune(now: start + 12 * hour - 1), "still inside its 12 hours")
        XCTAssertEqual(history.entries.count, 2)

        XCTAssertTrue(history.hasExpired(now: start + 12 * hour))
        XCTAssertTrue(history.prune(now: start + 12 * hour), "12 hours is the end of its life")
        XCTAssertEqual(history.entries.map(\.text), ["new"])

        XCTAssertTrue(history.prune(now: start + 23 * hour))
        XCTAssertTrue(history.isEmpty)
        XCTAssertFalse(history.hasExpired(now: start + 24 * hour))
    }

    func testCopyingTheSameTextAgainMovesItUpAndRestartsItsClock() {
        var history = ClipboardHistory()
        history.add("a", at: start)
        let id = history.entries[0].id
        history.add("b", at: start)
        history.add("a", at: start + 11 * hour)

        XCTAssertEqual(history.entries.map(\.text), ["a", "b"])
        XCTAssertEqual(history.entries[0].id, id, "same row, so a list doesn't flicker")
        history.prune(now: start + 12 * hour)
        XCTAssertEqual(history.entries.map(\.text), ["a"], "a was re-copied, b was not")
    }

    func testBlankAndHugeTextIsIgnored() {
        var history = ClipboardHistory()
        XCTAssertFalse(history.add("", at: start))
        XCTAssertFalse(history.add(" \n\t ", at: start))
        XCTAssertFalse(history.add(String(repeating: "x", count: ClipboardHistory.maxBytes + 1), at: start))
        XCTAssertTrue(history.isEmpty)
        XCTAssertTrue(history.add(String(repeating: "x", count: ClipboardHistory.maxBytes), at: start))
    }

    func testKeepsOnlyTheNewestFifty() {
        var history = ClipboardHistory()
        for number in 0..<(ClipboardHistory.maxEntries + 5) { history.add("item \(number)", at: start + Double(number)) }
        XCTAssertEqual(history.entries.count, ClipboardHistory.maxEntries)
        XCTAssertEqual(history.entries.first?.text, "item 54")
        XCTAssertEqual(history.entries.last?.text, "item 5")
    }

    func testRemoveAndClear() {
        var history = ClipboardHistory()
        history.add("a", at: start)
        history.add("b", at: start + 1)
        history.remove(history.entries[0].id)
        XCTAssertEqual(history.entries.map(\.text), ["a"])
        history.removeAll()
        XCTAssertTrue(history.isEmpty)
    }

    func testSecretAndFileCopiesAreNotRecordable() {
        XCTAssertTrue(ClipboardHistory.isRecordable(types: ["public.utf8-plain-text"], hasFiles: false))
        XCTAssertFalse(ClipboardHistory.isRecordable(
            types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"], hasFiles: false))
        XCTAssertFalse(ClipboardHistory.isRecordable(types: ["org.nspasteboard.TransientType"], hasFiles: false))
        XCTAssertFalse(ClipboardHistory.isRecordable(types: ["public.utf8-plain-text"], hasFiles: true))
    }

    func testPreviewIsOneShortLine() {
        XCTAssertEqual(ClipboardEntry.preview(of: "  first \n\n second  \n"), "first second")
        let long = ClipboardEntry.preview(of: String(repeating: "a", count: 300), limit: 10)
        XCTAssertEqual(long, String(repeating: "a", count: 10) + "…")
    }
}

final class ClipboardNotesTests: XCTestCase {
    func testAddKeepsOrderAndTrims() {
        var notes = ClipboardNotes()
        XCTAssertTrue(notes.add("  first \n"))
        XCTAssertTrue(notes.add("second"))
        XCTAssertEqual(notes.notes.map(\.text), ["first", "second"])
    }

    func testBlankNoteIsRejected() {
        var notes = ClipboardNotes()
        XCTAssertFalse(notes.add("  \n "))
        XCTAssertTrue(notes.isEmpty)
        notes.add("keep")
        XCTAssertFalse(notes.update(notes.notes[0].id, text: " "))
        XCTAssertEqual(notes.notes[0].text, "keep")
    }

    func testLongNoteIsCutAndListIsCapped() {
        var notes = ClipboardNotes()
        notes.add(String(repeating: "x", count: ClipboardNotes.maxLength + 50))
        XCTAssertEqual(notes.notes[0].text.count, ClipboardNotes.maxLength)
        for number in 1..<ClipboardNotes.maxNotes { XCTAssertTrue(notes.add("n\(number)")) }
        XCTAssertFalse(notes.add("one too many"))
        XCTAssertEqual(notes.notes.count, ClipboardNotes.maxNotes)
    }

    func testUpdateAndRemove() {
        var notes = ClipboardNotes()
        notes.add("a")
        notes.add("b")
        let id = notes.notes[0].id
        XCTAssertTrue(notes.update(id, text: " edited "))
        XCTAssertEqual(notes.notes[0].text, "edited")
        XCTAssertFalse(notes.update(UUID(), text: "ghost"))
        notes.remove(id)
        XCTAssertEqual(notes.notes.map(\.text), ["b"])
    }

    func testMoveMatchesOnMove() {
        var notes = ClipboardNotes()
        ["a", "b", "c"].forEach { notes.add($0) }
        notes.move(fromOffsets: [2], toOffset: 0)
        XCTAssertEqual(notes.notes.map(\.text), ["c", "a", "b"])
        notes.move(fromOffsets: [0], toOffset: 3)
        XCTAssertEqual(notes.notes.map(\.text), ["a", "b", "c"])
    }

    func testSurvivesSaveAndLoad() {
        var notes = ClipboardNotes()
        notes.add("keep me")
        XCTAssertEqual(ClipboardNotes(data: notes.encoded()), notes)
        XCTAssertTrue(ClipboardNotes(data: nil).isEmpty)
        XCTAssertTrue(ClipboardNotes(data: Data("not json".utf8)).isEmpty)
    }

    func testNotesDoNotExpire() {
        var notes = ClipboardNotes()
        notes.add("old note", at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(notes.notes.count, 1)
    }
}
