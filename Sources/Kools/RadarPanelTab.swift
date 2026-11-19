import KoolsCore
import RepoRadarCore
import SwiftUI

/// Repo Radar inside the panel: repos sorted most urgent first; click a
/// repo for its findings and actions.
struct RadarPanelTab: View {
    let radar: RadarModel
    /// Fetch a commit message from T3 Code as soon as a repo with changes opens.
    var autoSuggest = true
    @State private var expanded: String?
    @State private var showWorktrees = false

    private static let worktreeSection = "T3 worktrees"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            toolbar
            if let notice = radar.notice {
                Text(notice)
                    .font(.caption)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: Metrics.rowCorner))
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if radar.sections.isEmpty {
                        Text(radar.lastScan == nil ? "Scanning…" : "No repositories found under ~/Projects")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                    ForEach(radar.sections) { section in
                        if section.name == Self.worktreeSection {
                            worktrees(section)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                sectionTitle(section)
                                Card { rows(section.reports) }
                            }
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            if let lastScan = radar.lastScan {
                Text("Scanned \(lastScan.formatted(.relative(presentation: .named))) · ↑↓ as of last fetch")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            let total = radar.allReports.count
            let needing = radar.allReports.filter { $0.severity >= .attention }.count
            Text("\(total) repos")
                .font(.callout.weight(.medium))
            if needing > 0 {
                Text("· \(needing) need attention")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            Spacer()
            Button {
                radar.fetchAll()
            } label: {
                Image(systemName: radar.fetching.isEmpty ? "arrow.down.circle" : "ellipsis.circle")
            }
            .help("Fetch all repos with an upstream")
            .disabled(radar.fetchableReports.isEmpty || !radar.fetching.isEmpty)
            Button {
                Task { await radar.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(radar.isScanning ? 180 : 0))
                    .animation(.easeInOut, value: radar.isScanning)
            }
            .help("Scan again")
            .keyboardShortcut("r")
            .disabled(radar.isScanning)
        }
        .buttonStyle(.borderless)
    }

    private func sectionTitle(_ section: RadarModel.Section) -> some View {
        Text(section.name.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 6)
    }

    private func rows(_ reports: [RepoReport]) -> some View {
        ForEach(reports) { report in
            RepoRow(report: report, radar: radar, autoSuggest: autoSuggest, isExpanded: expanded == report.id) {
                withAnimation(.snappy(duration: 0.2)) {
                    expanded = expanded == report.id ? nil : report.id
                }
            }
        }
    }

    private func worktrees(_ section: RadarModel.Section) -> some View {
        let empty = section.reports.filter(\.isEmptyWorktree)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { showWorktrees.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .rotationEffect(.degrees(showWorktrees ? 90 : 0))
                        Text("\(section.name.uppercased()) (\(section.reports.count))")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                Spacer()
                if !empty.isEmpty {
                    Button("Clean \(empty.count) Empty…") { radar.cleanWorktrees(empty) }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }
            .padding(.leading, 6)
            if showWorktrees {
                Card { rows(section.reports) }
            }
        }
    }
}

private struct RepoRow: View {
    let report: RepoReport
    let radar: RadarModel
    let autoSuggest: Bool
    let isExpanded: Bool
    let toggle: () -> Void
    @State private var isHovered = false
    @State private var commitMessage = ""
    /// The last message T3 filled in; replaced by a new one only while untouched.
    @State private var filledMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: toggle) {
                HStack(spacing: 8) {
                    Image(systemName: report.severity.symbol)
                        .foregroundStyle(report.severity.color)
                        .frame(width: 16)
                    Text(report.displayName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    ForEach(report.badges, id: \.self) { badge in
                        Text(badge)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if isExpanded {
                details
                    .padding(.leading, 24)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            (isExpanded || isHovered) ? Color.primary.opacity(0.06) : .clear,
            in: .rect(cornerRadius: Metrics.rowCorner)
        )
        .onHover { isHovered = $0 }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(report.branchLine)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(report.findings, id: \.self) { finding in
                Label(finding.message, systemImage: finding.severity.symbol)
                    .font(.caption)
                    .foregroundStyle(finding.severity == .info ? .secondary : finding.severity.color)
            }
            if !gitTasks.isEmpty {
                gitSection
            }
            HStack(spacing: 6) {
                Button("Open in T3") { radar.openInT3(report) }
                Button(radar.fetching.contains(report.id) ? "Fetching…" : "Fetch") { radar.fetch(report) }
                    .disabled(report.status?.branch.upstream == nil || radar.fetching.contains(report.id))
                Button("Reveal") { radar.reveal(report) }
                Button("Copy Path") { radar.copyPath(report) }
            }
            .controlSize(.small)
            if report.isEmptyWorktree {
                Button("Remove Worktree…", role: .destructive) { radar.cleanWorktrees([report]) }
                    .controlSize(.small)
            }
        }
    }

    /// Git tasks that fit this repo's state, run by a T3 Code agent.
    private var gitTasks: [GitTask] {
        guard let status = report.status else { return [] }
        let branch = status.branch
        return GitTask.allCases.filter {
            $0.isAvailable(
                changes: status.counts.total,
                ahead: branch.ahead,
                behind: branch.behind,
                hasUpstream: branch.upstream != nil,
                isDetached: branch.isDetached
            )
        }
    }

    private var suggestion: RadarModel.CommitSuggestion.State? {
        radar.suggestions[report.id]?.state
    }

    private var gitSection: some View {
        let starting = radar.startingGitTask.contains(report.id)
        let commits = gitTasks.contains(.commit)
        let writing = suggestion == .writing
        return VStack(alignment: .leading, spacing: 6) {
            if commits {
                HStack(alignment: .top, spacing: 6) {
                    TextField(
                        writing ? "T3 Code is writing a message…" : "Commit message",
                        text: $commitMessage,
                        axis: .vertical
                    )
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    Button {
                        radar.suggestCommitMessage(for: report, again: true)
                    } label: {
                        if writing {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "sparkles")
                        }
                    }
                    .buttonStyle(.borderless)
                    .frame(width: 18, height: 20)
                    .disabled(writing)
                    .help(commitMessage.isEmpty ? "Ask T3 Code for a commit message" : "Ask T3 Code for a new message")
                }
                if case .failed(let reason) = suggestion {
                    Text("Couldn't get a message from T3 Code: \(reason). The agent will write one when you commit.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 6) {
                ForEach(gitTasks, id: \.self) { task in
                    Button {
                        radar.runGitTask(task, for: report, message: commits ? commitMessage : nil)
                        commitMessage = ""
                        filledMessage = ""
                    } label: {
                        Label(task.title, systemImage: task.symbol)
                    }
                    .help(help(for: task))
                }
                if starting { ProgressView().controlSize(.mini) }
            }
            .controlSize(.small)
            .disabled(starting)
            Text(caption(commits: commits, writing: writing))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(Color.accentColor.opacity(0.07), in: .rect(cornerRadius: Metrics.tileCorner))
        .onAppear {
            if commits, autoSuggest { radar.suggestCommitMessage(for: report) }
            fill(from: suggestion)
        }
        .onChange(of: suggestion) { _, new in fill(from: new) }
    }

    /// Puts T3's message in the field unless you've typed your own.
    private func fill(from state: RadarModel.CommitSuggestion.State?) {
        guard case .ready(let message) = state, commitMessage == filledMessage else { return }
        commitMessage = message
        filledMessage = message
    }

    private func caption(commits: Bool, writing: Bool) -> String {
        guard commits else { return "Runs in a T3 Code thread you can follow and answer." }
        if writing { return "You can commit now; the agent will finish the message itself." }
        if commitMessage.isEmpty { return "The agent writes the message from the diff when you commit." }
        return commitMessage == filledMessage
            ? "Message from T3 Code. Edit it if you like; the commit runs in the same thread."
            : "Your message is used as written; the commit runs in a T3 Code thread."
    }

    private func help(for task: GitTask) -> String {
        switch task {
        case .commit: "A T3 agent reviews the diff and commits. Nothing is pushed."
        case .commitAndPush: "A T3 agent reviews the diff, commits, then pushes."
        case .push: "A T3 agent pushes this branch. Never force pushes."
        case .pull: "A T3 agent fast-forwards this branch, and stops to ask if it can't."
        }
    }
}
