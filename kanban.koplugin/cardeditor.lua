-- A single, draft-based workspace for all card fields. Nothing is saved until
-- Save/Add; label and checklist changes remain local to this editor.
local BB = require('ffi/blitbuffer')
local ConfirmBox = require('ui/widget/confirmbox')
local Device = require('device')
local Font = require('ui/font')
local Frame = require('ui/widget/container/framecontainer')
local Geom = require('ui/geometry')
local GestureRange = require('ui/gesturerange')
local HGroup = require('ui/widget/horizontalgroup')
local HSpan = require('ui/widget/horizontalspan')
local InfoMessage = require('ui/widget/infomessage')
local InputContainer = require('ui/widget/container/inputcontainer')
local InputDialog = require('ui/widget/inputdialog')
local InputText = require('ui/widget/inputtext')
local Model = require('model')
local Scroll = require('ui/widget/container/scrollablecontainer')
local Size = require('ui/size')
local Style = require('kanbanstyle')
local Text = require('ui/widget/textwidget')
local TitleBar = require('ui/widget/titlebar')
local UI = require('ui/uimanager')
local VGroup = require('ui/widget/verticalgroup')
local VSpan = require('ui/widget/verticalspan')
local _ = require('gettext')
local Screen = Device.screen
local CardEditor = InputContainer:extend{covers_fullscreen=true}

