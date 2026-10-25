local Model = require("model")

local function find(list, value)
    for index, item in ipairs(list) do
        if item == value then
            return index
        end
    end
end

local function assert_invariants(state)
    for _, board in ipairs(state.boards) do
        local locations = {}
        for _, column in ipairs(board.columns) do
            for _, card_id in ipairs(column.cards) do
                assert.is_truthy(board.cards[card_id], "column contains an unknown card")
                locations[card_id] = (locations[card_id] or 0) + 1
            end
        end
        for _, card_id in ipairs(board.archived) do
            assert.is_truthy(board.cards[card_id], "archive contains an unknown card")
            locations[card_id] = (locations[card_id] or 0) + 1
        end
        for card_id, card in pairs(board.cards) do
            assert.equals(1, locations[card_id], "card must have one location")
            assert.equals(card.archived, find(board.archived, card_id) ~= nil)
        end
    end
end

describe("kanban model", function()
    it("creates the schema v1 default state", function()
        local state = Model.newState()
        assert.equals(1, state.version)
        assert.equals("b1", state.current_board)
        assert.same({ "To Do", "Doing", "Done" }, {
            state.boards[1].columns[1].name,
            state.boards[1].columns[2].name,
            state.boards[1].columns[3].name,
        })
        assert_invariants(state)
    end)

    it("adds, renames, and deletes boards", function()
        local state = Model.newState()
        assert.is_true(Model.addBoard(state, "  Reading  "))
        assert.equals("Reading", state.boards[2].name)
        assert.equals("b2", state.current_board)
        assert_invariants(state)
        assert.is_true(Model.renameBoard(state, "b2", "Library"))
        assert.equals("Library", state.boards[2].name)
        assert_invariants(state)
        assert.is_true(Model.deleteBoard(state, "b2"))
        assert.equals("b1", state.current_board)
        assert_invariants(state)
    end)

    it("adds, renames, moves, and deletes columns", function()
        local state = Model.newState()
        local board = state.boards[1]
        assert.is_true(Model.addColumn(board, "Later", 1))
        local column_id = board.columns[1].id
        assert.equals("Later", board.columns[1].name)
        assert_invariants(state)
        assert.is_true(Model.renameColumn(board, column_id, "Someday"))
        assert_invariants(state)
        assert.is_true(Model.moveColumn(board, column_id, 99))
        assert.equals("Someday", board.columns[#board.columns].name)
        assert_invariants(state)
        assert.is_true(Model.deleteColumn(board, column_id))
        assert_invariants(state)
    end)

    it("clamps card insertion indexes and rejects empty titles", function()
        local state = Model.newState()
        local board = state.boards[1]
        local todo = board.columns[1].id
        assert.is_nil(Model.addCard(board, todo, { title = "  " }))
        assert_invariants(state)
        assert.is_true(Model.addCard(board, todo, { title = "last" }, 999, 11))
        assert_invariants(state)
        assert.is_true(Model.addCard(board, todo, { title = "first" }, -10, 12))
        assert.same({ "k5", "k4" }, board.columns[1].cards)
        assert.equals(11, board.cards.k4.created)
        assert_invariants(state)
    end)

    it("edits cards", function()
        local state = Model.newState()
        local board = state.boards[1]
        local todo = board.columns[1].id
        assert.is_true(Model.addCard(board, todo, { title = "Draft" }, nil, 10))
        assert_invariants(state)
        assert.is_true(Model.editCard(board, "k4", { title = "  Ship feature ", notes = "note" }, 20))
        assert.equals("Ship feature", board.cards.k4.title)
        assert.equals("note", board.cards.k4.notes)
        assert.equals(10, board.cards.k4.created)
        assert.equals(20, board.cards.k4.updated)
        assert_invariants(state)
    end)

    it("moves a card within a column at first, last, and out-of-range indexes", function()
        local state = Model.newState()
        local board = state.boards[1]
        local todo = board.columns[1].id
        assert.is_true(Model.addCard(board, todo, { title = "one" }))
        assert_invariants(state)
        assert.is_true(Model.addCard(board, todo, { title = "two" }))
        assert_invariants(state)
        assert.is_true(Model.addCard(board, todo, { title = "three" }))
        assert_invariants(state)
        assert.is_true(Model.moveCard(board, "k6", todo, 1))
        assert.same({ "k6", "k4", "k5" }, board.columns[1].cards)
        assert_invariants(state)
        assert.is_true(Model.moveCard(board, "k6", todo, 999))
        assert.same({ "k4", "k5", "k6" }, board.columns[1].cards)
        assert_invariants(state)
        assert.is_true(Model.moveCard(board, "k5", todo, -5))
        assert.same({ "k5", "k4", "k6" }, board.columns[1].cards)
        assert_invariants(state)
    end)

    it("moves a card between columns at first, last, and out-of-range indexes", function()
        local state = Model.newState()
        local board = state.boards[1]
        local todo, doing = board.columns[1].id, board.columns[2].id
        assert.is_true(Model.addCard(board, todo, { title = "one" }))
        assert_invariants(state)
        assert.is_true(Model.addCard(board, todo, { title = "two" }))
        assert_invariants(state)
        assert.is_true(Model.addCard(board, doing, { title = "three" }))
        assert_invariants(state)
        assert.is_true(Model.moveCard(board, "k4", doing, 1))
        assert.same({ "k4", "k6" }, board.columns[2].cards)
        assert_invariants(state)
        assert.is_true(Model.moveCard(board, "k5", doing, 999))
        assert.same({ "k4", "k6", "k5" }, board.columns[2].cards)
        assert_invariants(state)
        assert.is_true(Model.moveCard(board, "k6", todo, -1))
        assert.same({ "k6" }, board.columns[1].cards)
        assert_invariants(state)
    end)

    it("archives a deleted column's cards and restores archived cards", function()
        local state = Model.newState()
        local board = state.boards[1]
        local todo, doing = board.columns[1].id, board.columns[2].id
        assert.is_true(Model.addCard(board, todo, { title = "one" }))
        assert_invariants(state)
        assert.is_true(Model.addCard(board, todo, { title = "two" }))
        assert_invariants(state)
        assert.is_true(Model.deleteColumn(board, todo))
        assert.same({ "k4", "k5" }, board.archived)
        assert.is_true(board.cards.k4.archived)
        assert_invariants(state)
        assert.is_true(Model.restoreCard(board, "k4", doing))
        assert.same({ "k4" }, board.columns[1].cards)
        assert.is_false(board.cards.k4.archived)
        assert_invariants(state)
        assert.is_true(Model.archiveCard(board, "k4"))
        assert_invariants(state)
        assert.is_nil(Model.moveCard(board, "k4", doing))
        assert_invariants(state)
    end)
end)
