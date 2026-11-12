// Procedural PBR texture sets for the character material (src/char/materials.js). Every set is a pair of tileable
// RGBA8 layers in one DataArrayTexture (sampler2DArray: no atlas bleeding, repeat wrap and mipmaps per layer):
//
//   layer A  R albedo variation (0.5 = neutral)   G roughness variation (0.5 = neutral)
//            B height / proximity (scorched: heat halo around cracks; engraved: groove halo)   A wear / chip noise
//   layer B  RG tangent-space normal (from the height field, Sobel)   B micro cavity (1 = open, 0 = deep crevice)
//            A set mask (scorched: crack cores; engraved: groove cores; cloth: weave gaps; fur: strand coverage;
//              mail: ring coverage; quilted: stitch lines)
//
// Generated once per page (deterministic: seeded RNG, pure JS, no canvas readback), shared by every character.
// Size 512 (default) costs ~16 MB of GPU memory with mips; configureTextureSets({ size: 256 }) for the low tier.

import * as THREE from 'three';
import { makeRng } from '../../core/math.js';

/** Texture set ids (also the `set` of a surface look). 0 is the legacy detail texture of the original kit material. */
export const SET = { legacy: 0, hammered: 1, scorched: 2, engraved: 3, leather: 4, cloth: 5, fur: 6, mail: 7, quilted: 8 };
export const SET_COUNT = 8;
/** Default tiles per metre of each set (index = set id). */
export const SET_SCALE = [0, 4.2, 3.4, 7.5, 9, 22, 6, 7.5, 6.5];
/** Normal strength of each set (index = set id). */
export const SET_BUMP = [0, 0.75, 0.75, 1.2, 1.0, 0.9, 0.8, 1.6, 1.1];

let config = { size: 512 };
let cached = null;

/** Choose the texture resolution before the first character is built (`size`: 256 | 512). */
export function configureTextureSets(o = {}) {
  if (cached && o.size && o.size !== config.size) { cached.dispose(); cached = null; }
  config = { ...config, ...o };
}

/** The shared DataArrayTexture (2 layers per set, set k -> layers 2(k-1), 2(k-1)+1). */
export function getTextureSets() {
  if (cached) return cached;
  const N = config.size;
  const data = new Uint8Array(N * N * 4 * SET_COUNT * 2);
  const gens = [hammered, scorched, engraved, leather, cloth, fur, mail, quilted];
  gens.forEach((gen, k) => {
    const rng = makeRng(7331 + k * 101);
    const { A, B } = gen(N, rng);
    data.set(A, (k * 2) * N * N * 4);
    data.set(B, (k * 2 + 1) * N * N * 4);
  });
  const tex = new THREE.DataArrayTexture(data, N, N, SET_COUNT * 2);
  tex.format = THREE.RGBAFormat;
  tex.type = THREE.UnsignedByteType;
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  tex.magFilter = THREE.LinearFilter;
  tex.minFilter = THREE.LinearMipmapLinearFilter;
  tex.generateMipmaps = true;
  tex.anisotropy = 4;
  tex.colorSpace = THREE.NoColorSpace;
  tex.needsUpdate = true;
  cached = tex;
  return tex;
}

// ---- field helpers (Float32Array N*N, tileable) ------------------------------------------------------------------------

const wrap = (i, N) => ((i % N) + N) % N;

/** Tileable value noise with lattice period P (P divides N), smoothstep interpolation. */
function vnoise(N, P, rng) {
  const L = new Float32Array(P * P);
  for (let i = 0; i < L.length; i++) L[i] = rng();
  const out = new Float32Array(N * N), s = P / N;
  for (let y = 0; y < N; y++) {
    const fy = y * s, iy = Math.floor(fy), ty = fy - iy, sy = ty * ty * (3 - 2 * ty);
    const r0 = (iy % P) * P, r1 = ((iy + 1) % P) * P;
    for (let x = 0; x < N; x++) {
      const fx = x * s, ix = Math.floor(fx), tx = fx - ix, sx = tx * tx * (3 - 2 * tx);
      const c0 = ix % P, c1 = (ix + 1) % P;
      const a = L[r0 + c0] + (L[r0 + c1] - L[r0 + c0]) * sx;
      const b = L[r1 + c0] + (L[r1 + c1] - L[r1 + c0]) * sx;
      out[y * N + x] = a + (b - a) * sy;
    }
  }
  return out;
}

