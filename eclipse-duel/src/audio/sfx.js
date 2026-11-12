// Sound library: every SFX of the game as a layered recipe (transient + body + tail), rendered once by kit.js.
//
// Meta fields (defaults in BASE; see README.md):
//   len (s) render length    level (dB) loudness target, K-weighted 100 ms max    channels 1 | 2
//   variants     pre-rendered takes (picked at random, never the same take twice in a row)
//   poly         max simultaneous voices of this name      throttle (s) min retrigger interval
//   pitchVar     +- semitones per play    volVar (dB) +- per play    panVar +- random pan
//   verb         hall reverb send 0..1    bus 'world' (follows slow-mo) | 'ui' (unaffected by slow-mo)
//   prio         0..10 voice-steal priority    clip  soft-clip overshoot allowed (>1 = louder, punchier transient)
//   loop         true = seamless loop asset    duck {amount, dur} music duck on play    maxLate (s)
//   role         measurement class (analyze.js)    group  lab grouping    desc  one-line description

/** @type {Record<string, object>} */
export const SOUNDS = {};

/** Alternative names accepted by audio.play / audio.loop. */
export const ALIASES = { whoosh_light: 'swing_light', whoosh_heavy: 'swing_heavy', whoosh_huge: 'swing_huge' };

const BASE = {
  len: 1, level: -14, channels: 1, variants: 1, poly: 3, throttle: 0.03, pitchVar: 0.5, volVar: 1, panVar: 0, verb: 0.15,
  bus: 'world', prio: 5, clip: 1, loop: false, duck: null, maxLate: 0.12, role: 'fx', group: 'misc', desc: '',
};

/**
 * Register (or replace) a sound.
 * @param {string} name
 * @param {object} meta     see the field list above
 * @param {(k: object, arg: any, variant: number) => (void|Promise<void>)} recipe  builds the graph with the kit
 */
export function defineSound(name, meta, recipe) {
  SOUNDS[name] = { ...BASE, ...meta, name, recipe };
  return SOUNDS[name];
}
const S = defineSound;

// ---- shared partial sets and layer helpers ----

/** steel blade / armour edge ring (inharmonic) */
const STEEL = [[1, 0.32, 0.5], [1.47, 0.26, 0.42], [2.09, 0.2, 0.34], [2.56, 0.16, 0.28], [3.9, 0.1, 0.2], [5.2, 0.06, 0.14]];
/** thick plate (shield / pauldron) */
const PLATE = [[1, 0.5, 0.55], [1.33, 0.34, 0.5], [1.72, 0.3, 0.42], [2.27, 0.27, 0.36], [2.81, 0.2, 0.3], [3.53, 0.15, 0.24], [4.48, 0.1, 0.18], [5.9, 0.07, 0.12]];
/** glass / ice body (free-plate ratios) */
const GLASS = [[1, 0.4, 0.35], [2.76, 0.3, 0.25], [5.4, 0.2, 0.18], [8.93, 0.12, 0.1]];
/** low gong body for cinematic punctuation */
const GONG = [[1, 0.5, 1.5], [2.1, 0.3, 1], [2.9, 0.2, 0.8], [4.2, 0.12, 0.5], [5.3, 0.08, 0.4]];
const FLAT = (d) => [[0, 1], [d, 1]];
const hz = (m) => 440 * Math.pow(2, (m - 69) / 12);

/** Fire crackle: sparse sharp noise grains (power-law amplitudes) plus occasional darker pops. */
function crackle(k, { at = 0, len, rate, gain = 0.35, hp = 1200 }) {
  const times = k.poisson(len, rate);
  k.grains({ at, len, times, kind: 'noise', lp: 0.9, decay: [0.0008, 0.006], amp: [0.05, 1], pow: 3, spread: 0.85, gain, filter: { type: 'highpass', f: hp } });
  k.grains({ at, len, times: times.filter((_, i) => i % 6 === 3), kind: 'noise', lp: 0.25, decay: [0.006, 0.02], amp: [0.2, 0.9], gain: gain * 0.7, filter: { type: 'bandpass', f: 900, q: 0.8 } });
}

/** Debris tail: chunks (coloured noise bursts) and pebbles (short pings), Poisson-timed, spread wide. */
function debris(k, { at = 0, len, rate, gain = 0.3, f = 2000 }) {
  k.grains({ at, len, times: k.poisson(len, rate), kind: 'noise', lp: 0.35, decay: [0.004, 0.03], amp: [0.08, 1], pow: 2.2, spread: 0.95, gain, filter: { type: 'bandpass', f, q: 0.6 } });
  k.grains({ at, len, times: k.poisson(len, (t) => rate(t) * 0.6), kind: 'ping', f: [900, 3800], decay: [0.005, 0.025], amp: [0.05, 0.6], spread: 0.95, gain: gain * 0.35 });
}

/** Brass/string chord stab (orchestral hit): detuned saws, filter blat, fast decay to a held tail. */
function stab(k, { at = 0, notes, len = 1.8, gain = 0.32, drive = 1.6, bright = 3500 }) {
  notes.forEach((f, i) => k.saws({
    at, len, f, voices: 3, spread: 14, drive, gain, pan: (i - (notes.length - 1) / 2) * 0.22,
    filter: { type: 'lowpass', f: [[0, 350], [0.025, bright, 'outQuad'], [0.35, bright * 0.35], [len, 500]], q: 1.1 },
    env: [[0, 0], [0.012, 1], [0.25, 0.5], [len, 0, 'outQuad']],
  }));
}

/** Crash cymbal: wide high noise wash with a darkening top and a few metallic partials. */
function crash(k, { at = 0, len = 2.4, gain = 0.3 }) {
  k.hiss({ at, len, type: 'highpass', f: 3000, post: { type: 'lowpass', f: [[0, 15000], [len, 5000]] }, env: { a: 0.002, h: 0.02, d: len * 0.9 }, gain, stereo: true });
  k.modal({ at, f: 430, partials: [[7.1, 0.2, len * 0.6], [9.3, 0.15, len * 0.5], [12.4, 0.12, len * 0.4], [15.6, 0.08, len * 0.35]], gain: gain * 0.25, beat: 9 });
}

// ============================================================================================ weapon whooshes

S('swing_light', {
  group: 'weapon', role: 'whoosh', len: 0.42, level: -20, channels: 2, variants: 4, poly: 4, throttle: 0.04, pitchVar: 1.4, volVar: 1.5, verb: 0.1, prio: 4,
  desc: 'quick blade whoosh: moving band-pass air, thin blade sing, doppler drop',
}, (k) => {
  const len = k.j(0.36, 0.08), pk = k.j(0.4, 0.1);
  k.whoosh({ len, peak: pk, sharp: 1.3, fLo: k.j(650), fHi: k.j(3200), q: 1.4, doppler: 0.1, air: 0.45, pan: [-0.3, 0.35], tone: { fLo: 1100, fHi: 2900, gain: 0.05 } });
  k.whoosh({ len: len * 0.9, peak: pk, fLo: 2400, fHi: 6500, q: 2.2, gain: 0.35, doppler: 0.12, pan: [-0.2, 0.3] });
});

S('swing_heavy', {
  group: 'weapon', role: 'whoosh', len: 0.62, level: -17, channels: 2, variants: 3, poly: 3, throttle: 0.05, pitchVar: 1.2, volVar: 1.2, verb: 0.12, prio: 5,
  desc: 'weighty arc: two moving noise bands, low "vwomp" tone bending down through the pass, sub air push',
}, (k) => {
  const len = k.j(0.56, 0.06), pk = k.j(0.46, 0.06);
  k.whoosh({ len, peak: pk, sharp: 1.6, fLo: k.j(320), fHi: k.j(1500), q: 1.0, doppler: 0.12, air: 0.25, pan: [-0.45, 0.45], flutter: { rate: [8, 18], depth: 0.25 }, tone: { fLo: 140, fHi: 330, gain: 0.12, type: 'triangle' }, sub: { f: 220, gain: 0.6 } });
  k.whoosh({ len: len * 0.92, peak: pk, fLo: 1300, fHi: 4200, q: 2, gain: 0.3, doppler: 0.14, pan: [-0.35, 0.4] });
});

