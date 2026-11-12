// VORN 볼른 — 뇌명의 창기사 · Stormcaller Lancer. Skill choreography (src/game/README.md "Fighter content API").
// Every move is a set piece on its moves.js markers (MOVES.md beats WIND-UP -> RELEASE -> IMPACT -> AFTERMATH -> SETTLE):
// arc-runes blaze on the wind-ups (design glow channels), lightning runs down the spear on the release, impacts are volt
// flowers punched around the thrust axis (vorn.flower, layered on the generic hit feel), and every skill leaves scorch,
// static and ozone behind. The ultimate follows the MOVES.md shot table on the lock clock (BALANCE.md § 7: storyboard
// t = 0.90 + lock t). Signature effects live in ./fx.js; beat clips come from ./clips (NAMES.md), with move-clip
// fallbacks so the lock reads even before they exist.

import * as THREE from 'three';
import { hasClip } from '../../char/index.js';
import design from './design.js';
import { defineVornFx, V } from './fx.js';

// ---- shared helpers ---------------------------------------------------------------------------------------------------

/** Per fighter slot (0 / 1): transient choreography state (Arc Step line, lodged javelin, tick counter). */
const ST = [{}, {}];
const st = (h) => ST[h.index];
const VIOLET = 0xc8b4ff;
const ROD_A = new THREE.Vector3(), ROD_B = new THREE.Vector3();

/** The design's glow control (arc-runes / gold veins / visor): attached once per character, null for other designs. */
function glowOf(h) {
  const c = h.self.char;
  if (!c) return null;
  if (c.glow) return c.glow;
  if (typeof design.attach !== 'function') return null;
  try { return design.attach(c); } catch (e) { return null; }
}
/** Arc-runes / veins / visor blaze: channel 'inlay' | 'vein' | 'eye' | 'all'. */
function runes(h, amount = 2, dur = 0.5, ch = 'inlay') {
  const g = glowOf(h);
  if (g) g.flare(ch, amount, dur);
}
/** World floor point under a position spec (sockets of airborne fighters included). */
function floorAt(h, where) {
  const p = h.pos(where);
  p.y = 0.02;
  return p;
}
/** Socket Object3D of the owner (followed by emitters / beams). */
const sock = (h, name) => h.self.char && h.self.char.sockets[name];
const foeSock = (h, name) => h.foe.char && h.foe.char.sockets[name];

/** Lightning runs down the spear (base -> past the tip): a thin line, a streak and a ring punched at the tip. */
function thrust(h, k = 1, o = {}) {
  h.fx('vorn.spear', { pos: 'weaponBase', target: 'weaponTip' }, { intensity: k, ...o });
}
/** Electric crescent of the spear in a plane (local pivot [f, u, s]). */
function arc(h, pivot, o) {
  h.fx('vorn.arc', { pos: pivot }, o);
}
/** Impact flower at the contact (layered on the generic hit). */
function flower(h, k, o = {}) {
  h.fx('vorn.flower', { pos: o.pos || 'contact', dir: o.dir || [1, 0.08, 0.25] }, { k, pierce: !!o.pierce, intensity: o.intensity ?? 1 });
}
/** The victim seizes with static for dur s. */
function seize(h, dur = 0.6, k = 1, delay = 0.08) {
  const c = foeSock(h, 'chest');
  if (c) h.after(delay, (h2) => h2.fx('vorn.static', 'foe.chest', { follow: c, duration: dur, intensity: k }));
}
/** Charge at the spear tip for dur s (follows the tip). */
function tipCharge(h, dur, k = 1, pop = false) {
  const t = sock(h, 'weaponTip');
  if (t) h.fx('vorn.tipCharge', 'weaponTip', { follow: t, duration: dur, intensity: k, pop });
}
/** Lightning wrapping the spear (base -> tip, follows the sockets). */
function spearArc(h, life = 0.25, k = 0.8, width = 0.2) {
  const a = sock(h, 'weaponBase'), b = sock(h, 'weaponTip');
  if (!a || !b || !h.vfx) return null;
  return h.vfx.beam({ look: 'volt', from: a, to: b, width, extend: 0.05, release: 0.08, life, wiggle: 0.04, flares: false, intensity: k });
}
/** Lock-only clip of a beat: 'vorn.ult.<beat>' when the animator authored it, else a move clip held near `t`. */
function beat(h, name, fb, o = {}) {
  const clip = 'vorn.ult.' + name;
  if (hasClip(clip)) { h.play(clip, { fade: 0.06, ...o }); return; }
  const A = h.self.actor;
  if (!fb || !A || !A.clips) return;
  if (fb.state) { h.play(A.clips.state(fb.state).name, { fade: fb.fade ?? 0.12 }); return; }
  const mc = A.clips.move(fb.move);
  h.play(mc.name, { fade: fb.fade ?? 0.08, startAt: mc.map(fb.t ?? mc.startup), speed: fb.speed ?? 1 });
}
/** Victim clip of a state slot during the lock. */
function foeClip(h, slot, o = {}) {
  const B = h.foe.actor;
  if (B && B.clips) h.foePlay(B.clips.state(slot).name, { fade: 0.06, ...o });
}
/** Weapon visibility (javelin throw in the ultimate, bolt form in Arc Step). */
function spearVisible(h, b) {
  const w = h.self.char && h.self.char.weapon;
  if (w && w.setVisible) w.setVisible(b);
}
/** Bookkeeping of a lock tick the default feel would have done (stats, HUD combo, stutter hit-stop). */
function book(h, e) {
  const s = h.ctx.game && h.ctx.game.session;
  if (s && s.stats && s.stats.tick) s.stats.tick(e);
  const f = h.fighter, hud = h.ctx.ui && h.ctx.ui.hud;
  if (hud && f && f.combo && f.combo.hits >= 2) hud.combo(h.index, f.combo.hits, f.combo.damage);
  if (e.hitstop) h.hitstop(e.hitstop);
}
function kill(x) { if (x && x.kill) x.kill(); return null; }

