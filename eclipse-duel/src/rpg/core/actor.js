// Actors of the RPG mode: the one object hero, enemies and the boss share, and the humanoid state machine
// (locomotion, roll, guard, attack timelines, reactions, death). README §5. Pure logic: the picture is core/view.js.
//
//   const a = createActor(world, spec, id, { x, z, yaw });      (world.spawn does this)
//   stepActor(world, a, dt);                                    (world.step, fixed 1/60 s)

import * as THREE from 'three';
import { DEG, EPS, STEP, angDiff, clamp, fwdX, fwdZ, hypot2, passes, rightX, rightZ, turnToward, yawTo } from './math3.js';
import { forwardAt, heightAt, normalizeAttack, windowAt } from './attacks.js';
import { createView } from './view.js';

const GRAVITY = -24;
const FRICTION = 15;

/** Defaults of the optional mechanics of a kind. */
const ROLL = { cost: 24, distance: 3.7, duration: 0.62, travel: 0.48, invuln: [0.03, 0.36], actFrom: 0.5, backScale: 0.55 };
const GUARD = { perfect: 0.16, arc: 80 * DEG, speed: 1.35, regenScale: 0.35 };
const STAMINA = { regen: 46, delay: 0.75, sprint: 13, recover: 0.15 };
const DRINK = { duration: 1.5, at: 0.9, speed: 0.9 };

/** Reset the reusable intent object (README §5.3). */
export function resetIntent(it) {
  it.moveX = 0; it.moveZ = 0; it.run = true; it.sprint = false; it.face = NaN; it.strafe = false;
  it.attack = ''; it.guard = false; it.roll = false; it.drink = false; it.interact = false;
  return it;
}

/**
 * @param {object} world
 * @param {object} spec kind spec (registry)
 * @param {number} id
 * @param {object} opts { x, z, yaw, level, target, controller, ... } (also handed to spec.onSpawn / spec.create)
 */
