// Procedural modelling primitives for armour, weapons and props. Every function returns an indexed BufferGeometry with
// `position` and `normal` (no uv: the kit material uses triplanar detail). Units are metres; pieces are authored in a
// bone's local frame (zero pose: +X forward, +Y up, +Z toward the camera / fighter's right).
//
// Values documented as "curve" accept: a number, an array of [v, value] control points (v in 0..1, Catmull-Rom
// interpolated) or a function f(v).

import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/examples/jsm/geometries/RoundedBoxGeometry.js';
import { DEG, lerp } from '../core/math.js';

/** Smooth curve through [[v, value], ...] control points (Catmull-Rom, clamped at the ends). */
export function profile(points) {
  const n = points.length;
  if (n === 1) return () => points[0][1];
  return (v) => {
    if (v <= points[0][0]) return points[0][1];
    if (v >= points[n - 1][0]) return points[n - 1][1];
    let i = 0;
    while (i < n - 2 && points[i + 1][0] < v) i++;
    const [t0, p0] = points[i], [t1, p1] = points[i + 1];
    const m = (k) => {
      if (k <= 0 || k >= n - 1) return 0;
      return (points[k + 1][1] - points[k - 1][1]) / (points[k + 1][0] - points[k - 1][0]);
    };
    const dt = t1 - t0, u = (v - t0) / dt, u2 = u * u, u3 = u2 * u;
    return (2 * u3 - 3 * u2 + 1) * p0 + (u3 - 2 * u2 + u) * dt * m(i) + (-2 * u3 + 3 * u2) * p1 + (u3 - u2) * dt * m(i + 1);
  };
}

/** Resolve a "curve" option into a function of v. */
export function fnOf(x, def = 0) {
  if (typeof x === 'function') return x;
  if (Array.isArray(x)) return profile(x);
  const c = x ?? def;
  return () => c;
}

function makeGeo(pos, nrm, idx) {
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  if (nrm) g.setAttribute('normal', new THREE.Float32BufferAttribute(nrm, 3));
  g.setIndex(idx);
  if (!nrm) g.computeVertexNormals();
  return g;
}

function gridIndex(W, H, flip) {
  const idx = [];
  for (let j = 0; j < H - 1; j++) for (let i = 0; i < W - 1; i++) {
    const a = j * W + i, b = a + 1, c = a + W + 1, d = a + W;
    if (flip) idx.push(a, d, b, b, d, c); else idx.push(a, b, d, b, c, d);
  }
  return idx;
}

/**
 * Curved armour plate: a superellipse tube section swept along local Y with real thickness and optional rolled rims.
 * @param {object} o
 *   y0=0, y1=-0.3     span along Y (v = 0 at y0, 1 at y1)
 *   rx, rz            radius toward +-X / +-Z (curve over v)          ox, oz  centre offset (curve)
 *   n=2               superellipse exponent (curve; 2 ellipse, 3-5 boxier)
 *   a0=0, a1=360      angular coverage in degrees (curve): 0 = +X front, 90 = +Z, 180 = back, 270 = -Z
 *   bulge(u, v)       extra radius factor (fn)      ridge {at: deg, w: deg, h: m}   medial ridge
 *   thick=0.006       inward thickness               rim: bead radius (0 = none), rimEdges: 'tbs' (top/bottom/sides)
 *   segs=[24, 10]     radial, ring segments
 */
