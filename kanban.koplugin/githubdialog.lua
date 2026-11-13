local TextViewer = require('ui/widget/textviewer')
local UI = require('ui/uimanager')
local KanbanDialog = require('widgets/kanbandialog')
local Model = require('model')
local GitHub = require('github')
local Store = require('githubstore')
local _ = require('gettext')
local T = require('ffi/util').template
local Dialog = {}
local publishing = false

local function message(text) UI:show(KanbanDialog:new{text=text}) end
local function openStore()
    local ok, data, save = pcall(Store.open)
    if not ok then
        message(_("GitHub upload history could not be read. Restore kanban-github.lua from a current backup before publishing."))
        return nil
    end
    return data, save
end

local function prompt(title, value, callback, password)
    local dialog
    dialog = KanbanDialog:new{
        title=title, input=value or '', text_type=password and 'password' or nil,
        buttons={{
            {text=_("Cancel"), callback=function() UI:close(dialog) end},
            {text=_("Save"), callback=function()
                local input = dialog:getInputText():match('^%s*(.-)%s*$')
                local ok, result = pcall(callback, input)
                if not ok then message(_("Could not save GitHub settings. Check free space and try again.")); return end
                if result ~= false then UI:close(dialog) end
            end},
        }},
    }
    UI:show(dialog)
    dialog:onShowKeyboard()
end