export function createActor(world, spec, id, opts = {}) {
  const st = spec.stats || {};
  const level = opts.level ?? 0;
  const mult = { hp: opts.hpMult ?? Math.pow(1.35, level), damage: opts.damageMult ?? Math.pow(1.2, level) };
  const isHero = spec.team === 'hero';
  const hpMax = Math.round((st.hp || 100) * (isHero ? 1 : mult.hp));
  const a = {
    id, kind: spec.kind, spec,
    team: spec.team || 'foe',
    name: spec.name || { ko: spec.kind, en: spec.kind },
    pos: { x: opts.x || 0, y: 0, z: opts.z || 0 },
    prev: { x: opts.x || 0, y: 0, z: opts.z || 0 },
    yaw: 0, prevYaw: 0,
    vel: { x: 0, y: 0, z: 0 },
    radius: st.radius ?? 0.42, height: st.height ?? 1.9, scale: st.scale ?? 1, mass: st.mass ?? 1,
    immovable: !!(spec.boss || st.immovable),
    hp: hpMax, hpMax,
    poise: st.poise || 0, poiseMax: st.poise || 0, poiseT: 0,
    stamina: st.stamina ?? Infinity, staminaMax: st.stamina ?? Infinity, stamT: 9, exhausted: false,
    fp: st.fp ?? 0, fpMax: st.fp ?? 0, fpT: 9,
    ult: 0, ultMax: st.ult ?? 0,
    state: 'idle', stateTime: 0, stateDur: 0,
    /** bumped by every reaction (the view restarts the reaction clip) */
    react: 0, reactFront: true, stunKind: '', thenDown: false,
    attack: null, attackSerial: 0,
    target: opts.target || null,
    intent: resetIntent({}),
    controller: null,
    char: null, view: null, clips: null,
    alive: true, dead: false, gone: false, leaving: 0, leaveDur: 0,
    invuln: false, armour: false, guarding: false, ghost: false, noclip: false,
    invulnT: 0, cine: false, cineInvuln: false,
    /** current horizontal speed (m/s), gait ('walk' | 'run' | 'sprint') and the direction of travel */
    speed: 0, gait: 'run', moveX: 0, moveZ: 0, moveSpeed: 0,
    guardTime: 0, rollX: 0, rollZ: 0, rollDist: 0, rollBack: false,
    postRoll: 0, sprintT: 0, sprintRecent: 0,
    /** cooldowns by key (seconds left) */
    cd: {},
    /** buffered presses (hero): slot + seconds left */
    buf: { attack: '', attackLeft: 0, roll: 0 },
    level, mult,
    data: {},
    /** heroes: progression state + derived numbers (core/hero.js) */
    prog: null, derived: null,
    chalice: 0, chaliceMax: 0,

    // ---- helpers ----------------------------------------------------------------------------------------------------
    /** World point in the actor frame: f forward, u above the floor, s to its right. */
    at(f = 0, u = 0, s = 0, out = new THREE.Vector3()) {
      const y = a.yaw;
      return out.set(a.pos.x + f * fwdX(y) + s * rightX(y), a.pos.y + u, a.pos.z + f * fwdZ(y) + s * rightZ(y));
    },
    /** World position of a character socket (chest when unknown; the body centre without a character). */
    socket(name, out = new THREE.Vector3()) {
      const c = a.char;
      const s = c && c.sockets ? c.sockets[name] || c.sockets.chest : null;
      if (s) return s.getWorldPosition(out);
      return out.set(a.pos.x, a.pos.y + a.height * 0.7, a.pos.z);
    },
    distTo(b) { return hypot2(b.pos.x - a.pos.x, b.pos.z - a.pos.z); },
    /** Signed angle (rad) from this actor's facing to the direction of `b` (+ = to its right... see angDiff). */
    angleTo(b) { return angDiff(a.yaw, yawTo(b.pos.x - a.pos.x, b.pos.z - a.pos.z)); },
    setState(name, dur = 0) { setState(world, a, name, dur); },
    stun(kind, dur, o) { stun(world, a, kind, dur, o); },
    startAttack(idOrDef, o) { return startAttack(world, a, idOrDef, o || {}); },
    endAttack(reason) { endAttack(world, a, reason || 'cancel'); },
    die(by) { die(world, a, by || null); },
    /** Place the actor (no interpolation, cloth / IK memories reset). */
    teleport(x, z, yaw) {
      a.pos.x = a.prev.x = x; a.pos.z = a.prev.z = z; a.pos.y = a.prev.y = 0;
      if (yaw !== undefined) a.yaw = a.prevYaw = yaw;
      a.vel.x = a.vel.y = a.vel.z = 0;
      if (a.view) a.view.teleport();
    },
  };
  a.yaw = a.prevYaw = opts.yaw !== undefined ? opts.yaw : world.hero && world.hero !== a ? yawTo(world.hero.pos.x - a.pos.x, world.hero.pos.z - a.pos.z) : 0;
  a.roll = spec.roll ? { ...ROLL, ...spec.roll } : spec.roll === undefined && isHero ? { ...ROLL } : null;
  a.guard = spec.guard ? { ...GUARD, ...spec.guard, arc: (spec.guard.arc !== undefined ? spec.guard.arc * DEG : GUARD.arc) } : spec.guard === undefined && isHero ? { ...GUARD } : null;
  a.stam = { ...STAMINA, ...(spec.stamina || {}) };
  a.drinkSpec = { ...DRINK, ...(spec.drink || {}) };
  a.view = createView(world.ctx, world, a, opts);
  a.char = a.view.char;
  a.clips = a.view.clips;
  if (opts.controller) a.controller = opts.controller;
  else if (typeof spec.controller === 'function') a.controller = spec.controller(world, a, opts);
  else a.controller = spec.controller || null;
  const spawnTime = opts.spawnTime ?? spec.spawnTime ?? (isHero ? 0 : 0.6);
  if (spawnTime > 0) { a.state = 'spawn'; a.stateDur = spawnTime; }
  refreshFlags(a);
  return a;
}

export function disposeActor(world, a) {
  if (a.view) a.view.dispose();
  a.char = null;
}

