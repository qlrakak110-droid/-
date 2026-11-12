// Procedural geometry toolkit for the ruins: a merging builder (position / normal / uv / colour / glow) and the
// primitives the layout is made of (chamfered ashlar blocks, fluted column drums with broken tops, rocks, lathes).
// Everything is deterministic: pass an rng from makeRng().

import * as THREE from 'three';

const _v = new THREE.Vector3();
const _n = new THREE.Vector3();
const _m3 = new THREE.Matrix3();

/** Small deterministic 3D value noise for CPU-side displacement (same idea as the GLSL vnoise3). */
export function noise3(x, y, z) {
  const ix = Math.floor(x), iy = Math.floor(y), iz = Math.floor(z);
  const fx = x - ix, fy = y - iy, fz = z - iz;
  const ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy), uz = fz * fz * (3 - 2 * fz);
  const h = (a, b, c) => {
    let n = (a * 374761393 + b * 668265263 + c * 2147483647) | 0;
    n = Math.imul(n ^ (n >>> 13), 1274126177);
    return ((n ^ (n >>> 16)) >>> 0) / 4294967296;
  };
  const l = (a, b, t) => a + (b - a) * t;
  return l(
    l(l(h(ix, iy, iz), h(ix + 1, iy, iz), ux), l(h(ix, iy + 1, iz), h(ix + 1, iy + 1, iz), ux), uy),
    l(l(h(ix, iy, iz + 1), h(ix + 1, iy, iz + 1), ux), l(h(ix, iy + 1, iz + 1), h(ix + 1, iy + 1, iz + 1), ux), uy),
    uz,
  );
}
/** fbm of noise3, 0..1 */
export function fbm3(x, y, z, oct = 3) {
  let s = 0, a = 0.5, n = 0;
  for (let i = 0; i < oct; i++) { s += a * noise3(x, y, z); n += a; x = x * 2.03 + 11.7; y = y * 2.03 + 3.1; z = z * 2.03 + 7.3; a *= 0.5; }
  return s / n;
}

/**
 * Accumulates many geometries into one indexed BufferGeometry with attributes
 * position, normal, uv, color (rgb multiplier on albedo), glow (baked warm emissive amount).
 */
export class Builder {
  constructor() { this.pos = []; this.nrm = []; this.uv = []; this.col = []; this.glow = []; this.idx = []; }
  get vertexCount() { return this.pos.length / 3; }

  /**
   * Append a geometry transformed by `matrix`.
   * opts.color: [r,g,b] or fn(worldPos, worldNormal, out[3]) ; opts.glow: fn(worldPos) -> number
   * opts.uv: 'keep' | 'box' (world box projection, metres / opts.uvScale) ; opts.displace: fn(worldPos, worldNormal)
   */
  add(geo, matrix, opts = {}) {
    const p = geo.attributes.position, n = geo.attributes.normal, t = geo.attributes.uv;
    const base = this.vertexCount;
    _m3.getNormalMatrix(matrix);
    const color = opts.color || [1, 1, 1];
    const out = [1, 1, 1];
    const uvs = opts.uvScale || 2.5;
    const box = opts.uv === 'box' || !t;
    for (let i = 0; i < p.count; i++) {
      _v.fromBufferAttribute(p, i).applyMatrix4(matrix);
      _n.fromBufferAttribute(n, i).applyMatrix3(_m3).normalize();
      this.pos.push(_v.x, _v.y, _v.z);
      this.nrm.push(_n.x, _n.y, _n.z);
      if (box) {
        const ax = Math.abs(_n.x), ay = Math.abs(_n.y), az = Math.abs(_n.z);
        if (ay >= ax && ay >= az) this.uv.push(_v.x / uvs, _v.z / uvs);
        else if (ax >= az) this.uv.push(_v.z / uvs, _v.y / uvs);
        else this.uv.push(_v.x / uvs, _v.y / uvs);
      } else this.uv.push(t.getX(i) / uvs, t.getY(i) / uvs);
      if (typeof color === 'function') { color(_v, _n, out); this.col.push(out[0], out[1], out[2]); } else this.col.push(color[0], color[1], color[2]);
      this.glow.push(opts.glow ? opts.glow(_v) : 0);
    }
    if (geo.index) { const ix = geo.index.array; for (let i = 0; i < ix.length; i++) this.idx.push(base + ix[i]); }
    else for (let i = 0; i < p.count; i++) this.idx.push(base + i);
  }

  /** @returns {THREE.BufferGeometry} */
  build() {
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(this.pos, 3));
    g.setAttribute('normal', new THREE.Float32BufferAttribute(this.nrm, 3));
    g.setAttribute('uv', new THREE.Float32BufferAttribute(this.uv, 2));
    g.setAttribute('color', new THREE.Float32BufferAttribute(this.col, 3));
    g.setAttribute('glow', new THREE.Float32BufferAttribute(this.glow, 1));
    const n = this.vertexCount;
    g.setIndex(n > 65535 ? new THREE.Uint32BufferAttribute(this.idx, 1) : new THREE.Uint16BufferAttribute(this.idx, 1));
    g.computeBoundingSphere();
    g.computeBoundingBox();
    return g;
  }
}

