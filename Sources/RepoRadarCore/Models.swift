import Foundation

public enum Severity: Int, Comparable, Sendable {
    case clean = 0
    case info
    case attention
    case warning

    public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct Finding: Hashable, Sendable {
    public let severity: Severity
    public let message: String

    public init(_ severity: Severity, _ message: String) {
        self.severity = severity
        self.message = message
    }
}

public enum RepoKind: Sendable {
    /// A working tree with its own `.git` directory.
    case repository
    /// A `.git` file pointing into a parent's `.git/modules`.
    case submodule
    /// A `.git` file pointing into another repo's `.git/worktrees`.
    case worktree
}

public struct BranchInfo: Equatable, Sendable {
    /// Branch name; nil when HEAD is detached.
    public var head: String?
    public var isDetached = false
    /// True when the repo has no commits yet.
    public var isInitial = false
    public var upstream: String?
    /// Counts relative to the upstream as of the last fetch. Nil without an upstream.
    public var ahead: Int?
    public var behind: Int?

    public init() {}
}

public struct WorkingTreeCounts: Equatable, Sendable {
    public var changed = 0
    public var untracked = 0
    public var conflicted = 0

    public init() {}

    public var total: Int { changed + untracked + conflicted }
}

public struct GitStatus: Equatable, Sendable {
    public var branch = BranchInfo()
    public var counts = WorkingTreeCounts()

    public init() {}
}

public struct RepoReport: Identifiable, Sendable {
    public let path: URL
    /// Path relative to the scan root, e.g. `Morsel/app/server`.
    public let displayName: String
    public let section: String
    public let kind: RepoKind
    public var status: GitStatus?
    public var lastCommit: Date?
    public var findings: [Finding]
    /// A linked worktree with no changes whose commits are all on a remote.
    public var isEmptyWorktree = false

    public var id: String { path.path }

    public var severity: Severity {
        var worst = findings.map(\.severity).max() ?? .clean
        if let status {
            let busy = status.counts.total > 0
                || (status.branch.ahead ?? 0) > 0
                || (status.branch.behind ?? 0) > 0
            if busy { worst = max(worst, .attention) }
        }
        return worst
    }
}
