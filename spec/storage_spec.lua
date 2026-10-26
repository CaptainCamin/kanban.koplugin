local saved = {}
local opened = {}
local settings_dir = "/settings"

local function clone(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, child in pairs(value) do
        copy[key] = clone(child)
    end
    return copy
end

-- Like the real LuaSettings, open never throws: unreadable files just yield no data.
package.loaded.luasettings = nil
package.loaded.datastorage = nil
package.loaded.storage = nil
package.preload.luasettings = function()
    return {
        open = function(_, path)
            opened[#opened + 1] = path
            return {
                readSetting = function(_, key) return clone(saved[key]) end,
                saveSetting = function(_, key, value) saved[key] = clone(value) end,
                flush = function() saved.flushed = true end,
            }
        end,
    }
end
package.preload.logger = function()
    return { warn = function() end }
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

local function realistic_v1_state()
    return {
        version = 1,
        current_board = "b2",
        boards = {
            {
                id = "b1",
                name = "Reading list",
                columns = {
                    { id = "c1", name = "To Read", cards = { "k1" } },
                    { id = "c2", name = "Finished", cards = {} },
                },
                cards = {
                    k1 = {
                        id = "k1",
                        title = "The Dispossessed",
                        notes = "Borrowed from the library",
                        created = 1730000000,
                        updated = 1730000100,
                        archived = false,
                        custom = { source = "library" },
                    },
                },
                archived = {},
                next_id = 2,
                description = "Personal queue",
            },
            {
                id = "b2",
                name = "Work",
                columns = {
                    { id = "c3", name = "Done", cards = {} },
                },
                cards = {
                    k7 = {
                        id = "k7",
                        title = "Ship release",
                        notes = "",
                        created = 1731000000,
                        archived = true,
                    },
                },
                archived = { "k7" },
                next_id = 8,
            },
        },
        preference = "keep-me",
    }
end

local function expected_v2_state()
    local expected = realistic_v1_state()
    expected.version = 2
    expected.boards[1].columns[1].collapsed = false
    expected.boards[1].columns[2].collapsed = false
    expected.boards[1].cards.k1.checklist = {}
    expected.boards[1].cards.k1.moved = 1730000100
    expected.boards[2].columns[1].collapsed = false
    expected.boards[2].cards.k7.checklist = {}
    expected.boards[2].cards.k7.moved = 1731000000
    return expected
end

describe("kanban storage", function()
    before_each(function()
        saved, opened = {}, {}
        settings_dir = "/settings"
    end)

    it("creates a schema v2 default state on first load", function()
        local state = Storage.load()
        assert.equals(2, state.version)
        assert.equals("My board", state.boards[1].name)
    end)

    it("migrates a realistic v1 state in place without losing fields", function()
        local state = realistic_v1_state()
        local migrated = Storage.migrate(state)
        assert.is_true(migrated == state)
        assert.same(expected_v2_state(), state)
        assert.same(expected_v2_state(), Storage.migrate(state))

        saved.state = realistic_v1_state()
        assert.same(expected_v2_state(), Storage.load())
        assert.same(expected_v2_state(), Storage.load())
    end)

    it("round-trips a schema v2 state and flushes it", function()
        local state = Model.newState()
        state.boards[1].name = "Saved board"
        local board = state.boards[1]
        assert.is_true(Model.addCard(board, board.columns[1].id, { title = "Saved card" }, nil, 100))
        assert.is_true(Model.addChecklistItem(board, "k4", "Check persistence", nil, 110))
        assert.is_true(Model.setColumnCollapsed(board, board.columns[2].id, true))
        local expected = clone(state)
        Storage.save(state)
        assert.is_true(saved.flushed)
        board.cards.k4.title = "Changed after save"
        local loaded = Storage.load()
        assert.same(expected, loaded)
        assert.equals(2, loaded.version)
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
            os.remove(file_path .. ".v1.bak")
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
            assert.equals(2, state.version)
            assert.is_nil(read(file_path))
            assert.equals("return { state = ", read(file_path .. ".bak"))
        end)

        it("backs up a v1 file when it is loaded, before any v2 save", function()
            local old_contents = "return { state = { version = 1, boards = {} } }"
            write(old_contents)

            Storage.load()
            write("return { state = { version = 1, boards = {}, changed = true } }")
            Storage.load()

            assert.equals(old_contents, read(file_path .. ".v1.bak"))
        end)

        it("leaves a valid file in place", function()
            write("return { state = { version = 1, boards = {} } }")
            Storage.load()
            assert.equals("return { state = { version = 1, boards = {} } }", read(file_path))
            assert.is_nil(read(file_path .. ".bak"))
        end)
    end)
end)
