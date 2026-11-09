local Blitbuffer = require("ffi/blitbuffer")
local T = require("ffi/util").template
local CardDialog = require("carddialog")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local InputContainer = require("ui/widget/container/inputcontainer")
local Model = require("model")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local Size = require("ui/size")
local Style = require("kanbanstyle")
local LineWidget = require("ui/widget/linewidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local Screen = Device.screen

local CardView = InputContainer:extend{
    board_view = nil,
    card_id = nil,
}

local function hasText(value)
    return type(value) == "string" and value:match("%S") ~= nil
end

local function addSpace(group, height)
    table.insert(group, VerticalSpan:new{ width = height })
end

function CardView.show(board_view, card_id)
    local view = CardView:new{
        board_view = board_view,
        card_id = card_id,
    }
    board_view.card_view = view
    UIManager:show(view, "full")
    return view
end

function CardView:init()
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    self:layout()
end

function CardView:getCard()
    return self.board_view:getBoard().cards[self.card_id]
end

function CardView:layout()
    local card = self:getCard()
    if not card then
        return
    end
    local scroll_offset = self.cropping_widget and self.cropping_widget:getScrolledOffset()

    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.covers_fullscreen = true
    self.title_bar = TitleBar:new{
        width = self.dimen.w,
        title = self.board_view:getBoard().name,
        title_face = Font:getFace("smallinfofontbold"),
        with_bottom_line = true,
        bottom_line_color = Blitbuffer.COLOR_BLACK,
        bottom_line_h_padding = Size.padding.large,
        close_callback = function() self:onClose() end,
        show_parent = self,
    }

    local outer_padding = Size.padding.large
    local control_gap = Size.padding.small
    local control_width = math.floor((self.dimen.w - 2 * outer_padding - 2 * control_gap) / 3)
    local control_row = HorizontalGroup:new{ align = "center" }
    local column = self.board_view:locateCard(self.card_id)
    for index, action in ipairs({
        { text = _("Edit"), callback = function()
            CardDialog.editCard(self.board_view, column.id, self.card_id)
        end },
        { text = _("Move to…"), callback = function()
            CardDialog.moveCardTo(self.board_view, self.card_id)
        end },
        { text = _("More…"), callback = function()
            CardDialog.showCardActions(self.board_view, self.card_id)
        end },
    }) do
        if index > 1 then
            table.insert(control_row, HorizontalSpan:new{ width = control_gap })
        end
        table.insert(control_row, Style.button{
            text = action.text, callback = action.callback, width = control_width,
            text_font_face = "cfont", text_font_size = 18,
            bordersize = Style.border, radius = Style.radius,
            background = index == 1 and Style.surface or Blitbuffer.COLOR_WHITE,
            show_parent = self,
        })
    end
    local controls = FrameContainer:new{
        bordersize = 0,
        padding_top = Size.padding.small, padding_bottom = Size.padding.small,
        padding_left = outer_padding, padding_right = outer_padding,
        background = Blitbuffer.COLOR_WHITE, control_row,
    }

    local scroll_gutter = ScrollableContainer:getScrollbarWidth()
    local content_width = math.max(1, self.dimen.w - scroll_gutter - 2 * outer_padding)
    local content = VerticalGroup:new{ align = "left" }
    table.insert(content, TextBoxWidget:new{
        text = column and column.name or "",
        width = content_width,
        face = Font:getFace("smallinfofont"),
        fgcolor = Blitbuffer.COLOR_BLACK,
    })
    addSpace(content, Size.padding.small)
    table.insert(content, TextBoxWidget:new{
        text = card.title,
        width = content_width,
        face = Font:getFace("cfont", 28),
        bold = true,
    })
    local issue = require("githubdialog").issue(self.board_view:getBoard(), card.id)
    if issue then
        table.insert(content, TextBoxWidget:new{
            text = "GitHub #" .. issue.number .. "\n" .. issue.url,
            width = content_width, face = Font:getFace("smallinfofont"),
        })
    end
    local labels = Model.labelText(self.board_view:getBoard(), card)
    if labels ~= "" then
        table.insert(content, TextBoxWidget:new{
            text = labels, width = content_width, face = Font:getFace("smallinfofont"),
        })
    end
    addSpace(content, Size.padding.large)
    table.insert(content, LineWidget:new{
        dimen = Geom:new{w=content_width,h=Style.border}, background = Style.rule,
    })
    addSpace(content, Size.padding.large)
    table.insert(content, TextWidget:new{
        text = _("Notes"),
        face = Font:getFace("cfont", 18),
        bold = true,
    })
    addSpace(content, Size.padding.small)
    if hasText(card.notes) then
        table.insert(content, TextBoxWidget:new{
            text = card.notes,
            width = content_width,
            face = Font:getFace("cfont", 20),
        })
    else
        table.insert(content, TextWidget:new{
            text = _("No notes."),
            face = Font:getFace("smallinfofont"),
            fgcolor = Blitbuffer.COLOR_BLACK,
        })
    end

    addSpace(content, Size.padding.large)
    local checklist = card.checklist or {}
    local completed = 0
    for _, item in ipairs(checklist) do
        if item.done then completed = completed + 1 end
    end
    table.insert(content, TextWidget:new{
        text = #checklist > 0 and T(_("Checklist · %1 of %2 done"), completed, #checklist) or _("Checklist"),
        face = Font:getFace("cfont", 18),
        bold = true,
    })
    addSpace(content, Size.padding.small)
    self.checklist_targets = {}
    if #checklist == 0 then
        table.insert(content, TextWidget:new{
            text = _("No checklist items."),
            face = Font:getFace("smallinfofont"),
            fgcolor = Blitbuffer.COLOR_BLACK,
        })
    else
        local item_gap = Size.padding.small
        local more_width = Screen:scaleBySize(52)
        local toggle_width = math.max(1, content_width - more_width - item_gap)
        for index, item in ipairs(checklist) do
            local item_index = index
            local row = HorizontalGroup:new{
                align = "top",
                Style.button{
                    text = (item.done and "☑ " or "☐ ") .. item.text,
                    width = toggle_width,
                    height = Screen:scaleBySize(64),
                    bordersize = 0,
                    padding_h = Size.padding.small,
                    align = "left",
                    text_font_face = "smallinfofont",
                    text_font_size = 20,
                    text_font_bold = false,
                    show_parent = self,
                    callback = function()
                        self:changeChecklist(function(board)
                            return Model.toggleChecklistItem(board, self.card_id, item_index)
                        end)
                    end,
                },
                HorizontalSpan:new{ width = item_gap },
                Style.button{
                    text = _("…"), width = more_width,
                    height = Screen:scaleBySize(64),
                    bordersize = 0,
                    text_font_size = 20,
                    show_parent = self,
                    callback = function() self:showChecklistActions(item_index) end,
                },
            }
            table.insert(self.checklist_targets, row[1])
            table.insert(content, row)
            table.insert(content, LineWidget:new{
                dimen = Geom:new{w=content_width,h=Style.border}, background = Style.rule,
            })
            addSpace(content, Size.padding.small)
        end
    end
    addSpace(content, Size.padding.small)
    self.checklist_add_button = Style.button{
        text = _("+ Add checklist item"), width = content_width,
        text_font_face = "cfont", text_font_size = 18,
        bordersize = Style.border, background = Style.surface, radius = Style.radius,
        show_parent = self, callback = function() self:promptChecklistItem() end,
    }
    table.insert(content, self.checklist_add_button)
    addSpace(content, outer_padding)

    local body_y = self.title_bar:getSize().h + controls:getSize().h
    self.cropping_widget = ScrollableContainer:new{
        dimen = Geom:new{
            x = 0,
            y = body_y,
            w = self.dimen.w,
            h = self.dimen.h - body_y,
        },
        show_parent = self,
        FrameContainer:new{
            width = self.dimen.w - scroll_gutter,
            padding = outer_padding,
            bordersize = 0,
            background = Blitbuffer.COLOR_WHITE,
            content,
        },
    }
    self.cropping_widget:setScrolledOffset(scroll_offset)
    self[1] = FrameContainer:new{
        width = self.dimen.w,
        height = self.dimen.h,
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            self.title_bar,
            controls,
            self.cropping_widget,
        },
    }
