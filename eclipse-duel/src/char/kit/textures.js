// Procedural PBR texture sets for the character material (src/char/materials.js). Every set is a pair of tileable
// RGBA8 layers in one DataArrayTexture (sampler2DArray: no atlas bleeding, repeat wrap and mipmaps per layer):
//
//   layer A  R albedo variation (0.5 = neutral)   G roughness variation (0.5 = neutral)
//            B height / proximity (scorched: heat halo around cracks; engraved / lacquer: groove halo; hemp: weave
//              height (gauze coverage); lamellar: plate edge proximity)   A wear / chip noise
//   layer B  RG tangent-space normal (from the height field, Sobel)   B micro cavity (1 = open, 0 = deep crevice)
//            A set mask (scorched: crack cores; engraved: groove cores; cloth / hemp: weave gaps; fur: strand coverage;
//              mail: ring coverage; quilted: stitch lines; damask: woven figure; lacquer: craquelure; lamellar: lacing
//              cords; bamboo: pinholes between the strips)
//   brocade is the exception: its two layers hold eight embroidery motifs, one height field per channel
//   (A: cloud, wave, flame, fret   B: sun, moon, thunder, lattice); the shader embosses the chosen one.
//
// Sets are generated lazily: the first look that names a set (surfDetail() -> requireTextureSet()) builds its layers
// (deterministic: seeded RNG, pure JS, no canvas readback) and uploads just those two layers. A duel therefore only pays
// for the materials its two heroes wear. Size 256 (default): 15-45 ms per set on desktop, ~10.5 MB of GPU memory with
// mips for all 15 generated sets. configureTextureSets({ size: 512 }) before the first character for crisper cinematic
// close-ups (4x the time and memory). Shader-mode sets (gauze, hair, blade, bronze, jade) reuse the layers of another
// set and cost nothing.

import * as THREE from 'three';
import { makeRng } from '../../core/math.js';

/**
 * Texture set ids (also the `set` of a surface look). 0 is the legacy detail texture of the original kit material.
 * UV sets (the mesh carries `uvw`): fur, brocade, lamellar, bamboo, gauze, hair, blade (see the kit README).
 */
export const SET = {
  legacy: 0, hammered: 1, scorched: 2, engraved: 3, leather: 4, cloth: 5, fur: 6, mail: 7, quilted: 8,
  silk: 9, hemp: 10, damask: 11, brocade: 12, lacquer: 13, lamellar: 14, bamboo: 15,
  gauze: 16, hair: 17, blade: 18, bronze: 19, jade: 20,
};
/** Highest set id (shader arrays hold SET_COUNT + 1 entries). */
export const SET_COUNT = 20;
/** Layer pairs in the array texture (generated sets). */
export const LAYER_SETS = 15;
/** First layer of each set (index = set id): shader-mode sets point at the layers they reuse. */
export const SET_LAYER = [0, 0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, /* gauze */ 18, /* hair */ 10, /* blade */ 0, /* bronze */ 0, /* jade */ 0];
/** Default tiles per metre of each set (index = set id; UV sets: scale of the mesh's own uv, 1 unless noted). */
export const SET_SCALE = [0, 4.2, 3.4, 7.5, 9, 22, 6, 7.5, 6.5, 55, 26, 6.5, 1, 5, 1, 1, 1, 1, 5.5, 4.6, 3.2];
/** Normal strength of each set (index = set id). */
export const SET_BUMP = [0, 0.55, 0.7, 1.2, 1.0, 0.6, 0.8, 1.6, 1.1, 0.55, 1.15, 0.55, 1.5, 0.45, 1.5, 1.25, 0.9, 0.9, 0.3, 0.4, 0.2];
/** Set id whose layers a set samples (itself for generated sets). */
const SOURCE = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 10, 6, 1, 1, 1];

let config = { size: 256 };
let cached = null;      // the DataArrayTexture
let data = null;        // its pixel store (all layers, zero until a set is generated)
let done = null;        // Uint8Array: generated flags per source set id
let uploaded = false;   // the texture has been uploaded once (later sets upload their two layers only)
let bank = null;        // shared noise fields
const timings = {};

/** Choose the texture resolution before the first character is built (`size`: 256 | 512). */
export function configureTextureSets(o = {}) {
  if (o.size && o.size !== config.size) {
    if (cached) cached.dispose();
    cached = null; data = null; done = null; bank = null; uploaded = false;
  }
  config = { ...config, ...o };
}

function store() {
  if (data) return;
  const N = config.size;
  data = new Uint8Array(N * N * 4 * LAYER_SETS * 2);
  done = new Uint8Array(SET_COUNT + 1);
}

/**
 * Make sure the layers of a set exist (generates them on first use; a no-op afterwards). Called by surfDetail(), so
 * building a design is enough; call it yourself (or prewarmTextureSets) for sets only reached through shader modes.
 * @param {number|string} set  SET id or name
 * @returns {number} the set id
 */
export function requireTextureSet(set) {
  const id = typeof set === 'string' ? SET[set] : set;
  if (!id || id > SET_COUNT) return id || 0;
  const src = SOURCE[id];
  store();
  if (done[src]) return id;
  done[src] = 1;
  const N = config.size, t0 = now();
  if (!bank) bank = makeBank(N);
  const rng = makeRng(7331 + (src - 1) * 101);
  const { A, B } = GENERATORS[src - 1](N, rng, bank);
  const L = SET_LAYER[src];
  data.set(A, L * N * N * 4);
  data.set(B, (L + 1) * N * N * 4);
  timings[NAMES[src]] = +(now() - t0).toFixed(1);
  if (cached) {
    if (uploaded) { cached.addLayerUpdate(L); cached.addLayerUpdate(L + 1); }
    cached.needsUpdate = true;
  }
  return id;
}

