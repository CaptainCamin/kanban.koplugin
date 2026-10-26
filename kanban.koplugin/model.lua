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

local function find_id(list, id)
    for index, value in ipairs(list) do
        if value == id then
            return index
        end
    end
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
    end
    table.remove(board.columns, index)
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
