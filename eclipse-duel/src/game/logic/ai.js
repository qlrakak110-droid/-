// AI controller: generic over any fighter definition. It reads its own fighter directly and the opponent through a
// delayed perception buffer (the reaction delay), and plays through the same input path as a human (held buttons,
// presses derived by the engine). Decisions use per-move `ai` hints when present and frame data derived from the
// move data otherwise (startup, reach, recovery, advantage).
//
// Behaviour layers, evaluated every step:
//   1. self-preservation: tech rolls, wake-up guard / reversal, holding guard through blockstrings
//   2. combo: hit-confirm (or pressure on block) and pick the best cancel / route the move data allows
//   3. defence: guard, dodge, counter-stance or back off against attacks and projectiles it has *perceived*
//   4. punish: blocked or whiffed moves with enough recovery, guard breaks, juggles
//   5. neutral (on think ticks): approach, dash, poke, zone, retreat, wait, bait, skills, ultimate
// Difficulty scales reaction time, every probability above, spacing discipline and mistakes.

import { deriveFrameData } from './framedata.js';
import { NEUTRAL_INPUT } from './constants.js';
import { forwardAt } from './moves.js';
import { toRng } from './rng.js';

/** Difficulty presets. Every field can be overridden through createAIController({ overrides }). */
export const AI_LEVELS = {
  easy: {
    reaction: 0.42, think: [0.16, 0.32], guard: 0.28, dodge: 0.06, counter: 0.05, backoff: 0.15, holdGuard: 0.45,
    punish: 0.18, whiffPunish: 0.12, confirm: 0.32, combo: 0.35, blockString: 0.35, mash: 0.35, juggle: 0.25,
    tech: 0.1, wakeGuard: 0.3, reversal: 0.03, spacing: 0.15, skill: 0.3, ult: 0.35, mistake: 0.22, aggression: 0.5,
    antiProjectile: 0.3, meaty: 0.1, perfect: 0, noise: 0.5,
  },
  normal: {
    reaction: 0.28, think: [0.1, 0.2], guard: 0.48, dodge: 0.13, counter: 0.1, backoff: 0.25, holdGuard: 0.65,
    punish: 0.45, whiffPunish: 0.3, confirm: 0.2, combo: 0.65, blockString: 0.45, mash: 0.18, juggle: 0.55,
    tech: 0.35, wakeGuard: 0.55, reversal: 0.08, spacing: 0.45, skill: 0.55, ult: 0.65, mistake: 0.09, aggression: 0.55,
    antiProjectile: 0.5, meaty: 0.35, perfect: 0.1, noise: 0.3,
  },
  hard: {
    reaction: 0.2, think: [0.07, 0.13], guard: 0.62, dodge: 0.22, counter: 0.14, backoff: 0.32, holdGuard: 0.8,
    punish: 0.72, whiffPunish: 0.55, confirm: 0.12, combo: 0.85, blockString: 0.5, mash: 0.08, juggle: 0.8,
    tech: 0.6, wakeGuard: 0.7, reversal: 0.12, spacing: 0.7, skill: 0.7, ult: 0.85, mistake: 0.04, aggression: 0.6,
    antiProjectile: 0.7, meaty: 0.6, perfect: 0.3, noise: 0.18,
  },
  nightmare: {
    reaction: 0.14, think: [0.04, 0.08], guard: 0.72, dodge: 0.32, counter: 0.18, backoff: 0.38, holdGuard: 0.9,
    punish: 0.92, whiffPunish: 0.8, confirm: 0.07, combo: 0.97, blockString: 0.55, mash: 0.02, juggle: 0.95,
    tech: 0.85, wakeGuard: 0.8, reversal: 0.15, spacing: 0.92, skill: 0.85, ult: 0.95, mistake: 0.012, aggression: 0.65,
    antiProjectile: 0.85, meaty: 0.8, perfect: 0.6, noise: 0.1,
  },
};

const ATTACK_KEYS = ['light', 'heavy', 'skill1', 'skill2', 'skill3', 'ult'];
const ACTIONABLE = new Set(['idle', 'walk', 'guard']);
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

