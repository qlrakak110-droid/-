// Hit detection and resolution: hurtboxes, strike collection, blocking / perfect guard / guard break, armour,
// counter stances, clean hits (combo scaling, hitstun decay, juggles, counter hits), hit-stop and KO.

import { worldBox, overlaps, contactPoint, crosses, windowAt, EPS } from './moves.js';
import { setState, endMove, startMove, launch, isInvulnerable, faceOpponent } from './fighter.js';
import { loseHp, gainUlt, gainFp, drainGuard } from './meters.js';
import { expireProjectile } from './projectiles.js';
import { startCinematic } from './cinematic.js';

const MAX_HURT = 8;
const hurt = [];
for (let i = 0; i < MAX_HURT; i++) hurt.push([0, 0, 0, 0]);
const hitBox = [0, 0, 0, 0];
const contact = { x: 0, y: 0 };

/** How long an attack's limb stays vulnerable after its hit window (whiff-punish window), seconds. */
export const HURT_EXTEND_AFTER = 0.12;

/**
 * Fill the module hurtbox list with fighter `f`'s world hurtboxes. Returns the count.
 * Standing: x +- hurtWidth, feet to head. Airborne victims: a lower, wider body. Attacks add their own `hurt` boxes
 * and, for hits with hurtExtend, the attacking limb from its active start until HURT_EXTEND_AFTER after it.
 */
export function hurtboxes(f) {
  const s = f.def.stats;
  let n = 0;
  const b0 = hurt[n++];
  if (f.state === 'launched') { b0[0] = f.x - 0.55; b0[1] = f.x + 0.55; b0[2] = f.y + 0.1; b0[3] = f.y + 1.35; }
  else if (f.state === 'knockdown' || f.state === 'ko') { b0[0] = f.x - 0.9; b0[1] = f.x + 0.9; b0[2] = 0; b0[3] = 0.45; }
  else { b0[0] = f.x - s.hurtWidth; b0[1] = f.x + s.hurtWidth; b0[2] = f.y; b0[3] = f.y + s.height; }
  if (f.state === 'attack') {
    const mv = f.moveData, t = f.moveTime;
    for (const w of mv.hurt) {
      if (n >= MAX_HURT) break;
      if (t >= w.t0 - EPS && t <= w.t1 + EPS) worldBox(f.x, f.y, f.facing, w.f0, w.f1, w.u0, w.u1, hurt[n++]);
    }
    for (const ht of mv.hits) {
      if (n >= MAX_HURT) break;
      if (!ht.hurtExtend || t < ht.t0 - EPS || t > ht.t1 + HURT_EXTEND_AFTER) continue;
      const reach = ht.f0 + (ht.f1 - ht.f0) * 0.7;
      if (reach > s.hurtWidth) worldBox(f.x, f.y, f.facing, s.hurtWidth * 0.5, reach, ht.u0, ht.u1, hurt[n++]);
    }
  }
  return n;
}

/**
 * Debug-overlay data of fighter `f` (training mode hitbox viewer): world AABBs [x0, x1, y0, y1] of its hurtboxes,
 * of the hit boxes active at its current move time, and of its push-box. Allocates: debug use only.
 */
export function debugBoxes(f) {
  const n = hurtboxes(f);
  const pw = f.def.stats.pushWidth;
  const out = { hurt: [], hit: [], push: [f.x - pw, f.x + pw, f.y, f.y + f.def.stats.height] };
  for (let i = 0; i < n; i++) out.hurt.push(hurt[i].slice());
  if (f.state === 'attack') {
    for (const ht of f.moveData.hits) {
      if (f.moveTime >= ht.t0 - EPS && f.moveTime <= ht.t1 + EPS) out.hit.push(worldBox(f.x, f.y, f.facing, ht.f0, ht.f1, ht.u0, ht.u1, [0, 0, 0, 0]));
    }
  }
  return out;
}

/** Contact point between a world box and fighter `d`'s hurtboxes, or null. (Reused object.) */
export function hurtContact(d, box) {
  const n = hurtboxes(d);
  for (let i = 0; i < n; i++) if (overlaps(box, hurt[i])) return contactPoint(box, hurt[i], contact);
  return null;
}

