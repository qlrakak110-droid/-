// VORN locomotion and stance clips: idle, guard, walks (root motion = the rules walk / back speeds), dash, backstep, dodge.

import { defineClip, definePose } from '../../../char/index.js';
import { STANCE, STANCE_HAND, FL, FR, YL, YR, sp, ft, keyset } from './common.js';
import { def } from '../moves.js';

// ---- idle: the low spear guard breathing; weight rolls front -> back, the spear head drifts with it ---------------------
defineClip('vorn.idle', {
  duration: 2.8, loop: true, breath: 1.25, gripAt: 'choke', base: 'vorn.stance',
  keys: [
    { t: 0, pose: 'vorn.stance', ease: 'inOutSine' },
    { t: 0.8, ease: 'inOutSine', hips: { pos: [-0.01, -0.116, 0.016], rot: [2, -27, 1.6] }, bones: { spine: [0, -8, -4.5], chest: [0.4, -6.5, -2.5] },
      ik: { handR: sp([0.335, 1.0, 0.15], [0.88, -0.45, -0.21]) } },
    { t: 1.45, ease: 'inOutSine', hips: { pos: [-0.03, -0.1, 0], rot: [0, -30, 0] }, bones: { spine: [0, -8, -3], chest: [1, -8, -1] },
      ik: { handR: sp([0.32, 1.025, 0.16], [0.86, -0.41, -0.27]) } },
    { t: 2.15, ease: 'inOutSine', hips: { pos: [-0.05, -0.092, -0.014], rot: [-1.6, -33, -1.4] }, bones: { spine: [0, -8.5, -2], chest: [1.6, -9.5, 0] },
      ik: { handR: sp([0.305, 1.035, 0.17], [0.85, -0.38, -0.3]) } },
  ],
});

// ---- guard: crouched behind the heavy left pauldron, spear level at the opponent (choke grip): a braced spear wall ------
definePose('vorn.guardPose', {
  hips: { pos: [-0.06, -0.22, 0], rot: [0, -26, 0] },
  bones: { spine: [0, -8, -14], chest: [0, -10, -10], neck: [0, 10, 8], head: [0, 16, 12], shoulderL: [-4, 8, 0] },
  ik: {
    handR: sp([0.38, 0.98, 0.21], [0.95, 0.16, -0.24]),
    footL: { pos: [0.44, 0, -0.17], rot: [0, 16, 0] }, footR: { pos: [-0.42, 0, 0.2], rot: [0, -50, 0] },
  },
  grip: 1, curl: [1, 1],
});
defineClip('vorn.guard', {
  duration: 1.6, loop: true, gripAt: 'choke', breath: 0.55, base: 'vorn.stance',
  keys: [
    { t: 0, pose: 'vorn.guardPose', ease: 'inOutSine' },
    { t: 0.8, ease: 'inOutSine', hips: { pos: [-0.065, -0.228, 0.004] }, bones: { chest: [0, -10.5, -10.8] },
      ik: { handR: sp([0.378, 0.972, 0.212], [0.95, 0.15, -0.24]) } },
  ],
});

