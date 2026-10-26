local Model = require("model")
local Markdown = require("markdown")

local function find_column(board, name)
    for _, column in ipairs(board.columns) do
        if column.name == name then
            return column
        end
    end
end

local function card_data(board, card_id)
    local card = board.cards[card_id]
    return {
        title = card.title,
        notes = card.notes,
        checklist = card.checklist,
        archived = card.archived,
    }
end

local function semantic_data(board)
    local data = { name = board.name, columns = {}, archived = {} }
    for _, column in ipairs(board.columns) do
        local column_data = { name = column.name, cards = {} }
        for _, card_id in ipairs(column.cards) do
            column_data.cards[#column_data.cards + 1] = card_data(board, card_id)
        end
        data.columns[#data.columns + 1] = column_data
    end
    for _, card_id in ipairs(board.archived) do
        data.archived[#data.archived + 1] = card_data(board, card_id)
    end
    return data
end

local function assert_invariants(board)
    local locations = {}
    local archived = {}
    for _, column in ipairs(board.columns) do
        for _, card_id in ipairs(column.cards) do
            assert.is_truthy(board.cards[card_id], "column contains an unknown card")
            locations[card_id] = (locations[card_id] or 0) + 1
        end
    end
    for _, card_id in ipairs(board.archived) do
        assert.is_truthy(board.cards[card_id], "archive contains an unknown card")
        locations[card_id] = (locations[card_id] or 0) + 1
        archived[card_id] = true
    end
    for card_id, card in pairs(board.cards) do
        assert.equals(1, locations[card_id], "card must have one location")
        assert.equals(card.archived, archived[card_id] == true)
        assert.is_table(card.checklist)
        for _, item in ipairs(card.checklist) do
            assert.is_string(item.text)
            assert.is_boolean(item.done)
        end
    end
end

local function example_board()
    local state = Model.newState()
    local board = state.boards[1]
    assert.is_true(Model.renameBoard(state, board.id, "Roadmap #1 & release"))
    assert.is_true(Model.renameColumn(board, "c1", "Ideas * & [now]"))
    assert.is_true(Model.renameColumn(board, "c2", "Empty _column_"))
    assert.is_true(Model.renameColumn(board, "c3", "Doing / blocked"))
    assert.is_true(Model.moveColumn(board, "c3", 1))

    local ideas = find_column(board, "Ideas * & [now]")
    assert.is_true(Model.addCard(board, ideas.id, {
        title = "Plan *release* #1 [x] C:\\notes ends **",
        notes = "First line\n\n# Markdown heading\n- [ ] literal checklist\n"
            .. "<!-- /kanban:notes -->\n  indented\n",
    }, nil, 100))
    assert.is_true(Model.addChecklistItem(board, "k4", "Write *release* notes", nil, 110))
    assert.is_true(Model.addChecklistItem(board, "k4", "Run [tests] & ship", nil, 120))
    assert.is_true(Model.toggleChecklistItem(board, "k4", 2, 130))
    assert.is_true(Model.addCard(board, ideas.id, { title = "[ ] marker-looking title" }, nil, 140))

    assert.is_true(Model.addCard(board, ideas.id, {
        title = "Archived #1 *card*",
        notes = "Archive note\n\nlast line",
    }, nil, 150))
    assert.is_true(Model.addChecklistItem(board, "k6", "Already done", nil, 160))
    assert.is_true(Model.toggleChecklistItem(board, "k6", 1, 170))
    assert.is_true(Model.archiveCard(board, "k6"))
    assert.is_true(Model.addCard(board, ideas.id, { title = "Second archived card" }, nil, 180))
    assert.is_true(Model.archiveCard(board, "k7"))
    return board
end

describe("kanban Markdown", function()
    it("round-trips board content, structure, notes, checklists, and archives", function()
        local source = example_board()
        local exported = Markdown.export(source)
        assert.is_truthy(exported:find("# Roadmap #1 & release", 1, true))
        assert.is_truthy(exported:find("## Empty _column_", 1, true))
        assert.is_truthy(exported:find("- Plan *release* #1 [x] C:"
            .. string.rep("\\", 2) .. "notes ends **", 1, true))
        assert.is_truthy(exported:find("\n- [ ] marker-looking title\n", 1, true))
        assert.is_truthy(exported:find("  - [ ] Write *release* notes", 1, true))
        assert.is_truthy(exported:find("  - [x] Run [tests] & ship", 1, true))
        assert.is_truthy(exported:find("  <!-- kanban:notes -->", 1, true))
        assert.is_nil(exported:find(
            "  <!-- kanban:notes -->\n  <!-- /kanban:notes -->", 1, true))
        assert.is_truthy(exported:find("# Archived cards", 1, true))

        local imported, err = Markdown.import(exported, nil, 999)
        assert.is_nil(err)
        assert.same(semantic_data(source), semantic_data(imported))
        assert_invariants(imported)
        assert.equals(999, imported.cards[imported.columns[2].cards[1]].created)
        assert.equals(999, imported.cards[imported.archived[1]].created)
    end)

    it("accepts CRLF, extra blank lines, and a missing archived section", function()
        local source = "\n\n# Hand edited\r\n\r\n\r\n## Inbox\r\n\r\n"
            .. "- **One card**\r\n\r\n  <!-- kanban:notes -->\r\n"
            .. "  > first line\r\n  >\r\n  > last line\r\n"
            .. "  <!-- /kanban:notes -->\r\n\r\n  - [X] Finished\r\n\r\n"
            .. "## Empty column\r\n\r\n"
        local imported, err = Markdown.import(source, nil, 321)
        assert.is_nil(err)
        assert.equals("Hand edited", imported.name)
        assert.same({ "Inbox", "Empty column" }, {
            imported.columns[1].name,
            imported.columns[2].name,
        })
        local card = imported.cards[imported.columns[1].cards[1]]
        assert.equals("first line\n\nlast line", card.notes)
        assert.same({ { text = "Finished", done = true } }, card.checklist)
        assert.same({}, imported.archived)
        assert_invariants(imported)
    end)

    it("adds an import to an existing state as a new Model board", function()
        local state = Model.newState()
        local original_board = state.boards[1]
        local imported, err = Markdown.import("# Imported\n\n## Inbox\n", state, 456)
        assert.is_nil(err)
        assert.equals(2, #state.boards)
        assert.equals("b2", imported.id)
        assert.equals("Imported", imported.name)
        assert.equals(imported.id, state.current_board)
        assert.equals("My board", original_board.name)
        assert.equals("c4", imported.columns[1].id)
        assert_invariants(imported)
    end)

    it("rejects malformed or unusable Markdown without changing a destination state", function()
        local malformed = {
            "",
            "not a heading",
            "# Board\n\n- **Card**\n",
            "# Board\n\n## Tasks\n\n- \n",
            "# Board\n\n## Tasks\n\n- **Card**\n  <!-- kanban:notes -->\n  > orphan\n",
            "# Board\n",
        }
        for _, text in ipairs(malformed) do
            local state = Model.newState()
            local before = state.boards[1]
            local imported, err = Markdown.import(text, state)
            assert.is_nil(imported)
            assert.is_string(err)
            assert.equals(1, #state.boards)
            assert.equals(before, state.boards[1])
        end
    end)
end)
