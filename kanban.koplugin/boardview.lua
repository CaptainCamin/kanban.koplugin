local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local ButtonDialog = require("ui/widget/buttondialog")
local CardDialog = require("carddialog")
local CardView = require("cardview")
local CardMove = require("cardmove")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local Model = require("model")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local Storage = require("storage")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")
local T = require("ffi/util").template
local _ = require("gettext")
local Screen = Device.screen

local MAX_EXPANDED_COLUMNS = 3
local TITLE_LINES = 3
local MIN_TAB_WIDTH = 88
local COLUMN_MARKER_GAP = Screen:scaleBySize(2)

local function buildColumnPages(columns, available_width, min_column_width, collapsed_width, gap)
    local pages = {}
    local first, used_width, expanded_count
    for index, column in ipairs(columns) do
        local width = column.collapsed and collapsed_width or min_column_width
        local next_width = (used_width or 0) + (first and gap or 0) + width
        local too_many_expanded = not column.collapsed
            and expanded_count and expanded_count >= MAX_EXPANDED_COLUMNS
        if first and (next_width > available_width or too_many_expanded) then
            table.insert(pages, { first = first, last = index - 1 })
            first, used_width, expanded_count = nil, nil, nil
            next_width = width
        end
        first = first or index
        used_width = next_width
        if not column.collapsed then
            expanded_count = (expanded_count or 0) + 1
        end
    end
    if first then
        table.insert(pages, { first = first, last = #columns })
    end
    return pages
end

local function measureTitleLines(title, width, face, bold)
    local measurement = TextBoxWidget:new{
        text = title,
        face = face,
        bold = bold,
        width = width,
        height = 1, -- only the first line needs a backing buffer during measurement
        for_measurement_only = true,
    }
    local lines = measurement:getAllLineCount()
    local glyph_extra_height = measurement.line_glyph_extra_height
    measurement:free(true)
    return math.max(1, math.min(TITLE_LINES, lines)), glyph_extra_height
end

local function copy_map(source)
    local copy = {}
    for key, value in pairs(source or {}) do
        copy[key] = value
    end
    return copy
end

local BoardView = InputContainer:extend{
    state = nil, -- storage state; changed only through Model, via commit()
    ui = nil, -- FileManager or ReaderUI that opened the board
    first_column = 1, -- index of the leftmost column shown
    moving_card = nil, -- id of the card picked up by a hold (quick-move)
}

-- Return the number of complete days since the card entered its column.
-- The clock is explicit so the day boundary can be tested deterministically.
local function cardMarkerText(card)
    local markers = {}
    if type(card.notes) == "string" and card.notes:match("%S") then
        table.insert(markers, "¶")
    end
    local checklist = card.checklist or {}
    if #checklist > 0 then
        local done = 0
        for _, item in ipairs(checklist) do
            if item.done then
                done = done + 1
            end
        end
        table.insert(markers, T(_("☑ %1/%2"), done, #checklist))
    end
    local days = Model.daysInColumn(card.moved, os.time)
    if days then
        table.insert(markers, T(_("%1d"), days))
    end
    return #markers > 0 and table.concat(markers, " · ") or nil
end

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
        self.ges_events.Tap = {
            GestureRange:new{ ges = "tap", range = self.dimen },
        }
        self.ges_events.Hold = {
            GestureRange:new{ ges = "hold", range = self.dimen },
        }
        self.ges_events.HoldPan = {
            GestureRange:new{ ges = "hold_pan", range = self.dimen },
        }
        self.ges_events.HoldRelease = {
            GestureRange:new{ ges = "hold_release", range = self.dimen },
        }
    end

    local board = self:getBoard()
    self.title_bar = TitleBar:new{
        width = self.dimen.w,
        align = "center",
        -- The title is the board switcher: the ▼ marks it as tappable.
        title = board and (board.name .. " ▼") or _("Kanban board"),
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
    local outer = Size.padding.large
    local gap = Size.padding.fullscreen
    local min_col_width = math.min(Screen:scaleBySize(220), self.dimen.w - 2 * outer)
    local collapsed_width = math.min(Screen:scaleBySize(48), self.dimen.w - 2 * outer)
    self.column_pages = buildColumnPages(columns, self.dimen.w - 2 * outer,
        min_col_width, collapsed_width, gap)
    local requested_column = math.min(self.first_column, math.max(1, #columns))
    local page_index, page = 1, self.column_pages[1]
    for index, candidate in ipairs(self.column_pages) do
        if requested_column <= candidate.last then
            page_index, page = index, candidate
            break
        end
        page_index, page = index, candidate
    end
    self.current_column_page = page_index
    local first = page and page.first or 1
    self.first_column = first
    local last = page and page.last or 0

    local footer = self:buildFooter(board, first, last)

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
    local collapsed_width = math.min(Screen:scaleBySize(48), self.dimen.w - 2 * outer)
    local available_width = self.dimen.w - 2 * outer - (last - first) * gap
    local collapsed_count, expanded_count = 0, 0
    for index = first, last do
        if board.columns[index].collapsed then
            collapsed_count = collapsed_count + 1
        else
            expanded_count = expanded_count + 1
        end
    end
    local expanded_width = expanded_count > 0
        and math.floor((available_width - collapsed_count * collapsed_width) / expanded_count)
        or nil
    local top = self.title_bar:getSize().h

    local card_border = Size.border.button
    local card_pad = Size.padding.large
    local card_gap = Screen:scaleBySize(8)
    local title_face = Font:getFace("cfont", 18)
    local marker_face = Font:getFace("xx_smallinfofont")
    local marker_measure = TextWidget:new{ text = "¶", face = marker_face }
    local marker_line_h = marker_measure:getSize().h

    local header_h = Screen:scaleBySize(36)
    local header_rule = Size.line.thick * 2
    local pager_h = Screen:scaleBySize(28)
    local pager_gap = card_gap

    -- Quick-move: the picked card gets a heavy border and a light gray fill, and
    -- the headers it can be dropped on turn into solid black bars.
    local heavy = Screen:scaleBySize(4)
    local moving_column = self.moving_card and self:locateCard(self.moving_card)

    self.column_rects = {}
    self.card_targets = {} -- { frame, id }; frame.dimen is set when painted
    self.add_card_targets = {} -- { frame, id = column id }
    self.header_targets = {}
    self.collapsed_targets = {}
    local row = HorizontalGroup:new{ align = "top", HorizontalSpan:new{ width = outer } }
    local x = outer
    for index = first, last do
        local column = board.columns[index]
        local col_w = column.collapsed and collapsed_width or expanded_width
        local column_widget
        if column.collapsed then
            local strip_pad = Size.padding.small
            local inner_pad = card_border + strip_pad
            local inner_w = math.max(1, col_w - 2 * inner_pad)
            local name_probe = TextWidget:new{
                text = column.name,
                face = Font:getFace("x_smallinfofont"),
                max_width = inner_w,
            }
            local name, truncated = name_probe:getFittedText()
            if truncated then
                name = name .. "…"
            end
            column_widget = FrameContainer:new{
                width = col_w,
                height = body_h,
                bordersize = card_border,
                color = Blitbuffer.COLOR_GRAY,
                radius = Size.radius.window,
                padding = strip_pad,
                background = Blitbuffer.COLOR_LIGHT_GRAY,
                CenterContainer:new{
                    dimen = Geom:new{ w = inner_w, h = math.max(1, body_h - 2 * inner_pad) },
                    VerticalGroup:new{
                        align = "center",
                        TextWidget:new{
                            text = name,
                            face = Font:getFace("x_smallinfofont"),
                            fgcolor = Blitbuffer.COLOR_BLACK,
                            max_width = inner_w,
                        },
                        VerticalSpan:new{ width = card_gap },
                        TextWidget:new{
                            text = tostring(#column.cards),
                            face = Font:getFace("xx_smallinfofont"),
                            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                        },
                    },
                },
            }
            table.insert(self.collapsed_targets, { frame = column_widget, id = column.id })
        else
            local text_w = col_w - 2 * (card_border + card_pad)
            local line_h = TextBoxWidget:new{ text = "", width = text_w, face = title_face }:getLineHeight()
            local cards_h = body_h - outer - header_h - header_rule - card_gap - pager_gap - pager_h
            local column_rect = {
                id = column.id,
                rect = Geom:new{ x = x, y = top, w = col_w + gap, h = body_h },
            }
            table.insert(self.column_rects, column_rect)

            local count = #column.cards
            local title_lines = {}
            local marker_texts = {}
            local card_heights = {}
            for position, card_id in ipairs(column.cards) do
                local card = board.cards[card_id]
                local lines, glyph_extra_height = measureTitleLines(
                    card.title, text_w, title_face, card_id == self.moving_card)
                title_lines[card_id] = lines
                local marker_text = cardMarkerText(card)
                marker_texts[card_id] = marker_text
                card_heights[position] = lines * line_h + glyph_extra_height
                    + (marker_text and marker_line_h + COLUMN_MARKER_GAP or 0)
                    + 2 * (card_border + card_pad)
            end
            local add_card_lines, add_card_glyph_extra_height = measureTitleLines(
                _("+ Add card"), text_w, title_face)
            local add_card_height = add_card_lines * line_h + add_card_glyph_extra_height
                + 2 * (card_border + card_pad)
            local pages = {}
            local page_start, page_height
            for position, card_h in ipairs(card_heights) do
                local required_h = card_h + (page_height and card_gap or 0)
                if position == count then
                    required_h = required_h + card_gap + add_card_height
                end
                if page_height and page_height + required_h > cards_h then
                    table.insert(pages, { start = page_start, stop = position - 1 })
                    page_start = position
                    page_height = card_h
                else
                    page_start = page_start or position
                    page_height = (page_height or 0) + required_h
                end
            end
            if page_start then
                table.insert(pages, { start = page_start, stop = count })
            end

            -- Keep the requested card visible after edits and additions.
            local requested_start = self.card_start[column.id] or 1
            local card_page_index = 1
            for page_number, card_page in ipairs(pages) do
                if requested_start <= card_page.stop then
                    card_page_index = page_number
                    break
                end
                card_page_index = page_number
            end
            local card_page = pages[card_page_index]
            local start = card_page and card_page.start or 1
            local stop = card_page and card_page.stop or 0
            self.card_start[column.id] = start
            column_rect.pages = pages
            column_rect.page_index = card_page_index

            local is_target = self.moving_card ~= nil and column ~= moving_column
            local ink = is_target and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
            local paper = is_target and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE
            local badge = FrameContainer:new{
                bordersize = 0,
                radius = Size.radius.window,
                padding = 0,
                padding_left = Size.padding.default,
                padding_right = Size.padding.default,
                background = ink,
                TextWidget:new{
                    text = tostring(count),
                    face = Font:getFace("xx_smallinfofont"),
                    bold = true,
                    fgcolor = paper,
                },
            }
            local badge_w = badge:getSize().w
            local header_pad = card_border + card_pad
            local inner_w = col_w - 2 * header_pad
            local header = FrameContainer:new{
                bordersize = 0,
                background = paper,
                radius = Size.radius.window,
                padding = 0,
                padding_left = header_pad,
                padding_right = header_pad,
                OverlapGroup:new{
                    dimen = Geom:new{ w = inner_w, h = header_h },
                    LeftContainer:new{
                        dimen = Geom:new{ w = inner_w - badge_w - Size.padding.default, h = header_h },
                        TextWidget:new{
                            text = column.name,
                            face = Font:getFace("smallinfofontbold"),
                            max_width = inner_w - badge_w - Size.padding.default,
                            fgcolor = ink,
                        },
                    },
                    RightContainer:new{
                        dimen = Geom:new{ w = inner_w, h = header_h },
                        badge,
                    },
                },
            }
            table.insert(self.header_targets, { frame = header, id = column.id })

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
                        dimen = Geom:new{ w = text_w, h = line_h },
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
                local picked = card.id == self.moving_card
                local title_h = title_lines[card.id] * line_h
                local title = TextBoxWidget:new{
                    text = card.title,
                    face = title_face,
                    bold = picked,
                    width = text_w,
                    height = title_h,
                    height_overflow_show_ellipsis = true,
                    bgcolor = picked and Blitbuffer.COLOR_LIGHT_GRAY or Blitbuffer.COLOR_WHITE,
                }
                local content = title
                if marker_texts[card.id] then
                    content = VerticalGroup:new{
                        align = "left",
                        title,
                        VerticalSpan:new{ width = COLUMN_MARKER_GAP },
                        TextWidget:new{
                            text = marker_texts[card.id],
                            face = marker_face,
                            max_width = text_w,
                            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                            bgcolor = picked and Blitbuffer.COLOR_LIGHT_GRAY or Blitbuffer.COLOR_WHITE,
                        },
                    }
                end
                local frame
                if picked then
                    -- Fill inside the heavy border to avoid white notches.
                    local picked_pad = card_border + card_pad - heavy
                    frame = FrameContainer:new{
                        bordersize = heavy,
                        radius = Size.radius.window,
                        padding = 0,
                        background = Blitbuffer.COLOR_WHITE,
                        FrameContainer:new{
                            bordersize = 0,
                            padding = picked_pad,
                            background = Blitbuffer.COLOR_LIGHT_GRAY,
                            content,
                        },
                    }
                else
                    frame = FrameContainer:new{
                        bordersize = card_border,
                        radius = Size.radius.window,
                        padding = card_pad,
                        background = Blitbuffer.COLOR_WHITE,
                        content,
                    }
                end
                table.insert(self.card_targets, { frame = frame, id = card.id })
                table.insert(group, frame)
                if position < stop then
                    table.insert(group, VerticalSpan:new{ width = card_gap })
                end
            end
            if count == 0 or stop == count then
                table.insert(group, VerticalSpan:new{ width = card_gap })
                local add_card_row = FrameContainer:new{
                    bordersize = card_border,
                    color = Blitbuffer.COLOR_GRAY,
                    radius = Size.radius.window,
                    padding = card_pad,
                    background = Blitbuffer.COLOR_WHITE,
                    TextBoxWidget:new{
                        text = _("+ Add card"),
                        face = title_face,
                        width = text_w,
                        height = add_card_lines * line_h,
                        alignment = "center",
                        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                    },
                }
                table.insert(self.add_card_targets, { frame = add_card_row, id = column.id })
                table.insert(group, add_card_row)
            end

            local used = group:getSize().h
            table.insert(group, VerticalSpan:new{ width = body_h - pager_gap - pager_h - used })
            table.insert(group, VerticalSpan:new{ width = pager_gap })
            local pager = CenterContainer:new{
                dimen = Geom:new{ w = col_w, h = pager_h },
                #pages > 1 and TextWidget:new{
                    text = start == stop
                        and T(_("Card %1 of %2"), start, count)
                        or T(_("Cards %1–%2 of %3"), start, stop, count),
                    face = Font:getFace("xx_smallinfofont"),
                } or VerticalSpan:new{ width = 0 },
            }
            table.insert(group, pager)
            group:resetLayout()
            column_widget = group
        end

        table.insert(row, column_widget)
        if index < last then
            table.insert(row, HorizontalSpan:new{ width = gap })
            x = x + col_w + gap
        end
    end
    return row
end

function BoardView:buildFooter(board, first, last)
    local row_width = self.dimen.w - 2 * Size.padding.large
    local row_height = Screen:scaleBySize(40)
    local row_items = {}
    local columns = board and board.columns or {}
    self.tab_targets = {}

    local function addChevron(icon, enabled, callback, width)
        local button = Button:new{
            icon = icon,
            icon_width = Screen:scaleBySize(20),
            icon_height = Screen:scaleBySize(20),
            width = width,
            height = row_height - 2 * Size.border.button,
            padding_h = 0,
            padding_v = 0,
            bordersize = Size.border.button,
            callback = callback,
            show_parent = self,
        }
        button:enableDisable(enabled)
        table.insert(row_items, button)
    end

    if #columns == 0 then
        table.insert(row_items, TextWidget:new{
            text = _("No columns"),
            face = Font:getFace("x_smallinfofont"),
        })
    else
        local show_all_tabs = #columns * Screen:scaleBySize(MIN_TAB_WIDTH) <= row_width
        local tab_first = show_all_tabs and 1 or first
        local tab_last = show_all_tabs and #columns or last
        local tab_count = tab_last - tab_first + 1
        local arrow_width = show_all_tabs and 0 or Screen:scaleBySize(40)
        local tab_space = row_width - 2 * arrow_width
        local tab_width = math.floor(tab_space / tab_count)
        local tab_font = Font:getFace("smallinfofont", 16)
        local tab_padding_h = Size.padding.small
        local tab_inner_padding = tab_padding_h + Size.border.button
        local count_gap = Screen:scaleBySize(8)

        if not show_all_tabs then
            local left, right = "chevron.left", "chevron.right"
            if BD.mirroredUILayout() then
                left, right = right, left
            end
            addChevron(left, first > 1, function() self:onPrevColumns() end, arrow_width)
        end

        for index = tab_first, tab_last do
            local column = columns[index]
            local this_width = index == tab_last and tab_space - tab_width * (tab_count - 1) or tab_width
            local count_text = tostring(#column.cards)
            local count_widget = TextWidget:new{
                text = count_text,
                face = tab_font,
                bold = true,
                padding = 0,
            }
            local name_width = this_width - 2 * tab_inner_padding - count_widget:getSize().w - count_gap
            local name_widget = TextWidget:new{
                text = column.name,
                face = tab_font,
                bold = true,
                padding = 0,
                max_width = math.max(0, name_width),
            }
            local name, truncated = name_widget:getFittedText()
            if truncated then
                name = name .. "…"
            end
            local tab = Button:new{
                text = name .. " " .. count_text,
                text_font_face = "smallinfofont",
                text_font_size = 16,
                text_font_bold = true,
                avoid_text_truncation = false,
                width = this_width,
                height = row_height - 2 * (Size.padding.small + Size.border.button),
                padding_h = tab_padding_h,
                padding_v = Size.padding.small,
                bordersize = Size.border.button,
                preselect = index >= first and index <= last,
                callback = function()
                    if self.moving_card then
                        CardMove.drop(self, { id = column.id })
                    else
                        self:revealColumn(index)
                        self:refresh()
                    end
                end,
                show_parent = self,
            }
            table.insert(self.tab_targets, { frame = tab, id = column.id })
            table.insert(row_items, tab)
        end

        if not show_all_tabs then
            local left, right = "chevron.left", "chevron.right"
            if BD.mirroredUILayout() then
                left, right = right, left
            end
            addChevron(right, last < #columns, function() self:onNextColumns() end, arrow_width)
        end
    end

    local footer_info = HorizontalGroup:new(row_items)
    local footer_h = math.max(row_height, footer_info:getSize().h)
    return VerticalGroup:new{
        LineWidget:new{
            dimen = Geom:new{ w = self.dimen.w - 2 * Size.padding.large, h = Size.line.thin },
            background = Blitbuffer.COLOR_DARK_GRAY,
        },
        CenterContainer:new{
            dimen = Geom:new{ w = self.dimen.w, h = footer_h },
            footer_info,
        },
    }
end

function BoardView:refresh()
    self:layout()
    UIManager:setDirty(self, "flashui")
end

function BoardView:onNextColumns()
    local page = self.column_pages[self.current_column_page + 1]
    if page then
        self.first_column = page.first
        self:refresh()
    end
    return true
end

function BoardView:onPrevColumns()
    local page = self.column_pages[self.current_column_page - 1]
    if page then
        self.first_column = page.first
        self:refresh()
    end
    return true
end

function BoardView:pageCards(pos, step)
    for _, column in ipairs(self.column_rects or {}) do
        if column.rect:contains(pos) then
            local page = column.pages[column.page_index + step]
            if page then
                self.card_start[column.id] = page.start
                self:refresh()
            end
            return
        end
    end
end

function BoardView:findColumn(column_id)
    for index, column in ipairs(self:getBoard().columns) do
        if column.id == column_id then
            return column, index
        end
    end
end

-- Returns the column holding `card_id` and the card's index in it.
function BoardView:locateCard(card_id)
    for _, column in ipairs(self:getBoard().columns) do
        for index, id in ipairs(column.cards) do
            if id == card_id then
                return column, index
            end
        end
    end
end

-- Show the column page that holds column `index`.
function BoardView:revealColumn(index)
    self.first_column = math.max(1, index)
end

-- Show the column page and card page that hold card `index` of a column.
function BoardView:revealCard(column_id, index)
    local _, column_index = self:findColumn(column_id)
    if not column_index then
        return
    end
    self:revealColumn(column_index)
    self.card_start[column_id] = index
end

-- Start from the first column after switching boards.
function BoardView:resetPosition()
    self.first_column = 1
    self.card_start = {}
end

-- Runs `change`, a function that calls one Model operation and returns its
-- result. On success, saves at once and repaints; `after` can adjust the view
-- position before the repaint.
function BoardView:commit(change, after, refresh_type, undo_message, defer_undo_message, undo_context)
    local board = self:getBoard()
    local previous_board = Model.copyBoard(board)
    local previous_position = {
        first_column = self.first_column,
        card_start = copy_map(self.card_start),
    }
    local ok, err = change()
    if not ok then
        logger.warn("kanban: change rejected:", err)
        UIManager:show(InfoMessage:new{ text = T(_("Could not change the board: %1"), tostring(err)) })
        return false
    end
    local current_board = self:getBoard()
    if current_board and current_board.id == board.id then
        self.state.undo = {
            board = previous_board,
            message = undo_message or _("Change made"),
            context = undo_context,
            first_column = previous_position.first_column,
            card_start = previous_position.card_start,
        }
    else
        self.state.undo = nil
    end
    Storage.save(self.state)
    if after then
        after()
    end
    self:layout()
    UIManager:setDirty(self, refresh_type or "ui")
    if self.card_view then
        self.card_view:onBoardChanged()
    end
    -- Only changes that name themselves (moves, archive, column delete, restore) pop up
    -- an Undo prompt; every change can still be undone from the board menu.
    if self.state.undo and undo_message and not defer_undo_message then
        self:showUndoMessage()
    end
    return true
end

function BoardView:undo()
    local undo = self.state.undo
    if not undo then
        return false
    end
    local ok, err = Model.restoreBoard(self.state, undo.board)
    if not ok then
        logger.warn("kanban: undo failed:", err)
        UIManager:show(InfoMessage:new{ text = T(_("Could not undo the change: %1"), tostring(err)) })
        return false
    end
    self.state.undo = nil
    self.first_column = undo.first_column or 1
    self.card_start = copy_map(undo.card_start)
    Storage.save(self.state)
    self:layout()
    UIManager:setDirty(self, "flashui")
    if self.card_view then
        self.card_view:onBoardChanged()
    end
    return true
end

function BoardView:showUndoMessage()
    local undo = self.state.undo
    if not undo then
        return
    end
    local dialog
    local timeout
    dialog = ButtonDialog:new{
        title = undo.message or _("Change made"),
        modal = true,
        buttons = { {
            {
                text = _("Undo"),
                callback = function()
                    UIManager:close(dialog)
                    self:undo()
                end,
            },
        } },
    }
    local on_close_widget = dialog.onCloseWidget
    dialog.onCloseWidget = function(widget)
        if timeout then
            UIManager:unschedule(timeout)
            timeout = nil
        end
        on_close_widget(widget)
    end
    UIManager:show(dialog)
    timeout = function()
        timeout = nil
        UIManager:close(dialog)
    end
    UIManager:scheduleIn(10, timeout)
end

local function hit(targets, pos)
    for _, target in ipairs(targets or {}) do
        local dimen = target.frame.dimen
        if dimen and dimen.x and dimen:contains(pos) then
            return target.id
        end
    end
end

function BoardView:setMovingCard(card_id)
    self.moving_card = card_id
    if not card_id then
        self.drag_origin, self.dragging, self.drop_preview = nil, nil, nil
    end
    self:layout()
    UIManager:setDirty(self, "ui")
end

function BoardView:onTap(_, ges)
    if self.moving_card then
        local collapsed_column_id = hit(self.collapsed_targets, ges.pos)
        if collapsed_column_id then
            return CardMove.drop(self, { id = collapsed_column_id, header = true })
        end
        return CardMove.drop(self, CardMove.target(self, ges.pos))
    end
    -- The title bar's icons are handled before this; the rest of the bar switches boards.
    local title_dimen = self.title_bar.dimen
    if title_dimen and title_dimen.x and title_dimen:contains(ges.pos) then
        CardDialog.showBoards(self)
        return true
    end
    local card_id = hit(self.card_targets, ges.pos)
    if card_id then
        CardView.show(self, card_id)
        return true
    end
    local collapsed_column_id = hit(self.collapsed_targets, ges.pos)
    if collapsed_column_id then
        local _, column_index = self:findColumn(collapsed_column_id)
        self:commit(function()
            return Model.setColumnCollapsed(self:getBoard(), collapsed_column_id, false)
        end, function()
            self:revealColumn(column_index)
        end)
        return true
    end
    local column_id = hit(self.header_targets, ges.pos)
    if column_id then
        CardDialog.showColumnActions(self, column_id)
        return true
    end
    local add_card_column_id = hit(self.add_card_targets, ges.pos)
    if add_card_column_id then
        CardDialog.editCard(self, add_card_column_id)
        return true
    end
    -- Let taps on the title bar and footer buttons through.
    return false
end

function BoardView:onHold(_, ges)
    return CardMove.hold(self, ges.pos)
end

function BoardView:onHoldPan(_, ges)
    return CardMove.pan(self, ges.pos)
end

function BoardView:onHoldRelease(_, ges)
    if self.moving_card and self.dragging then
        local collapsed_column_id = hit(self.collapsed_targets, ges.pos)
        if collapsed_column_id then
            return CardMove.drop(self, { id = collapsed_column_id, header = true })
        end
    end
    return CardMove.release(self, ges.pos)
end

function BoardView:paintTo(bb, x, y)
    InputContainer.paintTo(self, bb, x, y)
    CardMove.paint(self, bb)
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
    if self.moving_card then
        self:setMovingCard(nil)
    end
    CardDialog.showBoardMenu(self)
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
