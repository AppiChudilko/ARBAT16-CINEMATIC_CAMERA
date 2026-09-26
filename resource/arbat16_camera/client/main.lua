-- Arbat16 Camera: standalone FiveM / RedM editor. Timeline values are seconds.
local C, N, F = FC.Core, FC.Natives.call, FC.Flight
local game=FC.Natives.game
local isGta=game=='gta5'
local cfg = FCConfig or {}
local active, cam, player, previousCam, previousFrozen = false, nil, nil, nil, false
local scene = {version=1, name='New scene', frames={}, loop=false, speed=1}
local camera, attachment, aimProbe, pending = nil, nil, nil, {}
local settings = {speed=cfg.DefaultSpeed or 5, showPath=true, showCameras=true, hideHud=true,
    letterbox=false, grid=false, gridType='thirds', gridOpacity=0.6, stabilization='off'}
local flightSmoothing = F.new()
local playing, recording, flight, timeline = false, false, false, 0
local keys, lookX, lookY, inputAt, sequence = {}, 0, 0, 0, 0
local nextRecord, nextState, nextGizmos, nextEnvironment = 0, 0, 0, 0
local recordBuffer, renderedCamera, finishRecording, recordFrame
local environmentTouched, previousWeather, lastWeather, lastClock, requestedOpen = false, nil, nil, nil, nil
local pathCache, uiReady, stopped, sceneRevision = {}, false, false, 0
local tickCount, inputPackets, lastTickAt, lastRuntimeError = 0, 0, nil, nil
local stateSequence = 0
local D, DR = FC.Director, FC.DirectorRuntime
local savedCameras, savedPresets = {}, {}
local workspaceLoaded, workspaceBlocked, workspaceError = false, false, nil
local workspaceRevision, workspaceSavedRevision, workspaceSerial = 0, 0, 0
local workspacePending, workspaceDue, workspaceLastSent = nil, nil, -10000
local motionElapsed = 0
local flushWorkspace, markWorkspace, sendWorkspace
local nativeFlightInput = type(IsRawKeyDown)=='function'
local nativeInputTicks, lastFrameTime, diagnosticDue = 0, nil, nil
local reportRuntime
local diagnosticWarning = false
local rawPrevious, rawBlocked = {}, {}
-- Cfx raw keys use Windows virtual-key codes, independent of keyboard layout.
local rawKeys = {KeyW=0x57,KeyA=0x41,KeyS=0x53,KeyD=0x44,KeyQ=0x51,KeyE=0x45,
    Tab=0x09,Escape=0x1B,KeyF=0x46,KeyG=0x47,KeyH=0x48,
    KeyJ=0x4A,KeyR=0x52,F1=0x70,Space=0x20}
-- Cfx reads exact raw-key indices; generic modifier codes do not synthesize
-- left/right states. Normalize each family before the held-key safety guard.
local rawModifiers = {ShiftLeft={0x10,0xA0,0xA1},
    ControlLeft={0x11,0xA2,0xA3},AltLeft={0x12,0xA4,0xA5}}
local allowedKeys = {KeyW=true,KeyA=true,KeyS=true,KeyD=true,KeyQ=true,KeyE=true,
    ShiftLeft=true,ShiftRight=true,ControlLeft=true,ControlRight=true,AltLeft=true,AltRight=true}
local weatherNames = isGta and {clear=true,extrasunny=true,clouds=true,overcast=true,rain=true,clearing=true,
    thunder=true,smog=true,foggy=true,xmas=true,snow=true,snowlight=true,blizzard=true,
    halloween=true,neutral=true} or {sunny=true,clouds=true,overcast=true,overcastdark=true,rain=true,drizzle=true,
    thunder=true,thunderstorm=true,fog=true,misty=true,highpressure=true,snow=true,blizzard=true,
    snowlight=true,groundblizzard=true,hurricane=true,whiteout=true,sandstorm=true,sleet=true,hail=true}
local function now() return N('GET_GAME_TIMER') end
local function entityCoords(entity)
    if isGta then return N('GET_ENTITY_COORDS',entity,true) end
    return N('GET_ENTITY_COORDS',entity,true,true)
end
local function entityDead(entity)
    if isGta then return N('IS_ENTITY_DEAD',entity,false) end
    return N('IS_ENTITY_DEAD',entity)
end
local function finite(n) return type(n)=='number' and n==n and n>-math.huge and n<math.huge end
local function num(n, low, high, fallback) return finite(n) and C.clamp(n,low,high) or fallback end
local function vec(v) return {x=v.x+0.0,y=v.y+0.0,z=v.z+0.0} end
local function add(a,b) return {x=a.x+b.x,y=a.y+b.y,z=a.z+b.z} end
local function sub(a,b) return {x=a.x-b.x,y=a.y-b.y,z=a.z-b.z} end
local function mul(a,n) return {x=a.x*n,y=a.y*n,z=a.z*n} end
local function dot(a,b) return a.x*b.x+a.y*b.y+a.z*b.z end
local function length(a) return math.sqrt(dot(a,a)) end
local function message(value) if uiReady then SendNUIMessage(value) end end
local function bulkServerEvent(name,...)
    if type(TriggerLatentServerEvent)=='function' then TriggerLatentServerEvent(name,1048576,...)
    else TriggerServerEvent(name,...) end
end
local function toast(text,level)
    message({type='toast',message=text,level=level or 'info'})
    if not active then print('[arbat16_camera] '..text) end
end
local function sendScene(selectedId)
    message({type='scene',scene=scene,selectedId=selectedId,revision=sceneRevision})
    if markWorkspace then markWorkspace() end
end
local function sendState()
    stateSequence=stateSequence+1
    message({type='state',playing=playing,recording=recording,flight=flight,time=timeline,
        recordingDuration=recordBuffer and math.min(recordBuffer.maxDuration,math.max(0,(now()-recordBuffer.started)/1000)) or 0,
        recordingSamples=recordBuffer and #recordBuffer.samples or 0,
        duration=C.duration(scene),camera=camera,settings=settings,stateSequence=stateSequence,
        director=scene.director or D.defaults(),
        attachment=attachment and {mode=attachment.mode,entity=attachment.entity,rotate=attachment.rotate} or false})
end
local function clearInput()
    keys={};lookX=0;lookY=0;inputAt=0
    F.reset(flightSmoothing,camera and camera.rot)
end
local function rawSnapshot()
    local values={}
    for key,code in pairs(rawKeys) do
        local value=IsRawKeyDown(code)
        values[key]=value==true or value==1
    end
    for key,codes in pairs(rawModifiers) do
        values[key]=false
        for _,code in ipairs(codes) do
            local value=IsRawKeyDown(code)
            if value==true or value==1 then values[key]=true;break end
        end
    end
    return values
end
local function primeNativeInput()
    if not nativeFlightInput then return end
    rawPrevious=rawSnapshot();rawBlocked=C.copy(rawPrevious)
end
local function cameraFocus()
    local editorFocus=not (flight and nativeFlightInput)
    SetNuiFocus(editorFocus,editorFocus)
    if type(SetNuiFocusKeepInput)=='function' then SetNuiFocusKeepInput(false) end
end
local function safeReportRuntime(event)
    if not reportRuntime then return end
    local ok=pcall(reportRuntime,event)
    if not ok and not diagnosticWarning then
        diagnosticWarning=true
        pcall(print,'[arbat16_camera] Diagnostics are unavailable. Camera controls remain active.')
    end
end
local function diagnose(event,probe)
    if cfg.Diagnostics~=true then return end
    safeReportRuntime(event)
    if probe then
        local ok,tick=pcall(now)
        if ok and finite(tick) then diagnosticDue=tick+2000 end
    end
end
local function setFlight(enabled)
    if flight==enabled then sendState();return end
    flight=enabled;clearInput()
    if flight then playing=false;if camera then camera._recorded=nil end;primeNativeInput() end
    cameraFocus();sendState();diagnose('flight',flight)
end

-- RAGE rotation order 2 is ZXY. Matrix columns are right, forward, up.
local function basis(rot)
    local x,y,z=math.rad(rot.x),math.rad(rot.y),math.rad(rot.z)
    local sx,cx,sy,cy,sz,cz=math.sin(x),math.cos(x),math.sin(y),math.cos(y),math.sin(z),math.cos(z)
    return {right={x=cz*cy-sz*sx*sy,y=sz*cy+cz*sx*sy,z=-cx*sy},
        forward={x=-sz*cx,y=cz*cx,z=sx},
        up={x=cz*sy+sz*sx*cy,y=sz*sy-cz*sx*cy,z=cx*cy}}
