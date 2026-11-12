// Tailored cloth for ISKA: replaces the rig's rectangular cloth render mesh with a shaped, double-sided panel (pointed /
// diagonal hems, tapered sides), embroidered border bands, glowing star stitching and hem ornaments, all skinned
// bilinearly to the cloth particle bones exactly like the rig's own cloth mesh (no extra CPU work, no extra draw call).
//
//   const S = clothSurface(kit, rig, 'tailL', { anchor: 'chest', thickness: 0.012 });   // inside design.build()
//   panelCloth(kit, S, { hem: (a) => 1 - 0.2 * a, body: LOOK, border: TRIM, slots: { body: 'suit', border: 'plate' } });
//   suppressRigCloth(kit, ['tailL', 'tailR']);         // drop the rig's default meshes of those cloths
//
// The particle grid is read from the rig: cloth bones `<name>_<i>_<j>` are model-space roots whose rest offset is the
// grid position and whose rest rotation is the particle frame (X = surface normal). Parameters: u across the pinned
// edge (0 = the fighter's LEFT end) and v from the pinned row (0) to the hem (1), as in src/char/cloth.js.
// Rig change requested (see README): let a design hand the rig its own cloth render geometry, so suppressRigCloth()
// does not need to recognise the default mesh by its first skin bone.

import { mk, fixWinding, putSkinned } from '../../char/kit/geo.js';
import { qrot } from '../../char/rigmath.js';

const lerp = (a, b, t) => a + (b - a) * t;
const clamp = (x, a, b) => (x < a ? a : x > b ? b : x);

/**
 * Sampler of a simulated cloth's rest surface.
 * @param {object} kit  the build kit
 * @param {object} rig  the rig passed to design.build (contains the cloth bones)
 * @param {string} name cloth name
 * @param {object} o    { anchor: bone of the pinned edge (outward side test, as the rig does), thickness = 0.012 }
 * @returns {object|null} { name, C, R, first, th, at(u, v) -> { p, n, du, dv, w }, side }
 */
export function clothSurface(kit, rig, name, o = {}) {
  let C = 0, R = 0, first = -1;
  rig.names.forEach((n, i) => {
    const m = n.startsWith(name + '_') ? /_(\d+)_(\d+)$/.exec(n) : null;
    if (!m) return;
    C = Math.max(C, +m[1] + 1); R = Math.max(R, +m[2] + 1);
    if (first < 0) first = i;
  });
  if (first < 0) return null;
  const mp = kit.bind.mp, mq = kit.bind.mq, N = new Float32Array(C * R * 3);
  for (let k = 0; k < C * R; k++) qrot(N, k * 3, mq, (first + k) * 4, 1, 0, 0);
  // outward = away from the anchor bone (same rule as createCharacter)
  const mid = Math.floor(R / 2) * C + Math.floor(C / 2), b = kit.bonePos(o.anchor || 'chest');
  const away = (mp[(first + mid) * 3] - b[0]) * N[mid * 3] + (mp[(first + mid) * 3 + 2] - b[2]) * N[mid * 3 + 2];
  const side = away >= 0 ? 1 : -1;
  const th = (o.thickness ?? 0.012) * 0.5;
  const P = (i, j, k) => mp[(first + j * C + i) * 3 + k];
  const Nn = (i, j, k) => N[(j * C + i) * 3 + k];
  function at(u, v) {
    const fu = clamp(u, 0, 1) * (C - 1), fv = clamp(v, 0, 1) * (R - 1);
    const i0 = Math.min(C - 2, Math.floor(fu)), j0 = Math.min(R - 2, Math.floor(fv)), tu = fu - i0, tv = fv - j0;
    const cs = [[i0, j0, (1 - tu) * (1 - tv)], [i0 + 1, j0, tu * (1 - tv)], [i0, j0 + 1, (1 - tu) * tv], [i0 + 1, j0 + 1, tu * tv]];
    const p = [0, 0, 0], n = [0, 0, 0], w = [];
    for (const [i, j, ww] of cs) {
      for (let k = 0; k < 3; k++) { p[k] += P(i, j, k) * ww; n[k] += Nn(i, j, k) * ww; }
      if (ww > 1e-4) w.push([first + j * C + i, ww]);
    }
    const l = Math.hypot(n[0], n[1], n[2]) || 1;
    for (let k = 0; k < 3; k++) n[k] = (n[k] / l) * side;
    // parametric tangents (per unit u / v), bilinear cell derivatives
    const du = [0, 0, 0], dv = [0, 0, 0];
    for (let k = 0; k < 3; k++) {
      du[k] = ((P(i0 + 1, j0, k) - P(i0, j0, k)) * (1 - tv) + (P(i0 + 1, j0 + 1, k) - P(i0, j0 + 1, k)) * tv) * (C - 1);
      dv[k] = ((P(i0, j0 + 1, k) - P(i0, j0, k)) * (1 - tu) + (P(i0 + 1, j0 + 1, k) - P(i0 + 1, j0, k)) * tu) * (R - 1);
    }
    return { p, n, du, dv, w };
  }
  return { name, C, R, first, th, at, side };
}

