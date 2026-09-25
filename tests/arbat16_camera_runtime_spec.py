"""Mocked RedM runtime contract tests. Requires Python + lupa (Lua 5.4); no game session or downloaded fixtures."""
from pathlib import Path
from lupa.lua54 import LuaRuntime
ROOT = Path(__file__).resolve().parents[1]
root = ROOT / 'resource' / 'arbat16_camera'
lua=LuaRuntime(unpack_returned_tuples=True)
for name in ('shared/core.lua','shared/director.lua','shared/flight.lua','client/natives.lua'):
    lua.execute((root/name).read_text(encoding='utf-8-sig'))
# Exercise the real wrapper before replacing its transport with the runtime stub.
lua.execute('''
Citizen={ReturnResultAnyway=function() return 'return' end,
 ResultAsVector=function() return 'vector' end,ResultAsFloat=function() return 'float' end,
 ResultAsInteger=function() return 'integer' end}
local seen
Citizen.InvokeNative=function(hash,...)
 seen={hash=hash,args=table.pack(...)}
 if hash==FC.Natives.spec.GET_SCREEN_COORD_FROM_WORLD_COORD.hash then return 1,.25,.75 end
 if hash==FC.Natives.spec.IS_ENTITY_DEAD.hash then return 0 end
 if hash==FC.Natives.spec.GET_ENTITY_MATRIX.hash then return 'right','forward','up','position' end
end
FC.Natives.call('SET_CAM_FOV',100,50)
assert(math.type(seen.args[1])=='integer' and math.type(seen.args[2])=='float','float argument coercion preserves handles')
FC.Natives.call('SET_CAM_ROT',100,0,30,180,2)
assert(math.type(seen.args[2])=='float' and math.type(seen.args[3])=='float' and math.type(seen.args[4])=='float')
assert(math.type(seen.args[5])=='integer','rotation order remains integer')
local visible,x,y=FC.Natives.call('GET_SCREEN_COORD_FROM_WORLD_COORD',1,2,3,'px','py')
assert(visible==true and x==.25 and y==.75,'BOOL conversion preserves pointer outputs')
assert(seen.args[4]=='px' and seen.args[5]=='py' and seen.args[6]=='return' and seen.args[7]=='integer')
assert(FC.Natives.call('IS_ENTITY_DEAD',1)==false,'native numeric zero is false')
local a,b,c,d=FC.Natives.call('GET_ENTITY_MATRIX',1,'r','f','u','p')
assert(a=='right' and b=='forward' and c=='up' and d=='position','void native pointer outputs')
assert(not pcall(FC.Natives.call,'SET_CAM_FOV',100),'wrong native arity rejected')
print('Native wrapper: float coercion, integer handles, BOOL normalization, pointer outputs and arity checks passed.')
''')
runtime_harness='''
T={tick=100,rendering=0,events={},commands={},messages={},server={},calls={},frozen=false,entityX=0,raw={}}
FCConfig={DefaultSpeed=5,FreezePlayer=true,MaxDistance=2000,RecordInterval=33,MaxFrames=200}
Citizen={PointerValueVector=function() return {} end,PointerValueFloat=function() return {} end,PointerValueInt=function() return {} end}
function RegisterNetEvent(n,f) T.events[n]=f end
function AddEventHandler(n,f) T.events[n]=f end
function RegisterCommand(n,f) T.commands[n]=f end
function RegisterNUICallback(n,f) T.callback=f end
function SendNUIMessage(d) T.messages[#T.messages+1]=FC.Core.copy(d) end
function SetNuiFocus(a,b) T.focus=a end
function SetNuiFocusKeepInput(value) T.keepInput=value end
function TriggerServerEvent(...)
 local args=table.pack(...)
 if args[1]=='arbat16_camera:diagnostic' and T.failDiagnosticTransport then error('Simulated diagnostic transport failure') end
 T.server[#T.server+1]=args
end
function GetResourceState() return 'started' end
function GetCurrentResourceName() return 'arbat16_camera' end
function CreateThread(f) T.thread=coroutine.create(f) end
function Wait() coroutine.yield() end
function SetTimeout(_,f) f() end
FC.Natives.call=function(n,...)
 local a=table.pack(...);local spec=assert(FC.Natives.spec[n],n);assert(a.n==spec.arity,n..' arity')
 if T.failNative==n then error('Simulated native failure: '..n) end
 T.calls[#T.calls+1]={name=n,args=a}
 if n=='GET_GAME_TIMER' then return T.tick
 elseif n=='GET_FRAME_TIME' then return T.frameTime or .016
 elseif n=='GET_DISABLED_CONTROL_NORMAL' then return a[2]==0xA987235F and (T.mouseX or 0) or (T.mouseY or 0)
 elseif n=='IS_PAUSE_MENU_ACTIVE' then return T.paused==true
 elseif n=='PLAYER_PED_ID' then return 1
 elseif n=='DOES_ENTITY_EXIST' then return true
 elseif n=='IS_ENTITY_DEAD' then return T.dead==true
 elseif n=='_IS_ENTITY_FROZEN' then return T.frozen
 elseif n=='FREEZE_ENTITY_POSITION' then T.frozen=a[2]
 elseif n=='GET_RENDERING_CAM' then return T.rendering
 elseif n=='CREATE_CAM' then return 100
 elseif n=='DOES_CAM_EXIST' then return not T.invalidCamera
 elseif n=='IS_CAM_ACTIVE' or n=='IS_CAM_RENDERING' then return T.rendering==a[1]
 elseif n=='SET_CAM_COORD' then T.nativeCamPos={x=a[2],y=a[3],z=a[4]}
 elseif n=='SET_CAM_ROT' then T.nativeCamRot={x=a[2],y=a[3],z=a[4]}
 elseif n=='GET_CAM_COORD' then return T.nativeCamPos
 elseif n=='SET_CAM_ACTIVE' then if a[2] then T.rendering=a[1] end
 elseif n=='DESTROY_CAM' then T.destroyed=a[1]
 elseif n=='GET_FINAL_RENDERED_CAM_COORD' then return {x=0,y=0,z=2}
 elseif n=='GET_FINAL_RENDERED_CAM_ROT' then return {x=0,y=0,z=0}
 elseif n=='GET_FINAL_RENDERED_CAM_FOV' then return 50
 elseif n=='GET_ENTITY_COORDS' then return {x=0,y=0,z=0}
 elseif n=='GET_ENTITY_MATRIX' then return {x=1,y=0,z=0},{x=0,y=1,z=0},{x=0,y=0,z=1},{x=T.entityX,y=0,z=0}
 elseif n=='GET_CLOCK_HOURS' then return 12
 elseif n=='GET_CLOCK_MINUTES' then return 0
 elseif n=='_GET_NEXT_WEATHER_TYPE_HASH_NAME' then return 123
 elseif n=='GET_HASH_KEY' then return a[1]=='SUNNY' and 123 or 456
 elseif n=='GET_SCREEN_COORD_FROM_WORLD_COORD' then return true,.5+a[1]/100,.5+a[2]/100
 elseif n=='GET_MOUNT' then return 2
 end
end
function T.request(n,d)
 d=d or {};d.action=n;local count,result=0,nil
 T.callback(d,function(r) count=count+1;result=r end)
 assert(count==1,n..' callback exactly once');return result
end
function T.action(n,d) local r=T.request(n,d);assert(r.ok,n..' callback: '..tostring(r.error));return r end
function T.last(k) for i=#T.messages,1,-1 do if T.messages[i].type==k then return T.messages[i] end end end
function T.step(ms) T.tick=T.tick+(ms or 16);local ok,err=coroutine.resume(T.thread);assert(ok,err) end
function T.open() T.commands.ar16_cam();T.events['arbat16_camera:openAllowed'](true);assert(T.focus and T.frozen,'open') end
'''
lua.execute(runtime_harness)
lua.execute((root/'client/director.lua').read_text(encoding='utf-8-sig'))
lua.execute((root/'client/main.lua').read_text(encoding='utf-8-sig'))
lua.execute('''
T.action('ready');T.invalidCamera=true;T.commands.ar16_cam();T.events['arbat16_camera:openAllowed'](true)
assert(not T.focus and not T.frozen,'invalid camera handle cannot open the editor or freeze the player')
T.invalidCamera=nil;T.open();T.step();assert(T.last('open').capabilities.dofBlur==false)
local revision=T.last('open').revision
assert(type(revision)=='number','open seeds the authoritative revision')
local captureResult=T.action('capture');assert(#T.last('scene').scene.frames==1,'capture')
assert(captureResult.revision==T.last('scene').revision and captureResult.revision>revision,'capture acknowledgement and echo share a newer revision')
assert(captureResult.stateSequence==T.last('state').stateSequence and captureResult.stateSequence>T.last('open').stateSequence,'callback and state message share a monotonic sequence')
local id=T.last('scene').scene.frames[1].id
T.action('capture',{replaceId=id});assert(#T.last('scene').scene.frames==1,'replace')
T.action('flight',{enabled=true});T.action('input',{keys={'KeyW'},dx=10,dy=0});T.step();assert(T.last('state').flight,'flight')
T.action('capture');local s=T.last('scene').scene;assert(s.frames[2].pos.y>0,'movement')
local output,originalPrint={},print
print=function(value) output[#output+1]=tostring(value) end
local beforeDebugCalls=#T.calls;T.commands.ar16_camdebug();print=originalPrint
local diagnostic=table.concat(output,'\\n')
assert(diagnostic:find('cameraRendering=true',1,true) and diagnostic:find('inputPackets=1',1,true),'diagnostics expose actual renderer and accepted input')
assert(diagnostic:find('changedPoseSegments=1',1,true),'diagnostics distinguish a moving camera path')
for i=beforeDebugCalls+1,#T.calls do assert(not T.calls[i].name:find('SET_',1,true),'diagnostics are read only') end
assert(T.focus and T.frozen,'diagnostics preserve the editor state')
local lastPosition=FC.Core.copy(T.last('state').camera.pos)
T.step(1001)
assert(T.last('state').camera.pos.y==lastPosition.y,'stale input cleared')
local rejection=T.request('scene',{scene={version=1,name='Bad',frames={{pos={x=0,y=0,z=0}}}}})
assert(not rejection.ok and type(rejection.error)=='string','invalid scene rejected before acknowledgement')
assert(rejection.revision==T.last('scene').revision,'rejection identifies the unchanged authoritative revision')
assert(T.focus,'invalid scene not closed')
T.action('capture');assert(#T.last('scene').scene.frames==3,'invalid scene did not replace prior frames')
T.action('scene',{scene=s});T.action('play');T.step();assert(T.last('state').playing,'play')
assert(T.last('scene').revision>captureResult.revision,'subsequent accepted edits advance the revision')
T.action('settings');local beforeStall=T.last('state').time
T.frameTime=.5;T.step(500)
assert(math.abs(T.last('state').time-beforeStall-.5)<.000001,'playback clock survives slow frames')
T.frameTime=nil
T.action('pause');assert(not T.last('state').playing,'pause')
T.action('seek',{time=1});assert(T.last('state').time==1,'seek')
T.action('capture');assert(T.last('scene').scene.frames[3].timeHours==nil,'capture strips derived sample metadata')
T.action('scene',{scene=s})
T.action('setCamera',{frame=s.frames[2]});assert(T.last('state').camera.pos.y==s.frames[2].pos.y,'select camera pose')
local reachable=FC.Core.copy(T.last('state').camera)
local distant=FC.Core.copy(s.frames[2]);distant.pos.x=3000
rejection=T.request('setCamera',{frame=distant})
assert(not rejection.ok and T.last('state').camera.pos.x==reachable.pos.x,'distant setCamera rejected without moving camera')
local distantScene=FC.Core.copy(s);distantScene.frames[2]=distant
T.action('scene',{scene=distantScene});local oldTime=T.last('state').time
rejection=T.request('seek',{time=FC.Core.duration(distantScene)})
assert(not rejection.ok and T.last('state').time==oldTime,'rejected seek preserves timeline and camera')
T.action('scene',{scene=s})
local loop=FC.Core.copy(s);loop.loop=true;T.action('scene',{scene=loop});T.action('seek',{time=FC.Core.duration(loop)})
assert(T.last('state').camera.pos.y==loop.frames[#loop.frames].pos.y,'loop scrub endpoint remains final frame')
T.action('scene',{scene=s})
T.action('stop');assert(T.last('state').time==0,'stop')
T.action('attach',{mode='mount',rotate=true});T.entityX=10;T.step(200);assert(T.last('state').camera.pos.x>9,'attachment')
T.action('environment',{weather='RAIN',hour=20,minute=30});T.step(200)
assert(T.last('state').camera.weather=='RAIN' and T.last('state').camera.hour==20,'environment persistence')
T.action('attach',{mode='detach'});assert(T.last('state').attachment==false,'detach')
local oldDuration=T.last('scene').scene.frames[#T.last('scene').scene.frames].duration
T.action('record',{enabled=true});local count=#T.last('scene').scene.frames
assert(T.last('scene').scene.frames[count].duration==oldDuration,'record start preserves authored keyframe duration')
T.action('record',{enabled=true});assert(#T.last('scene').scene.frames==count,'duplicate record start is idempotent')
T.step(1500)
assert(#T.last('scene').scene.frames==count,'recording buffers samples without flooding timeline messages')
T.action('record',{enabled=false})
assert(#T.last('scene').scene.frames==count+1,'recording commits a single take')
assert(T.last('scene').scene.frames[count+1].take.duration==1.5,'recorded timing preserves actual elapsed interval')
T.action('save',{name='Test'})
local request=T.server[#T.server];assert(request[1]=='arbat16_camera:storage','storage')
T.events['arbat16_camera:storageResult'](request[2],{ok=true,name='Test',items={}});assert(T.last('scene').scene.name=='Test','save result')
T.action('save',{name='Canonical  '});request=T.server[#T.server]
T.events['arbat16_camera:storageResult'](request[2],{ok=true,name='Canonical',items={}})
assert(T.last('scene').scene.name=='Canonical','canonical server name reflected after save')
T.action('save',{name='Stale'});request=T.server[#T.server];T.action('capture')
T.events['arbat16_camera:storageResult'](request[2],{ok=true,name='Stale',items={}})
assert(T.last('scene').scene.name=='Canonical','late save response cannot rename an edited scene')
assert(T.last('toast').message~='Scene saved','late save response cannot mark newer edits saved')
T.action('load',{name='Test'});request=T.server[#T.server];T.action('capture')
local editedCount=#T.last('scene').scene.frames
T.events['arbat16_camera:storageResult'](request[2],{ok=true,scene=s,items={}})
assert(#T.last('scene').scene.frames==editedCount,'late load response cannot discard newer edits')
T.action('close');assert(not T.focus and not T.frozen and T.destroyed==100,'cleanup')
assert(T.server[#T.server][1]=='simple_weather:request','weather restore')
T.rendering=777;T.frozen=true;T.open();T.commands.ar16_camclose();assert(T.rendering==777 and T.frozen,'prior state')
T.frozen=false;T.open();T.failNative='GET_RENDERING_CAM';T.commands.ar16_camclose()
assert(not T.focus and not T.frozen and T.destroyed==100,'native error cannot trap NUI input')
T.failNative=nil
T.open();T.failNative='SET_CAM_FOV';rejection=T.request('lens',{fov=60})
assert(not rejection.ok and not T.focus and not T.frozen,'native failure returns one rejection and restores input')
T.failNative=nil
T.frozen=false;T.open();T.dead=true;T.step(200);assert(not T.focus and not T.frozen,'death')
T.dead=false;T.events['arbat16_camera:openAllowed'](true);assert(not T.focus,'unsolicited permission response ignored')
T.open();T.events.onClientResourceStop('another_resource');assert(T.focus,'another resource stop ignored')
T.events.onClientResourceStop('arbat16_camera');assert(not T.focus and not T.frozen,'resource stop cleanup')
print('Runtime smoke: capture/replace, NUI flight, transactional validation, stalled-frame playback, seek, attachment, environment, recording, storage races, cleanup and death passed.')
''')
print('Lua files compile; all native call arities match verified RDR3 signatures.')