/** fbm of value noise, periods P, 2P, 4P ... (normalised to ~0..1). */
function fbm(N, P, oct, rng, gain = 0.5) {
  const out = new Float32Array(N * N);
  let amp = 1, sum = 0;
  for (let o = 0; o < oct && P <= N; o++, P *= 2) {
    const n = vnoise(N, P, rng);
    for (let i = 0; i < out.length; i++) out[i] += n[i] * amp;
    sum += amp; amp *= gain;
  }
  for (let i = 0; i < out.length; i++) out[i] /= sum;
  return stretch(out);
}

/** Stretch a field to 0..1 (min/max). */
function stretch(f) {
  let lo = Infinity, hi = -Infinity;
  for (let i = 0; i < f.length; i++) { if (f[i] < lo) lo = f[i]; if (f[i] > hi) hi = f[i]; }
  const k = hi > lo ? 1 / (hi - lo) : 0;
  for (let i = 0; i < f.length; i++) f[i] = (f[i] - lo) * k;
  return f;
}

/**
 * Tileable Worley noise with C x C cells (one jittered feature point per cell). Optional domain warp fields (pixels).
 * Returns { f1, f2, id } (distances in cell units).
 */
function worley(N, C, rng, warp = null, jitter = 1) {
  const px = new Float32Array(C * C), py = new Float32Array(C * C), pid = new Float32Array(C * C);
  for (let i = 0; i < C * C; i++) { px[i] = 0.5 + (rng() - 0.5) * jitter; py[i] = 0.5 + (rng() - 0.5) * jitter; pid[i] = rng(); }
  const f1 = new Float32Array(N * N), f2 = new Float32Array(N * N), id = new Float32Array(N * N);
  const s = C / N;
  for (let y = 0; y < N; y++) {
    for (let x = 0; x < N; x++) {
      const k = y * N + x;
      let fx = x * s, fy = y * s;
      if (warp) { fx += warp[0][k] * s; fy += warp[1][k] * s; }
      const ix = Math.floor(fx), iy = Math.floor(fy);
      let d1 = 9, d2 = 9, best = 0;
      for (let oy = -1; oy <= 1; oy++) {
        const cy = iy + oy, wy = ((cy % C) + C) % C;
        for (let ox = -1; ox <= 1; ox++) {
          const cx = ix + ox, w = wy * C + (((cx % C) + C) % C);
          const dx = cx + px[w] - fx, dy = cy + py[w] - fy, d = dx * dx + dy * dy;
          if (d < d1) { d2 = d1; d1 = d; best = w; } else if (d < d2) d2 = d;
        }
      }
      f1[k] = Math.sqrt(d1); f2[k] = Math.sqrt(d2); id[k] = pid[best];
    }
  }
  return { f1, f2, id };
}

/** Separable wrap-around box blur, radius r, `passes` times (~gaussian). */
function blur(f, N, r, passes = 2) {
  let a = Float32Array.from(f), b = new Float32Array(f.length);
  const w = 1 / (2 * r + 1);
  for (let p = 0; p < passes; p++) {
    for (let y = 0; y < N; y++) {
      const row = y * N;
      let acc = 0;
      for (let i = -r; i <= r; i++) acc += a[row + wrap(i, N)];
      for (let x = 0; x < N; x++) {
        b[row + x] = acc * w;
        acc += a[row + wrap(x + r + 1, N)] - a[row + wrap(x - r, N)];
      }
    }
    for (let x = 0; x < N; x++) {
      let acc = 0;
      for (let i = -r; i <= r; i++) acc += b[wrap(i, N) * N + x];
      for (let y = 0; y < N; y++) {
        a[y * N + x] = acc * w;
        acc += b[wrap(y + r + 1, N) * N + x] - b[wrap(y - r, N) * N + x];
      }
    }
  }
  return a;
}

/**
 * Draw anti-aliased line segments into a field (max blend). segs: [[x0, y0, x1, y1, halfWidth, value], ...] in pixels.
 * profile: 'round' (soft groove) | 'hard' (flat with 1 px AA). Wraps across tile borders.
 */