/** Grid size { C, R } of a simulated cloth in the rig (the rig scales it with ctx.quality.cloth), or null. */
export function clothGrid(rig, name) {
  let C = 0, R = 0;
  for (const n of rig.names) {
    const m = n.startsWith(name + '_') ? /_(\d+)_(\d+)$/.exec(n) : null;
    if (m) { C = Math.max(C, +m[1] + 1); R = Math.max(R, +m[2] + 1); }
  }
  return C ? { C, R } : null;
}

/** Bilinear skin weights of a geometry built on a cloth surface: weightFn for kit.addSkinned (by vertex index). */
const weightsOf = (W) => (x, y, z, i) => W[i];

/**
 * Patch of the cloth surface: a grid over (a, b) in [a0, a1] x [b0, b1] mapped to (u, v) by map(a, b), offset along the
 * surface normal by `layer` * (th + lift). Returns { geo, W } (geo has position / normal / cav; W = per-vertex weights).
 */
function patch(S, map, as, bs, layer, lift = 0, cav = 1) {
  const pos = [], nor = [], idx = [], cv = [], W = [];
  const off = layer * (S.th + lift);
  for (const b of bs) for (const a of as) {
    const [u, v] = map(a, b), f = S.at(u, v);
    pos.push(f.p[0] + f.n[0] * off, f.p[1] + f.n[1] * off, f.p[2] + f.n[2] * off);
    nor.push(f.n[0] * layer, f.n[1] * layer, f.n[2] * layer);
    cv.push(cav); W.push(f.w);
  }
  const A = as.length;
  for (let j = 0; j < bs.length - 1; j++) for (let i = 0; i < A - 1; i++) {
    const p0 = j * A + i, p1 = p0 + 1, p2 = p0 + A, p3 = p2 + 1;
    idx.push(p0, p2, p1, p1, p2, p3);
  }
  return { geo: fixWinding(mk(pos, nor, idx, cv)), W };
}

