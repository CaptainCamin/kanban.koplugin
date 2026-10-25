local LuaSettings = require("luasettings")
local DataStorage = require("datastorage")
local Model = require("model")

local Storage = {}

local function path()
    return DataStorage:getSettingsDir() .. "/kanban.lua"
end

function Storage.migrate(state)
    if state.version == 1 then
        return state
    end
    return state
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
