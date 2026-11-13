// Curved tile roofs (기와지붕) from code: a roof is a set of slope patches, each a concave surface that steepens
// toward the ridge and lifts at the corners (the upturned eave), covered with rows of convex cover tiles (수키와,
// real half-round geometry: the eave silhouette and the grazing light need it) over a pan-tile surface carved by the
// relief atlas (ORN.tile). Ridges (용마루 / 추녀마루) are swept profiles; rafters and the eave board hang under the edge.
// Everything is returned as plain geometries with `ornUv`; the caller adds them to its builders.

import * as THREE from 'three';
import { sweep, mergeSimple } from './geometry.js';

const V = (x, y, z) => new THREE.Vector3(x, y, z);

/**
 * One roof slope in its own frame: X along the eave, Z outward (down the slope), Y up. The ridge runs along X at
 * z = 0, y = rise; the eave edge at z = depth, y = 0 (plus the corner lift).
 *
 * @param {object} o
 * @param {number} o.eaveHalf     half length of the eave
 * @param {number} [o.ridgeHalf]  half length of the ridge (default = eaveHalf: a gable slope; 0: a hip end)
 * @param {number} o.depth        plan depth, ridge to eave
 * @param {number} o.rise         ridge height above the eave
 * @param {number} [o.lift=0.5]   how far the eave corners rise
 * @param {number} [o.flare=0.25] how far the corners swing outward in plan
 * @param {number} [o.pitch=0.34] cover-tile row spacing
 * @param {number} [o.tube=0.085] cover-tile radius
 * @param {number} [o.nu=10], [o.nt=5]  surface grid
 * @param {boolean} [o.rows=true] build the cover-tile rows
 * @param {Function} [o.cut]      (x, t) => true where the roof is gone (x: metres along the eave, t: 0 ridge .. 1 eave)
 * @param {Function} [o.sag]      (x, t) => metres added to y (sagging / slumped structure)
 * @param {boolean} [o.soffit]    also return the underside (boards under the tiles)
 * @returns {{surface, rows, soffit, S: Function, N: Function, eave: THREE.Vector3[], hipL: THREE.Vector3[], hipR: THREE.Vector3[], o}}
 */
