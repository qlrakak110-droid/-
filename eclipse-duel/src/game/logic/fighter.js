// Fighter state machine: neutral movement, buffered actions, moves (timeline, motion, cancels), stun timers and
// airborne physics. Hit resolution lives in combat.js; the match orchestrates the order of a substep.

import { ATTACK_BUTTONS, COMBO_STATES } from './constants.js';
import { resolveCommand } from './defs.js';
import { createInputTracker, latestPress, consumePress, pressDir } from './input.js';
import { forwardAt, heightAt, windowAt, crosses, passes, EPS } from './moves.js';
import { spawnProjectile } from './projectiles.js';
import { spendFp, spendUlt, refillGuard } from './meters.js';

/**
 * Create the runtime state of one fighter.
 * @param {object} m match  @param {object} def compiled fighter definition  @param {number} index 0 | 1
 */
export function createFighter(m, def, index) {
  const s = def.stats;
  const f = {
    index,
    id: def.id,
    name: def.name,
    def,
    // body
    x: 0, y: 0, vx: 0, vy: 0, facing: index === 0 ? 1 : -1, airborne: false,
    // meters
    hp: s.hp, hpMax: s.hp, fp: s.fpMax, fpMax: s.fpMax, ult: 0, ultMax: s.ultMax, guard: s.guardMax, guardMax: s.guardMax,
    // state
    state: 'intro', stateTime: 0, timer: 0, stunKind: null, walkDir: 0,
    move: null, moveData: null, moveTime: 0, movePrevTime: 0, moveSerial: 0,
    moveConnected: false, moveHit: false,
    hitstop: 0, hitstopShake: false,
    combo: { hits: 0, damage: 0, active: false },
    recv: { active: false, hits: 0, damage: 0, juggle: 0, time: 0, scale: 1, wallBounces: 0, attacker: -1, crumpled: false },
    cooldowns: {},
    dodgeCooldown: 0,
    rounds: 0,
    result: null,
    // presentation flags (recomputed every substep)
    invulnerable: false,
    armoured: false,
    // internals
    input: createInputTracker(),
    hitCounts: [], hitLast: [],
    armourUsed: 0,
    endPending: false,
    turnTimer: 0,
    hard: false, koFall: false,
    slideFrom: -1,
    fpRegenWait: 0, guardRegenWait: 0,
    recoveryInvuln: false,
    perfectDodged: false,
    mov: null,
    _moveAdvanced: false,
  };
  return f;
}

/** Reset a fighter for a new round (HP / FP / guard / cooldowns reset; ULT kept unless `resetUlt`). */
export function resetFighter(m, f, x, facing, resetUlt) {
  const s = f.def.stats;
  f.x = x; f.y = 0; f.vx = 0; f.vy = 0; f.facing = facing; f.airborne = false;
  f.hp = f.hpMax = s.hp;
  f.fp = Math.min(s.fpMax, m.rules.meters.fpStart);
  f.guard = s.guardMax;
  if (resetUlt) f.ult = 0;
  f.state = 'intro'; f.stateTime = 0; f.timer = 0; f.stunKind = null; f.walkDir = 0;
  f.move = null; f.moveData = null; f.moveTime = 0; f.movePrevTime = 0;
  f.moveConnected = false; f.moveHit = false;
  f.hitstop = 0; f.hitstopShake = false;
  f.combo.hits = 0; f.combo.damage = 0; f.combo.active = false;
  Object.assign(f.recv, { active: false, hits: 0, damage: 0, juggle: 0, time: 0, scale: 1, wallBounces: 0, attacker: -1, crumpled: false });
  f.cooldowns = {};
  f.dodgeCooldown = 0;
  f.result = null;
  f.invulnerable = false; f.armoured = false;
  f.armourUsed = 0; f.endPending = false; f.turnTimer = 0; f.hard = false; f.koFall = false; f.slideFrom = -1;
  f.fpRegenWait = 0; f.guardRegenWait = 0; f.recoveryInvuln = false; f.perfectDodged = false; f.mov = null;
}