S('swing_huge', {
  group: 'weapon', role: 'whoosh', len: 1.05, level: -14, channels: 2, variants: 2, poly: 2, throttle: 0.08, pitchVar: 1, volVar: 1, verb: 0.15, prio: 6,
  desc: 'greatsword-scale arc: rotor flutter, roaring band noise, doppler-dropping drone, sub pressure wave',
}, (k) => {
  const len = k.j(0.98, 0.05);
  k.whoosh({ len, peak: 0.5, sharp: 2, fLo: k.j(180), fHi: k.j(1000), q: 0.85, doppler: 0.16, air: 0.3, pan: [-0.7, 0.7], flutter: { rate: [5, 15], depth: 0.5 }, tone: { fLo: 70, fHi: 190, gain: 0.18, type: 'sawtooth' }, sub: { f: 160, gain: 1 } });
  k.whoosh({ len: len * 0.94, peak: 0.51, fLo: 800, fHi: 3000, q: 1.8, gain: 0.32, doppler: 0.18, pan: [-0.5, 0.6], flutter: { rate: [6, 16], depth: 0.35 } });
});

// ============================================================================================ combat impacts

S('hit_slash_light', {
  group: 'combat', role: 'hit', len: 0.5, level: -14, variants: 4, poly: 5, throttle: 0.035, pitchVar: 1, verb: 0.12, clip: 1.3, prio: 7,
  desc: 'clean cut: hard click, bright slice, short steel ring, flesh body, small sub knock',
}, (k) => {
  k.click({ gain: 0.9, f: 2500 });
  k.hiss({ len: 0.18, f: k.j(4200, 0.1), q: 0.9, env: { a: 0.0008, d: 0.1 }, gain: 0.7, drive: 1.5 });
  k.modal({ f: k.j(2100, 0.06), partials: STEEL, beat: 4, gain: 0.3, bend: 0.4 });
  k.hiss({ len: 0.2, type: 'lowpass', f: 1300, env: { a: 0.001, d: 0.08 }, gain: 0.75, drive: 2 });
  k.thump({ f0: 270, f1: 150, drop: 0.02, len: 0.08, gain: 0.45, drive: 1.5 });
  k.thump({ f0: 150, f1: 65, drop: 0.035, len: 0.14, gain: 0.4, drive: 1.6 });
  k.hiss({ len: 0.45, type: 'highpass', f: 5500, env: { a: 0.002, d: 0.36 }, gain: 0.12 });
});

S('hit_slash_heavy', {
  group: 'combat', role: 'hit', len: 0.95, level: -10, variants: 3, poly: 4, throttle: 0.035, pitchVar: 0.8, verb: 0.16, clip: 1.4, prio: 8,
  desc: 'heavy cleave: click + driven crack, bending steel ring, chunky body, saturated sub drop, sizzle tail',
}, (k) => {
  k.click({ gain: 1, f: 2000 });
  k.hiss({ len: 0.2, f: k.j(2600, 0.1), q: 0.7, env: { a: 0.0005, d: 0.1 }, gain: 0.9, drive: 3 });
  k.modal({ f: k.j(1180, 0.05), partials: STEEL, beat: 2.5, gain: 0.4, bend: 0.6, bendTime: 0.025 });
  k.hiss({ len: 0.4, type: 'lowpass', f: [[0, 2400], [0.25, 600]], env: { a: 0.001, d: 0.18 }, gain: 0.95, drive: 2.5 });
  k.thump({ f0: 250, f1: 115, drop: 0.03, len: 0.14, gain: 0.6, drive: 2 });
  k.thump({ f0: 120, f1: 45, drop: 0.07, len: 0.42, gain: 0.6, drive: 2.2 });
  k.hiss({ len: 0.6, type: 'highpass', f: 6000, env: { a: 0.004, d: 0.4 }, gain: 0.12 });
});

S('hit_blunt', {
  group: 'combat', role: 'hit', len: 0.75, level: -11, variants: 3, poly: 4, throttle: 0.035, pitchVar: 0.8, verb: 0.14, clip: 1.4, prio: 7,
  desc: 'dull bone-and-armour impact: crunch grains, saturated low body, double thud with sub',
}, (k) => {
  k.click({ gain: 0.8, f: 1500, type: 'bandpass', q: 0.8, d: 0.006 });
  k.grains({ len: 0.035, count: 7, dist: 'uniform', kind: 'noise', lp: 0.5, decay: [0.003, 0.01], amp: [0.4, 1], gain: 0.8, filter: { type: 'bandpass', f: 1800, q: 0.7 } });
  k.hiss({ len: 0.4, type: 'lowpass', f: 900, env: { a: 0.001, d: 0.2 }, gain: 1, drive: 3 });
  k.thump({ f0: 230, f1: 95, drop: 0.04, len: 0.22, gain: 0.65, drive: 2.2 });
  k.thump({ f0: 95, f1: 40, drop: 0.1, len: 0.5, gain: 0.55, drive: 1.8 });
});

S('hit_crit', {
  group: 'combat', role: 'hit', len: 1.7, level: -8, poly: 2, throttle: 0.06, pitchVar: 0.6, verb: 0.22, clip: 1.5, prio: 9,
  desc: 'critical / counter hit: double transient, long bending ring + shimmer, deep sub drop, boom tail, spark glitter',
}, (k) => {
  k.click({ gain: 1, f: 1800, d: 0.005 });
  k.hiss({ len: 0.05, type: 'highpass', f: 5000, env: { a: 0, d: 0.012 }, gain: 0.8, drive: 4 });
  k.hiss({ len: 0.3, f: 3000, q: 0.6, env: { a: 0.0005, d: 0.12 }, gain: 0.7, drive: 4 });
  k.modal({ f: k.j(860, 0.04), partials: STEEL.map(([r, a, d]) => [r, a, d * 2.2]), beat: 1.8, gain: 0.45, bend: 1, bendTime: 0.04 });
  k.modal({ f: 3300, partials: [[1, 0.3, 0.25], [1.37, 0.2, 0.2], [1.93, 0.15, 0.15]], gain: 0.2 });
  k.hiss({ len: 0.6, type: 'lowpass', f: [[0, 2600], [0.35, 500]], env: { a: 0.001, d: 0.25 }, gain: 1, drive: 3 });
  k.thump({ f0: 260, f1: 120, drop: 0.03, len: 0.16, gain: 0.6, drive: 2 });
  k.thump({ f0: 115, f1: 30, drop: 0.25, len: 1.1, gain: 0.75, drive: 2.5 });
  k.rumble({ len: 1.4, f: 180, env: { a: 0.01, d: 1.2 }, gain: 0.3, rate: 4 });
  k.grains({ len: 1.2, count: 40, tau: 0.25, kind: 'ping', f: [4000, 9500], decay: [0.01, 0.06], amp: [0.1, 1], gain: 0.25 });
});

S('guard', {
  group: 'combat', role: 'hit', len: 0.85, level: -13, variants: 3, poly: 4, throttle: 0.04, pitchVar: 0.8, verb: 0.18, clip: 1.2, prio: 7,
  desc: 'blocked strike: metal-on-metal clang (plate partials with strike bend), scrape, short thud, sparks',
}, (k) => {
  k.click({ gain: 0.7, f: 3000, d: 0.003 });
  k.modal({ f: k.j(740, 0.05), partials: PLATE, beat: 3, gain: 0.5, bend: 0.8, bendTime: 0.02 });
  k.hiss({ len: 0.2, f: 3500, q: 1.5, env: { a: 0.001, d: 0.12 }, gain: 0.45 });
  k.thump({ f0: 190, f1: 95, drop: 0.03, len: 0.15, gain: 0.4, drive: 1.5 });
  k.grains({ len: 0.25, count: 14, tau: 0.08, kind: 'ping', f: [5000, 10000], decay: [0.005, 0.025], amp: [0.1, 1], gain: 0.15 });
});

