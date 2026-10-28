# Kanban board plugin for KOReader: implementation plan

This plan is written for coding agents. Work one phase at a time, meet the phase's
acceptance criteria before you start the next, and keep this file up to date: tick off
tasks, and record any decision that changes the plan under "Decision log".

## Goal

`kanban.koplugin` is a KOReader plugin for kanban boards. A board has ordered columns,
such as "To Do", "Doing" and "Done", and each column holds ordered cards. The board opens
from both the File Manager and the Reader. It is meant for tracking projects, feature
ideas and general productivity tasks; cards are not linked to books.

## Defaults (until the owner says otherwise)

- Scope: a general-purpose board for projects and tasks. No book linking.
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
4. **Respect e-ink.** No animation. The only drag-and-drop is phase 10's snap-preview
   drag: a drop bar that jumps between gaps, never a card that follows the finger. Use
   `UIManager:setDirty(widget, "ui")` for local changes and `"flashui"` when a page
   changes. Repaint only after a change, never on a timer.
5. **Wrap every user-visible string in `_()`** (`local _ = require("gettext")`).
6. **Never lose data.** Ask for confirmation (`ConfirmBox`) before deleting a column or
   a board. A deleted column's cards are archived, not destroyed. If `kanban.lua` exists
   but can't be read, back it up to `kanban.lua.bak` before writing a new file.
7. Use `logger` (`require("logger")`) for diagnostics. Don't use `print`.

## Data model (schema version 2)

