// AI controller: generic over any fighter definition. It reads its own fighter directly and the opponent through a
// delayed perception buffer (the reaction delay), and plays through the same input path as a human (held buttons,
// presses derived by the engine). Decisions use per-move `ai` hints when present and frame data derived from the
// move data otherwise (startup, reach, recovery, advantage).
//
// Layers, evaluated every step (first one that acts wins):
//   1. self-preservation  tech rolls, wake-up guard / reversal, holding guard through block strings
//   2. combo              hit-confirm (or pressure on block) and pick the best cancel / route the data allows
//   3. defence            guard, dodge, counter-stance or back off against attacks / projectiles it has *perceived*
//   4. punish             blocked or whiffed moves with enough recovery, guard breaks, juggles, okizeme
//   5. neutral            on think ticks, by distance zone (far / mid / close) and initiative (who is plus):
//                         approach, dash, poke, zone, retreat, wait, anticipatory guard, skills, ultimate
// Difficulty scales the reaction delay, every probability above, spacing discipline and the mistake rate.

import { deriveFrameData } from './framedata.js';
import { NEUTRAL_INPUT } from './constants.js';
import { forwardAt } from './moves.js';
import { backToWall } from './fighter.js';
import { toRng } from './rng.js';

/**
 * Difficulty presets. Every field can be overridden through createAIController({ overrides }).
 * Probabilities are per decision (each perceived attack, punish window, combo step ... is judged once).
 *   reaction   s     perception delay: the AI sees its opponent this many seconds late
 *   think      [s,s] interval between neutral decisions
 *   tempo      0..1  how often a neutral decision is an attack (easy waits and walks much more)
 *   guard / dodge / counter / backoff   chance to answer a perceived attack with guard / dodge / counter stance / retreat
 *   holdGuard  keep blocking through a block string     perfect  time guards and dodges at the impact (perfect guard)
 *   punish / whiffPunish   punish blocked / whiffed recovery     read   respect counter stances (wait, then punish)
 *   confirm    s     hit-confirm delay before a cancel   combo / blockString / mash   continue on hit / on block / on whiff
 *   depth      max cancels in one combo                   juggle   follow a launch       meaty   time attacks on get-up
 *   tech / wakeGuard / reversal   tech roll, guard on wake-up, counter-stance reversal on wake-up
 *   spacing    footsies discipline (hold the preferred range, back off)   variety  avoid repeating the same move
 *   skill / ult   appetite for FP skills / the ultimate   mistake  chance a neutral decision is random
 *   aggression 0..1 rushdown vs patience (mixed with the fighter's own ai.aggression)   patience  waiting / guarding
 *   noise      random spread of option weights
 */
export const AI_LEVELS = {
  easy: {
    reaction: 0.42, think: [0.22, 0.45], tempo: 0.5, guard: 0.3, dodge: 0.05, counter: 0.04, backoff: 0.15, holdGuard: 0.45,
    perfect: 0, punish: 0.15, whiffPunish: 0.08, read: 0.05, confirm: 0.32, combo: 0.35, blockString: 0.3, mash: 0.3,
    depth: 1, juggle: 0.2, meaty: 0.1, tech: 0.1, wakeGuard: 0.3, reversal: 0.03, spacing: 0.15, variety: 0.3,
    skill: 0.3, ult: 0.35, mistake: 0.2, aggression: 0.45, patience: 0.35, noise: 0.5,
  },
  normal: {
    reaction: 0.26, think: [0.12, 0.24], tempo: 0.8, guard: 0.5, dodge: 0.12, counter: 0.1, backoff: 0.25, holdGuard: 0.65,
    perfect: 0.1, punish: 0.52, whiffPunish: 0.3, read: 0.35, confirm: 0.2, combo: 0.72, blockString: 0.45, mash: 0.15,
    depth: 3, juggle: 0.55, meaty: 0.35, tech: 0.35, wakeGuard: 0.55, reversal: 0.08, spacing: 0.45, variety: 0.45,
    skill: 0.55, ult: 0.65, mistake: 0.08, aggression: 0.55, patience: 0.55, noise: 0.3,
  },
  hard: {
    reaction: 0.22, think: [0.07, 0.14], tempo: 0.86, guard: 0.62, dodge: 0.2, counter: 0.14, backoff: 0.32, holdGuard: 0.8,
    perfect: 0.2, punish: 0.66, whiffPunish: 0.55, read: 0.6, confirm: 0.12, combo: 0.88, blockString: 0.5, mash: 0.08,
    depth: 3, juggle: 0.8, meaty: 0.6, tech: 0.6, wakeGuard: 0.7, reversal: 0.12, spacing: 0.7, variety: 0.65,
    skill: 0.7, ult: 0.85, mistake: 0.035, aggression: 0.6, patience: 0.7, noise: 0.18,
  },
  nightmare: {
    reaction: 0.14, think: [0.04, 0.09], tempo: 1, guard: 0.76, dodge: 0.28, counter: 0.18, backoff: 0.38, holdGuard: 0.9,
    perfect: 0.6, punish: 0.93, whiffPunish: 0.8, read: 0.9, confirm: 0.07, combo: 0.97, blockString: 0.55, mash: 0.02,
    depth: 8, juggle: 0.95, meaty: 0.8, tech: 0.85, wakeGuard: 0.8, reversal: 0.15, spacing: 0.92, variety: 0.8,
    skill: 0.85, ult: 0.95, mistake: 0.012, aggression: 0.62, patience: 0.8, noise: 0.1,
  },
};