// ---- ultimate --------------------------------------------------------------------------------------------------------
// Lock clock (t = 0 at the skewer, storyboard = 0.90 + t). Shots: impact punch-in 0-0.30 | orbit sweep rising 0.30-0.90 |
// over the shoulder looking up 0.90-2.30 (nine bolts) | wide low establishing, slow-mo 0.35, 2.30-2.95 (catch, storm) |
// crash zoom 2.95-3.20 (dive) | top-down slam 3.20-4.10 (pillar, crater) | blend back 4.10-5.00.

const ULT_SHOTS = (h) => {
  const S = h.shots;
  return [
    S.impactPunchIn({ dur: 0.3, dist: [3.6, 2.3], height: [1.5, 1.6], look: 1.55, fov: [38, 30], shake: 0.5 }),
    { dur: 0.6, cut: true, space: 'mid', ease: 'inOutSine', handheld: 0.35,
      orbit: { pivot: [0.3, 1.9, 0], from: -52, to: 6, radius: [4.6, 4.0], height: [0.8, 2.0] }, from: { fov: 48 }, to: { fov: 46 } },
    { dur: 1.4, cut: true, space: 'anchor', ease: 'outSine', handheld: 0.7,
      from: { pos: [-1.5, 0.6, 2.0], look: [2.2, 4.0, 0], fov: 52, roll: -5 }, to: { pos: [-0.9, 2.1, 2.4], look: [2.4, 4.9, 0], fov: 46, roll: -2 } },
    { dur: 0.65, cut: true, space: 'mid', ease: 'inOutSine', handheld: 0.3,
      from: { pos: [-1.6, 0.8, 8.4], look: [0.3, 4.4, 0], fov: 52 }, to: { pos: [-0.3, 1.0, 7.8], look: [0.5, 4.9, 0], fov: 48 },
      slowmo: { scale: 0.35, at: 0.04, dur: 0.42, easeIn: 0.05, easeOut: 0.15 } },
    S.crashZoom({ dur: 0.25, subject: 'target', dist: [9, 4.2], height: [3.6, 2.0], look: 1.4, fov: [52, 40], shake: 0.25, follow: 'look', followY: true }),
    S.topDownSlam({ dur: 0.9, subject: 'target', height: [5.0, 6.4], toward: [5.4, 6.6], ahead: -1.0, look: 0.6, fov: [50, 56], roll: [0, 10] }),
  ];
};

/** The colossal slam (finish tick, lock 3.20 = storyboard 4.10). */
function slam(h, e) {
  book(h, e);
  const g = floorAt(h, 'foe.floor');
  h.fx('vorn.pillar', { pos: g }, { intensity: 0.8 });
  h.fx('vorn.flower', { pos: new THREE.Vector3(g.x, 0.55, g.z + 0.15), dir: h.dir([0.3, -1, 0.2]) }, { k: 0.75, pierce: true, intensity: 0.8 });
  h.post.flash(VIOLET, 0.1, { release: 0.35 });
  h.post.impact({ duration: 0.05, invert: 0, mono: 0.6 });   // a partial monochrome beat, not an inverted (white) frame
  h.post.pulse('exposure', 0.05, { attack: 0.02, release: 0.5 });
  h.post.chroma(0.3, { release: 0.4 });
  h.post.radial(g, 0.6, { release: 0.45 });
  h.cam.shake(1, { freq: 11, duration: 1.1, dir: [0, 1, 0] });
  h.pulse(g, V.core, 2);
  h.audio('ult_impact');
  h.audio('volt_strike', { volume: 0.9 });
  h.foe.flash([3, 2.2, 6], 0.7, 0.3);
  h.foe.impulse([0, -1, 0], 2);
  foeClip(h, 'down', { fade: 0.05 });
  runes(h, 3, 1.2, 'all');
  h.weaponGlow(1.2, 0.9);
}

