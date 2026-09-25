-- Pure Lua scene validation and sampling. No game natives are used here.
FC = FC or {}
FC.Core = {}
local C = FC.Core

local floor, min, max = math.floor, math.min, math.max
local sequence = 0
local MAX_FRAMES, MAX_DURATION = 200, 3600
C.MAX_TAKE_SAMPLES, C.MAX_SCENE_SAMPLES = 9001, 18002

function C.finite(value)
    return type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge
end

function C.clamp(value, lower, upper)
    if not C.finite(value) then return lower end
    return max(lower, min(upper, value))
end

function C.copy(value, seen)
    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[C.copy(key, seen)] = C.copy(item, seen) end
    return result
end

local easingFunctions = {
    linear = function(t) return t end,
    smooth = function(t) return t * t * (3 - 2 * t) end,
    easeIn = function(t) return t * t * t end,
    easeOut = function(t) return 1 - (1 - t) ^ 3 end,
    easeInOut = function(t)
        if t < 0.5 then return 4 * t * t * t end
        return 1 - ((-2 * t + 2) ^ 3) / 2
    end,
    smoother = function(t) return t * t * t * (t * (6 * t - 15) + 10) end
}

function C.easing(name, progress)
    return (easingFunctions[name] or easingFunctions.linear)(C.clamp(progress, 0, 1))
end

local function defaultVector(value)
    -- Cfx vectors have their own Lua type; convert them to persistable plain tables.
    local kind = type(value)
    value = (kind == 'table' or kind == 'vector3' or kind == 'vector4') and value or {}
    return { x = C.finite(value.x) and value.x or 0, y = C.finite(value.y) and value.y or 0,
        z = C.finite(value.z) and value.z or 0 }
end

function C.defaultFrame(pos, rot)
    sequence = sequence + 1
    return {
        id = ('frame_%06d'):format(sequence), label = ('Camera %02d'):format(sequence),
        pos = defaultVector(pos), rot = defaultVector(rot), fov = 50,
        duration = 3, easing = 'smooth', transition = 'smooth', weather = 'SUNNY',
        hour = 12, minute = 0, dof = { enabled = false, focus = 10, near = 1, far = 100, strength = 0.5 }
    }
end

local function fail(path, message) return nil, path .. ': ' .. message end

local function object(value, fields, path)
    if type(value) ~= 'table' or getmetatable(value) ~= nil then
        return fail(path, 'expected a plain table')
    end
    for key in pairs(value) do
        if type(key) ~= 'string' or not fields[key] then return fail(path, 'unknown field') end
    end
    return true
end

local function number(value, fallback, lower, upper, path, integer)
    if value == nil then value = fallback end
    if not C.finite(value) or value < lower or value > upper or (integer and value ~= floor(value)) then
        return fail(path, ('expected %s in [%s, %s]'):format(integer and 'an integer' or 'a finite number', lower, upper))
    end
    return value
end

local function stringValue(value, fallback, limit, path, pattern)
    if value == nil then value = fallback end
    if type(value) ~= 'string' or #value == 0 or #value > limit or value:find('[%z\1-\31\127]') then
        return fail(path, 'expected nonempty text of at most ' .. limit .. ' bytes, without control characters')
    end
    if pattern and not value:match(pattern) then return fail(path, 'invalid characters') end
    return value
end

local vectorFields = { x = true, y = true, z = true }
local function vector(value, path, bound)
    local ok, err = object(value, vectorFields, path)
    if not ok then return nil, err end
    local out = {}
    for _, axis in ipairs({ 'x', 'y', 'z' }) do
        out[axis], err = number(value[axis], nil, -bound, bound, path .. '.' .. axis)
        if out[axis] == nil then return nil, err end
    end
    return out
end

local function denseArray(value, lower, upper, path)
    if type(value) ~= 'table' or getmetatable(value) ~= nil then return fail(path, 'expected an array') end
    local count = 0
    for key in pairs(value) do
        if not C.finite(key) or key ~= floor(key) or key < 1 or key > upper then return fail(path, 'invalid array or too many entries') end
        count = count + 1
    end
    if count < lower then return fail(path, 'too few entries') end
    for i = 1, count do if value[i] == nil then return fail(path, 'array must not contain gaps') end end
    return count
end

