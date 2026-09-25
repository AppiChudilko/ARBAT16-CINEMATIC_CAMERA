local C=dofile('resource/arbat16_camera/shared/core.lua')
local F=dofile('resource/arbat16_camera/shared/flight.lua')
local checks=0
local function check(value,label) checks=checks+1;assert(value,label) end
local function close(a,b,label,epsilon)
    checks=checks+1;assert(math.abs(a-b)<(epsilon or 0.0000001),(label or 'value')..': '..a..' ~= '..b)
end
local function wrap(a) return (a+180)%360-180 end
local function pose(x,z) return {x=x or 0,y=7,z=z or 0} end
local function zero() return {x=0,y=0,z=0} end
local function phase(state,rot,pos,fps,seconds,level,velocity,yawRate,pitchRate)
    for _=1,math.floor(seconds*fps+0.5) do
        local delta
        rot,delta=F.step(state,rot,velocity,(yawRate or 0)/fps,(pitchRate or 0)/fps,1/fps,level)
        for _,axis in ipairs({'x','y','z'}) do pos[axis]=pos[axis]+delta[axis] end
    end
    return rot,pos
end

for _,level in ipairs({'off','light','medium','strong'}) do check(F.isLevel(level),'valid level '..level) end
for _,level in ipairs({'maximum',0,true,{}}) do check(not F.isLevel(level),'unknown level rejected') end
local level='off'
for _,expected in ipairs({'light','medium','strong','off'}) do level=F.cycle(level);check(level==expected,'cycle order') end

-- Off preserves the previous direct mouse gain and immediate movement/release.
do
    local state=F.new(pose(87,179))
    local rot,delta=F.step(state,pose(87,179),{x=2,y=-3,z=5},5,5,.016,'off')
    close(rot.z,-176,'off yaw wraps');close(rot.x,89.5,'off pitch clamps');close(rot.y,7,'roll retained')
    close(delta.x,.032);close(delta.y,-.048);close(delta.z,.08)
    local stopped=F.move(state,zero(),.016,'off');close(stopped.z,0,'off stops immediately')
end

-- Exact exponential integrals give the same ramp and release result at 30/60/144 FPS.
for _,level in ipairs({'light','medium','strong'}) do
    local samples={}
    for _,fps in ipairs({30,60,144}) do
        local rot,pos=pose(),zero();local state=F.new(rot)
        rot,pos=phase(state,rot,pos,fps,.5,level,{x=3,y=4,z=5},60,-35)
        samples[fps]={rot=C.copy(rot),pos=C.copy(pos)}
        rot,pos=phase(state,rot,pos,fps,3,level,zero(),0,0)
        samples[fps].released={rot=C.copy(rot),pos=C.copy(pos)}
        close(rot.z,30,'released yaw target');close(rot.x,-17.5,'released pitch target')
        close(state.velocity.z,0,'bounded release tail');close(state.velocity.x,0,'bounded horizontal tail')
    end
    for _,fps in ipairs({60,144}) do
        for _,axis in ipairs({'x','y','z'}) do
            close(samples[30].rot[axis],samples[fps].rot[axis],level..' rotation FPS invariant')
            close(samples[30].pos[axis],samples[fps].pos[axis],level..' movement FPS invariant')
            close(samples[30].released.pos[axis],samples[fps].released.pos[axis],level..' release FPS invariant')
        end
    end
end

do
    local samples={}
    for _,level in ipairs({'light','medium','strong'}) do
        local rot,pos=pose(),zero();local state=F.new(rot)
        rot,pos=phase(state,rot,pos,100,.15,level,{x=0,y=0,z=5},60,40)
        samples[level]={yaw=rot.z,pitch=rot.x,z=pos.z}
        local previous=pos.z
        rot,pos=phase(state,rot,pos,100,.1,level,zero(),0,0)
        check(pos.z>previous,'normal Q/E release eases to a stop')
    end
    for _,field in ipairs({'yaw','pitch','z'}) do
        check(samples.light[field]>samples.medium[field] and samples.medium[field]>samples.strong[field],field..' response ordering')
    end
end

-- Reversing horizontal/vertical mouse direction approaches the new target without overshoot.
do
    local rot,pos=pose(),zero();local state=F.new(rot)
    rot,pos=phase(state,rot,pos,60,.5,'strong',zero(),90,50)
    rot,pos=phase(state,rot,pos,60,.5,'strong',zero(),-180,-100)
    rot,pos=phase(state,rot,pos,60,3,'strong',zero(),0,0)
    close(rot.z,-45,'mouse reversal yaw');close(rot.x,-25,'mouse reversal pitch')
    rot,pos=phase(state,rot,pos,60,2,'strong',zero(),0,200)
    rot,pos=phase(state,rot,pos,60,3,'strong',zero(),0,0)
    close(rot.x,89.5,'smoothed pitch still clamps')
    local before=rot.x
    rot=F.rotate(state,rot,0,-1,1/60,'strong')
    check(rot.x<before,'pitch can immediately reverse away from its clamp')
end

do
    local rot=pose(0,179);local state=F.new(rot)
    for _=1,60 do
        local before=rot.z
        rot=F.rotate(state,rot,1/6,0,1/60,'medium')
        check(wrap(rot.z-before)>0 and wrap(rot.z-before)<.2,'yaw crosses 180 by the short route')
    end
    rot=select(1,phase(state,rot,zero(),60,3,'medium',zero(),0,0))
    close(rot.z,-171,'wrapped final yaw')
end

do
    local rot=pose();local state=F.new(rot)
    for _=1,120 do
        local before=rot.z
        rot=F.rotate(state,rot,12,0,1/60,'strong')
        check(wrap(rot.z-before)>0,'continuous fast sweep never reverses when lag exceeds 180 degrees')
    end
    rot=select(1,phase(state,rot,zero(),60,3,'strong',zero(),0,0))
    close(rot.z,0,'multiple full turns settle at the accumulated target')
end

-- External attachment rotation carries the unsmoothed target along with the mount.
do
    local initial=pose(10,20);local a,b=F.new(initial),F.new(initial)
    local ar=F.rotate(a,initial,12,4,.05,'strong')
    local br=F.rotate(b,initial,12,4,.05,'strong')
    ar.z=ar.z+45;ar.x=ar.x+8
    ar=F.rotate(a,ar,0,0,.05,'strong');br=F.rotate(b,br,0,0,.05,'strong')
    close(wrap(ar.z-br.z),45,'attachment yaw rebase');close(ar.x-br.x,8,'attachment pitch rebase')
end

-- Pausing, losing focus, recalling a camera or switching levels uses reset, not a coast.
do
    local rot=pose();local state=F.new(rot)
    rot=select(1,phase(state,rot,zero(),60,.5,'strong',{x=4,y=5,z=6},90,40))
    F.reset(state,rot)
    local nextRot,delta=F.step(state,rot,zero(),0,0,1/30,'strong')
    close(nextRot.z,rot.z,'reset removes yaw residue');close(nextRot.x,rot.x,'reset removes pitch residue')
    close(delta.x,0,'reset stops horizontal motion');close(delta.z,0,'reset stops vertical motion')
    local recalled=pose(-30,-155);F.reset(state,recalled)
    nextRot,delta=F.step(state,recalled,zero(),0,0,1/30,'medium')
    close(nextRot.z,recalled.z,'recall has no old target');close(delta.y,0,'recall has no old velocity')
end
print(('Flight stabilization: %d checks passed (FPS invariance, all axes, response levels, reversal, wrapping, attachments and reset).'):format(checks))
