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
        local VerticalGroup = require("ui/widget/verticalgroup")
        local VerticalSpan = require("ui/widget/verticalspan")
        local LineWidget = require("ui/widget/linewidget")
        local Geom = require("ui/geometry")
        local sc = Kit.sc(ctx.scale)
        local width = math.max(1, ctx.width)
        local remaining = ctx.max_height and ctx.max_height > 0 and ctx.max_height or nil
        local group = VerticalGroup:new{ align = "left" }

        -- Report natural height to Bookshelf's size fitter, but give each
        -- section only the space left in the card. Long titles cannot push
        -- later widgets beyond the host's clipping boundary.
        local function space(n)
            local h = sc(n)
            if remaining then h = math.min(h, math.max(0, remaining)) end
            if h <= 0 then return end
            group[#group + 1] = VerticalSpan:new{ width = h }
            if remaining then remaining = remaining - h end
        end
        local function text(value, size, muted, bold, lines)
            if remaining and remaining <= 0 then return end
            local cap = lines and sc(size * 1.5 * lines) or nil
            if remaining then cap = math.min(cap or remaining, remaining) end
            local widget = Kit.fitText{
                text = value, size = size, opts = { bold = bold or false },
                scale_pct = ctx.scale, width = width, max_h = cap,
                fgcolor = muted and Kit.COLOR_MUTED or Kit.COLOR_PRIMARY,
                bgcolor = Kit.CARD_BG,
            }
            local height = widget:getSize().h
            -- TextBoxWidget keeps at least one full line, even when its
            -- requested cap is smaller. Omit a row that cannot fit.
            if remaining and height > remaining then
                widget:free()
                return
            end
            group[#group + 1] = widget
            if remaining then remaining = remaining - height end
        end
        local function heading(name)
            text(name, 20, false, true, 1)
            space(5)
            if not remaining or remaining >= sc(1) then
                group[#group + 1] = LineWidget:new{
                    dimen = Geom:new{ w = width, h = sc(1) },
                    background = Kit.COLOR_MUTED,
                }
                if remaining then remaining = remaining - sc(1) end
            end
            space(7)
        end

        local owner, board
        if not ctx.preview then
            owner = plugin()
            board = owner and selected(ctx, stateFor(owner))
        end
        if not ctx.preview and not board then
            heading(_("Kanban board"))
            text(owner and _("Tap to choose a board.")
                or _("Enable Kanban and use Bookshelf 6.1 or newer."), 14, true)
            return group
        end

        heading(ctx.preview and _("Kanban board") or board.name)
        local pinned = not ctx.preview and board.now_card and board.cards[board.now_card]
        if ctx.preview or (pinned and not pinned.archived) then
            text(_("Now"), 12, true, true, 1)
            space(2)
            text(ctx.preview and _("Your pinned card") or pinned.title, 18, false, true, 2)
            space(9)
        end
        local column = not ctx.preview and owner:getBookshelfTodayColumn(board)
        if ctx.preview then
            text(_("In progress"), 12, true, true, 1)
            space(3)
            text(_("Choose a board to show its tasks."), 14, true)
        elseif column then
            local tasks = {}
            for _, id in ipairs(column.cards) do
                local card = board.cards[id]
                if card and not card.archived then tasks[#tasks + 1] = card end
            end
            text(column.name .. " · " .. #tasks, 12, true, true, 1)
            space(4)
            if #tasks == 0 then
                text(_("No cards in this column."), 14, true)
            else
                for i = 1, math.min(3, #tasks) do
                    text("•  " .. tasks[i].title, 15, false, false, 1)
                    if i < math.min(3, #tasks) then space(3) end
                end
                if #tasks > 3 then
                    space(4)
                    text("+" .. (#tasks - 3) .. " " .. _("more"), 12, true, false, 1)
                end
            end
        else
            text(_("No in-progress column."), 14, true)
        end
        return group
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
