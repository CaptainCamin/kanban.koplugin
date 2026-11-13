-- Shared grayscale design tokens. Keep geometry scaled and contrast suitable for e-ink.
local BB = require('ffi/blitbuffer')
local Screen = require('device').screen
local Font = require('ui/font')
local Size = require('ui/size')

local Style = {
    border = Screen:scaleBySize(1),
    radius = Screen:scaleBySize(6),
    radius_large = Screen:scaleBySize(10),
    rule = BB.COLOR_GRAY_9,
    muted = BB.COLOR_DARK_GRAY,
    surface = BB.COLOR_GRAY_E,
    paper = BB.COLOR_WHITE,

    palette = {
        paper = BB.COLOR_WHITE,
        surface = BB.COLOR_GRAY_E,
        raised = BB.COLOR_LIGHT_GRAY,
        chip = BB.COLOR_GRAY_D,
        rule = BB.COLOR_GRAY_9,
        muted = BB.COLOR_DARK_GRAY,
        ink = BB.COLOR_BLACK,
        scrim = BB.COLOR_GRAY_2,
        now = BB.COLOR_GRAY_D,
        disabled = BB.COLOR_GRAY,
    },

    font = {
        title = Font:getFace('cfont', 20),
        display = Font:getFace('cfont', 22),
        heading = Font:getFace('cfont', 18),
        body = Font:getFace('cfont', 16),
        small = Font:getFace('smallinfofont', 16),
        caption = Font:getFace('xx_smallinfofont'),
        bar = Font:getFace('smallinfofontbold'),
    },

    size = {
        title = 20,
        heading = 18,
        body = 16,
        small = 14,
        caption = 12,
    },

    space = {
        xs = Size.padding.tiny,
        sm = Size.padding.small,
        md = Size.padding.default,
        lg = Size.padding.large,
        xl = Screen:scaleBySize(16),
    },

    icon = {
        size = Screen:scaleBySize(22),
        touch = Screen:scaleBySize(36),
    },

    button = {
        height = Screen:scaleBySize(36),
        radius = Screen:scaleBySize(7),
    },
}

-- Compatibility aliases for older call sites while the migration lands.
Style.rule = Style.palette.rule
Style.muted = Style.palette.muted
Style.surface = Style.palette.surface

return Style
