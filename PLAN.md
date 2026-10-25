# Kanban board plugin for KOReader: implementation plan

This plan is written for coding agents. Work one phase at a time, meet the phase's
acceptance criteria before you start the next, and keep this file up to date: tick off
tasks, and record any decision that changes the plan under "Decision log".

## Goal

`kanban.koplugin` is a KOReader plugin for kanban boards. A board has ordered columns,
such as "To Do", "Doing" and "Done", and each column holds ordered cards. The board opens
from both the File Manager and the Reader. A card can optionally link to a book, so the
board can also work as a reading tracker.

## Defaults (until the owner says otherwise)

- Scope: a general-purpose board. Linking cards to books is a later phase (phase 6).
- Storage: one global file, `<settings dir>/kanban.lua`, written with `LuaSettings`.
- Sync: none.
- Target: the latest stable KOReader release. Don't add workarounds for older versions.
- Language: Lua 5.1 / LuaJIT. Use only modules that ship with KOReader. No external
  dependencies.

## Repository layout

```
kanban.koplugin/
  _meta.lua         -- plugin metadata (name, fullname, description)
  main.lua          -- WidgetContainer entry point: menus, Dispatcher actions, events
  model.lua         -- pure Lua data model and operations (no KOReader requires)
  storage.lua       -- load/save/migrate through LuaSettings
  boardview.lua     -- full-screen board widget (layout, paging, gestures)
  carddialog.lua    -- card editor and card/column action dialogs
spec/
  model_spec.lua    -- busted unit tests for model.lua
  storage_spec.lua  -- busted tests for storage.lua with a stubbed LuaSettings
README.md
PLAN.md
```

The repository root is not the plugin. To install, copy `kanban.koplugin/` into
`koreader/plugins/`.

## Engineering rules

1. **`model.lua` stays pure.** It must not `require` any KOReader module, so `busted`
   can run it with plain LuaJIT or Lua 5.1. Inject time (`os.time`) and ID generation
   where tests need them to be deterministic.
2. **Only the UI changes data, and only through model functions.** The board view never
   edits tables directly. After every change that succeeds, call `storage.save()`, which
   ends in `flush()`.
