import AppKit
import Foundation
import KoolsCore
import Observation
import os
import RepoRadarCore

@MainActor
@Observable
final class RadarModel {
    struct Section: Identifiable {
        let name: String
        let reports: [RepoReport]
        var id: String { name }
    }

    private(set) var sections: [Section] = []
    private(set) var isScanning = false
    private(set) var lastScan: Date?
    /// Result of the last action, shown at the top of the menu.
    private(set) var notice: String?
    /// Repos with a fetch in flight.
    private(set) var fetching: Set<String> = []
    /// Repos whose T3 git thread is being started.
    private(set) var startingGitTask: Set<String> = []
    /// Commit messages written by T3 Code, by repo id.
    private(set) var suggestions: [String: CommitSuggestion] = [:]

    struct CommitSuggestion {
        enum State: Equatable {
            case writing
            case ready(String)
            case failed(String)
        }

        /// The repo state the message was written for; a new state gets a new message.
        let key: String
        /// The T3 thread that wrote it. The commit request goes to the same thread.
        var threadID: String?
        var state: State
    }

    private static let log = Logger(subsystem: "local.kools", category: "scan")
    private let scanner = RepoScanner.standard()
    private let interval: Duration = .seconds(300)
    private static let sectionOrder = [RepoScanner.iCloudSection, "Projects", "T3 worktrees"]

    init() {
        Task { [weak self] in
            while let self {
                await self.refresh()
                try? await Task.sleep(for: self.interval)
            }
        }
    }

    var allReports: [RepoReport] { sections.flatMap(\.reports) }

    var worstSeverity: Severity {
        allReports.map(\.severity).max() ?? .clean
    }

    /// Repos with an upstream: the only ones a fetch can update.
    var fetchableReports: [RepoReport] {
        allReports.filter { $0.status?.branch.upstream != nil }
    }

    func refreshIfStale() {
        guard let lastScan, Date().timeIntervalSince(lastScan) < 30 else {
            Task { await refresh() }
            return
        }
    }

    func refresh() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        let started = Date()
        let reports = await scanner.scan()
        Self.log.notice("Scan found \(reports.count) repos in \(Date().timeIntervalSince(started), format: .fixed(precision: 2))s")
        let grouped = Dictionary(grouping: reports, by: \.section)
        sections = Self.sectionOrder.compactMap { name in
            guard let items = grouped[name], !items.isEmpty else { return nil }
            let sorted = items.sorted {
                $0.severity != $1.severity
                    ? $0.severity > $1.severity
                    : $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
            return Section(name: name, reports: sorted)
        }
        lastScan = Date()
    }

    // MARK: Actions

