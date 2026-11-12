// Fighter definitions: validation (precise, path-qualified messages for content authors) and compilation into the
// flat runtime form the engine reads every step. Authors write the format documented in README.md; the engine only
// ever sees the compiled form produced by compileFighterDef().

import {
  LEVELS, ATTACK_BUTTONS, CANCEL_TOKENS, GROUPS, DEFAULT_STATS, DEFAULT_MOVEMENT, HIT_DEFAULTS, DEFAULT_RULES,
} from './constants.js';

// ---------------------------------------------------------------------------------------------------------------
// schema (field lists drive the unknown-field warnings and their "did you mean" suggestions)

const F = {
  top: ['id', 'name', 'title', 'stats', 'movement', 'commands', 'moves', 'ai', 'meta'],
  stats: Object.keys(DEFAULT_STATS),
  movement: Object.keys(DEFAULT_MOVEMENT),
  dash: ['duration', 'distance', 'cancelFrom'],
  backstep: ['duration', 'distance', 'invuln'],
  dodge: ['duration', 'invuln', 'cooldown', 'cancelFrom'],
  roll: ['duration', 'distance'],
  move: ['name', 'group', 'duration', 'hits', 'motion', 'cancels', 'armour', 'invuln', 'passThrough', 'counter',
    'teleport', 'projectiles', 'markers', 'fpCost', 'ultCost', 'cooldown', 'cooldownKey', 'requires', 'superFreeze',
    'cinematic', 'hurt', 'ai', 'meta'],
  hit: ['t', 'box', 'damage', 'chip', 'hitstun', 'blockstun', 'knockback', 'level', 'hitstop', 'guardDamage',
    'unblockable', 'armourPierce', 'multi', 'juggle', 'air', 'ground', 'cinematic', 'hurtExtend', 'scaleStep', 'label'],
  projectile: ['t', 'kind', 'at', 'offset', 'box', 'velocity', 'gravity', 'lifetime', 'delay', 'hit', 'multi',
    'pierce', 'durability', 'clash', 'data'],
  cancel: ['t', 'into', 'on', 'dir', 'onHit', 'onContact'],
  armour: ['t', 'hits', 'damageScale'],
  invuln: ['t', 'vs'],
  counter: ['t', 'move', 'vs', 'hitstop'],
  teleport: ['t', 'to', 'distance', 'face'],
  marker: ['t', 'name', 'data'],
  requires: ['minDistance', 'maxDistance', 'opponentAirborne', 'hpBelow'],
  superFreeze: ['duration', 'userAnimates'],
  cinematic: ['hit', 'duration', 'distance', 'ticks', 'finish', 'markers', 'recovery'],
  tick: ['t', 'damage', 'hitstop', 'marker', 'data'],
  finish: ['t', 'damage', 'level', 'knockback', 'hitstop', 'marker', 'data'],
  hurt: ['t', 'box'],
  ai: ['range', 'role', 'weight', 'comboOnly'],
  fighterAi: ['aggression', 'preferredRange', 'zoning'],
};
F.projectileHit = F.hit.filter((k) => k !== 't' && k !== 'box' && k !== 'cinematic' && k !== 'hurtExtend');

export const AI_ROLES = ['poke', 'starter', 'combo', 'launcher', 'juggle', 'finisher', 'punish', 'antiair', 'zoning',
  'approach', 'counter', 'mobility', 'pressure', 'reversal'];
const VS = ['all', 'strike', 'projectile'];
const COMMAND_RE = /^(?:([dufb])\+)?(light|heavy|skill1|skill2|skill3|ult)$/;

// ---------------------------------------------------------------------------------------------------------------
// small checkers

const isObj = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);

/**
 * A deep-frozen copy of author data (marker / projectile / tick `data`): events hand it to presentation listeners,
 * which must never be able to change the definition (or the next event) through it.
 */
function frozen(v) {
  if (v === undefined) return null;
  if (v === null || typeof v !== 'object') return v;
  const out = Array.isArray(v) ? v.map(frozen) : Object.fromEntries(Object.entries(v).map(([k, x]) => [k, frozen(x)]));
  return Object.freeze(out);
}
const isNum = (v) => typeof v === 'number' && Number.isFinite(v);
const fmt = (v) => {
  try {
    const s = JSON.stringify(v);
    return s === undefined ? String(v) : s.length > 60 ? s.slice(0, 57) + '...' : s;
  } catch (e) { return String(v); }
};

function editDistance(a, b) {
  const m = a.length, n = b.length;
  const d = [];
  for (let i = 0; i <= m; i++) { d[i] = [i]; }
  for (let j = 1; j <= n; j++) d[0][j] = j;
  for (let i = 1; i <= m; i++) {
    for (let j = 1; j <= n; j++) {
      d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
    }
  }
  return d[m][n];
}

/** Closest name in `list` to `name` (edit distance <= 2 or a case-insensitive match), or null. */
function suggest(name, list) {
  let best = null, bd = 3;
  for (const c of list) {
    if (c.toLowerCase() === String(name).toLowerCase()) return c;
    const dd = editDistance(String(name), c);
    if (dd < bd) { bd = dd; best = c; }
  }
  return best;
}

