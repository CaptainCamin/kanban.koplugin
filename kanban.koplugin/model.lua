local Model = {}

local function trim(value)
    if type(value) ~= "string" then
        return nil
    end
    value = value:match("^%s*(.-)%s*$")
    if value == "" then
        return nil
    end
    return value
end

local function now(clock)
    if type(clock) == "function" then
        return clock()
    end
    if type(clock) == "number" then
        return clock
    end
    return os.time()
end

local function find_board(state, board_id)
    for index, board in ipairs(state.boards) do
        if board.id == board_id then
            return board, index
        end
    end
end

local function find_column(board, column_id)
    for index, column in ipairs(board.columns) do
        if column.id == column_id then
            return column, index
        end
    end
end

function Model.getTodayColumn(board)
    local column, index = find_column(board, board.today_column)
    if column then
        return column, index
    end
    if #board.columns == 0 then
        return nil
    end
    index = math.max(1, #board.columns - 1)
    return board.columns[index], index
end

function Model.setTodayColumn(board, column_id)
    if not find_column(board, column_id) then
        return nil, "column not found"
    end
    board.today_column = column_id
    return true
end

function Model.setNowCard(board, card_id)
    if card_id == nil then
        board.now_card = nil
        return true
    end
    local card = board.cards[card_id]
    if not card then
        return nil, "card not found"
    end
    if card.archived then
        return nil, "card is archived"
    end
    board.now_card = card_id
    return true
end

local function find_id(list, id)
    for index, value in ipairs(list) do
        if value == id then
            return index
        end
    end
end

local function copy_table(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, item in pairs(value) do
        copy[copy_table(key)] = copy_table(item)
    end
    return copy
end

local function clamp(index, minimum, maximum)
    index = tonumber(index) or maximum
    index = math.floor(index)
    if index < minimum then
        return minimum
    end
    if index > maximum then
        return maximum
    end
    return index
end

local function insert(list, value, index)
    table.insert(list, clamp(index, 1, #list + 1), value)
end

local function next_id(board, prefix)
    local id = prefix .. board.next_id
    board.next_id = board.next_id + 1
    return id
end

local function new_board(id, name)
    return {
        id = id,
        name = name,
        columns = {
            { id = "c1", name = "To Do", cards = {}, collapsed = false },
            { id = "c2", name = "Doing", cards = {}, collapsed = false },
            { id = "c3", name = "Done", cards = {}, collapsed = false },
        },
        cards = {},
        archived = {},
        labels = {},
        next_id = 4,
    }
end

function Model.newState()
    local board = new_board("b1", "My board")
    return {
        version = 2,
        current_board = board.id,
        boards = { board },
    }
end

function Model.copyBoard(board)
    return copy_table(board)
end

function Model.restoreBoard(state, snapshot)
    if type(snapshot) ~= "table" or type(snapshot.id) ~= "string" then
        return nil, "board snapshot is invalid"
    end
    local _, index = find_board(state, snapshot.id)
    if not index then
        return nil, "board not found"
    end
    state.boards[index] = copy_table(snapshot)
    return true
end

function Model.addBoard(state, name)
    name = trim(name)
    if not name then
        return nil, "board name is required"
    end
    local number = 1
    while find_board(state, "b" .. number) do
        number = number + 1
    end
    local board = new_board("b" .. number, name)
    table.insert(state.boards, board)
    state.current_board = board.id
    return true
end

function Model.renameBoard(state, board_id, name)
    local board = find_board(state, board_id)
    name = trim(name)
    if not board then
        return nil, "board not found"
    end
    if not name then
        return nil, "board name is required"
    end
    board.name = name
    return true
end

function Model.selectBoard(state, board_id)
    if not find_board(state, board_id) then
        return nil, "board not found"
    end
    state.current_board = board_id
    return true
end

function Model.deleteBoard(state, board_id)
    local _, index = find_board(state, board_id)
    if not index then
        return nil, "board not found"
    end
    if #state.boards == 1 then
        return nil, "cannot delete the last board"
    end
    table.remove(state.boards, index)
    if state.current_board == board_id then
        state.current_board = state.boards[1] and state.boards[1].id or nil
    end
    return true
end

-- Labels have stable IDs so names can change without changing assignments.
function Model.findLabel(board, label_id)
    for _, label in ipairs(board.labels or {}) do
        if label.id == label_id then return label end
    end
end

local function labelName(board, name, except_id)
    name = trim(name)
    if not name then return nil, "label name is required" end
    for _, label in ipairs(board.labels or {}) do
        if label.id ~= except_id and label.name:lower() == name:lower() then
            return nil, "a label with this name already exists"
        end
    end
    return name
end

function Model.addLabel(board, name)
    local value, err = labelName(board, name)
    if not value then return nil, err end
    board.labels = board.labels or {}
    table.insert(board.labels, { id = next_id(board, "l"), name = value })
    return true
end

function Model.renameLabel(board, label_id, name)
    local label = Model.findLabel(board, label_id)
    if not label then return nil, "label not found" end
    local value, err = labelName(board, name, label_id)
    if not value then return nil, err end
    label.name = value
    return true
end

function Model.deleteLabel(board, label_id)
    for index, label in ipairs(board.labels or {}) do
        if label.id == label_id then
            table.remove(board.labels, index)
            for _, card in pairs(board.cards) do
                for i = #(card.labels or {}), 1, -1 do
                    if card.labels[i] == label_id then table.remove(card.labels, i) end
                end
            end
            return true
        end
    end
    return nil, "label not found"
end

function Model.setCardLabels(board, card_id, label_ids, clock)
    local card = board.cards[card_id]
    if not card then return nil, "card not found" end
    local ids, seen = {}, {}
    for _, id in ipairs(label_ids) do
        if not Model.findLabel(board, id) then return nil, "label not found" end
        if not seen[id] then ids[#ids + 1], seen[id] = id, true end
    end
    card.labels = ids
    card.updated = now(clock)
    return true
end

function Model.hasLabel(card, label_id)
    return find_id(card.labels or {}, label_id) ~= nil
end

function Model.labelText(board, card)
    local names = {}
    for _, id in ipairs(card.labels or {}) do
        local label = Model.findLabel(board, id)
        if label then names[#names + 1] = "[" .. label.name .. "]" end
    end
    return table.concat(names, " ")
end

function Model.filteredCards(board, column, label_id)
    local cards = {}
    for _, id in ipairs(column.cards) do
        if not label_id or Model.hasLabel(board.cards[id], label_id) then
            cards[#cards + 1] = id
        end
    end
    return cards
end

function Model.addColumn(board, name, index)
    name = trim(name)
    if not name then
        return nil, "column name is required"
    end
    insert(board.columns, { id = next_id(board, "c"), name = name, cards = {}, collapsed = false }, index)
    return true
end

function Model.renameColumn(board, column_id, name)
    local column = find_column(board, column_id)
    name = trim(name)
    if not column then
        return nil, "column not found"
    end
    if not name then
        return nil, "column name is required"
    end
    column.name = name
    return true
end

function Model.moveColumn(board, column_id, new_index)
    local _, index = find_column(board, column_id)
    if not index then
        return nil, "column not found"
    end
    local column = table.remove(board.columns, index)
    insert(board.columns, column, new_index)
    return true
end

function Model.deleteColumn(board, column_id)
    local column, index = find_column(board, column_id)
    if not index then
        return nil, "column not found"
    end
    for _, card_id in ipairs(column.cards) do
        board.cards[card_id].archived = true
        table.insert(board.archived, card_id)
        if board.now_card == card_id then
            board.now_card = nil
        end
    end
    table.remove(board.columns, index)
    if board.today_column == column_id then
        board.today_column = nil
    end
    return true
end

function Model.addCard(board, column_id, fields, index, clock)
    local column = find_column(board, column_id)
    local title = fields and trim(fields.title)
    if not column then
        return nil, "column not found"
    end
    if not title then
        return nil, "card title is required"
    end
    for _, id in ipairs(fields.labels or {}) do
        if not Model.findLabel(board, id) then return nil, "label not found" end
    end
    local timestamp = now(clock)
    local card_id = next_id(board, "k")
    board.cards[card_id] = {
        id = card_id,
        title = title,
        notes = fields.notes or "",
        created = timestamp,
        updated = timestamp,
        moved = timestamp,
        archived = false,
        checklist = {},
        labels = copy_table(fields.labels or {}),
    }
    insert(column.cards, card_id, index)
    return true
end

function Model.editCard(board, card_id, fields, clock)
    local card = board.cards[card_id]
    if not card then
        return nil, "card not found"
    end
    local title = fields and trim(fields.title)
    if not title then
        return nil, "card title is required"
    end
    if fields.labels then
        local ok, err = Model.setCardLabels(board, card_id, fields.labels, clock)
        if not ok then return nil, err end
    end
    card.title = title
    card.notes = fields.notes or ""
    card.updated = now(clock)
    return true
end

local function checklist_index(card, item_index)
    local index = tonumber(item_index)
    if not index or index ~= math.floor(index) or not card.checklist
        or index < 1 or index > #card.checklist then
        return nil
    end
    return index
end

function Model.addChecklistItem(board, card_id, text, index, clock)
    local card = board.cards[card_id]
    text = trim(text)
    if not card then
        return nil, "card not found"
    end
    if not text then
        return nil, "checklist item text is required"
    end
    card.checklist = card.checklist or {}
    insert(card.checklist, { text = text, done = false }, index)
    card.updated = now(clock)
    return true
end

function Model.editChecklistItem(board, card_id, item_index, text, clock)
    local card = board.cards[card_id]
    if not card then
        return nil, "card not found"
    end
    local index = checklist_index(card, item_index)
    if not index then
        return nil, "checklist item not found"
    end
    text = trim(text)
    if not text then
        return nil, "checklist item text is required"
    end
    card.checklist[index].text = text
    card.updated = now(clock)
    return true
end

function Model.toggleChecklistItem(board, card_id, item_index, clock)
    local card = board.cards[card_id]
    if not card then
        return nil, "card not found"
    end
    local index = checklist_index(card, item_index)
    if not index then
        return nil, "checklist item not found"
    end
    card.checklist[index].done = not card.checklist[index].done
    card.updated = now(clock)
    return true
end

function Model.deleteChecklistItem(board, card_id, item_index, clock)
    local card = board.cards[card_id]
    if not card then
        return nil, "card not found"
    end
    local index = checklist_index(card, item_index)
    if not index then
        return nil, "checklist item not found"
    end
    table.remove(card.checklist, index)
    card.updated = now(clock)
    return true
end

function Model.moveChecklistItem(board, card_id, item_index, new_index, clock)
    local card = board.cards[card_id]
    if not card then
        return nil, "card not found"
    end
    local index = checklist_index(card, item_index)
    if not index then
        return nil, "checklist item not found"
    end
    local item = table.remove(card.checklist, index)
    insert(card.checklist, item, new_index)
    card.updated = now(clock)
    return true
end

-- Whole days since `moved` (a card's last column change), or nil below one day.
function Model.daysInColumn(moved, clock)
    if type(moved) ~= "number" then
        return nil
    end
    local days = math.floor((now(clock) - moved) / 86400)
    return days >= 1 and days or nil
end

function Model.setColumnCollapsed(board, column_id, collapsed)
    local column = find_column(board, column_id)
    if not column then
        return nil, "column not found"
    end
    if type(collapsed) ~= "boolean" then
        return nil, "collapsed must be a boolean"
    end
    column.collapsed = collapsed
    return true
end

function Model.moveCard(board, card_id, to_column_id, index, clock)
    local card = board.cards[card_id]
    local destination = find_column(board, to_column_id)
    if not card then
        return nil, "card not found"
    end
    if not destination then
        return nil, "column not found"
    end
    if card.archived then
        return nil, "card is archived"
    end
    local source
    for _, column in ipairs(board.columns) do
        local old_index = find_id(column.cards, card_id)
        if old_index then
            source = column
            table.remove(column.cards, old_index)
            break
        end
    end
    insert(destination.cards, card_id, index)
    if source ~= destination then
        card.moved = now(clock)
    end
    return true
end

function Model.archiveCard(board, card_id)
    local card = board.cards[card_id]
    if not card then
        return nil, "card not found"
    end
    for _, column in ipairs(board.columns) do
        local index = find_id(column.cards, card_id)
        if index then
            table.remove(column.cards, index)
            break
        end
    end
    if not find_id(board.archived, card_id) then
        table.insert(board.archived, card_id)
    end
    card.archived = true
    if board.now_card == card_id then
        board.now_card = nil
    end
    return true
end

-- Validate the complete batch before changing anything. IDs are ordered by the
-- caller (the UI uses board order), so appending a selection is deterministic.
function Model.changeCards(board, card_ids, to_column_id, clock)
    if to_column_id and not find_column(board, to_column_id) then
        return nil, "column not found"
    end
    local seen = {}
    for _, id in ipairs(card_ids) do
        if not board.cards[id] or board.cards[id].archived or seen[id] then
            return nil, "selection contains an invalid card"
        end
        seen[id] = true
    end
    for _, id in ipairs(card_ids) do
        if to_column_id then
            Model.moveCard(board, id, to_column_id, nil, clock)
        else
            Model.archiveCard(board, id)
        end
    end
    return true
end

function Model.restoreCard(board, card_id, column_id)
    local card = board.cards[card_id]
    local column = find_column(board, column_id)
    local archived_index = find_id(board.archived, card_id)
    if not card then
        return nil, "card not found"
    end
    if not column then
        return nil, "column not found"
    end
    if not archived_index then
        return nil, "card is not archived"
    end
    table.remove(board.archived, archived_index)
    table.insert(column.cards, card_id)
    card.archived = false
    return true
end

return Model
