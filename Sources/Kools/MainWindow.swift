import AppKit
import KoolsCore
import RepoRadarCore
import SwiftUI

/// The Kools settings window: General (tab priority) first, then one tab
/// per feature in the same priority order.
struct MainWindow: View {
    let model: AppModel
    @AppStorage("window.tab") private var selection = "general"

    var body: some View {
        TabView(selection: $selection) {
            GeneralTab(preferences: model.preferences)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag("general")
            ForEach(model.preferences.tabLayout.order) { tab in
                page(for: tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab.rawValue)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 500)
    }

    @ViewBuilder
    private func page(for tab: PanelTab) -> some View {
        switch tab {
        case .repoRadar: RepoRadarTab(radar: model.radar, preferences: model.preferences)
        case .tools: ToolsTab(model: model)
        }
    }
}

// MARK: General

private struct GeneralTab: View {
    @Bindable var preferences: Preferences

    var body: some View {
        Form {
            PrioritySection(
                title: "Tabs",
                footer: "Each main feature has its own tab; small features share Tools. Tabs appear in this order in the menu bar panel and here. The panel reopens on the tab you used last.",
                layout: $preferences.tabLayout
            )
            PrioritySection(
                title: "Tools",
                footer: "The order of the cards inside the Tools tab. Hidden tools keep working; they just leave the panel.",
                layout: $preferences.toolLayout
            )

            Section("Menu Bar") {
                LabeledContent("Icon") {
                    HStack(spacing: 10) {
                        Text(MenuBarIcon.emoji)
                        Text("when nothing needs you").foregroundStyle(.secondary)
                    }
                }
                ForEach(StatusBadge.allCases.reversed(), id: \.self) { badge in
                    LabeledContent {
                        Text(badge.summary).foregroundStyle(.secondary)
                    } label: {
                        Image(nsImage: MenuBarIcon.image(for: badge))
                    }
                }
            }
        }
    }
}

/// A reorderable, hideable list: drag rows or use the arrows.
private struct PrioritySection<Item: PriorityItem>: View {
    let title: String
    let footer: String
    @Binding var layout: PriorityOrder<Item>

    var body: some View {
        Section {
            List {
                ForEach(Array(layout.order.enumerated()), id: \.element) { index, item in
                    PriorityRow(
                        rank: index + 1,
                        title: item.title,
                        symbol: item.symbol,
                        isShown: Binding(
                            get: { !layout.hidden.contains(item) },
                            set: { layout.setHidden(item, !$0) }
                        ),
                        canHide: layout.visible != [item],
                        moveUp: index > 0 ? { move(index, by: -1) } : nil,
                        moveDown: index < layout.order.count - 1 ? { move(index, by: 1) } : nil
                    )
                }
                .onMove { layout.move(fromOffsets: $0, toOffset: $1) }
            }
            .frame(height: CGFloat(Item.allCases.count) * 40)
            .scrollDisabled(true)
        } header: {
            Text(title)
        } footer: {
            HStack(alignment: .top) {
                Text(footer)
                Spacer()
                Button("Reset") { layout = .default }
                    .disabled(layout == .default)
            }
        }
    }

    private func move(_ index: Int, by offset: Int) {
        layout.move(fromOffsets: [index], toOffset: offset < 0 ? index - 1 : index + 2)
    }
}

private struct PriorityRow: View {
    let rank: Int
    let title: String
    let symbol: String
    @Binding var isShown: Bool
    let canHide: Bool
    let moveUp: (() -> Void)?
    let moveDown: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
            Text("\(rank)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Image(systemName: symbol)
                .frame(width: 20)
                .foregroundStyle(isShown ? Color.accentColor : .secondary)
            Text(title)
                .foregroundStyle(isShown ? .primary : .secondary)
            Spacer()
            Button("Move Up", systemImage: "chevron.up") { moveUp?() }
                .disabled(moveUp == nil)
            Button("Move Down", systemImage: "chevron.down") { moveDown?() }
                .disabled(moveDown == nil)
            Toggle("Show in panel", isOn: $isShown)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .disabled(isShown && !canHide)
                .help(isShown && !canHide ? "At least one stays in the panel" : "Show in the menu bar panel")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .frame(height: 28)
    }
}

// MARK: Repo Radar

private struct RepoRadarTab: View {
    let radar: RadarModel
    @Bindable var preferences: Preferences

