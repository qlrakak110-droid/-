# src/rpg — 「강호행 江湖行」 (action-RPG mode; first brief: "일식 원정 · Eclipse Expedition")

A lone hero (`kael` / `iska` / `vorn`, reused as they are: designs, clips, move data, choreography) walks the arena
in free 3D behind a third-person camera: stamina melee, rolls with i-frames, guard / perfect guard, lock-on, three
heals, a rest point to recover and level at, encounters and a colossal boss. This file is the contract between the
core (this folder's `index.js`, `core/`, `camera.js`) and the teams that plug into it.

**Names.** Code identifiers follow the first brief and do not change; what the player reads follows `MURIM.md` §6
(the binding art direction). Use the right-hand column in every visible string:

| code / API name | brief | shown to the player (MURIM.md) |
|---|---|---|
| the mode, `rpg`, `#rpg=` | Eclipse Expedition | 「강호행 江湖行」 |
| `altar`, `flow.rest()`, `heroRest` | Starlit Altar | 「정심석 靜心石」, resting = 운기조식 運氣調息 |
| `chalice`, `drink` | Dawn Chalice | 「회천단 回天丹」 (three pills in a gourd) |
| `shards` | Eclipse Shards | 「공력 功力」 |
| stats `vigor` / `endurance` / `might` / `arcana` | Vigor / Endurance / Might / Arcana | 근골 筋骨 / 기식 氣息 / 외공 外功 / 내공 內功 |
| `level` (`progress.rank(level)`) | level | 경지 境地: 삼류 → 이류 → 일류 → 절정 → 초절정 → 화경 → 현경 |
| `fp`, `ult`, `hp` | FP / ultimate / HP | 내공 內功 / 오의 奧義 / 기혈 氣血 |
| foes, elite, `boss` | Ruin Sentinel / elite / Eclipse Colossus | 흑일교 무사 / 흑일교 호법 / 「흑일마신상 黑日魔神像」 |
| `gate` | mist gate | the mist curtain between two leaning gate pillars |

| folder | owner | plugs in through |
|---|---|---|
| `src/rpg/index.js`, `core/**`, `camera.js`, `registry.js`, `tests/**` | core | — |
| `src/rpg/boss/**` | boss | `export default function install(rpg)` in `boss/index.js` |
| `src/rpg/foes/**`, `src/rpg/world/**` | foes / world | `foes/index.js`, `world/index.js` (same `install(rpg)`) |
| `src/rpg/ui/**`, `src/rpg/progress.js` | hud | `ui/index.js` (`install(rpg)`), `progress.js` (`export default` a progress object or `install(rpg)`) |

**A missing folder is fine**: `registry.js` discovers `./<name>/index.js` and `./progress.js` with esbuild glob imports
(a missing module is a runtime miss, never a build error) and the core ships defaults for everything (a training
dummy, a melee husk, a three-step expedition with a stand-in boss, a debug HUD, default progression).

```
src/rpg/index.js            createRpg(ctx, { fighters, fx }) -> ctx.rpg: start / stop, fixed-step loop, test API
src/rpg/registry.js         the plug-in registry (`rpg.actor / attack kinds / encounter / world / ui / progress`)
src/rpg/camera.js           third-person camera: follow, free look, lock-on, wall collision, boss framing, cinematics
src/rpg/core/world.js       world state: actors, colliders, triggers, events, the 60 Hz step
src/rpg/core/actor.js       Actor + the humanoid state machine (locomotion, roll, guard, attacks, reactions, death)
src/rpg/core/combat.js      attack timelines, 3D hit volumes, hit resolution, stamina / poise, hit-stop
src/rpg/core/attacks.js     attack definition normaliser; fighter move data -> RPG attack
src/rpg/core/projectiles.js 3D projectiles (hero skills, enemy shots)
src/rpg/core/hero.js        hero spec per fighter (stats, move mapping, clips), human controller
src/rpg/core/bot.js         autoplaying hero AI (`#rpgbot`, soak tests, captures)
src/rpg/core/stage.js       the stage frame: fighter choreography and VFX presets (authored on the duel's X line) at any yaw
src/rpg/core/present.js     adapter: `src/fighters/<id>/present.js` handlers on RPG actors (helper `h`), ultimates, generic feel
src/rpg/core/kinds.js       built-in actor kinds: `dummy` (training post), `husk` (simple melee AI)
src/rpg/core/flow.js        the expedition loop (altar -> encounters -> boss -> new cycle), death / respawn, shards
src/rpg/core/progress.js    default progression (stats -> multipliers, level cost, save / load)
src/rpg/core/debughud.js    minimal built-in HUD (used until `ui/index.js` registers one)
src/rpg/core/feel.js        generic feel of every event (sparks, shake, sound, dust, projectile bodies) in stage frames
src/rpg/core/standin.js     stand-in rest stone + gate posts (until `world/` registers the real dressing)
src/rpg/core/clips/         `rpg.<hero>.run / sprint / roll / drink / death / rest` (+ `rpg.husk.rise`)
src/rpg/tests/              smoke.mjs, soak.mjs, gait.mjs, sheets.mjs, profile.mjs
```

---

## 1. Running it

```sh
node tools/shot.mjs game --as rpg-core --hash "rpg=kael" --size 960x540 --at 1,2,3 --sheet-only --out shots/rpg/core/boot
node tools/shot.mjs game --as rpg-core --hash "rpg=iska&rpgbot" --size 960x540 --at 5,10,15 --sheet-only --out shots/rpg/core/bot
node tools/shot.mjs game --as rpg-core --size 640x360 --scenario src/rpg/tests/smoke.mjs      # PASS / FAIL lines, every hero
node tools/shot.mjs game --as rpg-core --size 320x180 --scenario src/rpg/tests/soak.mjs       # bot vs 3 husks, 3 simulated minutes
node tools/shot.mjs game --as rpg-core --size 320x180 --scenario src/rpg/tests/gait.mjs       # planted-foot slide of run / sprint
HERO=vorn SECTIONS=circle,chain,ult node tools/shot.mjs game --as rpg-core --size 960x540 --scenario src/rpg/tests/sheets.mjs --sheet 6 --sheet-only --out shots/rpg/core/vorn
node tools/shot.mjs game --as rpg-core --hash "prof&q=high" --size 960x540 --scenario src/rpg/tests/profile.mjs
```

| URL flag | effect |
|---|---|
| `#rpg=kael\|iska\|vorn` | boot straight into the expedition with that hero (`#rpg` alone = kael) |
| `#rpgbot` | the hero is played by the bot (`core/bot.js`) |
| `#rpgenc=<id>` | start at that encounter (skips the walk from the altar) |
| `#rpgsandbox` | no expedition flow: an empty arena with one training dummy (tests, captures, tuning) |
| `#rpgdebug` | draw hit volumes, body cylinders, colliders and triggers (`world.debugShapes`) |
| `#seed=N`, `#q=`, `#prof`, `#test` | as in the duel |

The duel game is untouched: `createRpg` is created next to `createGame` in `src/main.js`; the title screen has a
`강호행 江湖行` row with one button per hero (`ui` event `expedition`, hero id); `game.expedition(hero)` →
`rpg.start(hero)` (which calls `game.leaveForRpg()`: the duel session is disposed) and `rpg.toTitle()` → `game.title()`.

---

## 2. Space, time, conventions

* **World**: metres, Y up, the floor is `y = 0`, the arena centre is the origin, the walkable disc has radius
  `world.arena.radius` (15.1 = `LAYOUT.floorR` 15.6 minus a body). Actors live on the XZ plane (`pos.y` = height
  above the floor, 0 when grounded).
* **Yaw** (radians, about +Y): `yaw = 0` faces `+X`; forward `F = (cos yaw, 0, -sin yaw)`, right `R = (sin yaw, 0, cos yaw)`.
  It is `char.root.rotation.y` (the characters' model forward is +X; RPG actors are never mirrored: facing stays +1).
  Helpers in `core/math3.js`: `yawTo(dx, dz)`, `fwdX(yaw)`, `fwdZ(yaw)`, `angDiff(a, b)`, `turnToward(yaw, target, maxStep)`.
* **Actor-local frame `[f, u, s]`**: forward, up, side = the actor's **right** (the same frame the fighters' clips,
  hit boxes and choreography are authored in; in the duel `s` happened to point at the camera).
  `world = pos + f * F + s * R`, height `u` above the floor.
* **Time**: the simulation advances in **fixed 1/60 s steps of game time** (`ctx.time.dtGame`: slow motion stretches
  it, hit-stop freezes it, pause stops it). Presentation interpolates positions between the last two steps. Every hit
  calls `ctx.time.hitstop()`: in this mode a hit-stop freezes the whole world (one hero against many), which is also
  what choreography `h.hitstop()` does.
* **Determinism**: `world.rng` (seeded from `#seed`), no `Math.random()`, no wall clock. The same inputs give the
  same run in `#test` mode.
* **No per-frame allocations** in `world.step`, the camera, the snapshot and the HUD path (events reuse nothing: an
  event payload is a fresh object, but events only fire on hits / state changes).

---

## 3. The registry — how a team plugs in

```js
// src/rpg/foes/index.js
import { defineClip } from '../../char/index.js';
export default function install(rpg) {
  rpg.actor('cultist', { ...kind spec, section 5... });
  rpg.encounter({ id: 'cultists', order: 10, title: { ko: '흑일교 무사들', en: 'BLACK SUN CULTISTS' },
    spawns: [{ kind: 'cultist', x: 4, z: -3 }, { kind: 'cultist', x: 6, z: 1 }, { kind: 'cultist', x: 4, z: 4 }] });
}
```

`install(rpg)` runs once, before the first `rpg.start()` (so presets / clips / materials it defines are prewarmed
with everything else). `rpg` is the registry:

| call | meaning |
|---|---|
| `rpg.actor(kind, spec)` | register (or replace) an actor kind — section 5 |
| `rpg.encounter(def)` | register (or replace by `id`) an encounter — section 9. As soon as a plug-in registers an ordinary encounter, the core's two stand-in encounters leave the playlist; a plug-in encounter with `boss: true` replaces the stand-in boss encounter |
| `rpg.world(factory)` | `factory(ctx, world) -> { update?(dtGame, dtReal), dispose?(), altar?: {x, z, yaw}, gate?: {x, z, yaw, r}, heroSpawn?: {x, z, yaw} }`: world dressing, colliders, triggers — section 8. Called at every `start()` (not in `#rpgsandbox`), before the hero exists |
| `rpg.ui(factory)` | `factory(ctx, api) -> { start(snapshot), stop(), update(snapshot, dtReal), dispose?() }`: replaces the debug HUD — section 11 |
| `rpg.progress(obj)` | replaces the default progression — section 12 |
| `rpg.setup(fn)` | `fn({ ctx, vfx, fx })` once at boot, right after every plug-in installed (define VFX presets, particle definitions); `vfx.prewarm()` runs again afterwards |
| `rpg.prewarm(fn)` | `fn(ctx, world)` at every `rpg.start()` before the compile pass (`renderer.compile` of the scene and the distortion scene): build pooled meshes / hidden instances so no program compiles mid-fight |
| `rpg.playlist()` | the encounters that will be played, in order |
| `rpg.on(event, fn)` | subscribe to world events for the lifetime of the page (re-bound to every new world) — section 7 |
| `rpg.kinds`, `rpg.encounters` | what is registered (Maps) |

Everything else a plug-in needs is on the **world** (`world`, section 4) that its hooks receive, or on `ctx.rpg`
(the mode object, section 13).

---

## 4. World

`ctx.rpg.world` exists while the mode runs (a new one per `start()`).

| member | meaning |
|---|---|
| `world.ctx`, `world.rng`, `world.time` | app context, seeded rng, simulated seconds |
| `world.actors` | live actors (array; do not hold indices) |
| `world.hero` | the hero actor |
| `world.arena` | `{ radius: 15.1 }` walkable disc |
| `world.spawn(kind, { x, z, yaw = toward the hero, level = cycle, ...opts }) -> actor` | create an actor of a registered kind (budget: at most `world.maxFoes` ordinary foes alive: 4, 3 on low; extra spawns are queued and enter as others die) |
| `world.despawn(actor, { fade = 0.6 })` | remove (dissolve) an actor |
| `world.on(event, fn) -> off` | world events (section 7) |
| `world.emit(event, payload)` | plug-ins may emit their own events (`bossPhase`, `bossIntro` ...) |
| `world.addCollider(c) -> remove()` | static obstacle: `{ type: 'circle', x, z, r }` or `{ type: 'box', x, z, hx, hz, yaw = 0 }` (+ `blocksCamera = true`, `height = 3`). Actors and the camera are pushed out of it |
| `world.addTrigger(t) -> remove()` | `{ x, z, r, team = 'hero', once = false, onEnter(actor)?, onLeave(actor)?, prompt?: { ko, en }, interact?(actor) }`; a trigger with `interact` shows its prompt and fires on the `interact` action (E) |
| `world.startAttack(actor, id | def, { target?, force? }) -> bool` | start an attack now (section 6) |
| `world.damage(victim, { amount, poise = 0, level = 'light', from?: actor, pos?, dir?, kind = 'effect', unblockable?, hitstop? })` | apply damage outside an attack timeline (hazards, boss scripts): the full hit resolution (i-frames, guard, poise, reactions, events) |
| `world.shoot(owner, spec) -> projectile` | 3D projectile (section 6.4) |
| `world.hitstop(sec)`, `world.slowmo(scale, dur)` | `ctx.time` passthroughs |
| `world.findTargets(actor, range)` | hostile live actors within range (sorted by distance; scratch array) |
| `world.byId(id)`, `world.hostile(a, b)`, `world.frozen(actor)` | lookup; may a hit b (teams; `neutral` is hit by the hero only); is the actor held by a world freeze |
| `world.fxAt(actor, preset, [f, u, s], opts)` | play a VFX preset at a point of the actor frame, oriented with the actor (stage frame, section 6.5) |
| `world.freeze` | `{ owners: [actors], left, onEnd }` or null: everyone but the owners (and projectiles) is held (super-freeze, lock, boss cinematics) |
| `world.present` | the choreography adapter: `sound(name, { pos })`, `call(actor, fn, key, e)`, `helperOf(actor)` (the `h` of section 6.5), `feel` |
| `world.flow` | the expedition flow (section 9) |
| `world.camera` | the third-person camera (section 10) |

### Collisions

Actors are vertical cylinders (`radius`, `height`). Each step: actor-vs-actor soft push (a rolling actor passes through
foes; `spec.stats.mass` weighs the push; the boss is immovable), then static colliders, then the arena wall. The camera
collides with `world.arena.radius + 0.35` and every collider with `blocksCamera`.

---

## 5. Actors

Hero, enemies and the boss are the same object:

```js
actor = {
  id,                       // unique int
  kind, spec,               // registered kind name + its spec
  team,                     // 'hero' | 'foe' | 'neutral' (friendly fire is off inside a team)
  pos: { x, y, z }, yaw,    // floor position (y = height above the floor), facing
  vel: { x, y, z },         // knockback / launch velocity (decays with friction; gravity while airborne)
  radius, height, scale,    // body cylinder; scale = body size relative to 1.9 m (camera framing, VFX scale)
  hp, hpMax, poise, poiseMax,
  stamina, staminaMax, fp, fpMax, ult, ultMax,      // heroes (enemies: stamina is Infinity unless the spec gives it)
  state, stateTime, stateDur,                       // state machine (below)
  attack,                   // running attack instance | null: { def, id, t, tPrev, serial, hitCount, target, connected, contact }
  target,                   // the actor it fights (hero: the lock-on target or the soft target)
  intent,                   // what its controller asked for this step (section 5.3)
  controller,               // { think(world, actor, dt, intent) }
  char,                     // src/char Character (or spec.create()'s object) — world matrices valid after ORDER.CHAR
  view, clips,              // presentation (core/view.js): view.pos (interpolated root), view.play / setOffset / flash /
                            // impulse / glow / trailStart; clips.state(slot) / clips.move(attackId) -> { name, ... }
  alive, dead, gone, invuln, armour, guarding, ghost,   // flags refreshed every step (ghost: passes through foes)
  cine,                     // true: the machine and the clip selection stand back (choreography / scripts drive it)
  level, mult: { damage, hp },                      // scaling (cycle / level)
  data,                     // free per-kind storage (AI memory, boss phase ...)
  // helpers
  at(f, u, s, out) -> world Vector3 in the actor frame;  socket(name, out) -> world position of a char socket
  distTo(other), angleTo(other) (signed rad from its facing),
  setState(name, dur), stun(kind, dur, { vx, vz, vy }), startAttack(idOrDef, { target, force, aim }), endAttack(reason),
  die(by), teleport(x, z, yaw)
}
```

### 5.1 States (the humanoid machine in `core/actor.js`)

| state | entered by | notes |
|---|---|---|
| `spawn` | `world.spawn` (`spec.spawnTime`, default 0.6 s) | invulnerable, plays `clips.spawn` |
| `idle`, `move` | default | `move` covers walk / run / sprint (`actor.moveSpeed` is the current speed) |
| `attack` | `intent.attack` | `actor.attack` runs its timeline; ends in `idle` (or a queued cancel) |
| `roll` | `intent.roll` | i-frames `spec.roll.invuln` (default 0.04–0.34 s), travels `spec.roll.distance`, stamina cost |
| `guard` | `intent.guard` held | `actor.guardTime` counts from the raise: `< spec.guard.perfect` (0.16 s) = perfect guard |
| `guardhit` | a blocked hit | short block stun, pushed back |
| `flinch` / `stagger` | light / heavy hit | `stagger` also follows a guard break, a perfect guard taken and a poise break |
| `launched` → `down` → `getup` | launch / knockdown / crumple hits | airborne, lying, rising (invulnerable while `down`, `getup`) |
| `drink` | `intent.drink` | hero: the Dawn Chalice (`spec.drink`: heal at 0.9 s of 1.5 s; interruptible = punishable) |
| `rest` | flow | sitting at the altar (controller ignored) |
| `dead` | hp 0 | `death` event; foes dissolve after `spec.corpseTime` (2.5 s), the hero respawns through the flow |
| `cine` | `actor.cine = true` | the choreography / a boss script owns the clip and the root; the machine only keeps timers |
| any custom string | `spec.step` | a kind with its own machine (the boss) may use its own state names |

`actor.setState(name, dur?)` changes state (emits `state`), `actor.stun(kind, dur)` forces a reaction.

### 5.2 Kind spec — `rpg.actor(kind, spec)`

```js
rpg.actor('cultist', {
  team: 'foe',
  name: { ko: '흑일교 무사', en: 'Black Sun Cultist' },
  stats: { hp: 260, poise: 40, radius: 0.45, height: 1.9, scale: 1, mass: 1,
           walk: 1.6, run: 3.4, turn: 420 /* deg/s */, shards: 35, damage: 1 },
  elite: false, boss: false,                 // boss: true -> the bottom boss bar, immovable, never flinches by level
  design: sentinelDesign,                    // a src/char design: the core calls createCharacter(ctx, design)
  // or: create(ctx, world, actor, opts) -> { root, sockets?, update(dtGame, dtReal), dispose(), flash?, impulse?, play?, setClipTime? }
  clips: { idle: 'rpg.foe.cultist.idle', walk: '…', run: '…', flinch: '…', stagger: '…', down: 'game.down',
           getup: 'game.getup', dead: '…', spawn: '…', guard: '…' },   // missing slots fall back to game.* / demo.*
  attacks: { slash: { ...attack def, section 6... }, lunge: {...} },
  roll: null, guard: null,                   // or { cost, distance, duration, travel, invuln: [a, b], actFrom } / { perfect, arc (deg), speed }
  taken: 1, lockable: true,                  // damage-taken multiplier; false = never held by an ultimate lock / skipped by auto lock-on
  spawnTime: 0.6, corpseTime: 2.4, downTime: 0.9, getupTime: 0.7,
  element: 'steel',                          // 'ember' | 'frost' | 'volt' | 'steel': palette of its generic sparks / trails
  controller: (world, actor) => ({ think(world, actor, dt, intent) { ... } }),     // section 5.3
  present: { markers: { name(h, e) {} }, moves: { slash: { swing(h, e) {}, hit(h, e) {} } }, on: { death(h, e) {} } },   // optional choreography, same shape as the fighters' (section 6.5)
  step: null,                                // (world, actor, dt) => void: replaces the humanoid machine entirely (boss);
                                             // it may still call updateAttack / locomotion / slide exported by core/actor.js
  onSpawn(world, actor, opts) {}, onDeath(world, actor, by) {}, onHit(world, actor, e) {}, onPoiseBreak(world, actor, by) {},   // optional hooks
  hurt: null,                                // optional hurt volumes instead of the body cylinder (boss): section 6.3
  budget: 'foe',                             // 'foe' counts toward world.maxFoes; 'boss' / 'prop' do not
});
```

Budgets (CONTRACT + the mode's brief): an ordinary enemy `<= 16k` triangles, `<= 2` draw calls, **no cloth**; the
boss `<= 80k` triangles and `<= 6` draw calls; at most 4 ordinary enemies alive (3 on `low`).
`world.spawn` warns once per kind when `char.stats` exceeds its budget.

### 5.3 Controllers and intents

A controller fills the actor's `intent` once per step; the machine decides what is possible (state, stamina, cooldowns).

```js
controller.think(world, actor, dt, intent)
intent = {
  moveX, moveZ,      // desired move direction in WORLD space, length 0..1 (0 = stand)
  run, sprint,       // gait: walk (default for foes) / run (default for the hero) / sprint (stamina)
  face,              // yaw to face while standing / guarding (NaN = keep; moving turns toward the move direction)
  strafe,            // true: move without turning away from `face` (guard walk, circling foes)
  attack,            // attack id to start this step ('' = none); hero slots: light heavy skill1 skill2 skill3 ult
  guard, roll,       // guard held; roll pressed (rolls along moveX/moveZ, or backward when standing)
  drink, interact,   // hero only
}
```

The intent object is reset before every `think`. A controller may also have `frame(dtReal)`: called once per rendered
frame for the hero (the human controller latches presses there, so nothing is lost during a hit-stop).
Built-in controllers: `core/hero.js` `humanController(ctx)` (reads `ctx.input` + the camera), `core/bot.js`
`botController()`, `core/kinds.js` `meleeController(opts)` — a
reusable approach / circle / telegraphed-attack / back-off AI that foes may configure instead of writing their own:

```js
controller: (world, actor) => meleeController({ attacks: [{ id: 'slash', range: [0, 2.2], weight: 2, cooldown: 1.4 }],
  aggro: 14, keep: 1.8, circle: 0.5, patience: [0.6, 1.6] })
```

---

## 6. Attacks and combat

### 6.1 Attack definition

```js
{
  id: 'slash', name: '…', duration: 1.2,
  clip: 'rpg.foe.cultist.slash',            // or { clip, hit: 0.5 } (clip impact time -> retimed onto the first active frame)
                                             // sampled at the attack clock (animation is locked to the frame data)
  stamina: 0, fp: 0, ult: 0, cooldown: 0,    // costs
  hits: [{
    t: [0.48, 0.58],                         // active window, seconds
    shape: { type: 'arc', r: [0.2, 2.3], angle: [-70, 70], u: [0.3, 1.9] },    // section 6.2
    damage: 70, poise: 35,                   // poise damage (default by level: 14 / 34 / 45 / 45 / 60)
    level: 'heavy',                          // light | heavy | launch | crumple | knockdown -> the victim's reaction
    knock: { f: 4, u: 0 },                   // m/s along the hit direction / up (defaults by level)
    hitstop: 0.1, guard: 30,                 // world freeze on hit; stamina drained from a blocker (default damage * 0.4)
    unblockable: false, chip: 0.15,          // chip = fraction of the damage that goes through a guard
    multi: { interval: 0.12, max: 3 },       // may hit the same victim again
    radial: false,                           // true: knock the victim away from the attacker instead of along its facing
  }],
  motion: [[0, 0], [0.3, 0], [0.5, 1.2]],    // cumulative forward travel keys [t, metres(, height)] or [{ t: [a, b], v }]
  track: { until: 0.4, rate: 240 },          // keeps turning toward its target until `until` s at `rate` deg/s
  armour: [[0.2, 0.5]], invuln: [],          // hyper-armour (no flinch) / invulnerable windows
  projectiles: [{ t: 0.4, ...section 6.4 }],
  markers: [{ t: 0.3, name: 'swing', data: { shake: 0.3, audio: 'swing_heavy' } }],   // -> `marker` events + choreography
  cancel: { from: 0.7 },                     // the actor may act again from here (default: duration)
  rollFrom: 0.6,                             // a roll may interrupt from here (default: min(cancel.from, last active + 0.14))
}
```

`normalizeAttack(def)` (core/attacks.js) fills the defaults; `fromFighterMove(compiledMove, { slot, stamina, shapes, track })` converts a move
of `src/fighters/<id>/moves.js` (hits, motion, armour, invuln, markers, projectiles, cancels, costs) — that is how
the heroes get their whole move set. `core/hero.js` documents the per-move 3D shapes.

### 6.2 Hit shapes (attacker-local `[f, u, s]`, metres, degrees)

| shape | fields | use |
|---|---|---|
| `arc` | `r: [r0, r1]`, `angle: [a0, a1]` (0 = forward, + = toward the right), `u: [u0, u1]` | weapon swings (a 360 sweep is `[-180, 180]`) |
| `box` | `f: [f0, f1]`, `s: [s0, s1]`, `u: [u0, u1]` | thrusts, lunges, beams along the facing |
| `sphere` | `at: [f, u, s]` or `socket: 'handR'`, `r` | slams, fists, a point on a limb (socket: follows the bone) |
| `capsule` | `a`, `b` (each `[f, u, s]` or a socket name), `r` | a limb / a weapon / a beam between two points |
| `ring` | `at: [f, u, s]`, `r: [r0, r1]`, `u: [u0, u1]`, `grow: [dr0, dr1]` (m/s, optional) | expanding shockwaves (jumpable / rollable band) |

A victim is its body cylinder (`radius`, `height` at `pos`), or `spec.hurt` volumes (section 6.3). Arcs / boxes test
the cylinder analytically in the attacker frame; spheres / capsules in world space.
`world.debugShapes(true)` (`#rpgdebug`, `__ED.rpg.debug()`) draws live hit volumes (dim while winding up, red while
active), body cylinders (cyan = invulnerable, yellow = guarding), hurt spheres, projectiles, colliders and triggers.

### 6.3 Hit resolution (in order)

1. **Filter**: same team (friendly fire off), dead, `spawn`, already hit by this hit window (unless `multi`).
2. **Invulnerable** (`roll` i-frames, attack `invuln`, `down` / `getup`): the hit is consumed for this window →
   `dodge` event (`perfect: true` when it was a roll's i-frames).
3. **Guard** (victim in `guard` / `guardhit`, attacker within `spec.guard.arc` = ±80° of its facing, hit not
   `unblockable`): `guardTime < spec.guard.perfect` → **perfect guard**: no damage, no stamina, the attacker takes
   `poise × 2.5` poise damage and is staggered unless it has armour → `perfectGuard`. Otherwise stamina −= `hit.guard`;
   stamina left → `guard` (chip damage, `guardhit`); none left → `guardBreak` (full `stagger`, 60 % damage).
   A fighter move with a `counter` stance (KAEL's bulwark) swallows the hit instead: `counter` event, its follow-up starts.
4. **Hit**: `damage = hit.damage × attacker.mult.damage × (group multiplier from progression) × victim.spec.taken`;
   `poise −= hit.poise`. Reaction: armour window or (poise still > 0 and the kind has `poise > 0`) → none (`armoured`),
   else by `level` (`flinch`, `stagger`, `launched`, crumple → `stagger` long then `down`, `knockdown`). A poise break
   refills poise after the reaction (`poiseBreak` event; a `boss` kind handles it in its own `onPoiseBreak`).
   Poise regenerates after 3 s without poise damage.
5. `hit` event → choreography (`present`), generic feel (sparks, flash, flinch impulse, shake, sound, hit-stop),
   damage number, shards / `death` when hp reaches 0.

`spec.hurt`: `[{ name, socket | at: [f, u, s], r, taken = 1, weak = false }]` spheres that replace the body cylinder
for incoming hits (a colossus: shins, knee weak point); the hit event carries `part`.

Stamina (hero): regenerates `spec.stamina.regen` /s after `spec.stamina.delay` s without spending; rolling, sprinting,
attacking and blocking spend it; at 0 the hero cannot sprint, roll or attack until it has recovered 15 %.

### 6.4 Projectiles

```js
world.shoot(owner, {
  kind: 'ember.wave',             // presentation key (a VFX preset name follows the projectile; else a generic body)
  at: [1.0, 1.1, 0],              // spawn point in the owner frame (or `pos: {x, y, z}` world)
  dir: [1, 0, 0],                 // direction in the owner frame (or `yaw`), `aim: actor` homes the launch at a target
  speed: 11, gravity: 0, lifetime: 0.85, delay: 0,
  radius: 0.5, height: [0, 2.2],  // hit cylinder around the projectile
  ground: false,                  // true: a stationary floor effect (columns, spikes, strikes) armed after `delay`
  pierce: false, hit: { damage, level, poise, knock, hitstop, guard, unblockable },
  data: {},                       // echoed in the events
});
```
Events: `projectileSpawn`, `projectileActive` (armed), `hit` (`kind: 'projectile'`), `projectileExpire`
(`reason: hit | lifetime | wall | world`).

### 6.5 Choreography on RPG actors (`core/present.js` + `core/stage.js`)

Every hero move keeps the VFX, sound and camera accents of its duel choreography: the handlers of
`src/fighters/<id>/present.js` (`moves`, `projectiles`, `markers`, `on`, `ult`) run unchanged against a helper `h`
with the surface of `src/game/present.js` (README of `src/game`, §3.4). Kinds may give their own `spec.present` in
the same shape (`moves[attackId][markerName | start | hit | guard | whiff | end]`, `markers`, `on`).

How it works in 3D — **the stage frame**. The choreography and the VFX presets were authored on the duel's fight line
(fighter at `(x, 0, 0)` facing `±X`, camera on `+Z`). While a handler runs (and in everything it schedules), a *stage
frame* is active: a rigid transform (the actor's position and yaw) between that virtual fight line and the world.

* `h.at / h.pos / h.socket / h.dir` return **stage-space** vectors (the actor stands at the stage origin facing +X,
  `s` = `+Z`); the socket objects `h.self.sockets.*` / `h.self.char.root` are proxies whose `getWorldPosition()`
  answers in stage space while a frame is active.
* every `ctx.vfx` primitive (`burst emitter trail ribbon slash ring pillar beam bolt spikes debris decal flare light
  distort speedlines afterimage play schedule`) is wrapped while the mode runs: positions, directions, plane normals
  and function-valued point sources are mapped stage → world on the way in; proxies are unwrapped; scheduled
  callbacks restore the frame they were scheduled in. Outside a frame the wrappers pass straight through.
* event payloads handed to handlers carry duel-shaped fields (`e.x`, `e.y`, `e.facing`, `e.attacker` / `e.defender`
  as indices 0 / 1, `e.level`, `e.hitstop`, `e.move`, `e.kind`, `e.projectile`, `e.data` …) in stage space, plus the
  RPG payload as `e.rpg`.
* `h.cam.play(shots)` runs the shot list of `src/cam` in the stage frame and the third-person camera maps the result
  into the world (section 10), so authored ultimates keep their camera.
* `'foe'` = the actor's current target (`h.foe` is a view of it; with no target, a point 2 m in front).

Enemy / boss code that wants oriented presets uses the same thing directly:

```js
import { withStage } from '../core/stage.js';
withStage(actor, () => ctx.vfx.play('combat.dust.dash', { pos: [0, 0, 0], facing: 1 }, { k: 1 }));   // stage space = actor frame
world.fxAt(actor, 'ember.eruption', [3, 0, 0], { k: 1.2 });        // shorthand: preset at [f, u, s] of the actor
```

Ultimates: against a human-sized, lockable enemy the full cinematic lock runs (the victim is held `cinematic.distance`
in front, ticks and the finish deal the move's damage, the fighter's `ult.shots` / `ult.at` play). Against a `boss`
kind (or any kind with `lockable: false`) the **ultimate strike** runs instead: the super-freeze, the opener's VFX
and a short camera accent, then the ultimate's total damage as one burst — the boss is never held or moved.

Handlers that cannot work in 3D are listed in section 14.

---

## 7. Events — `world.on(name, fn)` / `rpg.on(name, fn)`

Payloads are plain objects; `attacker` / `victim` / `actor` are actors.

| event | payload | when |
|---|---|---|
| `spawn` / `despawn` | `{ actor }` | actor enters / leaves the world |
| `state` | `{ actor, from, to }` | state change |
| `attackStart` / `attackEnd` | `{ actor, attack, id, reason }` | `reason`: `complete \| cancel \| interrupted \| death` |
| `marker` | `{ actor, attack, id, name, data, t }` | attack timeline marker |
| `hit` | `{ attacker, victim, attack, hit, id, kind: 'strike' \| 'projectile' \| 'effect', damage, level, reaction, armoured, part, pos: {x,y,z}, dirX, dirZ, hitstop, killed, front, crit }` | a hit dealt damage |
| `tick` | same shape (`kind: 'tick'`, `final`, `marker`, `strike`) | damage of an ultimate lock tick / finish, or the whole ultimate strike on a boss (HUD: damage numbers) |
| `counter` | `{ actor, attacker, attack, id, move }` | a counter stance swallowed a hit |
| `teleport` | `{ actor, fromX, fromZ }` | an attack teleported its user |
| `guard` / `perfectGuard` / `guardBreak` | same shape as `hit` (`blocked: true`) | blocked hits |
| `dodge` | `{ actor, attacker, perfect }` | a hit passed through i-frames |
| `roll` | `{ actor, dirX, dirZ }` | roll started |
| `stagger` / `poiseBreak` | `{ actor, kind, by }` | reaction started / poise broken |
| `death` | `{ actor, by, shards }` | hp reached 0 |
| `heroDeath` / `heroRespawn` | `{ hero, x, z, dropped }` | the hero died / woke at the altar |
| `heroRest` / `heroLeave` | `{ hero }` | sat down at / stood up from the altar |
| `drink` | `{ actor, heal, left }` | chalice used |
| `shards` | `{ amount, total, reason: 'kill' \| 'reclaim' \| 'lost' \| 'spend' \| 'boss' }` | currency changed |
| `levelUp` | `{ stat, level }` | a stat was raised |
| `encounterStart` / `encounterEnd` | `{ id, def, cleared }` | section 9 |
| `bossIntro` / `bossPhase` / `bossDefeated` | `{ boss, phase }` | emitted by the boss module (the stand-in emits them too) |
| `cycle` | `{ cycle }` | a new cycle started |
| `lock` | `{ target }` | lock-on changed (null = released) |
| `prompt` | `{ prompt \| null }` | an interact prompt appeared / went |
| `step`, `land` | `{ actor, foot }` | footsteps (clip `step` events), landings |
| `projectileSpawn` / `projectileActive` / `projectileExpire` | `{ projectile, owner, kind, pos, reason }` | section 6.4 |
| `mode` | `{ mode, prev }` | `off \| play \| pause \| dead \| rest \| cine \| victory` |
| `cine` | `{ on }` | the camera entered / left a cinematic |
| `announce` | `{ text, sub, style, actor }` | a name card request (ultimate name; boss teams may emit their own) |
| `gate` / `interact` | `{ hero }` / `{ trigger, actor }` | the gate was passed / an interact trigger fired |

---

## 8. World hooks (src/rpg/world)

The duel arena (`src/env`, read-only) is a 250° ring open toward the old fixed camera (+Z). `rpg.world(factory)`
adds the rest: the missing arc, the **Starlit Altar**, the **mist gate**, pickups, boss staging.

```js
rpg.world((ctx, world) => {
  const group = new THREE.Group(); ctx.scene.add(group);
  world.addCollider({ type: 'circle', x: -11.5, z: 6, r: 1.1 });               // altar plinth
  world.addTrigger({ x: -11.5, z: 6, r: 2.2, prompt: { ko: '별빛 제단에서 쉬기', en: 'Rest at the Starlit Altar' },
    interact: () => world.flow.rest() });
  return { altar: { x: -11.5, z: 6, yaw: 0.6 }, heroSpawn: { x: -10, z: 5, yaw: -0.4 }, gate: { x: -4, z: 0, yaw: 0, r: 2.5 },
    update(dtGame, dtReal) {}, dispose() { group.removeFromParent(); /* dispose geometries */ } };
});
```

Without a world module the core places a stand-in rest stone at `(-11, 0, 6.5)` and two gate posts at `(-5, 0, 2.4)`
(`core/standin.js`), so the loop is playable; with one, the stand-in props are not built. `world.flow.places` holds
the resolved `{ altar, gate, heroSpawn }`. The flow itself adds the rest trigger (r 2.4 around `altar`, prompt
"정심석에서 운기조식") and the gate trigger (r `gate.r`): a world module only supplies positions and dressing.
The dropped-`shards` marker (one small mesh, `rpg-dropped-shards`) and its walk-over reclaim trigger are the flow's
(`world.flow.dropped`); a world module may add its own visual on `heroDeath` / `shards`.

---

## 9. The expedition flow (`core/flow.js`) and encounters

```
wake at the altar ──> gate ──> encounter #1 ──> encounter #2 ──> boss ──> victory ──> new cycle (enemies stronger)
        ^                                 hero dies: shards stay where it fell, respawn at the altar, unfinished
        └──────────────────────────────── encounters respawn, the dropped shards can be reclaimed once
```

```js
rpg.encounter({
  id: 'cultists', order: 10,                  // played in ascending order; boss encounters last
  title: { ko: '흑일교 무사들', en: 'BLACK SUN CULTISTS' },
  boss: false,
  spawns: [{ kind: 'cultist', x: 4, z: -3, yaw?, delay?: 0.4, opts?: {} }],
  heroAt: { x: -2, z: 0, yaw: 0 },            // optional: where `#rpgenc=<id>` puts the hero
  trigger: { x: 0, z: 0, r: 6 },              // optional: starts when the hero enters (default: when the previous one ended / the gate was passed)
  onStart(world, enc) {}, onClear(world, enc) {}, update(world, enc, dt) {},
});
```

| `world.flow` member | meaning |
|---|---|
| `state` | `altar \| explore \| encounter \| boss \| victory \| dead` |
| `encounter` | the running encounter `{ def, actors, cleared }` or null; `index`, `cycle` |
| `start(id?)` | start the next (or the named) encounter now |
| `rest()` / `leave()` | sit at the altar (refill HP / FP / chalice, respawn unfinished encounters, `heroRest`) / stand up |
| `respawn()` | after death (also called automatically 3.2 s after `heroDeath`) |
| `dropped` | `{ x, z, amount }` or null: shards left where the hero fell |
| `nextCycle()` | after the victory banner: cycle + 1 (foe hp × 1.35, damage × 1.2 per cycle), everything respawns |

Scaling: `actor.level = flow.cycle`; `mult.hp = 1.35^cycle`, `mult.damage = 1.2^cycle` (kinds may read `opts.level`).

---

## 10. Camera (`src/rpg/camera.js`) — `world.camera` / `ctx.rpg.camera`

The mode switches `ctx.cam` to `'free'` and writes `ctx.camera` itself at `ctx.ORDER.CAM + 1`; `ctx.cam.shake / kick`
keep working (their samples are added), and cinematics still go through `ctx.cam.play` (stage frame → world).

| member | meaning |
|---|---|
| `yaw`, `pitch`, `dist` | orbit state (rad, rad, m). `look(dyaw, dpitch)` adds free-look input |
| `params` | live tuning: `{ dist: 4.4, height: 1.5, shoulder: 0.4, fov: 50, pitch: 0.22, pitchMin: -0.55, pitchMax: 1.05, lockPitch: 0.4, lockShoulder: 0.62, lockYaw: 0.09, lag: 0.085, lockLag: 0.16, recover: 0.2, minBoom: 0.7, floor: 0.25, autoFollow: 0.9, lockRange: 16, lockBreak: 22 }` (m, rad, s; fov deg, widened on portrait viewports) |
| `lock(target \| null)`, `toggleLock()`, `target`, `switch(dir)` | lock-on (the toggle picks the best target in front of the camera within 16 m; `switch(±1)` = next target to the left / right; auto-release when the target dies or is farther than 22 m). Locked: the camera looks down over the hero's shoulder, the hero left of the target |
| `setFraming({ point?: fn(out) \| socket, back = 0, up = 0, pitch = 0, fov = 0 })` / `setFraming(null)` | boss framing hook: aim at a body point, pull back / raise / tilt up while that target is locked. A `boss` kind gets a default from its `scale` |
| `cine(shots, { anchor: actor, target?: actor, side?: 1 \| -1, blendOut = 0.6, onDone, hud = true })` | play `src/cam` shots around an actor in its stage frame, then blend back to the follow camera |
| `worldShot(fn, { dur, blendOut, clock: 'game' \| 'real', onDone })` | free cinematic: `fn(t, out)` writes `out.pos / out.look` (Vector3) and `out.fov` in world space (boss intro, death) |
| `endCine(completed, blend?)`, `cinematic` | end the running cinematic and blend back; is one running |
| `zoom(factor, dur)`, `focusPoint(target, out)`, `project(worldPos, out)` | temporary push-in; the lock aim point of a target; world → stage CSS pixels `{ x, y, visible }` |
| `focus` | world point the camera looks at (also fed to `ctx.shadows` / `env.setFocus`) |
| `snap()` | jump behind the hero (respawn, teleport) |
| `forward(out)`, `yawOf()` | camera-relative basis for input |

Collision: the boom is shortened (never lengthened through a wall) against the arena wall cylinder and every
`blocksCamera` collider, with a 0.18 s recover lag; the camera never drops below 0.25 m.

---

## 11. HUD data — `ctx.rpg.snapshot()` (also `window.__ED.rpg.snapshot()`)

The HUD module is called every frame with the same reused object (**read it, do not keep references**):

```js
rpg.ui((ctx, api) => ({ start(snap) {}, stop() {}, update(snap, dtReal) {} }));

snap = {
  mode,                       // off | play | pause | dead | rest | cine | victory
  time, cycle,
  hero: { id, name, nameEn, element, level, hp, hpMax, fp, fpMax, stamina, staminaMax, staminaLocked, ult, ultMax, ultReady,
          chalice, chaliceMax, shards, state, x, y, z, yaw, lockId,
          skills: [{ slot, id, name, nameEn, icon, cost, cd /* 0..1 left */, ready }],   // skill1..3
          ultSkill: { id, name, nameEn, icon } },
  target: null | { id, kind, name, nameEn, hp, hpMax, poise, poiseMax, boss, elite, sx, sy, visible },   // locked target; sx / sy = reticle in CSS px of the stage
  foes: [{ id, kind, hp, hpMax, boss, elite, locked, sx, sy, visible, dist }],     // live hostile actors (length = foeCount)
  foeCount,
  boss: null | { id, name, nameEn, hp, hpMax, phase, poise, poiseMax },
  encounter: null | { id, title, titleEn, index, total, remaining, boss },
  flow,                       // altar | explore | encounter | boss | victory | dead
  prompt: null | { ko, en, key },                 // interact prompt
  dropped: null | { x, z, amount, sx, sy, visible },
  levelUp: null | { level, cost, canAfford, stats: { vigor, endurance, might, arcana }, derive: {...} },   // while resting
}
```

One-shot things are events (`api.on`): `hit` (damage numbers: `e.damage`, `e.pos`, `e.crit`; `api.project(pos, out)`
gives stage CSS pixels), `encounterStart` (title card), `heroDeath` (death banner), `bossDefeated`, `shards`,
`perfectGuard`, `levelUp`, `mode`.

`api` (= `ctx.rpg`): `on(event, fn)`, `snapshot()`, `project(worldPos, out)`, and the actions the HUD calls:
`pause()`, `resume()`, `toTitle()`, `levelUp(stat)`, `leaveAltar()`, `nextCycle()`, `respawn()`.
Touch controls feed `ctx.input` (`setVirtual(action, down)`, `setVirtualMove(x, y)`, `addLook(dx, dy)`), see below.

### Input (additive, `src/input`)

`input.setMode('rpg')` (set by the mode) remaps: `WASD` move, **arrows look**, `Q` / `Tab` lock, `R` chalice, `E`
interact, mouse: left button = light (on press), right button = look drag / heavy on a short click, any drag looks,
wheel = switch target (only presses that land on the stage canvas count, never on UI controls). Gamepad: left stick
move, right stick look, R3 lock, d-pad ↑ chalice, ↓ / L3 interact, ← → switch target, the duel's face buttons.
New actions (appended to `ACTIONS`, so the duel's bit order is unchanged): `lock chalice interact lookL lookR lookU
lookD lockL lockR`.

| call | meaning |
|---|---|
| `input.moveVec(player, out)` | analogue move vector `{ x, y }` (x right, y forward), length ≤ 1: keys, left stick, `setVirtualMove` |
| `input.setVirtualMove(x, y, player)` | touch stick |
| `input.look(player, out)` | look delta accumulated since the last frame `{ x, y }` in radians (yaw right +, pitch up +): mouse drag, right stick, arrow keys, `addLook` |
| `input.addLook(dx, dy, player)` | touch drag zone / tests (radians) |

Hero controls: `light` (chain light1-3), `heavy` (sprinting → the f+heavy move, right after a roll → the d+heavy
move), `skill1..3`, `ult`, `guard` (hold), `dodge` (tap = roll, hold = sprint), `lock`, `chalice`, `interact`, `pause`.

---

## 12. Progression (`src/rpg/progress.js`; default: `core/progress.js`)

```js
export default {
  STATS: ['vigor', 'endurance', 'might', 'arcana'],
  load(heroId) -> state,        // { level, stats: { vigor, endurance, might, arcana }, shards, dropped, cycle } (localStorage in try/catch)
  save(heroId, state),
  derive(state, base) -> { hpMax, staminaMax, fpMax, phys, arcane, chaliceMax, chaliceHeal },
        // base = { hp, fp, stamina } of the hero (fighter stats); phys multiplies normal moves, arcane skills + ultimate
  cost(level) -> shards,        // price of the next level
  levelUp(state, stat) -> bool, // spend + raise (the core calls save and re-derives)
  rank(level) -> string,        // optional: the 경지 title of a level
};
```
The core keeps `world.hero.prog` (the state) and `world.hero.derived`; it calls `save` on rest, level-up, death,
reclaim and boss kill. Default curve: cost `90 × 1.14^(level-1)`; vigor +6 % HP, endurance +5 % stamina, might +5 %
physical, arcana +5 % arcane and +4 % FP per point.

---

## 13. The mode object and the test API — `ctx.rpg` / `window.__ED.rpg`

| member | meaning |
|---|---|
| `active`, `mode`, `world`, `camera`, `hero` | state |
| `start(hero = 'kael', { bot, sandbox, encounter, seed })` | enter the mode (disposes the duel session, `ctx.cam.setMode('free')`, `ui.show('none')`, `input.setMode('rpg')`, `env.setMood(null)`, `vfx.clear()`, prewarm hooks + `renderer.compile`). `sandbox`: no flow, no dressing, hero at the centre and one `dummy` |
| `stop()` | leave: everything created is disposed, camera / HUD / input mode / mood restored (the caller shows the title) |
| `pause()`, `resume()`, `toTitle()` | pause menu actions (`pause` action / Esc toggles; `toTitle` = `stop()` + the duel's title) |
| `levelUp(stat)`, `leaveAltar()`, `rest()`, `nextCycle()`, `respawn()` | HUD actions (section 11) |
| `heroes`, `registry` | hero ids available; the registry |
| `snapshot()` | section 11 (the test API returns a JSON copy) |
| `on(event, fn)`, `project(pos, out)` | events, world → stage pixels |
| **test API only** | |
| `state()` | compact JSON: mode, flow, hero `{ x, z, yaw, state, hp, stamina, fp, ult, attack }`, foes `[{ id, kind, x, z, hp, state }]`, camera |
| `spawn(kind, x, z, opts)` | spawn now (returns the id) |
| `tp(x, z, yaw?)` | teleport the hero (camera snaps) |
| `give({ hp, fp, ult, stamina, shards, chalice })` | set meters (`true` = full) |
| `god(on)`, `debug(on)` | the hero takes no damage; the combat-volume overlay |
| `bot(on)` | swap the hero controller for the bot |
| `press(action, sec = 0.05)`, `move(x, y, sec)`, `look(dyaw, dpitch)` | scripted input (virtual) |
| `act(slot)` | start a hero move now, costs ignored (`light1 … ult`) |
| `lock(id \| true \| null)`, `clear()` | lock a target / remove every foe |
| `step(n = 1)` | advance n fixed frames without rendering |
| `kill(id)`, `hurt(amount)` | kill a foe / damage the hero |
| `flow(cmd)` | `'rest' 'leave' 'respawn' 'encounter:<id>' 'next' 'cycle'` |
| `checks()` | invariants for the soak test: NaN scan, stuck-state timers, counts (actors, scene children, geometries, textures, programs) |
| `prof()` | JS ms per group (`#prof`), draw calls, triangles |

---

## 14. Limits and known gaps

Movement and combat
* **Turn-to-move, no strafe clips.** The hero always runs facing its direction of travel (also while locked: the lock
  aims the camera and the attacks). Only the guard walk strafes: it reuses the fighter's forward / backward stance
  walk with the guard pose layered on the upper body, so sideways guard steps slide a little.
* **Stagger** uses the fighters' own `hitLight` / `hitHeavy` clips; knockdown / getup the generic `game.*` clips.
* Heroes have no poise (every clean hit staggers them unless a move's own armour window is active); heroes cannot be
  locked by an enemy's cinematic.
* The duel's `requires` field of a move (ISKA's afterimage `maxDistance`) is not enforced; `teleport: 'behind'`
  with no target steps forward instead.
* Projectile-vs-projectile clashes and juggle points of the duel rules do not exist here.

Choreography in 3D (section 6.5) — what differs from the duel
* Handlers that guard their camera with `ctx.cam.mode === 'fight'` (KAEL Fault Eruption ground skim, the bulwark
  crash zoom, ISKA's skill shots) do not run: the director is in `'free'` mode. `h.cam.play` is honoured only while an
  ultimate is being presented; marker `cam` hints are ignored.
* `h.announce`, the ULT cut-in card and combo counters of the duel HUD are not shown: the adapter emits `announce`
  (the RPG HUD draws its own card). `ctx.game.session` is null, so the fighters' result-screen bookkeeping is skipped.
* Particle *definitions* that carry a horizontal `vel` / `gravity` vector, and `side` hints baked into a definition,
  keep world axes (only per-spawn values are rotated by the stage frame). None of the shipped fighter effects
  depends on one.
* During a mirrored cinematic (`camera.cine` picked the hero's left side because the right is against the wall) the
  choreography's "toward the camera" offsets (`s > 0`) point away from the lens.
* ISKA's ultimate flips `char.setFacing(-1)` while she circles the crystal (as in the duel): the model is mirrored
  for those beats; the adapter restores `setFacing(1)` when the lock ends.
* Against a `boss` kind the ultimate is the **strike**: super-freeze + opener as authored, then one burst with the
  lock's total damage and the element's climax preset scaled to the target. The fighter's lock storyboard
  (`ult.at`, `ult.shots`, `ult.tick`) is not played there.

World / budgets
* `env.setFocus(x)` (read-only API of `src/env`) only follows X; the shadow window follows the casters through
  `ctx.shadows`, but the key-light mask of the env stays centred on the old fight line (z = 0).
* `world.spawn` builds the character at spawn time (geometry build = a CPU hitch of a few ms for the husk, more for
  heavy designs). Kinds with expensive designs should be warmed in `rpg.prewarm` (build one, dispose it) or kept small.
* The stand-in boss is the husk scaled 3.6x with three slow attacks: it exists so the loop, the boss bar, boss
  framing and the ultimate strike can be tested before `src/rpg/boss` lands.
