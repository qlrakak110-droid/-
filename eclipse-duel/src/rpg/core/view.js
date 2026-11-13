// The picture of an actor: its character (src/char), logic state -> clip, placement between two fixed steps, hit-stop
// shake, weapon trails / whooshes of every attack, glow, cinematic offsets. The logic never reads anything from here
// except `char` sockets (socket-bound hit shapes) — presentation only.
//
//   actor.view.present(alpha, dtGame, dtReal)   ORDER.GAME, after the fixed steps (alpha = fraction of the next step)
//   actor.view.animate(dtGame, dtReal)          ORDER.CHAR: character update

import * as THREE from 'three';
import { createCharacter, hasClip } from '../../char/index.js';
import { getClip, getClipDef } from '../../char/anim.js';
import { Ease, clamp } from '../../core/math.js';
import { createClipSet, GENERIC, clipDuration, clipRootSpeed } from '../../game/clips.js';
import { paletteOf, defsOf } from '../../game/fx.js';
import { STEP, fwdX, fwdZ, lerpAngle, rightX, rightZ } from './math3.js';

/** Weapon-trail looks per element (ramp over age, hot edge) — the duel's. */
const TRAILS = {
  ember: { color: [[0, 2.2, 0.85, 0.2, 0.65], [0.12, 1.3, 0.32, 0.04, 0.4], [0.45, 0.5, 0.08, 0.012, 0.16], [1, 0.1, 0.02, 0, 0]], edge: [7, 3.4, 1] },
  frost: { color: [[0, 0.7, 1.5, 2.8, 0.7], [0.12, 0.22, 0.6, 1.5, 0.42], [0.45, 0.06, 0.18, 0.5, 0.18], [1, 0.02, 0.05, 0.12, 0]], edge: [2.4, 4.8, 8] },
  volt: { color: [[0, 1.8, 1.2, 3.4, 0.75], [0.12, 0.8, 0.35, 2, 0.45], [0.45, 0.2, 0.06, 0.55, 0.2], [1, 0.04, 0.01, 0.1, 0]], edge: [5, 3.8, 9] },
  steel: { color: [[0, 1.6, 1.5, 1.4, 0.5], [0.15, 0.7, 0.66, 0.6, 0.3], [0.5, 0.2, 0.19, 0.18, 0.12], [1, 0.03, 0.03, 0.03, 0]], edge: [4, 3.6, 3] },
};
const TRAIL_LIFE = { light: 0.15, rising: 0.18, overhead: 0.2, huge: 0.22, heavy: 0.22, spin: 0.2, thrust: 0.12, drag: 0.26 };
const BLADES = { R: 0, L: 1, both: 'all', all: 'all' };

/** RPG state slot -> fallbacks (duel slot names of src/game/clips.js GENERIC, then generic clips). */
const SLOT_ALIAS = {
  walk: ['walkF'], run: ['walk', 'walkF'], sprint: ['run', 'walk', 'walkF'],
  flinch: ['hitLight'], stagger: ['hitHeavy'], guardbreak: ['guardBreak', 'hitHeavy'], guardhit: ['guard'],
  dead: ['ko'], drink: ['idle'], rest: ['idle'], spawn: ['idle'], backstep: ['roll', 'dash'], roll: ['dash'],
  hitLight: ['flinch'], hitHeavy: ['stagger'], ko: ['dead'], locked: ['stagger', 'hitHeavy'], launched: [], fall: [],
};

