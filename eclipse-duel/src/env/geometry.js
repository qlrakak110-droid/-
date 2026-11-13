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
 * position, normal, uv, color (rgb multiplier on albedo), glow (baked warm emissive amount)
 * and, with `new Builder({ orn: true })`, orn (vec4: relief-cell u, v, cell index, relief amount; see ornament.js).
 */
export class Builder {
  constructor({ orn = false } = {}) {
    this.pos = []; this.nrm = []; this.uv = []; this.col = []; this.glow = []; this.idx = [];
    this.orn = orn ? [] : null;
    this.tris = {};
    this._section = 'misc';
  }
  get vertexCount() { return this.pos.length / 3; }
  /** Name the part being added (triangle accounting per section, see `tris`). */
  section(name) { this._section = name; return this; }

  /**
   * Append a geometry transformed by `matrix`.
   * opts.color: [r,g,b] or fn(worldPos, worldNormal, out[3]) ; opts.glow: fn(worldPos) -> number
   * opts.uv: 'keep' | 'box' (world box projection, metres / opts.uvScale) | [u, v] (constant) ;
   * opts.orn: { cell, amount, su = 1, sv = 1, ou = 0, ov = 0, fn(localPos, localNormal) -> [u, v, w] } maps the
   *   geometry's `ornUv` attribute (u, v, weight[, cell override]; see setOrnUv, sweep) or `fn` into the relief
   *   channel (Builder({orn:true})). `cell` + 16 = panel mode: relief only where 0 <= v <= 1 (u still tiles)
   */
  add(geo, matrix, opts = {}) {
    const p = geo.attributes.position, n = geo.attributes.normal, t = geo.attributes.uv;
    const base = this.vertexCount;
    _m3.getNormalMatrix(matrix);
    const color = opts.color || [1, 1, 1];
    const out = [1, 1, 1];
    const uvs = opts.uvScale || 2.5;
    const cuv = Array.isArray(opts.uv) ? opts.uv : null;
    const box = !cuv && (opts.uv === 'box' || !t);
    const O = this.orn, oo = opts.orn, oa = oo && geo.attributes.ornUv;
    for (let i = 0; i < p.count; i++) {
      _v.fromBufferAttribute(p, i).applyMatrix4(matrix);
      _n.fromBufferAttribute(n, i).applyMatrix3(_m3).normalize();
      this.pos.push(_v.x, _v.y, _v.z);
      this.nrm.push(_n.x, _n.y, _n.z);
      if (cuv) this.uv.push(cuv[0], cuv[1]);
      else if (box) {
        const ax = Math.abs(_n.x), ay = Math.abs(_n.y), az = Math.abs(_n.z);
        if (ay >= ax && ay >= az) this.uv.push(_v.x / uvs, _v.z / uvs);
        else if (ax >= az) this.uv.push(_v.z / uvs, _v.y / uvs);
        else this.uv.push(_v.x / uvs, _v.y / uvs);
      } else this.uv.push(t.getX(i) / uvs, t.getY(i) / uvs);
      if (typeof color === 'function') { color(_v, _n, out); this.col.push(out[0], out[1], out[2]); } else this.col.push(color[0], color[1], color[2]);
      this.glow.push(opts.glow ? opts.glow(_v) : 0);
      if (O) {
        let u = 0, v = 0, w = 0;
        let cell = oo ? oo.cell : 0;
        if (oa) { u = oa.getX(i); v = oa.getY(i); w = oa.getZ(i); if (oa.itemSize > 3 && oa.getW(i) >= 0) cell = oa.getW(i); }
        else if (oo && oo.fn) { const r = oo.fn(_lp.fromBufferAttribute(p, i), _ln.fromBufferAttribute(n, i)); if (r) { u = r[0]; v = r[1]; w = r[2]; } }
        if (oo && w > 0) O.push(u * (oo.su ?? 1) + (oo.ou ?? 0), v * (oo.sv ?? 1) + (oo.ov ?? 0), cell, oo.amount * w);
        else O.push(0, 0, 0, 0);
      }
    }
    if (geo.index) { const ix = geo.index.array; for (let i = 0; i < ix.length; i++) this.idx.push(base + ix[i]); }
    else for (let i = 0; i < p.count; i++) this.idx.push(base + i);
    const nt = (geo.index ? geo.index.count : p.count) / 3;
    this.tris[this._section] = (this.tris[this._section] || 0) + nt;
  }

