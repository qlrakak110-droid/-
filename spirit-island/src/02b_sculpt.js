// ============================================================================
//  sculpt: signed-distance modelling → surface-nets mesh (organic, seamless bodies)
//  Pure JS (no THREE) so it can be tested headless; dragons.js wraps it in materials.
// ============================================================================
const SDF = {
  // round cone between a and b with radii r1 → r2 (iq). s0/s1: spine parameter at a/b
  rc(a, b, r1, r2, o = {}) {
    const ba = [b[0] - a[0], b[1] - a[1], b[2] - a[2]], l2 = ba[0] * ba[0] + ba[1] * ba[1] + ba[2] * ba[2];
    const rr = r1 - r2;
    return Object.assign({ t: 0, a, b, r1, r2, ba, l2, rr, a2: l2 - rr * rr, il2: 1 / l2, k: 0.1, s0: 0, s1: 0, col: null, jaw: 0, glow: 0, belly: 0, leg: 0, nz: 0, nf: 6, sub: false }, o);
  },
  el(c, r, o = {}) { return Object.assign({ t: 1, c, r, k: 0.1, s0: 0, s1: 0, col: null, jaw: 0, glow: 0, belly: 0, leg: 0, nz: 0, nf: 6, sub: false }, o); },
  dist(P, x, y, z) {
    if (P.nz) return SDF.dist0(P, x, y, z) + (vn3js(x * P.nf, y * P.nf, z * P.nf) - 0.5) * P.nz;
    return SDF.dist0(P, x, y, z);
  },
  dist0(P, x, y, z) {
    if (P.t === 0) {
      const pa0 = x - P.a[0], pa1 = y - P.a[1], pa2 = z - P.a[2];
      const yy = pa0 * P.ba[0] + pa1 * P.ba[1] + pa2 * P.ba[2], zz = yy - P.l2;
      const q0 = pa0 * P.l2 - P.ba[0] * yy, q1 = pa1 * P.l2 - P.ba[1] * yy, q2 = pa2 * P.l2 - P.ba[2] * yy;
      const x2 = q0 * q0 + q1 * q1 + q2 * q2, y2 = yy * yy * P.l2, z2 = zz * zz * P.l2;
      const k = Math.sign(P.rr) * P.rr * P.rr * x2;
      if (Math.sign(zz) * P.a2 * z2 > k) return Math.sqrt(x2 + z2) * P.il2 - P.r2;
      if (Math.sign(yy) * P.a2 * y2 < k) return Math.sqrt(x2 + y2) * P.il2 - P.r1;
      return (Math.sqrt(x2 * P.a2 * P.il2) + yy * P.rr) * P.il2 - P.r1;
    }
    const px = (x - P.c[0]) / P.r[0], py = (y - P.c[1]) / P.r[1], pz = (z - P.c[2]) / P.r[2];
    const k0 = Math.sqrt(px * px + py * py + pz * pz);
    const qx = px / P.r[0], qy = py / P.r[1], qz = pz / P.r[2];
    const k1 = Math.sqrt(qx * qx + qy * qy + qz * qz);
    return k1 > 1e-9 ? k0 * (k0 - 1) / k1 : -Math.min(P.r[0], P.r[1], P.r[2]);
  },
  // parameter along the primitive (0 at a, 1 at b) for attribute blending
  along(P, x, y, z) {
    if (P.t !== 0) return 0.5;
    const t = ((x - P.a[0]) * P.ba[0] + (y - P.a[1]) * P.ba[1] + (z - P.a[2]) * P.ba[2]) * P.il2;
    return t < 0 ? 0 : t > 1 ? 1 : t;
  },
  aabb(P) {
    const m = P.k + 0.02 + (P.nz || 0);
    if (P.t === 0) {
      const R = Math.max(P.r1, P.r2) + m;
      return [Math.min(P.a[0], P.b[0]) - R, Math.min(P.a[1], P.b[1]) - R, Math.min(P.a[2], P.b[2]) - R, Math.max(P.a[0], P.b[0]) + R, Math.max(P.a[1], P.b[1]) + R, Math.max(P.a[2], P.b[2]) + R];
    }
    return [P.c[0] - P.r[0] - m, P.c[1] - P.r[1] - m, P.c[2] - P.r[2] - m, P.c[0] + P.r[0] + m, P.c[1] + P.r[1] + m, P.c[2] + P.r[2] + m];
  },
};
function vn3js(x, y, z) {
  const xi = Math.floor(x), yi = Math.floor(y), zi = Math.floor(z), xf = x - xi, yf = y - yi, zf = z - zi;
  const u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf), w = zf * zf * (3 - 2 * zf);
  const h = (a, b, c) => hash2(a * 7 + c * 131, b * 13 - c * 57);
  const l = (a, b, t) => a + (b - a) * t;
  return l(l(l(h(xi, yi, zi), h(xi + 1, yi, zi), u), l(h(xi, yi + 1, zi), h(xi + 1, yi + 1, zi), u), v),
           l(l(h(xi, yi, zi + 1), h(xi + 1, yi, zi + 1), u), l(h(xi, yi + 1, zi + 1), h(xi + 1, yi + 1, zi + 1), u), v), w);
}
function sminP(a, b, k) { const h = Math.max(k - Math.abs(a - b), 0) / k; return Math.min(a, b) - h * h * k * 0.25; }

