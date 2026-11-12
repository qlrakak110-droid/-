// ISKA 이스카 — 서릿별 무녀 · Froststar Oracle. Choreography (src/game/README.md §3 "Fighter content API").
//
// Every move is a small set piece on the MOVES.md beats, hung on the timeline markers of moves.js (BALANCE.md §9):
//   WIND-UP  glints kindle on the blades, motes converge, frost creeps out from her feet
//   RELEASE  thin starlight crescents (iska.cut), shard fans, racing ice lines, camera kicks
//   IMPACT   the frost "flower" (iska.flower: cold flash, four-point star, a fan of crystal shards, a tilted crystalline
//            ring) layered over the generic hit feel (sound, hit-stop, shake, HUD, stats stay generic)
//   AFTERMATH glitter and snow that hang, pale mist sinking along the floor, frost decals that melt away
//   SETTLE   a last glint on the blades
// The ultimate follows the MOVES.md shot table on the lock clock (BALANCE.md §7: storyboard t = 0.75 + lock t).
//
// Budget: no per-frame code (everything is event-driven: spawn-time allocations only), lights only as short pooled
// flashes (the idle aura has none), at most ~10 beams alive at once (the beam pool holds 12).

import { hasClip } from '../../char/index.js';
import { iska as design } from './design.js';
import { D, F, STAR, registerDefs, defineIskaFx } from './fxlib.js';

const ULT_NAME = { name: '떨어지는 서릿별', nameEn: 'Fall of the Frozen Star' };
const MOOD = { darken: 0.8, tint: 0x8fc8ff };
/** per hit level: strength of the frost flower layered over the generic hit */
const FLOWER_K = { light: 0.55, heavy: 0.85, launch: 1.0, crumple: 1.05, knockdown: 1.15 };

// ---- small helpers ---------------------------------------------------------------------------------------------------
/** the running session (stats / HUD for ticks the choreography replaces) */
const sessionOf = (h) => (h.ctx.game && h.ctx.game.session) || null;
/** world point of the opponent in Iska's frame (f measured from Iska) */
const foeF = (h) => (h.foeFighter.x - h.fighter.x) * h.facing;
/** a world Vector3 */
const W = (h, x, y, z) => new h.THREE.Vector3(x, y, z);
/** the char's glow channels (design.attach is idempotent) */
const glowOf = (h) => { try { return design.attach(h.self.char); } catch (e) { return null; } };
/** shoulder pivot of a slash in her frame */
const pivot = (h, f = 0.18, u = 1.28, s = 0.22) => h.at(f, u, s);
/** a blade glint on a socket */
function glint(h, where = 'weaponTip', size = 0.4, k = 0.55) {
  h.flare(where, { kind: 'star', size, life: 0.12, decay: 2.5, color: STAR, intensity: k, rotation: 0.3 });
}
/** Iska's crescent cut (iska.cut) around a pivot; heavy = both blades (a second crescent a beat later), brighter */
function cut(h, o = {}) {
  return h.fx('iska.cut', { pos: o.pos || pivot(h) }, {
    arc: o.arc, radius: o.radius, width: o.width, normal: o.normal, roll: o.roll, sweep: o.sweep, life: o.life,
    k: (o.intensity ?? 1) * (o.heavy ? 1.2 : 0.85), twin: o.twin ?? !!o.heavy, light: !!o.heavy,
  });
}
/** frost flower at the contact point of a hit (strike direction mostly forward, toward the camera a little) */
function flower(h, e, k, o = {}) {
  h.fx('iska.flower', { pos: 'contact', dir: o.dir || [1, o.up ?? 0.1, 0.35] }, { k, floor: o.floor });
}
/** a horizontal ice crescent around her (spins): plane tilted toward the camera so it reads from the fight camera */
function spinRing(h, u, o = {}) {
  return cut(h, { pos: h.at(0, u, 0), arc: o.arc || [-160, 150], radius: o.radius || 1.45, width: o.width || 0.3, normal: [0, 1, 0.42], sweep: o.sweep || 0.07, intensity: o.intensity ?? 0.9, heavy: o.heavy });
}
/** clip of the opponent's state slot (cinematic victim poses) */
const foeClip = (h, slot) => h.foe.actor.clips.state(slot).name;
/** play an ultimate beat clip 'iska.ult.<beat>' (clips/NAMES.md) when it exists, else one of her move clips at move time `at` */
function beat(h, name, fallbackMove, o = {}) {
  const clip = 'iska.ult.' + name;
  if (hasClip(clip)) { h.play(clip, { fade: o.fade ?? 0.06 }); return true; }
  if (!fallbackMove) return false;
  const mc = h.self.actor.clips.move(fallbackMove);
  h.play(mc.name, { fade: o.fade ?? 0.05, startAt: mc.map(o.at ?? Math.max(0, mc.startup - 0.06)), speed: o.speed ?? 1 });
  return false;
}
/** stats + HUD combo of a lock tick the choreography presents itself (the generic cineTick does this otherwise) */
function tickBook(h, e) {
  const s = sessionOf(h);
  if (s && s.stats) s.stats.tick(e);
  const f = h.fighter, hud = h.ctx.ui && h.ctx.ui.hud;
  if (hud && f.combo && f.combo.hits >= 2) hud.combo(h.index, f.combo.hits, f.combo.damage);
}

// ---- per-match state (projectiles and the ultimate; reset by ambient() at every round start) ------------------------
const state = [mk(), mk()];
function mk() { return { shots: new Map(), ult: null }; }
const st = (h) => state[h.index];

