// Procedural audio engine (WebAudio). Every sound is synthesised: one-shots and loops are pre-rendered with an
// OfflineAudioContext (kit.js + sfx.js) so playback is a single buffer source; music is a step sequencer over
// rendered instrument samples (music.js). See README.md for the API.
//
//   voice -> gain -> pan -> world bus -> slow-mo low-pass -\
//                        -> ui bus ------------------------+-> sfx -> master -> glue comp -> limiter -> clipper -> out
//                        -> reverb send -> stone-hall convolver -> return -/
//   music tracks -> layer gains -> fade -> muffle / low-pass -> music -> low shelf -> duck -/
//
// Silent and exception-free when WebAudio is missing, before unlock() and in test mode (#test): play() returns null,
// loop() returns an inert handle. Offline rendering (render / renderScene) works in test mode for measurements.

import * as THREE from 'three';
import { makeRng, clamp } from '../core/math.js';
import { audioClasses, renderSound, renderOffline, hallIR, softClipCurve, releaseScratch } from './kit.js';
import { SOUNDS, ALIASES, defineSound } from './sfx.js';
import { INSTRUMENTS, TRACKS, createSequencer, midiHz } from './music.js';

/** Per quality tier: voice cap, reverb length (s), render sample rate (Hz), max variants per sound, mono assets. */
const TIERS = {
  low: { voices: 20, ir: 2.0, rate: 32000, variants: 2, mono: true },
  mid: { voices: 28, ir: 2.6, rate: 40000, variants: 3, mono: false },
  high: { voices: 40, ir: 3.2, rate: 48000, variants: 4, mono: false },
};
const MASTER_TRIM = 1.0;    // single hits pass the glue untouched; stacks get glued, then limited and soft-clipped
const MUSIC_TRIM = 0.3;     // music sits ~5 dB under heavy hits at default volumes (measured: analyze.js "as heard")
const VERB_RETURN = 0.3;
const LOOKAHEAD = 0.3;      // music scheduling horizon (s)
const SLOWMO_PITCH = 0.35;  // world one-shots play at rate * timeScale^this during slow motion
/** pre-render order: what is needed first (UI, title music, core combat) comes first */
const PRIORITY = ['ui_move', 'ui_select', 'ui_back', '@title', 'step', 'swing_light', 'swing_heavy', 'hit_slash_light', 'hit_slash_heavy', 'guard',
  'dodge', 'land', 'hit_blunt', 'swing_huge', 'hit_crit', 'guard_break', 'body_fall', 'announce_round', 'announce_fight', 'announce_ko', 'bell', '@battle'];

function buildGraph(ac, { ir, vol }) {
  const G = (v = 1) => { const g = ac.createGain(); g.gain.value = v; return g; };
  const nyq = ac.sampleRate / 2;
  const g = { ac };
  g.master = G(vol.master * MASTER_TRIM);
  const glue = ac.createDynamicsCompressor();
  glue.threshold.value = -6; glue.knee.value = 6; glue.ratio.value = 1.6; glue.attack.value = 0.015; glue.release.value = 0.25;
  const lim = ac.createDynamicsCompressor();
  lim.threshold.value = -2; lim.knee.value = 0; lim.ratio.value = 20; lim.attack.value = 0.001; lim.release.value = 0.08;
  const clip = ac.createWaveShaper();
  clip.curve = softClipCurve();
  g.master.connect(glue); glue.connect(lim); lim.connect(clip); clip.connect(ac.destination);
  g.sfx = G(vol.sfx); g.sfx.connect(g.master);
  g.slow = ac.createBiquadFilter();
  g.slow.type = 'lowpass'; g.slow.frequency.value = nyq; g.slow.Q.value = -3;
  g.world = G(); g.world.connect(g.slow); g.slow.connect(g.sfx);
  g.ui = G(); g.ui.connect(g.sfx);
  // music: a low shelf carves room under the music for the SFX sub drops, then the duck
  g.music = G(vol.music * MUSIC_TRIM); g.duck = G();
  const shelf = ac.createBiquadFilter();
  shelf.type = 'lowshelf'; shelf.frequency.value = 140; shelf.gain.value = -4;
  g.music.connect(shelf); shelf.connect(g.duck); g.duck.connect(g.master);
  g.verbIn = G();
  const conv = ac.createConvolver();
  conv.buffer = hallIR(ac, { seconds: ir });
  g.verbOut = G(VERB_RETURN);
  g.verbIn.connect(conv); conv.connect(g.verbOut); g.verbOut.connect(g.master);
  return g;
}

