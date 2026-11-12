// Small math helpers shared by every module. Pure functions, no three.js dependency.

export const TAU = Math.PI * 2;
export const DEG = Math.PI / 180;

export const clamp = (x, a = 0, b = 1) => (x < a ? a : x > b ? b : x);
export const saturate = (x) => (x < 0 ? 0 : x > 1 ? 1 : x);
export const lerp = (a, b, t) => a + (b - a) * t;
export const invLerp = (a, b, x) => (a === b ? 0 : (x - a) / (b - a));
export const remap = (x, a, b, c, d, clampOut = true) => {
  let t = invLerp(a, b, x);
  if (clampOut) t = saturate(t);
  return c + (d - c) * t;
};
export const smoothstep = (a, b, x) => {
  const t = saturate(invLerp(a, b, x));
  return t * t * (3 - 2 * t);
};
/** Frame-rate independent exponential approach: value moves toward target; lambda ~ 1/time-constant. */
export const damp = (a, b, lambda, dt) => lerp(a, b, 1 - Math.exp(-lambda * dt));
export const sign = (x) => (x < 0 ? -1 : 1);
export const fract = (x) => x - Math.floor(x);

/** Easing functions, t in [0,1] -> [0,1] (back/elastic overshoot on purpose). */
export const Ease = {
  linear: (t) => t,
  inQuad: (t) => t * t,
  outQuad: (t) => 1 - (1 - t) * (1 - t),
  inOutQuad: (t) => (t < 0.5 ? 2 * t * t : 1 - 2 * (1 - t) * (1 - t)),
  inCubic: (t) => t * t * t,
  outCubic: (t) => 1 - Math.pow(1 - t, 3),
  inOutCubic: (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2),
  inQuart: (t) => t * t * t * t,
  outQuart: (t) => 1 - Math.pow(1 - t, 4),
  inOutQuart: (t) => (t < 0.5 ? 8 * t * t * t * t : 1 - Math.pow(-2 * t + 2, 4) / 2),
  inQuint: (t) => t * t * t * t * t,
  outQuint: (t) => 1 - Math.pow(1 - t, 5),
  inExpo: (t) => (t <= 0 ? 0 : Math.pow(2, 10 * t - 10)),
  outExpo: (t) => (t >= 1 ? 1 : 1 - Math.pow(2, -10 * t)),
  inOutExpo: (t) => (t <= 0 ? 0 : t >= 1 ? 1 : t < 0.5 ? Math.pow(2, 20 * t - 10) / 2 : (2 - Math.pow(2, -20 * t + 10)) / 2),
  inSine: (t) => 1 - Math.cos((t * Math.PI) / 2),
  outSine: (t) => Math.sin((t * Math.PI) / 2),
  inOutSine: (t) => -(Math.cos(Math.PI * t) - 1) / 2,
  inCirc: (t) => 1 - Math.sqrt(1 - t * t),
  outCirc: (t) => Math.sqrt(1 - (t - 1) * (t - 1)),
  inBack: (t) => 2.70158 * t * t * t - 1.70158 * t * t,
  outBack: (t) => 1 + 2.70158 * Math.pow(t - 1, 3) + 1.70158 * Math.pow(t - 1, 2),
  inOutBack: (t) => {
    const c = 1.70158 * 1.525;
    return t < 0.5 ? (Math.pow(2 * t, 2) * ((c + 1) * 2 * t - c)) / 2 : (Math.pow(2 * t - 2, 2) * ((c + 1) * (t * 2 - 2) + c) + 2) / 2;
  },
  outElastic: (t) => (t <= 0 ? 0 : t >= 1 ? 1 : Math.pow(2, -10 * t) * Math.sin((t * 10 - 0.75) * (TAU / 3)) + 1),
  outBounce: (t) => {
    const n = 7.5625, d = 2.75;
    if (t < 1 / d) return n * t * t;
    if (t < 2 / d) return n * (t -= 1.5 / d) * t + 0.75;
    if (t < 2.5 / d) return n * (t -= 2.25 / d) * t + 0.9375;
    return n * (t -= 2.625 / d) * t + 0.984375;
  },
  /** hold at 0 then snap: useful for anticipation -> smear */
  snap: (t) => (t < 0.72 ? 0.06 * (t / 0.72) : 0.06 + 0.94 * Math.pow((t - 0.72) / 0.28, 0.6)),
};
/** Resolve an easing given as a name or a function. */
export const ease = (e) => (typeof e === 'function' ? e : Ease[e] || Ease.linear);

/**
 * Piecewise-linear curve sampler. points: [[t0, v0], [t1, v1], ...] sorted by t (v may be a number or an array).
 * Returns a function f(t) clamped to the end values.
 */
export function curve(points) {
  const n = points.length;
  const isArr = Array.isArray(points[0][1]);
  return (t) => {
    if (t <= points[0][0]) return points[0][1];
    if (t >= points[n - 1][0]) return points[n - 1][1];
    let i = 1;
    while (i < n && points[i][0] < t) i++;
    const a = points[i - 1], b = points[i];
    const k = (t - a[0]) / (b[0] - a[0] || 1);
    if (!isArr) return a[1] + (b[1] - a[1]) * k;
    return a[1].map((v, j) => v + (b[1][j] - v) * k);
  };
}

/**
 * Deterministic RNG (mulberry32). Use ctx.rng (or makeRng(seed)) instead of Math.random() so headless captures are
 * reproducible.
 */
export function makeRng(seed = 1234567) {
  let s = seed >>> 0;
  const next = () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  const rng = () => next();
  rng.next = next;
  rng.range = (a, b) => a + (b - a) * next();
  rng.int = (a, b) => Math.floor(a + (b - a + 1) * next());
  rng.sign = () => (next() < 0.5 ? -1 : 1);
  rng.pick = (arr) => arr[Math.floor(next() * arr.length) % arr.length];
  rng.chance = (p) => next() < p;
  /** value given as number or [min,max] */
  rng.of = (v) => (Array.isArray(v) ? v[0] + (v[1] - v[0]) * next() : v);
  rng.seed = (x) => { s = x >>> 0; };
  return rng;
}
