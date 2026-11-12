// Environment lab: the Eclipse Ruins arena with two 1.9 m grey capsule dummies on the fight line (x = -2.5 / +2.5).
// Scenarios frame the fight camera (near / mid / far), cinematic low / high / side angles, mood dimming and pulses.
//   node tools/shot.mjs env --do "__ED.lab.play('mid')" --each "__ED.lab.play('prime')" --out shots/env/mid
import * as THREE from 'three';
import { createLab } from '../core/lab.js';
import { DEG } from '../core/math.js';
import { createEnvironment } from '../env/index.js';

/** Fight-camera framing: camera at (x, h, d) looking at (x, look, 0). */
function fight(lab, d, h, look, x = 0, fov = 40) {
  lab.view({ target: [x, look, 0], dist: Math.hypot(d, h - look), yaw: 0, pitch: Math.atan2(h - look, d) / DEG, fov });
}
/** Look from an explicit camera position at a target. */
function lookFrom(lab, from, at, fov = 40) {
  const dx = from[0] - at[0], dy = from[1] - at[1], dz = from[2] - at[2];
  const dist = Math.hypot(dx, dy, dz);
  lab.view({ target: at, dist, yaw: Math.atan2(dx, dz) / DEG, pitch: Math.asin(dy / dist) / DEG, fov });
}

createLab({
  stage: false,
  view: { target: [0, 1.2, 0], dist: 8.5, yaw: 0, pitch: 2.7, fov: 40 },
  setup(ctx, lab) {
    const hash = ctx.flags.detail !== undefined ? Number(ctx.flags.detail) : undefined;
    const env = createEnvironment(ctx, { detail: hash });
    const mat = new THREE.MeshStandardMaterial({ name: 'lab.dummy', color: 0x8d8f94, roughness: 0.55, metalness: 0.0 });
    const geo = new THREE.CapsuleGeometry(0.3, 1.3, 8, 20);
    lab.dummies = [-2.5, 2.5].map((x) => {
      const m = new THREE.Mesh(geo, mat);
      m.position.set(x, 0.95, 0);
      m.castShadow = true;
      m.receiveShadow = true;
      ctx.scene.add(m);
      return m;
    });
    lab.dummyMat = mat;
    lab.env = env;
    env.prewarm();
  },
  scenarios: {
    /** render + copy the frame so the high-tier puddle reflection is current (use in --each) */
    prime(ctx) { ctx.env.captureReflection(true); },
    near(ctx, lab) { fight(lab, 6, 1.35, 1.15); },
    mid(ctx, lab) { fight(lab, 8.5, 1.6, 1.2); },
    far(ctx, lab) { fight(lab, 11, 1.95, 1.3); },
    /** fighters pushed to the left edge, camera following */
    edgeL(ctx, lab) { lab.dummies[0].position.x = -8.4; lab.dummies[1].position.x = -4.4; ctx.env.setFocus(-6.4); fight(lab, 8.5, 1.6, 1.2, -6.4); },
    edgeR(ctx, lab) { lab.dummies[0].position.x = 4.4; lab.dummies[1].position.x = 8.4; ctx.env.setFocus(6.4); fight(lab, 8.5, 1.6, 1.2, 6.4); },
    close(ctx, lab) { lab.dummies[0].position.x = -0.8; lab.dummies[1].position.x = 0.8; fight(lab, 6, 1.35, 1.15); },
    reset(ctx, lab) { lab.dummies[0].position.x = -2.5; lab.dummies[1].position.x = 2.5; ctx.env.setFocus(0); fight(lab, 8.5, 1.6, 1.2); },
    /** cinematic: low hero angle on P1 looking up */
    low(ctx, lab) { lookFrom(lab, [-0.9, 0.35, 3.0], [-2.5, 1.55, 0], 42); },
    /** cinematic: ground-level wide, both fighters against the eclipse */
    lowWide(ctx, lab) { lookFrom(lab, [0.6, 0.28, 6.2], [0, 2.6, 0], 50); },
    /** cinematic: high crane shot */
    high(ctx, lab) { lookFrom(lab, [2.5, 7.5, 7.5], [0, 0.8, 0], 40); },
    /** cinematic: over-the-shoulder close on P2 */
    ots(ctx, lab) { lookFrom(lab, [-3.6, 1.75, 1.3], [2.5, 1.5, 0], 36); },
    sideL(ctx, lab) { lab.view({ target: [0, 1.2, 0], dist: 9, yaw: -60, pitch: 4, fov: 40 }); },
    sideR(ctx, lab) { lab.view({ target: [0, 1.2, 0], dist: 9, yaw: 60, pitch: 4, fov: 40 }); },
    sideLowL(ctx, lab) { lab.view({ target: [0, 1.6, 0], dist: 6, yaw: -55, pitch: -8, fov: 45 }); },
    overview(ctx, lab) { lookFrom(lab, [0, 22, 30], [0, 0, -8], 50); },
    /** telephoto on the far left colossus (inspect the far silhouettes) */
    colossus(ctx, lab) { lookFrom(lab, [0, 1.6, 8.5], [-57, 24, -149], 16); },
    mood(ctx) { ctx.env.setMood({ darken: 0.85, tint: 0x8fa0ff, duration: 0.3 }); },
    moodWarm(ctx) { ctx.env.setMood({ darken: 0.8, tint: 0xff9a70, duration: 0.3 }); },
    moodOff(ctx) { ctx.env.setMood(null); },
    pulse(ctx) { ctx.env.pulse([0.6, 0, 0.4], [3.0, 1.2, 0.3], 1.2); },
    pulseFrost(ctx) { ctx.env.pulse([-2.0, 0, 0.2], [0.6, 1.8, 4.0], 1.0); },
    metal(ctx, lab) { lab.dummyMat.metalness = 1; lab.dummyMat.roughness = 0.28; lab.dummyMat.color.setRGB(0.75, 0.75, 0.78); },
    /** a few hot HDR spheres standing in for VFX (check that effects pop against the backdrop) */
    vfx(ctx) {
      const cols = [[8, 3, 0.6], [1.5, 4, 8], [5, 3.5, 9]];
      cols.forEach((c, i) => {
        const m = new THREE.Mesh(new THREE.SphereGeometry(0.16, 16, 12), new THREE.MeshBasicMaterial({ color: new THREE.Color(c[0], c[1], c[2]) }));
        m.position.set(-1.4 + i * 1.4, 1.3, 0.3);
        ctx.scene.add(m);
      });
    },
    stats(ctx) { return ctx.env.stats(); },
  },
});
