// Set dressing that tells the arena's story, merged into the ruins' builders (no extra draw calls beyond the props
// material): votive candle clusters and offerings at the braziers, chains draped and hanging from the arches, a
// gibbet cage, dead trees whose roots grip the podium wall, hanging dead vines, broken weapons and shields
// half-buried near the ring edge, and the shattered flagstones heaved up around the old impact.
// Returns the candle flame tongues for the fire mesh.

import * as THREE from 'three';
import { DEG, smoothstep } from '../core/math.js';
import { chamferBox, latheGrid, rock, addAll, trs, noise3, tube, setOrnUv, brokenBlock } from './geometry.js';
import { ORN, panel } from './ornament.js';
import { LAYOUT } from './config.js';

const WAX = [[0.42, 0.37, 0.27], [0.36, 0.31, 0.22], [0.2, 0.045, 0.035], [0.3, 0.26, 0.19]];
const WOOD = [0.06, 0.047, 0.036];
const ROOT = [0.052, 0.045, 0.038];
const VINE = [0.045, 0.043, 0.034];
const CLAY = [0.11, 0.066, 0.044];

/** Old impact centre (x, z) and radius: matches the floor bake (bake.js IMPACT). */
export const IMPACT = [-4.4, -6.2, 2.9];

/**
 * @param {object} o  { S, M, P builders, rng, tier, braziers, pillars, arches, stoneColor, glow, ringPos }
 * @returns {Array<{pos: THREE.Vector3, w: number, h: number, i: number}>} candle flames
 */
