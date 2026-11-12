// Inline SVG icon set (strings). Every glyph is our own line art on a 48x48 grid, drawn with currentColor so CSS
// colours it. Weapons use a tall 60x240 grid. No external images.

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

  // --- generic actions (touch pad, hints) --------------------------------------------------------------------
  light: `<path d="M9 39C17 30 27 19 40 8" stroke-width="3.4"/><path d="M8 31c6-6 13-13 21-20" stroke-width="1.6" opacity=".55"/><path d="M38 21l3 1M33 27l2 2" stroke-width="2"/>`,
  heavy: `<path d="M7 41C13 22 27 9 43 5 32 14 23 26 19 42z" fill="currentColor" fill-opacity=".85" stroke-width="1.8"/><path d="M5 30c3-8 9-15 16-20" stroke-width="2" opacity=".6"/><path d="M33 31l8 3M29 37l5 6" stroke-width="2.2"/>`,
  guard: `<path d="M24 5l15 5v12c0 10-7 17-15 21-8-4-15-11-15-21V10z" fill="currentColor" fill-opacity=".12"/><path d="M24 12v24M16 20h16" stroke-width="2"/>`,
  dodge: `<path d="M6 15h15M11 24h14M6 33h15" stroke-width="2.2" opacity=".7"/><path d="M29 11l13 13-13 13" stroke-width="3.2"/>`,
  ult: `<circle cx="24" cy="24" r="10" fill="currentColor" fill-opacity=".9"/><circle cx="24" cy="24" r="15.5" stroke-width="1.6"/>
    <path d="M24 2v5M24 41v5M2 24h5M41 24h5M8.4 8.4l3.6 3.6M36 36l3.6 3.6M8.4 39.6l3.6-3.6M36 12l3.6-3.6" stroke-width="2"/>`,
  pause: `<path d="M17 12v24M31 12v24" stroke-width="4"/>`,
  back: `<path d="M29 10L15 24l14 14" stroke-width="3"/>`,
  random: `<path d="M24 4l20 20-20 20L4 24z" stroke-width="1.8"/><path d="M18.5 19a5.5 5.5 0 1 1 8 4.9c-1.6.9-2.5 2-2.5 3.6V29" stroke-width="2.8"/><circle cx="24" cy="34.5" r="1.8" fill="currentColor" stroke="none"/>`,
  list: `<path d="M17 13h22M17 24h22M17 35h22" stroke-width="2.4"/><path d="M8 13l2-2 2 2-2 2zM8 24l2-2 2 2-2 2zM8 35l2-2 2 2-2 2z" fill="currentColor" stroke-width="1.2"/>`,
  gear: `<circle cx="24" cy="24" r="6"/><path d="M24 5v6M24 37v6M5 24h6M37 24h6M10.6 10.6l4.2 4.2M33.2 33.2l4.2 4.2M10.6 37.4l4.2-4.2M33.2 14.8l4.2-4.2"/><circle cx="24" cy="24" r="13" stroke-width="1.6"/>`,
  home: `<path d="M7 23L24 8l17 15M12 19v21h24V19" /><path d="M20 40V29h8v11" stroke-width="2"/>`,
  rematch: `<path d="M38 18A15 15 0 0 0 10.5 16M10 30a15 15 0 0 0 27.5 2" stroke-width="2.6"/><path d="M10 7v9h9M38 41v-9h-9" stroke-width="2.6"/>`,
  people: `<circle cx="17" cy="16" r="6"/><circle cx="33" cy="18" r="5" opacity=".7"/><path d="M5 40c1-8 6-12 12-12s11 4 12 12M29 30c5 0 11 2 13 10" />`,

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

