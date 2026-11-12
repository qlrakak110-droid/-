// Session: one rules match bound to the presentation (two actors, choreography, feel, camera, HUD, audio).
//
//   const s = createSession(ctx, [fighterA, fighterB], { mode: 'versus' | 'demo' | 'showcase' | 'training', difficulty, seed });
//   s.start()     begin round 1 (round intro camera, announcer, battle music)
//   s.rematch()   restart at round 1 with the same characters
//   s.dispose()   remove characters, hooks and listeners
//
// Time: the rules are stepped with REAL time x the presentation slow-motion factor (ctx.time.scale outside its
// hit-stop), never with a frozen dt: the rules apply their own per-fighter hit-stop. During a cinematic lock the
// match is stepped with game time so the lock clock, the camera shots and the VFX stay in sync with the stutter
// hit-stops of the choreography (the rules hold both fighters during a lock, so nothing is applied twice).

import * as SHOTS from '../cam/shots.js';
import { createMatch, createAIController, createHumanController, createIdleController } from './logic/index.js';
import { clamp } from '../core/math.js';
import { createActor } from './actor.js';
import { createPresenter } from './present.js';
import { createFeel } from './feel.js';

const ACTIONS = ['right', 'left', 'up', 'down', 'light', 'heavy', 'skill1', 'skill2', 'skill3', 'ult', 'guard', 'dodge'];

/** A non-allocating human controller reading ctx.input (held state; the rules derive presses). */
function inputController(ctx, player) {
  const s = { move: 0, up: false, down: false, light: false, heavy: false, skill1: false, skill2: false, skill3: false, ult: false, guard: false, dodge: false };
  return createHumanController(() => {
    const inp = ctx.input;
    if (!inp) return s;
    s.move = (inp.held('right', player) ? 1 : 0) - (inp.held('left', player) ? 1 : 0);
    for (let k = 2; k < ACTIONS.length; k++) s[ACTIONS[k]] = inp.held(ACTIONS[k], player);
    return s;
  });
}

/**
 * @param {object} ctx
 * @param {object[]} fighters two registry fighters
 * @param {object} [opts] { mode = 'versus', difficulty = 'normal', seed, rules, onEnd(result), onRoundEnd(e) }
 */