export function dressRuins(o) {
  const { S, M, P, rng, tier, braziers, pillars, arches, stoneColor, glow, ringPos } = o;
  const hi = tier.detail >= 2, mid = tier.detail >= 1;
  const flames = [];
  const iron = (k = 1) => (p, n, out) => {
    // rust blooms and pitting on the dark iron (vertex colour multiplies the iron albedo)
    const r = noise3(p.x * 6, p.y * 6, p.z * 6);
    const rust = smoothstep(0.45, 0.75, r);
    out[0] = k * (1 + rust * 1.4); out[1] = k * (1 + rust * 0.5); out[2] = k * (1 - rust * 0.2);
  };

  // ---- votive candles and offerings at the braziers ------------------------------------------------------------------
  P.section('candles');
  const nCandle = hi ? 12 : mid ? 8 : 4;
  braziers.forEach((b, bi) => {
    const th = Math.atan2(b.x, -b.z);
    const inward = new THREE.Vector3(-Math.sin(th), 0, Math.cos(th));
    const side = new THREE.Vector3(Math.cos(th), 0, Math.sin(th));
    for (let k = 0; k < nCandle; k++) {
      // clustered on the arena side of the pedestal and on its plinth, tall ones at the back
      const onPlinth = k < 3;
      const a = rng.range(-1.9, 1.9);
      const d = onPlinth ? rng.range(0.36, 0.48) : rng.range(0.6, 1.05) + (k % 3) * 0.08;
      const p = b.clone().addScaledVector(inward, Math.cos(a) * d).addScaledVector(side, Math.sin(a) * d);
      const y0 = onPlinth ? 0.22 : 0;
      const h = (onPlinth ? rng.range(0.1, 0.22) : rng.range(0.05, 0.34)) * (1.15 - 0.3 * Math.cos(a));
      const r = rng.range(0.018, 0.038) + h * 0.05;
      const col = rng.pick(WAX);
      const lit = rng.chance(0.75);
      const top = y0 + h;
      const seed = rng.range(0, 40);
      const waxGlow = (q) => (lit ? 2.2 * smoothstep(top - 0.07, top, q.y) : 0) + glow(q) * 0.3;
      // body with a melted, slumped rim
      const body = latheGrid({
        rows: 2, segs: 6, profile: (t) => [r * (1 + 0.12 * t * t), y0 + t * h],
        rmod: (phi, yy) => 1 + (noise3(Math.cos(phi) * 2 + seed, yy * 18, Math.sin(phi) * 2) - 0.5) * 0.25,
        topY: (phi) => top - Math.abs(noise3(Math.cos(phi) * 1.5 + seed, Math.sin(phi) * 1.5, 1)) * r * 1.2,
        capTop: top - r * 0.5,
      });
      addAll(P, body, trs(p.x, 0, p.z, rng.range(0, 6)), { color: col, glow: waxGlow, uv: [0, 0] });
      // drips running down the side, and a wax pool around the foot
      const nd = rng.int(0, 2);
      for (let j = 0; j < nd; j++) {
        const ph = rng.range(0, Math.PI * 2);
        const len = rng.range(0.3, 0.9) * h;
        const q = new THREE.Vector3(Math.cos(ph) * r * 1.05, 0, Math.sin(ph) * r * 1.05);
        const g = latheGrid({ rows: 1, segs: 3, profile: (t) => [0.006 + 0.004 * t, -t * len], capTop: false, capBottom: true });
        addAll(P, g, trs(p.x + q.x, top - 0.01, p.z + q.z), { color: col, glow: waxGlow, uv: [0, 0] });
      }
      if (!onPlinth || rng.chance(0.5)) {
        const pr = r * rng.range(1.8, 3.2);
        const pool = latheGrid({ rows: 1, segs: 6, profile: (t) => [pr * (1 - t * 0.85), y0 + 0.004 + t * 0.012], rmod: (phi) => 1 + (noise3(Math.cos(phi) * 2 + seed, Math.sin(phi) * 2, 2) - 0.5) * 0.6, capTop: true });
        addAll(P, pool, trs(p.x, 0, p.z), { color: col, glow: (q) => glow(q) * 0.3, uv: [0, 0] });
      }
      if (lit) flames.push({ pos: new THREE.Vector3(p.x, top - r * 0.4, p.z), w: 0.035 + r * 0.4, h: 0.07 + r * 1.4, i: rng.range(0.4, 0.62) });
    }
    // offerings: a clay bowl of iron coins, a cracked urn, a small carved stele (alternate braziers)
    if (bi < 2 || hi) {
      const q = b.clone().addScaledVector(inward, 0.75).addScaledVector(side, (bi % 2 ? -1 : 1) * 0.55);
      const bowl = latheGrid({ rows: 3, segs: 10, profile: (t) => [0.05 + 0.09 * Math.sin(t * Math.PI * 0.5), t * 0.07], capBottom: true });
      addAll(P, bowl, trs(q.x, 0, q.z), { color: CLAY, glow: (v) => glow(v) * 0.3, uv: [0, 0] });
      for (let c = 0; c < (hi ? 5 : 2); c++) {
        const cg = latheGrid({ rows: 1, segs: 6, profile: (t) => [0.016, t * 0.004], capTop: true });
        addAll(M, cg, trs(q.x + rng.range(-0.05, 0.05), 0.045 + c * 0.004, q.z + rng.range(-0.05, 0.05), 0, rng.range(-0.3, 0.3), rng.range(-0.3, 0.3)), { color: [2.2, 1.6, 0.8] });
      }
      const u = b.clone().addScaledVector(inward, 0.55).addScaledVector(side, (bi % 2 ? 1 : -1) * 0.7);
      const urn = latheGrid({ rows: 6, segs: 10, profile: (t) => [0.07 + 0.09 * Math.sin(t * Math.PI) - (t > 0.85 ? 0.04 : 0), t * 0.36], topY: (phi) => 0.36 - Math.max(0, Math.sin(phi * 1.5 + bi)) * 0.12, capBottom: true });
      addAll(P, urn, trs(u.x, 0, u.z, rng.range(0, 6), rng.range(-0.08, 0.08), 0), { color: [0.09, 0.06, 0.045], glow: (v) => glow(v) * 0.3, uv: [0, 0] });
      if (mid) {
        const s = b.clone().addScaledVector(inward, -0.15).addScaledVector(side, (bi % 2 ? 1 : -1) * 0.85);
        const g = chamferBox(0.34, 0.5, 0.12, 0.02, rng, 0.4);
        setOrnUv(g, (pp, n) => (n.z > 0.9 ? [pp.x / 0.34 + 0.5, (pp.y + 0.25 - 0.12) / 0.34, 1] : null));
        S.add(g, trs(s.x, 0.25, s.z, -th + rng.range(-0.2, 0.2), rng.range(-0.06, 0.06), rng.range(-0.05, 0.05)), { color: stoneColor(0.95), glow, uv: 'box', uvScale: 2.2, orn: { cell: panel(ORN.roundel), amount: 1, su: 1, sv: 1 } });
      }
    }
  });

  // ---- chains -------------------------------------------------------------------------------------------------------
  M.section('chains');
  const linkGeo = new THREE.TorusGeometry(0.05, 0.013, 3, 6);
  linkGeo.scale(1.45, 1, 1);
  /** Iron links along a polyline (each link along the local tangent, alternate links turned 90 degrees). */
  const chainAlong = (pts, k = 0.9) => {
    const pitch = 0.13;
    let carry = 0, n = 0;
    for (let i = 0; i < pts.length - 1; i++) {
      const a = pts[i], b = pts[i + 1];
      const seg = b.clone().sub(a);
      const L = seg.length();
      const dir = seg.clone().normalize();
      const q = new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(1, 0, 0), dir);
      let s = carry;
      while (s < L) {
        const p = a.clone().addScaledVector(dir, s);
        const qq = q.clone().multiply(new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(1, 0, 0), (n % 2) * Math.PI / 2 + 0.3));
        M.add(linkGeo, new THREE.Matrix4().compose(p, qq, new THREE.Vector3(1, 1, 1)), { color: iron(k) });
        s += pitch; n++;
      }
      carry = s - L;
    }
  };
  const catenary = (a, b, sag, n = 16) => {
    const out = [];
    for (let i = 0; i <= n; i++) {
      const t = i / n;
      const p = a.clone().lerp(b, t);
      p.y -= sag * 4 * t * (1 - t);
      out.push(p);
    }
    return out;
  };
  const byPair = (a, b) => arches.find((r) => r.A.equals(pillars.find((p) => p.i === a).pos) && r.B.equals(pillars.find((p) => p.i === b).pos));
  if (mid) {
    // draped across the face of two arches, from capital to capital
    for (const [a, b, sag] of [[5, 6, 1.6], [13, 14, 1.3]]) {
      const r = byPair(a, b);
      if (!r) continue;
      const p0 = r.C.clone().addScaledVector(r.u, -r.chord / 2 + 0.9).addScaledVector(r.w, -0.95); p0.y = 8.25;
      const p1 = r.C.clone().addScaledVector(r.u, r.chord / 2 - 0.9).addScaledVector(r.w, -0.95); p1.y = 8.25;
      chainAlong(catenary(p0, p1, sag, 14));
    }
  }
  // hanging from keystones, broken off; one carries the gibbet cage
  const cageArch = byPair(16, 17) || arches[arches.length - 1];
  {
    const r = byPair(4, 5);
    if (r && mid) {
      const top = r.C.clone().addScaledVector(r.w, -0.6); top.y = r.top - 0.75;
      chainAlong([top, top.clone().add(new THREE.Vector3(0.05, -1.4, 0.02)), top.clone().add(new THREE.Vector3(0.12, -2.9, 0.06))]);
    }
  }
  M.section('cage');
  {
    const r = cageArch;
    const top = r.C.clone().addScaledVector(r.w, -0.55); top.y = r.top - 0.75;
    const cageTop = top.clone().add(new THREE.Vector3(0, -1.5, 0));
    chainAlong([top, cageTop.clone().add(new THREE.Vector3(0, 0.25, 0))]);
    // gibbet: hoop rings, eight bars bowing out, a domed crown of straps, a hanging ring; one bar torn open
    const H = 1.75, R = 0.42;
    const yaw = rng.range(0, 6);
    const center = cageTop.clone();
    const ringAt = (y, rr) => {
      const pts = [];
      for (let i = 0; i <= 12; i++) { const a = (i / 12) * Math.PI * 2; pts.push(new THREE.Vector3(Math.cos(a) * rr, y, Math.sin(a) * rr)); }
      return pts;
    };
    const place = trs(center.x, center.y, center.z, yaw, 0.04, 0.05);
    for (const [y, rr] of [[-0.25, R * 0.85], [-H * 0.55, R * 1.04], [-H, R * 0.7]]) addAll(M, [tube(ringAt(y, rr), 0.014, { sides: 3 })], place, { color: iron(0.9) });
    for (let i = 0; i < 8; i++) {
      const a = (i / 8) * Math.PI * 2;
      const pts = [];
      for (let j = 0; j <= 6; j++) {
        const t = j / 6;
        const y = -0.25 - t * (H - 0.25);
        const rr = R * (0.85 + 0.35 * Math.sin(t * Math.PI) - 0.15 * t);
        const open = i === 3 ? Math.sin(t * Math.PI) * 0.25 : 0;
        pts.push(new THREE.Vector3(Math.cos(a) * (rr + open), y, Math.sin(a) * (rr + open)));
      }
      addAll(M, [tube(pts, 0.012, { sides: 3 })], place, { color: iron(1) });
    }
    for (let i = 0; i < 4; i++) {
      const a = (i / 4) * Math.PI * 2;
      const pts = [];
      for (let j = 0; j <= 4; j++) { const t = j / 4; const rr = R * 0.85 * Math.sin((1 - t) * Math.PI * 0.5); pts.push(new THREE.Vector3(Math.cos(a) * rr, -0.25 + Math.cos((1 - t) * Math.PI * 0.5) * 0.25, Math.sin(a) * rr)); }
      addAll(M, [tube(pts, 0.016, { sides: 3 })], place, { color: iron(0.9) });
    }
    // the hanging ring the chain passes through (vertical, above the crown)
    const hoop = ringAt(0, 0.07).map((p) => new THREE.Vector3(p.x, 0.07 + p.z, 0));
    addAll(M, [tube(hoop, 0.012, { sides: 3 })], place, { color: iron(0.9) });
  }
  // a second cage fallen on its side at the left wall, burst open
  if (hi) {
    const c = ringPos(14.2, -74 * DEG, 0.36);
    const place = trs(c.x, c.y, c.z, rng.range(0, 6), 0, Math.PI / 2 - 0.15);
    for (const [y, rr] of [[0.6, 0.36], [-0.2, 0.43], [-0.85, 0.3]]) {
      const pts = [];
      for (let i = 0; i <= 10; i++) { const a = (i / 10) * Math.PI * 2 * 0.85; pts.push(new THREE.Vector3(Math.cos(a) * rr, y, Math.sin(a) * rr)); }
      addAll(M, [tube(pts, 0.014, { sides: 3 })], place, { color: iron(1.1) });
    }
    for (let i = 0; i < 6; i++) {
      const a = (i / 7) * Math.PI * 2;
      const bend = i === 2 ? 0.35 : 0;
      addAll(M, [tube([new THREE.Vector3(Math.cos(a) * 0.36, 0.6, Math.sin(a) * 0.36), new THREE.Vector3(Math.cos(a) * (0.45 + bend), -0.2, Math.sin(a) * (0.45 + bend)), new THREE.Vector3(Math.cos(a) * 0.3, -0.85, Math.sin(a) * 0.3)], 0.012, { sides: 3 })], place, { color: iron(1.1) });
    }
    chainAlong([c.clone().add(new THREE.Vector3(0.6, -0.33, 0.1)), c.clone().add(new THREE.Vector3(1.2, -0.34, 0.5)), c.clone().add(new THREE.Vector3(1.5, -0.34, 1.2))], 1.1);
  }

  // ---- dead trees rooted in the wall top, roots gripping down the inner face; hanging dead vines ---------------------
  P.section('vegetation');
  const branch = (from, dir, len, r0, depth, out) => {
    const pts = [from.clone()];
    const d = dir.clone().normalize();
    const n = Math.max(3, Math.round(len / 0.35));
    let p = from.clone();
    for (let i = 1; i <= n; i++) {
      d.x += rng.range(-0.25, 0.25); d.z += rng.range(-0.25, 0.25); d.y += rng.range(-0.12, 0.1);
      d.normalize();
      p = p.clone().addScaledVector(d, len / n);
      pts.push(p);
    }
    out.push({ pts, r0 });
    if (depth > 0) {
      const kids = depth > 1 ? 2 : rng.int(1, 2);
      for (let k = 0; k < kids; k++) {
        const at = pts[Math.max(1, Math.round(pts.length * rng.range(0.45, 0.95)) - 1)];
        const nd = d.clone().add(new THREE.Vector3(rng.range(-0.9, 0.9), rng.range(-0.1, 0.5), rng.range(-0.9, 0.9)));
        branch(at, nd, len * rng.range(0.45, 0.7), r0 * 0.55, depth - 1, out);
      }
    }
  };
  const root = (from, inward, drop, r0, out) => {
    // over the cornice lip, down the face (hugging it, wandering), splaying on the floor
    const pts = [from.clone()];
    let p = from.clone().addScaledVector(inward, 0.45).add(new THREE.Vector3(0, 0.05, 0));
    pts.push(p);
    const side = new THREE.Vector3(inward.z, 0, -inward.x);
    const n = Math.round(drop / 0.3);
    for (let i = 1; i <= n; i++) {
      p = p.clone().add(new THREE.Vector3(0, -drop / n, 0)).addScaledVector(side, rng.range(-0.12, 0.12));
      const hug = i === 1 ? 0.05 : -0.015;
      p.addScaledVector(inward, hug);
      pts.push(p);
    }
    pts.push(p.clone().addScaledVector(inward, 0.35).add(new THREE.Vector3(0, -0.05, 0)).addScaledVector(side, rng.range(-0.3, 0.3)));
    out.push({ pts, r0 });
  };
  const trees = hi ? [[47, 1.0], [-52, 0.8], [-101, 0.7]] : mid ? [[47, 1.0], [-52, 0.8]] : [[47, 1.0]];
  for (const [deg, sc] of trees) {
    const th = deg * DEG;
    const wallTop = 3.62;
    const base = ringPos(16.25, th, wallTop - 0.05);
    const inward = new THREE.Vector3(-Math.sin(th), 0, Math.cos(th));
    const parts = [];
    branch(base, new THREE.Vector3(inward.x * 0.35, 1, inward.z * 0.35), 3.2 * sc, 0.16 * sc, hi ? 3 : 2, parts);
    for (let k = 0; k < (hi ? 5 : 3); k++) root(ringPos(16.1, th + rng.range(-0.05, 0.05), wallTop - 0.02), inward, wallTop - 0.1, rng.range(0.03, 0.07) * sc, parts);
    for (const b of parts) {
      const g = tube(b.pts, (t) => b.r0 * (1 - 0.7 * t) + 0.006, { sides: b.r0 > 0.09 ? 6 : b.r0 > 0.04 ? 4 : 3, caps: false });
      P.add(g, new THREE.Matrix4(), { color: b.r0 > 0.05 && b.pts[0].y > 3.5 ? WOOD : ROOT, glow: (q) => glow(q) * 0.4, uv: [0, 0] });
    }
  }
  if (mid) {
    // curtains of dead vines from the entablatures and the cornice
    // a dead vine: a woody stem that wanders as it hangs, thinning, with a few short dry side shoots
    const strand = (top, len, sway) => {
      const pts = [];
      const n = Math.max(5, Math.round(len / 0.22));
      let x = 0, z = 0;
      for (let i = 0; i <= n; i++) {
        const t = i / n;
        x += Math.sin(t * 7 + sway) * 0.05 + (noise3(t * 4, sway, 1) - 0.5) * 0.12;
        z += Math.cos(t * 5 + sway * 1.3) * 0.03;
        pts.push(top.clone().add(new THREE.Vector3(x * t, -t * len * (1 - 0.15 * t), z * t)));
      }
      const parts = [tube(pts, (t) => 0.026 * (1 - 0.7 * t) + 0.005, { sides: 3 })];
      for (let k = 1; k < n - 1; k += 3) {
        const a = pts[k], dir = new THREE.Vector3(Math.sin(k + sway) * 0.2, -0.12, Math.cos(k * 1.7 + sway) * 0.2);
        parts.push(tube([a, a.clone().add(dir), a.clone().add(dir.clone().multiplyScalar(1.8)).add(new THREE.Vector3(0, -0.12, 0))], 0.007, { sides: 3 }));
      }
      return parts;
    };
    for (const r of arches) {
      if (rng.chance(0.3)) continue;
      // clumped near one end of the entablature, not combed evenly across it
      const n = hi ? rng.int(2, 4) : rng.int(1, 2);
      const c0 = rng.range(-r.chord / 2, r.chord / 2);
      for (let k = 0; k < n; k++) {
        const s = c0 + rng.range(-0.5, 0.5);
        const top = r.C.clone().addScaledVector(r.u, s).addScaledVector(r.w, -1.15); top.y = r.top - 0.02;
        addAll(P, strand(top, rng.range(0.9, 2.6), rng.range(0, 6)), new THREE.Matrix4(), { color: VINE, uv: [0, 0] });
      }
    }
    const nC = hi ? 16 : 8;
    for (let k = 0; k < nC; k++) {
      const th = rng.range(-120, 120) * DEG;
      if (Math.abs(th) < 30 * DEG || o.coursesAt(th) <= o.courses) continue;
      const top = ringPos(LAYOUT.wallR - 0.3, th, o.courseY[o.courses] + 0.7);
      addAll(P, strand(top, rng.range(0.6, 2.0), rng.range(0, 6)), new THREE.Matrix4(), { color: VINE, uv: [0, 0] });
    }
  }

  // ---- broken weapons and shields, half-buried near the ring edge (never on the fight line) ---------------------------
  M.section('arms');
  const nArms = hi ? 14 : mid ? 9 : 5;
  const spots = [];
  for (let k = 0; k < 200 && spots.length < nArms; k++) {
    const th = rng.range(-95, 95) * DEG;
    if (Math.abs(th) < 22 * DEG) continue;
    const r = rng.range(11.2, 14.4);
    const p = ringPos(r, th, 0);
    if (p.z > -2.6) continue;
    if (braziers.some((b) => Math.hypot(b.x - p.x, b.z - p.z) < 1.6)) continue;
    if (spots.some((s) => s.distanceTo(p) < 1.6)) continue;
    spots.push(p);
  }
  spots.forEach((p, k) => {
    const kind = k % 4;
    const yaw = rng.range(0, Math.PI * 2);
    if (kind === 0) {
      // a greatsword snapped, its blade driven into the floor at an angle
      const L = rng.range(0.55, 0.95);
      const m = trs(p.x, 0, p.z, yaw, rng.range(-0.5, 0.5), rng.range(-0.45, 0.45));
      const blade = latheGrid({ rows: 2, segs: 4, squash: 0.18, profile: (t) => [0.06 * (1 - 0.15 * t), -0.25 + t * L], topY: (phi) => -0.25 + L - Math.abs(Math.sin(phi * 2.0 + k)) * 0.09, capTop: -0.25 + L - 0.05 });
      addAll(M, blade, m, { color: iron(1.3) });
      M.add(chamferBox(0.36, 0.045, 0.06, 0.01), m.clone().multiply(trs(0, -0.25 + L + 0.02, 0)), { color: iron(1) });
      addAll(P, [tube([new THREE.Vector3(0, -0.25 + L + 0.04, 0), new THREE.Vector3(0, -0.25 + L + 0.3, 0)], 0.022, { sides: 5, caps: true })], m, { color: [0.035, 0.024, 0.018], uv: [0, 0] });
      M.add(chamferBox(0.06, 0.06, 0.06, 0.015), m.clone().multiply(trs(0, -0.25 + L + 0.33, 0)), { color: iron(1) });
    } else if (kind === 1) {
      // a round shield, rim and boss, tipped over and half sunk in the dirt
      const R = rng.range(0.32, 0.45);
      const m = trs(p.x, R * 0.12, p.z, yaw, rng.range(1.32, 1.5), rng.range(-0.25, 0.25));
      addAll(P, latheGrid({ rows: 2, segs: 14, profile: (t) => [R * (1 - t), 0.02 + t * 0.06], rmod: (phi) => (Math.abs(Math.sin(phi * 3.0 + k)) > 0.97 ? 0.82 : 1), capTop: true, capBottom: true }), m, { color: WOOD, uv: [0, 0] });
      addAll(M, [tube(Array.from({ length: 15 }, (_, i) => { const a = (i / 14) * Math.PI * 2; return new THREE.Vector3(Math.cos(a) * R, 0.03, Math.sin(a) * R); }), 0.018, { sides: 3 })], m, { color: iron(1.2) });
      addAll(M, latheGrid({ rows: 3, segs: 8, profile: (t) => [0.09 * Math.cos(t * Math.PI * 0.5), 0.07 + t * 0.06], capTop: true }), m, { color: iron(1.1) });
    } else if (kind === 2) {
      // a spear snapped in two, the head half buried
      const L1 = rng.range(0.8, 1.3);
      const a0 = p.clone().add(new THREE.Vector3(0, 0.03, 0));
      const dir = new THREE.Vector3(Math.cos(yaw), 0, Math.sin(yaw));
      addAll(P, [tube([a0, a0.clone().addScaledVector(dir, L1).add(new THREE.Vector3(0, 0.02, 0))], 0.02, { sides: 5, caps: true })], new THREE.Matrix4(), { color: WOOD, uv: [0, 0] });
      const b0 = a0.clone().addScaledVector(dir, L1 + 0.15).add(new THREE.Vector3(rng.range(-0.2, 0.2), 0, rng.range(-0.2, 0.2)));
      const d2 = dir.clone().applyAxisAngle(new THREE.Vector3(0, 1, 0), rng.range(-0.5, 0.5));
      addAll(P, [tube([b0, b0.clone().addScaledVector(d2, 0.6).add(new THREE.Vector3(0, -0.04, 0))], 0.02, { sides: 5, caps: true })], new THREE.Matrix4(), { color: WOOD, uv: [0, 0] });
      const hm = trs(b0.x + d2.x * 0.75, 0.0, b0.z + d2.z * 0.75, Math.atan2(-d2.z, d2.x), 0, -Math.PI / 2 - 0.25);
      addAll(M, latheGrid({ rows: 3, segs: 4, squash: 0.3, profile: (t) => [0.05 * Math.sin((1 - t) * Math.PI * 0.8 + 0.3), t * 0.3], capTop: true }), hm, { color: iron(1.2) });
    } else {
      // a helm on its side and a broken blade beside it
      const m = trs(p.x, 0.1, p.z, yaw, Math.PI / 2 - 0.3, rng.range(-0.3, 0.3));
      addAll(M, latheGrid({ rows: 5, segs: 10, profile: (t) => [0.15 * Math.sin((1 - t) * Math.PI * 0.5 + 0.05) + 0.01, t * 0.24], rmod: (phi) => (Math.cos(phi) > 0.75 ? 1.12 : 1), capTop: true }), m, { color: iron(1.1) });
      const L = rng.range(0.4, 0.6);
      const bm = trs(p.x + 0.35, 0.02, p.z - 0.2, yaw + 1.3, 0, Math.PI / 2 - 0.06);
      addAll(M, latheGrid({ rows: 1, segs: 4, squash: 0.18, profile: (t) => [0.05, t * L], topY: (phi) => L - Math.abs(Math.sin(phi * 2 + k)) * 0.06, capTop: L - 0.03 }), bm, { color: iron(1.3) });
    }
  });

  // ---- the old impact: flagstones heaved up and shattered around the crater rim ----------------------------------------
  S.section('impact');
  {
    const [ix, iz, ir] = IMPACT;
    const n = hi ? 14 : mid ? 10 : 7;
    for (let k = 0; k < n; k++) {
      const a = (k / n) * Math.PI * 2 + rng.range(-0.2, 0.2);
      const d = ir * rng.range(0.55, 0.95);
      const x = ix + Math.cos(a) * d, z = iz + Math.sin(a) * d;
      const w = rng.range(0.55, 0.95), dd = rng.range(0.45, 0.75), h = rng.range(0.22, 0.34);
      // tipped up on the crater side, the outer edge still in the floor: thick, shattered, scorched
      const lift = rng.range(0.18, 0.5) * (1 - d / ir * 0.45);
      const g = brokenBlock(w, h, dd, rng, { jag: 0.4, nx: 3, nz: 2, bottom: true });
      const m = trs(x, -h * 0.3 + Math.sin(lift) * dd * 0.3, z, -a + Math.PI / 2 + rng.range(-0.3, 0.3), lift, rng.range(-0.15, 0.15));
      S.add(g, m, { color: stoneColor(rng.range(0.08, 0.13)), glow, uv: 'box', uvScale: 1.3 });
    }
    for (let k = 0; k < (hi ? 30 : 14); k++) {
      const a = rng.range(0, Math.PI * 2), d = ir * Math.sqrt(rng()) * 1.25;
      const s = rng.range(0.05, 0.14);
      S.add(rock(s, rng, { detail: 0, squash: 0.5 }), trs(ix + Math.cos(a) * d, s * 0.2, iz + Math.sin(a) * d, rng.range(0, 6)), { color: stoneColor(0.22), glow, uv: 'box', uvScale: 1.3 });
    }
  }
  linkGeo.dispose();
  return flames;
}
