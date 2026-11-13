// 일식 원정 · ECLIPSE EXPEDITION — the action-RPG mode (README.md is the API reference).
//
//   const rpg = await createRpg(ctx, { fighters, fx, enter, exit });   // ctx.rpg, window.__ED.rpg
//   rpg.start('kael');  rpg.stop();
//
// Per frame: ORDER.GAME input latch + fixed 60 Hz steps of game time + actor placement; ORDER.CHAR characters;
// ORDER.CHAR + 5 queued events -> choreography / feel; ORDER.CAM + 1 third-person camera; ORDER.UI snapshot -> HUD.

import * as THREE from 'three';
import { registry } from './registry.js';
import { createWorld } from './core/world.js';
import { createPresent } from './core/present.js';
import { createFlow } from './core/flow.js';
import { createRpgCamera } from './camera.js';
import { heroKind, humanController, HEROES } from './core/hero.js';
import { botController } from './core/bot.js';
import { registerBuiltinKinds, registerBuiltinEncounters } from './core/kinds.js';
import { createStandinWorld } from './core/standin.js';
import { createDebugHud } from './core/debughud.js';
import { createDebugShapes } from './core/debugshapes.js';
import { defaultProgress } from './core/progress.js';
import { STEP, yawTo } from './core/math3.js';
import { withStage } from './core/stage.js';
import { rosterEntry } from '../fighters/registry.js';

/**
 * @param {object} ctx app context with env, vfx, cam, audio, input, ui created
 * @param {object} o { fighters: Map (registry fighters), fx (src/game/fx.js createFx), profiler?, enter?(): void, exit?(): void }
 */