  /** @returns {THREE.BufferGeometry} */
  build() {
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(this.pos, 3));
    g.setAttribute('normal', new THREE.Float32BufferAttribute(this.nrm, 3));
    g.setAttribute('uv', new THREE.Float32BufferAttribute(this.uv, 2));
    g.setAttribute('color', new THREE.Float32BufferAttribute(this.col, 3));
    g.setAttribute('glow', new THREE.Float32BufferAttribute(this.glow, 1));
    if (this.orn) g.setAttribute('orn', new THREE.Float32BufferAttribute(this.orn, 4));
    const n = this.vertexCount;
    g.setIndex(n > 65535 ? new THREE.Uint32BufferAttribute(this.idx, 1) : new THREE.Uint16BufferAttribute(this.idx, 1));
    g.computeBoundingSphere();
    g.computeBoundingBox();
    g.userData.tris = { ...this.tris };
    return g;
  }
}
const _lp = new THREE.Vector3();
const _ln = new THREE.Vector3();

/**
 * Give a geometry relief-cell coordinates: fn(localPos, localNormal, index) -> [u, v, weight] (weight 0 = no relief).
 * Stored as the `ornUv` attribute that Builder.add maps through opts.orn.
 */
export function setOrnUv(geo, fn) {
  const p = geo.attributes.position, n = geo.attributes.normal;
  const a = new Float32Array(p.count * 3);
  for (let i = 0; i < p.count; i++) {
    const r = fn(_lp.fromBufferAttribute(p, i), _ln.fromBufferAttribute(n, i), i);
    if (r) { a[i * 3] = r[0]; a[i * 3 + 1] = r[1]; a[i * 3 + 2] = r[2]; }
  }
  geo.setAttribute('ornUv', new THREE.BufferAttribute(a, 3));
  return geo;
}

/** Relief mapping for the front (+Z) face of a box centred at the origin: u across (0..1), v up (0..1). */
export const frontFace = (w, h, minNz = 0.9) => (p, n) => (n.z > minNz ? [p.x / w + 0.5, p.y / h + 0.5, 1] : null);

/**
 * Sweep a 2D profile along a path (mouldings: cornices, bases, archivolts, entablatures).
 * profile: [[x, y, sharp?], ...] in the path frame (x along `side`, y along `up`), ordered from the back at the
 * bottom, over the front, to the back at the top; `sharp` (default true) splits the normal at that point.
 * path: [{ p: Vector3, side: Vector3 (unit, horizontal outward of the moulding), up?: Vector3 }, ...].
 * opts.caps: close both ends; opts.orn: { [segmentIndex]: [v0, v1, cell?, uPerMetre = 1] } relief v range (and
 * optionally its own cell and repeat length) on that profile segment; u = metres along the path x uPerMetre.
 * @returns {THREE.BufferGeometry} indexed, smooth along the path
 */
