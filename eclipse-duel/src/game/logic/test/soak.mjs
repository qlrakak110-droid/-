// Soak test: AI-vs-AI matches across every difficulty pair. Asserts no exceptions, no NaN, no broken invariants and
// no stuck states (every round ends), and prints the statistics used to tune the sample fighter and the AI.

import { createMatch } from '../match.js';
import { createAIController } from '../ai.js';
import { passesThrough } from '../fighter.js';
import { sampleFighter } from '../sample-fighter.js';

const LEVELS = ['easy', 'normal', 'hard', 'nightmare'];
const FREE = new Set(['idle', 'walk', 'guard', 'intro', 'victory', 'defeat', 'ko']);
const NUM = ['x', 'y', 'vx', 'vy', 'hp', 'fp', 'ult', 'guard', 'moveTime', 'timer', 'stateTime', 'hitstop'];
const STUCK_AFTER = 8;

/**
 * Run the soak.
 * @param {{matches?: number, log?: Function, def?: object, dt?: number}} [opts]
 * @returns {{ok: boolean, stats: object, failures: string[]}}
 */
export function runSoak({ matches = 300, log = () => {}, def = sampleFighter, dt = 1 / 60 } = {}) {
  const pairs = [];
  for (let i = 0; i < LEVELS.length; i++) for (let j = i; j < LEVELS.length; j++) pairs.push([LEVELS[i], LEVELS[j]]);
  const S = {
    matches: 0, rounds: 0, roundLen: [], ko: 0, time: 0, draws: 0, matchDraws: 0,
    wins: {}, games: {}, pair: {}, moves: {}, movesBy: {}, fightTime: {}, states: {}, stateTotal: 0,
    hits: 0, blocked: 0, perfectGuards: 0, guardBreaks: 0, perfectDodges: 0, counters: 0, armoured: 0, counterHits: 0,
    ults: 0, cinematics: 0, cineKO: 0, projectiles: 0, clashes: 0, techs: 0, wallBounces: 0, denied: 0,
    combos: 0, comboHits: 0, comboDamage: 0, maxComboHits: 0, maxComboDamage: 0, steps: 0,
  };
  for (const l of LEVELS) { S.wins[l] = 0; S.games[l] = 0; S.movesBy[l] = 0; S.fightTime[l] = 0; }
  const failures = [];
  const fail = (msg) => { if (failures.length < 30) failures.push(msg); };
  const t0 = Date.now();

  for (let i = 0; i < matches; i++) {
    const pr = pairs[i % pairs.length];
    const swap = Math.floor(i / pairs.length) % 2 === 1;
    const lv = swap ? [pr[1], pr[0]] : [pr[0], pr[1]];
    const tag = `match ${i} (${lv[0]} vs ${lv[1]}, seed ${9000 + i})`;
    try {
      const m = createMatch({ fighters: [def, def], controllers: lv.map((d) => createAIController({ difficulty: d })), rng: 9000 + i });
      const pk = lv.join(' vs ');
      if (!S.pair[pk]) S.pair[pk] = { games: 0, w0: 0, w1: 0, draws: 0 };
      m.on('roundEnd', (p) => {
        S.rounds++;
        S.roundLen.push(m.rules.roundTime - p.clock);
        if (p.reason === 'time') S.time++; else S.ko++;
        if (p.winner < 0) S.draws++;
      });
      m.on('matchEnd', (p) => {
        S.pair[pk].games++;
        if (p.winner < 0) { S.matchDraws++; S.pair[pk].draws++; } else { S.wins[lv[p.winner]]++; S.pair[pk]['w' + p.winner]++; }
        S.games[lv[0]]++; S.games[lv[1]]++;
      });
      m.on('moveStart', (p) => { S.moves[p.move] = (S.moves[p.move] || 0) + 1; S.movesBy[lv[p.fighter]]++; if (p.group === 'ult') S.ults++; });
      m.on('hit', (p) => {
        if (p.blocked) { S.blocked++; if (p.perfect) S.perfectGuards++; } else S.hits++;
        if (p.guardBreak) S.guardBreaks++;
        if (p.armoured) S.armoured++;
        if (p.counter) S.counterHits++;
      });
      m.on('perfectDodge', () => S.perfectDodges++);
      m.on('counter', () => S.counters++);
      m.on('cinematicStart', () => S.cinematics++);
      m.on('cinematicEnd', (p) => { if (p.ko) S.cineKO++; });
      m.on('projectileSpawn', () => S.projectiles++);
      m.on('projectileClash', () => S.clashes++);
      m.on('tech', () => S.techs++);
      m.on('wallBounce', () => S.wallBounces++);
      m.on('moveDenied', () => S.denied++);
      let cineDmg = 0;
      m.on('cinematicTick', (p) => { cineDmg += p.damage; });
      m.on('comboEnd', (p) => {
        S.combos++; S.comboHits += p.hits; S.comboDamage += p.damage;
        S.maxComboHits = Math.max(S.maxComboHits, p.hits);
        S.maxComboDamage = Math.max(S.maxComboDamage, p.damage - cineDmg);
        cineDmg = 0;
      });

      const since = [0, 0], cur = ['intro', 'intro'];
      const capTime = m.rules.maxRounds * (m.rules.roundTime + 40);
      let lastPhase = m.phase, phaseSince = 0;
      while (m.phase !== 'end') {
        m.step(dt);
        S.steps++;
        if (m.time > capTime) { fail(`${tag}: match did not end after ${capTime} s (phase ${m.phase}, round ${m.round})`); break; }
        if (m.phase !== lastPhase) { lastPhase = m.phase; phaseSince = m.time; }
        if (m.phase === 'fight' && m.time - phaseSince > m.rules.roundTime + 30) { fail(`${tag}: round ${m.round} fight phase lasted > ${m.rules.roundTime + 30} s`); break; }
        for (let k = 0; k < 2; k++) {
          const f = m.fighters[k];
          for (const key of NUM) if (!Number.isFinite(f[key])) fail(`${tag}: fighter ${k}.${key} = ${f[key]} at t ${m.time.toFixed(2)}`);
          if (Math.abs(f.x) > m.rules.arenaHalfWidth + 1e-6) fail(`${tag}: fighter ${k} outside the arena (x ${f.x})`);
          if (f.y < -1e-9) fail(`${tag}: fighter ${k} below the floor`);
          if (f.hp < 0 || f.hp > f.hpMax || f.fp < -1e-9 || f.fp > f.fpMax + 1e-9 || f.ult < 0 || f.ult > f.ultMax + 1e-9 || f.guard < -1e-9 || f.guard > f.guardMax + 1e-9) fail(`${tag}: fighter ${k} meter out of range`);
          if (f.recv.juggle > m.rules.juggle.limit + 2) fail(`${tag}: fighter ${k} juggle ${f.recv.juggle}`);
          if (f.state !== cur[k]) { cur[k] = f.state; since[k] = m.time; }
          else if (!FREE.has(f.state) && m.time - since[k] > STUCK_AFTER) { fail(`${tag}: fighter ${k} stuck in '${f.state}' for ${STUCK_AFTER} s (move ${f.move})`); since[k] = m.time; }
          S.states[f.state] = (S.states[f.state] || 0) + 1;
          S.stateTotal++;
          if (m.phase === 'fight') S.fightTime[lv[k]] += dt;
        }
        const [a, b] = m.fighters;
        if (a.y < 0.05 && b.y < 0.05 && !passesThrough(m, a) && !passesThrough(m, b) && Math.abs(a.x - b.x) < a.def.stats.pushWidth + b.def.stats.pushWidth - 0.02) {
          fail(`${tag}: push-boxes overlap (gap ${Math.abs(a.x - b.x).toFixed(3)}) at t ${m.time.toFixed(2)}`);
        }
        for (const p of m.projectiles) if (!Number.isFinite(p.x) || !Number.isFinite(p.y)) fail(`${tag}: projectile ${p.id} NaN`);
      }
      S.matches++;
    } catch (e) {
      fail(`${tag}: exception ${e && e.stack ? e.stack.split('\n').slice(0, 4).join(' | ') : e}`);
    }
  }

  const secs = (Date.now() - t0) / 1000;
  const stats = summarize(S, secs);
  print(stats, S, log);
  const checks = sanity(stats, S);
  for (const c of checks) if (!c.ok) fail(`sanity: ${c.what} (${c.value})`);
  if (failures.length) { log('\nSOAK FAILURES:'); for (const f of failures) log('  - ' + f); }
  else log(`\nsoak ok: ${S.matches} matches, ${S.rounds} rounds, ${S.steps} steps in ${secs.toFixed(1)} s (${Math.round(S.steps / secs)} steps/s)`);
  return { ok: failures.length === 0, stats, failures };
}

