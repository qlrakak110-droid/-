// Per-fighter input tracking: held state, press edges, the input buffer and double-tap detection.
//
// Controllers report *held* buttons once per match.step(). The tracker turns rising edges into buffered presses that
// stay usable for `rules.inputBuffer` seconds of the fighter's own time (the buffer does not age during the fighter's
// hit-stop, so a button pressed during hit-stop still comes out when the freeze ends).

import { ATTACK_BUTTONS, BUTTONS, NEUTRAL_INPUT } from './constants.js';

const PRESS_BUTTONS = [...ATTACK_BUTTONS, 'dodge'];
const MAX_BUFFER = 12;

/** Normalise any controller output into a full input state (missing fields = released). */
export function normalizeInput(raw, out = { ...NEUTRAL_INPUT }) {
  if (!raw) { Object.assign(out, NEUTRAL_INPUT); return out; }
  const mv = Number(raw.move) || 0;
  out.move = mv > 0.5 ? 1 : mv < -0.5 ? -1 : 0;
  for (const b of BUTTONS) out[b] = !!raw[b];
  return out;
}

/** @returns {object} a fresh tracker */
export function createInputTracker() {
  return {
    held: { ...NEUTRAL_INPUT },
    prev: { ...NEUTRAL_INPUT },
    buffer: [],                    // [{button, move, up, down, age, denied}]
    lastTap: { '-1': -Infinity, '1': -Infinity },
    dashReq: null,                 // {dir (world -1|1), age}
    guardPressedAt: -Infinity,     // match time of the last guard press (perfect guard)
  };
}

/** Clear everything (round start, input disabled). */
export function clearInput(tr) {
  Object.assign(tr.held, NEUTRAL_INPUT);
  Object.assign(tr.prev, NEUTRAL_INPUT);
  tr.buffer.length = 0;
  tr.lastTap['-1'] = tr.lastTap['1'] = -Infinity;
  tr.dashReq = null;
  tr.guardPressedAt = -Infinity;
}

/**
 * Feed this step's held state. Rising edges become buffered presses; a second tap of the same stick direction within
 * `rules.doubleTapWindow` becomes a dash request.
 * @param {object} tr tracker  @param {object} input normalised input  @param {number} now match time  @param {object} rules
 */
export function feedInput(tr, input, now, rules) {
  Object.assign(tr.prev, tr.held);
  Object.assign(tr.held, input);
  const h = tr.held, p = tr.prev;
  for (const b of PRESS_BUTTONS) {
    if (h[b] && !p[b]) {
      if (tr.buffer.length >= MAX_BUFFER) tr.buffer.shift();
      tr.buffer.push({ button: b, move: h.move, up: h.up, down: h.down, age: 0, denied: false });
    }
  }
  if (h.guard && !p.guard) tr.guardPressedAt = now;
  if (h.move !== 0 && h.move !== p.move) {
    const k = String(h.move);
    if (now - tr.lastTap[k] <= rules.doubleTapWindow) {
      tr.dashReq = { dir: h.move, age: 0 };
      tr.lastTap[k] = -Infinity;
    } else tr.lastTap[k] = now;
  }
}

/** Age the buffer by `dt` seconds and drop expired presses. */
export function ageInput(tr, dt, rules) {
  if (dt <= 0) return;
  const lim = rules.inputBuffer;
  const b = tr.buffer;
  let w = 0;
  for (let i = 0; i < b.length; i++) {
    const e = b[i];
    e.age += dt;
    if (e.age <= lim) b[w++] = e;
  }
  b.length = w;
  if (tr.dashReq) {
    tr.dashReq.age += dt;
    if (tr.dashReq.age > lim) tr.dashReq = null;
  }
}

/** Most recent buffered press of `button`, or null. */
export function latestPress(tr, button) {
  const b = tr.buffer;
  for (let i = b.length - 1; i >= 0; i--) if (b[i].button === button) return b[i];
  return null;
}

/** Remove one buffered press (consumed). */
export function consumePress(tr, entry) {
  const i = tr.buffer.indexOf(entry);
  if (i >= 0) tr.buffer.splice(i, 1);
}

/**
 * Direction of a press relative to the fighter: {fwd: -1|0|1, up, down}. Uses the stick at press time, or the stick
 * now when it was neutral at press time (so 'press then push' within the buffer still counts).
 */
export function pressDir(tr, entry, facing) {
  const mv = entry.move || tr.held.move;
  return { fwd: mv * facing, up: entry.up || tr.held.up, down: entry.down || tr.held.down };
}
