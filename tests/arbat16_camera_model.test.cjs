'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const M = require('../resource/arbat16_camera/web/model.js');
const D = require('../resource/arbat16_camera/web/director.js');

const frame = (id = 'frame_1') => ({id, label: 'Кадр', pos: {x: 1, y: 2, z: 3}, rot: {x: 0, y: 0, z: 350},
  fov: 50, duration: 3, easing: 'smooth', transition: 'smooth', weather: 'SUNNY', hour: 12, minute: 0,
  dof: {enabled: false, focus: 10, near: 1, far: 100, strength: .5}});
const scene = (count = 2) => ({version: 1, name: 'Test', frames: Array.from({length: count}, (_, i) => frame('frame_' + (i + 1))), loop: false, speed: 1});

test('default scene and frames normalize to the Lua schema without retaining input aliases', () => {
  assert.deepEqual(new M.Editor().scene, M.empty());
  const raw = {frames: [{pos: {x: 0, y: 0, z: 0}, rot: {x: 0, y: 0, z: 0}}]};
  const normalized = M.validate(raw);
  assert.equal(normalized.name, 'Untitled');
  assert.equal(normalized.frames[0].id, 'frame_1');
  assert.equal(normalized.frames[0].label, 'Camera 1');
  assert.equal(normalized.frames[0].fov, 50);
  assert.equal(normalized.frames[0].duration, 3);
  assert.deepEqual(normalized.frames[0].dof, {enabled: false, focus: 10, near: 1, far: 100, strength: .5});
  normalized.frames[0].pos.x = 99;
  assert.equal(raw.frames[0].pos.x, 0);
});

test('JSON imports reject malformed scene structure and values', () => {
  const mutations = [
    s => { s.version = 2; }, s => { s.frames = {}; }, s => { s.frames = new Array(2); },
    s => { s.frames[0] = null; }, s => { s.frames.other = frame(); },
    s => { s.frames[0].pos = {}; }, s => { s.frames[0].pos.x = '10'; },
    s => { s.frames[0].pos.x = Infinity; }, s => { s.frames[0].pos.x = NaN; },
    s => { s.frames[0].pos.x = 100001; }, s => { s.frames[0].rot.z = 360001; },
    s => { s.frames[0].id = s.frames[1].id; }, s => { s.frames[0].id = '<script>'; },
    s => { s.frames[0].id = 'x'.repeat(65); }, s => { s.frames[0].label = 'x'.repeat(161); },
    s => { s.frames[0].duration = -1; }, s => { s.frames[0].duration = 601; },
    s => { s.frames[0].fov = 0; }, s => { s.frames[0].fov = 131; },
    s => { s.frames[0].easing = {}; }, s => { s.frames[0].transition = 'unknown'; },
    s => { s.frames[0].weather = 'SUNNY;'; }, s => { s.frames[0].weather = ''; },
    s => { s.frames[0].hour = 24; }, s => { s.frames[0].minute = 1.5; },
    s => { s.frames[0].dof = false; }, s => { s.frames[0].dof.enabled = 'true'; },
    s => { s.frames[0].dof.near = 101; }, s => { s.frames[0].dof.far = 0; },
    s => { s.frames[0].dof.strength = 1.1; }, s => { s.frames[0].dof.focus = .001; },
    s => { s.frames[0].handleIn = {x: 0, y: 0}; }, s => { s.frames[0].handleOut = false; },
    s => { s.loop = 1; }, s => { s.speed = 0; }, s => { s.speed = 8.01; },
    s => { s.name = ' '; }, s => { s.name = 'x\0y'; }, s => { s.name = 'я'.repeat(33); },
    s => { s.name = '..'; }, s => { s.name = 'a/b'; }, s => { s.name = 'a\\b'; }, s => { s.name = 'a\x85b'; },
    s => { s.extra = {}; }, s => { s.frames[0].timeHours = 12; }, s => { s.frames[0].dof.extra = 1; }
  ];
  for (const mutate of mutations) { const input = scene(); mutate(input); assert.throws(() => M.validate(input), mutate.toString()); }
  assert.throws(() => M.validate(JSON.parse('{"version":1,"name":"test","frames":[],"__proto__":{"polluted":true}}')));
  assert.throws(() => M.validate(Object.assign(Object.create({bad: true}), scene())));
  assert.throws(() => M.validate(null));
  assert.throws(() => M.validate(scene(201)));
  assert.equal({}.polluted, undefined);
});

