// Music: sample-based instruments (each rendered once with the kit, multi-sampled at a few root notes, sustained
// notes loop a crossfaded region) driven by a small 16th-note step sequencer. All compositions are original.
//
//   title     54 BPM, D minor. Dark choir chords (Dm(add9) - Bbmaj7 - Gm(add9) - Asus4 -> A) over low strings, a
//             wind bed, soft heartbeat drum and a lone bell motif.
//   battle    140 BPM, D minor (Aeolian with a Phrygian bII in the B section). Galloping low-string ostinato
//             (3+3+2 accents); intensity layers: 'drums' (taiko, rim, shime, fills) and 'lift' (brass swells,
//             upper strings, choir, cymbals, a horn line in the B section at full intensity).
//   ultimate  overlay that sits over the battle track: D/Eb cluster drone, heartbeat pulse, rising tremolo cluster
//             every 2 bars, cymbal swells, dissonant low brass.
//   victory   84 BPM, 4 bars, not looped: Bb - C - Asus4 cadence resolving to D major (Picardy third) with bells.

import { smoothstep } from '../core/math.js';

/** MIDI note -> Hz. */
export const midiHz = (m) => 440 * Math.pow(2, (m - 69) / 12);

const CYMBAL = [[7.1, 0.2, 1], [9.3, 0.15, 0.85], [12.4, 0.12, 0.7], [15.6, 0.08, 0.6]];

/**
 * Instrument bank. roots = MIDI notes rendered (the nearest one is repitched), loop = sustain region [start, end] (s),
 * rel = release time (s), rate = render sample-rate cap (Hz). The recipe receives the root frequency.
 */
