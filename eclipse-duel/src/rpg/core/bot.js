// Autoplaying hero AI (`#rpgbot`, `__ED.rpg.bot(true)`, soak tests, captures). It plays the expedition like a careful
// player: walks the road, locks the nearest enemy, dodges or guards telegraphed attacks, punishes recoveries with the
// light chain / heavy, spends FP on skills and the gauge on the ultimate, backs off to drink the chalice.
// Deterministic: every decision draws from world.rng.

import { angDiff, fwdX, fwdZ, hypot2, rightX, rightZ, yawTo } from './math3.js';

/**
 * @param {{ skill?: number, aggression?: number }} [o] skill 0..1 (reaction quality), aggression 0..1
 */
export function botController(o = {}) {
  const skill = o.skill ?? 0.8, aggr = o.aggression ?? 0.7;
  const m = { think: 0, side: 1, sideT: 0, light: 0, wait: 0, retreat: 0, lastTarget: null, idleT: 0 };
  return {
    kind: 'bot',
    think(world, a, dt, it) {
      const rng = world.rng, flow = world.flow, cam = world.camera;
      m.light -= dt; m.wait -= dt; m.sideT -= dt; m.retreat -= dt;
      if (m.sideT <= 0) { m.sideT = rng.range(1.5, 3.5); m.side = rng.sign(); }
      if (flow && flow.resting) { flow.leave(); return; }
      // nearest hostile
      let t = null, best = 1e9;
      for (const b of world.actors) {
        if (b === a || !b.alive || b.leaving > 0 || !world.hostile(a, b) || b.team === 'neutral') continue;
        const d = a.distTo(b) - b.radius;
        const s = d + (b === m.lastTarget ? -1.5 : 0);
        if (s < best) { best = s; t = b; }
      }
      if (!t && o.dummy) for (const b of world.actors) if (b.team === 'neutral' && b.alive) { t = b; break; }
      m.lastTarget = t;
      a.target = t;
      if (cam && cam.target !== t) cam.lock(t);
      if (!t) {
        // the road: through the gate, then to the middle of the arena
        m.idleT += dt;
        if (flow && (flow.state === 'altar' || flow.state === 'explore')) {
          const g = flow.places.gate;
          const dg = hypot2(g.x - a.pos.x, g.z - a.pos.z);
          const past = a.pos.x > g.x + 1 || flow.index > 0 || dg < 0.8;
          const tx = past ? 0 : g.x, tz = past ? 0 : g.z;
          const dx = tx - a.pos.x, dz = tz - a.pos.z, d = hypot2(dx, dz);
          if (d > 1.2) { it.moveX = dx / d; it.moveZ = dz / d; }
        }
        return;
      }
      m.idleT = 0;
      const dx = t.pos.x - a.pos.x, dz = t.pos.z - a.pos.z;
      const dist = hypot2(dx, dz), d = dist - t.radius - a.radius;
      const face = yawTo(dx, dz);
      const nx = dx / (dist || 1), nz = dz / (dist || 1);
      const reach = (a.spec.reach || 1.9) + (t.radius - 0.44);
      // threats: a hostile wind-up about to land on us
      let danger = 0, dangerFrom = null;
      for (const b of world.actors) {
        if (!b.alive || !world.hostile(b, a) || !b.attack) continue;
        const inst = b.attack, def = inst.def;
        if (!def.hits.length) continue;
        const eta = def.firstActive - inst.t;
        if (eta > 0.36 || inst.t > def.lastActive) continue;
        const bd = a.distTo(b) - b.radius - a.radius;
        const rr = def.hits[0].shape.r1 ?? def.hits[0].shape.f1 ?? 2.5;
        if (bd > rr + 0.6) continue;
        if (Math.abs(angDiff(b.yaw, yawTo(a.pos.x - b.pos.x, a.pos.z - b.pos.z))) > 1.5 && (def.hits[0].shape.a1 === undefined || def.hits[0].shape.a1 - def.hits[0].shape.a0 < 5)) continue;
        if (eta < 0.3 && (danger === 0 || eta < danger)) { danger = Math.max(0.01, eta); dangerFrom = b; }
      }
      const free = a.state === 'idle' || a.state === 'move' || a.state === 'guard';
      if (danger > 0 && (free || (a.state === 'attack' && a.attack && a.attack.t >= a.attack.def.lastActive + 0.14))) {
        if (rng() < skill) {
          if (!a.exhausted && a.stamina > a.roll.cost && danger < 0.2) {
            // roll through / around the blow
            const side = m.side;
            const fy = yawTo(a.pos.x - dangerFrom.pos.x, a.pos.z - dangerFrom.pos.z);
            const mix = dangerFrom.scale > 1.5 ? 0.2 : 0.75;
            it.moveX = fwdX(fy) * (1 - mix) + rightX(fy) * side * mix; it.moveZ = fwdZ(fy) * (1 - mix) + rightZ(fy) * side * mix;
            it.roll = true;
            m.wait = 0.25;
            return;
          }
          if (a.guard && !a.exhausted && a.stamina > 20) { it.guard = true; it.face = yawTo(dangerFrom.pos.x - a.pos.x, dangerFrom.pos.z - a.pos.z); return; }
        }
      }
      if (a.state === 'guard' && danger === 0) it.guard = false;
      // heal when it is safe enough
      const low = a.hp < a.hpMax * 0.42;
      if (low && a.chalice > 0 && free) {
        if (d > 4.2 || (t.state !== 'attack' && d > 2.6 && rng() < 0.04)) { it.drink = true; return; }
        m.retreat = 0.6;
      }
      if (m.retreat > 0 && free) {
        it.moveX = -nx; it.moveZ = -nz; it.sprint = d < 4 && !a.exhausted;
        if (d < 2 && !a.exhausted && a.stamina > a.roll.cost && rng() < 0.08) it.roll = true;
        return;
      }
      if (a.state === 'drink') { it.moveX = -nx * 0.6; it.moveZ = -nz * 0.6; return; }
      // offense
      const tired = a.exhausted || a.stamina < 18;
      const targetOpen = t.state === 'flinch' || t.state === 'stagger' || t.state === 'guardhit' || t.state === 'idle' || t.state === 'move' || t.state === 'attack' || t.state === 'spawn' || t.team === 'neutral';
      if (m.wait <= 0 && !tired && targetOpen && t.state !== 'down' && t.state !== 'getup') {
        const slots = a.spec.slots, atk = a.spec.attacks;
        const cdOk = (slot) => { const id = slots[slot]; const df = id && atk[id]; return df && (a.cd[df.cooldownKey] || 0) <= 0 && a.fp >= df.fp; };
        if (a.ult >= a.ultMax && a.ultMax > 0 && d < 3.2 && free && rng() < 0.35) { it.attack = 'ult'; m.wait = 0.4; return; }
        if (free && rng() < 0.03 * (0.5 + aggr)) {
          if (d > 3 && d < 9 && cdOk('skill1')) { it.attack = 'skill1'; m.wait = 0.5; return; }
          if (d < 5.5 && cdOk('skill2')) { it.attack = 'skill2'; m.wait = 0.6; return; }
          if (d < 4.5 && d > 1.2 && cdOk('skill3') && a.spec.hero !== 'kael') { it.attack = 'skill3'; m.wait = 0.6; return; }
        }
        if (d < reach) {
          if (a.state === 'attack') { if (m.light <= 0) { it.attack = 'light'; m.light = 0.14; } }
          else if (rng() < 0.12 * aggr && a.stamina > 45 && t.state !== 'attack') { it.attack = 'heavy'; m.wait = 0.3; }
          else if (m.light <= 0) { it.attack = 'light'; m.light = 0.16; }
          it.face = face;
          return;
        }
      }
      // spacing
      if (free) {
        if (tired) {
          // breathe: keep away, circle
          it.moveX = -nx * 0.5 + rightX(face) * m.side * 0.8; it.moveZ = -nz * 0.5 + rightZ(face) * m.side * 0.8;
          if (d > 6) { it.moveX = 0; it.moveZ = 0; }
        } else if (d > reach - 0.25) {
          it.moveX = nx; it.moveZ = nz;
          it.sprint = d > 8;
        } else if (d < 0.5) { it.moveX = -nx; it.moveZ = -nz; }
      }
    },
  };
}