# Exercise native flight independently, with no browser keyboard packets.
native=LuaRuntime(unpack_returned_tuples=True)
for name in ('shared/core.lua','shared/director.lua','shared/flight.lua','client/natives.lua'):
    native.execute((root/name).read_text(encoding='utf-8-sig'))
native.execute(runtime_harness)
native.execute((root/'client/director.lua').read_text(encoding='utf-8-sig'))
native.execute('''
function IsRawKeyDown(code) return T.raw[code] or false end
function IsNuiFocused() return T.focus or T.otherFocus or false end
FCConfig.Diagnostics=true
T.printed={};print=function(value) T.printed[#T.printed+1]=tostring(value) end
function T.eventCount(kind)
 local count=0;for _,m in ipairs(T.messages) do if m.type==kind then count=count+1 end end;return count
end
function T.diagnostic(kind)
 for i=#T.server,1,-1 do
  local r=T.server[i]
  if r[1]=='arbat16_camera:diagnostic' and r[2].event==kind then return r[2] end
 end
end
''')
native.execute((root/'client/main.lua').read_text(encoding='utf-8-sig'))
native.execute('''
T.action('ready');T.open()
assert(T.last('open').capabilities.nativeFlightInput==true,'native capability negotiated')
assert(T.diagnostic('open').active and T.diagnostic('open').nativeFlightInput,'open records native diagnostics')
T.action('capture')
T.raw[0x57]=true;T.raw[0x46]=true
T.action('flight',{enabled=true})
assert(not T.focus and T.keepInput==false,'native flight gives keyboard and mouse back to game')
assert(T.diagnostic('flight').flight,'flight toggle is recorded')
T.step();assert(T.nativeCamPos.y==0 and #T.last('scene').scene.frames==1,'keys held on entry do not move or capture')
T.raw={};T.step();T.raw[0x57]=true;T.mouseX=.5;T.step()
assert(T.nativeCamPos.y>0,'native W moves without browser input')
T.action('settings');assert(T.last('state').camera.rot.z<0,'native mouse axis changes yaw')
T.mouseX=0
local before=T.nativeCamPos.y
T.action('input',{keys={'KeyS'},dx=500,dy=500});T.step()
assert(T.nativeCamPos.y>before,'late browser input cannot override native flight')
T.raw[0x46]=true;T.step();local count=#T.last('scene').scene.frames
T.step();assert(#T.last('scene').scene.frames==count and count==2,'F captures once per key press')
local h=T.eventCount('toggleClean');T.raw[0x48]=true;T.step();T.step()
assert(T.eventCount('toggleClean')==h+1,'H toggles clean mode once per key press')
T.raw={};T.step()
T.raw[0x45]=true;T.step();assert(T.nativeCamPos.z>2,'Q/E vertical native input')
T.raw={};T.step();T.raw[0x57]=true;T.step();local normal=T.nativeCamPos.y
T.raw[0x10]=true;T.step();local fast=T.nativeCamPos.y-normal
T.raw[0x10]=false;T.step();local slowReference=T.nativeCamPos.y-(normal+fast)
assert(fast>slowReference*3.9,'native Shift fast movement')
T.raw[0x11]=true;T.step();local controlled=T.nativeCamPos.y-(normal+fast+slowReference)
assert(controlled<slowReference*.21,'native Ctrl slow movement')
T.raw={};T.step();T.raw[0x57]=true;T.otherFocus=true
before=T.nativeCamPos.y;T.step();assert(T.nativeCamPos.y==before,'foreign NUI focus suspends native movement')
T.otherFocus=false;T.step();assert(T.nativeCamPos.y==before,'held key stays blocked after NUI focus returns')
T.raw={};T.step();T.raw[0x57]=true;T.step();assert(T.nativeCamPos.y>before,'fresh key press resumes after NUI focus')
T.paused=true;before=T.nativeCamPos.y;T.step();assert(T.nativeCamPos.y==before,'pause menu suspends movement')
T.paused=false;T.step();assert(T.nativeCamPos.y==before,'pause menu return requires releasing held keys')
T.raw={};T.step();T.raw[0x09]=true;T.step()
assert(T.focus and not T.last('state').flight,'Tab returns editor focus')
T.action('flight',{enabled=true});T.step()
assert(not T.focus and T.last('state').flight,'Tab held on reentry does not immediately exit flight')
T.raw={};T.step();T.raw[0x20]=true;T.step()
assert(T.focus and T.last('state').playing and not T.last('state').flight,'Space starts playback and restores editor focus')
assert(T.diagnostic('play').playing,'play diagnostic emitted')
T.step(2100);local probe=T.diagnostic('probe')
assert(probe and probe.ticks>0 and probe.nativeInputTicks>0 and probe.inputPackets==0,'delayed diagnostic proves direct input path')
assert(probe.targetPosition.y==probe.nativePosition.y and probe.changedPoseSegments>=1,'diagnostic distinguishes target/native positions and moving frames')
for _,r in ipairs(T.server) do
 if r[1]=='arbat16_camera:diagnostic' then
  for key,value in pairs(r[2]) do
   assert(type(value)~='string' or key=='event','diagnostics omit personal strings')
  end
 end
end
T.action('pause');T.action('flight',{enabled=true});T.raw={};T.step();T.raw[0x1B]=true;T.step()
assert(not T.focus and not T.frozen and T.last('close'),'Escape closes and restores player')
T.raw={};T.open()
local fresh=T.diagnostic('open')
assert(fresh.nativeInputTicks==0 and fresh.ticks==0 and fresh.inputPackets==0 and fresh.frameTime==nil,'new session resets input/frame diagnostics')
T.action('close');T.failDiagnosticTransport=true;T.open()
assert(T.focus and T.frozen,'diagnostic transport failure cannot close an opening camera')
T.action('flight',{enabled=true});T.raw[0x57]=true;T.step();before=T.nativeCamPos.y
T.step(2100)
assert(T.nativeCamPos.y>before and T.frozen and not T.focus,'failed automatic flight/probe reports cannot stop movement')
assert(pcall(T.commands.ar16_camdebug),'manual diagnostic transport failure cannot escape command handler')
T.action('play');T.step()
assert(T.focus and T.frozen and T.last('state').playing,'failed play diagnostic cannot close playback')
T.failDiagnosticTransport=false
T.action('flight',{enabled=true});T.events.onClientResourceStop('arbat16_camera')
assert(not T.focus and not T.frozen,'resource stop cleans native flight')
''')
print('Native flight: raw WASD/QE/modifiers, mouse axes, held-key guards, focus/pause suspension, Tab/F/H/Space/Escape, playback, diagnostic probes/session resets and logging-failure isolation passed.')

