import Foundation

/// The only git operations Repo Radar can perform; there is deliberately no way
/// to pass arbitrary arguments to git. Everything is read-only except `fetch`
/// (remote-tracking refs only) and `removeWorktree` (for verified-empty worktrees).
public enum GitCommand: Sendable {
    case status
    case lastCommitTime
    /// `ls-files -s -- <path>`: the index entry for a path (mode 160000 = submodule).
    case indexEntry(path: String)
    case trackedFiles
    /// The shared `.git` directory; for a linked worktree it lives in the main repo.
    case commonGitDirectory
    /// The working tree of the parent repo when this repo is a submodule; empty otherwise.
    case superprojectWorkingTree
    case fetch
    /// Remote-tracking refs that already contain HEAD. Non-empty = HEAD is on a remote.
    case remoteRefsContainingHead
    /// Ignored files and folders, which `worktree remove` deletes without asking.
    case ignoredEntries
    /// Every index entry; gitlinks (mode 160000) are submodules.
    case stagedEntries
    /// Git refuses worktrees containing submodules unless forced. `containsSubmodules`
    /// adds a single `--force`, which still refuses locked worktrees; callers must
    /// verify the worktree and every submodule are clean and pushed first.
    case removeWorktree(path: String, containsSubmodules: Bool)

    public var arguments: [String] {
        switch self {
        case .status: ["status", "--porcelain=v2", "--branch"]
        case .lastCommitTime: ["log", "-1", "--format=%ct"]
        case .indexEntry(let path): ["ls-files", "-s", "--", path]
        case .trackedFiles: ["ls-files", "-z"]
        case .commonGitDirectory: ["rev-parse", "--path-format=absolute", "--git-common-dir"]
        case .superprojectWorkingTree: ["rev-parse", "--show-superproject-working-tree"]
        case .fetch: ["fetch", "--quiet"]
        case .remoteRefsContainingHead: ["for-each-ref", "--contains", "HEAD", "--format=%(refname:short)", "refs/remotes"]
        case .ignoredEntries: ["ls-files", "--others", "--ignored", "--exclude-standard", "--directory", "-z"]
        case .stagedEntries: ["ls-files", "--stage", "-z"]
        case .removeWorktree(let path, let containsSubmodules):
            ["worktree", "remove"] + (containsSubmodules ? ["--force"] : []) + ["--", path]
        }
    }

    var isNetworked: Bool {
        if case .fetch = self { return true }
        return false
    }
}

public struct GitError: Error, Sendable, CustomStringConvertible {
    public let description: String
}

public struct GitRunner: Sendable {
    public var executable = URL(fileURLWithPath: "/usr/bin/git")
    public var timeout: TimeInterval = 15

    public init() {}

    public func run(_ command: GitCommand, in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = executable
        // --no-optional-locks: never take index.lock just to refresh stat info,
        // so a background scan can't collide with git commands the user runs.
        process.arguments = ["--no-optional-locks", "-C", directory.path] + command.arguments
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        // No interactive SSH prompts (passphrases, unknown host keys) from a menu bar app.
        environment["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes"
        environment["LC_ALL"] = "C"
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        try process.run()

        // Network calls get longer than local ones.
        let limit = command.isNetworked ? max(timeout, 90) : timeout
        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + limit, execute: killer)

        // Drain stderr concurrently so a chatty stderr can't block stdout.
        let errorBox = DataBox()
        let errorDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            errorBox.data = stderr.fileHandleForReading.readDataToEndOfFile()
            errorDone.signal()
        }
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        errorDone.wait()
        killer.cancel()

        if process.terminationReason == .uncaughtSignal {
            throw GitError(description: "git \(command.arguments[0]) timed out after \(Int(limit))s")
        }
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errorBox.data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitError(description: message.isEmpty ? "git exited with \(process.terminationStatus)" : message)
        }
        return String(decoding: output, as: UTF8.self)
    }
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}
