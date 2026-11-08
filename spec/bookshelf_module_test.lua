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
package.preload["gettext"] = function() return function(s) return s end end
package.preload["lib/bookshelf_module_kit"] = function() return {
    plugin = function(dir) assert(dir == root); return available and owner end,
    fitText = function(options) return options end,
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
local module = assert(loadfile(root .. "/kanban.lua"))(root)
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
assert(module.render({ width = 100, scale = 100, preview = true }).text:find("Kanban"))
assert(reads == 0, "picker preview must not load board data")
assert(module.render(first).text:find("Alpha"))
local text = module.render(second).text
assert(text:find("Beta") and text:find("Now: Pinned") and text:find("Task"))
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
assert(module.render(second).text:find("Tap to choose"))
available = false
assert(module.render(first).text:find("Enable Kanban"))
print("Bookshelf module checks passed")