/** Recompute per-face (flat) normals of a non-indexed geometry in place. */
export function flatNormals(geo) {
  const p = geo.attributes.position;
  const nrm = new Float32Array(p.count * 3);
  const a = new THREE.Vector3(), b = new THREE.Vector3(), c = new THREE.Vector3();
  for (let i = 0; i < p.count; i += 3) {
    a.fromBufferAttribute(p, i); b.fromBufferAttribute(p, i + 1); c.fromBufferAttribute(p, i + 2);
    b.sub(a); c.sub(a); b.cross(c).normalize();
    for (let k = 0; k < 3; k++) { nrm[(i + k) * 3] = b.x; nrm[(i + k) * 3 + 1] = b.y; nrm[(i + k) * 3 + 2] = b.z; }
  }
  geo.setAttribute('normal', new THREE.BufferAttribute(nrm, 3));
  return geo;
}

/** Displace every vertex of a geometry by fn(pos) -> Vector3 offset (applied in local space). */
export function displace(geo, fn) {
  const p = geo.attributes.position;
  for (let i = 0; i < p.count; i++) {
    _v.fromBufferAttribute(p, i);
    const d = fn(_v);
    p.setXYZ(i, _v.x + d.x, _v.y + d.y, _v.z + d.z);
  }
  p.needsUpdate = true;
  return geo;
}

/**
 * Chamfered box centred at the origin (flat shaded, 44 triangles). `chip` (0..1) knocks corners in irregularly.
 * @returns {THREE.BufferGeometry} non-indexed
 */
export function chamferBox(w, h, d, bevel = 0.04, rng = null, chip = 0) {
  const hx = w / 2, hy = h / 2, hz = d / 2;
  const b = Math.min(bevel, hx * 0.45, hy * 0.45, hz * 0.45);
  // corner c (sx,sy,sz) has three vertices, one per adjacent face axis
  const corner = {};
  const off = [];
  for (let i = 0; i < 8; i++) {
    const s = [i & 1 ? 1 : -1, i & 2 ? 1 : -1, i & 4 ? 1 : -1];
    let k = 0;
    if (rng && chip > 0 && rng() < chip) k = rng.range(0.4, 1.0);
    off.push(k);
    const cb = b + k * Math.min(hx, hy, hz) * 0.45;
    const v = (ax) => {
      const p = [s[0] * hx, s[1] * hy, s[2] * hz];
      for (let a = 0; a < 3; a++) if (a !== ax) p[a] -= s[a] * cb;
      return p;
    };
    corner[i] = [v(0), v(1), v(2)];
  }
  const out = [];
  const tri = (a, b2, c) => out.push(...a, ...b2, ...c);
  const quad = (a, b2, c, d2) => { tri(a, b2, c); tri(a, c, d2); };
  const ci = (sx, sy, sz) => (sx > 0 ? 1 : 0) | (sy > 0 ? 2 : 0) | (sz > 0 ? 4 : 0);
  // main faces
  for (let ax = 0; ax < 3; ax++) for (const sg of [-1, 1]) {
    const u = (ax + 1) % 3, v = (ax + 2) % 3;
    const pick = (su, sv) => { const s = [0, 0, 0]; s[ax] = sg; s[u] = su; s[v] = sv; return corner[ci(s[0], s[1], s[2])][ax]; };
    const a = pick(-1, -1), b2 = pick(1, -1), c = pick(1, 1), d2 = pick(-1, 1);
    if (sg > 0) quad(a, b2, c, d2); else quad(a, d2, c, b2);
  }
  // edge bevels (between faces ax and ay along the remaining axis)
  for (let ax = 0; ax < 3; ax++) for (let ay = ax + 1; ay < 3; ay++) {
    const az = 3 - ax - ay;
    for (const sx of [-1, 1]) for (const sy of [-1, 1]) {
      const pick = (sz, f) => { const s = [0, 0, 0]; s[ax] = sx; s[ay] = sy; s[az] = sz; return corner[ci(s[0], s[1], s[2])][f]; };
      const a = pick(-1, ax), b2 = pick(1, ax), c = pick(1, ay), d2 = pick(-1, ay);
      // orientation: outward normal along (sx on ax, sy on ay)
      const nrm = [0, 0, 0]; nrm[ax] = sx; nrm[ay] = sy;
      const e1 = [b2[0] - a[0], b2[1] - a[1], b2[2] - a[2]], e2 = [c[0] - a[0], c[1] - a[1], c[2] - a[2]];
      const cr = [e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]];
      if (cr[0] * nrm[0] + cr[1] * nrm[1] + cr[2] * nrm[2] > 0) quad(a, b2, c, d2); else quad(a, d2, c, b2);
    }
  }
  // corner triangles
  for (let i = 0; i < 8; i++) {
    const s = [i & 1 ? 1 : -1, i & 2 ? 1 : -1, i & 4 ? 1 : -1];
    const [a, b2, c] = corner[i];
    const e1 = [b2[0] - a[0], b2[1] - a[1], b2[2] - a[2]], e2 = [c[0] - a[0], c[1] - a[1], c[2] - a[2]];
    const cr = [e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]];
    if (cr[0] * s[0] + cr[1] * s[1] + cr[2] * s[2] > 0) tri(a, b2, c); else tri(a, c, b2);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(out, 3));
  return flatNormals(g);
}

