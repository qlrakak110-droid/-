// rpg.<hero>.roll / drink / death / rest — the hero motion of the expedition that the duel never needed.
//
//   roll    a forward shoulder roll: dive, one tucked turn over the back, feet under, up into the stance. Progress-driven
//           (clip time = state progress x clip length); the root travel is the machine's, so feet are IK-free while tumbling
//   drink   the restorative taken with the free hand: weapon lowered, hand to the mouth, head back, a breath (1.5 s)
//   death   rocked back, the knees give, down on the back (holds the last frame)
//   rest    seated cross-legged in breath meditation, the weapon at rest (loop)
// Each clip starts from the hero's own stance pose, so it blends from idle / run without a pop.

import { defineClip } from '../../../char/index.js';
import '../../../game/clips.js';      // game.koPose
import { SHOULDER_HAND as K_HAND } from '../../../fighters/kael/clips/common.js';
import { hand as iHand } from '../../../fighters/iska/clips/common.js';
import { sp as vSpear } from '../../../fighters/vorn/clips/common.js';

const TUCK = { thighR: [0, 0, 118], thighL: [0, 0, 104], shinR: [0, 0, -128], shinL: [0, 0, -118], footR: [0, 0, -18], footL: [0, 0, -18] };

/**
 * @param {string} id hero id
 * @param {object} H { stance, T (roll clip length), feet: { L: [f,u,s], R: [f,u,s], yawL, yawR }, sit (hips drop when seated),
 *                     rollHand(k) -> ik hands while tumbling, carry -> ik hands lowered (drink), restHands -> ik hands seated,
 *                     twin (a weapon in each hand) }
 */
