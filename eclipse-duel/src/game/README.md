# src/game — presentation layer and the fighter content API

The game: flow (title → select → vs → match → result), the binding of the rules engine (`src/game/logic/`) to
characters, VFX, camera, audio, post and UI, the generic "feel" of every hit, and **the API fighter choreographers
write against** (`src/fighters/<id>/index.js` → `present`).

```
src/main.js            boot: stored quality -> createApp -> env -> vfx -> cam -> audio -> input -> ui -> game; veil; ready()
src/game/index.js      createGame: flow, sessions, pause, quality, attract / quick-match flags, window.__ED.game (test API)
src/game/session.js    one rules match bound to the presentation: stepping, event queue, round flow, HUD, stats
src/game/actor.js      one fighter on screen: character, rules state -> clip, hit-stop freeze + shake, auto trail / whoosh
src/game/clips.js      clip resolution + retiming onto frame data, generic fallback clips (game.*)
src/game/present.js    content API runtime: event routing, the helper object `h`, the ultimate (super-freeze + lock) runner
src/game/feel.js       generic feel per event (sparks, shake, kicks, post, audio, dust, KO slow motion, projectiles)
src/game/fx.js         safe VFX access (unknown presets never throw) + generic presets (game.hit / guard / dust / ...)
src/game/placeholder.js tinted knight design + sample rules definition for fighters whose files do not exist yet
src/game/prof.js       #prof: per update-group CPU timing
src/game/tests/        capture.mjs (screens / fight / heavy / KO / ult / result), moves.mjs (every move of a fighter, guard,
                       guard break, knockdown), input.mjs (every human action + the whole menu flow, PASS / FAIL),
                       soak.mjs (CPU matches with per-frame invariants + session churn memory), poses.mjs, api.mjs,
                       profile.mjs (fight + ultimate peaks), ultcost.mjs (per-frame render cost of an ultimate)
src/fighters/registry.js  roster (menu data) + loader of src/fighters/<id>/ with fallbacks
```

---

## 1. Running it

```sh
node tools/build.mjs game                                   # dist/eclipse-duel.html
node tools/shot.mjs game --at 1 --out shots/game/title       # title screen
node tools/shot.mjs game --hash "demo=kael,iska" --at 3,6,9 --sheet-only --out shots/game/demo
node tools/shot.mjs game --scenario src/game/tests/capture.mjs --sheet --sheet-only --out shots/game/all
SECTIONS=ult node tools/shot.mjs game --scenario src/game/tests/capture.mjs --sheet --out shots/game/ult
node tools/shot.mjs game --scenario src/game/tests/capture.mjs --touch --size 390x844 --out shots/game/portrait
node tools/shot.mjs game --hash "prof&q=mid" --size 640x360 --scenario src/game/tests/profile.mjs   # timing per tier (fight + ultimate)
node tools/shot.mjs game --scenario src/game/tests/api.mjs                                  # content API smoke test
node tools/shot.mjs game --scenario src/game/tests/flow.mjs                                 # keyboard: title -> select -> vs -> fight -> pause
node tools/shot.mjs game --scenario src/game/tests/input.mjs --out shots/game/input         # every action + menus: PASS / FAIL lines
TOUCH=1 node tools/shot.mjs game --touch --size 844x390 --scenario src/game/tests/input.mjs # touch pad buttons + stick
FIGHTERS=iska GUARD=1 DOWN=1 node tools/shot.mjs game --size 960x540 --scenario src/game/tests/moves.mjs --sheet 4 --sheet-only --out shots/game/moves
SECTIONS=ult ULT=kael,iska,vorn node tools/shot.mjs game --scenario src/game/tests/capture.mjs --sheet 4 --sheet-only --out shots/game/ult
MEMORY=1 MATCHES=4 node tools/shot.mjs game --size 320x180 --scenario src/game/tests/soak.mjs   # invariants + memory churn
```

