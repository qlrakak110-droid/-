// createMatch: round flow, sub-stepping, super-freeze, cinematic lock, push-boxes and the public match API.
//
// One substep (h <= rules.maxSubstep):
//   1. phase gate (intro countdown) / super-freeze / cinematic lock (these replace the normal update)
//   2. each fighter advances by h minus its remaining hit-stop (input buffer ages on the same fighter clock)
//   3. push-boxes and walls, cooldowns
//   4. projectiles move, expire and clash
//   5. contacts: both fighters' strikes and every projectile are collected first, then resolved together (trades)
//   6. meters regenerate, the round clock runs, KO / time-up / round transitions

import { DEFAULT_RULES, NEUTRAL_INPUT } from './constants.js';
import { compileFighterDef } from './defs.js';
import { createEventQueue } from './events.js';
import { normalizeInput, feedInput, ageInput, clearInput } from './input.js';
import { toRng, forkRng } from './rng.js';
import {
  createFighter, resetFighter, updateFighter, setState, passesThrough, refreshFlags, moveBlockReason, endMove,
} from './fighter.js';
import { collectStrikes, resolveContacts, hurtContact } from './combat.js';
import { updateProjectiles, collectProjectileHits, compactProjectiles, clearProjectiles } from './projectiles.js';
import { updateCinematic } from './cinematic.js';
import { regenMeters } from './meters.js';

/** Deep-merge partial rules over the defaults (plain objects merge key by key, everything else replaces). */
export function mergeRules(base, over) {
  const out = {};
  for (const k of Object.keys(base)) {
    const b = base[k], o = over ? over[k] : undefined;
    if (b && typeof b === 'object' && !Array.isArray(b)) out[k] = mergeRules(b, o && typeof o === 'object' ? o : {});
    else out[k] = o !== undefined ? o : b;
  }
  if (over) for (const k of Object.keys(over)) if (!(k in base)) throw new Error(`rules.${k}: unknown rule`);
  return out;
}

function checkRules(R) {
  const pos = ['roundTime', 'arenaHalfWidth', 'gravity', 'maxSubstep', 'maxStep', 'maxSeparation'];
  for (const k of pos) if (!(typeof R[k] === 'number' && R[k] > 0)) throw new Error(`rules.${k}: expected a positive number, got ${R[k]}`);
  if (!(Number.isInteger(R.roundsToWin) && R.roundsToWin >= 1)) throw new Error(`rules.roundsToWin: expected an integer >= 1, got ${R.roundsToWin}`);
  if (!(Number.isInteger(R.maxRounds) && R.maxRounds >= R.roundsToWin)) throw new Error(`rules.maxRounds: expected an integer >= roundsToWin, got ${R.maxRounds}`);
  if (R.maxSubstep > 1 / 30) throw new Error('rules.maxSubstep: must be <= 1/30 s');
}

/**
 * Create a match.
 * @param {object} opts
 * @param {object[]} opts.fighters    two fighter definitions (author format; validated, throws on errors)
 * @param {object[]} [opts.controllers] two controllers ({update(view) -> input}); null = no input
 * @param {object} [opts.rules]       partial rules (see DEFAULT_RULES)
 * @param {number|Function} [opts.rng] seed or rng function (one value is drawn to seed the match's own stream)
 * @returns {object} match
 */
