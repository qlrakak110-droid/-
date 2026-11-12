// Environment lab: the Eclipse Ruins arena with two 1.9 m grey capsule dummies on the fight line (x = -2.5 / +2.5).
// Scenarios frame the fight camera (near / mid / far), cinematic low / high / side angles, mood dimming and pulses.
//   node tools/shot.mjs env --do "__ED.lab.play('gameMid')" --at 1.2 --each "__ED.lab.play('prime')" --out shots/env/gameMid
// `game*` scenarios frame the dummies with the game's own fight camera (src/cam); the others are fixed lab views.
import * as THREE from 'three';
import { createLab } from '../core/lab.js';
import { DEG } from '../core/math.js';
import { createEnvironment } from '../env/index.js';
import { createCameraDirector } from '../cam/index.js';
import * as shots from '../cam/shots.js';

/** Hand the camera back to the lab orbit (the real fight director, if a `game*` scenario started it, goes idle). */
function freeCam(lab) { if (lab.ctx.cam) lab.ctx.cam.setMode('free', 0); }
/** The real camera director on the dummies (created on first use). */
function director(ctx, lab) {
  if (!ctx.cam) {
    const chest = (m) => { const v = new THREE.Vector3(); return () => v.set(m.position.x, 1.35, m.position.z); };
    createCameraDirector(ctx).setTargets(chest(lab.dummies[0]), chest(lab.dummies[1]));
    ctx.cam.fight.breathe = 0;
  }
  return ctx.cam;
}
/**
 * The cinematic vocabulary on the dummies (src/cam/shots.js), held on its last frame: advance the clock to sample a
 * moment of the move. `anchor` 1 mirrors the shot (authored around P2). Handheld drift is switched off so captures
 * are repeatable.
 */
