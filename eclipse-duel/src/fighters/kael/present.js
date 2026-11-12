// KAEL 카엘 — 잿불의 집행자 · Cinder Warden: skill choreography (src/game/README.md "Fighter content API").
//
// Every move is staged on the MOVES.md beats, hung on the moves.js timeline markers (BALANCE.md § 9):
//   WIND-UP  glows, heat, gathering embers, runes / cracks on the floor (windup, armour, charge, drag, rune, aura ...)
//   RELEASE  the ember trail (`ember.trail`: glows, cools into smoke, sheds embers), flame crescents, launch bursts, kicks
//   IMPACT   Kael's ember impact flower layered on the generic hit (sparks / shake / hit-stop stay generic), floor bites
//   AFTERMATH lingering cinders, ash fall, scorch and magma cracks that cool to black
//   SETTLE   recover markers: the blade cools, a last drip of embers
// The ultimate (Pyre of the Black Sun) is directed on the lock clock of BALANCE.md § 7 (storyboard t = 1.00 + lock t).
// Signature effects are defined in ./fx.js (kael.*); the shared ember library (ember.*, combat.*) does the rest.

import { hasClip } from '../../char/index.js';
import { defineKaelFx, DRIP, RISE, CINDERS, SPIT, WALL, SPEAR, LINGER } from './fx.js';
import { def as rules } from './moves.js';

/** per-fighter-slot runtime handles (two Kaels in a mirror match never share state) */
const S = [{}, {}];
const st = (h) => S[h.index];

/** magma streak ribbon behind a charging body: dim orange that cools to smoke (camera-facing, so kept narrow and < 1.5) */
const STREAK = [[0, 1.4, 0.45, 0.08, 0.55], [0.3, 0.7, 0.14, 0.02, 0.35], [1, 0.08, 0.03, 0.01, 0]];

/** World point on the floor at fighter-local f. */
const floorAt = (h, f) => h.at(f, 0.02, 0);

// ---- weapon trail: the ember library trail (glows, cools into an occluding smoky tail, sheds embers) ----------------
const TRAIL_LIFE = { light: 0.17, rising: 0.2, overhead: 0.22, huge: 0.3, thrust: 0.14, drag: 0.3 };
/** trailOn -> trailOff span of every move (moves.js markers): the safety auto-stop of the trail */
const TRAIL_WINDOW = {};
for (const [id, mv] of Object.entries(rules.moves)) {
  const a = (mv.markers || []).find((m) => m.name === 'trailOn'), b = (mv.markers || []).find((m) => m.name === 'trailOff');
  if (a && b) TRAIL_WINDOW[id] = b.t - a.t;
}
function trailOn(h, style = 'light', dur = 0.4) {
  if (style === 'glow') return;
  trailOff(h);
  const s = h.self.sockets;
  st(h).trail = h.fx('ember.trail', 'weaponTip', { a: s.weaponBase, b: s.weaponTip, life: TRAIL_LIFE[style] ?? 0.2, duration: dur, intensity: 0.6, fallback: null });
}
function trailOff(h) {
  const x = st(h);
  if (x.trail) { x.trail.stop(); x.trail = null; }
}
/** Stop everything a move left running (cancels, interrupts, round ends). */
function cleanup(h) {
  trailOff(h);
  const x = st(h);
  for (const k of ['shell', 'groove', 'aura', 'streak']) if (x[k]) { x[k].stop(); x[k] = null; }
}

/** Ember accent layered over the generic hit (the generic flash, sparks, shake and hit-stop stay). */
function accent(h, k, dir = [1, -0.15, 0.3], cut = 30) {
  h.fx('kael.flower', { pos: 'contact', dir }, { k, cut, accent: true, fallback: null });
}

/**
 * A launch hit without the generic impact frame (Fault Eruption juggles: four inverted frames in 0.3 s would read as
 * white flashes). Keeps the generic bookkeeping: stats, combo counter, sound, flinch, shake.
 */
function quietHit(h, e, first) {
  h.fx('combat.hit.heavy', { pos: 'contact', dir: [0.2, 1, 0.3] }, { element: 'ember', intensity: 0.6, k: 1 });
  accent(h, 0.7, [0.2, 1, 0.3], 90);
  h.foe.impulse([-1, 0.5, 0.12], first ? 1.6 : 1.1);
  h.foe.flash([0.8, 0.66, 0.56], 0.3, 0.12);
  h.cam.shake(first ? 0.45 : 0.25, { freq: 14 });
  h.post.chroma(first ? 0.4 : 0.25, { release: 0.22 });
  if (first) h.post.impact({ duration: 0.034, invert: 0, mono: 1 });
  h.audio('hit_slash_heavy', { pos: h.pos('contact') });
  h.audio('hit_blunt', { pos: h.pos('contact'), volume: 0.6 });
  if (e.kind === 'strike' && e.hitstop) h.hitstop(e.hitstop);   // a strike's hit-stop is the feel layer's job
  const g = h.ctx.game, s = g && g.session, hud = h.ctx.ui && h.ctx.ui.hud;
  if (s && s.stats && s.stats.hit) s.stats.hit(e);
  if (hud && e.combo >= 2) hud.combo(e.attacker, e.combo, e.comboDamage);
}

