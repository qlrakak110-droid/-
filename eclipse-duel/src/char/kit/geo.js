// Armour kit geometry core. Every builder returns an indexed BufferGeometry with `position`, `normal` and:
//   cav  (float)  1 = neutral, < 1 occluded crevice / inner surface, 1..2 convex edge (edge wear)  -> material surf.w
//   uvw  (vec3)   optional: (u, v, edge code) of cloth / fur surfaces                                -> material glow
// put() / putPair() hand them to the character kit (src/char/build.js) with a surface `look` (see looks.js).
//
//   plate(S, o)            thick plate over a parametric outer surface S(u, v): inner skin, rounded / beaded edges,
//                          rolled rims, hard creases (medial ridges), curvature-derived edge wear, occlusion field
//   sweep(path, section, o)  2D section swept along a 3D path (parallel-transport frames), hard corners, taper, twist
//   lathe(profile, o)      surface of revolution with hard rows                 extrude(shape, o)  bevelled extrusion
//   strip(S, pts, o)       raised ribbon following a (u, v) path on a parametric surface (inlays, engraved runes)
//   studs(list, o)         rivets / bosses       merge(geos)  concatenation keeping kit attributes

import * as THREE from 'three';
import { xf, mirrorZ } from '../shapes.js';
import { surfDetail } from '../materials.js';

const V = THREE.Vector3;

/** Build an indexed geometry from flat arrays (+ optional cav / uvw arrays). */
export function mk(pos, nor, idx, cav = null, uvw = null) {
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3));
  const n = pos.length / 3;
  g.setAttribute('cav', new THREE.Float32BufferAttribute(cav || new Float32Array(n).fill(1), 1));
  if (uvw) g.setAttribute('uvw', new THREE.Float32BufferAttribute(uvw, 3));
  g.setIndex(new THREE.BufferAttribute(n > 65535 ? new Uint32Array(idx) : new Uint32Array(idx), 1));
  return g;
}

/** Concatenate geometries (position, normal, cav, uvw kept; missing cav = 1, missing uvw = 0). */
export function merge(geos) {
  geos = geos.filter(Boolean);
  let nv = 0, ni = 0, hasUvw = false;
  for (const g of geos) { nv += g.attributes.position.count; ni += g.index.count; if (g.attributes.uvw) hasUvw = true; }
  const pos = new Float32Array(nv * 3), nor = new Float32Array(nv * 3), cav = new Float32Array(nv), idx = new Uint32Array(ni);
  const uvw = hasUvw ? new Float32Array(nv * 3) : null;
  let vo = 0, io = 0;
  for (const g of geos) {
    const c = g.attributes.position.count;
    pos.set(g.attributes.position.array.subarray(0, c * 3), vo * 3);
    nor.set(g.attributes.normal.array.subarray(0, c * 3), vo * 3);
    if (g.attributes.cav) cav.set(g.attributes.cav.array.subarray(0, c), vo); else cav.fill(1, vo, vo + c);
    if (uvw && g.attributes.uvw) uvw.set(g.attributes.uvw.array.subarray(0, c * 3), vo * 3);
    const a = g.index.array;
    for (let i = 0; i < a.length; i++) idx[io + i] = a[i] + vo;
    io += a.length; vo += c;
  }
  const out = new THREE.BufferGeometry();
  out.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  out.setAttribute('normal', new THREE.BufferAttribute(nor, 3));
  out.setAttribute('cav', new THREE.BufferAttribute(cav, 1));
  if (uvw) out.setAttribute('uvw', new THREE.BufferAttribute(uvw, 3));
  out.setIndex(new THREE.BufferAttribute(idx, 1));
  return out;
}

/** Transform in place ({ at, rot (deg, ZXY), scale }); returns the geometry. */
export function place(g, o) { return xf(g, o); }

/** Multiply the cav attribute by an occlusion function occ(p) -> 0..1 (only darkens; edge values > 1 keep their wear). */
export function occlude(g, occ) {
  const P = g.attributes.position.array, C = g.attributes.cav.array, p = [0, 0, 0];
  for (let i = 0; i < C.length; i++) {
    p[0] = P[i * 3]; p[1] = P[i * 3 + 1]; p[2] = P[i * 3 + 2];
    const k = occ(p);
    C[i] = C[i] > 1 ? 1 + (C[i] - 1) * k : C[i] * k;
  }
  return g;
}

/**
 * Per-vertex convexity from the mesh (discrete mean curvature along triangle edges): cav = 1 + clamp(k * scale).
 * Positive (convex) -> edge wear, negative (concave) -> crevice. scale ~ metres of "edge radius" that saturates.
 */
export function autoCav(g, scale = 0.004, lo = -0.45, hi = 0.95) {
  const P = g.attributes.position.array, N = g.attributes.normal.array, I = g.index.array;
  const n = P.length / 3, acc = new Float32Array(n), cnt = new Float32Array(n);
  const edge = (a, b) => {
    const dx = P[b * 3] - P[a * 3], dy = P[b * 3 + 1] - P[a * 3 + 1], dz = P[b * 3 + 2] - P[a * 3 + 2];
    const l2 = dx * dx + dy * dy + dz * dz;
    if (l2 < 1e-12) return;
    const k = ((N[b * 3] - N[a * 3]) * dx + (N[b * 3 + 1] - N[a * 3 + 1]) * dy + (N[b * 3 + 2] - N[a * 3 + 2]) * dz) / l2;
    acc[a] += k; cnt[a]++; acc[b] += k; cnt[b]++;
  };
  for (let t = 0; t < I.length; t += 3) { edge(I[t], I[t + 1]); edge(I[t + 1], I[t + 2]); edge(I[t + 2], I[t]); }
  const C = g.attributes.cav ? g.attributes.cav.array : new Float32Array(n).fill(1);
  for (let i = 0; i < n; i++) {
    const k = cnt[i] ? (acc[i] / cnt[i]) * scale : 0;
    C[i] = Math.max(0.2, Math.min(2, C[i] + Math.max(lo, Math.min(hi, k))));
  }
  if (!g.attributes.cav) g.setAttribute('cav', new THREE.BufferAttribute(C, 1));
  return g;
}