function cine(ctx, lab, list, anchor = 0) {
  lab.dummies[0].position.x = -2.5;
  lab.dummies[1].position.x = 2.5;
  ctx.env.setFocus(0);
  const cam = director(ctx, lab);
  cam.setMode('fight', 0);
  cam.snap();
  cam.play(list.map((s) => ({ ...s, handheld: 0 })), { anchor, blendOut: false, hud: false });
}
/** Flagship review set: [name, shot list, anchor, sample time (s)] (README: "Cinematic review"). */
const CINE = {
  heroL: () => [[shots.heroPushIn()], 0, 0.9],
  heroR: () => [[shots.heroPushIn()], 1, 0.9],
  otsL: () => [[shots.overShoulder()], 0, 1.0],
  otsR: () => [[shots.overShoulder()], 1, 1.0],
  sideL: () => [[{ dur: 2, space: 'mid', orbit: { pivot: [0, 1.25, 0], from: -68, to: -68, radius: 7.2, height: 1.45 }, from: { fov: 38 } }], 0, 0.5],
  sideR: () => [[{ dur: 2, space: 'mid', orbit: { pivot: [0, 1.25, 0], from: 68, to: 68, radius: 7.2, height: 1.45 }, from: { fov: 38 } }], 0, 0.5],
  sideLow: () => [[{ dur: 2, space: 'mid', orbit: { pivot: [0, 1.7, 0], from: -55, to: -55, radius: 5.5, height: 0.45 }, from: { fov: 44 } }], 0, 0.5],
  crane: () => [[shots.wideEstablishing()], 0, 1.6],
  craneHigh: () => [[shots.topDownSlam({ height: [9, 8] })], 0, 0.5],
  orbit: () => [[shots.orbitSweep()], 0, 1.25],
  skim: () => [[shots.groundSkim()], 0, 0.85],
  face: () => [[shots.faceCloseUp()], 0, 1.0],
  dutch: () => [[shots.dutchDrift()], 0, 1.4],
};
/** Fight-camera framing: camera at (x, h, d) looking at (x, look, 0). */
function fight(lab, d, h, look, x = 0, fov = 40) {
  freeCam(lab);
  lab.view({ target: [x, look, 0], dist: Math.hypot(d, h - look), yaw: 0, pitch: Math.atan2(h - look, d) / DEG, fov });
}
/** Look from an explicit camera position at a target. */
function lookFrom(lab, from, at, fov = 40) {
  freeCam(lab);
  const dx = from[0] - at[0], dy = from[1] - at[1], dz = from[2] - at[2];
  const dist = Math.hypot(dx, dy, dz);
  lab.view({ target: at, dist, yaw: Math.atan2(dx, dz) / DEG, pitch: Math.asin(dy / dist) / DEG, fov });
}
/** The game's own fight camera (src/cam) framing the dummies `sep` metres apart around `mid`; snapped, no drift. */
function gameCam(ctx, lab, sep, mid = 0) {
  lab.dummies[0].position.x = mid - sep / 2;
  lab.dummies[1].position.x = mid + sep / 2;
  ctx.env.setFocus(mid);
  const cam = director(ctx, lab);
  if (cam.mode === 'cine') cam.stop(0);
  cam.setMode('fight', 0);
  cam.snap();
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
    // ground the dummies (what the game binding does per fighter every frame)
    const foot = new THREE.Vector3();
    ctx.onUpdate(() => { lab.dummies.forEach((m, i) => env.setContact(i, foot.set(m.position.x, m.position.y - 0.95, m.position.z), 0.32, 1.9)); }, ctx.ORDER.GAME);
    lab.env = env;
    env.prewarm();
  },
  scenarios: {
    /** render + copy the frame so the high-tier puddle reflection is current (use in --each) */
    prime(ctx) { ctx.env.captureReflection(true); },
    /** the real fight camera (src/cam) at near / mid / far separation; `gameAt(x)` = mid separation centred on x */
    gameNear(ctx, lab) { gameCam(ctx, lab, 1.4); },
    gameMid(ctx, lab) { gameCam(ctx, lab, 4.5); },
    gameFar(ctx, lab) { gameCam(ctx, lab, 9); },
    gameAt(ctx, lab, x = 6) { gameCam(ctx, lab, 4.5, x); },
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
    sideL(ctx, lab) { freeCam(lab); lab.view({ target: [0, 1.2, 0], dist: 9, yaw: -60, pitch: 4, fov: 40 }); },
    sideR(ctx, lab) { freeCam(lab); lab.view({ target: [0, 1.2, 0], dist: 9, yaw: 60, pitch: 4, fov: 40 }); },
    sideLowL(ctx, lab) { freeCam(lab); lab.view({ target: [0, 1.6, 0], dist: 6, yaw: -55, pitch: -8, fov: 45 }); },
    overview(ctx, lab) { lookFrom(lab, [0, 22, 30], [0, 0, -8], 50); },
    /** close inspection of the architecture: podium frieze + cornice, a capital and arch, the tier, a brazier shrine */
    inspWall(ctx, lab) { lookFrom(lab, [9.0, 1.5, -5.2], [13.6, 2.2, -7.9], 42); },
    inspCapital(ctx, lab) { lookFrom(lab, [6.6, 1.8, -9.0], [11.5, 8.6, -13.2], 46); },
    inspTier(ctx, lab) { lookFrom(lab, [-3.5, 7.5, -1.5], [-20.0, 6.0, -12.5], 46); },
    inspBrazier(ctx, lab) { lookFrom(lab, [6.6, 0.85, -8.6], [8.3, 0.55, -10.9], 40); },
    inspImpact(ctx, lab) { lookFrom(lab, [-1.6, 1.6, -1.2], [-4.6, 0.1, -6.6], 46); },
    inspTierHigh(ctx, lab, side = -1) { lookFrom(lab, [side * -3, 12.5, 3], [side * 22, 5.5, -8], 52); },
    inspImpactTop(ctx, lab) { lookFrom(lab, [-2.6, 9.5, 0.5], [-4.4, 0, -6.2], 50); },
    inspVista(ctx, lab) { lookFrom(lab, [2.0, 1.4, -9.0], [-4.0, 1.0, -16.5], 50); },
    /** the toppled column and its upside-down capital by the left wall; the fallen drums by the right wall */
    inspTopple(ctx, lab) { lookFrom(lab, [-7.0, 1.7, 3.4], [-11.8, 0.5, -1.4], 50); },
    inspFallenR(ctx, lab) { lookFrom(lab, [8.4, 2.4, 0.6], [13.0, 0.8, -5.0], 50); },
    /** the broken kerb across the vista, from the arena side (nothing may bridge a fallen course) */
    inspKerb(ctx, lab) { lookFrom(lab, [0, 1.4, -8.0], [0, 0.6, -15.5], 60); },
    /** the floor straight from above (puddles must read as wet stone, not holes) */
    topDown(ctx, lab) { lookFrom(lab, [-2.0, 9.0, 2.6], [-2.0, 0, 1.0], 50); },
    /** telephoto hero shots of the colossi from the vista edge: whole figure / cowl and hands */
    colossusL(ctx, lab) { lookFrom(lab, [-2, 1.8, -13.5], [-53.7, 10.5, -223.6], 15); },
    colossusR(ctx, lab) { lookFrom(lab, [2, 1.8, -13.5], [61.5, 10.5, -221.6], 15); },
    colossusStudy(ctx, lab, yaw = 0) { const a = Math.atan2(53.7, 223.6) + yaw; lookFrom(lab, [-53.7 + Math.sin(a) * 75, 16, -223.6 + Math.cos(a) * 75], [-53.7, 14, -223.6], 32); },
    colossusHead(ctx, lab) { lookFrom(lab, [-2, 1.8, -13.5], [-53.0, 18.5, -223.8], 6); },
    /** telephoto on the far left colossus (inspect the far silhouettes) */
    colossus(ctx, lab) { lookFrom(lab, [-1, 2.4, 4], [-53.7, 16, -223.6], 12); },
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
    /**
     * `cine(name)`: a held cinematic from the review set (CINE: heroL heroR otsL otsR sideL sideR sideLow crane
     * craneHigh orbit skim face dutch). Returns the sample time to advance before capturing.
     */
    cine(ctx, lab, name) {
      const [list, anchor, at] = CINE[name]();
      cine(ctx, lab, list, anchor);
      return at;
    },
    cineList() { return Object.keys(CINE); },
  },
});