// ---- walks: step-drag that keeps the stance; planted feet move back at exactly the root speed -------------------------
function walk(name, dir, v, T) {
  const D = dir * v * T, vel = D / T;
  const lead = dir > 0 ? 'footL' : 'footR', trail = dir > 0 ? 'footR' : 'footL';
  const x0 = { footL: FL, footR: FR }, yaw = { footL: YL, footR: YR };
  const keys = [{ t: 0, pose: 'vorn.stance', root: { pos: [0, 0] } }];
  const step = (foot, a, b, h) => {
    const p = x0[foot], m = (a + b) / 2;
    keys.push({ t: a, interp: 'linear', ik: { [foot]: { pos: [p[0] - vel * a, 0, p[2]], rot: [0, yaw[foot], 0] } } });
    keys.push({ t: a + (b - a) * 0.3, ease: 'outQuad', ik: { [foot]: { pos: [p[0] + D * 0.22 - vel * (a + (b - a) * 0.3), h * 0.8, p[2]], rot: [0, yaw[foot], -14 * dir] } } });
    keys.push({ t: m, ik: { [foot]: { pos: [p[0] + D * 0.5 - vel * m, h, p[2] + 0.012 * Math.sign(p[2])], rot: [0, yaw[foot], 0] } } });
    keys.push({ t: b, ease: 'inQuad', ik: { [foot]: { pos: [p[0] + D - vel * b, 0, p[2]], rot: [0, yaw[foot], 6 * dir] } } });
  };
  step(lead, 0.03 * T, 0.43 * T, 0.1);
  step(trail, 0.5 * T, 0.9 * T, 0.085);
  // body: rises through each swing, sinks into each plant, leans into the travel; the spear head bobs with the gait
  const lean = dir > 0 ? -5 : 4, hy = -0.12;
  const H = (t, dp, dyaw, hand, chest) => keys.push({ t, ease: 'inOutSine',
    hips: { pos: [-0.03 + dp[0], hy + dp[1], dp[2]], rot: [dp[3] || 0, -30 + dyaw, dp[4] || 0] },
    bones: { spine: [0, -8, -3 + lean], chest: [1, -8 + chest, -1 + lean * 0.5] },
    ik: { handR: sp([STANCE_HAND.pos[0] + hand[0], STANCE_HAND.pos[1] + hand[1], STANCE_HAND.pos[2]], [0.86, -0.44 + hand[2], -0.25]) } });
  H(0.2 * T, [0.025 * dir, 0.02, -0.01, -1.5, -1.5], 3 * dir, [0.01, 0.025, 0.03], 1.5);
  H(0.46 * T, [0.04 * dir, -0.014, 0], 0, [0, -0.01, -0.02], 0);
  H(0.7 * T, [-0.01 * dir, 0.018, 0.01, 1.5, 1.5], -3 * dir, [-0.01, 0.02, 0.025], -1.5);
  H(0.95 * T, [0, -0.008, 0], 0, [0, 0, 0], 0);
  keys.push({ t: T, interp: 'linear', root: { pos: [D, 0] }, ik: { footL: { pos: FL, rot: [0, YL, 0] }, footR: { pos: FR, rot: [0, YR, 0] } } });
  defineClip(name, {
    duration: T, loop: true, breath: 0.4, gripAt: 'choke', base: 'vorn.stance',
    keys: keys.sort((a, b) => a.t - b.t),
    events: [{ t: 0.43 * T, name: 'step', data: { foot: lead } }, { t: 0.9 * T, name: 'step', data: { foot: trail } }],
  });
}
walk('vorn.walkF', 1, def.stats.walkSpeed, 0.38);
walk('vorn.walkB', -1, def.stats.backSpeed, 0.42);