// ---- state changes ------------------------------------------------------------------------------------------------

function setState(world, a, name, dur = 0) {
  const from = a.state;
  a.state = name;
  a.stateTime = 0;
  a.stateDur = dur;
  if (from !== name) world.emit('state', { actor: a, from, to: name });
}

/**
 * Force a reaction: 'flinch' | 'stagger' | 'launched' | 'knockdown' | 'crumple' | 'guardbreak' | 'guardhit'.
 * o: { vx, vz, vy, front }
 */
function stun(world, a, kind, dur, o = {}) {
  if (a.dead) return;
  if (a.attack) endAttack(world, a, 'interrupted');
  a.buf.attack = ''; a.buf.attackLeft = 0; a.buf.roll = 0;
  a.react++;
  a.reactFront = o.front !== false;
  a.stunKind = kind;
  a.thenDown = false;
  if (o.vx !== undefined) { a.vel.x = o.vx; a.vel.z = o.vz || 0; }
  switch (kind) {
    case 'guardhit': setState(world, a, 'guardhit', dur ?? 0.26); break;
    case 'flinch': setState(world, a, 'flinch', dur ?? 0.34); break;
    case 'crumple': a.thenDown = true; setState(world, a, 'stagger', dur ?? 0.95); break;
    case 'launched': case 'knockdown':
      a.vel.y = o.vy ?? (kind === 'launched' ? 7 : 3.2);
      a.pos.y = Math.max(a.pos.y, 0.02);
      setState(world, a, 'launched', 0);
      break;
    default: setState(world, a, 'stagger', dur ?? 0.62);
  }
  world.emit('stagger', { actor: a, kind, by: o.by || null });
}

function die(world, a, by) {
  if (a.dead) return;
  if (a.attack) endAttack(world, a, 'death');
  a.hp = 0;
  a.dead = true;
  a.alive = false;
  a.react++;
  setState(world, a, 'dead', 0);
  refreshFlags(a);
  const shards = a.team === 'hero' ? 0 : Math.round((a.spec.stats && a.spec.stats.shards || 0) * (1 + 0.35 * a.level));
  if (a.spec.onDeath) { try { a.spec.onDeath(world, a, by); } catch (e) { world.warnOnce('onDeath:' + a.kind, a.kind + '.onDeath threw: ' + (e && e.message)); } }
  world.emit('death', { actor: a, by, shards });
}

// ---- attacks --------------------------------------------------------------------------------------------------------

/** Start an attack now. o: { target, force (ignore costs / cooldown), aim (yaw) }. Returns true when it started. */
function startAttack(world, a, idOrDef, o) {
  let def = typeof idOrDef === 'string' ? world.attackOf(a, idOrDef) : idOrDef;
  if (!def) return false;
  if (!def.normalized) def = normalizeAttack(def);
  if (!o.force) {
    if ((a.cd[def.cooldownKey] || 0) > 0) return false;
    if (def.fp > 0 && a.fp + 1e-6 < def.fp) return false;
    if (def.ult > 0 && a.ult + 1e-6 < def.ult) return false;
    if (def.stamina > 0 && (a.exhausted || a.stamina <= 0)) return false;
    if (def.fp > 0) { a.fp -= def.fp; a.fpT = 0; }
    if (def.ult > 0) a.ult = 0;
    if (def.stamina > 0 && a.staminaMax !== Infinity) spendStamina(a, def.stamina);
    if (def.cooldown > 0) a.cd[def.cooldownKey] = def.cooldown;
  }
  if (a.attack) endAttack(world, a, 'cancel');
  const target = o.target !== undefined ? o.target : a.target;
  const inst = {
    def, id: def.id, t: 0, tPrev: -1, serial: ++a.attackSerial, target,
    /** hits landed (clean or blocked) / at least one clean hit */
    hitCount: 0, connected: false, contact: false,
    /** per (hit, victim) log: [{ hit, vid, n, t }] */
    log: [], armourLeft: -1, armourWin: null,
    aim: o.aim !== undefined ? o.aim : NaN,
    /** distance already travelled along the motion track */
    moved: 0, forced: !!o.force, counterUsed: false,
  };
  a.attack = inst;
  a.speed = 0;
  if (Number.isFinite(inst.aim)) a.yaw = inst.aim;
  setState(world, a, 'attack', def.duration);
  world.emit('attackStart', { actor: a, attack: def, id: def.id, inst });
  if (def.superFreeze && world.present) world.present.superFreeze(a, inst);
  return true;
}