function makeReporter() {
  const errors = [], warnings = [];
  const r = {
    errors, warnings,
    err(path, msg) { errors.push(`${path}: ${msg}`); },
    warn(path, msg) { warnings.push(`${path}: ${msg}`); },
    unknown(obj, allowed, path) {
      for (const k of Object.keys(obj)) {
        if (allowed.includes(k)) continue;
        const s = suggest(k, allowed);
        r.warn(`${path}.${k}`, `unknown field (ignored)${s ? ` - did you mean '${s}'?` : ''}`);
      }
    },
    num(obj, key, path, { min = -Infinity, max = Infinity, required = false, int = false, exclusiveMin = false } = {}) {
      const v = obj[key];
      if (v === undefined) { if (required) r.err(`${path}.${key}`, 'required number is missing'); return false; }
      if (!isNum(v)) { r.err(`${path}.${key}`, `expected a finite number, got ${fmt(v)}`); return false; }
      if (int && !Number.isInteger(v)) { r.err(`${path}.${key}`, `expected an integer, got ${v}`); return false; }
      if (exclusiveMin ? v <= min : v < min) { r.err(`${path}.${key}`, `must be ${exclusiveMin ? '>' : '>='} ${min}, got ${v}`); return false; }
      if (v > max) { r.err(`${path}.${key}`, `must be <= ${max}, got ${v}`); return false; }
      return true;
    },
    bool(obj, key, path) {
      const v = obj[key];
      if (v !== undefined && typeof v !== 'boolean') r.err(`${path}.${key}`, `expected true or false, got ${fmt(v)}`);
    },
    oneOf(obj, key, list, path, required = false) {
      const v = obj[key];
      if (v === undefined) { if (required) r.err(`${path}.${key}`, `required, one of ${list.map((x) => `'${x}'`).join(' | ')}`); return; }
      if (!list.includes(v)) {
        const s = typeof v === 'string' ? suggest(v, list) : null;
        r.err(`${path}.${key}`, `expected one of ${list.map((x) => `'${x}'`).join(' | ')}, got ${fmt(v)}${s ? ` - did you mean '${s}'?` : ''}`);
      }
    },
    /** [a, b] with a <= b (or a < b when strict), optionally clamped inside [lo, hi]. */
    range(v, path, { lo = -Infinity, hi = Infinity, strict = false, what = 'range' } = {}) {
      if (!Array.isArray(v) || v.length !== 2 || !isNum(v[0]) || !isNum(v[1])) {
        r.err(path, `expected a ${what} [min, max] of two finite numbers, got ${fmt(v)}`);
        return false;
      }
      if (strict ? v[0] >= v[1] : v[0] > v[1]) { r.err(path, `${what} start ${v[0]} must be ${strict ? '<' : '<='} its end ${v[1]}`); return false; }
      if (v[0] < lo - 1e-9 || v[1] > hi + 1e-9) { r.err(path, `${what} ${fmt(v)} must lie inside [${lo}, ${hi}]`); return false; }
      return true;
    },
  };
  return r;
}

// ---------------------------------------------------------------------------------------------------------------
// validation

/**
 * Validate a fighter definition.
 * @param {object} def
 * @returns {{ok: boolean, errors: string[], warnings: string[]}} errors make the def unusable; warnings are typos and
 *   suspicious design choices (unknown fields, unreachable moves, ...).
 */
export function validateFighterDef(def) {
  const r = makeReporter();
  // body scale relative to the 1.85 m reference: size-related sanity limits grow with it (giant bosses)
  r.scale = isObj(def) && isObj(def.stats) && isNum(def.stats.height) && def.stats.height > 0 ? def.stats.height / DEFAULT_STATS.height : 1;
  if (!isObj(def)) { r.err('def', `expected a fighter definition object, got ${fmt(def)}`); return { ok: false, errors: r.errors, warnings: r.warnings }; }
  r.unknown(def, F.top, 'def');
  if (typeof def.id !== 'string' || !/^[a-z0-9_-]+$/i.test(def.id)) r.err('def.id', `expected an id string of letters, digits, '_' or '-', got ${fmt(def.id)}`);
  if (def.name !== undefined && typeof def.name !== 'string') r.err('def.name', `expected a string, got ${fmt(def.name)}`);
  if (def.name === undefined) r.warn('def.name', 'missing display name (the HUD will show the id)');

  if (def.stats !== undefined) {
    if (!isObj(def.stats)) r.err('def.stats', `expected an object, got ${fmt(def.stats)}`);
    else {
      r.unknown(def.stats, F.stats, 'def.stats');
      for (const k of F.stats) r.num(def.stats, k, 'def.stats', { min: 0, exclusiveMin: true });
      // knockback is divided by the weight: tiny weights turn every hit into a rocket
      if (isNum(def.stats.weight) && def.stats.weight > 0) r.num(def.stats, 'weight', 'def.stats', { min: 0.2, max: 50 });
      if (isNum(def.stats.walkSpeed) && isNum(def.stats.backSpeed) && def.stats.backSpeed > def.stats.walkSpeed) r.warn('def.stats.backSpeed', 'walking back is faster than walking forward');
    }
  }
  if (def.movement !== undefined) validateMovement(def.movement, r);
  if (def.ai !== undefined) {
    if (!isObj(def.ai)) r.err('def.ai', `expected an object, got ${fmt(def.ai)}`);
    else {
      r.unknown(def.ai, F.fighterAi, 'def.ai');
      r.num(def.ai, 'aggression', 'def.ai', { min: 0, max: 1 });
      r.num(def.ai, 'preferredRange', 'def.ai', { min: 0 });
      r.num(def.ai, 'zoning', 'def.ai', { min: 0, max: 1 });
    }
  }

  const moves = def.moves;
  const ids = isObj(moves) ? Object.keys(moves) : [];
  if (!isObj(moves)) r.err('def.moves', `expected an object of moves keyed by id, got ${fmt(moves)}`);
  else if (!ids.length) r.err('def.moves', 'a fighter needs at least one move');
  for (const id of ids) {
    if (!/^[a-z0-9_.-]+$/i.test(id)) r.err(`def.moves.${id}`, 'move ids may only use letters, digits, _ . -');
    validateMove(moves[id], `moves.${id}`, ids, moves, r, { ...DEFAULT_STATS, ...(isObj(def.stats) ? def.stats : {}) });
  }

  const reachable = new Set();
  if (!isObj(def.commands)) r.err('def.commands', `expected an object mapping command keys ('light', 'f+heavy', ...) to move ids, got ${fmt(def.commands)}`);
  else {
    for (const [key, id] of Object.entries(def.commands)) {
      if (!COMMAND_RE.test(key)) {
        const s = suggest(key, ['light', 'heavy', 'skill1', 'skill2', 'skill3', 'ult', 'f+heavy', 'd+heavy', 'b+heavy', 'u+heavy']);
        r.err(`def.commands.${key}`, `invalid command key: use [d+|u+|f+|b+]light|heavy|skill1|skill2|skill3|ult${s ? ` - did you mean '${s}'?` : ''}`);
        continue;
      }
      if (id === null) continue; // explicitly unavailable
      if (typeof id !== 'string' || !ids.includes(id)) {
        const s = typeof id === 'string' ? suggest(id, ids) : null;
        r.err(`def.commands.${key}`, `unknown move ${fmt(id)}${s ? ` - did you mean '${s}'?` : ''}`);
        continue;
      }
      reachable.add(id);
    }
    if (!def.commands.light) r.warn('def.commands.light', 'no light attack mapped');
  }
  // reachability: commands, then cancel routes and counter follow-ups
  if (isObj(moves)) {
    let grew = true;
    while (grew) {
      grew = false;
      for (const id of [...reachable]) {
        const mv = moves[id];
        if (!isObj(mv)) continue;
        const nexts = [];
        if (Array.isArray(mv.cancels)) for (const c of mv.cancels) if (isObj(c)) for (const t of [].concat(c.into || [])) if (typeof t === 'string' && t[0] !== '@') nexts.push(t);
        if (isObj(mv.counter) && typeof mv.counter.move === 'string') nexts.push(mv.counter.move);
        for (const n of nexts) if (ids.includes(n) && !reachable.has(n)) { reachable.add(n); grew = true; }
      }
    }
    for (const id of ids) if (!reachable.has(id)) r.warn(`moves.${id}`, 'not reachable from any command, cancel route or counter (dead data?)');
  }
  return { ok: r.errors.length === 0, errors: r.errors, warnings: r.warnings };
}