const ult = {
  mood: { darken: 0.8, tint: 0xa080ff },
  blendOut: 0.9,
  /** Added to the default super-freeze (mood, hero push-in, cut-in, ult_start, charge gather). */
  freeze(h, e) {
    h.fx('vorn.frozenRain', { pos: [1.2, 0, 0] });
    runes(h, 3, 0.9, 'all');
    // after the default super-freeze set-up (same frame): our own low hero angle, rain, the spear raised to the sky,
    // then the weapon-follow of the dash (held until the lock or the whiff takes the camera)
    const D = (e && e.duration) || 0.6;
    h.after(0, (h2) => h2.cam.play([
      { dur: D, cut: true, space: 'anchor', ease: 'outSine', letterbox: true, handheld: 0.4,
        from: { pos: [2.7, 0.45, 3.6], look: [0.1, 1.75, 0], fov: 40, roll: 6 }, to: { pos: [2.1, 0.55, 3.0], look: [0.1, 1.95, 0], fov: 35, roll: 4 } },
      h2.shots.weaponFollow({ dur: 1.0, hold: true, cut: true }),
    ], { blendOut: 0.45, keepLetterbox: true }));
  },
  shots: ULT_SHOTS,
  /** Lock start (the skewer): replaces the default impact (its crit + white flash double the trigger's own hit). */
  start(h) {
    st(h).tick = 0;
    flower(h, 0.95, { pos: 'foe.chest', dir: [1, 0.05, 0.25], pierce: true, intensity: 0.85 });
    thrust(h, 1.0, { width: 0.12, reach: 0.6, ring: 2, life: 0.2 });
    h.post.flash(VIOLET, 0.07, { release: 0.2 });
    h.post.chroma(0.7, { release: 0.45 });
    h.post.radial('foe.chest', 0.8, { release: 0.35 });
    h.cam.shake(0.6, { freq: 13 });
    h.audio('hit_crit');
    h.audio('volt_zap', { volume: 0.9 });
    h.foe.flash([2.5, 1.8, 5], 0.6, 0.25);
    h.hitstop(0.2);
    seize(h, 2.3, 1);
    runes(h, 2.5, 1.0, 'all');
    h.weaponGlow(1.0, 0.6);
    return false;
  },
  at: [
    { t: 0.05, do(h) {   // lift: the victim levered up on the spear, lightning wraps the shaft
      beat(h, 'lift', { move: 'ninefold_storm', t: 0.8, speed: 0.15 });
      h.foeOffset([0.05, 0.75], 0.25, 'outCubic');
      foeClip(h, 'hitHeavy', { startAt: 0.06 });
      spearArc(h, 0.3, 0.9, 0.24);
      h.audio('volt_charge', { volume: 0.6 });
    } },
    { t: 0.3, do(h) {    // hurl: flicks the victim into the air
      beat(h, 'hurl', { move: 'skyward_lance', t: 0.13 });
      h.foeOffset([-0.5, 3.4], 0.55, 'outCubic');
      foeClip(h, 'launched');
      flower(h, 1.0, { pos: 'foe.chest', dir: [0.3, 1, 0.2] });
      h.after(0.03, (h2) => h2.fx('vorn.skybolt', { socket: 'weaponTip', offset: [0.1, 0.7, 0] }, { intensity: 0.7 }));
      h.cam.shake(0.4, { freq: 15 });
      h.audio('swing_heavy');
      h.audio('hit_blunt', { volume: 0.7 });
    } },
    { t: 0.45, do(h) {   // throw: the spear goes after the victim (release at clip 0.08)
      beat(h, 'throw', { move: 'thunder_javelin', t: 0.2 });
      h.audio('swing_heavy', { volume: 0.8 });
      h.after(0.08, (h2) => {
        spearVisible(h2, false);
        const from = h2.pos('weaponTip'), to = h2.pos('foe.chest');
        to.y += 0.55;
        const dir = to.clone().sub(from).normalize();
        h2.fx('volt.javelin', { pos: from, dir: [dir.x * h2.facing, dir.y, dir.z] }, { to, intensity: 1.1 });
        h2.audio('volt_zap');
        h2.cam.kick({ fov: -2, duration: 0.3 });
      });
      // lodged in the victim: a lightning rod that crackles until the catch
      h.after(0.24, (h2) => {
        const c = foeSock(h2, 'chest');
        if (!c || !h2.vfx) return;
        // the ends are re-read every frame: two vectors owned by this rod, no per-frame allocation
        const f = h2.facing, PA = new THREE.Vector3(), PB = new THREE.Vector3();
        const a = () => c.getWorldPosition(PA).add(ROD_A.set(-f * 0.85, -0.55, 0.12));
        const b = () => c.getWorldPosition(PB).add(ROD_B.set(f * 0.25, 0.18, 0.12));
        kill(st(h2).rod);
        st(h2).rod = h2.vfx.beam({ look: 'volt', from: a, to: b, width: 0.16, extend: 0.02, release: 0.1, life: 1.62, wiggle: 0.03, flares: false, intensity: 0.7 });
        h2.cam.shake(0.35, { freq: 16 });
        h2.audio('hit_slash_heavy', { volume: 0.8 });
      });
    } },
    { t: 0.9, do(h) {    // leap
      beat(h, 'leap', { move: 'thunder_javelin', t: 0.36, speed: 0.25 });
      h.after(0.15, (h2) => {
        h2.offset([0.4, 2.2], 0.45, 'outCubic');
        h2.fx('combat.dust.land', 'floor', { heavy: true, k: 1.2 });
        h2.spawn('ring', h2.pos('floor'), { look: 'volt', radius: [0.2, 2.2], life: 0.4, intensity: 0.8 });
        h2.afterimage({ life: 0.35, count: 1 });
        h2.audio('dodge');
      });
    } },
    { t: 1.3, do(h) { beat(h, 'bolts', null, { loop: true }); } },
    { t: 1.5, do(h) { h.foeOffset([-0.6, 3.8], 0.8, 'inOutSine'); } },
    { t: 2.3, do(h) {    // catch: the spear tears out of the victim and flies back into his hand
      beat(h, 'catch', { move: 'stormfall', t: 0.1, speed: 0.3 });
      st(h).rod = kill(st(h).rod);
      const hand = h.pos('handR');
      if (h.vfx) h.vfx.bolt({ from: h.pos('foe.chest'), to: hand, width: 0.2, branches: 3, strikes: 3, interval: [0.03, 0.06], life: 0.3, leader: 0.02, impact: false, intensity: 0.85 });
      h.after(0.03, (h2) => spearVisible(h2, true));
      h.burst('vorn.arcs', 'handR', { count: 10 });
      h.burst('vorn.goldCone', 'handR', { dir: [0, 1, 0.2], count: 14 });
      h.offset([1.0, 4.6], 0.55, 'outCubic');
      runes(h, 3, 1.2, 'all');
      h.weaponGlow(1.2, 1.0);
      h.audio('volt_charge');
    } },
    { t: 2.4, do(h) {    // storm: the sky drains into the raised spear
      beat(h, 'storm', { move: 'stormfall', t: 0.22, speed: 0.15 });
      h.fx('vorn.storm', { pos: floorAt(h, 'foe.floor') }, { tip: h.at(1.0, 6.9, 0), duration: 0.65 });
      h.mood({ darken: 0.9, tint: 0x7050ff, duration: 0.4 });
      const t = sock(h, 'weaponTip');
      if (t) h.fx('vorn.tipCharge', 'weaponTip', { follow: t, duration: 0.55, intensity: 0.7 });
      h.audio('charge_up', { volume: 0.8 });
      h.audio('volt_strike', { volume: 0.5, delay: 0.2 });
    } },
    { t: 2.95, do(h) {   // dive: drives the victim down with the spear
      beat(h, 'slam', { move: 'stormfall', t: 0.38 });
      h.offset([1.6, 0], 0.25, 'inQuad');
      h.foeOffset([-0.3, 0], 0.25, 'inQuad');
      foeClip(h, 'fall', { fade: 0.04 });
      spearArc(h, 0.32, 1.1, 0.3);
      h.afterimage({ life: 0.3, count: 2, interval: 0.06 });
      if (h.vfx) h.vfx.speedlines({ pos: foeSock(h, 'chest'), life: 0.28, intensity: 0.5 });
      h.audio('swing_huge');
    } },
    { t: 3.75, do(h) { h.offset([0.8, 1.1], 0.2, 'outQuad'); h.fx('vorn.reform', 'floor', { intensity: 0.5 }); } },   // wrench free, vault back
    { t: 3.95, do(h) { h.offset([0, 0], 0.15, 'inQuad'); } },
    { t: 4.1, do(h) {    // land, blend back
      beat(h, 'land', { state: 'idle' });
      h.mood(null);
      h.fx('combat.dust.land', 'floor', { k: 0.9 });
      h.audio('land');
    } },
    { t: 4.4, do(h) {    // spear twirl, the arcs fade
      beat(h, 'twirl', { move: 'haft_spin', t: 0.02 });
      arc(h, [0.25, 1.15, 0.12], { arc: [200, -150], radius: 1.0, width: 0.16, sweep: 0.2, normal: [0, 0, 1], intensity: 0.6 });
      runes(h, 1.5, 0.8, 'inlay');
      h.audio('swing_light', { volume: 0.7 });
    } },
  ],
  /** The nine bolts (sky / his hand, alternating, accelerating) and the slam. */
  tick(h, e) {
    if (e.final) { slam(h, e); return false; }
    book(h, e);
    const n = (st(h).tick = (st(h).tick || 0) + 1);
    const last = !!(e.data && e.data.last) || n >= 9;
    const chest = h.pos('foe.chest');
    if (h.vfx) {
      if (last) {
        h.vfx.bolt({ from: [chest.x - h.facing * 1.2, 15, chest.z - 3], to: chest, width: 0.42, branches: 6, strikes: 3, interval: [0.03, 0.06], life: 0.4, leader: 0.02, impact: false, light: 90, lightRange: 10, intensity: 1 });
        h.vfx.pillar({ look: 'volt', pos: [chest.x, chest.y - 0.2, chest.z], height: 14, radius: 0.22, from: 'sky', life: 0.36, intensity: 0.55 });
      } else if (n % 2) {
        h.vfx.bolt({ from: [chest.x + (h.rng() - 0.5) * 3, 14, chest.z - 2.5], to: chest, width: 0.26, branches: 4, strikes: 2, interval: [0.03, 0.05], life: 0.22, leader: 0.015, impact: false, light: n % 4 === 1 ? 60 : 0, intensity: 0.85 });
      } else {
        h.vfx.bolt({ from: h.pos('handL'), to: chest, width: 0.2, branches: 3, strikes: 2, interval: [0.03, 0.05], life: 0.2, leader: 0.01, impact: false, intensity: 0.85 });
        h.burst('vorn.arcs', 'handL', { count: 6 });
      }
    }
    flower(h, last ? 1.1 : 0.6, { pos: 'foe.chest', dir: [0.4, last ? -1 : -0.4, 0.3], intensity: last ? 1 : 0.8 });
    h.foe.impulse([-1, 0.35, 0.1], last ? 1.6 : 0.8);
    h.foe.flash([2.5, 1.8, 5], last ? 0.7 : 0.4, 0.1);
    h.post.flash(VIOLET, last ? 0.12 : 0.05, { release: last ? 0.2 : 0.08 });
    h.post.chroma(last ? 0.8 : 0.35, { release: 0.2 });
    h.cam.shake(last ? 0.55 : 0.28, { freq: 17 });
    h.cam.kick({ fov: last ? -2.5 : -0.8, duration: 0.18 });
    h.audio(last ? 'volt_strike' : 'volt_zap', { volume: last ? 0.9 : 0.75, pitch: last ? 1 : 0.9 + 0.03 * n });
    if (!last && n % 3 === 0) h.audio('hit_slash_light', { volume: 0.6 });
    return false;
  },
  end(h) {
    st(h).rod = kill(st(h).rod);
    spearVisible(h, true);
  },
  whiff(h) {
    st(h).rod = kill(st(h).rod);
    spearVisible(h, true);
  },
};

