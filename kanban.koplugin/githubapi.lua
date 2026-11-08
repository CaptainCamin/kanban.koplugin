local Api = {}

-- LuaSec on KOReader exposes SANs but not OpenSSL's checkhost helper.
-- This client only ever connects to api.github.com.
function Api.isGitHubCertificate(cert)
    if not cert then return false end
    local sans = (cert:extensions() or {})['2.5.29.17'] or {}
    for _, name in ipairs(sans.dNSName or {}) do
        if name:lower() == 'api.github.com' or name:lower() == '*.github.com' then return true end
    end
    return false
end

function Api.client(token)
    local http = require('socket.http')
    local https = require('ssl.https')
    local ltn12 = require('ltn12')
    local json = require('rapidjson')
    local socketutil = require('socketutil')
    return function(method, path, payload)
        local chunks = {}
        local body = payload and json.encode(payload)
        local tls = https.tcp{
            verify='peer', cafile=os.getenv('SSL_CERT_FILE') or 'data/ca-bundle.crt',
        }
        local function create()
            local conn = tls()
            local connect = conn.connect
            function conn:connect(host, port)
                local ok, err = connect(self, host, port)
                if not ok then return nil, err end
                local cert = self.sock:getpeercertificate()
                if not Api.isGitHubCertificate(cert) then
                    self:close()
                    return nil, 'GitHub certificate hostname mismatch'
                end
                return 1
            end
            return conn
        end
        socketutil:set_timeout(5, 10)
        local ok, result, status = pcall(http.request, {
            url='https://api.github.com' .. path, method=method, redirect=false, create=create,
            headers={
                ['authorization']='Bearer ' .. token,
                ['accept']='application/vnd.github+json', ['x-github-api-version']='2022-11-28',
                ['user-agent']='KOReader-Kanban', ['content-type']='application/json',
                ['content-length']=body and #body or 0,
            },
            source=body and ltn12.source.string(body), sink=socketutil.table_sink(chunks),
        })
        socketutil:reset_timeout()
        -- Do not expose low-level errors or server-supplied text containing credentials.
        if not ok or not result or not tonumber(status) then return nil, 'Could not reach GitHub. Check your connection and retry.' end
        status = tonumber(status)
        if status == 401 then return nil, 'GitHub rejected the token. Update it in GitHub settings.', status end
        if status == 403 or status == 429 then return nil, 'GitHub denied the request or rate-limited it. Check repository permissions and retry later.', status end
        if status == 404 then return nil, 'Repository not found or the token cannot access it.', status end
        if status == 422 then return nil, 'GitHub rejected the issue. Check its title and mapped labels; labels must already exist in the repository.', status end
        if status < 200 or status >= 300 then return nil, 'GitHub request failed (HTTP ' .. status .. ').', status end
        local decoded_ok, response = pcall(json.decode, table.concat(chunks))
        if not decoded_ok or type(response) ~= 'table' then return nil, 'Invalid response from GitHub.', status end
        return response, nil, status
    end
end

return Api