/**
 * Hard / smooth normals for a non-indexed triangle soup: faces sharing a position average their normals when the angle
 * between them is below `angle` degrees. Positions are hashed at 1e-5 m. Returns an indexed geometry (welded).
 */
export function creased(g, angle = 40) {
  const src = g.index ? g.toNonIndexed() : g;
  const P = src.attributes.position.array, nT = P.length / 9;
  const fn = new Float32Array(nT * 3);
  for (let t = 0; t < nT; t++) {
    const o = t * 9;
    const ax = P[o + 3] - P[o], ay = P[o + 4] - P[o + 1], az = P[o + 5] - P[o + 2];
    const bx = P[o + 6] - P[o], by = P[o + 7] - P[o + 1], bz = P[o + 8] - P[o + 2];
    let nx = ay * bz - az * by, ny = az * bx - ax * bz, nz = ax * by - ay * bx;
    const l = Math.hypot(nx, ny, nz) || 1;
    fn[t * 3] = nx / l; fn[t * 3 + 1] = ny / l; fn[t * 3 + 2] = nz / l;
  }
  const key = (i) => `${Math.round(P[i * 3] * 1e5)},${Math.round(P[i * 3 + 1] * 1e5)},${Math.round(P[i * 3 + 2] * 1e5)}`;
  const map = new Map();
  for (let v = 0; v < nT * 3; v++) { const k = key(v); let a = map.get(k); if (!a) map.set(k, (a = [])); a.push(v); }
  const cosA = Math.cos((angle * Math.PI) / 180);
  const nor = new Float32Array(nT * 9);
  for (const list of map.values()) {
    for (const v of list) {
      const t = (v / 3) | 0;
      let sx = 0, sy = 0, sz = 0;
      for (const w of list) {
        const u = (w / 3) | 0;
        const d = fn[t * 3] * fn[u * 3] + fn[t * 3 + 1] * fn[u * 3 + 1] + fn[t * 3 + 2] * fn[u * 3 + 2];
        if (d >= cosA) { sx += fn[u * 3]; sy += fn[u * 3 + 1]; sz += fn[u * 3 + 2]; }
      }
      const l = Math.hypot(sx, sy, sz) || 1;
      nor[v * 3] = sx / l; nor[v * 3 + 1] = sy / l; nor[v * 3 + 2] = sz / l;
    }
  }
  // weld identical (position, normal)
  const wmap = new Map(), pos = [], nr = [], idx = [];
  for (let v = 0; v < nT * 3; v++) {
    const k = key(v) + '|' + Math.round(nor[v * 3] * 1e3) + ',' + Math.round(nor[v * 3 + 1] * 1e3) + ',' + Math.round(nor[v * 3 + 2] * 1e3);
    let i = wmap.get(k);
    if (i === undefined) {
      i = pos.length / 3;
      wmap.set(k, i);
      pos.push(P[v * 3], P[v * 3 + 1], P[v * 3 + 2]);
      nr.push(nor[v * 3], nor[v * 3 + 1], nor[v * 3 + 2]);
    }
    idx.push(i);
  }
  return mk(pos, nr, idx);
}

// ---- plate -----------------------------------------------------------------------------------------------------------

function samples(n, creases, closed) {
  const out = [];
  const cs = [...creases].sort((a, b) => a - b);
  for (let i = 0; i <= n; i++) out.push({ t: i / n, side: 0 });
  for (const c of cs) {
    // snap the nearest sample onto the crease, then duplicate it (left copy / right copy)
    let best = 0;
    for (let i = 1; i < out.length; i++) if (Math.abs(out[i].t - c) < Math.abs(out[best].t - c)) best = i;
    out[best].t = c;
    out.splice(best, 1, { t: c, side: -1, crease: true }, { t: c, side: 1, crease: true });
  }
  if (closed) { out[0].side = 0; out[out.length - 1].side = 0; }
  return out;
}

/**
 * Thick plate over a parametric outer surface.
 * @param {function} S  (u, v) -> [x, y, z]   outer surface; u across (0..1), v along (0..1)
 * @param {object} o
 *   nu=16, nv=8          segments                 thick=0.006   plate thickness (m)
 *   closeU=false         S is periodic in u (a hoop): only the v0 / v1 edges exist
 *   edge='round'         edge profile for every side, or { u0, u1, v0, v1 }: 'round' | 'none' (open, hidden)
 *   edgeR=0              bead radius of round edges (default thick / 2; larger = swollen forged edge)
 *   roll={}              { u0 | u1 | v0 | v1: radius } rolled rim tubes along those sides
 *   creaseU=[], creaseV=[]   hard normal lines (ridges); ridgeWear=0.7 extra edge wear on convex creases
 *   axis=[0, 0]          (x, z) of the vertical axis the outside faces away from (orientation), or out(p) -> [x,y,z]
 *   flip=false           invert the orientation
 *   inner=false          build the inner skin (visible undersides only)   innerCav=0.42   edgeSegs=3   rollSegs=5
 *   occ(u, v) -> 0..1    occlusion of the outer surface (tucked under the plate above ...)
 *   curv=0.004           curvature -> edge wear scale     edgeWear=0.85 wear at the edge apex
 * @returns geometry with userData { S, sign, normalAt(u, v) }
 */
