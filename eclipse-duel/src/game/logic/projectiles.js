// Projectiles: spawned by moves at their timeline time, travel along X (and Y), clash with enemy projectiles and hit
// the owner's opponent. A projectile freezes during its own hit-stop; its owner does not (the owner keeps acting).

import { worldBox, overlaps } from './moves.js';

const tmpA = [0, 0, 0, 0], tmpB = [0, 0, 0, 0];

/**
 * Spawn a projectile described by a compiled spec (move.projectiles[i]).
 * @returns {object} the projectile (also pushed to m.projectiles)
 */
export function spawnProjectile(m, f, spec, mv) {
  const o = m.fighters[1 - f.index];
  const facing = f.facing;
  const baseX = spec.at === 'opponent' ? o.x : f.x;
  const baseY = spec.at === 'opponent' ? 0 : f.y;
  const L = m.rules.arenaHalfWidth;
  const p = {
    id: m.nextProjectileId++,
    owner: f.index,
    kind: spec.kind,
    move: mv.id,
    x: Math.max(-L, Math.min(L, baseX + facing * spec.of)),
    y: baseY + spec.ou,
    vx: spec.vx * facing,
    vy: spec.vy,
    facing,
    age: 0,
    delay: spec.delay,
    life: spec.lifetime,
    active: spec.delay <= 0,
    hits: 0,
    lastHit: -Infinity,
    durability: spec.durability,
    hitstop: 0,
    alive: true,
    data: spec.data,
    spec,
  };
  m.projectiles.push(p);
  m.emit('projectileSpawn', {
    id: p.id, owner: p.owner, kind: p.kind, move: p.move, x: p.x, y: p.y, vx: p.vx, vy: p.vy, facing,
    delay: p.delay, lifetime: p.life, data: p.data,
  });
  return p;
}

/** World AABB of a projectile into `out`. */
export function projectileBox(p, out) {
  const s = p.spec;
  return worldBox(p.x, p.y, p.facing, s.f0, s.f1, s.u0, s.u1, out);
}

/** Remove a projectile and emit 'projectileExpire'. */
export function expireProjectile(m, p, reason) {
  if (!p.alive) return;
  p.alive = false;
  m.emit('projectileExpire', { id: p.id, owner: p.owner, kind: p.kind, x: p.x, y: p.y, reason });
}

/** Expire every projectile (round end, reset). */
export function clearProjectiles(m, reason) {
  for (const p of m.projectiles) expireProjectile(m, p, reason);
  m.projectiles.length = 0;
}

/** Drop dead projectiles from the list (in place, order preserved). */
export function compactProjectiles(m) {
  const a = m.projectiles;
  let w = 0;
  for (let i = 0; i < a.length; i++) if (a[i].alive) a[w++] = a[i];
  a.length = w;
}

/** Move, age, expire and clash every projectile for one substep. */
export function updateProjectiles(m, h) {
  const L = m.rules.arenaHalfWidth;
  const list = m.projectiles;
  const moveEvents = m.events.has('projectileMove');
  for (const p of list) {
    if (!p.alive) continue;
    if (p.hitstop > 0) { p.hitstop = Math.max(0, p.hitstop - h); continue; }
    p.age += h;
    if (!p.active) {
      if (p.age < p.delay) continue;
      p.active = true;
      m.emit('projectileActive', { id: p.id, owner: p.owner, kind: p.kind, x: p.x, y: p.y });
    }
    if (p.spec.gravity) p.vy -= p.spec.gravity * h;
    p.x += p.vx * h;
    p.y += p.vy * h;
    if (moveEvents) m.emit('projectileMove', { id: p.id, x: p.x, y: p.y, vx: p.vx, vy: p.vy });
    if (p.age >= p.delay + p.life) expireProjectile(m, p, 'lifetime');
    else if (Math.abs(p.x) > L + 1.5) expireProjectile(m, p, 'bounds');
    else if (p.y < -0.5) expireProjectile(m, p, 'ground');
  }
  // clashes between enemy projectiles
  for (let i = 0; i < list.length; i++) {
    const a = list[i];
    if (!a.alive || !a.active || !a.spec.clash) continue;
    for (let j = i + 1; j < list.length; j++) {
      const b = list[j];
      if (!b.alive || !b.active || !b.spec.clash || b.owner === a.owner) continue;
      if (!overlaps(projectileBox(a, tmpA), projectileBox(b, tmpB))) continue;
      const da = a.durability, db = b.durability;
      a.durability -= db;
      b.durability -= da;
      m.emit('projectileClash', {
        a: a.id, b: b.id, owners: [a.owner, b.owner], x: (a.x + b.x) * 0.5, y: (a.y + b.y) * 0.5,
        survivor: a.durability > 0 ? a.id : b.durability > 0 ? b.id : null,
      });
      if (a.durability <= 0) expireProjectile(m, a, 'clash');
      if (b.durability <= 0) expireProjectile(m, b, 'clash');
      if (!a.alive) break;
    }
  }
}

/**
 * Collect projectile-vs-fighter contacts for this substep into `out` (resolved by combat.js).
 * Each entry: {kind: 'projectile', projectile, attacker, defender, hit, cx, cy}
 */
export function collectProjectileHits(m, out) {
  for (const p of m.projectiles) {
    if (!p.alive || !p.active || p.hitstop > 0) continue;
    const s = p.spec;
    if (p.hits >= s.multiMax) continue;
    if (p.hits > 0 && p.age - p.lastHit < s.multiInterval - 1e-9) continue;
    const d = m.fighters[1 - p.owner];
    const box = projectileBox(p, tmpA);
    const c = m.hurtContact(d, box);
    if (!c) continue;
    out.push({ kind: 'projectile', projectile: p, attacker: m.fighters[p.owner], defender: d, hit: s.hit, move: null, cx: c.x, cy: c.y });
  }
}