function summarize(S, secs) {
  const len = S.roundLen.slice().sort((a, b) => a - b);
  const totalMoves = Object.values(S.moves).reduce((a, b) => a + b, 0);
  const share = (k) => (S.states[k] || 0) / S.stateTotal;
  return {
    matches: S.matches,
    rounds: S.rounds,
    avgRound: len.reduce((a, b) => a + b, 0) / Math.max(1, len.length),
    medianRound: len[Math.floor(len.length / 2)] || 0,
    p10Round: len[Math.floor(len.length * 0.1)] || 0,
    p90Round: len[Math.floor(len.length * 0.9)] || 0,
    koRate: S.ko / Math.max(1, S.rounds),
    timeRate: S.time / Math.max(1, S.rounds),
    blockedRate: S.blocked / Math.max(1, S.blocked + S.hits),
    winRate: Object.fromEntries(Object.keys(S.wins).map((l) => [l, S.wins[l] / Math.max(1, S.games[l])])),
    movesPerMin: Object.fromEntries(Object.keys(S.movesBy).map((l) => [l, S.movesBy[l] / Math.max(1e-9, S.fightTime[l] / 60)])),
    moveShare: Object.fromEntries(Object.entries(S.moves).sort((a, b) => b[1] - a[1]).map(([k, v]) => [k, v / totalMoves])),
    stateShare: Object.fromEntries(Object.keys(S.states).sort((a, b) => S.states[b] - S.states[a]).map((k) => [k, share(k)])),
    neutralShare: share('idle') + share('walk') + share('guard') + share('dash') + share('backstep') + share('dodge') + share('roll'),
    attackShare: share('attack'),
    guardShare: share('guard') + share('blockstun'),
    avgCombo: { hits: S.comboHits / Math.max(1, S.combos), damage: S.comboDamage / Math.max(1, S.combos) },
    perRound: {
      combos: S.combos / Math.max(1, S.rounds), guardBreaks: S.guardBreaks / Math.max(1, S.rounds), cinematics: S.cinematics / Math.max(1, S.rounds),
      ults: S.ults / Math.max(1, S.rounds), perfectGuards: S.perfectGuards / Math.max(1, S.rounds), perfectDodges: S.perfectDodges / Math.max(1, S.rounds),
      counters: S.counters / Math.max(1, S.rounds), projectiles: S.projectiles / Math.max(1, S.rounds), techs: S.techs / Math.max(1, S.rounds),
    },
    ultHitRate: S.cinematics / Math.max(1, S.ults),
    secs,
  };
}