end
local function localVector(b,v) return {x=dot(b.right,v),y=dot(b.forward,v),z=dot(b.up,v)} end
local function worldVector(b,v) return add(add(mul(b.right,v.x),mul(b.forward,v.y)),mul(b.up,v.z)) end
local function entityBasis(entity)
    local first,second,up,pos=N('GET_ENTITY_MATRIX',entity,Citizen.PointerValueVector(),
        Citizen.PointerValueVector(),Citizen.PointerValueVector(),Citizen.PointerValueVector())
    -- GTA V entity matrices return forward first; RDR3 returns right first.
    local right,forward=first,second
    if isGta then right,forward=second,first end
    return {right=vec(right),forward=vec(forward),up=vec(up),pos=vec(pos)}
end
local function orientation(b)
    local pitch=math.asin(C.clamp(b.forward.z,-1,1))
    local roll,yaw
    if math.abs(math.cos(pitch))>0.0001 then
        roll=math.atan(-b.right.z,b.up.z);yaw=math.atan(-b.forward.x,b.forward.y)
    else roll=0;yaw=math.atan(b.right.y,b.right.x) end
    return {x=math.deg(pitch),y=math.deg(roll),z=math.deg(yaw)}
end
local function transformPose(pose, inverse)
    if not attachment then return C.copy(pose) end
    local from,to=attachment.reference,attachment.current
    if inverse then from,to=to,from end
    local out=C.copy(pose)
    if attachment.rotate then
        out.pos=add(to.pos,worldVector(to,localVector(from,sub(pose.pos,from.pos))))
        local b=basis(pose.rot)
        out.rot=orientation({right=worldVector(to,localVector(from,b.right)),
            forward=worldVector(to,localVector(from,b.forward)),up=worldVector(to,localVector(from,b.up))})
    else out.pos=add(pose.pos,sub(to.pos,from.pos)) end
    return out
end
local function poseWithinReach(pose)
    if not player or not N('DOES_ENTITY_EXIST',player) then return false end
    return length(sub(pose.pos,vec(entityCoords(player)))) <= (cfg.MaxDistance or 2000)
