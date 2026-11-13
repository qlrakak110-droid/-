// Actor: the presentation of one fighter. Owns the character, follows the rules state (position, facing, clip),
// freezes and shakes during hit-stop, runs the automatic weapon trail / whoosh of every move, and exposes the
// controls the choreography helper uses (clip override, cinematic offsets, glow, trails, reactions).
//
//   const a = createActor(ctx, session, index, fighter);
//   a.update(dtGame, dtReal)   ORDER.GAME, after match.step: clip selection + root placement
//   a.animate(dtGame, dtReal)  ORDER.CHAR: character update (frozen in hit-stop / super-freeze)
//
// State -> clip resolution with variants (src/fighters/MOTION.md "Variant slots"; every variant is optional and falls
// back to the plain slot, so a fighter map without any of them plays exactly as before):
//   hit reactions   hitLightHigh / Mid / Low by the contact height, hitLightBack / hitHeavyBack for a blow from behind;
//                   without such a clip the plain reaction plays and the difference is a flinch where the blow landed
//   face-down chain launchedProne / fallProne / downProne / getupProne / koProne after a blow from behind
//   tech            tech / techProne when the fall was teched (the rules' recovery roll)
//   guard           guardHit / guardHitHeavy one-shots per blocked hit + a flinch scaled by the weight of the blow
//   idle            idleFidget (+ idleFidget2 ...) after a few still seconds, turn on a facing flip, walkStopF / B
//   victory         one of victory, victory2 ... per round
// Variants are picked with ctx.rng (deterministic) and compiled when the actor is created.

import * as THREE from 'three';
import { createCharacter } from '../char/index.js';
import { Ease, clamp } from '../core/math.js';
import { createClipSet } from './clips.js';
import { getClip } from '../char/anim.js';
import { paletteOf, defsOf } from './fx.js';

/** Weapon-trail looks per element (ramp over age, hot edge). */
const TRAILS = {
  ember: { color: [[0, 2.2, 0.85, 0.2, 0.65], [0.12, 1.3, 0.32, 0.04, 0.4], [0.45, 0.5, 0.08, 0.012, 0.16], [1, 0.1, 0.02, 0, 0]], edge: [7, 3.4, 1] },
  frost: { color: [[0, 0.7, 1.5, 2.8, 0.7], [0.12, 0.22, 0.6, 1.5, 0.42], [0.45, 0.06, 0.18, 0.5, 0.18], [1, 0.02, 0.05, 0.12, 0]], edge: [2.4, 4.8, 8] },
  volt: { color: [[0, 1.8, 1.2, 3.4, 0.75], [0.12, 0.8, 0.35, 2, 0.45], [0.45, 0.2, 0.06, 0.55, 0.2], [1, 0.04, 0.01, 0.1, 0]], edge: [5, 3.8, 9] },
};

/** Trail life (s) per moves.js trailOn style. */
const TRAIL_LIFE = { light: 0.15, rising: 0.18, overhead: 0.2, huge: 0.22, heavy: 0.22, spin: 0.2, thrust: 0.12, drag: 0.26 };
/** trailOn data.blades -> weapon index ('R' = the first design weapon, 'L' = the second). */
const BLADES = { R: 0, L: 1, both: 'all', all: 'all' };

const NEUTRAL = new Set(['idle', 'walk', 'guard', 'blockstun', 'dash', 'backstep', 'intro', 'recovery', 'attack', 'dodge']);
/** Light hit reaction slot per contact height band. */
const HIT_LIGHT = { High: 'hitLightHigh', Mid: 'hitLightMid', Low: 'hitLightLow' };
const LOOKING = new Set(['idle', 'walk', 'guard', 'blockstun', 'dash', 'backstep', 'intro', 'recovery', 'attack', 'hitstun', 'guardbreak', 'dodge']);

/**
 * @param {object} ctx
 * @param {object} session  match session (match, actors, fx, presenter)
 * @param {number} index    0 / 1
 * @param {object} fighter  registry fighter
 */
