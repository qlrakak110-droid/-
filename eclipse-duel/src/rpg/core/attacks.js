// Attack definitions of the RPG mode (README §6): the normaliser every kind's attacks go through, and the converter
// that turns a compiled move of src/fighters/<id>/moves.js into an RPG attack (3D hit volumes derived from its boxes).

import { DEG } from './math3.js';

/** Poise damage, knockback (m/s forward / up), hit-stop and stun seconds per hit level. */
export const LEVELS = {
  light: { poise: 14, kf: 2.2, ku: 0, hitstop: 0.055, stun: 0.34 },
  heavy: { poise: 34, kf: 3.6, ku: 0, hitstop: 0.1, stun: 0.62 },
  launch: { poise: 45, kf: 1.4, ku: 7.2, hitstop: 0.11, stun: 0 },
  crumple: { poise: 45, kf: 1.0, ku: 0, hitstop: 0.12, stun: 0.95 },
  knockdown: { poise: 60, kf: 4.4, ku: 3.2, hitstop: 0.12, stun: 0 },
};

const win = (w) => (Array.isArray(w) ? { t0: w[0], t1: w[1] } : { t0: w.t ? w.t[0] : w.t0, t1: w.t ? w.t[1] : w.t1, hits: w.hits });

/** Normalise one hit shape (README §6.2). Angles are stored in radians. */
export function normalizeShape(s) {
  if (!s) return { norm: true, type: 'arc', r0: 0, r1: 1.6, a0: -60 * DEG, a1: 60 * DEG, u0: 0, u1: 2 };
  if (s.norm) return s;
  const u = s.u || [0, 2.2];
  switch (s.type) {
    case 'box': return { norm: true, type: 'box', f0: s.f[0], f1: s.f[1], s0: s.s ? s.s[0] : -0.5, s1: s.s ? s.s[1] : 0.5, u0: u[0], u1: u[1] };
    case 'sphere': return { norm: true, type: 'sphere', at: s.at || [0, 1, 0], socket: s.socket || null, r: s.r ?? 0.6 };
    case 'capsule': return { norm: true, type: 'capsule', a: s.a, b: s.b, r: s.r ?? 0.4 };
    case 'ring': return { norm: true, type: 'ring', at: s.at || [0, 0, 0], r0: s.r[0], r1: s.r[1], g0: s.grow ? s.grow[0] : 0, g1: s.grow ? s.grow[1] : 0, u0: s.u ? u[0] : 0, u1: s.u ? u[1] : 0.9 };
    default: {
      const a = s.angle || [-60, 60], r = s.r || [0, 1.8];
      return { norm: true, type: 'arc', r0: r[0], r1: r[1], a0: a[0] * DEG, a1: a[1] * DEG, u0: u[0], u1: u[1] };
    }
  }
}

function normalizeHit(h, i, group) {
  const level = h.level || 'light';
  const L = LEVELS[level] || LEVELS.light;
  const t = h.t || [h.t0 || 0, h.t1 || 0];
  const damage = h.damage || 0;
  return {
    index: i, label: h.label || h.id || null,
    t0: t[0], t1: t[1],
    shape: normalizeShape(h.shape),
    damage,
    poise: h.poise ?? L.poise,
    level,
    kf: h.knock && h.knock.f !== undefined ? h.knock.f : L.kf,
    ku: h.knock && h.knock.u !== undefined ? h.knock.u : L.ku,
    stun: h.stun ?? L.stun,
    hitstop: h.hitstop ?? L.hitstop,
    guard: h.guard ?? Math.max(6, Math.round(damage * 0.4)),
    chip: h.chip ?? (group === 'normal' ? 0.08 : 0.2),
    unblockable: !!h.unblockable,
    armourPierce: !!h.armourPierce,
    multiInterval: h.multi ? h.multi.interval : 0,
    multiMax: h.multi ? h.multi.max : 1,
    radial: !!h.radial,
    air: h.air !== false,
    ground: h.ground !== false,
    cinematic: !!h.cinematic,
  };
}

/** Normalise a projectile entry of an attack (the spec handed to world.shoot at its `t`). */
function normalizeProjectile(p, i, id, group) {
  return { ...p, index: i, t: p.t || 0, kind: p.kind || `${id}.${i}`, hit: p.hit && p.hit.shape === undefined && p.hit.t0 === undefined ? normalizeHit({ ...p.hit, t: [0, 0], shape: { type: 'arc' } }, i, group) : p.hit };
}

/**
 * Fill the defaults of an attack definition. Idempotent (a normalised attack is returned as is).
 * @param {object} def README §6.1
 * @param {string} [id]
 */