export function plate(S, o = {}) {
  const nu = o.nu ?? 16, nv = o.nv ?? 8, t = o.thick ?? 0.006, closeU = !!o.closeU;
  const us = samples(nu, o.creaseU || [], closeU), vs = samples(nv, o.creaseV || [], false);
  const W = us.length, H = vs.length, n = W * H;
  const P = new Float32Array(n * 3), N = new Float32Array(n * 3), TU = new Float32Array(n * 3), TV = new Float32Array(n * 3);
  const h = 1e-3;
  const d3 = (a, b, k) => [(b[0] - a[0]) * k, (b[1] - a[1]) * k, (b[2] - a[2]) * k];
  for (let j = 0; j < H; j++) {
    const v = vs[j].t, sv = vs[j].side;
    for (let i = 0; i < W; i++) {
      const u = us[i].t, su = us[i].side, k = j * W + i;
      const p = S(u, v);
      P[k * 3] = p[0]; P[k * 3 + 1] = p[1]; P[k * 3 + 2] = p[2];
      let du;
      if (closeU || (su === 0 && u > h && u < 1 - h)) du = d3(S(u - h, v), S(u + h, v), 0.5 / h);
      else if (su < 0 || u >= 1 - h) du = d3(S(u - h, v), p, 1 / h);
      else du = d3(p, S(u + h, v), 1 / h);
      let dv;
      if (sv === 0 && v > h && v < 1 - h) dv = d3(S(u, v - h), S(u, v + h), 0.5 / h);
      else if (sv < 0 || v >= 1 - h) dv = d3(S(u, v - h), p, 1 / h);
      else dv = d3(p, S(u, v + h), 1 / h);
      TU.set(du, k * 3); TV.set(dv, k * 3);
      const nx = du[1] * dv[2] - du[2] * dv[1], ny = du[2] * dv[0] - du[0] * dv[2], nz = du[0] * dv[1] - du[1] * dv[0];
      const l = Math.hypot(nx, ny, nz) || 1;
      N[k * 3] = nx / l; N[k * 3 + 1] = ny / l; N[k * 3 + 2] = nz / l;
    }
  }
  // orientation
  let dot = 0;
  const ax = (o.axis || [0, 0])[0], az = (o.axis || [0, 0])[1];
  for (let k = 0; k < n; k++) {
    let ox, oy, oz;
    if (o.out) { const d = o.out([P[k * 3], P[k * 3 + 1], P[k * 3 + 2]]); ox = d[0]; oy = d[1]; oz = d[2]; }
    else { ox = P[k * 3] - ax; oy = 0; oz = P[k * 3 + 2] - az; }
    dot += N[k * 3] * ox + N[k * 3 + 1] * oy + N[k * 3 + 2] * oz;
  }
  const sign = (dot >= 0 ? 1 : -1) * (o.flip ? -1 : 1);
  if (sign < 0) for (let k = 0; k < N.length; k++) N[k] = -N[k];

  const parts = [];
  // ---- outer skin
  const cav = new Float32Array(n).fill(1);
  const curv = o.curv ?? 0.004;
  for (let j = 0; j < H; j++) for (let i = 0; i < W; i++) {
    const k = j * W + i;
    let acc = 0, c = 0;
    const nb = (ii, jj) => {
      if (ii < 0 || jj < 0 || ii >= W || jj >= H) return;
      if (us[ii].t === us[i].t && ii !== i) return;
      if (vs[jj].t === vs[j].t && jj !== j) return;
      const q = jj * W + ii;
      const dx = P[q * 3] - P[k * 3], dy = P[q * 3 + 1] - P[k * 3 + 1], dz = P[q * 3 + 2] - P[k * 3 + 2], l2 = dx * dx + dy * dy + dz * dz;
      if (l2 < 1e-12) return;
      acc += ((N[q * 3] - N[k * 3]) * dx + (N[q * 3 + 1] - N[k * 3 + 1]) * dy + (N[q * 3 + 2] - N[k * 3 + 2]) * dz) / l2; c++;
    };
    nb(i - 1, j); nb(i + 1, j); nb(i, j - 1); nb(i, j + 1);
    let e = c ? Math.max(-0.4, Math.min(0.6, (acc / c) * curv)) : 0;
    if (us[i].crease || vs[j].crease) {
      // convex crease (ridge) when the two copies' normals open toward the crease direction
      const other = us[i].crease ? (us[i].side < 0 ? k + 1 : k - 1) : (vs[j].side < 0 ? k + W : k - W);
      const T = us[i].crease ? TU : TV, s = (us[i].crease ? us[i].side : vs[j].side) < 0 ? 1 : -1;
      const cx = (N[other * 3] - N[k * 3]) * T[k * 3] + (N[other * 3 + 1] - N[k * 3 + 1]) * T[k * 3 + 1] + (N[other * 3 + 2] - N[k * 3 + 2]) * T[k * 3 + 2];
      if (cx * s > 0) e += o.ridgeWear ?? 0.7; else e -= 0.25;
    }
    const oc = o.occ ? o.occ(us[i].t, vs[j].t) : 1;
    cav[k] = Math.max(0.2, Math.min(2, (1 + Math.max(0, e)) * oc + Math.min(0, e)));
  }
  const quads = (Wd, Hd, base, flip, skipU, skipV) => {
    const idx = [];
    for (let j = 0; j < Hd - 1; j++) {
      if (skipV && skipV(j)) continue;
      for (let i = 0; i < Wd - 1; i++) {
        if (skipU && skipU(i)) continue;
        const a = base + j * Wd + i, b = a + 1, d = a + Wd, c = d + 1;
        if (!flip) idx.push(a, b, d, b, c, d); else idx.push(a, d, b, b, d, c);
      }
    }
    return idx;
  };
  const skipU = (i) => us[i].t === us[i + 1].t, skipV = (j) => vs[j].t === vs[j + 1].t;
  parts.push(mk(P, N, quads(W, H, 0, sign < 0, skipU, skipV), cav));
  if (t > 0) {
    // ---- inner skin
    if (o.inner === true) {
      const PI = new Float32Array(n * 3), NI = new Float32Array(n * 3);
      for (let k = 0; k < n * 3; k++) { PI[k] = P[k] - N[k] * t; NI[k] = -N[k]; }
      parts.push(mk(PI, NI, quads(W, H, 0, sign > 0, skipU, skipV), new Float32Array(n).fill(o.innerCav ?? 0.42)));
    }
    // ---- edges: one ring swept around each boundary loop
    const edgeOf = (side) => (typeof o.edge === 'object' ? o.edge[side] ?? 'round' : o.edge ?? 'round');
    const loops = [];
    if (closeU) {
      loops.push({ ids: [...Array(W - 1).keys()], dirs: (k) => neg(TV, k), side: () => 'v0', closed: true });
      loops.push({ ids: [...Array(W - 1).keys()].map((i) => (H - 1) * W + i), dirs: (k) => pos(TV, k), side: () => 'v1', closed: true });
    } else {
      const ids = [], sides = [];
      for (let i = 0; i < W - 1; i++) { ids.push(i); sides.push('v0'); }
      for (let j = 0; j < H - 1; j++) { ids.push(j * W + W - 1); sides.push('u1'); }
      for (let i = W - 1; i > 0; i--) { ids.push((H - 1) * W + i); sides.push('v1'); }
      for (let j = H - 1; j > 0; j--) { ids.push(j * W); sides.push('u0'); }
      const dirOf = (k, sd) => (sd === 'v0' ? neg(TV, k) : sd === 'v1' ? pos(TV, k) : sd === 'u0' ? neg(TU, k) : pos(TU, k));
      loops.push({
        ids, closed: true,
        side: (m) => sides[m],
        dirs: (k, m) => {
          const sd = sides[m], prev = sides[(m - 1 + sides.length) % sides.length];
          const d = dirOf(k, sd);
          if (prev !== sd) { const e = dirOf(k, prev); d[0] += e[0]; d[1] += e[1]; d[2] += e[2]; }
          return d;
        },
      });
    }
    const K = o.edgeSegs ?? 3, er = Math.max(t / 2, o.edgeR ?? 0), ew = o.edgeWear ?? 0.85;
    for (const L of loops) {
      const m = L.ids.length, pos = [], nor = [], cv = [], idx = [];
      for (let q = 0; q < m; q++) {
        const k = L.ids[q];
        const nx = N[k * 3], ny = N[k * 3 + 1], nz = N[k * 3 + 2];
        let d = L.dirs(k, q);
        const dd = d[0] * nx + d[1] * ny + d[2] * nz;
        d = [d[0] - nx * dd, d[1] - ny * dd, d[2] - nz * dd];
        const l = Math.hypot(d[0], d[1], d[2]) || 1;
        d = [d[0] / l, d[1] / l, d[2] / l];
        for (let s = 0; s <= K; s++) {
          const ph = Math.PI / 2 - (Math.PI * s) / K, c = Math.cos(ph), sn = Math.sin(ph);
          const off = -t / 2 + (t / 2) * sn;
          pos.push(P[k * 3] + d[0] * er * c + nx * off, P[k * 3 + 1] + d[1] * er * c + ny * off, P[k * 3 + 2] + d[2] * er * c + nz * off);
          // normal of the (possibly elliptic) bead
          const ex = c / er, ey = sn / (t / 2);
          const el = Math.hypot(ex, ey) || 1;
          nor.push((d[0] * ex + nx * ey) / el, (d[1] * ex + ny * ey) / el, (d[2] * ex + nz * ey) / el);
          cv.push(1 + ew * Math.pow(Math.max(0, c), 1.5) * (oc(o, us, vs, k, W)));
        }
      }
      for (let q = 0; q < (L.closed ? m : m - 1); q++) {
        if (edgeOf(L.side(q)) === 'none') continue;
        const a = q * (K + 1), b = ((q + 1) % m) * (K + 1);
        for (let s = 0; s < K; s++) {
          const a0 = a + s, a1 = a + s + 1, b0 = b + s, b1 = b + s + 1;
          if (sign > 0) idx.push(a0, a1, b0, b0, a1, b1); else idx.push(a0, b0, a1, b0, b1, a1);
        }
      }
      if (idx.length) {
        const ring = mk(pos, nor, idx, cv);
        // orientation check (normals vs winding) on the first quad
        fixWinding(ring);
        parts.push(ring);
      }
    }
  }
  // ---- rolled rims
  for (const side of ['u0', 'u1', 'v0', 'v1']) {
    const R = o.roll && o.roll[side];
    if (!R) continue;
    if (closeU && (side === 'u0' || side === 'u1')) continue;
    let ids;
    if (side === 'v0') ids = [...Array(W).keys()];
    else if (side === 'v1') ids = [...Array(W).keys()].map((i) => (H - 1) * W + i);
    else if (side === 'u0') ids = [...Array(H).keys()].map((j) => j * W);
    else ids = [...Array(H).keys()].map((j) => j * W + W - 1);
    const T = side[0] === 'v' ? TV : TU, sg = side[1] === '0' ? -1 : 1;
    const pts = [], nn = [];
    for (const k of ids) {
      if (pts.length && Math.abs(P[k * 3] - pts[pts.length - 1][0]) + Math.abs(P[k * 3 + 1] - pts[pts.length - 1][1]) + Math.abs(P[k * 3 + 2] - pts[pts.length - 1][2]) < 1e-7) continue;
      const nx = N[k * 3], ny = N[k * 3 + 1], nz = N[k * 3 + 2];
      let d = [T[k * 3] * sg, T[k * 3 + 1] * sg, T[k * 3 + 2] * sg];
      const dd = d[0] * nx + d[1] * ny + d[2] * nz;
      d = [d[0] - nx * dd, d[1] - ny * dd, d[2] - nz * dd];
      const l = Math.hypot(d[0], d[1], d[2]) || 1;
      const lift = R * 0.55 - t * 0.5, out = R * 0.25;
      pts.push([P[k * 3] + nx * lift + (d[0] / l) * out, P[k * 3 + 1] + ny * lift + (d[1] / l) * out, P[k * 3 + 2] + nz * lift + (d[2] / l) * out]);
      nn.push([nx, ny, nz]);
    }
    if (pts.length < 2) continue;
    const closedRim = closeU && side[0] === 'v';
    parts.push(rimTube(pts, nn, R, o.rollSegs ?? 5, closedRim));
  }
  const g = merge(parts);
  g.userData.S = S;
  g.userData.sign = sign;
  g.userData.normalAt = (u, v) => {
    const p = S(u, v), a = S(Math.min(1, u + h), v), b = S(Math.max(0, u - h), v), c = S(u, Math.min(1, v + h)), e = S(u, Math.max(0, v - h));
    const du = [a[0] - b[0], a[1] - b[1], a[2] - b[2]], dv = [c[0] - e[0], c[1] - e[1], c[2] - e[2]];
    const nn = new V(du[1] * dv[2] - du[2] * dv[1], du[2] * dv[0] - du[0] * dv[2], du[0] * dv[1] - du[1] * dv[0]).normalize().multiplyScalar(sign);
    return { p: new V(p[0], p[1], p[2]), n: nn, du: new V(...du).normalize(), dv: new V(...dv).normalize() };
  };
  return g;
}

