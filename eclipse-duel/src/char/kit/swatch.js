// Material swatches for look-dev (art lab `swatches` scenario): every murim look on a sphere over a hanging, folded
// panel, built with the static kit. UV sets get the uv scale a real piece would use, so what the lab shows is what a
// garment shows.
//
//   const sk = createStaticKit();
//   const pages = buildSwatches(sk, 'swatch');                 // pieces on slot 'swatch' (+ 'swatchCut' for cut-outs)
//   const group = sk.finish({ swatch: createKitMaterial(SWATCH_MATERIAL), swatchCut: createKitMaterial({ ...SWATCH_MATERIAL, cutout: true }) });

import { mk, fixWinding, put, band, merge } from './geo.js';
import { MURIM, MOTIF, LOOKS } from './looks.js';

/** Slot material options used by the lab for the swatches (channel-mode glow so vein / thread glow can be judged). */
export const SWATCH_MATERIAL = {
  envMapIntensity: 1, bump: 1, glow: { inlay: [2.5, 3.5, 6], vein: [5, 1.6, 0.3], eye: [6, 5, 2] }, rim: [0.2, 0.26, 0.4, 3.2],
  thread: [0.55, 0.36, 0.11], lace: [0.3, 0.025, 0.018], wearColor: [0.5, 0.5, 0.52],
};

/** uv scale of the UV sets on a swatch: units of u / v per metre (what the kit builders use). */
const UV = {
  lamellar: [1 / 0.092, 1 / 0.07], bamboo: [1 / 0.04, 1 / 0.04], gauze: [1 / 0.02, 1 / 0.02], hair: [8, 0], blade: [1, 0], fur: [4, 0],
};

function uvOf(set, x, y, w, h, code) {
  if (set === 'hair' || set === 'fur') return [x * UV[set][0], 1 - y / h, code];
  if (set === 'blade') return [x, y / h, code];
  const k = UV[set] || [1 / w, 1 / h];
  return [x * k[0], (h - y) * k[1], code];
}

/** Hanging panel w x h with soft vertical folds (deeper toward the hem), top edge at y = h. */
function panel(w, h, set, code, nx = 28, ny = 14) {
  const pos = [], nor = [], idx = [], uvw = [];
  for (let j = 0; j <= ny; j++) {
    const v = j / ny, y = h * (1 - v);
    for (let i = 0; i <= nx; i++) {
      const u = i / nx, x = (u - 0.5) * w;
      const amp = 0.014 * (0.25 + 0.75 * v), ph = u * Math.PI * 5 + 0.6;
      const z = amp * Math.sin(ph) + 0.004 * Math.sin(u * Math.PI * 11 + 1.7) * v;
      const dz = amp * Math.cos(ph) * Math.PI * 5 / w;
      const l = Math.hypot(dz, 1);
      pos.push(x, y, z); nor.push(-dz / l, 0, 1 / l);
      uvw.push(...uvOf(set, x + w / 2, y, w, h, code));
    }
  }
  for (let j = 0; j < ny; j++) for (let i = 0; i < nx; i++) { const a = j * (nx + 1) + i, b = a + 1, c = a + nx + 1, d = c + 1; idx.push(a, c, b, b, c, d); }
  return fixWinding(mk(pos, nor, idx, null, uvw));
}

/** Sphere of radius r centred at (0, cy, 0) with (u, v) = (longitude arc, latitude arc) in metres x the set's uv scale. */
function ball(r, cy, set, code, ws = 28, hs = 18) {
  const pos = [], nor = [], idx = [], uvw = [];
  for (let j = 0; j <= hs; j++) {
    const th = (j / hs) * Math.PI, st = Math.sin(th), ct = Math.cos(th);
    for (let i = 0; i <= ws; i++) {
      const ph = (i / ws) * Math.PI * 2;
      const n = [st * Math.sin(ph), ct, st * Math.cos(ph)];
      pos.push(n[0] * r, cy + n[1] * r, n[2] * r); nor.push(...n);
      uvw.push(...uvOf(set, (i / ws) * 2 * Math.PI * r, r * Math.PI * (1 - j / hs), 2 * Math.PI * r, Math.PI * r, code));
    }
  }
  for (let j = 0; j < hs; j++) for (let i = 0; i < ws; i++) { const a = j * (ws + 1) + i, b = a + 1, c = a + ws + 1, d = c + 1; idx.push(a, c, b, b, c, d); }
  return fixWinding(mk(pos, nor, idx, null, uvw));
}