    var body: some View {
        Form {
            Section {
                LabeledContent("Repositories", value: "\(radar.allReports.count)")
                LabeledContent("Need attention", value: "\(needingAttention.count)")
                LabeledContent("Last scan") {
                    Text(radar.lastScan?.formatted(.relative(presentation: .named)) ?? "Scanning…")
                }
                if let notice = radar.notice {
                    Text(notice).foregroundStyle(.secondary)
                }
                HStack {
                    Button(radar.isScanning ? "Scanning…" : "Refresh Now") {
                        Task { await radar.refresh() }
                    }
                    .disabled(radar.isScanning)
                    Button(radar.fetching.isEmpty ? "Fetch All" : "Fetching…") { radar.fetchAll() }
                        .disabled(radar.fetchableReports.isEmpty || !radar.fetching.isEmpty)
                }
            } footer: {
                Text("Every repo, with its actions, is in the Repo Radar tab of the menu bar panel. ↑↓ counts are as of the last fetch.")
            }

            Section {
                Toggle("Get commit messages from T3 Code automatically", isOn: $preferences.autoCommitMessages)
            } header: {
                Text("Git actions")
            } footer: {
                Text("Opening a repo with changes asks T3 Code, in the background, for a commit message, so you don't have to write one. That starts one T3 thread per set of changes, and the commit reuses it. Turned off, the ✨ button asks on demand.")
            }

            Section("Needs attention") {
                if needingAttention.isEmpty {
                    Text("Nothing needs attention.").foregroundStyle(.secondary)
                }
                ForEach(needingAttention) { report in
                    VStack(alignment: .leading, spacing: 2) {
                        Label {
                            Text(report.displayName)
                        } icon: {
                            Image(systemName: report.severity.symbol).foregroundStyle(report.severity.color)
                        }
                        ForEach(report.findings, id: \.self) { finding in
                            Text(finding.message).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Scanned folders") {
                LabeledContent("Projects", value: "~/Projects")
                LabeledContent("T3 worktrees", value: "~/.t3/worktrees")
                LabeledContent("In iCloud", value: "Desktop, Documents, iCloud Drive")
            }
        }
    }

    private var needingAttention: [RepoReport] {
        radar.allReports.filter { $0.severity >= .attention }
    }
}

// MARK: Tools

/// Every tool's settings on one page, in the Tools priority order.
private struct ToolsTab: View {
    let model: AppModel

    var body: some View {
        Form {
            ForEach(model.preferences.toolLayout.order) { tool in
                switch tool {
                case .shelf: ShelfSection(preferences: model.preferences, shelf: model.shelf)
                case .quitOnClose: QuitOnCloseSection(preferences: model.preferences, access: model.access)
                case .cutPaste: CutPasteSection(preferences: model.preferences, access: model.access)
                }
            }
        }
    }
}

private struct ShelfSection: View {
    @Bindable var preferences: Preferences
    let shelf: ShelfService

    var body: some View {
        Section {
            Toggle("Open the shelf when I shake the pointer while dragging", isOn: $preferences.shelfEnabled)
            LabeledContent("On the shelf", value: "\(shelf.shelf.items.count) item\(shelf.shelf.items.count == 1 ? "" : "s")")
            HStack {
                Button(shelf.isVisible ? "Hide Floating Shelf" : "Open Floating Shelf") { shelf.toggle() }
                Button("Clear Shelf") { shelf.clear() }
                    .disabled(shelf.shelf.isEmpty)
            }
        } header: {
            Label(ToolItem.shelf.title, systemImage: ToolItem.shelf.symbol)
        } footer: {
            Text("Drag files, links or text, give the pointer a quick side-to-side shake, and drop them on the shelf. Files stay where they are; the shelf only points to them. Items are kept until you quit Kools.")
        }
    }
}

private struct QuitOnCloseSection: View {
    @Bindable var preferences: Preferences
    let access: AccessibilityAccess

    var body: some View {
        Section {
            Toggle("Quit these apps when their last window closes", isOn: $preferences.quitOnCloseEnabled)
                .onChange(of: preferences.quitOnCloseEnabled) { _, on in
                    if on, !access.isTrusted { access.request() }
                }
            if preferences.quitOnCloseEnabled {
                PermissionRow(access: access)
            }
            QuitAppsEditor(preferences: preferences)
        } header: {
            Label(ToolItem.quitOnClose.title, systemImage: ToolItem.quitOnClose.symbol)
        } footer: {
            Text("Apps quit the normal way, so unsaved documents still ask first. A window that's minimized or on another Space keeps its app open.")
        }
    }
}

private struct CutPasteSection: View {
    @Bindable var preferences: Preferences
    let access: AccessibilityAccess

    var body: some View {
        Section {
            Toggle("Cut and paste files in Finder with ⌘X and ⌘V", isOn: $preferences.cutPasteEnabled)
                .onChange(of: preferences.cutPasteEnabled) { _, on in
                    if on, !access.isTrusted { access.request() }
                }
            if preferences.cutPasteEnabled {
                PermissionRow(access: access)
            }
            LabeledContent("⌘X", value: "Marks the selected files to move")
            LabeledContent("⌘V", value: "Moves them into the folder you're in")
        } header: {
            Label(ToolItem.cutPaste.title, systemImage: ToolItem.cutPaste.symbol)
        } footer: {
            Text("Finder does the move itself, so name conflicts are handled the usual way and ⌘Z undoes it. Copying anything else after ⌘X cancels the cut. Renaming a file and typing in the search field are left alone.")
        }
    }
}