export const INSTRUMENTS = {
  str_short: {
    roots: [33, 40, 47, 54, 61, 68, 75], len: 0.6, level: -14, rate: 32000, rel: 0.12,
    recipe(k, f) {
      k.saws({ len: 0.58, f, voices: 4, spread: 14, drive: 2, filter: [{ type: 'highpass', f: f * 0.9, q: 0.5 }, { type: 'lowpass', f: [[0, f * 4], [0.012, Math.min(f * 32, 8000)], [0.12, Math.min(f * 16, 4500)], [0.5, Math.min(f * 9, 3000)]], q: 0.9 }], env: [[0, 0], [0.006, 1], [0.08, 0.55, 'outQuad'], [0.3, 0.3], [0.56, 0, 'inQuad']] });
      k.hiss({ len: 0.1, f: 2600, q: 1.2, env: { a: 0.002, d: 0.05 }, gain: 0.12 });
    },
  },
  str_long: {
    roots: [31, 38, 45, 52], len: 2.4, loop: [0.8, 2.3], level: -16, rate: 32000, rel: 0.9,
    recipe(k, f) {
      const env = [[0, 0], [0.45, 1, 'outQuad'], [2.4, 1]];
      k.saws({ len: 2.4, f, voices: 6, spread: 16, filter: { type: 'lowpass', f: Math.min(f * 9, 4200), q: 0.6 }, env, vibrato: { rate: 5.2, depth: 9, delay: 0.35 } });
      k.hiss({ len: 2.4, f: Math.min(f * 10, 6000), q: 0.8, env, gain: 0.025 });
    },
  },
  brass: {
    roots: [48, 55, 62, 69], len: 2.4, loop: [1.5, 2.3], level: -14, rate: 32000, rel: 0.45,
    recipe(k, f) {
      // sforzando bite, dip, then a crescendo; brightness follows loudness like a real brass section
      const amp = k.fn([[0, 0], [0.03, 0.75, 'outQuad'], [0.3, 0.42], [1.4, 1, 'inQuad'], [2.4, 1]]);
      k.saws({ len: 2.4, f, voices: 3, spread: 7, drive: 1.6, env: amp, vibrato: { rate: 4.8, depth: 6, delay: 1.0 }, filter: { type: 'lowpass', f: (t) => f * (1.4 + 9 * Math.pow(amp(t), 1.7)), q: 1.3 } });
    },
  },
  choir: {
    roots: [50, 57, 64, 71], len: 3.0, loop: [1.2, 2.85], level: -16, rate: 32000, rel: 1.4,
    recipe(k, f) {
      const mix = k.ac.createGain();
      mix.gain.value = 0.4;
      for (let i = 0; i < 6; i++) {
        const o = k.osc('sawtooth', f, 0, 3);
        o.detune.value = (i - 2.5) * 7 + k.r(-3, 3);
        const lfo = k.osc('sine', k.r(4.2, 5.6), 0, 3), lg = k.ac.createGain();
        lg.gain.value = k.r(8, 16);
        lfo.connect(lg); lg.connect(o.detune);
        o.connect(mix);
      }
      const env = [[0, 0], [0.9, 1, 'inOutSine'], [3, 1]];
      k.send(k.chain(k.formant(mix, [[600, 1, 5], [1040, 0.55, 7], [2650, 0.25, 10], [3350, 0.1, 12]]), k.filter('lowpass', 5000), k.env(env)), 1);
      k.hiss({ len: 3, f: 1500, q: 1, env, gain: 0.03 });
    },
  },
  taiko: { roots: [36], len: 1.4, level: -10, rel: 0.2, recipe(k) { k.taiko({ f: 62, len: 1.35 }); } },
  ka: {
    roots: [72], len: 0.25, level: -16, rel: 0.05,
    recipe(k) {
      k.click({ gain: 0.6, f: 1800, type: 'bandpass', q: 1.2, d: 0.006 });
      k.modal({ f: 980, partials: [[1, 0.5, 0.07], [2.3, 0.3, 0.05], [3.7, 0.2, 0.035]], gain: 0.7 });
      k.hiss({ len: 0.1, f: 3500, q: 1.5, env: { a: 0, d: 0.03 }, gain: 0.4 });
    },
  },
  shime: {
    roots: [72], len: 0.2, level: -17, rel: 0.05,
    recipe(k) {
      k.thump({ f0: 520, f1: 380, drop: 0.01, len: 0.12, gain: 0.6, drive: 0 });
      k.modal({ f: 400, partials: [[1, 0.4, 0.1], [1.59, 0.25, 0.07]], gain: 0.4 });
      k.hiss({ len: 0.08, f: 3000, q: 1, env: { a: 0, d: 0.035 }, gain: 0.5 });
    },
  },
  crash: {
    roots: [60], len: 2.6, channels: 2, level: -16, rate: 32000, rel: 0.3,
    recipe(k) {
      k.hiss({ len: 2.5, type: 'highpass', f: 2800, post: { type: 'lowpass', f: [[0, 14000], [2.5, 5000]] }, env: { a: 0.002, h: 0.02, d: 2.3 }, gain: 0.9, stereo: true });
      k.modal({ f: 430, partials: CYMBAL.map(([r, a, d]) => [r, a, d * 2]), gain: 0.2, beat: 7 });
      k.click({ gain: 0.4, f: 4000 });
    },
  },
  swell: {
    roots: [60], len: 1.7, channels: 2, reverse: true, level: -16, rate: 32000, rel: 0.1,
    recipe(k) {
      k.hiss({ len: 1.65, type: 'highpass', f: 2500, post: { type: 'lowpass', f: 9000 }, env: { a: 0.001, d: 1.6 }, gain: 0.9, stereo: true });
      k.modal({ f: 430, partials: CYMBAL.map(([r, a, d]) => [r, a, d * 1.4]), gain: 0.15, beat: 6 });
    },
  },
  tick: {
    roots: [72], len: 0.18, level: -16, rel: 0.05,
    recipe(k) {
      k.modal({ f: 3100, partials: [[1, 0.5, 0.07], [1.41, 0.35, 0.05], [2.13, 0.25, 0.04], [2.6, 0.15, 0.03]], gain: 0.6 });
      k.hiss({ len: 0.08, type: 'highpass', f: 6000, env: { a: 0, d: 0.04 }, gain: 0.5 });
    },
  },
  bell: { roots: [69, 76], len: 5, level: -14, rate: 32000, rel: 1, recipe(k, f) { k.bell({ f, decay: 4.2, bright: 0.8 }); } },
  pulse: {
    roots: [36], len: 0.6, level: -12, rel: 0.1,
    recipe(k) {
      k.thump({ f0: 95, f1: 44, drop: 0.04, len: 0.5, drive: 1.8 });
      k.hiss({ len: 0.2, type: 'lowpass', f: 300, env: { a: 0.002, d: 0.12 }, gain: 0.4 });
    },
  },
  drone: {
    roots: [38], len: 5.5, loop: [1.6, 5.3], channels: 2, rate: 24000, level: -16, rel: 2,
    recipe(k, f) {
      const d = 5.5, env = [[0, 0], [1.4, 1, 'inOutSine'], [d, 1]], s = k.smooth(0.35);
      k.saws({ len: d, f: f / 2, voices: 3, spread: 6, filter: { type: 'lowpass', f: 240, q: 1.5 }, env, drive: 1.4, gain: 0.5 });
      k.saws({ len: d, f: f * Math.pow(2, 1 / 12), voices: 3, spread: 12, filter: { type: 'lowpass', f: 900 }, env, gain: 0.45, pan: 0.3 });
      k.saws({ len: d, f, voices: 3, spread: 9, filter: { type: 'lowpass', f: 1000 }, env, gain: 0.55, pan: -0.3 });
      k.saws({ len: d, f: f * 4 * Math.pow(2, 1 / 12), voices: 3, spread: 14, filter: { type: 'lowpass', f: 2400 }, env, gain: 0.15, am: { rate: 0.4, depth: 0.6 } });
      k.hiss({ len: d, stereo: true, color: 'pink', f: (t) => 220 + 380 * s(t), q: 2, env, gain: 0.35, am: { rate: 0.5, depth: 0.5 } });
    },
  },
  trem: {
    roots: [62, 69, 76], len: 2.2, loop: [0.8, 2.1], rate: 32000, level: -18, rel: 0.6,
    recipe(k, f) {
      const j = k.smooth(3);
      k.saws({ len: 2.2, f, voices: 4, spread: 12, filter: { type: 'lowpass', f: Math.min(f * 6, 5000), q: 0.7 }, env: [[0, 0], [0.5, 1, 'outQuad'], [2.2, 1]], am: (t) => 0.35 + 0.65 * Math.pow(Math.abs(Math.sin(Math.PI * (12.5 * t + 0.3 * j(t)))), 0.7) });
    },
  },
  air: {
    roots: [60], len: 5, loop: [0.8, 4.8], channels: 2, rate: 24000, level: -20, rel: 1.5,
    recipe(k) {
      const d = 5, env = [[0, 0], [0.8, 1], [d, 1]], s = k.smooth(0.25);
      k.hiss({ len: d, stereo: true, color: 'pink', f: (t) => 350 + 450 * s(t), q: 0.6, env, gain: 0.8, am: { rate: 0.3, depth: 0.6 } });
      k.hiss({ len: d, stereo: true, type: 'highpass', f: 4000, env, gain: 0.08, am: { rate: 0.5, depth: 0.7 } });
    },
  },
};