// ---- moves -------------------------------------------------------------------------------------------------------------

const moves = {
  // LIGHT1 섬광 찌르기 Flash Jab: a flick of light down the spear, a needle of a hit
  flash_jab: {
    windup(h) { h.burst('vorn.crawl', 'weaponTip', { count: 3 }); },
    swing(h) { h.after(0.03, (h2) => thrust(h2, 0.7)); },
    hit(h) { flower(h, 0.45, { dir: [1, 0.04, 0.25] }); },
    guard(h) { h.burst('vorn.arcs', 'contact', { count: 5 }); },
  },

  // LIGHT2 회전 쳐올리기 Haft Spin: the spear whirls (an electric disc), the butt-end rises
  haft_spin: {
    spin(h) { h.burst('vorn.crawl', 'weaponBase', { count: 4 }); },
    swing(h) { arc(h, [0.15, 0.95, 0.12], { arc: [-115, 72], radius: 1.3, width: 0.16, sweep: 0.06, normal: [0, -0.2, 1], intensity: 0.7, life: 0.2 }); },
    hit(h) {
      flower(h, 0.5, { dir: [0.5, 0.85, 0.2] });
      h.burst('vorn.gold', 'contact', { dir: [0.3, 1, 0.2], count: 12 });
    },
  },

  // LIGHT3 천둥 꿰기 Thunder Pierce: lunge, thrust, and a spike of lightning shoots out of the tip
  thunder_pierce: {
    windup(h) { runes(h, 1.4, 0.45); tipCharge(h, 0.2, 0.6); },
    lunge(h) { h.fx('combat.dust.slide', 'footR', { length: 0.6, intensity: 0.7 }); },
    swing(h) { h.after(0.03, (h2) => thrust(h2, 0.8)); },
    spike(h) {
      // the spike: a lance of light 0.7 m past the tip, forks ahead, an anamorphic streak
      const tip = h.pos('weaponTip');
      const end = h.at(3.3, 1.28, 0.1);
      if (h.vfx) {
        h.vfx.beam({ look: 'volt', from: tip, to: end, width: 0.1, extend: 0.025, release: 0.08, life: 0.16, flares: false, intensity: 0.5 });
        h.vfx.bolt({ from: end, to: h.at(4.0, 1.4, 0.2), width: 0.07, branches: 2, strikes: 2, detail: 5, life: 0.18, leader: 0, impact: false, intensity: 0.7 });
      }
      h.flare(end, { kind: 'streak', size: 0.1, aspect: 20, life: 0.12, dir: h.dir([1, 0, 0]), intensity: 0.4 });
      h.cam.kick({ fov: -1.6, duration: 0.25 });
      h.audio('volt_zap', { volume: 0.8 });
      runes(h, 2, 0.4);
    },
    trailOff(h) { const t = sock(h, 'weaponTip'); if (t) h.emitter('vorn.crawlTip', 'weaponTip', { follow: t, duration: 0.4 }); },
    hit(h, e) {
      if (e.label === 'spike') {
        flower(h, 0.95, { pierce: true, dir: [1, 0.02, 0.2] });
        seize(h, 0.35, 0.6);
        h.cam.shake(0.25, { freq: 16 });
      } else flower(h, 0.45);
    },
  },

  // HEAVY 폭풍 휩쓸기 Gale Sweep: a low electric crescent, the blade drags sparks and scorch along the floor
  gale_sweep: {
    windup(h) { runes(h, 1.4, 0.5); h.after(0.08, (h2) => tipCharge(h2, 0.14, 0.5)); },
    swing(h) { arc(h, [0.1, 0.3, 0.05], { arc: [-165, 25], radius: 2.2, width: 0.32, sweep: 0.09, normal: [0, 1, 0.32], intensity: 0.85, life: 0.32 }); },
    sparks(h) {
      h.fx('vorn.sweep', { pos: floorAt(h, 'weaponTip'), dir: [0.6, 0, 0.8] });
      h.after(0.04, (h2) => h2.fx('vorn.sweep', { pos: h2.at(2.0, 0.02, 0.2), dir: [1, 0, -0.2] }, { intensity: 0.6 }));
      h.spawn('decal', h.at(1.6, 0, 0.35), { kind: 'scorch', radius: 0.9, life: 3.5, magma: 0.6 });
      h.audio('volt_zap', { volume: 0.7 });
    },
    hit(h) {
      flower(h, 0.85, { dir: [0.6, 0.6, 0.3] });
      h.spawn('ring', 'foe.floor', { look: 'volt', radius: [0.2, 1.8], life: 0.4, intensity: 0.6 });
      seize(h, 0.4, 0.5);
    },
  },

  // F+HEAVY 번개 돌격 Lightning Charge: crouch, bursts into a streak of lightning, thrust at the head of it, skid
  lightning_charge: {
    windup(h) {
      runes(h, 1.8, 0.35, 'all');
      h.burst('vorn.crawlGround', h.at(0, 0.05, 0), { count: 10, dir: [0, 1, 0], scale: 0.6 });
      h.burst('vorn.gold', h.at(-0.2, 0.08, 0), { count: 12, dir: [-0.6, 1, 0.2] });
      tipCharge(h, 0.06, 0.6);
    },
    dash(h) {
      h.fx('volt.dash', { pos: 'floor', target: h.self.char.root }, { length: 3.9, ghosts: 1, intensity: 0.35 });
      h.cam.kick({ fov: -2.5, push: 0.4, duration: 0.3 });
      h.audio('volt_zap');
      h.audio('dodge', { volume: 0.7 });
    },
    swing(h) { h.after(0.03, (h2) => thrust(h2, 0.8)); },
    stop(h) {
      h.fx('combat.dust.slide', 'floor', { length: 1.2 });
      h.burst('vorn.gold', h.at(0.2, 0.06, 0.1), { count: 18, dir: [1, 0.5, 0.2] });
      h.burst('vorn.crawl', h.at(0, 1.0, 0.1), { count: 8, scale: 2 });
    },
    hit(h) { flower(h, 1.0, { pierce: true }); seize(h, 0.7, 0.7); },
  },

  // D+HEAVY 하늘 꿰뚫기 Skyward Lance: crouch, rising thrust, a bolt shoots from the tip to the sky
  skyward_lance: {
    windup(h) {
      runes(h, 1.8, 0.4);
      h.spawn('decal', 'floor', { kind: 'rune', radius: 0.9, life: 0.7, reveal: 0.1, fadeOut: 0.3, spin: 2 });
      tipCharge(h, 0.15, 0.7);
    },
    swing(h) { arc(h, [0.2, 0.85, 0.12], { arc: [-55, 98], radius: 1.8, width: 0.2, sweep: 0.06, normal: [0, -0.15, 1], intensity: 0.75, life: 0.24 }); },
    bolt(h) {
      // a beat after the hit flash, from just above the tip, so the two never pile up on the victim
      h.after(0.04, (h2) => h2.fx('vorn.skybolt', { socket: 'weaponTip', offset: [0.1, 0.6, 0] }));
      h.cam.kick({ fov: -2, duration: 0.3 });
      h.audio('volt_strike', { volume: 0.55, pitch: 1.15 });
    },
    hit(h) { flower(h, 0.9, { dir: [0.3, 1, 0.2] }); },
  },

  // SKILL1 뇌창 투척 Thunder Javelin: a javelin of pure lightning forms on the spear and is hurled
  thunder_javelin: {
    form(h) {
      runes(h, 2, 0.5, 'all');
      tipCharge(h, 0.2, 0.7);
      spearArc(h, 0.24, 0.55, 0.14);
    },
    release(h) {
      const p = h.at(0.9, 1.55, 0.05);
      h.spawn('ring', p, { look: 'volt', normal: h.dir([1, 0.05, 0]), radius: [0.04, 0.32], width: [0.03, 0.06], life: 0.16, intensity: 0.4 });
      h.burst('vorn.goldCone', p, { dir: [1, 0.1, 0.1], count: 14 });
      h.light(h.at(0.9, 1.7, 1.4), { intensity: 30, duration: 0.18, flicker: 0.5 });
    },
  },

  // SKILL2 낙뢰 Stormfall: the spear to the sky, the camera tilts up to the gathering clouds, three bolts crash down
  stormfall: {
    windup(h) { runes(h, 2, 0.8, 'all'); },
    raise(h) {
      tipCharge(h, 0.36, 0.8);
      h.after(0.22, (h2) => {
        const tip = h2.pos('weaponTip');
        if (h2.vfx) h2.vfx.bolt({ from: tip, to: [tip.x + h2.facing * 1.5, 11, tip.z - 2.5], width: 0.1, branches: 2, strikes: 3, interval: [0.03, 0.05], life: 0.2, leader: 0.03, impact: false, intensity: 0.65 });
      });
      // camera: tilt up from behind him to the sky over the target, crash down onto the first strike (cut)
      const cam = h.ctx.cam;
      if (cam && cam.mode === 'fight') {
        h.cam.play([
          { dur: 0.41, space: 'mid', ease: 'inOutSine', handheld: 0.3, cut: 0.12,
            from: { pos: [-2.4, 1.3, 6.4], look: [0.4, 1.9, 0], fov: 42 }, to: { pos: [-2.2, 0.6, 6.0], look: [1.1, 3.8, -1.0], fov: 50 } },
          h.shots.crashZoom({ dur: 0.36, subject: 'target', dist: [9.5, 6.8], height: [3.0, 1.8], look: 1.3, fov: [54, 44], angle: -14, shake: 0.2 }),
        ], { blendOut: 0.45, hud: false });
      }
    },
    clouds(h) { h.fx('vorn.clouds', 'foe.floor', { duration: 0.8 }); },
    release(h) { h.after(0.02, (h2) => arc(h2, [0.25, 1.4, 0.12], { arc: [120, -30], radius: 1.6, width: 0.2, sweep: 0.08, normal: [0, 0.2, 1], intensity: 0.6 })); },
  },

  // SKILL3 섬전 보법 Arc Step: dissolves into a bolt, re-forms 4 m on, the line he leaves detonates
  arc_step: {
    windup(h) {
      runes(h, 1.8, 0.3, 'all');
      h.burst('vorn.crawl', h.at(0, 1.0, 0.1), { count: 8, scale: 2 });
      h.burst('vorn.crawlGround', h.at(0, 0.05, 0), { count: 6, dir: [0, 1, 0], scale: 0.6 });
    },
    blink(h, e) {
      const s = st(h);
      s.blinkX = e && typeof e.x === 'number' ? e.x : h.pos('floor').x;
      const a = h.pos('floor');
      h.fx('volt.dash', { pos: a }, { to: h.at(4.0, 0, 0), intensity: 0.6 });
      h.after(0.017, (h2) => h2.self.setVisible(false));   // after the generic afterimage snapshot of this frame
      h.audio('volt_zap');
      h.cam.kick({ fov: -1.5, duration: 0.22 });
    },
    reappear(h, e) {
      h.self.setVisible(true);
      const s = st(h), x1 = e && typeof e.x === 'number' ? e.x : h.pos('floor').x;
      const x0 = typeof s.blinkX === 'number' ? s.blinkX : x1 - 4 * h.facing;
      h.fx('vorn.reform', 'floor', { intensity: 0.8 });
      h.fx('vorn.line', { pos: new THREE.Vector3(x0, 0, 0.05), target: new THREE.Vector3(x1, 0, 0.05) }, { hold: 0.25 });
      runes(h, 2.2, 0.4, 'all');
      h.audio('volt_charge', { volume: 0.5, pitch: 1.4 });
    },
    end(h) { h.self.setVisible(true); },
    options: { trail: false },
  },

  ninefold_storm: {
    // super-freeze 0 .. 0.6 (move clock): sky bolt into the spear tip, the charge, the frozen rain; dash 0.6
    skyBolt(h) {
      const t = sock(h, 'weaponTip');
      if (t && h.vfx) {
        const p = h.pos('weaponTip');
        h.vfx.bolt({ from: [p.x - h.facing * 1.6, 15, p.z - 3], to: t, width: 0.38, branches: 6, strikes: 4, interval: [0.04, 0.08], life: 0.5, leader: 0.03, impact: false, light: 60, lightRange: 9, intensity: 1 });
      }
      h.burst('vorn.arcs', 'weaponTip', { count: 12 });
      h.burst('vorn.goldCone', 'weaponTip', { dir: [0, -1, 0.2], count: 20 });
      h.post.chroma(0.6, { release: 0.3 });
      h.cam.shake(0.3, { freq: 14 });
      h.weaponGlow(1.2, 0.6);
      runes(h, 3, 0.6, 'all');
      h.audio('volt_strike', { volume: 0.75 });
    },
    charge(h) {
      tipCharge(h, 0.38, 0.9, false);
      h.spawn('decal', 'floor', { kind: 'rune', radius: 1.7, life: 1.0, reveal: 0.2, fadeOut: 0.3, spin: 1.8 });
      h.emitter('vorn.crawlGround', h.at(0, 0.06, 0), { dir: [0, 1, 0], scale: 1.3, duration: 0.4 });
      h.emitter('vorn.motesUp', h.at(0, 0.05, 0), { dir: [0, 1, 0], scale: 1.1, duration: 0.4 });
    },
    dash(h) {
      h.fx('volt.dash', { pos: 'floor', target: h.self.char.root }, { length: 6, ghosts: 1, speedlines: true, intensity: 0.5 });
      h.fx('vorn.rain', { pos: h.at(3, 0, 0) }, { duration: 1.4 });
      h.fx('combat.dust.dash', 'floor', { k: 1 });
      h.audio('volt_zap');
    },
    swing(h) { h.after(0.03, (h2) => thrust(h2, 1, { width: 0.1, reach: 0.4 })); },
    overrun(h) {   // whiff / block: the dash ends in a big but harmless lightning burst
      h.fx('volt.burst', 'weaponTip', { intensity: 0.6 });
      h.fx('vorn.skystrike', { pos: floorAt(h, 'weaponTip') }, { k: 1.4 });
      h.audio('volt_strike', { volume: 0.7 });
    },
    options: { whoosh: false },
  },
};