// ---- dash (0.26 s, 2.9 m): rear foot drives, a low bound, front foot lands, rear foot catches up -------------------------
// progress-driven: clip time = state progress x duration. Feet in root space (the rules carry the body).
defineClip('vorn.dash', {
  duration: 0.26, breath: 0, gripAt: 'choke', base: 'vorn.stance',
  keys: [
    { t: 0, pose: 'vorn.stance' },
    { t: 0.05, ease: 'outCubic', hips: { pos: [0.1, -0.2, 0], rot: [-2, -22, -4] }, bones: { spine: [0, -6, -14], chest: [0, -6, -10], neck: [0, 8, 10], head: [0, 12, 12] },
      ik: { handR: sp([0.26, 0.98, 0.2], [0.92, -0.3, -0.24]), footL: ft([0.52, 0.12, -0.14], 12, { space: 'root', pitch: 10 }), footR: ft([-0.52, 0.06, 0.19], -48, { space: 'root', pitch: -30 }) } },
    { t: 0.13, ease: 'inOutSine', hips: { pos: [0.12, -0.17, 0], rot: [-2, -24, -3] },
      ik: { handR: sp([0.25, 0.99, 0.2], [0.93, -0.28, -0.24]), footL: ft([0.5, 0.06, -0.14], 12, { space: 'root', pitch: 6 }), footR: ft([-0.6, 0.1, 0.19], -48, { space: 'root', pitch: -24 }) } },
    { t: 0.17, ease: 'inQuad', ik: { footL: ft([0.44, 0, -0.15], 12, { space: 'root' }) } },
    { t: 0.21, ease: 'inOutSine', hips: { pos: [0.02, -0.16, 0], rot: [0, -28, 0] }, ik: { footR: ft([-0.32, 0.07, 0.2], -48, { space: 'root', pitch: -8 }) } },
    { t: 0.26, ease: 'inOutSine', pose: 'vorn.stance' },
    // the left hand lets go for the bound and swings back for balance
    { t: 0.02, grip: 1 }, { t: 0.06, grip: 0, bones: { upperArmL: [-30, 0, -34], foreArmL: [0, 0, 40] } },
    { t: 0.17, grip: 0, bones: { upperArmL: [-24, 0, -20], foreArmL: [0, 0, 40] } }, { t: 0.24, grip: 1, bones: { upperArmL: [0, 0, 0], foreArmL: [0, 0, 0] } },
  ],
  events: [{ t: 0.17, name: 'step', data: { foot: 'footL' } }, { t: 0.25, name: 'step', data: { foot: 'footR' } }],
});

// ---- backstep (0.32 s, 1.85 m back): spring off the front foot, spear swept up across the body, land on the rear foot ----
defineClip('vorn.backstep', {
  duration: 0.32, breath: 0, gripAt: 'choke', base: 'vorn.stance',
  keys: [
    { t: 0, pose: 'vorn.stance' },
    { t: 0.07, ease: 'outQuad', hips: { pos: [-0.12, -0.04, 0], rot: [0, -34, 0] }, bones: { spine: [0, -6, 8], chest: [0, -8, 8], neck: [0, 10, -6], head: [0, 14, -8] },
      ik: { handR: sp([0.3, 1.2, 0.2], [0.8, 0.2, -0.3]), footL: ft([0.24, 0.14, -0.15], 12, { space: 'root', pitch: -14 }), footR: ft([-0.46, 0.12, 0.2], -48, { space: 'root', pitch: -8 }) } },
    { t: 0.18, ease: 'inQuad', hips: { pos: [-0.08, -0.2, 0], rot: [0, -32, 0] }, bones: { spine: [0, -8, -4], chest: [1, -8, -2] },
      ik: { footR: ft([-0.42, 0, 0.2], -48, { space: 'root' }) } },
    { t: 0.22, ease: 'inQuad', ik: { handR: sp([0.34, 1.0, 0.21], [0.86, -0.46, -0.25]), footL: ft([0.3, 0, -0.15], 12, { space: 'root' }) } },
    { t: 0.32, ease: 'inOutSine', pose: 'vorn.stance' },
  ],
  events: [{ t: 0.18, name: 'step', data: { foot: 'footR' } }, { t: 0.22, name: 'step', data: { foot: 'footL' } }],
});

// ---- dodge (0.42 s, in place): drop and sway back under the attack, spear tucked along the body ------------------------
defineClip('vorn.dodge', {
  duration: 0.42, breath: 0, gripAt: 'choke', base: 'vorn.stance',
  keys: [
    { t: 0, pose: 'vorn.stance' },
    { t: 0.08, ease: 'outCubic', hips: { pos: [-0.2, -0.36, -0.08], rot: [-6, -48, -6] }, bones: { spine: [-4, -10, 6], chest: [-6, -12, 8], neck: [0, 16, -4], head: [0, 22, -8] },
      ik: { handR: sp([0.24, 0.88, 0.22], [0.9, -0.2, -0.38]), footL: { pos: [0.3, 0, -0.18], rot: [0, 18, 0] }, footR: { pos: [-0.46, 0, 0.16], rot: [0, -52, 0] } } },
    { t: 0.28, ease: 'inOutSine', hips: { pos: [-0.18, -0.32, -0.07], rot: [-5, -44, -5] }, ik: { handR: sp([0.25, 0.9, 0.22], [0.9, -0.24, -0.36]) } },
    { t: 0.42, ease: 'inOutSine', pose: 'vorn.stance' },
  ],
});

