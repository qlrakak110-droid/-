// Frame data derived from move data: startup, active, recovery, reach, damage and advantage on hit / block.
// Works on author moves (def.moves.x) and on compiled moves alike; times in seconds, `frames` at 60 fps.

import { compileMove, compileFighterDef } from './defs.js';
import { forwardAt } from './moves.js';
import { DEFAULT_RULES } from './constants.js';

const FPS = 60;

/**
 * Derive frame data for one move.
 * @param {object} move author or compiled move
 * @param {{id?: string, rules?: object}} [opts]
 * @returns {{id, name, group, startup, activeEnd, active, recovery, duration, damage, hits, reach, level,
 *   onHit, onBlock, knockdown, cancellable, armour, invuln, projectile, frames: object}}
 *   startup   first active time (s)  (projectile moves: release time + delay)
 *   activeEnd end of the last hit window
 *   active    total active time (union of hit windows)
 *   recovery  duration - activeEnd
 *   reach     furthest forward point any hit box reaches (m, from the start position, including motion);
 *             projectiles: their travel distance
 *   onHit / onBlock  advantage (s) of the attacker after the LAST hit connects at its first active moment:
 *             victim stun - attacker time left in the move (+ = attacker acts first). null for knockdowns / launches.
 */
export function deriveFrameData(move, { id, rules = DEFAULT_RULES } = {}) {
  const mv = move.compiled ? move : compileMove(id || 'move', move, rules);
  const hits = mv.hits;
  let damage = 0, nh = 0, reach = 0;
  for (const h of hits) {
    damage += h.damage * h.multiMax;
    nh += h.multiMax;
    reach = Math.max(reach, forwardAt(mv, h.t1) + h.f1, forwardAt(mv, h.t0) + h.f1);
  }
  let projReach = 0;
  for (const p of mv.projectiles) {
    damage += p.hit.damage * p.multiMax;
    nh += p.multiMax;
    projReach = Math.max(projReach, forwardAt(mv, p.t) + p.of + p.f1 + Math.abs(p.vx) * p.lifetime);
  }
  const startup = Number.isFinite(mv.firstActive) ? mv.firstActive : null;
  const activeEnd = hits.length ? Math.max(...hits.map((h) => h.t1)) : (mv.projectiles.length ? Math.max(...mv.projectiles.map((p) => p.t + p.delay)) : null);
  // union of hit windows
  const wins = hits.map((h) => [h.t0, h.t1]).sort((a, b) => a[0] - b[0]);
  let active = 0, cur = null;
  for (const w of wins) {
    if (!cur || w[0] > cur[1]) { if (cur) active += cur[1] - cur[0]; cur = w.slice(); } else cur[1] = Math.max(cur[1], w[1]);
  }
  if (cur) active += cur[1] - cur[0];
  // advantage from the last hit (strike or projectile released at point blank)
  let last = null, lastT = -1;
  for (const h of hits) if (h.t0 + (h.multiMax - 1) * h.multiInterval >= lastT) { last = h; lastT = h.t0 + (h.multiMax - 1) * h.multiInterval; }
  for (const p of mv.projectiles) if (p.t + p.delay >= lastT) { last = p.hit; lastT = p.t + p.delay; }
  let onHit = null, onBlock = null;
  if (last) {
    const left = mv.duration - lastT;
    onBlock = last.unblockable ? null : last.blockstun - left;
    onHit = last.level === 'light' || last.level === 'heavy' || last.level === 'crumple' ? last.hitstun - left : null;
  }
  const cancellable = mv.cancels.some((c) => c.onHit || c.onContact || c.groups.size > 0);
  const fr = (s) => (s === null ? null : Math.round(s * FPS));
  const out = {
    id: mv.id,
    name: mv.name,
    group: mv.group,
    startup,
    activeEnd,
    active,
    recovery: activeEnd === null ? null : Math.max(0, mv.duration - activeEnd),
    duration: mv.duration,
    damage,
    hits: nh,
    reach: Math.max(reach, projReach),
    strikeReach: reach,
    projectile: mv.projectiles.length > 0,
    level: last ? last.level : null,
    unblockable: hits.some((h) => h.unblockable) || mv.projectiles.some((p) => p.hit.unblockable),
    onHit,
    onBlock,
    knockdown: last ? last.level === 'knockdown' || last.level === 'launch' : false,
    cancellable,
    armour: mv.armour.length > 0,
    invuln: mv.invuln.length > 0,
    counter: !!mv.counter,
    cinematic: !!mv.cinematic,
    fpCost: mv.fpCost,
    ultCost: mv.ultCost,
    cooldown: mv.cooldown,
    motion: mv.motion ? forwardAt(mv, mv.duration) : 0,
  };
  out.frames = {
    startup: fr(out.startup), active: fr(out.active), recovery: fr(out.recovery), duration: fr(out.duration),
    onHit: fr(out.onHit), onBlock: fr(out.onBlock),
  };
  return out;
}

