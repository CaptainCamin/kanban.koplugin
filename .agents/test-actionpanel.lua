-- Run after test-ux.lua initializes an isolated KOReader runtime.
local Panel = require('actionpanel')
local UI = require('ui/uimanager')
local Screen = require('device').screen
local BB = require('ffi/blitbuffer')
local Event = require('ui/event')
local Geom = require('ui/geometry')
local activated = 0
local function render(panel)
    local bb = BB.new(Screen:getWidth(),Screen:getHeight(),BB.TYPE_BB8)
    bb:fill(BB.COLOR_WHITE)
    panel:paintTo(bb,0,0)
    bb:free()
    local r = panel.panel.dimen
    assert(r.x >= 0 and r.y >= 0 and r.x+r.w <= Screen:getWidth()
        and r.y+r.h <= Screen:getHeight(), 'panel must fit screen')
end
local function tap(panel, control)
    local r = control.dimen
    return panel:handleEvent(Event:new('Gesture',{
        ges='tap',pos=Geom:new{x=r.x+r.w/2,y=r.y+r.h/2},
    }))
end
local function build(options)
    local panel = Panel:new(options)
    UI:show(panel)
    render(panel)
    assert(not panel.buttontable,'custom panel must not use ButtonTable')
    return panel
end
local panel = build{
    title='A card with a clear next step',context='Project · In progress',
    row_styles={'hero','tile'},
    buttons={
        {{text='Continue',description='A meaningful next action',callback=function() activated=activated+1 end}},
        {{text='Edit',callback=function() activated=activated+10 end},
         {text='Unavailable',enabled=false,callback=function() activated=activated+100 end}},
    },
}
assert(tap(panel,panel.action_widgets[1]))
assert(activated == 1,'tap should activate only the intended action once')
tap(panel,panel.action_widgets[3])
assert(activated == 1,'disabled action must not activate')
assert(panel:handleEvent(Event:new('Gesture',{ges='tap',pos=Geom:new{x=0,y=0}})))
assert((UI._window_stack[#UI._window_stack] or {}).widget ~= panel,'outside tap must dismiss')
local rows = {}
for index=1,18 do
    rows[index]={{text='Action '..index,description='Longer supporting text that must wrap safely in a narrow panel.',callback=function() end}}
end
panel = build{title=string.rep('Long translated title ',12),context='Context',buttons=rows}
assert(panel.cropping_widget,'long content must scroll')
panel:moveFocusTo(1,#panel.layout-1)
panel:onFocusMove({0,1})
render(panel)
assert(panel.cropping_widget._scroll_offset_y > 0,'keyboard focus must reveal lower actions')
panel:onClose()
panel = build{title='Resize',buttons={{{text='Close',callback=function() end}}}}
assert(panel:onScreenResize() == false)
assert((UI._window_stack[#UI._window_stack] or {}).widget ~= panel,'resize dismisses stale geometry')
print('PASS: custom panel real taps, disabled actions, outside dismissal, long content, keyboard scrolling and resize')