// ---------------------------------------------------------------------------------------------------------------
// state helpers

/** Change state (emits 'state'; ends a received combo when leaving the combo states). */
export function setState(m, f, state, timer = 0) {
  const from = f.state;
  f.timer = timer;
  if (from === state) return;
  f.state = state;
  f.stateTime = 0;
  if (state !== 'hitstun') f.stunKind = null;
  if (state !== 'recovery') f.recoveryInvuln = false;
  if (f.recv.active && COMBO_STATES.has(from) && !COMBO_STATES.has(state)) endCombo(m, f);
  m.emit('state', { fighter: f.index, from, to: state });
}

/** Close the combo `f` is receiving. */
function endCombo(m, f) {
  const r = f.recv;
  if (!r.active) return;
  r.active = false;
  const a = m.fighters[r.attacker] || m.fighters[1 - f.index];
  a.combo.active = false;
  m.emit('comboEnd', { attacker: a.index, defender: f.index, hits: r.hits, damage: r.damage, juggle: r.juggle, duration: r.time });
}

/** Distance between the two fighters' centres. */
const gap = (f, o) => Math.abs(o.x - f.x);

/** Turn to face the opponent immediately. */
export function faceOpponent(m, f) {
  const o = m.fighters[1 - f.index];
  const d = o.x - f.x;
  if (Math.abs(d) < 0.01) return;
  const want = d > 0 ? 1 : -1;
  if (want !== f.facing) {
    f.facing = want;
    m.emit('turn', { fighter: f.index, facing: want });
  }
  f.turnTimer = 0;
}

function autoFace(m, f, h) {
  const o = m.fighters[1 - f.index];
  const d = o.x - f.x;
  if (Math.abs(d) < 0.02) return;
  const want = d > 0 ? 1 : -1;
  if (want === f.facing) { f.turnTimer = 0; return; }
  f.turnTimer += h;
  if (f.turnTimer >= m.rules.turnDelay) faceOpponent(m, f);
}

/**
 * Move along X, clamped to the arena walls (and, when `limitSep`, to rules.maxSeparation from the opponent).
 * Returns the displacement actually applied.
 */
function moveX(m, f, dx, limitSep) {
  if (!dx) return 0;
  const L = m.rules.arenaHalfWidth - f.def.stats.pushWidth;
  let nx = f.x + dx;
  if (limitSep) {
    const o = m.fighters[1 - f.index];
    const maxS = m.rules.maxSeparation;
    if (Math.abs(nx - o.x) > maxS && Math.abs(nx - o.x) > Math.abs(f.x - o.x)) nx = f.x;
  }
  if (nx < -L) nx = -L; else if (nx > L) nx = L;
  const moved = nx - f.x;
  f.x = nx;
  return moved;
}

/** True when the fighter stands with its back within `dist` of a wall. */
export function backToWall(m, f, dist) {
  const L = m.rules.arenaHalfWidth - f.def.stats.pushWidth;
  return f.facing > 0 ? f.x - -L <= dist : L - f.x <= dist;
}

// ---------------------------------------------------------------------------------------------------------------
// moves

/**
 * Why a move cannot start now (null when it can).
 * @returns {null|'phase'|'fp'|'ult'|'cooldown'|'freeze'|'distance'|'airborne'|'hp'}
 */
export function moveBlockReason(m, f, mv) {
  if (m.phase !== 'fight') return 'phase';
  if (f.fp + 1e-9 < mv.fpCost) return 'fp';
  if (mv.ultCost > 0 && f.ult + 1e-9 < mv.ultCost) return 'ult';
  if ((f.cooldowns[mv.cooldownKey] || 0) > 0) return 'cooldown';
  if (mv.superFreeze && m.freeze) return 'freeze';
  const rq = mv.requires;
  if (rq) {
    const o = m.fighters[1 - f.index];
    const d = gap(f, o);
    if (rq.minDistance !== undefined && d < rq.minDistance) return 'distance';
    if (rq.maxDistance !== undefined && d > rq.maxDistance) return 'distance';
    if (rq.opponentAirborne !== undefined && rq.opponentAirborne !== (o.state === 'launched')) return 'airborne';
    if (rq.hpBelow !== undefined && f.hp / f.hpMax > rq.hpBelow) return 'hp';
  }
  return null;
}