S('guard_break', {
  group: 'combat', role: 'hit', len: 1.5, level: -9, channels: 2, poly: 2, throttle: 0.1, pitchVar: 0.5, verb: 0.22, clip: 1.4, prio: 8,
  desc: 'guard shattered: crack, low clang, glassy-metal shatter cloud, deflating energy sweep, sub, tinkle tail',
}, (k) => {
  k.click({ gain: 1, f: 2200, d: 0.005 });
  k.hiss({ len: 0.25, f: 2200, q: 0.7, env: { a: 0.0005, d: 0.1 }, gain: 0.6, drive: 4 });
  k.modal({ f: k.j(480, 0.04), partials: PLATE.map(([r, a, d]) => [r, a, d * 1.6]), beat: 2, gain: 0.45, bend: 1.2, bendTime: 0.03 });
  k.grains({ len: 0.8, count: 120, tau: 0.18, kind: 'glass', f: [1800, 7000], decay: [0.01, 0.09], amp: [0.08, 1], spread: 0.9, gain: 0.45 });
  k.saws({ len: 0.8, f: [[0, 320], [0.6, 55, 'outQuad']], voices: 2, spread: 20, filter: { type: 'lowpass', f: [[0, 1400], [0.6, 300]] }, env: { a: 0.01, d: 0.7 }, gain: 0.35 });
  k.hiss({ len: 0.3, type: 'lowpass', f: 1800, env: { a: 0.001, d: 0.14 }, gain: 0.7, drive: 2.5 });
  k.thump({ f0: 120, f1: 32, drop: 0.18, len: 0.8, gain: 0.65, drive: 2.2 });
  k.grains({ at: 0.15, len: 1.1, count: 25, dist: 'uniform', kind: 'ping', f: [2000, 6000], decay: [0.02, 0.12], amp: [0.05, 0.6], gain: 0.15 });
});

// ============================================================================================ movement foley

S('dodge', {
  group: 'move', role: 'whoosh', len: 0.42, level: -21, channels: 2, variants: 3, poly: 2, throttle: 0.08, pitchVar: 1.5, verb: 0.08, prio: 3,
  desc: 'evasive dash: airy high whoosh plus cloth flap flutter, crossing the stereo field',
}, (k) => {
  const len = k.j(0.34, 0.08);
  k.whoosh({ len, peak: 0.38, sharp: 1.2, fLo: 1200, fHi: 4200, q: 1.3, air: 0.6, doppler: 0.08, pan: [0.3, -0.3] });
  k.whoosh({ len: len * 0.95, peak: 0.36, fLo: 300, fHi: 900, q: 0.8, gain: 0.5, flutter: { rate: [22, 38], depth: 0.65 }, pan: [0.2, -0.2] });
});

S('step', {
  group: 'move', role: 'foley', len: 0.22, level: -26, variants: 6, poly: 4, throttle: 0.06, pitchVar: 1.2, volVar: 2, verb: 0.06, prio: 2,
  desc: 'armoured footstep on stone: low heel thud, grit scuff, faint armour jingle',
}, (k) => {
  k.thump({ f0: k.j(150), f1: 75, drop: 0.02, len: 0.08, gain: 0.35, drive: 1.6 });
  k.hiss({ len: 0.1, type: 'lowpass', f: 700, env: { a: 0.001, d: 0.04 }, gain: 0.5, drive: 1.5 });
  k.hiss({ len: 0.12, f: k.j(1800, 0.15), q: 0.8, env: { a: 0.002, d: 0.07 }, gain: 0.7 });
  k.grains({ len: 0.06, count: 6, dist: 'uniform', kind: 'noise', lp: 0.6, decay: [0.002, 0.008], amp: [0.2, 1], gain: 0.45, filter: { type: 'highpass', f: 1500 } });
  k.grains({ at: 0.005, len: 0.05, count: 3, dist: 'uniform', kind: 'ping', f: [3500, 7000], decay: [0.015, 0.04], amp: [0.2, 1], gain: 0.15 });
});

S('land', {
  group: 'move', role: 'foley', len: 0.65, level: -19, variants: 2, poly: 2, throttle: 0.08, pitchVar: 0.8, verb: 0.1, prio: 4,
  desc: 'landing from a jump: heavy thud with sub, dust and grit spray, armour rattle',
}, (k) => {
  k.thump({ f0: 200, f1: 90, drop: 0.03, len: 0.14, gain: 0.5, drive: 1.8 });
  k.thump({ f0: 110, f1: 45, drop: 0.05, len: 0.3, gain: 0.5, drive: 1.8 });
  k.hiss({ len: 0.3, type: 'lowpass', f: 900, env: { a: 0.002, d: 0.15 }, gain: 0.9, drive: 1.8 });
  k.hiss({ len: 0.4, f: 2500, q: 0.7, env: { a: 0.003, d: 0.22 }, gain: 0.45 });
  k.grains({ len: 0.3, count: 14, tau: 0.08, kind: 'noise', lp: 0.5, decay: [0.002, 0.01], amp: [0.1, 1], gain: 0.4, filter: { type: 'highpass', f: 1200 } });
  k.grains({ at: 0.01, len: 0.4, count: 10, tau: 0.15, kind: 'ping', f: [2500, 6000], decay: [0.02, 0.06], amp: [0.1, 1], gain: 0.2 });
});

S('body_fall', {
  group: 'move', role: 'foley', len: 1.1, level: -15, poly: 2, throttle: 0.1, pitchVar: 0.6, verb: 0.14, prio: 5,
  desc: 'knocked-down body: torso thud + limb/armour second hit, scattered metal clatter, dust slide',
}, (k) => {
  k.thump({ f0: 210, f1: 90, drop: 0.035, len: 0.18, gain: 0.55, drive: 2 });
  k.thump({ f0: 110, f1: 40, drop: 0.06, len: 0.4, gain: 0.55, drive: 2 });
  k.hiss({ len: 0.4, type: 'lowpass', f: 800, env: { a: 0.002, d: 0.2 }, gain: 1, drive: 2.2 });
  const t2 = k.j(0.085, 0.15);
  k.thump({ at: t2, f0: 190, f1: 75, drop: 0.03, len: 0.18, gain: 0.45, drive: 1.5 });
  k.hiss({ at: t2, len: 0.2, type: 'lowpass', f: 1200, env: { a: 0.001, d: 0.1 }, gain: 0.7, drive: 1.5 });
  k.grains({ at: 0.02, len: 0.7, count: 30, tau: 0.18, kind: 'ping', f: [1500, 5000], decay: [0.02, 0.09], amp: [0.05, 1], spread: 0.7, gain: 0.35 });
  k.grains({ at: 0.02, len: 0.5, count: 18, tau: 0.12, kind: 'noise', lp: 0.6, decay: [0.002, 0.01], amp: [0.1, 1], gain: 0.35, filter: { type: 'bandpass', f: 2500, q: 0.6 } });
  k.hiss({ at: 0.05, len: 0.8, f: 1200, q: 0.5, env: [[0, 0], [0.1, 1], [0.7, 0, 'outQuad']], gain: 0.2, stereo: true });
});

// ============================================================================================ fire (Kael)

S('fire_ignite', {
  group: 'fire', role: 'element', len: 1.0, level: -15, poly: 3, throttle: 0.06, pitchVar: 1, verb: 0.15, prio: 5,
  desc: 'flame catching: gas pop, filter-sweeping whoomph with turbulence, low roar, first crackles',
}, (k) => {
  k.thump({ f0: 180, f1: 70, drop: 0.03, len: 0.15, gain: 0.5 });
  k.hiss({ len: 0.12, type: 'lowpass', f: 1200, env: { a: 0.001, d: 0.06 }, gain: 0.4 });
  const sw = [[0, 0], [0.05, 1, 'outQuad'], [0.9, 0, 'inOutQuad']];
  k.hiss({ len: 0.95, color: 'pink', type: 'lowpass', f: [[0, 300], [0.09, 2600, 'outQuad'], [0.8, 650]], env: sw, gain: 0.9, am: { rate: 22, depth: 0.35 }, stereo: true });
  k.hiss({ len: 0.95, color: 'brown', type: 'lowpass', f: 300, env: sw, gain: 0.35, drive: 1.5 });
  k.hiss({ len: 0.95, f: [[0, 500], [0.09, 1400, 'outQuad'], [0.8, 700]], q: 0.7, env: sw, gain: 0.45, am: { rate: 16, depth: 0.4 } });
  crackle(k, { len: 0.95, rate: [[0, 0], [0.1, 70], [0.9, 8]], gain: 0.4 });
});

