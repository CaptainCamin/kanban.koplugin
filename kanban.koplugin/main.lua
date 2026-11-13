local BoardView = require("boardview")
local CardDialog = require("carddialog")
local CardMove = require("cardmove")
local Dispatcher = require("dispatcher")
local SleepScreen = require("sleepscreen")
local Storage = require("storage")
local Model = require("model")
local TodayView = require("todayview")
local UIManager = require("ui/uimanager")
local KanbanDialog = require("widgets/kanbandialog")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Kanban = WidgetContainer:extend{
    name = "kanban",
    is_doc_only = false,
}

function Kanban:init()
    self:onDispatcherRegisterActions()
    SleepScreen.restoreUserSettings()
    SleepScreen.installScreensaverHook()
    self.ui.menu:registerToMainMenu(self)
end

function Kanban:onResume()
    SleepScreen.restoreUserSettings()
end

-- Register Dispatcher actions so they can be bound to gestures in the Gesture
-- manager, just like bundled plugins (hello, calibre, vocabbuilder) do.
function Kanban:onDispatcherRegisterActions()
    Dispatcher:registerAction("kanban_open", {
        category = "none",
        event = "KanbanOpen",
        title = _("Open Kanban board"),
        general = true,
    })
    Dispatcher:registerAction("kanban_add_card", {
        category = "none",
        event = "KanbanAddCard",
        title = _("Add Kanban card"),
        general = true,
    })
    Dispatcher:registerAction("kanban_today", {
        category = "none",
        event = "KanbanToday",
        title = _("Kanban: Today"),
        general = true,
    })
end

-- Open the board view, from the Tools menu entry or the Dispatcher action.
-- A full refresh clears the File Manager or page underneath from the e-ink screen.
function Kanban:onKanbanOpen(board_id, on_close)
    local state = Storage.load()
    if board_id and not Model.selectBoard(state, board_id) then
        UIManager:show(KanbanDialog:new{ text = _("This board no longer exists."), timeout = 2 })
        return true
    end
    -- Selecting a Bookshelf card must not change the last-opened board until tapped.
    if board_id then Storage.save(state) end
    local view = BoardView:new{
        state = state,
        ui = self.ui,
    }
    if on_close then
        local original = view.onCloseWidget
        view.onCloseWidget = function(widget)
            if original then original(widget) end
            on_close()
        end
    end
    UIManager:show(view, "full")
    return true
end

-- Public bridge for our optional Bookshelf module. Keep plugin-local requires
-- here: Bookshelf's module loader uses a different Lua search path.
function Kanban:getBookshelfState()
    return Storage.load()
end

function Kanban:getBookshelfTodayColumn(board)
    return Model.getTodayColumn(board)
end

-- Add a card to the first column of the current board without opening the board.
-- The editor dialog reuses CardDialog.editCard; the change is committed through a
-- BoardView so Storage.save() is called exactly like every other edit. The view
-- itself is never shown, so only the editor dialog appears on top of File Manager
-- or Reader.
function Kanban:onKanbanAddCard()
    local state = Storage.load()
    local view = BoardView:new{
        state = state,
        ui = self.ui,
    }
    local board = view:getBoard()
    local column = board.columns[1]
    if not column then
        UIManager:show(KanbanDialog:new{
            text = _("This board has no columns."),
            timeout = 2,
        })
        return true
    end
    CardDialog.editCard(view, column.id)
    return true
end

-- Show the cross-board in-progress list from the Dispatcher action.
function Kanban:onKanbanToday()
    UIManager:show(TodayView:new{
        state = Storage.load(),
        ui = self.ui,
    }, "full")
    return true
end

function Kanban:addToMainMenu(menu_items)
    menu_items.kanban = {
        text = _("Kanban board"),
        sorting_hint = "tools",
        keep_menu_open = true,
        sub_item_table = {
            {
                text = _("Open board"),
                callback = function() self:onKanbanOpen() end,
            },
            {
                text = _("Drag to move"),
                checked_func = CardMove.isEnabled,
                keep_menu_open = true,
                callback = function()
                    CardMove.setEnabled(not CardMove.isEnabled())
                end,
            },
            {
                text = _("Show board on sleep screen"),
                checked_func = SleepScreen.isEnabled,
                keep_menu_open = true,
                callback = function()
                    SleepScreen.setEnabled(not SleepScreen.isEnabled())
                end,
            },
        },
    }
end

return Kanban