/**
 * Start a move. `forced` skips costs and cooldowns (counter follow-ups).
 * @param {object} m @param {object} f @param {string} id
 * @param {{cancelFrom?: string|null, forced?: boolean}} [opts]
 */
export function startMove(m, f, id, { cancelFrom = null, forced = false } = {}) {
  const mv = f.def.moves[id];
  if (f.move) endMove(m, f, cancelFrom ? 'cancel' : 'interrupted');
  // facing is locked during a move, but every new move (cancels included) turns toward the opponent first, so a
  // follow-up after a pass-through or teleport attacks the right way
  faceOpponent(m, f);
  if (!forced) {
    if (mv.fpCost > 0) spendFp(m, f, mv.fpCost);
    if (mv.ultCost > 0) spendUlt(m, f, mv.ultCost, mv.group === 'ult');
    if (mv.cooldown > 0) f.cooldowns[mv.cooldownKey] = mv.cooldown;
  }
  f.move = id;
  f.moveData = mv;
  f.moveTime = 0;
  f.movePrevTime = 0;
  f.moveSerial++;
  f.moveConnected = false;
  f.moveHit = false;
  f.armourUsed = 0;
  f.endPending = false;
  const n = mv.hits.length;
  if (f.hitCounts.length !== n) { f.hitCounts = new Array(n); f.hitLast = new Array(n); }
  f.hitCounts.fill(0);
  f.hitLast.fill(-Infinity);
  f.vx = 0;
  setState(m, f, 'attack');
  m.emit('moveStart', {
    fighter: f.index, move: id, name: mv.name, group: mv.group, cancelFrom, forced, facing: f.facing, x: f.x, y: f.y,
    duration: mv.duration, serial: f.moveSerial,
  });
  if (mv.superFreeze) {
    m.freeze = { owner: f.index, move: id, remaining: mv.superFreeze.duration, duration: mv.superFreeze.duration, userAnimates: mv.superFreeze.userAnimates };
    m.emit('superFreezeStart', { fighter: f.index, move: id, duration: mv.superFreeze.duration, x: f.x, y: f.y, facing: f.facing });
    m.emit('marker', { fighter: f.index, move: id, name: 'superFreeze', t: 0, data: { duration: mv.superFreeze.duration }, x: f.x, y: f.y, facing: f.facing });
  }
  runTimeline(m, f, -1, 0);
}

/** End the current move (reason: 'complete' | 'cancel' | 'interrupted' | 'cinematic' | 'round'). */
export function endMove(m, f, reason) {
  if (!f.move) return;
  const id = f.move;
  f.move = null;
  f.moveData = null;
  f.endPending = false;
  m.emit('moveEnd', { fighter: f.index, move: id, reason, connected: f.moveConnected, hit: f.moveHit });
}

/** Timeline items (markers, projectiles, teleports) with tPrev < t <= tNow. */
function runTimeline(m, f, tPrev, tNow) {
  const mv = f.moveData;
  for (const tp of mv.teleports) if (passes(tp.t, tPrev, tNow)) teleport(m, f, tp);
  for (const s of mv.projectiles) if (passes(s.t, tPrev, tNow)) spawnProjectile(m, f, s, mv);
  for (const k of mv.markers) {
    if (passes(k.t, tPrev, tNow)) m.emit('marker', { fighter: f.index, move: mv.id, name: k.name, t: k.t, data: k.data, x: f.x, y: f.y, facing: f.facing });
  }
}

