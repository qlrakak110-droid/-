// Procedural ink for the murim UI: brush strokes with pressure and dry-brush (비백) streaks, dividers, ragged band
// clips, seals (낙관), the ink eclipse, ink-wash mountains, ink splashes and the paper / wash textures. Everything is
// generated in code (SVG strings / 2D canvas) from fixed seeds, so the look never depends on an installed brush font
// and captures are deterministic. Nothing here animates: the UI moves the finished pieces with transform / opacity
// only. Brush-written Hangul (the title, announcer marks, names) lives in brush.js on top of strokePath().

import { makeRng, clamp, smoothstep } from '../core/math.js';

const r1 = (v) => String(Math.round(v * 10) / 10);
const r2 = (v) => String(Math.round(v * 100) / 100);
let uid = 0;

/** Serif (myeongjo) stack for Korean + Hanja; the same list is the CSS token --f-ko. */
export const FONT_KO = '"Noto Serif KR","Noto Serif CJK KR","Source Han Serif KR","Source Han Serif K","Nanum Myeongjo","NanumMyeongjo","AppleMyungjo","Batang","HYSinMyeongJo","Songti SC","SimSun","Hiragino Mincho ProN","Yu Mincho",Georgia,serif';

// ---------------------------------------------------------------------------------------------------------------
// noise

/** Smooth 1D value noise in -1..1 (seeded, period 64). */
function noise1(seed) {
  const rng = makeRng(seed);
  const tab = new Float32Array(64);
  for (let i = 0; i < 64; i++) tab[i] = rng() * 2 - 1;
  return (x) => {
    const i = Math.floor(x), f = x - i, u = f * f * (3 - 2 * f);
    const a = tab[i & 63], b = tab[(i + 1) & 63];
    return a + (b - a) * u;
  };
}

/** Smooth 2D value noise in 0..1 from a 128x128 table (seeded, tiles at 128). */
function noise2(seed) {
  const rng = makeRng(seed);
  const tab = new Float32Array(128 * 128);
  for (let i = 0; i < tab.length; i++) tab[i] = rng();
  return (x, y) => {
    const ix = Math.floor(x), iy = Math.floor(y);
    const fx = x - ix, fy = y - iy;
    const ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy);
    const x0 = ix & 127, x1 = (ix + 1) & 127, y0 = (iy & 127) << 7, y1 = ((iy + 1) & 127) << 7;
    const a = tab[x0 + y0], b = tab[x1 + y0], c = tab[x0 + y1], d = tab[x1 + y1];
    return a + (b - a) * ux + (c - a + (a - b - c + d) * ux) * uy;
  };
}

// ---------------------------------------------------------------------------------------------------------------
// brush strokes

/** Pressure profiles: [t, width multiplier] pairs along the stroke. */
export const PROFILE = {
  pull: [[0, 0.7], [0.07, 1.08], [0.3, 0.9], [0.72, 0.8], [1, 0.3]],     // press, pull, lift (long horizontals)
  bone: [[0, 0.82], [0.09, 1.1], [0.5, 0.8], [0.9, 1.02], [1, 0.78]],    // heavy at both ends
  drop: [[0, 0.8], [0.09, 1.14], [0.55, 0.9], [0.86, 0.6], [1, 0.1]],    // vertical ending in a needle point
  post: [[0, 0.85], [0.1, 1.12], [0.6, 0.92], [1, 0.62]],                // vertical with a blunt foot
  dot: [[0, 0.35], [0.45, 1.15], [1, 0.55]],
  ring: [[0, 0.5], [0.08, 1.1], [0.35, 0.95], [0.7, 0.7], [1, 0.16]],    // enso
  flat: [[0, 1], [1, 1]],
  hair: [[0, 0.3], [0.2, 1], [0.8, 0.9], [1, 0.1]],
};

function profileAt(p, t) {
  for (let i = 1; i < p.length; i++) {
    if (t <= p[i][0]) {
      const a = p[i - 1], b = p[i];
      const u = (t - a[0]) / Math.max(1e-6, b[0] - a[0]);
      return a[1] + (b[1] - a[1]) * (u * u * (3 - 2 * u));
    }
  }
  return p[p.length - 1][1];
}