// ---- the ultimate's sky: a constellation over the crystal (victim-local [f, u, s]) ------------------------------------
const STARS = [[-3.0, 7.2, -2.6], [-1.8, 8.7, -3.4], [-0.5, 7.7, -2.2], [0.7, 9.2, -3.8], [1.5, 7.4, -2.0], [2.7, 8.5, -3.0], [3.4, 6.9, -2.4], [0.2, 6.4, -1.6], [-2.3, 6.2, -1.8]];
const EDGES = [[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [5, 6], [2, 7]];
/** the six orbit slashes: Iska's f (relative to the victim) / hop height / facing (-1 = turned around, behind it) */
const ORBIT = [[-0.85, 0.0, 1], [0.9, 0.2, -1], [-0.95, 0.55, 1], [0.85, 0.0, -1], [-0.8, 0.35, 1], [0.95, 0.75, -1]];
/** arcs of the orbit slashes (iska.cut planes) */
const ORBIT_CUTS = [
  { arc: [135, -40], normal: [0, -0.2, 1] }, { arc: [-140, 35], normal: [0, 0.25, 1] }, { arc: [160, 10], normal: [0, 1, 0.5] },
  { arc: [120, -60], normal: [0.2, 0, 1] }, { arc: [-30, 170], normal: [0, 0.3, 1] }, { arc: [150, -30], normal: [0, -0.4, 1] },
];

export const present = {
  /** once at boot, before vfx.prewarm(): Iska's particle rows and composed presets */
  setup({ ctx, vfx }) {
    registerDefs(vfx);
    defineIskaFx(vfx, ctx.rng);
  },

  /** idle: hovering on her toes, a slow snowfall of glittering motes around her, glints on the blades, cold mist pooling */
  ambient(h) {
    state[h.index] = mk();
    glowOf(h);
    h.self.setVisible(true);
    const v = h.vfx, ch = h.self.char, so = ch.sockets;
    const out = [];
    const em = (def, obj, off) => { const e = v.emitter(def, { pos: h.at(0, 1, 0) }); e.follow(obj, off); out.push(e); };
    em(D.ambSnow, ch.root, [0, 2.25, 0]);
    em(D.ambMotes, so.chest || ch.root, [0, 0, 0]);
    if (so.weaponTip) em(D.ambTip, so.weaponTip, [0, 0, 0]);
    if (so.weaponTip2) em(D.ambTip, so.weaponTip2, [0, 0, 0]);
    em(D.ambPool, ch.root, [0, 0.03, 0]);
    return out;
  },

  moves: {
    // ---- light chain ------------------------------------------------------------------------------------------------
    rime_flick: {
      windup(h) { glint(h, 'weaponTip', 0.32, 0.45); },
      swing(h) { cut(h, { arc: [105, -32], radius: 0.98, width: 0.26, normal: [0, -0.15, 1] }); },
      hit(h, e) { flower(h, e, 0.55, { up: -0.15 }); },
    },
    twin_moons: {
      windup(h) { glint(h, 'weaponTip2', 0.3, 0.4); },
      slashL(h) { cut(h, { pos: pivot(h, 0.12, 1.2), arc: [-135, 38], radius: 1.1, width: 0.28, normal: [0, 0.22, 1] }); },
      slashR(h) { cut(h, { arc: [140, -32], radius: 1.22, width: 0.3, normal: [0, -0.2, 1] }); },
      hit(h, e) { flower(h, e, e.label === 'right' ? 0.62 : 0.5, { up: e.label === 'right' ? -0.2 : 0.3 }); },
    },
    star_fan: {
      windup(h) { h.fx('iska.gather', { pos: h.at(0.25, 1.2, 0.2) }, { time: 0.14, count: 14 }); },
      spin(h) { spinRing(h, 1.15, { radius: 1.35, arc: [-170, 160] }); },
      shards(h) {
        // the knockback cut throws a fan of crystal shards forward
        cut(h, { heavy: true, arc: [150, -28], radius: 1.4, normal: [0, -0.1, 1] });
        h.burst(D.shardFan, { pos: h.at(0.7, 1.15, 0.2), dir: [1, 0.08, 0.15], scale: 1.2 }, { count: 18 });
        h.burst(D.glint, { pos: h.at(1.1, 1.2, 0.2) }, { count: 12, scale: 1.4 });
        h.cam.kick({ fov: -1.5, duration: 0.25 });
      },
      hit(h, e) {
        if (e.label === 'shards') { flower(h, e, 0.8, { floor: true }); h.spawn('debris', 'contact', { kind: 'ice', dir: [h.facing, 0.6, 0.2], count: 6, speed: [2, 5], spread: 40, size: [0.04, 0.11, 2] }); }
        else flower(h, e, 0.55);
      },
    },

    // ---- heavies ----------------------------------------------------------------------------------------------------
    glacier_pirouette: {
      windup(h) {
        h.spawn('decal', 'floor', { kind: 'frost', radius: 1.5, reveal: 0.22, life: 2.2 });
        h.burst(D.mistLow, { pos: h.at(0, 0.03, 0), dir: [0, 1, 0] }, { count: 5, scale: 0.7 });
        h.fx('iska.gather', { pos: h.at(0.1, 1.05, 0.2) }, { time: 0.16, count: 14 });
      },
      spin1(h) { spinRing(h, 1.2, { arc: [-165, 160] }); },
      spin2(h) { spinRing(h, 0.95, { arc: [-150, 175], radius: 1.55 }); },
      frostRing(h) {
        // the third revolution throws the frost ring: a ground ring, a crown of short ice spikes, frost and mist
        spinRing(h, 0.7, { radius: 1.75, width: 0.42, intensity: 1.1, heavy: true });
        const g = h.at(0, 0, 0);
        h.spawn('ring', g, { look: 'frost', radius: [0.3, 3.4], life: 0.7, distort: 0.03, intensity: 0.9 });
        h.spawn('spikes', g, { kind: 'ice', pattern: 'ring', radius: 1.55, count: 11, height: [0.28, 0.62], width: 0.22, tilt: 32, stagger: 0.008, rise: 0.05, hold: 0.32 });
        h.spawn('decal', g, { kind: 'frost', radius: 2.7, reveal: 0.25, life: 3 });
        h.burst(D.mistLow, { pos: h.at(0, 0.03, 0), dir: [0, 1, 0] }, { count: 12, scale: 1.1 });
        h.burst(D.glint, { pos: h.at(0, 0.6, 0) }, { count: 20, scale: 2.2 });
        h.light([0, 0.9, 1.2], { intensity: 90, range: 7, duration: 0.4 });
        h.cam.shake(0.22, { freq: 16 });
      },
      recover(h) { glint(h, 'weaponTip', 0.3, 0.35); },
      hit(h, e) { flower(h, e, e.label === 'frostRing' ? 0.95 : 0.55, { floor: e.label === 'frostRing' }); },
    },
    frostline_step: {
      windup(h) { h.spawn('decal', 'floor', { kind: 'frost', radius: 0.9, reveal: 0.1, life: 1.6 }); glint(h, 'weaponTip2', 0.3, 0.4); },
      iceLine(h) { h.fx('iska.iceLine', { pos: h.at(0.25, 0, 0) }, { length: 3.7, time: 0.12 }); },
      slide(h) {
        const v = h.vfx, so = h.self.char.sockets;
        for (const s of [so.footL, so.footR]) {
          if (!s) continue;
          const a = v.emitter(D.skid, { pos: s.getWorldPosition(W(h, 0, 0, 0)), dir: h.dir([-1, 0.6, 0.3]), duration: 0.32 }); a.follow(s);
          const b = v.emitter(D.skidMist, { pos: s.getWorldPosition(W(h, 0, 0, 0)), dir: h.dir([-1, 0.3, 0.2]), duration: 0.32 }); b.follow(s);
        }
        h.afterimage({ count: 2, interval: 0.08, life: 0.22, intensity: 0.45 });  // ghosts cost a full character each (tri budget)
        h.audio('frost_wind', { volume: 0.5 });
      },
      swing(h) { cut(h, { heavy: true, arc: [-150, 25], radius: 1.35, normal: [0, 0.35, 1] }); },
      stop(h) {
        h.burst(D.mistLow, { pos: h.at(0, 0.03, 0), dir: [0, 1, 0] }, { count: 6, scale: 0.8 });
        h.burst(D.sparks, { pos: h.at(0.2, 0.05, 0.1), dir: [1, 0.5, 0.3] }, { count: 18, scale: 0.6 });
        h.spawn('decal', 'floor', { kind: 'frost', radius: 1.0, reveal: 0.12, life: 2 });
      },
      hit(h, e) {
        flower(h, e, 0.7);
        h.flare('contact', { kind: 'streak', size: 0.08, aspect: 24, life: 0.14, color: F.core, intensity: 0.35, dir: h.dir([1, 0, 0]) });
      },
    },
    rising_crescent: {
      windup(h) { h.spawn('decal', 'floor', { kind: 'frost', radius: 1.1, reveal: 0.12, life: 1.8 }); h.fx('iska.gather', { pos: h.at(0.3, 0.8, 0.2) }, { time: 0.1, count: 12 }); },
      flip(h) {
        h.spawn('ring', h.at(0, 0, 0), { look: 'frost', radius: [0.2, 1.6], life: 0.45, intensity: 0.6 });
        h.burst(D.mistLow, { pos: h.at(0, 0.03, 0), dir: [0, 1, 0] }, { count: 5, scale: 0.7 });
      },
      swing(h) {
        // a rising crescent of starlight drawn by the backflip
        cut(h, { heavy: true, pos: h.at(0.35, 1.0, 0.22), arc: [-75, 120], radius: 1.55, width: 0.48, normal: [0, 0, 1] });
      },
      land(h) { h.burst(D.mistLow, { pos: h.at(0, 0.03, 0), dir: [0, 1, 0] }, { count: 4, scale: 0.6 }); glint(h, 'weaponTip', 0.3, 0.35); },
      hit(h, e) {
        flower(h, e, 0.8, { dir: [0.25, 1, 0.3] });
        h.burst(D.shards, { pos: 'contact', dir: [0.15, 1, 0.2] }, { count: 10, scale: 0.9 });
        h.spawn('pillar', h.at(foeF(h), 0, 0.05), { look: 'frost', radius: 0.16, height: 2.6, life: 0.36, intensity: 0.26 });
        h.cam.kick({ fov: -2, duration: 0.28 });
      },
    },

    // ---- skills -----------------------------------------------------------------------------------------------------
    starshard_volley: {
      windup(h) { h.weaponGlow(1.2, 0.5); },
      crystallise(h) {
        // three ice shards crystallise in a fan around her, each kindling until it fires (0.18 / 0.24 / 0.30)
        const fan = [[0.55, 1.5, 0.3, 0.13], [0.72, 1.18, 0.4, 0.19], [0.55, 0.9, 0.3, 0.25]];
        for (const [f, u, s, t] of fan) h.fx('iska.crystallise', { pos: h.at(f, u, s) }, { time: t });
        h.glow(h.color('mid', 0.05), 1, 0.4, 0.05);
      },
      release(h) { h.cam.kick({ fov: -2, duration: 0.3 }); },
      recover(h) { glint(h, 'weaponTip', 0.3, 0.35); glint(h, 'weaponTip2', 0.28, 0.3); },
    },
    crystal_procession: {
      windup(h) { h.fx('iska.gather', { pos: h.at(0.45, 0.55, 0.15) }, { time: 0.12, count: 18 }); },
      stab(h) {
        // both blades into the floor
        const g = h.at(0.5, 0, 0);
        h.burst(D.flash, { pos: h.at(0.5, 0.12, 0.2) }, { scale: 0.45 });
        h.burst(D.shards, { pos: h.at(0.5, 0.08, 0.1), dir: [0, 1, 0.2] }, { count: 12, scale: 0.8 });
        h.spawn('ring', g, { look: 'frost', radius: [0.15, 1.5], life: 0.45, intensity: 0.7 });
        h.light([0.5, 0.6, 1.1], { intensity: 70, range: 5, duration: 0.3 });
        h.cam.shake(0.2, { freq: 18, dir: [0, 1, 0] });
        h.audio('ice_crack', { volume: 0.7 });
      },
      frost(h) {
        // frost spreads around her feet, a rune turns
        h.spawn('decal', 'floor', { kind: 'frost', radius: 2.3, reveal: 0.3, life: 3 });
        h.spawn('decal', 'floor', { kind: 'rune', palette: 'frost', radius: 1.35, reveal: 0.12, life: 0.9, fadeOut: 0.3, spin: 1.4, intensity: 0.8 });
        h.burst(D.mistLow, { pos: h.at(0, 0.03, 0), dir: [0, 1, 0] }, { count: 8, scale: 0.9 });
      },
      release(h) {
        h.fx('iska.iceLine', { pos: h.at(0.8, 0, 0) }, { length: 6.6, time: 0.24 });
        // side tracking shot along the spike line (only from fight framing)
        if (h.ctx.cam && h.ctx.cam.mode === 'fight') {
          h.cam.play([{
            dur: 0.6, space: 'anchor', ease: 'outSine',
            from: { pos: [1.2, 1.0, 5.6], look: [2.6, 0.95, 0], fov: 46 }, to: { pos: [4.6, 1.15, 5.8], look: [6.4, 1.0, 0], fov: 43 },
          }], { blendOut: 0.4, hud: false });
        }
      },
    },
    moonlit_afterimage: {
      windup(h) { const g = glowOf(h); if (g) g.flare('all', 1.5, 0.35); },
      blink(h) {
        h.afterimage({ count: 2, interval: 0.05, life: 0.2, intensity: 0.6 });  // + the statue: at most 3 ghosts alive
        h.burst(D.glint, { pos: 'chest' }, { count: 10, scale: 1.2 });
        h.audio('frost_wind', { volume: 0.55 });
      },
      vanish(h) {
        h.burst(D.glitter, { pos: 'chest' }, { count: 22, scale: 1.1 });
        h.burst(D.mist, { pos: h.at(0, 0.9, 0) }, { count: 3, scale: 0.8 });
        h.flare('chest', { kind: 'star', size: 1.0, life: 0.14, decay: 2.5, color: STAR, intensity: 0.6, rotation: 0.4 });
        h.self.setVisible(false);
        // MOVES.md camera: a whip-pan following the blink (0.2 s) from where she vanished to the opponent she
        // reappears behind (fight framing only; the hit's FOV kick is the punch-in)
        if (h.ctx.cam && h.ctx.cam.mode === 'fight') {
          h.cam.play([h.shots.whipPan({ dur: 0.22, pos: [-0.9, 1.45, 4.6], look: 1.25, fov: [42, 37], bank: 3 })], { blendOut: 0.35, hud: false });
        }
      },
      reappear(h) {
        h.self.setVisible(true);
        h.flare('chest', { kind: 'star', size: 1.3, life: 0.16, decay: 2.5, color: STAR, intensity: 0.7, rotation: 0.1 });
        h.spawn('ring', h.at(0, 0, 0), { look: 'frost', radius: [0.2, 1.8], life: 0.4, intensity: 0.7 });
        h.burst(D.glitter, { pos: 'chest' }, { count: 18, scale: 1.0 });
        h.afterimage({ count: 1, life: 0.22, intensity: 0.8 });
        h.cam.kick({ fov: -2.5, roll: 2.5 * h.facing, duration: 0.3 });
      },
      swing(h) { cut(h, { arc: [150, -40], radius: 1.25, normal: [0, -0.15, 1], intensity: 0.9 }); },
      hit(h, e) { flower(h, e, 0.8); h.cam.kick({ fov: -3, duration: 0.3 }); },
      end(h) { h.self.setVisible(true); },
    },

    // ---- the ultimate on the move clock (super-freeze 0 .. 0.6, the rune snaps at 0.75) ----------------------------
    frozen_star: {
      aura(h) {
        const u = st(h).ult;
        h.burst(D.glint, { pos: h.at(0, 1.2, 0) }, { count: 24, scale: 2 });
        if (u) u.handles.push(h.spawn('decal', 'floor', { kind: 'frost', radius: 1.3, reveal: 0.4, life: 3 }));
      },
      rune(h) {
        // the star rune drawn under the opponent (clamped to maxRange)
        const u = st(h).ult || (st(h).ult = { handles: [] });
        const range = (h.data && h.data.maxRange) || 6;
        const f = Math.max(0.6, Math.min(range, foeF(h)));
        const g = h.at(f, 0, 0);
        u.runeAt = g;
        u.handles.push(h.spawn('decal', g, { kind: 'rune', palette: 'frost', radius: 1.8, reveal: 0.2, life: 1.2, fadeOut: 0.25, spin: 2.2, intensity: 0.35 }));
        u.handles.push(h.spawn('decal', g, { kind: 'frost', radius: 1.2, reveal: 0.35, life: 4, intensity: 0.6 }));
        u.handles.push(h.flare(W(h, g.x, 0.25, 0.4), { kind: 'glow', size: [0.3, 1.8], life: 0.45, attack: 0.35, decay: 3, color: F.mid, intensity: 0.3 }));
        h.burst(D.glint, { pos: W(h, g.x, 0.4, 0) }, { count: 20, scale: 2.2 });
        h.light(W(h, g.x, 0.7, 1.4), { intensity: 80, range: 7, duration: 0.45, attack: 0.3 });
        h.audio('rune', { volume: 0.8 });
      },
      release(h) {
        // the circle starts to close
        const u = st(h).ult;
        if (!u || !u.runeAt) return;
        h.spawn('ring', u.runeAt, { look: 'frost', radius: [2.2, 0.3], life: 0.2, intensity: 0.5 });
      },
      snap(h) {
        const u = st(h).ult;
        const g = (u && u.runeAt) || h.at(foeF(h), 0, 0);
        h.burst(D.flash, { pos: W(h, g.x, 0.4, 0.3) }, { scale: 0.35, intensity: 0.7 });
        h.burst(D.sparksRadial, { pos: W(h, g.x, 0.15, 0.1) }, { count: 24, scale: 0.9 });
        h.audio('ice_form', { volume: 0.9 });
      },
    },
  },

  projectiles: {
    // Starshard Volley: the frost.shard bodies are the generic feel's (the kind names the preset); Iska adds the muzzle
    // and freezes the victim on the third shard
    'frost.shard': {
      spawn(h, e) {
        // Iska's own body for the shard (dimmer than the generic one): the frost.shard lance flying with the rules
        // projectile (constant 14 m/s), shattered on its hit by impact()
        const p = W(h, e.x, e.y, 0.1);
        const dx = Math.sign(e.vx || 0) || h.facing;
        const body = h.fx('frost.shard', { pos: W(h, e.x, e.y, 0.05), dir: W(h, dx, 0, 0), scale: 0.8 }, { speed: Math.abs(e.vx || 14), life: e.lifetime || 0.75, intensity: 0.5 });
        st(h).shots.set(e.id, { data: e.data || {}, body, impacted: false });
        h.flare(p, { kind: 'star', size: 0.7, life: 0.12, decay: 2.5, color: STAR, intensity: 0.6, rotation: 0.2 });
        h.burst(D.sparks, { pos: p, dir: [1, 0.05, 0.1] }, { count: 10, scale: 0.6 });
        h.audio('swing_light', { volume: 0.5, pitch: 1.3 });
        return false;
      },
      hit(h, e) {
        const s = st(h).shots.get(e.projectile);
        if (s && s.body && typeof s.body.impact === 'function' && !s.impacted) { s.impacted = true; s.body.impact(h.pos('contact')); }
        if (e.blocked) return;
        if (s && s.data.freeze) {
          // frozen solid: an ice cage around the victim, a crystalline shell, frost on the floor
          const g = h.at(foeF(h), 0, 0);
          h.spawn('spikes', g, { kind: 'ice', pattern: 'ring', radius: 0.42, count: 7, height: [0.45, 0.95], width: 0.2, tilt: 10, stagger: 0.01, rise: 0.05, hold: 0.55 });
          h.spawn('decal', g, { kind: 'frost', radius: 1.4, reveal: 0.2, life: 2.6 });
          h.vfx.afterimage(h.foe.char.root, { life: 0.8, palette: 'frost', fill: 0.1, fresnel: 2.4, intensity: 0.5, swell: 0.02 });
          h.foe.glow([0.25, 0.7, 1.6], 0.35, 0.7, 0.03);
          flower(h, e, 1.2, { floor: true });
          h.audio('ice_form', { volume: 0.8 });
        } else flower(h, e, 0.6);
      },
      guard(h, e) {
        const s = st(h).shots.get(e.projectile);
        if (s && s.body && typeof s.body.impact === 'function' && !s.impacted) { s.impacted = true; s.body.impact(h.pos('contact')); }
      },
      expire(h, e) {
        const s = st(h).shots.get(e.id);
        if (s && s.body && !s.impacted) { if (e.reason === 'clash' && typeof s.body.impact === 'function') s.body.impact(); else s.body.stop(); }
        st(h).shots.delete(e.id);
      },
    },
    // Crystal Procession: five spikes racing 7 m, each larger than the last (Iska's own body replaces the generic one)
    'frost.spike': {
      spawn(h, e) {
        st(h).shots.set(e.id, { data: e.data || {} });
        // the frost runs ahead of the eruption
        h.spawn('decal', W(h, e.x, 0, 0), { kind: 'frost', radius: 0.6 + 0.4 * ((e.data && e.data.size) || 0.5), reveal: Math.max(0.04, (e.delay || 0) * 0.8), life: 2.4 });
        return false;
      },
      active(h, e) {
        const s = st(h).shots.get(e.id);
        const d = (s && s.data) || {};
        h.fx('iska.spike', { pos: W(h, e.x, 0, 0) }, { size: d.size ?? 1, hold: d.hold ?? 0.6, last: !!d.last });
        h.audio(d.last ? 'ice_shatter' : 'ice_form', { volume: d.last ? 0.9 : 0.55, pitch: d.last ? 0.8 : 1 + 0.08 * (d.index || 0) });
        h.cam.shake(d.last ? 0.4 : 0.14 + 0.03 * (d.index || 0), { freq: 16, dir: [0, 1, 0] });
        if (d.last) h.post.chroma(0.4);
      },
      hit(h, e) { if (!e.blocked) flower(h, e, 0.95, { dir: [0.1, 1, 0.3] }); },
      expire(h, e) { st(h).shots.delete(e.id); },
    },
    // Moonlit Afterimage: the frozen statue left on the start spot bursts forward with her cut
    'frost.statue': {
      spawn(h, e) {
        const g = W(h, e.x, 0, 0);
        const shell = h.vfx.afterimage(h.self.char.root, { life: (e.delay || 0.32) + 0.12, palette: 'frost', fill: 0.3, fresnel: 1.8, intensity: 1.0, swell: 0.01 });
        h.spawn('spikes', g, { kind: 'ice', pattern: 'ring', radius: 0.3, count: 6, height: [0.25, 0.55], width: 0.2, tilt: 14, stagger: 0.01, rise: 0.05, hold: (e.delay || 0.32) - 0.12 });
        h.spawn('decal', g, { kind: 'frost', radius: 1.1, reveal: 0.15, life: 2.2 });
        h.burst(D.mist, { pos: W(h, e.x, 0.5, 0.1) }, { count: 3, scale: 0.7 });
        st(h).shots.set(e.id, { shell, x: e.x, body: null, impacted: false });
        return false;
      },
      active(h, e) {
        const s = st(h).shots.get(e.id);
        const p = W(h, e.x, 1.1, 0.05);
        if (s && s.shell) s.shell.kill();
        // the statue shatters and its shards fly forward as one lance
        h.burst(D.flash, { pos: p }, { scale: 0.3, intensity: 0.6 });
        h.burst(D.shardFan, { pos: p, dir: [1, 0.15, 0.2] }, { count: 18, scale: 1.0 });
        h.burst(D.glitter, { pos: p }, { count: 16, scale: 1.0 });
        h.spawn('debris', p, { kind: 'ice', dir: [h.facing, 0.5, 0.2], count: 6, speed: [2, 5], spread: 45, size: [0.05, 0.12, 2] });
        const body = h.fx('frost.shard', { pos: p, dir: [1, 0, 0], scale: 0.9 }, { speed: 16, life: 0.26, intensity: 0.35 });
        if (s) s.body = body;
        h.audio('ice_shatter', { volume: 0.7 });
      },
      hit(h, e) {
        const s = st(h).shots.get(e.projectile);
        if (s && s.body && typeof s.body.impact === 'function' && !s.impacted) { s.impacted = true; s.body.impact(h.pos('contact')); }
      },
      guard(h, e) {
        const s = st(h).shots.get(e.projectile);
        if (s && s.body && typeof s.body.impact === 'function' && !s.impacted) { s.impacted = true; s.body.impact(h.pos('contact')); }
      },
      expire(h, e) { st(h).shots.delete(e.id); },
    },
  },

  on: {
    hit(h, e) {
      // a small frost glint on every block (the guard sparks stay generic)
      if (e.blocked) h.burst(D.glint, { pos: 'contact' }, { count: 5, scale: 0.6 });
    },
    intro(h) {
      h.self.setVisible(true);
      const g = h.at(0, 0, 0);
      h.spawn('decal', g, { kind: 'frost', radius: 1.9, reveal: 0.6, life: 3.5 });
      h.spawn('decal', g, { kind: 'rune', palette: 'frost', radius: 1.3, reveal: 0.5, life: 1.8, fadeOut: 0.5, spin: 0.9, intensity: 0.7 });
      h.burst(D.vortex, { pos: h.at(0, 1.1, 0), target: h.at(0, 1.1, 0) }, { count: 40 });
      h.burst(D.snow, { pos: h.at(0, 2.2, 0) }, { count: 16, scale: 2 });
      h.flare('crest', { kind: 'star', size: 0.9, life: 0.5, attack: 0.2, decay: 2, color: STAR, intensity: 0.6, rotation: 0.2 });
      const gl = glowOf(h);
      if (gl) { gl.flare('eye', 2.5, 1.2); gl.flare('inlay', 1.2, 1.4); }
    },
    victory(h) {
      h.burst(D.snow, { pos: h.at(0, 2.3, 0) }, { count: 24, scale: 2.4 });
      h.burst(D.glint, { pos: 'weaponTip' }, { count: 12, scale: 1.2 });
      h.burst(D.glint, { pos: 'weaponTip2' }, { count: 10, scale: 1.2 });
      h.flare('weaponTip', { kind: 'star', size: 0.8, life: 0.3, decay: 2, color: STAR, intensity: 0.6, rotation: 0.3 });
      const gl = glowOf(h);
      if (gl) gl.flare('all', 1.2, 1.5);
    },
    ko(h, e) {
      // a frost flourish over the generic KO: the victim's frost bursts into glitter
      if (e.cinematic) return;
      h.fx('frost.shatter', { pos: 'foe.chest', dir: [1, 0.3, 0.3] }, { intensity: 0.5, realtime: true });
    },
    perfectDodge(h) {
      h.flare('chest', { kind: 'star', size: 1.2, life: 0.3, decay: 2, color: STAR, intensity: 0.6, rotation: 0.2 });
      h.spawn('ring', h.at(0, 0, 0), { look: 'frost', radius: [0.2, 2.0], life: 0.5, intensity: 0.6 });
      h.burst(D.glitter, { pos: 'chest' }, { count: 20, scale: 1.2 });
    },
    dodge(h, e) { if (e.kind === 'dodge') h.burst(D.glint, { pos: 'chest' }, { count: 8, scale: 1 }); },
    // Moonlit Afterimage presents its own blink (reappear marker): no generic teleport burst
    teleport() { return false; },
  },

  // ---- ULTIMATE: 떨어지는 서릿별 Fall of the Frozen Star (MOVES.md shot table on the lock clock) ---------------------
  ult: {
    mood: MOOD,
    /** 0.00 row: face close-up on Iska, slow push, eyes open, irises glowing; frost aura, snow motes swirl (replaces the default) */
    freeze(h, e) {
      const T = e.duration || 0.6;
      const u = st(h).ult = { handles: [] };
      h.mood({ ...MOOD, duration: 0.25 });
      if (h.ctx.cam) {
        h.cam.play([
          h.shots.faceCloseUp({ dur: T + 0.06, clock: 'real', letterbox: true, angle: 34, dist: [1.3, 0.92], fov: [30, 26] }),
          // 0.60 row: top-down view of the rune circle, held until the circle snaps shut (hit -> the lock's own shots)
          h.shots.topDownSlam({ dur: 1.0, hold: true, cut: true, height: [7.2, 6.6], toward: [1.3, 1.1], roll: [0, 6], fov: [42, 40], clock: 'real' }),
        ], { blendOut: 0.45, keepLetterbox: true });
      }
      h.announce(ULT_NAME.name, { style: 'ult', side: h.index, sub: ULT_NAME.nameEn });
      h.audio('ult_start');
      if (h.ctx.audio) h.ctx.audio.music('ultimate');
      h.glow(h.color('mid', 0.03), 1, T + 0.5, 0.15);
      h.weaponGlow(0.9, T + 0.9);
      const gl = glowOf(h);
      if (gl) { gl.flare('eye', 2.2, 0.9, { attack: 0.18 }); gl.flare('inlay', 0.8, 1.0, { attack: 0.2 }); }
      // the snow swirls around her and is drawn in; a cold halo behind her head
      const vx = h.vfx.emitter(D.vortex, { pos: h.at(0, 1.2, 0), target: h.at(0, 1.2, 0), duration: T, realtime: true });
      u.handles.push(vx);
      h.burst(D.glint, { pos: h.at(0.2, 1.3, -1.2) }, { count: 14, scale: 2.2 });
      h.flare('eyes', { kind: 'star', size: [0.04, 0.2], life: T, attack: T * 0.6, decay: 2, color: STAR, intensity: 0.3, rotation: 0.15, realtime: true });
      // a cold halo far behind her head (reads as a rim of light in the close-up, never over the face)
      h.flare(h.at(-0.3, 1.75, -1.6), { kind: 'glow', size: [0.6, 1.6], life: T + 0.1, attack: T * 0.5, decay: 1.5, color: F.mid, intensity: 0.22, pull: 0, realtime: true });
      h.post.pulse('exposure', -0.15, { attack: 0.1, hold: T - 0.2, release: 0.3 });
      return false;
    },

    shots: (h) => {
      const S = h.shots;
      return [
        // lock 0 .. 0.45 (0.60 row, continued): top-down on the rune as the crystal encases the victim
        S.topDownSlam({ dur: 0.45, cut: 0.12, height: [6.4, 5.4], toward: [1.3, 1.1], roll: [6, 12], fov: [40, 37] }),
        // 0.45 .. 1.65 (1.20 row): ground skim orbiting the crystal, two fast cuts
        { dur: 0.6, cut: true, space: 'target', ease: 'linear', handheld: 0.3, orbit: { pivot: [0, 1.0, 0], from: -78, to: -28, radius: [3.4, 3.0], height: [0.34, 0.5] }, from: { fov: 52 }, to: { fov: 48 } },
        { dur: 0.6, cut: true, space: 'target', ease: 'linear', handheld: 0.3, orbit: { pivot: [0, 1.05, 0], from: 34, to: 82, radius: [3.3, 3.0], height: [0.45, 0.75] }, from: { fov: 50 }, to: { fov: 46 } },
        // 1.65 .. 2.65 (2.40 row): wide low angle looking up toward the eclipse as she leaps, slow motion 0.4
        // (closer than a true wide so she stays readable against the night sky as she rises past the eclipse)
        { dur: 1.0, cut: true, space: 'target', ease: 'outSine', slowmo: { scale: 0.42, at: 0.03, dur: 0.45 },
          from: { pos: [-1.1, 0.5, 5.6], look: [-0.75, 2.3, 0], fov: 50 }, to: { pos: [-0.95, 0.45, 5.2], look: [-0.65, 4.4, 0], fov: 52 } },
        // 2.65 .. 3.65 (3.40 row): over the shoulder from Iska in the air down onto the crystal
        { dur: 1.0, cut: true, space: 'target', ease: 'inOutSine', handheld: 0.4,
          from: { pos: [-4.2, 7.4, 2.4], look: [-0.35, 3.3, 0], fov: 54 }, to: { pos: [-3.8, 7.0, 2.1], look: [-0.3, 3.0, 0], fov: 50 } },
        // 3.65 .. 4.15 (4.40 row): impact punch-in on the shatter, slow motion 0.2
        S.impactPunchIn({ dur: 0.5, angle: -24, dist: [4.2, 3.0], slowmo: { scale: 0.22, at: 0.02, dur: 0.22 }, shake: { amount: 0.9, freq: 14, decay: 1.4 } }),
        // 4.15 .. 4.65 (4.90 row): wide establishing as the frost wave rolls across the arena; then the blend back
        S.wideEstablishing({ dur: 0.5, cut: true, dist: [11, 11.8], height: [2.5, 3.1], look: [1.5, 1.4], drift: 0.9 }),
      ];
    },
    blendOut: 0.75,

    /** the circle snapped shut (trigger): the victim is frozen in a crystal (replaces the default impact) */
    start(h, e) {
      const u = st(h).ult || (st(h).ult = { handles: [] });
      const g = h.at(foeF(h), 0, 0);
      u.vf = foeF(h);
      // the circle closes into a crystal: a ring of ice snaps up around the victim, a cold ring sweeps out, mist rolls
      h.spawn('ring', g, { look: 'frost', radius: [0.3, 2.6], life: 0.6, distort: 0.03, intensity: 0.3 });
      h.burst(D.flash, { pos: h.at(u.vf, 1.0, 0.3) }, { scale: 0.3, intensity: 0.4 });
      h.burst(D.sparksRadial, { pos: h.at(u.vf, 0.8, 0.1) }, { count: 28, scale: 0.9 });
      h.burst(D.glint, { pos: h.at(u.vf, 1.2, 0) }, { count: 14, scale: 1.6 });
      h.burst(D.mistLow, { pos: g, dir: [0, 1, 0] }, { count: 10, scale: 1.0 });
      h.light(h.at(u.vf, 1.4, 1.4), { intensity: 45, range: 7, duration: 0.6, decay: 'outCubic' });
      h.distort(h.at(u.vf, 0.05, 0), { kind: 'shock', normal: [0, 1, 0], radius: [0.3, 3.2], strength: 0.035, life: 0.5 });
      u.cage = h.spawn('spikes', g, { kind: 'ice', pattern: 'ring', radius: 0.55, count: 6, height: [0.55, 1.15], width: 0.13, tilt: 10, stagger: 0.014, rise: 0.08, hold: 4.2 });
      u.shell = h.vfx.afterimage(h.foe.char.root, { life: 3.9, palette: 'frost', fill: 0.14, fresnel: 2.2, intensity: 0.75, swell: 0.035, alpha: 0.85 });
      h.foe.glow([0.22, 0.6, 1.4], 0.4, 3.7, 0.08);
      h.foePlay(foeClip(h, 'hitHeavy'), { fade: 0.04, startAt: 0.08, speed: 0 });
      h.post.impact({ duration: 0.034 });
      h.post.chroma(0.6, { release: 0.4 });
      h.cam.shake(0.45, { freq: 14 });
      h.hitstop(0.16);
      h.audio('hit_crit', { volume: 0.8 });
      h.audio('ice_form');
      h.foe.flash([0.6, 1.2, 2.4], 0.5, 0.25);
      beat(h, 'crystal', 'frozen_star', { at: 0.9 });
      return false;
    },

    at: [
      // 0.42: the orbit clip starts 0.03 s ahead of slash1 so each of its six cuts (clip t 0.03 + 0.2 k) lands on its tick
      { t: 0.42, do(h) { if (hasClip('iska.ult.orbit')) beat(h, 'orbit', null, { fade: 0.03 }); } },
      // 1.65 (2.40 row): crouch and spring (iska.ult.leap takes off at 0.12), she rises high; slow motion from the shot
      { t: 1.65, do(h) {
        const u = st(h).ult || {};
        h.self.char.setFacing(h.facing);
        const own = beat(h, 'leap', 'rising_crescent', { at: 0.1, speed: 0.55 });
        const up = (h2) => {
          h2.offset([(u.vf ?? 1.7) - 0.7, 4.3], 0.55, 'outCubic');
          h2.afterimage({ count: 1, life: 0.3, intensity: 0.65 });  // the crystal shell is already one ghost (tri budget)
          h2.spawn('ring', h2.at(0, 0, 0), { look: 'frost', radius: [0.3, 2.6], life: 0.6, intensity: 0.7 });
          h2.burst(D.mistLow, { pos: h2.at(0, 0.03, 0), dir: [0, 1, 0] }, { count: 8, scale: 1 });
          h2.audio('frost_wind', { volume: 0.8 });
        };
        if (own) h.after(0.12, up); else up(h);
      } },
      // 2.70: the constellation appears in the sky; the stars connect into lines
      { t: 1.95, do(h) {
        const u = st(h).ult || (st(h).ult = { handles: [] });
        if (hasClip('iska.ult.constellation')) beat(h, 'constellation', null);
        const vx = h.at(u.vf ?? 1.7, 0, 0).x, fc = h.facing;
        u.stars = STARS.map(([f, y, z]) => W(h, vx + f * fc, y, z));
        u.stars.forEach((p, k) => {
          h.after(k * 0.035, (h2) => {
            h2.flare(p, { kind: 'star', size: 1.25, life: 1.85 - k * 0.035, attack: 0.08, decay: 0.7, color: STAR, intensity: 0.85, rotation: 0.2 + k * 0.4 });
            h2.flare(p, { kind: 'glow', size: 0.9, life: 1.8 - k * 0.035, attack: 0.1, decay: 0.8, color: F.core, intensity: 0.4 });
          });
        });
        EDGES.forEach(([a, b], k) => {
          h.after(0.18 + k * 0.06, (h2) => {
            h2.vfx.beam({ look: 'frost', palette: 'frost', core: STAR, from: u.stars[a], to: u.stars[b], width: 0.09, coreWidth: 0.35, extend: 0.1, release: 0.25, life: 1.5 - k * 0.06, flares: false, intensity: 1.0 });
          });
        });
        h.burst(D.skyDust, { pos: W(h, vx, 7.8, -2.8) }, { count: 50 });
        const gl = glowOf(h);
        if (gl) gl.flare('all', 2, 1.6, { attack: 0.3 });
        h.weaponGlow(1.4, 1.8);
        h.light(W(h, vx, 6, 1), { intensity: 70, range: 14, duration: 1.7, attack: 0.5, decay: 'outQuad' });
        h.audio('charge_up', { volume: 0.8 });
      } },
      // 3.40 row: aiming down from the air (the lances are the ticks)
      { t: 2.65, do(h) { beat(h, 'starfall', 'star_fan', { at: 0.1, speed: 0 }); } },
      // the dive: she drops onto the crystal and lands on the shatter (iska.ult.land: impact 0.12 = lock 3.65)
      { t: 3.53, do(h) {
        const u = st(h).ult || {};
        beat(h, 'land', null);
        h.offset([(u.vf ?? 1.7) - 0.85, 0], 0.12, 'inQuad');
        h.afterimage({ count: 1, life: 0.2, intensity: 0.75 });
      } },
      // 4.90 row: the frost wave rolls across the arena, everything rimed; letterbox out
      { t: 4.15, do(h) {
        beat(h, 'frostWave', null);
        h.fx('frost.blizzard', { pos: h.at(0.3, 0, 0) }, { length: 10, travel: 1.2, duration: 2.4, intensity: 0.85 });
        h.cam.letterbox(false, 0.7);
        h.audio('frost_wind', { volume: 1 });
      } },
      // 5.40 row: blend back; Iska flicks the frost off her blades, glitter lingers
      { t: 4.65, do(h) {
        h.offset([0, 0], 0.55, 'inOutSine');
        if (!beat(h, 'blendBack', null)) h.play(h.self.actor.clips.state('idle').name, { fade: 0.3 });
        h.burst(D.glitter, { pos: 'weaponTip' }, { count: 16, scale: 1.2 });
        h.burst(D.glitter, { pos: 'weaponTip2' }, { count: 16, scale: 1.2 });
        h.burst(D.snow, { pos: h.at(0.6, 2.2, 0) }, { count: 20, scale: 2.4 });
      } },
    ],

    /** 6 orbit slashes, 12 star lances, the shatter (all presented here: return false) */
    tick(h, e) {
      const u = st(h).ult || (st(h).ult = { handles: [] });
      const vf = u.vf ?? foeF(h);
      const name = e.marker || '';
      const hs = e.hitstop || 0;
      if (name.startsWith('slash')) {
        const k = Math.max(0, Math.min(5, (parseInt(name.slice(5), 10) || 1) - 1));
        const [df, hop, face] = ORBIT[k];
        const from = h.socket('chest');
        h.afterimage({ count: 1, life: 0.16, intensity: 0.65 });
        h.offset([vf + df, hop], 0.05, 'outCubic');
        h.self.char.setFacing(h.facing * face);
        if (!hasClip('iska.ult.orbit')) beat(h, 'slash', ['rime_flick', 'twin_moons', 'star_fan'][k % 3], { fade: 0.03 });
        const to = h.at(vf + df, 1.25 + hop, 0);
        h.vfx.beam({ look: 'frost', palette: 'frost', core: STAR, from, to, width: 0.1, coreWidth: 0.3, extend: 0.03, release: 0.1, life: 0.12, flares: false, intensity: 0.6 });
        // the cut across the crystal
        const c = h.at(vf, 1.15 + 0.12 * (k % 2), 0.25);
        const o = ORBIT_CUTS[k];
        h.fx('iska.cut', { pos: c }, { arc: o.arc, normal: o.normal, radius: 1.05, width: 0.34, k: k === 5 ? 1.3 : 1, twin: k === 5 });
        h.fx('iska.flower', { pos: c, dir: [face, 0.1, 0.4] }, { k: 0.7 });
        h.foe.impulse([-face, 0.05, 0.1], 0.35);
        h.foe.flash([0.6, 1.2, 2.4], 0.35, 0.1);
        h.post.chroma(0.3, { release: 0.18 });
        h.cam.shake(0.26, { freq: 18 });
        h.audio('hit_slash_heavy', { volume: 0.8 });
        if (k % 2) h.audio('ice_crack', { volume: 0.6 });
      } else if (name.startsWith('lance')) {
        const k = (parseInt(name.slice(5), 10) || 1) - 1;
        const stars = u.stars || STARS.map(([f, y, z]) => h.at(vf + f, y, z));
        const from = stars[(k * 4) % stars.length];
        const ang = k * 2.4, r = 0.55 + 0.35 * ((k * 7) % 3) / 2;
        const ground = h.at(vf + Math.cos(ang) * r, 0, Math.sin(ang) * r * 0.7);
        const p = W(h, ground.x * 0.4 + h.at(vf, 0, 0).x * 0.6, 0.7 + 0.25 * (k % 3), ground.z * 0.5 + 0.15);
        h.fx('iska.lance', { pos: p, target: from }, { stick: true, ground, hold: Math.max(0.15, 3.66 - e.t), light: k % 3 === 0 });
        h.foe.flash([0.6, 1.2, 2.4], 0.3, 0.08);
        h.post.chroma(0.22, { release: 0.12 });
        h.cam.shake(0.18, { freq: 22 });
        h.audio(k % 2 ? 'ice_crack' : 'hit_slash_light', { volume: 0.65, pitch: 1 + 0.03 * k });
      } else if (e.final) {
        // 4.40 row: she lands and crosses her blades; crystal and victim shatter
        if (!hasClip('iska.ult.land')) beat(h, 'land', 'star_fan', { at: 0.25, fade: 0.03 });
        h.self.char.setFacing(h.facing);
        const c = h.at(vf, 1.2, 0.2);
        if (u.cage && u.cage.stop) u.cage.stop();
        if (u.shell && u.shell.kill) u.shell.kill();
        h.foe.glow(null);
        h.fx('frost.shatter', { pos: c, dir: [0, 1, 0] }, { intensity: 0.45 });
        h.fx('iska.flower', { pos: c, dir: [1, 0.2, 0.4] }, { k: 0.8 });
        h.spawn('ring', h.at(vf, 0, 0), { look: 'frost', radius: [0.4, 5.5], life: 0.9, distort: 0.04, intensity: 1 });
        h.spawn('ring', h.at(vf, 0.05, 0), { look: 'shock', palette: 'frost', radius: [0.3, 4.5], life: 0.45, intensity: 0.6 });
        h.spawn('decal', h.at(vf, 0, 0), { kind: 'frost', radius: 4.2, reveal: 0.35, life: 6 });
        // kept below a white-out: the punch-in camera is ~3 m away, the star and the light fill the frame otherwise
        h.flare(c, { kind: 'star', size: 1.5, life: 0.35, decay: 2.6, color: STAR, intensity: 0.32, rotation: 0.25 });
        h.light(W(h, c.x, 1.8, 2.4), { intensity: 55, range: 11, duration: 0.6, decay: 'outCubic' });
        h.distort(c, { kind: 'shock', radius: [0.3, 4.2], strength: 0.05, life: 0.55 });
        h.post.impact({ duration: 0.05, invert: 1 });
        h.post.flash(0xcfe6ff, 0.07, { release: 0.25 });
        h.post.radial(c, 0.55);
        h.post.chroma(0.9, { release: 0.5 });
        h.post.pulse('exposure', 0.12, { release: 0.5 });
        h.cam.shake(1, { freq: 10, duration: 1.2 });
        h.pulse(h.at(vf, 0, 0), null, 1.6);
        h.audio('ult_impact');
        h.audio('ice_shatter', { volume: 1 });
        // the victim is thrown out of the shattering crystal and slammed onto the floor
        h.foePlay(foeClip(h, 'fall'), { fade: 0.03 });
        h.foeOffset([0.55, 0.7], 0.14, 'outQuad');
        h.foe.impulse([-1, 0.4, 0.1], 1.8);
        h.after(0.16, (h2) => h2.foeOffset([1.0, 0], 0.14, 'inQuad'));
        h.after(0.3, (h2) => { h2.foePlay(foeClip(h2, 'down'), { fade: 0.08 }); h2.foe.impulse([0, -1, 0], 1.2); h2.burst(D.mistLow, { pos: h2.at((u.vf ?? 1.7) + 1.0, 0.03, 0), dir: [0, 1, 0] }, { count: 10, scale: 1.2 }); });
      }
      if (hs) h.hitstop(hs);
      tickBook(h, e);
      return false;
    },

    end(h) {
      const u = st(h).ult;
      if (u) {
        if (u.cage && u.cage.alive) u.cage.stop();
        if (u.shell && u.shell.alive) u.shell.kill();
        st(h).ult = null;
      }
      h.weaponGlow(0, 0);
      h.foe.glow(null);
    },

    /** missed (dodged / airborne victim): the rune shatters harmlessly */
    whiff(h) {
      const u = st(h).ult;
      const g = (u && u.runeAt) || h.at(Math.max(0.6, Math.min(6, foeF(h))), 0, 0);
      h.spawn('spikes', g, { kind: 'ice', pattern: 'ring', radius: 1.2, count: 9, height: [0.35, 0.8], width: 0.2, tilt: 26, stagger: 0.01, rise: 0.05, hold: 0.15 });
      h.burst(D.glitter, { pos: W(h, g.x, 0.6, 0) }, { count: 40, scale: 2.2 });
      h.burst(D.mistLow, { pos: g, dir: [0, 1, 0] }, { count: 10, scale: 1.1 });
      h.audio('ice_shatter', { volume: 0.6 });
      h.weaponGlow(0, 0);
      if (u) for (const x of u.handles) if (x && x.stop) x.stop();
      st(h).ult = null;
    },
  },
};

export default present;
