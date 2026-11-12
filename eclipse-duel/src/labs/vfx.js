// VFX lab: one scenario per primitive plus composed demos. Every scenario takes an optional position [x, y, z].
//   node tools/shot.mjs vfx --do "__ED.lab.play('sparks')" --at 0.05,0.15,0.3,0.6 --sheet-only --out shots/vfx/sparks
import * as THREE from 'three';
import { createLab } from '../core/lab.js';
import { createVfx } from '../vfx/index.js';
import { LIB, PALETTE } from '../vfx/library.js';

const P = (p, d) => (p ? new THREE.Vector3(...p) : new THREE.Vector3(...d));

// primitive scenarios use the tuned library layers
const D = {
  sparks: LIB.sparks,
  embers: LIB.embers,
  smoke: { ...LIB.smoke, count: 10, delay: 0 },
  fire: LIB.fire,
  converge: LIB.chargeStreaks,
};

const V3 = (x, y, z) => new THREE.Vector3(x, y, z);

/** Composed demo presets: each is a layered effect built only from the public vfx API. */
function definePresets(ctx, lab, vfx) {
  const post = ctx.post;
  const rng = ctx.rng;
  const VOLT = PALETTE.volt;

  // ---- sword impact: flash, directional sparks, fine spray, embers, smoke, light, shock ring, ground dust ----------
  vfx.define('demo.swordImpact', (v, at) => {
    const p = at.pos, d = at.dir, s = at.scale;
    v.burst(LIB.flashCore, { pos: p, scale: s });
    v.flare({ kind: 'glow', pos: p, size: 0.8 * s, life: 0.07, attack: 0, color: [10, 7, 4] });
    v.flare({ kind: 'star', pos: p, size: 1.7 * s, life: 0.1, attack: 0, decay: 3, color: [7, 3.4, 1.1], rotation: rng() * 0.6 });
    v.flare({ kind: 'streak', pos: p, size: 0.3 * s, aspect: 12, life: 0.13, attack: 0, decay: 2.5, color: [6, 2.4, 0.5], dir: d });
    v.burst(LIB.splash, { pos: p, dir: d, scale: s });
    v.burst(LIB.sparks, { pos: p, dir: d, scale: s });
    v.burst(LIB.sparksFine, { pos: p, dir: d, scale: s });
    v.burst(LIB.glowPuff, { pos: p, scale: s });
    v.burst(LIB.embers, { pos: p, dir: d, scale: s });
    v.burst(LIB.smoke, { pos: p, dir: d, scale: s });
    v.light({ pos: p, color: PALETTE.ember.core, intensity: 140, range: 6, duration: 0.3 });
    v.schedule(0.05, (v2) => v2.distort({ kind: 'shock', pos: p, radius: [0.25, 1.7 * s], life: 0.38, strength: 0.05 }));
    v.schedule(0.034, (v2) => v2.burst(LIB.dustRing, { pos: [p.x, 0.02, p.z], scale: 0.55 * s, count: 9 }));
    post.pulse('chroma', 0.35, { release: 0.25 });
  });

  // ---- fire burst: flash, fireball body cooling to smoke, licks, sparks, embers, lingering smoke, ground glow -------
  vfx.define('demo.fireBurst', (v, at) => {
    const p = at.pos, s = at.scale;
    const g = V3(p.x, 0.02, p.z);
    v.burst(LIB.flashCore, { pos: p, scale: 1.7 * s });
    v.flare({ kind: 'flash', pos: p, size: 5 * s, life: 0.07, attack: 0, decay: 3, color: [3, 1.2, 0.3], intensity: 0.4 });
    v.flare({ kind: 'glow', pos: p, size: 1.6 * s, life: 0.06, attack: 0, color: [10, 6, 2.5] });
    v.light({ pos: [p.x, p.y + 0.4, p.z + 0.6], color: PALETTE.ember.core, intensity: 200, range: 10, duration: 0.9, flicker: 0.35, decay: 'outCubic' });
    v.burst({ ...LIB.fireball, count: 16, size: [0.9, 1.7, 1.3] }, { pos: p, dir: [0, 1, 0], scale: s });
    v.burst(LIB.fireLicks, { pos: p, dir: [0, 1, 0], scale: s });
    v.burst({ ...LIB.sparks, count: 70, spread: 180, emit: 'radial', speed: [4, 14, 1.4], life: [0.3, 1.1, 1.4] }, { pos: p, scale: s });
    v.burst({ ...LIB.embers, count: 46, life: [1.4, 3.2, 0.8], speed: [1, 5, 1.4], gravity: 1.3 }, { pos: p, scale: s });
    v.burst(LIB.smokeLinger, { pos: [p.x, p.y + 0.3, p.z], dir: [0, 1, 0], scale: s });
    v.burst({ ...LIB.dustRing, count: 16, speed: [3, 7] }, { pos: g, scale: s });
    v.burst({ tex: 'glow', blend: 'add', align: 'flat', count: 1, life: [1.6, 1.6], speed: 0, size: 3.4 * s, groundFade: 0, rotation: 0,
      color: [[0, 4, 1.2, 0.2, 1], [0.15, 2, 0.4, 0.04, 0.8], [1, 0.2, 0.02, 0, 0]] }, { pos: [g.x, 0.03, g.z], dir: [0, 1, 0] });
    v.burst(LIB.heatHaze, { pos: p, dir: [0, 1, 0], scale: s, count: 8, delay: 0.1 });
    v.schedule(0.06, (v2) => {
      v2.distort({ kind: 'shock', pos: p, radius: [0.5, 3.4 * s], life: 0.55, strength: 0.05 });
      v2.distort({ kind: 'shock', pos: g, normal: [0, 1, 0], radius: [0.6, 4.2 * s], life: 0.7, strength: 0.04 });
    });
    post.pulse('chroma', 0.5, { release: 0.3 });
    post.pulse('exposure', 0.25, { release: 0.35 });
  });

  // ---- charge-up that converges, then releases (volt palette: violet-white core, gold sparks) ---------------------
  vfx.define('demo.chargeRelease', (v, at, o) => {
    const p = at.pos, s = at.scale, T = o.charge != null ? o.charge : 1.2;
    const g = V3(p.x, 0.03, p.z);
    const streaks = v.emitter({ ...LIB.chargeStreaks, color: [[0, 0.3, 0.1, 0.8, 0], [0.25, 1.6, 0.8, 4, 1], [1, 7, 5, 12, 1]] }, { pos: p, scale: s });
    const motes = v.emitter({ ...LIB.chargeMotes, color: [[0, 0.5, 0.2, 1.2, 0], [0.3, 2, 1, 5, 1], [1, 6, 4, 10, 0.6]] }, { pos: p, scale: s });
    const sparkles = v.emitter({ ...LIB.chargeStreaks, rate: 40, size: [0.02, 0.04], shape: { type: 'sphere', radius: 0.9, inner: 0.5 }, color: [[0, 2, 1, 0.1, 0], [0.3, 8, 5, 1, 1], [1, 10, 7, 2, 1]] }, { pos: p, scale: s });
    v.flare({ kind: 'glow', pos: p, size: [0.15 * s, 1.1 * s], life: T + 0.04, attack: T * 0.92, decay: 6, color: [5, 3.5, 9] });
    v.flare({ kind: 'star', pos: p, size: 1.3 * s, life: T + 0.04, attack: T, decay: 6, color: [3, 2, 6], rotation: 0.3 });
    v.distort({ kind: 'lens', pos: p, radius: 1.0 * s, strength: -0.05, life: T + 0.05, attack: T * 0.85, decay: 6 });
    v.burst({ tex: 'rune3', blend: 'add', align: 'flat', count: 1, life: [T + 0.5, T + 0.5], speed: 0, size: 3.0 * s, spin: [0.9, 0.9], spinBoth: false, groundFade: 0,
      sizeOverLife: [[0, 0.6], [0.25, 1], [1, 1.05]], color: [[0, 0.4, 0.2, 1.6, 0], [0.2, 0.7, 0.4, 2.6, 0.85], [0.7, 1.2, 0.75, 4, 1], [0.78, 2.4, 1.6, 6, 1], [1, 0.3, 0.1, 1, 0]] }, { pos: g, dir: [0, 1, 0] });
    v.light({ pos: [p.x, p.y, p.z + 0.4], color: VOLT.core, intensity: 90, range: 6, duration: T, curve: [[0, 0], [0.85, 1], [1, 1]], flicker: 0.25 });
    v.schedule(T, (v2) => {
      streaks.stop(); motes.stop(); sparkles.stop();
      v2.burst({ ...LIB.flashCore, color: [[0, 10, 9, 14, 1], [0.3, 4, 2.6, 9, 0.75], [1, 0.4, 0.2, 1.4, 0]] }, { pos: p, scale: 1.1 * s });
      v2.flare({ kind: 'glow', pos: p, size: 1.0 * s, life: 0.07, attack: 0, color: [9, 7, 14] });
      v2.flare({ kind: 'streak', pos: p, size: 0.28 * s, aspect: 18, life: 0.16, attack: 0, decay: 3, color: [4, 2.8, 8] });
      v2.flare({ kind: 'ring', pos: p, size: [0.4, 2.6 * s], life: 0.17, attack: 0, decay: 2, color: [0.8, 0.55, 1.8] });
      v2.burst({ ...LIB.sparks, count: 90, spread: 180, emit: 'radial', speed: [5, 18, 1.4], color: [[0, 12, 10, 6, 1], [0.15, ...VOLT.spark, 1], [0.6, 2.5, 1.2, 0.15, 1], [1, 0.4, 0.15, 0, 0]] }, { pos: p, scale: s });
      v2.burst({ tex: 'arc', blend: 'add', count: 14, life: [0.08, 0.2], shape: { type: 'sphere', radius: 0.3 }, emit: 'radial', spread: 10, speed: [8, 14], size: [0.5, 1.1], aspect: 2.2,
        align: 'velocity', stretch: 0.01, rotation: 0, flicker: { amount: 0.7, rate: 40 }, groundFade: 0, color: [[0, 8, 6, 14, 1], [1, 2, 1, 6, 0]] }, { pos: p, scale: s });
      v2.burst({ ...LIB.glitter, count: 40, color: [[0, 6, 5, 10, 0], [0.1, 6, 5, 10, 1], [1, 2, 1.5, 4, 0]] }, { pos: p, scale: 1.6 * s });
      v2.burst({ ...LIB.smoke, count: 8, size: [0.8, 1.5], speed: [1.5, 4], emit: 'radial', shape: { type: 'sphere', radius: 0.3 }, color: [[0, 0.3, 0.2, 0.6, 0], [0.08, 0.07, 0.05, 0.12, 0.6], [1, 0.04, 0.04, 0.06, 0]] }, { pos: p, scale: s });
      v2.burst({ ...LIB.dustRing, count: 14 }, { pos: g, scale: s });
      v2.light({ pos: p, color: VOLT.core, intensity: 160, range: 9, duration: 0.4 });
      v2.distort({ kind: 'shock', pos: p, radius: [0.3, 3 * s], life: 0.5, strength: 0.05 });
      v2.distort({ kind: 'shock', pos: g, normal: [0, 1, 0], radius: [0.3, 4 * s], life: 0.6, strength: 0.04 });
      post.pulse('chroma', 0.7, { release: 0.3 });
      post.pulse('radial', 0.35, { release: 0.3 });
    });
  });

  // ---- frost hit (README worked example 1): library layers recoloured with the frost palette -----------------------
  const F = vfx.palette.frost;
  const iceSparks = { ...vfx.lib.sparks, color: vfx.util.heatRamp(F.core, F.mid, F.tail), gravity: -6 };
  const shards = { tex: 'shard', blend: 'add', count: 14, life: [0.4, 0.9], spread: 40, speed: [3, 9], size: [0.08, 0.2, 2],
    spin: [4, 12], gravity: -9, collide: 'ground', erode: 'erodeLate', erodeChannel: 'cracks', color: vfx.util.heatRamp(F.core, F.mid, F.tail) };
  vfx.define('demo.frostHit', (v, at) => {
    v.burst(vfx.lib.flashCore, { pos: at.pos, color: [0.5, 0.9, 1.6] });
    v.burst(iceSparks, { pos: at.pos, dir: at.dir });
    v.burst(shards, { pos: at.pos, dir: at.dir, scale: at.scale });
    v.burst({ ...vfx.lib.glitter, color: [[0, 3, 6, 9, 0], [0.1, 3, 6, 9, 1], [1, 1, 2, 3, 0]] }, { pos: at.pos });
    v.light({ pos: at.pos, color: F.core, intensity: 120, duration: 0.3 });
    v.schedule(0.05, (v2) => v2.distort({ kind: 'shock', pos: at.pos, radius: [0.2, 1.4] }));
  });

  // ---- stage 2 set pieces: mesh effects layered with particles, lights, flares and distortion ----------------------
  const E = PALETTE.ember, FR = PALETTE.frost;
  // Kael heavy cleave: a downward flame crescent with a razor-hot inner edge, then the blade bites the floor in front
  vfx.define('demo.cleave', (v, at) => {
    const f = at.facing, p = at.pos;
    const hit = at.local(1.7, 0, 0.05);
    v.slash({ look: 'flame', pos: at.local(0.55, 1.15, 0.1), normal: [0, 0.18, 1], facing: f, arc: [125, -62], radius: 1.75, width: 0.75, sweep: 0.09, life: 0.62, distort: 0.025 });
    v.slash({ look: 'razor', pos: at.local(0.55, 1.15, 0.12), normal: [0, 0.18, 1], facing: f, arc: [118, -60], radius: 1.68, width: 0.22, sweep: 0.085, life: 0.3, intensity: 1.2 });
    v.schedule(0.075, (v2) => {
      const g = [hit.x, 0.02, hit.z];
      v2.burst(LIB.flashCore, { pos: [hit.x, 0.25, hit.z], scale: 1.4 });
      v2.flare({ kind: 'star', pos: [hit.x, 0.2, hit.z], size: 2.2, life: 0.12, decay: 3, color: [8, 3.5, 1], rotation: 0.2 });
      v2.flare({ kind: 'streak', pos: [hit.x, 0.15, hit.z], size: 0.35, aspect: 14, life: 0.16, decay: 2.5, color: [6, 2.2, 0.5] });
      v2.decal({ kind: 'crack', pos: g, radius: 2.0, magma: 1, life: 4.5, cool: 2.4 });
      v2.decal({ kind: 'scorch', pos: g, radius: 1.3, life: 4.5, magma: 0.6 });
      v2.ring({ look: 'fire', pos: g, radius: [0.3, 2.6], life: 0.6, distort: 0.03 });
      v2.ring({ look: 'dust', pos: g, radius: [0.4, 3.2], life: 1.2 });
      v2.debris({ kind: 'ember', pos: [hit.x, 0.1, hit.z], count: 16, speed: [3, 8.5, 1.3], spread: 40, size: [0.05, 0.22, 2] });
      v2.debris({ kind: 'rock', pos: [hit.x, 0.1, hit.z], count: 10, speed: [2, 6], spread: 55, size: [0.06, 0.2, 2] });
      v2.burst({ ...LIB.sparks, count: 110, spread: [70, 30] }, { pos: [hit.x, 0.15, hit.z], dir: [f * 0.4, 1, 0.15] });
      v2.burst(LIB.embers, { pos: [hit.x, 0.3, hit.z], scale: 1.3 });
      v2.burst({ ...LIB.fireLicks, count: 12 }, { pos: [hit.x, 0.2, hit.z], dir: [0, 1, 0] });
      v2.burst({ ...LIB.smoke, count: 9, size: [0.9, 1.7, 1.3] }, { pos: [hit.x, 0.3, hit.z], dir: [0, 1, 0] });
      v2.light({ pos: [hit.x, 0.6, hit.z + 0.6], color: E.core, intensity: 220, range: 9, duration: 0.55, decay: 'outCubic', flicker: 0.2 });
      v2.schedule(0.1, (v3) => v3.burst(LIB.smokeLinger, { pos: [hit.x, 0.4, hit.z], dir: [0, 1, 0], scale: 0.7 }));
      post.pulse('chroma', 0.6, { release: 0.3 });
    });
  });
  // Iska frost line: a fast cold crescent, then crystals race along the floor and shatter
  vfx.define('demo.frostLine', (v, at) => {
    const f = at.facing;
    v.slash({ look: 'ice', pos: at.local(0.4, 1.05, 0.1), normal: [0, -0.35, 1], facing: f, arc: [-150, 20], radius: 1.1, width: 0.32, sweep: 0.06, life: 0.45, distort: 0.02 });
    v.schedule(0.06, (v2) => {
      const s0 = at.local(0.9, 0, 0);
      v2.spikes({ kind: 'ice', pattern: 'line', pos: s0, dir: [f, 0, 0.05], length: 4.2, count: 8, stagger: 0.035, hold: 0.55, height: [0.8, 1.6] });
      for (let i = 0; i < 4; i++) v2.decal({ kind: 'frost', pos: at.local(1.2 + i * 1.1, 0, 0), radius: 0.9 + i * 0.15, reveal: 0.3, life: 3.5 });
      v2.ring({ look: 'frost', pos: s0, radius: [0.2, 1.8], life: 0.6 });
      v2.burst({ ...LIB.smoke, count: 10, size: [0.8, 1.5], color: [[0, 0.5, 0.65, 0.8, 0], [0.1, 0.4, 0.5, 0.6, 0.35], [1, 0.3, 0.36, 0.42, 0]] }, { pos: at.local(2.6, 0.2, 0), dir: [0, 1, 0], scale: 1.4 });
      v2.burst({ ...LIB.glitter, count: 36, color: [[0, 3, 6, 9, 0], [0.1, 3, 6, 9, 1], [1, 1, 2, 3, 0]] }, { pos: at.local(2.6, 0.7, 0), scale: 2.2 });
      v2.light({ pos: at.local(2.4, 0.9, 0.8), color: FR.core, intensity: 120, range: 8, duration: 0.9, decay: 'outQuad' });
    });
  });
  // Vorn sky strike: a rune marks the spot, the bolt falls, a column of light and a blast ring follow
  vfx.define('demo.skyStrike', (v, at) => {
    const t = at.local(1.8, 0, 0);
    const g = [t.x, 0.02, t.z];
    v.decal({ kind: 'rune', pos: g, radius: 1.4, palette: 'volt', life: 1.3, reveal: 0.3, fadeOut: 0.35, spin: 1.2 });
    v.burst({ ...LIB.chargeMotes, count: 30, color: [[0, 0.5, 0.2, 1.2, 0], [0.3, 2, 1, 5, 1], [1, 6, 4, 10, 0.6]] }, { pos: [t.x, 0.6, t.z], scale: 1.2 });
    v.schedule(0.42, (v2) => {
      v2.bolt({ from: [t.x - 1.2, 9, t.z - 2], to: [t.x, 0.05, t.z], width: 0.4, branches: 6, strikes: 3, light: 260, lightRange: 10 });
      v2.pillar({ look: 'volt', pos: [t.x, 0, t.z], height: 9, radius: 0.32, life: 0.6 });
      v2.decal({ kind: 'scorch', pos: g, radius: 1.5, life: 4, palette: 'volt', magma: 0.8 });
      v2.decal({ kind: 'crack', pos: g, radius: 1.8, life: 4 });
      v2.ring({ look: 'volt', pos: g, radius: [0.2, 3], life: 0.45, distort: 0.04 });
      v2.ring({ look: 'dust', pos: g, radius: [0.3, 2.8], life: 1.1 });
      v2.debris({ kind: 'rock', pos: [t.x, 0.1, t.z], count: 14, speed: [3, 9, 1.3], spread: 45 });
      v2.burst({ ...LIB.sparks, count: 120, spread: 80, emit: 'radial', color: [[0, 12, 10, 6, 1], [0.15, ...PALETTE.volt.spark, 1], [0.6, 2.5, 1.2, 0.15, 1], [1, 0.4, 0.15, 0, 0]] }, { pos: [t.x, 0.15, t.z], dir: [0, 1, 0] });
      v2.speedlines({ pos: [t.x, 1.0, t.z], life: 0.3, inner: 0.6, density: 130, intensity: 0.55 });
      post.pulse('chroma', 0.7, { release: 0.3 });
    });
  });

  // ---- swing trail with ember spray off the tip and a refraction twin --------------------------------------------
  vfx.define('demo.swingTrail', (v) => {
    const r = lab.rig;
    const tr = lab.play('trail', { distort: 0.025 });
    const em = v.emitter({ ...LIB.embers, count: undefined, rate: 0, perMeter: 22, delay: 0, speed: [0.2, 1.2], life: [0.4, 1.2], inherit: 0.12, spread: 180, emit: 'random' }, { pos: [0, 0, 0] }).follow(r.tip);
    const sp = v.emitter({ ...LIB.sparksFine, count: undefined, rate: 0, perMeter: 14, life: [0.1, 0.35], inherit: 0.35, spread: 180, emit: 'random' }, { pos: [0, 0, 0] }).follow(r.tip);
    v.schedule(0.5, () => { tr.stop(); em.stop(); sp.stop(); });
  });
}