On a loaded build machine the page can take minutes to boot (it parses ~2 MB and builds both fighters): the harness's
120 s navigation timeout then fails. A private copy of `tools/shot.mjs` with `page.goto(..., { timeout: 900000,
waitUntil: 'commit' })` works around it (`tools/` is the lead's).

URL flags (besides the core ones `#test #q=low|mid|high #fps #fpsmeter #nodrs`):

| flag | effect |
|---|---|
| `#demo=kael,iska[,hard]` | attract mode: CPU vs CPU forever (result screen 4 s, then a rematch) |
| `#fight=kael,vorn[,normal]` | straight into a match, P1 human vs CPU |
| `#training=kael,iska` | training: P2 idle dummy, infinite FP / ULT, HP refills below 25 % |
| `#seed=N` | seed of `ctx.rng` and of the match (AI decisions) |
| `#prof` | logs `[ed] prof {...}` every 2 s: JS ms per `ctx.ORDER` group, render submit ms, draw calls, triangles |

The quality chosen in the title / pause menu is stored in `localStorage` (`ed.quality`) and applied as `#q=` on
reload (both inside try/catch: blocked storage only loses the preference).

---

## 2. Time model (read this before writing choreography)

* The rules are stepped every frame with **real time × presentation slow motion** (`ctx.time.scale` outside a hit-stop;
  0 while paused). The rules apply their own per-fighter hit-stop; nothing in the presentation freezes the match.
* On every strike the feel layer also calls `ctx.time.hitstop(e.hitstop)`: **game time** (characters, VFX, the arena,
  game-clock camera shots) freezes with the fighters. Real-time things keep going: camera shake, post pulses, UI,
  and VFX spawned with `realtime: true` (the generic hit flash blooms and decays *during* the freeze while its sparks
  wait for it).
* During a **cinematic lock** the match is stepped with game time, so the lock clock (`h.lockTime`), the shot list, the
  VFX and your timeline stay in sync with the stutter hit-stops you add (`h.hitstop(0.06)` on a tick).
* A character is frozen while its fighter is in hit-stop (`fighter.hitstop > 0`, the victim also shakes) and while the
  opponent's super-freeze holds it. Move clips are **sampled at the rules' move time**, so animation is locked to the
  frame data, cancels included.
* `h.after(sec, fn)` and every VFX run on game time; `h.slowmo(scale, dur)` durations are real seconds.

---

## 3. The fighter content API

### 3.1 Module shape

`src/fighters/<id>/index.js` (default export, or the same names as named exports):

```js
import { design } from './design.js';            // character design (src/char README "Design format")
import { def } from './moves.js';                 // rules definition (src/game/logic README §8)
import './clips/index.js';                       // registers kael.* clips with defineClip (src/char README §5)
import { present } from './present.js';          // choreography (this README)

export default {
  id: 'kael',
  element: 'ember',          // optional: 'ember' | 'frost' | 'volt' (default: the roster's)
  design, def,
  clips: {                   // presentation slot / move id / MOVES.md slot -> clip (anything missing -> generic)
    idle: 'kael.idle', walkF: 'kael.walkF', walkB: 'kael.walkB', guard: 'kael.guard',
    light1: 'kael.ashCleave',                          // move id or slot: sampled at moveTime (1:1)
    sweep: { clip: 'kael.furnaceSweep', hit: 0.31 },   // `hit` = clip time of the first impact -> retimed to frame data
    victory: { clip: 'kael.victory', speed: 1 },
  },
  present,
};
```

Anything missing is filled in by `src/fighters/registry.js`: `design.js` / `moves.js` of the folder, else the demo
knight tinted by element and the rules sample (renamed after MOVES.md). A design that throws or a definition that does
not validate is reported once (`[ed] fighters: ...`) and replaced, so the game always runs.

### 3.2 `clips`: the state → clip map

`clips` is an object (or `({ defineClip, definePose, hasClip }) => object`, called once). Keys:

| slot | rules state | generic fallback |
|---|---|---|
| `intro` | `intro` (round intro, played once) | `game.intro` (blade planted, wrenched up into guard) |
| `idle`, `recovery` | `idle`, `recovery`; optional one-shots over the idle: `idleFidget` (+ `idleFidget2` …) after a few still seconds, `turn` when the facing flips, `walkStopF` / `walkStopB` | `demo.idle` (`game.fidget1/2`, `game.turn` for fallback fighters) |
| `walkF`, `walkB` | `walk` (`walkDir` ±1); playback speed = walk speed / clip root-motion speed (0.7–1.55×) | `game.walkF@<speed>` / `game.walkB@<speed>`: the generic step-drag walk re-authored per fighter for its `walkSpeed` / `backSpeed` (cadence up to 1.4×, the stride takes the rest), so it plays at 1× with planted feet |
| `dash`, `backstep`, `dodge`, `roll` | movement states; clip time = state progress × clip length | `game.dash/backstep/dodge` |
| `guard` | `guard`, `blockstun` (+ a flinch impulse per blocked hit, scaled by the weight of the blow; a `guardHit` / `guardHitHeavy` one-shot when the fighter has one) | `demo.guard` |
| `guardBreak` | `guardbreak` (progress-driven) | `game.guardbreak` |
| `hitLight`, `hitHeavy` | `hitstun` light / heavy; restarted on every hit with no fade, starting on the impact pose (that frame is held through the hit-stop). Variants by contact height and side: `hitLightHigh` / `Mid` / `Low` / `Back`, `hitHeavyBack` | `game.hitLight` (+ variants), `game.hitHeavy` (+ `Back`) |
| `crumple` | `hitstun` crumple (progress-driven) | `game.crumple` |
| `launched`, `fall` | `launched` rising (`vy > 0.6`) / falling, also the KO flight; `launchedProne` / `fallProne` after a blow from behind | `game.airRise`, `game.airFall` (+ `Prone`) |
| `down`, `getup`, `tech` | `knockdown` (lying), `getup` (progress-driven; `tech` when the fall was teched); `downProne` / `getupProne` / `techProne` face-down | `game.down`, `game.getup`, `game.tech` (+ `Prone`) |
| `ko` | `ko` (lying; `koProne` face-down) | `game.koDown`, `game.koProne` |
| `locked` | cinematic victim (default lock choreography) | `game.locked` |
| `victory`, `defeat` | round end; `victory`, `victory2` … `victory6`: one per round at random | `game.victory`, `game.victory2`, `game.defeat` |
| `<move id>` or `<slot>` | `attack`: the move clip, `setClipTime(map(moveTime))` | a demo clip chosen from the move data (light chain → `demo.combo1/2/3`, launch → `demo.combo2`, multi-hit / armour → `demo.combo3`, knockdown / cinematic / targeted projectile → `demo.slam`, counter stance → `demo.guard`, no hits → `game.dash`), always retimed |

Entry forms: `'clip.name'`, or `{ clip, hit, speed, fade }`. **Retiming:** with `hit` (or for fallbacks: the clip's
first `hit` / `impact` event) the clip is warped piecewise so `[0, startup] → [0, hit]` and `[startup, duration] →
[hit, clip end]`; the impact frame always lands on the first active frame, whatever the move data says. Without
`hit`, a fighter's clip plays 1:1 against the move time (`× speed`). Move ids resolve before slots (`light1` matches
the move whose `meta.slot` or command is `light1`). Clip `step` events play footsteps.

