// ============================================================================
//  people: stylized-realistic characters (adults 6.5–7 heads, kid ≈ 4.3) on a real skeleton
//  · every garment is its own sculpted SDF layer (crisp colour / material edges, real hems and overlaps), Taubin-
//    smoothed and skinned to a 21-bone rig with capsule weights; head, hands and accessories ride their bones rigidly
//  · faces with volume (brow ridge, cheekbones, nose bridge, lips, jaw, ears); eyes sit in carved sockets under real
//    lid shells (lash line, crease, lid shadow), irises with fibres / limbal ring / caustic seen through the cornea,
//    one shared catch-light direction, converging gaze with saccades, 120–150 ms blinks (sometimes double)
//  · hair = swept lens-section clumps grown over the scalp (bangs, sides, nape, long locks on a spring bone)
//  · own cel shading: two tones + narrow form band with an antialiased terminator, hue-shifted shade, skin scatter at
//    the terminator, shaped specular (leather / metal / lips), anisotropic hair sheen, cloth fresnel sheen, clean
//    sun-side rim, very soft baked crease AO; screen-space ink outline coloured from the albedo
//  · procedural animation: breathing, weight shift, look-at (head + eyes), walk → run → sprint with arm swing, knee
//    and foot roll, pelvis bob / yaw / roll, lean, hair spring, cloth tails
//  buildPerson(look) keeps the old look options (skin hair top shirt trim bottom shoe glove accent robe beard long pack
//  kid hat pin staff pendant eye eye2) and sets r.size and r.headY (head centre height above the feet).
// ============================================================================
const ppV = {
  add: (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]],
  sub: (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]],
  mul: (a, k) => [a[0] * k, a[1] * k, a[2] * k],
  dot: (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2],
  cross: (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]],
  len: (a) => Math.hypot(a[0], a[1], a[2]),
  norm: (a) => { const l = Math.hypot(a[0], a[1], a[2]) || 1; return [a[0] / l, a[1] / l, a[2] / l]; },
  lerp: (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t],
};
const _ppC = new THREE.Color();
const ppLin = (h) => { _ppC.set(h); return [_ppC.r, _ppC.g, _ppC.b]; };
const ppHex = (c) => { _ppC.setRGB(c[0], c[1], c[2]); return _ppC.getHex(); };
const ppMixC = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
// surface response per material: [specular, gloss, skin scatter, hair sheen]
const PP_M = { skin: [0.2, 0.3, 1, 0], lip: [0.42, 0.5, 1, 0], cloth: [0, 0, 0, 0], satin: [0.16, 0.22, 0, 0], leather: [0.4, 0.5, 0, 0], metal: [1, 0.8, 0, 0], hair: [0, 0, 0, 1], wood: [0.12, 0.2, 0, 0], ink: [0, 0, 0, 0] };
const PP_HI = () => Settings.high && !isTouch;

