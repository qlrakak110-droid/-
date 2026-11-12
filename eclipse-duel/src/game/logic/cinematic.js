// Cinematic lock: when the designated hit of a move with `cinematic` connects unblocked, both fighters are locked for
// a scripted duration. Damage ticks are scheduled on the lock's own clock; the finish (launch / knockdown) releases the
// victim when the lock ends. The victim cannot be KO'd before the finish: the KO lands at the climax.
// While locked: both fighters are invulnerable and frozen, the round clock and projectiles are paused.

import { setState, endMove, launch } from './fighter.js';
import { loseHp, gainUlt } from './meters.js';
import { knockOut } from './combat.js';
import { passes, EPS } from './moves.js';

/**
 * Start the lock. `scale` multiplies tick and finish damage (combo scaling at the trigger, floored by
 * rules.cinematicScaleFloor).
 */
export function startCinematic(m, a, d, scale) {
  const c = a.moveData.cinematic;
  const L = m.rules.arenaHalfWidth;
  if (d.move) endMove(m, d, 'interrupted');
  setState(m, d, 'locked');
  d.vx = d.vy = 0; a.vx = a.vy = 0;
  d.y = 0; a.y = 0;
  d.hitstop = a.hitstop = 0;
  d.hitstopShake = a.hitstopShake = false;
  // place the victim in front of the attacker; push the pair off the wall when needed
  const dist = c.distance !== null ? c.distance : a.def.stats.pushWidth + d.def.stats.pushWidth + 0.5;
  let dx = a.x + a.facing * dist;
  const lim = L - d.def.stats.pushWidth;
  if (dx > lim) { a.x -= dx - lim; dx = lim; } else if (dx < -lim) { a.x += -lim - dx; dx = -lim; }
  d.x = dx;
  if (d.facing !== -a.facing) {
    d.facing = -a.facing;
    m.emit('turn', { fighter: d.index, facing: d.facing });
  }
  m.cinematic = { attacker: a.index, defender: d.index, move: a.move, t: 0, duration: c.duration, def: c, scale, damage: 0, ticks: 0, finished: false, stepped: false };
  m.emit('cinematicStart', { attacker: a.index, defender: d.index, move: a.move, duration: c.duration, x: a.x, facing: a.facing, victimX: d.x, victimFacing: d.facing, scale });
}

/** Advance the lock by `h` seconds. */
export function updateCinematic(m, h) {
  const cs = m.cinematic;
  const a = m.fighters[cs.attacker], d = m.fighters[cs.defender];
  const c = cs.def;
  // the first step starts just before 0 so timeline items at lock t = 0 fire too
  const t0 = cs.stepped ? cs.t : -1;
  cs.stepped = true;
  const t1 = cs.t = Math.min(cs.duration, cs.t + h);
  for (const k of c.markers) {
    if (passes(k.t, t0, t1)) m.emit('marker', { fighter: a.index, move: cs.move, name: k.name, t: k.t, data: k.data, x: a.x, y: a.y, facing: a.facing, cinematic: true });
  }
  c.ticks.forEach((tk, i) => {
    if (!passes(tk.t, t0, t1)) return;
    const dmg = Math.round(tk.damage * cs.scale);
    const lost = loseHp(m, d, dmg, 1);
    cs.damage += lost;
    cs.ticks++;
    addCombo(m, a, d, lost);
    m.emit('cinematicTick', { attacker: a.index, defender: d.index, move: cs.move, index: i, t: tk.t, damage: lost, hitstop: tk.hitstop, marker: tk.marker, data: tk.data, final: false, x: d.x, y: d.def.stats.height * 0.65 });
    if (tk.marker) m.emit('marker', { fighter: a.index, move: cs.move, name: tk.marker, t: tk.t, data: tk.data, x: a.x, y: a.y, facing: a.facing, cinematic: true });
  });
  const fin = c.finish;
  if (!cs.finished && passes(fin.t, t0, t1)) {
    cs.finished = true;
    const dmg = Math.round(fin.damage * cs.scale);
    const lost = loseHp(m, d, dmg, 0);
    cs.damage += lost;
    addCombo(m, a, d, lost);
    m.emit('cinematicTick', { attacker: a.index, defender: d.index, move: cs.move, index: c.ticks.length, t: fin.t, damage: lost, hitstop: fin.hitstop, marker: fin.marker, data: fin.data, final: true, x: d.x, y: d.def.stats.height * 0.55 });
    if (fin.marker) m.emit('marker', { fighter: a.index, move: cs.move, name: fin.marker, t: fin.t, data: fin.data, x: a.x, y: a.y, facing: a.facing, cinematic: true });
  }
  if (t1 >= cs.duration - EPS) endCinematic(m);
}

function addCombo(m, a, d, lost) {
  const r = d.recv;
  r.hits++;
  r.damage += lost;
  a.combo.hits = r.hits;
  a.combo.damage = r.damage;
  a.combo.active = true;
  gainUlt(m, d, lost * m.rules.meters.ultTake);
}

/** Release both fighters: the victim takes the finish reaction, the attacker recovers (invulnerable). */
function endCinematic(m) {
  const cs = m.cinematic;
  if (!cs) return;
  const a = m.fighters[cs.attacker], d = m.fighters[cs.defender];
  const c = cs.def, fin = c.finish;
  m.cinematic = null;
  endMove(m, a, 'cinematic');
  setState(m, a, 'recovery', c.recovery);
  a.recoveryInvuln = true;
  const ko = d.hp <= 0;
  if (!ko) {
    if (fin.level === 'launch') d.recv.juggle = Math.max(d.recv.juggle, m.rules.juggle.limit - 2);
    launch(m, d, a.facing * fin.kx, fin.ky, fin.level !== 'launch');
  }
  m.emit('cinematicEnd', { attacker: a.index, defender: d.index, move: cs.move, damage: cs.damage, ko, x: d.x });
  if (ko) knockOut(m, d, a, a.facing, true);
}