S('fire_burst', {
  group: 'fire', role: 'hit', len: 1.5, level: -10, poly: 3, throttle: 0.05, pitchVar: 0.8, verb: 0.2, clip: 1.3, prio: 7,
  desc: 'fireball detonation: driven transient, wide whoomph (LP sweep), sub thump, fluttering roar, dense-to-sparse crackle',
}, (k) => {
  k.click({ gain: 1.3, f: 1200, type: 'bandpass', q: 0.7, d: 0.006 });
  k.hiss({ len: 0.05, type: 'highpass', f: 2500, env: { a: 0, d: 0.02 }, gain: 1, drive: 4 });
  k.hiss({ len: 0.12, f: 1500, q: 0.6, env: { a: 0.0005, d: 0.06 }, gain: 1, drive: 3 });
  k.hiss({ len: 1.4, color: 'pink', type: 'lowpass', f: [[0, 2500], [0.03, 4500, 'outQuad'], [0.3, 1300], [1.3, 300]], env: [[0, 0], [0.004, 0.8], [0.06, 0.65], [1.3, 0, 'outCubic']], gain: 0.9, drive: 1.5, stereo: true });
  k.thump({ f0: 200, f1: 90, drop: 0.03, len: 0.15, gain: 0.5, drive: 2 });
  k.thump({ f0: 85, f1: 34, drop: 0.12, len: 0.6, gain: 0.6, drive: 2 });
  k.hiss({ len: 1.4, color: 'brown', f: 500, q: 0.5, env: { a: 0.01, d: 1.1 }, gain: 0.5, am: { rate: 18, depth: 0.5 }, stereo: true });
  crackle(k, { len: 1.4, rate: [[0, 160], [0.3, 60], [1.3, 6]], gain: 0.4 });
});

S('fire_roar', {
  group: 'fire', role: 'element', len: 2.4, level: -12, poly: 2, throttle: 0.15, pitchVar: 0.6, verb: 0.2, prio: 6,
  desc: 'sustained pillar of fire: wandering low-pass roar with turbulence, low rumble, hiss, crackle throughout',
}, (k) => {
  const env = [[0, 0], [0.3, 1, 'inQuad'], [1.4, 0.85], [2.3, 0, 'inQuad']];
  const wob = k.smooth(3);
  k.hiss({ len: 2.35, color: 'pink', type: 'lowpass', f: (t) => 700 + 1100 * wob(t), env, gain: 0.9, am: { rate: 12, depth: 0.45 }, stereo: true });
  k.hiss({ len: 2.35, color: 'pink', f: (t) => 500 + 500 * wob(t), q: 0.8, env, gain: 0.55, drive: 2, am: { rate: 9, depth: 0.5 } });
  k.hiss({ len: 2.35, color: 'brown', type: 'lowpass', f: 160, env, gain: 0.35, drive: 1.6 });
  k.hiss({ len: 2.35, f: 2500, q: 0.4, env, gain: 0.2, stereo: true });
  k.hiss({ len: 0.5, color: 'pink', type: 'lowpass', f: [[0, 300], [0.12, 2500, 'outQuad'], [0.45, 800]], env: [[0, 0], [0.04, 1], [0.45, 0]], gain: 0.6 });
  crackle(k, { len: 2.3, rate: [[0, 20], [0.3, 45], [2.0, 35], [2.3, 0]], gain: 0.3 });
});

S('fire_loop', {
  group: 'fire', role: 'loop', len: 3, loop: true, level: -22, channels: 2, poly: 2, pitchVar: 0, volVar: 0, verb: 0.1, prio: 4,
  desc: 'seamless burning bed: breathing low roar, mid flutter, steady crackle and pops',
}, (k) => {
  const d = k.dur;
  k.hiss({ len: d, color: 'brown', type: 'lowpass', f: 450, env: FLAT(d), gain: 0.45, am: { rate: 3, depth: 0.4 }, stereo: true });
  k.hiss({ len: d, color: 'pink', f: 900, q: 0.5, env: FLAT(d), gain: 0.4, am: { rate: 7, depth: 0.5 }, stereo: true });
  crackle(k, { len: d, rate: 26, gain: 0.35 });
});

S('explosion', {
  group: 'fire', role: 'big', len: 3.3, level: -7, channels: 2, poly: 3, throttle: 0.06, pitchVar: 0.6, verb: 0.3, clip: 1.5, prio: 9, duck: { amount: 0.35, dur: 0.8 },
  desc: 'big blast: driven snap, falling low-pass blast, saturated sub drop, debris rain, long rolling rumble',
}, (k) => {
  k.click({ gain: 1.3, f: 1500, d: 0.006 });
  k.hiss({ len: 0.08, type: 'highpass', f: 3000, env: { a: 0, d: 0.03 }, gain: 1.4, drive: 4 });
  k.hiss({ len: 1.6, color: 'pink', type: 'lowpass', f: [[0, 6000], [0.05, 2500], [0.4, 500], [1.5, 180]], env: { a: 0.001, d: 1.3 }, gain: 1, drive: 2.5, stereo: true });
  k.thump({ f0: 190, f1: 80, drop: 0.04, len: 0.25, gain: 0.6, drive: 2 });
  k.thump({ f0: 72, f1: 24, drop: 0.35, len: 1.8, gain: 1, drive: 2.2 });
  k.hiss({ len: 0.6, f: 700, q: 0.6, env: { a: 0.001, d: 0.45 }, gain: 0.85, drive: 2 });
  debris(k, { at: 0.12, len: 2.6, rate: k.fn([[0, 0], [0.15, 45], [2.4, 3]]), gain: 0.35 });
  k.rumble({ len: 3.25, f: 160, env: [[0, 0], [0.05, 1], [3.2, 0, 'outQuad']], gain: 0.8, rate: 2.5, depth: 0.5 });
});

// ============================================================================================ ice (Iska)

S('ice_form', {
  group: 'ice', role: 'element', len: 1.25, level: -16, poly: 2, throttle: 0.08, pitchVar: 0.8, verb: 0.22, prio: 5,
  desc: 'crystal growth: creaking micro-cracks, rising glassy pings, inharmonic shimmer, then a glass "lock" tink',
}, (k) => {
  const L = 0.66;
  k.grains({ len: 0.7, times: k.poisson(0.7, [[0, 20], [0.6, 90], [L, 0]]), kind: 'noise', lp: 0.8, decay: [0.0005, 0.003], amp: [0.1, 1], gain: 0.3, filter: { type: 'bandpass', f: 3500, q: 1 } });
  k.grains({ len: L, count: 40, dist: 'uniform', kind: 'glass', f: (t, r) => 1400 * Math.pow(4, t / L) * (0.85 + 0.3 * r()), decay: [0.03, 0.12], amp: [0.1, 1], gain: 0.35 });
  [1, 1.5, 2.4, 3.3].forEach((r, i) => k.saws({ len: 1.2, type: 'sine', voices: 2, spread: 9, f: [[0, 1400 * r], [L, 1470 * r]], env: [[0, 0], [0.6, 1, 'inQuad'], [L + 0.02, 0.6], [1.2, 0, 'outQuad']], gain: 0.07 / (i + 1), pan: (i % 2 ? 0.4 : -0.4) }));
  k.click({ at: L, gain: 0.7, f: 4000 });
  k.modal({ at: L, f: 2600, partials: GLASS, gain: 0.35, beat: 5 });
  k.thump({ at: L, f0: 150, f1: 70, drop: 0.03, len: 0.2, gain: 0.5 });
  k.hiss({ at: L, len: 0.5, type: 'highpass', f: 6000, env: { a: 0.002, d: 0.35 }, gain: 0.2, stereo: true });
});