// ---- projectiles -----------------------------------------------------------------------------------------------------

const projectiles = {
  'volt.javelin': {
    hit(h) {
      flower(h, 1.0, { pierce: true, dir: [1, 0.02, 0.2] });
      seize(h, 0.9, 0.7);
      h.cam.shake(0.35, { freq: 15 });
      h.spawn('decal', 'foe.floor', { kind: 'scorch', radius: 1.0, life: 3, magma: 0.7 });
    },
    guard(h) { h.burst('vorn.arcs', 'contact', { count: 10 }); h.burst('vorn.gold', 'contact', { count: 20, dir: [-1, 0.5, 0.3] }); },
  },
  // Stormfall's sky bolts: the marker scorches under the opponent at spawn (index 1), every bolt lands on its delay
  'volt.strike': {
    spawn(h, e) {
      const d = e.data || {}, idx = d.index || 1, delay = e.delay || 0;
      const g = new THREE.Vector3(e.x, 0.02, 0);
      if (idx === 1) h.fx('vorn.mark', { pos: g }, { warn: delay });
      h.after(delay, (h2) => {
        const huge = !!d.huge;
        h2.fx('vorn.skystrike', { pos: g }, { k: huge ? 1.5 : 1, intensity: huge ? 0.8 : 0.75 });
        h2.fx('vorn.strikeX', { pos: g }, { k: huge ? 1.4 : 0.9 });
        h2.cam.shake(huge ? 0.6 : 0.35, { freq: 13, dir: [0, 1, 0] });
        h2.pulse(g, V.core, huge ? 1.6 : 0.8);
        if (huge) h2.post.flash(VIOLET, 0.06, { release: 0.2 });
        if (idx === 1) h2.post.pulse('exposure', 0.06, { release: 0.2 });
      });
      return false;
    },
    hit(h, e) { flower(h, e.label === 'bolt3' ? 1.0 : 0.6, { pos: 'foe.chest', dir: [0.1, -1, 0.3] }); },
  },
  // Arc Step's detonation along the line he left behind
  'volt.chain': {
    spawn(h, e) {
      const f = e.facing || h.facing, len = (e.data && e.data.length) || 4;
      h.fx('vorn.detonate', { pos: new THREE.Vector3(e.x - f * len * 0.5, 0, 0.05), target: new THREE.Vector3(e.x + f * len * 0.5, 0, 0.05) }, { intensity: 0.72 });
      h.audio('volt_strike', { volume: 0.6, pitch: 1.2 });
      return false;
    },
    hit(h) { flower(h, 0.85, { dir: [0, 1, 0.3] }); seize(h, 0.45, 0.6); },
  },
};