/** Knowledge of a compiled fighter def: per move frame data, role, range, weight and the keys that press it. */
export function knowledge(def) {
  let k = KNOW.get(def);
  if (k) return k;
  const moves = {};
  for (const id of Object.keys(def.moves)) {
    const mv = def.moves[id];
    const fd = deriveFrameData(mv);
    const ai = mv.ai || {};
    const role = ai.role || inferRole(mv, fd);
    const reach = fd.projectile ? fd.reach : fd.strikeReach;
    const range = ai.range || (fd.projectile ? [2.5, Math.min(9, reach)] : [0, reach]);
    moves[id] = { id, mv, fd, role, range, reach, weight: ai.weight !== undefined ? ai.weight : 1, comboOnly: !!ai.comboOnly, keys: [] };
  }
  for (const [key, id] of Object.entries(def.commands)) {
    const mm = /^(?:([dufb])\+)?(\w+)$/.exec(key);
    if (mm && moves[id]) moves[id].keys.push({ button: mm[2], dir: mm[1] || null });
  }
  const list = Object.values(moves);
  const pressable = list.filter((x) => x.keys.length && !x.comboOnly);
  const strikes = pressable.filter((x) => x.mv.hits.length && x.fd.startup !== null && !x.mv.cinematic);
  strikes.sort((a, b) => a.fd.startup - b.fd.startup);
  const pokes = pressable.filter((x) => x.role === 'poke');
  const pokeReach = pokes.length ? Math.max(...pokes.map((x) => x.range[1])) : (strikes[0] ? strikes[0].reach : 1.6);
  const threatReach = Math.max(pokeReach, ...pressable.filter((x) => !x.fd.projectile && x.mv.hits.length && (x.fd.startup || 1) < 0.3).map((x) => x.reach));
  k = { def, moves, list, pressable, strikes, pokeReach, threatReach };
  KNOW.set(def, k);
  return k;
}

// ---------------------------------------------------------------------------------------------------------------

/**
 * Create an AI controller.
 * @param {object} [opts]
 * @param {'easy'|'normal'|'hard'|'nightmare'} [opts.difficulty='normal']
 * @param {object} [opts.overrides] per-field overrides of the difficulty preset
 * @param {number|Function} [opts.rng] seed / rng; by default the match hands one out on attach
 */