// ---- compositions ----

const NOTE = { C: 36, D: 38, Eb: 39, E: 40, F: 41, G: 31, A: 33, Bb: 34 };
const chord = (s) => { const q = s.endsWith('m'); const r = NOTE[q ? s.slice(0, -1) : s]; return { r, t: q ? 3 : 4 }; };
/** chord tones (root, third, fifth) of c in the MIDI range [lo, hi] */
const voicing = (c, lo, hi) => {
  const out = [];
  for (let o = 0; o < 8; o++) for (const iv of [0, c.t, 7]) { const m = c.r + o * 12 + iv; if (m >= lo && m <= hi) out.push(m); }
  return out.sort((a, b) => a - b);
};

const B_PROG = ['Dm', 'Dm', 'Bb', 'C', 'Dm', 'Dm', 'Gm', 'A', 'Bb', 'C', 'Dm', 'Dm', 'Bb', 'C', 'Eb', 'A'].map(chord);
/** low-string ostinato: [interval ('t' = third, 'T' = tenth), velocity] per 16th; accents 1, 4, 7 | 9, 12, 15 (3+3+2) */
const OST = [[0, 1], [0, 0.42], [0, 0.5], [12, 0.8], [0, 0.42], [0, 0.5], [7, 0.85], [0, 0.45], [0, 0.95], [0, 0.42], [0, 0.5], [12, 0.8], [0, 0.42], ['T', 0.6], [7, 0.8], [12, 0.55]];
/** violin figure two octaves up (lift layer) */
const VIO = [12, 7, 't', 7, 12, 7, 't', 7, 12, 7, 't', 7, 'T', 12, 7, 12];
const ACCENT = new Set([0, 3, 6, 8, 11, 14]);
const BIG = { 0: 1, 6: 0.7, 10: 0.85 };
/** horn line for the B section: [bar (of 16), step, midi, length in steps] */
const HORN = [[8, 0, 65, 8], [8, 8, 67, 4], [8, 12, 69, 4], [9, 0, 67, 12], [9, 12, 64, 4], [10, 0, 62, 24], [11, 8, 57, 8],
  [12, 0, 65, 8], [12, 8, 67, 4], [12, 12, 69, 4], [13, 0, 72, 12], [13, 12, 70, 4], [14, 0, 70, 8], [14, 8, 67, 8], [15, 0, 69, 16]];