// ---- VORN's hit feel -------------------------------------------------------------------------------------------------
// The generic hit feel (src/game/feel.js) with the light event tamed. VORN's own impact flower (vorn.flower) already
// carries the brightness of every hit; stacked on the shared hit preset at full strength, the generic white finisher
// flash and the inverted impact frame, the victim disappeared in a white blob for ~3 frames at the two-shot framing and
// skill finishers flashed an almost white frame in the dark arena (director review). Everything else is the generic
// layer's beats, unchanged: hit-stop, flinch, shake, fov kick, chroma / radial, sounds, combo HUD, stats.

const LEVEL_K = { light: 0.55, heavy: 0.9, launch: 1.0, crumple: 1.0, knockdown: 1.1 };
const FLINCH = { light: 0.55, heavy: 1.0, launch: 1.6, crumple: 1.25, knockdown: 1.8 };
const HIT_AT = { pos: 'contact', dir: [1, 0.18, 0.32], scale: 1 };

function hitFeel(h, e) {
  const s = h.ctx.game && h.ctx.game.session;
  if (!s || !s.match || e.blocked) return undefined;            // generic feel
  const post = h.ctx.post;
  const lvl = e.level || 'light';
  const mv = e.move && s.match.defs[e.attacker] && s.match.defs[e.attacker].moves[e.move];
  const group = mv ? mv.group : 'normal';
  let k = LEVEL_K[lvl] ?? 0.7;
  if (group === 'skill') k += 0.25;
  if (group === 'ult') k += 0.35;
  if (e.counter) k += 0.25;
  if (e.armoured) k = 0.5;
  if (e.ko) k = Math.max(k, 1.5);
  const finisher = group !== 'normal' && (lvl === 'launch' || lvl === 'knockdown' || lvl === 'crumple');
  // the shared hit at ~60 % light and 85 % size: sparks / cut / shock read, the flash core no longer swallows the victim
  const names = e.counter || group === 'ult' ? ['combat.hit.crit', `combat.hit.${lvl}`] : group === 'skill' ? ['volt.hit', `combat.hit.${lvl}`] : [`combat.hit.${lvl}`];
  HIT_AT.scale = lvl === 'light' ? 0.85 : 0.7;
  const inten = e.armoured ? 0.35 : lvl === 'light' ? 0.55 : 0.36;
  h.fx(names, HIT_AT, { k: Math.min(k, 1.25), level: lvl, intensity: inten, fallback: 'game.hit' });
  if (!e.armoured) {
    h.foe.impulse([e.front === false ? 1 : -1, lvl === 'launch' ? 0.5 : 0.1, 0.12], FLINCH[lvl] ?? 1);
    h.foe.flash([0.62, 0.5, 0.9], Math.min(0.45, 0.18 + 0.18 * k), 0.1);   // violet-tinted, never a white body
  } else h.foe.flash([1.4, 1.0, 2.2], 0.45, 0.12);
  h.cam.shake(lvl === 'light' ? 0.15 + (e.counter ? 0.12 : 0) : finisher ? 0.5 : 0.35 + (e.counter ? 0.15 : 0), { freq: lvl === 'light' ? 20 : 15 });
  if (k >= 0.9) h.cam.kick({ fov: -1.2 - 1.8 * Math.min(1, k - 0.9), duration: 0.28 });
  post.pulse('chroma', 0.12 + 0.2 * Math.max(0, k - 0.55), { release: 0.2 });
  if (k >= 0.9) { h.post.radial('contact', 0.14 + 0.2 * Math.min(1, k - 0.9), { release: 0.2 }); }
  // impact frame: monochrome (no invert: the inverted frame of this dark arena is a white-out), violet flash not white
  // half-strength mono: at full strength the bloom of a lightning strike thresholds to an all-white frame
  if (e.counter || finisher || group === 'ult') post.impactFrame({ duration: e.counter && !finisher ? 0.034 : 0.05, invert: 0, mono: 0.5 });
  if (finisher) post.flash(VIOLET, 0.07, { release: 0.15 });
  const at = h.pos('contact');
  s.sound(lvl === 'light' ? 'hit_slash_light' : 'hit_slash_heavy', { pos: at });
  if (finisher) s.sound('hit_blunt', { pos: at, volume: 0.65 });
  if (e.counter) s.sound('hit_crit', { pos: at, volume: 0.8 });
  if (group === 'skill' && finisher) s.sound('volt_strike', { pos: at, volume: 0.5 });
  if (e.kind === 'strike') h.hitstop(e.hitstop);
  if (k >= 1.1) h.pulse(at, V.core, Math.min(1.5, 0.45 * k));
  const hud = h.ctx.ui && h.ctx.ui.hud;
  if (e.combo >= 2 && hud) hud.combo(e.attacker, e.combo, e.comboDamage);
  if (s.stats && s.stats.hit) s.stats.hit(e);
  return false;
}