/** The swatch list: [label, look, { code, cut (needs the cut-out slot), vein (vertex vein mask) }]. Four per page. */
export const SWATCHES = [
  ['silk', MURIM.silk], ['silkCrimson', MURIM.silkCrimson], ['silkIndigo', MURIM.silkIndigo], ['silkMoon', MURIM.silkMoon],
  ['damask', { ...MURIM.damask, color: [0.05, 0.018, 0.1] }], ['damask + vein', { ...MURIM.damask, color: [0.09, 0.012, 0.01], vein: 0.8 }], ['hemp', MURIM.hemp], ['hempInk', MURIM.hempInk],
  ['cotton', MURIM.cotton], ['leather', MURIM.leather], ['leatherBlack', MURIM.leatherBlack], ['wood', MURIM.wood],
  ['lacquer', MURIM.lacquer], ['lacquerRed', MURIM.lacquerRed], ['lacquer + vein', { ...MURIM.lacquer, vein: 0.9 }], ['bamboo', MURIM.bamboo],
  ['lamellar', MURIM.lamellar], ['lamellar + glow', MURIM.lamellar, { code: 0.8 }], ['lamellarIron', MURIM.lamellarIron], ['bambooDark', MURIM.bambooDark, { code: 0.6 }],
  ['steel (blade)', MURIM.steel, { code: 0.34 }], ['steelDark', MURIM.steelDark], ['iron', MURIM.iron], ['ironCharred', MURIM.ironCharred],
  ['bronze', MURIM.bronze], ['bronzeEngraved', MURIM.bronzeEngraved], ['gilt', MURIM.gilt], ['silver', MURIM.silver],
  ['jade', MURIM.jade], ['jadeWhite', MURIM.jadeWhite], ['gauze', MURIM.gauze, { code: 0.5, cut: true }], ['gauzeInk', MURIM.gauzeInk, { code: 0.62, cut: true }],
  ['hair', MURIM.hair, { code: 0.55, cut: true }], ['hairGrey', MURIM.hairGrey, { code: 0.55, cut: true }], ['horsehair', MURIM.horsehair, { code: 0.4, cut: true }], ['fur', LOOKS.fur, { cut: true }],
];

/**
 * Add every swatch to a static kit. Items sit on a line along x, `pitch` apart; page p holds items 4p .. 4p + 3 and
 * the brocade sampler follows as the last page.
 * @returns {{ pages: number, pitch: number, labels: string[], xOf(i): number, brocadeX: number }}
 */
export function buildSwatches(kit, slot = 'swatch', o = {}) {
  const pitch = o.pitch ?? 0.34, W = 0.26, H = 0.3, R = 0.085;
  SWATCHES.forEach(([, look, x = {}], i) => {
    const s = x.cut ? slot + 'Cut' : slot, code = x.code ?? 0, at = [i * pitch, 0, 0];
    const set = typeof look.set === 'string' ? look.set : '';
    put(kit, s, null, panel(W, H, set, code), look, { at });
    put(kit, s, null, ball(R, H + R + 0.012, set, code), look, { at });
  });
  // brocade sampler: the eight motifs as bands on a dark silk panel (glow rising left to right), and on a ball
  const bx = SWATCHES.length * pitch + 0.2;
  put(kit, slot, null, panel(0.62, 0.52, 'silk', 0, 40, 10), MURIM.silk, { at: [bx, 0, -0.004] });
  const names = Object.keys(MOTIF);
  names.forEach((name, k) => {
    const y = 0.5 - 0.03 - k * 0.062, frames = [];
    for (let i = 0; i <= 40; i++) {
      const u = i / 40, x = (u - 0.5) * 0.6, amp = 0.014 * (0.25 + 0.75 * (1 - y / 0.52)), ph = ((x + 0.31) / 0.62) * Math.PI * 5 + 0.6;
      const dz = amp * Math.cos(ph) * Math.PI * 5 / 0.62, l = Math.hypot(dz, 1);
      frames.push({ p: [x, y, amp * Math.sin(ph) + 0.004 * Math.sin(((x + 0.31) / 0.62) * Math.PI * 11 + 1.7) * (1 - y / 0.52) - 0.004], n: [-dz / l, 0, 1 / l] });
    }
    const half = (c0, c1) => merge([band(frames.slice(0, 21), { width: 0.05, code: MOTIF[name] + c0, side: [0, -1, 0] }), band(frames.slice(20), { width: 0.05, code: MOTIF[name] + c1, u0: 0.3 / 0.05, side: [0, -1, 0] })]);
    put(kit, slot, null, half(0, 0.7), { ...MURIM.trim, color: k % 2 ? [0.11, 0.008, 0.006] : [0.012, 0.012, 0.014] }, { at: [bx, 0, 0] });
  });
  return { pages: Math.ceil(SWATCHES.length / 4) + 1, pitch, labels: SWATCHES.map((s) => s[0]).concat(names.map((n) => 'brocade:' + n)), xOf: (i) => i * pitch, brocadeX: bx };
}
