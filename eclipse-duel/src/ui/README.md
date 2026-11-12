# src/ui — menus, HUD, touch controls (`ctx.ui`)

DOM UI inside `#ui`: title, character select, versus splash, in-fight HUD, pause, move list, result, and the touch pad.
Original dark-fantasy look: deep ink panels with generated grain, engraved gold-and-bone hairlines, element accents
(ember `#ff6a2b`, frost `#7fd4ff`, volt `#b48cff`), serif display type for names and titles, a clean sans for data.
The recurring motif is the eclipse itself: the logo mark, the timer medallion, the ULT orb's corona and the round
announcement are all a black sun inside a ray corona. Korean first with short English subtitles. Icons are inline SVG
(`icons.js`); no fonts, images or network.

```js
import { createInput } from './input/index.js';
import { createUI } from './ui/index.js';
createInput(ctx);                 // optional peer: without it the UI is mouse / touch only
const ui = createUI(ctx);         // also stored on ctx.ui
```

`createUI(ctx, opts?)` — `opts.touch`: force the touch pad on / off (default: `(pointer: coarse)` or `ctx.quality.mobile`).
The CSS (`ui.css`) is injected once as a `<style id="ed-ui-css">`. The UI registers its update at `ctx.ORDER.UI`.

## Layout, scale, stage

- **`#stage` belongs to the UI.** Full screen, except in portrait with the touch pad *while the fight is on screen*
  (`hud`, `pause`, `movelist` opened from pause): then the stage is a 16:10 strip at the top
  (`min(width × 0.625, height × 0.5)`, below the top safe area), the HUD's bars sit in a deck right under it and the
  pad fills the rest. Menus keep the full-screen backdrop. The canvas follows through the core's ResizeObserver
  (one resize when a fight starts / ends on a portrait phone). Set via `html.ed-pad-portrait` + `--ed-stage-h`.
- **Scale unit `--k`** (also `ui.k`) = one design pixel of the 1280×720 layout: `min(w/1280, h/720)` on desktop
  (0.62–1.7), `min(w/1080, h/540)` with the touch pad (phones are held close), `w/600` in portrait. Small text never
  drops below 10–11 px.
- **Layout classes** on `.ed-ui`: `is-touch`, `is-portrait`, `is-pad-portrait`, `is-short` (landscape, h < 520),
  `is-narrow` (w < 600), `dev-touch` / `dev-gamepad` (last device), `is-test` (CSS transitions off).
- **Safe areas** come from `env(safe-area-inset-*)` (read once per resize by a probe element for the pad layout).
- Tap targets are ≥ 44 px (menu rows 48+, segmented options 44, pad buttons 49–88).
- Stacking inside `.ed-ui`: pad (1) < HUD (2, pointer-events none except the touch pause button) < screens (3). A
  screen that is fading out stops taking pointer events at once, so a tap right after a screen change reaches the pad.
- Verified from 360×740 portrait to 1920×1080, plus 1024×768, 800×360 and 844×390 landscape phones.

## Screens — `ui.show(screen, data) -> ui`

`ui.screen` holds the current one; the `'screen'` event fires `(screen, prev)`. The previous screen fades out
(0.16 s). Menus are navigable with `ctx.input` (directions = spatial focus move, `confirm`, `back`; a focused value
control takes left / right) and by mouse / touch (hover focuses, click / tap activates). Fighters may be passed as
roster objects or ids (resolved against the last roster given to `select`, default `DEFAULT_ROSTER`). After a screen
change the rest of that frame's input is ignored (Esc is both `pause` and `back`).

| screen | data | notes |
|---|---|---|
| `'title'` | `{ quality? }` | logo lockup, "press any button / tap", quality toggle. Any face button, `confirm` or a tap on the backdrop emits `start` |
| `'select'` | `{ roster, p1?, cpu?, difficulty?, step? }` | three cards + random, detail panel (stats, skills, ULT), CPU difficulty, begin. Flow: P1 pick → CPU pick (or random) → difficulty → begin. `back` steps back; on the first step emits `back('select')` |
| `'vs'` | `{ p1, p2, difficulty?, arena?, arenaEn?, duration = 3.2 }` | versus splash (diagonal split; top / bottom in portrait). Emits `vsDone` once, after `duration` s, or on `confirm` / `pause` after 0.8 s |
| `'hud'` | `{ p1?, p2?, roundsToWin? }` | shows the HUD (calls `hud.setup(data)` when fighters are given; `hud.reset()` unless coming back from pause / move list) |
| `'pause'` | `{ p1, p2 }` or `{ fighters: [a, b] }`, `quality?` | over the dimmed HUD: resume, move list, quality, quit (two-step confirm). `back` / `pause` emit `resume` |
| `'movelist'` | `{ fighters?, index = 0, fromPause? }` | per-fighter tabs; keyboard keycaps and touch glyphs per move; scrolls with up / down. `back` returns to pause when `fromPause`, else emits `back('movelist')` |
| `'result'` | `{ winner: 0 \| 1 \| -1, p1, p2, score: [a, b], rounds: [{ winner, how: 'ko' \| 'time' \| 'perfect' \| 'draw' }], stats?: { p1: { maxCombo, damage, ults, hpLeft } } }` | victory / defeat / draw, score, per-round chips, stats; rematch / select / title |
| `'none'` | — | hides everything |

