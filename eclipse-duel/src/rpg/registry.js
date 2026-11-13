// Plug-in registry of the RPG mode (README §3). The core registers its built-ins here; the boss / foes / world / ui
// teams register theirs from `install(rpg)` in their own folders. Modules are discovered with esbuild glob imports:
// every `./<dir>/index.js` and `./pro*.js` that exists is bundled, a missing one is a runtime miss (never a build error),
// so the mode builds and runs with any subset of the folders present.
//
//   import { registry } from './registry.js';
//   registry.actor('husk', spec); registry.encounter(def); registry.world(factory); registry.ui(factory);

const warned = new Set();
function warn(key, msg) {
  if (warned.has(key)) return;
  warned.add(key);
  console.warn('[ed] rpg: ' + msg);
}

/** Optional plug-in folders, loaded in this order. */
export const PLUGINS = ['world', 'foes', 'boss', 'ui'];

// esbuild turns the template into a glob (`./**/*/index.js`, `./pro*.js`) and bundles every match
const IMPORTERS = {
  dir: (name) => import(`./${name}/index.js`),
  file: (name) => import(`./pro${name}.js`),
};

function createRegistry() {
  const listeners = [];
  const reg = {
    /** kind name -> spec */
    kinds: new Map(),
    /** encounter id -> def */
    encounters: new Map(),
    worldFactory: null,
    uiFactory: null,
    progressObj: null,
    setups: [],
    prewarms: [],
    /** which optional modules were found: { world: true, foes: false, ... } */
    found: {},
    /** true while the core registers its stand-ins (so a plug-in's registration is told apart from them) */
    builtin: false,

    /** Register (or replace) an actor kind. */
    actor(kind, spec) {
      if (!kind || !spec) throw new Error('rpg.actor(kind, spec)');
      reg.kinds.set(kind, { ...spec, kind, builtin: reg.builtin });
      return reg;
    },
    /** Register (or replace by id) an encounter. */
    encounter(def) {
      if (!def || !def.id) throw new Error('rpg.encounter({ id, ... })');
      reg.encounters.set(def.id, { order: 50, spawns: [], boss: false, ...def, builtin: reg.builtin });
      return reg;
    },
    /** World dressing factory (ctx, world) -> { update?, dispose?, altar?, gate?, heroSpawn? }. */
    world(factory) { reg.worldFactory = factory; return reg; },
    /** HUD factory (ctx, api) -> { start(snapshot), stop(), update(snapshot, dtReal), dispose?() }. */
    ui(factory) { reg.uiFactory = factory; return reg; },
    /** Progression object (README §12). */
    progress(obj) { reg.progressObj = obj; return reg; },
    /** fn({ ctx, vfx, fx }) once at boot, before the VFX prewarm. */
    setup(fn) { reg.setups.push(fn); return reg; },
    /** fn(ctx, world) at every start, before the compile pass. */
    prewarm(fn) { reg.prewarms.push(fn); return reg; },
    /** Subscribe to world events for the lifetime of the page (bound to every new world). */
    on(event, fn) { listeners.push([event, fn]); return reg; },
    /** @private bind the page-lifetime listeners to a new world */
    bind(world) { for (const [ev, fn] of listeners) world.on(ev, fn); },

    /** Encounters in play order; plug-in encounters replace the core's stand-ins of the same class (ordinary / boss). */
    playlist() {
      const all = [...reg.encounters.values()];
      const own = all.filter((e) => !e.builtin);
      const ownOrdinary = own.some((e) => !e.boss), ownBoss = own.some((e) => e.boss);
      return all.filter((e) => !e.builtin || (e.boss ? !ownBoss : !ownOrdinary)).sort((a, b) => (a.boss ? 1 : 0) - (b.boss ? 1 : 0) || a.order - b.order);
    },

    /**
     * Discover and install the optional modules (`./world`, `./foes`, `./boss`, `./ui`, `./progress.js`). Never throws:
     * a missing module is skipped, a module that throws is reported once and skipped.
     */
    async discover() {
      for (const name of PLUGINS) {
        let mod = null;
        try { mod = await IMPORTERS.dir(name); } catch (e) {
          if (!/not found in bundle|Cannot find module|Failed to fetch|Could not resolve/i.test(String(e && e.message))) warn('load:' + name, `${name}/index.js failed to load: ${e && (e.stack || e.message)}`);
        }
        reg.found[name] = !!mod;
        if (!mod) continue;
        const install = typeof mod.default === 'function' ? mod.default : typeof mod.install === 'function' ? mod.install : null;
        if (!install) { warn('install:' + name, `${name}/index.js has no install(rpg) export`); continue; }
        try { await install(reg); } catch (e) { warn('run:' + name, `${name}/index.js install() threw: ${e && (e.stack || e.message)}`); }
      }
      let prog = null;
      try { prog = await IMPORTERS.file('gress'); } catch (e) {
        if (!/not found in bundle|Cannot find module|Failed to fetch|Could not resolve/i.test(String(e && e.message))) warn('load:progress', `progress.js failed to load: ${e && (e.stack || e.message)}`);
      }
      reg.found.progress = !!prog;
      if (prog) {
        try {
          if (typeof prog.install === 'function') await prog.install(reg);
          else if (prog.default && typeof prog.default === 'object') reg.progress(prog.default);
          else if (typeof prog.default === 'function') await prog.default(reg);
        } catch (e) { warn('run:progress', `progress.js threw: ${e && (e.stack || e.message)}`); }
      }
      return reg.found;
    },
  };
  return reg;
}

/** The one registry of the page. */
export const registry = createRegistry();
export default registry;
