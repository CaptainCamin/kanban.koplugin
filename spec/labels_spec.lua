local Model = require('model')
local Markdown = require('markdown')

describe('Board labels', function()
    it('keeps assignments through rename, archive and restore, and cleans them on deletion', function()
        local board = Model.newState().boards[1]
        assert.is_true(Model.addLabel(board, ' Bug '))
        local id = board.labels[1].id
        assert.is_nil(Model.addLabel(board, 'bug'))
        assert.is_nil(Model.addLabel(board, '  '))
        assert.is_true(Model.addCard(board, 'c1', {title = 'Fix', labels = {id}}, nil, 10))
        local card_id = board.columns[1].cards[1]
        assert.is_true(Model.renameLabel(board, id, 'Defect'))
        assert.equals('[Defect]', Model.labelText(board, board.cards[card_id]))
        Model.archiveCard(board, card_id)
        Model.restoreCard(board, card_id, 'c2')
        assert.is_true(Model.hasLabel(board.cards[card_id], id))
        assert.is_true(Model.deleteLabel(board, id))
        assert.same({}, board.cards[card_id].labels)
    end)

    it('validates assignments atomically and filters without changing card order', function()
        local board = Model.newState().boards[1]
        Model.addLabel(board, 'Ready')
        local id = board.labels[1].id
        Model.addCard(board, 'c1', {title = 'First'})
        Model.addCard(board, 'c1', {title = 'Second'})
        local first, second = unpack(board.columns[1].cards)
        assert.is_true(Model.setCardLabels(board, second, {id, id}, 12))
        assert.same({id}, board.cards[second].labels)
        assert.is_nil(Model.setCardLabels(board, second, {'missing'}, 13))
        assert.same({id}, board.cards[second].labels)
        assert.same({second}, Model.filteredCards(board, board.columns[1], id))
        assert.same({first, second}, board.columns[1].cards)
        local snapshot = Model.copyBoard(board)
        Model.deleteLabel(board, id)
        local state = {boards = {board}}
        Model.restoreBoard(state, snapshot)
        assert.is_true(Model.hasLabel(state.boards[1].cards[second], id))
    end)

    it('round trips assigned, archived and unused labels through Markdown', function()
        local board = Model.newState().boards[1]
        Model.addLabel(board, 'Bug --> [urgent], שלום')
        Model.addLabel(board, 'Unused')
        local id = board.labels[1].id
        Model.addCard(board, 'c1', {title = 'Fix', notes = 'Notes', labels = {id}})
        local card_id = board.columns[1].cards[1]
        Model.addChecklistItem(board, card_id, 'Check it')
        Model.archiveCard(board, card_id)
        local imported = assert(Markdown.import(Markdown.export(board)))
        assert.equals(2, #imported.labels)
        assert.equals(board.labels[1].name, imported.labels[1].name)
        local card = imported.cards[imported.archived[1]]
        assert.equals(Model.labelText(board, board.cards[card_id]), Model.labelText(imported, card))
        assert.equals('Notes', card.notes)
        assert.equals('Check it', card.checklist[1].text)
    end)
end)
