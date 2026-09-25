local C=dofile('resource/arbat16_camera/shared/core.lua')
local D=dofile('resource/arbat16_camera/shared/director.lua')
local checks=0
local function eq(a,b,label)checks=checks+1;assert(a==b,(label or 'value')..': '..tostring(a)..' ~= '..tostring(b))end
local function close(a,b,label)checks=checks+1;assert(math.abs(a-b)<0.000001,(label or 'value')..': '..a..' ~= '..b)end
local function sample(t,x,yaw,fov,focus,hour,minute,weather)
    return {t,x,2,3,0,0,yaw or 0,fov or 50,focus or 10,hour or 12,minute or 0,weather or 'SUNNY'}
end
local function recording()
    local f=C.defaultFrame({x=999,y=888,z=777},{x=0,y=0,z=99})
    f.id='recorded_1';f.duration=3;f.transition=nil
    f.take={duration=3,samples={sample(0,0,350),sample(1,0,350),sample(2,10,10,70,20),sample(3,10,10,70,20)}}
    return f
end
local function scene()return {frames={recording()}}end
local function rejects(raw,label)local out,err=C.validateScene(raw);eq(out,nil,label);eq(type(err),'string','error returned')end
local raw=scene();local s=assert(C.validateScene(raw));local f=s.frames[1]
eq(f.transition,'hold','recordings default to self-contained hold transition')
eq(f.pos.x,0,'first sample controls entry pose');eq(f.rot.z,350);eq(f.take.samples[4][1],3)
f.take.samples[2][2]=123;eq(raw.frames[1].take.samples[2][2],0,'recording validation copies input')
s=assert(C.validateScene(scene()))
for _, t in ipairs({0,.1,.5,.999,1})do close(C.sample(s,t).pos.x,0,'stationary recorded interval is exact')end
for _, t in ipairs({2,2.01,2.5,3,4})do close(C.sample(s,t).pos.x,10,'stationary final hold is exact')end
local mid,index,progress=C.sample(s,1.5)
close(mid.pos.x,5);close(mid.rot.z,360,'shortest rotation across wrap');close(mid.fov,60);close(mid.dof.focus,15)
close(progress,.5);eq(index,1);eq(mid.take,nil,'render pose omits dense samples');eq(mid._recorded,true,'render pose bypasses procedural motion')
mid.pos.x=999;mid.dof.focus=999;eq(s.frames[1].take.samples[2][2],0);eq(s.frames[1].dof.focus,10)
s.frames[1].duration=6;close(C.sample(s,3).pos.x,5,'editable duration retimes source data')
s.frames[1].easing='easeIn';s.frames[1].transition='cut';close(C.sample(s,3).pos.x,5,'take ignores frame easing and outgoing transition')
s.loop=true;close(C.sample(s,6).pos.x,0,'scene loop wraps recording to its start');close(C.sample(s,9).pos.x,5)
local prefix=C.defaultFrame({x=-5,y=0,z=0},{x=0,y=0,z=0});prefix.id='prefix';prefix.duration=2;prefix.transition='hold'
local mixed=assert(C.validateScene({frames={prefix,recording()}}))
close(C.sample(mixed,1).pos.x,-5);close(C.sample(mixed,2).pos.x,0);close(C.sample(mixed,3.5).pos.x,5)
close(C.sample(mixed,5).pos.x,10,'final recorded frame samples its endpoint, including preceding clip offset')
local suffix=C.defaultFrame({x=40,y=0,z=0},{x=0,y=0,z=0});suffix.id='suffix';suffix.duration=1
mixed=assert(C.validateScene({frames={recording(),suffix}}))
close(C.sample(mixed,2.999).pos.x,10,'recorded clip never drifts toward following frame');close(C.sample(mixed,3).pos.x,40,'boundary enters next clip')
local tiny=recording();tiny.duration=1e-8;tiny.take={duration=1e-8,samples={sample(0,0),sample(1e-8,10)}}
close(C.sample(assert(C.validateScene({frames={tiny}})),.5e-8).pos.x,5,'all positive clip durations sample correctly')
local midnight=recording();midnight.duration=2;midnight.take={duration=2,samples={sample(0,0,0,50,10,23,59,'rain'),sample(2,1,0,50,10,0,1,'SUNNY')}}
local night=assert(C.validateScene({frames={midnight}}));close(C.sample(night,1).timeHours,0,'clock interpolates across midnight')
eq(C.sample(night,1).weather,'RAIN','weather held until next timestamp');eq(C.sample(night,2).weather,'SUNNY')
local tolerance=scene();tolerance.frames[1].take.samples[4][1]=3.00005
eq(assert(C.validateScene(tolerance)).frames[1].take.samples[4][1],3,'endpoint tolerance normalizes to duration')