function battleStep(n, t, P, st) {
  const bar = Math.floor(n / 16), s = n % 16, bi = bar % 16, sec = bi >= 8, c = B_PROG[bi], I = st.intensity, bd = P.barDur, sd = P.stepDur;
  const ivOf = (o) => (o === 't' ? c.t : o === 'T' ? c.t + 12 : o);
  const [o, v] = OST[s];
  const iv = ivOf(o);
  // base: low strings + violas an octave up on the galloping ostinato, quiet contrabass pedal, downbeat drum, shime 8ths
  P.note('str_short', c.r + iv, t, { vel: v * 0.72, dur: sd * 0.9, pan: -0.2 });
  P.note('str_short', c.r + 12 + iv, t, { vel: v * 0.62, dur: sd * 0.85, pan: 0.2 });
  if (s === 0) { P.note('str_long', c.r - 12, t, { vel: 0.22, dur: bd * 0.98 }); P.note('taiko', 36, t, { vel: 0.55 }); }
  if (s % 4 === 2) P.note('shime', 72, t, { vel: 0.3, pan: -0.35 });
  // drums layer
  if (BIG[s]) P.note('taiko', 36, t, { vel: BIG[s] * 0.85, layer: 'drums' });
  if (s === 12 || s === 14) P.note('taiko', 43, t, { vel: s === 12 ? 0.5 : 0.62, layer: 'drums', pan: 0.25 });
  if (s === 4 || s === 12) P.note('ka', 72, t, { vel: 0.8, layer: 'drums', pan: 0.15 });
  if (s === 7 || s === 15) P.note('ka', 72, t, { vel: 0.35, layer: 'drums', pan: 0.15 });
  if (s % 2 === 1) P.note('shime', 72, t, { vel: I > 0.75 ? 0.25 : 0.15, layer: 'drums', pan: -0.35 });
  if (s % 2 === 0) P.note('tick', s % 4 === 0 ? 74 : 72, t, { vel: s % 8 === 4 ? 0.75 : 0.5, layer: 'drums', pan: 0.4 });
  if (bar % 4 === 3 && s >= 12 && I > 0.55) P.note('taiko', 38, t, { vel: 0.4 + (s - 12) * 0.14, layer: 'drums' });
  // lift layer
  if (s === 0 && bar % 2 === 0) voicing(c, 50, 64).forEach((m, i, a) => P.note('brass', m, t, { vel: 0.65, dur: bd * 1.95, swell: 0.85, layer: 'lift', pan: (i - (a.length - 1) / 2) * 0.2 }));
  P.note('str_short', c.r + 24 + ivOf(VIO[s]), t, { vel: ACCENT.has(s) ? 0.6 : 0.42, dur: sd * 0.8, layer: 'lift', pan: 0.35 });
  if (s === 0 && bar % 2 === 0 && (sec || bi >= 4)) voicing(c, 57, 69).forEach((m, i) => P.note('choir', m, t, { vel: 0.6, dur: bd * 1.95, layer: 'lift', pan: (i - 1) * 0.35 }));
  if (bi % 4 === 0 && s === 0) P.note('crash', 60, t, { vel: bi % 8 === 0 ? 0.75 : 0.5, layer: 'lift' });
  if (bi % 8 === 7 && s === 0) P.note('swell', 60, t + bd - P.len('swell'), { vel: 0.6, layer: 'lift' });
  if (sec && I > 0.8) for (const [b, hs, m, l] of HORN) if (b === bi && hs === s) P.note('brass', m, t, { vel: 0.72, dur: l * P.stepDur * 0.95, layer: 'lift', pan: 0.1 });
}