/**
 * Kael's own heavy-hit feel (replaces the generic one: its star flash at ~0.95 intensity stacked with the ember slash
 * frozen at peak heat during the hit-stop washed the whole frame white on sweep / lunge / Cinder Drop / vent).
 * Same beats as the generic layer, tempered: library hit at o.intensity, flinch, body flash, shake, kick, chroma, sound,
 * the strike's hit-stop and the result-screen / combo bookkeeping. A KO keeps the generic (it owns the KO slow motion).
 */
const FINISH = { launch: 1, knockdown: 1, crumple: 1 };
function hitFeel(h, e, o = {}) {
  if (e.ko) return undefined;
  const lvl = e.level || 'heavy', fin = !!FINISH[lvl];
  const dir = o.dir || [1, -0.1, 0.3];
  h.fx(e.counter ? 'combat.hit.crit' : fin ? 'combat.hit.heavy' : `combat.hit.${lvl}`, { pos: 'contact', dir }, { element: 'ember', intensity: o.intensity ?? 0.42, k: o.k ?? 0.8, level: lvl });
  if (!e.armoured) {
    h.foe.impulse([e.front === false ? 1 : -1, lvl === 'launch' ? 0.5 : 0.1, 0.12], lvl === 'launch' ? 1.6 : fin ? 1.4 : 1.0);
    h.foe.flash([0.8, 0.66, 0.56], 0.32, 0.12);
  }
  h.cam.shake(o.shake ?? (fin ? 0.45 : 0.35), { freq: 15 });
  if (o.kick) h.cam.kick({ fov: -o.kick, duration: 0.28 });
  h.post.chroma(o.chroma ?? 0.25, { release: 0.22 });
  h.audio('hit_slash_heavy', { pos: h.pos('contact') });
  if (fin) h.audio('hit_blunt', { pos: h.pos('contact'), volume: 0.65 });
  if (e.counter) h.audio('hit_crit', { volume: 0.8 });
  if (e.kind === 'strike' && e.hitstop) h.hitstop(e.hitstop);
  const g = h.ctx.game, s = g && g.session, hud = h.ctx.ui && h.ctx.ui.hud;
  if (s && s.stats && s.stats.hit) s.stats.hit(e);
  if (hud && e.combo >= 2) hud.combo(e.attacker, e.combo, e.comboDamage);
  return false;
}

// ---- ultimate helpers ----------------------------------------------------------------------------------------------
/**
 * Dissolve the ULT cut-in card early (workaround: the hud card runs a fixed 1.9 s). Fades the card's `.an-fit` wrapper,
 * which the hud's own tween never writes, so its entrance / exit animation and removal stay untouched.
 */
function fadeUltCard(dur) {
  if (typeof document === 'undefined') return;
  const list = document.querySelectorAll('.ann.st-ult > .an-fit');
  for (let i = 0; i < list.length; i++) {
    const s = list[i].style;
    s.transition = `opacity ${dur}s ease-in`;
    s.opacity = '0';
  }
}
/** Play an ultimate beat clip (kael.ult.<beat>) when the animator registered it, else a move clip of Kael's set. */
function beat(h, name, fallbackMove, lead = 0.1, o = {}) {
  const full = name ? 'kael.ult.' + name : null;
  if (full && hasClip(full)) { h.play(full, { fade: 0.06, ...o }); return; }
  if (!fallbackMove) return;
  const mc = h.self.actor.clips.move(fallbackMove);
  h.play(mc.name, { fade: 0.05, startAt: Math.max(0, mc.map(mc.startup) - lead), ...o });
}
/** Victim reaction clip by state slot (hitHeavy, locked, launched, fall, down ...). */
function foeState(h, slot, o = {}) {
  const c = h.foe.actor.clips.state(slot);
  h.foePlay(c.name, { fade: 0.05, ...o });
}
/** Keep the result-screen stats and the combo counter when a tick handler replaces the generic tick feel. */
function tickBookkeeping(h, e) {
  const g = h.ctx.game, s = g && g.session;
  if (s && s.stats && s.stats.tick) s.stats.tick(e);
  const f = h.fighter, hud = h.ctx.ui && h.ctx.ui.hud;
  if (hud && f.combo && f.combo.hits >= 2) hud.combo(h.index, f.combo.hits, f.combo.damage);
}

