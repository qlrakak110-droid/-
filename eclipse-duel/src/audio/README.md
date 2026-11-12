# src/audio — procedural audio engine

Every sound in ECLIPSE DUEL is synthesised in code with WebAudio: no samples, no files, no network.

- **One-shots and loops.** Each is a layered recipe (transient + body + tail) rendered **once** in an `OfflineAudioContext`
  and mastered to a loudness target. Playback is then one `AudioBufferSourceNode`, so it is cheap on phones.
- **Music.** A small step sequencer plays instrument samples that are rendered the same way (low strings, brass, choir,
  taiko, bells, drones), with intensity layers, crossfades and an "ultimate" overlay. All of it is original.
- **Silence by default.** The engine is silent and exception-free when WebAudio is missing, before `unlock()` and in
  test mode (`#test`).

```
voice -> gain -> pan -> world bus -> slow-mo low-pass -\
                     -> ui bus ------------------------+-> sfx -> master -> glue comp -> limiter -> soft clipper -> out
                     -> reverb send -> stone-hall convolver (generated IR) -> return -/
music tracks -> layer gains -> fade -> muffle / low-pass -> music -> low shelf (-4 dB @140 Hz) -> duck -/
```

| file | role |
|---|---|
| `index.js` | `createAudio(ctx)`: context lifecycle, buses, voices, loops, music player, ducking, slow-mo, render queue |
| `kit.js` | offline synthesis toolkit (layers), mastering, hall impulse generator, K-weighted loudness |
| `sfx.js` | the sound library: every SFX recipe + its playback meta |
| `music.js` | instruments, compositions (`TRACKS`), sequencer |
| `analyze.js` | measurement and self-test used by the lab (not imported by the game) |

## Quick start

```js
import { createAudio } from './audio/index.js';
const audio = createAudio(ctx);           // ctx.audio; pre-renders in the background (not in test mode)
canvas.addEventListener('pointerdown', () => audio.unlock(), { once: true });   // also hooked automatically
audio.music('title');                     // starts as soon as the context is unlocked
```

```js
// combat: hit at the victim, positioned by the camera; spark ring 80 ms later
audio.play('hit_slash_heavy', { pos: victim.position });
audio.play('ice_shatter', { pos: victim.position, delay: 0.08, volume: 0.8 });
audio.setIntensity(clamp(1 - minHpRatio, 0.2, 1));   // drives the battle layers

// a burning weapon: loop + fade out
const burn = audio.loop('fire_loop', { volume: 0.6 });
burn.setVolume(1, 0.3);
burn.stop(0.8);
```

```js
// ultimate: super-freeze stinger, music overlay, back to battle afterwards
audio.play('ult_start');
audio.music('ultimate');                  // battle keeps playing underneath, muffled
// ... at the finisher
audio.play('ult_impact');                 // ducks the music by itself
audio.music('battle', { fade: 2 });       // removes the overlay
```

## API — `createAudio(ctx)` → `ctx.audio`

`ctx` fields used when present: `test`, `quality.tier`, `time` (slow-mo / hit-stop), `camera` (`pos` → pan),
`onUpdate` / `ORDER` (registers at `ORDER.UI`), `flags.seed`. A plain `{}` works too (no update hook).

