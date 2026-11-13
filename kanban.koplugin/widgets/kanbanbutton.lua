-- Custom e-ink friendly button built from KOReader's low-level widget primitives.
local Blitbuffer = require('ffi/blitbuffer')
local CenterContainer = require('ui/widget/container/centercontainer')
local CheckMark = require('ui/widget/checkmark')
local FrameContainer = require('ui/widget/container/framecontainer')
local Geom = require('ui/geometry')
local GestureRange = require('ui/gesturerange')
local HorizontalGroup = require('ui/widget/horizontalgroup')
local HorizontalSpan = require('ui/widget/horizontalspan')
local IconWidget = require('ui/widget/iconwidget')
local InputContainer = require('ui/widget/container/inputcontainer')
local LeftContainer = require('ui/widget/container/leftcontainer')
local Font = require('ui/font')
local Style = require('kanbanstyle')
local TextWidget = require('ui/widget/textwidget')
local UIManager = require('ui/uimanager')

local KanbanButton = InputContainer:extend{
    text = nil,
    text_func = nil,
    checked_func = nil,
    leading_widget = nil,
    leading_icon = nil,
    leading_icon_width = nil,
    leading_icon_height = nil,
    leading_spacing = nil,
    icon = nil,
    icon_width = nil,
    icon_height = nil,
    icon_rotation_angle = 0,
    align = "center",
    preselect = false,
    callback = nil,
    enabled = true,
    enabled_func = nil,
    hidden = false,
    allow_tap_when_disabled = false,
    readonly = nil,
    margin = 0,
    bordersize = Style.border,
    border_color = nil,
    background = nil,
    radius = Style.button.radius,
    padding = nil,
    padding_h = nil,
    padding_v = nil,
    width = nil,
    max_width = nil,
    height = nil,
    avoid_text_truncation = true,
    text_font_face = "cfont",
    text_font_size = Style.size.body,
    text_font_bold = true,
    -- ButtonTable-style aliases used by dialog definitions.
    font_size = nil,
    font_bold = nil,
}

function KanbanButton:init()
    if self.text_func then
        self.text = self.text_func()
    end
    if self.font_size then
        self.text_font_size = self.font_size
    end
    if self.font_bold ~= nil then
        self.text_font_bold = self.font_bold
    end
    self.padding_h = self.padding_h or self.padding or Style.space.sm
    self.padding_v = self.padding_v or self.padding or Style.space.xs
    self.enabled = self.enabled ~= false
    self._base_enabled = self.enabled

    local display_text = self.text or ""

    local text_color = self.enabled and (self.preselect and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK)
        or Style.palette.disabled
    local face = Font:getFace(self.text_font_face, self.text_font_size)
    if self.leading_widget == nil and self.checked_func then
        self.leading_widget = CheckMark:new{
            checked = self.checked_func() == true,
            face = face,
            enabled = self.enabled,
        }
    elseif self.leading_widget == nil and self.leading_icon then
        self.leading_widget = IconWidget:new{
            icon = self.leading_icon,
            width = self.leading_icon_width or Style.icon.size,
            height = self.leading_icon_height or Style.icon.size,
            dim = not self.enabled,
            invert = self.preselect,
        }
    end
    local leading_width = self.leading_widget and (self.leading_widget:getSize().w + (self.leading_spacing or Style.space.xs)) or 0

    local content_width = self.width and self.width - 2 * (self.margin + self.bordersize + self.padding_h) or nil
    local content_height = self.height and self.height - 2 * (self.margin + self.bordersize + self.padding_v) or nil

    local content
    if self.icon then
        local icon_widget = IconWidget:new{
            icon = self.icon,
            width = self.icon_width or Style.icon.size,
            height = self.icon_height or Style.icon.size,
            rotation_angle = self.icon_rotation_angle,
            dim = not self.enabled,
            invert = self.preselect,
        }
        content = CenterContainer:new{
            dimen = Geom:new{ w = content_width or icon_widget:getSize().w,
                              h = content_height or icon_widget:getSize().h },
            icon_widget,
        }
        self.icon_widget = icon_widget
    else
        self.label_widget = TextWidget:new{
            text = display_text,
            face = face,
            bold = self.text_font_bold,
            fgcolor = text_color,
            max_width = content_width and (content_width - leading_width) or nil,
            padding = 0,
        }
        local label = self.label_widget
        if self.leading_widget then
            label = HorizontalGroup:new{
                align = "center",
                self.leading_widget,
                HorizontalSpan:new{ width = self.leading_spacing or Style.space.xs },
                self.label_widget,
            }
        end
        local align_container = self.align == "left" and LeftContainer or CenterContainer
        content = align_container:new{
            dimen = Geom:new{ w = content_width or label:getSize().w,
                              h = content_height or label:getSize().h },
            label,
        }
    end

    local inverted = self.preselect
    self.frame = FrameContainer:new{
        width = self.width,
        height = self.height,
        bordersize = self.bordersize,
        color = self.border_color or (self.bordersize > 0 and (inverted and Blitbuffer.COLOR_BLACK or Style.palette.rule) or Blitbuffer.COLOR_BLACK),
        radius = self.radius,
        margin = self.margin,
        padding_top = self.padding_v,
        padding_bottom = self.padding_v,
        padding_left = self.padding_h,
        padding_right = self.padding_h,
        background = inverted and Blitbuffer.COLOR_BLACK or (self.background or Style.palette.paper),
        show_parent = self.show_parent,
        content,
    }
    self[1] = self.frame
    self.dimen = self.frame:getSize()
    self._min_needed_width = content_width and (content_width + 2 * (self.margin + self.bordersize + self.padding_h)) or nil

    local range = self.dimen
    self.ges_events = {
        TapSelectButton = { GestureRange:new{ ges = "tap", range = range } },
        HoldSelectButton = { GestureRange:new{ ges = "hold", range = range } },
        HoldReleaseSelectButton = { GestureRange:new{ ges = "hold_release", range = range } },
    }