const pct = (v) => (v * 100).toFixed(1) + '%';

function print(st, S, log) {
  log('\n=== SOAK: AI vs AI ===');
  log(`matches ${st.matches}, rounds ${st.rounds}; round length avg ${st.avgRound.toFixed(1)} s, median ${st.medianRound.toFixed(1)}, p10 ${st.p10Round.toFixed(1)}, p90 ${st.p90Round.toFixed(1)}`);
  log(`round ends: KO ${pct(st.koRate)}, time-up ${pct(st.timeRate)}, drawn rounds ${S.draws}, drawn matches ${S.matchDraws}`);
  log('win rate by difficulty: ' + Object.entries(st.winRate).map(([k, v]) => `${k} ${pct(v)}`).join(', '));
  log('pairs (P1 wins - P2 wins - draws): ' + Object.entries(S.pair).map(([k, v]) => `${k} ${v.w0}-${v.w1}-${v.draws}`).join('; '));
  log('moves per minute of fight: ' + Object.entries(st.movesPerMin).map(([k, v]) => `${k} ${v.toFixed(0)}`).join(', '));
  log('move usage: ' + Object.entries(st.moveShare).map(([k, v]) => `${k} ${pct(v)}`).join(', '));
  log(`time share: attack ${pct(st.attackShare)}, neutral ${pct(st.neutralShare)} (guarding ${pct(st.guardShare)}); ` + Object.entries(st.stateShare).slice(0, 12).map(([k, v]) => `${k} ${pct(v)}`).join(' '));
  log(`contacts: ${S.hits} hits, ${S.blocked} blocked (${pct(st.blockedRate)}), armoured ${S.armoured}, counter-hits ${S.counterHits}`);
  log(`combos: avg ${st.avgCombo.hits.toFixed(1)} hits / ${st.avgCombo.damage.toFixed(0)} dmg, max ${S.maxComboHits} hits / ${S.maxComboDamage} dmg (excl. cinematic)`);
  const pr = st.perRound;
  log(`per round: combos ${pr.combos.toFixed(1)}, ults ${pr.ults.toFixed(2)} (cinematic ${pr.cinematics.toFixed(2)}, ult hit rate ${pct(st.ultHitRate)}), guard breaks ${pr.guardBreaks.toFixed(2)}, perfect guards ${pr.perfectGuards.toFixed(2)}, perfect dodges ${pr.perfectDodges.toFixed(2)}, counter stances ${pr.counters.toFixed(2)}, projectiles ${pr.projectiles.toFixed(1)}, tech rolls ${pr.techs.toFixed(2)}`);
  log(`other: clashes ${S.clashes}, wall bounces ${S.wallBounces}, cinematic KOs ${S.cineKO}, denied presses ${S.denied}`);
}

