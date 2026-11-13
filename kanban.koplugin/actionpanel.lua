-- Purpose-built Kanban action sheet. No ButtonDialog or ButtonTable layout.
-- KanbanButton supplies touch feedback and activation; its contents are
-- composed here so each action can have a title, supporting text and hierarchy.
local BB = require('ffi/blitbuffer')
local Button = require('widgets/kanbanbutton')
local BottomContainer = require('ui/widget/container/bottomcontainer')
local CenterContainer = require('ui/widget/container/centercontainer')
local Device = require('device')
local FocusManager = require('ui/widget/focusmanager')
local Font = require('ui/font')
local FrameContainer = require('ui/widget/container/framecontainer')
local Geom = require('ui/geometry')
local GestureRange = require('ui/gesturerange')
local HorizontalGroup = require('ui/widget/horizontalgroup')
local HorizontalSpan = require('ui/widget/horizontalspan')
local ScrollableContainer = require('ui/widget/container/scrollablecontainer')
local Style = require('kanbanstyle')
local TextBoxWidget = require('ui/widget/textboxwidget')
local TextWidget = require('ui/widget/textwidget')
local UI = require('ui/uimanager')
local VerticalGroup = require('ui/widget/verticalgroup')
local VerticalSpan = require('ui/widget/verticalspan')
local _ = require('gettext')
local Screen = Device.screen

local Action = Button:extend{}
function Action:init()
    self.text_font_face = 'cfont'
    self.text_font_size = 18
    self.bordersize, self.margin, self.padding = 0, 0, 0
    Button.init(self)
    local old = self.frame
    local pad = Screen:scaleBySize(self.kind == 'quiet' and 8 or 14)
    local background = self.kind == 'hero' and BB.COLOR_BLACK
        or self.kind == 'tile' and Style.surface or BB.COLOR_WHITE
    local foreground = self.kind == 'hero' and BB.COLOR_WHITE
        or BB.COLOR_BLACK
    local border = self.kind == 'tile' and Style.border or 0
    local text_width = math.max(1, self.width - 2 * (pad+border))
    local title = TextBoxWidget:new{
        text = self.text, width = text_width,
        face = Font:getFace('cfont', self.kind == 'hero' and 22 or 18),
        bold = self.kind == 'hero' or self.kind == 'tile',
        fgcolor = foreground, bgcolor = background,
    }
    local content = VerticalGroup:new{align='left', title}
    if self.enabled == false then self.description = _('Unavailable') end
    if self.description then
        table.insert(content, VerticalSpan:new{width=Screen:scaleBySize(4)})
        table.insert(content, TextBoxWidget:new{
            text = self.description, width = text_width,
            face = Font:getFace('cfont', 14),
            fgcolor = self.kind == 'hero' and BB.COLOR_WHITE or BB.COLOR_BLACK,
            bgcolor = background,
        })
    end
    local height = math.max(self.height or 0, content:getSize().h + 2 * (pad+border))
    self.frame = FrameContainer:new{
        width=self.width, height=height, padding=pad,
        bordersize=self.kind == 'tile' and Style.border or 0,
        color=BB.COLOR_BLACK, radius=Style.radius, background=background,
        CenterContainer:new{
            dimen=Geom:new{w=text_width,h=height-2*(pad+border)}, content,
        },
    }
    self[1], self.label_widget = self.frame, title
    -- Preserve the geometry object already referenced by Button's gestures.
    self.dimen.w, self.dimen.h = self.width, height
    old:free()
end

local ActionPanel = FocusManager:extend{
    modal = true,
    title = '',
    buttons = nil, -- action definitions, retained for callers and inspection
}