export function createActor(ctx, session, index, fighter) {
  const match = session.match;
  let char, design = fighter.design;
  try { char = createCharacter(ctx, design, { name: 'p' + (index + 1) }); } catch (e) {
    console.warn('[ed] design of ' + fighter.id + ' failed (' + (e && e.message) + '), using the tinted knight');
    design = fighter.fallbackDesign();
    char = createCharacter(ctx, design, { name: 'p' + (index + 1) });
  }
  char.root.traverse((o) => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
  // design runtime hook (art team): living glow channels (ember flicker, flares), VORN's arc crackle -> char.glow
  if (design && typeof design.attach === 'function') {
    try { design.attach(char); } catch (e) { console.warn('[ed] ' + fighter.id + ' design.attach failed: ' + (e && e.message)); }
  }
  const env = ctx.env;
  if (env && env.wind) char.wind = [env.wind.x * 2.4, 0, env.wind.z * 2.4];
  const weapons = [];
  for (let k = 0; ; k++) {
    const sfx = k === 0 ? '' : String(k + 1);
    const a = char.sockets['weaponBase' + sfx], b = char.sockets['weaponTip' + sfx];
    if (!a || !b) break;
    weapons.push({ a, b });
  }
  // a weapon in each hand: the fallback clips must not glue the off hand to the main weapon's grip
  const clips = createClipSet(fighter, match.defs[index], { twin: weapons.length > 1 });
  const element = fighter.element;
  const pal = paletteOf(element);
  const trailLook = TRAILS[element] || TRAILS.ember;

  const actor = {
    index, fighter, char, clips, element, palette: pal, weapons,
    /** current clip key (state / move serial / reaction) */
    key: '',
    /** hit reaction serial: bumped by every clean hit taken (restarts the reaction clip) */
    react: 0,
    reactFront: true,
    /** last clean hit taken: contact height band ('High' | 'Mid' | 'Low') and whether the fall it starts lands face-down */
    hitBand: 'Mid',
    prone: false,
    /** the current get-up is a tech roll (rules 'tech' event) */
    teched: false,
    /** blocked hits: serial (bumped per block), the last one shown, heavy blow */
    guardHit: { serial: 0, shown: 0, heavy: false },
    /** idle life: still time, next fidget time, the running one-shot (fidget / turn / walk stop) and a queued one */
    idle: { t: 0, next: 6, shot: '', pending: '', fade: 0.3, serial: 0, last: -1 },
    victoryRound: -1,
    victoryClip: null,
    lastWalk: 'walkF',
    dt: 0,
    /** choreography controls the clip (cinematic lock, h.play) */
    cine: false,
    /** cinematic presentation offset (fighter-local f / u metres), tweened */
    off: { f: 0, u: 0, f0: 0, u0: 0, f1: 0, u1: 0, t: 1, dur: 0, ease: Ease.inOutSine },
    glowState: { color: new THREE.Color(), amount: 0, t: 0, dur: 0, fadeIn: 0, fadeOut: 0.2 },
    weaponGlow: { color: new THREE.Color(), amount: 0, t: 0, dur: 0, on: false },
    trails: [],
    trailMotes: null,
    autoTrail: { serial: -1, on: false, done: false, swung: false },
    lastState: '',
    hidden: false,
    /** world position of the root (presentation, after offsets) */
    pos: new THREE.Vector3(),

    get f() { return match.fighters[index]; },
    get facing() { return match.fighters[index].facing; },

    update, animate, play,
    setOffset, trailStart, trailStop, glow, flash: (c, a, d) => char.flash(c, a, d), impulse,
    socket, at, dispose, restartRound,
  };

  // ---- per-frame: rules state -> clip + placement ----------------------------------------------------------------
  function play(name, o = {}) {
    try { char.play(name, o); } catch (e) { char.play('demo.idle', { fade: 0.1 }); }
  }

  function setKey(key, name, o) {
    if (actor.key === key) return false;
    actor.key = key;
    play(name, o);
    return true;
  }

  /** Presentation slot family of the rules state (the switch below works on these). */
  function stateSlot(f) {
    switch (f.state) {
      case 'intro': return 'intro';
      case 'walk': return f.walkDir > 0 ? 'walkF' : 'walkB';
      case 'blockstun': return 'guard';
      case 'hitstun': return f.stunKind === 'crumple' ? 'crumple' : f.stunKind === 'light' ? 'hitLight' : 'hitHeavy';
      case 'launched': return f.vy > 0.6 ? 'launched' : 'fall';
      case 'knockdown': return 'down';
      case 'guardbreak': return 'guardBreak';
      case 'roll': return 'roll';
      default: return f.state;
    }
  }

  /** The variant slot of a family for this moment (direction of the blow, contact height, face-down chain, tech). */
  function variantSlot(slot) {
    switch (slot) {
      case 'hitLight': return actor.reactFront ? HIT_LIGHT[actor.hitBand] : 'hitLightBack';
      case 'hitHeavy': return actor.reactFront ? 'hitHeavy' : 'hitHeavyBack';
      case 'launched': return actor.prone ? 'launchedProne' : 'launched';
      case 'fall': return actor.prone ? 'fallProne' : 'fall';
      case 'down': return actor.prone ? 'downProne' : 'down';
      case 'ko': return actor.prone ? 'koProne' : 'ko';
      case 'getup': return actor.teched ? (actor.prone ? 'techProne' : 'tech') : actor.prone ? 'getupProne' : 'getup';
      default: return slot;
    }
  }

  /** One clip of a multi-clip slot, picked with ctx.rng (never the one picked last when there is a choice). */
  function pick(slot, last = -1) {
    const list = clips.variants(slot);
    if (!list.length) return null;
    let i = 0;
    if (list.length > 1) {
      i = Math.min(list.length - 1, Math.floor(ctx.rng() * list.length));
      if (i === last) i = (i + 1) % list.length;
    }
    pick.index = i;
    return list[i];
  }
  const fidgetDelay = () => 4.5 + ctx.rng() * 4;

  /** One-shot over the idle loop (turn-around, walk stop, fidget): held until it finishes or the state changes. */
  function idleShot(kind, c, fade) {
    const I = actor.idle;
    I.shot = kind + (++I.serial);
    setKey(I.shot, c.name, { fade, restart: true });
  }

  function selectIdle(f, c) {
    const I = actor.idle;
    if (actor.lastState !== 'idle') { I.t = 0; I.next = fidgetDelay(); I.shot = ''; }
    if (I.pending) {
      const kind = I.pending;
      I.pending = '';
      if (clips.has(kind)) { idleShot(kind, clips.state(kind), I.fade); return; }
    }
    if (I.shot) {
      if (actor.key === I.shot && !char.finished) return;
      I.shot = ''; I.t = 0; I.next = fidgetDelay();
      setKey('idle', c.name, { fade: 0.3 });
      return;
    }
    if (actor.lastState === 'walk') {
      const stop = actor.lastWalk === 'walkB' ? 'walkStopB' : 'walkStopF';
      if (clips.has(stop)) { idleShot(stop, clips.state(stop), 0.12); return; }
    }
    setKey('idle', c.name, { fade: 0.16 });
    // a few still seconds: one fidget, then the loop again (any input changes the state and cuts it)
    I.t += actor.dt;
    if (I.t >= I.next && match.phase === 'fight' && clips.has('idleFidget')) {
      const v = pick('idleFidget', I.last);
      if (v) { I.last = pick.index; idleShot('idleFidget', v, 0.3); }
    }
  }

  const walkOpts = { speed: 1 };
  function select(f) {
    const st = f.state;
    if (st === 'attack' && f.move) {
      const mc = clips.move(f.move);
      if (setKey('m' + f.moveSerial, mc.name, { fade: actor.lastState === 'attack' ? mc.fade : 0.1, restart: true })) actor.autoTrail.serial = -1;
      char.setClipTime(mc.map(f.moveTime));
      return;
    }
    const slot = stateSlot(f);
    if (st !== 'getup') actor.teched = false;
    const c = clips.state(variantSlot(slot));
    switch (slot) {
      case 'walkF': case 'walkB': {
        actor.lastWalk = slot;
        setKey(slot, c.name, { fade: 0.16 });
        const v = slot === 'walkF' ? f.def.stats.walkSpeed : f.def.stats.backSpeed;
        const rs = Math.abs(c.rootSpeed) || v;
        walkOpts.speed = clamp(v / rs, 0.7, 1.55);
        char.play(c.name, walkOpts);
        return;
      }
      case 'dash': case 'backstep': case 'dodge': case 'roll': {
        const mv = f.def.movement[st] || f.def.movement.dash;
        setKey(slot, c.name, { fade: 0.05, restart: true });
        char.setClipTime(clamp(f.stateTime / mv.duration) * c.duration);
        return;
      }
      case 'hitLight': case 'hitHeavy': {
        // restarted on every hit; no fade, so the frame held through the hit-stop is the impact pose
        setKey(slot + actor.react, c.name, { fade: 0, restart: true, startAt: slot === 'hitLight' ? 0.05 : 0.06 });
        return;
      }
      case 'crumple': case 'getup': case 'guardBreak': {
        const total = f.stateTime + Math.max(0, f.timer);
        setKey(slot + (slot === 'crumple' ? actor.react : ''), c.name, { fade: slot === 'getup' ? 0.06 : 0.04, restart: true });
        char.setClipTime(clamp(f.stateTime / Math.max(0.05, total)) * c.duration);
        return;
      }
      case 'launched': case 'fall':
        setKey(slot, c.name, { fade: actor.lastState === 'launched' ? 0.18 : 0.05 });
        return;
      case 'down':
        setKey(slot, c.name, { fade: 0.07 });
        return;
      case 'ko':
        setKey(slot, c.name, { fade: actor.lastState === 'launched' ? 0.08 : 0.3 });
        return;
      case 'intro':
        setKey('intro' + match.round, c.name, { fade: 0.2, restart: true });
        return;
      case 'guard': {
        // a blocked hit: its flinch clip (when the fighter has one), then back into the guard loop
        const g = actor.guardHit;
        if (g.serial !== g.shown) {
          g.shown = g.serial;
          const gs = g.heavy && clips.has('guardHitHeavy') ? 'guardHitHeavy' : 'guardHit';
          if (clips.has(gs)) { g.key = 'guardHit' + g.serial; setKey(g.key, clips.state(gs).name, { fade: 0.03, restart: true }); return; }
        }
        if (g.key && actor.key === g.key) {
          if (!char.finished && st === 'blockstun') return;
          g.key = '';
          setKey('guard', c.name, { fade: 0.12 });
          return;
        }
        setKey('guard', c.name, { fade: 0.08 });
        return;
      }
      case 'idle':
        selectIdle(f, c);
        return;
      case 'victory': {
        if (actor.victoryRound !== match.round) { actor.victoryRound = match.round; actor.victoryClip = pick('victory') || c; }
        setKey(slot, actor.victoryClip.name, { fade: 0.2 });
        return;
      }
      default:
        setKey(slot, c.name, { fade: 0.2 });
    }
  }

  function update(dtGame, dtReal) {
    const f = match.fighters[index];
    if (!actor.cine) {
      actor.dt = dtGame;
      if (f.facing !== char.facing) {
        const neutral = NEUTRAL.has(f.state) && f.state !== 'attack';
        char.setFacing(f.facing, neutral ? { turn: 0.1 } : {});
        // standing still when the opponent crossed over: the turn-around settle plays over the spin
        if (f.state === 'idle' && actor.lastState === 'idle' && clips.has('turn')) { actor.idle.pending = 'turn'; actor.idle.fade = 0.05; }
      }
      select(f);
      autoMoveFx(f);
    }
    actor.lastState = f.state;
    // offsets (cinematic choreography), eased on game time
    const o = actor.off;
    if (o.t < 1) {
      o.t = o.dur > 0 ? Math.min(1, o.t + dtGame / o.dur) : 1;
      const k = o.ease(o.t);
      o.f = o.f0 + (o.f1 - o.f0) * k;
      o.u = o.u0 + (o.u1 - o.u0) * k;
    }
    let x = f.x + o.f * f.facing, y = f.y + o.u;
    if (f.hitstop > 0 && f.hitstopShake && !match.cinematic) {
      const a = 0.03 * Math.min(1, f.hitstop * 14);
      x += Math.sin(ctx.time.real * 97) * a;
      y += Math.sin(ctx.time.real * 61 + 1) * a * 0.25;
    }
    char.root.position.set(x, Math.max(0, y), 0);
    actor.pos.copy(char.root.position);
    // head tracking
    const other = session.actors[1 - index];
    if (other) {
      const look = LOOKING.has(f.state) && !actor.cine;
      char.lookAt(look ? other.char.sockets.head : null, 0.85);
    }
  }

  /** Character update: frozen by this fighter's hit-stop and by the opponent's super-freeze. */
  function animate(dtGame, dtReal) {
    const f = match.fighters[index];
    let dt = dtGame;
    if (!actor.cine && f.hitstop > 0) dt = 0;
    const fz = match.freeze;
    if (fz && !fz.owners.includes(index)) dt = 0;
    // sustained glow (h.glow): re-armed flash
    const g = actor.glowState;
    if (g.amount > 0) {
      g.t += dtReal;
      let k = 1;
      if (g.fadeIn > 0 && g.t < g.fadeIn) k = g.t / g.fadeIn;
      if (g.dur > 0) { const left = g.dur - g.t; if (left <= 0) g.amount = 0; else if (left < g.fadeOut) k = Math.min(k, left / g.fadeOut); }
      if (g.amount > 0) char.flash(g.color, g.amount * k, 0.25);
    }
    char.update(dt, dtReal);
    const w = actor.weaponGlow;
    if (w.on && char.weapon && char.weapon.material) {
      w.t += dtReal;
      const left = w.dur > 0 ? w.dur - w.t : 1;
      const k = left <= 0 ? 0 : Math.min(1, left / 0.2, w.t / 0.08);
      char.weapon.material.userData.kit.uFlash.value.copy(w.color).multiplyScalar(w.amount * k);
      if (left <= 0) w.on = false;
    }
  }

  // ---- automatic weapon trail + whoosh per move (unless the fighter's present options override them) ----------------
  function autoMoveFx(f) {
    const at = actor.autoTrail;
    if (f.state !== 'attack' || !f.move) {
      if (at.on) { trailStop(); at.on = false; }
      at.serial = -1;
      return;
    }
    if (at.serial !== f.moveSerial) {
      if (at.on) trailStop();
      at.serial = f.moveSerial; at.on = false; at.done = false; at.swung = false;
      at.spec = moveFxSpec(f.move);
    }
    const s = at.spec;
    if (!s) return;
    const t = f.moveTime;
    if (s.whoosh && !at.swung && t >= s.whooshAt) {
      at.swung = true;
      session.sound(s.whoosh, { pos: actor.pos, volume: s.whooshVolume });
    }
    if (!s.trail) return;
    if (!at.on && !at.done && t >= s.t0 && t < s.t1) { trailStart(s.trailOpts); at.on = true; }
    if (at.on && t >= s.t1) { trailStop(); at.on = false; at.done = true; }
  }

  const specCache = {};
  /** Trail window / whoosh of a move: derived from its frame data, overridable by present.moves[id].options. */
  function moveFxSpec(id) {
    if (id in specCache) return specCache[id];
    const mv = f0().def.moves[id];
    const mc = clips.move(id);
    const opts = session.moveHandlers(index, id);
    const o = (opts && opts.options) || {};
    let spec = null;
    if (mv) {
      const hits = mv.hits || [];
      const startup = mc.startup ?? mv.duration * 0.4;
      const end = hits.length ? Math.max(...hits.map((h) => h.t1)) : startup + 0.12;
      const heavy = mv.duration > 0.75 || mv.group !== 'normal';
      spec = {
        trail: o.trail !== false && (hits.length > 0 || (mv.projectiles && mv.projectiles.length > 0)),
        t0: Math.max(0, startup - (heavy ? 0.12 : 0.08)), t1: end + 0.06,
        trailOpts: typeof o.trail === 'object' ? o.trail : { life: heavy ? 0.26 : 0.18 },
        whoosh: o.whoosh === false ? null : typeof o.whoosh === 'string' ? o.whoosh : mv.duration < 0.45 ? 'swing_light' : mv.duration < 0.85 ? 'swing_heavy' : 'swing_huge',
        whooshAt: Math.max(0, startup - 0.06), whooshVolume: 0.9,
      };
      // moves.js markers drive the defaults when present: trailOn / trailOff (data.style) and swing / release
      const marks = mv.markers || [];
      const mOn = marks.find((x) => x.name === 'trailOn'), mOff = marks.find((x) => x.name === 'trailOff');
      const mSwing = marks.find((x) => x.name === 'swing') || marks.find((x) => x.name === 'release');
      if (mOn) {
        spec.t0 = mOn.t;
        if (mOff) spec.t1 = mOff.t;
        const style = mOn.data && mOn.data.style;
        if (style === 'glow') spec.trail = false;
        if (typeof o.trail !== 'object') {
          const blades = mOn.data && BLADES[mOn.data.blades];
          spec.trailOpts = { life: TRAIL_LIFE[style] ?? spec.trailOpts.life, weapon: blades !== undefined && (blades === 'all' || blades < weapons.length) ? blades : 'all' };
        }
      }
      if (mSwing) spec.whooshAt = Math.max(0, mSwing.t - 0.03);
      if (o.trail && o.trail.t) { spec.t0 = o.trail.t[0]; spec.t1 = o.trail.t[1]; }
      if (mv.cinematic) spec.whoosh = null;
    }
    return (specCache[id] = spec);
  }
  const f0 = () => match.fighters[index];

  // ---- controls used by the choreography helper --------------------------------------------------------------------
  /** Weapon trail on the weapon sockets. opts: { weapon: 'all' | 0 | 1, life, color, edge, width, distort, motes } */
  function trailStart(opts = {}) {
    if (!ctx.vfx) return;
    const list = opts.weapon === undefined || opts.weapon === 'all' ? weapons : weapons.filter((_, k) => k === opts.weapon);
    for (const w of list) {
      const h = session.fx.call('trail', {
        a: w.a, b: w.b, life: opts.life ?? 0.2, color: opts.color || trailLook.color, edge: opts.edge || trailLook.edge,
        distort: opts.distort ?? 0.012, width: opts.width, minSpeed: opts.minSpeed ?? 2.5,
      });
      actor.trails.push(h);
    }
    if (opts.motes !== false && weapons[0] && !actor.trailMotes) {
      actor.trailMotes = session.fx.call('emitter', defsOf(element).trailMotes, {});
      if (actor.trailMotes.follow) actor.trailMotes.follow(weapons[0].b);
    }
  }
  function trailStop() {
    for (const h of actor.trails) h.stop();
    actor.trails.length = 0;
    if (actor.trailMotes) { actor.trailMotes.stop(); actor.trailMotes = null; }
  }

  /** Sustained emissive glow: colour (HDR [r,g,b] / hex), amount, duration s (0 = until glow(null)). */
  function glow(color, amount = 1, dur = 0, fadeIn = 0.1) {
    const g = actor.glowState;
    if (color === null || amount <= 0) { g.amount = 0; return; }
    if (Array.isArray(color)) g.color.setRGB(color[0], color[1], color[2]); else g.color.set(color);
    g.amount = amount; g.t = 0; g.dur = dur; g.fadeIn = fadeIn;
  }

  /** Physical flinch in this fighter's frame: dir [f, u, s] push direction, amount (1 = heavy hit). */
  function impulse(dir, amount = 1, bone = 'body') {
    char.impulse({ bone, dir, amount });
  }

  /** Cinematic offset of the root in the fighter frame: to [f, u] metres over dur s (game time). */
  function setOffset(to, dur = 0.2, ease = 'inOutSine') {
    const o = actor.off;
    o.f0 = o.f; o.u0 = o.u; o.f1 = to[0] || 0; o.u1 = to[1] || 0; o.t = dur > 0 ? 0 : 1; o.dur = dur;
    o.ease = typeof ease === 'function' ? ease : Ease[ease] || Ease.inOutSine;
    if (dur <= 0) { o.f = o.f1; o.u = o.u1; }
  }

  /** World position of a socket (fresh after this frame's character update). */
  function socket(name, out = new THREE.Vector3()) {
    const s = char.sockets[name] || char.sockets.chest;
    return s.getWorldPosition(out);
  }

  /** World point in this fighter's frame: f forward (mirrored by facing), u height above the floor, s toward the camera. */
  function at(fv = 0, u = 0, s = 0, out = new THREE.Vector3()) {
    return out.set(actor.pos.x + fv * match.fighters[index].facing, u, s);
  }

  function restartRound() {
    trailStop();
    actor.key = '';
    actor.cine = false;
    actor.react = 0;
    actor.reactFront = true; actor.hitBand = 'Mid'; actor.prone = false; actor.teched = false;
    actor.guardHit.shown = actor.guardHit.serial; actor.guardHit.key = '';
    actor.idle.t = 0; actor.idle.shot = ''; actor.idle.pending = '';
    actor.lastState = '';
    setOffset([0, 0], 0);
    actor.glowState.amount = 0;
    actor.weaponGlow.on = false;
    if (char.weapon && char.weapon.material) char.weapon.material.userData.kit.uFlash.value.setRGB(0, 0, 0);
    const f = match.fighters[index];
    char.root.position.set(f.x, 0, 0);
    char.setFacing(f.facing);
    char.teleport();
  }

  function dispose() {
    trailStop();
    for (const off of offs) off();
    char.dispose();
  }

  // compile every clip this fighter can play now, variants included (clips compile lazily per rig: no first-use hitch mid-fight)
  for (const name of clips.names()) { try { getClip(char.rig, name); } catch (e) { /* reported when played */ } }

  // reaction bookkeeping straight from the rules events (they fire inside match.step, before this frame's update)
  const offs = [
    match.on('hit', (e) => {
      if (e.defender !== index || e.armoured) return;
      if (e.blocked) {
        if (e.guardBreak) return;
        // a flinch scaled by the weight of the blow (its hit-stop grows with the damage), on top of the feel layer's
        const k = clamp(((e.hitstop || 0.05) - 0.04) / 0.08);
        const g = actor.guardHit;
        g.serial++; g.heavy = k > 0.5 || (e.level && e.level !== 'light');
        if (!e.perfect && k > 0) char.impulse({ bone: 'body', dir: [-1, 0, 0], amount: 0.45 * k });
        return;
      }
      const f = match.fighters[index];
      const h = (f.def.stats.height || 1.9), y = ((e.y ?? h * 0.6) - f.y) / h;
      const band = (actor.hitBand = y > 0.72 ? 'High' : y < 0.4 ? 'Low' : 'Mid');
      // thrown forward by a blow from behind: the fall that follows ends face-down
      actor.prone = e.front === false;
      // no reaction clip made for this height / side yet (a hero with a single hitLight / hitHeavy): the same clip
      // plays, and the body takes the difference as a physical flinch where the blow landed
      const lvl = e.level || 'light', heavy = lvl !== 'light';
      const slot = heavy ? (e.front === false ? 'hitHeavyBack' : null) : e.front === false ? 'hitLightBack' : HIT_LIGHT[band];
      if (!(slot && clips.has(slot)) && (lvl === 'light' || lvl === 'heavy')) {
        const d = e.front === false ? 1 : -1, k = heavy ? 0.9 : 0.55;
        if (band === 'High') {          // the head goes first
          char.impulse({ bone: 'head', dir: [d, 0.25, 0.3], amount: 1.3 * k });
          char.impulse({ bone: 'neck', dir: [d, 0.1, 0.15], amount: 0.7 * k });
        } else if (band === 'Low') {    // the front leg is knocked from under the hips
          char.impulse({ bone: 'thighL', dir: [d, 0, 0], amount: 0.9 * k });
          char.impulse({ bone: 'chest', dir: [-d, -0.2, 0], amount: 0.5 * k });
        } else {                        // folds around the blow: the chest comes forward as the hips are shoved back
          char.impulse({ bone: 'chest', dir: [-d, -0.2, 0], amount: 0.8 * k });
          char.impulse({ bone: 'head', dir: [d, 0, 0], amount: 0.4 * k });
        }
      }
    }),
    match.on('tech', (e) => { if (e.fighter === index) actor.teched = true; }),
  ];

  char.onEvent((name, data) => {
    if (name === 'step' && !actor.cine) session.onStep(actor, data);
  });
  char.setFacing(match.fighters[index].facing);
  char.root.position.set(match.fighters[index].x, 0, 0);
  actor.pos.copy(char.root.position);
  return actor;
}