def director_runtime(native_input=False):
    runtime = LuaRuntime(unpack_returned_tuples=True)
    for filename in ('shared/core.lua', 'shared/director.lua', 'shared/flight.lua', 'client/natives.lua'):
        runtime.execute((root / filename).read_text(encoding='utf-8-sig'))
    runtime.execute(runtime_harness)
    if native_input:
        runtime.execute('''
function IsRawKeyDown(code) return T.raw[code] or false end
function IsNuiFocused() return T.focus or T.otherFocus or false end
''')
    for filename in ('client/director.lua', 'client/main.lua'):
        runtime.execute((root / filename).read_text(encoding='utf-8-sig'))
    runtime.execute('''
function T.lastSave()
 for i=#T.server,1,-1 do if T.server[i][1]=='arbat16_camera:workspaceSave' then return T.server[i] end end
end
function T.ackSave()
 local request=assert(T.lastSave(),'workspace request sent')
 T.events['arbat16_camera:workspaceResult'](request[2],{ok=true})
 return request[3]
end
T.action('ready')
''')
    return runtime

director = director_runtime()
director.execute('''
T.open()
local pose=FC.Core.defaultFrame({x=12,y=8,z=3},{x=5,y=0,z=25})
T.action('setCamera',{frame=pose});T.action('capture')
local look=FC.Director.defaults();look.framing.ratio='4:3';look.motion.type='sway'
T.action('director',{director=look})
T.action('settings',{stabilization='strong'})
T.action('cameraSave',{name='Bridge wide'});T.action('presetSave',{name='My quiet shot'})
local bank=T.last('workspace').cameras;local custom=T.last('workspace').presets
assert(#bank==1 and #custom==1,'camera bank and custom presets created')
assert(not T.request('cameraSave',{name='bad/name'}).ok,'invalid bank name rejected before mutation')
T.action('lens',{fov=80});T.action('presetApply',{id=custom[1].id})
assert(T.last('state').camera.fov==50,'custom preset restores lens')
T.action('generateMove',{kind='truck',distance=4,duration=6,returnToStart=true})
assert(#T.last('scene').scene.frames==4,'generated return move appended without removing authored frame')
T.action('capture');assert(#T.last('scene').scene.frames==5,'ordinary capture can follow a generated final zero-duration frame')
T.action('generateMove',{kind='crane',distance=1,duration=2});T.action('record',{enabled=true});T.step(40);T.action('record',{enabled=false})
assert(#T.last('scene').scene.frames==8,'recording can start after a generated move')
T.action('play');T.step(800);T.action('pause')
assert(T.request('generateMove',{kind='pan',angle=30,duration=2}).ok,'move generator accepts interpolated runtime poses')
T.action('cameraRecall',{id=bank[1].id})
assert(T.last('state').camera.pos.x==12 and T.last('state').director.framing.ratio=='4:3','recall restores independent pose and framing')
assert(T.last('state').settings.stabilization=='strong','camera recall preserves global stabilization')
T.action('play');T.action('presetApply',{id=custom[1].id});T.step(100)
assert(not T.last('state').playing and T.last('state').camera.fov==custom[1].fov,'applying preset pauses playback so lens does not immediately revert')
assert(T.last('state').settings.stabilization=='strong','look presets preserve global stabilization')
T.action('cameraRecall',{id=bank[1].id})
T.step(900);local payload=T.ackSave()
assert(#payload.cameras==1 and #payload.presets==1 and #payload.scene.frames>1,'autosave contains bank, presets and complete timeline')
assert(payload.camera.timeHours==nil,'snapshot strips transient playback fields')
assert(payload.settings.stabilization=='strong','workspace persists stabilization level')
T.action('close');T.step(900);T.ackSave();T.open()
assert(T.last('open').camera.pos.x==12 and T.last('open').camera.pos.y==8,'command reopen restores last camera')
assert(#T.last('open').workspace.cameras==1,'command reopen retains camera bank')
T.action('settings',{speed=8});T.step(900)
local request=T.lastSave()
T.events['arbat16_camera:workspaceResult'](request[2],{ok=false,error='Simulated disk failure'})
assert(T.last('workspace').status=='error' and T.focus and T.frozen,'save failure is visible without losing the active camera')
T.step(5100);T.ackSave()
T.action('attach',{mode='player',rotate=false});T.entityX=10;T.step(900);T.ackSave();T.action('capture')
T.step(2200);local baked=T.ackSave()
assert(baked.scene.frames[1].pos.x>=22,'attached route persisted in current world coordinates')
T.action('save',{name='Attached scene'});local stored=T.server[#T.server]
assert(stored[1]=='arbat16_camera:storage' and stored[4].scene.frames[1].pos.x==baked.scene.frames[1].pos.x,'named scenes and autosave bake the same current attachment transform')
T.action('cameraDelete',{id=bank[1].id});T.action('presetDelete',{id=custom[1].id})
assert(#T.last('workspace').cameras==0 and #T.last('workspace').presets==0,'bank and preset removal supported')
T.action('close');T.step(900)
T.saved=T.ackSave()
''')