```lua
{
  version = 2,
  current_board = "b1",            -- id of the board opened last
  boards = {                       -- array; order = board list order
    {
      id = "b1",
      name = "My board",
      columns = {                  -- array; order = left-to-right
        { id = "c1", name = "To Do", cards = { --[[card ids in order]] }, collapsed = false },
      },
      cards = {                    -- map id -> card
        k1 = {
          id = "k1",
          title = "Read chapter 3", -- required, non-empty after trim
          notes = "",
          created = 1730000000,     -- os.time()
          updated = 1730000000,
          moved = 1730000000,       -- last time the card changed columns
          archived = false,
          checklist = { { text = "Read the chapter", done = false } },
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
`addCard(board, col_id, fields, index?, clock?)`, `editCard`,
`moveCard(board, card_id, to_col_id, index?, clock?)` (with no index, append),
`addChecklistItem`, `editChecklistItem`, `toggleChecklistItem`, `deleteChecklistItem`,
`moveChecklistItem`, `setColumnCollapsed`, `archiveCard`, and
`restoreCard(board, card_id, col_id)`.

Invariants (tests must check these after every operation): each card id appears in
exactly one column's `cards` list or in `archived`, never in two places. Every id in a
list exists in `cards`. Indexes are clamped to the valid range.

## Phases

### Phase 0: Tooling
- [x] Add `.agents/setup`. It installs `luajit`, `luarocks` and `busted`.
      KOReader Linux AppImage (or emulator build) download is deferred to phase 1.
- [x] Add `.busted` so that `busted` from the repo root finds `spec/` and
      `kanban.koplugin/?.lua`.
- **Done when:** `busted` runs without errors.

### Phase 1: Skeleton
- [x] `_meta.lua` with `fullname = _("Kanban board")` and a description. (No `name`
      field; current KOReader ignores it and logs a deprecation warning.)
- [x] `main.lua`: `WidgetContainer:extend{ name = "kanban", is_doc_only = false }`.
      `init` calls `self.ui.menu:registerToMainMenu(self)`, and `addToMainMenu` adds
      `menu_items.kanban` (sorted under Tools), which shows an `InfoMessage`.
- [x] Extend `.agents/setup` to download the latest stable Linux x86_64 AppImage
      into `${XDG_CACHE_HOME:-$HOME/.cache}/koreader`, extract it without FUSE, and
      reuse the download and extraction on subsequent runs.
- **Done when:** the plugin appears in Tools in both File Manager and Reader in the
  emulator, and `crash.log` shows no errors.
- **Verified (2026-10-25, KOReader v2026.07.1):** Tools → Kanban board appears
  and opens the placeholder message in both File Manager and Reader. No errors or
  plugin failures in `~/.config/koreader/crash.log`. Inspected captures:
  `.amp/in/artifacts/phase1-filemanager-tools.png`,
  `.amp/in/artifacts/phase1-reader-tools.png`, and corresponding `*-message.png`.
  `bash -n .agents/setup`, Lua syntax checks, and `busted` pass. An empty-cache
  setup run took 1.2 seconds; its repeat took 0.1 seconds without downloading or
  extracting again.
- **Orb launch:** run `amp orb desktop ensure`, link the repo's `kanban.koplugin`
  into `~/.cache/koreader/current/usr/lib/koreader/plugins/`, then run:
  `amp orb service start koreader --command 'source /home/user/.cache/amp/desktop/environment; export SDL_VIDEODRIVER=x11; exec /home/user/.cache/koreader/current/AppRun > /home/user/.config/koreader/crash.log 2>&1'`.
  Append a book path to `AppRun` to start in Reader. Settings live in
  `~/.config/koreader`; the running app is visible in the orb Desktop tab.

### Phase 2: Model and storage
- [x] Implement `model.lua` as specified above.
- [x] `storage.lua`: `load()` returns the state, creating a default board with columns
      To Do, Doing and Done on first run. `save(state)` writes it. `migrate(state)` is
      a no-op for v1 but runs on every load.
- [x] Specs: moving a card within one column and between columns, at index 1, at the
      last index and out of range. Deleting a column archives its cards. Restoring a
      card. Rejecting empty titles. A save/load round trip. A corrupt file gets a `.bak`.
      Check the invariants after every operation.
- **Done when:** `busted` passes and the model has no KOReader `require`s
  (`rg 'require' kanban.koplugin/model.lua` shows nothing KOReader-specific).

### Phase 3: Read-only board view
- [x] `boardview.lua`: a full-screen `InputContainer` with a `TitleBar` (board name,
      left menu button, close button) and a body: a `HorizontalGroup` of columns. Each
      column is a header and then fixed-height card frames (`FrameContainer` +
      `TextBoxWidget`, titles cut to 3 lines).
- [x] Columns per screen: `max(1, floor(screen_width / min_col_width))`, capped at 3.
      Swipe east/west moves between column pages. Swipe north/south pages the cards in
      the column under the finger. A footer shows "‹ Columns 1–3 of 5 ›"; the chevrons are tappable
      and dimmed when there are no more columns that way.
- [x] Rebuild the layout when the screen is rotated (`onScreenResize` /
      `onSetRotationMode`).
- **Done when:** emulator screenshots look right for portrait, landscape, an empty
  column, a column with more cards than fit on one page, and a very long title.
  Screenshots go in `.amp/in/artifacts/`.
- **Verified (2026-10-25, KOReader v2026.07.1):** Tools → Kanban board opens the
  board from File Manager and Reader, loading the state with `storage.lua`. With a
  seeded 5-column board (14 cards in Ideas, empty Blocked, one very long title),
  inspected captures: `.amp/in/artifacts/phase3-portrait.png` (600×800, 2 columns,
  6 cards per column), `phase3-landscape.png` (800×600, 3 columns, 4 cards),
  `phase3-empty-column.png`, `phase3-card-paging.png` (Ideas 1–6, 7–12, 13–14 while
  To Do stays put) and `phase3-long-title.png` (cut to 3 lines with "…"). Swipes,
  window resize (`ScreenResize`) and `SetRotationMode` 1 → 0 (sent through
  httpinspector, from both File Manager and Reader) rebuild the layout, and the
  underlying File Manager / Reader is laid out correctly after closing. No errors in
  `crash.log`. `busted` passes.
- **Orb capture notes:** the Desktop output is 1280×720, which clips a 600×800 window
  (KOReader then resizes itself to 600×693). Run `wlr-randr --output HEADLESS-1
  --custom-mode 1280x960` first, and drive the emulator with `xdotool` (a mouse drag is
  a swipe) and `import -window`. Captures taken in landscape show the unrotated
  framebuffer; rotate them 90°. Gestures and hotkeys don't reach File Manager while the
  board covers it, so send rotation with httpinspector
  (`"httpinspector": {autostart = true}` in `settings.reader.lua`, then
  `curl localhost:8080/koreader/event/SetRotationMode/1`).

### Phase 4: Editing
- [x] Tap a card to open a `ButtonDialog`: Edit, Move to…, Move up, Move down,
      Archive, Cancel. "Move to…" lists the other columns as buttons.
- [x] Hold a card for quick-move: the card is highlighted and the next tap on a column
      header moves it there. Tapping anywhere else cancels.
- [x] Tap a column header for: Add card, Rename, Move left, Move right, Delete.
- [x] Title bar menu: Add column, Archived cards (a list with Restore). Board switching
      (switch, new, rename, delete) opens from tapping the title (see decision log).
- [x] The card editor is a `MultiInputDialog` with title and notes fields.
- **Done when:** in the emulator, each action works, the view repaints correctly, and
  every change is still there after restarting KOReader.
- **Verified (2026-10-25, KOReader v2026.07.1, 600×800):** on a seeded 4-column
  board, every action was run in the emulator: card Edit (multi-line notes), Move to…
  (to a column on another page), Move up/down, Archive; quick-move drop onto a header
  on another column page and cancel by tapping elsewhere; column Add card, Rename,
  Move left/right, Delete (with confirmation, cards archived); ☰ Add column, Archived
  cards → Restore into a chosen column, Boards… switch/new/rename/delete (with
  confirmation). Empty titles and names are refused with a message. After
  `amp orb service restart koreader` the board, column order, edits, archive and the
  last selected board (`current_board`) were all still there. No errors in
  `crash.log`; `busted` passes (13 tests). Inspected captures in
  `.amp/in/artifacts/`: `phase4-card-actions.png`, `phase4-move-to.png`,
  `phase4-quick-move.png`, `phase4-card-editor.png`, `phase4-column-actions.png`,
  `phase4-delete-column-confirm.png`, `phase4-board-menu.png`, `phase4-archive.png`,
  `phase4-boards.png`.
- **Orb notes:** the plugin's data file is `~/.config/koreader/settings/kanban.lua`
  (`DataStorage:getSettingsDir()`), not `~/.config/koreader/kanban.lua`. httpinspector
  autostart needs an explicit `port` in its settings table, or KOReader crashes on start.
  Tools → Kanban board is on page 2 of the Tools tab, and the menu reopens on the last
  tab/page, so capture before each tap instead of replaying fixed coordinates.

### Phase 5: Integration
- [x] Register Dispatcher actions in `main.lua`: `kanban_open` ("Open Kanban board")
      and `kanban_add_card` ("Add Kanban card"), with handlers `onKanbanOpen` and
      `onKanbanAddCard`.
- [x] Reopen the board the user had open last (`current_board`). Already done by
      phase 4, which saves `current_board` when switching boards.
- **Done when:** a gesture bound to these actions in Gesture manager works from both
  File Manager and Reader.
- **Verified (2026-10-25, KOReader v2026.07.1):** with `kanban_open` bound to
  `tap_left_bottom_corner` and `kanban_add_card` to `tap_right_bottom_corner` in
  `settings/gestures.lua` (both `gesture_fm` and `gesture_reader`), each gesture opened
  the board or the new-card editor in File Manager and in Reader, and cards added
  through the editor were saved and appeared in the first column. No errors in
  `crash.log`. Captures: `.amp/in/artifacts/phase5-open-fm.png`,
  `phase5-add-card-reader.png`, `phase5-open-reader.png`.

### Phase 6: Device pass
- [x] Test on at least one real e-ink device. Check refresh and ghosting, that tap
      targets are at least about 8 mm, and keyboard-only navigation on devices with
      buttons (`FocusManager` / key events for the board view).
- **Done when:** the problems found are fixed or recorded as known issues in README.
- **Done (2026-10-25):** the owner tested the plugin on their e-ink device. Two
  problems were found and fixed in `651e2fa`: ghosting when the board opens (now a
  full refresh), and the column dialog closing after every move (now it stays open).
  Keyboard-only navigation was not tested; the board only handles Back and the
  page-turn keys. Record that as a known issue in the README.

### Phase 7: Release
- [x] README: features, installation, screenshots, data file location.
- [x] A script that zips `kanban.koplugin/` into `kanban.koplugin.zip` (`package.sh`).
- [ ] Optional: export a board to Markdown in the home folder. (Moved to phase 14.)
- **Done when:** installing from the zip on a clean KOReader works.
- **Verified (2026-10-26, KOReader v2026.07.1, 600×800):** `./package.sh` produced
  a valid zip. Extracted it into a brand-new, empty HOME with no repository symlink;
  Tools → Kanban board opened the default board with To Do, Doing and Done. Rechecked
  the title-bar Boards dialog and board switching, the ☰ menu entries (Add column,
  Archived cards, Rotate screen; no Boards…), and portrait → landscape → portrait
  rotation with the columns laid out correctly. No errors, failures or crashes in
  `crash.log`; `busted` passes (13 tests). Inspected captures:
  `.amp/in/artifacts/verify-board-menu.png`, `verify-boards-dialog.png`,
  `verify-board-portrait.png`, `verify-board-landscape.png`,
  `verify-clean-install.png` and `verify-clean-install-done.png`.

### Phase 8: Layout
- [x] C1: size each card to its title (1–3 lines, still cut at 3 with "…"). Fill each
      column page with as many cards as fit; card paging (`card_start`, swipe
      north/south, "Cards 1–10 of 14") follows the variable heights.
- [x] C2: replace the "‹ Columns 1–2 of 4 ›" footer with a row of column tabs showing
      each column's name and card count (`Ideas 14`). The columns on screen are inverted
      (black fill, white text). Tapping a tab shows the page holding that column. Long
      names are cut so every tab fits; if the tabs can't fit, keep the chevrons at the
      row's ends.
- **Done when:** emulator captures at 600×800, 1264×1680 portrait and 1680×1264
  landscape show more cards per column than before (target: about 10 on 7" portrait
  with the seeded board), tabs for 4 and 7 columns, and a column with a 3-line title.
- **Verified (2026-10-26, KOReader v2026.07.1):** after the pager-spacing fix,
  inspected `.amp/in/artifacts/phase8-600x800.png`: the populated Ideas column has a
  three-line title, the pager reads “Cards 1–9 of 14”, and the last card no longer
  overlaps it. Reused the pre-rebase captures at 1264×1680 portrait and 1680×1264
  landscape, as requested: `phase8-1264x1680-portrait.png` (all 14 cards fit) and
  `phase8-1680x1264-landscape.png` (3 columns, 6 of 14 cards on page 1, seven tabs and
  three-line title). Swiped to cards 11–14 (`phase8-card-paging-11-14.png`); tapped
  tabs on 4- and 7-column boards (`phase8-tabs-4-columns.png` and
  `phase8-tabs-long-name.png`, with the long label ellipsized without hiding its
  count). In the emulator, ☰ → Today → Idea 11 opened the Ideas column at
  “Cards 10–14 of 14” with Idea 11's action dialog (`phase8-today-card-page.png`).
  Card and column dialogs, header quick-move, title-bar board switching, Rotate
  screen, and rotation rebuild were also verified. No errors or crashes in
  `crash.log`; `busted` passes (24 tests).

### Phase 9: Fewer taps
- [x] A1: the card dialog gets "← <previous column>" and "<next column> →" buttons
      (disabled at the ends; next column emphasized). "Move to…" stays.
- [x] A2: a "+ Add card" row under the last card of every column (dashed or
      otherwise clearly different border),
      opening the card editor for that column. On a column page that doesn't show the
      last card, it isn't shown.
- [x] A4: Move up/down keep the card dialog open (like the column dialog); add "Move to
      top" and "Move to bottom".
- [x] A3: undo the last change. `commit()` keeps a deep copy of the board before each
      change; after move, archive, delete column and restore, show a short message with
      an Undo button. Within-column reorders show the message and button in the open
      card dialog. Undo restores the copy, saves, and repaints. One level only.
- **Done when:** each action works in the emulator, Undo restores the previous board
  and survives a restart, and model specs cover any new Model functions.
- **Verified A2 (2026-10-26, KOReader v2026.07.1 AppImage, 600×800):** checked an
  empty column, a column ending mid-page, a second-page last card, and a full first
  page where reserving the row moves the final card to page two. Adding cards from
  the row saved and displayed them. Holding the row did not quick-move. After phase
  10 was integrated, tapping the row with a card picked up canceled pickup without
  opening the editor; dragging to the column-end gap appended the card above the row.
  `busted` passes (24 tests); no ERROR/FATAL/CRASH entries in `crash.log`. Inspected captures:
  `.amp/in/artifacts/phase9-addrow-empty.png`, `phase9-addrow-second-page.png`,
  `phase9-addrow-overflow-page1.png`, `phase9-addrow-overflow-page2.png`,
  `phase9-addrow-hold.png`, `phase9-addrow-quickmove.png`,
  `phase9-addrow-picked-up-row.png`, and `phase9-addrow-end-drop.png`.
- **Verified (2026-10-26, KOReader v2026.07.1, 600×800):** A1 previous/next shortcuts
  and Move to… (Doing and Done) work, with the endpoint actions disabled. A4 Move
  up/down/top/bottom reorder cards and leave the card dialog open with an inline Undo
  row; repeated moves remain available, and Undo restores the previous order without
  closing the dialog. A3 Undo restores after move, archive, column deletion and
  restore; the persisted reorder Undo prompt survived restart, then restored the board
  and cleared the undo record. `busted` passes (25 tests). The current `crash.log`
  contains no ERROR/FATAL/CRASH entries; earlier pre-fix tracebacks were recorded in
  the prior session log. Inspected
  captures in `.amp/in/artifacts/`: `phase9-card-dialog-final.png`,
  `phase9-reorder-inline-undo.png`, `phase9-inline-undo-restored.png`,
  `phase9-reorder-repeated-final.png`, `phase9-reorder-repeated-undo-final.png`,
  `phase9-move-to-top-inline*.png`, and `phase9-undo-restart-current-*.png`. Archive,
  delete-column, restore, adjacent-column and Move to… captures use the patterns
  `phase9-latest-archive-*`, `phase9-latest-delete-column-*`, `phase9-latest-restore-*`,
  `phase9-latest-previous-*`, `phase9-latest-next-*`, and `phase9-latest-move-to-*`.
  The full interaction matrix above was run before the fast-forward. After updating to
  `origin/main` (`f57fb93`), manually reopened and inspected the latest board and card
  dialog in `phase9-final-board.png` and `phase9-final-card-dialog.png`; the startup
  helper did not expose httpinspector, so the post-fast-forward interaction pass could
  not be completed through its automation.

### Phase 10: Moving cards
- [x] B2: after hold-and-lift (today's quick-move), tapping a gap between cards drops
      the card there, and tapping a tab drops it at the end of that column. Headers keep
      working. Holding works on a one-column board too (reordering).
- [x] B1: drag, behind a "Drag to move" setting (default on). Hold a card, then slide:
      `hold_pan` events move a thick drop bar between gaps; the bar is redrawn only when
      it changes gap, with `"a2"` refresh on the old and new bar regions. Sliding onto a
      tab inverts it. `hold_release` drops through `commit()`, followed by one `"ui"`
      refresh. Lifting where the card was picked up cancels; lifting without moving
      falls back to B2. Movement under `PAN_THRESHOLD` doesn't start a drag.
- **Done when:** in the emulator, drag within a column, to another column on screen and
  to a tab on another page all work, and cancel leaves the board unchanged. The owner
  tries it on their device and records how responsive it is.
- **Verified (2026-10-26, KOReader v2026.07.1 Emulator, 600×800):** real mouse
  hold/lift/tap reordered within a column, inserted between another column's cards,
  appended through a tab, and filled an empty column. Drag reordered down and up,
  inserted into the other visible column, and appended through the Done tab while
  that column was on another page. Returning to the pickup card before lifting
  cancelled with byte-identical saved state; lifting without moving (also with a
  6×5 px wobble below the detector threshold) stayed selected for tap-to-drop.
  With Drag to move off, sliding did not move the card or request any drag refresh;
  header quick-move still appended it. The off setting survived restarting KOReader.
  A one-column board supported both tap-to-drop and upward drag; its own header
  cancelled without saving. The setting was restored to on through the menu.
  `busted`: 24 successes; LuaJIT syntax checks pass; no errors or tracebacks in the
  emulator's redirected `crash.log`. No Model functions or model specs were added.
  Inspected captures in `.amp/in/artifacts/`: `phase10-before.png`,
  `phase10-tap-{same-column,other-column,tab}.png`,
  `phase10-drag-{bar,same-column,other-bar,other-column,tab-preview,tab}.png`,
  `phase10-cancel-origin.png`, `phase10-hold-lift{,-drop}.png`,
  `phase10-empty-column-drop.png`, `phase10-setting-{on,off}.png`,
  `phase10-drag-disabled.png`, `phase10-header-quick-move.png`,
  `phase10-off-after-restart.png`, and `phase10-one-column-{tap,preview,drag}.png`.
  Recording was attempted once but X11 capture was black; used these inspected
  before/during/after captures instead. `phase10-refresh-regions.log` records only
  the old/new 282×6 bars (or the hovered tab) receiving `a2` during motion, no refresh
  for movement in the same gap, and one `ui` refresh on release. Test board/options
  files were removed from the emulator settings afterward. **The owner still needs
  to try drag on an e-ink device and report responsiveness/ghosting.**

### Phase 11: Card detail (data model version 2)
- [x] Schema version 2: cards gain `checklist = { { text, done } }`, `moved`; columns
      gain `collapsed`. `Storage.migrate` upgrades version 1 files; specs cover the
      migration and a round trip.
- [x] E1: tapping a card opens a full-screen card view: title, all notes (scrollable),
      the checklist (tap an item to tick it, add/edit/delete items), and the card
      actions from phase 9.
- **Verified E1 (2026-10-27, KOReader v2026.07.1 AppImage, 600×800):** a long-notes
  card scrolled through its notes and checklist; tapping toggled an item, and add,
  edit and delete all saved. A card without notes or checklist showed both empty
  states. Actions moved a card to another column and archived a card (closing the
  detail view). Today opened the same card view. After restarting KOReader, the
  checklist edits remained. `busted` passes (25 tests); LuaJIT syntax checks pass;
  no ERROR/FATAL/CRASH/Traceback entries in `crash.log`. Inspected captures:
  `.amp/in/artifacts/phase11-cardview-long-notes.png`,
  `phase11-cardview-checklist.png`, `phase11-cardview-checklist-toggled.png`,
  `phase11-cardview-checklist-added.png`, `phase11-cardview-checklist-edited.png`,
  `phase11-cardview-checklist-deleted.png`,
  `phase11-cardview-checklist-restarted.png`,
  `phase11-cardview-no-notes.png`, `phase11-cardview-action-moved.png`,
  `phase11-cardview-action-archived.png`, and `phase11-cardview-from-today.png`.
- [x] C4: small markers on board cards: ¶ when it has notes, ☑ done/total for the
      checklist, and days in the current column (needs a `moved` timestamp, set by
      `addCard`/`moveCard`).
- [x] C6: collapse a column (column dialog) into a narrow strip with its name and count;
      tap it to expand. Collapsed columns take less room, so more columns fit a page.
- **Verified C4/C6 and CardView integration (2026-10-27, KOReader v2026.07.1 AppImage):**
  inspected 600×800 and 1680×1264 landscape captures for notes-only, checklist-only,
  days-only, combined and marker-free cards. A 3-day-old `moved` value shows `3d`;
  cards younger than one complete day omit the age marker. Collapsing Blocked through
  its column dialog produced a counted strip between expanded columns; tapping the
  strip expanded it again. The mixed-width page showed three columns at 600×800 and
  four at 1680×1264. Hold-and-lift then tapping the strip, dragging onto the strip,
  and dragging onto its tab each appended a card while preserving `collapsed = true`.
  After restarting KOReader, the collapsed flag and appended cards remained saved.
  Tapping a checklist-marked card opened CardView; checking the remaining item changed
  its board marker from `☑ 1/2` to `☑ 2/2` after closing. `busted` passes (26 tests),
  LuaJIT syntax checks pass, and `crash.log` has no ERROR/FATAL/CRASH/Traceback entries.
  Inspected captures: `.amp/in/artifacts/phase11-markers-600x800.png`,
  `phase11-markers-1680x1264.png`, `phase11-collapse-600x800.png`,
  `phase11-collapse-expanded-600x800.png`, `phase11-collapse-1680x1264.png`,
  `phase11-collapse-tab-drag.png`, `phase11-collapse-restart-600x800.png`,
  `phase11-collapse-restart-1680x1264.png`,
  `phase11-cardview-checklist.png`, `phase11-cardview-checklist-toggled.png`, and
  `phase11-cardview-marker-updated.png`.
- **Done when:** a version 1 file loads and upgrades without losing data, and captures
  show the card view, markers and a collapsed column.

### Phase 12: Bulk actions and faster repaints
- [x] A8: Select mode (board menu): tapping cards toggles them; a bar offers Move to…,
      Archive and Cancel for the selection.
- [x] D4: repaint only the widgets a change touched (the affected columns, the tabs)
      with `setDirty` on their regions, instead of rebuilding and refreshing the whole
      board. Page changes still use `"flashui"`.
- **Done when:** select-and-move/archive works, and moving a card within one column
  refreshes only that column (checked by logging the refreshed regions).
- **Verified (2026-10-27, KOReader v2026.07.1 Emulator, 600×800):** selected cards
  across column/card pages, toggled selection, moved and archived batches, and used
  one Undo after each; Cancel and hold/drag suppression worked. Debug logs show a
  within-column move requesting only c1 (10,51,282,708) and tabs (0,760,600,40),
  and a between-column move adding only c2 (307,51,282,708). An unchanged column's
  widget identity was retained. Page swipes still requested full-board `flashui`
  (0,0,600,800). Edits, drag/drop (including `a2` preview), undo and collapse/expand
  left a capture pixel-identical to a fresh restart of the same saved state
  (`magick compare -metric AE`: 0). Card detail checklist commits, Today → card
  detail, and the off-screen sleep renderer worked; the sleep option was disabled
  afterwards. `busted`: 27 successes; LuaJIT syntax checks pass; final crash.log has
  no ERROR/FATAL/CRASH/Traceback entries. The initial selection-bar gettext shadowing
  bug was fixed before the successful pass. X11 recording was black (one attempt),
  so inspected screenshots are the visual evidence. Captures and refresh log:
  `.amp/in/artifacts/phase12-*.png`, `phase12-refresh-regions.log`.

### Phase 13: Now card and sleep screen
- [x] D2: pin one card as "Now" (card actions). It shows above the columns in bold;
      unpin from the same place. One per board.
- [x] D1: opt-in "Show board on sleep screen" setting. On suspend, render the current
      board (or the Now card, if set) to a PNG in the settings dir and point the
      screensaver at it, the way Screenshoter's "Set as book cover" does
      (`screensaver_type` / `screensaver_document_cover`). Turning it off restores the
      user's previous screensaver settings.
- **Verified (2026-10-26, KOReader v2026.07.1 Emulator, 600×800):** with D1 enabled,
  F2 suspend from File Manager showed the rendered board image; F2 suspend while the
  board was open showed the sleep image, and resuming returned to the still-open board.
  Disabling the option restored `screensaver_type = "disable"` and the previously
  absent `screensaver_document_cover`; another suspend did not show the board image.
  No errors in `~/.config/koreader/crash.log`; `busted` passes. Inspected captures:
  `.amp/in/artifacts/phase13-sleep-filemanager.png`,
  `phase13-sleep-board-open.png`, `phase13-sleep-board-resumed.png`,
  `phase13-sleep-setting-off.png`, `phase13-sleep-setting-off-suspend.png`, and
  `phase13-sleep-resumed.png`. The owner still needs to check this on a device.
- **Verified D2 (2026-10-27, KOReader v2026.07.1 Emulator, 600×800):** pinned a
  card, replaced it with a second, unpinned it, and archived a pinned card (which
  removed the bar). Tapping the bar opened the card view. With a pinned card, F2
  suspend showed the board and Now bar; resuming returned to the open board. The
  pin remained after restarting KOReader. The sleep-screen option was turned off
  through the Tools UI afterward; its setting and screensaver snapshot are cleared.
  `busted` passes (29 tests), LuaJIT bytecode syntax checks pass, and `crash.log`
  has no ERROR/FATAL/CRASH/Traceback entries. Inspected captures:
  `.amp/in/artifacts/phase13-now-pinned.png`, `phase13-now-replaced.png`,
  `phase13-now-unpinned.png`, `phase13-now-archive-clears.png`,
  `phase13-now-tap-bar.png`, `phase13-now-sleep.png`,
  `phase13-now-sleep-resumed.png`, `phase13-now-after-restart.png`, and
  `phase13-now-sleep-setting-off.png`.
- **Done when:** the setting works in the emulator's suspend flow, the previous
  screensaver settings come back when it's turned off, and the owner checks it on
  their device.

### Phase 14: Across boards and Markdown
- [x] F3: a "Today" view from the board menu and a Dispatcher action, listing the cards
      in every board's in-progress columns (by default, the second-to-last column;
      configurable per board), grouped by board. Tapping a card opens it.
- **Verified (2026-10-26, KOReader v2026.07.1, 600×800):** Today opens from the board
  menu and from the `kanban_today` gesture in both File Manager and Reader. With two
  boards, the default Doing column is empty on My board and Release board uses its
  changed To Do column to show “Prepare release notes”. Tapping it opens Release board
  on To Do with the existing card actions dialog. No errors in `crash.log`; `busted`
  passes (20 tests). Inspected captures: `.amp/in/artifacts/phase14-today-fm-default-empty.png`,
  `phase14-today-board-menu-empty.png`, `phase14-today-column-setting.png`,
  `phase14-today-two-boards.png`, `phase14-today-card-actions.png`, and
  `phase14-today-reader-gesture.png`.
- [x] F7: export a board to Markdown in the home folder (columns as headings, cards as
      list items, checklists as `- [ ]`), and import such a file as a new board.
- **Verified (2026-10-27, KOReader v2026.07.1, 600×800):** exported the demo board
  to `kanban-Demo board.md`, checked the headings, cards, notes and checklist text,
  and confirmed a second export overwrote the file with identical content. Imported
  it through the PathChooser; the new board was selected and saved (`current_board`
  is `b2`), and re-exporting it matched the source Markdown exactly. Importing a
  malformed file displayed “Card appears before a column heading”; the saved state
  hash was unchanged. No errors or crashes in `crash.log` (the expected malformed
  import warning was logged); `busted` passes (25 tests). Inspected captures:
  `.amp/in/artifacts/phase14-md-menu.png`, `phase14-md-exported.png`,
  `phase14-md-import-chooser.png`, `phase14-md-imported.png`, and
  `phase14-md-malformed.png`.
- **Done when:** export then import gives an identical board (spec), and the Today view
  works from the menu and a gesture.

### Later (not scheduled)
Ideas the owner wants to keep but not build yet:
- Pinch to zoom: `pinch`/`spread` step between fixed density levels (one large column,
  normal, compact one-line cards, overview with count bars), one refresh per step; also
  in the board menu for devices without multitouch.
- Screenshots on cards: attach the newest KOReader screenshot or any image; files kept
  next to `kanban.lua`, opened in KOReader's image viewer from the card view.
- Sending bugs to Claude: either ask the Anthropic API about a card and append the reply
  to its notes, or file a card as a bug for a coding agent. Undecided which.

## How to verify

- Unit tests: run `busted` from the repo root. It must pass before every commit.
- Manual: start KOReader (the AppImage or `./kodev run`) with the plugin linked or
  copied into its `plugins/` directory, then follow the phase's acceptance criteria.
  Check `crash.log` afterwards.
- For any UI change, capture and inspect screenshots of every affected state.
- Verify only what your phase changed. Checks across several features are done once,
  in a combined emulator pass after merging.
- If a check needs fixing the environment rather than the plugin, try once, then skip
  it and say why in your report. If a check is taking unusually long, tell the
  coordinating thread in one line instead of digging further.

### Emulator notes (orb)

These add to the per-phase orb notes above.
- There are two ways to run KOReader, and they behave differently:
  - The **desktop build** (`AppRun`, with `KO_MULTIUSER=1`) keeps its settings in
    `~/.config/koreader/settings/`. F2 does **not** suspend, so it can't test the
    sleep screen.
  - The **emulator build** keeps its settings next to the program, in
    `~/.cache/koreader/current/usr/lib/koreader/settings/`. F2 suspends and resumes.
    Seed `kanban.lua` (and any `kanban-sleepscreen.lua`) there, or the board comes up
    empty.
- **Launching:** run `.agents/emulator start [--size WxH] [--seed demo|empty]
  [--build desktop|emulator] [--reader BOOK]`. It links this checkout's plugin,
  seeds the selected build's settings (saving a replaced board as `kanban.lua.prev`),
  sizes the orb output/window, and starts KOReader as the supervised `koreader`
  service with the board open and httpinspector on port 8080. Use
  `.agents/emulator screenshot FILE` to capture the window and `.agents/emulator stop`
  to stop it. The default is 600×800, demo seed, desktop build; use the emulator build
  for F2 suspend/resume checks.
- Undo test state before finishing: `today_column` choices, the sleep-screen option
  (turn it off from the UI so the screensaver settings are restored), and any data
  files copied into the emulator build's settings folder.

## Decision log

- 2026-10-25: Deferred the KOReader AppImage/emulator download to phase 1 — phase 0 only needs the Lua test toolchain.
- 2026-10-25: Model IDs use each board's `next_id` counter for columns and cards; board IDs use the first unused `bN` value.
- 2026-10-25: Dropped book linking (old phase 6) — the board is for projects, feature ideas and productivity tasks. Later phases renumbered.
- 2026-10-25: Phase 1 fulfills the deferred download with GitHub's latest stable
  x86_64 AppImage, extracted using `--appimage-extract` outside the checkout.
  `~/.cache/koreader/current/AppRun` is the FUSE-free launcher. Validate the native
  SDL app on the orb Desktop using X11 and a supervised `koreader` service.
- 2026-10-25: Checked v2026.07.1's bundled `hello.koplugin`, `texteditor.koplugin`,
  `frontend/ui/menusorter.lua`, and both menu-order tables. Use `sorting_hint =
  "tools"` (not the example plugin's `"more_tools"`) for the top-level Tools entry.
  `_meta.lua` has no `name` field, because current KOReader ignores it and logs a
  deprecation warning.
- 2026-10-25: Phase 3 board layout: minimum column width `Screen:scaleBySize(240)`
  (2 columns in 600 px portrait, 3 in 800 px landscape), cards are fixed at 3 title
  lines (`TextBoxWidget` with `height_overflow_show_ellipsis`). Column pages start at
  multiples of the columns per screen, so the last page can be short; it stays left-
  aligned. After a rotation, the page that holds the previous leftmost column is shown.
  Each column keeps its own card offset; swipe north shows later cards, south earlier.
- 2026-10-25: The title bar's menu button is present but does nothing until phase 4
  adds the board menu (done in phase 4). The board view also closes with the Back key and pages columns
  with the page-turn keys; full keyboard navigation stays in phase 6.
- 2026-10-25: Rotation follows `Menu:onSetRotationMode`: the board asks the
  underlying FileManager (`ui:onSetRotationMode`) or ReaderUI (`ui.view:
  onSetRotationMode`) to rotate, then rebuilds itself. On devices this event comes
  from the accelerometer, which sends it to the top widget.
- 2026-10-25: Phase 4 model changes: added `Model.selectBoard(state, id)` (switching
  boards goes through the model and is saved), and `deleteBoard` refuses to delete the
  last board, so the board view always has a board. The Boards dialog disables Delete
  when only one board is left.
- 2026-10-25: Every edit goes through `BoardView:commit(change, after, refresh)`:
  `change` calls one Model function; on success the state is saved with
  `Storage.save()` right away and the view is rebuilt (`"ui"` refresh, `"flashui"`
  when the board changes). On failure, it logs and shows an `InfoMessage`. After an
  add, move or restore the view pages to where the card landed.
- 2026-10-25: Quick-move highlight for grayscale: the picked card gets a 4 px border,
  a light-gray fill and bold title; every column it can go to has its header inverted
  (black bar, white text and badge); the footer reads "Tap a column header to move the
  card". Headers are tap targets in all modes. Hold does nothing on a one-column board.
  Tapping the card's own column, anywhere else, or ☰ cancels.
- 2026-10-25: Card actions show the card's title in bold and its notes (first 300
  characters) below it. Disabled actions (Move up on the first card, Move left on the
  first column, Move to… on a one-column board) are grayed out, not hidden.
- 2026-10-25: Card editor: Enter in the title field saves; the notes field
  (`allow_newline`) takes new lines. New cards go to the end of the column.
- 2026-10-25: Archived cards lists newest first; tapping a card asks which column to
  restore it to (appended at the end). Deleting a board deletes its archived cards too,
  and the confirmation says so; deleting a column archives its cards (as before).
- 2026-10-25: The column footer has ‹ › chevron buttons, built like `Menu`'s page
  footer (`chevron.left`/`chevron.right`, mirrored for RTL, `enableDisable`), so it's
  visible that more columns are a swipe away and they can be reached by tapping.
- 2026-10-25: "Add Kanban card" builds a `BoardView` without showing it and passes it
  to `CardDialog.editCard`, so the card is saved through the same `commit()` path as
  every other edit.
- 2026-10-25: From the owner's first device test: opening the board uses a "full"
  refresh to clear ghosting, and Move left/right in the column dialog reopens the
  dialog so a column can be moved several places (its last button is now "Close").
- 2026-10-25: Don't give phases that need screenshot checks to Amp's `low` mode: its
  model can't accept images, and once a screenshot is in the thread every request
  fails.
- 2026-10-26: Added phases 8–14 from a UI/UX brainstorm; the owner picked the items
  (IDs such as C1 and B1 refer to that list). Not picked for now: holding a column
  header to move the column (B3), the columns-per-screen setting, list view, labels,
  due dates, search. Pinch to zoom, screenshots on cards and sending bugs to Claude are
  under "Later". Rule 4 now allows phase 10's snap-preview drag. On 7" Kindles
  (1264×1680) the board keeps 2 columns in portrait, because `scaleBySize` scales with
  screen pixels, not physical size.
- 2026-10-26: The board name in the title bar (marked ▼) is the board switcher: tapping
  the title opens the Boards dialog, so switching is no longer one of four equal menu
  items. The menu's "Boards…" entry was removed because it opened the same dialog.
  The Boards dialog's title is just "Boards"; its buttons read "Rename “<board>”" and
  "Delete “<board>”".
- 2026-10-26: The board menu has "Rotate screen" for devices without an accelerometer.
  It switches between portrait and landscape (like KOReader's `SwapRotation`), not
  through all four rotations.
- 2026-10-26: Amp's `low` mode now uses GPT-6 Luna, which accepts images, so the
  2026-10-25 rule against giving it screenshot phases no longer applies.
- 2026-10-26: Schema v2 uses an ordered `card.checklist` array of `{ text, done }`
  items, `card.moved` (initialized with `created`, reset only when a move changes
  columns), and `column.collapsed` (default `false`). Migration preserves all v1
  fields, defaults missing checklists/collapse flags, and derives a missing `moved`
  from `updated`, then `created`, then `0`. When `Storage.load` reads a v1 file, it
  first copies it to `kanban.lua.v1.bak` (once; an existing backup is kept), so the
  first v2 save can't lose it. A failed backup is logged, not fatal.
- 2026-10-26: Checklist operations use 1-based array positions and trim/reject empty
  item text. The UI-facing signatures are
  `Model.addChecklistItem(board, card_id, text, index?, clock?)`,
  `Model.editChecklistItem(board, card_id, item_index, text, clock?)`,
  `Model.toggleChecklistItem(board, card_id, item_index, clock?)`,
  `Model.deleteChecklistItem(board, card_id, item_index, clock?)`,
  `Model.moveChecklistItem(board, card_id, item_index, new_index, clock?)`, and
  `Model.setColumnCollapsed(board, column_id, collapsed)`. Checklist mutations update
  `card.updated`; add/move indexes clamp to the valid range.
- 2026-10-26: The pure Markdown format uses `# Board name`, one `## Column` heading
  per column, plain top-level `- Title` card items, and nested `- [ ]` / `- [x]`
  checklist items. Card notes use an HTML-comment-delimited region only when non-empty;
  every note line is a blockquote line inside the card, preserving blank lines and
  Markdown-looking text while keeping the boundaries unambiguous. The final
  `# Archived cards` section holds archived cards. Names, titles and checklist text are
  written verbatim except that backslashes and newline, carriage-return and tab
  characters are escaped as `\\`, `\n`, `\r` and `\t`; structure is determined by line
  position and indentation. Import accepts CRLF, extra blank lines and a missing
  archive section.