## Events — `ui.on(name, fn) -> off`

| event | args | when |
|---|---|---|
| `start` | — | title confirmed |
| `pick` | `{ p1: id, cpu: id, difficulty: 'easy' \| 'normal' \| 'hard' \| 'nightmare', random: bool }` | select finished (`random`: the CPU came from the random card; already resolved to an id) |
| `vsDone` | — | versus splash finished |
| `pause` | — | player asked to pause (Esc / Start on the HUD, or the touch pause button). The UI does **not** open the pause screen itself: the game freezes time and calls `ui.show('pause', ...)` |
| `resume` | — | pause closed |
| `quality` | `'low' \| 'mid' \| 'high'` | quality toggle changed (title or pause) |
| `toTitle` | — | quit confirmed (pause) or "title" (result) |
| `rematch` | — | result |
| `select` | — | result → character select |
| `back` | `'select' \| 'movelist'` | back out of a screen that has no parent of its own |
| `screen` | `(screen, prev)` | after every `show` |
| `hud:ultReady` | `(side, full)` | a ULT gauge ignited / was spent |
| `hud:skills`, `hud:cinematic` | `(side, list)`, `(on)` | mirrors of the HUD calls (for other listeners) |

UI sounds go through `ctx.audio.play('ui_move' | 'ui_select' | 'ui_back')` when audio exists; the first gesture
calls `ctx.audio.unlock()`.

## HUD — `ui.hud`

All per-frame calls compare against cached values and only write what changed; bars, sweeps and gauges move by
`transform` (no layout), text is written only when the shown value changes. 600 `set` + `skills` + `combo` calls with
changing values add no DOM nodes and cost ~0.1 ms each in the test harness (`tests/interaction.mjs`).

```js
ui.hud.setup({ p1: rosterEntry, p2: rosterEntry, roundsToWin: 2 });     // names, titles, elements, skill + ULT icons, weapon
ui.hud.set({ time, roundsToWin?, p1: { name?, hp, hpMax, fp, fpMax, ult, ultMax = 100, rounds, element, title? }, p2: {...} });
ui.hud.skills(side, [{ id, name, key?, cd: 0..1, ready?, cost, icon }]);
ui.hud.combo(side, hits, damage);
ui.hud.announce(text, { sub, style, duration, round, side, element, keep, kicker });
ui.hud.cinematic(on);
```

| call | details |
|---|---|
| `setup(o)` | static info once per match. Fighter = roster entry (`nameEn` big serif + `name` Korean + `title · titleEn`). Builds skill slots from `moves` (`skillsOf(f)` is exposed); the ULT orb (and the touch ULT button for P1) shows the icon of the `ult` move; `weaponArt` is used by the ULT cut-in |
| `set(o)` | every frame. **time**: seconds left, shown in the eclipse medallion (black disc in a slowly turning corona; `null` / `Infinity` shows ∞); ≤ 10 s the corona burns red, quickens and the number pulses each second. **hp**: forged bar (dark rim, bevelled gold frame darkening toward the outer end, recessed well, hatched fill) anchored at the timer, with a white-hot leading edge in the fighter's element colour; damage holds a red ghost for 0.55 s then drains, flashes the lost segment white and jolts the bar; < 25 % the fill and frame turn blood red and the fill throbs. **fp**: element bar with quarter ticks + value. **ult**: ring gauge in the desktop orb / thin bar on touch; reaching full **ignites** it (white core flash, two shock rings, a horizontal flare, the corona snapping open, the "궁극기 ULT READY" label slamming in), then it breathes (glow + a wide element aura in the corner) with a turning corona until spent. **rounds**: won-round pips (pop when gained) |
| `skills(side, list)` | up to 3 slots. `cd` 0..1 = remaining cooldown fraction (clockwise sweep with a gold hand). `ready` defaults to `cd <= 0 && fp >= cost`; becoming ready fires a burst, ready slots breathe. `cost` tag turns red when FP is short. `key` overrides the hint (default from `input.keyLabel`; hidden for the CPU side unless `input.mode === 'versus'`). `icon` = an icon name (below) |
| `combo(side, hits, damage)` | `side` = attacker. Shows at `hits >= 2`, punches (scale + tilt + white flash) on every increase, fades 2.6 s after the last update or when `hits < 2` |
| `announce(text, o)` | see below; returns an id |
| `clearAnnounce()` | remove announcements |
| `cinematic(on)` | slides the top bar up and the docks down (0.38 s), dims the touch pad; announcements stay |
| `hints(on)` | control strip (keyboard / gamepad labels follow the last device; hidden on touch) |
| `reset()` | between rounds: clears ghosts, combos, announcements |
| `cine` | current cinematic blend 0..1 |

