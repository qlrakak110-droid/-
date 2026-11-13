// VORN 볼른 — signature effects (registered by present.setup through vfx.define before vfx.prewarm()).
// Visual language (MOVES.md / the volt library): instantaneous and straight. Lines along the thrust axis, rings punched
// around the spear's axis, jagged forked bolts, strobing flicker, gold sparks that bounce, dark scorch and thin ozone.
// Palette: violet-white arc core (5, 3.5, 9) -> electric violet (1.6, 0.8, 4) -> gold sparks (8, 5, 1).
// Every preset spawns world-space VFX only (camera / post / sound are placed by the choreography in present.js).
//
//   vorn.flower      contact point, dir = strike axis    impact flower: star + axial streak, rings punched around the
//                                                         axis, (pierce) a line of light through the body, a gold exit
//                                                         cone, forked bolts, a grounding bolt, light, shock, static motes
//                    opts: k (0.5 light .. 1.6 ult), pierce
//   vorn.static      victim chest (opts.follow)          the victim seizes: arcs crawl over the body, small bolts jump
//                                                         across it every 60-120 ms (opts.duration)
//   vorn.tipCharge   spear tip (opts.follow)             charge: converging violet streaks and motes, growing tip glow,
//                                                         crackle, rising light (opts.duration, opts.pop = release pop)
//   vorn.skybolt     spear tip                           a bolt shoots from the tip into the sky, sky glow, falling gold
//   vorn.mark        floor point                         Stormfall marker: rune + scorch, crackle, rising motes, a light
//                                                         that swells, upward streamers just before the bolt (opts.warn)
//   vorn.clouds      floor point under the clouds        dark storm billows overhead lit from inside by sheet lightning
//   vorn.strikeX     floor point                         extras over volt.strike: ground bolts lashing out, floor glow,
//                                                         gold fountain, ozone (opts.k)
//   vorn.reform      floor point of the arrival          Arc Step re-forming: converging arcs, flash, floor ring, dust
//   vorn.line        a = start (floor), target = end     the charged lightning line left by Arc Step (opts.hold s)
//   vorn.detonate    a = start (floor), target = end     the line detonates: a ripple of bolts erupting along it
//   vorn.sweep       floor point under the blade         Gale Sweep floor drag: gold fountain, arcs, scorch, floor bolts
//   vorn.frozenRain  floor point (mid-arena)             rain streaks hanging still in the air (super-freeze)
//   vorn.rain        floor point                         rain lashing down (opts.duration)
//   vorn.storm       floor point (victim)                the ultimate's storm gathering into the spear: rune, clouds,
//                                                         rain, streaks converging into opts.tip, sky bolts around
//   vorn.pillar      floor point (crater)                the ultimate's colossal lightning pillar + crater + aftermath

import * as THREE from 'three';
import { LIB, PALETTE } from '../../vfx/library.js';
import { heatRamp } from '../../vfx/util.js';
import { KIT } from '../../vfx/presets/common.js';

export const V = PALETTE.volt;
const WHITE = [7, 6, 11];
const GOLD = { core: [10, 7.5, 3.5], mid: [8, 5, 1], tail: [0.7, 0.25, 0.02] };
const key = (t, c, a, m = 1) => [t, c[0] * m, c[1] * m, c[2] * m, a];

// ---- particle definitions (module scope, registered once in setup) -----------------------------------------------------