-- Compact recording samples: t, x/y/z, pitch/roll/yaw, fov, focus, hour, minute, weather.
local function validateTake(raw, path)
    local ok, err = object(raw, {duration=true,samples=true}, path)
    if not ok then return nil, err end
    local duration; duration, err = number(raw.duration,nil,0,300,path..'.duration')
    if not duration then return nil, err end
    if duration <= 0 then return fail(path..'.duration','must be greater than zero') end
    local count; count, err = denseArray(raw.samples,2,C.MAX_TAKE_SAMPLES,path..'.samples')
    if not count then return nil, err end
    local out = {duration=duration,samples={}}
    local ranges = {{0,duration+0.0001},{-100000,100000},{-100000,100000},{-100000,100000},
        {-360000,360000},{-360000,360000},{-360000,360000},{1,130},{0.01,100000},{0,23,true},{0,59,true}}
    local previous = -1
    for i=1,count do
        local input, point, pointPath = raw.samples[i], {}, path..'.samples['..i..']'
        local columns; columns, err = denseArray(input,12,12,pointPath)
        if not columns then return nil, err end
        for column, range in ipairs(ranges) do
            point[column], err = number(input[column],nil,range[1],range[2],pointPath..'['..column..']',range[3])
            if point[column] == nil then return nil, err end
        end
        point[12], err = stringValue(input[12],nil,32,pointPath..'[12]','^[%w_]+$')
        if not point[12] then return nil, err end
        point[12] = point[12]:upper()
        if (i == 1 and point[1] ~= 0) or point[1] <= previous then return fail(pointPath..'[1]','timestamps must start at zero and increase strictly') end
        if i < count and point[1] >= duration then return fail(pointPath..'[1]','nonfinal timestamp must be below take duration') end
        previous=point[1];out.samples[i]=point
    end
    if math.abs(out.samples[count][1]-duration)>0.0001 then return fail(path..'.samples','final timestamp must match take duration') end
    out.samples[count][1]=duration
    return out
end

local sceneFields = { version = true, name = true, frames = true, loop = true, speed = true, director = true }
local frameFields = {
    id = true, label = true, pos = true, rot = true, fov = true, duration = true, easing = true,
    transition = true, weather = true, hour = true, minute = true, dof = true, handleIn = true, handleOut = true, take = true
}
local dofFields = { enabled = true, focus = true, near = true, far = true, strength = true }
local transitions = { smooth = true, linear = true, cut = true, hold = true }

