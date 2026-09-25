local C = dofile('resource/arbat16_camera/shared/core.lua')
local D = dofile('resource/arbat16_camera/shared/director.lua')
local checks = 0
local function equal(actual,expected,label)
    checks=checks+1; assert(actual==expected,(label or 'value')..': '..tostring(actual)..' ~= '..tostring(expected))
end
local function close(actual,expected,label)
    checks=checks+1; assert(math.abs(actual-expected)<0.000001,(label or 'number')..': '..tostring(actual)..' ~= '..tostring(expected))
end
local function camera() return C.defaultFrame({x=1,y=2,z=3},{x=0,y=0,z=0}) end
local function workspace()
    return {version=1,scene={name='Test',frames={camera()},director=D.defaults()},camera=camera(),
        settings={speed=5,showPath=true,hideHud=true,letterbox=false,grid=false},
        cameras={{id='cam_1',name='Camera 1',frame=camera(),director=D.defaults()}},
        presets={{id='preset_1',name='Custom look',director=D.defaults(),fov=40,focus=4}},time=1}
end
local function rejects(fn,raw,label)
    local out,err=fn(raw); equal(out,nil,label); equal(type(err),'string','validation error')
end
local basic = assert(D.validate({}))
equal(basic.look.filter,'none'); equal(basic.motion.type,'none'); equal(basic.framing.ratio,'native')
for _, filter in ipairs(D.filters) do equal(assert(D.validate({look={filter=filter.id}})).look.filter,filter.id) end
local monochrome
for _, filter in ipairs(D.filters) do if filter.id=='monochrome' then monochrome=filter end end
equal(monochrome.label,'Black & White')
equal(monochrome.postfx,'PhotoMode_FilterModern07','verified native Noir effect')
equal(monochrome.modifier,nil,'photo effect is never passed as a timecycle name')
for _, ratio in ipairs(D.ratios) do equal(assert(D.validate({framing={ratio=ratio}})).framing.ratio,ratio) end
for _, preset in ipairs(D.presets) do assert(D.validate(preset.director)) end
for _, mutate in ipairs({
    function(d)d.look.filter='GTA_only'end, function(d)d.look.strength=1.001 end,
    function(d)d.framing.ratio='cinema'end, function(d)d.framing.opacity=-.1 end,
    function(d)d.motion.type='random'end, function(d)d.motion.amplitude=2.1 end,
    function(d)d.motion.frequency=3.1 end, function(d)d.motion.roll=5.1 end,
    function(d)d.look=false end,function(d)d.extra=true end,
    function(d)d.motion.amplitude=0/0 end,function(d)d.motion.frequency=math.huge end
}) do local raw=D.defaults();mutate(raw);rejects(D.validate,raw,'invalid director') end
rejects(D.validate,setmetatable({},{__index={}}),'metatable')
local bounded=assert(D.validate({look={strength=0},framing={opacity=0},motion={amplitude=2,frequency=3,roll=5}}))
equal(bounded.motion.roll,5)
local old=assert(C.validateScene({frames={camera()}})); equal(old.director,nil,'old scene must not gain a director field')
local scene=assert(C.validateScene({frames={camera()},director={look={filter='dusk'}}}))
equal(scene.director.look.filter,'dusk'); equal(scene.director.motion.type,'none')
rejects(C.validateScene,{frames={},director={extra=1}},'invalid scene director')

local saved=workspace(); local restored=assert(D.validateWorkspace(saved))
equal(restored.scene.director.look.filter,'none');equal(restored.cameras[1].name,'Camera 1')
equal(restored.presets[1].fov,40);equal(restored.time,1)
local monochromeWorkspace=workspace()
for _,director in ipairs({monochromeWorkspace.scene.director,monochromeWorkspace.cameras[1].director,monochromeWorkspace.presets[1].director}) do
    director.look={filter='monochrome',strength=.75}
end
local monochromeRestored=assert(D.validateWorkspace(monochromeWorkspace))
for _,director in ipairs({monochromeRestored.scene.director,monochromeRestored.cameras[1].director,monochromeRestored.presets[1].director}) do
    equal(director.look.filter,'monochrome');equal(director.look.strength,.75)
