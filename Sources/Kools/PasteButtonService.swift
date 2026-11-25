import AppKit
import SwiftUI

/// Shows a small button at the text field you are typing in. It opens the
/// clipboard history and notes; picking one pastes it into that field.
///
/// The field is found through Accessibility, so apps that don't report
/// their focused field get no button. Password fields are skipped. The
/// panels never take focus, so the field keeps the cursor.
@MainActor
final class PasteButtonService {
    private static let buttonSize: CGFloat = 24
    private static let menuSize = CGSize(width: 260, height: 240)

    private let clipboard: ClipboardService
    private var loop: Task<Void, Never>?
    private var button: PopupPanel?
    private var menu: PopupPanel?
    private var outsideClick: Any?

    init(clipboard: ClipboardService) {
        self.clipboard = clipboard
    }

    func setActive(_ active: Bool) {
        if active, loop == nil {
            loop = Task { [weak self] in
                while !Task.isCancelled {
                    self?.refresh()
                    try? await Task.sleep(for: .milliseconds(300))
                }
            }
        } else if !active, loop != nil {
            loop?.cancel()
            loop = nil
            hideAll()
        }
    }

    // MARK: Following the text field

    private func refresh() {
        guard clipboard.hasPasteable,
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let field = Self.focusedTextField(of: app.processIdentifier)
        else {
            hideAll()
            return
        }
        let panel = button ?? makeButton()
        panel.setFrameOrigin(Self.buttonOrigin(for: field))
        panel.orderFrontRegardless()
    }

    /// The frame of the focused, non-password text field, if there is one.
    private static func focusedTextField(of pid: pid_t) -> CGRect? {
        // Short timeout: this runs on the main thread, so a stuck app mustn't stall Kools.
        guard let element = AX.element(AX.application(pid, timeout: 0.15), kAXFocusedUIElementAttribute),
              let role = AX.string(element, kAXRoleAttribute),
              role == kAXTextFieldRole || role == kAXTextAreaRole || role == kAXComboBoxRole,
              AX.string(element, kAXSubroleAttribute) != kAXSecureTextFieldSubrole,
              let frame = AX.frame(element),
              frame.width >= 80, frame.height >= 16
        else { return nil }
        return frame
    }

    /// Inside the field's right edge: centered on a one-line field, in the
    /// top corner of a tall one.
    private static func buttonOrigin(for field: CGRect) -> NSPoint {
        let size = buttonSize
        let x = field.maxX - size - 6
        let y = field.height <= 44 ? field.midY - size / 2 : field.maxY - size - 6
        return NSPoint(x: x, y: y)
    }

    // MARK: Panels

    private func makeButton() -> PopupPanel {
        let size = CGSize(width: Self.buttonSize, height: Self.buttonSize)
        let panel = PopupPanel(size: size, content: PasteButtonView { [weak self] in self?.toggleMenu() })
        button = panel
        return panel
    }

    private func toggleMenu() {
        if let menu, menu.isVisible {
            hideMenu()
            return
        }
        guard let button else { return }
        let menu = menu ?? PopupPanel(
            size: Self.menuSize,
            content: PasteMenuView(service: clipboard) { [weak self] text in self?.choose(text) }
        )
        self.menu = menu
        menu.setFrameOrigin(Self.menuOrigin(below: button.frame))
        menu.orderFrontRegardless()
        // A click anywhere outside Kools' panels closes the menu.
        outsideClick = outsideClick ?? NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hideMenu() }
        }
    }

    /// Under the button with their right edges aligned, above it when there
    /// is no room below, and always on screen.
    private static func menuOrigin(below button: CGRect) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.intersects(button) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return button.origin }
        var origin = NSPoint(x: button.maxX - menuSize.width, y: button.minY - 6 - menuSize.height)
        if origin.y < visible.minY { origin.y = button.maxY + 6 }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - menuSize.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - menuSize.height - 8)
        return origin
    }

    private func choose(_ text: String) {
        hideMenu()
        Task { await clipboard.paste(text) }
    }

    private func hideMenu() {
        menu?.orderOut(nil)
        if let outsideClick {
            NSEvent.removeMonitor(outsideClick)
            self.outsideClick = nil
        }
    }

    private func hideAll() {
        hideMenu()
        button?.orderOut(nil)
    }
}

/// A small floating panel that never becomes key or active, so the app and
/// text field you are working in keep focus while you click it.
final class PopupPanel: NSPanel {
    init(size: CGSize, content: some View) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        contentView = NSHostingView(rootView: content)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