for _, mutate in ipairs({
    function(f)f.take=false end,function(f)f.take.duration=0 end,function(f)f.take.duration=301 end,
    function(f)f.take.extra=1 end,function(f)f.take.samples={}end,function(f)f.take.samples={sample(0,0)}end,
    function(f)f.take.samples={ [1]=sample(0,0),[3]=sample(3,3)}end,
    function(f)f.take.samples[1].extra=true end,function(f)f.take.samples[1][13]=0 end,
    function(f)f.take.samples[1][12]=nil end,function(f)f.take.samples[1][1]=.01 end,
    function(f)f.take.samples[2][1]=0 end,function(f)f.take.samples[2][1]=2.5 end,
    function(f)f.take.samples[4][1]=2.9 end,function(f)f.take.samples[2][1]=3 end,
    function(f)f.take.samples[1][2]=100001 end,function(f)f.take.samples[1][5]=360001 end,
    function(f)f.take.samples[1][8]=0 end,function(f)f.take.samples[1][9]=0 end,
    function(f)f.take.samples[1][10]=24 end,function(f)f.take.samples[1][11]=1.5 end,
    function(f)f.take.samples[1][12]='rain;clear'end,function(f)f.take.samples[1][3]=math.huge end,
    function(f)f.take.samples[1][4]=0/0 end,function(f)f.duration=0 end,
    function(f)f.take.samples=setmetatable(f.take.samples,{})end,
    function(f)f.take.samples[1]=setmetatable(f.take.samples[1],{})end
})do local bad=scene();mutate(bad.frames[1]);rejects(bad,'invalid recording')end

local large=recording();large.duration=300;large.take={duration=300,samples={}}
for i=0,9000 do large.take.samples[i+1]=sample(i/30,i%7)end
eq(#assert(C.validateScene({frames={large}})).frames[1].take.samples,9001,'five minutes at 30Hz plus initial endpoint')
local second=C.copy(large);second.id='recorded_2'
local limit=assert(C.validateScene({frames={large,second}}));eq(#limit.frames[2].take.samples,9001,'scene capacity admits two maximum takes')
local third=recording();third.id='recorded_3';rejects({frames={large,second,third}},'scene total sample cap')
large.take.samples[9002]=sample(300.001,0);rejects({frames={large}},'single take sample cap')

-- Instrument copy calls: render work must not traverse the sample payload.
local originalCopy=C.copy;local copiedTake=false;local copiedSample=false
C.copy=function(value,seen)
    if value==limit.frames[1].take then copiedTake=true end
    if value==limit.frames[1].take.samples[1] then copiedSample=true end
    return originalCopy(value,seen)
end
local rendered=C.sample(limit,123.456)
C.copy=originalCopy
eq(copiedTake,false,'render avoids full take copy');eq(copiedSample,false,'render samples scalars only');eq(rendered.take,nil)
local workspace={scene=assert(C.validateScene(scene())),camera=C.defaultFrame({x=0,y=0,z=0},{x=0,y=0,z=0}),cameras={},presets={}}
assert(D.validateWorkspace(workspace));workspace.camera=recording()
eq(D.validateWorkspace(workspace),nil,'current camera cannot contain a dense recording')
workspace.camera=C.defaultFrame({x=0,y=0,z=0},{x=0,y=0,z=0});workspace.cameras={{id='bank_1',name='Bank',frame=recording()}}
eq(D.validateWorkspace(workspace),nil,'bank entries cannot contain dense recordings')
print(('Recorded takes: %d checks passed'):format(checks))
