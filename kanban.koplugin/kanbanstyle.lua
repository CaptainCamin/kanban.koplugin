-- Shared monochrome styling. Keep geometry scaled and contrast suitable for e-ink.
local BB = require('ffi/blitbuffer')
local Screen = require('device').screen
local Font = require('ui/font')
local Size = require('ui/size')
local Style = {
    border = Screen:scaleBySize(1),
    radius = Screen:scaleBySize(6),
    rule = BB.COLOR_BLACK,
    muted = BB.COLOR_BLACK,
    surface = BB.COLOR_WHITE,
}

-- Native Button ties border color to its background; keep white fills with
-- black outlines without changing native input, feedback or disabled behavior.
function Style.button(options)
    local button = require('ui/widget/button'):new(options)
    if options.bordersize and options.bordersize > 0 then button.frame.color = BB.COLOR_BLACK end
    return button
end

function Style.dialog(options)
    options.title_face = options.title_face or Font:getFace('cfont', 20)
    options.title_padding = options.title_padding or Size.padding.large
    if options.use_info_style == nil then options.use_info_style = false end
    for _, row in ipairs(options.buttons or {}) do
        for _, button in ipairs(row) do
            button.font_face = button.font_face or 'cfont'
            button.font_size = button.font_size or 20
        end
    end
    local dialog = require('ui/widget/buttondialog'):new(options)
    local function blackRules(widget)
        if widget.background and (widget.background == BB.COLOR_GRAY or widget.background == BB.COLOR_DARK_GRAY) then
            widget.background = BB.COLOR_BLACK
        end
        for _,child in ipairs(widget) do blackRules(child) end
    end
    blackRules(dialog)
    return dialog
end

return Style
