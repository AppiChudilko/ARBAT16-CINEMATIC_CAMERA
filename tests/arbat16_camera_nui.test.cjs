// Pure DOM/transport checks. No browser, game window or Computer Use automation.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
let jsdom;
try { jsdom=require('jsdom'); } catch(error) { if(error.code!=='MODULE_NOT_FOUND')throw error;jsdom=require('../artifacts/camera-test-deps/node_modules/jsdom'); }
const {JSDOM,VirtualConsole} = jsdom;
const web = path.join(__dirname, '../resource/arbat16_camera/web');
const flush = async () => { for (let i=0;i<4;i++) await new Promise(setImmediate); };

function fixture(nativeFlightInput) {
  const errors=[],virtualConsole=new VirtualConsole();virtualConsole.on('jsdomError',error=>errors.push(error));
  const dom = new JSDOM(fs.readFileSync(path.join(web, 'index.html'), 'utf8'), {
    url:'https://cfx-nui-arbat16_camera/', runScripts:'outside-only', pretendToBeVisual:true,virtualConsole
  });
  const w=dom.window, requests=[], intervals=[], pending=[];
  w.TextEncoder=TextEncoder;w.GetParentResourceName=()=> 'arbat16_camera';
  // jsdom omits dialog's browser top-layer implementation. These test-only
  // shims model the open / close contract; no production API is replaced.
  w.HTMLDialogElement.prototype.showModal=function(){this.setAttribute('open','');};
  w.HTMLDialogElement.prototype.close=function(){this.removeAttribute('open');this.dispatchEvent(new w.Event('close'));};
  w.setInterval=fn=>{intervals.push(fn);return intervals.length;};
  let pointerRequests=0, actionHandler=null;
  w.document.getElementById('viewport').requestPointerLock=()=>{pointerRequests++;};
  w.fetch=async (_url, options)=>{
    const data=JSON.parse(options.body);requests.push(data);
    if(actionHandler){const custom=actionHandler(data);if(custom)return custom;}
    if(data.action==='flight')return new Promise(resolve=>pending.push(()=>resolve({ok:true,json:async()=>({ok:true,revision:1,stateSequence:5})})));
    return {ok:true,json:async()=>({ok:true,revision:1,stateSequence:1})};
  };
  w.eval(fs.readFileSync(path.join(web,'director.js'),'utf8'));
  w.eval(fs.readFileSync(path.join(web,'model.js'),'utf8'));
  w.eval(fs.readFileSync(path.join(web,'app.js'),'utf8'));
  const message=data=>w.dispatchEvent(new w.MessageEvent('message',{data:w.JSON.parse(JSON.stringify(data))}));
  const scene={name:'Input regression',frames:[{id:'first',pos:{x:0,y:0,z:2},rot:{x:0,y:0,z:0}},{id:'second',pos:{x:0,y:10,z:2},rot:{x:0,y:0,z:0}}]};
  message({type:'open',scene,camera:scene.frames[0],revision:1,stateSequence:1,capabilities:{nativeFlightInput}});
  return {w,requests,intervals,pending,message,scene,onRequest:fn=>{actionHandler=fn;},close:()=>{w.close();assert.deepEqual(errors.map(error=>error.message),[],'Unexpected DOM errors');},pointerRequests:()=>pointerRequests,
    el:id=>w.document.getElementById(id)};
}

test('native flight skips browser capture/packets and survives delayed state snapshots',async()=>{
  const f=fixture(true);
  try {
    await flush();assert.equal(f.el('editor').hidden,false);
    f.el('flight-button').click();await flush();
    assert.equal(f.requests.at(-1).action,'flight');
    f.message({type:'state',stateSequence:1,flight:false});
    assert.equal(f.el('flight-label').textContent,'Return to Editor');
    f.pending.shift()();await flush();
    f.message({type:'state',stateSequence:4,flight:false});
    assert.equal(f.el('flight-label').textContent,'Return to Editor');
    assert.equal(f.pointerRequests(),0);
    const inputCount=f.requests.filter(r=>r.action==='input').length;
    f.w.document.dispatchEvent(new f.w.KeyboardEvent('keydown',{code:'KeyW',bubbles:true}));
    f.intervals.forEach(fn=>fn());await flush();
    assert.equal(f.requests.filter(r=>r.action==='input').length,inputCount);
    f.message({type:'toggleClean'});assert.equal(f.el('editor').classList.contains('clean'),true);
    f.message({type:'state',stateSequence:6,flight:false,playing:false});
    assert.equal(f.el('flight-label').textContent,'Move Camera');
    assert.equal(f.w.document.activeElement,f.el('viewport'));
    f.message({type:'close'});assert.equal(f.el('editor').hidden,true);
  } finally {f.close();}
});

test('older clients retain browser flight input and play is routed to Lua',async()=>{
  const f=fixture(false);
  try {
    await flush();f.el('flight-button').click();await flush();
    f.pending.shift()();await flush();assert.equal(f.pointerRequests(),1);
    f.el('viewport').dispatchEvent(new f.w.KeyboardEvent('keydown',{code:'KeyW',bubbles:true}));
    f.intervals.forEach(fn=>fn());await flush();
    assert.ok(f.requests.some(r=>r.action==='input'&&r.keys.includes('KeyW')));
    f.el('play').click();await flush();assert.equal(f.requests.at(-1).action,'play');
    f.message({type:'state',stateSequence:6,flight:false,playing:true,time:1});
    assert.equal(f.el('play').getAttribute('aria-label'),'Pause Route');
    assert.equal(f.el('timecode').textContent,'00:01:00');
  } finally {f.close();}
});


function change(f,id,value){
  const el=f.el(id);el.value=String(value);el.dispatchEvent(new f.w.Event('input',{bubbles:true}));el.dispatchEvent(new f.w.Event('change',{bubbles:true}));
}
const latest=(f,action)=>f.requests.filter(r=>r.action===action).at(-1);