export function sweep(profile, path, { caps = true, orn = null } = {}) {
  const ns = profile.length - 1;
  const segN = [];
  for (let s = 0; s < ns; s++) {
    const dx = profile[s + 1][0] - profile[s][0], dy = profile[s + 1][1] - profile[s][1];
    const l = Math.hypot(dx, dy) || 1;
    segN.push([dy / l, -dx / l]);
  }
  const ptN = (s, end) => {
    const i = s + end;
    const sharp = profile[i][2] !== false;
    const own = segN[s];
    if (sharp) return own;
    const other = end ? segN[s + 1] : segN[s - 1];
    if (!other) return own;
    const x = own[0] + other[0], y = own[1] + other[1], l = Math.hypot(x, y) || 1;
    return [x / l, y / l];
  };
  const pos = [], nrm = [], ouv = [], uv = [], idx = [];
  const up0 = new THREE.Vector3(0, 1, 0);
  const plen = [0];
  for (let i = 1; i < profile.length; i++) plen.push(plen[i - 1] + Math.hypot(profile[i][0] - profile[i - 1][0], profile[i][1] - profile[i - 1][1]));
  let acc = 0;
  const lens = path.map((q, k) => { if (k > 0) acc += q.p.distanceTo(path[k - 1].p); return acc; });
  const cols = 2 * ns;
  for (let k = 0; k < path.length; k++) {
    const { p, side } = path[k];
    const up = path[k].up || up0;
    for (let s = 0; s < ns; s++) for (let e = 0; e < 2; e++) {
      const [x, y] = profile[s + e];
      const nn = ptN(s, e);
      pos.push(p.x + side.x * x + up.x * y, p.y + side.y * x + up.y * y, p.z + side.z * x + up.z * y);
      const nx = side.x * nn[0] + up.x * nn[1], ny = side.y * nn[0] + up.y * nn[1], nz = side.z * nn[0] + up.z * nn[1];
      const l = Math.hypot(nx, ny, nz) || 1;
      nrm.push(nx / l, ny / l, nz / l);
      uv.push(lens[k], plen[s + e]);
      const o = orn && orn[s];
      ouv.push(lens[k] * (o && o[3] ? o[3] : 1), o ? o[0] + (o[1] - o[0]) * e : 0, o ? 1 : 0, o && o[2] !== undefined ? o[2] : -1);
    }
  }
  // winding: check one quad against its normal and flip consistently
  let flip = false;
  if (path.length > 1) {
    const a = new THREE.Vector3(pos[0], pos[1], pos[2]), b = new THREE.Vector3(pos[3], pos[4], pos[5]);
    const c = new THREE.Vector3(pos[cols * 3], pos[cols * 3 + 1], pos[cols * 3 + 2]);
    const cr = b.clone().sub(a).cross(c.clone().sub(a));
    flip = cr.dot(new THREE.Vector3(nrm[0], nrm[1], nrm[2])) < 0;
  }
  for (let k = 0; k < path.length - 1; k++) for (let s = 0; s < ns; s++) {
    const a = k * cols + s * 2, b = a + 1, c = a + cols, d = c + 1;
    if (flip) idx.push(a, c, b, b, c, d); else idx.push(a, b, c, b, d, c);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('normal', new THREE.Float32BufferAttribute(nrm, 3));
  g.setAttribute('ornUv', new THREE.Float32BufferAttribute(ouv, 4));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  g.setIndex(idx);
  if (!caps) return g;
  // end caps: the profile closed along the back (x = 0)
  const closed = profile.length > 3 && profile[0][0] === profile[ns][0] && profile[0][1] === profile[ns][1];
  const contour = (closed ? profile.slice(0, ns) : profile).map(([x, y]) => new THREE.Vector2(x, y));
  const tris = THREE.ShapeUtils.triangulateShape(contour, []);
  const cap = (k, dir) => {
    const { p, side } = path[k];
    const up = path[k].up || up0;
    const t = k === 0 ? path[1].p.clone().sub(p) : p.clone().sub(path[k - 1].p);
    t.normalize().multiplyScalar(dir);
    const cp = [], cn = [], co = [], cu = [];
    for (const tr of tris) {
      const v = tr.map((i) => { const [x, y] = profile[i]; return new THREE.Vector3(p.x + side.x * x + up.x * y, p.y + side.y * x + up.y * y, p.z + side.z * x + up.z * y); });
      const cr = v[1].clone().sub(v[0]).cross(v[2].clone().sub(v[0]));
      const order = cr.dot(t) < 0 ? [0, 2, 1] : [0, 1, 2];
      for (const o of order) { cp.push(v[o].x, v[o].y, v[o].z); cn.push(t.x, t.y, t.z); co.push(0, 0, 0, -1); cu.push(profile[tr[o]][0], profile[tr[o]][1]); }
    }
    const cg = new THREE.BufferGeometry();
    cg.setAttribute('position', new THREE.Float32BufferAttribute(cp, 3));
    cg.setAttribute('normal', new THREE.Float32BufferAttribute(cn, 3));
    cg.setAttribute('ornUv', new THREE.Float32BufferAttribute(co, 4));
    cg.setAttribute('uv', new THREE.Float32BufferAttribute(cu, 2));
    return cg;
  };
  return mergeSimple([g, cap(0, -1), cap(path.length - 1, 1)]);
}

/** Merge geometries that share position / normal (+ optional uv, ornUv) into one indexed geometry. */
export function mergeSimple(parts) {
  const pos = [], nrm = [], ouv = [], uv = [], idx = [];
  for (const g of parts) {
    const base = pos.length / 3;
    const p = g.attributes.position, n = g.attributes.normal, o = g.attributes.ornUv, t = g.attributes.uv;
    for (let i = 0; i < p.count; i++) {
      pos.push(p.getX(i), p.getY(i), p.getZ(i)); nrm.push(n.getX(i), n.getY(i), n.getZ(i));
      uv.push(t ? t.getX(i) : 0, t ? t.getY(i) : 0);
      ouv.push(o ? o.getX(i) : 0, o ? o.getY(i) : 0, o ? o.getZ(i) : 0, o && o.itemSize > 3 ? o.getW(i) : -1);
    }
    if (g.index) for (const i of g.index.array) idx.push(base + i); else for (let i = 0; i < p.count; i++) idx.push(base + i);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('normal', new THREE.Float32BufferAttribute(nrm, 3));
  g.setAttribute('ornUv', new THREE.Float32BufferAttribute(ouv, 4));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  g.setIndex(idx);
  return g;
}

/** Path helper: a horizontal ring arc at radius r and height y from theta a0 to a1 (ring convention), side = inward. */
export function arcPath(r, a0, a1, y = 0, segs = 8) {
  const out = [];
  for (let i = 0; i <= segs; i++) {
    const th = a0 + ((a1 - a0) * i) / segs;
    out.push({ p: new THREE.Vector3(r * Math.sin(th), y, -r * Math.cos(th)), side: new THREE.Vector3(-Math.sin(th), 0, Math.cos(th)) });
  }
  return out;
}

/** Path helper: straight run from a to b (horizontal), side = the given unit vector. */
export function linePath(a, b, side, segs = 1) {
  const out = [];
  for (let i = 0; i <= segs; i++) out.push({ p: a.clone().lerp(b, i / segs), side: side.clone() });
  return out;
}

/**
 * Tube along a polyline (vines, roots, chains' hang lines, fingers). Parallel-transport frames, smooth normals.
 * radius: number or fn(t 0..1). Optional flat caps.
 * @returns {THREE.BufferGeometry} indexed
 */
export function tube(points, radius, { sides = 5, caps = false } = {}) {
  const n = points.length;
  const rf = typeof radius === 'function' ? radius : () => radius;
  const T = [], N = [], Bv = [];
  for (let i = 0; i < n; i++) {
    const a = points[Math.max(0, i - 1)], b = points[Math.min(n - 1, i + 1)];
    T.push(b.clone().sub(a).normalize());
  }
  const ref = Math.abs(T[0].y) < 0.9 ? new THREE.Vector3(0, 1, 0) : new THREE.Vector3(1, 0, 0);
  N.push(new THREE.Vector3().crossVectors(T[0], ref).normalize());
  for (let i = 1; i < n; i++) {
    const nn = N[i - 1].clone().sub(T[i].clone().multiplyScalar(N[i - 1].dot(T[i]))).normalize();
    N.push(nn);
  }
  for (let i = 0; i < n; i++) Bv.push(new THREE.Vector3().crossVectors(T[i], N[i]));
  const pos = [], nrm = [], idx = [];
  for (let i = 0; i < n; i++) {
    const r = rf(i / (n - 1));
    for (let s = 0; s <= sides; s++) {
      const a = (s / sides) * Math.PI * 2;
      const d = N[i].clone().multiplyScalar(Math.cos(a)).addScaledVector(Bv[i], Math.sin(a));
      pos.push(points[i].x + d.x * r, points[i].y + d.y * r, points[i].z + d.z * r);
      nrm.push(d.x, d.y, d.z);
    }
  }
  const c = sides + 1;
  for (let i = 0; i < n - 1; i++) for (let s = 0; s < sides; s++) {
    const a = i * c + s, b = a + 1, d = a + c, e = d + 1;
    idx.push(a, b, d, b, e, d);
  }
  if (caps) {
    for (const [i, dir] of [[0, -1], [n - 1, 1]]) {
      const ci = pos.length / 3;
      pos.push(points[i].x, points[i].y, points[i].z);
      nrm.push(T[i].x * dir, T[i].y * dir, T[i].z * dir);
      const ring = [];
      for (let s = 0; s < sides; s++) {
        const k = i * c + s;
        ring.push(pos.length / 3);
        pos.push(pos[k * 3], pos[k * 3 + 1], pos[k * 3 + 2]);
        nrm.push(T[i].x * dir, T[i].y * dir, T[i].z * dir);
      }
      for (let s = 0; s < sides; s++) {
        const a = ring[s], b = ring[(s + 1) % sides];
        if (dir > 0) idx.push(ci, a, b); else idx.push(ci, b, a);
      }
    }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('normal', new THREE.Float32BufferAttribute(nrm, 3));
  g.setIndex(idx);
  return g;
}

/**
 * A broken ashlar block (open bottom unless `bottom`), the top shattered into a jagged, flat-shaded fracture surface (grid nx x nz),
 * sides following the fracture. `jag` = max depth of the break as a fraction of h.
 * @returns {THREE.BufferGeometry} non-indexed
 */
export function brokenBlock(w, h, d, rng, { jag = 0.45, nx = 3, nz = 2, tilt = 0, bottom = false } = {}) {
  const hx = w / 2, hy = h / 2, hz = d / 2;
  const seed = rng.range(0, 100);
  const top = [];
  for (let j = 0; j <= nz; j++) {
    const row = [];
    for (let i = 0; i <= nx; i++) {
      const x = -hx + (w * i) / nx, z = -hz + (d * j) / nz;
      const edge = i === 0 || i === nx || j === 0 || j === nz;
      const k = noise3(x * 2.3 + seed, z * 2.3, seed * 0.3);
      const y = hy - jag * h * (0.25 + 0.75 * k) * (edge ? 1 : 0.85) + tilt * x / Math.max(hx, 1e-3) * h * 0.2 + (edge ? 0 : rng.range(-0.05, 0.05) * h);
      row.push(new THREE.Vector3(x + (edge ? 0 : rng.range(-0.08, 0.08) * w / nx), y, z + (edge ? 0 : rng.range(-0.08, 0.08) * d / nz)));
    }
    top.push(row);
  }
  const out = [];
  const tri = (a, b, c) => out.push(a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z);
  for (let j = 0; j < nz; j++) for (let i = 0; i < nx; i++) {
    const a = top[j][i], b = top[j][i + 1], c = top[j + 1][i + 1], e = top[j + 1][i];
    if ((i + j) % 2) { tri(a, e, b); tri(b, e, c); } else { tri(a, e, c); tri(a, c, b); }
  }
  // sides: quads from the floor of the block up to the fracture edge
  const sideRun = (pts, outward) => {
    for (let k = 0; k < pts.length - 1; k++) {
      const a = pts[k], b = pts[k + 1];
      const a0 = new THREE.Vector3(a.x, -hy, a.z), b0 = new THREE.Vector3(b.x, -hy, b.z);
      const nrm = new THREE.Vector3().crossVectors(b0.clone().sub(a0), a.clone().sub(a0));
      if (nrm.dot(outward) < 0) { tri(a0, a, b0); tri(b0, a, b); } else { tri(a0, b0, a); tri(b0, b, a); }
    }
  };
  sideRun(top[nz], new THREE.Vector3(0, 0, 1));
  sideRun(top[0], new THREE.Vector3(0, 0, -1));
  sideRun(top.map((r) => r[0]), new THREE.Vector3(-1, 0, 0));
  sideRun(top.map((r) => r[nx]), new THREE.Vector3(1, 0, 0));
  if (bottom) {
    const a = new THREE.Vector3(-hx, -hy, -hz), b = new THREE.Vector3(hx, -hy, -hz), c = new THREE.Vector3(hx, -hy, hz), e = new THREE.Vector3(-hx, -hy, hz);
    tri(a, b, c); tri(a, c, e);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(out, 3));
  return flatNormals(g);
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
 * Smooth normals. Optional top cap (fan) and bottom cap; topY / bottomY (fn(phi)) reshape the last / first row;
 * `arc` = [phi0, phi1] builds an open partial lathe (capes, open hoods; no caps, no seam welding).
 * @returns {THREE.BufferGeometry} indexed
 */
export function latheGrid({ rows, segs, profile, rmod = null, capTop = false, capBottom = false, topY = null, bottomY = null, squash = 1, arc = null }) {
  const pos = [], uv = [], idx = [];
  const p0 = arc ? arc[0] : 0, p1 = arc ? arc[1] : Math.PI * 2;
  for (let j = 0; j <= rows; j++) {
    const [r, y] = profile(j / rows);
    for (let i = 0; i <= segs; i++) {
      const phi = p0 + (i / segs) * (p1 - p0);
      const m = rmod ? rmod(phi, y, j) : 1;
      let yy = y;
      if (topY && j === rows) yy = topY(phi);
      if (bottomY && j === 0) yy = bottomY(phi);
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
  if (arc) return [g];
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
 * Ashlar block for a coursed wall seen from one side: a chamfered box keeping only the triangles that can show
 * (front face, front bevels and corners; plus the top / end faces when `top` / `ends` say they are exposed).
 * Interior blocks drop from 44 to 14 triangles. Front = +Z.
 * @returns {THREE.BufferGeometry} non-indexed
 */
export function ashlar(w, h, d, bevel, rng, chip, { top = false, ends = false } = {}) {
  const g = chamferBox(w, h, d, bevel, rng, chip);
  const p = g.attributes.position.array, n = g.attributes.normal.array;
  const keepP = [], keepN = [];
  for (let t = 0; t < p.length; t += 9) {
    const nx = n[t], ny = n[t + 1], nz = n[t + 2];
    let keep = nz > 0.3;
    if (!keep && top && ny > 0.3 && nz > -0.3) keep = true;
    if (!keep && ends && Math.abs(nx) > 0.3 && nz > -0.3 && ny > -0.3) keep = true;
    if (keep) for (let k = 0; k < 9; k++) { keepP.push(p[t + k]); keepN.push(n[t + k]); }
  }
  const out = new THREE.BufferGeometry();
  out.setAttribute('position', new THREE.Float32BufferAttribute(keepP, 3));
  out.setAttribute('normal', new THREE.Float32BufferAttribute(keepN, 3));
  g.dispose();
  return out;
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

/**
 * A squared timber along X (centred): faces carry metric uvs with v along the grain (X) and u around the section,
 * so a grain texture runs the right way. `ends` adds the two end-grain faces. 8 / 12 triangles.
 * `ornFace`: also write the relief coordinates of the +Z face (u 0..1 along X, v 0..1 up) as `ornUv`
 * ('both': the -Z face too, mirrored).
 * @returns {THREE.BufferGeometry} non-indexed
 */
export function beam(L, h, d, { ends = true, ornFace = null } = {}) {
  const x0 = -L / 2, x1 = L / 2, y0 = -h / 2, y1 = h / 2, z0 = -d / 2, z1 = d / 2;
  const pos = [], nrm = [], uv = [], ouv = [];
  const quad = (a, b, c, e, n, ua, ub, uc, ue, orn) => {
    for (const [p, t, k] of [[a, ua, 0], [b, ub, 1], [c, uc, 2], [a, ua, 0], [c, uc, 2], [e, ue, 3]]) {
      pos.push(p[0], p[1], p[2]); nrm.push(n[0], n[1], n[2]); uv.push(t[0], t[1]);
      if (orn) ouv.push(orn[k][0], orn[k][1], 1); else ouv.push(0, 0, 0);
    }
  };
  const fr = [[0, 0], [1, 0], [1, 1], [0, 1]], bk = [[1, 0], [0, 0], [0, 1], [1, 1]];
  // front (+Z), back (-Z), top, bottom: v = x
  quad([x0, y0, z1], [x1, y0, z1], [x1, y1, z1], [x0, y1, z1], [0, 0, 1], [0, x0], [0, x1], [h, x1], [h, x0], ornFace ? fr : null);
  quad([x1, y0, z0], [x0, y0, z0], [x0, y1, z0], [x1, y1, z0], [0, 0, -1], [h + d, x1], [h + d, x0], [2 * h + d, x0], [2 * h + d, x1], ornFace === 'both' ? bk : null);
  quad([x0, y1, z1], [x1, y1, z1], [x1, y1, z0], [x0, y1, z0], [0, 1, 0], [h, x0], [h, x1], [h + d, x1], [h + d, x0], null);
  quad([x0, y0, z0], [x1, y0, z0], [x1, y0, z1], [x0, y0, z1], [0, -1, 0], [2 * h + d, x0], [2 * h + d, x1], [2 * h + 2 * d, x1], [2 * h + 2 * d, x0], null);
  if (ends) {
    quad([x1, y0, z1], [x1, y0, z0], [x1, y1, z0], [x1, y1, z1], [1, 0, 0], [0, 0], [d, 0], [d, h], [0, h], null);
    quad([x0, y0, z0], [x0, y0, z1], [x0, y1, z1], [x0, y1, z0], [-1, 0, 0], [0, 0], [d, 0], [d, h], [0, h], null);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('normal', new THREE.Float32BufferAttribute(nrm, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  g.setAttribute('ornUv', new THREE.Float32BufferAttribute(ouv, 3));
  return g;
}

/**
 * Extrude a convex 2D outline (points [x, y], counter-clockwise seen from +Z) along Z by `depth` (centred).
 * Flat shaded: bracket arms, wedges, gable boards, stair cheeks. @returns {THREE.BufferGeometry} non-indexed
 */
export function prism(outline, depth) {
  const z0 = -depth / 2, z1 = depth / 2, n = outline.length;
  const out = [];
  const tri = (a, b, c) => out.push(...a, ...b, ...c);
  for (let i = 1; i < n - 1; i++) {
    tri([outline[0][0], outline[0][1], z1], [outline[i][0], outline[i][1], z1], [outline[i + 1][0], outline[i + 1][1], z1]);
    tri([outline[0][0], outline[0][1], z0], [outline[i + 1][0], outline[i + 1][1], z0], [outline[i][0], outline[i][1], z0]);
  }
  for (let i = 0; i < n; i++) {
    const a = outline[i], b = outline[(i + 1) % n];
    tri([a[0], a[1], z1], [a[0], a[1], z0], [b[0], b[1], z0]);
    tri([a[0], a[1], z1], [b[0], b[1], z0], [b[0], b[1], z1]);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(out, 3));
  return flatNormals(g);
}

/** Position / Y-rotation helper on the ring: matrix at ring angle `th`, radius r, height y, facing the centre (+Z local = inward). */
export function ringM(r, th, y = 0, yaw = 0, rx = 0, rz = 0, s = 1) {
  return trs(r * Math.sin(th), y, -r * Math.cos(th), -th + yaw, rx, rz, s);
}