/** Collect the strike of attacker `f` on its opponent this substep (at most one hit index per substep). */
export function collectStrikes(m, f, out) {
  if (f.state !== 'attack' || !f._moveAdvanced) return;
  const d = m.fighters[1 - f.index];
  const mv = f.moveData, tP = f.movePrevTime, tN = f.moveTime;
  for (const ht of mv.hits) {
    if (!crosses(ht.t0, ht.t1, tP, tN)) continue;
    const i = ht.index;
    if (f.hitCounts[i] >= ht.multiMax) continue;
    if (f.hitCounts[i] > 0 && tN - f.hitLast[i] < ht.multiInterval - EPS) continue;
    worldBox(f.x, f.y, f.facing, ht.f0, ht.f1, ht.u0, ht.u1, hitBox);
    const c = hurtContact(d, hitBox);
    if (!c) continue;
    out.push({ kind: 'strike', projectile: null, attacker: f, defender: d, hit: ht, move: mv, cx: c.x, cy: c.y });
    return;
  }
}

function freeze(f, s, shake) {
  if (s > f.hitstop) f.hitstop = s;
  f.hitstopShake = shake;
}

const airborneNow = (d) => d.state === 'launched' || d.y > 0.05;

/**
 * Resolve one contact. Returns 'whiff' (passed through: invulnerable / wrong height; not consumed), 'countered',
 * 'blocked', 'armoured' or 'hit'.
 */
export function resolveContact(m, c) {
  const { attacker: a, defender: d, hit } = c;
  const proj = c.projectile;
  const kind = c.kind;
  if (isInvulnerable(m, d, kind)) {
    if (d.state === 'dodge' && !d.perfectDodged) {
      d.perfectDodged = true;
      m.emit('perfectDodge', { fighter: d.index, attacker: a.index, move: proj ? proj.move : c.move.id, projectile: proj ? proj.id : null, x: d.x });
    }
    return 'whiff';
  }
  const air = airborneNow(d);
  if (air ? !hit.air : !hit.ground) return 'whiff';
  const dirX = proj ? (proj.vx ? Math.sign(proj.vx) : proj.facing) : a.facing;
  const srcX = proj ? proj.x : a.x;
  const moveId = proj ? proj.move : c.move.id;
  const group = a.def.moves[moveId] ? a.def.moves[moveId].group : 'normal';

  // counter stance
  if (d.state === 'attack' && d.moveData.counter && !hit.unblockable && !hit.cinematic) {
    const ct = d.moveData.counter;
    if (d.moveTime >= ct.t0 && d.moveTime <= ct.t1 && (ct.vs === 'all' || ct.vs === kind)) {
      m.emit('counter', { fighter: d.index, attacker: a.index, move: d.move, into: ct.move, against: moveId, projectile: proj ? proj.id : null, x: d.x, y: d.y });
      freeze(d, ct.hitstop, false);
      if (!proj) freeze(a, ct.hitstop, true);
      else expireProjectile(m, proj, 'countered');
      startMove(m, d, ct.move, { cancelFrom: d.move, forced: true });
      faceOpponent(m, d);
      return 'countered';
    }
  }

  // guard
  const front = proj
    ? (proj.vx ? proj.vx * d.facing < 0 : (srcX - d.x) * d.facing >= -0.15)
    : (srcX - d.x) * d.facing >= -0.15;
  if ((d.state === 'guard' || d.state === 'blockstun') && !air && front && !hit.unblockable) {
    block(m, c, dirX, moveId, group);
    return 'blocked';
  }

  // armour
  const arm = d.state === 'attack' ? windowAt(d.moveData.armour, d.moveTime) : null;
  if (arm && !hit.armourPierce && !hit.cinematic && d.armourUsed < arm.hits) {
    d.armourUsed++;
    const dmg = Math.max(hit.damage > 0 ? 1 : 0, Math.round(hit.damage * arm.damageScale));
    loseHp(m, d, dmg);
    const hs = hit.hitstop * 0.8;
    freeze(d, hs, true);
    if (proj) proj.hitstop = hs; else { freeze(a, hs, false); a.moveConnected = true; }
    gainUlt(m, d, dmg * m.rules.meters.ultTake);
    if (group !== 'ult') gainUlt(m, a, dmg * m.rules.meters.ultDeal);
    m.emit('hit', hitPayload(m, c, moveId, { damage: dmg, blocked: false, armoured: true, level: hit.level, hitstop: hs }));
    if (d.hp <= 0) knockOut(m, d, a, dirX);
    return 'armoured';
  }

  clean(m, c, dirX, moveId, group, air);
  return 'hit';
}