function oc(o, us, vs, k, W) {
  if (!o.occ) return 1;
  const i = k % W, j = (k / W) | 0;
  return Math.max(0.35, o.occ(us[i].t, vs[j].t));
}
const neg = (T, k) => [-T[k * 3], -T[k * 3 + 1], -T[k * 3 + 2]];
const pos = (T, k) => [T[k * 3], T[k * 3 + 1], T[k * 3 + 2]];

/** Make triangle winding agree with the stored normals (majority vote). */
export function fixWinding(g) {
  const P = g.attributes.position.array, N = g.attributes.normal.array, I = g.index.array;
  let s = 0;
  for (let t = 0; t < I.length; t += 3) {
    const a = I[t], b = I[t + 1], c = I[t + 2];
    const ux = P[b * 3] - P[a * 3], uy = P[b * 3 + 1] - P[a * 3 + 1], uz = P[b * 3 + 2] - P[a * 3 + 2];
    const vx = P[c * 3] - P[a * 3], vy = P[c * 3 + 1] - P[a * 3 + 1], vz = P[c * 3 + 2] - P[a * 3 + 2];
    const fx = uy * vz - uz * vy, fy = uz * vx - ux * vz, fz = ux * vy - uy * vx;
    s += fx * (N[a * 3] + N[b * 3] + N[c * 3]) + fy * (N[a * 3 + 1] + N[b * 3 + 1] + N[c * 3 + 1]) + fz * (N[a * 3 + 2] + N[b * 3 + 2] + N[c * 3 + 2]);
  }
  if (s < 0) for (let t = 0; t < I.length; t += 3) { const x = I[t + 1]; I[t + 1] = I[t + 2]; I[t + 2] = x; }
  return g;
}

