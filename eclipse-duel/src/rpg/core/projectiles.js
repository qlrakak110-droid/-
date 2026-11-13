// 3D projectiles of the RPG mode (README §6.4): travelling shots (waves, shards, javelins, enemy bolts) and stationary
// floor effects armed after a delay (magma columns, ice spikes, sky strikes). A projectile is a vertical cylinder that
// moves on the floor plane; it hits hostile body cylinders through the same hit resolution as strikes.

import { fwdX, fwdZ, hypot2, rightX, rightZ, yawTo } from './math3.js';
import { normalizeAttack } from './attacks.js';

/**
 * @param {object} world
 */
export function createProjectiles(world) {
  const list = [];
  let nextId = 1;

  /** Normalise a `hit` given in author form ({ damage, level, knock ... }). */
  function hitOf(h, group) {
    if (h && h.t0 !== undefined && h.kf !== undefined) return h;
    return normalizeAttack({ id: 'p', duration: 1, group, hits: [{ ...h, t: [0, 0], shape: { type: 'arc' } }] }).hits[0];
  }

  /**
   * Launch a projectile (README §6.4).
   * @param {object} owner actor (its team decides who can be hit)
   * @param {object} s spec
   * @param {object} [def] attack it belongs to (damage group, events)
   */
  function shoot(owner, s, def = null) {
    const group = def ? def.group : s.group || 'skill';
    let x, y, z;
    const yaw0 = s.yaw !== undefined ? s.yaw : owner.yaw;
    if (s.pos) { x = s.pos.x; y = s.pos.y || 0; z = s.pos.z; }
    else {
      const at = s.at || [0, null, 0];
      const u = at[1] === null || at[1] === undefined ? owner.height * 0.65 : at[1];
      x = owner.pos.x + at[0] * fwdX(yaw0) + (at[2] || 0) * rightX(yaw0);
      z = owner.pos.z + at[0] * fwdZ(yaw0) + (at[2] || 0) * rightZ(yaw0);
      y = owner.pos.y + u;
    }
    let dx, dy, dz;
    if (s.aim && s.aim.pos) {
      const tx = s.aim.pos.x - x, tz = s.aim.pos.z - z, ty = s.aim.pos.y + s.aim.height * 0.6 - y;
      const d = Math.hypot(tx, ty, tz) || 1;
      dx = tx / d; dy = s.flat ? 0 : ty / d; dz = tz / d;
    } else {
      const d = s.dir || [1, 0, 0];
      dx = d[0] * fwdX(yaw0) + (d[2] || 0) * rightX(yaw0);
      dz = d[0] * fwdZ(yaw0) + (d[2] || 0) * rightZ(yaw0);
      dy = d[1] || 0;
    }
    const speed = s.speed || 0;
    const p = {
      id: nextId++, owner, team: owner.team, kind: s.kind || 'shot', def, group,
      x, y, z, vx: dx * speed, vy: dy * speed, vz: dz * speed,
      dirX: dx, dirZ: dz, yaw: yawTo(dx, dz), speed,
      gravity: s.gravity || 0, age: 0, delay: s.delay || 0, lifetime: s.lifetime ?? 1,
      radius: s.radius ?? 0.4, h0: s.height ? s.height[0] : -0.3, h1: s.height ? s.height[1] : 0.3,
      ground: s.ground !== undefined ? !!s.ground : speed < 2,
      pierce: !!s.pierce, hit: hitOf(s.hit || { damage: 10 }, group),
      multiMax: s.multi ? s.multi.max : 1, multiInterval: s.multi ? s.multi.interval : 0,
      log: [], data: s.data || {}, alive: true, armed: !(s.delay > 0),
      /** presentation slot (core/present.js) */
      view: null,
      /** where it started (stage frames of its presentation are anchored here) */
      x0: x, z0: z, ownerX: owner.pos.x, ownerZ: owner.pos.z, ownerYaw: yaw0,
    };
    list.push(p);
    world.emit('projectileSpawn', { projectile: p, owner, kind: p.kind, pos: p, delay: p.delay });
    if (p.armed) world.emit('projectileActive', { projectile: p, owner, kind: p.kind, pos: p });
    return p;
  }

  /** Spawn a projectile entry of an attack timeline (normalised by fromFighterMove / normalizeAttack). */
  function fromAttack(a, inst, e) {
    const spec = { ...e };
    if (e.from === 'opponent') {
      const t = inst.target && inst.target.alive ? inst.target : null;
      const fwd = e.at ? e.at[0] : 0;
      if (t) {
        const yaw = yawTo(t.pos.x - a.pos.x, t.pos.z - a.pos.z);
        spec.pos = { x: t.pos.x + fwd * fwdX(yaw), y: 0, z: t.pos.z + fwd * fwdZ(yaw) };
        spec.yaw = yaw;
      } else spec.pos = { x: a.pos.x + (4 + fwd) * fwdX(a.yaw), y: 0, z: a.pos.z + (4 + fwd) * fwdZ(a.yaw) };
      spec.at = null;
    }
    return shoot(a, spec, inst.def);
  }

  function expire(p, reason) {
    if (!p.alive) return;
    p.alive = false;
    world.emit('projectileExpire', { projectile: p, owner: p.owner, kind: p.kind, pos: p, reason });
  }

  function step(dt) {
    const actors = world.actors;
    const R = world.arena.radius + 1.5;
    for (let i = 0; i < list.length; i++) {
      const p = list[i];
      if (!p.alive) continue;
      p.age += dt;
      if (!p.armed) {
        if (p.age < p.delay) continue;
        p.armed = true;
        world.emit('projectileActive', { projectile: p, owner: p.owner, kind: p.kind, pos: p });
      }
      const life = p.age - p.delay;
      if (life > p.lifetime) { expire(p, 'lifetime'); continue; }
      p.vy += p.gravity * dt;
      p.x += p.vx * dt; p.y += p.vy * dt; p.z += p.vz * dt;
      if (hypot2(p.x, p.z) > R) { expire(p, 'wall'); continue; }
      if (p.y + p.h1 < 0 && p.vy < 0) { expire(p, 'floor'); continue; }
      for (let j = 0; j < actors.length; j++) {
        const v = actors[j];
        if (v === p.owner || v.gone || v.dead || v.leaving > 0 || v.state === 'spawn' || !world.hostile(p.owner, v)) continue;
        const d = hypot2(v.pos.x - p.x, v.pos.z - p.z);
        if (d > p.radius + v.radius) continue;
        if (p.y + p.h1 < v.pos.y || p.y + p.h0 > v.pos.y + v.height) continue;
        let rec = null;
        for (let k = 0; k < p.log.length; k++) if (p.log[k].vid === v.id) { rec = p.log[k]; break; }
        if (rec && (rec.n >= p.multiMax || rec.dodged || life - rec.t < p.multiInterval - 1e-6)) continue;
        if (!rec) { rec = { vid: v.id, n: 0, t: 0, dodged: false }; p.log.push(rec); }
        rec.t = life;
        const info = { kind: 'projectile', projectile: p, x: v.pos.x - p.dirX * v.radius * 0.6, y: Math.max(v.pos.y + 0.3, Math.min(v.pos.y + v.height * 0.75, p.y + (p.ground ? 1.0 : 0))), z: v.pos.z - p.dirZ * v.radius * 0.6 };
        if (!p.ground || p.speed > 0.1) { info.dirX = p.dirX; info.dirZ = p.dirZ; }
        const res = world.resolveHit(p.owner, v, p.def, p.hit, info);
        if (res === 'dodge' || res === 'counter') { rec.dodged = true; continue; }
        rec.n++;
        if (!p.pierce && !p.ground) { expire(p, 'hit'); break; }
      }
    }
    // compact
    let w = 0;
    for (let i = 0; i < list.length; i++) if (list[i].alive) list[w++] = list[i];
    list.length = w;
  }

  function clear() {
    for (const p of list) expire(p, 'world');
    list.length = 0;
  }

  return { list, shoot, fromAttack, step, clear, expire };
}