export function normalizeAttack(def, id) {
  if (def && def.normalized) return def;
  const aid = def.id || id || 'attack';
  const group = def.group || (def.ult ? 'ult' : def.fp ? 'skill' : 'normal');
  let motion = null;
  if (Array.isArray(def.motion) && def.motion.length) {
    if (Array.isArray(def.motion[0])) motion = { keys: def.motion.map((k) => k.slice()), hasU: def.motion.some((k) => k.length > 2) };
    else motion = { segs: def.motion.map((s) => ({ t0: s.t[0], t1: s.t[1], v: s.v })) };
  } else if (def.motion && (def.motion.keys || def.motion.segs)) motion = def.motion;
  const hits = (def.hits || []).map((h, i) => normalizeHit(h, i, group));
  const tr = def.track === false ? null : def.track || {};
  const firstActive = hits.length ? Math.min(...hits.map((h) => h.t0)) : def.duration * 0.4;
  return {
    normalized: true,
    id: aid, name: def.name || aid, group,
    duration: def.duration,
    clip: def.clip || null,
    stamina: def.stamina || 0, fp: def.fp || 0, ult: def.ult || 0,
    cooldown: def.cooldown || 0, cooldownKey: def.cooldownKey || aid,
    hits,
    motion,
    /** keeps turning toward its target until `until` s (rad/s) */
    track: tr ? { until: tr.until ?? Math.max(0, firstActive - 0.06), rate: (tr.rate ?? 360) * DEG } : null,
    armour: (def.armour || []).map(win),
    invuln: (def.invuln || []).map(win),
    passThrough: (def.passThrough || []).map(win),
    projectiles: (def.projectiles || []).map((p, i) => normalizeProjectile(p, i, aid, group)),
    markers: (def.markers || []).map((m) => ({ t: m.t, name: m.name, data: m.data || null })).sort((a, b) => a.t - b.t),
    cancelFrom: def.cancel && def.cancel.from !== undefined ? def.cancel.from : def.duration,
    cancels: def.cancels || null,
    counter: def.counter || null,
    teleports: def.teleports || [],
    superFreeze: def.superFreeze || null,
    cinematic: def.cinematic || null,
    firstActive,
    lastActive: hits.length ? Math.max(...hits.map((h) => h.t1)) : firstActive,
    slot: def.slot || null,
    meta: def.meta || null,
    /** source move (heroes): the compiled fighter move this attack was converted from */
    move: def.move || null,
  };
}

// ---- fighter moves -> RPG attacks -----------------------------------------------------------------------------------

/** Half-angle (deg) of the arc a weapon swing covers, by the move's trail style (moves.js trailOn data.style). */
const STYLE_ARC = { light: 62, rising: 48, overhead: 36, heavy: 70, spin: 180, huge: 150, drag: 50, glow: 60 };
/** Half-width (m) of a thrust box. */
const THRUST_HALF = 0.55;

/**
 * 3D hit volume of a fighter hit box { f: [f0, f1], u: [u0, u1] } (the duel's 2D box, extruded in depth).
 * thrusts -> a box along the facing; reaching far behind (f0 < -1.4) -> a full circle; everything else -> an arc
 * whose half-angle follows the swing style (`huge` swings wrap around; a box that starts behind the body widens it).
 */
export function shapeFromBox(h, style) {
  const f0 = h.f0, f1 = h.f1, u0 = Math.max(0, h.u0), u1 = h.u1;
  if (style === 'thrust') return normalizeShape({ type: 'box', f: [Math.min(f0, 0.1) - 0.1, f1], s: [-THRUST_HALF, THRUST_HALF], u: [u0, u1] });
  if (f0 < -1.4) return normalizeShape({ type: 'arc', r: [0, Math.max(f1, -f0)], angle: [-180, 180], u: [u0, u1] });
  let half = STYLE_ARC[style] ?? 58;
  if (f0 < -0.3) half = Math.max(half, 150);
  // a low ground box far ahead (runes, cracks): a forward lane, not a swing
  if (u1 <= 0.6 && f1 > 3) return normalizeShape({ type: 'box', f: [f0, f1], s: [-1.2, 1.2], u: [0, 1.2] });
  return normalizeShape({ type: 'arc', r: [Math.max(0, f0 - 0.25), f1], angle: [-half, half], u: [u0, u1] });
}

/**
 * Convert a compiled fighter move (src/game/logic compileFighterDef) into an RPG attack.
 * @param {object} mv compiled move
 * @param {object} [o] { slot, stamina, shapes: { [hitIndex | label]: shape }, clip }
 */