- 2026-10-26: `Markdown.export(board)` returns the Markdown string.
  `Markdown.import(text, state?, clock?)` returns the newly built board or `nil, err`;
  with a destination state it adds a board through `Model.addBoard`, and without one
  it builds a standalone board from `Model.newState`. Optional `clock` is forwarded to
  Model card/checklist operations for deterministic timestamps. Phase 14 F7 remains
  unchecked until its UI and file writing are done.
- 2026-10-26: F3 stores the selected in-progress column by ID in `board.today_column`,
  with no schema version bump. When the ID is absent or no longer valid, Today uses
  the second-to-last column (the only column when there is one); a board with no
  columns has no in-progress column. Deleting the selected column clears its ID so
  the default applies again.
- 2026-10-26: The column actions dialog marks the board's in-progress column for
  Today. Today is a scrollable, grouped list that keeps empty boards visible; tapping
  a card selects its board, opens the board at that card's column page, then shows the
  existing card actions dialog. When Today was opened from a board's menu, that board
  view is closed first so board views don't stack.
- 2026-10-26: D1 renders a fresh `BoardView` into an off-screen grayscale Blitbuffer
  instead of capturing the visible screen, so the sleep image tracks board layout
  changes without modifying `boardview.lua`. KOReader calls `Screensaver.setup()`
  before the later `Suspend` broadcast, so rendering and the temporary
  `screensaver_type = "document_cover"` / `screensaver_document_cover` override happen
  in a `Screensaver.setup` hook, before the native screensaver reads them. The prior
  values of both keys (including a key that was absent) are restored on resume,
  startup, or when the option is turned off. The emulator pass is complete, but the
  owner still needs to check D1 on a device.