/** Catmull-Rom samples of a polyline: returns { x, y, tx, ty, t }[] with unit tangents and arc-length t. */
function sampleSpline(pts, n) {
  const P = (i) => pts[Math.max(0, Math.min(pts.length - 1, i))];
  const out = [];
  const segs = pts.length - 1;
  for (let k = 0; k <= n; k++) {
    const u = (k / n) * segs;
    const i = Math.min(segs - 1, Math.floor(u)), f = u - i;
    const p0 = P(i - 1), p1 = P(i), p2 = P(i + 1), p3 = P(i + 2);
    const f2 = f * f, f3 = f2 * f;
    const c = (a, b, c2, d) => 0.5 * (2 * b + (-a + c2) * f + (2 * a - 5 * b + 4 * c2 - d) * f2 + (-a + 3 * b - 3 * c2 + d) * f3);
    out.push({ x: c(p0[0], p1[0], p2[0], p3[0]), y: c(p0[1], p1[1], p2[1], p3[1]), tx: 0, ty: 0, t: 0 });
  }
  let len = 0;
  for (let k = 1; k < out.length; k++) { len += Math.hypot(out[k].x - out[k - 1].x, out[k].y - out[k - 1].y); out[k].t = len; }
  for (let k = 0; k < out.length; k++) {
    const a = out[Math.max(0, k - 1)], b = out[Math.min(out.length - 1, k + 1)];
    const d = Math.hypot(b.x - a.x, b.y - a.y) || 1;
    out[k].tx = (b.x - a.x) / d; out[k].ty = (b.y - a.y) / d;
    out[k].t = len > 0 ? out[k].t / len : 0;
  }
  out.len = len;
  return out;
}

/** Closed smooth outline through polygon points (quadratic through edge midpoints: soft, organic edges). */
function smoothClosed(p) {
  const n = p.length;
  let d = `M${r1((p[0][0] + p[n - 1][0]) / 2)} ${r1((p[0][1] + p[n - 1][1]) / 2)}`;
  for (let i = 0; i < n; i++) {
    const a = p[i], b = p[(i + 1) % n];
    d += `Q${r1(a[0])} ${r1(a[1])} ${r1((a[0] + b[0]) / 2)} ${r1((a[1] + b[1]) / 2)}`;
  }
  return d + 'Z';
}

/**
 * One brush stroke as SVG path data. Dry-brush streaks are sub-paths wound against the body, so with the default
 * (nonzero) fill rule they are holes and any number of strokes can share one <path>.
 * @param {number[][]} pts centre line [[x, y], ...] (a spline goes through the points)
 * @param {{ w?: number, profile?: number[][], rough?: number, dry?: number, seed?: number, spray?: number, head?: string, streaks?: number, streakW?: number }} [o]
 *   w: full width at pressure 1; rough: edge jitter 0..1; dry: 0..1 amount of dry-brush streaks toward the end
 *   (streaks: how many, streakW: their relative thickness); spray: flecks thrown off the tail; head: 'round' |
 *   'slant' (the brush lands from the upper left)
 * @returns {string} path data
 */