S('ice_shatter', {
  group: 'ice', role: 'hit', len: 1.7, level: -10, channels: 2, poly: 3, throttle: 0.05, pitchVar: 0.8, verb: 0.24, clip: 1.3, prio: 8,
  desc: 'crystal shattering: crack transient, thump, glass body partials, dense shard cloud, long tinkle tail',
}, (k) => {
  k.click({ gain: 1, f: 3000, d: 0.004 });
  k.hiss({ len: 0.12, f: 4500, q: 0.8, env: { a: 0.0005, d: 0.05 }, gain: 0.7, drive: 3 });
  k.thump({ f0: 130, f1: 50, drop: 0.05, len: 0.35, gain: 0.9, drive: 1.8 });
  k.modal({ f: k.j(950, 0.05), partials: GLASS, gain: 0.4, beat: 3 });
  k.grains({ len: 1.0, count: 220, tau: 0.12, kind: 'glass', f: [2200, 10000], decay: [0.008, 0.07], amp: [0.05, 1], pow: 2, spread: 0.95, gain: 0.6 });
  k.grains({ at: 0.15, len: 1.3, count: 40, dist: 'uniform', kind: 'glass', f: [3000, 8000], decay: [0.03, 0.15], amp: [0.05, 0.7], gain: 0.2 });
  k.grains({ at: 0.08, len: 0.6, count: 20, dist: 'uniform', kind: 'noise', lp: 0.6, decay: [0.003, 0.01], amp: [0.1, 1], gain: 0.2, filter: { type: 'bandpass', f: 3000, q: 0.7 } });
});

S('ice_crack', {
  group: 'ice', role: 'element', len: 0.7, level: -15, variants: 3, poly: 3, throttle: 0.05, pitchVar: 1, verb: 0.16, prio: 5,
  desc: 'ice splitting: a run of sharp crack transients with resonant pings, a pulsed creak, small sub',
}, (k) => {
  let t = 0;
  for (let i = 0; i < 4; i++) {
    const g = 1 - i * 0.18;
    k.click({ at: t, gain: 0.8 * g, f: 2000, d: 0.002 });
    k.modal({ at: t, f: k.r(2000, 4500), partials: [[1, 0.5, 0.05], [2.3, 0.3, 0.03]], gain: 0.3 * g });
    k.hiss({ at: t, len: 0.06, f: 2800, q: 0.9, env: { a: 0.0003, d: 0.03 }, gain: 0.4 * g });
    t += k.r(0.05, 0.11);
  }
  const jit = k.smooth(8);
  k.hiss({ len: 0.55, f: 420, q: 3, env: [[0, 0], [0.05, 1], [0.5, 0, 'outQuad']], gain: 0.35, am: (tt) => Math.pow(0.5 + 0.5 * Math.sin(2 * Math.PI * 58 * tt + 4 * jit(tt)), 3) });
  k.thump({ f0: 140, f1: 70, drop: 0.03, len: 0.15, gain: 0.25 });
});

S('frost_wind', {
  group: 'ice', role: 'loop', len: 3, loop: true, level: -24, channels: 2, poly: 2, pitchVar: 0, volVar: 0, verb: 0.15, prio: 3,
  desc: 'seamless icy wind: wandering band of air, thin whistle, breathing hiss, sparse glitter',
}, (k) => {
  const d = k.dur, c = k.smooth(0.7), w = k.smooth(1.1);
  k.hiss({ len: d, color: 'pink', f: (t) => 450 + 500 * c(t), q: 1.2, env: FLAT(d), gain: 0.8, am: { rate: 0.6, depth: 0.5 }, stereo: true });
  k.hiss({ len: d, f: (t) => 1100 + 700 * w(t), q: 12, env: FLAT(d), gain: 0.35, am: { rate: 0.9, depth: 0.8 } });
  k.hiss({ len: d, type: 'highpass', f: 5000, env: FLAT(d), gain: 0.15, am: { rate: 1.2, depth: 0.6 }, stereo: true });
  k.grains({ len: d, count: 14, dist: 'uniform', kind: 'glass', f: [5000, 9000], decay: [0.02, 0.08], amp: [0.1, 1], gain: 0.08 });
});

// ============================================================================================ lightning (Vorn)

S('volt_zap', {
  group: 'volt', role: 'element', len: 0.5, level: -15, variants: 3, poly: 4, throttle: 0.04, pitchVar: 1.5, verb: 0.12, prio: 5,
  desc: 'electric zap: snap, jittering driven buzz, gated "tzzt" hiss, spark crackle',
}, (k) => {
  k.click({ gain: 0.9, f: 3000, d: 0.003 });
  k.hiss({ len: 0.05, type: 'highpass', f: 4000, env: { a: 0, d: 0.02 }, gain: 0.5 });
  const jit = k.smooth(45);
  k.saws({ len: 0.35, f: (t) => 140 * (0.75 + 0.5 * jit(t)), voices: 2, spread: 40, filter: { type: 'bandpass', f: 1800, q: 0.7 }, env: { a: 0.001, h: 0.06, d: 0.22 }, drive: 4, gain: 0.6 });
  k.hiss({ len: 0.3, type: 'highpass', f: 3000, env: { a: 0.001, h: 0.04, d: 0.18 }, gain: 0.45, am: (t) => (Math.sin(t * 2 * Math.PI * 85) > 0 ? 1 : 0.15), stereo: true });
  k.grains({ len: 0.3, count: 30, tau: 0.1, kind: 'noise', lp: 1, decay: [0.0003, 0.0015], amp: [0.1, 1], gain: 0.35, filter: { type: 'highpass', f: 2000 } });
});

S('volt_strike', {
  group: 'volt', role: 'big', len: 2.7, level: -8, channels: 2, poly: 3, throttle: 0.06, pitchVar: 0.8, verb: 0.28, clip: 1.5, prio: 9, duck: { amount: 0.3, dur: 0.6 },
  desc: 'lightning strike: razor snap, ripping gated crackle, boom, rolling thunder tail panned wide',
}, (k) => {
  k.click({ gain: 1, f: 2000, d: 0.004 });
  k.hiss({ len: 0.05, type: 'highpass', f: 2500, env: { a: 0, d: 0.02 }, gain: 1, drive: 6 });
  k.hiss({ len: 0.08, f: 1200, q: 0.6, env: { a: 0, d: 0.04 }, gain: 0.9, drive: 4 });
  const gate = k.smooth(140);
  k.hiss({ len: 0.55, f: 2200, q: 0.5, env: [[0, 0.5], [0.04, 0.6], [0.35, 0.18, 'outQuad'], [0.5, 0]], gain: 0.7, drive: 3, am: (t) => (gate(t) > 0.45 ? 1 : 0.1), stereo: true });
  k.grains({ len: 0.5, times: k.poisson(0.5, [[0, 900], [0.3, 200], [0.5, 0]]), kind: 'noise', lp: 1, decay: [0.0002, 0.002], amp: [0.05, 1], pow: 2.5, gain: 0.5, filter: { type: 'highpass', f: 1500 } });
  k.thump({ f0: 90, f1: 30, drop: 0.2, len: 1.0, gain: 0.8, drive: 2 });
  k.rumble({ at: 0.05, len: 2.6, f: [[0, 900], [0.4, 260], [2.4, 110]], env: [[0, 0], [0.2, 1, 'outQuad'], [0.6, 0.7], [2.55, 0, 'inOutQuad']], gain: 0.55, rate: 3, depth: 0.7 });
});

