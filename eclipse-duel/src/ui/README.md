# src/ui — menus, HUD, touch controls (`ctx.ui`) of 「흑일무림 黑日武林」

DOM UI inside `#ui`: title, hero select, versus splash, in-fight HUD, pause, move list (초식표), result, and the touch
pad. The look is ink-wash (수묵) murim, binding art direction in `MURIM.md`:

- **Ink, paper, cinnabar.** Ink-black panels with generated paper grain and wash, pale paper (한지) for text and
  cartouches, cinnabar red for seals (낙관) and the call to action, old gold almost nowhere. The three inner energies
  (열양 `#ff6a2b`, 한빙 `#86d2ff`, 뇌정 `#b48cff`) appear only as inner glow.
- **Written, not typed.** Display Korean is written stroke by stroke by `brush.js` (a procedural 판본체 brush hand built
  on `ink.strokePath`), so the title, announcer marks, hero names and 오의 banners look the same on every device.
  Hanja is the accent: carved on seals, set in small myeongjo beside the Korean. English is a small third voice.
- **Procedural everything.** Brush strokes, dry-brush rules, seals, the ink eclipse, ink mountains, splashes, band
  shapes and textures are generated in code (`ink.js`) from fixed seeds. No fonts, images or network.
- The eclipse stays the brand: the title mark, the timer dial, the 오의 orb and the round card are the black sun.

```js
import { createInput } from './input/index.js';
import { createUI } from './ui/index.js';
createInput(ctx);                 // optional peer: without it the UI is mouse / touch only
const ui = createUI(ctx);         // also stored on ctx.ui
```

`createUI(ctx, opts?)` — `opts.touch`: force the touch pad on / off (default: `(pointer: coarse)` or `ctx.quality.mobile`).
The CSS (`ui.css`) is injected once as a `<style id="ed-ui-css">`. The UI registers its update at `ctx.ORDER.UI`.

## Files

| file | contents |
|---|---|
| `index.js` | `createUI`: layout (scale unit, portrait stage), focus / navigation, screen switching, ink tokens (CSS custom properties) |
| `screens.js` | title, select, vs, pause, movelist, result |
| `hud.js` | 기혈 bands, timer dial + incense stick, seal pips, 내공 / 오의, skill slots, combo, announcer, cinematic mode |
| `touch.js` | virtual stick + action cluster |
| `ink.js` | `strokePath`, `divider`, `dash`, `swath`, `bandClip`, `seal`, `inkEclipse`, `mountains`, `splash`, `paperTexture`, `washTexture`, `cssUrl`, `PROFILE`, `FONT_KO` |
| `brush.js` | `brushText(text, opts)`: brush-written Hangul (any syllable), digits, `!`, `·`; other glyphs fall back to the serif stack |
| `icons.js` | `icon(name)`, `weaponArt(kind)`, `eclipseMark()`, `corona()` |
| `roster.js` | `DEFAULT_ROSTER`, `DIFFICULTIES`, `QUALITIES`, `ELEMENTS`, `ARENA`, `TITLE` — the one place player-facing names live |
| `anim.js` | tween runner on `ctx.time` real seconds, `h()` element helper |
| `ui.css` | all styling |

## Layout, scale, stage

- **`#stage` belongs to the UI.** Full screen, except in portrait with the touch pad *while the fight is on screen*
  (`hud`, `pause`, `movelist` opened from pause): then the stage is a 16:10 strip at the top
  (`min(width × 0.625, height × 0.5)`, below the top safe area), the HUD's bands sit in a deck right under it and the
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
- The title never crops: its lockup and menu are measured on `enter` / resize and shrink as one block when they would
  not fit between the top edge and the footer (so extra menu entries, such as the 강호행 row that `src/rpg` adds,
  cannot push the title off screen).
- Verified at 1280×720, 844×390 touch and 390×844 touch (every screen and card), plus 1920×1080 / 1024×768 / 360×740
  through `tests/capture.mjs`.