/**
 * Afterimage test subject: a skinned body (3 bones, smooth weights) with a rigid head and blade parented to the top
 * bone, so ghosts of both SkinnedMesh and plain Mesh children are exercised. play(t) poses it along a dash.
 */
function makeFigure(ctx) {
  const geo = new THREE.CylinderGeometry(0.2, 0.27, 1.3, 18, 16, false);
  geo.translate(0, 0.65, 0);
  const p = geo.getAttribute('position');
  const si = [], sw = [];
  for (let i = 0; i < p.count; i++) {
    const y = p.getY(i) / 0.5;
    const b = Math.min(1, Math.floor(y)), w = Math.min(1, Math.max(0, y - b));
    si.push(b, Math.min(2, b + 1), 0, 0); sw.push(1 - w, w, 0, 0);
  }
  geo.setAttribute('skinIndex', new THREE.Uint16BufferAttribute(si, 4));
  geo.setAttribute('skinWeight', new THREE.Float32BufferAttribute(sw, 4));
  const metal = new THREE.MeshStandardMaterial({ color: 0x6d7380, metalness: 0.85, roughness: 0.35 });
  const body = new THREE.SkinnedMesh(geo, metal);
  const b0 = new THREE.Bone(), b1 = new THREE.Bone(), b2 = new THREE.Bone();
  b1.position.y = 0.5; b2.position.y = 0.5;
  b0.add(b1); b1.add(b2);
  body.add(b0);
  body.bind(new THREE.Skeleton([b0, b1, b2]));
  const head = new THREE.Mesh(new THREE.SphereGeometry(0.17, 16, 12), metal);
  head.position.y = 0.48;
  const blade = new THREE.Mesh(new THREE.BoxGeometry(0.06, 1.1, 0.02), new THREE.MeshStandardMaterial({ color: 0x9aa0aa, metalness: 0.9, roughness: 0.3 }));
  blade.position.set(0.32, 0.25, 0.1); blade.rotation.z = -0.9;
  b2.add(head, blade);
  const root = new THREE.Group();
  root.add(body);
  root.visible = false;
  ctx.scene.add(root);
  return {
    root, bones: [b0, b1, b2],
    /** pose at dash time t (0..1): run from x = -3 to x = 3, leaning into the dash, blade sweeping */
    play(t) {
      const e = t < 1 ? 1 - Math.pow(1 - t, 3) : 1;
      root.position.set(-3 + 6 * e, 0, 0);
      const lean = Math.sin(Math.min(1, t) * Math.PI) * 0.5;
      b1.rotation.z = -lean * 0.6; b2.rotation.z = -lean * 0.5; b2.rotation.y = t * 2.2;
    },
  };
}

