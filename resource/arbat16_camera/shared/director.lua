-- Pure director data, persistence validation and reproducible camera motion.
FC = FC or {}
FC.Director = {}
local D, C = FC.Director, FC.Core

-- Modifier names from femga/rdr3_discoveries/graphics/timecycles/timecycles.lua.
-- Monochrome uses the game's Noir photo effect, not a GTA timecycle name:
-- Halen84/RDR3-Decompiled-Scripts/1491.50/camera_photomode.c, CAM_PM_F_M7.
D.filters = {
    {id='none', label='Original'},
    {id='monochrome', label='Black & White', postfx='PhotoMode_FilterModern07'},
    {id='player_camera', label='Photo Camera', modifier='PlayerCamera'},
    {id='cinematic', label='Cinematic Exposure', modifier='SPOTMETER_cinematicCam'},
    {id='flat', label='Flat Profile', modifier='FlatProfile'},
    {id='dusk', label='Frontier Dusk', modifier='teaser_canyon'},
    {id='frontier', label='Frontier Trailer', modifier='TRAILER3_Val'},
    {id='dream', label='Deer Dream', modifier='dreams_deer_resting'}
}
D.ratios = {'native', '2.39', '2.35', '1.85', '16:9', '4:3', '1:1'}
local filterSet, ratioSet = {}, {}
for _, item in ipairs(D.filters) do filterSet[item.id] = item end
for _, item in ipairs(D.ratios) do ratioSet[item] = true end

function D.defaults()
    return {look={filter='none', strength=0.6}, framing={ratio='native', opacity=1},
        motion={type='none', amplitude=0.15, frequency=0.2, roll=0.25}}
end
local function fail(path, message) return nil, path .. ': ' .. message end
local function object(raw, allowed, path)
    if type(raw) ~= 'table' or getmetatable(raw) ~= nil then return fail(path, 'expected a plain table') end
    for key in pairs(raw) do
        if type(key) ~= 'string' or not allowed[key] then return fail(path, 'unknown field') end
    end
    return true
end
local function number(raw, fallback, lower, upper, path)
    if raw == nil then raw = fallback end
    if not C.finite(raw) or raw < lower or raw > upper then return fail(path, 'out of range') end
    return raw
end
local function name(raw, path, id)
    if type(raw) ~= 'string' or #raw == 0 or #raw > 64 or not utf8.len(raw) or raw:find('[/\\]') then
        return fail(path, 'expected 1-64 bytes without control characters or slashes')
    end
    for _, code in utf8.codes(raw) do
        if code < 32 or (code >= 127 and code <= 159) then return fail(path,'control characters are not allowed') end
    end
    raw = raw:gsub('^ +', ''):gsub(' +$', '')
    if raw == '' or raw == '.' or raw == '..' or (id and not raw:match('^[%w_:%-]+$')) then
        return fail(path, 'invalid name')
    end
    return raw
end
local function array(raw, limit, path)
    if type(raw) ~= 'table' or getmetatable(raw) ~= nil then return fail(path, 'expected an array') end
    local count = 0
    for key in pairs(raw) do
        if not C.finite(key) or key ~= math.floor(key) or key < 1 or key > limit then return fail(path, 'invalid array or too many entries') end
        count = count + 1
    end
    for i=1,count do if raw[i] == nil then return fail(path, 'array contains gaps') end end
    return count
end

function D.validate(raw)
    local ok, err = object(raw, {look=true,framing=true,motion=true}, 'director')
    if not ok then return nil, err end
    local out = D.defaults()
    local fields = {look={filter=true,strength=true},framing={ratio=true,opacity=true},
        motion={type=true,amplitude=true,frequency=true,roll=true}}
    for group, allowed in pairs(fields) do
        if raw[group] ~= nil then
            ok, err = object(raw[group], allowed, 'director.'..group)
            if not ok then return nil, err end
            for key, value in pairs(raw[group]) do out[group][key] = value end
        end
    end
    if type(out.look.filter) ~= 'string' or not filterSet[out.look.filter] then return fail('director.look.filter','unknown filter') end
    if type(out.framing.ratio) ~= 'string' or not ratioSet[out.framing.ratio] then return fail('director.framing.ratio','unknown ratio') end
    if out.motion.type ~= 'none' and out.motion.type ~= 'sway' and out.motion.type ~= 'handheld' then return fail('director.motion.type','unknown motion') end
    for _, spec in ipairs({{'look','strength',0,1},{'framing','opacity',0,1},{'motion','amplitude',0,2},
            {'motion','frequency',0,3},{'motion','roll',0,5}}) do
        local value = out[spec[1]][spec[2]]
        if not C.finite(value) or value < spec[3] or value > spec[4] then return fail('director.'..spec[1]..'.'..spec[2],'out of range') end
    end
    return out
end

local function preset(id, label, filter, strength, ratio, fov, focus, motion)
    local director = D.defaults()
    director.look = {filter=filter,strength=strength}
    director.framing.ratio = ratio
    if motion then director.motion = motion end
    return {id=id,name=label,director=director,fov=fov,focus=focus}