test('Lua boundary ranges and zero-duration cut/final hold are accepted', () => {
  const s = scene();
  Object.assign(s.frames[0], {duration: 0, transition: 'cut', fov: 1, weather: 'sunny'});
  s.frames[0].rot.z = 360000;
  s.frames[0].handleOut = {x: 100000, y: -100000, z: 0};
  s.frames[0].dof = {enabled: true, focus: .01, near: 0, far: 100000, strength: 1};
  s.frames[1].duration = 0;
  const validated = M.validate(s);
  assert.equal(validated.frames[0].weather, 'SUNNY');
  assert.equal(M.duration(validated), 0);
  for (const transition of ['linear', 'smooth', 'hold']) {
    s.frames[0].transition = transition;
    assert.throws(() => M.validate(s), 'zero nonfinal ' + transition);
  }
  const single = scene(1); single.frames[0].duration = 0;
  assert.equal(M.duration(M.validate(single)), 0);
});

test('duration includes final hold, starts align, 3600-second limit is exact', () => {
  const s = scene(); s.frames[0].duration = 2; s.frames[1].duration = 1;
  assert.equal(M.duration(s), 3);
  assert.deepEqual(M.starts(s), [0, 2]);
  const maximum = scene(6); maximum.frames.forEach(f => { f.duration = 600; });
  assert.equal(M.duration(M.validate(maximum)), 3600);
  maximum.frames.push(frame('extra'));
  assert.throws(() => M.validate(maximum));
  assert.equal(M.timecode(60), '01:00:00');
  assert.equal(M.timecode(1 / 30), '00:00:01');
});

test('history is bounded to 50 commits and a new branch clears redo', () => {
  const editor = new M.Editor();
  for (let i = 1; i <= 60; i++) editor.edit(s => { s.name = 'Revision ' + i; });
  assert.equal(editor.past.length, 50);
  for (let i = 0; i < 50; i++) assert.equal(editor.undo(), true);
  assert.equal(editor.scene.name, 'Revision 10');
  assert.equal(editor.undo(), false);
  for (let i = 0; i < 50; i++) assert.equal(editor.redo(), true);
  assert.equal(editor.scene.name, 'Revision 60');
  assert.equal(editor.redo(), false);
  assert.equal(editor.past.length, 50);
  editor.undo();
  editor.edit(s => { s.name = 'New branch'; });
  assert.equal(editor.future.length, 0);
  assert.equal(editor.redo(), false);
  const previousCount = editor.past.length;
  assert.equal(editor.apply(M.clone(editor.scene)), false);
  assert.equal(editor.past.length, previousCount);
});

test('streamed drag updates retain history and commit one undoable gesture', () => {
  const editor = new M.Editor(scene());
  editor.edit(s => { s.name = 'Before drag'; });
  editor.edit(s => { s.name = 'Discarded branch'; });
  editor.undo();
  const historyDrag = M.clone(editor.scene);
  const previousPast = M.clone(editor.past);
  const previousFuture = M.clone(editor.future);
  for (let i = 1; i <= 8; i++) {
    const next = M.clone(editor.scene);
    next.frames[0].handleOut = {x: i, y: 0, z: 0};
    editor.apply(next, false);
  }
  assert.deepEqual(editor.past, previousPast);
  assert.deepEqual(editor.future, previousFuture);
  editor.past.push(historyDrag); if (editor.past.length > 50) editor.past.shift(); editor.future = [];
  assert.equal(editor.past.length, previousPast.length + 1);
  assert.equal(editor.scene.frames[0].handleOut.x, 8);
  assert.equal(editor.undo(), true);
  assert.deepEqual(editor.scene, historyDrag);
  assert.equal(editor.redo(), true);
  assert.equal(editor.scene.frames[0].handleOut.x, 8);
});

test('invalid edits do not mutate scene, history, or redo', () => {
  const editor = new M.Editor(scene());
  editor.edit(s => { s.name = 'Revision'; }); editor.undo();
  const before = M.clone(editor.scene);
  assert.throws(() => editor.edit(s => { s.frames[0].fov = -1; }));
  assert.deepEqual(editor.scene, before);
  assert.equal(editor.past.length, 0);
  assert.equal(editor.future.length, 1);
  assert.equal(editor.redo(), true);
});