function ActionPanel:init()
    local margin, padding = Screen:scaleBySize(12), Screen:scaleBySize(18)
    local gap = Screen:scaleBySize(10)
    local width = math.min(Screen:getWidth()-2*margin, Screen:scaleBySize(540))
    local inner = width - 2 * (padding + Style.border)
    local header = VerticalGroup:new{align='left'}
    if self.context then
        table.insert(header, TextWidget:new{
            text=self.context, face=Font:getFace('cfont',14),
            fgcolor=Style.muted, max_width=inner-Screen:scaleBySize(42),
        })
        table.insert(header, VerticalSpan:new{width=Screen:scaleBySize(6)})
    end
    table.insert(header, TextBoxWidget:new{
        text=self.title, width=inner-Screen:scaleBySize(42),
        face=Font:getFace('cfont',24), bold=true,
        height=Screen:scaleBySize(84), height_adjust=true,
        height_overflow_show_ellipsis=true,
    })
    local close = Button:new{
        icon='close', icon_width=Style.icon.size, icon_height=Style.icon.size,
        width=Screen:scaleBySize(32), height=Screen:scaleBySize(36),
        bordersize=0, padding=0, text_font_size=26, show_parent=self,
        callback=function() self:onClose() end,
    }
    local header_row = HorizontalGroup:new{align='top',header,
        HorizontalSpan:new{width=Screen:scaleBySize(10)},close}
    local function buildBody(body_width)
        local body = VerticalGroup:new{align='left'}
        self.layout, self.action_widgets = {{close}}, {}
        for row_index, row in ipairs(self.buttons or {}) do
            local kind = (self.row_styles or {})[row_index] or 'quiet'
            local action_width = math.floor((body_width - gap*(#row-1))/#row)
            local group, focus_row = HorizontalGroup:new{align='top'}, {}
            for index, definition in ipairs(row) do
                local action = Action:new{
                    text=definition.text, description=definition.description,
                    kind=kind, enabled=definition.enabled ~= false,
                    width=index == #row and body_width-(action_width+gap)*(#row-1) or action_width,
                    height=Screen:scaleBySize(kind == 'quiet' and 44 or kind == 'hero' and 76 or 68),
                    show_parent=self, callback=definition.callback,
                }
                table.insert(group,action)
                table.insert(focus_row,action)
                table.insert(self.action_widgets,action)
                if index < #row then table.insert(group,HorizontalSpan:new{width=gap}) end
            end
            table.insert(body,group)
            table.insert(self.layout,focus_row)
            if row_index < #self.buttons then table.insert(body,VerticalSpan:new{width=gap}) end
        end
        return body
    end
    local body = buildBody(inner)
    local max_body = math.max(Screen:scaleBySize(48), Screen:getHeight()
        - 2*margin - 2*(padding+Style.border) - header_row:getSize().h - gap)
    local body_widget = body
    if body:getSize().h > max_body then
        -- Rebuild at the cropped width only when a scrollbar is needed.
        body:free()
        body = buildBody(inner - ScrollableContainer:getScrollbarWidth())
        self.cropping_widget = ScrollableContainer:new{
            dimen=Geom:new{w=inner,h=max_body}, show_parent=self,
            body,
        }
        body_widget = self.cropping_widget
    end
    self.panel = FrameContainer:new{
        width=width, padding=padding, bordersize=Style.border,
        radius=Screen:scaleBySize(12), color=BB.COLOR_BLACK,
        background=BB.COLOR_WHITE,
        VerticalGroup:new{align='left',header_row,VerticalSpan:new{width=gap},body_widget},
    }
    self[1] = BottomContainer:new{
        dimen=Screen:getSize(),
        FrameContainer:new{
            bordersize=0,padding=0,padding_bottom=margin,
            CenterContainer:new{dimen=Geom:new{w=Screen:getWidth(),h=self.panel:getSize().h},self.panel},
        },
    }
    if Device:hasKeys() then self.key_events.Close={{Device.input.group.Back}} end
    self.ges_events.TapOutside={GestureRange:new{ges='tap',range=Screen:getSize()}}
end

function ActionPanel:onTapOutside(_, ges)
    if self.panel.dimen and not self.panel.dimen:contains(ges.pos) then self:onClose() end
    return true
end
function ActionPanel:onClose()
    if self.closed then return true end
    self.closed = true
    UI:close(self)
    return true
end
function ActionPanel:onShow()
    UI:setDirty(self,function() return 'ui', self.panel.dimen end)
end
function ActionPanel:onCloseWidget()
    UI:setDirty(nil,'flashui',self.panel.dimen)
end
function ActionPanel:onScreenResize()
    -- Dismiss against the old geometry; the board handles the size change.
    self:onClose()
    return false
end
function ActionPanel:onSetRotationMode()
    self:onClose()
    return false
end
function ActionPanel:onFocusMove(args)
    local result = FocusManager.onFocusMove(self,args)
    if self.cropping_widget then
        local focus = self:getFocusItem()
        local crop = self.cropping_widget.dimen
        if focus and focus.dimen and crop and crop.y then
            local delta = focus.dimen.y < crop.y and focus.dimen.y-crop.y
                or focus.dimen.y+focus.dimen.h > crop.y+crop.h
                    and focus.dimen.y+focus.dimen.h-crop.y-crop.h or 0
            if delta ~= 0 then self.cropping_widget:_scrollBy(0,delta,true) end
        end
    end
    return result
end

return ActionPanel
