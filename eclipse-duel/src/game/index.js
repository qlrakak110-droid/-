// Game: flow (title -> select -> vs -> match -> result), match sessions, pause, quality, attract mode and the test API.
//
//   const game = await createGame(ctx);     // ctx.game; loads the roster, defines presets, compiles, shows the title
//   URL flags: #demo=kael,iska[,hard]  CPU vs CPU forever      #fight=kael,vorn[,normal]  straight into a match (P1 human)
//              #seed=N                 match / RNG seed         #training=kael,iska         training (infinite meters, idle dummy)
// Test API: window.__ED.game (see README.md "Test API").

import * as SHOTS from '../cam/shots.js';
import { ROSTER, rosterEntry, loadRoster } from '../fighters/registry.js';
import { startMove } from './logic/fighter.js';
import { createIdleController, createAIController } from './logic/index.js';
import { createFx, fxDefs } from './fx.js';
import { createSession } from './session.js';

const ARENA = { arena: '일식의 폐허', arenaEn: 'ECLIPSE RUINS' };
const DIFFS = ['easy', 'normal', 'hard', 'nightmare'];

/**
 * @param {object} ctx app context with env, vfx, cam, audio, input, ui created
 * @param {{ profiler?: object }} [opts]
 */
export async function createGame(ctx, opts = {}) {
  const fighters = await loadRoster();
  const fx = createFx(ctx);
  const game = {
    ctx, fighters, fx, roster: ROSTER,
    state: 'boot',
    session: null,
    pick: { p1: 'kael', cpu: 'iska', difficulty: 'normal' },
    pending: null,
    timers: [],
  };
  ctx.game = game;

  // fighter setup hooks (preset definitions) run once, before the VFX programs are compiled
  for (const f of fighters.values()) {
    const setup = f.present && f.present.setup;
    if (typeof setup === 'function') {
      try { setup({ ctx, vfx: ctx.vfx, fx, element: f.element, palette: fx.paletteOf(f.element) }); } catch (e) { console.warn('[ed] present.setup of ' + f.id + ': ' + e.message); }
    }
  }
  if (ctx.vfx) ctx.vfx.prewarm(fxDefs());

  // ---- timers on real time (frame-driven, so test captures are exact) -----------------------------------------------
  function after(sec, fn) { const t = { left: sec, fn }; game.timers.push(t); return t; }
  ctx.onUpdate((dg, dr) => {
    if (game.pending) { const p = game.pending; game.pending = null; p(); }
    for (let i = game.timers.length - 1; i >= 0; i--) {
      const t = game.timers[i];
      if (ctx.time.baseScale === 0 && !t.realPause) continue;
      t.left -= dr;
      if (t.left <= 0) { game.timers.splice(i, 1); t.fn(); }
    }
  }, ctx.ORDER.GAME - 1);
  const clearTimers = () => { game.timers.length = 0; };

  // ---- sessions -----------------------------------------------------------------------------------------------------
  function buildSession(p1, p2, mode, extra = {}) {
    if (game.session) { game.session.dispose(); game.session = null; }
    if (ctx.cam) ctx.cam.stop(0);
    const s = createSession(ctx, [fighters.get(p1) || fighters.get('kael'), fighters.get(p2) || fighters.get('iska')], {
      mode, fx, difficulty: extra.difficulty || game.pick.difficulty, difficulty1: extra.difficulty1, seed: extra.seed,
      rules: mode === 'training' ? { roundTime: 999 } : undefined,
      onEnd: (result) => onMatchEnd(result),
    });
    game.session = s;
    compile();
    return s;
  }

  /** Compile every program now (both fighters, arena, VFX) so nothing compiles mid-fight. */
  function compile() {
    const r = ctx.renderer;
    try {
      r.compile(ctx.scene, ctx.camera);
      if (ctx.post && ctx.post.distortionScene) r.compile(ctx.post.distortionScene, ctx.camera);
    } catch (e) { console.warn('[ed] compile: ' + e.message); }
  }

  function showcase(p1 = game.pick.p1, p2 = game.pick.cpu) {
    const s = buildSession(p1, p2, 'showcase');
    s.start();
    for (const a of s.actors) { a.cine = true; a.play(a.clips.state('idle').name, { fade: 0 }); }
    if (ctx.cam) {
      const loop = (dir) => {
        if (game.session !== s) return;
        ctx.cam.play([SHOTS.orbitSweep({ dur: 26, clock: 'real', from: -32 * dir, to: 32 * dir, radius: [8.8, 8.2], height: [1.5, 2.3], look: 1.25, fov: 36, ease: 'inOutSine' })],
          { anchor: 0, blendOut: false, hud: false, onDone: (ok) => { if (ok) loop(-dir); } });
      };
      ctx.cam.snap();
      loop(1);
    }
    return s;
  }

  // ---- screens / flow -------------------------------------------------------------------------------------------------
  function title() {
    clearTimers();
    resumeTime();
    game.state = 'title';
    if (!game.session || game.session.mode !== 'showcase') showcase();
    ctx.ui.show('title', { quality: ctx.quality.tier });
    if (ctx.audio) ctx.audio.music('title', { fade: 1.5 });
  }

  function select() {
    clearTimers();
    resumeTime();
    game.state = 'select';
    if (!game.session || game.session.mode !== 'showcase') showcase();
    ctx.ui.show('select', { roster: ROSTER, p1: game.pick.p1, cpu: game.pick.cpu, difficulty: game.pick.difficulty });
    if (ctx.audio) ctx.audio.music('title', { fade: 1.5 });
  }

  function versus(p1, cpu, difficulty) {
    game.pick = { p1, cpu, difficulty };
    game.state = 'vs';
    ctx.ui.show('vs', { p1: rosterEntry(p1), p2: rosterEntry(cpu), difficulty, ...ARENA });
    // build next frame so the splash shows first (character build + compile happen behind it)
    game.pending = () => { buildSession(p1, cpu, 'versus', { difficulty }); };
  }

  function beginMatch() {
    if (game.pending) { const p = game.pending; game.pending = null; p(); }
    const s = game.session;
    if (!s || s.mode === 'showcase') return;
    game.state = 'match';
    ctx.ui.show('hud', { p1: rosterEntry(s.fighters[0].id), p2: rosterEntry(s.fighters[1].id), roundsToWin: s.match.rules.roundsToWin });
    s.start();
  }

  /** Straight into a match (flags, test API). mode: 'versus' | 'demo' | 'training'. */
  function quickMatch(p1, p2, mode = 'versus', o = {}) {
    clearTimers();
    resumeTime();
    game.pick = { p1, cpu: p2, difficulty: o.difficulty || game.pick.difficulty };
    buildSession(p1, p2, mode, o);
    game.state = 'match';
    ctx.ui.show('hud', { p1: rosterEntry(p1), p2: rosterEntry(p2), roundsToWin: game.session.match.rules.roundsToWin });
    game.session.start();
    if (mode === 'training') training(game.session);
    return game.session;
  }

  function training(s) {
    const id = ctx.onUpdate(() => {
      if (game.session !== s) { id(); return; }
      const m = s.match;
      for (let i = 0; i < 2; i++) { m.setMeter(i, 'fp', 100); m.setMeter(i, 'ult', 100); if (m.fighters[i].hp < m.fighters[i].hpMax * 0.25 && m.phase === 'fight') m.setMeter(i, 'hp', m.fighters[i].hpMax); }
    }, ctx.ORDER.GAME + 1);
  }

  function onMatchEnd(result) {
    const s = game.session;
    after(1.2, () => {
      if (game.session !== s) return;
      game.state = 'result';
      ctx.ui.show('result', result);
      if (s.mode === 'demo') after(4, () => { if (game.session === s) { game.state = 'match'; ctx.ui.show('hud', { p1: rosterEntry(s.fighters[0].id), p2: rosterEntry(s.fighters[1].id) }); s.rematch(); } });
    });
  }

  function rematch() {
    const s = game.session;
    if (!s || s.mode === 'showcase') return select();
    clearTimers();
    game.state = 'match';
    ctx.ui.show('hud', { p1: rosterEntry(s.fighters[0].id), p2: rosterEntry(s.fighters[1].id), roundsToWin: s.match.rules.roundsToWin });
    s.rematch();
  }

  // ---- pause ----------------------------------------------------------------------------------------------------------
  function pause() {
    if (game.state !== 'match') return;
    game.state = 'pause';
    ctx.time.baseScale = 0;
    const s = game.session;
    ctx.ui.show('pause', { p1: rosterEntry(s.fighters[0].id), p2: rosterEntry(s.fighters[1].id), quality: ctx.quality.tier });
    if (ctx.input) ctx.input.clearVirtual(0);
    if (ctx.audio) ctx.audio.duck(0.7, 0.6);
  }
  function resume() {
    if (game.state !== 'pause') return;
    game.state = 'match';
    resumeTime();
    ctx.ui.show('hud');
  }
  function resumeTime() { ctx.time.baseScale = 1; }

  /** Quality switch: stored in localStorage + the URL hash, then the page reloads with the new tier. */
  function setQuality(q) {
    if (q === ctx.quality.tier || ctx.test) return;
    try { localStorage.setItem('ed.quality', q); } catch (e) { /* storage blocked */ }
    try {
      const parts = String(location.hash || '').replace(/^#/, '').split('&').filter((p) => p && !/^q=/.test(p));
      parts.push('q=' + q);
      history.replaceState(null, '', location.pathname + location.search + '#' + parts.join('&'));
      location.reload();
    } catch (e) { /* no reload possible: the new tier applies next visit */ }
  }

  const ui = ctx.ui;
  ui.on('start', () => { if (game.state === 'title') select(); });
  ui.on('back', (from) => { if (from === 'select') title(); });
  ui.on('pick', ({ p1, cpu, difficulty }) => versus(p1, cpu, difficulty));
  ui.on('vsDone', () => { if (game.state === 'vs') beginMatch(); });
  ui.on('pause', () => pause());
  ui.on('resume', () => resume());
  ui.on('rematch', () => rematch());
  ui.on('select', () => { resumeTime(); select(); });
  ui.on('toTitle', () => { resumeTime(); title(); });
  ui.on('quality', (q) => setQuality(q));
  if (typeof document !== 'undefined') document.addEventListener('visibilitychange', () => { if (document.hidden) pause(); });

  // ---- test API ---------------------------------------------------------------------------------------------------------
  const m = () => game.session && game.session.match;
  const api = {
    get state() { return game.state; },
    get screen() { return ctx.ui.screen; },
    roster: () => ROSTER.map((r) => ({ id: r.id, ...fighters.get(r.id).sources, stub: fighters.get(r.id).stub })),
    snapshot: () => (m() ? m().snapshot() : null),
    match: m,
    session: () => game.session,
    events: () => (game.session ? game.session.log.slice() : []),
    /** start a match directly: mode 'versus' | 'demo' | 'training' */
    start: (p1 = 'kael', p2 = 'iska', o = {}) => { quickMatch(p1, p2, o.mode || 'demo', o); return api.snapshot(); },
    title, select, versus, pause, resume, rematch,
    /** advance the match to the 'fight' phase (skips the round intro) */
    skipIntro() {
      const mm = m();
      if (!mm) return null;
      for (let k = 0; k < 600 && mm.phase !== 'fight'; k++) ctx.frame(1 / 60, false);
      return mm.phase;
    },
    /** force fighter i into a move now (costs ignored), e.g. forceMove(0, 'heavy') */
    forceMove(i, id) {
      const mm = m();
      if (!mm || !mm.fighters[i].def.moves[id]) return false;
      startMove(mm, mm.fighters[i], id, { forced: true });
      return true;
    },
    /** move id of fighter i for a MOVES.md slot ('light1' 'heavy' 'fheavy' 'dheavy' 'skill1'..'skill3' 'ult') */
    moveFor(i, slot) { const s = game.session; return s ? s.actors[i].clips.slots[slot] || null : null; },
    /** set meters: meters(0, { hp: 300, fp: 100, ult: 100, guard: 100 }) */
    meters(i, o) { const mm = m(); if (!mm) return; for (const k in o) mm.setMeter(i, k, o[k]); },
    place(i, x, facing) { const mm = m(); if (mm) mm.place(i, x, facing); },
    /** controller of fighter i: 'idle' | 'ai' (difficulty) | 'human' */
    controller(i, kind = 'idle', difficulty = 'normal') {
      const mm = m();
      if (!mm) return;
      mm.setController(i, kind === 'ai' ? createAIController({ difficulty }) : kind === 'human' ? null : createIdleController());
    },
    /** jump to a round: rounds won [a, b] and round number n (restarts that round) */
    round(n = 1, wins = [0, 0]) {
      const mm = m();
      if (!mm) return;
      mm.fighters[0].rounds = wins[0]; mm.fighters[1].rounds = wins[1];
      mm.round = n;
      mm.restartRound();
    },
    /** hold a pose: actor i plays `clip` frozen at clip time t (cancel with pose(i, null)) */
    pose(i, clip, t = 0) {
      const a = game.session && game.session.actors[i];
      if (!a) return;
      if (!clip) { a.cine = false; a.key = ''; return; }
      a.cine = true;
      a.play(clip, { fade: 0, restart: true });
      a.char.setClipTime(t);
    },
    prof: () => (opts.profiler ? opts.profiler.report() : null),
    profReset: () => opts.profiler && opts.profiler.reset(),
    info: () => window.__ED.info(),
  };
  window.__ED.game = api;
  game.api = api;
  game.title = title; game.select = select; game.quickMatch = quickMatch; game.pause = pause; game.resume = resume;

  // ---- first screen: flags or the title ---------------------------------------------------------------------------------
  const flags = ctx.flags;
  const pair = (v) => String(v).split(',').map((s) => s.trim());
  const valid = (id) => (fighters.has(id) ? id : null);
  if (flags.demo) {
    const [a, b, d] = pair(flags.demo === true ? 'kael,iska' : flags.demo);
    quickMatch(valid(a) || 'kael', valid(b) || 'iska', 'demo', { difficulty: DIFFS.includes(d) ? d : 'hard' });
  } else if (flags.fight) {
    const [a, b, d] = pair(flags.fight === true ? 'kael,iska' : flags.fight);
    quickMatch(valid(a) || 'kael', valid(b) || 'iska', 'versus', { difficulty: DIFFS.includes(d) ? d : 'normal' });
  } else if (flags.training) {
    const [a, b] = pair(flags.training === true ? 'kael,iska' : flags.training);
    quickMatch(valid(a) || 'kael', valid(b) || 'iska', 'training');
  } else {
    title();
  }
  return game;
}
