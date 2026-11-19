@testable import KoolsCore
import XCTest

final class CutPasteRouterTests: XCTestCase {
    private func key(_ character: String, command: Bool = true, other: Bool = false) -> CutPasteRouter.KeyPress {
        .init(character: character, command: command, otherModifiers: other)
    }

    private func finder(changeCount: Int = 1, files: Bool = true, editing: Bool = false, frontmost: Bool = true) -> CutPasteRouter.Context {
        .init(finderIsFrontmost: frontmost, isEditingText: editing, pasteboardChangeCount: changeCount, pasteboardHasFiles: files)
    }

    func testCommandXInFinderBecomesCopy() {
        XCTAssertEqual(CutPasteRouter().action(for: key("x"), in: finder()), .copyAsCut)
    }

    func testOtherAppsTextFieldsAndModifiersPassThrough() {
        let router = CutPasteRouter()
        XCTAssertEqual(router.action(for: key("x"), in: finder(frontmost: false)), .pass)
        XCTAssertEqual(router.action(for: key("x"), in: finder(editing: true)), .pass)
        XCTAssertEqual(router.action(for: key("x", other: true), in: finder()), .pass)
        XCTAssertEqual(router.action(for: key("x", command: false), in: finder()), .pass)
        XCTAssertEqual(router.action(for: key("c"), in: finder()), .pass)
    }

    func testPasteWithoutCutIsNormalPaste() {
        XCTAssertEqual(CutPasteRouter().action(for: key("v"), in: finder()), .pass)
    }

    func testPasteAfterCutMoves() {
        var router = CutPasteRouter()
        router.recordCut(before: 4, after: 5, hasFiles: true)
        XCTAssertEqual(router.action(for: key("v"), in: finder(changeCount: 5)), .move)
    }

    func testCopyingSomethingElseCancelsTheCut() {
        var router = CutPasteRouter()
        router.recordCut(before: 4, after: 5, hasFiles: true)
        XCTAssertEqual(router.action(for: key("v"), in: finder(changeCount: 6)), .pass)
    }

    func testCutWithNothingSelectedRecordsNothing() {
        var router = CutPasteRouter()
        router.recordCut(before: 4, after: 4, hasFiles: true)
        XCTAssertFalse(router.hasPendingCut)
        router.recordCut(before: 4, after: 5, hasFiles: false)
        XCTAssertFalse(router.hasPendingCut)
    }

    func testPasteInsideTextFieldStaysNormalEvenWithCut() {
        var router = CutPasteRouter()
        router.recordCut(before: 1, after: 2, hasFiles: true)
        XCTAssertEqual(router.action(for: key("v"), in: finder(changeCount: 2, editing: true)), .pass)
    }

    func testClearEndsTheCut() {
        var router = CutPasteRouter()
        router.recordCut(before: 1, after: 2, hasFiles: true)
        router.clear()
        XCTAssertEqual(router.action(for: key("v"), in: finder(changeCount: 2)), .pass)
    }
}

final class QuitOnCloseTests: XCTestCase {
    private let selected: Set<String> = ["com.apple.Preview", "com.apple.finder"]
    private let big = QuitOnClose.ServerWindow(layer: 0, width: 800, height: 600, alpha: 1)

    func testQuitsSelectedAppWithNoWindows() {
        XCTAssertTrue(QuitOnClose.shouldQuit(bundleID: "com.apple.Preview", selected: selected, accessibilityWindowCount: 0, serverWindows: []))
    }

    func testKeepsUnselectedAndExemptApps() {
        XCTAssertFalse(QuitOnClose.shouldQuit(bundleID: "com.apple.Notes", selected: selected, accessibilityWindowCount: 0, serverWindows: []))
        XCTAssertFalse(QuitOnClose.shouldQuit(bundleID: "com.apple.finder", selected: selected, accessibilityWindowCount: 0, serverWindows: []))
        XCTAssertFalse(QuitOnClose.shouldQuit(bundleID: nil, selected: selected, accessibilityWindowCount: 0, serverWindows: []))
    }

    func testAnyRemainingWindowKeepsTheApp() {
        XCTAssertFalse(QuitOnClose.shouldQuit(bundleID: "com.apple.Preview", selected: selected, accessibilityWindowCount: 1, serverWindows: []))
        // Accessibility sees none, but the window server has one (another Space).
        XCTAssertFalse(QuitOnClose.shouldQuit(bundleID: "com.apple.Preview", selected: selected, accessibilityWindowCount: 0, serverWindows: [big]))
    }

    func testHelperSurfacesDoNotCountAsWindows() {
        let helpers = [
            QuitOnClose.ServerWindow(layer: 25, width: 800, height: 600, alpha: 1),
            QuitOnClose.ServerWindow(layer: 0, width: 20, height: 20, alpha: 1),
            QuitOnClose.ServerWindow(layer: 0, width: 800, height: 600, alpha: 0),
        ]
        XCTAssertTrue(QuitOnClose.shouldQuit(bundleID: "com.apple.Preview", selected: selected, accessibilityWindowCount: 0, serverWindows: helpers))
    }
}

final class ShelfItemsTests: XCTestCase {
    func testDeduplicatesAndSkipsBlankText() {
        let file = ShelfItem.file(URL(fileURLWithPath: "/tmp/a.txt"))
        var shelf = ShelfItems([file, .text("  \n"), file, .text("hello")])
        XCTAssertEqual(shelf.items, [file, .text("hello")])
        shelf.add([.text("hello")])
        XCTAssertEqual(shelf.items.count, 2)
    }

    func testPrunesMissingFilesOnly() {
        let kept = ShelfItem.file(URL(fileURLWithPath: "/kept"))
        let gone = ShelfItem.file(URL(fileURLWithPath: "/gone"))
        let link = ShelfItem.link(URL(string: "https://example.com")!)
        var shelf = ShelfItems([kept, gone, link])
        shelf.pruneMissingFiles { $0.path == "/kept" }
        XCTAssertEqual(shelf.items, [kept, link])
    }

    func testTitles() {
        XCTAssertEqual(ShelfItem.link(URL(string: "https://github.com/x")!).title, "github.com")
        XCTAssertEqual(ShelfItem.text("first line\nsecond").title, "first line")
        XCTAssertEqual(ShelfItem.text(String(repeating: "a", count: 70)).title.count, 61)
    }
}

final class ShakeDetectorTests: XCTestCase {
    func testShakeIsDetectedOnce() {
        var detector = ShakeDetector()
        let xs: [Double] = [0, 60, 0, 60, 0, 60, 0]
        let hits = xs.enumerated().map { detector.add(time: Double($0.offset) * 0.05, x: $0.element) }
        XCTAssertEqual(hits.filter { $0 }.count, 1)
    }

    func testStraightDragIsNotAShake() {
        var detector = ShakeDetector()
        let hits = (0..<20).map { detector.add(time: Double($0) * 0.02, x: Double($0) * 30) }
        XCTAssertFalse(hits.contains(true))
    }

    func testSlowWiggleIsNotAShake() {
        var detector = ShakeDetector()
        let xs: [Double] = [0, 60, 0, 60, 0, 60, 0]
        let hits = xs.enumerated().map { detector.add(time: Double($0.offset) * 0.3, x: $0.element) }
        XCTAssertFalse(hits.contains(true))
    }

    func testSmallJitterIsNotAShake() {
        var detector = ShakeDetector()
        let xs: [Double] = [0, 4, 0, 4, 0, 4, 0, 4]
        let hits = xs.enumerated().map { detector.add(time: Double($0.offset) * 0.02, x: $0.element) }
        XCTAssertFalse(hits.contains(true))
    }
}