test('reorder/remove preserve frame identity and support undo', () => {
  const editor = new M.Editor(scene(3));
  const ids = () => editor.scene.frames.map(f => f.id);
  editor.reorder('frame_3', 'frame_1');
  assert.deepEqual(ids(), ['frame_3', 'frame_1', 'frame_2']);
  editor.reorder('frame_3', null);
  assert.deepEqual(ids(), ['frame_1', 'frame_2', 'frame_3']);
  assert.equal(editor.reorder('missing', 'frame_1'), false);
  assert.equal(editor.reorder('frame_1', 'frame_1'), false);
  editor.remove(new Set(['frame_1', 'frame_3']));
  assert.deepEqual(ids(), ['frame_2']);
  editor.undo(); assert.deepEqual(ids(), ['frame_1', 'frame_2', 'frame_3']);
});

test('paste creates unique IDs even when clock/random repeat and retains independent values', () => {
  const editor = new M.Editor(scene());
  const copied = [M.clone(editor.scene.frames[0]), M.clone(editor.scene.frames[1])];
  const oldNow = Date.now; const oldRandom = Math.random;
  try {
    Date.now = () => 1; Math.random = () => 0;
    const first = editor.paste(copied, 'frame_1');
    const second = editor.paste(copied, 'frame_1');
    assert.equal(new Set([...first, ...second]).size, 4);
    assert.equal(new Set(editor.scene.frames.map(f => f.id)).size, 6);
    assert.deepEqual(editor.scene.frames.slice(1, 3).map(f => f.id), second);
    copied[0].pos.x = 999;
    assert.equal(editor.scene.frames.find(f => f.id === first[0]).pos.x, 1);
    editor.undo(); assert.equal(editor.scene.frames.length, 4);
    editor.undo(); assert.equal(editor.scene.frames.length, 2);
  } finally { Date.now = oldNow; Math.random = oldRandom; }
  assert.throws(() => editor.paste(null));
  assert.throws(() => editor.paste([null]));
  assert.equal(editor.scene.frames.length, 2);
});

test('director settings survive scene edits, export and history while old scenes remain unchanged', () => {
  assert.equal('director' in M.validate(scene()), false);
  const input = scene(); input.director = {look:{filter:'dusk'}};
  const editor = new M.Editor(input);
  assert.deepEqual(editor.scene.director, {...D.defaults(),look:{filter:'dusk',strength:.6}});
  editor.edit(s => { s.director.framing.ratio='2.39';s.director.motion.type='handheld'; });
  const exported = JSON.parse(JSON.stringify(editor.scene));
  assert.equal(M.validate(exported).director.motion.type,'handheld');
  editor.undo();assert.equal(editor.scene.director.framing.ratio,'native');
  editor.redo();assert.equal(editor.scene.director.framing.ratio,'2.39');
  assert.equal(input.director.framing,undefined);
});

test('director catalog presets and strict bounds agree with the persistence schema', () => {
  for (const preset of D.presets) assert.deepEqual(D.validate(preset.director),preset.director);
  for (const filter of D.filters) assert.equal(D.validate({look:{filter:filter.id}}).look.filter,filter.id);
  for (const ratio of D.ratios) assert.equal(D.validate({framing:{ratio}}).framing.ratio,ratio);
  for (const bad of [null,[],{extra:true},{look:false},{look:{filter:'bogus'}},{look:{strength:1.01}},
    {framing:{ratio:'cinema'}},{framing:{opacity:-.1}},{motion:{type:'random'}},{motion:{amplitude:2.01}},
    {motion:{frequency:Infinity}},{motion:{frequency:3.01}},{motion:{roll:5.01}},{motion:{roll:NaN}}]) {
    assert.throws(() => D.validate(bad));const input=scene();input.director=bad;assert.throws(() => M.validate(input));
  }
  assert.equal(D.validate({motion:{amplitude:2,frequency:3,roll:5}}).motion.roll,5);
  const first=D.defaults();first.look.filter='flat';assert.equal(D.defaults().look.filter,'none');
});

