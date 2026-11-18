import Foundation

public enum RepoActions {
    /// The folder to open in T3 Code. T3 projects are set up at the top-level repo,
    /// so a linked worktree opens its main repo and a submodule opens its parent.
    public static func t3WorkspaceRoot(for repo: URL, kind: RepoKind, runner: GitRunner = GitRunner()) -> URL {
        switch kind {
        case .worktree:
            if let main = mainRepo(ofWorktree: repo, runner: runner) { return main }
        case .submodule:
            if let raw = try? runner.run(.superprojectWorkingTree, in: repo) {
                let parent = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !parent.isEmpty { return URL(fileURLWithPath: parent) }
            }
        case .repository:
            break
        }
        return repo
    }

    /// Updates remote-tracking refs only. Never merges, rebases, or touches files.
    public static func fetch(_ repo: URL, runner: GitRunner = GitRunner()) throws {
        _ = try runner.run(.fetch, in: repo)
    }

    // MARK: Empty worktrees

    /// `<main repo>/.git` → `<main repo>`; nil if `worktree` is not a linked worktree.
    public static func mainRepo(ofWorktree worktree: URL, runner: GitRunner = GitRunner()) -> URL? {
        guard let raw = try? runner.run(.commonGitDirectory, in: worktree) else { return nil }
        let gitDir = URL(fileURLWithPath: raw.trimmingCharacters(in: .whitespacesAndNewlines))
        guard gitDir.lastPathComponent == ".git" else { return nil }
        let main = gitDir.deletingLastPathComponent()
        let same = main.resolvingSymlinksInPath().standardizedFileURL.path
            == worktree.resolvingSymlinksInPath().standardizedFileURL.path
        return same ? nil : main
    }

    /// Empty means removing it loses nothing: no modified or untracked files, and the
    /// checked-out commit is already contained in a remote-tracking branch. The same
    /// must hold for every initialized submodule inside it, checked directly rather
    /// than through the parent's status (a `.gitmodules` `ignore =` setting can hide it).
    public static func isEmptyWorktree(_ worktree: URL, status: GitStatus, runner: GitRunner = GitRunner()) -> Bool {
        guard isCleanAndPushed(worktree, status: status, runner: runner) else { return false }
        return initializedSubmodules(in: worktree, runner: runner).allSatisfy { submodule in
            guard let raw = try? runner.run(.status, in: submodule) else { return false }
            return isCleanAndPushed(submodule, status: StatusParser.parse(raw), runner: runner)
        }
    }

    private static func isCleanAndPushed(_ tree: URL, status: GitStatus, runner: GitRunner) -> Bool {
        guard status.counts.total == 0, !status.branch.isInitial else { return false }
        guard let refs = try? runner.run(.remoteRefsContainingHead, in: tree) else { return false }
        return !refs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Checked-out submodules under `tree`, nested ones included.
    public static func initializedSubmodules(in tree: URL, runner: GitRunner = GitRunner()) -> [URL] {
        guard let raw = try? runner.run(.stagedEntries, in: tree) else { return [] }
        var result: [URL] = []
        for entry in raw.split(separator: "\0") where entry.hasPrefix("160000 ") {
            guard let tab = entry.firstIndex(of: "\t") else { continue }
            let submodule = tree.appendingPathComponent(String(entry[entry.index(after: tab)...]))
            guard FileManager.default.fileExists(atPath: submodule.appendingPathComponent(".git").path) else { continue }
            result.append(submodule)
            result += initializedSubmodules(in: submodule, runner: runner)
        }
        return result
    }

    /// Ignored files and folders that removal would delete (e.g. `node_modules/`, `.env`),
    /// including those inside submodules, relative to the worktree.
    public static func ignoredEntries(in worktree: URL, runner: GitRunner = GitRunner()) -> [String] {
        let prefixLength = worktree.standardizedFileURL.path.count + 1
        return ([worktree] + initializedSubmodules(in: worktree, runner: runner)).flatMap { tree -> [String] in
            guard let raw = try? runner.run(.ignoredEntries, in: tree) else { return [] }
            let prefix = tree == worktree ? "" : String(tree.standardizedFileURL.path.dropFirst(prefixLength)) + "/"
            return raw.split(separator: "\0").map { prefix + $0 }
        }
    }

    public struct RemovalError: Error, CustomStringConvertible, Sendable {
        public let description: String
    }

    /// Re-checks emptiness at removal time (the scan may be stale), then runs
    /// `git worktree remove` from the main repo. The branch is kept. Git only removes
    /// worktrees with submodules when forced; that single `--force` is used only after
    /// the check above has verified each submodule, and it still refuses locked worktrees.
    public static func removeEmptyWorktree(_ worktree: URL, runner: GitRunner = GitRunner()) throws {
        guard let main = mainRepo(ofWorktree: worktree, runner: runner) else {
            throw RemovalError(description: "\(worktree.lastPathComponent) is not a linked worktree")
        }
        let status = StatusParser.parse(try runner.run(.status, in: worktree))
        guard isEmptyWorktree(worktree, status: status, runner: runner) else {
            throw RemovalError(description: "\(worktree.lastPathComponent) has changes or unpushed commits; left in place")
        }
        let hasSubmodules = !initializedSubmodules(in: worktree, runner: runner).isEmpty
        _ = try runner.run(.removeWorktree(path: worktree.path, containsSubmodules: hasSubmodules), in: main)
    }
}