// ---- fighter-wide hooks ----------------------------------------------------------------------------------------------

const on = {
  hit(h, e) { return hitFeel(h, e); },
  intro(h) {
    // a bolt finds the planted spear; the runes wake
    h.after(0.35, (h2) => {
      const t = sock(h2, 'weaponTip');
      if (t && h2.vfx) { const p = h2.pos('weaponTip'); h2.vfx.bolt({ from: [p.x - h2.facing, 14, p.z - 3], to: t, width: 0.4, branches: 4, strikes: 3, life: 0.4, light: 120, intensity: 0.9 }); }
      h2.spawn('ring', 'floor', { look: 'volt', radius: [0.2, 2.2], life: 0.45, intensity: 0.8 });
      h2.spawn('decal', 'floor', { kind: 'scorch', radius: 1.0, life: 3, magma: 0.6 });
      runes(h2, 4, 1.2, 'all');
      h2.weaponGlow(1.2, 0.8);
      h2.audio('volt_strike', { volume: 0.6 });
    });
  },
  victory(h) {
    h.after(0.5, (h2) => {
      h2.fx('vorn.skybolt', 'weaponTip', { intensity: 0.8 });
      runes(h2, 4, 1.6, 'all');
      h2.audio('volt_strike', { volume: 0.55 });
    });
  },
  ko(h, e) {
    if (e && e.cinematic) return undefined;
    // the last hit calls a bolt down onto the fallen opponent
    h.after(0.12, (h2) => {
      h2.fx('vorn.skystrike', { pos: floorAt(h2, 'foe.floor') }, { k: 1.2 });
      runes(h2, 3, 1.5, 'all');
    });
    return undefined;
  },
  dodge(h) { h.burst('vorn.crawl', h.at(0, 1.0, 0.1), { count: 6, scale: 1.8 }); },
};

