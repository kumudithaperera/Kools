import RepoRadarCore

/// The most urgent thing Kools wants you to do. The menu bar shows it as a
/// small status icon in place of the app icon; with nothing to do, the app
/// icon comes back. Higher raw values win.
public enum StatusBadge: Int, Comparable, CaseIterable, Sendable {
    /// Commits on the remote not pulled yet.
    case pull
    /// Commits not pushed, or a branch with no upstream.
    case push
    /// Uncommitted changes.
    case commit
    /// A repo warning: nested repo, iCloud, conflicts, failed status.
    case warning
    /// A feature is on but Accessibility access is missing.
    case permission

    public static func < (lhs: StatusBadge, rhs: StatusBadge) -> Bool { lhs.rawValue < rhs.rawValue }

    public var symbol: String {
        switch self {
        case .pull: "arrow.down"
        case .push: "arrow.up"
        case .commit: "pencil"
        case .warning: "exclamationmark.triangle.fill"
        case .permission: "lock.fill"
        }
    }

    public var summary: String {
        switch self {
        case .pull: "Commits to pull"
        case .push: "Commits to push"
        case .commit: "Uncommitted changes"
        case .warning: "A repo needs a look"
        case .permission: "Kools needs Accessibility access"
        }
    }

    /// What a single repo needs most; nil when it needs nothing.
    public static func badge(for report: RepoReport) -> StatusBadge? {
        var needs: [StatusBadge] = []
        if report.findings.contains(where: { $0.severity == .warning }) { needs.append(.warning) }
        if report.findings.contains(where: { $0.severity == .attention }) { needs.append(.push) }
        if let status = report.status {
            if status.counts.total > 0 { needs.append(.commit) }
            if (status.branch.ahead ?? 0) > 0 { needs.append(.push) }
            if (status.branch.behind ?? 0) > 0 { needs.append(.pull) }
        }
        return needs.max()
    }

    /// What Kools needs most overall.
    public static func top(reports: [RepoReport], needsPermission: Bool) -> StatusBadge? {
        if needsPermission { return .permission }
        return reports.compactMap(badge(for:)).max()
    }

    /// Every distinct need with how many things share it, most urgent first.
    /// Repos are counted under the one badge that is their top need; a
    /// permission need counts the features that are missing access.
    public static func needs(reports: [RepoReport], permissionCount: Int) -> [StatusNeed] {
        var counts: [StatusBadge: Int] = [:]
        for badge in reports.compactMap(badge(for:)) { counts[badge, default: 0] += 1 }
        if permissionCount > 0 { counts[.permission] = permissionCount }
        return counts
            .map { StatusNeed(badge: $0.key, count: $0.value) }
            .sorted { $0.badge > $1.badge }
    }
}

/// One kind of need and how many things share it. The menu bar draws the
/// most urgent as a compact pill, or the top two as a minimal pair.
public struct StatusNeed: Hashable, Sendable {
    public let badge: StatusBadge
    public let count: Int

    public init(badge: StatusBadge, count: Int) {
        self.badge = badge
        self.count = count
    }

    /// The count as shown in the pill, capped so the width stays fixed.
    public var countLabel: String { count > 99 ? "99+" : String(count) }

    public var summary: String { "\(badge.summary): \(count)" }
}
