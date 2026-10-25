local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Kanban = WidgetContainer:extend{
    name = "kanban",
    is_doc_only = false,
}

function Kanban:init()
    self.ui.menu:registerToMainMenu(self)
end

function Kanban:addToMainMenu(menu_items)
    menu_items.kanban = {
        text = _("Kanban board"),
        sorting_hint = "tools",
        callback = function()
            UIManager:show(InfoMessage:new{
                text = _("Kanban board is ready. Board features are coming soon."),
            })
        end,
    }
end

return Kanban
