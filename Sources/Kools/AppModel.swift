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
    var cutPasteEnabled: Bool {
        didSet { save(cutPasteEnabled, "cutPaste.enabled") }
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
        cutPasteEnabled = defaults.bool(forKey: "cutPaste.enabled")
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
    @ObservationIgnored private let quitOnClose = QuitOnCloseService()

    init() {
        preferences.onChange = { [weak self] in self?.apply() }
        access.onChange = { [weak self] in self?.apply() }
        apply()
    }

    /// A feature that needs Accessibility is on, but access isn't granted.
    var needsPermission: Bool {
        (preferences.quitOnCloseEnabled || preferences.cutPasteEnabled) && !access.isTrusted
    }

    /// What the menu bar shows in place of the app icon, if anything.
    var statusBadge: StatusBadge? {
        StatusBadge.top(reports: radar.allReports, needsPermission: needsPermission)
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
        }
    }

    private func apply() {
        shelf.setEnabled(preferences.shelfEnabled)
        cutPaste.setActive(preferences.cutPasteEnabled && access.isTrusted)
        quitOnClose.update(
            active: preferences.quitOnCloseEnabled && access.isTrusted,
            bundleIDs: Set(preferences.quitOnCloseApps)
        )
    }
}