function endAttack(world, a, reason) {
  const inst = a.attack;
  if (!inst) return;
  a.attack = null;
  if (a.pos.y > 0 && heightAt(inst.def, inst.t) >= 0) a.pos.y = 0;
  world.emit('attackEnd', { actor: a, attack: inst.def, id: inst.id, reason, connected: inst.connected, contact: inst.contact, inst });
}

function spendStamina(a, amount) {
  if (a.staminaMax === Infinity) return;
  a.stamina -= amount;
  a.stamT = 0;
  if (a.stamina <= 0) { a.stamina = 0; a.exhausted = true; }
}
export { spendStamina };

/** Advance the running attack: tracking, motion, markers, projectiles, teleports, end. */
export function updateAttack(world, a, dt) {
  const inst = a.attack, def = inst.def;
  inst.tPrev = inst.t;
  inst.t += dt;
  const t = inst.t, tp = inst.tPrev;
  // the world freeze of an ultimate holds everything but its owner
  const tgt = inst.target && inst.target.alive ? inst.target : null;
  // (a move that passes through its target stops tracking once it does: it must not turn back mid-dash)
  const passed = def.passThrough.length > 0 && t >= def.passThrough[0].t0;
  if (def.track && t <= def.track.until + EPS && tgt && !passed && !a.spec.noTrack) {
    a.yaw = turnToward(a.yaw, yawTo(tgt.pos.x - a.pos.x, tgt.pos.z - a.pos.z), def.track.rate * dt);
  }
  // motion along the facing; a solid target in the way stops it (nothing tunnels) unless the move passes through
  if (def.motion) {
    let df = forwardAt(def, t) - forwardAt(def, Math.max(0, tp));
    const pass = windowAt(def.passThrough, t) !== null;
    if (df > 0 && tgt && !pass && !tgt.ghost) {
      const dx = tgt.pos.x - a.pos.x, dz = tgt.pos.z - a.pos.z;
      const along = dx * fwdX(a.yaw) + dz * fwdZ(a.yaw), side = Math.abs(dx * rightX(a.yaw) + dz * rightZ(a.yaw));
      const min = a.radius + tgt.radius;
      if (side < min && along > 0) df = Math.max(0, Math.min(df, along - min * 0.92));
    }
    a.pos.x += fwdX(a.yaw) * df; a.pos.z += fwdZ(a.yaw) * df;
    const h = heightAt(def, t);
    if (h >= 0) a.pos.y = h;
  }
  for (let i = 0; i < def.teleports.length; i++) {
    const tp2 = def.teleports[i];
    if (!passes(tp2.t, tp, t)) continue;
    const fromX = a.pos.x, fromZ = a.pos.z;
    if (tp2.to === 'behind' && tgt) {
      const y = yawTo(tgt.pos.x - a.pos.x, tgt.pos.z - a.pos.z);
      const d = tp2.distance + tgt.radius;
      a.pos.x = tgt.pos.x + fwdX(y) * d; a.pos.z = tgt.pos.z + fwdZ(y) * d;
      if (tp2.face) a.yaw = yawTo(tgt.pos.x - a.pos.x, tgt.pos.z - a.pos.z);
    } else {
      a.pos.x += fwdX(a.yaw) * tp2.distance; a.pos.z += fwdZ(a.yaw) * tp2.distance;
    }
    const lim = world.arena.radius - a.radius;
    const d0 = hypot2(a.pos.x, a.pos.z);
    if (d0 > lim) { a.pos.x *= lim / d0; a.pos.z *= lim / d0; }
    a.prev.x = a.pos.x; a.prev.z = a.pos.z; a.prevYaw = a.yaw;
    world.emit('teleport', { actor: a, fromX, fromZ });
  }
  for (let i = 0; i < def.markers.length; i++) {
    const m = def.markers[i];
    if (passes(m.t, tp, t)) world.emit('marker', { actor: a, attack: def, id: def.id, name: m.name, data: m.data, t: m.t, inst });
  }
  for (let i = 0; i < def.projectiles.length; i++) {
    const p = def.projectiles[i];
    if (passes(p.t, tp, t) || (p.t <= 0 && tp < 0)) world.projectiles.fromAttack(a, inst, p);
  }
}

