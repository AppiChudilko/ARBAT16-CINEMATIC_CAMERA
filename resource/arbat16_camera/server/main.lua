-- Each player's entire library is replaced with one synchronous KVP write.
-- Names are display labels; no client value ever becomes a filesystem path.
local config = FCConfig or {}
local cooldowns = {}
local workspaceCooldowns = {}
local diagnosticCooldowns, diagnosticWarning = {}, false
local HARD_MAX_SCENES, HARD_MAX_FRAMES, HARD_MAX_SCENE_BYTES = 30, 200, 4194304
local MAX_WORKSPACE_BYTES = 8388608
local BULK_BYTES_PER_SECOND = 1048576

local function sendBulkClient(event, player, ...)
    if type(TriggerLatentClientEvent) == 'function' then
        TriggerLatentClientEvent(event, player, BULK_BYTES_PER_SECOND, ...)
    else
        TriggerClientEvent(event, player, ...)
    end
end

local function boundedInteger(value, fallback, minimum, maximum)
    if type(value) ~= 'number' or value ~= value then return fallback end
    return math.max(minimum, math.min(maximum, math.floor(value)))
end

local maxScenes = boundedInteger(config.MaxScenes, 30, 1, HARD_MAX_SCENES)
local maxSceneBytes = boundedInteger(config.MaxSceneBytes, 4194304, 1024, HARD_MAX_SCENE_BYTES)
local maxFrames = boundedInteger(config.MaxFrames, 200, 1, HARD_MAX_FRAMES)
local storageCooldown = boundedInteger(config.StorageCooldown, 600, 0, 60000)
local workspaceCooldown = boundedInteger(config.WorkspaceCooldown, 500, 500, 60000)
-- Configured limits apply to new saves. Existing scenes remain readable and
-- removable after an administrator tightens limits, within the format bounds.
local maxDocumentBytes = (HARD_MAX_SCENE_BYTES + 512) * HARD_MAX_SCENES + 1024

local errors = {
    denied = 'Camera access denied. An ACE permission is required.',
    identity = 'Your player profile could not be identified. Reconnect to the server.',
    cooldown = 'Requests are too frequent. Wait a moment and try again.',
    request = 'Invalid scene library request.',
    name = 'Use a name of 1 to 64 UTF-8 bytes, without control characters or slashes.',
    scene = 'The scene contains invalid settings.',
    structure = 'The scene is too large or contains unsupported data.',
    size = 'The scene exceeds the allowed file size.',
    full = 'Your scene library is full. Delete a scene before saving a new one.',
    missing = 'The saved scene could not be found.',
    storage = 'The scene library could not be read. Saved scenes have not been changed.',
    write = 'The scene library could not be updated. Try again later.',
    workspace = 'The director workspace contains invalid settings.',
    workspaceSize = 'The director workspace exceeds the allowed file size.',
    workspaceStorage = 'Your saved director workspace could not be read. It has been preserved. Reset it explicitly to enable saving.',
    workspaceWrite = 'The director workspace could not be saved. Try again later.',
    workspaceReset = 'The director workspace could not be reset. Try again later.'
}

local function allowed(player)
    if config.RequireAce == false then return true end
    local granted = IsPlayerAceAllowed(tostring(player), config.AcePermission or 'arbat16_camera.use')
    -- Normalize BOOL values explicitly: Lua treats numeric zero as truthy.
    return granted == true or granted == 1
end

-- Diagnostics are untrusted client observations, never authority for game
-- actions. Copy only this fixed schema; no identifiers or arbitrary text.
local diagnosticBooleans = {
    'active', 'flight', 'playing', 'recording', 'uiReady', 'exists',
    'cameraActive', 'cameraRendering', 'nativeFlightInput'
}
local diagnosticNumbers = {
    'camera', 'renderingCamera', 'ticks', 'tickAgeMs', 'inputPackets', 'inputAgeMs',
    'heldKeys', 'nativeInputTicks', 'frameTime', 'keyframes', 'changedPoseSegments',
    'time', 'duration', 'speed', 'revision', 'stateSequence'
}
local DIAGNOSTIC_FILE, DIAGNOSTIC_MAX_BYTES = 'camera-diagnostics.jsonl', 262144

