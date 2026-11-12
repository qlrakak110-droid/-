# `src/game/logic/` — ECLIPSE DUEL rules engine

Pure, deterministic JavaScript (ES modules, no three.js, no DOM). It runs the whole fight — inputs, moves, hits,
guard, dodge, juggles, projectiles, meters, the ultimate's super-freeze and cinematic lock, rounds — and tells the
presentation what happened through an event stream and plain fighter state. It runs in Node for tests and is bundled
into the browser build unchanged.

```
index.js          public API (import everything from here)
match.js          createMatch: round flow, sub-stepping, super-freeze, push-boxes, public match API
fighter.js        fighter state machine: neutral, buffered actions, moves (timeline, motion, cancels), stun, air
combat.js         hurtboxes, strike collection, hit resolution (guard, armour, counter stance, combos, KO)
cinematic.js      cinematic lock (scheduled ticks, finish, release)
projectiles.js    spawn / travel / clash / hit collection
meters.js         HP, FP, ULT, guard gauge
input.js          held -> presses, input buffer, double taps
moves.js          motion sampling, timeline windows, boxes (EPS)
defs.js           validateFighterDef (path-qualified messages), compilation into the runtime form
framedata.js      deriveFrameData / fighterFrameData / frameDataTable
controllers.js    human, scripted, idle controllers (+ actionsProvider adapter)
ai.js             AI controller (easy / normal / hard / nightmare)
sample-fighter.js complete, commented sample definition — the template for real fighters
constants.js      DEFAULT_RULES, DEFAULT_STATS, DEFAULT_MOVEMENT, HIT_DEFAULTS, enums
rng.js            seeded streams (makeRng from core/math.js)
test/             run.mjs (runner), unit / determinism tests, soak, frame-data CLI
```

---

## 1. Quick start

```js
import { createMatch, createAIController, createHumanController, actionsProvider, sampleFighter } from './game/logic/index.js';

// human (P1, reads ctx.input) vs AI (P2)
const match = createMatch({
  fighters: [kaelDef, iskaDef],                       // author-format definitions (validated; throws on errors)
  controllers: [
    createHumanController(actionsProvider((action, player) => ctx.input.held(action, player))),
    createAIController({ difficulty: 'hard' }),
  ],
  rules: { roundTime: 99 },                           // partial rules, merged over DEFAULT_RULES
  rng: 20261112,                                      // seed (or ctx.rng: one value is drawn to seed the match)
});

// step with real time x pause (x your own slow-motion factor) - never with a dt frozen by ctx.time.hitstop (§3)
ctx.onUpdate((dtGame, dtReal) => match.step(dtReal * ctx.time.baseScale), ctx.ORDER.GAME);
match.on('hit', (e) => { if (!e.blocked) ctx.vfx.play('hit.slash', { pos: [e.x, e.y, 0] }); });
match.on('marker', (e) => choreography[e.fighter][e.name]?.(e));
```

```js
// a deterministic demo / test: scripted inputs, no intro
import { createMatch, createScriptedController, sampleFighter } from './index.js';
const m = createMatch({
  fighters: [sampleFighter, sampleFighter],
  controllers: [createScriptedController([{ t: 0, light: true }, { t: 0.15, light: true }, { t: 0.42, light: true }]), null],
  rules: { introTime: 0 },
});
for (let i = 0; i < 120; i++) m.step(1 / 60);
console.log(m.fighters[1].hp, m.snapshot());
```

```sh
node src/game/logic/test/run.mjs            # unit + determinism tests, then the 300-match AI soak with statistics
node src/game/logic/test/run.mjs --quick    # tests only
node src/game/logic/test/framedata.mjs src/fighters/kael/moves.js   # frame-data table of any definition module
```

---

## 2. Space, units, conventions

* Metres, seconds, HP / meter points. Y up. Fighters live on the X axis (`z = 0`); the floor is `y = 0`.
* Arena `|x| <= rules.arenaHalfWidth` (9) — the *body* stays inside: `|x| <= 9 - pushWidth`.
* P1 (index 0) starts at `x = -rules.startX` facing `+1`, P2 at `+startX` facing `-1`.
* **Fighter-local frame**: `f` = metres forward along the facing, `u` = metres above the floor.
  World x = `x + f * facing`. Every box, offset and motion in a definition uses this frame, so P2 mirrors for free.
* `facing` is `+1 | -1`. In neutral states (idle, walk, guard) a fighter turns toward the opponent once the opponent
  has been on the other side for `rules.turnDelay` (0.05 s). Facing is **locked during a move**, but every move start
  (cancels and counter follow-ups included) first turns toward the opponent.
* Times inside a move are seconds from the move start; comparisons use a tolerance `EPS = 1e-6` so a 0.1 s startup is
  active on exactly the 6th 60 fps step.

---

## 3. Time, stepping and hit-stop

`match.step(dt)` advances the match by `dt` seconds:

* Controllers are polled **once per call**; the engine derives presses from held buttons.
* `dt` is clamped to `rules.maxStep` (0.1 s) and split into `ceil(dt / rules.maxSubstep)` equal substeps
  (`maxSubstep` 1/60). Move timing does not depend on dt: the same inputs at dt 1/144, 1/60 or 1/30 produce the same
  hits and damage, shifted by at most one step of input polling (tested).
* Events raised during the call are **queued and dispatched when it returns** (listeners never see a half-resolved
  substep, and a throwing listener cannot corrupt the simulation; the first error is re-thrown after dispatch).

**Hit-stop is part of the rules.** On a strike, attacker and victim freeze for the hit's `hitstop`; on a projectile hit
only the victim (and the projectile) freeze. A frozen fighter's move clock, stun timer, motion and input-buffer ageing
stop; everything else (the other fighter if not frozen, projectiles, the round clock, cooldowns, regen) keeps running.
`fighter.hitstop` is the remaining freeze (s) and `fighter.hitstopShake` is true for the victim side.

