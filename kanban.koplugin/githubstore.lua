-- Credentials and external effects live outside board snapshots and Markdown.
local LuaSettings = require('luasettings')
local DataStorage = require('datastorage')
local Store = {}

function Store.open()
    local path = DataStorage:getSettingsDir() .. '/kanban-github.lua'
    local file = io.open(path, 'rb')
    if file then
        file:close()
        -- An old backup may omit accepted uploads, so never silently fall back.
        local chunk = loadfile(path)
        local ok, stored = pcall(chunk or error)
        if not ok or type(stored) ~= 'table' or type(stored.github) ~= 'table' or type(stored.github.uploads) ~= 'table' then
            error('GitHub upload history is unreadable; restore its current file before uploading.')
        end
    end
    if not file then
        local backup = io.open(path .. '.old', 'rb')
        if backup then
            backup:close()
            error('Only an old GitHub journal backup exists; restore the current history before uploading.')
        end
    end
    local settings = LuaSettings:open(path)
    local data = settings:readSetting('github') or {uploads={}}
    data.uploads = data.uploads or {}
    return data, function()
        settings:saveSetting('github', data)
        settings:flush()
        local chunk = loadfile(path)
        local ok, stored = pcall(chunk or error)
        if not ok or type(stored) ~= 'table'
            or not require('util').tableEquals(stored.github, data) then
            error('Could not persist GitHub upload history')
        end
        -- Do not leave a previous credential behind after replacement/removal.
        os.remove(path .. '.old')
    end
end

return Store