// ---- moves --------------------------------------------------------------------------------------------------------
const moves = {
  // 재가르기 Ash Cleave — diagonal down cut from the shoulder, short ember trail
  light1: {
    windup(h) { h.weaponGlow(0.35, 0.22); },
    swing(h) {
      h.fx('ember.slash', { pos: [0.25, 1.42, 0.14] }, { arc: [118, -38], radius: 1.55, width: 0.48, sweep: 0.075, normal: [0, 0.22, 1], roll: -12, intensity: 0.32 });
    },
    hit(h) { accent(h, 0.5, [1, -0.45, 0.3], -40); },
    recover(h) { h.burst(DRIP, 'weaponTip', { count: 5 }); },
  },
  // 역날베기 Back Edge — rising backhand, the trail continues the arc
  light2: {
    swing(h) {
      h.fx('ember.slash', { pos: [0.2, 1.3, 0.14] }, { arc: [-70, 98], radius: 1.55, width: 0.48, sweep: 0.075, normal: [0, -0.2, 1], roll: 10, intensity: 0.3 });
    },
    hit(h) { accent(h, 0.55, [1, 0.5, 0.3], 55); },
  },
  // 잿불내려찍기 Cinder Drop — overhead into the floor: crack + ember spray, knockdown
  light3: {
    windup(h) { h.weaponGlow(0.6, 0.3); h.flare('weaponTip', { kind: 'glow', size: 0.6, life: 0.25, intensity: 0.4 }); },
    swing(h) {
      h.fx('ember.slash', { pos: [0.3, 1.5, 0.14] }, { arc: [140, -36], radius: 1.75, width: 0.5, sweep: 0.08, normal: [0, 0.15, 1], intensity: 0.32 });
    },
    crack(h) {
      h.fx('kael.bite', floorAt(h, 1.65), { k: 0.9 });
      h.cam.shake(0.35, { freq: 14, dir: [0, 1, 0] });
      h.pulse(floorAt(h, 1.65), null, 0.35);
      return false;                                         // replaces the generic crack decal (kael.bite lays its own)
    },
    hit(h, e) { accent(h, 0.6, [1, -0.6, 0.3], -70); return hitFeel(h, e, { dir: [1, -0.6, 0.3], intensity: 0.4 }); },
    recover(h) { h.fx('kael.ashfall', floorAt(h, 1.5), { radius: 0.8 }); },
  },
  // 용광로 휘두르기 Furnace Sweep — armoured coil, 300° horizontal spin, huge trail, wall of sparks
  sweep: {
    windup(h) {
      h.glow(h.color('mid', 0.03), 1, 0.4, 0.12);           // armour cracks blaze through the coil (hyper-armour tell)
      h.weaponGlow(0.7, 0.45);
    },
    armour(h) {
      h.fx('kael.shell', 'floor', { follow: h.self.char.root, duration: 0.22, lite: true, fallback: null });
      h.audio('fire_ignite', { volume: 0.6 });
    },
    swing(h) {
      h.fx('ember.slash', { pos: [0.05, 1.05, 0] }, { arc: [-300, 2], radius: 2.1, width: 0.7, sweep: 0.13, normal: [0, 1, 0.18], forward: [1, 0, 0], intensity: 0.3 });
      h.cam.kick({ fov: -2, duration: 0.3 });
    },
    sparks(h) {
      h.burst(WALL, [1.0, 1.0, 0.2], { dir: h.dir([1, 0.25, 0.35]), count: 34 });
      h.distort([1.0, 1.0, 0.2], { kind: 'shock', radius: [0.3, 2.6], life: 0.4, strength: 0.03 });
      h.spawn('ring', 'floor', { look: 'fire', radius: [0.4, 2.6], life: 0.5, intensity: 0.32 });
    },
    hit(h, e) { accent(h, 0.7, [1, 0.05, 0.35], 5); return hitFeel(h, e, { dir: [1, 0.05, 0.35], intensity: 0.42, kick: 1.5 }); },
    recover(h) { h.fx('kael.ashfall', floorAt(h, 0.8), { radius: 1.2 }); },
  },
  // 돌진 찌르기 Molten Lunge — shoulder-first charge, magma streak behind, thrust, crumple
  lunge: {
    windup(h) { h.glow(h.color('mid', 0.025), 1, 0.3, 0.05); },
    charge(h) {
      const x = st(h);
      x.streak = h.spawn('ribbon', 'hips', { follow: h.self.sockets.hips, width: 0.42, life: 0.28, color: STREAK });
      h.fx('combat.dust.dash', 'floor', { k: 0.8, fallback: null });
      h.spawn('speedlines', 'foe.chest', { mode: 'focus', life: 0.3, intensity: 0.22, inner: 0.66 });
      h.audio('fire_burst', { volume: 0.5 });
    },
    swing(h) {
      const x = st(h);
      if (x.streak) { x.streak.stop(); x.streak = null; }
      h.flare('weaponTip', { kind: 'streak', size: 0.4, aspect: 9, life: 0.12, decay: 2.5, intensity: 0.2, dir: h.dir([1, 0, 0]) });
      h.burst(SPEAR, 'weaponTip', { dir: h.dir([1, 0.05, 0.1]), count: 24 });
      h.cam.kick({ fov: -2.5, push: 0.25, duration: 0.3 });
    },
    hit(h, e) { accent(h, 0.7, [1, 0, 0.25], 0); return hitFeel(h, e, { dir: [1, 0, 0.25], intensity: 0.4, kick: 1.2 }); },
    end(h) { cleanup(h); },
  },
  // 분화 올려베기 Vent Launcher — the blade splits the floor, fire geyser, launch
  vent: {
    windup(h) { h.weaponGlow(0.5, 0.25); },
    split(h) {
      h.spawn('decal', floorAt(h, 1.3), { kind: 'crack', radius: 1.1, magma: 1, reveal: 0.05, life: 3, cool: 2.2 });
      h.burst(SPIT, floorAt(h, 1.3), { dir: [0, 1, 0] });
      return false;                                         // own crack (the generic decal would land at the blade)
    },
    swing(h) {
      h.fx('ember.slash', { pos: [0.25, 1.15, 0.14] }, { arc: [-82, 92], radius: 1.6, width: 0.5, sweep: 0.08, normal: [0, -0.25, 1], roll: 6, intensity: 0.38 });
    },
    geyser(h) {
      // the geyser blooms just after the hit flash (game time: after the hit-stop) so the two never stack into one blob
      h.after(0.05, (h2) => {
        h2.fx('kael.geyser', floorAt(h2, 1.15), { k: 0.7, fallback: null });
        h2.cam.shake(0.3, { freq: 13, dir: [0, 1, 0] });
        h2.audio('fire_roar', { volume: 0.7 });
      });
    },
    hit(h, e) { accent(h, 0.75, [0.3, 1, 0.3], 90); return hitFeel(h, e, { dir: [0.3, 1, 0.3], intensity: 0.42 }); },
  },
  // 잿불 초승달 Ember Crescent — blade dragged on the floor (sparks, molten groove), a burning crescent wave detaches
  crescent: {
    windup(h) { h.audio('fire_ignite', { volume: 0.5 }); },
    drag(h) {
      st(h).groove = h.fx('kael.groove', 'weaponTip', { follow: h.self.sockets.weaponTip, duration: 0.24, fallback: null });
    },
    release(h) {
      h.fx('ember.slash', { pos: [0.3, 1.2, 0.14] }, { arc: [-95, 70], radius: 1.7, width: 0.55, sweep: 0.08, normal: [0, -0.15, 1], intensity: 0.38 });
      h.burst(SPIT, floorAt(h, 1.0), { dir: [0, 1, 0], count: 18 });
    },
    end(h) { cleanup(h); },
  },
  // 균열 분출 Fault Eruption — overhead raise, rune, aura; blade into the floor; cracks race 6 m; 4 magma columns
  eruption: {
    windup(h) { h.weaponGlow(0.55, 0.6); },
    rune(h) {
      h.spawn('decal', 'floor', { kind: 'rune', radius: 1.7, palette: 'ember', life: 1.1, reveal: 0.25, spin: 1.3, intensity: 1.0 });
      h.spawn('decal', 'floor', { kind: 'glow', radius: 1.3, palette: 'ember', life: 0.9, fadeIn: 0.15, intensity: 0.9 });
      return false;                                         // own rune (ember palette, a little longer)
    },
    aura(h) {
      st(h).aura = h.fx('ember.aura', 'floor', { follow: h.self.char.root, duration: 0.32, intensity: 0.6, fallback: null });
      h.glow(h.color('mid', 0.03), 1, 0.3, 0.1);
      h.audio('fire_roar', { volume: 0.55 });
    },
    release(h) {
      h.fx('kael.bite', floorAt(h, 1.25), { k: 1.15 });
      h.cam.kick({ fov: -2.2, duration: 0.3 });
      h.pulse(floorAt(h, 1.25), null, 1.0);
    },
    crack(h) {
      h.fx('kael.fault', floorAt(h, 1.45), { length: 5.4, speed: 18.75, fallback: null });
      // camera: low ground skim racing along the crack toward the opponent (0.5 s, slow motion 0.6), framed wide
      // enough (4.5 m off the line) that the columns read as columns, then back to fight framing
      if (h.ctx.cam && h.ctx.cam.mode === 'fight') {
        h.cam.play([{ dur: 0.5, space: 'anchor', ease: 'outSine',
          from: { pos: [-0.8, 0.34, 4.9], look: [3.2, 1.25, 0], fov: 46, roll: -2 },
          to: { pos: [1.4, 0.42, 4.5], look: [4.6, 1.45, 0], fov: 42, roll: 0 },
          slowmo: { scale: 0.6, dur: 0.42, easeIn: 0.04, easeOut: 0.12 } }], { blendOut: 0.35, hud: false });
      }
      return false;                                         // replaces the generic camera cue of the marker data
    },
    recover(h) {
      h.fx('combat.dust.land', floorAt(h, 1.1), { k: 0.5, fallback: null });
      h.burst(CINDERS, [1.1, 0.4, 0.1], { count: 14 });
    },
    end(h) { cleanup(h); },
  },
  // 화염 갑주 Pyre Bulwark — sword planted, ember shell; struck in the window: instant counter
  bulwark: {
    windup(h) { h.fx('kael.bite', floorAt(h, 0.75), { k: 0.4 }); },
    shell(h) {
      st(h).shell = h.fx('kael.shell', 'floor', { follow: h.self.char.root, duration: 0.56, fallback: null });
      h.glow(h.color('mid', 0.035), 1, 0.58, 0.08);
      h.weaponGlow(0.8, 0.6);
      h.audio('fire_ignite', { volume: 0.8 });
    },
    shed(h) {
      const x = st(h);
      if (x.shell) { x.shell.stop(); x.shell = null; }
      h.fx('kael.shed', 'floor', { fallback: null });
    },
    counter(h) {
      cleanup(h);
      h.flash([6, 3, 1], 1, 0.18);                           // the shell flashes white-hot as it swallows the blow
      h.post.impact({ duration: 0.034, invert: 0, mono: 1 });
      h.post.chroma(0.6, { release: 0.3 });
      h.cam.shake(0.5, { freq: 14 });
      h.audio('release');
      return false;                                         // the explosion is the burst move's `explode` beat
    },
    end(h) { cleanup(h); },
  },
  bulwark_burst: {
    /** the counter catches: crash-zoom onto Kael (0.25 s; the marker's generic cue would frame the opponent) */
    counter(h) {
      if (h.ctx.cam && h.ctx.cam.mode === 'fight') {
        h.cam.play([h.shots.crashZoom({ dur: 0.25, subject: 'anchor', angle: 22, dist: [9, 3.6], height: [1.7, 1.4], look: 1.3, fov: [46, 32], shake: 0.4 })],
          { blendOut: 0.45, hud: false });
      }
      return false;
    },
    explode(h) {
      h.fx('ember.explosion', 'hips', { scale: 1.0, intensity: 0.5 });
      h.spawn('ring', 'floor', { look: 'fire', radius: [0.6, 4.4], width: [0.5, 1.2], life: 0.8, height: 0.7, intensity: 0.85 });
      h.after(0.3, (h2) => h2.fx('kael.ashfall', 'floor', { radius: 1.8, fallback: null }));
      h.pulse('floor', null, 1.4);
      h.audio('fire_burst');
      h.cam.shake(0.5, { freq: 14 });
      h.post.impact({ duration: 0.05, invert: 0, mono: 1 });
      return false;                                         // the marker's generic impact frame is an inverted (white) one
    },
    hit(h, e) { quietHit(h, e, false); return false; },     // no second inverted frame from the generic finisher feel
  },
  // 일식의 장작 Pyre of the Black Sun — the opener on the move clock (the lock is `ult` below)
  pyre: {
    ignite(h) {
      h.weaponGlow(1.6, 1.0, [9, 6.5, 3.6]);                 // white-hot blade
      h.flare('weaponTip', { kind: 'star', size: 2.4, life: 0.3, decay: 3, color: [9, 6.5, 3.2], intensity: 0.7 });
      h.audio('fire_roar', { volume: 0.8 });
    },
    leap(h) {
      // the ULT cut-in card (hud 'ult' style, 1.9 s from the freeze) would sit across the 1.00 punch-in and the X cuts:
      // it has been read for 0.6 s, so it dissolves on this cut instead
      fadeUltCard(0.22);
      // storyboard 0.60: cut to a wide side shot with a slight orbit for the leap-slash (held until the hit lands)
      h.cam.play([h.shots.orbitSweep({ dur: 0.5, cut: true, subject: 'mid', from: -6, to: 8, radius: [7.4, 6.6], height: [1.3, 1.6], look: 1.2, fov: 38, hold: true })], { blendOut: 0.4, keepLetterbox: true });
      h.spawn('speedlines', 'foe.chest', { mode: 'focus', life: 0.45, intensity: 0.55, inner: 0.6 });
      h.fx('combat.dust.dash', 'floor', { k: 1, fallback: null });
      h.afterimage({ count: 3, interval: 0.06, life: 0.32, palette: 'ember' });
      st(h).streak = h.spawn('ribbon', 'hips', { follow: h.self.sockets.hips, width: 0.5, life: 0.26, color: STREAK });
    },
    release(h) {
      st(h).slash = h.fx('ember.slash.heavy', { pos: [0.35, 1.75, 0.16] }, { arc: [150, -40], radius: 2.05, sweep: 0.1, normal: [0, 0.18, 1], intensity: 0.6 });
    },
    slam(h) {
      const x = st(h);
      if (x.streak) { x.streak.stop(); x.streak = null; }
      if (h.lockTime !== null) return false;                  // connected: the lock owns the impact
      // whiff / blocked: the huge slam still splits the floor, harmlessly
      h.fx('kael.bite', floorAt(h, 1.9), { k: 1.5 });
      h.fx('kael.geyser', floorAt(h, 2.0), { k: 0.6, fallback: null });
      return undefined;
    },
    end(h) { cleanup(h); },
    options: { whoosh: false },
  },
};

