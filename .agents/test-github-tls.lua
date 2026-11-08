-- Invoked by test-github-tls.py with a bundled KOReader runtime.
require('setupkoenv')
package.path = arg[1] .. '/kanban.koplugin/?.lua;' .. package.path
-- socketutil uses only this metadata for its User-Agent. The HTTP, socket and
-- TLS implementations below are the actual bundled modules, without mocks.
package.loaded.device = {model='GitHub transport test'}
local socketutil = require('socketutil')
local socket = require('socket')
local http = require('socket.http')
local Api = require('githubapi')
local probe = socket.tcp()
local methods = getmetatable(probe).__index
probe:close()
local original = methods.connect
local port = tonumber(arg[2])
methods.connect = function(self, host, requested_port)
    assert(host == 'api.github.com' and tonumber(requested_port) == 443)
    return original(self, '127.0.0.1', port)
end
local request = Api.client('FAKE_TLS_TEST_TOKEN')
local response, err, status = request('POST', '/post', {title='Local TLS test'})
assert(response and response.number==123 and status==201, err)
local issues = assert(request('GET', '/get'))
assert(issues[1].number==123)
-- Simulate an older HTTP parser with no HTTPS scheme definition.
if http.schemes then http.schemes.https = nil end
assert(request('POST', '/post', {title='Legacy parser test'}))
response, err, status = request('GET', '/redirect')
assert(response==nil and status==301)
port = tonumber(arg[3])
assert(request('POST', '/post', {title='Wrong hostname'})==nil)
port = tonumber(arg[4])
assert(request('POST', '/post', {title='Untrusted certificate'})==nil)
assert(socketutil.total_timeout==socketutil.DEFAULT_TOTAL_TIMEOUT)
methods.connect = original
print('Real HTTP/TLS checks passed: POST, GET, legacy parser, redirects, hostname, certificate trust')
