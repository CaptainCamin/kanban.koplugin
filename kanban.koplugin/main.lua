local BoardView = require("boardview")
local CardDialog = require("carddialog")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local Storage = require("storage")
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
end

-- Open the board view, same as the Tools menu entry.
function Kanban:onKanbanOpen()
    UIManager:show(BoardView:new{
        state = Storage.load(),
        ui = self.ui,
    })
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

function Kanban:addToMainMenu(menu_items)
    menu_items.kanban = {
        text = _("Kanban board"),
        sorting_hint = "tools",
        callback = function()
            UIManager:show(BoardView:new{
                state = Storage.load(),
                ui = self.ui,
            })
        end,
    }
end

return Kanban