> **Presentation:** step the match with *real* time (times pause / slow-motion scale), **not** with `ctx.time.dtGame`
> while also calling `ctx.time.hitstop()` — that would freeze the rules twice. Freeze a character's animation while
> `fighter.hitstop > 0` and shake it while `hitstopShake`. A global `ctx.time.hitstop(e.hitstop)` for VFX on `hit`
> events is fine as long as the match itself is stepped with `dtReal`.

Super-freeze and cinematic lock pause the round clock; hit-stop does not.

**Determinism.** No `Math.random`, no wall clock. The engine never rolls dice; AI controllers draw from their own
streams forked from the match seed (`createMatch({ rng })`). Same definitions + rules + seed + inputs + dt sequence =
the same event log, bit for bit (tested by hashing the log, also with two matches stepped interleaved).

---

## 4. Match API

`createMatch({ fighters: [defA, defB], controllers: [c0, c1], rules, rng })` → `match`

| member | meaning |
|---|---|
| `step(dt)` | advance (see §3); returns the match |
| `on(name, fn)` / `off(name, fn)` | subscribe to an event (`fn(payload)`); `on('*', fn(name, payload))` for everything. `on` returns an unsubscribe function. `'moveEvent'` is an alias of `'marker'` (CONTRACT name) |
| `fighters[0..1]` | live fighter state (§5) — read every frame, do not write |
| `projectiles` | live projectiles: `{id, owner, kind, move, x, y, vx, vy, facing, age, delay, life, active, hits, durability, hitstop, data}` |
| `phase` | `'intro' \| 'fight' \| 'ko' \| 'timeup' \| 'outro' \| 'end'` |
| `phaseTime` | seconds in the current phase (time since `fightStart` during `'fight'`) |
| `round` | current round number (1-based) |
| `clock` | round clock, seconds left (starts at `rules.roundTime`) |
| `roundWinner`, `roundReason` | set when a round is decided: index or `-1` (draw); `'ko' \| 'doubleKo' \| 'time'` |
| `winner` | match winner once `phase === 'end'` (index or `-1` = drawn match), else `null` |
| `freeze` | active super-freeze `{owner, move, remaining, duration, userAnimates}` or `null` |
| `cinematic` | active lock `{attacker, defender, move, t, duration, scale, damage, ...}` or `null` |
| `time` | match time (s) since creation / reset |
| `rules`, `defs` | merged rules; compiled definitions (`defs[i].moves[id]`, `.commands`, `.stats`, `.warnings`) |
| `snapshot()` | JSON-safe picture of everything (bug reports, debugging) |
| `reset()` | restart the match at round 1 (rounds and ULT cleared) |
| `restartRound()` | restart the current round (HP/FP/guard/positions reset, ULT and round wins kept) — training mode |
| `setController(i, c)` | swap a controller (calls `c.attach({match, index, rng})` when present) |
| `setMeter(i, kind, v)` | set `'hp' \| 'fp' \| 'ult' \| 'guard'` directly (training mode, tests) |
| `place(i, x, facing?)` | teleport a fighter (training mode, tests) |
| `slots(i)` | HUD helper: per command key `{key, move, name, group, fpCost, ultCost, cooldown, cd: 0..1, ready}` |
| `canUse(i, moveId)` | why that move could not start now (`null` when it could): `'phase' 'fp' 'ult' 'cooldown' 'freeze' 'distance' 'airborne' 'hp'` |

---

## 5. Fighter state (`match.fighters[i]`)

| field | meaning |
|---|---|
| `index`, `id`, `name`, `def` | 0 / 1, definition id, display name, compiled definition |
| `x`, `y`, `vx`, `vy` | position (m) and velocity (m/s); `vx` is the pushback slide on the ground |
| `facing` | `+1 \| -1` |
| `airborne` | `y > 0.01` |
| `hp / hpMax`, `fp / fpMax`, `ult / ultMax`, `guard / guardMax` | meters |
| `state`, `stateTime` | state (§6) and seconds in it |
| `timer` | remaining time of timed states (hitstun, blockstun, guardbreak, knockdown, getup, recovery) |
| `stunKind` | in `hitstun`: `'light'` flinch, `'heavy'` stagger, `'crumple'` |
| `walkDir` | in `walk`: `+1` forward, `-1` back |
| `move`, `moveData`, `moveTime`, `moveSerial` | current move id, compiled move (`duration`, `hits`, ...), seconds into it, a counter that increments per move start |
| `moveConnected`, `moveHit` | the current move touched the opponent (hit or block) / landed a clean hit |
| `hitstop`, `hitstopShake` | remaining hit-stop (s); true on the victim side |
| `combo` | the combo this fighter is **dealing**: `{hits, damage, active}` (kept after it ends for the HUD) |
| `recv` | the combo this fighter is **receiving**: `{active, hits, damage, juggle, time, scale, wallBounces, attacker}` |
| `cooldowns` | `{cooldownKey: seconds left}` |
| `dodgeCooldown` | seconds before the next neutral dodge |
| `rounds` | rounds won |
| `result` | after a round: `'win' \| 'lose' \| 'draw'`, else `null` |
| `invulnerable`, `armoured` | presentation flags, recomputed every substep |
| `hard`, `koFall` | airborne and not juggleable (hard knockdown flight) / falling KO'd |

---

## 6. States

```
                 roundStart                     fightStart
   (any) ───────────────────────► intro ───────────────────────► idle
                                                                  │ ▲
       ┌─────────────── stick / guard held ───────────────────────┘ │
       ▼                                                            │ (timers end -> toNeutral, buffered
   idle ◄──► walk ◄──► guard ──hit (front)──► blockstun ───────────►│  presses come out on the first frame)
     │                    └──── empty gauge ──► guardbreak ────────►│
     ├─ press ──► attack ──(cancel window + press)──► attack         │
     │              │  └── complete ───────────────────────────────►│
     │              └── counter window struck ──► attack (follow-up) │
     ├─ dodge / double tap ──► dash | backstep | dodge | roll ──────►│
     │                                                               │
   (hit) ──► hitstun (light / heavy / crumple) ───────────────────► │
         │         └── crumple ends ──► knockdown                    │
         ├─► launched ──(air hits, juggle points)── land ──► knockdown ──► getup (invuln) ──┘
         │        └── dodge buffered on landing (not hard) ──► getup (tech roll) ──────────┘
         ├─► locked (cinematic victim) ──► launched (finish) ...
         └─► launched (koFall) ──► ko
   attacker after a cinematic ──► recovery (invulnerable) ──► idle
   round over: idle/walk/guard ──► victory | defeat  (a fighter still busy switches when it gets back to neutral)
```