export function strokePath(pts, o = {}) {
  const { w = 8, profile = PROFILE.pull, rough = 0.5, dry = 0, seed = 1, spray = 0, head: headKind = 'round', streaks, streakW = 1 } = o;
  const rng = makeRng(seed * 7919 + 13);
  const nA = noise1(seed * 3 + 1), nB = noise1(seed * 3 + 2);
  let len = 0;
  for (let i = 1; i < pts.length; i++) len += Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]);
  const N = clamp(Math.round(len / Math.max(1.5, w * 0.55)), 8, 72);
  const S = sampleSpline(pts, N);
  const hw = (t, nz, k) => {
    const j = 1 + rough * (0.16 * nz(k * 0.9 + 3) + 0.1 * nz(k * 2.7 + 11));
    return Math.max(0.15, 0.5 * w * profileAt(profile, t) * j);
  };
  const L = [], R = [];
  for (let k = 0; k <= N; k++) {
    const s = S[k];
    const a = hw(s.t, nA, k), b = hw(s.t, nB, k);
    L.push([s.x - s.ty * a, s.y + s.tx * a]);
    R.push([s.x + s.ty * b, s.y - s.tx * b]);
  }
  // caps: a rounded head where the brush lands, a ragged or pointed tail where it lifts
  const head = S[0], tail = S[N];
  const h0 = 0.5 * w * profileAt(profile, 0), h1 = 0.5 * w * profileAt(profile, 1);
  let capH;
  if (headKind === 'slant') {
    // the brush lands from the upper left: that corner of the head juts out sharp, the other one stays round
    const lx = -head.ty, ly = head.tx;                                       // normal toward the L edge
    const sgn = lx * -1 + ly * -1 > 0 ? 1 : -1;                              // which edge faces the upper left
    const corner = [head.x - head.tx * h0 * 1.05 + sgn * lx * h0 * 1.22, head.y - head.ty * h0 * 1.05 + sgn * ly * h0 * 1.22];
    const round = [head.x - head.tx * h0 * 0.42 - sgn * lx * h0 * 0.86, head.y - head.ty * h0 * 0.42 - sgn * ly * h0 * 0.86];
    // polygon order runs R (reversed) -> head -> L: R is the -normal edge
    capH = sgn > 0 ? [round, corner, corner] : [corner, corner, round];
  } else {
    capH = [[head.x - head.tx * h0 * 0.75 + head.ty * h0 * 0.5, head.y - head.ty * h0 * 0.75 - head.tx * h0 * 0.5],
      [head.x - head.tx * h0 * 0.95 - head.ty * h0 * 0.25, head.y - head.ty * h0 * 0.95 + head.tx * h0 * 0.25]];
  }
  const capT = [[tail.x + tail.tx * h1 * (0.9 + rng() * 0.8) - tail.ty * h1 * 0.3, tail.y + tail.ty * h1 * (0.9 + rng() * 0.8) + tail.tx * h1 * 0.3]];
  const poly = [...L, ...capT, ...R.reverse(), ...capH];
  let d = smoothClosed(poly);

  // dry-brush: slivers of bare paper along the stroke, gathering toward the tail
  if (dry > 0) {
    const count = streaks || Math.round(2 + dry * 5);
    for (let c = 0; c < count; c++) {
      const u = rng.range(-0.78, 0.78);
      const t0 = rng.range(0.28, 0.78), t1 = Math.min(0.97, t0 + rng.range(0.2, 0.62));
      const th = (rng.range(0.07, 0.2) * dry + 0.05) * streakW;
      const up = [], dn = [];
      const steps = 7;
      for (let q = 0; q <= steps; q++) {
        const t = t0 + ((t1 - t0) * q) / steps;
        const s = S[Math.min(N, Math.round(t * N))];
        const half = 0.5 * w * profileAt(profile, s.t);
        const env = Math.sin((q / steps) * Math.PI) ** 0.6;           // sliver tapers at both ends
        const off = u * half * 0.92, tk = Math.max(0.12, th * half * env);
        up.push([s.x - s.ty * (off + tk), s.y + s.tx * (off + tk)]);
        dn.push([s.x - s.ty * (off - tk), s.y + s.tx * (off - tk)]);
      }
      d += smoothClosed([...dn, ...up.reverse()]);                           // wound against the body: a hole
    }
  }
  // flecks off the tail
  for (let c = 0; c < spray; c++) {
    const dist = h1 * 2 + w * rng.range(0.4, 2.4), side = rng.range(-1, 1) * w * 0.55, rr = w * rng.range(0.04, 0.13);
    const x = tail.x + tail.tx * dist - tail.ty * side, y = tail.y + tail.ty * dist + tail.tx * side;
    d += `M${r1(x - rr * 1.6)} ${r1(y)}Q${r1(x)} ${r1(y - rr)} ${r1(x + rr * 1.6)} ${r1(y)}Q${r1(x)} ${r1(y + rr)} ${r1(x - rr * 1.6)} ${r1(y)}Z`;
  }
  return d;
}

/**
 * Dry-brush divider: one long pulled stroke with a thinner companion. Stretches to its box (width 100 %).
 * @param {{ seed?: number, flip?: boolean, cls?: string }} [o]
 */