const ACTIONABLE = new Set(['idle', 'walk', 'guard']);
const OP_DISADVANTAGE = new Set(['blockstun', 'hitstun', 'guardbreak', 'recovery']);
const HISTORY = 128;

// ---------------------------------------------------------------------------------------------------------------
// knowledge of a fighter definition (cached per compiled def)

const KNOW = new WeakMap();

function inferRole(mv, fd) {
  if (mv.cinematic) return 'finisher';
  if (mv.counter) return 'counter';
  if (fd.projectile) return 'zoning';
  if (!mv.hits.length) return 'mobility';
  if (fd.level === 'launch') return 'launcher';
  if (fd.motion > 1.5) return 'approach';
  if (fd.startup !== null && fd.startup <= 0.13) return 'poke';
  return 'pressure';
}

/**
 * What the AI knows about a compiled fighter def: per move frame data, role, range, weight and the command keys
 * that press it; the fastest strikes; its poke reach and its "threat reach" (how far its fast attacks hit).
 */
function knowledge(def) {
  let k = KNOW.get(def);
  if (k) return k;
  const moves = {};
  // moves reached only through a chain route (light1 -> light2 -> light3) are combo parts unless the author says otherwise
  const commanded = new Set(Object.values(def.commands));
  const routed = new Set();
  for (const mv of Object.values(def.moves)) for (const c of mv.cancels) if (c.on) routed.add(c.route);
  for (const id of Object.keys(def.moves)) {
    const mv = def.moves[id];
    const fd = deriveFrameData(mv);
    const ai = mv.ai || {};
    const role = ai.role || (routed.has(id) && !commanded.has(id) ? 'combo' : inferRole(mv, fd));
    const reach = fd.projectile ? fd.reach : fd.strikeReach;
    const range = ai.range || (fd.projectile ? [2.5, Math.min(9, reach)] : [0, reach]);
    moves[id] = { id, mv, fd, role, range, reach, weight: ai.weight !== undefined ? ai.weight : 1, comboOnly: !!ai.comboOnly, keys: [] };
  }
  for (const [key, id] of Object.entries(def.commands)) {
    const mm = /^(?:([dufb])\+)?(\w+)$/.exec(key);
    if (mm && moves[id]) moves[id].keys.push({ button: mm[2], dir: mm[1] || null });
  }
  const pressable = Object.values(moves).filter((x) => x.keys.length && !x.comboOnly);
  const strikes = pressable.filter((x) => x.mv.hits.length && x.fd.startup !== null && !x.mv.cinematic);
  strikes.sort((a, b) => a.fd.startup - b.fd.startup);
  const pokes = pressable.filter((x) => x.role === 'poke');
  const pokeReach = pokes.length ? Math.max(...pokes.map((x) => x.range[1])) : (strikes[0] ? strikes[0].reach : 1.6);
  const fast = pressable.filter((x) => !x.fd.projectile && x.mv.hits.length && x.fd.startup !== null && x.fd.startup < 0.3);
  const threatReach = Math.max(pokeReach, ...fast.map((x) => x.reach));
  k = { def, moves, pressable, strikes, pokeReach, threatReach };
  KNOW.set(def, k);
  return k;
}

// ---------------------------------------------------------------------------------------------------------------

/**
 * Create an AI controller.
 * @param {object} [opts]
 * @param {'easy'|'normal'|'hard'|'nightmare'} [opts.difficulty='normal']
 * @param {object} [opts.overrides] per-field overrides of the difficulty preset (see AI_LEVELS)
 * @param {number|Function} [opts.rng] seed / rng; by default the match hands one out on attach
 */
