// Flags, events and quality tiers.

/** Parse `#a&b=1` and `?a&b=1` into {a:true, b:'1'}. Artifact hosts only pass a plain #name, so nothing here is required. */
export function parseFlags() {
  const out = {};
  let raw = '';
  try { raw = String(location.hash || '').replace(/^#/, '') + '&' + String(location.search || '').replace(/^\?/, ''); } catch (e) { /* no location */ }
  for (const part of raw.split('&')) {
    if (!part) continue;
    const i = part.indexOf('=');
    if (i < 0) out[decodeURIComponent(part)] = true;
    else out[decodeURIComponent(part.slice(0, i))] = decodeURIComponent(part.slice(i + 1));
  }
  return out;
}

/** Tiny event emitter: on(name, fn) -> off(), emit(name, ...args). */
export class Emitter {
  constructor() { this._m = new Map(); }
  on(name, fn) {
    let a = this._m.get(name);
    if (!a) this._m.set(name, (a = []));
    a.push(fn);
    return () => { const i = a.indexOf(fn); if (i >= 0) a.splice(i, 1); };
  }
  emit(name, ...args) {
    const a = this._m.get(name);
    if (!a) return;
    for (const fn of a.slice()) fn(...args);
  }
}

/**
 * Quality tiers. Everything that costs GPU time reads from ctx.quality:
 *   pixelRatio     canvas pixels per CSS pixel
 *   msaa           MSAA samples of the HDR scene target
 *   shadows        directional shadow map on/off, shadowSize its resolution (the key light's frustum is fitted to the
 *                  shadow casters every frame by ctx.shadows, so the texels stay small: see src/post/README.md)
 *   bloomLevels    bloom mip count
 *   depth          the scene target carries a depth texture (post fog / AO / light shafts / DOF / post.sceneDepth)
 *   ao             screen-space ambient occlusion: 0 off, 1 reduced (half res, 6 taps, 5-tap blur), 2 full (10 taps, 7-tap blur)
 *   fog            post height fog + sun in-scattering: 0 off, 1 (2 fog lights), 2 (4 fog lights)
 *   shafts         screen-space light shafts from the sun: 0 off, 1 (one 20-tap pass), 2 (two 16-tap passes)
 *   dof            cinematic depth of field (post.dof): 0 off, 1 (16-tap gather), 2 (32-tap gather)
 *   particleScale  multiply particle counts / emission rates by this
 *   envDetail      0..2 environment detail (props, ambient particles, reflections)
 *   cloth          cloth simulation detail multiplier
 *   maxLights      size of the pooled dynamic point-light set (never add/remove lights at runtime: it recompiles shaders)
 * URL overrides for A/B checks: #ao=0..2 #fog=0..2 #shafts=0..2 #dof=0..2 #msaa=0|4 #shadow=0|512..4096.
 */
export function pickQuality(flags = {}) {
  const ua = (typeof navigator !== 'undefined' && navigator.userAgent) || '';
  const nav = typeof navigator !== 'undefined' ? navigator : {};
  const mobile = /Android|iPhone|iPad|iPod|Mobile/i.test(ua) || ((nav.maxTouchPoints || 0) > 1 && /Macintosh/.test(ua));
  let tier = flags.q;
  if (tier !== 'low' && tier !== 'mid' && tier !== 'high') {
    if (flags.test) tier = 'high';
    else if (mobile) tier = (nav.hardwareConcurrency || 4) >= 8 && (nav.deviceMemory || 4) >= 6 ? 'mid' : 'low';
    else tier = 'high';
  }
  const dpr = (typeof window !== 'undefined' && window.devicePixelRatio) || 1;
  const T = {
    low: { tier: 'low', pixelRatio: Math.min(dpr, 1.0), msaa: 0, shadows: false, shadowSize: 0, bloomLevels: 4, depth: false, ao: 0, fog: 0, shafts: 0, dof: 0, particleScale: 0.45, envDetail: 0, cloth: 0.5, maxLights: 3 },
    mid: { tier: 'mid', pixelRatio: Math.min(dpr, 1.5), msaa: 0, shadows: true, shadowSize: 1024, bloomLevels: 5, depth: true, ao: 1, fog: 1, shafts: 1, dof: 1, particleScale: 0.7, envDetail: 1, cloth: 1, maxLights: 4 },
    high: { tier: 'high', pixelRatio: Math.min(dpr, 2.0), msaa: 4, shadows: true, shadowSize: 2048, bloomLevels: 6, depth: true, ao: 2, fog: 2, shafts: 2, dof: 2, particleScale: 1.0, envDetail: 2, cloth: 1, maxLights: 6 },
  };
  const q = T[tier];
  q.mobile = mobile;
  if (flags.test) q.pixelRatio = 1;
  const lvl = (v) => Math.max(0, Math.min(2, Math.round(Number(v)) || 0));
  for (const k of ['ao', 'fog', 'shafts', 'dof']) if (flags[k] !== undefined && flags[k] !== true) q[k] = lvl(flags[k]);
  if (flags.msaa !== undefined && flags.msaa !== true) q.msaa = Math.max(0, Number(flags.msaa) | 0);
  if (flags.shadow !== undefined && flags.shadow !== true) { const s = Number(flags.shadow) | 0; q.shadows = s > 0; q.shadowSize = s; }
  // every depth consumer needs the depth texture
  if (q.ao || q.fog || q.shafts || q.dof) q.depth = true;
  return q;
}
