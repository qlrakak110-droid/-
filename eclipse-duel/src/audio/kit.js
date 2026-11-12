// Offline synthesis toolkit for the procedural sound library (sfx.js) and the music instruments (music.js).
//
// A sound is a recipe `(k, arg, variant) => {}` (may be async) that builds a WebAudio graph inside an
// OfflineAudioContext through the kit `k`. renderSound() renders it once to an AudioBuffer and masters it (seamless
// loop crossfade, end fade, loudness normalisation with a soft-clip ceiling). Playback is then a single
// AudioBufferSourceNode, which is what keeps the engine cheap on phones.
//
// Layer vocabulary (every layer takes { at = start seconds, gain, pan, ... } and is summed into k.out):
//   click   broadband transient            thump   pitched sine kick / sub drop with saturation
//   hiss    filtered noise layer           modal   ringing (in)harmonic partials (metal, glass, wood, bells)
//   grains  JS-built grain cloud: pings, glass, noise crackle (Poisson or clustered times)
//   whoosh  moving band-pass + doppler drop + rotor flutter + blade tone + sub push
//   rumble  slow-modulated low noise       saws    detuned oscillator stack (strings, brass, risers)
//   bell    church-bell partial set        taiko   big drum            formant  vowel filter bank
// "Spec" parameters accept a number, a function of local time t (seconds from `at`), or points
// [[t, value, ease?], ...] (ease names from core/math Ease; frequencies interpolate in log space).

import { makeRng, ease as easeOf, clamp } from '../core/math.js';

/** Seamless-loop crossfade length (seconds) rendered past the end of `loop: true` sounds. */
const XF = 0.12;

/** WebAudio constructors available right now (null when missing). Read at call time so tests can stub them. */
export function audioClasses() {
  const g = typeof window !== 'undefined' ? window : globalThis;
  return {
    AC: g.AudioContext || g.webkitAudioContext || null,
    OAC: g.OfflineAudioContext || g.webkitOfflineAudioContext || null,
  };
}

/** Render an OfflineAudioContext; supports both the promise and the legacy `oncomplete` forms. */
export function renderOffline(oac) {
  return new Promise((resolve, reject) => {
    let done = false;
    const finish = (b) => { if (!done) { done = true; resolve(b); } };
    oac.oncomplete = (e) => finish(e.renderedBuffer);
    try {
      const p = oac.startRendering();
      if (p && typeof p.then === 'function') p.then(finish, reject);
    } catch (e) { reject(e); }
  });
}

/** FNV-1a hash of a string (stable per-sound seeds). */
export function hashName(s) {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); }
  return h >>> 0;
}

/** Piecewise curve through [[t, v, ease?], ...]; `log` interpolates geometrically (frequencies). */
export function pointsFn(pts, log = false) {
  const n = pts.length;
  return (t) => {
    if (t <= pts[0][0]) return pts[0][1];
    for (let i = 1; i < n; i++) {
      const b = pts[i];
      if (t <= b[0]) {
        const a = pts[i - 1];
        const u = easeOf(b[2] || 'linear')((t - a[0]) / (b[0] - a[0] || 1));
        return log ? a[1] * Math.pow(b[1] / a[1], u) : a[1] + (b[1] - a[1]) * u;
      }
    }
    return pts[n - 1][1];
  };
}

const specFn = (spec, log) => (typeof spec === 'function' ? spec : Array.isArray(spec) ? pointsFn(spec, log) : () => spec);

// ---- scratch noise (seamless, per sample rate / colour / channel count; released once the render queue drains) ----
const NOISE = new Map();
function noiseBuffer(ac, color, channels) {
  const key = color + ':' + channels + ':' + ac.sampleRate;
  let b = NOISE.get(key);
  if (b) return b;
  const sr = ac.sampleRate, len = Math.round(sr * 3), xf = Math.round(sr * 0.08);
  b = ac.createBuffer(channels, len, sr);
  const rng = makeRng(0x6e01 + channels * 31 + color.charCodeAt(0) * 977);
  const tmp = new Float32Array(len + xf);
  for (let c = 0; c < channels; c++) {
    let p0 = 0, p1 = 0, p2 = 0, br = 0, e = 0;
    for (let i = 0; i < len + xf; i++) {
      const w = rng() * 2 - 1;
      let v = w;
      if (color === 'pink') { p0 = 0.99765 * p0 + w * 0.099046; p1 = 0.963 * p1 + w * 0.2965164; p2 = 0.57 * p2 + w * 1.0526913; v = p0 + p1 + p2 + w * 0.1848; }
      else if (color === 'brown') { br = (br + 0.02 * w) / 1.02; v = br; }
      tmp[i] = v; e += v * v;
    }
    const d = b.getChannelData(c), s = 0.3 / Math.sqrt(e / (len + xf));
    for (let i = 0; i < len; i++) d[i] = tmp[i] * s;
    // equal-power crossfade of the overrun into the head: the buffer loops without a seam
    for (let i = 0; i < xf; i++) { const w = (i / xf) * Math.PI * 0.5; d[i] = (tmp[i] * Math.sin(w) + tmp[len + i] * Math.cos(w)) * s; }
  }
  NOISE.set(key, b);
  return b;
}
/** Free the scratch noise buffers (they are regenerated on demand). */
export function releaseScratch() { NOISE.clear(); }

