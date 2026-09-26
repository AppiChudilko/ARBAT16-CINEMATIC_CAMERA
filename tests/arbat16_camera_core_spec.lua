-- Run from the redm workspace: lua tests/arbat16_camera_core_spec.lua
-- Also runs without a Lua executable through Python's embedded lupa runtime.
local C = dofile('resource/arbat16_camera/shared/core.lua')
local count = 0
local function equal(actual, expected, message)
    count = count + 1
    assert(actual == expected, (message or 'values differ') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
end
local function close(actual, expected, message)
    count = count + 1
    assert(math.abs(actual - expected) < 0.000001, (message or 'values differ') .. ': expected ' .. expected .. ', got ' .. tostring(actual))
end
local function scene()
    local a = C.defaultFrame({ x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 350 })
    local b = C.defaultFrame({ x = 10, y = 0, z = 0 }, { x = 0, y = 0, z = 10 })
    a.duration, a.easing, a.transition = 2, 'linear', 'linear'
    b.duration, b.fov = 1, 70
    return { version = 1, name = 'Test', loop = false, speed = 1, frames = { a, b } }
end
local function invalid(mutator, contains)
    local value = scene()
    mutator(value)
    local result, err = C.validateScene(value)
    equal(result, nil, 'invalid scene accepted')
    equal(type(err), 'string', 'missing validation error')
    if contains then equal(err:find(contains, 1, true) ~= nil, true, err) end
end

equal(C.finite(0), true)
equal(C.finite(0 / 0), false)
equal(C.finite(math.huge), false)
equal(C.finite(-math.huge), false)
equal(C.finite('1'), false)
equal(C.clamp(0 / 0, 0, 1), 0)
local cycle = {}; cycle.self = cycle
local cycleCopy = C.copy(cycle)
equal(cycleCopy.self, cycleCopy)
equal(cycleCopy == cycle, false)

local s, err = C.validateScene(scene())
assert(s, err)
equal(C.duration(s), 3, 'terminal hold duration')
local p, segment, progress = C.sample(s, 1)
close(p.pos.x, 5)
close(p.rot.z, 360, 'shortest rotation crosses 360')
close(p.fov, 60)
equal(segment, 1)
close(progress, 0.5)
equal(C.sample(s, 0).rot.z, 350, 'exact initial angle')
equal(C.sample(s, 2).rot.z, 10, 'exact destination angle')
close(C.sample(s, -100).pos.x, 0, 'negative nonloop time clamps')
close(C.sample(s, 100).pos.x, 10, 'past end clamps')
close(C.sample(s, 2.5).pos.x, 10, 'final hold')
close(C.sample(s, 3).pos.x, 10, 'exact end')
local nanResult = C.sample(s, 0 / 0)
equal(nanResult, nil, 'NaN time rejected')
equal(C.sample(s, math.huge), nil, 'infinite time rejected')
local untouched = s.frames[1].pos.x
p.pos.x = 999
equal(s.frames[1].pos.x, untouched, 'sampling does not alias scene')
s.loop = true
close(C.sample(s, 3).pos.x, 0, 'loop endpoint wraps')
close(C.sample(s, 4).pos.x, 5, 'loop movement')
close(C.sample(s, -0.5).pos.x, 10, 'negative loop time wraps')
s = scene()
s.frames[1].transition = 'cut'
close(C.sample(s, 0).pos.x, 10, 'cut switches at interval start')
close(C.sample(s, 1).pos.x, 10)
s.frames[1].duration = 0
assert(C.validateScene(s))
close(C.sample(s, 0).pos.x, 10, 'zero duration cut')
s = scene()
s.frames[1].transition = 'hold'
close(C.sample(s, 1.99).pos.x, 0, 'hold keeps source')
close(C.sample(s, 2).pos.x, 10, 'hold changes at boundary')

for _, mode in ipairs({ 'linear', 'smooth', 'easeIn', 'easeOut', 'easeInOut', 'smoother' }) do
    close(C.easing(mode, 0), 0, mode .. ' start')
    close(C.easing(mode, 1), 1, mode .. ' end')
    local last = 0
    for i = 0, 100 do
        local current = C.easing(mode, i / 100)
        equal(current >= last - 1e-12 and current <= 1, true, mode .. ' monotonic')
        last = current
    end
end
close(C.easing('smooth', 0.5), 0.5)
close(C.easing('easeIn', 0.5), 0.125)
close(C.easing('easeOut', 0.5), 0.875)
s = scene()
s.frames[1].transition = 'smooth'
close(C.sample(s, 1).pos.x, 5, 'Catmull-Rom symmetric midpoint')
s.frames[1].handleOut = { x = 0, y = 10, z = 0 }
s.frames[2].handleIn = { x = 0, y = 10, z = 0 }
close(C.sample(s, 1).pos.x, 5, 'Bezier midpoint X')
close(C.sample(s, 1).pos.y, 7.5, 'Bezier relative handles')
close(C.sample(s, 0).pos.y, 0, 'Bezier initial endpoint')
close(C.sample(s, 2).pos.y, 0, 'Bezier final endpoint')
s.frames[1].handleOut, s.frames[2].handleIn = nil, nil
local middle = C.defaultFrame({ x = 20, y = 0, z = 0 }, { x = 0, y = 0, z = 0 })
s.frames[3] = middle
close(C.sample(s, 1).pos.x, 4.375, 'Catmull-Rom uses adjacent control point')
s = scene()
s.frames[1].hour, s.frames[2].hour = 23, 1
s.frames[1].weather, s.frames[2].weather = 'RAIN', (C.game=='gta5' and 'CLEAR' or 'SUNNY')
close(C.sample(s, 1).timeHours, 0, 'clock crosses midnight by shortest route')
equal(C.sample(s, 1).hour, 0)
equal(C.sample(s, 1).weather, 'RAIN', 'weather sticks to source keyframe')
equal(C.sample(s, 2).weather, (C.game=='gta5' and 'CLEAR' or 'SUNNY'))
s.frames[2].dof.enabled, s.frames[2].dof.focus = true, 30
p = C.sample(s, 1)
equal(p.dof.enabled, true)
close(p.dof.strength, 0.25, 'disabled DOF fades from zero')
close(p.dof.focus, 20)

invalid(function(v) v.frames[1].pos.x = math.huge end, '.pos.x')
invalid(function(v) v.frames[1].pos.x = 0 / 0 end, '.pos.x')
invalid(function(v) v.frames[1].pos.x = '1' end, '.pos.x')
invalid(function(v) v.frames[1].pos = nil end, '.pos')
invalid(function(v) v.frames[1].rot.z = 360001 end, '.rot.z')
invalid(function(v) v.frames[1].duration = -1 end, '.duration')
invalid(function(v) v.frames[1].duration = 0 end, '.duration')
invalid(function(v) v.frames[1].duration = 601 end, '.duration')
invalid(function(v) v.frames[1].fov = 131 end, '.fov')
invalid(function(v) v.frames[1].easing = 'arbitrary' end, '.easing')
invalid(function(v) v.frames[1].easing = {} end, '.easing')
invalid(function(v) v.frames[1].transition = 'arbitrary' end, '.transition')
invalid(function(v) v.frames[1].id = v.frames[2].id end, 'duplicate')
invalid(function(v) v.frames[1].id = '<script>' end, '.id')
invalid(function(v) v.frames[1].label = 'a\0b' end, '.label')
invalid(function(v) v.frames[1].hour = 24 end, '.hour')
invalid(function(v) v.frames[1].minute = 1.5 end, '.minute')
invalid(function(v) v.frames[1].weather = 'SUNNY;os.execute()' end, '.weather')
invalid(function(v) v.frames[1].dof.near = 101 end, '.dof')
invalid(function(v) v.frames[1].dof.enabled = 'true' end, '.dof.enabled')
invalid(function(v) v.frames[1].dof = false end, '.dof')
invalid(function(v) v.frames[1].handleOut = { x = 0, y = 0 } end, '.handleOut.z')
invalid(function(v) v.speed = 0 end, '.speed')
invalid(function(v) v.loop = 1 end, '.loop')
invalid(function(v) v.version = 2 end, '.version')
invalid(function(v) v.frames[3] = v.frames[2]; v.frames[2] = nil end, 'gaps')
invalid(function(v) v.frames.foo = v.frames[1] end, 'array')
invalid(function(v) v.frames[201] = v.frames[1] end, 'at most')
invalid(function(v) v.name = string.rep('x', 161) end, '.name')
invalid(function(v) v.extra = function() end end, 'unknown field')
invalid(function(v) setmetatable(v, { __pairs = function() error('must not run') end }) end, 'plain table')
invalid(function(v) v.frames[1].pos = v end, 'unknown field')
invalid(function(v)
    v.frames = {}
    for i = 1, 7 do
        v.frames[i] = C.defaultFrame({}, {})
        v.frames[i].duration = 600
    end
end, '3600')
local raw = scene()
raw.frames[1].weather = (C.game=='gta5' and 'clear' or 'sunny')
raw.frames[1].dof = nil
raw.frames[1].easing, raw.frames[1].fov, raw.name = nil, nil, nil
s = assert(C.validateScene(raw))
equal(s.name, 'Untitled')
equal(C.defaultFrame().label:match('^Camera %d+$') ~= nil, true, 'new frame names are English')
equal(s.frames[1].weather, (C.game=='gta5' and 'CLEAR' or 'SUNNY'))
equal(s.frames[1].dof.focus, 10)
equal(s.frames[1].easing, 'smooth')
equal(s.frames[1].fov, 50)
s.frames[1].pos.x = 123
equal(raw.frames[1].pos.x, 0, 'validation does not alias raw scene')
local userScene = scene()
userScene.name, userScene.frames[1].label = 'Рассвет у реки', 'Первый кадр'
local preserved = assert(C.validateScene(userScene))
equal(preserved.name, 'Рассвет у реки', 'existing user scene names are preserved')
equal(preserved.frames[1].label, 'Первый кадр', 'existing user frame labels are preserved')
local empty = assert(C.validateScene({ frames = {} }))
equal(C.duration(empty), 0)
equal(C.sample(empty, 0), nil)
local one = { frames = { C.defaultFrame({}, {}) }, loop = true }
one.frames[1].duration = 0
one = assert(C.validateScene(one))
equal(C.duration(one), 0)
close(C.sample(one, 1000).pos.x, 0, 'zero duration still scene')
print(('arbat16_camera_core_spec: %d assertions passed'):format(count))
