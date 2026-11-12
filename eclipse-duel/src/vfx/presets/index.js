// Composed preset library (stage 3): installs every family through vfx.define so game code plays them with
// vfx.play(name, at, opts). Families live one per file: combat (element-neutral hits, guards, dust, whooshes, charge,
// KO, ultimate flash), ember (Kael), frost (Iska), volt (Vorn). See README "Preset catalogue".
//
// Every preset takes at = { pos, dir?, facing?, scale?, color?, target? } and opts with at least `intensity` (0.5..2,
// brightness and counts) and `realtime` (run everything on real time: KO slow motion, super-freeze). Presets spawn
// world-space VFX only (no camera, no post pulses) and stagger their layers with vfx.schedule.

import { DEFS, realtimeView } from './common.js';
import { createMotion } from './motion.js';
import { defineCombat } from './combat.js';
import { defineEmber } from './ember.js';
import { defineFrost } from './frost.js';
import { defineVolt } from './volt.js';

/**
 * Sub-module installer (appended to MODULES in ../index.js).
 * @param {object} vfx
 * @param {object} shared
 */
export function installPresets(vfx, shared) {
  const motion = createMotion(shared);
  const RT = realtimeView(vfx);
  const fns = new Map();
  const P = {
    rng: shared.rng,
    motion,
    /** the realtime view of vfx (spawns default to realtime: true) */
    rt: RT,
    /** define a preset; with opts.realtime it receives the realtime view instead of vfx */
    define(name, fn) {
      fns.set(name, fn);
      vfx.define(name, (v, at, o) => fn(o.realtime ? RT : v, at, o));
    },
    /** run another preset's body inside the current group with the same view */
    run(name, v, at, o) { return fns.get(name)(v, at, o); },
    /** register `name` as another name for `target` */
    alias(name, target) { P.define(name, (v, at, o) => P.run(target, v, at, o)); },
  };
  defineCombat(vfx, P);
  defineEmber(vfx, P);
  defineFrost(vfx, P);
  defineVolt(vfx, P);

  return {
    name: 'presets',
    api: {
      /** particle definitions the presets use (already registered by vfx.prewarm) */
      presetDefs: DEFS,
    },
    update(dtGame, dtReal) { motion.update(dtGame, dtReal); },
    clear() { motion.clear(); },
    prewarm() { for (const d of DEFS) vfx.particles.compile(d); },
  };
}