### Announcer

`text` is free text or a preset: `'round'` (`o.round`), `'final'`, `'fight'`, `'ko'`, `'perfect'`, `'timeup'`, `'draw'`
(`'ROUND 2'`, `'K.O.'`, `'TIME UP'` ... are recognised too). `o.sub` / `o.style` override the preset's. Each card is
built from layers (band, hairlines, emblem, shock ring, flare, blast, text, echo) driven by one tween; a new card
replaces the current one unless `keep` (an `ult` cut-in survives others).

| style | composition | default duration |
|---|---|---|
| `round` | the eclipse emblem rises and turns with the round number in its black disc, a ring flash and a flare; "라운드" on a band beneath, "ROUND n". `final`: red corona, "최종 라운드 / FINAL ROUND" (number shown when `o.round` is given) | 1.6 s |
| `fight` | "결투" slams in from 2.6× with a white blast, a shock ring, a horizontal flare, a short echo and a jolt; "FIGHT" | 1.0 s |
| `ko` | blood band; "K.O." slams in, a white-red slash cuts it along a rising line and the two halves part along the cut; red ring, flare and echo; "격파" | 2.3 s |
| `perfect` | gold "완벽" over a large faint emblem, ring and flare, a shine pass | 2.1 s |
| `timeup` (also `draw`) | cold steel band; the line drops in and lands | 1.8 s |
| `banner`, `win` | gold band; the line drops in (`win` uses the display serif) | 1.6 s / 2.4 s |
| `ult` | cut-in for `o.side`: an element-lit slanted band sweeps across from that side carrying the fighter's weapon silhouette; kicker "◆ 궁극기 · ULTIMATE — NAME" (`o.kicker` overrides), the ultimate's name slams in, English sub, element flare | 1.9 s |

Layout: desktop HUD has names + HP + pips + timer on top and the ULT orb, skills and FP docked in the bottom corners.
Touch landscape: compact FP / ULT bars under the HP bars, a pause button under the timer, no skill slots (the pad
shows them). Touch portrait: the stage stays clean (only the combo, announcements and a pause button at its top
right); names, HP bars, timer, pips and the FP / ULT row form a deck under it.

## Touch pad — `ui.touch`

| call | meaning |
|---|---|
| `ui.touch.setVisible(b)` | enable the pad (shown while the HUD screen is up). Landscape: overlay on the stage. Portrait: stage on top, pad below |
| `ui.touch.visible` | current state |
| `ui.touch.el` | root element |

- **Stick** (left 42 % of the pad area): floats to where the thumb lands, 8-way; horizontal within ±67° of the
  axis, vertical stricter (±52°) so accidental up / down is rare; 28 % dead zone.
- **Cluster** (diameters at scale 1; scale follows the short side, 0.84–1.3, so the smallest button stays ≥ 49 px):
  light 88, heavy 68, skill 1–3 60 (cooldown sweep, cost tag, ready glow, icons from `hud.skills(0, ...)`),
  ULT 70 (ring gauge from P1's `ult`; ignites with a shock ring and an opening corona; shows the fighter's ULT icon),
  guard and dodge 58. Landscape keeps the cluster in the right third and low (fighters stand in the middle band):
  dodge and guard beside the light button on the screen edge, heavy to its left, skills on an arc above, ULT on top.
  Portrait keeps every button right of the stick, within the right thumb's arc. Buttons are translucent at rest
  (the fight shows through) and solid and lit while held.
- Pointer events with capture: every finger owns the control it landed on; release, cancel, lost capture and window
  blur all let go. Everything feeds `ctx.input.setVirtual(action, down, 0)`.

## Data

`roster.js` exports placeholder menu data matching `src/fighters/MOVES.md`:

- `DEFAULT_ROSTER`: `[{ id, name, nameEn, title, titleEn, weapon, weaponEn, weaponArt: 'greatsword' | 'crescents' | 'spear', element: 'ember' | 'frost' | 'volt', blurb, blurbEn, stats: { power, speed, reach, difficulty } (1..5), moves: [{ slot, name, nameEn, desc, cost?, cd?, icon? }] }]`.
  Move slots: `light1 light2 light3 heavy fheavy dheavy skill1 skill2 skill3 ult` (the move list derives inputs from the slot).
- `DIFFICULTIES` (`easy` 수련 / `normal` 기사 / `hard` 영웅 / `nightmare` 일식), `QUALITIES`, `ELEMENTS`.