// ---- stage 3: preset gallery ------------------------------------------------------------------------------------------
// Two grey 1.9 m capsule dummies give scale: A is the user (darker), B the target. Every entry of DEMOS places them in
// the fighter-local frame of a scene origin x with facing f, and returns the `at` / opts the preset is played with.
// `near` is a close dramatic camera (lab.view params relative to x), `wide` widens the fight camera, `times` are the
// capture times of the contact sheets.

const T_HIT = [0, 0.017, 0.05, 0.1, 0.17, 0.27, 0.45, 0.75, 1.2];
const T_SWING = [0.017, 0.05, 0.1, 0.17, 0.27, 0.4, 0.6, 0.9, 1.4];
const T_BIG = [0.05, 0.13, 0.25, 0.4, 0.6, 0.9, 1.3, 2.0, 3.0];
const T_LOOP = [0.2, 0.45, 0.8, 1.2, 1.6, 2.0, 2.4, 2.9];
const T_ULT = [0.15, 0.5, 1.0, 1.6, 2.2, 2.5, 2.8, 3.4, 4.5];
const T_SHOT = [0.05, 0.15, 0.3, 0.45, 0.6, 0.75, 0.95, 1.3, 2.0];

const L = (x, f, df, u, s = 0) => [x + df * f, u, s];
const N3 = (a) => { const v = new THREE.Vector3(...a).normalize(); return [v.x, v.y, v.z]; };
const NEAR_HIT = { dx: 0.3, ty: 1.25, dist: 3.4, yaw: 24, pitch: 5 };
const NEAR_SWING = { dx: 0.2, ty: 1.15, dist: 4.6, yaw: 28, pitch: 6 };
const NEAR_FOOT = { dx: 0, ty: 0.35, dist: 2.6, yaw: 22, pitch: 9 };
const NEAR_GROUND = { dx: 0.6, ty: 1.3, dist: 6, yaw: 30, pitch: 4 };
const NEAR_LOW = { dx: 0.6, ty: 1.6, dist: 6.5, yaw: 22, pitch: -3 };

