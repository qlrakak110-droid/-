// World of the RPG mode: actors, colliders, triggers, events and the fixed 60 Hz step (README §4).
//
//   const world = createWorld(ctx, { registry, seed });
//   world.spawn('husk', { x: 4, z: 0 });  world.step(1 / 60);  world.on('hit', (e) => {});
//
// Step order: controllers -> actor machines (attack timelines, movement) -> collisions -> strikes -> projectiles ->
// triggers -> flow -> deaths. Everything is deterministic (world.rng) and allocation-free except event payloads.

import { makeRng } from '../../core/math.js';
import { STEP, hypot2, yawTo } from './math3.js';
import { createActor, stepActor, resetIntent, disposeActor } from './actor.js';
import { resolveStrikes, resolveHit, applyDamage } from './combat.js';
import { createProjectiles } from './projectiles.js';
import { normalizeAttack } from './attacks.js';

/**
 * @param {object} ctx
 * @param {{ registry: object, seed?: number }} o
 */
export function createWorld(ctx, o) {
  const registry = o.registry;
  const handlers = new Map();
  let nextId = 1;
  const scratch = [];

  const world = {
    ctx, registry,
    rng: makeRng((o.seed ?? 20261113) >>> 0),
    time: 0, frame: 0,
    actors: [],
    hero: null,
    arena: { radius: 15.1 },
    colliders: [],
    triggers: [],
    /** ordinary foes alive at once (budget): 4, 3 on the low tier */
    maxFoes: ctx.quality && ctx.quality.tier === 'low' ? 3 : 4,
    /** spawns waiting for a free slot */
    queue: [],
    /** world freeze (ultimate super-freeze / cinematic lock): actors not in `owners` do not step */
    freeze: null,
    /** running cinematic lock (core/present.js) */
    lock: null,
    flow: null, camera: null, present: null,
    projectiles: null,
    /** test switch: the hero takes no damage */
    godMode: false,
    /** interact prompt currently offered to the hero ({ ko, en, trigger }) */
    prompt: null,

    // ---- events ---------------------------------------------------------------------------------------------------
    on(name, fn) {
      let list = handlers.get(name);
      if (!list) handlers.set(name, (list = []));
      list.push(fn);
      return () => { const i = list.indexOf(fn); if (i >= 0) list.splice(i, 1); };
    },
    emit(name, e) {
      const list = handlers.get(name);
      if (list) for (let i = 0; i < list.length; i++) { try { list[i](e, name); } catch (err) { warnOnce('ev:' + name, 'listener of ' + name + ' threw: ' + (err && (err.stack || err.message))); } }
      const all = handlers.get('*');
      if (all) for (let i = 0; i < all.length; i++) { try { all[i](e, name); } catch (err) { warnOnce('ev:*' + name, 'listener (*) of ' + name + ' threw: ' + (err && (err.stack || err.message))); } }
    },

    // ---- actors ---------------------------------------------------------------------------------------------------
    /**
     * Create an actor of a registered kind. Ordinary foes beyond world.maxFoes are queued and enter as others die.
     * @returns {object|null} the actor (null when queued)
     */
    spawn(kind, opts = {}) {
      const spec = registry.kinds.get(kind);
      if (!spec) { warnOnce('kind:' + kind, 'unknown actor kind "' + kind + '"'); return null; }
      if ((spec.budget || 'foe') === 'foe' && spec.team !== 'hero' && !opts.force && countFoes() >= world.maxFoes) {
        world.queue.push({ kind, opts });
        return null;
      }
      const actor = createActor(world, spec, nextId++, opts);
      world.actors.push(actor);
      if (spec.team === 'hero' && !world.hero) world.hero = actor;
      if (spec.onSpawn) { try { spec.onSpawn(world, actor, opts); } catch (e) { warnOnce('onSpawn:' + kind, kind + '.onSpawn threw: ' + (e && e.message)); } }
      world.emit('spawn', { actor });
      return actor;
    },
    /** Remove an actor (immediately; `fade` seconds of dissolve are presentational). */
    despawn(actor, { fade = 0 } = {}) {
      if (!actor || actor.gone) return;
      if (fade > 0 && !actor.leaving) { actor.leaving = fade; actor.leaveDur = fade; actor.alive = false; return; }
      actor.gone = true;
      actor.alive = false;
      const i = world.actors.indexOf(actor);
      if (i >= 0) world.actors.splice(i, 1);
      world.emit('despawn', { actor });
      if (world.camera && world.camera.target === actor) world.camera.lock(null);
      for (const a of world.actors) if (a.target === actor) a.target = null;
      disposeActor(world, actor);
      if (world.hero === actor) world.hero = null;
    },
    /** Hostile live actors within `range` of `actor`, nearest first (shared scratch array: do not keep). */
    findTargets(actor, range = 20) {
      scratch.length = 0;
      for (let i = 0; i < world.actors.length; i++) {
        const b = world.actors[i];
        if (b === actor || !b.alive || !hostile(actor, b)) continue;
        const d = hypot2(b.pos.x - actor.pos.x, b.pos.z - actor.pos.z);
        if (d > range + b.radius) continue;
        b._d = d;
        scratch.push(b);
      }
      scratch.sort(byDist);
      return scratch;
    },
    byId(id) { for (const a of world.actors) if (a.id === id) return a; return null; },
    hostile,

    // ---- colliders / triggers ---------------------------------------------------------------------------------------
    addCollider(c) {
      const col = { type: 'circle', x: 0, z: 0, r: 1, hx: 1, hz: 1, yaw: 0, blocksCamera: true, height: 3, ...c };
      world.colliders.push(col);
      return () => { const i = world.colliders.indexOf(col); if (i >= 0) world.colliders.splice(i, 1); };
    },
    addTrigger(t) {
      const trig = { x: 0, z: 0, r: 1.5, team: 'hero', once: false, inside: false, dead: false, ...t };
      world.triggers.push(trig);
      return () => { trig.dead = true; const i = world.triggers.indexOf(trig); if (i >= 0) world.triggers.splice(i, 1); if (world.prompt && world.prompt.trigger === trig) setPrompt(null); };
    },

    // ---- combat passthroughs -----------------------------------------------------------------------------------------
    /** Start an attack of the actor's kind (or a definition) now. */
    startAttack(actor, idOrDef, opts = {}) { return actor.startAttack(idOrDef, opts); },
    /** Damage outside an attack timeline (hazards, scripts): the full hit resolution. */
    damage(victim, d = {}) { return applyDamage(world, victim, d); },
    resolveHit(attacker, victim, atk, hit, info) { return resolveHit(world, attacker, victim, atk, hit, info); },
    /** 3D projectile (README §6.4). */
    shoot(owner, spec) { return world.projectiles.shoot(owner, spec); },
    hitstop(sec) { if (sec > 0) ctx.time.hitstop(sec); },
    slowmo(scale, dur, opts) { return ctx.time.slowmo(scale, dur, opts); },
    /** Normalised attack of a kind by id. */
    attackOf(actor, id) {
      const table = actor.spec.attacks;
      if (!table || !table[id]) return null;
      if (!table[id].normalized) table[id] = normalizeAttack(table[id], id);
      return table[id];
    },

    step, dispose,
  };
  world.projectiles = createProjectiles(world);

  const warned = new Set();
  function warnOnce(key, msg) {
    if (warned.has(key)) return;
    warned.add(key);
    console.warn('[ed] rpg: ' + msg);
  }
  world.warnOnce = warnOnce;

  function byDist(a, b) { return a._d - b._d; }
  function hostile(a, b) {
    if (a.team === b.team) return false;
    if (a.team === 'neutral') return false;
    // neutral things (training dummies) can be hit by the hero only
    if (b.team === 'neutral') return a.team === 'hero';
    return true;
  }
  function countFoes() {
    let n = 0;
    for (const a of world.actors) if (a.team !== 'hero' && (a.spec.budget || 'foe') === 'foe' && !a.gone && !a.dead) n++;
    return n;
  }
  function setPrompt(p) {
    if (world.prompt === p) return;
    world.prompt = p;
    world.emit('prompt', { prompt: p });
  }

  // ---- the step ---------------------------------------------------------------------------------------------------
  function frozen(a) { return world.freeze !== null && world.freeze.owners.indexOf(a) < 0; }
  world.frozen = frozen;

  /** Advance the world by one fixed step. */
  function step(dt = STEP) {
    world.time += dt;
    world.frame++;
    const actors = world.actors;
    if (world.freeze) {
      world.freeze.left -= dt;
      if (world.freeze.left <= 0) { const f = world.freeze; world.freeze = null; if (f.onEnd) f.onEnd(); }
    }
    for (let i = 0; i < actors.length; i++) {
      const a = actors[i];
      a.prev.x = a.pos.x; a.prev.y = a.pos.y; a.prev.z = a.pos.z; a.prevYaw = a.yaw;
    }
    // controllers
    for (let i = 0; i < actors.length; i++) {
      const a = actors[i];
      resetIntent(a.intent);
      if (!a.alive || a.cine || frozen(a) || !a.controller) continue;
      a.controller.think(world, a, dt, a.intent);
    }
    // machines
    for (let i = 0; i < actors.length; i++) {
      const a = actors[i];
      if (a.gone) continue;
      if (frozen(a)) continue;
      stepActor(world, a, dt);
    }
    collide(dt);
    if (world.present) world.present.stepLock(dt);
    resolveStrikes(world);
    if (!world.freeze) world.projectiles.step(dt);
    stepTriggers();
    if (world.flow) world.flow.step(dt);
    // leaving actors, queued spawns
    for (let i = actors.length - 1; i >= 0; i--) {
      const a = actors[i];
      if (a.leaving > 0) { a.leaving -= dt; if (a.leaving <= 0) world.despawn(a); }
    }
    if (world.queue.length && countFoes() < world.maxFoes) {
      const q = world.queue.shift();
      const a = world.spawn(q.kind, q.opts);
      if (a && q.opts.onSpawned) q.opts.onSpawned(a);
    }
  }

  // ---- collisions -------------------------------------------------------------------------------------------------
  function collide() {
    const actors = world.actors;
    const n = actors.length;
    // soft body push (two passes are plenty for a handful of actors)
    for (let i = 0; i < n; i++) {
      const a = actors[i];
      if (!solid(a)) continue;
      for (let j = i + 1; j < n; j++) {
        const b = actors[j];
        if (!solid(b)) continue;
        if ((a.ghost || b.ghost) && a.team !== b.team) continue;   // rolling / passing through
        const dx = b.pos.x - a.pos.x, dz = b.pos.z - a.pos.z;
        const min = a.radius + b.radius;
        const d2 = dx * dx + dz * dz;
        if (d2 >= min * min) continue;
        if (Math.abs(a.pos.y - b.pos.y) > Math.max(a.height, b.height)) continue;
        let d = Math.sqrt(d2), nx, nz;
        if (d < 1e-4) { nx = Math.cos(a.id * 2.4); nz = Math.sin(a.id * 2.4); d = 0; } else { nx = dx / d; nz = dz / d; }
        const push = min - d;
        const ma = a.immovable ? 1e6 : a.mass, mb = b.immovable ? 1e6 : b.mass;
        const ka = mb / (ma + mb), kb = ma / (ma + mb);
        a.pos.x -= nx * push * ka; a.pos.z -= nz * push * ka;
        b.pos.x += nx * push * kb; b.pos.z += nz * push * kb;
      }
    }
    const R = world.arena.radius;
    for (let i = 0; i < n; i++) {
      const a = actors[i];
      if (a.gone || a.noclip) continue;
      const cols = world.colliders;
      for (let k = 0; k < cols.length; k++) pushOut(a, cols[k]);
      const lim = R - a.radius * 0.6;
      const d = hypot2(a.pos.x, a.pos.z);
      if (d > lim) {
        const s = lim / d;
        a.pos.x *= s; a.pos.z *= s;
        if (a.state === 'launched' || a.state === 'stagger') { a.vel.x *= 0.2; a.vel.z *= 0.2; }
      }
    }
  }
  const solid = (a) => !a.gone && !a.noclip && a.state !== 'dead' && a.state !== 'down' && !(a.leaving > 0);

  /** Push an actor out of a static collider. */
  function pushOut(a, c) {
    if (c.type === 'circle') {
      const dx = a.pos.x - c.x, dz = a.pos.z - c.z, min = c.r + a.radius;
      const d2 = dx * dx + dz * dz;
      if (d2 >= min * min) return;
      const d = Math.sqrt(d2);
      if (d < 1e-4) { a.pos.x = c.x + min; return; }
      a.pos.x = c.x + (dx / d) * min; a.pos.z = c.z + (dz / d) * min;
      return;
    }
    // oriented box: closest point in the box frame
    const cs = Math.cos(c.yaw), sn = Math.sin(c.yaw);
    const dx = a.pos.x - c.x, dz = a.pos.z - c.z;
    const lx = dx * cs - dz * sn, lz = dx * sn + dz * cs;       // world -> box (box +X = (cos, 0, -sin))
    const px = Math.max(-c.hx, Math.min(c.hx, lx)), pz = Math.max(-c.hz, Math.min(c.hz, lz));
    let ox = lx - px, oz = lz - pz;
    const d2 = ox * ox + oz * oz;
    if (d2 >= a.radius * a.radius) return;
    let nx, nz, pen;
    if (d2 > 1e-8) { const d = Math.sqrt(d2); nx = ox / d; nz = oz / d; pen = a.radius - d; } else {
      // centre inside the box: leave through the nearest face
      const ex = c.hx - Math.abs(lx), ez = c.hz - Math.abs(lz);
      if (ex < ez) { nx = Math.sign(lx) || 1; nz = 0; pen = ex + a.radius; } else { nx = 0; nz = Math.sign(lz) || 1; pen = ez + a.radius; }
    }
    ox = nx * pen; oz = nz * pen;
    a.pos.x += ox * cs + oz * sn; a.pos.z += -ox * sn + oz * cs;
  }

  // ---- triggers ---------------------------------------------------------------------------------------------------
  function stepTriggers() {
    const hero = world.hero;
    let prompt = null;
    for (let i = world.triggers.length - 1; i >= 0; i--) {
      const t = world.triggers[i];
      if (t.dead) continue;
      const who = hero;   // triggers watch the hero (team 'hero'); foes never open gates
      const inside = !!who && who.alive && hypot2(who.pos.x - t.x, who.pos.z - t.z) <= t.r;
      if (inside && !t.inside) {
        t.inside = true;
        if (t.onEnter) t.onEnter(who, t);
        if (t.once && !t.interact) { t.dead = true; world.triggers.splice(i, 1); continue; }
      } else if (!inside && t.inside) {
        t.inside = false;
        if (t.onLeave) t.onLeave(who, t);
      }
      if (inside && t.interact && t.prompt && (!t.enabled || t.enabled())) {
        if (!prompt) { if (!t._p) t._p = { ko: t.prompt.ko, en: t.prompt.en, key: 'E', trigger: t }; prompt = t._p; }
      }
    }
    setPrompt(prompt);
    if (prompt && hero && hero.intent.interact && (hero.state === 'idle' || hero.state === 'move')) {
      const t = prompt.trigger;
      world.emit('interact', { trigger: t, actor: hero });
      t.interact(hero, t);
      if (t.once) { t.dead = true; const i = world.triggers.indexOf(t); if (i >= 0) world.triggers.splice(i, 1); setPrompt(null); }
    }
  }

  /** Yaw from an actor toward a point / another actor. */
  world.yawBetween = (a, b) => yawTo((b.pos ? b.pos.x : b.x) - a.pos.x, (b.pos ? b.pos.z : b.z) - a.pos.z);

  function dispose() {
    world.projectiles.clear();
    for (let i = world.actors.length - 1; i >= 0; i--) { const a = world.actors[i]; a.gone = true; disposeActor(world, a); }
    world.actors.length = 0;
    world.queue.length = 0;
    world.colliders.length = 0;
    world.triggers.length = 0;
    handlers.clear();
    world.hero = null;
  }

  return world;
}