export function createSession(ctx, fighters, opts = {}) {
  const mode = opts.mode || 'versus';
  const difficulty = opts.difficulty || 'normal';
  const ai = (d) => createAIController({ difficulty: d });
  const controllers = mode === 'versus' || mode === 'training' ? [inputController(ctx, 0), mode === 'training' ? createIdleController() : ai(difficulty)]
    : mode === 'demo' ? [ai(opts.difficulty1 || difficulty), ai(difficulty)] : [null, null];
  const seed = opts.seed ?? (Number(ctx.flags.seed) || Math.floor(ctx.rng() * 1e9));
  /** real time each sound name was last played (marker hints skip a sound the generic layer just played) */
  const soundAt = new Map();
  const match = createMatch({ fighters: fighters.map((f) => f.def), controllers, rules: opts.rules || {}, rng: seed });

  const session = {
    ctx, mode, difficulty, fighters, match, seed,
    actors: [],
    fx: opts.fx,
    stats: null, presenter: null, feel: null,
    result: null,
    ended: false,
    /** the match is stepped only once start() ran (built behind the VS splash, idle until then) */
    running: false,
    /** presentation events seen this round (test API) */
    log: [],
    presentOf: (i) => fighters[i].present || {},
    /** choreography of a move: present.moves[moveId] or present.moves[slot] */
    moveHandlers(i, id) {
      const t = (fighters[i].present || {}).moves;
      if (!t || !id) return null;
      if (t[id]) return t[id];
      const a = session.actors[i];
      return a ? t[a.clips.move(id).slot] || null : null;
    },
    projectileKind: (id) => projKinds.get(id) || '',
    /** A controller reading ctx.input for player i (held state; the rules derive presses). */
    humanController: (i) => inputController(ctx, i),
    sound(name, o) {
      soundAt.set(name, ctx.time.real);
      if (ctx.audio) { try { return ctx.audio.play(name, o); } catch (e) { /* optional peer */ } }
      return null;
    },
    /** Was `name` played through session.sound within the last `sec` real seconds. */
    playedRecently(name, sec) { const t = soundAt.get(name); return t !== undefined && ctx.time.real - t < sec; },
    onStep, onVictory,
    start, rematch, update, animate, dispatchQueued, dispose, restartRound,
  };

  // ---- actors, choreography, feel -----------------------------------------------------------------------------------
  session.actors = [createActor(ctx, session, 0, fighters[0]), createActor(ctx, session, 1, fighters[1])];
  session.stats = createStats(session);
  session.feel = createFeel(ctx, session);
  session.presenter = createPresenter(ctx, session, session.feel);
  if (ctx.cam) ctx.cam.setTargets(session.actors[0].char.sockets.chest, session.actors[1].char.sockets.chest);

  // fighter ambient presentation (auras, idle particles): present.ambient(h) may return handles; it runs again at every
  // round start (the round reset clears the VFX)
  const ambient = [];
  function startAmbient() {
    for (const h of ambient) { try { h.kill(); } catch (e) { /* ignore */ } }
    ambient.length = 0;
    for (let i = 0; i < 2; i++) {
      const fn = session.presentOf(i).ambient;
      if (typeof fn !== 'function') continue;
      try { const r = fn(session.presenter.helper(i)); if (r) ambient.push(...(Array.isArray(r) ? r : [r])); } catch (e) { console.warn('[ed] ambient of ' + fighters[i].id + ': ' + e.message); }
    }
  }

  // ---- events: queued by the listener, dispatched after the characters updated (fresh sockets) ----------------------
  const queue = [];
  const projKinds = new Map();
  const off = match.on('*', (name, e) => {
    queue.push(name, e);
    if (name === 'hit' && !e.blocked && !e.armoured) { const a = session.actors[e.defender]; a.react++; a.reactFront = e.front !== false; }
    else if (name === 'projectileSpawn') projKinds.set(e.id, e.kind);
  });

  function dispatchQueued() {
    if (!queue.length) return;
    // copy first: a handler may step nothing, but keep the loop safe against re-entrancy
    const q = queue.splice(0, queue.length);
    for (let k = 0; k < q.length; k += 2) {
      const name = q[k], e = q[k + 1];
      if (session.log.length < 400) session.log.push(name);
      try { flow(name, e); session.presenter.dispatch(name, e); } catch (err) { console.warn('[ed] presentation of ' + name + ' failed: ' + (err && (err.stack || err.message))); }
      // the kind is needed until the expiry itself was presented (hits of that frame are dispatched before it)
      if (name === 'projectileExpire') projKinds.delete(e.id);
    }
  }

  // ---- round flow: intro camera, announcer, KO / outro, results ------------------------------------------------------
  const rounds = [];
  function flow(name, e) {
    const hud = ctx.ui && ctx.ui.hud;
    switch (name) {
      case 'roundStart': onRoundStart(e); break;
      case 'fightStart':
        if (hud) hud.announce('fight');
        session.sound('announce_fight');
        if (ctx.cam) ctx.cam.kick({ fov: -2, duration: 0.4 });
        break;
      case 'timeUp':
        if (hud) hud.announce('timeup');
        session.sound('bell');
        break;
      case 'roundEnd': {
        const w = e.winner;
        const how = w < 0 ? 'draw' : e.reason === 'time' ? 'time' : match.fighters[w].hp >= match.fighters[w].hpMax ? 'perfect' : 'ko';
        rounds.push({ winner: w, how });
        if (hud && how === 'perfect') hud.announce('perfect');
        else if (hud && w < 0) hud.announce('draw');
        if (opts.onRoundEnd) opts.onRoundEnd(e);
        break;
      }
      case 'matchEnd': {
        const w = e.winner;
        if (hud && w >= 0) { const r = fighters[w].roster; hud.announce(r.nameEn, { style: 'win', sub: `${r.name} 승리 · WINNER`, duration: 2.6 }); }
        if (ctx.audio) ctx.audio.music('victory', { fade: 0.6 });
        break;
      }
      default:
    }
  }

  function onRoundStart(e) {
    const hud = ctx.ui && ctx.ui.hud;
    for (const a of session.actors) a.restartRound();
    session.feel.clearProjectiles();
    session.presenter.reset();
    if (ctx.vfx) ctx.vfx.clear();
    startAmbient();
    if (ctx.env) ctx.env.setMood(null);
    ctx.post.reset(0.2);
    if (ctx.cam) { ctx.cam.clearFx(); ctx.cam.letterbox(false, 0.2); }
    if (hud && mode !== 'showcase') {
      hud.reset();
      const last = match.rules.roundsToWin - 1;
      const final = match.fighters[0].rounds === last && match.fighters[1].rounds === last;
      hud.announce(final ? 'final' : 'round', { round: e.round });
    }
    if (mode !== 'showcase') {
      // a lethal ultimate lock leaves its music overlay on (cinematicEnd keeps it for the KO): every round starts on
      // the plain battle track (a no-op when it is already playing)
      if (ctx.audio && e.round > 1) ctx.audio.music('battle', { fade: 1.2 });
      session.sound('announce_round');
      if (e.round === 1) session.sound('bell', { delay: 0.1, volume: 0.6 });
      introCamera(e.round);
    }
    session.log.length = 0;
  }

  function introCamera(round) {
    if (!ctx.cam) return;
    const T = match.rules.introTime;
    ctx.cam.snap();
    const shots = round === 1 ? [
      SHOTS.wideEstablishing({ dur: T * 0.5, dist: [13, 11.5], height: [3.6, 2.6], drift: 2.2 }),
      SHOTS.orbitSweep({ dur: T * 0.5, cut: 0.3, from: -42, to: -6, radius: [7.4, 6.6], height: [1.6, 1.5] }),
    ] : [
      SHOTS.orbitSweep({ dur: T * 0.85, from: 38, to: 4, radius: [7, 6.4], height: [2.2, 1.5] }),
    ];
    ctx.cam.play(shots, { anchor: 0, blendOut: 0.55, hud: false });
  }

  /** Round winner reached its victory pose: hero shot on the winner during the outro. */
  function onVictory(i) {
    if (!ctx.cam || mode === 'showcase' || match.phase === 'fight') return;
    if (session.presenter.cine) return;
    ctx.cam.play([SHOTS.heroPushIn({ dur: 2.4, clock: 'real', dist: [4.4, 3.3], height: [0.6, 0.75], look: [1.45, 1.55], angle: 30 })], { anchor: i, blendOut: 0.8 });
  }

  /** Footsteps from the clips' step events. */
  function onStep(actor, data) {
    const f = match.fighters[actor.index];
    if (f.state === 'walk' || f.state === 'dash' || f.state === 'intro' || f.state === 'backstep') {
      session.sound('step', { pos: actor.pos, volume: f.state === 'walk' ? 0.4 : 0.6 });
      session.feel.step(actor);
      void data;
    }
  }

  // ---- per frame ----------------------------------------------------------------------------------------------------
  let lastScale = 1;
  let lastIntensity = -1;
  /** Match dt for this frame (see the header: real time x slow motion; game time during a lock; 0 when paused). */
  function stepDt(dtGame, dtReal) {
    const T = ctx.time;
    if (T.baseScale === 0) return 0;
    if (match.cinematic) return dtGame;
    if (T.scale > 0) lastScale = T.scale;
    return dtReal * (T.scale > 0 ? T.scale : lastScale);
  }

  const hudState = {
    time: 99, p1: { hp: 1, hpMax: 1, fp: 0, fpMax: 100, ult: 0, ultMax: 100, rounds: 0 }, p2: { hp: 1, hpMax: 1, fp: 0, fpMax: 100, ult: 0, ultMax: 100, rounds: 0 },
  };
  const skillLists = [0, 1].map((i) => skillSlots(i));
  function skillSlots(i) {
    const def = match.defs[i];
    const roster = fighters[i].roster;
    return [1, 2, 3].map((n) => {
      const id = def.commands['skill' + n];
      const mv = id && def.moves[id];
      const r = roster.moves.find((m) => m.slot === 'skill' + n) || {};
      return { id: r.icon || 'skill' + n, name: r.name || (mv && mv.name) || '', icon: r.icon, cost: mv ? mv.fpCost : 0, cd: 0, ready: false, _mv: mv };
    });
  }

  function update(dtGame, dtReal) {
    if (session.running && !session.ended) {
      const dt = stepDt(dtGame, dtReal);
      if (dt > 0) match.step(dt);
    }
    for (const a of session.actors) a.update(dtGame, dtReal);
    const f0 = match.fighters[0], f1 = match.fighters[1];
    if (ctx.env) ctx.env.setFocus((session.actors[0].pos.x + session.actors[1].pos.x) * 0.5);
    if (mode === 'showcase') return;
    // battle music intensity: only real changes reach WebAudio (each call schedules parameter automation)
    const intensity = clamp(1.15 - Math.min(f0.hp / f0.hpMax, f1.hp / f1.hpMax) + (match.round - 1) * 0.1, 0.25, 1);
    if (ctx.audio && ctx.audio.setIntensity && Math.abs(intensity - lastIntensity) > 0.01) { lastIntensity = intensity; ctx.audio.setIntensity(intensity); }
    updateHud();
    if (match.phase === 'end' && !session.ended) {
      session.ended = true;
      session.result = buildResult();
      if (opts.onEnd) opts.onEnd(session.result);
    }
  }

  function updateHud() {
    const hud = ctx.ui && ctx.ui.hud;
    if (!hud) return;
    hudState.time = mode === 'training' ? Infinity : match.clock;
    for (let i = 0; i < 2; i++) {
      const f = match.fighters[i], o = i ? hudState.p2 : hudState.p1;
      o.hp = f.hp; o.hpMax = f.hpMax; o.fp = f.fp; o.fpMax = f.fpMax; o.ult = f.ult; o.ultMax = f.ultMax; o.rounds = f.rounds;
      const list = skillLists[i];
      for (const s of list) {
        const mv = s._mv;
        if (!mv) continue;
        const left = f.cooldowns[mv.cooldownKey] || 0;
        s.cd = mv.cooldown > 0 ? left / mv.cooldown : 0;
        s.ready = left <= 0 && f.fp + 1e-9 >= mv.fpCost;
      }
      hud.skills(i, list);
    }
    hud.set(hudState);
  }

  /** Character updates (ORDER.CHAR). */
  function animate(dtGame, dtReal) {
    for (const a of session.actors) a.animate(dtGame, dtReal);
  }

  /** After the characters (ORDER.CHAR + 5): events -> choreography / feel, projectile bodies, ult timeline. */
  function late() {
    dispatchQueued();
    session.presenter.update();
    session.feel.updateProjectiles();
  }

  const offs = [
    ctx.onUpdate((dg, dr) => update(dg, dr), ctx.ORDER.GAME),
    ctx.onUpdate((dg, dr) => animate(dg, dr), ctx.ORDER.CHAR),
    ctx.onUpdate(() => late(), ctx.ORDER.CHAR + 5),
  ];

  // ---- lifecycle ----------------------------------------------------------------------------------------------------
  function start() {
    session.running = mode !== 'showcase';
    session.ended = false;
    session.result = null;
    rounds.length = 0;
    session.stats.reset();
    if (ctx.ui && ctx.ui.hud && mode !== 'showcase') {
      ctx.ui.hud.setup({ p1: fighters[0].roster, p2: fighters[1].roster, roundsToWin: match.rules.roundsToWin });
    }
    if (ctx.audio && mode !== 'showcase') ctx.audio.music('battle', { fade: 1.2 });
    // createMatch / match.reset() already announced round 1 (before we listened / into the queue): run it once here
    queue.length = 0;
    projKinds.clear();
    onRoundStart({ round: match.round });
    for (const a of session.actors) a.restartRound();
  }

  function rematch() {
    match.reset();
    start();
  }

  function restartRound() { match.restartRound(); }

  function buildResult() {
    const w = match.winner;
    const p1 = match.fighters[0];
    return {
      winner: w, p1: fighters[0].roster, p2: fighters[1].roster,
      score: [match.fighters[0].rounds, match.fighters[1].rounds],
      rounds: rounds.slice(),
      stats: { p1: { maxCombo: session.stats.maxCombo[0], damage: session.stats.damage[0], ults: session.stats.ults[0], hpLeft: Math.round((p1.hp / p1.hpMax) * 100) } },
    };
  }

  function dispose() {
    off();
    for (const o of offs) o();
    for (const h of ambient) { try { h.kill(); } catch (e) { /* ignore */ } }
    session.feel.clearProjectiles();
    // nothing of this match may outlive its characters (afterimage ghosts share their geometry)
    if (ctx.vfx) ctx.vfx.clear();
    for (const a of session.actors) a.dispose();
    session.actors.length = 0;
  }

  return session;
}

/** Match statistics for the result screen. */
function createStats(session) {
  const s = {
    maxCombo: [0, 0], damage: [0, 0], ults: [0, 0], kos: [0, 0],
    reset() { s.maxCombo = [0, 0]; s.damage = [0, 0]; s.ults = [0, 0]; s.kos = [0, 0]; },
    hit(e) { s.damage[e.attacker] += e.damage || 0; s.maxCombo[e.attacker] = Math.max(s.maxCombo[e.attacker], e.combo || 0); },
    tick(e) { s.damage[e.attacker] += e.damage || 0; s.maxCombo[e.attacker] = Math.max(s.maxCombo[e.attacker], session.match.fighters[e.attacker].combo.hits || 0); },
    ko(e) { s.kos[e.by]++; },
  };
  session.match.on('cinematicStart', (e) => { s.ults[e.attacker]++; });
  return s;
}
