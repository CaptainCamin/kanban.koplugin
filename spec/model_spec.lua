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
    it("creates the schema v2 default state", function()
        local state = Model.newState()
        assert.equals(2, state.version)
        assert.equals("b1", state.current_board)
        assert.same({ "To Do", "Doing", "Done" }, {
            state.boards[1].columns[1].name,
            state.boards[1].columns[2].name,
            state.boards[1].columns[3].name,
        })
        for _, column in ipairs(state.boards[1].columns) do
            assert.is_false(column.collapsed)
        end
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

    it("selects boards and keeps the last board", function()
        local state = Model.newState()
        Model.addBoard(state, "Ideas")
        assert_invariants(state)
        assert.is_true(Model.selectBoard(state, "b1"))
        assert.equals("b1", state.current_board)
        assert_invariants(state)
        assert.is_nil(Model.selectBoard(state, "b9"))
        assert.equals("b1", state.current_board)
        assert_invariants(state)
        assert.is_true(Model.deleteBoard(state, "b1"))
        assert.equals("b2", state.current_board)
        assert_invariants(state)
        local ok, err = Model.deleteBoard(state, "b2")
        assert.is_nil(ok)
        assert.equals("cannot delete the last board", err)
        assert.equals(1, #state.boards)
        assert_invariants(state)
    end)

    it("adds, renames, moves, and deletes columns", function()
        local state = Model.newState()
        local board = state.boards[1]
        assert.is_true(Model.addColumn(board, "Later", 1))
        local column_id = board.columns[1].id
        assert.equals("Later", board.columns[1].name)
        assert.is_false(board.columns[1].collapsed)
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
        assert.equals(11, board.cards.k4.moved)
        assert.same({}, board.cards.k4.checklist)
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

    it("adds, edits, toggles, and deletes checklist items", function()
        local state = Model.newState()
        local board = state.boards[1]
        assert.is_true(Model.addCard(board, board.columns[1].id, { title = "Prepare release" }, nil, 10))
        assert_invariants(state)

        assert.is_true(Model.addChecklistItem(board, "k4", "  Update notes  ", nil, 11))
        assert.same({ { text = "Update notes", done = false } }, board.cards.k4.checklist)
        assert.equals(11, board.cards.k4.updated)
        assert_invariants(state)
        assert.is_true(Model.addChecklistItem(board, "k4", "Run tests", 1, 12))
        assert.same({
            { text = "Run tests", done = false },
            { text = "Update notes", done = false },
        }, board.cards.k4.checklist)
        assert_invariants(state)

        local ok, err = Model.addChecklistItem(board, "k4", "  ", nil, 13)
        assert.is_nil(ok)
        assert.equals("checklist item text is required", err)
        assert.equals(12, board.cards.k4.updated)
        assert_invariants(state)

        assert.is_true(Model.editChecklistItem(board, "k4", 1, "  Run the suite  ", 14))
        assert.equals("Run the suite", board.cards.k4.checklist[1].text)
        assert.equals(14, board.cards.k4.updated)
        assert_invariants(state)
        ok, err = Model.editChecklistItem(board, "k4", 1, " ", 15)
        assert.is_nil(ok)
        assert.equals("checklist item text is required", err)
        assert.equals("Run the suite", board.cards.k4.checklist[1].text)
        assert.equals(14, board.cards.k4.updated)
        assert_invariants(state)

        assert.is_true(Model.toggleChecklistItem(board, "k4", 1, 16))
        assert.is_true(board.cards.k4.checklist[1].done)
        assert.equals(16, board.cards.k4.updated)
        assert_invariants(state)
        assert.is_true(Model.deleteChecklistItem(board, "k4", 1, 17))
        assert.same({ { text = "Update notes", done = false } }, board.cards.k4.checklist)
        assert.equals(17, board.cards.k4.updated)
        assert_invariants(state)

        ok, err = Model.toggleChecklistItem(board, "k4", 9, 18)
        assert.is_nil(ok)
        assert.equals("checklist item not found", err)
        assert_invariants(state)
        ok, err = Model.deleteChecklistItem(board, "k9", 1, 19)
        assert.is_nil(ok)
        assert.equals("card not found", err)
        assert_invariants(state)
    end)

    it("moves checklist items with clamped indexes", function()
        local state = Model.newState()
        local board = state.boards[1]
        assert.is_true(Model.addCard(board, board.columns[1].id, { title = "Prepare release" }, nil, 10))
        assert_invariants(state)
        for index, text in ipairs({ "First", "Second", "Third" }) do
            assert.is_true(Model.addChecklistItem(board, "k4", text, nil, 10 + index))
            assert_invariants(state)
        end

        assert.is_true(Model.moveChecklistItem(board, "k4", 3, 1, 20))
        assert.same({ "Third", "First", "Second" }, {
            board.cards.k4.checklist[1].text,
            board.cards.k4.checklist[2].text,
            board.cards.k4.checklist[3].text,
        })
        assert.equals(20, board.cards.k4.updated)
        assert_invariants(state)
        assert.is_true(Model.moveChecklistItem(board, "k4", 1, 999, 21))
        assert.same({ "First", "Second", "Third" }, {
            board.cards.k4.checklist[1].text,
            board.cards.k4.checklist[2].text,
            board.cards.k4.checklist[3].text,
        })
        assert.equals(21, board.cards.k4.updated)
        assert_invariants(state)
        local ok, err = Model.moveChecklistItem(board, "k4", 4, 1, 22)
        assert.is_nil(ok)
        assert.equals("checklist item not found", err)
        assert_invariants(state)
    end)

    it("sets a column's collapsed state", function()
        local state = Model.newState()
        local board = state.boards[1]
        local column_id = board.columns[1].id
        assert.is_true(Model.setColumnCollapsed(board, column_id, true))
        assert.is_true(board.columns[1].collapsed)
        assert_invariants(state)
        assert.is_true(Model.setColumnCollapsed(board, column_id, false))
        assert.is_false(board.columns[1].collapsed)
        assert_invariants(state)
        local ok, err = Model.setColumnCollapsed(board, column_id, "yes")
        assert.is_nil(ok)
        assert.equals("collapsed must be a boolean", err)
        assert.is_false(board.columns[1].collapsed)
        assert_invariants(state)
        ok, err = Model.setColumnCollapsed(board, "c99", true)
        assert.is_nil(ok)
        assert.equals("column not found", err)
        assert_invariants(state)
    end)

    it("updates moved only when a card changes columns", function()
        local state = Model.newState()
        local board = state.boards[1]
        local todo, doing = board.columns[1].id, board.columns[2].id
        assert.is_true(Model.addCard(board, todo, { title = "Task" }, nil, 10))
        assert.equals(10, board.cards.k4.moved)
        assert_invariants(state)

        assert.is_true(Model.moveCard(board, "k4", todo, 1, 20))
        assert.equals(10, board.cards.k4.moved)
        assert_invariants(state)
        assert.is_true(Model.moveCard(board, "k4", doing, nil, 30))
        assert.equals(30, board.cards.k4.moved)
        assert_invariants(state)
        assert.is_true(Model.moveCard(board, "k4", doing, 1, 40))
        assert.equals(30, board.cards.k4.moved)
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