const GOLD_RAMP = heatRamp(GOLD.core, GOLD.mid, GOLD.tail);
export const DEFS = {
  /** gold sparks: ballistic, bouncy, many small */
  gold: { ...LIB.sparks, count: 30, bounce: 0.5, friction: 0.6, color: GOLD_RAMP },
  /** exit cone of long gold sparks along the strike axis */
  goldCone: { ...LIB.sparks, count: 30, spread: 26, speed: [5, 16, 1.4], life: [0.25, 0.8, 1.4], bounce: 0.5, friction: 0.6, color: GOLD_RAMP },
  /** sparks thrown up off the floor (blade drag, strikes) */
  goldUp: { ...LIB.sparks, count: 60, spread: [62, 26], speed: [3, 11, 1.3], life: [0.3, 1.1, 1.4], bounce: 0.45, friction: 0.6, color: GOLD_RAMP },
  goldRadial: { ...LIB.sparks, count: 90, spread: 180, emit: 'radial', speed: [4, 15, 1.4], life: [0.3, 1.1, 1.4], bounce: 0.5, friction: 0.6, color: GOLD_RAMP },
  /** gold drips that fall off charged metal (aftermath) */
  goldDrip: { ...LIB.sparks, count: 0, rate: 14, emit: 'random', spread: 180, speed: [0.2, 1.4], life: [0.35, 0.9], size: [0.025, 0.06], bounce: 0.5, friction: 0.6, color: GOLD_RAMP },
  /** crackle arcs flying out (velocity-aligned arc sprites, strobing) */
  arcs: { tex: 'arc', blend: 'add', count: 10, life: [0.06, 0.18], shape: { type: 'sphere', radius: 0.22 }, emit: 'radial', spread: 20, speed: [5, 12],
    size: [0.28, 0.75], aspect: 2.2, align: 'velocity', stretch: 0.01, rotation: 0, flicker: { amount: 0.8, rate: 40 }, groundFade: 0,
    color: [key(0, WHITE, 1, 1.0), key(0.4, V.core, 1, 0.75), key(1, V.mid, 0)] },
  /** crawling arcs (no motion, random orientation, very short) */
  crawl: { tex: 'arc', blend: 'add', count: 6, life: [0.05, 0.12], shape: { type: 'sphere', radius: 0.3 }, emit: 'random', speed: 0,
    size: [0.18, 0.45], aspect: 1.8, rotation: [0, 6.28], flicker: { amount: 0.9, rate: 50 }, groundFade: 0,
    color: [key(0, WHITE, 1, 0.85), key(1, V.mid, 0, 1.2)] },
  /** idle crackle on the spear head (emitter) */
  crawlTip: { tex: 'arc', blend: 'add', count: 0, rate: 9, life: [0.04, 0.1], shape: { type: 'sphere', radius: 0.14 }, emit: 'random', speed: 0,
    size: [0.1, 0.26], aspect: 1.8, rotation: [0, 6.28], flicker: { amount: 0.9, rate: 50 }, groundFade: 0,
    color: [key(0, WHITE, 1, 0.75), key(1, V.mid, 0, 1.1)] },
  /** arcs crawling over a body (charged, seizing) */
  crawlBody: { tex: 'arc', blend: 'add', count: 0, rate: 34, life: [0.05, 0.12], shape: { type: 'box', size: [0.5, 1.5, 0.35] }, emit: 'random', speed: 0,
    size: [0.2, 0.5], aspect: 1.8, rotation: [0, 6.28], flicker: { amount: 0.9, rate: 50 }, groundFade: 0,
    color: [key(0, WHITE, 1, 0.8), key(1, V.mid, 0, 1.1)] },
  /** arcs crawling on the floor (charged ground, telegraphs, craters) */
  crawlGround: { tex: 'arc', blend: 'add', count: 0, rate: 26, life: [0.05, 0.14], shape: { type: 'disc', radius: 1 }, emit: 'random', speed: 0,
    size: [0.22, 0.55], aspect: 1.8, rotation: [0, 6.28], flicker: { amount: 0.9, rate: 50 }, groundFade: 0,
    color: [key(0, V.core, 1, 0.8), key(1, V.mid, 0, 1)] },
  /** ionised motes: rising, flickering */
  motes: { tex: 'dot', blend: 'add', count: 12, life: [0.4, 1.1], shape: { type: 'sphere', radius: 0.35 }, emit: 'random', speed: [0.2, 1.0],
    size: [0.025, 0.06, 2], gravity: 0.8, drag: 2, turbulence: { amp: 0.7, freq: 2, speed: 2 }, flicker: { amount: 0.8, rate: 25 },
    color: [key(0, V.core, 0, 0.8), key(0.1, V.core, 1, 0.8), key(1, V.mid, 0, 0.6)] },
  /** idle motes shed by the spear head (emitter) */
  motesTip: { tex: 'dot', blend: 'add', count: 0, rate: 5, life: [0.5, 1.2], shape: { type: 'sphere', radius: 0.12 }, emit: 'random', speed: [0.1, 0.4],
    size: [0.02, 0.045, 2], gravity: 0.5, drag: 2, turbulence: { amp: 0.5, freq: 2, speed: 2 }, flicker: { amount: 0.8, rate: 25 },
    color: [key(0, V.core, 0, 0.7), key(0.1, V.core, 1, 0.7), key(1, V.mid, 0, 0.5)] },
  /** motes rising from a charged floor (emitter) */
  motesUp: { tex: 'dot', blend: 'add', count: 0, rate: 40, life: [0.5, 1.2], shape: { type: 'disc', radius: 1 }, emit: 'axis', spread: 12, speed: [1, 3.2],
    size: [0.025, 0.06, 2], drag: 0.8, turbulence: { amp: 0.5, freq: 2, speed: 2 }, flicker: { amount: 0.8, rate: 25 },
    color: [key(0, V.core, 0, 0.8), key(0.1, V.core, 1, 0.8), key(1, V.mid, 0, 0.6)] },
  /** thin dark ozone wisps after a strike (alpha) */
  ozone: { ...LIB.smoke, count: 4, size: [0.4, 0.9], life: [0.8, 1.5], speed: [0.3, 1.0], gravity: 0.6,
    color: [[0, 0.3, 0.2, 0.6, 0], [0.06, 0.06, 0.05, 0.1, 0.5], [0.5, 0.045, 0.04, 0.06, 0.35], [1, 0.04, 0.04, 0.05, 0]] },
  /** smoke column out of the crater (alpha, violet-black) */
  smokeColumn: { ...LIB.smokeLinger, count: 9,
    color: [[0, 0.5, 0.35, 1.1, 0], [0.08, 0.07, 0.055, 0.12, 0.75], [0.4, 0.05, 0.045, 0.07, 0.6], [1, 0.045, 0.045, 0.05, 0]] },
  /** converging charge streaks (attract + swirl) */
  gather: { ...LIB.chargeStreaks, rate: 90, shape: { type: 'sphere', radius: 1.3, inner: 0.6 }, size: [0.02, 0.06, 1.6], life: [0.32, 0.55],
    color: [key(0, V.tail, 0, 4), key(0.25, V.mid, 1), key(1, WHITE, 1, 0.9)] },
  gatherMotes: { ...LIB.chargeMotes, rate: 26, shape: { type: 'sphere', radius: 0.9, inner: 0.5 }, life: [0.3, 0.55],
    color: [key(0, V.tail, 0, 3), key(0.3, V.mid, 1, 1.2), key(1, V.core, 0.6)] },
  /** the storm drawn into the spear from all around (ultimate) */
  gatherWide: { ...LIB.chargeStreaks, rate: 150, shape: { type: 'sphere', radius: 4.2, inner: 0.7 }, size: [0.03, 0.08, 1.6], life: [0.45, 0.8],
    stretch: 0.08, maxStretch: 1.2, color: [key(0, V.tail, 0, 4), key(0.25, V.mid, 1), key(1, WHITE, 1)] },
  /** violet flash core (1-3 frames) */
  flash: { ...LIB.flashCore, color: [[0, 8, 7, 11, 1], key(0.3, V.core, 0.75, 0.7), key(1, V.tail, 0)] },
  /** soft violet bloom puff */
  puff: { ...LIB.glowPuff, color: [key(0, V.core, 0.9, 0.4), key(0.3, V.mid, 0.45, 0.5), [1, 0, 0, 0, 0]] },
  /** violet floor glow under a strike (flat) */
  floorGlow: { tex: 'glow', blend: 'add', align: 'flat', count: 1, life: [0.6, 0.6], speed: 0, size: 3.0, groundFade: 0, rotation: 0,
    color: [[0, 3, 2, 6, 1], [0.15, 1.2, 0.6, 3, 0.6], [1, 0.05, 0.02, 0.2, 0]] },
  /** rain streaks hanging still in the air (super-freeze): barely drifting, long */
  frozenRain: { tex: 'streak', blend: 'add', count: 260, life: [0.95, 1.2], shape: { type: 'box', size: [15, 6, 6] }, emit: 'axis', dir: [-0.12, -1, 0], spread: 3,
    speed: [0.25, 0.4], size: [0.022, 0.04], stretch: 1.5, maxStretch: 0.7, rotation: 0, groundFade: 0.05,
    color: [[0, 0.6, 0.56, 1.1, 0], [0.12, 0.6, 0.56, 1.1, 0.6], [0.85, 0.5, 0.46, 0.95, 0.5], [1, 0.4, 0.36, 0.8, 0]] },
  /** rain lashing down */
  rain: { tex: 'streak', blend: 'add', count: 0, rate: 300, life: [0.25, 0.4], shape: { type: 'box', size: [15, 1, 6] }, emit: 'axis', dir: [-0.12, -1, 0], spread: 3,
    speed: [17, 23], size: [0.025, 0.045], stretch: 0.05, maxStretch: 1.6, rotation: 0, groundFade: 0.05,
    color: [[0, 1.0, 0.95, 1.8, 0], [0.15, 1.0, 0.95, 1.8, 0.75], [1, 0.55, 0.5, 1.1, 0.5]] },
  /** storm clouds: dark violet-grey billows (alpha) */
  cloud: { ...LIB.smokeLinger, count: 8, delay: [0, 0.15], shape: { type: 'disc', radius: 3.2, height: 0.6 }, emit: 'axis', spread: 70, speed: [0.2, 0.6], gravity: 0, swirl: 0.25, lift: 0,
    size: [2.6, 4.2, 1.3], life: [1.6, 2.4], color: [[0, 0.16, 0.12, 0.3, 0], [0.15, 0.1, 0.085, 0.17, 0.85], [0.7, 0.07, 0.06, 0.11, 0.7], [1, 0.05, 0.045, 0.07, 0]] },
  /** sheet lightning inside the clouds (big dim flickering glows) */
  cloudGlow: { tex: 'smoke', blend: 'add', count: 9, life: [0.1, 0.24], delay: [0, 0.6], shape: { type: 'disc', radius: 3.4, height: 0.6 }, speed: 0, size: [2.6, 4.6],
    flicker: { amount: 0.9, rate: 18 }, groundFade: 0, color: [[0, 0.8, 0.5, 1.8, 0.7], [0.4, 0.4, 0.22, 1.0, 0.45], [1, 0.05, 0.02, 0.2, 0]] },
  dust: { ...LIB.dustRing },
  dustSmall: { ...LIB.dustRing, count: 6, speed: [0.8, 2.6], size: [0.25, 0.55, 1.3], life: [0.45, 0.9], shape: { type: 'ring', radius: 0.12, thickness: 0.1 }, lift: 0.3 },
  pebbles: { ...LIB.pebbles },
};
// variants (shape / emission) of the layers above, at module scope so no definition is built per call
Object.assign(DEFS, {
  crawlLine: { ...DEFS.crawl, shape: { type: 'line' } },
  motesLine: { ...DEFS.motes, shape: { type: 'line' } },
  arcsLine: { ...DEFS.arcs, shape: { type: 'line' }, speed: [2, 6], size: [0.2, 0.55] },
  goldFan: { ...DEFS.gold, emit: 'axis', spread: 70 },
  goldRing: { ...DEFS.gold, emit: 'radial', spread: 70 },
  gatherBurst: { ...DEFS.gather, count: 40, rate: 0, life: [0.08, 0.14], shape: { type: 'sphere', radius: 1.0, inner: 0.7 } },
});