**Variant slots** (src/fighters/MOTION.md §4 has the full table and the authoring rules): a state entry may be an array
of clips; a registered clip named `<fighter id>.<slot>` is used without a map entry (`kael.hitLightHigh`,
`iska.idleFidget2`); a variant slot falls back to the fighter's own clip of its parent slot (`hitLightHigh` →
`hitLight`), then to the generic variant. Variants are picked with `ctx.rng` and every clip is compiled when the actor
is created. Generic clips are re-based on the fighter's own `<id>.stance` pose when its library defines it
(`game.getup@kael` ends with the saber on the shoulder).

The fallbacks are authored for a two-handed greatsword (the off hand IKs onto the main weapon's grip). A design with a
weapon in each hand (twin blades) gets `<clip>@twin` variants of every fallback: no grip, both fists closed on their
own weapons. A fighter's own clips are used as they are.

### 3.3 `present`: choreography

```js
export const present = {
  setup({ vfx, fx, element, palette }) {},  // once at boot, before vfx.prewarm(): vfx.define('kael.groove', ...)
  ambient(h) { return [handles] },          // once per match: auras / idle particles; returned handles are killed at the end
  moves: {                                  // per move id (or MOVES.md slot)
    crescent: {
      start(h, e) {},                       // moveStart (also cancels into it)
      windup(h, e) {}, release(h, e) {},    // any timeline marker name of moves.js
      hit(h, e) {}, guard(h, e) {},         // this move's strike landed / was blocked; return false = no generic feel
      whiff(h, e) {},                       // the move completed without touching
      counter(h, e) {},                     // counter stance triggered (on the stance move)
      end(h, e) {},                         // moveEnd (e.reason: complete | cancel | interrupted | cinematic | round)
      options: { trail: false | { t: [0.2, 0.4], life, weapon: 0 | 1 | 'all', color, edge }, whoosh: false | 'swing_huge' },
    },
  },
  projectiles: {                            // per projectile `kind` (moves.js projectiles[].kind)
    ember_wave: { spawn(h, e) {}, active(h, e) {}, hit(h, e) {}, guard(h, e) {}, expire(h, e) {}, clash(h, e) {} },
  },                                        // spawn returning false = no generic projectile body
  markers: { trailOn(h, e) {} },            // marker handlers for every move of this fighter
  on: {                                     // fighter-wide hooks (return false = no generic feel)
    hit(h, e) {}, guard(h, e) {}, ko(h, e) {}, intro(h, e) {}, victory(h, e) {}, defeat(h, e) {},
    dodge(h, e) {}, perfectDodge(h, e) {}, land(h, e) {}, tech(h, e) {}, wallBounce(h, e) {}, guardBreak(h, e) {}, teleport(h, e) {},
  },
  ult: { ... },                             // §3.5
};
```

Rules of dispatch:

* Handlers receive `(h, e)`: the helper (§3.4) and the rules event payload (logic README §17), also as `h.e`;
  marker data as `h.data`.
* **Layering:** the generic feel runs after your handler **unless the handler returns `false`**. Return `false` when
  your set piece replaces the default (its own impact flower instead of the generic sparks); return nothing to add on
  top. `h.defaultFeel()` runs the default hit / guard feel explicitly.
* Handlers run after the characters updated this frame: sockets are where the pose is.
* A handler that throws is reported once (`[ed] choreography kael.crescent.release threw ...`) and the game goes on.
* Marker data hints work without any code (from `moves.js` alone):

  | hint | effect |
  |---|---|
  | `shake: 0.35`, `kickFov: -3`, `impactFrame: true`, `flash: 0.6` | camera trauma / fov punch / impact frame / element emissive flash of the fighter |
  | `afterimage: true` | a ghost of the fighter in its element palette |
  | `audio: 'name'` (or `sound`) | one-shot at the fighter; skipped when the generic layer played the same sound in the last second (`ult_start` of the super-freeze, `ult_impact` of the lock finish) |
  | `decal: 'crack' \| 'scorch …' \| 'frost' \| 'rune …' \| 'glow'` | floor decal (first word): at the weapon tip's x, `rune` under the fighter (not during a lock) |
  | `slowmo: 0.7` | 0.4 s of slow motion at that scale (not during a lock) |
  | `cam: { shot, dur, slowmo, subject }` | a vocabulary shot (`h.shots` names) anchored on the fighter, HUD kept, 0.3 s blend back; only from fight framing, not during a lock. `groundSkim` is framed 3–3.6 m off the fight line so it clears columns and spike lines |

  `decal`, `slowmo` and `cam` are set pieces: they are skipped when the fighter's choreography has a handler for that
  marker (`moves[move][marker]` or `markers[marker]`), so a hand-made camera never competes with the data cue. A `vfx`
  / `fx` string in marker data is a storyboard note and is never played automatically: presets are placed by the
  choreography (`h.fx`).
* Defaults for every move: a weapon trail from `trailOn` to `trailOff` markers (style → life: light .15, rising .18,
  overhead .2, huge / heavy .22, spin .2, thrust .12, drag .26; `glow` = none; `data.blades: 'R' | 'L' | 'both'` picks
  the weapon of a twin-blade design), else from the frame data (startup − 0.08 … last active + 0.06); a whoosh at
  `swing` / `release` (or startup − 0.06) sized by duration; a cast glow + element sound on skills.

### 3.4 The helper `h`

Everything is in the **fighter-local frame of the handler's owner**: `[f, u, s]` = forward (mirrored by facing), height
above the floor, toward the camera. Positions (`where`) accept:

| `where` | meaning |
|---|---|
| `undefined` | own chest socket |
| `[f, u, s]` | point in the owner's frame (`u` = metres above the floor) |
| `'weaponTip'`, `'weaponBase'`, `'weaponTip2'`, `'handR'`, `'chest'`, `'head'`, `'hips'`, `'footL'`, `'back'` ... | own socket (this frame) |
| `'foe.chest'`, `'foe.head'` ..., `'foe'` | the opponent's socket |
| `'contact'` | the event's contact point (`e.x`, `e.y`), slightly toward the camera |
| `'floor'`, `'foe.floor'` | the floor under the owner / the opponent |
| `{ socket: 'weaponTip', of: 'foe', offset: [f, u, s] }` | socket + local offset |
| `THREE.Vector3`, `Object3D` | world |

VFX calls take `where` or an *at object* `{ pos: where, dir: [f, u, s], scale, color, target: where }` (dir is local
and mirrored).

| member | description |
|---|---|
| `h.fx(name, where, opts)` | play a preset with facing applied; `opts.element` defaults to the fighter's. **An unknown or broken preset never throws**: it plays `opts.fallback` (default `game.burst`, an element-coloured burst) |
| `h.burst(def, where)`, `h.emitter(def, where, { follow: 'weaponTip' \| 'foe.chest' \| Object3D })` | particles (definitions: vfx README) |
| `h.spawn(kind, where, opts)` | any vfx primitive with a `pos` (`'ring' 'pillar' 'slash' 'decal' 'spikes' 'debris' 'bolt'`...), `palette` = element, `facing` / `dir` filled; a primitive that does not exist yet is a no-op |
| `h.light(where, o)`, `h.flare(where, o)`, `h.distort(where, o)` | pooled light (element core colour, 120 cd, 0.3 s by default), flare, refraction |
| `h.trail.start(o)`, `h.trail.stop()` | weapon trail on every weapon (`o.weapon: 0 \| 1 \| 'all'`, `life`, `color`, `edge`, `width`, `distort`, `motes: false`) |
| `h.afterimage(o)` | ghost copy of the owner (if the VFX module provides `afterimage`) |
| `h.glow(color?, amount, dur, fadeIn)` | sustained emissive glow of the whole character (`dur` 0 = until `h.glow(null)`); `h.flash(color, amount, dur)` one-shot |
| `h.weaponGlow(amount, dur, color?)` | the blade material glows (element core by default) |
| `h.impulse(dir, amount, who = 'foe')` | physical flinch `[f, u, s]` of the opponent (or `'self'`) |
| `h.self`, `h.foe` | views: `{ index, actor, char, sockets, fighter, facing, at(f,u,s), socket(name), play(clip, o), offset([f,u], dur, ease), impulse, flash, glow, weaponGlow, afterimage, setVisible }` (each in **its own** frame) |
| `h.play(clip, o)`, `h.foePlay(clip, o)` | clip override — **during the cinematic lock only** (elsewhere the rules state drives the clips) |
| `h.offset([f, u], dur, ease)`, `h.foeOffset(...)` | cinematic root offset from the rules position (leaps, lifting the victim); eased back to 0 when the lock ends |
| `h.cam.shake(a, o)`, `.kick(o)`, `.zoom(f, d, o)`, `.play(shots, o)`, `.stop(b)`, `.letterbox(on, d)` | camera; `play` anchors on the owner (cam README) |
| `h.shots` | the shot vocabulary (`heroPushIn crashZoom overShoulder whipPan orbitSweep impactPunchIn topDownSlam wideEstablishing faceCloseUp weaponFollow groundSkim dutchDrift`) |
| `h.audio(name, o)` | one-shot at the owner (audio README names) |
| `h.post.pulse(k, a, o)`, `.flash(c, a, o)`, `.impact(o)`, `.radial(where, a, o)`, `.chroma(a, o)` | post FX (real time) |
| `h.mood(m)`, `h.pulse(where, color, strength)` | `env.setMood` (null restores), floor pulse |
| `h.slowmo(scale, dur, o)`, `h.hitstop(sec)` | `ctx.time` slow motion (real s) / global presentation freeze |
| `h.after(sec, fn)` | `fn(h)` after `sec` game seconds (frozen by hit-stop, cancelled at a round reset); `h.e` is the event of the scheduling call |
| `h.announce(text, o)` | `ui.hud.announce` |
| `h.at(f, u, s)`, `h.socket(where)`, `h.pos(where)`, `h.dir([f,u,s])` | resolve positions / directions to world `Vector3`s |
| `h.e`, `h.data`, `h.t`, `h.move`, `h.lockTime`, `h.fighter`, `h.foeFighter`, `h.facing` | event, marker data, move time, move id, lock clock, rules state (read only) |
| `h.element`, `h.palette`, `h.color(key = 'core', k = 1)` | element and its HDR palette (`core mid tail smoke`) |
| `h.vfx`, `h.ctx`, `h.rng`, `h.THREE`, `h.Ease` | escape hatches (deterministic rng) |

### 3.5 Ultimates

```js
ult: {
  mood: { darken: 0.75, tint: 0xff5020 },         // world mood for the super-freeze (default: the roster's)
  freeze(h, e) {},                                // superFreezeStart; return false = replace the default
  shots: (h) => [...],                            // camera of the lock (array or function), anchored on the user
  blendOut: 0.7,                                  // seconds back to fight framing
  start(h, e) {},                                 // cinematicStart; return false = no default impact (flash, impact frame)
  at: [{ t: 1.25, do(h) {} }, ...],               // timed actions on the lock clock (seconds from the trigger)
  markers: { meteor(h, e) {} },                   // lock markers / tick markers by name (also routed to moves[ultId])
  tick(h, e) {},                                  // every cinematicTick (e.final on the finish); return false = no default
  end(h, e) {},                                   // cinematicEnd (e.ko: the lock killed)
  whiff(h, e) {},                                 // the ultimate missed or was blocked (no lock)
}
```

Default super-freeze: world mood, letterbox, hero push-in on the user (real clock) then a held weapon-follow shot,
the HUD ULT cut-in with the ultimate's name, `ult_start`, the `ultimate` music overlay, user glow + blade glow, a
converging charge at the weapon tip, exposure dip. Default lock (no `shots` / `at`): punch-in on the trigger, an orbit
through the ticks, crash zoom, wide finish; the attacker cuts with its chain clips on every tick and settles into idle
between them, the victim reacts; the finish (`combat.hit.crit` + `<element>.eruption`, `ult_impact`, white flash,
shake 1) throws the victim up and slams it into the floor, where it lies until the lock releases it. On `cinematicEnd`
the mood, letterbox, offsets, glows and music are restored and the camera blends back. Whiff / block: the same restore.
Every round start also returns the music to the plain battle track (a lethal lock keeps its overlay through the KO).

During the lock both characters are in **cine mode**: the rules hold them (`locked` victim, the attacker in its move)
and nothing drives their clips but you (`h.play`, `h.foePlay`, offsets). The rules place the victim `cinematic.distance`
in front of the user; at the end they release it with the finish knockback from that spot.

### 3.6 Complete example

```js
// src/fighters/kael/present.js
export const present = {
  setup({ vfx, palette }) {
    const P = palette;
    vfx.define('kael.groove', (v, at) => {
      v.burst({ ...vfx.lib.sparks, count: 30, spread: 60, color: vfx.util.heatRamp(P.core, P.mid, P.tail) }, { pos: at.pos, dir: [0, 1, 0] });
    });
  },
  ambient(h) {
    // embers dripping from the armour cracks all match long
    return [h.emitter({ ...h.vfx.lib.embers, count: 0, rate: 6 }, 'chest', { follow: 'chest' })];
  },
  moves: {
    crescent: {
      drag(h) { h.fx('kael.groove', 'floor'); h.audio('fire_ignite', { volume: 0.6 }); },
      release(h) {
        h.cam.kick({ fov: -3 });
        h.fx('ember.wave.launch', { pos: [0.9, 1.0, 0], dir: [1, 0.1, 0] });   // falls back to a burst until it exists
      },
    },
    sweep: {
      swing(h) { h.trail.start({ life: 0.3 }); h.after(0.24, (h2) => h2.trail.stop()); },
      hit(h, e) {
        h.fx('ember.hit.heavy', { pos: 'contact', dir: [1, 0.15, 0.3] });
        h.cam.shake(0.4); h.post.radial('contact', 0.35);
        return false;                                          // replaces the generic heavy-hit sparks
      },
      options: { trail: false, whoosh: 'swing_huge' },        // the swing handler owns the trail
    },
    bulwark: {
      start(h) { h.glow(h.color('mid', 0.4), 1, 0.6); },
      counter(h) { h.fx('ember.explosion', 'chest', { scale: 1.3 }); h.cam.play([h.shots.crashZoom({ dur: 0.3, subject: 'anchor' })]); },
    },
  },
  projectiles: {
    crescent: {   // projectile kind from moves.js
      spawn(h, e) {
        const wave = h.spawn('slash', [0.8, 1.1, 0], { look: 'flame', arc: [-70, 70], radius: 1.1, speed: 11, life: 0.9 });
        return false;                                          // no generic projectile body
      },
      hit(h) { h.fx('ember.flower', 'contact'); },
    },
  },
  ult: {
    mood: { darken: 0.75, tint: 0xff5020 },
    freeze(h) { h.fx('charge.gather', 'weaponTip'); },          // added to the default super-freeze
    shots: (h) => [
      h.shots.impactPunchIn({ dur: 0.4 }),
      h.shots.orbitSweep({ dur: 1.05, cut: 0.2, from: -60, to: 10, slowmo: 0.7 }),
      h.shots.topDownSlam({ dur: 0.5 }),
      h.shots.groundSkim({ dur: 1.1, slowmo: { scale: 0.3, dur: 0.6 } }),
      h.shots.crashZoom({ dur: 0.4 }),
      h.shots.wideEstablishing({ dur: 1.75, shake: { amount: 1, at: 0.05 } }),
    ],
    at: [
      { t: 0.25, do(h) { h.play('kael.ult.xcuts'); h.afterimage(); } },
      { t: 1.3, do(h) { h.play('kael.ult.hurl'); h.foeOffset([0.4, 1.8], 0.35, 'outQuad'); h.foePlay('game.airRise'); } },
      { t: 1.8, do(h) { h.offset([0.2, 2.2], 0.4, 'outCubic'); h.fx('ember.inferno', 'weaponTip'); h.mood({ darken: 0.85, tint: 0xff2000 }); } },
      { t: 2.9, do(h) { h.offset([0.4, 0], 0.18, 'inQuad'); h.foeOffset([0.5, 0], 0.18, 'inQuad'); } },
    ],
    tick(h, e) {
      if (e.final) { h.fx('ember.meteor', 'foe.floor', { scale: 1.4 }); h.pulse('foe.floor', null, 2); }
      else h.fx('ember.slash', { pos: 'foe.chest', dir: [1, -0.4, 0] });
      h.hitstop(e.hitstop || 0.06);                              // stutter (the lock runs on game time)
    },
  },
};
```

---

## 4. Generic feel (feel.js)

| event | default |
|---|---|
| clean hit | the VFX library's `combat.hit.<level>` (`combat.hit.crit` for counters / ultimates, `<element>.hit` first for skills; `game.hit` when missing) at the contact point, strength `k` by level (light .55, heavy .9, launch / crumple 1, knockdown 1.1; skill +.25, ult +.35, counter +.25, KO ≥ 1.5); victim impulse (front / back) + flash; shake .15 light / .35 heavy / .5 skill finisher (+.12–.15 counter); fov kick from heavy; chroma; radial blur from heavy; impact frame on counters, skill finishers, ultimates; `hit_slash_light/heavy`, `hit_blunt`, `hit_crit`; global hit-stop = the rule's; floor pulse from k 1.1; HUD combo |
| blocked | `combat.guard.block` (perfect: bigger glint, pitch up), `guard`, small flinch and shake |
| guard break | `combat.guard.break`, `guard_break`, shake .5, chroma, flash, 0.12 s freeze |
| counter stance triggered | `<element>.explosion` at the user, impact frame, zoom on the user, `release` + element burst sound |
| skill start | `combat.charge.gather` (0.22 s) on the weapon tip, glow, element cast sound |
| projectile | a `kind` that names a VFX preset plays it: travelling ones (`ember.wave`, `frost.shard`, `volt.javelin`) follow the rules projectile (`opts.follow`), `impact()` on its hit / clash, fizzle on lifetime; `volt.strike` is armed with `warn` = the rules delay so the bolt lands on the active frame; `volt.chain` runs along `data.length`. Other kinds: travelling (≥ 2 m/s) → generic body (glow flare, ribbon, motes, light, element slash arc) from the moment it is armed (`data.statue`: an afterimage holds the spot meanwhile); on the floor (opponent-anchored or creeping < 2 m/s: spike lines, columns) → element floor telegraph (magma crack / frost / rune) while it is armed, then the element eruption timed to the active frame (`ember.eruption` 0.14 s early for its crack lead-in, an ice-spike cluster sized by `data.size` holding `data.hold`, `volt.strike`; `data.huge` / `data.last` bigger) |
| dash / backstep / dodge / steps | `combat.dust.dash` / `combat.dust.step`, `dodge` / `step`, afterimage on dodges; perfect dodge: 0.35× slow motion, chroma, afterimage |
| land / tech / wall bounce | `combat.dust.land` (heavy on knockdowns), `land` / `body_fall`, vertical shake |
| KO | `combat.ko.burst` (real time), impact frame, then 0.22× slow motion for 1.7 s, punch-in + orbit on the victim, `announce_ko`, music duck, `K.O.` card |
| super-freeze / lock | `combat.ult.flash` behind the user, `combat.charge.gather` on the weapon; lock ticks `combat.hit.heavy`, finish `combat.hit.crit` + `<element>.eruption` |
| round | intro shots (wide establishing + orbit, shorter from round 2), `round` / `final` card, `announce_round` (+ bell), `fight` card + `announce_fight`, hero shot on the round winner, `perfect` / `draw` / `timeup` cards, winner card + `victory` music at the match end |

---

## 5. Test API — `window.__ED.game`

| member | description |
|---|---|
| `state`, `screen` | flow state (`title select vs match pause result`), UI screen |
| `roster()` | per fighter: which design / definition source is live (`kael/design.js`, `knight (tinted)`, `sample (placeholder)`) |
| `start(p1, p2, { mode = 'demo' \| 'versus' \| 'training', difficulty, seed })` | a match now (no menus) |
| `title()`, `select()`, `versus(p1, p2, diff)`, `pause()`, `resume()`, `rematch()` | flow |
| `skipIntro()` | advance (no render) until the fight phase |
| `snapshot()`, `match()`, `session()`, `events()` | rules snapshot / objects / event names seen this round |
| `forceMove(i, id)`, `moveFor(i, slot)` | start a move now (costs ignored); move id of a MOVES.md slot |
| `meters(i, { hp, fp, ult, guard })`, `place(i, x, facing)` | rules state |
| `controller(i, 'idle' \| 'ai' \| 'human', difficulty)` | swap a controller (`'human'` reads `ctx.input` player `i`: `setVirtual(action, down, i)`) |
| `round(n, [winsA, winsB])` | restart as round `n` with those wins (`round(3, [1, 1])` = final round) |
| `pose(i, clip, t)` / `pose(i, null)` | freeze fighter `i` on a clip time (clip review) |
| `prof()`, `profReset()`, `info()` | `#prof` report, renderer info |

---

## 6. Performance

Measured with `src/game/tests/profile.mjs` (headless Chromium + SwiftShader on the 4-core build container) with the
fighters' own content (designs, clips, choreography), Kael vs Iska: **fight** = 240 rendered frames of a hard-AI match,
**ult** = 420 frames through Kael's whole ultimate (super-freeze, 5.2 s lock, aftermath). Triangles (shadow pass
included), draw calls and program counts are exact; CPU milliseconds are wall-clock JS time and scale with the load of
the shared container (all groups inflate together, by ~5–10x at load average 50–90).

