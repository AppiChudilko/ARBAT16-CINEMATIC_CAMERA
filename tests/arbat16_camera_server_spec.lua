-- Offline storage contract tests. Run with Lua 5.4 or lupa.lua54.
local serverPath = arg[1] or 'resource/arbat16_camera/server/main.lua'
local corePath = arg[2] or serverPath:gsub('server[/\\]main%.lua$', 'shared/core.lua')
local directorPath = arg[3] or serverPath:gsub('server[/\\]main%.lua$', 'shared/director.lua')
local checks = 0
local function equal(actual, expected, label)
    assert(actual == expected, (label or 'value') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
end
local function clone(value)
    if type(value) ~= 'table' then return value end
    local copy = {}; for key, child in pairs(value) do copy[key] = clone(child) end; return copy
end
local function signature(value)
    if type(value) == 'string' then return string.format('%q', value) end
    if type(value) ~= 'table' then return tostring(value) end
    local keys, parts = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do parts[#parts + 1] = '[' .. signature(key) .. ']=' .. signature(value[key]) end
    return '{' .. table.concat(parts, ',') .. '}'
end
local function scene(duration)
    return {version = 1, duration = duration or 4, frames = {{time = 0}, {time = duration or 4}}}
end
local function fixture(overrides)
    local f = {time = 10000, store = {}, jsonDocuments = {}, events = {}, sent = {}, writes = 0,
        kvpReads = 0, deletes = 0, encodeCalls = 0, decodeCalls = 0,
        files = {}, fileReads = 0, fileWrites = 0, warnings = {}, fileCalls = {},
        acl = {[1] = true, [2] = true}, identifiers = {[1] = 'license:aaaaaaaa', [2] = 'license:bbbbbbbb'},
        config = {RequireAce = true, AcePermission = 'arbat16_camera.use', MaxScenes = 30,
            MaxFrames = 200, MaxSceneBytes = 262144, StorageCooldown = 600}}
    for key, value in pairs(overrides or {}) do f.config[key] = value end
    local env = setmetatable({}, {__index = _G})
    f.env = env
    env.FCConfig = f.config
    env.os = setmetatable({date = function(format)
        equal(format, '!%Y-%m-%dT%H:%M:%SZ'); return '2026-09-24T22:15:00Z'
    end}, {__index = os})
    function env.print(message) f.warnings[#f.warnings + 1] = message end
    env.FC = {Core = {validateScene = function(raw)
        if f.validateThrows then error('internal identifier:license:aaaaaaaa') end
        if raw.invalid or type(raw.frames) ~= 'table' or #raw.frames < 2 or #raw.frames > f.config.MaxFrames then
            return nil, 'invalid scene'
        end
        local clean = clone(raw); clean.privateField = nil; return clean
    end, duration = function(value) return value.duration end}}
    env.json = {
        encode = function(value)
            f.encodeCalls = f.encodeCalls + 1
            if f.encodeThrows then error('internal encoder error') end
            local encoded = signature(value)
            if f.encodeTooLarge then encoded = encoded .. string.rep(' ', f.config.MaxSceneBytes + 1) end
            if f.workspaceEncodeTooLarge then encoded = encoded .. string.rep(' ', 8388609) end
            f.jsonDocuments[encoded] = clone(value)
            return encoded
        end,
        decode = function(value)
            f.decodeCalls = f.decodeCalls + 1
            assert(f.jsonDocuments[value], 'corrupt document contains license:aaaaaaaa')
            return clone(f.jsonDocuments[value])
        end
    }
    function env.RegisterNetEvent(name, handler) f.events[name] = handler end
    function env.AddEventHandler(name, handler) f.events[name] = handler end
    function env.IsPlayerAceAllowed(player, permission)
        equal(type(player), 'string', 'native player source'); equal(permission, f.config.AcePermission)
        return f.acl[tonumber(player)]
    end
    function env.GetPlayerIdentifierByType(player, identifierType)
        equal(identifierType, 'license'); return f.identifiers[player]
    end
    function env.GetGameTimer() return f.time % 4294967296 end
    function env.GetCurrentResourceName() return 'arbat16_camera' end
    function env.LoadResourceFile(resource, path)
        equal(resource, 'arbat16_camera'); equal(path, 'camera-diagnostics.jsonl')
        f.fileReads = f.fileReads + 1
        if f.fileReadThrows then error('private server file read failure') end
        return f.files[path]
    end
    function env.SaveResourceFile(resource, path, value, size)
        equal(resource, 'arbat16_camera'); equal(path, 'camera-diagnostics.jsonl')
        equal(size, #value); assert(size <= 262144, 'diagnostic log exceeded its hard byte limit')
        f.fileCalls[#f.fileCalls + 1] = path
        if f.fileWriteThrows then error('private server file write failure') end
        if f.fileWriteFalse then return false end
        f.fileWrites = f.fileWrites + 1; f.files[path] = value
        return f.fileWriteResult == nil and true or f.fileWriteResult
    end
    function env.GetResourceKvpString(key)
        f.kvpReads = f.kvpReads + 1
        if f.readThrows then error('disk read error for ' .. key) end
        return f.store[key]
    end
    function env.SetResourceKvp(key, value)
        if f.writeThrows then error('disk write error for ' .. key) end
        if f.writeFalse then return false end
        f.writes = f.writes + 1; f.store[key] = value
    end
    function env.DeleteResourceKvp(key)
        if f.deleteThrows then error('private KVP delete error for ' .. key) end
        if f.deleteFalse then return false end
        f.deletes = f.deletes + 1; f.store[key] = nil
    end
    function env.TriggerClientEvent(name, player, ...)
        f.sent[#f.sent + 1] = {name = name, player = player, args = clone({...})}
    end
    assert(loadfile(serverPath, 't', env))()
    function f.event(player, event, ...)
        env.source = player; assert(f.events[event], event)(...)
    end
    function f.request(player, operation, payload, id, wait)
        if wait ~= false then f.time = f.time + 601 end
        local before = #f.sent
        f.event(player, 'arbat16_camera:storage', id == nil and 'request-1' or id, operation, payload)
        local message = f.sent[#f.sent]
        if #f.sent == before then return nil end
        equal(message.name, 'arbat16_camera:storageResult'); equal(message.player, player)
        equal(message.args[1], id == nil and 'request-1' or id)
        return message.args[2]
    end
    function f.save(name, value, player)
        return f.request(player or 1, 'save', {name = name or 'Сцена', scene = value or scene()})
    end
    function f.key(player) return 'arbat16_camera:v1:' .. f.identifiers[player] end
    function f.setDocument(document, player)
        f.store[f.key(player or 1)] = env.json.encode(document)
    end
    function f.useRealCore() assert(loadfile(corePath, 't', env))(); return env.FC.Core end
    function f.useRealDirector()
        f.useRealCore(); assert(loadfile(directorPath, 't', env))(); return env.FC.Director
    end
    function f.workspaceKey(player)
        return 'arbat16_camera:workspace:v1:' .. f.identifiers[player or 1]
    end
    function f.workspaceValue()
        return {version = 1, scene = {version = 1, name = 'Working scene', frames = {}},
            camera = f.env.FC.Core.defaultFrame({x = 100, y = 200, z = 300}, {x = -5, y = 2, z = 45}),
            settings = {speed = 3, showPath = true, hideHud = true, letterbox = false, grid = false},
            cameras = {}, presets = {}, time = 0}
    end
    function f.workspaceRequest(event, value, player, id, wait)
        player, id = player or 1, id == nil and 'workspace-1' or id
        if wait ~= false then f.time = f.time + 501 end
        local before = #f.sent
        if event == 'workspaceReset' then f.event(player, 'arbat16_camera:' .. event, id)
        else f.event(player, 'arbat16_camera:' .. event, id, value) end
        if #f.sent == before then return nil end
        local message = f.sent[#f.sent]
        equal(message.name, 'arbat16_camera:workspaceResult'); equal(message.player, player)
        equal(message.args[1], id); return message.args[2]
    end
    function f.openContext(player)
        f.event(player or 1, 'arbat16_camera:requestOpen')
        local message = f.sent[#f.sent]
        equal(message.name, 'arbat16_camera:openAllowed'); return message.args[2], message.args[1]
    end
    function f.diagnostic(payload, player)
        f.event(player or 1, 'arbat16_camera:diagnostic', payload or {event = 'runtime'})
    end
    function f.diagnosticRows()
        local rows = {}
        for line in (f.files['camera-diagnostics.jsonl'] or ''):gmatch('([^\n]+)\n') do
            rows[#rows + 1] = f.env.json.decode(line)
        end
        return rows
    end
    return f
end

local function test(name, run)
    local ok, reason = pcall(run)
    assert(ok, name .. ': ' .. tostring(reason))
    checks = checks + 1
end

test('open checks ACE and blocks server source', function()
    local f = fixture(); f.event(1, 'arbat16_camera:requestOpen')
    equal(f.sent[1].name, 'arbat16_camera:openAllowed'); equal(f.sent[1].args[1], true)
    f.acl[1] = false; f.event(1, 'arbat16_camera:requestOpen'); equal(f.sent[2].args[1], false)
    f.event(0, 'arbat16_camera:requestOpen'); equal(#f.sent, 2)
end)

test('permission rechecked for every operation', function()
    local f = fixture(); assert(f.save().ok); local before = f.store[f.key(1)]
    f.acl[1] = false
    for _, operation in ipairs({'list', 'load', 'save', 'delete'}) do
        local result = f.request(1, operation, {name = 'Сцена', scene = scene()})
        equal(result.ok, false); assert(result.error:find('ACE'))
    end
    equal(f.store[f.key(1)], before); equal(f.writes, 1)
end)

test('integer BOOL grant permits open and the complete storage lifecycle', function()
    local f = fixture(); f.acl[1] = 1
    f.event(1, 'arbat16_camera:requestOpen')
    equal(f.sent[1].args[1], true)
    equal(f.save('Native BOOL').ok, true)
    equal(f.request(1, 'list').items[1].name, 'Native BOOL')
    equal(f.request(1, 'load', {name = 'Native BOOL'}).ok, true)
    equal(f.request(1, 'delete', {name = 'Native BOOL'}).ok, true)
    equal(f.writes, 2)
end)

test('integer BOOL zero denies open and every storage operation without writes', function()
    local f = fixture(); equal(f.save('Protected').ok, true)
    local before = f.store[f.key(1)]; f.acl[1] = 0
    f.event(1, 'arbat16_camera:requestOpen')
    equal(f.sent[#f.sent].args[1], false)
    for _, operation in ipairs({'list', 'load', 'save', 'delete'}) do
        local result = f.request(1, operation, {name = 'Protected', scene = scene(20)})
        equal(result.ok, false); assert(result.error:find('ACE'))
    end
    equal(f.store[f.key(1)], before); equal(f.writes, 1)
end)

test('unexpected truthy native values never grant permission', function()
    local f = fixture()
    for _, value in ipairs({2, -1, '1', 'true', {}}) do
        f.acl[1] = value; f.event(1, 'arbat16_camera:requestOpen')
        equal(f.sent[#f.sent].args[1], false)
        equal(f.save('Denied').ok, false)
    end
    equal(f.writes, 0)
end)

test('public configuration can disable ACE', function()
    local f = fixture({RequireAce = false}); f.acl[1] = false
    equal(f.request(1, 'list').ok, true)
end)

test('full lifecycle and canonical scene storage', function()
    local f = fixture(); local raw = scene(12); raw.privateField = 'not persisted'
    local saved = f.save('  Поезд в горах  ', raw)
    equal(saved.ok, true); equal(saved.items[1].name, 'Поезд в горах')
    equal(saved.name, 'Поезд в горах')
    equal(saved.items[1].frames, 2); equal(saved.items[1].duration, 12)
    local loaded = f.request(1, 'load', {name = 'Поезд в горах'})
    equal(loaded.ok, true); equal(loaded.scene.duration, 12); equal(loaded.scene.privateField, nil)
    equal(loaded.name, 'Поезд в горах'); equal(loaded.scene.name, 'Поезд в горах')
    equal(f.request(1, 'list').items[1].name, 'Поезд в горах')
    local deleted = f.request(1, 'delete', {name = 'Поезд в горах'})
    equal(deleted.ok, true); equal(#deleted.items, 0)
    equal(f.request(1, 'load', {name = 'Поезд в горах'}).ok, false)
end)

test('ownership isolated and stable across source IDs', function()
    local f = fixture(); assert(f.save('Private').ok)
    equal(#f.request(2, 'list').items, 0)
    equal(f.request(2, 'load', {name = 'Private', identifier = f.identifiers[1]}).ok, false)
    equal(f.request(2, 'delete', {name = 'Private'}).ok, false)
    f.identifiers[7] = f.identifiers[1]; f.acl[7] = true
    equal(f.request(7, 'load', {name = 'Private'}).ok, true)
end)

test('missing or malformed stable identity never falls back to source', function()
    local f = fixture()
    for _, identifier in ipairs({'', 'ip:127.0.0.1', 'license:../../other', 'license:123'}) do
        f.identifiers[1] = identifier
        local result = f.request(1, 'list'); equal(result.ok, false)
        assert(not result.error:find(identifier, 1, true) or identifier == '')
    end
    f.identifiers[1] = nil; equal(f.request(1, 'list').ok, false); equal(f.writes, 0)
end)

test('request IDs are bounded and invalid IDs are not reflected', function()
    local f = fixture()
    for _, id in ipairs({{}, true, '', string.rep('r', 65), '../x', -1, 1.5, math.huge, 2147483648}) do
        equal(f.request(1, 'list', nil, id), nil)
    end
    equal(f.request(1, 'list', nil, 0).ok, true)
    equal(f.request(1, 'list', nil, 2147483647).ok, true)
    equal(f.request(1, 'list', nil, 'nui:20_1-2').ok, true)
    equal(f.request(0, 'list'), nil)
end)

test('invalid operations and payloads produce useful errors', function()
    local f = fixture()
    for _, operation in ipairs({'wipe', '', 7}) do equal(f.request(1, operation).ok, false) end
    for _, operation in ipairs({'load', 'save', 'delete'}) do equal(f.request(1, operation, 'wrong').ok, false) end
    equal(f.request(1, 'delete', {name = 'Missing'}).ok, false)
end)

test('scene labels reject controls paths invalid UTF-8 and oversize', function()
    local f = fixture()
    for _, name in ipairs({'', '  ', '.', '..', '../x', 'a/b', 'a\\b', 'a\0b', 'a\nb', 'x\n',
        '\194\128', '\255', string.rep('я', 33), string.rep('a', 65)}) do
        equal(f.save(name).ok, false, 'name ' .. name)
    end
    equal(f.save(string.rep('я', 32)).ok, true)
end)

test('scene quota blocks new names but permits replacement', function()
    local f = fixture({MaxScenes = 2})
    assert(f.save('A').ok); assert(f.save('B').ok)
    local prior = f.store[f.key(1)]
    equal(f.save('C').ok, false); equal(f.store[f.key(1)], prior)
    equal(f.save('A', scene(7)).ok, true)
    equal(f.request(1, 'load', {name = 'A'}).scene.duration, 7)
end)

test('server library stays bounded to 30 even with excessive configuration', function()
    local f = fixture({MaxScenes = 10000})
    for i = 1, 30 do assert(f.save('Scene ' .. i).ok) end
    equal(f.save('Scene 31').ok, false)
end)

test('scene validation and failed encodes preserve prior library', function()
    local f = fixture(); assert(f.save('Keep').ok)
    local prior = f.store[f.key(1)]
    equal(f.save('Keep', {invalid = true, frames = {}}).ok, false)
    f.validateThrows = true; equal(f.save('Keep').ok, false); f.validateThrows = false
    f.encodeThrows = true; equal(f.save('Keep').ok, false); f.encodeThrows = false
    f.encodeTooLarge = true; equal(f.save('Keep').ok, false); f.encodeTooLarge = false
    equal(f.store[f.key(1)], prior); equal(f.writes, 1)
end)

test('cycles nesting non-finite numbers unsupported values and width are bounded', function()
    local f = fixture(); local cyclic = scene(); cyclic.self = cyclic
    local deep = scene(); local child = deep
    for _ = 1, 15 do child.nested = {}; child = child.nested end
    local wide = scene(); for i = 1, 20000 do wide['field' .. i] = true end
    local nan = scene(); nan.value = 0 / 0
    local infinity = scene(); infinity.value = math.huge
    local callable = scene(); callable.value = function() end
    local meta = setmetatable(scene(), {})
    for _, value in ipairs({cyclic, deep, wide, nan, infinity, callable, meta}) do
        equal(f.save('Bad', value).ok, false)
    end
    equal(f.writes, 0)
end)

test('oversized scene rejected before encoder', function()
    local f = fixture(); local raw = scene(); raw.payload = string.rep('a', 262145)
    f.env.json.encode = function() error('encoder should not be called') end
    equal(f.save('Huge', raw).ok, false); equal(f.writes, 0)
end)

test('corrupt or empty KVP never replaced by fresh library', function()
    for _, raw in ipairs({'broken-json', ''}) do
        local f = fixture(); f.store[f.key(1)] = raw
        local result = f.save('New'); equal(result.ok, false)
        assert(not result.error:find('license', 1, true))
        equal(f.store[f.key(1)], raw); equal(f.writes, 0)
    end
end)

test('invalid stored schema and timestamps fail closed', function()
    for _, document in ipairs({{}, {version = 99, scenes = {}}, {version = 1, scenes = 'bad'},
        {version = 1, scenes = {A = {scene = scene(), updated = -1}}},
        {version = 1, scenes = {A = {scene = {invalid = true}, updated = 1}}},
        {version = 1, scenes = {['../x'] = {scene = scene(), updated = 1}}}}) do
        local f = fixture(); f.setDocument(document)
        local prior = f.store[f.key(1)]
        equal(f.save('New').ok, false); equal(f.store[f.key(1)], prior); equal(f.writes, 0)
    end
end)

test('oversized and over-count stored libraries fail closed', function()
    local f = fixture({MaxScenes = 1})
    f.store[f.key(1)] = string.rep('x', (4194304 + 512) * 30 + 1025)
    local decodeCalls = 0
    local decode = f.env.json.decode
    f.env.json.decode = function(raw) decodeCalls = decodeCalls + 1; return decode(raw) end
    equal(f.request(1, 'list').ok, false)
    equal(decodeCalls, 0, 'oversized storage must be rejected before JSON decode')
    local document = {version = 1, scenes = {}}
    for i = 1, 31 do document.scenes['Scene ' .. i] = {scene = scene(), updated = i} end
    f.setDocument(document)
    equal(f.request(1, 'list').ok, false); equal(f.writes, 0)
end)

test('read and write errors do not leak server identifiers', function()
    local f = fixture(); assert(f.save('Keep').ok); local prior = f.store[f.key(1)]
    f.readThrows = true; local read = f.request(1, 'list'); equal(read.ok, false)
    assert(not read.error:find('license', 1, true)); f.readThrows = false
    f.writeThrows = true; local write = f.save('New'); equal(write.ok, false)
    assert(not write.error:find('license', 1, true)); f.writeThrows = false
    f.writeFalse = true; equal(f.save('New').ok, false)
    equal(f.store[f.key(1)], prior); equal(f.writes, 1)
end)

test('one atomic write per mutation and no writes during reads', function()
    local f = fixture(); assert(f.save('A').ok); equal(f.writes, 1)
    assert(f.request(1, 'list').ok); assert(f.request(1, 'load', {name = 'A'}).ok); equal(f.writes, 1)
    assert(f.request(1, 'delete', {name = 'A'}).ok); equal(f.writes, 2)
    local count = 0; for _ in pairs(f.store) do count = count + 1 end; equal(count, 1)
end)

test('storage rate limit is per player and survives timer rollover', function()
    local f = fixture(); equal(f.request(1, 'list', nil, nil, false).ok, true)
    equal(f.request(1, 'list', nil, nil, false).ok, false)
    equal(f.request(2, 'list', nil, nil, false).ok, true)
    f.time = 4294967290; equal(f.request(1, 'list', nil, nil, false).ok, true)
    f.time = f.time + 10; equal(f.request(1, 'list', nil, nil, false).ok, false)
    f.time = f.time + 600; equal(f.request(1, 'list', nil, nil, false).ok, true)
    f.event(1, 'playerDropped'); equal(f.request(1, 'list', nil, nil, false).ok, true)
end)

test('scene lists use stable newest-first ordering', function()
    local f = fixture()
    f.setDocument({version = 1, scenes = {Z = {scene = scene(), updated = 1},
        B = {scene = scene(), updated = 9}, A = {scene = scene(), updated = 9}}})
    local items = f.request(1, 'list').items
    equal(items[1].name, 'A'); equal(items[2].name, 'B'); equal(items[3].name, 'Z')
end)

test('real shared core scene persists with timeline duration and nested optics', function()
    local f = fixture(); local core = f.useRealCore()
    local a = core.defaultFrame({x = 1, y = 2, z = 3}, {x = 0, y = 0, z = 15})
    local b = core.defaultFrame({x = 4, y = 5, z = 6}, {x = 0, y = 0, z = 90})
    a.duration = 7; b.duration = 2; a.dof.enabled = true
    a.handleOut = {x = 1, y = 2, z = 0}
    local saved = f.save('Рассвет', {version = 1, name = 'Рассвет', frames = {a, b}, loop = true, speed = 0.5})
    equal(saved.ok, true); equal(saved.items[1].duration, 9); equal(saved.items[1].frames, 2)
    local loaded = f.request(1, 'load', {name = 'Рассвет'})
    equal(loaded.ok, true); equal(loaded.scene.frames[1].dof.enabled, true)
    equal(loaded.scene.frames[1].handleOut.y, 2); equal(loaded.scene.speed, 0.5)
    equal(f.save('Пустая', {version = 1, name = 'Пустая', frames = {}}).ok, true)
end)

test('configured frame limit enforced alongside real shared core', function()
    local f = fixture({MaxFrames = 1}); local core = f.useRealCore()
    local raw = {version = 1, name = 'A', frames = {core.defaultFrame(), core.defaultFrame()}}
    equal(f.save('A', raw).ok, false); equal(f.writes, 0)
end)

test('lowered limits preserve access to older scenes and allow deletion', function()
    local f = fixture({MaxScenes = 1, MaxFrames = 1, MaxSceneBytes = 1024})
    local core = f.useRealCore()
    local frames = {core.defaultFrame(), core.defaultFrame(), core.defaultFrame()}
    for _, frame in ipairs(frames) do frame.label = string.rep('a', 160) end
    local old = assert(core.validateScene({name = 'Old', frames = frames}))
    assert(#signature(old) > 1024, 'fixture must exceed the new byte limit')
    f.setDocument({version = 1, scenes = {A = {scene = old, updated = 1}, B = {scene = old, updated = 2}}})
    equal(#f.request(1, 'list').items, 2)
    equal(#f.request(1, 'load', {name = 'A'}).scene.frames, 3)
    equal(f.save('C', {name = 'C', frames = {}}).ok, false, 'new names still obey the new scene quota')
    equal(f.save('A', {name = 'A', frames = {}}).ok, true, 'replacement under new limits is allowed')
    equal(f.request(1, 'delete', {name = 'A'}).ok, true)
    equal(#f.request(1, 'load', {name = 'B'}).scene.frames, 3, 'deleting another scene preserves the large scene')
    equal(f.request(1, 'delete', {name = 'B'}).ok, true)
    equal(f.save('C', {name = 'C', frames = {}}).ok, true)
end)

test('existing Unicode scene titles and labels are never translated or renamed on read', function()
    local f = fixture(); local core = f.useRealCore()
    local frame = core.defaultFrame(); frame.label = 'Кадр у вокзала'
    local old = assert(core.validateScene({name = '  Рассвет  ', frames = {frame}}))
    f.setDocument({version = 1, scenes = {['Рассвет'] = {scene = old, updated = 1}}})
    local prior = f.store[f.key(1)]
    local loaded = f.request(1, 'load', {name = 'Рассвет'})
    equal(loaded.ok, true); equal(loaded.scene.name, '  Рассвет  ')
    equal(loaded.scene.frames[1].label, 'Кадр у вокзала')
    equal(f.store[f.key(1)], prior); equal(f.writes, 0)
    equal(f.save('New', {name = 'New', frames = {}}).ok, true)
    loaded = f.request(1, 'load', {name = 'Рассвет'})
    equal(loaded.scene.name, '  Рассвет  '); equal(loaded.scene.frames[1].label, 'Кадр у вокзала')
end)

test('name normalization replaces the same library entry without changing request data', function()
    local f = fixture(); local raw = scene(); raw.name = 'Original title'
    equal(f.save('  Dawn  ', raw).ok, true); equal(raw.name, 'Original title')
    local nextScene = scene(8); nextScene.name = 'Unrelated title'
    local saved = f.save('Dawn', nextScene)
    equal(saved.ok, true); equal(#saved.items, 1); equal(saved.name, 'Dawn')
    local loaded = f.request(1, 'load', {name = ' Dawn '})
    equal(loaded.name, 'Dawn'); equal(loaded.scene.name, 'Dawn'); equal(loaded.scene.duration, 8)
end)

test('new scene names are included in canonical size validation', function()
    local f = fixture({MaxSceneBytes = 1024})
    local canonical = {frames = {{time = 0}, {time = 1}}, duration = 1, payload = ''}
    canonical.payload = string.rep('a', 1000 - #signature(canonical))
    equal(#signature(canonical), 1000, 'unnamed canonical scene fits the byte limit')
    f.env.FC.Core.validateScene = function() return clone(canonical) end
    equal(f.save(string.rep('n', 64)).ok, false); equal(f.writes, 0)
end)

test('validation errors are useful English messages while runtime exceptions stay private', function()
    local f = fixture(); local core = f.useRealCore()
    local frame = core.defaultFrame(); frame.fov = 999
    local invalid = f.save('Invalid', {frames = {frame}})
    equal(invalid.ok, false); assert(invalid.error:find('scene.frames[1].fov', 1, true))
    assert(invalid.error:match('^[%z\1-\127]+$'), 'server-authored error must be English ASCII')
    f.env.FC.Core.validateScene = function() error('private license:aaaaaaaa') end
    local failed = f.save('Failure', {frames = {}})
    equal(failed.ok, false); assert(not failed.error:find('license', 1, true))
    assert(failed.error:match('^[%z\1-\127]+$'))
end)

test('diagnostics require valid player source and current ACE without storage access', function()
    local f = fixture(); f.acl[1] = 0
    f.diagnostic({event = 'runtime'})
    f.acl[1] = false; f.diagnostic({event = 'runtime'})
    f.acl[1] = true
    for _, player in ipairs({0, -1, 1.5, math.huge, 0 / 0, 'invalid'}) do f.diagnostic({event = 'runtime'}, player) end
    equal(f.fileWrites, 0); equal(f.fileReads, 0); equal(f.writes, 0); equal(#f.sent, 0)
    f.acl[1] = 1; f.identifiers[1] = nil
    f.diagnostic({event = 'runtime'})
    equal(f.fileWrites, 1, 'transient server source is enough; diagnostics never query player identity')
    f.time = f.time + 1000; f.acl[1] = 0; f.diagnostic({event = 'runtime'})
    equal(f.fileWrites, 1, 'revoked permission blocks later reports')
end)

test('diagnostics can be disabled without changing camera permissions or storage', function()
    local f = fixture({Diagnostics = false})
    f.diagnostic({event = 'runtime'})
    equal(f.fileWrites, 0); equal(f.fileReads, 0); equal(#f.warnings, 0)
    f.event(1, 'arbat16_camera:requestOpen'); equal(f.sent[#f.sent].args[1], true)
    equal(f.save('Still available').ok, true)
    local public = fixture({RequireAce = false}); public.acl[1] = false
    public.diagnostic({event = 'runtime'}); equal(public.fileWrites, 1)
end)

test('diagnostics whitelist fields and stamp server origin source and UTC time', function()
    local f = fixture()
    local payload = {event = 'flight.start-1', active = true, flight = true, playing = false,
        recording = false, uiReady = true, camera = 8, exists = true, cameraActive = true,
        cameraRendering = false, renderingCamera = 9, ticks = 100, tickAgeMs = 5,
        inputPackets = 18, inputAgeMs = 7, heldKeys = 2, nativeInputTicks = 31,
        nativeFlightInput = true, frameTime = 0.016, keyframes = 4, changedPoseSegments = 3,
        time = 1.5, duration = 12, speed = 1, revision = 2, stateSequence = 30,
        targetPosition = {x = 1, y = -2, z = 3, private = 'excluded'},
        nativePosition = {x = 4, y = 5, z = -6}, source = 999,
        receivedAt = 'spoof', origin = 'server', license = 'license:secret', path = '../../secret'}
    f.diagnostic(payload)
    local rows = f.diagnosticRows(); equal(#rows, 1); local row = rows[1]
    equal(row.event, payload.event); equal(row.camera, 8); equal(row.active, true)
    equal(row.playing, false); equal(row.cameraRendering, false); equal(row.frameTime, 0.016)
    equal(row.targetPosition.y, -2); equal(row.targetPosition.private, nil)
    equal(row.nativePosition.z, -6); equal(row.source, 1); equal(row.time, 1.5)
    equal(row.receivedAt, '2026-09-24T22:15:00Z'); equal(row.origin, 'client_report')
    equal(row.license, nil); equal(row.path, nil)
    assert(not f.files['camera-diagnostics.jsonl']:find('secret', 1, true))
    equal(f.writes, 0); equal(#f.sent, 0); equal(#f.warnings, 0)
end)

test('diagnostics reject malformed event labels without consuming the rate limit', function()
    local f = fixture()
    for _, payload in ipairs({false, 1, 'text', {}, {event = ''}, {event = 'line\nbreak'},
        {event = 'bad/path'}, {event = string.rep('x', 33)}, {event = {}}, {event = 'камера'},
        setmetatable({event = 'runtime'}, {__index = function() error('must not run') end})}) do
        f.event(1, 'arbat16_camera:diagnostic', payload)
    end
    equal(f.fileWrites, 0); equal(#f.warnings, 0)
    f.diagnostic({event = string.rep('x', 32)})
    equal(f.fileWrites, 1)
end)

test('diagnostics omit invalid scalar and vector values and ignore unknown nested data', function()
    local f = fixture(); local cycle = {}; cycle.self = cycle
    f.diagnostic({event = 'runtime', active = 'true', flight = 1, camera = 'license:secret',
        ticks = math.huge, tickAgeMs = -math.huge, inputPackets = 0 / 0,
        inputAgeMs = 1000000000001, heldKeys = {}, nativeFlightInput = function() end,
        targetPosition = {x = 1, y = 2, z = math.huge},
        nativePosition = {x = 1000001, y = 0, z = 0}, ignored = cycle, uiReady = true})
    local row = f.diagnosticRows()[1]
    equal(row.uiReady, true); equal(row.active, nil); equal(row.flight, nil); equal(row.camera, nil)
    equal(row.ticks, nil); equal(row.tickAgeMs, nil); equal(row.inputPackets, nil)
    equal(row.inputAgeMs, nil); equal(row.heldKeys, nil); equal(row.nativeFlightInput, nil)
    equal(row.targetPosition, nil); equal(row.nativePosition, nil); equal(row.ignored, nil)
    equal(#f.warnings, 0)
end)

test('diagnostic throttle is per player separate from storage and handles timer rollover', function()
    local f = fixture(); f.diagnostic({event = 'first'})
    equal(f.request(1, 'list', nil, nil, false).ok, true, 'diagnostics do not consume storage cooldown')
    f.diagnostic({event = 'blocked'}); equal(f.fileWrites, 1)
    f.diagnostic({event = 'other'}, 2); equal(f.fileWrites, 2)
    f.time = f.time + 999; f.diagnostic({event = 'early'}); equal(f.fileWrites, 2)
    f.time = f.time + 1; f.diagnostic({event = 'next'}); equal(f.fileWrites, 3)
    f.time = 4294967290; f.diagnostic({event = 'wrap_before'}); equal(f.fileWrites, 4)
    f.time = f.time + 500; f.diagnostic({event = 'wrap_early'}); equal(f.fileWrites, 4)
    f.time = f.time + 500; f.diagnostic({event = 'wrap_after'}); equal(f.fileWrites, 5)
    f.event(1, 'playerDropped'); f.diagnostic({event = 'reconnected'}); equal(f.fileWrites, 6)
end)

test('diagnostic JSONL rotates at 256 KiB without retaining partial records', function()
    local f = fixture()
    for i = 1, 700 do
        f.time = f.time + 1000
        f.diagnostic({event = 'runtime', ticks = i, active = true, flight = false, playing = true,
            camera = 999, cameraActive = true, cameraRendering = true, renderingCamera = 999,
            inputPackets = i, inputAgeMs = 20, heldKeys = 3, nativeInputTicks = i,
            nativeFlightInput = true, frameTime = 0.016, keyframes = 200,
            changedPoseSegments = 199, time = i / 10, duration = 600, speed = 1,
            revision = i, stateSequence = i, targetPosition = {x = 10, y = 20, z = 30},
            nativePosition = {x = 10, y = 20, z = 30}})
    end
    local content = f.files['camera-diagnostics.jsonl']
    assert(#content <= 262144 and #content > 250000, 'rotation should retain a bounded recent tail')
    equal(content:sub(-1), '\n')
    local rows = f.diagnosticRows(); assert(#rows < 700 and #rows > 1)
    assert(rows[1].ticks > 1, 'oldest rows should be removed'); equal(rows[#rows].ticks, 700)
    for i = 2, #rows do equal(rows[i].ticks, rows[i - 1].ticks + 1, 'all retained rows are complete and ordered') end
    local complete = f.env.json.encode({event = 'retained'}) .. '\n'
    f.files['camera-diagnostics.jsonl'] = complete .. '{"partial":'
    f.time = f.time + 1000; f.diagnostic({event = 'after_partial'})
    rows = f.diagnosticRows(); equal(#rows, 2); equal(rows[1].event, 'retained'); equal(rows[2].event, 'after_partial')
    f.files['camera-diagnostics.jsonl'] = string.rep('x', 300000)
    f.time = f.time + 1000; f.diagnostic({event = 'after_bad_tail'})
    rows = f.diagnosticRows(); equal(#rows, 1); equal(rows[1].event, 'after_bad_tail')
end)

test('diagnostic failures warn once remain throttled and never break scene storage', function()
    for _, failure in ipairs({'fileReadThrows', 'fileWriteThrows', 'fileWriteFalse', 'encodeThrows'}) do
        local f = fixture(); equal(f.save('Protected').ok, true)
        local prior = f.store[f.key(1)]; f[failure] = true
        f.diagnostic({event = 'failure'}); f.time = f.time + 1000; f.diagnostic({event = 'failure_again'})
        equal(#f.warnings, 1, 'one warning per resource lifetime')
        assert(not f.warnings[1]:find('private', 1, true)); assert(not f.warnings[1]:find('license', 1, true))
        equal(f.store[f.key(1)], prior); equal(f.writes, 1)
        f[failure] = false; f.diagnostic({event = 'too_early'}); equal(f.fileWrites, 0)
        f.time = f.time + 1000; f.diagnostic({event = 'recovered'}); equal(f.fileWrites, 1)
        equal(f.request(1, 'load', {name = 'Protected'}).ok, true)
        equal(f.save('After recovery').ok, true); equal(#f.warnings, 1)
    end
    local f = fixture(); f.fileWriteResult = 1
    f.diagnostic({event = 'native_bool'}); equal(f.fileWrites, 1); equal(#f.warnings, 0)
end)

test('missing director workspace is a normal open with no writes', function()
    local f = fixture(); f.useRealDirector()
    local context, granted = f.openContext()
    equal(granted, true); equal(context.workspace, nil); equal(context.workspaceError, nil)
    equal(f.writes, 0); equal(f.deletes, 0)
end)

test('director workspace persists canonically across reopening reconnect and resource reload', function()
    local f = fixture(); local director = f.useRealDirector()
    local raw = f.workspaceValue(); raw.camera.pos.x = 1234.5; raw.settings.stabilization = 'strong'
    raw.scene.frames = {f.env.FC.Core.defaultFrame(), f.env.FC.Core.defaultFrame()}
    raw.time = 1.5
    local canonical = assert(director.validateWorkspace(raw))
    equal(f.workspaceRequest('workspaceSave', raw).ok, true); equal(f.writes, 1)
    local saved = f.store[f.workspaceKey()]; assert(saved)
    local context = f.openContext(); equal(signature(context.workspace), signature(canonical))
    raw.camera.pos.x = -99; equal(f.openContext().workspace.camera.pos.x, 1234.5)
    f.event(1, 'playerDropped'); f.identifiers[7] = f.identifiers[1]; f.acl[7] = true
    equal(f.openContext(7).workspace.camera.pos.x, 1234.5)
    assert(loadfile(serverPath, 't', f.env))()
    equal(f.openContext(7).workspace.time, 1.5)
    equal(f.openContext(7).workspace.settings.stabilization, 'strong', 'flight preference survives reconnect and resource reload')
    equal(f.store[f.workspaceKey()], saved); equal(f.writes, 1)
end)

test('legacy workspace gains direct flight and invalid stabilization cannot replace it', function()
    local f = fixture(); f.useRealDirector()
    local old = f.workspaceValue(); old.settings.stabilization = nil
    f.store[f.workspaceKey()] = f.env.json.encode(old)
    equal(f.openContext().workspace.settings.stabilization, 'off')
    local preserved = f.store[f.workspaceKey()]
    local invalid = f.workspaceValue(); invalid.settings.stabilization = 'unbounded'
    equal(f.workspaceRequest('workspaceSave', invalid).ok, false)
    equal(f.store[f.workspaceKey()], preserved, 'invalid smoothing level leaves old workspace untouched')
    old.settings.stabilization = 'medium'
    equal(f.workspaceRequest('workspaceSave', old).ok, true)
    equal(f.openContext().workspace.settings.stabilization, 'medium')
end)

test('director workspace identity and scene library stay isolated on save and reset', function()
    local f = fixture(); f.useRealDirector()
    equal(f.save('Saved scene', {version = 1, frames = {}}).ok, true)
    local library = f.store[f.key(1)]
    local first, second = f.workspaceValue(), f.workspaceValue(); second.camera.pos.x = 500
    equal(f.workspaceRequest('workspaceSave', first).ok, true)
    equal(f.workspaceRequest('workspaceSave', second, 2).ok, true)
    equal(f.openContext(1).workspace.camera.pos.x, 100)
    equal(f.openContext(2).workspace.camera.pos.x, 500)
    local other = f.store[f.workspaceKey(2)]
    equal(f.workspaceRequest('workspaceReset').ok, true)
    equal(f.store[f.workspaceKey(1)], nil); equal(f.store[f.workspaceKey(2)], other)
    equal(f.store[f.key(1)], library); equal(f.deletes, 1)
    local context = f.openContext(); equal(context.workspace, nil); equal(context.workspaceError, nil)
end)

test('workspace permission is checked on every read save and explicit reset', function()
    local f = fixture(); f.useRealDirector(); local value = f.workspaceValue()
    equal(f.workspaceRequest('workspaceSave', value).ok, true)
    local prior, reads = f.store[f.workspaceKey()], f.kvpReads
    for _, denied in ipairs({false, 0, 2, 'true'}) do
        f.acl[1] = denied
        local context, granted = f.openContext(); equal(granted, false); equal(context.workspace, nil)
        for _, event in ipairs({'workspaceSave', 'workspaceReset'}) do
            local result = f.workspaceRequest(event, value)
            equal(result.ok, false); assert(result.error:find('ACE', 1, true))
        end
    end
    equal(f.kvpReads, reads); equal(f.store[f.workspaceKey()], prior); equal(f.deletes, 0)
    f.acl[1] = 1; equal(f.workspaceRequest('workspaceSave', value).ok, true)
    local public = fixture({RequireAce = false}); public.useRealDirector(); public.acl[1] = false
    equal(public.workspaceRequest('workspaceSave', public.workspaceValue()).ok, true)
end)

test('workspace requires stable identity and ignores untrusted ownership fields', function()
    local f = fixture(); f.useRealDirector(); local raw = f.workspaceValue()
    for _, identifier in ipairs({'', 'license:123', 'license:../other', 'ip:127.0.0.1'}) do
        f.identifiers[1] = identifier
        local context, granted = f.openContext(); equal(granted, true)
        equal(context.workspace, nil); assert(context.workspaceError:find('profile', 1, true))
        equal(f.workspaceRequest('workspaceSave', raw).ok, false)
        equal(f.workspaceRequest('workspaceReset').ok, false)
    end
    f.identifiers[1] = nil; equal(f.workspaceRequest('workspaceSave', raw).ok, false)
    f.identifiers[1] = 'license:aaaaaaaa'; raw.identifier = 'license:bbbbbbbb'
    equal(f.workspaceRequest('workspaceSave', raw).ok, false)
    equal(f.writes, 0); equal(f.deletes, 0)
end)

test('workspace rejects invalid requests and non-player sources without reflecting them', function()
    local f = fixture(); f.useRealDirector(); local value = f.workspaceValue()
    for _, id in ipairs({{}, true, '', string.rep('x', 65), '../x', -1, 1.5, math.huge, 2147483648}) do
        equal(f.workspaceRequest('workspaceSave', value, 1, id), nil)
        equal(f.workspaceRequest('workspaceReset', nil, 1, id), nil)
    end
    for _, player in ipairs({0, -1, 1.5, math.huge, 0 / 0, 'bad'}) do
        f.event(player, 'arbat16_camera:workspaceSave', 'valid', value)
        f.event(player, 'arbat16_camera:workspaceReset', 'valid')
        f.event(player, 'arbat16_camera:requestOpen')
    end
    equal(#f.sent, 0); equal(f.kvpReads, 0); equal(f.writes, 0); equal(f.deletes, 0)
    equal(f.workspaceRequest('workspaceSave', value, 1, 0).ok, true)
    equal(f.workspaceRequest('workspaceReset', nil, 1, 2147483647).ok, true)
end)

test('corrupt director workspace is preserved on open and save until explicit reset', function()
    for _, saved in ipairs({'', 'broken-json', 'invalid-schema'}) do
        local f = fixture(); f.useRealDirector()
        if saved == 'invalid-schema' then f.jsonDocuments[saved] = {version = 99} end
        f.store[f.workspaceKey()] = saved
        local context = f.openContext(); equal(context.workspace, nil)
        assert(context.workspaceError:find('preserved', 1, true))
        local result = f.workspaceRequest('workspaceSave', f.workspaceValue())
        equal(result.ok, false); assert(result.error:find('preserved', 1, true))
        equal(f.store[f.workspaceKey()], saved); equal(f.writes, 0)
        equal(f.workspaceRequest('workspaceReset').ok, true)
        equal(f.workspaceRequest('workspaceSave', f.workspaceValue()).ok, true)
        equal(f.openContext().workspace.camera.pos.x, 100)
    end
end)

test('workspace accepts large saved documents but rejects more than 8 MiB before JSON decode', function()
    local f = fixture(); f.useRealDirector(); local raw = f.workspaceValue()
    local encoded = f.env.json.encode(raw)
    local large = encoded .. string.rep(' ', 700000 - #encoded)
    f.jsonDocuments[large] = clone(raw); f.store[f.workspaceKey()] = large
    equal(f.openContext().workspace.camera.pos.z, 300); equal(f.writes, 0)
    f.store[f.workspaceKey()] = string.rep('x', 8388609)
    local calls = f.decodeCalls
    local context = f.openContext(); assert(context.workspaceError); equal(context.workspace, nil)
    equal(f.decodeCalls, calls, 'oversized KVP rejected before JSON decode')
    equal(f.workspaceRequest('workspaceSave', raw).ok, false); equal(f.decodeCalls, calls)
    equal(#f.store[f.workspaceKey()], 8388609); equal(f.writes, 0)
end)

test('workspace preserves maximum camera preset and timeline collections together', function()
    local f = fixture(); local director = f.useRealDirector(); local raw = f.workspaceValue()
    raw.scene.director = director.defaults()
    for i = 1, 200 do
        local frame = f.env.FC.Core.defaultFrame({x = i, y = -i, z = 10})
        frame.label = string.rep('f', 160); frame.duration = 1
        frame.handleIn, frame.handleOut = {x = 1, y = 2, z = 3}, {x = 3, y = 2, z = 1}
        raw.scene.frames[i] = frame
    end
    for i = 1, 100 do
        raw.cameras[i] = {id = 'camera_' .. i, name = string.rep('c', 64),
            frame = clone(raw.scene.frames[i]), director = director.defaults()}
    end
    for i = 1, 40 do
        raw.presets[i] = {id = 'preset_' .. i, name = string.rep('p', 64),
            director = director.defaults(), fov = 45, focus = 100}
    end
    raw.time = 199
    equal(f.workspaceRequest('workspaceSave', raw).ok, true)
    local restored = f.openContext().workspace
    equal(#restored.scene.frames, 200); equal(#restored.cameras, 100); equal(#restored.presets, 40)
    equal(restored.cameras[100].frame.pos.x, 100); equal(restored.time, 199)
    equal(restored.scene.frames[200].handleIn.y, 2)
end)

test('workspace structural bounds reject unsafe data before JSON encoding', function()
    local f = fixture(); f.useRealDirector()
    local cyclic = f.workspaceValue(); cyclic.self = cyclic
    local deep = f.workspaceValue(); local child = deep
    for _ = 1, 15 do child.child = {}; child = child.child end
    local wide = f.workspaceValue(); for i = 1, 70000 do wide['field' .. i] = true end
    local huge = f.workspaceValue(); huge.padding = string.rep('x', 8388609)
    local escaped = f.workspaceValue(); escaped.padding = string.rep('\0', 1500000)
    local meta = f.workspaceValue(); meta.camera = setmetatable({}, {__index = function() error('must not run') end})
    local infinity = f.workspaceValue(); infinity.camera.pos.x = math.huge
    local callable = f.workspaceValue(); callable.unknown = function() end
    for _, value in ipairs({cyclic, deep, wide, huge, escaped, meta, infinity, callable}) do
        local calls = f.encodeCalls
        equal(f.workspaceRequest('workspaceSave', value).ok, false)
        equal(f.encodeCalls, calls, 'unsafe structure must not enter encoder')
    end
    equal(f.writes, 0)
end)

test('workspace validation and encoding failures preserve existing state with private exceptions hidden', function()
    local f = fixture(); f.useRealDirector(); local good = f.workspaceValue()
    equal(f.workspaceRequest('workspaceSave', good).ok, true)
    local prior = f.store[f.workspaceKey()]
    local invalid = f.workspaceValue(); invalid.camera.fov = 999
    equal(f.workspaceRequest('workspaceSave', invalid).ok, false)
    local validate = f.env.FC.Director.validateWorkspace
    f.env.FC.Director.validateWorkspace = function() error('private license:aaaaaaaa') end
    local result = f.workspaceRequest('workspaceSave', good)
    equal(result.ok, false); assert(not result.error:find('license', 1, true))
    f.env.FC.Director.validateWorkspace = validate
    for _, failure in ipairs({'encodeThrows', 'workspaceEncodeTooLarge', 'readThrows', 'writeThrows', 'writeFalse'}) do
        f[failure] = true; result = f.workspaceRequest('workspaceSave', good)
        equal(result.ok, false); assert(not result.error:find('license', 1, true))
        f[failure] = false; equal(f.store[f.workspaceKey()], prior)
    end
    equal(f.writes, 1)
end)

test('workspace throttle is independent per player enforces minimum and clears after disconnect', function()
    local f = fixture({WorkspaceCooldown = 0}); f.useRealDirector(); local raw = f.workspaceValue()
    equal(f.workspaceRequest('workspaceSave', raw, 1, nil, false).ok, true)
    equal(f.request(1, 'list', nil, nil, false).ok, true)
    f.diagnostic({event = 'workspace'}); equal(f.fileWrites, 1)
    equal(f.workspaceRequest('workspaceSave', raw, 1, nil, false).ok, false)
    equal(f.workspaceRequest('workspaceSave', raw, 2, nil, false).ok, true)
    f.time = f.time + 499; equal(f.workspaceRequest('workspaceReset', nil, 1, nil, false).ok, false)
    f.time = f.time + 1; equal(f.workspaceRequest('workspaceSave', raw, 1, nil, false).ok, true)
    f.time = 4294967290; equal(f.workspaceRequest('workspaceSave', raw, 1, nil, false).ok, true)
    f.time = f.time + 499; equal(f.workspaceRequest('workspaceSave', raw, 1, nil, false).ok, false)
    f.time = f.time + 1; equal(f.workspaceRequest('workspaceSave', raw, 1, nil, false).ok, true)
    f.event(1, 'playerDropped'); equal(f.workspaceRequest('workspaceReset', nil, 1, nil, false).ok, true)
end)

test('workspace reset failures never delete scenes or report success', function()
    local f = fixture(); f.useRealDirector(); equal(f.workspaceRequest('workspaceSave', f.workspaceValue()).ok, true)
    equal(f.save('Protected', {frames = {}}).ok, true)
    local prior, library = f.store[f.workspaceKey()], f.store[f.key(1)]
    for _, failure in ipairs({'deleteThrows', 'deleteFalse'}) do
        f[failure] = true
        local result = f.workspaceRequest('workspaceReset'); equal(result.ok, false)
        assert(not result.error:find('license', 1, true)); f[failure] = false
        equal(f.store[f.workspaceKey()], prior); equal(f.store[f.key(1)], library)
    end
    equal(f.deletes, 0); equal(f.workspaceRequest('workspaceReset').ok, true)
    equal(f.deletes, 1); equal(f.store[f.key(1)], library)
end)

test('dense recordings survive workspace reconnect and named scene storage at full sample capacity', function()
    local f = fixture({MaxSceneBytes = 4194304}); f.useRealDirector()
    local raw = f.workspaceValue()
    for clip = 1, 2 do
        local frame = f.env.FC.Core.defaultFrame({x = 0, y = 0, z = 5})
        frame.id = 'take_' .. clip; frame.duration = 300
        frame.take = {duration = 300, samples = {}}
        for i = 0, 9000 do
            frame.take.samples[i + 1] = {i / 30, i < 4500 and 0 or 10, 0, 5, 0, 0, 0, 50, 10, 12, 0, (GetConvar and GetConvar('gamename','gta5')=='gta5' and 'CLEAR' or 'SUNNY')}
        end
        raw.scene.frames[clip] = frame
    end
    local result = f.workspaceRequest('workspaceSave', raw)
    assert(result.ok, result.error)
    local restored = f.openContext().workspace
    equal(#restored.scene.frames[2].take.samples, 9001)
    equal(restored.scene.frames[1].take.samples[4500][2], 0)
    equal(restored.scene.frames[1].take.samples[4501][2], 10)
    result = f.save('Long take', raw.scene); assert(result.ok, result.error)
    local loaded = f.request(1, 'load', {name = 'Long take'})
    equal(loaded.scene.frames[2].take.duration, 300)
    local prior = f.store[f.workspaceKey()]
    raw.scene.frames[2].take.samples[9002] = clone(raw.scene.frames[2].take.samples[9001])
    equal(f.workspaceRequest('workspaceSave', raw).ok, false)
    equal(f.store[f.workspaceKey()], prior)
end)

test('bulk restores use latent transport while small replies remain ordinary events', function()
    local f = fixture(); f.useRealDirector(); local latent = {}
    function f.env.TriggerLatentClientEvent(event, player, bps, ...)
        equal(bps, 1048576); latent[#latent + 1] = event
        f.env.TriggerClientEvent(event, player, ...)
    end
    f.openContext(); equal(#latent, 0)
    equal(f.workspaceRequest('workspaceSave', f.workspaceValue()).ok, true)
    f.openContext(); equal(latent[1], 'arbat16_camera:openAllowed')
    equal(f.save('Empty', {frames = {}}).ok, true)
    f.request(1, 'load', {name = 'Empty'})
    equal(latent[2], 'arbat16_camera:storageResult'); equal(#latent, 2)
end)

print(('arbat16_camera server: %d contract checks passed'):format(checks))
