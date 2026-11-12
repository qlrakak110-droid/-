// ISKA locomotion and stance: idle, guard, walks (root speed = def.stats walk / back speed, planted feet), dash, roll,
// backstep, dodge. Movement states are progress-driven (clip time = state progress x clip length).

import { defineClip } from '../../../char/index.js';
import { foot, hand, XR, XL, FL, FR, YAW_L, YAW_R, PITCH, ev } from './common.js';

const lerp3 = (a, b, k) => [a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k];

// ---- idle: hovering on the toes, blades crossed low, slow breath, weight drifting front / back ----------------------
defineClip('iska.idle', {
  duration: 2.4, loop: true, breath: 1.3,
  keys: [
    { t: 0, pose: 'iska.stance', ease: 'inOutSine' },
    { t: 0.6, ease: 'inOutSine', hips: { pos: [-0.015, -0.068, 0.01], rot: [1.2, -22, 0.8] }, bones: { chest: [-0.6, -5, -0.6], head: [0, 11, -3] },
      ik: { handR: hand([0.225, 0.945, 0.12], [0.52, -0.64, -0.56]), handL: hand([0.275, 0.972, -0.065], [0.53, -0.6, 0.58]),
        footL: foot(FL, YAW_L, PITCH - 2), footR: foot(FR, YAW_R, PITCH - 3) } },
    { t: 1.2, ease: 'inOutSine', hips: { pos: [-0.03, -0.082, 0], rot: [0, -24, 0] }, bones: { chest: [0, -6, -2], head: [0, 12, -4] },
      ik: { handR: hand([0.22, 0.93, 0.12], [0.5, -0.66, -0.56]), handL: hand([0.27, 0.96, -0.06], [0.52, -0.62, 0.58]),
        footL: foot(FL, YAW_L, PITCH), footR: foot(FR, YAW_R, PITCH) } },
    { t: 1.8, ease: 'inOutSine', hips: { pos: [-0.045, -0.07, -0.01], rot: [-1.2, -26, -0.8] }, bones: { chest: [0.6, -7, -2.6], head: [0, 13, -4.5] },
      ik: { handR: hand([0.215, 0.94, 0.125], [0.49, -0.67, -0.56]), handL: hand([0.265, 0.965, -0.055], [0.51, -0.63, 0.58]),
        footL: foot(FL, YAW_L, PITCH - 3), footR: foot(FR, YAW_R, PITCH - 2) } },
  ],
});

// ---- guard: crossed blades before the face ------------------------------------------------------------------------
defineClip('iska.guard', {
  duration: 1.8, loop: true, breath: 0.7,
  keys: [
    { t: 0, pose: 'iska.block', ease: 'inOutSine' },
    { t: 0.9, ease: 'inOutSine', hips: { pos: [-0.065, -0.14, 0.006] }, bones: { chest: [0, -8.5, -6] },
      ik: { handR: { ...XR, pos: [0.335, 1.29, -0.072] }, handL: { ...XL, pos: [0.355, 1.26, 0.082] } } },
  ],
});

// ---- walks ----------------------------------------------------------------------------------------------------------
/**
 * Light bounding stance gait (a gliding chasse): the lead foot never passes the trail foot, each foot is planted for
 * `plant` of the cycle and moves back in root space at exactly the root speed (no slide), two short flights per cycle.
 * @param {string} name @param {number} dir +1 forward / -1 backward @param {number} v m/s @param {number} T cycle s
 */
