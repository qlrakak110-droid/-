// Inline SVG icon set (strings). Every glyph is our own art on a 48x48 grid, drawn with currentColor so CSS colours
// it: action glyphs and marks are written with the brush (ink.strokePath), skill icons and sect emblems are line art.
// Weapons use a tall 60x240 grid. No external images.

import { strokePath, PROFILE, inkEclipse } from './ink.js';

/** Brush-filled body (the icon wrapper strokes by default). */
const B = (d, extra = '') => `<g fill="currentColor" stroke="none"><path d="${d}"/>${extra}</g>`;
const arc = (cx, cy, r, a0, a1, n = 12) => { const p = []; for (let i = 0; i <= n; i++) { const a = a0 + ((a1 - a0) * i) / n; p.push([cx + Math.cos(a) * r, cy + Math.sin(a) * r]); } return p; };
const SLASH = [[0, 0.3], [0.25, 1.1], [0.7, 0.85], [1, 0.12]];

const G = (body, vb = '0 0 48 48', cls = '') =>
  `<svg class="ico ${cls}" viewBox="${vb}" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${body}</svg>`;

const P = {
  // --- elements ---------------------------------------------------------------------------------------------
  ember: `<path d="M24 4c3 8 12 12 12 24a12 12 0 0 1-24 0c0-6 3-9 5-13 1 4 3 6 5 7-1-7 0-12 2-18z" fill="currentColor" fill-opacity=".14"/>
    <path d="M24 44c-4 0-7-3-7-7 0-4 3-6 4-9 1 3 3 4 4 4 0-3 1-5 3-7 2 4 3 7 3 11 0 5-3 8-7 8z" fill="currentColor" fill-opacity=".55" stroke-width="1.6"/>`,
  frost: `<path d="M24 3v42M5.8 13.5l36.4 21M5.8 34.5l36.4-21"/>
    <path d="M24 10l-4-4M24 10l4-4M24 38l-4 4M24 38l4 4M12 17l-5.5 1.5M12 17l-1.5-5.5M36 31l5.5-1.5M36 31l1.5 5.5M12 31l-1.5 5.5M12 31l-5.5-1.5M36 17l1.5-5.5M36 17l5.5 1.5" stroke-width="1.8"/>
    <path d="M24 17l6 7-6 7-6-7z" fill="currentColor" fill-opacity=".5" stroke-width="1.6"/>`,
  volt: `<circle cx="24" cy="24" r="20" stroke-width="1.4" stroke-dasharray="3 4" opacity=".6"/>
    <path d="M28 4L13 27h10l-5 17 17-24H25l3-16z" fill="currentColor" fill-opacity=".3"/>`,

  // --- generic actions (touch pad, hints): brush glyphs -----------------------------------------------------------
  // 경초: one quick flick of the brush
  light: B(strokePath([[9, 40], [21, 25], [40, 8]], { w: 6.4, profile: SLASH, rough: 0.8, dry: 0.6, spray: 2, seed: 41 })
    + strokePath([[8, 28], [16, 19], [27, 10]], { w: 2, profile: PROFILE.hair, rough: 0.6, seed: 42 })),
  // 중초: a loaded crescent sweep
  heavy: B(strokePath([[7, 41], [10, 23], [24, 10], [43, 6]], { w: 12.5, profile: [[0, 0.3], [0.3, 1.1], [0.72, 0.9], [1, 0.16]], rough: 0.8, dry: 0.8, spray: 3, seed: 43, streaks: 5, streakW: 0.7 })
    + strokePath([[24, 40], [30, 30], [41, 22]], { w: 3, profile: PROFILE.hair, rough: 0.6, seed: 44 })),
  // 호신강기: a ring of guarding energy around three formation bars (the middle one broken)
  guard: B(strokePath(arc(24, 24, 18.5, -1.2, 4.75, 18), { w: 4.6, profile: PROFILE.ring, rough: 0.8, dry: 0.5, seed: 45 })
    + strokePath([[15, 17], [33, 16.4]], { w: 3.4, profile: PROFILE.bone, seed: 46 })
    + strokePath([[15, 24.4], [21.5, 24.1]], { w: 3.4, profile: PROFILE.bone, seed: 47 }) + strokePath([[26.5, 24], [33, 23.7]], { w: 3.4, profile: PROFILE.bone, seed: 48 })
    + strokePath([[15, 31.8], [33, 31.2]], { w: 3.4, profile: PROFILE.bone, seed: 49 })),
  // 경공: the step that leaves only wind behind
  dodge: B(strokePath([[5, 15.5], [22, 14.6]], { w: 2.6, profile: PROFILE.hair, seed: 50 }) + strokePath([[9, 24.5], [27, 23.6]], { w: 3, profile: PROFILE.hair, seed: 51 })
    + strokePath([[5, 33.5], [22, 32.6]], { w: 2.6, profile: PROFILE.hair, seed: 52 })
    + strokePath([[28, 9], [36, 16], [43, 24]], { w: 5.4, profile: PROFILE.pull, rough: 0.7, seed: 53 }) + strokePath([[43, 24], [36, 32], [28, 39]], { w: 5.4, profile: PROFILE.pull, rough: 0.7, dry: 0.4, seed: 54 })),
  // 오의: the black sun
  ult: B(strokePath(arc(24, 24, 15.6, -0.9, 5.0, 18), { w: 3.6, profile: PROFILE.ring, rough: 0.8, dry: 0.5, seed: 55 })
    + [0, 1, 2, 3, 4, 5, 6, 7].map((i) => { const a = i * 0.785 + 0.2, c = Math.cos(a), sn = Math.sin(a); return strokePath([[24 + c * 19.5, 24 + sn * 19.5], [24 + c * (i % 2 ? 22.6 : 24), 24 + sn * (i % 2 ? 22.6 : 24)]], { w: 2.2, profile: PROFILE.hair, seed: 56 + i }); }).join(''),
    '<circle cx="24" cy="24" r="10.6"/>'),
  stick: `<circle cx="24" cy="24" r="19" stroke-width="1.6" opacity=".7"/><circle cx="30" cy="24" r="8" fill="currentColor" fill-opacity=".35" stroke-width="2"/><path d="M41 24h5M43 21l3 3-3 3" stroke-width="2"/>`,
  pause: B(strokePath([[17.5, 10], [17, 38]], { w: 6, profile: PROFILE.post, rough: 0.7, seed: 61, head: 'slant' }) + strokePath([[31.5, 10], [31, 38]], { w: 6, profile: PROFILE.post, rough: 0.7, seed: 62, head: 'slant' })),
  back: B(strokePath([[31, 8], [22, 16], [14, 24]], { w: 5.2, profile: PROFILE.pull, rough: 0.7, seed: 63 }) + strokePath([[14, 24], [22, 32], [31, 40]], { w: 5.2, profile: PROFILE.pull, rough: 0.7, dry: 0.4, seed: 64 })),
  // 운명: a blank lot drawn from the cylinder
  random: B(strokePath(arc(24, 24, 19, -1.35, 4.6, 18), { w: 3.4, profile: PROFILE.ring, rough: 0.8, dry: 0.5, seed: 65 })
    + strokePath([[17.5, 19], [19, 13.5], [25, 11.5], [30.5, 15], [29, 21], [24.5, 25], [24, 29.5]], { w: 4.6, profile: PROFILE.pull, rough: 0.6, seed: 66 }),
    '<circle cx="24" cy="36" r="2.4"/>'),
  list: `<path d="M17 13h22M17 24h22M17 35h22" stroke-width="2.4"/><path d="M8 13l2-2 2 2-2 2zM8 24l2-2 2 2-2 2zM8 35l2-2 2 2-2 2z" fill="currentColor" stroke-width="1.2"/>`,
  gear: `<circle cx="24" cy="24" r="6"/><path d="M24 5v6M24 37v6M5 24h6M37 24h6M10.6 10.6l4.2 4.2M33.2 33.2l4.2 4.2M10.6 37.4l4.2-4.2M33.2 14.8l4.2-4.2"/><circle cx="24" cy="24" r="13" stroke-width="1.6"/>`,
  // 산문: back to the gate
  home: `<path d="M5 17Q24 7 43 17" stroke-width="3"/><path d="M11 21h26" stroke-width="2"/><path d="M14 17v25M34 17v25" stroke-width="2.8"/><path d="M9 42h10M29 42h10" stroke-width="2"/>`,
  rematch: `<path d="M38 18A15 15 0 0 0 10.5 16M10 30a15 15 0 0 0 27.5 2" stroke-width="2.6"/><path d="M10 7v9h9M38 41v-9h-9" stroke-width="2.6"/>`,
  people: `<path d="M9 14Q17 7 25 14" stroke-width="2.2"/><path d="M6 15h22" stroke-width="2"/><circle cx="17" cy="21" r="4.4"/><path d="M6 41c1-9 5-13 11-13s10 4 11 13"/><path d="M27 18Q33 13 40 18" stroke-width="1.8" opacity=".7"/><circle cx="33.5" cy="24" r="3.6" opacity=".7"/><path d="M31 31c6 0 10 3 11 10" opacity=".7"/>`,

  // --- sect emblems (our own designs) ------------------------------------------------------------------------------
  // 적양문 赤陽門: the red sun standing in the gate
  'sect-kael': `<path d="M6 17Q24 6 42 17" stroke-width="3"/><path d="M11 22h26" stroke-width="2"/><path d="M13.5 18v24M34.5 18v24" stroke-width="3"/>
    <circle cx="24" cy="33" r="6.6" fill="currentColor" stroke="none"/><path d="M24 8V3M16.5 10l-2-4.4M31.5 10l2-4.4" stroke-width="2"/><path d="M8 42h11M29 42h11" stroke-width="2"/>`,
  // 한월궁 寒月宮: a pear blossom in the arms of the cold moon
  'sect-iska': `<path d="M29 5a19 19 0 1 0 13 30A15 15 0 1 1 29 5z" fill="currentColor" fill-opacity=".9" stroke-width="1.4"/>
    <g fill="currentColor" fill-opacity=".55" stroke-width="1.3"><circle cx="31" cy="15.2" r="3.3"/><circle cx="36.3" cy="19" r="3.3"/><circle cx="34.3" cy="25.2" r="3.3"/><circle cx="27.7" cy="25.2" r="3.3"/><circle cx="25.7" cy="19" r="3.3"/></g>
    <circle cx="31" cy="21" r="1.7" fill="currentColor" stroke="none"/><path d="M39 38l1.5 1.5M43 33l1 1M36 43l1 1" stroke-width="2"/>`,
  // 뇌운보 雷雲堡: thunder falling from a cloud scroll onto the keep
  'sect-vorn': `<path d="M9 17c-5-1-5-8 1-8 1-6 10-7 13-2 4-4 13-2 12 4 6 0 6 7 0 7" stroke-width="2.2"/><path d="M30 17a3.4 3.4 0 1 0-3.2-4.4" stroke-width="1.8"/>
    <path d="M24 13l-8 12h7l-4 9 12-13h-7l4-8z" fill="currentColor" fill-opacity=".92" stroke-width="1.2"/>
    <path d="M6 44V34h6v-4h5v4M31 34v-4h5v4h6v10" stroke-width="2.2"/><path d="M4 44h40" stroke-width="2.4"/>`,

  // --- KAEL skills ---------------------------------------------------------------------------------------------
  'kael-crescent': `<path d="M13 5c17 4 26 17 21 38-2-14-9-26-21-38z" fill="currentColor" fill-opacity=".85" stroke-width="1.6"/><path d="M6 43h36" stroke-width="2" opacity=".6"/><path d="M8 32c3-6 6-9 10-11M5 22c4-3 7-4 10-4" stroke-width="1.8" opacity=".6"/><circle cx="40" cy="14" r="1.4" fill="currentColor"/><circle cx="43" cy="22" r="1" fill="currentColor"/>`,
  'kael-eruption': `<path d="M24 5c6 7 8 15 4 23l2 10H18l2-10c-4-8-2-16 4-23z" fill="currentColor" fill-opacity=".8" stroke-width="1.6"/><path d="M3 38h42" stroke-width="2.2"/><path d="M10 38l3 6M36 38l-3 6M13 30l-4-6M35 30l4-6" stroke-width="2"/>`,
  'kael-bulwark': `<path d="M24 4l17 6v12c0 11-8 18-17 22-9-4-17-11-17-22V10z" stroke-width="2.2"/><path d="M24 36c-4 0-6-3-6-6 0-4 3-6 4-9 1 2 2 3 3 3 0-3 1-5 3-7 2 4 3 6 3 10 0 5-3 9-7 9z" fill="currentColor" fill-opacity=".85" stroke-width="1.4"/>`,
  'kael-ult': `<circle cx="24" cy="26" r="11" fill="currentColor" fill-opacity=".95"/><path d="M24 4c3 4 3 7 1 10M14 8c3 3 4 6 3 9M34 8c-3 3-4 6-3 9M7 18c3 1 5 3 6 5M41 18c-3 1-5 3-6 5" stroke-width="2.2"/><path d="M8 42h32" stroke-width="2"/>`,

  // --- ISKA skills ---------------------------------------------------------------------------------------------
  'iska-shards': `<path d="M24 4l4 17-4 17-4-17z" fill="currentColor" fill-opacity=".85" stroke-width="1.6"/><path d="M10 10l7 14-1 15-5-14z" fill="currentColor" fill-opacity=".45" stroke-width="1.6"/><path d="M38 10l-7 14 1 15 5-14z" fill="currentColor" fill-opacity=".45" stroke-width="1.6"/><path d="M14 44h20" stroke-width="1.8" opacity=".6"/>`,
  'iska-procession': `<path d="M4 42l4-9 4 9M11 42l6-16 6 16M21 42l9-26 9 26" fill="currentColor" fill-opacity=".35"/><path d="M30 16l9 26" stroke-width="1.2"/><path d="M2 42h44" stroke-width="2"/><path d="M41 9l2-4M44 14l3-1" stroke-width="1.8"/>`,
  'iska-afterimage': `<path d="M30 6a18 18 0 1 0 12 30A14 14 0 1 1 30 6z" fill="currentColor" fill-opacity=".85" stroke-width="1.6"/><path d="M18 8a18 18 0 0 0-2 30" stroke-dasharray="2.5 3.5" stroke-width="1.8" opacity=".6"/><path d="M10 11a18 18 0 0 0-1 24" stroke-dasharray="2 4" stroke-width="1.4" opacity=".35"/>`,
  'iska-ult': `<path d="M30 6l3.5 8.5L42 18l-8.5 3.5L30 30l-3.5-8.5L18 18l8.5-3.5z" fill="currentColor" fill-opacity=".9" stroke-width="1.6"/><path d="M22 26L8 40M17 23L7 33M25 31L15 41" stroke-width="2" opacity=".7"/>`,

  // --- VORN skills ---------------------------------------------------------------------------------------------
  'vorn-javelin': `<path d="M7 41L35 13" stroke-width="2.6"/><path d="M33 7l8 0 0 8-6 2-4-4z" fill="currentColor" fill-opacity=".9" stroke-width="1.6"/><path d="M10 30l5 1-1-5 6 1-1-5 6 1" stroke-width="1.8" opacity=".75"/>`,
  'vorn-stormfall': `<path d="M12 20c-5 0-6-7-1-8 1-6 9-7 12-3 4-4 13-2 13 4 5 0 6 7 1 7z" stroke-width="2"/><path d="M25 23l-7 11h7l-5 11 13-15h-7l4-7z" fill="currentColor" fill-opacity=".9" stroke-width="1.6"/>`,
  'vorn-arcstep': `<path d="M4 31h9l4-9 6 15 4-8h6" stroke-width="2.4"/><path d="M33 20l9 9-9 9" stroke-width="3"/><path d="M6 16h12M10 41h10" stroke-width="1.6" opacity=".55"/>`,
  'vorn-ult': `<path d="M24 46V12" stroke-width="2.6"/><path d="M24 2l5 10-5 5-5-5z" fill="currentColor" fill-opacity=".9" stroke-width="1.6"/><path d="M15 19l-5 6h5l-4 7M33 19l5 6h-5l4 7" stroke-width="1.8"/><path d="M17 15h14" stroke-width="2"/>`,
};

