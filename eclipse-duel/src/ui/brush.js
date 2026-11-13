// Brush-written Hangul (판본체 붓글씨): every syllable is composed from jamo templates and written stroke by stroke
// with ink.strokePath (pressure, slanted brush landings, dry-brush tails). The title 「흑일무림」, announcer marks,
// hero names and technique banners are drawn with it, so display type never depends on an installed font. Digits,
// "!" and "·" have stroke templates too; any other character (Hanja, Latin) falls back to serif glyphs.
//
//   el.innerHTML = brushText('겨뤄라!');                  // inline SVG, 1 cell = 100 units, fill = currentColor
//   el.innerHTML = brushText('흑일분천', { vertical: true });
//
// Output is static SVG text, cached per string + options; size it from CSS (height, width follows the viewBox).

import { strokePath, PROFILE, FONT_KO } from './ink.js';

const VERT = [0, 1, 2, 3, 4, 5, 6, 7, 20];            // ㅏ ㅐ ㅑ ㅒ ㅓ ㅔ ㅕ ㅖ ㅣ
const HORZ = [8, 12, 13, 17, 18];                     // ㅗ ㅛ ㅜ ㅠ ㅡ
// mixed vowels: [horizontal part, vertical part]
const MIXED = { 9: [8, 0], 10: [8, 1], 11: [8, 20], 14: [13, 4], 15: [13, 5], 16: [13, 20], 19: [18, 20] };
const LEAD = ['ㄱ', 'ㄲ', 'ㄴ', 'ㄷ', 'ㄸ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅃ', 'ㅅ', 'ㅆ', 'ㅇ', 'ㅈ', 'ㅉ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ'];
const TAIL = ['', 'ㄱ', 'ㄲ', 'ㄱㅅ', 'ㄴ', 'ㄴㅈ', 'ㄴㅎ', 'ㄷ', 'ㄹ', 'ㄹㄱ', 'ㄹㅁ', 'ㄹㅂ', 'ㄹㅅ', 'ㄹㅌ', 'ㄹㅍ', 'ㄹㅎ', 'ㅁ', 'ㅂ', 'ㅂㅅ', 'ㅅ', 'ㅆ', 'ㅇ', 'ㅈ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ'];
const DOUBLE = { 'ㄲ': 'ㄱㄱ', 'ㄸ': 'ㄷㄷ', 'ㅃ': 'ㅂㅂ', 'ㅆ': 'ㅅㅅ', 'ㅉ': 'ㅈㅈ' };

const NEEDLE = [[0, 0.85], [0.08, 1.14], [0.6, 0.92], [1, 0.4]];
const FOOT = [[0, 0.5], [0.3, 0.92], [0.85, 1], [1, 0.72]];

// ---------------------------------------------------------------------------------------------------------------
// stroke primitives (cell coordinates, y down). Horizontals rise a little to the right, as a right hand writes them.

const RISE = 0.055;
function hb(S, x0, y, x1, w, o) {
  const r = (x1 - x0) * RISE;
  S.push({ p: [[x0, y + r * 0.5], [(x0 + x1) / 2, y - 0.5], [x1, y - r * 0.5]], w, profile: PROFILE.bone, ...o });
}
function vb(S, x, y0, y1, w, o) {
  S.push({ p: [[x, y0], [x + 0.45, (y0 + y1) / 2], [x - 0.3, y1]], w, profile: PROFILE.post, ...o });
}
function dg(S, x0, y0, x1, y1, w, o = {}) {
  const bend = o.bend || 0;
  const mx = (x0 + x1) / 2 - (y1 - y0) * bend, my = (y0 + y1) / 2 + (x1 - x0) * bend;
  S.push({ p: [[x0, y0], [mx, my], [x1, y1]], w, profile: PROFILE.drop, ...o });
}
function ring(S, cx, cy, rx, ry, w, o) {
  const p = [];
  for (let i = 0; i <= 14; i++) { const a = -2.2 - (i / 14) * Math.PI * 1.97; p.push([cx + Math.cos(a) * rx, cy + Math.sin(a) * ry]); }
  S.push({ p, w, profile: [[0, 0.7], [0.1, 1.1], [0.5, 0.82], [0.85, 1], [1, 0.6]], head: 'round', ...o });
}
function dot(S, x0, y0, x1, y1, w) {
  S.push({ p: [[x0, y0], [(x0 + x1) / 2 + 0.6, (y0 + y1) / 2 + 0.4], [x1, y1]], w, profile: PROFILE.dot, head: 'round' });
}