| tier | draw calls fight avg / peak | ult avg / peak | triangles fight avg / peak | ult avg / peak | programs before → after the ultimate |
|---|---|---|---|---|---|
| high | 42 / 51 | 47 / 60 | 365k / 445k | 442k / 592k | 49 → 49 |
| mid | 40 / 49 | 45 / 58 | 355k / 434k | 424k / 569k | 47 → 47 |
| low | 33 / 42 | 38 / 51 | 207k / 283k | 267k / 403k | 46 → 46 |

CPU, low tier, through the ultimate in the quietest window of the session: **2.2 ms JS per frame** (CHAR 1.76, GAME
0.12, VFX 0.15, CAM 0.08, UI 0.08, INPUT 0.03), 4.6 ms wall per frame including the render submit. Earlier quiet-ish
runs on high: 2.8–3.0 ms per fight frame (CHAR ~2.5). The game layer (session, actors, feel, presenter, HUD binding)
stays at 0.1–0.3 ms; the characters (animation, IK, two cloths each) are ~80 % of the JS.

Over budget: triangles on high average 365k in neutral (budget 350k) and peak at 445k (fight) / 592k (ultimate). The
peaks are afterimage ghosts: every ghost is a full copy of a character (~58k triangles, one draw per mesh, additive,
no depth write), and choreographies spawn several at once (Kael's ultimate leap, Iska's blink). The generic layer
rate-limits its own ghosts to one per fighter per 0.25 s. Under SwiftShader the ultimate costs ~300x the GPU time of
neutral fighting (fill: stacked ghosts, close-up cameras inside pillars and rings); verify on real hardware.

Hitch prevention: every clip a fighter can play is compiled when its actor is created; every program is compiled at
boot and again behind the VS splash when new characters are built (`renderer.compile` on the scene and the distortion
scene), plus one warm frame at boot (shadow programs). Verified: no program is compiled during a fight or an ultimate
(counts above, and soak.mjs renders through whole matches). No per-frame allocations in the session / actor / HUD paths
(the walk speed and the music intensity are written in place / only on change).

Memory (soak.mjs `MEMORY=1`: ten session builds across every pairing, each also rematched): geometries 35, textures 66,
programs 49, scene children 4 and JS heap 98 MB from match 2 to match 10 (no growth). A disposed session clears the
VFX (ghosts share their character's geometry).