function teleport(m, f, tp) {
  const o = m.fighters[1 - f.index];
  const from = f.x;
  const L = m.rules.arenaHalfWidth - f.def.stats.pushWidth;
  let nx = tp.to === 'behind' ? o.x + f.facing * tp.distance : f.x + f.facing * tp.distance;
  nx = Math.max(-L, Math.min(L, nx));
  f.x = nx;
  if (tp.face) faceOpponent(m, f);
  m.emit('teleport', { fighter: f.index, move: f.move, from, to: nx, facing: f.facing });
}

/** Is a cancel window of the current move open now? Returns the open windows (reused array). */
const openWins = [];
function openCancels(f) {
  openWins.length = 0;
  const mv = f.moveData, t = f.moveTime;
  for (const c of mv.cancels) {
    if (t < c.t0 - EPS || t > c.t1 + EPS) continue;
    if (c.onHit && !f.moveHit) continue;
    if (c.onContact && !f.moveConnected) continue;
    openWins.push(c);
  }
  return openWins;
}

const dirOk = (d, dir) => (d === 'f' ? dir.fwd > 0 : d === 'b' ? dir.fwd < 0 : d === 'd' ? dir.down : dir.up);

function tryCancel(m, f) {
  const wins = openCancels(f);
  if (!wins.length) return false;
  const tr = f.input;
  const from = f.move;
  for (const b of ATTACK_BUTTONS) {
    const e = latestPress(tr, b);
    if (!e) continue;
    const dir = pressDir(tr, e, f.facing);
    let target = null;
    for (const c of wins) if (c.on === b && c.dir && dirOk(c.dir, dir)) { target = c.route; break; }
    if (!target) for (const c of wins) if (c.on === b && !c.dir) { target = c.route; break; }
    if (!target) {
      const id = resolveCommand(f.def, b, dir);
      if (id) {
        const g = f.def.moves[id].group;
        for (const c of wins) if (!c.on && (c.ids.has(id) || c.groups.has('any') || c.groups.has(g))) { target = id; break; }
      }
    }
    if (!target) continue;
    const mv = f.def.moves[target];
    const why = moveBlockReason(m, f, mv);
    if (!why) {
      consumePress(tr, e);
      startMove(m, f, target, { cancelFrom: from });
      return true;
    }
    if (!e.denied) { e.denied = true; m.emit('moveDenied', { fighter: f.index, move: target, reason: why }); }
  }
  // dodge / dash cancels
  const e = latestPress(tr, 'dodge');
  if (e) {
    const dodgeOk = wins.some((c) => !c.on && c.groups.has('dodge'));
    const dashOk = wins.some((c) => !c.on && c.groups.has('dash'));
    const dir = pressDir(tr, e, f.facing);
    if (dir.fwd !== 0 && dashOk) { consumePress(tr, e); endMove(m, f, 'cancel'); startMovement(m, f, dir.fwd > 0 ? 'dash' : 'backstep'); return true; }
    if (dir.fwd === 0 && dodgeOk && f.dodgeCooldown <= 0) { consumePress(tr, e); endMove(m, f, 'cancel'); startMovement(m, f, 'dodge'); return true; }
  }
  return false;
}

/**
 * Try every buffered action in priority order: moves (ult > skills > heavy > light), then dodge / dash.
 * @returns {boolean} true when something started
 */
function tryActions(m, f, allowDodge = true) {
  const tr = f.input;
  for (const b of ATTACK_BUTTONS) {
    const e = latestPress(tr, b);
    if (!e) continue;
    const id = resolveCommand(f.def, b, pressDir(tr, e, f.facing));
    if (!id) { consumePress(tr, e); continue; }
    const why = moveBlockReason(m, f, f.def.moves[id]);
    if (!why) { consumePress(tr, e); startMove(m, f, id); return true; }
    if (!e.denied) { e.denied = true; m.emit('moveDenied', { fighter: f.index, move: id, reason: why }); }
  }
  if (!allowDodge) return false;
  const e = latestPress(tr, 'dodge');
  if (e) {
    const dir = pressDir(tr, e, f.facing);
    if (dir.fwd > 0) { consumePress(tr, e); startMovement(m, f, 'dash'); return true; }
    if (dir.fwd < 0) { consumePress(tr, e); startMovement(m, f, 'backstep'); return true; }
    if (f.dodgeCooldown <= 0) { consumePress(tr, e); startMovement(m, f, 'dodge'); return true; }
  }
  if (tr.dashReq) {
    const fwd = tr.dashReq.dir * f.facing;
    tr.dashReq = null;
    startMovement(m, f, fwd > 0 ? 'dash' : 'backstep');
    return true;
  }
  return false;
}