const T_CH = [[50, 57, 64, 65], [46, 53, 57, 62], [55, 58, 62, 69], [57, 62, 64, 67]];
const T_BASS = [38, 34, 31, 33];
/** lone bell motif: [bar, step, midi] */
const T_BELL = [[0, 0, 69], [0, 8, 74], [1, 0, 72], [2, 0, 69], [2, 8, 65], [3, 0, 67], [4, 0, 74], [5, 0, 70], [5, 8, 69], [6, 0, 64], [6, 8, 73]];

function titleStep(n, t, P) {
  const bar = Math.floor(n / 16) % 8, s = n % 16, bd = P.barDur;
  if (s === 0 && bar % 2 === 0) {
    T_CH[bar / 2].forEach((m, i) => P.note('choir', m, t, { vel: 0.5, dur: bar === 6 && m === 62 ? bd : bd * 2.02, pan: (i - 1.5) * 0.35 }));
    if (bar === 6) P.note('choir', 61, t + bd, { vel: 0.5, dur: bd * 1.02, pan: 0.17 });
    P.note('str_long', T_BASS[bar / 2], t, { vel: 0.5, dur: bd * 2.02 });
  }
  if (s === 0 && bar === 0) P.note('air', 60, t, { vel: 0.6, dur: bd * 8.1 });
  if (s === 0 && (bar === 0 || bar === 4)) P.note('taiko', 31, t, { vel: 0.35 });
  for (const [b, bs, m] of T_BELL) if (b === bar && bs === s) P.note('bell', m, t, { vel: 0.55, pan: 0.2 });
}

function ultimateStep(n, t, P) {
  const bar = Math.floor(n / 16), s = n % 16, bd = P.barDur;
  if (n === 0) P.note('drone', 38, t, { vel: 0.8, dur: Infinity });
  if (s === 0 || s === 8) P.note('pulse', 36, t, { vel: 0.75 });
  if (s === 3 || s === 11) P.note('pulse', 36, t, { vel: 0.45 });
  if (s === 0 && bar % 2 === 0) {
    const sh = [0, 2, 4, 6][(bar / 2) % 4];
    [62 + sh, 63 + sh, 69 + sh].forEach((m, i) => P.note('trem', m, t, { vel: 0.62, dur: bd * 2.02, swell: 0.9, pan: (i - 1) * 0.4 }));
    P.note('brass', 50, t, { vel: 0.42, dur: bd * 0.9 });
    P.note('brass', 51, t, { vel: 0.38, dur: bd * 0.9 });
  }
  if (s === 0 && bar % 4 === 3) P.note('swell', 60, t + bd - P.len('swell'), { vel: 0.55 });
}