function hitPayload(m, c, moveId, extra) {
  const d = c.defender;
  return {
    attacker: c.attacker.index, defender: d.index, kind: c.kind, move: moveId, hit: c.hit.index,
    projectile: c.projectile ? c.projectile.id : null, label: c.hit.label,
    damage: 0, chip: 0, blocked: false, perfect: false, armoured: false, counter: false, punish: false,
    unblockable: c.hit.unblockable, guardBreak: false, cinematic: false, ko: false,
    level: c.hit.level, x: c.cx, y: c.cy, facing: c.attacker.facing,
    combo: d.recv.active ? d.recv.hits : 0, comboDamage: d.recv.active ? d.recv.damage : 0, scaling: d.recv.active ? d.recv.scale : 1,
    juggle: d.recv.juggle, hitstop: 0, guard: d.guard,
    ...extra,
  };
}

function block(m, c, dirX, moveId, group) {
  const { attacker: a, defender: d, hit } = c;
  const R = m.rules, B = R.block;
  const proj = c.projectile;
  const perfect = m.time - d.input.guardPressedAt <= B.perfectWindow;
  const chip = perfect ? 0 : hit.chip;
  const gd = perfect ? 0 : hit.guardDamage;
  const lost = loseHp(m, d, chip, B.chipCanKO ? 0 : 1);
  const broke = drainGuard(m, d, gd);
  let hs = hit.hitstop * B.hitstopScale;
  if (broke) {
    hs *= 1.6;
    if (d.move) endMove(m, d, 'interrupted');
    setState(m, d, 'guardbreak', R.guardBreakTime);
    d.vx = dirX * 2.5;
    d.slideFrom = proj ? -1 : a.index;
    m.emit('guardBreak', { fighter: d.index, attacker: a.index, move: moveId, x: d.x, y: c.cy });
  } else {
    setState(m, d, 'blockstun', perfect ? hit.blockstun * B.perfectStunScale : hit.blockstun);
    d.vx = dirX * hit.kx * B.pushbackScale * (perfect ? 0.5 : 1) / d.def.stats.weight;
    d.slideFrom = proj ? -1 : a.index;
  }
  freeze(d, hs, true);
  if (proj) proj.hitstop = hs; else { freeze(a, hs, false); a.moveConnected = true; }
  const M = R.meters;
  gainUlt(m, d, (lost + gd) * M.ultBlockTake);
  if (group !== 'ult') gainUlt(m, a, (lost + gd) * M.ultBlockDeal);
  m.emit('hit', hitPayload(m, c, moveId, { damage: lost, chip: lost, blocked: true, perfect, guardBreak: broke, hitstop: hs }));
  m.emit('guard', { fighter: d.index, attacker: a.index, move: moveId, perfect, chip: lost, gauge: d.guard, guardBreak: broke, x: c.cx, y: c.cy });
  if (d.hp <= 0) knockOut(m, d, a, dirX);
}

