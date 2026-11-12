// ISKA look-dev lab: the Froststar Oracle under the art lab's moody lighting rig (warm key, cold rims, ember bounce,
// procedural studio environment), with framing scenarios for turntables, close-ups, combat poses (lab-only poses with her
// twin crescents: real clips come with her move set), spins that make the cape tails / tabard / ribbons flow, a
// silhouette line-up against KAEL, the arena readability check and rig QA with her proportions.
//
//   node tools/shot.mjs art_iska --do "__ED.lab.play('bust')" --at 0.5 --out shots/art/iska_bust
//   node tools/shot.mjs art_iska --do "__ED.lab.play('turntable')" --at 0,0.25,0.5,0.75,1,1.25,1.5,1.75 --sheet-only --out shots/art/iska_turn
//   node tools/shot.mjs art_iska --do "__ED.lab.play('spin')" --at 0.2,0.3,0.4,0.5 --sheet-only --out shots/art/iska_spin
//   node tools/shot.mjs art_iska --hash arena --do "__ED.lab.play('fight')" --at 1 --out shots/art/iska_arena_fight
//
// Flags: #arena (Eclipse Ruins backdrop + lights), #tex=256|512, #q=low|mid|high (quality tier: cloth grid size).
// Scenarios: full, bust, face, turntable(every), back, side, fight, pose(name, yaw, dist), spin(yaw), combat(name),
// silhouette, lineup(lit), glow, joints, stats, qa(clips).

import * as THREE from 'three';
import { createLab, ORDER } from '../core/lab.js';
import { createEnvironment } from '../env/index.js';
import { createCharacter, definePose, defineClip } from '../char/index.js';
import { configureTextureSets } from '../char/materials.js';
import { iska } from '../fighters/iska/design.js';
import { kael } from '../fighters/kael/design.js';
import '../char/clips/demo.js';
import { auditClip } from '../char/qa.js';