// ---- the humanoid machine -------------------------------------------------------------------------------------------

/** Advance one actor by dt (fixed step). */
export function stepActor(world, a, dt) {
  a.stateTime += dt;
  tick(world, a, dt);
  if (a.leaving > 0) return;
  if (a.spec.step) {
    a.spec.step(world, a, dt);
    refreshFlags(a);
    return;
  }
  if (a.cine) { refreshFlags(a); return; }
  const it = a.intent;
  // buffered presses (a press is kept for a moment so chains and roll-outs feel responsive)
  if (it.attack) { a.buf.attack = it.attack; a.buf.attackLeft = 0.32; }
  if (it.roll) a.buf.roll = 0.26;
  switch (a.state) {
    case 'spawn':
      if (a.stateTime >= a.stateDur) setState(world, a, 'idle');
      break;
    case 'idle': case 'move':
      if (!act(world, a, dt)) locomotion(world, a, dt, 1);
      break;
    case 'attack': {
      updateAttack(world, a, dt);
      const inst = a.attack;
      if (!inst) break;
      if (inst.t >= inst.def.duration - EPS) { endAttack(world, a, 'complete'); setState(world, a, 'idle'); act(world, a, dt); break; }
      cancelOut(world, a, inst, dt);
      break;
    }
    case 'roll': {
      const r = a.roll, T = r.duration, tt = Math.min(1, a.stateTime / r.travel);
      // ease-out travel: d * (1 - (1 - u)^2)
      const d = a.rollDist * (1 - (1 - tt) * (1 - tt));
      const step = d - a.rollMoved;
      a.rollMoved = d;
      a.pos.x += a.rollX * step; a.pos.z += a.rollZ * step;
      if (a.stateTime >= r.actFrom && (a.buf.attackLeft > 0 || (a.buf.roll > 0 && a.stateTime >= T - 0.05))) {
        a.postRoll = 0.4;
        setState(world, a, 'idle');
        act(world, a, dt);
      } else if (a.stateTime >= T) { a.postRoll = 0.4; setState(world, a, 'idle'); }
      break;
    }
    case 'guard': {
      a.guardTime += dt;
      if (a.buf.roll > 0 && tryRoll(world, a)) break;
      if (a.buf.attackLeft > 0 && tryAttackSlot(world, a, a.buf.attack)) break;
      if (!it.guard || a.exhausted) { setState(world, a, 'idle'); break; }
      locomotion(world, a, dt, 0, a.guard.speed);
      break;
    }
    case 'guardhit':
      slide(a, dt);
      a.guardTime += dt;
      if (a.stateTime >= a.stateDur) setState(world, a, it.guard && !a.exhausted ? 'guard' : 'idle');
      break;
    case 'flinch': case 'stagger':
      slide(a, dt);
      if (a.stateTime >= a.stateDur) {
        if (a.thenDown) { a.thenDown = false; a.react++; setState(world, a, 'down', a.spec.downTime ?? 0.9); }
        else { if (a.poise <= 0) a.poise = a.poiseMax; setState(world, a, 'idle'); }
      }
      break;
    case 'launched':
      a.vel.y += GRAVITY * dt;
      a.pos.y += a.vel.y * dt;
      a.pos.x += a.vel.x * dt; a.pos.z += a.vel.z * dt;
      if (a.pos.y <= 0 && a.vel.y < 0) {
        a.pos.y = 0; a.vel.y = 0; a.vel.x *= 0.35; a.vel.z *= 0.35;
        a.react++;
        setState(world, a, 'down', a.spec.downTime ?? 0.9);
        world.emit('land', { actor: a, hard: true });
      }
      break;
    case 'down':
      slide(a, dt);
      if (a.stateTime >= a.stateDur) setState(world, a, 'getup', a.spec.getupTime ?? 0.7);
      break;
    case 'getup':
      if (a.stateTime >= a.stateDur) { a.invulnT = 0.15; if (a.poise <= 0) a.poise = a.poiseMax; setState(world, a, 'idle'); }
      break;
    case 'drink': {
      const ds = a.drinkSpec;
      if (!a.drank && a.stateTime >= ds.at) {
        a.drank = true;
        const heal = Math.round(a.derived ? a.derived.chaliceHeal : a.hpMax * 0.4);
        a.hp = Math.min(a.hpMax, a.hp + heal);
        world.emit('drink', { actor: a, heal, left: a.chalice });
      }
      locomotion(world, a, dt, 0, ds.speed);
      if (a.stateTime >= ds.duration) setState(world, a, 'idle');
      break;
    }
    case 'dead':
      slide(a, dt);
      if (a.pos.y > 0) { a.vel.y += GRAVITY * dt; a.pos.y = Math.max(0, a.pos.y + a.vel.y * dt); }
      if (a.team !== 'hero' && !a.keepCorpse && a.stateTime >= (a.spec.corpseTime ?? 2.4)) world.despawn(a, { fade: 0.9 });
      break;
    default: break;   // 'rest' and unknown states: nothing
  }
  refreshFlags(a);
}