test('precise values route to Lua, blank / out-of-range numbers never write zero',async()=>{
  const f=fixture(true);
  try{
    await flush();
    change(f,'fov-value',37.125);await flush();assert.equal(latest(f,'lens').fov,37.125);
    const count=f.requests.length;change(f,'fov-value','');await flush();assert.equal(f.requests.length,count);assert.equal(f.el('fov-value').getAttribute('aria-invalid'),'true');
    change(f,'fov-value',131);await flush();assert.equal(f.requests.length,count);
    change(f,'fov-value',45.375);await flush();assert.equal(latest(f,'lens').fov,45.375);assert.equal(f.el('fov-value').hasAttribute('aria-invalid'),false);
    change(f,'roll-value',-12.75);await flush();assert.equal(latest(f,'lens').roll,-12.75);
    change(f,'fly-speed-value',2.75);await flush();assert.equal(latest(f,'settings').speed,2.75);
    change(f,'playback-speed',1.125);await flush();assert.equal(latest(f,'scene').scene.speed,1.125);
    change(f,'scrubber-value',2.375);await flush();assert.equal(latest(f,'seek').time,2.375);
    const seeks=f.requests.filter(r=>r.action==='seek').length;change(f,'scrubber-value',99);await flush();assert.equal(f.requests.filter(r=>r.action==='seek').length,seeks);
    for(const slider of f.w.document.querySelectorAll('input[type=range]'))assert.ok(f.el(slider.id+'-value'),'missing exact numeric field: '+slider.id);
  }finally{f.close();}
});

test('director filters, masks and continuous motion use validated game actions',async()=>{
  const f=fixture(true);
  try{
    await flush();change(f,'look-filter','cinematic');await flush();assert.equal(latest(f,'director').director.look.filter,'cinematic');
    change(f,'look-strength-value',.4321);await flush();assert.equal(latest(f,'director').director.look.strength,.4321);
    change(f,'frame-ratio','16:9');await flush();assert.equal(f.el('letterbox').hidden,false);assert.equal(f.el('letterbox').style.getPropertyValue('--frame-y'),'12.5%');assert.equal(f.el('letterbox').style.getPropertyValue('--frame-x'),'0%');
    Object.defineProperty(f.w,'innerWidth',{value:3440,configurable:true});Object.defineProperty(f.w,'innerHeight',{value:1440,configurable:true});f.w.dispatchEvent(new f.w.Event('resize'));
    assert.equal(f.el('letterbox').style.getPropertyValue('--frame-y'),'0%');assert.ok(parseFloat(f.el('letterbox').style.getPropertyValue('--frame-x'))>12);
    f.el('clean-button').click();assert.equal(f.el('editor').classList.contains('clean'),true);assert.equal(f.el('letterbox').hidden,false);
    change(f,'frame-opacity-value',.8);await flush();assert.equal(f.el('letterbox').style.opacity,'0.8');
    change(f,'motion-type','sway');await flush();change(f,'motion-amplitude-value',.125);await flush();change(f,'motion-frequency-value',.33);await flush();change(f,'motion-roll-value',.75);await flush();
    const motion=latest(f,'director').director.motion;assert.deepEqual(motion,{type:'sway',amplitude:.125,frequency:.33,roll:.75});
    f.el('show-bars').checked=true;f.el('show-bars').dispatchEvent(new f.w.Event('change'));await flush();assert.equal(latest(f,'director').director.framing.ratio,'2.39');
    f.el('show-bars').checked=false;f.el('show-bars').dispatchEvent(new f.w.Event('change'));await flush();assert.equal(f.el('letterbox').hidden,true);
  }finally{f.close();}
});

test('camera bank and custom presets save, recall, update and delete with stable IDs',async()=>{
  const f=fixture(true);
  try{
    await flush();const camera={id:'camera_1',name:'Station Roof',frame:{...f.scene.frames[0],fov:45}},preset={id:'preset_1',name:'My Western',director:{},fov:45,focus:10};
    f.message({type:'workspace',cameras:[camera],presets:[preset],status:'saved'});
    assert.equal(f.el('camera-bank-count').textContent,'1');assert.equal(f.el('workspace-status').textContent,'Workspace saved');assert.equal(f.el('camera-recall').disabled,false);
    f.el('camera-recall').click();await flush();assert.equal(latest(f,'cameraRecall').id,'camera_1');
    f.el('camera-update').click();assert.equal(f.el('asset-name').value,'Station Roof');f.el('asset-name').value='Station Roof West';
    [...f.el('modal-body').querySelectorAll('button')].find(b=>b.textContent==='Update').click();await flush();assert.deepEqual(latest(f,'cameraSave'),{action:'cameraSave',id:'camera_1',name:'Station Roof West'});
    f.el('camera-save').click();f.el('asset-name').value='River Bridge';[...f.el('modal-body').querySelectorAll('button')].find(b=>b.textContent==='Save').click();await flush();assert.deepEqual(latest(f,'cameraSave'),{action:'cameraSave',name:'River Bridge'});
    f.el('camera-delete').click();[...f.el('modal-body').querySelectorAll('button')].find(b=>b.textContent==='Delete').click();await flush();assert.equal(latest(f,'cameraDelete').id,'camera_1');
    assert.ok([...f.el('preset-select').options].some(o=>o.value==='western_scope'));
    change(f,'preset-select','western_scope');f.el('preset-apply').click();await flush();assert.equal(latest(f,'presetApply').id,'western_scope');assert.equal(f.el('custom-preset-actions').hidden,true);
    change(f,'preset-select','preset_1');assert.equal(f.el('custom-preset-actions').hidden,false);f.el('preset-update').click();f.el('asset-name').value='Portrait Warm';[...f.el('modal-body').querySelectorAll('button')].find(b=>b.textContent==='Update').click();await flush();assert.equal(latest(f,'presetSave').id,'preset_1');
    f.el('preset-delete').click();[...f.el('modal-body').querySelectorAll('button')].find(b=>b.textContent==='Delete').click();await flush();assert.equal(latest(f,'presetDelete').id,'preset_1');
    f.message({type:'workspace',status:'saving'});assert.equal(f.el('camera-bank').value,'camera_1');assert.equal(f.el('preset-select').value,'preset_1');assert.equal(f.el('workspace-status').textContent,'Saving workspace…');assert.notEqual(f.el('save-status').textContent,'Saved on server');
  }finally{f.close();}
});

