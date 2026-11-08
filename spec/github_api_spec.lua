local Api = require('githubapi')

describe('GitHub HTTPS transport', function()
    it('accepts only GitHub API certificate names after chain validation', function()
        local function cert(names)
            return {extensions=function() return {['2.5.29.17']={dNSName=names}} end}
        end
        assert.is_true(Api.isGitHubCertificate(cert({'api.github.com'})))
        assert.is_true(Api.isGitHubCertificate(cert({'*.github.com'})))
        assert.is_false(Api.isGitHubCertificate(cert({'other.github.com'})))
        assert.is_false(Api.isGitHubCertificate(cert({'api.github.com.evil.example'})))
        assert.is_false(Api.isGitHubCertificate(cert({'*.*.com'})))
        assert.is_false(Api.isGitHubCertificate(cert({})))
        assert.is_false(Api.isGitHubCertificate(nil))
    end)
end)
