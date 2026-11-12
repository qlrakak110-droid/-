// Fuzzer: random-input controllers (mashers, holders, mixed, plus the AI) on the sample, extreme, giant and authored
// definitions, random dt patterns and rule variations, for thousands of simulated seconds. Every step checks the
// state invariants and every event is checked for shape and order (see INVARIANTS below). Deterministic per seed.
//
//   node src/game/logic/test/run.mjs --fuzz 40      40 fuzz matches (no soak)

import { createMatch } from '../match.js';
import { createAIController } from '../ai.js';
import { passesThrough } from '../fighter.js';
import { makeRng } from '../rng.js';
import { NEUTRAL_INPUT, STATES, BUTTONS } from '../constants.js';
import { sampleFighter } from '../sample-fighter.js';
import { extremeFighter, giantFighter, authoredFighter } from './fixtures.mjs';

// INVARIANTS (per step): finite numbers; bodies inside the arena and above the floor; meters, timers, cooldowns in
// range; state known; 'attack' <=> a current move whose clock lies inside its duration; solid grounded push-boxes never
// overlap; no fighter stuck in a non-neutral state; the round clock never rises inside a round; HP never rises inside a
// round; every match ends. (per event): known name, finite non-decreasing time, valid fighter indices, state chains
// (from == previous to), moveStart/moveEnd pairing, projectile ids spawned once / expired once / no events after,
// superFreeze and cinematic start/end pairing, at most one KO per fighter per round, sane hit payloads.

const KNOWN = new Set([
  'roundStart', 'fightStart', 'phase', 'timeUp', 'roundEnd', 'matchEnd', 'state', 'turn', 'moveStart', 'moveEnd',
  'moveDenied', 'marker', 'teleport', 'dodge', 'perfectDodge', 'hit', 'guard', 'guardBreak', 'counter', 'comboEnd',
  'land', 'tech', 'wallBounce', 'ko', 'meter', 'ultReady', 'projectileSpawn', 'projectileActive', 'projectileMove',
  'projectileHit', 'projectileClash', 'projectileExpire', 'superFreezeStart', 'superFreezeEnd', 'cinematicStart',
  'cinematicTick', 'cinematicEnd',
]);
const STATE_SET = new Set(STATES);
const FREE = new Set(['idle', 'walk', 'guard', 'intro', 'victory', 'defeat', 'ko']);
const NUM = ['x', 'y', 'vx', 'vy', 'hp', 'fp', 'ult', 'guard', 'moveTime', 'timer', 'stateTime', 'hitstop', 'dodgeCooldown'];
const IDX = ['fighter', 'attacker', 'defender', 'owner', 'by'];

/** A random-input controller. style: 'masher' (fast toggles), 'holder' (long holds), 'mixed'. */
export function createRandomController(seed, style = 'mixed') {
  const r = makeRng(seed);
  const held = { ...NEUTRAL_INPUT };
  const until = {};
  let moveUntil = 0;
  const rate = style === 'masher' ? 0.35 : style === 'holder' ? 0.03 : 0.12;
  return {
    kind: 'fuzz',
    update(view) {
      const t = view.time;
      for (const b of BUTTONS) {
        if (t < (until[b] || 0)) continue;
        if (r() < rate * (b === 'guard' ? 1.5 : b === 'ult' ? 0.4 : 1)) {
          held[b] = !held[b];
          until[b] = t + (style === 'holder' ? r() * 1.5 : r() * 0.2);
        }
      }
      if (t >= moveUntil) {
        held.move = r() < 0.4 ? 0 : r() < 0.5 ? -1 : 1;
        moveUntil = t + (style === 'masher' ? r() * 0.1 : r() * 0.8);
      }
      return held;
    },
  };
}

const DT_PATTERNS = {
  fixed60: () => () => 1 / 60,
  fixed30: () => () => 1 / 30,
  fixed120: () => () => 1 / 120,
  jitter: (r) => () => 1 / 240 + r() * (1 / 20 - 1 / 240),
  spikes: (r) => (i) => (i % 53 === 0 ? 0.1 + r() * 0.3 : 1 / 60),
};

/**
 * Run the fuzzer.
 * @param {{matches?: number, seconds?: number, seed?: number, log?: Function}} [opts]
 *   matches: number of matches; seconds: simulated cap per match
 * @returns {{ok: boolean, failures: string[], stats: object}}
 */
