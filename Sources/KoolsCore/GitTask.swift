import Foundation

/// A git change Kools hands to a T3 Code agent. Kools never runs these git
/// commands itself; the agent does, in a new thread you can watch and answer.
public enum GitTask: String, CaseIterable, Sendable {
    case commit, commitAndPush, push, pull

    public var title: String {
        switch self {
        case .commit: "Commit"
        case .commitAndPush: "Commit & Push"
        case .push: "Push"
        case .pull: "Pull"
        }
    }

    public var symbol: String {
        switch self {
        case .commit: "checkmark.circle"
        case .commitAndPush: "arrow.up.circle"
        case .push: "arrow.up"
        case .pull: "arrow.down"
        }
    }

    /// Whether the task makes sense for a repo in this state.
    public func isAvailable(changes: Int, ahead: Int?, behind: Int?, hasUpstream: Bool, isDetached: Bool) -> Bool {
        guard !isDetached else { return false }
        switch self {
        case .commit, .commitAndPush: return changes > 0
        case .push: return changes == 0 && ((ahead ?? 0) > 0 || !hasUpstream)
        case .pull: return hasUpstream && (behind ?? 0) > 0
        }
    }

    /// Thread title, e.g. "Commit & Push: Morsel/app".
    public func threadTitle(repoName: String) -> String {
        "\(title): \(repoName)"
    }

    /// The message for the agent. `repo` is the working tree to act on, which
    /// can differ from the T3 project folder (worktrees, nested repos).
    public func prompt(repo: URL, branch: String?, message: String?) -> String {
        let place = "the git repository at `\(repo.path)`" + (branch.map { " (branch `\($0)`)" } ?? "")
        let note = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let messageLine = note.isEmpty
            ? "Write a clear commit message from the diff: a short summary line, then a body if the change needs one. If the changes are unrelated to each other, split them into separate commits."
            : "Commit them together as one commit with this message, fixing only typos:\n\n\(note)\n"
        let safety = "Never commit secrets, credentials or `.env` files; if you find any in the changes, stop and tell me. Never force push or rewrite history."

        switch self {
        case .commit:
            return """
            Commit the current changes in \(place). This was requested from Kools (Repo Radar).

            Review `git status` and the diff first. Stage the changes and commit them. \(messageLine) Don't push.

            \(safety)

            Reply with the commit hash and message.
            """
        case .commitAndPush:
            return """
            Commit the current changes in \(place) and push them. This was requested from Kools (Repo Radar).

            Review `git status` and the diff first. Stage the changes and commit them. \(messageLine) Then push to the branch's upstream; if there is none, push to `origin` and set it as the upstream.

            \(safety) If the push is rejected because the remote has new commits, stop and tell me instead of merging or rebasing.

            Reply with the commit hash, message and push result.
            """
        case .push:
            return """
            Push the commits on \(place). This was requested from Kools (Repo Radar).

            Push to the branch's upstream; if there is none, push to `origin` and set it as the upstream. Don't commit anything.

            \(safety) If the push is rejected because the remote has new commits, stop and tell me instead of merging or rebasing.

            Reply with what was pushed.
            """
        case .pull:
            return """
            Pull the latest commits for \(place). This was requested from Kools (Repo Radar).

            Fetch, then fast-forward the branch to its upstream. If it can't fast-forward because the branch has diverged, or uncommitted changes are in the way, stop and tell me the options instead of merging, rebasing or stashing.

            \(safety)

            Reply with what changed.
            """
        }
    }

    /// Asks the agent only for a commit message, changing nothing. The reply
    /// is read back with `CommitMessage.extract`, and the same thread then
    /// gets the commit request, so one commit uses one thread.
    public static func suggestMessagePrompt(repo: URL, branch: String?) -> String {
        let place = "the git repository at `\(repo.path)`" + (branch.map { " (branch `\($0)`)" } ?? "")
        return """
        Suggest a commit message for the current changes in \(place). This was requested from Kools (Repo Radar), which will show your message for review before anything is committed.

        Read `git status` and the full diff (staged, unstaged, and the names of untracked files). Don't change, stage or commit anything yet.

        Reply with the message inside these tags and nothing else inside them:

        \(CommitMessage.openTag)
        Short summary line, 72 characters at most

        Optional body explaining what changed and why.
        \(CommitMessage.closeTag)

        If you see secrets, credentials or `.env` files in the changes, say so outside the tags.
        """
    }
}

/// Reads a commit message out of an agent's reply.
public enum CommitMessage {
    public static let openTag = "<commit-message>"
    public static let closeTag = "</commit-message>"

    /// The text between the tags (the last pair, if the agent quoted the
    /// format first), with surrounding blank lines and code fences removed.
    /// Nil when the reply has no tagged message.
    public static func extract(from reply: String) -> String? {
        guard let close = reply.range(of: closeTag, options: .backwards),
              let open = reply.range(of: openTag, options: .backwards, range: reply.startIndex..<close.lowerBound)
        else { return nil }
        var lines = reply[open.upperBound..<close.lowerBound]
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
        lines.removeAll { $0.hasPrefix("```") }
        while lines.first?.isEmpty == true { lines.removeFirst() }
        while lines.last?.isEmpty == true { lines.removeLast() }
        let message = lines.joined(separator: "\n")
        return message.isEmpty ? nil : message
    }
}