export function shell(o = {}) {
  const radial = (o.segs && o.segs[0]) || 24, rings = (o.segs && o.segs[1]) || 10;
  const y0 = o.y0 ?? 0, y1 = o.y1 ?? -0.3;
  const RX = fnOf(o.rx, 0.1), RZ = fnOf(o.rz ?? o.rx, 0.1), OX = fnOf(o.ox, 0), OZ = fnOf(o.oz, 0), NE = fnOf(o.n, 2);
  const A0 = fnOf(o.a0, 0), A1 = fnOf(o.a1, 360);
  const thick = o.thick ?? 0.006;
  const W = radial + 1, H = rings + 1;
  const closed = Math.abs(A1(0.5) - A0(0.5)) >= 359.9;
  const P = new Float32Array(W * H * 3);
  for (let j = 0; j < H; j++) {
    const v = j / rings, y = lerp(y0, y1, v);
    const rx = RX(v), rz = RZ(v), ox = OX(v), oz = OZ(v), e = 2 / NE(v), a0 = A0(v), a1 = A1(v);
    for (let i = 0; i < W; i++) {
      const u = i / radial, th = lerp(a0, a1, u) * DEG;
      const c = Math.cos(th), s = Math.sin(th);
      const ex = Math.sign(c) * Math.pow(Math.abs(c), e), ez = Math.sign(s) * Math.pow(Math.abs(s), e);
      let k = 1 + (o.bulge ? o.bulge(u, v) : 0);
      if (o.ridge) {
        let d = Math.abs(((lerp(a0, a1, u) - o.ridge.at + 540) % 360) - 180);
        const r = Math.max(0, 1 - (d / o.ridge.w) ** 2);
        k += (o.ridge.h * r * r) / Math.max(1e-3, Math.hypot(rx * ex, rz * ez));
      }
      const p = (j * W + i) * 3;
      P[p] = ox + rx * ex * k; P[p + 1] = y; P[p + 2] = oz + rz * ez * k;
    }
  }
  // outer surface
  let outer = makeGeo(P, null, gridIndex(W, H, false));
  // make sure normals face away from the axis
  {
    const N = outer.attributes.normal.array;
    let dot = 0;
    for (let j = 0; j < H; j++) for (let i = 0; i < W; i++) {
      const p = (j * W + i) * 3, v = j / rings;
      dot += (P[p] - OX(v)) * N[p] + (P[p + 2] - OZ(v)) * N[p + 2];
    }
    if (dot < 0) outer = makeGeo(P, null, gridIndex(W, H, true));
  }
  const N = outer.attributes.normal.array;
  if (closed) { // weld seam normals
    for (let j = 0; j < H; j++) {
      const a = j * W * 3, b = (j * W + W - 1) * 3;
      const nx = N[a] + N[b], ny = N[a + 1] + N[b + 1], nz = N[a + 2] + N[b + 2], l = Math.hypot(nx, ny, nz) || 1;
      N[a] = N[b] = nx / l; N[a + 1] = N[b + 1] = ny / l; N[a + 2] = N[b + 2] = nz / l;
    }
  }
  const flipped = outer.index.array[1] !== 1;
  const parts = [outer];
  if (thick > 0) {
    const PI = new Float32Array(P.length), NI = new Float32Array(P.length);
    for (let k = 0; k < P.length; k++) { PI[k] = P[k] - N[k] * thick; NI[k] = -N[k]; }
    parts.push(makeGeo(PI, NI, gridIndex(W, H, !flipped)));
    // thin side strips joining outer and inner borders
    const strip = (ids) => {
      const pos = [];
      for (const id of ids) pos.push(P[id * 3], P[id * 3 + 1], P[id * 3 + 2]);
      for (const id of ids) pos.push(PI[id * 3], PI[id * 3 + 1], PI[id * 3 + 2]);
      return pos;
    };
    const borders = [];
    borders.push([...Array(W).keys()]);                          // top (v=0)
    borders.push([...Array(W).keys()].map((i) => (H - 1) * W + i).reverse()); // bottom
    if (!closed) {
      borders.push([...Array(H).keys()].map((j) => j * W).reverse());      // a0 side
      borders.push([...Array(H).keys()].map((j) => j * W + W - 1));        // a1 side
    }
    for (const [bi, b] of borders.entries()) {
      const pos = strip(b), L = b.length, idx = [];
      for (let i = 0; i < L - 1; i++) {
        const a = i, c = i + 1, d = L + i, e = L + i + 1;
        idx.push(a, c, d, c, e, d);
      }
      let g = makeGeo(pos, null, idx);
      // orient: the strip normal must point away from the plate body
      const m = b[Math.floor(L / 2)];
      const inner = bi === 0 ? m + W : bi === 1 ? m - W : bi === 2 ? m + 1 : m - 1;
      const gn = g.attributes.normal.array, k = Math.floor(L / 2) * 3;
      const dx = P[m * 3] - P[inner * 3], dy = P[m * 3 + 1] - P[inner * 3 + 1], dz = P[m * 3 + 2] - P[inner * 3 + 2];
      if (gn[k] * dx + gn[k + 1] * dy + gn[k + 2] * dz < 0) { flipWinding(g); g.computeVertexNormals(); }
      parts.push(g);
    }
  }
  if (o.rim) {
    const edges = o.rimEdges || 'tbs';
    const take = (ids) => ids.map((id) => new THREE.Vector3(P[id * 3] - N[id * 3] * thick * 0.5, P[id * 3 + 1] - N[id * 3 + 1] * thick * 0.5, P[id * 3 + 2] - N[id * 3 + 2] * thick * 0.5));
    const rr = Math.max(o.rim, thick * 0.7);
    if (edges.includes('t')) parts.push(tube(take([...Array(W).keys()]), rr, 6, { closed }));
    if (edges.includes('b')) parts.push(tube(take([...Array(W).keys()].map((i) => (H - 1) * W + i)), rr, 6, { closed }));
    if (edges.includes('s') && !closed) {
      parts.push(tube(take([...Array(H).keys()].map((j) => j * W)), rr, 6));
      parts.push(tube(take([...Array(H).keys()].map((j) => j * W + W - 1)), rr, 6));
    }
  }
  return merge(parts);
}