/** Edge strip joining the outer and inner layers along a path of (a, b) points (the cloth's cut edge / hem binding). */
function rim(S, map, path, cav = 1.35) {
  const pos = [], nor = [], idx = [], cv = [], W = [];
  for (let k = 0; k < path.length; k++) {
    const [u, v] = map(...path[k]), f = S.at(u, v);
    // outward edge direction in the surface: away from the neighbours' midpoint, perpendicular to the normal
    const pa = map(...path[Math.max(0, k - 1)]), pb = map(...path[Math.min(path.length - 1, k + 1)]);
    const fa = S.at(...pa), fb = S.at(...pb);
    const t = [fb.p[0] - fa.p[0], fb.p[1] - fa.p[1], fb.p[2] - fa.p[2]];
    let e = [t[1] * f.n[2] - t[2] * f.n[1], t[2] * f.n[0] - t[0] * f.n[2], t[0] * f.n[1] - t[1] * f.n[0]];
    const el = Math.hypot(...e) || 1;
    e = e.map((x) => x / el);
    for (const s of [1, 0, -1]) {
      const o = s * S.th, bulge = (1 - Math.abs(s)) * S.th * 0.6;
      pos.push(f.p[0] + f.n[0] * o + e[0] * bulge, f.p[1] + f.n[1] * o + e[1] * bulge, f.p[2] + f.n[2] * o + e[2] * bulge);
      const nx = e[0] * (1 - Math.abs(s) * 0.6) + f.n[0] * s * 0.8, ny = e[1] * (1 - Math.abs(s) * 0.6) + f.n[1] * s * 0.8, nz = e[2] * (1 - Math.abs(s) * 0.6) + f.n[2] * s * 0.8;
      const l = Math.hypot(nx, ny, nz) || 1;
      nor.push(nx / l, ny / l, nz / l);
      cv.push(cav); W.push(f.w);
    }
  }
  for (let k = 0; k < path.length - 1; k++) for (let s = 0; s < 2; s++) {
    const a0 = k * 3 + s, a1 = a0 + 1, b0 = a0 + 3, b1 = b0 + 1;
    idx.push(a0, b0, a1, a1, b0, b1);
  }
  return { geo: fixWinding(mk(pos, nor, idx, cv)), W };
}

/**
 * Raised stitch strip following (a, b) points on one layer (embroidery, glowing star stitches).
 * o: { width = 0.004 (m, or fn(t) along the stroke: tapered rays), lift = 0.0009, bead = 0.0007, layer = 1, smooth = 3 }
 */
function stitch(S, map, pts, o = {}) {
  const wf = typeof o.width === 'function' ? o.width : () => o.width ?? 0.004;
  const layer = o.layer ?? 1, lift = o.lift ?? 0.0009, bead = o.bead ?? 0.0007, sub = o.smooth ?? 3;
  const dense = [];
  for (let i = 0; i < pts.length - 1; i++) for (let s = 0; s < sub; s++) dense.push([lerp(pts[i][0], pts[i + 1][0], s / sub), lerp(pts[i][1], pts[i + 1][1], s / sub)]);
  dense.push(pts[pts.length - 1]);
  const F = dense.map(([a, b]) => S.at(...map(a, b)));
  const pos = [], nor = [], idx = [], cv = [], W = [];
  const across = [-1, -0.4, 0.4, 1];
  for (let i = 0; i < F.length; i++) {
    const w = wf(i / Math.max(1, F.length - 1)) / 2;
    const A = F[Math.max(0, i - 1)].p, B = F[Math.min(F.length - 1, i + 1)].p, n = F[i].n.map((x) => x * layer);
    const t = [B[0] - A[0], B[1] - A[1], B[2] - A[2]];
    let sd = [n[1] * t[2] - n[2] * t[1], n[2] * t[0] - n[0] * t[2], n[0] * t[1] - n[1] * t[0]];
    const sl = Math.hypot(...sd) || 1;
    sd = sd.map((x) => x / sl);
    for (const x of across) {
      const h = S.th + lift + bead * (1 - x * x);
      pos.push(F[i].p[0] + sd[0] * x * w + n[0] * h, F[i].p[1] + sd[1] * x * w + n[1] * h, F[i].p[2] + sd[2] * x * w + n[2] * h);
      const q = [n[0] + sd[0] * x * 0.7, n[1] + sd[1] * x * 0.7, n[2] + sd[2] * x * 0.7], ql = Math.hypot(...q) || 1;
      nor.push(q[0] / ql, q[1] / ql, q[2] / ql);
      cv.push(1 + 0.45 * (1 - x * x)); W.push(F[i].w);
    }
  }
  const K = across.length;
  for (let i = 0; i < F.length - 1; i++) for (let k = 0; k < K - 1; k++) {
    const a = i * K + k, b = a + 1, c = a + K, d = c + 1;
    idx.push(a, c, b, b, c, d);
  }
  return { geo: fixWinding(mk(pos, nor, idx, cv)), W };
}

