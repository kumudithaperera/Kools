import Foundation

public struct ScanRoot: Sendable {
    public let section: String
    public let url: URL
    public let maxDepth: Int
    /// Keep only repos that are in iCloud (used for Desktop/Documents/iCloud Drive).
    public let onlyICloud: Bool

    public init(section: String, url: URL, maxDepth: Int, onlyICloud: Bool = false) {
        self.section = section
        self.url = url
        self.maxDepth = maxDepth
        self.onlyICloud = onlyICloud
    }
}

public struct RepoScanner: Sendable {
    public var roots: [ScanRoot]
    public var runner = GitRunner()
    public var icloud: ICloudDetector
    public var concurrency = 4

    public init(roots: [ScanRoot], icloud: ICloudDetector) {
        self.roots = roots
        self.icloud = icloud
    }

    public static let iCloudSection = "In iCloud"

    public static func standard(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> RepoScanner {
        RepoScanner(
            roots: [
                ScanRoot(section: "Projects", url: home.appendingPathComponent("Projects"), maxDepth: 6),
                ScanRoot(section: "T3 worktrees", url: home.appendingPathComponent(".t3/worktrees"), maxDepth: 2),
                ScanRoot(section: iCloudSection, url: home.appendingPathComponent("Desktop"), maxDepth: 4, onlyICloud: true),
                ScanRoot(section: iCloudSection, url: home.appendingPathComponent("Documents"), maxDepth: 4, onlyICloud: true),
                ScanRoot(
                    section: iCloudSection,
                    url: home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs"),
                    maxDepth: 4,
                    onlyICloud: true
                ),
            ],
            icloud: .system(home: home)
        )
    }

    private struct Job: Sendable {
        let repo: DiscoveredRepo
        let root: ScanRoot
        let parent: URL?
    }

    @concurrent
    public func scan() async -> [RepoReport] {
        var jobs: [Job] = []
        var seen = Set<String>()
        for root in roots {
            let found = Discovery.findRepos(under: root.url, maxDepth: root.maxDepth)
                .filter { !root.onlyICloud || icloud.isInICloud($0.path) }
            let paths = found.map(\.path)
            for repo in found where seen.insert(repo.path.resolvingSymlinksInPath().path).inserted {
                jobs.append(Job(repo: repo, root: root, parent: Discovery.nearestAncestor(of: repo.path, in: paths)))
            }
        }

        var reports: [RepoReport] = []
        await withTaskGroup(of: RepoReport.self) { group in
            var pending = jobs.makeIterator()
            for _ in 0..<max(1, concurrency) {
                guard let job = pending.next() else { break }
                group.addTask { inspect(job) }
            }
            for await report in group {
                reports.append(report)
                if let job = pending.next() {
                    group.addTask { inspect(job) }
                }
            }
        }
        return reports
    }

    private func inspect(_ job: Job) -> RepoReport {
        let path = job.repo.path
        var findings: [Finding] = []
        var kind = job.repo.kind

        if let parent = job.parent {
            // The parent's index is the source of truth: older submodule clones
            // keep a full `.git` directory instead of a `.git` pointer file.
            if isRegisteredSubmodule(path, of: parent) {
                kind = .submodule
                findings.append(Finding(.info, "Submodule of \(parent.lastPathComponent)"))
            } else {
                findings.append(Finding(.warning, "Nested inside \(parent.lastPathComponent) but not registered as a submodule"))
            }
        }

        var report = RepoReport(
            path: path,
            displayName: relativeName(of: path, under: job.root.url),
            section: job.root.section,
            kind: kind,
            findings: findings
        )

        if icloud.isInICloud(path) {
            report.findings.append(Finding(.warning, "Inside iCloud: files can be evicted from this Mac"))
            let limit = 50
            let evicted = EvictionCheck.evictedCount(in: path, runner: runner, limit: limit)
            if evicted > 0 {
                let amount = evicted >= limit ? "\(limit)+" : "\(evicted)"
                report.findings.append(Finding(.warning, "\(amount) files evicted; skipped git status to avoid downloading them"))
                return report
            }
        }

        do {
            let status = StatusParser.parse(try runner.run(.status, in: path))
            report.status = status
            report.findings += statusFindings(status, kind: kind)
            if kind == .worktree, RepoActions.isEmptyWorktree(path, status: status, runner: runner) {
                report.isEmptyWorktree = true
                // Its branch is local-only, but every commit is on a remote, so drop that alarm.
                report.findings.removeAll { $0.message.hasPrefix("No upstream") }
                report.findings.append(Finding(.info, "Empty: no changes, all commits are on the remote"))
            }
        } catch {
            report.findings.append(Finding(.warning, "git status failed: \(error)"))
        }

        if let raw = try? runner.run(.lastCommitTime, in: path),
           let seconds = TimeInterval(raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
            report.lastCommit = Date(timeIntervalSince1970: seconds)
        }
        return report
    }

    /// True when the parent's index records `repo` as a gitlink (mode 160000).
    private func isRegisteredSubmodule(_ repo: URL, of parent: URL) -> Bool {
        let relative = String(repo.standardizedFileURL.path.dropFirst(parent.standardizedFileURL.path.count + 1))
        let entry = try? runner.run(.indexEntry(path: relative), in: parent)
        return entry?.hasPrefix("160000 ") == true
    }

    private func statusFindings(_ status: GitStatus, kind: RepoKind) -> [Finding] {
        var findings: [Finding] = []
        let branch = status.branch
        if status.counts.conflicted > 0 {
            findings.append(Finding(.warning, "\(status.counts.conflicted) conflicted files"))
        }
        if branch.isDetached {
            // Submodules sit on a detached HEAD by design.
            if kind != .submodule { findings.append(Finding(.info, "Detached HEAD")) }
        } else if branch.upstream == nil && !branch.isInitial {
            findings.append(Finding(.attention, "No upstream: this branch exists only on this Mac"))
        }
        return findings
    }

    private func relativeName(of path: URL, under root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let full = path.standardizedFileURL.path
        guard full.hasPrefix(rootPath + "/") else { return path.lastPathComponent }
        return String(full.dropFirst(rootPath.count + 1))
    }
}
