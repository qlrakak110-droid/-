// Build system: a design's build(kit) function adds pieces (any BufferGeometry + material slot + bone binding); the kit
// bakes them into bind-pose model space with skin weights and merges everything into ONE SkinnedMesh per material slot.
//
//   kit.add(slot, bone, geo, opts)            rigid piece, 100% on `bone`; geo authored in the bone's zero-pose frame
//   kit.addPair(slot, base, geo, opts)        same for base+'R' and the z-mirrored copy on base+'L' ('elbow' or 'elbowR')
//   kit.addBlend(slot, frame, geo, weights, opts)    rigid shape split over several bones: weights [[bone, w], ...]
//   kit.addSkinned(slot, geo, weightFn, opts) per-vertex weights: weightFn(x, y, z) (bind space) -> [[bone, w], ...]
//   kit.loft(slot, spec, opts) / kit.loftPair  smooth-skinned tube along a chain of bones (the under-suit)
// opts (surface): { at, rot, scale (transform in the bone frame), color: hex | [r,g,b] linear | fn(p, n) -> [r,g,b],
//                   rough=0.5, metal=0, detail=1, cavity=1 | fn(p, n) -> 0..1, glow: [r,g,b] HDR | fn(p, n) }

import * as THREE from 'three';
import { qrot, qslerp } from './rigmath.js';
import { fnOf, xf, mirrorZ } from './shapes.js';

const _c = new THREE.Color();
const toLinear = (c) => {
  if (Array.isArray(c)) return c;
  _c.set(c);
  return [_c.r, _c.g, _c.b];
};

/**
 * @param {object} rig   from createRig
 * @param {object} bind  from bindMatrices(rig): { matrices, mq, mp }
 */