export function roofPatch(o) {
  const a = o.eaveHalf, ar = o.ridgeHalf !== undefined ? o.ridgeHalf : a, b = o.depth, H = o.rise;
  const lift = o.lift !== undefined ? o.lift : 0.5, flare = o.flare !== undefined ? o.flare : 0.25;
  const pitch = o.pitch || 0.34, rt = o.tube || 0.085, nu = o.nu || 10, nt = o.nt || 5;
  const cut = o.cut || (() => false), sag = o.sag || (() => 0);
  const slopeLen = Math.hypot(b, H) * 1.06;
  /** Surface point at u in -1..1 (along the eave), t in 0..1 (ridge to eave). */
  const S = (u, t, out = V(0, 0, 0)) => {
    const au = Math.abs(u), c = au * au * au * t * t;
    const xw = ar + (a - ar) * t;
    const x = u * xw + Math.sign(u) * flare * c;
    const k = Math.max(0, 1 - t);
    return out.set(x, H * (0.28 * k + 0.72 * Math.pow(k, 2.1)) + lift * c + sag(x, t), b * t + flare * c);
  };
  const _a = V(0, 0, 0), _b = V(0, 0, 0), _c = V(0, 0, 0);
  /** Unit surface normal (pointing up / out). */
  const N = (u, t, out = V(0, 0, 0)) => {
    const e = 0.02;
    const u0 = Math.max(-1, u - e), u1 = Math.min(1, u + e), t0 = Math.max(0, t - e), t1 = Math.min(1, t + e);
    S(u1, t, _a).sub(S(u0, t, _b));
    S(u, t1, _c).sub(S(u, t0, _b));
    out.crossVectors(_c, _a).normalize();
    if (out.y < 0) out.negate();
    return out;
  };

  // ---- pan-tile surface -------------------------------------------------------------------------------------------
  const pos = [], ouv = [], uv = [], idx = [];
  const p = V(0, 0, 0);
  for (let j = 0; j <= nt; j++) for (let i = 0; i <= nu; i++) {
    const u = -1 + (2 * i) / nu, t = j / nt;
    S(u, t, p);
    pos.push(p.x, p.y, p.z);
    ouv.push(p.x / pitch + 0.5, (t * slopeLen) / 0.4, 1);
    uv.push(p.x, t * slopeLen);
  }
  for (let j = 0; j < nt; j++) for (let i = 0; i < nu; i++) {
    const uc = -1 + (2 * i + 1) / nu, tc = (j + 0.5) / nt;
    if (cut(S(uc, tc, p).x, tc)) continue;
    const q0 = j * (nu + 1) + i, q1 = q0 + 1, q2 = q0 + nu + 1, q3 = q2 + 1;
    idx.push(q0, q2, q1, q1, q2, q3);
  }
  const mk = (ps, os, us, ix) => {
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(ps, 3));
    g.setAttribute('ornUv', new THREE.Float32BufferAttribute(os, 3));
    g.setAttribute('uv', new THREE.Float32BufferAttribute(us, 2));
    g.setIndex(ix);
    g.computeVertexNormals();
    return g;
  };
  const surface = mk(pos, ouv, uv, idx);
  let soffit = null;
  if (o.soffit) {
    const sp = [], n = V(0, 0, 0);
    for (let j = 0; j <= nt; j++) for (let i = 0; i <= nu; i++) {
      const u = -1 + (2 * i) / nu, t = j / nt;
      S(u, t, p).addScaledVector(N(u, t, n), -0.14);
      sp.push(p.x, p.y, p.z);
    }
    const si = [];
    for (let k = 0; k < idx.length; k += 3) si.push(idx[k], idx[k + 2], idx[k + 1]);
    soffit = mk(sp, ouv.map((v, k) => (k % 3 === 2 ? 0 : v)), uv, si);
  }

  // ---- cover-tile rows ----------------------------------------------------------------------------------------------
  let rows = null;
  const rowX = [];
  if (o.rows !== false) {
    const rp = [], rn = [], ro = [], ru = [], ri = [];
    const n0 = V(0, 0, 0), tg = V(0, 0, 0), side = V(0, 0, 0), q = V(0, 0, 0), prev = V(0, 0, 0);
    const count = Math.max(1, Math.round((2 * a) / pitch));
    const step = (2 * a) / count;
    for (let r = 0; r < count; r++) {
      const x0 = -a + (r + 0.5) * step;
      const tStart = a > ar + 1e-6 ? Math.max(0, (Math.abs(x0) - ar) / (a - ar)) : 0;
      if (tStart > 0.94) continue;
      rowX.push(x0);
      const nseg = Math.max(1, Math.ceil((1 - tStart) * nt));
      let ring = -1;
      for (let s = 0; s <= nseg; s++) {
        const t = tStart + ((1 - tStart) * s) / nseg;
        const u = Math.max(-1, Math.min(1, x0 / Math.max(1e-5, ar + (a - ar) * t)));
        S(u, t, p);
        const tm = tStart + ((1 - tStart) * (s - 0.5)) / nseg;
        const gone = s > 0 && cut(x0, tm);
        N(u, t, n0);
        const t1 = Math.min(1, t + 0.03), t0 = Math.max(tStart, t - 0.03);
        S(Math.max(-1, Math.min(1, x0 / Math.max(1e-5, ar + (a - ar) * t1))), t1, tg).sub(S(Math.max(-1, Math.min(1, x0 / Math.max(1e-5, ar + (a - ar) * t0))), t0, q)).normalize();
        side.crossVectors(tg, n0).normalize();
        const base = rp.length / 3;
        for (let k = 0; k < 4; k++) {
          const ang = (k / 3) * Math.PI, cs = Math.cos(ang), sn = Math.sin(ang);
          q.copy(p).addScaledVector(side, cs * rt).addScaledVector(n0, sn * rt * 1.15 - 0.012);
          rp.push(q.x, q.y, q.z);
          q.copy(side).multiplyScalar(cs).addScaledVector(n0, sn).normalize();
          rn.push(q.x, q.y, q.z);
          ro.push(0, (t * slopeLen) / 0.4, 1);
          ru.push(k * 0.08, t * slopeLen);
        }
        if (s > 0 && !gone && ring >= 0) {
          for (let k = 0; k < 3; k++) ri.push(ring + k, base + k, ring + k + 1, ring + k + 1, base + k, base + k + 1);
        }
        ring = base;
        prev.copy(p);
        // round end tile (막새) closing the row at the eave
        if (s === nseg && !cut(x0, 0.97)) {
          const c = rp.length / 3;
          q.copy(p).addScaledVector(n0, rt * 0.35).addScaledVector(tg, 0.012);
          rp.push(q.x, q.y, q.z); rn.push(tg.x, tg.y, tg.z); ro.push(0, 0, 0); ru.push(0, 0);
          for (let k = 0; k < 4; k++) {
            rp.push(rp[(base + k) * 3], rp[(base + k) * 3 + 1], rp[(base + k) * 3 + 2]);
            rn.push(tg.x, tg.y, tg.z); ro.push(0, 0, 0); ru.push(0, 0);
          }
          for (let k = 0; k < 3; k++) ri.push(c, c + 2 + k, c + 1 + k);
        }
      }
    }
    rows = new THREE.BufferGeometry();
    rows.setAttribute('position', new THREE.Float32BufferAttribute(rp, 3));
    rows.setAttribute('normal', new THREE.Float32BufferAttribute(rn, 3));
    rows.setAttribute('ornUv', new THREE.Float32BufferAttribute(ro, 3));
    rows.setAttribute('uv', new THREE.Float32BufferAttribute(ru, 2));
    rows.setIndex(ri);
  }
  const eave = [], hipL = [], hipR = [];
  for (let i = 0; i <= nu; i++) eave.push(S(-1 + (2 * i) / nu, 1, V(0, 0, 0)));
  for (let j = 0; j <= nt; j++) { hipL.push(S(-1, j / nt, V(0, 0, 0))); hipR.push(S(1, j / nt, V(0, 0, 0))); }
  return { surface, rows, soffit, S, N, eave, hipL, hipR, rowX, o: { a, ar, b, H, pitch, cut } };
}