- 2026-10-26: Phase 8 sizes cards from their measured wrapped title lines (up to
  three) and greedily packs each column page by actual card heights plus gaps. Card
  swipes move between these calculated page ranges, and the pager reports the visible
  range rather than a fixed card count. Reserve a card-gap spacer before its fixed
  pager row, and include `TextBoxWidget`'s extra glyph-buffer height in each measured
  card height; without that extra height, stacked cards can extend into the pager.
- 2026-10-26: Phase 8 replaces the column-range footer with named, counted tabs. If
  every tab can fit at the minimum scaled width, show them all; otherwise show the
  current column page's tabs between chevrons. The visible columns are inverted,
  tapping another tab reveals its column page, and long names are ellipsized while
  retaining the count. Quick-move keeps its existing prompt and chevrons instead of
  the tabs.
- 2026-10-26: Phase 10 supersedes the old quick-move footer: keep column tabs visible
  during pickup so they can accept end-of-column drops. Headers still append to
  another column, and the picked card's own header still cancels. Holding is now
  allowed with one column. Gaps are derived from painted card/header frames in
  `cardmove.lua`, independent of card-list construction (including the future Add
  card row); same-column insertion indexes account for removal of the source card.
  Actual moves call the existing `commit()` unchanged; no-op drops/cancels do not
  save or consume undo.