function clean(m, c, dirX, moveId, group, air) {
  const { attacker: a, defender: d, hit } = c;
  const R = m.rules, C = R.combo;
  const proj = c.projectile;
  const r = d.recv;
  if (!r.active || r.attacker !== a.index) {
    r.active = true; r.hits = 0; r.damage = 0; r.juggle = 0; r.time = 0; r.scale = 1; r.wallBounces = 0; r.attacker = a.index; r.crumpled = false;
  }
  r.hits++;
  if (r.hits > C.fullHits) r.scale = Math.max(C.floor, r.scale - (hit.scaleStep !== null ? hit.scaleStep : C.step));
  const inMove = d.state === 'attack';
  const counter = inMove && d.moveTime <= d.moveData.lastActive;
  const punish = !counter && (inMove || d.state === 'guardbreak' || d.state === 'recovery' || d.state === 'dash' || d.state === 'backstep' || (d.state === 'dodge'));
  const CH = R.counterHit;
  let dmg = hit.damage * r.scale * (counter ? CH.damage : 1);
  dmg = Math.max(hit.damage > 0 ? 1 : 0, Math.round(dmg));
  const trigger = !proj && hit.cinematic && c.move.cinematic;
  const lost = loseHp(m, d, dmg, trigger ? 1 : 0);
  r.damage += lost;
  a.combo.hits = r.hits; a.combo.damage = r.damage; a.combo.active = true;
  if (d.move) endMove(m, d, 'interrupted');

  const M = R.meters;
  gainUlt(m, d, lost * M.ultTake);
  if (group !== 'ult') gainUlt(m, a, lost * M.ultDeal);
  gainFp(m, a, M.fpOnHit);

  let hs = hit.hitstop * (counter ? CH.hitstop : 1);
  let level = hit.level;
  if (trigger) {
    m.emit('hit', hitPayload(m, c, moveId, { damage: lost, counter, punish, level, hitstop: hs, cinematic: true }));
    a.moveConnected = a.moveHit = true;
    startCinematic(m, a, d, Math.max(R.cinematicScaleFloor, r.scale));
    return;
  }

  // reaction
  if (r.hits > C.maxHits || r.time > C.maxTime) level = 'knockdown';
  if (level === 'crumple' && (r.crumpled || air)) level = air ? 'heavy' : 'knockdown';
  let k = Math.max(C.hitstunFloor, 1 - C.hitstunStep * (r.hits - 1));
  if (r.time > C.hitstunTime) k *= Math.max(0.3, 1 - C.hitstunTimeRate * (r.time - C.hitstunTime));
  if (counter) k *= CH.hitstun;
  const w = d.def.stats.weight;
  d.slideFrom = -1;
  if (level === 'knockdown') {
    launch(m, d, dirX * hit.kx / w, Math.max(2, hit.ky) / w, true);
  } else if (level === 'launch') {
    r.juggle += air ? hit.juggle : 1;
    launch(m, d, dirX * hit.kx / w, hit.ky / w, false);
  } else if (air) {
    r.juggle += hit.juggle;
    launch(m, d, dirX * hit.kx * 0.5 / w, Math.max(hit.ky, R.juggle.pop) / w, false);
  } else if (level === 'crumple') {
    r.crumpled = true;
    r.juggle += 1;
    setState(m, d, 'hitstun', hit.hitstun * k);
    d.stunKind = 'crumple';
    d.vx = dirX * hit.kx / w;
  } else {
    setState(m, d, 'hitstun', hit.hitstun * k);
    d.stunKind = level;
    d.vx = dirX * hit.kx / w;
    d.slideFrom = proj ? -1 : a.index;
  }
  freeze(d, hs, true);
  if (proj) proj.hitstop = hs;
  else { freeze(a, hs, false); a.moveConnected = a.moveHit = true; }
  const ko = d.hp <= 0;
  m.emit('hit', hitPayload(m, c, moveId, { damage: lost, counter, punish, level, hitstop: hs, ko }));
  if (ko) knockOut(m, d, a, dirX);
}

/** KO: the loser flies (hard knockdown flight) and stays down. */
export function knockOut(m, d, a, dirX, cinematic = false) {
  if (d.koFall || d.state === 'ko') return;
  d.hp = 0;
  if (d.move) endMove(m, d, 'interrupted');
  d.koFall = true;
  launch(m, d, dirX * Math.max(3.5, Math.abs(d.vx)), Math.max(5, d.vy), true);
  d.koFall = true;
  m.koQueue.push(d.index);
  m.emit('ko', { fighter: d.index, by: a.index, x: d.x, y: d.y, cinematic });
}

/**
 * Resolve every contact collected this substep. Cinematic triggers resolve first; once a cinematic starts, the
 * remaining contacts of the substep are dropped (both fighters are locked).
 */
export function resolveContacts(m, list) {
  if (list.length > 1) list.sort((x, y) => (y.hit.cinematic ? 1 : 0) - (x.hit.cinematic ? 1 : 0));
  for (const c of list) {
    if (m.cinematic) break;
    const res = resolveContact(m, c);
    if (res === 'whiff') continue;
    if (c.kind === 'strike') {
      const a = c.attacker;
      a.hitCounts[c.hit.index]++;
      a.hitLast[c.hit.index] = a.moveTime;
      if (res === 'countered') a.hitCounts[c.hit.index] = c.hit.multiMax;
    } else {
      const p = c.projectile;
      if (!p.alive) continue;
      p.hits++;
      p.lastHit = p.age;
      if (p.hits >= p.spec.multiMax && !p.spec.pierce) expireProjectile(m, p, 'hit');
      m.emit('projectileHit', { id: p.id, owner: p.owner, defender: c.defender.index, result: res, x: c.cx, y: c.cy });
    }
  }
  list.length = 0;
}
