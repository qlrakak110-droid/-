// Fighter content API runtime: routes rules events to each fighter's `present` choreography and builds the helper
// object (`h`) the handlers receive. Generic behaviour (src/game/feel.js) runs for everything a fighter does not
// define, and after a handler unless the handler returns `false`. See README.md "Fighter content API".

import * as THREE from 'three';
import * as SHOTS from '../cam/shots.js';
import { Ease } from '../core/math.js';

const warned = new Set();
function warnOnce(key, e) {
  if (warned.has(key)) return;
  warned.add(key);
  console.warn('[ed] choreography ' + key + ' threw: ' + (e && (e.stack || e.message) || e));
}

/**
 * @param {object} ctx
 * @param {object} session
 * @param {object} feel generic feel layer (createFeel)
 */
export function createPresenter(ctx, session, feel) {
  const match = session.match;
  const helpers = [makeHelper(0), makeHelper(1)];
  /** running cinematic lock (ult runner) */
  let cine = null;
  /** running super-freeze presentation per fighter (generic camera / mood to undo on a whiff) */
  const ultState = [null, null];

  const presentOf = (i) => session.presentOf(i);
  /** Handlers of a move: present.moves[moveId], else present.moves[MOVES.md slot] ('skill1', 'heavy' ...). */
  const handlersOf = (i, id) => session.moveHandlers(i, id);

  /** Call a content handler safely; returns its result (undefined when missing). */
  function call(i, fn, key, e, extra) {
    if (typeof fn !== 'function') return undefined;
    const h = helpers[i];
    const pe = h.e, pd = h.data;
    h.e = e || null;
    h.data = (e && e.data) || null;
    try { return fn(h, e, extra); } catch (err) { warnOnce(session.fighters[i].id + '.' + key, err); return undefined; } finally { h.e = pe; h.data = pd; }
  }

  // ---------------------------------------------------------------------------------------------------------------
  // the helper object handed to every handler: everything in the fighter-local frame of its owner

  function view(i) {
    const A = () => session.actors[i];
    return {
      index: i,
      get actor() { return A(); },
      get char() { return A().char; },
      get sockets() { return A().char.sockets; },
      get fighter() { return match.fighters[i]; },
      get facing() { return match.fighters[i].facing; },
      /** world point in this fighter's frame (u = height above the floor) */
      at(f = 0, u = 0, s = 0) { return A().at(f, u, s, new THREE.Vector3()); },
      /** world position of a socket of this fighter (weaponTip, weaponBase, handR, handL, chest, head, hips, footL/R, back ...) */
      socket(name) { return A().socket(name, new THREE.Vector3()); },
      /** clip override (cinematic lock only; outside it the rules state drives the clips) */
      play(clip, o = {}) { const a = A(); if (a.cine) a.play(clip, { fade: 0.08, restart: true, ...o }); },
      /** cinematic root offset [f, u] metres over dur s (eased back to 0 when the lock ends) */
      offset(to, dur = 0.25, ease = 'inOutSine') { A().setOffset(to, dur, ease); },
      impulse(dir = [-1, 0.1, 0], amount = 1, bone) { A().impulse(dir, amount, bone); },
      flash(color = [3, 2, 1.4], amount = 1, dur = 0.15) { A().char.flash(color, amount, dur); },
      glow(color, amount = 1, dur = 0, fadeIn = 0.1) { A().glow(color, amount, dur, fadeIn); },
      weaponGlow(amount = 1, dur = 0.5, color) {
        const w = A().weaponGlow;
        const c = color || A().palette.core;
        if (Array.isArray(c)) w.color.setRGB(c[0] * 0.25, c[1] * 0.25, c[2] * 0.25); else w.color.set(c);
        w.amount = amount; w.dur = dur; w.t = 0; w.on = amount > 0;
      },
      afterimage(o = {}) { return session.fx.call('afterimage', A().char.root, { palette: A().element, intensity: 0.7, ...o }); },
      setVisible(b) { A().char.setVisible(b); },
    };
  }

  function makeHelper(i) {
    const self = view(i), foe = view(1 - i);
    const fighter = session.fighters[i];
    const tmpV = new THREE.Vector3();

    /** Resolve a position spec to a world Vector3 (new object). */
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
      if (spec.isObject3D) return spec.getWorldPosition(new THREE.Vector3());
      if (typeof spec === 'object') {
        const who = spec.of === 'foe' ? foe : self;
        const base = spec.socket ? who.socket(spec.socket) : spec.pos !== undefined ? pos(spec.pos) : who.at(0, 0, 0);
        if (spec.offset) base.add(tmpV.set(spec.offset[0] * who.facing, spec.offset[1] || 0, spec.offset[2] || 0));
        return base;
      }
      return self.socket('chest');
    }
    /** Local direction [f, u, s] -> world (mirrored by facing), normalised. */
    function dir(spec) {
      if (spec == null) return new THREE.Vector3(self.facing, 0, 0);
      if (spec.isVector3) return spec.clone().normalize();
      return new THREE.Vector3(spec[0] * self.facing, spec[1] || 0, spec[2] || 0).normalize();
    }
    /** `where` = position spec, or { pos, dir, scale, color, target } -> vfx `at` object. */
    function atObj(where) {
      const isAt = where && typeof where === 'object' && !Array.isArray(where) && !where.isVector3 && !where.isObject3D &&
        ('pos' in where || 'dir' in where || 'scale' in where || 'color' in where || 'target' in where) && !('socket' in where) && !('of' in where);
      const at = { pos: pos(isAt ? where.pos : where), facing: self.facing };
      if (isAt) {
        if (where.dir !== undefined) at.dir = dir(where.dir);
        if (where.scale !== undefined) at.scale = where.scale;
        if (where.color !== undefined) at.color = where.color;
        if (where.target !== undefined) at.target = typeof where.target === 'object' && where.target.isObject3D ? where.target : pos(where.target);
      }
      return at;
    }

    const h = {
      index: i, id: fighter.id, element: fighter.element, ctx, shots: SHOTS, Ease, THREE,
      get palette() { return session.actors[i].palette; },
      get vfx() { return ctx.vfx; },
      get rng() { return ctx.rng; },
      e: null, data: null,
      self, foe,
      get fighter() { return match.fighters[i]; },
      get foeFighter() { return match.fighters[1 - i]; },
      get facing() { return match.fighters[i].facing; },
      get t() { return match.fighters[i].moveTime; },
      get move() { return match.fighters[i].move; },
      get lockTime() { return match.cinematic ? match.cinematic.t : null; },
      pos, dir,
      at: (f, u, s) => self.at(f, u, s),
      socket: (name) => pos(name),
      color(key = 'core', k = 1) { const c = h.palette[key] || h.palette.core; return [c[0] * k, c[1] * k, c[2] * k]; },

      // VFX (facing applied; unknown presets fall back to a generic element burst, never throw)
      fx(name, where, opts = {}) { return session.fx.play(name, atObj(where), { element: h.element, ...opts }, opts.fallback ?? 'game.burst'); },
      burst(def, where, o = {}) { return session.fx.call('burst', def, { ...atObj(where), ...o, pos: atObj(where).pos }); },
      emitter(def, where, o = {}) {
        const { follow, ...rest } = o;
        const em = session.fx.call('emitter', def, { ...atObj(where), ...rest });
        if (follow && em.follow) em.follow(typeof follow === 'string' ? (follow.startsWith('foe.') ? foe.char.sockets[follow.slice(4)] : self.char.sockets[follow]) : follow);
        return em;
      },
      /** any vfx primitive with a pos: h.spawn('ring', where, { radius: [0.2, 3] }) (no-op if it does not exist yet) */
      spawn(kind, where, o = {}) { const a = atObj(where); return session.fx.call(kind, { palette: h.element, facing: a.facing, dir: a.dir, ...o, pos: a.pos }); },
      light(where, o = {}) { return session.fx.call('light', { color: h.palette.core, intensity: 120, range: 6, duration: 0.3, ...o, pos: pos(where) }); },
      flare(where, o = {}) { return session.fx.call('flare', { color: h.palette.core, ...o, pos: pos(where) }); },
      distort(where, o = {}) { return session.fx.call('distort', { ...o, pos: pos(where) }); },
      trail: {
        start(o) { session.actors[i].trailStart(o); },
        stop() { session.actors[i].trailStop(); },
      },
      afterimage: (o) => self.afterimage(o),
      glow: (c, a, d, fi) => self.glow(c ?? h.palette.core, a, d, fi),
      flash: (c, a, d) => self.flash(c ?? h.color('core', 0.5), a, d),
      weaponGlow: (a, d, c) => self.weaponGlow(a, d, c),
      impulse(dirv = [-1, 0.1, 0], amount = 1, who = 'foe') { (who === 'self' ? self : foe).impulse(dirv, amount); },
      play: (clip, o) => self.play(clip, o),
      foePlay: (clip, o) => foe.play(clip, o),
      offset: (to, d, e) => self.offset(to, d, e),
      foeOffset: (to, d, e) => foe.offset(to, d, e),

      // camera (anchored on this fighter), audio, post, world, time
      cam: {
        shake: (a, o) => ctx.cam && ctx.cam.shake(a, o),
        kick: (o) => ctx.cam && ctx.cam.kick(o),
        zoom: (f, d, o = {}) => ctx.cam && ctx.cam.zoom(f, d, { focus: i, ...o }),
        play: (shots, o = {}) => (ctx.cam ? ctx.cam.play(shots, { anchor: i, ...o }) : null),
        stop: (b) => ctx.cam && ctx.cam.stop(b),
        letterbox: (on, d) => ctx.cam && ctx.cam.letterbox(on, d),
      },
      audio(name, o = {}) { return session.sound(name, { pos: self.socket('chest'), ...o }); },
      post: {
        pulse: (k, a, o) => ctx.post.pulse(k, a, o),
        flash: (c = 0xffffff, a = 0.6, o) => ctx.post.flash(c, a, o),
        impact: (o) => ctx.post.impactFrame(o),
        radial(where, amount = 0.4, o = {}) { ctx.post.radialAt(pos(where ?? 'contact')); ctx.post.pulse('radial', amount, { attack: 0.01, hold: 0.03, release: 0.3, ...o }); },
        chroma: (amount = 0.5, o = {}) => ctx.post.pulse('chroma', amount, { release: 0.3, ...o }),
      },
      mood(m) { if (ctx.env) ctx.env.setMood(m); },
      pulse(where, color, strength = 1) { if (ctx.env) ctx.env.pulse(pos(where ?? 'floor'), color || h.palette.core, strength); },
      slowmo: (scale, dur, o) => ctx.time.slowmo(scale, dur, o),
      hitstop: (sec) => ctx.time.hitstop(sec),
      /** run fn(h) after `sec` game seconds (frozen by hit-stop, cancelled at round reset) */
      after(sec, fn) {
        const e = h.e;
        if (!ctx.vfx) return null;
        return ctx.vfx.schedule(sec, () => call(i, fn, 'after', e));
      },
      announce(text, o = {}) { return ctx.ui && ctx.ui.hud ? ctx.ui.hud.announce(text, o) : null; },
      /** run the generic feel for the current hit / guard event explicitly (inside a handler that returns false) */
      defaultFeel() { if (h.e) feel.hit(h.e); },
    };
    return h;
  }

  // ---------------------------------------------------------------------------------------------------------------
  // dispatch

  /** Route one rules event to the content handlers and the generic feel. */
  function dispatch(name, e) {
    switch (name) {
      case 'moveStart': {
        const mh = handlersOf(e.fighter, e.move);
        if (mh) call(e.fighter, mh.start, e.move + '.start', e);
        feel.moveStart(e);
        break;
      }
      case 'marker': {
        const mh = handlersOf(e.fighter, e.move);
        let r;
        let own = false;
        if (mh && typeof mh[e.name] === 'function') { own = true; r = call(e.fighter, mh[e.name], e.move + '.' + e.name, e); }
        const on = presentOf(e.fighter).markers;
        if (on && typeof on[e.name] === 'function') { own = true; if (call(e.fighter, on[e.name], 'markers.' + e.name, e) === false) r = false; }
        if (e.cinematic && cine) cineMarker(e);
        if (r !== false) feel.marker(e, own);
        break;
      }
      case 'moveEnd': {
        const mh = handlersOf(e.fighter, e.move);
        if (mh) {
          if (!e.connected && e.reason === 'complete') call(e.fighter, mh.whiff, e.move + '.whiff', e);
          call(e.fighter, mh.end, e.move + '.end', e);
        }
        ultMoveEnd(e);
        feel.moveEnd(e);
        break;
      }
      case 'hit': {
        const a = e.attacker;
        let handler;
        if (e.kind === 'projectile') handler = (presentOf(a).projectiles || {})[session.projectileKind(e.projectile)];
        else handler = handlersOf(a, e.move);
        const key = e.blocked ? 'guard' : 'hit';
        const r = handler ? call(a, handler[key], e.move + '.' + key, e) : undefined;
        const onAll = presentOf(a).on && presentOf(a).on[key];
        const r2 = onAll ? call(a, onAll, 'on.' + key, e) : undefined;
        if (r !== false && r2 !== false) feel.hit(e);
        break;
      }
      case 'counter': {
        const mh = handlersOf(e.fighter, e.move);
        const r = mh ? call(e.fighter, mh.counter, e.move + '.counter', e) : undefined;
        if (r !== false) feel.counter(e);
        break;
      }
      case 'superFreezeStart': ultFreeze(e); break;
      case 'cinematicStart': cineStart(e); break;
      case 'cinematicTick': cineTick(e); break;
      case 'cinematicEnd': cineEnd(e); break;
      case 'projectileSpawn': case 'projectileActive': case 'projectileExpire': case 'projectileClash': {
        const owner = e.owner !== undefined ? e.owner : null;
        let r;
        if (owner !== null && !Array.isArray(owner)) {
          const ph = (presentOf(owner).projectiles || {})[e.kind || session.projectileKind(e.id)];
          const key = name === 'projectileSpawn' ? 'spawn' : name === 'projectileActive' ? 'active' : name === 'projectileExpire' ? 'expire' : 'clash';
          if (ph) r = call(owner, ph[key], 'projectiles.' + e.kind + '.' + key, e);
        }
        feel.projectile(name, e, r === false);
        break;
      }
      case 'ko': {
        const on = presentOf(e.by).on;
        const r = on ? call(e.by, on.ko, 'on.ko', e) : undefined;
        if (r !== false) feel.ko(e);
        break;
      }
      case 'state': {
        const on = presentOf(e.fighter).on;
        if (on && (e.to === 'victory' || e.to === 'defeat' || e.to === 'intro')) call(e.fighter, on[e.to], 'on.' + e.to, e);
        feel.state(e);
        break;
      }
      case 'dodge': case 'perfectDodge': case 'land': case 'tech': case 'wallBounce': case 'guardBreak': case 'comboEnd': case 'turn': case 'teleport': {
        const who = name === 'guardBreak' ? e.attacker : e.fighter !== undefined ? e.fighter : e.attacker;
        const on = who !== undefined ? presentOf(who).on : null;
        const r = on && on[name] ? call(who, on[name], 'on.' + name, e) : undefined;
        if (r !== false && feel[name]) feel[name](e);
        break;
      }
      default:
        if (feel[name]) feel[name](e);
    }
  }

  // ---------------------------------------------------------------------------------------------------------------
  // ultimate: super-freeze, cinematic lock runner, whiff

  function ultName(i) {
    const r = session.fighters[i].roster;
    const m = r && r.moves.find((x) => x.slot === 'ult');
    return m ? { name: m.name, nameEn: m.nameEn } : { name: '궁극기', nameEn: 'ULTIMATE' };
  }

  function ultFreeze(e) {
    const i = e.fighter, h = helpers[i];
    const ult = presentOf(i).ult || {};
    ultState[i] = { move: e.move, cine: false, cam: null };
    const r = call(i, ult.freeze, 'ult.freeze', e);
    if (r === false) return;
    const mood = ult.mood || session.fighters[i].roster.mood || { darken: 0.75 };
    if (ctx.env) ctx.env.setMood({ ...mood, duration: 0.25 });
    if (ctx.cam) {
      ultState[i].cam = ctx.cam.play([
        SHOTS.heroPushIn({ dur: e.duration + 0.12, clock: 'real', letterbox: true, roll: 5 }),
        SHOTS.weaponFollow({ dur: 1.2, hold: true, cut: 0.18 }),
      ], { anchor: i, blendOut: 0.45, keepLetterbox: true });
    }
    const n = ultName(i);
    if (ctx.ui && ctx.ui.hud) ctx.ui.hud.announce(n.name, { style: 'ult', side: i, sub: n.nameEn });
    session.sound('ult_start');
    if (ctx.audio) ctx.audio.music('ultimate');
    h.glow(h.color('mid', 0.035), 1, e.duration + 0.5, 0.15);
    h.weaponGlow(0.4, e.duration + 0.6);
    // the eclipse corona backlights the user: 1 m behind the chest (the preset pulls its disc 0.6 m toward the camera,
    // which at the hero push-in's 2.5 m hid the fighter behind it)
    const behind = h.socket('chest');
    behind.z -= 1.0; behind.y += 0.15;
    session.fx.play('combat.ult.flash', { pos: behind, facing: h.facing, scale: 0.55 }, { element: h.element, intensity: 0.4 }, null);
    if (session.fx.has('combat.charge.gather')) session.fx.play('combat.charge.gather', { pos: h.socket('weaponTip'), facing: h.facing }, { element: h.element, duration: e.duration * 0.9, follow: session.actors[i].char.sockets.weaponTip });
    else {
      const em = session.fx.call('emitter', session.fx.defsOf(h.element).charge, { pos: h.socket('weaponTip'), duration: e.duration * 0.9, realtime: true });
      if (em.follow) em.follow(session.actors[i].char.sockets.weaponTip);
    }
    ctx.post.pulse('exposure', -0.15, { attack: 0.1, hold: e.duration - 0.2, release: 0.3 });
  }

  /** The ultimate move ended without a lock (whiff / blocked): undo the super-freeze presentation. */
  function ultMoveEnd(e) {
    const st = ultState[e.fighter];
    if (!st || st.move !== e.move) return;
    ultState[e.fighter] = null;
    if (st.cine || e.reason === 'cinematic') return;
    const ult = presentOf(e.fighter).ult || {};
    call(e.fighter, ult.whiff, 'ult.whiff', e);
    restoreWorld(0.5);
  }

  function restoreWorld(camBlend = 0.6) {
    if (ctx.env) ctx.env.setMood(null);
    if (ctx.cam) { if (ctx.cam.mode === 'cine') ctx.cam.stop(camBlend); ctx.cam.letterbox(false, 0.5); }
    if (ctx.audio) ctx.audio.music('battle', { fade: 1.5 });
  }

  function cineStart(e) {
    const i = e.attacker, h = helpers[i];
    const ult = presentOf(i).ult || {};
    const cdef = (match.defs[i].moves[e.move] || {}).cinematic || {};
    if (ultState[i]) ultState[i].cine = true;
    for (const a of session.actors) a.cine = true;
    const at = (ult.at || []).map((x) => ({ t: x.t, do: x.do, done: false })).sort((a, b) => a.t - b.t);
    cine = { attacker: i, defender: e.defender, move: e.move, duration: e.duration, at, generic: !ult.at, cdef, cam: null, ticks: 0 };
    let shots = null;
    try { shots = typeof ult.shots === 'function' ? ult.shots(h) : ult.shots; } catch (err) { warnOnce(session.fighters[i].id + '.ult.shots', err); }
    if (!shots || !shots.length) shots = genericUltShots(e.duration, cdef);
    if (ctx.cam) cine.cam = ctx.cam.play(shots, { anchor: i, blendOut: ult.blendOut ?? 0.7, keepLetterbox: true });
    if (ctx.cam) ctx.cam.letterbox(true, 0.2);
    const r = call(i, ult.start, 'ult.start', e);
    if (r !== false) feel.cineStart(e);
    if (cine.generic) genericCine('start', e);
  }

  /** Called every frame (after the characters): ult timeline on the lock clock. */
  function update() {
    if (!cine) return;
    const t = match.cinematic ? match.cinematic.t : cine.duration;
    for (const x of cine.at) {
      if (x.done || t < x.t) continue;
      x.done = true;
      call(cine.attacker, x.do, 'ult.at[' + x.t + ']', { t: x.t, cinematic: true });
    }
  }

  function cineTick(e) {
    if (!cine) return;
    cine.ticks++;
    const ult = presentOf(e.attacker).ult || {};
    const r = call(e.attacker, ult.tick, 'ult.tick', e);
    if (r !== false) feel.cineTick(e);
    if (cine.generic) genericCine(e.final ? 'finish' : 'tick', e);
  }

  function cineMarker(e) {
    const ult = presentOf(cine.attacker).ult || {};
    if (ult.markers && typeof ult.markers[e.name] === 'function') call(cine.attacker, ult.markers[e.name], 'ult.markers.' + e.name, e);
  }

  function cineEnd(e) {
    if (!cine) return;
    const ult = presentOf(e.attacker).ult || {};
    call(e.attacker, ult.end, 'ult.end', e);
    const c = cine;
    cine = null;
    for (const a of session.actors) { a.cine = false; a.key = ''; a.setOffset([0, 0], 0.3); a.glow(null); }
    if (c.cam && !c.cam.done && ctx.cam && ctx.cam.mode === 'cine') ctx.cam.stop(0.6);
    if (ctx.env) ctx.env.setMood(null);
    if (ctx.cam) ctx.cam.letterbox(false, 0.6);
    if (ctx.audio && !e.ko) ctx.audio.music('battle', { fade: 2 });
  }

  /** Default shot list for a lock: punch-in on the trigger, orbit through the ticks, crash zoom, wide finish. */
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

  /** Default choreography of a lock for fighters without `ult.at`: cuts on every tick, slam on the finish. */
  const CUT_SLOTS = ['light1', 'light2', 'light3', 'heavy'];
  /** Attacker clip `name` started at `startAt`: settle into idle when it ends, unless something else was played. */
  function settleAfter(A, name, startAt) {
    const dur = A.char.clip === name ? A.char.clipDuration : 0.6;
    helpers[A.index].after(Math.max(0.1, dur - startAt - 0.05), () => { if (A.cine && A.char.clip === name) A.play(A.clips.state('idle').name, { fade: 0.25 }); });
  }
  function genericCine(phase, e) {
    const A = session.actors[cine.attacker], B = session.actors[cine.defender];
    const H = helpers[cine.attacker];
    if (phase === 'start') {
      B.play(B.clips.state('locked').name, { fade: 0.05, restart: true });
      return;
    }
    if (phase === 'tick') {
      const ids = CUT_SLOTS.map((s) => A.clips.slots[s]).filter(Boolean);
      const id = ids.length ? ids[cine.ticks % ids.length] : null;
      if (id) {
        const mc = A.clips.move(id);
        const startAt = Math.max(0, mc.map(mc.startup) - 0.1);
        A.play(mc.name, { fade: 0.05, restart: true, startAt });
        settleAfter(A, mc.name, startAt);
      }
      const hc = B.clips.state('hitHeavy');
      B.play(hc.name, { fade: 0, restart: true, startAt: 0.06 });
      B.impulse([-1, 0.1, 0.15], 1.1);
      A.trailStart({ life: 0.16 });
      H.after(0.12, () => A.trailStop());
      return;
    }
    if (phase === 'finish') {
      const mc = A.clips.move(cine.move);
      const startAt = Math.max(0, mc.map(mc.startup) - 0.08);
      A.play(mc.name, { fade: 0.05, restart: true, startAt });
      settleAfter(A, mc.name, startAt);
      // the victim is thrown, slammed into the floor and stays down until the lock releases it
      B.play(B.clips.state('fall').name, { fade: 0.04, restart: true });
      B.setOffset([-0.5, 0.35], 0.16, 'outQuad');
      B.impulse([-1, -0.3, 0], 2);
      H.after(0.18, () => { if (B.cine) B.setOffset([-0.75, 0], 0.14, 'inQuad'); });
      H.after(0.32, () => {
        if (!B.cine) return;
        B.play(B.clips.state('down').name, { fade: 0.08, restart: true });
        B.impulse([0, -1, 0], 1.2);
        feel.land({ fighter: B.index, hard: true });
      });
    }
  }

  /** Round reset: drop any running ultimate presentation. */
  function reset() {
    cine = null;
    ultState[0] = ultState[1] = null;
  }

  return {
    dispatch, update, reset, helper: (i) => helpers[i],
    get cine() { return cine; },
    get freezeCam() { return ultState.some((s) => s && s.cam); },
  };
}