// ---- lab-only poses / clips with the twin crescents (fighter frame, ISKA's proportions) --------------------------------------
// Hand IK: pos = fist centre, aim = where the blade points out of the thumb side, up = the blade's back (the crescent curves
// toward `up`). Feet: sole point under the ankle; toes slightly pointed for her light, on-the-toes stance.
const FOOT = (pos, yaw, pitch = 0) => ({ pos, rot: [0, yaw, pitch] });
definePose('artiska.stance', {
  hips: { pos: [-0.03, -0.07, 0], rot: [0, -22, 0] },
  bones: { spine: [2, -4, -2], chest: [0, -6, -1], neck: [0, 6, 2], head: [0, 10, -4] },
  ik: {
    handR: { pos: [0.2, 0.9, 0.11], aim: [0.5, -0.66, -0.56], up: [0.86, 0.5, 0.1] },
    handL: { pos: [0.25, 0.93, -0.07], aim: [0.52, -0.62, 0.58], up: [0.84, 0.54, -0.1] },
    footL: FOOT([0.22, 0.022, -0.12], 14, -16), footR: FOOT([-0.24, 0.022, 0.14], -38, -16),
  },
  grip: 0, curl: [1, 1],
});
// wide cross-body slash: right blade extended forward-high, left blade trailing low behind, lunge
definePose('artiska.slash', {
  hips: { pos: [0.08, -0.14, 0], rot: [-4, 30, -6] },
  bones: { spine: [-4, 14, -10], chest: [-6, 16, -6], neck: [0, -14, 6], head: [0, -20, 4] },
  ik: {
    handR: { pos: [0.62, 1.18, -0.12], aim: [0.62, 0.22, -0.75], up: [0.2, 0.96, 0.1] },
    handL: { pos: [-0.36, 0.9, -0.22], aim: [-0.8, -0.3, -0.5], up: [0.1, 0.9, -0.4] },
    footL: FOOT([0.46, 0, -0.14], 12), footR: FOOT([-0.36, 0.03, 0.16], -46, -22),
  },
  grip: 0, curl: [1, 1],
});
// crossed guard: both blades raised in an X before the face
definePose('artiska.guard', {
  hips: { pos: [-0.04, -0.1, 0], rot: [0, -20, 0] },
  bones: { spine: [0, -6, -6], chest: [0, -8, -4], neck: [0, 8, 6], head: [0, 12, 2] },
  ik: {
    handR: { pos: [0.3, 1.36, 0.08], aim: [0.3, 0.75, -0.6], up: [0.9, -0.1, 0.4] },
    handL: { pos: [0.3, 1.34, -0.04], aim: [0.3, 0.75, 0.6], up: [0.9, -0.1, -0.4] },
    footL: FOOT([0.26, 0, -0.13], 14), footR: FOOT([-0.28, 0, 0.15], -44),
  },
  grip: 0, curl: [1, 1],
});
// pirouette with both blades out (makes the tails, tabard and ribbons flare): one full turn on the left foot. During
// the turn the feet ride the pelvis ('hips' space: pivot foot under the left hip, right foot drawn up to the knee).
const PIVOT = (y) => ({ space: 'hips', pos: [0.03, y, -0.1], rot: [0, 0, -18] });
const PASSE = (y) => ({ space: 'hips', pos: [0.1, y + 0.36, 0.05], rot: [0, -20, -50] });
const ARMS_OUT = (k) => ({
  handR: { space: 'chest', pos: [0.05 + 0.03 * k, -0.02, 0.5], aim: [0.2, 0.1, 1], up: [0, 1, 0] },
  handL: { space: 'chest', pos: [0.05 + 0.03 * k, -0.02, -0.5], aim: [0.2, 0.1, -1], up: [0, 1, 0] },
});
defineClip('artiska.spin', {
  duration: 0.9, breath: 0,
  keys: [
    { t: 0, pose: 'artiska.stance' },
    { t: 0.12, ease: 'outCubic', hips: { pos: [-0.02, -0.06, 0], rot: [0, -60, 0] }, ik: { ...ARMS_OUT(0), footL: PIVOT(-0.945), footR: PASSE(-0.945) } },
    { t: 0.55, ease: 'inOutSine', hips: { pos: [0.0, -0.03, 0], rot: [0, 300, 0] }, ik: { ...ARMS_OUT(1), footL: PIVOT(-0.975), footR: PASSE(-0.975) } },
    // the slash pose's hips yaw (30) plus the full turn: per-component interpolation must not unwind backwards
    { t: 0.9, ease: 'outQuad', pose: 'artiska.slash', hips: { pos: [0.08, -0.14, 0], rot: [-4, 390, -6] } },
  ],
});
// joint torture pose (deformation check of the bodysuit and the plate overlaps)
definePose('artiska.joints', {
  hips: { pos: [0, -0.12, 0], rot: [0, -20, 0] },
  bones: {
    spine: [0, 20, -10], chest: [6, 22, -8], neck: [0, -20, 10], head: [10, -25, 12],
    shoulderR: [-12, 0, 8], upperArmR: [-75, 20, 35], foreArmR: [0, 70, 130], handR: [30, 60, -20],
    shoulderL: [-15, 0, 0], upperArmL: [-10, -30, 165], foreArmL: [0, -60, 95], handL: [-20, 0, 40],
    thighR: [-10, 15, 105], shinR: [0, 0, -135], footR: [0, 0, -30],
    thighL: [-35, -20, -25], shinL: [0, 0, -60], footL: [0, 0, 20],
  },
  grip: 0, curl: [0.3, 1],
});