const hitDemo = (name, opts = {}, dir = [1, 0.18, 0.32]) => ({
  A: -1.1, B: 0.35, times: T_HIT, near: NEAR_HIT, cx: -0.3,
  at: (x, f) => ({ pos: L(x, f, 0.3, 1.3, 0.18), dir: N3([dir[0] * f, dir[1], dir[2]]), facing: f }), opts: () => opts, preset: name,
});
const swingDemo = (name, opts = {}, times = T_SWING) => ({
  A: -0.55, B: 1.25, times, near: NEAR_SWING, cx: 0.3,
  at: (x, f) => ({ pos: L(x, f, -0.33, 1.38, 0.12), facing: f }), opts: () => opts, preset: name,
});
const trailDemo = (name, opts = {}) => ({
  A: -0.45, B: 1.5, times: [0.25, 0.3, 0.33, 0.36, 0.4, 0.45, 0.55, 0.7, 0.95], near: NEAR_SWING, cx: 0.3, preset: name,
  play(ctx, lab) {
    startSwing(lab);
    return ctx.vfx.play(name, { pos: lab.rig.tip }, { a: lab.rig.base, b: lab.rig.tip, duration: 0.62, ...opts });
  },
});
const auraDemo = (name, opts = {}) => ({
  A: 0, B: null, times: T_LOOP, near: { dx: 0, ty: 1.1, dist: 4, yaw: 20, pitch: 6 }, cx: 0, preset: name,
  play(ctx, lab, x, f) { return ctx.vfx.play(name, { pos: [x, 0, 0], facing: f, target: lab.dummyA }, { duration: 2.2, ...opts }); },
});
const groundDemo = (name, df, opts = {}, times = T_BIG, A = -2.2) => ({
  A, B: df, times, near: NEAR_GROUND, cx: df * 0.5,
  at: (x, f) => ({ pos: L(x, f, df, 0, 0), facing: f }), opts: () => opts, preset: name,
});
const shotDemo = (name, from, to, opts = {}) => ({
  A: -3.1, B: 2.3, times: T_SHOT, near: { dx: 0.4, ty: 1.2, dist: 6.5, yaw: 32, pitch: 5 }, cx: -0.2, preset: name,
  at: (x, f) => ({ pos: L(x, f, ...from), dir: [f, 0, 0], facing: f }), opts: (x, f) => ({ to: L(x, f, ...to), ...opts }),
});
const ultDemo = (name, opts = {}, from = 0) => ({
  A: -3.6, B: 0, times: T_ULT, near: { dx: from * 0.4, ty: 2.0, dist: 9, yaw: 26, pitch: 5 }, cx: 0, wide: 12, preset: name,
  at: (x, f) => ({ pos: L(x, f, from, 0, 0), facing: f }), opts: () => opts,
});