/** Rolled rim tube: wear on the side facing the plate's outer normal. */
function rimTube(pts, nn, R, seg, closed) {
  const g = sweep(pts, circle(seg), { scale: R, closed, caps: !closed, up: nn[0] });
  // wear on top of the roll: compare normals with the (interpolated) plate normal
  const Nn = g.attributes.normal.array, C = g.attributes.cav.array, ring = seg + 1;
  for (let i = 0; i < C.length; i++) {
    const r = Math.min(nn.length - 1, Math.floor(i / ring));
    const q = nn[r] || nn[nn.length - 1];
    const d = Nn[i * 3] * q[0] + Nn[i * 3 + 1] * q[1] + Nn[i * 3 + 2] * q[2];
    C[i] = d > 0 ? 1 + 0.55 * d : 1 + d * 0.45;
  }
  return g;
}

// ---- sweep / lathe / extrude ------------------------------------------------------------------------------------------

/** Closed circle section with n segments (radius 1). */
export function circle(n = 8) { const out = []; for (let i = 0; i < n; i++) { const a = (i / n) * Math.PI * 2; out.push([Math.cos(a), Math.sin(a)]); } return out; }

/** Rounded rectangle section (half sizes w, h, corner radius r, corner segments cs). */
export function rrect(w, h, r = 0, cs = 2) {
  if (r <= 0) return [[w, h], [-w, h], [-w, -h], [w, -h]];
  const out = [], cor = [[w - r, h - r, 0], [-w + r, h - r, 90], [-w + r, -h + r, 180], [w - r, -h + r, 270]];
  for (const [cx, cy, a0] of cor) for (let k = 0; k <= cs; k++) { const a = ((a0 + (90 * k) / cs) * Math.PI) / 180; out.push([cx + Math.cos(a) * r, cy + Math.sin(a) * r]); }
  return out;
}

/** Diamond / lozenge section (half width w along x, half height h along y) with optional bevel b. */
export function lozenge(w, h) { return [[w, 0], [0, h], [-w, 0], [0, -h]]; }

/** Catmull-Rom resample of control points [[x,y,z]...] -> n+1 points (arrays). */
export function curve(ctrl, n = 16, closed = false) {
  const c = new THREE.CatmullRomCurve3(ctrl.map((p) => new V(p[0], p[1], p[2])), closed, 'centripetal');
  return c.getPoints(n).map((p) => [p.x, p.y, p.z]);
}

/**
 * Sweep a closed 2D section along a polyline.
 * @param {Array} path  [[x,y,z], ...]
 * @param {Array|function} section  [[x, y], ...] closed loop (x along the frame normal, y along the binormal), or fn(t)
 * @param {object} o  { scale = 1 | fn(t) -> number | [sx, sy], twist: fn(t) -> rad, up: [x,y,z] first normal hint,
 *                      closed = false (closed path), caps = true, hard: [section indices with hard normals],
 *                      cavScale = 0.004 }
 */
