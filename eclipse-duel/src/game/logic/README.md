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
test/             run.mjs (runner), unit / edge-case / AI / determinism tests, fuzzer, soak, AI commentator, frame data
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
node src/game/logic/test/run.mjs            # all tests, the 60-match fuzzer, then the 300-match AI soak with statistics
node src/game/logic/test/run.mjs --quick    # tests only
node src/game/logic/test/framedata.mjs src/fighters/kael/moves.js   # frame-data table of any definition module
node src/game/logic/test/watch.mjs easy hard --seed 3 --rounds 1      # commentated AI-vs-AI timeline + behaviour report
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
* **Scale is a parameter** (boss-mode roadmap): nothing in the engine assumes a 1.9 m human. Body hurtboxes (standing,
  airborne, lying), the push-box vertical overlap, the default projectile height, the corner-roll thresholds, the
  cinematic victim placement and the validator's size sanity limits all derive from each fighter's `stats`
  (`height`, `hurtWidth`, `pushWidth`, `weight`). An 8 m colossus is just a definition with bigger stats, boxes and
  movement distances (covered by a test).

---

## 3. Time, stepping and hit-stop

`match.step(dt)` advances the match by `dt` seconds:

* Controllers are polled **once per call**; the engine derives presses from held buttons.
* `dt` is clamped to `rules.maxStep` (0.1 s) and split into `ceil(dt / rules.maxSubstep)` equal substeps
  (`maxSubstep` 1/60). Move timing does not depend on dt: the same inputs at dt 1/144, 1/60 or 1/30 produce the same
  hits and damage, shifted by at most one step of input polling (tested).
* Events raised during the call are **queued and dispatched when it returns** (listeners never see a half-resolved
  substep, and a throwing listener cannot corrupt the simulation; the first error is re-thrown after dispatch).

**Order inside one substep** (`match.js`): (1) intro gate, or a super-freeze / cinematic substep instead of the rest;
(2) each fighter advances by the substep minus its remaining hit-stop (move clock, motion, timeline, stun timers,
neutral actions); (3) push-boxes; cooldowns; (4) projectiles move, expire, clash; (5) both fighters' strikes and every
projectile contact are collected, then resolved together (trades); (6) **moves settle**: cancel windows are checked
against the buffered presses and moves that reached their end finish — *after* the substep's strike was collected,
so a cancel on the same frame as a hit never swallows the hit (and a cancel never happens while the fighter is in
hit-stop: it comes out when the freeze ends); (7) push-boxes again; meters regenerate; round clock; KO / time-up.

**Hit-stop is part of the rules.** On a strike, attacker and victim freeze for the hit's `hitstop`; on a projectile hit
only the victim (and the projectile) freeze. A frozen fighter's move clock, stun timer, motion and input-buffer ageing
stop; everything else (the other fighter if not frozen, projectiles, the round clock, cooldowns, regen) keeps running.
`fighter.hitstop` is the remaining freeze (s) and `fighter.hitstopShake` is true for the victim side.

> **Presentation:** step the match with *real* time (times pause / slow-motion scale), **not** with `ctx.time.dtGame`
> while also calling `ctx.time.hitstop()` — that would freeze the rules twice. Freeze a character's animation while
> `fighter.hitstop > 0` and shake it while `hitstopShake`. A global `ctx.time.hitstop(e.hitstop)` for VFX on `hit`
> events is fine as long as the match itself is stepped with `dtReal`.

Super-freeze and cinematic lock pause the round clock; hit-stop does not. Combo length (`fighter.recv.time`, the
`rules.combo.maxTime` cap, `comboEnd.duration`) runs on match time **including hit-stop** (not during a freeze or a
lock), so long hit-stops cannot stretch a combo past the cap.

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
| `freeze` | active super-freeze `{owner, move, remaining, duration, userAnimates, owners, moves, startTime}` or `null`. `owners` lists both fighters when both ultimates started in the same substep (§11); `owner` / `move` / `userAnimates` describe the first |
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
| `boxes(i)` | hitbox-viewer data for a training-mode overlay: `{hurt: [box], hit: [box], push: box, projectiles: [{id, active, box}]}`, boxes as world `[x0, x1, y0, y1]` (allocates) |
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
| `moveConnected`, `moveHit` | the current move touched the opponent (hit or block) / landed a clean hit — strikes, and projectiles it fired that connect while it is still running |
| `hitstop`, `hitstopShake` | remaining hit-stop (s); true on the victim side |
| `combo` | the combo this fighter is **dealing**: `{hits, damage, active}` (kept after it ends for the HUD) |
| `recv` | the combo this fighter is **receiving**: `{active, hits, damage, juggle, time (s of match time, hit-stop included), scale, wallBounces, attacker}` |
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
window (strikes only), `recovery` after a cinematic, move `invuln` windows, the super-freeze owner(s), everyone during a
cinematic, airborne victims that are `hard` (knockdown flight) or out of juggle points, everyone outside `'fight'`.

