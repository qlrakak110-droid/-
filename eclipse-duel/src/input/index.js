// Input layer: keyboard, gamepads and virtual sources (touch pad, AI, tests) merged into one per-player action state.
//
//   const input = createInput(ctx);           // ctx.input
//   input.held('light'), input.pressed('skill1', 1), input.axis(0)
//   input.on((action, down, player, info) => { ... })   // menus
//   input.setVirtual('guard', true, 0)                   // touch / AI / tests
//   input.frame(0)  -> { move, up, down, light, heavy, skill1, skill2, skill3, ult, guard, dodge, held, pressed }
//   input.setMode('rpg'): third-person controls (src/rpg): arrows look, Q / Tab lock, R chalice, E interact, mouse
//                         buttons attack, mouse drag looks; input.moveVec(0, out), input.look(0, out)
//
// Per frame (ctx.ORDER.INPUT) every source is sampled into `held`; `pressed` is the rising edge since the previous
// frame. A tap that goes down and up between two frames still counts as pressed (and held) for exactly one frame.

/**
 * Action names, in bit order (bit i of a mask = ACTIONS[i]). The first 15 are the duel's; the rest were appended for
 * the action-RPG mode (lock-on, chalice, interact, look keys, target switching) and never fire outside mode 'rpg'.
 */
export const ACTIONS = ['left', 'right', 'up', 'down', 'light', 'heavy', 'skill1', 'skill2', 'skill3', 'ult', 'guard', 'dodge', 'pause', 'confirm', 'back',
  'lock', 'chalice', 'interact', 'lookL', 'lookR', 'lookU', 'lookD', 'lockL', 'lockR'];
/** Bit value per action name: BIT.light === 1 << 4. */
export const BIT = Object.fromEntries(ACTIONS.map((a, i) => [a, 1 << i]));
const NA = ACTIONS.length;
const IDX = Object.fromEntries(ACTIONS.map((a, i) => [a, i]));
const PLAYERS = 2;
const NAV = new Set(['left', 'right', 'up', 'down']);

/** Keyboard P1 (KeyboardEvent.code -> actions). Arrows are P1 movement in 'solo' mode, P2 movement in 'versus' mode. */
export const KEYS_P1 = {
  KeyA: ['left'], KeyD: ['right'], KeyW: ['up'], KeyS: ['down'],
  KeyJ: ['light', 'confirm'], KeyK: ['heavy', 'back'], KeyU: ['skill1'], KeyI: ['skill2'], KeyO: ['skill3'], KeyP: ['ult'],
  KeyL: ['guard'], Space: ['dodge'], Enter: ['confirm'], NumpadEnter: ['confirm'], Escape: ['pause', 'back'], Backspace: ['back'],
};
export const KEYS_ARROWS = { ArrowLeft: ['left'], ArrowRight: ['right'], ArrowUp: ['up'], ArrowDown: ['down'] };
/** Extra keyboard bindings of mode 'rpg' (P1): the arrows look instead of moving. */
export const KEYS_RPG = {
  KeyQ: ['lock'], Tab: ['lock'], KeyR: ['chalice'], KeyE: ['interact'],
  ArrowLeft: ['lookL'], ArrowRight: ['lookR'], ArrowUp: ['lookU'], ArrowDown: ['lookD'],
};
/** Keyboard P2 (only in 'versus' mode): arrows + numpad. */
export const KEYS_P2 = {
  ...KEYS_ARROWS,
  Numpad1: ['light', 'confirm'], Numpad2: ['heavy', 'back'], Numpad4: ['skill1'], Numpad5: ['skill2'], Numpad6: ['skill3'],
  Numpad8: ['ult'], Numpad3: ['guard'], Numpad0: ['dodge'], NumpadAdd: ['pause'],
};