export function sweep(path, section, o = {}) {
  const pts = path.map((p) => (p.isVector3 ? p.clone() : new V(p[0], p[1], p[2])));
  const n = pts.length, closed = !!o.closed;
  const secAt = typeof section === 'function' ? section : () => section;
  // hard corners: duplicate section points
  const hard = new Set(o.hard || []);
  const expand = (sec) => { const out = []; sec.forEach((p, i) => { out.push(p); if (hard.has(i)) out.push(p); }); return out; };
  const S0 = expand(secAt(0)), m = S0.length;
  // frames (parallel transport)
  const T = [];
  for (let i = 0; i < n; i++) {
    let a = pts[Math.max(0, i - 1)], b = pts[Math.min(n - 1, i + 1)];
    if (closed) { a = pts[(i - 1 + n) % n]; b = pts[(i + 1) % n]; }
    const tt = new V().subVectors(b, a);
    if (tt.lengthSq() < 1e-14) tt.set(0, 1, 0);
    T.push(tt.normalize());
  }
  let nrm = o.up ? new V(...o.up) : new V(0, 1, 0);
  if (Math.abs(T[0].dot(nrm)) > 0.95) nrm = Math.abs(T[0].y) < 0.9 ? new V(0, 1, 0) : new V(1, 0, 0);
  nrm.addScaledVector(T[0], -T[0].dot(nrm)).normalize();
  const Nf = [], Bf = [];
  for (let i = 0; i < n; i++) {
    if (i > 0) {
      const q = new THREE.Quaternion().setFromUnitVectors(T[i - 1], T[i]);
      nrm = nrm.clone().applyQuaternion(q);
      nrm.addScaledVector(T[i], -T[i].dot(nrm)).normalize();
    }
    Nf.push(nrm.clone()); Bf.push(new V().crossVectors(T[i], nrm));
  }
  const scale = typeof o.scale === 'function' ? o.scale : () => o.scale ?? 1;
  const twist = o.twist || (() => 0);
  const pos = [], idx = [];
  const ring = m + 1;
  for (let i = 0; i < n; i++) {
    const t = n > 1 ? i / (n - 1) : 0;
    const sec = expand(secAt(t));
    let s = scale(t);
    const sx = Array.isArray(s) ? s[0] : s, sy = Array.isArray(s) ? s[1] : s;
    const tw = twist(t), ct = Math.cos(tw), st = Math.sin(tw);
    for (let k = 0; k <= m; k++) {
      const [x0, y0] = sec[k % m];
      const x = (x0 * ct - y0 * st) * sx, y = (x0 * st + y0 * ct) * sy;
      pos.push(pts[i].x + Nf[i].x * x + Bf[i].x * y, pts[i].y + Nf[i].y * x + Bf[i].y * y, pts[i].z + Nf[i].z * x + Bf[i].z * y);
    }
  }
  const segs = closed ? n : n - 1;
  for (let i = 0; i < segs; i++) {
    const i2 = (i + 1) % n;
    for (let k = 0; k < m; k++) {
      // skip the zero-width quad between duplicated hard corners
      const a = i * ring + k, b = a + 1, c = i2 * ring + k, d = c + 1;
      if (pos[a * 3] === pos[b * 3] && pos[a * 3 + 1] === pos[b * 3 + 1] && pos[a * 3 + 2] === pos[b * 3 + 2]) continue;
      idx.push(a, c, b, b, c, d);
    }
  }
  let g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setIndex(idx);
  g.computeVertexNormals();
  // weld the section seam (k = 0 and k = m) unless the first point is a hard corner
  const N = g.attributes.normal.array;
  if (!hard.has(0)) {
    for (let i = 0; i < n; i++) {
      const a = i * ring * 3, b = (i * ring + m) * 3;
      const x = N[a] + N[b], y = N[a + 1] + N[b + 1], z = N[a + 2] + N[b + 2], l = Math.hypot(x, y, z) || 1;
      N[a] = N[b] = x / l; N[a + 1] = N[b + 1] = y / l; N[a + 2] = N[b + 2] = z / l;
    }
  }
  if (closed) {
    for (let k = 0; k <= m; k++) {
      const a = k * 3, b = ((n - 1) * ring + k) * 3;
      if (a === b) continue;
    }
  }
  g = mk(pos, Array.from(N), idx);
  fixWinding(g);
  // outward check: section centroid -> vertex vs normal
  {
    const P = g.attributes.position.array, NN = g.attributes.normal.array;
    let s = 0;
    for (let i = 0; i < n; i++) for (let k = 0; k < m; k++) {
      const v = i * ring + k;
      s += (P[v * 3] - pts[i].x) * NN[v * 3] + (P[v * 3 + 1] - pts[i].y) * NN[v * 3 + 1] + (P[v * 3 + 2] - pts[i].z) * NN[v * 3 + 2];
    }
    if (s < 0) {
      for (let k = 0; k < NN.length; k++) NN[k] = -NN[k];
      fixWinding(g);
    }
  }
  autoCav(g, o.cavScale ?? 0.004);
  const parts = [g];
  if (!closed && o.caps !== false) {
    for (const [i, dir] of [[0, -1], [n - 1, 1]]) {
      const t = n > 1 ? i / (n - 1) : 0, s = scale(t);
      if ((Array.isArray(s) ? Math.min(s[0], s[1]) : s) < 1e-5) continue;
      const cp = [pts[i].x, pts[i].y, pts[i].z], cn = [T[i].x * dir, T[i].y * dir, T[i].z * dir], ci = [];
      for (let k = 0; k < m; k++) {
        const v = i * ring + k;
        cp.push(pos[v * 3], pos[v * 3 + 1], pos[v * 3 + 2]);
        cn.push(T[i].x * dir, T[i].y * dir, T[i].z * dir);
      }
      for (let k = 1; k <= m; k++) ci.push(0, k, (k % m) + 1);
      const cap = mk(cp, cn, ci, new Float32Array(m + 1).fill(1.05));
      fixWinding(cap);
      parts.push(cap);
    }
  }
  return parts.length > 1 ? merge(parts) : g;
}