function lines(f, N, segs, profile = 'round') {
  for (const [x0, y0, x1, y1, hw, val] of segs) {
    const minx = Math.floor(Math.min(x0, x1) - hw - 2), maxx = Math.ceil(Math.max(x0, x1) + hw + 2);
    const miny = Math.floor(Math.min(y0, y1) - hw - 2), maxy = Math.ceil(Math.max(y0, y1) + hw + 2);
    const dx = x1 - x0, dy = y1 - y0, ll = dx * dx + dy * dy || 1e-6;
    for (let y = miny; y <= maxy; y++) {
      for (let x = minx; x <= maxx; x++) {
        let t = ((x - x0) * dx + (y - y0) * dy) / ll;
        t = t < 0 ? 0 : t > 1 ? 1 : t;
        const ex = x - (x0 + dx * t), ey = y - (y0 + dy * t), d = Math.sqrt(ex * ex + ey * ey);
        let v;
        if (profile === 'hard') v = Math.max(0, Math.min(1, hw + 0.5 - d));
        else { const q = d / (hw + 0.75); v = q >= 1 ? 0 : (1 - q * q) * (1 - q * q); }
        if (v <= 0) continue;
        const k = wrap(y, N) * N + wrap(x, N);
        const w = v * val;
        if (w > f[k]) f[k] = w;
      }
    }
  }
}

/** Polyline helper: points [[x,y]...] -> segments for lines(). */
function polySegs(pts, hw, val, taper = false) {
  const out = [];
  for (let i = 0; i < pts.length - 1; i++) {
    const k = taper ? 1 - (i / (pts.length - 1)) * 0.7 : 1;
    out.push([pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1], hw * k, val]);
  }
  return out;
}

/** Normals (RG, 0..255 encoded) + micro cavity from a height field. strength = slope gain. */
function normalsAndCavity(h, N, strength, cavR = 4, cavGain = 2.2) {
  const n = new Float32Array(N * N * 2);
  for (let y = 0; y < N; y++) {
    const ym = wrap(y - 1, N) * N, yp = wrap(y + 1, N) * N, yc = y * N;
    for (let x = 0; x < N; x++) {
      const xm = wrap(x - 1, N), xp = wrap(x + 1, N);
      // Sobel
      const gx = (h[ym + xp] + 2 * h[yc + xp] + h[yp + xp]) - (h[ym + xm] + 2 * h[yc + xm] + h[yp + xm]);
      const gy = (h[yp + xm] + 2 * h[yp + x] + h[yp + xp]) - (h[ym + xm] + 2 * h[ym + x] + h[ym + xp]);
      let nx = -gx * strength, ny = -gy * strength;
      const l = Math.sqrt(nx * nx + ny * ny + 1);
      n[(yc + x) * 2] = nx / l; n[(yc + x) * 2 + 1] = ny / l;
    }
  }
  const bl = blur(h, N, cavR, 2);
  const cav = new Float32Array(N * N);
  for (let i = 0; i < cav.length; i++) cav[i] = Math.max(0, Math.min(1, 1 + (h[i] - bl[i]) * cavGain));
  return { n, cav };
}

const sat = (x) => (x < 0 ? 0 : x > 1 ? 1 : x);
const sstep = (a, b, x) => { const t = sat((x - a) / (b - a)); return t * t * (3 - 2 * t); };

/** Pack fields into the two RGBA8 layers. */
function pack(N, albedo, rough, hB, wearA, h, strength, mask, cavOpt = {}) {
  const { n, cav } = normalsAndCavity(h, N, strength, cavOpt.r ?? 4, cavOpt.gain ?? 2.2);
  const A = new Uint8Array(N * N * 4), B = new Uint8Array(N * N * 4);
  for (let i = 0; i < N * N; i++) {
    A[i * 4] = Math.round(sat(albedo[i]) * 255);
    A[i * 4 + 1] = Math.round(sat(rough[i]) * 255);
    A[i * 4 + 2] = Math.round(sat(hB[i]) * 255);
    A[i * 4 + 3] = Math.round(sat(wearA[i]) * 255);
    B[i * 4] = Math.round((n[i * 2] * 0.5 + 0.5) * 255);
    B[i * 4 + 1] = Math.round((n[i * 2 + 1] * 0.5 + 0.5) * 255);
    B[i * 4 + 2] = Math.round(sat(cav[i]) * 255);
    B[i * 4 + 3] = Math.round(sat(mask ? mask[i] : 0) * 255);
  }
  return { A, B };
}