| member | description |
|---|---|
| `unlock()` → `bool` | Creates / resumes the `AudioContext` (call from a user gesture; `pointerdown` / `keydown` / `touchend` are also hooked). `false` in test mode, without WebAudio or after `dispose()`. |
| `play(name, o)` → `handle \| null` | One-shot. Returns `{ name, stop(fade = 0.05) }`, or `null` when silent, locked, throttled or unknown. |
| `loop(name, o)` → `handle` | Looping voice: `{ name, playing, setVolume(v, fade = 0.2), setPitch(p, fade = 0.2), setPan(p), stop(fade = 0.4) }`. Always returns a handle (inert when silent). If requested before unlock, it starts on unlock. |
| `music(track, { fade = 1.5 })` | `'title' \| 'battle' \| 'ultimate' \| 'victory' \| null`. Crossfades. `'ultimate'` overlays the current track (muffled underneath, beat-aligned); any other call removes the overlay. Requested before unlock, it starts on unlock. Asking again for a finished `victory` replays it. |
| `setIntensity(x, tc = 0.5)` | Battle intensity 0..1: drums fade in over 0.1–0.5, brass / choir / violins over 0.45–0.85, horn line above 0.8. `tc` = glide time constant (s). |
| `setVolume({ master, sfx, music })` / `getVolume()` | Bus volumes 0..1 (any subset; default 1 / 1 / 0.8). |
| `duck(amount = 0.5, dur = 0.8)` | Music down by `amount` (0..1) for `dur` s, 40 ms attack, ~0.3 s release. Some sounds duck by themselves (`duck` meta). |
| `stopAll(fade = 0.2)` | Stop every voice, loop and track. |
| `list()` / `tracks()` / `info(name)` | Sound names / track names / a sound's meta (`desc`, `role`, `group`, `len`, `bus` ...). |
| `define(name, meta, recipe)` | Add or replace a sound at runtime (see "Adding a sound"). |
| `prewarm()` → `Promise` | Render every variant + instrument now (starts automatically 0.5 s after creation outside test mode). |
| `render(name, { variant = 0 })` → `Promise<{ buffer, gain, rawPeak, rawLoud } \| null>` | The mastered asset (`gain` = dB applied by mastering). Works in test mode. |
| `renderScene({ seconds = 8, sr = 48000, music, intensity, events })` → `Promise<AudioBuffer \| null>` | Offline render through the full mix chain: `music` = a track or `['battle', 'ultimate']`, `events` = `[[time, name, { volume, pitch, pan }], ...]` (no voice limits). |
| `stats()` | `{ state, voices, maxVoices, loops, buffers, bytes, musicBytes, pending, music: { base, overlay, intensity }, slow, duck }` |
| `state` | `'unavailable' \| 'test' \| 'locked' \| 'starting' \| 'running' \| 'suspended' \| 'disposed'` |
| `context` / `intensity` | The live `AudioContext` (null until unlocked) / the current intensity. |
| `dispose()` | Stops everything and closes the context; removes listeners, timers and the update hook. |

### `play` / `loop` options

| option | default | unit | meaning |
|---|---|---|---|
| `volume` | 1 | linear | multiplied with the per-play random variation (`volVar`) |
| `pitch` | 1 | playback rate | 2 = an octave up (tape-style: duration scales too); `pitchVar` is added on top |
| `pan` | 0 | -1..1 | explicit stereo position |
| `pos` | — | world `Vector3` or `[x, y, z]` | pan from the camera projection (used when `pan` is not given) |
| `delay` | 0 | s, audio clock | sample-accurate scheduling (real time: not slowed by slow-mo or hit-stop) |
| `reverb` | 1 | multiplier | scales the sound's hall send (`verb`) |
| `noSlowmo` | false | — | `play` only: skip the slow-mo pitch drop for this world sound |
| `maxLate` | per sound | s | `play` only: drop the voice if its first render is ready later than this |
| `fade` | 0.3 | s | `loop` only: fade-in time |

### Behaviour

- **Unlock.** `play()` is a no-op (returns `null`) until the context is running; music and loops requested earlier
  start on unlock. Hidden tabs suspend the context; it resumes on return.
- **Voices.** There is a global cap per tier (`20 / 28 / 40` for low / mid / high). Beyond it the engine steals the
  lowest-`prio`, oldest voice, or drops the new one if that has the lowest priority. Each name has a `poly` cap (the
  oldest copy fades out in 30 ms).
- **Spam protection.** A repeat of the same name within `throttle` seconds is ignored. Copies of one sound that start
  within 120 ms of each other are attenuated (`1 / (1 + 0.35 n)`). The output stage is a glue compressor, then a
  limiter (−2 dB, 20:1, 1 ms), then a soft clipper with a hard ceiling of 0.965. It cannot clip: 30 heavy one-shots
  inside 120 ms over full battle music peak at 0.964 with no voice limiting.
- **Variation.** Several sounds pre-render 2–6 takes (different grain / jitter seeds). Takes are chosen at random,
  never the same twice in a row, with ± `pitchVar` semitones and ± `volVar` dB per play.
- **Slow motion.** This reads `ctx.time.scale` (hit-stop is ignored). The `world` bus is low-passed (`18 kHz · s^1.3`,
  ≥ 900 Hz), the hall return grows by up to +70 %, and new world one-shots play at `rate · s^0.35` (s ≥ 0.25). The
  `ui` bus (UI, announcer, ultimate start, slow-mo whooshes) is unaffected.