export function divider({ seed = 3, flip = false, cls = '' } = {}) {
  const a = strokePath([[4, 9], [150, 7.2], [330, 8.6], [596, 7.4]], { w: 7, profile: PROFILE.pull, rough: 0.9, dry: 0.9, seed, spray: 3 });
  const b = strokePath([[60, 14.5], [240, 14], [470, 14.8]], { w: 1.6, profile: PROFILE.hair, rough: 0.6, seed: seed + 5 });
  return `<svg class="brush-div ${cls}" viewBox="0 0 600 18" preserveAspectRatio="none" aria-hidden="true"${flip ? ' style="transform:scaleX(-1)"' : ''}><path d="${a}${b}" fill="currentColor"/></svg>`;
}

/**
 * A short accent stroke (under a heading, beside a focused menu row): viewBox 120 x 16, stretches to its box.
 */
export function dash({ seed = 5, cls = '' } = {}) {
  const a = strokePath([[3, 8], [40, 6.6], [116, 8.4]], { w: 9, profile: PROFILE.pull, rough: 0.9, dry: 0.7, seed, spray: 2 });
  return `<svg class="brush-dash ${cls}" viewBox="0 0 120 16" preserveAspectRatio="none" aria-hidden="true"><path d="${a}" fill="currentColor"/></svg>`;
}

/**
 * A wide swath (a loaded brush dragged across): the body of announcer bands, bars and cartouches. viewBox 400 x 100,
 * stretches to its box.
 * @param {{ seed?: number, dry?: number, cls?: string }} [o]
 */
export function swath({ seed = 9, dry = 0.8, cls = '' } = {}) {
  const a = strokePath([[6, 52], [110, 47], [250, 53], [394, 48]], { w: 92, profile: [[0, 0.72], [0.05, 1], [0.5, 0.96], [0.86, 0.9], [1, 0.52]], rough: 0.55, dry, seed, spray: 4, streaks: 16, streakW: 0.22 });
  return `<svg class="brush-swath ${cls}" viewBox="0 0 400 100" preserveAspectRatio="none" aria-hidden="true"><path d="${a}" fill="currentColor"/></svg>`;
}

/**
 * CSS clip-path polygon for a brushed band: wavering long edges, a blunt, frayed or tapering end on each side.
 * Percent units, so it follows the element. `flip` mirrors it left-right.
 * @param {{ seed?: number, n?: number, amp?: number, left?: string, right?: string, flip?: boolean }} [o]
 *   amp: edge waver in % of the height; left / right: 'blunt' | 'fray' | 'taper'
 */
export function bandClip({ seed = 1, n = 14, amp = 9, left = 'blunt', right = 'fray', flip = false } = {}) {
  const rng = makeRng(seed * 131 + 7);
  const nz = noise1(seed + 40);
  const top = [], bot = [];
  const end = (kind, x0, dir) => {
    // points from the top edge to the bottom edge around one end; dir = -1 left end, +1 right end
    const pts = [];
    if (kind === 'fray') {
      const teeth = 4 + Math.floor(rng() * 2);
      for (let i = 0; i <= teeth * 2; i++) {
        const y = 6 + (88 * i) / (teeth * 2);
        const depth = i % 2 ? rng.range(1.2, 4.6) : rng.range(0, 0.9);
        pts.push([x0 - dir * depth, y + rng.range(-2, 2)]);
      }
    } else if (kind === 'taper') {
      pts.push([x0 - dir * 3.2, 22], [x0, 46 + rng.range(-6, 6)], [x0 - dir * 2.6, 74]);
    } else {
      pts.push([x0 - dir * 0.5, 14], [x0, 38 + rng.range(-5, 5)], [x0 - dir * 0.2, 64], [x0 - dir * 0.9, 88]);
    }
    return pts;
  };
  for (let i = 0; i <= n; i++) {
    const x = 2 + (96 * i) / n;
    top.push([x, amp * (0.5 + 0.5 * nz(i * 0.83))]);
    bot.push([x, 100 - amp * (0.5 + 0.5 * nz(i * 0.71 + 20))]);
  }
  const pts = [...top, ...end(right, 100, 1), ...bot.reverse(), ...end(left, 0, -1).reverse()];
  return 'polygon(' + pts.map(([x, y]) => `${r1(flip ? 100 - x : x)}% ${r1(clamp(y, 0, 100))}%`).join(',') + ')';
}

