local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local T = require("ffi/util").template
local _ = require("gettext")
local Screen = Device.screen

local MAX_COLUMNS = 3
local TITLE_LINES = 3

local BoardView = InputContainer:extend{
    state = nil, -- storage state, read only here
    ui = nil, -- FileManager or ReaderUI that opened the board
    first_column = 1, -- index of the leftmost column shown
}

function BoardView:init()
    self.card_start = {} -- column id -> index of the first card shown
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
        self.key_events.NextColumns = { { Device.input.group.PgFwd } }
        self.key_events.PrevColumns = { { Device.input.group.PgBack } }
    end
    self:layout()
end

function BoardView:getBoard()
    for _, board in ipairs(self.state.boards) do
        if board.id == self.state.current_board then
            return board
        end
    end
    return self.state.boards[1]
end

function BoardView:layout()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.covers_fullscreen = true -- hint for UIManager:_repaint()
    if Device:isTouchDevice() then
        self.ges_events.Swipe = {
            GestureRange:new{ ges = "swipe", range = self.dimen },
        }
    end

    local board = self:getBoard()
    self.title_bar = TitleBar:new{
        width = self.dimen.w,
        align = "center",
        title = board and board.name or _("Kanban board"),
        title_face = Font:getFace("smallinfofontbold"),
        with_bottom_line = true,
        bottom_line_color = Blitbuffer.COLOR_DARK_GRAY,
        bottom_line_h_padding = Size.padding.large,
        left_icon = "appbar.menu",
        left_icon_tap_callback = function() self:onShowMenu() end,
        close_callback = function() self:onClose() end,
        show_parent = self,
    }

    local columns = board and board.columns or {}
    local min_col_width = Screen:scaleBySize(240)
    self.per_page = math.min(MAX_COLUMNS, math.max(1, math.floor(self.dimen.w / min_col_width)))
    -- Pages start at multiples of per_page; after a rotation, show the page
    -- that holds the previous leftmost column.
    local first = math.floor((math.min(self.first_column, math.max(1, #columns)) - 1) / self.per_page)
        * self.per_page + 1
    self.first_column = first
    self.column_count = #columns
    local last = math.min(#columns, first + self.per_page - 1)

    local footer_text
    if #columns == 0 then
        footer_text = _("No columns")
    elseif first == last then
        footer_text = T(_("Column %1 of %2"), first, #columns)
    else
        footer_text = T(_("Columns %1–%2 of %3"), first, last, #columns)
    end
    -- Chevrons like Menu's page footer: dimmed when there is nothing more that way.
    local footer_info = TextWidget:new{
        text = footer_text,
        face = Font:getFace("x_smallinfofont"),
    }
    if #columns > 0 then
        local chevron_left, chevron_right = "chevron.left", "chevron.right"
        if BD.mirroredUILayout() then
            chevron_left, chevron_right = chevron_right, chevron_left
        end
        local prev_chev = Button:new{
            icon = chevron_left,
            callback = function() self:onPrevColumns() end,
            bordersize = 0,
            show_parent = self,
        }
        local next_chev = Button:new{
            icon = chevron_right,
            callback = function() self:onNextColumns() end,
            bordersize = 0,
            show_parent = self,
        }
        prev_chev:enableDisable(first > 1)
        next_chev:enableDisable(last < #columns)
        local spacer = HorizontalSpan:new{ width = Screen:scaleBySize(32) }
        footer_info = HorizontalGroup:new{
            prev_chev, spacer, footer_info, spacer, next_chev,
        }
    end
    local footer = VerticalGroup:new{
        LineWidget:new{
            dimen = Geom:new{ w = self.dimen.w - 2 * Size.padding.large, h = Size.line.thin },
            background = Blitbuffer.COLOR_DARK_GRAY,
        },
        CenterContainer:new{
            dimen = Geom:new{
                w = self.dimen.w,
                h = math.max(Screen:scaleBySize(32), footer_info:getSize().h),
            },
            footer_info,
        },
    }

    local body_h = self.dimen.h - self.title_bar:getSize().h - footer:getSize().h
    local body
    if #columns == 0 then
        body = CenterContainer:new{
            dimen = Geom:new{ w = self.dimen.w, h = body_h },
            TextWidget:new{
                text = _("This board has no columns."),
                face = Font:getFace("infofont"),
                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            },
        }
    else
        body = self:buildColumns(board, first, last, body_h)
    end

    self[1] = FrameContainer:new{
        width = self.dimen.w,
        height = self.dimen.h,
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left", -- keep a short last column page left-aligned
            self.title_bar,
            body,
            footer,
        },
    }
end

function BoardView:buildColumns(board, first, last, body_h)
    local outer = Size.padding.large
    local gap = Size.padding.fullscreen
    local col_w = math.floor((self.dimen.w - 2 * outer - (self.per_page - 1) * gap) / self.per_page)
    local top = self.title_bar:getSize().h

    local card_border = Size.border.button
    local card_pad = Size.padding.large
    local card_gap = Screen:scaleBySize(8)
    local text_w = col_w - 2 * (card_border + card_pad)
    local title_face = Font:getFace("cfont", 18)
    local line_h = TextBoxWidget:new{ text = "", width = text_w, face = title_face }:getLineHeight()
    local card_h = TITLE_LINES * line_h + 2 * (card_border + card_pad)

    local header_h = Screen:scaleBySize(36)
    local header_rule = Size.line.thick * 2
    local pager_h = Screen:scaleBySize(28)
    local cards_h = body_h - outer - header_h - header_rule - card_gap - pager_h
    local per_column = math.max(1, math.floor((cards_h + card_gap) / (card_h + card_gap)))

    self.column_rects = {}
    local row = HorizontalGroup:new{ align = "top", HorizontalSpan:new{ width = outer } }
    for index = first, last do
        local column = board.columns[index]
        local x = outer + (index - first) * (col_w + gap)
        table.insert(self.column_rects, {
            id = column.id,
            rect = Geom:new{ x = x, y = top, w = col_w + gap, h = body_h },
            per_column = per_column,
        })

        local count = #column.cards
        local start = self.card_start[column.id] or 1
        if start > count then
            start = math.max(1, count - (count - 1) % per_column)
        end
        self.card_start[column.id] = start
        local stop = math.min(count, start + per_column - 1)

        local badge = FrameContainer:new{
            bordersize = 0,
            radius = Size.radius.window,
            padding = 0,
            padding_left = Size.padding.default,
            padding_right = Size.padding.default,
            background = Blitbuffer.COLOR_BLACK,
            TextWidget:new{
                text = tostring(count),
                face = Font:getFace("xx_smallinfofont"),
                bold = true,
                fgcolor = Blitbuffer.COLOR_WHITE,
            },
        }
        local badge_w = badge:getSize().w
        local header = OverlapGroup:new{
            dimen = Geom:new{ w = col_w, h = header_h },
            LeftContainer:new{
                dimen = Geom:new{ w = col_w - badge_w - Size.padding.default, h = header_h },
                TextWidget:new{
                    text = column.name,
                    face = Font:getFace("smallinfofontbold"),
                    max_width = col_w - badge_w - Size.padding.default,
                },
            },
            RightContainer:new{
                dimen = Geom:new{ w = col_w, h = header_h },
                badge,
            },
        }

        local group = VerticalGroup:new{
            align = "left",
            VerticalSpan:new{ width = outer },
            header,
            LineWidget:new{ dimen = Geom:new{ w = col_w, h = header_rule } },
            VerticalSpan:new{ width = card_gap },
        }
        if count == 0 then
            table.insert(group, FrameContainer:new{
                bordersize = card_border,
                color = Blitbuffer.COLOR_GRAY,
                radius = Size.radius.window,
                padding = card_pad,
                CenterContainer:new{
                    dimen = Geom:new{ w = text_w, h = card_h - 2 * (card_border + card_pad) },
                    TextWidget:new{
                        text = _("No cards"),
                        face = Font:getFace("x_smallinfofont"),
                        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                    },
                },
            })
        end
        for position = start, stop do
            local card = board.cards[column.cards[position]]
            table.insert(group, FrameContainer:new{
                bordersize = card_border,
                radius = Size.radius.window,
                padding = card_pad,
                background = Blitbuffer.COLOR_WHITE,
                TextBoxWidget:new{
                    text = card.title,
                    face = title_face,
                    width = text_w,
                    height = TITLE_LINES * line_h,
                    height_overflow_show_ellipsis = true,
                },
            })
            if position < stop then
                table.insert(group, VerticalSpan:new{ width = card_gap })
            end
        end

        -- Cards end at a fixed line so the pager sits at the bottom of every column.
        local used = group:getSize().h
        table.insert(group, VerticalSpan:new{ width = body_h - pager_h - used })
        local pager = CenterContainer:new{
            dimen = Geom:new{ w = col_w, h = pager_h },
            count > per_column and TextWidget:new{
                text = T(_("Cards %1–%2 of %3"), start, stop, count),
                face = Font:getFace("xx_smallinfofont"),
            } or VerticalSpan:new{ width = 0 },
        }
        table.insert(group, pager)
        group:resetLayout() -- getSize() above cached the offsets of fewer children

        table.insert(row, group)
        if index < last then
            table.insert(row, HorizontalSpan:new{ width = gap })
        end
    end
    return row
end

function BoardView:refresh()
    self:layout()
    UIManager:setDirty(self, "flashui")
end

function BoardView:onNextColumns()
    if self.first_column + self.per_page <= self.column_count then
        self.first_column = self.first_column + self.per_page
        self:refresh()
    end
    return true
end

function BoardView:onPrevColumns()
    if self.first_column > 1 then
        self.first_column = self.first_column - self.per_page
        self:refresh()
    end
    return true
end

function BoardView:pageCards(pos, step)
    for _, column in ipairs(self.column_rects or {}) do
        if column.rect:contains(pos) then
            local count = #self:findColumn(column.id).cards
            local start = self.card_start[column.id] + step * column.per_column
            if start >= 1 and start <= count then
                self.card_start[column.id] = start
                self:refresh()
            end
            return
        end
    end
end

function BoardView:findColumn(column_id)
    for _, column in ipairs(self:getBoard().columns) do
        if column.id == column_id then
            return column
        end
    end
end

function BoardView:onSwipe(_, ges)
    local direction = BD.flipDirectionIfMirroredUILayout(ges.direction)
    if direction == "west" then
        return self:onNextColumns()
    elseif direction == "east" then
        return self:onPrevColumns()
    elseif direction == "north" then
        self:pageCards(ges.pos, 1)
        return true
    elseif direction == "south" then
        self:pageCards(ges.pos, -1)
        return true
    end
    -- Let diagonal swipes through (e.g. screenshots).
    return false
end

function BoardView:onShowMenu()
    -- The board menu (columns, archive, boards) arrives with editing in phase 4.
    return true
end

function BoardView:onScreenResize()
    self:refresh()
    return false
end

-- Same approach as Menu:onSetRotationMode: let the underlying FileManager or
-- ReaderUI rotate and relayout first, then rebuild our own layout.
function BoardView:onSetRotationMode(rotation)
    if rotation == nil or rotation == Screen:getRotationMode() then
        return false
    end
    if self.ui.view then
        self.ui.view:onSetRotationMode(rotation)
    else
        self.ui:onSetRotationMode(rotation)
    end
    self:refresh()
    return true
end

function BoardView:onClose()
    UIManager:close(self)
    -- Remove ghosting
    UIManager:setDirty(nil, "full")
    return true
end

return BoardView