export function createAIController({ difficulty = 'normal', overrides = {}, rng } = {}) {
  if (!AI_LEVELS[difficulty]) throw new Error(`createAIController: unknown difficulty '${difficulty}' (use ${Object.keys(AI_LEVELS).join(', ')})`);
  const lv = { ...AI_LEVELS[difficulty], ...overrides };
  const ownRng = rng !== undefined;
  let R = ownRng ? toRng(rng) : toRng(1);

  // perception ring buffer of opponent observations (reused objects)
  const hist = [];
  for (let i = 0; i < HISTORY; i++) {
    hist.push({ t: -1, x: 0, y: 0, vx: 0, state: 'idle', stateTime: 0, move: null, moveTime: 0, serial: 0, connected: false, hard: false, timer: 0, guard: 1, hp: 1, invuln: false, proj: [] });
  }
  let head = -1, count = 0;

  const st = {
    nextThink: 0, busyUntil: 0,
    holdMove: 0, holdUntil: 0,          // +1 toward the opponent, -1 away
    holdGuard: false, holdGuardUntil: 0,
    presses: [],                        // [{button, dir, at}]
    decided: new Map(),                 // decision key -> outcome (each opponent action is judged once)
    comboSerial: -1, hitSerial: -1, hitSeenAt: -1,
    lastMoveId: null, lastState: 'idle',
    init: 'none', initUntil: 0,         // initiative: 'me' | 'them' | 'none'
    opAggro: 0.5, opGuard: 0.3, opSerial: -1,
    mySerial: -1, chain: 0, lastNeutral: null, streak: 0, // own moves: cancels in this combo, repeated neutral moves
    prevOut: { ...NEUTRAL_INPUT },
  };
  const out = { ...NEUTRAL_INPUT };

  function reset() {
    head = -1; count = 0;
    st.nextThink = 0; st.busyUntil = 0; st.holdMove = 0; st.holdUntil = 0; st.holdGuard = false; st.holdGuardUntil = 0;
    st.presses.length = 0; st.decided.clear(); st.comboSerial = -1; st.hitSerial = -1; st.hitSeenAt = -1;
    st.lastMoveId = null; st.lastState = 'idle'; st.init = 'none'; st.initUntil = 0;
    st.mySerial = -1; st.chain = 0; st.lastNeutral = null; st.streak = 0;
    Object.assign(st.prevOut, NEUTRAL_INPUT);
  }

  // ------------------------------------------------------------------------------------------------- perception
  function observe(match, op) {
    head = (head + 1) % HISTORY;
    count = Math.min(HISTORY, count + 1);
    const o = hist[head];
    o.t = match.time; o.x = op.x; o.y = op.y; o.vx = op.vx;
    o.state = op.state; o.stateTime = op.stateTime; o.move = op.move; o.moveTime = op.moveTime; o.serial = op.moveSerial;
    o.connected = op.moveConnected; o.hard = op.hard || op.koFall; o.timer = op.timer;
    o.guard = op.guard / op.guardMax; o.hp = op.hp / op.hpMax; o.invuln = op.invulnerable;
    o.proj.length = 0;
    for (const p of match.projectiles) {
      if (p.owner === op.index && p.alive) o.proj.push({ id: p.id, x: p.x, vx: p.vx, wait: p.delay - p.age, half: Math.max(Math.abs(p.spec.f0), Math.abs(p.spec.f1)), unblockable: p.spec.hit.unblockable });
    }
  }
  /** Most recent observation at least `delay` seconds old (or the oldest one kept). */
  function perceived(now, delay) {
    let best = null;
    for (let i = 0; i < count; i++) {
      const o = hist[(head - i + HISTORY) % HISTORY];
      best = o;
      if (o.t <= now - delay) break;
    }
    return best;
  }

  // ------------------------------------------------------------------------------------------------- helpers
  const press = (button, dir, at) => { st.presses.push({ button, dir, at }); };
  const hold = (rel, dur, now) => { st.holdMove = rel; st.holdUntil = now + dur; st.busyUntil = now + dur; };
  const guardFor = (dur, now) => { st.holdGuard = true; st.holdGuardUntil = Math.max(st.holdGuardUntil, now + dur); st.holdMove = 0; };
  const usable = (match, me, x) => match.canUse(me.index, x.id) === null;
  const keyOf = (x) => x.keys[0];
  const pressMove = (x, at) => { const k = keyOf(x); press(k.button, k.dir, at); st.holdGuard = false; };
  function once(key, p) {
    if (st.decided.has(key)) return st.decided.get(key);
    const v = R() < p;
    remember(key, v);
    return v;
  }
  function remember(key, v) {
    st.decided.set(key, v);
    if (st.decided.size > 256) st.decided.delete(st.decided.keys().next().value);
  }
  function pick(options) {
    let tot = 0;
    for (const o of options) tot += Math.max(0, o.w);
    if (tot <= 0) return null;
    let r = R() * tot;
    for (const o of options) { r -= Math.max(0, o.w); if (r <= 0) return o; }
    return options[options.length - 1];
  }
  const setInit = (who, dur, now) => { st.init = who; st.initUntil = now + dur; };

  // ------------------------------------------------------------------------------------------------- update
  function update(view) {
    const match = view.match, me = view.self, opNow = view.opponent;
    const now = match.time;
    observe(match, opNow);
    if (view.phase !== 'fight') {
      st.presses.length = 0; st.holdGuard = false; st.holdMove = 0;
      Object.assign(st.prevOut, NEUTRAL_INPUT);
      return NEUTRAL_INPUT;
    }
    const op = perceived(now, lv.reaction);
    const lag = now - op.t;
    const opX = op.x + op.vx * Math.min(lag, 0.1);
    const C = { match, me, op, opNow, mine: knowledge(me.def), theirs: knowledge(opNow.def), now, lag, opX, dist: Math.abs(opX - me.x) };

    if (st.holdGuard && now > st.holdGuardUntil) st.holdGuard = false;
    trackSelf(me);
    trackInitiative(C);
    trackOpponent(C);

    const s = me.state;
    if (s === 'attack') comboLogic(C);
    else if (s === 'launched') techLogic(C);
    else if (s === 'knockdown' || s === 'getup') wakeLogic(C);
    else if (s === 'blockstun') blockLogic(C);
    else if (s === 'hitstun' || s === 'guardbreak') st.holdGuard = false;
    else if (ACTIONABLE.has(s) || s === 'dash' || s === 'dodge') {
      const reacted = defend(C) || punish(C) || juggle(C) || oki(C);
      if (!reacted && now >= st.nextThink && now >= st.busyUntil && !st.presses.length && !(st.holdGuard && now < st.holdGuardUntil)) {
        neutral(C);
        st.nextThink = now + lv.think[0] + R() * (lv.think[1] - lv.think[0]);
      }
    }
    st.lastState = s;
    return emit(C);
  }

  function emit(C) {
    const { me, now } = C;
    Object.assign(out, NEUTRAL_INPUT);
    const toward = C.opX >= me.x ? 1 : -1;
    if (now < st.holdUntil && st.holdMove) out.move = st.holdMove * toward;
    if (st.holdGuard) { out.guard = true; out.move = 0; }
    for (let i = 0; i < st.presses.length; i++) {
      const p = st.presses[i];
      if (p.at > now) continue;
      if (st.prevOut[p.button]) break; // release first, press on the next step
      out[p.button] = true;
      out.move = p.dir === 'f' ? toward : p.dir === 'b' ? -toward : 0;
      out.down = p.dir === 'd';
      out.up = p.dir === 'u';
      out.guard = false;
      st.presses.splice(i, 1);
      break;
    }
    if (st.presses.length > 6) st.presses.splice(0, st.presses.length - 6);
    Object.assign(st.prevOut, out);
    return out;
  }

  /** Who is "plus": after blocking (or a blocked unsafe move of mine), the opponent; while it is stunned, me. */
  function trackInitiative(C) {
    const { me, op, now, mine } = C;
    if (st.lastState === 'attack' && me.state !== 'attack' && me.moveConnected && !me.moveHit) {
      const x = mine.moves[st.lastMoveId];
      if (x && x.fd.onBlock !== null) setInit(x.fd.onBlock < -0.03 ? 'them' : 'me', 0.4, now);
    }
    if (me.state === 'attack') st.lastMoveId = me.move;
    if (me.state === 'blockstun') setInit('them', 0.45, now);
    else if (me.state === 'hitstun') setInit('them', 0.3, now);
    else if (OP_DISADVANTAGE.has(op.state)) setInit('me', 0.35, now);
    else if (op.state === 'attack' && op.connected && me.state !== 'attack') setInit('them', 0.35, now);
    if (now > st.initUntil) st.init = 'none';
  }

  /**
   * Own moves: cancels taken in the current string (combo depth; chain routes such as light1 -> light2 are free: any
   * beginner mashes them out) and repeats of the same neutral move (variety).
   */
  function trackSelf(me) {
    if (me.state !== 'attack' || me.moveSerial === st.mySerial) return;
    st.mySerial = me.moveSerial;
    if (st.lastState === 'attack') {
      const prev = st.lastMoveId && me.def.moves[st.lastMoveId];
      if (!(prev && prev.cancels.some((c) => c.on && c.route === me.move))) st.chain++;
      return;
    }
    st.chain = 0;
    st.streak = me.move === st.lastNeutral ? st.streak + 1 : 1;
    st.lastNeutral = me.move;
  }

  /** Is the opponent (as perceived) inside a counter-stance window, or about to be? */
  function inStance(C) {
    const { op, theirs, lag } = C;
    if (op.state !== 'attack' || !op.move) return false;
    const x = theirs.moves[op.move];
    const ct = x && x.mv.counter;
    const est = op.moveTime + lag;
    return !!ct && est <= ct.t1 + 0.02;
  }

  /** Light opponent model: how often it attacks and how often it guards (shifts neutral weights). */
  function trackOpponent(C) {
    const { op } = C;
    if (op.state === 'attack' && op.serial !== st.opSerial) { st.opSerial = op.serial; st.opAggro = st.opAggro * 0.9 + 0.1; }
    if (op.state === 'guard' || op.state === 'blockstun') st.opGuard = st.opGuard * 0.995 + 0.005;
    else if (op.state === 'idle' || op.state === 'walk') { st.opGuard *= 0.997; st.opAggro *= 0.9985; }
  }

  // ------------------------------------------------------------------------------------------------- self-preservation
  function techLogic(C) {
    const { me, now } = C;
    st.holdGuard = false;
    if (me.hard || me.koFall || me.vy >= 0 || me.y > 0.7) return;
    if (once('tech' + me.recv.hits + ':' + me.recv.juggle, lv.tech) && !st.decided.has('techp' + me.recv.hits)) {
      remember('techp' + me.recv.hits, true);
      press('dodge', null, now);
    }
  }

  function wakeLogic(C) {
    const { me, match, mine, now, dist } = C;
    const key = 'wake' + Math.floor(now - me.stateTime);
    if (st.decided.has(key)) return;
    remember(key, true);
    // wake-up reversal: a counter stance or a move tagged 'reversal' (invulnerable start)
    const counter = mine.pressable.find((x) => x.role === 'reversal' && usable(match, me, x)) || mine.pressable.find((x) => x.role === 'counter' && usable(match, me, x));
    const left = me.state === 'knockdown' ? me.timer + match.rules.getupTime : me.timer;
    if (counter && dist < 3 && R() < lv.reversal) { pressMove(counter, now + Math.max(0, left - 0.15)); return; }
    if (R() < lv.wakeGuard) guardFor(left + 0.2 + R() * 0.3, now);
  }

  function blockLogic(C) {
    const { me, op, theirs, now, dist } = C;
    const k = 'bs' + op.serial;
    if (!st.decided.has(k)) {
      once(k, lv.holdGuard);
      const om = op.move && theirs.moves[op.move];
      if (om && om.fd.onBlock !== null && om.fd.onBlock < -0.12 && R() < lv.punish) {
        const pun = bestPunisher(C, -om.fd.onBlock - 0.02, dist);
        if (pun) pressMove(pun, now + Math.max(0, me.timer - 0.1));
      }
    }
    if (st.decided.get(k)) guardFor(0.15, now);
    else st.holdGuard = false;
  }

  // ------------------------------------------------------------------------------------------------- combos
  function comboLogic(C) {
    const { me, now, opNow } = C;
    st.holdGuard = false;
    st.holdMove = 0;
    const mv = me.moveData;
    if (!mv || !mv.cancels.length || st.comboSerial === me.moveSerial) return;
    // nothing connects on a hard-knockdown flight or a KO: do not waste a cancel (or FP) on it
    if (opNow.state === 'launched' && (opNow.hard || opNow.koFall)) return;
    if (me.moveHit && st.hitSerial !== me.moveSerial) { st.hitSerial = me.moveSerial; st.hitSeenAt = now; }
    if (st.chain >= lv.depth) return; // easy stops after a cancel or two; nightmare runs the full route
    let mode;
    if (me.moveHit) {
      if (now - st.hitSeenAt < lv.confirm * (0.7 + R() * 0.6)) return;
      mode = 'hit';
    } else if (me.moveConnected) mode = 'block';
    else if (!mv.hits.length && !mv.projectiles.length) mode = 'follow'; // mobility / teleport: built to lead into an attack
    else {
      if (me.moveTime < mv.lastActive) return;
      mode = 'whiff';
    }
    st.comboSerial = me.moveSerial;
    const p = mode === 'hit' ? lv.combo : mode === 'block' ? lv.blockString : mode === 'follow' ? lv.combo * 0.85 : lv.mash;
    if (R() >= p) return;
    let best = null;
    for (const o of comboOptions(C, mode)) if (!best || o.w > best.w) best = o;
    if (best) press(best.button, best.dir, Math.max(now, now + (best.from - me.moveTime) - 0.1));
  }

  function comboOptions(C, mode) {
    const { me, match, mine, opNow } = C;
    const mv = me.moveData;
    const res = [];
    const t = me.moveTime;
    const air = opNow.state === 'launched';
    const ultReady = me.ult >= me.ultMax - 1e-6;
    const add = (id, button, dir, from, route = false) => {
      const x = mine.moves[id];
      if (!x || match.canUse(me.index, id) !== null) return;
      const f = x.fd;
      let w = f.damage * 0.01 + 0.5 + (route ? 0.5 : 0); // designed chains are worth finishing
      if (mode === 'hit') {
        if (x.role === 'finisher') w = ultReady && R() < lv.ult ? 6 + opNow.recv.scale * 4 : 0;
        else if (x.role === 'launcher') w = air ? 0.2 : 2.2;
        else if (x.role === 'combo') w += air ? 1.4 : 1.2;
        else if (f.projectile) w = air ? 0.1 : 0.4;
        else if (x.role === 'counter' || x.role === 'mobility') w = 0;
        if (f.fpCost && R() > lv.skill) w *= 0.25;
        if (opNow.recv.juggle >= match.rules.juggle.limit - 1) w *= 0.2;
      } else if (mode === 'block') {
        if (x.role === 'finisher' || x.role === 'launcher') w = 0;
        else if (f.onBlock !== null && f.onBlock < -0.15) w *= 0.25;
        if (f.projectile) w += 0.6;
      } else if (mode === 'follow') {
        // after a dash-through / teleport: a fast strike that reaches, never another movement
        const d = Math.abs(opNow.x - me.x);
        w = !x.mv.hits.length || f.projectile ? 0 : d <= x.reach + 0.2 ? 2 + (0.4 - Math.min(0.4, f.startup || 0.4)) * 5 : 0.1;
      } else w = x.role === 'combo' ? 0.8 : 0.1;
      if (w > 0) res.push({ id, button, dir, from, w: w * (1 + (R() - 0.5) * lv.noise) });
    };
    for (const c of mv.cancels) {
      if (c.t1 < t || (c.onHit && !me.moveHit) || (c.onContact && !me.moveConnected)) continue;
      if (c.on) { add(c.route, c.on, c.dir, c.t0, true); continue; }
      for (const x of mine.pressable) {
        if (c.ids.has(x.id) || c.groups.has('any') || c.groups.has(x.mv.group)) add(x.id, keyOf(x).button, keyOf(x).dir, c.t0);
      }
    }
    return res;
  }

  // ------------------------------------------------------------------------------------------------- defence
  /** The attack (or projectile) the AI perceives coming at it, with its estimated time to impact. */
  function threat(C) {
    const { op, theirs, me, dist, lag } = C;
    if (op.state === 'attack' && op.move) {
      const x = theirs.moves[op.move];
      if (x) {
        const est = op.moveTime + lag;
        const fd = x.fd;
        if (x.mv.hits.length) {
          const tta = fd.startup - est;
          const left = fd.activeEnd - est;
          const reach = x.reach - forwardAt(x.mv, Math.min(est, fd.startup)) + 0.35;
          if (left > -0.03 && tta < 0.55 && dist <= reach) {
            return { key: 's' + op.serial, tta: Math.max(0, tta), until: Math.max(0.05, left) + 0.12, unblockable: fd.unblockable };
          }
        } else if (fd.projectile) {
          const rel = x.mv.projectiles[0];
          const tta = rel.t + rel.delay - est + Math.max(0, dist - 1.2) / Math.max(1, Math.abs(rel.vx));
          if (tta > -0.05 && tta < 0.6 && dist < x.reach + 0.5) return { key: 'p' + op.serial, tta: Math.max(0, tta), until: 0.35, unblockable: rel.hit.unblockable, projectile: true };
        }
      }
    }
    for (const p of op.proj) {
      const dx = me.x - p.x;
      if (p.vx !== 0) {
        if (Math.sign(dx) !== Math.sign(p.vx)) continue;
        const tti = (Math.abs(dx) - 0.5 - p.half) / Math.abs(p.vx) - lag;
        if (tti < 0.5 && tti > -0.15) return { key: 'q' + p.id, tta: Math.max(0, tti), until: 0.3, unblockable: p.unblockable, projectile: true };
      } else if (Math.abs(dx) < 1.3 && p.wait < 0.6) {
        return { key: 'q' + p.id, tta: Math.max(0, p.wait - lag), until: 0.4, unblockable: p.unblockable, projectile: true, column: true };
      }
    }
    return null;
  }

  function defend(C) {
    const { me, match, mine, now } = C;
    const th = threat(C);
    if (!th) return false;
    let choice = st.decided.get(th.key);
    if (choice === undefined) {
      const counter = mine.pressable.find((x) => x.role === 'counter' && usable(match, me, x) && x.mv.counter.t0 < th.tta + 0.02);
      const opts = [
        { k: 'guard', w: th.unblockable ? 0 : lv.guard * (me.guard / me.guardMax > 0.25 ? 1 : 0.4) },
        { k: 'dodge', w: me.dodgeCooldown <= 0 ? lv.dodge * (th.unblockable ? 2.5 : 1) : 0 },
      ];
      if (counter && !th.projectile) opts.push({ k: 'counter', w: lv.counter * lv.skill, x: counter });
      if (th.column || th.tta > 0.2) opts.push({ k: 'back', w: lv.backoff * (th.column ? 2 : 1) });
      // the chance to react at all is the summed weight (capped); otherwise it simply did not see it coming
      let sum = 0;
      for (const o of opts) sum += o.w;
      const o = R() < Math.min(0.97, sum) ? pick(opts) : null;
      choice = o ? o.k : 'none';
      remember(th.key, choice);
      if (o && o.x) remember(th.key + 'c', o.x);
    }
    switch (choice) {
      case 'guard': {
        // the stronger levels hold off and press guard just before the impact: a perfect guard
        // (already guarding: let go and press again at the impact - the press is what counts)
        if (st.decided.get(th.key + 'p') === undefined) remember(th.key + 'p', R() < lv.perfect && th.tta > 0.12);
        if (st.decided.get(th.key + 'p') && th.tta > 0.07) { st.holdGuard = false; st.holdMove = 0; return true; }
        guardFor(th.tta + th.until, now);
        return true;
      }
      case 'dodge': {
        if (st.decided.get(th.key + 'd')) return true;
        // aim the invulnerable window at the impact (the stronger levels time it for a perfect dodge)
        const inv = me.def.movement.dodge.invuln;
        const lead = R() < lv.perfect ? inv[0] + 0.03 : 0.1 + R() * 0.14;
        if (th.tta <= lead + 0.02) { press('dodge', null, now); remember(th.key + 'd', true); }
        else st.holdMove = 0;
        return true;
      }
      case 'counter': {
        if (st.decided.get(th.key + 'x')) return true;
        const x = st.decided.get(th.key + 'c');
        if (x && usable(match, me, x)) pressMove(x, now);
        remember(th.key + 'x', true);
        return true;
      }
      case 'back':
        hold(-1, 0.3 + th.tta, now);
        st.holdGuard = false;
        return true;
      default:
        return false;
    }
  }

  // ------------------------------------------------------------------------------------------------- punish / juggle / oki
  function bestPunisher(C, window, dist) {
    const { me, match, mine } = C;
    let best = null, bw = 0;
    for (const x of mine.pressable) {
      if (!x.mv.hits.length || x.fd.startup === null || x.fd.startup > window) continue;
      if (dist > x.reach + 0.1 || dist < x.range[0] - 0.4) continue;
      if (!usable(match, me, x)) continue;
      let w = x.fd.damage + (x.role === 'launcher' ? 90 : 0) + (x.role === 'punish' ? 80 : 0) + (x.fd.cancellable ? 40 : 0);
      if (x.role === 'finisher') w = R() < lv.ult ? 600 : 0;
      if (x.fd.fpCost && R() > lv.skill) w *= 0.3;
      if (w > bw) { bw = w; best = x; }
    }
    return best;
  }

  function punish(C) {
    const { op, theirs, now, dist, lag, opNow } = C;
    let window = 0, key = null, p = 0;
    if (op.state === 'attack' && op.move) {
      const x = theirs.moves[op.move];
      const est = op.moveTime + lag;
      if (x && x.mv.counter && !x.mv.hits.length) {
        // a counter stance that caught nothing: its recovery after the window is free (the 'read' skill)
        if (est > x.mv.counter.t1 + 0.02) { window = x.mv.duration - est; key = 'pun' + op.serial; p = lv.read; }
      } else if (x && x.fd.activeEnd !== null && est > x.fd.activeEnd + 0.02 && !x.mv.counter) {
        window = x.mv.duration - est;
        key = 'pun' + op.serial;
        p = op.connected ? lv.punish : lv.whiffPunish;
      }
    } else if (op.state === 'guardbreak' || op.state === 'recovery') {
      window = op.timer - lag;
      key = op.state + op.serial + ':' + Math.floor(op.t - op.stateTime);
      p = lv.punish;
    } else if (op.state === 'backstep' || op.state === 'dash') {
      window = opNow.def.movement[op.state].duration - op.stateTime - lag;
      key = 'mv' + Math.floor((op.t - op.stateTime) * 10);
      p = lv.whiffPunish * 0.5;
    }
    if (!key || window < 0.08 || !once(key, p) || st.decided.has(key + 'done')) return false;
    const pun = bestPunisher(C, window - 0.03, dist);
    if (pun) { pressMove(pun, now); remember(key + 'done', true); return true; }
    if (window > 0.55 && dist > 2) { hold(1, 0.25, now); return true; }
    return false;
  }

  function juggle(C) {
    const { op, opNow, match, me, mine, now, dist } = C;
    if (op.state !== 'launched' || op.hard || opNow.state !== 'launched') return false;
    if (opNow.recv.attacker !== me.index || opNow.recv.juggle >= match.rules.juggle.limit - 0.5) return false;
    const key = 'jg' + opNow.recv.hits;
    if (st.decided.has(key + 'done') || !once(key, lv.juggle)) return false;
    const g = match.rules.gravity * (1 + match.rules.juggle.gravityStep * opNow.recv.juggle);
    const land = (opNow.vy + Math.sqrt(Math.max(0, opNow.vy * opNow.vy + 2 * g * opNow.y))) / g;
    let best = null, bw = 0;
    for (const x of mine.pressable) {
      if (!x.mv.hits.length || x.fd.startup === null || x.fd.startup > land - 0.03) continue;
      if (!x.mv.hits.some((h) => h.air) || dist > x.reach + 0.2 || !usable(match, me, x)) continue;
      let w = x.fd.damage + (x.role === 'combo' ? 60 : 0) + (x.role === 'poke' ? 30 : 0) + (x.role === 'juggle' || x.role === 'antiair' ? 70 : 0);
      if (x.role === 'finisher') w = me.ult >= me.ultMax && R() < lv.ult ? 400 : 0;
      if (x.role === 'launcher') w *= 0.6;
      if (w > bw) { bw = w; best = x; }
    }
    if (!best) {
      if (dist > 1.6) { hold(1, 0.1, now); return true; }
      return false;
    }
    pressMove(best, now);
    remember(key + 'done', true);
    return true;
  }

  function oki(C) {
    const { op, now, dist, mine, match, me } = C;
    if (op.state !== 'knockdown' && op.state !== 'getup') return false;
    const left = (op.state === 'knockdown' ? op.timer + match.rules.getupTime : op.timer) - C.lag;
    if (dist > mine.pokeReach) { hold(1, 0.08, now); return true; }
    const down = 'oki' + Math.floor(op.t - op.stateTime);
    if (once(down, lv.meaty)) {
      const x = mine.strikes.find((s) => s.role === 'poke' && usable(match, me, s)) || mine.strikes[0];
      if (x && left <= x.fd.startup + 0.02 && !st.decided.has(down + 'done')) {
        remember(down + 'done', true);
        pressMove(x, now);
      }
      return true;
    }
    if (left < 0.3 && !st.decided.has(down + 'g')) { remember(down + 'g', true); if (R() < lv.patience) guardFor(0.35, now); }
    return true;
  }

  // ------------------------------------------------------------------------------------------------- neutral
  function neutral(C) {
    const { me, op, match, mine, theirs, now, dist } = C;
    const A = Math.min(1, Math.max(0, lv.aggression * 0.6 + me.def.ai.aggression * 0.4));
    const hpLead = me.hp / me.hpMax - op.hp;
    const protect = hpLead > 0.12 && match.clock < 25;
    const cornered = backToWall(match, me, 1.2);
    const opCornered = backToWall(match, C.opNow, 1.5);
    const tReach = theirs.threatReach;
    const myPoke = mine.pokeReach;
    const zone = dist > tReach + 1.0 ? 'far' : dist > Math.min(tReach, myPoke) - 0.05 ? 'mid' : 'close';
    const init = st.init;
    const opts = [];
    const add = (k, w, x) => { if (w > 0) opts.push({ k, w, x }); };
    // an opponent that cannot be hit right now (down, airborne out of reach of the juggle logic, invulnerable flight)
    const opDown = op.state === 'knockdown' || op.state === 'getup' || op.state === 'launched' || op.state === 'ko';
    // a perceived counter stance: the levels that read it hold their attacks and wait for its recovery
    const stance = inStance(C) && once('stance' + op.serial, lv.read);
    // footsies: hold the preferred range (def.ai.preferredRange, else just inside the own poke reach)
    const pref = me.def.ai.preferredRange !== undefined ? me.def.ai.preferredRange : myPoke * 0.9;

    if (zone === 'far') {
      add('approach', 1.0 + A + (protect ? -0.8 : 0));
      add('dash', 0.25 + A * 0.5);
      add('wait', 0.3 + (1 - A) * 0.4 + (protect ? 1.2 : 0));
      add('retreat', protect ? 0.6 : 0.05);
    } else if (zone === 'mid') {
      add('step', 0.7 + A * 0.6 + (dist > pref + 0.5 ? lv.spacing * 0.6 : 0));
      add('retreat', cornered ? 0 : 0.25 + lv.spacing * 0.5 + (protect ? 0.6 : 0) + (dist < pref - 0.5 ? lv.spacing * 0.8 : 0));
      add('wait', 0.3 + lv.patience * 0.5);
      add('guard', 0.15 + st.opAggro * 0.5 * lv.patience);
      add('dash', 0.1 + A * 0.2);
    } else {
      const theirTurn = init === 'them', myTurn = init === 'me';
      add('guard', (theirTurn ? 1.2 + lv.holdGuard : 0.45 + (1 - A) * 0.5 + st.opAggro * 0.6 + lv.patience * 0.3) * (me.guard / me.guardMax < 0.25 ? 0.4 : 1));
      add('backstep', cornered ? 0 : lv.spacing * (theirTurn ? 0.5 : 0.25));
      add('retreat', cornered ? 0 : lv.spacing * (dist < pref - 0.5 ? 0.6 : 0.35));
      add('escape', cornered ? 0.3 + lv.spacing * 0.6 : 0);
      add('dodge', me.dodgeCooldown <= 0 ? lv.dodge * (theirTurn ? 0.6 : 0.2) : 0);
      add('wait', 0.15);
      opts.attackBias = myTurn ? 1.8 : theirTurn ? 0.35 - lv.holdGuard * 0.25 : 1;
    }

    if (stance) { add('wait', 1.5); add('retreat', cornered ? 0 : 0.6); }
    // attacks from data; tempo (level) and patience lower how often a think tick turns into an attack
    const bias = (opts.attackBias !== undefined ? opts.attackBias : 1) * (0.25 + 0.6 * A) * (1.25 - lv.patience * 0.6) *
      lv.tempo * (stance ? 0.04 : 1) * (opDown ? 0 : 1);
    for (const x of mine.pressable) {
      if (x.role === 'finisher' || x.role === 'counter' || !usable(match, me, x)) continue;
      if (dist < x.range[0] - 0.05 || dist > x.range[1] + 0.05) continue;
      let w = x.weight * bias;
      switch (x.role) {
        case 'poke': w *= (zone === 'mid' ? 0.9 : 0.7) + A * 0.6; break;
        case 'pressure': w *= 0.35 + A * 0.4 + (op.guard < 0.4 ? 0.8 : 0) + st.opGuard * 0.8 + (opCornered ? 0.3 : 0); break;
        case 'approach': w *= 0.35 + A * 0.5; break;
        case 'launcher': w *= 0.2 + A * 0.2 + (st.opGuard < 0.2 ? 0.2 : 0); break;
        case 'zoning': w *= (0.3 + me.def.ai.zoning * 1.2) * (zone === 'far' ? 1.4 : 0.4); break;
        case 'combo': w *= 0.2; break;
        case 'mobility': w *= cornered ? 0.8 : 0.15 + A * 0.2; break;
        case 'starter': w *= 0.6 + A * 0.5; break;
        case 'punish': w *= 0.2; break;                    // kept for punish windows
        case 'juggle': case 'antiair': w *= 0.1; break;    // kept for airborne opponents
        case 'reversal': w *= 0.15; break;                 // kept for wake-up
        default: w *= 0.4;
      }
      if (x.fd.fpCost) w *= lv.skill * (me.fp > x.fd.fpCost + 20 ? 1 : 0.4);
      if (op.invuln) w *= 0.15;
      // variety: the same neutral move again and again gets less likely (easy spams, nightmare mixes it up)
      if (x.id === st.lastNeutral) w *= Math.pow(1 - 0.55 * lv.variety, st.streak);
      add('attack', w, x);
    }
    const counter = mine.pressable.find((x) => x.role === 'counter' && usable(match, me, x));
    // a counter stance only where the opponent's fast attacks can actually reach
    if (counter && dist <= tReach && !opDown && !stance) add('attack', st.opAggro * lv.counter * 1.5 * (st.init === 'them' ? 2 : 1), counter);
    const ult = mine.pressable.find((x) => x.role === 'finisher' && usable(match, me, x));
    if (ult && dist <= ult.range[1] && !opDown && !stance) add('attack', lv.ult * (difficulty === 'easy' ? 0.35 : 0.05), ult);

    const o = R() < lv.mistake ? opts[Math.floor(R() * opts.length)] : pick(opts);
    if (!o) return;
    switch (o.k) {
      case 'approach': hold(1, 0.2 + R() * 0.4, now); break;
      case 'step': hold(1, 0.08 + R() * 0.16, now); break;
      case 'dash': press('dodge', 'f', now); st.busyUntil = now + 0.3; break;
      case 'retreat': hold(-1, 0.12 + R() * 0.25, now); break;
      case 'backstep': press('dodge', 'b', now); st.busyUntil = now + 0.35; break;
      case 'escape': press('dodge', 'f', now); st.busyUntil = now + 0.4; break;
      case 'dodge': press('dodge', null, now); st.busyUntil = now + 0.4; break;
      case 'wait': hold(0, 0.08 + R() * 0.25 * (0.5 + lv.patience), now); break;
      case 'guard': guardFor(0.2 + R() * (0.25 + 0.4 * lv.patience), now); st.busyUntil = st.holdGuardUntil; break;
      default: pressMove(o.x, now); break;
    }
  }

  return {
    kind: 'ai',
    difficulty,
    level: lv,
    /** Called by the match: takes the match-forked rng unless one was given. */
    attach({ rng: r }) { if (!ownRng) R = r; reset(); },
    reset,
    update,
  };
}