const CURVES = new Map();
function tanhCurve(a) {
  const key = a.toFixed(2);
  let c = CURVES.get(key);
  if (!c) {
    c = new Float32Array(1025);
    const n = Math.tanh(a);
    for (let i = 0; i < 1025; i++) c[i] = Math.tanh(a * (i / 512 - 1)) / n;
    CURVES.set(key, c);
  }
  return c;
}

/** Output-stage safety clipper: identity below 0.85, smooth knee to a hard ceiling of ~0.965. */
export function softClipCurve() {
  const c = new Float32Array(2049);
  for (let i = 0; i < 2049; i++) {
    const x = i / 1024 - 1, a = Math.abs(x);
    c[i] = a <= 0.85 ? x : Math.sign(x) * (0.85 + 0.15 * Math.tanh((a - 0.85) / 0.15));
  }
  return c;
}

/**
 * Generated impulse response of a large stone hall: sparse early reflections, diffuse build-up, then an exponential
 * tail whose high end dies faster than the low end (stone + air absorption). Stereo with decorrelated channels.
 * @param {BaseAudioContext} ac
 * @param {{seconds?: number, predelay?: number, damp?: number, seed?: number}} [o]  seconds = RT60
 */
export function hallIR(ac, { seconds = 3.2, predelay = 0.024, damp = 0.6, seed = 7 } = {}) {
  const sr = ac.sampleRate, pd = Math.round(predelay * sr), len = pd + Math.ceil(seconds * sr);
  const buf = ac.createBuffer(2, len, sr);
  const rng = makeRng(seed);
  const tau = seconds / 6.9;
  for (let c = 0; c < 2; c++) {
    const d = buf.getChannelData(c);
    for (let e = 0; e < 16; e++) {
      const t = 0.005 + Math.pow(rng(), 1.4) * 0.09;
      const i = pd + Math.round(t * sr * (c ? 1.06 : 0.97));
      if (i < len) d[i] += (rng() < 0.5 ? -1 : 1) * (0.7 - t * 4) * (0.5 + 0.5 * rng());
    }
    let l1 = 0, l2 = 0;
    for (let i = pd; i < len; i++) {
      const t = (i - pd) / sr;
      const cutoff = 900 + 7600 * Math.exp(-t * (1.2 + damp));
      const a = 1 - Math.exp((-2 * Math.PI * cutoff) / sr);
      l1 += a * (rng() * 2 - 1 - l1);
      l2 += a * (l1 - l2);
      d[i] += l2 * Math.exp(-t / tau) * (1 - Math.exp(-t / 0.03)) * 2.2;
    }
  }
  return buf;
}

// ---- loudness (ITU-R BS.1770 K-weighting, short-window maximum) ----

function kWeighting(sr) {
  // stage 1: high shelf (+4 dB above ~1.7 kHz); stage 2: high-pass at ~38 Hz (RBJ forms of the BS.1770 filters)
  let w = (2 * Math.PI * 1681.974450955533) / sr, cs = Math.cos(w), al = Math.sin(w) / (2 * 0.7071752369554196);
  const A = Math.pow(10, 3.999843853973347 / 40), sA = Math.sqrt(A);
  let a0 = A + 1 - (A - 1) * cs + 2 * sA * al;
  const s1 = [
    (A * (A + 1 + (A - 1) * cs + 2 * sA * al)) / a0, (-2 * A * (A - 1 + (A + 1) * cs)) / a0, (A * (A + 1 + (A - 1) * cs - 2 * sA * al)) / a0,
    (2 * (A - 1 - (A + 1) * cs)) / a0, (A + 1 - (A - 1) * cs - 2 * sA * al) / a0,
  ];
  w = (2 * Math.PI * 38.13547087602444) / sr; cs = Math.cos(w); al = Math.sin(w) / (2 * 0.5003270373238773); a0 = 1 + al;
  const s2 = [(1 + cs) / 2 / a0, -(1 + cs) / a0, (1 + cs) / 2 / a0, (-2 * cs) / a0, (1 - al) / a0];
  return [s1, s2];
}

/**
 * K-weighted loudness of a buffer, in dB comparable to LUFS. Channel powers are summed, so a mono asset is measured
 * as it sounds through a centred equal-power panner.
 * @param {AudioBuffer} buf
 * @param {number} [win] window (seconds) for `max`
 * @returns {{max: number, mean: number}} max = loudest window, mean = whole buffer
 */