function heroActions(id, H) {
  const stance = id + '.stance';
  const feet = (df = 0, w = 1) => ({
    footL: { pos: [H.feet.L[0] + df, 0, H.feet.L[2]], rot: [0, H.feet.yawL, 0], w },
    footR: { pos: [H.feet.R[0] + df, 0, H.feet.R[2]], rot: [0, H.feet.yawR, 0], w },
  });
  /** feet off IK (tumbling, lying, seated): the legs follow their FK keys */
  const NO_FEET = feet(0, 0);

  // ---- roll --------------------------------------------------------------------------------------------------------
  {
    const T = H.T;
    const k = (f) => +(f * T).toFixed(4);
    defineClip(`rpg.${id}.roll`, {
      duration: T, breath: 0, look: false, base: stance,
      keys: [
        { t: 0, pose: stance, grip: H.twin ? 0 : 1 },
        // dive: the lead shoulder drops, the back rounds, the hands go down
        { t: k(0.12), ease: 'outQuad', hips: { pos: [0.18, -0.36, 0], rot: [6, -6, -38] }, bones: { spine: [0, 0, -30], chest: [0, 0, -26], neck: [0, 0, -24], head: [0, 0, -22] },
          ik: { ...H.rollHand(0), footL: { pos: [0.1, 0, H.feet.L[2]], rot: [0, 6, -30] }, footR: { pos: [-0.5, 0.06, H.feet.R[2]], rot: [0, -6, -50] } }, grip: 0 },
        // over: tucked, the back rolls on the floor (hips pitch a full turn)
        { t: k(0.2), hips: { pos: [0.2, -0.56, 0], rot: [8, -4, -100] }, bones: { spine: [0, 0, -38], chest: [0, 0, -32], neck: [0, 0, -30], head: [0, 0, -26], ...TUCK }, ik: { ...H.rollHand(1), ...NO_FEET } },
        { t: k(0.34), hips: { pos: [0.1, -0.6, 0], rot: [4, -2, -190] }, bones: { spine: [0, 0, -40], chest: [0, 0, -34], neck: [0, 0, -30], head: [0, 0, -28], ...TUCK }, ik: { ...H.rollHand(1), ...NO_FEET } },
        { t: k(0.5), hips: { pos: [-0.04, -0.56, 0], rot: [0, 0, -290] }, bones: { spine: [0, 0, -36], chest: [0, 0, -30], neck: [0, 0, -22], head: [0, 0, -16], ...TUCK }, ik: { ...H.rollHand(1), ...NO_FEET } },
        // feet under, rising
        { t: k(0.66), ease: 'outQuad', hips: { pos: [-0.04, -0.42, 0], rot: [0, -10, -360] }, bones: { spine: [0, -4, -24], chest: [0, -4, -16], neck: [0, 6, 6], head: [0, 8, 10] },
          ik: { ...H.rollHand(0.4), ...feet(0, 1) } },
        { t: k(0.82), ease: 'inOutSine', hips: { pos: [-0.03, -0.24, 0], rot: [0, -18, -360] }, bones: { spine: [0, -5, -12], chest: [0, -5, -8] }, ik: { ...H.rollHand(0), ...feet(0, 1) } },
        { t: T, ease: 'inOutSine', pose: stance, hips: { rot: [0, H.yaw, -360] }, grip: H.twin ? 0 : 1 },
      ],
      events: [{ t: k(0.66), name: 'step', data: { foot: 'footL' } }],
    });
  }

  // ---- drink (the pill from the gourd: free hand to the mouth) -----------------------------------------------------
  defineClip(`rpg.${id}.drink`, {
    duration: 1.5, breath: 0.4, look: false, base: stance,
    keys: [
      { t: 0, pose: stance, grip: H.twin ? 0 : 1 },
      { t: 0.22, ease: 'inOutSine', grip: 0, hips: { pos: [-0.03, -0.09, 0], rot: [0, H.yaw * 0.5, 0] }, bones: { spine: [0, -2, 2], chest: [0, -2, 3] }, ik: { ...H.carry } },
      // hand to the mouth, chin up
      { t: 0.55, ease: 'inOutSine', bones: { upperArmL: [34, 14, 52], foreArmL: [0, 30, 132], handL: [10, 0, 10], neck: [0, 4, 10], head: [0, 6, 14], chest: [0, -2, 6] } },
      { t: 0.95, ease: 'inOutSine', bones: { upperArmL: [36, 14, 56], foreArmL: [0, 30, 136], handL: [14, 0, 14], neck: [0, 4, 20], head: [0, 6, 26], chest: [0, -2, 9] } },
      // lowers, exhales
      { t: 1.2, ease: 'inOutSine', bones: { upperArmL: [-10, 6, 12], foreArmL: [0, 0, 40], handL: [0, 0, 0], neck: [0, 6, -4], head: [0, 8, -6], chest: [0, -3, -2] }, ik: { ...H.carry } },
      { t: 1.5, ease: 'inOutSine', pose: stance, grip: H.twin ? 0 : 1 },
    ],
  });

  // ---- death ---------------------------------------------------------------------------------------------------------
  defineClip(`rpg.${id}.death`, {
    duration: 1.5, breath: 0, look: false, base: stance,
    keys: [
      { t: 0, pose: stance },
      // rocked back, arms loosen
      { t: 0.2, ease: 'outCubic', grip: 0, hips: { pos: [-0.16, -0.08, 0], rot: [0, -16, 14] }, bones: { spine: [0, -4, 12], chest: [0, -4, 14], neck: [0, 6, 16], head: [0, 8, 22] }, ik: { ...H.carry } },
      // the knees give
      { t: 0.62, ease: 'inOutSine', hips: { pos: [-0.3, -0.5, 0], rot: [0, -10, 30] }, bones: { spine: [0, -2, 8], chest: [0, -2, 8], neck: [0, 4, 10], head: [0, 6, 14] }, ik: { ...NO_FEET } },
      // down on the back
      { t: 0.98, ease: 'inQuad', pose: 'game.koPose' },
      { t: 1.08, ease: 'outQuad', pose: 'game.koPose', hips: { pos: [0.22, -0.885, 0] } },
      { t: 1.5, ease: 'inOutSine', pose: 'game.koPose' },
    ],
    events: [{ t: 0.98, name: 'fall' }],
  });

  // ---- rest: seated meditation ---------------------------------------------------------------------------------------
  {
    const sit = H.sit;
    const legs = { thighR: [-52, -24, 84], thighL: [-52, -24, 84], shinR: [0, 0, -138], shinL: [0, 0, -132], footR: [0, 0, -30], footL: [0, 0, -30] };
    const armsRest = H.twin ? {} : { upperArmL: [-16, 8, 24], foreArmL: [0, 20, 62], handL: [0, 0, 0] };
    const seat = (du, lean, head) => ({
      hips: { pos: [-0.04, sit + du, 0], rot: [0, 0, -3] },
      bones: { spine: [0, 0, -4 + lean], chest: [0, 0, -2 + lean], neck: [0, 0, 6], head: [0, 0, head], ...legs, ...armsRest },
      ik: { ...H.restHands(du), ...NO_FEET },
      grip: 0, curl: [0.5, 1],
    });
    defineClip(`rpg.${id}.rest`, {
      duration: 4.4, loop: true, breath: 1.4, look: false, base: stance,
      keys: [
        { t: 0, ease: 'inOutSine', ...seat(0, 0, -6) },
        { t: 2.2, ease: 'inOutSine', ...seat(0.012, -1.5, -4) },
      ],
    });
  }
}

