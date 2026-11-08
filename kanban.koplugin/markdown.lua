local Model = require("model")

local Markdown = {}

local NOTES_START = "  <!-- kanban:notes -->"
local NOTES_END = "  <!-- /kanban:notes -->"
local ARCHIVE_HEADING = "# Archived cards"

local function escape_inline(value)
    local escaped = {}
    for index = 1, #value do
        local char = value:sub(index, index)
        if char == "\n" then
            escaped[#escaped + 1] = "\\n"
        elseif char == "\r" then
            escaped[#escaped + 1] = "\\r"
        elseif char == "\t" then
            escaped[#escaped + 1] = "\\t"
        elseif char == "\\" then
            escaped[#escaped + 1] = "\\" .. char
        else
            escaped[#escaped + 1] = char
        end
    end
    return table.concat(escaped)
end

local function unescape_inline(value)
    local decoded = {}
    local index = 1
    while index <= #value do
        local char = value:sub(index, index)
        local next_char = value:sub(index + 1, index + 1)
        if char == "\\" and next_char ~= "" then
            if next_char == "n" then
                decoded[#decoded + 1] = "\n"
                index = index + 2
            elseif next_char == "r" then
                decoded[#decoded + 1] = "\r"
                index = index + 2
            elseif next_char == "t" then
                decoded[#decoded + 1] = "\t"
                index = index + 2
            elseif next_char == "\\" then
                decoded[#decoded + 1] = next_char
                index = index + 2
            else
                decoded[#decoded + 1] = char
                index = index + 1
            end
        else
            decoded[#decoded + 1] = char
            index = index + 1
        end
    end
    return table.concat(decoded)
end

local function split_lines(value)
    local lines = {}
    if value == "" then
        return lines
    end
    for line in (value .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = line
    end
    return lines
end

local function is_blank(line)
    return line:match("^%s*$") ~= nil
end

-- Hex keeps arbitrary label names safe inside Markdown comments.
local function encode_label(name)
    return (name:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end

local function decode_label(value)
    if #value % 2 ~= 0 or value:find("[^0-9a-f]") then return nil end
    return (value:gsub("..", function(pair) return string.char(tonumber(pair, 16)) end))
end

local function append_card(lines, board, card_id)
    local card = board.cards[card_id]
    lines[#lines + 1] = "- " .. escape_inline(card.title)
    for _, id in ipairs(card.labels or {}) do
        local label = Model.findLabel(board, id)
        if label then lines[#lines + 1] = "  <!-- kanban-label:" .. encode_label(label.name) .. " -->" end
    end
    if card.notes and card.notes ~= "" then
        lines[#lines + 1] = NOTES_START
        for _, note_line in ipairs(split_lines(card.notes)) do
            if note_line == "" then
                lines[#lines + 1] = "  >"
            else
                lines[#lines + 1] = "  > " .. note_line
            end
        end
        lines[#lines + 1] = NOTES_END
    end
    for _, item in ipairs(card.checklist or {}) do
        local marker = item.done and "x" or " "
        lines[#lines + 1] = "  - [" .. marker .. "] " .. escape_inline(item.text)
    end
end

function Markdown.export(board)
    local lines = { "# " .. escape_inline(board.name) }
    for _, label in ipairs(board.labels or {}) do
        lines[#lines + 1] = "<!-- kanban-label:" .. encode_label(label.name) .. " -->"
    end
    for _, column in ipairs(board.columns) do
        lines[#lines + 1] = ""
        lines[#lines + 1] = "## " .. escape_inline(column.name)
        for _, card_id in ipairs(column.cards) do
            lines[#lines + 1] = ""
            append_card(lines, board, card_id)
        end
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = ARCHIVE_HEADING
    for _, card_id in ipairs(board.archived) do
        lines[#lines + 1] = ""
        append_card(lines, board, card_id)
    end
    return table.concat(lines, "\n") .. "\n"
end

local function parse_card_title(line)
    local title = line:match("^%- (.*)$")
    if title == nil then
        return nil
    end
    return unescape_inline(title)
end

local function parse_checklist_item(line)
    local marker, text = line:match("^  %- %[([ xX])%] (.*)$")
    if marker == nil then
        return nil
    end
    return {
        text = unescape_inline(text),
        done = marker == "x" or marker == "X",
    }
end

local function parse_document(text)
    if type(text) ~= "string" then
        return nil, "Markdown text must be a string"
    end
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
    local lines = split_lines(text)
    local first, last = 1, #lines
    while first <= last and is_blank(lines[first]) do
        first = first + 1
    end
    while last >= first and is_blank(lines[last]) do
        last = last - 1
    end
    if first > last then
        return nil, "Markdown board heading is missing"
    end

    local encoded_name = lines[first]:match("^# (.*)$")
    if encoded_name == nil then
        return nil, "Markdown must start with a '# Board name' heading"
    end
    local parsed = {
        name = unescape_inline(encoded_name),
        labels = {},
        columns = {},
        archived = {},
    }
    if is_blank(parsed.name) then
        return nil, "Board name is required"
    end

    local section
    local archive_seen = false
    local index = first + 1
    while index <= last do
        local line = lines[index]
        if is_blank(line) then
            index = index + 1
        elseif line:match("^<!%-%- kanban%-label:([0-9a-f]+) %-%->$") then
            local name = decode_label(line:match("kanban%-label:([0-9a-f]+)"))
            if not name or is_blank(name) then return nil, "Invalid label name" end
            parsed.labels[#parsed.labels + 1] = name
            index = index + 1
        elseif line == ARCHIVE_HEADING then
            if archive_seen then
                return nil, "Archived cards section appears more than once"
            end
            archive_seen = true
            section = { cards = parsed.archived }
            index = index + 1
        else
            local encoded_column_name = line:match("^## (.*)$")
            if encoded_column_name ~= nil then
                if archive_seen then
                    return nil, "Columns cannot follow the archived cards section"
                end
                section = {
                    name = unescape_inline(encoded_column_name),
                    cards = {},
                }
                if is_blank(section.name) then
                    return nil, "Column name is required"
                end
                parsed.columns[#parsed.columns + 1] = section
                index = index + 1
            elseif line:sub(1, 1) == "#" then
                return nil, "Unexpected Markdown heading"
            else
                if not section then
                    return nil, "Card appears before a column heading"
                end
                local title = parse_card_title(line)
                if title == nil then
                    return nil, "Expected a card list item or section heading"
                end
                if is_blank(title) then
                    return nil, "Card title is required"
                end
                local card = { title = title, notes = "", checklist = {}, labels = {} }
                index = index + 1

                while index <= last and is_blank(lines[index]) do
                    index = index + 1
                end
                while lines[index] and lines[index]:match("^  <!%-%- kanban%-label:([0-9a-f]+) %-%->$") do
                    local name = decode_label(lines[index]:match("kanban%-label:([0-9a-f]+)"))
                    if not name or is_blank(name) then return nil, "Invalid label name" end
                    card.labels[#card.labels + 1] = name
                    index = index + 1
                end
                if lines[index] == NOTES_START then
                    index = index + 1
                    local note_lines = {}
                    local notes_closed = false
                    while index <= last do
                        local note_line = lines[index]
                        if note_line == NOTES_END then
                            notes_closed = true
                            index = index + 1
                            break
                        elseif note_line == "  >" then
                            note_lines[#note_lines + 1] = ""
                        elseif note_line:sub(1, 4) == "  > " then
                            note_lines[#note_lines + 1] = note_line:sub(5)
                        elseif is_blank(note_line) then
                            note_lines[#note_lines + 1] = ""
                        else
                            return nil, "Invalid line inside card notes"
                        end
                        index = index + 1
                    end
                    if not notes_closed then
                        return nil, "Card notes section is not closed"
                    end
                    card.notes = table.concat(note_lines, "\n")
                end

                while index <= last do
                    if is_blank(lines[index]) then
                        index = index + 1
                    else
                        local item = parse_checklist_item(lines[index])
                        if not item then
                            break
                        end
                        if is_blank(item.text) then
                            return nil, "Checklist item text is required"
                        end
                        card.checklist[#card.checklist + 1] = item
                        index = index + 1
                    end
                end
                section.cards[#section.cards + 1] = card
            end
        end
    end

    if #parsed.columns == 0 then
        return nil, "At least one column is required"
    end
    return parsed
end

local function checked(result, err)
    if not result then
        return nil, err
    end
    return true
end

local function add_card(board, column_id, source, clock)
    local ok, err = Model.addCard(board, column_id, {
        title = source.title,
        notes = source.notes,
    }, nil, clock)
    if not ok then
        return nil, err
    end
    local column
    for _, candidate in ipairs(board.columns) do
        if candidate.id == column_id then
            column = candidate
            break
        end
    end
    local card_id = column.cards[#column.cards]
    local ids = {}
    for _, name in ipairs(source.labels or {}) do
        local label_id
        for _, label in ipairs(board.labels) do
            if label.name:lower() == name:lower() then label_id = label.id end
        end
        if not label_id then
            Model.addLabel(board, name)
            label_id = board.labels[#board.labels].id
        end
        ids[#ids + 1] = label_id
    end
    Model.setCardLabels(board, card_id, ids, clock)
    for item_index, item in ipairs(source.checklist) do
        ok, err = Model.addChecklistItem(board, card_id, item.text, nil, clock)
        if not ok then
            return nil, err
        end
        if item.done then
            ok, err = Model.toggleChecklistItem(board, card_id, item_index, clock)
            if not ok then
                return nil, err
            end
        end
    end
    return card_id
end

function Markdown.import(text, state, clock)
    local parsed, err = parse_document(text)
    if not parsed then
        return nil, err
    end
    if state ~= nil and (type(state) ~= "table" or type(state.boards) ~= "table") then
        return nil, "State must be a Model state"
    end

    local board
    if state then
        local ok
        ok, err = checked(Model.addBoard(state, parsed.name))
        if not ok then
            return nil, err
        end
        board = state.boards[#state.boards]
    else
        state = Model.newState()
        board = state.boards[1]
        local ok
        ok, err = checked(Model.renameBoard(state, board.id, parsed.name))
        if not ok then
            return nil, err
        end
    end

    for _, name in ipairs(parsed.labels) do
        Model.addLabel(board, name)
    end
    while #board.columns > 0 do
        local ok
        ok, err = checked(Model.deleteColumn(board, board.columns[#board.columns].id))
        if not ok then
            return nil, err
        end
    end
    for _, source_column in ipairs(parsed.columns) do
        local ok
        ok, err = checked(Model.addColumn(board, source_column.name))
        if not ok then
            return nil, err
        end
        local column = board.columns[#board.columns]
        for _, source_card in ipairs(source_column.cards) do
            ok, err = add_card(board, column.id, source_card, clock)
            if not ok then
                return nil, err
            end
        end
    end

    local archive_column_id = board.columns[1].id
    for _, source_card in ipairs(parsed.archived) do
        local card_id
        card_id, err = add_card(board, archive_column_id, source_card, clock)
        if not card_id then
            return nil, err
        end
        local ok
        ok, err = checked(Model.archiveCard(board, card_id))
        if not ok then
            return nil, err
        end
    end
    return board
end

return Markdown