test('move generator appends requested relative move and validates orbit radius',async()=>{
  const f=fixture(true);
  try{
    await flush();f.el('generate-move').click();change(f,'move-kind','orbit');change(f,'move-distance',0);f.el('move-return').checked=true;
    const append=[...f.el('modal-body').querySelectorAll('button')].find(b=>b.textContent==='Append Move');append.click();await flush();assert.equal(latest(f,'generateMove'),undefined);assert.equal(f.el('move-distance').getAttribute('aria-invalid'),'true');
    change(f,'move-distance',12.5);change(f,'move-angle',-90);change(f,'move-duration',12);append.click();await flush();assert.deepEqual(latest(f,'generateMove'),{action:'generateMove',kind:'orbit',distance:12.5,angle:-90,duration:12,returnToStart:true});
    assert.equal(f.el('modal').open,false);
  }finally{f.close();}
});

test('closing waits for queued scene changes before Lua snapshots the workspace',async()=>{
  const f=fixture(true);let release;
  try{
    await flush();f.onRequest(data=>data.action==='scene'?new Promise(resolve=>{release=()=>resolve({ok:true,json:async()=>({ok:true,revision:2,stateSequence:2})});}):undefined);
    change(f,'playback-speed',1.75);await flush();assert.ok(release);f.el('close').click();await flush();assert.equal(latest(f,'close'),undefined);assert.equal(f.el('editor').hidden,false);
    release();await flush();assert.equal(f.el('editor').hidden,true);assert.equal(f.requests.at(-1).action,'close');assert.equal(latest(f,'scene').scene.speed,1.75);
  }finally{f.close();}
});


test('immediate keyframe edits keep the newest director while earlier echoes arrive',async()=>{
  const f=fixture(true);let release;
  try{
    await flush();f.onRequest(data=>data.action==='director'?new Promise(resolve=>{release=()=>resolve({ok:true,json:async()=>({ok:true,revision:2,stateSequence:2})});}):undefined);
    change(f,'look-filter','cinematic');await flush();assert.ok(release);
    // A second edit is created before the first native callback returns.
    f.el('loop').click();f.message({type:'scene',revision:2,scene:{...f.scene,director:latest(f,'director').director}});await flush();assert.equal(latest(f,'scene'),undefined);
    release();await flush();const queued=latest(f,'scene').scene;assert.equal(queued.director.look.filter,'cinematic');assert.equal(queued.loop,true);
    // Undo returns the loop and then the look in the same authored order.
    f.onRequest(null);f.el('undo').click();await flush();assert.equal(latest(f,'scene').scene.loop,false);assert.equal(latest(f,'scene').scene.director.look.filter,'cinematic');
    f.el('undo').click();await flush();assert.equal(latest(f,'scene').scene.director?.look.filter||'none','none');assert.equal(f.el('look-filter').value,'none');
  }finally{f.close();}
});

test('reopening renders the restored camera and workspace; corruption recovery is explicit',async()=>{
  const f=fixture(true);
  try{
    await flush();f.message({type:'close'});
    const director={look:{filter:'dusk',strength:.7},framing:{ratio:'2.39',opacity:1},motion:{type:'sway',amplitude:.1,frequency:.2,roll:.3}};
    const camera={...f.scene.frames[0],pos:{x:351,y:-201,z:87},fov:32.5};
    f.message({type:'open',scene:{...f.scene,director},camera,workspace:{cameras:[{id:'camera_1',name:'Restored angle',frame:camera,director}],presets:[],status:'saved'}});
    assert.equal(f.el('cam-x').textContent,'351.0');assert.equal(f.el('fov-value').value,'32.5');assert.equal(f.el('look-filter').value,'dusk');assert.equal(f.el('camera-bank').options[0].textContent,'Restored angle');assert.equal(f.el('letterbox').dataset.ratio,'2.39');
    f.message({type:'workspace',status:'disabled',error:'Unreadable saved data'});assert.equal(f.el('workspace-recover').hidden,false);
    f.el('workspace-recover').click();await flush();assert.equal(latest(f,'workspaceReset'),undefined);assert.match(f.el('modal-body').textContent,/Discard the unreadable autosaved workspace/);
    [...f.el('modal-body').querySelectorAll('button')].find(b=>b.textContent==='Reset Workspace').click();await flush();assert.ok(latest(f,'workspaceReset'));
  }finally{f.close();}
});


test('empty Lua array encodings clear the last camera and custom preset',async()=>{
  const f=fixture(true);
  try{
    await flush();const entries={type:'workspace',cameras:[{id:'c1',name:'Last camera',frame:f.scene.frames[0]}],presets:[{id:'p1',name:'Last preset'}],status:'saved'};
    for(const empty of [{},[]]){
      f.message(entries);change(f,'preset-select','p1');assert.equal(f.el('custom-preset-actions').hidden,false);
      f.message({type:'workspace',cameras:empty,presets:empty,status:'saved'});
      assert.equal(f.el('camera-bank').options.length,0);assert.equal(f.el('camera-recall').disabled,true);assert.equal(f.el('custom-preset-actions').hidden,true);assert.equal([...f.el('preset-select').options].some(option=>option.value==='p1'),false);
    }
  }finally{f.close();}
});

