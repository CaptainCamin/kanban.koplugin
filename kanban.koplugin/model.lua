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
            { id = "c1", name = "To Do", cards = {} },
            { id = "c2", name = "Doing", cards = {} },
            { id = "c3", name = "Done", cards = {} },
        },
        cards = {},
        archived = {},
        next_id = 4,
    }
end

function Model.newState()
    local board = new_board("b1", "My board")
    return {
        version = 1,
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
    insert(board.columns, { id = next_id(board, "c"), name = name, cards = {} }, index)
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
        archived = false,
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

function Model.moveCard(board, card_id, to_column_id, index)
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
    for _, column in ipairs(board.columns) do
        local old_index = find_id(column.cards, card_id)
        if old_index then
            table.remove(column.cards, old_index)
            break
        end
    end
    insert(destination.cards, card_id, index)
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