S('volt_charge', {
  group: 'volt', role: 'riser', len: 1.45, level: -16, poly: 2, throttle: 0.1, pitchVar: 0.5, verb: 0.15, prio: 5,
  desc: 'electric charge-up: rising driven buzz through an opening band, accelerating whine, thickening sparks, end spark',
}, (k) => {
  const T = 1.22;
  k.saws({ len: 1.3, f: [[0, 70], [T, 290, 'inQuad']], voices: 3, spread: 25, filter: { type: 'bandpass', f: [[0, 400], [T, 3000, 'inQuad']], q: 2 }, env: [[0, 0], [T, 1, 'inQuad'], [1.28, 0]], drive: 3, gain: 0.5 });
  k.saws({ len: 1.3, type: 'sine', voices: 1, f: [[0, 500], [T, 3200, 'inQuad']], vibrato: { rate: 9, depth: 30 }, env: [[0, 0], [T, 1, 'inCubic'], [1.26, 0]], gain: 0.12 });
  k.grains({ len: T, times: k.poisson(T, [[0, 10], [T, 300, 'inQuad']]), kind: 'noise', lp: 1, decay: [0.0002, 0.0015], amp: [0.05, 1], gain: 0.4, filter: { type: 'highpass', f: 3000 } });
  k.click({ at: T, gain: 0.8, f: 2500 });
  k.hiss({ at: T, len: 0.2, type: 'highpass', f: 3000, env: { a: 0, d: 0.1 }, gain: 0.5 });
});

S('volt_loop', {
  group: 'volt', role: 'loop', len: 2, loop: true, level: -23, channels: 2, poly: 2, pitchVar: 0, volVar: 0, verb: 0.1, prio: 4,
  desc: 'seamless live-current hum: driven mains buzz, crackle, gated sizzle bursts, occasional arc zaps',
}, (k) => {
  const d = k.dur, gate = k.smooth(20);
  k.saws({ len: d, f: 100, voices: 2, spread: 12, filter: { type: 'bandpass', f: 600, q: 1 }, env: FLAT(d), drive: 2, gain: 0.3, am: { rate: 8, depth: 0.3 } });
  k.grains({ len: d, times: k.poisson(d, 60), kind: 'noise', lp: 1, decay: [0.0002, 0.0012], amp: [0.05, 1], gain: 0.35, filter: { type: 'highpass', f: 2000 } });
  k.hiss({ len: d, type: 'highpass', f: 4000, env: FLAT(d), gain: 0.25, am: (t) => Math.max(0, gate(t) - 0.55) * 2.2, stereo: true });
  for (let i = 0; i < 3; i++) k.hiss({ at: k.r(0.1, d - 0.3), len: 0.12, f: 2000, q: 0.8, env: { a: 0.001, d: 0.06 }, gain: 0.3, am: (t) => (Math.sin(t * 2 * Math.PI * 100) > 0 ? 1 : 0.2), pan: k.r(-0.6, 0.6) });
});

// ============================================================================================ magic / skills

S('charge_up', {
  group: 'magic', role: 'riser', len: 1.7, level: -15, poly: 2, throttle: 0.1, pitchVar: 0.3, verb: 0.2, prio: 6,
  desc: 'energy riser: detuned saws and filtered noise climbing two octaves, accelerating shimmer tremolo, sub swell',
}, (k) => {
  const T = 1.55, env = [[0, 0], [T, 1, 'inCubic'], [1.62, 0]];
  k.saws({ len: 1.65, f: [[0, 110], [T, 440, 'inQuad']], voices: 4, spread: 18, filter: { type: 'lowpass', f: [[0, 400], [T, 6000, 'inQuad']], q: 1.5 }, env, gain: 0.45 });
  k.hiss({ len: 1.65, color: 'pink', f: [[0, 500], [T, 5000, 'inQuad']], q: 1.5, env, gain: 0.5, stereo: true });
  k.saws({ len: 1.65, type: 'sine', voices: 2, spread: 12, f: [[0, 880], [T, 1760, 'inQuad']], env: [[0, 0], [T, 1, 'inQuad'], [1.6, 0]], gain: 0.12, am: (t) => 0.6 + 0.4 * Math.sin(2 * Math.PI * (8 * t + 5 * t * t)) });
  k.saws({ len: 1.65, type: 'sine', voices: 1, f: [[0, 55], [T, 110, 'inQuad']], env, gain: 0.35 });
});

S('release', {
  group: 'magic', role: 'hit', len: 1.1, level: -11, poly: 3, throttle: 0.06, pitchVar: 0.6, verb: 0.2, clip: 1.3, prio: 7,
  desc: 'energy release: punchy thoom, down-sweeping driven zap, outward air burst (wide), spark glitter',
}, (k) => {
  k.click({ gain: 0.9, f: 2000 });
  k.thump({ f0: 240, f1: 110, drop: 0.03, len: 0.15, gain: 0.5, drive: 2 });
  k.thump({ f0: 140, f1: 40, drop: 0.12, len: 0.6, gain: 0.65, drive: 2 });
  k.saws({ len: 0.45, f: [[0, 900], [0.3, 120, 'outQuad']], voices: 3, spread: 25, filter: { type: 'lowpass', f: [[0, 3000], [0.35, 500]] }, env: { a: 0.002, d: 0.35 }, drive: 2, gain: 0.55 });
  for (const p of [-0.5, 0.5]) k.hiss({ len: 0.8, f: [[0, 3500], [0.6, 600, 'outQuad']], q: 1, env: { a: 0.005, d: 0.6 }, gain: 0.5, pan: p });
  k.grains({ len: 0.9, count: 30, tau: 0.3, kind: 'ping', f: [4000, 9000], decay: [0.01, 0.05], amp: [0.1, 1], gain: 0.15 });
});

S('shockwave', {
  group: 'magic', role: 'big', len: 1.9, level: -10, channels: 2, poly: 2, throttle: 0.08, pitchVar: 0.6, verb: 0.25, clip: 1.4, prio: 8,
  desc: 'expanding shockwave: sub whump, collapsing pressure blast, twin doppler whooshes flying out to both sides, rumble',
}, (k) => {
  k.click({ gain: 0.7, f: 1500, d: 0.005 });
  k.thump({ f0: 82, f1: 28, drop: 0.2, len: 0.9, gain: 0.85, drive: 2 });
  k.hiss({ len: 0.9, color: 'pink', type: 'lowpass', f: [[0, 5000], [0.06, 1800], [0.6, 250]], env: { a: 0.001, d: 0.7 }, gain: 1, drive: 1.8, stereo: true });
  for (const s of [-1, 1]) k.whoosh({ at: 0.02, len: 0.9, peak: 0.22, sharp: 1, fLo: 300 + s * 10, fHi: 1850 + s * 50, q: 0.9, doppler: 0.15, pan: [0, 0.85 * s], gain: 0.5 });
  k.rumble({ len: 1.85, f: 120, env: [[0, 0], [0.1, 1], [1.8, 0, 'outQuad']], gain: 0.5 });
});

S('magic_cast', {
  group: 'magic', role: 'magic', len: 1.4, level: -16, poly: 3, throttle: 0.06, pitchVar: 0.4, verb: 0.3, prio: 5,
  desc: 'spell cast: rising arpeggio of bell sparkles (D minor), chorused shimmer pad, breathy air, soft low swell',
}, (k) => {
  [74, 77, 81, 84, 86, 89, 93, 96].forEach((m, i) => k.modal({ at: i * 0.045 + k.r(0, 0.01), f: hz(m), partials: [[1, 0.5, 0.5], [2, 0.15, 0.3], [3.01, 0.06, 0.2]], gain: 0.13, pan: (i % 2 ? 0.5 : -0.5) * (0.4 + i * 0.07) }));
  k.saws({ len: 1.3, type: 'sine', voices: 6, spread: 22, f: 880, env: [[0, 0], [0.25, 1], [1.25, 0, 'outQuad']], gain: 0.12 });
  k.saws({ len: 1.3, type: 'sine', voices: 4, spread: 18, f: 1318.5, env: [[0, 0], [0.3, 1], [1.25, 0, 'outQuad']], gain: 0.08 });
  k.hiss({ len: 1.0, f: [[0, 3000], [0.5, 6000]], q: 1, env: [[0, 0], [0.15, 1], [0.95, 0]], gain: 0.3, stereo: true });
  k.thump({ f0: 160, f1: 80, drop: 0.08, len: 0.5, gain: 0.35, a: 0.01, drive: 0 });
});

