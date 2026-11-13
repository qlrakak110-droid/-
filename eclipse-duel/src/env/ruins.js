// The ruined summit of the Heaven-Martial Sect, assembled: this file owns the build context shared by the
// sub-builders and returns merged geometries (one draw call per material) plus everything the moving layers and the
// game need (fire sources, cloth, smoke, colliders, landmarks).
//
//   terrace.js   retaining wall + balustrade, stairs, paving, cliff, rim, rubble, the old impact      (stone)
//   timber.js    gallery (회랑), the collapsed hall (천무전), the mountain gate (산문) + name board      (timber, tiles)
//   dressing.js  stone lanterns, incense braziers, weapon racks, stele, drum, banner poles, talisman ropes
//   flora.js     pines on rocks, bamboo, dry grass                                                     (foliage mesh)
//
// Build context C (passed to every sub-builder):
//   C.S / C.M / C.P      Builders (all with the relief channel): stone, metal, painted timber
//   C.rng, C.tier        deterministic rng, tierSettings()
//   C.glow(p)            baked warm light at a world point (per-vertex `glow` attribute)
//   C.st(tint, extra)    Builder options for stone;  C.wd(color, extra) timber;  C.mt(color, extra) metal
//   C.stoneColor(tint), C.blockTint(), C.erosion()
//   C.lacquer(k) / C.jade(k) / C.bare(k) / C.iron(k) / C.bronze(k)   vertex-colour functions
//   C.colliders          { circles: [{x, z, r, y0, h, tag}], boxes: [{x, z, hx, hz, yaw, y0, h, tag}] }

import * as THREE from 'three';
import { DEG, smoothstep } from '../core/math.js';
import { Builder, noise3, fbm3 } from './geometry.js';
import { LAYOUT, PALETTE, HALL, GATE } from './config.js';
import { buildTerrace } from './terrace.js';
import { buildGallery, buildHall, buildGate } from './timber.js';
import { dressTerrace } from './dressing.js';
import { buildFlora } from './flora.js';

const ringPos = (r, th, y = 0) => new THREE.Vector3(r * Math.sin(th), y, -r * Math.cos(th));

/**
 * @param {Function} rng   deterministic rng (makeRng)
 * @param {object} tier    tierSettings()
 * @returns {object} { stone, metal, props, foliage: BufferGeometry, banners: cloth specs, braziers: Vector3[4],
 *   lamps: Vector3[], flames, smokes, colliders, stairs, landmarks, sections }
 */