export function createMatch({ fighters, controllers = [], rules = {}, rng } = {}) {
  if (!Array.isArray(fighters) || fighters.length !== 2) throw new Error('createMatch: `fighters` must be an array of two fighter definitions');
  const R = mergeRules(DEFAULT_RULES, rules);
  checkRules(R);
  const events = createEventQueue();
  const seedRng = toRng(rng);
  const m = {
    rules: R,
    events,
    defs: fighters.map((d) => compileFighterDef(d, R)),
    fighters: [],
    projectiles: [],
    controllers: [null, null],
    rng: forkRng(seedRng),
    time: 0,
    phase: 'intro',
    phaseTime: 0,
    round: 0,
    clock: R.roundTime,
    roundWinner: null,
    roundReason: null,
    winner: null,
    freeze: null,
    cine: null,
    side: 1,
    nextProjectileId: 1,
    koQueue: [],
    steps: 0,

    /** Subscribe: on(name, fn(payload)) or on('*', fn(name, payload)). Returns off(). */
    on: (name, fn) => events.on(name, fn),
    off: (name, fn) => events.off(name, fn),
    /** internal: queue an event (stamped with the match time) */
    emit(name, payload) { payload.time = m.time; events.push(name, payload); },
    hurtContact,

    step, snapshot, reset, restartRound, setController, setMeter, place, slots, canUse,
  };
  m.fighters = m.defs.map((d, i) => createFighter(m, d, i));
  const views = m.fighters.map((f, i) => ({ match: m, index: i, self: f, opponent: null, dt: 0, time: 0, roundTime: 0, phase: 'intro' }));
  views[0].opponent = m.fighters[1];
  views[1].opponent = m.fighters[0];
  const tmpInput = { ...NEUTRAL_INPUT };
  const contacts = [];

  for (let i = 0; i < 2; i++) setController(i, controllers[i] || null);
  startRound(1, true);
  events.flush();

  // -------------------------------------------------------------------------------------------------------------

  /**
   * Advance the match by `dt` seconds (any dt; internally sub-stepped to rules.maxSubstep, clamped to rules.maxStep).
   * Controllers are polled once per call. Events raised during the step are dispatched when it returns.
   */
  function step(dt) {
    if (!(dt > 0)) { events.flush(); return m; }
    dt = Math.min(dt, R.maxStep);
    const live = m.phase === 'fight';
    for (let i = 0; i < 2; i++) {
      const f = m.fighters[i];
      const v = views[i];
      v.dt = dt; v.time = m.time; v.phase = m.phase; v.roundTime = m.phase === 'fight' ? R.roundTime - m.clock : 0;
      const c = m.controllers[i];
      const raw = c ? c.update(v) : null;
      if (live) feedInput(f.input, normalizeInput(raw, tmpInput), m.time, R);
      else clearInput(f.input);
    }
    const n = Math.max(1, Math.ceil(dt / R.maxSubstep - 1e-9));
    const h = dt / n;
    for (let k = 0; k < n; k++) substep(h);
    m.steps++;
    events.flush();
    return m;
  }

  function substep(h) {
    m.time += h;
    m.phaseTime += h;
    const F = m.fighters;
    if (m.phase === 'intro') {
      if (m.phaseTime >= R.introTime) beginFight();
      else return;
    }
    if (m.freeze) { freezeStep(h); return; }
    if (m.cine) {
      updateCinematic(m, h);
      for (const f of F) ageInput(f.input, h, R);
      afterContacts(h, false);
      return;
    }
    for (const f of F) {
      let fh = h;
      if (f.hitstop > 0) {
        const u = Math.min(f.hitstop, h);
        f.hitstop -= u;
        fh -= u;
        if (f.hitstop <= 1e-12) { f.hitstop = 0; f.hitstopShake = false; }
      }
      if (fh > 1e-9) {
        ageInput(f.input, fh, R);
        updateFighter(m, f, fh);
      } else f._moveAdvanced = false;
    }
    resolvePush();
    for (const f of F) {
      if (f.dodgeCooldown > 0) f.dodgeCooldown = Math.max(0, f.dodgeCooldown - h);
      for (const k in f.cooldowns) if (f.cooldowns[k] > 0) f.cooldowns[k] = Math.max(0, f.cooldowns[k] - h);
    }
    updateProjectiles(m, h);
    if (m.phase === 'fight') {
      collectStrikes(m, F[0], contacts);
      collectStrikes(m, F[1], contacts);
      collectProjectileHits(m, contacts);
      resolveContacts(m, contacts);
    }
    compactProjectiles(m);
    afterContacts(h, true);
  }

  function freezeStep(h) {
    const fz = m.freeze;
    const o = m.fighters[fz.owner], v = m.fighters[1 - fz.owner];
    fz.remaining -= h;
    if (fz.userAnimates) {
      ageInput(o.input, h, R);
      updateFighter(m, o, h);
    }
    ageInput(v.input, h, R);
    resolvePush();
    if (fz.remaining <= 1e-9) {
      m.freeze = null;
      m.emit('superFreezeEnd', { fighter: fz.owner, move: fz.move });
    }
    for (const f of m.fighters) refreshFlags(m, f);
  }

  function afterContacts(h, live) {
    const F = m.fighters;
    if (m.phase === 'fight') {
      if (live) for (const f of F) regenMeters(m, f, h);
      if (m.koQueue.length) {
        const alive = F.filter((f) => f.hp > 0);
        m.roundWinner = alive.length === 1 ? alive[0].index : -1;
        m.roundReason = alive.length === 1 ? 'ko' : 'doubleKo';
        m.koQueue.length = 0;
        setPhase('ko');
      } else if (live && !m.cine) {
        m.clock = Math.max(0, m.clock - h);
        if (m.clock <= 0) {
          const r0 = F[0].hp / F[0].hpMax, r1 = F[1].hp / F[1].hpMax;
          m.roundWinner = Math.abs(r0 - r1) < 1e-9 ? -1 : r0 > r1 ? 0 : 1;
          m.roundReason = 'time';
          m.emit('timeUp', { winner: m.roundWinner, hp: [F[0].hp, F[1].hp] });
          setPhase('timeup');
        }
      }
    } else if (m.phase === 'ko' && m.phaseTime >= R.koTime) endRound();
    else if (m.phase === 'timeup' && m.phaseTime >= R.timeUpTime) endRound();
    else if (m.phase === 'outro' && m.phaseTime >= R.outroTime) nextRoundOrEnd();
    for (const f of F) refreshFlags(m, f);
  }

  function setPhase(p) {
    const from = m.phase;
    m.phase = p;
    m.phaseTime = 0;
    m.emit('phase', { from, to: p, round: m.round });
  }

  function beginFight() {
    setPhase('fight');
    for (const f of m.fighters) {
      clearInput(f.input);
      setState(m, f, 'idle');
    }
    m.emit('fightStart', { round: m.round, clock: m.clock });
  }

  function startRound(n, fresh) {
    m.round = n;
    m.freeze = null;
    m.cine = null;
    m.roundWinner = null;
    m.roundReason = null;
    m.koQueue.length = 0;
    m.clock = R.roundTime;
    m.side = 1;
    clearProjectiles(m, 'round');
    m.fighters.forEach((f, i) => {
      if (f.move) endMove(m, f, 'round');
      resetFighter(m, f, i === 0 ? -R.startX : R.startX, i === 0 ? 1 : -1, fresh || !R.meters.ultCarry);
      clearInput(f.input);
    });
    setPhase('intro');
    m.emit('roundStart', { round: n, rounds: m.fighters.map((f) => f.rounds), introTime: R.introTime, clock: m.clock });
    if (R.introTime <= 0) beginFight();
  }

  function decideMatch() {
    const [a, b] = m.fighters.map((f) => f.rounds);
    const need = R.roundsToWin;
    if (a >= need && a > b) return 0;
    if (b >= need && b > a) return 1;
    if (m.round >= R.maxRounds) return a > b ? 0 : b > a ? 1 : -1;
    return null;
  }

  function endRound() {
    const F = m.fighters;
    const w = m.roundWinner;
    if (w >= 0) F[w].rounds++;
    else { F[0].rounds++; F[1].rounds++; }
    const decided = decideMatch();
    for (const f of F) {
      f.result = w < 0 ? 'draw' : f.index === w ? 'win' : 'lose';
      if (f.state === 'idle' || f.state === 'walk' || f.state === 'guard') setState(m, f, f.result === 'win' ? 'victory' : 'defeat');
    }
    clearProjectiles(m, 'round');
    m.emit('roundEnd', {
      round: m.round, winner: w, reason: m.roundReason, hp: F.map((f) => f.hp), rounds: F.map((f) => f.rounds),
      clock: m.clock, matchOver: decided !== null, matchWinner: decided,
    });
    setPhase('outro');
  }

  function nextRoundOrEnd() {
    const w = decideMatch();
    if (w === null) { startRound(m.round + 1, false); return; }
    m.winner = w;
    setPhase('end');
    m.emit('matchEnd', { winner: w, rounds: m.fighters.map((f) => f.rounds), roundsPlayed: m.round });
  }

  function resolvePush() {
    const [a, b] = m.fighters;
    if (passesThrough(m, a) || passesThrough(m, b)) return;
    if (Math.abs(a.y - b.y) > 1.3) return;
    const pa = a.def.stats.pushWidth, pb = b.def.stats.pushWidth;
    const dx = b.x - a.x;
    const side = dx > 1e-6 ? 1 : dx < -1e-6 ? -1 : m.side;
    m.side = side;
    const ov = pa + pb - side * dx;
    if (ov <= 0) return;
    const L = R.arenaHalfWidth;
    const la = L - pa, lb = L - pb;
    let ax = a.x - side * ov * 0.5, bx = b.x + side * ov * 0.5;
    if (ax < -la) { bx += -la - ax; ax = -la; } else if (ax > la) { bx -= ax - la; ax = la; }
    if (bx < -lb) { ax += -lb - bx; bx = -lb; } else if (bx > lb) { ax -= bx - lb; bx = lb; }
    a.x = ax;
    b.x = bx;
  }

  // -------------------------------------------------------------------------------------------------------------
  // public helpers

  /** A JSON-safe picture of the whole match (debugging, bug reports). */
  function snapshot() {
    const r3 = (v) => Math.round(v * 1000) / 1000;
    return {
      time: r3(m.time), phase: m.phase, round: m.round, clock: r3(m.clock), winner: m.winner,
      roundWinner: m.roundWinner, roundReason: m.roundReason,
      freeze: m.freeze ? { owner: m.freeze.owner, move: m.freeze.move, remaining: r3(m.freeze.remaining) } : null,
      cinematic: m.cine ? { attacker: m.cine.attacker, defender: m.cine.defender, move: m.cine.move, t: r3(m.cine.t), duration: m.cine.duration } : null,
      fighters: m.fighters.map((f) => ({
        index: f.index, id: f.id, x: r3(f.x), y: r3(f.y), vx: r3(f.vx), vy: r3(f.vy), facing: f.facing,
        state: f.state, stateTime: r3(f.stateTime), timer: r3(f.timer), stunKind: f.stunKind,
        move: f.move, moveTime: r3(f.moveTime), hitstop: r3(f.hitstop),
        hp: f.hp, fp: r3(f.fp), ult: r3(f.ult), guard: r3(f.guard), rounds: f.rounds,
        combo: { ...f.combo }, recv: { ...f.recv }, cooldowns: Object.fromEntries(Object.entries(f.cooldowns).map(([k, v]) => [k, r3(v)])),
        invulnerable: f.invulnerable, armoured: f.armoured, buffer: f.input.buffer.map((e) => e.button),
      })),
      projectiles: m.projectiles.map((p) => ({ id: p.id, owner: p.owner, kind: p.kind, x: r3(p.x), y: r3(p.y), vx: p.vx, age: r3(p.age), hits: p.hits, active: p.active })),
    };
  }

  /** Restart the whole match from round 1 (ULT and round wins cleared). */
  function reset() {
    for (const f of m.fighters) f.rounds = 0;
    m.winner = null;
    startRound(1, true);
    events.flush();
    return m;
  }

  /** Restart the current round (meters reset as at a round start; ULT kept; round wins kept). */
  function restartRound() {
    startRound(Math.max(1, m.round), false);
    events.flush();
    return m;
  }

  /** Attach a controller to fighter i (calls controller.attach({match, index, rng}) when present). */
  function setController(i, c) {
    m.controllers[i] = c || null;
    if (c && typeof c.attach === 'function') c.attach({ match: m, index: i, rng: forkRng(m.rng) });
  }

  /** Set a meter directly (training mode, tests): kind 'hp' | 'fp' | 'ult' | 'guard'. */
  function setMeter(i, kind, value) {
    const f = m.fighters[i];
    const max = { hp: f.hpMax, fp: f.fpMax, ult: f.ultMax, guard: f.guardMax }[kind];
    if (max === undefined) throw new Error(`setMeter: unknown meter '${kind}'`);
    f[kind] = Math.max(0, Math.min(max, value));
    return m;
  }

  /** Place fighter i at x (and facing) — training mode and tests. */
  function place(i, x, facing) {
    const f = m.fighters[i];
    f.x = x; f.y = 0; f.vx = 0; f.vy = 0;
    if (facing === 1 || facing === -1) f.facing = facing;
    return m;
  }

  /**
   * HUD helper: one entry per command key of fighter i:
   * {key, move, name, group, fpCost, ultCost, cooldown (s left), cd (0..1 of the cooldown left), ready}
   */
  function slots(i) {
    const f = m.fighters[i];
    return Object.entries(f.def.commands).map(([key, id]) => {
      const mv = f.def.moves[id];
      const left = f.cooldowns[mv.cooldownKey] || 0;
      return {
        key, move: id, name: mv.name, group: mv.group, fpCost: mv.fpCost, ultCost: mv.ultCost,
        cooldown: left, cd: mv.cooldown > 0 ? left / mv.cooldown : 0,
        ready: left <= 0 && f.fp + 1e-9 >= mv.fpCost && (mv.ultCost <= 0 || f.ult + 1e-9 >= mv.ultCost),
      };
    });
  }

  /** Why fighter i cannot start move `id` right now (null when it could, ignoring its current state). */
  function canUse(i, id) {
    const f = m.fighters[i];
    const mv = f.def.moves[id];
    if (!mv) return 'unknown';
    return moveBlockReason(m, f, mv);
  }

  return m;
}