function gait(name, dir, v, T, plant) {
  const D = dir * v * T, disp = dir * v * plant * T, h = 0.1;
  const lead = dir > 0 ? 'footL' : 'footR', trail = dir > 0 ? 'footR' : 'footL';
  const base = { footL: FL, footR: FR }, yaw = { footL: YAW_L, footR: YAW_R };
  // planted windows [land, lift] in cycle fractions: trail plants first in a forward walk
  const win = { [trail]: [0, plant], [lead]: [0.5, 0.5 + plant] };
  const keys = [{ t: 0, root: { pos: [0, 0] } }];
  const fk = (f, x, pos, pitch, interp, ease) => keys.push({ t: x * T, interp, ease, ik: { [f]: foot(pos, yaw[f], pitch) } });
  for (const f of ['footL', 'footR']) {
    const [land, lift] = win[f], b = base[f];
    const pLand = [b[0] + disp / 2, 0.012, b[2]], pLift = [b[0] - disp / 2, 0.012, b[2]];
    // planted: linear slide back at root speed; swing: lift, pass, reach, land (cycle fractions, unwrapped)
    const sw = 1 - plant;
    const list = [
      [land, pLand, 0, PITCH, 'auto', 'inQuad'], [lift, pLift, 0, PITCH, 'linear'],
      [lift + sw * 0.25, lerp3(pLift, pLand, 0.18), h * 0.75, PITCH - 30, 'auto', 'outQuad'],
      [lift + sw * 0.55, lerp3(pLift, pLand, 0.62), h, PITCH - 14, 'auto'],
      [lift + sw * 0.8, lerp3(pLift, pLand, 0.93), h * 0.45, PITCH - 4, 'auto'],
      [land + 1, pLand, 0, PITCH, 'auto', 'inQuad'],
    ].map(([x, p, l, pitch, interp, ease]) => [x, [p[0], p[1] + l, p[2] + (l > 0 ? 0.012 * Math.sign(p[2]) : 0)], pitch, interp, ease]);
    // wrap into [0, 1]: keys past the cycle end move to the start, plus a boundary key at x = 0 and x = 1
    const i1 = list.findIndex((k) => k[0] > 1);
    if (i1 > 0 && list[i1 - 1][0] < 1) {
      const [xa, pa, ya] = list[i1 - 1], [xb, pb, yb] = list[i1];
      const k = (1 - xa) / (xb - xa);
      const pm = lerp3(pa, pb, k), ym = ya + (yb - ya) * k;
      fk(f, 0, pm, ym, 'auto'); fk(f, 1, pm, ym, 'auto');
    }
    for (const [x, pos, pitch, interp, ease] of list) {
      if (x > 1 + 1e-6) { if (Math.abs(x - 1 - land) > 1e-6) fk(f, x - 1, pos, pitch, interp, ease); } else fk(f, x, pos, pitch, interp, ease);
    }
  }
  // body: low in each plant, up in each flight; lean into the walk; blades sway against the stride
  const lean = dir > 0 ? -5 : 4;
  for (const [x, up, sway] of [[0, -0.004, 0.5], [plant * 0.5, -0.02, 1], [plant + 0.08, 0.012, 0], [0.5, -0.004, -0.5], [0.5 + plant * 0.5, -0.02, -1], [0.5 + plant + 0.08, 0.012, 0], [1, -0.004, 0.5]]) {
    keys.push({
      t: x * T, ease: 'inOutSine',
      hips: { pos: [-0.03 + 0.03 * dir, -0.1 + up, 0.006 * sway], rot: [1.5 * sway, -24 + 3 * sway, 1.2 * sway] },
      bones: { spine: [0, -4, lean], chest: [0, -6 - 2 * sway, lean * 0.6], neck: [0, 8, 2 - lean * 0.4], head: [0, 12 + 2 * sway, -4 - lean * 0.5] },
      ik: {
        handR: hand([0.2 - 0.03 * sway, 0.95 + up * 0.6, 0.13], [0.5, -0.66, -0.56], [0.86, 0.5, 0.1]),
        handL: hand([0.26 + 0.03 * sway, 0.98 + up * 0.6, -0.07], [0.52, -0.62, 0.58], [0.84, 0.54, -0.1]),
      },
    });
  }
  keys.push({ t: T, interp: 'linear', root: { pos: [D, 0] } });
  defineClip(name, {
    duration: T, loop: true, breath: 0.4, base: 'iska.stance',
    keys: keys.sort((a, b) => a.t - b.t),
    events: ev([[(win[lead][0] % 1) * T, 'step', { foot: lead }], [win[trail][0] * T + 1e-3, 'step', { foot: trail }]]),
  });
}
gait('iska.walkF', 1, 3.1, 0.44, 0.36);
gait('iska.walkB', -1, 2.4, 0.46, 0.4);

// ---- dash: 2.9 m in 0.24 s, a low skating glide (feet skim the frost), blades swept back ----------------------------
defineClip('iska.dash', {
  duration: 0.24, breath: 0,
  keys: [
    { t: 0, pose: 'iska.stance' },
    { t: 0.045, ease: 'outCubic', hips: { pos: [0.06, -0.2, 0], rot: [0, -32, 0] },
      bones: { spine: [0, -4, -16], chest: [0, -4, -12], neck: [0, 8, 12], head: [0, 10, 14] },
      ik: { handR: hand([-0.1, 0.92, 0.3], [-0.85, 0.15, 0.5], [0.1, 0.98, 0.1]), handL: hand([-0.02, 0.95, -0.28], [-0.85, 0.15, -0.5], [0.1, 0.98, -0.1]),
        footL: foot([0.46, 0.07, -0.12], 12, -6), footR: foot([-0.5, 0.05, 0.14], -40, -40) } },
    { t: 0.15, ease: 'inOutSine', hips: { pos: [0.08, -0.22, 0], rot: [0, -30, 0] },
      bones: { spine: [0, -4, -14], chest: [0, -4, -10] },
      ik: { handR: hand([-0.12, 0.9, 0.3], [-0.88, 0.1, 0.46], [0.1, 0.98, 0.1]), handL: hand([-0.04, 0.93, -0.28], [-0.88, 0.1, -0.46], [0.1, 0.98, -0.1]),
        footL: foot([0.42, 0.01, -0.12], 14, -4), footR: foot([-0.42, 0.07, 0.14], -40, -30) } },
    { t: 0.24, ease: 'inOutSine', pose: 'iska.stance' },
  ],
  events: ev([[0.15, 'step', { foot: 'footL' }]]),
});

