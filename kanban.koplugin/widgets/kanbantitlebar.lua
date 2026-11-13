-- Lightweight token-styled title bar: title/subtitle plus optional icon buttons.
local FrameContainer = require('ui/widget/container/framecontainer')
local Geom = require('ui/geometry')
local HorizontalGroup = require('ui/widget/horizontalgroup')
local CenterContainer = require('ui/widget/container/centercontainer')
local LeftContainer = require('ui/widget/container/leftcontainer')
local LineWidget = require('ui/widget/linewidget')
local Style = require('kanbanstyle')
local KanbanButton = require('widgets/kanbanbutton')
local TextWidget = require('ui/widget/textwidget')
local VerticalGroup = require('ui/widget/verticalgroup')
local VerticalSpan = require('ui/widget/verticalspan')
local WidgetContainer = require('ui/widget/container/widgetcontainer')

local KanbanTitleBar = WidgetContainer:extend{}

function KanbanTitleBar:init()
    self.width = self.width or require('device').screen:getWidth()
    self.align = self.align or "center"
    self.pad = Style.space.md
    self.icon_size = Style.icon.touch
    local content_width = self.width - 2 * self.pad
    local left_w = self.left_icon and self.icon_size or 0
    local right_w = self.close_callback and self.icon_size or 0
    local title_width = math.max(0, content_width - left_w - right_w)

    self.title_widget = TextWidget:new{
        text = self.title or "",
        face = self.title_face or Style.font.bar,
        bold = self.title_bold ~= false,
        fgcolor = Style.palette.ink,
        max_width = title_width,
        padding = 0,
    }
    local title_children = { self.title_widget }
    if self.subtitle and self.subtitle ~= "" then
        title_children[#title_children + 1] = TextWidget:new{
            text = self.subtitle,
            face = self.subtitle_face or Style.font.small,
            fgcolor = Style.palette.muted,
            max_width = title_width,
            padding = 0,
        }
    end
    local title_group = VerticalGroup:new{ align = self.align, unpack(title_children) }
    local title_area = (self.align == "left" and LeftContainer or CenterContainer):new{
        dimen = Geom:new{ w = title_width, h = self.title_widget:getSize().h + (self.subtitle and Style.space.xs or 0) },
        title_group,
    }

    local children = {}
    if self.left_icon then
        children[#children + 1] = KanbanButton:new{
            icon = self.left_icon,
            width = self.icon_size,
            height = self.icon_size,
            bordersize = 0,
            padding_h = 0,
            padding_v = 0,
            callback = self.left_icon_tap_callback,
            show_parent = self.show_parent,
        }
    end
    children[#children + 1] = title_area
    if self.close_callback then
        children[#children + 1] = KanbanButton:new{
            icon = self.close_icon or "close",
            width = self.icon_size,
            height = self.icon_size,
            bordersize = 0,
            padding_h = 0,
            padding_v = 0,
            callback = self.close_callback,
            show_parent = self.show_parent,
        }
    end
    local header = HorizontalGroup:new{ spacing = 0, align = "center", unpack(children) }
    local body_children = { header }
    if self.with_bottom_line then
        local line_width = self.width - 2 * (self.bottom_line_h_padding or self.pad)
        body_children[#body_children + 1] = VerticalSpan:new{ width = Style.space.xs }
        body_children[#body_children + 1] = LineWidget:new{
            dimen = Geom:new{ w = line_width, h = Style.border },
            background = self.bottom_line_color or Style.palette.rule,
        }
    end
    self.frame = FrameContainer:new{
        width = self.width,
        bordersize = 0,
        padding = self.pad,
        background = self.background or Style.palette.paper,
        show_parent = self.show_parent,
        VerticalGroup:new{ align = "center", unpack(body_children) },
    }
    self[1] = self.frame
    self.dimen = self.frame:getSize()
end

function KanbanTitleBar:setTitle(title)
    self.title = title
    if self.title_widget then self.title_widget:setText(title or "") end
end

function KanbanTitleBar:getHeight()
    return self.dimen and self.dimen.h or self.frame:getSize().h
end

return KanbanTitleBar
