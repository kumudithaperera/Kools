import AppKit
import KoolsCore
import SwiftUI

/// The menu bar panel: header, a tab bar in the user's priority order, the
/// selected feature, and a footer.
struct KoolsPanel: View {
    let model: AppModel
    @AppStorage("panel.lastTab") private var lastTab: String = ""
    @Environment(\.openWindow) private var openWindow

    private var layout: TabLayout { model.preferences.tabLayout }
    private var activeTab: PanelTab { layout.opening(lastUsed: lastTab) }

    var body: some View {
        VStack(spacing: 10) {
            header
            tabBar
            content
                .frame(height: Metrics.contentHeight, alignment: .top)
            Divider()
            footer
        }
        .padding(12)
        .frame(width: Metrics.panelWidth)
        .onAppear {
            model.radar.refreshIfStale()
            model.cutPaste.refreshPending()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(MenuBarIcon.emoji).font(.system(size: 20))
            Text("Kools").font(.title3.weight(.semibold))
            Spacer()
            if let badge = model.statusBadge {
                Label(badge.summary, systemImage: badge.symbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(badge.color.gradient, in: .capsule)
            } else {
                Label("All good", systemImage: "checkmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(layout.visible) { tab in
                let isActive = tab == activeTab
                Button {
                    lastTab = tab.rawValue
                } label: {
                    // Icon and name: with few tabs there's room, and names read faster.
                    HStack(spacing: 6) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .overlay(alignment: .topTrailing) {
                                if let badge = model.badge(for: tab) {
                                    Circle()
                                        .fill(badge.color)
                                        .frame(width: 7, height: 7)
                                        .offset(x: 4, y: -3)
                                }
                            }
                        Text(tab.title)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .contentShape(.rect(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isActive ? Color.accentColor.opacity(0.16) : .clear)
                )
                .help(tab.title)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(isActive ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary, lineWidth: 0.5))
    }

    @ViewBuilder
    private var content: some View {
        switch activeTab {
        case .repoRadar: RadarPanelTab(radar: model.radar, autoSuggest: model.preferences.autoCommitMessages)
        case .tools: ToolsPanelTab(model: model)
        }
    }

    private var footer: some View {
        HStack {
            Button {
                openWindow(id: KoolsApp.mainWindowID)
                NSApp.activate()
            } label: {
                Label("Settings…", systemImage: "gearshape")
            }
            .keyboardShortcut(",")
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit Kools", systemImage: "power")
            }
            .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}

// MARK: Tools

/// The small features, one card each, in the user's priority order. One
/// card is open at a time; every card's switch works while it's closed.
private struct ToolsPanelTab: View {
    let model: AppModel
    @AppStorage("panel.openTool") private var openTool = ""

    private var current: ToolItem? {
        openTool == "none" ? nil : model.preferences.toolLayout.opening(lastUsed: openTool)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(model.preferences.toolLayout.visible) { tool in
                    ToolCard(
                        tool: tool,
                        caption: caption(for: tool),
                        badge: model.badge(for: tool),
                        isOn: isOn(tool),
                        isOpen: current == tool,
                        toggleOpen: {
                            withAnimation(.snappy(duration: 0.2)) {
                                openTool = current == tool ? "none" : tool.rawValue
                            }
                        }
                    ) {
                        details(for: tool)
                    }
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func caption(for tool: ToolItem) -> String {
        switch tool {
        case .shelf:
            let count = model.shelf.shelf.items.count
            return count == 0 ? "Shake while dragging to park things" : "\(count) item\(count == 1 ? "" : "s") on the shelf"
        case .quitOnClose:
            let count = model.preferences.quitOnCloseApps.count
            return count == 0 ? "Auto-quit apps with no windows left" : "Quits \(count) app\(count == 1 ? "" : "s") on last window close"
        case .cutPaste:
            let pending = model.cutPaste.pendingFileCount
            return pending > 0 ? "\(pending) item\(pending == 1 ? "" : "s") ready to move" : "Move files in Finder with ⌘X and ⌘V"
        }
    }

    private func isOn(_ tool: ToolItem) -> Binding<Bool> {
        let preferences = model.preferences
        let access = model.access
        switch tool {
        case .shelf:
            return Binding(get: { preferences.shelfEnabled }, set: { preferences.shelfEnabled = $0 })
        case .quitOnClose:
            return Binding(get: { preferences.quitOnCloseEnabled }, set: {
                preferences.quitOnCloseEnabled = $0
                if $0, !access.isTrusted { access.request() }
            })
        case .cutPaste:
            return Binding(get: { preferences.cutPasteEnabled }, set: {
                preferences.cutPasteEnabled = $0
                if $0, !access.isTrusted { access.request() }
            })
        }
    }

    @ViewBuilder
    private func details(for tool: ToolItem) -> some View {
        switch tool {
        case .shelf:
            ShelfItemsList(service: model.shelf)
                .frame(height: 130)
                .background(.background.opacity(0.5), in: .rect(cornerRadius: Metrics.rowCorner))
            HStack {
                Button(model.shelf.isVisible ? "Hide Floating Shelf" : "Open Floating Shelf") { model.shelf.toggle() }
                Spacer()
                Button("Clear", role: .destructive) { model.shelf.clear() }
                    .disabled(model.shelf.shelf.isEmpty)
            }
            .controlSize(.small)
        case .quitOnClose:
            if model.preferences.quitOnCloseEnabled {
                PermissionRow(access: model.access)
            }
            QuitAppsEditor(preferences: model.preferences)
        case .cutPaste:
            if model.preferences.cutPasteEnabled {
                PermissionRow(access: model.access)
            }
            HStack(spacing: 12) {
                shortcut("⌘X", "mark")
                shortcut("⌘V", "move here")
                shortcut("⌘Z", "undo")
            }
            Text("Copying anything else after ⌘X cancels the cut. Renaming and the search field are left alone.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func shortcut(_ keys: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Text(keys)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.background, in: .rect(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.quaternary))
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// One tool: a header with its switch, and details when open.
private struct ToolCard<Details: View>: View {
    let tool: ToolItem
    let caption: String
    let badge: StatusBadge?
    @Binding var isOn: Bool
    let isOpen: Bool
    let toggleOpen: () -> Void
    @ViewBuilder let details: Details

    init(tool: ToolItem, caption: String, badge: StatusBadge?, isOn: Binding<Bool>, isOpen: Bool,
         toggleOpen: @escaping () -> Void, @ViewBuilder details: () -> Details) {
        self.tool = tool
        self.caption = caption
        self.badge = badge
        _isOn = isOn
        self.isOpen = isOpen
        self.toggleOpen = toggleOpen
        self.details = details()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button(action: toggleOpen) {
                    HStack(spacing: 10) {
                        Image(systemName: tool.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isOn ? Color.accentColor : .secondary)
                            .frame(width: 28, height: 28)
                            .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 7))
                            .overlay(alignment: .topTrailing) {
                                if let badge {
                                    Circle().fill(badge.color).frame(width: 7, height: 7).offset(x: 2, y: -2)
                                }
                            }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tool.title).font(.callout.weight(.semibold))
                            Text(caption)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isOpen ? 90 : 0))
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                Toggle(tool.title, isOn: $isOn)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
            }
            if isOpen {
                VStack(alignment: .leading, spacing: 8) { details }
                    .transition(.opacity)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: Metrics.corner))
        .overlay(RoundedRectangle(cornerRadius: Metrics.corner).strokeBorder(.quaternary, lineWidth: 0.5))
    }
}