- **Determinism.** No `Math.random()`. Recipes use per-sound seeds (`hashName(name) + variant`). Per-play variation
  uses the engine's own `makeRng` (seeded from `flags.seed`), so it never consumes `ctx.rng`. In test mode nothing
  plays, so audio cannot change a capture.
- **Rendering.** A serial queue renders one sound at a time and yields between renders. A sound needed now jumps the
  queue (`play` before its buffer exists starts it when ready, unless that is more than `maxLate` late). A full
  prewarm takes about 3–4 s of background wall time. Most assets cost a few milliseconds of main-thread JS; the
  worst are about 20–50 ms (measured with `prewarmCost`). To get there, the hot loops (grains, noise, impulse) use
  recurrences, and automation curves are sampled at 400 points/s.
- **Memory (all assets rendered).**

  | tier | SFX rate | music rate | channels | takes | memory |
  |---|---|---|---|---|---|
  | low | 26 kHz | 22 kHz | mono | ≤ 2 | ~12 MB |
  | mid | 40 kHz | 32 kHz | stereo | ≤ 3 | ~25 MB |
  | high | 48 kHz | 48 kHz | stereo | ≤ 4 | ~29 MB |

  Mastering trims tails below −72 dBFS.

## Sound list

`level` = loudness target in dB (K-weighted, loudest 100 ms). `takes` = pre-rendered variants. `bus ui` = not affected
by slow-mo. Aliases: `whoosh_light / whoosh_heavy / whoosh_huge` → `swing_*`.

