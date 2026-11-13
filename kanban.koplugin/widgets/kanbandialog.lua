-- Token-styled modal dialog used for confirmations, messages, choices and text prompts.
local Device = require('device')
local Geom = require('ui/geometry')
local GestureRange = require('ui/gesturerange')
local FrameContainer = require('ui/widget/container/framecontainer')
local CenterContainer = require('ui/widget/container/centercontainer')
local HorizontalGroup = require('ui/widget/horizontalgroup')
local HorizontalSpan = require('ui/widget/horizontalspan')
local InputContainer = require('ui/widget/container/inputcontainer')
local InputText = require('ui/widget/inputtext')
local ScrollableContainer = require('ui/widget/container/scrollablecontainer')
local Style = require('kanbanstyle')
local TextBoxWidget = require('ui/widget/textboxwidget')
local TextWidget = require('ui/widget/textwidget')
local UIManager = require('ui/uimanager')
local VerticalGroup = require('ui/widget/verticalgroup')
local VerticalSpan = require('ui/widget/verticalspan')
local _ = require('gettext')
local Screen = Device.screen
local KanbanButton = require('widgets/kanbanbutton')

local KanbanDialog = InputContainer:extend{covers_fullscreen = true, is_always_active = true}

local function hasText(value)
    return type(value) == "string" and value:match("%S") ~= nil
end