// ---- hit reactions (the game starts them on the impact pose: hitLight at 0.05, hitHeavy at 0.06) -------------------------
defineClip('vorn.hitLight', {
  duration: 0.32, breath: 0.5, gripAt: 'choke', base: 'vorn.stance',
  keys: [
    { t: 0, pose: 'vorn.stance' },
    { t: 0.05, ease: 'outQuad', hips: { pos: [-0.08, -0.13, 0.01], rot: [-2, -35, 4] }, bones: { spine: [-2, -10, 8], chest: [-3, -8, 10], neck: [3, 8, 10], head: [4, 10, 16] },
      ik: { handR: sp([0.22, 1.1, 0.25], [0.86, -0.22, -0.3]) } },
    { t: 0.32, ease: 'inOutSine', pose: 'vorn.stance' },
  ],
});
defineClip('vorn.hitHeavy', {
  duration: 0.85, breath: 0.6, gripAt: 'choke', base: 'vorn.stance',
  keys: [
    { t: 0, pose: 'vorn.stance' },
    // the blow folds him back, the spear knocked up off line, the rear foot catches the weight
    { t: 0.06, ease: 'outQuad', hips: { pos: [-0.12, -0.13, 0.01], rot: [-4, -38, 7] }, bones: { spine: [-4, -10, 12], chest: [-5, -8, 15], neck: [4, 6, 16], head: [6, 10, 24], shoulderR: [0, 0, 6], shoulderL: [0, 0, 6] },
      ik: { handR: sp([0.26, 1.18, 0.2], [0.62, 0.56, -0.3]), footL: ft(FL, YL, { space: 'root' }), footR: ft(FR, YR, { space: 'root' }) } },
    { t: 0.16, ease: 'inOutSine', hips: { pos: [-0.1, -0.17, 0.01], rot: [-3, -37, 5] }, bones: { spine: [-2, -10, 6], chest: [-3, -9, 8], neck: [2, 8, 6], head: [3, 10, 6], shoulderR: [0, 0, 0], shoulderL: [0, 0, 0] },
      ik: { handR: sp([0.27, 1.1, 0.2], [0.75, 0.3, -0.3]), footR: ft([FR[0] - 0.1, 0.07, FR[2]], YR, { space: 'root', pitch: 6 }) } },
    { t: 0.26, ease: 'inQuad', ik: { footR: ft([FR[0] - 0.14, 0, FR[2]], YR, { space: 'root' }) } },
    { t: 0.42, ease: 'inOutSine', hips: { pos: [-0.06, -0.13, 0], rot: [-1, -32, 2] }, bones: { spine: [0, -9, -2], chest: [1, -8, -1] },
      ik: { handR: sp([0.3, 1.04, 0.18], [0.86, -0.3, -0.28]) } },
    { t: 0.6, ease: 'inOutSine', ik: { footR: ft([FR[0] - 0.08, 0.05, FR[2]], YR, { space: 'root', pitch: -6 }) } },
    { t: 0.7, ease: 'inQuad', ik: { footR: ft(FR, YR, { space: 'root' }) } },
    { t: 0.85, ease: 'inOutSine', pose: 'vorn.stance' },
  ],
  events: [{ t: 0.26, name: 'step', data: { foot: 'footR' } }, { t: 0.7, name: 'step', data: { foot: 'footR' } }],
});