// every move: the ember library trail on trailOn / trailOff (instead of the generic ribbon), stopped on any end
for (const id of Object.keys(moves)) {
  const m = moves[id];
  m.options = { ...(m.options || {}), trail: false };
  const end = m.end;
  m.end = end || ((h) => cleanup(h));
}

// ---- the ultimate lock: storyboard t = 1.00 + lock t (BALANCE.md § 7) ---------------------------------------------
const ult = {
  mood: { darken: 0.75, tint: 0xff5020 },

  /** 0.00 super-freeze: Kael lifts the sword to the eclipse; the blade drinks the corona; embers are sucked upward. */
  freeze(h, e) {
    const d = e.duration || 0.6;
    h.fx('kael.updraft', 'floor', { duration: d, fallback: null });
    h.fx('kael.corona', 'weaponTip', { follow: h.self.sockets.weaponTip, duration: d, fallback: null });
  },

  /** camera of the lock (anchored on Kael, victim at cinematic.distance 1.7 m in front) */
  shots: (h) => [
    // 1.00 impact punch-in on the victim (lock 0 - 0.25)
    h.shots.impactPunchIn({ dur: 0.25, dist: [5.0, 3.7], height: [1.5, 1.45], shake: 0.5 }),
    // 1.25 orbit sweep 70 degrees around both: the X cuts (lock 0.25 - 1.30)
    h.shots.orbitSweep({ dur: 1.05, cut: true, subject: 'mid', from: -40, to: 30, radius: [5.0, 4.4], height: [1.25, 1.75], look: 1.3, fov: 38, handheld: 0.35 }),
    // 2.30 top-down slam view: the hurl, a geyser shooting at the lens (lock 1.30 - 1.80)
    h.shots.topDownSlam({ dur: 0.5, cut: true, subject: 'target', height: [6.8, 6.0], toward: [1.6, 1.3], fov: [44, 40], roll: [0, 8] }),
    // 2.80 ground-level skim looking up, slow motion 0.3: the leap after the victim, the spin (lock 1.80 - 2.74)
    { dur: 0.94, cut: true, space: 'anchor',
      from: { pos: [-1.3, 0.3, 4.9], look: [1.0, 2.8, 0], fov: 50, roll: -4 },
      to: { pos: [-0.2, 0.42, 4.5], look: [1.1, 3.5, 0], fov: 45, roll: 1 },
      ease: 'outSine', handheld: 0.4, slowmo: { scale: 0.3, at: 0.18, dur: 0.5, easeIn: 0.06, easeOut: 0.16 } },
    // 3.90 crash zoom from far onto the meteor slam (cut at lock 2.74 so the descent reads; impact at 2.90)
    h.shots.crashZoom({ dur: 0.56, cut: true, subject: 'target', angle: -14, dist: [14, 7.6], height: [3.8, 1.8], look: 1.0, fov: [48, 40], shake: false }),
    // 4.30 wide establishing: the shockwave crosses the arena (lock 3.30 - 4.20), then blend back
    h.shots.wideEstablishing({ dur: 0.9, cut: true, dist: [11.5, 12.5], height: [2.6, 3.1], look: [1.6, 1.5], drift: 1.2, shake: false }),
  ],
  blendOut: 1.0,

  /** 1.00 the blade connects: impact frame (3 monochrome frames), a short white flash, hit-stop 0.2, chroma, radial
   *  (storyboard chroma 1 / radial 0.8, tempered to 0.7 / 0.55 so the close punch-in stays readable) */
  start(h) {
    cleanup(h);
    // the leap-slash crescent would fill the punch-in frame: the impact replaces it with a crisp, readable hit
    const x = st(h);
    if (x.slash) { x.slash.kill(); x.slash = null; }
    const dir = [1, -0.35, 0.3];
    h.fx('combat.hit.crit', { pos: 'foe.chest', dir }, { element: 'ember', intensity: 0.35 });
    h.fx('kael.flower', { pos: 'foe.chest', dir }, { k: 0.6, cut: -50, accent: true, fallback: null });
    h.post.impact({ duration: 0.05, invert: 0, mono: 1 });     // 3 hard monochrome frames (no inverted white frame)
    h.post.flash(0xffffff, 0.14, { release: 0.2 });
    h.post.chroma(0.5, { release: 0.4 });
    h.post.radial('foe.chest', 0.5, { release: 0.35 });
    h.cam.shake(0.6, { freq: 13 });
    h.audio('hit_crit');
    h.audio('fire_burst', { volume: 0.7 });
    h.hitstop(0.2);
    h.foe.flash([1.4, 1.1, 0.9], 0.5, 0.2);
    h.pulse('foe.floor', null, 1.2);
    return false;
  },

  at: [
    // the victim is held; Kael's blade still smoulders
    { t: 0.01, do(h) { foeState(h, 'hitHeavy', { fade: 0, startAt: 0.06 }); h.weaponGlow(1.0, 1.4, [8, 4.5, 1.6]); } },
    { t: 0.1, do(h) { if (hasClip('kael.ult.cuts')) beat(h, 'cuts'); foeState(h, 'locked', { fade: 0.15 }); } },
    { t: 0.15, do(h) { if (hasClip('kael.ult.cuts')) trailOn(h, 'light', 0.47); } },
    { t: 0.75, do(h) { foeState(h, 'locked', { fade: 0.2 }); } },
    // 1.55 -> 2.30: Kael coils low for the hurl; the floor under the victim heats and cracks (anticipation)
    { t: 0.95, do(h) {
      if (hasClip('kael.ult.hurl')) beat(h, 'hurl');
      h.spawn('decal', 'foe.floor', { kind: 'crack', radius: 1.4, magma: 1, reveal: 0.3, life: 4, cool: 3 });
      h.spawn('decal', 'foe.floor', { kind: 'glow', radius: 1.5, palette: 'ember', life: 0.5, fadeIn: 0.3, intensity: 1.2 });
      h.weaponGlow(1.3, 0.5, [9, 5, 1.8]);
    } },
    { t: 1.1, do(h) { if (!hasClip('kael.ult.hurl')) beat(h, null, 'vent', 0.2); } },
    { t: 1.18, do(h) { h.burst(SPIT, 'foe.floor', { dir: [0, 1, 0], count: 22 }); } },
    { t: 1.21, do(h) { trailOn(h, 'rising', 0.3); } },
    // 2.80 Kael leaps after the victim, sky turns crimson, the inferno begins under them
    { t: 1.8, do(h) {
      beat(h, 'leapAfter', 'vent', 0.0);
      h.offset([0.85, 2.75], 0.42, 'outCubic');
      h.foeOffset([-0.35, 3.05], 0.7, 'outSine');
      h.mood({ darken: 0.86, tint: 0xff2a10, duration: 0.5 });
      // the firestorm under the airborne pair (own preset: the library inferno's centre detonation buried the rise)
      h.fx('kael.inferno', 'foe.floor', { radius: 1.7, duration: 1.5, intensity: 0.5, fallback: null });
      h.fx('combat.dust.land', 'floor', { k: 1.2, heavy: true, fallback: null });
      h.afterimage({ count: 2, interval: 0.05, life: 0.3, palette: 'ember' });
      h.audio('fire_roar');
    } },
    { t: 2.4, do(h) { beat(h, 'spin', 'sweep', 0.12); } },
    // 3.90 the meteor: both bodies come down as one burning mass; the crater opens at the finish (lock 2.90)
    { t: 2.7, do(h) { beat(h, 'meteor', 'light3', 0.2); } },
    { t: 2.72, do(h) {
      h.offset([0.6, 0], 0.18, 'inQuad');
      h.foeOffset([-0.3, 0], 0.18, 'inQuad');
      foeState(h, 'fall', { fade: 0.04 });
      // the floor under the pair glows as they come down (the crater itself opens on the finish tick)
      h.spawn('decal', 'foe.floor', { kind: 'glow', radius: 1.6, palette: 'ember', life: 0.32, fadeIn: 0.14, intensity: 0.9 });
      h.spawn('speedlines', 'foe.floor', { mode: 'focus', life: 0.2, intensity: 0.25, inner: 0.65 });
      st(h).streak = h.spawn('ribbon', 'hips', { follow: h.self.sockets.hips, width: 0.55, life: 0.2, color: STREAK });
    } },
    { t: 2.8, do(h) { trailOn(h, 'overhead', 0.16); } },
    // 5.20 Kael rises from the crater, sword onto the shoulder; embers and smoke linger 3 s
    { t: 4.2, do(h) {
      beat(h, 'rise', null);
      if (!hasClip('kael.ult.rise')) h.play(h.self.actor.clips.state('idle').name, { fade: 0.4 });
      h.offset([0, 0], 0.9, 'inOutSine');
      h.emitter(LINGER, 'foe.floor', { duration: 3 });
      h.fx('kael.ashfall', 'foe.floor', { radius: 2.4, smoke: true, fallback: null });
    } },
  ],

  markers: {
    /** 3.40: one full spin in the air, the blade trailing a full ring of fire */
    spin(h) {
      h.fx('kael.ringOfFire', 'chest', { radius: 1.75, sweep: 0.2, fallback: null });
      h.afterimage({ count: 3, interval: 0.04, life: 0.3, palette: 'ember' });
      trailOn(h, 'huge', 0.35);
      h.audio('swing_huge');
    },
    /** 4.30: the shockwave crosses the arena, pillars of fire; letterbox out */
    shockwave(h) {
      h.fx('kael.shockwave', 'foe.floor', { pillars: 5, fallback: null });
      h.post.pulse('exposure', 0.12, { attack: 0.04, hold: 0.1, release: 0.6 });
      h.post.chroma(0.5, { release: 0.5 });
      h.cam.letterbox(false, 0.8);
      h.pulse('foe.floor', null, 1.6);
      return undefined;                                     // generic: shake 1.0 + ult_impact from the marker data
    },
  },

  /** cuts, hurl and the meteor finish (replaces the generic tick feel; bookkeeping kept) */
  tick(h, e) {
    tickBookkeeping(h, e);
    const name = e.marker;
    if (name === 'cut1' || name === 'cut2' || name === 'cut3') {
      // three rapid burning cuts in an X
      const k = name === 'cut1' ? 0 : name === 'cut2' ? 1 : 2;
      const arcs = [[128, -40], [-58, 112], [175, -5]];
      const rolls = [-28, 24, 0];
      if (!hasClip('kael.ult.cuts')) beat(h, null, ['light1', 'light2', 'sweep'][k], 0.06);
      h.fx('ember.slash', { pos: [0.55, 1.45, 0.2] }, { arc: arcs[k], radius: 1.6, width: 0.55, sweep: 0.06, normal: [0, 0.1, 1], roll: rolls[k], intensity: 0.5 });
      h.fx('kael.flower', { pos: 'foe.chest', dir: [1, k === 1 ? 0.5 : -0.5, 0.3] }, { k: 0.7, cut: [-40, 55, 0][k], fallback: null });
      if (!hasClip('kael.ult.cuts')) trailOn(h, 'light', 0.16);
      foeState(h, 'hitHeavy', { fade: 0, startAt: 0.06 });
      h.foe.impulse([-1, 0.1, 0.15], 1.1);
      h.cam.shake(0.32, { freq: 17 });
      h.post.chroma(0.45, { release: 0.2 });
      h.audio('hit_slash_heavy');
      h.hitstop(e.hitstop || 0.06);
      return false;
    }
    if (name === 'hurl') {
      // 2.30 the rising cut hurls the victim: a fire geyser under it, debris, crit
      h.fx('kael.geyser', 'foe.floor', { k: 1.1, fallback: null });
      h.fx('combat.hit.heavy', { pos: 'foe.chest', dir: [0.3, 1, 0.3] }, { element: 'ember', intensity: 0.6 });
      h.foeOffset([-0.3, 2.4], 0.45, 'outCubic');
      foeState(h, 'launched', { fade: 0.04 });
      h.foe.impulse([-0.3, 1, 0], 1.6);
      h.cam.shake(0.55, { freq: 12, dir: [0, 1, 0] });
      h.post.chroma(0.6, { release: 0.3 });
      h.audio('fire_burst');
      h.hitstop(e.hitstop || 0.1);
      return false;
    }
    if (e.final) {
      // 3.90 the meteor slam: crater (ember.meteor), magma rim, the victim driven into the floor
      const x = st(h);
      if (x.streak) { x.streak.stop(); x.streak = null; }
      h.fx('kael.crater', 'foe.floor', { intensity: 0.5, fallback: null });
      h.spawn('decal', 'foe.floor', { kind: 'scorch', radius: 3.6, life: 8, magma: 1 });
      h.post.impact({ duration: 0.05, invert: 0, mono: 1 });
      h.post.flash(0xffffff, 0.08, { release: 0.25 });
      h.post.chroma(0.45, { release: 0.4 });
      h.post.radial('foe.floor', 0.45, { release: 0.4 });
      h.cam.shake(0.8, { freq: 11, dir: [0, 1, 0] });
      foeState(h, 'down', { fade: 0.05 });
      h.foe.impulse([0, -1, 0], 2);
      h.audio('explosion');
      h.audio('fire_burst', { volume: 0.8 });
      h.hitstop(Math.min(0.14, e.hitstop || 0.14));         // the rules hold the bodies 0.22; the picture breathes sooner
      return false;
    }
    return undefined;
  },

  /** whiff / blocked: the opener's slam already split the floor; let the embers settle */
  whiff(h) { cleanup(h); h.fx('kael.ashfall', 'floor', { radius: 1.6, fallback: null }); },
  end(h) { cleanup(h); },
};