export function loudness(buf, win = 0.1) {
  const sr = buf.sampleRate, n = buf.length;
  const pw = new Float64Array(n);
  const [p, q] = kWeighting(sr);
  for (let c = 0; c < buf.numberOfChannels; c++) {
    const x = buf.getChannelData(c);
    let x1 = 0, x2 = 0, y1 = 0, y2 = 0, z1 = 0, z2 = 0;
    for (let i = 0; i < n; i++) {
      const xi = x[i];
      const y = p[0] * xi + p[1] * x1 + p[2] * x2 - p[3] * y1 - p[4] * y2;
      const z = q[0] * y + q[1] * y1 + q[2] * y2 - q[3] * z1 - q[4] * z2;
      x2 = x1; x1 = xi; y2 = y1; y1 = y; z2 = z1; z1 = z;
      pw[i] += z * z;
    }
  }
  const W = Math.max(1, Math.min(n, Math.round(win * sr)));
  let s = 0, total = 0;
  for (let i = 0; i < W; i++) s += pw[i];
  let best = s;
  for (let i = W; i < n; i++) { s += pw[i] - pw[i - W]; if (s > best) best = s; }
  for (let i = 0; i < n; i++) total += pw[i];
  return { max: -0.691 + 10 * Math.log10(best / W + 1e-12), mean: -0.691 + 10 * Math.log10(total / n + 1e-12) };
}

/** Absolute peak over all channels. */
export function peakOf(buf) {
  let p = 0;
  for (let c = 0; c < buf.numberOfChannels; c++) {
    const d = buf.getChannelData(c);
    for (let i = 0; i < d.length; i++) { const a = Math.abs(d[i]); if (a > p) p = a; }
  }
  return p;
}

// ---- the kit ----

/**
 * Build the synthesis kit for one OfflineAudioContext.
 * @param {OfflineAudioContext} ac
 * @param {() => number} rng   seeded RNG (core/math makeRng)
 * @param {number} dur         render length in seconds
 */