// ---------------------------------------------------------------------------------------------------------------
// seals (낙관)

/**
 * A carved seal: cinnabar block with pale reserve characters (1 to 4 of them: two or three stack, four read right
 * column first),
 * worn at the edges. Characters use the serif stack (class `seal-t`).
 * @param {string} chars
 * @param {{ seed?: number, cls?: string, relief?: boolean }} [o] relief: red characters and frame on bare ground
 */
export function seal(chars, { seed = 11, cls = '', relief = false } = {}) {
  const ch = Array.from(String(chars));
  const n = ch.length;
  const W = 100, H = n === 2 ? 178 : n === 3 ? 256 : 100;
  const rng = makeRng(seed * 977 + n);
  const id = 'sl' + uid++;
  // block outline: rounded rectangle with a wavering edge
  const pts = [];
  const rad = 9, step = 9;
  const edge = (x0, y0, x1, y1) => {
    const len = Math.hypot(x1 - x0, y1 - y0), k = Math.max(2, Math.round(len / step));
    for (let i = 0; i < k; i++) { const t = i / k; pts.push([x0 + (x1 - x0) * t + rng.range(-1.1, 1.1), y0 + (y1 - y0) * t + rng.range(-1.1, 1.1)]); }
  };
  edge(rad, 2, W - rad, 2); edge(W - 2, rad, W - 2, H - rad); edge(W - rad, H - 2, rad, H - 2); edge(2, H - rad, 2, rad);
  const block = smoothClosed(pts);
  // wear: chips along the edge and specks inside
  let wear = '';
  for (let i = 0; i < 16; i++) {
    const onEdge = i < 7;
    const x = onEdge ? (rng() < 0.5 ? rng.range(0, 6) : rng.range(W - 6, W)) : rng.range(8, W - 8);
    const y = onEdge && rng() < 0.5 ? rng.range(0, H) : onEdge ? (rng() < 0.5 ? rng.range(0, 6) : rng.range(H - 6, H)) : rng.range(8, H - 8);
    wear += `<ellipse cx="${r1(x)}" cy="${r1(y)}" rx="${r1(rng.range(0.6, onEdge ? 3.2 : 1.6))}" ry="${r1(rng.range(0.5, onEdge ? 2.4 : 1.2))}" transform="rotate(${Math.round(rng.range(0, 180))} ${r1(x)} ${r1(y)})"/>`;
  }
  wear += `<path d="M${r1(rng.range(10, 40))} ${r1(rng.range(6, H - 6))}l${r1(rng.range(20, 46))} ${r1(rng.range(-9, 9))}" stroke="#000" stroke-opacity=".5" stroke-width=".6" fill="none"/>`;
  let glyphs = '';
  const put = (c, x, y, size) => { glyphs += `<text class="seal-t" x="${x}" y="${y}" font-size="${size}" text-anchor="middle" dominant-baseline="central">${c}</text>`; };
  if (n === 1) put(ch[0], 50, 52, 70);
  else if (n === 2) { put(ch[0], 50, 50, 68); put(ch[1], 50, 130, 68); }
  else if (n === 3) { put(ch[0], 50, 49, 68); put(ch[1], 50, 129, 68); put(ch[2], 50, 209, 68); }
  else { put(ch[0], 73, 28, 40); put(ch[1], 73, 74, 40); put(ch[2], 27, 28, 40); put(ch[3] || '', 27, 74, 40); }
  const body = relief
    ? `<path d="${block}" fill="none" stroke="currentColor" stroke-width="5"/><g fill="currentColor">${glyphs}</g>`
    : `<path d="${block}" fill="currentColor"/><rect x="7.5" y="7.5" width="${W - 15}" height="${H - 15}" rx="4" fill="none" stroke="var(--seal-paper,#f3e7cd)" stroke-opacity=".55" stroke-width="1.4"/><g fill="var(--seal-paper,#f3e7cd)">${glyphs}</g>`;
  return `<svg class="seal ${cls}" viewBox="0 0 ${W} ${H}" aria-hidden="true"><defs><mask id="${id}"><rect width="${W}" height="${H}" fill="#fff"/><g fill="#000">${wear}</g></mask></defs><g mask="url(#${id})">${body}</g></svg>`;
}