Icon names (`icons.js` → `icon(name)`): elements `ember frost volt`; actions `light heavy guard dodge ult stick pause
back random list gear home rematch people`; skills `kael-crescent kael-eruption kael-bulwark kael-ult
iska-shards iska-procession iska-afterimage iska-ult vorn-javelin vorn-stormfall vorn-arcstep vorn-ult`.
`weaponArt(kind)`, `eclipseMark()` and `corona({ n, r0, len, w })` draw the weapon silhouettes, the logo mark and
the ray corona (100×100 grid, fixed pattern).

## Typography

`--f-display` (Cinzel, Cormorant SC, Trajan Pro, Palatino, Book Antiqua → Korean serif → Georgia → serif),
`--f-ko` (Noto Serif KR, Nanum Myeongjo, AppleMyungjo, Batang …) and `--f-data` (Pretendard, Inter, Noto Sans KR,
Apple SD Gothic Neo, Malgun Gothic, system-ui). Only installed fonts are used (no font files are loaded, per the
no-network rule). Display moments do not depend on the face: announcer and ULT text get a metal gradient fill, a hard
drop shadow and a glow, and the brand shapes (emblem, corona, medallion) are SVG.

## Determinism and motion

Every UI animation (screen entrances, bar ghosts, combo punches, announcer, ULT ignition, versus splash, timer
corona) runs on a small tween runner fed by `ctx.time` real seconds, so it keeps moving through hit-stop / pause and
captures in test mode are exact. Only `transform` and `opacity` are animated. CSS transitions are limited to hover /
press micro-feedback and are disabled under `#test`. The menu's random pick uses its own seeded stream (never `ctx.rng`).

## Example: game flow

```js
ui.show('title');
ui.on('start', () => ui.show('select', { roster }));
ui.on('back', (from) => from === 'select' && ui.show('title'));
ui.on('pick', ({ p1, cpu, difficulty }) => { setupMatch(p1, cpu, difficulty); ui.show('vs', { p1, p2: cpu, difficulty }); });
ui.on('vsDone', () => { ui.show('hud', { p1: rosterById[p1], p2: rosterById[cpu], roundsToWin: 2 }); ui.hud.announce('round', { round: 1 }); });
ui.on('pause', () => { ctx.time.baseScale = 0; ui.show('pause', { p1: f1, p2: f2 }); });
ui.on('resume', () => { ctx.time.baseScale = 1; ui.show('hud'); });
ctx.onUpdate(() => {
  ui.hud.set({ time: m.time, p1: { hp: a.hp, hpMax: a.hpMax, fp: a.fp, fpMax: 100, ult: a.ult, rounds: a.wins }, p2: { ... } });
  ui.hud.skills(0, a.skills.map((s) => ({ id: s.id, icon: s.icon, name: s.name, cost: s.cost, cd: s.cdLeft / s.cd })));
}, ctx.ORDER.GAME + 1);
match.on('hit', (e) => ui.hud.combo(e.attacker, e.combo, e.comboDamage));
match.on('ko', () => ui.hud.announce('ko'));
match.on('cinematicStart', (e) => { ui.hud.cinematic(true); ui.hud.announce(e.ultName, { sub: e.ultNameEn, style: 'ult', side: e.side }); });
```

## Lab and tests

`src/labs/ui.js` — neutral stage with two stand-ins behind the UI. Scenarios: `title select selectCpu selectDiff vs
hud hudLow hudFight hudDamage hudCombo hudUlt announce(kind) cine hints pause movelist movelistVorn result resultLose
touch touchPressed none`. The lab wires the menu events, so the whole flow is playable by hand.

```
node tools/shot.mjs ui --do "__ED.lab.play('hudFight')" --at 0.3,1.1,1.75,2.6,3.5 --sheet-only --out shots/ui/fight
node tools/shot.mjs ui --do "__ED.lab.play('announce', 'ko')" --at 0.06,0.16,0.3,0.7,1.8 --sheet-only --out shots/ui/ko
node tools/shot.mjs ui --scenario src/ui/tests/capture.mjs --out shots/ui/desk            # every state, 1280 / 1920 / 1024
node tools/shot.mjs ui --scenario src/ui/tests/capture.mjs --touch --out shots/ui/phone   # 844x390 / 390x844 / 360x740
node tools/shot.mjs ui --scenario src/ui/tests/interaction.mjs --touch --size 844x390 --out shots/ui/test
```

`tests/interaction.mjs` drives real Playwright keyboard and CDP multi-touch input and prints PASS / FAIL per check:
title → select → vs → hud → pause → resume by keyboard with the emitted events; held / pressed / released edges and
axis cancel; blur release; stick + two buttons held together and released one finger at a time; the stick's vertical
sector; hit tests proving nothing covers the pad (also during a screen fade); no DOM growth over 600 HUD updates.