Invulnerable: `knockdown`, `getup`, `roll`, `locked`, `ko`, the dodge's `invuln` window, the backstep's `invuln`
window (strikes only), `recovery` after a cinematic, move `invuln` windows, the super-freeze owner, everyone during a
cinematic, airborne victims that are `hard` (knockdown flight) or out of juggle points, everyone outside `'fight'`.

---

## 7. Inputs, buffer, commands, cancels

Controllers report **held** state: `{ move: -1|0|1 (world X), up, down, light, heavy, skill1, skill2, skill3, ult, guard, dodge }`.

* **Presses** are rising edges. Each press is buffered with the stick at that moment and stays usable for
  `rules.inputBuffer` (0.2 s) of the fighter's own clock — the buffer does **not** age during that fighter's hit-stop,
  so a cancel pressed during hit-stop still comes out. It does age during a super-freeze or cinematic.
* **Priority** when several presses are buffered: `ult > skill1 > skill2 > skill3 > heavy > light`, then `dodge`.
  A press that cannot start (no FP, cooldown, requirement) stays buffered and emits `moveDenied` once.
* **Direction** is relative to facing: `fwd = move * facing`. The stick at press time is used, or the stick now if it
  was neutral then.
* **Command map** (`def.commands`): `[d+|u+|f+|b+]light|heavy|skill1|skill2|skill3|ult` → move id. A press resolves
  `d+X`, then `u+X`, `f+X`, `b+X`, then plain `X`; a missing slot is simply unavailable (the press is dropped).
* **Movement**: dodge alone → `dodge`; dodge + forward or double-tap forward (within `rules.doubleTapWindow`) →
  `dash`; dodge + back or double-tap back → `backstep`. A forward dash with the back within 1.1 m of a wall and the
  opponent in your face becomes a **`roll`** that passes through (the corner escape). Dash / dodge accept attacks from
  their `cancelFrom` time.
* **Guard** is held: in neutral, holding guard enters `guard` (no walking). Attack and dodge presses override it.
* **Cancels**: during a move, open cancel windows are checked every substep against the buffered presses:
  1. *Routes* — a window with `on: 'light'` (and optional `dir`) sends that button to its single `into` move
     (`light1 → light2 → light3` chains). Routes with a matching `dir` win over routes without.
  2. *General cancels* — the press is resolved through the command map; the resulting move may start if a window lists
     it (`into: ['launcher']`) or its group (`'@normal' '@skill' '@ult' '@any'`).
  3. `'@dodge'` / `'@dash'` windows let dodge (+ direction) cancel the move.
  `onHit: true` windows need a clean hit by this move, `onContact: true` a hit or a block. Cancels pay the target's
  costs like any start.

---

## 8. Fighter definition

Plain data (JSON-compatible). Validate with `validateFighterDef(def)`; `createMatch` throws with every error listed.
Units: seconds, metres, m/s, HP. `sample-fighter.js` is the annotated template.

### 8.1 Top level

| field | type | default | meaning |
|---|---|---|---|
| `id` | string | required | `[a-z0-9_-]` |
| `name` | string | id | display name (Korean first is fine) |
| `title` | string | `''` | subtitle |
| `stats` | object | §8.2 | body and meters |
| `movement` | object | §8.3 | dash / backstep / dodge / roll tuning |
| `commands` | object | required | command key → move id (§7). `null` value = explicitly unavailable |
| `moves` | object | required | move id (`[a-z0-9_.-]`) → move (§9) |
| `ai` | object | `{aggression: 0.5, zoning: 0.5}` | AI personality: `aggression` 0..1 (rush vs patient), `zoning` 0..1 (projectile appetite), `preferredRange` m |
| `meta` | any | — | free data for presentation (ignored by the rules) |

### 8.2 `stats`

| field | default | unit | meaning |
|---|---|---|---|
| `hp` | 1000 | HP | max HP (reset every round) |
| `fpMax` | 100 | FP | focus max (round start: `rules.meters.fpStart`) |
| `ultMax` | 100 | ULT | ultimate gauge max |
| `guardMax` | 100 | pts | guard gauge |
| `walkSpeed` | 2.5 | m/s | forward walk |
| `backSpeed` | 1.8 | m/s | back walk (should be slower) |
| `weight` | 1 | × | knockback received is divided by this |
| `pushWidth` | 0.4 | m | push-box half-width |
| `hurtWidth` | 0.42 | m | standing hurtbox half-width |
| `height` | 1.85 | m | standing hurtbox height |

### 8.3 `movement`

| key | fields (defaults) |
|---|---|
| `dash` | `duration` 0.3 s, `distance` 2.4 m, `cancelFrom` 0.14 s (attacks may start from then) |
| `backstep` | `duration` 0.34, `distance` 1.7, `invuln` [0, 0.14] (strike-invulnerable) |
| `dodge` | `duration` 0.42, `invuln` [0.02, 0.3] (fully invulnerable), `cooldown` 0.7 (after it ends), `cancelFrom` 0.3 |
| `roll` | `duration` 0.42, `distance` 2.6 (corner escape; invulnerable, passes through) |

Displacement follows an ease-out over the duration. Backstep / back walk cannot increase the separation beyond
`rules.maxSeparation`.

---

## 9. Move reference

```js
heavy: {
  name: 'Iron Sweep', duration: 0.78,
  armour: [{ t: [0.08, 0.34], hits: 1 }],
  hits: [{ t: [0.34, 0.42], box: { f: [0.2, 2.3], u: [0.3, 1.9] }, damage: 105, level: 'heavy', hitstun: 0.5,
           blockstun: 0.3, knockback: { x: 4.5, y: 0 }, hitstop: 0.11, guardDamage: 28 }],
  cancels: [{ t: [0.38, 0.55], into: ['@skill', '@ult'], onHit: true }],
  markers: [{ t: 0.28, name: 'swing', data: { trail: 'heavy' } }, { t: 0.34, name: 'impact' }],
  ai: { range: [0.8, 2.25], role: 'pressure', weight: 0.8 },
}
```

