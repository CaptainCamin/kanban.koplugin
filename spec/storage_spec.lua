local saved = {}
local opened = {}
local settings_dir = "/settings"

-- Like the real LuaSettings, open never throws: unreadable files just yield no data.
package.loaded.luasettings = nil
package.loaded.datastorage = nil
package.loaded.storage = nil
package.preload.luasettings = function()
    return {
        open = function(_, path)
            opened[#opened + 1] = path
            return {
                readSetting = function(_, key) return saved[key] end,
                saveSetting = function(_, key, value) saved[key] = value end,
                flush = function() saved.flushed = true end,
            }
        end,
    }
end
package.preload.datastorage = function()
    return { getSettingsDir = function() return settings_dir end }
end

local Model = require("model")
local Storage = require("storage")

local function read(path)
    local file = io.open(path, "r")
    if not file then return nil end
    local content = file:read("*a")
    file:close()
    return content
end

describe("kanban storage", function()
    before_each(function()
        saved, opened = {}, {}
        settings_dir = "/settings"
    end)

    it("creates and migrates a schema v1 default state on first load", function()
        local state = Storage.load()
        assert.equals(1, state.version)
        assert.equals("My board", state.boards[1].name)
    end)

    it("round-trips saved state and flushes it", function()
        local state = Model.newState()
        state.boards[1].name = "Saved board"
        Storage.save(state)
        assert.is_true(saved.flushed)
        local loaded = Storage.load()
        assert.equals("Saved board", loaded.boards[1].name)
        assert.equals("/settings/kanban.lua", opened[1])
    end)

    describe("with a settings file on disk", function()
        local file_path

        before_each(function()
            settings_dir = os.tmpname()
            os.remove(settings_dir)
            os.execute("mkdir " .. settings_dir)
            file_path = settings_dir .. "/kanban.lua"
        end)

        after_each(function()
            os.remove(file_path)
            os.remove(file_path .. ".bak")
            os.remove(settings_dir)
        end)

        local function write(content)
            local file = assert(io.open(file_path, "w"))
            file:write(content)
            file:close()
        end

        it("backs up a corrupt file before it can be overwritten", function()
            write("return { state = ")
            local state = Storage.load()
            assert.equals(1, state.version)
            assert.is_nil(read(file_path))
            assert.equals("return { state = ", read(file_path .. ".bak"))
        end)

        it("leaves a valid file in place", function()
            write("return { state = { version = 1, boards = {} } }")
            Storage.load()
            assert.equals("return { state = { version = 1, boards = {} } }", read(file_path))
            assert.is_nil(read(file_path .. ".bak"))
        end)
    end)
end)