/** Generate sets ahead of time (names or ids; default: all of them). Returns the per-set generation times in ms. */
export function prewarmTextureSets(sets) {
  for (const s of sets || Object.keys(SET).slice(1)) requireTextureSet(s);
  return { ...timings };
}

/** Milliseconds spent generating each set so far: { name: ms }. */
export function textureSetTimings() { return { ...timings }; }

/** The shared DataArrayTexture (2 layers per generated set; layers stay empty until their set is required). */
export function getTextureSets() {
  if (cached) return cached;
  store();
  requireTextureSet(SET.hammered);      // base metal grain: also the noise source of cloth tears and the blade / bronze / jade modes
  const N = config.size;
  const tex = new THREE.DataArrayTexture(data, N, N, LAYER_SETS * 2);
  tex.format = THREE.RGBAFormat;
  tex.type = THREE.UnsignedByteType;
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  tex.magFilter = THREE.LinearFilter;
  tex.minFilter = THREE.LinearMipmapLinearFilter;
  tex.generateMipmaps = true;
  tex.anisotropy = 4;
  tex.colorSpace = THREE.NoColorSpace;
  tex.onUpdate = () => { uploaded = true; };
  tex.addEventListener('dispose', () => { uploaded = false; });
  tex.needsUpdate = true;
  cached = tex;
  return tex;
}

const now = () => (typeof performance !== 'undefined' ? performance.now() : Date.now());

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

/**
 * 1 hammered plate steel: small planishing-hammer facets that come and go in patches (most of a plate reads smooth and
 * forged, not crumpled), directional polish streaks and smudges in the roughness, fine grain, scratches.
 */
function hammered(N, rng, B) {
  const s = N / 512;
  const w1 = worley(N, 20, rng), w2 = worley(N, 36, rng);
  const grain = B.fbm(rng, 64, 3), mott = B.fbm(rng, 4, 4, 0.55), wear = B.fbm(rng, 8, 5, 0.6);
  const patch = B.fbm(rng, 4, 3, 0.5), smudge = B.fbm(rng, 8, 3, 0.55);
  const polish = vnoiseAniso(N, 4, 128, rng), polish2 = vnoiseAniso(N, 8, 256, rng);
  const scr = new Float32Array(N * N);
  lines(scr, N, scratchSegs(N, rng, 320));
  const h = new Float32Array(N * N), alb = new Float32Array(N * N), rough = new Float32Array(N * N), hb = new Float32Array(N * N);
  for (let i = 0; i < N * N; i++) {
    const d1 = Math.min(1, w1.f1[i] * 1.2), d2 = Math.min(1, w2.f1[i] * 1.2);
    const vis = 0.25 + 0.75 * sstep(0.38, 0.72, patch[i]);   // hammered patches vs planished areas
    const dent = (d1 * d1 * 0.15 + d2 * d2 * 0.07) * vis;   // shallow facets: low centre, faint ridges between dents
    const streak = (polish[i] - 0.5) * 0.7 + (polish2[i] - 0.5) * 0.3;
    h[i] = dent + grain[i] * 0.05 - scr[i] * 0.1;
    hb[i] = dent * 2.2;
    alb[i] = 0.5 + (mott[i] - 0.5) * 0.45 + (w1.id[i] - 0.5) * 0.05 * vis + scr[i] * 0.16 - sstep(0.55, 0.8, smudge[i]) * 0.08;
    rough[i] = 0.5 + (mott[i] - 0.5) * 0.25 + streak * 0.32 + (grain[i] - 0.5) * 0.15 + scr[i] * 0.22 + sstep(0.5, 0.8, smudge[i]) * 0.18;
  }
  return pack(N, alb, rough, hb, wear, h, 1.6 * s, null);
}

/** 2 scorched / fire-blackened plate: soot flakes, pitting, warped crack network (mask), heat halo (proximity). */
function scorched(N, rng, B) {
  const s = N / 512;
  const wx = B.fbm(rng, 8, 4), wy = B.fbm(rng, 8, 4);
  const warp = [new Float32Array(N * N), new Float32Array(N * N)];
  for (let i = 0; i < N * N; i++) { warp[0][i] = (wx[i] - 0.5) * 44 * s; warp[1][i] = (wy[i] - 0.5) * 44 * s; }
  const big = worley(N, 5, rng, warp, 0.85);
  const wx2 = B.fbm(rng, 16, 3), wy2 = B.fbm(rng, 16, 3);
  for (let i = 0; i < N * N; i++) { warp[0][i] = (wx2[i] - 0.5) * 22 * s; warp[1][i] = (wy2[i] - 0.5) * 22 * s; }
  const small = worley(N, 12, rng, warp, 0.9);
  const keep = B.fbm(rng, 4, 3), keep2 = B.fbm(rng, 8, 3), widthN = B.fbm(rng, 16, 2);
  const dent = worley(N, 7, rng), pits = worley(N, 30, rng), pitKeep = B.fbm(rng, 8, 3);
  const soot = B.fbm(rng, 4, 5, 0.62), grain = B.fbm(rng, 64, 3), wear = B.fbm(rng, 8, 5, 0.6);
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
    h[i] = d * d * 0.09 + grain[i] * 0.07 - pit * 0.18 - Math.min(1, halo2[i] * 2.5) * 0.42 - scr[i] * 0.06 + flake * 0.05;
    hb[i] = Math.pow(halo[i], 0.8);
    alb[i] = 0.5 + (soot[i] - 0.5) * 0.7 - flake * 0.12 - pit * 0.15 + scr[i] * 0.12;
    rough[i] = 0.5 + flake * 0.25 + (grain[i] - 0.5) * 0.2 + pit * 0.2 - scr[i] * 0.05;
  }
  return pack(N, alb, rough, hb, wear, h, 2.6 * s, core);
}