export function buildRuins(rng, tier) {
  const S = new Builder({ orn: true });   // stone + roof tiles
  const M = new Builder({ orn: true });   // bronze + iron
  const P = new Builder({ orn: true });   // painted timber, bare wood, rope
  // fire sources known up front (the baked glow needs them): the four of env.braziers, then the extra lit lanterns
  // sources with a real point light glow weakly in the bake (uFire.a = 0.3 on those tiers); the others carry their
  // whole light in it, so they are boosted to read the same on every tier
  const fireA = tier.pointLights > 0 ? 0.3 : 1.1;
  const fires = LAYOUT.braziers.map(([deg, r, kind], i) => { const p = ringPos(r, deg * DEG, kind === 'lantern' ? 1.73 : 1.6); p.k = i < tier.pointLights ? 1 : 1.1 / fireA; return p; });
  LAYOUT.lamps.forEach(([deg, r, y0 = 0], i) => { if (i >= 4 && tier.detail < 1) return; const p = ringPos(r, deg * DEG, y0 + 1.6); p.k = 0.55 * 1.1 / fireA; fires.push(p); });
  const glow = (p) => {
    let g = 0;
    for (const b of fires) {
      const dx = p.x - b.x, dy = p.y - b.y, dz = p.z - b.z;
      g += Math.min(b.k * 1.2, b.k * Math.exp(-(dx * dx + dy * dy * 0.6 + dz * dz) / 7.5));
    }
    return g;
  };
  // albedo multiplier: big discolouration patches, grime + rain streaks toward the ground, moss on tops
  const stoneColor = (tint) => (p, n, out) => {
    const v = 0.8 + 0.4 * fbm3(p.x * 0.13, p.y * 0.13, p.z * 0.13, 2);
    const ground = 0.5 + 0.5 * smoothstep(-0.5, 3.0, p.y);
    const streak = 0.86 + 0.14 * noise3(p.x * 2.1 + p.z * 1.7, p.y * 0.16, 0.5);
    const up = Math.max(0, n.y);
    const moss = up > 0.55 ? smoothstep(0.45, 0.7, fbm3(p.x * 0.6, p.y * 0.6, p.z * 0.6, 2)) * 0.7 : 0;
    const k = v * ground * streak * tint;
    out[0] = k * (1 - moss * 0.45);
    out[1] = k * (1 - moss * 0.2);
    out[2] = k * (1 - moss * 0.55);
  };
  const paint = (rgb, wet = 0.3) => (k = 1) => (p, n, out) => {
    // patchy fading, darker and damper toward the foot of a member
    const v = k * (0.72 + 0.56 * fbm3(p.x * 0.45, p.y * 0.3, p.z * 0.45, 2)) * (1 - wet + wet * smoothstep(0.0, 2.6, p.y - LAYOUT.platY * 0.5));
    out[0] = rgb[0] * v; out[1] = rgb[1] * v; out[2] = rgb[2] * v;
  };
  const metalCol = (rgb, rustK) => (k = 1) => (p, n, out) => {
    const rust = smoothstep(0.45, 0.75, noise3(p.x * 6, p.y * 6, p.z * 6));
    out[0] = rgb[0] * k * (1 + rust * rustK); out[1] = rgb[1] * k * (1 + rust * rustK * 0.35); out[2] = rgb[2] * k * (1 - rust * 0.2);
  };
  const colliders = { circles: [], boxes: [] };
  const C = {
    S, M, P, rng, tier, glow, stoneColor, colliders,
    blockTint: () => rng.range(0.78, 1.18),
    erosion: () => (rng.chance(0.18) ? rng.range(0.15, 0.4) : rng.range(0.65, 1.0)),
    st: (tint, extra) => ({ color: stoneColor(tint), glow, uv: 'box', uvScale: 2.2, ...extra }),
    wd: (color, extra) => ({ color, glow: (p) => glow(p) * 0.6, uv: 'box', uvScale: 1.1, ...extra }),
    mt: (color, extra) => ({ color, uv: 'box', uvScale: 1.5, ...extra }),
    lacquer: paint(PALETTE.lacquer), jade: paint(PALETTE.jade, 0.2), bare: paint(PALETTE.wood, 0.15),
    iron: metalCol([0.075, 0.07, 0.068], 1.4), bronze: metalCol([0.2, 0.125, 0.055], 0.25),
  };

  const terrace = buildTerrace(C);
  const pillars = buildGallery(C);
  const hall = buildHall(C);
  const gate = buildGate(C);
  const dress = dressTerrace(C, { fires, pillars, hall, gate });
  const foliage = buildFlora(C);

  const sections = { ...S.tris };
  for (const [k, v] of Object.entries(M.tris)) sections['metal.' + k] = v;
  for (const [k, v] of Object.entries(P.tris)) sections['wood.' + k] = v;
  sections.foliage = foliage.index.count / 3;
  const landmarks = {
    hall: { x: hall.base.elements[12], z: hall.base.elements[14], theta: HALL.th, eaveY: hall.yEave, ridgeY: hall.ridgeY },
    gate: { x: gate.base.elements[12], z: gate.base.elements[14], theta: GATE.th, eaveY: gate.yEave, ridgeY: gate.ridgeY, clearWidth: GATE.halfBay * 2 - 0.62, clearHeight: GATE.colH - 1.4 },
    stele: { x: ringPos(14.25, 72 * DEG).x, z: ringPos(14.25, 72 * DEG).z },
    impact: { x: -4.4, z: -6.2, r: 2.9 },
  };
  return {
    stone: S.build(), metal: M.build(), props: P.build(), foliage,
    banners: dress.cloth, braziers: dress.tops, lamps: dress.lamps, flames: dress.flames, smokes: dress.smokes,
    colliders, stairs: terrace.stairs, landmarks, sections,
  };
}