local function diagnosticNumber(value, bound)
    return type(value) == 'number' and value == value and value >= -bound and value <= bound
end

local function diagnosticPayload(raw)
    if type(raw) ~= 'table' or getmetatable(raw) ~= nil then return nil end
    if type(raw.event) ~= 'string' or #raw.event < 1 or #raw.event > 32
        or not raw.event:match('^[A-Za-z0-9_.:%-]+$') then return nil end
    local report = {event = raw.event}
    for _, key in ipairs(diagnosticBooleans) do
        if type(raw[key]) == 'boolean' then report[key] = raw[key] end
    end
    for _, key in ipairs(diagnosticNumbers) do
        if diagnosticNumber(raw[key], 1000000000000) then report[key] = raw[key] end
    end
    for _, key in ipairs({'targetPosition', 'nativePosition'}) do
        local value = raw[key]
        if type(value) == 'table' and getmetatable(value) == nil
            and diagnosticNumber(value.x, 1000000) and diagnosticNumber(value.y, 1000000)
            and diagnosticNumber(value.z, 1000000) then
            report[key] = {x = value.x, y = value.y, z = value.z}
        end
    end
    return report
end

local function diagnosticWarnOnce()
    if diagnosticWarning then return end
    diagnosticWarning = true
    pcall(print, '[arbat16_camera] Camera diagnostics could not be written. Camera controls and scene storage are unaffected.')
end