| field | type / unit | default | meaning |
|---|---|---|---|
| `name` | string | id | display name |
| `group` | `'normal' \| 'skill' \| 'ult'` | inferred: `cinematic`/`superFreeze`/`ultCost` → ult, `fpCost` → skill, else normal | cancel groups, chip default, ULT gain rules |
| `duration` | s | **required** | total length; the fighter is busy until it ends (or cancels) |
| `hits` | array | `[]` | hit windows (§9.1) |
| `motion` | segments or keys | none | `[{t: [a, b], v}]` forward velocity m/s inside windows, or `{keys: [[t, f], [t, f, u], ...]}` cumulative forward displacement (m) and optional height (m), linear between keys. A height track should end at 0 |
| `cancels` | array | `[]` | `{t: [from, to], into, on?, dir?, onHit?, onContact?}` (§7). `into`: move id, ids, or tokens `@normal @skill @ult @any @dodge @dash`. With `on` (an attack button) it is a route with exactly one target |
| `armour` | array | `[]` | hyper-armour `{t: [a, b], hits = ∞, damageScale = 1}`: hits taken in the window deal `damage × damageScale` but cause no flinch, up to `hits` per move start. `armourPierce` hits and cinematic triggers ignore it |
| `invuln` | array | `[]` | `{t: [a, b], vs = 'all' \| 'strike' \| 'projectile'}` |
| `passThrough` | array | `[]` | `[a, b]` windows with push-boxes off (dash through the opponent) |
| `hurt` | array | `[]` | extra hurtboxes `{t: [a, b], box: {f, u}}` (extended limbs). Strikes of `normal` moves also extend the hurtbox automatically from their start to 0.12 s after their end (70 % of the reach), so whiffs can be punished |
| `counter` | object | none | counter stance `{t: [a, b], move, vs = 'strike', hitstop = 0.12}`: a non-unblockable hit landing in the window is nullified, both freeze `hitstop`, and `move` starts at once (forced: no cost). Give the follow-up `invuln` from t = 0 |
| `teleport` | array | `[]` | `{t, to: 'forward' \| 'behind', distance = 1, face = true}`: at `t`, jump `distance` forward, or to `distance` past the opponent; `face` turns toward the opponent afterwards. Emits `teleport` |
| `projectiles` | array | `[]` | spawned at their `t` (§9.2) |
| `markers` | array | `[]` | `{t, name, data?}` presentation hooks, emitted as `marker` when the move clock passes `t` |
| `fpCost` | FP | 0 | spent at start; FP regen pauses `rules.meters.fpRegenDelay` |
| `ultCost` | ULT | 0 | required to start; an `ult`-group move **empties** the gauge |
| `cooldown` | s | 0 | counted from the move start |
| `cooldownKey` | string | move id | moves with the same key share one cooldown (one HUD slot, two variants) |
| `requires` | object | none | `{minDistance, maxDistance}` (centre distance m), `opponentAirborne: bool`, `hpBelow: 0..1` |
| `superFreeze` | s or `{duration, userAnimates = true}` | none | §11 |
| `cinematic` | object | none | §11 |
| `ai` | object | derived | §14.2 |
| `meta` | any | — | free data for presentation |

### 9.1 Hit fields

Only `t`, `box` and `damage` are required; the rest default by `level` (`HIT_DEFAULTS`).

| field | unit | default (light / heavy / launch / crumple / knockdown) | meaning |
|---|---|---|---|
| `t` | `[t0, t1]` s | required | active window (inside the duration) |
| `box` | `{f: [a, b], u: [c, d]}` m | required | fighter-local hit box |
| `damage` | HP | required | before combo scaling / counter bonus |
| `level` | enum | `'light'` | reaction: `light` flinch, `heavy` stagger, `launch` airborne juggle, `crumple` long stun then falls (once per combo; a second becomes a knockdown), `knockdown` hard knockdown flight (no juggle) |
| `hitstun` | s | 0.3 / 0.45 / – / 0.95 / – | grounded stun on hit (launch / knockdown ignore it) |
| `blockstun` | s | 0.18 / 0.26 / 0.26 / 0.26 / 0.28 | stun on block |
| `knockback` | `{x, y}` m/s | x 2.4 / 4.2 / 1.2 / 1.0 / 4.5, y 0 / 0 / 8.5 / 0 / 3.4 | velocity along the attacker's forward and up. Ground slide ≈ x² / (2 × groundFriction) m |
| `hitstop` | s | 0.06 / 0.1 / 0.11 / 0.12 / 0.12 | freeze on hit (× 0.75 on block, × 1.35 on counter hit) |
| `chip` | HP | `damage × rules.chip[group]` (normal 0, skill 15 %, ult 20 %) | HP lost through guard (never below 1 HP unless `rules.block.chipCanKO`) |
| `guardDamage` | pts | `max(3, damage × 0.3)` | guard gauge drained on block |
| `unblockable` | bool | false | ignores guard (and counter stances) |
| `armourPierce` | bool | false | ignores hyper-armour |
| `multi` | `{interval, max}` | 1 hit | may connect up to `max` times, `interval` s of move time apart |
| `juggle` | points | 1 | juggle points added when it hits an airborne victim (fractional allowed) |
| `air` / `ground` | bool | true / true | can hit airborne / grounded victims |
| `cinematic` | bool | false | the cinematic trigger (normally set through `cinematic.hit`) |
| `hurtExtend` | bool | true for `normal` moves | auto hurtbox extension (see `hurt`) |
| `scaleStep` | 0..1 | `rules.combo.step` | combo scale lost by this hit (multi-hit sub-hits use small steps) |
| `label` | string | — | echoed in `hit` events |

### 9.2 Projectile fields