export function makeKit(ac, rng, dur) {
  const sr = ac.sampleRate, nyq = sr * 0.45;
  const out = ac.createGain();
  const hp = ac.createBiquadFilter();
  hp.type = 'highpass'; hp.frequency.value = 22; hp.Q.value = -3; // DC / infrasonic guard (Q in dB for HP/LP)
  out.connect(hp); hp.connect(ac.destination);
  const stereoOK = typeof ac.createStereoPanner === 'function';

  const k = {
    ac, sr, dur, rng, out,
    /** uniform random in [a, b) */
    r: (a, b) => a + (b - a) * rng(),
    /** x jittered by +-amt (relative) */
    j: (x, amt = 0.06) => x * (1 + (rng() * 2 - 1) * amt),
    /** log-uniform random in [a, b) */
    lr: (a, b) => a * Math.pow(b / a, rng()),
    /** piecewise curve function (see pointsFn) */
    fn: pointsFn,

    /** Drive an AudioParam with a number / function / points over [at, at + len]. */
    set(param, spec, at = 0, len = dur - at, log = false) {
      if (typeof spec === 'number') { param.value = spec; return param; }
      const f = specFn(spec, log);
      len = Math.max(0.002, len);
      const n = Math.max(2, Math.min(32768, Math.ceil(len * 1500)));
      const arr = new Float32Array(n);
      for (let i = 0; i < n; i++) { const v = f((i / (n - 1)) * len); arr[i] = Number.isFinite(v) ? v : 0; }
      param.value = arr[0];
      param.setValueCurveAtTime(arr, at, len);
      return param;
    },

    /** Smooth value noise in [0, 1] with `rate` knots per second (cosine interpolation). */
    smooth(rate) {
      const v = [rng(), rng()];
      return (t) => {
        const x = Math.max(0, t) * rate, i = Math.floor(x);
        while (v.length < i + 2) v.push(rng());
        const u = (1 - Math.cos((x - i) * Math.PI)) / 2;
        return v[i] + (v[i + 1] - v[i]) * u;
      };
    },

    /** Looping noise source (white | pink | brown), random start offset, mono or stereo. */
    noise(color = 'white', at = 0, len = dur - at, stereo = false) {
      const s = ac.createBufferSource();
      s.buffer = noiseBuffer(ac, color, stereo ? 2 : 1);
      s.loop = true;
      s.start(at, rng() * s.buffer.duration);
      s.stop(at + len + 0.02);
      return s;
    },

    /** Oscillator with a frequency spec (log interpolation). */
    osc(type, f, at = 0, len = dur - at) {
      const o = ac.createOscillator();
      o.type = type;
      k.set(o.frequency, f, at, len, true);
      o.start(at); o.stop(at + len + 0.02);
      return o;
    },

    /** Biquad filter; `q` is a linear Q for every type (converted to dB for lowpass / highpass). */
    filter(type, f, q = 0.707, at = 0, len = dur - at) {
      const b = ac.createBiquadFilter();
      b.type = type;
      if (typeof f === 'number') b.frequency.value = Math.min(f, nyq);
      else { const g = specFn(f, true); k.set(b.frequency, (t) => Math.min(g(t), nyq), at, len, true); }
      b.Q.value = type === 'lowpass' || type === 'highpass' ? 20 * Math.log10(Math.max(q, 0.05)) : q;
      return b;
    },

    /**
     * Gain envelope. `{a, h, d, peak}` = linear attack, hold, exponential decay where `d` is the time to -60 dB;
     * points / function = arbitrary shape.
     */
    env(spec, at = 0, len = dur - at) {
      const g = ac.createGain();
      if (spec && typeof spec === 'object' && !Array.isArray(spec)) {
        const { a = 0.001, h = 0, d = 0.3, peak = 1 } = spec;
        g.gain.value = 0;
        g.gain.setValueAtTime(0, at);
        if (a > 0) g.gain.linearRampToValueAtTime(peak, at + a); else g.gain.setValueAtTime(peak, at);
        if (h > 0) g.gain.setValueAtTime(peak, at + a + h);
        g.gain.setTargetAtTime(0, at + a + h, d / 6.9);
      } else if (spec != null) k.set(g.gain, spec, at, len, false);
      return g;
    },

    /** Amplitude modulation gain: function of t, or `{rate, depth}` smooth random flutter. */
    am(spec, at = 0, len = dur - at) {
      const g = ac.createGain();
      let f = spec;
      if (spec && typeof spec === 'object' && !Array.isArray(spec)) {
        const s = k.smooth(spec.rate), d = spec.depth ?? 0.5;
        f = (t) => 1 - d * s(t);
      }
      k.set(g.gain, f, at, len, false);
      return g;
    },

    /** tanh saturation (adds harmonics so sub content still reads on phone speakers). */
    drive(amount) {
      const ws = ac.createWaveShaper();
      ws.curve = tanhCurve(amount);
      ws.oversample = '2x';
      return ws;
    },

    /** Stereo panner (spec allowed); a pass-through gain where StereoPannerNode is missing. */
    pan(p, at = 0, len = dur - at) {
      if (!stereoOK) return ac.createGain();
      const n = ac.createStereoPanner();
      k.set(n.pan, p, at, len, false);
      return n;
    },

    /** Connect nodes in series (nulls skipped); returns the last. */
    chain(...nodes) {
      const a = nodes.filter(Boolean);
      for (let i = 0; i < a.length - 1; i++) a[i].connect(a[i + 1]);
      return a[a.length - 1];
    },

    /** Route `node` to the output through a gain and an optional (automated) pan. */
    send(node, gain = 1, pan = 0, at = 0, len = dur - at) {
      const g = ac.createGain();
      g.gain.value = gain;
      node.connect(g);
      if (pan) { const p = k.pan(pan, at, len); g.connect(p); p.connect(out); } else g.connect(out);
      return g;
    },

    // ---------------------------------------------------------------------------------------------------- layers

    /**
     * Filtered noise layer. Level is compensated for the filter bandwidth, so `gain: 1` is about 0.35 RMS in-band
     * whatever the filter; `post` adds more filters, `am` adds amplitude modulation.
     */
    hiss({ at = 0, len, color = 'white', stereo = false, type = 'bandpass', f = 1000, q = 0.707, post, env = { a: 0.002, d: 0.3 }, gain = 1, drive = 0, pan = 0, am } = {}) {
      len = len ?? dur - at;
      const ff = specFn(f, true);
      let fr = 0;
      for (let i = 0; i < 9; i++) fr += Math.log(Math.max(20, Math.min(ff((i / 8) * len), nyq)));
      fr = Math.exp(fr / 9);
      const bw = type === 'bandpass' ? fr / q : type === 'lowpass' ? fr : type === 'highpass' ? sr / 2 - fr : sr / 2;
      const comp = clamp(Math.sqrt(sr / 2 / Math.max(bw, 30)), 1, 14) * (color === 'white' ? 1.15 : 1);
      const nodes = [k.noise(color, at, len, stereo), k.filter(type, f, q, at, len)];
      for (const p of [].concat(post || [])) nodes.push(k.filter(p.type, p.f, p.q ?? 0.707, at, len));
      nodes.push(k.env(env, at, len));
      if (drive) nodes.push(k.drive(drive));
      if (am) nodes.push(k.am(am, at, len));
      return k.send(k.chain(...nodes), gain * comp, pan, at, len);
    },

    /** Very short broadband transient. */
    click({ at = 0, gain = 1, f = 3000, type = 'highpass', d = 0.004, q = 0.707, pan = 0 } = {}) {
      return k.hiss({ at, len: d * 1.6 + 0.008, type, f, q, env: { a: 0, d }, gain, pan });
    },

    /** Pitched sine kick: exponential pitch drop f0 -> f1 (time constant drop/3), decay to -60 dB at `len`. */
    thump({ at = 0, f0 = 120, f1 = 45, drop = 0.08, len = 0.5, gain = 1, drive = 1.5, a = 0.0006, h = 0.008, pan = 0 } = {}) {
      const o = ac.createOscillator();
      const tc = drop / 3;
      k.set(o.frequency, (t) => f1 + (f0 - f1) * Math.exp(-t / tc), at, Math.min(len, drop * 4 + 0.05));
      o.start(at); o.stop(at + len + 0.05);
      return k.send(k.chain(o, k.env({ a, h, d: len }, at), drive ? k.drive(drive) : null), gain, pan, at, len);
    },

    /**
     * Ringing partials [[ratio, amp, decaySeconds(-60 dB)], ...] on f. `bend` (semitones) starts sharp and settles
     * in `bendTime` (struck metal), `beat` (Hz) doubles every partial slightly detuned (bell / plate beating).
     */
    modal({ at = 0, f, partials, gain = 1, pan = 0, bend = 0, bendTime = 0.03, beat = 0, a = 0.0004, decayMul = 1 } = {}) {
      const sum = ac.createGain();
      for (const [ratio, amp, dec0] of partials) {
        const dec = dec0 * decayMul;
        for (let v = 0; v < (beat ? 2 : 1); v++) {
          const fr = f * ratio + (v ? beat * (0.4 + rng()) : 0);
          if (fr >= nyq || amp <= 0) continue;
          const o = ac.createOscillator();
          if (bend) {
            o.frequency.value = fr * Math.pow(2, bend / 12);
            o.frequency.setValueAtTime(fr * Math.pow(2, bend / 12), at);
            o.frequency.setTargetAtTime(fr, at, bendTime / 3);
          } else o.frequency.value = fr;
          const e = k.env({ a, d: dec, peak: amp * (v ? 0.55 : 1) }, at);
          o.connect(e); e.connect(sum);
          o.start(at); o.stop(at + a + dec * 1.05 + 0.02);
        }
      }
      return k.send(sum, gain, pan, at);
    },

    /** Event times of a Poisson process with rate spec (events / second) over [0, len] (thinning). */
    poisson(len, rate, max = 4000) {
      const f = specFn(rate, false);
      let rmax = 0;
      for (let i = 0; i <= 64; i++) rmax = Math.max(rmax, f((i / 64) * len));
      const out = [];
      if (rmax <= 0) return out;
      let t = 0;
      while (out.length < max) {
        t += -Math.log(1 - rng()) / rmax;
        if (t >= len) break;
        if (rng() * rmax < f(t)) out.push(t);
      }
      return out;
    },

    /**
     * Grain cloud synthesised in JS (stereo). kinds: 'ping' (decaying sine), 'glass' (sine + inharmonic 2.76x /
     * 5.40x partials), 'noise' (one-pole coloured noise burst, `lp` 0..1). Times: `times` array, or `count` drawn
     * with dist 'exp' (clustered at the start, time constant `tau`) | 'uniform'. `f` may be a function (t, rng).
     */
    grains({ at = 0, len = 0.5, times, count = 20, dist = 'exp', tau = 0.15, f = [2000, 8000], decay = [0.01, 0.06], amp = [0.15, 1], pow = 2, kind = 'ping', spread = 0.8, lp = 1, attack = 0.0004, gain = 1, pan = 0, filter } = {}) {
      const maxDec = Array.isArray(decay) ? decay[1] : decay;
      const n = Math.ceil((len + maxDec * 1.1) * sr);
      const buf = ac.createBuffer(2, n, sr);
      const L = buf.getChannelData(0), R = buf.getChannelData(1);
      const ts = times || Array.from({ length: count }, () => (dist === 'uniform' ? rng() * len : -tau * Math.log(1 - rng() * (1 - Math.exp(-len / tau)))));
      for (const t0 of ts) {
        const fr = typeof f === 'function' ? f(t0, rng) : f[0] * Math.pow(f[1] / f[0], rng());
        const dec = Array.isArray(decay) ? decay[0] + (decay[1] - decay[0]) * rng() : decay;
        const A = amp[0] + (amp[1] - amp[0]) * Math.pow(rng(), pow);
        const p = (rng() * 2 - 1) * spread;
        const gl = A * Math.cos(((p + 1) * Math.PI) / 4), gr = A * Math.sin(((p + 1) * Math.PI) / 4);
        const i0 = Math.floor(t0 * sr), m = Math.min(n - i0, Math.ceil(dec * sr));
        const k60 = 6.9 / (dec * sr), atk = Math.max(1, attack * sr);
        const w = (2 * Math.PI * Math.min(fr, nyq)) / sr, ph = rng() * 6.283;
        const g2 = kind === 'glass' && fr * 2.756 < nyq ? 0.45 : 0, g3 = kind === 'glass' && fr * 5.404 < nyq ? 0.22 : 0;
        let s = 0;
        for (let j = 0; j < m; j++) {
          const e = Math.exp(-j * k60) * (j < atk ? j / atk : 1);
          let v;
          if (kind === 'noise') { s += lp * (rng() * 2 - 1 - s); v = s; }
          else {
            v = Math.sin(ph + w * j);
            if (g2) v += g2 * Math.sin(ph * 1.7 + 2.756 * w * j) * Math.exp(-j * k60 * 0.7) + g3 * Math.sin(ph * 2.3 + 5.404 * w * j) * Math.exp(-j * k60 * 1.4);
          }
          v *= e;
          L[i0 + j] += v * gl; R[i0 + j] += v * gr;
        }
      }
      const src = ac.createBufferSource();
      src.buffer = buf;
      src.start(at);
      const nodes = [src];
      for (const fs of [].concat(filter || [])) nodes.push(k.filter(fs.type, fs.f, fs.q ?? 0.707, at, len));
      return k.send(k.chain(...nodes), gain, pan, at, len);
    },

    /**
     * Weapon / body whoosh. A bell-shaped "speed" curve peaks at `peak` (fraction of len) and drives: band-pass
     * noise centre (log fLo -> fHi), amplitude (speed^1.5), an optional blade tone, sub air push and high air. A
     * doppler factor (+doppler before the pass, -doppler after) bends every frequency down through the pass, the
     * stereo position follows the blade, and `flutter` adds the rotor "whum-whum" of a big spinning weapon.
     */
    whoosh({ at = 0, len = 0.5, peak = 0.45, sharp = 1.5, fLo = 500, fHi = 2500, q = 1.2, gain = 1, color = 'white', doppler = 0.08, flutter, tone, air = 0, sub, pan = [-0.3, 0.3], stereo = false } = {}) {
      const speed = (t) => {
        const u = clamp(t / len, 0, 1);
        if (u < peak) { const x = u / peak; return Math.pow(x * x * (3 - 2 * x), sharp); }
        const x = (u - peak) / (1 - peak);
        return Math.exp(-3.2 * x) * (1 - x * x * x * x);
      };
      const dop = (t) => 1 + doppler * Math.tanh((peak - t / len) * 9);
      const N = Math.ceil(len * 2000) + 2, fl = new Float32Array(N), pos = new Float32Array(N);
      let ph = 0, acc = 0;
      for (let i = 0; i < N; i++) {
        const t = i / 2000, s = speed(t);
        if (flutter) { ph += (2 * Math.PI * (flutter.rate[0] + (flutter.rate[1] - flutter.rate[0]) * s)) / 2000; fl[i] = 1 - flutter.depth * (0.5 - 0.5 * Math.cos(ph)); } else fl[i] = 1;
        acc += s; pos[i] = acc;
      }
      const at2 = (arr, t) => arr[Math.min(N - 1, Math.max(0, Math.round(t * 2000)))];
      const panF = (t) => pan[0] + (pan[1] - pan[0]) * (at2(pos, t) / acc);
      const band = (t) => fLo * Math.pow(fHi / fLo, speed(t)) * dop(t);
      const comp = clamp(Math.sqrt(sr / 2 / (Math.sqrt(fLo * fHi) / q)), 1, 14);
      const g = ac.createGain();
      k.set(g.gain, (t) => Math.pow(speed(t), 1.5) * at2(fl, t), at, len);
      k.chain(k.noise(color, at, len, stereo), k.filter('bandpass', band, q, at, len), g);
      k.send(g, gain * comp, panF, at, len);
      if (tone) {
        const o = k.osc(tone.type || 'sine', (t) => tone.fLo * Math.pow(tone.fHi / tone.fLo, speed(t)) * dop(t), at, len);
        const tg = ac.createGain();
        k.set(tg.gain, (t) => speed(t) * speed(t) * at2(fl, t), at, len);
        const lpf = tone.type && tone.type !== 'sine' ? k.filter('lowpass', (t) => tone.fLo * 3 * Math.pow(tone.fHi / tone.fLo, speed(t)), 0.8, at, len) : null;
        k.send(k.chain(o, lpf, tg), gain * tone.gain, panF, at, len);
      }
      if (sub) {
        const sg = ac.createGain();
        k.set(sg.gain, (t) => speed(t) * speed(t) * at2(fl, t), at, len);
        k.chain(k.noise('brown', at, len), k.filter('lowpass', (t) => sub.f * (0.45 + speed(t)) * dop(t), 0.9, at, len), sg);
        k.send(sg, gain * sub.gain * 3, 0, at, len);
      }
      if (air) {
        const ag = ac.createGain();
        k.set(ag.gain, (t) => Math.pow(speed(t), 3), at, len);
        k.chain(k.noise('white', at, len, stereo), k.filter('highpass', 6500, 0.7, at, len), ag);
        k.send(ag, gain * air * 2.2, panF, at, len);
      }
      return g;
    },

    /** Low rolling noise (thunder / debris bed / fire body): brown noise, low-pass, slow random AM. */
    rumble({ at = 0, len, f = 150, q = 0.707, gain = 1, env, rate = 2.5, depth = 0.5, stereo = true, color = 'brown', drive = 0 } = {}) {
      len = len ?? dur - at;
      return k.hiss({ at, len, color, stereo, type: 'lowpass', f, q, env: env || { a: 0.02, d: len }, gain, am: { rate, depth }, drive });
    },

    /** Detuned oscillator stack through optional filters, envelope and drive. `vibrato` = {rate, depth cents, delay}. */
    saws({ at = 0, len, f, voices = 3, spread = 12, type = 'sawtooth', gain = 1, filter, env, drive = 0, pan = 0, vibrato, am, stagger = 0.004 } = {}) {
      len = len ?? dur - at;
      const sum = ac.createGain();
      sum.gain.value = 1 / Math.sqrt(voices);
      for (let i = 0; i < voices; i++) {
        const t0 = at + (i ? rng() * stagger : 0);
        const o = k.osc(type, f, t0, len);
        o.detune.value = voices > 1 ? spread * ((i / (voices - 1)) * 2 - 1) + (rng() - 0.5) * spread * 0.3 : 0;
        if (vibrato) {
          const lfo = ac.createOscillator(), lg = ac.createGain();
          lfo.frequency.value = vibrato.rate * (0.88 + 0.24 * rng());
          lg.gain.value = 0;
          lg.gain.setValueAtTime(0, at + (vibrato.delay || 0));
          lg.gain.linearRampToValueAtTime(vibrato.depth, at + (vibrato.delay || 0) + 0.6);
          lfo.connect(lg); lg.connect(o.detune);
          lfo.start(at); lfo.stop(at + len + 0.02);
        }
        o.connect(sum);
      }
      const nodes = [sum];
      for (const fs of [].concat(filter || [])) nodes.push(k.filter(fs.type || 'lowpass', fs.f, fs.q ?? 0.707, at, len));
      nodes.push(k.env(env || { a: 0.01, d: len }, at, len));
      if (drive) nodes.push(k.drive(drive));
      if (am) nodes.push(k.am(am, at, len));
      return k.send(k.chain(...nodes), gain, pan, at, len);
    },

    /** Parallel band-pass bank [[freq, gain, q], ...] fed by `input` (vowel formants); returns the sum node. */
    formant(input, formants) {
      const sum = ac.createGain();
      for (const [f, g, q] of formants) {
        const gg = ac.createGain();
        gg.gain.value = g * Math.sqrt(q);
        const b = k.filter('bandpass', f, q);
        input.connect(b); b.connect(gg); gg.connect(sum);
      }
      return sum;
    },

    /** Struck bronze bell (hum, prime, minor-third tierce, quint, nominal ... partials, beating doublets). */
    bell({ at = 0, f = 220, gain = 1, decay = 4, bright = 1, pan = 0 } = {}) {
      const P = [[0.5, 0.55, 1], [1, 0.5, 0.8], [1.183, 0.42, 0.62], [1.506, 0.26, 0.5], [2, 0.42, 0.45], [2.514, 0.2, 0.3],
        [2.662, 0.16, 0.27], [3.011, 0.15, 0.22], [4.166, 0.11, 0.15], [5.433, 0.07, 0.1], [6.796, 0.045, 0.07]];
      k.modal({ at, f, partials: P.map(([r, a, d], i) => [r, a * (i > 7 ? bright : 1), d * decay]), beat: 0.7, gain, pan, a: 0.0012 });
      k.click({ at, gain: 0.35 * gain, f: 2400, type: 'bandpass', q: 0.9, d: 0.025, pan });
    },

    /** Big drum: pitched head thump, membrane modes (Bessel ratios), skin slap and stick noise. */
    taiko({ at = 0, f = 60, gain = 1, len = 1.2, pan = 0 } = {}) {
      k.thump({ at, f0: f * 2.6, f1: f, drop: 0.03, len, gain, drive: 1.4, pan });
      k.modal({ at, f: f * 1.03, partials: [[1, 0.5, len * 0.8], [1.59, 0.3, len * 0.45], [2.14, 0.2, len * 0.3], [2.3, 0.14, len * 0.25], [2.65, 0.1, len * 0.2]], gain: 0.4 * gain, pan });
      k.hiss({ at, len: 0.35, type: 'lowpass', f: 900, env: { a: 0.001, d: 0.1 }, gain: 0.5 * gain, pan });
      k.hiss({ at, len: 0.06, type: 'bandpass', f: 2600, q: 1, env: { a: 0, d: 0.018 }, gain: 0.3 * gain, pan });
    },

    /** Render a nested recipe to an AudioBuffer (same rate, own kit) — e.g. to reverse it. */
    async sub(len, channels, recipe) {
      const { OAC } = audioClasses();
      const o = new OAC(channels, Math.ceil(len * sr), sr);
      const k2 = makeKit(o, rng, len);
      await recipe(k2);
      return renderOffline(o);
    },

    /** A reversed copy of a buffer. */
    reverse(buf) {
      const r = ac.createBuffer(buf.numberOfChannels, buf.length, buf.sampleRate);
      for (let c = 0; c < buf.numberOfChannels; c++) { const s = buf.getChannelData(c), d = r.getChannelData(c); for (let i = 0, n = s.length; i < n; i++) d[i] = s[n - 1 - i]; }
      return r;
    },

    /** Play a buffer into the output. */
    play(buf, { at = 0, gain = 1, pan = 0, offset = 0, rate = 1, filter } = {}) {
      const s = ac.createBufferSource();
      s.buffer = buf; s.playbackRate.value = rate;
      s.start(at, offset);
      const nodes = [s];
      for (const fs of [].concat(filter || [])) nodes.push(k.filter(fs.type, fs.f, fs.q ?? 0.707, at));
      return k.send(k.chain(...nodes), gain, pan, at);
    },

    /** Add the stone-hall reverb to everything summed into k.out (used inside nested renders). */
    verb(wet = 0.5, seconds = 2.4) {
      const c = ac.createConvolver();
      c.buffer = hallIR(ac, { seconds });
      const g = ac.createGain();
      g.gain.value = wet;
      out.connect(c); c.connect(g); g.connect(hp);
    },
  };
  return k;
}