/** Random scratch segments: a few dominant directions, many short strokes, some long. */
function scratchSegs(N, rng, count, scale = 1) {
  const dirs = [rng() * Math.PI, rng() * Math.PI, rng() * Math.PI];
  const segs = [];
  for (let k = 0; k < count; k++) {
    const x0 = rng() * N, y0 = rng() * N;
    const a = rng() < 0.75 ? dirs[(rng() * 3) | 0] + (rng() - 0.5) * 0.35 : rng() * Math.PI;
    const len = (4 + rng() * rng() * 60) * scale * (N / 512);
    // slightly curved: 3 sub-segments
    let x = x0, y = y0, ang = a;
    const bend = (rng() - 0.5) * 0.2;
    const hw = (0.35 + rng() * 0.5) * (N / 512);
    const val = 0.3 + rng() * 0.7;
    for (let s = 0; s < 3; s++) {
      const nx = x + Math.cos(ang) * len / 3, ny = y + Math.sin(ang) * len / 3;
      segs.push([x, y, nx, ny, hw, val]);
      x = nx; y = ny; ang += bend;
    }
  }
  return segs;
}

// ---- sets --------------------------------------------------------------------------------------------------------------

/** 1 hammered plate steel: overlapping hammer dents, fine grain, scratches. */
function hammered(N, rng) {
  const s = N / 512;
  const w1 = worley(N, 13, rng), w2 = worley(N, 24, rng);
  const grain = fbm(N, 64, 3, rng), mott = fbm(N, 4, 4, rng, 0.55), wear = fbm(N, 8, 5, rng, 0.6);
  const scr = new Float32Array(N * N);
  lines(scr, N, scratchSegs(N, rng, 320));
  const h = new Float32Array(N * N), alb = new Float32Array(N * N), rough = new Float32Array(N * N), hb = new Float32Array(N * N);
  for (let i = 0; i < N * N; i++) {
    const d1 = Math.min(1, w1.f1[i] * 1.25), d2 = Math.min(1, w2.f1[i] * 1.25);
    const dent = d1 * d1 * 0.42 + d2 * d2 * 0.2;            // bowls: low centre, ridges between dents
    h[i] = dent * 0.9 + grain[i] * 0.08 - scr[i] * 0.12;
    hb[i] = dent * 0.8;
    alb[i] = 0.5 + (mott[i] - 0.5) * 0.5 + (w1.id[i] - 0.5) * 0.08 + scr[i] * 0.18;
    rough[i] = 0.5 + (mott[i] - 0.5) * 0.35 + (grain[i] - 0.5) * 0.25 + scr[i] * 0.22 - dent * 0.05;
  }
  return pack(N, alb, rough, hb, wear, h, 1.9 * s, null);
}