/** Start one buffer voice on a graph (live or offline). p = { rate, gain, pan, verb, loop } */
function startVoice(g, def, buffer, p, when) {
  const a = g.ac;
  const src = a.createBufferSource();
  src.buffer = buffer;
  src.playbackRate.value = p.rate;
  src.loop = !!p.loop;
  const gain = a.createGain();
  const dur = buffer.duration / p.rate;
  if (def.loop === true && !p.loop) {
    // a seamless loop asset played once: fade its open edges
    gain.gain.value = 0;
    gain.gain.setValueAtTime(0, when);
    gain.gain.linearRampToValueAtTime(p.gain, when + 0.12);
    gain.gain.setValueAtTime(p.gain, when + dur - 0.4);
    gain.gain.linearRampToValueAtTime(0, when + dur);
  } else gain.gain.value = p.gain;
  src.connect(gain);
  let tail = gain, panner = null;
  if (a.createStereoPanner) { panner = a.createStereoPanner(); panner.pan.value = p.pan; gain.connect(panner); tail = panner; }
  tail.connect(def.bus === 'ui' ? g.ui : g.world);
  let send = null;
  if (p.verb > 0) { send = a.createGain(); send.gain.value = p.verb; tail.connect(send); send.connect(g.verbIn); }
  src.start(when);
  return { src, gain, panner, tail, send, when, name: def.name, prio: def.prio, dead: false };
}

/**
 * Create the audio engine and store it on ctx.audio.
 * @param {object} ctx  app context (uses ctx.test, ctx.quality.tier, ctx.time, ctx.camera, ctx.onUpdate when present)
 */