camera_tracks = director_runtime()
camera_tracks.execute('''
T.open()
local first=FC.Core.defaultFrame({x=10,y=5,z=3},{x=0,y=0,z=0});first.fov=60
T.action('setCamera',{frame=first});T.action('cameraSave',{name='Wide'})
local firstId=T.last('workspace').cameras[1].id
local second=FC.Core.defaultFrame({x=-8,y=15,z=5},{x=-10,y=2,z=90})
T.action('setCamera',{frame=second});T.action('cameraSave',{name='Close'})
local secondId=T.last('workspace').cameras[2].id
T.action('settings',{showPath=false});T.step(100)
local markers=T.last('gizmos').cameras
assert(#markers==2 and #T.last('gizmos').points==0,'saved cameras remain visible with route path hidden')
assert(markers[1].id==firstId and markers[1].index==1 and markers[1].name=='Wide','stable bank ids, number and labels')
assert(math.abs(markers[1].x-.6)<.000001 and math.abs(markers[1].y-.55)<.000001,'markers project actual world position')
assert(#markers[1].lines==8 and #markers[2].lines==8,'world frustums include four rays and four edges')
assert(markers[1].lines[1].x2~=markers[1].lines[2].x2,'world frustum has nonzero projected extent')
T.action('cameraAdd',{id=firstId});local shot=T.last('scene').scene.frames[1]
assert(shot.label=='Wide' and shot.duration==3 and shot.transition=='hold' and shot.fov==60,'saved angle becomes timed static shot')
assert(T.last('state').camera.pos.x==-8,'adding shot does not move current camera')
T.action('cameraAdd',{id=secondId,beforeId=shot.id,duration=2})
local route=T.last('scene').scene
assert(route.frames[1].label=='Close' and route.frames[2].label=='Wide','saved camera insertion honors drop target')
assert(FC.Core.sample(route,1).pos.x==-8 and FC.Core.sample(route,2).pos.x==10,'shots hold and cut at their boundary')
assert(not T.request('cameraAdd',{id=firstId,beforeId='missing'}).ok,'stale drop target rejected')
assert(not T.request('cameraAdd',{id=firstId,duration=0}).ok,'invalid shot duration rejected')
T.action('record',{enabled=true})
assert(not T.request('cameraAdd',{id=firstId}).ok,'recording reserves its timeline slot')
T.step(40);T.action('record',{enabled=false})
T.action('attach',{mode='player',rotate=false});T.entityX=7;T.step(100)
T.action('cameraAdd',{id=firstId,duration=1})
local attached=T.last('scene').scene.frames
assert(attached[#attached].pos.x==3,'saved world angle converts into current attachment coordinates')
T.action('attach',{mode='detach'})
assert(T.last('scene').scene.frames[#attached].pos.x==10,'detaching restores saved world angle exactly')
T.action('settings',{showCameras=false});T.step(900)
assert(#T.last('gizmos').cameras==0,'camera visibility is independently configurable')
local pending=T.lastSave();if pending then T.ackSave();T.step(900) end
local snapshot=T.ackSave();assert(snapshot.settings.showCameras==false,'camera marker preference persists')
T.action('settings',{showCameras=true});T.action('play');T.step(100)
assert(#T.last('gizmos').cameras==0,'playback hides editor world markers')
T.action('pause');T.step(100);assert(#T.last('gizmos').cameras==2,'paused editing restores markers')
''')
print('Saved camera timeline: world frustums, independent visibility, ordered hold shots, attachment coordinates and recording guards passed.')

