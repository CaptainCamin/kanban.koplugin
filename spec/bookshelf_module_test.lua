-- Standalone module contract/interaction test; run from the repository root:
-- luajit spec/bookshelf_module_test.lua
local root = "kanban.koplugin/bookshelf_modules"
local shown, pending, opened, refreshed, reads = nil, nil, nil, 0, 0
local state = { current_board = "a", boards = {
    { id = "a", name = "Alpha", cards = {}, columns = {} },
    { id = "b", name = "Beta", now_card = "1", cards = {
        ["1"] = { title = "Pinned" }, ["2"] = { title = "Task" },
    }, columns = {{ name = "Doing", cards = {"1", "2"} }} },
} }
local owner = {
    getBookshelfState = function() reads = reads + 1; return state end,
    getBookshelfTodayColumn = function(_, board) return board.columns[1] end,
    onKanbanOpen = function(_, id, on_close) opened = id; on_close() end,
}
local available = true
local text_widgets = {}
package.preload["gettext"] = function() return function(s) return s end end
package.preload["lib/bookshelf_module_kit"] = function() return {
    plugin = function(dir) assert(dir == root); return available and owner end,
    COLOR_PRIMARY = "primary", COLOR_MUTED = "muted", CARD_BG = "card",
    sc = function(scale) return function(n) return math.max(1, math.floor(n * (scale or 100) / 100 + 0.5)) end end,
    fitText = function(options)
        -- Like TextBoxWidget, retain one full line even when max_h is
        -- smaller. The renderer must omit that widget rather than clip it.
        local line_height = options.size * (options.scale_pct or 100) / 100 * 1.5
        function options:getSize() return { w = self.width, h = line_height } end
        function options:free()
            assert(not self.freed, "text widget must not be freed twice")
            self.freed = true
        end
        text_widgets[#text_widgets + 1] = options
        return options
    end,
} end
package.preload["ui/uimanager"] = function() return {
    show = function(_, dialog) shown = dialog end,
    close = function(_, dialog) assert(shown == dialog); shown = nil end,
    nextTick = function(_, callback) pending = callback end,
} end
for _, name in ipairs({"buttondialog", "infomessage"}) do
    package.preload["ui/widget/" .. name] = function() return {
        new = function(_, options) return options end,
    } end
end
for _, name in ipairs({"verticalgroup", "verticalspan", "linewidget"}) do
    package.preload["ui/widget/" .. name] = function() return {
        new = function(_, options) return options end,
    } end
end
package.preload["ui/geometry"] = function() return {
    new = function(_, options) return options end,
} end
local function contents(widget)
    local lines = {}
    for _, child in ipairs(widget) do
        if child.text then lines[#lines + 1] = child.text end
    end
    return table.concat(lines, "\n")
end
local module = assert(loadfile(root .. "/kanban.lua"))(root)
local function rendered(ctx) return contents(module.render(ctx)) end
local function context(id)
    local values = { board_id = id }
    return { width = 240, scale = 100,
        config = {
            get = function(_, key) return values[key] end,
            set = function(_, key, value) values[key] = value end,
        },
        refresh = function() refreshed = refreshed + 1 end,
    }
end
local first, second = context("a"), context("b")
assert(module.key == "kanban_board" and module.summary and module.keep_open)
assert(rendered({ width = 100, scale = 100, preview = true }):find("Kanban"))
assert(reads == 0, "picker preview must not load board data")
assert(rendered(first):find("Alpha"))
local text = rendered(second)
assert(text:find("Beta") and text:find("Now\nPinned") and text:find("Task"))
assert(state.current_board == "a", "render must not select a board")
module.show_settings(first)
shown.buttons[2][1].callback()
assert(first.config:get("board_id") == "b")
assert(second.config:get("board_id") == "b")
module.show_settings(first)
shown.buttons[1][1].callback()
assert(first.config:get("board_id") == "a" and second.config:get("board_id") == "b")
module.on_tap(second)
assert(opened == nil and pending, "opening must wait for the tap to finish")
pending()
assert(opened == "b" and refreshed == 1)
local added
module.on_add(first, function(fields) added = fields end)
shown.buttons[2][1].callback()
assert(added.board_id == "b")
module.on_add(first, function(fields) added = fields or "cancelled" end)
shown.buttons[#shown.buttons][1].callback()
assert(added == "cancelled")
table.remove(state.boards, 2)
-- Tap forces a fresh read, so deletion cannot open a different board.
module.on_tap(second)
assert(shown.title == "Choose Kanban board")
assert(rendered(second):find("Tap to choose"))
available = false
assert(rendered(first):find("Enable Kanban"))
available = true
local board = state.boards[1]
board.now_card = "p"
board.cards = { p = { title = "Pinned title" }, a = { title = "Visible task" },
    old = { title = "Archived task", archived = true } }
board.columns = {{ name = "Doing", cards = { "missing", "old", "a", "a", "a", "a" } }}
module.on_tap(first)
local full = module.render(first)
assert(full[1].opts.bold and full[1].size == 20)
local rendered_text = contents(full)
assert(rendered_text:find("Doing · 4") and rendered_text:find("+1 more"))
assert(not rendered_text:find("Archived task"))
for _, height in ipairs({1, 24, 60, 100, 240}) do
    local ctx = context("a")
    ctx.max_height = height
    text_widgets = {}
    local layout = module.render(ctx)
    local used, retained = 0, {}
    for _, child in ipairs(layout) do
        retained[child] = true
        assert(not child.freed, "freed widgets must not remain in the layout")
        used = used + (child.text and child:getSize().h or child.dimen and child.dimen.h or child.width or 0)
    end
    assert(used <= height, "layout must respect the available height")
    local omitted = 0
    for _, widget in ipairs(text_widgets) do
        if widget.max_h and widget:getSize().h > widget.max_h then
            omitted = omitted + 1
            assert(widget.freed, "a row exceeding the available height must be freed")
            assert(not retained[widget], "an oversized row must be omitted")
        else
            assert(retained[widget] and not widget.freed, "fitting rows must be retained")
        end
    end
    if height == 1 then
        assert(#text_widgets == 1 and omitted == 1, "one-pixel cards must omit the full-line heading")
        assert(contents(layout) == "", "one-pixel cards cannot contain text")
    elseif height == 60 then
        assert(omitted > 0 and contents(layout):find("Alpha"),
            "partial layouts must retain the heading and omit overflowing later rows")
    end
end
print("Bookshelf module checks passed")
