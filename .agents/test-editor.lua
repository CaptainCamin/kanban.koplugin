-- Real-widget editor, draft/undo and filter regressions, within test-ux's runtime.
local UI=require('ui/uimanager')
local Model=require('model')
local Dialog=require('carddialog')
local BB=require('ffi/blitbuffer')
local Screen=require('device').screen
local Event=require('ui/event')
local Geom=require('ui/geometry')
local view
for _,window in ipairs(UI._window_stack) do
    if window.widget.getBoard and window.widget.revealCard then view=window.widget end
end
assert(view)
local original=view.state
local original_virtual=G_reader_settings:readSetting('virtual_keyboard_enabled')
local function top() return UI._window_stack[#UI._window_stack].widget end
local function render(widget,name)
    local bb=BB.new(Screen:getWidth(),Screen:getHeight(),BB.TYPE_BB8)
    bb:fill(BB.COLOR_WHITE);widget:paintTo(bb,0,0)
    if name then bb:writePNG(os.getenv('KO_HOME')..'/'..name..'.png') end
    bb:free()
end
local ok,err=xpcall(function()
    view.state=Model.newState();view.label_filter=nil;view:resetPosition();view:refresh()
    local board=view:getBoard()
    assert(Model.addLabel(board,'Feature'))
    local label=board.labels[1].id
    local editor=Dialog.editCard(view,'c1')
    editor.input_fields[1]:setText('Publish a clear release plan')
    editor.input_fields[2]:setText('Explain the next steps and confirm the delivery date.\nKeep the draft local until Save.')
    editor.label_buttons[label].callback()
    editor.checklist={{text='Confirm the scope',done=true},{text='Review the release notes',done=false}}
    editor:refresh()
    assert(#board.columns[1].cards==0,'draft must not change board')
    render(editor,'ux-editor')
    editor:onScreenResize()
    assert(editor:getFields()[1]=='Publish a clear release plan' and #editor.checklist==2,
        'resize must preserve the draft')
    local rotation=Screen:getRotationMode()
    assert(editor:onSetRotationMode(rotation%2==0 and rotation+1 or rotation-1))
    assert(editor:getFields()[1]=='Publish a clear release plan' and editor.selected_labels[label])
    assert(editor:onSetRotationMode(rotation))
    render(editor)
    G_reader_settings:saveSetting('virtual_keyboard_enabled',true)
    editor:onSwitchFocus(editor.input_fields[2])
    render(editor)
    assert(editor._input_widget:isKeyboardVisible(),'inline notes must support a keyboard')
    local keyboard_h=editor._input_widget:getKeyboardDimen().h
    local crop=editor.cropping_widget.dimen
    assert(crop.y+crop.h <= Screen:getHeight()-keyboard_h,'form must fit above keyboard')
    local notes=editor.input_fields[2].dimen
    assert(notes.y >= crop.y and notes.y+notes.h <= crop.y+crop.h,
        'focused notes must be visible above keyboard')
    editor:onCloseKeyboard()
    assert(editor:save())
    local id=board.columns[1].cards[1]
    assert(board.cards[id].notes:match('Keep the draft'))
    assert(#board.cards[id].checklist==2 and board.cards[id].checklist[1].done)
    assert(Model.hasLabel(board.cards[id],label))
    editor.checklist[1].text='Mutated draft'
    assert(board.cards[id].checklist[1].text=='Confirm the scope','saved checklist must be copied')
    editor=Dialog.editCard(view,'c1',id)
    editor.input_fields[2]:setText('Discard this edit')
    editor.checklist[1].done=false;editor:toggleLabel(label)
    editor:requestClose()
    local confirm=top();UI:close(confirm);confirm.ok_callback()
    assert(board.cards[id].notes~='Discard this edit' and board.cards[id].checklist[1].done)
    assert(Model.hasLabel(board.cards[id],label),'discard must preserve every field')
    editor=Dialog.editCard(view,'c1',id)
    editor.input_fields[1]:setText('   ')
    assert(editor:save()==false)
    UI:close(top()) -- validation message, editor remains open
    editor.input_fields[1]:setText('Revised plan')
    editor.input_fields[2]:setText('Revised notes')
    editor.checklist={{text='One new item',done=false}};editor:toggleLabel(label)
    assert(editor:save())
    assert(board.cards[id].title=='Revised plan' and #board.cards[id].checklist==1)
    assert(view:undo())
    board=view:getBoard()
    assert(board.cards[id].title=='Publish a clear release plan' and #board.cards[id].checklist==2)
    assert(Model.hasLabel(board.cards[id],label),'one undo restores all editor fields')
    local title=board.cards[id].title
    assert(not Model.editCard(board,id,{title='Must not apply',labels={},checklist={{text=' '}}}))
    assert(board.cards[id].title==title and Model.hasLabel(board.cards[id],label),'invalid draft must be atomic')
    local next_id=board.next_id
    assert(not Model.addCard(board,'c1',{title='Invalid new card',checklist={{text=''}}}))
    assert(board.next_id==next_id,'invalid new draft must not consume ids')
    view.label_filter=label;view:refresh();render(view,'ux-card-previews')
    assert(view.filter_strip and view.filter_clear_button)
    local r=view.filter_clear_button.dimen
    assert(view:handleEvent(Event:new('Gesture',{ges='tap',pos=Geom:new{x=r.x+r.w/2,y=r.y+r.h/2}})))
    assert(not view.label_filter and not view.filter_strip,'clear filter must restore full board')
end,debug.traceback)
while top()~=view do UI:close(top()) end
G_reader_settings:saveSetting('virtual_keyboard_enabled',original_virtual)
view.state=original;view.label_filter=nil;view:resetPosition();view:refresh()
require('storage').save(original)
assert(ok,err)
print('PASS: unified editor drafts, inline keyboard, cancellation, validation, atomic save/undo, previews and filter clear')