/** 2 scorched / fire-blackened plate: soot flakes, pitting, warped crack network (mask), heat halo (proximity). */
function scorched(N, rng) {
  const s = N / 512;
  const wx = fbm(N, 8, 4, rng), wy = fbm(N, 8, 4, rng);
  const warp = [new Float32Array(N * N), new Float32Array(N * N)];
  for (let i = 0; i < N * N; i++) { warp[0][i] = (wx[i] - 0.5) * 44 * s; warp[1][i] = (wy[i] - 0.5) * 44 * s; }
  const big = worley(N, 5, rng, warp, 0.85);
  const wx2 = fbm(N, 16, 3, rng), wy2 = fbm(N, 16, 3, rng);
  for (let i = 0; i < N * N; i++) { warp[0][i] = (wx2[i] - 0.5) * 22 * s; warp[1][i] = (wy2[i] - 0.5) * 22 * s; }
  const small = worley(N, 12, rng, warp, 0.9);
  const keep = fbm(N, 4, 3, rng), keep2 = fbm(N, 8, 3, rng), widthN = fbm(N, 16, 2, rng);
  const dent = worley(N, 7, rng), pits = worley(N, 30, rng), pitKeep = fbm(N, 8, 3, rng);
  const soot = fbm(N, 4, 5, rng, 0.62), grain = fbm(N, 64, 3, rng), wear = fbm(N, 8, 5, rng, 0.6);
  const scr = new Float32Array(N * N);
  lines(scr, N, scratchSegs(N, rng, 160));
  const core = new Float32Array(N * N);
  for (let i = 0; i < N * N; i++) {
    // main fissures: F2-F1 edge distance, width modulated, network broken up by noise so it reads as cracks, not cells
    const e1 = (big.f2[i] - big.f1[i]) / 5 * 512 * s;                 // ~pixels
    const w1 = (0.7 + widthN[i] * 2.2) * s;
    const on1 = sstep(0.64, 0.73, keep[i]);
    const c1 = (1 - sstep(w1 * 0.4, w1 + 1.2 * s, e1)) * on1;
    const e2 = (small.f2[i] - small.f1[i]) / 12 * 512 * s;
    const on2 = sstep(0.64, 0.74, keep2[i]) * sstep(0.56, 0.68, keep[i]);
    const c2 = (1 - sstep(0.15 * s, 0.9 * s, e2)) * on2 * 0.85;
    core[i] = Math.max(c1, c2);
  }
  const halo = stretch(blur(core, N, Math.round(7 * s), 3));
  const halo2 = blur(core, N, Math.round(2 * s), 2);
  const h = new Float32Array(N * N), alb = new Float32Array(N * N), rough = new Float32Array(N * N), hb = new Float32Array(N * N);
  for (let i = 0; i < N * N; i++) {
    const d = Math.min(1, dent.f1[i] * 1.2);
    const pit = (1 - sstep(0.0, 0.1, pits.f1[i])) * sstep(0.62, 0.75, pitKeep[i]);
    const flake = sstep(0.5, 0.62, soot[i]);
    h[i] = d * d * 0.2 + grain[i] * 0.08 - pit * 0.18 - Math.min(1, halo2[i] * 2.5) * 0.42 - scr[i] * 0.06 + flake * 0.05;
    hb[i] = Math.pow(halo[i], 0.8);
    alb[i] = 0.5 + (soot[i] - 0.5) * 0.7 - flake * 0.12 - pit * 0.15 + scr[i] * 0.12;
    rough[i] = 0.5 + flake * 0.25 + (grain[i] - 0.5) * 0.2 + pit * 0.2 - scr[i] * 0.05;
  }
  return pack(N, alb, rough, hb, wear, h, 2.6 * s, core);
}

/** 3 engraved ornament: interlaced scrolls and angular glyph bands cut into the metal (mask = groove cores). */
function engraved(N, rng) {
  const s = N / 512;
  const g = new Float32Array(N * N);
  const segs = [];
  // spiral scrolls with tendrils
  for (let k = 0; k < 9; k++) {
    const cx = rng() * N, cy = rng() * N, R = (34 + rng() * 34) * s, dir = rng() < 0.5 ? 1 : -1, a0 = rng() * Math.PI * 2;
    const pts = [];
    for (let t = 0; t <= 1; t += 0.02) {
      const a = a0 + dir * t * Math.PI * 2.6, r = R * (1 - t * 0.82);
      pts.push([cx + Math.cos(a) * r, cy + Math.sin(a) * r]);
    }
    segs.push(...polySegs(pts, 1.6 * s, 1, true));
    // outgoing S-curve stem
    const stem = [];
    const ax = cx + Math.cos(a0) * R, ay = cy + Math.sin(a0) * R;
    const ang = a0 + dir * Math.PI / 2;
    for (let t = 0; t <= 1; t += 0.05) {
      const bend = Math.sin(t * Math.PI * 1.5) * 26 * s;
      stem.push([ax + Math.cos(ang) * t * 90 * s + Math.cos(ang + Math.PI / 2) * bend, ay + Math.sin(ang) * t * 90 * s + Math.sin(ang + Math.PI / 2) * bend]);
    }
    segs.push(...polySegs(stem, 1.4 * s, 0.9));
    // leaves: short tapered strokes off the spiral
    for (let l = 0; l < 5; l++) {
      const t = 0.1 + l * 0.12, a = a0 + dir * t * Math.PI * 2.6, r = R * (1 - t * 0.82);
      const px = cx + Math.cos(a) * r, py = cy + Math.sin(a) * r, la = a + (rng() - 0.5) * 0.6;
      const L = (10 + rng() * 12) * s;
      segs.push([px, py, px + Math.cos(la) * L, py + Math.sin(la) * L, 1.1 * s, 0.85]);
    }
  }
  lines(g, N, segs);
  // angular glyph band (horizontal), repeated twice per tile
  const gl = new Float32Array(N * N), gsegs = [];
  for (const by of [N * 0.25, N * 0.75]) {
    gsegs.push([0, by - 18 * s, N, by - 18 * s, 1.0 * s, 1], [0, by + 18 * s, N, by + 18 * s, 1.0 * s, 1]);
    for (let x = 6 * s; x < N; x += 22 * s) {
      const m = (rng() * 6) | 0, h = 12 * s;
      const L = [[x, by - h, x, by + h]];
      if (m === 0 || m === 3) L.push([x, by - h, x + 9 * s, by - h * 0.3]);
      if (m === 1 || m === 4) L.push([x, by, x + 9 * s, by + h]);
      if (m === 2) L.push([x - 5 * s, by - h * 0.4, x + 7 * s, by + h * 0.4]);
      if (m === 5) L.push([x, by + h * 0.2, x + 8 * s, by - h * 0.6]);
      for (const [a, b, c, d] of L) gsegs.push([a, b, c, d, 1.0 * s, 1]);
    }
  }
  lines(gl, N, gsegs, 'hard');
  const grain = fbm(N, 64, 3, rng), mott = fbm(N, 4, 4, rng), wear = fbm(N, 8, 5, rng, 0.6);
  const core = new Float32Array(N * N);
  for (let i = 0; i < N * N; i++) core[i] = Math.max(g[i], gl[i] * 0.95);
  const halo = stretch(blur(core, N, Math.round(3 * s), 2));
  const h = new Float32Array(N * N), alb = new Float32Array(N * N), rough = new Float32Array(N * N);
  for (let i = 0; i < N * N; i++) {
    h[i] = -core[i] * 0.7 + grain[i] * 0.05;
    alb[i] = 0.5 + (mott[i] - 0.5) * 0.35 - core[i] * 0.25;
    rough[i] = 0.5 + (mott[i] - 0.5) * 0.3 + core[i] * 0.25;
  }
  const cm = core.map((v) => sstep(0.25, 0.75, v));
  return pack(N, alb, rough, halo, wear, h, 3.0 * s, cm, { r: 3, gain: 3 });
}