- 2026-10-26: Checked bundled KOReader v2026.07.1
  `frontend/device/gesturedetector.lua`: `hold_pan` uses current finger coordinates
  and is emitted only when either axis reaches DPI-scaled `PAN_THRESHOLD` (35 at
  base DPI); both stationary holds and hold-pans finish with `hold_release` at the
  lift position. Rely on that detector threshold, not a competing plugin threshold.
  Checked `frontend/ui/uimanager.lua`'s `setDirty(widget, refreshtype, refreshregion)`
  contract: snap-preview overlays use `a2` with explicit old/new bar/tab rectangles,
  only when the target changes; release uses the normal commit's one `ui` refresh.
  The source card never follows the finger, and lifting back in its original frame
  cancels. Drag off preserves hold-and-lift/tap-to-drop. Tools → Kanban board →
  Drag to move defaults on and flushes `drag_to_move` to `kanban-options.lua` in
  `DataStorage:getSettingsDir()`, following sleepscreen.lua's LuaSettings pattern.
- 2026-10-26: A2's add-card row uses a light-gray `FrameContainer` border because
  KOReader's `FrameContainer` has no dashed-border option. Its height and gap count
  toward card-page packing, so the final card moves to a later page when needed to
  keep the row with it. Empty columns keep "No cards" and show the add row beneath it;
  the row is a separate tap target, never a quick-move or hold-card target.