S('rune', {
  group: 'magic', role: 'loop', len: 2, loop: true, level: -24, channels: 2, poly: 2, pitchVar: 0, volVar: 0, verb: 0.25, prio: 4,
  desc: 'seamless rune-circle hum: beating low fifths pulsing at 0.5 Hz, faint vowel formant, glassy overtones',
}, (k) => {
  const d = k.dur, pulse = (t) => 0.75 + 0.25 * Math.sin(Math.PI * t);
  k.saws({ len: d, type: 'sine', voices: 2, spread: 8, f: 55, env: FLAT(d), drive: 2.5, gain: 0.35, am: pulse });
  k.saws({ len: d, type: 'triangle', voices: 2, spread: 6, f: 110, env: FLAT(d), gain: 0.25, am: pulse });
  k.saws({ len: d, type: 'sine', voices: 2, spread: 5, f: 165, env: FLAT(d), gain: 0.18 });
  const o = k.osc('sawtooth', 110, 0, d);
  k.send(k.chain(k.formant(o, [[700, 1, 4], [1150, 0.6, 5], [2500, 0.25, 8]]), k.am({ rate: 0.8, depth: 0.6 })), 0.3);
  for (const f of [1760, 2640, 3530]) k.saws({ len: d, type: 'sine', voices: 2, spread: 4, f, env: FLAT(d), gain: 0.05, am: { rate: 1.5, depth: 0.7 } });
});

// ============================================================================================ ultimates

S('ult_start', {
  group: 'ult', role: 'riser', len: 2.3, level: -11, channels: 2, poly: 1, throttle: 0.5, pitchVar: 0, volVar: 0, verb: 0.3, bus: 'ui', clip: 1.3, prio: 9, maxLate: 0.3, duck: { amount: 0.6, dur: 1.2 },
  desc: 'ultimate super-freeze: dark gong hit, true reversed hall swell + riser peaking at 0.85 s, shimmer tail',
}, async (k) => {
  const P = 0.85;
  k.thump({ f0: 62, f1: 28, drop: 0.3, len: 1.2, gain: 0.6, drive: 2 });
  k.hiss({ len: 0.5, type: 'lowpass', f: 700, env: { a: 0.002, d: 0.4 }, gain: 0.6, drive: 1.5 });
  k.modal({ f: 98, partials: GONG, gain: 0.4, beat: 0.6 });
  const fwd = await k.sub(1.6, 2, (s) => {
    s.verb(0.9, 1.8);
    s.hiss({ len: 1.5, type: 'highpass', f: 2500, env: { a: 0.002, d: 1.3 }, gain: 0.7, stereo: true });
    for (const f of [146.8, 220]) s.saws({ len: 1.5, f, voices: 4, spread: 20, filter: { type: 'lowpass', f: 2200 }, env: { a: 0.005, d: 1.2 }, gain: 0.45 });
    s.thump({ f0: 90, f1: 40, drop: 0.1, len: 0.6, gain: 0.6 });
  });
  const rev = k.reverse(fwd);
  k.play(rev, { at: Math.max(0, P - rev.duration), offset: Math.max(0, rev.duration - P) });
  const env = [[0, 0], [P, 1, 'inCubic'], [P + 0.02, 0]];
  k.saws({ len: P + 0.03, f: [[0, 55], [P, 220, 'inQuad']], voices: 4, spread: 20, filter: { type: 'lowpass', f: [[0, 300], [P, 4000, 'inQuad']] }, env, gain: 0.4 });
  k.hiss({ len: P + 0.03, color: 'pink', f: [[0, 300], [P, 4000, 'inQuad']], q: 1.2, env, gain: 0.4, stereo: true });
  k.grains({ at: P, len: 1.2, count: 30, tau: 0.4, kind: 'glass', f: [3000, 9000], decay: [0.05, 0.3], amp: [0.1, 1], gain: 0.15 });
  k.modal({ at: P, f: 1174.7, partials: [[1, 0.4, 1.2], [2.01, 0.15, 0.8], [2.76, 0.1, 0.5]], gain: 0.15, beat: 1.5 });
});

S('ult_impact', {
  group: 'ult', role: 'big', len: 4.4, level: -6, channels: 2, poly: 2, throttle: 0.2, pitchVar: 0, volVar: 0, verb: 0.32, clip: 1.6, prio: 10, maxLate: 0.2, duck: { amount: 0.7, dur: 1.8 },
  desc: 'ultimate finisher: driven snap + crack, steel ring, collapsing blast, huge 78->20 Hz sub drop, twin shock whooshes, debris, gong, rumble',
}, (k) => {
  k.click({ gain: 1, f: 1500, d: 0.006 });
  k.hiss({ len: 0.06, type: 'highpass', f: 2500, env: { a: 0, d: 0.03 }, gain: 1, drive: 6 });
  k.hiss({ len: 0.4, f: 2000, q: 0.5, env: { a: 0.0005, d: 0.16 }, gain: 0.8, drive: 4, stereo: true });
  k.modal({ f: 520, partials: STEEL.map(([r, a, d]) => [r, a, d * 3]), beat: 1.2, gain: 0.3, bend: 1.5, bendTime: 0.05 });
  k.hiss({ len: 2.4, color: 'pink', type: 'lowpass', f: [[0, 8000], [0.08, 3000], [0.6, 600], [2.2, 180]], env: { a: 0.002, d: 1.8 }, gain: 1, drive: 2.5, stereo: true });
  k.thump({ f0: 78, f1: 20, drop: 0.6, len: 3.0, gain: 1.15, drive: 2.5 });
  k.thump({ f0: 210, f1: 85, drop: 0.04, len: 0.35, gain: 0.75, drive: 2.2 });
  for (const s of [-1, 1]) k.whoosh({ at: 0.05, len: 1.4, peak: 0.2, sharp: 1, fLo: 250 + s * 8, fHi: 1520 + s * 30, q: 0.8, doppler: 0.15, pan: [0, 0.9 * s], gain: 0.45 });
  debris(k, { at: 0.2, len: 3.4, rate: k.fn([[0, 0], [0.2, 50], [3.2, 2]]), gain: 0.35 });
  k.rumble({ len: 4.35, f: 140, env: [[0, 0], [0.08, 1], [4.3, 0, 'outQuad']], gain: 0.9, rate: 2, depth: 0.4 });
  k.modal({ f: 98, partials: [[1, 0.5, 3], [1.48, 0.25, 2.4], [2.03, 0.3, 2], [2.73, 0.15, 1.5], [3.6, 0.1, 1]], gain: 0.25, beat: 0.5 });
  k.hiss({ len: 2.6, type: 'highpass', f: 5000, env: { a: 0.01, d: 2.2 }, gain: 0.1, stereo: true });
});

// ============================================================================================ time

S('slowmo_in', {
  group: 'time', role: 'transition', len: 1.5, level: -15, poly: 1, throttle: 0.3, pitchVar: 0, volVar: 0, verb: 0.3, bus: 'ui', prio: 7,
  desc: 'time slows: air swell that sinks through a closing filter, tape-stop tone, deep sub boom',
}, (k) => {
  const env = [[0, 0], [0.25, 1], [1.35, 0]];
  k.hiss({ len: 1.45, f: [[0, 2600], [0.3, 1800], [1.3, 500, 'outQuad']], q: 0.7, env: [[0, 0], [0.3, 1, 'inCubic'], [1.4, 0, 'outQuad']], gain: 0.6, stereo: true });
  k.saws({ len: 1.4, f: [[0, 220], [1.1, 35, 'inQuad']], voices: 2, spread: 10, filter: { type: 'lowpass', f: [[0, 1800], [1.1, 300]] }, env, drive: 1.5, gain: 0.3 });
  k.saws({ len: 1.4, type: 'sine', voices: 1, f: [[0, 110], [1.1, 30, 'inQuad']], env, gain: 0.3 });
  k.thump({ at: 0.3, f0: 70, f1: 25, drop: 0.4, len: 1.0, gain: 0.9, drive: 1.6 });
  k.hiss({ len: 1.45, color: 'brown', type: 'lowpass', f: 300, env: [[0, 0], [0.3, 1], [1.4, 0]], gain: 0.4 });
});