end

function KanbanButton:getDisplayText()
    return self.text or ""
end

function KanbanButton:enableDisable(enabled)
    self.enabled = self._base_enabled and enabled ~= false
    if self.label_widget then
        self.label_widget.fgcolor = self.enabled and (self.preselect and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK) or Style.palette.disabled
        if self.label_widget.update then self.label_widget:update() end
    end
    if self.leading_widget and self.leading_widget.dim ~= nil then
        self.leading_widget.dim = not self.enabled
    end
    if self.leading_widget and self.leading_widget.checkable ~= nil then
        self.leading_widget.enabled = self.enabled
        self.leading_widget:free()
        self.leading_widget:init()
    end
end

function KanbanButton:enable() self:enableDisable(true) end
function KanbanButton:disable() self:enableDisable(false) end

function KanbanButton:setText(text)
    self.text = text
    if not self.label_widget then return end
    if self.width and self.label_widget.max_width == self.width then
        self.label_widget:setText(self:getDisplayText())
    else
        self:free()
        self:init()
    end
end

function KanbanButton:setIcon(icon)
    self.icon = icon
    self:free()
    self:init()
end

function KanbanButton:_setPressed(pressed)
    if not self.frame then return end
    if pressed then
        self._feedback = {
            background = self.frame.background,
            color = self.frame.color,
            fgcolor = self.label_widget and self.label_widget.fgcolor,
            bgcolor = self.label_widget and self.label_widget.bgcolor,
            icon_invert = self.icon_widget and self.icon_widget.invert,
        }
        self.frame.background = Blitbuffer.COLOR_BLACK
        self.frame.color = Blitbuffer.COLOR_BLACK
        if self.label_widget then
            self.label_widget.fgcolor = Blitbuffer.COLOR_WHITE
            self.label_widget.bgcolor = Blitbuffer.COLOR_BLACK
            if self.label_widget.update then self.label_widget:update() end
        end
        if self.icon_widget then self.icon_widget.invert = true end
    elseif self._feedback then
        self.frame.background = self._feedback.background
        self.frame.color = self._feedback.color
        if self.label_widget then
            self.label_widget.fgcolor = self._feedback.fgcolor or Blitbuffer.COLOR_BLACK
            self.label_widget.bgcolor = self._feedback.bgcolor
            if self.label_widget.update then self.label_widget:update() end
        end
        if self.icon_widget then self.icon_widget.invert = self._feedback.icon_invert end
        self._feedback = nil
    end
end

function KanbanButton:_repaint(dimen)
    dimen = dimen or (self.frame and self.frame.dimen)
    if not dimen then return end
    if self.frame.dimen then
        UIManager:widgetRepaint(self.frame, self.frame.dimen.x, self.frame.dimen.y)
    end
    UIManager:setDirty(nil, "fast", dimen)
end

function KanbanButton:onTapSelectButton()
    if self.enabled_func then
        self:enableDisable(self.enabled_func())
    end
    if not self.enabled then
        return self.allow_tap_when_disabled == true
    end
    if not G_reader_settings:nilOrTrue("flash_ui") then
        if self.callback then self.callback() end
        return true
    end
    local dimen = self.frame.dimen
    self:_setPressed(true)
    self:_repaint(dimen)
    UIManager:forceRePaint()
    UIManager:yieldToEPDC()
    self:_setPressed(false)
    self:_repaint(dimen)
    if self.callback then self.callback() end
    UIManager:forceRePaint()
    return true
end

function KanbanButton:onHoldSelectButton() return self:onTapSelectButton() end
function KanbanButton:onHoldReleaseSelectButton() return true end

function KanbanButton:getMinNeededWidth()
    if self._min_needed_width then return self._min_needed_width end
    return self.dimen and self.dimen.w or 0
end

function KanbanButton:refresh()
    if self.checked_func then
        if self.text_func then self.text = self.text_func() end
        self:free()
        self:init()
    elseif self.text_func then
        self:setText(self.text_func())
    end
end

return KanbanButton