| name | group | role | len s | level | ch | takes | bus | description |
|---|---|---|---|---|---|---|---|---|
| `swing_light` | weapon | whoosh | 0.42 | -20 | st | 4 | world | quick blade whoosh: moving band-pass air, thin blade sing, doppler drop |
| `swing_heavy` | weapon | whoosh | 0.62 | -17 | st | 3 | world | weighty arc: two moving noise bands, low "vwomp" tone bending down through the pass, sub air push |
| `swing_huge` | weapon | whoosh | 1.05 | -14 | st | 2 | world | greatsword-scale arc: rotor flutter, roaring band noise, doppler-dropping drone, sub pressure wave |
| `hit_slash_light` | combat | hit | 0.5 | -14 | mono | 4 | world | clean cut: hard click, bright slice, short steel ring, flesh body, small sub knock |
| `hit_slash_heavy` | combat | hit | 0.95 | -10 | mono | 3 | world | heavy cleave: click + driven crack, bending steel ring, chunky body, saturated sub drop, sizzle tail |
| `hit_blunt` | combat | hit | 0.75 | -11 | mono | 3 | world | dull bone-and-armour impact: crunch grains, saturated low body, double thud with sub |
| `hit_crit` | combat | hit | 1.7 | -8 | mono | 1 | world | critical / counter hit: double transient, long bending ring + shimmer, deep sub drop, boom tail, spark glitter |
| `guard` | combat | hit | 0.85 | -13 | mono | 3 | world | blocked strike: metal-on-metal clang (plate partials with strike bend), scrape, short thud, sparks |
| `guard_break` | combat | hit | 1.5 | -9 | st | 1 | world | guard shattered: crack, low clang, glassy-metal shatter cloud, deflating energy sweep, sub, tinkle tail |
| `dodge` | move | whoosh | 0.42 | -21 | st | 3 | world | evasive dash: airy high whoosh plus cloth flap flutter, crossing the stereo field |
| `step` | move | foley | 0.22 | -26 | mono | 6 | world | armoured footstep on stone: low heel thud, grit scuff, faint armour jingle |
| `land` | move | foley | 0.65 | -19 | mono | 2 | world | landing from a jump: heavy thud with sub, dust and grit spray, armour rattle |
| `body_fall` | move | foley | 1.1 | -15 | mono | 1 | world | knocked-down body: torso thud + limb/armour second hit, scattered metal clatter, dust slide |
| `fire_ignite` | fire | element | 1 | -15 | mono | 1 | world | flame catching: soft gas inhale, pop, whoomph swelling through an opening filter (peak ~0.1 s), roar, crackles |
| `fire_burst` | fire | hit | 1.5 | -10 | mono | 1 | world | fireball detonation: driven transient, big whoomph (LP sweep), mid + sub thump, fluttering roar, dense-to-sparse crackle |
| `fire_roar` | fire | element | 2.4 | -12 | mono | 1 | world | sustained pillar of fire: wandering low-pass roar with turbulence, low rumble, hiss, crackle throughout |
| `fire_loop` | fire | loop | 3 loop | -22 | st | 1 | world | seamless burning bed: breathing low roar, mid flutter, steady crackle and pops |
| `explosion` | fire | big | 3.3 | -7 | st | 1 | world | big blast: driven snap, falling low-pass blast, saturated sub drop, debris rain, long rolling rumble |
| `ice_form` | ice | element | 1.25 | -16 | mono | 1 | world | crystal growth: creaking micro-cracks, rising glassy pings, inharmonic shimmer, then a glass "lock" tink |
| `ice_shatter` | ice | hit | 1.7 | -10 | st | 1 | world | crystal shattering: crack transient, thump, glass body partials, dense shard cloud, long tinkle tail |
| `ice_crack` | ice | element | 0.7 | -15 | mono | 3 | world | ice splitting: a run of sharp crack transients with resonant pings, a pulsed creak, small sub |
| `frost_wind` | ice | loop | 3 loop | -24 | st | 1 | world | seamless icy wind: wandering band of air, thin whistle, breathing hiss, sparse glitter |
| `volt_zap` | volt | element | 0.5 | -15 | mono | 3 | world | electric zap: snap, jittering driven buzz, gated "tzzt" hiss, spark crackle |
| `volt_strike` | volt | big | 2.7 | -8 | st | 1 | world | lightning strike: razor snap, ripping gated crackle, boom, rolling thunder tail panned wide |
| `volt_charge` | volt | riser | 1.45 | -16 | mono | 1 | world | electric charge-up: rising driven buzz through an opening band, accelerating whine, thickening sparks, end spark |
| `volt_loop` | volt | loop | 2 loop | -23 | st | 1 | world | seamless live-current hum: driven mains buzz, crackle, gated sizzle bursts, occasional arc zaps |
| `charge_up` | magic | riser | 1.7 | -15 | mono | 1 | world | energy riser: detuned saws and filtered noise climbing two octaves, accelerating shimmer tremolo, sub swell |
| `release` | magic | hit | 1.1 | -11 | mono | 1 | world | energy release: punchy thoom, down-sweeping driven zap, outward air burst, spark glitter |
| `shockwave` | magic | big | 1.9 | -10 | st | 1 | world | expanding shockwave: sub whump, collapsing pressure blast, twin doppler whooshes flying out to both sides, rumble |
| `magic_cast` | magic | magic | 1.4 | -16 | mono | 1 | world | spell cast: rising arpeggio of bell sparkles (D minor), chorused shimmer pad, breathy air, soft low swell |
| `rune` | magic | loop | 2 loop | -24 | st | 1 | world | seamless rune-circle hum: beating low fifths pulsing at 0.5 Hz, faint vowel formant, glassy overtones |
| `ult_start` | ult | riser | 2.3 | -11 | st | 1 | ui | ultimate super-freeze: dark gong hit, true reversed hall swell + riser peaking at 0.85 s, shimmer tail |
| `ult_impact` | ult | big | 4.4 | -6 | st | 1 | world | ultimate finisher: driven snap + crack, steel ring, collapsing blast, huge 78->20 Hz sub drop, twin shock whooshes, debris, gong, rumble |
| `slowmo_in` | time | transition | 1.5 | -15 | mono | 1 | ui | time slows: air swell that sinks through a closing filter, tape-stop tone, deep sub boom |
| `slowmo_out` | time | transition | 0.95 | -17 | mono | 1 | ui | time snaps back: tape-start tone rising through an opening filter, accelerating air swell |
| `ui_move` | ui | ui | 0.12 | -28 | mono | 1 | ui | cursor tick: soft sine blip with a faint octave and click |
| `ui_select` | ui | ui | 0.55 | -24 | mono | 1 | ui | confirm: rising two-note chime (D6 -> A6) over a soft low tap |
| `ui_back` | ui | ui | 0.28 | -27 | mono | 1 | ui | cancel: falling two-note blip (A5 -> E5) |
| `announce_round` | announce | stinger | 3 | -9 | st | 1 | ui | ROUND: taiko hit under a D-minor brass/string stab, crash, bell toll on D5, sub |
| `announce_fight` | announce | stinger | 2.6 | -8 | st | 1 | ui | FIGHT: pickup drum + upward string rip into a driven brass blat on D, big taiko, crash, sub boom |
| `announce_ko` | announce | stinger | 3.8 | -7 | st | 1 | ui | K.O.: massive sub impact, taiko, dissonant brass cluster sagging down a minor third, low bell toll, dark choir decay |
| `bell` | announce | stinger | 4.6 | -12 | mono | 1 | ui | great bronze bell (G3 strike): hum / prime / tierce / quint / nominal partials beating, 4 s decay |