function validateMovement(mv, r) {
  if (!isObj(mv)) { r.err('def.movement', `expected an object, got ${fmt(mv)}`); return; }
  r.unknown(mv, F.movement, 'def.movement');
  for (const k of F.movement) {
    const v = mv[k];
    if (v === undefined) continue;
    const p = `def.movement.${k}`;
    if (!isObj(v)) { r.err(p, `expected an object, got ${fmt(v)}`); continue; }
    r.unknown(v, F[k], p);
    r.num(v, 'duration', p, { min: 0.05, max: 2 });
    if ('distance' in v) r.num(v, 'distance', p, { min: 0, max: 8 * r.scale });
    if ('cancelFrom' in v) r.num(v, 'cancelFrom', p, { min: 0 });
    if ('cooldown' in v) r.num(v, 'cooldown', p, { min: 0 });
    if (v.invuln !== undefined) r.range(v.invuln, `${p}.invuln`, { lo: 0, hi: v.duration || DEFAULT_MOVEMENT[k].duration, what: 'time window' });
  }
}

function validateHitFields(h, p, r, { projectile = false, duration = Infinity } = {}) {
  r.unknown(h, projectile ? F.projectileHit : F.hit, p);
  if (!projectile) {
    r.range(h.t, `${p}.t`, { lo: 0, hi: duration, what: 'hit window (s)' });
    validateBox(h.box, `${p}.box`, r);
  }
  r.num(h, 'damage', p, { min: 0, required: true });
  r.oneOf(h, 'level', LEVELS, p);
  for (const k of ['chip', 'hitstun', 'blockstun', 'guardDamage', 'juggle']) r.num(h, k, p, { min: 0 });
  r.num(h, 'hitstop', p, { min: 0, max: 0.6 });
  if (isNum(h.hitstop) && h.hitstop > 0.3) r.warn(`${p}.hitstop`, `${h.hitstop} s is a very long hit-stop (finishers use 0.14-0.2)`);
  r.num(h, 'scaleStep', p, { min: 0, max: 1 });
  for (const k of ['unblockable', 'armourPierce', 'air', 'ground', 'cinematic', 'hurtExtend']) r.bool(h, k, p);
  if (h.knockback !== undefined) {
    if (!isObj(h.knockback)) r.err(`${p}.knockback`, `expected {x, y} in m/s, got ${fmt(h.knockback)}`);
    else {
      r.unknown(h.knockback, ['x', 'y'], `${p}.knockback`);
      r.num(h.knockback, 'x', `${p}.knockback`, { min: -30, max: 30 });
      r.num(h.knockback, 'y', `${p}.knockback`, { min: -30, max: 30 });
    }
  }
  if (h.multi !== undefined) {
    if (!isObj(h.multi)) r.err(`${p}.multi`, `expected {interval, max}, got ${fmt(h.multi)}`);
    else {
      r.unknown(h.multi, ['interval', 'max'], `${p}.multi`);
      r.num(h.multi, 'interval', `${p}.multi`, { min: 0, exclusiveMin: true, required: true });
      r.num(h.multi, 'max', `${p}.multi`, { min: 1, int: true, required: true });
      if (!projectile && Array.isArray(h.t) && isNum(h.multi.interval) && isNum(h.multi.max) && h.t[1] - h.t[0] < h.multi.interval * (h.multi.max - 1) - 1e-9) {
        r.warn(`${p}.multi`, `window ${h.t[1] - h.t[0]} s is too short for ${h.multi.max} hits ${h.multi.interval} s apart (needs ${(h.multi.interval * (h.multi.max - 1)).toFixed(3)} s)`);
      }
    }
  }
  if (h.ground === false && h.air === false) r.err(p, 'a hit with ground: false and air: false can never connect');
}

function validateBox(b, p, r) {
  if (!isObj(b)) { r.err(p, `expected a box {f: [min, max], u: [min, max]} in fighter-local metres, got ${fmt(b)}`); return; }
  r.unknown(b, ['f', 'u'], p);
  if (r.range(b.f, `${p}.f`, { strict: true, what: 'forward range (m)' }) && (b.f[1] > 8 * r.scale || b.f[0] < -3 * r.scale)) r.warn(`${p}.f`, `unusual reach ${fmt(b.f)} m for a ${(DEFAULT_STATS.height * r.scale).toFixed(2)} m fighter`);
  if (r.range(b.u, `${p}.u`, { strict: true, what: 'height range (m)' }) && (b.u[0] < -0.5 || b.u[1] > 6 * r.scale)) r.warn(`${p}.u`, `unusual height ${fmt(b.u)} m for a ${(DEFAULT_STATS.height * r.scale).toFixed(2)} m fighter`);
}

/** A list of timeline windows `{t: [from, to], ...}`; with `shorthand`, a bare `[from, to]` is accepted too. */
function windows(list, p, r, dur, fields, extra, shorthand = false) {
  if (list === undefined) return;
  if (!Array.isArray(list)) { r.err(p, `expected an array, got ${fmt(list)}`); return; }
  list.forEach((w, i) => {
    const q = `${p}[${i}]`;
    if (shorthand && Array.isArray(w)) { r.range(w, q, { lo: 0, hi: dur, what: 'time window (s)' }); return; }
    if (!isObj(w)) { r.err(q, `expected ${shorthand ? '[from, to] or ' : ''}an object {t: [from, to], ...}, got ${fmt(w)}`); return; }
    r.unknown(w, fields, q);
    r.range(w.t, `${q}.t`, { lo: 0, hi: dur, what: 'time window (s)' });
    if (extra) extra(w, q);
  });
}

