# Kanban board for KOReader

Kanban is a KOReader plugin for tracking projects, ideas, and general tasks with
boards, columns, and cards. Cards are not linked to books.

## Features

- Organize cards into ordered columns and move or reorder columns.
- Add and edit cards with a title and optional notes. Tap a card for a full-screen
  detail view with scrollable notes and a checklist; tap items to toggle them, or
  add, edit and delete items. Its **Actions** button opens Edit, move/reorder and
  Archive actions.
- Create, rename, and delete board labels from **☰ → Labels…**. Assign multiple
  labels with **Labels…** in the new/edit card dialog. Labels appear as text badges
  on cards and in the detail view. Use **☰ → Filter by label…** to show matching
  cards, or **All cards** to clear the filter. Filters reset when switching boards.
  Labels are saved locally and included in Markdown exports and imports.
- Connect a board to GitHub from **☰ → GitHub issues…**. Choose which labels
  upload, preview matching cards, and publish them as a batch of GitHub issues.
  Published cards retain their issue links and are excluded from later batches.
- Hold a card and slide it: a bar shows where it will land, and sliding onto a
  column tab moves it to that column. Or hold, lift, then tap a gap between
  cards, a column header or a tab. Lift where you picked it up to cancel. Turn
  dragging off with **Tools → Kanban board → Drag to move**.
- Undo the last change: moves, archiving, deleting a column and restoring show
  an **Undo** button for a few seconds, and the board menu (☰) always has
  **Undo: <change>**, even after a restart. The card dialog also has
  previous/next column buttons and Move to top/bottom.
- Choose **Select cards** in the board menu (☰), tap cards across pages, then
  **Move to…** or **Archive** the selection. One **Undo** restores the whole batch;
  **Cancel** leaves cards unchanged. Hold and drag are disabled while selecting.
- Cards show small markers: ¶ when they have notes, ☑ done/total for a
  checklist, and how many days they've been in their column.
- Pin one card as **Now** per board; it appears in a bold bar above the columns
  and opens its detail view when tapped.
- Collapse a column (column dialog) into a narrow strip to fit more columns on
  screen; tap the strip to expand it.
- Restore archived cards to a selected column. Deleting a column archives its
  cards rather than deleting them.
- Create, switch between, rename, and delete multiple boards. Tap the board name
  (marked ▼) in the title bar to open the Boards dialog.