/** Broad "looks like a real fight" checks (the tuning targets). */
function sanity(st, S) {
  const used = Object.keys(sampleFighter.moves).filter((id) => !S.moves[id]);
  const top = Object.values(st.moveShare)[0] || 0;
  return [
    { what: 'average round length within 20..60 s', ok: st.avgRound >= 20 && st.avgRound <= 60, value: st.avgRound.toFixed(1) },
    { what: 'every move of the sample fighter is used', ok: used.length === 0, value: used.join(',') || 'all' },
    { what: 'no single move above 35 % of all moves', ok: top <= 0.35, value: pct(top) },
    { what: 'not a pure turtle: guarding below 35 % of the time', ok: st.guardShare < 0.35, value: pct(st.guardShare) },
    { what: 'not a pure rush: blocked contacts above 20 %', ok: st.blockedRate > 0.2, value: pct(st.blockedRate) },
    { what: 'nightmare beats easy most of the time', ok: (S.pair['easy vs nightmare'] ? (S.pair['easy vs nightmare'].w1 + (S.pair['nightmare vs easy'] ? S.pair['nightmare vs easy'].w0 : 0)) / Math.max(1, S.pair['easy vs nightmare'].games + (S.pair['nightmare vs easy'] ? S.pair['nightmare vs easy'].games : 0)) : 1) >= 0.7, value: 'see pairs' },
    { what: 'difficulty ordering: easy < normal < hard <= nightmare win rates', ok: st.winRate.easy < st.winRate.normal && st.winRate.normal < st.winRate.hard && st.winRate.hard <= st.winRate.nightmare + 0.05, value: Object.values(st.winRate).map(pct).join('/') },
  ];
}