function CardEditor:init()
    self.board = self.view:getBoard()
    local card = self.card_id and self.board.cards[self.card_id]
    self.selected_labels, self.checklist = {}, {}
    for _, id in ipairs(card and card.labels or {}) do self.selected_labels[id]=true end
    if not card and self.view.label_filter then self.selected_labels[self.view.label_filter]=true end
    for _, item in ipairs(card and card.checklist or {}) do
        self.checklist[#self.checklist+1]={text=item.text,done=item.done}
    end
    self.original = {title=card and card.title or '', notes=card and card.notes or ''}
    self:createInputs(self.original.title,self.original.notes)
    self._input_widget=self.input_fields[1];self._input_widget:focus()
    self:rebuild()
    self.ges_events.Tap = { GestureRange:new{
        ges = 'tap',
        range = function() return Geom:new{x=0,y=0,w=Screen:getWidth(),h=Screen:getHeight()} end,
    } }
    if Device:hasKeys() then self.key_events.Close={{Device.input.group.Back}} end
end
function CardEditor:createInputs(title,notes)
    local width = Screen:getWidth()-2*Size.padding.large-Scroll:getScrollbarWidth()
    self.input_fields={}
    for index, definition in ipairs({
        {text=title,hint=_('What needs doing?'),height=56},
        {text=notes,hint=_('Details, links and next steps'),height=112},
    }) do
        self.input_fields[index]=InputText:new{
            text=definition.text,hint=definition.hint,width=width,
            height=Screen:scaleBySize(definition.height),scroll=true,
            face=Font:getFace('cfont',index==1 and 22 or 18),
            focused=false,parent=self,margin=0,padding=Size.padding.small,
            allow_newline=index==2,
            enter_callback=index==1 and function() self:onSwitchFocus(self.input_fields[2]) end or nil,
        }
    end
end
function CardEditor:getFields()
    return {self.input_fields[1]:getText(),self.input_fields[2]:getText()}
end
local function detachInputs(widget,inputs)
    for index=#widget,1,-1 do
        local child=widget[index]
        if child==inputs[1] or child==inputs[2] then table.remove(widget,index)
        else detachInputs(child,inputs) end
    end
end
function CardEditor:rebuild()
    local offset=self.cropping_widget and self.cropping_widget:getScrolledOffset()
    for _,input in ipairs(self.input_fields) do
        input._frame_textwidget.color=BB.COLOR_BLACK
    end
    local old=self[1]
    if old then detachInputs(old,self.input_fields);old:free() end
    self.dimen=Geom:new{x=0,y=0,w=Screen:getWidth(),h=Screen:getHeight()}
    local pad,gap=Size.padding.large,Size.padding.small
    local width=self.dimen.w-2*pad-Scroll:getScrollbarWidth()
    local content=VGroup:new{align='left'}
    local function heading(text)
        table.insert(content,VSpan:new{width=pad})
        table.insert(content,Text:new{text=text,face=Font:getFace('cfont',16),bold=true})
        table.insert(content,VSpan:new{width=gap})
    end
    heading(_('Title'));table.insert(content,self.input_fields[1])
    heading(_('Notes'));table.insert(content,self.input_fields[2])
    heading(_('Labels'))
    self.label_buttons={}
    if #self.board.labels==0 then
        table.insert(content,Text:new{text=_('No labels on this board'),face=Font:getFace('cfont',16),fgcolor=Style.muted})
    end
    for _,label in ipairs(self.board.labels) do
        local id=label.id
        local button=Style.button{
            text=(self.selected_labels[id] and '☑ ' or '☐ ')..label.name,
            width=width,align='left',text_font_face='cfont',text_font_size=18,
            bordersize=self.selected_labels[id] and Style.border or 0,background=self.selected_labels[id] and Style.surface or BB.COLOR_WHITE,
            show_parent=self,callback=function() self:toggleLabel(id) end,
        }
        self.label_buttons[id]=button
        table.insert(content,button)
        table.insert(content,VSpan:new{width=gap})
    end
    heading(_('Checklist'))
    self.checklist_targets={}
    for index,item in ipairs(self.checklist) do
        local n=index
        local action_width=Screen:scaleBySize(48)
        local toggle=Style.button{
            text=(item.done and '☑ ' or '☐ ')..item.text,
            width=width-2*action_width-2*gap,height=Screen:scaleBySize(52),align='left',
            text_font_face='cfont',text_font_size=18,text_font_bold=false,bordersize=0,show_parent=self,
            callback=function() self.checklist[n].done=not self.checklist[n].done;self:refresh() end,
        }
        self.checklist_targets[n]=toggle
        table.insert(content,HGroup:new{align='center',toggle,HSpan:new{width=gap},
            Style.button{text=_('Edit'),width=action_width,bordersize=0,text_font_size=16,show_parent=self,
                callback=function() self:promptChecklist(n) end},HSpan:new{width=gap},
            Style.button{text=_('×'),width=action_width,bordersize=0,show_parent=self,
                callback=function() table.remove(self.checklist,n);self:refresh() end},
        })
    end
    self.add_checklist_button=Style.button{
        text=_('+ Add checklist item'),width=width,bordersize=Style.border,background=Style.surface,
        text_font_face='cfont',text_font_size=18,show_parent=self,
        callback=function() self:promptChecklist() end,
    }
    table.insert(content,self.add_checklist_button)
    table.insert(content,VSpan:new{width=pad})
    local column=self.view:findColumn(self.column_id)
    local bar=TitleBar:new{
        width=self.dimen.w,title=self.card_id and _('Edit card') or _('New card'),
        subtitle=column and column.name or self.board.name,
        title_face=Font:getFace('smallinfofontbold'),with_bottom_line=true,
        close_callback=function() self:requestClose() end,show_parent=self,
    }
    local save_text=self.card_id and _('Save') or _('Add')
    self.buttons={{
        {text=_('Cancel'),callback=function() self:requestClose() end},
        {text=save_text,callback=function() self:save() end},
    }}
    local footer=HGroup:new{align='center',
        Style.button{text=_('Cancel'),width=math.floor(self.dimen.w/2),bordersize=0,
            text_font_size=18,show_parent=self,callback=self.buttons[1][1].callback},
        Style.button{text=save_text,width=self.dimen.w-math.floor(self.dimen.w/2),bordersize=Style.border,
            background=Style.surface,text_font_size=18,show_parent=self,callback=self.buttons[1][2].callback},
    }
    self.footer_actions={footer[1],footer[2]}
    local keyboard_h=self._input_widget and self._input_widget:isKeyboardVisible()
        and self._input_widget:getKeyboardDimen().h or 0
    local body_y=bar:getSize().h
    self.cropping_widget=Scroll:new{
        dimen=Geom:new{x=0,y=body_y,w=self.dimen.w,h=math.max(40,self.dimen.h-keyboard_h-body_y-footer:getSize().h)},
        show_parent=self,
        Frame:new{width=self.dimen.w-Scroll:getScrollbarWidth(),padding=pad,bordersize=0,content},
    }
    self.cropping_widget:setScrolledOffset(offset)
    self[1]=Frame:new{
        width=self.dimen.w,height=self.dimen.h,bordersize=0,padding=0,background=BB.COLOR_WHITE,
        VGroup:new{align='left',bar,self.cropping_widget,footer},
    }
end
function CardEditor:refresh()
    self:rebuild();UI:setDirty(self,'ui')
end
function CardEditor:toggleLabel(id)
    self.selected_labels[id]=not self.selected_labels[id] or nil
    self:refresh()
end
function CardEditor:promptChecklist(index)
    self:onCloseKeyboard()
    local dialog
    dialog=InputDialog:new{
        title=index and _('Edit checklist item') or _('Add checklist item'),
        input=index and self.checklist[index].text or '',input_hint=_('Checklist item'),
        buttons={{
            {text=_('Cancel'),callback=function() UI:close(dialog) end},
            {text=index and _('Save') or _('Add'),is_enter_default=true,callback=function()
                local text=dialog:getInputText()
                if not text:match('%S') then return end
                UI:close(dialog)
                if index then self.checklist[index].text=text
                else self.checklist[#self.checklist+1]={text=text,done=false} end
                self:refresh()
            end},
        }},
    }
    UI:show(dialog);dialog:onShowKeyboard()
end
function CardEditor:save()
    local fields=self:getFields()
    if not fields[1]:match('%S') then
        UI:show(InfoMessage:new{text=_('A card needs a title.'),timeout=2});return false
    end
    local labels={}
    for _,label in ipairs(self.board.labels) do if self.selected_labels[label.id] then labels[#labels+1]=label.id end end
    local values={title=fields[1],notes=fields[2],labels=labels,checklist=self.checklist}
    local ok=self.view:commit(function()
        if self.card_id then return Model.editCard(self.board,self.card_id,values) end
        return Model.addCard(self.board,self.column_id,values)
    end,function()
        if not self.card_id then
            local column=self.view:findColumn(self.column_id)
            self.view:revealCard(self.column_id,#column.cards)
        end
    end)
    if ok then self:close() end
    return ok
end
function CardEditor:isChanged()
    local fields=self:getFields()
    local card=self.card_id and self.board.cards[self.card_id]
    if fields[1]~=self.original.title or fields[2]~=self.original.notes then return true end
    local labels={}
    for _,id in ipairs(card and card.labels or {}) do labels[id]=true end
    if not card and self.view.label_filter then labels[self.view.label_filter]=true end
    for _,label in ipairs(self.board.labels) do
        if (self.selected_labels[label.id] or false)~=(labels[label.id] or false) then return true end
    end
    local original=card and card.checklist or {}
    if #original~=#self.checklist then return true end
    for i,item in ipairs(original) do
        if item.text~=self.checklist[i].text or item.done~=self.checklist[i].done then return true end
    end
    return false
end
function CardEditor:requestClose()
    self:onCloseKeyboard()
    if not self:isChanged() then return self:close() end
    UI:show(ConfirmBox:new{
        text=_('Discard your card changes?'),ok_text=_('Discard'),
        ok_callback=function() self:close() end,
    })
    return true
end
function CardEditor:close()
    if self.closed then return true end
    self.closed=true;self:onCloseKeyboard();UI:close(self);UI:setDirty(nil,'flashui');return true
end
function CardEditor:onClose() return self:requestClose() end
function CardEditor:onCloseDialog() return self:requestClose() end
function CardEditor:onTap(_, ges)
    local input = self._input_widget
    if not (input and input:isKeyboardVisible()) then return false end
    local keyboard = input.keyboard
    if keyboard and keyboard.dimen and ges.pos and ges.pos:notIntersectWith(keyboard.dimen) then
        self:onCloseKeyboard()
    end
    return true
end
function CardEditor:onSwitchFocus(input)
    if self._input_widget and self._input_widget~=input then
        self._input_widget:onCloseKeyboard();self._input_widget:unfocus()
    end
    self._input_widget=input;input:focus()
    self:onShowKeyboard()
end
function CardEditor:onShowKeyboard()
    if not self._input_widget then return end
    if not ((Device:hasKeyboard() or Device:hasScreenKB()) and G_reader_settings:nilOrFalse('virtual_keyboard_enabled')) then
        self._input_widget:onShowKeyboard()
    end
    -- The modal keyboard only forwards unconsumed events to always-active widgets.
    self.is_always_active=self._input_widget:isKeyboardVisible()
    self:refresh()
    UI:forceRePaint()
    local input=self._input_widget.dimen
    local crop=self.cropping_widget.dimen
    if input and crop and input.y and crop.y then
        local delta=input.y<crop.y and input.y-crop.y
            or input.y+input.h>crop.y+crop.h and input.y+input.h-crop.y-crop.h or 0
        if delta~=0 then self.cropping_widget:_scrollBy(0,delta,true) end
    end
end
function CardEditor:onCloseKeyboard()
    local visible=self._input_widget and self._input_widget:isKeyboardVisible()
    if self._input_widget then self._input_widget:onCloseKeyboard() end
    self.is_always_active=false
    if visible and not self.closed then self:refresh() end
end
function CardEditor:onKeyboardClosed() self.is_always_active=false;self:refresh() end
function CardEditor:onKeyboardHeightChanged() self:refresh() end
function CardEditor:onScreenResize()
    local fields=self:getFields()
    self:onCloseKeyboard()
    -- The old inputs must be detached before freeing the previous layout.
    if self[1] then
        detachInputs(self[1],self.input_fields);self[1]:free();self[1]=nil
    end
    for _,input in ipairs(self.input_fields) do input:onCloseWidget() end
    self.cropping_widget=nil
    self:createInputs(fields[1],fields[2]);self._input_widget=nil
    self:refresh();return false
end
function CardEditor:onSetRotationMode(mode)
    if mode==nil or mode==Screen:getRotationMode() then return false end
    if self.view.card_view then self.view.card_view:onSetRotationMode(mode)
    else self.view:onSetRotationMode(mode) end
    self:onScreenResize();return true
end
return CardEditor
