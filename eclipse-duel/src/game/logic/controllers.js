// Controllers feed one fighter's held input to the match once per match.step().
//
//   controller = { kind, update(view) -> input, attach?({match, index, rng}), reset?() }
//   view       = { match, index, self, opponent, dt, time, phase, roundTime }
//   input      = { move: -1|0|1 (world X), up, down, light, heavy, skill1, skill2, skill3, ult, guard, dodge }  (held)
//
// The engine derives presses from held state, so a controller only ever reports what is held right now.

import { NEUTRAL_INPUT } from './constants.js';

/** A controller that never presses anything. */
export function createIdleController() {
  return { kind: 'idle', update: () => NEUTRAL_INPUT };
}

/**
 * Human player: reads an input-state provider every step.
 * @param {(index: number, view: object) => object} provider returns the held input state (missing fields = released)
 */
export function createHumanController(provider) {
  if (typeof provider !== 'function') throw new Error('createHumanController: provider must be a function (index, view) => input');
  return { kind: 'human', update: (view) => provider(view.index, view) };
}

/**
 * Adapter from an action-based input module (CONTRACT: input.held(action, player)) to an input-state provider.
 * Usage: createHumanController(actionsProvider((a, p) => ctx.input.held(a, p)))
 * @param {(action: string, player: number) => boolean} held
 * @param {number} [player] player slot to read (defaults to the fighter index)
 */
export function actionsProvider(held, player) {
  return (index) => {
    const p = player === undefined ? index : player;
    return {
      move: (held('right', p) ? 1 : 0) - (held('left', p) ? 1 : 0),
      up: held('up', p), down: held('down', p),
      light: held('light', p), heavy: held('heavy', p),
      skill1: held('skill1', p), skill2: held('skill2', p), skill3: held('skill3', p),
      ult: held('ult', p), guard: held('guard', p), dodge: held('dodge', p),
    };
  };
}

/**
 * Scripted controller: a list of timed inputs (tests, demos, attract mode).
 *   [{ t: 0.5, light: true }, { t: 1.0, dur: 0.6, move: 1 }, { t: 2, guard: true, dur: 1 }]
 * Each entry is held from `t` for `dur` seconds (default 0.05). Overlapping entries combine (buttons OR'd, the latest
 * entry's `move` wins). Times are seconds since the current round's fight began (view.roundTime), or match time with
 * { clock: 'match' }. Alternatively pass a function (t, view) => input.
 * @param {object[]|Function} script
 * @param {{clock?: 'round'|'match', loop?: number}} [opts] loop: repeat the script every `loop` seconds
 */
export function createScriptedController(script, { clock = 'round', loop = 0 } = {}) {
  const out = { ...NEUTRAL_INPUT };
  const isFn = typeof script === 'function';
  const list = isFn ? null : script.map((e) => ({ ...e, dur: e.dur === undefined ? 0.05 : e.dur })).sort((a, b) => a.t - b.t);
  return {
    kind: 'scripted',
    update(view) {
      let t = clock === 'match' ? view.time : view.roundTime;
      if (view.phase !== 'fight' && clock !== 'match') return NEUTRAL_INPUT;
      if (loop > 0) t %= loop;
      if (isFn) return script(t, view);
      Object.assign(out, NEUTRAL_INPUT);
      for (const e of list) {
        if (e.t > t) break;
        if (t >= e.t + e.dur) continue;
        for (const k in e) {
          if (k === 't' || k === 'dur') continue;
          if (k === 'move') out.move = e.move;
          else if (e[k]) out[k] = true;
        }
      }
      return out;
    },
  };
}
