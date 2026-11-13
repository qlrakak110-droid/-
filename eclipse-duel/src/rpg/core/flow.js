// The expedition loop (README §9): wake at the Starlit Altar -> the mist gate -> encounters in order -> the boss ->
// victory -> a new cycle (enemies stronger). Death: the Eclipse Shards stay where the hero fell and can be reclaimed
// once; the hero wakes at the altar and unfinished encounters respawn. Resting refills HP / FP / the Dawn Chalice and
// opens the level-up screen (the HUD reads snapshot.levelUp and calls rpg.levelUp(stat)).
//
//   const flow = createFlow(ctx, world, { progress, places, sandbox, encounter });      world.flow

import * as THREE from 'three';
import { hypot2, yawTo } from './math3.js';

const DEFAULT_PLACES = { altar: { x: -11, z: 6.5, yaw: -0.5 }, heroSpawn: { x: -9.6, z: 5.6, yaw: -0.52 }, gate: { x: -5, z: 2.4, yaw: -0.5, r: 2.6 } };

/**
 * @param {object} ctx
 * @param {object} world
 * @param {object} o { progress, places (from the world module), sandbox, encounter (start id), playlist }
 */
export function createFlow(ctx, world, o) {
  const progress = o.progress;
  const places = { altar: { ...DEFAULT_PLACES.altar }, heroSpawn: { ...DEFAULT_PLACES.heroSpawn }, gate: { ...DEFAULT_PLACES.gate } };
  if (o.places) for (const k of ['altar', 'heroSpawn', 'gate']) if (o.places[k]) Object.assign(places[k], o.places[k]);
  const list = o.playlist || [];
  const timers = [];
  const removers = [];
  let droppedRemove = null, droppedMark = null;

  const flow = {
    /** altar | explore | encounter | boss | victory | dead | sandbox */
    state: o.sandbox ? 'sandbox' : 'altar',
    places, list,
    /** index of the next / running encounter in `list` */
    index: 0,
    /** running encounter: { def, actors: [], pending, cleared } */
    encounter: null,
    cycle: 0,
    dropped: null,
    resting: false,
    start, rest, leave, respawn, nextCycle, step, dispose, levelUp, addShards, music,
    after,
  };

  function after(sec, fn) { timers.push({ left: sec, fn }); }
  function music() { return flow.state === 'altar' || flow.state === 'victory' ? 'title' : 'battle'; }
  const hero = () => world.hero;

  // ---- shards ---------------------------------------------------------------------------------------------------
  function addShards(amount, reason) {
    const h = hero();
    if (!h || !h.prog || !amount) return;
    h.prog.shards = Math.max(0, h.prog.shards + amount);
    world.emit('shards', { amount, total: h.prog.shards, reason });
  }
  function save() { const h = hero(); if (h && h.prog && progress) { h.prog.cycle = flow.cycle; h.prog.dropped = flow.dropped ? { ...flow.dropped } : null; progress.save(h.spec.hero, h.prog); } }
  flow.save = save;

  /** Re-derive the hero's maxima from its progression state (after a level-up / at start). */
  function derive(refill) {
    const h = hero();
    if (!h || !progress) return;
    const d = progress.derive(h.prog, h.spec.base);
    h.derived = d;
    const k = h.hpMax > 0 ? h.hp / h.hpMax : 1;
    h.hpMax = d.hpMax; h.staminaMax = d.staminaMax; h.fpMax = d.fpMax; h.chaliceMax = d.chaliceMax;
    if (refill) { h.hp = h.hpMax; h.stamina = h.staminaMax; h.fp = h.fpMax; h.chalice = h.chaliceMax; h.exhausted = false; }
    else { h.hp = Math.min(h.hpMax, Math.max(1, Math.round(h.hpMax * k))); h.stamina = Math.min(h.stamina, h.staminaMax); h.fp = Math.min(h.fp, h.fpMax); }
  }
  flow.derive = derive;

  function levelUp(stat) {
    const h = hero();
    if (!h || !progress || !flow.resting) return false;
    if (!progress.levelUp(h.prog, stat)) return false;
    derive(true);
    save();
    world.emit('shards', { amount: 0, total: h.prog.shards, reason: 'spend' });
    world.emit('levelUp', { stat, level: h.prog.level });
    return true;
  }

  // ---- encounters -------------------------------------------------------------------------------------------------
  /** Start the next (or the named) encounter now. */
  function start(id) {
    if (flow.encounter && !flow.encounter.cleared) return null;
    if (id) { const i = list.findIndex((e) => e.id === id); if (i < 0) return null; flow.index = i; }
    const def = list[flow.index];
    if (!def) return null;
    const enc = { def, actors: [], pending: 0, cleared: false, time: 0 };
    flow.encounter = enc;
    flow.state = def.boss ? 'boss' : 'encounter';
    for (const s of def.spawns || []) {
      enc.pending++;
      const spawn = () => {
        if (flow.encounter !== enc) return;
        const opts = { x: s.x, z: s.z, yaw: s.yaw, level: flow.cycle, ...(s.opts || {}), onSpawned: (a) => { enc.pending--; enc.actors.push(a); } };
        const a = world.spawn(s.kind, opts);
        if (a) { enc.pending--; enc.actors.push(a); }
        else if (!world.registry.kinds.has(s.kind)) enc.pending--;      // unknown kind: do not wait for it forever
      };
      if (s.delay > 0) after(s.delay, spawn); else spawn();
    }
    world.emit('encounterStart', { id: def.id, def, encounter: enc });
    if (def.onStart) { try { def.onStart(world, enc); } catch (e) { world.warnOnce('enc:' + def.id, def.id + '.onStart threw: ' + (e && e.message)); } }
    if (ctx.audio) ctx.audio.music('battle', { fade: 1.2 });
    return enc;
  }
  function clearEncounter() {
    const enc = flow.encounter;
    enc.cleared = true;
    const def = enc.def;
    world.emit('encounterEnd', { id: def.id, def, cleared: true });
    if (def.onClear) { try { def.onClear(world, enc); } catch (e) { world.warnOnce('encc:' + def.id, def.id + '.onClear threw: ' + (e && e.message)); } }
    flow.index++;
    if (def.boss || flow.index >= list.length) {
      flow.state = 'victory';
      world.emit('bossDefeated', { boss: enc.actors[0] || null, cycle: flow.cycle });
      save();
      if (ctx.audio) ctx.audio.music('victory', { fade: 1 });
      // a bot (soak / demo) rolls straight into the next cycle; a player presses the HUD's button (rpg.nextCycle())
      if (hero() && hero().controller && hero().controller.kind === 'bot') after(6, () => { if (flow.state === 'victory') nextCycle(); });
    } else {
      flow.state = 'explore';
      const next = list[flow.index];
      if (!next.trigger) after(next.boss ? 4 : 2.6, () => { if (flow.state === 'explore' && hero() && hero().alive) start(); });
    }
  }

  /** Remove the running encounter's actors (hero death / rest): it starts over later. */
  function resetEncounter() {
    const enc = flow.encounter;
    if (enc && !enc.cleared) {
      for (const a of enc.actors) if (!a.gone) world.despawn(a);
      world.queue.length = 0;
      world.emit('encounterEnd', { id: enc.def.id, def: enc.def, cleared: false });
      flow.encounter = null;
    }
    if (world.aiTokens) world.aiTokens.holders.clear();
    world.projectiles.clear();
  }

  // ---- altar, death, respawn --------------------------------------------------------------------------------------
  function placeAtAltar() {
    const h = hero();
    h.teleport(places.heroSpawn.x, places.heroSpawn.z, places.heroSpawn.yaw);
    if (world.camera) { world.camera.lock(null); world.camera.snap(places.heroSpawn.yaw); }
  }
  /** Sit at the altar: refill, respawn unfinished encounters. */
  function rest() {
    const h = hero();
    if (!h || !h.alive || flow.resting) return false;
    if (flow.state === 'encounter' || flow.state === 'boss') { const enc = flow.encounter; if (enc && !enc.cleared && enc.actors.some((a) => a.alive)) return false; }
    resetEncounter();
    flow.resting = true;
    if (flow.state !== 'victory') flow.state = 'altar';
    h.endAttack('cancel');
    h.setState('rest');
    h.yaw = yawTo(places.altar.x - h.pos.x, places.altar.z - h.pos.z);
    derive(true);
    save();
    world.emit('heroRest', { hero: h });
    if (ctx.audio) ctx.audio.music('title', { fade: 1.5 });
    return true;
  }
  function leave() {
    const h = hero();
    if (!h || !flow.resting) return;
    flow.resting = false;
    if (h.state === 'rest') h.setState('idle');
    world.emit('heroLeave', { hero: h });
  }
  function onHeroDeath() {
    const h = hero();
    flow.state = 'dead';
    // the shards stay where the hero fell (a previous unclaimed drop is lost)
    const amount = h.prog ? h.prog.shards : 0;
    if (flow.dropped) world.emit('shards', { amount: -flow.dropped.amount, total: 0, reason: 'lost' });
    setDropped(amount > 0 ? { x: h.pos.x, z: h.pos.z, amount } : null);
    if (h.prog) h.prog.shards = 0;
    world.emit('heroDeath', { hero: h, x: h.pos.x, z: h.pos.z, dropped: flow.dropped });
    save();
    after(3.4, () => { if (flow.state === 'dead') respawn(); });
  }
  /** Wake at the altar after death. */
  function respawn() {
    const h = hero();
    if (!h) return;
    resetEncounter();
    h.dead = false; h.alive = true;
    h.vel.x = h.vel.y = h.vel.z = 0;
    derive(true);
    h.ult = 0;
    h.setState('idle');
    h.react++;
    placeAtAltar();
    if (h.view) h.view.key = '';
    flow.state = flow.index > 0 ? 'explore' : 'altar';
    flow.resting = false;
    // back on the road: the next encounter waits behind the gate (or starts on its own once the hero walks out)
    armGate();
    world.emit('heroRespawn', { hero: h, x: h.pos.x, z: h.pos.z, dropped: flow.dropped });
    if (ctx.audio) ctx.audio.music('title', { fade: 1.5 });
  }

  /** Dropped shards: a marker + a walk-over reclaim trigger. */
  function setDropped(d) {
    if (droppedRemove) { droppedRemove(); droppedRemove = null; }
    if (droppedMark) { droppedMark.visible = false; }
    flow.dropped = d;
    if (!d) return;
    if (!droppedMark) {
      // a small upright shard of light (one pooled mesh; the world / HUD teams may add their own on `heroDeath`)
      const g = new THREE.OctahedronGeometry(0.22, 0);
      g.scale(0.55, 1.6, 0.55);
      const m = new THREE.MeshBasicMaterial({ color: new THREE.Color(1.6, 2.6, 5) });
      droppedMark = new THREE.Mesh(g, m);
      droppedMark.name = 'rpg-dropped-shards';
      ctx.scene.add(droppedMark);
    }
    droppedMark.position.set(d.x, 0.75, d.z);
    droppedMark.visible = true;
    droppedRemove = world.addTrigger({ x: d.x, z: d.z, r: 1.3, once: true, onEnter: () => {
      const amount = flow.dropped ? flow.dropped.amount : 0;
      setDropped(null);
      addShards(amount, 'reclaim');
      save();
      if (ctx.vfx) { try { ctx.vfx.play('game.burst', { pos: [d.x, 1, d.z] }, { element: 'frost', k: 0.8 }); } catch (e) { /* decoration */ } }
      if (ctx.audio) { try { ctx.audio.play('rune', { volume: 0.7 }); } catch (e) { /* optional */ } }
    } });
  }
  flow.setDropped = setDropped;

  /** The mist gate: walking through it starts the road (the first / next encounter). */
  let gateRemove = null;
  function armGate() {
    if (gateRemove) { gateRemove(); gateRemove = null; }
    if (o.sandbox) return;
    const g = places.gate;
    gateRemove = world.addTrigger({ x: g.x, z: g.z, r: g.r, once: true, onEnter: () => {
      gateRemove = null;
      if (flow.state !== 'altar' && flow.state !== 'explore') return;
      if (flow.encounter && !flow.encounter.cleared) return;
      world.emit('gate', { hero: hero() });
      if (flow.index < list.length) { flow.state = 'explore'; after(0.6, () => { if (hero() && hero().alive && (!flow.encounter || flow.encounter.cleared)) start(); }); }
    } });
  }

  /** After the victory banner: a new cycle, everything respawns stronger. */
  function nextCycle() {
    flow.cycle++;
    flow.index = 0;
    flow.encounter = null;
    flow.state = 'explore';
    world.emit('cycle', { cycle: flow.cycle });
    save();
    armGate();
    const h = hero();
    // the road starts again on its own if the hero is already past the gate
    if (h && hypot2(h.pos.x - places.gate.x, h.pos.z - places.gate.z) > places.gate.r + 1) after(2.5, () => { if (flow.state === 'explore' && !flow.encounter) start(); });
    if (ctx.audio) ctx.audio.music('battle', { fade: 1.5 });
  }

  // ---- world events ---------------------------------------------------------------------------------------------------
  removers.push(world.on('death', (e) => {
    const a = e.actor;
    if (a === hero()) { onHeroDeath(); return; }
    if (e.shards > 0) addShards(e.shards, a.spec.boss ? 'boss' : 'kill');
  }));

  /** Per fixed step. */
  function step(dt) {
    for (let i = timers.length - 1; i >= 0; i--) {
      const t = timers[i];
      t.left -= dt;
      if (t.left <= 0) { timers.splice(i, 1); t.fn(); }
    }
    const enc = flow.encounter;
    if (enc && !enc.cleared) {
      enc.time += dt;
      if (enc.def.update) enc.def.update(world, enc, dt);
      if (enc.pending <= 0 && world.queue.length === 0) {
        let alive = 0;
        for (const a of enc.actors) if (!a.dead && !a.gone) alive++;
        if (alive === 0 && enc.actors.length > 0) clearEncounter();
      }
    }
    if (droppedMark && droppedMark.visible) { droppedMark.rotation.y += dt * 1.6; droppedMark.position.y = 0.75 + Math.sin(world.time * 2.2) * 0.08; }
  }

  /** Begin: hero state from the save, at the altar (or wherever a sandbox puts it). */
  flow.begin = () => {
    const h = hero();
    if (h && progress) {
      h.prog = progress.load(h.spec.hero);
      flow.cycle = h.prog.cycle || 0;
      derive(true);
      if (h.prog.dropped && !o.sandbox) setDropped({ ...h.prog.dropped });
    }
    if (o.sandbox) return;
    placeAtAltar();
    // the altar: rest / level up whenever no fight is on
    const al = places.altar;
    removers.push(world.addCollider({ type: 'circle', x: al.x, z: al.z, r: 0.75 }));
    removers.push(world.addTrigger({ x: al.x, z: al.z, r: 2.4, prompt: { ko: '별빛 제단에서 쉬기', en: 'Rest at the Starlit Altar' },
      enabled: () => !flow.resting && !(flow.encounter && !flow.encounter.cleared && flow.encounter.actors.some((a) => a.alive)),
      interact: () => rest() }));
    armGate();
    if (o.encounter) { const i = list.findIndex((e) => e.id === o.encounter); if (i >= 0) { flow.index = i; flow.state = 'explore'; const sp = list[i].heroAt || { x: -2, z: 0, yaw: 0 }; h.teleport(sp.x, sp.z, sp.yaw); if (world.camera) world.camera.snap(sp.yaw); after(0.3, () => start()); } }
  };

  function dispose() {
    for (const r of removers) r();
    if (gateRemove) gateRemove();
    if (droppedRemove) droppedRemove();
    if (droppedMark) { droppedMark.removeFromParent(); droppedMark.geometry.dispose(); droppedMark.material.dispose(); droppedMark = null; }
    timers.length = 0;
  }

  return flow;
}