export function createAudio(ctx = {}) {
  const tier = TIERS[(ctx.quality && ctx.quality.tier) || 'high'] || TIERS.high;
  const test = !!ctx.test;
  const cls = audioClasses();
  const canRender = !!cls.OAC;
  const canPlay = !!cls.AC && canRender && !test;
  const rng = makeRng((0xa0d10 ^ (Number(ctx.flags && ctx.flags.seed) || 0)) >>> 0);
  const vol = { master: 1, sfx: 1, music: 0.8 };
  const store = new Map(), queue = [];
  const voices = [], loops = new Set(), lastPlay = new Map(), lastVar = new Map(), ducks = [], warned = new Set();
  const mus = { base: null, over: null }, req = { base: null, over: false };
  let ac = null, g = null, resuming = false, disposed = false, pumping = false, timer = 0;
  let slow = 1, duckLevel = 1, intensity = 0.5;
  const v3 = new THREE.Vector3();

  const warn = (msg) => { if (!warned.has(msg)) { warned.add(msg); console.warn('[audio] ' + msg); } };
  const resolve = (name) => {
    const d = SOUNDS[ALIASES[name] || name];
    if (!d && name != null) warn('unknown sound: ' + name);
    return d || null;
  };
  const live = () => !!ac && !disposed && (ac.state === 'running' || resuming);

  // ---- render queue (one offline render at a time, yielding between renders) ----
  function request(key, make, urgent) {
    let e = store.get(key);
    if (!e) {
      e = { key, make, result: null, done: false };
      e.promise = new Promise((r) => { e.resolve = r; });
      store.set(key, e);
      queue.push(e);
    }
    if (!e.done) {
      if (urgent) { const i = queue.indexOf(e); if (i > 0) { queue.splice(i, 1); queue.unshift(e); } }
      pump();
    }
    return e;
  }
  async function pump() {
    if (pumping || disposed) return;
    pumping = true;
    while (queue.length && !disposed) {
      const e = queue.shift();
      try { e.result = await e.make(); } catch (err) { e.result = null; warn('render failed: ' + e.key + ' ' + err); }
      e.done = true;
      e.resolve(e.result);
      await new Promise((r) => setTimeout(r, 0));
    }
    pumping = false;
    if (!queue.length) releaseScratch();
  }
  const sfxEntry = (name, v, urgent) => request(name + '#' + v, () => renderSound(SOUNDS[name], { sr: tier.rate, variant: v, mono: tier.mono }), urgent);
  const instEntry = (inst, root) => {
    const d = INSTRUMENTS[inst];
    return request('@' + inst + ':' + root, () => renderSound({ ...d, name: inst + root, clip: 1 }, { sr: Math.min(tier.rate, d.rate || tier.rate), arg: midiHz(root), mono: tier.mono }));
  };
  const bank = {
    pick(inst, midi) {
      const d = INSTRUMENTS[inst];
      let best = null;
      for (const r of d.roots) {
        const e = store.get('@' + inst + ':' + r);
        if (e && e.done && e.result && (!best || Math.abs(midi - r) < Math.abs(midi - best.root))) best = { root: r, buffer: e.result.buffer, loop: d.loop || null, rel: d.rel ?? 0.3 };
      }
      return best;
    },
    duration(inst) { const s = bank.pick(inst, 60); return s ? s.buffer.duration : 1; },
    ensure(names) { return Promise.all(names.flatMap((n) => INSTRUMENTS[n].roots.map((r) => instEntry(n, r).promise))); },
  };

  // ---- voices ----
  function stopVoice(v, fade = 0.04) {
    if (v.dead || !v.src) return;
    v.dead = true;
    const t = v.src.context.currentTime;
    try {
      v.gain.gain.cancelScheduledValues(t);
      v.gain.gain.setValueAtTime(v.gain.gain.value, t);
      v.gain.gain.linearRampToValueAtTime(0, t + fade);
      v.src.stop(Math.max(t + fade + 0.01, v.when));
    } catch (e) { /* already stopped */ }
  }
  function release(v) {
    v.dead = true;
    const i = voices.indexOf(v);
    if (i >= 0) voices.splice(i, 1);
    try { v.tail.disconnect(); v.gain.disconnect(); if (v.send) v.send.disconnect(); } catch (e) { /* already gone */ }
  }
  function admit(def) {
    let same = 0, oldest = null, alive = 0, victim = null;
    for (const v of voices) {
      if (v.dead) continue;
      alive++;
      if (v.name === def.name) { same++; if (!oldest || v.when < oldest.when) oldest = v; }
      if (!victim || v.prio < victim.prio || (v.prio === victim.prio && v.when < victim.when)) victim = v;
    }
    if (same >= def.poly && oldest) { stopVoice(oldest, 0.03); alive--; if (victim === oldest) victim = null; }
    if (alive >= tier.voices) {
      if (victim && victim.prio <= def.prio) stopVoice(victim, 0.03); else return false;
    }
    return true;
  }
  function panOf(pos) {
    const cam = ctx.camera;
    if (!cam || !pos) return 0;
    if (Array.isArray(pos)) v3.set(pos[0], pos[1], pos[2]); else v3.copy(pos);
    v3.project(cam);
    return Number.isFinite(v3.x) ? clamp(v3.x * 0.75, -0.85, 0.85) : 0;
  }
  function voiceParams(def, o, when) {
    let rate = (o.pitch ?? 1) * Math.pow(2, ((rng() * 2 - 1) * def.pitchVar) / 12);
    if (def.bus === 'world' && !o.noSlowmo) rate *= Math.pow(clamp(slow, 0.25, 1), SLOWMO_PITCH);
    let gain = (o.volume ?? 1) * Math.pow(10, ((rng() * 2 - 1) * def.volVar) / 20);
    let stacked = 0;
    for (const v of voices) if (!v.dead && v.name === def.name && Math.abs(v.when - when) < 0.12) stacked++;
    gain /= 1 + 0.35 * stacked;  // simultaneous copies of one sound do not sum to a spike
    const pan = clamp((o.pan ?? (o.pos ? panOf(o.pos) : 0)) + (rng() * 2 - 1) * def.panVar, -1, 1);
    return { rate, gain, pan, verb: def.verb * (o.reverb ?? 1) };
  }
  function pickVariant(def) {
    const n = Math.min(def.variants, tier.variants);
    if (n <= 1) return 0;
    let v = Math.floor(rng() * n);
    if (v === lastVar.get(def.name)) v = (v + 1) % n;
    lastVar.set(def.name, v);
    return v;
  }

  // ---- loops ----
  function rampParam(param, v, fade) {
    const now = ac.currentTime;
    param.cancelScheduledValues(now);
    param.setValueAtTime(param.value, now);
    param.linearRampToValueAtTime(v, now + Math.max(0.01, fade));
  }
  function startLoop(h) {
    if (h.voice || h.starting || h.stopped) return;
    h.starting = true;
    sfxEntry(h.def.name, 0, true).promise.then((r) => {
      h.starting = false;
      if (!r || h.stopped || !live()) return;
      h.voice = startVoice(g, h.def, r.buffer, { rate: h.pitch, gain: 0, pan: h.pan, verb: h.def.verb, loop: true }, ac.currentTime);
      rampParam(h.voice.gain.gain, h.volume, h.fadeIn);
    });
  }

  // ---- music ----
  function tickMusic() {
    if (!live()) return;
    const until = ac.currentTime + LOOKAHEAD;
    for (const tr of [mus.base, mus.over]) if (tr && tr.seq && !tr.seq.ended) tr.seq.tick(until);
  }
  function startTrack(name, fade, alignTo) {
    const tr = { name, seq: null, stopped: false, muffled: false };
    const def = TRACKS[name];
    bank.ensure(def.instruments).then(() => {
      if (tr.stopped || !live()) return;
      const now = ac.currentTime + 0.06;
      const ref = alignTo && alignTo.seq;
      tr.seq = createSequencer(ac, bank, name, { dest: g.music, verb: g.verbIn, t0: ref && !ref.ended ? ref.nextBeat(now) : now, intensity, fadeIn: def.fadeIn ?? fade });
      if (tr.muffled) tr.seq.muffle(true, 0.05);
      tickMusic();
    });
    return tr;
  }
  function endTrack(tr, fade) {
    tr.stopped = true;
    if (!tr.seq) return;
    const seq = tr.seq;
    seq.stop(fade);
    setTimeout(() => seq.disconnect(), (fade + 0.6) * 1000);
  }
  function muffleBase(on, dur) {
    if (!mus.base) return;
    mus.base.muffled = on;
    if (mus.base.seq) mus.base.seq.muffle(on, dur);
  }
  function applyMusic(fade) {
    if (req.base !== (mus.base ? mus.base.name : null)) {
      if (mus.base) endTrack(mus.base, fade);
      mus.base = req.base ? startTrack(req.base, fade, null) : null;
      if (mus.over) muffleBase(true, 0.05);
    }
    if (req.over && !mus.over) { mus.over = startTrack('ultimate', Math.min(fade, 0.6), mus.base); muffleBase(true, 0.5); }
    else if (!req.over && mus.over) { endTrack(mus.over, fade); mus.over = null; muffleBase(false, fade); }
  }

  // ---- ducking / slow motion ----
  function applyDuck() {
    if (!g) return;
    const now = ac.currentTime;
    let a = 0;
    for (let i = ducks.length - 1; i >= 0; i--) {
      if (ducks[i].until <= now) ducks.splice(i, 1);
      else if (ducks[i].from <= now) a = Math.max(a, ducks[i].amount);
    }
    const target = 1 - a;
    if (Math.abs(target - duckLevel) > 0.005) {
      g.duck.gain.setTargetAtTime(target, now, target < duckLevel ? 0.04 : 0.3);
      duckLevel = target;
    }
  }
  function applySlow() {
    const now = ac.currentTime, nyq = ac.sampleRate / 2;
    g.slow.frequency.setTargetAtTime(slow >= 0.98 ? nyq : clamp(18000 * Math.pow(slow, 1.3), 900, nyq), now, 0.06);
    g.verbOut.gain.setTargetAtTime(VERB_RETURN * (1 + 0.7 * (1 - slow)), now, 0.12);
  }
  function update() {
    if (!g || disposed) return;
    const tm = ctx.time;
    if (tm) {
      const s = tm.inHitstop ? slow : clamp(tm.scale, 0, 1);
      if (Math.abs(s - slow) > 0.01) { slow = s; applySlow(); }
    }
    applyDuck();
    tickMusic();
  }

  // ---- context lifecycle ----
  function onState() {
    if (!ac) return;
    if (ac.state === 'running') {
      resuming = false;
      const stale = ac.currentTime - 0.25;
      for (const v of voices) if (v.when < stale && !v.src.loop) stopVoice(v, 0.02);
      startPending();
    }
  }
  function startPending() {
    if (!live()) return;
    applyMusic(1.0);
    for (const h of loops) startLoop(h);
  }
  const onGesture = () => { if (!disposed && (!ac || ac.state !== 'running')) audio.unlock(); };
  const onVisibility = () => {
    if (!ac || disposed) return;
    if (document.hidden) ac.suspend().catch(() => {});
    else if (resuming || ac.state === 'suspended') ac.resume().then(onState, () => {});
  };
  const GESTURES = ['pointerdown', 'keydown', 'touchend'];
  if (canPlay && typeof window !== 'undefined') {
    for (const e of GESTURES) window.addEventListener(e, onGesture, { capture: true, passive: true });
    if (typeof document !== 'undefined') document.addEventListener('visibilitychange', onVisibility);
  }

  const audio = {
    /** 'unavailable' | 'test' | 'locked' | 'starting' | 'running' | 'suspended' | 'disposed' */
    get state() {
      if (disposed) return 'disposed';
      if (test) return 'test';
      if (!canPlay) return 'unavailable';
      if (!ac) return 'locked';
      return ac.state === 'running' ? 'running' : resuming ? 'starting' : 'suspended';
    },
    /** The live AudioContext (null until unlocked). */
    get context() { return ac; },
    /** Current music intensity 0..1. */
    get intensity() { return intensity; },

    /** Create / resume the AudioContext. Call from a user gesture (also hooked automatically). Returns success. */
    unlock() {
      if (!canPlay || disposed) return false;
      try {
        if (!ac) {
          try { ac = new cls.AC({ latencyHint: 'interactive' }); } catch (e) { ac = new cls.AC(); }
          g = buildGraph(ac, { ir: tier.ir, vol });
          ac.onstatechange = onState;
          timer = setInterval(() => { tickMusic(); if (g) applyDuck(); }, 50);
        }
        if (ac.state !== 'running') {
          resuming = true;
          const p = ac.resume();
          if (p && p.then) p.then(onState, () => { resuming = false; });
        }
        // iOS: a buffer started inside the gesture opens the output
        const s = ac.createBufferSource();
        s.buffer = ac.createBuffer(1, 1, ac.sampleRate);
        s.connect(ac.destination);
        s.start();
      } catch (e) {
        warn('unlock failed: ' + e);
        return false;
      }
      startPending();
      return true;
    },

    /**
     * Play a one-shot. o = { volume = 1, pitch = 1 (rate), pan (-1..1) | pos (world position -> pan),
     * delay = 0 (s, audio clock), reverb = 1 (send multiplier), noSlowmo }. Returns a handle { name, stop(fade) } or null.
     */
    play(name, o = {}) {
      if (!live()) return null;
      const def = resolve(name);
      if (!def) return null;
      const now = ac.currentTime, when = now + Math.max(0, +o.delay || 0);
      const last = lastPlay.get(def.name);
      if (last !== undefined && Math.abs(when - last) < def.throttle) return null;
      lastPlay.set(def.name, when);
      const p = voiceParams(def, o, when);
      const e = sfxEntry(def.name, pickVariant(def), true);
      const h = { name: def.name, voice: null, cancelled: false, stop(fade = 0.05) { h.cancelled = true; if (h.voice) stopVoice(h.voice, fade); } };
      const go = (r) => {
        if (!r || h.cancelled || !live()) return;
        const t = Math.max(when, ac.currentTime);
        if (t - when > def.maxLate || !admit(def)) return;
        const v = startVoice(g, def, r.buffer, p, t);
        v.src.onended = () => release(v);
        voices.push(v);
        h.voice = v;
      };
      if (e.done) go(e.result); else e.promise.then(go);
      if (def.duck) ducks.push({ amount: def.duck.amount, from: when, until: when + def.duck.dur });
      return h;
    },

    /**
     * Start a looping sound (any name; `loop: true` sounds are seamless). o = { volume = 1, pitch = 1, pan = 0, fade = 0.3 }.
     * Returns { name, playing, setVolume(v, fade), setPitch(p, fade), setPan(p), stop(fade) }; inert when silent.
     */
    loop(name, o = {}) {
      const def = resolve(name);
      const h = {
        name, def, volume: o.volume ?? 1, pitch: o.pitch ?? 1, pan: o.pan ?? 0, fadeIn: o.fade ?? 0.3, voice: null, starting: false, stopped: false,
        get playing() { return !!h.voice && !h.stopped; },
        setVolume(v, fade = 0.2) { h.volume = v; if (h.voice && ac) rampParam(h.voice.gain.gain, v, fade); return h; },
        setPitch(p, fade = 0.2) { h.pitch = p; if (h.voice && ac) rampParam(h.voice.src.playbackRate, p, fade); return h; },
        setPan(p) { h.pan = p; if (h.voice && h.voice.panner) h.voice.panner.pan.setTargetAtTime(p, ac.currentTime, 0.05); return h; },
        stop(fade = 0.4) { if (h.stopped) return; h.stopped = true; loops.delete(h); if (h.voice) stopVoice(h.voice, fade); },
      };
      if (!def || !canPlay || disposed) { h.stopped = true; return h; }
      loops.add(h);
      if (live()) startLoop(h);
      return h;
    },

    /**
     * Music: 'title' | 'battle' | 'ultimate' | 'victory' | null (stop). 'ultimate' overlays the current track (which is
     * muffled underneath); any other call removes the overlay. Crossfades over o.fade seconds (default 1.5).
     * Requested before unlock(), it starts on unlock.
     */
    music(track, o = {}) {
      if (track != null && !TRACKS[track]) { warn('unknown track: ' + track); return; }
      if (track === 'ultimate') req.over = true; else { req.base = track; req.over = false; }
      if (live()) applyMusic(o.fade ?? 1.5);
    },

    /** Battle music intensity 0..1 (layers fade in: drums from 0.15, brass / choir / horn from 0.5). */
    setIntensity(x, tc = 0.5) {
      intensity = clamp(+x || 0);
      for (const tr of [mus.base, mus.over]) if (tr && tr.seq) tr.seq.setIntensity(intensity, tc);
    },

    /** Bus volumes 0..1 (any subset). */
    setVolume(v = {}) {
      for (const k of ['master', 'sfx', 'music']) if (v[k] != null) vol[k] = clamp(+v[k] || 0, 0, 1.5);
      if (!g) return;
      const now = ac.currentTime;
      g.master.gain.setTargetAtTime(vol.master * MASTER_TRIM, now, 0.03);
      g.sfx.gain.setTargetAtTime(vol.sfx, now, 0.03);
      g.music.gain.setTargetAtTime(vol.music * MUSIC_TRIM, now, 0.03);
    },
    /** Current bus volumes. */
    getVolume() { return { ...vol }; },

    /** Duck the music by `amount` (0..1) for `dur` seconds (fast attack, smooth release). */
    duck(amount = 0.5, dur = 0.8) {
      if (!live()) return;
      ducks.push({ amount: clamp(amount), from: 0, until: ac.currentTime + Math.max(0, dur) });
      applyDuck();
    },

    /** Stop every voice, loop and music track. */
    stopAll(fade = 0.2) {
      for (const h of [...loops]) h.stop(fade);
      if (!ac) { req.base = null; req.over = false; return; }
      for (const v of voices) stopVoice(v, fade);
      audio.music(null, { fade });
    },

    /** Sound names (contract names plus extras). */
    list() { return Object.keys(SOUNDS); },
    /** Music track names. */
    tracks() { return Object.keys(TRACKS); },
    /** Meta of a sound (desc, role, group, len, ...), or null. */
    info(name) { const d = SOUNDS[ALIASES[name] || name]; if (!d) return null; const { recipe, ...meta } = d; return meta; },

    /** Register a new sound (see README "Adding a sound"); clears cached renders of that name. */
    define(name, meta, recipe) {
      defineSound(name, meta, recipe);
      for (const k of [...store.keys()]) if (k.startsWith(name + '#')) store.delete(k);
    },

    /** Render (or reuse) a mastered one-shot: { buffer, gain (dB applied), rawPeak, rawLoud } or null. */
    render(name, { variant = 0 } = {}) {
      const def = resolve(name);
      if (!def || !canRender) return Promise.resolve(null);
      return sfxEntry(def.name, variant, true).promise;
    },

    /** Pre-render every sound variant and instrument. Resolves when done (use behind a loading screen if wanted). */
    prewarm() {
      if (!canRender) return Promise.resolve();
      const all = [];
      const names = [...PRIORITY, ...Object.keys(SOUNDS).filter((n) => !PRIORITY.includes(n)), '@ultimate', '@victory'];
      for (const n of names) {
        if (n[0] === '@') all.push(bank.ensure(TRACKS[n.slice(1)].instruments));
        else all.push(sfxEntry(n, 0).promise);
      }
      for (const n of Object.keys(SOUNDS)) for (let v = 1; v < Math.min(SOUNDS[n].variants, tier.variants); v++) all.push(sfxEntry(n, v).promise);
      return Promise.all(all).then(() => undefined);
    },

    /**
     * Render a scene offline through the full mix chain: music track(s) (a name or [base, 'ultimate']) at an
     * intensity, plus one-shot events [[time, name, {volume, pitch, pan}], ...]. Returns the stereo AudioBuffer.
     */
    async renderScene({ seconds = 8, sr = 48000, music: tracks, intensity: I = intensity, events = [] } = {}) {
      if (!canRender) return null;
      const oac = new cls.OAC(2, Math.ceil(seconds * sr), sr);
      const og = buildGraph(oac, { ir: tier.ir, vol });
      let base = null;
      for (const name of [].concat(tracks || [])) {
        await bank.ensure(TRACKS[name].instruments);
        const over = !!TRACKS[name].overlay && base;
        const seq = createSequencer(oac, bank, name, { dest: og.music, verb: og.verbIn, t0: over ? base.nextBeat(0.5) : 0.02, intensity: I, fadeIn: 0.01 });
        if (over) base.muffle(true, 0.01);
        seq.tick(seconds);
        if (!over) base = seq;
      }
      for (const [t, name, o = {}] of events) {
        const def = resolve(name);
        const r = def && await sfxEntry(def.name, 0, true).promise;
        if (r) startVoice(og, def, r.buffer, { rate: o.pitch ?? 1, gain: o.volume ?? 1, pan: o.pan ?? 0, verb: def.verb }, t);
      }
      return renderOffline(oac);
    },

    /** Engine statistics. */
    stats() {
      let bytes = 0, musicBytes = 0, buffers = 0;
      for (const e of store.values()) {
        if (!e.result) continue;
        const b = e.result.buffer.length * e.result.buffer.numberOfChannels * 4;
        buffers++; bytes += b;
        if (e.key[0] === '@') musicBytes += b;
      }
      return {
        state: audio.state, voices: voices.filter((v) => !v.dead).length, maxVoices: tier.voices, loops: loops.size, buffers, bytes, musicBytes, pending: queue.length,
        music: { base: mus.base && mus.base.name, overlay: mus.over && mus.over.name, intensity }, slow, duck: duckLevel,
      };
    },

    /** Stop everything, release the AudioContext, listeners and timers. */
    dispose() {
      if (disposed) return;
      audio.stopAll(0.02);
      disposed = true;
      queue.length = 0;
      clearInterval(timer);
      if (offUpdate) offUpdate();
      if (typeof window !== 'undefined') for (const e of GESTURES) window.removeEventListener(e, onGesture, { capture: true });
      if (typeof document !== 'undefined') document.removeEventListener('visibilitychange', onVisibility);
      if (ac) { try { ac.close(); } catch (e) { /* already closed */ } }
      ac = null; g = null;
    },
  };

  const offUpdate = typeof ctx.onUpdate === 'function' ? ctx.onUpdate(update, (ctx.ORDER && ctx.ORDER.UI) ?? 60) : null;
  if (canPlay && !test) setTimeout(() => { if (!disposed) audio.prewarm(); }, 500);
  ctx.audio = audio;
  return audio;
}