// ---- render + master ----

function sanitize(buf) {
  for (let c = 0; c < buf.numberOfChannels; c++) {
    const d = buf.getChannelData(c);
    for (let i = 0; i < d.length; i++) if (!Number.isFinite(d[i])) d[i] = 0;
  }
}

function seamless(oac, buf, n) {
  const xf = Math.round(XF * buf.sampleRate);
  const out = oac.createBuffer(buf.numberOfChannels, n, buf.sampleRate);
  for (let c = 0; c < buf.numberOfChannels; c++) {
    const s = buf.getChannelData(c), d = out.getChannelData(c);
    d.set(s.subarray(0, n));
    for (let i = 0; i < xf; i++) { const w = (i / xf) * Math.PI * 0.5; d[i] = s[i] * Math.sin(w) + s[n + i] * Math.cos(w); }
  }
  return out;
}

function loopRegion(buf, [ls, le]) {
  const sr = buf.sampleRate, s = Math.round(ls * sr), e = Math.round(le * sr), xf = Math.min(Math.round(0.18 * sr), s);
  for (let c = 0; c < buf.numberOfChannels; c++) {
    const d = buf.getChannelData(c);
    for (let i = 0; i < xf; i++) {
      const w = ((i + 1) / xf) * Math.PI * 0.5, a = e - xf + i, b = s - xf + i;
      d[a] = d[a] * Math.cos(w) + d[b] * Math.sin(w);
    }
  }
}