end
equal(restored.settings.stabilization,'off','old workspaces keep direct flight until stabilization is enabled')
equal(restored.settings.showCameras,true,'old workspaces show saved camera guides by default')
equal(restored.settings.gridType,'thirds','legacy workspaces retain the thirds guide')
close(restored.settings.gridOpacity,0.6,'legacy workspaces receive readable guide opacity')
for _,enabled in ipairs({true,false}) do
    local raw=workspace();raw.settings.grid=enabled
    local migrated=assert(D.validateWorkspace(raw))
    equal(migrated.settings.grid,enabled,'migration preserves enabled composition guides')
    equal(migrated.settings.gridType,'thirds');close(migrated.settings.gridOpacity,0.6)
    equal(raw.settings.gridType,nil,'migration does not modify the saved input')
end
local missingSettings=workspace();missingSettings.settings=nil
local defaultSettings=assert(D.validateWorkspace(missingSettings)).settings
equal(defaultSettings.grid,false);equal(defaultSettings.gridType,'thirds');close(defaultSettings.gridOpacity,0.6)
for _,gridType in ipairs({'thirds','golden','diagonals','quarters','center','safe'}) do
    for _,opacity in ipairs({0.1,0.6,1}) do
        local raw=workspace();raw.settings.grid=true;raw.settings.gridType=gridType;raw.settings.gridOpacity=opacity
        local validated=assert(D.validateWorkspace(raw))
        equal(validated.settings.gridType,gridType,'composition guide selection survives validation')
        close(validated.settings.gridOpacity,opacity,'composition opacity survives validation')
        equal(validated.settings.grid,true)
    end
end
for _,invalid in ipairs({'Thirds','diagonal','',1,true,{}}) do
    local raw=workspace();raw.settings.gridType=invalid
    rejects(D.validateWorkspace,raw,'invalid composition grid type')
end
for _,invalid in ipairs({0,0.099,1.001,-1,math.huge,-math.huge,0/0,'0.6',true,{}}) do
    local raw=workspace();raw.settings.gridOpacity=invalid
    rejects(D.validateWorkspace,raw,'invalid composition grid opacity')
end
rejects(D.validateSettings,{grid=true,gridType='safe',unexpected=1},'unknown live setting')
rejects(D.validateSettings,setmetatable({grid=true},{}),'settings must be plain data')
local disabledGrid=assert(D.validateSettings({grid=false,gridType='golden',gridOpacity=0.25}))
equal(disabledGrid.grid,false);equal(disabledGrid.gridType,'golden');close(disabledGrid.gridOpacity,0.25)
for _,enabled in ipairs({true,false}) do
    local raw=workspace();raw.settings.showCameras=enabled
    equal(assert(D.validateWorkspace(raw)).settings.showCameras,enabled,'saved camera guide preference survives validation')
end
for _,invalid in ipairs({'true',0,1,{}}) do
    local raw=workspace();raw.settings.showCameras=invalid
    rejects(D.validateWorkspace,raw,'invalid saved camera guide preference')
end
for _,level in ipairs({'off','light','medium','strong'}) do
    local raw=workspace();raw.settings.stabilization=level
    equal(assert(D.validateWorkspace(raw)).settings.stabilization,level,'stabilization survives workspace validation')
end
for _,invalid in ipairs({'maximum','',1,true,{}}) do
    local raw=workspace();raw.settings.stabilization=invalid
    rejects(D.validateWorkspace,raw,'unknown stabilization setting cannot enter persisted workspace')