function validateMove(mv, p, ids, moves, r, stats) {
  if (!isObj(mv)) { r.err(p, `expected a move object, got ${fmt(mv)}`); return; }
  r.unknown(mv, F.move, p);
  if (!r.num(mv, 'duration', p, { min: 0, exclusiveMin: true, max: 12, required: true })) return;
  const dur = mv.duration;
  if (mv.name !== undefined && typeof mv.name !== 'string') r.err(`${p}.name`, `expected a string, got ${fmt(mv.name)}`);
  r.oneOf(mv, 'group', GROUPS, p);
  for (const k of ['fpCost', 'ultCost', 'cooldown']) r.num(mv, k, p, { min: 0 });
  if (isNum(mv.fpCost) && isNum(stats.fpMax) && mv.fpCost > stats.fpMax) r.err(`${p}.fpCost`, `${mv.fpCost} can never be paid (stats.fpMax is ${stats.fpMax})`);
  if (isNum(mv.ultCost) && isNum(stats.ultMax) && mv.ultCost > stats.ultMax) r.err(`${p}.ultCost`, `${mv.ultCost} can never be paid (stats.ultMax is ${stats.ultMax})`);
  if ((mv.cinematic !== undefined || mv.superFreeze !== undefined) && !(mv.ultCost > 0)) r.warn(`${p}.ultCost`, 'an ultimate (superFreeze / cinematic) without an ultCost is free to spam');
  if (mv.cooldownKey !== undefined && typeof mv.cooldownKey !== 'string') r.err(`${p}.cooldownKey`, `expected a string, got ${fmt(mv.cooldownKey)}`);

  // hits
  let firstActive = Infinity;
  if (mv.hits !== undefined) {
    if (!Array.isArray(mv.hits)) r.err(`${p}.hits`, `expected an array of hits, got ${fmt(mv.hits)}`);
    else mv.hits.forEach((h, i) => {
      const q = `${p}.hits[${i}]`;
      if (!isObj(h)) { r.err(q, `expected a hit object, got ${fmt(h)}`); return; }
      validateHitFields(h, q, r, { duration: dur });
      if (Array.isArray(h.t) && isNum(h.t[0])) firstActive = Math.min(firstActive, h.t[0]);
      if (isObj(h.box) && Array.isArray(h.box.f) && isNum(h.box.f[1]) && h.box.f[1] <= 0) r.warn(`${q}.box.f`, `${fmt(h.box.f)} only reaches behind the fighter (f is forward-positive) - a sign mistake?`);
      if (h.cinematic === true && mv.cinematic === undefined) r.err(`${q}.cinematic`, 'a cinematic trigger needs the move\'s `cinematic` block');
      if (h.cinematic === true && isObj(mv.cinematic) && isNum(mv.cinematic.hit) && mv.cinematic.hit !== i) r.warn(`${q}.cinematic`, `hit ${i} is flagged as a trigger but cinematic.hit is ${mv.cinematic.hit}: both will trigger`);
    });
  }

  // motion
  if (mv.motion !== undefined) {
    const m = mv.motion;
    if (Array.isArray(m)) {
      m.forEach((s, i) => {
        const q = `${p}.motion[${i}]`;
        if (!isObj(s)) { r.err(q, `expected a velocity segment {t: [from, to], v}, got ${fmt(s)}`); return; }
        r.unknown(s, ['t', 'v'], q);
        r.range(s.t, `${q}.t`, { lo: 0, hi: dur, what: 'time window (s)' });
        r.num(s, 'v', q, { min: -40, max: 40, required: true });
      });
    } else if (isObj(m)) {
      r.unknown(m, ['keys'], `${p}.motion`);
      if (!Array.isArray(m.keys) || m.keys.length < 2) r.err(`${p}.motion.keys`, `expected at least two keys [t, forward, up?], got ${fmt(m.keys)}`);
      else {
        let last = -Infinity;
        m.keys.forEach((k, i) => {
          const q = `${p}.motion.keys[${i}]`;
          if (!Array.isArray(k) || k.length < 2 || k.length > 3 || !k.every(isNum)) { r.err(q, `expected [t, forward] or [t, forward, up] numbers, got ${fmt(k)}`); return; }
          if (k[0] < 0 || k[0] > dur + 1e-9) r.err(q, `key time ${k[0]} outside the move [0, ${dur}]`);
          if (k[0] < last) r.err(q, `key times must increase (${k[0]} after ${last})`);
          if (k.length === 3 && k[2] < 0) r.err(q, `height ${k[2]} must be >= 0`);
          last = k[0];
        });
        const lastKey = m.keys[m.keys.length - 1];
        if (Array.isArray(lastKey) && lastKey.length === 3 && lastKey[2] > 0.01) r.warn(`${p}.motion.keys`, `the move ends ${lastKey[2]} m above the floor; the fighter will drop at the end`);
      }
    } else r.err(`${p}.motion`, `expected velocity segments [{t: [from, to], v}] or {keys: [[t, f, u?], ...]}, got ${fmt(m)}`);
  }

  // cancels
  windows(mv.cancels, `${p}.cancels`, r, dur, F.cancel, (c, q) => {
    const into = [].concat(c.into === undefined ? [] : c.into);
    if (!into.length) r.err(`${q}.into`, 'required: a move id, a list of move ids, or group tokens (@normal @skill @ult @any @dodge @dash)');
    for (const t of into) {
      if (typeof t !== 'string') { r.err(`${q}.into`, `expected strings, got ${fmt(t)}`); continue; }
      if (t[0] === '@') { if (!CANCEL_TOKENS.includes(t)) r.err(`${q}.into`, `unknown token '${t}' (use ${CANCEL_TOKENS.join(' ')})`); }
      else if (!ids.includes(t)) { const s = suggest(t, ids); r.err(`${q}.into`, `unknown move '${t}'${s ? ` - did you mean '${s}'?` : ''}`); }
    }
    if (c.on !== undefined) {
      if (!ATTACK_BUTTONS.includes(c.on)) r.err(`${q}.on`, `expected one of ${ATTACK_BUTTONS.join(' | ')}, got ${fmt(c.on)}`);
      if (into.length !== 1 || (typeof into[0] === 'string' && into[0][0] === '@')) r.err(`${q}.into`, "a route (with 'on') must name exactly one move id");
    }
    if (c.dir !== undefined) {
      r.oneOf(c, 'dir', ['f', 'b', 'd', 'u'], q);
      if (c.on === undefined) r.err(`${q}.dir`, "'dir' only applies to routes (cancels with 'on')");
    }
    r.bool(c, 'onHit', q);
    r.bool(c, 'onContact', q);
  });

  windows(mv.armour, `${p}.armour`, r, dur, F.armour, (a, q) => {
    r.num(a, 'hits', q, { min: 1, int: true });
    r.num(a, 'damageScale', q, { min: 0, max: 2 });
  }, true);
  windows(mv.invuln, `${p}.invuln`, r, dur, F.invuln, (a, q) => r.oneOf(a, 'vs', VS, q), true);
  windows(mv.hurt, `${p}.hurt`, r, dur, F.hurt, (a, q) => validateBox(a.box, `${q}.box`, r));
  if (mv.passThrough !== undefined) {
    if (!Array.isArray(mv.passThrough)) r.err(`${p}.passThrough`, `expected an array of [from, to] windows, got ${fmt(mv.passThrough)}`);
    else mv.passThrough.forEach((w, i) => r.range(isObj(w) ? w.t : w, `${p}.passThrough[${i}]`, { lo: 0, hi: dur, what: 'time window (s)' }));
  }

  if (mv.counter !== undefined) {
    const c = mv.counter, q = `${p}.counter`;
    if (!isObj(c)) r.err(q, `expected {t: [from, to], move}, got ${fmt(c)}`);
    else {
      r.unknown(c, F.counter, q);
      r.range(c.t, `${q}.t`, { lo: 0, hi: dur, what: 'time window (s)' });
      r.oneOf(c, 'vs', VS, q);
      r.num(c, 'hitstop', q, { min: 0, max: 0.6 });
      if (typeof c.move !== 'string' || !ids.includes(c.move)) { const s = typeof c.move === 'string' ? suggest(c.move, ids) : null; r.err(`${q}.move`, `unknown move ${fmt(c.move)}${s ? ` - did you mean '${s}'?` : ''}`); }
      else {
        const cm = moves[c.move];
        const inv = isObj(cm) && Array.isArray(cm.invuln) && cm.invuln.some((w) => { const wt = Array.isArray(w) ? w : isObj(w) ? w.t : null; return Array.isArray(wt) && wt[0] <= 0.001; });
        if (!inv) r.warn(`${q}.move`, `counter follow-up '${c.move}' has no invulnerability at t = 0; it can be stuffed by multi-hit attacks`);
      }
      // invulnerability is checked before the counter stance: a hit the move is invulnerable to just passes through
      if (Array.isArray(c.t) && Array.isArray(mv.invuln)) {
        const cvs = c.vs || 'strike';
        mv.invuln.forEach((w, i) => {
          const wt = Array.isArray(w) ? w : isObj(w) ? w.t : null;
          const wvs = isObj(w) && w.vs ? w.vs : 'all';
          if (Array.isArray(wt) && wt[0] < c.t[1] && c.t[0] < wt[1] && (wvs === 'all' || cvs === 'all' || wvs === cvs)) r.warn(`${q}.t`, `overlaps invuln[${i}]: hits pass through an invulnerable fighter, so the counter cannot trigger there`);
        });
      }
    }
  }

  if (mv.teleport !== undefined) {
    if (!Array.isArray(mv.teleport)) r.err(`${p}.teleport`, `expected an array of {t, to, distance, face?}, got ${fmt(mv.teleport)}`);
    else mv.teleport.forEach((tp, i) => {
      const q = `${p}.teleport[${i}]`;
      if (!isObj(tp)) { r.err(q, `expected {t, to, distance, face?}, got ${fmt(tp)}`); return; }
      r.unknown(tp, F.teleport, q);
      r.num(tp, 't', q, { min: 0, max: dur, required: true });
      r.oneOf(tp, 'to', ['forward', 'behind'], q, true);
      r.num(tp, 'distance', q, { min: 0, max: 18 });
      r.bool(tp, 'face', q);
    });
  }

  if (mv.projectiles !== undefined) {
    if (!Array.isArray(mv.projectiles)) r.err(`${p}.projectiles`, `expected an array, got ${fmt(mv.projectiles)}`);
    else mv.projectiles.forEach((s, i) => {
      const q = `${p}.projectiles[${i}]`;
      if (!isObj(s)) { r.err(q, `expected a projectile spec, got ${fmt(s)}`); return; }
      r.unknown(s, F.projectile, q);
      r.num(s, 't', q, { min: 0, max: dur, required: true });
      r.oneOf(s, 'at', ['self', 'opponent'], q);
      if (s.kind !== undefined && typeof s.kind !== 'string') r.err(`${q}.kind`, `expected a string, got ${fmt(s.kind)}`);
      if (s.offset !== undefined) {
        if (!isObj(s.offset)) r.err(`${q}.offset`, `expected {f, u} metres, got ${fmt(s.offset)}`);
        else { r.unknown(s.offset, ['f', 'u'], `${q}.offset`); r.num(s.offset, 'f', `${q}.offset`); r.num(s.offset, 'u', `${q}.offset`); }
      }
      validateBox(s.box, `${q}.box`, r);
      if (s.velocity !== undefined) {
        if (!isObj(s.velocity)) r.err(`${q}.velocity`, `expected {x, y} m/s (x = forward), got ${fmt(s.velocity)}`);
        else { r.unknown(s.velocity, ['x', 'y'], `${q}.velocity`); r.num(s.velocity, 'x', `${q}.velocity`, { min: -60, max: 60 }); r.num(s.velocity, 'y', `${q}.velocity`, { min: -60, max: 60 }); }
      }
      r.num(s, 'gravity', q, { min: 0 });
      r.num(s, 'lifetime', q, { min: 0, exclusiveMin: true, max: 20, required: true });
      r.num(s, 'delay', q, { min: 0, max: 10 });
      r.num(s, 'durability', q, { min: 1, int: true });
      r.bool(s, 'pierce', q);
      r.bool(s, 'clash', q);
      if (!isObj(s.hit)) r.err(`${q}.hit`, `required: hit data {damage, level, ...}, got ${fmt(s.hit)}`);
      else validateHitFields(s.hit, `${q}.hit`, r, { projectile: true });
      if (s.multi !== undefined) {
        if (!isObj(s.multi)) r.err(`${q}.multi`, `expected {interval, max}, got ${fmt(s.multi)}`);
        else {
          r.unknown(s.multi, ['interval', 'max'], `${q}.multi`);
          r.num(s.multi, 'interval', `${q}.multi`, { min: 0, exclusiveMin: true, required: true });
          r.num(s.multi, 'max', `${q}.multi`, { min: 1, int: true, required: true });
        }
      }
      if (isNum(s.t)) firstActive = Math.min(firstActive, s.t + (isNum(s.delay) ? s.delay : 0));
    });
  }

  if (mv.markers !== undefined) {
    if (!Array.isArray(mv.markers)) r.err(`${p}.markers`, `expected an array of {t, name, data?}, got ${fmt(mv.markers)}`);
    else mv.markers.forEach((k, i) => {
      const q = `${p}.markers[${i}]`;
      if (!isObj(k)) { r.err(q, `expected {t, name, data?}, got ${fmt(k)}`); return; }
      r.unknown(k, F.marker, q);
      r.num(k, 't', q, { min: 0, max: dur, required: true });
      if (typeof k.name !== 'string' || !k.name) r.err(`${q}.name`, `expected a non-empty string, got ${fmt(k.name)}`);
    });
  }

  if (mv.requires !== undefined) {
    const q = `${p}.requires`;
    if (!isObj(mv.requires)) r.err(q, `expected an object, got ${fmt(mv.requires)}`);
    else {
      r.unknown(mv.requires, F.requires, q);
      r.num(mv.requires, 'minDistance', q, { min: 0 });
      r.num(mv.requires, 'maxDistance', q, { min: 0 });
      r.num(mv.requires, 'hpBelow', q, { min: 0, max: 1 });
      r.bool(mv.requires, 'opponentAirborne', q);
      if (isNum(mv.requires.minDistance) && isNum(mv.requires.maxDistance) && mv.requires.minDistance > mv.requires.maxDistance) r.err(q, `minDistance ${mv.requires.minDistance} > maxDistance ${mv.requires.maxDistance}: the move can never start`);
    }
  }

  let freeze = 0;
  if (mv.superFreeze !== undefined) {
    const q = `${p}.superFreeze`;
    if (isNum(mv.superFreeze)) { if (mv.superFreeze <= 0 || mv.superFreeze > 3) r.err(q, `expected 0 < seconds <= 3, got ${mv.superFreeze}`); else freeze = mv.superFreeze; }
    else if (isObj(mv.superFreeze)) {
      r.unknown(mv.superFreeze, F.superFreeze, q);
      if (r.num(mv.superFreeze, 'duration', q, { min: 0, exclusiveMin: true, max: 3, required: true })) freeze = mv.superFreeze.duration;
      r.bool(mv.superFreeze, 'userAnimates', q);
    } else r.err(q, `expected seconds or {duration, userAnimates}, got ${fmt(mv.superFreeze)}`);
    const animates = !(isObj(mv.superFreeze) && mv.superFreeze.userAnimates === false);
    if (animates && freeze && firstActive < freeze) r.err(q, `the first active time ${firstActive} s falls inside the ${freeze} s super-freeze; hits must start after the freeze`);
  }

  if (mv.cinematic !== undefined) {
    const c = mv.cinematic, q = `${p}.cinematic`;
    if (!isObj(c)) r.err(q, `expected an object, got ${fmt(c)}`);
    else {
      r.unknown(c, F.cinematic, q);
      if (r.num(c, 'hit', q, { min: 0, int: true }) && (!Array.isArray(mv.hits) || !mv.hits[c.hit])) r.err(`${q}.hit`, `hit index ${c.hit} does not exist in ${p}.hits`);
      r.num(c, 'duration', q, { min: 0, exclusiveMin: true, max: 12, required: true });
      r.num(c, 'distance', q, { min: 0, max: 4 * r.scale });
      r.num(c, 'recovery', q, { min: 0, max: 3 });
      const cd = isNum(c.duration) ? c.duration : Infinity;
      if (c.ticks !== undefined) {
        if (!Array.isArray(c.ticks)) r.err(`${q}.ticks`, `expected an array of {t, damage}, got ${fmt(c.ticks)}`);
        else c.ticks.forEach((tk, i) => {
          const qq = `${q}.ticks[${i}]`;
          if (!isObj(tk)) { r.err(qq, `expected {t, damage, hitstop?, marker?}, got ${fmt(tk)}`); return; }
          r.unknown(tk, F.tick, qq);
          r.num(tk, 't', qq, { min: 0, max: cd, required: true });
          r.num(tk, 'damage', qq, { min: 0, required: true });
          r.num(tk, 'hitstop', qq, { min: 0, max: 0.6 });
          if (tk.marker !== undefined && typeof tk.marker !== 'string') r.err(`${qq}.marker`, `expected a string, got ${fmt(tk.marker)}`);
        });
      }
      if (!isObj(c.finish)) r.err(`${q}.finish`, 'required: {t, damage, level, knockback}');
      else {
        r.unknown(c.finish, F.finish, `${q}.finish`);
        r.num(c.finish, 't', `${q}.finish`, { min: 0, max: cd, required: true });
        r.num(c.finish, 'damage', `${q}.finish`, { min: 0, required: true });
        r.oneOf(c.finish, 'level', ['launch', 'knockdown'], `${q}.finish`);
        r.num(c.finish, 'hitstop', `${q}.finish`, { min: 0, max: 0.6 });
        if (c.finish.knockback !== undefined && !isObj(c.finish.knockback)) r.err(`${q}.finish.knockback`, `expected {x, y}, got ${fmt(c.finish.knockback)}`);
        if (isNum(c.finish.t) && Array.isArray(c.ticks)) c.ticks.forEach((tk, i) => { if (isObj(tk) && isNum(tk.t) && tk.t > c.finish.t) r.warn(`${q}.ticks[${i}].t`, `${tk.t} s comes after the finish (${c.finish.t} s): damage after the climax`); });
      }
      if (c.markers !== undefined) {
        if (!Array.isArray(c.markers)) r.err(`${q}.markers`, `expected an array, got ${fmt(c.markers)}`);
        else c.markers.forEach((k, i) => {
          const qq = `${q}.markers[${i}]`;
          if (!isObj(k)) { r.err(qq, `expected {t, name, data?}, got ${fmt(k)}`); return; }
          r.unknown(k, F.marker, qq);
          r.num(k, 't', qq, { min: 0, max: cd, required: true });
          if (typeof k.name !== 'string' || !k.name) r.err(`${qq}.name`, `expected a non-empty string, got ${fmt(k.name)}`);
        });
      }
    }
    if (!freeze) r.warn(`${p}.superFreeze`, 'a cinematic move without a super-freeze; ultimates normally open with one');
  }

  if (mv.ai !== undefined) {
    const q = `${p}.ai`;
    if (!isObj(mv.ai)) r.err(q, `expected an object, got ${fmt(mv.ai)}`);
    else {
      r.unknown(mv.ai, F.ai, q);
      if (mv.ai.range !== undefined) r.range(mv.ai.range, `${q}.range`, { lo: 0, hi: 20, what: 'distance range (m)' });
      r.oneOf(mv.ai, 'role', AI_ROLES, q);
      r.num(mv.ai, 'weight', q, { min: 0 });
      r.bool(mv.ai, 'comboOnly', q);
    }
  }
}

