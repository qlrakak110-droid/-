// Procedural, tileable PBR-ish textures (color + normal map) generated on canvas at load time.
import * as THREE from 'three';

const mod = (a, n) => ((a % n) + n) % n;

function hash(x, y, s) {
  let h = (x * 374761393 + y * 668265263 + s * 982451653) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967295;
}

/** Periodic value noise: tiles every `p` lattice cells. */
function vnoise(x, y, p, seed) {
  const xi = Math.floor(x), yi = Math.floor(y);
  const xf = x - xi, yf = y - yi;
  const u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf);
  const x0 = mod(xi, p), x1 = mod(xi + 1, p), y0 = mod(yi, p), y1 = mod(yi + 1, p);
  const a = hash(x0, y0, seed), b = hash(x1, y0, seed), c = hash(x0, y1, seed), d = hash(x1, y1, seed);
  return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
}

/** Tileable fBm on [0,1)^2 with `base` cells per tile at the first octave. */
export function fbm(u, v, base, oct, seed) {
  let sum = 0, amp = 0.5, norm = 0, p = base;
  for (let o = 0; o < oct; o++) {
    sum += vnoise(u * p, v * p, p, seed + o * 17) * amp;
    norm += amp;
    amp *= 0.5;
    p *= 2;
  }
  return sum / norm;
}

/**
 * Build a texture pair from a per-pixel function returning [r, g, b, height].
 * Height drives the normal map; colors are 0..255.
 */
function generate(size, fn, { normalStrength = 2, repeat = true } = {}) {
  const color = new Uint8ClampedArray(size * size * 4);
  const height = new Float32Array(size * size);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const [r, g, b, h] = fn(x / size, y / size, x, y);
      const i = y * size + x;
      color[i * 4] = r; color[i * 4 + 1] = g; color[i * 4 + 2] = b; color[i * 4 + 3] = 255;
      height[i] = h;
    }
  }
  const nrm = new Uint8ClampedArray(size * size * 4);
  const H = (x, y) => height[mod(y, size) * size + mod(x, size)];
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const dx = (H(x + 1, y) - H(x - 1, y)) * normalStrength;
      const dy = (H(x, y + 1) - H(x, y - 1)) * normalStrength;
      const l = Math.hypot(dx, dy, 1);
      const i = (y * size + x) * 4;
      nrm[i] = (-dx / l * 0.5 + 0.5) * 255;
      nrm[i + 1] = (dy / l * 0.5 + 0.5) * 255;
      nrm[i + 2] = (1 / l * 0.5 + 0.5) * 255;
      nrm[i + 3] = 255;
    }
  }
  const toTex = (data, srgb) => {
    const c = document.createElement('canvas');
    c.width = c.height = size;
    c.getContext('2d').putImageData(new ImageData(data, size, size), 0, 0);
    const t = new THREE.CanvasTexture(c);
    if (repeat) t.wrapS = t.wrapT = THREE.RepeatWrapping;
    if (srgb) t.colorSpace = THREE.SRGBColorSpace;
    t.anisotropy = 8;
    return t;
  };
  return { map: toTex(color, true), normalMap: toTex(nrm, false) };
}

const shade = (base, k) => [base[0] * k, base[1] * k, base[2] * k];
const mix = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
const smooth = (e0, e1, x) => { const t = Math.min(1, Math.max(0, (x - e0) / (e1 - e0))); return t * t * (3 - 2 * t); };