function victoryStep(n, t, P) {
  const sd = P.stepDur;
  const stab = (notes, dur, vel) => notes.forEach((m, i) => P.note('brass', m, t, { vel, dur, pan: (i - 1.5) * 0.25 }));
  if (n === 0) {
    P.note('taiko', 36, t, { vel: 1 }); P.note('crash', 60, t, { vel: 0.7 });
    stab([46, 53, 58, 62], sd * 5.5, 0.8); P.note('str_long', 34, t, { vel: 0.6, dur: sd * 5.5 });
  }
  if (n === 6) { P.note('taiko', 38, t, { vel: 0.8 }); stab([48, 55, 60, 64], sd * 5.5, 0.8); P.note('str_long', 36, t, { vel: 0.6, dur: sd * 5.5 }); }
  if (n === 12) { stab([45, 52, 57, 62], sd * 4, 0.75); P.note('str_long', 33, t, { vel: 0.6, dur: sd * 4 }); }
  if (n >= 12 && n < 16) P.note('taiko', 36 + (n - 12), t, { vel: 0.5 + (n - 12) * 0.15 });
  if (n === 16) {
    stab([50, 57, 62, 66], sd * 30, 0.9);
    [62, 66, 69, 74].forEach((m, i) => P.note('choir', m, t, { vel: 0.55, dur: sd * 30, pan: (i - 1.5) * 0.3 }));
    P.note('str_long', 38, t, { vel: 0.65, dur: sd * 30 }); P.note('str_long', 50, t, { vel: 0.5, dur: sd * 30 });
    P.note('taiko', 36, t, { vel: 1 }); P.note('crash', 60, t, { vel: 0.8 }); P.note('bell', 74, t, { vel: 0.6 });
  }
  if (n === 24) P.note('bell', 69, t, { vel: 0.5 });
  if (n === 32) { P.note('bell', 74, t, { vel: 0.45 }); P.note('taiko', 33, t, { vel: 0.5 }); }
}

/**
 * Track definitions. gain: track trim. layers: name -> intensity ramp [from, to] (null = always on). fadeIn: fixed
 * entry fade (s) for tracks with a strong downbeat (otherwise the music() fade is used). steps: total length
 * (non-looping tracks). overlay: plays over the current track instead of replacing it.
 */
export const TRACKS = {
  title: { bpm: 54, gain: 1.7, verb: 0.55, layers: { base: null }, instruments: ['choir', 'str_long', 'bell', 'taiko', 'air'], step: titleStep },
  battle: { bpm: 140, gain: 1, verb: 0.2, fadeIn: 0.05, layers: { base: null, drums: [0.15, 0.5], lift: [0.5, 0.85] }, instruments: ['str_short', 'str_long', 'taiko', 'ka', 'shime', 'tick', 'brass', 'choir', 'crash', 'swell'], step: battleStep },
  ultimate: { bpm: 140, gain: 1.5, verb: 0.3, overlay: true, layers: { base: null }, instruments: ['drone', 'pulse', 'trem', 'swell', 'brass'], step: ultimateStep },
  victory: { bpm: 84, gain: 1, verb: 0.4, fadeIn: 0.05, steps: 64, layers: { base: null }, instruments: ['brass', 'choir', 'str_long', 'taiko', 'crash', 'bell'], step: victoryStep },
};

const layerLevel = (range, x) => (range ? smoothstep(range[0], range[1], x) : 1);

/** Schedule one sample note. Notes scheduled in the past start immediately at the right offset. */
function playSample(ac, dest, s, midi, t, { vel = 0.8, dur, pan = 0, swell = 0 }) {
  const rate = Math.pow(2, (midi - s.root) / 12);
  let off = 0;
  if (t < ac.currentTime) { off = (ac.currentTime - t) * rate; t = ac.currentTime; if (!s.loop && off >= s.buffer.duration) return null; }
  const src = ac.createBufferSource();
  src.buffer = s.buffer;
  src.playbackRate.value = rate;
  const g = ac.createGain(), peak = Math.pow(vel, 1.5);
  const held = dur === Infinity, timed = dur != null && Number.isFinite(dur);
  if (swell && timed) { g.gain.setValueAtTime(peak * 0.25, t); g.gain.linearRampToValueAtTime(peak, t + dur * swell); } else g.gain.setValueAtTime(peak, t);
  if (s.loop && (held || (timed && dur > s.loop[0]))) { src.loop = true; src.loopStart = s.loop[0]; src.loopEnd = s.loop[1]; }
  src.connect(g);
  let tail = g;
  if (pan && ac.createStereoPanner) { const p = ac.createStereoPanner(); p.pan.value = pan; g.connect(p); tail = p; }
  tail.connect(dest);
  src.onended = () => { try { tail.disconnect(); g.disconnect(); } catch (e) { /* already gone */ } };
  src.start(t, off);
  if (timed) { g.gain.setTargetAtTime(0, t + dur, s.rel / 4); src.stop(t + dur + s.rel * 1.6); }
  return src;
}