end
D.presets = {
    preset('natural','Natural','none',0.6,'native',50,10),
    preset('western_scope','Western Scope','cinematic',0.65,'2.39',45,25),
    preset('frontier','Frontier','frontier',0.45,'2.35',52,30),
    preset('quiet_portrait','Quiet Portrait','player_camera',0.5,'4:3',30,4),
    preset('handheld','Handheld','flat',0.3,'1.85',55,10,{type='handheld',amplitude=0.045,frequency=0.6,roll=0.3}),
    preset('dream_sequence','Dream Sequence','dream',0.5,'2.39',40,20,{type='sway',amplitude=0.12,frequency=0.12,roll=0.2})
}

-- Motion never writes back into the saved pose and depends only on elapsed time.
function D.motionPose(base, director, elapsed)
    local out = C.copy(base)
    local motion = director and director.motion
    if not motion or motion.type == 'none' or not C.finite(elapsed) then return out end
    local phase = math.max(0, elapsed) * motion.frequency * math.pi * 2
    local x, z, roll = math.sin(phase), math.sin(phase*2)*0.35, math.sin(phase)*motion.roll
    if motion.type == 'handheld' then
        x = math.sin(phase)*0.55 + math.sin(phase*2.31)*0.25 + math.sin(phase*4.17)*0.2
        z = math.sin(phase*1.73)*0.3 + math.sin(phase*3.71)*0.2
        roll = (math.sin(phase*1.21)*0.7 + math.sin(phase*3.11)*0.3)*motion.roll
    end
    local yaw = math.rad(base.rot.z)
    out.pos.x = out.pos.x + math.cos(yaw)*x*motion.amplitude
    out.pos.y = out.pos.y + math.sin(yaw)*x*motion.amplitude
    out.pos.z = out.pos.z + z*motion.amplitude
    out.rot.y = out.rot.y + roll
    return out
end

local function frame(raw)
    if type(raw)=='table' and raw.take~=nil then return fail('camera.take','recorded clips belong on the scene timeline') end
    local scene, err = C.validateScene({frames={raw}})
    if not scene then return nil, err end
    return scene.frames[1]
end
-- One settings contract serves persisted workspaces and transactional live edits.
-- Missing fields migrate older workspaces without changing the enabled grid flag.
D.gridTypes = {'thirds','golden','diagonals','quarters','center','safe'}
local gridTypes = {}
for _, gridType in ipairs(D.gridTypes) do gridTypes[gridType] = true end
function D.validateSettings(raw)
    local ok, err = object(raw,{speed=true,showPath=true,showCameras=true,hideHud=true,
        letterbox=true,grid=true,gridType=true,gridOpacity=true,stabilization=true},'workspace.settings')
    if not ok then return nil, err end
    local out = {speed=5,showPath=true,showCameras=true,hideHud=true,letterbox=false,
        grid=false,gridType='thirds',gridOpacity=0.6,stabilization='off'}
    if raw.stabilization~=nil then
        local levels={off=true,light=true,medium=true,strong=true}
        if type(raw.stabilization)~='string' or not levels[raw.stabilization] then
            return fail('workspace.settings.stabilization','expected off, light, medium or strong')
        end
        out.stabilization=raw.stabilization
    end
    if raw.gridType~=nil then
        if type(raw.gridType)~='string' or not gridTypes[raw.gridType] then
            return fail('workspace.settings.gridType','expected thirds, golden, diagonals, quarters, center or safe')
        end
        out.gridType=raw.gridType
    end
    out.speed, err = number(raw.speed,5,0.1,100,'workspace.settings.speed')
    if not out.speed then return nil, err end
    out.gridOpacity, err = number(raw.gridOpacity,0.6,0.1,1,'workspace.settings.gridOpacity')
    if not out.gridOpacity then return nil, err end
    for _, key in ipairs({'showPath','showCameras','hideHud','letterbox','grid'}) do
        if raw[key] ~= nil then
            if type(raw[key]) ~= 'boolean' then return fail('workspace.settings.'..key,'expected a boolean') end
            out[key] = raw[key]
        end
    end
    return out