export function createAIController({ difficulty = 'normal', overrides = {}, rng } = {}) {
  if (!AI_LEVELS[difficulty]) throw new Error(`createAIController: unknown difficulty '${difficulty}' (use ${Object.keys(AI_LEVELS).join(', ')})`);
  const lv = { ...AI_LEVELS[difficulty], ...overrides };
  let R = rng !== undefined ? toRng(rng) : null;
  const ownRng = rng !== undefined;

  // perception ring
  const hist = [];
  for (let i = 0; i < HISTORY; i++) hist.push({ t: -1, x: 0, y: 0, vx: 0, vy: 0, facing: 1, state: 'idle', stateTime: 0, move: null, moveTime: 0, serial: 0, connected: false, hit: false, hard: false, juggle: 0, invuln: false, timer: 0, guard: 100, hp: 1, proj: [] });
  let head = -1, count = 0;

  // working memory
  const st = {
    nextThink: 0, holdUntil: 0, holdMove: 0 /* +1 toward, -1 away */, holdGuard: false, holdGuardUntil: 0, holdDown: false,
    presses: [], decided: new Map(), lastComboSerial: -1, hitSeenAt: -1, hitSerial: -1, airSerial: -1,
    wakeSerial: -1, prevOut: { ...NEUTRAL_INPUT }, opAggro: 0.5, opGuardRate: 0.3, lastOpSerial: -1,
    stats: null,
  };
  const out = { ...NEUTRAL_INPUT };

  function reset() {
    head = -1; count = 0;
    st.nextThink = 0; st.holdUntil = 0; st.holdMove = 0; st.holdGuard = false; st.holdGuardUntil = 0; st.holdDown = false;
    st.presses.length = 0; st.decided.clear(); st.lastComboSerial = -1; st.hitSeenAt = -1; st.hitSerial = -1;
    st.airSerial = -1; st.wakeSerial = -1; Object.assign(st.prevOut, NEUTRAL_INPUT);
  }

  // ------------------------------------------------------------------------------------------------- perception
  function observe(match, op) {
    head = (head + 1) % HISTORY;
    count = Math.min(HISTORY, count + 1);
    const o = hist[head];
    o.t = match.time; o.x = op.x; o.y = op.y; o.vx = op.vx; o.vy = op.vy; o.facing = op.facing;
    o.state = op.state; o.stateTime = op.stateTime; o.move = op.move; o.moveTime = op.moveTime; o.serial = op.moveSerial;
    o.connected = op.moveConnected; o.hit = op.moveHit; o.hard = op.hard || op.koFall; o.juggle = op.recv.juggle;
    o.invuln = op.invulnerable; o.timer = op.timer; o.guard = op.guard / op.guardMax; o.hp = op.hp / op.hpMax;
    o.proj.length = 0;
    for (const p of match.projectiles) if (p.owner === op.index && p.alive) o.proj.push({ id: p.id, x: p.x, y: p.y, vx: p.vx, active: p.active, wait: p.delay - p.age, f0: p.spec.f0, f1: p.spec.f1, facing: p.facing, unblockable: p.spec.hit.unblockable });
  }
  /** Most recent observation at least `delay` seconds old (or the oldest one). */
  function perceived(now, delay) {
    let best = null;
    for (let i = 0; i < count; i++) {
      const o = hist[(head - i + HISTORY) % HISTORY];
      best = o;
      if (o.t <= now - delay) break;
    }
    return best;
  }

  // ------------------------------------------------------------------------------------------------- output helpers
  function press(button, dir, at) { st.presses.push({ button, dir, at }); }
  function hold(moveRel, dur, now) { st.holdMove = moveRel; st.holdUntil = now + dur; }
  function guardFor(dur, now) { st.holdGuard = true; st.holdGuardUntil = Math.max(st.holdGuardUntil, now + dur); }
  function once(key, p) {
    if (st.decided.has(key)) return st.decided.get(key);
    const v = R() < p;
    st.decided.set(key, v);
    if (st.decided.size > 256) st.decided.delete(st.decided.keys().next().value);
    return v;
  }
  function pick(options) {
    let tot = 0;
    for (const o of options) tot += Math.max(0, o.w);
    if (tot <= 0) return null;
    let r = R() * tot;
    for (const o of options) { r -= Math.max(0, o.w); if (r <= 0) return o; }
    return options[options.length - 1];
  }
  const usable = (match, me, x) => match.canUse(me.index, x.id) === null;
  const keyOf = (x) => x.keys[0];

  // ------------------------------------------------------------------------------------------------- update
  function update(view) {
    const match = view.match, me = view.self, opNow = view.opponent;
    if (!R) R = toRng(1);
    const now = match.time;
    observe(match, opNow);
    if (view.phase !== 'fight') {
      st.presses.length = 0; st.holdGuard = false; st.holdMove = 0;
      Object.assign(st.prevOut, NEUTRAL_INPUT);
      return NEUTRAL_INPUT;
    }
    const op = perceived(now, lv.reaction);
    const mine = knowledge(me.def), theirs = knowledge(opNow.def);
    const lag = now - op.t;
    const opX = op.x + op.vx * lag;
    const dist = Math.abs(opX - me.x);
    const C = { match, me, op, opNow, mine, theirs, now, dist, opX, lag };

    if (st.holdGuard && now > st.holdGuardUntil) st.holdGuard = false;
    trackOpponent(C);

    const s = me.state;
    if (s === 'attack') comboLogic(C);
    else if (s === 'launched') techLogic(C);
    else if (s === 'knockdown' || s === 'getup') wakeLogic(C);
    else if (s === 'blockstun') blockLogic(C);
    else if (s === 'hitstun' || s === 'guardbreak') st.holdGuard = false;
    else if (ACTIONABLE.has(s) || s === 'dash' || s === 'dodge') {
      const reacted = defend(C) || punish(C) || juggle(C) || oki(C);
      if (!reacted && now >= st.nextThink && !st.presses.length) {
        neutral(C);
        st.nextThink = now + lv.think[0] + R() * (lv.think[1] - lv.think[0]);
      }
    }
    return emit(C);
  }

  function emit(C) {
    const { me, now } = C;
    Object.assign(out, NEUTRAL_INPUT);
    const toward = C.opX >= me.x ? 1 : -1;
    if (now < st.holdUntil && st.holdMove) out.move = st.holdMove * toward;
    out.down = st.holdDown;
    if (st.holdGuard) { out.guard = true; out.move = 0; }
    for (let i = 0; i < st.presses.length; i++) {
      const p = st.presses[i];
      if (p.at > now) continue;
      if (st.prevOut[p.button]) break; // release first, press next step
      out[p.button] = true;
      out.move = p.dir === 'f' ? toward : p.dir === 'b' ? -toward : 0;
      out.down = p.dir === 'd';
      out.up = p.dir === 'u';
      if (p.button !== 'guard') out.guard = false;
      st.presses.splice(i, 1);
      break;
    }
    if (st.presses.length > 6) st.presses.splice(0, st.presses.length - 6);
    Object.assign(st.prevOut, out);
    return out;
  }

  /** Light opponent modelling: how often it attacks and guards (adapts weights). */
  function trackOpponent(C) {
    const { op } = C;
    if (op.state === 'attack' && op.serial !== st.lastOpSerial) {
      st.lastOpSerial = op.serial;
      st.opAggro = st.opAggro * 0.92 + 0.08;
    }
    if (op.state === 'guard' || op.state === 'blockstun') st.opGuardRate = st.opGuardRate * 0.995 + 0.005;
    else if (op.state === 'idle' || op.state === 'walk') { st.opGuardRate *= 0.997; st.opAggro *= 0.999; }
  }

  // ------------------------------------------------------------------------------------------------- self-preservation
  function techLogic(C) {
    const { me, now } = C;
    st.holdGuard = false;
    if (me.hard || me.koFall) return;
    const key = 'tech' + me.stateTime.toFixed(0) + ':' + me.recv.hits;
    if (me.vy < 0 && me.y < 0.7 && st.airSerial !== me.recv.hits) {
      st.airSerial = me.recv.hits;
      if (once(key, lv.tech)) press('dodge', null, now);
    }
  }

  function wakeLogic(C) {
    const { me, match, mine, now, dist } = C;
    const key = 'wake' + me.recv.hits + ':' + Math.round(now);
    if (st.wakeSerial === key) return;
    st.wakeSerial = key;
    const counter = mine.pressable.find((x) => x.role === 'counter' && usable(match, me, x));
    if (counter && dist < 3 && once(key + 'r', lv.reversal)) { press(keyOf(counter).button, keyOf(counter).dir, now + Math.max(0, me.timer - 0.15)); return; }
    if (once(key + 'g', lv.wakeGuard)) guardFor(me.timer + 0.25 + R() * 0.3, now);
  }

  function blockLogic(C) {
    const { me, op, theirs, match, mine, now, dist } = C;
    const k = 'bs' + op.serial;
    if (!st.decided.has(k)) {
      once(k, lv.holdGuard);
      // punish an unsafe blocked move: buffer the fastest move that reaches
      const om = op.move && theirs.moves[op.move];
      if (om && om.fd.onBlock !== null && om.fd.onBlock < -0.12 && once(k + 'p', lv.punish)) {
        const pun = bestPunisher(C, -om.fd.onBlock - 0.02, dist);
        if (pun) press(keyOf(pun).button, keyOf(pun).dir, now + Math.max(0, me.timer - 0.1));
      }
    }
    if (st.decided.get(k)) guardFor(0.12, now);
    else st.holdGuard = false;
    void mine; void match;
  }

  // ------------------------------------------------------------------------------------------------- combos
  function comboLogic(C) {
    const { me, match, mine, opNow, now } = C;
    st.holdGuard = false;
    st.holdMove = 0;
    const mv = me.moveData;
    if (!mv || !mv.cancels.length) return;
    if (st.lastComboSerial === me.moveSerial) return;
    if (me.moveHit && st.hitSerial !== me.moveSerial) { st.hitSerial = me.moveSerial; st.hitSeenAt = now; }
    let mode = null;
    if (me.moveHit) {
      if (now - st.hitSeenAt < lv.confirm * (0.7 + R() * 0.6)) return;
      mode = 'hit';
    } else if (me.moveConnected) mode = 'block';
    else {
      const last = mv.hits.length ? Math.max(...mv.hits.map((h) => h.t1)) : 0;
      if (me.moveTime < last) return;
      mode = 'whiff';
    }
    st.lastComboSerial = me.moveSerial;
    const p = mode === 'hit' ? lv.combo : mode === 'block' ? lv.blockString : lv.mash;
    if (R() >= p) return;
    const opts = comboOptions(C, mode);
    const best = pickBest(opts);
    if (!best) return;
    const at = Math.max(now, now + (best.from - me.moveTime) - 0.1);
    press(best.button, best.dir, at);
    void match; void mine; void opNow;
  }

  function comboOptions(C, mode) {
    const { me, match, mine, opNow } = C;
    const mv = me.moveData;
    const res = [];
    const t = me.moveTime;
    const air = opNow.state === 'launched';
    const ultReady = me.ult >= me.ultMax - 1e-6;
    for (const c of mv.cancels) {
      if (c.t1 < t) continue;
      if (c.onHit && !me.moveHit) continue;
      if (c.onContact && !me.moveConnected) continue;
      const add = (id, button, dir) => {
        const x = mine.moves[id];
        if (!x || match.canUse(me.index, id) !== null) return;
        let w = x.fd.damage * 0.01 + 0.5;
        const f = x.fd;
        if (mode === 'hit') {
          if (x.role === 'finisher') w = ultReady && R() < lv.ult ? 6 + opNow.recv.scale * 4 : 0;
          else if (x.role === 'launcher') w = air ? 0.2 : 2.2;
          else if (x.role === 'combo') w += air ? 1.4 : 1.2;
          else if (f.projectile) w = air ? 0.1 : 0.4;
          else if (x.role === 'counter' || x.role === 'mobility') w = 0;
          if (x.fd.fpCost && R() > lv.skill) w *= 0.25;
          if (opNow.recv.juggle >= match.rules.juggle.limit - 1) w *= 0.2;
        } else if (mode === 'block') {
          if (x.role === 'finisher' || x.role === 'launcher') w = 0;
          else if (f.onBlock !== null && f.onBlock < -0.15) w *= 0.25;
          if (f.projectile) w += 0.6;
        } else {
          w = x.role === 'combo' ? 0.8 : 0.1;
        }
        if (w > 0) res.push({ id, button, dir, from: c.t0, w: w * (1 + (R() - 0.5) * lv.noise) });
      };
      if (c.on) add(c.route, c.on, c.dir);
      else {
        for (const x of mine.pressable) {
          if (!(c.ids.has(x.id) || c.groups.has('any') || c.groups.has(x.mv.group))) continue;
          const k = keyOf(x);
          add(x.id, k.button, k.dir);
        }
      }
    }
    return res;
  }

  function pickBest(opts) {
    let best = null;
    for (const o of opts) if (!best || o.w > best.w) best = o;
    return best;
  }

  // ------------------------------------------------------------------------------------------------- defence
  function threat(C) {
    const { op, theirs, me, dist, lag, opNow } = C;
    // strikes
    if (op.state === 'attack' && op.move) {
      const x = theirs.moves[op.move];
      if (x && x.mv.hits.length) {
        const est = op.moveTime + lag;
        const fd = x.fd;
        const tta = fd.startup - est;
        const activeLeft = fd.activeEnd - est;
        const travel = forwardAt(x.mv, Math.max(est, fd.activeEnd)) - forwardAt(x.mv, est);
        const reachNow = x.reach - forwardAt(x.mv, est) + travel * 0 + 0.35;
        if (activeLeft > -0.03 && dist <= Math.max(reachNow, x.reach - forwardAt(x.mv, Math.min(est, fd.startup))) + 0.35 && tta < 0.55) {
          return { key: 's' + op.serial, tta: Math.max(0, tta), until: Math.max(0.05, activeLeft) + 0.1, unblockable: fd.unblockable, move: x, est };
        }
      }
      // projectile moves before release: treat as a projectile threat at release time
      if (x && x.fd.projectile && !x.mv.hits.length) {
        const est = op.moveTime + lag;
        const rel = x.mv.projectiles[0];
        const tta = rel.t + rel.delay - est + Math.max(0, dist - 1.2) / Math.max(1, Math.abs(rel.vx));
        if (tta > -0.05 && tta < 0.6 && dist < x.reach + 0.5) return { key: 'p' + op.serial, tta: Math.max(0, tta), until: 0.35, unblockable: rel.hit.unblockable, move: x, est, projectile: true };
      }
    }
    for (const p of op.proj) {
      const dx = me.x - p.x;
      if (p.vx !== 0) {
        if (Math.sign(dx) !== Math.sign(p.vx)) continue;
        const gapM = Math.abs(dx) - 0.5 - Math.max(Math.abs(p.f0), Math.abs(p.f1));
        const tti = gapM / Math.abs(p.vx) - lag;
        if (tti < 0.5 && tti > -0.15) return { key: 'q' + p.id, tta: Math.max(0, tti), until: 0.3, unblockable: p.unblockable, projectile: true };
      } else if (Math.abs(dx) < 1.3 && p.wait < 0.6) {
        return { key: 'q' + p.id, tta: Math.max(0, p.wait - lag), until: 0.4, unblockable: p.unblockable, projectile: true, column: true };
      }
    }
    void opNow;
    return null;
  }

  function defend(C) {
    const { me, match, mine, now } = C;
    const th = threat(C);
    if (!th) {
      if (st.holdGuard && now > st.holdGuardUntil - 0.02) st.holdGuard = false;
      return false;
    }
    let choice = st.decided.get(th.key);
    if (choice === undefined) {
      const counter = mine.pressable.find((x) => x.role === 'counter' && usable(match, me, x) && x.mv.counter.t0 < th.tta + 0.02);
      const opts = [];
      const guardW = th.unblockable ? 0 : lv.guard * (me.guard / me.guardMax > 0.25 ? 1 : 0.4);
      opts.push({ k: 'guard', w: guardW });
      opts.push({ k: 'dodge', w: me.dodgeCooldown <= 0 ? lv.dodge * (th.unblockable ? 2.5 : 1) : 0 });
      if (counter && !th.projectile) opts.push({ k: 'counter', w: lv.counter * lv.skill });
      if (th.column || th.tta > 0.2) opts.push({ k: 'back', w: lv.backoff * (th.column ? 2 : 1) * (C.dist < 3.5 ? 1 : 0.3) });
      let sum = 0;
      for (const o of opts) sum += o.w;
      // the chance to react at all is the sum of the option weights (capped); the rest is "did not see it"
      const reactP = Math.min(0.97, sum);
      if (R() < reactP) choice = pick(opts).k; else choice = 'none';
      st.decided.set(th.key, choice);
      if (choice === 'counter') st.decided.set(th.key + 'c', counter);
    }
    if (choice === 'none') return false;
    if (choice === 'guard') { guardFor(th.tta + th.until, now); st.holdMove = 0; return true; }
    if (choice === 'dodge') {
      if (st.decided.get(th.key + 'd')) return true;
      // aim the invulnerable window at the impact (nightmare times it for a perfect dodge)
      const inv = me.def.movement.dodge.invuln;
      const lead = lv.perfect > R() ? (inv[0] + 0.03) : 0.12 + R() * 0.12;
      if (th.tta <= lead + 0.02) { press('dodge', null, now); st.decided.set(th.key + 'd', true); }
      else if (!st.holdGuard) st.holdMove = 0;
      return true;
    }
    if (choice === 'counter') {
      if (st.decided.get(th.key + 'x')) return true;
      const x = st.decided.get(th.key + 'c');
      if (x && usable(match, me, x)) press(keyOf(x).button, keyOf(x).dir, now);
      st.decided.set(th.key + 'x', true);
      return true;
    }
    if (choice === 'back') { hold(-1, 0.3 + th.tta, now); st.holdGuard = false; return true; }
    return false;
  }

  // ------------------------------------------------------------------------------------------------- punish / juggle / oki
  function bestPunisher(C, window, dist) {
    const { me, match, mine } = C;
    let best = null, bw = 0;
    for (const x of mine.pressable) {
      if (!x.mv.hits.length || x.fd.startup === null || x.fd.startup > window) continue;
      if (dist > x.reach + 0.1 || dist < x.range[0] - 0.4) continue;
      if (!usable(match, me, x)) continue;
      let w = x.fd.damage + (x.role === 'launcher' ? 90 : 0) + (x.fd.cancellable ? 40 : 0);
      if (x.role === 'finisher') w = R() < lv.ult ? 600 : 0;
      if (x.fd.fpCost && R() > lv.skill) w *= 0.3;
      if (w > bw) { bw = w; best = x; }
    }
    return best;
  }

  function punish(C) {
    const { op, theirs, now, dist, lag, me } = C;
    let window = 0, key = null, p = 0;
    if (op.state === 'attack' && op.move) {
      const x = theirs.moves[op.move];
      const est = op.moveTime + lag;
      if (x && x.fd.activeEnd !== null && est > x.fd.activeEnd + 0.02 && !x.mv.counter) {
        window = x.mv.duration - est;
        key = 'pun' + op.serial;
        p = op.connected ? lv.punish : lv.whiffPunish;
      }
    } else if (op.state === 'guardbreak') { window = op.timer - lag; key = 'gb' + op.serial + ':' + Math.round(op.t * 2); p = lv.punish; }
    else if (op.state === 'recovery') { window = op.timer - lag; key = 'rec' + op.serial; p = lv.punish; }
    else if (op.state === 'backstep' || op.state === 'dash') {
      const mvSpec = C.opNow.def.movement[op.state];
      window = mvSpec.duration - op.stateTime - lag;
      key = 'mv' + op.state + Math.round(op.t * 4);
      p = lv.whiffPunish * 0.5;
    }
    if (!key || window < 0.08) return false;
    if (!once(key, p)) return false;
    if (st.decided.get(key + 'done')) return false;
    const pun = bestPunisher(C, window - 0.03, dist);
    if (pun) {
      press(keyOf(pun).button, keyOf(pun).dir, now);
      st.decided.set(key + 'done', true);
      st.holdGuard = false;
      return true;
    }
    // too far: dash in when the window is long (guard break, ult recovery)
    if (window > 0.55 && dist > 2) { hold(1, 0.25, now); return true; }
    void me;
    return false;
  }

  function juggle(C) {
    const { op, opNow, match, me, mine, now, dist } = C;
    if (op.state !== 'launched' || op.hard || opNow.state !== 'launched') return false;
    if (opNow.recv.attacker !== me.index || opNow.recv.juggle >= match.rules.juggle.limit - 0.5) return false;
    const key = 'jg' + opNow.recv.hits;
    if (st.decided.has(key + 'done')) return false;
    if (!once(key, lv.juggle)) return false;
    // time until the victim lands
    const g = match.rules.gravity * (1 + match.rules.juggle.gravityStep * opNow.recv.juggle);
    const land = (opNow.vy + Math.sqrt(Math.max(0, opNow.vy * opNow.vy + 2 * g * opNow.y))) / g;
    let best = null, bw = 0;
    for (const x of mine.pressable) {
      if (!x.mv.hits.length || x.fd.startup === null || x.fd.startup > land - 0.03) continue;
      if (!x.mv.hits.some((h) => h.air)) continue;
      if (dist > x.reach + 0.2) continue;
      if (!usable(match, me, x)) continue;
      let w = x.fd.damage + (x.role === 'combo' ? 60 : 0) + (x.role === 'poke' ? 30 : 0);
      if (x.role === 'finisher') w = me.ult >= me.ultMax && R() < lv.ult ? 400 : 0;
      if (x.role === 'launcher') w *= 0.6;
      if (w > bw) { bw = w; best = x; }
    }
    if (!best) { if (dist > 1.6) hold(1, 0.1, now); return dist > 1.6; }
    press(keyOf(best).button, keyOf(best).dir, now);
    st.decided.set(key + 'done', true);
    return true;
  }

  function oki(C) {
    const { op, now, dist, mine, match, me } = C;
    if (op.state !== 'knockdown' && op.state !== 'getup') return false;
    const left = (op.state === 'knockdown' ? op.timer + match.rules.getupTime : op.timer) - C.lag;
    const want = mine.pokeReach - 0.3;
    if (dist > want + 0.3) { hold(1, 0.08, now); return true; }
    const key = 'oki' + Math.round(op.t * 2);
    if (once('okd' + op.serial + ':' + Math.round(op.t), lv.meaty)) {
      const x = mine.strikes.find((s) => s.role === 'poke' && usable(match, me, s)) || mine.strikes[0];
      if (x && left <= x.fd.startup + 0.02 && left > x.fd.startup - 0.06 && !st.decided.has(key)) {
        st.decided.set(key, true);
        press(keyOf(x).button, keyOf(x).dir, now);
      }
      return true;
    }
    if (left < 0.25 && R() < lv.guard * 0.5) guardFor(0.3, now);
    return true;
  }

  // ------------------------------------------------------------------------------------------------- neutral
  function neutral(C) {
    const { me, op, match, mine, theirs, now, dist } = C;
    const A = clamp01(lv.aggression * 0.6 + me.def.ai.aggression * 0.4);
    const zoning = me.def.ai.zoning;
    const hpLead = me.hp / me.hpMax - op.hp;
    const clockLow = match.clock < 20;
    const guardLow = me.guard / me.guardMax < 0.3;
    const theirReach = theirs.threatReach;
    const prefer = Math.max(1.2, mine.pokeReach - 0.15);
    const opts = [];
    const mistake = R() < lv.mistake;

    // movement
    const far = dist - prefer;
    opts.push({ k: 'approach', w: far > 0.3 ? 1.2 + A + far * 0.25 : 0.15 });
    opts.push({ k: 'dash', w: far > 1.2 ? 0.4 + A * 0.6 : 0 });
    opts.push({ k: 'retreat', w: (dist < theirReach + 0.25 && dist > 0.9 ? lv.spacing * 0.8 : 0.1) + (hpLead > 0.15 && clockLow ? 1 : 0) + (guardLow ? 0.4 : 0) });
    opts.push({ k: 'backstep', w: dist < 1.3 ? lv.spacing * 0.35 : 0 });
    opts.push({ k: 'wait', w: 0.35 + (1 - A) * 0.5 + (hpLead > 0.1 && clockLow ? 0.8 : 0) });
    opts.push({ k: 'guard', w: dist < theirReach + 0.6 ? 0.25 + (1 - A) * 0.4 + st.opAggro * 0.4 : 0.02 });
    opts.push({ k: 'dodgeBait', w: dist < theirReach + 0.4 && me.dodgeCooldown <= 0 ? 0.08 : 0 });

    // attacks from data
    for (const x of mine.pressable) {
      if (x.role === 'finisher' || x.role === 'counter') continue;
      if (!usable(match, me, x)) continue;
      const inRange = dist >= x.range[0] - 0.05 && dist <= x.range[1] + 0.05;
      if (!inRange && !mistake) continue;
      let w = x.weight;
      switch (x.role) {
        case 'poke': w *= 1.0 + A * 0.8; break;
        case 'pressure': w *= 0.6 + A * 0.6 + (op.guard < 0.4 ? 0.8 : 0) + st.opGuardRate * 0.6; break;
        case 'approach': w *= 0.5 + A * 0.7; break;
        case 'launcher': w *= 0.35 + A * 0.3; break;
        case 'zoning': w *= (0.4 + zoning * 1.4) * (dist > 4 ? 1.3 : 0.5); break;
        case 'combo': w *= 0.25; break;
        case 'mobility': w *= 0.25 + A * 0.25; break;
        default: w *= 0.5;
      }
      if (x.fd.fpCost) w *= lv.skill * (me.fp > x.fd.fpCost + 20 ? 1 : 0.5);
      if (op.invuln) w *= 0.2;
      opts.push({ k: 'attack', x, w });
    }
    // counter stance as a read against an aggressive opponent at close range
    const counter = mine.pressable.find((x) => x.role === 'counter' && usable(match, me, x));
    if (counter && dist < theirReach + 0.8) opts.push({ k: 'attack', x: counter, w: st.opAggro * lv.counter * 1.2 });
    // raw ultimate: rare, mostly at close range on lower levels; the strong AI saves it for punishes and combos
    const ult = mine.pressable.find((x) => x.role === 'finisher' && usable(match, me, x));
    if (ult && dist <= ult.range[1]) opts.push({ k: 'attack', x: ult, w: lv.ult * (difficulty === 'easy' ? 0.4 : 0.06) });

    let o;
    if (mistake) o = opts[Math.floor(R() * opts.length)];
    else o = pick(opts);
    if (!o) return;
    switch (o.k) {
      case 'approach': hold(1, 0.15 + R() * 0.35, now); break;
      case 'dash': press('dodge', 'f', now); break;
      case 'retreat': hold(-1, 0.15 + R() * 0.3, now); break;
      case 'backstep': press('dodge', 'b', now); break;
      case 'wait': hold(0, 0.1 + R() * 0.25, now); break;
      case 'guard': guardFor(0.15 + R() * 0.35, now); break;
      case 'dodgeBait': press('dodge', null, now); break;
      case 'attack': {
        const k = keyOf(o.x);
        st.holdGuard = false;
        press(k.button, k.dir, now);
        break;
      }
      default: break;
    }
  }

  const clamp01 = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);

  return {
    kind: 'ai',
    difficulty,
    level: lv,
    attach({ rng: r }) { if (!ownRng) R = r; reset(); },
    reset,
    update,
  };
}

export { ATTACK_KEYS };