/** Gamepad standard mapping (button index -> actions). Left stick and d-pad move. */
export const PAD_BUTTONS = {
  0: ['light', 'confirm'], 1: ['dodge', 'back'], 2: ['heavy'], 3: ['ult'],
  4: ['skill1'], 5: ['skill2'], 6: ['guard'], 7: ['skill3'], 8: ['back'], 9: ['pause'],
  12: ['up'], 13: ['down'], 14: ['left'], 15: ['right'],
};
const PAD_LIST = Object.entries(PAD_BUTTONS).map(([k, acts]) => [Number(k), acts.map((a) => IDX[a])]);
/** Gamepad mapping of mode 'rpg': the d-pad is chalice / interact / target switching, L3 interacts, R3 locks on. */
export const PAD_BUTTONS_RPG = {
  ...PAD_BUTTONS, 10: ['interact'], 11: ['lock'], 12: ['chalice'], 13: ['interact'], 14: ['lockL'], 15: ['lockR'],
};
const PAD_LIST_RPG = Object.entries(PAD_BUTTONS_RPG).map(([k, acts]) => [Number(k), acts.map((a) => IDX[a])]);
/** Look rates (rad/s) of the look keys and the right stick, and mouse-drag sensitivity (rad/px). */
const LOOK_KEY = 2.3, LOOK_STICK_X = 3.2, LOOK_STICK_Y = 2.0, LOOK_MOUSE = 0.0042;
const PAD_GLYPH = { 0: 'A', 1: 'B', 2: 'X', 3: 'Y', 4: 'LB', 5: 'RB', 6: 'LT', 7: 'RT', 8: 'SELECT', 9: 'START', 12: '↑', 13: '↓', 14: '←', 15: '→' };
const KEY_NAME = { Tab: 'Tab', Space: 'Space', Enter: 'Enter', NumpadEnter: 'Enter', Escape: 'Esc', Backspace: '⌫', ArrowLeft: '←', ArrowRight: '→', ArrowUp: '↑', ArrowDown: '↓', NumpadAdd: 'Num+' };

/** action -> label of its first binding in a table (keyboard codes or pad buttons). */
const labelsOf = (table, name) => {
  const m = {};
  for (const k in table) for (const a of table[k]) if (!(a in m)) m[a] = name(k);
  return m;
};
const keyName = (code) => KEY_NAME[code] || code.replace(/^Key/, '').replace(/^Numpad/, 'Num');
const LABEL_P1 = { ...labelsOf(KEYS_RPG, keyName), ...labelsOf(KEYS_P1, keyName), confirm: 'Enter', back: 'Esc', lock: 'Q' };
const LABEL_P2 = labelsOf(KEYS_P2, keyName);
const LABEL_PAD = { ...labelsOf(PAD_BUTTONS, (i) => PAD_GLYPH[i]), lock: 'R3', interact: 'L3', chalice: '↑', lockL: '←', lockR: '→' };

const STICK_ON = 0.5, STICK_OFF = 0.35;   // hysteresis on the analogue stick
const REPEAT_DELAY = 0.38, REPEAT_RATE = 0.085;   // menu auto-repeat for directions (real seconds)

/**
 * Create the input layer and store it on ctx.input.
 * @param {object} ctx app context (createApp)
 * @param {{ target?: EventTarget, mode?: 'solo'|'versus' }} [opts]
 */
