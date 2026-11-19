import AppKit
import KoolsCore
import RepoRadarCore
import SwiftUI
import UniformTypeIdentifiers

/// Spacing and shape tokens shared by the panel and the settings window.
enum Metrics {
    static let panelWidth: CGFloat = 340
    static let contentHeight: CGFloat = 380
    static let corner: CGFloat = 10
    static let rowCorner: CGFloat = 7
}

/// Accessibility status, with a button to grant it when missing.
struct PermissionRow: View {
    let access: AccessibilityAccess

    var body: some View {
        if access.isTrusted {
            Label("Accessibility access granted", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else {
            HStack(spacing: 8) {
                Image(systemName: StatusBadge.permission.symbol)
                    .foregroundStyle(StatusBadge.permission.color)
                Text("Needs Accessibility access to work")
                    .font(.caption)
                Spacer(minLength: 4)
                Button("Grant Access…") { access.request() }
                    .controlSize(.small)
            }
            .padding(8)
            .background(StatusBadge.permission.color.opacity(0.1), in: .rect(cornerRadius: Metrics.rowCorner))
        }
    }
}

/// A rounded group of rows, like a grouped form section.
struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: Metrics.corner))
            .overlay(RoundedRectangle(cornerRadius: Metrics.corner).strokeBorder(.quaternary, lineWidth: 0.5))
    }
}

/// An app picked for Quit on Close.
struct AppRow: View {
    let bundleID: String
    var remove: (() -> Void)?
    @State private var isHovered = false

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack(spacing: 8) {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "app.dashed").frame(width: 20, height: 20)
            }
            Text(url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let remove {
                Button("Remove", systemImage: "minus.circle.fill", action: remove)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .opacity(isHovered ? 1 : 0)
                    .help("Stop quitting this app")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(isHovered ? Color.primary.opacity(0.06) : .clear, in: .rect(cornerRadius: Metrics.rowCorner))
        .onHover { isHovered = $0 }
    }
}

/// The Quit on Close app list with Add and Remove.
struct QuitAppsEditor: View {
    @Bindable var preferences: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if preferences.quitOnCloseApps.isEmpty {
                Text("No apps yet. Add the ones you want to quit when their last window closes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
            ForEach(preferences.quitOnCloseApps, id: \.self) { id in
                AppRow(bundleID: id) { preferences.quitOnCloseApps.removeAll { $0 == id } }
            }
            HStack {
                Menu("Add Running App") {
                    ForEach(runningCandidates, id: \.processIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "?") { add(app.bundleIdentifier) }
                    }
                }
                .fixedSize()
                .disabled(runningCandidates.isEmpty)
                Button("Choose…", action: chooseApp)
            }
            .controlSize(.small)
        }
    }

    /// Regular apps running now that aren't chosen yet and are allowed.
    private var runningCandidates: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { app in
                guard app.activationPolicy == .regular, let id = app.bundleIdentifier else { return false }
                return isAllowed(id) && !preferences.quitOnCloseApps.contains(id)
            }
            .sorted { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
    }

    private func isAllowed(_ id: String) -> Bool {
        id != Bundle.main.bundleIdentifier && !QuitOnClose.alwaysExempt.contains(id)
    }

    private func add(_ bundleID: String?) {
        guard let bundleID, isAllowed(bundleID), !preferences.quitOnCloseApps.contains(bundleID) else { return }
        preferences.quitOnCloseApps.append(bundleID)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach { add(Bundle(url: $0)?.bundleIdentifier) }
    }
}

// MARK: Repo formatting

extension Severity {
    var symbol: String {
        switch self {
        case .clean: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        case .attention: "arrow.triangle.branch"
        case .warning: "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .clean: .green
        case .info: .blue
        case .attention: .orange
        case .warning: .red
        }
    }
}

extension RepoReport {
    /// e.g. ["●1", "↑2", "↓3"]
    var badges: [String] {
        guard let status else { return [] }
        var badges: [String] = []
        if status.counts.total > 0 { badges.append("●\(status.counts.total)") }
        if let ahead = status.branch.ahead, ahead > 0 { badges.append("↑\(ahead)") }
        if let behind = status.branch.behind, behind > 0 { badges.append("↓\(behind)") }
        return badges
    }

    /// e.g. "main → origin/main · last commit 2 hours ago"
    var branchLine: String {
        var parts: [String] = []
        if let branch = status?.branch {
            if branch.isDetached {
                parts.append("detached HEAD")
            } else if let head = branch.head {
                parts.append(branch.upstream.map { "\(head) → \($0)" } ?? head)
            }
        }
        switch kind {
        case .submodule: parts.append("submodule")
        case .worktree: parts.append("worktree")
        case .repository: break
        }
        if let lastCommit {
            parts.append("last commit \(lastCommit.formatted(.relative(presentation: .named)))")
        }
        return parts.isEmpty ? path.path : parts.joined(separator: " · ")
    }
}
