-- GitHub issue publishing policy. Network and durable journal are injected.
local Model = require('model')
local GitHub = {}

function GitHub.repository(value)
    if type(value) ~= 'string' then return nil end
    value = value:match('^%s*(.-)%s*$'):gsub('^https://github%.com/', ''):gsub('/$', '')
    local owner, repo = value:match('^([%w%-]+)/([%w_.%-]+)$')
    if not owner or not repo or repo == '.' or repo == '..' then return nil end
    return (owner .. '/' .. repo):lower()
end

function GitHub.newIdentity()
    local file = io.open('/dev/urandom', 'rb')
    local bytes = file and file:read(16)
    if file then file:close() end
    if not bytes or #bytes ~= 16 then return nil, 'Cannot generate an upload identity.' end
    return (bytes:gsub('.', function(c) return string.format('%02x', c:byte()) end))
end

function GitHub.key(board, card_id, repository)
    return repository .. ':' .. board.github_id .. ':' .. card_id
end

function GitHub.issueBody(card, marker)
    local lines = {}
    if card.notes and card.notes:match('%S') then lines[#lines + 1] = card.notes end
    if #(card.checklist or {}) > 0 then
        lines[#lines + 1] = ''
        for _, item in ipairs(card.checklist) do
            lines[#lines + 1] = '- [' .. (item.done and 'x' or ' ') .. '] ' .. item.text
        end
    end
    lines[#lines + 1] = ''
    lines[#lines + 1] = marker
    return table.concat(lines, '\n')
end

function GitHub.candidates(board, journal)
    local config = board.github or {}
    local repo = GitHub.repository(config.repository)
    if not repo or not board.github_id then return nil, 'Connect this board to a repository first.' end
    local enabled = {}
    for _, label in ipairs(board.labels or {}) do
        if (config.upload_labels or {})[label.id] then enabled[label.id] = true end
    end
    if not next(enabled) then return nil, 'Choose labels to upload first.' end
    local cards = {}
    for _, column in ipairs(board.columns) do
        for _, id in ipairs(column.cards) do
            local card = board.cards[id]
            local record = journal[GitHub.key(board, id, repo)]
            local eligible = false
            for _, label_id in ipairs(card.labels or {}) do
                if enabled[label_id] then eligible = true; break end
            end
            if not card.archived and eligible and not (record and record.issue) then
                local labels, seen = {}, {}
                for _, label_id in ipairs(card.labels or {}) do
                    local mapped = enabled[label_id] and (config.label_map or {})[label_id]
                    if type(mapped) == 'string' and mapped:match('%S') and not seen[mapped:lower()] then
                        labels[#labels + 1], seen[mapped:lower()] = mapped, true
                    end
                end
                local marker = '<!-- koreader-kanban:' .. board.github_id .. ':' .. id .. ' -->'
                cards[#cards + 1] = {
                    card_id = id, repository = repo, key = GitHub.key(board, id, repo),
                    title = record and record.title or card.title,
                    body = record and record.body or GitHub.issueBody(card, marker),
                    labels = record and record.labels or labels, marker = marker,
                    recovering = record ~= nil,
                }
            end
        end
    end
    return cards
end

local function validIssue(issue, repository)
    return type(issue) == 'table' and type(issue.number) == 'number' and issue.number > 0
        and issue.number == math.floor(issue.number)
        and type(issue.html_url) == 'string'
        and issue.html_url:lower() == 'https://github.com/' .. repository .. '/issues/' .. issue.number
end

-- A POST interrupted after GitHub accepts it must never be blindly repeated.
local function recover(candidate, record, request)
    for page = 1, 5 do
        local issues, err = request('GET', '/repos/' .. candidate.repository
            .. '/issues?state=all&sort=created&direction=desc&per_page=100&page=' .. page
            .. '&since=' .. os.date('!%Y-%m-%dT%H:%M:%SZ', record.started - 60))
        if not issues then return nil, err end
        if type(issues) ~= 'table' then return nil, 'Invalid GitHub issue list.' end
        for _, issue in ipairs(issues) do
            if not issue.pull_request and type(issue.body) == 'string'
                and issue.body:find(candidate.marker, 1, true) and validIssue(issue, candidate.repository) then
                return {number=issue.number, url=issue.html_url}
            end
        end
        if #issues < 100 then
            return nil, 'The previous upload is uncertain and its issue was not found. Retry later; no duplicate was created.'
        end
    end
    return nil, 'Too many recent issues to verify the previous upload. No new issue was created.'
end

function GitHub.publish(candidate, journal, save, request, clock)
    local record = journal[candidate.key]
    if record and record.issue then return record.issue end
    if record then
        local issue, err = recover(candidate, record, request)
        if not issue then return nil, err end
        record.issue = issue
        save()
        return issue
    end
    record = {title=candidate.title, body=candidate.body, labels=candidate.labels, started=(clock or os.time)()}
    journal[candidate.key] = record
    save() -- Write the attempt before sending anything to GitHub.
    local response, err, status = request('POST', '/repos/' .. candidate.repository .. '/issues', {
        title=record.title, body=record.body, labels=#record.labels > 0 and record.labels or nil,
    })
    if not response then
        -- Definitive client rejections did not create an issue; edits can be retried.
        if status and status >= 400 and status < 500 and status ~= 408 then
            journal[candidate.key] = nil
            save()
        end
        return nil, err
    end
    if not validIssue(response, candidate.repository) then
        return nil, 'GitHub returned an unexpected response. Retry to check whether the issue was created.'
    end
    record.issue = {number=response.number, url=response.html_url}
    save() -- Every success is durable before the next card starts.
    return record.issue
end

return GitHub
