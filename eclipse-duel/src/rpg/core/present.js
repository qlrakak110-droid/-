// Choreography adapter of the RPG mode (README §6.5): runs the handlers of src/fighters/<id>/present.js (and of any
// kind's `spec.present`) on RPG actors through a helper `h` with the surface of src/game/present.js, in a stage frame
// (core/stage.js), routes world events to them and to the generic feel (core/feel.js), and runs the ultimates:
// super-freeze, the cinematic lock against lockable enemies, the non-locking "ultimate strike" against a boss.
//
//   const present = createPresent(ctx, world, { fx });      world.present
//   present.late(dtGame, dtReal)                            ORDER.CHAR + 5: queued events -> handlers / feel (fresh sockets)
//   present.stepLock(dt)                                    world.step: the lock clock (ticks, finish, release)

import * as THREE from 'three';
import * as SHOTS from '../../cam/shots.js';
import { Ease } from '../../core/math.js';
import { paletteOf } from '../../game/fx.js';
import { rosterEntry } from '../../fighters/registry.js';
import { actorFrame, currentFrame, dirToWorld, installStage, proxy, proxySockets, stageToWorld, unwrap, withFrame, worldToStage } from './stage.js';
import { createFeel } from './feel.js';
import { fwdX, fwdZ, hypot2, passes, yawTo } from './math3.js';

const NULL_CAM = Object.freeze({ stop() {}, next() {}, goto() {}, done: true, index: -1, time: 0 });
const CUT_SLOTS = ['light1', 'light2', 'light3', 'heavy'];

/**
 * @param {object} ctx
 * @param {object} world
 * @param {{ fx: object }} o the duel's safe VFX access (src/game/fx.js createFx)
 */