const DEMOS = {
  'hit.light': hitDemo('hit.light'),
  'hit.heavy': hitDemo('hit.heavy'),
  'hit.heavy:ember': hitDemo('hit.heavy', { element: 'ember' }),
  'hit.heavy:frost': hitDemo('hit.heavy', { element: 'frost' }),
  'hit.heavy:volt': hitDemo('hit.heavy', { element: 'volt' }),
  'hit.crit': hitDemo('hit.crit'),
  'hit.crit:ember': hitDemo('hit.crit', { element: 'ember' }),
  'hit.crit:frost': hitDemo('hit.crit', { element: 'frost' }),
  'hit.crit:volt': hitDemo('hit.crit', { element: 'volt' }),
  'hit.pierce': hitDemo('hit.pierce', { element: 'volt' }, [1, 0.02, 0.1]),
  'guard.block': hitDemo('guard.block'),
  'guard.block:perfect': hitDemo('guard.block', { perfect: true }),
  'guard.break': hitDemo('guard.break'),
  'ko.burst': { ...hitDemo('ko.burst', { element: 'ember' }), times: T_BIG },
  'dust.step': { A: 0, B: null, times: [0.017, 0.07, 0.15, 0.3, 0.5, 0.8], near: NEAR_FOOT, cx: 0, preset: 'dust.step', at: (x, f) => ({ pos: L(x, f, 0.12, 0, 0.12), facing: f }) },
  'dust.dash': { A: 0, B: null, times: [0.017, 0.07, 0.15, 0.3, 0.5, 0.8, 1.2], near: NEAR_FOOT, cx: -0.5, preset: 'dust.dash', at: (x, f) => ({ pos: L(x, f, 0, 0, 0.1), facing: f }) },
  'dust.land': { A: 0, B: null, times: [0.017, 0.07, 0.15, 0.3, 0.5, 0.8, 1.2], near: NEAR_FOOT, cx: 0, preset: 'dust.land', at: (x, f) => ({ pos: L(x, f, 0, 0, 0), facing: f }) },
  'dust.land:heavy': { A: 0, B: null, times: [0.017, 0.07, 0.15, 0.3, 0.5, 0.8, 1.2], near: NEAR_FOOT, cx: 0, preset: 'dust.land', at: (x, f) => ({ pos: L(x, f, 0, 0, 0), facing: f }), opts: () => ({ heavy: true }) },
  'dust.slide': { A: 0, B: null, times: [0.017, 0.1, 0.2, 0.35, 0.5, 0.8, 1.2], near: NEAR_FOOT, cx: -0.6, preset: 'dust.slide', at: (x, f) => ({ pos: L(x, f, 0.3, 0, 0.1), facing: f }) },
  'whoosh.light': swingDemo('whoosh.light'),
  'whoosh.heavy': swingDemo('whoosh.heavy'),
  'charge.gather': { A: -0.4, B: null, times: [0.15, 0.4, 0.7, 0.95, 1.12, 1.2, 1.35, 1.6, 2.0], near: { dx: 0, ty: 1.2, dist: 3.4, yaw: 22, pitch: 5 }, cx: 0, preset: 'charge.gather',
    at: (x, f) => ({ pos: L(x, f, -0.05, 1.25, 0.3), facing: f }), opts: () => ({ duration: 1.1, release: true, rune: true, element: 'volt' }) },
  'charge.release': { ...hitDemo('charge.release', { element: 'ember' }), times: T_HIT },
  'ult.flash': { A: 0, B: null, times: [0.017, 0.05, 0.1, 0.2, 0.35, 0.55, 0.8, 1.2, 1.8], near: { dx: 0, ty: 1.4, dist: 4.5, yaw: 18, pitch: 4 }, cx: 0, preset: 'ult.flash',
    at: (x, f) => ({ pos: L(x, f, 0.05, 1.35, 0.15), facing: f }), opts: () => ({ element: 'eclipse' }) },
  // ember
  'ember.hit': hitDemo('ember.hit', { k: 1 }),
  'ember.slash': swingDemo('ember.slash'),
  'ember.slash.heavy': { ...swingDemo('ember.slash.heavy'), times: [0.017, 0.05, 0.1, 0.17, 0.27, 0.4, 0.6, 1.0, 1.6] },
  'ember.trail': trailDemo('ember.trail'),
  'ember.aura': auraDemo('ember.aura'),
  'ember.eruption': groundDemo('ember.eruption', 0.6),
  'ember.wave': shotDemo('ember.wave', [-1.9, 0, 0.05], [2.0, 0, 0.05]),
  'ember.explosion': { A: 0, B: 1.4, times: T_BIG, near: NEAR_GROUND, cx: 0.3, preset: 'ember.explosion', at: (x, f) => ({ pos: L(x, f, 0, 1.05, 0.1), facing: f }) },
  'ember.meteor': { ...groundDemo('ember.meteor', 0.6, {}, [0.1, 0.3, 0.45, 0.52, 0.6, 0.8, 1.1, 1.7, 2.8]), near: NEAR_LOW },
  'ember.inferno': ultDemo('ember.inferno'),
  // frost
  'frost.hit': hitDemo('frost.hit', { k: 1 }),
  'frost.slash': swingDemo('frost.slash'),
  'frost.slash.heavy': swingDemo('frost.slash.heavy'),
  'frost.trail': trailDemo('frost.trail'),
  'frost.aura': auraDemo('frost.aura'),
  'frost.spikes': { ...groundDemo('frost.spikes', -2.0, {}, T_BIG, -2.7), B: 3.2, cx: 1.2, near: { dx: 0.4, ty: 1.3, dist: 7.5, yaw: 30, pitch: 6 } },
  'frost.shard': shotDemo('frost.shard', [-2.5, 1.38, 0.1], [2.15, 1.3, 0.12]),
  'frost.nova': groundDemo('frost.nova', 0.6),
  'frost.shatter': { A: -2, B: 0.4, times: T_HIT.concat([1.8]).slice(1), near: NEAR_HIT, cx: 0.2, preset: 'frost.shatter', at: (x, f) => ({ pos: L(x, f, 0.4, 1.0, 0.1), facing: f }) },
  'frost.blizzard': ultDemo('frost.blizzard', {}, -3.2),
  'frost.starfall': { ...groundDemo('frost.starfall', 0.6, { count: 5 }, [0.04, 0.08, 0.12, 0.2, 0.3, 0.45, 0.7, 1.1, 1.8]), near: NEAR_LOW },
  // volt
  'volt.hit': hitDemo('volt.hit', { k: 1 }),
  'volt.thrust': { A: -1.25, B: 1.25, times: T_HIT, near: NEAR_SWING, cx: 0.2, preset: 'volt.thrust', at: (x, f) => ({ pos: L(x, f, -0.85, 1.35, 0.12), dir: [f, 0, 0], facing: f }) },
  'volt.slash': swingDemo('volt.slash'),
  'volt.trail': trailDemo('volt.trail'),
  'volt.aura': auraDemo('volt.aura'),
  'volt.strike': { ...groundDemo('volt.strike', 0.8), near: NEAR_LOW },
  'volt.strike:huge': { ...groundDemo('volt.strike', 0.8, { huge: true }), near: NEAR_LOW },
  'volt.chain': { A: -2, B: 1.5, times: T_HIT, near: { dx: 0, ty: 1.2, dist: 5.5, yaw: 25, pitch: 5 }, cx: -0.2, preset: 'volt.chain',
    at: (x, f) => ({ pos: L(x, f, -1.6, 1.45, 0.1), facing: f, target: L(x, f, 1.5, 1.2, 0.12) }) },
  'volt.dash': { A: null, B: null, times: [0.05, 0.12, 0.2, 0.3, 0.42, 0.55, 0.75, 1.0, 1.4], near: { dx: 0, ty: 1.0, dist: 7, yaw: 25, pitch: 5 }, cx: 0, preset: 'volt.dash',
    play(ctx, lab, x, f) {
      const fig = lab.figure;
      fig.root.visible = true;
      let t = 0;
      fig.play(0);
      const off = ctx.onUpdate((dt) => { t += dt / 0.55; fig.play(t); if (t > 1.6) off(); }, ctx.ORDER.CHAR);
      return ctx.vfx.play('volt.dash', { pos: [-3, 0, 0], facing: 1, target: fig.root }, { to: [3, 0, 0] });
    } },
  'volt.burst': { A: -2, B: 0.4, times: T_HIT, near: NEAR_HIT, cx: 0, preset: 'volt.burst', at: (x, f) => ({ pos: L(x, f, 0.4, 1.2, 0.12), facing: f }) },
  'volt.storm': ultDemo('volt.storm'),
  'volt.javelin': shotDemo('volt.javelin', [-2.4, 1.55, 0.1], [2.15, 1.3, 0.12]),
};

/** Start the lab rig's swing: anticipation (slow wind-up), smear (fast arc), follow-through, settle. */
function startSwing(lab) {
  const r = lab.rig;
  r.pivot.visible = true;
  const inQ = (u) => u * u, outQ = (u) => 1 - (1 - u) * (1 - u), outE = (u) => 1 - Math.pow(2, -8 * u);
  r.keys = [[0, 150, null, 0], [0.22, 165, outQ, -0.2], [0.36, -40, inQ, 0.25], [0.5, -95, outE, 0.35], [0.9, -100, outQ, 0.3]];
  r.t = 0;
  r.pivot.rotation.set(0, 0, 150 * Math.PI / 180);
  r.pivot.updateMatrixWorld(true);
  return r;
}

/** grey capsule dummy, 1.9 m tall (feet at y = 0) */
function makeDummy(ctx, color) {
  const m = new THREE.Mesh(new THREE.CapsuleGeometry(0.2, 1.5, 6, 16), new THREE.MeshStandardMaterial({ color, roughness: 0.55, metalness: 0.15 }));
  m.position.y = 0.95;
  m.castShadow = true;
  const g = new THREE.Group();
  g.add(m);
  g.visible = false;
  ctx.scene.add(g);
  return g;
}

/** Place the dummies and the camera for a demo; returns the demo entry. */
function stageDemo(lab, name, x = 0, f = 1) {
  const d = DEMOS[name];
  if (!d) throw new Error('no preset demo: ' + name);
  for (const [k, obj] of [['A', lab.dummyA], ['B', lab.dummyB]]) {
    obj.visible = d[k] != null;
    if (obj.visible) { obj.position.set(x + d[k] * f, 0, 0); obj.updateMatrixWorld(true); }
  }
  lab.figure.root.visible = false;
  lab.rig.pivot.visible = false;
  return d;
}