export async function createRpg(ctx, o = {}) {
  const fighters = o.fighters || new Map();
  const fx = o.fx;
  registry.builtin = true;
  for (const f of fighters.values()) {
    try { registry.actor('hero.' + f.id, heroKind(f)); } catch (e) { console.warn('[ed] rpg: hero ' + f.id + ' failed: ' + (e && (e.stack || e.message))); }
  }
  registerBuiltinKinds(registry);
  registerBuiltinEncounters(registry);
  registry.builtin = false;
  await registry.discover();
  for (const fn of registry.setups) { try { fn({ ctx, vfx: ctx.vfx, fx }); } catch (e) { console.warn('[ed] rpg: setup hook threw: ' + (e && e.message)); } }
  if (registry.setups.length && ctx.vfx) ctx.vfx.prewarm();
  const progress = () => registry.progressObj || defaultProgress;

  let world = null, hud = null, dressing = null, standin = null, human = null, shapes = null;
  let acc = 0, paused = false, prevInputMode = 'solo';
  const look = { x: 0, y: 0 };
  const P = { x: 0, y: 0, visible: false };
  const V = new THREE.Vector3();
  const pageListeners = [];

  // ---- snapshot (README §11): one reused object ------------------------------------------------------------------------
  const snap = {
    mode: 'off', time: 0, cycle: 0, flow: 'altar',
    hero: { id: '', name: '', nameEn: '', element: '', level: 1, hp: 1, hpMax: 1, fp: 0, fpMax: 0, stamina: 0, staminaMax: 0, staminaLocked: false, ult: 0, ultMax: 100, ultReady: false,
      chalice: 0, chaliceMax: 0, shards: 0, state: 'idle', x: 0, y: 0, z: 0, yaw: 0, lockId: 0, skills: [], ultSkill: null },
    target: null, foes: [], foeCount: 0, boss: null, encounter: null, prompt: null, dropped: null, levelUp: null,
  };
  const targetSnap = { id: 0, kind: '', name: '', nameEn: '', hp: 0, hpMax: 1, poise: 0, poiseMax: 0, boss: false, elite: false, sx: 0, sy: 0, visible: false };
  const bossSnap = { id: 0, name: '', nameEn: '', hp: 0, hpMax: 1, phase: 1, poise: 0, poiseMax: 0 };
  const encSnap = { id: '', title: '', titleEn: '', index: 0, total: 0, remaining: 0, boss: false };
  const dropSnap = { x: 0, z: 0, amount: 0, sx: 0, sy: 0, visible: false };
  const lvlSnap = { level: 1, cost: 0, canAfford: false, stats: { vigor: 0, endurance: 0, might: 0, arcana: 0 }, derive: null };
  const foePool = [];

  function setupHeroSnap(hero) {
    const sp = hero.spec, r = rosterEntry(sp.hero);
    const h = snap.hero;
    h.id = sp.hero; h.name = r.name; h.nameEn = r.nameEn; h.element = sp.element;
    h.skills = ['skill1', 'skill2', 'skill3'].map((slot) => {
      const id = sp.slots[slot], def = id && sp.attacks[id];
      const rm = r.moves.find((m) => m.slot === slot) || {};
      return { slot, id: id || '', name: rm.name || (def ? def.name : ''), nameEn: rm.nameEn || '', icon: rm.icon || '', cost: def ? def.fp : 0, cd: 0, ready: false, _def: def };
    });
    const um = r.moves.find((m) => m.slot === 'ult') || {};
    h.ultSkill = { id: sp.slots.ult || '', name: um.name || '', nameEn: um.nameEn || '', icon: um.icon || '' };
  }

  function fillSnapshot() {
    const hero = world.hero, flow = world.flow, cam = world.camera;
    snap.mode = rpg.mode; snap.time = world.time; snap.cycle = flow.cycle; snap.flow = flow.state;
    const h = snap.hero;
    if (hero) {
      h.level = hero.prog ? hero.prog.level : 1;
      h.hp = hero.hp; h.hpMax = hero.hpMax; h.fp = hero.fp; h.fpMax = hero.fpMax;
      h.stamina = hero.stamina; h.staminaMax = hero.staminaMax; h.staminaLocked = hero.exhausted;
      h.ult = hero.ult; h.ultMax = hero.ultMax; h.ultReady = hero.ultMax > 0 && hero.ult + 1e-6 >= hero.ultMax;
      h.chalice = hero.chalice; h.chaliceMax = hero.chaliceMax; h.shards = hero.prog ? hero.prog.shards : 0;
      h.state = hero.state; h.x = hero.pos.x; h.y = hero.pos.y; h.z = hero.pos.z; h.yaw = hero.yaw;
      h.lockId = cam.target ? cam.target.id : 0;
      for (let i = 0; i < h.skills.length; i++) {
        const s = h.skills[i], def = s._def;
        if (!def) continue;
        const left = hero.cd[def.cooldownKey] || 0;
        s.cd = def.cooldown > 0 ? left / def.cooldown : 0;
        s.ready = left <= 0 && hero.fp + 1e-6 >= def.fp;
      }
    }
    // foes
    let n = 0, boss = null;
    for (let i = 0; i < world.actors.length; i++) {
      const a = world.actors[i];
      if (a === hero || !a.alive || a.leaving > 0 || !hero || !world.hostile(hero, a)) continue;
      let f = foePool[n];
      if (!f) { f = foePool[n] = { id: 0, kind: '', hp: 0, hpMax: 1, boss: false, elite: false, locked: false, sx: 0, sy: 0, visible: false, dist: 0 }; }
      f.id = a.id; f.kind = a.kind; f.hp = a.hp; f.hpMax = a.hpMax; f.boss = !!a.spec.boss; f.elite = !!a.spec.elite; f.locked = cam.target === a;
      V.set(a.view.pos.x, a.view.pos.y + a.height + 0.25, a.view.pos.z);
      cam.project(V, P);
      f.sx = P.x; f.sy = P.y; f.visible = P.visible; f.dist = hero.distTo(a);
      snap.foes[n++] = f;
      if (a.spec.boss) boss = a;
    }
    snap.foes.length = n;
    snap.foeCount = n;
    const t = cam.target;
    if (t && t.alive) {
      const ts = targetSnap;
      ts.id = t.id; ts.kind = t.kind; ts.name = t.name.ko; ts.nameEn = t.name.en; ts.hp = t.hp; ts.hpMax = t.hpMax; ts.poise = t.poise; ts.poiseMax = t.poiseMax; ts.boss = !!t.spec.boss; ts.elite = !!t.spec.elite;
      const fr = t.spec.boss && cam.focusPoint ? cam.focusPoint(t, V) : t.socket('chest', V);
      cam.project(fr, P);
      ts.sx = P.x; ts.sy = P.y; ts.visible = P.visible;
      snap.target = ts;
    } else snap.target = null;
    if (boss) {
      bossSnap.id = boss.id; bossSnap.name = boss.name.ko; bossSnap.nameEn = boss.name.en; bossSnap.hp = boss.hp; bossSnap.hpMax = boss.hpMax;
      bossSnap.phase = boss.data.phase || 1; bossSnap.poise = boss.poise; bossSnap.poiseMax = boss.poiseMax;
      snap.boss = bossSnap;
    } else snap.boss = null;
    const enc = flow.encounter;
    if (enc && !enc.cleared) {
      encSnap.id = enc.def.id; encSnap.title = enc.def.title ? enc.def.title.ko : enc.def.id; encSnap.titleEn = enc.def.title ? enc.def.title.en : '';
      encSnap.index = flow.index; encSnap.total = flow.list.length; encSnap.boss = !!enc.def.boss;
      let rem = enc.pending + world.queue.length;
      for (const a of enc.actors) if (!a.dead && !a.gone) rem++;
      encSnap.remaining = rem;
      snap.encounter = encSnap;
    } else snap.encounter = null;
    snap.prompt = world.prompt;
    if (flow.dropped) {
      dropSnap.x = flow.dropped.x; dropSnap.z = flow.dropped.z; dropSnap.amount = flow.dropped.amount;
      cam.project(V.set(flow.dropped.x, 1.2, flow.dropped.z), P);
      dropSnap.sx = P.x; dropSnap.sy = P.y; dropSnap.visible = P.visible;
      snap.dropped = dropSnap;
    } else snap.dropped = null;
    if (flow.resting && hero && hero.prog) {
      const pr = progress();
      lvlSnap.level = hero.prog.level; lvlSnap.cost = pr.cost(hero.prog.level); lvlSnap.canAfford = hero.prog.shards >= lvlSnap.cost;
      for (const k in lvlSnap.stats) lvlSnap.stats[k] = hero.prog.stats[k] || 0;
      lvlSnap.derive = hero.derived;
      snap.levelUp = lvlSnap;
    } else snap.levelUp = null;
    return snap;
  }

  // ---- lifecycle ---------------------------------------------------------------------------------------------------------
  function setMode(m) {
    if (rpg.mode === m) return;
    const prev = rpg.mode;
    rpg.mode = m;
    if (world) world.emit('mode', { mode: m, prev });
  }

  /**
   * Enter the mode. opts: { bot, sandbox, encounter, seed }
   * @param {string} heroId kael | iska | vorn
   */
  function start(heroId = 'kael', opts = {}) {
    if (rpg.active) stop();
    if (o.enter) o.enter();
    const id = registry.kinds.has('hero.' + heroId) ? heroId : fighters.keys().next().value || 'kael';
    ctx.time.baseScale = 1;
    paused = false; acc = 0;
    if (ctx.cam) { ctx.cam.stop(0); ctx.cam.clearFx(); ctx.cam.letterbox(false, 0); ctx.cam.setMode('free'); }
    if (ctx.env) ctx.env.setMood(null);
    if (ctx.post) ctx.post.reset(0.2);
    if (ctx.vfx) ctx.vfx.clear();
    if (ctx.input) { prevInputMode = ctx.input.mode; ctx.input.setMode('rpg'); ctx.input.clearVirtual(0); }
    if (ctx.ui) { ctx.ui.show('none'); if (ctx.ui.touch) ctx.ui.touch.setVisible(false); }
    const seed = opts.seed ?? (Number(ctx.flags.seed) || 20261113);
    world = createWorld(ctx, { registry, seed });
    rpg.world = world;
    registry.bind(world);
    for (const [ev, fn] of pageListeners) world.on(ev, fn);
    world.present = createPresent(ctx, world, { fx });
    world.camera = createRpgCamera(ctx, world);
    rpg.camera = world.camera;
    shapes = createDebugShapes(ctx, world);
    world.debugShapes = (on = true) => shapes.set(on);
    if (ctx.flags.rpgdebug !== undefined) shapes.set(true);
    world.fxAt = (actor, name, at = [0, 0, 0], fo = {}) => withStage(actor, () => fx.play(name, { pos: at, facing: 1, scale: fo.scale }, fo, fo.fallback ?? null));
    dressing = null;
    if (registry.worldFactory && !opts.sandbox) { try { dressing = registry.worldFactory(ctx, world) || null; } catch (e) { console.warn('[ed] rpg: world module threw: ' + (e && (e.stack || e.message))); } }
    world.flow = createFlow(ctx, world, { progress: progress(), places: dressing, sandbox: !!opts.sandbox, encounter: opts.encounter, playlist: registry.playlist() });
    standin = !registry.worldFactory && !opts.sandbox ? createStandinWorld(ctx, world, world.flow.places) : null;
    human = humanController(ctx);
    const sp = opts.sandbox ? { x: 0, z: 0, yaw: 0 } : world.flow.places.heroSpawn;
    const hero = world.spawn('hero.' + id, { x: sp.x, z: sp.z, yaw: sp.yaw, controller: opts.bot ? botController({ dummy: !!opts.sandbox }) : human });
    rpg.hero = hero;
    world.flow.begin();
    setupHeroSnap(hero);
    world.present.startAmbient(hero);
    if (opts.sandbox) world.spawn('dummy', { x: 4, z: 0, yaw: Math.PI });
    world.camera.snap(hero.yaw);
    for (const fn of registry.prewarms) { try { fn(ctx, world); } catch (e) { console.warn('[ed] rpg: prewarm hook threw: ' + (e && e.message)); } }
    rpg.active = true;
    setMode('play');
    hud = null;
    try { hud = registry.uiFactory ? registry.uiFactory(ctx, rpg) : createDebugHud(ctx, rpg); } catch (e) { console.warn('[ed] rpg: ui module threw: ' + (e && (e.stack || e.message))); hud = createDebugHud(ctx, rpg); }
    try { if (hud && hud.start) hud.start(fillSnapshot()); } catch (e) { console.warn('[ed] rpg: hud.start threw: ' + (e && (e.stack || e.message))); }
    compile();
    if (ctx.audio) ctx.audio.music('title', { fade: 1.5 });
    return hero;
  }

  /** Compile every program now (hero, dressing, VFX) so nothing compiles mid-fight. */
  function compile() {
    try {
      // one presentation pass so every object sits where it will be drawn
      for (const a of world.actors) { a.view.present(0, 0, 0); a.view.animate(0, 0); }
      world.camera.update(0, 0);
      ctx.renderer.compile(ctx.scene, ctx.camera);
      if (ctx.post && ctx.post.distortionScene) ctx.renderer.compile(ctx.post.distortionScene, ctx.camera);
    } catch (e) { console.warn('[ed] rpg compile: ' + (e && e.message)); }
  }

  /** Leave the mode: everything it created is disposed, the stage is handed back (the caller shows a screen). */
  function stop() {
    if (!rpg.active) return;
    rpg.active = false;
    setMode('off');
    try { if (hud && hud.stop) hud.stop(); if (hud && hud.dispose) hud.dispose(); } catch (e) { /* hud teardown */ }
    hud = null;
    if (world.present.cine || world.lock) { world.lock = null; world.freeze = null; }
    world.flow.dispose();
    if (standin) { standin.dispose(); standin = null; }
    if (dressing && dressing.dispose) { try { dressing.dispose(); } catch (e) { console.warn('[ed] rpg: world dispose threw: ' + (e && e.message)); } }
    dressing = null;
    world.present.dispose();
    if (shapes) { shapes.dispose(); shapes = null; }
    if (ctx.vfx) ctx.vfx.clear();
    world.dispose();
    world = null; rpg.world = null; rpg.camera = null; rpg.hero = null;
    ctx.time.baseScale = 1;
    paused = false;
    if (ctx.env) ctx.env.setMood(null);
    if (ctx.post) ctx.post.reset(0.2);
    if (ctx.cam) { ctx.cam.clearFx(); ctx.cam.letterbox(false, 0); ctx.cam.setMode('fight', 0); ctx.cam.snap(); }
    if (ctx.input) { ctx.input.clearVirtual(0); ctx.input.setMode(prevInputMode === 'rpg' ? 'solo' : prevInputMode); }
    if (ctx.camera.fov !== 40) { ctx.camera.fov = 40; ctx.camera.updateProjectionMatrix(); }
  }

  function pause() {
    if (!rpg.active || paused || rpg.mode === 'cine') return;
    paused = true;
    ctx.time.baseScale = 0;
    if (ctx.input) ctx.input.clearVirtual(0);
    if (human) human.clear();
    if (ctx.audio) ctx.audio.duck(0.7, 0.6);
    setMode('pause');
  }
  function resume() {
    if (!paused) return;
    paused = false;
    ctx.time.baseScale = 1;
    if (human) human.clear();
  }
  function toTitle() { stop(); if (o.exit) o.exit(); }

  // ---- per frame ------------------------------------------------------------------------------------------------------
  ctx.onUpdate((dtGame, dtReal) => {
    if (!rpg.active) return;
    const inp = ctx.input, hero = world.hero;
    if (inp && inp.pressed('pause')) { if (paused) resume(); else pause(); }
    if (!paused) {
      if (hero && hero.controller && hero.controller.frame) hero.controller.frame(dtReal);
      if (inp && inp.look) { inp.look(0, look); if (look.x || look.y) world.camera.look(look.x, look.y); }
      acc += dtGame;
      let n = 0;
      while (acc >= STEP - 1e-9 && n < 6) { world.step(STEP); acc -= STEP; n++; }
      if (n === 6) acc = 0;
    }
    const alpha = Math.min(1, Math.max(0, acc / STEP));
    for (let i = 0; i < world.actors.length; i++) world.actors[i].view.present(alpha, dtGame, dtReal);
    const flow = world.flow;
    setMode(paused ? 'pause' : hero && hero.dead ? 'dead' : world.camera.cinematic || world.lock ? 'cine' : flow.resting ? 'rest' : flow.state === 'victory' ? 'victory' : 'play');
    if (ctx.env && hero) ctx.env.setFocus(hero.view.pos.x);
  }, ctx.ORDER.GAME);
  ctx.onUpdate((dtGame, dtReal) => {
    if (!rpg.active) return;
    for (let i = 0; i < world.actors.length; i++) world.actors[i].view.animate(dtGame, dtReal);
    if (standin) standin.update(dtGame, dtReal);
    if (dressing && dressing.update) dressing.update(dtGame, dtReal);
  }, ctx.ORDER.CHAR);
  ctx.onUpdate(() => { if (rpg.active) { world.present.late(); if (shapes.on) shapes.update(); } }, ctx.ORDER.CHAR + 5);
  ctx.onUpdate((dtGame, dtReal) => { if (rpg.active) world.camera.update(dtGame, dtReal); }, ctx.ORDER.CAM + 1);
  ctx.onUpdate((dtGame, dtReal) => {
    if (!rpg.active || !hud) return;
    try { hud.update(fillSnapshot(), dtReal); } catch (e) { if (!rpg._hudWarned) { rpg._hudWarned = true; console.warn('[ed] rpg: hud.update threw: ' + (e && (e.stack || e.message))); } }
  }, ctx.ORDER.UI);
  if (typeof document !== 'undefined') document.addEventListener('visibilitychange', () => { if (document.hidden && rpg.active) pause(); });

  // ---- the mode object -------------------------------------------------------------------------------------------------
  const rpg = {
    ctx, registry,
    active: false, mode: 'off', world: null, camera: null, hero: null,
    heroes: Object.keys(HEROES).filter((id) => registry.kinds.has('hero.' + id)),
    start, stop, pause, resume, toTitle,
    snapshot: () => (rpg.active ? fillSnapshot() : snap),
    /** Subscribe to world events for the lifetime of the page (re-bound to every new world). Returns off(). */
    on(ev, fn) {
      const entry = [ev, fn];
      pageListeners.push(entry);
      const off = world ? world.on(ev, fn) : null;
      return () => { const i = pageListeners.indexOf(entry); if (i >= 0) pageListeners.splice(i, 1); if (off) off(); };
    },
    project(pos, out) { return world ? world.camera.project(pos, out) : out; },
    levelUp(stat) { return world ? world.flow.levelUp(stat) : false; },
    leaveAltar() { if (world) world.flow.leave(); },
    rest() { return world ? world.flow.rest() : false; },
    nextCycle() { if (world && world.flow.state === 'victory') world.flow.nextCycle(); },
    respawn() { if (world && world.flow.state === 'dead') world.flow.respawn(); },
  };
  ctx.rpg = rpg;

  // ---- test API (README §13) -------------------------------------------------------------------------------------------
  const r2 = (x) => Math.round(x * 100) / 100;
  const holds = [];
  ctx.onUpdate((dg, dr) => {
    for (let i = holds.length - 1; i >= 0; i--) {
      const hd = holds[i];
      hd.left -= dr;
      if (hd.left <= 0) { holds.splice(i, 1); hd.end(); }
    }
  }, ctx.ORDER.INPUT - 1);
  const api = {
    get active() { return rpg.active; },
    get mode() { return rpg.mode; },
    world: () => world,
    heroes: () => rpg.heroes,
    found: () => ({ ...registry.found }),
    start(hero = 'kael', so = {}) { start(hero, so); return api.state(); },
    stop() { toTitle(); },
    pause, resume,
    snapshot: () => JSON.parse(JSON.stringify(rpg.snapshot(), (k, v) => (k === '_def' || k === 'trigger' ? undefined : v))),
    state() {
      if (!world) return { mode: rpg.mode };
      const h = world.hero, cam = world.camera;
      return {
        mode: rpg.mode, flow: world.flow.state, time: r2(world.time), cycle: world.flow.cycle, encounter: world.flow.encounter ? world.flow.encounter.def.id : null,
        hero: h ? { id: h.spec.hero, x: r2(h.pos.x), y: r2(h.pos.y), z: r2(h.pos.z), yaw: r2(h.yaw), state: h.state, hp: Math.round(h.hp), hpMax: h.hpMax, stamina: Math.round(h.stamina), fp: Math.round(h.fp), ult: Math.round(h.ult),
          attack: h.attack ? h.attack.id : null, t: h.attack ? r2(h.attack.t) : 0, chalice: h.chalice, shards: h.prog ? h.prog.shards : 0, level: h.prog ? h.prog.level : 1, speed: r2(h.speed), gait: h.gait } : null,
        foes: world.actors.filter((a) => a !== h).map((a) => ({ id: a.id, kind: a.kind, x: r2(a.pos.x), z: r2(a.pos.z), y: r2(a.pos.y), hp: Math.round(a.hp), state: a.state, attack: a.attack ? a.attack.id : null })),
        camera: { yaw: r2(cam.yaw), pitch: r2(cam.pitch), dist: r2(cam.dist), lock: cam.target ? cam.target.id : 0, cine: cam.cinematic },
        lock: world.lock ? r2(world.lock.t) : null,
      };
    },
    spawn(kind, x = 4, z = 0, so = {}) { const a = world.spawn(kind, { x, z, force: true, ...so }); return a ? a.id : 0; },
    tp(x, z, yaw) { const h = world.hero; h.teleport(x, z, yaw); world.camera.snap(h.yaw); },
    give(g = {}) {
      const h = world.hero;
      if (g.hp !== undefined) h.hp = g.hp === true ? h.hpMax : Math.min(h.hpMax, g.hp);
      if (g.fp !== undefined) h.fp = g.fp === true ? h.fpMax : Math.min(h.fpMax, g.fp);
      if (g.ult !== undefined) h.ult = g.ult === true ? h.ultMax : Math.min(h.ultMax, g.ult);
      if (g.stamina !== undefined) { h.stamina = g.stamina === true ? h.staminaMax : Math.min(h.staminaMax, g.stamina); h.exhausted = false; }
      if (g.chalice !== undefined) h.chalice = g.chalice === true ? h.chaliceMax : g.chalice;
      if (g.shards !== undefined && h.prog) { h.prog.shards = g.shards; world.emit('shards', { amount: 0, total: g.shards, reason: 'test' }); }
      if (g.cooldowns) for (const k in h.cd) h.cd[k] = 0;
    },
    god(on = true) { world.godMode = !!on; },
    /** draw hit volumes, body cylinders, colliders, triggers (also `#rpgdebug`) */
    debug(on = true) { world.debugShapes(on); },
    bot(on = true, bo = {}) { world.hero.controller = on ? botController(bo) : human; },
    /** hold a virtual action for `sec` real seconds */
    press(action, sec = 0.05) { ctx.input.setVirtual(action, true, 0); holds.push({ left: sec, end: () => ctx.input.setVirtual(action, false, 0) }); },
    /** hold the move stick (x right, y forward; camera-relative) for `sec` real seconds (0 = until changed) */
    move(x = 0, y = 0, sec = 0) { ctx.input.setVirtualMove(x, y, 0); if (sec > 0) holds.push({ left: sec, end: () => ctx.input.setVirtualMove(0, 0, 0) }); },
    look(dyaw = 0, dpitch = 0) { world.camera.look(dyaw, dpitch); },
    /** start a hero move now, costs ignored: light1 light2 light3 heavy fheavy dheavy skill1 skill2 skill3 ult */
    act(slot) {
      const h = world.hero, id = h.spec.slots[slot] || slot;
      if (!h.spec.attacks[id]) return false;
      if (h.state !== 'idle' && h.state !== 'move' && h.state !== 'attack' && h.state !== 'guard') return false;
      const t = world.camera.target || h.target;
      return h.startAttack(id, { force: true, target: t, aim: t ? yawTo(t.pos.x - h.pos.x, t.pos.z - h.pos.z) : undefined });
    },
    lock(id) { const cam = world.camera; if (id === true) { cam.lock(null); return cam.toggleLock() ? cam.target.id : 0; } cam.lock(id ? world.byId(id) : null); return cam.target ? cam.target.id : 0; },
    clear() { for (const a of world.actors.slice()) if (a !== world.hero) world.despawn(a); world.queue.length = 0; world.projectiles.clear(); },
    step(n = 1) { for (let i = 0; i < n; i++) ctx.frame(1 / 60, false); return api.state(); },
    kill(id) { const a = world.byId(id); if (a && a.alive) { a.hp = 0; a.die(world.hero); } },
    hurt(amount = 100, level = 'heavy') { return world.damage(world.hero, { amount, level, pos: world.hero.at(0.4, 1.2, 0), dir: { x: -Math.cos(world.hero.yaw), z: Math.sin(world.hero.yaw) } }); },
    flow(cmd) {
      const f = world.flow;
      if (cmd === 'rest') return f.rest();
      if (cmd === 'leave') return f.leave();
      if (cmd === 'respawn') return f.respawn();
      if (cmd === 'next') return !!f.start();
      if (cmd === 'cycle') return f.nextCycle();
      if (typeof cmd === 'string' && cmd.startsWith('encounter:')) return !!f.start(cmd.slice(10));
      return f.state;
    },
    levelUp: (stat) => rpg.levelUp(stat),
    /** Invariants for the soak test. */
    checks() {
      const bad = [];
      if (!world) return { ok: false, bad: ['no world'] };
      for (const a of world.actors) {
        for (const v of [a.pos.x, a.pos.y, a.pos.z, a.yaw, a.hp, a.stamina === Infinity ? 0 : a.stamina, a.vel.x, a.vel.y, a.vel.z, a.speed]) if (!Number.isFinite(v)) { bad.push('NaN in actor ' + a.kind + '#' + a.id); break; }
        if (Math.hypot(a.pos.x, a.pos.z) > world.arena.radius + 0.6) bad.push(a.kind + '#' + a.id + ' outside the arena');
        if (a.pos.y < -0.01 || a.pos.y > 12) bad.push(a.kind + '#' + a.id + ' y=' + a.pos.y.toFixed(2));
        const lim = a.state === 'attack' ? (a.attack ? a.attack.def.duration + 1 : 1) : a.state === 'roll' ? 2 : a.state === 'flinch' || a.state === 'stagger' || a.state === 'guardhit' ? 4 : a.state === 'launched' ? 5 : a.state === 'down' || a.state === 'getup' ? 4 : a.state === 'cine' ? 9 : a.state === 'drink' ? 3 : a.state === 'spawn' ? 4 : Infinity;
        if (a.stateTime > lim) bad.push(a.kind + '#' + a.id + ' stuck in ' + a.state + ' ' + a.stateTime.toFixed(1) + ' s');
        if (a.hp > a.hpMax + 0.5 || a.hp < 0) bad.push(a.kind + '#' + a.id + ' hp ' + a.hp);
      }
      const cp = ctx.camera.position;
      if (!Number.isFinite(cp.x + cp.y + cp.z)) bad.push('camera NaN');
      const info = ctx.renderer.info;
      return { ok: bad.length === 0, bad, actors: world.actors.length, projectiles: world.projectiles.list.length, triggers: world.triggers.length, colliders: world.colliders.length,
        sceneChildren: ctx.scene.children.length, geometries: info.memory.geometries, textures: info.memory.textures, programs: (info.programs || []).length };
    },
    prof: () => (o.profiler ? o.profiler.report() : null),
    profReset: () => o.profiler && o.profiler.reset(),
    info: () => window.__ED.info(),
  };
  rpg.api = api;
  if (typeof window !== 'undefined' && window.__ED) window.__ED.rpg = api;
  return rpg;
}
