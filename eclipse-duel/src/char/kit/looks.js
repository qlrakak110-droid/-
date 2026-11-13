// Surface looks: { color (sRGB hex or linear [r,g,b]), rough, metal, set (texture set), amt (detail amount 0..1),
// inlay / vein / eye (glow channel masks 0..1, material `glow` mode), occ (occlusion multiplier), wear (edge-wear scale),
// tint(p, n, i) -> albedo multiplier }. Pass a look to put() / putPair(). Copy and tweak per design.

/** Generic presets (linear colours). */
export const LOOKS = {
  blackSteel: { color: [0.055, 0.053, 0.055], rough: 0.4, metal: 1, set: 'hammered', amt: 1 },
  scorchedSteel: { color: [0.045, 0.041, 0.04], rough: 0.46, metal: 0.92, set: 'scorched', amt: 1, vein: 0.6 },
  brightSteel: { color: [0.42, 0.42, 0.44], rough: 0.24, metal: 1, set: 'hammered', amt: 0.8 },
  blueSteel: { color: [0.16, 0.18, 0.24], rough: 0.28, metal: 1, set: 'hammered', amt: 0.8 },
  bronze: { color: [0.3, 0.17, 0.07], rough: 0.36, metal: 1, set: 'engraved', amt: 0.9 },
  silver: { color: [0.6, 0.6, 0.62], rough: 0.22, metal: 1, set: 'engraved', amt: 0.9 },
  gold: { color: [0.62, 0.42, 0.14], rough: 0.26, metal: 1, set: 'engraved', amt: 0.8 },
  leather: { color: [0.05, 0.03, 0.02], rough: 0.68, metal: 0, set: 'leather', amt: 1 },
  darkLeather: { color: [0.022, 0.015, 0.012], rough: 0.62, metal: 0, set: 'leather', amt: 1 },
  mail: { color: [0.16, 0.16, 0.17], rough: 0.42, metal: 1, set: 'mail', amt: 1 },
  gambeson: { color: [0.06, 0.045, 0.035], rough: 0.85, metal: 0, set: 'quilted', amt: 1 },
  cloth: { color: [0.05, 0.02, 0.016], rough: 0.85, metal: 0, set: 'cloth', amt: 1 },
  fur: { color: [0.04, 0.032, 0.026], rough: 0.8, metal: 0, set: 'fur', amt: 1 },
  slit: { color: [0.004, 0.004, 0.004], rough: 0.9, metal: 0, set: 'hammered', amt: 0, occ: 0.4 },
  emberInlay: { color: [0.03, 0.01, 0.005], rough: 0.5, metal: 0, set: 'hammered', amt: 0, inlay: 1 },
};


/**
 * Murim material library (linear colours): cloth-first martial masters. Copy and tint per hero:
 *   put(kit, 'robe', 'chest', geo, { ...MURIM.silk, color: [0.2, 0.012, 0.01] });
 * Cloth: silk (matte, satin sheen, the weave only shows in close-ups), damask (figured silk: the `vein` channel glows
 * through the woven clouds), hemp / cotton (coarse), gauze (veils; needs a `cutout` material and a uv code = opacity).
 * Hard: lacquer (clear coat; `vein` glows through the craquelure), lamellar (찰갑, UV set), leather, bamboo (UV set),
 * blade steel (UV set: bright honed edge + temper line), aged bronze (verdigris), jade, silver.
 * Hair: UV set (ribbons / cards with strand highlights).
 */