/**
 * Create a sequencer for a track on any (Offline)AudioContext.
 * @param {BaseAudioContext} ac
 * @param {{pick(inst: string, midi: number): object|null, duration(inst: string): number}} bank  rendered samples
 * @param {string} name   track name (TRACKS)
 * @param {{dest: AudioNode, verb: AudioNode, t0: number, intensity?: number, fadeIn?: number}} o
 */
export function createSequencer(ac, bank, name, { dest, verb, t0, intensity = 0.5, fadeIn = 0.05 }) {
  const def = TRACKS[name];
  const stepDur = 60 / def.bpm / 4;
  const fade = ac.createGain(), muff = ac.createGain(), lp = ac.createBiquadFilter(), send = ac.createGain();
  muff.gain.value = def.gain;
  fade.gain.value = 0;
  fade.gain.setValueAtTime(0, t0);
  fade.gain.linearRampToValueAtTime(1, t0 + Math.max(0.01, fadeIn));
  lp.type = 'lowpass'; lp.frequency.value = ac.sampleRate / 2; lp.Q.value = 0;
  send.gain.value = def.verb;
  fade.connect(muff); muff.connect(lp); lp.connect(dest); lp.connect(send); send.connect(verb);
  const layers = {};
  for (const [ln, range] of Object.entries(def.layers)) {
    const g = ac.createGain();
    g.gain.value = layerLevel(range, intensity);
    g.connect(fade);
    layers[ln] = g;
  }
  const st = { intensity, held: [] };
  const P = {
    stepDur, barDur: stepDur * 16,
    len: (inst) => bank.duration(inst),
    note(inst, midi, t, o = {}) {
      const s = bank.pick(inst, midi);
      if (!s) return;
      const src = playSample(ac, layers[o.layer || 'base'], s, midi, t, o);
      if (src && o.dur === Infinity) st.held.push(src);
    },
  };
  let n = 0;
  const seq = {
    name, t0, stepDur, ended: false,
    /** Schedule every step that starts before `until` (context time). */
    tick(until) {
      while (!seq.ended && t0 + n * stepDur < until) {
        def.step(n, t0 + n * stepDur, P, st);
        n++;
        if (def.steps && n >= def.steps) seq.ended = true;
      }
    },
    /** Intensity 0..1: layer gains glide with time constant `tc`. */
    setIntensity(x, tc = 0.5) {
      st.intensity = x;
      for (const [ln, range] of Object.entries(def.layers)) layers[ln].gain.setTargetAtTime(layerLevel(range, x), ac.currentTime, tc);
    },
    /** Context time of the next beat at or after t. */
    nextBeat(t) { return t0 + Math.max(0, Math.ceil((t - t0) / (stepDur * 4))) * stepDur * 4; },
    /** Low-pass + attenuate (another track overlays this one). */
    muffle(on, dur = 0.5) {
      const now = ac.currentTime;
      lp.frequency.setTargetAtTime(on ? 1600 : ac.sampleRate / 2, now, dur / 3);
      muff.gain.setTargetAtTime(def.gain * (on ? 0.7 : 1), now, dur / 3);
    },
    /** Fade out over `sec` and stop scheduling; held notes stop after the fade. */
    stop(sec) {
      const now = ac.currentTime;
      seq.ended = true;
      fade.gain.cancelScheduledValues(now);
      fade.gain.setValueAtTime(fade.gain.value, now);
      fade.gain.linearRampToValueAtTime(0, now + Math.max(0.02, sec));
      for (const s of st.held) { try { s.stop(now + sec + 0.05); } catch (e) { /* already stopped */ } }
    },
    /** Detach from the mix (after the fade has finished). */
    disconnect() { try { lp.disconnect(); send.disconnect(); } catch (e) { /* already gone */ } },
  };
  return seq;
}