- 2026-10-26: Phase 9 A1 keeps Move to… for arbitrary destinations and adds adjacent
  column shortcuts; the next-column shortcut uses a larger font, and unavailable
  directions stay visible but disabled.
- 2026-10-26: Phase 9 A4 keeps the card action dialog open after within-column moves,
  including Move to top/bottom. Its Card moved message and Undo button are inline with
  the actions, so the user can immediately repeat a reorder; Undo rebuilds the dialog
  for the restored order.
- 2026-10-26: Phase 9 A3 persists one board snapshot and the previous paging position
  in the state for active-board commits, covering card-dialog and drag moves, archive,
  delete-column and restore. Reorder records also keep their card context for the
  inline Undo row. Successful active-board changes replace the one-level record;
  board selection/add/delete that switches the current board clears it. Moves (dialog
  and drag), archive, column delete and restore show an Undo prompt that closes after
  10 seconds; other changes (edits, adds, renames) show none. The last change of the
  current board can always be undone from the board menu's "Undo: <change>" entry,
  which is how undo survives a restart (no prompt pops up when the board opens).
- 2026-10-26: The Move to… and Restore destination buttons bind each destination in
  a per-iteration local and resolve their gettext message outside the generic-for loop;
  this avoids Lua 5.1 loop-variable capture and `_` shadowing in callbacks.