end
function D.validateWorkspace(raw)
    local ok, err = object(raw,{version=true,scene=true,camera=true,settings=true,cameras=true,presets=true,time=true},'workspace')
    if not ok then return nil, err end
    if raw.version ~= nil and raw.version ~= 1 then return fail('workspace.version','unsupported version') end
    local out = {version=1,cameras={},presets={}}
    out.scene, err = C.validateScene(raw.scene)
    if not out.scene then return nil, err end
    out.scene.name, err = name(out.scene.name, 'workspace.scene.name')
    if not out.scene.name then return nil, err end
    out.camera, err = frame(raw.camera)
    if not out.camera then return nil, err end
    out.time, err = number(raw.time,0,0,C.duration(out.scene),'workspace.time')
    if out.time == nil then return nil, err end
    out.settings, err = D.validateSettings(raw.settings == nil and {} or raw.settings)
    if not out.settings then return nil, err end
    for _, spec in ipairs({{'cameras',100},{'presets',40}}) do
        local group, limit = spec[1], spec[2]
        local list = raw[group] == nil and {} or raw[group]
        local count; count, err = array(list,limit,'workspace.'..group)
        if not count then return nil, err end
        local ids = {}
        for i=1,count do
            local item, itemPath = list[i], 'workspace.'..group..'['..i..']'
            local allowed = group == 'cameras' and {id=true,name=true,frame=true,director=true} or {id=true,name=true,director=true,fov=true,focus=true}
            ok, err = object(item,allowed,itemPath)
            if not ok then return nil, err end
            local entry = {}
            entry.id, err = name(item.id,itemPath..'.id',true)
            if not entry.id then return nil, err end
            if ids[entry.id] then return fail(itemPath..'.id','duplicate ID') end
            ids[entry.id] = true
            entry.name, err = name(item.name,itemPath..'.name')
            if not entry.name then return nil, err end
            entry.director, err = D.validate(item.director == nil and {} or item.director)
            if not entry.director then return nil, err end
            if group == 'cameras' then
                entry.frame, err = frame(item.frame)
                if not entry.frame then return nil, err end
            else
                entry.fov, err = number(item.fov,50,1,130,itemPath..'.fov')
                if not entry.fov then return nil, err end
                entry.focus, err = number(item.focus,10,0.01,100000,itemPath..'.focus')
                if not entry.focus then return nil, err end
            end
            out[group][i] = entry
        end
    end
    return out
end

function D.generateMove(camera, options)
    local base, err = frame(camera)
    if not base then return nil, err end
    local ok; ok, err = object(options,{kind=true,distance=true,angle=true,duration=true,returnToStart=true},'move')
    if not ok then return nil, err end
    local kind = options.kind
    if kind ~= 'dolly' and kind ~= 'truck' and kind ~= 'crane' and kind ~= 'pan' and kind ~= 'orbit' then return fail('move.kind','unknown move') end
    local distance; distance, err = number(options.distance,5,-500,500,'move.distance')
    if distance == nil then return nil, err end
    local angle; angle, err = number(options.angle,45,-360,360,'move.angle')
    if angle == nil then return nil, err end
    local duration; duration, err = number(options.duration,6,0.2,600,'move.duration')
    if not duration then return nil, err end
    if options.returnToStart ~= nil and type(options.returnToStart) ~= 'boolean' then return fail('move.returnToStart','expected a boolean') end
    if kind == 'orbit' and math.abs(distance) < 0.1 then return fail('move.distance','orbit radius must be at least 0.1 m') end
    local yaw, pitch = math.rad(base.rot.z), math.rad(base.rot.x)
    local forward = {x=-math.sin(yaw)*math.cos(pitch),y=math.cos(yaw)*math.cos(pitch),z=math.sin(pitch)}
    local count = (kind == 'orbit' or kind == 'pan') and math.max(2,math.ceil(math.abs(angle)/30)+1) or 2
    local frames = {}
    for i=1,count do
        local t, f = (i-1)/(count-1), C.copy(base)
        f.handleIn, f.handleOut = nil, nil
        if kind == 'dolly' then
            for _, axis in ipairs({'x','y','z'}) do f.pos[axis] = f.pos[axis] + forward[axis]*distance*t end
        elseif kind == 'truck' then
            f.pos.x, f.pos.y = f.pos.x+math.cos(yaw)*distance*t, f.pos.y+math.sin(yaw)*distance*t
        elseif kind == 'crane' then f.pos.z = f.pos.z+distance*t
        elseif kind == 'pan' then f.rot.z = f.rot.z+angle*t
        else
            local radius, arc = math.abs(distance), math.rad(angle*t)
            local pivotX, pivotY = base.pos.x-math.sin(yaw)*radius, base.pos.y+math.cos(yaw)*radius
            local dx, dy = base.pos.x-pivotX, base.pos.y-pivotY
            f.pos.x, f.pos.y = pivotX+dx*math.cos(arc)-dy*math.sin(arc), pivotY+dx*math.sin(arc)+dy*math.cos(arc)
            f.rot.z = f.rot.z+angle*t
        end
        f.easing = count == 2 and 'easeInOut' or 'linear'
        f.transition = kind == 'orbit' and 'smooth' or 'linear'
        frames[#frames+1] = f
    end
    if options.returnToStart then for i=count-1,1,-1 do frames[#frames+1] = C.copy(frames[i]) end end
    for i, f in ipairs(frames) do
        f.id, f.label = 'move_'..i, kind:sub(1,1):upper()..kind:sub(2)..' '..i
        f.duration = i == #frames and 0 or duration/(#frames-1)
    end
    local validated; validated, err = C.validateScene({frames=frames})
    if not validated then return nil, err end
    return validated.frames
end

return D
