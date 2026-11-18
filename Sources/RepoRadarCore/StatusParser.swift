import Foundation

/// Parses `git status --porcelain=v2 --branch`.
public enum StatusParser {
    public static func parse(_ output: String) -> GitStatus {
        var status = GitStatus()
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("# ") {
                parseHeader(line.dropFirst(2), into: &status.branch)
                continue
            }
            switch line.first {
            case "1", "2": status.counts.changed += 1
            case "u": status.counts.conflicted += 1
            case "?": status.counts.untracked += 1
            default: break // "!" ignored entries, or anything unknown
            }
        }
        return status
    }

    private static func parseHeader(_ header: Substring, into branch: inout BranchInfo) {
        let parts = header.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { return }
        let value = String(parts[1])
        switch parts[0] {
        case "branch.oid":
            branch.isInitial = value == "(initial)"
        case "branch.head":
            if value == "(detached)" {
                branch.isDetached = true
                branch.head = nil
            } else {
                branch.head = value
            }
        case "branch.upstream":
            branch.upstream = value
        case "branch.ab":
            let counts = value.split(separator: " ")
            guard counts.count == 2 else { return }
            branch.ahead = Int(counts[0].dropFirst())  // "+3"
            branch.behind = Int(counts[1].dropFirst()) // "-1"
        default:
            break
        }
    }
}
