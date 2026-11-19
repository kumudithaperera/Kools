@testable import KoolsCore
@testable import RepoRadarCore
import XCTest

final class PriorityOrderTests: XCTestCase {
    func testDefaultOrderShowsEverything() {
        XCTAssertEqual(TabLayout().visible, [.repoRadar, .tools])
        XCTAssertEqual(ToolLayout().visible, [.shelf, .quitOnClose, .cutPaste])
    }

    func testSavedOrderIsRepairedNotLost() {
        // Old saves listed the tools as tabs; those names are dropped.
        XCTAssertEqual(TabLayout(order: ["shelf", "tools", "cutPaste"]).order, [.tools, .repoRadar])
        XCTAssertEqual(ToolLayout(order: ["cutPaste", "bogus", "cutPaste"]).order, [.cutPaste, .shelf, .quitOnClose])
    }

    func testMoveMatchesOnMove() {
        var layout = ToolLayout()
        layout.move(fromOffsets: [2], toOffset: 0)
        XCTAssertEqual(layout.order, [.cutPaste, .shelf, .quitOnClose])
        layout.move(fromOffsets: [0], toOffset: 3)
        XCTAssertEqual(layout.order, [.shelf, .quitOnClose, .cutPaste])
        layout.move(fromOffsets: [0, 1], toOffset: 3)
        XCTAssertEqual(layout.order, [.cutPaste, .shelf, .quitOnClose])
    }

    func testLastVisibleItemCannotBeHidden() {
        var layout = TabLayout(hidden: ["tools"])
        layout.setHidden(.repoRadar, true)
        XCTAssertEqual(layout.visible, [.repoRadar])
        XCTAssertEqual(ToolLayout(hidden: ToolItem.allCases.map(\.rawValue)).visible, [.shelf])
    }

    func testOpensOnLastUsedUnlessHidden() {
        let layout = TabLayout(order: ["tools"], hidden: [])
        XCTAssertEqual(layout.opening(lastUsed: "repoRadar"), .repoRadar)
        XCTAssertEqual(layout.opening(lastUsed: "shelf"), .tools)
        XCTAssertEqual(layout.opening(lastUsed: nil), .tools)
        XCTAssertEqual(TabLayout(hidden: ["repoRadar"]).opening(lastUsed: "repoRadar"), .tools)
    }

    func testSavedHiddenFollowsOrder() {
        let layout = ToolLayout(order: ["cutPaste", "shelf"], hidden: ["shelf", "cutPaste"])
        XCTAssertEqual(layout.savedHidden, ["cutPaste", "shelf"])
    }
}

final class GitTaskTests: XCTestCase {
    func testAvailability() {
        XCTAssertTrue(GitTask.commit.isAvailable(changes: 2, ahead: 0, behind: 0, hasUpstream: true, isDetached: false))
        XCTAssertFalse(GitTask.commit.isAvailable(changes: 0, ahead: 0, behind: 0, hasUpstream: true, isDetached: false))
        XCTAssertTrue(GitTask.push.isAvailable(changes: 0, ahead: 1, behind: 0, hasUpstream: true, isDetached: false))
        XCTAssertTrue(GitTask.push.isAvailable(changes: 0, ahead: nil, behind: nil, hasUpstream: false, isDetached: false))
        // With changes, push is offered as Commit & Push instead.
        XCTAssertFalse(GitTask.push.isAvailable(changes: 1, ahead: 1, behind: 0, hasUpstream: true, isDetached: false))
        XCTAssertTrue(GitTask.pull.isAvailable(changes: 0, ahead: 0, behind: 3, hasUpstream: true, isDetached: false))
        XCTAssertFalse(GitTask.pull.isAvailable(changes: 0, ahead: 0, behind: 0, hasUpstream: true, isDetached: false))
        XCTAssertFalse(GitTask.commit.isAvailable(changes: 2, ahead: 0, behind: 0, hasUpstream: true, isDetached: true))
    }

    func testPromptNamesTheRepoAndKeepsSafetyRules() {
        let repo = URL(fileURLWithPath: "/Users/me/Projects/Morsel/app")
        for task in GitTask.allCases {
            let prompt = task.prompt(repo: repo, branch: "main", message: nil)
            XCTAssertTrue(prompt.contains("`/Users/me/Projects/Morsel/app` (branch `main`)"), "\(task)")
            XCTAssertTrue(prompt.contains("Never force push"), "\(task)")
        }
        XCTAssertTrue(GitTask.commit.prompt(repo: repo, branch: nil, message: nil).contains("Don't push"))
    }

    func testCommitMessageIsUsedWhenGiven() {
        let repo = URL(fileURLWithPath: "/r")
        XCTAssertTrue(GitTask.commit.prompt(repo: repo, branch: nil, message: "  Fix login  ").contains("\n\nFix login\n"))
        XCTAssertTrue(GitTask.commit.prompt(repo: repo, branch: nil, message: "  ").contains("Write a clear commit message"))
        XCTAssertEqual(GitTask.commitAndPush.threadTitle(repoName: "Morsel/app"), "Commit & Push: Morsel/app")
    }
}

