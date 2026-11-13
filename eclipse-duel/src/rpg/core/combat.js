// Combat resolution of the RPG mode (README §6.2, §6.3): 3D hit volumes in the attacker's frame against body cylinders
// (or hurt spheres), then i-frames -> counter stances -> guard / perfect guard -> armour / poise -> reaction, damage,
// events. Deterministic, allocation-free until a hit actually lands (the event payload).

import * as THREE from 'three';
import { EPS, angDiff, crosses, fwdX, fwdZ, hypot2, rightX, rightZ, wrapPi, yawTo } from './math3.js';
import { LEVELS } from './attacks.js';
import { spendStamina } from './actor.js';

const V = new THREE.Vector3(), A = new THREE.Vector3(), B = new THREE.Vector3();
/** contact scratch */
const C = { x: 0, y: 0, z: 0, part: null };

// ---- shape tests ----------------------------------------------------------------------------------------------------

/** World point of a shape anchor: [f, u, s] in the attacker frame, or a socket name. */
function anchor(a, spec, out) {
  if (typeof spec === 'string') return a.socket(spec, out);
  return a.at(spec[0], spec[1], spec[2], out);
}

/**
 * Does the hit shape of attacker `a` (attack time t, window start t0) touch a vertical cylinder at (x, z), radius r,
 * from y0 to y1? Writes the contact point into C.
 */
function touches(a, shape, t, t0, x, z, r, y0, y1) {
  const dx = x - a.pos.x, dz = z - a.pos.z;
  const ay = a.pos.y;
  switch (shape.type) {
    case 'arc': {
      if (ay + shape.u1 < y0 || ay + shape.u0 > y1) return false;
      const d = hypot2(dx, dz);
      if (d - r > shape.r1 || d + r < shape.r0) return false;
      if (d > r && shape.a1 - shape.a0 < Math.PI * 2 - 1e-3) {
        const lf = dx * fwdX(a.yaw) + dz * fwdZ(a.yaw), ls = dx * rightX(a.yaw) + dz * rightZ(a.yaw);
        const ang = Math.atan2(ls, lf), mid = (shape.a0 + shape.a1) * 0.5, half = (shape.a1 - shape.a0) * 0.5;
        if (Math.abs(wrapPi(ang - mid)) > half + Math.asin(Math.min(1, r / d))) return false;
      }
      return contact(a, x, z, r, ay + shape.u0, ay + shape.u1, y0, y1);
    }
    case 'box': {
      if (ay + shape.u1 < y0 || ay + shape.u0 > y1) return false;
      const lf = dx * fwdX(a.yaw) + dz * fwdZ(a.yaw), ls = dx * rightX(a.yaw) + dz * rightZ(a.yaw);
      if (lf < shape.f0 - r || lf > shape.f1 + r || ls < shape.s0 - r || ls > shape.s1 + r) return false;
      return contact(a, x, z, r, ay + shape.u0, ay + shape.u1, y0, y1);
    }
    case 'ring': {
      if (ay + shape.u1 < y0 || ay + shape.u0 > y1) return false;
      a.at(shape.at[0], 0, shape.at[2], V);
      const k = Math.max(0, t - t0);
      const d = hypot2(x - V.x, z - V.z);
      if (d - r > shape.r1 + shape.g1 * k || d + r < shape.r0 + shape.g0 * k) return false;
      return contact(a, x, z, r, ay + shape.u0, ay + shape.u1, y0, y1);
    }
    case 'sphere': {
      if (shape.socket) a.socket(shape.socket, V); else anchor(a, shape.at, V);
      const py = Math.max(y0, Math.min(y1, V.y));
      const ddx = V.x - x, ddz = V.z - z, ddy = V.y - py;
      const R = shape.r * (shape.socket ? a.scale : 1) + r;
      if (ddx * ddx + ddz * ddz + ddy * ddy > R * R) return false;
      C.x = x + ddx * 0.5; C.y = py; C.z = z + ddz * 0.5;
      return true;
    }
    case 'capsule': {
      anchor(a, shape.a, A); anchor(a, shape.b, B);
      const d = segToAxis(A, B, x, z, y0, y1);
      if (d > shape.r + r) return false;
      return true;
    }
    default: return false;
  }
}