## Screens — `ui.show(screen, data) -> ui`

`ui.screen` holds the current one; the `'screen'` event fires `(screen, prev)`. The previous screen fades out
(0.16 s). Menus are navigable with `ctx.input` (directions = spatial focus move, `confirm`, `back`; a focused value
control takes left / right) and by mouse / touch (hover focuses, click / tap activates). Fighters may be passed as
roster objects or ids (resolved against the last roster given to `select`, default `DEFAULT_ROSTER`). After a screen
change the rest of that frame's input is ignored (Esc is both `pause` and `back`).

| screen | data | notes |
|---|---|---|
| `'title'` | `{ quality? }` | the ink eclipse behind the brush-written 「흑일무림」 with its seal 黑日武林, the Hanja between dry-brush rules, ECLIPSE DUEL, ink mountains rising from the bottom, the start prompt, quality toggle. Any face button, `confirm` or a tap on the backdrop emits `start`. Title menu entries stack in `.tt-menu` under the prompt |
| `'select'` | `{ roster, p1?, cpu?, difficulty?, step? }` | three hero cards (weapon line art on a wash, sect emblem, the name written down a paper cartouche with the hero's seal, 별호) + 천명 (random), detail panel (brush name, Hanja, 별호, 문파 / 병기 / 내공 lines, stats, 절기 and 오의), CPU rank, begin. Flow: P1 pick → CPU pick (or random) → rank → begin. `back` steps back; on the first step emits `back('select')` |
| `'vs'` | `{ p1, p2, difficulty?, arena?, arenaHanja?, arenaEn?, duration = 3.2 }` | versus splash (diagonal split; top / bottom in portrait): brush names, seals, 별호, sect and inner art; the black sun with 「대」 and the seal 對 at the seam; arena (default `ARENA` = 천무대 天武臺) and rank below. Emits `vsDone` once, after `duration` s, or on `confirm` / `pause` after 0.8 s |
| `'hud'` | `{ p1?, p2?, roundsToWin? }` | shows the HUD (calls `hud.setup(data)` when fighters are given; `hud.reset()` unless coming back from pause / move list) |
| `'pause'` | `{ p1, p2 }` or `{ fighters: [a, b] }`, `quality?` | 「숨 고르기」 over the dimmed HUD: resume, 초식표, quality, quit (two-step confirm). `back` / `pause` emit `resume` |
| `'movelist'` | `{ fighters?, index = 0, fromPause? }` | 초식표 per hero: 기본 초식 / 절기 / 오의 / 신법 with Korean · Hanja · gloss, keyboard keycaps and touch glyphs per move; scrolls with up / down. `back` returns to pause when `fromPause`, else emits `back('movelist')` |
| `'result'` | `{ winner: 0 \| 1 \| -1, p1, p2, score: [a, b], rounds: [{ winner, how: 'ko' \| 'time' \| 'perfect' \| 'draw' }], stats?: { p1: { maxCombo, damage, ults, hpLeft } } }` | the verdict from the player's side, written large over an ink blot and stamped: 「승 勝」 / 「패 敗」 / 무승부; winner's brush name, score, per-round chips (결 決 / 향진 香盡 / 무결 無缺), stats; rematch / select / title |
| `'none'` | — | hides everything |

## Events — `ui.on(name, fn) -> off`

| event | args | when |
|---|---|---|
| `start` | — | title confirmed |
| `pick` | `{ p1: id, cpu: id, difficulty: 'easy' \| 'normal' \| 'hard' \| 'nightmare', random: bool }` | select finished (`random`: the CPU came from the random card; already resolved to an id). The ranks read 삼류 / 이류 / 일류 / 절정; the values are unchanged |
| `vsDone` | — | versus splash finished |
| `pause` | — | player asked to pause (Esc / Start on the HUD, or the touch pause button). The UI does **not** open the pause screen itself: the game freezes time and calls `ui.show('pause', ...)` |
| `resume` | — | pause closed |
| `quality` | `'low' \| 'mid' \| 'high'` | quality toggle changed (title or pause) |
| `toTitle` | — | quit confirmed (pause) or "title" (result) |
| `rematch` | — | result |
| `select` | — | result → hero select |
| `back` | `'select' \| 'movelist'` | back out of a screen that has no parent of its own |
| `screen` | `(screen, prev)` | after every `show` |
| `hud:ultReady` | `(side, full)` | a 오의 gauge ignited / was spent |
| `hud:skills`, `hud:cinematic` | `(side, list)`, `(on)` | mirrors of the HUD calls (for other listeners) |

UI sounds go through `ctx.audio.play('ui_move' | 'ui_select' | 'ui_back')` when audio exists; the first gesture
calls `ctx.audio.unlock()`.

## HUD — `ui.hud`

All per-frame calls compare against cached values and only write what changed; bands, sweeps and gauges move by
`transform` (no layout), text is written only when the shown value changes. 600 `set` + `skills` + `combo` calls with
changing values add no DOM nodes (`tests/interaction.mjs`).

```js
ui.hud.setup({ p1: rosterEntry, p2: rosterEntry, roundsToWin: 2 });     // names, seals, elements, skill + 오의 icons, weapon
ui.hud.set({ time, roundsToWin?, p1: { name?, hp, hpMax, fp, fpMax, ult, ultMax = 100, rounds, element, title? }, p2: {...} });
ui.hud.skills(side, [{ id, name, key?, cd: 0..1, ready?, cost, icon }]);
ui.hud.combo(side, hits, damage);
ui.hud.announce(text, { sub, style, duration, round, side, element, keep, kicker, seal, hanja });
ui.hud.cinematic(on);
```

| call | details |
|---|---|
| `setup(o)` | static info once per match. Fighter = roster entry: the plate shows the sect emblem, the brush-written `name`, its `hanja`, and `title · sect`. Builds skill slots from `moves` (`skillsOf(f)` is exposed); the 오의 orb (and the touch 오의 button for P1) shows the icon of the `ult` move; `weaponArt`, `seal` and the `ult` move feed the 오의 banner |
| `set(o)` | every frame. **time**: seconds left as numerals in the eclipse dial (`null` / `Infinity` shows ∞); under the dial an incense stick burns toward its foot (fraction of the largest time seen since `setup`), the ember riding its end; ≤ 10 s the dial burns red, quickens and the number pulses each second. **hp** (기혈): a band of pale ink inside a black under-stroke with brushed, frayed ends; the fill carries the element as an inner glow and a white-hot leading edge; damage holds a cinnabar ghost for 0.55 s then drains, flashes the lost segment and jolts the band; < 25 % the band turns blood red and throbs. **fp** (내공): element bar with quarter ticks + value. **ult** (오의): ring gauge in the desktop orb / thin bar on touch; reaching full **ignites** it (core flash, two shock rings, a flare, the corona snapping open, the brush label 「오의」 with its seal 奧義 slamming in), then it breathes until spent. **rounds**: a seal 勝 is stamped into the next empty frame |
| `skills(side, list)` | up to 3 ink roundels. `cd` 0..1 = remaining cooldown fraction (clockwise sweep with a hand). `ready` defaults to `cd <= 0 && fp >= cost`; becoming ready fires a burst, ready slots breathe. `cost` tag turns red when 내공 is short. `key` overrides the hint (default from `input.keyLabel`; hidden for the CPU side unless `input.mode === 'versus'`). `icon` = an icon name (below) |
| `combo(side, hits, damage)` | `side` = attacker. Shows at `hits >= 2` (「n 연환」, on a swath of ink so it reads over white-hot effects), punches (scale + tilt + white flash) on every increase, fades 2.6 s after the last update or when `hits < 2` |
| `announce(text, o)` | see below; returns an id |
| `clearAnnounce()` | remove announcements |
| `dismiss(style = 'ult', dur = 0.25)` | fade the cards of one style out early and remove them (default: the 오의 banner; `null` = every card). For choreography that wants the whole frame before a card's time is up — use this instead of reaching into the HUD's DOM |
| `cinematic(on)` | slides the top bar up and the docks down (0.38 s), dims the touch pad; announcements stay |
| `hints(on)` | control strip (keyboard / gamepad labels follow the last device; hidden on touch): 이동 · 경초 · 중초 · 절기 · 오의 · 호신 · 경공 · 숨 고르기 |
| `reset()` | between rounds: clears ghosts, combos, announcements |
| `cine` | current cinematic blend 0..1 |

### Announcer

`text` is free text or a preset: `'round'` (`o.round`), `'final'`, `'fight'`, `'ko'`, `'perfect'`, `'timeup'`, `'draw'`,
`'win'`, `'lose'` (`'ROUND 2'`, `'K.O.'`, `'TIME UP'` ... are recognised too). `o.sub` / `o.style` / `o.seal` override the
preset's. A card is a stack of layers driven by one tween: a band of black ink dragged across (so the line reads over
any effect), the main line written by `brushText`, its Hanja on a seal that is stamped after the line lands, a
dry-brush rule and the English sub on its own slip of ink; slamming cards add an ink splash, a ring and a flare. A new card replaces the
current one unless `keep` (an `ult` banner survives others). Transform / opacity only.