/**
 * Surface of revolution around +Y. profile: [[r, y], ...] (any direction; outside faces away from the axis).
 * o: { segs = 16, a0 = 0, a1 = 360 (deg, 0 = +X), hard: [profile indices with hard normals], cavScale }
 */
export function lathe(profile, o = {}) {
  const segs = o.segs || 16, a0 = o.a0 ?? 0, a1 = o.a1 ?? 360;
  const hard = new Set(o.hard || []);
  const prof = [];
  profile.forEach((p, i) => { prof.push(p); if (hard.has(i)) prof.push(p); });
  const H = prof.length, W = segs + 1;
  // profile normals in (r, y): perpendicular of the tangent, pointing away from the axis
  const pn = [];
  for (let j = 0; j < H; j++) {
    const dup = j > 0 && prof[j] === prof[j - 1], dupN = j < H - 1 && prof[j] === prof[j + 1];
    const a = dup ? prof[j] : prof[Math.max(0, j - 1)], b = dupN ? prof[j] : prof[Math.min(H - 1, j + 1)];
    let tr = b[0] - a[0], ty = b[1] - a[1];
    if (dup && j > 0) { tr = prof[Math.min(H - 1, j + 1)][0] - prof[j][0]; ty = prof[Math.min(H - 1, j + 1)][1] - prof[j][1]; }
    if (dupN) { tr = prof[j][0] - prof[Math.max(0, j - 1)][0]; ty = prof[j][1] - prof[Math.max(0, j - 1)][1]; }
    let nr = ty, ny = -tr;
    const l = Math.hypot(nr, ny) || 1;
    pn.push([nr / l, ny / l]);
  }
  // orientation: outward = away from the axis on average
  let s = 0;
  for (let j = 0; j < H; j++) s += pn[j][0] * prof[j][0];
  const sg = s >= 0 ? 1 : -1;
  const pos = [], nor = [], idx = [];
  for (let j = 0; j < H; j++) {
    for (let i = 0; i < W; i++) {
      const a = ((a0 + ((a1 - a0) * i) / segs) * Math.PI) / 180, c = Math.cos(a), sn = Math.sin(a);
      const r = Math.max(0, prof[j][0]);
      pos.push(r * c, prof[j][1], r * sn);
      nor.push(pn[j][0] * sg * c, pn[j][1] * sg, pn[j][0] * sg * sn);
    }
  }
  for (let j = 0; j < H - 1; j++) {
    if (prof[j] === prof[j + 1]) continue;
    for (let i = 0; i < W - 1; i++) { const a = j * W + i, b = a + 1, d = a + W, c = d + 1; idx.push(a, d, b, b, d, c); }
  }
  const g = mk(pos, nor, idx);
  fixWinding(g);
  return autoCav(g, o.cavScale ?? 0.004);
}

/**
 * Bevelled extrusion of a 2D THREE.Shape (or [[x,y]...] outline) along +Z, centred on z = 0.
 * o: { depth = 0.01, bevel = 0.002 (size = thickness), bevelSegs = 2, curveSegs = 6, crease = 40 (deg), cavScale }
 */
export function extrude(shape, o = {}) {
  const sh = Array.isArray(shape) ? new THREE.Shape(shape.map(([x, y]) => new THREE.Vector2(x, y))) : shape;
  const depth = o.depth ?? 0.01, bv = o.bevel ?? 0.002;
  const eg = new THREE.ExtrudeGeometry(sh, {
    depth, steps: 1, curveSegments: o.curveSegs ?? 6,
    bevelEnabled: bv > 0, bevelThickness: o.bevelT ?? bv, bevelSize: bv, bevelOffset: -bv * 0.5, bevelSegments: o.bevelSegs ?? 2,
  });
  eg.translate(0, 0, -depth / 2);
  eg.deleteAttribute('uv');
  const g = creased(eg, o.crease ?? 40);
  eg.dispose();
  fixWinding(g);
  return autoCav(g, o.cavScale ?? 0.0035);
}

/**
 * Raised ribbon following a path on a parametric surface (engraved inlays, glowing runes, trim lines).
 * @param {object} surf  a plate() geometry (uses its userData.normalAt) or { normalAt(u, v) }
 * @param {Array} uv     [[u, v], ...] path in the surface's parameter space
 * @param {object} o     { width = 0.004, lift = 0.0008 (above the surface), bead = 0.0006 (crown height), smooth = 4 }
 */
export function strip(surf, uv, o = {}) {
  const w = (o.width ?? 0.004) / 2, lift = o.lift ?? 0.0008, bead = o.bead ?? 0.0006;
  // densify the uv path
  const dense = [];
  const sub = o.smooth ?? 4;
  for (let i = 0; i < uv.length - 1; i++) for (let s = 0; s < sub; s++) {
    const t = s / sub;
    dense.push([uv[i][0] + (uv[i + 1][0] - uv[i][0]) * t, uv[i][1] + (uv[i + 1][1] - uv[i][1]) * t]);
  }
  dense.push(uv[uv.length - 1]);
  const F = dense.map(([u, v]) => surf.normalAt(u, v));
  const pos = [], nor = [], idx = [], cav = [];
  const across = [-1, -0.5, 0, 0.5, 1];
  for (let i = 0; i < F.length; i++) {
    const a = F[Math.max(0, i - 1)].p, b = F[Math.min(F.length - 1, i + 1)].p;
    const tng = new V().subVectors(b, a).normalize();
    const nn = F[i].n;
    const side = new V().crossVectors(nn, tng).normalize();
    for (const x of across) {
      const h = lift + bead * (1 - x * x);
      const p = F[i].p.clone().addScaledVector(side, x * w).addScaledVector(nn, h);
      pos.push(p.x, p.y, p.z);
      const q = nn.clone().addScaledVector(side, x * 0.6).normalize();
      nor.push(q.x, q.y, q.z);
      cav.push(1 + 0.4 * (1 - x * x));
    }
  }
  const R = across.length;
  for (let i = 0; i < F.length - 1; i++) for (let k = 0; k < R - 1; k++) {
    const a = i * R + k, b = a + 1, c = a + R, d = c + 1;
    idx.push(a, c, b, b, c, d);
  }
  const g = mk(pos, nor, idx, cav);
  return fixWinding(g);
}

