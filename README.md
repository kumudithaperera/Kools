# Repo Radar

A menu bar app that watches every git repo under `~/Projects` and shows what needs attention.

- Branch, uncommitted file count (`●`), and commits ahead/behind upstream (`↑` `↓`).
- Warns about repos nested inside other repos that are not registered submodules
  (registered submodules get an info note).
- Warns about repos inside iCloud, and counts files iCloud has evicted.
- Lists T3 worktrees from `~/.t3/worktrees` in a collapsed section.

## Menu actions

Each repo is a submenu with its branch, findings, and these actions:

- **Open in T3 Code**: runs `~/.t3/bin/t3 app <folder>`, starting T3 Code first if needed.
  T3 projects live at the top-level repo, so a T3 worktree opens its main repo and a
  submodule opens its parent. A folder with no T3 project yet gets a new one.
- **Fetch**: `git fetch --quiet` (only for repos with an upstream). **Fetch All** in the
  main menu fetches every such repo, four at a time.
- **Remove Worktree…** (empty worktrees only) and **Clean Empty Worktrees…** at the top
  of the T3 worktrees submenu. A worktree is empty when it has no modified or untracked
  files and its checked-out commit is already in a remote-tracking branch, so removing
  it loses nothing. A dialog lists the worktrees and any ignored files (`node_modules/`,
  `.env`) that would go with them, including inside submodules. Every initialized
  submodule must also be clean with its commit on its own remote, checked directly
  (a `.gitmodules` `ignore =` setting can hide submodule changes from the parent).
  Emptiness is re-checked right before removal, which runs `git worktree remove` from
  the main repo. Git refuses to remove worktrees containing submodules unless forced,
  so those get a single `--force` after that check; locked worktrees are still refused.
  Branches are kept.
- **Reveal in Finder**, **Copy Path**.

## What git can do

Every git call goes through `GitRunner`, which only accepts a fixed set of commands:
`status`, `log -1`, `ls-files`, `rev-parse`, `for-each-ref`, `fetch`, and
`worktree remove`. Nothing can commit, push, pull, merge, or change your branches.
`fetch` only updates remote-tracking refs, and the only files ever deleted are those
of an empty worktree you confirmed. SSH runs with `BatchMode=yes`, so a fetch that needs a passphrase or an unknown
host key fails with a message instead of hanging.
Scans run with `--no-optional-locks` so they never take `index.lock`.

Scans don't fetch, so ↑↓ counts are relative to the last fetch.

## What gets scanned

| Section | Path | Depth |
|---|---|---|
| Projects | `~/Projects` | 6 |
| T3 worktrees | `~/.t3/worktrees` | 2 |
| In iCloud | `~/Desktop`, `~/Documents`, iCloud Drive (only repos macOS reports as iCloud items) | 4 |

Skipped: hidden folders, symlinks, app bundles, `node_modules`, `Pods`, `Carthage`,
`DerivedData`, `build`, `dist`, `vendor`.

For repos in iCloud, eviction is checked with `lstat` first. If any files are evicted,
`git status` is skipped, because it would make iCloud download them.

Scans run at launch, every 5 minutes, when the menu opens (if the last scan is over
30 seconds old), and from the refresh button.

## Build and run

Requires macOS 14+ and Xcode (Swift 6).

```sh
swift test               # unit + integration tests (builds throwaway repos in $TMPDIR)
scripts/bundle.sh        # builds build/RepoRadar.app
open build/RepoRadar.app
```

The menu is a native system menu (`MenuBarExtra` with `.menu` style), so macOS draws
it with the standard menu material, including Liquid Glass on macOS 26 and later.
