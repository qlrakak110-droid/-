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