def plain_table(value):
    if hasattr(value, 'items'):
        return {key: plain_table(child) for key, child in value.items()}
    return value

saved = plain_table(director.globals().T.saved)
restored = director_runtime()
restored.globals().saved = restored.table_from(saved, recursive=True)
restored.execute('''
T.commands.ar16_cam();T.events['arbat16_camera:openAllowed'](true,{workspace=saved})
assert(T.focus and T.frozen,'reconnected workspace opens')
assert(T.last('open').camera.pos.x==saved.camera.pos.x,'new client runtime restores last exact camera position')
assert(#T.last('open').scene.frames==#saved.scene.frames and T.last('open').settings.speed==8,'scene and settings survive runtime reload')
assert(T.last('state').director.framing.ratio=='4:3','director settings survive runtime reload')
assert(T.last('state').settings.stabilization=='strong','stabilization survives runtime reload')
T.step(900);T.ackSave()
''')

blocked = director_runtime()
blocked.execute('''
T.commands.ar16_cam();T.events['arbat16_camera:openAllowed'](true,{workspaceError='Saved workspace is corrupt'})
T.action('capture');T.step(15000)
assert(not T.lastSave() and T.last('workspace').status=='disabled','corrupt stored workspace cannot be overwritten by autosave')
T.action('workspaceReset');local request=T.server[#T.server]
assert(request[1]=='arbat16_camera:workspaceReset','explicit recovery uses reset endpoint')
T.events['arbat16_camera:workspaceResult'](request[2],{ok=true});T.step(900);T.ackSave()
assert(T.focus,'explicit workspace recovery preserves camera')
''')

distant = director_runtime()
distant.globals().saved = distant.table_from(saved, recursive=True)
distant.execute('''
saved.camera.pos.x=3000
T.commands.ar16_cam();T.events['arbat16_camera:openAllowed'](true,{workspace=saved})
assert(not T.focus and not T.frozen and not T.lastSave(),'distant saved camera is preserved without freezing player or autosaving a replacement')
T.commands.ar16_camresetview();T.events['arbat16_camera:openAllowed'](true)
assert(T.focus and T.last('open').camera.pos.x==0 and #T.last('open').scene.frames==#saved.scene.frames,'reset view opens at player without deleting scene')
''')
print('Director runtime: camera bank, custom presets, generated motion, autosave/reopen/reconnect, attachment baking, failure recovery and distance recovery passed.')

def stabilized_runtime(native_input):
    runtime=LuaRuntime(unpack_returned_tuples=True)
    for filename in ('shared/core.lua','shared/director.lua','shared/flight.lua','client/natives.lua'):
        runtime.execute((root/filename).read_text(encoding='utf-8-sig'))
    runtime.execute(runtime_harness)
    if native_input:
        runtime.execute('''
function IsRawKeyDown(code) return T.raw[code] or false end
function IsNuiFocused() return T.focus or T.otherFocus or false end
''')
    for filename in ('client/director.lua','client/main.lua'):
        runtime.execute((root/filename).read_text(encoding='utf-8-sig'))
    runtime.execute("T.action('ready');T.open()")
    return runtime

stabilized=stabilized_runtime(True)
stabilized.execute('''
assert(T.last('state').settings.stabilization=='off','old/default workspace keeps direct control')
local rejected=T.request('settings',{stabilization='extreme',speed=77})
assert(not rejected.ok,'unknown stabilization level rejected')
T.action('settings');assert(T.last('state').settings.speed==5,'invalid level cannot partially change settings')
T.raw[0x4A]=true;T.raw[0x52]=true;T.raw[0x70]=true
T.action('flight',{enabled=true});T.step()
assert(T.last('state').flight and not T.last('state').recording and T.last('state').settings.stabilization=='off','new shortcuts held on entry stay blocked')
T.raw={};T.step();T.raw[0x4A]=true;T.step();T.action('settings')
assert(T.last('state').settings.stabilization=='light','J changes stabilization natively')
T.step();T.action('settings');assert(T.last('state').settings.stabilization=='light','held J does not repeat')
T.raw={};T.step();T.raw[0x4A]=true;T.step();T.action('settings')
assert(T.last('state').settings.stabilization=='medium','second J selects medium')
T.action('cycleStabilization');assert(T.last('state').settings.stabilization=='strong','NUI cycle shares native action')
T.raw={};T.step()
local start=FC.Core.copy(T.nativeCamPos)
T.mouseX=.5;T.mouseY=-.5;T.raw[0x45]=true;T.step();T.action('settings')
local state=T.last('state')
assert(state.camera.rot.z<0 and state.camera.rot.z>-6,'native yaw is smoothed with unchanged target gain')
assert(state.camera.rot.x>0 and state.camera.rot.x<6,'native pitch is smoothed')
assert(T.nativeCamPos.z>start.z and T.nativeCamPos.z<start.z+.08,'vertical speed eases in')
T.mouseX=0;T.mouseY=0
FCConfig.RecordInterval=16
T.raw[0x52]=true;T.step();T.action('settings')
assert(T.last('state').recording,'R starts recording in flight')
T.step(40);T.action('settings')
assert(T.last('state').recording and T.last('state').recordingSamples==2,'held R keeps one recording buffer without repeated toggles')
local before=T.nativeCamPos.z
T.raw={};T.step();assert(T.nativeCamPos.z>before,'key release has a controlled soft stop')
local finalZ=T.nativeCamPos.z;local finalYaw=T.last('state').camera.rot.z
T.action('settings');finalYaw=T.last('state').camera.rot.z
T.raw[0x52]=true;T.step();T.action('settings');assert(not T.last('state').recording,'second R stops recording')
local frames=T.last('scene').scene.frames;local samples=frames[#frames].take.samples
assert(#frames==1 and #samples>=2,'recorded flight becomes one take')
assert(math.abs(samples[#samples][4]-finalZ)<1e-9,'recorded endpoint captures actual last rendered smoothed position')
assert(math.abs(samples[#samples][7]-finalYaw)<1e-9,'recorded endpoint captures actual last rendered smoothed rotation')
T.raw={};T.raw[0x57]=true;T.mouseX=.5;T.step();T.action('settings')
local paused=FC.Core.copy(T.last('state').camera)
T.otherFocus=true;T.raw[0x4A]=true;T.raw[0x52]=true;T.raw[0x70]=true
T.step();T.action('settings')
assert(T.nativeCamPos.x==paused.pos.x and T.nativeCamPos.y==paused.pos.y and T.nativeCamPos.z==paused.pos.z,'foreign NUI stops all smoothing velocity immediately')
assert(T.last('state').camera.rot.z==paused.rot.z,'foreign NUI stops pending rotation immediately')
assert(T.last('state').settings.stabilization=='strong' and not T.last('state').recording and T.last('state').flight,'foreign NUI blocks shortcuts')
T.otherFocus=false;T.mouseX=0;T.raw={};T.step()
T.raw[0x45]=true;T.mouseY=-.5;T.step();T.action('settings');paused=FC.Core.copy(T.last('state').camera)
T.paused=true;T.step();T.action('settings')
assert(T.nativeCamPos.z==paused.pos.z and T.last('state').camera.rot.x==paused.rot.x,'pause has no translation or rotation drift')
T.paused=false;T.mouseY=0;T.raw={};T.step()
T.raw[0x70]=true;T.step()
assert(T.focus and not T.last('state').flight and T.last('help'),'F1 returns to editor and opens help')
assert(T.rendering==100 and T.frozen,'help preserves the active camera')
local helpPose=FC.Core.copy(T.nativeCamPos);T.step()
assert(T.nativeCamPos.z==helpPose.z,'help has no smoothing drift')
T.raw={};T.action('flight',{enabled=true});T.step();T.raw[0x45]=true;T.step()
T.action('settings');local previous=FC.Core.copy(T.last('state').camera)
T.action('settings',{stabilization='light'});T.raw={};T.step();T.action('settings')
assert(T.nativeCamPos.z==previous.pos.z and T.last('state').camera.rot.x==previous.rot.x,'changing level removes residue without jumping')
T.action('flight',{enabled=false})
local frame=FC.Core.defaultFrame({x=4,y=7,z=8},{x=-10,y=0,z=170})
T.action('setCamera',{frame=frame});T.action('flight',{enabled=true});T.step()
assert(T.nativeCamPos.z==8,'newly selected camera has no prior velocity')
T.action('close');T.open();T.action('flight',{enabled=true});T.step()
assert(T.nativeCamPos.z==8,'reopened camera has no prior velocity')
''')