function KanbanDialog:init()
    self.title = self.title or ""
    self.message = self.message or self.text or self.body
    self.dismissable = self.dismissable ~= false
    self.modal = self.modal ~= false
    self.width = self.width or math.min(Screen:getWidth() - 2 * Style.space.lg, Screen:scaleBySize(540))
    self.max_height = self.max_height or math.floor(Screen:getHeight() * 0.78)

    if self.ok_text or self.ok_callback or self.cancel_text or self.cancel_callback then
        self.ok_text = self.ok_text or _("OK")
        self.cancel_text = self.cancel_text or _("Cancel")
        local ok_callback = self.ok_callback
        local cancel_callback = self.cancel_callback
        self.buttons = self.buttons or {{
            { text = self.cancel_text, callback = function()
                if cancel_callback then cancel_callback() end
                UIManager:close(self)
            end },
            { text = self.ok_text, is_enter_default = true, callback = function()
                if ok_callback then ok_callback() end
                UIManager:close(self)
            end },
        }}
    end
    self.buttons = self.buttons or {}
    if self.enter_callback == nil and not self.allow_newline then
        for _, row in ipairs(self.buttons) do
            for _, definition in ipairs(row) do
                if definition.is_enter_default and definition.callback then
                    self.enter_callback = definition.callback
                    break
                end
            end
            if self.enter_callback then break end
        end
    end

    local has_input = self.input ~= nil or self.input_hint ~= nil or self.input_type ~= nil or self.text_type ~= nil
    if has_input then
        local input_height = Screen:scaleBySize(self.allow_newline and 88 or 48)
        self.input_widget = InputText:new{
            text = self.input or "",
            hint = self.input_hint,
            input_type = self.input_type,
            text_type = self.text_type,
            width = self.width - 2 * Style.space.lg - 2 * Style.border,
            height = input_height,
            scroll = true,
            face = self.input_face or Style.font.body,
            focused = true,
            parent = self,
            margin = 0,
            padding = Style.space.sm,
            allow_newline = self.allow_newline == true,
            bordersize = Style.border,
            enter_callback = self.enter_callback,
        }
        self._input_widget = self.input_widget
        if (Device:hasKeyboard() or Device:hasScreenKB()) and G_reader_settings:nilOrFalse("virtual_keyboard_enabled") then
            self.skip_first_show_keyboard = true
        end
    end

    if Device:hasKeys() then
        self.key_events = self.key_events or {}
        self.key_events.Close = { { Device.input.group.Back } }
    end
    self.ges_events = self.ges_events or {}
    self.ges_events.TapClose = { GestureRange:new{
        ges = "tap",
        range = function() return Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() } end,
    } }

    self:build()
    self.info_style = self.info_style or (self.title == "" and #self.buttons == 0 and hasText(self.message))
    if self.timeout then
        self._timeout_func = function()
            self._timeout_func = nil
            UIManager:close(self)
        end
        UIManager:scheduleIn(self.timeout, self._timeout_func)
    end
end

function KanbanDialog:build()
    local pad = Style.space.lg
    local gap = Style.space.md
    local content_width = self.width - 2 * pad - 2 * Style.border
    self.content_width = content_width
    local children = {}

    if hasText(self.title) then
        children[#children + 1] = TextBoxWidget:new{
            text = self.title,
            width = content_width,
            face = Style.font.title,
            bold = true,
            fgcolor = Style.palette.ink,
            bgcolor = Style.palette.paper,
            alignment = self.title_align or "left",
            padding = 0,
        }
    end

    if hasText(self.message) then
        children[#children + 1] = VerticalSpan:new{ width = Style.space.xs }
        children[#children + 1] = TextBoxWidget:new{
            text = self.message,
            width = content_width,
            face = self.message_face or Style.font.body,
            fgcolor = self.message_fgcolor or Style.palette.muted,
            bgcolor = Style.palette.paper,
            alignment = "left",
            padding = 0,
        }
    end

    if self.input_widget then
        children[#children + 1] = VerticalSpan:new{ width = Style.space.sm }
        children[#children + 1] = self.input_widget
    end

    for _, widgets in ipairs(self.extra_widgets or {}) do
        children[#children + 1] = VerticalSpan:new{ width = gap }
        children[#children + 1] = widgets
    end

    if #self.buttons > 0 then
        children[#children + 1] = VerticalSpan:new{ width = gap }
    end

    local button_rows = {}
    self.button_widgets = {}
    local gap_w = Style.space.sm
    for row_index, row in ipairs(self.buttons) do
        local count = #row
        local button_width = math.floor((content_width - gap_w * (count - 1)) / count)
        local widgets = {}
        for button_index, definition in ipairs(row) do
            local width = button_width + (button_index == count and (content_width - gap_w * (count - 1)) % count or 0)
            local button = KanbanButton:new{
                text = definition.text,
                callback = definition.callback,
                width = width,
                height = self.button_height or Style.button.height,
                bordersize = definition.bordersize == nil and Style.border or definition.bordersize,
                background = definition.background,
                preselect = definition.preselect,
                radius = definition.radius or Style.button.radius,
                padding_h = definition.padding_h or Style.space.md,
                padding_v = definition.padding_v or Style.space.xs,
                align = definition.align,
                avoid_text_truncation = definition.avoid_text_truncation,
                text_font_face = definition.font_face or "cfont",
                text_font_size = definition.font_size or Style.size.body,
                text_font_bold = definition.font_bold ~= false,
                enabled = definition.enabled,
                checked_func = definition.checked_func,
                id = definition.id,
                show_parent = self,
            }
            widgets[#widgets + 1] = button
            self.button_widgets[#self.button_widgets + 1] = button
        end
        local row_widget = HorizontalGroup:new{ spacing = gap_w, align = "center", unpack(widgets) }
        button_rows[#button_rows + 1] = row_widget
        if row_index < #self.buttons then
            children[#children + 1] = VerticalSpan:new{ width = gap_w }
        end
        children[#children + 1] = row_widget
    end

    local content = VerticalGroup:new{ align = "left", unpack(children) }
    local content_height = content:getSize().h
    local body = content
    if content_height > self.max_height - 2 * pad - 2 * Style.border then
        body = ScrollableContainer:new{
            dimen = Geom:new{ w = content_width, h = self.max_height - 2 * pad - 2 * Style.border },
            content,
        }
    end

    self.card = FrameContainer:new{
        bordersize = Style.border,
        color = Style.palette.rule,
        radius = Style.radius_large,
        padding = pad,
        background = Style.palette.paper,
        body,
    }

    local screen_size = Geom:new{ w = Screen:getWidth(), h = Screen:getHeight() }
    local scrim = FrameContainer:new{
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        bordersize = 0,
        padding = 0,
        margin = 0,
        background = self.modal and Style.palette.scrim or nil,
        CenterContainer:new{ dimen = screen_size, self.card },
    }
    self[1] = scrim
    self.dimen = screen_size
end

function KanbanDialog:onTapClose(_, ges)
    local pos = ges and ges.pos
    if self.input_widget and self.input_widget:isKeyboardVisible() then
        self.input_widget:onCloseKeyboard()
        return true
    end
    if self.info_style and self.dismissable then
        UIManager:close(self)
        return true
    end
    local dimen = self.card and self.card.dimen
    if self.dismissable and dimen and pos and pos:notIntersectWith(dimen) then
        UIManager:close(self)
    end
    return true
end

function KanbanDialog:onClose()
    if self.dismissable then
        UIManager:close(self)
    end
    return true
end
function KanbanDialog:onShow() end

function KanbanDialog:onCloseWidget()
    if self._timeout_func then
        UIManager:unschedule(self._timeout_func)
        self._timeout_func = nil
    end
    if self.dismiss_callback then
        local callback = self.dismiss_callback
        self.dismiss_callback = nil
        callback()
    end
    if self.input_widget then self.input_widget:onCloseWidget() end
end

function KanbanDialog:addWidget(widget)
    self.extra_widgets = self.extra_widgets or {}
    self.extra_widgets[#self.extra_widgets + 1] = widget
    self:build()
end

function KanbanDialog:getAddedWidgetAvailableWidth()
    return self.content_width or (self.width - 2 * Style.space.lg - 2 * Style.border)
end

function KanbanDialog:getFocusableWidgetXY() return nil, nil end
function KanbanDialog:getInputText()
    return self.input_widget and self.input_widget:getText() or ""
end

function KanbanDialog:setInputText(text)
    if self.input_widget then self.input_widget:setText(text) end
end

function KanbanDialog:getInputValue() return self:getInputText() end
function KanbanDialog:isTextEdited() return self.input_widget and self.input_widget:isTextEdited() or false end
function KanbanDialog:onShowKeyboard(ignore_first_hold_release)
    if self.skip_first_show_keyboard then
        self.skip_first_show_keyboard = nil
        return true
    end
    if self.input_widget then
        self.input_widget:onShowKeyboard(ignore_first_hold_release)
        return true
    end
end
function KanbanDialog:onCloseKeyboard() if self.input_widget then return self.input_widget:onCloseKeyboard() end end
function KanbanDialog:isKeyboardVisible() return self.input_widget and self.input_widget:isKeyboardVisible() or false end
function KanbanDialog:lockKeyboard(toggle) return self.input_widget and self.input_widget:lockKeyboard(toggle) end

function KanbanDialog:getButtonById(id)
    for _, button in ipairs(self.button_widgets or {}) do
        if button.id == id then return button end
    end
end

return KanbanDialog
