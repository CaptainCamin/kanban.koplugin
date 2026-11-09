-- Run from KOReader's runtime directory using its bundled luajit.
-- Requires an isolated KO_HOME; never point this at your normal settings.
local repo, artifacts = assert(arg[1], 'repository path required'), assert(arg[2], 'artifact directory required')
assert(os.getenv('KO_HOME') == artifacts, 'KO_HOME must be the isolated artifact directory')
require('setupkoenv')
G_defaults = require('luadefaults'):open()
G_reader_settings = require('luasettings'):open(artifacts .. '/settings.reader.lua')
local Device = require('device')
require('document/canvascontext'):init(Device)
local UI = require('ui/uimanager')
package.path = repo .. '/kanban.koplugin/?.lua;' .. package.path
local Model = require('model')
local state = Model.newState()
local board = state.boards[1]
for i = 1, 24 do
    assert(Model.addCard(board, board.columns[1].id, {title='Review release task ' .. i, notes=i == 1 and 'Consider the next action and record the decision.' or ''}))
end
assert(Model.addCard(board, board.columns[2].id, {title='Prepare the next release', notes='Confirm the final checklist.'}))
local id = board.columns[1].cards[1]
assert(Model.addChecklistItem(board, id, 'Check a long checklist item that should wrap across two lines without competing with edit and delete buttons'))
assert(Model.addChecklistItem(board, id, 'Review the final draft'))
local View = require('boardview')
local view = View:new{state=state,ui={onSetRotationMode=function(_,mode) Device.screen:setRotationMode(mode) end}}
UI:show(view)
local function capture(widget, name)
    local bb = require('ffi/blitbuffer').new(Device.screen:getWidth(), Device.screen:getHeight(), require('ffi/blitbuffer').TYPE_BB8)
    bb:fill(require('ffi/blitbuffer').COLOR_WHITE)
    widget:paintTo(bb, 0, 0)
    if widget == view then
        assert(view[1]:getSize().h <= Device.screen:getHeight(), 'board must fit vertically')
        for _, target in ipairs(view.add_card_targets) do
            assert(target.frame.dimen.y + target.frame.dimen.h <= view.footer_region.dimen.y,
                'creation control must fit above footer')
        end
    end
    bb:writePNG(artifacts .. '/' .. name .. '.png')
    bb:free()
end
capture(view, 'ux-board')
assert(#view.add_card_targets == #view.header_targets, 'creation available on first page')
local col = view.column_rects[1]
assert(#col.pages > 1)
assert(view:onSwipe(nil,{direction='north',pos=require('ui/geometry'):new{x=col.rect.x,y=col.rect.y}}))
assert(view.card_start[col.id] > 1)
capture(view, 'ux-board-page2')
assert(#view.add_card_targets == #view.header_targets, 'creation available on middle page')
-- Stationary hold opens contextual actions; hold-and-slide remains a drag.
view:revealCard(board.columns[1].id, 1)
view:refresh()
capture(view, 'ux-board')
local Move = require('cardmove')
local Geom = require('ui/geometry')
local function top() return UI._window_stack[#UI._window_stack].widget end
local function cardPosition()
    for _, target in ipairs(view.card_targets) do
        if target.id == id then
            local r = target.frame.dimen
            return Geom:new{x=r.x+r.w/2,y=r.y+r.h/2}
        end
    end
    error('card must be visible')
end
local pos = cardPosition()
assert(view:onHold(nil,{pos=pos}))
assert(view:onHoldRelease(nil,{pos=pos}))
assert(view.moving_card == nil and top().buttons)
local actions = top()
assert(actions.buttons[1][1].text == 'Move to Doing →')
assert(actions.buttons[1][1].font_size > actions.buttons[4][1].font_size)
capture(actions, 'ux-card-actions')
actions.buttons[4][1].callback()
assert(top().buttons[1][2].text == 'Doing →')
top().buttons[#top().buttons][1].callback()
top().buttons[4][2].callback()
assert(view.selected_cards[id])
view:setSelectMode(false)
capture(view, 'ux-before-drag')
assert(Move.hold(view,cardPosition()))
capture(view, 'ux-drag')
local header = view.header_targets[2].frame.dimen
local destination = Geom:new{x=header.x+header.w/2,y=header.y+header.h/2}
assert(Move.pan(view,destination))
assert(Move.release(view,destination))
assert(view:locateCard(id).id == board.columns[2].id)
top().buttons[1][1].callback() -- Undo movement.
assert(view:locateCard(id).id == board.columns[1].id)
local cardview = require('cardview').show(view, id)
capture(cardview, 'ux-card')
cardview:changeChecklist(function(b) return Model.toggleChecklistItem(b,id,1) end)
assert(view:getBoard().cards[id].checklist[1].done)
cardview:showChecklistActions(1)
local dialog = UI._window_stack[#UI._window_stack].widget
assert(dialog.buttons[1][1].text == 'Edit')
dialog.buttons[2][1].callback()
assert(#view:getBoard().cards[id].checklist == 1)
UI._window_stack[#UI._window_stack].widget.buttons[1][1].callback()
assert(#view:getBoard().cards[id].checklist == 2)
cardview:onClose()
require('carddialog').showBoardMenu(view)
local menu
for _, window in ipairs(UI._window_stack) do
    if window.widget.buttons and window.widget.title == board.name then menu = window.widget end
end
assert(menu and menu.buttons[1][1].text == 'Today')
capture(menu, 'ux-menu')
menu.buttons[1][1].callback()
local today = UI._window_stack[#UI._window_stack].widget
assert(today.title_bar.title == 'Today')
capture(today, 'ux-today')
today:onClose()
require('carddialog').showBoardMenu(view)
menu = UI._window_stack[#UI._window_stack].widget
local secondary = menu.buttons[#menu.buttons]
secondary[1].callback()
assert(top().title == 'Board tools')
assert(top().buttons[1][1].text == 'Add column')
UI:close(top())
require('carddialog').showBoardMenu(view)
top().buttons[#top().buttons][2].callback()
assert(top().title == 'Import / export')
assert(top().buttons[1][1].text == 'GitHub issues…')
UI:close(top())
-- Capture under a filter and save through the actual editor.
assert(Model.addLabel(view:getBoard(), 'Focus'))
local label = view:getBoard().labels[1].id
view.label_filter = label
view:refresh()
require('carddialog').editCard(view, view:getBoard().columns[1].id)
local editor = UI._window_stack[#UI._window_stack].widget
editor.getFields = function() return {'A filtered task', ''} end
editor:save()
local filtered = Model.filteredCards(view:getBoard(), view:getBoard().columns[1], label)
assert(#filtered == 1 and view:getBoard().cards[filtered[1]].title == 'A filtered task')
assert(#view.add_card_targets == #view.header_targets)
capture(view, 'ux-filtered')
print('PASS: layout, swipes, stationary hold actions, selection, drag/undo, menu hierarchy, checklist and filtered capture')

local labels = dofile(repo .. '/.agents/test-labels.lua')
print('PASS: ' .. labels.passed .. ' existing labels integration checks')

dofile(repo .. '/.agents/test-actionpanel.lua')

dofile(repo .. '/.agents/test-editor.lua')
