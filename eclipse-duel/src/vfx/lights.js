// Pooled point lights. The pool (ctx.quality.maxLights PointLights) is added to the scene once at start-up and never
// changes size, so lit shaders never recompile; idle lights sit at intensity 0. vfx.light() borrows the weakest light.

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

  /**
   * Flash a pooled point light.
   * opts: pos, color (HDR colour; normalised to its brightest channel), intensity (candela, default 60), range (m, default 6),
   * duration (s, default 0.35; Infinity until stop()), attack (s, default 0.02), decay (ease name, default 'outQuad' fall-off),
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
    s.attack = opts.attack != null ? opts.attack : 0.02;
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
    api: { light, lights: { pool } },
    update() {
      for (const s of pool) {
        if (!s.active) continue;
        place(s);
        evaluate(s);
      }
    },
    clear() { for (const s of pool) { s.active = false; s.cur = 0; s.light.intensity = 0; } },
    dispose() { for (const s of pool) s.light.removeFromParent(); },
  };
}