/** 4 leather: pebbled grain, wrinkles, pores, scuffs. */
function leather(N, rng) {
  const s = N / 512;
  const cells = worley(N, 44, rng), cells2 = worley(N, 90, rng);
  const wr = vnoiseAniso(N, 6, 48, rng), wr2 = vnoiseAniso(N, 12, 96, rng);
  const mott = fbm(N, 4, 4, rng), wear = fbm(N, 8, 5, rng, 0.6), fine = fbm(N, 128, 2, rng);
  const h = new Float32Array(N * N), alb = new Float32Array(N * N), rough = new Float32Array(N * N);
  for (let i = 0; i < N * N; i++) {
    const p = 1 - Math.min(1, cells.f1[i] * 1.4), p2 = 1 - Math.min(1, cells2.f1[i] * 1.5);
    const crease = Math.pow(1 - Math.abs(wr[i] - 0.5) * 2, 10) * sstep(0.3, 0.7, mott[i]) + Math.pow(1 - Math.abs(wr2[i] - 0.5) * 2, 14) * 0.6;
    h[i] = p * 0.45 + p2 * 0.2 - crease * 0.5 + fine[i] * 0.05;
    alb[i] = 0.5 + (mott[i] - 0.5) * 0.6 - crease * 0.2 + (cells.id[i] - 0.5) * 0.06;
    rough[i] = 0.5 + (mott[i] - 0.5) * 0.4 - p * 0.12 + crease * 0.15;
  }
  return pack(N, alb, rough, mott, wear, h, 1.6 * s, null);
}

/** Anisotropic value noise (different lattice periods in x and y). */
function vnoiseAniso(N, Px, Py, rng) {
  const L = new Float32Array(Px * Py);
  for (let i = 0; i < L.length; i++) L[i] = rng();
  const out = new Float32Array(N * N);
  for (let y = 0; y < N; y++) {
    const fy = (y * Py) / N, iy = Math.floor(fy), ty = fy - iy, sy = ty * ty * (3 - 2 * ty);
    for (let x = 0; x < N; x++) {
      const fx = (x * Px) / N, ix = Math.floor(fx), tx = fx - ix, sx = tx * tx * (3 - 2 * tx);
      const g = (a, b) => L[(b % Py) * Px + (a % Px)];
      const a = g(ix, iy) + (g(ix + 1, iy) - g(ix, iy)) * sx;
      const b = g(ix, iy + 1) + (g(ix + 1, iy + 1) - g(ix, iy + 1)) * sx;
      out[y * N + x] = a + (b - a) * sy;
    }
  }
  return out;
}