export function createPresent(ctx, world, o) {
  const fx = o.fx;
  const warned = new Set();
  const soundAt = new Map();
  const helpers = new Map();
  const queue = [];
  /** running super-freeze / ultimate presentation of the hero: { actor, move, cine, cam } */
  let ultState = null;
  /** presentation side of the running lock */
  let cine = null;
  const uninstallStage = installStage(ctx.vfx);

  function warnOnce(key, e) {
    if (warned.has(key)) return;
    warned.add(key);
    console.warn('[ed] rpg choreography ' + key + ' threw: ' + (e && (e.stack || e.message) || e));
  }
  function sound(name, so) {
    soundAt.set(name, ctx.time.real);
    if (ctx.audio) { try { return ctx.audio.play(name, so); } catch (e) { /* optional peer */ } }
    return null;
  }
  const playedRecently = (name, sec) => { const t = soundAt.get(name); return t !== undefined && ctx.time.real - t < sec; };
  const presentOf = (a) => (a && a.spec.present) || null;
  const indexOf = (a) => (a && a.team === 'hero' ? 0 : 1);
  /** Handlers of an attack: present.moves[id] or present.moves[slot]. */
  function moveHandlers(a, id) {
    const pr = presentOf(a);
    const t = pr && pr.moves;
    if (!t || !id) return null;
    if (t[id]) return t[id];
    const def = a.spec.attacks && a.spec.attacks[id];
    return def && def.slot && t[def.slot] ? t[def.slot] : null;
  }

  // ---- phantom foe: handlers may address 'foe.*' with nothing targeted ------------------------------------------------
  const phantom = (() => {
    const root = new THREE.Object3D();
    const sockets = {};
    for (const [n, y] of [['chest', 1.35], ['head', 1.75], ['hips', 1.0], ['footL', 0], ['footR', 0], ['handL', 1.1], ['handR', 1.1], ['back', 1.3], ['weaponTip', 1.2], ['weaponBase', 1.1]]) {
      const s = new THREE.Object3D(); s.position.set(0, y, 0); root.add(s); sockets[n] = s;
    }
    const pos = { x: 0, y: 0, z: 0 };
    return {
      phantom: true, id: -1, pos, prev: pos, yaw: 0, scale: 1, height: 1.9, radius: 0.4, alive: false, cine: false, team: 'none', spec: {},
      char: { root, sockets, flash() {}, impulse() {}, setVisible() {} },
      view: { play() {}, setOffset() {}, impulse() {}, flash() {}, glow() {}, weaponGlow: { color: new THREE.Color(), amount: 0, dur: 0, t: 0, on: false }, palette: paletteOf('ember'), element: 'ember', pos: new THREE.Vector3() },
      clips: { state: () => ({ name: 'demo.idle', duration: 1 }), move: () => ({ name: 'demo.idle', map: (t) => t, startup: 0.2 }) },
      at(f, u, s, out = new THREE.Vector3()) { return out.set(pos.x - f * fwdX(this.yaw), u, pos.z - f * fwdZ(this.yaw)); },
      socket(name, out = new THREE.Vector3()) { return (sockets[name] || sockets.chest).getWorldPosition(out); },
      place(a) {
        pos.x = a.pos.x + fwdX(a.yaw) * 2.2; pos.z = a.pos.z + fwdZ(a.yaw) * 2.2;
        this.yaw = a.yaw + Math.PI;
        root.position.set(pos.x, 0, pos.z); root.rotation.y = this.yaw; root.updateMatrixWorld(true);
        return this;
      },
    };
  })();

  // ---- the helper ---------------------------------------------------------------------------------------------------
  function helperOf(a) {
    let h = helpers.get(a.id);
    if (!h || h.owner !== a) { h = makeHelper(a); helpers.set(a.id, h); }
    return h;
  }

  /** View of one side: who() returns the actor (the owner, or its current foe). */
  function view(index, who, isFoe) {
    const cache = { actor: null, char: null, sockets: null, src: null };
    const refresh = () => {
      const a = who();
      if (cache.src === a) return a;
      cache.src = a;
      const c = a.char;
      cache.sockets = c && c.sockets ? proxySockets(c.sockets) : {};
      if (c) {
        cache.char = Object.create(c);
        Object.defineProperty(cache.char, 'root', { value: c.root ? proxy(c.root) : null });
        Object.defineProperty(cache.char, 'sockets', { value: cache.sockets });
      } else cache.char = null;
      cache.actor = { index, char: cache.char, clips: a.clips, get cine() { return a.cine; }, play: (n, po) => a.view.play(n, po), rpg: a };
      return a;
    };
    const v = {
      index,
      get actor() { refresh(); return cache.actor; },
      get char() { refresh(); return cache.char; },
      get sockets() { refresh(); return cache.sockets; },
      get rpg() { return who(); },
      get fighter() { return fighterOf(who(), isFoe); },
      get facing() { return isFoe ? -1 : 1; },
      /** stage point in this side's frame (u = height above the floor) */
      at(f = 0, u = 0, s = 0) {
        const a = who(), fr = currentFrame() || actorFrame(a);
        const p = worldToStage(new THREE.Vector3(a.view && a.view.pos ? a.view.pos.x : a.pos.x, 0, a.view && a.view.pos ? a.view.pos.z : a.pos.z), fr);
        p.x += f * (isFoe ? -1 : 1); p.y = u; p.z += s;
        return p;
      },
      /** stage position of a socket of this side */
      socket(name) {
        const a = who(), fr = currentFrame() || actorFrame(a);
        return worldToStage(a.socket(name, new THREE.Vector3()), fr);
      },
      play(clip, po = {}) { const a = who(); if (a.cine && a.view) a.view.play(clip, { fade: 0.08, restart: true, ...po }); },
      offset(to, dur = 0.25, ease = 'inOutSine') { const a = who(); if (a.view) a.view.setOffset(to, dur, ease); },
      impulse(dir = [-1, 0.1, 0], amount = 1, bone) { const a = who(); if (a.view) a.view.impulse(dir, amount, bone); },
      flash(color = [3, 2, 1.4], amount = 1, dur = 0.15) { const a = who(); if (a.view) a.view.flash(color, amount, dur); },
      glow(color, amount = 1, dur = 0, fadeIn = 0.1) { const a = who(); if (a.view && a.view.glow) a.view.glow(color, amount, dur, fadeIn); },
      weaponGlow(amount = 1, dur = 0.5, color) {
        const a = who();
        const w = a.view && a.view.weaponGlow;
        if (!w) return;
        const c = color || a.view.palette.core;
        if (Array.isArray(c)) w.color.setRGB(c[0] * 0.25, c[1] * 0.25, c[2] * 0.25); else w.color.set(c);
        w.amount = amount; w.dur = dur; w.t = 0; w.on = amount > 0;
      },
      afterimage(ao = {}) { const a = who(); return a.char && a.char.root && !a.phantom ? fx.call('afterimage', a.char.root, { palette: a.view.element === 'steel' ? 'frost' : a.view.element, intensity: 0.7, ...ao }) : fx.NULL; },
      setVisible(b) { const a = who(); if (a.char && a.char.setVisible) a.char.setVisible(b); },
    };
    return v;
  }

  /** Rules-state stand-in (h.fighter / h.foeFighter): what the fighters' handlers read. */
  function fighterOf(a, isFoe) {
    const fr = currentFrame() || actorFrame(a);
    const p = worldToStage(new THREE.Vector3(a.pos.x, 0, a.pos.z), fr);
    return {
      x: p.x, y: a.pos.y, facing: isFoe ? -1 : 1, hp: a.hp || 0, hpMax: a.hpMax || 1, fp: a.fp || 0, ult: a.ult || 0,
      state: a.state || 'idle', move: a.attack ? a.attack.id : null, moveTime: a.attack ? a.attack.t : 0,
      combo: { hits: cine ? cine.ticks + 1 : 1, damage: 0 }, hitstop: 0,
    };
  }

  function makeHelper(actor) {
    const index = indexOf(actor);
    const el = actor.view ? actor.view.element : 'ember';
    const foeOf = () => {
      const f = h._foe || (actor.attack && actor.attack.target) || actor.target;
      return f && !f.gone ? f : phantom.place(actor);
    };
    const self = view(index, () => actor, false), foe = view(1 - index, foeOf, true);
    const tmp = new THREE.Vector3();
    const frame = () => currentFrame() || actorFrame(actor);
    const toW = (v) => stageToWorld(v.clone ? v.clone() : new THREE.Vector3(v[0], v[1], v[2]), frame());

    /** Position spec -> stage Vector3 (new object). */
    function pos(spec) {
      if (spec == null) return self.socket('chest');
      if (spec.isVector3) return spec.clone();
      if (Array.isArray(spec)) return self.at(spec[0], spec[1], spec[2]);
      if (typeof spec === 'string') {
        if (spec === 'contact') { const e = h.e; return e && e.x !== undefined ? new THREE.Vector3(e.x, e.y ?? 1.2, 0.12) : foe.socket('chest'); }
        if (spec === 'self') return self.socket('chest');
        if (spec === 'foe') return foe.socket('chest');
        if (spec === 'floor') return self.at(0, 0.02, 0);
        if (spec === 'foe.floor') return foe.at(0, 0.02, 0);
        if (spec.startsWith('foe.')) return foe.socket(spec.slice(4));
        return self.socket(spec);
      }
      if (spec.isObject3D) return worldToStage(unwrap(spec).getWorldPosition(new THREE.Vector3()), frame());
      if (typeof spec === 'object') {
        const who = spec.of === 'foe' ? foe : self;
        const base = spec.socket ? who.socket(spec.socket) : spec.pos !== undefined ? pos(spec.pos) : who.at(0, 0, 0);
        if (spec.offset) base.add(tmp.set(spec.offset[0] * who.facing, spec.offset[1] || 0, spec.offset[2] || 0));
        return base;
      }
      return self.socket('chest');
    }
    function dir(spec) {
      if (spec == null) return new THREE.Vector3(1, 0, 0);
      if (spec.isVector3) return spec.clone().normalize();
      return new THREE.Vector3(spec[0], spec[1] || 0, spec[2] || 0).normalize();
    }
    function atObj(where) {
      const isAt = where && typeof where === 'object' && !Array.isArray(where) && !where.isVector3 && !where.isObject3D &&
        ('pos' in where || 'dir' in where || 'scale' in where || 'color' in where || 'target' in where) && !('socket' in where) && !('of' in where);
      const at = { pos: pos(isAt ? where.pos : where), facing: 1 };
      if (isAt) {
        if (where.dir !== undefined) at.dir = dir(where.dir);
        if (where.scale !== undefined) at.scale = where.scale;
        if (where.color !== undefined) at.color = where.color;
        if (where.target !== undefined) at.target = typeof where.target === 'object' && where.target.isObject3D ? where.target : pos(where.target);
      }
      return at;
    }
    const socketObj = (name) => {
      const isF = name.startsWith('foe.');
      const a = isF ? foeOf() : actor;
      const n = isF ? name.slice(4) : name;
      return a.char && a.char.sockets ? a.char.sockets[n] || null : null;
    };

    const h = {
      owner: actor, index, id: actor.spec.hero || actor.kind, element: el, ctx, shots: SHOTS, Ease, THREE,
      get palette() { return actor.view.palette; },
      get vfx() { return ctx.vfx; },
      get rng() { return world.rng; },
      e: null, data: null, _foe: null,
      self, foe,
      get fighter() { return fighterOf(actor, false); },
      get foeFighter() { return fighterOf(foeOf(), true); },
      get facing() { return 1; },
      get t() { return actor.attack ? actor.attack.t : 0; },
      get move() { return actor.attack ? actor.attack.id : cine ? cine.move : null; },
      get lockTime() { return world.lock ? world.lock.t : null; },
      pos, dir,
      at: (f, u, s) => self.at(f, u, s),
      socket: (name) => pos(name),
      color(key = 'core', k = 1) { const c = h.palette[key] || h.palette.core; return [c[0] * k, c[1] * k, c[2] * k]; },
      /** the RPG actor / world behind this helper (new code may use them; the fighters' handlers do not) */
      actor, world,

      fx(name, where, opts = {}) { return fx.play(name, atObj(where), { element: h.element, ...opts }, opts.fallback ?? 'game.burst'); },
      burst(def, where, bo = {}) { const a = atObj(where); return fx.call('burst', def, { ...a, ...bo, pos: a.pos }); },
      emitter(def, where, eo = {}) {
        const { follow, ...rest } = eo;
        const em = fx.call('emitter', def, { ...atObj(where), ...rest });
        if (follow && em.follow) { const t = typeof follow === 'string' ? socketObj(follow) : follow; if (t) em.follow(t); }
        return em;
      },
      spawn(kind, where, so = {}) { const a = atObj(where); return fx.call(kind, { palette: h.element, facing: 1, dir: a.dir, ...so, pos: a.pos }); },
      light(where, lo = {}) { return fx.call('light', { color: h.palette.core, intensity: 120, range: 6, duration: 0.3, ...lo, pos: pos(where) }); },
      flare(where, fo = {}) { return fx.call('flare', { color: h.palette.core, ...fo, pos: pos(where) }); },
      distort(where, d = {}) { return fx.call('distort', { ...d, pos: pos(where) }); },
      trail: { start(to) { actor.view.trailStart(to); }, stop() { actor.view.trailStop(); } },
      afterimage: (ao) => self.afterimage(ao),
      glow: (c, a, d, fi) => self.glow(c ?? h.palette.core, a, d, fi),
      flash: (c, a, d) => self.flash(c ?? h.color('core', 0.5), a, d),
      weaponGlow: (a, d, c) => self.weaponGlow(a, d, c),
      impulse(dirv = [-1, 0.1, 0], amount = 1, who = 'foe') { (who === 'self' ? self : foe).impulse(dirv, amount); },
      play: (clip, po) => self.play(clip, po),
      foePlay: (clip, po) => foe.play(clip, po),
      offset: (to, d, e) => self.offset(to, d, e),
      foeOffset: (to, d, e) => foe.offset(to, d, e),

      cam: {
        shake: (a, so) => ctx.cam && ctx.cam.shake(a, so && so.dir ? { ...so, dir: dirToWorld(new THREE.Vector3(so.dir[0], so.dir[1], so.dir[2]), frame()) } : so),
        kick: (ko) => ctx.cam && ctx.cam.kick(ko && ko.offset ? { ...ko, offset: dirToWorld(new THREE.Vector3(ko.offset[0], ko.offset[1], ko.offset[2]), frame()) } : ko),
        zoom: (f, d) => world.camera && world.camera.zoom(f, d),
        play: (shots, co = {}) => camPlay(actor, shots, co),
        stop: (b) => { void b; if (world.camera && world.camera.cinematic) world.camera.endCine(false); },
        letterbox: (on, d) => ctx.cam && ctx.cam.letterbox(on, d),
      },
      audio(name, ao = {}) { return sound(name, { ...ao, pos: ao.pos ? toW(ao.pos.isVector3 ? ao.pos : pos(ao.pos)) : actor.socket('chest', new THREE.Vector3()) }); },
      post: {
        pulse: (k, a, po) => ctx.post.pulse(k, a, po),
        flash: (c = 0xffffff, a = 0.6, po) => ctx.post.flash(c, a, po),
        impact: (po) => ctx.post.impactFrame(po),
        radial(where, amount = 0.4, po = {}) { ctx.post.radialAt(toW(pos(where ?? 'contact'))); ctx.post.pulse('radial', amount, { attack: 0.01, hold: 0.03, release: 0.3, ...po }); },
        chroma: (amount = 0.5, po = {}) => ctx.post.pulse('chroma', amount, { release: 0.3, ...po }),
      },
      mood(m) { if (ctx.env) ctx.env.setMood(m); },
      pulse(where, color, strength = 1) { if (ctx.env) ctx.env.pulse(toW(pos(where ?? 'floor')), color || h.palette.core, strength); },
      slowmo: (scale, dur, so) => ctx.time.slowmo(scale, dur, so),
      hitstop: (sec) => ctx.time.hitstop(sec),
      after(sec, fn) {
        const e = h.e, foeNow = h._foe;
        if (!ctx.vfx) return null;
        return ctx.vfx.schedule(sec, () => call(actor, fn, 'after', e, null, foeNow));
      },
      announce(text, ao = {}) { world.emit('announce', { text, ...ao, actor }); return null; },
      defaultFeel() { if (h.e && h.e.rpg) (h.e.rpg.blocked ? feel.guard : feel.hit)(h.e.rpg); },
    };
    return h;
  }

  /** Call a content handler safely in a stage frame; returns its result (undefined when missing). */
  function call(a, fn, key, e, frame, foe) {
    if (typeof fn !== 'function' || !a || a.gone) return undefined;
    const h = helperOf(a);
    const pe = h.e, pd = h.data, pf = h._foe;
    h.e = e || null;
    h.data = (e && e.data) || null;
    if (foe !== undefined) h._foe = foe;
    try {
      return withFrame(frame || currentFrame() || actorFrame(a), () => fn(h, e));
    } catch (err) { warnOnce((a.spec.hero || a.kind) + '.' + key, err); return undefined; } finally { h.e = pe; h.data = pd; h._foe = pf; }
  }

  // ---- camera routing -------------------------------------------------------------------------------------------------
  /** Is an ultimate (super-freeze, opener or lock) of this actor being presented: cinematic cameras are allowed. */
  const ultActive = (a) => !!(ultState && ultState.actor === a) || !!(world.lock && world.lock.attacker === a);
  function camPlay(a, shots, co = {}) {
    if (!world.camera || !shots || !shots.length) return NULL_CAM;
    if (!co.force && !ultActive(a)) return NULL_CAM;     // skill cameras never take the third-person view away
    const h = helperOf(a);
    const foe = h._foe || (world.lock && world.lock.attacker === a ? world.lock.victim : a.target) || null;
    return world.camera.cine(shots, { ...co, anchor: a, target: foe }) || NULL_CAM;
  }
  // choreography that calls ctx.cam.play directly lands in the same place
  const director = ctx.cam;
  if (director && !director._rpgPlay) {
    director._rpgPlay = director.play;
    director.play = (shots, po = {}) => {
      const hero = world.hero;
      if (!hero) return NULL_CAM;
      if (po.anchor !== undefined && typeof po.anchor !== 'number') {
        // a world-space point source: play it as it is in an identity stage (world = stage)
        world.camera.adoptDirector({ pos: { x: 0, z: 0 }, yaw: 0 }, 1);
        return director._rpgPlay.call(director, shots, { ...po, blendOut: 0 });
      }
      const a = po.anchor === 1 ? (world.lock ? world.lock.victim : hero.target) || hero : hero;
      const { anchor, target, ...rest } = po;
      void anchor; void target;
      return camPlay(a, shots, rest);
    };
  }

  // ---- event queue ----------------------------------------------------------------------------------------------------
  const QUEUED = ['attackStart', 'attackEnd', 'marker', 'hit', 'guard', 'perfectGuard', 'guardBreak', 'counter', 'roll', 'dodge', 'step', 'land', 'teleport',
    'projectileSpawn', 'projectileActive', 'projectileExpire'];
  const offs = QUEUED.map((name) => world.on(name, (e) => {
    // the frame of the moment (the actor may have moved by the time the queue is flushed)
    let frame = null;
    const a = e.actor || e.attacker || e.owner;
    if (name === 'hit' || name === 'guard' || name === 'perfectGuard' || name === 'guardBreak') frame = a ? actorFrame(a, e.pos) : null;
    else if (name.startsWith('projectile')) frame = feel.projFrame(e.projectile);
    else if (a) frame = actorFrame(a);
    queue.push(name, e, frame);
  }));

  function flush() {
    if (!queue.length) return;
    const q = queue.splice(0, queue.length);
    for (let k = 0; k < q.length; k += 3) {
      try { dispatch(q[k], q[k + 1], q[k + 2]); } catch (err) { warnOnce('dispatch.' + q[k], err); }
    }
  }

  /** Duel-shaped hit payload for the handlers (stage space of `frame`). */
  function hitPayload(e, frame) {
    const p = worldToStage(new THREE.Vector3(e.pos.x, e.pos.y, e.pos.z), frame);
    return {
      attacker: indexOf(e.attacker), defender: indexOf(e.victim), move: e.id, kind: e.kind === 'projectile' ? 'projectile' : 'strike',
      level: e.level, damage: e.damage, blocked: !!e.blocked, perfect: !!e.perfect, guardBreak: !!e.guardBreak, armoured: !!e.armoured,
      counter: !!e.crit, ko: !!e.killed, front: e.front, hitstop: e.hitstop, x: p.x, y: p.y, facing: 1,
      combo: 1, comboDamage: e.damage, label: e.hit ? e.hit.label : null, projectile: e.projectile ? e.projectile.id : undefined, rpg: e,
    };
  }
  function projPayload(p, frame, e) {
    const s = worldToStage(new THREE.Vector3(p.x, p.y, p.z), frame);
    return { id: p.id, owner: indexOf(p.owner), kind: p.kind, x: s.x, y: p.y, vx: p.speed, vy: p.vy, facing: 1, delay: p.delay, lifetime: p.lifetime, data: p.data, reason: e.reason, rpg: e };
  }

  function dispatch(name, e, frame) {
    switch (name) {
      case 'attackStart': {
        const a = e.actor;
        if (a.gone) break;
        const mh = moveHandlers(a, e.id);
        const pe = { fighter: indexOf(a), move: e.id, group: e.attack.group, forced: e.inst.forced, rpg: e };
        if (mh) call(a, mh.start, e.id + '.start', pe, frame);
        feel.moveStart(e);
        break;
      }
      case 'marker': {
        const a = e.actor;
        if (a.gone) break;
        const mh = moveHandlers(a, e.id);
        const pe = { fighter: indexOf(a), move: e.id, name: e.name, data: e.data, t: e.t, cinematic: !!e.cinematic, rpg: e };
        let r, own = false;
        if (mh && typeof mh[e.name] === 'function') { own = true; r = call(a, mh[e.name], e.id + '.' + e.name, pe, frame); }
        const pr = presentOf(a);
        const on = pr && pr.markers;
        if (on && typeof on[e.name] === 'function') { own = true; if (call(a, on[e.name], 'markers.' + e.name, pe, frame) === false) r = false; }
        if (e.cinematic && cine && pr && pr.ult && pr.ult.markers && typeof pr.ult.markers[e.name] === 'function') call(a, pr.ult.markers[e.name], 'ult.markers.' + e.name, pe, frame);
        if (r !== false) feel.marker(e, own);
        break;
      }
      case 'attackEnd': {
        const a = e.actor;
        const mh = moveHandlers(a, e.id);
        const pe = { fighter: indexOf(a), move: e.id, reason: e.reason, connected: e.connected, rpg: e };
        if (mh && !a.gone) {
          if (!e.connected && e.reason === 'complete') call(a, mh.whiff, e.id + '.whiff', pe, frame);
          call(a, mh.end, e.id + '.end', pe, frame);
        }
        ultMoveEnd(e);
        break;
      }
      case 'hit': case 'guard': case 'perfectGuard': case 'guardBreak': {
        const a = e.attacker;
        const blocked = name !== 'hit';
        let r, r2;
        if (a && !a.gone && frame) {
          const pe = hitPayload(e, frame);
          const pr = presentOf(a);
          const handler = e.kind === 'projectile' && e.projectile ? (pr && pr.projectiles ? pr.projectiles[e.projectile.kind] : null) : moveHandlers(a, e.id);
          const key = blocked ? 'guard' : 'hit';
          if (handler && !e.killed) r = call(a, handler[key], e.id + '.' + key, pe, frame, e.victim);
          const onAll = pr && pr.on && pr.on[key];
          if (onAll && !e.killed) r2 = call(a, onAll, 'on.' + key, pe, frame, e.victim);
          if (e.killed && pr && pr.on && pr.on.ko) call(a, pr.on.ko, 'on.ko', { fighter: indexOf(e.victim), by: indexOf(a), cinematic: false, rpg: e }, frame, e.victim);
        }
        if (e.kind === 'projectile' && e.projectile) feel.projectileHit(e.projectile, e);
        if (r !== false && r2 !== false) (blocked ? feel.guard : feel.hit)(e);
        else if (e.victim.view && e.hitstop > 0) e.victim.view.shake = 1;
        // the victim's own reaction hook (kinds: armour sparks, boss roars ...)
        const vp = presentOf(e.victim);
        if (vp && vp.on && vp.on.hurt && !e.victim.gone) call(e.victim, vp.on.hurt, 'on.hurt', { rpg: e }, null, a);
        if (!blocked && e.attack && e.hit && e.hit.cinematic && e.attack.cinematic && a && !a.gone) ultConnect(a, e.victim, e);
        break;
      }
      case 'counter': {
        const a = e.actor;
        const mh = moveHandlers(a, e.id);
        const r = mh ? call(a, mh.counter, e.id + '.counter', { fighter: indexOf(a), move: e.id, rpg: e }, frame, e.attacker) : undefined;
        if (r !== false) feel.counter(e);
        break;
      }
      case 'projectileSpawn': case 'projectileActive': case 'projectileExpire': {
        const p = e.projectile;
        const pr = presentOf(p.owner);
        const ph = pr && pr.projectiles ? pr.projectiles[p.kind] : null;
        const key = name === 'projectileSpawn' ? 'spawn' : name === 'projectileActive' ? 'active' : 'expire';
        let r;
        if (ph && !p.owner.gone) r = call(p.owner, ph[key], 'projectiles.' + p.kind + '.' + key, projPayload(p, frame, e), frame);
        if (name === 'projectileSpawn') feel.projectileSpawn(p, r === false);
        else if (name === 'projectileActive') feel.projectileActive(p);
        else feel.projectileExpire(p, e.reason);
        break;
      }
      case 'roll': {
        const pr = presentOf(e.actor);
        const r = pr && pr.on && pr.on.dodge ? call(e.actor, pr.on.dodge, 'on.dodge', { fighter: indexOf(e.actor), kind: 'roll', rpg: e }, frame) : undefined;
        if (r !== false) feel.roll(e);
        break;
      }
      case 'dodge': {
        const pr = presentOf(e.actor);
        const r = e.perfect && pr && pr.on && pr.on.perfectDodge ? call(e.actor, pr.on.perfectDodge, 'on.perfectDodge', { fighter: indexOf(e.actor), rpg: e }, frame) : undefined;
        if (r !== false) feel.dodge(e);
        break;
      }
      case 'teleport': {
        const pr = presentOf(e.actor);
        const r = pr && pr.on && pr.on.teleport ? call(e.actor, pr.on.teleport, 'on.teleport', { fighter: indexOf(e.actor), from: worldToStage(new THREE.Vector3(e.fromX, 0, e.fromZ), frame).x, rpg: e }, frame) : undefined;
        if (r !== false) feel.teleport(e);
        break;
      }
      case 'step': feel.step(e); break;
      case 'land': feel.land(e); break;
      default:
    }
  }

  // ---- ultimates: super-freeze, lock, strike ----------------------------------------------------------------------------
  function ultName(a) {
    const r = a.spec.hero ? rosterEntry(a.spec.hero) : null;
    const m = r && r.moves.find((x) => x.slot === 'ult');
    return m ? { name: m.name, nameEn: m.nameEn } : { name: '궁극기', nameEn: 'ULTIMATE' };
  }
  const ultOf = (a) => { const pr = presentOf(a); return (pr && pr.ult) || {}; };
  const moodOf = (a) => ultOf(a).mood || (a.spec.hero ? rosterEntry(a.spec.hero).mood : null) || { darken: 0.75 };

  /** Called by the actor machine when a move with a super-freeze starts: freeze the world around its user. */
  function superFreeze(a, inst) {
    const dur = inst.def.superFreeze.duration;
    world.freeze = { owners: [a], left: dur, onEnd: null };
    ultState = { actor: a, move: inst.id, cine: false, cam: null, connected: false };
    queueDirect(() => ultFreeze(a, { fighter: indexOf(a), move: inst.id, duration: dur }));
  }
  const direct = [];
  function queueDirect(fn) { direct.push(fn); }

  function ultFreeze(a, e) {
    if (a.gone) return;
    const h = helperOf(a);
    const ult = ultOf(a);
    const r = call(a, ult.freeze, 'ult.freeze', e);
    if (r === false) return;
    if (ctx.env) ctx.env.setMood({ ...moodOf(a), duration: 0.25 });
    if (world.camera) {
      ultState.cam = world.camera.cine([
        SHOTS.heroPushIn({ dur: e.duration + 0.12, clock: 'real', letterbox: true, roll: 5 }),
        SHOTS.weaponFollow({ dur: 1.2, hold: true, cut: 0.18 }),
      ], { anchor: a, target: a.target, blendOut: 0.45, keepLetterbox: true });
    }
    const n = ultName(a);
    world.emit('announce', { text: n.name, sub: n.nameEn, style: 'ult', actor: a });
    sound('ult_start');
    if (ctx.audio) ctx.audio.music('ultimate');
    withFrame(actorFrame(a), () => {
      h.glow(h.color('mid', 0.035), 1, e.duration + 0.5, 0.15);
      h.weaponGlow(0.4, e.duration + 0.6);
      const behind = h.socket('chest');
      behind.z -= 1.0; behind.y += 0.15;
      fx.play('combat.ult.flash', { pos: behind, facing: 1, scale: 0.55 }, { element: h.element, intensity: 0.4 }, null);
      const tip = a.char && a.char.sockets ? a.char.sockets.weaponTip : null;
      if (fx.has('combat.charge.gather')) fx.play('combat.charge.gather', { pos: h.socket('weaponTip'), facing: 1 }, { element: h.element, duration: e.duration * 0.9, follow: tip });
    });
    ctx.post.pulse('exposure', -0.15, { attack: 0.1, hold: Math.max(0.05, e.duration - 0.2), release: 0.3 });
  }

  /** The ultimate move ended: without a lock / strike, undo the super-freeze presentation. */
  function ultMoveEnd(e) {
    const st = ultState;
    if (!st || st.actor !== e.actor || st.move !== e.id) return;
    if (st.cine || st.strike || e.reason === 'cinematic') return;
    ultState = null;
    call(e.actor, ultOf(e.actor).whiff, 'ult.whiff', { fighter: indexOf(e.actor), move: e.id, reason: e.reason });
    restoreWorld(0.5);
  }
  function restoreWorld(camBlend = 0.6) {
    if (ctx.env) ctx.env.setMood(null);
    if (world.camera && world.camera.cinematic) world.camera.endCine(false, camBlend);
    if (ctx.cam) ctx.cam.letterbox(false, 0.5);
    if (ctx.audio) ctx.audio.music(world.flow && world.flow.music ? world.flow.music() : 'battle', { fade: 1.5 });
  }

  /** The opener of an ultimate landed clean: lock a lockable victim, strike everything else. */
  function ultConnect(a, v, e) {
    if (world.lock || !ultState || ultState.actor !== a) return;
    const def = e.attack;
    const lockable = v.alive && !v.spec.boss && v.spec.lockable !== false && v.scale <= 1.5 && !v.immovable;
    if (lockable) startLock(a, v, def);
    else if (v.alive) strike(a, v, def);
  }

  // .. the lock: logic side (stepped by world.step) ......................................................................
  function startLock(a, v, def) {
    const c = def.cinematic;
    const dist = c.distance ?? a.radius + v.radius + 0.5;
    // room for the pair: pull both inside the arena
    const R = world.arena.radius - 1.2;
    let vx = a.pos.x + fwdX(a.yaw) * dist, vz = a.pos.z + fwdZ(a.yaw) * dist;
    const d = hypot2(vx, vz);
    if (d > R) { const k = (d - R) / d; a.pos.x -= vx * k; a.pos.z -= vz * k; vx -= vx * k; vz -= vz * k; }
    if (a.attack) a.endAttack('cinematic');
    v.endAttack('interrupted');
    v.pos.x = vx; v.pos.z = vz; v.pos.y = 0; a.pos.y = 0;
    v.yaw = yawTo(a.pos.x - v.pos.x, a.pos.z - v.pos.z);
    v.vel.x = v.vel.y = v.vel.z = 0;
    for (const x of [a, v]) { x.prev.x = x.pos.x; x.prev.y = 0; x.prev.z = x.pos.z; x.prevYaw = x.yaw; x.cine = true; x.cineInvuln = true; x.setState('cine'); x.view.key = ''; }
    world.lock = { attacker: a, victim: v, def, c, t: 0, done: false, lethal: false };
    world.freeze = { owners: [a, v], left: Infinity, onEnd: null };
    ultState.cine = true;
    queueDirect(() => cineStart(a, v, def));
  }

  /** Advance the lock clock (world.step). */
  function stepLock(dt) {
    const L = world.lock;
    if (!L) return;
    const tp = L.t;
    L.t += dt;
    const { attacker: a, victim: v, c, def } = L;
    for (let i = 0; i < c.markers.length; i++) {
      const m = c.markers[i];
      if (passes(m.t, tp, L.t)) world.emit('marker', { actor: a, attack: def, id: def.id, name: m.name, data: m.data, t: m.t, cinematic: true, inst: null });
    }
    for (let i = 0; i < c.ticks.length; i++) {
      const tk = c.ticks[i];
      if (passes(tk.t, tp, L.t)) tick(L, tk, false);
    }
    if (!L.finished && passes(c.finish.t, tp, L.t)) { L.finished = true; tick(L, c.finish, true); }
    if (L.t >= c.duration - 1e-6) endLock();
    void v;
  }
  function tick(L, tk, final) {
    const { attacker: a, victim: v, def } = L;
    const mul = a.mult.damage * (a.derived ? a.derived.arcane : 1) * (v.spec.taken ?? 1);
    let dmg = Math.round(tk.damage * mul);
    if (!final) dmg = Math.min(dmg, Math.max(0, v.hp - 1));     // the lock kills on its finish, never mid-way
    v.hp = Math.max(0, v.hp - dmg);
    if (final && v.hp <= 0) L.lethal = true;
    const pos = v.socket('chest', new THREE.Vector3());
    const ev = { attacker: a, victim: v, attack: def, hit: null, id: def.id, kind: 'tick', damage: dmg, level: final ? 'knockdown' : 'heavy', reaction: '', armoured: false, blocked: false,
      pos: { x: pos.x, y: pos.y, z: pos.z }, dirX: fwdX(a.yaw), dirZ: fwdZ(a.yaw), hitstop: tk.hitstop, killed: false, front: true, crit: final, final, marker: tk.marker };
    world.emit('tick', ev);
    if (tk.marker) world.emit('marker', { actor: a, attack: def, id: def.id, name: tk.marker, data: tk.data, t: tk.t, cinematic: true, inst: null });
    queueDirect(() => cineTick(L, { attacker: indexOf(a), defender: indexOf(v), move: def.id, damage: dmg, hitstop: tk.hitstop, marker: tk.marker, data: tk.data, final, t: tk.t, cinematic: true, rpg: ev }));
  }
  function endLock() {
    const L = world.lock;
    if (!L) return;
    const { attacker: a, victim: v, c } = L;
    world.lock = null;
    world.freeze = null;
    for (const x of [a, v]) { x.cine = false; x.cineInvuln = false; x.view.key = ''; x.view.setOffset([0, 0], 0.3); x.view.glow(null); }
    if (a.char && a.char.setFacing) a.char.setFacing(1);
    if (!a.dead) a.setState('idle');
    if (L.lethal || v.hp <= 0) { v.vel.x = fwdX(a.yaw) * c.finish.kx * 0.6; v.vel.z = fwdZ(a.yaw) * c.finish.kx * 0.6; v.setState('idle'); v.die(a); }
    else {
      v.setState('idle');
      v.stun('knockdown', 0, { vx: fwdX(a.yaw) * c.finish.kx * 0.7, vz: fwdZ(a.yaw) * c.finish.kx * 0.7, vy: Math.max(2.5, c.finish.ky * 0.8), by: a });
    }
    a.invulnT = 0.4;
    queueDirect(() => cineEnd(L));
  }

  // .. the lock: presentation side ..........................................................................................
  function genericUltShots(D, cdef) {
    const F = cdef.finish ? Math.min(D - 0.3, cdef.finish.t) : D * 0.7;
    const mid = Math.max(0.5, F - 1.05);
    const last = Math.max(0.4, D - (0.5 + mid + 0.55));
    return [
      SHOTS.impactPunchIn({ dur: 0.5, shake: 0.6 }),
      SHOTS.orbitSweep({ dur: mid, cut: 0.22, from: -50, to: 30, radius: [5.6, 4.8], height: [1.1, 2.1], handheld: 0.4 }),
      SHOTS.crashZoom({ dur: 0.55, dist: [9, 3.2], shake: 0.4 }),
      SHOTS.wideEstablishing({ dur: last, dist: [10, 11.5], height: [2.2, 3.0], shake: { amount: 1, at: 0.03, freq: 11 } }),
    ];
  }
  function cineStart(a, v, def) {
    const h = helperOf(a);
    const ult = ultOf(a);
    const at = (ult.at || []).map((x) => ({ t: x.t, do: x.do, done: false })).sort((p, q) => p.t - q.t);
    cine = { attacker: a, victim: v, move: def.id, duration: def.cinematic.duration, at, generic: !ult.at, cdef: def.cinematic, cam: null, ticks: 0 };
    h._foe = v;
    let shots = null;
    try { shots = withFrame(actorFrame(a), () => (typeof ult.shots === 'function' ? ult.shots(h) : ult.shots)); } catch (err) { warnOnce((a.spec.hero || a.kind) + '.ult.shots', err); }
    if (!shots || !shots.length) shots = genericUltShots(cine.duration, cine.cdef);
    if (world.camera) cine.cam = world.camera.cine(shots, { anchor: a, target: v, blendOut: ult.blendOut ?? 0.7, keepLetterbox: true });
    if (ctx.cam) ctx.cam.letterbox(true, 0.2);
    const pe = { attacker: indexOf(a), defender: indexOf(v), move: def.id, duration: cine.duration };
    const r = call(a, ult.start, 'ult.start', pe, null, v);
    if (r !== false) feel.cineStart(a, v);
    if (cine.generic) v.view.play(v.clips.state('locked').name, { fade: 0.05, restart: true });
  }
  function settleAfter(A, name, startAt) {
    const dur = A.char.clip === name ? A.char.clipDuration : 0.6;
    helperOf(A).after(Math.max(0.1, dur - startAt - 0.05), () => { if (A.cine && A.char.clip === name) A.view.play(A.clips.state('idle').name, { fade: 0.25 }); });
  }
  function cineTick(L, e) {
    if (!cine) return;
    const a = cine.attacker, v = cine.victim;
    cine.ticks++;
    const ult = ultOf(a);
    const r = call(a, ult.tick, 'ult.tick', e, null, v);
    if (r !== false) feel.cineTick(a, v, e);
    if (!cine.generic) return;
    // default choreography of a lock: a cut per tick, a slam on the finish
    const H = helperOf(a);
    withFrame(actorFrame(a), () => {
      if (!e.final) {
        const ids = CUT_SLOTS.map((s) => a.spec.slots && a.spec.slots[s]).filter(Boolean);
        const id = ids.length ? ids[cine.ticks % ids.length] : null;
        if (id) { const mc = a.clips.move(id); const startAt = Math.max(0, mc.map(mc.startup) - 0.1); a.view.play(mc.name, { fade: 0.05, restart: true, startAt }); settleAfter(a, mc.name, startAt); }
        v.view.play(v.clips.state('hitHeavy').name, { fade: 0, restart: true, startAt: 0.06 });
        v.view.impulse([-1, 0.1, 0.15], 1.1);
        a.view.trailStart({ life: 0.16 });
        H.after(0.12, () => a.view.trailStop());
        return;
      }
      const mc = a.clips.move(cine.move);
      const startAt = Math.max(0, mc.map(mc.startup) - 0.08);
      a.view.play(mc.name, { fade: 0.05, restart: true, startAt });
      settleAfter(a, mc.name, startAt);
      v.view.play(v.clips.state('fall').name, { fade: 0.04, restart: true });
      v.view.setOffset([-0.5, 0.35], 0.16, 'outQuad');
      v.view.impulse([-1, -0.3, 0], 2);
      H.after(0.18, () => { if (v.cine) v.view.setOffset([-0.75, 0], 0.14, 'inQuad'); });
      H.after(0.32, () => { if (!v.cine) return; v.view.play(v.clips.state('down').name, { fade: 0.08, restart: true }); v.view.impulse([0, -1, 0], 1.2); feel.land({ actor: v, hard: true }); });
    });
    void L;
  }
  function cineEnd(L) {
    const c = cine;
    if (!c) return;
    const a = c.attacker;
    call(a, ultOf(a).end, 'ult.end', { attacker: indexOf(a), defender: indexOf(c.victim), ko: !!L.lethal }, null, c.victim);
    cine = null;
    ultState = null;
    helperOf(a)._foe = null;
    if (world.camera && world.camera.cinematic) world.camera.endCine(false);
    if (ctx.env) ctx.env.setMood(null);
    if (ctx.cam) ctx.cam.letterbox(false, 0.6);
    if (ctx.audio) ctx.audio.music(world.flow && world.flow.music ? world.flow.music() : 'battle', { fade: 2 });
  }
  /** Per frame (after the characters): the ultimate's `at` timeline on the lock clock. */
  function updateCine() {
    if (!cine) return;
    const t = world.lock ? world.lock.t : cine.duration;
    for (const x of cine.at) {
      if (x.done || t < x.t) continue;
      x.done = true;
      call(cine.attacker, x.do, 'ult.at[' + x.t + ']', { t: x.t, cinematic: true }, null, cine.victim);
    }
  }

  // .. the ultimate strike: a boss (or anything that cannot be held) takes the whole lock as one burst ......................
  function strike(a, v, def) {
    const c = def.cinematic;
    let total = c.finish.damage;
    for (const tk of c.ticks) total += tk.damage;
    ultState.strike = true;
    const el = a.view.element;
    // the opener already landed; 0.28 s later (game time, after its hit-stop) the storm of the lock arrives at once
    ctx.vfx.schedule(0.28, () => {
      if (v.gone || a.gone) { ultState = null; restoreWorld(0.5); return; }
      const mul = a.mult.damage * (a.derived ? a.derived.arcane : 1) * (v.spec.taken ?? 1);
      const dmg = Math.round(total * mul);
      const pos = v.socket('chest', new THREE.Vector3());
      const ev = { attacker: a, victim: v, attack: def, hit: null, id: def.id, kind: 'tick', damage: dmg, level: 'knockdown', reaction: '', armoured: true, blocked: false,
        pos: { x: pos.x, y: pos.y, z: pos.z }, dirX: fwdX(a.yaw), dirZ: fwdZ(a.yaw), hitstop: 0.2, killed: false, front: true, crit: true, final: true, strike: true };
      v.hp = Math.max(0, v.hp - dmg);
      if (v.poiseMax > 0) { v.poise -= 120; v.poiseT = 0; if (v.poise <= 0) { world.emit('poiseBreak', { actor: v, by: a }); if (v.spec.onPoiseBreak) v.spec.onPoiseBreak(world, v, a); } }
      if (v.hp <= 0) ev.killed = true;
      world.emit('tick', ev);
      world.emit('hit', { ...ev, kind: 'tick' });
      // presentation: the element's climax at the target, scaled to it, a crash zoom, then the world comes back
      const f = actorFrame(a, v.pos);
      const ps = worldToStage(new THREE.Vector3(pos.x, pos.y, pos.z), f);
      const sc = Math.min(2.6, Math.max(1, v.scale * 0.8));
      withFrame(f, () => {
        fx.play('combat.hit.crit', { pos: [ps.x, Math.min(ps.y, 2.2 * sc), 0.2], dir: [1, 0.25, 0.3], facing: 1, scale: sc }, { element: el, intensity: 0.7 }, 'game.finisher');
        const fin = el === 'frost' ? 'frost.shatter' : el === 'volt' ? 'volt.strike' : 'ember.eruption';
        fx.play([fin, `${el}.eruption`], { pos: [ps.x, el === 'frost' ? Math.min(ps.y, 2.2 * sc) : 0.02, 0], dir: [0, 1, 0], facing: 1, scale: sc }, { element: el, k: 1.2, huge: true }, 'game.erupt');
      });
      ctx.post.flash(0xffffff, 0.25, { release: 0.3 });
      ctx.post.impactFrame({ duration: 0.07, invert: 0, mono: 0.8 });
      ctx.post.pulse('chroma', 0.6, { release: 0.5 });
      ctx.cam.shake(1, { freq: 10, duration: 1.1 });
      ctx.time.hitstop(0.2);
      sound('ult_impact', { pos });
      if (ctx.env) ctx.env.pulse([v.pos.x, 0, v.pos.z], a.view.palette.core, 1.6);
      if (v.view && v.view.flash) v.view.flash([1.4, 1.2, 1], 0.6, 0.25);
      if (ev.killed) v.die(a);
      ctx.vfx.schedule(0.7, () => { ultState = null; restoreWorld(0.7); });
    });
  }

  // ---- per frame --------------------------------------------------------------------------------------------------------
  function late() {
    if (direct.length) { const d = direct.splice(0, direct.length); for (const fn of d) { try { fn(); } catch (err) { warnOnce('ult', err); } } }
    flush();
    updateCine();
    feel.updateProjectiles();
  }

  /** Ambient presentation of an actor (present.ambient(h) -> handles), restarted after vfx.clear(). */
  const ambient = new Map();
  function startAmbient(a) {
    stopAmbient(a);
    const pr = presentOf(a);
    if (!pr || typeof pr.ambient !== 'function') return;
    const list = [];
    try { const r = withFrame(actorFrame(a), () => pr.ambient(helperOf(a))); if (r) list.push(...(Array.isArray(r) ? r : [r])); } catch (e) { warnOnce((a.spec.hero || a.kind) + '.ambient', e); }
    ambient.set(a.id, list);
  }
  function stopAmbient(a) {
    const list = ambient.get(a.id);
    if (list) for (const h of list) { try { h.kill(); } catch (e) { /* ignore */ } }
    ambient.delete(a.id);
  }
  offs.push(world.on('despawn', (e) => { stopAmbient(e.actor); helpers.delete(e.actor.id); }));
  offs.push(world.on('death', (e) => { if (e.actor !== world.hero) stopAmbient(e.actor); }));

  function dispose() {
    for (const off of offs) off();
    for (const list of ambient.values()) for (const h of list) { try { h.kill(); } catch (e) { /* ignore */ } }
    ambient.clear();
    feel.clearProjectiles();
    if (director && director._rpgPlay) { director.play = director._rpgPlay; delete director._rpgPlay; }
    uninstallStage();
    queue.length = 0; direct.length = 0;
    cine = null; ultState = null;
  }

  const present = { fx, sound, playedRecently, call, helperOf, indexOf, moveHandlers, superFreeze, stepLock, late, startAmbient, stopAmbient, dispose, camPlay,
    get cine() { return cine; }, get ult() { return ultState; }, ultActive };
  const feel = createFeel(ctx, world, present);
  present.feel = feel;
  return present;
}