| preset | main line · seal · sub | style, motion | duration |
|---|---|---|---|
| `round` | 「제 n 합」 · 第n合 · ROUND n | `round`: the black sun rises and turns, the round is written across its lower limb | 1.6 s |
| `final` | 「마지막 합」 · 決勝 · FINAL ROUND | `round`, blood-dark band | 1.6 s |
| `fight` | 「겨뤄라!」 · 比武 · FIGHT | `fight`: slams in from 2.6× over an ink splash, ring, flare, echo, jolt | 1.0 s |
| `ko` | 「결」 · 決 · K.O. | `ko`: blood-dark ink; the mark is cut along a rising slash and the halves part | 2.3 s |
| `perfect` | 「무결」 · 無缺 · PERFECT | `perfect`: the eclipse behind, a pass of light | 2.1 s |
| `timeup` | 「향이 다 탔다」 · 香盡 · TIME UP | `timeup`: cold ink, the line drops in | 1.8 s |
| `draw` | 「무승부」 · 和 · DRAW | `timeup` | 1.8 s |
| `win` / `lose` | 「승」 · 勝 / 「패」 · 敗 | `verdict`: slams in like `fight` (`lose` on blood-dark ink) | 2.4 s |

Free text takes `style: 'banner'` (default, 1.6 s) or `style: 'win'` (2.4 s, seal 勝: the game announces the match
winner with `announce(roster.name, { style: 'win', sub: '승 · WINNER' })`). Hangul is brush-written; other glyphs in
free text fall back to the serif stack.