// ---- ambient: arcs crawling on the spear head and the helm horns, the arc-runes crackling -----------------------------

function ambient(h) {
  spearVisible(h, true);
  h.self.setVisible(true);
  glowOf(h);
  const out = [];
  const tip = sock(h, 'weaponTip');
  if (tip) {
    out.push(h.emitter('vorn.crawlTip', 'weaponTip', { follow: tip }));
    out.push(h.emitter('vorn.motesTip', 'weaponTip', { follow: tip }));
  }
  for (const horn of ['hornR', 'hornL']) {
    const s = sock(h, horn);
    if (s) out.push(h.emitter('vorn.horn', horn, { follow: s }));
  }
  // every so often a small arc jumps between the spear head and the blade root
  const loop = { live: true, kill() { this.live = false; }, stop() { this.live = false; } };
  const jump = (h2) => {
    if (!loop.live) return;
    const a = sock(h2, 'weaponTip'), b = sock(h2, 'weaponBase');
    const f = h2.fighter;
    if (a && b && h2.vfx && f && (f.state === 'idle' || f.state === 'walk' || f.state === 'guard')) {
      const pa = h2.pos('weaponTip'), pb = pa.clone().lerp(h2.pos('weaponBase'), 0.22);
      h2.vfx.bolt({ from: pa, to: pb, width: 0.05, branches: 1, strikes: 2, interval: [0.02, 0.04], detail: 4, life: 0.1, leader: 0, impact: false, glow: 0.8, intensity: 0.7 });
    }
    h2.after(0.7 + h2.rng() * 1.1, jump);
  };
  h.after(0.5, jump);
  out.push(loop);
  return out;
}
const DEF_HORN = { tex: 'arc', blend: 'add', count: 0, rate: 3, life: [0.04, 0.09], shape: { type: 'sphere', radius: 0.06 }, emit: 'random', speed: 0,
  size: [0.07, 0.16], aspect: 1.8, rotation: [0, 6.28], flicker: { amount: 0.9, rate: 50 }, groundFade: 0,
  color: [[0, 4.9, 4.2, 7.7, 1], [1, 1.9, 1, 4.8, 0]] };

// ---- the module ------------------------------------------------------------------------------------------------------

export const present = {
  setup({ ctx, vfx }) {
    if (!vfx) return;
    defineVornFx(vfx, ctx && ctx.rng);
    vfx.particleDef('vorn.horn', DEF_HORN);
  },
  ambient,
  moves,
  projectiles,
  on,
  ult,
};

export default present;