/** Contact point on a struck cylinder: toward the attacker, at the vertical middle of the overlap. */
function contact(a, x, z, r, u0, u1, y0, y1) {
  const dx = a.pos.x - x, dz = a.pos.z - z;
  const d = hypot2(dx, dz) || 1;
  const k = Math.min(r * 0.75, d * 0.5);
  C.x = x + (dx / d) * k; C.z = z + (dz / d) * k;
  const lo = Math.max(u0, y0), hi = Math.min(u1, y1);
  // bias toward chest height of the victim rather than the box middle (floor-to-sky boxes)
  const chest = y0 + (y1 - y0) * 0.68;
  C.y = Math.max(lo, Math.min(hi, chest));
  return true;
}

/** Distance between segment AB and the vertical segment at (x, z) from y0 to y1; writes the closest point into C. */
function segToAxis(a, b, x, z, y0, y1) {
  // sample-free closest points of two segments (Ericson, Real-Time Collision Detection 5.1.9)
  const d1x = b.x - a.x, d1y = b.y - a.y, d1z = b.z - a.z;
  const d2y = y1 - y0;
  const rx = a.x - x, ry = a.y - y0, rz = a.z - z;
  const aa = d1x * d1x + d1y * d1y + d1z * d1z, e = d2y * d2y, f = d2y * ry;
  let s, t;
  if (aa <= 1e-9 && e <= 1e-9) { s = t = 0; }
  else if (aa <= 1e-9) { s = 0; t = Math.max(0, Math.min(1, f / e)); }
  else {
    const c = d1x * rx + d1y * ry + d1z * rz;
    if (e <= 1e-9) { t = 0; s = Math.max(0, Math.min(1, -c / aa)); }
    else {
      const bb = d1y * d2y, den = aa * e - bb * bb;
      s = den > 1e-9 ? Math.max(0, Math.min(1, (bb * f - c * e) / den)) : 0;
      t = (bb * s + f) / e;
      if (t < 0) { t = 0; s = Math.max(0, Math.min(1, -c / aa)); } else if (t > 1) { t = 1; s = Math.max(0, Math.min(1, (bb - c) / aa)); }
    }
  }
  const px = a.x + d1x * s, py = a.y + d1y * s, pz = a.z + d1z * s;
  const qy = y0 + d2y * t;
  C.x = (px + x) * 0.5; C.y = (py + qy) * 0.5; C.z = (pz + z) * 0.5;
  return Math.sqrt((px - x) * (px - x) + (py - qy) * (py - qy) + (pz - z) * (pz - z));
}

/**
 * Test a hit shape against a victim (body cylinder, or its hurt spheres). Returns true and fills C (+ C.part).
 */
export function shapeHits(a, shape, t, t0, v) {
  C.part = null;
  const hurt = v.spec.hurt;
  if (!hurt) return touches(a, shape, t, t0, v.pos.x, v.pos.z, v.radius, v.pos.y, v.pos.y + v.height);
  let best = null;
  for (let i = 0; i < hurt.length; i++) {
    const p = hurt[i];
    if (p.socket) v.socket(p.socket, V); else v.at(p.at[0], p.at[1], p.at[2], V);
    const px = V.x, py = V.y, pz = V.z, pr = p.r * (p.socket ? v.scale : 1);
    if (!touches(a, shape, t, t0, px, pz, pr, py - pr, py + pr)) continue;
    if (!best || (p.weak && !best.weak)) { best = p; A.set(C.x, C.y, C.z); }
  }
  if (!best) return false;
  C.x = A.x; C.y = A.y; C.z = A.z; C.part = best;
  return true;
}

// ---- strikes --------------------------------------------------------------------------------------------------------

/** Collect and resolve the active hit windows of every attacking actor. */
export function resolveStrikes(world) {
  const actors = world.actors;
  for (let i = 0; i < actors.length; i++) {
    const a = actors[i];
    const inst = a.attack;
    if (!inst || a.gone || world.frozen(a)) continue;
    const def = inst.def;
    for (let h = 0; h < def.hits.length; h++) {
      const hit = def.hits[h];
      if (!crosses(hit.t0, hit.t1, inst.tPrev, inst.t)) continue;
      for (let j = 0; j < actors.length; j++) {
        const v = actors[j];
        if (v === a || v.gone || v.dead || v.leaving > 0 || !world.hostile(a, v)) continue;
        if (v.state === 'spawn') continue;
        if (!hit.air && v.pos.y > 0.3) continue;
        if (!hit.ground && v.pos.y <= 0.3) continue;
        // per (hit, victim) log: one touch per window unless the hit is a multi-hit
        let rec = null;
        for (let k = 0; k < inst.log.length; k++) { const r = inst.log[k]; if (r.hit === h && r.vid === v.id) { rec = r; break; } }
        if (rec && (rec.n >= hit.multiMax || rec.dodged || inst.t - rec.t < hit.multiInterval - EPS)) continue;
        if (!shapeHits(a, hit.shape, inst.t, hit.t0, v)) continue;
        if (!rec) { rec = { hit: h, vid: v.id, n: 0, t: 0, dodged: false }; inst.log.push(rec); }
        rec.t = inst.t;
        const res = resolveHit(world, a, v, def, hit, { kind: 'strike', x: C.x, y: C.y, z: C.z, part: C.part, inst });
        if (res === 'dodge' || res === 'counter') rec.dodged = true; else rec.n++;
        if (!a.attack || a.attack !== inst) break;     // countered / interrupted by the resolution
      }
      if (!a.attack || a.attack !== inst) break;
    }
  }
}