    func openInT3(_ report: RepoReport) {
        Task {
            let root = await Task.detached {
                RepoActions.t3WorkspaceRoot(for: report.path, kind: report.kind)
            }.value
            do {
                try await T3Launcher.open(root)
                notice = nil
            } catch {
                notice = "Couldn't open \(root.lastPathComponent) in T3 Code: \(error)"
                Self.log.error("T3 open failed for \(root.path, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Asks T3 Code, in the background, for a commit message for the repo's
    /// current changes. Runs once per repo state unless `again` is set, so
    /// reopening a repo never starts a second thread for the same changes.
    func suggestCommitMessage(for report: RepoReport, again: Bool = false) {
        let key = Self.suggestionKey(for: report)
        let existing = suggestions[report.id]
        if existing?.state == .writing { return }
        if !again, existing?.key == key { return }

        suggestions[report.id] = CommitSuggestion(key: key, threadID: existing?.threadID, state: .writing)
        Task {
            do {
                let prompt = GitTask.suggestMessagePrompt(repo: report.path, branch: report.status?.branch.head)
                let thread: String
                var itemsBefore: Int?
                if let reused = existing?.threadID {
                    thread = reused
                    itemsBefore = try await T3Launcher.itemCount(of: reused)
                    try await T3Launcher.send(to: reused, message: prompt)
                } else {
                    let root = await Self.workspaceRoot(for: report)
                    thread = try await T3Launcher.startThread(
                        in: root,
                        title: "Commit message: \(report.displayName)",
                        message: prompt,
                        inBackground: true
                    )
                    suggestions[report.id]?.threadID = thread
                }
                let reply = try await T3Launcher.waitForReply(in: thread, afterItemCount: itemsBefore)
                guard let message = CommitMessage.extract(from: reply) else {
                    throw T3Launcher.LaunchError(description: "T3 Code replied without a commit message")
                }
                if suggestions[report.id]?.key == key { suggestions[report.id]?.state = .ready(message) }
            } catch {
                suggestions[report.id]?.state = .failed(String(describing: error))
                Self.log.error("Commit message failed for \(report.path.path, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Hands a commit, push or pull to a T3 Code agent. A commit goes to the
    /// thread that wrote its message when there is one; otherwise a new
    /// thread starts. T3 Code comes to the front so you can follow it.
    func runGitTask(_ task: GitTask, for report: RepoReport, message: String? = nil) {
        guard !startingGitTask.contains(report.id) else { return }
        startingGitTask.insert(report.id)
        let prompt = task.prompt(repo: report.path, branch: report.status?.branch.head, message: message)
        let reusable = (task == .commit || task == .commitAndPush) ? suggestions[report.id]?.threadID : nil
        Task {
            defer { startingGitTask.remove(report.id) }
            let root = await Self.workspaceRoot(for: report)
            do {
                if let reusable {
                    try await T3Launcher.open(root)
                    try await T3Launcher.send(to: reusable, message: prompt)
                } else {
                    try await T3Launcher.startThread(in: root, title: task.threadTitle(repoName: report.displayName), message: prompt)
                }
                suggestions[report.id] = nil
                notice = "\(task.title) for \(report.displayName) started in T3 Code"
            } catch {
                notice = "Couldn't start \(task.title) in T3 Code: \(error)"
                Self.log.error("T3 thread failed for \(report.path.path, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
    }

    private static func workspaceRoot(for report: RepoReport) async -> URL {
        await Task.detached { RepoActions.t3WorkspaceRoot(for: report.path, kind: report.kind) }.value
    }

    /// Changes to this mean the diff changed enough to need a new message.
    private static func suggestionKey(for report: RepoReport) -> String {
        let status = report.status
        return [
            "\(status?.counts.changed ?? 0)/\(status?.counts.untracked ?? 0)/\(status?.counts.conflicted ?? 0)",
            status?.branch.head ?? "",
            report.lastCommit.map { "\($0.timeIntervalSince1970)" } ?? "",
        ].joined(separator: "|")
    }

    func fetch(_ report: RepoReport) {
        Task {
            let failures = await fetch([report])
            notice = failures.isEmpty ? "Fetched \(report.displayName)" : failures[0]
            await refresh()
        }
    }

    func fetchAll() {
        let targets = fetchableReports
        guard !targets.isEmpty else { return }
        Task {
            let failures = await fetch(targets)
            notice = failures.isEmpty
                ? "Fetched \(targets.count) repos"
                : "Fetched \(targets.count - failures.count) of \(targets.count). \(failures[0])"
            await refresh()
        }
    }

    /// Runs fetches four at a time off the main actor; returns one message per failure.
    private func fetch(_ reports: [RepoReport]) async -> [String] {
        let pending = reports.filter { !fetching.contains($0.id) }
        fetching.formUnion(pending.map(\.id))
        defer { fetching.subtract(pending.map(\.id)) }

        return await withTaskGroup(of: String?.self) { group in
            var iterator = pending.makeIterator()
            func next() -> RepoReport? { iterator.next() }
            for _ in 0..<4 {
                guard let report = next() else { break }
                group.addTask { Self.fetchOne(report) }
            }
            var failures: [String] = []
            for await failure in group {
                if let failure { failures.append(failure) }
                if let report = next() { group.addTask { Self.fetchOne(report) } }
            }
            return failures
        }
    }

    nonisolated private static func fetchOne(_ report: RepoReport) -> String? {
        do {
            try RepoActions.fetch(report.path)
            return nil
        } catch {
            return "Fetch failed for \(report.displayName): \(error)"
        }
    }

    var emptyWorktrees: [RepoReport] { allReports.filter(\.isEmptyWorktree) }

    /// Asks first, listing the worktrees and any ignored files that go with them.
    func cleanWorktrees(_ reports: [RepoReport]) {
        guard !reports.isEmpty else { return }
        Task {
            let ignored = await Task.detached {
                reports.flatMap { report in
                    RepoActions.ignoredEntries(in: report.path).map { "\(report.path.lastPathComponent)/\($0)" }
                }
            }.value
            guard Self.confirmRemoval(of: reports, ignored: ignored) else { return }

            let failures = await Task.detached {
                reports.compactMap { report -> String? in
                    do {
                        try RepoActions.removeEmptyWorktree(report.path)
                        return nil
                    } catch {
                        return "\(report.displayName): \(error)"
                    }
                }
            }.value
            let removed = reports.count - failures.count
            notice = failures.isEmpty
                ? "Removed \(removed) empty worktree\(removed == 1 ? "" : "s")"
                : "Removed \(removed) of \(reports.count). \(failures[0])"
            await refresh()
        }
    }

    private static func confirmRemoval(of reports: [RepoReport], ignored: [String]) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = reports.count == 1
            ? "Remove worktree \(reports[0].displayName)?"
            : "Remove \(reports.count) empty worktrees?"
        var lines = reports.map { "• \($0.path.path)" + ($0.status?.branch.head.map { " (\($0))" } ?? "") }
        lines.append("")
        lines.append("They have no changes and every commit is already on the remote. Branches are kept. T3 threads using these worktrees will lose their checkout.")
        if !ignored.isEmpty {
            let shown = ignored.prefix(8).joined(separator: ", ")
            lines.append("")
            lines.append("Ignored files are deleted too: \(shown)\(ignored.count > 8 ? ", and \(ignored.count - 8) more" : "")")
        }
        alert.informativeText = lines.joined(separator: "\n")
        let remove = alert.addButton(withTitle: "Remove")
        remove.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    func reveal(_ report: RepoReport) {
        NSWorkspace.shared.activateFileViewerSelecting([report.path])
    }

    func copyPath(_ report: RepoReport) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report.path.path, forType: .string)
    }
}