// KAEL: the great blade stays on the shoulder through the roll; seated, it leans on the shoulder
heroActions('kael', {
  T: 0.7, yaw: -24, twin: false, sit: -0.83,
  feet: { L: [0.36, 0, -0.16], R: [-0.36, 0, 0.2], yawL: 12, yawR: -40 },
  rollHand: (k) => ({ handR: { space: 'chest', pos: [0.2 - 0.06 * k, 0.02 - 0.1 * k, 0.26], aim: [-0.7, 0.66 - 0.3 * k, 0.26], up: [-0.66, -0.75, 0] } }),
  carry: { handR: { pos: [0.24, 0.98, 0.3], aim: [0.55, -0.82, 0.1], up: [0.82, 0.55, 0] } },
  restHands: (du) => ({ handR: { pos: [K_HAND.pos[0] + 0.02, K_HAND.pos[1] - 0.86 + du, K_HAND.pos[2] + 0.02], aim: [-0.5, 0.86, 0.08], up: [-0.86, -0.5, 0] } }),
});

// ISKA: blades tucked along the forearms; seated, they rest across the knees
heroActions('iska', {
  T: 0.56, yaw: -24, twin: true, sit: -0.81,
  feet: { L: [0.24, 0.02, -0.12], R: [-0.25, 0.02, 0.14], yawL: 14, yawR: -38 },
  rollHand: () => ({
    handR: iHand([0.16, 0.12, 0.22], [-0.3, 0.2, 0.93], [0.9, 0.3, 0.2], { space: 'chest' }),
    handL: iHand([0.16, 0.12, -0.22], [-0.3, 0.2, -0.93], [0.9, 0.3, -0.2], { space: 'chest' }),
  }),
  // right blade lowered; the left hand comes off its target (FK) to reach the mouth
  carry: { handR: iHand([0.12, 0.86, 0.3], [0.2, -0.9, 0.38], [0.95, 0.25, 0.1]), handL: { pos: [0.27, 0.96, -0.06], w: 0 } },
  restHands: (du) => ({
    handR: iHand([0.3, 0.3 + du, 0.3], [0.62, -0.1, 0.78], [0.2, 0.97, 0.1]),
    handL: iHand([0.3, 0.3 + du, -0.3], [0.62, -0.1, -0.78], [0.2, 0.97, -0.1]),
  }),
});

// VORN: the spear hugged along the body in the roll; seated, it stands against the shoulder
heroActions('vorn', {
  T: 0.62, yaw: -30, twin: false, sit: -0.88,
  feet: { L: [0.35, 0, -0.15], R: [-0.36, 0, 0.2], yawL: 12, yawR: -48 },
  rollHand: () => ({ handR: vSpear([0.1, -0.1, 0.3], [0.3, 0.9, 0.3], { space: 'chest' }) }),
  carry: { handR: vSpear([0.22, 0.98, 0.3], [0.5, 0.85, 0.05]) },
  restHands: (du) => ({ handR: vSpear([0.24, 0.84 + du, 0.34], [0.06, 0.99, -0.1]) }),
});