export const MURIM = {
  silk: { color: [0.03, 0.03, 0.035], rough: 0.52, metal: 0, set: 'silk', amt: 1 },
  silkCrimson: { color: [0.2, 0.012, 0.01], rough: 0.5, metal: 0, set: 'silk', amt: 1 },
  silkIndigo: { color: [0.016, 0.022, 0.09], rough: 0.5, metal: 0, set: 'silk', amt: 1 },
  silkMoon: { color: [0.36, 0.38, 0.42], rough: 0.5, metal: 0, set: 'silk', amt: 1 },
  silkViolet: { color: [0.05, 0.018, 0.1], rough: 0.5, metal: 0, set: 'silk', amt: 1 },
  damask: { color: [0.03, 0.03, 0.035], rough: 0.5, metal: 0, set: 'damask', amt: 1 },
  hemp: { color: [0.22, 0.18, 0.12], rough: 0.92, metal: 0, set: 'hemp', amt: 1 },
  hempInk: { color: [0.022, 0.021, 0.022], rough: 0.9, metal: 0, set: 'hemp', amt: 1 },
  cotton: { color: [0.05, 0.045, 0.04], rough: 0.86, metal: 0, set: 'cloth', amt: 1 },
  wrap: { color: [0.12, 0.1, 0.075], rough: 0.9, metal: 0, set: 'hemp', amt: 1 },
  gauze: { color: [0.34, 0.36, 0.4], rough: 0.8, metal: 0, set: 'gauze', amt: 1 },
  gauzeInk: { color: [0.02, 0.02, 0.024], rough: 0.8, metal: 0, set: 'gauze', amt: 1 },
  trim: { color: [0.025, 0.02, 0.02], rough: 0.55, metal: 0, set: 'brocade', amt: 1 },
  leather: { color: [0.045, 0.026, 0.016], rough: 0.64, metal: 0, set: 'leather', amt: 1 },
  leatherBlack: { color: [0.016, 0.013, 0.012], rough: 0.58, metal: 0, set: 'leather', amt: 1 },
  lacquer: { color: [0.012, 0.011, 0.011], rough: 0.3, metal: 0, set: 'lacquer', amt: 1, wear: 1.1 },
  lacquerRed: { color: [0.2, 0.014, 0.008], rough: 0.3, metal: 0, set: 'lacquer', amt: 1, wear: 1.1 },
  lamellar: { color: [0.014, 0.012, 0.012], rough: 0.34, metal: 0, set: 'lamellar', amt: 1 },
  lamellarIron: { color: [0.11, 0.105, 0.1], rough: 0.42, metal: 1, set: 'lamellar', amt: 1 },
  bamboo: { color: [0.2, 0.14, 0.065], rough: 0.5, metal: 0, set: 'bamboo', amt: 1 },
  bambooDark: { color: [0.045, 0.032, 0.02], rough: 0.4, metal: 0, set: 'bamboo', amt: 1 },
  wood: { color: [0.02, 0.012, 0.008], rough: 0.36, metal: 0, set: 'lacquer', amt: 0.7 },
  steel: { color: [0.2, 0.2, 0.21], rough: 0.3, metal: 1, set: 'blade', amt: 0.5, wear: 0.6 },
  steelDark: { color: [0.05, 0.048, 0.05], rough: 0.4, metal: 1, set: 'hammered', amt: 0.8 },
  iron: { color: [0.06, 0.056, 0.055], rough: 0.5, metal: 0.9, set: 'hammered', amt: 1 },
  ironCharred: { color: [0.04, 0.036, 0.035], rough: 0.56, metal: 0.85, set: 'scorched', amt: 1, vein: 0.7 },
  bronze: { color: [0.3, 0.17, 0.07], rough: 0.4, metal: 1, set: 'bronze', amt: 0.9 },
  bronzeEngraved: { color: [0.3, 0.17, 0.07], rough: 0.38, metal: 1, set: 'engraved', amt: 1 },
  gilt: { color: [0.62, 0.42, 0.14], rough: 0.3, metal: 1, set: 'engraved', amt: 0.8 },
  silver: { color: [0.62, 0.63, 0.66], rough: 0.24, metal: 1, set: 'engraved', amt: 0.8 },
  silverPlain: { color: [0.62, 0.63, 0.66], rough: 0.2, metal: 1, set: 'hammered', amt: 0.5 },
  jade: { color: [0.045, 0.2, 0.1], rough: 0.22, metal: 0, set: 'jade', amt: 0.6 },
  jadeWhite: { color: [0.42, 0.5, 0.42], rough: 0.22, metal: 0, set: 'jade', amt: 0.6 },
  hair: { color: [0.012, 0.011, 0.012], rough: 0.42, metal: 0, set: 'hair', amt: 1 },
  hairGrey: { color: [0.3, 0.3, 0.32], rough: 0.45, metal: 0, set: 'hair', amt: 1 },
  horsehair: { color: [0.3, 0.02, 0.012], rough: 0.5, metal: 0, set: 'hair', amt: 1 },
  cord: { color: [0.2, 0.014, 0.01], rough: 0.8, metal: 0, set: 'hemp', amt: 0.8 },
  dark: { color: [0.003, 0.003, 0.003], rough: 0.95, metal: 0, set: 'hammered', amt: 0, occ: 0.3 },
  eye: { color: [0.01, 0.01, 0.01], rough: 0.6, metal: 0, set: 'hammered', amt: 0, eye: 1 },
  energy: { color: [0.02, 0.02, 0.02], rough: 0.5, metal: 0, set: 'hammered', amt: 0, inlay: 1 },
};

/** Brocade motif ids (the integer part of a brocade band's uv code). */
export const MOTIF = { cloud: 0, wave: 1, flame: 2, fret: 3, sun: 4, moon: 5, thunder: 6, lattice: 7 };