/**
 * Start a movement action: 'dash' | 'backstep' | 'dodge'. A forward dash with the back to the wall and the opponent
 * right in front becomes a 'roll' that passes through the opponent (the corner escape).
 */
function startMovement(m, f, kind) {
  const o = m.fighters[1 - f.index];
  faceOpponent(m, f);
  if (kind === 'dash' && backToWall(m, f, 1.1) && gap(f, o) < f.def.stats.pushWidth + o.def.stats.pushWidth + 0.6 && o.y < 0.5) kind = 'roll';
  const spec = f.def.movement[kind];
  f.mov = { kind, dist: spec.distance || 0, dur: spec.duration, dir: kind === 'backstep' ? -1 : 1 };
  f.perfectDodged = false;
  f.vx = 0;
  setState(m, f, kind);
  m.emit('dodge', { fighter: f.index, kind, x: f.x, facing: f.facing, duration: spec.duration });
}

const easeOut = (u) => 1 - (1 - u) * (1 - u);

// ---------------------------------------------------------------------------------------------------------------
// per-substep update

/** Return to neutral (or to the victory / defeat pose once the round is over) and act at once (reversals). */
function toNeutral(m, f) {
  if (f.result && m.phase !== 'fight') {
    setState(m, f, f.result === 'win' ? 'victory' : 'defeat');
    return;
  }
  setState(m, f, 'idle');
  faceOpponent(m, f);
  neutral(m, f, 0);
}

function neutral(m, f, h) {
  if (m.phase === 'fight' && tryActions(m, f, true)) return;
  const inp = f.input.held;
  autoFace(m, f, h);
  if (inp.guard && m.phase === 'fight') {
    if (f.state !== 'guard') setState(m, f, 'guard');
    return;
  }
  const fwd = inp.move * f.facing;
  if (fwd !== 0) {
    f.walkDir = fwd;
    if (f.state !== 'walk') setState(m, f, 'walk');
    const sp = fwd > 0 ? f.def.stats.walkSpeed : f.def.stats.backSpeed;
    moveX(m, f, inp.move * sp * h, fwd < 0);
  } else if (f.state !== 'idle') setState(m, f, 'idle');
}

/** Ground slide from pushback (vx) with friction; a victim pinned to the wall passes the push to its attacker. */
function slide(m, f, h) {
  if (!f.vx) return;
  const want = f.vx * h;
  const moved = moveX(m, f, want, false);
  if (Math.abs(moved) < Math.abs(want) - 1e-9 && f.slideFrom >= 0) {
    const a = m.fighters[f.slideFrom];
    if (a.y <= 0.01 && a.state !== 'launched') a.vx = -f.vx * 0.85;
    f.slideFrom = -1;
    f.vx = 0;
    return;
  }
  const dec = m.rules.groundFriction * h;
  f.vx = Math.abs(f.vx) <= dec ? 0 : f.vx - Math.sign(f.vx) * dec;
  if (!f.vx) f.slideFrom = -1;
}

/** Put a fighter into the air (launch / juggle / knockdown flight). */
export function launch(m, f, vx, vy, hard) {
  if (f.state !== 'launched') setState(m, f, 'launched');
  f.vx = vx;
  f.vy = vy;
  f.hard = !!hard;
  if (f.y <= 0) f.y = 0.001;
  f.airborne = true;
}