function key(f,code,target=f.el('viewport'),extra={}){const event=new f.w.KeyboardEvent('keydown',{code,key:code,bubbles:true,cancelable:true,...extra});target.dispatchEvent(event);return event;}

test('beginner tabs use keyboard navigation and reveal point tools only when selected',async()=>{
  const f=fixture(true);try{
    await flush();assert.equal(f.el('view-camera').hidden,false);assert.equal(f.el('view-advanced').hidden,true);assert.equal(f.el('selected-point').hidden,true);
    f.el('tab-camera').focus();key(f,'ArrowRight',f.el('tab-camera'));
    assert.equal(f.el('view-camera').hidden,true);assert.equal(f.el('view-look').hidden,false);assert.equal(f.el('tab-look').getAttribute('aria-selected'),'true');assert.equal(f.w.document.activeElement,f.el('tab-look'));
    key(f,'End',f.el('tab-look'));assert.equal(f.el('view-advanced').hidden,false);assert.equal(f.el('selected-point').hidden,true);
    assert.equal(key(f,'Tab',f.el('tab-advanced')).defaultPrevented,false,'Tab must keep normal keyboard focus navigation');
    f.el('track').querySelector('button').click();assert.equal(f.el('selected-point').hidden,false);assert.equal(f.el('duration').disabled,false);assert.equal(f.el('view-advanced').hidden,false);
    f.el('deselect-frame').click();assert.equal(f.el('selected-point').hidden,true);assert.equal(f.el('view-camera').hidden,false);
    assert.equal(f.el('capture').textContent.includes('Add Point'),true);assert.equal(f.el('play-label').textContent,'Play Route');
    f.el('save-scene').click();assert.equal(f.el('modal-title').textContent,'Save Scene');
    const ids=[...f.w.document.querySelectorAll('[id]')].map(element=>element.id);assert.equal(new Set(ids).size,ids.length,'No duplicate control IDs');
  }finally{f.close();}
});

test('stabilization levels restore, echo from Lua and reject unknown values',async()=>{
  const f=fixture(true);try{
    await flush();assert.equal(f.el('flight-stabilization').value,'off');
    f.message({type:'state',stateSequence:3,settings:{stabilization:'strong'}});assert.equal(f.el('flight-stabilization').value,'strong');assert.equal(f.el('stabilization-status').textContent,'Strong');
    change(f,'flight-stabilization','medium');await flush();assert.equal(latest(f,'settings').stabilization,'medium');
    f.message({type:'state',stateSequence:4,settings:{stabilization:'invented'}});assert.equal(f.el('flight-stabilization').value,'medium');
    const count=f.requests.filter(request=>request.action==='settings').length;change(f,'flight-stabilization','invalid');await flush();assert.equal(f.requests.filter(request=>request.action==='settings').length,count);assert.equal(f.el('flight-stabilization').value,'medium');
    f.message({type:'close'});f.message({type:'open',scene:f.scene,camera:f.scene.frames[0],settings:{stabilization:'light'}});assert.equal(f.el('flight-stabilization').value,'light');
  }finally{f.close();}
});

test('J R and F1 shortcuts avoid typing, modifiers, repeats and dialogs',async()=>{
  const f=fixture(false);try{
    await flush();key(f,'KeyJ');await flush();assert.ok(latest(f,'cycleStabilization'));
    key(f,'KeyR');await flush();assert.equal(latest(f,'record').enabled,true);
    f.message({type:'state',stateSequence:7,recording:true});key(f,'KeyR');await flush();assert.equal(latest(f,'record').enabled,false);
    const count=f.requests.length;for(const code of ['KeyJ','KeyR','F1']){key(f,code,f.el('fov-value'));key(f,code,f.el('viewport'),{repeat:true});key(f,code,f.el('viewport'),{altKey:true});key(f,code,f.el('viewport'),{ctrlKey:true});key(f,code,f.el('viewport'),{shiftKey:true});}await flush();assert.equal(f.requests.length,count);assert.equal(f.el('modal').open,false);
    key(f,'F1');await flush();assert.equal(f.el('modal-title').textContent,'Camera Guide');assert.match(f.el('modal-body').textContent,/not video/);assert.match(f.el('modal-body').textContent,/Ctrl or Alt/);
    const afterHelp=f.requests.length;key(f,'KeyR');key(f,'KeyJ');await flush();assert.equal(f.requests.length,afterHelp);f.el('modal-close').click();assert.equal(f.el('modal').open,false);
    f.el('clean-button').click();f.message({type:'help'});assert.equal(f.el('editor').classList.contains('clean'),false);assert.equal(f.el('modal').open,true);
  }finally{f.close();}
});

test('help is available on hover and keyboard focus, flight legend is contextual',async()=>{
  const f=fixture(true);try{
    await flush();f.el('capture').focus();assert.equal(f.el('control-tooltip').hidden,false);assert.match(f.el('control-tooltip').textContent,/keyframe/);assert.match(f.el('capture').getAttribute('aria-describedby'),/control-tooltip/);
    f.el('help-button').focus();assert.equal(f.el('capture').hasAttribute('aria-describedby'),false);
    f.el('record').dispatchEvent(new f.w.Event('pointerover',{bubbles:true}));assert.equal(f.el('control-tooltip').hidden,false);assert.match(f.el('control-tooltip').textContent,/not a video/);
    f.el('flight-button').click();await flush();f.pending.shift()();await flush();assert.equal(f.el('control-tooltip').hidden,true);assert.equal(f.el('flight-guide').hidden,false);assert.match(f.el('flight-guide').textContent,/Down/);assert.match(f.el('flight-guide').textContent,/Slower/);
    f.message({type:'state',stateSequence:8,flight:false});assert.equal(f.el('flight-guide').hidden,true);
  }finally{f.close();}
});