export function createKit(rig, bind) {
  const pieces = [];
  const bi = (name) => {
    const i = rig.index[name];
    if (i === undefined) throw new Error('char kit: unknown bone ' + name);
    return i;
  };
  const m4 = new THREE.Matrix4();

  function surface(geo, opts) {
    const n = geo.attributes.position.count, P = geo.attributes.position.array, N = geo.attributes.normal.array;
    const col = new Float32Array(n * 3), surf = new Float32Array(n * 4), glow = new Float32Array(n * 3);
    const cFn = typeof opts.color === 'function' ? opts.color : null, cK = cFn ? null : toLinear(opts.color ?? 0x808080);
    const aFn = typeof opts.cavity === 'function' ? opts.cavity : null;
    const gFn = typeof opts.glow === 'function' ? opts.glow : null, gK = gFn ? null : opts.glow || [0, 0, 0];
    const rough = opts.rough ?? 0.5, metal = opts.metal ?? 0, detail = opts.detail ?? 1, cav = aFn ? 1 : opts.cavity ?? 1;
    const p = [0, 0, 0], q = [0, 0, 0];
    for (let i = 0; i < n; i++) {
      p[0] = P[i * 3]; p[1] = P[i * 3 + 1]; p[2] = P[i * 3 + 2]; q[0] = N[i * 3]; q[1] = N[i * 3 + 1]; q[2] = N[i * 3 + 2];
      const c = cFn ? toLinear(cFn(p, q, i)) : cK;
      col[i * 3] = c[0]; col[i * 3 + 1] = c[1]; col[i * 3 + 2] = c[2];
      surf[i * 4] = rough; surf[i * 4 + 1] = metal; surf[i * 4 + 2] = detail; surf[i * 4 + 3] = aFn ? aFn(p, q, i) : cav;
      const g = gFn ? gFn(p, q, i) : gK;
      glow[i * 3] = g[0]; glow[i * 3 + 1] = g[1]; glow[i * 3 + 2] = g[2];
    }
    return { col, surf, glow };
  }

  function push(slot, geo, skinIdx, skinW, s) {
    pieces.push({ slot, geo, skinIdx, skinW, ...s });
  }

  function toBind(geo, boneIndex) {
    m4.fromArray(bind.matrices, boneIndex * 16);
    geo.applyMatrix4(m4);
    return geo;
  }

  function uniformWeights(n, pairs) {
    const idx = new Uint16Array(n * 4), w = new Float32Array(n * 4);
    for (let i = 0; i < n; i++) for (let k = 0; k < Math.min(4, pairs.length); k++) { idx[i * 4 + k] = pairs[k][0]; w[i * 4 + k] = pairs[k][1]; }
    return { idx, w };
  }

  const kit = {
    rig, bind,
    /** Model-space bind position of a bone (array [x,y,z]). */
    bonePos(name) { const i = bi(name); return [bind.mp[i * 3], bind.mp[i * 3 + 1], bind.mp[i * 3 + 2]]; },

    add(slot, bone, geo, opts = {}) {
      const b = bi(bone);
      const g = xf(geo.clone(), opts);
      const s = surface(g, opts);
      toBind(g, b);
      const { idx, w } = uniformWeights(g.attributes.position.count, [[b, 1]]);
      push(slot, g, idx, w, s);
      return kit;
    },

    addPair(slot, base, geo, opts = {}) {
      if (rig.index[base + 'R'] === undefined && /R$/.test(base)) base = base.slice(0, -1);
      const g = xf(geo.clone(), opts);
      const o2 = { ...opts, at: undefined, rot: undefined, scale: undefined };
      kit.add(slot, base + 'R', g, o2);
      const gm = mirrorZ(g);
      const mirrored = { ...o2 };
      for (const k of ['color', 'cavity', 'glow']) {
        if (typeof opts[k] === 'function') { const f = opts[k]; mirrored[k] = (p, n) => f([p[0], p[1], -p[2]], [n[0], n[1], -n[2]]); }
      }
      kit.add(slot, base + 'L', gm, mirrored);
      return kit;
    },

    addBlend(slot, frame, geo, weights, opts = {}) {
      const g = xf(geo.clone(), opts);
      const s = surface(g, opts);
      toBind(g, bi(frame));
      let tot = 0;
      for (const [, ww] of weights) tot += ww;
      const { idx, w } = uniformWeights(g.attributes.position.count, weights.map(([b, ww]) => [bi(b), ww / tot]));
      push(slot, g, idx, w, s);
      return kit;
    },

    /** geo in bind (model) space unless opts.frame names a bone; weightFn(x,y,z) returns [[boneName|index, w], ...]. */
    addSkinned(slot, geo, weightFn, opts = {}) {
      const g = xf(geo.clone(), opts);
      const s = surface(g, opts);
      if (opts.frame) toBind(g, bi(opts.frame));
      const n = g.attributes.position.count, P = g.attributes.position.array;
      const idx = new Uint16Array(n * 4), w = new Float32Array(n * 4);
      for (let i = 0; i < n; i++) {
        const ws = weightFn(P[i * 3], P[i * 3 + 1], P[i * 3 + 2], i).slice().sort((a, b) => b[1] - a[1]).slice(0, 4);
        let tot = 0;
        for (const x of ws) tot += x[1];
        ws.forEach(([b, ww], k) => { idx[i * 4 + k] = typeof b === 'number' ? b : bi(b); w[i * 4 + k] = ww / (tot || 1); });
      }
      push(slot, g, idx, w, s);
      return kit;
    },

    /**
     * Smooth-skinned tube along a bone chain (under-suit limbs, torso, plumes ...).
     * spec = {
     *   path:    [[bone, [x,y,z]], ...]   centreline control points (bone + offset in its zero frame), >= 2
     *   weights: [[k, bone], ...]         skin stations at fractional path index k (sorted); influence blends smoothly
     *                                     between consecutive stations (smoothstep)
     *   rx, rz:  curve over the fractional path index (0 .. n-1), radius toward the bone's +X / +Z
     *   ox, oz:  curve, centre offset;   n: curve, superellipse exponent (2 = ellipse)
     *   segs:    [radial=16, rings=24];  caps: [start=true, end=true]
     * }
     */
    loft(slot, spec, opts = {}) {
      const geo = loftGeometry(rig, bind, spec, bi);
      const s = surface(geo.geo, opts);
      push(slot, geo.geo, geo.idx, geo.w, s);
      return kit;
    },

    /** loft() for the R side and its mirror on the L side (bone names R->L, offsets/oz negated). */
    loftPair(slot, spec, opts = {}) {
      kit.loft(slot, spec, opts);
      const swap = (b) => (typeof b === 'string' && b.endsWith('R') ? b.slice(0, -1) + 'L' : b);
      const neg = (c) => (typeof c === 'function' ? (v) => -c(v) : Array.isArray(c) ? c.map(([k, x]) => [k, -x]) : c === undefined ? undefined : -c);
      const ms = {
        ...spec,
        path: spec.path.map(([b, o]) => [swap(b), [o[0], o[1], -o[2]]]),
        weights: spec.weights.map(([k, b]) => [k, swap(b)]),
        oz: neg(spec.oz),
        mirror: true,
      };
      const mo = { ...opts };
      for (const k of ['color', 'cavity', 'glow']) {
        if (typeof opts[k] === 'function') { const f = opts[k]; mo[k] = (p, n) => f([p[0], p[1], -p[2]], [n[0], n[1], -n[2]]); }
      }
      kit.loft(slot, ms, mo);
      return kit;
    },

    /** Finish: one SkinnedMesh per slot. materials: { slot: THREE.Material }. */
    finish(materials, skeleton) {
      const bySlot = new Map();
      for (const p of pieces) { if (!bySlot.has(p.slot)) bySlot.set(p.slot, []); bySlot.get(p.slot).push(p); }
      const meshes = {};
      let tris = 0;
      for (const [slot, list] of bySlot) {
        if (!materials[slot]) throw new Error('char kit: no material for slot ' + slot);
        const geo = mergePieces(list);
        tris += geo.index.count / 3;
        const mesh = new THREE.SkinnedMesh(geo, materials[slot]);
        mesh.name = 'char:' + slot;
        mesh.frustumCulled = false;
        mesh.castShadow = true;
        mesh.receiveShadow = true;
        mesh.bind(skeleton, new THREE.Matrix4());
        meshes[slot] = mesh;
      }
      return { meshes, triangles: tris };
    },

    get pieceCount() { return pieces.length; },
  };
  return kit;
}