// ---------------------------------------------------------------- sculpt: SDF field → surface nets (no attributes)
function ppSculpt(prims, cell) {
  let x0 = 1e9, y0 = 1e9, z0 = 1e9, x1 = -1e9, y1 = -1e9, z1 = -1e9;
  for (const P of prims) if (!P.sub) { const a = SDF.aabb(P); x0 = Math.min(x0, a[0]); y0 = Math.min(y0, a[1]); z0 = Math.min(z0, a[2]); x1 = Math.max(x1, a[3]); y1 = Math.max(y1, a[4]); z1 = Math.max(z1, a[5]); }
  x0 -= cell * 2; y0 -= cell * 2; z0 -= cell * 2; x1 += cell * 2; y1 += cell * 2; z1 += cell * 2;
  const nx = Math.ceil((x1 - x0) / cell) + 1, ny = Math.ceil((y1 - y0) / cell) + 1, nz = Math.ceil((z1 - z0) / cell) + 1;
  const N = nx * ny * nz, grid = new Float32Array(N).fill(1e3), sxy = nx * ny;
  for (const P of prims) {
    const bb = SDF.aabb(P);
    const ia = Math.max(0, Math.floor((bb[0] - x0) / cell)), ib = Math.min(nx - 1, Math.ceil((bb[3] - x0) / cell));
    const ja = Math.max(0, Math.floor((bb[1] - y0) / cell)), jb = Math.min(ny - 1, Math.ceil((bb[4] - y0) / cell));
    const ka = Math.max(0, Math.floor((bb[2] - z0) / cell)), kb = Math.min(nz - 1, Math.ceil((bb[5] - z0) / cell));
    const k = P.k;
    for (let kz = ka; kz <= kb; kz++) {
      const z = z0 + kz * cell;
      for (let jy = ja; jy <= jb; jy++) {
        const y = y0 + jy * cell, row = kz * sxy + jy * nx;
        for (let ix = ia; ix <= ib; ix++) {
          const d = SDF.dist(P, x0 + ix * cell, y, z), g = grid[row + ix];
          if (P.sub) { const h = Math.max(k - Math.abs(-d - g), 0) / k; grid[row + ix] = Math.max(g, -d) + h * h * k * 0.25; }
          else if (d < g + k) { const h = Math.max(k - Math.abs(g - d), 0) / k; grid[row + ix] = Math.min(g, d) - h * h * k * 0.25; }
        }
      }
    }
  }
  const at = (i, j, k) => grid[k * sxy + j * nx + i];
  const sample = (x, y, z) => {
    let fx = (x - x0) / cell, fy = (y - y0) / cell, fz = (z - z0) / cell;
    if (fx < 0 || fy < 0 || fz < 0 || fx > nx - 1.001 || fy > ny - 1.001 || fz > nz - 1.001) return 1e3;
    const i = fx | 0, j = fy | 0, k = fz | 0, u = fx - i, v = fy - j, w = fz - k;
    const c00 = at(i, j, k) * (1 - u) + at(i + 1, j, k) * u, c10 = at(i, j + 1, k) * (1 - u) + at(i + 1, j + 1, k) * u;
    const c01 = at(i, j, k + 1) * (1 - u) + at(i + 1, j, k + 1) * u, c11 = at(i, j + 1, k + 1) * (1 - u) + at(i + 1, j + 1, k + 1) * u;
    return (c00 * (1 - v) + c10 * v) * (1 - w) + (c01 * (1 - v) + c11 * v) * w;
  };
  const cellV = new Int32Array(N).fill(-1);
  let pos = new Float32Array(1 << 16), nv = 0;
  const CO = [[0, 0, 0], [1, 0, 0], [0, 1, 0], [1, 1, 0], [0, 0, 1], [1, 0, 1], [0, 1, 1], [1, 1, 1]];
  const ED = [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]];
  const v = new Float64Array(8);
  for (let k = 0; k < nz - 1; k++) for (let j = 0; j < ny - 1; j++) for (let i = 0; i < nx - 1; i++) {
    let mask = 0;
    for (let c = 0; c < 8; c++) { v[c] = at(i + CO[c][0], j + CO[c][1], k + CO[c][2]); if (v[c] < 0) mask |= 1 << c; }
    if (mask === 0 || mask === 255) continue;
    let sx = 0, sy = 0, sz = 0, n = 0;
    for (const [a, b] of ED) {
      const va = v[a], vb = v[b];
      if ((va < 0) === (vb < 0)) continue;
      const t = va / (va - vb);
      sx += CO[a][0] + t * (CO[b][0] - CO[a][0]); sy += CO[a][1] + t * (CO[b][1] - CO[a][1]); sz += CO[a][2] + t * (CO[b][2] - CO[a][2]); n++;
    }
    if (nv * 3 + 3 > pos.length) { const np = new Float32Array(pos.length * 2); np.set(pos); pos = np; }
    pos[nv * 3] = x0 + (i + sx / n) * cell; pos[nv * 3 + 1] = y0 + (j + sy / n) * cell; pos[nv * 3 + 2] = z0 + (k + sz / n) * cell;
    cellV[k * sxy + j * nx + i] = nv++;
  }
  pos = pos.slice(0, nv * 3);
  const nor = new Float32Array(nv * 3), h = cell * 0.7;
  const fieldNormals = () => {
    for (let q = 0; q < nv; q++) {
      const x = pos[q * 3], y = pos[q * 3 + 1], z = pos[q * 3 + 2];
      const gx = sample(x + h, y, z) - sample(x - h, y, z), gy = sample(x, y + h, z) - sample(x, y - h, z), gz = sample(x, y, z + h) - sample(x, y, z - h);
      const l = Math.hypot(gx, gy, gz) || 1; nor[q * 3] = gx / l; nor[q * 3 + 1] = gy / l; nor[q * 3 + 2] = gz / l;
    }
  };
  fieldNormals();
  let idx = new Uint32Array(1 << 17), ni = 0;
  const cv = (i, j, k) => cellV[k * sxy + j * nx + i];
  const tri = (a, b, c) => {
    if (a < 0 || b < 0 || c < 0) return;
    const ax = pos[a * 3], ay = pos[a * 3 + 1], az = pos[a * 3 + 2];
    const ux = pos[b * 3] - ax, uy = pos[b * 3 + 1] - ay, uz = pos[b * 3 + 2] - az, wx = pos[c * 3] - ax, wy = pos[c * 3 + 1] - ay, wz = pos[c * 3 + 2] - az;
    const fx = uy * wz - uz * wy, fy = uz * wx - ux * wz, fz = ux * wy - uy * wx;
    const mx = nor[a * 3] + nor[b * 3] + nor[c * 3], my = nor[a * 3 + 1] + nor[b * 3 + 1] + nor[c * 3 + 1], mz = nor[a * 3 + 2] + nor[b * 3 + 2] + nor[c * 3 + 2];
    if (ni + 3 > idx.length) { const n2 = new Uint32Array(idx.length * 2); n2.set(idx); idx = n2; }
    if (fx * mx + fy * my + fz * mz >= 0) { idx[ni++] = a; idx[ni++] = b; idx[ni++] = c; } else { idx[ni++] = a; idx[ni++] = c; idx[ni++] = b; }
  };
  const quad = (a, b, c, d) => { tri(a, b, c); tri(a, c, d); };
  for (let k = 0; k < nz - 1; k++) for (let j = 0; j < ny - 1; j++) for (let i = 0; i < nx - 1; i++) {
    const s0 = at(i, j, k) < 0;
    if (j > 0 && k > 0 && s0 !== (at(i + 1, j, k) < 0)) quad(cv(i, j - 1, k - 1), cv(i, j, k - 1), cv(i, j, k), cv(i, j - 1, k));
    if (i > 0 && k > 0 && s0 !== (at(i, j + 1, k) < 0)) quad(cv(i - 1, j, k - 1), cv(i, j, k - 1), cv(i, j, k), cv(i - 1, j, k));
    if (i > 0 && j > 0 && s0 !== (at(i, j, k + 1) < 0)) quad(cv(i - 1, j - 1, k), cv(i, j - 1, k), cv(i, j, k), cv(i - 1, j, k));
  }
  idx = idx.slice(0, ni);
  // Taubin λ|μ smoothing: removes the surface-nets ripple without shrinking; then normals again from the field
  {
    const acc = new Float32Array(nv * 3), cnt = new Float32Array(nv);
    for (let it = 0; it < 3; it++) for (const lam of [0.55, -0.58]) {
      acc.fill(0); cnt.fill(0);
      for (let t = 0; t < ni; t += 3) for (let e = 0; e < 3; e++) {
        const a = idx[t + e], b = idx[t + (e + 1) % 3];
        acc[a * 3] += pos[b * 3]; acc[a * 3 + 1] += pos[b * 3 + 1]; acc[a * 3 + 2] += pos[b * 3 + 2]; cnt[a]++;
        acc[b * 3] += pos[a * 3]; acc[b * 3 + 1] += pos[a * 3 + 1]; acc[b * 3 + 2] += pos[a * 3 + 2]; cnt[b]++;
      }
      for (let q = 0; q < nv; q++) if (cnt[q]) for (let c = 0; c < 3; c++) pos[q * 3 + c] += lam * (acc[q * 3 + c] / cnt[q] - pos[q * 3 + c]);
    }
    fieldNormals();
  }
  return { pos, nor, idx, nv, sample, bounds: [x0, y0, z0, x1, y1, z1] };
}
// exact replay of the sculpt field (same union / subtraction order) — to find surfaces before meshing
function ppField(prims, x, y, z) {
  let g = 1e3;
  for (const P of prims) {
    const d = SDF.dist(P, x, y, z), k = P.k;
    if (P.sub) { const h = Math.max(k - Math.abs(-d - g), 0) / k; g = Math.max(g, -d) + h * h * k * 0.25; }
    else if (d < g + k) { const h = Math.max(k - Math.abs(g - d), 0) / k; g = Math.min(g, d) - h * h * k * 0.25; }
  }
  return g;
}

