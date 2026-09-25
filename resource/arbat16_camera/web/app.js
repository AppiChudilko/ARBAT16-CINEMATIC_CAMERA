/* UI transport only. The RedM camera, interpolation and persistence live in Lua. */
(() => {
  'use strict';
  const M = CameraModel, D = CameraDirector, $ = id => document.getElementById(id);
  const maxSceneBytes=4*1024*1024;
  const isNui = typeof GetParentResourceName === 'function';
  const editor = new M.Editor();
  const state = {open:false, flight:false, nativeFlightInput:false, playing:false, recording:false, time:0, clean:false, camera:null, attachment:false, stabilization:'off', director:D.defaults()};
  const stabilizationLevels=['off','light','medium','strong'];
  const gridHints={thirds:'Place your subject where the lines cross.',golden:'A tighter grid for balanced, off-centre framing.',diagonals:'Use the diagonals to lead the eye through the shot.',quarters:'Four equal rows and columns for precise alignment.',center:'Keep a subject or horizon centred.',safe:'Outer box: 90% action area. Inner box: 80% title area.'};
  const defaultGuides=()=>({grid:false,gridType:'thirds',gridOpacity:.6});
  let guides=defaultGuides(),acknowledgedGuides=defaultGuides(),guidesRequest=0,pendingGuides=false,previewGuides=false;
  const inspectorTabs=[...document.querySelectorAll('[data-inspector-tab]')];
  let tooltipTarget=null,infoTarget=null, stabilizationRequest=0, pendingStabilization=false, acknowledgedStabilization='off';
  function showInspectorTab(name,focus=false){
    const active=inspectorTabs.find(tab=>tab.dataset.inspectorTab===name);if(!active)return;
    for(const tab of inspectorTabs){const selected=tab===active;tab.setAttribute('aria-selected',String(selected));tab.tabIndex=selected?0:-1;$(tab.getAttribute('aria-controls')).hidden=!selected;}
    document.querySelector('.inspector-content').scrollTop=0;
    hideTooltip();hideInfo();if(focus)active.focus({preventScroll:true});
  }
  function hideInfo(restoreFocus=false){
    const previous=infoTarget;infoTarget=null;$('info-popover').hidden=true;
    if(previous){previous.setAttribute('aria-expanded','false');if(restoreFocus&&previous.isConnected)previous.focus({preventScroll:true});}
  }
  function showInfo(target){
    if(infoTarget===target){hideInfo(true);return;}
    hideInfo();hideTooltip();if(!state.open||state.flight||state.clean||$('modal').open)return;
    infoTarget=target;target.setAttribute('aria-expanded','true');
    $('info-title').textContent=target.dataset.infoTitle||'About this setting';$('info-body').textContent=target.dataset.info;
    const popup=$('info-popover');popup.hidden=false;
    const rect=target.getBoundingClientRect(),size=popup.getBoundingClientRect();
    popup.style.left=Math.max(12,Math.min(rect.right-size.width,innerWidth-size.width-12))+'px';
    const below=rect.bottom+8,above=rect.top-size.height-8;
    popup.style.top=Math.max(12,Math.min(below+size.height<=innerHeight-12?below:above,innerHeight-size.height-12))+'px';
    $('info-close').focus({preventScroll:true});
  }
  function hideTooltip(){
    $('control-tooltip').hidden=true;
    if(tooltipTarget){const ids=(tooltipTarget.getAttribute('aria-describedby')||'').split(/\s+/).filter(id=>id&&id!=='control-tooltip');if(ids.length)tooltipTarget.setAttribute('aria-describedby',ids.join(' '));else tooltipTarget.removeAttribute('aria-describedby');tooltipTarget=null;}
  }
  function showTooltip(target){
    hideTooltip();if(!target||!state.open||state.flight||state.clean||$('modal').open||infoTarget||target.disabled)return;
    const help=target.dataset.help||target.getAttribute('title');if(!help)return;
    const tip=$('control-tooltip');tooltipTarget=target;tip.textContent=help;tip.hidden=false;
    target.setAttribute('aria-describedby',`${target.getAttribute('aria-describedby')||''} control-tooltip`.trim());
    const rect=target.getBoundingClientRect(),size=tip.getBoundingClientRect();
    tip.style.left=Math.max(8,Math.min(rect.left,innerWidth-size.width-8))+'px';
    tip.style.top=Math.max(8,rect.bottom+size.height+12<innerHeight?rect.bottom+8:rect.top-size.height-8)+'px';
  }
  function renderStabilization(){
    $('flight-stabilization').value=state.stabilization;
    $('stabilization-status').textContent=state.stabilization[0].toUpperCase()+state.stabilization.slice(1);
  }
  function receiveSettings(settings){
    if(!pendingStabilization&&settings&&stabilizationLevels.includes(settings.stabilization)){state.stabilization=settings.stabilization;acknowledgedStabilization=state.stabilization;renderStabilization();}
    if(settings&&!pendingGuides&&!previewGuides){
      if(typeof settings.grid==='boolean')guides.grid=settings.grid;
      if(Object.hasOwn(gridHints,settings.gridType))guides.gridType=settings.gridType;
      if(Number.isFinite(settings.gridOpacity)&&settings.gridOpacity>=.1&&settings.gridOpacity<=1)guides.gridOpacity=settings.gridOpacity;
      acknowledgedGuides={...guides};renderGuides();
    }
  }
  async function changeGuides(patch){
    const next={...guides,...patch};
    if(!Object.hasOwn(gridHints,next.gridType)||typeof next.grid!=='boolean'||!Number.isFinite(next.gridOpacity)||next.gridOpacity<.1||next.gridOpacity>1){renderGuides(true);return;}
    const request=++guidesRequest,requestSession=session;
    guides=next;previewGuides=false;pendingGuides=true;renderGuides();
    const result=await send('settings',next);
    if(requestSession!==session)return;
    if(result.ok)acknowledgedGuides={...next};
    if(request!==guidesRequest)return;
    pendingGuides=false;if(!result.ok)guides={...acknowledgedGuides};renderGuides(!result.ok);
  }
  async function changeStabilization(level){
    if(!stabilizationLevels.includes(level)){renderStabilization();return;}
    const request=++stabilizationRequest,requestSession=session;
    pendingStabilization=true;state.stabilization=level;renderStabilization();
    const result=await send('settings',{stabilization:level});
    if(requestSession!==session)return;
    if(result.ok)acknowledgedStabilization=level;
    if(request!==stabilizationRequest)return;
    pendingStabilization=false;if(!result.ok)state.stabilization=acknowledgedStabilization;renderStabilization();
  }
  const selected = new Set(), keys = new Set();
  let copied = [], dx = 0, dy = 0, dragId = null, dragCameraId = null, dragHandle = null, movedHandle = false, pendingLibrary = false, pendingSave = false;
  let session = 0, commandQueue = Promise.resolve(), sceneRevision = 0, pendingScenes = 0;
  let acknowledgedServerRevision = -1, latestStateSequence = -1, acknowledgedHistory = {past:[],future:[]};
  let acknowledgedScene = M.empty(), lastPlayState = null, pointerLocked = false, inputPending = false;
  let flightRequest = 0, pendingFlight = null, lastFlightState = false;
  let workspace = {cameras:[],presets:[],status:'loading'}, directorPending = 0, directorRequest = 0, closing = false;
  const directorPairs = {
    'look-strength':['look','strength',2,''], 'frame-opacity':['framing','opacity',2,''],
    'motion-amplitude':['motion','amplitude',2,' m'], 'motion-frequency':['motion','frequency',2,' Hz'],
    'motion-roll':['motion','roll',2,'°']
  };
  const weather = {SUNNY:'Sunny',CLOUDS:'Cloudy',OVERCAST:'Overcast',OVERCASTDARK:'Dark Overcast',RAIN:'Rain',DRIZZLE:'Drizzle',THUNDER:'Thunder',THUNDERSTORM:'Thunderstorm',FOG:'Fog',MISTY:'Mist',HIGHPRESSURE:'High Pressure',SNOW:'Snow',BLIZZARD:'Blizzard',SNOWLIGHT:'Light Snow',GROUNDBLIZZARD:'Ground Blizzard',HURRICANE:'Hurricane',WHITEOUT:'Whiteout',SANDSTORM:'Sandstorm',SLEET:'Sleet',HAIL:'Hail'};
  for (const [value,label] of Object.entries(weather)) { const o = document.createElement('option'); o.value=value; o.textContent=label; $('weather').append(o); }
  function toast(message,level='info') { const item=document.createElement('div'); item.className='toast '+(level==='error'?'error':''); item.textContent=String(message); $('toasts').append(item); setTimeout(()=>item.remove(),4200); if(level==='error'&&$('modal').open){let feedback=$('modal-body').querySelector('.dialog-feedback');if(!feedback){feedback=document.createElement('p');feedback.className='dialog-feedback';feedback.setAttribute('role','alert');$('modal-body').append(feedback);}feedback.textContent=String(message);} }
  function send(action,payload={}) {
    if(closing&&action!=='close')return Promise.resolve({ok:false,stale:true,error:'Camera is closing.'});
    if (!isNui) return Promise.resolve({ok:false,error:'Arbat16 Camera must run inside RedM.'});
    const requestSession = session, body = JSON.stringify({action,...payload});
    const perform = async () => {
      if (requestSession !== session || (!state.open && !['ready','close'].includes(action))) {
        return {ok:false,stale:true,error:'The camera session has ended.'};
      }
      const controller = new AbortController();let reply;
      const timeout = setTimeout(()=>controller.abort(),8000);
      try {
        const response = await fetch(`https://${GetParentResourceName()}/action`,{
          method:'POST',headers:{'Content-Type':'application/json; charset=UTF-8'},body,signal:controller.signal
        });
        if (!response.ok) throw Error('The RedM camera did not accept the request.');
        const result = await response.json();reply=result;
        if (requestSession !== session) return {ok:false,stale:true};
        if(Number.isSafeInteger(result?.revision))acknowledgedServerRevision=Math.max(acknowledgedServerRevision,result.revision);
        if(Number.isSafeInteger(result?.stateSequence))latestStateSequence=Math.max(latestStateSequence,result.stateSequence);
        if (!result || result.ok !== true) throw Error(result?.error || 'Camera action failed.');
        return result;
      } catch(error) {
        const message = error.name === 'AbortError' ? 'The camera did not respond. Try again.' : error.message;
        if (requestSession === session && state.open && !['input','ready'].includes(action)) toast(message,'error');
        return {ok:false,error:message,revision:reply?.revision,stale:requestSession !== session};
      } finally { clearTimeout(timeout); }
    };
    // Keep scene edits, captures and playback requests in user order. Input and
    // shutdown must remain responsive even when another callback is delayed.
    if (['input','ready','close'].includes(action)) return perform();
    const task = commandQueue.then(perform,perform);
    commandQueue = task.then(()=>undefined,()=>undefined);
    return task;
  }
  function cameraPose(raw) {
    if (!raw || typeof raw !== 'object') throw Error('Missing camera pose.');
    const projected = {};
    for (const key of ['id','label','pos','rot','fov','duration','easing','transition','weather','hour','minute','dof','handleIn','handleOut']) {
      if (raw[key] !== undefined) projected[key] = raw[key];
    }
    // Lua samples also carry interpolation metadata such as timeHours. The
    // inspector accepts only scene-schema fields and never fabricates a pose.
    return M.validate({frames:[projected]}).frames[0];
  }
  for(const item of D.filters){const option=document.createElement('option');option.value=item.id;option.textContent=item.label;$('look-filter').append(option);}
  function hideEditor() {
    closing=false;session++; sceneRevision++; pendingScenes=0; commandQueue=Promise.resolve();acknowledgedServerRevision=-1;
    flightRequest++;pendingFlight=null;
    latestStateSequence=-1;
    Object.assign(state,{open:false,flight:false,nativeFlightInput:false,playing:false,recording:false,recordingDuration:0,clean:false,time:0,camera:null,attachment:false,stabilization:'off'});
    lastFlightState=false;directorPending=0;directorRequest++;stabilizationRequest++;pendingStabilization=false;acknowledgedStabilization='off';
    guidesRequest++;pendingGuides=false;previewGuides=false;guides=defaultGuides();acknowledgedGuides=defaultGuides();renderGuides(true);
    keys.clear(); dx=dy=0; inputPending=false; pendingLibrary=false; pendingSave=false; dragHandle=null; dragId=null;dragCameraId=null;
    $('editor').hidden=true; $('editor').classList.remove('flight','clean','closing');
    $('inspector').hidden=false;$('inspector-toggle').setAttribute('aria-expanded','true');
    $('file-menu').hidden=true; $('file-button').setAttribute('aria-expanded','false');
    $('hidden-hint').hidden=true; $('path-layer').replaceChildren(); $('gizmo-layer').replaceChildren();
    $('camera-layer').replaceChildren();$('camera-frustums').replaceChildren();
    $('toasts').replaceChildren(); if($('modal').open)$('modal').close();
    hideTooltip();showInspectorTab('camera');$('flight-guide').hidden=true;renderStabilization();
    if(document.pointerLockElement)document.exitPointerLock();
  }
  function firstSelected(){ return editor.scene.frames.find(f=>selected.has(f.id)); }
  function current(){return firstSelected() || state.camera;}
  function mutate(fn){try{editor.edit(fn);sync();return true;}catch(e){toast(e.message,'error');render();return false;}}
  async function sync(){
    if(!state.open)return false;
    const revision=++sceneRevision,requestSession=session,snapshot=M.clone(editor.scene);
    const historySnapshot={past:M.clone(editor.past),future:M.clone(editor.future)};
    pendingScenes++;state.director=D.validate(editor.scene.director||D.defaults());state.playing=false;$('save-status').textContent='Applying changes…';render();
    const result=await send('scene',{scene:snapshot});
    if(requestSession!==session)return false;
    pendingScenes=Math.max(0,pendingScenes-1);
    if(result.ok&&(!Number.isSafeInteger(result.revision)||result.revision>=acknowledgedServerRevision)){
      acknowledgedScene=snapshot;acknowledgedHistory=historySnapshot;
    }
    if(revision===sceneRevision){
      if(!result.ok){editor.apply(acknowledgedScene,false);editor.past=M.clone(acknowledgedHistory.past);editor.future=M.clone(acknowledgedHistory.future);selected.clear();}
      $('save-status').textContent=result.ok?'Unsaved changes':'Changes were not applied';render();
    }
    return result.ok===true;
  }
  function changeFrames(fn){ if(!selected.size)return false; return mutate(s=>s.frames.filter(f=>selected.has(f.id)).forEach(fn)); }
  function value(id,val){if(document.activeElement!==$(id)&&$(id).getAttribute('aria-invalid')!=='true')$(id).value=val;}
  function render(){
    for(const id of selected)if(!editor.scene.frames.some(f=>f.id===id))selected.delete(id);
    $('scene-name').textContent=editor.scene.name;$('undo').disabled=!editor.past.length;$('redo').disabled=!editor.future.length;
    value('playback-speed',String(editor.scene.speed));$('loop').setAttribute('aria-pressed',String(editor.scene.loop));
    renderInspector();renderTimeline();renderState();renderDirector();
  }
  function renderInspector(){
    const f=current(),has=selected.size>0,hasTake=editor.scene.frames.some(frame=>selected.has(frame.id)&&frame.take);
    if(!f)return;
    $('selected-label').textContent=has?`Point ${String(editor.scene.frames.indexOf(firstSelected())+1).padStart(2,'0')}`:'Live camera';
    document.querySelectorAll('[data-frame-only]').forEach(section=>section.hidden=!has);
    $('pos-x').closest('details').hidden=!has||hasTake;
    $('duration').closest('details').querySelector('summary').textContent=hasTake?'Recorded clip timing':'Travel to the next point';
    $('selected-point').querySelector('.hint').textContent=hasTake?'Adjust timing; keep the recorded movement.':'An angle on your route.';
    $('point-info').dataset.info=hasTake?'Recorded clips keep their captured movement and lens together. Rename, retime, reorder, copy or delete the clip. Back to Live Camera unlocks manual lens controls.':'Each point stores a camera angle. Duration controls travel to the next point, or the hold time of the final point. Back to Live Camera returns to the lens controls.';
    $('selected-count').textContent=selected.size>1?`${selected.size} selected`:has?'Point':'Live';
    $('frame-label').disabled=!has;value('frame-label',has?f.label:'');$('delete-frame').disabled=!has;$('replace-frame').disabled=selected.size!==1||hasTake;
    $('take-timing').hidden=!has||!f.take;
    $('take-timing').textContent=f.take?`Recorded take: ${f.take.duration.toFixed(2)} s at original speed. Changing duration retimes this clip; ${f.take.samples.length} captured samples stay together.`:'';
    value('fov',f.fov);value('fov-value',f.fov);$('fov-output').textContent=Number(f.fov).toFixed(1)+'°';value('roll',f.rot.y);value('roll-value',f.rot.y);$('roll-output').textContent=Number(f.rot.y).toFixed(1)+'°';
    value('focus',f.dof.focus);value('duration',f.duration);value('transition',f.transition);value('easing',f.easing);
    for(const axis of ['x','y','z']){value('pos-'+axis,Number(f.pos[axis]).toFixed(3));$('pos-'+axis).disabled=!has;for(const dir of ['in','out']){value(dir+'-'+axis,f[dir==='in'?'handleIn':'handleOut']?.[axis]??0);$(dir+'-'+axis).disabled=!has;}}
    for(const id of ['duration','transition','easing','auto-handles'])$(id).disabled=!has;
    for(const id of ['fov','fov-value','roll','roll-value','focus','weather','time-of-day'])$(id).disabled=hasTake;
    if(hasTake)for(const id of ['transition','easing','auto-handles','pos-x','pos-y','pos-z','in-x','in-y','in-z','out-x','out-y','out-z'])$(id).disabled=true;
    value('weather',f.weather);value('time-of-day',String(f.hour).padStart(2,'0')+':'+String(f.minute).padStart(2,'0'));
  }
  function markNumber(input,message){
    if(message){input.setAttribute('aria-invalid','true');input.setCustomValidity(message);input.title=message;}
    else{input.removeAttribute('aria-invalid');input.setCustomValidity('');input.removeAttribute('title');}
  }
  function numberFrom(input,report=true){
    const raw=input.value.trim(),n=Number(raw),min=Number(input.min),max=Number(input.max);
    const valid=raw!==''&&Number.isFinite(n)&&(input.min===''||n>=min)&&(input.max===''||n<=max);
    const message=valid?'':`Enter a number${input.min!==''&&input.max!==''?` from ${min} to ${max}`:''}.`;
    markNumber(input,message);if(!valid&&report)toast(message,'error');return valid?n:null;
  }
  function bindNumber(id,commit){
    const input=$(id);let remembered=input.value;
    input.addEventListener('focus',()=>{remembered=input.value;});
    input.addEventListener('input',()=>numberFrom(input,false));
    input.addEventListener('change',()=>{const n=numberFrom(input);if(n!==null){remembered=input.value;commit(n);}});
    input.addEventListener('keydown',e=>{
      if(e.key==='Escape'){e.preventDefault();e.stopPropagation();input.value=remembered;markNumber(input,'');input.blur();}
      if(e.key==='Enter'){e.preventDefault();input.blur();}
    });
  }
  function bindPair(id,{preview,commit,digits=2,unit=''}){
    const slider=$(id),input=$(id+'-value'),output=$(id+'-output');
    const show=n=>{if(output)output.textContent=n.toFixed(digits)+unit;};
    slider.addEventListener('input',()=>{const n=Number(slider.value);input.value=slider.value;markNumber(input,'');show(n);preview?.(n);});
    slider.addEventListener('change',()=>commit(Number(slider.value)));
    bindNumber(id+'-value',n=>{slider.value=String(n);show(n);preview?.(n);commit(n);});
  }
  function renderFraming(){
    const frame=state.director.framing,mask=$('letterbox');
    const ratios={'2.39':2.39,'2.35':2.35,'1.85':1.85,'16:9':16/9,'4:3':4/3,'1:1':1};
    const target=ratios[frame.ratio],aspect=innerWidth/Math.max(1,innerHeight);
    const x=target&&aspect>target?(1-target/aspect)*50:0,y=target&&aspect<target?(1-aspect/target)*50:0;
    mask.style.setProperty('--frame-x',x+'%');mask.style.setProperty('--frame-y',y+'%');
    mask.style.opacity=String(frame.opacity);mask.dataset.ratio=frame.ratio;mask.hidden=!target||frame.opacity===0;
    $('grid').style.setProperty('--frame-x',x+'%');$('grid').style.setProperty('--frame-y',y+'%');
    $('show-bars').checked=frame.ratio==='2.39';
  }
  function renderGuides(force=false){
    const layer=$('grid');layer.hidden=!guides.grid;layer.style.opacity=String(guides.gridOpacity);
    $('show-grid').checked=guides.grid;$('grid-type').value=guides.gridType;
    const percent=Number((guides.gridOpacity*100).toFixed(2));
    for(const id of ['grid-opacity','grid-opacity-value']){if(force)$(id).value=String(percent);else value(id,percent);}
    $('grid-opacity-output').textContent=percent+'%';$('grid-hint').textContent=gridHints[guides.gridType];
    if(layer.dataset.type===guides.gridType)return;
    layer.dataset.type=guides.gridType;
    const ns='http://www.w3.org/2000/svg',svg=document.createElementNS(ns,'svg');
    svg.setAttribute('width','100%');svg.setAttribute('height','100%');svg.setAttribute('aria-hidden','true');
    const shapes=[];
    const line=(x1,y1,x2,y2)=>shapes.push(['line',{x1:x1+'%',y1:y1+'%',x2:x2+'%',y2:y2+'%'}]);
    if(['thirds','golden','quarters'].includes(guides.gridType)){
      const golden=100/((1+Math.sqrt(5))/2)**2;
      const stops=guides.gridType==='golden'?[golden,100-golden]:guides.gridType==='quarters'?[25,50,75]:[100/3,200/3];
      for(const p of stops){line(p,0,p,100);line(0,p,100,p);}
    }else if(guides.gridType==='diagonals'){line(0,0,100,100);line(0,100,100,0);}
    else if(guides.gridType==='center'){line(50,0,50,100);line(0,50,100,50);}
    else for(const inset of [5,10])shapes.push(['rect',{x:inset+'%',y:inset+'%',width:(100-2*inset)+'%',height:(100-2*inset)+'%'}]);
    // Two crisp strokes remain legible over bright skies and dark interiors.
    for(const name of ['guide-outline','guide-lines']){
      const group=document.createElementNS(ns,'g');group.setAttribute('class',name);
      for(const [tag,attributes] of shapes){const el=document.createElementNS(ns,tag);for(const [key,val] of Object.entries(attributes))el.setAttribute(key,val);group.append(el);}
      svg.append(group);
    }
    layer.replaceChildren(svg);
  }
  function renderDirector(){
    value('look-filter',state.director.look.filter);value('frame-ratio',state.director.framing.ratio);value('motion-type',state.director.motion.type);
    for(const [id,[group,key,digits,unit]] of Object.entries(directorPairs)){
      const n=state.director[group][key];value(id,n);value(id+'-value',n);$(id+'-output').textContent=n.toFixed(digits)+unit;
      const disabled=group==='motion'&&state.director.motion.type==='none'||group==='look'&&state.director.look.filter==='none';
      $(id).disabled=disabled;$(id+'-value').disabled=disabled;
    }
    renderFraming();
  }
  async function commitDirector(raw,action='director',payload={},nextCamera){
    const previous=M.clone(state.director),beforeScene=M.clone(editor.scene),beforeCamera=state.camera&&M.clone(state.camera);
    const beforeHistory={past:M.clone(editor.past),future:M.clone(editor.future)};
    try{state.director=D.validate(raw);editor.edit(scene=>{scene.director=M.clone(state.director);});}
    catch(error){state.director=previous;toast(error.message,'error');return;}
    if(nextCamera)state.camera=nextCamera;
    const snapshot=M.clone(editor.scene),historySnapshot={past:M.clone(editor.past),future:M.clone(editor.future)};
    const revision=++sceneRevision,request=++directorRequest,requestSession=session;directorPending++;render();
    const result=await send(action,action==='director'?{director:M.clone(state.director)}:payload);
    if(requestSession!==session)return;
    directorPending=Math.max(0,directorPending-1);
    if(result.ok&&(!Number.isSafeInteger(result.revision)||result.revision>=acknowledgedServerRevision)){
      acknowledgedScene=snapshot;acknowledgedHistory=historySnapshot;
    }
    if(!result.ok&&request===directorRequest&&revision===sceneRevision){
      state.director=previous;state.camera=beforeCamera;editor.apply(beforeScene,false);editor.past=beforeHistory.past;editor.future=beforeHistory.future;
    }
    if(revision===sceneRevision){$('save-status').textContent=result.ok?'Unsaved changes':'Changes were not applied';render();}
  }
  function changeDirector(edit){const draft=M.clone(state.director);edit(draft);return commitDirector(draft);}
  function recoverWorkspace(){
    const body=modal('Recover Workspace');text('p',workspace.error||'The saved workspace could not be loaded.',body);
    text('p','Discard the unreadable autosaved workspace and start saving the current session? Named scenes in Scene Library will remain.',body);
    const actions=text('div','',body);actions.className='actions';button('Cancel',actions,()=>$('modal').close());
    const reset=button('Reset Workspace',actions,async()=>{reset.disabled=true;const result=await send('workspaceReset');reset.disabled=false;if(result.ok&&body.contains(reset))$('modal').close();},'danger-button');
  }
  function selectedCamera(){return workspace.cameras.find(camera=>camera.id===$('camera-bank').value);}
  function chooseCamera(id){if(!workspace.cameras.some(camera=>camera.id===id))return;$('camera-bank').value=id;renderCameraSelection();showInspectorTab('saved');$('inspector').hidden=false;$('inspector-toggle').setAttribute('aria-expanded','true');}
  function addCameraToRoute(id,beforeId){if(!workspace.cameras.some(camera=>camera.id===id))return;send('cameraAdd',{id,duration:3,...(beforeId?{beforeId}:{})});}
  function selectedPreset(){return workspace.presets.find(preset=>preset.id===$('preset-select').value);}
  function renderCameraSelection(){
    const camera=selectedCamera(),info=$('camera-bank-info');
    if(camera){const f=camera.frame;info.textContent=f?.pos?`${Number(f.pos.x).toFixed(1)}, ${Number(f.pos.y).toFixed(1)}, ${Number(f.pos.z).toFixed(1)} · ${Number(f.fov??50).toFixed(1)}° FOV`:camera.name;}
    else info.textContent='Save a camera to return to this exact angle.';
    for(const id of ['camera-recall','camera-update','camera-delete','camera-add'])$(id).disabled=!camera;
    for(const card of $('camera-cards').children)card.setAttribute('aria-pressed',String(card.dataset.cameraId===camera?.id));
    for(const marker of $('camera-layer').children)marker.setAttribute('aria-pressed',String(marker.dataset.cameraId===camera?.id));
    $('camera-bank-count').textContent=String(workspace.cameras.length);
  }
  function renderPresetSelection(){
    const custom=selectedPreset();$('custom-preset-actions').hidden=!custom;$('preset-apply').disabled=!$('preset-select').value;
  }
  function renderWorkspace(){
    const cameraId=$('camera-bank').value,presetId=$('preset-select').value;
    $('camera-bank').replaceChildren();$('camera-cards').replaceChildren();
    for(const [index,camera]of workspace.cameras.entries()){
      const option=document.createElement('option');option.value=camera.id;option.textContent=camera.name;option.title=camera.name;$('camera-bank').append(option);
      const card=document.createElement('button');card.type='button';card.className='camera-card';card.dataset.cameraId=camera.id;card.draggable=true;card.setAttribute('aria-pressed','false');card.dataset.help=`${camera.name}. Select this angle, or drag it onto the timeline to add a shot.`;
      const number=text('span',String(index+1).padStart(2,'0'),card);number.className='camera-card-number';text('span',camera.name,card);const handle=text('span','⠿',card);handle.className='camera-card-grip';handle.setAttribute('aria-hidden','true');
      card.onclick=()=>chooseCamera(camera.id);card.ondblclick=()=>{chooseCamera(camera.id);$('camera-recall').click();};
      card.ondragstart=event=>{dragCameraId=camera.id;dragId=null;event.dataTransfer.setData('application/x-arbat16-camera',camera.id);event.dataTransfer.effectAllowed='copy';$('track').classList.add('drop-ready');};
      card.ondragend=()=>{dragCameraId=null;$('track').classList.remove('drop-ready');};$('camera-cards').append(card);
    }
    if(workspace.cameras.some(c=>c.id===cameraId))$('camera-bank').value=cameraId;
    else if(workspace.cameras.length)$('camera-bank').selectedIndex=0;
    $('preset-select').replaceChildren();
    for(const [label,items] of [['Built-in',D.presets],['Your Presets',workspace.presets]]){
      if(!items.length)continue;const group=document.createElement('optgroup');group.label=label;
      for(const preset of items){const option=document.createElement('option');option.value=preset.id;option.textContent=preset.name;group.append(option);}$('preset-select').append(group);
    }
    if([...D.presets,...workspace.presets].some(p=>p.id===presetId))$('preset-select').value=presetId;
    const statuses={loading:'Workspace loading…',saving:'Saving workspace…',saved:'Workspace saved',error:'Workspace save failed',disabled:'Workspace saving disabled'};
    $('workspace-status').textContent=statuses[workspace.status]||'Workspace ready';
    $('workspace-feedback').dataset.status=workspace.status;$('workspace-recover').hidden=workspace.status!=='disabled';
    $('workspace-feedback').title=workspace.error||'Your last camera, saved cameras and presets are restored when you return.';
    renderCameraSelection();renderPresetSelection();
  }
  function receiveWorkspace(raw){
    if(!raw||typeof raw!=='object')return;
    for(const key of ['cameras','presets']){
      const entries=raw[key];
      if(Array.isArray(entries))workspace[key]=entries.filter(item=>item&&typeof item.id==='string'&&typeof item.name==='string');
      // Cfx may encode an empty Lua array as an empty JSON object.
      else if(entries&&typeof entries==='object'&&Object.keys(entries).length===0)workspace[key]=[];
    }
    if(typeof raw.status==='string')workspace.status=raw.status;
    workspace.error=typeof raw.error==='string'?raw.error.slice(0,240):'';renderWorkspace();
  }
  function nameAsset(kind,item){
    const isCamera=kind==='camera',body=modal(item?`Update ${isCamera?'Camera':'Preset'}`:`Save ${isCamera?'Camera':'Preset'}`);
    text('p',isCamera?'Save the current camera position, lens, look, framing and motion.':'Save the current lens, look, framing and motion as a reusable preset.',body);
    const label=text('label',isCamera?'Camera name':'Preset name',body);label.htmlFor='asset-name';
    const input=document.createElement('input');input.id='asset-name';input.type='text';input.maxLength=64;input.value=item?.name||`${isCamera?'Camera':'Preset'} ${(isCamera?workspace.cameras:workspace.presets).length+1}`;body.append(input);
    const actions=text('div','',body);actions.className='actions';button('Cancel',actions,()=>$('modal').close());let busy=false;
    const submit=async()=>{
      if(busy)return;const name=input.value.trim();
      if(!name||new TextEncoder().encode(name).length>64||/[\x00-\x1f\x7f-\x9f/\\]/.test(name)){markNumber(input,'Use a name from 1 to 64 bytes without slashes or control characters.');toast('Use a name from 1 to 64 bytes without slashes or control characters.','error');return;}
      markNumber(input,'');busy=true;save.disabled=true;
      const result=await send(isCamera?'cameraSave':'presetSave',{name,...(item?{id:item.id}:{})});busy=false;save.disabled=false;
      if(result.ok&&body.contains(input))$('modal').close();
    };
    const save=button(item?'Update':'Save',actions,submit,'primary');input.onkeydown=e=>{if(e.key==='Enter'){e.preventDefault();submit();}};input.focus();input.select();
  }
  function deleteAsset(kind,item){
    if(!item)return;const body=modal(`Delete ${kind==='camera'?'Saved Camera':'Preset'}?`);text('p',item.name,body);
    const actions=text('div','',body);actions.className='actions';button('Cancel',actions,()=>$('modal').close());
    const remove=button('Delete',actions,async()=>{remove.disabled=true;const result=await send(kind==='camera'?'cameraDelete':'presetDelete',{id:item.id});remove.disabled=false;if(result.ok&&body.contains(remove))$('modal').close();},'danger-button');
  }
  function showMove(){
    const body=modal('Generate Camera Move');text('p','Append an editable move to the timeline, starting from your current camera. Use a negative distance or angle to reverse its direction.',body);
    const form=text('div','',body);form.className='move-form';
    const field=(id,label,tag='input')=>{const row=text('label',label,form);row.htmlFor=id;const control=document.createElement(tag);control.id=id;row.append(control);return control;};
    const kind=field('move-kind','Move','select');
    for(const [id,label] of [['dolly','Dolly · forward / back'],['truck','Truck · left / right'],['crane','Crane · up / down'],['pan','Pan · turn in place'],['orbit','Orbit · around a point ahead']]){const option=document.createElement('option');option.value=id;option.textContent=label;kind.append(option);}
    const numeric=(id,label,min,max,step,initial)=>{const input=field(id,label);Object.assign(input,{type:'number',min:String(min),max:String(max),step:String(step),value:String(initial)});input.oninput=()=>numberFrom(input,false);return input;};
    const distance=numeric('move-distance','Travel / orbit radius, m',-500,500,.1,5),angle=numeric('move-angle','Turn / orbit angle, degrees',-360,360,1,45),duration=numeric('move-duration','Total duration, s',.2,600,.1,5);
    const returnRow=text('label','',form);returnRow.className='toggle-row';text('span','Return to start',returnRow);const back=document.createElement('input');back.id='move-return';back.type='checkbox';returnRow.append(back);
    const note=text('p','Duration includes the return journey. Orbit centres on a point ahead at the absolute radius you enter.',body);note.className='hint';
    const configure=()=>{angle.disabled=!['pan','orbit'].includes(kind.value);distance.disabled=kind.value==='pan';};kind.onchange=configure;configure();
    const actions=text('div','',body);actions.className='actions';button('Cancel',actions,()=>$('modal').close());
    const generate=button('Append Move',actions,async()=>{
      const d=distance.disabled?5:numberFrom(distance),a=angle.disabled?0:numberFrom(angle),seconds=numberFrom(duration);if(d===null||a===null||seconds===null)return;
      if(kind.value==='orbit'&&Math.abs(d)<.1){markNumber(distance,'Orbit radius must be at least 0.1 m.');toast('Orbit radius must be at least 0.1 m.','error');return;}
      generate.disabled=true;const result=await send('generateMove',{kind:kind.value,distance:d,angle:a,duration:seconds,returnToStart:back.checked});generate.disabled=false;
      if(result.ok&&body.contains(generate)){$('modal').close();toast('Camera move appended. Press Play to preview.');}
    },'primary');
  }
  function renderTimeline(){
    const total=M.duration(editor.scene),span=Math.max(12,total),starts=M.starts(editor.scene);
    $('frame-total').textContent=String(editor.scene.frames.length).padStart(2,'0');$('total-time').textContent=M.timecode(total);
    $('scrubber').max=String(span);$('scrubber-value').max=String(total);$('ruler').replaceChildren();$('track').replaceChildren();
    for(let i=0;i<=12;i++){const mark=document.createElement('span');mark.style.left=(i/12*100)+'%';mark.textContent=Number((span*i/12).toFixed(1))+'s';$('ruler').append(mark);}
    editor.scene.frames.forEach((f,i)=>{
      const key=document.createElement('button');key.className='keyframe '+f.transition+(f.take?' recorded-take':'')+(selected.has(f.id)?' selected':'');key.style.left=starts[i]/span*100+'%';key.style.width=Math.max(.25,f.duration/span*100)+'%';key.dataset.id=f.id;key.draggable=true;
      key.setAttribute('aria-label',`${f.label}, ${f.duration} s`);key.setAttribute('aria-pressed',String(selected.has(f.id)));key.title=`${f.label} · ${f.duration.toFixed(2)} s · ${f.transition}`;
      const diamond=document.createElement('span');diamond.className='diamond';const name=document.createElement('span');name.className='frame-name';name.textContent=`${String(i+1).padStart(2,'0')}  ${f.label}`;key.append(diamond,name);
      if(f.take){key.dataset.help=`Recorded take · ${f.duration.toFixed(2)} s · ${f.take.samples.length} samples · drag to reorder. Duration changes retime the original ${f.take.duration.toFixed(2)} s recording.`;const meta=text('span',`Recorded · ${f.duration.toFixed(1)} s`,key);meta.className='take-meta';}
      key.addEventListener('click',e=>selectFrame(f.id,e.shiftKey||e.ctrlKey));key.addEventListener('dblclick',()=>f.take?send('seek',{time:starts[i]}):send('setCamera',{frame:f}));
      key.addEventListener('dragstart',e=>{dragId=f.id;dragCameraId=null;e.dataTransfer.setData('text/plain',f.id);e.dataTransfer.effectAllowed='move';});key.addEventListener('dragover',e=>e.preventDefault());
      key.addEventListener('drop',e=>{e.preventDefault();e.stopPropagation();if(dragCameraId){addCameraToRoute(dragCameraId,f.id);dragCameraId=null;$('track').classList.remove('drop-ready');}else if(dragId){try{editor.reorder(dragId,f.id);sync();}catch(err){toast(err.message,'error');}}dragId=null;});
      key.addEventListener('dragend',()=>dragId=null);$('track').append(key);
    });
    renderTime();
  }
  function selectFrame(id,multi=false){if(!multi)selected.clear();if(multi&&selected.has(id))selected.delete(id);else selected.add(id);if(selected.size)showInspectorTab('advanced');renderInspector();renderTimeline();}
  function renderTime(){value('scrubber-value',Number(state.time.toFixed(3)));const span=Math.max(12,M.duration(editor.scene));$('timecode').textContent=M.timecode(state.time);$('playhead').style.left=M.clamp(state.time/span*100,0,100)+'%';if(document.activeElement!==$('scrubber'))$('scrubber').value=String(state.time);}
  function renderState(){
    $('editor').classList.toggle('flight',state.flight);$('editor').classList.toggle('clean',state.clean);
    $('mode-label').textContent=state.recording?'Recording route':state.playing?'Playback':state.flight?'Moving camera':'Editor';
    $('flight-label').textContent=state.flight?'Return to Editor':'Move Camera';
    $('flight-guide').hidden=!state.flight;
    $('flight-guide-title').textContent=state.recording?`Recording ${M.timecode(state.recordingDuration||0)} · R to stop`:'Camera moving';
    if(state.flight||state.clean){hideTooltip();hideInfo();}
    $('attachment-label').textContent=state.attachment?'Attached camera':'Free camera';
    $('record').setAttribute('aria-pressed',String(state.recording));$('record-label').textContent=state.recording?'Stop Recording':'Record Route';
    $('record').setAttribute('aria-label',state.recording?'Stop Recording Route':'Record Route');
    if(lastPlayState!==state.playing){
      lastPlayState=state.playing;
      $('play').setAttribute('aria-label',state.playing?'Pause Route':'Play Route');
      $('play-label').textContent=state.playing?'Pause Route':'Play Route';
      $('play').setAttribute('aria-pressed',String(state.playing));
      $('play').querySelector('path').setAttribute('d',state.playing?'M8 5v14M16 5v14':'m8 5 11 7-11 7z');
    }
    $('play').disabled=editor.scene.frames.length===0;
    if(state.camera){for(const axis of ['x','y','z'])$('cam-'+axis).textContent=Number(state.camera.pos[axis]).toFixed(1);$('cam-fov').textContent=Number(state.camera.fov).toFixed(1)+'°';}
    if(!state.flight&&document.pointerLockElement)document.exitPointerLock();
    if(lastFlightState&&!state.flight&&state.nativeFlightInput&&!$('modal').open)$('viewport').focus({preventScroll:true});
    lastFlightState=state.flight;renderTime();
  }
  function releaseKeys(){keys.clear();dx=dy=0;if(state.open)send('input',{keys:[],dx:0,dy:0});}
  function pointerLockFallback(){if(state.open&&state.flight)toast('Hold the right mouse button to look around.');}
  function setFlight(enabled){
    if(!state.open)return;
    const requestSession=session,request=++flightRequest;
    pendingFlight=enabled;state.flight=enabled;releaseKeys();renderState();
    send('flight',{enabled}).then(result=>{
      if(requestSession!==session||request!==flightRequest)return;
      pendingFlight=null;state.flight=result.ok?enabled:false;renderState();
    });
    if(enabled&&!state.nativeFlightInput){
      $('viewport').focus({preventScroll:true});
      try{
        if(!$('viewport').requestPointerLock){pointerLockFallback();return;}
        const result=$('viewport').requestPointerLock();result?.catch?.(pointerLockFallback);
      }catch{pointerLockFallback();}
    }
  }
  async function close(){
    if(closing)return;const requestSession=session;closing=true;$('editor').classList.add('closing');
    // Let accepted edits reach Lua before it snapshots the closing workspace.
    // hideEditor increments the session, so it must follow the queued callbacks.
    await commandQueue;if(requestSession!==session){closing=false;return;}hideEditor();closing=false;send('close');
  }
  function clean(){state.clean=!state.clean;renderState();$('hidden-hint').hidden=!state.clean;if(state.clean)setTimeout(()=>$('hidden-hint').hidden=true,3000);}
  function history(redo=false){if((redo?editor.redo():editor.undo())){selected.clear();sync();}}
  function copy(){copied=M.clone(editor.scene.frames.filter(f=>selected.has(f.id)));if(copied.length)toast(`Keyframes copied: ${copied.length}`);}
  function paste(){if(!copied.length)return;try{const ids=editor.paste(copied,firstSelected()?.id);selected.clear();ids.forEach(id=>selected.add(id));sync();}catch(e){toast(e.message,'error');}}
  function remove(){if(!selected.size)return;editor.remove(selected);selected.clear();sync();}
  function step(direction){state.time=M.clamp(state.time+direction/30,0,M.duration(editor.scene));send('seek',{time:state.time});renderTime();}
  function modal(title){hideTooltip();hideInfo();releaseKeys();if(state.flight)setFlight(false);$('modal-title').textContent=title;$('modal-body').replaceChildren();if(!$('modal').open)$('modal').showModal();return $('modal-body');}
  function text(tag,content,parent){const node=document.createElement(tag);node.textContent=content;parent.append(node);return node;}
  function button(label,parent,handler,className=''){const b=text('button',label,parent);b.type='button';b.className=className;b.addEventListener('click',handler);return b;}
  function nameDialog(){
    const body=modal('Save Scene');
    text('p','Save to your personal scene library on the server. An existing scene with the same name will be replaced.',body);
    const label=text('label','Scene name',body);label.htmlFor='save-name';
    const input=document.createElement('input');input.id='save-name';input.type='text';input.maxLength=64;input.value=editor.scene.name;body.append(input);
    const actions=text('div','',body);actions.className='actions';button('Cancel',actions,()=>$('modal').close());
    let busy=false;
    const submit=async()=>{
      if(busy)return;
      let name;try{name=M.validate({...editor.scene,name:input.value}).name;}catch(e){toast(e.message,'error');return;}
      busy=true;save.disabled=true;pendingSave=true;$('save-status').textContent='Saving to server…';
      const result=await send('save',{name});busy=false;save.disabled=false;
      if(result.ok){if(body.contains(input))$('modal').close();}
      else if(!result.stale){pendingSave=false;$('save-status').textContent='Save failed — changes remain in memory';}
    };
    const save=button('Save',actions,submit,'primary');
    input.addEventListener('keydown',e=>{if(e.key==='Enter'){e.preventDefault();submit();}});input.focus();input.select();
  }
  function showLibrary(items){pendingLibrary=false;const body=modal('Scene Library');if(!items.length)text('p','Your saved scenes will appear here.',body);for(const item of items){const row=text('div','',body);row.className='library-row';const info=text('div','',row);text('strong',item.name,info);text('small',`${item.frames} keyframes · ${M.timecode(item.duration)}`,info);button('Open',row,()=>{send('load',{name:item.name});$('modal').close();});button('Delete',row,()=>{const confirm=modal('Delete Saved Scene?');text('p',item.name,confirm);const actions=text('div','',confirm);actions.className='actions';button('Back',actions,()=>showLibrary(items));button('Delete',actions,()=>{pendingLibrary=true;send('delete',{name:item.name});},'danger-button');});}}
  function showHelp(){
    state.clean=false;renderState();const body=modal('Camera Guide');
    text('h3','Make your first shot',body);const steps=text('ol','',body);steps.className='help-steps';
    for(const instruction of ['Click Move Camera. Use WASD and the mouse to find your first angle. Q moves down; E moves up.','Press F to Add Point. Move to another angle and press F again. A point is also called a keyframe.','Press Tab to return, then Play Route. Click a point on the timeline to change its travel time.','Click Save Scene to keep the route. Use Record Route (R) to capture your flying movement automatically instead.'])text('li',instruction,steps);
    text('p','Record Route saves camera movement, not video. Capture video with OBS or your graphics card recorder. Your current workspace, including the last camera angle, also saves automatically.',body);
    text('h3','Smooth flight',body);text('p','In Camera, choose Off, Light, Medium or Strong stabilization. It softens mouse turns and movement in every direction, including up and down. Stronger levels feel slower and more floating. Press J while flying to change the level. The recorded route uses the smoothed movement.',body);
    const groups=[['While moving the camera',[['W A S D','Move forward, backward and sideways'],['Q / E','Move down / up'],['Mouse','Look around'],['Shift','Move faster'],['Ctrl or Alt','Move slower'],['J','Change stabilization level'],['R','Start / stop recording a route'],['F','Add a route point'],['Tab','Return to the editor']]],['Editor and playback',[['F','Add a route point'],['Space','Play / pause route'],['R','Start / stop recording a route'],['← / →','Step one timeline frame'],['Shift + click','Select several points'],['Delete','Delete selected points'],['Ctrl C / V / A','Copy / paste / select all points'],['Ctrl Z / Ctrl Shift Z','Undo / redo'],['Ctrl S','Save Scene']]],['View and help',[['G','Show / hide composition guides'],['H','Hide / show the interface'],['F1','Open this guide'],['Esc','Close camera, or close the open dialog']]]];
    for(const [heading,shortcuts]of groups){const section=text('details','',body);section.className='help-shortcuts';section.open=heading==='While moving the camera';text('summary',heading,section);for(const [key,description]of shortcuts){const row=text('div','',section);row.className='shortcut-row';text('span',description,row);text('kbd',key,row);}}
    text('h3','Where everything lives',body);text('p','Camera: flight smoothing, composition guides and lens. Look: presets, filters and cinema frames. Saved: reusable camera angles and scene library. Advanced: route points, generated moves, weather and added sway. Stabilization smooths your input; added sway creates deliberate movement.',body);
    text('p','A saved camera is one angle. A scene is a complete route and look. A preset is a reusable look. In the editor, Tab moves between controls; click Move Camera to start flying. Shortcuts pause while you type or use a dialog.',body);
  }
  function showAttach(){const body=modal('Attach Camera Path');text('p','Move the entire path with a character, horse or wagon. For crosshair selection, first point the centre of the camera at the entity.',body);const label=text('label','',body);label.className='toggle-row';text('span','Follow entity rotation',label);const rotate=document.createElement('input');rotate.type='checkbox';rotate.checked=true;label.append(rotate);const actions=text('div','',body);actions.className='actions';for(const [mode,name] of [['aim','At Crosshair'],['player','Player'],['mount','Horse / Wagon'],['detach','Detach']])button(name,actions,()=>{send('attach',{mode,rotate:rotate.checked});$('modal').close();});}
  function exportScene(){const body=modal('Export Scene');text('p','Select and copy the JSON to transfer your scene. If file downloads are available, you can save a .json file.',body);const area=document.createElement('textarea');area.value=JSON.stringify(editor.scene,null,2);area.readOnly=true;area.setAttribute('aria-label','Scene JSON');body.append(area);const actions=text('div','',body);actions.className='actions';button('Select JSON',actions,()=>{area.focus();area.select();});button('Download .json',actions,()=>{const url=URL.createObjectURL(new Blob([area.value],{type:'application/json'}));const a=document.createElement('a');a.href=url;a.download='arbat16-camera-scene.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);},'primary');}
  async function applyImport(raw){
    try{
      if(new TextEncoder().encode(raw).length>maxSceneBytes)throw Error('File exceeds 4 MB.');
      editor.apply(JSON.parse(raw));selected.clear();state.time=0;
      if(await sync()){if($('modal').open)$('modal').close();toast('Scene imported');}
    }catch(e){toast(e.message,'error');}
  }
  function importScene(){const body=modal('Import Scene');text('p','Paste scene JSON below or choose a file. You can undo an import with Ctrl Z.',body);const area=document.createElement('textarea');area.setAttribute('aria-label','Scene JSON to import');body.append(area);const actions=text('div','',body);actions.className='actions';button('Choose File',actions,()=>$('import-file').click());button('Import',actions,()=>applyImport(area.value),'primary');}
  const fileActions={new:()=>{editor.apply(M.empty());selected.clear();state.time=0;sync();},save:nameDialog,library:()=>{pendingLibrary=true;const body=modal('Scene Library');text('p','Loading…',body);send('list');},export:exportScene,import:importScene};
  $('file-button').onclick=()=>{const open=$('file-menu').hidden;$('file-menu').hidden=!open;$('file-button').setAttribute('aria-expanded',String(open));};
  document.querySelectorAll('#file-menu [data-action]').forEach(b=>b.onclick=()=>{$('file-menu').hidden=true;$('file-button').setAttribute('aria-expanded','false');fileActions[b.dataset.action]();});
  document.addEventListener('click',e=>{if(!e.target.closest('.menu-wrap')){$('file-menu').hidden=true;$('file-button').setAttribute('aria-expanded','false');}});
  $('help-button').onclick=showHelp;$('attach-button').onclick=showAttach;$('modal-close').onclick=()=>$('modal').close();
  $('save-scene').onclick=nameDialog;$('scene-library').onclick=fileActions.library;
  document.querySelectorAll('[data-info]').forEach(button=>button.onclick=()=>showInfo(button));
  $('info-close').onclick=()=>hideInfo(true);
  document.addEventListener('click',event=>{if(infoTarget&&!event.target.closest('[data-info],#info-popover'))hideInfo();});
  document.addEventListener('keydown',event=>{
    if(!infoTarget)return;
    if(event.code==='Escape'){event.preventDefault();event.stopImmediatePropagation();hideInfo(true);}
  },true);
  document.addEventListener('focusin',event=>{if(infoTarget&&event.target!==infoTarget&&!$('info-popover').contains(event.target))hideInfo();});
  document.querySelector('.inspector-content').addEventListener('scroll',()=>hideInfo());
  $('deselect-frame').onclick=()=>{selected.clear();showInspectorTab('camera');render();};
  $('flight-stabilization').onchange=()=>changeStabilization($('flight-stabilization').value);
  inspectorTabs.forEach((tab,index)=>{
    tab.onclick=()=>showInspectorTab(tab.dataset.inspectorTab);
    tab.addEventListener('keydown',event=>{
      if(event.altKey||event.ctrlKey||event.metaKey||event.shiftKey)return;
      const target=event.code==='ArrowRight'?(index+1)%inspectorTabs.length:event.code==='ArrowLeft'?(index+inspectorTabs.length-1)%inspectorTabs.length:event.code==='Home'?0:event.code==='End'?inspectorTabs.length-1:null;
      if(target!==null){event.preventDefault();event.stopPropagation();showInspectorTab(inspectorTabs[target].dataset.inspectorTab,true);}
    });
  });
  document.querySelectorAll('[title]').forEach(element=>{if(!element.dataset.help)element.dataset.help=element.title;element.removeAttribute('title');});
  document.addEventListener('pointerover',event=>showTooltip(event.target.closest('[data-help],[title]')));
  document.addEventListener('pointerout',event=>{if(tooltipTarget&&!tooltipTarget.contains(event.relatedTarget))hideTooltip();});
  document.addEventListener('focusin',event=>showTooltip(event.target.closest('[data-help],[title]')));
  document.addEventListener('focusout',hideTooltip);document.addEventListener('scroll',hideTooltip,true);
  $('close').onclick=close;$('clean-button').onclick=clean;$('flight-button').onclick=()=>setFlight(!state.flight);
  $('inspector-toggle').onclick=()=>{hideInfo();const visible=$('inspector').hidden;$('inspector').hidden=!visible;$('inspector-toggle').setAttribute('aria-expanded',String(visible));};
  $('capture').onclick=()=>send('capture');$('replace-frame').onclick=()=>send('capture',{replaceId:firstSelected()?.id});$('delete-frame').onclick=remove;
  $('play').onclick=()=>send(state.playing?'pause':'play');$('stop').onclick=()=>send('stop');$('record').onclick=()=>send('record',{enabled:!state.recording});
  $('loop').onclick=()=>mutate(s=>s.loop=!s.loop);$('undo').onclick=()=>history();$('redo').onclick=()=>history(true);$('previous').onclick=()=>step(-1);$('next').onclick=()=>step(1);
  $('scrubber').oninput=()=>{state.time=M.clamp(Number($('scrubber').value),0,M.duration(editor.scene));markNumber($('scrubber-value'),'');send('seek',{time:state.time});renderTime();};
  bindNumber('scrubber-value',n=>{state.time=n;send('seek',{time:n});renderTime();});
  bindNumber('playback-speed',n=>mutate(s=>s.speed=n));
  bindPair('fly-speed',{digits:1,preview:n=>send('settings',{speed:n}),commit:()=>{}});
  $('frame-label').onchange=()=>changeFrames(f=>f.label=$('frame-label').value.trim()||'Keyframe');
  bindNumber('duration',n=>changeFrames(f=>f.duration=n));for(const id of ['transition','easing'])$(id).onchange=()=>changeFrames(f=>f[id]=$(id).value);
  for(const [id,key] of [['fov','fov'],['roll','roll']])bindPair(id,{digits:1,unit:'°',preview:n=>send('lens',{[key]:n}),commit:n=>changeFrames(f=>{if(id==='fov')f.fov=n;else f.rot.y=n;})});
  for(const [id,[group,key,digits,unit]] of Object.entries(directorPairs))bindPair(id,{digits,unit,preview:n=>{if(group==='framing'){const preview=M.clone(state.director);preview[group][key]=n;const previous=state.director;state.director=preview;renderFraming();state.director=previous;}},commit:n=>changeDirector(d=>{d[group][key]=n;})});
  for(const [id,group,key] of [['look-filter','look','filter'],['frame-ratio','framing','ratio'],['motion-type','motion','type']])$(id).onchange=()=>changeDirector(d=>{d[group][key]=$(id).value;if(id==='look-filter'&&d.look.filter==='monochrome')d.look.strength=1;});
  $('camera-bank').onchange=renderCameraSelection;$('preset-select').onchange=renderPresetSelection;
  $('camera-add').onclick=()=>{const camera=selectedCamera();if(camera)addCameraToRoute(camera.id);};
  $('track').addEventListener('dragover',event=>{if(dragCameraId||dragId){event.preventDefault();event.dataTransfer.dropEffect=dragCameraId?'copy':'move';}});
  $('track').addEventListener('drop',event=>{
    if(!dragCameraId&&!dragId)return;event.preventDefault();
    if(dragCameraId)addCameraToRoute(dragCameraId);
    else{try{editor.reorder(dragId,null);sync();}catch(error){toast(error.message,'error');}}
    dragCameraId=null;dragId=null;$('track').classList.remove('drop-ready');
  });
  $('camera-save').onclick=()=>nameAsset('camera');$('camera-update').onclick=()=>nameAsset('camera',selectedCamera());
  $('camera-recall').onclick=()=>{const item=selectedCamera();if(item){selected.clear();commitDirector(item.director||D.defaults(),'cameraRecall',{id:item.id},cameraPose(item.frame));}};
  $('camera-delete').onclick=()=>deleteAsset('camera',selectedCamera());
  $('preset-apply').onclick=()=>{const preset=[...workspace.presets,...D.presets].find(item=>item.id===$('preset-select').value);if(!preset)return;selected.clear();const camera=M.clone(state.camera);camera.fov=preset.fov;camera.dof.focus=preset.focus;commitDirector(preset.director,'presetApply',{id:preset.id},camera);};
  $('preset-save').onclick=()=>nameAsset('preset');$('preset-update').onclick=()=>nameAsset('preset',selectedPreset());$('preset-delete').onclick=()=>deleteAsset('preset',selectedPreset());
  $('generate-move').onclick=showMove;$('workspace-recover').onclick=recoverWorkspace;
  window.addEventListener('resize',()=>{hideInfo();renderFraming();});
  bindNumber('focus',focus=>{send('lens',{dof:{focus}});changeFrames(f=>f.dof.focus=focus);});
  function worldChanged(){
    const input=$('time-of-day'),match=/^([01]\d|2[0-3]):([0-5]\d)$/.exec(input.value);
    if(!match){
      input.setAttribute('aria-invalid','true');
      toast('Enter a time in HH:MM format, from 00:00 to 23:59.','error');return;
    }
    input.removeAttribute('aria-invalid');
    const data={weather:$('weather').value,hour:Number(match[1]),minute:Number(match[2])};
    send('environment',data);changeFrames(f=>Object.assign(f,data));
  }
  $('weather').onchange=worldChanged;$('time-of-day').onchange=worldChanged;
  for(const axis of ['x','y','z']){
    bindNumber('pos-'+axis,n=>{const start=firstSelected();if(!start)return;const delta=n-start.pos[axis];changeFrames(f=>f.pos[axis]+=delta);});
    for(const dir of ['in','out'])bindNumber(dir+'-'+axis,val=>{changeFrames(f=>{const key=dir==='in'?'handleIn':'handleOut';f[key]??={x:0,y:0,z:0};f[key][axis]=val;});});
  }
  $('auto-handles').onclick=()=>changeFrames(f=>{delete f.handleIn;delete f.handleOut;});
  $('show-grid').onchange=()=>changeGuides({grid:$('show-grid').checked});
  $('grid-type').onchange=()=>changeGuides({gridType:$('grid-type').value,grid:true});
  bindPair('grid-opacity',{digits:0,unit:'%',preview:n=>{previewGuides=true;guides.gridOpacity=n/100;renderGuides();},commit:n=>changeGuides({gridOpacity:n/100})});
  $('grid-opacity').addEventListener('blur',()=>{if(previewGuides&&!pendingGuides){previewGuides=false;guides={...acknowledgedGuides};renderGuides(true);}});
  for(const [id,key] of [['show-path','showPath'],['show-cameras','showCameras'],['hide-hud','hideHud']])$(id).onchange=()=>{send('settings',{[key]:$(id).checked});if(key==='showPath'){if(!$(id).checked){$('path-layer').replaceChildren();$('gizmo-layer').replaceChildren();}}if(key==='showCameras'&&!$(id).checked){$('camera-layer').replaceChildren();$('camera-frustums').replaceChildren();}};
  $('show-bars').onchange=()=>changeDirector(d=>{d.framing.ratio=$('show-bars').checked?'2.39':'native';});
  $('import-file').onchange=async()=>{const f=$('import-file').files[0],requestSession=session;if(!f)return;try{if(f.size>maxSceneBytes)throw Error('File exceeds 4 MB.');const raw=await f.text();if(requestSession===session&&state.open)await applyImport(raw);}catch(e){toast(e.message,'error');}$('import-file').value='';};
  function drawSavedCameras(raw){
    const layer=$('camera-layer'),frustums=$('camera-frustums');
    if(!$('show-cameras').checked||state.clean){layer.replaceChildren();frustums.replaceChildren();return;}
    const cameras=Array.isArray(raw)?raw.filter(camera=>camera&&typeof camera.id==='string'&&Number.isFinite(camera.x)&&Number.isFinite(camera.y)).slice(0,100):[];
    const existing=new Map([...layer.children].map(marker=>[marker.dataset.cameraId,marker])),retained=new Set(),lines=[];
    for(const camera of cameras){
      const saved=workspace.cameras.find(item=>item.id===camera.id);if(!saved)continue;
      retained.add(camera.id);let marker=existing.get(camera.id);
      if(!marker){marker=document.createElement('button');marker.type='button';marker.className='world-camera';marker.dataset.cameraId=camera.id;marker.innerHTML='<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 6h13v12H3zM16 10l5-3v10l-5-3M6 10h6"/></svg><span></span>';marker.onclick=()=>chooseCamera(camera.id);marker.ondblclick=()=>{chooseCamera(camera.id);$('camera-recall').click();};layer.append(marker);}
      const index=Number.isSafeInteger(camera.index)&&camera.index>0?camera.index:workspace.cameras.indexOf(saved)+1;
      marker.style.left=(camera.x*100)+'%';marker.style.top=(camera.y*100)+'%';marker.querySelector('span').textContent=String(index).padStart(2,'0')+' · '+saved.name;marker.setAttribute('aria-label','Select saved camera '+index+': '+saved.name);marker.setAttribute('aria-pressed',String($('camera-bank').value===camera.id));marker.dataset.help=saved.name+' · select to add this camera to the route. Double-click to go to this angle.';
      if(Array.isArray(camera.lines))for(const line of camera.lines.slice(0,16))if(line&&['x1','y1','x2','y2'].every(key=>Number.isFinite(line[key])))lines.push(line);
    }
    for(const[id,marker]of existing)if(!retained.has(id))marker.remove();
    lines.forEach((line,index)=>{let element=frustums.children[index];if(!element){element=document.createElementNS('http://www.w3.org/2000/svg','line');frustums.append(element);}for(const key of ['x1','y1','x2','y2'])element.setAttribute(key,line[key]*100+'%');});
    while(frustums.children.length>lines.length)frustums.lastElementChild.remove();
  }
  function drawGizmos(data){
    drawSavedCameras(data.cameras);
    if(dragHandle)return;
    const path=$('path-layer'),gizmos=$('gizmo-layer');
    if(!$('show-path').checked||state.clean){path.replaceChildren();gizmos.replaceChildren();return;}
    const lines=Array.isArray(data.lines)?data.lines.filter(line=>line&&['x1','y1','x2','y2'].every(key=>Number.isFinite(line[key]))):[];
    lines.forEach((line,index)=>{
      let el=path.children[index];
      if(!el){el=document.createElementNS('http://www.w3.org/2000/svg','line');path.append(el);}
      for(const key of ['x1','y1','x2','y2'])el.setAttribute(key,line[key]*100+'%');
      el.classList.toggle('handle',line.handle===true);
    });
    while(path.children.length>lines.length)path.lastElementChild.remove();
    const existing=new Map([...gizmos.children].map(el=>[el.dataset.key,el])),retained=new Set();
    for(const point of Array.isArray(data.points)?data.points:[]){
      if(!point||typeof point.id!=='string'||!['node','in','out'].includes(point.kind)||!Number.isFinite(point.x)||!Number.isFinite(point.y))continue;
      const key=point.id+':'+point.kind;let b=existing.get(key);retained.add(key);
      if(!b){
        b=document.createElement('button');b.type='button';b.dataset.key=key;gizmos.append(b);
        b.onpointerdown=e=>{
          const point=b.cameraPoint;
          if(point.kind==='node'){selectFrame(point.id,e.shiftKey||e.ctrlKey);return;}
          e.preventDefault();b.setPointerCapture(e.pointerId);
          dragHandle={...point,startX:e.clientX,startY:e.clientY,dx:0,dy:0};movedHandle=false;b.classList.add('dragging');
        };
        b.onpointermove=e=>{
          if(!dragHandle)return;
          dragHandle.dx=M.clamp((e.clientX-dragHandle.startX)/innerWidth,-.25,.25);
          dragHandle.dy=M.clamp((e.clientY-dragHandle.startY)/innerHeight,-.25,.25);movedHandle=true;
          b.style.left=(dragHandle.x+dragHandle.dx)*100+'%';b.style.top=(dragHandle.y+dragHandle.dy)*100+'%';
        };
        const finish=()=>{
          if(!dragHandle)return;const gesture=dragHandle;dragHandle=null;
          if(movedHandle)send('dragHandle',{id:gesture.id,kind:gesture.kind,dx:gesture.dx,dy:gesture.dy});
          b.classList.remove('dragging');
        };
        b.onpointerup=finish;b.onlostpointercapture=finish;
        b.onpointercancel=()=>{dragHandle=null;movedHandle=false;b.classList.remove('dragging');};
      }
      b.cameraPoint=point;
      b.className='gizmo'+(point.kind==='node'?'':' handle')+(selected.has(point.id)?' selected':'');
      b.style.left=point.x*100+'%';b.style.top=point.y*100+'%';
      const label=point.kind==='node'?String(point.label??''):'';if(b.textContent!==label)b.textContent=label;
      b.setAttribute('aria-label',point.kind==='node'?'Select keyframe '+label:'Drag '+(point.kind==='in'?'incoming':'outgoing')+' tangent');
      b.title=point.kind==='node'?'Select keyframe':'Drag tangent';
    }
    for(const [key,el] of existing)if(!retained.has(key))el.remove();
  }
  window.addEventListener('message',event=>{
    const d=event.data;
    if(!isNui||!d||typeof d!=='object'||Array.isArray(d)||typeof d.type!=='string')return;
    try {
      if(d.type==='close'||d.type==='reset'){hideEditor();return;}
      if(d.type==='open'){
        // Validate before displaying anything: startup and malformed messages
        // always leave a completely transparent, hidden NUI.
        const scene=M.validate(d.scene),camera=cameraPose(d.camera);
        hideEditor();editor.apply(scene,false);editor.past=[];editor.future=[];
        acknowledgedScene=M.clone(scene);acknowledgedHistory={past:[],future:[]};
        acknowledgedServerRevision=Number.isSafeInteger(d.revision)?d.revision:-1;selected.clear();copied=[];
        latestStateSequence=Number.isSafeInteger(d.stateSequence)?d.stateSequence:-1;
        document.querySelectorAll('input[aria-invalid]').forEach(input=>markNumber(input,''));
        Object.assign(state,{open:true,camera,nativeFlightInput:d.capabilities?.nativeFlightInput===true,director:D.validate(d.director||scene.director||D.defaults())});workspace={cameras:[],presets:[],status:'loading'};receiveWorkspace(d.workspace||{});
        const settings=d.settings||{};
        receiveSettings(settings);
        if(Number.isFinite(settings.speed)){
          $('fly-speed').value=M.clamp(settings.speed,.1,100);
          $('fly-speed-output').textContent=Number(settings.speed).toFixed(1);$('fly-speed-value').value=String(settings.speed);
        }
        for(const [id,key] of [['show-path','showPath'],['show-cameras','showCameras'],['show-bars','letterbox'],['hide-hud','hideHud']]){
          $(id).checked=typeof settings[key]==='boolean'?settings[key]:['showPath','showCameras','hideHud'].includes(key);
        }
        if(!d.director&&!scene.director&&settings.letterbox===true)state.director.framing.ratio='2.39';renderFraming();
        $('save-status').textContent='Scene loaded in camera';
        render();$('editor').hidden=false;$('viewport').focus({preventScroll:true});return;
      }
      if(!state.open)return;
      if(d.type==='toggleClean'){clean();return;}
      if(d.type==='help'){showHelp();return;}
      if(d.type==='workspace'){receiveWorkspace(d.workspace||d);return;}
      if(d.type==='scene'){
        if(Number.isSafeInteger(d.revision)&&d.revision<acknowledgedServerRevision)return;
        const scene=M.validate(d.scene);acknowledgedScene=M.clone(scene);
        if(Number.isSafeInteger(d.revision))acknowledgedServerRevision=d.revision;
        if(!pendingScenes&&!directorPending){
          editor.apply(scene);if(!directorPending)state.director=D.validate(scene.director||D.defaults());if(d.selectedId){selected.clear();selected.add(d.selectedId);showInspectorTab('advanced');}
          acknowledgedHistory={past:M.clone(editor.past),future:M.clone(editor.future)};
          $('save-status').textContent='Unsaved changes';render();
        }
      }
      if(d.type==='state'){
        if(Number.isSafeInteger(d.stateSequence)){
          if(d.stateSequence<latestStateSequence)return;
          latestStateSequence=d.stateSequence;
        }
        if(d.camera!==undefined)state.camera=cameraPose(d.camera);if(d.director!==undefined&&!directorPending){state.director=D.validate(d.director);renderDirector();}
        receiveSettings(d.settings);
        for(const key of ['playing','recording','flight']){
          // An older periodic Lua state can arrive while the flight request is
          // queued. It must not release a newly acquired mouse lock and enqueue
          // a second request that immediately turns flight off again.
          if(key==='flight'&&pendingFlight!==null)continue;
          if(typeof d[key]==='boolean')state[key]=d[key];
        }
        if(Number.isFinite(d.time))state.time=M.clamp(d.time,0,3600);
        if(Number.isFinite(d.recordingDuration))state.recordingDuration=M.clamp(d.recordingDuration,0,3600);
        if(d.attachment!==undefined)state.attachment=!!d.attachment;
        renderState();if(!selected.size)renderInspector();
      }
      if(d.type==='toast'&&typeof d.message==='string'){
        toast(d.message,d.level);
        if(d.code==='scene_saved'||d.message==='Scene saved'){pendingSave=false;$('save-status').textContent='Saved on server';}
        if(d.message==='Earlier scene version saved; current changes are not saved'){pendingSave=false;$('save-status').textContent='Unsaved changes';}
        if(d.level==='error'&&pendingSave){pendingSave=false;$('save-status').textContent='Save failed — changes remain in memory';}
        if(d.level==='error'&&pendingLibrary){
          pendingLibrary=false;
          if($('modal').open&&$('modal-title').textContent==='Scene Library')$('modal-body').textContent=d.message;
        }
      }
      if(d.type==='library'&&(pendingLibrary||($('modal').open&&$('modal-title').textContent==='Scene Library'))){
        if(!Array.isArray(d.items))throw Error('Invalid scene library response.');
        showLibrary(d.items.filter(item=>item&&typeof item.name==='string'&&Number.isFinite(item.frames)&&Number.isFinite(item.duration)));
      }
      if(d.type==='gizmos')drawGizmos(d);
    }catch(error){
      if(d.type==='open'){hideEditor();send('close');}
      else toast('Scene rejected: '+error.message,'error');
    }
  });
  document.addEventListener('keydown',e=>{
    if(!state.open)return;if($('modal').open||infoTarget)return;
    if(state.flight&&state.nativeFlightInput)return;
    const field=e.target.closest('input,select,textarea,[contenteditable="true"]');if(field && e.code!=='Escape')return;
    if(e.code==='Tab'){
      // Forms and toolbar controls keep ordinary keyboard navigation. Click the
      // viewport or Flight button to use Tab as the camera control shortcut.
      if(!e.ctrlKey&&!e.metaKey&&!e.altKey&&(state.flight||(!e.shiftKey&&(e.target===$('viewport')||e.target===$('flight-button'))))){
        e.preventDefault();if(!e.repeat)setFlight(!state.flight);
      }
      return;
    }
    if(e.code==='Escape'){e.preventDefault();if(document.pointerLockElement){document.exitPointerLock();setFlight(false);}else close();return;}
    if(state.flight){if(['KeyW','KeyA','KeyS','KeyD','KeyQ','KeyE','ShiftLeft','ShiftRight','ControlLeft','ControlRight','AltLeft','AltRight'].includes(e.code)){e.preventDefault();keys.add(e.code);return;}}
    if(e.repeat)return;
    if(['Space','Enter'].includes(e.code)&&e.target.closest('button,summary'))return;
    if(!state.flight&&(e.ctrlKey||e.metaKey)){
      const map={KeyZ:()=>history(e.shiftKey),KeyY:()=>history(true),KeyC:copy,KeyV:paste,KeyA:()=>{editor.scene.frames.forEach(f=>selected.add(f.id));render();},KeyS:nameDialog,KeyN:fileActions.new};if(map[e.code]){e.preventDefault();map[e.code]();return;}
    }
    if(e.ctrlKey||e.metaKey||e.altKey||e.shiftKey)return;
    const map={KeyF:()=>send('capture'),KeyG:()=>send('toggleGrid'),KeyH:clean,KeyJ:()=>send('cycleStabilization'),KeyR:()=>send('record',{enabled:!state.recording}),F1:showHelp,Space:()=>send(state.playing?'pause':'play'),Delete:remove,ArrowLeft:()=>step(-1),ArrowRight:()=>step(1)};if(map[e.code]){e.preventDefault();map[e.code]();}
  });
  document.addEventListener('keyup',e=>keys.delete(e.code));window.addEventListener('blur',releaseKeys);document.addEventListener('visibilitychange',()=>{if(document.hidden)releaseKeys();});
  document.addEventListener('pointerlockchange',()=>{const wasLocked=pointerLocked;pointerLocked=!!document.pointerLockElement;if(wasLocked&&!pointerLocked&&state.open&&state.flight)setFlight(false);});
  document.addEventListener('pointerlockerror',pointerLockFallback);
  $('viewport').addEventListener('pointerdown',e=>{if(e.target===$('viewport'))$('viewport').focus({preventScroll:true});});
  $('viewport').addEventListener('contextmenu',e=>e.preventDefault());
  document.addEventListener('mousemove',e=>{if(state.open&&state.flight&&!state.nativeFlightInput&&(document.pointerLockElement||(e.buttons&2))){dx+=Number.isFinite(e.movementX)?e.movementX:0;dy+=Number.isFinite(e.movementY)?e.movementY:0;}});
  setInterval(()=>{
    if(state.open&&state.flight&&!state.nativeFlightInput&&!inputPending){
      inputPending=true;const requestSession=session;
      send('input',{keys:[...keys],dx,dy}).finally(()=>{if(requestSession===session)inputPending=false;});dx=dy=0;
    }
  },33);
  window.addEventListener('pagehide',hideEditor);
  if(isNui) send('ready');
})();
