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
const PP_M = { skin: [0.2, 0.3, 1, 0], lip: [0.42, 0.5, 1, 0], cloth: [0, 0, 0, 0], satin: [0.1, 0.05, 0, 0], leather: [0.4, 0.5, 0, 0], metal: [1, 0.8, 0, 0], hair: [0, 0, 0, 1], wood: [0.12, 0.2, 0, 0], ink: [0, 0, 0, 0] };
const PP_HI = () => Settings.high && !isTouch;

// ---------------------------------------------------------------- sculpt: SDF field → surface nets (no attributes)
function ppAabb(P, cell) {
  const a = SDF.aabb(P), sh = Math.max(0, 0.02 - cell * 1.5);
  return [a[0] + sh, a[1] + sh, a[2] + sh, a[3] - sh, a[4] - sh, a[5] - sh];
}
function ppSculpt(prims, cell) {
  let x0 = 1e9, y0 = 1e9, z0 = 1e9, x1 = -1e9, y1 = -1e9, z1 = -1e9;
  for (const P of prims) if (!P.sub) { const a = ppAabb(P, cell); x0 = Math.min(x0, a[0]); y0 = Math.min(y0, a[1]); z0 = Math.min(z0, a[2]); x1 = Math.max(x1, a[3]); y1 = Math.max(y1, a[4]); z1 = Math.max(z1, a[5]); }
  x0 -= cell * 2; y0 -= cell * 2; z0 -= cell * 2; x1 += cell * 2; y1 += cell * 2; z1 += cell * 2;
  const nx = Math.ceil((x1 - x0) / cell) + 1, ny = Math.ceil((y1 - y0) / cell) + 1, nz = Math.ceil((z1 - z0) / cell) + 1;
  const N = nx * ny * nz, grid = new Float32Array(N).fill(1e3), sxy = nx * ny;
  for (const P of prims) {
    const bb = ppAabb(P, cell);
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
  const n = P.length, seg = o.seg || 6, closed = !!o.closed, shape = o.shape || 'lens', caps = !closed && o.caps !== false;
  const rings = n, nv = rings * seg + (caps ? 2 : 0), nt = (closed ? n : n - 1) * seg * 2 + (caps ? seg * 2 : 0);
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
  if (caps) {
    // close both ends with a fan (open tubes would show their inside as dark ink)
    for (let e = 0; e < 2; e++) {
      const i = e ? n - 1 : 0, q = rings * seg + e, Tn = ppV.norm(ppV.sub(P[e ? n - 1 : 1], P[e ? n - 2 : 0]));
      s.pos.set(P[i], q * 3); s.nor.set(e ? Tn : ppV.mul(Tn, -1), q * 3); s.tan.set(Tn, q * 3);
      s.uv[q * 2] = e ? s.uv[(i * seg) * 2] : 0; s.uv[q * 2 + 1] = 0;
      for (let k = 0; k < seg; k++) { s.idx[ti++] = q; s.idx[ti++] = i * seg + k; s.idx[ti++] = i * seg + (k + 1) % seg; }
    }
    // cap normals: use the ring's average so the shading does not pop
    for (let e = 0; e < 2; e++) { const i = e ? n - 1 : 0, q = rings * seg + e; let a = [0, 0, 0]; for (let k = 0; k < seg; k++) a = ppV.add(a, [s.nor[(i * seg + k) * 3], s.nor[(i * seg + k) * 3 + 1], s.nor[(i * seg + k) * 3 + 2]]); if (ppV.len(a) > 1e-3) s.nor.set(ppV.norm(ppV.add(ppV.norm(a), [s.nor[q * 3], s.nor[q * 3 + 1], s.nor[q * 3 + 2]])), q * 3); }
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
      if (x < b[0] - 0.045 || y < b[1] - 0.045 || z < b[2] - 0.045 || x > b[3] + 0.045 || y > b[4] + 0.045 || z > b[5] + 0.045) { ds[p] = 1e9; continue; }
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
function ppAO(s, fields0, R) {
  if (!R) return;
  const n = s.nv, ao = s.ao, steps = [0.45, 1.1], sw = [1, 0.6];
  let bx0 = 1e9, by0 = 1e9, bz0 = 1e9, bx1 = -1e9, by1 = -1e9, bz1 = -1e9;
  for (let q = 0; q < n; q++) { const x = s.pos[q * 3], y = s.pos[q * 3 + 1], z = s.pos[q * 3 + 2]; if (x < bx0) bx0 = x; if (y < by0) by0 = y; if (z < bz0) bz0 = z; if (x > bx1) bx1 = x; if (y > by1) by1 = y; if (z > bz1) bz1 = z; }
  const m = R * 1.4, fields = fields0.filter((f) => f && !(f.b[0] > bx1 + m || f.b[3] < bx0 - m || f.b[1] > by1 + m || f.b[4] < by0 - m || f.b[2] > bz1 + m || f.b[5] < bz0 - m));
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
      for (let k = 0; k < 2; k++) {
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
  if (window.__ppDebug) list.forEach((s, i) => { let bad = 0; for (let q = 0; q < s.pos.length; q++) if (!Number.isFinite(s.pos[q])) bad++; if (bad) console.log('LAB nan surf', i, s.nv, bad, s.tag || ''); });
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

// ---------------------------------------------------------------- proportions & joints (rest pose, feet on y = 0, facing +z)
function ppSpec(C) {
  const kid = !!C.kid, elder = !!C.beard, guard = !!(C.robe && C.hat === 'hood'), fem = !!C.long && !elder && !kid, hero = !!C.pin, trav = C.hat === 'wide';
  const H = kid ? 1.3 : elder ? 1.96 : guard ? (fem ? 2.08 : 2.14) : fem ? 1.97 : hero ? 2.05 : 2.0;
  const heads = kid ? 4.3 : elder ? 6.6 : guard ? 7.0 : fem ? 6.8 : hero ? 7.0 : 6.85;
  const u = H / heads;
  const A = kid ? { neck: 0.13, sh: 0.4, chest: 1.62, waist: 2.05, hips: 2.33, hipJ: 2.52 } : { neck: 0.26, sh: 0.47, chest: 2.0, waist: 2.75, hips: 3.18, hipJ: hero ? 3.42 : 3.48 };
  const W = kid ? { sh: 0.6, chest: 0.5, chestD: 0.36, waist: 0.46, waistD: 0.36, hip: 0.48, hipD: 0.37, hipX: 0.27, neck: 0.15, arm: [0.13, 0.105, 0.11, 0.085], leg: [0.2, 0.14, 0.15, 0.1] }
    : fem ? { sh: 0.7, chest: 0.52, chestD: 0.34, waist: 0.36, waistD: 0.27, hip: 0.58, hipD: 0.37, hipX: 0.36, neck: 0.15, arm: [0.13, 0.105, 0.11, 0.08], leg: [0.3, 0.17, 0.18, 0.1] }
    : { sh: hero ? 0.8 : guard ? 0.86 : elder ? 0.72 : 0.77, chest: hero ? 0.64 : guard ? 0.7 : 0.6, chestD: 0.37, waist: hero ? 0.43 : elder ? 0.5 : 0.47, waistD: elder ? 0.37 : 0.31, hip: 0.5, hipD: 0.35, hipX: 0.32, neck: 0.18, arm: [0.165, 0.13, 0.14, 0.1], leg: [0.3, 0.185, 0.2, 0.115] };
  const y = (h) => H - h * u, shY = y(1 + A.sh), j = {};
  j.base = [0, 0, 0];
  j.hips = [0, y(A.hips), 0];
  j.spine = [0, y(A.waist), 0];
  j.chest = [0, y(A.chest + 0.1), -0.02 * u];
  j.neck = [0, y(1 + A.neck), -0.05 * u];
  j.head = [0, y(1) + 0.12 * u, -0.06 * u];
  const a0 = kid ? 0.24 : 0.2, Lu = (kid ? 0.95 : 1.3) * u, Lf = (kid ? 0.82 : 1.12) * u, Lh = (kid ? 0.6 : 0.72) * u;
  for (const s of [1, -1]) {
    const X = s > 0 ? 'L' : 'R';
    j['clav' + X] = [s * 0.1 * u, shY + 0.05 * u, 0.02 * u];
    const sh = [s * W.sh * u, shY, -0.03 * u];
    j['arm' + X] = sh;
    const el = ppV.add(sh, ppV.mul(ppV.norm([s * Math.sin(a0), -Math.cos(a0), -0.02]), Lu));
    j['fore' + X] = el;
    const fd = ppV.norm([s * Math.sin(a0 * 0.7), -Math.cos(a0 * 0.7), 0.17]);
    j['hand' + X] = ppV.add(el, ppV.mul(fd, Lf));
    j['tip' + X] = ppV.add(j['hand' + X], ppV.mul(fd, Lh));
    const hj = [s * W.hipX * u, y(A.hipJ), 0];
    j['thigh' + X] = hj;
    j['shin' + X] = [s * (W.hipX + 0.02) * u, hj[1] * 0.52, 0.03 * u];
    j['foot' + X] = [s * (W.hipX + 0.035) * u, 0.3 * u, -0.05 * u];
    j['toe' + X] = [s * (W.hipX + 0.06) * u, 0.06 * u, 0.62 * u];
  }
  j.hairB = [0, y(0.55), -0.32 * u];
  const cap = (a, b, R) => { const d = ppV.sub(b, a); return { a, d, il2: 1 / Math.max(ppV.dot(d, d), 1e-8), R: R * u }; };
  const caps = { base: cap([0, 0, 0], [0, 0.01, 0], 1), hips: cap(j.hips, j.spine, 0.5), spine: cap(j.spine, j.chest, 0.45), chest: cap(j.chest, j.neck, 0.55), neck: cap(j.neck, j.head, 0.2), head: cap(j.head, [0, H, 0], 0.4), hairB: cap(j.hairB, [0, j.hairB[1] - u, -0.45 * u], 0.3) };
  for (const X of ['L', 'R']) {
    caps['clav' + X] = cap(j['clav' + X], j['arm' + X], 0.18); caps['arm' + X] = cap(j['arm' + X], j['fore' + X], 0.17);
    caps['fore' + X] = cap(j['fore' + X], j['hand' + X], 0.14); caps['hand' + X] = cap(j['hand' + X], j['tip' + X], 0.12);
    caps['thigh' + X] = cap(j['thigh' + X], j['shin' + X], 0.3); caps['shin' + X] = cap(j['shin' + X], j['foot' + X], 0.2); caps['foot' + X] = cap(j['foot' + X], j['toe' + X], 0.16);
  }
  const eyeW = kid ? 0.235 : fem ? 0.205 : elder ? 0.165 : 0.19;
  return { C, H, u, kid, elder, guard, fem, hero, trav, robe: !!C.robe, W, j, hc: [0, H - 0.5 * u, 0], shY, caps, A, eyeW, eyeY: kid ? -0.1 : -0.06, Q: PP_HI() ? 1 : 1.5 };
}

// ---------------------------------------------------------------- face: one fine layer (skull, brow, cheekbones, nose, lips, jaw, ears, neck)
function ppFace(K, S, C) {
  const u = S.u, hc = S.hc;
  const P = (x, y, z) => [hc[0] + x * u, hc[1] + y * u, hc[2] + z * u], R = (x, y, z) => [x * u, y * u, z * u], k = (v, o = {}) => Object.assign({ k: v * u }, o);
  const skin = C.skin, lip = ppHex(ppMixC(ppLin(C.skin), ppLin(0xb04858), S.fem ? 0.42 : S.kid ? 0.3 : 0.2));
  const L = K.layer('face', { cell: u * 0.018 * S.Q, ch: 'head', m: PP_M.skin, aoR: 0.07 * u, soft: 0.0016 });
  if (S.kid) {
    K.el(P(0, 0.06, -0.05), R(0.4, 0.45, 0.46), skin, k(0.1));
    for (const s of [-1, 1]) K.el(P(s * 0.19, -0.17, 0.15), R(0.17, 0.16, 0.17), skin, k(0.14));
    K.el(P(0, -0.3, 0.15), R(0.21, 0.17, 0.2), skin, k(0.14));
    for (const s of [-1, 1]) K.el(P(s * 0.15, 0.03, 0.32), R(0.12, 0.04, 0.06), skin, k(0.08));
    K.rc(P(0, -0.04, 0.37), P(0, -0.13, 0.42), 0.022 * u, 0.03 * u, skin, k(0.05));
    K.el(P(0, -0.14, 0.42), R(0.04, 0.034, 0.034), skin, k(0.04));
    K.el(P(0, -0.27, 0.355), R(0.06, 0.02, 0.03), lip, k(0.03, { m: PP_M.lip }));
    K.el(P(0, -0.3, 0.35), R(0.055, 0.024, 0.03), lip, k(0.03, { m: PP_M.lip }));
    for (const s of [-1, 1]) { K.el(P(s * 0.4, -0.06, -0.03), R(0.06, 0.13, 0.085), skin, k(0.04)); K.sub(P(s * 0.44, -0.05, 0.0), R(0.03, 0.075, 0.05), 0.02 * u); }
    K.rc(P(0, -0.38, -0.13), P(0, -0.95, -0.09), S.W.neck * u, (S.W.neck + 0.02) * u, skin, k(0.12, { ch: 'neck' }));
  } else {
    const f = S.fem, e = S.elder;
    K.el(P(0, 0.08, -0.06), R(f ? 0.32 : 0.335, 0.42, 0.43), skin, k(0.1));
    K.el(P(0, 0.13, 0.1), R(0.28, 0.25, 0.25), skin, k(0.1));
    K.el(P(0, -0.1, 0.14), R(f ? 0.255 : 0.265, 0.26, 0.21), skin, k(0.1));
    for (const s of [-1, 1]) {
      K.rc(P(s * 0.24, -0.1, -0.06), P(s * (f ? 0.07 : 0.08), -0.385, 0.16), (f ? 0.08 : 0.095) * u, (f ? 0.045 : 0.06) * u, skin, k(0.1));
      K.el(P(s * 0.17, f ? -0.05 : -0.06, 0.22), R(0.1, 0.065, 0.09), skin, k(0.07));
      K.el(P(s * 0.14, 0.075, 0.27), R(0.12, e ? 0.055 : 0.045, e ? 0.07 : 0.06), skin, k(0.06));
      K.el(P(s * 0.335, -0.03, -0.03), R(0.055, 0.14, 0.085), skin, k(0.04));
      K.sub(P(s * 0.37, -0.03, 0.0), R(0.03, 0.085, 0.05), 0.02 * u);
    }
    K.el(P(0, f ? -0.41 : -0.415, f ? 0.17 : 0.18), R(f ? 0.075 : 0.09, f ? 0.055 : 0.065, f ? 0.065 : 0.075), skin, k(0.08));
    K.el(P(0, -0.24, 0.2), R(0.14, 0.12, 0.13), skin, k(0.08));
    const ns = f ? 0.85 : e ? 1.15 : 1;
    K.rc(P(0, -0.03, 0.3), P(0, -0.12, 0.305 + 0.05 * ns), 0.02 * u * ns, 0.03 * u * ns, skin, k(0.06));
    K.el(P(0, -0.135, 0.315 + 0.05 * ns), R(0.036 * ns, 0.031 * ns, 0.033 * ns), skin, k(0.04));
    for (const s of [-1, 1]) K.el(P(s * 0.034 * ns, -0.152, 0.33), R(0.026 * ns, 0.022 * ns, 0.024), skin, k(0.03));
    K.el(P(0, -0.25, 0.312), R(f ? 0.07 : 0.075, f ? 0.026 : 0.021, 0.035), lip, k(0.03, { m: PP_M.lip }));
    K.el(P(0, -0.283, 0.302), R(f ? 0.064 : 0.066, f ? 0.032 : 0.026, 0.034), lip, k(0.03, { m: PP_M.lip }));
    K.rc(P(0, -0.42, -0.12), P(0, -1.0, -0.08), S.W.neck * u, (S.W.neck + 0.02) * u, skin, k(0.12, { ch: 'neck' }));
  }
  // eye sockets: find the face surface along each eye axis, sink the eyeball 0.8 R behind it, carve the socket
  const Rr = S.eyeW * u / 1.68;
  S.eyes = [];
  for (const s of [1, -1]) {
    const yaw = s * 0.14, ax = [Math.sin(yaw), 0, Math.cos(yaw)];
    const base = P(s * S.eyeW, S.eyeY, 0);
    let zs = null;
    for (let t = 0.7 * u; t > -0.2 * u; t -= 0.004 * u) { const p = ppV.add(base, ppV.mul(ax, t)); if (ppField(L.prims, p[0], p[1], p[2]) < 0) { zs = t; break; } }
    const c = ppV.add(base, ppV.mul(ax, (zs ?? 0.3 * u) - 0.8 * Rr));
    S.eyes.push({ s, c, yaw, R: Rr });
  }
  for (const E of S.eyes) K.sub(E.c, [E.R * 1.15, E.R * 1.15, E.R * 1.15], E.R * 0.25);
  return L;
}

// ---------------------------------------------------------------- garments
function ppTorso(K, S, o, col, opt = {}) {
  const u = S.u, j = S.j, W = S.W;
  K.el([0, j.chest[1] + 0.1 * u, -0.03 * u], [W.chest * u + o, 0.6 * u + o, W.chestD * u + o], col, { k: 0.12 * u });
  K.el([0, j.spine[1], 0], [W.waist * u + o, 0.6 * u + o, W.waistD * u + o], col, { k: 0.15 * u });
  if (opt.pelvis !== false) K.el([0, j.hips[1] - 0.06 * u, -0.02 * u], [W.hip * u + o + (opt.hipX || 0), 0.42 * u + o, W.hipD * u + o + (opt.hipZ || 0)], col, { k: 0.14 * u });
  if (S.fem && !S.kid) for (const s of [-1, 1]) K.el([s * 0.17 * u, j.chest[1] + 0.02 * u, 0.12 * u], [0.17 * u + o, 0.16 * u + o, 0.15 * u + o], col, { k: 0.1 * u });
  else if (!S.kid) for (const s of [-1, 1]) K.el([s * 0.19 * u, j.chest[1] + 0.12 * u, 0.1 * u], [0.2 * u + o, 0.16 * u + o, 0.13 * u + o], col, { k: 0.1 * u });
  for (const s of [-1, 1]) {
    const X = s > 0 ? 'L' : 'R';
    K.rc([s * 0.13 * u, j.neck[1] - 0.04 * u, -0.07 * u], [s * (W.sh - 0.1) * u, S.shY + 0.0 * u, -0.05 * u], 0.12 * u + o, 0.18 * u + o, col, { k: 0.1 * u, ch: 'upper' });
    K.el([s * (W.sh - 0.01) * u, S.shY - 0.05 * u, -0.03 * u], [0.18 * u + o, 0.2 * u + o, 0.19 * u + o], col, { k: 0.08 * u, ch: 'arm' + X });
  }
}
function ppSleeve(K, S, s, o, col, opt = {}) {
  const u = S.u, j = S.j, X = s > 0 ? 'L' : 'R', a = S.W.arm;
  const sh = j['arm' + X], el = j['fore' + X], wr = j['hand' + X];
  K.rc(sh, el, a[0] * u + o, a[1] * u + o, col, { k: 0.06 * u, ch: 'arm' + X });
  if (opt.upperOnly) return;
  const end = ppV.lerp(el, wr, opt.len ?? 0.92);
  K.rc(el, end, a[2] * u + o, a[3] * u + o + (opt.flare || 0), col, { k: 0.05 * u, ch: 'arm' + X });
  if (opt.puff) K.el(ppV.lerp(sh, el, 0.15), [0.26 * u, 0.24 * u, 0.24 * u], col, { k: 0.08 * u, ch: 'arm' + X });
}
function ppLeg(K, S, s, o, col, yEnd, opt = {}) {
  const u = S.u, j = S.j, X = s > 0 ? 'L' : 'R', g = S.W.leg;
  const hj = j['thigh' + X], kn = j['shin' + X], an = j['foot' + X];
  K.rc(hj, kn, g[0] * u + o, g[1] * u + o, col, { k: 0.08 * u, ch: 'leg' + X });
  if (opt.thighOnly) return;
  const t = clamp((kn[1] - yEnd) / (kn[1] - an[1]), 0, 1), end = ppV.lerp(kn, an, t);
  K.rc(kn, end, g[2] * u + o, lerp(g[2], g[3], t) * u + o + (opt.flare || 0), col, { k: 0.06 * u, ch: 'leg' + X });
  K.el(ppV.add(ppV.lerp(kn, an, 0.28), [0, 0, -0.06 * u]), [(g[2] + 0.01) * u + o, 0.32 * u, (g[2] - 0.02) * u + o], col, { k: 0.08 * u, ch: 'leg' + X });
}
// cut everything below a horizontal plane (hems) or above it
function ppCutBelow(K, y, k = 0.006) { K.sub([0, y - 3, 0], [4, 3, 4], k); }
function ppCutAbove(K, y, k = 0.006) { K.sub([0, y + 3, 0], [4, 3, 4], k); }
function ppFoot(K, S, s, col, o, opt = {}) {
  const u = S.u, X = s > 0 ? 'L' : 'R', an = S.j['foot' + X], toe = S.j['toe' + X];
  const ch = 'leg' + X;
  K.rc([an[0], 0.2 * u, an[2] - 0.2 * u], [toe[0], 0.15 * u, toe[2] - 0.12 * u], 0.17 * u + o, 0.15 * u + o, col, { k: 0.05 * u, ch });
  K.el([toe[0], 0.13 * u, toe[2] - 0.12 * u], [0.155 * u + o, 0.13 * u + o, 0.17 * u + o], col, { k: 0.06 * u, ch });
  K.el([an[0], 0.22 * u, an[2] - 0.13 * u], [0.16 * u + o, 0.2 * u + o, 0.17 * u + o], col, { k: 0.06 * u, ch });
  if (opt.shaft) K.rc([an[0], opt.shaft, an[2] + 0.01 * u], [an[0], 0.25 * u, an[2] - 0.04 * u], opt.r1, opt.r2, col, { k: 0.06 * u, ch });
}
function ppSole(K, S, s, col) {
  const u = S.u, X = s > 0 ? 'L' : 'R', an = S.j['foot' + X], toe = S.j['toe' + X];
  K.rc([an[0], 0.04 * u, an[2] - 0.22 * u], [toe[0], 0.04 * u, toe[2] - 0.08 * u], 0.19 * u, 0.17 * u, col, { k: 0.04 * u, ch: 'leg' + X, m: PP_M.leather });
}

// ---------------------------------------------------------------- hands (canonical: wrist at 0, fingers −y, palm −x, thumb +z), relaxed or gripping
function ppHand(S, C, s, glove) {
  const u = S.u, X = s > 0 ? 'L' : 'R', grip = !!(C.staff && s < 0);
  const K = ppKit(); K.layer('hand', { cell: u * 0.02 * S.Q, ch: 'hand' + X, m: PP_M.skin, soft: 0.0015 });
  const skin = C.skin, sc = S.kid ? 0.92 : S.fem ? 0.9 : 1, U = (v) => v * u * sc;
  const gcol = glove ? C.glove : skin, gm = glove ? { m: PP_M.leather } : {};
  K.rc([0, U(0.06), 0], [0, U(-0.06), 0.0], U(0.1), U(0.105), gcol, Object.assign({ k: U(0.05) }, gm));
  K.el([U(-0.005), U(-0.2), U(0.0)], [U(0.068), U(0.19), U(0.145)], gcol, Object.assign({ k: U(0.06) }, gm));
  const fz = [0.105, 0.036, -0.034, -0.1], fl = [0.29, 0.32, 0.3, 0.24], fr = [0.044, 0.045, 0.043, 0.038];
  for (let f = 0; f < 4; f++) {
    let p = [U(-0.01), U(-0.36 + Math.abs(f - 1.3) * 0.02), U(fz[f])], dir = [0, -1, 0];
    const bends = grip ? [1.05, 1.2, 0.85] : [0.18 + f * 0.05, 0.32 + f * 0.04, 0.26];
    let ang = 0;
    for (let q = 0; q < 3; q++) {
      ang += bends[q];
      dir = [-Math.sin(ang), -Math.cos(ang), (fz[f] > 0 ? 0.02 : -0.03) * (q + 1)];
      const L = U(fl[f] * [0.42, 0.33, 0.25][q]);
      const p2 = ppV.add(p, ppV.mul(ppV.norm(dir), L));
      const r1 = U(fr[f] * (1 - q * 0.1)), r2 = U(fr[f] * (0.92 - q * 0.12));
      K.rc(p, p2, r1, r2, q === 0 && glove ? C.glove : skin, Object.assign({ k: U(0.02) }, q === 0 && glove ? { m: PP_M.leather } : {}));
      p = p2;
    }
  }
  // thumb
  {
    let p = [U(-0.03), U(-0.1), U(0.11)];
    const d1 = ppV.norm(grip ? [-0.75, -0.45, 0.45] : [-0.35, -0.62, 0.7]), d2 = ppV.norm(grip ? [-0.8, -0.55, -0.1] : [-0.3, -0.85, 0.42]);
    const p1 = ppV.add(p, ppV.mul(d1, U(0.17))), p2 = ppV.add(p1, ppV.mul(d2, U(0.15)));
    K.rc(p, p1, U(0.06), U(0.048), glove ? C.glove : skin, Object.assign({ k: U(0.04) }, gm));
    K.rc(p1, p2, U(0.047), U(0.04), skin, { k: U(0.02) });
  }
  const sf = ppLayerSurf(S, K.layers[0]);
  // into the forearm frame: canonical +y → towards the elbow, +x → outward, +z → forward
  const wr = S.j['hand' + X], el = S.j['fore' + X];
  const Y = ppV.norm(ppV.sub(el, wr)), X0 = [1, 0, 0];
  const Xw = ppV.norm(ppV.sub(X0, ppV.mul(Y, ppV.dot(X0, Y)))), Z = ppV.cross(Xw, Y);
  const wrL = [Math.abs(wr[0]), wr[1], wr[2]];
  const YL = [Math.abs(Y[0]) * Math.sign(Y[0] * s) || 0, Y[1], Y[2]];
  const XL = ppV.norm(ppV.sub(X0, ppV.mul(YL, ppV.dot(X0, YL)))), ZL = ppV.cross(XL, YL);
  ppXform(sf, XL, YL, ZL, wrL);
  if (s < 0) ppMirror(sf);
  // weights: rigid hand, blending into the forearm at the wrist
  const acc = new Float32Array(PP_BONES.length), hb = PP_BI['hand' + X], fb = PP_BI['fore' + X];
  for (let q = 0; q < sf.nv; q++) {
    const d = ppV.dot(ppV.sub([sf.pos[q * 3], sf.pos[q * 3 + 1], sf.pos[q * 3 + 2]], wr), ppV.mul(Y, -1));
    const w = smooth(-0.06 * u, 0.04 * u, d);
    acc.fill(0); acc[hb] = w; acc[fb] = 1 - w; ppPack(acc, sf, q);
  }
  sf.field = null; sf.aoR = 0;
  return sf;
}

// ---------------------------------------------------------------- generated trims: rings (belts, cuffs, collars, hems), straps, strands
// ring around axis `ax` through c, resting on field F (marched in from r0·1.8); open at the front when o.gap (radians)
function ppRing(F, c, ax, r0, hw, ht, o = {}) {
  ax = ppV.norm(ax);
  const fz = ppV.sub([0, 0, 1], ppV.mul(ax, ax[2]));
  const e1 = ppV.len(fz) > 1e-3 ? ppV.norm(fz) : [1, 0, 0], e2 = ppV.cross(ax, e1);
  const n = o.n || 32, gap = o.gap || 0, closed = !gap, N = closed ? n : n + 1, off = o.off ?? ht * 0.55;
  const pts = [], ups = [];
  for (let i = 0; i < N; i++) {
    const a = closed ? (i / n) * Math.PI * 2 : gap + (Math.PI * 2 - 2 * gap) * (i / n);
    const dir = ppV.add(ppV.mul(e1, Math.cos(a)), ppV.mul(e2, Math.sin(a)));
    let r = r0 * (o.start ?? 1.8), hit = r0, st = r0 * 0.03;
    for (; r > 0; r -= st) { const p = ppV.add(c, ppV.mul(dir, r)); if (F(p[0], p[1], p[2]) < off) { let lo = r, hi = r + st; for (let b = 0; b < 6; b++) { const m = (lo + hi) / 2, q = ppV.add(c, ppV.mul(dir, m)); if (F(q[0], q[1], q[2]) < off) lo = m; else hi = m; } hit = (lo + hi) / 2; break; } }
    pts.push(ppV.add(c, ppV.mul(dir, hit + (o.lift || 0)))); ups.push(dir);
  }
  const s = ppSweep(pts, pts.map(() => hw), pts.map(() => ht), (i) => ups[i], { closed, shape: 'flat', seg: o.seg || 8, uvLen: o.stitch ? 0.012 : 0 });
  return s;
}
// strap along control points, hugging F
function ppStrap(F, ctrl, hw, ht, o = {}) {
  const pts = [], n = o.n || 22;
  for (let i = 0; i < n; i++) {
    const t = (i / (n - 1)) * (ctrl.length - 1), k = Math.min(Math.floor(t), ctrl.length - 2), f = t - k;
    const p0 = ctrl[Math.max(0, k - 1)], p1 = ctrl[k], p2 = ctrl[k + 1], p3 = ctrl[Math.min(ctrl.length - 1, k + 2)];
    const cr = (a) => 0.5 * ((2 * p1[a]) + (-p0[a] + p2[a]) * f + (2 * p0[a] - 5 * p1[a] + 4 * p2[a] - p3[a]) * f * f + (-p0[a] + 3 * p1[a] - 3 * p2[a] + p3[a]) * f * f * f);
    pts.push(ppProject(F, [cr(0), cr(1), cr(2)], o.off ?? ht * 0.6, 6));
  }
  return ppSweep(pts, pts.map(() => hw), pts.map(() => ht), (i) => ppGrad(F, pts[i]), { shape: 'flat', seg: 8, uvLen: o.stitch ? 0.012 : 0 });
}
// colour / material / flags / weights for a generated surface
function ppDress(S, s, col, m, ch, o = {}) {
  ppFill(s, col, m);
  if (o.stitch) for (let q = 0; q < s.nv; q++) s.uv[q * 2 + 1] = 1.5 + 0.49 * clamp(s.uv[q * 2 + 1], -1, 1);
  else if (o.flag !== undefined) for (let q = 0; q < s.nv; q++) s.uv[q * 2 + 1] = o.flag;
  else for (let q = 0; q < s.nv; q++) s.uv[q * 2 + 1] = 0;
  return ppSkinChain(S, s, ch);
}

// ---------------------------------------------------------------- hair: lens clumps grown over the scalp
function ppHair(S, C, FH, FB, out) {
  const u = S.u, hc = S.hc, hi = S.Q === 1;
  let col = ppLin(C.hair); { const l = 0.2126 * col[0] + 0.7152 * col[1] + 0.0722 * col[2]; if (l < 0.04) col = ppV.add(ppV.mul(col, 0.04 / Math.max(l, 1e-4) * 0.7), [0.006, 0.006, 0.008]); }
  const rnd = mulberry32(((C.hair * 7) ^ ((C.skin || 0) >> 3) ^ (S.kid ? 99 : 0)) >>> 0);
  const style = S.kid ? 'kid' : S.elder ? 'elder' : S.guard ? 'hood' : S.fem ? 'long' : S.trav ? 'hat' : 'short';
  const F = (x, y, z) => Math.min(FH(x, y, z), FB(x, y, z));
  const W = ppV.norm([0, 0.8, -0.6]);
  const taper = (t) => (t < 0.14 ? Math.sqrt(t / 0.14) : 1) * Math.pow(1 - t, 0.65) * (1 + 0.25 * Math.sin(Math.PI * Math.min(1, t * 1.6)));
  const clump = (root, dir0, len, w0, o = {}) => {
    const n = hi ? 9 : 6, pts = [], ws = [], ts = [];
    let p = ppProject(FH, root, -0.012 * u, 5), d = ppV.norm(dir0);
    for (let i = 0; i < n; i++) {
      const t = i / (n - 1), tp = taper(t);
      pts.push(p); ws.push(w0 * tp); ts.push(w0 * (o.flat ?? 0.4) * tp);
      if (i === n - 1) break;
      const g = ppGrad(F, p);
      d = ppV.norm(ppV.add(ppV.add(d, [0, -(o.grav ?? 0.5) / n * 2.2, 0]), ppV.mul(g, (o.lift ?? 0.2) * (1 - t) / n * 3 + (o.flick ?? 0) * t * t / n * 4)));
      if (o.curl) d = ppV.norm(ppV.add(d, ppV.mul(o.curl, 1 / n)));
      const dn = ppV.dot(d, g); if (dn < -0.05 && t < 0.85) d = ppV.norm(ppV.sub(d, ppV.mul(g, dn + 0.05)));
      p = ppV.add(p, ppV.mul(d, len / (n - 1)));
      const off = w0 * (o.flat ?? 0.4) * taper(t + 1 / n) + 0.006 * u + (o.hover || 0) * Math.sin(Math.PI * t);
      const f = F(p[0], p[1], p[2]);
      if (f < off) { const g2 = ppGrad(F, p); p = ppV.add(p, ppV.mul(g2, off - f)); }
    }
    const s = ppSweep(pts, ws, ts, (i) => ppGrad(F, pts[i]), { seg: hi ? 6 : 4, shape: 'lens' });
    for (let q = 0; q < s.nv; q++) {
      const x = s.pos[q * 3] - hc[0], y = s.pos[q * 3 + 1] - hc[1] - 0.05 * u, z = s.pos[q * 3 + 2] - hc[2] + 0.04 * u;
      const ne = ppV.norm([x / 0.16, y / 0.25, z / 0.2]), k = o.smoothN ?? 0.6;
      s.nor.set(ppV.norm(ppV.lerp([s.nor[q * 3], s.nor[q * 3 + 1], s.nor[q * 3 + 2]], ne, k)), q * 3);
    }
    const shade = 0.94 + rnd() * 0.12, cc = ppV.mul(col, shade);
    ppFill(s, cc, PP_M.hair);
    for (let q = 0; q < s.nv; q++) { const t = s.uv[q * 2]; s.uv[q * 2 + 1] = 4 + s.uv[q * 2 + 1]; s.ao[q] = 0.62 + 0.38 * smooth(0, 0.4, t); }
    const acc = new Float32Array(PP_BONES.length), sp = o.spring || 0;
    for (let q = 0; q < s.nv; q++) {
      const t = s.uv[q * 2], w = sp * smooth(0.2, 0.85, t);
      acc.fill(0); acc[PP_BI.head] = 1 - w; acc[PP_BI.hairB] = w;
      if (o.chain) { acc.fill(0); ppChainW(S, o.chain, s.pos[q * 3], s.pos[q * 3 + 1], s.pos[q * 3 + 2], acc, 1); }
      ppPack(acc, s, q);
    }
    out.push(s);
  };
  const sph = (az, el) => [Math.sin(az) * Math.cos(el), Math.sin(el), Math.cos(az) * Math.cos(el)];
  const rootAt = (az, el) => ppV.add(hc, ppV.mul(sph(az, el), 0.5 * u));
  const deg = Math.PI / 180, J = (a) => (rnd() - 0.5) * a;
  // crown flow: long clumps fanning out from the whorl over the skull, so their tips end only at the hairline,
  // over the ears and at the nape (a smooth top with strand definition, spiky only at the perimeter)
  const Wd = ppV.norm([0.06, 0.86, -0.5]), e1 = ppV.norm(ppV.sub([0, 0, 1], ppV.mul(Wd, Wd[2]))), e2 = ppV.cross(Wd, e1);
  const flow = (n, pol0, pol1, lenF, w0, o = {}) => {
    for (let i = 0; i < n; i++) {
      const a = (i / n) * Math.PI * 2 + J(0.25), pol = pol0 + (pol1 - pol0) * rnd();
      let A = a % (Math.PI * 2); if (A > Math.PI) A -= Math.PI * 2;
      const rad = ppV.add(ppV.mul(e1, Math.cos(a)), ppV.mul(e2, Math.sin(a)));
      const rd = ppV.norm(ppV.add(ppV.mul(Wd, Math.cos(pol)), ppV.mul(rad, Math.sin(pol))));
      const fd = ppV.norm(ppV.sub(ppV.mul(rad, Math.cos(pol)), ppV.mul(Wd, Math.sin(pol))));
      clump(ppV.add(hc, ppV.mul(rd, 0.5 * u)), fd, lenF(A) * u * (0.9 + rnd() * 0.2), w0 * (0.9 + rnd() * 0.25), o);
    }
  };
  const ring = (n, el0, el1, len, w0, o = {}) => {
    for (let i = 0; i < n; i++) {
      const az = (i / n) * Math.PI * 2 + J(0.3), el = (el0 + (el1 - el0) * rnd()) * deg;
      let A = az % (Math.PI * 2); if (A > Math.PI) A -= Math.PI * 2;
      if (Math.abs(A) < (o.front ?? 70) * deg) continue;
      clump(rootAt(az, el), [Math.sin(az) * 0.3, -0.9, Math.cos(az) * 0.3], len * (0.85 + rnd() * 0.3), w0, Object.assign({ grav: 1.0, lift: 0.1, flat: 0.38 }, o));
    }
  };
  const bangs = (n, len, w0, o = {}) => {
    const part = o.part ?? 0.25;
    for (let i = 0; i < n; i++) {
      const t = i / (n - 1), az = (-50 + 100 * t + J(6)) * deg, el = (o.el ?? 50) * deg;
      const side = Math.sin(az - part);
      const L = len * (0.82 + 0.3 * Math.sin(Math.PI * t) + rnd() * 0.15);
      clump(rootAt(az, el), [side * 0.4 + J(0.15), -0.5, 0.85], L, w0 * (0.9 + rnd() * 0.2), Object.assign({ grav: 0.9, lift: 0.15, flick: 0.12, flat: 0.34 }, o));
    }
  };
  const sideLen = (A, f, sd, b) => { const c = Math.abs(A) / Math.PI; return c < 0.25 ? lerp(f, sd, smooth(0.0, 0.25, c)) : lerp(sd, b, smooth(0.3, 0.85, c)); };
  if (style === 'short') {
    flow(hi ? 38 : 22, 0.05, 0.4, (A) => sideLen(A, 0.95, 0.8, 1.0), 0.21 * u, { grav: 0.6, lift: 0.05, flick: 0.4, flat: 0.34 });
    ring(hi ? 14 : 8, 0, 22, 0.4 * u, 0.16 * u, { flick: 0.3 });
    bangs(hi ? 8 : 5, 0.52 * u, 0.15 * u, { flick: 0.2 });
  } else if (style === 'kid') {
    flow(hi ? 34 : 20, 0.05, 0.4, (A) => sideLen(A, 0.85, 0.72, 0.8), 0.22 * u, { grav: 0.5, lift: 0.08, flick: 0.6, flat: 0.36 });
    ring(hi ? 12 : 7, -2, 20, 0.34 * u, 0.16 * u, { flick: 0.4 });
    bangs(hi ? 7 : 5, 0.42 * u, 0.15 * u, { flick: 0.3 });
  } else if (style === 'long') {
    flow(hi ? 40 : 24, 0.05, 0.38, (A) => sideLen(A, 0.78, 1.7, 2.7), 0.23 * u, { grav: 0.9, lift: 0.08, flick: 0.0, flat: 0.36, spring: 0.7 });
    for (const s of [-1, 1]) for (let i = 0; i < (hi ? 3 : 2); i++) clump(rootAt(s * (66 + i * 12) * deg, (30 - i * 8) * deg), [s * 0.1, -0.95, 0.3], (1.45 + 0.12 * i) * u, 0.18 * u, { grav: 1.4, lift: 0.05, flat: 0.36, spring: 0.55 });
    bangs(hi ? 7 : 5, 0.58 * u, 0.15 * u, { part: -0.5, flick: 0.05 });
  } else if (style === 'hat') {
    flow(hi ? 30 : 18, 0.45, 0.75, (A) => sideLen(A, 0.6, 0.6, 0.65), 0.2 * u, { grav: 0.7, lift: 0.15, flick: 0.35, flat: 0.36 });
    ring(hi ? 12 : 7, 0, 20, 0.4 * u, 0.16 * u, { flick: 0.25 });
    bangs(hi ? 7 : 4, 0.48 * u, 0.15 * u, { el: 40, flick: 0.2 });
    for (let i = 0; i < 4; i++) { const az = Math.PI + (i - 1.5) * 0.18; clump(rootAt(az, -0.28), [J(0.2), -1, -0.25], 0.85 * u, 0.13 * u, { grav: 1.3, lift: 0.05, spring: 0.8 }); }
  } else if (style === 'hood') {
    bangs(hi ? 7 : 4, 0.52 * u, 0.15 * u, { el: 42, flick: 0.15 });
    if (S.fem) for (const s of [-1, 1]) for (let i = 0; i < 3; i++) clump(rootAt(s * (58 + i * 10) * deg, (26 - i * 6) * deg), [s * 0.15, -0.95, 0.4], (1.5 + i * 0.12) * u, 0.17 * u, { grav: 1.4, lift: 0.1, flat: 0.36, spring: 0.4, hover: 0.04 * u });
  } else if (style === 'elder') {
    ring(hi ? 30 : 16, 6, 40, 0.38 * u, 0.12 * u, { front: 62, flick: 0.12, grav: 0.9, flat: 0.45 });
    // beard: from the jaw and chin, falling onto the chest; moustache from under the nose
    const nb = hi ? 17 : 9;
    for (let i = 0; i < nb; i++) {
      const t = i / (nb - 1), az = (-80 + 160 * t + J(5)) * deg, el = (-36 - 18 * Math.sin(Math.PI * t) + J(6)) * deg;
      const L = (0.4 + 0.8 * Math.pow(Math.sin(Math.PI * t), 1.5)) * u * (0.9 + rnd() * 0.2);
      clump(ppV.add(hc, ppV.mul(sph(az, el), 0.45 * u)), [Math.sin(az) * 0.2, -0.9, 0.35], L, 0.13 * u, { grav: 1.5, lift: 0.22, flick: 0.08, flat: 0.5, chain: 'neck' });
    }
    for (const s of [-1, 1]) clump(ppV.add(hc, [s * 0.05 * u, -0.215 * u, 0.35 * u]), [s * 0.7, -0.6, 0.3], 0.3 * u, 0.08 * u, { grav: 0.8, lift: 0.1, flat: 0.5 });
  }
}
// brows and the mouth line: thin strokes resting on the face
function ppFaceStrokes(S, C, FF, out) {
  const u = S.u, hc = S.hc, ey = hc[1] + S.eyeY * u;
  const browC = S.elder ? ppLin(0xe8e4ec) : ppV.mul(ppLin(C.hair), 0.72);
  for (const s of [-1, 1]) {
    const arch = S.fem ? 0.06 : S.kid ? 0.05 : 0.035, lift = S.kid ? 0.17 : S.elder ? 0.2 : 0.2, wd = S.eyeW;
    const pts = [];
    for (let i = 0; i < 8; i++) {
      const t = i / 7, x = s * (wd * 0.42 + wd * 1.3 * t) * u, y = ey + (lift + arch * Math.sin(Math.PI * Math.pow(t, 0.8)) - (S.hero ? 0.03 * (1 - t) : 0) - 0.05 * t * t) * u;
      pts.push(ppProject(FF, [x, y, hc[2] + 0.45 * u], 0.007 * u, 8));
    }
    const W0 = (S.elder ? 0.038 : S.fem ? 0.024 : 0.032) * u;
    const sf = ppSweep(pts, pts.map((p, i) => W0 * (1 - 0.6 * Math.pow(i / 7, 1.4))), pts.map(() => 0.011 * u), (i) => ppGrad(FF, pts[i]), { seg: 6 });
    out.push(ppDress(S, sf, browC, PP_M.hair, 'head', { flag: -1 }));
  }
  const my = hc[1] + (S.kid ? -0.285 : -0.266) * u, mw = (S.kid ? 0.06 : S.fem ? 0.072 : 0.078) * u, pts = [];
  for (let i = 0; i < 9; i++) { const t = i / 8 * 2 - 1; pts.push(ppProject(FF, [t * mw, my + (Math.abs(t) * Math.abs(t) * 0.012 - 0.002) * u, hc[2] + 0.45 * u], 0.001 * u, 8)); }
  const lipC = ppV.mul(ppMixC(ppLin(C.skin), ppLin(0x6a2030), 0.75), 0.6);
  const ms = ppSweep(pts, pts.map((p, i) => 0.0085 * u * Math.pow(Math.sin(Math.PI * (i + 0.5) / 9), 0.6)), pts.map(() => 0.004 * u), (i) => ppGrad(FF, pts[i]), { seg: 6 });
  out.push(ppDress(S, ms, lipC, PP_M.ink, 'head', { flag: -1 }));
}

// ---------------------------------------------------------------- outfits per role (sculpted layers + generated trims after meshing)
function ppHairCap(K, S, C) {
  const u = S.u, hc = S.hc, col = ppHex(ppV.mul(ppLin(C.hair), 0.78)), kw = S.kid ? 0.415 : 0.355;
  const P = (x, y, z) => [hc[0] + x * u, hc[1] + y * u, hc[2] + z * u];
  K.layer('cap', { cell: u * 0.032 * S.Q, ch: 'head', m: PP_M.hair, aoR: 0.06 * u, soft: 0.002 });
  K.el(P(0, 0.1, -0.06), [kw * u, (S.kid ? 0.475 : 0.445) * u, (S.kid ? 0.48 : 0.455) * u], col, { k: 0.04 * u });
  K.sub(S.kid ? P(0, -0.3, 0.4) : P(0, -0.24, 0.36), [(kw + 0.03) * u, 0.38 * u, 0.32 * u], 0.07 * u);
  for (const s of [-1, 1]) K.sub(P(s * (kw + 0.01), -0.13, 0.0), [0.08 * u, 0.15 * u, 0.12 * u], 0.03 * u);
  if (S.elder) K.sub(P(0, 0.42, 0.08), [0.42 * u, 0.3 * u, 0.44 * u], 0.1 * u);
}
function ppOutfit(K, S, C) {
  const u = S.u, j = S.j, W = S.W, kneeY = j.shinL[1], post = [];
  const kind = S.robe ? 'robe' : S.kid ? 'kid' : S.fem ? 'healer' : S.trav ? 'traveler' : 'hero';
  S.kind = kind;
  const Lr = (s) => (s > 0 ? 'L' : 'R');
  const dark = (h, k) => ppHex(ppV.mul(ppLin(h), k));
  const cuffs = (F, col, m, r, o = {}) => { const out = []; for (const s of [-1, 1]) { const X = Lr(s), el = j['fore' + X], wr = j['hand' + X]; out.push(ppDress(S, ppRing(F, ppV.lerp(el, wr, o.at ?? 0.86), ppV.sub(wr, el), r, o.hw ?? 0.07 * u, o.ht ?? 0.02 * u, { stitch: true }), col, m, 'arm' + X, { stitch: true })); } return out; };
  const bootCuffs = (F, col, top) => { const out = []; for (const s of [-1, 1]) { const X = Lr(s), an = j['foot' + X]; out.push(ppDress(S, ppRing(F, [an[0], top - 0.03 * u, an[2]], [0, 1, 0.04], (W.leg[2] + 0.12) * u, 0.085 * u, 0.026 * u, { stitch: true }), col, PP_M.leather, 'leg' + X, { stitch: true })); } return out; };
  const belt = (F, y, col, hw = 0.075 * u) => [ppDress(S, ppRing(F, [0, y, 0], [0, 1, 0], (W.hip + 0.2) * u, hw, 0.022 * u, { stitch: true, start: 1 }), col, PP_M.leather, 'torso', { stitch: true })];
  const shoes = (col, o, shaftTop, r1, r2) => {
    K.layer('boots', { cell: 0.0105 * S.Q, ch: 'legL', aoR: 0.05, m: PP_M.leather });
    for (const s of [-1, 1]) ppFoot(K, S, s, col, o, shaftTop ? { shaft: shaftTop, r1, r2 } : {});
    ppCutBelow(K, 0.03 * u);
    K.layer('sole', { cell: 0.009 * S.Q, ch: 'legL', aoR: 0.03, m: PP_M.leather });
    for (const s of [-1, 1]) ppSole(K, S, s, S.kid ? 0xece6da : 0x2a1d16);
    ppCutBelow(K, 0.002); ppCutAbove(K, 0.07 * u);
  };
  const pack = () => {
    const z = -(W.chestD + 0.3) * u, y = j.chest[1] + 0.02 * u, sc = S.kid ? 0.85 : 1;
    K.layer('pack', { cell: 0.012 * S.Q, ch: 'chest', aoR: 0.06, m: PP_M.cloth });
    K.el([0, y, z], [0.34 * u * sc, 0.4 * u * sc, 0.2 * u * sc], 0x8a6a48, { k: 0.12 * u });
    for (const s of [-1, 1]) K.el([s * 0.3 * u * sc, y - 0.12 * u, z + 0.02 * u], [0.1 * u, 0.2 * u * sc, 0.14 * u * sc], 0x7a5a3c, { k: 0.05 * u });
    K.layer('packflap', { cell: 0.011 * S.Q, ch: 'chest', aoR: 0.05, m: PP_M.leather });
    K.el([0, y + 0.22 * u * sc, z - 0.01 * u], [0.36 * u * sc, 0.2 * u * sc, 0.22 * u * sc], 0x5a3a26, { k: 0.06 * u });
    ppCutBelow(K, y + 0.06 * u);
    K.layer('bedroll', { cell: 0.012 * S.Q, ch: 'chest', aoR: 0.05, m: PP_M.cloth });
    K.rc([-0.42 * u * sc, y + 0.48 * u * sc, z + 0.02 * u], [0.42 * u * sc, y + 0.48 * u * sc, z + 0.02 * u], 0.13 * u * sc, 0.13 * u * sc, S.kid ? 0x5aa0d8 : 0xb8a27a, { k: 0.03 * u });
    post.push((F) => {
      const out = [];
      for (const s of [-1, 1]) out.push(ppDress(S, ppStrap(F('jacket'), [[s * 0.22 * u, y + 0.3 * u, z + 0.1 * u], [s * 0.3 * u, S.shY + 0.2 * u, -0.1 * u], [s * 0.32 * u, S.shY - 0.1 * u, (W.chestD + 0.06) * u], [s * 0.5 * u, j.chest[1] - 0.3 * u, 0.2 * u]], 0.05 * u, 0.016 * u, { stitch: true }), ppLin(0x4a3020), PP_M.leather, 'upper', { stitch: true }));
      return out;
    });
  };
  if (kind === 'hero' || kind === 'traveler') {
    const coat = kind === 'traveler';
    K.layer('shirt', { cell: 0.012 * S.Q, ch: 'upper', aoR: 0.05 });
    K.el([0, j.chest[1] + 0.3 * u, 0.0], [0.34 * u, 0.6 * u, (W.chestD - 0.02) * u], C.shirt, { k: 0.05 * u });
    K.rc([0, j.neck[1] - 0.12 * u, -0.05 * u], [0, j.neck[1] + 0.06 * u, -0.06 * u], (W.neck + 0.05) * u, (W.neck + 0.035) * u, C.shirt, { k: 0.05 * u, ch: 'neck' });
    K.layer('jacket', { cell: 0.0125 * S.Q, ch: 'torso', aoR: 0.07 });
    ppTorso(K, S, 0.05 * u, C.top, { hipX: 0.04 * u, hipZ: 0.03 * u });
    for (const s of [-1, 1]) ppSleeve(K, S, s, 0.045 * u, C.top);
    if (coat) K.rc([0, j.hips[1] - 0.1 * u, -0.02 * u], [0, kneeY + 0.2 * u, -0.06 * u], (W.hip + 0.1) * u, (W.hip + 0.26) * u, C.top, { k: 0.1 * u, ch: 'skirt' });
    const hemY = coat ? kneeY + 0.1 * u : j.hips[1] - 0.32 * u;
    ppCutBelow(K, hemY);
    K.subrc([0, j.neck[1] + 0.05 * u, 0.52 * u], [0, j.chest[1] - 0.22 * u, 0.44 * u], 0.2 * u, 0.05 * u, 0.015 * u);
    if (coat) K.subrc([0, j.hips[1] - 0.12 * u, 0.62 * u], [0, hemY - 0.1 * u, 0.78 * u], 0.04 * u, 0.22 * u, 0.01 * u);
    K.layer('pants', { cell: 0.0125 * S.Q, ch: 'torso', aoR: 0.06 });
    K.el([0, j.hips[1] - 0.08 * u, -0.02 * u], [(W.hip + 0.02) * u, 0.42 * u, (W.hipD + 0.015) * u], C.bottom, { k: 0.12 * u });
    for (const s of [-1, 1]) ppLeg(K, S, s, 0.03 * u, C.bottom, j.footL[1] + 0.5 * u);
    const bootTop = kneeY - 0.26 * u;
    shoes(C.shoe, 0.012 * u, bootTop, (W.leg[2] + 0.08) * u, (W.leg[3] + 0.065) * u);
    if (!coat) {
      K.layer('scarf', { cell: 0.011 * S.Q, ch: 'upper', aoR: 0.05, m: PP_M.cloth });
      const ny = j.neck[1] + 0.0 * u, R0 = (W.neck + 0.16) * u, ring = (a) => [Math.sin(a) * R0 * 1.08, ny - 0.07 * u * Math.cos(a), Math.cos(a) * R0 * 0.98 - 0.06 * u];
      for (let i = 0; i < 12; i++) { const a0 = i / 12 * Math.PI * 2, a1 = (i + 1) / 12 * Math.PI * 2; K.rc(ring(a0), ring(a1), (0.1 + 0.02 * Math.cos(a0)) * u, (0.1 + 0.02 * Math.cos(a1)) * u, C.accent, { k: 0.05 * u }); }
      K.el([0.15 * u, ny - 0.15 * u, (W.neck + 0.2) * u], [0.095 * u, 0.1 * u, 0.085 * u], C.accent, { k: 0.04 * u });
      K.rc([0.16 * u, ny - 0.2 * u, (W.neck + 0.23) * u], [0.24 * u, ny - 0.42 * u, (W.chestD + 0.1) * u], 0.07 * u, 0.04 * u, C.accent, { k: 0.03 * u });
    } else {
      K.layer('scarf', { cell: 0.0105 * S.Q, ch: 'upper', aoR: 0.05, m: PP_M.satin });
      const ny = j.neck[1] + 0.0 * u, R0 = (W.neck + 0.1) * u, ring = (a) => [Math.sin(a) * R0 * 1.05, ny - 0.06 * u * Math.cos(a), Math.cos(a) * R0 * 0.95 - 0.05 * u];
      for (let i = 0; i < 12; i++) K.rc(ring(i / 12 * Math.PI * 2), ring((i + 1) / 12 * Math.PI * 2), 0.06 * u, 0.06 * u, C.accent, { k: 0.04 * u });
      K.rc([0, ny - 0.1 * u, (W.neck + 0.18) * u], [0, ny - 0.38 * u, (W.chestD + 0.12) * u], 0.09 * u, 0.02 * u, C.accent, { k: 0.04 * u });
    }
    if (C.pack !== false) pack();
    if (!coat) {
      K.layer('pouch', { cell: 0.01 * S.Q, ch: 'hips', aoR: 0.04, m: PP_M.leather });
      K.el([-(W.hip + 0.13) * u, j.hips[1] - 0.06 * u, 0.12 * u], [0.1 * u, 0.13 * u, 0.13 * u], 0x7a5038, { k: 0.04 * u });
      K.el([-(W.hip + 0.15) * u, j.hips[1] + 0.03 * u, 0.13 * u], [0.11 * u, 0.06 * u, 0.14 * u], 0x5a3a26, { k: 0.02 * u });
    }
    post.push((F) => {
      const FJ = F('jacket'), out = [];
      out.push(...belt(FJ, j.spine[1] - 0.3 * u, ppLin(0x4a2e1e)));
      out.push(...cuffs(FJ, ppLin(C.trim), PP_M.cloth, (W.arm[3] + 0.09) * u));
      out.push(...bootCuffs(F('boots'), ppLin(dark(C.shoe, 1.25)), bootTop));
      if (!coat) {
        out.push(ppDress(S, ppRing(FJ, [0, hemY + 0.045 * u, 0], [0, 1, 0], (W.hip + 0.2) * u, 0.04 * u, 0.016 * u, { stitch: true, start: 1 }), ppLin(C.trim), PP_M.cloth, 'torso', { stitch: true }));
        out.push(ppDress(S, ppStrap(FJ, [[0.32 * u, S.shY + 0.2 * u, -0.06 * u], [0.24 * u, S.shY - 0.1 * u, 0.42 * u], [-0.02 * u, j.chest[1] - 0.25 * u, 0.48 * u], [-0.32 * u, j.spine[1] - 0.1 * u, 0.42 * u], [-0.55 * u, j.hips[1] + 0.1 * u, 0.1 * u]], 0.055 * u, 0.016 * u, { stitch: true }), ppLin(0x6a4430), PP_M.leather, 'torso', { stitch: true }));
        out.push(ppDress(S, ppStrap(FJ, [[0.32 * u, S.shY + 0.2 * u, -0.06 * u], [0.2 * u, S.shY - 0.2 * u, -0.45 * u], [-0.2 * u, j.spine[1], -0.42 * u], [-0.55 * u, j.hips[1] + 0.1 * u, -0.05 * u]], 0.055 * u, 0.016 * u, { stitch: true }), ppLin(0x6a4430), PP_M.leather, 'torso', { stitch: true }));
      } else {
        out.push(ppDress(S, ppRing(F('shirt'), [0, j.neck[1] + 0.08 * u, -0.04 * u], [0, 1, -0.25], 0.36 * u, 0.07 * u, 0.02 * u, { gap: 0.5, stitch: true }), ppLin(C.top), PP_M.cloth, 'neck', { stitch: true }));
      }
      return out;
    });
  } else if (kind === 'kid') {
    K.layer('shirt', { cell: 0.009 * S.Q, ch: 'upper', aoR: 0.05 });
    K.el([0, j.chest[1] + 0.2 * u, 0.0], [0.3 * u, 0.45 * u, (W.chestD - 0.02) * u], C.shirt, { k: 0.05 * u });
    K.rc([0, j.neck[1] - 0.1 * u, -0.05 * u], [0, j.neck[1] + 0.1 * u, -0.06 * u], (W.neck + 0.05) * u, (W.neck + 0.04) * u, C.shirt, { k: 0.04 * u, ch: 'neck' });
    K.layer('jacket', { cell: 0.009 * S.Q, ch: 'torso', aoR: 0.05 });
    ppTorso(K, S, 0.06 * u, C.top, { hipX: 0.03 * u, hipZ: 0.03 * u });
    for (const s of [-1, 1]) ppSleeve(K, S, s, 0.05 * u, C.top, { len: 0.55, flare: 0.03 * u });
    K.el([0, j.neck[1] + 0.02 * u, -(W.chestD + 0.16) * u], [0.36 * u, 0.2 * u, 0.2 * u], C.top, { k: 0.08 * u, ch: 'upper' });
    ppCutBelow(K, j.hips[1] - 0.2 * u);
    K.subrc([0, j.neck[1] + 0.05 * u, 0.5 * u], [0, j.chest[1] - 0.05 * u, 0.44 * u], 0.17 * u, 0.04 * u, 0.012 * u);
    K.layer('arms', { cell: 0.008 * S.Q, ch: 'armL', aoR: 0.03, m: PP_M.skin, soft: 0.002 });
    for (const s of [-1, 1]) { const X = Lr(s); K.rc(j['fore' + X], j['hand' + X], W.arm[2] * u, W.arm[3] * u, C.skin, { k: 0.04 * u, ch: 'arm' + X }); }
    K.layer('pants', { cell: 0.009 * S.Q, ch: 'torso', aoR: 0.05 });
    K.el([0, j.hips[1] - 0.06 * u, -0.02 * u], [(W.hip + 0.05) * u, 0.36 * u, (W.hipD + 0.04) * u], C.bottom, { k: 0.1 * u });
    for (const s of [-1, 1]) ppLeg(K, S, s, 0.06 * u, C.bottom, 0, { thighOnly: true });
    ppCutBelow(K, kneeY + 0.16 * u);
    K.layer('legs', { cell: 0.008 * S.Q, ch: 'legL', aoR: 0.04, m: PP_M.skin, soft: 0.002 });
    for (const s of [-1, 1]) ppLeg(K, S, s, 0, C.skin, j.footL[1] + 0.1 * u);
    ppCutAbove(K, kneeY + 0.3 * u);
    K.layer('socks', { cell: 0.008 * S.Q, ch: 'legL', aoR: 0.03 });
    for (const s of [-1, 1]) { const an = j['foot' + Lr(s)]; K.rc([an[0], an[1] + 0.55 * u, an[2] + 0.01 * u], [an[0], 0.25 * u, an[2] - 0.03 * u], (W.leg[3] + 0.04) * u, (W.leg[3] + 0.035) * u, 0xf4f0e8, { k: 0.03 * u, ch: 'leg' + Lr(s) }); }
    shoes(C.shoe, 0.03 * u);
    if (C.pack !== false) pack();
    post.push((F) => {
      const out = [];
      out.push(...cuffs(F('jacket'), ppLin(dark(C.top, 0.8)), PP_M.cloth, (W.arm[2] + 0.12) * u, { at: 0.5, hw: 0.06 * u }));
      out.push(ppDress(S, ppRing(F('jacket'), [0, j.hips[1] - 0.16 * u, 0], [0, 1, 0], (W.hip + 0.24) * u, 0.05 * u, 0.018 * u, { stitch: true, start: 1 }), ppLin(dark(C.top, 0.8)), PP_M.cloth, 'torso', { stitch: true }));
      if (C.hat === 'band') out.push(ppDress(S, ppRing(F('cap'), ppV.add(S.hc, [0, 0.2 * u, -0.04 * u]), [0, 1, 0.3], 0.6 * u, 0.075 * u, 0.026 * u, { off: 0.02 * u }), ppLin(C.accent), PP_M.satin, 'head'));
      return out;
    });
  } else if (kind === 'healer') {
    K.layer('jacket', { cell: 0.0115 * S.Q, ch: 'torso', aoR: 0.06 });
    ppTorso(K, S, 0.035 * u, C.top, { pelvis: false });
    for (const s of [-1, 1]) ppSleeve(K, S, s, 0.04 * u, C.top, { puff: true, len: 0.9, flare: 0.04 * u });
    K.rc([0, j.neck[1] - 0.05 * u, -0.05 * u], [0, j.neck[1] + 0.1 * u, -0.06 * u], (W.neck + 0.045) * u, (W.neck + 0.035) * u, C.top, { k: 0.04 * u, ch: 'neck' });
    ppCutBelow(K, j.hips[1] - 0.05 * u);
    K.subrc([0, j.neck[1] + 0.06 * u, 0.42 * u], [0, j.chest[1] + 0.25 * u, 0.4 * u], 0.12 * u, 0.04 * u, 0.012 * u);
    const hemY = kneeY - 0.62 * u;
    K.layer('skirt', { cell: 0.0125 * S.Q, ch: 'skirt', aoR: 0.06 });
    K.el([0, j.spine[1] - 0.1 * u, 0], [(W.waist + 0.06) * u, 0.4 * u, (W.waistD + 0.06) * u], C.bottom, { k: 0.12 * u, ch: 'torso' });
    K.el([0, j.hips[1] - 0.05 * u, -0.02 * u], [(W.hip + 0.08) * u, 0.5 * u, (W.hipD + 0.08) * u], C.bottom, { k: 0.12 * u });
    K.rc([0, j.hips[1] - 0.1 * u, -0.02 * u], [0, hemY + 0.06 * u, -0.05 * u], (W.hip + 0.08) * u, (W.hip + 0.32) * u, C.bottom, { k: 0.12 * u });
    for (let i = 0; i < 7; i++) { const a = (i / 7) * Math.PI * 2 + 0.2; K.rc([Math.sin(a) * (W.hip + 0.1) * u, j.hips[1] - 0.3 * u, Math.cos(a) * (W.hipD + 0.1) * u], [Math.sin(a) * (W.hip + 0.38) * u, hemY + 0.06 * u, Math.cos(a) * (W.hip + 0.3) * u - 0.04 * u], 0.05 * u, 0.09 * u, C.bottom, { k: 0.12 * u }); }
    ppCutBelow(K, hemY); ppCutAbove(K, j.chest[1] - 0.35 * u);
    shoes(C.shoe, 0.012 * u, hemY + 0.25 * u, (W.leg[2] + 0.05) * u, (W.leg[3] + 0.06) * u);
    post.push((F) => {
      const out = [];
      out.push(ppDress(S, ppRing(F('skirt'), [0, j.spine[1] + 0.02 * u, 0], [0, 1, 0], (W.hip + 0.2) * u, 0.1 * u, 0.025 * u, { start: 1 }), ppLin(C.accent), PP_M.satin, 'torso'));
      out.push(ppDress(S, ppRing(F('skirt'), [0, hemY + 0.06 * u, 0], [0, 1, 0], (W.hip + 0.6) * u, 0.045 * u, 0.016 * u, { stitch: true }), ppLin(dark(C.bottom, 0.7)), PP_M.cloth, 'skirt', { stitch: true }));
      out.push(...cuffs(F('jacket'), ppLin(C.accent), PP_M.satin, (W.arm[3] + 0.12) * u, { at: 0.86, hw: 0.05 * u }));
      out.push(ppDress(S, ppRing(F('jacket'), [0, j.neck[1] + 0.06 * u, -0.04 * u], [0, 1, -0.2], 0.34 * u, 0.04 * u, 0.018 * u), ppLin(C.accent), PP_M.satin, 'neck'));
      return out;
    });
  } else {
    // robes: elder and the three guardians (mantle + hood), wide sleeves, sash, embroidered hems
    K.layer('shirt', { cell: 0.011 * S.Q, ch: 'neck', aoR: 0.05 });
    K.rc([0, j.neck[1] - 0.15 * u, -0.04 * u], [0, j.neck[1] + 0.1 * u, -0.06 * u], (W.neck + 0.06) * u, (W.neck + 0.045) * u, C.trim, { k: 0.05 * u });
    K.layer('jacket', { cell: 0.014 * S.Q, ch: 'torso', aoR: 0.08 });
    ppTorso(K, S, 0.06 * u, C.top, { hipX: 0.06 * u, hipZ: 0.05 * u });
    if (S.elder) K.el([0, j.spine[1] - 0.05 * u, 0.1 * u], [0.44 * u, 0.48 * u, 0.4 * u], C.top, { k: 0.15 * u });
    for (const s of [-1, 1]) ppSleeve(K, S, s, 0.055 * u, C.top, { len: 0.86, flare: 0.13 * u });
    K.rc([0, j.hips[1] + 0.05 * u, -0.02 * u], [0, 0.22 * u, -0.05 * u], (W.hip + 0.07) * u, (W.hip + 0.36) * u, C.top, { k: 0.12 * u, ch: 'skirt' });
    ppCutBelow(K, 0.11 * u);
    K.subrc([0, j.neck[1] + 0.06 * u, 0.48 * u], [0, j.chest[1] + 0.15 * u, 0.46 * u], 0.15 * u, 0.04 * u, 0.012 * u);
    shoes(C.shoe, 0.015 * u);
    if (S.guard) {
      const mc = dark(C.top, 0.62);
      K.layer('mantle', { cell: 0.0125 * S.Q, ch: 'upper', aoR: 0.07 });
      K.el([0, S.shY - 0.02 * u, -0.03 * u], [(W.sh + 0.32) * u, 0.46 * u, (W.chestD + 0.26) * u], mc, { k: 0.1 * u });
      ppCutBelow(K, S.shY - 0.44 * u);
      K.subrc([0, j.neck[1] - 0.3 * u, -0.05 * u], [0, j.neck[1] + 0.8 * u, -0.05 * u], (W.neck + 0.13) * u, (W.neck + 0.13) * u, 0.03 * u);
      K.layer('hood', { cell: 0.0115 * S.Q, ch: 'neck', aoR: 0.07 });
      K.el(ppV.add(S.hc, [0, 0.05 * u, -0.1 * u]), [0.5 * u, 0.58 * u, 0.58 * u], mc, { k: 0.08 * u });
      K.el([0, j.neck[1] + 0.05 * u, -0.2 * u], [0.46 * u, 0.36 * u, 0.4 * u], mc, { k: 0.12 * u });
      K.sub(ppV.add(S.hc, [0, -0.12 * u, 0.47 * u]), [0.37 * u, 0.53 * u, 0.44 * u], 0.05 * u);
      K.sub(ppV.add(S.hc, [0, -0.02 * u, -0.06 * u]), [0.4 * u, 0.48 * u, 0.48 * u], 0.03 * u);
    }
    post.push((F) => {
      const out = [], FJ = F('jacket');
      out.push(ppDress(S, ppRing(FJ, [0, j.spine[1] - 0.12 * u, 0], [0, 1, 0], (W.hip + (S.elder ? 0.42 : 0.28)) * u, 0.11 * u, 0.028 * u, { start: 1 }), ppLin(C.accent), PP_M.satin, 'torso'));
      out.push(ppDress(S, ppRing(FJ, [0, 0.2 * u, 0], [0, 1, 0], (W.hip + 0.7) * u, 0.06 * u, 0.018 * u, { stitch: true }), ppLin(C.accent), PP_M.satin, 'skirt', { stitch: true }));
      out.push(...cuffs(FJ, ppLin(C.accent), PP_M.satin, (W.arm[3] + 0.3) * u, { at: 0.82, hw: 0.055 * u }));
      if (S.guard) out.push(ppDress(S, ppRing(F('mantle'), [0, S.shY - 0.4 * u, -0.03 * u], [0, 1, 0], (W.sh + 0.6) * u, 0.045 * u, 0.016 * u, { stitch: true }), ppLin(C.accent), PP_M.satin, 'upper', { stitch: true }));
      return out;
    });
  }
  return post;
}

// ---------------------------------------------------------------- build (cached per look): sculpt → trims → hair → strokes → hands → AO → merge
const _ppCache = {};
function ppKey(C) { return JSON.stringify([C.skin, C.hair, C.top, C.shirt, C.trim, C.bottom, C.shoe, C.glove, C.accent, C.robe, C.beard, C.long, C.pack, C.kid, C.hat, C.pin, C.staff, PP_HI()]); }
function ppBuild(C) {
  const key = ppKey(C);
  if (_ppCache[key]) return _ppCache[key];
  const t0 = performance.now();
  const S = ppSpec(C), K = ppKit();
  ppFace(K, S, C);
  ppHairCap(K, S, C);
  const post = ppOutfit(K, S, C);
  const surfs = [], fields = {};
  const PF = window.__ppProf, tm = (k, t) => { if (PF) PF[k] = (PF[k] || 0) + performance.now() - t; };
  let t1 = performance.now();
  for (const L of K.layers) { const tl = performance.now(); const s = ppLayerSurf(S, L); surfs.push(s); fields[L.name] = s.field; if (L.name === 'face') ppFaceNormals(S, s); tm('L_' + L.name, tl); }
  tm('layers', t1); t1 = performance.now();
  const F = (name) => ppUnion([fields[name]]);
  const all = Object.values(fields);
  for (const fn of post) for (const s of fn(F)) surfs.push(s);
  const extra = [];
  if (fields.jacket) S.pendant = ppProject(F('jacket'), [0, S.j.chest[1] - (S.kind === 'hero' ? 0.32 : S.kind === 'healer' ? -0.25 : 0.05) * S.u, 0.8 * S.u], 0.025 * S.u, 8);
  const FH = ppUnion([fields.face, fields.cap]), FB = ppUnion(Object.keys(fields).filter((n) => n !== 'face' && n !== 'cap').map((n) => fields[n]));
  tm('post', t1); t1 = performance.now();
  ppHair(S, C, FH, FB, extra); tm('hair', t1); t1 = performance.now();
  if (C.pin) S.pinPos = ppProject(FH, ppV.add(S.hc, [0.3 * S.u, 0.14 * S.u, 0.16 * S.u]), 0.05 * S.u, 8);
  ppFaceStrokes(S, C, F('face'), extra);
  if (C.hat === 'wide') extra.push(ppHatWide(S, C));
  const glove = S.kind === 'hero';
  for (const s of [1, -1]) surfs.push(ppHand(S, C, s, glove));
  tm('strokes+hands', t1); t1 = performance.now();
  for (const s of surfs) if (s.aoR) ppAO(s, all, s.aoR);
  tm('ao', t1); t1 = performance.now();
  const geo = ppMerge(surfs.concat(extra)); tm('merge', t1);
  geo.computeBoundingSphere();
  const res = { S, geo, ms: performance.now() - t0, tris: geo.index.count / 3 };
  _ppCache[key] = res;
  return res;
}
// anime-style face normals: the front of the face takes most of its shading normal from a smooth head ellipsoid, so
// the light/shade boundary is one clean curve instead of following every bump (nose and lips keep a little detail)
function ppFaceNormals(S, s) {
  const u = S.u, c = ppV.add(S.hc, [0, -0.05 * u, -0.08 * u]), R = [0.34 * u, 0.5 * u, 0.44 * u];
  for (let q = 0; q < s.nv; q++) {
    const x = s.pos[q * 3], y = s.pos[q * 3 + 1], z = s.pos[q * 3 + 2];
    const ne = ppV.norm([(x - c[0]) / (R[0] * R[0]), (y - c[1]) / (R[1] * R[1]), (z - c[2]) / (R[2] * R[2])]);
    const rel = (y - S.hc[1]) / u;
    const k = 0.78 * smooth(-0.2, 0.3, ne[2]) * (1 - smooth(0.25 * u, 0.32 * u, Math.abs(x))) * smooth(-0.62, -0.46, rel);
    if (k <= 0) continue;
    const n = ppV.norm(ppV.lerp([s.nor[q * 3], s.nor[q * 3 + 1], s.nor[q * 3 + 2]], ne, k));
    s.nor.set(n, q * 3);
  }
}
function ppHatWide(S, C) {
  const u = S.u, pr = [[0.0, 0.66], [0.2, 0.65], [0.33, 0.6], [0.38, 0.36], [0.41, 0.12], [0.5, 0.06], [0.78, 0.02], [0.96, -0.04], [0.97, -0.07], [0.78, -0.03], [0.5, 0.02], [0.4, 0.06], [0.36, 0.3], [0.31, 0.56], [0.0, 0.6]];
  const g = new THREE.LatheGeometry(pr.map(([r, y]) => new THREE.Vector2(r * u, y * u)), PP_HI() ? 40 : 24);
  const s = ppFromGeo(g); g.dispose();
  const c = ppV.add(S.hc, [0, 0.33 * u, -0.04 * u]), ca = Math.cos(-0.12), sa = Math.sin(-0.12);
  ppXform(s, [1, 0, 0], [0, ca, sa], [0, -sa, ca], c);
  ppFill(s, ppLin(C.accent), PP_M.cloth);
  for (let q = 0; q < s.nv; q++) { const y = s.pos[q * 3 + 1] - c[1]; if (y > 0.1 * u && y < 0.22 * u && Math.hypot(s.pos[q * 3] - c[0], s.pos[q * 3 + 2] - c[2]) < 0.45 * u) s.col.set(ppV.mul(ppLin(C.top), 0.7), q * 3); }
  return ppRigid(s, PP_BI.head);
}

// ---------------------------------------------------------------- person cel material (skinned or not; ribbons add a flutter)
// two tones + narrow form band, antialiased terminator, hue-shifted shade (rosy for skin, cool for cloth), skin scatter
// band at the terminator, shaped specular (leather, metal, lips, skin sheen), Kajiya-Kay hair sheen along the strands,
// matte cloth fresnel sheen, stitched seams, clean sun-side rim, soft crease AO.
const PP_FRAG_DECL = `
varying vec4 vM; varying vec3 vTanV; varying vec2 vUV2; varying float vAO;
struct ToonMaterial { vec3 diffuseColor; };
float gSun = 0.0;
vec3 ppShade(vec3 a) {
  float l = dot(a, vec3(0.2126, 0.7152, 0.0722));
  vec3 s = max(mix(vec3(l), a, 1.3), 0.0);
  return mix(s * vec3(0.88, 0.92, 1.12), s * vec3(1.06, 0.8, 0.8), vM.z);
}
void RE_Direct_Toon( const in IncidentLight directLight, const in vec3 geometryPosition, const in vec3 geometryNormal, const in vec3 geometryViewDir, const in vec3 geometryClearcoatNormal, const in ToonMaterial material, inout ReflectedLight reflectedLight ) {
  vec3 N = geometryNormal, L = directLight.direction, V = geometryViewDir;
  float NdL = dot(N, L);
  float I = dot(directLight.color, vec3(0.3333));
  float strong = smoothstep(0.45, 1.3, I);
  vec3 Lc = mix(vec3(I), directLight.color, 0.7);
  float sss = vM.z;
  float w = mix(0.03, 0.075, sss) + fwidth(NdL) * 0.9;
  float th = mix(0.06, -0.02, sss);
  float cel = smoothstep(th - w, th + w, NdL);
  float form = mix(0.84, 1.0, smoothstep(th + w, 0.62, NdL));
  float k = mix(clamp(NdL * 0.5 + 0.5, 0.0, 1.0) * 0.55, cel * form, strong);
  vec3 irr = Lc * k * mix(1.0, vAO, 0.3);
  reflectedLight.directDiffuse += irr * BRDF_Lambert(material.diffuseColor);
  float band = (1.0 - smoothstep(0.0, w * 2.0 + 0.1, abs(NdL - th))) * sss * strong;
  reflectedLight.directDiffuse += Lc * band * vec3(0.3, 0.06, 0.03) * BRDF_Lambert(material.diffuseColor);
  gSun = max(gSun, cel * smoothstep(0.4, 1.4, I));
  vec3 H = normalize(L + V);
  float NdH = max(dot(N, H), 0.0);
  float sp = pow(NdH, mix(20.0, 150.0, vM.y));
  float spec = smoothstep(0.3, 0.62, sp) * vM.x * cel * strong;
  vec3 specC = mix(vec3(1.0), material.diffuseColor * 3.0 + 0.05, step(0.85, vM.x));
  vec3 acc = specC * spec * 0.35;
  if (vM.w > 0.01) {
    vec3 tv = dot(vTanV, vTanV) > 1e-8 ? vTanV : (viewMatrix * vec4(0.0, -1.0, 0.0, 0.0)).xyz;
    vec3 T = tv - N * dot(tv, N); T = dot(T, T) > 1e-8 ? normalize(T) : vec3(1.0, 0.0, 0.0);
    vec3 T1 = normalize(T + N * 0.18), T2 = normalize(T - N * 0.25);
    float d1 = dot(T1, H), d2 = dot(T2, H);
    float s1 = pow(sqrt(max(1.0 - d1 * d1, 0.0)), 110.0), s2 = pow(sqrt(max(1.0 - d2 * d2, 0.0)), 28.0);
    float hs = (smoothstep(0.3, 0.7, s1) * 0.2 + s2 * 0.04) * vM.w * mix(0.25, 1.0, cel) * strong;
    acc += hs * (material.diffuseColor * 3.0 + vec3(0.07, 0.075, 0.09));
  }
  reflectedLight.directSpecular += directLight.color * acc;
}
void RE_IndirectDiffuse_Toon( const in vec3 irradiance, const in vec3 geometryPosition, const in vec3 geometryNormal, const in vec3 geometryViewDir, const in vec3 geometryClearcoatNormal, const in ToonMaterial material, inout ReflectedLight reflectedLight ) {
  reflectedLight.indirectDiffuse += irradiance * BRDF_Lambert(ppShade(material.diffuseColor)) * mix(1.0, vAO, 0.85);
}
#define RE_Direct RE_Direct_Toon
#define RE_IndirectDiffuse RE_IndirectDiffuse_Toon
`;
// directional shadows are applied at full strength on clothes and softened on skin (clean faces; hair and hat
// shadows still read)
const PP_LIGHTS_BEGIN = (() => {
  let c = THREE.ShaderChunk.lights_fragment_begin;
  const a = 'directLight.color *= ( directLight.visible && receiveShadow ) ? getShadow( directionalShadowMap[ i ]';
  const b = 'vDirectionalShadowCoord[ i ] ) : 1.0;';
  if (c.split(a).length === 2 && c.split(b).length === 2) c = c.replace(a, 'float ppSh = ( directLight.visible && receiveShadow ) ? getShadow( directionalShadowMap[ i ]').replace(b, b + '\n\t\tdirectLight.color *= mix(1.0, ppSh, mix(1.0, 0.5, vM.z));');
  return c;
})();
const _ppMats = {};
function ppMaterial(variant = 'base', U) {
  if (variant === 'base' && _ppMats.base) return _ppMats.base;
  const m = new THREE.MeshToonMaterial({ vertexColors: true });
  m.userData.noAO = false;
  m.defaultAttributeValues = { aM: [0, 0, 0, 0], aUV2: [0, 0], aTan: [0, 1, 0], aAO: [1] };
  m.onBeforeCompile = (sh) => {
    if (U) Object.assign(sh.uniforms, U);
    sh.vertexShader = `attribute vec4 aM; attribute vec2 aUV2; attribute vec3 aTan; attribute float aAO;
      varying vec4 vM; varying vec3 vTanV; varying vec2 vUV2; varying float vAO;
      ${variant === 'ribbon' ? 'uniform float uTime, uMove, uPh, uStiff;' : ''}
      ` + sh.vertexShader
      .replace('#include <defaultnormal_vertex>', `#include <defaultnormal_vertex>
        { vec3 tn = aTan;
          #ifdef USE_SKINNING
            tn = (skinMatrix * vec4(tn, 0.0)).xyz;
          #endif
          vTanV = normalMatrix * tn; }
        vM = aM; vUV2 = aUV2; vAO = aAO;`)
      .replace('#include <begin_vertex>', variant === 'ribbon' ? `#include <begin_vertex>
        { float s = aUV2.x, cs = s * s;
          transformed.z += sin(uTime * 4.2 + uPh - s * 5.0) * (0.03 + uMove * 0.07) * s;
          transformed.x += sin(uTime * 3.1 + uPh * 1.7 - s * 4.0) * 0.022 * s;
          transformed.z -= cs * (0.05 + uMove * 0.42) * uStiff;
          transformed.y += cs * uMove * 0.15 * uStiff; }` : '#include <begin_vertex>');
    sh.fragmentShader = sh.fragmentShader
      .replace('#include <lights_toon_pars_fragment>', 'varying vec3 vViewPosition;\n' + PP_FRAG_DECL)
      .replace('#include <lights_fragment_begin>', PP_LIGHTS_BEGIN)
      .replace('#include <color_fragment>', `#include <color_fragment>
        if (vUV2.y > 0.99 && vUV2.y < 2.01) {
          // stitched seams along both edges of bands and straps (fade out when the dashes get sub-pixel)
          float v = (vUV2.y - 1.5) / 0.49;
          float aa = 1.0 - smoothstep(0.25, 0.6, fwidth(vUV2.x));
          float line = smoothstep(0.14, 0.05, abs(abs(v) - 0.66));
          float dash = smoothstep(0.32, 0.18, abs(fract(vUV2.x) - 0.5));
          diffuseColor.rgb = mix(diffuseColor.rgb, diffuseColor.rgb * 0.45 + vec3(0.38, 0.33, 0.26), line * dash * aa * 0.85);
          diffuseColor.rgb *= 1.0 - 0.18 * smoothstep(0.82, 1.0, abs(v));
        } else if (vUV2.y > 2.5) {
          // hair: darker roots, strands across the clump, lighter tips
          float t = vUV2.x, a = vUV2.y - 4.0;
          float aa = 1.0 - smoothstep(0.08, 0.3, fwidth(a * 5.0));
          diffuseColor.rgb *= mix(0.72, 1.0, smoothstep(0.0, 0.35, t)) * (1.0 + 0.08 * smoothstep(0.6, 1.0, t));
          diffuseColor.rgb *= 1.0 + (sin(a * 9.0 + t * 3.0) * 0.07 + sin(a * 23.0) * 0.04) * aa;
        }`)
      .replace('#include <opaque_fragment>', `
        {
          vec3 Vv = normalize(vViewPosition);
          float ndv = clamp(dot(normal, Vv), 0.0, 1.0);
          outgoingLight += reflectedLight.directSpecular;
          float matte = (1.0 - clamp(vM.x * 3.0, 0.0, 1.0)) * (1.0 - vM.z) * (1.0 - vM.w);
          outgoingLight += reflectedLight.indirectDiffuse * pow(1.0 - ndv, 3.0) * 0.55 * matte;
          #if NUM_DIR_LIGHTS > 0
            float rimM = smoothstep(0.6, 0.72, 1.0 - ndv) * smoothstep(-0.15, 0.3, dot(normal, directionalLights[0].direction));
            outgoingLight += directionalLights[0].color * diffuseColor.rgb * rimM * gSun * 0.16;
          #endif
        }
        #include <opaque_fragment>`);
  };
  m.customProgramCacheKey = () => 'ppCel-v1-' + variant;
  if (variant === 'base') _ppMats.base = m;
  return m;
}
// inverted-hull ink line that follows the skin; screen-space width (≈1–2 px), coloured from the albedo; strokes
// flagged "no outline" (brows, mouth) collapse
function ppOutlineMat() {
  if (_ppMats.ol) return _ppMats.ol;
  const m = new THREE.MeshBasicMaterial({ color: 0xffffff, side: THREE.BackSide, vertexColors: true });
  m.userData.noAO = true;
  const U = { uOlRes: { value: new THREE.Vector2(1280, 720) } };
  m.userData.U = U;
  m.onBeforeCompile = (sh) => {
    Object.assign(sh.uniforms, U);
    sh.vertexShader = 'attribute vec2 aUV2; uniform vec2 uOlRes;\n' + sh.vertexShader.replace('#include <skinning_vertex>', `#include <skinning_vertex>
      {
        vec3 nO = normal;
        #ifdef USE_SKINNING
          nO = (skinMatrix * vec4(normal, 0.0)).xyz;
        #endif
        nO = normalize(nO);
        vec4 mv0 = modelViewMatrix * vec4(transformed, 1.0);
        float depth = projectionMatrix[3][3] > 0.5 ? 1.0 : max(-mv0.z, 0.01);
        float px = 2.0 * depth / (projectionMatrix[1][1] * max(uOlRes.y, 1.0));
        float ref = max(uOlRes.y / 900.0, 0.6);
        float sN = max(length(mat3(modelViewMatrix) * nO), 1e-5);
        float wPx = clamp(0.006 * sN / px, 0.8 * ref, 1.9 * ref) * (aUV2.y > 2.5 ? 0.65 : 1.0);
        transformed += nO * (wPx * px / sN);
        if (aUV2.y < -0.5) transformed = vec3(0.0);
      }`).replace('#include <project_vertex>', `#include <project_vertex>
      gl_Position.z += 0.00004 * gl_Position.w;`);
    sh.fragmentShader = sh.fragmentShader.replace('#include <color_fragment>', `
      { vec3 c = vColor; float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
        c = max(mix(vec3(l), c, 1.4), 0.0);
        diffuseColor.rgb = c * c * 0.16 + vec3(0.012, 0.008, 0.016); }`);
  };
  m.customProgramCacheKey = () => 'ppOl-v1';
  _ppMats.ol = m;
  return m;
}
const _ppRes = new THREE.Vector2();

// ---------------------------------------------------------------- eyes: eyeball shader + lid shells
// eye frame: origin at the eyeball centre, +z out of the face, +x towards the OUTER corner (side mirrors it)
function ppEyeMat(C, S, side) {
  const U = {
    uR: { value: S.eyes[0].R }, uIris: { value: new THREE.Color(C.eye ?? 0x2a2a6a) }, uIris2: { value: new THREE.Color(C.eye2 ?? 0x7a9aff) },
    uSclera: { value: new THREE.Color(0xe8e2dc) }, uGaze: { value: new THREE.Vector3(0, 0, 1) }, uLid: { value: new THREE.Vector4(0.5, 0.42, -0.04, 0.08) },
    uPhi: { value: new THREE.Vector2(-0.95, 1.0) }, uSide: { value: side }, uIrisA: { value: S.kid ? 0.56 : 0.5 }, uPupil: { value: 0.4 }, uDepth: { value: 0.3 }, uBlink: { value: 0 }, uLight: { value: 0.9 },
  };
  const m = new THREE.ShaderMaterial({
    uniforms: THREE.UniformsUtils.merge([THREE.UniformsLib.fog]),
    vertexShader: `uniform float uR; varying vec3 vP; varying vec3 vNv; varying vec3 vVo;
      #include <fog_pars_vertex>
      void main() {
        vP = position / uR;
        vec4 mvPosition = modelViewMatrix * vec4(position, 1.0);
        vNv = normalize(normalMatrix * normal);
        mat3 m3 = mat3(modelViewMatrix); vec3 s2 = max(vec3(dot(m3[0], m3[0]), dot(m3[1], m3[1]), dot(m3[2], m3[2])), vec3(1e-10));
        vec3 vv = -mvPosition.xyz; vVo = vec3(dot(m3[0], vv), dot(m3[1], vv), dot(m3[2], vv)) / s2;
        gl_Position = projectionMatrix * mvPosition;
        #include <fog_vertex>
      }`,
    fragmentShader: `uniform vec3 uIris, uIris2, uSclera, uGaze; uniform vec4 uLid; uniform vec2 uPhi; uniform float uSide, uIrisA, uPupil, uDepth, uBlink, uLight;
      varying vec3 vP; varying vec3 vNv; varying vec3 vVo;
      #include <fog_pars_fragment>
      void main() {
        vec3 n = normalize(vP);
        float ph = atan(n.x * uSide, n.z), th = asin(clamp(n.y, -1.0, 1.0));
        float uu = clamp((ph - uPhi.x) / (uPhi.y - uPhi.x), 0.0, 1.0);
        float thc = mix(uLid.z, uLid.w, uu), shp = pow(sin(3.14159 * pow(uu, 0.85)), 0.75);
        float tT = thc + uLid.x * shp, tB = thc - uLid.y * pow(sin(3.14159 * uu), 0.9);
        float shT = smoothstep(tT - 0.55, tT - 0.03, th);
        vec3 col = uSclera * (0.7 + 0.3 * smoothstep(-0.3, 0.95, n.z));
        vec3 d = normalize(uGaze);
        vec3 tu = normalize(cross(vec3(0.0, 1.0, 0.0), d)); vec3 tv = cross(d, tu);
        float cz = dot(n, d);
        vec3 V = normalize(vVo);
        vec2 q = vec2(dot(n, tu), dot(n, tv)) / sin(uIrisA);
        q -= vec2(dot(V, tu), dot(V, tv)) * uDepth * smoothstep(cos(uIrisA) - 0.2, 1.0, cz);
        float r = length(q);
        float px = max(fwidth(r), 1e-4);
        if (cz > 0.0 && r < 1.0 + px * 2.0) {
          float ang = atan(q.y, q.x);
          float aa = 1.0 - smoothstep(0.06, 0.22, px);
          vec3 ir = mix(uIris2, uIris, smoothstep(-0.65, 0.55, q.y));
          ir *= 1.0 + (0.17 * sin(ang * 31.0 + r * 7.0) + 0.09 * sin(ang * 67.0 - r * 11.0) + 0.06 * sin(ang * 13.0 + 1.7)) * aa * smoothstep(0.38, 0.62, r);
          ir += uIris2 * 0.6 * smoothstep(0.42, 0.66, r) * smoothstep(0.98, 0.72, r) * smoothstep(0.05, -0.75, q.y);
          ir = mix(ir, ir * 1.3 + 0.015, smoothstep(0.08, 0.0, abs(r - 0.47)) * aa * 0.5);
          ir = mix(ir, uIris * 0.1, smoothstep(0.76, 1.0, r));
          ir = mix(ir, vec3(0.005, 0.005, 0.01), smoothstep(uPupil + px, uPupil - px, r));
          col = mix(col, ir, smoothstep(1.0 + px, 1.0 - px, r));
        }
        col *= mix(1.0, 0.36, shT);
        col *= 0.86 + 0.14 * smoothstep(tB, tB + 0.35, th);
        col *= uLight;
        vec3 nv = normalize(vNv);
        vec3 H1 = normalize(vec3(-0.4, 0.48, 1.0)), H2 = normalize(vec3(0.32, -0.28, 1.0));
        float a1 = acos(clamp(dot(nv, H1), -1.0, 1.0)), a2 = acos(clamp(dot(nv, H2), -1.0, 1.0));
        float pa = max(fwidth(a1), 1e-3);
        float r1 = max(0.17, pa * 1.6), r2 = max(0.075, pa * 1.1);
        float c1 = smoothstep(r1 + pa, r1 - pa, a1), c2 = smoothstep(r2 + pa, r2 - pa, a2);
        float fr = pow(1.0 - clamp(nv.z, 0.0, 1.0), 3.0);
        col += vec3(0.22, 0.27, 0.34) * fr * 0.3 * (1.0 - shT);
        float open = 1.0 - uBlink;
        col = mix(col, vec3(1.55), c1 * open * (1.0 - shT * 0.55));
        col = mix(col, vec3(1.05), c2 * 0.75 * open * (1.0 - shT));
        gl_FragColor = vec4(col, 1.0);
        #include <fog_fragment>
      }`,
    fog: true,
  });
  Object.assign(m.uniforms, U);
  m.userData.U = U; m.userData.noAO = true;
  return m;
}
// lid shells: upper (lash line, lid, crease) and lower lid as spherical strips around the eyeball, rebuilt on the CPU
// when blink / squint / gaze change. Corners close; the outer rows tuck under the sculpted socket.
function ppLids(S, C, E, side) {
  const R = E.R, NP = PP_HI() ? 16 : 11;
  const skin = ppLin(C.skin), lash = ppLin(0x1a1014), lid = ppV.mul(skin, 0.97), crease = ppV.mul(ppMixC(skin, ppLin(0x8a4a48), 0.18), 0.9), rim = ppMixC(skin, ppLin(0xc06a6a), 0.35), low = ppMixC(skin, ppLin(0x5a3a3a), 0.3);
  const UP = [[0, 1.0, lash], [0.035, 1.06, lash], [0.12, 1.08, lash], [0.12, 1.08, lid], [0.3, 1.1, lid], [0.44, 1.075, crease], [0.6, 1.13, lid], [1.0, 1.32, lid]];
  const LO = [[0, 1.0, rim], [-0.04, 1.05, low], [-0.1, 1.065, low], [-0.1, 1.065, skin], [-0.38, 1.1, skin], [-0.85, 1.3, skin]];
  const rowsT = UP.length, rowsB = LO.length, nv = NP * (rowsT + rowsB);
  const pos = new Float32Array(nv * 3), col = new Float32Array(nv * 3), idx = [];
  const ph0 = -1.25, ph1 = 1.32;
  let o = 0;
  for (const rows of [UP, LO]) {
    const rev = (rows === LO) !== (side < 0);
    for (let r = 0; r < rows.length; r++) for (let k = 0; k < NP; k++) col.set(rows[r][2], (o + r * NP + k) * 3);
    for (let r = 0; r < rows.length - 1; r++) for (let k = 0; k < NP - 1; k++) {
      const a = o + r * NP + k, b = a + 1, c = a + NP + 1, d = a + NP;
      if (rev) idx.push(a, c, b, a, d, c); else idx.push(a, b, c, a, c, d);
    }
    o += rows.length * NP;
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  g.setAttribute('color', new THREE.BufferAttribute(col, 3));
  const mA = new Float32Array(nv * 4); for (let q = 0; q < nv; q++) mA.set(PP_M.skin, q * 4);
  g.setAttribute('aM', new THREE.BufferAttribute(mA, 4));
  g.setAttribute('aUV2', new THREE.BufferAttribute(new Float32Array(nv * 2).fill(-1), 2));
  g.setAttribute('aTan', new THREE.BufferAttribute(new Float32Array(nv * 3), 3));
  g.setAttribute('aAO', new THREE.BufferAttribute(new Float32Array(nv).fill(1), 1));
  g.setIndex(idx);
  const L = { g, tT: 0.5, tB: 0.42, c0: -0.04, c1: 0.08, phA: -0.95, phB: 1.0, last: '' };
  const Ht = S.kid ? 0.5 : S.fem ? 0.44 : S.elder ? 0.34 : 0.4, Hb = S.kid ? 0.36 : S.elder ? 0.24 : 0.28, c0 = -0.06, c1 = S.fem ? 0.12 : 0.08;
  L.update = (blink, squint, gy) => {
    const key = blink.toFixed(3) + squint.toFixed(3) + gy.toFixed(3);
    if (key === L.last) return; L.last = key;
    const look = clamp(gy, -0.4, 0.4);
    const ht = Ht * (1 - 0.22 * squint) + look * 0.55, hb = Hb * (1 - 0.45 * squint) - look * 0.25;
    L.tT = ht; L.tB = hb; L.c0 = c0; L.c1 = c1;
    let q = 0;
    for (let part = 0; part < 2; part++) {
      const rows = part === 0 ? UP : LO;
      for (let r = 0; r < rows.length; r++) for (let k = 0; k < NP; k++, q++) {
        const ph = ph0 + (ph1 - ph0) * (k / (NP - 1)), uu = (ph - L.phA) / (L.phB - L.phA), uc = clamp(uu, 0, 1);
        const thc = lerp(c0, c1, uc), inside = uu > 0 && uu < 1;
        const sT = inside ? Math.pow(Math.sin(Math.PI * Math.pow(uc, 0.85)), 0.75) : 0, sB = inside ? Math.pow(Math.sin(Math.PI * uc), 0.9) : 0;
        let eT = thc + ht * sT, eB = thc - hb * sB;
        const close = eB + (eT - eB) * 0.18;
        eT = lerp(eT, close, blink); eB = lerp(eB, close, blink * 0.9);
        const th = (part === 0 ? eT : eB) + rows[r][0], rr = R * rows[r][1];
        pos[q * 3] = side * rr * Math.cos(th) * Math.sin(ph); pos[q * 3 + 1] = rr * Math.sin(th); pos[q * 3 + 2] = rr * Math.cos(th) * Math.cos(ph);
      }
    }
    g.attributes.position.needsUpdate = true;
    g.computeVertexNormals();
    const n = g.attributes.normal.array;
    // normals must point away from the eyeball (checked once; both lids share one winding convention)
    let flip = 0; for (let i = 0; i < nv; i += 7) flip += n[i * 3] * pos[i * 3] + n[i * 3 + 1] * pos[i * 3 + 1] + n[i * 3 + 2] * pos[i * 3 + 2];
    if (flip < 0) { for (let i = 0; i < n.length; i++) n[i] = -n[i]; const I = g.index.array; for (let t = 0; t < I.length; t += 3) { const a = I[t + 1]; I[t + 1] = I[t + 2]; I[t + 2] = a; } g.index.needsUpdate = true; }
  };
  L.update(0, 0, 0);
  return L;
}

// ---------------------------------------------------------------- cloth tails (scarf ends, coat tails, sash ribbons)
function ppRibbon(parent, o) {
  const L = o.length, seg = 8, taper = o.taper ?? 0.3;
  const g = new THREE.PlaneGeometry(o.width, L, 1, seg); g.translate(0, -L / 2, 0);
  const p = g.attributes.position, n = p.count;
  const uv2 = new Float32Array(n * 2), col = new Float32Array(n * 3), mA = new Float32Array(n * 4), c = ppLin(o.color);
  for (let i = 0; i < n; i++) { const t = -p.getY(i) / L; uv2[i * 2] = t; uv2[i * 2 + 1] = -1; p.setX(i, p.getX(i) * (1 - t * taper)); col.set(c, i * 3); mA.set(o.m || PP_M.satin, i * 4); }
  g.setAttribute('aUV2', new THREE.BufferAttribute(uv2, 2)); g.setAttribute('color', new THREE.BufferAttribute(col, 3)); g.setAttribute('aM', new THREE.BufferAttribute(mA, 4));
  g.setAttribute('aTan', new THREE.BufferAttribute(new Float32Array(n * 3), 3)); g.setAttribute('aAO', new THREE.BufferAttribute(new Float32Array(n).fill(1), 1));
  const U = { uTime: Shared.time, uMove: { value: 0 }, uPh: { value: o.ph || 0 }, uStiff: { value: o.stiff ?? 1 } };
  const mat = ppMaterial('ribbon', U); mat.side = THREE.DoubleSide;
  const m = new THREE.Mesh(g, mat); m.position.set(...o.pos); m.rotation.set(...o.rot); m.castShadow = true;
  parent.add(m);
  return { mesh: m, uMove: U.uMove };
}
// staff: carved shaft, three-prong head holding a glowing crystal (rides the right hand, kept upright per frame)
function ppStaff(S, C) {
  const u = S.u, g = new THREE.Group(), low = S.j.handR[1] * 0.985, top = S.H * (S.elder ? 0.42 : 0.5);
  const parts = [];
  const shaft = [], n = 10;
  for (let i = 0; i < n; i++) { const t = i / (n - 1); shaft.push([Math.sin(t * 5.0) * 0.006 * u, -low + (low + top) * t, Math.cos(t * 4.0) * 0.006 * u]); }
  const sw = shaft.map((p, i) => (0.072 - 0.012 * (i / (n - 1))) * u);
  parts.push(ppFill(ppSweep(shaft, sw, sw, () => [1, 0, 0], { seg: 8 }), ppLin(0x5a3b26), PP_M.wood));
  for (let k = 0; k < 3; k++) {
    const a = (k / 3) * Math.PI * 2, pts = [];
    for (let i = 0; i < 6; i++) { const t = i / 5, r = (0.06 + 0.2 * Math.sin(Math.PI * t * 0.85)) * u; pts.push([Math.cos(a) * r, top - 0.05 * u + t * 0.55 * u, Math.sin(a) * r]); }
    const w = pts.map((p, i) => (0.045 - 0.032 * (i / 5)) * u);
    parts.push(ppFill(ppSweep(pts, w, w, () => [Math.cos(a), 0, Math.sin(a)], { seg: 6 }), ppLin(0x6a4a2e), PP_M.wood));
  }
  for (const y of [top - 0.08 * u, -0.25 * u]) parts.push(ppFill(ppSweep([[0, y - 0.03 * u, 0], [0, y + 0.03 * u, 0]], [0.09 * u, 0.09 * u], [0.09 * u, 0.09 * u], () => [1, 0, 0], { seg: 10 }), ppLin(0xc8a050), PP_M.metal));
  const mesh = new THREE.Mesh(ppMerge(parts), ppMaterial()); mesh.castShadow = true;
  g.add(mesh);
  const gem = part(GEO.octa, E(C.staff, 2.6), g, [0, top + 0.3 * u, 0], [0.12 * u, 0.2 * u, 0.12 * u]);
  gem.userData.noOl = true;
  return { g, gem };
}

// ---------------------------------------------------------------- procedural animation
// t: rig time, dt, mv: 0 idle · 1 jog · ~1.4 sprint (World uses 6 / 10.5 units per second)
const _ppV1 = new THREE.Vector3(), _ppV2 = new THREE.Vector3(), _ppQ1 = new THREE.Quaternion(), _ppQ2 = new THREE.Quaternion(), _ppM4 = new THREE.Matrix4();
function ppAnimator(r, S, B, eyes, extras) {
  const st = { ph: Math.random() * 6, hy: 0, hp: 0, ha: 0, hv: 0, bl: -1, blT: 1 + Math.random() * 3, dbl: 0, sac: [0, 0], sacT: 0, seed: Math.random() * 100, look: null, gp: 0, prevY: 0 };
  r.pp = st;
  const kid = S.kid, elder = S.elder, staff = !!S.C.staff, u = S.u;
  const hips0 = B.hips.position.clone();
  return (t, dt, mv) => {
    dt = Math.min(dt, 0.05);
    const walk = smooth(0.03, 0.3, mv), run = smooth(0.5, 1.05, mv), spr = smooth(1.05, 1.35, mv), idle = 1 - walk;
    const cad = (kid ? 1.3 : 1.0) * (lerp(1.05, 1.42, run) + 0.32 * spr) * (elder ? 0.82 : 1);
    if (walk > 0.001) st.ph += dt * Math.PI * 2 * cad;
    const ph = st.ph, T = t + st.seed, br = Math.sin(T * (kid ? 2.1 : 1.6));
    // ---- pelvis
    const sw = Math.sin(T * 0.42) * idle;
    B.hips.position.set(hips0.x + sw * 0.07 * u, hips0.y - walk * ((0.04 + 0.1 * run) * Math.cos(2 * ph) + 0.06 * run) * u - idle * (elder ? 0.05 * u : 0), hips0.z);
    const hipYaw = -walk * (0.13 - 0.05 * run) * Math.sin(ph), hipRoll = -walk * 0.045 * Math.cos(ph) + sw * 0.04;
    B.hips.rotation.set(walk * (0.04 + 0.06 * run), hipYaw, hipRoll);
    // ---- legs
    for (const [X, off] of [['L', 0], ['R', Math.PI]]) {
      const p = ph + off, sp = Math.sin(p), cp = Math.cos(p);
      const At = walk * (0.36 + 0.3 * run + 0.14 * spr);
      const thx = -At * sp - walk * (0.04 + 0.1 * run);
      const kn = walk * (0.08 + (0.62 + 0.95 * run + 0.35 * spr) * Math.pow(Math.max(0, Math.cos(p + 0.35)), 1.3) + 0.22 * run * Math.pow(Math.max(0, -cp), 2));
      const stance = smooth(-0.2, 0.3, -cp);
      const foot = lerp(-0.25 * kn + 0.08 * walk, -(thx + kn), stance) + walk * 0.55 * (0.5 + 0.5 * run) * Math.pow(Math.max(0, -Math.sin(p + 0.6)), 3) - walk * 0.1 * Math.pow(Math.max(0, sp), 2);
      // idle: weight on one leg, the other knee relaxed; elder bends both a little
      const relax = idle * (0.5 + 0.5 * Math.sin(T * 0.42 + (X === 'L' ? 0 : Math.PI))) * 0.12 + (elder ? 0.08 * idle : 0);
      B['thigh' + X].rotation.set(thx - relax * 0.6, -hipYaw * 0.6, -hipRoll);
      B['shin' + X].rotation.set(kn + relax * 1.2, 0, 0);
      B['foot' + X].rotation.set(foot - relax * 0.6 + B.hips.rotation.x * -1, 0, 0);
    }
    // ---- spine, chest (counter-twist, breathing), lean with speed
    const lean = walk * (0.05 + 0.12 * run + 0.1 * spr) + (elder ? 0.16 : 0) + (S.guard ? -0.03 : 0);
    B.spine.rotation.set(lean * 0.55 + idle * 0.006 * br, -hipYaw * 0.4, -hipRoll * 0.55);
    B.chest.rotation.set(lean * 0.45 + (elder ? 0.08 : 0) - idle * 0.018 * br, -hipYaw * 0.7 + walk * 0.13 * Math.sin(ph), -hipRoll * 0.35);
    // ---- look-at: head and neck turn toward the target, eyes do the rest
    let tgt = null;
    if (r.gazeAt) tgt = r.gazeAt.isObject3D ? r.gazeAt.getWorldPosition(_ppV1) : _ppV1.copy(r.gazeAt);
    else if (typeof World !== 'undefined' && World.player && World.player.root) {
      const me = r.root.position;
      if (World.player !== r) { const pp = World.player.root.position; if (Math.hypot(pp.x - me.x, pp.z - me.z) < 7) tgt = _ppV1.set(pp.x, pp.y + (World.player.headY || 1.8), pp.z); }
      else if (mv < 0.1 && World.npcs) {
        let best = 4.5;
        for (const n of World.npcs) { const q = n.rig.root.position, d = Math.hypot(q.x - me.x, q.z - me.z); if (d < best) { best = d; tgt = _ppV1.set(q.x, q.y + (n.rig.headY || 1.7), q.z); } }
      }
    }
    let yaw = 0, pitch = 0;
    if (tgt) {
      r.body.updateMatrixWorld();
      _ppV2.copy(tgt); r.body.worldToLocal(_ppV2);
      const dx = _ppV2.x - S.j.head[0], dy = _ppV2.y - S.hc[1], dz = _ppV2.z - S.j.head[2];
      const ya = Math.atan2(dx, dz);
      if (Math.abs(ya) < 1.9) { yaw = clamp(ya, -1.05, 1.05); pitch = clamp(Math.atan2(dy, Math.hypot(dx, dz)), -0.45, 0.35); }
      st.look = (st.look || new THREE.Vector3()).copy(tgt);
    } else st.look = null;
    yaw += idle * 0.12 * Math.sin(T * 0.23) * (tgt ? 0.3 : 1); pitch += idle * 0.04 * Math.sin(T * 0.31 + 1);
    if (Math.abs(yaw * 0.75 - st.hy) > 0.45 && st.bl < 0) st.blT = 0;
    st.hy = damp(st.hy, yaw * 0.75, 3.2, dt); st.hp = damp(st.hp, pitch * 0.6, 3.2, dt); st.gp = pitch;
    const comp = lean + (elder ? 0.08 : 0);
    B.neck.rotation.set(-comp * 0.45 + st.hp * 0.35 + (elder ? 0.12 : 0), st.hy * 0.4, 0);
    B.head.rotation.set(-comp * 0.45 + st.hp * 0.65 - (elder ? 0.18 : 0) + walk * 0.03 * Math.cos(2 * ph), st.hy * 0.6, idle * 0.03 * Math.sin(T * 0.37));
    // ---- arms (opposite to the legs), elbows bend more when running
    for (const [X, off, sg] of [['L', 0, 1], ['R', Math.PI, -1]]) {
      const p = ph + off, sp = Math.sin(p);
      const Aa = walk * (0.4 + 0.22 * run + 0.12 * spr);
      let ax = Aa * sp * (sp < 0 ? 0.75 : 1.15) + idle * (0.035 * Math.sin(T * 0.8 + off) - 0.05), az = -sg * (0.13 - 0.07 * run) + sg * idle * 0.012 * br;
      let fx = -(0.24 * idle + walk * (0.28 + 1.05 * run + 0.15 * spr) + walk * (0.25 + 0.3 * run) * Math.max(0, -sp)), fy = 0;
      if (staff && X === 'R') { ax = -0.32 + 0.06 * sp * walk; az = 0.04; fx = -1.25; fy = 0.1; }
      if (kid) ax *= 1.15;
      B['arm' + X].rotation.set(ax, 0, az);
      B['fore' + X].rotation.set(fx, fy, 0);
      B['hand' + X].rotation.set(walk * 0.12 * sp - 0.05, 0, sg * walk * 0.1 * run);
      B['clav' + X].rotation.set(0, 0, sg * (idle * 0.016 * br + walk * 0.035 * sp * run));
    }
    // ---- hair spring (long locks trail when running)
    const ht = 0.12 * walk + 0.22 * run + 0.06 * spr + 0.05 * walk * Math.sin(2 * ph) + 0.03 * Math.sin(T * 1.3);
    st.hv += ((ht - st.ha) * 60 - st.hv * 9) * dt; st.ha += st.hv * dt;
    B.hairB.rotation.set(st.ha, 0, 0.03 * Math.sin(T * 0.9));
    // ---- blinks (120–150 ms, sometimes double), saccades
    st.blT -= dt;
    if (st.bl < 0 && st.blT <= 0) { st.bl = 0; st.blT = 2 + Math.random() * 3.5; if (Math.random() < 0.2) st.dbl = 1; }
    let bv = 0;
    if (st.bl >= 0) {
      st.bl += dt;
      const a = st.bl; bv = a < 0.05 ? (a / 0.05) * (a / 0.05) : a < 0.075 ? 1 : a < 0.15 ? 1 - Math.pow((a - 0.075) / 0.075, 0.7) : 0;
      if (a >= 0.15) { st.bl = -1; if (st.dbl) { st.dbl = 0; st.blT = 0.12; } }
    }
    st.sacT -= dt;
    if (st.sacT <= 0) { st.sacT = 1 + Math.random() * 2; const still = Math.random() < 0.3; st.sac[0] = still ? 0 : (Math.random() - 0.5) * 0.14; st.sac[1] = still ? 0 : (Math.random() - 0.5) * 0.08; }
    const squint = r.expr === 'happy' ? 1 : r.expr === 'hurt' ? 0.6 : 0;
    for (const E of eyes) {
      E.L.update(Math.max(bv, r.expr === 'hurt' ? 0.75 : 0), squint, st.gp * 0.8);
      const U = E.U; U.uLid.value.set(E.L.tT, E.L.tB, E.L.c0, E.L.c1); U.uPhi.value.set(E.L.phA, E.L.phB); U.uBlink.value = bv;
    }
    for (const c of extras.cloth) c.uMove.value = damp(c.uMove.value, mv, 5, dt);
    if (extras.staff) {
      // keep the staff upright in the character's frame, whatever the hand does
      const sg = extras.staff.g;
      sg.parent.updateWorldMatrix(true, false);
      sg.parent.getWorldQuaternion(_ppQ1).invert();
      r.body.getWorldQuaternion(_ppQ2);
      sg.quaternion.copy(_ppQ1.multiply(_ppQ2));
      extras.staff.gem.rotation.y += dt * 0.8;
    }
  };
}
// eyes look where the rig looks; when a camera is close in front (portraits, dialogue close-ups) they meet it
function ppEyeGaze(r, E, cam) {
  const st = r.pp; if (!st) return;
  const g = E.g; g.updateWorldMatrix(true, false);
  let tgt = null;
  if (cam) {
    _ppV2.setFromMatrixPosition(cam.matrixWorld);
    const hp = _ppV1.setFromMatrixPosition(g.matrixWorld), d = _ppV2.distanceTo(hp);
    if (d < 3.4) { const to = _ppV2.clone().sub(hp).normalize(); g.getWorldDirection(_ppV1); if (_ppV1.dot(to) > 0.45) tgt = _ppV2; }
  }
  if (!tgt && st.look) tgt = _ppV2.copy(st.look);
  let yaw = 0, pitch = 0;
  if (tgt) {
    _ppM4.copy(g.matrixWorld).invert(); const l = tgt.clone().applyMatrix4(_ppM4);
    yaw = Math.atan2(l.x * E.side, l.z); pitch = Math.atan2(l.y, Math.hypot(l.x, l.z));
    if (Math.abs(yaw) > 1.6) { yaw = 0; pitch = 0; }
  }
  yaw = clamp(yaw + st.sac[0] * E.side, -0.17, 0.42); pitch = clamp(pitch + st.sac[1], -0.32, 0.26);
  const cy = Math.cos(pitch);
  E.U.uGaze.value.set(E.side * Math.sin(yaw) * cy, Math.sin(pitch), Math.cos(yaw) * cy);
}

// ---------------------------------------------------------------- build a person rig
const _ppEyeGeo = {};
function buildPerson(o = {}) {
  const C = Object.assign({ skin: 0xffdcc6, hair: 0x2a2238, top: 0x2c4a8a, shirt: 0xf2f2f6, trim: 0xf4f0e6, bottom: 0x2a2e3e, shoe: 0x6a4026, glove: 0x3a2a20, accent: 0x8b5cff, pack: true }, o);
  if (o.top !== undefined && o.trim === undefined) C.trim = 0xf4ecd8;
  const r = newRig(); r.hopAmp = 0; r.olw = 0; r.person = true; r.noBreath = true;
  const { S, geo } = ppBuild(C);
  const u = S.u;
  // skeleton
  const B = {}, list = [];
  for (const n of PP_BONES) { const b = new THREE.Bone(); b.name = n; B[n] = b; list.push(b); }
  const J = (n) => (n === 'base' ? [0, 0, 0] : S.j[n]);
  for (const n of PP_BONES) {
    const p = PP_PARENT[n], jp = J(n);
    if (p) { const pj = J(p); B[n].position.set(jp[0] - pj[0], jp[1] - pj[1], jp[2] - pj[2]); B[p].add(B[n]); } else B[n].position.set(jp[0], jp[1], jp[2]);
  }
  r.body.add(B.base);
  const mesh = new THREE.SkinnedMesh(geo, ppMaterial());
  mesh.castShadow = true; mesh.receiveShadow = true;
  r.body.add(mesh);
  r.body.updateMatrixWorld(true);
  const skel = new THREE.Skeleton(list);
  mesh.bind(skel);
  const ol = new THREE.SkinnedMesh(geo, ppOutlineMat());
  ol.bind(skel, mesh.bindMatrix); ol.userData.isOl = true; ol.castShadow = false; ol.raycast = () => {};
  ol.onBeforeRender = (rr) => { rr.getDrawingBufferSize(_ppRes); if (_ppRes.y > 0) ol.material.userData.U.uOlRes.value.copy(_ppRes); };
  r.body.add(ol);
  const bs = new THREE.Sphere(new THREE.Vector3(0, S.H * 0.5, 0), S.H * 0.8);
  mesh.boundingSphere = bs; ol.boundingSphere = bs.clone();
  // eyes + lids (children of the head bone)
  const eyes = [];
  for (const E0 of S.eyes) {
    const g = grp(B.head, ppV.sub(E0.c, S.j.head), [0, E0.yaw, 0]);
    const gk = E0.R.toFixed(4) + (PP_HI() ? 'h' : 'l');
    const eg = _ppEyeGeo[gk] || (_ppEyeGeo[gk] = new THREE.SphereGeometry(E0.R, PP_HI() ? 32 : 20, PP_HI() ? 24 : 14));
    const em = ppEyeMat(C, S, E0.s);
    const ball = new THREE.Mesh(eg, em); ball.userData.noOl = true; g.add(ball);
    const L = ppLids(S, C, E0, E0.s);
    const lid = new THREE.Mesh(L.g, ppMaterial()); lid.userData.noOl = true; g.add(lid);
    const E = { g, U: em.userData.U, L, side: E0.s };
    ball.onBeforeRender = (rr, sc, cam) => ppEyeGaze(r, E, cam);
    eyes.push(E);
  }
  // accessories
  const extras = { cloth: [], staff: null };
  const j = S.j;
  if (S.kind === 'hero') {
    extras.cloth.push(ppRibbon(B.chest, { pos: [0.04 * u, j.neck[1] - j.chest[1] + 0.0 * u, -(S.W.neck + 0.2) * u], rot: [0.3, 0.2, 0.1], length: 1.7 * u, width: 0.34 * u, color: C.accent, ph: 0 }));
    extras.cloth.push(ppRibbon(B.chest, { pos: [-0.04 * u, j.neck[1] - j.chest[1] - 0.02 * u, -(S.W.neck + 0.2) * u], rot: [0.24, -0.18, -0.07], length: 1.35 * u, width: 0.3 * u, color: C.accent, ph: 1.7 }));
    for (const s of [-1, 1]) extras.cloth.push(ppRibbon(B.hips, { pos: [s * 0.2 * u, j.spine[1] - j.hips[1] - 0.32 * u, -(S.W.hipD + 0.08) * u], rot: [0.12, s * 0.12, s * 0.06], length: 0.95 * u, width: 0.5 * u, color: C.top, ph: s * 1.3, stiff: 0.45, taper: 0.1, m: PP_M.cloth }));
  } else if (S.kind === 'healer' || S.kind === 'robe') {
    const y = (S.kind === 'robe' ? j.spine[1] - 0.12 * u : j.spine[1] + 0.02 * u) - j.hips[1], side = S.kind === 'robe' ? 1 : 0;
    const z = S.kind === 'robe' ? (S.W.waistD + 0.12 + (S.elder ? 0.12 : 0)) * u : -(S.W.waistD + 0.1) * u;
    for (const s of [-1, 1]) extras.cloth.push(ppRibbon(B.hips, { pos: [side * 0.25 * u + s * 0.06 * u, y, z], rot: [z > 0 ? -0.1 : 0.1, s * 0.15, s * 0.08], length: (S.kind === 'robe' ? 1.6 : 1.3) * u, width: 0.2 * u, color: C.accent, ph: s * 1.1, stiff: 0.6, taper: 0.2 }));
  }
  if (C.staff) { extras.staff = ppStaff(S, C); const grip = ppV.add(ppV.mul(ppV.norm(ppV.sub(j.handR, j.foreR)), 0.24 * u), [0.02 * u, 0, 0]); extras.staff.g.position.set(...grip); B.handR.add(extras.staff.g); }
  if (o.pendant !== false && !C.robe && S.pendant) { const gm = part(GEO.octa, E(0xb48cff, 2.2), B.chest, ppV.sub(S.pendant, j.chest), [0.05 * u, 0.08 * u, 0.03 * u]); gm.userData.noOl = true; }
  if (C.pin && S.pinPos) {
    const pg = grp(B.head, ppV.sub(S.pinPos, j.head), [0.2, 0.3, -0.5]);
    part(GEO.box, M(0xd8b060), pg, [0, 0, 0], [0.03 * u, 0.13 * u, 0.02 * u]);
    part(GEO.octa, E(C.pin, 2.4), pg, [0, 0.08 * u, 0.015 * u], [0.04 * u, 0.06 * u, 0.025 * u]).userData.noOl = true;
  }
  r.fns.push(ppAnimator(r, S, B, eyes, extras));
  r.bones = B; r.skel = skel; r.pp.S = S;
  r.size = S.H * 0.95;
  r.headY = S.hc[1];
  try { if (typeof contactShadow === 'function') { const c = contactShadow(r); if (c) { c.scale.set(u * (S.robe ? 3.4 : 2.7), 1, u * (S.robe ? 3.0 : 2.4)); c.position.set(0, 0.025, 0.06 * u); } } } catch (e) {}
  rigUpdate(r, 0.001);
  return r;
}