end
restored.camera.pos.x=99;equal(saved.camera.pos.x,1,'workspace must copy live camera')
restored.cameras[1].director.look.filter='flat';equal(saved.cameras[1].director.look.filter,'none','workspace must copy look')
local unicode=workspace();unicode.cameras[1].name='Камера';equal(assert(D.validateWorkspace(unicode)).cameras[1].name,'Камера')
local maximum=workspace();maximum.cameras={};maximum.presets={}
for i=1,100 do maximum.cameras[i]={id='cam_'..i,name='Camera '..i,frame=camera(),director=D.defaults()} end
for i=1,40 do maximum.presets[i]={id='preset_'..i,name='Preset '..i,director=D.defaults(),fov=50,focus=10} end
equal(#assert(D.validateWorkspace(maximum)).cameras,100)
equal(#assert(D.validateWorkspace(maximum)).presets,40)
for _, mutate in ipairs({
    function(w)w.cameras[101]=w.cameras[1]end,function(w)w.presets[41]=w.presets[1]end,
    function(w)w.cameras[2]=C.copy(w.cameras[1])end,function(w)w.presets[2]=C.copy(w.presets[1])end,
    function(w)w.cameras[1].name='../camera'end,function(w)w.presets[1].name='a\\b'end,
    function(w)w.cameras[1].name='a'..utf8.char(133)..'b'end,function(w)w.cameras[1].name=string.rep('я',33)end,
    function(w)w.cameras[1].name='bad\0name'end,function(w)w.camera.pos.x=math.huge end,
    function(w)w.settings.speed=100.01 end,function(w)w.settings.grid='true'end,
    function(w)w.camera.timeHours=1 end,function(w)w.scene.name='..'end,
    function(w)w.time=4 end,function(w)w.cameras[1].director=false end,
    function(w)w.cameras={ [2]=w.cameras[1] }end,function(w)w.presets[1].focus=0 end,
    function(w)w.cameras[1].extra=true end,function(w)w.extra=true end
}) do local raw=workspace();mutate(raw);rejects(D.validateWorkspace,raw,'invalid workspace')end

local base=camera();local moving=D.defaults();moving.motion.type='sway'
local still=D.motionPose(base,moving,0);close(still.pos.x,base.pos.x);close(still.rot.y,base.rot.y)
local first=D.motionPose(base,moving,1.25);close(first.pos.x,base.pos.x+.15);close(first.rot.y,.25)
local repeated=D.motionPose(base,moving,1.25);close(first.pos.x,repeated.pos.x,'time-based motion reproducible')
equal(base.pos.x,1,'motion must not drift base pose');equal(base.rot.y,0)
for _, mode in ipairs({'sway','handheld'}) do
    moving.motion.type=mode
    for i=0,100 do
        local pose=D.motionPose(base,moving,i/13)
        equal(math.abs(pose.pos.x-base.pos.x)<=.150001,true,'bounded motion translation')
        equal(math.abs(pose.rot.y-base.rot.y)<=.250001,true,'bounded motion roll')
    end
end
for _, kind in ipairs({'dolly','truck','crane','pan','orbit'}) do
    for _, goBack in ipairs({false,true}) do
        local frames=assert(D.generateMove(base,{kind=kind,distance=5,angle=90,duration=6,returnToStart=goBack}))
        close(C.duration({frames=frames}),6,'move duration');equal(frames[#frames].duration,0)
        equal(frames[1].pos.x,1);equal(frames[1].pos.y,2)
        equal(frames[1].fov,50);equal(frames[#frames].dof.focus,10)
        if goBack then
            for _,axis in ipairs({'x','y','z'}) do close(frames[#frames].pos[axis],base.pos[axis]);close(frames[#frames].rot[axis],base.rot[axis]) end
        end
        assert(C.validateScene({frames=frames}))
    end
end
local dolly=assert(D.generateMove(base,{kind='dolly'}));close(dolly[#dolly].pos.y,7)
local truck=assert(D.generateMove(base,{kind='truck'}));close(truck[#truck].pos.x,6)
local crane=assert(D.generateMove(base,{kind='crane'}));close(crane[#crane].pos.z,8)
local pan=assert(D.generateMove(base,{kind='pan',angle=360}));close(pan[#pan].rot.z,360)
local orbit=assert(D.generateMove(base,{kind='orbit',angle=90}));close(orbit[#orbit].pos.x,6);close(orbit[#orbit].pos.y,7)
for _, options in ipairs({{kind='bad'},{kind='dolly',duration=0},{kind='orbit',distance=0},{kind='pan',angle=361},
    {kind='crane',distance=501},{kind='truck',returnToStart=1},{kind='dolly',extra=true}}) do
    local out,err=D.generateMove(base,options);equal(out,nil,'invalid generated move');equal(type(err),'string')
end
equal(base.pos.x,1,'generator must not mutate original')

-- A filter is a single shared game slot: updates are idempotent and cleanup
-- cannot clear another resource's replacement or an untouched original effect.
local calls,index,ids={},41,{PlayerCamera=10,FlatProfile=11}
local effects,strengths={},{}
local failedNative
local function mockNative(native,...)
    local values={...};calls[#calls+1]={native,table.unpack(values)}
    if native==failedNative then error('mock unavailable native: '..native) end
    if native=='GET_TIMECYCLE_MODIFIER_INDEX' then return index end
    if native=='SET_TIMECYCLE_MODIFIER' then index=ids[values[1]] or 12 end
    if native=='CLEAR_TIMECYCLE_MODIFIER' then index=-1 end
    if native=='ANIMPOSTFX_IS_RUNNING' then return effects[values[1]]==true end
    if native=='ANIMPOSTFX_PLAY' then effects[values[1]]=true end
    if native=='ANIMPOSTFX_STOP' then effects[values[1]]=false end
    if native=='_ANIMPOSTFX_SET_STRENGTH' then strengths[values[1]]=values[2] end
end
FC.Natives={call=mockNative}
local R=dofile('resource/arbat16_camera/client/director.lua')
R.apply(D.defaults());R.cleanup();equal(index,41,'no filter must preserve original effect')
local look=D.defaults();look.look.filter='player_camera';R.apply(look);equal(index,10)
local before=#calls;R.apply(look);equal(#calls,before,'unchanged effect must not call game natives')
look.look.strength=.2;R.apply(look);equal(calls[#calls][1],'SET_TIMECYCLE_MODIFIER_STRENGTH')
index=99;R.cleanup();equal(index,99,'cleanup must preserve another resource replacement')
R.apply(look);equal(index,10);R.cleanup();equal(index,-1,'cleanup clears own active effect')
R.apply(look);look.look.strength=0;R.apply(look);equal(index,-1,'zero strength clears own effect')
local mono=D.defaults();mono.look={filter='monochrome',strength=1}
local effect=monochrome.postfx
effects.UnrelatedGameplayEffect=true
index=41;equal(R.apply(mono),true);equal(effects[effect],true,'monochrome starts native photo effect')
equal(strengths[effect],1);equal(index,41,'photo effect leaves unowned timecycle intact')
before=#calls;R.apply(mono);equal(#calls,before,'unchanged monochrome is not restarted every frame')
mono.look.strength=.25;R.apply(mono);equal(calls[#calls][1],'_ANIMPOSTFX_SET_STRENGTH');equal(strengths[effect],.25)
look.look.strength=.6;R.apply(look);equal(effects[effect],false,'switching to timecycle stops owned photo effect');equal(index,10)
R.apply(mono);equal(index,-1,'switching to photo effect clears owned timecycle');equal(effects[effect],true)
mono.look.strength=0;R.apply(mono);equal(effects[effect],false,'zero strength stops monochrome')
mono.look.strength=1;R.apply(mono);R.cleanup();equal(effects[effect],false,'cleanup stops owned monochrome')
equal(effects.UnrelatedGameplayEffect,true,'unrelated gameplay effects survive cleanup')
effects[effect]=true;strengths[effect]=.42;before=#calls
R.apply(mono);mono.look.strength=.5;R.apply(mono);R.cleanup()
equal(effects[effect],true,'cleanup cannot stop pre-existing monochrome effect')
equal(strengths[effect],.42,'pre-existing effect strength remains owned by its caller')
for i=before+1,#calls do equal(calls[i][1]~='ANIMPOSTFX_STOP' and calls[i][1]~='_ANIMPOSTFX_SET_STRENGTH',true,'external effect is not mutated') end
effects[effect]=false;failedNative='_ANIMPOSTFX_SET_STRENGTH'
equal(R.apply(mono),false,'strength native failure is isolated');equal(effects[effect],true)
failedNative=nil;equal(R.cleanup(),true);equal(effects[effect],false,'cleanup still owns effect after strength failure')
failedNative='ANIMPOSTFX_PLAY';equal(R.apply(mono),false,'play native failure is isolated')
failedNative=nil;equal(R.cleanup(),true,'failed start remains safe to clean')
R.apply(mono);R.apply(D.defaults());equal(effects[effect],false,'Original clears only owned monochrome')
for _,call in ipairs(calls) do equal(call[1]~='ANIMPOSTFX_STOP_ALL',true,'no global postfx cleanup') end
FC.Natives.call=function()error('mock unavailable native')end
look.look.strength=.5;equal(R.apply(look),false,'native failure must not terminate camera loop')
equal(R.apply(look),true,'unchanged failure must not spam retries')
-- Exercise the real wrapper's float signature without a game process.
dofile('resource/arbat16_camera/client/natives.lua')
local invoked
Citizen={InvokeNative=function(hash,...)invoked={hash=hash,args=table.pack(...)};return 1 end,
    ReturnResultAnyway=function()return 'return'end,ResultAsInteger=function()return 'integer'end}
FC.Natives.call('_ANIMPOSTFX_SET_STRENGTH',effect,1)
equal(invoked.hash,0xCAB4DD2D5B2B7246);equal(invoked.args[1],effect);equal(math.type(invoked.args[2]),'float')
equal(FC.Natives.call('ANIMPOSTFX_IS_RUNNING',effect),true,'postfx running native uses normalized BOOL')
equal(pcall(FC.Natives.call,'ANIMPOSTFX_PLAY',effect,0),false,'RDR3 postfx play accepts only the effect name')
print(('Director: %d checks passed'):format(checks))