/** Clip resolver of a non-fighter kind: spec.clips, aliases, then the generic game.* / demo.* set. */
function kindClips(spec) {
  const map = spec.clips || {};
  const states = {}, moves = {};
  const pick = (slot) => {
    const v = map[slot];
    if (!v) return null;
    const o = typeof v === 'string' ? { clip: v } : v;
    return o.clip && hasClip(o.clip) ? o : null;
  };
  const state = (slot) => {
    if (states[slot]) return states[slot];
    let o = pick(slot);
    if (!o) for (const alt of SLOT_ALIAS[slot] || []) { o = pick(alt); if (o) break; }
    let name = o ? o.clip : null;
    if (!name) {
      const g = GENERIC[slot] || (SLOT_ALIAS[slot] || []).map((s) => GENERIC[s]).find(Boolean);
      name = g && hasClip(g) ? g : 'demo.idle';
    }
    return (states[slot] = { name, speed: (o && o.speed) || 1, own: !!o, duration: clipDuration(name), rootSpeed: clipRootSpeed(name) });
  };
  const move = (id) => {
    if (moves[id]) return moves[id];
    const atk = spec.attacks && spec.attacks[id];
    const c = atk && atk.clip ? (typeof atk.clip === 'string' ? { clip: atk.clip } : atk.clip) : null;
    const name = c && hasClip(c.clip) ? c.clip : hasClip('demo.combo1') ? 'demo.combo1' : 'demo.idle';
    const cd = clipDuration(name);
    const dur = atk ? atk.duration : cd;
    // retimed onto the frame data: `hit` (clip impact time), else the clip's own hit / impact event; `hit: false` or
    // `speed` plays the clip 1:1 against the attack clock
    let impact = c && typeof c.hit === 'number' ? c.hit : null;
    if (impact === null && !(c && (c.hit === false || c.speed))) {
      const d = getClipDef(name);
      const ev = d && d.events ? d.events.find((e) => e.name === 'hit' || e.name === 'impact') : null;
      impact = ev ? ev.t : c && hasClip(c.clip) ? null : cd * 0.35;
    }
    const startup = atk && atk.hits && atk.hits.length ? Math.min(...atk.hits.map((h) => (h.t ? h.t[0] : h.t0))) : dur * 0.4;
    let mapFn;
    if (impact === null) { const k = (c && c.speed) || 1; mapFn = (t) => Math.min(cd, t * k); }
    else {
      const s = Math.max(1e-3, Math.min(startup, dur - 1e-3));
      const k1 = impact / s, k2 = (cd - impact) / Math.max(1e-3, dur - s);
      mapFn = (t) => (t <= s ? t * k1 : Math.min(cd, impact + (t - s) * k2));
    }
    return (moves[id] = { name, map: mapFn, own: !!c, fade: (c && c.fade) ?? 0.08, startup, slot: id });
  };
  return { state, move, slots: {} };
}

/**
 * @param {object} ctx
 * @param {object} world
 * @param {object} a actor
 * @param {object} opts spawn options
 */