function fadeEnd(buf, sec) {
  const m = Math.min(buf.length, Math.round(sec * buf.sampleRate));
  for (let c = 0; c < buf.numberOfChannels; c++) {
    const d = buf.getChannelData(c), n = d.length;
    for (let i = 0; i < m; i++) d[n - 1 - i] *= i / m;
  }
}

/**
 * Master a raw render: loop crossfade / end fade, then gain to the loudness target `def.level` (dB, K-weighted
 * 100 ms max). The peak may overshoot the ceiling by `def.clip` (>= 1); that overshoot is folded back by a smooth
 * soft clipper (punchier transients without hard clipping).
 */
function master(oac, raw, def) {
  sanitize(raw);
  let buf = raw;
  if (def.loop === true) buf = seamless(oac, raw, Math.round(def.len * raw.sampleRate));
  else {
    if (Array.isArray(def.loop)) loopRegion(buf, def.loop);
    fadeEnd(buf, 0.008);
  }
  if (def.reverse) {
    for (let c = 0; c < buf.numberOfChannels; c++) buf.getChannelData(c).reverse();
  }
  const rawLoud = loudness(buf).max, rawPeak = peakOf(buf);
  const ceil = def.ceil ?? 0.94, over = Math.max(1, def.clip ?? 1);
  let gain = rawPeak > 1e-5 ? Math.pow(10, (def.level - rawLoud) / 20) : 1;
  if (rawPeak * gain > ceil * over) gain = (ceil * over) / rawPeak;
  const T = ceil * 0.72, span = ceil - T, soft = rawPeak * gain > ceil;
  let last = 0;
  for (let c = 0; c < buf.numberOfChannels; c++) {
    const d = buf.getChannelData(c);
    for (let i = 0; i < d.length; i++) {
      let x = d[i] * gain;
      if (soft) { const a = Math.abs(x); if (a > T) x = Math.sign(x) * (T + span * Math.tanh((a - T) / span)); }
      d[i] = x;
      if (Math.abs(x) > 2.5e-4 && i > last) last = i;  // -72 dBFS
    }
  }
  // one-shots: drop the inaudible tail (memory), ending on a short fade
  const keep = Math.min(buf.length, last + Math.round(0.012 * buf.sampleRate));
  if (!def.loop && !def.reverse && keep < buf.length * 0.97) {
    const t = oac.createBuffer(buf.numberOfChannels, keep, buf.sampleRate);
    for (let c = 0; c < buf.numberOfChannels; c++) t.getChannelData(c).set(buf.getChannelData(c).subarray(0, keep));
    fadeEnd(t, 0.012);
    buf = t;
  }
  return { buffer: buf, gain: 20 * Math.log10(gain), rawPeak, rawLoud };
}

/**
 * Render and master one sound definition. Returns null when OfflineAudioContext is missing.
 * def: { name, len, level, channels?, loop?: true | [loopStart, loopEnd], reverse?, clip?, ceil?, recipe }.
 * `mono` folds stereo recipes to one channel (low tier: half the memory, phones are near-mono anyway).
 * @returns {Promise<{buffer: AudioBuffer, gain: number, rawPeak: number, rawLoud: number} | null>} gain in dB
 */
export async function renderSound(def, { sr = 48000, variant = 0, arg, mono = false } = {}) {
  const { OAC } = audioClasses();
  if (!OAC) return null;
  const len = def.len + (def.loop === true ? XF : 0);
  const oac = new OAC(mono ? 1 : def.channels || 1, Math.max(1, Math.ceil(len * sr)), sr);
  const k = makeKit(oac, makeRng((hashName(def.name) + variant * 7919) >>> 0), len);
  await def.recipe(k, arg, variant);
  return master(oac, await renderOffline(oac), def);
}