/** Timers every actor runs every step: cooldowns, stamina / poise / FP regeneration, buffers. */
function tick(world, a, dt) {
  for (const k in a.cd) if (a.cd[k] > 0) a.cd[k] = Math.max(0, a.cd[k] - dt);
  if (a.buf.attackLeft > 0) a.buf.attackLeft -= dt;
  if (a.buf.roll > 0) a.buf.roll -= dt;
  if (a.invulnT > 0) a.invulnT -= dt;
  if (a.postRoll > 0) a.postRoll -= dt;
  if (a.sprintRecent > 0) a.sprintRecent -= dt;
  if (a.dead) return;
  if (a.staminaMax !== Infinity) {
    a.stamT += dt;
    const busy = a.state === 'roll' || a.state === 'attack' || (a.state === 'move' && a.gait === 'sprint');
    if (!busy && a.stamT >= a.stam.delay && a.stamina < a.staminaMax) {
      const k = a.state === 'guard' || a.state === 'guardhit' ? (a.guard ? a.guard.regenScale : 0.35) : 1;
      a.stamina = Math.min(a.staminaMax, a.stamina + a.stam.regen * k * dt);
    }
    if (a.exhausted && a.stamina >= a.staminaMax * a.stam.recover) a.exhausted = false;
  }
  if (a.poiseMax > 0 && a.poise < a.poiseMax && a.poise > 0) {
    a.poiseT += dt;
    if (a.poiseT > 3) a.poise = Math.min(a.poiseMax, a.poise + a.poiseMax * 0.5 * dt);
  }
  if (a.fpMax > 0 && a.fp < a.fpMax) {
    a.fpT += dt;
    if (a.fpT > 1.5) a.fp = Math.min(a.fpMax, a.fp + (a.spec.fpRegen ?? 2.2) * dt);
  }
}

/** Slide with the knockback velocity (friction). */
function slide(a, dt) {
  const v = hypot2(a.vel.x, a.vel.z);
  if (v < 1e-3) { a.vel.x = a.vel.z = 0; return; }
  a.pos.x += a.vel.x * dt; a.pos.z += a.vel.z * dt;
  const nv = Math.max(0, v - FRICTION * dt);
  a.vel.x *= nv / v; a.vel.z *= nv / v;
}

