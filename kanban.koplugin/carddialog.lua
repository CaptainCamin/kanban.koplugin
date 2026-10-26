--[[--
Dialogs for the board view: card and column actions, the board menu, the
archive, board management and the card editor.

Every function takes the BoardView as `view`. Changes go through `Model` and
`view:commit()`, which saves the state and repaints the board.
]]

local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Model = require("model")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local T = require("ffi/util").template
local _ = require("gettext")
local N_ = _.ngettext

local CardDialog = {}

local NOTES_PREVIEW = 300 -- characters of notes shown in the card actions dialog

local function hasText(value)
    return type(value) == "string" and value:match("%S") ~= nil
end

local function showDialog(dialog)
    UIManager:show(dialog)
    return dialog
end

-- A one-line text prompt (column and board names).
local function promptName(args)
    local dialog
    dialog = InputDialog:new{
        title = args.title,
        input = args.value or "",
        input_hint = args.hint,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = args.ok_text,
                    is_enter_default = true,
                    callback = function()
                        local value = dialog:getInputText()
                        if not hasText(value) then
                            UIManager:show(InfoMessage:new{
                                text = args.empty_text,
                                timeout = 2,
                            })
                            return
                        end
                        UIManager:close(dialog)
                        args.callback(value)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

-- Card editor: a new card in `column_id`, or the existing card `card_id`.
function CardDialog.editCard(view, column_id, card_id)
    local board = view:getBoard()
    local card = card_id and board.cards[card_id]
    local dialog
    local function save()
        local fields = dialog:getFields()
        if not hasText(fields[1]) then
            UIManager:show(InfoMessage:new{
                text = _("A card needs a title."),
                timeout = 2,
            })
            return
        end
        UIManager:close(dialog)
        local values = { title = fields[1], notes = fields[2] }
        if card then
            view:commit(function() return Model.editCard(board, card_id, values) end)
        else
            view:commit(function() return Model.addCard(board, column_id, values) end, function()
                local column = view:findColumn(column_id)
                view:revealCard(column_id, #column.cards)
            end)
        end
    end
    dialog = MultiInputDialog:new{
        title = card and _("Edit card") or _("New card"),
        fields = {
            {
                description = _("Title"),
                text = card and card.title or "",
                hint = _("What needs doing?"),
            },
            {
                description = _("Notes"),
                text = card and card.notes or "",
                hint = _("Details, links, next steps (optional)"),
                allow_newline = true,
            },
        },
        -- Enter saves from the title field; the notes field takes new lines.
        enter_callback = save,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = card and _("Save") or _("Add"),
                    callback = save,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

-- "Move to…": the other columns, one per row.
function CardDialog.moveCardTo(view, card_id)
    local board = view:getBoard()
    local card = board.cards[card_id]
    local from = view:locateCard(card_id)
    local dialog
    local buttons = {}
    for _, column in ipairs(board.columns) do
        if column ~= from then
            table.insert(buttons, { {
                text = column.name,
                callback = function()
                    UIManager:close(dialog)
                    view:commit(function() return Model.moveCard(board, card_id, column.id) end, function()
                        view:revealCard(column.id, #column.cards)
                    end)
                end,
            } })
        end
    end
    table.insert(buttons, { {
        text = _("Cancel"),
        callback = function()
            UIManager:close(dialog)
        end,
    } })
    dialog = showDialog(ButtonDialog:new{
        title = T(_("Move “%1” to"), card.title),
        buttons = buttons,
    })
end

function CardDialog.showCardActions(view, card_id)
    local board = view:getBoard()
    local card = board.cards[card_id]
    local column, index = view:locateCard(card_id)
    local dialog
    local function action(fn)
        return function()
            UIManager:close(dialog)
            fn()
        end
    end
    dialog = ButtonDialog:new{
        title = card.title,
        use_info_style = false, -- bold title, so the notes below stand apart
        buttons = {
            {
                {
                    text = _("Edit"),
                    callback = action(function()
                        CardDialog.editCard(view, column.id, card_id)
                    end),
                },
                {
                    text = _("Move to…"),
                    enabled = #board.columns > 1,
                    callback = action(function()
                        CardDialog.moveCardTo(view, card_id)
                    end),
                },
            },
            {
                {
                    text = _("Move up"),
                    enabled = index > 1,
                    callback = action(function()
                        view:commit(function() return Model.moveCard(board, card_id, column.id, index - 1) end, function()
                            view:revealCard(column.id, index - 1)
                        end)
                    end),
                },
                {
                    text = _("Move down"),
                    enabled = index < #column.cards,
                    callback = action(function()
                        view:commit(function() return Model.moveCard(board, card_id, column.id, index + 1) end, function()
                            view:revealCard(column.id, index + 1)
                        end)
                    end),
                },
            },
            {
                {
                    text = _("Archive"),
                    callback = action(function()
                        view:commit(function() return Model.archiveCard(board, card_id) end)
                    end),
                },
                {
                    text = _("Cancel"),
                    callback = action(function() end),
                },
            },
        },
    }
    if hasText(card.notes) then
        local notes = card.notes
        if #notes > NOTES_PREVIEW then
            -- Cut on a UTF-8 character boundary.
            notes = notes:sub(1, NOTES_PREVIEW):gsub("[\128-\191]*$", ""):gsub("[\192-\255]$", "") .. "…"
        end
        dialog:addWidget(TextBoxWidget:new{
            text = notes,
            face = Font:getFace("x_smallinfofont"),
            width = dialog:getAddedWidgetAvailableWidth(),
            not_focusable = true,
            parent = dialog, -- keeps it from being freed when the dialog reinits
        })
    end
    UIManager:show(dialog)
end

function CardDialog.showColumnActions(view, column_id)
    local board = view:getBoard()
    local column, index = view:findColumn(column_id)
    local dialog
    local function action(fn)
        return function()
            UIManager:close(dialog)
            fn()
        end
    end
    -- Reopen the dialog after a move so the column can be moved again.
    local function move(to)
        if view:commit(function() return Model.moveColumn(board, column_id, to) end, function()
            view:revealColumn(to)
        end) then
            CardDialog.showColumnActions(view, column_id)
        end
    end
    dialog = showDialog(ButtonDialog:new{
        title = T(N_("%1 · 1 card", "%1 · %2 cards", #column.cards), column.name, #column.cards),
        use_info_style = false,
        buttons = {
            {
                {
                    text = _("Add card"),
                    callback = action(function()
                        CardDialog.editCard(view, column_id)
                    end),
                },
                {
                    text = _("Rename"),
                    callback = action(function()
                        promptName{
                            title = _("Rename column"),
                            value = column.name,
                            hint = _("Column name"),
                            ok_text = _("Rename"),
                            empty_text = _("A column needs a name."),
                            callback = function(name)
                                view:commit(function() return Model.renameColumn(board, column_id, name) end)
                            end,
                        }
                    end),
                },
            },
            {
                {
                    text = _("Move left"),
                    enabled = index > 1,
                    callback = action(function() move(index - 1) end),
                },
                {
                    text = _("Move right"),
                    enabled = index < #board.columns,
                    callback = action(function() move(index + 1) end),
                },
            },
            {
                {
                    text = _("Delete"),
                    callback = action(function()
                        local text
                        if #column.cards == 0 then
                            text = T(_("Delete column “%1”?"), column.name)
                        else
                            text = T(N_("Delete column “%1”?\n\nIts card will be moved to Archived cards.",
                                "Delete column “%1”?\n\nIts %2 cards will be moved to Archived cards.",
                                #column.cards), column.name, #column.cards)
                        end
                        UIManager:show(ConfirmBox:new{
                            text = text,
                            ok_text = _("Delete"),
                            ok_callback = function()
                                view:commit(function() return Model.deleteColumn(board, column_id) end)
                            end,
                        })
                    end),
                },
                {
                    text = _("Close"),
                    callback = action(function() end),
                },
            },
        },
    })
end

function CardDialog.restoreCard(view, card_id, close_parent)
    local board = view:getBoard()
    local card = board.cards[card_id]
    local dialog
    local buttons = {}
    for _, column in ipairs(board.columns) do
        table.insert(buttons, { {
            text = column.name,
            callback = function()
                UIManager:close(dialog)
                close_parent()
                view:commit(function() return Model.restoreCard(board, card_id, column.id) end, function()
                    view:revealCard(column.id, #column.cards)
                end)
            end,
        } })
    end
    table.insert(buttons, { {
        text = _("Cancel"),
        callback = function()
            UIManager:close(dialog)
        end,
    } })
    dialog = showDialog(ButtonDialog:new{
        title = T(_("Restore “%1” to"), card.title),
        buttons = buttons,
    })
end

function CardDialog.showArchive(view)
    local board = view:getBoard()
    if #board.archived == 0 then
        UIManager:show(InfoMessage:new{ text = _("No archived cards."), timeout = 2 })
        return
    end
    if #board.columns == 0 then
        UIManager:show(InfoMessage:new{ text = _("Add a column first, to restore cards into it.") })
        return
    end
    local dialog
    local buttons = {}
    -- Most recently archived first.
    for position = #board.archived, 1, -1 do
        local card_id = board.archived[position]
        table.insert(buttons, { {
            text = board.cards[card_id].title,
            align = "left",
            font_bold = false, -- list items; the bold button is the action
            avoid_text_truncation = false, -- cut long titles instead of shrinking the font
            callback = function()
                CardDialog.restoreCard(view, card_id, function()
                    UIManager:close(dialog)
                end)
            end,
        } })
    end
    table.insert(buttons, { {
        text = _("Close"),
        callback = function()
            UIManager:close(dialog)
        end,
    } })
    dialog = showDialog(ButtonDialog:new{
        title = T(_("Archived cards (%1)\nTap a card to restore it."), #board.archived),
        buttons = buttons,
    })
end

function CardDialog.showBoards(view)
    local state = view.state
    local current = view:getBoard()
    local dialog
    local function action(fn)
        return function()
            UIManager:close(dialog)
            fn()
        end
    end
    local buttons = {}
    for _, board in ipairs(state.boards) do
        table.insert(buttons, { {
            text = board.name,
            align = "left",
            font_bold = false,
            checked_func = function() return board == current end,
            callback = action(function()
                if board ~= current then
                    view:commit(function() return Model.selectBoard(state, board.id) end, function()
                        view:resetPosition()
                    end, "full")
                end
            end),
        } })
    end
    table.insert(buttons, {
        {
            text = _("New board"),
            callback = action(function()
                promptName{
                    title = _("New board"),
                    hint = _("Board name"),
                    ok_text = _("Create"),
                    empty_text = _("A board needs a name."),
                    callback = function(name)
                        view:commit(function() return Model.addBoard(state, name) end, function()
                            view:resetPosition()
                        end, "full")
                    end,
                }
            end),
        },
        {
            text = T(_("Rename “%1”"), current.name),
            callback = action(function()
                promptName{
                    title = _("Rename board"),
                    value = current.name,
                    hint = _("Board name"),
                    ok_text = _("Rename"),
                    empty_text = _("A board needs a name."),
                    callback = function(name)
                        view:commit(function() return Model.renameBoard(state, current.id, name) end)
                    end,
                }
            end),
        },
        {
            text = T(_("Delete “%1”"), current.name),
            enabled = #state.boards > 1,
            callback = action(function()
                local count = 0
                for _ in pairs(current.cards) do
                    count = count + 1
                end
                local text
                if count == 0 then
                    text = T(_("Delete board “%1”?"), current.name)
                else
                    text = T(N_("Delete board “%1” and its card?\n\nThis can't be undone.",
                        "Delete board “%1” and all %2 of its cards, including archived ones?\n\nThis can't be undone.",
                        count), current.name, count)
                end
                UIManager:show(ConfirmBox:new{
                    text = text,
                    ok_text = _("Delete"),
                    ok_callback = function()
                        view:commit(function() return Model.deleteBoard(state, current.id) end, function()
                            view:resetPosition()
                        end, "full")
                    end,
                })
            end),
        },
    })
    dialog = showDialog(ButtonDialog:new{
        title = _("Boards"),
        buttons = buttons,
    })
end

function CardDialog.showBoardMenu(view)
    local board = view:getBoard()
    local dialog
    local function action(fn)
        return function()
            UIManager:close(dialog)
            fn()
        end
    end

    -- Rotate screen: switch between portrait and landscape, like KOReader's
    -- DeviceListener:onSwapRotation (portrait modes are even, landscape = portrait + 1).
    local function rotateScreen()
        local rotation = require("device").screen:getRotationMode()
        view:onSetRotationMode(rotation % 2 == 0 and rotation + 1 or rotation - 1)
    end

    dialog = showDialog(ButtonDialog:new{
        title = board.name,
        use_info_style = false,
        buttons = {
            { {
                text = _("Add column"),
                callback = action(function()
                    promptName{
                        title = _("Add column"),
                        hint = _("Column name"),
                        ok_text = _("Add"),
                        empty_text = _("A column needs a name."),
                        callback = function(name)
                            view:commit(function() return Model.addColumn(board, name) end, function()
                                view:revealColumn(#board.columns)
                            end)
                        end,
                    }
                end),
            } },
            { {
                text = T(_("Archived cards (%1)"), #board.archived),
                callback = action(function()
                    CardDialog.showArchive(view)
                end),
            } },
            { {
                text = _("Rotate screen"),
                callback = action(function()
                    rotateScreen()
                end),
            } },
        },
    })
end

return CardDialog
