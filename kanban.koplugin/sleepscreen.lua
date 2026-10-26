local Blitbuffer = require("ffi/blitbuffer")
local BoardView = require("boardview")
local DataStorage = require("datastorage")
local Device = require("device")
local LuaSettings = require("luasettings")
local Screensaver = require("ui/screensaver")
local Storage = require("storage")
local logger = require("logger")
local util = require("util")

local SleepScreen = {}

local settings_dir = DataStorage:getSettingsDir()
local settings = LuaSettings:open(settings_dir .. "/kanban-sleepscreen.lua")
local image_path = settings_dir .. "/kanban-sleep.png"
local screensaver_keys = { "screensaver_type", "screensaver_document_cover" }
local screensaver_setup_hook

local function captureScreensaverSettings()
    local snapshot = {}
    for _, key in ipairs(screensaver_keys) do
        snapshot[key] = {
            present = G_reader_settings:has(key),
            value = G_reader_settings:readSetting(key),
        }
    end
    return snapshot
end

local function restoreScreensaverSettings(snapshot)
    if type(snapshot) ~= "table" then
        return false
    end
    for _, key in ipairs(screensaver_keys) do
        local saved = snapshot[key]
        if type(saved) == "table" and type(saved.present) == "boolean" then
            if saved.present then
                G_reader_settings:saveSetting(key, saved.value)
            else
                G_reader_settings:delSetting(key)
            end
        end
    end
    return true
end

local function renderBoard()
    local ok, err = util.makePath(settings_dir)
    if not ok then
        return nil, err
    end

    local screen = Device.screen
    local width, height = screen:getWidth(), screen:getHeight()
    local buffer = Blitbuffer.new(width, height, Blitbuffer.TYPE_BB8)
    local view
    local rendered, render_err = pcall(function()
        buffer:fill(Blitbuffer.COLOR_WHITE)
        view = BoardView:new{ state = Storage.load() }
        view:paintTo(buffer, 0, 0)
        local wrote, write_err = buffer:writeToFile(image_path, "png")
        if not wrote then
            error(write_err or "could not write board image")
        end
    end)
    if view then
        pcall(view.free, view, true)
    end
    buffer:free()
    if not rendered then
        return nil, render_err
    end

    local file = io.open(image_path, "rb")
    local file_size = file and file:seek("end") or 0
    if file then
        file:close()
    end
    if not file_size or file_size == 0 then
        return nil, "board image was not written"
    end
    return image_path
end

function SleepScreen.isEnabled()
    return settings:isTrue("enabled")
end

-- Persist the user's screensaver values before applying our temporary override.
function SleepScreen.setEnabled(enabled)
    if enabled then
        settings:saveSetting("screensaver_snapshot", captureScreensaverSettings())
        settings:saveSetting("enabled", true):flush()
        return
    end

    restoreScreensaverSettings(settings:readSetting("screensaver_snapshot"))
    G_reader_settings:flush()
    settings:delSetting("screensaver_snapshot")
    settings:delSetting("enabled"):flush()
end

-- A previous suspend may have flushed our temporary screensaver override to disk
-- before KOReader was interrupted. Restore the saved user values on startup/resume.
function SleepScreen.restoreUserSettings()
    if SleepScreen.isEnabled()
            and restoreScreensaverSettings(settings:readSetting("screensaver_snapshot")) then
        G_reader_settings:flush()
    end
end

function SleepScreen.prepareSuspend()
    if not SleepScreen.isEnabled() then
        return false
    end

    -- Capture again immediately before overriding, so changes made in KOReader's
    -- screensaver settings while this option is enabled are preserved as well.
    settings:saveSetting("screensaver_snapshot", captureScreensaverSettings()):flush()
    local path, err = renderBoard()
    if not path then
        logger.warn("kanban: could not render sleep screen", err)
        return false
    end

    G_reader_settings:saveSetting("screensaver_type", "document_cover")
    G_reader_settings:saveSetting("screensaver_document_cover", path)
    return true
end

function SleepScreen.installScreensaverHook()
    if screensaver_setup_hook then
        return
    end
    local original = Screensaver.setup
    if type(original) ~= "function" then
        logger.warn("kanban: screensaver setup is unavailable; sleep screen is disabled")
        return
    end
    screensaver_setup_hook = function(screensaver, event, ...)
        -- Screensaver setup runs before KOReader shows the suspend image; the
        -- Suspend event itself is broadcast later, after that image is queued.
        if event == nil and SleepScreen.isEnabled() then
            local ok, err = pcall(SleepScreen.prepareSuspend)
            if not ok then
                logger.warn("kanban: failed to prepare sleep screen", err)
            end
        end
        return original(screensaver, event, ...)
    end
    Screensaver.setup = screensaver_setup_hook
end

return SleepScreen
