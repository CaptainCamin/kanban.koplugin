-- Real-widget checks in an English KOReader instance, using a fake GitHub API.
-- Invoke through HTTP inspector like .agents/test-labels.lua. No issues are created.
local UI = require('ui/uimanager')
local Model = require('model')
local Storage = require('storage')
local Store = require('githubstore')
local Api = require('githubapi')
local Network = require('ui/network/manager')
local Dialog = require('githubdialog')
local GitHub = require('github')
local view
for _, window in ipairs(UI._window_stack) do
    if window.widget.getBoard and window.widget.revealCard then view=window.widget end
end
assert(view, 'Open a Kanban board first')
local original = {
    state=view.state, first_column=view.first_column, card_start=view.card_start,
    label_filter=view.label_filter, open=Store.open, client=Api.client,
    online=Network.runWhenOnline, nextTick=UI.nextTick, load=Storage.load, save=Storage.save,
}
local data, writes, queue, requests = {uploads={}}, 0, {}, 0
Store.open=function() return data, function() writes=writes+1 end end
Storage.save=function() end -- Do not write test boards to the user's settings.
Storage.load=function() return view.state end
Network.runWhenOnline=function(_, callback) callback() end
UI.nextTick=function(_, callback) queue[#queue+1]=callback end
local function top() return UI._window_stack[#UI._window_stack].widget end
local function closeDialogs() while top() ~= view do UI:close(top()) end end
local function click(text)
    for _, row in ipairs(top().buttons or {}) do
        for _, button in ipairs(row) do
            if button.text == text then button.callback(); return end
        end
    end
    error('Button not found: '..text)
end
local results = {}
local function check(name, value) assert(value, name); results[#results+1]=name end
local ok, err = xpcall(function()
    closeDialogs()
    view.state=Model.newState()
    local board=view:getBoard()
    Model.addLabel(board, 'Feature')
    Model.addLabel(board, 'Bug')
    Model.addCard(board, 'c1', {title='Fix drafts', notes='Offline notes', labels={board.labels[1].id,board.labels[2].id}})
    Model.addCard(board, 'c2', {title='Second card', labels={board.labels[2].id}})
    Model.addCard(board, 'c1', {title='Private idea'})
    view:resetPosition(); view:refresh()
    Dialog.show(view)
    click('Repository: Not connected')
    top():setInputText('CaptainCamin/kanban.koplugin')
    click('Save')
    check('repository and stable identity saved', board.github.repository=='captaincamin/kanban.koplugin' and #board.github_id==32)
    click('Labels to upload: 0')
    click('☐ Feature'); click('☐ Bug'); click('Close')
    check('multiple upload labels enabled', board.github.upload_labels[board.labels[1].id] and board.github.upload_labels[board.labels[2].id])
    Dialog.show(view)
    click('GitHub label mappings…')
    click('Feature → Feature')
    top():setInputText('enhancement'); click('Save')
    click('Bug → Bug')
    top():setInputText('bug'); click('Save'); click('Close')
    check('GitHub label names configured', board.github.label_map[board.labels[1].id]=='enhancement' and board.github.label_map[board.labels[2].id]=='bug')
    Dialog.show(view)
    click('Set GitHub token…')
    check('token input is masked', top().text_type=='password')
    top():setInputText('FAKE_TEST_TOKEN'); click('Save')
    click('Preview batch…')
    check('two eligible cards, with the doubly labelled card counted once', #GitHub.candidates(board,data.uploads)==2)
    Api.client=function(token)
        assert(token=='FAKE_TEST_TOKEN')
        return function(method, path, payload)
            requests=requests+1
            assert(writes>0 and method=='POST')
            if requests==1 then
                check('payload includes both mapped labels', payload.labels[1]=='enhancement' and payload.labels[2]=='bug')
                return {number=101, html_url='https://github.com/CaptainCamin/kanban.koplugin/issues/101'}
            end
            return nil, 'Simulated permission rejection', 403
        end
    end
    click('Publish batch')
    local confirm=top()
    confirm.ok_callback(); UI:close(confirm)
    local steps=0
    while #queue>0 do
        steps=steps+1; assert(steps<30, 'batch did not stop')
        table.remove(queue,1)()
    end
    check('partial batch stops after rejection', requests==2)
    local remaining=GitHub.candidates(board,data.uploads)
    check('only rejected card remains for retry', #remaining==1 and remaining[1].title=='Second card')
    local link=Dialog.issue(board,board.columns[1].cards[1])
    check('successful issue link retained', link and link.number==101)
    closeDialogs()
    require('cardview').show(view, board.columns[1].cards[1])
    check('published card detail renders', top().card_id==board.columns[1].cards[1])
    top():onClose()
    Dialog.show(view)
    click('Forget GitHub token')
    check('forget token preserves upload history', data.token==nil and next(data.uploads)~=nil)
end, debug.traceback)
closeDialogs()
Store.open, Api.client, Network.runWhenOnline, UI.nextTick = original.open, original.client, original.online, original.nextTick
Storage.load, Storage.save = original.load, original.save
view.state, view.first_column, view.card_start, view.label_filter = original.state, original.first_column, original.card_start, original.label_filter
view:refresh()
assert(ok, err)
return {passed=#results, checks=results}