/**
 * Lathe-like grid around Y: profile(t) -> [radius, y] for t in 0..1 (rows), radial modulation rmod(phi, y) multiplier.
 * Smooth normals. Optional top cap (fan) and bottom cap.
 * @returns {THREE.BufferGeometry} indexed
 */
export function latheGrid({ rows, segs, profile, rmod = null, capTop = false, capBottom = false, topY = null, squash = 1 }) {
  const pos = [], uv = [], idx = [];
  for (let j = 0; j <= rows; j++) {
    const [r, y] = profile(j / rows);
    for (let i = 0; i <= segs; i++) {
      const phi = (i / segs) * Math.PI * 2;
      const m = rmod ? rmod(phi, y, j) : 1;
      let yy = y;
      if (topY && j === rows) yy = topY(phi);
      pos.push(Math.cos(phi) * r * m, yy, Math.sin(phi) * r * m * squash);
      uv.push((phi * Math.max(r, 0.3)), yy);
    }
  }
  for (let j = 0; j < rows; j++) for (let i = 0; i < segs; i++) {
    const a = j * (segs + 1) + i, b = a + 1, c = a + segs + 1, d = c + 1;
    idx.push(a, c, b, b, c, d);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  g.setIndex(idx);
  g.computeVertexNormals();
  // the seam column is duplicated: average its normals so the lathe has no visible seam
  const n = g.attributes.normal;
  for (let j = 0; j <= rows; j++) {
    const a = j * (segs + 1), b = a + segs;
    const x = (n.getX(a) + n.getX(b)) / 2, y = (n.getY(a) + n.getY(b)) / 2, z = (n.getZ(a) + n.getZ(b)) / 2;
    const l = Math.hypot(x, y, z) || 1;
    n.setXYZ(a, x / l, y / l, z / l); n.setXYZ(b, x / l, y / l, z / l);
  }
  const parts = [g];
  if (capTop || capBottom) {
    for (const top of [true, false]) {
      if (top ? !capTop : !capBottom) continue;
      const j = top ? rows : 0;
      const y = profile(j / rows)[1];
      const cap = [];
      const cy = top && typeof capTop === 'number' ? capTop : y;
      for (let i = 0; i < segs; i++) {
        const a = j * (segs + 1) + i;
        const ax = pos[a * 3], ay = pos[a * 3 + 1], az = pos[a * 3 + 2];
        const bx = pos[(a + 1) * 3], by = pos[(a + 1) * 3 + 1], bz = pos[(a + 1) * 3 + 2];
        if (top) cap.push(0, cy, 0, bx, by, bz, ax, ay, az); else cap.push(0, cy, 0, ax, ay, az, bx, by, bz);
      }
      const cg = new THREE.BufferGeometry();
      cg.setAttribute('position', new THREE.Float32BufferAttribute(cap, 3));
      flatNormals(cg);
      parts.push(cg);
    }
  }
  return parts;
}

/**
 * Rough rock: displaced icosahedron, flat shaded.
 * @returns {THREE.BufferGeometry} non-indexed
 */
export function rock(radius, rng, { detail = 1, squash = 0.7, rough = 0.35 } = {}) {
  const g = new THREE.IcosahedronGeometry(radius, detail);
  const s = rng.range(0, 100);
  const sx = rng.range(0.8, 1.3), sz = rng.range(0.8, 1.3);
  const d = new THREE.Vector3();
  displace(g, (p) => {
    const k = 1 + (fbm3(p.x / radius * 1.3 + s, p.y / radius * 1.3, p.z / radius * 1.3, 2) - 0.5) * 2 * rough;
    return d.set(p.x * (k * sx - 1), p.y * (k * squash - 1), p.z * (k * sz - 1));
  });
  return flatNormals(g.index ? g.toNonIndexed() : g);
}

/** Merge non-indexed or indexed parts into one Builder with the same transform/opts. */
export function addAll(builder, parts, matrix, opts) {
  for (const p of parts) builder.add(p, matrix, opts);
}

/** Compose a matrix from position, Y rotation (and optional X/Z tilt) and uniform/non-uniform scale. */
export function trs(x, y, z, ry = 0, rx = 0, rz = 0, sx = 1, sy = sx, sz = sx) {
  const m = new THREE.Matrix4();
  m.compose(new THREE.Vector3(x, y, z), new THREE.Quaternion().setFromEuler(new THREE.Euler(rx, ry, rz, 'YXZ')), new THREE.Vector3(sx, sy, sz));
  return m;
}