Push-boxes are off (the opponent can pass) for `roll`, `locked`, move `passThrough` windows, and bodies **lying on the
floor** (`knockdown`, `ko`): a standing fighter steps over a downed opponent, which is how wake-up cross-ups happen. The
riser is solid again in `getup` (invulnerable); if the two overlap then, they are pushed apart on their actual sides and
the riser turns to face its opponent. Every state change is announced by a `state` event, including the reset to
`intro` at a new round.

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
  `dash`; dodge + back or double-tap back → `backstep`. A forward dash with the back within 2.75 × pushWidth (1.1 m)
  of a wall and the opponent in your face becomes a **`roll`** that passes through (the corner escape). Dash / dodge
  accept attacks from their `cancelFrom` time. The dodge **cooldown starts with the dodge** (`duration + cooldown`
  from its start), so cancelling a dodge into an attack or being hit out of it cannot skip it.
* **Guard** is held: in neutral, holding guard enters `guard` (no walking). Attack and dodge presses override it.
* **Cancels**: during a move, open cancel windows are checked every substep — after that substep's contacts (§3) —
  against the buffered presses:
  1. *Routes* — a window with `on: 'light'` (and optional `dir`) sends that button to its single `into` move
     (`light1 → light2 → light3` chains). Routes with a matching `dir` win over routes without.
  2. *General cancels* — the press is resolved through the command map; the resulting move may start if a window lists
     it (`into: ['launcher']`) or its group (`'@normal' '@skill' '@ult' '@any'`).
  3. `'@dodge'` / `'@dash'` windows let dodge (+ direction) cancel the move.
  `onHit: true` windows need a clean hit by this move, `onContact: true` a hit or a block (a projectile fired by the
  move counts while the move is still running). Cancels pay the target's costs like any start. A move whose last
  moment touches a hit window or that has cancel windows stays alive through its final substep's contacts, so a
  last-frame hit lands and a window that runs to the end can still be taken.

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
| `ai` | object | `{aggression: 0.5, zoning: 0.5}` | AI personality: `aggression` 0..1 (rush vs patient), `zoning` 0..1 (projectile appetite), `preferredRange` m (footsies distance the AI tries to hold; default 0.9 × its longest poke reach) |
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
| `weight` | 1 | × (0.2 .. 50) | knockback received is divided by this |
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
| `armour` | array | `[]` | hyper-armour `{t: [a, b], hits = ∞, damageScale = 1}` (or the shorthand `[a, b]`): hits taken in the window deal `damage × damageScale` but cause no flinch, up to `hits` per move start. `armourPierce` hits and cinematic triggers ignore it |
| `invuln` | array | `[]` | `{t: [a, b], vs = 'all' \| 'strike' \| 'projectile'}` (or the shorthand `[a, b]`, vs all). Checked before counter stances: a hit the fighter is invulnerable to passes through |
| `passThrough` | array | `[]` | `[a, b]` (or `{t: [a, b]}`) windows with push-boxes off (dash through the opponent). Without one, motion of any speed stops at the opponent's centre and shoves it: nothing tunnels through a solid opponent |
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
| `t` | `[t0, t1]` s | required | active window (inside the duration). Zero-length windows (`[0.2, 0.2]`, also `[0, 0]`) strike exactly once at any dt |
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
| `at` | `'self' \| 'opponent'` | `'self'` | spawn origin: the owner (at its height), or the opponent's x on the floor (targeted strikes: pillars, eruptions) |
| `offset` | `{f, u}` m | `{f: 0, u: 0.65 × owner height}` for `'self'`, `{f: 0, u: 0}` for `'opponent'` | spawn offset (forward relative to the owner's facing) |
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

**Order inside a substep:** see §3. Both fighters' strikes and every projectile contact are **collected**, then
resolved together, so trades happen: both hits land, both are counter hits (each victim was in its startup), both
fighters freeze, and both can be KO'd on the same step (double KO). Cinematic triggers resolve first; once a lock
starts, the substep's other contacts are dropped — except when **both** fighters' triggers connect in the same substep
(simultaneous ultimates): they clash, neither lock starts and both resolve as ordinary hits (`hit.clash`). Each
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

**Bodies:** solid fighters never pass each other: any movement (walk, dash, motion, slide, flight) that would carry a
fighter past the opponent's centre stops there, and the push-boxes split the overlap. Passing needs a pass-through
window, a roll, a teleport, a lying opponent or enough height (one fighter more than 0.7 × the shorter height above the
other: juggles).

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
invulnerable until it lands. Launch speed is capped so no flight rises above `rules.juggle.apex` (3) × the victim's
height, whatever the knockback and weight. **Wall bounce**: a juggled / knocked-down victim hitting the wall at ≥ 5.5 m/s bounces
once per combo (+1 juggle point, re-opens a hard knockdown). **Landing** → `knockdown` (0.7 s, invulnerable) →
`getup` (0.45 s, invulnerable) → neutral; a dodge press buffered on landing from a non-hard juggle **tech rolls**
(straight to `getup`, sliding away). Safety net: after 40 hits or 8 s of combo (match time, hit-stop included) every
hit of the combo becomes a knockdown — a non-juggleable flight — so no infinite exists.

**KO:** HP 0 → the victim flies (hard) and lies in `ko`; `ko` event; the round goes to phase `'ko'`. Both at 0 in the
same substep = double KO (drawn round).

---

## 11. Ultimates: super-freeze and cinematic lock

* **Super-freeze** (`superFreeze: 0.6` or `{duration, userAnimates}`): at the move start, `superFreezeStart` and a
  `marker` named `'superFreeze'` are emitted and for `duration` s the opponent, all projectiles, the round clock,
  cooldowns and regen are frozen. With `userAnimates: true` (default) the user's move clock keeps running so the
  wind-up plays on its timeline (hits must start after the freeze — the validator enforces it); the user is
  invulnerable during the freeze. With `false` the user's move clock also waits. The frozen opponent's input buffer
  keeps ageing (no mashing through the freeze: only a press in the last `rules.inputBuffer` seconds comes out when it
  ends). Then `superFreezeEnd`.
* **Simultaneous ultimates**: an ultimate pressed while a freeze runs is refused (`moveDenied` `'freeze'`; in practice
  the frozen opponent never gets to try) — except in the very substep the freeze started: then both start (no player
  priority), share one freeze lasting the longer duration (`freeze.owners` = both, `superFreezeStart.simultaneous`),
  each user animates for exactly its own freeze duration, and each gets its `superFreezeEnd`. If both triggers then
  connect in the same substep they clash (§10).
* **Cinematic lock** (`cinematic`): when hit `cinematic.hit` (index into `hits`) connects **unblocked** (armour does
  not stop it), the trigger hit deals its damage (never lethal) and the lock starts: `cinematicStart`. The victim
  (`locked`) is placed `distance` m in front of the attacker (default: both push-widths + 0.5 m; both pushed off a
  wall if needed); both are frozen and
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

| level | reaction (s) | tempo | guard | perfect | punish | read | combo | depth | spacing | variety | mistakes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| easy | 0.42 | 0.5 | 0.30 | 0 | 0.15 | 0.05 | 0.35 | 1 | 0.15 | 0.3 | 0.20 |
| normal | 0.26 | 0.8 | 0.50 | 0.1 | 0.52 | 0.35 | 0.72 | 3 | 0.45 | 0.45 | 0.08 |
| hard | 0.22 | 0.86 | 0.62 | 0.2 | 0.66 | 0.6 | 0.88 | 3 | 0.70 | 0.65 | 0.035 |
| nightmare | 0.14 | 1 | 0.76 | 0.6 | 0.93 | 0.9 | 0.97 | 8 | 0.92 | 0.8 | 0.012 |

What the levels mean in play (sample fighter mirror, measured with `test/watch.mjs`, `test/soak.mjs` and 40-match
ladders): **easy** throws about 23 attacks a minute, waits and walks a lot, ends its combos after one cancel (chain
routes such as light1 → light2 → light3 are free at every level), rarely punishes, walks into counter stances and
perfect-guards only by luck (~15 % of its blocks). **Normal** ~30 attacks a minute, medium combos, punishes about half
the unsafe moves it blocks. **Hard** ~34, long combos, punishes reliably, reads stances, holds its footsies range.
**Nightmare** ~38: perfect-guards about 30 % of everything it blocks (two thirds of the slow, reactable attacks),
perfect-dodges, punishes stance recoveries, lands about 95 % of its ultimates (inside combos). Each level beats the
one below most of the time: easy takes roughly 5 % of matches from normal, normal 15–20 % from hard, hard 20–30 % from
nightmare (300-match soak and 40-match ladders).

Every field of `AI_LEVELS` (`ai.js`, documented there) can be overridden:
`createAIController({ difficulty: 'hard', overrides: { reaction: 0.25 } })`. Fields: `reaction`, `think` [s, s],
`tempo`, `guard`, `dodge`, `counter`, `backoff`, `holdGuard`, `perfect`, `punish`, `whiffPunish`, `read`, `confirm` (s),
`combo`, `blockString`, `mash`, `depth`, `juggle`, `meaty`, `tech`, `wakeGuard`, `reversal`, `spacing`, `variety`,
`skill`, `ult`, `mistake`, `aggression`, `patience`, `noise`.

### 14.2 AI hints (`move.ai`)

| field | meaning | when absent |
|---|---|---|
| `range: [min, max]` | centre-to-centre distance (m) where the move is a good idea | `[0, reach]` from frame data; projectiles `[2.5, min(9, reach)]` |
| `role` | `poke` (fast, safe-ish neutral), `starter` (neutral opener, like a poke), `pressure` (frame traps, guard drain; more against a low gauge or a cornered opponent), `approach` (closes distance), `launcher`, `combo` (used mostly in combos), `juggle` / `antiair` (preferred on airborne opponents, rare in neutral), `finisher` (ultimate: combo ender / punish), `punish` (preferred in punish windows, rare in neutral), `zoning` (projectiles, at range), `counter` (counter stance: against perceived attacks, on wake-up), `mobility` (dashes, teleports: always followed by an attack when the move has a cancel window for one), `reversal` (wake-up reversal, preferred over a counter stance) | inferred: cinematic → finisher, counter → counter, reached only through a chain route (not in the command map) → combo, projectile → zoning, no hits → mobility, launch → launcher, ≥ 1.5 m of motion → approach, startup ≤ 0.13 s → poke, else pressure |
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
  Errors also catch moves that can never start (`fpCost` / `ultCost` above the stat maximum, `minDistance` >
  `maxDistance`), a `cinematic: true` hit without a `cinematic` block, and absurd `stats.weight`.
  Warnings: unknown fields with suggestions (`moves.heavy.hit: unknown field (ignored) - did you mean 'hits'?`),
  multi-hit windows too short for their hit count, unreachable moves, counter follow-ups without invulnerability,
  counter windows hidden by the move's own `invuln` (hits pass through before the counter is checked), an ultimate
  without `ultCost`, hit boxes that only reach behind the fighter (sign slip), cinematic ticks after the finish, two
  trigger hits, height tracks that end in the air, very long hit-stops.
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
| `juggle` | `{limit 6, gravityStep 0.08, pop 4.2, apex 3}` | §10 (`apex`: highest flight, in victim heights) |
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

Every payload is a fresh plain object with `time` (match time, s; never decreasing). Fighter references are indices
(0 / 1). World positions are on the fight line (`z = 0`). Author `data` / `meta` echoed in events are deep-frozen
copies: a listener cannot change the definition (or the next event) through them.

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
| `hit` | `attacker, defender, kind 'strike' \| 'projectile', move, hit (index), projectile, label, damage, chip, blocked, perfect, armoured, counter, punish, unblockable, guardBreak, cinematic (lock trigger), clash (simultaneous triggers), ko (this hit kills: clean, armoured or chip), level, reaction (defender state after the hit: 'hitstun' 'launched' 'blockstun' 'guardbreak' 'locked', or its move state for armour), x, y (contact point), facing (attacker), defenderFacing, front (false: hit from behind), combo (hits so far), comboDamage, scaling, juggle, hitstop, guard (victim gauge)` |
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
| `superFreezeStart` / `superFreezeEnd` | `fighter, move, duration, x, y, facing, simultaneous` / `fighter, move` (one pair per ultimate user) |
| `cinematicStart` | `attacker, defender, move, duration, x, facing, victimX, victimFacing, scale` (a `turn` event precedes it when the victim is turned to face the attacker) |
| `cinematicTick` | `attacker, defender, move, index, t, damage, hitstop, marker, data, final, x, y` |
| `cinematicEnd` | `attacker, defender, move, damage (lock total), ko, x` |

---

## 18. Presentation notes

* Drive each character from `state` / `stateTime` (locomotion, stun, knockdown) and `move` / `moveTime` (the move
  clip, sampled at `moveTime`, so hit-stop and cancels stay in sync). Name clips after move ids; time VFX, trails,
  audio and camera from `marker` names.
* `hit` gives the contact point, level, the defender's resulting `reaction`, `front` (pick a front or back flinch),
  counter / punish / armour / perfect / ko flags and the hit-stop to scale shakes, flashes and impact frames.
  `blocked` + `perfect` deserve a distinct spark; `guardBreak` a big one; `ko` the slow-motion finisher.
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
  time-up, draws, reset paths, debug boxes, markers, a giant-scale definition, the AI on a bare definition (no hints,
  no skills) and the AI's reaction delay.
* edge cases (`test/edge.test.mjs`): trades (simultaneous jabs, double KO, simultaneous ultimates and trigger clash),
  hits on the last active frame and at the move end, zero-length windows at t = 0 / mid / end at four dts, markers at
  0 and at the end, a cancel on the same frame as a hit, presses buffered through a long hit-stop and through a
  super-freeze (late ones come out, early ones expire), hits in dodge recovery and the dodge cooldown, guard released
  during blockstun, the owner's projectile during its cinematic, time-up vs a running lock (and a lethal lock), lock
  release overlap, corner pass-through and pushback, no tunnelling at any speed, stepping over a knocked-down
  opponent, launch apex cap, combo cap with long hit-stops, wall bounce at the floor, projectile spawn heights and
  on-hit cancels from projectiles, hit payload flags, immutable event data, state-event continuity across rounds, dt
  1/30 vs 1/60 vs 1/120 equivalence, a whole idle match, extreme data, and the validator's authoring checks.
* AI (`test/ai.test.mjs`): every level defines every field the AI reads; counter stances are read and their recovery
  punished; mobility moves are followed up; activity is ordered easy < normal < nightmare; nobody stands still for
  long or repeats one move; `preferredRange` moves its footsies distance; a 10-move fighter with a cinematic ultimate
  written from this README with no `ai` hints (`authoredFighter` in `test/fixtures.mjs`) validates warning-free and
  the AI uses every one of its moves.
* determinism (`test/determinism.test.mjs`): same seed → identical event-log hash and snapshot; interleaved matches
  equal solo runs; jittered dt with 0.1 s spikes is reproducible and sane.
* fuzz (`test/fuzz.mjs`, 60 matches, several thousand simulated seconds): random-input controllers (mashers, holders,
  mixed) and the AI on the sample, an extreme-data fixture, an 8 m giant and the authored fighter (`test/fixtures.mjs`), random dt patterns
  (1/30, 1/60, 1/120, jitter, 0.1–0.4 s spikes) and rule variations. Every step: finite numbers, bodies inside the
  arena and above the floor, meters / timers / cooldowns in range, 'attack' ⇔ a move whose clock lies in its
  duration, solid push-boxes never overlapping, nothing stuck, clock and HP never rising inside a round; every event:
  known name, non-decreasing time, valid indices, `state` chains (from = previous to), moveStart / moveEnd pairing,
  projectile ids spawned once and expired once, super-freeze and cinematic pairing, one KO per fighter per round, the
  combo cap. `--fuzz N`, `--fuzz-seed S`.
* `node src/game/logic/test/watch.mjs [level] [level] [--seed N] [--rounds N] [--def module] [--quiet]` prints a
  commentated AI-vs-AI timeline (throws, cancels, hits, blocks, whiffs, punishes, combos, ultimates, KOs, standing
  still) and a per-fighter report (move mix, moves per minute, whiff rate, punishes, perfect guards / dodges, idle
  share and longest idle, longest same-move streak, guard share, distance zones).
* soak (`test/soak.mjs`, 300 AI-vs-AI matches across all 16 difficulty pairings): no exceptions, no NaN, invariants
  (arena, meters, juggle cap, push-boxes), no stuck state (> 8 s), every round ends; prints round length, KO / time-up
  rates, win rates per level and pairing, move usage, time share per state, block rate, combo stats, ULT / cinematic /
  guard-break / perfect-guard / dodge / counter / projectile / tech frequencies, and checks the tuning targets
  (average round 20–60 s, every sample move used, no move above 35 %, guarding < 35 % of the time, blocked contacts
  > 20 %, nightmare beats easy, win rates ordered by level).