/** Closed ridge-tile profile (rounded top) of width w and height h, for sweep(). */
const ridgeProfile = (w, h) => [[-w * 0.5, 0], [w * 0.5, 0], [w * 0.6, h * 0.55, false], [w * 0.32, h, false], [-w * 0.32, h, false], [-w * 0.6, h * 0.55, false], [-w * 0.5, 0]];

/**
 * A ridge of stacked tiles swept along a polyline (the main ridge, a hip ridge, a wall coping).
 * `tip` > 0 lifts and thickens the last point (the upturned end of a hip ridge).
 * @param {THREE.Vector3[]} pts
 * @returns {THREE.BufferGeometry}
 */
export function ridge(pts, { w = 0.34, h = 0.36, tip = 0 } = {}) {
  const path = [];
  for (let i = 0; i < pts.length; i++) {
    const a = pts[Math.max(0, i - 1)], b = pts[Math.min(pts.length - 1, i + 1)];
    const d = b.clone().sub(a);
    const side = V(d.z, 0, -d.x).normalize();
    const pt = pts[i].clone();
    if (tip && i === pts.length - 1) pt.y += tip;
    path.push({ p: pt, side, up: V(0, 1, 0) });
  }
  return sweep(ridgeProfile(w, h), path, { orn: { 2: [0, 1], 4: [0, 1] } });
}