final class StatusBadgeTests: XCTestCase {
    private func report(findings: [Finding] = [], changed: Int = 0, ahead: Int? = nil, behind: Int? = nil) -> RepoReport {
        var status = GitStatus()
        status.counts.changed = changed
        status.branch.ahead = ahead
        status.branch.behind = behind
        return RepoReport(path: URL(fileURLWithPath: "/r"), displayName: "r", section: "Projects", kind: .repository,
                          status: status, findings: findings)
    }

    func testCleanRepoNeedsNothing() {
        XCTAssertNil(StatusBadge.badge(for: report(ahead: 0, behind: 0)))
        XCTAssertNil(StatusBadge.badge(for: report(findings: [Finding(.info, "Detached HEAD")])))
    }

    func testEachNeedMapsToItsIcon() {
        XCTAssertEqual(StatusBadge.badge(for: report(behind: 2)), .pull)
        XCTAssertEqual(StatusBadge.badge(for: report(ahead: 1)), .push)
        XCTAssertEqual(StatusBadge.badge(for: report(findings: [Finding(.attention, "No upstream")])), .push)
        XCTAssertEqual(StatusBadge.badge(for: report(changed: 3)), .commit)
        XCTAssertEqual(StatusBadge.badge(for: report(findings: [Finding(.warning, "Inside iCloud")])), .warning)
    }

    func testMostUrgentWins() {
        XCTAssertEqual(StatusBadge.badge(for: report(changed: 1, ahead: 1, behind: 1)), .commit)
        let reports = [report(behind: 1), report(ahead: 2), report(findings: [Finding(.warning, "Nested")])]
        XCTAssertEqual(StatusBadge.top(reports: reports, needsPermission: false), .warning)
        XCTAssertEqual(StatusBadge.top(reports: reports, needsPermission: true), .permission)
        XCTAssertNil(StatusBadge.top(reports: [], needsPermission: false))
    }

    func testNeedsCountReposPerBadgeMostUrgentFirst() {
        let reports = [
            report(ahead: 1), report(ahead: 3), report(changed: 2), report(behind: 1),
            report(findings: [Finding(.warning, "Nested")]), report(),
        ]
        XCTAssertEqual(StatusBadge.needs(reports: reports, permissionCount: 0), [
            StatusNeed(badge: .warning, count: 1),
            StatusNeed(badge: .commit, count: 1),
            StatusNeed(badge: .push, count: 2),
            StatusNeed(badge: .pull, count: 1),
        ])
        XCTAssertEqual(StatusBadge.needs(reports: reports, permissionCount: 2).first,
                       StatusNeed(badge: .permission, count: 2))
        XCTAssertTrue(StatusBadge.needs(reports: [report()], permissionCount: 0).isEmpty)
    }

    func testCountLabelCapsAtNinetyNinePlus() {
        XCTAssertEqual(StatusNeed(badge: .pull, count: 9).countLabel, "9")
        XCTAssertEqual(StatusNeed(badge: .pull, count: 99).countLabel, "99")
        XCTAssertEqual(StatusNeed(badge: .pull, count: 128).countLabel, "99+")
    }
}

final class CommitMessageTests: XCTestCase {
    func testExtractsTaggedMessage() {
        let reply = """
        Here's a message:

        <commit-message>
        Add git actions to Repo Radar

        Commits, pushes and pulls run in T3 threads.
        </commit-message>
        """
        XCTAssertEqual(CommitMessage.extract(from: reply), "Add git actions to Repo Radar\n\nCommits, pushes and pulls run in T3 threads.")
    }

    func testUsesLastPairAndStripsFences() {
        let reply = "Format: <commit-message>x</commit-message>\n<commit-message>\n```\nFix login\n```\n</commit-message>"
        XCTAssertEqual(CommitMessage.extract(from: reply), "Fix login")
    }

    func testMissingOrEmptyTagsGiveNil() {
        XCTAssertNil(CommitMessage.extract(from: "I couldn't read the diff."))
        XCTAssertNil(CommitMessage.extract(from: "<commit-message>\n\n</commit-message>"))
    }

    func testSuggestPromptChangesNothing() {
        let prompt = GitTask.suggestMessagePrompt(repo: URL(fileURLWithPath: "/r"), branch: "main")
        XCTAssertTrue(prompt.contains("Don't change, stage or commit anything"))
        XCTAssertTrue(prompt.contains(CommitMessage.openTag))
    }

    func testGivenMessageIsOneCommit() {
        let prompt = GitTask.commit.prompt(repo: URL(fileURLWithPath: "/r"), branch: nil, message: "Fix login")
        XCTAssertTrue(prompt.contains("one commit with this message"))
        XCTAssertFalse(prompt.contains("split them"))
    }
}
