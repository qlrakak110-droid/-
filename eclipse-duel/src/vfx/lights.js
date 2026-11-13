// Pooled point lights. The pool (ctx.quality.maxLights PointLights) is added to the scene once at start-up and never
// changes size, so lit shaders never recompile; idle lights sit at intensity 0. vfx.light() borrows the weakest light.
//
// Fog link. The post fog draws a glow around the scene's strongest point lights (airlight). An event light is NOT where
// the effect is: it sits ~1.5 m toward the camera so it rims the fighters without whiting them out, and it is 5-20x
// brighter than a brazier. Picked up as it is, every hit hangs a white ball of lit mist in front of the fight. So this
// module hands the fog its light list itself (ctx.post.fogLights): the environment's point lights as they are, the
// pooled lights at `fog.vfxScale` of their intensity, with a wide core radius, pulled back toward the fight plane
// (z * fog.pullZ). vfx.lights.fog.enabled = false returns the choice to the post module (post.fogLights(null)).

import * as THREE from 'three';
import { toVec3, toColor, toCurveFn } from './util.js';
import { ease as resolveEase } from '../core/math.js';

/**
 * @param {object} vfx
 * @param {object} shared
 */
export function installLights(vfx, shared) {
  const { ctx, clock, root } = shared;
  const n = Math.max(1, ctx.quality.maxLights | 0);
  const pool = [];
  for (let i = 0; i < n; i++) {
    const l = new THREE.PointLight(0xffffff, 0, 6, 2);
    l.castShadow = false;
    l.name = 'vfx.light' + i;
    root.add(l);
    pool.push({ light: l, active: false, t0: 0, dur: 0, peak: 0, attack: 0, curve: null, decay: null, follow: null, offset: new THREE.Vector3(), realtime: false, flicker: 0, flickerRate: 14, seed: i * 7.31, serial: 0, cur: 0 });
  }
  let serial = 1;
  const col = new THREE.Color();

  // ---- fog link (see the header) ------------------------------------------------------------------------------------
  const post = ctx.post;
  const fog = { enabled: !!(post && post.fogLights && post.features && post.features.fog), vfxScale: 0.16, radius: 0.95, pullZ: 0.35, envRadius: 0.35 };
  const FOGN = 4;
  const fogList = [];
  for (let i = 0; i < FOGN; i++) fogList.push({ pos: new THREE.Vector3(0, -100, 0), color: [0, 0, 0], intensity: 0, radius: 0.35 });
  const envLights = [];
  const fogPick = new Array(FOGN).fill(null), fogW = new Float64Array(FOGN);
  let fogScan = -1e9, fogFrame = 0, fogOn = false;
  const isOurs = (o) => { for (; o; o = o.parent) if (o === root) return true; return false; };
  const shown = (o) => { for (; o; o = o.parent) if (!o.visible) return false; return true; };
  function updateFog() {
    if (!fog.enabled) { if (fogOn) { post.fogLights(null); fogOn = false; } return; }
    if (!fogOn) { post.fogLights(fogList); fogOn = true; }
    if (++fogFrame - fogScan > 120) {
      envLights.length = 0;
      ctx.scene.traverse((o) => { if (o.isPointLight && !isOurs(o)) envLights.push(o); });
      fogScan = fogFrame;
    }
    for (let i = 0; i < FOGN; i++) { fogPick[i] = null; fogW[i] = 0; }
    const offer = (l, w) => {
      for (let i = 0; i < FOGN; i++) {
        if (w > fogW[i]) {
          for (let k = FOGN - 1; k > i; k--) { fogPick[k] = fogPick[k - 1]; fogW[k] = fogW[k - 1]; }
          fogPick[i] = l; fogW[i] = w;
          return;
        }
      }
    };
    for (let j = 0; j < envLights.length; j++) {
      const l = envLights[j], w = l.intensity * Math.max(l.color.r, l.color.g, l.color.b);
      if (w > 0.01 && shown(l)) offer(l, w);
    }
    for (let j = 0; j < pool.length; j++) {
      const l = pool[j].light, w = l.intensity * fog.vfxScale;
      if (w > 0.01) offer(l, w);
    }
    for (let i = 0; i < FOGN; i++) {
      const l = fogPick[i], e = fogList[i];
      if (!l) { e.intensity = 0; e.pos.set(0, -100, 0); continue; }
      const ours = l.parent === root;
      e.pos.setFromMatrixPosition(l.matrixWorld);
      if (ours) { e.pos.copy(l.position); e.pos.z *= fog.pullZ; }
      e.color[0] = l.color.r; e.color[1] = l.color.g; e.color[2] = l.color.b;
      e.intensity = l.intensity * (ours ? fog.vfxScale : 1);
      e.radius = ours ? fog.radius : fog.envRadius;
    }
  }

  /**
   * Flash a pooled point light.
   * opts: pos, color (HDR colour; normalised to its brightest channel), intensity (candela, default 60), range (m, default 6),
   * duration (s, default 0.35; Infinity until stop()), attack (s, default 0), decay (ease name, default 'outQuad' fall-off),
   * curve (custom envelope over normalised life, overrides attack/decay), flicker (0..1), flickerRate (Hz),
   * follow (Object3D | () => pos), offset ([x, y, z] local to follow), realtime.
   * Returns { light, kill(), stop(), follow(obj, offset), setIntensity(v), alive }.
   */
  function light(opts = {}) {
    let s = null;
    for (const p of pool) if (!p.active) { s = p; break; }
    if (!s) { s = pool[0]; for (const p of pool) if (p.cur < s.cur) s = p; }
    const realtime = !!opts.realtime;
    s.active = true;
    s.serial = serial++;
    s.realtime = realtime;
    s.t0 = realtime ? clock.real : clock.game;
    s.dur = opts.duration != null ? opts.duration : 0.35;
    s.peak = opts.intensity != null ? opts.intensity : 60;
    s.attack = opts.attack != null ? opts.attack : 0;
    s.decay = resolveEase(opts.decay || 'outQuad');
    s.curve = opts.curve ? toCurveFn(opts.curve) : null;
    s.flicker = opts.flicker || 0;
    s.flickerRate = opts.flickerRate || 14;
    s.follow = opts.follow || null;
    if (opts.offset) toVec3(opts.offset, s.offset); else s.offset.set(0, 0, 0);
    toColor(opts.color != null ? opts.color : [6, 3, 1], col);
    const m = Math.max(col.r, col.g, col.b, 1e-6);
    s.light.color.setRGB(col.r / m, col.g / m, col.b / m);
    s.light.distance = opts.range != null ? opts.range : 6;
    if (opts.pos != null) toVec3(opts.pos, s.light.position);
    s.stopping = false;
    place(s);
    evaluate(s);
    const my = s.serial;
    const h = {
      light: s.light,
      get alive() { return s.active && s.serial === my; },
      kill() { if (s.serial === my) { s.active = false; s.cur = 0; s.light.intensity = 0; } },
      stop() { if (s.serial === my && !s.stopping) { const now = s.realtime ? clock.real : clock.game; s.stopping = true; s.stopAt = now; s.stopFrom = s.cur; } },
      follow(obj, offset) { if (s.serial === my) { s.follow = obj; if (offset) toVec3(offset, s.offset); place(s); } return h; },
      setIntensity(v) { if (s.serial === my) s.peak = v; return h; },
    };
    shared.track(h);
    return h;
  }

  function place(s) {
    const f = s.follow;
    if (!f) return;
    if (f.isObject3D) { f.updateWorldMatrix(true, false); s.light.position.copy(s.offset).applyMatrix4(f.matrixWorld); }
    else toVec3(f, s.light.position).add(s.offset);
  }

  function evaluate(s) {
    const now = s.realtime ? clock.real : clock.game;
    const age = now - s.t0;
    let k;
    if (s.stopping) {
      const r = (now - s.stopAt) / 0.18;
      if (r >= 1) { s.active = false; s.cur = 0; s.light.intensity = 0; return; }
      s.cur = s.stopFrom * (1 - r) * (1 - r);
      s.light.intensity = s.cur;
      return;
    }
    if (age >= s.dur) { s.active = false; s.cur = 0; s.light.intensity = 0; return; }
    if (s.curve) k = s.curve(Math.min(1, age / s.dur));
    else if (age < s.attack) k = age / s.attack;
    else k = Number.isFinite(s.dur) ? 1 - s.decay(Math.min(1, (age - s.attack) / Math.max(1e-4, s.dur - s.attack))) : 1;
    if (s.flicker > 0) {
      const x = age * s.flickerRate + s.seed;
      const a = Math.sin(x * 12.9898) * 43758.5453, b = Math.sin((x + 1) * 12.9898) * 43758.5453;
      const fr = x - Math.floor(x);
      const hn = (a - Math.floor(a)) * (1 - fr) + (b - Math.floor(b)) * fr;
      k *= 1 - s.flicker * hn;
    }
    s.cur = Math.max(0, k * s.peak);
    s.light.intensity = s.cur;
  }

  return {
    name: 'lights',
    api: { light, lights: { pool, fog } },
    update() {
      for (const s of pool) {
        if (!s.active) continue;
        place(s);
        evaluate(s);
      }
      updateFog();
    },
    clear() { for (const s of pool) { s.active = false; s.cur = 0; s.light.intensity = 0; } },
    dispose() { if (fogOn) post.fogLights(null); for (const s of pool) s.light.removeFromParent(); },
  };
}