/** Procedural studio environment: dark dome, warm key softbox, cold rim strips, ember floor bounce (as the art lab). */
function studioEnv(renderer) {
  const scene = new THREE.Scene();
  scene.add(new THREE.Mesh(new THREE.SphereGeometry(30, 48, 24), new THREE.ShaderMaterial({
    side: THREE.BackSide, depthWrite: false,
    vertexShader: 'varying vec3 vP; void main(){ vP = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }',
    fragmentShader: `varying vec3 vP; void main(){
      float y = vP.y;
      vec3 zen = vec3(0.012, 0.016, 0.026), hor = vec3(0.05, 0.045, 0.05), flo = vec3(0.012, 0.008, 0.006);
      vec3 c = y > 0.0 ? mix(hor, zen, pow(y, 0.5)) : mix(hor * 0.6, flo, pow(-y, 0.35));
      c += vec3(0.12, 0.05, 0.015) * pow(max(0.0, 1.0 - abs(y + 0.08) * 5.0), 3.0) * max(0.0, vP.z);
      gl_FragColor = vec4(c, 1.0); }`,
  })));
  const panel = (w, h, col, pos, look = [0, 1.2, 0]) => {
    const m = new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshBasicMaterial({ color: new THREE.Color(...col), side: THREE.DoubleSide }));
    m.position.set(...pos); m.lookAt(...look); scene.add(m);
  };
  panel(5, 3.5, [2.2, 1.85, 1.5], [6, 8, 7]);
  panel(1.2, 9, [0.8, 1.1, 1.9], [-9, 3, -6]);
  panel(1.2, 9, [0.6, 0.85, 1.5], [9, 3, -7]);
  panel(10, 1.0, [0.9, 0.38, 0.12], [0, -0.6, 9]);
  panel(3, 3, [0.25, 0.3, 0.42], [0, 12, 0]);
  const pmrem = new THREE.PMREMGenerator(renderer);
  const tex = pmrem.fromScene(scene, 0.02).texture;
  pmrem.dispose();
  return tex;
}

/** lab.view with the target offset by the character's root position (studio x = 0, arena x = -2.5). */
function frame(lab, v) {
  const x = lab.char.root.position.x;
  lab.view({ ...v, target: [v.target[0] + x, v.target[1], v.target[2]] });
}