// ---------------------------------------------------------------------------------------------------------------
// the ink eclipse (logo mark, emblem behind cards): black sun, pale corona wash, a brushed ring and the bead

/**
 * @param {{ cls?: string, seed?: number, streamers?: boolean }} [o]
 */
export function inkEclipse({ cls = '', seed = 4, streamers = true } = {}) {
  const id = 'ie' + uid++;
  const rng = makeRng(seed * 31 + 5);
  // corona streamers: long soft plumes, longer along one axis like the real corona
  let plumes = '';
  if (streamers) {
    const n = 17;
    for (let i = 0; i < n; i++) {
      const a = (i / n) * Math.PI * 2 + rng.range(-0.16, 0.16);
      const axis = Math.abs(Math.cos(a - 0.5)) ** 3;                         // longer near the tilted equator
      const len = 9 + 31 * axis * rng.range(0.55, 1.1) + rng.range(0, 9);
      const half = rng.range(0.05, 0.13);
      const r0 = 57, r1e = r0 + len;
      const x = (r, an) => r1(100 + Math.cos(an) * r), y = (r, an) => r1(100 + Math.sin(an) * r);
      plumes += `<path d="M${x(r0, a - half)} ${y(r0, a - half)}Q${x(r0 + len * 0.5, a - half * 0.5)} ${y(r0 + len * 0.5, a - half * 0.5)} ${x(r1e, a + rng.range(-0.03, 0.03))} ${y(r1e, a)}Q${x(r0 + len * 0.5, a + half * 0.5)} ${y(r0 + len * 0.5, a + half * 0.5)} ${x(r0, a + half)} ${y(r0, a + half)}Z" opacity="${r2(0.1 + 0.26 * axis * rng.range(0.4, 1))}"/>`;
    }
  }
  // the ring: one loaded brush turn (enso), heavy where it starts at the upper right, drying out as it comes round
  const ringPts = [];
  for (let i = 0; i <= 22; i++) { const a = -0.82 + (i / 22) * Math.PI * 1.9; ringPts.push([100 + Math.cos(a) * 59.2, 100 + Math.sin(a) * 59.2]); }
  const ring = strokePath(ringPts, { w: 6.4, profile: PROFILE.ring, rough: 0.8, dry: 0.75, seed: seed + 2, spray: 3 });
  const arcPts = [];
  for (let i = 0; i <= 10; i++) { const a = 2.2 + (i / 10) * 1.5; arcPts.push([100 + Math.cos(a) * 66.5, 100 + Math.sin(a) * 66.5]); }
  const arc = strokePath(arcPts, { w: 1.5, profile: PROFILE.hair, rough: 0.7, seed: seed + 3 });
  return `<svg class="ink-eclipse ${cls}" viewBox="0 0 200 200" aria-hidden="true">
    <defs>
      <radialGradient id="${id}c" cx="50%" cy="50%" r="50%"><stop offset=".53" stop-color="#fff3d2" stop-opacity="0"/><stop offset=".575" stop-color="#fff6de" stop-opacity=".8"/><stop offset=".66" stop-color="#f1d9a2" stop-opacity=".3"/><stop offset=".82" stop-color="#d8b46a" stop-opacity=".08"/><stop offset="1" stop-color="#d8b46a" stop-opacity="0"/></radialGradient>
      <radialGradient id="${id}p" cx="50%" cy="50%" r="50%"><stop offset=".56" stop-color="#fff6de" stop-opacity=".95"/><stop offset=".78" stop-color="#f1d9a2" stop-opacity=".35"/><stop offset="1" stop-color="#e8c888" stop-opacity="0"/></radialGradient>
      <radialGradient id="${id}b" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="#fff" stop-opacity="1"/><stop offset=".22" stop-color="#fff8e4" stop-opacity=".92"/><stop offset="1" stop-color="#f3dca0" stop-opacity="0"/></radialGradient>
    </defs>
    <circle cx="100" cy="100" r="100" fill="url(#${id}c)"/>
    <g fill="url(#${id}p)">${plumes}</g>
    <path d="${ring}${arc}" fill="#fff4d8"/>
    <circle cx="100" cy="100" r="56.5" fill="#040406"/>
    <circle cx="100" cy="100" r="51" fill="none" stroke="#fff" stroke-opacity=".05" stroke-width=".7"/>
    <circle cx="141" cy="57.5" r="15" fill="url(#${id}b)"/>
  </svg>`;
}