// ---------------------------------------------------------------------------------------------------------------
// consonants in a rectangle (x0, y0) .. (x1, y1). `pos`: 'side' (left of a vertical vowel) | 'top' | 'tail'

const J = {
  'ㄱ'(S, x0, y0, x1, y1, w, pos) {
    hb(S, x0, y0 + w * 0.5, x1, w);
    if (pos === 'side') dg(S, x1 - w * 0.4, y0 + w * 0.2, x1 - (x1 - x0) * 0.3, y1, w * 1.05, { bend: -0.05 });
    else vb(S, x1 - w * 0.45, y0 + w * 0.2, y1, w * 1.05, { profile: PROFILE.drop });
  },
  'ㄴ'(S, x0, y0, x1, y1, w) {
    vb(S, x0 + w * 0.45, y0, y1 - w * 0.3, w, { profile: PROFILE.flat });
    hb(S, x0, y1 - w * 0.5, x1 + 2, w, { profile: PROFILE.pull, dry: 0.3 });
  },
  'ㄷ'(S, x0, y0, x1, y1, w) {
    hb(S, x0, y0 + w * 0.5, x1 - 1, w);
    vb(S, x0 + w * 0.5, y0 + w * 0.3, y1 - w * 0.3, w, { profile: PROFILE.flat });
    hb(S, x0, y1 - w * 0.5, x1 + 2, w, { profile: PROFILE.pull });
  },
  'ㄹ'(S, x0, y0, x1, y1, w) {
    const ym = (y0 + y1) / 2, q = w * 0.9;
    hb(S, x0, y0 + q * 0.5, x1, q);
    vb(S, x1 - q * 0.45, y0 + q * 0.2, ym + q * 0.2, q * 0.95, { profile: PROFILE.flat });
    hb(S, x0 + 1, ym, x1, q * 0.92);
    vb(S, x0 + q * 0.5, ym - q * 0.1, y1 - q * 0.3, q * 0.95, { profile: PROFILE.flat });
    hb(S, x0, y1 - q * 0.5, x1 + 4, q * 1.08, { profile: PROFILE.pull, dry: 0.4, spray: 2 });
  },
  'ㅁ'(S, x0, y0, x1, y1, w) {
    vb(S, x0 + w * 0.45, y0, y1, w);
    hb(S, x0 - 0.5, y0 + w * 0.55, x1, w * 0.96);
    vb(S, x1 - w * 0.45, y0 - 0.5, y1, w * 1.05);
    hb(S, x0, y1 - w * 0.5, x1 + 2, w * 0.98);
  },
  'ㅂ'(S, x0, y0, x1, y1, w) {
    vb(S, x0 + w * 0.45, y0 - 1, y1, w);
    vb(S, x1 - w * 0.45, y0 - 2, y1, w * 1.04);
    hb(S, x0 + w * 0.4, y0 + (y1 - y0) * 0.46, x1 - w * 0.4, w * 0.85);
    hb(S, x0, y1 - w * 0.5, x1 + 2, w * 0.98);
  },
  'ㅅ'(S, x0, y0, x1, y1, w) {
    const xm = (x0 + x1) / 2, H = y1 - y0;
    dg(S, xm + (x1 - x0) * 0.05, y0, x0, y1, w * 1.06, { bend: -0.1 });
    dg(S, xm - (x1 - x0) * 0.04, y0 + H * 0.34, x1, y1 - 1, w, { bend: 0.1, profile: FOOT, head: 'round' });
  },
  'ㅇ'(S, x0, y0, x1, y1, w) {
    ring(S, (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2 - w * 0.4, (y1 - y0) / 2 - w * 0.4, w * 0.9);
  },
  'ㅈ'(S, x0, y0, x1, y1, w) {
    const xm = (x0 + x1) / 2, H = y1 - y0;
    hb(S, x0 + 1, y0 + w * 0.5, x1 - 1, w);
    dg(S, xm + (x1 - x0) * 0.06, y0 + w * 0.5, x0, y1, w * 1.04, { bend: -0.1 });
    dg(S, xm - (x1 - x0) * 0.03, y0 + H * 0.42, x1, y1 - 1, w, { bend: 0.1, profile: FOOT, head: 'round' });
  },
  'ㅊ'(S, x0, y0, x1, y1, w) {
    const xm = (x0 + x1) / 2, H = y1 - y0;
    dot(S, xm - (x1 - x0) * 0.16, y0 - H * 0.02, xm + (x1 - x0) * 0.12, y0 + H * 0.1, w);
    J['ㅈ'](S, x0, y0 + H * 0.24, x1, y1, w);
  },
  'ㅋ'(S, x0, y0, x1, y1, w, pos) {
    J['ㄱ'](S, x0, y0, x1, y1, w, pos);
    hb(S, x0 + 1, (y0 + y1) / 2, x1 - w * 0.7, w * 0.85);
  },
  'ㅌ'(S, x0, y0, x1, y1, w) {
    J['ㄷ'](S, x0, y0, x1, y1, w);
    hb(S, x0 + w * 0.4, (y0 + y1) / 2, x1 - (x1 - x0) * 0.06, w * 0.85);
  },
  'ㅍ'(S, x0, y0, x1, y1, w) {
    const W = x1 - x0;
    hb(S, x0, y0 + w * 0.5, x1, w);
    vb(S, x0 + W * 0.3, y0 + w * 0.5, y1 - w * 0.4, w * 0.9, { profile: PROFILE.flat });
    vb(S, x0 + W * 0.7, y0 + w * 0.4, y1 - w * 0.4, w * 0.9, { profile: PROFILE.flat });
    hb(S, x0 - 1, y1 - w * 0.5, x1 + 3, w * 1.02, { profile: PROFILE.pull });
  },
  'ㅎ'(S, x0, y0, x1, y1, w) {
    const xm = (x0 + x1) / 2, W = x1 - x0, H = y1 - y0;
    dot(S, xm - W * 0.16, y0 - H * 0.03, xm + W * 0.14, y0 + H * 0.1, w * 1.02);
    hb(S, x0, y0 + H * 0.3, x1, w * 0.95);
    const ry = H * 0.25;
    ring(S, xm, y1 - ry - w * 0.1, Math.min(W * 0.27, ry * 1.25), ry, w * 0.8);
  },
};

/** Write one or two consonants (doubles, final clusters) into a rectangle. */
function consonants(S, jamo, x0, y0, x1, y1, w, pos) {
  const list = Array.from(DOUBLE[jamo] || jamo);
  if (list.length === 1) { J[list[0]](S, x0, y0, x1, y1, w, pos); return; }
  const xm = (x0 + x1) / 2, gap = (x1 - x0) * 0.035, q = w * 0.84;
  J[list[0]](S, x0, y0, xm - gap, y1, q, pos === 'side' ? 'top' : pos);
  J[list[1]](S, xm + gap, y0, x1, y1, q, pos === 'side' ? 'top' : pos);
}

// ---------------------------------------------------------------------------------------------------------------
// vowels

/** Vertical vowel: stems and ticks. `xs` = main stem x, y0..y1 its extent, `yt` = tick height centre. */
function vowelV(S, v, xs, y0, y1, yt, w, tl) {
  const stem = (x, a, b, o) => vb(S, x, a, b, w * 1.1, { profile: NEEDLE, ...o });
  const tick = (xa, xb, y) => hb(S, xa, y, xb, w * 0.86, { profile: PROFILE.pull });
  const twin = v === 1 || v === 3 || v === 5 || v === 7;                    // ㅐ ㅒ ㅔ ㅖ
  const xa = twin ? xs - 19 : xs;
  if (twin) { stem(xa, y0 + (y1 - y0) * 0.08, y1 - (y1 - y0) * 0.08, { profile: PROFILE.post }); stem(xs, y0, y1); } else stem(xs, y0, y1);
  const two = (y1 - y0) * 0.13;
  switch (v) {
    case 0: tick(xs + w * 0.2, xs + tl, yt); break;                         // ㅏ
    case 2: tick(xs + w * 0.2, xs + tl, yt - two); tick(xs + w * 0.2, xs + tl, yt + two); break;   // ㅑ
    case 4: tick(xs - tl, xs - w * 0.2, yt); break;                         // ㅓ
    case 6: tick(xs - tl, xs - w * 0.2, yt - two); tick(xs - tl, xs - w * 0.2, yt + two); break;   // ㅕ
    case 1: tick(xa + w * 0.2, xs - w * 0.2, yt); break;                    // ㅐ
    case 3: tick(xa + w * 0.2, xs - w * 0.2, yt - two); tick(xa + w * 0.2, xs - w * 0.2, yt + two); break;   // ㅒ
    case 5: tick(xa - tl * 0.85, xa - w * 0.2, yt); break;                  // ㅔ
    case 7: tick(xa - tl * 0.85, xa - w * 0.2, yt - two); tick(xa - tl * 0.85, xa - w * 0.2, yt + two); break;   // ㅖ
    default:                                                                // ㅣ
  }
}

/** Horizontal vowel: the bar at y from xa to xb, ticks up (ㅗ ㅛ) from yUp or stems down (ㅜ ㅠ) to yDown. */
function vowelH(S, v, xa, xb, y, yUp, yDown, w) {
  const xm = (xa + xb) / 2, sp = (xb - xa) * 0.14;
  const bar = () => hb(S, xa, y, xb, w * 1.22, { profile: PROFILE.pull, dry: 0.7, spray: 3 });
  if (v === 8) { vb(S, xm, yUp, y, w * 0.95, { profile: PROFILE.flat }); bar(); }
  else if (v === 12) { vb(S, xm - sp, yUp, y, w * 0.9, { profile: PROFILE.flat }); vb(S, xm + sp, yUp, y, w * 0.9, { profile: PROFILE.flat }); bar(); }
  else if (v === 13) { bar(); vb(S, xm, y - w * 0.2, yDown, w * 1.06, { profile: PROFILE.drop }); }
  else if (v === 17) { bar(); dg(S, xm - sp, y - w * 0.2, xm - sp * 1.5, yDown - 2, w * 0.95, { bend: -0.04 }); vb(S, xm + sp, y - w * 0.2, yDown, w, { profile: PROFILE.drop }); }
  else bar();
}

// ---------------------------------------------------------------------------------------------------------------
// one syllable -> strokes in a 100 x 100 cell

function syllable(code) {
  const S = [];
  const c = code - 0xac00;
  const L = LEAD[Math.floor(c / 588)], V = Math.floor((c % 588) / 28), T = TAIL[c % 28];
  const W0 = 9.4;
  const fin = !!T;
  const wOf = (x0, y0, x1, y1) => W0 * Math.max(0.74, Math.min(1.04, 0.6 + (0.4 * Math.min(x1 - x0, y1 - y0)) / 44));
  const put = (jamo, r, pos) => consonants(S, jamo, r[0], r[1], r[2], r[3], wOf(...r), pos);
  if (VERT.includes(V)) {
    const twin = V === 1 || V === 3 || V === 5 || V === 7;
    const leftTick = V === 4 || V === 6 || V === 5 || V === 7;
    const xs = twin ? 88 : V === 20 ? 80 : leftTick ? 82 : 76;
    const x1 = twin ? (leftTick ? 44 : 52) : leftTick ? 51 : 59;
    if (!fin) {
      put(L, [7, 17, x1, 82], 'side');
      vowelV(S, V, xs, 3, 97, 50, W0, twin ? 14 : 17);
    } else {
      put(L, [9, 6, x1, 50], 'side');
      vowelV(S, V, xs, 1, 58, 29, W0, twin ? 14 : 17);
      put(T, [20, 65, 90, 96], 'tail');
    }
  } else if (HORZ.includes(V)) {
    if (!fin) {
      put(L, [21, 6, 79, V === 13 || V === 17 ? 46 : 50], 'top');
      if (V === 13 || V === 17) vowelH(S, V, 4, 96, 61, 0, 99, W0);
      else if (V === 18) vowelH(S, V, 4, 96, 74, 0, 0, W0);
      else vowelH(S, V, 4, 96, 78, 54, 0, W0);
    } else {
      put(L, [23, 3, 77, 33], 'top');
      if (V === 13 || V === 17) { vowelH(S, V, 5, 95, 43, 0, 61, W0 * 0.94); put(T, [22, 66, 80, 97], 'tail'); }
      else if (V === 18) { vowelH(S, V, 5, 95, 47, 0, 0, W0 * 0.94); put(T, [22, 62, 80, 96], 'tail'); }
      else { vowelH(S, V, 5, 95, 52, 37, 0, W0 * 0.94); put(T, [22, 65, 80, 97], 'tail'); }
    }
  } else {
    const [hv, vv] = MIXED[V];
    const twin = vv === 1 || vv === 5;
    const xs = twin ? 90 : 81;
    const xr = twin ? 58 : 66;                                               // right end of the horizontal part
    if (!fin) {
      put(L, [7, 8, twin ? 50 : 57, 47], 'top');
      if (hv === 8) vowelH(S, hv, 3, xr, 69, 51, 0, W0 * 0.92);
      else if (hv === 13) vowelH(S, hv, 3, xr, 59, 0, 93, W0 * 0.92);
      else vowelH(S, hv, 3, xr, 72, 0, 0, W0 * 0.92);
      vowelV(S, vv, xs, 3, 97, hv === 13 ? 77 : 46, W0, 13);
    } else {
      put(L, [9, 3, twin ? 50 : 56, 30], 'top');
      if (hv === 8) vowelH(S, hv, 5, xr, 45, 32, 0, W0 * 0.88);
      else if (hv === 13) vowelH(S, hv, 5, xr, 40, 0, 58, W0 * 0.88);
      else vowelH(S, hv, 5, xr, 46, 0, 0, W0 * 0.88);
      vowelV(S, vv, xs, 1, 59, hv === 13 ? 51 : 28, W0, 12);
      put(T, [20, 66, 90, 97], 'tail');
    }
  }
  return S;
}

// digits and marks: [advance, strokes(S)]
const curve = (S, p, w, o) => S.push({ p, w, profile: PROFILE.bone, ...o });
const GLYPH = {
  '1': [50, (S) => { dg(S, 13, 24, 28, 9, 7, { profile: PROFILE.hair, head: 'round' }); vb(S, 28, 7, 95, 11, { profile: NEEDLE }); }],
  '2': [66, (S) => { curve(S, [[12, 28], [24, 10], [46, 9], [54, 28], [40, 52], [12, 88]], 9.6, { profile: PROFILE.post }); hb(S, 10, 89, 60, 10.5, { profile: PROFILE.pull, dry: 0.5, spray: 2 }); }],
  '3': [64, (S) => { curve(S, [[11, 17], [32, 7], [52, 19], [40, 43], [26, 47]], 9.4); curve(S, [[27, 47], [52, 56], [54, 80], [34, 94], [9, 84]], 9.8, { profile: PROFILE.pull }); }],
  '4': [70, (S) => { dg(S, 44, 6, 7, 66, 9, { bend: 0.03, profile: PROFILE.post }); hb(S, 5, 67, 66, 9.6, { profile: PROFILE.pull }); vb(S, 46, 6, 96, 11, { profile: NEEDLE }); }],
  '5': [64, (S) => { hb(S, 16, 12, 56, 9.6); vb(S, 17, 12, 47, 9, { profile: PROFILE.flat }); curve(S, [[16, 47], [38, 39], [56, 55], [51, 82], [30, 94], [8, 84]], 9.8, { profile: PROFILE.pull }); }],
  '6': [64, (S) => { curve(S, [[50, 10], [26, 24], [12, 56], [20, 86], [42, 92], [54, 72], [40, 54], [18, 62]], 9.4, { profile: PROFILE.post }); }],
  '7': [62, (S) => { hb(S, 8, 13, 56, 10); dg(S, 54, 12, 26, 95, 10.5, { bend: 0.06 }); }],
  '8': [64, (S) => { ring(S, 32, 29, 17, 17, 8.8); ring(S, 32, 70, 21, 21, 9.4); }],
  '9': [64, (S) => { ring(S, 31, 32, 19, 20, 9); curve(S, [[51, 30], [50, 62], [34, 90], [14, 92]], 9.6, { profile: PROFILE.pull }); }],
  '0': [66, (S) => { ring(S, 33, 51, 22, 39, 9.6); }],
  '!': [34, (S) => { vb(S, 17, 5, 68, 13, { profile: PROFILE.drop }); dot(S, 13, 84, 22, 92, 11); }],
  '·': [34, (S) => { dot(S, 11, 46, 23, 56, 12); }],
  ' ': [42, () => {}],
};

// ---------------------------------------------------------------------------------------------------------------

const cache = new Map();
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
let gradSeq = 0;

/**
 * Text written with the brush, as inline SVG markup. Each Hangul syllable takes a 100 x 100 cell.
 * @param {string} text
 * @param {{ vertical?: boolean, gap?: number, seed?: number, weight?: number, cls?: string, shadow?: boolean,
 *   fill?: string[] | string, rough?: number, title?: boolean }} [o]
 *   gap: space between cells (default 8); weight: stroke width multiplier; shadow: a dark ink copy offset under the
 *   strokes (default true); fill: 'currentColor' (default) or [top, bottom] colours for a gradient
 * @returns {string} `<svg class="brush-text" viewBox ...>` — set its height in CSS, the width follows
 */
export function brushText(text, o = {}) {
  const { vertical = false, gap = 8, seed = 0, weight = 1, cls = '', shadow = true, fill = 'currentColor', rough = 0.75 } = o;
  const key = [text, vertical ? 1 : 0, gap, seed, weight, shadow ? 1 : 0, Array.isArray(fill) ? fill.join() : fill, rough].join('|');
  let hit = cache.get(key);
  if (!hit) {
    let d = '', fallback = '';
    let pen = 0, n = 0;
    for (const ch of Array.from(String(text))) {
      const code = ch.codePointAt(0);
      const S = [];
      let adv = 100;
      if (code >= 0xac00 && code <= 0xd7a3) S.push(...syllable(code));
      else if (GLYPH[ch]) { adv = GLYPH[ch][0]; GLYPH[ch][1](S); }
      else {
        adv = code > 0x2e7f ? 100 : 62;
        const cx = vertical ? 50 : pen + adv / 2, cy = vertical ? pen + 50 : 50;
        fallback += `<text x="${cx}" y="${cy + 2}" font-size="${code > 0x2e7f ? 92 : 84}" text-anchor="middle" dominant-baseline="central">${esc(ch)}</text>`;
      }
      const ox = vertical ? (100 - adv) / 2 : pen, oy = vertical ? pen : 0;
      // a hand never repeats itself: each cell leans and breathes a little
      const lean = ((((code * 7 + n * 13 + seed * 5) % 9) - 4) / 4) * 0.9, grow = 1 + ((((code + n * 5 + seed) % 7) - 3) / 3) * 0.022;
      S.forEach((st, i) => {
        const pts = st.p.map(([x, y]) => {
          const dx = (x - adv / 2) * grow, dy = (y - 50) * grow;
          return [ox + adv / 2 + dx - dy * lean * 0.012, oy + 50 + dy + dx * lean * 0.006];
        });
        d += strokePath(pts, { w: st.w * weight * grow, profile: st.profile, rough, dry: st.dry || 0, spray: st.spray || 0, seed: code * 31 + i * 7 + n * 101 + seed, head: st.head || 'slant' });
      });
      pen += (vertical ? 100 : adv) + gap;
      n++;
    }
    pen -= gap;
    const W = vertical ? 100 : pen, H = vertical ? pen : 100;
    hit = { d, fallback, W, H };
    cache.set(key, hit);
  }
  const pad = 9;
  let defs = '', paint = 'currentColor';
  if (Array.isArray(fill)) {
    const id = 'bt' + gradSeq++;
    defs = `<defs><linearGradient id="${id}" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="0" y2="${hit.H}"><stop offset="0" stop-color="${fill[0]}"/><stop offset="1" stop-color="${fill[1]}"/></linearGradient></defs>`;
    paint = `url(#${id})`;
  }
  const fb = hit.fallback ? `<g style="font-family:${FONT_KO.replace(/"/g, '&quot;')};font-weight:800">${hit.fallback}</g>` : '';
  const under = shadow ? `<g fill="#000" fill-opacity=".8" transform="translate(2.2 3.4)"><path d="${hit.d}"/>${fb}</g>` : '';
  const vb2 = `${-pad} ${-pad} ${hit.W + pad * 2} ${hit.H + pad * 2}`;
  return `<svg class="brush-text ${cls}" viewBox="${vb2}" style="aspect-ratio:${hit.W + pad * 2}/${hit.H + pad * 2}" role="img" aria-label="${esc(text)}">${defs}${under}<g fill="${paint}"><path d="${hit.d}"/>${fb}</g></svg>`;
}