function airborne(m, f, h) {
  const R = m.rules;
  const g = R.gravity * (1 + R.juggle.gravityStep * f.recv.juggle);
  f.vy -= g * h;
  f.y += f.vy * h;
  const want = f.vx * h;
  const moved = moveX(m, f, want, false);
  if (Math.abs(moved) < Math.abs(want) - 1e-9) {
    const wb = R.wallBounce;
    if (!f.koFall && Math.abs(f.vx) >= wb.speed && f.recv.wallBounces < wb.max && f.recv.active) {
      f.recv.wallBounces++;
      f.recv.juggle += 1;
      f.vx = -f.vx * wb.restitution;
      f.vy = Math.max(f.vy, wb.pop);
      f.hard = false;
      m.emit('wallBounce', { fighter: f.index, x: f.x, y: f.y });
    } else f.vx = 0;
  }
  f.vx *= Math.max(0, 1 - R.airDrag * h);
  if (f.y <= 0 && f.vy <= 0) land(m, f);
}

function land(m, f) {
  f.y = 0;
  f.vy = 0;
  f.airborne = false;
  f.vx *= 0.3;
  const tech = !f.hard && !f.koFall && latestPress(f.input, 'dodge');
  m.emit('land', { fighter: f.index, x: f.x, hard: !tech, ko: f.koFall });
  if (f.koFall) { setState(m, f, 'ko'); return; }
  if (tech) {
    consumePress(f.input, tech);
    // recovery roll away from the opponent: invulnerable, then neutral
    const o = m.fighters[1 - f.index];
    f.vx = (f.x > o.x ? 1 : -1) * Math.sqrt(2 * m.rules.groundFriction * m.rules.techRollDistance);
    setState(m, f, 'getup', m.rules.getupTime);
    m.emit('tech', { fighter: f.index, x: f.x });
    return;
  }
  setState(m, f, 'knockdown', m.rules.knockdownTime);
}

/**
 * Advance one fighter by `h` seconds of its own time (hit-stop already removed by the caller).
 */
export function updateFighter(m, f, h) {
  f._moveAdvanced = false;
  if (f.endPending) finishMove(m, f);
  const st0 = f.stateTime;
  f.stateTime += h;
  if (f.recv.active) f.recv.time += h;
  switch (f.state) {
    case 'idle': case 'walk': case 'guard':
      if (m.phase === 'fight') neutral(m, f, h);
      else if (f.result) toNeutral(m, f);
      else if (f.state !== 'idle') setState(m, f, 'idle');
      slide(m, f, h);
      break;
    case 'attack':
      advanceMove(m, f, h);
      slide(m, f, h);
      break;
    case 'dash': case 'backstep': case 'roll': case 'dodge': {
      const mv = f.mov;
      if (mv.dist) {
        const u0 = Math.min(1, st0 / mv.dur), u1 = Math.min(1, f.stateTime / mv.dur);
        moveX(m, f, (easeOut(u1) - easeOut(u0)) * mv.dist * mv.dir * f.facing, mv.dir < 0);
      }
      const spec = f.def.movement[mv.kind];
      if (f.stateTime >= mv.dur) {
        if (mv.kind === 'dodge') f.dodgeCooldown = spec.cooldown;
        f.mov = null;
        toNeutral(m, f);
      } else if (spec.cancelFrom !== undefined && f.stateTime >= spec.cancelFrom && m.phase === 'fight') {
        tryActions(m, f, false);
      }
      break;
    }
    case 'hitstun':
      slide(m, f, h);
      f.timer -= h;
      if (f.timer <= 0) {
        if (f.stunKind === 'crumple') { setState(m, f, 'knockdown', m.rules.knockdownTime); m.emit('land', { fighter: f.index, x: f.x, hard: true, ko: false }); }
        else toNeutral(m, f);
      }
      break;
    case 'blockstun':
      slide(m, f, h);
      f.timer -= h;
      if (f.timer <= 0) toNeutral(m, f);
      break;
    case 'guardbreak':
      slide(m, f, h);
      f.timer -= h;
      if (f.timer <= 0) { refillGuard(m, f); toNeutral(m, f); }
      break;
    case 'launched':
      airborne(m, f, h);
      break;
    case 'knockdown':
      slide(m, f, h);
      f.timer -= h;
      if (f.timer <= 0) setState(m, f, 'getup', m.rules.getupTime);
      break;
    case 'getup': case 'recovery':
      slide(m, f, h);
      f.timer -= h;
      if (f.timer <= 0) toNeutral(m, f);
      break;
    case 'ko': case 'victory': case 'defeat': case 'intro':
      slide(m, f, h);
      break;
    default:
      break; // 'locked': driven by the cinematic
  }
}