fallback=stabilized_runtime(False)
fallback.execute('''
T.action('settings',{stabilization='strong'});T.action('flight',{enabled=true})
T.action('input',{keys={'KeyE'},dx=50,dy=-50});T.step();T.action('settings')
local before=FC.Core.copy(T.last('state').camera)
assert(before.pos.z>2 and before.pos.z<2.08,'browser fallback also stabilizes vertical input')
T.step(600);T.action('settings')
assert(T.nativeCamPos.z==before.pos.z and T.last('state').camera.rot.x==before.rot.x,'stale input cancels both velocity and mouse target')
T.action('input',{keys={'KeyE'},dx=50,dy=-50});T.step()
local frame=FC.Core.defaultFrame({x=1,y=2,z=3},{x=10,y=0,z=150})
T.action('scene',{scene={version=1,name='Exact playback',frames={frame},loop=false,speed=1}})
T.action('seek',{time=0});T.step();T.action('settings')
assert(T.nativeCamPos.z==3 and T.last('state').camera.rot.z==150,'seek discards old smoothing')
T.action('play');T.step();T.action('settings')
assert(T.nativeCamPos.z==3 and T.last('state').camera.rot.z==150,'playback is not stabilized a second time')
''')
print('Stabilized runtime: native/fallback motion, J/R/F1 edges and focus guards, actual recorded poses, pause/stale-input stops, level changes, seek/reopen resets and unsmoothed playback passed.')

dense = director_runtime()
dense.execute('''
function TriggerLatentServerEvent(name,bandwidth,...)
 assert(bandwidth==1048576,'bulk transfer bandwidth is bounded')
 T.latent=(T.latent or 0)+1;TriggerServerEvent(name,...)
end
T.open()
local look=FC.Director.defaults();look.motion.type='sway';look.motion.amplitude=.4;look.motion.roll=.8
T.action('director',{director=look});T.frameTime=.034;T.step(34)
local first=FC.Core.copy(T.nativeCamPos)
T.action('settings',{stabilization='strong'});T.action('flight',{enabled=true})
T.action('record',{enabled=true});local began=T.tick
local sceneMessages=0
for _,item in ipairs(T.messages) do if item.type=='scene' then sceneMessages=sceneMessages+1 end end
local observed={}
for index=1,260 do
 T.action('input',{keys={'KeyW','KeyE'},dx=index%3,dy=-.5})
 T.frameTime=.034;T.step(34)
 observed[index]={time=(T.tick-began)/1000,pos=FC.Core.copy(T.nativeCamPos),rot=FC.Core.copy(T.nativeCamRot)}
 if T.lastSave() then T.ackSave() end
end
local afterMessages=0
for _,item in ipairs(T.messages) do if item.type=='scene' then afterMessages=afterMessages+1 end end
assert(afterMessages==sceneMessages,'dense recording never emits a scene payload per sample')
local autosaved=assert(T.lastSave())[3]
assert(#autosaved.scene.frames==1 and #autosaved.scene.frames[1].take.samples>200,'autosave includes in-progress dense take without ordinary keyframe cap')
T.action('settings');assert(T.last('state').recordingSamples==261,'one sample for each eligible rendered frame')
T.action('capture');assert(T.last('state').recording,'F cannot truncate a running take')
local heldFrame=FC.Core.copy(T.nativeCamPos)
T.tick=T.tick+7;T.action('record',{enabled=false})
local take=T.last('scene').scene.frames[1]
assert(#T.last('scene').scene.frames==1 and #take.take.samples==262,'more than 200 samples occupy one timeline clip')
assert(math.abs(take.duration-(T.tick-began)/1000)<1e-9,'final unscheduled endpoint preserves real duration')
assert(take.take.samples[1][2]==first.x and take.take.samples[1][4]==first.z,'first sample is the displayed director pose')
for index,actual in ipairs(observed) do
 local point=take.take.samples[index+1]
 assert(math.abs(point[1]-actual.time)<1e-9,'sample uses elapsed timestamp')
 assert(math.abs(point[2]-actual.pos.x)<1e-9 and math.abs(point[4]-actual.pos.z)<1e-9,'sample caches native rendered position including motion')
 assert(math.abs(point[5]-actual.rot.x)<1e-9 and math.abs(point[7]-actual.rot.z)<1e-9,'sample caches native rendered rotation')
end
assert(take.take.samples[#take.take.samples][4]==heldFrame.z,'stop appends last displayed pose')
T.action('flight',{enabled=false})
local sample=take.take.samples[90]
T.action('seek',{time=sample[1]})
assert(math.abs(T.nativeCamPos.x-sample[2])<1e-9 and math.abs(T.nativeCamPos.z-sample[4])<1e-9,'take playback does not add director sway again')
T.action('play');T.frameTime=.017;T.step(17);T.action('settings')
local expected=FC.Core.sample(T.last('scene').scene,T.last('state').time)
assert(math.abs(T.nativeCamPos.x-expected.pos.x)<1e-9,'playing take follows exact sampled path without another stabilization pass')
T.action('pause');T.action('record',{enabled=true});local start=T.tick
T.frameTime=.2;T.step(200);T.frameTime=.017;T.step(17);T.frameTime=.7;T.step(700)
T.action('record',{enabled=false})
local irregular=T.last('scene').scene.frames[2].take
assert(#irregular.samples==3,'slow frames do not create repeated catch-up samples')
assert(math.abs(irregular.duration-(T.tick-start)/1000)<1e-9,'irregular frames preserve elapsed duration')
T.action('record',{enabled=true});T.step(100);T.action('save',{name='Flush REC'})
local saved=T.server[#T.server]
assert(saved[1]=='arbat16_camera:storage' and #saved[4].scene.frames==3,'manual save first commits live recording')
assert(T.latent and T.latent>1,'workspace and named-scene bulk saves use latent transport when available')
T.action('record',{enabled=true});T.step(100);T.action('play')
assert(#T.last('scene').scene.frames==4 and not T.last('state').recording,'Play commits live recording before playback')
T.action('pause');T.action('record',{enabled=true});T.step(100);T.action('close');T.open()
assert(#T.last('open').scene.frames==5,'close retains final recorded endpoint for reopen')
''')