/**
 * Tube along a polyline (parallel-transport frames, capped ends).
 * @param {THREE.Vector3[]} pts
 * @param {number|function} radius  number or fn(v) along the length
 * @param {number} seg  radial segments
 * @param {object} o  { closed=false, caps=true, scaleZ=1 (elliptic cross-section along the binormal) }
 */
export function tube(pts, radius, seg = 8, o = {}) {
  const R = fnOf(radius, 0.01);
  const n = pts.length, closed = !!o.closed;
  const T = [], Nn = [], B = [];
  for (let i = 0; i < n; i++) {
    const a = pts[Math.max(0, i - 1)], b = pts[Math.min(n - 1, i + 1)];
    let t = new THREE.Vector3().subVectors(closed && i === 0 ? pts[1] : b, closed && i === 0 ? pts[n - 2] : a);
    if (closed && i === n - 1) t.subVectors(pts[1], pts[n - 2]);
    if (t.lengthSq() < 1e-12) t.set(0, 1, 0);
    T.push(t.normalize());
  }
  let nrm = new THREE.Vector3(0, 1, 0);
  if (Math.abs(T[0].dot(nrm)) > 0.9) nrm.set(1, 0, 0);
  nrm.sub(T[0].clone().multiplyScalar(T[0].dot(nrm))).normalize();
  for (let i = 0; i < n; i++) {
    if (i > 0) {
      const q = new THREE.Quaternion().setFromUnitVectors(T[i - 1], T[i]);
      nrm = nrm.clone().applyQuaternion(q);
      nrm.sub(T[i].clone().multiplyScalar(T[i].dot(nrm))).normalize();
    }
    Nn.push(nrm.clone());
    B.push(new THREE.Vector3().crossVectors(T[i], nrm));
  }
  const pos = [], nor = [], idx = [];
  const sz = o.scaleZ ?? 1;
  for (let i = 0; i < n; i++) {
    const r = R(n > 1 ? i / (n - 1) : 0);
    for (let k = 0; k <= seg; k++) {
      const a = (k / seg) * Math.PI * 2, c = Math.cos(a), s = Math.sin(a);
      const dx = Nn[i].x * c + B[i].x * s * sz, dy = Nn[i].y * c + B[i].y * s * sz, dz = Nn[i].z * c + B[i].z * s * sz;
      pos.push(pts[i].x + dx * r, pts[i].y + dy * r, pts[i].z + dz * r);
      const ln = Math.hypot(Nn[i].x * c * sz + B[i].x * s, Nn[i].y * c * sz + B[i].y * s, Nn[i].z * c * sz + B[i].z * s) || 1;
      nor.push((Nn[i].x * c * sz + B[i].x * s) / ln, (Nn[i].y * c * sz + B[i].y * s) / ln, (Nn[i].z * c * sz + B[i].z * s) / ln);
    }
  }
  const W = seg + 1;
  for (let i = 0; i < n - 1; i++) for (let k = 0; k < seg; k++) {
    const a = i * W + k, b = a + 1, c = a + W, d = c + 1;
    idx.push(a, c, b, b, c, d);
  }
  const g = makeGeo(pos, nor, idx);
  if (closed || o.caps === false) return g;
  const caps = [];
  for (const [i, dir] of [[0, -1], [n - 1, 1]]) {
    const r = R(i / Math.max(1, n - 1));
    if (r < 1e-5) continue;
    const cp = [pts[i].x, pts[i].y, pts[i].z], cn = [T[i].x * dir, T[i].y * dir, T[i].z * dir], ci = [];
    for (let k = 0; k <= seg; k++) {
      const a = (k / seg) * Math.PI * 2, c = Math.cos(a), s = Math.sin(a);
      cp.push(pts[i].x + (Nn[i].x * c + B[i].x * s * sz) * r, pts[i].y + (Nn[i].y * c + B[i].y * s * sz) * r, pts[i].z + (Nn[i].z * c + B[i].z * s * sz) * r);
      cn.push(T[i].x * dir, T[i].y * dir, T[i].z * dir);
    }
    for (let k = 1; k <= seg; k++) { if (dir > 0) ci.push(0, k, k + 1); else ci.push(0, k + 1, k); }
    caps.push(makeGeo(cp, cn, ci));
  }
  return merge([g, ...caps]);
}