3. **Check KOReader APIs against the source**
   (https://github.com/koreader/koreader, `frontend/ui/widget/` and `plugins/`) before
   you use them. Copy patterns from bundled plugins; `plugins/vocabbuilder.koplugin`
   and `plugins/statistics.koplugin` are good references for full-screen widgets.
   Don't invent widget options.
4. **Respect e-ink.** No animation and no drag-and-drop. Use
   `UIManager:setDirty(widget, "ui")` for local changes and `"flashui"` when a page
   changes. Repaint only after a change, never on a timer.
5. **Wrap every user-visible string in `_()`** (`local _ = require("gettext")`).
6. **Never lose data.** Ask for confirmation (`ConfirmBox`) before deleting a column or
   a board. A deleted column's cards are archived, not destroyed. If `kanban.lua` exists
   but can't be read, back it up to `kanban.lua.bak` before writing a new file.
7. Use `logger` (`require("logger")`) for diagnostics. Don't use `print`.

## Data model (schema version 1)

```lua
{
  version = 1,
  current_board = "b1",            -- id of the board opened last
  boards = {                       -- array; order = board list order
    {
      id = "b1",
      name = "My board",
      columns = {                  -- array; order = left-to-right
        { id = "c1", name = "To Do", cards = { --[[card ids in order]] } },
      },
      cards = {                    -- map id -> card
        k1 = {
          id = "k1",
          title = "Read chapter 3", -- required, non-empty after trim
          notes = "",
          created = 1730000000,     -- os.time()
          updated = 1730000000,
          archived = false,
          book = nil,               -- optional absolute file path (phase 6)
        },
      },
      archived = { --[[card ids]] },
      next_id = 2,                 -- per-board counter used to make ids
    },
  },
}
```

Model operations (each returns `true` or `nil, err`): `newState`, `addBoard`,
`renameBoard`, `deleteBoard`, `addColumn(board, name, index?)`, `renameColumn`,
`moveColumn(board, col_id, new_index)`, `deleteColumn` (archives its cards),
`addCard(board, col_id, fields, index?)`, `editCard`,
`moveCard(board, card_id, to_col_id, index?)` (with no index, append),
`archiveCard`, `restoreCard(board, card_id, col_id)`, `findCardByBook(path)`.

Invariants (tests must check these after every operation): each card id appears in
exactly one column's `cards` list or in `archived`, never in two places. Every id in a
list exists in `cards`. Indexes are clamped to the valid range.

## Phases

### Phase 0: Tooling
- [ ] Add `.agents/setup`. It installs `luajit`, `luarocks` and `busted`, and downloads
      the KOReader Linux AppImage (or the emulator build) for manual runs.
- [ ] Add `.busted` so that `busted` from the repo root finds `spec/` and
      `kanban.koplugin/?.lua`.
- **Done when:** `busted` runs and reports 0 tests, without errors.

### Phase 1: Skeleton
- [ ] `_meta.lua` with `name = "kanban"`, `fullname = _("Kanban board")` and a
      description.
- [ ] `main.lua`: `WidgetContainer:extend{ name = "kanban", is_doc_only = false }`.
      `init` calls `self.ui.menu:registerToMainMenu(self)`, and `addToMainMenu` adds
      `menu_items.kanban` (sorted under Tools), which shows an `InfoMessage`.
- **Done when:** the plugin appears in Tools in both File Manager and Reader in the
  emulator, and `crash.log` shows no errors.

### Phase 2: Model and storage
- [ ] Implement `model.lua` as specified above.
- [ ] `storage.lua`: `load()` returns the state, creating a default board with columns
      To Do, Doing and Done on first run. `save(state)` writes it. `migrate(state)` is
      a no-op for v1 but runs on every load.
- [ ] Specs: moving a card within one column and between columns, at index 1, at the
      last index and out of range. Deleting a column archives its cards. Restoring a
      card. Rejecting empty titles. A save/load round trip. A corrupt file gets a `.bak`.
      Check the invariants after every operation.
- **Done when:** `busted` passes and the model has no KOReader `require`s
  (`rg 'require' kanban.koplugin/model.lua` shows nothing KOReader-specific).

### Phase 3: Read-only board view
- [ ] `boardview.lua`: a full-screen `InputContainer` with a `TitleBar` (board name,
      left menu button, close button) and a body: a `HorizontalGroup` of columns. Each
      column is a header and then fixed-height card frames (`FrameContainer` +
      `TextBoxWidget`, titles cut to 3 lines).
- [ ] Columns per screen: `max(1, floor(screen_width / min_col_width))`, capped at 3.
      Swipe east/west moves between column pages. Swipe north/south pages the cards in
      the column under the finger. A footer shows "Columns 1–3 of 5".
- [ ] Rebuild the layout when the screen is rotated (`onScreenResize` /
      `onSetRotationMode`).
- **Done when:** emulator screenshots look right for portrait, landscape, an empty
  column, a column with more cards than fit on one page, and a very long title.
  Screenshots go in `.amp/in/artifacts/`.

### Phase 4: Editing
- [ ] Tap a card to open a `ButtonDialog`: Edit, Move to…, Move up, Move down,
      Archive, Cancel. "Move to…" lists the other columns as buttons.
- [ ] Hold a card for quick-move: the card is highlighted and the next tap on a column
      header moves it there. Tapping anywhere else cancels.
- [ ] Tap a column header for: Add card, Rename, Move left, Move right, Delete.
- [ ] Title bar menu: Add column, Archived cards (a list with Restore), Boards…
      (switch, new, rename, delete).
- [ ] The card editor is a `MultiInputDialog` with title and notes fields.
- **Done when:** in the emulator, each action works, the view repaints correctly, and
  every change is still there after restarting KOReader.

### Phase 5: Integration
- [ ] Register Dispatcher actions in `main.lua`: `kanban_open` ("Open Kanban board")
      and `kanban_add_card` ("Add Kanban card"), with handlers `onKanbanOpen` and
      `onKanbanAddCard`.
- [ ] Reopen the board the user had open last (`current_board`).
- **Done when:** a gesture bound to these actions in Gesture manager works from both
  File Manager and Reader.

### Phase 6: Book linking
- [ ] Reader menu entry and Dispatcher action "Add current book to board". It creates a
      card titled with the book's title (from document props, or the file name if
      there's none) and `book = self.ui.document.file`. If a card for the book already
      exists, it says so instead of adding a duplicate.
- [ ] Linked cards show a book marker and get an "Open book" action
      (`ReaderUI:showReader(path)`; first check that the file still exists).
- [ ] Optional setting, off by default, "Auto-move linked books": opening a book moves
      its card to a configurable "reading" column, and `onEndOfBook` moves it to a
      configurable "done" column.
- [ ] Optional: show reading progress on linked cards from `DocSettings`
      (`percent_finished`).
- **Done when:** in the emulator, you can add the current book, open it from its card
  and, with auto-move on, see the card move on open and at the end of the book.

### Phase 7: Device pass
- [ ] Test on at least one real e-ink device. Check refresh and ghosting, that tap
      targets are at least about 8 mm, and keyboard-only navigation on devices with
      buttons (`FocusManager` / key events for the board view).
- **Done when:** the problems found are fixed or recorded as known issues in README.

### Phase 8: Release
- [ ] README: features, installation, screenshots, data file location.
- [ ] A script that zips `kanban.koplugin/` into `kanban.koplugin.zip`.
- [ ] Optional: export a board to Markdown in the home folder.
- **Done when:** installing from the zip on a clean KOReader works.

## How to verify

- Unit tests: run `busted` from the repo root. It must pass before every commit.
- Manual: start KOReader (the AppImage or `./kodev run`) with the plugin linked or
  copied into its `plugins/` directory, then follow the phase's acceptance criteria.
  Check `crash.log` afterwards.
- For any UI change, capture and inspect screenshots of every affected state.

## Decision log

- (empty — add entries as `YYYY-MM-DD: decision — reason`)
