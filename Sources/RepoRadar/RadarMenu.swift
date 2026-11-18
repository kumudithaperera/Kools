import RepoRadarCore
import SwiftUI

/// Content of a native `.menu` MenuBarExtra: a real system menu, so macOS draws it
/// with the standard menu material (Liquid Glass on macOS 26 and later).
struct RadarMenu: View {
    let model: RadarModel

    var body: some View {
        Group {
            if let notice = model.notice {
                Text(notice)
                Divider()
            }

            if model.sections.isEmpty {
                Text(model.lastScan == nil ? "Scanning…" : "No repositories found under ~/Projects")
            }

            ForEach(model.sections) { section in
                if section.name == "T3 worktrees" {
                    // Collapsed by default: a submenu instead of inline rows.
                    Menu {
                        let empty = section.reports.filter(\.isEmptyWorktree)
                        Button {
                            model.cleanWorktrees(empty)
                        } label: {
                            Label("Clean Empty Worktrees (\(empty.count))…", systemImage: "trash")
                        }
                        .disabled(empty.isEmpty)
                        Divider()
                        ForEach(section.reports) { RepoMenu(report: $0, model: model) }
                    } label: {
                        Label(sectionTitle(section), systemImage: "square.stack.3d.up")
                    }
                } else {
                    Section(sectionTitle(section)) {
                        ForEach(section.reports) { RepoMenu(report: $0, model: model) }
                    }
                }
            }

            Divider()

            Button {
                model.fetchAll()
            } label: {
                Label(model.fetching.isEmpty ? "Fetch All" : "Fetching…", systemImage: "arrow.down.circle")
            }
            .disabled(model.fetchableReports.isEmpty || !model.fetching.isEmpty)

            Button {
                Task { await model.refresh() }
            } label: {
                Label(model.isScanning ? "Scanning…" : "Refresh Now", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r")
            .disabled(model.isScanning)

            if let lastScan = model.lastScan {
                Text("Scanned \(lastScan.formatted(.relative(presentation: .named))) · ↑↓ as of last fetch")
            }

            Divider()

            Button("Quit Repo Radar") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .onAppear { model.refreshIfStale() }
    }

    private func sectionTitle(_ section: RadarModel.Section) -> String {
        let needing = section.reports.filter { $0.severity >= .attention }.count
        return needing == 0
            ? "\(section.name) (\(section.reports.count))"
            : "\(section.name) (\(section.reports.count), \(needing) need attention)"
    }
}

/// One repo: a submenu with its details, then its actions.
private struct RepoMenu: View {
    let report: RepoReport
    let model: RadarModel

    var body: some View {
        Menu {
            Text(branchLine)
            ForEach(report.findings, id: \.self) { finding in
                Label(finding.message, systemImage: finding.severity.symbol)
            }

            Divider()

            Button {
                model.openInT3(report)
            } label: {
                Label("Open in T3 Code", systemImage: "bubble.left.and.text.bubble.right")
            }

            Button {
                model.fetch(report)
            } label: {
                Label(model.fetching.contains(report.id) ? "Fetching…" : "Fetch", systemImage: "arrow.down.circle")
            }
            .disabled(report.status?.branch.upstream == nil || model.fetching.contains(report.id))

            if report.isEmptyWorktree {
                Button {
                    model.cleanWorktrees([report])
                } label: {
                    Label("Remove Worktree…", systemImage: "trash")
                }
            }

            Divider()

            Button {
                model.reveal(report)
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
            Button {
                model.copyPath(report)
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }
        } label: {
            Label(title, systemImage: report.severity.symbol)
        }
    }

    /// e.g. "Morsel/app   ●1 ↑2 ↓3"
    private var title: String {
        var badges: [String] = []
        if let status = report.status {
            if status.counts.total > 0 { badges.append("●\(status.counts.total)") }
            if let ahead = status.branch.ahead, ahead > 0 { badges.append("↑\(ahead)") }
            if let behind = status.branch.behind, behind > 0 { badges.append("↓\(behind)") }
        }
        return badges.isEmpty ? report.displayName : "\(report.displayName)   \(badges.joined(separator: " "))"
    }

    private var branchLine: String {
        var parts: [String] = []
        if let branch = report.status?.branch {
            if branch.isDetached {
                parts.append("detached HEAD")
            } else if let head = branch.head {
                parts.append(branch.upstream.map { "\(head) → \($0)" } ?? head)
            }
        }
        switch report.kind {
        case .submodule: parts.append("submodule")
        case .worktree: parts.append("worktree")
        case .repository: break
        }
        if let lastCommit = report.lastCommit {
            parts.append("last commit \(lastCommit.formatted(.relative(presentation: .named)))")
        }
        return parts.isEmpty ? report.path.path : parts.joined(separator: " · ")
    }
}

extension Severity {
    var symbol: String {
        switch self {
        case .clean: "checkmark.circle"
        case .info: "info.circle"
        case .attention: "arrow.triangle.branch"
        case .warning: "exclamationmark.triangle"
        }
    }
}
