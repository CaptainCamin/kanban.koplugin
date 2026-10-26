local BoardView = require("boardview")
local CardDialog = require("carddialog")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local Storage = require("storage")
local TodayView = require("todayview")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Kanban = WidgetContainer:extend{
    name = "kanban",
    is_doc_only = false,
}

function Kanban:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
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
function Kanban:onKanbanOpen()
    UIManager:show(BoardView:new{
        state = Storage.load(),
        ui = self.ui,
    }, "full")
    return true
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
        UIManager:show(InfoMessage:new{
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
        callback = function() self:onKanbanOpen() end,
    }
end

return Kanban