/**
 * Rafters (서까래) under the eave of a patch: open prisms from the eave edge back up the slope, one under every
 * `every`-th tile row, plus the eave board along the edge.
 * @returns {THREE.BufferGeometry} non-indexed, flat shaded, with uv (v along the rafter)
 */
export function rafters(patch, { every = 2, len = 1.5, size = 0.11, drop = 0.16 } = {}) {
  const { S, N, rowX, o } = patch;
  const pos = [], nrm = [], uv = [];
  const p0 = V(0, 0, 0), p1 = V(0, 0, 0), n0 = V(0, 0, 0), n1 = V(0, 0, 0), side = V(0, 0, 0), d = V(0, 0, 0);
  const quad = (A, B, C, D, ref) => {
    const nn = B.clone().sub(A).cross(C.clone().sub(A)).normalize();
    const flip = nn.dot(ref) < 0;
    if (flip) nn.negate();
    const order = flip ? [[A, [0, 0]], [C, [size, len]], [B, [size, 0]], [A, [0, 0]], [D, [0, len]], [C, [size, len]]] : [[A, [0, 0]], [B, [size, 0]], [C, [size, len]], [A, [0, 0]], [C, [size, len]], [D, [0, len]]];
    for (const [q, t] of order) { pos.push(q.x, q.y, q.z); nrm.push(nn.x, nn.y, nn.z); uv.push(t[0], t[1]); }
  };
  const tIn = Math.max(0, 1 - len / o.b);
  for (let r = 0; r < rowX.length; r += every) {
    const x0 = rowX[r];
    if (o.cut(x0, 0.95)) continue;
    const u1 = Math.max(-1, Math.min(1, x0 / o.a)), u0 = Math.max(-1, Math.min(1, x0 / Math.max(1e-5, o.ar + (o.a - o.ar) * tIn)));
    if (Math.abs(u0) >= 0.999 && o.a > o.ar) continue;
    S(u1, 1, p1).addScaledVector(N(u1, 1, n1), -drop); S(u0, tIn, p0).addScaledVector(N(u0, tIn, n0), -drop);
    d.copy(p1).sub(p0).normalize();
    p1.addScaledVector(d, -0.06);
    side.crossVectors(d, n1).normalize();
    const hs = side.clone().multiplyScalar(size / 2);
    const a0 = p0.clone().sub(hs), a1 = p0.clone().add(hs), b0 = p1.clone().sub(hs), b1 = p1.clone().add(hs);
    const dn0 = n0.clone().multiplyScalar(-size), dn1 = n1.clone().multiplyScalar(-size);
    const c0 = a0.clone().add(dn0), c1 = a1.clone().add(dn0), e0 = b0.clone().add(dn1), e1 = b1.clone().add(dn1);
    quad(c0, c1, e1, e0, n1.clone().negate());   // underside
    quad(a0, c0, e0, b0, side.clone().negate()); // sides
    quad(a1, b1, e1, c1, side);
    quad(b0, e0, e1, b1, d);                     // end grain at the eave
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('normal', new THREE.Float32BufferAttribute(nrm, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  return g;
}

/** The eave board (연함) under the tile ends: thin sweeps along the surviving runs of a patch's eave polyline. */
export function eaveBoard(patch, { h = 0.1, d = 0.07, drop = 0.03 } = {}) {
  const runs = [];
  let run = [];
  for (const p of patch.eave) {
    if (patch.o.cut(p.x, 0.97)) { if (run.length > 1) runs.push(run); run = []; } else run.push(p);
  }
  if (run.length > 1) runs.push(run);
  if (!runs.length) return null;
  const parts = runs.map((pts) => sweep([[0, 0], [d, 0], [d, h], [0, h], [0, 0]], pts.map((p) => ({ p: V(p.x, p.y - drop - h, p.z - d * 0.5), side: V(0, 0, 1), up: V(0, 1, 0) }))));
  return mergeSimple(parts);
}

export { mergeSimple };
