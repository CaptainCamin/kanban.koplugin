local MODULE_DIR = ...
local Kit = require("lib/bookshelf_module_kit")
local _ = require("gettext")

-- Cache the settings read across Bookshelf's repeated size-fitting renders.
-- A board close/settings change invalidates it immediately.
local cached_state, cached_at
local function plugin()
    return Kit.plugin and Kit.plugin(MODULE_DIR)
end
local function stateFor(owner, fresh)
    local now = os.time()
    if fresh or not cached_state or cached_at ~= now then
        cached_state, cached_at = owner:getBookshelfState(), now
    end
    return cached_state
end
local function selected(ctx, state)
    local id = ctx.config and ctx.config:get("board_id")
    if not id then return nil end
    for _, board in ipairs(state.boards) do
        if board.id == id then return board end
    end
end

local function chooseBoard(ctx, done)
    local owner = plugin()
    if not owner then
        require("ui/uimanager"):show(require("ui/widget/infomessage"):new{
            text = _("Enable Kanban and use Bookshelf 6.1 or newer."),
        })
        if done then done(nil) end
        return
    end
    local UIManager = require("ui/uimanager")
    local dialog
    local rows = {}
    for _, board in ipairs(stateFor(owner, true).boards) do
        local board_id = board.id
        rows[#rows + 1] = {{
            text = board.name,
            callback = function()
                UIManager:close(dialog)
                cached_state = nil
                if done then
                    done({ board_id = board_id })
                elseif ctx.config then
                    ctx.config:set("board_id", board_id)
                end
            end,
        }}
    end
    rows[#rows + 1] = {{ text = _("Cancel"), callback = function()
        UIManager:close(dialog)
        if done then done(nil) end
    end }}
    dialog = require("ui/widget/buttondialog"):new{
        title = _("Choose Kanban board"), buttons = rows,
    }
    UIManager:show(dialog)
end

return {
    key = "kanban_board",
    title = _("Kanban board"),
    summary = _("Your Kanban board, Now card and in-progress tasks. Works offline."),
    min_w = 2,
    min_h = 1,
    tap_feedback = true,
    -- Keep the shelf behind the board, and behind the board picker.
    keep_open = true,
    on_add = function(ctx, done) chooseBoard(ctx, done) end,
    show_settings = function(ctx) chooseBoard(ctx) end,
    render = function(ctx)
        local lines = {}
        if ctx.preview then
            lines = { _("Kanban board"), _("Now: Your pinned card"),
                _("Choose a board to show its in-progress tasks.") }
        else
            local owner = plugin()
            local board = owner and selected(ctx, stateFor(owner))
            if not owner then
                lines = { _("Kanban board"), _("Enable Kanban and use Bookshelf 6.1 or newer.") }
            elseif not board then
                lines = { _("Kanban board"), _("Tap to choose a board.") }
            else
                lines[#lines + 1] = board.name
                local pinned = board.now_card and board.cards[board.now_card]
                if pinned and not pinned.archived then
                    lines[#lines + 1] = _("Now:") .. " " .. pinned.title
                end
                local column = owner:getBookshelfTodayColumn(board)
                if column then
                    lines[#lines + 1] = column.name .. " (" .. #column.cards .. ")"
                    for i = 1, math.min(3, #column.cards) do
                        local card = board.cards[column.cards[i]]
                        if card then lines[#lines + 1] = "• " .. card.title end
                    end
                    if #column.cards == 0 then
                        lines[#lines + 1] = _("No cards in this column.")
                    elseif #column.cards > 3 then
                        lines[#lines + 1] = "…"
                    end
                else
                    lines[#lines + 1] = _("No in-progress column.")
                end
            end
        end
        return Kit.fitText{
            text = table.concat(lines, "\n"), size = 18,
            scale_pct = ctx.scale, width = math.max(1, ctx.width),
            -- A natural height lets Bookshelf shrink the text to fit the card.
            max_h = ctx.max_height, fgcolor = Kit.COLOR_PRIMARY,
            bgcolor = Kit.CARD_BG,
        }
    end,
    on_tap = function(ctx)
        local owner = plugin()
        local board = owner and selected(ctx, stateFor(owner, true))
        if not board then chooseBoard(ctx); return end
        require("ui/uimanager"):nextTick(function()
            owner:onKanbanOpen(board.id, function()
                cached_state = nil
                if ctx.refresh then ctx.refresh() end
            end)
        end)
    end,
}