test('saved cameras add shots and drag onto the route before an existing clip',async()=>{
  const f=fixture(true);try{
    await flush();f.message({type:'workspace',cameras:[{id:'cam1',name:'Station roof',frame:f.scene.frames[0]},{id:'cam2',name:'River',frame:f.scene.frames[1]}]});
    f.el('camera-add').click();await flush();assert.deepEqual(latest(f,'cameraAdd'),{action:'cameraAdd',id:'cam1',duration:3});
    const card=f.el('camera-cards').children[1];card.click();assert.equal(f.el('camera-bank').value,'cam2');assert.equal(f.el('view-saved').hidden,false);assert.equal(card.getAttribute('aria-pressed'),'true');
    const transfer={setData(){},effectAllowed:'',dropEffect:''};const drag=new f.w.Event('dragstart',{bubbles:true});Object.defineProperty(drag,'dataTransfer',{value:transfer});card.dispatchEvent(drag);
    const drop=new f.w.Event('drop',{bubbles:true,cancelable:true});Object.defineProperty(drop,'dataTransfer',{value:transfer});f.el('track').querySelector('button').dispatchEvent(drop);await flush();assert.deepEqual(latest(f,'cameraAdd'),{action:'cameraAdd',id:'cam2',beforeId:'first',duration:3});
    const dragAgain=new f.w.Event('dragstart',{bubbles:true});Object.defineProperty(dragAgain,'dataTransfer',{value:transfer});card.dispatchEvent(dragAgain);f.el('track').dispatchEvent(new f.w.Event('drop',{bubbles:true,cancelable:true}));await flush();assert.deepEqual(latest(f,'cameraAdd'),{action:'cameraAdd',id:'cam2',duration:3});
  }finally{f.close();}
});

test('world camera markers stay separate from path guides and safely select saved angles',async()=>{
  const f=fixture(true);try{
    await flush();f.message({type:'workspace',cameras:[{id:'cam1',name:'Roof <safe>',frame:f.scene.frames[0]}]});
    f.el('show-path').checked=false;
    f.message({type:'gizmos',cameras:[{id:'cam1',x:.4,y:.3,lines:[{x1:.3,y1:.3,x2:.4,y2:.4}]},{id:'unknown',x:.1,y:.1}],points:[],lines:[]});
    assert.equal(f.el('camera-layer').children.length,1);assert.equal(f.el('camera-frustums').children.length,1);const marker=f.el('camera-layer').firstElementChild;assert.equal(marker.style.left,'40%');assert.match(marker.textContent,/<safe>/);assert.equal(marker.querySelector('safe'),null);
    marker.click();assert.equal(f.el('view-saved').hidden,false);assert.equal(f.el('camera-bank').value,'cam1');
    f.el('show-cameras').checked=false;f.el('show-cameras').dispatchEvent(new f.w.Event('change'));await flush();assert.equal(latest(f,'settings').showCameras,false);assert.equal(f.el('camera-layer').children.length,0);
  }finally{f.close();}
});

test('dense recordings render as one retimeable clip without exposing destructive pose edits',async()=>{
  const f=fixture(true);try{
    await flush();const samples=Array.from({length:9001},(_,i)=>[i/30,i/300,0,2,0,0,i/300,50,10,12,0,'SUNNY']);
    const take={...f.scene.frames[0],id:'recorded',label:'Recorded Take',duration:300,take:{duration:300,samples}};
    f.message({type:'scene',revision:2,scene:{name:'Full recording',frames:[take,f.scene.frames[1]]}});
    const clips=f.el('track').querySelectorAll('.keyframe');assert.equal(clips.length,2);assert.equal(f.el('track').querySelectorAll('.recorded-take').length,1);assert.match(clips[0].dataset.help,/9001 samples/);
    clips[0].dispatchEvent(new f.w.MouseEvent('dblclick',{bubbles:true}));await flush();assert.equal(latest(f,'seek').time,0);assert.equal(latest(f,'setCamera'),undefined);
    clips[0].click();assert.equal(f.el('duration').disabled,false);assert.equal(f.el('frame-label').disabled,false);assert.equal(f.el('replace-frame').disabled,true);
    for(const id of ['fov','fov-value','roll','roll-value','focus','weather','time-of-day','easing','transition','pos-x','in-x','out-x'])assert.equal(f.el(id).disabled,true,id+' must not edit a recorded sample silently');
    assert.match(f.el('take-timing').textContent,/9001 captured samples/);change(f,'duration',150);await flush();const edited=latest(f,'scene').scene.frames[0];assert.equal(edited.duration,150);assert.equal(edited.take.duration,300);assert.equal(edited.take.samples.length,9001);assert.deepEqual(edited.take.samples.at(-1),samples.at(-1));
    f.el('deselect-frame').click();assert.equal(f.el('fov-value').disabled,false);assert.equal(f.el('weather').disabled,false);
  }finally{f.close();}
});

