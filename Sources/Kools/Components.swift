import AppKit
import KoolsCore
import RepoRadarCore
import SwiftUI
import UniformTypeIdentifiers

/// Spacing and shape tokens shared by the panel and the settings window.
///
/// Radii are concentric: each is the next one out minus the padding between
/// them, so nested shapes keep an even gap around the curve. The panel
/// window sits outside all of these.
enum Metrics {
    static let panelWidth: CGFloat = 340
    static let contentHeight: CGFloat = 380
    /// Cards and the tab bar, inset 12 from the panel edge.
    static let corner: CGFloat = 18
    /// The selected tab, inset 4 inside the tab bar.
    static let tabCorner: CGFloat = 14
    /// Rows inside a card, inset 6.
    static let rowCorner: CGFloat = 12
    /// Wells and notices inside a card's details, icon tiles, key caps.
    static let tileCorner: CGFloat = 8
    /// The menu bar panel window.
    static let panelCorner: CGFloat = 26
    /// The floating shelf window.
    static let shelfCorner: CGFloat = 24
}

extension View {
    /// Liquid Glass on macOS 26 and later; a flat tinted fill with a hairline
    /// before that.
    @ViewBuilder
    func glassSurface<S: InsettableShape>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false,
        fallback: AnyShapeStyle = AnyShapeStyle(.quaternary.opacity(0.35))
    ) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            background(fallback, in: shape)
                .overlay(shape.strokeBorder(.quaternary, lineWidth: 0.5))
        }
    }

    /// The selected tab: tinted glass behind the label that slides between
    /// tabs. The glass is applied to the label itself so the text draws on
    /// top of it.
    @ViewBuilder
    func tabSelection(_ isActive: Bool, in namespace: Namespace.ID) -> some View {
        if #available(macOS 26, *) {
            if isActive {
                glassEffect(.regular.tint(Color.accentColor.opacity(0.25)), in: .rect(cornerRadius: Metrics.tabCorner))
                    .glassEffectID("activeTab", in: namespace)
            } else {
                self
            }
        } else {
            background(isActive ? Color.accentColor.opacity(0.16) : .clear, in: .rect(cornerRadius: Metrics.tabCorner))
        }
    }

    /// Groups glass shapes so they blend and sample the same backdrop.
    @ViewBuilder
    func glassGroup(spacing: CGFloat = 8) -> some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }
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
            .background(StatusBadge.permission.color.opacity(0.12), in: .rect(cornerRadius: Metrics.tileCorner))
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
            .glassSurface(in: .rect(cornerRadius: Metrics.corner))
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

/// Gives the menu bar window a Liquid Glass backdrop on macOS 26 and later.
/// `MenuBarExtra` draws its own flat background and ignores
/// `containerBackground`, so this puts an `NSGlassEffectView` behind the
/// hosting view and clears the window's background.
struct PanelGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            guard #available(macOS 26, *), let window = view?.window,
                  let frameView = window.contentView?.superview,
                  !frameView.subviews.contains(where: { $0 is NSGlassEffectView })
            else { return }
            let glass = NSGlassEffectView(frame: frameView.bounds)
            glass.autoresizingMask = [.width, .height]
            glass.cornerRadius = Metrics.panelCorner
            window.backgroundColor = .clear
            window.isOpaque = false
            frameView.wantsLayer = true
            frameView.layer?.cornerRadius = Metrics.panelCorner
            frameView.layer?.cornerCurve = .continuous
            frameView.layer?.masksToBounds = true
            frameView.addSubview(glass, positioned: .below, relativeTo: frameView.subviews.first)
            window.invalidateShadow()
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