createLab({
  stage: false,
  view: { target: [0, 0.95, 0], dist: 5.0, yaw: 28, pitch: 5, fov: 35 },
  async setup(ctx, lab) {
    const { scene, renderer } = ctx;
    if (ctx.flags.tex) configureTextureSets({ size: Number(ctx.flags.tex) });
    lab.arena = !!ctx.flags.arena;
    if (lab.arena) {
      createEnvironment(ctx, {});
    } else {
      scene.background = new THREE.Color(0x07080c);
      scene.fog = new THREE.FogExp2(0x07080c, 0.03);
      scene.environment = studioEnv(renderer);
      scene.environmentIntensity = 0.75;
      const key = new THREE.DirectionalLight(new THREE.Color(1.0, 0.86, 0.72), 3.4);
      key.position.set(4, 7, 5.5);
      key.castShadow = !!ctx.quality.shadows;
      if (key.castShadow) {
        key.shadow.mapSize.set(2048, 2048);
        const c = key.shadow.camera; c.left = -3; c.right = 3; c.top = 3.5; c.bottom = -1; c.near = 1; c.far = 25;
        key.shadow.bias = -0.0003; key.shadow.normalBias = 0.015;
      }
      const rim = new THREE.DirectionalLight(new THREE.Color(0.55, 0.72, 1.0), 5.0);
      rim.position.set(-5, 4.5, -6);
      const rim2 = new THREE.DirectionalLight(new THREE.Color(0.5, 0.62, 1.0), 2.6);
      rim2.position.set(5.5, 3, -5);
      const bounce = new THREE.DirectionalLight(new THREE.Color(1.0, 0.42, 0.14), 0.7);
      bounce.position.set(1, -2, 4);
      const hemi = new THREE.HemisphereLight(new THREE.Color(0.16, 0.19, 0.28), new THREE.Color(0.08, 0.04, 0.02), 0.35);
      scene.add(key, rim, rim2, bounce, hemi, key.target);
    }
    lab.bg = { background: scene.background, fog: scene.fog };
    const floor = new THREE.Mesh(new THREE.CircleGeometry(12, 64), new THREE.MeshLambertMaterial({ color: 0x0a0a0c }));
    floor.rotation.x = -Math.PI / 2; floor.receiveShadow = true;
    floor.visible = !lab.arena;
    scene.add(floor);
    lab.floor = floor;

    const char = createCharacter(ctx, iska, { name: 'iska' });
    lab.glow = iska.attach(char);
    char.play('artiska.stance', { fade: 0 });
    char.update(0, 0);
    lab.char = char;
    window.__ED.char = char;
    console.log('[ed] art_iska', JSON.stringify(char.stats));
    lab.kael = null;
    const st = { spin: null, t: 0, hold: null };
    lab.st = st;
    ctx.onUpdate((dg, dr) => {
      st.t += dg;
      if (st.spin) lab.view({ yaw: st.spin.yaw0 + Math.floor(st.t / st.spin.every + 1e-6) * st.spin.step });
      if (st.hold !== null) char.setClipTime(st.hold);
      char.update(dg, dr);
      if (lab.kael && lab.kael.root.visible) lab.kael.update(dg, dr);
    }, ORDER.CHAR);
  },
  scenarios: {
    full(ctx, lab, yaw = 28) { reset(lab); frame(lab, { target: [0, 0.95, 0], dist: 4.7, yaw, pitch: 5, fov: 35 }); },
    bust(ctx, lab, yaw = 30) { reset(lab); frame(lab, { target: [0.02, 1.5, 0], dist: 1.3, yaw, pitch: 3, fov: 35 }); },
    face(ctx, lab, yaw = 18) { reset(lab); frame(lab, { target: [0.04, 1.64, 0], dist: 0.72, yaw, pitch: 1, fov: 35 }); },
    turntable(ctx, lab, every = 0.25) { reset(lab); lab.st.t = 0; lab.st.spin = { yaw0: 0, step: 45, every }; frame(lab, { target: [0, 0.95, 0], dist: 4.7, yaw: 0, pitch: 4, fov: 35 }); },
    back(ctx, lab) { reset(lab); frame(lab, { target: [0, 1.0, 0], dist: 3.4, yaw: 200, pitch: 8, fov: 35 }); },
    side(ctx, lab) { reset(lab); frame(lab, { target: [0, 0.95, 0], dist: 4.4, yaw: 90, pitch: 3, fov: 35 }); },
    fight(ctx, lab) {
      reset(lab);
      if (lab.arena) lab.view({ target: [-1.2, 1.15, 0], dist: 6.4, yaw: 0, pitch: 5, fov: 40 });
      else lab.view({ target: [0, 1.1, 0], dist: 7.2, yaw: 0, pitch: 6, fov: 40 });
    },
    /** Hold a lab pose (artiska.stance / slash / guard / joints, or any clip at t = 0): camera yaw / distance / target height. */
    pose(ctx, lab, name = 'artiska.slash', yaw = 20, dist = 4.2, ty = 1.0) {
      reset(lab, name);
      frame(lab, { target: [0.15, ty, 0], dist, yaw, pitch: 4, fov: 35 });
    },
    /** Pirouette into the slash: capture at 0.2-0.6 s to see the cloth / ribbons flare. */
    spin(ctx, lab, yaw = 15, dist = 4.4) {
      reset(lab);
      lab.char.play('artiska.spin', { fade: 0, restart: true });
      frame(lab, { target: [0.05, 1.0, 0], dist, yaw, pitch: 4, fov: 35 });
    },
    combat(ctx, lab, clip = 'demo.combo1', t = 0.25, yaw = 20) {
      reset(lab, clip);
      lab.st.hold = t;
      frame(lab, { target: [0.2, 1.0, 0], dist: 4.4, yaw, pitch: 4, fov: 35 });
    },
    silhouette(ctx, lab, withKael = false) {
      reset(lab);
      if (withKael) placeKael(ctx, lab);
      ctx.scene.background = new THREE.Color(0xd8d8d8);
      ctx.scene.fog = null;
      lab.floor.visible = false;
      lab.sil = { env: ctx.scene.environmentIntensity, lights: [] };
      ctx.scene.traverse((o) => { if (o.isLight) { lab.sil.lights.push([o, o.intensity]); o.intensity = 0; } });
      ctx.scene.environmentIntensity = 0;
      const chars = [lab.char, ...(withKael ? [lab.kael] : [])];
      lab.sil.chars = chars;
      for (const c of chars) {
        if (c.glow) c.glow.gain = 0;
        for (const m of Object.values(c.materials)) { m.userData.kit.uRim.value.w += 100; m.userData.kit.uGlowScale.value = 0; }
      }
      lab.view(withKael ? { target: [0, 1.0, 0], dist: 6.6, yaw: 0, pitch: 3, fov: 35 } : { target: [0, 1.0, 0], dist: 5.4, yaw: 0, pitch: 3, fov: 35 });
    },
    /** ISKA next to KAEL (lit): scale, silhouette and palette contrast. */
    lineup(ctx, lab) {
      reset(lab);
      placeKael(ctx, lab);
      lab.view({ target: [0, 1.0, 0], dist: 6.2, yaw: 10, pitch: 4, fov: 35 });
    },
    glow(ctx, lab) { reset(lab); lab.glow.flare('all', 2.5, 0.8); frame(lab, { target: [0.02, 1.4, 0], dist: 2.0, yaw: 30, pitch: 3, fov: 35 }); },
    joints(ctx, lab, yaw = 30) { reset(lab, 'artiska.joints'); frame(lab, { target: [0, 1.0, 0], dist: 3.6, yaw, pitch: 5, fov: 35 }); },
    stats(ctx, lab) { return { ...lab.char.stats }; },
    /** Rig QA (src/char/qa.js) of ISKA's proportions + crescents over the demo clips and her lab poses. */
    qa(ctx, lab, clips = ['demo.idle', 'demo.guard', 'demo.walkF', 'demo.combo1', 'demo.combo2', 'demo.combo3', 'demo.slam', 'artiska.spin']) {
      const out = {};
      for (const c of clips) {
        const a = auditClip(lab.char, c);
        out[c] = {
          nan: a.nan, floor: Object.fromEntries(Object.entries(a.floor).map(([k, v]) => [k, v.min])),
          below: Object.fromEntries(Object.entries(a.floor).filter(([, v]) => v.below > 0).map(([k, v]) => [k, v.below])),
          hits: a.intersections.slice(0, 5).map((x) => x.pair + ':' + x.depth),
          feet: { maxDrift: a.feet.maxDrift, maxSlide: a.feet.maxSlide },
          limits: Array.isArray(a.limits) ? a.limits.length : Object.keys(a.limits || {}).length,
          cpu: a.cpu.mean,
        };
      }
      reset(lab);
      return out;
    },
  },
});