test('Black & White is available in both catalogs and survives scene history and export', () => {
  const fs=require('node:fs'),path=require('node:path');
  const lua=fs.readFileSync(path.join(__dirname,'../resource/arbat16_camera/shared/director.lua'),'utf8');
  const catalog=lua.slice(lua.indexOf('D.filters ='),lua.indexOf('D.ratios ='));
  const luaFilters=[...catalog.matchAll(/\{id='([^']+)', label='([^']+)'/g)].map(([,id,label])=>({id,label}));
  assert.deepEqual(D.filters,luaFilters,'Lua and NUI expose matching filter IDs and labels');
  assert.deepEqual(D.filters.find(f=>f.id==='monochrome'),{id:'monochrome',label:'Black & White'});
  const input=scene();input.director=D.defaults();const editor=new M.Editor(input);
  editor.edit(s=>{s.director.look={filter:'monochrome',strength:1};});
  const exported=M.validate(JSON.parse(JSON.stringify(editor.scene)));
  assert.deepEqual(exported.director.look,{filter:'monochrome',strength:1});
  editor.undo();assert.equal(editor.scene.director.look.filter,'none');editor.redo();
  assert.equal(editor.scene.director.look.filter,'monochrome');
  for(const strength of [0,.25,1])assert.equal(D.validate({look:{filter:'monochrome',strength}}).look.strength,strength);
  for(const strength of [-.01,1.01,NaN])assert.throws(()=>D.validate({look:{filter:'monochrome',strength}}));
});

const takeSample = (t,x=0) => [t,x,2,3,0,0,350,50,10,12,0,'SUNNY'];
const takeScene = () => {
  const s=scene(1);s.frames[0].transition=undefined;
  s.frames[0].take={duration:3,samples:[takeSample(0),takeSample(1),takeSample(2,10),takeSample(3,10)]};
  return s;
};
test('recorded clips preserve dense samples through export, duration edits, undo and clipboard', () => {
  const original=takeScene();const editor=new M.Editor(original);
  assert.equal(editor.scene.frames[0].transition,'hold');assert.equal(editor.scene.frames[0].pos.x,0);
  editor.edit(s=>{s.frames[0].duration=6;});
  assert.equal(editor.scene.frames[0].take.duration,3);assert.equal(M.duration(editor.scene),6);
  const exported=JSON.parse(JSON.stringify(editor.scene));assert.deepEqual(M.validate(exported),editor.scene);
  editor.undo();assert.equal(editor.scene.frames[0].duration,3);
  editor.redo();assert.equal(editor.scene.frames[0].duration,6);
  editor.paste([editor.scene.frames[0]],editor.scene.frames[0].id);
  assert.equal(editor.scene.frames.length,2);assert.notEqual(editor.scene.frames[0].id,editor.scene.frames[1].id);
  editor.scene.frames[1].take.samples[0][1]=99;
  assert.equal(editor.scene.frames[0].take.samples[0][1],0);assert.equal(original.frames[0].take.samples[0][1],0);
  assert.equal('take' in M.validate(scene(1)).frames[0],false);
});

test('recording schema rejects malformed timestamps, columns, bounds and oversized timelines', () => {
  const mutations=[f=>{f.take=false;},f=>{f.take.duration=0;},f=>{f.take.duration=301;},f=>{f.take.extra=1;},
    f=>{f.take.samples=[];},f=>{f.take.samples=[takeSample(0)];},f=>{delete f.take.samples[1];},
    f=>{f.take.samples[0].extra=1;},f=>{f.take.samples[0].push(1);},f=>{f.take.samples[0].pop();},
    f=>{f.take.samples[0][0]=.01;},f=>{f.take.samples[1][0]=0;},f=>{f.take.samples[1][0]=2.5;},
    f=>{f.take.samples[3][0]=2.9;},f=>{f.take.samples[1][0]=3;},f=>{f.take.samples[0][1]=100001;},
    f=>{f.take.samples[0][4]=360001;},f=>{f.take.samples[0][7]=0;},f=>{f.take.samples[0][8]=0;},
    f=>{f.take.samples[0][9]=24;},f=>{f.take.samples[0][10]=1.5;},f=>{f.take.samples[0][11]='RAIN;';},
    f=>{f.take.samples[0][2]=Infinity;},f=>{f.take.samples[0][3]=NaN;},f=>{f.duration=0;}];
  for(const mutate of mutations){const raw=takeScene();mutate(raw.frames[0]);assert.throws(()=>M.validate(raw),mutate.toString());}
  const bounded=takeScene();bounded.frames[0].take.samples.at(-1)[0]=3.00005;
  assert.equal(M.validate(bounded).frames[0].take.samples.at(-1)[0],3);
  const large=takeScene();large.frames[0].duration=300;
  large.frames[0].take={duration:300,samples:Array.from({length:9001},(_,i)=>takeSample(i/30,i%7))};
  assert.equal(M.validate(large).frames[0].take.samples.length,9001);
  large.frames.push({...M.clone(large.frames[0]),id:'second'});
  assert.equal(M.validate(large).frames.length,2);
  large.frames.push({...takeScene().frames[0],id:'third'});assert.throws(()=>M.validate(large));
  large.frames.length=1;large.frames[0].take.samples.push(takeSample(300.001));assert.throws(()=>M.validate(large));
});

test('dense recording undo and redo share a serialized byte budget without losing retained samples', () => {
  const large=takeScene();large.name='Dense recording';
  large.frames[0].duration=300;
  large.frames[0].take={duration:300,samples:Array.from({length:9001},(_,i)=>[
    i/30,Math.sin(i)*12345.67890123456,Math.cos(i)*23456.78901234567,123.4567890123456,
    12.34567890123456,23.45678901234567,34.56789012345678,45.67890123456789,56.7890123456789,12,30,'OVERCASTDARK'])};
  large.frames.push({...M.clone(large.frames[0]),id:'dense_2'});
  const editor=new M.Editor(large);
  const sceneBytes=Buffer.byteLength(JSON.stringify(editor.scene),'utf8');
  assert.ok(sceneBytes>2*1024*1024&&sceneBytes<4*1024*1024,'exercise a multi-megabyte valid scene');
  const samples=JSON.stringify(editor.scene.frames.map(f=>f.take.samples));
  const verifyBudget=()=>{
    const actual=[...editor.past,...editor.future].reduce((n,s)=>n+Buffer.byteLength(JSON.stringify(s),'utf8'),0);
    assert.equal(editor.historyBytes(),actual,'reported estimate equals serialized UTF-8 size');
    assert.ok(actual<=M.MAX_HISTORY_BYTES,'undo and redo combined stay under byte budget');
    assert.ok(editor.past.length+editor.future.length<=M.MAX_HISTORY_STATES);
  };
  for(let i=1;i<=12;i++){editor.edit(s=>{s.name='Dense edit '+i;});verifyBudget();}
  assert.ok(editor.past.length>=1&&editor.past.length<12,'large oldest revisions are evicted');
  assert.equal(editor.past.at(-1).name,'Dense edit 11','nearest undo remains available');
  const currentName=editor.scene.name;
  assert.equal(editor.undo(),true);verifyBudget();
  assert.equal(editor.scene.name,'Dense edit 11');assert.equal(JSON.stringify(editor.scene.frames.map(f=>f.take.samples)),samples);
  assert.equal(editor.redo(),true);verifyBudget();assert.equal(editor.scene.name,currentName);
  assert.equal(JSON.stringify(editor.scene.frames.map(f=>f.take.samples)),samples);
  let count=0;while(editor.undo()){count++;verifyBudget();assert.equal(JSON.stringify(editor.scene.frames.map(f=>f.take.samples)),samples);}
  assert.ok(count>=1);assert.ok(editor.future.length>=1,'bounded redo remains usable');
  editor.redo();editor.edit(s=>{s.name='New dense branch';});verifyBudget();assert.equal(editor.future.length,0);
});

test('manual history commits can enforce the same combined state and byte limits', () => {
  const editor=new M.Editor();
  editor.past=Array.from({length:45},(_,i)=>({...M.empty(),name:'Past '+i}));
  editor.future=Array.from({length:30},(_,i)=>({...M.empty(),name:'Future '+i}));
  editor.trimHistory();
  assert.equal(editor.past.length+editor.future.length,M.MAX_HISTORY_STATES);
  assert.equal(editor.past.at(-1).name,'Past 44','manual trimming preserves nearest undo');
  assert.equal(editor.future.at(-1).name,'Future 29','manual trimming preserves nearest redo');
  assert.ok(editor.historyBytes()<=M.MAX_HISTORY_BYTES);
});