function C.validateScene(raw)
    local ok, err = object(raw, sceneFields, 'scene')
    if not ok then return nil, err end
    local out = { version = 1, frames = {} }
    if raw.version ~= nil and raw.version ~= 1 then return fail('scene.version', 'unsupported version') end
    out.name, err = stringValue(raw.name, 'Untitled', 160, 'scene.name')
    if not out.name then return nil, err end
    if raw.loop ~= nil and type(raw.loop) ~= 'boolean' then return fail('scene.loop', 'expected a boolean') end
    out.loop = raw.loop == true
    out.speed, err = number(raw.speed, 1, 0.1, 8, 'scene.speed')
    if not out.speed then return nil, err end
    if raw.director ~= nil then
        if not FC.Director then return fail('scene.director', 'director module is not loaded') end
        out.director, err = FC.Director.validate(raw.director)
        if not out.director then return nil, err end
    end
    if type(raw.frames) ~= 'table' or getmetatable(raw.frames) ~= nil then return fail('scene.frames', 'expected an array') end
    local count = 0
    for key in pairs(raw.frames) do
        if not C.finite(key) or key ~= floor(key) or key < 1 or key > MAX_FRAMES then
            return fail('scene.frames', 'expected an array of at most ' .. MAX_FRAMES .. ' frames')
        end
        count = count + 1
    end
    for index = 1, count do
        if raw.frames[index] == nil then return fail('scene.frames', 'array must not contain gaps') end
    end
    local ids, total, totalSamples = {}, 0, 0
    for index = 1, count do
        local input, path = raw.frames[index], 'scene.frames[' .. index .. ']'
        ok, err = object(input, frameFields, path)
        if not ok then return nil, err end
        local frame = {}
        frame.id, err = stringValue(input.id, 'frame_' .. index, 64, path .. '.id', '^[%w_:%-]+$')
        if not frame.id then return nil, err end
        if ids[frame.id] then return fail(path .. '.id', 'duplicate frame id') end
        ids[frame.id] = true
        frame.label, err = stringValue(input.label, 'Camera ' .. index, 160, path .. '.label')
        if not frame.label then return nil, err end
        frame.pos, err = vector(input.pos, path .. '.pos', 100000)
        if not frame.pos then return nil, err end
        frame.rot, err = vector(input.rot, path .. '.rot', 360000)
        if not frame.rot then return nil, err end
        frame.fov, err = number(input.fov, 50, 1, 130, path .. '.fov')
        if not frame.fov then return nil, err end
        frame.duration, err = number(input.duration, 3, 0, 600, path .. '.duration')
        if not frame.duration then return nil, err end
        frame.easing = input.easing == nil and 'smooth' or input.easing
        if type(frame.easing) ~= 'string' or not easingFunctions[frame.easing] then return fail(path .. '.easing', 'unknown easing') end
        frame.transition = input.transition == nil and (input.take ~= nil and 'hold' or 'smooth') or input.transition
        if type(frame.transition) ~= 'string' or not transitions[frame.transition] then return fail(path .. '.transition', 'unknown transition') end
        if frame.duration == 0 and index < count and frame.transition ~= 'cut' then
            return fail(path .. '.duration', 'only cuts or the final hold may have zero duration')
        end
        frame.weather, err = stringValue(input.weather, 'SUNNY', 32, path .. '.weather', '^[%w_]+$')
        if not frame.weather then return nil, err end
        frame.weather = frame.weather:upper()
        frame.hour, err = number(input.hour, 12, 0, 23, path .. '.hour', true)
        if frame.hour == nil then return nil, err end
        frame.minute, err = number(input.minute, 0, 0, 59, path .. '.minute', true)
        if frame.minute == nil then return nil, err end
        local inputDof = input.dof == nil and {} or input.dof
        ok, err = object(inputDof, dofFields, path .. '.dof')
        if not ok then return nil, err end
        if inputDof.enabled ~= nil and type(inputDof.enabled) ~= 'boolean' then return fail(path .. '.dof.enabled', 'expected a boolean') end
        frame.dof = { enabled = inputDof.enabled == true }
        for _, spec in ipairs({ { 'focus', 10, 0.01, 100000 }, { 'near', 1, 0, 100000 },
                { 'far', 100, 0.01, 100000 }, { 'strength', 0.5, 0, 1 } }) do
            frame.dof[spec[1]], err = number(inputDof[spec[1]], spec[2], spec[3], spec[4], path .. '.dof.' .. spec[1])
            if frame.dof[spec[1]] == nil then return nil, err end
        end
        if frame.dof.near > frame.dof.far then return fail(path .. '.dof', 'near must not exceed far') end
        for _, handle in ipairs({ 'handleIn', 'handleOut' }) do
            if input[handle] ~= nil then
                frame[handle], err = vector(input[handle], path .. '.' .. handle, 100000)
                if not frame[handle] then return nil, err end
            end
        end
        if input.take ~= nil then
            if frame.duration <= 0 then return fail(path..'.duration','a recorded clip must have positive duration') end
            frame.take, err = validateTake(input.take,path..'.take')
            if not frame.take then return nil, err end
            totalSamples=totalSamples+#frame.take.samples
            if totalSamples>C.MAX_SCENE_SAMPLES then return fail('scene.frames','too many recorded samples') end
            -- The frame thumbnail/entry pose is always the first recorded sample.
            local start=frame.take.samples[1]
            frame.pos={x=start[2],y=start[3],z=start[4]};frame.rot={x=start[5],y=start[6],z=start[7]}
            frame.fov=start[8];frame.dof.focus=start[9]
            frame.hour,frame.minute,frame.weather=start[10],start[11],start[12]
        end
        total = total + frame.duration
        if total > MAX_DURATION then return fail('scene.frames', 'total duration exceeds 3600 seconds') end
        out.frames[index] = frame
    end
    return out
end

-- Every frame owns an interval; recorded clips sample their own dense take,
-- while an ordinary final frame owns a still hold.
-- Speed is a playback multiplier, so duration remains timeline seconds.
function C.duration(scene)
    local duration = 0
    for _, frame in ipairs(scene.frames or {}) do duration = duration + frame.duration end
    return duration
end

local function lerp(a, b, t) return a + (b - a) * t end
local function angle(a, b, t) return a + ((b - a + 180) % 360 - 180) * t end
local function catmull(a, b, c, d, t)
    return 0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t * t
        + (-a + 3 * b - 3 * c + d) * t * t * t)
end
local function bezier(a, b, c, d, t)
    local u = 1 - t
    return u * u * u * a + 3 * u * u * t * b + 3 * u * t * t * c + t * t * t * d
end