function finishMove(m, f) {
  endMove(m, f, 'complete');
  // motion height tracks must end on the floor (the validator warns); snap whatever is left
  f.y = 0;
  f.airborne = false;
  toNeutral(m, f);
}

function advanceMove(m, f, h) {
  const mv = f.moveData;
  const fz = m.freeze;
  if (fz && fz.owner === f.index && !fz.userAnimates) return;
  const t0 = f.moveTime;
  const t1 = Math.min(mv.duration, t0 + h);
  f.movePrevTime = t0;
  f.moveTime = t1;
  f._moveAdvanced = true;
  if (mv.motion) {
    const d = forwardAt(mv, t1) - forwardAt(mv, t0);
    if (d) moveX(m, f, d * f.facing, false);
    const hy = heightAt(mv, t1);
    if (hy !== null) { f.y = hy; f.airborne = hy > 0.01; }
  }
  runTimeline(m, f, t0, t1);
  if (f.state !== 'attack' || f.moveData !== mv) return;
  if (tryCancel(m, f)) return;
  if (t1 >= mv.duration - EPS) {
    // keep the move alive for this substep when a hit window touches it, so the final hit can still be collected
    let pending = false;
    for (const ht of mv.hits) if (crosses(ht.t0, ht.t1, t0, t1)) { pending = true; break; }
    if (pending) f.endPending = true;
    else finishMove(m, f);
  }
}

/** Is fighter `f` invulnerable to `kind` ('strike' | 'projectile') right now? */
export function isInvulnerable(m, f, kind) {
  if (m.phase !== 'fight') return true;
  if (m.cinematic) return true;
  if (m.freeze && m.freeze.owner === f.index) return true;
  switch (f.state) {
    case 'knockdown': case 'getup': case 'locked': case 'ko': case 'intro': case 'victory': case 'defeat': case 'roll':
      return true;
    case 'recovery':
      return f.recoveryInvuln;
    case 'dodge': {
      const w = f.def.movement.dodge.invuln;
      return f.stateTime >= w[0] && f.stateTime <= w[1];
    }
    case 'backstep': {
      const w = f.def.movement.backstep.invuln;
      return kind === 'strike' && !!w && f.stateTime >= w[0] && f.stateTime <= w[1];
    }
    case 'launched':
      return f.hard || f.koFall || f.recv.juggle >= m.rules.juggle.limit - 1e-9;
    case 'attack': {
      const w = windowAt(f.moveData.invuln, f.moveTime);
      return !!w && (w.vs === 'all' || w.vs === kind);
    }
    default:
      return false;
  }
}

/** Are push-boxes off for this fighter now (roll, pass-through windows, cinematic)? */
export function passesThrough(m, f) {
  if (f.state === 'roll' || f.state === 'locked' || f.state === 'ko') return true;
  if (f.state === 'attack') return !!windowAt(f.moveData.passThrough, f.moveTime);
  return false;
}

/** Recompute the presentation flags (invulnerable, armoured, airborne). */
export function refreshFlags(m, f) {
  f.invulnerable = m.phase === 'fight' && isInvulnerable(m, f, 'strike');
  f.armoured = f.state === 'attack' && !!windowAt(f.moveData.armour, f.moveTime);
  f.airborne = f.y > 0.01;
}