/** 5 woven cloth: 2/2 twill of slubbed threads with fibre streaks (mask = gaps between threads). */
function cloth(N, rng) {
  const s = N / 512;
  const T = 32;                                   // threads per tile
  const ts = N / T;
  const warpV = new Float32Array(T), weftV = new Float32Array(T);
  for (let i = 0; i < T; i++) { warpV[i] = rng(); weftV[i] = rng(); }
  const fibX = vnoiseAniso(N, 256, 16, rng), fibY = vnoiseAniso(N, 16, 256, rng);
  const mott = fbm(N, 4, 4, rng), wear = fbm(N, 8, 5, rng, 0.6);
  const h = new Float32Array(N * N), alb = new Float32Array(N * N), rough = new Float32Array(N * N), gap = new Float32Array(N * N);
  for (let y = 0; y < N; y++) {
    const j = Math.floor(y / ts), fy = (y % ts) / ts;
    for (let x = 0; x < N; x++) {
      const i = Math.floor(x / ts), fx = (x % ts) / ts, k = y * N + x;
      const warpTop = ((i + j) & 3) < 2;
      // thread cross-section bumps
      const bx = Math.sin(fx * Math.PI), by = Math.sin(fy * Math.PI);
      const warpH = Math.pow(bx, 0.6) * (0.75 + 0.25 * Math.sin((fy + (warpTop ? 0 : 1)) * Math.PI * 0.5));
      const weftH = Math.pow(by, 0.6) * (0.75 + 0.25 * Math.sin((fx + (warpTop ? 1 : 0)) * Math.PI * 0.5));
      const top = warpTop ? warpH : weftH;
      const under = warpTop ? weftH * 0.55 : warpH * 0.55;
      const v = Math.max(top, under);
      const fib = warpTop ? fibY[k] : fibX[k];
      h[k] = v * 0.85 + (fib - 0.5) * 0.18;
      gap[k] = 1 - sstep(0.05, 0.35, v);
      const tv = warpTop ? warpV[i] : weftV[j];
      alb[k] = 0.5 + (tv - 0.5) * 0.22 + (fib - 0.5) * 0.25 + (mott[k] - 0.5) * 0.35 - gap[k] * 0.25;
      rough[k] = 0.55 + (fib - 0.5) * 0.2 + gap[k] * 0.2;
    }
  }
  return pack(N, alb, rough, mott, wear, h, 1.8 * s, gap, { r: 2, gain: 2 });
}

/** 6 fur: clumped vertical strands (mask = strand coverage across u), dark roots handled by the shader. */
function fur(N, rng) {
  const s = N / 512;
  const cov = new Float32Array(N * N), h = new Float32Array(N * N), alb = new Float32Array(N * N);
  const segs = [];
  const clumps = 26;
  for (let c = 0; c < clumps; c++) {
    const cx = rng() * N, lean = (rng() - 0.5) * 30 * s, bright = rng();
    const strands = 22 + ((rng() * 18) | 0);
    for (let k = 0; k < strands; k++) {
      const x0 = cx + (rng() - 0.5) * 26 * s, y0 = rng() * N;
      const len = (90 + rng() * 260) * s;
      const curl = (rng() - 0.5) * 14 * s;
      const pts = [];
      for (let t = 0; t <= 1.0001; t += 0.125) pts.push([x0 + lean * t + Math.sin(t * Math.PI) * curl, y0 + t * len]);
      segs.push(...polySegs(pts, (0.8 + rng() * 1.3) * s, 0.55 + bright * 0.45 * rng(), true));
    }
  }
  lines(cov, N, segs);
  const fine = vnoiseAniso(N, 192, 6, rng), mott = fbm(N, 4, 3, rng), wear = fbm(N, 8, 4, rng);
  const rough = new Float32Array(N * N);
  for (let i = 0; i < N * N; i++) {
    const c = Math.max(cov[i], sstep(0.55, 0.9, fine[i]) * 0.5);
    cov[i] = c;
    h[i] = c * 0.8 + fine[i] * 0.15;
    alb[i] = 0.5 + (c - 0.5) * 0.5 + (mott[i] - 0.5) * 0.3;
    rough[i] = 0.55 + (1 - c) * 0.25;
  }
  return pack(N, alb, rough, mott, wear, h, 1.4 * s, cov, { r: 2, gain: 1.5 });
}