end

function CardView:showChecklistActions(item_index)
    local item = self:getCard().checklist[item_index]
    local dialog
    dialog = Style.dialog{
        title = item.text,
        buttons = {
            { { text = _("Edit"), callback = function()
                UIManager:close(dialog)
                self:promptChecklistItem(item_index)
            end } },
            { { text = _("Delete"), callback = function()
                UIManager:close(dialog)
                self.board_view:commit(function()
                    return Model.deleteChecklistItem(self.board_view:getBoard(), self.card_id, item_index)
                end, nil, nil, _("Checklist item deleted"))
            end } },
            { { text = _("Cancel"), callback = function() UIManager:close(dialog) end } },
        },
    }
    UIManager:show(dialog)
end

function CardView:changeChecklist(change)
    local board = self.board_view:getBoard()
    self.board_view:commit(function()
        return change(board)
    end)
end

function CardView:promptChecklistItem(item_index)
    local card = self:getCard()
    local dialog
    local function save()
        local text = dialog:getInputText()
        if not hasText(text) then
            UIManager:show(InfoMessage:new{
                text = _("A checklist item needs text."),
                timeout = 2,
            })
            return
        end
        UIManager:close(dialog)
        local board = self.board_view:getBoard()
        self.board_view:commit(function()
            if item_index then
                return Model.editChecklistItem(board, self.card_id, item_index, text)
            end
            return Model.addChecklistItem(board, self.card_id, text)
        end)
    end
    dialog = InputDialog:new{
        title = item_index and _("Edit checklist item") or _("Add checklist item"),
        input = item_index and card.checklist[item_index].text or "",
        input_hint = _("Checklist item"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function() UIManager:close(dialog) end,
                },
                {
                    text = item_index and _("Save") or _("Add"),
                    is_enter_default = true,
                    callback = save,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function CardView:onBoardChanged()
    local card = self:getCard()
    if not card or card.archived or not self.board_view:locateCard(self.card_id) then
        self:onClose()
        return
    end
    self:layout()
    UIManager:setDirty(self, "ui")
end

function CardView:onClose()
    if self.closed then
        return true
    end
    self.closed = true
    if self.board_view.card_view == self then
        self.board_view.card_view = nil
    end
    local column, index = self.board_view:locateCard(self.card_id)
    if column then
        self.board_view:revealCard(column.id, index)
    end
    self.board_view:layout()
    UIManager:close(self)
    UIManager:setDirty(nil, "full")
    return true
end

function CardView:onScreenResize()
    self.board_view:onScreenResize()
    self:layout()
    UIManager:setDirty(self, "flashui")
    return false
end

function CardView:onSetRotationMode(rotation)
    if rotation == nil or rotation == Screen:getRotationMode() then
        return false
    end
    self.board_view:onSetRotationMode(rotation)
    self:layout()
    UIManager:setDirty(self, "flashui")
    return true
end

return CardView
