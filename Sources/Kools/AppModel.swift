import AppKit
import KoolsCore
import Observation

/// Settings that survive relaunches. Every new feature starts off.
@MainActor
@Observable
final class Preferences {
    private let defaults = UserDefaults.standard
    @ObservationIgnored var onChange: (() -> Void)?

    var shelfEnabled: Bool {
        didSet { save(shelfEnabled, "shelf.enabled") }
    }
    var quitOnCloseEnabled: Bool {
        didSet { save(quitOnCloseEnabled, "quitOnClose.enabled") }
    }
    /// Bundle identifiers of the apps to quit when their last window closes.
    var quitOnCloseApps: [String] {
        didSet { save(quitOnCloseApps, "quitOnClose.apps") }
    }
    /// Quit every app on its last window close, except the exempt ones.
    var quitOnCloseAllApps: Bool {
        didSet { save(quitOnCloseAllApps, "quitOnClose.allApps") }
    }
    /// Bundle identifiers never quit while `quitOnCloseAllApps` is on.
    var quitOnCloseExempt: [String] {
        didSet { save(quitOnCloseExempt, "quitOnClose.exempt") }
    }
    var cutPasteEnabled: Bool {
        didSet { save(cutPasteEnabled, "cutPaste.enabled") }
    }
    var clipboardEnabled: Bool {
        didSet { save(clipboardEnabled, "clipboard.enabled") }
    }
    /// Show a paste button at the text field being typed in. Needs Accessibility.
    var clipboardPasteButton: Bool {
        didSet { save(clipboardPasteButton, "clipboard.pasteButton") }
    }
    /// Ask T3 Code for a commit message when a repo with changes is opened.
    /// On by default.
    var autoCommitMessages: Bool {
        didSet { save(autoCommitMessages, "repoRadar.autoCommitMessages") }
    }
    /// Tab priority for the menu bar panel and the settings window.
    var tabLayout: TabLayout {
        didSet {
            defaults.set(tabLayout.savedOrder, forKey: "tabs.order")
            defaults.set(tabLayout.savedHidden, forKey: "tabs.hidden")
        }
    }
    /// Order of the small features inside the Tools tab.
    var toolLayout: ToolLayout {
        didSet {
            defaults.set(toolLayout.savedOrder, forKey: "tools.order")
            defaults.set(toolLayout.savedHidden, forKey: "tools.hidden")
        }
    }

    init() {
        shelfEnabled = defaults.bool(forKey: "shelf.enabled")
        quitOnCloseEnabled = defaults.bool(forKey: "quitOnClose.enabled")
        quitOnCloseApps = defaults.stringArray(forKey: "quitOnClose.apps") ?? []
        quitOnCloseAllApps = defaults.bool(forKey: "quitOnClose.allApps")
        quitOnCloseExempt = defaults.stringArray(forKey: "quitOnClose.exempt") ?? []
        cutPasteEnabled = defaults.bool(forKey: "cutPaste.enabled")
        clipboardEnabled = defaults.bool(forKey: "clipboard.enabled")
        clipboardPasteButton = defaults.object(forKey: "clipboard.pasteButton") as? Bool ?? true
        autoCommitMessages = defaults.object(forKey: "repoRadar.autoCommitMessages") as? Bool ?? true
        tabLayout = TabLayout(
            order: defaults.stringArray(forKey: "tabs.order") ?? [],
            hidden: defaults.stringArray(forKey: "tabs.hidden") ?? []
        )
        toolLayout = ToolLayout(
            order: defaults.stringArray(forKey: "tools.order") ?? [],
            hidden: defaults.stringArray(forKey: "tools.hidden") ?? []
        )
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        onChange?()
    }
}

/// Accessibility permission, rechecked every two seconds so granting or
/// revoking it in System Settings takes effect without a relaunch.
@MainActor
@Observable
final class AccessibilityAccess {
    private(set) var isTrusted = AXIsProcessTrusted()
    @ObservationIgnored var onChange: (() -> Void)?

    init() {
        Task { [weak self] in
            while let self {
                let trusted = AXIsProcessTrusted()
                if trusted != self.isTrusted {
                    self.isTrusted = trusted
                    self.onChange?()
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// Shows the system prompt (first time only) and opens the settings pane.
    func request() {
        // The key is the value of kAXTrustedCheckOptionPrompt.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Owns every feature and switches each one on or off from the preferences.
@MainActor
@Observable
final class AppModel {
    let radar = RadarModel()
    let preferences = Preferences()
    let access = AccessibilityAccess()
    let shelf = ShelfService()
    let cutPaste = CutPasteService()
    let clipboard = ClipboardService()
    @ObservationIgnored private let quitOnClose = QuitOnCloseService()
    @ObservationIgnored private let pasteButton: PasteButtonService

    init() {
        pasteButton = PasteButtonService(clipboard: clipboard)
        preferences.onChange = { [weak self] in self?.apply() }
        access.onChange = { [weak self] in self?.apply() }
        cutPaste.onCut = { [weak self] urls in self?.shelf.parkCut(urls) }
        cutPaste.onMove = { [weak self] urls in self?.shelf.cutWasPasted(urls) }
        apply()
    }

    /// A feature that needs Accessibility is on, but access isn't granted.
    var needsPermission: Bool {
        permissionCount > 0
    }

    /// The paste button is the part of Clipboard that needs Accessibility.
    private var clipboardNeedsAccessibility: Bool {
        preferences.clipboardEnabled && preferences.clipboardPasteButton
    }

    /// Features that are on but lack Accessibility access.
    private var permissionCount: Int {
        guard !access.isTrusted else { return 0 }
        return [preferences.quitOnCloseEnabled, preferences.cutPasteEnabled, clipboardNeedsAccessibility].filter { $0 }.count
    }

    /// What the menu bar shows in place of the app icon, most urgent first.
    var statusNeeds: [StatusNeed] {
        StatusBadge.needs(reports: radar.allReports, permissionCount: permissionCount)
    }

    /// The dot on a tab's icon in the panel.
    func badge(for tab: PanelTab) -> StatusBadge? {
        switch tab {
        case .repoRadar: StatusBadge.top(reports: radar.allReports, needsPermission: false)
        case .tools: needsPermission ? .permission : nil
        }
    }

    /// The dot on a tool's row in the Tools tab.
    func badge(for tool: ToolItem) -> StatusBadge? {
        switch tool {
        case .shelf: nil
        case .quitOnClose: preferences.quitOnCloseEnabled && !access.isTrusted ? .permission : nil
        case .cutPaste: preferences.cutPasteEnabled && !access.isTrusted ? .permission : nil
        case .clipboard: clipboardNeedsAccessibility && !access.isTrusted ? .permission : nil
        }
    }

    private func apply() {
        shelf.setEnabled(preferences.shelfEnabled)
        clipboard.setEnabled(preferences.clipboardEnabled)
        pasteButton.setActive(clipboardNeedsAccessibility && access.isTrusted)
        cutPaste.setActive(preferences.cutPasteEnabled && access.isTrusted)
        quitOnClose.update(
            active: preferences.quitOnCloseEnabled && access.isTrusted,
            rule: QuitOnClose.Rule(
                allApps: preferences.quitOnCloseAllApps,
                selected: Set(preferences.quitOnCloseApps),
                exempt: Set(preferences.quitOnCloseExempt)
            )
        )
    }
}