/**
 * Rivets / bosses: small domes at points with outward normals. list: [{ p: [x,y,z] | Vector3, n: [x,y,z] | Vector3 }]
 * o: { r = 0.006, h = 0.004 (height), segs = 6, flange = true }
 */
export function studs(list, o = {}) {
  const r = o.r ?? 0.006, hh = o.h ?? 0.004;
  const prof = o.flange === false
    ? [[r, -0.001], [r, 0], [r * 0.82, hh * 0.6], [r * 0.45, hh * 0.95], [0, hh]]
    : [[r * 1.15, -0.001], [r * 1.15, 0.0004], [r * 0.95, 0.0007], [r * 0.85, hh * 0.55], [r * 0.5, hh * 0.92], [0, hh]];
  const base = lathe(prof, { segs: o.segs ?? 7, hard: o.flange === false ? [1] : [2] });
  const up = new V(0, 1, 0), q = new THREE.Quaternion(), m = new THREE.Matrix4(), out = [];
  for (const s of list) {
    const p = s.p.isVector3 ? s.p : new V(...s.p), n = (s.n.isVector3 ? s.n.clone() : new V(...s.n)).normalize();
    q.setFromUnitVectors(up, n);
    m.compose(p, q, new V(s.s ?? 1, s.s ?? 1, s.s ?? 1));
    const g = base.clone();
    g.applyMatrix4(m);
    out.push(g);
  }
  return merge(out);
}

/** Points + normals at (u, v) parameter positions of a plate's surface (rivet rows along edges ...). */
export function onSurface(surf, uvs, inset = 0) {
  return uvs.map(([u, v]) => { const f = surf.normalAt(u, v); return { p: f.p.addScaledVector(f.n, inset), n: f.n }; });
}

// ---- kit placement ----------------------------------------------------------------------------------------------------

const lin = new THREE.Color();
function colorOf(c) {
  if (Array.isArray(c) || typeof c === 'function') return c;
  lin.set(c ?? 0x808080);
  return [lin.r, lin.g, lin.b];
}

/**
 * Kit options for a geometry + surface look. look: { color, rough, metal, set, amt, inlay, vein, eye, occ, tint(p) }
 * o: { at, rot, scale, glow: fn(p, n, i) -> [inlay, vein, eye] | [a,b,c], color: override, cav: fn(p, n, i) multiplier }
 */
export function kitOpts(geo, look, o = {}, mirror = false) {
  const cav = geo.attributes.cav ? geo.attributes.cav.array : null;
  const uvw = geo.attributes.uvw ? geo.attributes.uvw.array : null;
  const mp = (p) => (mirror ? [p[0], p[1], -p[2]] : p);
  const occ = look.occ ?? 1;
  const baseC = colorOf(o.color ?? look.color);
  const tint = o.tint || look.tint;
  const color = typeof baseC === 'function' ? (p, n, i) => baseC(mp(p), n, i)
    : tint ? (p, n, i) => { const k = tint(mp(p), n, i); return Array.isArray(k) ? [baseC[0] * k[0], baseC[1] * k[1], baseC[2] * k[2]] : [baseC[0] * k, baseC[1] * k, baseC[2] * k]; }
      : baseC;
  const cavFn = o.cav;
  const glowK = [look.inlay ?? 0, look.vein ?? 0, look.eye ?? 0];
  const glowFn = o.glow || look.glow;
  let glow;
  if (uvw) glow = (p, n, i) => [uvw[i * 3], uvw[i * 3 + 1], uvw[i * 3 + 2]];
  else if (glowFn) glow = (p, n, i) => glowFn(mp(p), n, i);
  else glow = glowK;
  return {
    at: o.at, rot: o.rot, scale: o.scale,
    color,
    rough: look.rough ?? 0.5, metal: look.metal ?? 0,
    detail: surfDetail(look.set ?? 0, look.amt ?? 1),
    cavity: (p, n, i) => {
      let c = cav ? cav[i] : 1;
      if (c <= 1) c *= occ; else c = 1 + (c - 1) * (look.wear ?? 1);
      if (cavFn) { const k = cavFn(mp(p), n, i); c = c > 1 ? 1 + (c - 1) * k : c * k; }
      return c;
    },
    glow,
  };
}

/** Add a rigid piece on one bone. */
export function put(kit, slot, bone, geo, look, o = {}) {
  kit.add(slot, bone, geo, kitOpts(geo, look, o));
  return geo;
}

/** Add a piece on base+'R' and its mirror image on base+'L' (per-vertex data preserved, unlike kit.addPair). */
export function putPair(kit, slot, base, geo, look, o = {}) {
  const g = xf(geo.clone(), o);
  const o2 = { ...o, at: undefined, rot: undefined, scale: undefined };
  kit.add(slot, base + 'R', g, kitOpts(g, look, o2));
  const gm = mirrorZ(g);
  kit.add(slot, base + 'L', gm, kitOpts(gm, look, o2, true));
  return g;
}

/** Add a piece skinned over several bones with per-vertex weights weightFn(x, y, z, i) (bind space) -> [[bone, w]...]. */
export function putSkinned(kit, slot, geo, look, weightFn, o = {}) {
  kit.addSkinned(slot, geo, weightFn, { ...kitOpts(geo, look, o), frame: o.frame });
  return geo;
}

/** Mirror a geometry across z (left-side copies built by hand). */
export function mirror(geo) { return mirrorZ(geo); }
