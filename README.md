# Kanban board for KOReader

Kanban is a KOReader plugin for tracking projects, ideas, and general tasks with
boards, columns, and cards. Cards are not linked to books.

## Features

- Organize cards into ordered columns and move or reorder columns.
- Add and edit cards with a title and optional notes. Tap a card for a full-screen
  detail view with scrollable notes and a checklist; tap items to toggle them, or
  add, edit and delete items. Its **Actions** button opens Edit, move/reorder and
  Archive actions.
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

## Known issues

- Keyboard-only navigation is not supported. The board handles Back and the
  page-turn keys only.

## Development

Run the test suite from the repository root with:

```sh
busted
```