local function appendDiagnostic(report)
    local encoded = json.encode(report)
    -- Every record occupies exactly one complete JSONL line.
    if type(encoded) ~= 'string' or #encoded > 4095 or encoded:find('[\r\n]') then
        error('invalid diagnostic encoding')
    end
    local line = encoded .. '\n'
    local resource = GetCurrentResourceName()
    local previous = LoadResourceFile(resource, DIAGNOSTIC_FILE)
    if previous == nil then previous = '' end
    if type(previous) ~= 'string' then error('invalid diagnostic file') end
    local budget = DIAGNOSTIC_MAX_BYTES - #line
    local start = math.max(1, #previous - budget + 1)
    if start > 1 and previous:sub(start - 1, start - 1) ~= '\n' then
        local boundary = previous:find('\n', start, true)
        start = boundary and boundary + 1 or #previous + 1
    end
    local tail = previous:sub(start)
    -- A partial final record from an interrupted write is not carried forward.
    local lastNewline = tail:match('^.*()\n')
    tail = lastNewline and tail:sub(1, lastNewline) or ''
    local content = tail .. line
    local saved = SaveResourceFile(resource, DIAGNOSTIC_FILE, content, #content)
    if saved ~= true and saved ~= 1 then error('diagnostic write failed') end
end

RegisterNetEvent('arbat16_camera:diagnostic', function(raw)
    -- Keep logging failures isolated from all camera/storage event handlers.
    local ok = pcall(function()
        local player = tonumber(source)
        if config.Diagnostics == false or not diagnosticNumber(player, 2147483647)
            or player <= 0 or player % 1 ~= 0 or not allowed(player) then return end
        local tick = GetGameTimer()
        local previous = diagnosticCooldowns[player]
        if previous and (tick - previous) % 4294967296 < 1000 then return end
        local report = diagnosticPayload(raw)
        if not report then return end
        diagnosticCooldowns[player] = tick
        report.source = player
        report.receivedAt = os.date('!%Y-%m-%dT%H:%M:%SZ')
        report.origin = 'client_report'
        appendDiagnostic(report)
    end)
    if not ok then diagnosticWarnOnce() end
end)

local function requestIdIsValid(id)
    if type(id) == 'number' then
        return id == id and id >= 0 and id <= 2147483647 and id % 1 == 0
    end
    return type(id) == 'string' and #id >= 1 and #id <= 64 and id:match('^[%w_:%-]+$') ~= nil
end

local function safeName(raw)
    if type(raw) ~= 'string' or #raw > 64 then return nil end
    if not utf8.len(raw) then return nil end
    for _, code in utf8.codes(raw) do
        if code < 32 or (code >= 127 and code <= 159) then return nil end
    end
    local name = raw:match('^%s*(.-)%s*$')
    if name == '' or name == '.' or name == '..' or name:find('[/\\]') then return nil end
    return name
end

local function playerKey(player)
    -- A source ID is temporary and must never own a saved library.
    local identifier = GetPlayerIdentifierByType(player, 'license')
    if type(identifier) ~= 'string' or #identifier > 136 then return nil end
    local license = identifier:match('^license:([%x]+)$')
    if not license or #license < 8 then return nil end
    return 'arbat16_camera:v1:license:' .. license:lower()
end

local function workspaceKey(player)
    local key = playerKey(player)
    return key and key:gsub('^arbat16_camera:v1:', 'arbat16_camera:workspace:v1:')
end

-- Reject cycles, excessive depth/width, non-JSON data, and oversized strings
-- before entering json.encode or the shared scene validator.
local function boundedScene(raw, byteLimit, frameLimit, includeJsonOverhead)
    local seen, bytes, nodes = {}, 0, 0
    local maxNodes = frameLimit * 80 + 512 + 18002 * 26
    local function visit(value, depth, isKey)
        nodes = nodes + 1
        if nodes > maxNodes or depth > 12 then return false end
        local kind = type(value)
        if kind == 'string' then
            bytes = bytes + #value
            if includeJsonOverhead then
                -- Reserve the longest JSON escape for every escaped byte.
                -- This keeps hostile strings below the budget before encoding.
                local _, escaped = value:gsub('[%z\1-\31\\"]', '')
                bytes = bytes + 2 + escaped * 5
            end
        elseif kind == 'number' then
            if value ~= value or value == math.huge or value == -math.huge then return false end
            -- Dense recordings use JSON arrays: numeric indices consume no
            -- encoded bytes. Values still reserve a full numeric JSON token.
            bytes = bytes + (isKey and 0 or (includeJsonOverhead and 32 or 8))
        elseif kind == 'boolean' or kind == 'nil' then
            bytes = bytes + (includeJsonOverhead and 5 or 4)
        elseif kind == 'table' then
            if seen[value] or getmetatable(value) ~= nil then return false end
            seen[value] = true
            if includeJsonOverhead then bytes = bytes + 2 end
            local entries = 0
            for key, child in pairs(value) do
                entries = entries + 1
                if entries > 9001 then return false end
                if type(key) ~= 'string' and (type(key) ~= 'number' or key % 1 ~= 0) then return false end
                if includeJsonOverhead then bytes = bytes + 2 end
                if not visit(key, depth + 1, true) or not visit(child, depth + 1) then return false end
            end
            seen[value] = nil
        else
            return false
        end
        return bytes <= byteLimit
    end
    return type(raw) == 'table' and visit(raw, 0)
end

local function validateScene(raw, name, byteLimit, frameLimit)
    byteLimit, frameLimit = byteLimit or maxSceneBytes, frameLimit or maxFrames
    if not boundedScene(raw, byteLimit, frameLimit) then return nil, errors.structure end
    local encodedOk, encoded = pcall(json.encode, raw)
    if not encodedOk or type(encoded) ~= 'string' then return nil, errors.scene end
    if #encoded > byteLimit then return nil, errors.size end
    local valid, scene, detail = pcall(FC.Core.validateScene, raw)
    if not valid then return nil, errors.scene end
    if type(scene) ~= 'table' then
        return nil, type(detail) == 'string' and ('Invalid scene: ' .. detail:sub(1, 240)) or errors.scene
    end
    if type(scene.frames) ~= 'table' then return nil, errors.scene end
    if #scene.frames > frameLimit then return nil, ('The scene exceeds the limit of %d keyframes.'):format(frameLimit) end
    -- Align newly saved metadata with its library label. Reads do not rename or
    -- rewrite existing scenes, including scenes created by earlier versions.
    if name then scene.name = name end
    local canonicalOk, canonical = pcall(json.encode, scene)
    if not canonicalOk or type(canonical) ~= 'string' then return nil, errors.scene end
    if #canonical > byteLimit then return nil, errors.size end
    return scene
end

local function readDocument(key)
    local ok, raw = pcall(GetResourceKvpString, key)
    if not ok then return nil end
    if raw == nil then return {version = 1, scenes = {}} end
    if type(raw) ~= 'string' or #raw > maxDocumentBytes then return nil end
    local decoded, document = pcall(json.decode, raw)
    if not decoded or type(document) ~= 'table' or document.version ~= 1 or type(document.scenes) ~= 'table' then return nil end
    local clean, count = {version = 1, scenes = {}}, 0
    for name, entry in pairs(document.scenes) do
        count = count + 1
        if count > HARD_MAX_SCENES or safeName(name) ~= name or type(entry) ~= 'table' then return nil end
        local scene = validateScene(entry.scene, nil, HARD_MAX_SCENE_BYTES, HARD_MAX_FRAMES)
        if not scene or type(entry.updated) ~= 'number' or entry.updated ~= entry.updated
            or entry.updated < 0 or entry.updated > 9007199254740991 or entry.updated % 1 ~= 0 then return nil end
        clean.scenes[name] = {scene = scene, updated = entry.updated}
    end
    return clean
end

local function sceneItems(document)
    local items = {}
    for name, entry in pairs(document.scenes) do
        local scene = entry.scene
        items[#items + 1] = {name = name, frames = #scene.frames,
            duration = FC.Core.duration(scene), updated = entry.updated}
    end
    table.sort(items, function(a, b)
        if a.updated == b.updated then return a.name < b.name end
        return a.updated > b.updated
    end)
    return items
end

local function writeDocument(key, document)
    local ok, raw = pcall(json.encode, document)
    if not ok or type(raw) ~= 'string' or #raw > maxDocumentBytes then return false end
    local written, result = pcall(SetResourceKvp, key, raw)
    return written and result ~= false
end

-- Workspace storage is independent of the named scene library. All incoming
-- structures are bounded before validation/encoding, including unknown fields.
-- Existing invalid documents remain untouched until an explicit reset request.
local function validateWorkspace(raw)
    if not boundedScene(raw, MAX_WORKSPACE_BYTES, HARD_MAX_FRAMES * 4, true) then
        return nil, errors.workspaceSize
    end
    local rawOk, rawEncoded = pcall(json.encode, raw)
    if not rawOk or type(rawEncoded) ~= 'string' then return nil, errors.workspace end
    if #rawEncoded > MAX_WORKSPACE_BYTES then return nil, errors.workspaceSize end
    local valid, workspace = pcall(function() return FC.Director.validateWorkspace(raw) end)
    if not valid or type(workspace) ~= 'table'
        or not boundedScene(workspace, MAX_WORKSPACE_BYTES, HARD_MAX_FRAMES * 4, true) then
        return nil, errors.workspace
    end
    local encodedOk, encoded = pcall(json.encode, workspace)
    if not encodedOk or type(encoded) ~= 'string' then return nil, errors.workspace end
    if #encoded > MAX_WORKSPACE_BYTES then return nil, errors.workspaceSize end
    return workspace, nil, encoded
end

local function readWorkspace(key)
    local ok, raw = pcall(GetResourceKvpString, key)
    if not ok then return nil, errors.workspaceStorage end
    if raw == nil then return nil end
    if type(raw) ~= 'string' or #raw == 0 or #raw > MAX_WORKSPACE_BYTES then
        return nil, errors.workspaceStorage
    end
    local decoded, value = pcall(json.decode, raw)
    if not decoded then return nil, errors.workspaceStorage end
    local workspace = validateWorkspace(value)
    if not workspace then return nil, errors.workspaceStorage end
    return workspace
end

local function workspaceRequest(player, requestId)
    if not diagnosticNumber(player, 2147483647) or player <= 0 or player % 1 ~= 0
        or not requestIdIsValid(requestId) then return nil end
    local function reply(result)
        TriggerClientEvent('arbat16_camera:workspaceResult', player, requestId, result)
    end
    if not allowed(player) then reply({ok = false, error = errors.denied}); return nil end
    local now, previous = GetGameTimer(), workspaceCooldowns[player]
    if previous and (now - previous) % 4294967296 < workspaceCooldown then
        reply({ok = false, error = errors.cooldown}); return nil
    end
    workspaceCooldowns[player] = now
    local key = workspaceKey(player)
    if not key then reply({ok = false, error = errors.identity}); return nil end
    return key, reply
end

RegisterNetEvent('arbat16_camera:requestOpen', function()
    local player = tonumber(source)
    if not diagnosticNumber(player, 2147483647) or player <= 0 or player % 1 ~= 0 then return end
    local granted, context = allowed(player) == true, {}
    if granted then
        local key = workspaceKey(player)
        if key then
            context.workspace, context.workspaceError = readWorkspace(key)
        else
            context.workspaceError = errors.identity
        end
    end
    if context.workspace then
        sendBulkClient('arbat16_camera:openAllowed', player, granted, context)
    else
        TriggerClientEvent('arbat16_camera:openAllowed', player, granted, context)
    end
end)

RegisterNetEvent('arbat16_camera:workspaceSave', function(requestId, raw)
    local key, reply = workspaceRequest(tonumber(source), requestId)
    if not key then return end
    local _, readError = readWorkspace(key)
    if readError then return reply({ok = false, error = readError}) end
    local workspace, validationError, encoded = validateWorkspace(raw)
    if not workspace then return reply({ok = false, error = validationError}) end
    local written, result = pcall(SetResourceKvp, key, encoded)
    if not written or result == false then return reply({ok = false, error = errors.workspaceWrite}) end
    reply({ok = true})
end)

RegisterNetEvent('arbat16_camera:workspaceReset', function(requestId)
    local key, reply = workspaceRequest(tonumber(source), requestId)
    if not key then return end
    local deleted, result = pcall(DeleteResourceKvp, key)
    if not deleted or result == false then return reply({ok = false, error = errors.workspaceReset}) end
    reply({ok = true})
end)

RegisterNetEvent('arbat16_camera:storage', function(requestId, operation, payload)
    local player = tonumber(source)
    if not player or player <= 0 or not requestIdIsValid(requestId) then return end
    local function reply(result)
        if result.scene then
            sendBulkClient('arbat16_camera:storageResult', player, requestId, result)
        else
            TriggerClientEvent('arbat16_camera:storageResult', player, requestId, result)
        end
    end
    local function fail(message) reply({ok = false, error = message}) end
    if not allowed(player) then return fail(errors.denied) end
    local now = GetGameTimer()
    local previous = cooldowns[player]
    if previous and (now - previous) % 4294967296 < storageCooldown then return fail(errors.cooldown) end
    cooldowns[player] = now
    if operation ~= 'list' and operation ~= 'save' and operation ~= 'load' and operation ~= 'delete' then
        return fail(errors.request)
    end
    local key = playerKey(player)
    if not key then return fail(errors.identity) end
    local name, scene
    if operation ~= 'list' then
        if type(payload) ~= 'table' then return fail(errors.request) end
        name = safeName(payload.name)
        if not name then return fail(errors.name) end
        if operation == 'save' then
            local reason
            scene, reason = validateScene(payload.scene, name)
            if not scene then return fail(reason) end
        end
    end
    local document = readDocument(key)
    if not document then return fail(errors.storage) end
    if operation == 'list' then return reply({ok = true, items = sceneItems(document)}) end
    if operation == 'load' then
        if not document.scenes[name] then return fail(errors.missing) end
        return reply({ok = true, name = name, scene = document.scenes[name].scene})
    end
    if operation == 'delete' then
        if not document.scenes[name] then return fail(errors.missing) end
        document.scenes[name] = nil
    else
        if not document.scenes[name] then
            local count = 0
            for _ in pairs(document.scenes) do count = count + 1 end
            if count >= maxScenes then return fail(errors.full) end
        end
        document.scenes[name] = {scene = scene, updated = os.time()}
    end
    if not writeDocument(key, document) then return fail(errors.write) end
    reply({ok = true, name = name, items = sceneItems(document)})
end)

AddEventHandler('playerDropped', function()
    local player = tonumber(source)
    if player then
        cooldowns[player] = nil; workspaceCooldowns[player] = nil; diagnosticCooldowns[player] = nil
    end
end)
