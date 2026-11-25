import AppKit
import Carbon.HIToolbox
import KoolsCore
import SwiftUI

enum ClipboardTab: String, CaseIterable, Identifiable {
    case history = "History"
    case notes = "Notes"

    var id: String { rawValue }
}

/// Remembers text you copy for 12 hours, keeps a list of notes that never
/// expire, and shows both on a floating shelf-like panel that opens when you
/// copy something. The history lives in memory only. Notes are saved.
///
/// macOS has no pasteboard-change notification, so the pasteboard's change
/// count is checked twice a second.
@MainActor
@Observable
final class ClipboardService {
    private static let notesKey = "clipboard.notes"
    private static let autoHideDelay: Duration = .seconds(5)

    private(set) var history = ClipboardHistory()
    private(set) var notes: ClipboardNotes
    private(set) var isVisible = false
    /// Which list the panel and the Tools card show.
    var tab: ClipboardTab = .history

    @ObservationIgnored private var panel: ShelfPanel?
    @ObservationIgnored private var poller: Task<Void, Never>?
    @ObservationIgnored private var autoHide: Task<Void, Never>?
    @ObservationIgnored private var lastChangeCount = NSPasteboard.general.changeCount
    /// The panel opened because something was copied; it closes again by
    /// itself unless the pointer is on it or it is being used.
    @ObservationIgnored private var openedByCopy = false

    init() {
        notes = ClipboardNotes(data: UserDefaults.standard.data(forKey: Self.notesKey))
    }

    /// Something to offer: a copy from the last 12 hours, or a note.
    var hasPasteable: Bool { !history.isEmpty || !notes.isEmpty }

    // MARK: Recording

    func setEnabled(_ enabled: Bool) {
        if enabled, poller == nil {
            // What was copied before it was switched on is not recorded.
            lastChangeCount = NSPasteboard.general.changeCount
            poller = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                    self?.tick()
                }
            }
        } else if !enabled, poller != nil {
            poller?.cancel()
            poller = nil
            history.removeAll()
            hide()
        }
    }

    private func tick() {
        if history.hasExpired() { history.prune() }
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        let types = (pasteboard.types ?? []).map(\.rawValue)
        let hasFiles = pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        guard ClipboardHistory.isRecordable(types: types, hasFiles: hasFiles),
              let text = pasteboard.string(forType: .string),
              history.add(text)
        else { return }
        tab = .history
        if !isVisible {
            openedByCopy = true
            show()
        }
        if openedByCopy { scheduleAutoHide() }
    }

    // MARK: Showing

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let panel = panel ?? makePanel()
        panel.orderFrontRegardless()
        isVisible = true
    }

    func hide() {
        autoHide?.cancel()
        panel?.orderOut(nil)
        isVisible = false
        openedByCopy = false
    }

    private func makePanel() -> ShelfPanel {
        let panel = ShelfPanel(content: ClipboardView(service: self))
        // Bottom right, so it stays clear of the shelf at the middle of the edge.
        panel.place(near: nil)
        if let visible = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: panel.frame.origin.x, y: visible.minY + 16))
        }
        self.panel = panel
        return panel
    }

    private func scheduleAutoHide() {
        autoHide?.cancel()
        autoHide = Task { [weak self] in
            try? await Task.sleep(for: Self.autoHideDelay)
            while !Task.isCancelled {
                guard let self, self.openedByCopy, let panel = self.panel else { return }
                if panel.isKeyWindow {
                    // Someone is typing in it: leave it open.
                    self.openedByCopy = false
                    return
                }
                if !panel.frame.contains(NSEvent.mouseLocation) {
                    self.hide()
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: History

    func remove(_ entry: ClipboardEntry) {
        history.remove(entry.id)
    }

    func clearHistory() {
        history.removeAll()
    }

    // MARK: Notes

    @discardableResult
    func addNote(_ text: String) -> Bool {
        var updated = notes
        guard updated.add(text) else { return false }
        notes = updated
        saveNotes()
        return true
    }

    func updateNote(_ note: ClipboardNote, text: String) {
        var updated = notes
        guard updated.update(note.id, text: text) else { return }
        notes = updated
        saveNotes()
    }

    func removeNote(_ note: ClipboardNote) {
        notes.remove(note.id)
        saveNotes()
    }

    func moveNotes(from source: IndexSet, to destination: Int) {
        notes.move(fromOffsets: source, toOffset: destination)
        saveNotes()
    }

    private func saveNotes() {
        UserDefaults.standard.set(notes.encoded(), forKey: Self.notesKey)
    }

    // MARK: Putting text back

    /// Puts the text on the pasteboard without recording it again.
    func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }

    /// Types the text into whatever has focus: it goes on the pasteboard,
    /// ⌘V is pressed, and the previous pasteboard contents come back.
    func paste(_ text: String) async {
        let pasteboard = NSPasteboard.general
        let saved = Self.snapshot(of: pasteboard)
        copy(text)
        let ours = pasteboard.changeCount
        try? await Task.sleep(for: .milliseconds(60))
        Self.pressPaste()
        // The app reads the pasteboard a moment after ⌘V.
        try? await Task.sleep(for: .milliseconds(400))
        // If something else was copied meanwhile, that copy wins.
        guard pasteboard.changeCount == ours else { return }
        Self.restore(saved, to: pasteboard)
        lastChangeCount = pasteboard.changeCount
    }

    private static func snapshot(of pasteboard: NSPasteboard) -> [[(NSPasteboard.PasteboardType, Data)]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
    }

    private static func restore(_ saved: [[(NSPasteboard.PasteboardType, Data)]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let items = saved.map { entries in
            let item = NSPasteboardItem()
            for (type, data) in entries { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }

    private static func pressPaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        let code = keyCode(producing: "v") ?? CGKeyCode(kVK_ANSI_V)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    /// The key that types `character` in the current layout, so ⌘V works on
    /// layouts such as Dvorak where V isn't in the usual place.
    private static func keyCode(producing character: Character) -> CGKeyCode? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        for code in 0..<128 {
            var deadKeys: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout, UInt16(code), UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, characters.count, &length, &characters
            )
            if status == noErr, length > 0,
               String(utf16CodeUnits: characters, count: length).lowercased() == String(character) {
                return CGKeyCode(code)
            }
        }
        return nil
    }
}
