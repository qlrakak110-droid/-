// Colour-grade presets (display-referred, applied after ACES + sRGB encoding).
//
//   gradeLift / gradeGamma / gradeGain   ASC-CDL-style per-channel lift (adds to the blacks), gamma, gain
//   toneShadows / toneHighlights         split-toning hues (only their chroma is used: luminance-neutral)
//   toneAmount                           split-toning strength (0..0.2 sensible)
//   toneBalance                          -1 (more of the image counts as shadow) .. +1 (more counts as highlight)
//   saturation / contrast                optional: the generic fx keys, included where a mood needs them
//
// Values are plain arrays so a preset can be passed straight to post.grade() or post.to().

/** @type {Record<string, object>} */
export const GRADES = {
  /** identity: ACES only */
  neutral: {
    gradeLift: [0, 0, 0], gradeGamma: [1, 1, 1], gradeGain: [1, 1, 1],
    toneShadows: [0.5, 0.5, 0.5], toneHighlights: [0.5, 0.5, 0.5], toneAmount: 0, toneBalance: 0,
  },
  /** the arena by default: cold blue-black shadows, faintly warm highlights (brazier pools), rim stays cold */
  night: {
    gradeLift: [0.002, 0.005, 0.014], gradeGamma: [0.98, 1.0, 1.03], gradeGain: [1.03, 1.0, 0.97],
    toneShadows: [0.32, 0.5, 0.82], toneHighlights: [1.0, 0.78, 0.5], toneAmount: 0.07, toneBalance: 0.1,
  },
  /** ultimate darkness: the world sinks to cold steel, colour lives only in the VFX */
  eclipse: {
    gradeLift: [0.0, 0.004, 0.012], gradeGamma: [0.94, 0.97, 1.04], gradeGain: [1.0, 1.0, 1.02],
    toneShadows: [0.3, 0.45, 0.85], toneHighlights: [0.9, 0.85, 0.8], toneAmount: 0.06, toneBalance: -0.3,
  },
  /** KAEL / fire: ember-orange highlights, smoky brown-black shadows */
  ember: {
    gradeLift: [0.012, 0.005, 0.002], gradeGamma: [1.03, 0.99, 0.95], gradeGain: [1.07, 0.99, 0.9],
    toneShadows: [0.55, 0.38, 0.3], toneHighlights: [1.0, 0.62, 0.3], toneAmount: 0.09, toneBalance: 0,
  },
  /** ISKA / frost: blue-white highlights, deep teal shadows, a touch lifted */
  frost: {
    gradeLift: [0.004, 0.009, 0.018], gradeGamma: [0.96, 1.0, 1.05], gradeGain: [0.95, 1.0, 1.06],
    toneShadows: [0.3, 0.55, 0.75], toneHighlights: [0.75, 0.88, 1.0], toneAmount: 0.08, toneBalance: 0.15,
  },
  /** VORN / storm: violet shadows, gold-white highlights */
  storm: {
    gradeLift: [0.008, 0.004, 0.016], gradeGamma: [0.99, 0.97, 1.03], gradeGain: [1.03, 1.0, 1.0],
    toneShadows: [0.5, 0.36, 0.85], toneHighlights: [1.0, 0.85, 0.55], toneAmount: 0.09, toneBalance: 0,
  },
  /** result screen: warm, slightly lifted, gentle */
  victory: {
    gradeLift: [0.008, 0.006, 0.004], gradeGamma: [1.02, 1.0, 0.97], gradeGain: [1.05, 1.01, 0.94],
    toneShadows: [0.45, 0.45, 0.6], toneHighlights: [1.0, 0.8, 0.55], toneAmount: 0.08, toneBalance: 0.2,
  },
};

/** Keys of the grade that are colours (tweened as THREE.Color). */
export const GRADE_COLOR_KEYS = ['gradeLift', 'gradeGamma', 'gradeGain', 'toneShadows', 'toneHighlights'];
