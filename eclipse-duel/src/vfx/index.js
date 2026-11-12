// VFX facade: createVfx(ctx) -> ctx.vfx. Small sub-modules (particles, ribbons, lights, flares, distortion, scheduler,
// and the mesh effects added later) install themselves behind this object through vfx.use(install):
//
//   export function installThing(vfx, shared) {
//     ...build GPU resources once (pooled, hidden while idle)...
//     return {
//       name: 'thing',
//       api: { thing(opts) { ...; return shared.track(handle); } },   // merged onto vfx (names must be unique)
//       update(dtGame, dtReal) {},    // once per frame at ctx.ORDER.VFX (after characters, before the camera)
//       clear() {},                   // kill everything (round reset)
//       prewarm() {},                 // optional extra warm-up (programs are compiled by the facade)
//       dispose() {},
//     };
//   }
//
// `shared` carries the resources every module needs (see README.md "Extending"): ctx, root (Group in the scene),
// textures (atlas / noise / flow + sprite rects), clock (rebased game / real time), uniforms (uTime / uTimeReal shared
// by every VFX material), rng, util (coercion helpers), track(handle) (adds a handle to the running preset's group),
// EffectPool / InstanceRing / ParamTable building blocks.

import * as THREE from 'three';
import { createTextures } from './textures.js';
import { installParticles } from './particles.js';
import { installRibbons } from './ribbons.js';
import { installLights } from './lights.js';
import { installFlares } from './flares.js';
import { installDistort } from './distort.js';
import { installScheduler } from './scheduler.js';
import { installSlash } from './slash.js';
import { installRing } from './ring.js';
import { installPillar } from './pillar.js';
import { installBeam } from './beam.js';
import { installBolt } from './bolt.js';
import { installDecal } from './decal.js';
import { installDebris } from './debris.js';
import { installSpikes } from './spikes.js';
import { installSpeedlines } from './speedlines.js';
import { installAfterimage } from './afterimage.js';
import { installPresets } from './presets/index.js';
import { EffectPool } from './pool.js';
import { InstanceRing, makeQuadGeometry } from './instanced.js';
import { ParamTable, tableGlsl } from './table.js';
import * as util from './util.js';
import { LIB, PALETTE } from './library.js';

/**
 * Built-in sub-modules, in update order. The presets module runs right after the scheduler so its moving anchors are
 * placed before the layers that follow them sample their positions.
 */
export const MODULES = [installScheduler, installPresets, installParticles, installRibbons, installLights, installFlares, installDistort, installSlash, installRing, installPillar, installBeam, installBolt, installDecal, installDebris, installSpikes, installSpeedlines, installAfterimage];

/**
 * Create the VFX system, store it on ctx.vfx and register its per-frame update at ctx.ORDER.VFX.
 * Create it before the first render so the pooled lights are part of every lit shader from the start.
 * @param {object} ctx  app context (src/core/app.js)
 * @returns {object} vfx
 */