Timing notes for the choreography: `ult_start` peaks at **0.85 s** (the cut), so `delay` it if the leap lands later.
`announce_fight`'s main hit lands at **0.11 s** after a pickup. `volt_charge` ends with a spark at 1.22 s and
`charge_up` peaks at 1.55 s; both hand over to `release` / `volt_strike`.

## Music

| track | tempo / key | content |
|---|---|---|
| `title` | 54 BPM, D minor, 8-bar loop | dark choir chords Dm(add9) – Bbmaj7 – Gm(add9) – Asus4→A over low strings, a wind bed, a soft heartbeat drum, a lone bell motif |
| `battle` | 140 BPM, D minor (Phrygian bII in the B section), 16-bar loop | **base:** galloping low-string ostinato (3+3+2 accents) doubled by violas, contrabass pedal, downbeat taiko, shime 8ths. **drums** (0.1→0.5): taiko groove, toms, rim, metal ticks, fills. **lift** (0.45→0.85): brass swells, violin figure, choir, cymbals / reverse swells, horn line in the B section above 0.8 |
| `ultimate` | 140 BPM overlay | D/Eb cluster drone, heartbeat pulse (lub-dub, 70 per minute), tremolo string cluster rising a whole tone every 2 bars, cymbal swells, dissonant low brass. The battle track keeps playing underneath, low-passed at 1.6 kHz and at 70 % level, and the overlay starts on its next beat |
| `victory` | 84 BPM, 4 bars, plays once | Bb – C – Asus4 cadence with taiko roll, resolving to D major (Picardy third) with choir, crash and three bell tolls |

Measured through the mix chain (K-weighted 100 ms max) for an 8 s render: title ≈ −18, battle ≈ −24 / −20 / −19.5 at
intensity 0 / 0.5 / 1, battle + ultimate ≈ −18.6, victory ≈ −17. A heavy hit is about −12.8 as heard, so the music
sits about 6–7 dB under the combat.

## Adding a sound

```js
import { defineSound } from './audio/sfx.js';      // or audio.define(name, meta, recipe) at runtime

defineSound('spear_spin', {
  group: 'weapon', role: 'whoosh', len: 0.8, level: -17, channels: 2, variants: 2, poly: 2, throttle: 0.08,
  pitchVar: 1, verb: 0.12, desc: 'spinning spear: fluttering whoosh with a whistle',
}, (k) => {
  k.whoosh({ len: 0.75, peak: 0.5, fLo: 400, fHi: 2200, q: 1.2, flutter: { rate: [12, 28], depth: 0.6 }, pan: [-0.5, 0.5] });
  k.hiss({ len: 0.6, f: [[0, 1800], [0.3, 2600], [0.6, 1500]], q: 10, env: [[0, 0], [0.3, 1], [0.6, 0]], gain: 0.2 });
});
```

Build every sound as **transient + body + tail**. Keep sub layers at or below the body (phone speakers only reproduce
what is above about 200 Hz; the drive on `thump` adds the harmonics that carry it). Give one-shots a tail that decays
inside `len`. Then run the report (below): the new sound must come out with no flags.

**Meta fields** (defaults in `sfx.js` `BASE`):

| field | default | meaning |
|---|---|---|
| `len` | 1 | render length (s); tails below −72 dBFS are trimmed |
| `level` | −14 | loudness target, dB (K-weighted, loudest 100 ms) |
| `clip` | 1 | allowed peak overshoot folded back by a soft clipper (1.5–2 = denser, punchier hits) |
| `channels` | 1 | 2 for sounds whose stereo motion matters (pan sweeps, wide debris); low tier renders mono anyway |
| `variants` | 1 | pre-rendered takes (capped per tier) |
| `poly` / `throttle` | 3 / 0.03 s | per-name voice cap / minimum retrigger interval |
| `pitchVar` / `volVar` / `panVar` | 0.5 st / 1 dB / 0 | random variation per play (±) |
| `verb` | 0.15 | hall reverb send |
| `bus` | `'world'` | `'ui'` = untouched by slow-mo |
| `prio` | 5 | 0..10 voice-steal priority |
| `loop` | false | `true` = render a seamless loop (0.12 s crossfaded) |
| `duck` | null | `{ amount, dur }` music duck on play |
| `maxLate` | 0.12 | drop if the first render arrives later than this (s) |
| `role` / `group` / `desc` | — | measurement class (`analyze.js` `ROLES`) / lab grouping / one-liner |