- 2026-10-27: Markdown exports use the configured `home_dir`, falling back to
  `Device.home_dir` when it is unset or invalid. Export filenames replace unsafe
  characters, trim leading/trailing dots and spaces, and cap the board-name portion
  at 240 bytes without splitting UTF-8 characters; an existing export is overwritten.
- 2026-10-27: Markdown import uses KOReader's `PathChooser`, filtered to `.md` files.
  A successful import is committed through the board view, which selects the new
  board and saves it with a full refresh; an invalid Markdown document is rejected
  without adding a board.
- 2026-10-27: E1 uses a dedicated full-screen CardView over the board. The title,
  scrollable notes and checklist share one scroll area; closing returns to the board
  with the card's current column and page shown. The existing CardDialog actions are
  reused: moving keeps the detail view open, while archiving closes it.
- 2026-10-27: Checklist add, edit, toggle and delete call the schema-v2 Model
  operations through `BoardView:commit()`, retaining the existing save and one-level
  undo behavior. Board commits notify an open CardView to repaint. Today opens the
  same detail view after selecting and revealing its card.
- 2026-10-27: C4 omits the marker row when a card has no notes, checklist or completed
  day in its current column. A pure `Model.daysInColumn(moved, clock)` helper floors elapsed
  seconds to complete 24-hour days, with the clock supplied by the caller for tests.
  Marker rows are included in variable-height card packing.