export function createInput(ctx, opts = {}) {
  const target = opts.target || window;
  // per player, per action: number of keyboard keys holding it, gamepad state, virtual state
  const kb = [new Int8Array(NA), new Int8Array(NA)];
  const pad = [new Uint8Array(NA), new Uint8Array(NA)];
  const virt = [new Uint8Array(NA), new Uint8Array(NA)];
  const mouse = [new Uint8Array(NA), new Uint8Array(NA)];     // mouse buttons (mode 'rpg', P1)
  const tap = [new Uint8Array(NA), new Uint8Array(NA)];       // went down since the last frame sample
  const live = [new Uint8Array(NA), new Uint8Array(NA)];      // union of sources right now (event edges)
  const heldF = [0, 0], pressF = [0, 0], relF = [0, 0];        // frame-sampled masks
  const repeatT = [new Float32Array(NA), new Float32Array(NA)];
  const keysDown = new Map();                                   // code -> [{p, i}] it holds (so a mode switch never strands a key)
  const listeners = [];
  const padStick = [{ x: 0, y: 0 }, { x: 0, y: 0 }];
  const padPrev = [new Uint8Array(NA), new Uint8Array(NA)];
  // analogue move / look (mode 'rpg'): raw left stick, right stick, virtual stick, look accumulated since the last frame
  const padMove = [{ x: 0, y: 0 }, { x: 0, y: 0 }], padLook = [{ x: 0, y: 0 }, { x: 0, y: 0 }], virtMove = [{ x: 0, y: 0 }, { x: 0, y: 0 }];
  const lookAcc = [{ x: 0, y: 0 }, { x: 0, y: 0 }], lookFrame = [{ x: 0, y: 0 }, { x: 0, y: 0 }];
  let mode = opts.mode === 'versus' ? 'versus' : opts.mode === 'rpg' ? 'rpg' : 'solo';
  let device = 'keyboard';
  let enabled = true;

  const emit = (action, down, player, info) => {
    for (let i = 0; i < listeners.length; i++) listeners[i](action, down, player, info);
  };
  const setDevice = (d) => {
    if (d === device) return;
    device = d;
    emit('device', true, 0, { device: d });
  };
  /** Recompute the live union for (p, i) and emit an edge event if it changed. */
  const refresh = (p, i) => {
    const on = kb[p][i] > 0 || pad[p][i] > 0 || virt[p][i] > 0 || mouse[p][i] > 0 ? 1 : 0;
    if (on === live[p][i]) return;
    live[p][i] = on;
    if (on) { tap[p][i] = 1; repeatT[p][i] = REPEAT_DELAY; }
    emit(ACTIONS[i], !!on, p, null);
  };

  const mapFor = (code) => {
    const out = [];
    const p1 = KEYS_P1[code];
    if (p1) for (const a of p1) out.push({ p: 0, i: IDX[a] });
    if (KEYS_ARROWS[code] && mode === 'solo') for (const a of KEYS_ARROWS[code]) out.push({ p: 0, i: IDX[a] });
    if (mode === 'rpg' && KEYS_RPG[code]) for (const a of KEYS_RPG[code]) out.push({ p: 0, i: IDX[a] });
    if (mode === 'versus' && KEYS_P2[code]) for (const a of KEYS_P2[code]) out.push({ p: 1, i: IDX[a] });
    return out;
  };

  const onKeyDown = (e) => {
    if (!enabled) return;
    const code = e.code;
    if (!code) return;
    if (e.ctrlKey || e.metaKey || e.altKey) return;
    const binds = mapFor(code);
    if (!binds.length) return;
    // keep the page from scrolling / activating focused buttons while playing
    e.preventDefault();
    setDevice('keyboard');
    if (keysDown.has(code)) return; // OS key repeat: our own auto-repeat handles menus
    keysDown.set(code, binds);
    for (const b of binds) { kb[b.p][b.i]++; refresh(b.p, b.i); }
  };
  const onKeyUp = (e) => {
    const binds = keysDown.get(e.code);
    if (!binds) return;
    keysDown.delete(e.code);
    for (const b of binds) { kb[b.p][b.i] = Math.max(0, kb[b.p][b.i] - 1); refresh(b.p, b.i); }
  };

  /** Release every held source (focus loss, pause, scene change). */
  const releaseAll = () => {
    keysDown.clear();
    for (let p = 0; p < PLAYERS; p++) {
      for (let i = 0; i < NA; i++) { kb[p][i] = 0; pad[p][i] = 0; virt[p][i] = 0; mouse[p][i] = 0; padPrev[p][i] = 0; refresh(p, i); }
      padStick[p].x = padStick[p].y = 0;
      padMove[p].x = padMove[p].y = padLook[p].x = padLook[p].y = virtMove[p].x = virtMove[p].y = lookAcc[p].x = lookAcc[p].y = 0;
    }
  };
  const onBlur = () => releaseAll();
  const onVis = () => { if (document.hidden) releaseAll(); };

  // --- mouse (mode 'rpg' only): left button = light on press, right button = look drag / heavy on a short click,
  //     any drag looks, wheel switches the lock-on target. Only presses that land on the stage count (not UI controls).
  const drag = { on: false, id: -1, button: 0, x: 0, y: 0, moved: 0, t: 0 };
  const onStage = (e) => { const t = e.target; return !!t && (t.tagName === 'CANVAS' || t.id === 'stage' || t.id === 'app' || t === document.body); };
  const tapAction = (name) => { const i = IDX[name]; tap[0][i] = 1; emit(name, true, 0, null); emit(name, false, 0, null); };
  const onPointerDown = (e) => {
    if (!enabled || mode !== 'rpg' || e.pointerType !== 'mouse' || !onStage(e)) return;
    setDevice('keyboard');
    drag.on = true; drag.id = e.pointerId; drag.button = e.button; drag.x = e.clientX; drag.y = e.clientY; drag.moved = 0; drag.t = e.timeStamp;
    if (e.button === 0) { mouse[0][IDX.light] = 1; refresh(0, IDX.light); }
  };
  const onPointerMove = (e) => {
    if (!drag.on || e.pointerId !== drag.id) return;
    const dx = e.clientX - drag.x, dy = e.clientY - drag.y;
    drag.x = e.clientX; drag.y = e.clientY;
    drag.moved += Math.abs(dx) + Math.abs(dy);
    lookAcc[0].x += dx * LOOK_MOUSE; lookAcc[0].y -= dy * LOOK_MOUSE;
  };
  const onPointerUp = (e) => {
    if (!drag.on || e.pointerId !== drag.id) return;
    drag.on = false;
    if (drag.button === 0) { mouse[0][IDX.light] = 0; refresh(0, IDX.light); }
    else if (drag.button === 2 && drag.moved < 10 && e.timeStamp - drag.t < 320 && mode === 'rpg') tapAction('heavy');
  };
  const onWheel = (e) => { if (enabled && mode === 'rpg' && onStage(e) && e.deltaY !== 0) tapAction(e.deltaY > 0 ? 'lockR' : 'lockL'); };
  const onContext = (e) => { if (mode === 'rpg' && onStage(e)) e.preventDefault(); };
  if (typeof window !== 'undefined') {
    window.addEventListener('pointerdown', onPointerDown);
    window.addEventListener('pointermove', onPointerMove);
    window.addEventListener('pointerup', onPointerUp);
    window.addEventListener('pointercancel', onPointerUp);
    window.addEventListener('wheel', onWheel, { passive: true });
    window.addEventListener('contextmenu', onContext);
  }

  target.addEventListener('keydown', onKeyDown, { passive: false });
  target.addEventListener('keyup', onKeyUp);
  window.addEventListener('blur', onBlur);
  document.addEventListener('visibilitychange', onVis);

  // --- gamepads ------------------------------------------------------------------------------------------------
  const pollPads = () => {
    if (typeof navigator === 'undefined' || !navigator.getGamepads) return;
    let pads;
    try { pads = navigator.getGamepads(); } catch (e) { return; }
    if (!pads) return;
    let slot = 0;
    pad[0].fill(0); pad[1].fill(0);
    const rpg = mode === 'rpg';
    const list = rpg ? PAD_LIST_RPG : PAD_LIST;
    padMove[0].x = padMove[0].y = padMove[1].x = padMove[1].y = padLook[0].x = padLook[0].y = padLook[1].x = padLook[1].y = 0;
    for (let k = 0; k < pads.length && slot < PLAYERS; k++) {
      const gp = pads[k];
      if (!gp || !gp.connected) continue;
      const p = slot++;
      const st = pad[p];
      const b = gp.buttons;
      let any = false;
      for (let j = 0; j < list.length; j++) {
        const btn = b[list[j][0]];
        if (btn && (btn.pressed || btn.value > 0.5)) { const acts = list[j][1]; for (let q = 0; q < acts.length; q++) st[acts[q]] = 1; any = true; }
      }
      const ax = gp.axes[0] || 0, ay = gp.axes[1] || 0, s = padStick[p];
      s.x = Math.abs(ax) > (Math.abs(s.x) > STICK_OFF ? STICK_OFF : STICK_ON) ? ax : 0;
      s.y = Math.abs(ay) > (Math.abs(s.y) > STICK_OFF ? STICK_OFF : STICK_ON) ? ay : 0;
      if (s.x < 0) st[IDX.left] = 1; else if (s.x > 0) st[IDX.right] = 1;
      if (s.y < 0) st[IDX.up] = 1; else if (s.y > 0) st[IDX.down] = 1;
      // analogue sticks (radial dead zone 0.2): left = move (y up positive), right = look
      const lm = Math.hypot(ax, ay), rx = gp.axes[2] || 0, ry = gp.axes[3] || 0, rm = Math.hypot(rx, ry);
      if (lm > 0.2) { const k = Math.min(1, (lm - 0.2) / 0.75) / lm; padMove[p].x = ax * k; padMove[p].y = -ay * k; }
      if (rm > 0.2) { const k = Math.min(1, (rm - 0.2) / 0.75) / rm; padLook[p].x = rx * k; padLook[p].y = -ry * k; any = true; }
      if (any || s.x || s.y) setDevice('gamepad');
    }
    for (let p = 0; p < PLAYERS; p++) {
      for (let i = 0; i < NA; i++) if (pad[p][i] !== padPrev[p][i]) { padPrev[p][i] = pad[p][i]; refresh(p, i); }
    }
  };

  // --- per-frame sampling --------------------------------------------------------------------------------------
  const sample = (dtReal) => {
    pollPads();
    for (let p = 0; p < PLAYERS; p++) {
      let m = 0;
      const t = tap[p], l = live[p];
      for (let i = 0; i < NA; i++) {
        if (l[i] || t[i]) m |= 1 << i;
        // menu auto-repeat for directions held by any source
        if (l[i] && NAV.has(ACTIONS[i])) {
          repeatT[p][i] -= dtReal;
          if (repeatT[p][i] <= 0) { repeatT[p][i] += REPEAT_RATE; emit(ACTIONS[i], true, p, { repeat: true }); }
        }
        t[i] = 0;
      }
      pressF[p] = m & ~heldF[p];
      relF[p] = heldF[p] & ~m;
      heldF[p] = m;
      // look delta of this frame (radians): drags / addLook accumulated since the last sample + look keys + right stick
      const lf = lookFrame[p], la = lookAcc[p];
      lf.x = la.x + (((m & BIT.lookR) ? 1 : 0) - ((m & BIT.lookL) ? 1 : 0)) * LOOK_KEY * dtReal + padLook[p].x * LOOK_STICK_X * dtReal;
      lf.y = la.y + (((m & BIT.lookU) ? 1 : 0) - ((m & BIT.lookD) ? 1 : 0)) * LOOK_KEY * 0.7 * dtReal + padLook[p].y * LOOK_STICK_Y * dtReal;
      la.x = la.y = 0;
    }
  };
  ctx.onUpdate((dtGame, dtReal) => sample(dtReal), ctx.ORDER.INPUT);

  const bitOf = (action) => {
    const i = IDX[action];
    if (i === undefined) throw new Error('input: unknown action ' + action);
    return 1 << i;
  };

  const input = {
    ACTIONS, BIT,
    /** True while `action` is held this frame (any source). */
    held(action, player = 0) { return (heldF[player] & bitOf(action)) !== 0; },
    /** True on the frame `action` went down. */
    pressed(action, player = 0) { return (pressF[player] & bitOf(action)) !== 0; },
    /** True on the frame `action` went up. */
    released(action, player = 0) { return (relF[player] & bitOf(action)) !== 0; },
    /** -1 | 0 | +1 on X (left and right together cancel). */
    axis(player = 0) {
      const m = heldF[player];
      return ((m & BIT.right) ? 1 : 0) - ((m & BIT.left) ? 1 : 0);
    },
    /** Analogue left stick of the player's gamepad (dead-zoned), {x, y} in -1..1. */
    stick(player = 0) { return padStick[player]; },
    /**
     * Analogue move vector for free 3D movement: x = right, y = forward, length <= 1. Keys and virtual buttons
     * (left / right / up / down) give unit directions; the pad's left stick and setVirtualMove are analogue.
     */
    moveVec(player = 0, out = { x: 0, y: 0 }) {
      const k = kb[player], v = virt[player];
      let x = ((k[IDX.right] > 0 || v[IDX.right] > 0) ? 1 : 0) - ((k[IDX.left] > 0 || v[IDX.left] > 0) ? 1 : 0);
      let y = ((k[IDX.up] > 0 || v[IDX.up] > 0) ? 1 : 0) - ((k[IDX.down] > 0 || v[IDX.down] > 0) ? 1 : 0);
      x += padMove[player].x + virtMove[player].x; y += padMove[player].y + virtMove[player].y;
      const l = Math.hypot(x, y);
      if (l > 1) { x /= l; y /= l; }
      out.x = x; out.y = y;
      return out;
    },
    /** Touch stick / tests: analogue move vector (x right, y forward), kept until changed. */
    setVirtualMove(x = 0, y = 0, player = 0) { virtMove[player].x = x; virtMove[player].y = y; },
    /**
     * Look delta of this frame in radians: x = yaw to the right, y = pitch up. Sources: mouse drag (mode 'rpg'), the look
     * keys, the right stick, addLook().
     */
    look(player = 0, out = { x: 0, y: 0 }) { out.x = lookFrame[player].x; out.y = lookFrame[player].y; return out; },
    /** Touch drag zone / tests: add a look delta (radians) to the next frame. */
    addLook(dx = 0, dy = 0, player = 0) { lookAcc[player].x += dx; lookAcc[player].y += dy; },
    /** Held / pressed bit masks for this frame (see BIT). */
    mask(player = 0) { return { held: heldF[player], pressed: pressF[player], released: relF[player] }; },
    /**
     * Per-player input frame for the rules engine. `move` is the held X axis, `up` / `down` / `guard` are held,
     * the attack buttons and `dodge` are rising edges this frame. `held` / `pressed` carry the full masks.
     * Pass `out` to reuse an object (no allocation).
     */
    frame(player = 0, out = {}) {
      const h = heldF[player], pr = pressF[player];
      out.move = ((h & BIT.right) ? 1 : 0) - ((h & BIT.left) ? 1 : 0);
      out.up = (h & BIT.up) !== 0;
      out.down = (h & BIT.down) !== 0;
      out.guard = (h & BIT.guard) !== 0;
      out.light = (pr & BIT.light) !== 0;
      out.heavy = (pr & BIT.heavy) !== 0;
      out.skill1 = (pr & BIT.skill1) !== 0;
      out.skill2 = (pr & BIT.skill2) !== 0;
      out.skill3 = (pr & BIT.skill3) !== 0;
      out.ult = (pr & BIT.ult) !== 0;
      out.dodge = (pr & BIT.dodge) !== 0;
      out.held = h;
      out.pressed = pr;
      return out;
    },
    /** Subscribe to edge events fn(action, down, player, info). info = { repeat: true } for menu auto-repeat, or
     *  { device } for the special action 'device'. Returns an unsubscribe function. */
    on(fn) {
      listeners.push(fn);
      return () => { const i = listeners.indexOf(fn); if (i >= 0) listeners.splice(i, 1); };
    },
    /** Touch buttons / AI / tests: hold or release an action. Same path as a real key. */
    setVirtual(action, down, player = 0) {
      const i = IDX[action];
      if (i === undefined) return;
      const v = down ? 1 : 0;
      if (virt[player][i] === v) return;
      virt[player][i] = v;
      refresh(player, i);
    },
    /** Release every virtual action of a player (e.g. when the touch pad hides). */
    clearVirtual(player = 0) {
      for (let i = 0; i < NA; i++) if (virt[player][i]) { virt[player][i] = 0; refresh(player, i); }
      virtMove[player].x = virtMove[player].y = 0;
    },
    /** Release all sources of all players. */
    releaseAll,
    /**
     * 'solo' (arrows also move P1), 'versus' (arrows + numpad drive P2 on the same keyboard) or 'rpg' (third-person:
     * arrows look, Q / Tab lock, R chalice, E interact, mouse buttons attack, mouse drag looks).
     */
    setMode(m) {
      const next = m === 'versus' ? 'versus' : m === 'rpg' ? 'rpg' : 'solo';
      if (next === mode) return;
      releaseAll();
      mode = next;
    },
    get mode() { return mode; },
    /** Last device used: 'keyboard' | 'gamepad' | 'touch'. Changes emit the pseudo action 'device'. */
    get device() { return device; },
    /** Mark the touch pad as the active device (the UI calls this on touch). */
    noteDevice(d) { setDevice(d); },
    /** Stop listening to the keyboard (text entry, etc.) while keeping virtual input alive. */
    setEnabled(b) { enabled = !!b; if (!enabled) { keysDown.clear(); for (let p = 0; p < PLAYERS; p++) for (let i = 0; i < NA; i++) { kb[p][i] = 0; refresh(p, i); } } },
    /**
     * Short label of the primary binding of an action for UI hints, e.g. keyLabel('skill1') -> 'U',
     * keyLabel('skill1', 0, 'gamepad') -> 'LB'. Returns '' for unknown / touch.
     */
    keyLabel(action, player = 0, dev = device) {
      if (dev === 'touch') return '';
      return (dev === 'gamepad' ? LABEL_PAD : player === 1 ? LABEL_P2 : LABEL_P1)[action] || '';
    },
    /**
     * Haptic feedback: gamepad rumble for `player` when supported, else a short vibration on phones.
     * @param {number} strong 0..1  @param {number} weak 0..1  @param {number} ms
     */
    rumble(player = 0, strong = 0.5, weak = 0.5, ms = 80) {
      if (ctx.test) return;
      try {
        if (device === 'gamepad' && navigator.getGamepads) {
          let slot = 0;
          for (const gp of navigator.getGamepads()) {
            if (!gp || !gp.connected) continue;
            if (slot++ !== player) continue;
            const act = gp.vibrationActuator;
            if (act && act.playEffect) act.playEffect('dual-rumble', { duration: ms, strongMagnitude: strong, weakMagnitude: weak });
          }
        } else if (device === 'touch' && navigator.vibrate) navigator.vibrate(Math.min(60, ms * 0.4));
      } catch (e) { /* unsupported */ }
    },
    /** Remove every listener this module added. */
    dispose() {
      target.removeEventListener('keydown', onKeyDown);
      target.removeEventListener('keyup', onKeyUp);
      window.removeEventListener('blur', onBlur);
      document.removeEventListener('visibilitychange', onVis);
      if (typeof window !== 'undefined') {
        window.removeEventListener('pointerdown', onPointerDown);
        window.removeEventListener('pointermove', onPointerMove);
        window.removeEventListener('pointerup', onPointerUp);
        window.removeEventListener('pointercancel', onPointerUp);
        window.removeEventListener('wheel', onWheel);
        window.removeEventListener('contextmenu', onContext);
      }
      listeners.length = 0;
    },
  };
  ctx.input = input;
  return input;
}
