local Model = require('model')
local GitHub = require('github')

local function fixture()
    local state = Model.newState()
    local board = state.boards[1]
    Model.addLabel(board, 'Ready')
    Model.addLabel(board, 'Bug')
    board.github_id = 'test-board-identity'
    board.github = {repository='captaincamin/kanban.koplugin', upload_labels={[board.labels[1].id]=true,[board.labels[2].id]=true},
        label_map={[board.labels[2].id]='bug'}}
    Model.addCard(board, 'c1', {title='Fix offline drafts', notes='Keep local notes',
        labels={board.labels[1].id, board.labels[2].id}})
    local card = board.cards[board.columns[1].cards[1]]
    Model.addChecklistItem(board, card.id, 'Check restart')
    return state, board, card
end
local function issue(number)
    return {number=number, html_url='https://github.com/CaptainCamin/kanban.koplugin/issues/'..number}
end

describe('GitHub batch publishing', function()
    it('accepts repository names and URLs and rejects arbitrary endpoints', function()
        assert.equals('owner/repo', GitHub.repository(' https://github.com/Owner/Repo/ '))
        assert.is_nil(GitHub.repository('https://other.example/owner/repo'))
        assert.is_nil(GitHub.repository('owner/repo/issues'))
        assert.is_nil(GitHub.repository('owner/..'))
        assert.is_nil(GitHub.repository('owner/repo?token=secret'))
    end)

    it('selects ready cards in board order and maps labels without mutating cards', function()
        local _, board, card = fixture()
        Model.addCard(board, 'c1', {title='Private idea'})
        Model.addCard(board, 'c2', {title='Next', labels={board.labels[1].id}})
        local candidates = assert(GitHub.candidates(board, {}))
        assert.equals(2, #candidates)
        assert.equals(card.id, candidates[1].card_id)
        assert.same({'bug'}, candidates[1].labels)
        assert.is_truthy(candidates[1].body:find('Keep local notes',1,true))
        assert.is_truthy(candidates[1].body:find('- [ ] Check restart',1,true))
        assert.is_truthy(candidates[1].body:find(candidates[1].marker,1,true))
        assert.equals('Keep local notes', card.notes)
        Model.archiveCard(board, card.id)
        assert.equals(1, #GitHub.candidates(board, {}))
    end)

    it('requires at least one existing upload label', function()
        local _, board = fixture()
        Model.deleteLabel(board, board.labels[1].id)
        Model.deleteLabel(board, board.labels[1].id)
        assert.is_nil(GitHub.candidates(board, {}))
    end)

    it('uploads cards with either enabled label once and includes both mapped labels', function()
        local _, board, card = fixture()
        local ready, bug = board.labels[1].id, board.labels[2].id
        board.github.upload_labels = {[ready]=true, [bug]=true}
        board.github.label_map[ready] = 'enhancement'
        Model.addCard(board, 'c2', {title='Only bug', labels={bug}})
        local candidates = GitHub.candidates(board,{})
        assert.equals(2,#candidates)
        assert.equals(card.id,candidates[1].card_id)
        assert.same({'enhancement','bug'},candidates[1].labels)
        assert.same({'bug'},candidates[2].labels)
        board.github.upload_labels[ready]=nil
        candidates=GitHub.candidates(board,{})
        assert.equals(2,#candidates)
        assert.same({'bug'},candidates[1].labels)
    end)

    it('saves before POST and saves each successful issue before proceeding', function()
        local _, board = fixture()
        local journal, events = {}, {}
        local candidate = GitHub.candidates(board,journal)[1]
        local link = assert(GitHub.publish(candidate,journal,function() events[#events+1]='save' end,
            function(method,path,payload)
                events[#events+1]='post'
                assert.equals('POST',method)
                assert.equals('/repos/captaincamin/kanban.koplugin/issues',path)
                assert.equals(candidate.title,payload.title)
                assert.same({'bug'},payload.labels)
                assert.is_truthy(journal[candidate.key])
                return issue(12)
            end))
        assert.same({'save','post','save'},events)
        assert.equals(12,link.number)
        assert.equals(0,#GitHub.candidates(board,journal))
        assert.equals(12,GitHub.publish(candidate,journal,function() error('unexpected save') end,
            function() error('duplicate POST') end).number)
    end)

    it('does not send a request if the attempt cannot be persisted', function()
        local _, board = fixture()
        local candidate = GitHub.candidates(board,{})[1]
        local ok = pcall(GitHub.publish,candidate,{},function() error('disk full') end,
            function() error('must not reach network') end)
        assert.is_false(ok)
    end)

    it('reconciles an interrupted accepted POST instead of posting again', function()
        local _, board, card = fixture()
        local journal = {}
        local candidate = GitHub.candidates(board,journal)[1]
        assert.is_nil(GitHub.publish(candidate,journal,function() end,function() return nil,'timeout' end,function() return 100 end))
        card.title='Edited offline'
        local retry = GitHub.candidates(board,journal)[1]
        assert.equals(candidate.title,retry.title)
        local recovered = assert(GitHub.publish(retry,journal,function() end,function(method)
            assert.equals('GET',method)
            local existing=issue(42); existing.body=candidate.body
            return {existing}
        end))
        assert.equals(42,recovered.number)
        assert.equals(0,#GitHub.candidates(board,journal))
    end)

    it('keeps uncertain attempts pending when no matching issue can be found', function()
        local _, board = fixture()
        local journal={}
        local candidate=GitHub.candidates(board,journal)[1]
        GitHub.publish(candidate,journal,function() end,function() return nil,'timeout' end)
        assert.is_nil(GitHub.publish(candidate,journal,function() end,function(method)
            assert.equals('GET',method); return {}
        end))
        assert.is_truthy(journal[candidate.key])
    end)

    it('retries definitive client rejections using current card content', function()
        local _, board, card=fixture()
        local journal={}
        local candidate=GitHub.candidates(board,journal)[1]
        assert.is_nil(GitHub.publish(candidate,journal,function() end,function() return nil,'forbidden',403 end))
        assert.is_nil(journal[candidate.key])
        card.title='Corrected title'
        assert.equals('Corrected title',GitHub.candidates(board,journal)[1].title)
    end)

    it('does not retry ambiguous server errors, malformed successes, or request timeouts as POST', function()
        local _, board=fixture()
        for _, result in ipairs({{nil,'server error',500},{nil,'timeout',408},{number=9,html_url='https://evil.example/'}}) do
            local journal={}
            local candidate=GitHub.candidates(board,journal)[1]
            local response = result.number and result or nil
            GitHub.publish(candidate,journal,function() end,function() return response,result[2],result[3] end)
            assert.is_truthy(journal[candidate.key])
            assert.is_nil(journal[candidate.key].issue)
        end
    end)

    it('paginates recovery and ignores pull requests with copied markers', function()
        local _, board=fixture()
        local journal={}
        local candidate=GitHub.candidates(board,journal)[1]
        GitHub.publish(candidate,journal,function() end,function() return nil,'timeout' end)
        local pages=0
        local recovered=assert(GitHub.publish(candidate,journal,function() end,function(method,path)
            pages=pages+1
            assert.is_truthy(path:find('page='..pages,1,true))
            local existing=issue(21); existing.body=candidate.body
            if pages==2 then return {existing} end
            existing.pull_request={}
            local rows={existing}
            for i=2,100 do rows[i]={body='unrelated'} end
            return rows
        end))
        assert.equals(2,pages)
        assert.equals(21,recovered.number)
    end)

    it('keeps upload identities and allocated IDs stable across undo', function()
        local state,board,card=fixture()
        local before=Model.copyBoard(board)
        before.github_id=nil
        local journal={}
        local candidate=GitHub.candidates(board,journal)[1]
        GitHub.publish(candidate,journal,function() end,function() return issue(4) end)
        local count=board.next_id
        Model.addCard(board,'c1',{title='New card'})
        Model.restoreBoard(state,before)
        board=state.boards[1]
        assert.equals('test-board-identity',board.github_id)
        assert.is_true(board.next_id>count)
        assert.equals(0,#GitHub.candidates(board,journal))
    end)

    it('tracks the same card independently for different repositories', function()
        local _,board=fixture()
        local journal={}
        local candidate=GitHub.candidates(board,journal)[1]
        GitHub.publish(candidate,journal,function() end,function() return issue(4) end)
        board.github.repository='other/repo'
        assert.equals(1,#GitHub.candidates(board,journal))
        board.github.repository='captaincamin/kanban.koplugin'
        assert.equals(0,#GitHub.candidates(board,journal))
    end)
end)