/** Validate and throw one Error listing every problem (used by createMatch). */
export function assertFighterDef(def) {
  const res = validateFighterDef(def);
  if (!res.ok) {
    const id = isObj(def) && typeof def.id === 'string' ? def.id : '?';
    throw new Error(`invalid fighter definition '${id}':\n  - ${res.errors.join('\n  - ')}`);
  }
  return res;
}

// ---------------------------------------------------------------------------------------------------------------
// compilation

const tw = (w) => (Array.isArray(w) ? { t0: w[0], t1: w[1] } : { t0: w.t[0], t1: w.t[1] });

/** Infer a move's group from its fields when the author did not set one. */
function inferGroup(mv) {
  if (mv.group) return mv.group;
  if (mv.cinematic || mv.superFreeze || (mv.ultCost || 0) > 0) return 'ult';
  if ((mv.fpCost || 0) > 0) return 'skill';
  return 'normal';
}

/**
 * Compile one hit (move hit or projectile hit) with every default filled in.
 * @param {object} h author hit  @param {number} index  @param {string} group move group (for the chip default)
 * @param {object} rules match rules
 */
function compileHit(h, index, group, rules = DEFAULT_RULES) {
  const level = h.level || 'light';
  const d = HIT_DEFAULTS[level];
  const kb = h.knockback || {};
  const damage = h.damage;
  const chipRatio = (rules.chip && rules.chip[group]) || 0;
  return {
    index,
    label: h.label || null,
    t0: h.t ? h.t[0] : 0,
    t1: h.t ? h.t[1] : 0,
    f0: h.box ? h.box.f[0] : 0,
    f1: h.box ? h.box.f[1] : 0,
    u0: h.box ? h.box.u[0] : 0,
    u1: h.box ? h.box.u[1] : 0,
    damage,
    chip: h.chip !== undefined ? h.chip : Math.round(damage * chipRatio),
    hitstun: h.hitstun !== undefined ? h.hitstun : d.hitstun,
    blockstun: h.blockstun !== undefined ? h.blockstun : d.blockstun,
    kx: kb.x !== undefined ? kb.x : d.knockback.x,
    ky: kb.y !== undefined ? kb.y : d.knockback.y,
    level,
    hitstop: h.hitstop !== undefined ? h.hitstop : d.hitstop,
    guardDamage: h.guardDamage !== undefined ? h.guardDamage : Math.max(3, Math.round(damage * rules.guardDamageRatio)),
    unblockable: !!h.unblockable,
    armourPierce: !!h.armourPierce,
    multiInterval: h.multi ? h.multi.interval : 0,
    multiMax: h.multi ? h.multi.max : 1,
    juggle: h.juggle !== undefined ? h.juggle : 1,
    air: h.air !== false,
    ground: h.ground !== false,
    cinematic: !!h.cinematic,
    hurtExtend: h.hurtExtend !== undefined ? !!h.hurtExtend : group === 'normal',
    scaleStep: h.scaleStep !== undefined ? h.scaleStep : null,
  };
}

