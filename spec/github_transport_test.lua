-- Standalone transport checks: no network calls or credentials required.
package.path = './kanban.koplugin/?.lua;' .. package.path
local status, body, throws, wrong_host = 201, 'valid', false, false
local tls_options, last_request, resets, closed = nil, nil, 0, false
local timeouts = {set_timeout=function() end, reset_timeout=function() resets=resets+1 end,
    table_sink=function(chunks) return function(chunk) if chunk then chunks[#chunks+1]=chunk end; return 1 end end}
package.preload.socketutil=function() return timeouts end
package.preload.ltn12=function() return {source={string=function(value) return function() return value end end}} end
package.preload.rapidjson=function() return {
    encode=function() return 'encoded-json' end,
    decode=function(value) if value~='valid' then error('bad JSON') end; return {number=1} end,
} end
package.preload['ssl.https']=function() return {tcp=function(options)
    tls_options=options
    return function() return {
        connect=function() return 1 end, close=function() closed=true end,
        sock={getpeercertificate=function() return {extensions=function() return {
            ['2.5.29.17']={dNSName={wrong_host and 'evil.example' or '*.github.com'}}
        } end} end},
    } end
end} end
package.preload['socket.http']=function() return {request=function(request)
    last_request=request
    if throws then error('request failed with FAKE_TOKEN') end
    local conn=request.create()
    local ok, err=conn:connect('api.github.com',443)
    if not ok then return nil,err end
    request.sink(body)
    return 1,status,{}
end} end
local Api=require('githubapi')
local request=Api.client('FAKE_TOKEN')
assert(request('POST','/repos/owner/repo/issues',{title='Example'}).number==1)
assert(last_request.url=='https://api.github.com/repos/owner/repo/issues')
assert(last_request.headers.authorization=='Bearer FAKE_TOKEN')
assert(last_request.redirect==false and tls_options.verify=='peer' and tls_options.cafile)
assert(last_request.scheme=='http' and last_request.port==443 and last_request.create)
assert(last_request.headers['content-length']==#'encoded-json')
assert(resets==1)
for _,code in ipairs({401,403,404,422,429,500,301}) do
    status=code
    local result,err,returned=request('POST','/repos/owner/repo/issues',{})
    assert(result==nil and type(err)=='string' and returned==code)
    assert(not err:find('FAKE_TOKEN',1,true))
end
status,body=201,'malformed'
assert(request('POST','/repos/owner/repo/issues',{})==nil)
throws=true
local result,err=request('POST','/repos/owner/repo/issues',{})
assert(result==nil and not err:find('FAKE_TOKEN',1,true))
assert(resets==10)
throws,body,wrong_host=false,'valid',true
assert(request('POST','/repos/owner/repo/issues',{})==nil and closed)
print('GitHub transport checks passed: TLS, hostname, redirects, auth, errors, JSON, timeouts')