/** 7 riveted mail (4-in-1): overlapping tilted rings; mask = ring coverage. */
function mail(N, rng) {
  const s = N / 512;
  const R = 8;                                    // rings across the tile
  const sp = N / R;
  const h = new Float32Array(N * N).fill(-1), cov = new Float32Array(N * N), id = new Float32Array(N * N);
  const ro = sp * 0.62, wid = sp * 0.15;
  for (let row = 0; row < R * 2; row++) {
    const cy0 = (row + 0.5) * sp * 0.5, off = (row & 1) * sp * 0.5, tilt = row & 1 ? 1 : -1, ringId = rng;
    for (let col = 0; col < R; col++) {
      const cx0 = (col + 0.5) * sp + off, rid = ringId();
      const base = (row % 2) * 0.12;
      for (let y = Math.floor(cy0 - ro - wid - 2); y <= Math.ceil(cy0 + ro + wid + 2); y++) {
        for (let x = Math.floor(cx0 - ro - wid - 2); x <= Math.ceil(cx0 + ro + wid + 2); x++) {
          const dx = x - cx0, dy = (y - cy0) * 1.25, d = Math.sqrt(dx * dx + dy * dy);
          const q = Math.abs(d - ro * 0.85) / wid;
          if (q >= 1) continue;
          const prof = Math.sqrt(1 - q * q);
          const z = base + prof * 0.6 + (dx / ro) * 0.22 * tilt + (dy / ro) * 0.1;
          const k = wrap(y, N) * N + wrap(x, N);
          if (z > h[k]) { h[k] = z; cov[k] = sstep(0, 0.35, prof); id[k] = rid; }
        }
      }
    }
  }
  const mott = fbm(N, 4, 3, rng), wear = fbm(N, 8, 5, rng, 0.6);
  const alb = new Float32Array(N * N), rough = new Float32Array(N * N);
  for (let i = 0; i < N * N; i++) {
    if (h[i] < -0.5) h[i] = -0.35;
    alb[i] = 0.5 + (id[i] - 0.5) * 0.18 + (mott[i] - 0.5) * 0.3 - (1 - cov[i]) * 0.3;
    rough[i] = 0.5 + (mott[i] - 0.5) * 0.3 + (1 - cov[i]) * 0.3;
  }
  return pack(N, alb, rough, mott, wear, h, 2.2 * s, cov, { r: 3, gain: 2.5 });
}

/** 8 quilted gambeson: diamond quilting with puffed cells, stitch dashes and a fine weave. */
function quilted(N, rng) {
  const s = N / 512;
  const P = N / 4;                                 // diamond spacing (4 per tile along each diagonal)
  const weave = vnoiseAniso(N, 128, 128, rng), mott = fbm(N, 4, 4, rng), wear = fbm(N, 8, 5, rng, 0.6);
  const h = new Float32Array(N * N), alb = new Float32Array(N * N), rough = new Float32Array(N * N), stitch = new Float32Array(N * N);
  for (let y = 0; y < N; y++) {
    for (let x = 0; x < N; x++) {
      const k = y * N + x;
      const a = (x + y) / P, b = (x - y + N) / P;
      const da = Math.abs(a - Math.round(a)), db = Math.abs(b - Math.round(b));
      const d = Math.min(da, db) * P;               // px to the nearest stitch line
      const puff = Math.sqrt(sat(d / (P * 0.32)));
      const along = da < db ? (x - y) : (x + y);
      const dash = Math.sin(along * 0.55 / s) > -0.2 ? 1 : 0;
      stitch[k] = (1 - sstep(0.6 * s, 1.8 * s, d)) * dash;
      h[k] = puff * 0.85 - stitch[k] * 0.1 + (weave[k] - 0.5) * 0.06;
      alb[k] = 0.5 + (mott[k] - 0.5) * 0.4 + (weave[k] - 0.5) * 0.12 - (1 - puff) * 0.15 + stitch[k] * 0.12;
      rough[k] = 0.55 + (weave[k] - 0.5) * 0.15 + (1 - puff) * 0.1;
    }
  }
  return pack(N, alb, rough, mott, wear, h, 1.5 * s, stitch, { r: 6, gain: 1.8 });
}