const vec = (p) => (p && p.isVector3 ? p.clone() : new THREE.Vector3(p[0], p[1], p[2]));

/**
 * Register Vorn's particle definitions and presets.
 * @param {object} vfx  ctx.vfx
 * @param {object} rng  deterministic rng (ctx.rng)
 */
export function defineVornFx(vfx, rng) {
  for (const name in DEFS) vfx.particleDef('vorn.' + name, DEFS[name]);
  const D = DEFS;
  const R = () => (rng ? rng() : 0.5);
  const jit = (p, r, ry = r, rz = r) => new THREE.Vector3(p.x + (R() - 0.5) * 2 * r, p.y + (R() - 0.5) * 2 * ry, p.z + (R() - 0.5) * 2 * rz);
  const I = (o) => (o && o.intensity != null ? o.intensity : 1);
  const lightAt = (p, up = 0.2, side = 1.1) => new THREE.Vector3(p.x, p.y + up, p.z + side);

  // ---- contact flower ---------------------------------------------------------------------------------------------
  vfx.define('vorn.flower', (v, at, o) => {
    const k = o.k ?? 1, s = at.scale, p = at.pos, d = at.dir, i = I(o);
    // the generic hit (combat.hit.<level> in volt) carries the flash core and the light: these layers add the spear's
    // signature around it and stay thin so the struck body always reads
    v.flare({ kind: 'streak', pos: p, size: (0.05 + 0.05 * k) * s, aspect: 16, life: 0.08 + 0.05 * k, dir: d, color: WHITE, intensity: 0.3 * i, realtime: true });
    if (k >= 1.2) v.flare({ kind: 'star', pos: p, size: (0.2 + 0.3 * k) * s, life: 0.1 + 0.05 * k, decay: 3, color: V.core, intensity: 0.2 * i, rotation: 0.35, realtime: true });
    // rings punched around the strike axis, one behind the other (the spear's signature)
    const nr = k >= 1.2 ? 2 : 1;
    for (let j = 0; j < nr; j++) {
      const c = p.clone().addScaledVector(d, (0.1 + 0.3 * j) * s);
      v.schedule(0.02 * j, (w) => w.ring({ look: 'volt', normal: d, pos: c, radius: [0.04 * s, (0.2 + 0.16 * k + 0.08 * j) * s], width: [0.03 * s, 0.06 * s], life: 0.15, intensity: 0.35 * i, alpha: 0.7 }));
    }
    // a line of light through the body (armour-piercing thrusts)
    if (o.pierce) v.beam({ look: 'volt', from: p.clone().addScaledVector(d, -0.2 * s), to: p.clone().addScaledVector(d, (0.6 + 0.5 * k) * s), width: 0.09 * s, extend: 0.02, release: 0.07, life: 0.12, flares: false, intensity: 0.5 * i });
    // sparks are born one game frame later: they burst out when the hit-stop releases instead of piling up at the contact
    v.schedule(0.017, (w) => {
      w.burst(D.goldCone, { pos: p, dir: d, count: Math.round((8 + 20 * k) * i), scale: s });
      w.burst(D.arcs, { pos: p, dir: d, count: Math.round((3 + 5 * k) * i), scale: 0.8 * s });
    });
    // forked bolts lashing out of the contact along the strike, one grounding into the floor on heavy hits
    const nb = k >= 1.2 ? 2 : k >= 0.8 ? 1 : 0;
    for (let j = 0; j < nb; j++) {
      const to = jit(p.clone().addScaledVector(d, (0.7 + 0.4 * k) * s), 0.4 * s, 0.5 * s, 0.25 * s);
      v.schedule(0.015 * j, (w) => w.bolt({ from: p, to, width: 0.06 * s, branches: 1, strikes: 2, detail: 5, life: 0.16, leader: 0.01, impact: false, intensity: 0.6 * i }));
    }
    if (k >= 1.0 && p.y > 0.4) {
      const g = new THREE.Vector3(p.x + d.x * 0.7 + (R() - 0.5) * 0.6, 0.03, p.z + 0.2 + R() * 0.3);
      v.schedule(0.03, (w) => { w.bolt({ from: p, to: g, width: 0.07 * s, branches: 1, strikes: 2, life: 0.2, leader: 0.02, impact: false, intensity: 0.6 * i }); w.decal({ kind: 'scorch', pos: g, radius: 0.4 * s, life: 2.5, palette: 'volt', magma: 0.5 }); });
    }
    if (k >= 1.0) v.light({ pos: lightAt(p, 0.2, 1.3), color: V.core, intensity: (12 + 18 * k) * i, range: 4, duration: 0.15, flicker: 0.5, realtime: true });
    if (k >= 0.8) v.schedule(0.035, (w) => w.distort({ kind: 'shock', pos: p, normal: d, radius: [0.1 * s, (0.5 + 0.6 * k) * s], life: 0.28, strength: 0.03 }));
    v.burst(D.motes, { pos: p, count: Math.round(3 + 6 * k), scale: s });
    if (k >= 0.9) v.burst(D.ozone, { pos: p, dir: [0, 1, 0], count: 2, scale: 0.6 * s, delay: 0.08 });
    if (k >= 1.2) v.burst(KIT.volt.scrap, { pos: p, dir: [d.x, d.y + 0.5, d.z], count: 2, scale: 0.9 * s });   // talisman slips, violet script
  });

  // ---- lightning along the spear (thrusts): a thin line base -> tip, a streak and a ring at the tip -------------------
  vfx.define('vorn.spear', (v, at, o) => {
    const s = at.scale, i = I(o), a = at.pos, b = vec(at.target);
    const d = b.clone().sub(a).normalize(), ext = b.clone().addScaledVector(d, (o.reach ?? 0.25) * s);
    v.beam({ look: 'volt', from: a, to: ext, width: (o.width ?? 0.07) * s, extend: 0.025, release: 0.07, life: o.life ?? 0.1, wiggle: 0.02, flares: false, intensity: 0.45 * i });
    v.flare({ kind: 'streak', pos: ext, size: 0.07 * s, aspect: 14, life: 0.09, dir: d, color: WHITE, intensity: 0.3 * i });
    v.ring({ look: 'volt', normal: d, pos: ext, radius: [0.03 * s, 0.26 * s * (o.ring ?? 1)], width: [0.04 * s, 0.07 * s], life: 0.14, intensity: 0.5 * i, alpha: 0.8 });
    v.burst(D.goldCone, { pos: ext, dir: d, count: Math.round(8 * i), scale: 0.7 * s });
    v.burst(D.arcsLine, { pos: a, to: ext, count: Math.round(3 * i), scale: 0.7 * s });
  });

  // ---- electric crescent (smears of the spear) ------------------------------------------------------------------
  vfx.define('vorn.arc', (v, at, o) => {
    const s = at.scale, i = I(o), f = at.facing;
    const plane = { normal: o.normal || [0, 0.2, 1], forward: o.forward || [1, 0, 0], roll: o.roll || 0, facing: f };
    const arc = o.arc || [150, -30], R0 = (o.radius ?? 1.4) * s, sweep = o.sweep ?? 0.07;
    v.slash({ look: 'electric', pos: at.pos, ...plane, arc, radius: R0, width: (o.width ?? 0.22) * s, sweep, life: o.life ?? 0.26, intensity: 0.42 * i, alpha: 0.8 });
    v.slash({ look: 'razor', palette: 'volt', core: WHITE, pos: at.pos, ...plane, arc, radius: R0 * 0.995, width: 0.035 * s, sweep, life: 0.1, intensity: 0.6 * i });
  });

  // ---- the victim seizes (loop over opts.duration) ----------------------------------------------------------------
  vfx.define('vorn.static', (v, at, o) => {
    const s = at.scale, dur = o.duration ?? 0.6, follow = o.follow || null;
    const em = v.emitter(D.crawlBody, { pos: at.pos, scale: s, duration: dur, intensity: I(o) });
    if (follow) em.follow(follow, [0, -0.25, 0.05]);
    const drip = v.emitter(D.goldDrip, { pos: at.pos, scale: s, duration: dur });
    if (follow) drip.follow(follow);
    const base = new THREE.Vector3();
    let live = true, t = 0;
    const tick = (w) => {
      if (!live || t > dur) return;
      if (follow) follow.getWorldPosition(base); else base.copy(at.pos);
      const a = jit(base, 0.3 * s, 0.6 * s, 0.15 * s), b = jit(base, 0.3 * s, 0.6 * s, 0.15 * s);
      w.bolt({ from: a, to: b, width: 0.08 * s, branches: 1, strikes: 2, interval: [0.02, 0.04], detail: 4, life: 0.1, leader: 0, impact: false, glow: 0.9, intensity: 0.9 * I(o) });
      const gap = 0.06 + R() * 0.06;
      t += gap;
      w.schedule(gap, tick);
    };
    v.schedule(0.02, tick);
    return { stop() { live = false; } };
  });

  // ---- charge at the spear tip -------------------------------------------------------------------------------------
  vfx.define('vorn.tipCharge', (v, at, o) => {
    const T = o.duration ?? 0.3, s = at.scale, follow = o.follow || null, i = I(o);
    const hs = [v.emitter(D.gather, { pos: at.pos, scale: s, duration: T, intensity: i }), v.emitter(D.gatherMotes, { pos: at.pos, scale: s, duration: T * 0.9, intensity: i }),
      v.emitter(D.crawlTip, { pos: at.pos, scale: 1.4 * s, duration: T + 0.05 })];
    hs[2].rate = 34;
    const fl = v.flare({ kind: 'glow', pos: at.pos, size: [0.1 * s, 0.5 * s], life: T + 0.06, attack: T * 0.85, decay: 6, color: V.core, intensity: 0.4 * i });
    const lt = v.light({ pos: lightAt(at.pos, 0.1, 1.4), color: V.core, intensity: 22 * i, range: 4, duration: T + 0.08, curve: [[0, 0], [0.85, 1], [1, 0.6]], flicker: 0.4 });
    if (follow) { for (const h of hs) h.follow(follow); fl.follow(follow); lt.follow(follow, [0, 0.1, 0.9]); }
    if (o.pop) {
      const tip = new THREE.Vector3();
      v.schedule(T, (w) => {
        if (follow) follow.getWorldPosition(tip); else tip.copy(at.pos);
        w.burst(D.flash, { pos: tip, scale: 0.3 * s, intensity: 0.45 });
        w.burst(D.arcs, { pos: tip, count: 10, scale: s });
        w.burst(D.gold, { pos: tip, dir: [0, 1, 0], count: 16, scale: 0.7 * s });
      });
    }
  });

  // ---- a bolt from the spear tip into the sky ---------------------------------------------------------------------
  vfx.define('vorn.skybolt', (v, at, o) => {
    const s = at.scale, f = at.facing, p = at.pos, i = I(o);
    const top = new THREE.Vector3(p.x + f * (0.9 + R() * 0.8), 15, p.z - 3);
    v.bolt({ from: p, to: top, width: 0.32 * s, branches: 5, strikes: 3, interval: [0.04, 0.08], leader: 0.03, life: 0.42, impact: false, intensity: i });
    v.schedule(0.02, (w) => w.bolt({ from: p, to: jit(top, 2.5, 1, 1), width: 0.14 * s, branches: 2, strikes: 2, leader: 0.02, life: 0.3, impact: false, intensity: 0.7 * i }));
    v.flare({ kind: 'streak', pos: p, size: 0.1 * s, aspect: 14, life: 0.14, dir: [0, 1, 0], color: WHITE, intensity: 0.4 * i });
    v.ring({ look: 'volt', normal: [0, 1, 0.25], pos: p, radius: [0.05 * s, 0.6 * s], width: [0.05 * s, 0.1 * s], life: 0.2, intensity: 0.55 * i });
    v.burst(D.goldFan, { pos: p, dir: [0, 1, 0], count: Math.round(34 * i), scale: 0.8 * s });
    v.burst(D.arcs, { pos: p, count: 10, scale: s });
    // the clouds light up where the bolt enters them
    v.flare({ kind: 'flash', pos: new THREE.Vector3(top.x, 9, top.z), size: 6, life: 0.3, decay: 2, color: V.mid, intensity: 0.12 * i, pull: 0 });
    v.light({ pos: lightAt(p, 0.5, 1.6), color: V.core, intensity: 35 * i, range: 5, duration: 0.25, flicker: 0.6 });
  });

  // ---- Stormfall marker under the opponent ----------------------------------------------------------------------
  vfx.define('vorn.mark', (v, at, o) => {
    const s = at.scale, g = new THREE.Vector3(at.pos.x, 0.02, at.pos.z), warn = o.warn ?? 0.37;
    v.decal({ kind: 'rune', pos: new THREE.Vector3(g.x, 0, g.z), radius: 1.45 * s, palette: 'volt', life: warn + 1.1, reveal: Math.min(0.25, warn * 0.6), fadeOut: 0.4, spin: 1.6, intensity: 1.1 });
    v.decal({ kind: 'scorch', pos: new THREE.Vector3(g.x, 0, g.z), radius: 0.7 * s, life: warn + 3.5, palette: 'volt', magma: 0.9 });
    v.emitter(D.crawlGround, { pos: new THREE.Vector3(g.x, 0.08, g.z), dir: [0, 1, 0], scale: 1.15 * s, duration: warn }).rate = 30;
    v.emitter(D.motesUp, { pos: new THREE.Vector3(g.x, 0.05, g.z), dir: [0, 1, 0], scale: 0.9 * s, duration: warn + 0.1 }).rate = 34;
    v.light({ pos: new THREE.Vector3(g.x, 0.5, g.z + 1.2), color: V.core, intensity: 25, range: 4, duration: warn + 0.05, curve: [[0, 0], [0.8, 1], [1, 1]], flicker: 0.5, flickerRate: 18 });
    // upward streamers reaching for the descending bolt (the last instant before it lands)
    const lead = Math.max(0.05, warn - 0.1);
    for (let j = 0; j < 3; j++) {
      v.schedule(lead + j * 0.025, (w) => {
        const a = jit(g, 0.6 * s, 0, 0.3 * s); a.y = 0.03;
        w.bolt({ from: a, to: jit(new THREE.Vector3(g.x, 1.6 + R() * 1.2, g.z), 0.4, 0.3, 0.2), width: 0.07 * s, branches: 1, strikes: 2, detail: 5, life: 0.1, leader: 0.03, impact: false, intensity: 0.7 });
      });
    }
  });

  // ---- storm clouds overhead -----------------------------------------------------------------------------------
  vfx.define('vorn.clouds', (v, at, o) => {
    const s = at.scale, c = new THREE.Vector3(at.pos.x, 6.4 * s, at.pos.z - 1.6), dur = o.duration ?? 1.2;
    v.burst(D.cloud, { pos: c, dir: [0, 1, 0], scale: s });
    v.burst(D.cloudGlow, { pos: new THREE.Vector3(c.x, c.y - 0.3, c.z + 0.6), dir: [0, 1, 0], scale: s });
    v.light({ pos: new THREE.Vector3(c.x, 4.5, c.z + 2.2), color: V.core, intensity: 30, range: 10, duration: dur, attack: 0.1, flicker: 0.85, flickerRate: 9 });
  });

  // ---- a sky bolt onto a floor point (Stormfall): Vorn's own strike, bright where it lands but never a white sheet ----
  vfx.define('vorn.skystrike', (v, at, o) => {
    const k = o.k ?? 1, s = at.scale, f = at.facing, i = I(o), g = new THREE.Vector3(at.pos.x, 0.02, at.pos.z);
    const top = new THREE.Vector3(g.x - f * (1.0 + R() * 0.8) * k, 12, g.z - 2.4);
    v.bolt({ from: top, to: new THREE.Vector3(g.x, 0.05, g.z), width: 0.3 * s * k, branches: Math.round(4 * k), strikes: 3, interval: [0.04, 0.08], life: 0.45, leader: 0.025, impact: false, light: 70 * k * i, lightRange: 8, intensity: 0.9 * i });
    v.pillar({ look: 'volt', pos: g, height: 12, radius: 0.16 * s * k, life: 0.45, intensity: 0.5 * i });
    v.burst(D.flash, { pos: new THREE.Vector3(g.x, 0.4, g.z + 0.2), scale: 0.3 * s * k, intensity: 0.3 * i });
    v.decal({ kind: 'scorch', pos: g, radius: 1.1 * s * k, life: 4.5, palette: 'volt', magma: 0.8 });
    v.decal({ kind: 'crack', pos: g, radius: 1.4 * s * k, life: 4.5, density: 0.9 });
    v.ring({ look: 'volt', pos: g, radius: [0.15 * s, 2.2 * s * k], life: 0.4, distort: 0.035, intensity: 0.6 * i });
    v.ring({ look: 'dust', pos: g, radius: [0.3 * s, 2.4 * s * k], life: 1.0 });
    v.burst(D.goldUp, { pos: g, dir: [0, 1, 0], count: Math.round(50 * k * i), scale: s });
    v.burst(D.arcs, { pos: new THREE.Vector3(g.x, 0.2, g.z), count: Math.round(10 * k), scale: 1.2 * s });
    v.burst(D.dust, { pos: g, dir: [0, 1, 0], count: Math.round(8 * k), scale: s * k });
    v.debris({ kind: 'rock', pos: [g.x, 0.1, g.z], count: Math.round(8 * k * i), speed: [3, 8, 1.3], spread: 45, scale: s });
    v.schedule(0.12, (w) => w.burst(D.ozone, { pos: new THREE.Vector3(g.x, 0.4, g.z), dir: [0, 1, 0], count: Math.round(4 * k), scale: s * k }));
    if (k > 1.2) {
      for (let j = 0; j < 2; j++) v.schedule(0.05 + j * 0.07, (w) => w.bolt({ from: new THREE.Vector3(g.x + (j ? 1 : -1) * 2.2, 11, g.z - 1.8), to: jit(g, 1.3 * s, 0, 0.4 * s).setY(0.05), width: 0.16 * s, branches: 3, strikes: 2, impact: false, intensity: 0.7 * i }));
      v.distort({ kind: 'shock', pos: new THREE.Vector3(g.x, 1, g.z), radius: [0.4 * s, 4 * s], life: 0.45, strength: 0.05 });
    }
  });

  // ---- extras over a strike (ground bolts lashing out, floor glow, gold fountain, ozone) ------------------------
  vfx.define('vorn.strikeX', (v, at, o) => {
    const k = o.k ?? 1, s = at.scale, g = new THREE.Vector3(at.pos.x, 0.03, at.pos.z), i = I(o);
    const n = Math.round(3 + 2 * k);
    for (let j = 0; j < n; j++) {
      const a = (j / n) * Math.PI * 2 + R() * 0.7, r = (1.2 + R() * 1.4) * k * s;
      const to = new THREE.Vector3(g.x + Math.cos(a) * r, 0.03, g.z + Math.sin(a) * r * 0.6);
      v.schedule(0.01 + j * 0.012, (w) => w.bolt({ from: g, to, width: 0.08 * s, branches: 2, strikes: 2, detail: 5, roughness: 0.3, life: 0.22, leader: 0.02, impact: false, intensity: 0.65 * i }));
    }
    v.burst(D.ozone, { pos: new THREE.Vector3(g.x, 0.5, g.z), dir: [0, 1, 0], count: Math.round(3 * k), scale: s, delay: 0.15 });
    v.emitter(D.crawlGround, { pos: g, dir: [0, 1, 0], scale: 0.9 * k * s, duration: 0.5 + 0.3 * k }).rate = 18;
  });

  // ---- Arc Step: re-forming -----------------------------------------------------------------------------------------
  vfx.define('vorn.reform', (v, at, o) => {
    const s = at.scale, g = new THREE.Vector3(at.pos.x, 0.02, at.pos.z), c = new THREE.Vector3(at.pos.x, 1.1 * s, at.pos.z + 0.1), i = I(o);
    v.burst(D.gatherBurst, { pos: c, scale: s });
    v.burst(D.flash, { pos: c, scale: 0.3 * s, intensity: 0.4 * i });
    v.flare({ kind: 'star', pos: c, size: 0.8 * s, life: 0.14, decay: 3, color: V.core, intensity: 0.25 * i, rotation: 0.6 });
    v.ring({ look: 'volt', pos: g, radius: [0.15 * s, 1.5 * s], life: 0.32, intensity: 0.6 * i, distort: 0.02 });
    v.burst(D.dustSmall, { pos: g, dir: [0, 1, 0], count: 7, scale: 1.2 * s });
    v.burst(D.goldRing, { pos: new THREE.Vector3(g.x, 0.1, g.z), dir: [0, 1, 0], count: 26, scale: 0.8 * s });
    v.burst(D.arcs, { pos: c, count: 12, scale: 1.2 * s });
    for (let j = 0; j < 2; j++) v.bolt({ from: jit(c, 0.25, 0.6, 0.1), to: new THREE.Vector3(g.x + (R() - 0.5) * 1.2, 0.03, g.z + R() * 0.4), width: 0.09 * s, branches: 1, strikes: 2, detail: 5, life: 0.16, leader: 0, impact: false, intensity: 0.8 * i });
    v.light({ pos: lightAt(c, 0, 1.5), color: V.core, intensity: 30 * i, range: 4.5, duration: 0.22, flicker: 0.5 });
  });

  // ---- Arc Step: the charged line, then its detonation -------------------------------------------------------------
  vfx.define('vorn.line', (v, at, o) => {
    const s = at.scale, hold = o.hold ?? 0.26, i = I(o);
    const a = new THREE.Vector3(at.pos.x, 0.14, at.pos.z + 0.05), b = vec(at.target); b.y = 0.14; b.z = at.pos.z + 0.05;
    v.beam({ look: 'volt', from: a, to: b, width: 0.12 * s, extend: 0.05, release: 0.06, life: hold, wiggle: 0.05, flares: false, intensity: 0.5 * i });
    v.bolt({ from: a, to: b, width: 0.08 * s, branches: 4, strikes: Math.max(2, Math.round(hold / 0.06)), interval: [0.04, 0.07], detail: 6, roughness: 0.22, life: hold, leader: 0.03, impact: false, intensity: 0.85 * i });
    const len = a.distanceTo(b);
    for (let x = 0.3; x < len; x += 0.9) {
      const p = a.clone().lerp(b, x / len); p.y = 0.02;
      v.schedule(0.02 + (x / len) * 0.05, (w) => w.decal({ kind: 'scorch', pos: p, radius: (0.35 + R() * 0.25) * s, life: 2.4 + R(), palette: 'volt', magma: 0.7 }));
    }
    for (let t = 0; t < hold; t += 0.06) v.schedule(t, (w) => w.burst(D.crawlLine, { pos: a, to: b, count: 5, scale: s }));
    v.burst(D.motesLine, { pos: a, to: b, count: 16, scale: s });
  });
  vfx.define('vorn.detonate', (v, at, o) => {
    const s = at.scale, i = I(o);
    const a = new THREE.Vector3(at.pos.x, 0.03, at.pos.z), b = vec(at.target); b.y = 0.03; b.z = at.pos.z;
    const n = 5;
    for (let j = 0; j < n; j++) {
      const p = a.clone().lerp(b, (j + 0.5) / n);
      v.schedule(j * 0.028, (w) => {
        w.bolt({ from: p, to: jit(new THREE.Vector3(p.x, 2.0 + R() * 0.8, p.z), 0.3, 0.2, 0.15), width: 0.1 * s, branches: 2, strikes: 2, detail: 5, life: 0.2, leader: 0.015, impact: false, intensity: 0.75 * i });
        w.pillar({ look: 'volt', pos: p, height: 2.2 * s, radius: 0.08 * s, life: 0.26, from: 'ground', intensity: 0.45 * i });
        w.burst(D.goldUp, { pos: p, dir: [0, 1, 0], count: Math.round(20 * i), scale: 0.8 * s });
        w.ring({ look: 'volt', pos: p, radius: [0.1 * s, 0.85 * s], life: 0.26, intensity: 0.5 * i });
      });
    }
    const m = a.clone().lerp(b, 0.5); m.y = 1.0;
    v.bolt({ from: new THREE.Vector3(a.x, 1.0, a.z + 0.1), to: new THREE.Vector3(b.x, 1.0, b.z + 0.1), width: 0.16 * s, branches: 3, strikes: 3, interval: [0.04, 0.07], life: 0.32, leader: 0.03, impact: false, intensity: i });
    v.burst(D.arcsLine, { pos: new THREE.Vector3(a.x, 0.6, a.z), to: new THREE.Vector3(b.x, 0.6, b.z), count: 18, scale: s });
    v.burst(D.dust, { pos: m.clone().setY(0.03), dir: [0, 1, 0], count: 8, scale: 1.3 * s });
    v.light({ pos: lightAt(m, 0, 1.8), color: V.core, intensity: 50 * i, range: 6, duration: 0.28, flicker: 0.6 });
    v.schedule(0.04, (w) => w.distort({ kind: 'shock', pos: m, radius: [0.3 * s, 2.8 * s], life: 0.35, strength: 0.04 }));
    v.burst(D.ozone, { pos: m, dir: [0, 1, 0], count: 4, scale: s, delay: 0.12 });
  });

  // ---- Gale Sweep: the blade drags along the floor -----------------------------------------------------------------
  vfx.define('vorn.sweep', (v, at, o) => {
    const s = at.scale, g = new THREE.Vector3(at.pos.x, 0.04, at.pos.z), d = at.dir, i = I(o);
    v.burst(D.goldUp, { pos: g, dir: new THREE.Vector3(d.x * 0.7, 1, d.z * 0.7 + 0.2).normalize(), count: Math.round(50 * i), scale: s });
    v.burst(D.arcsLine, { pos: g, to: g.clone().addScaledVector(d, 1.4 * s), count: 10, scale: s });
    for (let j = 0; j < 3; j++) {
      const to = g.clone().addScaledVector(d, (0.6 + 0.6 * j) * s); to.z += 0.3 + R() * 0.5; to.y = 0.03;
      v.schedule(j * 0.02, (w) => w.bolt({ from: g, to, width: 0.06 * s, branches: 1, strikes: 2, detail: 5, roughness: 0.3, life: 0.18, leader: 0.01, impact: false, intensity: 0.6 * i }));
    }
    v.burst(D.dustSmall, { pos: g, dir: [0, 1, 0], count: 6, scale: 1.4 * s });
    v.burst(D.pebbles, { pos: g, dir: [0, 1, 0], count: 6, scale: 0.8 });
    v.light({ pos: lightAt(g, 0.5, 1.5), color: V.core, intensity: 20 * i, range: 4, duration: 0.25, flicker: 0.6 });
  });

  // ---- weather ---------------------------------------------------------------------------------------------------
  vfx.define('vorn.frozenRain', (v, at) => {
    v.burst(D.frozenRain, { pos: new THREE.Vector3(at.pos.x, 3.2, at.pos.z + 1.0), dir: [0, -1, 0], scale: at.scale });
  });
  vfx.define('vorn.rain', (v, at, o) => {
    v.emitter(D.rain, { pos: new THREE.Vector3(at.pos.x, 6, at.pos.z + 0.8), scale: at.scale, duration: o.duration ?? 1, intensity: I(o) });
  });

  // ---- ultimate: the storm gathers into the spear ------------------------------------------------------------------
  vfx.define('vorn.storm', (v, at, o) => {
    const s = at.scale, f = at.facing, T = o.duration ?? 0.8, g = new THREE.Vector3(at.pos.x, 0.02, at.pos.z), i = I(o);
    const tip = o.tip ? vec(o.tip) : new THREE.Vector3(g.x, 4, g.z);
    v.decal({ kind: 'rune', pos: new THREE.Vector3(g.x, 0, g.z), radius: 3.6 * s, palette: 'volt', life: T + 0.15, reveal: 0.3, fadeOut: 0.3, spin: 0.9, intensity: 0.4 * i });
    v.emitter(D.crawlGround, { pos: new THREE.Vector3(g.x, 0.08, g.z), dir: [0, 1, 0], scale: 3 * s, duration: T + 0.3 }).rate = 40;
    v.emitter(D.motesUp, { pos: new THREE.Vector3(g.x, 0.05, g.z), dir: [0, 1, 0], scale: 2.6 * s, duration: T }).rate = 60;
    v.emitter(D.rain, { pos: new THREE.Vector3(g.x, 6, g.z + 0.8), scale: s, duration: T + 0.5 });
    v.burst(D.cloud, { pos: new THREE.Vector3(g.x, 7.2, g.z - 2.2), dir: [0, 1, 0], count: 10, scale: 1.25 * s });
    v.burst(D.cloudGlow, { count: 8, pos: new THREE.Vector3(g.x, 6.6, g.z - 1.2), dir: [0, 1, 0], scale: 1.3 * s });
    v.emitter(D.gatherWide, { pos: tip, scale: s, duration: T, intensity: i });
    v.light({ pos: new THREE.Vector3(g.x, 3.5, g.z + 2), color: V.core, intensity: 70 * i, range: 12, duration: T + 0.3, attack: 0.2, flicker: 0.8, flickerRate: 7 });
    // sky bolts hammer the floor around the victim in a stutter
    const N = 5;
    for (let k = 0; k < N; k++) {
      const a = R() * Math.PI * 2, r = (1.6 + 2.2 * Math.sqrt(R())) * s;
      const p = new THREE.Vector3(g.x + Math.cos(a) * r, 0.02, g.z + Math.sin(a) * r * 0.5);
      v.schedule(0.08 + (k / N) * (T - 0.15) + R() * 0.05, (w) => {
        w.bolt({ from: new THREE.Vector3(p.x - f * 0.8 + (R() - 0.5), 11, p.z - 2.5), to: p, width: 0.3 * s, branches: 4, strikes: 2, light: k % 2 ? 0 : 130 * i, lightRange: 8, intensity: 0.9 * i });
        w.pillar({ look: 'volt', pos: p, height: 10, radius: 0.16 * s, life: 0.32, intensity: 0.6 * i });
        w.decal({ kind: 'scorch', pos: p, radius: 0.8 * s, life: 4, palette: 'volt', magma: 0.7 });
        w.ring({ look: 'volt', pos: p, radius: [0.1 * s, 1.3 * s], life: 0.3, intensity: 0.7 * i });
        w.burst(D.goldUp, { pos: p, dir: [0, 1, 0], count: 26, scale: 0.7 * s });
      });
    }
  });

  // ---- ultimate: the colossal pillar, the crater, the aftermath ------------------------------------------------------
  vfx.define('vorn.pillar', (v, at, o) => {
    const s = at.scale, f = at.facing, g = new THREE.Vector3(at.pos.x, 0.02, at.pos.z), i = I(o);
    // the column: a wide sheath and a blinding thin core from the sky, a second fat bolt riding it
    // one thin column (seen from the high slam camera a wide sheath stacks into a white disc)
    v.pillar({ look: 'volt', pos: g, height: 16, radius: 0.16 * s, sheath: 1.6, life: 0.75, rise: 0.04, intensity: 0.4 * i });
    v.bolt({ from: new THREE.Vector3(g.x - f * 0.6, 16, g.z - 2.5), to: new THREE.Vector3(g.x, 0.05, g.z), width: 0.5 * s, branches: 7, strikes: 4, interval: [0.05, 0.1], life: 0.7, leader: 0.02, impact: false, light: 120 * i, lightRange: 12, intensity: i });
    for (let j = 0; j < 3; j++) v.schedule(0.04 + j * 0.06, (w) => w.bolt({ from: new THREE.Vector3(g.x + (j - 1) * 3, 13, g.z - 2.5), to: jit(g, 1.6 * s, 0, 0.5 * s).setY(0.05), width: 0.3 * s, branches: 3, strikes: 2, intensity: 0.8 * i }));
    // crater
    v.decal({ kind: 'crack', pos: g, radius: 3.6 * s, life: 7, density: 1.4 });
    v.decal({ kind: 'scorch', pos: g, radius: 2.6 * s, life: 7, palette: 'volt', magma: 1, cool: 2.5 });
    v.spikes({ kind: 'rock', pattern: 'ring', pos: g, radius: 1.5 * s, count: 9, height: [0.35, 0.8], width: 0.35, tilt: 38, hold: 2.6, stagger: 0.012, rise: 0.06 });
    // shock waves across the arena
    v.ring({ look: 'volt', pos: g, radius: [0.4 * s, 7 * s], life: 0.6, distort: 0.05, intensity: 0.7 * i });
    v.ring({ look: 'dust', pos: g, radius: [0.5 * s, 6.5 * s], life: 1.4 });
    v.schedule(0.03, (w) => w.distort({ kind: 'shock', pos: new THREE.Vector3(g.x, 1.0, g.z), radius: [0.5 * s, 7 * s], life: 0.6, strength: 0.06 }));
    // ground bolts lashing out to the walls of the crater and beyond
    for (let j = 0; j < 8; j++) {
      const a = (j / 8) * Math.PI * 2 + R() * 0.5, r = (2.6 + R() * 2.2) * s;
      const to = new THREE.Vector3(g.x + Math.cos(a) * r, 0.03, g.z + Math.sin(a) * r * 0.55);
      v.schedule(0.02 + j * 0.018, (w) => w.bolt({ from: g, to, width: 0.16 * s, branches: 3, strikes: 2, detail: 6, roughness: 0.3, life: 0.3, leader: 0.03, impact: false, intensity: 0.85 * i }));
    }
    v.burst(D.floorGlow, { pos: g, dir: [0, 1, 0], scale: 1.6 * s, intensity: 0.35 });
    // the debris layers are born one game frame after the strike: a hit-stop would otherwise hold hundreds of sparks
    // at their common birth point (a white disc) for its whole duration
    v.schedule(0.017, (w) => {
      w.burst(D.goldRadial, { pos: new THREE.Vector3(g.x, 0.25, g.z), count: Math.round(90 * i), scale: 1.2 * s });
      w.burst(D.goldUp, { pos: g, dir: [0, 1, 0], count: Math.round(90 * i), scale: 1.5 * s });
      w.burst(D.arcs, { pos: new THREE.Vector3(g.x, 0.4, g.z), count: 18, scale: 1.5 * s });
      w.debris({ kind: 'rock', pos: [g.x, 0.12, g.z], count: Math.round(30 * i), speed: [4, 11, 1.3], spread: 55, scale: s });
      w.burst(D.dust, { pos: g, dir: [0, 1, 0], count: 16, scale: 2.2 * s });
    });
    v.light({ pos: new THREE.Vector3(g.x, 2.6, g.z + 2.4), color: V.core, intensity: 140 * i, range: 12, duration: 0.6, flicker: 0.5 });
    // aftermath: smoke rising out of the crater, static crawling, gold dripping, ozone
    v.schedule(0.25, (w) => {
      w.burst(D.smokeColumn, { pos: g, dir: [0, 1, 0], scale: 1.1 * s });
      w.emitter(D.crawlGround, { pos: new THREE.Vector3(g.x, 0.06, g.z), dir: [0, 1, 0], scale: 2 * s, duration: 2.6 });
      w.emitter(D.motesUp, { pos: new THREE.Vector3(g.x, 0.05, g.z), dir: [0, 1, 0], scale: 1.8 * s, duration: 2.4 }).rate = 24;
      w.burst(D.ozone, { pos: new THREE.Vector3(g.x, 0.6, g.z), dir: [0, 1, 0], count: 8, scale: 1.4 * s });
    });
  });
}