/** Icon markup by name ('' for unknown). */
export function icon(name, cls = '') {
  const body = P[name];
  return body ? G(body, '0 0 48 48', cls) : '';
}
export const hasIcon = (name) => !!P[name];

// Weapons: tall line art used as the hero art on fighter cards / versus / result / the 오의 banner. 60 x 240 grid, tip
// at the top. Keys are the roster's `weaponArt` values (unchanged identifiers).
const W = {
  // 참마대도 斬馬大刀: a broad single-edged great saber, clipped point, disc guard, long wrapped grip, ring pommel
  greatsword: `<path d="M37 150L38.5 54l3.5-7Q37 26 35.5 5Q15 22 12 58Q13 112 23 150z" fill="currentColor" fill-opacity=".16"/>
    <path d="M37 150L38.5 54l3.5-7Q37 26 35.5 5Q15 22 12 58Q13 112 23 150"/>
    <path d="M33.5 56L32.6 143" stroke-width="1.3" opacity=".65"/><path d="M33 13Q19.5 28 17 59Q18 108 26.5 147" stroke-width="1" opacity=".45"/>
    <path d="M29 121q3-4 0-8q-3-4 0-8" stroke-width="1" opacity=".5"/>
    <path d="M23 144h14v7H23z" fill="currentColor" fill-opacity=".4"/>
    <ellipse cx="30" cy="154.5" rx="14" ry="3.8" fill="currentColor" fill-opacity=".3" stroke-width="2.4"/>
    <path d="M26 159l.8 58M34 159l-.8 58"/><path d="M26.2 166l7.4 5M26.4 176l7.2 5M26.6 186l7 5M26.8 196l6.6 5M27 206l6.2 5M33.8 166l-7.4 5M33.6 176l-7.2 5M33.4 186l-7 5M33.2 196l-6.6 5" stroke-width="1.1" opacity=".7"/>
    <circle cx="30" cy="225" r="7.4" stroke-width="2.6"/><path d="M30 232.5q-5 3-4.5 7.5M30 232.5q4.5 2.5 5 7" stroke-width="1.3" opacity=".7"/>`,
  // 월아쌍도 月牙雙刀: twin crescent blades
  crescents: `<g transform="rotate(-14 30 120)"><path d="M18 18c26 26 30 70 14 108 4-36-2-70-14-108z" fill="currentColor" fill-opacity=".2"/><path d="M18 18c26 26 30 70 14 108M18 18c12 38 18 72 14 108"/>
      <path d="M22 30c18 26 21 62 11 92" stroke-width="1" opacity=".5"/>
      <path d="M22.5 128.5q5.5-3 11 0" stroke-width="2.6"/><path d="M28 130v27" stroke-width="3.4"/><path d="M26 136l4 3M26 143l4 3M26 150l4 3" stroke-width="1" opacity=".7"/>
      <circle cx="28" cy="162" r="4.6" stroke-width="2"/><path d="M28 166.5q-3 4-1.5 9" stroke-width="1.1" opacity=".7"/></g>
    <g transform="rotate(14 30 120)"><path d="M42 82c-26 26-30 70-14 108-4-36 2-70 14-108z" fill="currentColor" fill-opacity=".2"/><path d="M42 82c-26 26-30 70-14 108M42 82c-12 38-18 72-14 108"/>
      <path d="M38 94c-18 26-21 62-11 92" stroke-width="1" opacity=".5"/>
      <path d="M26.5 192.5q5.5-3 11 0" stroke-width="2.6"/><path d="M32 194v27" stroke-width="3.4"/><path d="M30 200l4 3M30 207l4 3M30 214l4 3" stroke-width="1" opacity=".7"/>
      <circle cx="32" cy="226" r="4.6" stroke-width="2"/><path d="M32 230.5q3 4 1.5 8" stroke-width="1.1" opacity=".7"/></g>`,
  // 뇌룡창 雷龍槍: a long war spear with a horsehair tassel (창영) under the head
  spear: `<path d="M30 2Q40 26 35.5 46L30 57L24.5 46Q20 26 30 2z" fill="currentColor" fill-opacity=".22"/><path d="M30 2Q40 26 35.5 46L30 57L24.5 46Q20 26 30 2z"/><path d="M30 9v44" stroke-width="1.2" opacity=".6"/>
    <path d="M30 64v165" stroke-width="3.2"/>
    <path d="M25.5 57h9v8h-9z" fill="currentColor" fill-opacity=".45"/><path d="M23.5 65h13" stroke-width="2.6"/>
    <path d="M26 66Q12 80 13.5 101l4-4 2.5 7 4-5 4.5 6 3.5-6 4 5 3-7 4.5 4Q48 80 34 66z" fill="currentColor" fill-opacity=".28" stroke-width="1.6"/>
    <path d="M28 68Q20 82 19.5 98M30 68Q27.5 84 28 101M31.5 68Q34.5 84 36 100M33.5 68Q40.5 82 41.5 96M27 67Q16.5 80 16 95" stroke-width="1" opacity=".7"/>
    <path d="M27 132h6M27 136h6M27 184h6M27 188h6" stroke-width="1.4" opacity=".7"/>
    <path d="M30 229l4 4.5-4 6-4-6z" fill="currentColor" fill-opacity=".5"/>`,
};