export function runFuzz({ matches = 40, seconds = 400, seed = 1, log = () => {}, only = -1, trace = 0 } = {}) {
  const defs = [sampleFighter, extremeFighter, giantFighter, authoredFighter];
  const styles = ['masher', 'holder', 'mixed', 'ai'];
  const failures = [];
  const seen = new Set();
  const stats = { matches: 0, simSeconds: 0, steps: 0, events: 0, rounds: 0, hits: 0, kos: 0, doubleKos: 0, timeUps: 0, cinematics: 0, freezes: 0, projectiles: 0 };
  const t0 = Date.now();

  for (let i = 0; i < matches; i++) {
    const r = makeRng(seed * 7919 + i);
    const pick = (a) => a[Math.floor(r() * a.length)];
    const fd = [pick(defs), pick(defs)];
    const st = [pick(styles), pick(styles)];
    const dtName = pick(Object.keys(DT_PATTERNS));
    const dtOf = DT_PATTERNS[dtName](r);
    const rules = {};
    if (r() < 0.5) rules.introTime = 0;
    if (r() < 0.3) rules.roundTime = 10 + Math.floor(r() * 30);
    if (r() < 0.2) rules.block = { chipCanKO: true };
    if (r() < 0.2) rules.maxSubstep = 1 / 120;
    if (r() < 0.2) rules.meters = { fpRegen: 40, ultDeal: 0.5, ultTake: 0.5 };
    if (only >= 0 && i !== only) continue;
    const tag = `fuzz ${i} (${fd.map((d) => d.id).join(' vs ')}, ${st.join('/')}, dt ${dtName}, rules ${JSON.stringify(rules)})`;
    const recent = [];
    const fail = (msg) => {
      const key = msg.replace(/[-\d.]+/g, '#');
      if (seen.has(key)) return;
      seen.add(key);
      if (failures.length < 40) failures.push(`${tag}: ${msg}`);
      if (trace) log(`--- ${tag}: ${msg}\n    last events:\n      ${recent.join('\n      ')}`);
    };
    try {
      const controllers = st.map((s, k) => (s === 'ai' ? createAIController({ difficulty: pick(['easy', 'normal', 'hard', 'nightmare']) }) : createRandomController(seed * 1000 + i * 2 + k, s)));
      const m = createMatch({ fighters: fd, controllers, rules, rng: seed * 31 + i });
      const R = m.rules;
      // ---------------------------------------------------------------- event checks
      let lastTime = -Infinity;
      const lastState = [m.fighters[0].state, m.fighters[1].state];
      const openMove = [null, null];
      const proj = new Map(); // id -> 'alive' | 'dead'
      const freezeOpen = [false, false];
      let cineOpen = false;
      let koThisRound = [false, false];
      const lastChange = [0, 0];
      const lateHits = [0, 0]; // match time of the last state change or move start per fighter (stuck detection)
      m.on('*', (name, p) => {
        if ((name === 'state' || name === 'moveStart') && (p.fighter === 0 || p.fighter === 1)) lastChange[p.fighter] = p.time;
        if (name === 'hit' && (p.defender === 0 || p.defender === 1)) {
          // contact is activity (long hit-stops, block strings): not a stuck state
          lastChange[p.defender] = lastChange[p.attacker] = p.time;
          // the combo cap: past rules.combo.maxTime every hit becomes a (non-juggleable) knockdown, so at most the
          // converting hit and one wall-bounce follow-up may land late in a combo
          const d = m.fighters[p.defender];
          if (!p.blocked && d.recv.active && d.recv.time > R.combo.maxTime + 0.7 && ++lateHits[p.defender] > 2) fail(`${lateHits[p.defender]} hits landed after the ${R.combo.maxTime} s combo cap`);
        }
        if (name === 'comboEnd') lateHits[p.defender] = 0;
        if (trace && name !== 'meter' && name !== 'projectileMove') { recent.push(`${p.time.toFixed(3)} ${name} ${JSON.stringify(p).slice(0, 160)}`); if (recent.length > trace) recent.shift(); }
        stats.events++;
        if (!KNOWN.has(name)) fail(`unknown event '${name}'`);
        if (!p || typeof p !== 'object') { fail(`${name}: payload is not an object`); return; }
        if (!Number.isFinite(p.time)) fail(`${name}: time ${p.time}`);
        if (p.time < lastTime - 1e-12) fail(`${name}: time went back ${lastTime} -> ${p.time}`);
        lastTime = p.time;
        for (const k of IDX) if (k in p && p[k] !== 0 && p[k] !== 1) fail(`${name}.${k} = ${p[k]}`);
        for (const k of ['x', 'y', 'damage', 'hitstop']) if (k in p && p[k] !== null && !Number.isFinite(p[k])) fail(`${name}.${k} = ${p[k]}`);
        switch (name) {
          case 'state':
            if (p.from !== lastState[p.fighter]) fail(`state chain broken for ${p.fighter}: ${lastState[p.fighter]} then ${p.from}->${p.to}`);
            if (!STATE_SET.has(p.to)) fail(`unknown state ${p.to}`);
            lastState[p.fighter] = p.to;
            break;
          case 'moveStart':
            if (openMove[p.fighter] !== null) fail(`moveStart ${p.move} while ${openMove[p.fighter]} is still open`);
            openMove[p.fighter] = p.move;
            break;
          case 'moveEnd':
            if (openMove[p.fighter] !== p.move) fail(`moveEnd ${p.move} but open is ${openMove[p.fighter]}`);
            openMove[p.fighter] = null;
            break;
          case 'projectileSpawn':
            if (proj.has(p.id)) fail(`projectile id ${p.id} spawned twice`);
            proj.set(p.id, 'alive');
            stats.projectiles++;
            break;
          case 'projectileActive': case 'projectileMove': case 'projectileHit':
            if (proj.get(p.id) !== 'alive' && !(name === 'projectileHit' && proj.get(p.id) === 'dead')) fail(`${name} for ${proj.has(p.id) ? 'dead' : 'unknown'} projectile`);
            break;
          case 'projectileExpire':
            if (proj.get(p.id) !== 'alive') fail(`projectileExpire for ${proj.has(p.id) ? 'dead' : 'unknown'} projectile (${p.reason})`);
            proj.set(p.id, 'dead');
            break;
          case 'projectileClash':
            if (proj.get(p.a) !== 'alive' || proj.get(p.b) !== 'alive') fail('projectileClash with a dead projectile');
            break;
          case 'superFreezeStart':
            if (freezeOpen[p.fighter]) fail('superFreezeStart twice');
            freezeOpen[p.fighter] = true;
            stats.freezes++;
            break;
          case 'superFreezeEnd':
            if (!freezeOpen[p.fighter]) fail('superFreezeEnd without start');
            freezeOpen[p.fighter] = false;
            break;
          case 'cinematicStart':
            if (cineOpen) fail('cinematicStart while a lock is running');
            cineOpen = true;
            stats.cinematics++;
            break;
          case 'cinematicTick':
            if (!cineOpen) fail('cinematicTick outside a lock');
            break;
          case 'cinematicEnd':
            if (!cineOpen) fail('cinematicEnd without start');
            cineOpen = false;
            break;
          case 'hit':
            stats.hits++;
            if (p.attacker === p.defender) fail('hit on self');
            if (p.damage < 0 || p.chip < 0) fail(`negative damage ${p.damage}/${p.chip}`);
            if (p.blocked && p.armoured) fail('hit both blocked and armoured');
            if (p.ko && !m.fighters[p.defender]) fail('ko flag on a missing fighter');
            break;
          case 'ko':
            if (koThisRound[p.fighter]) fail(`fighter ${p.fighter} KO'd twice in a round`);
            koThisRound[p.fighter] = true;
            stats.kos++;
            break;
          case 'roundStart':
            koThisRound = [false, false];
            if (freezeOpen[0] || freezeOpen[1]) fail('roundStart with an open super-freeze');
            for (const [id, s] of proj) if (s === 'alive') fail(`projectile ${id} survives into a new round`);
            break;
          case 'roundEnd':
            stats.rounds++;
            if (p.reason === 'doubleKo') stats.doubleKos++;
            if (p.reason === 'time') stats.timeUps++;
            break;
          case 'meter':
            if (p.value < -1e-9 || p.value > p.max + 1e-9) fail(`meter ${p.kind} ${p.value} outside [0, ${p.max}]`);
            break;
          default:
        }
      });
      // ---------------------------------------------------------------- state checks
      const maxCine = Math.max(...m.defs.flatMap((d) => Object.values(d.moves).map((mv) => (mv.cinematic ? mv.cinematic.duration : 0))));
      const maxMove = Math.max(...m.defs.flatMap((d) => Object.values(d.moves).map((mv) => mv.duration)));
      // a combo may last rules.combo.maxTime, then its last knockdown flight; a lock its duration; a move its duration
      // the longest legitimate flight: a launch to the apex cap and back down
      const maxFlight = Math.max(...m.defs.map((d) => 2 * Math.sqrt(2 * R.juggle.apex * d.stats.height / R.gravity)));
      const stuckAfter = Math.max(R.combo.maxTime + maxFlight + 2, maxCine + 3, maxMove + 3);
      let lastRound = m.round, lastClock = m.clock, lastHp = m.fighters.map((f) => f.hp);
      let k = 0;
      const cap = seconds;
      while (m.phase !== 'end' && m.time < cap) {
        const dt = dtOf(k++);
        m.step(dt);
        stats.steps++;
        if (m.round !== lastRound) { lastRound = m.round; lastClock = m.clock; lastHp = m.fighters.map((f) => f.hp); }
        if (m.clock > lastClock + 1e-9) fail(`clock rose ${lastClock} -> ${m.clock}`);
        lastClock = m.clock;
        if (m.clock < -1e-9 || m.clock > R.roundTime + 1e-9) fail(`clock ${m.clock}`);
        for (let j = 0; j < 2; j++) {
          const f = m.fighters[j];
          for (const key of NUM) if (!Number.isFinite(f[key])) fail(`fighter.${key} = ${f[key]}`);
          const L = R.arenaHalfWidth - f.def.stats.pushWidth;
          if (Math.abs(f.x) > L + 1e-6) fail(`outside the arena (x ${f.x.toFixed(4)}, limit ${L})`);
          if (f.y < -1e-9) fail(`below the floor (y ${f.y})`);
          if (f.hp < 0 || f.hp > f.hpMax) fail(`hp ${f.hp}`);
          if (f.fp < -1e-9 || f.fp > f.fpMax + 1e-9) fail(`fp ${f.fp}`);
          if (f.ult < -1e-9 || f.ult > f.ultMax + 1e-9) fail(`ult ${f.ult}`);
          if (f.guard < -1e-9 || f.guard > f.guardMax + 1e-9) fail(`guard ${f.guard}`);
          if (f.hitstop < 0 || f.stateTime < 0 || f.dodgeCooldown < 0 || f.timer < -1e-9) fail(`negative timer (hitstop ${f.hitstop}, stateTime ${f.stateTime}, timer ${f.timer})`);
          for (const c in f.cooldowns) if (!(f.cooldowns[c] >= 0)) fail(`cooldown ${c} = ${f.cooldowns[c]}`);
          if (!STATE_SET.has(f.state)) fail(`unknown state ${f.state}`);
          if ((f.state === 'attack') !== (f.move !== null)) fail(`state ${f.state} with move ${f.move}`);
          if (f.move !== null && (f.moveData !== f.def.moves[f.move] || f.moveTime < 0 || f.moveTime > f.moveData.duration + 1e-9)) fail(`move clock ${f.moveTime} outside ${f.move}`);
          if (f.hp > lastHp[j] + 1e-9) fail(`hp rose inside a round ${lastHp[j]} -> ${f.hp}`);
          lastHp[j] = f.hp;
          if (!FREE.has(f.state) && m.time - lastChange[j] > stuckAfter) { fail(`stuck in '${f.state}' for ${stuckAfter} s (move ${f.move}, opponent ${m.fighters[1 - j].state})`); lastChange[j] = m.time; }
        }
        const [a, b] = m.fighters;
        if (a.y < 0.05 && b.y < 0.05 && !passesThrough(m, a) && !passesThrough(m, b) && Math.abs(a.x - b.x) < a.def.stats.pushWidth + b.def.stats.pushWidth - 1e-6) {
          fail(`push-boxes overlap (gap ${Math.abs(a.x - b.x).toFixed(4)}, states ${a.state}/${b.state})`);
        }
        for (const p of m.projectiles) if (!Number.isFinite(p.x) || !Number.isFinite(p.y)) fail(`projectile ${p.id} NaN`);
      }
      for (let j = 0; j < 2; j++) if ((openMove[j] === null) !== (m.fighters[j].move === null)) fail(`event stream says move ${openMove[j]}, fighter says ${m.fighters[j].move}`);
      stats.matches++;
      stats.simSeconds += m.time;
    } catch (e) {
      fail(`exception ${e && e.stack ? e.stack.split('\n').slice(0, 5).join(' | ') : e}`);
    }
  }
  const secs = (Date.now() - t0) / 1000;
  log(`\n=== FUZZ: ${stats.matches} matches, ${stats.simSeconds.toFixed(0)} simulated s, ${stats.steps} steps, ${stats.events} events in ${secs.toFixed(1)} s ===`);
  log(`rounds ${stats.rounds} (time-ups ${stats.timeUps}, double KOs ${stats.doubleKos}), hits ${stats.hits}, KOs ${stats.kos}, super-freezes ${stats.freezes}, cinematics ${stats.cinematics}, projectiles ${stats.projectiles}`);
  if (failures.length) { log('FUZZ FAILURES:'); for (const f of failures) log('  - ' + f); } else log('fuzz ok: every invariant held');
  return { ok: failures.length === 0, failures, stats };
}
