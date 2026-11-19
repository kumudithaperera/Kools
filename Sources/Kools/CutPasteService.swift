import AppKit
import KoolsCore
import os

/// Finder cut and paste: ⌘X runs Finder's Copy and remembers it as a cut,
/// the next ⌘V becomes Finder's ⌥⌘V (Move Item Here). See `CutPasteRouter`.
///
/// A keyboard event tap claims only plain ⌘X and ⌘V, only while Finder is
/// in front and no text field is being edited. Needs Accessibility.
@MainActor
@Observable
final class CutPasteService {
    private static let finderID = "com.apple.finder"
    private static let log = Logger(subsystem: "local.kools", category: "cut-paste")

    /// Files waiting for ⌘V; 0 when no cut is pending.
    private(set) var pendingFileCount = 0

    /// Called with the cut files once Finder's copy lands on the pasteboard.
    @ObservationIgnored var onCut: (([URL]) -> Void)?
    /// Called with the cut files when ⌘V turns into a move.
    @ObservationIgnored var onMove: (([URL]) -> Void)?
    @ObservationIgnored private var cutURLs: [URL] = []

    @ObservationIgnored private var tap: CFMachPort?
    @ObservationIgnored private var source: CFRunLoopSource?
    @ObservationIgnored private var router = CutPasteRouter() {
        didSet { if !router.hasPendingCut { pendingFileCount = 0 } }
    }
    /// Key codes whose key-up must get the same treatment as their key-down.
    @ObservationIgnored private var swallowedKeyUps: Set<Int64> = []
    @ObservationIgnored private var movedKeyUps: Set<Int64> = []

    /// Drops a pending cut that something else has overwritten on the pasteboard.
    func refreshPending() {
        if let pending = router.pendingCutChangeCount, pending != NSPasteboard.general.changeCount {
            router.clear()
        }
    }

    func setActive(_ active: Bool) {
        if active, tap == nil { start() } else if !active, tap != nil { stop() }
    }

    private func start() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: cutPasteTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Self.log.error("Couldn't create the key event tap; Accessibility is probably not granted")
            return
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
    }

    private func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        router.clear()
        swallowedKeyUps.removeAll()
        movedKeyUps.removeAll()
    }

    /// Returns false to swallow the event.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return true
        case .keyUp:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            if swallowedKeyUps.remove(code) != nil { return false }
            if movedKeyUps.remove(code) != nil { event.flags.insert(.maskAlternate) }
            return true
        case .keyDown:
            return handleKeyDown(event)
        default:
            return true
        }
    }

    private func handleKeyDown(_ event: CGEvent) -> Bool {
        let flags = event.flags
        // Fast exit for every key that isn't a Command shortcut.
        guard flags.contains(.maskCommand),
              let character = NSEvent(cgEvent: event)?.charactersIgnoringModifiers?.lowercased(),
              character == "x" || character == "v",
              let finder = NSWorkspace.shared.frontmostApplication,
              finder.bundleIdentifier == Self.finderID
        else { return true }

        let pasteboard = NSPasteboard.general
        let key = CutPasteRouter.KeyPress(
            character: character,
            command: true,
            otherModifiers: !flags.isDisjoint(with: [.maskShift, .maskAlternate, .maskControl])
        )
        let context = CutPasteRouter.Context(
            finderIsFrontmost: true,
            isEditingText: Self.isEditingText(in: finder.processIdentifier),
            pasteboardChangeCount: pasteboard.changeCount,
            pasteboardHasFiles: Self.hasFiles(pasteboard)
        )
        let code = event.getIntegerValueField(.keyboardEventKeycode)

        switch router.action(for: key, in: context) {
        case .pass:
            return true
        case .copyAsCut:
            swallowedKeyUps.insert(code)
            // Holding ⌘X repeats the key; one cut is enough.
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                let pid = finder.processIdentifier
                Task { await self.cut(in: pid) }
            }
            return false
        case .move:
            event.flags.insert(.maskAlternate)
            movedKeyUps.insert(code)
            router.clear()
            onMove?(cutURLs)
            cutURLs = []
            return true
        }
    }

    private func cut(in pid: pid_t) async {
        let pasteboard = NSPasteboard.general
        let before = pasteboard.changeCount
        guard Self.pressCopy(in: pid) else {
            NSSound.beep()
            return
        }
        // Finder writes the pasteboard shortly after the menu action.
        try? await Task.sleep(for: .milliseconds(300))
        router.recordCut(before: before, after: pasteboard.changeCount, hasFiles: Self.hasFiles(pasteboard))
        cutURLs = router.hasPendingCut
            ? pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
            : []
        pendingFileCount = cutURLs.count
        if !cutURLs.isEmpty { onCut?(cutURLs) }
    }

    /// Presses Finder's own Edit ▸ Copy through Accessibility, found by its
    /// ⌘C shortcut so it works in every language and keyboard layout.
    private static func pressCopy(in pid: pid_t) -> Bool {
        let app = AX.application(pid, timeout: 0.5)
        guard let menuBar = AX.element(app, kAXMenuBarAttribute) else { return false }
        for barItem in AX.elements(menuBar, kAXChildrenAttribute) ?? [] {
            for menu in AX.elements(barItem, kAXChildrenAttribute) ?? [] {
                for item in AX.elements(menu, kAXChildrenAttribute) ?? [] {
                    guard AX.string(item, kAXMenuItemCmdCharAttribute) == "C",
                          (AX.value(item, kAXMenuItemCmdModifiersAttribute) as? Int) == 0
                    else { continue }
                    guard (AX.value(item, kAXEnabledAttribute) as? Bool) == true else { return false }
                    return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
                }
            }
        }
        return false
    }

    /// True while a text field has focus, such as renaming a file.
    private static func isEditingText(in pid: pid_t) -> Bool {
        guard let focused = AX.element(AX.application(pid), kAXFocusedUIElementAttribute) else { return false }
        let role = AX.string(focused, kAXRoleAttribute)
        return role == kAXTextFieldRole || role == kAXTextAreaRole || role == kAXComboBoxRole
            || AX.string(focused, kAXSubroleAttribute) == kAXSearchFieldSubrole
    }

    private static func hasFiles(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }
}

/// The tap runs on the main run loop, so the service is used on the main actor.
private func cutPasteTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let service = Unmanaged<CutPasteService>.fromOpaque(userInfo).takeUnretainedValue()
    // The callback already runs on the main thread; the event never leaves it.
    nonisolated(unsafe) let event = event
    let keep = MainActor.assumeIsolated { service.handle(type: type, event: event) }
    return keep ? Unmanaged.passUnretained(event) : nil
}