- Export the current board to Markdown in a folder you choose (it remembers the
  last one; the first time it starts in KOReader's home folder), or import a
  Markdown file as a new board. Cards, notes, checklists, and archived cards are
  included.
- Open the board from **Tools → Kanban board → Open board** in both the File
  Manager and Reader, or bind any of these actions in Gesture manager:
  - **Open Kanban board**
  - **Add Kanban card** (opens the card editor for the first column of the
    currently selected board)
  - **Kanban: Today**
- **Today** (board menu ☰, or the gesture above) lists the cards in every
  board's in-progress column, grouped by board. The in-progress column is the
  second-to-last column unless you pick another in its column dialog.
- **Show board on sleep screen** (Tools → Kanban board) shows the current board
  as the sleep screen. Turning it off restores your previous sleep screen
  settings.
- Board layout adapts when the screen rotates. On devices without an
  accelerometer, **Rotate screen** in the board menu (☰) switches between
  portrait and landscape. Swipe to navigate column pages
  and card pages; the page-turn keys move between column pages.

## Bookshelf module

With [Bookshelf](https://github.com/AndyHazz/bookshelf.koplugin) 6.1 or newer
enabled, Kanban also provides a **Kanban board** micro-module. Add it through
Bookshelf's module picker and choose a board. Each instance remembers its own
board, so you can add several cards for different boards.

The module shows the board name, its pinned **Now** card, and up to three tasks
from its in-progress column (the same column used by **Today**). Tap to open
that board. Use **Module settings…** from the card's long-press menu to choose
another board. If a chosen board is deleted, tap the card to choose again.
Closing a board refreshes the module. Everything works offline; Bookshelf is
optional and the module is included in the normal plugin zip.

## Screenshots

| Board in portrait | Board in landscape |
| --- | --- |
| ![Kanban board in portrait](docs/screenshots/board-portrait.png) | ![Kanban board in landscape](docs/screenshots/board-landscape.png) |

| Card actions | Quick-move a card |
| --- | --- |
| ![Card actions](docs/screenshots/card-actions.png) | ![Quick-move a card](docs/screenshots/quick-move.png) |

![Board menu](docs/screenshots/board-menu.png)

## Installation

From the repository root, run `./package.sh` to build `kanban.koplugin.zip`.
The zip contains the `kanban.koplugin/` folder. Unzip it into KOReader's
`plugins/` folder, or copy the `kanban.koplugin/` folder there, then restart
KOReader.

## Data file

Board data is stored in `kanban.lua` in KOReader's settings directory, returned
by `DataStorage:getSettingsDir()` (for example, `koreader/settings/kanban.lua`).
If the data file is corrupt, the plugin keeps a backup as `kanban.lua.bak`.

## GitHub issue uploads

1. Open **☰ → GitHub issues…** and enter a repository as `owner/repository`.
2. Open **Labels to upload** and check any labels you want, such as **Bug** and
   **Feature**. A card with any checked label is eligible. A card with both creates
   one issue, with both labels. Unchecked labels stay local.
3. In **GitHub label mappings…**, map those board labels to existing GitHub label
   names, such as `Bug → bug` and `Feature → enhancement`. Enabling a label starts
   with its current board name; clear a mapping to upload without that issue label.
4. Set a GitHub fine-grained personal access token for that repository with
   **Issues: read and write** permission. Enter the token on the device.
5. Open **Preview batch…** while offline or online. Tap a card to review its issue
   contents. **Publish batch → Publish** connects and uploads the batch. Archived
   cards and cards already published to that repository are excluded.

Titles become issue titles; notes and checklists become the issue body. Issue
links appear in card details. This version creates issues on github.com; it does
not synchronize later edits or GitHub status back to the board. Changing a label
name does not change its configured GitHub mapping.

Each success is recorded before the next card starts. The batch stops on an error;
retry from a new preview to continue with remaining cards. If a request was
interrupted after GitHub may have accepted it, retry checks recent issues for a
hidden card marker. If the result remains uncertain, the plugin leaves it pending
rather than automatically creating a second issue. Keep that marker in the GitHub
issue body until recovery is complete.

The token and upload journal are stored locally, unencrypted, in
`kanban-github.lua` in KOReader's settings directory. Keep that file with your
board backups; undo and Markdown exports do not contain it. **Forget GitHub token**
removes the saved token while preserving issue history. Markdown imports create
new boards and do not restore GitHub connections or published issue links.

## Known issues

- Keyboard-only navigation is not supported. The board handles Back and the
  page-turn keys only.

## Development

Run the test suite from the repository root with:

```sh
busted
```

For a repeatable emulator smoke pass before device testing, run:

```sh
.agents/smoke                              # emulator build, all checks
.agents/smoke --build desktop --skip-sleep  # desktop build, no F2 sleep check
.agents/smoke --only board-tools,gestures --keep
```

It uses `.agents/setup`, Xvfb, an isolated KO_HOME, httpinspector and X11 input to
exercise board open, gestures/Today, card checklist, drag/edge paging, bulk
archive/undo, Markdown round-trip and sleep-screen resume, failing on KOReader
errors or missing UI states. Artifacts (screenshots/logs) go to
`.agents/artifacts/smoke`. Physical e-ink checks such as ghosting, tap-target size
and real-device responsiveness remain manual.
With a Kanban board open in an English-language KOReader test instance and
HTTP inspector enabled, run the real-widget labels integration checks with:

```sh
curl 'http://127.0.0.1:8080/koreader/globals/dofile/%22/workspace/kanban.koplugin/.agents/test-labels.lua%22'
```

Adjust the script path for your checkout. The script temporarily replaces the
open board with test data and restores the original state when it finishes.
It covers label dialogs, editor save/cancel, filtering, paging, drag destination
styling, persistence, Markdown, deletion, and undo.

The standalone Bookshelf module interaction checks run without KOReader or
Bookshelf installed:

```sh
luajit spec/bookshelf_module_test.lua
```

The GitHub widget checks use simulated responses and never create real issues.
The settings checks use a temporary directory and fake tokens:

```sh
curl 'http://127.0.0.1:8080/koreader/globals/dofile/%22/workspace/kanban.koplugin/.agents/test-github.lua%22'
curl 'http://127.0.0.1:8080/koreader/globals/dofile/%22/workspace/kanban.koplugin/.agents/test-github-store.lua%22'
```

Run the standalone HTTP transport checks with:

```sh
luajit spec/github_transport_test.lua
```
