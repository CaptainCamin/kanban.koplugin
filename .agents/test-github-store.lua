-- Real settings checks in KOReader using a temporary directory and fake tokens.
local Store=require('githubstore')
local DataStorage=require('datastorage')
local original=DataStorage.getSettingsDir
local path=os.tmpname()
os.remove(path)
assert(require('libs/libkoreader-lfs').mkdir(path) or require('libs/libkoreader-lfs').attributes(path,'mode')=='directory')
DataStorage.getSettingsDir=function() return path end
local ok,err=xpcall(function()
    os.remove(path..'/kanban-github.lua')
    os.remove(path..'/kanban-github.lua.old')
    local data,save=Store.open()
    data.token='FAKE_TEST_TOKEN'
    data.uploads.example={started=100,issue={number=1,url='https://github.com/owner/repo/issues/1'}}
    save()
    local reloaded=Store.open()
    assert(reloaded.token==data.token and reloaded.uploads.example.issue.number==1)
    local backup=assert(io.open(path..'/kanban-github.lua.old','w'))
    backup:write('return {github={token="FAKE_OLD_TOKEN",uploads={}}}'); backup:close()
    data.token=nil
    save()
    assert(Store.open().token==nil)
    assert(io.open(path..'/kanban-github.lua.old','r')==nil)
    assert(Store.open().uploads.example.issue.number==1)
    local corrupt=assert(io.open(path..'/kanban-github.lua','w')); corrupt:write('broken file'); corrupt:close()
    assert(not pcall(Store.open))
    return true
end,debug.traceback)
DataStorage.getSettingsDir=original
os.remove(path..'/kanban-github.lua')
os.remove(path..'/kanban-github.lua.old')
require('libs/libkoreader-lfs').rmdir(path)
assert(ok,err)
return {passed=true,checks='journal reload, token removal, old-token backup removal, history retained, corrupt history fails closed'}