/** Free-state actions by priority: drink, roll, attack, guard. Returns true when the state changed. */
function act(world, a, dt) {
  const it = a.intent;
  if (it.drink && tryDrink(world, a)) return true;
  if (a.buf.roll > 0 && tryRoll(world, a)) return true;
  if (a.buf.attackLeft > 0 && tryAttackSlot(world, a, a.buf.attack)) return true;
  if (it.guard && a.guard && !a.exhausted) {
    a.guardTime = 0;
    a.speed = Math.min(a.speed, a.guard.speed);
    setState(world, a, 'guard');
    return true;
  }
  void dt;
  return false;
}

/** During an attack: chain / cancel into the next action when the move allows it. */
function cancelOut(world, a, inst, dt) {
  const def = inst.def;
  const it = a.intent;
  const free = inst.t >= def.cancelFrom - EPS;
  if (a.buf.attackLeft > 0) {
    const pick = a.spec.cancelInto;
    const id = pick ? pick(world, a, inst, a.buf.attack, free) : free ? pickAttack(world, a, a.buf.attack) : null;
    if (id) {
      const aim = aimFor(world, a);
      if (startAttack(world, a, id, { aim })) { a.buf.attackLeft = 0; return; }
    }
  }
  const rollFrom = def.rollFrom ?? Math.min(def.cancelFrom, def.lastActive + 0.14);
  if (a.buf.roll > 0 && inst.t >= rollFrom && !def.superFreeze && tryRoll(world, a)) return;
  if (!free) return;
  if (it.drink && tryDrink(world, a)) return;
  if (it.guard && a.guard && !a.exhausted) { endAttack(world, a, 'cancel'); a.guardTime = 0; setState(world, a, 'guard'); return; }
  if (it.moveX * it.moveX + it.moveZ * it.moveZ > 0.04) { endAttack(world, a, 'cancel'); setState(world, a, 'idle'); locomotion(world, a, dt, 1); }
}

/** The attack id a slot press means right now (kinds may map slots by context: chains, sprint attack ...). */
function pickAttack(world, a, slot) {
  return a.spec.pick ? a.spec.pick(world, a, slot) : slot;
}

/** Facing an attack starts with: the locked / soft target, else the move input, else as it stands. */
function aimFor(world, a) {
  const it = a.intent;
  if (a.spec.aim) return a.spec.aim(world, a);
  const t = a.target && a.target.alive ? a.target : null;
  if (t) return yawTo(t.pos.x - a.pos.x, t.pos.z - a.pos.z);
  if (it.moveX * it.moveX + it.moveZ * it.moveZ > 0.04) return yawTo(it.moveX, it.moveZ);
  return NaN;
}

function tryAttackSlot(world, a, slot) {
  const id = pickAttack(world, a, slot);
  if (!id) { return false; }
  const ok = startAttack(world, a, id, { aim: aimFor(world, a) });
  if (ok) a.buf.attackLeft = 0;
  return ok;
}

function tryRoll(world, a) {
  const r = a.roll;
  if (!r || a.exhausted || a.stamina <= 0) return false;
  const it = a.intent;
  let dx = it.moveX, dz = it.moveZ;
  const m = hypot2(dx, dz);
  a.rollBack = m < 0.2;
  if (a.rollBack) { dx = -fwdX(a.yaw); dz = -fwdZ(a.yaw); } else { dx /= m; dz /= m; a.yaw = yawTo(dx, dz); }
  if (a.attack) endAttack(world, a, 'cancel');
  spendStamina(a, r.cost);
  a.buf.roll = 0;
  a.rollX = dx; a.rollZ = dz;
  a.rollDist = r.distance * (a.rollBack ? r.backScale : 1);
  a.rollMoved = 0;
  a.speed = 0;
  setState(world, a, 'roll', r.duration);
  world.emit('roll', { actor: a, dirX: dx, dirZ: dz, back: a.rollBack });
  return true;
}

function tryDrink(world, a) {
  if (a.chalice <= 0 || a.hp >= a.hpMax) return false;
  if (a.attack) endAttack(world, a, 'cancel');
  a.chalice--;
  a.drank = false;
  setState(world, a, 'drink', a.drinkSpec.duration);
  return true;
}

