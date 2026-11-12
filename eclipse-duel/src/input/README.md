# src/input — input mapping (`ctx.input`)

Keyboard, gamepads and virtual sources (touch pad, AI, tests) merged into one per-player action state, sampled once
per frame at `ctx.ORDER.INPUT` (before game logic). Two players: `0` (P1) and `1` (P2 / CPU).

```js
import { createInput } from './input/index.js';
const input = createInput(ctx);                 // also stored on ctx.input
```

`createInput(ctx, opts?)`

| opt | default | meaning |
|---|---|---|
| `target` | `window` | where keyboard listeners attach |
| `mode` | `'solo'` | `'solo'`: arrows also move P1. `'versus'`: arrows + numpad drive P2 on the same keyboard |

## Actions

`left right up down light heavy skill1 skill2 skill3 ult guard dodge pause confirm back`

`ACTIONS` (array, bit order) and `BIT` (`BIT.light === 1 << 4`) are exported and also on the instance.

## Bindings

Keys are matched by `KeyboardEvent.code` (physical position), so a Korean IME or a non-QWERTY layout does not
change the controls.

| action | P1 keyboard | P2 keyboard (`versus` mode) | gamepad (standard mapping) |
|---|---|---|---|
| left / right / up / down | `A D W S`, arrows in `solo` mode | arrows | left stick (0.5 on / 0.35 off hysteresis), d-pad |
| light | `J` | `Num1` | A / Cross (0) |
| heavy | `K` | `Num2` | X / Square (2) |
| skill1 / 2 / 3 | `U` `I` `O` | `Num4` `Num5` `Num6` | LB (4) / RB (5) / RT (7) |
| ult | `P` | `Num8` | Y / Triangle (3) |
| guard | `L` | `Num3` | LT (6) |
| dodge | `Space` | `Num0` | B / Circle (1) |
| confirm | `Enter`, `NumpadEnter`, `J` | `Num1` | A (0) |
| back | `Esc`, `Backspace`, `K` | `Num2` | B (1), Select (8) |
| pause | `Esc` | `Num+` | Start (9) |

One key can carry several actions (`J` = light + confirm, `Esc` = pause + back); consumers listen to the action they
care about. Gamepads are assigned to players in connection order. Keys with Ctrl / Meta / Alt held are ignored.

## Per-frame state

| call | returns |
|---|---|
| `input.held(action, player = 0)` | `true` while held this frame (any source) |
| `input.pressed(action, player = 0)` | `true` on the frame it went down (rising edge) |
| `input.released(action, player = 0)` | `true` on the frame it went up |
| `input.axis(player = 0)` | `-1 \| 0 \| +1` on X (left + right together cancel to 0) |
| `input.stick(player = 0)` | `{ x, y }` dead-zoned analogue left stick of that player's pad (shared object) |
| `input.mask(player = 0)` | `{ held, pressed, released }` bit masks (see `BIT`) |
| `input.frame(player = 0, out?)` | rules-engine frame (below); pass `out` to reuse an object (no allocation) |

A tap that goes down and up between two samples still reads as `pressed` **and** `held` for exactly one frame, so
nothing is lost at low frame rates or in the 1/60 s test harness.

`input.frame(player)`:

```js
{
  move: -1 | 0 | 1,          // held X axis
  up: bool, down: bool,      // held
  guard: bool,               // held
  light, heavy, skill1, skill2, skill3, ult, dodge,   // bool, pressed this frame (edges)
  held: number, pressed: number,                      // full bit masks for anything else (buffers, charge moves)
}
```

## Event stream (menus)

`input.on(fn) -> off` with `fn(action, down, player, info)`:

- called immediately on every edge of the merged state (not per source: holding `A` and `←` together gives one
  `left` down and one `left` up);
- directions auto-repeat while held (any source): first after 0.38 s, then every 0.085 s, with `info = { repeat: true }`
  (real time, advanced in the INPUT update);
- the pseudo action `'device'` reports a change of the last-used device: `fn('device', true, 0, { device })`.

## Virtual input, devices, misc

| call | meaning |
|---|---|
| `input.setVirtual(action, down, player = 0)` | hold / release an action from touch buttons, AI or tests (same path as a key) |
| `input.clearVirtual(player = 0)` | release every virtual action of a player |
| `input.releaseAll()` | release every source of every player (also runs on window blur and when the page is hidden) |
| `input.setMode('solo' \| 'versus')`, `input.mode` | keyboard sharing mode (switching releases everything) |
| `input.device` | `'keyboard' \| 'gamepad' \| 'touch'` (last used) |
| `input.noteDevice(d)` | mark a device as last used (the touch pad calls this) |
| `input.setEnabled(b)` | stop / resume keyboard listening (virtual input keeps working) |
| `input.keyLabel(action, player = 0, device = input.device)` | short hint label: `'U'`, `'Space'`, `'LB'`, `'Num4'`; `''` for touch |
| `input.rumble(player, strong, weak, ms)` | gamepad dual-rumble, or a short `navigator.vibrate` on touch; no-op in test mode |
| `input.dispose()` | remove listeners |

Exported tables: `KEYS_P1`, `KEYS_ARROWS`, `KEYS_P2`, `PAD_BUTTONS`.

## Examples

```js
// rules engine controller (one object reused every frame)
const f = {};
const controller = { read: (player) => ctx.input.frame(player, f) };

// CPU: the AI presses buttons through the same path as a human
ctx.input.setVirtual('guard', true, 1);
ctx.vfx.schedule(0.3, () => ctx.input.setVirtual('guard', false, 1));

// menu navigation without polling
const off = ctx.input.on((action, down, player, info) => {
  if (!down || action === 'device') return;
  if (action === 'left') moveCursor(-1);
  if (action === 'confirm' && !(info && info.repeat)) select();
});
```

Verified in the UI lab (`src/labs/ui.js`): edges, intra-frame taps, axis cancel, auto-repeat timing, blur release,
P2 virtual frames, versus remap, OS key-repeat suppression, and multi-touch (stick + two buttons) through CDP touch
events. The repeatable part runs as `src/ui/tests/interaction.mjs` (real Playwright keyboard / CDP touch input, see
`src/ui/README.md`): key down → held + pressed for one frame then held only; left + right cancel; blur releases keys
and pad buttons with a released edge; a tap inside one frame reads as pressed exactly once; touch buttons and the
stick feed `held` / `pressed` independently per finger.