// stamp every primitive into a dense grid (only inside its own box), then mesh with naive surface nets
function sculptMesh(prims, bounds, cell) {
  const [x0, y0, z0, x1, y1, z1] = bounds;
  const nx = Math.ceil((x1 - x0) / cell) + 1, ny = Math.ceil((y1 - y0) / cell) + 1, nz = Math.ceil((z1 - z0) / cell) + 1;
  const N = nx * ny * nz, grid = new Float32Array(N).fill(1e3);
  const sxy = nx * ny;
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
    fx = Math.min(Math.max(fx, 0), nx - 1.001); fy = Math.min(Math.max(fy, 0), ny - 1.001); fz = Math.min(Math.max(fz, 0), nz - 1.001);
    const i = fx | 0, j = fy | 0, k = fz | 0, u = fx - i, v = fy - j, w = fz - k;
    const c00 = at(i, j, k) * (1 - u) + at(i + 1, j, k) * u, c10 = at(i, j + 1, k) * (1 - u) + at(i + 1, j + 1, k) * u;
    const c01 = at(i, j, k + 1) * (1 - u) + at(i + 1, j, k + 1) * u, c11 = at(i, j + 1, k + 1) * (1 - u) + at(i + 1, j + 1, k + 1) * u;
    return (c00 * (1 - v) + c10 * v) * (1 - w) + (c01 * (1 - v) + c11 * v) * w;
  };
  // vertices: one per sign-changing cell, at the mean of its edge crossings
  const cellV = new Int32Array(N).fill(-1);
  let pos = new Float32Array(1 << 18), nv = 0;
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
  // normals from the field gradient
  const nor = new Float32Array(nv * 3), h = cell * 0.6;
  for (let q = 0; q < nv; q++) {
    const x = pos[q * 3], y = pos[q * 3 + 1], z = pos[q * 3 + 2];
    let gx = sample(x + h, y, z) - sample(x - h, y, z), gy = sample(x, y + h, z) - sample(x, y - h, z), gz = sample(x, y, z + h) - sample(x, y, z - h);
    const l = Math.hypot(gx, gy, gz) || 1; nor[q * 3] = gx / l; nor[q * 3 + 1] = gy / l; nor[q * 3 + 2] = gz / l;
  }
  // faces: every sign-changing grid edge joins the four cells around it
  let idx = new Uint32Array(1 << 19), ni = 0;
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
  // per-vertex attributes blended from nearby primitives (soft nearest)
  const col = new Float32Array(nv * 3), aS = new Float32Array(nv), aJaw = new Float32Array(nv), aGlow = new Float32Array(nv), aBelly = new Float32Array(nv), aLeg = new Float32Array(nv);
  const add = prims.filter((P) => !P.sub);
  const boxes = add.map((P) => SDF.aabb(P));
  const ds = new Float64Array(add.length);
  for (let q = 0; q < nv; q++) {
    const x = pos[q * 3], y = pos[q * 3 + 1], z = pos[q * 3 + 2];
    let dmin = 1e9;
    for (let p = 0; p < add.length; p++) {
      const b = boxes[p];
      if (x < b[0] - 0.2 || y < b[1] - 0.2 || z < b[2] - 0.2 || x > b[3] + 0.2 || y > b[4] + 0.2 || z > b[5] + 0.2) { ds[p] = 1e9; continue; }
      ds[p] = SDF.dist(add[p], x, y, z); if (ds[p] < dmin) dmin = ds[p];
    }
    let W = 0, cr = 0, cg = 0, cb = 0, s = 0, jw = 0, gl = 0, be = 0, lg = 0;
    for (let p = 0; p < add.length; p++) {
      if (ds[p] > dmin + 0.12) continue;
      const P = add[p], w = Math.exp(-(ds[p] - dmin) / 0.025);
      const c = P.col || [1, 1, 1];
      W += w; cr += c[0] * w; cg += c[1] * w; cb += c[2] * w;
      s += (P.s0 + (P.s1 - P.s0) * SDF.along(P, x, y, z)) * w; jw += P.jaw * w; gl += P.glow * w; be += P.belly * w; lg += P.leg * w;
    }
    if (W <= 0) { W = 1; cr = cg = cb = 1; }
    col[q * 3] = cr / W; col[q * 3 + 1] = cg / W; col[q * 3 + 2] = cb / W;
    aS[q] = s / W; aJaw[q] = jw / W; aGlow[q] = gl / W; aBelly[q] = be / W; aLeg[q] = lg / W;
  }
  return { pos, nor, idx, col, aS, aJaw, aGlow, aBelly, aLeg, nv, nt: ni / 3, sample };
}

// Catmull-Rom through control points → dense list of {p, r, s}
function spinePath(pts, radii, sub = 4) {
  const out = [], n = pts.length;
  const cr = (p0, p1, p2, p3, t) => { const t2 = t * t, t3 = t2 * t; return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3); };
  for (let i = 0; i < n - 1; i++) {
    const p0 = pts[Math.max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[Math.min(n - 1, i + 2)];
    for (let k = 0; k < sub; k++) {
      const t = k / sub;
      out.push({ p: [0, 1, 2].map((a) => cr(p0[a], p1[a], p2[a], p3[a], t)), r: radii[i] + (radii[i + 1] - radii[i]) * t, s: (i + t) / (n - 1) });
    }
  }
  out.push({ p: pts[n - 1].slice(), r: radii[n - 1], s: 1 });
  return out;
}