// ---------------------------------------------------------------- surfaces: one vertex stream per part, merged at the end
// s = { pos, nor, idx, nv, col (rgb), m (vec4 material), uv (vec2: x param, y flag: 0 plain · 1..2 stitched band ·
//       ≥3 hair strand · <0 no outline), tan (vec3), ao, sk (4 bone idx), sw (4 weights) }
function ppSurf(nv, nt) {
  return { nv, pos: new Float32Array(nv * 3), nor: new Float32Array(nv * 3), idx: new Uint32Array(nt * 3), col: new Float32Array(nv * 3), m: new Float32Array(nv * 4), uv: new Float32Array(nv * 2), tan: new Float32Array(nv * 3), ao: new Float32Array(nv).fill(1), sk: new Uint16Array(nv * 4), sw: new Float32Array(nv * 4) };
}
function ppFill(s, col, m, uvy = 0) {
  for (let q = 0; q < s.nv; q++) { s.col.set(col, q * 3); s.m.set(m, q * 4); s.uv[q * 2 + 1] = uvy; }
  return s;
}
// rigid: every vertex on one bone
function ppRigid(s, bi) { for (let q = 0; q < s.nv; q++) { s.sk[q * 4] = bi; s.sw[q * 4] = 1; } return s; }
// mirror x (left ↔ right) keeping the winding outward
function ppMirror(s) {
  for (let q = 0; q < s.nv; q++) { s.pos[q * 3] *= -1; s.nor[q * 3] *= -1; s.tan[q * 3] *= -1; }
  for (let t = 0; t < s.idx.length; t += 3) { const a = s.idx[t + 1]; s.idx[t + 1] = s.idx[t + 2]; s.idx[t + 2] = a; }
  return s;
}
// rotate (columns X, Y, Z) and translate
function ppXform(s, X, Y, Z, T) {
  const f = (arr, q, w) => { const x = arr[q * 3], y = arr[q * 3 + 1], z = arr[q * 3 + 2]; arr[q * 3] = X[0] * x + Y[0] * y + Z[0] * z + w * T[0]; arr[q * 3 + 1] = X[1] * x + Y[1] * y + Z[1] * z + w * T[1]; arr[q * 3 + 2] = X[2] * x + Y[2] * y + Z[2] * z + w * T[2]; };
  for (let q = 0; q < s.nv; q++) { f(s.pos, q, 1); f(s.nor, q, 0); f(s.tan, q, 0); }
  return s;
}
// sweep a cross-section along a polyline. w / t: half width / half thickness per point, up(i) → the direction the
// thickness points to (usually the surface normal under the strip). shape: 'lens' (ellipse), 'flat' (rounded slab).
function ppSweep(P, w, t, up, o = {}) {
  const n = P.length, seg = o.seg || 6, closed = !!o.closed, shape = o.shape || 'lens';
  const rings = n, nv = rings * seg, nt = (closed ? n : n - 1) * seg * 2;
  const s = ppSurf(nv, nt);
  let along = 0;
  for (let i = 0; i < n; i++) {
    const pv = closed ? P[(i - 1 + n) % n] : P[Math.max(0, i - 1)], nx = closed ? P[(i + 1) % n] : P[Math.min(n - 1, i + 1)];
    const T = ppV.norm(ppV.sub(nx, pv));
    let U = up(i, T); U = ppV.sub(U, ppV.mul(T, ppV.dot(U, T))); const N0 = ppV.norm(U);
    const B = ppV.cross(T, N0);
    if (i > 0) along += ppV.len(ppV.sub(P[i], P[i - 1]));
    for (let k = 0; k < seg; k++) {
      const a = (k / seg) * Math.PI * 2, ca = Math.cos(a), sa = Math.sin(a);
      let x, y, gx, gy;
      if (shape === 'flat') {
        const e = 0.35; x = Math.sign(ca) * Math.pow(Math.abs(ca), e) * w[i]; y = Math.sign(sa) * Math.pow(Math.abs(sa), e) * t[i];
        gx = Math.sign(ca) * Math.pow(Math.abs(ca), 2 - e) / Math.max(w[i], 1e-5); gy = Math.sign(sa) * Math.pow(Math.abs(sa), 2 - e) / Math.max(t[i], 1e-5);
      } else { x = ca * w[i]; y = sa * t[i]; gx = ca / Math.max(w[i], 1e-5); gy = sa / Math.max(t[i], 1e-5); }
      const q = i * seg + k;
      s.pos[q * 3] = P[i][0] + B[0] * x + N0[0] * y; s.pos[q * 3 + 1] = P[i][1] + B[1] * x + N0[1] * y; s.pos[q * 3 + 2] = P[i][2] + B[2] * x + N0[2] * y;
      const nn = ppV.norm([B[0] * gx + N0[0] * gy, B[1] * gx + N0[1] * gy, B[2] * gx + N0[2] * gy]);
      s.nor.set(nn, q * 3); s.tan.set(T, q * 3);
      s.uv[q * 2] = o.uvLen ? along / o.uvLen : i / (n - 1); s.uv[q * 2 + 1] = ca;
    }
  }
  let ti = 0;
  for (let i = 0; i < (closed ? n : n - 1); i++) {
    const i2 = (i + 1) % n;
    for (let k = 0; k < seg; k++) {
      const k2 = (k + 1) % seg, a = i * seg + k, b = i2 * seg + k, c = i2 * seg + k2, d = i * seg + k2;
      s.idx[ti++] = a; s.idx[ti++] = b; s.idx[ti++] = c; s.idx[ti++] = a; s.idx[ti++] = c; s.idx[ti++] = d;
    }
  }
  ppOrient(s);
  return s;
}
// make every triangle face along its vertex normals
function ppOrient(s) {
  const p = s.pos, n = s.nor, I = s.idx;
  for (let t = 0; t < I.length; t += 3) {
    const a = I[t], b = I[t + 1], c = I[t + 2];
    const ux = p[b * 3] - p[a * 3], uy = p[b * 3 + 1] - p[a * 3 + 1], uz = p[b * 3 + 2] - p[a * 3 + 2];
    const wx = p[c * 3] - p[a * 3], wy = p[c * 3 + 1] - p[a * 3 + 1], wz = p[c * 3 + 2] - p[a * 3 + 2];
    const fx = uy * wz - uz * wy, fy = uz * wx - ux * wz, fz = ux * wy - uy * wx;
    const mx = n[a * 3] + n[b * 3] + n[c * 3], my = n[a * 3 + 1] + n[b * 3 + 1] + n[c * 3 + 1], mz = n[a * 3 + 2] + n[b * 3 + 2] + n[c * 3 + 2];
    if (fx * mx + fy * my + fz * mz < 0) { I[t + 1] = c; I[t + 2] = b; }
  }
}
// any THREE geometry (lathe, box…) as a surface
function ppFromGeo(g) {
  g = g.index ? g : THREE.BufferGeometryUtils ? g : g;
  const ng = g.index ? g : null;
  const P = g.attributes.position, Nn = g.attributes.normal;
  const nt = ng ? g.index.count / 3 : P.count / 3;
  const s = ppSurf(P.count, nt);
  s.pos.set(P.array.subarray(0, P.count * 3)); s.nor.set(Nn.array.subarray(0, P.count * 3));
  if (ng) s.idx.set(g.index.array); else for (let i = 0; i < P.count; i++) s.idx[i] = i;
  return s;
}