attached_rec = director_runtime()
attached_rec.execute('''
T.open();T.action('capture');T.action('attach',{mode='mount',rotate=true})
T.action('record',{enabled=true});T.frameTime=.05
T.entityX=10;T.step(50);T.entityX=20;T.step(50)
T.action('record',{enabled=false})
local frames=T.last('scene').scene.frames;local take=frames[2]
assert(T.last('state').attachment==false,'finished recording becomes an independent world path')
assert(frames[1].pos.x==20,'existing authored route is baked on detach')
assert(take.take.samples[1][2]==0 and take.take.samples[2][2]==10 and take.take.samples[3][2]==20,'recording retains actual moving-entity world positions')
T.action('seek',{time=frames[1].duration+.05})
assert(math.abs(T.nativeCamPos.x-10)<1e-9,'attached take playback does not transform world coordinates twice')
T.action('attach',{mode='mount',rotate=true});T.entityX=30;T.step(50)
T.action('save',{name='Attached existing take'})
local snapshot=T.server[#T.server][4].scene.frames[2].take.samples
assert(snapshot[1][2]==10 and snapshot[2][2]==20 and snapshot[3][2]==30,'saving an attached existing take bakes every sample')
T.action('attach',{mode='detach'})
local baked=T.last('scene').scene.frames[2].take.samples
assert(baked[1][2]==10 and baked[2][2]==20 and baked[3][2]==30,'detaching an existing take bakes every sample')
T.action('scene',{scene={version=1,name='Still hold',frames={},loop=false,speed=1}})
T.action('record',{enabled=true});T.frameTime=10;T.step(300000)
assert(not T.last('state').recording,'five-minute limit stops automatically')
local held=T.last('scene').scene.frames[1]
assert(held.duration==300 and #held.take.samples==2,'a still shot retains full real-time duration without invented samples')
assert(held.take.samples[1][2]==held.take.samples[2][2],'stationary recording remains stationary')
T.action('setCamera',{frame=held});assert(T.last('state').camera.take==nil,'selecting a take never places its sample array in per-frame camera state')
T.action('scene',{scene={version=1,name='30 Hz',frames={},loop=false,speed=1}})
T.action('record',{enabled=true});T.frameTime=1/60
for index=1,60 do T.step(index%3==0 and 16 or 17) end
T.action('settings')
assert(T.last('state').recordingSamples>=30 and T.last('state').recordingSamples<=31,'60 FPS flight records about 30 samples per second without schedule drift')
T.action('record',{enabled=false})
''')
load_during_rec = director_runtime()
load_during_rec.execute('''
T.open();T.action('capture');T.action('attach',{mode='mount',rotate=true})
T.action('load',{name='Another scene'});local request=T.server[#T.server]
T.action('record',{enabled=true});T.entityX=10;T.step(40)
local incoming={version=1,name='Another scene',frames={FC.Core.defaultFrame({x=100,y=0,z=2},{x=0,y=0,z=0})},loop=false,speed=1}
T.events['arbat16_camera:storageResult'](request[2],{ok=true,scene=incoming,items={}})
T.action('settings')
assert(T.last('state').recording and T.last('state').attachment.mode=='mount','late load cannot detach a target during recording')
assert(T.last('scene').scene.name=='New scene','late load preserves authored scene while recording')
assert(T.last('toast').message:find('Recording started while loading',1,true),'late load reports why it was not applied')
local events=#T.server;T.action('load',{name='Another scene'})
assert(#T.server==events and T.last('toast').message:find('Stop REC',1,true),'load initiated during REC is rejected before request')
T.action('record',{enabled=false})
assert(#T.last('scene').scene.frames==2 and T.last('scene').scene.frames[2].take,'rejected loads preserve the complete recording')
''')
record_limit = stabilized_runtime(True)
record_limit.execute('''
local full={version=1,name='Full timeline',frames={}}
for i=1,200 do local frame=FC.Core.defaultFrame({x=0,y=0,z=2});frame.id='full_'..i;full.frames[i]=frame end
T.action('scene',{scene=full});T.action('flight',{enabled=true})
T.raw[0x52]=true;T.step();T.action('settings')
assert(not T.last('state').recording,'native R cannot overfill a timeline')
assert(T.last('toast').message:find('Timeline is full',1,true),'native R explains why recording cannot start')
''')
print('Dense REC runtime: rendered poses, 260 samples in one clip, real timestamps/holds, no catch-up, in-progress autosave, final flushes, 5-minute limit, attachment world paths, load races, native limit feedback and single-pass motion playback passed.')

modifiers = stabilized_runtime(True)
modifiers.execute('''
T.frameTime=.02
T.action('flight',{enabled=true});T.raw[0x57]=true
local before=T.nativeCamPos.y;T.step(20);local normal=T.nativeCamPos.y-before
for _,code in ipairs({0xA0,0xA1,0x10}) do
 T.raw={[0x57]=true,[code]=true};before=T.nativeCamPos.y;T.step(20)
 assert(math.abs((T.nativeCamPos.y-before)/normal-4)<1e-8,'physical/legacy Shift must accelerate fourfold: '..code)
 T.raw={[0x57]=true};before=T.nativeCamPos.y;T.step(20)
 assert(math.abs((T.nativeCamPos.y-before)/normal-1)<1e-8,'releasing Shift restores normal speed')
end
T.raw={[0x57]=true,[0xA0]=true,[0xA1]=true,[0x10]=true};before=T.nativeCamPos.y;T.step(20)
assert(math.abs((T.nativeCamPos.y-before)/normal-4)<1e-8,'both Shifts and aggregate state apply only one multiplier')
T.raw[0xA0]=false;T.raw[0x10]=false;before=T.nativeCamPos.y;T.step(20)
assert(math.abs((T.nativeCamPos.y-before)/normal-4)<1e-8,'releasing left Shift keeps held right Shift active')
for _,code in ipairs({0xA2,0xA3,0xA4,0xA5,0x11,0x12}) do
 T.raw={[0x57]=true,[code]=true};before=T.nativeCamPos.y;T.step(20)
 assert(math.abs((T.nativeCamPos.y-before)/normal-.2)<1e-8,'physical/legacy slow modifier: '..code)
end
T.raw={[0x57]=true,[0xA0]=0,[0xA1]=0,[0x10]=0};before=T.nativeCamPos.y;T.step(20)
assert(math.abs((T.nativeCamPos.y-before)/normal-1)<1e-8,'numeric zero is not a held modifier')
T.raw={[0x57]=true,[0xA1]=1};before=T.nativeCamPos.y;T.step(20)
assert(math.abs((T.nativeCamPos.y-before)/normal-4)<1e-8,'numeric one is a held right modifier')
T.otherFocus=true;T.step(20);before=T.nativeCamPos.y;T.otherFocus=false;T.step(20)
assert(T.nativeCamPos.y==before,'side-specific held keys stay blocked after another UI takes focus')
T.raw={};T.step(20);T.raw={[0x57]=true,[0xA0]=true};before=T.nativeCamPos.y;T.step(20)
assert(math.abs((T.nativeCamPos.y-before)/normal-4)<1e-8,'fresh movement and physical Shift resume after focus')
''')
for level in ('off', 'light', 'medium', 'strong'):
    for code in (0xA0, 0xA1):
        boosted = stabilized_runtime(True)
        boosted.globals().modifierCode = code
        boosted.globals().smoothingLevel = level
        boosted.execute('''
T.frameTime=1/30;T.action('settings',{stabilization=smoothingLevel});T.action('flight',{enabled=true})
T.raw={[0x57]=true}
for i=1,90 do T.step(33) end
local before=T.nativeCamPos.y;T.step(33);local normal=T.nativeCamPos.y-before
T.raw[modifierCode]=true
for i=1,90 do T.step(33) end
before=T.nativeCamPos.y;T.step(33);local fast=T.nativeCamPos.y-before
assert(fast/normal>3.99 and fast/normal<4.01,'Shift reaches fourfold speed with '..smoothingLevel)
T.raw[modifierCode]=false
for i=1,90 do T.step(33) end
before=T.nativeCamPos.y;T.step(33)
assert(math.abs((T.nativeCamPos.y-before)/normal-1)<.01,'Shift release settles normally with '..smoothingLevel)
''')
print('Flight modifiers: left/right/aggregate Shift, Ctrl/Alt, release, BOOL normalization, focus guards and all stabilization levels passed.')