/**
 * Resolve one hit (README §6.3). `info`: { kind: 'strike' | 'projectile' | 'tick' | 'effect', x, y, z, part, inst,
 * projectile, dirX, dirZ }. Returns 'dodge' | 'counter' | 'perfect' | 'guard' | 'break' | 'hit'.
 */
export function resolveHit(world, a, v, def, hit, info) {
  const kind = info.kind || 'strike';
  // direction of the blow on the floor plane
  let dirX, dirZ;
  if (info.dirX !== undefined) { dirX = info.dirX; dirZ = info.dirZ; }
  else if (hit.radial || !a) {
    const ox = a ? a.pos.x : info.x, oz = a ? a.pos.z : info.z;
    const d = hypot2(v.pos.x - ox, v.pos.z - oz) || 1;
    dirX = (v.pos.x - ox) / d; dirZ = (v.pos.z - oz) / d;
  } else { dirX = fwdX(a.yaw); dirZ = fwdZ(a.yaw); }
  const pos = { x: info.x ?? v.pos.x, y: info.y ?? v.pos.y + v.height * 0.65, z: info.z ?? v.pos.z };
  const base = {
    attacker: a, victim: v, attack: def, hit, id: def ? def.id : '', kind, damage: 0, level: hit.level,
    reaction: '', armoured: false, blocked: false, perfect: false, guardBreak: false, part: info.part ? info.part.name || null : null,
    pos, dirX, dirZ, hitstop: 0, killed: false, front: true, crit: false, projectile: info.projectile || null,
    inst: info.inst || null,
  };
  // which side of the victim the blow comes from
  const fromYaw = yawTo(-dirX, -dirZ);
  base.front = Math.abs(angDiff(v.yaw, fromYaw)) < Math.PI * 0.5;

  // 1. invulnerable: the hit is consumed
  if (v.invuln && kind !== 'tick') {
    world.emit('dodge', { actor: v, attacker: a, perfect: v.state === 'roll', attack: def, kind });
    return 'dodge';
  }
  // 2. counter stance (a fighter move with `counter`)
  const vi = v.attack;
  if (vi && vi.def.counter && !vi.counterUsed && !hit.unblockable && kind !== 'tick') {
    const c = vi.def.counter;
    if (vi.t >= c.t0 - EPS && vi.t <= c.t1 + EPS && (c.vs === 'all' || (c.vs === 'strike') === (kind === 'strike'))) {
      vi.counterUsed = true;
      world.hitstop(c.hitstop);
      world.emit('counter', { actor: v, attacker: a, attack: vi.def, id: vi.id, move: c.move, pos });
      v.startAttack(c.move, { force: true, target: a, aim: a ? yawTo(a.pos.x - v.pos.x, a.pos.z - v.pos.z) : undefined });
      return 'counter';
    }
  }
  const dmgMul = (a ? a.mult.damage * (a.spec.stats && a.spec.stats.damage !== undefined ? a.spec.stats.damage : 1) : 1)
    * (a && a.derived ? (def && def.group !== 'normal' ? a.derived.arcane : a.derived.phys) : 1)
    * (v.spec.taken ?? 1) * (info.part && info.part.taken !== undefined ? info.part.taken : 1) * (info.scale ?? 1);
  let damage = Math.max(0, Math.round(hit.damage * dmgMul));
  const L = LEVELS[hit.level] || LEVELS.light;
  const hero = world.hero;
  const involvesHero = a === hero || v === hero;

  // 3. guard
  if (v.guarding && v.guard && !hit.unblockable && kind !== 'tick' && a && Math.abs(angDiff(v.yaw, fromYaw)) <= v.guard.arc) {
    base.blocked = true;
    if (v.state === 'guard' && v.guardTime <= v.guard.perfect) {
      base.perfect = true;
      base.hitstop = 0.11;
      if (involvesHero) world.hitstop(base.hitstop);
      if (kind === 'strike' && a.alive) {
        a.poise -= hit.poise * 2.5; a.poiseT = 0;
        if (!a.armour && !a.spec.boss) a.stun('stagger', 0.95, { vx: -dirX * 1.5, vz: -dirZ * 1.5, by: v });
        else if (a.poiseMax > 0 && a.poise <= 0) poiseBreak(world, a, v);
      }
      if (v.fpMax > 0) v.fp = Math.min(v.fpMax, v.fp + 8);
      if (v.ultMax > 0) v.ult = Math.min(v.ultMax, v.ult + 5);
      if (info.inst) info.inst.contact = true;
      world.emit('perfectGuard', base);
      return 'perfect';
    }
    const cost = hit.guard;
    if (v.staminaMax === Infinity || v.stamina > cost) {
      spendStamina(v, cost);
      damage = Math.round(damage * hit.chip);
      if (v === hero && world.godMode) damage = 0;
      base.damage = Math.min(damage, Math.max(0, v.hp - 1));     // chip never kills
      v.hp -= base.damage;
      base.hitstop = hit.hitstop * 0.6;
      if (involvesHero && kind === 'strike') world.hitstop(base.hitstop);
      v.stun('guardhit', 0.2 + hit.hitstop, { vx: dirX * 2.2 / v.mass, vz: dirZ * 2.2 / v.mass, by: a });
      if (info.inst) info.inst.contact = true;
      world.emit('guard', base);
      return 'guard';
    }
    // guard broken
    base.guardBreak = true;
    v.stamina = 0; v.exhausted = true; v.stamT = 0;
    damage = Math.round(damage * 0.6);
    if (v === hero && world.godMode) damage = 0;
    base.damage = damage;
    v.hp -= damage;
    base.hitstop = 0.12;
    if (involvesHero) world.hitstop(base.hitstop);
    if (info.inst) { info.inst.contact = true; info.inst.connected = true; info.inst.hitCount++; }
    base.reaction = 'stagger';
    if (v.hp <= 0) { base.killed = true; world.emit('guardBreak', base); v.die(a); return 'break'; }
    v.stun('guardbreak', 1.1, { vx: dirX * 2.5 / v.mass, vz: dirZ * 2.5 / v.mass, by: a });
    world.emit('guardBreak', base);
    return 'break';
  }

  // 4. hit
  if (v === hero && world.godMode) damage = 0;
  base.damage = damage;
  base.crit = !!(info.part && info.part.weak) || !!info.crit;
  v.hp -= damage;
  const vInst = v.attack;
  let armoured = v.armour && !hit.armourPierce;
  if (armoured && vInst && vInst.armourLeft !== Infinity && vInst.armourLeft > 0) vInst.armourLeft--;
  let broke = false;
  if (v.poiseMax > 0) {
    const before = v.poise;
    v.poise -= hit.poise * (info.part && info.part.poise !== undefined ? info.part.poise : 1);
    v.poiseT = 0;
    if (before > 0 && v.poise <= 0) broke = true;
    // poise holds: no reaction to light / heavy blows
    if (!broke && v.poise > 0 && (hit.level === 'light' || hit.level === 'heavy' || v.spec.boss || v.spec.elite)) armoured = true;
  }
  if (v.spec.boss && !broke) armoured = true;
  base.armoured = armoured && !broke;
  base.hitstop = kind === 'projectile' ? 0 : hit.hitstop;
  if (involvesHero && base.hitstop > 0) world.hitstop(base.hitstop);
  if (info.inst) { info.inst.connected = true; info.inst.contact = true; info.inst.hitCount++; }
  // meters of the attacker
  if (a && a.ultMax > 0 && def && def.group !== 'ult' && damage > 0) a.ult = Math.min(a.ultMax, a.ult + damage * (a.spec.ultGain ?? 0.03));
  if (a && a.fpMax > 0 && def && def.group === 'normal' && damage > 0) { a.fp = Math.min(a.fpMax, a.fp + (hit.level === 'light' ? 2.5 : 5)); }
  if (v.ultMax > 0 && damage > 0) v.ult = Math.min(v.ultMax, v.ult + (damage / v.hpMax) * 60);

  if (v.hp <= 0) {
    v.hp = 0;
    base.killed = true;
    base.reaction = 'dead';
    // the body is thrown by the killing blow
    v.vel.x = dirX * Math.max(2.5, hit.kf) / v.mass; v.vel.z = dirZ * Math.max(2.5, hit.kf) / v.mass;
    if (hit.ku > 0 && !v.immovable) { v.vel.y = hit.ku * 0.7; v.pos.y = Math.max(v.pos.y, 0.02); }
    world.emit('hit', base);
    if (v.spec.onHit) v.spec.onHit(world, v, base);
    v.die(a);
    return 'hit';
  }
  if (broke) {
    poiseBreak(world, v, a);
    base.reaction = v.spec.boss ? 'break' : 'stagger';
    if (!v.spec.boss && !v.spec.onPoiseBreak) v.stun(hit.level === 'launch' || hit.level === 'knockdown' ? hit.level === 'launch' ? 'launched' : 'knockdown' : 'stagger', Math.max(0.9, hit.stun), { vx: dirX * hit.kf / v.mass, vz: dirZ * hit.kf / v.mass, vy: hit.ku || undefined, front: base.front, by: a });
  } else if (!base.armoured && kind !== 'tick' && !v.cine) {
    const kx = dirX * hit.kf / v.mass, kz = dirZ * hit.kf / v.mass;
    switch (hit.level) {
      case 'light': base.reaction = 'flinch'; v.stun('flinch', hit.stun || L.stun, { vx: kx, vz: kz, front: base.front, by: a }); break;
      case 'heavy': base.reaction = 'stagger'; v.stun('stagger', hit.stun || L.stun, { vx: kx, vz: kz, front: base.front, by: a }); break;
      case 'crumple': base.reaction = 'crumple'; v.stun('crumple', hit.stun || L.stun, { vx: kx, vz: kz, front: base.front, by: a }); break;
      case 'launch': base.reaction = 'launched'; v.stun('launched', 0, { vx: kx, vz: kz, vy: hit.ku || L.ku, front: base.front, by: a }); break;
      default: base.reaction = 'knockdown'; v.stun('knockdown', 0, { vx: kx, vz: kz, vy: hit.ku || L.ku, front: base.front, by: a });
    }
  }
  world.emit('hit', base);
  if (v.spec.onHit) v.spec.onHit(world, v, base);
  return 'hit';
}