local function still(frame)
    -- Never clone thousands of recording samples into the render pose each tick.
    local result = {}
    for key,value in pairs(frame) do if key~='take' then result[key]=C.copy(value) end end
    result.timeHours = result.hour + result.minute / 60
    return result
end

local function recorded(frame, progress)
    local take, result = frame.take, still(frame)
    result._recorded = true
    local sourceTime = C.clamp(progress,0,1)*take.duration
    local samples, low, high = take.samples, 1, #take.samples
    -- Find the last sample at or before this source time in logarithmic work.
    while low < high do
        local middle=floor((low+high+1)/2)
        if samples[middle][1] <= sourceTime then low=middle else high=middle-1 end
    end
    local a, b = samples[low], samples[min(low+1,#samples)]
    local t = a==b and 0 or C.clamp((sourceTime-a[1])/(b[1]-a[1]),0,1)
    result.pos={x=lerp(a[2],b[2],t),y=lerp(a[3],b[3],t),z=lerp(a[4],b[4],t)}
    result.rot={x=angle(a[5],b[5],t),y=angle(a[6],b[6],t),z=angle(a[7],b[7],t)}
    result.fov=lerp(a[8],b[8],t);result.dof.focus=lerp(a[9],b[9],t)
    local clockA,clockB=a[10]*60+a[11],b[10]*60+b[11]
    local minutes=(clockA+((clockB-clockA+720)%1440-720)*t)%1440
    result.timeHours=minutes/60;result.hour=floor(minutes/60);result.minute=floor(minutes%60)
    result.weather=a[12]
    return result
end

function C.sample(scene, time)
    if not C.finite(time) then return nil, 'time must be a finite number' end
    if type(scene) ~= 'table' or type(scene.frames) ~= 'table' or #scene.frames == 0 then
        return nil, 'scene has no frames'
    end
    local frames, total = scene.frames, C.duration(scene)
    if scene.loop and total > 0 then time = time % total else time = C.clamp(time, 0, total) end
    local elapsed, index = 0, #frames
    for i = 1, #frames do
        if time < elapsed + frames[i].duration or i == #frames then index = i; break end
        elapsed = elapsed + frames[i].duration
    end
    local a, b = frames[index], frames[index + 1]
    local progress = C.clamp((time - elapsed) / (a.duration>0 and a.duration or 0.000001), 0, 1)
    if a.take then return recorded(a,progress), index, progress end
    if not b then return still(a), index, 1 end
    if a.transition == 'cut' then return still(b), index, progress end
    if a.transition == 'hold' then return still(a), index, progress end
    local t = C.easing(a.easing, progress)
    if t == 0 then return still(a), index, progress end
    if t == 1 then return still(b), index, progress end
    local result = still(a)
    local previous, following = frames[max(1, index - 1)], frames[min(#frames, index + 2)]
    for _, axis in ipairs({ 'x', 'y', 'z' }) do
        if a.transition == 'linear' then
            result.pos[axis] = lerp(a.pos[axis], b.pos[axis], t)
        elseif a.handleOut or b.handleIn then
            -- An omitted handle follows the straight chord at one third distance.
            local handleOut = a.handleOut and a.handleOut[axis] or (b.pos[axis] - a.pos[axis]) / 3
            local handleIn = b.handleIn and b.handleIn[axis] or (a.pos[axis] - b.pos[axis]) / 3
            result.pos[axis] = bezier(a.pos[axis], a.pos[axis] + handleOut, b.pos[axis] + handleIn, b.pos[axis], t)
        else
            result.pos[axis] = catmull(previous.pos[axis], a.pos[axis], b.pos[axis], following.pos[axis], t)
        end
        result.rot[axis] = angle(a.rot[axis], b.rot[axis], t)
    end
    result.fov = lerp(a.fov, b.fov, t)
    -- Move through midnight by the shortest interval; weather changes at each keyframe.
    local clockA, clockB = a.hour * 60 + a.minute, b.hour * 60 + b.minute
    local minutes = (clockA + ((clockB - clockA + 720) % 1440 - 720) * t) % 1440
    result.timeHours = minutes / 60
    result.hour, result.minute = floor(minutes / 60), floor(minutes % 60)
    for _, key in ipairs({ 'focus', 'near', 'far' }) do result.dof[key] = lerp(a.dof[key], b.dof[key], t) end
    result.dof.enabled = a.dof.enabled or b.dof.enabled
    result.dof.strength = lerp(a.dof.enabled and a.dof.strength or 0, b.dof.enabled and b.dof.strength or 0, t)
    return result, index, progress
end

return C