// Weapons: tall silhouettes used as the hero art on fighter cards / versus / result. 60 x 240 grid, tip at the top.
const W = {
  greatsword: `<path d="M30 4l11 26v150H19V30z" fill="currentColor" fill-opacity=".16"/>
    <path d="M30 4l11 26v150M30 4L19 30v150"/><path d="M30 26v150" stroke-width="1.2" opacity=".6"/>
    <path d="M24 60h12M24 92h12M24 124h12" stroke-width="1" opacity=".35"/>
    <path d="M4 186c4-6 10-6 14-6h24c4 0 10 0 14 6" stroke-width="2.6"/><path d="M8 186l-2 6M52 186l2 6" />
    <path d="M18 180h24v8H18z" fill="currentColor" fill-opacity=".35"/>
    <path d="M26 188h8v34h-8z" fill="currentColor" fill-opacity=".22"/><path d="M26 196l8 4M26 204l8 4M26 212l8 4" stroke-width="1.4"/>
    <path d="M30 222l7 7-7 9-7-9z" fill="currentColor" fill-opacity=".5"/>`,
  crescents: `<g transform="rotate(-14 30 120)"><path d="M18 18c26 26 30 70 14 108 4-36-2-70-14-108z" fill="currentColor" fill-opacity=".2"/><path d="M18 18c26 26 30 70 14 108M18 18c12 38 18 72 14 108"/>
      <path d="M28 126v32M24 130h8" stroke-width="2.2"/><path d="M28 158l4 5-4 5-4-5z" fill="currentColor" fill-opacity=".5"/></g>
    <g transform="rotate(14 30 120)"><path d="M42 82c-26 26-30 70-14 108-4-36 2-70 14-108z" fill="currentColor" fill-opacity=".2"/><path d="M42 82c-26 26-30 70-14 108M42 82c-12 38-18 72-14 108"/>
      <path d="M32 190v32M28 194h8" stroke-width="2.2"/><path d="M32 222l4 5-4 5-4-5z" fill="currentColor" fill-opacity=".5"/></g>`,
  spear: `<path d="M30 3l9 30-9 22-9-22z" fill="currentColor" fill-opacity=".22"/><path d="M30 3l9 30-9 22-9-22z"/><path d="M30 10v40" stroke-width="1.2" opacity=".6"/>
    <path d="M14 58c6 2 10 2 16 2s10 0 16-2M18 58l-4-8M42 58l4-8" stroke-width="2.2"/><path d="M27 60h6v8h-6z" fill="currentColor" fill-opacity=".4"/>
    <path d="M30 68v162" stroke-width="3"/><path d="M27 100h6M27 104h6M27 150h6M27 154h6" stroke-width="1.4" opacity=".7"/>
    <path d="M30 230l4 5-4 4-4-4z" fill="currentColor" fill-opacity=".5"/>`,
};

/** Weapon silhouette markup ('greatsword' | 'crescents' | 'spear'). */
export function weaponArt(kind, cls = '') {
  const body = W[kind] || W.greatsword;
  return G(body, '0 0 60 240', 'weapon ' + cls);
}

/**
 * The eclipse emblem (logo mark): black disc, engraved rings, a corona of fine rays and the diamond-ring bead.
 * Rays come from a fixed pattern so the mark is identical everywhere.
 */
export function eclipseMark(cls = '') {
  let rays = '';
  for (let i = 0; i < 72; i++) {
    const a = (i / 72) * Math.PI * 2;
    const len = 8 + ((i * 37) % 11) * 2.2 + (i % 6 === 0 ? 16 : 0) + (i % 18 === 0 ? 12 : 0);
    const r0 = 62, r1 = r0 + len;
    const x0 = 100 + Math.cos(a) * r0, y0 = 100 + Math.sin(a) * r0, x1 = 100 + Math.cos(a) * r1, y1 = 100 + Math.sin(a) * r1;
    rays += `<line x1="${x0.toFixed(1)}" y1="${y0.toFixed(1)}" x2="${x1.toFixed(1)}" y2="${y1.toFixed(1)}" stroke-width="${i % 6 === 0 ? 1.3 : 0.7}" opacity="${i % 6 === 0 ? 0.95 : 0.55}"/>`;
  }
  return `<svg class="eclipse ${cls}" viewBox="0 0 200 200" fill="none" stroke="currentColor" aria-hidden="true">
    <defs>
      <radialGradient id="edCor" cx="50%" cy="50%" r="50%"><stop offset=".55" stop-color="#f3dca0" stop-opacity=".55"/><stop offset=".64" stop-color="#d8b46a" stop-opacity=".22"/><stop offset="1" stop-color="#d8b46a" stop-opacity="0"/></radialGradient>
      <radialGradient id="edBead" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="#fff" stop-opacity="1"/><stop offset=".25" stop-color="#fff4d6" stop-opacity=".9"/><stop offset="1" stop-color="#f3dca0" stop-opacity="0"/></radialGradient>
    </defs>
    <circle cx="100" cy="100" r="98" fill="url(#edCor)" stroke="none"/>
    <g class="eclipse-rays">${rays}</g>
    <circle cx="100" cy="100" r="61" stroke-width="2.2" stroke="#fbeec8"/>
    <circle cx="100" cy="100" r="58.5" fill="#030306" stroke="none"/>
    <circle cx="100" cy="100" r="52" stroke-width=".6" opacity=".35"/>
    <circle cx="100" cy="100" r="86" stroke-width=".6" opacity=".45" stroke-dasharray="1 5"/>
    <circle cx="143" cy="57" r="16" fill="url(#edBead)" stroke="none"/>
  </svg>`;
}