/**
 * Surface of revolution around local Y. profile: [[r, y], ...] from bottom to top (or any order; the outside is to
 * the right of the walking direction). o: { segs=24, a0=0, a1=360 (degrees, 0 = +X) }
 */
export function lathe(points, o = {}) {
  const segs = o.segs || 24, a0 = o.a0 ?? 0, a1 = o.a1 ?? 360;
  const closed = Math.abs(a1 - a0) >= 359.9;
  const W = segs + 1, H = points.length, pos = new Float32Array(W * H * 3);
  for (let j = 0; j < H; j++) {
    const [r, y] = points[j];
    for (let i = 0; i < W; i++) {
      const a = lerp(a0, a1, i / segs) * DEG, p = (j * W + i) * 3;
      pos[p] = Math.max(0, r) * Math.cos(a); pos[p + 1] = y; pos[p + 2] = Math.max(0, r) * Math.sin(a);
    }
  }
  let g = makeGeo(pos, null, gridIndex(W, H, false));
  let dot = 0;
  const N = g.attributes.normal.array;
  for (let k = 0; k < pos.length; k += 3) dot += pos[k] * N[k] + pos[k + 2] * N[k + 2];
  if (dot < 0) g = makeGeo(pos, null, gridIndex(W, H, true));
  if (closed) {
    const n = g.attributes.normal.array;
    for (let j = 0; j < H; j++) {
      const a = j * W * 3, b = (j * W + W - 1) * 3;
      const nx = n[a] + n[b], ny = n[a + 1] + n[b + 1], nz = n[a + 2] + n[b + 2], l = Math.hypot(nx, ny, nz) || 1;
      n[a] = n[b] = nx / l; n[a + 1] = n[b + 1] = ny / l; n[a + 2] = n[b + 2] = nz / l;
    }
  }
  return g;
}

/** Rounded box centred at the origin. */
export function box(w, h, d, radius = 0.004, seg = 2) {
  if (radius <= 0) return clean(new THREE.BoxGeometry(w, h, d));
  return clean(new RoundedBoxGeometry(w, h, d, seg, Math.min(radius, Math.min(w, h, d) * 0.49)));
}

export function sphere(r, ws = 12, hs = 8, o = {}) {
  return clean(new THREE.SphereGeometry(r, ws, hs, o.phi0 ?? 0, o.phiLen ?? Math.PI * 2, o.theta0 ?? 0, o.thetaLen ?? Math.PI));
}