test('recording JSON above the old 256 KB limit imports and the 4 MB ceiling remains enforced',async()=>{
  const f=fixture(true);try{
    await flush();const samples=Array.from({length:9001},(_,i)=>[i/30,i/300,0,2,0,0,i/300,50,10,12,0,'SUNNY']);
    const raw=JSON.stringify({name:'Imported recording',frames:[{...f.scene.frames[0],id:'take',duration:300,take:{duration:300,samples}}]});assert.ok(Buffer.byteLength(raw)>262144);
    f.w.document.querySelector('[data-action=import]').click();f.el('modal-body').querySelector('textarea').value=raw;[...f.el('modal-body').querySelectorAll('button')].find(button=>button.textContent==='Import').click();await flush();assert.equal(latest(f,'scene').scene.frames[0].take.samples.length,9001);assert.equal(f.el('modal').open,false);
    const count=f.requests.filter(request=>request.action==='scene').length;f.w.document.querySelector('[data-action=import]').click();f.el('modal-body').querySelector('textarea').value=' '.repeat(4*1024*1024)+'{}';[...f.el('modal-body').querySelectorAll('button')].find(button=>button.textContent==='Import').click();await flush();assert.equal(f.requests.filter(request=>request.action==='scene').length,count);assert.match(f.el('toasts').textContent,/File exceeds 4 MB/);
  }finally{f.close();}
});

const closeNumber=(actual,expected,label)=>assert.ok(Math.abs(actual-expected)<.001,`${label}: ${actual} != ${expected}`);
function percentAttribute(element,attribute){
  const value=element.getAttribute(attribute);assert.match(value??'',/^-?\d+(?:\.\d+)?%$/,attribute+' must stay in local percentage coordinates');return parseFloat(value);
}
function guideShapes(svg){
  // A contrast underlay may repeat each stroke; inspect distinct geometry.
  const shapes=new Map();for(const element of svg.querySelectorAll('line,rect')){const attributes=element.tagName==='line'?['x1','y1','x2','y2']:['x','y','width','height'];const signature=element.tagName+attributes.map(name=>name+':'+element.getAttribute(name)).join('|');shapes.set(signature,element);}return [...shapes.values()];
}

test('composition controls restore six distinct SVG guides in the Camera tab',async()=>{
  const f=fixture(true);try{
    await flush();assert.equal(f.el('show-grid').closest('[role=tabpanel]').id,'view-camera');
    assert.equal(f.el('grid').hidden,true);assert.equal(f.el('grid-type').value,'thirds');assert.equal(f.el('grid-opacity-value').value,'60');
    f.message({type:'close'});f.message({type:'open',scene:f.scene,camera:f.scene.frames[0],stateSequence:2,settings:{grid:true,gridType:'golden',gridOpacity:.35}});
    assert.equal(f.el('grid').hidden,false);assert.equal(f.el('show-grid').checked,true);assert.equal(f.el('grid-type').value,'golden');assert.equal(f.el('grid-opacity-value').value,'35');closeNumber(parseFloat(f.el('grid').style.opacity),.35,'restored guide opacity');
    const kinds={thirds:4,golden:4,diagonals:2,quarters:6,center:2,safe:2};let sequence=3;
    for(const [kind,count] of Object.entries(kinds)){
      f.message({type:'state',stateSequence:sequence++,settings:{grid:true,gridType:kind,gridOpacity:.6}});
      assert.equal(f.el('grid-type').value,kind);
      const svg=f.el('grid').querySelector('svg');assert.ok(svg,kind+' has SVG geometry');
      const shapes=guideShapes(svg);assert.equal(shapes.length,count,kind+' guide count');
      if(kind==='safe'){
        assert.equal(svg.querySelectorAll('line').length,0);
        const insets=shapes.map(rect=>{const x=percentAttribute(rect,'x'),y=percentAttribute(rect,'y');closeNumber(x,y,'safe symmetric inset');closeNumber(percentAttribute(rect,'width'),100-2*x,'safe width');closeNumber(percentAttribute(rect,'height'),100-2*y,'safe height');return x;}).sort((a,b)=>a-b);
        assert.deepEqual(insets,[5,10]);
      }else{
        assert.equal(svg.querySelectorAll('rect').length,0);
        const points=shapes.map(line=>Object.fromEntries(['x1','y1','x2','y2'].map(name=>[name,percentAttribute(line,name)])));
        if(kind==='diagonals'){
          for(const p of points){assert.equal(Math.abs(p.x2-p.x1),100);assert.equal(Math.abs(p.y2-p.y1),100);}
          assert.equal(new Set(points.map(p=>Math.sign((p.x2-p.x1)*(p.y2-p.y1)))).size,2,'both crossing diagonals are present');
        }else{
          const expected=kind==='thirds'?[100/3,200/3]:kind==='golden'?[38.196601125,61.803398875]:kind==='quarters'?[25,50,75]:[50];
          const vertical=points.filter(p=>p.x1===p.x2),horizontal=points.filter(p=>p.y1===p.y2);
          assert.equal(vertical.length,expected.length);assert.equal(horizontal.length,expected.length);
          vertical.sort((a,b)=>a.x1-b.x1);horizontal.sort((a,b)=>a.y1-b.y1);
          expected.forEach((coordinate,index)=>{closeNumber(vertical[index].x1,coordinate,kind+' vertical');closeNumber(horizontal[index].y1,coordinate,kind+' horizontal');assert.equal(Math.abs(vertical[index].y2-vertical[index].y1),100);assert.equal(Math.abs(horizontal[index].x2-horizontal[index].x1),100);});
        }
      }
    }
  }finally{f.close();}
});