const range = (a, b, n) => Array.from({ length: n + 1 }, (_, i) => lerp(a, b, i / n));

/**
 * Shaped, double-sided cloth panel on a cloth surface with embroidered borders and star stitching.
 * o:
 *   hem(a) -> v       hem line (v at the hem for a in 0..1 across), default 1
 *   sides(b) -> [uL, uR]   side edges over b (0 top .. 1 hem), default [0, 1]
 *   hemBand = 0.05    hem band depth (fraction of v);  sideBand = 0  side band width (fraction of u; 'left'/'right' via bandSides)
 *   bandSides = 'both' | 'left' | 'right' | 'none'
 *   na = 12, nb = 24  segments across / along the body
 *   body, border      looks (body on slots.body, border bands + rim on slots.border)
 *   slots = { body: 'suit', border: 'plate' }
 *   stars = []        four-point star stitches: [{ a, b, r (m), width, both (also on the lining) }]
 *   lines = []        stitch lines: [{ pts: [[a, b]...], width, look, both = true }]
 *   starLook          look of the star stitches
 * Returns { map } (the (a, b) -> (u, v) mapping) for extra ornaments.
 */
export function panelCloth(kit, S, o = {}) {
  if (!S) return null;
  const hem = o.hem || (() => 1), sides = o.sides || (() => [0, 1]);
  const map = (a, b) => { const [uL, uR] = sides(b); const u = lerp(uL, uR, a); return [u, b * hem(a)]; };
  const hb = 1 - (o.hemBand ?? 0.05), sb = o.sideBand ?? 0, bs = o.bandSides ?? 'both';
  const sL = bs === 'both' || bs === 'left' ? sb : 0, sR = bs === 'both' || bs === 'right' ? sb : 0;
  const na = o.na ?? 12, nb = o.nb ?? 24;
  const slots = { body: 'suit', border: 'plate', ...(o.slots || {}) };
  const add = (slot, part, look) => putSkinned(kit, slot, part.geo, look, weightsOf(part.W));
  const bodyA = range(sL, 1 - sR, Math.max(2, Math.round(na * (1 - sL - sR)))), bodyB = range(0, hb, Math.max(2, Math.round(nb * hb)));
  for (const layer of [1, -1]) {
    add(slots.body, patch(S, map, bodyA, bodyB, layer, 0, layer > 0 ? 1 : 0.6), layer > 0 ? o.body : (o.lining || o.body));
    // border bands (hem band spans the full width, side bands stop at the hem band)
    const bandB = range(hb, 1, 2);
    add(slots.border, patch(S, map, range(0, 1, na), bandB, layer, 0.0004), o.border);
    if (sL > 0) add(slots.border, patch(S, map, range(0, sL, 1), bodyB, layer, 0.0004), o.border);
    if (sR > 0) add(slots.border, patch(S, map, range(1 - sR, 1, 1), bodyB, layer, 0.0004), o.border);
  }
  // cut edges: sides + hem in the border look, the hidden top edge in the body look
  const left = range(0, 1, nb).map((b) => [0, b]), right = range(0, 1, nb).map((b) => [1, b]).reverse(), bottom = range(0, 1, na * 2).map((a) => [a, 1]);
  add(slots.border, rim(S, map, [...left, ...bottom.slice(1), ...right.slice(1)]), o.border);
  add(slots.body, rim(S, map, range(1, 0, na).map((a) => [a, 0]), 0.7), o.body);
  // embroidery: star stitches (outer layer unless `both`) and stitch lines (both layers unless `both: false`)
  for (const st of o.stars || []) {
    for (const layer of st.both ? [1, -1] : [1]) {
      for (const [ray, w] of starRays(S, map, st)) add(slots.border, stitch(S, map, ray, { width: (t) => w * (1 - t) ** 1.3 + 0.0004, layer, smooth: 3 }), o.starLook || o.border);
    }
  }
  for (const ln of o.lines || []) {
    for (const layer of ln.both === false ? [1] : [1, -1]) add(slots.border, stitch(S, map, ln.pts, { width: ln.width ?? 0.004, layer }), ln.look || o.border);
  }
  return { map };
}