export function cylinder(rTop, rBot, h, seg = 12, open = false) {
  return clean(new THREE.CylinderGeometry(rTop, rBot, h, seg, 1, open));
}

/**
 * Blade lofted along +X. o: { length, width: curve (half width, v 0 base .. 1 tip), thick: curve (half thickness at the
 * spine), edge = 0.006 (bevel width at the edges), fuller: { from, to, w (half), depth } (v range), sections = 24,
 * back: if true, single-edged (the +Y side is a flat spine) }
 */
export function blade(o) {
  const L = o.length, S = o.sections || 24;
  const Wf = fnOf(o.width, 0.03), Tf = fnOf(o.thick, 0.004), edge = o.edge ?? 0.008;
  const fl = o.fuller;
  // cross-section corner list (y, z) for half-width w, half-thickness t, at v
  const section = (v) => {
    const w = Wf(v), t = Tf(v), e = Math.min(edge, w * 0.6);
    const pts = [];
    const fullerOn = fl && v >= fl.from && v <= fl.to;
    let fw = 0, fd = 0;
    if (fullerOn) {
      const k = Math.min(1, Math.min(v - fl.from, fl.to - v) / 0.04);
      fw = Math.min(fl.w, (w - e) * 0.7); fd = fl.depth * k;
    }
    const top = o.back ? [[w, t * 0.9], [w, -t * 0.9]] : [[w, 0]];
    // walk around: top edge -> +Z face -> bottom edge -> -Z face
    for (const p of top) pts.push(p);
    pts.push([w - e, t]);
    if (fullerOn) { pts.push([fw, t]); pts.push([fw * 0.6, t - fd]); pts.push([-fw * 0.6, t - fd]); pts.push([-fw, t]); }
    pts.push([-(w - e), t]);
    pts.push([-w, 0]);
    pts.push([-(w - e), -t]);
    if (fullerOn) { pts.push([-fw, -t]); pts.push([-fw * 0.6, -t + fd]); pts.push([fw * 0.6, -t + fd]); pts.push([fw, -t]); }
    pts.push([w - e, -t]);
    return pts;
  };
  // fuller changes vertex count; build each facet strip between consecutive corners with a fixed facet table
  const K = section(0.5).length;
  const resample = (v) => {
    const s = section(v);
    if (s.length === K) return s;
    // no fuller here: collapse fuller corners onto the face
    const base = section(v), out = [];
    const t = Tf(v), w = Wf(v), e = Math.min(edge, w * 0.6);
    const top = o.back ? 2 : 1;
    for (let i = 0; i < top; i++) out.push(base[i]);
    out.push([w - e, t]);
    for (let i = 0; i < 4; i++) out.push([lerp(w - e, -(w - e), (i + 1) / 5), t]);
    out.push([-(w - e), t]); out.push([-w, 0]); out.push([-(w - e), -t]);
    for (let i = 0; i < 4; i++) out.push([lerp(-(w - e), w - e, (i + 1) / 5), -t]);
    out.push([w - e, -t]);
    return out;
  };
  const rings = [];
  for (let j = 0; j <= S; j++) { const v = j / S; rings.push({ x: v * L, s: resample(v) }); }
  const parts = [];
  for (let k = 0; k < K; k++) {
    const k2 = (k + 1) % K, pos = [], idx = [];
    for (let j = 0; j <= S; j++) {
      const r = rings[j];
      pos.push(r.x, r.s[k][0], r.s[k][1], r.x, r.s[k2][0], r.s[k2][1]);
    }
    for (let j = 0; j < S; j++) { const a = j * 2; idx.push(a, a + 1, a + 2, a + 1, a + 3, a + 2); }
    parts.push(makeGeo(pos, null, idx));
  }
  // base cap
  const base = rings[0].s, cp = [0, 0, 0], ci = [];
  for (const p of base) cp.push(0, p[0], p[1]);
  for (let k = 0; k < K; k++) ci.push(0, 1 + ((k + 1) % K), 1 + k);
  parts.push(makeGeo(cp, null, ci));
  return merge(parts);
}

