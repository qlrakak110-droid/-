// Default progression of the RPG mode (README §12). Replaced by src/rpg/progress.js when the HUD team ships one.
// Four stats: 생명력 Vigor (HP), 지구력 Endurance (stamina), 완력 Might (physical damage), 비전 Arcana (FP + skill /
// ultimate damage). State is saved per hero in localStorage (inside try / catch: blocked storage only loses progress).

const KEY = 'ed.rpg.';
export const STATS = ['vigor', 'endurance', 'might', 'arcana'];

const fresh = () => ({ level: 1, stats: { vigor: 0, endurance: 0, might: 0, arcana: 0 }, shards: 0, dropped: null, cycle: 0 });

export const defaultProgress = {
  STATS,
  /** @returns {object} state */
  load(heroId) {
    const s = fresh();
    try {
      const raw = typeof localStorage !== 'undefined' ? localStorage.getItem(KEY + heroId) : null;
      if (raw) {
        const o = JSON.parse(raw);
        if (o && typeof o === 'object') {
          s.level = Math.max(1, o.level | 0) || 1;
          for (const k of STATS) s.stats[k] = Math.max(0, (o.stats && o.stats[k]) | 0);
          s.shards = Math.max(0, o.shards | 0);
          s.cycle = Math.max(0, o.cycle | 0);
          if (o.dropped && Number.isFinite(o.dropped.x) && Number.isFinite(o.dropped.z) && o.dropped.amount > 0) s.dropped = { x: o.dropped.x, z: o.dropped.z, amount: o.dropped.amount | 0 };
        }
      }
    } catch (e) { /* storage unavailable or corrupt: a fresh hero */ }
    return s;
  },
  save(heroId, state) {
    try { if (typeof localStorage !== 'undefined') localStorage.setItem(KEY + heroId, JSON.stringify(state)); } catch (e) { /* storage blocked */ }
  },
  /**
   * @param {object} state
   * @param {{ hp: number, fp: number, stamina: number }} base hero base numbers (fighter stats)
   */
  derive(state, base) {
    const s = state.stats;
    const hpMax = Math.round(base.hp * (1 + 0.06 * s.vigor));
    return {
      hpMax,
      staminaMax: Math.round(base.stamina * (1 + 0.05 * s.endurance)),
      fpMax: Math.round(base.fp * (1 + 0.04 * s.arcana)),
      phys: 1 + 0.05 * s.might,
      arcane: 1 + 0.05 * s.arcana,
      chaliceMax: 3,
      chaliceHeal: Math.round(hpMax * 0.42),
    };
  },
  /** Shards the next level costs. */
  cost(level) { return Math.round(90 * Math.pow(1.14, Math.max(0, level - 1))); },
  /** Spend shards and raise a stat. */
  levelUp(state, stat) {
    if (!STATS.includes(stat)) return false;
    const c = defaultProgress.cost(state.level);
    if (state.shards < c) return false;
    state.shards -= c;
    state.level++;
    state.stats[stat]++;
    return true;
  },
};

export default defaultProgress;
