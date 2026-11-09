-- Run inside a KOReader test instance with a Kanban board open:
-- curl 'http://127.0.0.1:8080/koreader/globals/dofile/%22/workspace/kanban.koplugin/.agents/test-labels.lua%22'
-- Uses real widgets, restores the original state even when an assertion fails.
local UI = require('ui/uimanager')
local Model = require('model')
local Storage = require('storage')
local Dialog = require('carddialog')
local Markdown = require('markdown')
local BB = require('ffi/blitbuffer')
local view
for _, window in ipairs(UI._window_stack) do
    if window.widget.getBoard and window.widget.revealCard then view = window.widget end
end
assert(view, 'Open the Kanban board before running this test')
local original_state = view.state
local original_position = {first_column=view.first_column, card_start=view.card_start, label_filter=view.label_filter}
local function top() return UI._window_stack[#UI._window_stack].widget end
local function closeDialogs()
    while top() ~= view do UI:close(top()) end
end
local function click(text)
    local dialog = top()
    for _, row in ipairs(dialog.buttons or {}) do
        for _, button in ipairs(row) do
            if button.text == text then button.callback(); return end
        end
    end
    error('Button not found: '..text)
end
local results = {}
local function check(name, value)
    assert(value, name)
    results[#results + 1] = name
end
local ok, err = xpcall(function()
    closeDialogs()
    view.state = Model.newState()
    view:resetPosition()
    view:refresh()
    local board = view:getBoard()

    Dialog.showLabels(view)
    click('Add label')
    top():setInputText('Ready')
    click('Add')
    local ready = board.labels[1].id
    click('Add label')
    top():setInputText('Bug')
    click('Add')
    local bug = board.labels[2].id
    check('create labels in real dialogs', #board.labels == 2)
    click('Close')

    Dialog.editCard(view, 'c1')
    local editor = top()
    editor.input_fields[1]:setText('Fix offline upload')
    editor.input_fields[2]:setText('Keep drafts locally')
    editor.label_buttons[ready].callback()
    editor.label_buttons[bug].callback()
    click('Add')
    local id = board.columns[1].cards[1]
    check('new card retains both chosen labels and notes', Model.hasLabel(board.cards[id], ready)
        and Model.hasLabel(board.cards[id], bug) and board.cards[id].notes == 'Keep drafts locally')

    editor=Dialog.editCard(view, 'c1', id)
    editor.label_buttons[bug].callback()
    click('Cancel')
    local discard=top();UI:close(discard);discard.ok_callback()
    check('cancel editor preserves existing assignments', Model.hasLabel(board.cards[id], bug))
    editor=Dialog.editCard(view, 'c1', id)
    editor.label_buttons[bug].callback()
    click('Save')
    check('save editor removes only the unchecked label', Model.hasLabel(board.cards[id], ready)
        and not Model.hasLabel(board.cards[id], bug))

    for i=2,24 do Model.addCard(board, 'c1', {title='Ready task '..i, labels={ready}}) end
    Model.addCard(board, 'c2', {title='Other task'})
    Dialog.filterLabels(view)
    click('Ready')
    check('filter hides unmatched cards from rendered columns', #view.card_targets > 0)
    for _, target in ipairs(view.card_targets) do
        check('visible card matches active filter: '..target.id, Model.hasLabel(board.cards[target.id], ready))
    end
    view.card_start.c1 = 15
    view:refresh()
    local previous = view.card_start.c1
    check('fixture reaches a later page', previous > 1)
    Model.addCard(board, 'c1', {title='Hidden card'})
    view:revealCard('c1', #board.columns[1].cards)
    view:refresh()
    check('hidden card addition preserves page', view.card_start.c1 == previous)
    view:revealCard('c1', 2)
    check('matching card uses filtered position', view.card_start.c1 == 2)
    for _, filtered in ipairs({true, false}) do
        view.label_filter = filtered and ready or nil
        view:refresh()
        view:setMovingCard(id)
        local source, destination
        for _, target in ipairs(view.header_targets) do
            if target.id == 'c1' then source = target.frame.background
            elseif target.id == 'c2' then destination = target.frame.background end
        end
        check('drop targets preserve source identity, filtered='..tostring(filtered),
            source == BB.COLOR_WHITE and destination == BB.COLOR_BLACK)
        view:setMovingCard(nil)
    end

    Dialog.showLabels(view)
    click('Ready')
    top():setInputText('Publish')
    click('Save')
    check('rename retains assignments', Model.labelText(board, board.cards[id]) == '[Publish]')
    click('Close')
    require('cardview').show(view, id)
    check('detail view renders labelled card', top().card_id == id)
    top():onClose()
    Storage.save(view.state)
    local loaded = Storage.load().boards[1]
    check('saved labels reload with assignments', Model.labelText(loaded, loaded.cards[id]) == '[Publish]')
    local imported = assert(Markdown.import(Markdown.export(board)))
    local imported_card = imported.cards[imported.columns[1].cards[1]]
    check('Markdown retains assigned and unused labels', #imported.labels == 2
        and Model.labelText(imported, imported_card) == '[Publish]')

    Dialog.filterLabels(view)
    click('Publish')
    Dialog.showLabels(view)
    top().buttons[1][2].callback() -- Delete Publish
    top().ok_callback()
    closeDialogs()
    check('deletion clears assignments and invalid filter', not Model.hasLabel(board.cards[id], ready)
        and view.label_filter == nil)
    view:undo()
    board = view:getBoard()
    check('undo restores label and assignments', Model.hasLabel(board.cards[id], ready)
        and Model.findLabel(board, ready).name == 'Publish')
    closeDialogs()
end, debug.traceback)
closeDialogs()
view.state = original_state
view.first_column, view.card_start, view.label_filter = original_position.first_column, original_position.card_start, original_position.label_filter
view.moving_card = nil
Storage.save(original_state)
view:refresh()
assert(ok, err)
return {passed=#results, checks=results}