/** Compile one move. `id` is its key in def.moves. */
export function compileMove(id, mv, rules = DEFAULT_RULES) {
  const group = inferGroup(mv);
  const hits = (mv.hits || []).map((h, i) => compileHit(h, i, group, rules));
  if (mv.cinematic && hits[mv.cinematic.hit || 0]) hits[mv.cinematic.hit || 0].cinematic = true;
  let motion = null;
  if (Array.isArray(mv.motion)) motion = { segs: mv.motion.map((s) => ({ t0: s.t[0], t1: s.t[1], v: s.v })) };
  else if (mv.motion && mv.motion.keys) motion = { keys: mv.motion.keys.map((k) => k.slice()), hasU: mv.motion.keys.some((k) => k.length > 2) };
  const cancels = (mv.cancels || []).map((c) => {
    const into = [].concat(c.into);
    return {
      t0: c.t[0], t1: c.t[1],
      on: c.on || null,
      dir: c.dir || null,
      route: c.on ? into[0] : null,
      ids: new Set(into.filter((x) => x[0] !== '@')),
      groups: new Set(into.filter((x) => x[0] === '@').map((x) => x.slice(1))),
      onHit: !!c.onHit,
      onContact: !!c.onContact,
    };
  });
  const sf = mv.superFreeze;
  const superFreeze = sf ? (typeof sf === 'number' ? { duration: sf, userAnimates: true } : { duration: sf.duration, userAnimates: sf.userAnimates !== false }) : null;
  const projectiles = (mv.projectiles || []).map((s, i) => ({
    index: i,
    t: s.t,
    kind: s.kind || `${id}.${i}`,
    at: s.at || 'self',
    of: s.offset ? s.offset.f || 0 : 0,
    ou: s.offset && s.offset.u !== undefined ? s.offset.u : null, // null: the owner's chest height (0.65 x height)
    f0: s.box.f[0], f1: s.box.f[1], u0: s.box.u[0], u1: s.box.u[1],
    vx: s.velocity ? s.velocity.x || 0 : 0,
    vy: s.velocity ? s.velocity.y || 0 : 0,
    gravity: s.gravity || 0,
    lifetime: s.lifetime,
    delay: s.delay || 0,
    hit: compileHit(s.hit, i, group, rules),
    multiInterval: s.multi ? s.multi.interval : 0,
    multiMax: s.multi ? s.multi.max : (s.hit.multi ? s.hit.multi.max : 1),
    pierce: !!s.pierce,
    durability: s.durability || 1,
    clash: s.clash !== false,
    data: frozen(s.data),
  }));
  for (const p of projectiles) if (!p.multiInterval && p.hit.multiInterval) p.multiInterval = p.hit.multiInterval;
  const cin = mv.cinematic;
  const cinematic = cin ? {
    hit: cin.hit || 0,
    duration: cin.duration,
    distance: cin.distance !== undefined ? cin.distance : null, // null: both push-widths + 0.5 m
    recovery: cin.recovery !== undefined ? cin.recovery : 0.5,
    ticks: (cin.ticks || []).map((t) => ({ t: t.t, damage: t.damage, hitstop: t.hitstop || 0, marker: t.marker || null, data: frozen(t.data) })).sort((a, b) => a.t - b.t),
    finish: {
      t: cin.finish.t,
      damage: cin.finish.damage,
      level: cin.finish.level || 'knockdown',
      kx: cin.finish.knockback && cin.finish.knockback.x !== undefined ? cin.finish.knockback.x : 5,
      ky: cin.finish.knockback && cin.finish.knockback.y !== undefined ? cin.finish.knockback.y : 5,
      hitstop: cin.finish.hitstop || 0.2,
      marker: cin.finish.marker || null,
      data: frozen(cin.finish.data),
    },
    markers: (cin.markers || []).map((k) => ({ t: k.t, name: k.name, data: frozen(k.data) })).sort((a, b) => a.t - b.t),
  } : null;
  const c = mv.counter;
  const lastHitEnd = hits.reduce((m, h) => Math.max(m, h.t1), 0);
  const out = {
    compiled: true,
    id,
    name: mv.name || id,
    group,
    duration: mv.duration,
    hits,
    motion,
    cancels,
    armour: (mv.armour || []).map((a) => ({ ...tw(a), hits: a.hits || Infinity, damageScale: a.damageScale !== undefined ? a.damageScale : 1 })),
    invuln: (mv.invuln || []).map((a) => ({ ...tw(a), vs: a.vs || 'all' })),
    passThrough: (mv.passThrough || []).map(tw),
    hurt: (mv.hurt || []).map((a) => ({ ...tw(a), f0: a.box.f[0], f1: a.box.f[1], u0: a.box.u[0], u1: a.box.u[1] })),
    counter: c ? { t0: c.t[0], t1: c.t[1], move: c.move, vs: c.vs || 'strike', hitstop: c.hitstop !== undefined ? c.hitstop : 0.12 } : null,
    teleports: (mv.teleport || []).map((tp) => ({ t: tp.t, to: tp.to, distance: tp.distance !== undefined ? tp.distance : 1, face: tp.face !== false })).sort((a, b) => a.t - b.t),
    projectiles,
    markers: (mv.markers || []).map((k) => ({ t: k.t, name: k.name, data: frozen(k.data) })).sort((a, b) => a.t - b.t),
    fpCost: mv.fpCost || 0,
    ultCost: mv.ultCost || 0,
    cooldown: mv.cooldown || 0,
    cooldownKey: mv.cooldownKey || id,
    requires: mv.requires ? { ...mv.requires } : null,
    superFreeze,
    cinematic,
    ai: mv.ai ? { ...mv.ai } : {},
    firstActive: Math.min(
      hits.length ? Math.min(...hits.map((h) => h.t0)) : Infinity,
      projectiles.length ? Math.min(...projectiles.map((p) => p.t + p.delay)) : Infinity,
    ),
    lastActive: Math.max(lastHitEnd, projectiles.length ? Math.max(...projectiles.map((p) => p.t)) : 0),
    meta: frozen(mv.meta),
  };
  return out;
}