// ---------------------------------------------------------------------------------------------------------------
// ink-wash mountains (수묵 산수): ridges that rise out of mist, pale and far to black and near

/**
 * @param {{ seed?: number, cls?: string }} [o]
 * @returns {string} SVG (viewBox 1600 x 420; scale it with preserveAspectRatio xMidYMax slice from CSS)
 */
export function mountains({ seed = 8, cls = '' } = {}) {
  const id = 'mt' + uid++;
  const W = 1600, H = 420;
  // far -> near: [base y, amplitude, frequency, ink colour, opacity at the ridge, where the wash dies out]
  const layers = [
    [250, 150, 0.9, '#8f97ad', 0.2, 0.62],
    [292, 170, 1.25, '#59607a', 0.34, 0.66],
    [332, 150, 1.7, '#23262f', 0.74, 0.8],
    [378, 110, 2.3, '#060608', 0.98, 1],
  ];
  let defs = '', body = '';
  layers.forEach(([base, amp, freq, col, op, fade], i) => {
    const nz = noise1(seed * 17 + i * 5), nz2 = noise1(seed * 17 + i * 5 + 1);
    let d = `M0 ${H}`;
    for (let x = 0; x <= W; x += 10) {
      const u = (x / W) * 6 * freq + i * 3.3;
      const ridge = 1 - Math.abs(nz(u));                                    // sharp crests
      const crag = 1 - Math.abs(nz2(u * 3.1 + 9));
      const tall = ridge ** 2.6;                                             // a few steep spires, long saddles
      const y = base - amp * (0.72 * tall + 0.2 * crag * (0.4 + tall) + 0.08 * nz2(u * 9));
      d += `L${x} ${r1(y)}`;
    }
    d += `L${W} ${H}Z`;
    defs += `<linearGradient id="${id}g${i}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${col}" stop-opacity="${op}"/><stop offset="${r2(fade * 0.55)}" stop-color="${col}" stop-opacity="${r2(op * (i === 3 ? 1 : 0.5))}"/><stop offset="${fade}" stop-color="${col}" stop-opacity="${i === 3 ? 1 : 0}"/></linearGradient>`;
    body += `<path d="${d}" fill="url(#${id}g${i})"/>`;
  });
  return `<svg class="ink-mountains ${cls}" viewBox="0 0 ${W} ${H}" preserveAspectRatio="xMidYMax slice" aria-hidden="true"><defs>${defs}</defs>${body}</svg>`;
}

// ---------------------------------------------------------------------------------------------------------------
// ink splash (impact behind announcer marks)

/**
 * A thrown blot: an irregular body with spikes and droplets flung toward +x. viewBox 400 x 240.
 * @param {{ seed?: number, cls?: string }} [o]
 */
export function splash({ seed = 21, cls = '' } = {}) {
  const rng = makeRng(seed * 53 + 1);
  const nz = noise1(seed + 70);
  const pts = [];
  const n = 46;
  for (let i = 0; i < n; i++) {
    const a = (i / n) * Math.PI * 2;
    const spike = rng() < 0.2 ? rng.range(0.25, 0.75) : 0;
    const dirBias = 0.5 + 0.5 * Math.cos(a);                                 // longer toward +x
    const rad = 1 + 0.2 * nz(i * 0.7) + spike * (0.4 + 0.8 * dirBias);
    pts.push([200 + Math.cos(a) * 118 * rad, 120 + Math.sin(a) * 62 * rad]);
  }
  let d = smoothClosed(pts);
  for (let i = 0; i < 26; i++) {
    const a = rng.range(-0.6, 0.6) + (rng() < 0.25 ? Math.PI : 0);
    const dist = rng.range(150, 198), rr = rng.range(1.2, 7) * (1 - (dist - 150) / 90);
    const x = 200 + Math.cos(a) * dist, y = 120 + Math.sin(a) * dist * 0.56;
    d += `M${r1(x - rr * 1.5)} ${r1(y)}Q${r1(x)} ${r1(y - rr)} ${r1(x + rr * 1.5)} ${r1(y)}Q${r1(x)} ${r1(y + rr)} ${r1(x - rr * 1.5)} ${r1(y)}Z`;
  }
  return `<svg class="ink-splash ${cls}" viewBox="0 0 400 240" preserveAspectRatio="none" aria-hidden="true"><path d="${d}" fill="currentColor"/></svg>`;
}