export function createVfx(ctx) {
  const root = new THREE.Group();
  root.name = 'vfx';
  root.matrixAutoUpdate = false;
  ctx.scene.add(root);

  const textures = createTextures(ctx.renderer);
  const clock = {
    _base: ctx.time.game, _baseReal: ctx.time.real,
    /** game-time seconds since the last vfx.clear() (frozen by hit-stop, scaled by slow motion) */
    get game() { return ctx.time.game - this._base; },
    /** real seconds since the last vfx.clear() */
    get real() { return ctx.time.real - this._baseReal; },
    /** current time on the requested clock */
    now(realtime) { return realtime ? this.real : this.game; },
  };
  const uniforms = { uTime: { value: 0 }, uTimeReal: { value: 0 } };

  // ---- groups: everything spawned while a preset (or a callback scheduled by it) runs belongs to its group ----------
  let capture = null;
  function makeGroup(name) {
    const g = {
      name, handles: [],
      get alive() { for (const h of g.handles) if (h.alive) return true; return false; },
      kill() { for (const h of g.handles) h.kill(); },
      stop() { for (const h of g.handles) if (h.stop) h.stop(); },
    };
    return g;
  }

  const shared = {
    ctx, root, textures, clock, uniforms, rng: ctx.rng, util,
    EffectPool, InstanceRing, ParamTable, tableGlsl, makeQuadGeometry,
    /** Add a spawn handle to the running preset's group (returns the handle). */
    track(h) {
      if (capture) {
        const hs = capture.handles;
        hs.push(h);
        // long-running groups (auras re-spawning bolts, storms) would grow without bound: drop finished handles
        if (hs.length >= 128 && (hs.length & 63) === 0) {
          let j = 0;
          for (let i = 0; i < hs.length; i++) if (hs[i].alive) hs[j++] = hs[i];
          hs.length = j;
        }
      }
      return h;
    },
    currentGroup() { return capture; },
    /** Run fn with `group` as the capture group (used by the scheduler). */
    runInGroup(group, fn) {
      const prev = capture;
      capture = group;
      try { fn(vfx); } finally { capture = prev; }
    },
  };

  const modules = [];
  const presets = new Map();

  const vfx = {
    ctx, root, textures, clock, util, shared,
    /** tuned base particle layers (see library.js / README) */
    lib: LIB,
    /** element colour palettes (linear HDR) */
    palette: PALETTE,

    /**
     * Install a sub-module: install(vfx, shared) -> { name, api?, update?, clear?, prewarm?, dispose? }.
     * Its api functions are merged onto vfx (a name clash throws).
     */
    use(install) {
      const m = install(vfx, shared);
      if (m.api) {
        for (const k in m.api) {
          if (k in vfx) throw new Error('vfx: "' + k + '" is already defined (module ' + m.name + ')');
          vfx[k] = m.api[k];
        }
      }
      modules.push(m);
      return m;
    },

    /** Current time on the VFX game clock (or real clock), seconds since the last clear(). */
    now(realtime = false) { return realtime ? clock.real : clock.game; },

    /**
     * Compile every VFX program and upload every VFX texture now (call once while loading, after defining presets).
     * `defs` (optional): particle definitions to register up front so no definition row is uploaded mid-fight.
     */
    prewarm(defs = []) {
      for (const d of defs) vfx.particles.compile(d);
      for (const k in LIB) vfx.particles.compile(LIB[k]);
      for (const m of modules) if (m.prewarm) m.prewarm();
      const r = ctx.renderer;
      r.compile(ctx.scene, ctx.camera);
      // the post pass renders the distortion scene on its own (no lights): compile it the same way so the cache keys match
      if (ctx.post && ctx.post.distortionScene) r.compile(ctx.post.distortionScene, ctx.camera);
      r.initTexture(vfx.particles.table.texture);
      r.initTexture(vfx.ribbons.table.texture);
    },

    /** Kill everything (round reset): particles, ribbons, lights, flares, distortion, scheduled callbacks. */
    clear() {
      for (const m of modules) if (m.clear) m.clear();
      clock._base = ctx.time.game;
      clock._baseReal = ctx.time.real;
      uniforms.uTime.value = 0;
      uniforms.uTimeReal.value = 0;
    },

    /**
     * Register a composed preset: fn(vfx, at, opts) spawns layers (and may vfx.schedule() later ones).
     * at = { pos: Vector3, dir: Vector3 (default forward = facing * X), facing: ±1, scale, color: Color|null, target,
     *        local(f, u, s) -> Vector3 in the fighter-local frame, raw: the caller's object }.
     */
    define(name, fn) {
      presets.set(name, fn);
      return vfx;
    },

    /**
     * Play a preset. Returns a group handle { kill(), stop(), alive, handles } covering everything it spawns.
     * A preset may return an object of extra members (e.g. a projectile's impact(), a live `pos` getter): they are
     * merged onto the group; its functions run inside the group (what they spawn is killed with it). A returned
     * `stop` runs before the default stop (which stops every handle of the group).
     */
    play(name, at, opts = {}) {
      const fn = presets.get(name);
      if (!fn) throw new Error('vfx: unknown preset "' + name + '" (have: ' + [...presets.keys()].join(', ') + ')');
      const group = makeGroup(name);
      const prev = capture;
      capture = group;
      let api;
      try { api = fn(vfx, presetAt(at), opts || {}); } finally { capture = prev; }
      if (api && typeof api === 'object') extendGroup(group, api);
      shared.track(group);
      return group;
    },

    /** Names of the registered presets. */
    presets() { return [...presets.keys()]; },

    dispose() {
      for (const m of modules) if (m.dispose) m.dispose();
      textures.dispose();
      root.removeFromParent();
    },
  };

  function extendGroup(group, api) {
    const ds = Object.getOwnPropertyDescriptors(api);
    for (const k in ds) {
      const d = ds[k];
      if (d.get) { Object.defineProperty(group, k, { get: d.get, enumerable: true, configurable: true }); continue; }
      if (typeof d.value !== 'function') { group[k] = d.value; continue; }
      const m = d.value;
      const inGroup = (...a) => { let r; shared.runInGroup(group, () => { r = m(...a); }); return r; };
      if (k === 'stop') { const base = group.stop; group.stop = () => { inGroup(); base(); }; } else group[k] = inGroup;
    }
  }

  function presetAt(src) {
    const a = {
      pos: new THREE.Vector3(), dir: new THREE.Vector3(), facing: 1, scale: 1, color: null, target: null, raw: src,
      local(f = 0, u = 0, s = 0, out = new THREE.Vector3()) { return out.set(a.pos.x + f * a.facing, a.pos.y + u, a.pos.z + s); },
    };
    if (src == null) { a.dir.set(1, 0, 0); return a; }
    if (src.isVector3 || Array.isArray(src)) { util.toVec3(src, a.pos); a.dir.set(1, 0, 0); return a; }
    util.toVec3(src.pos, a.pos);
    if (src.facing != null) a.facing = src.facing < 0 ? -1 : 1;
    if (src.dir != null) util.toVec3(src.dir, a.dir).normalize(); else a.dir.set(a.facing, 0, 0);
    if (src.scale != null) a.scale = src.scale;
    if (src.color != null) a.color = util.toColor(src.color);
    if (src.target != null) a.target = src.target;
    return a;
  }

  for (const install of MODULES) vfx.use(install);

  ctx.onUpdate((dtGame, dtReal) => {
    uniforms.uTime.value = clock.game;
    uniforms.uTimeReal.value = clock.real;
    for (let i = 0; i < modules.length; i++) if (modules[i].update) modules[i].update(dtGame, dtReal);
  }, ctx.ORDER.VFX);

  ctx.vfx = vfx;
  return vfx;
}
