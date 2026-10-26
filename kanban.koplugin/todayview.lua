local Blitbuffer = require("ffi/blitbuffer")
local BoardView = require("boardview")
local Button = require("ui/widget/button")
local CardDialog = require("carddialog")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local Model = require("model")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local Size = require("ui/size")
local Storage = require("storage")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local Screen = Device.screen

local TodayView = InputContainer:extend{
    state = nil,
    ui = nil,
    board_view = nil, -- the board it was opened from, replaced when a card is opened
}

function TodayView:init()
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    self:layout()
end

function TodayView:layout()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.covers_fullscreen = true

    self.title_bar = TitleBar:new{
        width = self.dimen.w,
        title = _("Today"),
        title_face = Font:getFace("smallinfofontbold"),
        with_bottom_line = true,
        bottom_line_color = Blitbuffer.COLOR_DARK_GRAY,
        bottom_line_h_padding = Size.padding.large,
        close_callback = function() self:onClose() end,
        show_parent = self,
    }

    local list = VerticalGroup:new{ align = "left" }
    local outer_padding = Size.padding.large
    local scroll_gutter = ScrollableContainer:getScrollbarWidth()
    local list_width = math.max(1, self.dimen.w - scroll_gutter - 2 * outer_padding)
    local card_width = list_width
    for board_index = 1, #self.state.boards do
        local board = self.state.boards[board_index]
        local column = Model.getTodayColumn(board)
        local section = VerticalGroup:new{ align = "left" }
        table.insert(section, FrameContainer:new{
            width = list_width,
            bordersize = 0,
            padding = Size.padding.default,
            background = Blitbuffer.COLOR_LIGHT_GRAY,
            TextWidget:new{
                text = board.name,
                face = Font:getFace("smallinfofontbold"),
                max_width = list_width - 2 * Size.padding.default,
            },
        })
        if not column then
            table.insert(section, TextWidget:new{
                text = _("No in-progress column."),
                face = Font:getFace("x_smallinfofont"),
                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                padding = Size.padding.large,
            })
        elseif #column.cards == 0 then
            table.insert(section, TextWidget:new{
                text = _("No cards in this column."),
                face = Font:getFace("x_smallinfofont"),
                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                padding = Size.padding.large,
            })
        else
            for index, card_id in ipairs(column.cards) do
                local card = board.cards[card_id]
                local selected_board, selected_column = board, column
                local selected_card_id, selected_index = card_id, index
                table.insert(section, Button:new{
                    text = card.title,
                    width = card_width,
                    height = Screen:scaleBySize(52),
                    align = "left",
                    text_font_face = "smallinfofont",
                    text_font_size = 22,
                    text_font_bold = false,
                    avoid_text_truncation = false,
                    padding_h = Size.padding.large,
                    padding_v = Size.padding.small,
                    show_parent = self,
                    callback = function()
                        self:openCard(selected_board, selected_column, selected_card_id, selected_index)
                    end,
                })
                table.insert(section, VerticalSpan:new{ width = Size.padding.small })
            end
        end
        table.insert(list, VerticalSpan:new{ width = Size.padding.large })
        table.insert(list, section)
    end
    table.insert(list, VerticalSpan:new{ width = Size.padding.large })

    local body_y = self.title_bar:getSize().h
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
            list,
        },
    }

    self[1] = FrameContainer:new{
        width = self.dimen.w,
        height = self.dimen.h,
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            self.title_bar,
            self.cropping_widget,
        },
    }
end

function TodayView:openCard(board, column, card_id, card_index)
    if self.state.current_board ~= board.id then
        Model.selectBoard(self.state, board.id)
        Storage.save(self.state)
    end
    local board_view = BoardView:new{
        state = self.state,
        ui = self.ui,
    }
    board_view:revealCard(column.id, card_index)
    board_view:layout()
    UIManager:close(self)
    if self.board_view then
        UIManager:close(self.board_view)
    end
    UIManager:show(board_view, "full")
    CardDialog.showCardActions(board_view, card_id)
end

function TodayView:onClose()
    UIManager:close(self)
    UIManager:setDirty(nil, "full")
    return true
end

function TodayView:onScreenResize()
    self:layout()
    UIManager:setDirty(self, "flashui")
    return false
end

function TodayView:onSetRotationMode(rotation)
    if rotation == nil or rotation == Screen:getRotationMode() then
        return false
    end
    if self.ui.view then
        self.ui.view:onSetRotationMode(rotation)
    else
        self.ui:onSetRotationMode(rotation)
    end
    self:layout()
    UIManager:setDirty(self, "flashui")
    return true
end

return TodayView