/** 3 engraved ornament: interlaced scrolls and angular glyph bands cut into the metal (mask = groove cores). */
function engraved(N, rng, B) {
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
  const grain = B.fbm(rng, 64, 3), mott = B.fbm(rng, 4, 4), wear = B.fbm(rng, 8, 5, 0.6);
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
function leather(N, rng, B) {
  const s = N / 512;
  const cells = worley(N, 44, rng), cells2 = worley(N, 90, rng);
  const wr = vnoiseAniso(N, 6, 48, rng), wr2 = vnoiseAniso(N, 12, 96, rng);
  const mott = B.fbm(rng, 4, 4), wear = B.fbm(rng, 8, 5, 0.6), fine = B.fbm(rng, 128, 2);
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
function cloth(N, rng, B) {
  const s = N / 512;
  const T = 32;                                   // threads per tile
  const ts = N / T;
  const warpV = new Float32Array(T), weftV = new Float32Array(T);
  for (let i = 0; i < T; i++) { warpV[i] = rng(); weftV[i] = rng(); }
  const fibX = vnoiseAniso(N, 256, 16, rng), fibY = vnoiseAniso(N, 16, 256, rng);
  const mott = B.fbm(rng, 4, 4), wear = B.fbm(rng, 8, 5, 0.6);
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
      alb[k] = 0.5 + (tv - 0.5) * 0.16 + (fib - 0.5) * 0.2 + (mott[k] - 0.5) * 0.45 - gap[k] * 0.12;
      rough[k] = 0.55 + (fib - 0.5) * 0.2 + gap[k] * 0.2;
    }
  }
  return pack(N, alb, rough, mott, wear, h, 1.8 * s, gap, { r: 2, gain: 2 });
}