test('composition changes commit once, selecting a guide enables it, invalid opacity never writes',async()=>{
  const f=fixture(true);try{
    await flush();change(f,'grid-type','quarters');await flush();assert.equal(latest(f,'settings').gridType,'quarters');assert.equal(latest(f,'settings').grid,true);
    assert.equal(f.el('grid').hidden,false);assert.equal(f.el('show-grid').checked,true);
    const count=f.requests.filter(request=>request.action==='settings').length,slider=f.el('grid-opacity');
    for(const value of [20,40,65,80]){slider.value=String(value);slider.dispatchEvent(new f.w.Event('input',{bubbles:true}));}
    await flush();assert.equal(f.requests.filter(request=>request.action==='settings').length,count,'drag previews do not flood Lua');assert.equal(f.el('grid-opacity-value').value,'80');closeNumber(parseFloat(f.el('grid').style.opacity),.8,'drag updates actual overlay opacity');
    slider.dispatchEvent(new f.w.Event('change',{bubbles:true}));await flush();assert.equal(f.requests.filter(request=>request.action==='settings').length,count+1);assert.equal(latest(f,'settings').gridOpacity,.8);
    assert.match(f.el('grid-opacity-output').textContent,/80/);
    for(const invalid of ['',9,101]){change(f,'grid-opacity-value',invalid);await flush();assert.equal(f.requests.filter(request=>request.action==='settings').length,count+1);assert.equal(f.el('grid-opacity-value').getAttribute('aria-invalid'),'true');}
    change(f,'grid-opacity-value',45);await flush();assert.equal(latest(f,'settings').gridOpacity,.45);assert.equal(f.el('grid-opacity-value').hasAttribute('aria-invalid'),false);
    f.el('show-grid').checked=false;f.el('show-grid').dispatchEvent(new f.w.Event('change',{bubbles:true}));await flush();assert.equal(latest(f,'settings').grid,false);assert.equal(f.el('grid').hidden,true);
  }finally{f.close();}
});

test('composition pending edits survive old state and rejected edits restore acknowledged values',async()=>{
  const f=fixture(true);let release;
  try{
    await flush();f.message({type:'state',stateSequence:3,settings:{grid:false,gridType:'thirds',gridOpacity:.6}});
    f.onRequest(data=>data.action==='settings'?new Promise(resolve=>{release=result=>resolve({ok:true,json:async()=>result});}):undefined);
    change(f,'grid-type','golden');await flush();assert.ok(release);
    f.message({type:'state',stateSequence:4,settings:{grid:false,gridType:'thirds',gridOpacity:.6}});
    assert.equal(f.el('grid-type').value,'golden');assert.equal(f.el('show-grid').checked,true);assert.equal(f.el('grid').hidden,false);
    release({ok:true,revision:1,stateSequence:5});await flush();f.message({type:'state',stateSequence:4,settings:{grid:false,gridType:'thirds',gridOpacity:.6}});assert.equal(f.el('grid-type').value,'golden');
    f.message({type:'state',stateSequence:6,settings:{grid:true,gridType:'golden',gridOpacity:.6}});
    release=null;change(f,'grid-opacity-value',85);await flush();assert.ok(release);
    f.message({type:'state',stateSequence:7,settings:{grid:true,gridType:'golden',gridOpacity:.6}});assert.equal(f.el('grid-opacity-value').value,'85');
    release({ok:false,error:'Settings rejected',revision:1,stateSequence:8});await flush();assert.equal(f.el('grid-opacity-value').value,'60');closeNumber(parseFloat(f.el('grid').style.opacity),.6,'rejected overlay opacity rolls back');assert.equal(f.el('grid-type').value,'golden');assert.equal(f.el('show-grid').checked,true);
  }finally{f.close();}
});

test('G waits for Lua and respects fields, repeats, dialogs, modifiers and native flight ownership',async()=>{
  const f=fixture(true);try{
    await flush();key(f,'KeyG');await flush();assert.equal(f.requests.filter(request=>request.action==='toggleGrid').length,1);assert.equal(f.el('grid').hidden,true,'G must wait for authoritative Lua state');
    f.message({type:'state',stateSequence:3,settings:{grid:true,gridType:'thirds',gridOpacity:.6}});assert.equal(f.el('grid').hidden,false);
    const count=f.requests.length;
    key(f,'KeyG',f.el('grid-opacity-value'));key(f,'KeyG',f.el('grid-type'));
    for(const extra of [{repeat:true},{ctrlKey:true},{altKey:true},{shiftKey:true},{metaKey:true}])key(f,'KeyG',f.el('viewport'),extra);
    await flush();assert.equal(f.requests.length,count);
    f.el('help-button').click();await flush();const dialogCount=f.requests.length;key(f,'KeyG');await flush();assert.equal(f.requests.length,dialogCount);f.el('modal-close').click();
    f.el('flight-button').click();await flush();f.pending.shift()();await flush();const flyingCount=f.requests.length;key(f,'KeyG');await flush();assert.equal(f.requests.length,flyingCount,'native flight reads G in Lua only');
  }finally{f.close();}
  const fallback=fixture(false);try{
    await flush();fallback.el('flight-button').click();await flush();fallback.pending.shift()();await flush();key(fallback,'KeyG');await flush();assert.equal(fallback.requests.filter(request=>request.action==='toggleGrid').length,1,'browser fallback still forwards G');
  }finally{fallback.close();}
});

test('composition guides follow framed image insets at landscape, portrait and 4K sizes',async()=>{
  const f=fixture(true);try{
    await flush();f.message({type:'state',stateSequence:3,settings:{grid:true,gridType:'thirds',gridOpacity:.6}});
    for(const [width,height] of [[1920,1080],[1080,1920],[3840,2160]]){
      Object.defineProperty(f.w,'innerWidth',{value:width,configurable:true});Object.defineProperty(f.w,'innerHeight',{value:height,configurable:true});f.w.dispatchEvent(new f.w.Event('resize'));
      for(const [ratio,target] of [['native',null],['2.39',2.39],['4:3',4/3],['1:1',1]]){
        change(f,'frame-ratio',ratio);await flush();const aspect=width/height;
        const x=target&&aspect>target?(1-target/aspect)*50:0,y=target&&aspect<target?(1-aspect/target)*50:0;
        for(const [axis,expected] of [['x',x],['y',y]]){
          const grid=f.el('grid').style.getPropertyValue('--frame-'+axis),mask=f.el('letterbox').style.getPropertyValue('--frame-'+axis);
          closeNumber(parseFloat(grid),expected,`${width}x${height} ${ratio} grid ${axis}`);assert.equal(grid,mask,'guide and framing mask share the same inset');
        }
        assert.equal(f.el('grid').hidden,false);assert.equal(guideShapes(f.el('grid').querySelector('svg')).length,4);
      }
    }
    f.el('clean-button').click();assert.equal(f.el('editor').classList.contains('clean'),true);assert.equal(f.el('grid').hidden,false,'Clean View hides overlays through CSS without losing the enabled setting');
    f.el('clean-button').click();assert.equal(f.el('editor').classList.contains('clean'),false);assert.equal(f.el('show-grid').checked,true);
  }finally{f.close();}
});