S('slowmo_out', {
  group: 'time', role: 'transition', len: 0.95, level: -17, poly: 1, throttle: 0.3, pitchVar: 0, volVar: 0, verb: 0.25, bus: 'ui', prio: 6,
  desc: 'time snaps back: tape-start tone rising through an opening filter, accelerating air swell',
}, (k) => {
  k.saws({ len: 0.85, f: [[0, 35], [0.55, 240, 'outQuad']], voices: 2, spread: 10, filter: { type: 'lowpass', f: [[0, 300], [0.55, 2500]] }, env: [[0, 0], [0.5, 1], [0.8, 0]], gain: 0.3 });
  k.hiss({ len: 0.9, f: [[0, 600], [0.55, 3500, 'inQuad']], q: 0.8, env: [[0, 0], [0.55, 1, 'inQuad'], [0.85, 0]], gain: 0.6, stereo: true });
  k.hiss({ at: 0.45, len: 0.4, type: 'highpass', f: 5000, env: { a: 0.08, d: 0.25 }, gain: 0.3, stereo: true });
});

// ============================================================================================ UI

S('ui_move', {
  group: 'ui', role: 'ui', len: 0.12, level: -28, poly: 2, throttle: 0.03, pitchVar: 0, volVar: 0, verb: 0.04, bus: 'ui', prio: 6,
  desc: 'cursor tick: soft sine blip with a faint octave and click',
}, (k) => {
  k.saws({ len: 0.08, type: 'sine', voices: 1, f: [[0, 1700], [0.05, 1600]], env: { a: 0.001, d: 0.05 }, gain: 0.5 });
  k.saws({ len: 0.06, type: 'triangle', voices: 1, f: 3300, env: { a: 0.001, d: 0.025 }, gain: 0.15 });
  k.click({ gain: 0.2, f: 4000, d: 0.003 });
});

S('ui_select', {
  group: 'ui', role: 'ui', len: 0.55, level: -24, poly: 2, throttle: 0.05, pitchVar: 0, volVar: 0, verb: 0.08, bus: 'ui', prio: 6,
  desc: 'confirm: rising two-note chime (D6 -> A6) over a soft low tap',
}, (k) => {
  k.modal({ f: 1174.7, partials: [[1, 0.5, 0.35], [2, 0.15, 0.2], [3.01, 0.06, 0.12]], gain: 0.5 });
  k.modal({ at: 0.07, f: 1760, partials: [[1, 0.5, 0.4], [2, 0.15, 0.22], [3.01, 0.06, 0.12]], gain: 0.5 });
  k.thump({ f0: 230, f1: 140, drop: 0.02, len: 0.08, gain: 0.3, drive: 0 });
  k.hiss({ len: 0.12, f: 6000, q: 1, env: { a: 0.001, d: 0.08 }, gain: 0.1 });
});

S('ui_back', {
  group: 'ui', role: 'ui', len: 0.28, level: -27, poly: 2, throttle: 0.05, pitchVar: 0, volVar: 0, verb: 0.05, bus: 'ui', prio: 6,
  desc: 'cancel: falling two-note blip (A5 -> E5)',
}, (k) => {
  k.modal({ f: 880, partials: [[1, 0.5, 0.15], [2, 0.1, 0.08]], gain: 0.45 });
  k.modal({ at: 0.05, f: 659.3, partials: [[1, 0.5, 0.18], [2, 0.1, 0.08]], gain: 0.45 });
  k.click({ gain: 0.15, f: 3000, d: 0.003 });
});

// ============================================================================================ announcer stingers

const STINGER = { group: 'announce', role: 'stinger', channels: 2, poly: 1, throttle: 0.5, pitchVar: 0, volVar: 0, verb: 0.35, bus: 'ui', clip: 1.3, prio: 9, maxLate: 0.5 };

S('announce_round', {
  ...STINGER, len: 3.0, level: -9, duck: { amount: 0.5, dur: 1.6 },
  desc: 'ROUND: taiko hit under a D-minor brass/string stab, crash, bell toll on D5, sub',
}, (k) => {
  k.taiko({ f: 58, gain: 1, len: 1.5 });
  stab(k, { notes: [146.8, 220, 293.7, 349.2, 440], len: 2, gain: 0.42 });
  k.saws({ len: 1.2, f: 73.4, voices: 3, spread: 10, filter: { type: 'lowpass', f: 1200 }, env: { a: 0.005, d: 0.9 }, gain: 0.4 });
  crash(k, { len: 2.6, gain: 0.4 });
  k.bell({ f: 587.3, gain: 0.45, decay: 2.6 });
  k.thump({ f0: 70, f1: 35, drop: 0.15, len: 0.9, gain: 0.45, drive: 1.6 });
});

S('announce_fight', {
  ...STINGER, len: 2.6, level: -8, duck: { amount: 0.5, dur: 1.4 },
  desc: 'FIGHT: pickup drum + upward string rip into a driven brass blat on D, big taiko, crash, sub boom',
}, (k) => {
  const T = 0.11;
  k.taiko({ f: 92, gain: 0.6, len: 0.6 });
  k.saws({ len: T + 0.02, f: [[0, 220], [T, 587, 'inQuad']], voices: 4, spread: 20, filter: { type: 'bandpass', f: 1500, q: 0.7 }, env: [[0, 0], [T, 1, 'inQuad'], [T + 0.02, 0]], gain: 0.3 });
  k.taiko({ at: T, f: 55, gain: 1, len: 1.6 });
  stab(k, { at: T, notes: [146.8, 220, 293.7, 440, 587.3], len: 1.6, drive: 3, bright: 5000, gain: 0.42 });
  crash(k, { at: T, len: 2.3, gain: 0.45 });
  k.thump({ at: T, f0: 80, f1: 30, drop: 0.2, len: 1.2, gain: 0.55, drive: 2 });
});

S('announce_ko', {
  ...STINGER, len: 3.8, level: -7, clip: 1.4, duck: { amount: 0.7, dur: 2.5 },
  desc: 'K.O.: massive sub impact, taiko, dissonant brass cluster sagging down a minor third, low bell toll, dark choir decay',
}, (k) => {
  k.click({ gain: 1, f: 1500, d: 0.006 });
  k.thump({ f0: 82, f1: 22, drop: 0.5, len: 2.5, gain: 0.9, drive: 2.5 });
  k.hiss({ len: 1.5, color: 'pink', type: 'lowpass', f: [[0, 3500], [1.2, 300]], env: { a: 0.001, d: 1 }, gain: 1, drive: 2, stereo: true });
  k.taiko({ f: 50, gain: 0.8, len: 1.8 });
  [146.8, 155.6, 220, 293.7].forEach((f, i) => k.saws({
    len: 2.4, f: [[0, f], [0.25, f], [2.0, f * Math.pow(2, -3 / 12), 'inOutQuad']], voices: 3, spread: 16, drive: 2, gain: 0.3, pan: (i - 1.5) * 0.3,
    filter: { type: 'lowpass', f: [[0, 400], [0.02, 3500], [2.2, 400]] }, env: [[0, 0], [0.012, 1], [0.3, 0.6], [2.3, 0, 'outQuad']],
  }));
  k.bell({ f: 146.8, gain: 0.5, decay: 3.6, bright: 0.7 });
  const mix = k.ac.createGain();
  for (const f of [146.8, 220.6]) k.osc('sawtooth', f, 0, 3.6).connect(mix);
  k.send(k.chain(k.formant(mix, [[700, 1, 6], [1100, 0.5, 8], [2600, 0.2, 10]]), k.env([[0, 0], [0.15, 1], [3.5, 0, 'outQuad']])), 0.25);
  k.hiss({ len: 3.5, type: 'highpass', f: 2500, env: { a: 0.003, d: 3 }, gain: 0.25, stereo: true });
});

S('bell', {
  group: 'announce', role: 'stinger', len: 4.6, level: -12, poly: 2, throttle: 0.3, pitchVar: 0, volVar: 0, verb: 0.4, bus: 'ui', prio: 8, maxLate: 0.3,
  desc: 'great bronze bell (G3 strike): hum / prime / tierce / quint / nominal partials beating, 4 s decay',
}, (k) => {
  k.bell({ f: 196, gain: 1, decay: 4.2 });
  k.thump({ f0: 160, f1: 98, drop: 0.02, len: 0.2, gain: 0.25, drive: 0 });
});