// ---------------------------------------------------------------- skeleton & skin weights
const PP_BONES = ['base', 'hips', 'spine', 'chest', 'neck', 'head', 'clavL', 'armL', 'foreL', 'handL', 'clavR', 'armR', 'foreR', 'handR', 'thighL', 'shinL', 'footL', 'thighR', 'shinR', 'footR', 'hairB'];
const PP_PARENT = { hips: 'base', spine: 'hips', chest: 'spine', neck: 'chest', head: 'neck', clavL: 'chest', armL: 'clavL', foreL: 'armL', handL: 'foreL', clavR: 'chest', armR: 'clavR', foreR: 'armR', handR: 'foreR', thighL: 'hips', shinL: 'thighL', footL: 'shinL', thighR: 'hips', shinR: 'thighR', footR: 'shinR', hairB: 'head' };
const PP_BI = Object.fromEntries(PP_BONES.map((b, i) => [b, i]));
const PP_CHAINS = {
  torso: ['hips', 'spine', 'chest', 'clavL', 'clavR'], upper: ['spine', 'chest', 'clavL', 'clavR', 'neck'], neck: ['chest', 'neck', 'head'],
  armL: ['clavL', 'armL', 'foreL', 'handL'], armR: ['clavR', 'armR', 'foreR', 'handR'],
  legL: ['hips', 'thighL', 'shinL', 'footL'], legR: ['hips', 'thighR', 'shinR', 'footR'], skirt: ['hips', 'thighL', 'thighR'],
};
function ppSegD(c, x, y, z) {
  const ax = x - c.a[0], ay = y - c.a[1], az = z - c.a[2];
  const t = clamp((ax * c.d[0] + ay * c.d[1] + az * c.d[2]) * c.il2, 0, 1);
  return Math.hypot(ax - c.d[0] * t, ay - c.d[1] * t, az - c.d[2] * t);
}
const _ppW = new Float32Array(8);
function ppChainW(S, ch, x, y, z, acc, k) {
  const L = PP_CHAINS[ch];
  if (!L) { acc[PP_BI[ch] ?? 0] += k; return; }
  let tot = 0;
  for (let i = 0; i < L.length; i++) {
    const c = S.caps[L[i]], d = ppSegD(c, x, y, z) / c.R, e = d * d + 0.04;
    _ppW[i] = 1 / (e * e); tot += _ppW[i];
  }
  if (ch === 'skirt') {
    // robes and skirts: mostly the pelvis, the legs pull the lower hem a little
    const f = 0.55 * smooth(S.j.thighL[1], S.j.shinL[1] - 0.25 * S.u, y);
    const wl = _ppW[1] / tot, wr = _ppW[2] / tot;
    acc[PP_BI.hips] += k * (1 - f * (wl + wr)); acc[PP_BI.thighL] += k * f * wl; acc[PP_BI.thighR] += k * f * wr;
    return;
  }
  for (let i = 0; i < L.length; i++) acc[PP_BI[L[i]]] += k * _ppW[i] / tot;
}
// keep the 4 biggest influences
function ppPack(acc, s, q) {
  const n = acc.length;
  for (let r = 0; r < 4; r++) {
    let bi = -1, bw = 0;
    for (let i = 0; i < n; i++) if (acc[i] > bw) { bw = acc[i]; bi = i; }
    if (bi < 0) { s.sk[q * 4 + r] = 0; s.sw[q * 4 + r] = 0; continue; }
    s.sk[q * 4 + r] = bi; s.sw[q * 4 + r] = bw; acc[bi] = 0;
  }
  const t = s.sw[q * 4] + s.sw[q * 4 + 1] + s.sw[q * 4 + 2] + s.sw[q * 4 + 3] || 1;
  for (let r = 0; r < 4; r++) s.sw[q * 4 + r] /= t;
  if (s.sw[q * 4] === 0) { s.sk[q * 4] = PP_BI.hips; s.sw[q * 4] = 1; }
}
// weights for a generated surface following one chain (or bone)
function ppSkinChain(S, s, ch) {
  const acc = new Float32Array(PP_BONES.length);
  for (let q = 0; q < s.nv; q++) { acc.fill(0); ppChainW(S, ch, s.pos[q * 3], s.pos[q * 3 + 1], s.pos[q * 3 + 2], acc, 1); ppPack(acc, s, q); }
  return s;
}

