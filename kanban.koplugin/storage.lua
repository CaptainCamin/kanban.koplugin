local LuaSettings = require("luasettings")
local DataStorage = require("datastorage")
local Model = require("model")
local logger = require("logger")

local Storage = {}

local function path()
    return DataStorage:getSettingsDir() .. "/kanban.lua"
end

function Storage.migrate(state)
    if state.version == 1 then
        for _, board in ipairs(state.boards) do
            for _, column in ipairs(board.columns) do
                if column.collapsed == nil then
                    column.collapsed = false
                end
            end
            for _, card in pairs(board.cards) do
                if card.checklist == nil then
                    card.checklist = {}
                end
                if card.moved == nil then
                    card.moved = card.updated or card.created or 0
                end
            end
        end
        state.version = 2
    end
    -- Additive fields keep existing version-2 files and undo snapshots compatible.
    for _, board in ipairs(state.boards) do
        board.labels = board.labels or {}
        for _, card in pairs(board.cards) do card.labels = card.labels or {} end
    end
    if state.undo and state.undo.board then
        local board = state.undo.board
        board.labels = board.labels or {}
        for _, card in pairs(board.cards) do card.labels = card.labels or {} end
    end
    return state
end

-- Keep a copy of a schema v1 file before the first v2 save overwrites it.
local function backupV1(settings_path)
    local backup_path = settings_path .. ".v1.bak"
    local existing = io.open(backup_path, "rb")
    if existing then
        existing:close()
        return
    end
    local source = io.open(settings_path, "rb")
    local contents = source and source:read("*a")
    if source then source:close() end
    local backup = contents and io.open(backup_path, "wb")
    if not (backup and backup:write(contents)) then
        logger.warn("kanban: could not back up schema v1 file to", backup_path)
    end
    if backup then backup:close() end
end

function Storage.load()
    local settings_path = path()
    -- LuaSettings:open swallows read errors and returns empty data, so check the file
    -- ourselves and keep a corrupt one as .bak before the next save overwrites it.
    local file = io.open(settings_path, "r")
    if file then
        file:close()
        local chunk = loadfile(settings_path)
        local ok, data = pcall(chunk or error)
        if not ok or type(data) ~= "table" then
            os.rename(settings_path, settings_path .. ".bak")
        elseif type(data.state) == "table" and data.state.version == 1 then
            backupV1(settings_path)
        end
    end
    local settings = LuaSettings:open(settings_path)
    local state = settings:readSetting("state")
    if not state then
        state = Model.newState()
    end
    return Storage.migrate(state)
end

function Storage.save(state)
    local settings = LuaSettings:open(path())
    settings:saveSetting("state", state)
    settings:flush()
end

return Storage