function placeKael(ctx, lab) {
  if (!lab.kael) { lab.kael = createCharacter(ctx, kael, { name: 'kael' }); kael.attach(lab.kael); }
  lab.kael.setVisible(true);
  lab.kael.root.position.set(1.15, 0, 0); lab.kael.setFacing(-1); lab.kael.teleport();
  lab.kael.play('demo.idle', { fade: 0, restart: true });
  lab.char.root.position.set(-1.15, 0, 0); lab.char.teleport();
}

function reset(lab, pose = 'artiska.stance') {
  const ctx = lab.ctx;
  lab.st.spin = null; lab.st.hold = null;
  ctx.scene.background = lab.bg.background;
  ctx.scene.fog = lab.bg.fog;
  if (lab.sil) {
    for (const [l, i] of lab.sil.lights) l.intensity = i;
    ctx.scene.environmentIntensity = lab.sil.env;
    for (const c of lab.sil.chars) {
      if (c.glow) c.glow.gain = 1;
      for (const m of Object.values(c.materials)) { m.userData.kit.uRim.value.w -= 100; m.userData.kit.uGlowScale.value = 1; }
    }
    lab.sil = null;
  }
  if (lab.kael) lab.kael.setVisible(false);
  lab.floor.visible = !lab.arena;
  lab.char.setVisible(true);
  lab.char.root.position.set(lab.arena ? -2.5 : 0, 0, 0);
  lab.char.setFacing(1);
  lab.char.teleport();
  lab.char.play(pose, { fade: 0, restart: true });
}

