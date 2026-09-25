-- Pure free-flight stabilization. Input deltas are degrees and elapsed time is seconds.
FC = FC or {}
FC.Flight = {}
local F, C = FC.Flight, FC.Core
local levels = {'off', 'light', 'medium', 'strong'}
local responses = {light={rotation=0.07, movement=0.10},
    medium={rotation=0.17, movement=0.22}, strong={rotation=0.35, movement=0.40}}
local function wrap(value) return (value+180)%360-180 end
local function validTime(dt) return C.finite(dt) and math.max(0,dt) or 0 end
function F.isLevel(level) return level=='off' or responses[level]~=nil end
function F.cycle(level)
    for index,value in ipairs(levels) do if level==value then return levels[index%#levels+1] end end
    return 'off'
end
function F.reset(state, rot)
    rot=rot or {x=0,y=0,z=0}
    state.yaw=wrap(rot.z);state.pitch=C.clamp(rot.x,-89.5,89.5)
    state.lastYaw=wrap(rot.z);state.lastPitch=rot.x;state.outputYaw=wrap(rot.z)
    state.rotationIdle=0;state.velocity={x=0,y=0,z=0};state.velocityIdle={x=0,y=0,z=0}
    return state
end
function F.new(rot) return F.reset({},rot) end

-- The target advances linearly during this frame. Integrating that ramp exactly
-- avoids frame-rate-dependent lag when the same mouse sweep is sampled at 30/144 Hz.
local function rotationStep(current, previousError, delta, dt, tau)
    if dt<=0 then return current end
    local response=1-math.exp(-dt/tau)
    return current+previousError*response+delta*(1-tau*response/dt)
end
function F.rotate(state, rot, yawDelta, pitchDelta, dt, level)
    dt=validTime(dt)
    local response=responses[level]
    if not response then
        local out={x=C.clamp(rot.x+pitchDelta,-89.5,89.5),y=rot.y,z=wrap(rot.z+yawDelta)}
        F.reset(state,out);return out
    end
    -- An attachment may rotate between ticks. Carry the target with its external
    -- rotation, instead of pulling a mounted camera back toward an old world angle.
    local externalYaw=wrap(rot.z-state.lastYaw)
    state.yaw=state.yaw+externalYaw;state.outputYaw=state.outputYaw+externalYaw
    state.pitch=C.clamp(state.pitch+rot.x-state.lastPitch,-89.5,89.5)
    -- Mouse gestures remain unwrapped internally: a fast sweep can leave more
    -- than 180 degrees of lag, and must never reverse to chase a shorter route.
    local oldYawError=state.yaw-state.outputYaw
    local targetYaw=state.yaw+yawDelta
    local targetPitch=C.clamp(state.pitch+pitchDelta,-89.5,89.5)
    local pitchChange=targetPitch-state.pitch
    if yawDelta~=0 or pitchDelta~=0 then state.rotationIdle=0
    else state.rotationIdle=state.rotationIdle+dt end
    local outputYaw=rotationStep(state.outputYaw,oldYawError,yawDelta,dt,response.rotation)
    local out={y=rot.y,
        x=C.clamp(rotationStep(rot.x,state.pitch-rot.x,pitchChange,dt,response.rotation),-89.5,89.5),
        z=wrap(outputYaw)}
    -- Finish a released mouse gesture in bounded time; the remaining correction
    -- after eight response times is below 0.04% of the original angular error.
    if state.rotationIdle>=response.rotation*8 then out.x=targetPitch;outputYaw=targetYaw;out.z=wrap(targetYaw) end
    -- Rebase both by the same full turns, retaining their continuous difference
    -- while avoiding unbounded numbers during a long session.
    state.yaw=targetYaw-(outputYaw-out.z);state.outputYaw=out.z
    state.pitch=targetPitch;state.lastYaw=out.z;state.lastPitch=out.x
    return out
end

function F.move(state, desired, dt, level)
    dt=validTime(dt)
    local response=responses[level]
    local displacement={}
    for _,axis in ipairs({'x','y','z'}) do
        local target=desired[axis]
        if not response then
            displacement[axis]=target*dt;state.velocity[axis]=0;state.velocityIdle[axis]=0
        else
            local tau=response.movement
            local elapsed=dt
            if target==0 then
                -- Integrate only the remaining release tail, even when a frame
                -- straddles the end, so stopping distance is invariant across FPS.
                elapsed=math.min(dt,math.max(0,tau*6-state.velocityIdle[axis]))
                state.velocityIdle[axis]=state.velocityIdle[axis]+dt
            else state.velocityIdle[axis]=0 end
            local decay=math.exp(-elapsed/tau)
            local velocity=state.velocity[axis]
            displacement[axis]=target*elapsed+(velocity-target)*tau*(1-decay)
            state.velocity[axis]=target+(velocity-target)*decay
            if target==0 and state.velocityIdle[axis]>=tau*6 then state.velocity[axis]=0 end
        end
    end
    return displacement
end
function F.step(state, rot, desired, yawDelta, pitchDelta, dt, level)
    return F.rotate(state,rot,yawDelta,pitchDelta,dt,level),F.move(state,desired,dt,level)
end
return F