/**
 * Walk / run / sprint from the intent. `full` = 1: free locomotion (states idle / move); 0: a capped walk inside
 * another state (guard, drink) at `cap` m/s.
 */
function locomotion(world, a, dt, full, cap = 0) {
  const it = a.intent, st = a.spec.stats || {};
  let mx = it.moveX, mz = it.moveZ;
  const mag = Math.min(1, hypot2(mx, mz));
  const turn = (st.turn ?? 540) * DEG;
  if (mag > 0.1) {
    const len = hypot2(mx, mz);
    mx /= len; mz /= len;
    let v, gait = 'walk';
    const walk = st.walk ?? 1.6, run = st.run ?? walk;
    if (!full) v = cap;
    else if (it.sprint && !a.exhausted && a.stamina > 0 && st.sprint) { v = st.sprint; gait = 'sprint'; }
    else if (it.run !== false && mag > 0.55) { v = run; gait = 'run'; }
    else { v = walk; }
    if (gait === 'sprint') { spendStamina(a, a.stam.sprint * dt); a.sprintT += dt; a.sprintRecent = 0.25; } else a.sprintT = 0;
    const accel = st.accel ?? 26;
    a.speed = a.speed < v ? Math.min(v, a.speed + accel * dt) : Math.max(v, a.speed - accel * 1.4 * dt);
    const strafe = it.strafe || (!full && a.target && a.target.alive);
    if (strafe) {
      const fy = Number.isFinite(it.face) ? it.face : a.target ? yawTo(a.target.pos.x - a.pos.x, a.target.pos.z - a.pos.z) : a.yaw;
      a.yaw = turnToward(a.yaw, fy, turn * dt);
    } else a.yaw = turnToward(a.yaw, yawTo(mx, mz), turn * dt);
    a.moveX = mx; a.moveZ = mz;
    a.pos.x += mx * a.speed * dt; a.pos.z += mz * a.speed * dt;
    a.gait = gait;
    a.moveSpeed = a.speed;
    if (full && a.state !== 'move') setState(world, a, 'move');
  } else {
    a.sprintT = 0;
    if (a.speed > 0) {
      a.speed = Math.max(0, a.speed - (st.decel ?? 34) * dt);
      a.pos.x += a.moveX * a.speed * dt; a.pos.z += a.moveZ * a.speed * dt;
    }
    a.moveSpeed = a.speed;
    const fy = Number.isFinite(it.face) ? it.face : !full && a.target && a.target.alive ? yawTo(a.target.pos.x - a.pos.x, a.target.pos.z - a.pos.z) : NaN;
    if (Number.isFinite(fy)) a.yaw = turnToward(a.yaw, fy, turn * dt);
    if (full && a.state !== 'idle' && a.speed <= 0.05) setState(world, a, 'idle');
  }
}
export { locomotion, slide, tryRoll, tryAttackSlot, act };

/** Refresh the flags the hit resolution reads. */
export function refreshFlags(a) {
  const s = a.state;
  let inv = s === 'spawn' || s === 'down' || s === 'getup' || s === 'dead' || s === 'rest' || a.invulnT > 0 || a.cineInvuln;
  let armour = false, ghost = false;
  if (s === 'roll' && a.roll) {
    const t = a.stateTime;
    if (t >= a.roll.invuln[0] && t <= a.roll.invuln[1]) inv = true;
    ghost = t <= a.roll.duration * 0.8;
  }
  const inst = a.attack;
  if (inst) {
    const def = inst.def, t = inst.t;
    if (windowAt(def.invuln, t)) inv = true;
    const w = windowAt(def.armour, t);
    if (w) {
      if (inst.armourWin !== w) { inst.armourWin = w; inst.armourLeft = w.hits === undefined || w.hits === Infinity ? Infinity : w.hits; }
      armour = inst.armourLeft > 0;
    }
    if (windowAt(def.passThrough, t)) ghost = true;
  }
  a.invuln = inv;
  a.armour = armour || !!a.spec.alwaysArmour;
  a.ghost = ghost;
  a.guarding = s === 'guard' || s === 'guardhit';
}

export { STEP };
