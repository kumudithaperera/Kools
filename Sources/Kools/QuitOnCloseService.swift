import AppKit
import KoolsCore
import os

/// Quits chosen apps when their last window closes. Watches each running
/// chosen app's windows through Accessibility and, half a second after one
/// closes, quits the app if `QuitOnClose.shouldQuit` agrees. Apps quit the
/// normal way, so unsaved documents still ask first.
@MainActor
final class QuitOnCloseService {
    private static let log = Logger(subsystem: "local.kools", category: "quit-on-close")

    private var active = false
    private var bundleIDs: Set<String> = []
    private var watchers: [pid_t: WindowWatcher] = [:]
    private var pendingChecks: [pid_t: Task<Void, Never>] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []

    func update(active: Bool, bundleIDs: Set<String>) {
        self.bundleIDs = bundleIDs
        if active != self.active {
            self.active = active
            active ? start() : stop()
        } else if active {
            syncWatchers()
        }
    }

    private func start() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // A new app needs a moment before Accessibility can see it.
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(1))
                    self?.syncWatchers()
                }
            })
        }
        syncWatchers()
    }

    private func stop() {
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers.removeAll()
        pendingChecks.values.forEach { $0.cancel() }
        pendingChecks.removeAll()
        watchers.values.forEach { $0.invalidate() }
        watchers.removeAll()
    }

    private func syncWatchers() {
        guard active else { return }
        let wanted = NSWorkspace.shared.runningApplications.filter { app in
            guard let id = app.bundleIdentifier, !app.isTerminated else { return false }
            return bundleIDs.contains(id) && !QuitOnClose.alwaysExempt.contains(id)
        }
        let wantedPIDs = Set(wanted.map(\.processIdentifier))

        for (pid, watcher) in watchers where !wantedPIDs.contains(pid) {
            watcher.invalidate()
            watchers[pid] = nil
            pendingChecks.removeValue(forKey: pid)?.cancel()
        }
        for app in wanted where watchers[app.processIdentifier] == nil {
            let pid = app.processIdentifier
            if let watcher = WindowWatcher(pid: pid, onWindowClosed: { [weak self] in self?.windowClosed(in: app) }) {
                watchers[pid] = watcher
            }
        }
    }

    /// Closing several windows at once (⌥⌘W) gives one check, not many.
    private func windowClosed(in app: NSRunningApplication) {
        let pid = app.processIdentifier
        pendingChecks[pid]?.cancel()
        pendingChecks[pid] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self, !app.isTerminated else { return }
            self.pendingChecks[pid] = nil
            guard let axCount = AX.elements(AX.application(pid), kAXWindowsAttribute)?.count else { return }
            let quit = QuitOnClose.shouldQuit(
                bundleID: app.bundleIdentifier,
                selected: self.bundleIDs,
                accessibilityWindowCount: axCount,
                serverWindows: Self.serverWindows(of: pid)
            )
            if quit {
                Self.log.notice("Quitting \(app.bundleIdentifier ?? "?", privacy: .public): last window closed")
                app.terminate()
            }
        }
    }

    /// Every window the window server has for the app, on any Space.
    private static func serverWindows(of pid: pid_t) -> [QuitOnClose.ServerWindow] {
        let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { info in
            guard (info[kCGWindowOwnerPID as String] as? Int).map(pid_t.init) == pid,
                  let bounds = info[kCGWindowBounds as String] as? [String: Double]
            else { return nil }
            return QuitOnClose.ServerWindow(
                layer: info[kCGWindowLayer as String] as? Int ?? -1,
                width: bounds["Width"] ?? 0,
                height: bounds["Height"] ?? 0,
                alpha: info[kCGWindowAlpha as String] as? Double ?? 0
            )
        }
    }
}

/// Accessibility notifications for one app: new windows get a "destroyed"
/// watch, and a destroyed window calls `onWindowClosed`.
@MainActor
private final class WindowWatcher {
    private let app: AXUIElement
    private let observer: AXObserver
    private let onWindowClosed: () -> Void

    init?(pid: pid_t, onWindowClosed: @escaping () -> Void) {
        var observer: AXObserver?
        guard AXObserverCreate(pid, windowWatcherCallback, &observer) == .success, let observer else { return nil }
        self.app = AX.application(pid)
        self.observer = observer
        self.onWindowClosed = onWindowClosed

        guard add(kAXWindowCreatedNotification, to: app) else { return nil }
        AX.elements(app, kAXWindowsAttribute)?.forEach { add(kAXUIElementDestroyedNotification, to: $0) }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    func invalidate() {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    @discardableResult
    private func add(_ notification: String, to element: AXUIElement) -> Bool {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let result = AXObserverAddNotification(observer, element, notification as CFString, refcon)
        return result == .success || result == .notificationAlreadyRegistered
    }

    fileprivate func received(_ notification: String, element: AXUIElement) {
        if notification == kAXWindowCreatedNotification {
            add(kAXUIElementDestroyedNotification, to: element)
        } else if notification == kAXUIElementDestroyedNotification {
            onWindowClosed()
        }
    }
}

private func windowWatcherCallback(
    observer: AXObserver,
    element: AXUIElement,
    notification: CFString,
    refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let watcher = Unmanaged<WindowWatcher>.fromOpaque(refcon).takeUnretainedValue()
    let name = notification as String
    // AX observers deliver on the run loop they were added to: the main one.
    nonisolated(unsafe) let element = element
    MainActor.assumeIsolated { watcher.received(name, element: element) }
}