// ---------------------------------------------------------------- layered sculpt kit
function ppKit() {
  const layers = []; let cur = null;
  const K = {
    layers,
    layer(name, o = {}) { cur = Object.assign({ name, prims: [], cell: 0.014, soft: 0.0035, ch: 'torso', m: PP_M.cloth, aoR: 0.05, field: true }, o); layers.push(cur); return cur; },
    el(c, r, col, o = {}) { const P = SDF.el(c, r, Object.assign({ k: 0.02, col: ppLin(col), m: cur.m, ch: cur.ch }, o)); cur.prims.push(P); return P; },
    rc(a, b, r1, r2, col, o = {}) { const P = SDF.rc(a, b, r1, r2, Object.assign({ k: 0.02, col: ppLin(col), m: cur.m, ch: cur.ch }, o)); cur.prims.push(P); return P; },
    sub(c, r, k = 0.01) { cur.prims.push(SDF.el(c, r, { k, sub: true })); },
    subrc(a, b, r1, r2, k = 0.01) { cur.prims.push(SDF.rc(a, b, r1, r2, { k, sub: true })); },
  };
  return K;
}
// mesh one layer and give every vertex colour / material (soft nearest primitive) and chain-blended skin weights
function ppLayerSurf(S, L) {
  const M = ppSculpt(L.prims, L.cell);
  const s = ppSurf(M.nv, M.idx.length / 3);
  s.pos = M.pos; s.nor = M.nor; s.idx = M.idx;
  const add = L.prims.filter((P) => !P.sub), boxes = add.map((P) => SDF.aabb(P)), ds = new Float64Array(add.length);
  const acc = new Float32Array(PP_BONES.length), soft = L.soft;
  for (let q = 0; q < M.nv; q++) {
    const x = M.pos[q * 3], y = M.pos[q * 3 + 1], z = M.pos[q * 3 + 2];
    let dmin = 1e9;
    for (let p = 0; p < add.length; p++) {
      const b = boxes[p];
      if (x < b[0] - 0.1 || y < b[1] - 0.1 || z < b[2] - 0.1 || x > b[3] + 0.1 || y > b[4] + 0.1 || z > b[5] + 0.1) { ds[p] = 1e9; continue; }
      ds[p] = SDF.dist(add[p], x, y, z); if (ds[p] < dmin) dmin = ds[p];
    }
    let W = 0, cr = 0, cg = 0, cb = 0, m0 = 0, m1 = 0, m2 = 0, m3 = 0, flag = 0, fw = 0;
    acc.fill(0);
    for (let p = 0; p < add.length; p++) {
      const dd = ds[p] - dmin; if (dd > 0.04) continue;
      const P = add[p], w = Math.exp(-dd / (P.soft || soft)), wb = Math.exp(-dd / 0.014);
      W += w; cr += P.col[0] * w; cg += P.col[1] * w; cb += P.col[2] * w;
      m0 += P.m[0] * w; m1 += P.m[1] * w; m2 += P.m[2] * w; m3 += P.m[3] * w;
      if (w > fw) { fw = w; flag = P.flag || 0; }
      ppChainW(S, P.ch, x, y, z, acc, wb);
    }
    if (W <= 0) { W = 1; cr = cg = cb = 1; }
    s.col[q * 3] = cr / W; s.col[q * 3 + 1] = cg / W; s.col[q * 3 + 2] = cb / W;
    s.m[q * 4] = m0 / W; s.m[q * 4 + 1] = m1 / W; s.m[q * 4 + 2] = m2 / W; s.m[q * 4 + 3] = m3 / W;
    s.uv[q * 2 + 1] = flag;
    ppPack(acc, s, q);
  }
  s.field = { sample: M.sample, b: M.bounds };
  s.aoR = L.aoR;
  return s;
}
// soft crease occlusion from every sculpted layer's field (cross-layer: under hems, collars, hair, chin, arms)
function ppAO(s, fields, R) {
  if (!R) return;
  const n = s.nv, ao = s.ao, steps = [0.3, 0.7, 1.3], sw = [1, 0.7, 0.45];
  const F = (x, y, z) => {
    let f = 1e3;
    for (const fl of fields) { const b = fl.b; if (x < b[0] || y < b[1] || z < b[2] || x > b[3] || y > b[4] || z > b[5]) continue; const v = fl.sample(x, y, z); if (v < f) f = v; }
    return f;
  };
  for (let q = 0; q < n; q++) {
    const px = s.pos[q * 3], py = s.pos[q * 3 + 1], pz = s.pos[q * 3 + 2], nx = s.nor[q * 3], ny = s.nor[q * 3 + 1], nz = s.nor[q * 3 + 2];
    let tx, ty, tz; if (Math.abs(ny) < 0.9) { tx = nz; ty = 0; tz = -nx; } else { tx = 0; ty = -nz; tz = ny; }
    const l = Math.hypot(tx, ty, tz) || 1; tx /= l; ty /= l; tz /= l;
    const bx = ny * tz - nz * ty, by = nz * tx - nx * tz, bz = nx * ty - ny * tx;
    let occ = 0, tot = 0;
    for (let d = 0; d < 5; d++) {
      let dx = nx, dy = ny, dz = nz, cs = 1;
      if (d > 0) { const a = d * Math.PI / 2 + 0.4, ca = Math.cos(a) * 0.62, sa = Math.sin(a) * 0.62; dx = nx * 0.78 + tx * ca + bx * sa; dy = ny * 0.78 + ty * ca + by * sa; dz = nz * 0.78 + tz * ca + bz * sa; cs = 0.78; }
      for (let k = 0; k < 3; k++) {
        const st = steps[k] * R, f = F(px + dx * st, py + dy * st, pz + dz * st);
        occ += clamp((st * cs - f) / st, 0, 1) * sw[k]; tot += sw[k];
      }
    }
    ao[q] = 1 - clamp(occ / tot * 1.7, 0, 0.8);
  }
  // low-frequency only: two neighbour averages
  const acc = new Float32Array(n), cnt = new Float32Array(n);
  for (let it = 0; it < 2; it++) {
    acc.fill(0); cnt.fill(0);
    for (let t = 0; t < s.idx.length; t += 3) for (let e = 0; e < 3; e++) { const a = s.idx[t + e], b = s.idx[t + (e + 1) % 3]; acc[a] += ao[b]; acc[b] += ao[a]; cnt[a]++; cnt[b]++; }
    for (let q = 0; q < n; q++) if (cnt[q]) ao[q] = (ao[q] + acc[q] / cnt[q]) * 0.5;
  }
}
function ppMerge(list) {
  let nv = 0, ni = 0;
  for (const s of list) { nv += s.nv; ni += s.idx.length; }
  const pos = new Float32Array(nv * 3), nor = new Float32Array(nv * 3), col = new Float32Array(nv * 3), m = new Float32Array(nv * 4), uv = new Float32Array(nv * 2), tan = new Float32Array(nv * 3), ao = new Float32Array(nv), sk = new Uint16Array(nv * 4), sw = new Float32Array(nv * 4), idx = new Uint32Array(ni);
  let ov = 0, oi = 0;
  for (const s of list) {
    pos.set(s.pos, ov * 3); nor.set(s.nor, ov * 3); col.set(s.col, ov * 3); m.set(s.m, ov * 4); uv.set(s.uv, ov * 2); tan.set(s.tan, ov * 3); ao.set(s.ao, ov); sk.set(s.sk, ov * 4); sw.set(s.sw, ov * 4);
    for (let i = 0; i < s.idx.length; i++) idx[oi + i] = s.idx[i] + ov;
    ov += s.nv; oi += s.idx.length;
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  g.setAttribute('normal', new THREE.BufferAttribute(nor, 3));
  g.setAttribute('color', new THREE.BufferAttribute(col, 3));
  g.setAttribute('aM', new THREE.BufferAttribute(m, 4));
  g.setAttribute('aUV2', new THREE.BufferAttribute(uv, 2));
  g.setAttribute('aTan', new THREE.BufferAttribute(tan, 3));
  g.setAttribute('aAO', new THREE.BufferAttribute(ao, 1));
  g.setAttribute('skinIndex', new THREE.Uint16BufferAttribute(sk, 4));
  g.setAttribute('skinWeight', new THREE.BufferAttribute(sw, 4));
  g.setIndex(new THREE.BufferAttribute(idx, 1));
  return g;
}
// push a point out of (or onto) a field to distance `off` from its zero set
function ppProject(F, p, off, it = 4) {
  let x = p[0], y = p[1], z = p[2];
  const h = 0.004;
  for (let i = 0; i < it; i++) {
    const f = F(x, y, z); if (f > 50) break;
    let gx = F(x + h, y, z) - F(x - h, y, z), gy = F(x, y + h, z) - F(x, y - h, z), gz = F(x, y, z + h) - F(x, y, z - h);
    const l = Math.hypot(gx, gy, gz) || 1; gx /= l; gy /= l; gz /= l;
    const e = off - f; x += gx * e; y += gy * e; z += gz * e;
    if (Math.abs(e) < 1e-4) break;
  }
  return [x, y, z];
}
function ppGrad(F, p) {
  const h = 0.004, x = p[0], y = p[1], z = p[2];
  return ppV.norm([F(x + h, y, z) - F(x - h, y, z), F(x, y + h, z) - F(x, y - h, z), F(x, y, z + h) - F(x, y, z - h)]);
}
function ppUnion(fields) {
  return (x, y, z) => {
    let f = 1e3;
    for (const fl of fields) { if (!fl) continue; const b = fl.b; if (x < b[0] || y < b[1] || z < b[2] || x > b[3] || y > b[4] || z > b[5]) continue; const v = fl.sample(x, y, z); if (v < f) f = v; }
    return f;
  };
}
