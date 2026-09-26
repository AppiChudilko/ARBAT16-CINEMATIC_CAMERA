(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.CameraDirector = api;
})(typeof globalThis === 'object' ? globalThis : this, function () {
  'use strict';
  const catalogs = {gta5:[
    {id:'none',label:'Original'}, {id:'monochrome',label:'Black & White'}, {id:'player_camera',label:'Photo Camera'},
    {id:'cinematic',label:'Cinema'}, {id:'flat',label:'Neutral'},
    {id:'dusk',label:'Warm Tone'}, {id:'frontier',label:'Urban Contrast'}, {id:'dream',label:'Soft Focus'}
  ],rdr3:[
    {id:'none',label:'Original'}, {id:'monochrome',label:'Black & White'}, {id:'player_camera',label:'Photo Camera'},
    {id:'cinematic',label:'Cinematic Exposure'}, {id:'flat',label:'Flat Profile'},
    {id:'dusk',label:'Frontier Dusk'}, {id:'frontier',label:'Frontier Trailer'}, {id:'dream',label:'Deer Dream'}
  ]};
  let game='rdr3';
  const filters=[],presets=[];
  const ratios = ['native','2.39','2.35','1.85','16:9','4:3','1:1'];
  const defaults = () => ({look:{filter:'none',strength:.6},framing:{ratio:'native',opacity:1},
    motion:{type:'none',amplitude:.15,frequency:.2,roll:.25}});
  function validate(raw) {
    const object = (value, fields, label) => {
      if (!value || typeof value !== 'object' || Array.isArray(value) ||
          ![Object.prototype,null].includes(Object.getPrototypeOf(value)) || Object.keys(value).some(key => !fields.includes(key))) {
        throw Error('Invalid director fields: '+label+'.');
      }
    };
    object(raw,['look','framing','motion'],'director');
    const out = defaults();
    const groups = {look:['filter','strength'],framing:['ratio','opacity'],motion:['type','amplitude','frequency','roll']};
    for (const [group,fields] of Object.entries(groups)) if (raw[group] !== undefined) {
      object(raw[group],fields,group); Object.assign(out[group],raw[group]);
    }
    if (!filters.some(item => item.id === out.look.filter)) throw Error('Unknown camera filter.');
    if (!ratios.includes(out.framing.ratio)) throw Error('Unknown frame ratio.');
    if (!['none','sway','handheld'].includes(out.motion.type)) throw Error('Unknown camera motion.');
    for (const [group,key,max] of [['look','strength',1],['framing','opacity',1],['motion','amplitude',2],['motion','frequency',3],['motion','roll',5]]) {
      if (!Number.isFinite(out[group][key]) || out[group][key] < 0 || out[group][key] > max) throw Error('Invalid director value: '+group+'.'+key+'.');
    }
    return out;
  }
  const preset = (id,name,filter,strength,ratio,fov,focus,motion) => {
    const director = defaults(); director.look = {filter,strength}; director.framing.ratio=ratio;
    if (motion) director.motion=motion;
    return {id,name,director,fov,focus};
  };
  const makePresets = () => [
    preset('natural','Natural','none',.6,'native',50,10),
    preset('western_scope',game==='gta5'?'Cinema Scope':'Western Scope','cinematic',.65,'2.39',45,25),
    preset('frontier',game==='gta5'?'Urban':'Frontier','frontier',.45,'2.35',52,30),
    preset('quiet_portrait','Quiet Portrait','player_camera',.5,'4:3',30,4),
    preset('handheld','Handheld','flat',.3,'1.85',55,10,{type:'handheld',amplitude:.045,frequency:.6,roll:.3}),
    preset('dream_sequence','Dream Sequence','dream',.5,'2.39',40,20,{type:'sway',amplitude:.12,frequency:.12,roll:.2})
  ];
  function setGame(value) {
    const aliases={gta5:'gta5',fivem:'gta5',rdr3:'rdr3',redm:'rdr3'};
    const normalized=typeof value==='string'&&Object.prototype.hasOwnProperty.call(aliases,value)?aliases[value]:null;
    if(!normalized)throw Error('Unsupported camera game.');
    game=normalized;
    // Keep array references valid for controls that read the packaged catalog.
    filters.splice(0,filters.length,...catalogs[game].map(item=>({...item})));
    presets.splice(0,presets.length,...makePresets());
    return game;
  }
  setGame('rdr3');
  return {defaults,validate,filters,presets,ratios,setGame,get game(){return game;}};
});
