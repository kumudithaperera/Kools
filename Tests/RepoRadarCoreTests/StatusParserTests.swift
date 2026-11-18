@testable import RepoRadarCore
import XCTest

final class StatusParserTests: XCTestCase {
    func testCleanBranchWithUpstream() {
        let status = StatusParser.parse("""
        # branch.oid be8f19333d7e9f180391fd0fbd96a54829e61d2e
        # branch.head main
        # branch.upstream origin/main
        # branch.ab +0 -0

        """)
        XCTAssertEqual(status.branch.head, "main")
        XCTAssertEqual(status.branch.upstream, "origin/main")
        XCTAssertEqual(status.branch.ahead, 0)
        XCTAssertEqual(status.branch.behind, 0)
        XCTAssertFalse(status.branch.isDetached)
        XCTAssertEqual(status.counts.total, 0)
    }

    func testCountsEveryEntryType() {
        let status = StatusParser.parse("""
        # branch.oid be8f19333d7e9f180391fd0fbd96a54829e61d2e
        # branch.head feature/pricing-update
        # branch.upstream origin/feature/pricing-update
        # branch.ab +3 -12
        1 .M N... 100644 100644 100644 aaaa aaaa src/app.ts
        1 .M S..U 160000 160000 160000 0230e82 0230e82 server
        2 R. N... 100644 100644 100644 bbbb bbbb R100 new name.txt\told name.txt
        u UU N... 100644 100644 100644 100644 cccc dddd eeee conflicted file.swift
        ? notes with spaces.md
        ? scratch/
        ! ignored.log
        """)
        XCTAssertEqual(status.branch.head, "feature/pricing-update")
        XCTAssertEqual(status.branch.ahead, 3)
        XCTAssertEqual(status.branch.behind, 12)
        XCTAssertEqual(status.counts.changed, 3)
        XCTAssertEqual(status.counts.conflicted, 1)
        XCTAssertEqual(status.counts.untracked, 2)
        XCTAssertEqual(status.counts.total, 6)
    }

    func testDetachedHeadWithoutUpstream() {
        let status = StatusParser.parse("""
        # branch.oid 0230e8251d307eb075d908dea476ad129be78c47
        # branch.head (detached)
        """)
        XCTAssertTrue(status.branch.isDetached)
        XCTAssertNil(status.branch.head)
        XCTAssertNil(status.branch.upstream)
        XCTAssertNil(status.branch.ahead)
    }

    func testInitialRepo() {
        let status = StatusParser.parse("""
        # branch.oid (initial)
        # branch.head main
        ? README.md
        """)
        XCTAssertTrue(status.branch.isInitial)
        XCTAssertEqual(status.counts.untracked, 1)
    }

    func testCommandsNeverCommitPushOrRewrite() {
        // Writing verbs: fetch (remote-tracking refs only) and worktree remove.
        let allowedVerbs: Set<String> = ["status", "log", "ls-files", "rev-parse", "for-each-ref", "fetch", "worktree"]
        let commands: [GitCommand] = [
            .status, .lastCommitTime, .indexEntry(path: "x"), .trackedFiles,
            .commonGitDirectory, .superprojectWorkingTree, .fetch,
            .remoteRefsContainingHead, .ignoredEntries, .stagedEntries,
            .removeWorktree(path: "x", containsSubmodules: false),
        ]
        for command in commands {
            XCTAssertTrue(allowedVerbs.contains(command.arguments[0]), "\(command.arguments)")
            XCTAssertFalse(command.arguments.contains { $0 == "-f" || $0 == "--force" }, "\(command.arguments)")
        }
        XCTAssertEqual(GitCommand.fetch.arguments, ["fetch", "--quiet"])
        XCTAssertEqual(
            GitCommand.removeWorktree(path: "-f", containsSubmodules: false).arguments,
            ["worktree", "remove", "--", "-f"]
        )
        // Submodules need exactly one --force, which git still refuses for locked worktrees.
        XCTAssertEqual(
            GitCommand.removeWorktree(path: "x", containsSubmodules: true).arguments,
            ["worktree", "remove", "--force", "--", "x"]
        )
    }
}
