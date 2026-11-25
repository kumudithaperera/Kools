# Kools

A menu bar toolkit for macOS: Repo Radar, a drag-and-drop Shelf, Quit on Close,
Finder cut and paste and a Clipboard history, behind one icon. Every feature except Repo Radar starts off.

Shelf, Quit on Close and Cut & Paste follow features from
[Vorssaint](https://github.com/vorssaint/vorssaint-utils). The code here is written
from scratch; none of it is copied from Vorssaint.

## Install

Requires macOS 14 or later. Repo Radar looks in `~/Projects` and opens repos in
[T3 Code](https://t3.codes); without those it stays empty, and the other tools work as usual.

**Download** the latest `Kools.zip` from [Releases](https://github.com/kumudithaperera/Kools/releases),
unzip it and drag `Kools.app` to Applications. The app isn't notarized, so macOS blocks the
first launch: open **System Settings ▸ Privacy & Security** and click **Open Anyway**, or run
`xattr -dr com.apple.quarantine /Applications/Kools.app` once.

**Or build it yourself** (needs Xcode):

```sh
git clone https://github.com/kumudithaperera/Kools.git
cd Kools
scripts/install.sh
```

This builds Kools and copies it to `/Applications`. Run it again to update. A build made
without an Apple Development certificate is signed ad hoc, so macOS asks you to grant
Accessibility again after each update.

Kools lives in the menu bar and has no Dock icon. Features that need Accessibility
(Quit on Close, Cut & Paste, the paste button) ask for it when you switch them on.

## Menu bar icon

The icon is 😆 while nothing needs you. When something does, it is replaced, like a
Live Activity, by a small colored pill with only the icon of the most urgent action:

| Icon | Means | Priority |
|---|---|---|
| 🔒 purple | A feature is on but Accessibility access is missing | 1 |
| ⚠ red | A repo warning: nested repo, iCloud, conflicts | 2 |
| ✎ orange | Uncommitted changes | 3 |
| ↑ blue | Commits to push, or a branch with no upstream | 4 |
| ↓ teal | Commits to pull (as of the last fetch) | 5 |

## Panel

Clicking the icon opens a panel with two tabs for now: **Repo Radar**, and **Tools** for
the small features (Shelf, Quit on Close, Cut & Paste, Clipboard), one card each with its own switch.
Each main feature added later gets its own tab, before Tools: Tools always stays last.
A dot on a tab or card shows it needs something. The panel reopens on the tab you used
last.

**Settings…** (⌘,) opens the settings window. Its **General** tab sets the priority of
both: the order of the tabs, and the order of the cards inside Tools. Drag to reorder,
or hide what you don't use. The panel and the settings window follow the same order.

## Shelf

Drag files, links or text and shake the pointer side to side: a shelf opens beside the
pointer. Drop things on it, then drag them off later. The Shelf card in the Tools tab shows the same
items and opens the floating shelf without a drag. Files stay where they are; the shelf only points to them, and files that
have since moved drop off it. Items are kept until Kools quits. No permissions needed.

## Quit on Close

Pick apps in the Quit on Close card, or turn on All apps and exempt the ones to keep open.
When one of them closes its last window, Kools quits it the normal way, so unsaved documents still ask first. Kools quits an app only when
Accessibility and the window server both report no windows left, so a minimized window
or one on another Space keeps the app open. Finder and system UI are never quit.
Needs Accessibility.

## Cut & Paste

In Finder, ⌘X marks the selected files and ⌘V moves them into the current folder.
⌘X runs Finder's own Copy (pressed through Accessibility, so it works in any language
or keyboard layout) and Kools remembers that copy. ⌘V becomes Finder's ⌥⌘V
(Move Item Here), so Finder handles name conflicts and ⌘Z undoes the move. Copying
anything else in between cancels the cut. Kools changes only ⌘X and ⌘V, and only while
Finder is in front and you're not typing in a text field. Needs Accessibility.

## Clipboard

Copy text and a small clipboard panel opens in the bottom right corner with what you
copied. It hides itself after a few seconds, unless the pointer is on it or you click into
it. The same lists are in the Clipboard card in the Tools tab, and the card opens the
floating panel without a copy. Clicking a row copies it again.

- **History** keeps text for 12 hours after it was copied, then drops it. At most 50 items,
  and nothing over 100 KB. Copying the same text again moves it to the top and restarts its
  12 hours. History lives in memory only, is gone when Kools quits or the feature is
  switched off, and skips copies that password managers mark as secret. Copied files
  aren't recorded.
- **Notes** are short text you type by hand, for things you paste often. They never expire,
  are saved on this Mac until you delete them and can be reordered by dragging. Keep
  passwords out of them.
- **Paste button** is a small button inside the text field you're typing in. It opens the
  history and notes, and clicking one pastes it there (Kools presses ⌘V, then puts your
  previous clipboard back). It isn't shown in password fields, and apps that don't report
  their focused field to Accessibility get no button. Needs Accessibility; the history and
  notes don't.

## Repo Radar

Watches every git repo under `~/Projects` and shows what needs attention.

- Branch, uncommitted file count (`●`), and commits ahead/behind upstream (`↑` `↓`).
- Warns about repos nested inside other repos that are not registered submodules
  (registered submodules get an info note).
- Warns about repos inside iCloud, and counts files iCloud has evicted.
- Lists T3 worktrees from `~/.t3/worktrees` in a collapsed section.

### Actions

In the Repo Radar tab, repos are listed most urgent first. Click one to see its branch,
findings, and these actions:

- **Open in T3 Code**: runs `~/.t3/bin/t3 app <folder>`, starting T3 Code first if needed.
  T3 projects live at the top-level repo, so a T3 worktree opens its main repo and a
  submodule opens its parent. A folder with no T3 project yet gets a new one.
- **Fetch**: `git fetch --quiet` (only for repos with an upstream). The ⬇ button at the
  top of the tab fetches every such repo, four at a time.
- **Remove Worktree…** (empty worktrees only) and **Clean Empty…** next to the
  collapsed T3 worktrees group. A worktree is empty when it has no modified or untracked
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

### Git actions through T3 Code

A repo that needs a commit, push or pull shows those buttons when opened: **Commit**,
**Commit & Push**, **Push** or **Pull**, depending on its state. Each one starts a new
thread in T3 Code (`t3 thread start`) in that repo's project, with a short brief for the
agent, and brings T3 Code to the front so you can follow it:

- **Commit** and **Commit & Push**: you don't write the message. Opening a repo with
  changes asks T3 Code in the background (without bringing it to the front) to read the
  diff and propose one, which fills the message field. Edit it if you like, or press ✨
  for a new one. The commit then goes to that same thread, so one commit uses one
  thread. Committing before the message arrives also works: the agent writes it then.
  Settings ▸ Repo Radar can turn the automatic message off; ✨ still asks on demand.
- **Push**: sets an upstream on `origin` if the branch has none.
- **Pull**: fast-forward only.

Every brief tells the agent never to force push or rewrite history, never to commit
secrets or `.env` files, and to stop and ask instead of merging or rebasing when the
remote has moved on. The agent runs on the project's default model.

### What git can do

Every git call goes through `GitRunner`, which only accepts a fixed set of commands:
`status`, `log -1`, `ls-files`, `rev-parse`, `for-each-ref`, `fetch`, and
`worktree remove`. Kools itself never commits, pushes, pulls, merges, or changes your
branches; those happen only in a T3 Code thread you start with the buttons above.
`fetch` only updates remote-tracking refs, and the only files ever deleted are those
of an empty worktree you confirmed. SSH runs with `BatchMode=yes`, so a fetch that needs a passphrase or an unknown
host key fails with a message instead of hanging.
Scans run with `--no-optional-locks` so they never take `index.lock`.

Scans don't fetch, so ↑↓ counts are relative to the last fetch.

### What gets scanned

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
scripts/bundle.sh        # builds build/Kools.app
open build/Kools.app
```

`bundle.sh` signs with your Apple Development certificate when there is one
(override with `KOOLS_SIGN_IDENTITY`). macOS ties the Accessibility grant to the
signature, so an ad-hoc signed build would need it granted again after every rebuild.

The app icon is also 😆, drawn by `scripts/make-icon.swift` during `bundle.sh`, so the
repo holds no image files.