export function createView(ctx, world, a, opts) {
  const spec = a.spec;
  let char = null, custom = false;
  if (typeof spec.create === 'function') {
    char = spec.create(ctx, world, a, opts);
    custom = true;
    if (char && char.root && !char.root.parent) ctx.scene.add(char.root);
  } else if (spec.design) {
    let design = spec.design;
    try { char = createCharacter(ctx, design, { name: spec.kind + a.id }); } catch (e) {
      console.warn('[ed] rpg: design of ' + spec.kind + ' failed (' + (e && e.message) + ')');
      if (spec.fallbackDesign) { design = spec.fallbackDesign(); char = createCharacter(ctx, design, { name: spec.kind + a.id }); }
    }
    if (char) {
      char.root.traverse((o) => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
      if (design && typeof design.attach === 'function') { try { design.attach(char); } catch (e) { /* art hook is optional */ } }
      const env = ctx.env;
      if (env && env.wind) char.wind = [env.wind.x * 2.4, 0, env.wind.z * 2.4];
      if (a.scale !== 1 && spec.scaleChar !== false && !design.scale) char.scale = a.scale;
    }
  }
  const weapons = [];
  if (char && char.sockets) {
    for (let k = 0; ; k++) {
      const sfx = k === 0 ? '' : String(k + 1);
      const s0 = char.sockets['weaponBase' + sfx], s1 = char.sockets['weaponTip' + sfx];
      if (!s0 || !s1) break;
      weapons.push({ a: s0, b: s1 });
    }
  }
  const element = spec.element || 'steel';
  const palette = spec.palette || (element === 'steel' ? { core: [9, 7, 4.6], mid: [3.2, 1.7, 0.55], tail: [0.3, 0.1, 0.02], smoke: [0.06, 0.055, 0.05] } : paletteOf(element));
  const trailLook = TRAILS[element] || TRAILS.steel;
  const clips = spec.fighter ? heroClips(spec, weapons.length > 1) : kindClips(spec);

  const view = {
    char, clips, weapons, element, palette, custom,
    /** current clip key (state / attack serial / reaction serial) */
    key: '',
    /** presentation root position (after interpolation and offsets) */
    pos: new THREE.Vector3(a.pos.x, a.pos.y, a.pos.z), yaw: a.yaw,
    /** cinematic offset in the actor frame [f, u], tweened on game time */
    off: { f: 0, u: 0, f0: 0, u0: 0, f1: 0, u1: 0, t: 1, dur: 0, ease: Ease.inOutSine },
    glowState: { color: new THREE.Color(), amount: 0, t: 0, dur: 0, fadeIn: 0, fadeOut: 0.2 },
    weaponGlow: { color: new THREE.Color(), amount: 0, t: 0, dur: 0, on: false },
    trails: [], trailMotes: null,
    auto: { serial: -1, on: false, done: false, swung: false, spec: null },
    lastState: '', shake: 0, lookTarget: null,
    present, animate, play, setOffset, trailStart, trailStop, glow, impulse, flash, teleport, dispose,
  };

  function play(name, o = {}) {
    if (!char || !char.play) return;
    try { char.play(name, o); } catch (e) { try { char.play('demo.idle', { fade: 0.1 }); } catch (e2) { /* no clips at all */ } }
  }
  function setKey(key, name, o) {
    if (view.key === key) return false;
    view.key = key;
    play(name, o);
    return true;
  }

  const moveOpts = { speed: 1 };
  /** Logic state -> clip. */
  function select(alpha) {
    if (!char || !char.play) return;
    const s = a.state;
    if (s === 'attack' && a.attack) {
      const inst = a.attack;
      const mc = clips.move(inst.id);
      if (setKey('m' + inst.serial, mc.name, { fade: view.lastState === 'attack' ? mc.fade : 0.1, restart: true })) view.auto.serial = -1;
      if (char.setClipTime) char.setClipTime(mc.map(Math.max(0, inst.t + (world.frozen(a) ? 0 : alpha * STEP))));
      return;
    }
    switch (s) {
      case 'move': {
        const slot = a.gait === 'sprint' ? 'sprint' : a.gait === 'run' ? 'run' : 'walk';
        const c = clips.state(slot);
        setKey(slot, c.name, { fade: 0.18 });
        const rs = Math.abs(c.rootSpeed) || a.moveSpeed || 1;
        moveOpts.speed = clamp(a.moveSpeed / rs, 0.55, 1.5);
        char.play(c.name, moveOpts);
        return;
      }
      case 'guard': case 'guardhit': {
        if (a.speed > 0.3 && s === 'guard') {
          // guard walk: the fighter's stance walks, forward or backward along the facing
          const fwd = a.moveX * fwdX(a.yaw) + a.moveZ * fwdZ(a.yaw) >= -0.2;
          const c = clips.state(fwd ? 'walkF' : 'walkB');
          setKey(fwd ? 'gwF' : 'gwB', c.name, { fade: 0.16 });
          moveOpts.speed = clamp(a.speed / (Math.abs(c.rootSpeed) || 1.5), 0.5, 1.4);
          char.play(c.name, moveOpts);
          if (char.layer && !view.guardLayer) { view.guardLayer = true; char.layer('guard', clips.state('guard').name, { mask: 'upper', fade: 0.1 }); }
          return;
        }
        if (view.guardLayer) { view.guardLayer = false; char.stopLayer('guard', 0.12); }
        setKey('guard', clips.state('guard').name, { fade: 0.08 });
        return;
      }
      case 'roll': {
        const c = clips.state(a.rollBack ? 'backstep' : 'roll');
        setKey('roll' + a.react + (a.rollBack ? 'b' : ''), c.name, { fade: 0.05, restart: true });
        if (char.setClipTime) char.setClipTime(clamp((a.stateTime + alpha * STEP) / a.roll.duration) * c.duration);
        return;
      }
      case 'flinch': {
        const c = clips.state('flinch');
        setKey('fl' + a.react, c.name, { fade: 0, restart: true, startAt: 0.05 });
        return;
      }
      case 'stagger': {
        const c = clips.state(a.stunKind === 'guardbreak' ? 'guardbreak' : a.stunKind === 'crumple' ? 'crumple' : 'stagger');
        if (a.stunKind === 'crumple' || a.stunKind === 'guardbreak') {
          setKey('st' + a.react, c.name, { fade: 0.04, restart: true });
          if (char.setClipTime) char.setClipTime(clamp(a.stateTime / Math.max(0.05, a.stateDur)) * c.duration);
        } else setKey('st' + a.react, c.name, { fade: 0, restart: true, startAt: 0.06 });
        return;
      }
      case 'launched': {
        const rising = a.vel.y > 0.6;
        setKey(rising ? 'rise' : 'fall', clips.state(rising ? 'launched' : 'fall').name, { fade: view.lastState === 'launched' ? 0.18 : 0.05 });
        return;
      }
      case 'down': setKey('down' + a.react, clips.state('down').name, { fade: 0.07 }); return;
      case 'getup': {
        const c = clips.state('getup');
        setKey('getup' + a.react, c.name, { fade: 0.06, restart: true });
        if (char.setClipTime) char.setClipTime(clamp(a.stateTime / Math.max(0.05, a.stateDur)) * c.duration);
        return;
      }
      case 'dead': setKey('dead', clips.state('dead').name, { fade: view.lastState === 'launched' ? 0.08 : 0.12, restart: true }); return;
      case 'drink': {
        const c = clips.state('drink');
        setKey('drink' + a.chalice, c.name, { fade: 0.1, restart: true });
        if (char.setClipTime && c.own) char.setClipTime(clamp(a.stateTime / a.drinkSpec.duration) * c.duration);
        return;
      }
      case 'rest': setKey('rest', clips.state('rest').name, { fade: 0.35 }); return;
      case 'spawn': setKey('spawn', clips.state('spawn').name, { fade: 0 }); return;
      case 'idle': setKey('idle', clips.state('idle').name, { fade: view.lastState === 'move' ? 0.2 : 0.16 }); return;
      default: {
        // custom states of a kind with its own machine: a clip slot of the same name, else idle
        const c = clips.state(s);
        setKey(s, c.name, { fade: 0.15 });
      }
    }
  }

  /** Place the root between the last two steps; select the clip. */
  function present(alpha, dtGame, dtReal) {
    if (!a.cine) {
      if (view.guardLayer && a.state !== 'guard') { view.guardLayer = false; if (char && char.stopLayer) char.stopLayer('guard', 0.12); }
      select(alpha);
      autoMoveFx();
    } else if (view.guardLayer) { view.guardLayer = false; if (char && char.stopLayer) char.stopLayer('guard', 0.05); }
    view.lastState = a.state;
    const o = view.off;
    if (o.t < 1) {
      o.t = o.dur > 0 ? Math.min(1, o.t + dtGame / o.dur) : 1;
      const k = o.ease(o.t);
      o.f = o.f0 + (o.f1 - o.f0) * k;
      o.u = o.u0 + (o.u1 - o.u0) * k;
    }
    const fr = world.frozen(a) ? 1 : alpha;
    let x = a.prev.x + (a.pos.x - a.prev.x) * fr, y = a.prev.y + (a.pos.y - a.prev.y) * fr, z = a.prev.z + (a.pos.z - a.prev.z) * fr;
    const yaw = lerpAngle(a.prevYaw, a.yaw, fr);
    if (o.f !== 0 || o.u !== 0) { x += fwdX(yaw) * o.f; z += fwdZ(yaw) * o.f; y += o.u; }
    if (view.shake > 0) {
      view.shake = ctx.time.inHitstop ? view.shake : 0;
      const k = 0.028 * a.scale, t = ctx.time.real;
      x += Math.sin(t * 97) * k * rightX(yaw); z += Math.sin(t * 97) * k * rightZ(yaw); y += Math.sin(t * 61 + 1) * k * 0.25;
    }
    view.pos.set(x, Math.max(0, y), z);
    view.yaw = yaw;
    if (char && char.root) {
      const r = char.root;
      if (a.leaving > 0 && a.leaveDur > 0) {
        // dissolve: sink into the floor haze
        const k = clamp(a.leaving / a.leaveDur);
        r.position.set(x, Math.max(0, y) - (1 - k) * (1 - k) * a.height * 1.05, z);
      } else r.position.copy(view.pos);
      r.rotation.y = yaw;
      if (char.lookAt) {
        const t = a.target && a.target.alive && a.target.char && !a.cine && (a.state === 'idle' || a.state === 'move' || a.state === 'guard' || a.state === 'attack') ? a.target : null;
        const lt = t && t.char.sockets ? t.char.sockets.head || t.char.sockets.chest : null;
        if (lt !== view.lookTarget) { view.lookTarget = lt; char.lookAt(lt, 0.8); }
      }
    }
    void dtReal;
  }

  /** Character update (frozen by the world freeze of an ultimate when this actor is not its owner). */
  function animate(dtGame, dtReal) {
    if (!char) return;
    const dt = world.frozen(a) && !a.cine ? 0 : dtGame;
    const g = view.glowState;
    if (g.amount > 0 && char.flash) {
      g.t += dtReal;
      let k = 1;
      if (g.fadeIn > 0 && g.t < g.fadeIn) k = g.t / g.fadeIn;
      if (g.dur > 0) { const left = g.dur - g.t; if (left <= 0) g.amount = 0; else if (left < g.fadeOut) k = Math.min(k, left / g.fadeOut); }
      if (g.amount > 0) char.flash(g.color, g.amount * k, 0.25);
    }
    char.update(dt, dtReal);
    const w = view.weaponGlow;
    if (w.on && char.weapon && char.weapon.material && char.weapon.material.userData.kit) {
      w.t += dtReal;
      const left = w.dur > 0 ? w.dur - w.t : 1;
      const k = left <= 0 ? 0 : Math.min(1, left / 0.2, w.t / 0.08);
      char.weapon.material.userData.kit.uFlash.value.copy(w.color).multiplyScalar(w.amount * k);
      if (left <= 0) w.on = false;
    }
  }

  // ---- automatic weapon trail + whoosh per attack (unless the choreography owns them) -------------------------------
  const specCache = new Map();
  function fxSpec(def) {
    if (specCache.has(def)) return specCache.get(def);
    const mh = world.present ? world.present.moveHandlers(a, def.id) : null;
    const o = (mh && mh.options) || {};
    const startup = def.firstActive;
    const heavy = def.duration > 0.75 || def.group !== 'normal';
    const s = {
      trail: o.trail !== false && (def.hits.length > 0 || def.projectiles.length > 0) && weapons.length > 0,
      t0: Math.max(0, startup - (heavy ? 0.12 : 0.08)), t1: def.lastActive + 0.06,
      trailOpts: typeof o.trail === 'object' ? o.trail : { life: heavy ? 0.26 : 0.18 },
      whoosh: o.whoosh === false || def.cinematic ? null : typeof o.whoosh === 'string' ? o.whoosh : def.duration < 0.45 ? 'swing_light' : def.duration < 0.85 ? 'swing_heavy' : 'swing_huge',
      whooshAt: Math.max(0, startup - 0.06),
    };
    const mOn = def.markers.find((x) => x.name === 'trailOn'), mOff = def.markers.find((x) => x.name === 'trailOff');
    const mSwing = def.markers.find((x) => x.name === 'swing') || def.markers.find((x) => x.name === 'release');
    if (mOn) {
      s.t0 = mOn.t;
      if (mOff) s.t1 = mOff.t;
      const style = mOn.data && mOn.data.style;
      if (style === 'glow') s.trail = false;
      if (typeof o.trail !== 'object') {
        const blades = mOn.data && BLADES[mOn.data.blades];
        s.trailOpts = { life: TRAIL_LIFE[style] ?? s.trailOpts.life, weapon: blades !== undefined && (blades === 'all' || blades < weapons.length) ? blades : 'all' };
      }
    }
    if (mSwing) s.whooshAt = Math.max(0, mSwing.t - 0.03);
    if (o.trail && o.trail.t) { s.t0 = o.trail.t[0]; s.t1 = o.trail.t[1]; }
    if (def.hits.length === 0 && def.projectiles.length === 0 && !mSwing) s.whoosh = null;
    specCache.set(def, s);
    return s;
  }
  function autoMoveFx() {
    const at = view.auto;
    const inst = a.attack;
    if (a.state !== 'attack' || !inst) {
      if (at.on) { trailStop(); at.on = false; }
      at.serial = -1;
      return;
    }
    if (at.serial !== inst.serial) {
      if (at.on) trailStop();
      at.serial = inst.serial; at.on = false; at.done = false; at.swung = false;
      at.spec = fxSpec(inst.def);
    }
    const s = at.spec, t = inst.t;
    if (s.whoosh && !at.swung && t >= s.whooshAt) {
      at.swung = true;
      if (world.present) world.present.sound(s.whoosh, { pos: view.pos, volume: a.team === 'hero' ? 0.9 : 0.6 });
    }
    if (!s.trail) return;
    if (!at.on && !at.done && t >= s.t0 && t < s.t1) { trailStart(s.trailOpts); at.on = true; }
    if (at.on && t >= s.t1) { trailStop(); at.on = false; at.done = true; }
  }

  // ---- controls used by the choreography helper and the feel layer ---------------------------------------------------
  function trailStart(o = {}) {
    const vfx = ctx.vfx;
    if (!vfx || !vfx.trail) return;
    const list = o.weapon === undefined || o.weapon === 'all' ? weapons : weapons.filter((_, k) => k === o.weapon);
    for (const w of list) {
      try {
        view.trails.push(vfx.trail({ a: w.a, b: w.b, life: o.life ?? 0.2, color: o.color || trailLook.color, edge: o.edge || trailLook.edge, distort: o.distort ?? 0.012, width: o.width, minSpeed: o.minSpeed ?? 2.5 }));
      } catch (e) { /* trail is decoration */ }
    }
    if (o.motes !== false && weapons[0] && !view.trailMotes && element !== 'steel') {
      try { view.trailMotes = vfx.emitter(defsOf(element).trailMotes, {}); if (view.trailMotes.follow) view.trailMotes.follow(weapons[0].b); } catch (e) { view.trailMotes = null; }
    }
  }
  function trailStop() {
    for (const h of view.trails) h.stop();
    view.trails.length = 0;
    if (view.trailMotes) { view.trailMotes.stop(); view.trailMotes = null; }
  }
  /** Sustained emissive glow: colour, amount, duration s (0 = until glow(null)). */
  function glow(color, amount = 1, dur = 0, fadeIn = 0.1) {
    const g = view.glowState;
    if (color === null || color === undefined || amount <= 0) { g.amount = 0; return; }
    if (Array.isArray(color)) g.color.setRGB(color[0], color[1], color[2]); else g.color.set(color);
    g.amount = amount; g.t = 0; g.dur = dur; g.fadeIn = fadeIn;
  }
  function impulse(dir, amount = 1, bone = 'body') { if (char && char.impulse) char.impulse({ bone, dir, amount }); }
  function flash(c, k, d) { if (char && char.flash) char.flash(c, k, d); }
  /** Cinematic root offset in the actor frame: to [f, u] metres over dur s (game time). */
  function setOffset(to, dur = 0.2, ease = 'inOutSine') {
    const o = view.off;
    o.f0 = o.f; o.u0 = o.u; o.f1 = to[0] || 0; o.u1 = to[1] || 0; o.t = dur > 0 ? 0 : 1; o.dur = dur;
    o.ease = typeof ease === 'function' ? ease : Ease[ease] || Ease.inOutSine;
    if (dur <= 0) { o.f = o.f1; o.u = o.u1; }
  }
  function teleport() {
    view.pos.set(a.pos.x, a.pos.y, a.pos.z);
    if (char && char.root) { char.root.position.copy(view.pos); char.root.rotation.y = a.yaw; }
    if (char && char.teleport) char.teleport();
  }
  function dispose() {
    trailStop();
    if (char && char.dispose) char.dispose();
    else if (char && char.root) char.root.removeFromParent();
  }

  // compile every clip this actor can play now (no first-use hitch mid-fight)
  if (char && char.rig) {
    const warm = (name) => { try { getClip(char.rig, name); } catch (e) { /* reported when played */ } };
    for (const slot of ['idle', 'walk', 'run', 'sprint', 'roll', 'backstep', 'guard', 'flinch', 'stagger', 'guardbreak', 'crumple', 'launched', 'fall', 'down', 'getup', 'dead', 'drink', 'rest', 'spawn', 'walkF', 'walkB', 'locked']) warm(clips.state(slot).name);
    if (spec.attacks) for (const id in spec.attacks) warm(clips.move(id).name);
    if (spec.warmClips) for (const n of spec.warmClips) if (hasClip(n)) warm(n);
  }
  if (char && char.onEvent) char.onEvent((name, data) => { if (name === 'step' && !a.cine) world.emit('step', { actor: a, foot: data && data.foot }); });
  if (char && char.root) { char.root.position.copy(view.pos); char.root.rotation.y = a.yaw; }
  if (char && char.teleport) char.teleport();
  return view;
}

/** Clip resolver of a hero: the fighter's own clip set (states + every move) plus the rpg.<hero>.* locomotion. */
function heroClips(spec, twin) {
  const base = createClipSet(spec.fighter, spec.cdef, { twin });
  const own = spec.clips || {};
  const cache = {};
  const HERO_SLOT = { flinch: 'hitLight', stagger: 'hitHeavy', guardbreak: 'guardBreak', dead: 'ko', guardhit: 'guard', spawn: 'idle' };
  const state = (slot) => {
    if (cache[slot]) return cache[slot];
    const name = own[slot] && hasClip(own[slot]) ? own[slot] : null;
    if (name) return (cache[slot] = { name, speed: 1, own: true, duration: clipDuration(name), rootSpeed: clipRootSpeed(name) });
    let s = HERO_SLOT[slot] || slot;
    if (slot === 'run' || slot === 'walk' || slot === 'sprint') s = 'walkF';
    if (slot === 'backstep' || slot === 'roll') s = slot;
    if (slot === 'drink' || slot === 'rest') s = 'idle';
    return (cache[slot] = base.state(s));
  };
  return { state, move: base.move, slots: base.slots };
}