/** Weapon silhouette markup ('greatsword' | 'crescents' | 'spear'). */
export function weaponArt(kind, cls = '') {
  const body = W[kind] || W.greatsword;
  return G(body, '0 0 60 240', 'weapon ' + cls);
}

/**
 * Corona of fine rays around a disc (the eclipse motif used by the timer, the ULT orb and the announcer): `n` rays
 * starting at radius `r0` on a 100x100 grid, lengths from a fixed pattern (every 6th ray long), so it is identical
 * everywhere. Drawn with currentColor.
 * @param {{ n?: number, r0?: number, len?: number, w?: number }} [o]
 */
export function corona({ n = 48, r0 = 38, len = 10, w = 1 } = {}) {
  let d = '', dl = '';
  for (let i = 0; i < n; i++) {
    const a = (i / n) * Math.PI * 2;
    const major = i % 6 === 0;
    const l = len * (0.35 + ((i * 37) % 11) / 16) + (major ? len * 0.7 : 0);
    const seg = `M${(50 + Math.cos(a) * r0).toFixed(2)} ${(50 + Math.sin(a) * r0).toFixed(2)}L${(50 + Math.cos(a) * (r0 + l)).toFixed(2)} ${(50 + Math.sin(a) * (r0 + l)).toFixed(2)}`;
    if (major) dl += seg; else d += seg;
  }
  return `<svg viewBox="0 0 100 100" fill="none" stroke="currentColor" stroke-linecap="round" aria-hidden="true"><path d="${d}" stroke-width="${(w * 0.7).toFixed(2)}" opacity=".6"/><path d="${dl}" stroke-width="${(w * 1.3).toFixed(2)}"/></svg>`;
}

/**
 * The eclipse emblem (logo mark, pause emblem, announcer backdrops): the ink black sun of ink.inkEclipse().
 * @param {string} [cls]
 */
export function eclipseMark(cls = '') {
  return inkEclipse({ cls: 'eclipse ' + cls });
}