function mergePieces(list) {
  let nv = 0, ni = 0;
  for (const p of list) { nv += p.geo.attributes.position.count; ni += p.geo.index.count; }
  const pos = new Float32Array(nv * 3), nor = new Float32Array(nv * 3), col = new Float32Array(nv * 3);
  const surf = new Float32Array(nv * 4), glow = new Float32Array(nv * 3), si = new Uint16Array(nv * 4), sw = new Float32Array(nv * 4);
  const idx = nv > 65535 ? new Uint32Array(ni) : new Uint16Array(ni);
  let vo = 0, io = 0;
  for (const p of list) {
    const c = p.geo.attributes.position.count;
    pos.set(p.geo.attributes.position.array.subarray(0, c * 3), vo * 3);
    nor.set(p.geo.attributes.normal.array.subarray(0, c * 3), vo * 3);
    col.set(p.col, vo * 3); surf.set(p.surf, vo * 4); glow.set(p.glow, vo * 3);
    si.set(p.skinIdx, vo * 4); sw.set(p.skinW, vo * 4);
    const a = p.geo.index.array;
    for (let i = 0; i < a.length; i++) idx[io + i] = a[i] + vo;
    io += a.length; vo += c;
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  g.setAttribute('normal', new THREE.BufferAttribute(nor, 3));
  g.setAttribute('color', new THREE.BufferAttribute(col, 3));
  g.setAttribute('surf', new THREE.BufferAttribute(surf, 4));
  g.setAttribute('glow', new THREE.BufferAttribute(glow, 3));
  g.setAttribute('skinIndex', new THREE.Uint16BufferAttribute(si, 4));
  g.setAttribute('skinWeight', new THREE.BufferAttribute(sw, 4));
  g.setIndex(new THREE.BufferAttribute(idx, 1));
  g.computeBoundingSphere();
  return g;
}

const sm = (x) => (x <= 0 ? 0 : x >= 1 ? 1 : x * x * (3 - 2 * x));

function loftGeometry(rig, bind, spec, bi) {
  const radial = (spec.segs && spec.segs[0]) || 16, rings = (spec.segs && spec.segs[1]) || 24;
  const np = spec.path.length;
  // control points in bind space + their bone bind rotations
  const pts = [], rots = [];
  const tmp = new Float32Array(3);
  for (const [b, o] of spec.path) {
    const i = bi(b);
    qrot(tmp, 0, bind.mq, i * 4, o[0], o[1], o[2]);
    pts.push(new THREE.Vector3(bind.mp[i * 3] + tmp[0], bind.mp[i * 3 + 1] + tmp[1], bind.mp[i * 3 + 2] + tmp[2]));
    rots.push(i);
  }
  const curve = new THREE.CatmullRomCurve3(pts, false, 'centripetal');
  // arc-length table over the fractional path index
  const D = 64 * (np - 1), table = new Float32Array(D + 1);
  let prev = curve.getPoint(0), L = 0;
  for (let k = 1; k <= D; k++) { const p = curve.getPoint(k / D); L += p.distanceTo(prev); table[k] = L; prev = p; }
  const fAt = (s) => { // arc length -> fractional index
    let lo = 0, hi = D;
    while (hi - lo > 1) { const mid = (lo + hi) >> 1; if (table[mid] < s) lo = mid; else hi = mid; }
    const a = table[lo], b = table[hi], u = b > a ? (s - a) / (b - a) : 0;
    return ((lo + u) / D) * (np - 1);
  };
  const RX = fnOf(spec.rx, 0.05), RZ = fnOf(spec.rz ?? spec.rx, 0.05), OX = fnOf(spec.ox, 0), OZ = fnOf(spec.oz, 0), NE = fnOf(spec.n, 2);
  const st = spec.weights.map(([k, b]) => [k, bi(b)]);
  const weightsAt = (f) => {
    if (f <= st[0][0]) return [[st[0][1], 1]];
    for (let i = 0; i < st.length - 1; i++) {
      if (f <= st[i + 1][0]) {
        const t = sm((f - st[i][0]) / Math.max(1e-6, st[i + 1][0] - st[i][0]));
        if (st[i][1] === st[i + 1][1]) return [[st[i][1], 1]];
        return [[st[i][1], 1 - t], [st[i + 1][1], t]];
      }
    }
    return [[st[st.length - 1][1], 1]];
  };
  const W = radial + 1, H = rings + 1;
  const pos = new Float32Array(W * H * 3);
  const idxArr = new Uint16Array(W * H * 4), wArr = new Float32Array(W * H * 4);
  const q = new Float32Array(4), fx = new Float32Array(3), zx = new Float32Array(3);
  const T = new THREE.Vector3(), F = new THREE.Vector3(), S = new THREE.Vector3(), Zb = new THREE.Vector3();
  const centers = [];
  for (let j = 0; j < H; j++) {
    const s = (j / rings) * L, f = fAt(s), u = f / (np - 1);
    const c = curve.getPoint(u);
    T.copy(curve.getTangent(Math.min(0.9999, Math.max(0.0001, u)))).normalize();
    const k0 = Math.min(np - 2, Math.floor(f)), fr = f - k0;
    qslerp(q, 0, bind.mq, rots[k0] * 4, bind.mq, rots[k0 + 1] * 4, fr);
    qrot(fx, 0, q, 0, 1, 0, 0); qrot(zx, 0, q, 0, 0, 0, 1);
    F.set(fx[0], fx[1], fx[2]); F.addScaledVector(T, -F.dot(T));
    if (F.lengthSq() < 0.04) { qrot(fx, 0, q, 0, 0, 1, 0); F.set(fx[0], fx[1], fx[2]).addScaledVector(T, -T.dot(F)); }
    F.normalize();
    Zb.set(zx[0], zx[1], zx[2]);
    if (Math.abs(Zb.dot(T)) > 0.95) Zb.crossVectors(T, F);
    S.copy(Zb).addScaledVector(T, -Zb.dot(T)).addScaledVector(F, -Zb.dot(F)).normalize();
    const rx = RX(f), rz = RZ(f), ox = OX(f), oz = OZ(f), e = 2 / NE(f);
    centers.push(c.clone().addScaledVector(F, ox).addScaledVector(S, oz));
    const wts = weightsAt(f);
    for (let i = 0; i < W; i++) {
      const th = (i / radial) * Math.PI * 2, ct = Math.cos(th), sn = Math.sin(th);
      const ex = Math.sign(ct) * Math.pow(Math.abs(ct), e), ez = Math.sign(sn) * Math.pow(Math.abs(sn), e);
      const p = (j * W + i) * 3;
      pos[p] = c.x + F.x * (ox + rx * ex) + S.x * (oz + rz * ez);
      pos[p + 1] = c.y + F.y * (ox + rx * ex) + S.y * (oz + rz * ez);
      pos[p + 2] = c.z + F.z * (ox + rx * ex) + S.z * (oz + rz * ez);
      const vi = (j * W + i) * 4;
      wts.forEach(([b, w], k) => { idxArr[vi + k] = b; wArr[vi + k] = w; });
    }
  }
  const idx = [];
  for (let j = 0; j < H - 1; j++) for (let i = 0; i < W - 1; i++) {
    const a = j * W + i, b = a + 1, c = a + W + 1, d = a + W;
    idx.push(a, b, d, b, c, d);
  }
  let geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  geo.setIndex(idx);
  geo.computeVertexNormals();
  // outward check
  {
    const N = geo.attributes.normal.array;
    let dot = 0;
    for (let j = 1; j < H - 1; j++) for (let i = 0; i < W; i += 3) {
      const p = (j * W + i) * 3, c = centers[j];
      dot += (pos[p] - c.x) * N[p] + (pos[p + 1] - c.y) * N[p + 1] + (pos[p + 2] - c.z) * N[p + 2];
    }
    if (dot < 0) { const a = geo.index.array; for (let i = 0; i < a.length; i += 3) { const t = a[i + 1]; a[i + 1] = a[i + 2]; a[i + 2] = t; } geo.computeVertexNormals(); }
  }
  // weld seam normals
  {
    const N = geo.attributes.normal.array;
    for (let j = 0; j < H; j++) {
      const a = j * W * 3, b = (j * W + W - 1) * 3;
      const nx = N[a] + N[b], ny = N[a + 1] + N[b + 1], nz = N[a + 2] + N[b + 2], l = Math.hypot(nx, ny, nz) || 1;
      N[a] = N[b] = nx / l; N[a + 1] = N[b + 1] = ny / l; N[a + 2] = N[b + 2] = nz / l;
    }
  }
  const caps = spec.caps || [true, true];
  const posA = Array.from(pos), norA = Array.from(geo.attributes.normal.array), idxA = Array.from(geo.index.array);
  const si = Array.from(idxArr), sw = Array.from(wArr);
  for (const [end, on] of [[0, caps[0]], [H - 1, caps[1]]]) {
    if (!on) continue;
    const c = centers[end];
    const tdir = curve.getTangent(end === 0 ? 0.0001 : 0.9999).normalize().multiplyScalar(end === 0 ? -1 : 1);
    const base = posA.length / 3;
    posA.push(c.x, c.y, c.z); norA.push(tdir.x, tdir.y, tdir.z);
    const w0 = (end * W) * 4;
    si.push(idxArr[w0], idxArr[w0 + 1], idxArr[w0 + 2], idxArr[w0 + 3]); sw.push(wArr[w0], wArr[w0 + 1], wArr[w0 + 2], wArr[w0 + 3]);
    for (let i = 0; i < W; i++) {
      const p = (end * W + i) * 3;
      posA.push(pos[p], pos[p + 1], pos[p + 2]); norA.push(tdir.x, tdir.y, tdir.z);
      const vi = (end * W + i) * 4;
      si.push(idxArr[vi], idxArr[vi + 1], idxArr[vi + 2], idxArr[vi + 3]); sw.push(wArr[vi], wArr[vi + 1], wArr[vi + 2], wArr[vi + 3]);
    }
    const capIdx = [];
    for (let i = 0; i < W - 1; i++) capIdx.push(base, base + 1 + i, base + 2 + i);
    // orient cap triangles along tdir
    const a = new THREE.Vector3(posA[(base + 1) * 3], posA[(base + 1) * 3 + 1], posA[(base + 1) * 3 + 2]).sub(c);
    const b = new THREE.Vector3(posA[(base + 2) * 3], posA[(base + 2) * 3 + 1], posA[(base + 2) * 3 + 2]).sub(c);
    const flip = a.cross(b).dot(tdir) < 0;
    for (let i = 0; i < capIdx.length; i += 3) idxA.push(capIdx[i], flip ? capIdx[i + 2] : capIdx[i + 1], flip ? capIdx[i + 1] : capIdx[i + 2]);
  }
  geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(posA, 3));
  geo.setAttribute('normal', new THREE.Float32BufferAttribute(norA, 3));
  geo.setIndex(idxA);
  return { geo, idx: new Uint16Array(si), w: new Float32Array(sw) };
}