| field | unit | default | meaning |
|---|---|---|---|
| `t` | s | required | spawn time in the move |
| `kind` | string | `'<move>.<i>'` | presentation key (VFX by kind) |
| `at` | `'self' \| 'opponent'` | `'self'` | spawn origin: the owner, or the opponent's x on the floor (targeted strikes) |
| `offset` | `{f, u}` m | `{f: 0, u: 1.2}` | spawn offset (forward relative to the owner's facing) |
| `box` | `{f, u}` m | required | hit box relative to the projectile, `f` along its travel direction |
| `velocity` | `{x, y}` m/s | 0 | x along the owner's forward |
| `gravity` | m/s² | 0 | |
| `lifetime` | s | required | active life (after `delay`) |
| `delay` | s | 0 | harmless telegraph before it becomes active (does not move meanwhile) |
| `hit` | object | required | hit fields of §9.1 without `t` / `box` |
| `multi` | `{interval, max}` | 1 | multi-hit (interval in projectile age) |
| `pierce` | bool | false | keeps living after its last hit (otherwise expires `'hit'`) |
| `durability` | int | 1 | clash strength: overlapping enemy projectiles subtract each other's durability; ≤ 0 expires `'clash'` |
| `clash` | bool | true | takes part in clashes |
| `data` | any | null | echoed in `projectileSpawn` |

---

## 10. Combat rules

**Order inside a substep:** both fighters move → push-boxes → projectiles move and clash → both fighters' strikes and
every projectile contact are **collected**, then resolved together (so trades happen: both hits land) → push-boxes are
settled again. Cinematic triggers resolve first; once a lock starts, the substep's other contacts are dropped. Each
attacker connects at most one hit window per substep.

**Resolution of one contact** (`combat.js resolveContact`):

1. *Invulnerable* → passes through (not consumed; the window can still connect later). A dodging victim inside its
   invulnerable window emits `perfectDodge` (once per dodge).
2. Wrong height (`air: false` vs airborne, `ground: false` vs grounded) → passes through.
3. *Counter stance* window of the victim, `vs` matching, hit not unblockable / not a cinematic trigger → `counter`.
4. *Guard*: victim in `guard` / `blockstun`, grounded, attacker in front (projectiles: travelling toward the victim's
   front), hit not unblockable → **block**: chip (≥ 1 HP left), guard gauge −`guardDamage`, `blockstun`, pushback
   `knockback.x × 0.85`, hit-stop × 0.75. **Perfect guard**: guard pressed within `rules.block.perfectWindow` (0.12 s)
   before the hit → no chip, no gauge damage, half blockstun and pushback. **Guard break**: gauge empty → `guardbreak`
   stun (`rules.guardBreakTime` 1.1 s, hit-stop × 1.6), the gauge refills when it ends.
5. *Armour* window with hits left, hit not `armourPierce` / not a trigger → damage, no flinch, hit-stop × 0.8.
6. *Clean hit*: combo bookkeeping, damage, reaction, hit-stop, meters, KO.

**Pinned victims:** when a grounded victim's pushback slide is stopped by the wall, the remaining slide is passed to the
attacker (× 0.85), so corner pressure pushes the attacker out instead of locking both in place.

**Combos** (`fighter.recv` on the victim, `fighter.combo` on the attacker): a combo starts with the first clean hit
and lasts while the victim stays in `hitstun` / `launched` / `guardbreak` / `locked`; leaving those states emits
`comboEnd`. Damage scale: the first `combo.fullHits` (2) hits 100 %, then −`combo.step` (10 %) per hit (or the hit's
`scaleStep`), floor `combo.floor` (40 %). Hitstun multiplier: `max(0.5, 1 − 0.03 × (hits − 1))`, further × (1 − 0.15
per second) after 3 s of combo. **Counter hit** (victim hit during the startup or active part of its move): damage ×
1.2, hitstun × 1.3, hit-stop × 1.35 (`hit.counter`). **Punish** flag: victim in move recovery, dash, backstep, dodge,
guard break or recovery.

**Juggles:** a `launch` hit (or any hit on an airborne victim) sends the victim into `launched`; every air hit adds its
`juggle` points (launch from the ground: 1). Air hits pop the victim up by `max(knockback.y, juggle.pop 4.2)` m/s with
half the horizontal knockback. Gravity grows 8 % per juggle point. At `rules.juggle.limit` (6) points the victim is
invulnerable until it lands. **Wall bounce**: a juggled / knocked-down victim hitting the wall at ≥ 5.5 m/s bounces
once per combo (+1 juggle point, re-opens a hard knockdown). **Landing** → `knockdown` (0.7 s, invulnerable) →
`getup` (0.45 s, invulnerable) → neutral; a dodge press buffered on landing from a non-hard juggle **tech rolls**
(straight to `getup`, sliding away). Safety net: after 40 hits or 8 s every hit of the combo becomes a knockdown — no
infinite exists.

**KO:** HP 0 → the victim flies (hard) and lies in `ko`; `ko` event; the round goes to phase `'ko'`. Both at 0 in the
same substep = double KO (drawn round).

---

## 11. Ultimates: super-freeze and cinematic lock

* **Super-freeze** (`superFreeze: 0.6` or `{duration, userAnimates}`): at the move start, `superFreezeStart` and a
  `marker` named `'superFreeze'` are emitted and for `duration` s the opponent, all projectiles, the round clock,
  cooldowns and regen are frozen. With `userAnimates: true` (default) the user's move clock keeps running so the
  wind-up plays on its timeline (hits must start after the freeze — the validator enforces it); the user is
  invulnerable during the freeze. With `false` the user's move clock also waits. The frozen opponent's input buffer
  keeps ageing (no mashing through the freeze). Then `superFreezeEnd`.
* **Cinematic lock** (`cinematic`): when hit `cinematic.hit` (index into `hits`) connects **unblocked** (armour does
  not stop it), the trigger hit deals its damage (never lethal) and the lock starts: `cinematicStart`. The victim
  (`locked`) is placed `distance` m in front of the attacker (both pushed off a wall if needed); both are frozen and
  invulnerable; projectiles and the round clock pause. On the lock's own clock (t = 0 at the trigger):
  * `ticks: [{t, damage, hitstop?, marker?, data?}]` deal damage (never below 1 HP) and emit `cinematicTick` (+ a
    `marker` named `marker`); `hitstop` is for the presentation to stutter its animation.
  * `finish: {t, damage, level: 'knockdown' | 'launch', knockback, hitstop, marker}` deals the last damage (may KO).
  * `markers: [{t, name, data}]` are emitted as `marker` events with `cinematic: true`.
  * At `duration`: `cinematicEnd`; the victim is released with the finish knockback (knockdown flight, or a juggle
    with only 2 juggle points left for `launch`); the attacker enters `recovery` for `cinematic.recovery` (0.5 s),
    invulnerable. A lethal lock emits `ko` (with `cinematic: true`) here — the KO lands at the climax.
  * Tick and finish damage × `max(rules.cinematicScaleFloor 0.7, combo scale at the trigger)`.
* **Blocked** trigger: a normal block (ult chip 20 %), no lock, the move recovers. **Whiffed**: the move simply
  recovers. The ULT gauge is spent either way.

---

## 12. Projectiles

Spawned from the move timeline (`projectileSpawn`), first inactive for `delay` (telegraph; `projectileActive` when it
arms), then they travel for `lifetime`. They expire by `'lifetime'`, `'bounds'` (|x| > arena + 1.5), `'ground'`,
`'hit'`, `'clash'`, `'countered'` (absorbed by a counter stance) or `'round'`. Enemy projectiles that overlap clash
(`projectileClash`, durability arithmetic). A projectile hit freezes the victim and the projectile, never the owner.
Projectiles hit only the owner's opponent and keep flying when the owner is hit. `projectileMove` is emitted every
substep only when somebody listens to it (reading `match.projectiles` is cheaper).

---

## 13. Meters and rounds

| meter | rules |
|---|---|
| HP | 1000 default; reset every round |
| FP | start of round `meters.fpStart` (100); spent by `fpCost`; regenerates `fpRegen` 7/s after `fpRegenDelay` 0.6 s; +`fpOnHit` 1 per clean hit dealt |
| ULT | 0 at match start; +`ultDeal` 0.045 per HP dealt and +`ultTake` 0.06 per HP taken (blocked: 0.02 / 0.03 per chip+guard point); an attacker gains nothing from its own `ult` moves; an `ult`-group move empties it; **carries between rounds** (`meters.ultCarry`) |
| guard | `guardMax` 100; drained by `guardDamage`; regenerates `guardRegen` 14/s after `guardRegenDelay` 1.3 s (× 0.25 while holding guard); empty = guard break, refilled when the break ends; reset every round |

Discrete changes emit `meter` (`{fighter, kind, value, delta, max}`); continuous regeneration does not — read the
fields every frame. `ultReady` fires when ULT reaches its max.

**Round flow:** `roundStart` → phase `intro` (`introTime` 2.2 s, fighters in `intro`) → `fightStart` → phase `fight`
(clock `roundTime` 99 s) → KO (`ko`, phase `'ko'` for `koTime` 2.8 s) or time-up (`timeUp`, phase `'timeup'`
`timeUpTime` 2 s: higher HP ratio wins, equal = draw) → `roundEnd` (winner states switch to `victory` / `defeat`) →
phase `outro` (`outroTime` 2.4 s) → next round, or `matchEnd` and phase `'end'`. A drawn round gives both fighters a
round. The first to `roundsToWin` (2) with more rounds than the other wins; after `maxRounds` (5) the leader wins, or
the match is drawn (`winner: -1`). New round: HP / FP / guard / cooldowns / positions reset, ULT carried, projectiles
cleared.

---

## 14. Controllers

`controller = { kind, update(view) -> input, attach?({match, index, rng}), reset?() }`, polled once per `step`.
`view = { match, index, self, opponent, dt, time, phase, roundTime (s since fightStart), clock }`.

| factory | use |
|---|---|
| `createHumanController(provider)` | `provider(index, view)` returns the held input state |
| `actionsProvider(held, player?)` | adapts `input.held(action, player)` (CONTRACT input module) to a provider |
| `createScriptedController(script, {clock = 'round', loop})` | `[{t, dur = 0.05, ...input}]` entries held from `t` for `dur`; or `(t, view) => input` |
| `createIdleController()` | presses nothing |
| `createAIController({difficulty, overrides, rng})` | §14.1 |

### 14.1 AI

Generic over any definition. It perceives its opponent through a delay buffer (`reaction` seconds old; positions
lightly extrapolated) — it never reads inputs — and plays through held buttons like a human. Each step: tech roll /
wake-up guard or reversal / hold guard through block strings → hit-confirm and pick the best cancel (combo) → react to
perceived attacks and projectiles (guard, dodge timed at the impact, counter stance, back off) → punish blocked or
whiffed recovery, guard breaks, juggle, okizeme (meaty on get-up) → on think ticks, neutral by distance zone
(`far` / `mid` / `close` vs the opponent's threat reach) and initiative (who is plus after a block / hit): approach,
dash, step in and out, wait, anticipatory guard, pokes, pressure, launchers, zoning, mobility, skills, ultimate.

| level | reaction (s) | guard | dodge | punish | hit-confirm (s) | combo | spacing | mistakes |
|---|---|---|---|---|---|---|---|---|
| easy | 0.42 | 0.30 | 0.06 | 0.18 | 0.32 | 0.35 | 0.15 | 0.20 |
| normal | 0.28 | 0.50 | 0.12 | 0.45 | 0.20 | 0.65 | 0.45 | 0.08 |
| hard | 0.20 | 0.66 | 0.20 | 0.72 | 0.12 | 0.85 | 0.70 | 0.035 |
| nightmare | 0.14 | 0.76 | 0.28 | 0.92 | 0.07 | 0.97 | 0.92 | 0.012 |

All fields (`AI_LEVELS` in `ai.js`: also counter, backoff, holdGuard, whiffPunish, blockString, mash, juggle, tech,
wakeGuard, reversal, skill, ult, aggression, patience, perfect, noise, think interval) can be overridden:
`createAIController({ difficulty: 'hard', overrides: { reaction: 0.25 } })`.

### 14.2 AI hints (`move.ai`)

| field | meaning | when absent |
|---|---|---|
| `range: [min, max]` | centre-to-centre distance (m) where the move is a good idea | `[0, reach]` from frame data; projectiles `[2.5, min(9, reach)]` |
| `role` | `poke` (fast, safe-ish neutral), `pressure` (frame traps, guard drain), `approach` (closes distance), `launcher`, `combo` (used mostly in combos), `juggle`, `finisher` (ultimate: combo ender / punish), `punish`, `antiair`, `zoning` (projectiles), `counter` (counter stance), `mobility` (dashes, teleports), `reversal` | inferred: cinematic → finisher, counter → counter, projectile → zoning, no hits → mobility, launch → launcher, ≥ 1.5 m of motion → approach, startup ≤ 0.13 s → poke, else pressure |
| `weight` | relative preference (1 = normal) | 1 |
| `comboOnly` | never thrown raw from neutral (chain parts) | false |

The AI also uses `startup`, `activeEnd`, `recovery`, `reach`, `onBlock`, `damage`, unblockable flags and cancel windows
it derives from the move data, for both its own moves and the opponent's (threat range, punish windows).

---

## 15. Validation and frame data

* `validateFighterDef(def)` → `{ok, errors, warnings}`. Errors are path-qualified and specific, e.g.
  `moves.light2.hits[0].t: hit window (s) [0.1,0.9] must lie inside [0, 0.4]`,
  `moves.heavy.cancels[0].into: unknown move 'lunj' - did you mean 'lunge'?`,
  `moves.verdict.superFreeze: the first active time 0.82 s falls inside the 0.9 s super-freeze; hits must start after the freeze`.
  Warnings: unknown fields with suggestions (`moves.heavy.hit: unknown field (ignored) - did you mean 'hits'?`),
  multi-hit windows too short for their hit count, unreachable moves, counter follow-ups without invulnerability,
  height tracks that end in the air, very long hit-stops.
* `deriveFrameData(move)` → `{startup, activeEnd, active, recovery, duration, damage, hits, reach, strikeReach, level,
  onHit, onBlock, knockdown, cancellable, armour, invuln, counter, teleport, cinematic, projectile, unblockable, fpCost,
  ultCost, cooldown, motion, frames: {startup, active, recovery, duration, onHit, onBlock}}` (seconds; `frames` at
  60 fps). Advantage = victim stun − attacker time left after the **last** hit's first active moment (projectiles:
  released at point blank); `null` for launches / knockdowns.
* `fighterFrameData(def)` (all moves), `frameDataTable(def, {unit: 'frames' | 'seconds'})` (printable):

```
$ node src/game/logic/test/framedata.mjs
move        slot      startup  active  recov  total  dmg  hits   reach  onHit  onBlock  level      cost     cd  notes
light1      light           6       2     13     22   34     1    1.75     +2       -4  light      -        -   cancel
heavy       heavy          20       5     22     47  105     1    2.30     +4       -8  heavy      -        -   armour cancel
grave       b+skill1       45       0      3     48   90     3  target    +21       +9  light      FP 25    4s  proj
verdict     ult            49      10     37     96   80     1    5.87    -20      -28  heavy      ULT 100  -   invuln cinematic moves 4.0m
...
```

---

## 16. Rules (`DEFAULT_RULES`, override any subset in `createMatch({ rules })`)

| rule | default | meaning |
|---|---|---|
| `roundsToWin` / `maxRounds` | 2 / 5 | match length |
| `roundTime` | 99 s | round clock |
| `introTime` / `koTime` / `timeUpTime` / `outroTime` | 2.2 / 2.8 / 2.0 / 2.4 s | phase lengths (`introTime: 0` starts fighting at once) |
| `arenaHalfWidth` / `startX` / `maxSeparation` | 9 / 2.5 / 11 m | arena, start positions, max distance walking back allows |
| `gravity` / `groundFriction` / `airDrag` | 24 m/s² / 15 m/s² / 0.4 /s | physics of launches and slides |
| `maxSubstep` / `maxStep` | 1/60 / 0.1 s | sub-stepping (§3) |
| `inputBuffer` / `doubleTapWindow` / `turnDelay` | 0.2 / 0.22 / 0.05 s | input |
| `combo` | `{fullHits 2, step 0.1, floor 0.4, hitstunStep 0.03, hitstunFloor 0.5, hitstunTime 3, hitstunTimeRate 0.15, maxHits 40, maxTime 8}` | §10 |
| `juggle` | `{limit 6, gravityStep 0.08, pop 4.2}` | §10 |
| `counterHit` | `{damage 1.2, hitstun 1.3, hitstop 1.35}` | multipliers |
| `block` | `{hitstopScale 0.75, pushbackScale 0.85, perfectWindow 0.12, perfectStunScale 0.5, chipCanKO false}` | §10 |
| `chip` | `{normal 0, skill 0.15, ult 0.2}` | default chip ratio by move group |
| `guardDamageRatio` | 0.3 | default `guardDamage` = damage × ratio (min 3) |
| `guardBreakTime` / `knockdownTime` / `getupTime` | 1.1 / 0.7 / 0.45 s | |
| `techRollDistance` | 1.4 m | |
| `wallBounce` | `{speed 5.5, restitution 0.35, pop 4.5, max 1}` | |
| `cinematicScaleFloor` | 0.7 | §11 |
| `meters` | `{fpStart 100, fpRegen 7, fpRegenDelay 0.6, fpOnHit 1, ultDeal 0.045, ultTake 0.06, ultBlockDeal 0.02, ultBlockTake 0.03, ultCarry true, guardRegen 14, guardRegenDelay 1.3, guardRegenWhileGuarding 0.25}` | §13 |

Unknown rule names throw (`rules.roundTim: unknown rule`).

---

## 17. Events

Every payload is a fresh plain object with `time` (match time, s). Fighter references are indices (0 / 1). World
positions are on the fight line (`z = 0`).

| event | payload |
|---|---|
| `roundStart` | `round, rounds: [a, b], introTime, clock` |
| `fightStart` | `round, clock` |
| `phase` | `from, to, round` |
| `timeUp` | `winner (-1 draw), hp: [a, b]` |
| `roundEnd` | `round, winner (-1 draw), reason 'ko' \| 'doubleKo' \| 'time', hp, rounds, clock, matchOver, matchWinner` |
| `matchEnd` | `winner (-1 draw), rounds: [a, b], roundsPlayed` |
| `state` | `fighter, from, to` |
| `turn` | `fighter, facing` |
| `moveStart` | `fighter, move, name, group, cancelFrom (id \| null), forced, facing, x, y, duration, serial` |
| `moveEnd` | `fighter, move, reason 'complete' \| 'cancel' \| 'interrupted' \| 'cinematic' \| 'round', connected, hit` |
| `moveDenied` | `fighter, move, reason` (once per press; HUD feedback) |
| `marker` (alias `moveEvent`) | `fighter, move, name, t, data, x, y, facing, cinematic?` |
| `teleport` | `fighter, move, from, to, facing` |
| `dodge` | `fighter, kind 'dash' \| 'backstep' \| 'dodge' \| 'roll', x, facing, duration` |
| `perfectDodge` | `fighter, attacker, move, projectile (id \| null), x` |
| `hit` | `attacker, defender, kind 'strike' \| 'projectile', move, hit (index), projectile, label, damage, chip, blocked, perfect, armoured, counter, punish, unblockable, guardBreak, cinematic, ko, level, x, y (contact point), facing (attacker), combo (hits so far), comboDamage, scaling, juggle, hitstop, guard (victim gauge)` |
| `guard` | `fighter, attacker, move, perfect, chip, gauge, guardBreak, x, y` |
| `guardBreak` | `fighter, attacker, move, x, y` |
| `counter` | `fighter, attacker, move (stance), into (follow-up), against (attacker move), projectile, x, y` |
| `comboEnd` | `attacker, defender, hits, damage, juggle, duration` |
| `land` | `fighter, x, hard, ko` |
| `tech` | `fighter, x` |
| `wallBounce` | `fighter, x, y` |
| `ko` | `fighter (loser), by, x, y, cinematic` |
| `meter` | `fighter, kind 'hp' \| 'fp' \| 'ult' \| 'guard', value, delta, max` |
| `ultReady` | `fighter` |
| `projectileSpawn` | `id, owner, kind, move, x, y, vx, vy, facing, delay, lifetime, data` |
| `projectileActive` | `id, owner, kind, x, y` |
| `projectileMove` | `id, x, y, vx, vy` (only when listened to) |
| `projectileHit` | `id, owner, defender, result 'hit' \| 'blocked' \| 'armoured', x, y` |
| `projectileClash` | `a, b, owners, x, y, survivor (id \| null)` |
| `projectileExpire` | `id, owner, kind, x, y, reason` |
| `superFreezeStart` / `superFreezeEnd` | `fighter, move, duration, x, y, facing` / `fighter, move` |
| `cinematicStart` | `attacker, defender, move, duration, x, facing, victimX, scale` |
| `cinematicTick` | `attacker, defender, move, index, t, damage, hitstop, marker, data, final, x, y` |
| `cinematicEnd` | `attacker, defender, move, damage (lock total), ko, x` |

---

## 18. Presentation notes

* Drive each character from `state` / `stateTime` (locomotion, stun, knockdown) and `move` / `moveTime` (the move
  clip, sampled at `moveTime`, so hit-stop and cancels stay in sync). Name clips after move ids; time VFX, trails,
  audio and camera from `marker` names.
* `hit` gives the contact point, level, counter / punish / armour / perfect flags and the hit-stop to scale shakes,
  flashes and impact frames. `blocked` + `perfect` deserve a distinct spark; `guardBreak` a big one.
* Ultimates: `superFreezeStart` → darken the world, letterbox, cut to the user; `cinematicStart` → play the shot list
  anchored on `attacker` (choreograph freely: the rules hold both fighters in place); `cinematicTick` → impacts;
  `cinematicEnd` → blend back to the logic positions (`fighters[i].x`). Whiff / block → no lock.
* HUD: `fighters[i].hp / fp / ult / guard`, `match.clock`, `fighters[i].rounds`, `match.slots(i)` for skill buttons,
  `fighters[attacker].combo` + `comboEnd` for the combo counter, `moveDenied` for "not enough FP / cooldown" feedback.

---

## 19. Tests

`node src/game/logic/test/run.mjs` (Node ≥ 22, no dependencies):

* unit tests (`test/unit.test.mjs`): validation messages, frame data, hits and hit-stop (also at dt 1/30 and 1/144),
  guard / chip / perfect guard / cross-up / guard break, dodge invulnerability and cooldown, armour (and its hit
  limit), counter stance, input buffer (and expiry), on-hit-only cancels, direction variants, dash / backstep / walk
  speeds, command dash pass-through, teleport cross-ups, requirements, armour-pierce, hurtbox extension, projectiles
  (timeline spawn, lifetime, clash, victim-only hit-stop, opponent-anchored telegraph, shared cooldown), combo scaling
  and hitstun decay, juggle limit, counter hits, corner pushback transfer, corner roll escape, push-boxes, wall bounce,
  tech roll, FP / ULT / cooldowns / HUD slots, super-freeze, cinematic lock (hit, blocked, whiffed, lethal), rounds,
  time-up, draws, reset paths, markers.
* determinism (`test/determinism.test.mjs`): same seed → identical event-log hash and snapshot; interleaved matches
  equal solo runs; jittered dt with 0.1 s spikes is reproducible and sane.
* soak (`test/soak.mjs`, 300 AI-vs-AI matches across all 16 difficulty pairings): no exceptions, no NaN, invariants
  (arena, meters, juggle cap, push-boxes), no stuck state (> 8 s), every round ends; prints round length, KO / time-up
  rates, win rates per level and pairing, move usage, time share per state, block rate, combo stats, ULT / cinematic /
  guard-break / perfect-guard / dodge / counter / projectile / tech frequencies, and checks the tuning targets
  (average round 20–60 s, every sample move used, no move above 35 %, guarding < 35 % of the time, blocked contacts
  > 20 %, nightmare beats easy, win rates ordered by level).