createLab({
  view: { target: [0, 1.0, 0], dist: 7, yaw: 0, pitch: 8 },
  setup(ctx, lab) {
    const vfx = createVfx(ctx);
    lab.vfx = vfx;
    lab.D = D;
    // dim backdrop wall with a stone-block pattern: something for refraction to bend and smoke to read against
    const cv = document.createElement('canvas');
    cv.width = cv.height = 256;
    const g = cv.getContext('2d');
    g.fillStyle = '#1a1c22'; g.fillRect(0, 0, 256, 256);
    g.strokeStyle = '#2c303a'; g.lineWidth = 3;
    for (let y = 0; y < 256; y += 32) { g.beginPath(); g.moveTo(0, y); g.lineTo(256, y); g.stroke(); for (let x = (y / 32) % 2 ? 0 : 32; x < 256; x += 64) { g.beginPath(); g.moveTo(x, y); g.lineTo(x, y + 32); g.stroke(); } }
    const tex = new THREE.CanvasTexture(cv);
    tex.colorSpace = THREE.SRGBColorSpace; tex.wrapS = tex.wrapT = THREE.RepeatWrapping; tex.repeat.set(6, 2);
    const wall = new THREE.Mesh(new THREE.PlaneGeometry(30, 10), new THREE.MeshStandardMaterial({ map: tex, roughness: 0.9 }));
    wall.position.set(0, 5, -5);
    ctx.scene.add(wall);
    // swinging weapon rig: pivot at shoulder height, blade from 0.25 m to 1.45 m along the arm
    const pivot = new THREE.Group();
    pivot.position.set(-0.2, 1.3, 0.3);
    const blade = new THREE.Mesh(new THREE.BoxGeometry(1.2, 0.07, 0.02), new THREE.MeshStandardMaterial({ color: 0x9aa0aa, metalness: 0.9, roughness: 0.3 }));
    blade.position.x = 0.85;
    const base = new THREE.Object3D(); base.position.x = 0.25;
    const tip = new THREE.Object3D(); tip.position.x = 1.45;
    pivot.add(blade, base, tip);
    pivot.visible = false;
    ctx.scene.add(pivot);
    lab.rig = { pivot, base, tip, t: 1e9, keys: null };
    ctx.onUpdate((dt) => {
      const r = lab.rig;
      if (!r.keys) return;
      r.t += dt;
      const k = r.keys;
      let i = 1;
      while (i < k.length - 1 && k[i][0] < r.t) i++;
      const a = k[i - 1], b = k[i];
      const u = Math.min(1, Math.max(0, (r.t - a[0]) / (b[0] - a[0])));
      const e = b[2] ? b[2](u) : u;
      pivot.rotation.z = (a[1] + (b[1] - a[1]) * e) * Math.PI / 180;
      pivot.rotation.y = (a[3] || 0) + ((b[3] || 0) - (a[3] || 0)) * e;
    }, ctx.ORDER.CHAR);
    lab.figure = makeFigure(ctx);
    lab.dummyA = makeDummy(ctx, 0x5d6370);
    lab.dummyB = makeDummy(ctx, 0x8a8478);
    lab.demos = DEMOS;
    definePresets(ctx, lab, vfx);
    vfx.prewarm();
  },
  scenarios: {
    atlas(ctx, lab, which = 'atlas', mode = 0) {
      const t = ctx.vfx.textures[which];
      const m = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), new THREE.ShaderMaterial({
        depthTest: false, depthWrite: false, transparent: true, uniforms: { t: { value: t }, mode: { value: mode }, asp: { value: ctx.viewport.aspect } },
        vertexShader: 'varying vec2 vUv; uniform float asp; void main(){ vUv = uv; gl_Position = vec4(position.x / asp, position.y, 0.0, 1.0); }',
        fragmentShader: `uniform sampler2D t; uniform int mode; varying vec2 vUv; void main(){ vec4 s = texture2D(t, vUv);
          vec3 bg = vec3(mod(floor(vUv.x*64.0)+floor(vUv.y*64.0), 2.0) > 0.5 ? 0.02 : 0.035);
          vec3 col;
          if (mode == 0) { vec3 hot = vec3(0.95 + 0.05*s.g, 0.4 + 0.6*s.g, 0.12 + 0.88*s.g*s.g); col = mix(bg, hot * s.r, s.a); }
          else if (mode == 1) col = vec3(s.a);
          else if (mode == 2) col = s.rgb * s.a;
          else col = s.rgb;
          gl_FragColor = vec4(col * 0.75, 1.0); }`,
      }));
      m.frustumCulled = false; m.renderOrder = 999;
      ctx.scene.add(m);
    },
    gallery(ctx, lab, which = 'all') {
      // every sprite as a static particle: additive ones lit warm, alpha ones as grey matter against the wall
      const sp = ctx.vfx.textures.sprites;
      const alphaSet = new Set(['smoke1', 'smoke2', 'smoke3', 'smoke4', 'dust', 'pebble1', 'pebble2', 'pebble3', 'ash1', 'ash2', 'petal', 'shard1', 'shard2', 'shard3']);
      const names = Object.keys(sp).filter((n) => sp[n].frames === 1 && (which === 'all' || (which === 'alpha') === alphaSet.has(n)));
      const cols = which === 'all' ? 10 : 7;
      names.forEach((n, i) => {
        const a = alphaSet.has(n);
        const big = n.startsWith('smoke') || n.startsWith('flame') || n === 'burst';
        const def = { tex: n, blend: a ? 'alpha' : 'add', count: 1, life: 1e4, speed: 0, size: (big ? 1.1 : 0.62) * (which === 'all' ? 1 : 1.5), rotation: 0, groundFade: 0,
          color: a ? [0.32, 0.3, 0.28] : [3, 1.4, 0.45], heat: a ? 0 : 0.0 };
        if (!a) def.color = [[0, 3, 1.3, 0.4, 1], [1, 3, 1.3, 0.4, 1]];
        const x = ((i % cols) - (cols - 1) / 2) * (which === 'all' ? 0.85 : 1.2), y = 2.5 - Math.floor(i / cols) * (which === 'all' ? 0.8 : 1.15);
        ctx.vfx.burst(def, { pos: [x, y, 0], color: a ? null : [1, 1, 1] });
      });
    },
    sparks(ctx, lab, p) { return ctx.vfx.burst(D.sparks, { pos: P(p, [0, 1.2, 0]), dir: [0.6, 0.5, 0.3] }); },
    embers(ctx, lab, p) { return ctx.vfx.burst(D.embers, { pos: P(p, [0, 0.8, 0]) }); },
    smoke(ctx, lab, p) { return ctx.vfx.burst(D.smoke, { pos: P(p, [0, 0.6, 0]) }); },
    fire(ctx, lab, p) {
      // standing fire: flames + rising smoke + embers + a flickering light, all following one point
      const at = { pos: P(p, [0, 0.02, 0]) };
      const v = ctx.vfx;
      return [
        v.emitter(D.fire, at),
        v.emitter({ ...LIB.smokeLinger, rate: 5, delay: 0, size: [0.7, 1.4], life: [1.6, 2.6], speed: [0.6, 1.2], shape: { type: 'disc', radius: 0.25 }, emit: 'axis', spread: 10 }, { pos: at.pos.clone().setY(0.7) }),
        v.emitter({ ...LIB.embers, rate: 12, delay: 0, speed: [0.5, 2] }, { pos: at.pos.clone().setY(0.5) }),
        v.light({ pos: at.pos.clone().setY(0.6), color: PALETTE.ember.core, intensity: 25, range: 5, duration: Infinity, flicker: 0.4, flickerRate: 9 }),
      ];
    },
    converge(ctx, lab, p) { return ctx.vfx.emitter(D.converge, { pos: P(p, [0, 1.2, 0]) }); },
    trail(ctx, lab, opts = {}) {
      const r = startSwing(lab);
      return ctx.vfx.trail({ a: r.base, b: r.tip, ...opts });
    },
    ribbon(ctx, lab) {
      const o = new THREE.Object3D();
      ctx.scene.add(o);
      let t = 0;
      const off = ctx.onUpdate((dt) => { t += dt; o.position.set(-4 + t * 7, 1.3 + Math.sin(t * 6) * 0.35, Math.cos(t * 4) * 0.4); if (t > 1.3) off(); }, ctx.ORDER.CHAR);
      o.position.set(-4, 1.3, 0.4);
      ctx.vfx.ribbon({ follow: o, width: 0.22, life: 0.5 });
      ctx.vfx.emitter({ ...D.embers, rate: 60, delay: 0, speed: [0.1, 0.6], life: [0.3, 0.9] }, { pos: o.position }).follow(o);
      return o;
    },
    flare(ctx, lab) {
      const kinds = ['glow', 'star', 'streak', 'ring', 'flash'];
      kinds.forEach((k, i) => ctx.vfx.flare({ kind: k, pos: [-3 + i * 1.5, 1.3, 0], size: k === 'streak' ? 0.5 : k === 'ring' ? [0.3, 1.2] : k === 'flash' ? 2.5 : 0.9, life: 1.2, color: [5, 3, 1.5], intensity: k === 'flash' ? 0.3 : 1 }));
    },
    distort(ctx, lab) {
      ctx.vfx.distort({ kind: 'shock', pos: [-2.5, 1.3, 0], radius: [0.2, 2.2], life: 0.8 });
      ctx.vfx.distort({ kind: 'shock', pos: [0, 0.02, 0], normal: [0, 1, 0], radius: [0.3, 3], life: 0.8 });
      ctx.vfx.distort({ kind: 'heat', pos: [2.2, 1.0, 0], radius: 1.0, life: 2 });
      ctx.vfx.distort({ kind: 'lens', pos: [0, 2.6, -1], radius: 1.0, strength: 0.06, life: 2 });
    },
    light(ctx, lab, p) {
      ctx.vfx.light({ pos: P(p, [0, 0.6, 0.5]), color: [8, 3, 0.6], intensity: 120, range: 7, duration: 1.2 });
      ctx.vfx.flare({ kind: 'glow', pos: P(p, [0, 0.6, 0.5]), size: 0.8, life: 1.2, color: [8, 3, 0.6] });
    },
    schedule(ctx, lab) {
      for (let i = 0; i < 5; i++) ctx.vfx.schedule(i * 0.15, (v) => v.burst(D.sparks, { pos: [-2 + i, 1.2, 0], dir: [0, 1, 0], count: 30 }));
    },
    swordImpact(ctx, lab, p, d) { return ctx.vfx.play('demo.swordImpact', { pos: P(p, [0, 1.35, 0]), dir: d || [0.85, -0.35, 0.4] }); },
    fireBurst(ctx, lab, p) { return ctx.vfx.play('demo.fireBurst', { pos: P(p, [0, 0.9, 0]) }); },
    chargeRelease(ctx, lab, p, charge) { return ctx.vfx.play('demo.chargeRelease', { pos: P(p, [0, 1.4, 0]) }, { charge }); },
    swingTrail(ctx) { return ctx.vfx.play('demo.swingTrail'); },
    frostHit(ctx, lab, p, d) { return ctx.vfx.play('demo.frostHit', { pos: P(p, [0, 1.35, 0]), dir: d || [-1, 0.2, 0.3] }); },
    // ---- mesh effects (stage 2) ---------------------------------------------------------------------------------
    slash(ctx, lab, look = 'razor', o = {}) {
      return ctx.vfx.slash({ look, pos: [0, 1.25, 0], normal: [0, 0.28, 1], forward: [1, 0, 0], arc: [150, -25], radius: 1.5, distort: 0.02, ...o });
    },
    slashes(ctx, lab, o = {}) {
      const looks = ['razor', 'flame', 'ice', 'electric', 'eclipse'];
      looks.forEach((look, i) => ctx.vfx.slash({ look, pos: [-4 + i * 2, 1.2, 0], normal: [0, 0.25, 1], arc: [150, -25], radius: 0.85, width: 0.32, ...o }));
    },
    slashWave(ctx, lab, look = 'flame') {
      // a crescent projectile: sweeps, then flies forward and grows
      return ctx.vfx.slash({ look, pos: [-3, 1.0, 0], normal: [0, 0, 1], forward: [1, 0, 0], arc: [-70, 70], radius: 0.9, width: 0.45, speed: 9, expand: 0.6, drag: 1.2, life: 0.9, sweep: 0.05, distort: 0.03 });
    },
    ring(ctx, lab, look = 'shock', o = {}) {
      return ctx.vfx.ring({ look, pos: [0, 0, 0], distort: look === 'dust' ? 0 : 0.035, ...o });
    },
    rings(ctx, lab, o = {}) {
      ['shock', 'dust', 'fire', 'frost', 'volt'].forEach((look, i) => ctx.vfx.ring({ look, pos: [-5 + i * 2.5, 0, 0], scale: 0.42, ...o }));
    },
    ringsAir(ctx) {
      // camera-facing and tilted rings in the air
      ctx.vfx.ring({ look: 'shock', orient: 'camera', pos: [-2.2, 1.4, 0], radius: [0.1, 1.6], width: [0.25, 0.5] });
      ctx.vfx.ring({ look: 'volt', normal: [1, 0.3, 0.2], pos: [0, 1.4, 0], radius: [0.1, 1.4], width: [0.2, 0.4] });
      ctx.vfx.ring({ look: 'frost', normal: [0.2, 0.4, 1], pos: [2.2, 1.4, 0], radius: [0.1, 1.4], width: [0.3, 0.6] });
    },
    pillar(ctx, lab, look = 'fire', o = {}) { return ctx.vfx.pillar({ look, pos: [0, 0, 0], ...o }); },
    pillars(ctx, lab, o = {}) {
      ['fire', 'frost', 'volt', 'eclipse'].forEach((look, i) => ctx.vfx.pillar({ look, pos: [-3.6 + i * 2.4, 0, 0], scale: 0.6, ...o }));
    },
    beams(ctx, lab, o = {}) {
      // every look, each released after 0.9 s (stop())
      const hs = ['energy', 'fire', 'frost', 'volt', 'eclipse'].map((look, i) => ctx.vfx.beam({ look, from: [-3.6, 0.5 + i * 0.55, 0], to: [3.6, 0.4 + i * 0.6, -0.5], ...o }));
      ctx.vfx.schedule(0.9, () => hs.forEach((h) => h.stop()));
      return hs;
    },
    beam(ctx, lab, look = 'energy', o = {}) {
      // a beam whose impact end sweeps (setEnds every frame), released after 1.2 s
      const h = ctx.vfx.beam({ look, from: [-3, 1.3, 0], to: [3, 1.0, 0], ...o });
      let t = 0;
      const off = ctx.onUpdate((dt) => { t += dt; h.setEnds(null, [2.5 + Math.sin(t * 2) * 0.8, 0.8 + Math.sin(t * 3.1) * 0.6, Math.cos(t * 2) * 0.6]); if (t > 1.6) off(); }, ctx.ORDER.GAME);
      ctx.vfx.schedule(1.2, () => h.stop());
      return h;
    },
    bolt(ctx, lab, o = {}) {
      // sky strike onto the floor, lighting the stage
      return ctx.vfx.bolt({ from: [-0.8, 6.5, -1.5], to: [0.3, 0, 0], width: 0.34, light: 160, ...o });
    },
    bolts(ctx, lab) {
      // palettes side by side, horizontal arcs between two points, and a long crackling arc
      ctx.vfx.bolt({ from: [-4.5, 5.5, -1], to: [-3, 0, 0], palette: 'volt' });
      ctx.vfx.bolt({ from: [-1.5, 5.5, -1], to: [-0.6, 0, 0], palette: 'frost', branches: 7 });
      ctx.vfx.bolt({ from: [1.2, 5.5, -1], to: [1.6, 0, 0], palette: 'ember', roughness: 0.32 });
      ctx.vfx.bolt({ from: [2.6, 1.6, 0], to: [4.6, 0.9, 0], width: 0.18, branches: 2, strikes: 14, interval: [0.03, 0.06], life: 0.8, leader: 0, detail: 6 });
    },
    decal(ctx, lab, kind = 'crack', o = {}) { return ctx.vfx.decal({ kind, pos: [0, 0, 0], ...o }); },
    decals(ctx, lab) {
      // every kind (cracks twice: dry and with cooling magma)
      ctx.vfx.decal({ kind: 'crack', pos: [-4.4, 0, 0], radius: 1.5, life: 5 });
      ctx.vfx.decal({ kind: 'crack', pos: [-1.6, 0, 0], radius: 1.5, magma: 1, life: 5 });
      ctx.vfx.decal({ kind: 'scorch', pos: [1.1, 0, 0], radius: 1.3, life: 5 });
      ctx.vfx.decal({ kind: 'frost', pos: [3.9, 0, 0], radius: 1.5, life: 5 });
      ctx.vfx.decal({ kind: 'rune', pos: [-2.9, 0, -3.2], radius: 1.5, life: 5, palette: 'volt' });
      ctx.vfx.decal({ kind: 'rune', pos: [0.6, 0, -3.2], radius: 1.5, life: 5 });
      ctx.vfx.decal({ kind: 'glow', pos: [3.6, 0, -3.2], radius: 1.4, life: 5 });
    },
    debris(ctx, lab, kind = 'rock', o = {}) { return ctx.vfx.debris({ kind, pos: [0, 0.1, 0], count: 22, ...o }); },
    debrisAll(ctx) {
      ['rock', 'ember', 'ice', 'crystal'].forEach((kind, i) => ctx.vfx.debris({ kind, pos: [-3.6 + i * 2.4, 0.1, 0], count: 18, speed: [2.5, 6.5, 1.3] }));
      ctx.vfx.light({ pos: [-1.2, 1.2, 1.2], color: [8, 3, 0.6], intensity: 30, range: 6, duration: 2 });
    },
    spikes(ctx, lab, kind = 'ice', pattern = 'line', o = {}) {
      return ctx.vfx.spikes({ kind, pattern, pos: pattern === 'line' ? [-2.5, 0, 0] : [0, 0, 0], dir: [1, 0, 0.15], ...o });
    },
    spikesAll(ctx) {
      // a line of ice, a cluster of crystal, a ring of rock, a magma cluster; a light so the facets read
      ctx.vfx.spikes({ kind: 'ice', pattern: 'line', pos: [-4.6, 0, 0.6], dir: [1, 0, 0.1], length: 3.2, count: 6 });
      ctx.vfx.spikes({ kind: 'crystal', pattern: 'cluster', pos: [0.6, 0, 0.3], count: 7 });
      ctx.vfx.spikes({ kind: 'rock', pattern: 'ring', pos: [3.6, 0, -0.4], radius: 1.0, count: 9, height: [0.5, 1.0] });
      ctx.vfx.spikes({ kind: 'magma', pattern: 'cluster', pos: [-1.6, 0, -2.2], count: 6, height: [0.6, 1.3] });
      ctx.vfx.light({ pos: [-2, 2.2, 2.2], color: [6, 5, 4], intensity: 40, range: 10, duration: 3 });
    },
    speedlines(ctx, lab, mode = 'focus', o = {}) {
      return ctx.vfx.speedlines({ mode, life: 0.8, ...o });
    },
    speedlinesAll(ctx, lab, which = 0) {
      // 0 focus on a world point (tracks it), 1 directional, 2 ink focus
      if (which === 0) return ctx.vfx.speedlines({ pos: [1.2, 1.4, 0], life: 0.8, inner: 0.45 });
      if (which === 1) return ctx.vfx.speedlines({ mode: 'directional', dir: [1, -0.15], life: 0.8 });
      return ctx.vfx.speedlines({ style: 'ink', life: 0.8, density: 90, inner: 0.6 });
    },
    afterimage(ctx, lab, o = {}) {
      // the skinned figure dashes; ghosts every 50 ms (game time: hit-stop freezes them too)
      const fig = lab.figure;
      fig.root.visible = true;
      let t = 0;
      fig.play(0);
      const off = ctx.onUpdate((dt) => { t += dt / 0.55; fig.play(t); if (t > 1.6) off(); }, ctx.ORDER.CHAR);
      return ctx.vfx.afterimage(fig.root, { count: 9, interval: 0.05, life: 0.42, drift: [0, 0.15, 0], ...o });
    },
    cleave(ctx, lab, f = 1) { return ctx.vfx.play('demo.cleave', { pos: [-1.8 * f, 0, 0], facing: f }); },
    frostLine(ctx, lab, f = 1) { return ctx.vfx.play('demo.frostLine', { pos: [-2.8 * f, 0, 0], facing: f }); },
    skyStrike(ctx, lab, f = 1) { return ctx.vfx.play('demo.skyStrike', { pos: [-1.8 * f, 0, 0], facing: f }); },
    slowmo(ctx, lab, s = 0.2, d = 2) { ctx.time.slowmo(s, d, { easeIn: 0, easeOut: 0 }); },
    hitstop(ctx, lab, d = 0.3) { ctx.time.hitstop(d); },
    clear(ctx) { ctx.vfx.clear(); },
    /** live VFX counts: particles per layer (alive now), draw calls of the last render, live pooled effects */
    stats(ctx) {
      const v = ctx.vfx, out = {};
      for (const k in v.particles.layers) {
        const r = v.particles.layers[k].ring, f = r.f32;
        let n = 0;
        for (let i = 0; i < r.capacity; i++) {
          const o = i * r.stride, life = f[o + 7];
          if (life === 0) continue;
          const now = life < 0 ? v.clock.real : v.clock.game;
          if (now >= f[o + 3] && now < f[o + 3] + Math.abs(life)) n++;
        }
        out[k] = n;
      }
      const i = ctx.renderer.info.render;
      out.calls = i.calls; out.tris = i.triangles; out.programs = (ctx.renderer.info.programs || []).length;
      return out;
    },
    // ---- stage 3: presets -------------------------------------------------------------------------------------------
    /** play any preset (or a DEMOS variant such as 'hit.crit:frost') at scene origin x with facing f; extra opts merge in */
    preset(ctx, lab, name, x = 0, f = 1, extra = {}) {
      const d = DEMOS[name] ? stageDemo(lab, name, x, f) : null;
      if (d && d.play) return d.play(ctx, lab, x, f);
      if (!d) return ctx.vfx.play(name, { pos: [x, 1.2, 0.1], facing: f }, extra);
      return ctx.vfx.play(d.preset, d.at(x, f, lab), { ...(d.opts ? d.opts(x, f, lab) : {}), ...extra });
    },
    /** camera for a demo: which = 'fight' (yaw 0, pitch 6, 8 m, wider for ultimates) | 'near' (close dramatic angle) */
    presetView(ctx, lab, name, which = 'fight', x = 0, f = 1) {
      const d = DEMOS[name];
      if (which === 'near') { const n = d.near; return lab.view({ target: [x + n.dx * f, n.ty, 0], dist: n.dist, yaw: n.yaw * f, pitch: n.pitch, fov: 40 }); }
      return lab.view({ target: [x + (d.cx || 0) * f, 1.1, 0], dist: d.wide || 8, yaw: 0, pitch: 6, fov: 40 });
    },
    /** one preset per family side by side (combat, ember, frost, volt), fight camera pulled back */
    families(ctx, lab, names = ['hit.crit', 'ember.eruption', 'frost.nova', 'volt.strike']) {
      lab.view({ target: [0, 1.3, 0], dist: 15, yaw: 0, pitch: 6, fov: 40 });
      const xs = [-6.3, -2.4, 1.6, 5.6];
      const hs = names.map((n, i) => lab.play('preset', n, xs[i], 1));
      lab.dummyA.visible = false;
      lab.dummyB.visible = false;
      return hs;
    },
    /** three ultimate-scale presets overlapping (performance check) */
    overlap(ctx, lab, names = ['ember.inferno', 'frost.blizzard', 'volt.storm']) {
      lab.view({ target: [0, 1.6, 0], dist: 13, yaw: 0, pitch: 6, fov: 40 });
      return names.map((n, i) => ctx.vfx.play(n, { pos: [(i - 1) * 2.5, 0, 0], facing: 1 }));
    },
  },
});