export function makeTextures() {
  const T = {};

  // Paving slabs: 4x4 per tile, bevelled joints, per-slab tint, grime.
  T.ground = generate(512, (u, v) => {
    const tu = u * 4, tv = v * 4;
    const cx = Math.floor(tu), cy = Math.floor(tv);
    const fx = tu - cx, fy = tv - cy;
    const edge = Math.min(fx, fy, 1 - fx, 1 - fy);
    const joint = smooth(0.006, 0.03, edge);
    const tint = 0.9 + hash(cx, cy, 3) * 0.16;
    const n = fbm(u, v, 8, 5, 11), dirt = fbm(u, v, 3, 4, 41);
    const pits = fbm(u, v, 64, 2, 7) > 0.72 ? -0.4 : 0;
    let c = shade([150, 145, 135], tint * (0.85 + n * 0.3));
    c = mix(c, [98, 90, 78], smooth(0.5, 0.8, dirt) * 0.55);
    c = mix([62, 58, 52], c, joint);
    return [...c, joint * 1.0 + n * 0.25 + pits * 0.15];
  }, { normalStrength: 3 });

  // Cast concrete with formwork seams, tie holes and rain streaks.
  T.concrete = generate(512, (u, v) => {
    const n = fbm(u, v, 6, 5, 21), fine = fbm(u, v, 48, 2, 22);
    const seamX = Math.min(u % 0.5, 0.5 - (u % 0.5)), seamY = Math.min(v % 0.5, 0.5 - (v % 0.5));
    const seam = smooth(0.0, 0.006, Math.min(seamX, seamY));
    const hx = (u % 0.25) - 0.125, hy = (v % 0.25) - 0.125;
    const hole = smooth(0.01, 0.016, Math.hypot(hx, hy));
    const streak = fbm(u * 1, v * 0.1, 16, 3, 23);
    let c = shade([196, 188, 172], 0.86 + n * 0.25);
    c = mix(c, [130, 122, 110], smooth(0.55, 0.85, streak) * 0.5 * v);
    c = shade(c, 0.75 + 0.25 * seam * hole);
    const pits = fine > 0.7 ? -0.6 : 0;
    return [...c, seam * hole + n * 0.35 + pits * 0.1];
  }, { normalStrength: 2.5 });

  // Concrete block wall in running bond.
  T.wall = generate(512, (u, v) => {
    const rows = 16, cols = 8;
    const ry = v * rows, row = Math.floor(ry);
    const rx = u * cols + (row % 2) * 0.5, col = Math.floor(rx);
    const fx = rx - col, fy = ry - row;
    const edge = Math.min(fx / 2, fy, (1 - fx) / 2, 1 - fy);
    const mortar = smooth(0.02, 0.06, edge);
    const tint = 0.88 + hash(mod(col, cols), row, 5) * 0.18;
    const n = fbm(u, v, 8, 5, 31), stain = fbm(u, v, 2, 3, 37);
    let c = shade([168, 163, 152], tint * (0.85 + n * 0.3));
    c = mix(c, [110, 104, 94], smooth(0.45, 0.8, stain) * 0.45);
    c = mix([120, 116, 108], c, mortar);
    return [...c, mortar * 0.9 + n * 0.3];
  }, { normalStrength: 3 });

  // Wooden crate: planks, frame and diagonal brace with nails.
  T.crate = generate(256, (u, v, x, y) => {
    const border = Math.min(u, v, 1 - u, 1 - v);
    const frame = border < 0.09;
    const d = Math.abs(u - v) / Math.SQRT2;
    const brace = !frame && d < 0.055;
    const plank = Math.floor(v * 5);
    const grain = fbm(u * (frame ? 0.3 : 1) + plank * 0.37, v * (frame ? 1 : 0.1), 32, 4, 51 + plank);
    let c = shade([168, 120, 68], 0.75 + grain * 0.45 + hash(plank, 1, 52) * 0.08);
    let h = grain * 0.2;
    if (frame || brace) { c = shade(c, 0.82); h += 1; }
    else {
      const pv = v * 5 - plank;
      if (pv < 0.04 || pv > 0.96) { c = shade(c, 0.45); h -= 0.6; }
    }
    if (frame) { const inner = smooth(0.07, 0.09, border); h -= inner * 0.4; }
    for (const [nx, ny] of [[0.045, 0.045], [0.955, 0.045], [0.045, 0.955], [0.955, 0.955], [0.5, 0.5]]) {
      if (Math.hypot(u - nx, v - ny) < 0.012) { c = [70, 66, 60]; h += 0.6; }
    }
    return [...c, h];
  }, { normalStrength: 3 });

  // Corrugated container steel with rust and scratches (white base; tinted by material colour).
  T.container = generate(256, (u, v) => {
    const ribs = 8, p = (u * ribs) % 1;
    const prof = p < 0.15 ? p / 0.15 : p < 0.5 ? 1 : p < 0.65 ? 1 - (p - 0.5) / 0.15 : 0;
    const n = fbm(u, v, 4, 5, 61), rust = fbm(u, v, 6, 5, 67);
    const r = smooth(0.62, 0.75, rust * (0.7 + 0.6 * v));
    let c = shade([235, 235, 235], 0.82 + n * 0.25);
    c = mix(c, [150, 96, 60], r * 0.85);
    const scratch = fbm(u * 0.2, v * 3, 32, 2, 69) > 0.78 ? 0.75 : 1;
    c = shade(c, scratch);
    return [...c, prof * 1.2 + n * 0.1 - r * 0.15];
  }, { normalStrength: 4 });

  // Painted metal (barrels) with chipped paint.
  T.metal = generate(256, (u, v) => {
    const n = fbm(u, v, 6, 5, 71), chip = fbm(u, v, 12, 4, 73);
    const band = Math.abs(v - 0.33) < 0.02 || Math.abs(v - 0.66) < 0.02;
    let c = shade([230, 230, 230], 0.85 + n * 0.2);
    const chipped = smooth(0.66, 0.7, chip);
    c = mix(c, [90, 80, 72], chipped);
    return [...c, (band ? 1 : 0) + chipped * -0.3 + n * 0.1];
  }, { normalStrength: 3 });

  // Woodland camo fabric with weave.
  T.camo = generate(256, (u, v) => {
    const a = fbm(u, v, 4, 4, 81), b = fbm(u, v, 5, 4, 83), cN = fbm(u, v, 6, 4, 87);
    let c = [104, 110, 82];
    if (a > 0.55) c = [72, 80, 56];
    if (b > 0.6) c = [128, 112, 84];
    if (cN > 0.66) c = [48, 46, 40];
    const weave = (Math.sin(u * 256 * Math.PI) * Math.sin(v * 256 * Math.PI)) * 0.5 + 0.5;
    c = shade(c, 0.9 + weave * 0.12);
    return [...c, weave * 0.4];
  }, { normalStrength: 1.5 });

  // Plain tactical nylon (vest/helmet cover; tinted by material colour).
  T.nylon = generate(128, (u, v) => {
    const weave = (Math.sin(u * 128 * Math.PI) * 0.5 + 0.5) * (Math.sin(v * 128 * Math.PI) * 0.5 + 0.5);
    const n = fbm(u, v, 4, 3, 91);
    const c = shade([225, 225, 225], 0.85 + n * 0.2 + weave * 0.08);
    return [...c, weave * 0.5];
  }, { normalStrength: 1.5 });

  // Burlap sand bags.
  T.burlap = generate(128, (u, v) => {
    const wx = Math.sin(u * 96 * Math.PI), wy = Math.sin(v * 96 * Math.PI);
    const n = fbm(u, v, 4, 4, 95);
    const c = shade([176, 156, 112], 0.8 + n * 0.3 + (wx * wy) * 0.06);
    return [...c, (wx * 0.5 + 0.5) * (wy * 0.5 + 0.5)];
  }, { normalStrength: 2 });

  // Gun metal: subtle brushed finish.
  T.gunmetal = generate(128, (u, v) => {
    const n = fbm(u * 0.1, v, 32, 3, 101);
    const c = shade([200, 200, 200], 0.9 + n * 0.15);
    return [...c, n * 0.3];
  }, { normalStrength: 1 });

  // Office-tower facade for the skyline (map + emissive for lit windows).
  {
    const size = 256;
    const c = document.createElement('canvas'), e = document.createElement('canvas');
    c.width = c.height = e.width = e.height = size;
    const g = c.getContext('2d'), ge = e.getContext('2d');
    g.fillStyle = '#7f8794'; g.fillRect(0, 0, size, size);
    ge.fillStyle = '#000'; ge.fillRect(0, 0, size, size);
    for (let y = 0; y < 16; y++) for (let x = 0; x < 8; x++) {
      const lit = hash(x, y, 7) > 0.82;
      g.fillStyle = lit ? '#c9b98a' : `rgb(${40 + hash(x, y, 9) * 30},${55 + hash(x, y, 9) * 30},${75 + hash(x, y, 9) * 35})`;
      g.fillRect(x * 32 + 5, y * 16 + 3, 22, 10);
      if (lit) { ge.fillStyle = '#ffd9a0'; ge.fillRect(x * 32 + 5, y * 16 + 3, 22, 10); }
    }
    const mk = (cv, srgb) => {
      const t = new THREE.CanvasTexture(cv);
      t.wrapS = t.wrapT = THREE.RepeatWrapping;
      if (srgb) t.colorSpace = THREE.SRGBColorSpace;
      return t;
    };
    T.facade = { map: mk(c, true), emissiveMap: mk(e, true) };
  }
  // Muzzle flash star.
  {
    const s = 128, c = document.createElement('canvas');
    c.width = c.height = s;
    const g = c.getContext('2d');
    const grd = g.createRadialGradient(s / 2, s / 2, 0, s / 2, s / 2, s / 2);
    grd.addColorStop(0, 'rgba(255,255,235,1)'); grd.addColorStop(0.25, 'rgba(255,200,90,.9)'); grd.addColorStop(1, 'rgba(255,120,20,0)');
    g.fillStyle = grd;
    g.beginPath();
    for (let i = 0; i < 16; i++) {
      const a = (i / 16) * Math.PI * 2, r = i % 2 ? s * 0.18 : s * 0.5;
      g.lineTo(s / 2 + Math.cos(a) * r, s / 2 + Math.sin(a) * r);
    }
    g.fill();
    T.muzzle = new THREE.CanvasTexture(c);
    T.muzzle.colorSpace = THREE.SRGBColorSpace;
  }
  // Soft round puff for smoke/dust.
  {
    const s = 64, c = document.createElement('canvas');
    c.width = c.height = s;
    const g = c.getContext('2d');
    const grd = g.createRadialGradient(s / 2, s / 2, 0, s / 2, s / 2, s / 2);
    grd.addColorStop(0, 'rgba(255,255,255,.9)'); grd.addColorStop(0.5, 'rgba(255,255,255,.35)'); grd.addColorStop(1, 'rgba(255,255,255,0)');
    g.fillStyle = grd; g.fillRect(0, 0, s, s);
    T.puff = new THREE.CanvasTexture(c);
  }
  return T;
}
