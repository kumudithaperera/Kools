@testable import RepoRadarCore
import XCTest

/// Builds real repos in a temp folder whose name contains spaces.
final class ScannerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Radar Test \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Fixture helpers (tests may write; the app never does)

    @discardableResult
    private func git(_ args: [String], in dir: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = [
            "-c", "user.name=Radar Test", "-c", "user.email=radar@example.invalid",
            "-c", "init.defaultBranch=main", "-c", "commit.gpgsign=false",
            "-c", "protocol.file.allow=always", "-C", dir.path,
        ] + args
        let out = Pipe()
        process.standardOutput = out
        process.standardError = out
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw GitError(description: "git \(args.joined(separator: " ")) failed: \(text)")
        }
        return text
    }

    private func dir(_ relative: String) throws -> URL {
        let url = root.appendingPathComponent(relative, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ relative: String, in repo: URL, _ text: String = "x\n") throws {
        try text.write(to: repo.appendingPathComponent(relative), atomically: true, encoding: .utf8)
    }

    private func committedRepo(_ relative: String) throws -> URL {
        let repo = try dir(relative)
        try git(["init", "-q"], in: repo)
        try write("README.md", in: repo)
        try git(["add", "."], in: repo)
        try git(["commit", "-qm", "init"], in: repo)
        return repo
    }

    private func scanner(icloudRoots: [URL] = []) -> RepoScanner {
        RepoScanner(
            roots: [ScanRoot(section: "Projects", url: root, maxDepth: 6)],
            icloud: ICloudDetector(syncedRoots: icloudRoots)
        )
    }

    private func report(_ name: String, in reports: [RepoReport]) throws -> RepoReport {
        try XCTUnwrap(reports.first { $0.displayName == name }, "no report for \(name): \(reports.map(\.displayName))")
    }

    // MARK: Tests

    func testDiscoverySkipsDependencyAndHiddenFolders() throws {
        _ = try committedRepo("visible")
        _ = try committedRepo("app/node_modules/pkg")
        _ = try committedRepo(".hidden/repo")
        let found = Discovery.findRepos(under: root, maxDepth: 6).map(\.path.lastPathComponent)
        XCTAssertEqual(found, ["visible"])
    }

    func testDirtyRepoWithSpacesAndNoUpstream() async throws {
        let repo = try committedRepo("Carbon Website")
        try write("README.md", in: repo, "changed\n")
        try write("new file.txt", in: repo)

        let result = try report("Carbon Website", in: await scanner().scan())
        XCTAssertEqual(result.status?.branch.head, "main")
        XCTAssertEqual(result.status?.counts.changed, 1)
        XCTAssertEqual(result.status?.counts.untracked, 1)
        XCTAssertTrue(result.findings.contains { $0.message.hasPrefix("No upstream") })
        XCTAssertEqual(result.severity, .attention)
        XCTAssertNotNil(result.lastCommit)
    }

    func testAheadAndBehindAgainstUpstream() async throws {
        let seed = try committedRepo("seed")
        let bare = try dir("remotes/origin.git")
        try git(["clone", "-q", "--bare", seed.path, bare.path], in: root)
        try git(["clone", "-q", bare.path, root.appendingPathComponent("work").path], in: root)
        let work = root.appendingPathComponent("work")
        try write("local.txt", in: work)
        try git(["add", "."], in: work)
        try git(["commit", "-qm", "local"], in: work)

        let result = try report("work", in: await scanner().scan())
        XCTAssertEqual(result.status?.branch.upstream, "origin/main")
        XCTAssertEqual(result.status?.branch.ahead, 1)
        XCTAssertEqual(result.status?.branch.behind, 0)
        XCTAssertEqual(result.severity, .attention)
    }

    func testRegisteredSubmoduleIsInfoNotWarning() async throws {
        let library = try committedRepo("library")
        let parent = try committedRepo("Morsel/app")
        try git(["submodule", "add", "-q", library.path, "server"], in: parent)
        try git(["commit", "-qm", "add submodule"], in: parent)

        let result = try report("Morsel/app/server", in: await scanner().scan())
        XCTAssertEqual(result.kind, .submodule)
        XCTAssertTrue(result.findings.contains(Finding(.info, "Submodule of app")))
        XCTAssertFalse(result.findings.contains { $0.severity == .warning })
        XCTAssertFalse(result.findings.contains { $0.message == "Detached HEAD" })
    }

    func testSubmoduleWithFullGitDirectoryIsStillASubmodule() async throws {
        let parent = try committedRepo("outer")
        let inner = try committedRepo("outer/server")
        XCTAssertEqual(Discovery.kind(ofGitEntry: inner.appendingPathComponent(".git")), .repository)
        let sha = try git(["rev-parse", "HEAD"], in: inner).trimmingCharacters(in: .whitespacesAndNewlines)
        try git(["update-index", "--add", "--cacheinfo", "160000,\(sha),server"], in: parent)

        let result = try report("outer/server", in: await scanner().scan())
        XCTAssertEqual(result.kind, .submodule)
        XCTAssertEqual(result.findings, [Finding(.info, "Submodule of outer"), Finding(.attention, "No upstream: this branch exists only on this Mac")])
    }

    func testStrayNestedRepoIsWarning() async throws {
        _ = try committedRepo("outer")
        _ = try committedRepo("outer/inner")

        let reports = await scanner().scan()
        let inner = try report("outer/inner", in: reports)
        XCTAssertTrue(inner.findings.contains(Finding(.warning, "Nested inside outer but not registered as a submodule")))
        XCTAssertEqual(inner.severity, .warning)
        XCTAssertFalse(try report("outer", in: reports).findings.contains { $0.message.contains("Nested") })
    }

    func testRepoInsideICloudRootIsWarning() async throws {
        let cloud = try dir("Mobile Documents")
        _ = try committedRepo("Mobile Documents/Morsel")

        let result = try report("Mobile Documents/Morsel", in: await scanner(icloudRoots: [cloud]).scan())
        XCTAssertTrue(result.findings.contains { $0.severity == .warning && $0.message.hasPrefix("Inside iCloud") })
        // No evicted files in a local temp folder, so status still runs.
        XCTAssertNotNil(result.status)
    }

    func testOnlyICloudRootDropsLocalRepos() async throws {
        _ = try committedRepo("Desktop/local-only")
        let scanner = RepoScanner(
            roots: [ScanRoot(section: RepoScanner.iCloudSection, url: root, maxDepth: 4, onlyICloud: true)],
            icloud: ICloudDetector(syncedRoots: [])
        )
        let reports = await scanner.scan()
        XCTAssertTrue(reports.isEmpty)
    }

    func testFetchUpdatesBehindCountWithoutTouchingTheBranch() async throws {
        let seed = try committedRepo("seed")
        let bare = root.appendingPathComponent("origin.git")
        try git(["clone", "-q", "--bare", seed.path, bare.path], in: root)
        let work = root.appendingPathComponent("work")
        let other = root.appendingPathComponent("other")
        try git(["clone", "-q", bare.path, work.path], in: root)
        try git(["clone", "-q", bare.path, other.path], in: root)
        try write("remote.txt", in: other)
        try git(["add", "."], in: other)
        try git(["commit", "-qm", "remote change"], in: other)
        try git(["push", "-q"], in: other)
        let headBefore = try git(["rev-parse", "HEAD"], in: work)

        let before = try report("work", in: await scanner().scan())
        XCTAssertEqual(before.status?.branch.behind, 0)
        try RepoActions.fetch(work)
        let after = try report("work", in: await scanner().scan())
        XCTAssertEqual(after.status?.branch.behind, 1)
        XCTAssertEqual(try git(["rev-parse", "HEAD"], in: work), headBefore)
    }

    func testT3OpensTheTopLevelRepo() throws {
        let main = try committedRepo("Morsel/app")
        let worktree = root.appendingPathComponent("worktrees/t3-abc")
        try git(["worktree", "add", "-q", "-b", "t3/feature", worktree.path], in: main)
        let library = try committedRepo("library")
        try git(["submodule", "add", "-q", library.path, "server"], in: main)
        let resolved = { (url: URL) in url.resolvingSymlinksInPath().standardizedFileURL.path }

        XCTAssertEqual(resolved(RepoActions.t3WorkspaceRoot(for: worktree, kind: .worktree)), resolved(main))
        XCTAssertEqual(resolved(RepoActions.t3WorkspaceRoot(for: main.appendingPathComponent("server"), kind: .submodule)), resolved(main))
        XCTAssertEqual(RepoActions.t3WorkspaceRoot(for: library, kind: .repository), library)
    }

    // MARK: Empty worktrees

    /// A clone of a bare remote plus a linked worktree on a new branch at origin/main.
    private func repoWithWorktree() throws -> (main: URL, worktree: URL) {
        let seed = try committedRepo("seed")
        let bare = root.appendingPathComponent("origin.git")
        try git(["clone", "-q", "--bare", seed.path, bare.path], in: root)
        let main = root.appendingPathComponent("app")
        try git(["clone", "-q", bare.path, main.path], in: root)
        let worktree = root.appendingPathComponent("worktrees/t3 one")
        try git(["worktree", "add", "-q", "-b", "t3/task", worktree.path], in: main)
        return (main, worktree)
    }

    private func worktreeScanner() -> RepoScanner {
        RepoScanner(
            roots: [ScanRoot(section: "T3 worktrees", url: root.appendingPathComponent("worktrees"), maxDepth: 2)],
            icloud: ICloudDetector(syncedRoots: [])
        )
    }

    func testCleanWorktreeOnRemoteIsEmptyAndRemovable() async throws {
        let (main, worktree) = try repoWithWorktree()

        let scanned = try report("t3 one", in: await worktreeScanner().scan())
        XCTAssertTrue(scanned.isEmptyWorktree)
        XCTAssertFalse(scanned.findings.contains { $0.message.hasPrefix("No upstream") })

        try RepoActions.removeEmptyWorktree(worktree)
        XCTAssertFalse(FileManager.default.fileExists(atPath: worktree.path))
        XCTAssertEqual(try git(["branch", "--list", "t3/task"], in: main).trimmingCharacters(in: .whitespacesAndNewlines), "t3/task")
    }

    func testIgnoredEntriesAreListed() throws {
        let (_, worktree) = try repoWithWorktree()
        try "node_modules/\n".write(to: worktree.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: worktree.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
        try write("node_modules/pkg.js", in: worktree)
        XCTAssertEqual(RepoActions.ignoredEntries(in: worktree), ["node_modules/"])
    }

    func testWorktreeWithChangesIsNotEmptyAndRemovalRefuses() async throws {
        let (_, worktree) = try repoWithWorktree()
        try write("scratch.txt", in: worktree)

        let scanned = try report("t3 one", in: await worktreeScanner().scan())
        XCTAssertFalse(scanned.isEmptyWorktree)
        XCTAssertThrowsError(try RepoActions.removeEmptyWorktree(worktree))
        XCTAssertTrue(FileManager.default.fileExists(atPath: worktree.appendingPathComponent("scratch.txt").path))
    }

    func testWorktreeWithUnpushedCommitIsNotEmpty() async throws {
        let (_, worktree) = try repoWithWorktree()
        try write("work.txt", in: worktree)
        try git(["add", "."], in: worktree)
        try git(["commit", "-qm", "local only"], in: worktree)

        let scanned = try report("t3 one", in: await worktreeScanner().scan())
        XCTAssertFalse(scanned.isEmptyWorktree)
        XCTAssertTrue(scanned.findings.contains { $0.message.hasPrefix("No upstream") })
        XCTAssertThrowsError(try RepoActions.removeEmptyWorktree(worktree))
        XCTAssertTrue(FileManager.default.fileExists(atPath: worktree.path))
    }

    func testRemovalRechecksWhenWorktreeChangedAfterScan() async throws {
        let (_, worktree) = try repoWithWorktree()
        let scanned = try report("t3 one", in: await worktreeScanner().scan())
        XCTAssertTrue(scanned.isEmptyWorktree)
        try write("late edit.txt", in: worktree)
        XCTAssertThrowsError(try RepoActions.removeEmptyWorktree(worktree))
        XCTAssertTrue(FileManager.default.fileExists(atPath: worktree.path))
    }

    func testMainCheckoutIsNeverRemovable() throws {
        let (main, _) = try repoWithWorktree()
        XCTAssertNil(RepoActions.mainRepo(ofWorktree: main))
        XCTAssertThrowsError(try RepoActions.removeEmptyWorktree(main))
        XCTAssertTrue(FileManager.default.fileExists(atPath: main.appendingPathComponent(".git").path))
    }

    // MARK: Worktrees with submodules (git refuses these without --force)

    /// App repo with a `server` submodule, both with bare remotes, plus a linked
    /// worktree whose submodule is initialized. `ignoreAll` sets `ignore = all` on
    /// the submodule so the parent's status hides changes inside it.
    private func worktreeWithSubmodule(ignoreAll: Bool = false) throws -> (main: URL, worktree: URL, submodule: URL) {
        let lib = try committedRepo("lib-seed")
        let libRemote = root.appendingPathComponent("lib.git")
        try git(["clone", "-q", "--bare", lib.path, libRemote.path], in: root)

        let seed = try committedRepo("app-seed")
        try git(["submodule", "add", "-q", libRemote.path, "server"], in: seed)
        if ignoreAll { try git(["config", "-f", ".gitmodules", "submodule.server.ignore", "all"], in: seed) }
        try git(["add", "."], in: seed)
        try git(["commit", "-qm", "add server"], in: seed)
        let appRemote = root.appendingPathComponent("app.git")
        try git(["clone", "-q", "--bare", seed.path, appRemote.path], in: root)

        let main = root.appendingPathComponent("app")
        try git(["clone", "-q", appRemote.path, main.path], in: root)
        let worktree = root.appendingPathComponent("worktrees/t3 one")
        try git(["worktree", "add", "-q", "-b", "t3/task", worktree.path], in: main)
        try git(["submodule", "update", "--init", "-q"], in: worktree)
        return (main, worktree, worktree.appendingPathComponent("server"))
    }

    func testWorktreeWithPushedSubmoduleIsRemoved() async throws {
        let (main, worktree, submodule) = try worktreeWithSubmodule()
        XCTAssertEqual(RepoActions.initializedSubmodules(in: worktree).map(\.lastPathComponent), ["server"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: submodule.appendingPathComponent(".git").path))

        let scanned = try report("t3 one", in: await worktreeScanner().scan())
        XCTAssertTrue(scanned.isEmptyWorktree)

        try RepoActions.removeEmptyWorktree(worktree)
        XCTAssertFalse(FileManager.default.fileExists(atPath: worktree.path))
        XCTAssertFalse(try git(["worktree", "list"], in: main).contains("t3 one"))
    }

    func testDirtySubmoduleHiddenFromParentStatusBlocksRemoval() async throws {
        let (_, worktree, submodule) = try worktreeWithSubmodule(ignoreAll: true)
        try write("unsaved.txt", in: submodule)
        // The parent sees nothing because of ignore = all...
        XCTAssertEqual(StatusParser.parse(try GitRunner().run(.status, in: worktree)).counts.total, 0)

        // ...but the submodule is checked directly.
        let scanned = try report("t3 one", in: await worktreeScanner().scan())
        XCTAssertFalse(scanned.isEmptyWorktree)
        XCTAssertThrowsError(try RepoActions.removeEmptyWorktree(worktree))
        XCTAssertTrue(FileManager.default.fileExists(atPath: submodule.appendingPathComponent("unsaved.txt").path))
    }

    func testUnpushedSubmoduleCommitBlocksRemoval() async throws {
        let (_, worktree, submodule) = try worktreeWithSubmodule(ignoreAll: true)
        try write("local.txt", in: submodule)
        try git(["add", "."], in: submodule)
        try git(["commit", "-qm", "only here"], in: submodule)

        let scanned = try report("t3 one", in: await worktreeScanner().scan())
        XCTAssertFalse(scanned.isEmptyWorktree)
        XCTAssertThrowsError(try RepoActions.removeEmptyWorktree(worktree))
        XCTAssertTrue(FileManager.default.fileExists(atPath: submodule.appendingPathComponent("local.txt").path))
    }

    func testLockedWorktreeWithSubmoduleIsStillRefused() throws {
        let (main, worktree, _) = try worktreeWithSubmodule()
        try git(["worktree", "lock", worktree.path], in: main)
        XCTAssertThrowsError(try RepoActions.removeEmptyWorktree(worktree))
        XCTAssertTrue(FileManager.default.fileExists(atPath: worktree.path))
    }

    func testIgnoredFilesInsideSubmodulesAreListed() throws {
        let (_, worktree, submodule) = try worktreeWithSubmodule()
        let exclude = try git(["rev-parse", "--path-format=absolute", "--git-path", "info/exclude"], in: submodule)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: exclude).deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try "node_modules/\n".write(toFile: exclude, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: submodule.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
        try write("node_modules/pkg.js", in: submodule)
        XCTAssertEqual(RepoActions.ignoredEntries(in: worktree), ["server/node_modules/"])
    }

    func testRunnerHandlesPathsWithSpaces() throws {
        let repo = try committedRepo("path with spaces/repo")
        let output = try GitRunner().run(.status, in: repo)
        XCTAssertTrue(output.contains("# branch.head main"))
    }
}