// ---- projectiles ----------------------------------------------------------------------------------------------------
const projectiles = {
  // the crescent wave: the library's ember.wave rides the rules projectile (generic); Kael adds the launch and impact
  'ember.wave': {
    spawn(h, e) {
      const p = new h.THREE.Vector3(e.x, 1.1, 0.1);
      h.flare(p, { kind: 'flash', size: 2.2, life: 0.1, decay: 3, intensity: 0.16 });
      h.spawn('ring', new h.THREE.Vector3(e.x, 0.02, 0), { look: 'fire', radius: [0.2, 1.4], life: 0.35, intensity: 0.6 });
    },
    hit(h, e) {
      h.spawn('decal', new h.THREE.Vector3(e.x, 0, 0), { kind: 'scorch', radius: 1.3, life: 3.5, magma: 0.9 });
      h.cam.shake(0.3, { freq: 15 });
      h.hitstop(0.08);
    },
    guard(h) { h.cam.shake(0.18); },
  },
  // Fault Eruption columns: own timing (the crack opens and spits 0.04 s before the rules arm the column)
  'ember.column': {
    spawn(h, e) {
      const at = new h.THREE.Vector3(e.x, 0.02, 0);
      const last = !!(e.data && e.data.last);
      const x = st(h);
      if (!x.cols) x.cols = new Map();
      if (x.cols.size > 16) x.cols.clear();
      x.cols.set(e.id, (e.data && e.data.index) || 1);
      h.after(Math.max(0, (e.delay || 0) - 0.04), (h2) => {
        h2.fx('kael.column', at, { last, fallback: null });
        h2.cam.shake(last ? 0.35 : 0.2, { freq: 14, dir: [0, 1, 0] });
        h2.audio('fire_burst', { volume: last ? 0.85 : 0.5 });
        if (last) h2.pulse(at, null, 1.2);
      });
      return false;
    },
    hit(h, e) {
      const x = st(h);
      const first = !x.cols || (x.cols.get(e.projectile) ?? 1) === 1;
      quietHit(h, e, first);
      return false;
    },
  },
};