end
local function rebuildPath()
    pathCache={}
    if #scene.frames<2 then return end
    -- At most 200 segments, with exact endpoints and no lines across cuts/holds.
    local count=math.max(1,math.min(16,math.floor(200/(#scene.frames-1))))
    local sampleScene=C.copy(scene);sampleScene.loop=false
    local elapsed=0
    for index=1,#scene.frames-1 do
        local frame,nextFrame=scene.frames[index],scene.frames[index+1]
        if frame.duration>0 and frame.transition~='cut' and frame.transition~='hold' then
            local previous=frame.pos
            for part=1,count do
                local point
                if part==count then point=nextFrame.pos
                else point=C.sample(sampleScene,elapsed+frame.duration*part/count).pos end
                pathCache[#pathCache+1]={a=previous,b=point};previous=point
            end
        end
        elapsed=elapsed+frame.duration
    end
end
local function project(pos)
    local visible,x,y=N('GET_SCREEN_COORD_FROM_WORLD_COORD',pos.x,pos.y,pos.z,
        Citizen.PointerValueFloat(),Citizen.PointerValueFloat())
    if visible and finite(x) and finite(y) and x>=-0.1 and x<=1.1 and y>=-0.1 and y<=1.1 then return x,y end
end
local function transformedPoint(pos)
    if not attachment then return pos end
    return transformPose({pos=pos,rot={x=0,y=0,z=0}},false).pos
end
local function sendGizmos()
    local points,lines,cameras={},{},{}
    if settings.showPath and not playing then
        for _,edge in ipairs(pathCache) do
            local x1,y1=project(transformedPoint(edge.a));local x2,y2=project(transformedPoint(edge.b))
            if x1 and x2 then lines[#lines+1]={x1=x1,y1=y1,x2=x2,y2=y2} end
        end
        for index,frame in ipairs(scene.frames) do
            local node=transformedPoint(frame.pos);local x,y=project(node)
            if x then points[#points+1]={id=frame.id,kind='node',x=x,y=y,label=tostring(index)} end
            for _,kind in ipairs({'in','out'}) do
                local offset=frame[kind=='in' and 'handleIn' or 'handleOut']
                if offset then
                    local hx,hy=project(transformedPoint(add(frame.pos,offset)))
                    if hx then points[#points+1]={id=frame.id,kind=kind,x=hx,y=hy} end
                    if x and hx then lines[#lines+1]={x1=x,y1=y,x2=hx,y2=hy,handle=true} end
                end
            end
        end
    end
    if settings.showCameras and not playing then
        for index,entry in ipairs(savedCameras) do
            local origin=entry.frame.pos
            local x,y=project(origin)
            if x then
                -- Project a small world-space viewfinder, so its orientation
                -- and size follow the actual saved camera as the viewer moves.
                local b=basis(entry.frame.rot)
                local center=add(origin,mul(b.forward,1.2))
                local height=1.2*math.tan(math.rad(entry.frame.fov/2))
                local corners={}
                for _,sign in ipairs({{-1,-1},{1,-1},{1,1},{-1,1}}) do
                    corners[#corners+1]=add(center,add(mul(b.right,sign[1]*height*16/9),mul(b.up,sign[2]*height)))
                end
                local edges={}
                local function edge(a,bp)
                    local x1,y1=project(a);local x2,y2=project(bp)
                    if x1 and x2 then edges[#edges+1]={x1=x1,y1=y1,x2=x2,y2=y2} end
                end
                for i,corner in ipairs(corners) do
                    edge(origin,corner);edge(corner,corners[i%4+1])
                end
                cameras[#cameras+1]={id=entry.id,name=entry.name,index=index,x=x,y=y,lines=edges}
            end
        end
    end
    message({type='gizmos',points=points,lines=lines,cameras=cameras})
end
local function environment(force)
    if not active or not camera or cfg.WeatherEnabled==false then return end
    local tick=now()
    if not force and tick<nextEnvironment then return end
    nextEnvironment=tick+500
    local name=type(camera.weather)=='string' and camera.weather:lower() or nil
    if name and weatherNames[name] and (force or name~=lastWeather) then
        environmentTouched=true
        if not isGta then N('_SET_WEATHER_TYPE_FROZEN',false) end
        N('CLEAR_OVERRIDE_WEATHER');N('CLEAR_WEATHER_TYPE_PERSIST')
        if isGta then N('SET_WEATHER_TYPE_NOW_PERSIST',name:upper())
        else N('SET_WEATHER_TYPE',N('GET_HASH_KEY',name:upper()),true,true,true,0.5,false) end
        lastWeather=name
    end
    local hour,minute=math.floor(num(camera.hour,0,23,12)),math.floor(num(camera.minute,0,59,0))
    local clock=hour*60+minute
    if force or lastClock~=clock then
        environmentTouched=true;lastClock=clock
        if isGta then N('NETWORK_OVERRIDE_CLOCK_TIME',hour,minute,0)
        else N('_NETWORK_CLOCK_TIME_OVERRIDE',hour,minute,0,0,true) end
    end
end
local function applyCamera()
    local rendered=camera._recorded and camera or DR.pose(camera,scene.director or D.defaults(),motionElapsed)
    if not poseWithinReach(rendered) then rendered=camera end
    renderedCamera=C.copy(rendered)
    N('SET_CAM_COORD',cam,rendered.pos.x,rendered.pos.y,rendered.pos.z)
    N('SET_CAM_ROT',cam,rendered.rot.x,rendered.rot.y,rendered.rot.z,2)
    N('SET_CAM_FOV',cam,rendered.fov)
    local dof=rendered.dof or {}
    local enabled=dof.enabled==true
    if isGta then N('SET_CAM_USE_SHALLOW_DOF_MODE',cam,enabled) end
    if isGta and enabled then
        -- Documented GTA distances define an in-focus band. The focus control
        -- centers that band, with a 10% half-width (at least five centimetres).
        local focus=num(dof.focus,0.01,100000,10)
        local halfWidth=math.max(0.05,focus*0.1)
        N('SET_CAM_NEAR_DOF',cam,math.max(0,focus-halfWidth))
        N('SET_CAM_FAR_DOF',cam,focus+halfWidth)
        N('SET_CAM_DOF_STRENGTH',cam,num(dof.strength,0,1,0.5))
        N('SET_USE_HI_DOF') -- GTA requires this every rendered frame.
    elseif not isGta then
        -- RDR3 only exposes the verified scalar focus setter; blur ABI is not used.
        N('_SET_CAM_FOCUS_DISTANCE',cam,num(dof.focus,0.01,100000,10))
    end
    N('SET_FOCUS_POS_AND_VEL',camera.pos.x,camera.pos.y,camera.pos.z,0.0,0.0,0.0)
    DR.apply(scene.director or D.defaults())
end
local function bakeFrame(frame)
    local pose=transformPose(frame,false)
    frame.pos,frame.rot=pose.pos,pose.rot
    if frame.take then
        for _,sample in ipairs(frame.take.samples) do
            local transformed=transformPose({pos={x=sample[2],y=sample[3],z=sample[4]},rot={x=sample[5],y=sample[6],z=sample[7]}},false)
            sample[2],sample[3],sample[4]=transformed.pos.x,transformed.pos.y,transformed.pos.z
            sample[5],sample[6],sample[7]=transformed.rot.x,transformed.rot.y,transformed.rot.z
        end
    end
    if attachment.rotate then
        for _,key in ipairs({'handleIn','handleOut'}) do
            if frame[key] then frame[key]=worldVector(attachment.current,localVector(attachment.reference,frame[key])) end
        end
    end
end
local function detach(silent)
    if not attachment then return end
    -- Bake the current entity transform so detaching never jumps the scene.
    for _,frame in ipairs(scene.frames) do
        bakeFrame(frame)
    end
    attachment=nil;clearInput();sceneRevision=sceneRevision+1;rebuildPath();sendScene()
    if not silent then toast('Camera detached') end
end
local function persistedFrame(pose)
    -- Playback samples carry transient timeHours; persist the public frame schema only.
    local frame=C.defaultFrame(pose.pos,pose.rot)
    frame.fov=pose.fov;frame.dof=C.copy(pose.dof)
    frame.weather=pose.weather;frame.hour=pose.hour;frame.minute=pose.minute
    return frame
end
local function recordedSample(pose,elapsed)
    return {elapsed,pose.pos.x,pose.pos.y,pose.pos.z,pose.rot.x,pose.rot.y,pose.rot.z,
        pose.fov,(pose.dof and pose.dof.focus) or 10,pose.hour or 12,pose.minute or 0,pose.weather or (isGta and 'CLEAR' or 'SUNNY')}
end
local function appendRecordedSample(tickTime,force)
    if not recordBuffer then return end
    local elapsed=math.min(recordBuffer.maxDuration,math.max(0,(tickTime-recordBuffer.started)/1000))
    local samples=recordBuffer.samples
    local sample=recordedSample(renderedCamera or camera,elapsed)
    local last=samples[#samples]
    if last and elapsed<=last[1] then
        if force then samples[#samples]=sample end
        return
    end
    -- Leave room for an exact final endpoint even at the maximum sample rate.
    if #samples>=recordBuffer.maxSamples-1 and not force then return end
    samples[#samples+1]=sample
end
recordFrame=function()
    if not recordBuffer or #recordBuffer.samples<2 then return end
    local samples=recordBuffer.samples
    local duration=samples[#samples][1]
    if duration<=0 then return end
    local frame=C.copy(recordBuffer.frame)
    frame.duration=duration;frame.transition='linear';frame.easing='linear'
    frame.take={duration=duration,samples=C.copy(samples)}
    return frame
end
local function appendTake(target,frame)
    local previous=target.frames[#target.frames]
    if previous and previous.duration==0 then previous.transition='cut' end
    target.frames[#target.frames+1]=frame
end
local function workspacePacket()
    return {cameras=savedCameras,presets=savedPresets,
        status=workspaceBlocked and 'disabled' or workspaceError and 'error'
            or (workspacePending or workspaceRevision>workspaceSavedRevision) and 'saving' or 'saved',
        error=workspaceError}
end
sendWorkspace=function() local packet=workspacePacket();packet.type='workspace';message(packet) end
markWorkspace=function()
    if not workspaceLoaded or workspaceBlocked then return end
    workspaceRevision=workspaceRevision+1
    if not workspaceDue then workspaceDue=now()+((flight or playing) and 2000 or 800) end
end
local function worldSceneSnapshot()
    local snapshotScene=C.copy(scene)
    -- Entity handles expire on reconnect. Store a world-space copy of the current route.
    if attachment then
        for _,frame in ipairs(snapshotScene.frames) do
            bakeFrame(frame)
        end
    end
    local take=recordFrame()
    if take then appendTake(snapshotScene,take) end
    return snapshotScene
end
local function workspaceSnapshot()
    if not camera then return nil,'No camera to save' end
    return D.validateWorkspace({version=1,scene=worldSceneSnapshot(),camera=persistedFrame(camera),
        settings=C.copy(settings),cameras=C.copy(savedCameras),presets=C.copy(savedPresets),time=timeline})
end
flushWorkspace=function(force)
    if not workspaceLoaded or workspaceBlocked or workspacePending or not camera
        or workspaceRevision<=workspaceSavedRevision then return end
    local tick=now()
    if tick-workspaceLastSent<650 or (not force and (not workspaceDue or tick<workspaceDue)) then return end
    local ok,payload,err=pcall(workspaceSnapshot)
    if not ok or not payload then
        workspaceError=type(err)=='string' and err or 'Workspace could not be prepared for saving'
        workspaceDue=tick+5000;sendWorkspace();return
    end
    workspaceSerial=workspaceSerial+1
    local id='workspace_'..tostring(tick)..'_'..workspaceSerial
    workspacePending={id=id,revision=workspaceRevision,at=tick};workspaceLastSent=tick;workspaceDue=nil
    local sent=pcall(bulkServerEvent,'arbat16_camera:workspaceSave',id,payload)
    if not sent then workspacePending=nil;workspaceError='Workspace save could not reach the server';workspaceDue=tick+5000 end
    sendWorkspace()
end
local function serviceWorkspace()
    if workspacePending and now()-workspacePending.at>30000 then
        workspacePending=nil;workspaceError='Workspace save timed out; retrying';workspaceDue=now()+2000;sendWorkspace()
    end
    flushWorkspace(false)
end
local function restoreWorkspace(packet)
    if workspaceLoaded then return end
    workspaceLoaded=true
    if type(packet)~='table' then return end
    if type(packet.workspaceError)=='string' then
        workspaceBlocked=true;workspaceError=packet.workspaceError:sub(1,300);return
    end
    if packet.workspace then
        local restored,err=D.validateWorkspace(packet.workspace)
        if not restored then workspaceBlocked=true;workspaceError=err or 'Saved workspace is invalid';return end
        scene=restored.scene;camera=restored.camera;settings=restored.settings
        savedCameras=restored.cameras;savedPresets=restored.presets;timeline=restored.time
        sceneRevision=sceneRevision+1
    end
end
local function attach(entity,mode,rotate)
    if not entity or entity==0 or not N('DOES_ENTITY_EXIST',entity) then return toast('No suitable target found','error') end
    detach(true)
    local matrix=entityBasis(entity)
    attachment={entity=entity,mode=mode,rotate=rotate==true,reference=matrix,current=matrix,
        freePose=C.copy(camera)}
    clearInput()
    toast('Camera attached to entity');sendState()
end
local function cleanup()
    requestedOpen=nil
    diagnosticDue=nil
    if aimProbe then aimProbe.cancelled=true end
    -- Release keyboard/mouse before any native call can fail. The fallback
    -- command remains useful even if camera/entity cleanup encounters an error.
    SetNuiFocus(false,false)
    if type(SetNuiFocusKeepInput)=='function' then pcall(SetNuiFocusKeepInput,false) end
    if not active and not cam then return end
    -- Saving is independent from native cleanup. It cannot prevent releasing controls.
    if recording and finishRecording then pcall(finishRecording,true) end
    if attachment then pcall(detach,true) end
    pcall(markWorkspace);pcall(flushWorkspace,true)
    active=false;playing=false;recording=false;flight=false;recordBuffer=nil;clearInput()
    rawPrevious={};rawBlocked={}
    if attachment then pcall(detach,true) end
    attachment=nil
    pcall(DR.cleanup)
    if cam then
        local oldCam=cam;cam=nil
        local ok,rendering=pcall(N,'GET_RENDERING_CAM')
        if ok and rendering==oldCam then
            local exists,previousExists=false,false
            if previousCam and previousCam~=0 then exists,previousExists=pcall(N,'DOES_CAM_EXIST',previousCam) end
            if exists and previousExists then
                pcall(N,'SET_CAM_ACTIVE',previousCam,true)
                pcall(N,'RENDER_SCRIPT_CAMS',true,false,0,true,false,0)
            else pcall(N,'RENDER_SCRIPT_CAMS',false,false,0,true,false,0) end
        end
        pcall(N,'DESTROY_CAM',oldCam,true)
    end
    pcall(N,'CLEAR_FOCUS')
    if player and cfg.FreezePlayer~=false and not previousFrozen then
        local ok,exists=pcall(N,'DOES_ENTITY_EXIST',player)
        if ok and exists then pcall(N,'FREEZE_ENTITY_POSITION',player,false) end
    end
    if environmentTouched then
        pcall(N,'NETWORK_CLEAR_CLOCK_TIME_OVERRIDE')
        if not isGta then pcall(N,'_SET_WEATHER_TYPE_FROZEN',false) end
        pcall(N,'CLEAR_OVERRIDE_WEATHER');pcall(N,'CLEAR_WEATHER_TYPE_PERSIST')
        if isGta then
            -- Release the network override before restoring the captured hash.
            -- SET_WEATHER_TYPE_NOW is explicitly unsupported in GTA network sessions.
            pcall(N,'CLEAR_WEATHER_TYPE_NOW_PERSIST_NETWORK',0)
            if previousWeather then pcall(N,'SET_CURR_WEATHER_STATE',previousWeather,previousWeather,0.0) end
        elseif GetResourceState('simple_weather')=='started' then TriggerServerEvent('simple_weather:request')
        elseif previousWeather then pcall(N,'SET_WEATHER_TYPE',previousWeather,true,true,true,0.5,false) end
    end
    environmentTouched=false;previousWeather=nil;lastWeather=nil;lastClock=nil;player=nil;previousCam=nil
    pending={}
    message({type='gizmos',points={},lines={}});message({type='close'})
end
local function open()
    if active or stopped then return end
    player=N('PLAYER_PED_ID')
    if player==0 or not N('DOES_ENTITY_EXIST',player) or entityDead(player) then player=nil;return end
    previousCam=N('GET_RENDERING_CAM')
    previousFrozen=N(isGta and 'IS_ENTITY_POSITION_FROZEN' or '_IS_ENTITY_FROZEN',player)
    local weatherHash=N(isGta and 'GET_PREV_WEATHER_TYPE_HASH_NAME' or '_GET_NEXT_WEATHER_TYPE_HASH_NAME')
    previousWeather=weatherHash
    local weatherName
    for name in pairs(weatherNames) do
        if N('GET_HASH_KEY',name:upper())==weatherHash then weatherName=name:upper();break end
    end
    local freshCamera=not camera
    if freshCamera then
        camera=C.defaultFrame(vec(N('GET_FINAL_RENDERED_CAM_COORD')),vec(N('GET_FINAL_RENDERED_CAM_ROT',2)))
        camera.fov=num(N('GET_FINAL_RENDERED_CAM_FOV'),1,130,50)
        camera.hour=N('GET_CLOCK_HOURS');camera.minute=N('GET_CLOCK_MINUTES')
        if weatherName then camera.weather=weatherName end
    end
    -- Retain the saved shot if the player reconnects far away. Do not silently overwrite it.
    if not poseWithinReach(camera) then
        player=nil;return toast('Your saved camera is beyond the distance limit. Move closer, or use /ar16_camresetview to open at the player. Saved cameras and scenes are retained.','error')
    end
    cam=N('CREATE_CAM','DEFAULT_SCRIPTED_CAMERA',true)
    if not cam or cam==0 or not N('DOES_CAM_EXIST',cam) then
        cam=nil;player=nil;return toast('Could not create the camera','error')
    end
    active=true;timeline=C.clamp(timeline,0,C.duration(scene));flight=false;playing=false;recording=false;lastClock=nil;lastWeather=nil;motionElapsed=0
    tickCount=0;inputPackets=0;nativeInputTicks=0;lastTickAt=nil;lastFrameTime=nil;lastRuntimeError=nil
    nextState=0;nextGizmos=0;nextEnvironment=0;clearInput()
    N('SET_CAM_NEAR_CLIP',cam,0.05);applyCamera()
    N('SET_CAM_ACTIVE',cam,true);N('RENDER_SCRIPT_CAMS',true,false,0,true,false,0)
    if cfg.FreezePlayer~=false and not previousFrozen then N('FREEZE_ENTITY_POSITION',player,true) end
    cameraFocus()
    rebuildPath()
    message({type='open',game=game,scene=scene,settings=settings,camera=camera,workspace=workspacePacket(),revision=sceneRevision,stateSequence=stateSequence,
        capabilities={focusDistance=true,dofBlur=isGta,projectedPath=true,nativeFlightInput=nativeFlightInput}})
    sendState()
    if not freshCamera then environment(true) end
    markWorkspace()
    diagnose('open',false)
end
local function guard(fn)
    local ok,result,detail=xpcall(fn,debug.traceback)
    if not ok then
        lastRuntimeError=tostring(result)
        print('[arbat16_camera] '..tostring(result));pcall(cleanup)
        toast('Camera error: controls restored. See F8 for details.','error')
    end
    return ok,result,detail
end
local function safeScene(raw,quiet)
    local value,err=C.validateScene(raw)
    if value and #value.frames>(cfg.MaxFrames or 200) then value=nil;err='Scene exceeds the keyframe limit' end
    if not value then
        err=err or 'Invalid scene'
        if not quiet then toast(err,'error') end
        return nil,err
    end
    return value
end
finishRecording=function(quiet)
    if not recording or not recordBuffer then return true end
    appendRecordedSample(now(),true)
    local frame=recordFrame()
    -- The buffer contains the world positions actually rendered during the take.
    -- Bake an attachment's authored route before adding that independent world path.
    if attachment then detach(true) end
    if frame then
        local candidate=C.copy(scene);appendTake(candidate,frame)
        local value,err=safeScene(candidate,true)
        if not value then return false,err end
        scene=value;sceneRevision=sceneRevision+1
    end
    recording=false;recordBuffer=nil
    if frame then
        rebuildPath();sendScene(frame.id)
        if not quiet then toast(('Recorded take saved (%.2f s)'):format(frame.duration)) end
    end
    markWorkspace();sendState();return true
end
local function updateScene(raw,selectedId)
    if recording then return false,'Stop recording before editing the timeline' end
    local value,err=safeScene(raw,true);if not value then return false,err end
    scene=value;timeline=C.clamp(timeline,0,C.duration(scene));playing=false;recording=false
    settings.letterbox=(scene.director or D.defaults()).framing.ratio~='native'
    sceneRevision=sceneRevision+1
    rebuildPath();sendScene(selectedId);sendState();return true
end
local function capture(replaceId,quiet)
    if recording then return toast('Stop REC before adding a separate keyframe') end
    if not camera then return end
    local frame=C.defaultFrame(camera.pos,camera.rot)
    local pose=transformPose(camera,true)
    frame.pos,frame.rot=pose.pos,pose.rot
    frame.fov=camera.fov;frame.dof=C.copy(camera.dof)
    frame.weather=camera.weather;frame.hour=camera.hour;frame.minute=camera.minute
    local index
    if type(replaceId)=='string' then for i,v in ipairs(scene.frames) do if v.id==replaceId then index=i;break end end end
    if replaceId and not index then return toast('Keyframe to replace was not found','error') end
    if not index and #scene.frames>=(cfg.MaxFrames or 200) then
        recording=false;return toast('Keyframe limit reached','error')
    end
    sequence=sequence+1
    frame.id=index and scene.frames[index].id or ('frame_%d_%d'):format(now(),sequence)
    frame.label=index and scene.frames[index].label or ('Keyframe %02d'):format(#scene.frames+1)
    local nextScene=C.copy(scene)
    if index then
        local old=scene.frames[index]
        frame.duration=old.duration;frame.easing=old.easing;frame.transition=old.transition
        frame.handleIn=old.handleIn;frame.handleOut=old.handleOut
        nextScene.frames[index]=frame
    else
        local previous=nextScene.frames[#nextScene.frames]
        if previous and previous.duration==0 and previous.transition~='cut' then previous.transition='cut' end
        nextScene.frames[#nextScene.frames+1]=frame
    end
    local validated=safeScene(nextScene)
    if not validated then recording=false;return end
    scene=validated;sceneRevision=sceneRevision+1
    rebuildPath();sendScene(frame.id)
    if not quiet then toast(index and 'Keyframe updated' or 'Keyframe added') end
    sendState()
end
local function seek(time)
    if not finite(time) then return false,'Seek time must be a finite number' end
    if recording then local ok,err=finishRecording(true);if not ok then return false,err end end
    local total=C.duration(scene)
    local targetTime=C.clamp(time,0,total)
    local sampleScene=scene
    if targetTime>=total and scene.loop then sampleScene=C.copy(scene);sampleScene.loop=false end
    local pose=C.sample(sampleScene,targetTime)
    if pose then
        pose=transformPose(pose,false)
        if not poseWithinReach(pose) then playing=false;sendState();return false,'Keyframe is beyond the camera distance limit' end
        camera=pose
        if attachment then attachment.freePose=transformPose(camera,true) end
        applyCamera();environment(true)
    end
    clearInput();timeline=targetTime;sendState();return true
end
local function storage(op,data)
    if op=='load' and recording then return toast('Stop REC before loading another scene','error') end
    local name=type(data.name)=='string' and data.name or scene.name
    if op~='list' and (type(name)~='string' or #name<1 or #name>64 or name:find('[%z\1-\31\127/\\]')) then
        return toast('Use a name of up to 64 UTF-8 bytes without slashes or control characters','error')
    end
    local count=0;for _ in pairs(pending) do count=count+1 end
    if count>=4 then return toast('Wait for the pending storage requests','error') end
    sequence=sequence+1;local id=('req_%d_%d'):format(now(),sequence)
    local payload={name=name}
    if op=='save' then
        if recording then local ok,err=finishRecording(true);if not ok then return toast(err,'error') end end
        payload.scene=worldSceneSnapshot();payload.scene.name=name
        if not safeScene(payload.scene) then return end
    end
    pending[id]={at=now(),op=op,name=name,revision=sceneRevision}
    if op=='save' then bulkServerEvent('arbat16_camera:storage',id,op,payload)
    else TriggerServerEvent('arbat16_camera:storage',id,op,payload) end
end
local actions={}
actions.close=function() cleanup() end
actions.flight=function(data)
    if type(data.enabled)~='boolean' then return end
    setFlight(data.enabled)
end
actions.input=function(data)
    if nativeFlightInput or not flight or type(data.keys)~='table' or #data.keys>16 then return end
    inputPackets=inputPackets+1
    local nextKeys={}
    for _,key in ipairs(data.keys) do if type(key)=='string' and allowedKeys[key] then nextKeys[key]=true end end
    keys=nextKeys;inputAt=now()
    lookX=C.clamp(lookX+num(data.dx,-500,500,0),-1000,1000)
    lookY=C.clamp(lookY+num(data.dy,-500,500,0),-1000,1000)
end
actions.capture=function(data) capture(data.replaceId) end
actions.scene=function(data) return updateScene(data.scene,data.selectedId) end
actions.setCamera=function(data)
    if type(data.frame)~='table' then return false,'A camera keyframe is required' end
    local value,err=safeScene({version=1,name='Preview',frames={data.frame},loop=false,speed=1},true)
    if not value then return false,err end
    local pose=transformPose(value.frames[1].take and C.sample(value,0) or value.frames[1],false)
    if not poseWithinReach(pose) then return false,'Keyframe is beyond the camera distance limit' end
    if recording then local ok,err=finishRecording(true);if not ok then return false,err end end
    camera=pose;playing=false;clearInput()
    if attachment then attachment.freePose=transformPose(camera,true) end
    applyCamera();environment(true);sendState();return true
end
actions.play=function()
    if recording then local ok,err=finishRecording(true);if not ok then return false,err end end
    if #scene.frames==0 then return false,'Add at least one keyframe' end
    recording=false;flight=false;clearInput()
    cameraFocus()
    if timeline>=C.duration(scene) then timeline=0 end
    playing=true
    local ok,err=seek(timeline)
    diagnose('play',ok)
    return ok,err
end
actions.pause=function() playing=false;sendState() end
actions.stop=function() playing=false;return seek(0) end
actions.seek=function(data) playing=false;return seek(data.time) end
actions.record=function(data)
    if type(data.enabled)~='boolean' then return end
    if recording==data.enabled then sendState();return end
    if not data.enabled then return finishRecording(false) end
    if #scene.frames>=(cfg.MaxFrames or 200) then return false,'Timeline is full; remove a clip before recording' end
    local sampleCount=0
    for _,frame in ipairs(scene.frames) do if frame.take then sampleCount=sampleCount+#frame.take.samples end end
    if sampleCount>18000 then return false,'Recorded sample limit reached; start another scene' end
    local remaining=3600-C.duration(scene)
    if remaining<=0 then return false,'Scene duration limit reached; start another scene' end
    sequence=sequence+1
    local first=renderedCamera or camera
    local frame=persistedFrame(first)
    frame.id=('take_%d_%d'):format(now(),sequence);frame.label=('Recorded take %02d'):format(#scene.frames+1)
    recordBuffer={started=now(),frame=frame,samples={recordedSample(first,0)},
        maxDuration=math.min(300,remaining),maxSamples=math.min(9001,18002-sampleCount)}
    recording=true;playing=false
    nextRecord=now()+math.max(1000/30,cfg.RecordInterval or 1000/30)
    markWorkspace();sendState();return true
end
actions.settings=function(data)
    -- Validate the complete prospective state before changing any setting,
    -- camera smoothing, or scene framing. Invalid mixed edits cannot partly apply.
    if type(data)~='table' or getmetatable(data)~=nil then return false,'Invalid camera settings' end
    local draft=C.copy(settings)
    for key,value in pairs(data) do if key~='action' then draft[key]=value end end
    local validated,err=D.validateSettings(draft)
    if not validated then return false,err end
    local stabilizationChanged=validated.stabilization~=settings.stabilization
    settings=validated
    if stabilizationChanged then clearInput() end
    if data.letterbox~=nil then
        scene.director=scene.director or D.defaults()
        scene.director.framing.ratio=data.letterbox and '2.39' or 'native'
        sceneRevision=sceneRevision+1;sendScene()
    end
    sendState()
end
actions.toggleGrid=function()
    settings.grid=not settings.grid
    sendState();markWorkspace();sendWorkspace()
    toast(settings.grid and 'Composition guides on' or 'Composition guides off')
end
actions.cycleStabilization=function()
    settings.stabilization=F.cycle(settings.stabilization)
    clearInput();sendState();markWorkspace();sendWorkspace()
    local label=settings.stabilization:gsub('^%l',string.upper)
    toast('Stabilization: '..label)
end
actions.lens=function(data)
    if isGta and recording and type(data.dof)=='table' then
        -- A take records focus per sample; its DOF enable/strength are fixed
        -- on the starting frame. Reject changes before mutating any lens field.
        local dof=camera.dof or {enabled=false,strength=0.5}
        local changedEnabled=type(data.dof.enabled)=='boolean' and data.dof.enabled~=(dof.enabled==true)
        local changedStrength=finite(data.dof.strength) and C.clamp(data.dof.strength,0,1)~=(dof.strength or 0.5)
        if changedEnabled or changedStrength then return false,'Stop REC before changing depth of field or blur strength' end
    end
    if finite(data.fov) then camera.fov=C.clamp(data.fov,1,130) end
    if finite(data.roll) then camera.rot.y=C.clamp(data.roll,-180,180) end
    if type(data.dof)=='table' then
        camera.dof=camera.dof or {enabled=false,focus=10,near=1,far=100,strength=0.5}
        if isGta and type(data.dof.enabled)=='boolean' then camera.dof.enabled=data.dof.enabled end
        if finite(data.dof.focus) then camera.dof.focus=C.clamp(data.dof.focus,0.1,1000) end
        if isGta and finite(data.dof.strength) then camera.dof.strength=C.clamp(data.dof.strength,0,1) end
    end
    if attachment then attachment.freePose=transformPose(camera,true) end
    applyCamera();sendState()
end
actions.environment=function(data)
    if type(data.weather)=='string' and weatherNames[data.weather:lower()] then camera.weather=data.weather:upper() end
    if finite(data.hour) then camera.hour=math.floor(C.clamp(data.hour,0,23)) end
    if finite(data.minute) then camera.minute=math.floor(C.clamp(data.minute,0,59)) end
    if attachment then attachment.freePose=transformPose(camera,true) end
    environment(true);sendState()
end
actions.attach=function(data)
    if data.mode=='detach' then detach();sendState()
    elseif data.mode=='player' then attach(player,'player',data.rotate)
    elseif isGta and data.mode=='vehicle' then
        local entity=N('GET_VEHICLE_PED_IS_IN',player,false)
        attach(entity,'vehicle',data.rotate)
    elseif not isGta and data.mode=='mount' then
        local entity=N('GET_MOUNT',player)
        if entity==0 then entity=N('GET_VEHICLE_PED_IS_IN',player,false) end
        attach(entity,'mount',data.rotate)
    elseif data.mode=='aim' and not aimProbe then
        local direction=basis(camera.rot).forward
        local target=add(camera.pos,mul(direction,200.0))
        local handle=N('START_SHAPE_TEST_LOS_PROBE',camera.pos.x,camera.pos.y,camera.pos.z,target.x,target.y,target.z,31,player,7)
        if handle and handle~=0 then aimProbe={handle=handle,rotate=data.rotate==true,at=now()} end
    end
end
actions.dragHandle=function(data)
    if data.kind~='in' and data.kind~='out' then return end
    if not finite(data.dx) or not finite(data.dy) then return end
    local frame
    for _,f in ipairs(scene.frames) do if f.id==data.id then frame=f;break end end
    if not frame then return end
    -- dx/dy are normalized viewport deltas; distance scales screen movement.
    local depth=math.max(1,length(sub(transformedPoint(frame.pos),camera.pos)))
    local b=basis(camera.rot);local scale=2*depth*math.tan(math.rad(camera.fov/2))
    local offset=add(mul(b.right,C.clamp(data.dx,-0.25,0.25)*scale),mul(b.up,-C.clamp(data.dy,-0.25,0.25)*scale))
    if attachment and attachment.rotate then offset=worldVector(attachment.reference,localVector(attachment.current,offset)) end
    local key=data.kind=='in' and 'handleIn' or 'handleOut'
    local old=frame[key] or {x=0,y=0,z=0}
    local p=add(old,offset)
    frame[key]={x=C.clamp(p.x,-10000,10000),y=C.clamp(p.y,-10000,10000),z=C.clamp(p.z,-10000,10000)}
    sceneRevision=sceneRevision+1
    rebuildPath();sendScene(frame.id)
end
actions.save=function(data) storage('save',data) end
actions.list=function(data) storage('list',data) end
actions.load=function(data) storage('load',data) end
actions.delete=function(data) storage('delete',data) end
local function entryName(value)
    if type(value)~='string' or #value>64 or not utf8.len(value) or value:find('[%z\1-\31\127/\\]') then return nil end
    for _,code in utf8.codes(value) do if code>=127 and code<=159 then return nil end end
    value=value:match('^%s*(.-)%s*$')
    return value~='' and value~='.' and value~='..' and value or nil
end
local function findEntry(entries,id)
    for index,entry in ipairs(entries) do if entry.id==id then return entry,index end end
end
local function entryId(prefix,entries)
    local id
    repeat sequence=sequence+1;id=('%s_%d_%d'):format(prefix,now(),sequence) until not findEntry(entries,id)
    return id
end
local function setDirector(raw)
    local director,err=D.validate(raw)
    if not director then return false,err end
    scene.director=director;settings.letterbox=director.framing.ratio~='native'
    sceneRevision=sceneRevision+1;motionElapsed=0
    DR.apply(director);sendScene();sendState();return true
end
actions.director=function(data) return setDirector(data.director) end
actions.cameraSave=function(data)
    local name=entryName(data.name)
    if not name then return false,'Use a camera name of 1 to 64 bytes without slashes or control characters' end
    local old,index=findEntry(savedCameras,data.id)
    if data.id and not old then return false,'Saved camera was not found' end
    if not old and #savedCameras>=100 then return false,'The camera bank is full (100 cameras)' end
    local entry={id=old and old.id or entryId('camera',savedCameras),name=name,
        frame=persistedFrame(camera),director=C.copy(scene.director or D.defaults())}
    savedCameras[index or #savedCameras+1]=entry
    sendWorkspace();toast(old and 'Saved camera updated' or 'Camera added to bank');return true
end
actions.cameraRecall=function(data)
    local entry=findEntry(savedCameras,data.id)
    if not entry then return false,'Saved camera was not found' end
    if not poseWithinReach(entry.frame) then return false,'Saved camera is beyond the camera distance limit' end
    if recording then local ok,err=finishRecording(true);if not ok then return false,err end end
    detach(true);playing=false;recording=false;flight=false;clearInput();cameraFocus()
    camera=C.copy(entry.frame);clearInput();setDirector(entry.director);applyCamera();environment(true);sendState();return true
end
actions.cameraDelete=function(data)
    local entry,index=findEntry(savedCameras,data.id)
    if not entry then return false,'Saved camera was not found' end
    table.remove(savedCameras,index);sendWorkspace();return true
end

actions.cameraAdd=function(data)
    if recording then return false,'Stop recording before adding a camera to the timeline' end
    local entry=findEntry(savedCameras,data.id)
    if not entry then return false,'Saved camera was not found' end
    if #scene.frames>=(cfg.MaxFrames or 200) then return false,'The timeline is full' end
    if not poseWithinReach(entry.frame) then return false,'Saved camera is beyond the camera distance limit' end
    if data.duration~=nil and (not finite(data.duration) or data.duration<=0 or data.duration>600) then
        return false,'Choose a shot duration between 0 and 600 seconds'
    end
    local insertion=#scene.frames+1
    if data.beforeId~=nil then
        local _,index=findEntry(scene.frames,data.beforeId)
        if not index then return false,'The target clip was not found' end
        insertion=index
    end
    local nextScene=C.copy(scene)
    local frame=transformPose(entry.frame,true)
    frame.id=entryId('shot',nextScene.frames);frame.label=entry.name
    frame.duration=data.duration or 3;frame.transition='hold';frame.easing='linear'
    table.insert(nextScene.frames,insertion,frame)
    for i=1,#nextScene.frames-1 do
        if nextScene.frames[i].duration==0 then nextScene.frames[i].transition='cut' end
    end
    local ok,err=updateScene(nextScene,frame.id)
    if ok then toast('Camera added to timeline. Drag clips to change their order.') end
    return ok,err
end
actions.presetSave=function(data)
    local name=entryName(data.name)
    if not name then return false,'Use a preset name of 1 to 64 bytes without slashes or control characters' end
    local old,index=findEntry(savedPresets,data.id)
    if data.id and not old then return false,'Custom preset was not found' end
    if not old and #savedPresets>=40 then return false,'The preset library is full (40 presets)' end
    savedPresets[index or #savedPresets+1]={id=old and old.id or entryId('preset',savedPresets),name=name,
        director=C.copy(scene.director or D.defaults()),fov=camera.fov,focus=camera.dof.focus}
    sendWorkspace();toast(old and 'Preset updated' or 'Preset saved');return true
end
actions.presetApply=function(data)
    local preset=findEntry(savedPresets,data.id) or findEntry(D.presets,data.id)
    if not preset then return false,'Preset was not found' end
    playing=false;camera.fov=preset.fov;camera.dof.focus=preset.focus
    if attachment then attachment.freePose=transformPose(camera,true) end
    setDirector(preset.director);applyCamera();return true
end
actions.presetDelete=function(data)
    local preset,index=findEntry(savedPresets,data.id)
    if not preset then return false,'Custom preset was not found' end
    table.remove(savedPresets,index);sendWorkspace();return true
end
actions.generateMove=function(data)
    if recording then return false,'Stop recording before adding a camera move' end
    local frames,err=D.generateMove(persistedFrame(camera),{kind=data.kind,distance=data.distance,angle=data.angle,
        duration=data.duration,returnToStart=data.returnToStart})
    if not frames then return false,err end
    if #scene.frames+#frames>(cfg.MaxFrames or 200) then return false,'This move would exceed the keyframe limit' end
    for _,frame in ipairs(frames) do if not poseWithinReach(frame) then return false,'This move exceeds the camera distance limit' end end
    local nextScene=C.copy(scene)
    -- Convert into attachment coordinates without detaching or changing the existing clip.
    for _,frame in ipairs(frames) do
        local pose=transformPose(frame,true);frame.pos,frame.rot=pose.pos,pose.rot
        frame.id=entryId('move',nextScene.frames)
        nextScene.frames[#nextScene.frames+1]=frame
    end
    local previous=nextScene.frames[#scene.frames]
    if previous and previous.duration==0 and previous.transition~='cut' then previous.transition='cut' end
    local ok,detail=updateScene(nextScene,frames[1].id)
    if ok then toast('Camera move added. Enable Loop to repeat it.') end
    return ok,detail
end
actions.workspaceReset=function()
    if not workspaceBlocked then return false,'Workspace reset is only available when recovery is required' end
    if workspacePending then return false,'Wait for the current save request' end
    workspaceSerial=workspaceSerial+1
    local id='reset_'..now()..'_'..workspaceSerial
    workspacePending={id=id,revision=workspaceRevision,at=now(),reset=true}
    TriggerServerEvent('arbat16_camera:workspaceReset',id);sendWorkspace();return true
end
local readOnlyActions={input=true,list=true,delete=true,workspaceReset=true}
RegisterNUICallback('action',function(data,cb)
    if type(data)~='table' or type(data.action)~='string' or #data.action>32 then cb({ok=false,error='Invalid action',revision=sceneRevision,stateSequence=stateSequence});return end
    if data.action=='ready' then
        uiReady=true;cb({ok=true,revision=sceneRevision,stateSequence=stateSequence})
        if active then message({type='open',game=game,scene=scene,settings=settings,camera=camera,workspace=workspacePacket(),revision=sceneRevision,stateSequence=stateSequence,
            capabilities={focusDistance=true,dofBlur=isGta,projectedPath=true,nativeFlightInput=nativeFlightInput}});sendState() end
        return
    end
    local handler=actions[data.action]
    if not active or not handler then cb({ok=false,error='Camera is closed or action is unknown',revision=sceneRevision,stateSequence=stateSequence});return end
    -- Validation completes before acknowledgement so NUI can roll back edits.
    -- Storage handlers still only enqueue asynchronous server work here.
    local ok,result,err=guard(function() return handler(data) end)
    if not ok then cb({ok=false,error='Camera error. Controls restored; see F8 for details.',revision=sceneRevision,stateSequence=stateSequence})
    elseif result==false then cb({ok=false,error=err or 'Action rejected',revision=sceneRevision,stateSequence=stateSequence})
    else
        if not readOnlyActions[data.action] then markWorkspace();sendWorkspace() end
        cb({ok=true,revision=sceneRevision,stateSequence=stateSequence})
    end
end)
RegisterNetEvent('arbat16_camera:openAllowed',function(allowed,packet)
    if not requestedOpen or now()-requestedOpen>30000 then return end
    requestedOpen=nil
    if allowed==true then guard(function() restoreWorkspace(packet);open() end) else toast('You do not have permission to use the camera','error') end
end)
RegisterNetEvent('arbat16_camera:workspaceResult',function(id,result)
    if not workspacePending or workspacePending.id~=id or type(result)~='table' then return end
    local request=workspacePending;workspacePending=nil
    if result.ok==true then
        workspaceError=nil
        if request.reset then
            workspaceBlocked=false;markWorkspace();workspaceDue=now()+800
        else workspaceSavedRevision=request.revision end
        if workspaceRevision>workspaceSavedRevision and not workspaceDue then workspaceDue=now()+800 end
    else
        workspaceError=type(result.error)=='string' and result.error:sub(1,300) or 'Workspace save failed'
        workspaceDue=now()+5000
    end
    sendWorkspace()
end)
RegisterNetEvent('arbat16_camera:storageResult',function(id,result)
    if type(id)~='string' or not pending[id] or type(result)~='table' then return end
    local request=pending[id];pending[id]=nil
    if result.ok~=true then return toast(type(result.error)=='string' and result.error:sub(1,300) or 'Storage request failed','error') end
    if request.op=='load' and result.scene then
        if recording then
            toast('Recording started while loading. Stop REC, then load the scene again.','error')
        elseif request.revision~=sceneRevision then
            toast('Scene changed while loading. Load again to replace your edits.','error')
        elseif safeScene(result.scene) then detach(true);updateScene(result.scene) end
    elseif request.op=='save' then
        if request.revision==sceneRevision then
            scene.name=type(result.name)=='string' and result.name or request.name
            sceneRevision=sceneRevision+1;sendScene();toast('Scene saved')
        else toast('Earlier scene version saved; current changes are not saved') end
    elseif request.op=='delete' then toast('Scene deleted') end
    if type(result.items)=='table' then message({type='library',items=result.items}) end
    markWorkspace()
end)
if not isGta then RegisterNetEvent('simple_weather:sync',function()
    if active and environmentTouched then
        -- Let the weather resource finish its current handler, then reapply the
        -- editor override. Closing requests a fresh authoritative server sync.
        SetTimeout(50,function() if active then guard(function() environment(true) end) end end)
    end
end) end
RegisterCommand(cfg.Command or 'ar16_cam',function()
    if active then cleanup();return end
    if requestedOpen and now()-requestedOpen<2000 then return end
    requestedOpen=now();TriggerServerEvent('arbat16_camera:requestOpen')
end,false)
RegisterCommand((cfg.Command or 'ar16_cam')..'close',function() cleanup() end,false)
if (cfg.Command or 'ar16_cam')~='ar16_cam' then RegisterCommand('ar16_camclose',function() cleanup() end,false) end
RegisterCommand('ar16_camresetview',function()
    if active then cleanup() end
    camera=nil;timeline=0
    -- Loading a workspace is intentionally completed first; resetting the view never deletes scenes or bookmarks.
    if not workspaceLoaded then
        toast('Open /ar16_cam once before resetting the saved view','error');return
    end
    requestedOpen=now();TriggerServerEvent('arbat16_camera:requestOpen')
end,false)

-- Read-only diagnostics: useful on a player's F8 console without enabling
-- recurring logs, exposing server configuration, or changing camera ownership.
reportRuntime=function(event)
    event=type(event)=='string' and event or 'manual'
    local function read(name,...)
        local ok,value=pcall(N,name,...)
        if ok then return value end
    end
    local function position(p)
        if not p then return 'unavailable' end
        return ('%.3f, %.3f, %.3f'):format(p.x,p.y,p.z)
    end
    local tick=read('GET_GAME_TIMER')
    local held=0;for _ in pairs(keys) do held=held+1 end
    local changedSegments=0
    for i=2,#scene.frames do
        local a,b=scene.frames[i-1],scene.frames[i]
        if length(sub(a.pos,b.pos))>0.001 or length(sub(a.rot,b.rot))>0.001 or math.abs(a.fov-b.fov)>0.001 then
            changedSegments=changedSegments+1
        end
    end
    local exists=cam and read('DOES_CAM_EXIST',cam) or false
    local nativePosition=exists and read('GET_CAM_COORD',cam) or nil
    local cameraActive=exists and read('IS_CAM_ACTIVE',cam) or false
    local cameraRendering=exists and read('IS_CAM_RENDERING',cam) or false
    local renderingCamera=read('GET_RENDERING_CAM')
    print(('[arbat16_camera] event=%s active=%s flight=%s playing=%s recording=%s uiReady=%s'):format(event,
        tostring(active),tostring(flight),tostring(playing),tostring(recording),tostring(uiReady)))
    print(('[arbat16_camera] camera=%s exists=%s cameraActive=%s cameraRendering=%s renderingCamera=%s'):format(
        tostring(cam),tostring(exists),tostring(cameraActive),tostring(cameraRendering),tostring(renderingCamera)))
    print(('[arbat16_camera] targetPosition=(%s) nativePosition=(%s)'):format(
        position(camera and camera.pos),position(nativePosition)))
    print(('[arbat16_camera] ticks=%d tickAgeMs=%s inputPackets=%d inputAgeMs=%s heldKeys=%d nativeInputTicks=%d nativeFlightInput=%s frameTime=%s'):format(
        tickCount,tostring(tick and lastTickAt and tick-lastTickAt or 'none'),inputPackets,
        tostring(tick and inputAt~=0 and tick-inputAt or 'none'),held,nativeInputTicks,tostring(nativeFlightInput),tostring(lastFrameTime)))
    print(('[arbat16_camera] keyframes=%d changedPoseSegments=%d time=%.3f duration=%.3f speed=%.2f revision=%d'):format(
        #scene.frames,changedSegments,timeline,C.duration(scene),scene.speed,sceneRevision))
    if #scene.frames>1 and changedSegments==0 then
        print('[arbat16_camera] Keyframes share one position, rotation and FOV. Fly to a different angle before capturing the next keyframe.')
    end
    if lastRuntimeError then print('[arbat16_camera] Last runtime error: '..lastRuntimeError) end
    if cfg.Diagnostics==true then
        TriggerServerEvent('arbat16_camera:diagnostic',{event=event,active=active,flight=flight,
            playing=playing,recording=recording,uiReady=uiReady,camera=cam,exists=exists,
            cameraActive=cameraActive,cameraRendering=cameraRendering,renderingCamera=renderingCamera,
            targetPosition=camera and vec(camera.pos) or nil,nativePosition=nativePosition and vec(nativePosition) or nil,
            ticks=tickCount,tickAgeMs=tick and lastTickAt and tick-lastTickAt or nil,inputPackets=inputPackets,
            inputAgeMs=tick and inputAt~=0 and tick-inputAt or nil,heldKeys=held,nativeInputTicks=nativeInputTicks,
            nativeFlightInput=nativeFlightInput,frameTime=lastFrameTime,keyframes=#scene.frames,
            changedPoseSegments=changedSegments,time=timeline,duration=C.duration(scene),speed=scene.speed,
            revision=sceneRevision,stateSequence=stateSequence})
    end
end
RegisterCommand((cfg.Command or 'ar16_cam')..'debug',function() safeReportRuntime('manual') end,false)
if (cfg.Command or 'ar16_cam')~='ar16_cam' then RegisterCommand('ar16_camdebug',function() safeReportRuntime('manual') end,false) end

local function pollNativeFlightInput()
    if not nativeFlightInput or not flight then return end
    local raw=rawSnapshot()
    local focused=type(IsNuiFocused)=='function' and IsNuiFocused()
    -- Raw key states can remain held when another NUI takes focus (Cfx #3064).
    -- Suspend input, and require held keys to be released before accepting them.
    if focused==true or focused==1 or N('IS_PAUSE_MENU_ACTIVE') then
        clearInput();rawPrevious=raw;rawBlocked=C.copy(raw);return
    end
    nativeInputTicks=nativeInputTicks+1
    local pressed={}
    for key,down in pairs(raw) do
        if not down then rawBlocked[key]=false end
        pressed[key]=down and not rawPrevious[key] and not rawBlocked[key]
    end
    rawPrevious=raw
    if pressed.Escape then cleanup();return end
    if pressed.Tab then setFlight(false);return end
    if pressed.F1 then setFlight(false);message({type='help'});return end
    if pressed.Space then
        local ok,err=actions.play()
        if ok==false then toast(err,'error') end
        return
    end
    if pressed.KeyF then capture() end
    if pressed.KeyG then actions.toggleGrid() end
    if pressed.KeyH then message({type='toggleClean'}) end
    if pressed.KeyJ then actions.cycleStabilization() end
    if pressed.KeyR then
        local ok,err=actions.record({enabled=not recording})
        if ok==false then toast(err or 'Recording could not start','error') end
    end
    local nextKeys={}
    for key in pairs(allowedKeys) do if raw[key] and not rawBlocked[key] then nextKeys[key]=true end end
    keys=nextKeys;inputAt=now()
    -- Game-specific INPUT_LOOK_LR / INPUT_LOOK_UD. Disabled controls remain readable
    -- after gameplay actions are disabled, while NUI no longer owns the mouse.
    lookX=num(N('GET_DISABLED_CONTROL_NORMAL',0,isGta and 1 or 0xA987235F),-1,1,0)*100.0
    lookY=num(N('GET_DISABLED_CONTROL_NORMAL',0,isGta and 2 or 0xD2047988),-1,1,0)*100.0
end

local function pollAim()
    if not aimProbe then return end
    local status,hit,_,_,entity=N('GET_SHAPE_TEST_RESULT',aimProbe.handle,Citizen.PointerValueInt(),
        Citizen.PointerValueVector(),Citizen.PointerValueVector(),Citizen.PointerValueInt())
    if status==0 or status==2 then
        local old=aimProbe;aimProbe=nil
        if not active or old.cancelled then return end
        if status==2 and (hit==true or hit==1) and entity and entity~=0 and N('DOES_ENTITY_EXIST',entity)
            and (N('GET_ENTITY_TYPE',entity)==1 or N('GET_ENTITY_TYPE',entity)==2) then attach(entity,'aim',old.rotate)
        else toast(isGta and 'Aim the center of the camera at a character or vehicle' or 'Aim the center of the camera at a character, horse or wagon','error') end
    elseif now()-aimProbe.at>1500 then
        -- Shape tests have no documented cancellation native. Abandon a stalled
        -- handle after a bounded poll so another attachment request can proceed.
        aimProbe=nil
        if active then toast('Target detection timed out. Aim and try again.','error') end
    end
end
local function tick()
    pollAim()
    if not active then return end
    if not player or N('PLAYER_PED_ID')~=player or not N('DOES_ENTITY_EXIST',player) or entityDead(player) then cleanup();return end
    local tickTime=now();local frameTime=num(N('GET_FRAME_TIME'),0,10,0.016)
    local oldPosition,oldRotation=C.copy(camera.pos),C.copy(camera.rot)
    motionElapsed=motionElapsed+frameTime
    tickCount=tickCount+1;lastTickAt=tickTime;lastFrameTime=frameTime
    -- Clamp interactive travel after a stall, but preserve real playback timing.
    local dt=math.min(frameTime,0.1)
    N('DISABLE_ALL_CONTROL_ACTIONS',0)
    if settings.hideHud then N('HIDE_HUD_AND_RADAR_THIS_FRAME') end
    pollNativeFlightInput()
    if not active then return end
    if attachment then
        if not N('DOES_ENTITY_EXIST',attachment.entity) then detach();toast('The attached entity no longer exists','error')
        else attachment.current=entityBasis(attachment.entity) end
    end
    if playing then
        local total=C.duration(scene)
        timeline=timeline+frameTime*num(scene.speed,0.1,8,1)
        if total<=0 then playing=false;timeline=0
        elseif timeline>=total then
            if scene.loop then timeline=timeline%total else timeline=total;playing=false end
        end
        local pose=C.sample(scene,timeline)
        if pose then
            pose=transformPose(pose,false)
            if poseWithinReach(pose) then camera=pose
            else playing=false;toast('Playback stopped at the camera distance limit','error') end
        end
        if attachment then attachment.freePose=transformPose(camera,true) end
    elseif attachment then camera=transformPose(attachment.freePose,false) end
    if flight and not playing then
        if tickTime-inputAt>500 then clearInput() end
        camera.rot=F.rotate(flightSmoothing,camera.rot,-lookX*(cfg.LookSensitivity or 0.12),
            -lookY*(cfg.LookSensitivity or 0.12),dt,settings.stabilization)
        lookX=0;lookY=0
        local b=basis(camera.rot)
        local forward=(keys.KeyW and 1 or 0)-(keys.KeyS and 1 or 0)
        local strafe=(keys.KeyD and 1 or 0)-(keys.KeyA and 1 or 0)
        local vertical=(keys.KeyE and 1 or 0)-(keys.KeyQ and 1 or 0)
        local direction=add(add(mul(b.forward,forward),mul(b.right,strafe)),{x=0,y=0,z=vertical})
        local distance=length(direction)
        local desired={x=0,y=0,z=0}
        if distance>0 then
            local speed=settings.speed
            if keys.ShiftLeft or keys.ShiftRight then speed=speed*(cfg.FastMultiplier or 4) end
            if keys.ControlLeft or keys.ControlRight or keys.AltLeft or keys.AltRight then speed=speed*(cfg.SlowMultiplier or 0.2) end
            desired=mul(direction,speed/math.max(1,distance))
        end
        local displacement=F.move(flightSmoothing,desired,dt,settings.stabilization)
        if length(displacement)>0 then
            local target=add(camera.pos,displacement)
            local origin=vec(entityCoords(player));local delta=sub(target,origin)
            local maximum=cfg.MaxDistance or 2000
            if length(delta)>maximum then target=add(origin,mul(delta,maximum/length(delta))) end
            camera.pos=target
        end
        if attachment then attachment.freePose=transformPose(camera,true) end
    end
    applyCamera();environment(false)
    if playing or recording or length(sub(camera.pos,oldPosition))>0.000001
        or length(sub(camera.rot,oldRotation))>0.000001 then markWorkspace() end
    if recording and (tickTime>=nextRecord or tickTime-recordBuffer.started>=recordBuffer.maxDuration*1000) then
        appendRecordedSample(tickTime,false)
        -- Keep the 30 Hz schedule on its original clock. At 60 FPS this samples
        -- roughly every other rendered frame rather than drifting down to 20 Hz.
        local interval=math.max(1000/30,cfg.RecordInterval or 1000/30)
        nextRecord=nextRecord+math.max(1,math.floor((tickTime-nextRecord)/interval+1e-7)+1)*interval
        if tickTime-recordBuffer.started>=recordBuffer.maxDuration*1000 or #recordBuffer.samples>=recordBuffer.maxSamples-1 then
            local ok,err=finishRecording(true)
            if ok then toast('Recording limit reached; the take was saved') else toast(err,'error') end
        end
    end
    if tickTime>=nextState then sendState();nextState=tickTime+100 end
    if tickTime>=nextGizmos then sendGizmos();nextGizmos=tickTime+50 end
    if diagnosticDue and tickTime>=diagnosticDue then diagnosticDue=nil;diagnose('probe',false) end
    for id,request in pairs(pending) do
        if tickTime-request.at>30000 then pending[id]=nil;toast('Storage did not respond. Please try again.','error') end
    end
end
CreateThread(function()
    while not stopped do
        -- Autosaves also finish after closing the editor, without keeping the camera active.
        pcall(serviceWorkspace)
        if active or aimProbe then guard(tick);Wait(0) else Wait(200) end
        if requestedOpen and now()-requestedOpen>30000 then requestedOpen=nil;toast('The server did not respond to the camera request','error') end
    end
end)
AddEventHandler('onClientResourceStop',function(name)
    if name~=GetCurrentResourceName() then return end
    stopped=true;guard(cleanup)
end)
AddEventHandler('playerSpawned',function() if active then guard(cleanup) end end)