/**
 * Compile a validated fighter definition into its runtime form (throws if it is invalid).
 * @param {object} def   author definition
 * @param {object} rules match rules (chip / guard-damage defaults depend on them)
 */
export function compileFighterDef(def, rules = DEFAULT_RULES) {
  const res = assertFighterDef(def);
  const stats = { ...DEFAULT_STATS, ...(def.stats || {}) };
  const movement = {};
  for (const k of Object.keys(DEFAULT_MOVEMENT)) movement[k] = { ...DEFAULT_MOVEMENT[k], ...((def.movement && def.movement[k]) || {}) };
  const moves = {};
  for (const id of Object.keys(def.moves)) moves[id] = compileMove(id, def.moves[id], rules);
  const commands = {};
  for (const [k, v] of Object.entries(def.commands)) if (v) commands[k] = v;
  return {
    id: def.id,
    name: def.name || def.id,
    title: def.title || '',
    stats,
    movement,
    commands,
    moves,
    ai: { aggression: 0.5, zoning: 0.5, ...(def.ai || {}) },
    warnings: res.warnings,
    source: def,
  };
}

/**
 * Resolve the move a button press asks for, honouring direction variants: d+ > u+ > f+ > b+ > plain.
 * @param {object} cdef compiled def  @param {string} button  @param {{fwd: number, up: boolean, down: boolean}} dir
 * @returns {string|null} move id
 */
export function resolveCommand(cdef, button, dir) {
  const c = cdef.commands;
  if (dir.down && c['d+' + button]) return c['d+' + button];
  if (dir.up && c['u+' + button]) return c['u+' + button];
  if (dir.fwd > 0 && c['f+' + button]) return c['f+' + button];
  if (dir.fwd < 0 && c['b+' + button]) return c['b+' + button];
  return c[button] || null;
}