export function fromFighterMove(mv, o = {}) {
  const style = (() => { const m = mv.markers.find((x) => x.name === 'trailOn'); return (m && m.data && m.data.style) || (mv.duration > 0.75 ? 'heavy' : 'light'); })();
  const hits = mv.hits.map((h) => {
    const custom = o.shapes && (o.shapes[h.label] || o.shapes[h.index]);
    return {
      t: [h.t0, h.t1], label: h.label,
      shape: custom ? normalizeShape(custom) : shapeFromBox(h, style),
      damage: h.damage, level: h.level,
      knock: { f: h.kx * 0.8, u: h.ky * 0.85 },
      stun: h.level === 'light' || h.level === 'heavy' || h.level === 'crumple' ? h.hitstun : 0,
      hitstop: h.hitstop, guard: Math.round(h.guardDamage * 0.9),
      unblockable: h.unblockable, armourPierce: h.armourPierce,
      multi: h.multiMax > 1 ? { interval: h.multiInterval, max: h.multiMax } : null,
      air: h.air, ground: h.ground, cinematic: h.cinematic,
      radial: h.f0 < -1.4,
    };
  });
  const projectiles = mv.projectiles.map((p) => {
    const speed = Math.hypot(p.vx, p.vy);
    return {
      t: p.t, kind: p.kind, from: p.at,                       // 'self' | 'opponent'
      at: [p.of, p.ou, 0],                                    // ou null: chest height
      dir: speed > 1e-6 ? [p.vx / speed, p.vy / speed, 0] : [1, 0, 0],
      speed, gravity: p.gravity, lifetime: p.lifetime, delay: p.delay,
      radius: Math.max(0.3, (p.f1 - p.f0) * 0.5), height: [p.u0, p.u1],
      ground: speed < 2,
      pierce: p.pierce, multi: p.multiMax > 1 ? { interval: p.multiInterval, max: p.multiMax } : null,
      hit: {
        damage: p.hit.damage, level: p.hit.level, knock: { f: p.hit.kx * 0.8, u: p.hit.ky * 0.85 }, stun: p.hit.hitstun,
        hitstop: p.hit.hitstop, guard: Math.round(p.hit.guardDamage * 0.9), unblockable: p.hit.unblockable,
      },
      data: p.data, source: p,
    };
  });
  return normalizeAttack({
    id: mv.id, name: mv.name, group: mv.group, duration: mv.duration,
    clip: o.clip || null,
    stamina: o.stamina || 0, fp: mv.fpCost, ult: mv.ultCost, cooldown: mv.cooldown, cooldownKey: mv.cooldownKey,
    hits,
    motion: mv.motion,
    track: o.track,
    armour: mv.armour.map((a) => ({ t0: a.t0, t1: a.t1, hits: a.hits })),
    invuln: mv.invuln.map((a) => ({ t0: a.t0, t1: a.t1 })),
    passThrough: mv.passThrough.map((a) => ({ t0: a.t0, t1: a.t1 })),
    projectiles,
    markers: mv.markers,
    cancels: mv.cancels,
    counter: mv.counter,
    teleports: mv.teleports,
    superFreeze: mv.superFreeze,
    cinematic: mv.cinematic,
    slot: o.slot || (mv.meta && mv.meta.slot) || null,
    meta: mv.meta,
    move: mv,
  }, mv.id);
}

/** Forward displacement (m) accumulated from attack start to time t. */
export function forwardAt(atk, t) {
  const m = atk.motion;
  if (!m) return 0;
  if (m.segs) {
    let d = 0;
    for (let i = 0; i < m.segs.length; i++) { const s = m.segs[i]; if (t > s.t0) d += s.v * (Math.min(t, s.t1) - s.t0); }
    return d;
  }
  return sampleKeys(m.keys, t, 1);
}
/** Height (m) the attack puts the actor at, or -1 when its motion has no height track. */
export function heightAt(atk, t) {
  const m = atk.motion;
  if (!m || !m.hasU) return -1;
  return Math.max(0, sampleKeys(m.keys, t, 2));
}
function sampleKeys(keys, t, k) {
  const n = keys.length;
  if (t <= keys[0][0]) return keys[0][k] || 0;
  if (t >= keys[n - 1][0]) return keys[n - 1][k] || 0;
  let i = 1;
  while (i < n && keys[i][0] < t) i++;
  const a = keys[i - 1], b = keys[i], span = b[0] - a[0];
  const u = span > 0 ? (t - a[0]) / span : 1;
  return (a[k] || 0) + ((b[k] || 0) - (a[k] || 0)) * u;
}
/** First window { t0, t1 } of `list` containing t. */
export function windowAt(list, t) {
  for (let i = 0; i < list.length; i++) { const w = list[i]; if (t >= w.t0 - 1e-6 && t <= w.t1 + 1e-6) return w; }
  return null;
}