// ---- backstep: 2 m hop back in 0.3 s, blades pulled in across the chest ------------------------------------------
defineClip('iska.backstep', {
  duration: 0.3, breath: 0,
  keys: [
    { t: 0, pose: 'iska.stance' },
    { t: 0.05, ease: 'outCubic', hips: { pos: [0.0, -0.17, 0], rot: [0, -26, 0] }, bones: { spine: [0, -4, -6], chest: [0, -6, -4] },
      ik: { handR: hand([0.24, 1.12, 0.08], [0.4, 0.5, -0.76], [0.8, -0.2, 0.5]), handL: hand([0.26, 1.1, -0.04], [0.4, 0.5, 0.76], [0.8, -0.2, -0.5]),
        footL: foot(FL, YAW_L, -10), footR: foot(FR, YAW_R, -20) } },
    { t: 0.13, ease: 'outQuad', hips: { pos: [-0.06, -0.02, 0], rot: [0, -24, 0] }, bones: { spine: [0, -4, 8], chest: [0, -6, 8], neck: [0, 8, -4], head: [0, 12, -8] },
      ik: { handR: hand([0.26, 1.18, 0.1], [0.45, 0.55, -0.7]), handL: hand([0.28, 1.16, -0.03], [0.45, 0.55, 0.7]),
        footL: foot([0.3, 0.18, -0.12], YAW_L, -28), footR: foot([-0.32, 0.12, 0.14], YAW_R, -34) } },
    { t: 0.22, ease: 'inQuad', hips: { pos: [-0.04, -0.17, 0], rot: [0, -24, 0] }, bones: { spine: [0, -4, -4], chest: [0, -6, -3] },
      ik: { footL: foot(FL, YAW_L, PITCH), footR: foot(FR, YAW_R, PITCH) } },
    { t: 0.3, ease: 'inOutSine', pose: 'iska.stance' },
  ],
  events: ev([[0.22, 'step', { foot: 'footR' }]]),
});

// ---- dodge: in place, a deep low sway away (back arched, head tucked), blades held close ---------------------------
defineClip('iska.dodge', {
  duration: 0.38, breath: 0,
  keys: [
    { t: 0, pose: 'iska.stance' },
    { t: 0.08, ease: 'outCubic', hips: { pos: [-0.2, -0.3, -0.06], rot: [-6, -40, 4] },
      bones: { spine: [-4, -8, 8], chest: [-6, -10, 10], neck: [2, 14, -10], head: [4, 18, -16] },
      ik: { handR: hand([0.08, 1.02, 0.18], [0.6, 0.55, -0.58], [0.6, -0.4, 0.7]), handL: hand([0.12, 1.0, -0.1], [0.6, 0.55, 0.58], [0.6, -0.4, -0.7]),
        footL: foot([0.2, 0, -0.14], 18, -4), footR: foot([-0.46, 0.01, 0.1], -46, -18) } },
    { t: 0.26, ease: 'inOutSine', hips: { pos: [-0.18, -0.28, -0.05], rot: [-5, -38, 4] },
      ik: { handR: hand([0.09, 1.04, 0.18], [0.6, 0.55, -0.58]), handL: hand([0.13, 1.02, -0.1], [0.6, 0.55, 0.58]) } },
    { t: 0.38, ease: 'inOutSine', pose: 'iska.stance' },
  ],
});

// ---- roll: 2.7 m in 0.38 s, a low spinning glide (one turn toward the camera), blades tucked across the chest ----------
defineClip('iska.roll', {
  duration: 0.38, breath: 0,
  keys: [
    { t: 0, pose: 'iska.stance' },
    { t: 0.06, ease: 'outCubic', hips: { pos: [0.0, -0.26, 0], rot: [0, -40, 0] }, bones: { spine: [0, -4, -10], chest: [0, -6, -8], neck: [0, 10, 8], head: [0, 14, 10] },
      ik: { handR: { ...XR, pos: [0.26, 1.08, -0.06] }, handL: { ...XL, pos: [0.28, 1.05, 0.07] },
        footL: { space: 'hips', pos: [0.1, -0.7, -0.12], rot: [0, 0, -16] }, footR: { space: 'hips', pos: [-0.14, -0.7, 0.13], rot: [0, 0, -30] } } },
    { t: 0.2, hips: { pos: [0.0, -0.24, 0], rot: [0, -220, 0] },
      ik: { footL: { space: 'hips', pos: [0.1, -0.7, -0.12], rot: [0, 0, -16] }, footR: { space: 'hips', pos: [-0.14, -0.7, 0.13], rot: [0, 0, -30] } } },
    { t: 0.27, ik: { footL: { space: 'hips', pos: [0.12, -0.74, -0.12], rot: [0, 0, -10] }, footR: { space: 'hips', pos: [-0.2, -0.74, 0.13], rot: [0, 0, -24] } } },
    { t: 0.3, ease: 'outQuad', hips: { pos: [-0.02, -0.2, 0], rot: [0, -380, 0] },
      ik: { footL: foot(FL, YAW_L, -6), footR: foot(FR, YAW_R, -20) } },
    { t: 0.38, ease: 'inOutSine', pose: 'iska.stance', hips: { pos: [-0.03, -0.08, 0], rot: [0, -384, 0] } },
  ],
  events: ev([[0.3, 'step', { foot: 'footL' }]]),
});