/** Four-point star around (a, b) as tapered rays from the centre: [[points, base width (m)], ...]; r = long ray (m). */
function starRays(S, map, st) {
  const f = S.at(...map(st.a, st.b));
  const la = Math.hypot(...f.du) || 1, lb = Math.hypot(...f.dv) || 1;
  const r = st.r ?? 0.03, w = st.width ?? r * 0.32, c = [st.a, st.b];
  const ray = (da, db, k) => [[c, [st.a + (da * r * k) / la, st.b + (db * r * k) / lb]], w * Math.sqrt(k)];
  const d = Math.SQRT1_2;
  const rays = [ray(0, -1, 1), ray(0, 1, 1), ray(-1, 0, 0.62), ray(1, 0, 0.62)];
  return r >= 0.02 ? [...rays, ray(d, d, 0.3), ray(-d, d, 0.3), ray(d, -d, 0.3), ray(-d, -d, 0.3)] : rays;
}

/**
 * Rigid ornament following one point of the cloth (hem weights, tassel charms): geo authored in a local frame
 * (+Y = up along the cloth, +X = outward normal) is placed at (u, v) and skinned to that point's particle weights.
 */
export function clothCharm(kit, S, u, v, geo, look, o = {}) {
  if (!S) return;
  const f = S.at(u, v);
  const n = f.n, dv = f.dv, dl = Math.hypot(...dv) || 1;
  const up = [-dv[0] / dl, -dv[1] / dl, -dv[2] / dl];                    // toward the pinned edge
  const z = [n[1] * up[2] - n[2] * up[1], n[2] * up[0] - n[0] * up[2], n[0] * up[1] - n[1] * up[0]];
  const g = geo.clone(), Pp = g.attributes.position.array, Nn = g.attributes.normal.array;
  const off = o.offset ?? 0;
  for (let i = 0; i < Pp.length; i += 3) {
    const x = Pp[i], y = Pp[i + 1], zz = Pp[i + 2];
    Pp[i] = f.p[0] + n[0] * (x + off) + up[0] * y + z[0] * zz;
    Pp[i + 1] = f.p[1] + n[1] * (x + off) + up[1] * y + z[1] * zz;
    Pp[i + 2] = f.p[2] + n[2] * (x + off) + up[2] * y + z[2] * zz;
    const a = Nn[i], b = Nn[i + 1], c = Nn[i + 2];
    Nn[i] = n[0] * a + up[0] * b + z[0] * c; Nn[i + 1] = n[1] * a + up[1] * b + z[1] * c; Nn[i + 2] = n[2] * a + up[2] * b + z[2] * c;
  }
  const W = new Array(Pp.length / 3).fill(f.w);
  putSkinned(kit, o.slot || 'plate', fixWinding(g), look, weightsOf(W));
}

/**
 * Drop the rig's default render mesh of the named cloths. Call it LAST in build(): the rig adds its cloth meshes through
 * kit.addSkinned after build() returns, and recognising them by their first skin bone would also drop the tailored
 * pieces if they were added after this call.
 */
export function suppressRigCloth(kit, rig, names) {
  const ranges = [];
  for (const name of names) {
    let first = -1, last = -1;
    rig.names.forEach((n, i) => { if (n.startsWith(name + '_') && /_\d+_\d+$/.test(n)) { if (first < 0) first = i; last = i; } });
    if (first >= 0) ranges.push([first, last]);
  }
  const orig = kit.addSkinned;
  kit.addSkinned = function (slot, geo, weightFn, opts = {}) {
    const w0 = weightFn(0, 0, 0, 0), bi = w0 && w0[0] ? w0[0][0] : -1;
    if (typeof bi === 'number' && ranges.some(([a, b]) => bi >= a && bi <= b)) return kit;
    return orig.call(kit, slot, geo, weightFn, opts);
  };
  return kit;
}