**`style: 'ult'` — the 오의 banner.** A hanging banner at the side of the screen that belongs to `o.side` (left for P1,
right for P2; the hero shot in the middle stays clear): the kicker 「오의 奧義」, the 오의 written down the banner
glyph by glyph in the hero's element, its Hanja running beside it, the hero's seal, the English gloss at the foot,
the weapon line art behind. With a `side` whose roster entry has an `ult` move the banner shows **that
move's `name` / `hanja` / `nameEn`** (so callers cannot drift from the roster); `text`, `o.hanja` and `o.sub` are used
for a custom banner (pass `o.hanja`, `''` for none) or when no roster was set up. `o.kicker` replaces the kicker.
1.7 s by default.

Layout: desktop HUD has plates + bands + seal pips + the dial on top and the 오의 orb, skills and 내공 docked in the
bottom corners. Touch landscape: compact 내공 / 오의 bars under the bands, a pause button under the dial, no skill
slots (the pad shows them). Touch portrait: the stage stays clean (only the combo, announcements and a pause button at
its top right); names, bands, dial, pips and the 내공 / 오의 row form a deck under it.

## Touch pad — `ui.touch`

| call | meaning |
|---|---|
| `ui.touch.setVisible(b)` | enable the pad (shown while the HUD screen is up). Landscape: overlay on the stage. Portrait: stage on top, pad below |
| `ui.touch.visible` | current state |
| `ui.touch.el` | root element |