-- Bound the number of rows for small screens, including boards with many labels.
local function list(title, items, footer, page)
    page = page or 1
    local dialog
    local buttons = {}
    for index=(page-1)*5+1, math.min(page*5, #items) do
        local item = items[index]
        buttons[#buttons+1] = {{text=item.text, callback=function()
            if not item.keep_open then UI:close(dialog) end
            item.callback()
        end}}
    end
    if #items > 5 then
        buttons[#buttons+1] = {
            {text=_("Previous"), enabled=page>1, callback=function()
                UI:close(dialog); list(title, items, footer, page-1)
            end},
            {text=_("Next"), enabled=page*5<#items, callback=function()
                UI:close(dialog); list(title, items, footer, page+1)
            end},
        }
    end
    for _, row in ipairs(footer or {}) do buttons[#buttons+1]=row end
    buttons[#buttons+1] = {{text=_("Close"), callback=function() UI:close(dialog) end}}
    dialog = KanbanDialog:new{title=title, buttons=buttons}
    UI:show(dialog)
end

local function setConfig(view, key, value)
    local board = view:getBoard()
    return view:commit(function()
        board.github = board.github or {}
        board.github[key] = value
        return true
    end)
end

local function chooseLabels(view)
    local board = view:getBoard()
    local config = board.github or {}
    local items = {}
    for label_index, label in ipairs(board.labels or {}) do
        local id, name = label.id, label.name
        local selected = (config.upload_labels or {})[id]
        items[#items+1] = {text=(selected and "☑ " or "☐ ") .. name, callback=function()
            view:commit(function()
                board.github = board.github or {}
                board.github.upload_labels = board.github.upload_labels or {}
                board.github.label_map = board.github.label_map or {}
                board.github.upload_labels[id] = not selected or nil
                if not selected and board.github.label_map[id] == nil then
                    board.github.label_map[id] = name
                end
                return true
            end)
            chooseLabels(view)
        end}
    end
    if #items == 0 then message(_("Create board labels first, then choose which ones upload to GitHub.")); return end
    list(_("Upload cards with ANY checked label"), items)
end

local function mappings(view)
    local board = view:getBoard()
    local config = board.github or {}
    local items = {}
    for label_index, label in ipairs(board.labels or {}) do
        local id, name = label.id, label.name
        local mapped = (config.label_map or {})[id]
        items[#items+1] = {text=name .. ' → ' .. (mapped or _("No GitHub label")), callback=function()
            prompt(T(_("GitHub label for “%1” (empty = none)"), name), mapped, function(value)
                if #value > 50 or value:find('[\r\n]') then
                    message(_("Enter one GitHub label name, up to 50 characters.")); return false
                end
                view:commit(function()
                    board.github = board.github or {}
                    board.github.label_map = board.github.label_map or {}
                    board.github.label_map[id] = value ~= '' and value or nil
                    return true
                end)
                mappings(view)
            end)
        end}
    end
    if #items == 0 then message(_("Create board labels first.")); return end
    list(_("Map to existing GitHub labels"), items)
end

local function runBatch(view, candidates, data, save)
    if not data.token or data.token == '' then message(_("Set a GitHub token before publishing.")); return end
    local source_board = view:getBoard()
    local Network = require('ui/network/manager')
    Network:runWhenOnline(function()
        if view:getBoard() ~= source_board then message(_("The board changed. Preview the batch again.")); return end
        -- Do not publish with a board identity that failed to reach disk.
        local stored = require('storage').load()
        local identity_saved = false
        for _, board in ipairs(stored.boards) do
            if board.id == source_board.id and board.github_id == source_board.github_id then identity_saved = true end
        end
        if not identity_saved then message(_("Save the board's GitHub settings before publishing.")); return end
        if publishing then message(_("A GitHub batch is already running.")); return end
        local fresh, persist = openStore()
        if not fresh then return end
        data, save = fresh, persist
        if not data.token then message(_("Set a GitHub token before publishing.")); return end
        publishing = true
        local request = require('githubapi').client(data.token)
        local progress, cancelled, finished = nil, false, false
        local count, index = 0, 1
        local board_id = view:getBoard().id
        local function finish(err)
            finished, publishing = true, false
            if progress then UI:close(progress); progress=nil end
            view:refresh()
            message(T(_("GitHub: %1 of %2 cards published or recovered."), count, #candidates)
                .. (err and '\n\n' .. err or ''))
        end
        local step
        step = function()
            if finished then return end
            if cancelled or not view:getBoard() or view:getBoard().id ~= board_id then finish(_("Batch stopped. Remaining cards are still ready to upload.")); return end
            local candidate = candidates[index]
            if not candidate then finish(); return end
            if progress then UI:close(progress) end
            progress = KanbanDialog:new{
                title=T(_("Publishing card %1 of %2"), index, #candidates),
                buttons={{{text=_("Stop after current card"), callback=function() cancelled=true end}}},
            }
            UI:show(progress)
            -- Repaint progress before making the blocking network request.
            UI:nextTick(function()
                local ok, issue, err = pcall(GitHub.publish, candidate, data.uploads, save, request)
                if not ok then finish(_("Could not save upload progress. Retry to check the result before uploading again.")); return end
                if not issue then finish(err); return end
                count, index = count+1, index+1
                UI:nextTick(step)
            end)
        end
        step()
    end)
end

function Dialog.preview(view)
    if publishing then message(_("A GitHub batch is already running.")); return end
    local data, save = openStore()
    if not data then return end
    local candidates, err = GitHub.candidates(view:getBoard(), data.uploads)
    if not candidates then message(err); return end
    if #candidates == 0 then message(_("No ready cards to upload. Already published and archived cards are excluded.")); return end
    local items = {}
    for candidate_index, candidate in ipairs(candidates) do
        local card = candidate
        items[#items+1] = {keep_open=true, text=(card.recovering and _("Check previous upload: ") or '') .. card.title, callback=function()
            UI:close(dialog)
            UI:show(TextViewer:new{
                title=card.title,
                text=T(_("Repository: %1\nGitHub labels: %2\n\n%3"), card.repository,
                    table.concat(card.labels, ', '), card.body:gsub('\n?<!%-%- koreader%-kanban:.-%-%->', '')),
            })
        end}
    end
    list(T(_("Ready to publish: %1 cards → %2"), #candidates, candidates[1].repository), items, {{
        {text=_("Publish batch"), callback=function()
            UI:show(KanbanDialog:new{
                text=T(_("Create GitHub issues for these %1 cards in %2? Published issues cannot be undone from the board."), #candidates, candidates[1].repository),
                ok_text=_("Publish"), ok_callback=function() runBatch(view, candidates, data, save) end,
            })
        end},
    }})
end

function Dialog.show(view)
    if publishing then message(_("A GitHub batch is already running.")); return end
    local board = view:getBoard()
    local config = board.github or {}
    local upload_count = 0
    for _, label in ipairs(board.labels or {}) do
        if (config.upload_labels or {})[label.id] then upload_count = upload_count + 1 end
    end
    local data = openStore()
    if not data then return end
    local dialog
    local function action(fn) return function() UI:close(dialog); fn() end end
    dialog = KanbanDialog:new{
        title=_("GitHub issues"),
        buttons={
            {{text=T(_("Repository: %1"), config.repository or _("Not connected")), callback=action(function()
                prompt(_("GitHub repository (owner/repository)"), config.repository, function(value)
                    local repo = GitHub.repository(value)
                    if not repo then message(_("Enter a GitHub repository as owner/repository.")); return false end
                    if not board.github_id then
                        local identity, err = GitHub.newIdentity()
                        if not identity then message(err); return false end
                        board.github_id = identity
                    end
                    setConfig(view, 'repository', repo)
                    Dialog.show(view)
                end)
            end)}},
            {{text=T(_("Labels to upload: %1"), upload_count), callback=action(function() chooseLabels(view) end)}},
            {{text=_("GitHub label mappings…"), callback=action(function() mappings(view) end)}},
            {{text=data.token and _("Replace GitHub token…") or _("Set GitHub token…"), callback=action(function()
                prompt(_("Token with repository Issues read/write access"), '', function(value)
                    if value == '' or value:find('%s') then message(_("Enter a token without spaces.")); return false end
                    local credentials, save = openStore()
                    if not credentials then return false end
                    credentials.token = value
                    save()
                    Dialog.show(view)
                end, true)
            end)}},
            {{text=_("Forget GitHub token"), enabled=data.token ~= nil, callback=action(function()
                local credentials, save = openStore()
                if not credentials then return end
                credentials.token = nil
                local ok = pcall(save)
                if not ok then message(_("Could not remove the saved token.")); return end
                Dialog.show(view)
            end)}},
            {{text=_("Preview batch…"), callback=action(function() Dialog.preview(view) end)}},
            {{text=_("Close"), callback=action(function() end)}},
        },
    }
    UI:show(dialog)
end

function Dialog.issue(board, card_id)
    if not board.github_id then return nil end
    local repo = GitHub.repository((board.github or {}).repository)
    if not repo then return nil end
    local ok, data = pcall(Store.open)
    if not ok then return nil end
    local record = data.uploads[GitHub.key(board, card_id, repo)]
    return record and record.issue
end

return Dialog