- 2026-10-27: C6 packs column pages by minimum widths: collapsed columns use a
  `Screen:scaleBySize(48)` strip, expanded columns use a 220-scaled-pixel minimum, and
  no page has more than three expanded columns. The slightly narrower minimum lets a
  collapsed strip free enough room for another column on wide landscape screens.
  Strips are not header/card-gap targets; drops on a strip are append operations, as
  are drops on its tab, and neither changes the collapsed flag.
- Combined check (2026-10-27, origin/main `993710b`): Phase 8 layout passed at 600×800
  and the board at 1264×1680; Phase 9 add row, shortcuts, reorder and both Undo paths;
  Phase 10 tap-to-drop, drag (including another column and tab) and its setting; Today,
  board switcher, rotation and Add Kanban card gesture; emulator-build sleep image.
  Sleep-screen option was turned off afterwards. No crash.log errors or commit-path
  require crash. Fixed the one-card pager to show translated “Card 11 of 11”. `busted`:
  25 successes. Inspected captures: `.amp/in/artifacts/combined-*.png`.
- 2026-10-27: D2 stores the pinned card id as `board.now_card`, with no schema bump;
  setting it validates that the card exists and is not archived, and archiving a
  card or deleting its column clears the pin. The Now bar consumes vertical space
  before the columns, so card-page packing uses the remaining height; the card stays
  in its column. The sleep-screen render shows the full board with its Now bar rather
  than rendering only the pinned card, reusing BoardView's existing off-screen renderer.
- 2026-10-27: A8 keeps selection in the board view, not saved card data. Selected
  cards use a heavy black border and gray fill without changing title metrics or
  page packing. The counted action bar replaces tabs; swipes/page keys still page,
  while card holds/drags and non-card body taps do nothing. Bulk operations pass
  board-ordered IDs to pure `Model.changeCards(board, ids, destination?, clock?)`;
  it validates the entire batch before mutating and delegates to move/archive.
  Each batch uses one commit/save/snapshot, so one Undo restores every card.
- 2026-10-27: D4 diffs the previous board snapshot for changed column lists and
  card contents, reuses untouched column widgets/targets, and rebuilds affected
  columns and tabs. Unknown board metadata, column structure/collapse, and pickup
  decorations retain a full-layout fallback; page changes use full-board `flashui`.
  Undo uses the same diff path. Repaint regions are named painted widgets (`tabs`
  and column IDs), not y offsets, so an additional region above columns can be
  registered alongside them without changing refresh geometry. Checked KOReader's
  `UIManager:setDirty` and vocabbuilder's callback pattern: dirty the shown board,
  resolve child regions after painting. The tab region excludes the unchanged
  separator because UIManager merges even edge-touching rectangles; including the
  separator would merge columns and tabs into a near-full-board refresh. Drag's
  existing old/new `a2` preview rectangles remain unchanged; release's full fallback
  clears pickup headers and source highlighting.