// ---------------------------------------------------------------------------------------------------------------
// textures (canvas -> data URL), generated once

function canvasURL(size, paint) {
  try {
    const c = document.createElement('canvas');
    c.width = c.height = size;
    const g = c.getContext('2d');
    const img = g.createImageData(size, size);
    paint(img.data, size);
    g.putImageData(img, 0, 0);
    return `url(${c.toDataURL('image/png')})`;
  } catch (e) { return 'none'; }
}

/** Fine paper grain (tiles). */
export function paperTexture() {
  return canvasURL(128, (px, n) => {
    const rng = makeRng(77);
    const fib = noise2(5);
    for (let y = 0; y < n; y++) {
      for (let x = 0; x < n; x++) {
        const i = (y * n + x) * 4;
        const fibre = fib(x * 0.07, y * 0.9) * 0.5 + fib(x * 0.9, y * 0.05) * 0.5;      // crossed paper fibres
        const v = 128 + (rng() - 0.5) * 200 + (fibre - 0.5) * 120;
        px[i] = px[i + 1] = px[i + 2] = v;
        px[i + 3] = 7 + rng() * 13;
      }
    }
  });
}

/** Smooth value noise on a P x P lattice that wraps: u, v in 0..1 cover one tile. */
function tileNoise(seed, P) {
  const rng = makeRng(seed);
  const tab = new Float32Array(P * P);
  for (let i = 0; i < tab.length; i++) tab[i] = rng();
  return (u, v) => {
    const x = u * P, y = v * P;
    const ix = Math.floor(x) % P, iy = Math.floor(y) % P;
    const fx = x - Math.floor(x), fy = y - Math.floor(y);
    const ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy);
    const x1 = (ix + 1) % P, y1 = (iy + 1) % P;
    const a = tab[ix + iy * P], b = tab[x1 + iy * P], c = tab[ix + y1 * P], d = tab[x1 + y1 * P];
    return a + (b - a) * ux + (c - a + (a - b - c + d) * ux) * uy;
  };
}

/** Blotchy ink wash (tiles at 256): soft clouds of thin black ink with darker tide lines. */
export function washTexture() {
  return canvasURL(256, (px, n) => {
    const a = tileNoise(31, 4), b = tileNoise(32, 9), c = tileNoise(33, 23);
    for (let y = 0; y < n; y++) {
      for (let x = 0; x < n; x++) {
        const i = (y * n + x) * 4;
        const u = x / n, v = y / n;
        const f = 0.55 * a(u, v) + 0.3 * b(u, v) + 0.15 * c(u, v);
        const pool = smoothstep(0.4, 0.6, f);
        const tide = 1 - Math.min(1, Math.abs(f - 0.5) * 22);                  // the darker rim where a wash dried
        px[i] = px[i + 1] = px[i + 2] = 0;
        px[i + 3] = 120 * pool * (0.5 + 0.5 * f) + 46 * tide;
      }
    }
  });
}

// ---------------------------------------------------------------------------------------------------------------
// brush shapes as CSS images (mask-image / background-image)

/** An SVG string as a CSS url() value. `color` replaces currentColor (masks only need the shape). */
export function cssUrl(svg, color = '#000') {
  const body = svg.replace(/currentColor/g, color).replace('<svg ', '<svg xmlns="http://www.w3.org/2000/svg" ');
  return `url("data:image/svg+xml,${encodeURIComponent(body)}")`;
}