- **Stick** (left 42 % of the pad area): floats to where the thumb lands, 8-way; horizontal within ±67° of the
  axis, vertical stricter (±52°) so accidental up / down is rare; 28 % dead zone.
- **Cluster** of ink roundels with brush glyphs (diameters at scale 1; scale follows the short side, 0.84–1.3, so the
  smallest button stays ≥ 49 px): 경초 (light) 88, 중초 (heavy) 68, 절기 1–3 60 (cooldown sweep, cost tag, ready glow,
  icons from `hud.skills(0, ...)`), 오의 70 (ring gauge from P1's `ult`; ignites with a shock ring and an opening
  corona; shows the hero's 오의 icon), 호신 (guard) and 경공 (dodge) 58. Landscape keeps the cluster in the right third
  and low (fighters stand in the middle band). Portrait keeps every button right of the stick, within the right thumb's
  arc. Buttons are translucent at rest (the fight shows through) and turn to lit paper while held.
- Pointer events with capture: every finger owns the control it landed on; release, cancel, lost capture and window
  blur all let go. Everything feeds `ctx.input.setVirtual(action, down, 0)`.

## Data — `roster.js`

The single source of player-facing names (`src/fighters/registry.js` builds `ROSTER` from it and adds `mood`). Code ids,
slots, icon names and `weaponArt` keys never change.

```
DEFAULT_ROSTER: [{
  id: 'kael' | 'iska' | 'vorn',
  name, hanja, nameEn,                       // 염무강 · 炎武剛 · YEOM MU-GANG
  title, titleHanja, titleEn,                // 별호: 적염패도 · 赤焰覇刀 · Crimson Flame Tyrant Saber
  sect, sectHanja, sectEn, seal, emblem,     // 적양문 · 赤陽門 · Red Sun Gate · seal '赤陽' · icon 'sect-kael'
  weapon, weaponHanja, weaponEn, weaponArt,  // 참마대도 · 斬馬大刀 · Great Saber · 'greatsword' | 'crescents' | 'spear'
  art, artHanja, artEn, element,             // 열양진기 · 烈陽眞氣 · Blazing-Sun Qi · 'ember' | 'frost' | 'volt'
  blurb, blurbEn, stats: { power, speed, reach, difficulty } (1..5),
  moves: [{ slot, name, hanja, nameEn, desc, cost?, cd?, icon? }],
}]
```

Move slots: `light1 light2 light3 heavy fheavy dheavy skill1 skill2 skill3 ult` (the move list derives inputs from the
slot). The full 초식 table is in `src/fighters/MOVES.md`. `DIFFICULTIES` (`easy` 삼류 / `normal` 이류 / `hard` 일류 /
`nightmare` 절정), `QUALITIES`, `ELEMENTS` (열양 烈陽 / 한빙 寒氷 / 뇌정 雷霆), `ARENA` (천무대 天武臺), `TITLE`.

Icon names (`icons.js` → `icon(name)`): elements `ember frost volt`; sect emblems `sect-kael` (the red sun standing in
a gate), `sect-iska` (a pear blossom in the arms of the cold moon), `sect-vorn` (thunder falling from a cloud scroll
onto a keep); brush action glyphs `light heavy guard dodge ult pause back random` plus `stick list gear home rematch
people`; skills `kael-crescent kael-eruption kael-bulwark kael-ult iska-shards iska-procession iska-afterimage iska-ult
vorn-javelin vorn-stormfall vorn-arcstep vorn-ult`. `weaponArt(kind)` draws the great saber (참마대도), the twin
crescents (월아쌍도) and the tasselled spear (뇌룡창) on a 60×240 grid; `eclipseMark()` is the ink eclipse;
`corona({ n, r0, len, w })` the fine ray ring of the dial and the orb.

## Ink and brush API

```js
import { brushText } from './ui/brush.js';
import { seal, divider, strokePath, PROFILE } from './ui/ink.js';
el.innerHTML = brushText('겨뤄라!', { weight: 1.15, fill: ['#fffaf0', '#dfd3b8'] });   // inline SVG; set its height in CSS
el.innerHTML = brushText('흑일분천', { vertical: true }) + seal('赤陽') + divider({ seed: 4 });
```

| function | returns |
|---|---|
| `brushText(text, { vertical, gap = 8, seed, weight = 1, shadow = true, fill = 'currentColor' \| [top, bottom], rough, cls })` | `<svg class="brush-text">`: each Hangul syllable is composed from jamo templates (all 19 initials, 21 vowels, 27 finals) in a 100×100 cell and written with pressure, slanted brush landings and dry tails; a dark ink copy sits under it for contrast. Cached per text + options |
| `strokePath(points, { w, profile, rough, dry, streaks, streakW, spray, head, seed })` | path data of one brush stroke; dry-brush streaks are counter-wound sub-paths (holes under the default fill rule), so many strokes can share one `<path>` |
| `divider({ seed, flip })`, `dash({ seed })`, `swath({ seed, dry })` | stretchable brush shapes (rule, accent, wide swath) as `<svg>` |
| `bandClip({ seed, n, amp, left, right, flip, vertical })` | a CSS `polygon()` for a brushed band (HP, announcer, banner) |
| `seal(chars, { seed, relief })` | a worn cinnabar seal with 1–4 reserve characters (four read right column first) |
| `inkEclipse({ streamers, seed })`, `mountains({ seed })`, `splash({ seed })` | the black sun, layered ink ridges, a thrown blot |
| `paperTexture()`, `washTexture()`, `cssUrl(svg)` | CSS `url(...)` values (canvas data URLs / SVG data URLs for masks) |

`index.js` sets the shared pieces once as custom properties on `.ed-ui`: `--noise`, `--wash`, `--clip-hp-l / -r`,
`--clip-bar-l / -r`, `--clip-band`, `--clip-tag`, `--clip-scroll`, `--m-swath`, `--m-dash`, `--m-div`.

## Typography

`--f-ko` (the myeongjo stack for Korean + Hanja: Noto Serif KR / CJK, Source Han Serif, Nanum Myeongjo, AppleMyungjo,
Batang, Songti, Mincho → Georgia → serif), `--f-display` (Latin serif for numerals and English accents) and `--f-data`
(Pretendard, Inter, Noto Sans KR, Apple SD Gothic Neo, Malgun Gothic, system-ui). Only installed fonts are used (no
font files are loaded). Nothing that carries the look depends on the face: display Korean is brush-written SVG, seals
frame their Hanja, and the eclipse, rules and bands are drawn. Bilingual rule: Korean first, Hanja as the accent
(class `hj`), small English third.

## Determinism and motion

Every UI animation (screen entrances, band ghosts, combo punches, announcer, 오의 ignition, versus splash, dial corona)
runs on a small tween runner fed by `ctx.time` real seconds, so it keeps moving through hit-stop / pause and captures
in test mode are exact. Only `transform` and `opacity` are animated; the announcer's lines carry no CSS filter (their
shadow is a second ink copy inside the SVG). CSS transitions are limited to hover / press micro-feedback and are disabled under `#test`. The
menu's random pick uses its own seeded stream (never `ctx.rng`). Procedural art is generated once (strings / data
URLs) at creation, never per frame.

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
touch touchPressed none`; `announce` kinds: `round final fight ko perfect timeup draw win lose winner ult ultP2`. The
lab wires the menu events, so the whole flow is playable by hand.

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
