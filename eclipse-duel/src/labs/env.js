// Environment lab: the arena 「천무대」 with two 1.9 m grey capsule dummies on the fight line (x = -2.5 / +2.5).
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
    /** close inspection: the gate and its name board, the hall, the gallery, lanterns, censer, wall reliefs, floor */
    inspGate(ctx, lab) { lookFrom(lab, [1.2, 1.7, 9.5], [0, 5.6, 20.5], 50); },
    inspBoard(ctx, lab) { lookFrom(lab, [0.6, 1.7, 15.2], [0.1, 6.9, 20.3], 34); },
    inspGateSide(ctx, lab) { lookFrom(lab, [-9.5, 1.7, 9.0], [-2, 5.0, 20.5], 55); },
    inspHall(ctx, lab) { lookFrom(lab, [-6.5, 1.7, 1.5], [-22, 5.2, -4.6], 55); },
    inspHallWreck(ctx, lab) { lookFrom(lab, [-9.5, 1.8, 8.5], [-22, 4.2, 3.0], 55); },
    inspHallEave(ctx, lab) { lookFrom(lab, [-9.0, 1.7, -7.0], [-18.0, 7.2, -13.8], 50); },
    inspGallery(ctx, lab) { lookFrom(lab, [7.5, 1.7, -4.0], [16.5, 5.2, -10.5], 55); },
    inspGalleryFallen(ctx, lab) { lookFrom(lab, [6.0, 1.7, 6.0], [13.2, 2.6, 13.0], 55); },
    inspLantern(ctx, lab) { lookFrom(lab, [-6.3, 1.25, -8.4], [-8.24, 1.35, -10.94], 42); },
    inspCenser(ctx, lab) { lookFrom(lab, [9.6, 1.3, -4.4], [12.1, 1.0, -6.2], 42); },
    inspWall(ctx, lab) { lookFrom(lab, [10.5, 1.3, 5.0], [15.2, 1.2, 8.0], 46); },
    inspStairs(ctx, lab) { lookFrom(lab, [4.5, 1.6, 11.0], [0.5, 1.4, 17.5], 50); },
    inspStele(ctx, lab) { lookFrom(lab, [10.4, 1.5, -2.0], [13.5, 1.5, -4.4], 40); },
    inspRack(ctx, lab) { lookFrom(lab, [11.0, 1.4, -0.5], [14.4, 1.0, -1.5], 46); },
    inspRim(ctx, lab) { lookFrom(lab, [3.0, 1.6, -9.5], [-2.0, 0.4, -15.0], 56); },
    inspPine(ctx, lab) { lookFrom(lab, [6.0, 1.6, -9.0], [14.5, 7.0, -17.0], 58); },
    inspImpact(ctx, lab) { lookFrom(lab, [-1.6, 1.6, -1.2], [-4.6, 0.1, -6.6], 46); },
    inspImpactTop(ctx, lab) { lookFrom(lab, [-2.6, 9.5, 0.5], [-4.4, 0, -6.2], 50); },
    inspVista(ctx, lab) { lookFrom(lab, [2.0, 1.4, -9.0], [-4.0, 1.0, -16.5], 50); },
    /** the floor straight from above (puddles must read as wet stone, not holes); the whole diagram from high up */
    topDown(ctx, lab) { lookFrom(lab, [-2.0, 9.0, 2.6], [-2.0, 0, 1.0], 50); },
    diagram(ctx, lab) { lookFrom(lab, [0, 30, 4.0], [0, 0, 0], 58); },
    diagramNear(ctx, lab) { lookFrom(lab, [0, 9.5, 5.5], [0, 0, -1.0], 62); },
    overviewN(ctx, lab) { lookFrom(lab, [0, 26, -34], [0, 2, 0], 55); },
    overviewW(ctx, lab) { lookFrom(lab, [30, 20, 6], [-6, 3, -2], 50); },
    /**
     * telephoto studies of the guardian statues: `statue(i)` whole figure from the terrace's rim, `statueHead(i)` the
     * mask and helmet, `statueStudy(i, yaw)` from 90 m in front of it at `yaw` degrees round
     */
    statue(ctx, lab, i = 0) { const s = ctx.env.statues[i]; lookFrom(lab, [s.position.x * 0.06, 1.8, -13.0], [s.position.x, s.position.y + s.height * 0.56, s.position.z], 17); },
    statueHead(ctx, lab, i = 0) { const s = ctx.env.statues[i]; lookFrom(lab, [s.position.x * 0.06, 1.8, -13.0], [s.head.x, s.head.y, s.head.z], 5.5); },
    statueStudy(ctx, lab, i = 0, yaw = 0, dist = 90) {
      const s = ctx.env.statues[i];
      const a = s.yaw + yaw * DEG;
      lookFrom(lab, [s.position.x + Math.sin(a) * dist, s.position.y + s.height * 0.55, s.position.z + Math.cos(a) * dist], [s.position.x, s.position.y + s.height * 0.5, s.position.z], 36);
    },
    statueHide(ctx, lab, i = 0, on = false) { ctx.env.statues[i].visible = on; },
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
    /**
     * 360-degree review: stand at (x, z) at eye height and look along `yaw` degrees (0 = toward -Z / the vista,
     * 90 = +X, 180 = +Z / the gate, -90 = -X / the hall). `turn(x, z, yaw, eye = 1.7, fov = 60, pitch = 4)`.
     */
    turn(ctx, lab, x = 0, z = 0, yaw = 0, eye = 1.7, fov = 60, pitch = 4) {
      const a = yaw * DEG, c = Math.cos(pitch * DEG);
      lookFrom(lab, [x, eye, z], [x + Math.sin(a) * c * 10, eye + Math.sin(pitch * DEG) * 10, z - Math.cos(a) * c * 10], fov);
    },
    /**
     * Third-person action-RPG framing: a dummy stands at (x, z), the camera 4.6 m behind and 2.3 m up, looking over
     * it along `yaw` (same convention as `turn`). The other dummy is parked off the terrace.
     */
    rpg(ctx, lab, x = 0, z = 0, yaw = 0, dist = 4.6, height = 2.3, fov = 50) {
      const a = yaw * DEG, fx = Math.sin(a), fz = -Math.cos(a);
      lab.dummies[0].position.set(x, 0.95, z);
      lab.dummies[1].position.set(0, -50, 0);
      ctx.env.setFocus(x);
      lookFrom(lab, [x - fx * dist, height, z - fz * dist], [x + fx * 3, 1.5, z + fz * 3], fov);
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