**Kit layers** (all take `at` = start s, `gain`, `pan`). A *spec* is a number, a function `t => value`, or points
`[[t, v, ease?], ...]`; frequency specs interpolate geometrically.

| layer | key options |
|---|---|
| `k.click({ f, type, d })` | broadband transient, `d` = decay (s) |
| `k.thump({ f0, f1, drop, len, drive })` | sine kick: pitch falls `f0 → f1` (time constant `drop / 3`), decays to −60 dB at `len`, tanh `drive` |
| `k.hiss({ len, color, stereo, type, f, q, post, env, drive, am })` | filtered noise (`white / pink / brown`), level-compensated for bandwidth, so `gain: 1` is about 0.35 RMS |
| `k.modal({ f, partials: [[ratio, amp, decay]], bend, bendTime, beat })` | ringing partials; `bend` starts sharp (semitones); `beat` adds detuned doublets |
| `k.grains({ len, times \| count + dist / tau, kind, f, decay, amp, pow, spread, lp, filter })` | JS-built grain cloud: `'ping' \| 'glass' \| 'noise'`; `k.poisson(len, rate)` makes timed events |
| `k.whoosh({ len, peak, sharp, fLo, fHi, q, doppler, flutter: { rate: [a, b], depth }, tone, sub, air, pan: [from, to] })` | speed-driven band, amplitude, doppler drop, rotor flutter, blade tone, sub push, air; pan follows the blade |
| `k.rumble({ len, f, env, rate, depth })` | slow-modulated low noise |
| `k.saws({ f, voices, spread, type, filter, env, drive, vibrato, am })` | detuned oscillator stack |
| `k.bell({ f, decay, bright })` / `k.taiko({ f, len })` | bronze bell / big drum |
| `k.formant(input, [[f, gain, q]])` | vowel filter bank |
| `await k.sub(len, ch, recipe)` + `k.reverse(buf)` + `k.play(buf, o)` | nested render (e.g. a true reverse swell); `k.verb(wet, s)` adds the hall inside it |
| `k.env(spec)` / `k.am(spec)` / `k.filter(type, f, q)` / `k.drive(a)` / `k.pan(p)` / `k.chain(...)` / `k.send(node, gain, pan)` | building blocks |
| `k.fast(fn, res)` | mark a function spec that moves faster than 400 points/s can follow (e.g. an 85 Hz gate at `res` 2000) |

## Lab and measurement

```
node tools/build.mjs audio                                                      # build/audio.html: audition everything
node tools/shot.mjs audio --eval "__ED.lab.play('report').then(r => r.table)"   # measured table (below)
node tools/shot.mjs audio --eval "__ED.lab.play('selftest')"                    # API safety checks
node tools/shot.mjs audio --eval "__ED.lab.play('prewarmCost', 'low')"          # main-thread cost per asset
node tools/shot.mjs audio --do "__ED.lab.play('sheet')" --size 1800x1300 --out shots/audio/sheet         # SFX spectrograms
node tools/shot.mjs audio --do "__ED.lab.play('musicSheet')" --size 1800x1300 --out shots/audio/music    # music spectrograms
```

`report` renders every sound (as the engine stores it) and 8 s of each track through the mix chain. For each it
gives duration, audible length, peak, RMS, K-weighted loudness, attack time, spectral centroid and low / high energy
share. It flags silence (peak < 0.02), clipping (> 0.99), DC, NaN, wrong length for the role, slow attacks or thin low
end on impacts, dull whooshes, cut tails and loop seams. It also checks loudness order (impacts > whooshes > UI), the
as-heard balance through the chain, a 30-hit stress mix, and asset memory with everything rendered. `selftest` covers
test mode, missing WebAudio, play-before-unlock, throttling, per-name polyphony, the voice cap, loops, music and
dispose.