guides = director_runtime()
guides.execute('''
T.open()
local defaults=T.last('open').settings
assert(defaults.grid==false and defaults.gridType=='thirds' and defaults.gridOpacity==.6,'new workspaces default to hidden thirds at 60 percent')
T.action('settings',{speed=9,stabilization='light',showPath=false,showCameras=false,hideHud=false,letterbox=false,
 grid=true,gridType='golden',gridOpacity=.35})
local baseline=FC.Core.copy(T.last('state').settings)
local revision=T.last('scene').revision
local ratio=T.last('state').director.framing.ratio
local invalid={
 {gridType='spiral'},{gridType=true},{gridType={}},
 {gridOpacity=0},{gridOpacity=1.01},{gridOpacity='0.5'},{gridOpacity=0/0},{gridOpacity=math.huge},
 {grid='true'},{showPath=1},{showCameras='false'},{hideHud=0},{letterbox='true'},
 {speed=0},{speed=101},{speed='10'},{speed=0/0},{speed=-math.huge},{stabilization='cinematic'}
}
for _,bad in ipairs(invalid) do
 local proposal={speed=27,stabilization='strong',showPath=true,showCameras=true,hideHud=true,letterbox=true,
  grid=false,gridType='quarters',gridOpacity=.8}
 for key,value in pairs(bad) do proposal[key]=value end
 local rejection=T.request('settings',proposal)
 assert(not rejection.ok and type(rejection.error)=='string','invalid known setting rejected before acknowledgement')
 assert(rejection.revision==revision,'rejected settings do not alter scene revision')
 T.action('settings')
 for key,value in pairs(baseline) do
  assert(T.last('state').settings[key]==value,'invalid mixed settings must be transactional: '..key)
 end
 assert(T.last('state').director.framing.ratio==ratio,'rejected letterbox mixture cannot change framing')
end
for index,kind in ipairs({'thirds','golden','diagonals','quarters','center','safe'}) do
 local opacity=index==1 and .1 or index==6 and 1 or index/10
 T.action('settings',{grid=true,gridType=kind,gridOpacity=opacity})
 local actual=T.last('state').settings
 assert(actual.grid and actual.gridType==kind and actual.gridOpacity==opacity,'every supported guide and opacity boundary round-trips')
end
T.action('settings',{gridType='diagonals',gridOpacity=.45})
T.action('toggleGrid')
assert(T.last('state').settings.grid==false and T.last('toast').message=='Composition guides off','NUI action disables guides with feedback')
assert(T.last('state').settings.gridType=='diagonals' and T.last('state').settings.gridOpacity==.45,'toggle preserves selected pattern and opacity')
T.step(900);T.ackSave();T.step(900);T.saved=T.ackSave()
assert(T.saved.settings.grid==false and T.saved.settings.gridType=='diagonals' and T.saved.settings.gridOpacity==.45,'disabled guides retain their preferences in persisted workspace')
T.action('toggleGrid')
assert(T.last('state').settings.grid and T.last('toast').message=='Composition guides on','NUI action enables guides with feedback')
T.step(900);T.saved=T.ackSave()
assert(T.saved.settings.grid==true,'enabled state is also autosaved')
T.action('close');T.step(900);T.saved=T.ackSave();T.open()
local reopened=T.last('open').settings
assert(reopened.grid and reopened.gridType=='diagonals' and reopened.gridOpacity==.45,'closing and reopening restores all guide settings')
''')

guides_restored = director_runtime()
guides_restored.globals().saved = guides_restored.table_from(plain_table(guides.globals().T.saved), recursive=True)
guides_restored.execute('''
T.commands.ar16_cam();T.events['arbat16_camera:openAllowed'](true,{workspace=saved})
local actual=T.last('open').settings
assert(T.focus and actual.grid and actual.gridType=='diagonals' and actual.gridOpacity==.45,'fresh client restores guide pattern, opacity and visibility after reconnect')
''')

legacy_guides = director_runtime()
legacy_guides.globals().saved = legacy_guides.table_from(plain_table(guides.globals().T.saved), recursive=True)
legacy_guides.execute('''
saved.settings.gridType=nil;saved.settings.gridOpacity=nil;saved.settings.grid=true
T.commands.ar16_cam();T.events['arbat16_camera:openAllowed'](true,{workspace=saved})
local actual=T.last('open').settings
assert(T.focus and actual.grid and actual.gridType=='thirds' and actual.gridOpacity==.6,'legacy visible grid migrates without losing visibility')
''')

native_guides = director_runtime(True)
native_guides.execute('''
T.open();T.action('settings',{grid=false,gridType='safe',gridOpacity=.7})
local function enabled()
 T.action('settings');return T.last('state').settings.grid
end
T.raw[0x47]=true;T.action('flight',{enabled=true});T.step()
assert(not enabled(),'G held when entering flight does not toggle guides')
T.raw={};T.step();T.raw[0x47]=true;T.step()
assert(enabled(),'fresh native G enables guides without browser input')
T.step();T.step();assert(enabled(),'held G only toggles once')
assert(T.last('toast').message=='Composition guides on','native G shares guide feedback')
T.raw={};T.step();T.raw[0x47]=true;T.step()
assert(not enabled(),'second distinct native G disables guides')
T.raw={};T.step();T.otherFocus=true;T.raw[0x47]=true;T.step()
assert(not enabled(),'typing G in another NUI cannot change guides')
T.otherFocus=false;T.step();assert(not enabled(),'held G remains blocked after NUI releases focus')
T.raw={};T.step();T.raw[0x47]=true;T.step();assert(enabled(),'fresh G resumes after NUI focus')
T.raw={};T.step();T.paused=true;T.raw[0x47]=true;T.step()
assert(enabled(),'pause menu blocks G')
T.paused=false;T.step();assert(enabled(),'held G remains blocked after pause closes')
T.raw={};T.step();T.raw[0x47]=true;T.step();assert(not enabled(),'fresh G resumes after pause')
T.action('flight',{enabled=false});T.raw={};T.step();T.raw[0x47]=true;T.step()
assert(not enabled(),'raw G in editor fields cannot toggle guides')
T.action('flight',{enabled=true});T.step()
assert(not enabled(),'editor G held through flight entry is blocked')
T.raw={};T.step();T.raw[0x47]=true;T.step();assert(enabled(),'released editor G can subsequently toggle in flight')
local actual=T.last('state').settings
assert(actual.gridType=='safe' and actual.gridOpacity==.7,'native toggles keep selected pattern and opacity')
T.action('flight',{enabled=false});T.step(2200);T.ackSave();T.step(2200)
local saved=T.ackSave()
assert(saved.settings.grid and saved.settings.gridType=='safe' and saved.settings.gridOpacity==.7,'native G changes persist in autosaved workspace')
T.raw={};T.action('flight',{enabled=true});T.step(2200);T.ackSave();T.step(2200);T.ackSave()
local previousRequest=T.lastSave()[2]
T.raw[0x47]=true;T.step()
assert(not T.last('state').settings.grid,'native G publishes its own state without a NUI settings request')
T.step(2200)
assert(T.lastSave()[2]~=previousRequest,'native G itself schedules autosave without any later NUI action')
assert(T.ackSave().settings.grid==false,'native-only toggle persists its new visibility')
''')
print('Composition guides runtime: six patterns, opacity boundaries, transactional settings, NUI/native G toggles, entry/focus/pause guards, autosave/reopen/reconnect and legacy migration passed.')