function poiseBreak(world, v, by) {
  world.emit('poiseBreak', { actor: v, by });
  if (v.spec.onPoiseBreak) { try { v.spec.onPoiseBreak(world, v, by); } catch (e) { world.warnOnce('pb:' + v.kind, v.kind + '.onPoiseBreak threw: ' + (e && e.message)); } }
}

/** Scratch hit for world.damage. */
const EFFECT = { damage: 0, poise: 0, level: 'light', kf: 0, ku: 0, stun: 0, hitstop: 0, guard: 10, chip: 0.1, unblockable: false, armourPierce: false, multiMax: 1, multiInterval: 0, radial: true, air: true, ground: true };

/**
 * Damage outside an attack timeline (README §4 world.damage).
 * d: { amount, poise, level, from, pos: {x,y,z}, dir: {x,z}, kind, unblockable, hitstop, knock: {f,u}, scale }
 */
export function applyDamage(world, v, d) {
  if (!v || v.dead || v.gone) return null;
  const L = LEVELS[d.level || 'light'] || LEVELS.light;
  const hit = { ...EFFECT, damage: d.amount || 0, poise: d.poise ?? 0, level: d.level || 'light', kf: d.knock ? d.knock.f ?? L.kf : L.kf, ku: d.knock ? d.knock.u ?? L.ku : L.ku,
    stun: L.stun, hitstop: d.hitstop ?? 0, unblockable: !!d.unblockable, guard: d.guard ?? Math.round((d.amount || 0) * 0.4) };
  const info = { kind: d.kind || 'effect', x: d.pos ? d.pos.x : undefined, y: d.pos ? d.pos.y : undefined, z: d.pos ? d.pos.z : undefined, scale: d.scale, crit: d.crit };
  if (d.dir) { info.dirX = d.dir.x; info.dirZ = d.dir.z; }
  return resolveHit(world, d.from || null, v, d.attack || null, hit, info);
}