test('click explanations expose accessible text, toggle, restore focus and consume camera shortcuts',async()=>{
  const f=fixture(true);try{
    await flush();const buttons=[...f.w.document.querySelectorAll('.info-button')];assert.ok(buttons.length>=4,'settings have contextual explanation buttons');
    for(const button of buttons){assert.equal(button.type,'button');assert.equal(button.getAttribute('aria-controls'),'info-popover');assert.ok(button.getAttribute('aria-label'));assert.ok(button.dataset.info.trim());assert.equal(button.getAttribute('aria-expanded'),'false');}
    const first=buttons[0],second=buttons[1],popup=f.el('info-popover');
    assert.equal(popup.getAttribute('role'),'dialog');assert.equal(popup.getAttribute('aria-modal'),'false');assert.equal(popup.getAttribute('aria-labelledby'),'info-title');assert.equal(popup.hidden,true);
    f.el('capture').focus();assert.equal(f.el('control-tooltip').hidden,false);
    first.click();assert.equal(popup.hidden,false);assert.equal(first.getAttribute('aria-expanded'),'true');assert.equal(f.el('info-title').textContent,first.dataset.infoTitle);assert.equal(f.el('info-body').textContent,first.dataset.info);assert.equal(f.w.document.activeElement,f.el('info-close'));assert.equal(f.el('control-tooltip').hidden,true);
    const requests=f.requests.length;for(const code of ['KeyG','KeyR','KeyJ','KeyF','KeyH','Space','Delete'])key(f,code,f.el('info-close'));await flush();assert.equal(f.requests.length,requests,'explanation focus cannot trigger camera or recording commands');
    key(f,'Escape',f.el('info-close'));await flush();assert.equal(popup.hidden,true);assert.equal(first.getAttribute('aria-expanded'),'false');assert.equal(f.w.document.activeElement,first);assert.equal(f.el('editor').hidden,false);assert.equal(latest(f,'close'),undefined,'Escape closes the explanation without closing the camera');
    first.click();first.click();assert.equal(popup.hidden,true);assert.equal(f.w.document.activeElement,first,'clicking the same info icon closes and restores its focus');
    first.click();second.click();assert.equal(first.getAttribute('aria-expanded'),'false');assert.equal(second.getAttribute('aria-expanded'),'true');assert.equal(f.el('info-title').textContent,second.dataset.infoTitle);
    f.el('info-close').click();assert.equal(popup.hidden,true);assert.equal(f.w.document.activeElement,second);
  }finally{f.close();}
});

test('explanations close when their context moves, disappears or becomes a flight view',async()=>{
  const f=fixture(true);try{
    await flush();const info=f.w.document.querySelector('#view-camera .info-button'),popup=f.el('info-popover');
    const open=()=>{info.click();assert.equal(popup.hidden,false);};
    const closed=reason=>{assert.equal(popup.hidden,true,reason);assert.equal(info.getAttribute('aria-expanded'),'false',reason+' resets trigger state');};
    open();f.el('viewport').dispatchEvent(new f.w.MouseEvent('click',{bubbles:true}));closed('outside click');
    open();f.el('fov-value').focus();closed('focus moved outside');assert.equal(f.w.document.activeElement,f.el('fov-value'));
    open();f.w.document.querySelector('.inspector-content').dispatchEvent(new f.w.Event('scroll'));closed('inspector scroll');
    open();f.w.dispatchEvent(new f.w.Event('resize'));closed('viewport resize');
    open();f.el('tab-look').click();closed('inspector tab changed');f.el('tab-camera').click();
    open();f.el('clean-button').click();closed('clean view');f.el('clean-button').click();
    open();f.el('help-button').click();closed('modal opened');assert.equal(f.el('modal').open,true);f.el('modal-close').click();await flush();
    open();f.el('flight-button').click();closed('flight started');await flush();f.pending.shift()();await flush();f.message({type:'state',stateSequence:8,flight:false});
    open();f.message({type:'close'});closed('camera closed');assert.equal(f.el('editor').hidden,true);
    f.message({type:'open',scene:f.scene,camera:f.scene.frames[0],stateSequence:10,capabilities:{nativeFlightInput:true}});assert.equal(popup.hidden,true,'reopening does not resurrect an old explanation');assert.equal(info.getAttribute('aria-expanded'),'false');
  }finally{f.close();}
});


test('Black & White starts at full strength and keeps manual intensity control',async()=>{
  const f=fixture(true);
  try{
    await flush();
    const option=[...f.el('look-filter').options].find(option=>option.value==='monochrome');
    assert.equal(option.textContent,'Black & White');
    change(f,'look-filter','monochrome');await flush();
    assert.equal(latest(f,'director').director.look.filter,'monochrome');
    assert.equal(latest(f,'director').director.look.strength,1);
    assert.equal(Number(f.el('look-strength-value').value),1);
    change(f,'look-strength-value',.35);await flush();
    assert.equal(latest(f,'director').director.look.strength,.35);
    change(f,'look-filter','none');await flush();
    assert.equal(latest(f,'director').director.look.filter,'none');
    assert.equal(f.el('look-strength').disabled,true);
  }finally{f.close();}
});
