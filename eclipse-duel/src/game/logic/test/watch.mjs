// Watch an AI-vs-AI match like a commentator: an annotated timeline of every action, hit, block, whiff, punish,
// combo, ultimate and KO, followed by a per-fighter behaviour report (move mix, idle stretches, repeated-move
// streaks, whiffs, punishes, spacing). Used to judge whether each difficulty feels like an opponent.
//
//   node src/game/logic/test/watch.mjs                         normal vs hard, seed 1, the whole match
//   node src/game/logic/test/watch.mjs easy nightmare --seed 4 --rounds 1
//   node src/game/logic/test/watch.mjs hard hard --def src/fighters/kael/moves.js --quiet   (report only)

import path from 'node:path';
import url from 'node:url';
import { createMatch } from '../match.js';
import { createAIController, AI_LEVELS } from '../ai.js';
import { sampleFighter } from '../sample-fighter.js';

/**
 * Run and narrate one match.
 * @param {{levels?: string[], seed?: number, rounds?: number, defs?: object[], quiet?: boolean, log?: Function}} o
 * @returns {object} the per-fighter report
 */
export function watch({ levels = ['normal', 'hard'], seed = 1, rounds = 99, defs = [sampleFighter, sampleFighter], quiet = false, log = console.log } = {}) {
  const m = createMatch({ fighters: defs, controllers: levels.map((difficulty) => createAIController({ difficulty })), rng: seed });
  const name = (i) => `P${i + 1}(${levels[i]})`;
  const say = (t, s) => { if (!quiet) log(`${t.toFixed(2).padStart(7)}  ${s}`); };
  const dist = () => Math.abs(m.fighters[0].x - m.fighters[1].x);
  const R = [0, 1].map(() => ({
    moves: {}, starts: 0, whiffs: 0, hits: 0, blocked: 0, taken: 0, guarded: 0, perfect: 0, punishes: 0, counters: 0,
    combos: 0, maxCombo: 0, ults: 0, ultLanded: 0, dodges: 0, perfectDodges: 0, techs: 0, idle: 0, longestIdle: 0,
    streak: 0, longestStreak: 0, lastMove: null, zone: { close: 0, mid: 0, far: 0 }, fight: 0, wall: 0, guardTime: 0,
    damage: 0,
  }));
  const idleSince = [null, null];
  const pending = new Map(); // fighter -> {move, t, d, cancelFrom}
  m.on('roundStart', (e) => say(e.time, `===== ROUND ${e.round}  (rounds ${e.rounds.join('-')}) =====`));
  m.on('fightStart', (e) => say(e.time, 'FIGHT!'));
  m.on('moveStart', (e) => {
    const r = R[e.fighter];
    r.starts++;
    r.moves[e.move] = (r.moves[e.move] || 0) + 1;
    if (e.cancelFrom === null) {
      r.streak = r.lastMove === e.move ? r.streak + 1 : 1;
      r.longestStreak = Math.max(r.longestStreak, r.streak);
      r.lastMove = e.move;
    }
    if (e.group === 'ult') r.ults++;
    pending.set(e.fighter, { move: e.move, t: e.time });
    say(e.time, `${name(e.fighter)} ${e.cancelFrom ? `  -> cancels into ${e.name}` : `${e.forced ? 'counters with' : 'throws'} ${e.name}`} (${e.move}) at ${dist().toFixed(1)} m`);
  });
  m.on('moveEnd', (e) => {
    if (!e.connected && e.reason === 'complete') {
      const mv = m.defs[e.fighter].moves[e.move];
      if (mv.hits.length || mv.projectiles.length) { R[e.fighter].whiffs++; say(e.time, `${name(e.fighter)}   ...${e.move} whiffs`); }
    }
  });
  m.on('hit', (e) => {
    const a = R[e.attacker], d = R[e.defender];
    if (e.blocked) {
      a.blocked++; d.guarded++; if (e.perfect) d.perfect++;
      say(e.time, `        ${e.move} ${e.perfect ? 'PERFECT-GUARDED' : 'blocked'}${e.chip ? `, chip ${e.chip}` : ''} (gauge ${Math.round(e.guard)})${e.guardBreak ? '  GUARD BREAK!' : ''}`);
      return;
    }
    a.hits++; d.taken++; a.damage += e.damage;
    if (e.punish) a.punishes++;
    if (e.counter) a.counters++;
    const tags = [e.counter && 'COUNTER', e.punish && 'PUNISH', e.armoured && 'armoured', e.cinematic && 'LOCK!', e.clash && 'clash', e.ko && 'KO', e.front ? '' : 'from behind'].filter(Boolean).join(' ');
    say(e.time, `        ${e.move} hits ${name(e.defender)} for ${e.damage} (${e.level}${e.combo > 1 ? `, combo ${e.combo} / ${e.comboDamage}` : ''})${tags ? '  ' + tags : ''}`);
  });
  m.on('comboEnd', (e) => {
    const a = R[e.attacker];
    if (e.hits >= 2) { a.combos++; a.maxCombo = Math.max(a.maxCombo, e.hits); say(e.time, `        == ${name(e.attacker)} combo: ${e.hits} hits, ${e.damage} damage (${e.duration.toFixed(1)} s)`); }
  });
  m.on('dodge', (e) => { R[e.fighter].dodges++; say(e.time, `${name(e.fighter)} ${e.kind}${e.kind === 'dash' ? 'es in' : e.kind === 'backstep' ? 's out' : 's'} at ${dist().toFixed(1)} m`); });
  m.on('perfectDodge', (e) => { R[e.fighter].perfectDodges++; say(e.time, `        ${name(e.fighter)} PERFECT DODGE`); });
  m.on('counter', (e) => say(e.time, `        ${name(e.fighter)} COUNTER STANCE catches ${e.against}`));
  m.on('tech', (e) => { R[e.fighter].techs++; say(e.time, `        ${name(e.fighter)} tech-rolls`); });
  m.on('wallBounce', (e) => say(e.time, `        ${name(e.fighter)} WALL BOUNCE`));
  m.on('superFreezeStart', (e) => say(e.time, `${name(e.fighter)} ***** ULTIMATE: ${e.move} *****`));
  m.on('cinematicStart', (e) => { R[e.attacker].ultLanded++; say(e.time, `        ***** ${name(e.attacker)} LOCKS ${name(e.defender)} (${e.duration} s) *****`); });
  m.on('cinematicEnd', (e) => say(e.time, `        ***** lock ends: ${e.damage} damage${e.ko ? ', KO' : ''} *****`));
  m.on('ko', (e) => say(e.time, `!!!!! ${name(e.fighter)} is KNOCKED OUT by ${name(e.by)} !!!!!`));
  m.on('timeUp', (e) => say(e.time, `TIME UP (hp ${e.hp.join(' / ')})`));
  m.on('roundEnd', (e) => say(e.time, `round ${e.round}: ${e.winner < 0 ? 'draw' : name(e.winner) + ' wins'} by ${e.reason}, clock ${e.clock.toFixed(1)}`));
  m.on('matchEnd', (e) => say(e.time, `MATCH: ${e.winner < 0 ? 'draw' : name(e.winner) + ' wins'} ${e.rounds.join('-')}`));

  const dt = 1 / 60;
  while (m.phase !== 'end' && m.round <= rounds && m.time < 1200) {
    m.step(dt);
    if (m.phase !== 'fight') { idleSince[0] = idleSince[1] = null; continue; }
    const d = dist();
    for (let i = 0; i < 2; i++) {
      const f = m.fighters[i], r = R[i];
      r.fight += dt;
      r.zone[d < 1.9 ? 'close' : d < 3.5 ? 'mid' : 'far'] += dt;
      if (Math.abs(f.x) > m.rules.arenaHalfWidth - 1.5) r.wall += dt;
      if (f.state === 'guard' || f.state === 'blockstun') r.guardTime += dt;
      // idle: standing still in neutral (no walking, no guard), not reacting to anything
      if (f.state === 'idle') {
        if (idleSince[i] === null) idleSince[i] = m.time;
        r.idle += dt;
      } else if (idleSince[i] !== null) {
        const len = m.time - idleSince[i];
        r.longestIdle = Math.max(r.longestIdle, len);
        if (len > 1.0) say(m.time, `${name(i)} stood still for ${len.toFixed(1)} s`);
        idleSince[i] = null;
      }
    }
  }
  const report = R.map((r, i) => ({
    who: name(i),
    hp: m.fighters[i].hp,
    rounds: m.fighters[i].rounds,
    movesPerMin: +(r.starts / (r.fight / 60)).toFixed(1),
    mix: Object.entries(r.moves).sort((a, b) => b[1] - a[1]).map(([k, v]) => `${k} ${v}`).join(', '),
    whiffRate: +(r.whiffs / Math.max(1, r.starts)).toFixed(2),
    hits: r.hits, blocked: r.blocked, taken: r.taken, guarded: r.guarded, perfect: r.perfect,
    punishes: r.punishes, counterHits: r.counters, combos: r.combos, maxCombo: r.maxCombo, damage: r.damage,
    ults: r.ults, ultLanded: r.ultLanded, dodges: r.dodges, perfectDodges: r.perfectDodges, techs: r.techs,
    idleShare: +(r.idle / r.fight).toFixed(2), longestIdle: +r.longestIdle.toFixed(2), longestSameMoveStreak: r.longestStreak,
    guardShare: +(r.guardTime / r.fight).toFixed(2), wallShare: +(r.wall / r.fight).toFixed(2),
    zones: Object.fromEntries(Object.entries(r.zone).map(([k, v]) => [k, +(v / r.fight).toFixed(2)])),
  }));
  log('\nREPORT\n' + report.map((r) => JSON.stringify(r)).join('\n'));
  return report;
}

// CLI
if (import.meta.url === url.pathToFileURL(process.argv[1] || '').href) {
  const args = process.argv.slice(2);
  const val = (k, d) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : d; };
  const lv = args.filter((a) => AI_LEVELS[a]);
  let defs;
  const mod = val('--def', null);
  if (mod) {
    const x = await import(url.pathToFileURL(path.resolve(mod)).href);
    const def = x.default && x.default.moves ? x.default : Object.values(x).find((v) => v && typeof v === 'object' && v.moves);
    defs = [def, def];
  }
  watch({ levels: lv.length === 2 ? lv : lv.length === 1 ? [lv[0], lv[0]] : undefined, seed: Number(val('--seed', 1)), rounds: Number(val('--rounds', 99)), defs, quiet: args.includes('--quiet') });
}