// ---- fighter-wide hooks -----------------------------------------------------------------------------------------------
const on = {
  /** round intro: the planted blade is wrenched free in a spray of embers */
  intro(h) {
    h.after(0.35, (h2) => { h2.fx('kael.bite', floorAt(h2, 0.7), { k: 0.5 }); h2.weaponGlow(0.8, 0.8); h2.audio('fire_ignite', { volume: 0.6 }); });
  },
  /** victory: the armour blazes, ember aura, ash drifting */
  victory(h) {
    h.fx('ember.aura', 'floor', { follow: h.self.char.root, duration: 2.6, intensity: 0.8, fallback: null });
    h.weaponGlow(1.0, 2.5);
    h.after(0.4, (h2) => h2.fx('kael.ashfall', 'floor', { radius: 2, fallback: null }));
  },
  /** KO flourish on top of the generic KO */
  ko(h, e) {
    if (e.cinematic) return undefined;
    h.fx('kael.flower', { pos: 'foe.chest', dir: [1, 0.2, 0.3] }, { k: 1.4, fallback: null });
    h.after(0.5, (h2) => h2.fx('kael.ashfall', 'foe.floor', { radius: 1.8, fallback: null }));
    return undefined;
  },
};

// ---- markers shared by every move ---------------------------------------------------------------------------------------
const markers = {
  trailOn(h, e) {
    const d = (e && e.data) || {};
    trailOn(h, d.style, (TRAIL_WINDOW[e.move] ?? 0.35) + 0.05);
  },
  trailOff(h) { trailOff(h); },
};

export const present = {
  setup({ vfx }) {
    if (!vfx) return;
    defineKaelFx(vfx);
  },
  /** embers drip from the armour cracks all match long, a few rise off the shoulders */
  ambient(h) {
    const drip = h.emitter(DRIP, 'chest', { follow: 'chest' });
    const rise = h.emitter(RISE, 'chest', { follow: 'chest' });
    return [drip, rise];
  },
  moves,
  projectiles,
  markers,
  on,
  ult,
};

export default present;