/** 6 fur: clumped vertical strands (mask = strand coverage across u), dark roots handled by the shader. */
function fur(N, rng, B) {
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
  const fine = vnoiseAniso(N, 192, 6, rng), mott = B.fbm(rng, 4, 3), wear = B.fbm(rng, 8, 4);
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
function mail(N, rng, B) {
  const s = N / 512;
  const R = 8;                                    // rings across the tile
  const sp = N / R;
  const h = new Float32Array(N * N).fill(-1), cov = new Float32Array(N * N), id = new Float32Array(N * N);
  const ro = sp * 0.62, wid = sp * 0.15;
  for (let row = 0; row < R * 2; row++) {
    const cy0 = (row + 0.5) * sp * 0.5, off = (row & 1) * sp * 0.5, tilt = row & 1 ? 1 : -1;
    for (let col = 0; col < R; col++) {
      const cx0 = (col + 0.5) * sp + off, rid = rng();
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
  const mott = B.fbm(rng, 4, 3), wear = B.fbm(rng, 8, 5, 0.6);
  const alb = new Float32Array(N * N), rough = new Float32Array(N * N);
  for (let i = 0; i < N * N; i++) {
    if (h[i] < -0.5) h[i] = -0.35;
    alb[i] = 0.5 + (id[i] - 0.5) * 0.18 + (mott[i] - 0.5) * 0.3 - (1 - cov[i]) * 0.3;
    rough[i] = 0.5 + (mott[i] - 0.5) * 0.3 + (1 - cov[i]) * 0.3;
  }
  return pack(N, alb, rough, mott, wear, h, 2.2 * s, cov, { r: 3, gain: 2.5 });
}

/** 8 quilted gambeson: diamond quilting with puffed cells, stitch dashes and a fine weave. */
function quilted(N, rng, B) {
  const s = N / 512;
  const P = N / 4;                                 // diamond spacing (4 per tile along each diagonal)
  const weave = vnoiseAniso(N, 128, 128, rng), mott = B.fbm(rng, 4, 4), wear = B.fbm(rng, 8, 5, 0.6);
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

// ---- shared noise bank ---------------------------------------------------------------------------------------------------

function hashStr(s) { let h = 2166136261; for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); } return h >>> 0; }

/** Circularly shifted copy of a tileable field. */
function shifted(f, N, dx, dy) {
  const out = new Float32Array(N * N);
  for (let y = 0; y < N; y++) {
    const r = ((y + dy) % N) * N, o = y * N;
    out.set(f.subarray(r + dx, r + N), o);
    if (dx) out.set(f.subarray(r, r + dx), o + N - dx);
  }
  return out;
}

/**
 * Noise fields shared by every set: one tileable fbm per (period, octaves, gain), handed out as circularly shifted
 * copies (the shift comes from the set's own RNG, so a set looks the same whatever was generated before it).
 */
function makeBank(N) {
  const cache = {};
  return {
    fbm(rng, P, oct, gain = 0.5) {
      const key = `${P}:${oct}:${gain}`;
      const base = cache[key] || (cache[key] = fbm(N, P, oct, makeRng(hashStr(key)), gain));
      return shifted(base, N, Math.floor(rng() * N), Math.floor(rng() * N));
    },
  };
}

// ---- murim sets ----------------------------------------------------------------------------------------------------------

/**
 * 9 silk: five-harness satin. Long warp floats run along v (vertical on a hanging robe), bound once every five picks
 * in a staggered order, so the face is nearly all smooth float: a fine rib only a close-up resolves, slubs along the
 * threads, binding points as the faintest diagonal grain.
 */
function silk(N, rng, B) {
  const s = N / 512;
  const T = 60, ts = N / T;                        // threads per tile (a multiple of 5)
  const slub = vnoiseAniso(N, T, 12, rng), fib = vnoiseAniso(N, T * 2, 6, rng);
  const mott = B.fbm(rng, 4, 4), wear = B.fbm(rng, 8, 5, 0.6);
  const tv = new Float32Array(T);
  for (let i = 0; i < T; i++) tv[i] = rng();
  const h = new Float32Array(N * N), alb = new Float32Array(N * N), rough = new Float32Array(N * N), mask = new Float32Array(N * N);
  for (let y = 0; y < N; y++) {
    const yt = y / ts, j = Math.floor(yt), fy = yt - j;
    for (let x = 0; x < N; x++) {
      const xt = x / ts, i = Math.floor(xt), fx = xt - i, k = y * N + x;
      const rib = Math.pow(Math.sin(fx * Math.PI), 0.7);
      const bind = (((j - 2 * i) % 5) + 5) % 5 === 0 ? 1 - Math.pow(Math.abs(2 * fy - 1), 2) : 0;   // the weft crosses over here
      const thick = 0.8 + 0.4 * slub[k];
      h[k] = rib * thick * (1 - 0.45 * bind) + (fib[k] - 0.5) * 0.12;
      mask[k] = bind * rib;
      alb[k] = 0.5 + (tv[i] - 0.5) * 0.07 + (fib[k] - 0.5) * 0.1 + (mott[k] - 0.5) * 0.3 - bind * 0.06;
      rough[k] = 0.5 + (fib[k] - 0.5) * 0.18 + bind * 0.2 + (slub[k] - 0.5) * 0.12;
    }
  }
  return pack(N, alb, rough, mott, wear, h, 1.5 * s, mask, { r: 2, gain: 1.4 });
}

/**
 * 10 hemp / coarse cotton: plain weave of thick, uneven threads (width varies thread to thread, slubs and nubs along
 * them, fibre fuzz). Layer A blue = weave height (the gauze mode cuts its open mesh from it), mask = gaps.
 */
function hemp(N, rng, B) {
  const s = N / 512;
  const T = 24, ts = N / T;
  const wv = new Float32Array(T), fv = new Float32Array(T), wt = new Float32Array(T), ft = new Float32Array(T);
  for (let i = 0; i < T; i++) { wv[i] = rng(); fv[i] = rng(); wt[i] = 0.72 + 0.28 * rng(); ft[i] = 0.72 + 0.28 * rng(); }
  const slubX = vnoiseAniso(N, 8, T, rng), slubY = vnoiseAniso(N, T, 8, rng);
  const fibX = vnoiseAniso(N, 128, T * 2, rng), fibY = vnoiseAniso(N, T * 2, 128, rng);
  const mott = B.fbm(rng, 4, 4), wear = B.fbm(rng, 8, 5, 0.6);
  const h = new Float32Array(N * N), alb = new Float32Array(N * N), rough = new Float32Array(N * N), gap = new Float32Array(N * N), hb = new Float32Array(N * N);
  for (let y = 0; y < N; y++) {
    const yt = y / ts, j = Math.floor(yt) % T, fy = yt - Math.floor(yt);
    for (let x = 0; x < N; x++) {
      const xt = x / ts, i = Math.floor(xt) % T, fx = xt - Math.floor(xt), k = y * N + x;
      // thread bodies: half width per thread plus slubs; cross-section is a flattened arc
      const ww = wt[i] * (0.8 + 0.4 * slubY[k]), fw = ft[j] * (0.8 + 0.4 * slubX[k]);
      const dx = Math.abs(fx - 0.5) * 2 / ww, dy = Math.abs(fy - 0.5) * 2 / fw;
      const bx = dx < 1 ? Math.pow(1 - dx * dx, 0.45) : 0, by = dy < 1 ? Math.pow(1 - dy * dy, 0.45) : 0;
      // over / under: each thread rides a cosine, neighbours in antiphase
      const up = 0.5 + 0.5 * Math.cos(Math.PI * (yt - 0.5 + i)), uf = 0.5 - 0.5 * Math.cos(Math.PI * (xt - 0.5 + j));
      const hw = bx * (0.3 + 0.7 * up), hf = by * (0.3 + 0.7 * uf);
      const warp = hw >= hf, v = warp ? hw : hf;
      const fib = warp ? fibY[k] : fibX[k];
      h[k] = v * 0.9 + (fib - 0.5) * 0.16;
      hb[k] = v;
      gap[k] = 1 - sstep(0.04, 0.3, Math.max(bx, by));
      alb[k] = 0.5 + ((warp ? wv[i] : fv[j]) - 0.5) * 0.22 + (fib - 0.5) * 0.24 + (mott[k] - 0.5) * 0.4 - gap[k] * 0.2;
      rough[k] = 0.56 + (fib - 0.5) * 0.22 + gap[k] * 0.2;
    }
  }
  return pack(N, alb, rough, hb, wear, h, 2.0 * s, gap, { r: 3, gain: 2.2 });
}

/** Stroke collector for motif tiles: coordinates in 0..1 of the tile, widths in pixels at 256. */
function strokes(N) {
  const segs = [], k = N / 256;
  const S = {
    segs,
    line(pts, hw = 2.2, taper = false, val = 1) { segs.push(...polySegs(pts.map(([x, y]) => [x * N, y * N]), hw * k, val, taper)); return S; },
    dot(x, y, r) { segs.push([x * N, y * N, x * N + 0.01, y * N, r * N, 1]); return S; },
    arc(cx, cy, r, a0, a1, hw = 2.2, n = 24, taper = false) {
      const pts = [];
      for (let i = 0; i <= n; i++) { const a = a0 + (a1 - a0) * (i / n); pts.push([cx + Math.cos(a) * r, cy + Math.sin(a) * r]); }
      return S.line(pts, hw, taper);
    },
    /** Spiral from radius r0 at angle a0, shrinking to r1 over `turns` (dir +-1). */
    spiral(cx, cy, r0, r1, a0, turns, dir = 1, hw = 2.2, taper = true) {
      const pts = [], n = Math.ceil(26 * turns);
      for (let i = 0; i <= n; i++) { const t = i / n, a = a0 + dir * t * turns * Math.PI * 2, r = r0 + (r1 - r0) * Math.pow(t, 0.8); pts.push([cx + Math.cos(a) * r, cy + Math.sin(a) * r]); }
      return S.line(pts, hw, taper);
    },
    field() { const f = new Float32Array(N * N); lines(f, N, segs); return f; },
  };
  return S;
}

/** A cloud wisp (운문): spiral head, a smaller counter-curl riding on it and an S tail (tailLen head radii) trailing away along `ang`. */
function cloudWisp(S, cx, cy, R, ang, dir, hw, tailLen = 2.3) {
  const ca = Math.cos(ang), sa = Math.sin(ang);
  const P = (x, y) => [cx + (x * ca - y * sa * dir) * R, cy + (x * sa + y * ca * dir) * R];
  const head = [];
  for (let i = 0; i <= 36; i++) { const t = i / 36, a = t * Math.PI * 2 * 1.35, r = 1 - 0.8 * Math.pow(t, 0.85); head.push(P(Math.cos(a) * r, Math.sin(a) * r)); }
  S.line(head, hw, true);
  const tail = [];
  for (let i = 0; i <= 18; i++) { const t = i / 18; tail.push(P(1 + t * tailLen - 0.25 * Math.sin(t * Math.PI), -0.05 + 0.75 * Math.sin(t * Math.PI * 1.1) * (1 - 0.4 * t))); }
  S.line(tail, hw, true);
  const curl = [];
  for (let i = 0; i <= 20; i++) { const t = i / 20, a = Math.PI * 0.9 - t * Math.PI * 2 * 1.05, r = 0.5 * (1 - 0.75 * t); curl.push(P(1.55 + Math.cos(a) * r, -0.62 + Math.sin(a) * r)); }
  S.line(curl, hw * 0.9, true);
}

/**
 * 11 damask: tone-on-tone figured silk for whole garments. Scattered cloud wisps and small florets woven as satin
 * figure on a matt ground: the figure is smoother (it catches the light as the cloth turns), barely raised, and it is
 * the set mask, so the `vein` glow channel lets inner energy seep through the woven figure.
 */
function damask(N, rng, B) {
  const s = N / 512;
  const S = strokes(N);
  const spots = [[0.2, 0.22, 0.4, 1], [0.7, 0.36, 3.5, -1], [0.38, 0.72, 2.2, 1], [0.86, 0.84, 5.4, -1]];
  for (const [x, y, a, d] of spots) cloudWisp(S, x, y, 0.062, a, d, 2.6);
  for (const [x, y] of [[0.52, 0.1], [0.08, 0.55], [0.6, 0.6], [0.2, 0.92], [0.92, 0.12]]) {
    for (let q = 0; q < 4; q++) { const a = q * Math.PI / 2 + 0.4; S.dot(x + Math.cos(a) * 0.017, y + Math.sin(a) * 0.017, 0.011); }
    S.dot(x, y, 0.006);
  }
  const fig = S.field();
  const grain = vnoiseAniso(N, 128, 8, rng), mott = B.fbm(rng, 4, 4), wear = B.fbm(rng, 8, 5, 0.6);
  const halo = stretch(blur(fig, N, Math.max(1, Math.round(3 * s)), 2));
  const h = new Float32Array(N * N), alb = new Float32Array(N * N), rough = new Float32Array(N * N), mask = new Float32Array(N * N);
  for (let i = 0; i < N * N; i++) {
    const f = sstep(0.2, 0.7, fig[i]);
    mask[i] = f;
    h[i] = f * 0.34 + (grain[i] - 0.5) * 0.1;
    alb[i] = 0.5 + (mott[i] - 0.5) * 0.3 + f * 0.07 + (grain[i] - 0.5) * 0.08;
    rough[i] = 0.58 - f * 0.34 + (grain[i] - 0.5) * 0.14 + (mott[i] - 0.5) * 0.1;
  }
  return pack(N, alb, rough, halo, wear, h, 1.3 * s, mask, { r: 3, gain: 1.6 });
}

/**
 * 12 brocade motif atlas: eight embroidery bands, one height field per channel (the two selvedge lines included), each
 * tileable along u with the band across v. A: 0 cloud 운문, 1 wave 파도문, 2 flame 화염문, 3 fret 뇌문.
 * B: 4 red-sun emblem (적양문), 5 cold-moon emblem (한월궁), 6 thunder emblem (뇌운보), 7 tortoise-shell lattice 귀갑문.
 * All motifs are our own drawings of the common pattern families.
 */
function brocade(N) {
  const TAU = Math.PI * 2;
  const band = (draw) => {
    const S = strokes(N);
    S.line([[0, 0.055], [1, 0.055]], 1.7).line([[0, 0.945], [1, 0.945]], 1.7);
    draw(S);
    return S.field();
  };
  const cloud = band((S) => { cloudWisp(S, 0.28, 0.56, 0.235, 0, 1, 2.6, 2.0); });
  const wave = band((S) => {
    const w = 0.5;
    for (let u = 0; u < 2; u++) {
      const x0 = u * w;
      for (let e = 0; e < 3; e++) {
        const pts = [], end = 1 - e * 0.2;
        for (let i = 0; i <= 16; i++) { const t = (i / 16) * end; pts.push([x0 + w * (0.02 + 0.7 * t), 0.8 + e * 0.03 - (0.5 - e * 0.11) * t * t * (3 - 2 * t)]); }
        S.line(pts, 2.4 - e * 0.35, e > 0);
      }
      // the crest curls forward and down like a breaking wave
      S.spiral(x0 + w * 0.72, 0.3 + 0.075, 0.075, 0.014, -Math.PI / 2, 1.1, 1, 2.4);
      S.dot(x0 + w * 0.97, 0.24, 0.014).dot(x0 + w * 0.9, 0.15, 0.009).dot(x0 + w * 1.04, 0.4, 0.008);
      const base = [];
      for (let i = 0; i <= 10; i++) { const t = i / 10; base.push([x0 + w * t, 0.88 + 0.016 * Math.sin(t * TAU)]); }
      S.line(base, 1.5);
    }
  });
  const flame = band((S) => {
    const w = 0.5;
    const tongue = (xb, yb, xt, yt, bend, hw) => {
      const pts = [];
      for (let i = 0; i <= 16; i++) { const t = i / 16; pts.push([xb + (xt - xb) * t + bend * Math.sin(t * Math.PI * 1.25), yb + (yt - yb) * t]); }
      S.line(pts, hw, true);
    };
    for (let u = 0; u < 2; u++) {
      const xc = u * w + w * 0.5;
      tongue(xc, 0.89, xc + 0.02, 0.13, 0.06, 3.6);
      tongue(xc - 0.018, 0.89, xc - w * 0.33, 0.34, -0.05, 3.0);
      tongue(xc + 0.018, 0.89, xc + w * 0.35, 0.46, 0.045, 2.9);
      tongue(xc - 0.006, 0.86, xc - 0.014, 0.48, -0.022, 1.7);
      S.dot(u * w, 0.25, 0.016).dot(u * w + 0.02, 0.43, 0.009);
      S.arc(u * w, 0.93, w * 0.22, Math.PI * 1.15, Math.PI * 1.85, 1.7, 10);
    }
  });
  const fret = band((S) => {
    const sp = [[0.08, 0.92], [0.08, 0.08], [0.92, 0.08], [0.92, 0.92], [0.34, 0.92], [0.34, 0.34], [0.66, 0.34], [0.66, 0.66]];
    for (let c = 0; c < 3; c++) {
      const flip = c & 1;
      S.line(sp.map(([x, y]) => [(c + (flip ? 1 - x : x)) / 3, 0.18 + 0.64 * (flip ? 1 - y : y)]), 2.5);
    }
  });
  const sun = band((S) => {
    const cx = 0.5, cy = 0.5;
    S.arc(cx, cy, 0.165, 0, TAU, 2.6, 32).dot(cx, cy, 0.07);
    for (let q = 0; q < 8; q++) {
      const pts = [], a0 = q * TAU / 8 + 0.2;
      for (let i = 0; i <= 7; i++) { const t = i / 7, a = a0 + 0.34 * t * t, r = 0.22 + 0.14 * t; pts.push([cx + Math.cos(a) * r, cy + Math.sin(a) * r]); }
      S.line(pts, 3.6, true);
    }
    S.line([[-0.04, 0.5], [0, 0.4], [0.04, 0.5], [0, 0.6], [-0.04, 0.5]], 1.8).dot(0, 0.5, 0.012);
  });
  const moon = band((S) => {
    const cx = 0.36, cy = 0.5, R = 0.24, th = 50 * Math.PI / 180, d = 0.11;
    const tx = R * Math.cos(th) - d, ty = R * Math.sin(th), r2 = Math.hypot(tx, ty), ph = Math.atan2(ty, tx);
    S.arc(cx, cy, R, th, TAU - th, 2.7, 34).arc(cx + d, cy, r2, ph, TAU - ph, 2.2, 28);
    const sx = 0.76, sy = 0.36, sr = 0.09;
    for (let q = 0; q < 3; q++) {
      const a = q * Math.PI / 3 + Math.PI / 2, ca = Math.cos(a), sa = Math.sin(a);
      S.line([[sx - ca * sr, sy - sa * sr], [sx + ca * sr, sy + sa * sr]], 1.8);
      for (const e of [-1, 1]) for (const b of [-1, 1]) {
        const px = sx + e * ca * sr * 0.58, py = sy + e * sa * sr * 0.58, ba = a + b * Math.PI / 3;
        S.line([[px, py], [px + e * Math.cos(ba) * sr * 0.36, py + e * Math.sin(ba) * sr * 0.36]], 1.4);
      }
    }
    S.dot(0.8, 0.72, 0.015).dot(0.66, 0.8, 0.009).dot(0.93, 0.58, 0.008);
  });
  const thunder = band((S) => {
    const cx = 0.5;
    S.line([[cx - 0.29, 0.5], [cx, 0.16], [cx + 0.29, 0.5], [cx, 0.84], [cx - 0.29, 0.5]], 2.1);
    S.line([[cx - 0.1, 0.25], [cx + 0.06, 0.47], [cx - 0.055, 0.53], [cx + 0.11, 0.77]], 3.6, true);
    const q = 0.06;
    for (const sg of [1, -1]) {
      const y0 = 0.5 + sg * 0.2;
      S.line([[-q, y0 + sg * q], [-q, y0 - sg * q], [q, y0 - sg * q], [q, y0 + sg * q * 0.45], [-q * 0.25, y0 + sg * q * 0.45], [-q * 0.25, y0 - sg * q * 0.3]], 1.8);
    }
  });
  const lattice = band((S) => {
    const r = 0.25 / Math.sqrt(3), w = 0.25;
    const hex = (cx, cy) => { const pts = []; for (let q = 0; q <= 6; q++) { const a = q * Math.PI / 3 + Math.PI / 6; pts.push([cx + Math.cos(a) * r, cy + Math.sin(a) * r]); } S.line(pts, 1.9); };
    for (let c = 0; c < 4; c++) {
      hex(c * w + w / 2, 0.5); S.dot(c * w + w / 2, 0.5, 0.019);
      hex(c * w, 0.5 - 1.5 * r); hex(c * w, 0.5 + 1.5 * r);
    }
  });
  const A = new Uint8Array(N * N * 4), Bq = new Uint8Array(N * N * 4);
  const put4 = (dst, fs) => { for (let i = 0; i < N * N; i++) for (let c = 0; c < 4; c++) dst[i * 4 + c] = Math.round(sat(fs[c][i]) * 255); };
  put4(A, [cloud, wave, flame, fret]);
  put4(Bq, [sun, moon, thunder, lattice]);
  return { A, B: Bq };
}

/**
 * 13 lacquer (옻칠): a deep, glassy coat. Faint orange peel and wiped streaks in the gloss, dust pits, and a sparse
 * craquelure where the coat has aged (mask = cracks, blue = their halo): the `vein` channel glows through the cracks.
 */
function lacquer(N, rng, B) {
  const s = N / 512;
  const wx = B.fbm(rng, 8, 4), wy = B.fbm(rng, 8, 4);
  const warp = [new Float32Array(N * N), new Float32Array(N * N)];
  for (let i = 0; i < N * N; i++) { warp[0][i] = (wx[i] - 0.5) * 30 * s; warp[1][i] = (wy[i] - 0.5) * 30 * s; }
  const cells = worley(N, 9, rng, warp, 0.9), pits = worley(N, 26, rng);
  const keep = B.fbm(rng, 4, 4), peel = B.fbm(rng, 16, 3), fine = B.fbm(rng, 64, 3), pitKeep = B.fbm(rng, 8, 5, 0.6);
  const mott = B.fbm(rng, 4, 4), wear = B.fbm(rng, 8, 5, 0.6);
  const wipe = vnoiseAniso(N, 4, 96, rng);
  const core = new Float32Array(N * N);
  for (let i = 0; i < N * N; i++) {
    const e = (cells.f2[i] - cells.f1[i]) / 9 * 512 * s;
    core[i] = (1 - sstep(0.25 * s, 1.5 * s, e)) * sstep(0.56, 0.7, keep[i]);
  }
  const halo = stretch(blur(core, N, Math.max(1, Math.round(4 * s)), 2));
  const h = new Float32Array(N * N), alb = new Float32Array(N * N), rough = new Float32Array(N * N);
  for (let i = 0; i < N * N; i++) {
    const pit = (1 - sstep(0.0, 0.09, pits.f1[i])) * sstep(0.66, 0.8, pitKeep[i]);
    h[i] = (peel[i] - 0.5) * 0.1 + (fine[i] - 0.5) * 0.03 - core[i] * 0.5 - pit * 0.2;
    alb[i] = 0.5 + (mott[i] - 0.5) * 0.3 - core[i] * 0.25 - pit * 0.1;
    rough[i] = 0.42 + (wipe[i] - 0.5) * 0.3 + (mott[i] - 0.5) * 0.16 + core[i] * 0.4 + pit * 0.3;
  }
  return pack(N, alb, rough, halo, wear, h, 2.2 * s, core, { r: 3, gain: 2.5 });
}

/**
 * 14 lamellar (찰갑), UV set: one tile = 4 small plates across x 2 rows (the lower row offset by half a plate). Each
 * plate is domed, shingled over its neighbour and tucked under the row above, with rounded lower corners. A braided
 * lacing cord runs along every row and one suspension lace per plate drops over its lower edge to the row below
 * (mask = cords, blue = closeness to the plate rim for edge wear).
 */
function lamellar(N, rng, B) {
  const s = N / 512;
  const pw = N / 4, ph = N / 2;
  const mott = B.fbm(rng, 4, 4), wear = B.fbm(rng, 8, 5, 0.6), grain = B.fbm(rng, 64, 3);
  const pid = new Float32Array(8);
  for (let i = 0; i < 8; i++) pid[i] = rng();
  const h = new Float32Array(N * N), alb = new Float32Array(N * N), rough = new Float32Array(N * N), cord = new Float32Array(N * N), prox = new Float32Array(N * N);
  const rc = 0.34;                                 // corner radius, plate widths
  for (let y = 0; y < N; y++) {
    const row = Math.floor(y / ph), fy = y / ph - row;
    for (let x = 0; x < N; x++) {
      const k = y * N + x;
      const xs = (x + (row & 1) * pw * 0.5) / pw, col = Math.floor(xs), fx = xs - col;
      // distance (plate widths) to the plate outline: sides, bottom with rounded corners; the top is hidden
      const ax = Math.min(fx, 1 - fx), ay = (1 - fy) * (ph / pw);
      let d = Math.min(ax, ay);
      if (ax < rc && ay < rc) d = rc - Math.hypot(rc - ax, rc - ay);
      const inside = d > 0.015 ? 1 : 0;
      const bevel = sstep(0.015, 0.12, d);
      const id = pid[(row & 1) * 4 + (col & 3)];
      // a plate: tucked under the row above (low at its top), proud and bevelled at its lower rim, tilted over its neighbour
      let z = inside
        ? 0.3 + 0.36 * bevel + fy * 0.3 + (0.5 - fx) * 0.2 + 0.08 * Math.sin(fx * Math.PI) + (id - 0.5) * 0.08
        : 0.05;
      // lacing: a braided cord along the row; one suspension lace per plate over its lower edge
      let c = 0;
      const sy = Math.abs(fy - 0.2) * ph, hw = 0.036 * ph;
      if (sy < hw) c = Math.sqrt(1 - (sy / hw) ** 2) * (0.72 + 0.28 * Math.sin((x * 2 + (fy - 0.2) * ph * 2.4) * Math.PI / (pw * 0.25)));
      const ex = Math.abs(fx - 0.5) * pw, vw = 0.05 * pw;
      if (ex < vw && fy > 0.66) c = Math.max(c, Math.sqrt(1 - (ex / vw) ** 2) * sstep(0.66, 0.72, fy) * (0.8 + 0.2 * Math.sin(y * 1.9 / s)));
      if (c > 0) z = Math.max(z, (inside ? z : 0.4) + 0.2 * c);
      cord[k] = sstep(0.2, 0.55, c);
      h[k] = z + (grain[k] - 0.5) * 0.04;
      prox[k] = inside ? 1 - bevel : 0;
      alb[k] = 0.5 + (id - 0.5) * 0.3 + (mott[k] - 0.5) * 0.3 - (inside ? 0 : 0.4);
      rough[k] = 0.5 + (mott[k] - 0.5) * 0.3 + (id - 0.5) * 0.2 + (inside ? 0 : 0.3);
    }
  }
  return pack(N, alb, rough, prox, wear, h, 3.0 * s, cord, { r: 4, gain: 2.6 });
}

/**
 * 15 woven bamboo (죽립), UV set: a 2/2 twill plait of flat split-bamboo strips, 8 x 8 per tile (the spokes run along
 * v). Flat crowns with bevelled edges, fibres along each strip, a node ring here and there, strips of slightly
 * different age and colour (mask = the pinholes where four strips meet).
 */
function bamboo(N, rng, B) {
  const s = N / 512;
  const T = 8, ts = N / T;
  const cu = new Float32Array(T), cv = new Float32Array(T), nu = new Float32Array(T), nvv = new Float32Array(T);
  for (let i = 0; i < T; i++) { cu[i] = rng(); cv[i] = rng(); nu[i] = rng(); nvv[i] = rng(); }
  const fibX = vnoiseAniso(N, 8, 128, rng), fibY = vnoiseAniso(N, 128, 8, rng);
  const mott = B.fbm(rng, 4, 4), wear = B.fbm(rng, 8, 5, 0.6);
  const h = new Float32Array(N * N), alb = new Float32Array(N * N), rough = new Float32Array(N * N), hole = new Float32Array(N * N), hb = new Float32Array(N * N);
  for (let y = 0; y < N; y++) {
    const j = Math.floor(y / ts), fy = y / ts - j;
    for (let x = 0; x < N; x++) {
      const i = Math.floor(x / ts), fx = x / ts - i, k = y * N + x;
      const spokeTop = ((i + j) & 3) < 2;
      const px = Math.min(1, Math.min(fx, 1 - fx) / 0.16), py = Math.min(1, Math.min(fy, 1 - fy) / 0.16);
      const ex = sstep(0, 1, px), ey = sstep(0, 1, py);
      // the strip on top is a flat crown; where it dives under the next crossing it slopes down toward its ends
      const dive = (f) => 0.82 + 0.18 * Math.sin(f * Math.PI);
      const top = spokeTop ? ex * dive(fy) : ey * dive(fx);
      const under = (spokeTop ? ey : ex) * 0.34;
      const v = Math.max(top * (0.55 + 0.45 * (spokeTop ? ex : ey)), under);
      const onTop = top >= under;
      const isSpoke = onTop ? spokeTop : !spokeTop;
      const fib = isSpoke ? fibY[k] : fibX[k];
      // node ring across a strip (one per strip per tile, at its own place)
      const along = isSpoke ? y / N : x / N, np = isSpoke ? nu[i] : nvv[j];
      const dn = Math.abs(((along - np + 1.5) % 1) - 0.5) * N;
      const node = (1 - sstep(0.8 * s, 2.6 * s, dn)) * (onTop ? 1 : 0);
      h[k] = v + (fib - 0.5) * 0.09 + node * 0.07;
      hb[k] = v;
      hole[k] = 1 - sstep(0.02, 0.2, Math.max(px, py));
      const tone = isSpoke ? cu[i] : cv[j] * 0.85;
      alb[k] = 0.5 + (tone - 0.5) * 0.34 + (fib - 0.5) * 0.2 + (mott[k] - 0.5) * 0.22 - node * 0.16 - (onTop ? 0 : 0.14);
      rough[k] = 0.46 + (fib - 0.5) * 0.24 + (1 - (isSpoke ? ex : ey)) * 0.16 + node * 0.12;
    }
  }
  return pack(N, alb, rough, hb, wear, h, 2.2 * s, hole, { r: 3, gain: 2.4 });
}

const GENERATORS = [hammered, scorched, engraved, leather, cloth, fur, mail, quilted, silk, hemp, damask, brocade, lacquer, lamellar, bamboo];
const NAMES = Object.keys(SET);