/** Drop uv / extra attributes and make indexed. */
export function clean(g) {
  if (!g.index) {
    const n = g.attributes.position.count, idx = [];
    for (let i = 0; i < n; i++) idx.push(i);
    g.setIndex(idx);
  }
  for (const k of Object.keys(g.attributes)) if (k !== 'position' && k !== 'normal') g.deleteAttribute(k);
  if (!g.attributes.normal) g.computeVertexNormals();
  return g;
}

/** Concatenate indexed position/normal geometries (inputs are not modified). Keeps per-vertex extra attributes listed in `keep`. */
export function merge(geos, keep = []) {
  let nv = 0, ni = 0;
  for (const g of geos) { nv += g.attributes.position.count; ni += g.index ? g.index.count : g.attributes.position.count; }
  const pos = new Float32Array(nv * 3), nor = new Float32Array(nv * 3), idx = new Uint32Array(ni);
  const extra = keep.map((k) => ({ k, size: geos[0].attributes[k].itemSize, arr: new Float32Array(nv * geos[0].attributes[k].itemSize) }));
  let vo = 0, io = 0;
  for (const g of geos) {
    const c = g.attributes.position.count;
    pos.set(g.attributes.position.array.subarray(0, c * 3), vo * 3);
    if (g.attributes.normal) nor.set(g.attributes.normal.array.subarray(0, c * 3), vo * 3);
    for (const e of extra) e.arr.set(g.attributes[e.k].array.subarray(0, c * e.size), vo * e.size);
    if (g.index) { const a = g.index.array; for (let i = 0; i < a.length; i++) idx[io + i] = a[i] + vo; io += a.length; }
    else { for (let i = 0; i < c; i++) idx[io + i] = vo + i; io += c; }
    vo += c;
  }
  const out = new THREE.BufferGeometry();
  out.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  out.setAttribute('normal', new THREE.BufferAttribute(nor, 3));
  for (const e of extra) out.setAttribute(e.k, new THREE.BufferAttribute(e.arr, e.size));
  out.setIndex(new THREE.BufferAttribute(idx, 1));
  return out;
}

const _m = new THREE.Matrix4(), _q = new THREE.Quaternion(), _e = new THREE.Euler(0, 0, 0, 'ZXY'), _s = new THREE.Vector3(), _p = new THREE.Vector3();

/** Transform a geometry in place: { at:[x,y,z], rot:[x,y,z] degrees (order ZXY), scale: number|[x,y,z] }. Returns it. */
export function xf(g, o = {}) {
  _e.set(((o.rot && o.rot[0]) || 0) * DEG, ((o.rot && o.rot[1]) || 0) * DEG, ((o.rot && o.rot[2]) || 0) * DEG, 'ZXY');
  _q.setFromEuler(_e);
  const s = o.scale ?? 1;
  if (Array.isArray(s)) _s.set(s[0], s[1], s[2]); else _s.set(s, s, s);
  _p.set(...(o.at || [0, 0, 0]));
  _m.compose(_p, _q, _s);
  g.applyMatrix4(_m);
  if (_m.determinant() < 0) flipWinding(g);
  return g;
}

/** Mirror across the XY plane (z -> -z): builds the left-side copy of a right-side piece. Returns a new geometry. */
export function mirrorZ(g) {
  const c = g.clone();
  const p = c.attributes.position.array, n = c.attributes.normal.array;
  for (let i = 2; i < p.length; i += 3) { p[i] = -p[i]; n[i] = -n[i]; }
  flipWinding(c);
  return c;
}

export function flipWinding(g) {
  const a = g.index.array;
  for (let i = 0; i < a.length; i += 3) { const t = a[i + 1]; a[i + 1] = a[i + 2]; a[i + 2] = t; }
  g.index.needsUpdate = true;
  return g;
}

/** Points along a quadratic/cubic Bezier or Catmull-Rom path: pts [[x,y,z]...] -> n Vector3 samples. */
export function path(pts, n = 16) {
  const curve = new THREE.CatmullRomCurve3(pts.map((p) => new THREE.Vector3(...p)), false, 'centripetal');
  return curve.getPoints(n);
}