/** Frame data for every move of a fighter definition (author or compiled), keyed by move id. */
export function fighterFrameData(def, rules = DEFAULT_RULES) {
  const cdef = def.source ? def : compileFighterDef(def, rules);
  const out = {};
  for (const id of Object.keys(cdef.moves)) out[id] = deriveFrameData(cdef.moves[id], { rules });
  return out;
}

/**
 * Printable frame-data table of a fighter definition.
 * @param {object} def author or compiled definition
 * @param {{unit?: 'frames'|'seconds', rules?: object}} [opts]
 * @returns {string}
 */
export function frameDataTable(def, { unit = 'frames', rules = DEFAULT_RULES } = {}) {
  const cdef = def.source ? def : compileFighterDef(def, rules);
  const fd = fighterFrameData(cdef, rules);
  const slotOf = {};
  for (const [k, id] of Object.entries(cdef.commands)) slotOf[id] = slotOf[id] ? slotOf[id] + ',' + k : k;
  const T = (s) => (s === null || s === undefined ? '-' : unit === 'frames' ? String(Math.round(s * FPS)) : s.toFixed(3));
  const A = (s, kd) => (s === null ? (kd ? 'KD' : '-') : (s >= 0 ? '+' : '') + (unit === 'frames' ? Math.round(s * FPS) : s.toFixed(3)));
  const head = ['move', 'slot', 'startup', 'active', 'recov', 'total', 'dmg', 'hits', 'reach', 'onHit', 'onBlock', 'level', 'cost', 'cd', 'notes'];
  const rows = [head];
  for (const id of Object.keys(fd)) {
    const d = fd[id];
    const notes = [d.projectile && 'proj', d.armour && 'armour', d.invuln && 'invuln', d.counter && 'counter', d.cinematic && 'cinematic', d.unblockable && 'unblockable', d.cancellable && 'cancel', d.motion ? `moves ${d.motion.toFixed(1)}m` : ''].filter(Boolean).join(' ');
    rows.push([
      id, slotOf[id] || '(route)', T(d.startup), T(d.active), T(d.recovery), T(d.duration), String(Math.round(d.damage)), String(d.hits),
      d.reach.toFixed(2), A(d.onHit, d.knockdown), A(d.onBlock, false), d.level || '-',
      d.ultCost ? `ULT ${d.ultCost}` : d.fpCost ? `FP ${d.fpCost}` : '-', d.cooldown ? d.cooldown + 's' : '-', notes,
    ]);
  }
  const w = head.map((_, c) => Math.max(...rows.map((r) => r[c].length)));
  const line = (r) => r.map((v, c) => (c < 2 || c >= 11 ? v.padEnd(w[c]) : v.padStart(w[c]))).join('  ');
  const unitNote = unit === 'frames' ? 'times in frames @60fps' : 'times in seconds';
  return `${cdef.name} (${cdef.id}) - ${unitNote}; reach in metres from the start position; advantage measured from the last hit\n` +
    line(rows[0]) + '\n' + w.map((n) => '-'.repeat(n)).join('  ') + '\n' + rows.slice(1).map(line).join('\n');
}
