// The colosseum ruins, built from code: an ashlar podium wall, a ring of colossal fluted piers carrying arches, the
// collapsed seating tier, the broken cliff edge of the vista gap behind the fighters, rubble, brazier pedestals and the
// iron fittings banners hang from. Returns merged geometries (one draw call per material) plus anchor points.

import * as THREE from 'three';
import { DEG, smoothstep, clamp } from '../core/math.js';
import { Builder, chamferBox, latheGrid, rock, addAll, trs, noise3, fbm3, flatNormals } from './geometry.js';
import { LAYOUT } from './config.js';

const ringPos = (r, th, y = 0) => new THREE.Vector3(r * Math.sin(th), y, -r * Math.cos(th));

/**
 * @param {Function} rng   deterministic rng (makeRng)
 * @param {object} tier    tierSettings()
 * @returns {{stone: THREE.BufferGeometry, metal: THREE.BufferGeometry, banners: Array, braziers: Array, pillars: Array}}
 */
export function buildRuins(rng, tier) {
  const S = new Builder();   // stone
  const M = new Builder();   // iron
  const braziers = LAYOUT.braziers.map(([deg, r]) => ringPos(r, deg * DEG, 0));
  const glow = (p) => {
    let g = 0;
    for (const b of braziers) {
      const dx = p.x - b.x, dy = p.y - 1.5, dz = p.z - b.z;
      g += Math.exp(-(dx * dx + dy * dy * 0.6 + dz * dz) / 7.5);
    }
    return Math.min(g, 1.2);
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
  const blockTint = () => rng.range(0.78, 1.18);

  const { wallR, wallT, pillarR, gap, thetaMax } = LAYOUT;

  // ---- podium wall ----------------------------------------------------------------------------------------------
  const courseH = 0.6, courses = 5;
  const wallRc = wallR + wallT / 2;
  const coursesAt = (th) => {
    const a = Math.abs(th);
    if (a < gap) return Math.round(clamp(0.4 + 1.4 * noise3(th * 9, 1.3, 0.2) + (a / gap) * 1.6, 0, 3));
    const dip = noise3(th * 5 + 4, 7.7, 0.3);
    let c = courses + 1;
    if (dip > 0.66) c = Math.round(2 + (1 - dip) * 6);
    if (a < gap + 7 * DEG) c = Math.min(c, Math.round(2 + (a - gap) / (7 * DEG) * 3));
    return c;
  };
  for (let c = 0; c <= courses; c++) {
    const coping = c === courses;
    const h = coping ? 0.36 : courseH;
    const y0 = c * courseH;
    let th = -thetaMax - rng.range(0, 1.2) / wallRc;
    while (th < thetaMax) {
      const L = coping ? rng.range(1.4, 2.1) : rng.range(0.95, 1.75);
      const dth = L / wallRc;
      const tc = th + dth / 2;
      th += dth;
      const n = coursesAt(tc);
      if (c >= n) continue;
      const top = c === n - 1 && n < courses + 1;
      const fallen = top && rng.chance(0.25);
      const hh = top ? h * rng.range(0.55, 1) : h;
      const depth = coping ? wallT + 0.28 : wallT;
      const rr = coping ? wallRc - 0.12 : wallRc;
      const geo = chamferBox(L - 0.025, hh - 0.012, depth, coping ? 0.06 : 0.045, rng, top ? 0.5 : 0.12);
      const jitter = fallen ? rng.range(-0.25, 0.25) : rng.range(-0.012, 0.012);
      const p = ringPos(rr + jitter, tc, y0 + hh / 2);
      const m = trs(p.x, p.y, p.z, -tc + rng.range(-0.01, 0.01) + (fallen ? rng.range(-0.2, 0.2) : 0), fallen ? rng.range(-0.15, 0.15) : 0, fallen ? rng.range(-0.1, 0.1) : rng.range(-0.004, 0.004));
      S.add(geo, m, { color: stoneColor(blockTint() * (coping ? 0.92 : 1)), glow, uv: 'box', uvScale: 2.2 });
    }
  }

  // ---- outer ground and the broken cliff edge -----------------------------------------------------------------------
  const edgeR = (th) => {
    const a = Math.abs(th);
    const inGap = 1 - smoothstep(gap - 2 * DEG, gap + 9 * DEG, a);
    return 31 - inGap * (31 - (17.1 + 1.6 * noise3(th * 7, 0.5, 2.2) + 0.9 * noise3(th * 23, 1.5, 0.2)));
  };
  {
    const segs = 128, rows = 6;
    const pos = [], idx = [];
    for (let i = 0; i <= segs; i++) {
      const th = -thetaMax + (2 * thetaMax * i) / segs;
      const re = edgeR(th);
      for (let j = 0; j <= rows; j++) {
        const r = wallR - 0.2 + (re - wallR + 0.2) * (j / rows);
        const p = ringPos(r, th, 0);
        pos.push(p.x, j === rows ? -0.05 : 0, p.z);
      }
    }
    for (let i = 0; i < segs; i++) for (let j = 0; j < rows; j++) {
      const a = i * (rows + 1) + j, b = a + 1, c = a + rows + 1, d = c + 1;
      idx.push(a, b, c, b, d, c);
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    g.setIndex(idx);
    g.computeVertexNormals();
    S.add(g, new THREE.Matrix4(), { color: stoneColor(0.8), glow, uv: 'box', uvScale: 3 });
    // cliff face under the edge (only where it can be seen: the gap and its shoulders)
    const cpos = [], cidx = [];
    const crow = 10;
    const thA = gap + 16 * DEG;
    const cseg = 72;
    for (let i = 0; i <= cseg; i++) {
      const th = -thA + (2 * thA * i) / cseg;
      const re = edgeR(th);
      for (let j = 0; j <= crow; j++) {
        const t = j / crow;
        const y = -0.05 - t * t * 40;
        const out = t * 6 + (fbm3(th * 6, y * 0.12, 1.0, 3) - 0.5) * 3.2 * (0.3 + t);
        const p = ringPos(re + out - 0.2 * (1 - t), th, y);
        cpos.push(p.x, p.y, p.z);
      }
    }
    for (let i = 0; i < cseg; i++) for (let j = 0; j < crow; j++) {
      const a = i * (crow + 1) + j, b = a + 1, c = a + crow + 1, d = c + 1;
      cidx.push(a, c, b, b, c, d);
    }
    const cg = new THREE.BufferGeometry();
    cg.setAttribute('position', new THREE.Float32BufferAttribute(cpos, 3));
    cg.setIndex(cidx);
    const flat = flatNormals(cg.toNonIndexed());
    S.add(flat, new THREE.Matrix4(), { color: (p, n, o) => { const k = 0.55 * (0.7 + 0.5 * noise3(p.x * 0.3, p.y * 0.3, p.z * 0.3)); o[0] = k; o[1] = k * 0.98; o[2] = k * 0.95; }, uv: 'box', uvScale: 4 });
  }

  // ---- colonnade -------------------------------------------------------------------------------------------------
  // per slot: H = height (null = gone), cap = intact with capital
  const slotDeg = 360 / LAYOUT.pillarCount;
  const slotState = {
    3: { H: 5.6 }, 4: { cap: true }, 5: { cap: true }, 6: { cap: true }, 7: { cap: true }, 8: { H: 9.6 }, 9: { H: 4.4 },
    10: { H: 1.7 }, 11: null, 12: { H: 6.6 }, 13: { cap: true }, 14: { cap: true }, 15: { H: 10.8 }, 16: { cap: true },
    17: { cap: true }, 18: { H: 3.1 },
  };
  const capH = 8.0, pierR = 0.95;
  const pillars = [];
  const drum = 1.55;
  for (const key of Object.keys(slotState)) {
    const i = Number(key);
    const st = slotState[i];
    const th = (i - 10.5) * slotDeg * DEG;
    const base = ringPos(pillarR, th, 0);
    pillars.push({ i, th, pos: base, state: st });
    if (!st) continue;
    const tint = blockTint();
    const col = { color: stoneColor(tint), glow, uv: 'keep', uvScale: 2.4 };
    // plinth + torus base
    S.add(chamferBox(2.5, 0.55, 2.5, 0.06, rng, 0.2), trs(base.x, 0.275, base.z, -th), { color: stoneColor(tint * 0.95), glow, uv: 'box', uvScale: 2.2 });
    addAll(S, latheGrid({ rows: 6, segs: 32, profile: (t) => [pierR + 0.18 * Math.sin(t * Math.PI) - 0.02 * t, 0.55 + t * 0.4] }), trs(base.x, 0, base.z, rng.range(0, 6)), col);
    // shaft in drums: fluted (alternating radii), entasis, slight misalignment, chips; jagged top if broken
    const H = st.cap ? capH - 0.75 : st.H;
    let y = 0.95;
    let dx = 0, dz = 0;
    while (y < H - 0.05) {
      const h = Math.min(drum, H - y);
      const last = y + h >= H - 0.05;
      dx += rng.range(-0.025, 0.025); dz += rng.range(-0.025, 0.025);
      const y0 = y;
      const seed = rng.range(0, 50);
      const chunk = rng.chance(0.22) ? rng.range(0, Math.PI * 2) : -9;
      const broken = last && !st.cap;
      const rTop = (t) => pierR * (1 - 0.1 * t * t);
      const parts = latheGrid({
        rows: 3, segs: 32,
        profile: (t) => {
          const yy = y0 + t * h;
          const tt = yy / Math.max(H, 6);
          const groove = t < 0.04 || t > 0.96 ? 0.965 : 1;
          return [rTop(tt) * groove, yy - (t === 1 ? 0.0 : 0)];
        },
        rmod: (phi, yy) => {
          const flute = (Math.round(phi / (Math.PI * 2) * 32) % 2) ? 0.955 : 1.0;
          let m = flute * (1 + (noise3(Math.cos(phi) * 2 + seed, yy * 1.2, Math.sin(phi) * 2) - 0.5) * 0.07);
          if (chunk > -1) { const dphi = Math.abs(((phi - chunk + Math.PI * 3) % (Math.PI * 2)) - Math.PI); if (dphi < 0.6) m *= 1 - 0.22 * (1 - dphi / 0.6); }
          return m;
        },
        topY: broken ? (phi) => y0 + h - Math.abs(noise3(Math.cos(phi) * 1.5 + seed, Math.sin(phi) * 1.5, 3.3) - 0.35) * 1.6 - 0.1 : null,
        capTop: broken ? y0 + h - rng.range(0.35, 0.8) : true,
      });
      addAll(S, parts, trs(base.x + dx, 0, base.z + dz, rng.range(0, 6)), col);
      y += h;
    }
    if (st.cap) {
      // echinus + abacus
      addAll(S, latheGrid({ rows: 4, segs: 32, profile: (t) => [pierR * 0.9 + 0.38 * t * t, H + t * 0.38], capTop: false }), trs(base.x + dx, 0, base.z + dz, 0), col);
      S.add(chamferBox(2.45, 0.38, 2.45, 0.05, rng, 0.25), trs(base.x + dx, H + 0.38 + 0.19, base.z + dz, -th), { color: stoneColor(tint), glow, uv: 'box', uvScale: 2.2 });
    }
  }

  // ---- arches between intact neighbours, with attic beams ------------------------------------------------------------
  const archPairs = [[4, 5], [5, 6], [6, 7], [13, 14], [16, 17]];
  const halfArch = [[7, 8]]; // a broken arch springing from slot 7 toward the fallen top of 8
  const voussoir = (pa, pb, count, keep) => {
    const A = pillars.find((p) => p.i === pa).pos, B = pillars.find((p) => p.i === pb).pos;
    const C = A.clone().add(B).multiplyScalar(0.5);
    const u = B.clone().sub(A); const chord = u.length(); u.normalize();
    const w = new THREE.Vector3().crossVectors(new THREE.Vector3(0, 1, 0), u).normalize(); // right-handed basis (t, rdir, w)
    const rIn = (chord - 2.45) / 2, th = 0.78, rMid = rIn + th / 2;
    const yS = capH;
    for (let k = 0; k < count; k++) {
      if (k >= keep) break;
      const a = Math.PI - ((k + 0.5) / count) * Math.PI;
      const rdir = u.clone().multiplyScalar(Math.cos(a)).add(new THREE.Vector3(0, Math.sin(a), 0));
      const t = u.clone().multiplyScalar(-Math.sin(a)).add(new THREE.Vector3(0, Math.cos(a), 0));
      const m = new THREE.Matrix4().makeBasis(t, rdir, w);
      const c = C.clone().addScaledVector(rdir, rMid); c.y += yS;
      m.setPosition(c);
      const arc = (Math.PI * rMid) / count;
      S.add(chamferBox(arc - 0.02, th, 1.55, 0.04, rng, 0.15), m, { color: stoneColor(blockTint()), glow, uv: 'box', uvScale: 2.2 });
    }
    return { C, u, w, chord, top: yS + rIn + th };
  };
  for (const [a, b] of archPairs) {
    const r = voussoir(a, b, 9, 9);
    // spandrel blocks over the capitals and an attic beam across
    const ang = Math.atan2(r.u.z, r.u.x);
    for (const s of [-1, 1]) {
      const p = r.C.clone().addScaledVector(r.u, s * (r.chord / 2 - 0.55));
      S.add(chamferBox(1.25, r.top - capH, 1.55, 0.05, rng, 0.2), trs(p.x, capH + (r.top - capH) / 2, p.z, -ang), { color: stoneColor(blockTint()), glow, uv: 'box', uvScale: 2.2 });
    }
    const attic = rng.chance(0.75);
    if (attic) S.add(chamferBox(r.chord + 0.9, 0.8, 1.8, 0.07, rng, 0.35), trs(r.C.x, r.top + 0.4, r.C.z, -ang, 0, rng.range(-0.01, 0.01)), { color: stoneColor(blockTint() * 0.95), glow, uv: 'box', uvScale: 2.2 });
  }
  for (const [a, b] of halfArch) voussoir(a, b, 9, 4);

  // second storey fragments on the best preserved bays
  for (const i of [5, 6, 16]) {
    const p = pillars.find((q) => q.i === i).pos;
    const h = i === 6 ? 2.6 : rng.range(3.5, 5.0);
    addAll(S, latheGrid({
      rows: 6, segs: 24, profile: (t) => [0.62 * (1 - 0.08 * t), 11.0 + t * h],
      rmod: (phi) => ((Math.round(phi / (Math.PI * 2) * 24) % 2) ? 0.95 : 1),
      topY: (phi) => 11.0 + h - Math.abs(noise3(Math.cos(phi) + i, Math.sin(phi), 0) - 0.4) * 1.2, capTop: 11.0 + h - 0.5,
    }), trs(p.x, 0, p.z, 0), { color: stoneColor(blockTint()), glow, uv: 'keep', uvScale: 2.4 });
  }

  // ---- seating tier (cavea), collapsed toward the vista ---------------------------------------------------------------
  const steps = 11, stepD = (LAYOUT.tierR1 - LAYOUT.tierR0) / steps, stepH = 0.52, tierBase = 3.6;
  const tierLimit = (th) => {
    const a = Math.abs(th);
    const g0 = th < 0 ? gap + 9 * DEG : gap + 5 * DEG;
    if (a < g0) return 0;
    return Math.min(steps, Math.floor(((a - g0) / (16 * DEG)) * steps + 2.0 * noise3(th * 11, 2.0, 0.0)));
  };
  for (let k = 0; k < steps; k++) {
    const r0 = LAYOUT.tierR0 + k * stepD;
    const rc = r0 + stepD / 2;
    const top = tierBase + (k + 1) * stepH;
    let th = -thetaMax;
    while (th < thetaMax) {
      const L = rng.range(2.0, 3.0);
      const dth = L / rc;
      const tc = th + dth / 2;
      th += dth;
      if (k >= tierLimit(tc)) continue;
      if (rng.chance(0.06)) continue; // fallen slab
      const sunk = rng.chance(0.08) ? rng.range(0.2, 0.5) : 0;
      const h = top - sunk;
      const p = ringPos(rc, tc, h / 2);
      S.add(chamferBox(L - 0.04, h, stepD + 0.02, 0.05, rng, 0.25), trs(p.x, p.y, p.z, -tc + rng.range(-0.006, 0.006), sunk ? rng.range(-0.04, 0.04) : 0, 0), { color: stoneColor(blockTint() * 0.9), glow, uv: 'box', uvScale: 2.2 });
    }
  }
  // outer facade fragments rising above the tier on the flanks
  for (const [d0, d1, h] of [[-112, -64, 13.5], [52, 98, 12.6]]) {
    const R = LAYOUT.tierR1 + 0.6;
    let th = d0 * DEG;
    while (th < d1 * DEG) {
      const L = rng.range(2.2, 3.4);
      const dth = L / R;
      const tc = th + dth / 2;
      th += dth;
      const hh = h * (0.55 + 0.45 * noise3(tc * 6, 0.3, 4.4)) + rng.range(-0.5, 0.5);
      const p = ringPos(R, tc, hh / 2);
      const pier = Math.round(tc / (6 * DEG)) % 2 === 0;
      S.add(chamferBox(L - 0.05, hh, pier ? 1.6 : 1.1, 0.06, rng, 0.3), trs(p.x, p.y, p.z, -tc), { color: stoneColor(blockTint() * 0.85), glow, uv: 'box', uvScale: 2.6 });
    }
  }

  // ---- fallen drums and rubble -----------------------------------------------------------------------------------
  const drumGeo = (len, seed) => latheGrid({
    rows: 2, segs: 18, profile: (t) => [pierR * 0.98, t * len],
    rmod: (phi, yy) => ((Math.round(phi / (Math.PI * 2) * 18) % 2) ? 0.95 : 1) * (1 + (noise3(Math.cos(phi) * 2 + seed, yy, Math.sin(phi) * 2) - 0.5) * 0.12),
    capTop: true, capBottom: true,
  });
  const fallen = [
    [-1.6, -15.0, 0.4, 1.2], [1.9, -16.5, 2.1, 1.5], [-4.6, -18.2, 0.9, 1.4], [3.9, -18.0, 2.6, 1.3],
    [12.6, -7.3, 1.25, 1.5], [13.4, -5.2, 1.4, 1.4], [14.1, -3.1, 1.6, 1.5], [-13.0, -6.2, 2.2, 1.3],
  ];
  for (const [x, z, ry, len] of fallen) {
    const seed = rng.range(0, 40);
    const m = trs(x, pierR * 0.9, z, ry, 0, Math.PI / 2 + rng.range(-0.08, 0.08));
    m.multiply(trs(0, -len / 2, 0));
    addAll(S, drumGeo(len, seed), m, { color: stoneColor(blockTint()), glow, uv: 'box', uvScale: 2.4 });
  }
  const rubbleN = Math.round(170 * tier.rubble);
  for (let i = 0; i < rubbleN; i++) {
    let p, s;
    const roll = rng();
    if (roll < 0.45) { // along the wall base, inside the arena (keeps clear of the fight line)
      const th = rng.range(-thetaMax * 0.9, thetaMax * 0.9);
      const a = Math.abs(th);
      const near = a < gap ? 0.75 : 0.35;
      if (!rng.chance(near)) continue;
      p = ringPos(rng.range(14.2, 15.4), th, 0); s = rng.range(0.12, a < gap ? 0.7 : 0.45);
    } else if (roll < 0.75) { // the gap: on the outer ground up to the edge
      const th = rng.range(-gap - 6 * DEG, gap + 6 * DEG);
      p = ringPos(rng.range(15.8, edgeR(th) - 0.3), th, 0); s = rng.range(0.2, 0.95);
    } else { // at broken pillar feet and tier breaks
      const pl = rng.pick(pillars.filter((q) => !q.state || !q.state.cap));
      const a = rng.range(0, Math.PI * 2), d = rng.range(1.0, 3.2);
      p = pl.pos.clone().add(new THREE.Vector3(Math.cos(a) * d, 0, Math.sin(a) * d));
      if (p.length() < 15.2) continue;
      s = rng.range(0.25, 1.1);
    }
    const isBlock = rng.chance(0.35);
    const g = isBlock ? chamferBox(s * rng.range(1.2, 2.2), s * rng.range(0.6, 1.0), s * rng.range(0.9, 1.4), 0.04, rng, 0.6) : rock(s, rng, { detail: s > 0.5 ? 1 : 0, squash: rng.range(0.45, 0.8) });
    S.add(g, trs(p.x, s * (isBlock ? 0.3 : 0.25), p.z, rng.range(0, 6), rng.range(-0.3, 0.3), rng.range(-0.3, 0.3)), { color: stoneColor(blockTint() * 0.9), glow, uv: 'box', uvScale: 2.2 });
  }

  // ---- braziers: stone pedestals (iron bowls go in the metal builder) ------------------------------------------------
  const brazierTops = [];
  for (const b of braziers) {
    const th = Math.atan2(b.x, -b.z);
    S.add(chamferBox(0.95, 0.22, 0.95, 0.04, rng, 0.2), trs(b.x, 0.11, b.z, -th), { color: stoneColor(0.9), glow, uv: 'box' });
    addAll(S, latheGrid({ rows: 5, segs: 8, profile: (t) => [0.3 - 0.07 * Math.sin(t * Math.PI) + (t > 0.85 ? 0.08 : 0), 0.22 + t * 0.78], capTop: true }), trs(b.x, 0, b.z, Math.PI / 8), { color: stoneColor(0.85), glow, uv: 'box' });
    // iron bowl with a rolled rim and three claws
    addAll(M, latheGrid({ rows: 6, segs: 20, profile: (t) => [0.18 + 0.42 * Math.sin(t * Math.PI * 0.5), 1.0 + t * 0.34] }), trs(b.x, 0, b.z), { color: [1, 1, 1] });
    addAll(M, latheGrid({ rows: 4, segs: 20, profile: (t) => [0.6 + 0.04 * Math.sin(t * Math.PI * 2), 1.34 + 0.04 * Math.cos(t * Math.PI * 2)] }), trs(b.x, 0, b.z), { color: [1, 1, 1] });
    for (let k = 0; k < 3; k++) {
      const a = (k / 3) * Math.PI * 2 + th;
      const g = chamferBox(0.07, 0.62, 0.12, 0.02);
      M.add(g, trs(b.x + Math.cos(a) * 0.36, 1.12, b.z + Math.sin(a) * 0.36, -a, 0, 0.5 * (k % 2 ? 1 : -1) * 0.2), { color: [1, 1, 1] });
    }
    brazierTops.push(new THREE.Vector3(b.x, 1.36, b.z));
  }

  // ---- banners: hang points + iron poles -----------------------------------------------------------------------------
  const banners = [];
  const onPillar = [5, 7, 13, 16, 4, 14, 17, 6];
  for (const i of onPillar.slice(0, tier.banners)) {
    const pl = pillars.find((q) => q.i === i);
    const inward = pl.pos.clone().setY(0).normalize().multiplyScalar(-1);
    const top = pl.pos.clone().addScaledVector(inward, pierR + 0.18);
    top.y = 7.35;
    banners.push({ top, normal: inward.clone(), width: rng.range(1.25, 1.5), length: rng.range(3.7, 4.0), seed: rng.range(0, 100) });
    const ang = Math.atan2(inward.z, inward.x);
    M.add(chamferBox(1.9, 0.07, 0.07, 0.015), trs(top.x, top.y + 0.05, top.z, -ang + Math.PI / 2), { color: [0.8, 0.8, 0.8] });
    M.add(chamferBox(0.05, 0.05, 0.42, 0.01), trs(top.x - inward.x * 0.2, top.y + 0.05, top.z - inward.z * 0.2, -ang + Math.PI / 2), { color: [0.8, 0.8, 0.8] });
  }

  return { stone: S.build(), metal: M.build(), banners, braziers: brazierTops, pillars, edgeR };
}
