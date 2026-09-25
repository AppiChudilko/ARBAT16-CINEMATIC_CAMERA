(function (root, factory) {
  const api = factory(typeof module === 'object' && module.exports ? require('./director.js') : root.CameraDirector);
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.CameraModel = api;
})(typeof globalThis === 'object' ? globalThis : this, function (Director) {
  'use strict';
  const clone = value => JSON.parse(JSON.stringify(value));
  const clamp = (n, min, max) => Math.min(max, Math.max(min, n));
  const empty = () => ({version: 1, name: 'Untitled Scene', frames: [], loop: false, speed: 1});
  const duration = scene => scene.frames.reduce((n, f) => n + f.duration, 0);
  const MAX_TAKE_SAMPLES = 9001, MAX_SCENE_SAMPLES = 18002;
  const MAX_HISTORY_BYTES = 16 * 1024 * 1024, MAX_HISTORY_STATES = 50;
  const utf8Bytes = value => new TextEncoder().encode(value).byteLength;
  const starts = scene => { let t = 0; return scene.frames.map(f => {const start = t; t += f.duration; return start;}); };
  let sequence = 0;
  const uid = () => 'k' + Date.now().toString(36) + '_' + (++sequence).toString(36);
  const timecode = (s, fps = 30) => {
    s = Math.max(0, s || 0); const ticks = Math.floor(s * fps + 0.00001);
    return [Math.floor(ticks / fps / 60), Math.floor(ticks / fps) % 60, ticks % fps].map(v => String(v).padStart(2, '0')).join(':');
  };
  function validate(scene) {
    const object = (value, allowed, label) => {
      if (!value || typeof value !== 'object' || Array.isArray(value) ||
          ![Object.prototype, null].includes(Object.getPrototypeOf(value)) ||
          Object.keys(value).some(key => !allowed.includes(key))) throw Error('Invalid fields: ' + label + '.');
    };
    const number = (value, fallback, min, max, label, integer = false) => {
      if (value === undefined) value = fallback;
      if (!Number.isFinite(value) || value < min || value > max || (integer && !Number.isInteger(value))) throw Error('Invalid value: ' + label + '.');
      return value;
    };
    const text = (value, fallback, limit, label, pattern) => {
      if (value === undefined) value = fallback;
      if (typeof value !== 'string' || !value.length || new TextEncoder().encode(value).length > limit ||
          /[\x00-\x1f\x7f]/.test(value) || (pattern && !pattern.test(value))) throw Error('Invalid value: ' + label + '.');
      return value;
    };
    const vector = (value, limit, label) => {
      object(value, ['x', 'y', 'z'], label);
      return Object.fromEntries(['x', 'y', 'z'].map(axis => [axis, number(value[axis], undefined, -limit, limit, label + '.' + axis)]));
    };
    const array = (value,min,max,label) => {
      if (!Array.isArray(value) || value.length < min || value.length > max ||
          Object.keys(value).length !== value.length ||
          Object.keys(value).some(key => !/^(0|[1-9]\d*)$/.test(key) || Number(key) >= value.length)) throw Error('Invalid recording array: '+label+'.');
      return value;
    };
    const take = raw => {
      object(raw,['duration','samples'],'recording');
      const seconds=number(raw.duration,undefined,0,300,'recording duration');
      if (seconds<=0) throw Error('Recording duration must be positive.');
      array(raw.samples,2,MAX_TAKE_SAMPLES,'samples');
      const ranges=[[0,seconds+.0001],[-100000,100000],[-100000,100000],[-100000,100000],
        [-360000,360000],[-360000,360000],[-360000,360000],[1,130],[.01,100000],[0,23,true],[0,59,true]];
      let previous=-1;
      const samples=raw.samples.map((sample,index) => {
        array(sample,12,12,'sample');
        const point=ranges.map(([min,max,integer],column) => number(sample[column],undefined,min,max,'recording sample '+index+' column '+column,integer));
        point.push(text(sample[11],undefined,32,'recording weather',/^[A-Za-z0-9_]+$/).toUpperCase());
        if ((index===0 && point[0]!==0) || point[0]<=previous) throw Error('Recording timestamps must start at zero and increase strictly.');
        if (index<raw.samples.length-1 && point[0]>=seconds) throw Error('Recording timestamp exceeds clip duration.');
        previous=point[0];return point;
      });
      if (Math.abs(samples.at(-1)[0]-seconds)>.0001) throw Error('Final recording timestamp must match its duration.');
      samples.at(-1)[0]=seconds;
      return {duration:seconds,samples};
    };
    object(scene, ['version', 'name', 'frames', 'loop', 'speed', 'director'], 'scene');
    if ((scene.version !== undefined && scene.version !== 1) || !Array.isArray(scene.frames) || scene.frames.length > 200 ||
        Object.keys(scene.frames).some(key => !/^(0|[1-9]\d*)$/.test(key) || Number(key) >= scene.frames.length)) throw Error('Invalid scene format or more than 200 keyframes.');
    if (scene.loop !== undefined && typeof scene.loop !== 'boolean') throw Error('Loop must be a boolean.');
    // Names are deliberately narrower than the Lua core to match server storage.
    const out = {version: 1, name: text(scene.name, 'Untitled', 64, 'name (1–64 bytes)'),
      frames: [], loop: scene.loop === true, speed: number(scene.speed, 1, .1, 8, 'speed (0.1–8×)')};
    out.name = out.name.replace(/^ +| +$/g, '');
    if (!out.name || out.name === '.' || out.name === '..' || /[\x7f-\x9f/\\]/.test(out.name)) throw Error('Invalid scene name.');
    if (scene.director !== undefined) {
      if (!Director) throw Error('Director module is not loaded.');
      out.director = Director.validate(scene.director);
    }
    const ids = new Set();let totalSamples=0;
    for (const [index, input] of scene.frames.entries()) {
      object(input, ['id', 'label', 'pos', 'rot', 'fov', 'duration', 'easing', 'transition', 'weather',
        'hour', 'minute', 'dof', 'handleIn', 'handleOut', 'take'], 'keyframe ' + (index + 1));
      const f = {
        id: text(input.id, 'frame_' + (index + 1), 64, 'keyframe ID', /^[A-Za-z0-9_:\-]+$/),
        label: text(input.label, 'Camera ' + (index + 1), 160, 'keyframe label'),
        pos: vector(input.pos, 100000, 'position'), rot: vector(input.rot, 360000, 'rotation'),
        fov: number(input.fov, 50, 1, 130, 'FOV'), duration: number(input.duration, 3, 0, 600, 'duration'),
        easing: input.easing === undefined ? 'smooth' : input.easing,
        transition: input.transition === undefined ? (input.take === undefined ? 'smooth' : 'hold') : input.transition,
        weather: text(input.weather, 'SUNNY', 32, 'weather', /^[A-Za-z0-9_]+$/).toUpperCase(),
        hour: number(input.hour, 12, 0, 23, 'hour', true), minute: number(input.minute, 0, 0, 59, 'minute', true)
      };
      if (ids.has(f.id)) throw Error('Duplicate keyframe IDs.');
      ids.add(f.id);
      if (!['smooth','linear','cut','hold'].includes(f.transition) || !['linear','smooth','easeIn','easeOut','easeInOut','smoother'].includes(f.easing)) throw Error('Unknown transition or easing.');
      if (f.duration === 0 && index < scene.frames.length - 1 && f.transition !== 'cut') throw Error('Zero duration is only allowed for cuts or the final keyframe.');
      const dof = input.dof === undefined ? {} : input.dof;
      object(dof, ['enabled', 'focus', 'near', 'far', 'strength'], 'depth of field');
      if (dof.enabled !== undefined && typeof dof.enabled !== 'boolean') throw Error('DOF enabled must be a boolean.');
      f.dof = {enabled: dof.enabled === true, focus: number(dof.focus, 10, .01, 100000, 'focus'),
        near: number(dof.near, 1, 0, 100000, 'near distance'), far: number(dof.far, 100, .01, 100000, 'far distance'),
        strength: number(dof.strength, .5, 0, 1, 'DOF strength')};
      if (f.dof.near > f.dof.far) throw Error('DOF near distance cannot exceed far distance.');
      for (const key of ['handleIn', 'handleOut']) if (input[key] !== undefined) f[key] = vector(input[key], 100000, 'tangent');
      if (input.take!==undefined) {
        if (f.duration<=0) throw Error('Recorded clips must have positive timeline duration.');
        f.take=take(input.take);totalSamples+=f.take.samples.length;
        if (totalSamples>MAX_SCENE_SAMPLES) throw Error('Maximum recorded samples per scene exceeded.');
        const start=f.take.samples[0];
        f.pos={x:start[1],y:start[2],z:start[3]};f.rot={x:start[4],y:start[5],z:start[6]};
        f.fov=start[7];f.dof.focus=start[8];f.hour=start[9];f.minute=start[10];f.weather=start[11];
      }
      out.frames.push(f);
    }
    if (duration(out) > 3600) throw Error('Maximum scene duration is 60 minutes.');
    return out;
  }
  class Editor {
    constructor(scene = empty()) { this.scene = validate(scene); this.past = []; this.future = []; this._historySizes = new WeakMap(); }
    _snapshotBytes(scene) {
      if (!this._historySizes.has(scene)) this._historySizes.set(scene,utf8Bytes(JSON.stringify(scene)));
      return this._historySizes.get(scene);
    }
    historyBytes() { return [...this.past,...this.future].reduce((total,scene)=>total+this._snapshotBytes(scene),0); }
    trimHistory() {
      let bytes=this.historyBytes();
      while (bytes>MAX_HISTORY_BYTES || this.past.length+this.future.length>MAX_HISTORY_STATES) {
        // Index zero is farthest from the current edit in both stacks. Keep the
        // nearest undo even if an externally supplied oversized scene exceeds
        // the estimate; supported 4 MiB scenes always fit the 16 MiB budget.
        let removed;
        if (this.past.length>1 && (this.past.length>=this.future.length || !this.future.length)) removed=this.past.shift();
        else if (this.future.length) removed=this.future.shift();
        else break;
        bytes-=this._snapshotBytes(removed);
      }
      return bytes;
    }
    apply(scene, remember = true) {
      const next = validate(scene);
      const nextJson=JSON.stringify(next),currentJson=JSON.stringify(this.scene);
      if (nextJson === currentJson) return false;
      // A drag streams intermediate scenes without history; its caller commits
      // the pre-drag snapshot once when the gesture finishes.
      if (remember) {
        const previous=JSON.parse(currentJson);this._historySizes.set(previous,utf8Bytes(currentJson));
        this.past.push(previous);this.future = [];
      }
      this._historySizes.set(next,utf8Bytes(nextJson));
      this.scene = next;this.trimHistory();return true;
    }
    edit(fn) { const next = clone(this.scene); fn(next); return this.apply(next); }
    undo() { if (!this.past.length) return false; this.future.push(this.scene); this.scene = this.past.pop();this.trimHistory();return true; }
    redo() { if (!this.future.length) return false; this.past.push(this.scene); this.scene = this.future.pop();this.trimHistory();return true; }
    reorder(id, targetId) {
      return this.edit(s => { const from = s.frames.findIndex(f => f.id === id); if (from < 0 || id === targetId) return; const [f] = s.frames.splice(from, 1); const target = s.frames.findIndex(f => f.id === targetId); s.frames.splice(target < 0 ? s.frames.length : target, 0, f); });
    }
    remove(ids) { return this.edit(s => { s.frames = s.frames.filter(f => !ids.has(f.id)); }); }
    paste(frames, afterId) {
      if (!Array.isArray(frames)) throw Error('Keyframe clipboard must be an array.');
      const used = new Set(this.scene.frames.map(f => f.id));
      const copies = clone(frames).map(f => {
        let id; do { id = uid(); } while (used.has(id)); used.add(id);
        return {...f, id};
      });
      this.edit(s => { const at = s.frames.findIndex(f => f.id === afterId); s.frames.splice(at < 0 ? s.frames.length : at + 1, 0, ...copies); });
      return copies.map(f => f.id);
    }
  }
  return {clone, clamp, empty, duration, starts, uid, timecode, validate, Editor, MAX_TAKE_SAMPLES, MAX_SCENE_SAMPLES, MAX_HISTORY_BYTES, MAX_HISTORY_STATES};
});
