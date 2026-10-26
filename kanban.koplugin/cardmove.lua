local Blitbuffer = require("ffi/blitbuffer")
local DataStorage = require("datastorage")
local Device = require("device")
local Geom = require("ui/geometry")
local LuaSettings = require("luasettings")
local Model = require("model")
local UIManager = require("ui/uimanager")
local logger = require("logger")

local CardMove = {}
local settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/kanban-options.lua")

function CardMove.isEnabled()
    return settings:readSetting("drag_to_move") ~= false
end

function CardMove.setEnabled(enabled)
    settings:saveSetting("drag_to_move", enabled):flush()
end

local function hit(targets, pos)
    for _, target in ipairs(targets or {}) do
        local rect = target.frame.dimen
        if rect and rect.x and rect:contains(pos) then
            return target, rect
        end
    end
end

-- Derive gaps from painted frames, not a second copy of the variable-height
-- layout. Indexes describe insertion BEFORE removal of the picked card.
function CardMove.gaps(view)
    local gaps = {}
    local thickness = Device.screen:scaleBySize(6)
    for _, header in ipairs(view.header_targets or {}) do
        local rect = header.frame.dimen
        if rect and rect.x then
            local column = view:findColumn(header.id)
            local cards = {}
            for _, target in ipairs(view.card_targets) do
                local owner, index = view:locateCard(target.id)
                if owner == column then
                    table.insert(cards, { rect = target.frame.dimen, index = index })
                end
            end
            local function add(index, y)
                table.insert(gaps, {
                    id = column.id, index = index,
                    rect = Geom:new{ x = rect.x, y = math.floor(y - thickness / 2),
                        w = rect.w, h = thickness },
                })
            end
            if #cards == 0 then
                add(1, rect.y + rect.h + Device.screen:scaleBySize(12))
            else
                for i, card in ipairs(cards) do
                    local previous = cards[i - 1]
                    local y = previous and (previous.rect.y + previous.rect.h + card.rect.y) / 2
                        or card.rect.y - Device.screen:scaleBySize(4)
                    add(card.index, y)
                end
                local last = cards[#cards]
                add(last.index + 1, last.rect.y + last.rect.h + Device.screen:scaleBySize(4))
            end
        end
    end
    return gaps
end

function CardMove.target(view, pos, dragging)
    local tab, rect = hit(view.tab_targets, pos)
    if tab then
        return { id = tab.id, tab = true, rect = rect:copy() }
    end
    local header = hit(view.header_targets, pos)
    if header then
        return { id = header.id, header = true }
    end
    local nearest, distance
    for _, gap in ipairs(CardMove.gaps(view)) do
        local r = gap.rect
        if pos.x >= r.x and pos.x < r.x + r.w then
            local d = math.abs(pos.y - (r.y + r.h / 2))
            if not distance or d < distance then
                nearest, distance = gap, d
            end
        end
    end
    if nearest then
        if dragging then
            for _, column in ipairs(view.column_rects) do
                if column.id == nearest.id and column.rect:contains(pos) then
                    return nearest
                end
            end
        elseif distance <= Device.screen:scaleBySize(12) then
            return nearest
        end
    end
end

function CardMove.drop(view, target)
    local card_id = view.moving_card
    local source, old_index = view:locateCard(card_id)
    local destination = target and view:findColumn(target.id)
    if target and target.header and source == destination then
        destination = nil -- retain quick-move's own-header cancellation
    end
    local index = target and target.index
    if destination and not index then
        index = #destination.cards + 1
    end
    if source == destination and index and index > old_index then
        index = index - 1
    end
    view.moving_card, view.drag_origin, view.dragging, view.drop_preview = nil, nil, nil, nil
    if destination and not (source == destination and old_index == index) then
        view:commit(function()
            return Model.moveCard(view:getBoard(), card_id, destination.id, index)
        end, function() view:revealCard(destination.id, index) end)
    else
        view:layout()
        UIManager:setDirty(view, "ui")
    end
    return true
end

function CardMove.hold(view, pos)
    local card, rect = hit(view.card_targets, pos)
    if not card then
        return false
    end
    view.drag_origin = rect:copy()
    view.dragging, view.drop_preview = nil, nil
    view:setMovingCard(card.id)
    return true
end

function CardMove.pan(view, pos)
    if not view.moving_card then
        return false
    end
    if not CardMove.isEnabled() then
        return true
    end
    -- The detector emits hold_pan only at/above its DPI-scaled PAN_THRESHOLD.
    view.dragging = true
    local target = not view.drag_origin:contains(pos) and CardMove.target(view, pos, true) or nil
    local old = view.drop_preview
    if old and target and old.id == target.id and old.index == target.index and old.tab == target.tab then
        return true
    end
    if not old and not target then
        return true
    end
    view.drop_preview = target
    for _, preview in pairs({ old = old, new = target }) do
        if preview.rect then
            logger.dbg("kanban: drag refresh a2", preview.rect)
            UIManager:setDirty(view, "a2", preview.rect)
        end
    end
    return true
end

function CardMove.release(view, pos)
    if not view.moving_card then
        return false
    end
    if not view.dragging then
        return true -- hold-and-lift stays picked up for tap-to-drop
    end
    local target = not view.drag_origin:contains(pos) and CardMove.target(view, pos, true) or nil
    return CardMove.drop(view, target)
end

function CardMove.paint(view, bb)
    local target = view.drop_preview
    if target and target.rect then
        local r = target.rect
        if target.tab then
            bb:invertRect(r.x, r.y, r.w, r.h)
        else
            bb:paintRect(r.x, r.y, r.w, r.h, Blitbuffer.COLOR_BLACK)
        end
    end
end

return CardMove
