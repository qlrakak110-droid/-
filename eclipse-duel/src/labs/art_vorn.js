// VORN art lab: look-dev of the Stormcaller Lancer under the art lab's lighting rig (warm key, cold rims, ember bounce,
// procedural studio environment) or the real arena (#arena), with lab-only spear poses (clips belong to the fighter
// content team: these exist to judge the design, the two-handed grip points, foot contact and deformation).
//
//   node tools/shot.mjs art_vorn --do "__ED.lab.play('bust')" --at 0.5 --out shots/art/vorn_bust
//   node tools/shot.mjs art_vorn --do "__ED.lab.play('turntable')" --at 0,0.25,0.5,0.75,1,1.25,1.5,1.75 --sheet-only --out shots/art/vorn_turn
//   node tools/shot.mjs art_vorn --do "__ED.lab.play('pose','vornlab.guard')" --at 0.5 --out shots/art/vorn_guard
//   node tools/shot.mjs art_vorn --do "__ED.lab.play('full')" --at 0.2 --eval "__ED.lab.play('grip')"
//
// Flags: #design=vorn (default) | vornLow | kael, #arena, #tex=256|512.
// Scenarios: full, bust, face, front(yaw, pose, dist, ty), turntable(every), back, side, fight, pose(name, yaw, dist, ty),
// clip(name), silhouette, lineup(sil) (KAEL - VORN - ISKA, black on grey), glow, joints (torture pose), feet, hands, stats,
// grip (off-hand error per grip point and pose), feetContact (sole heights), qa(clips) (src/char/qa.js audit).
// Lab poses: vornlab.rest (default), vornlab.portrait (close-ups), vornlab.guard, .thrust, .sky, .brace (choke grip).

import * as THREE from 'three';
import { createLab, ORDER } from '../core/lab.js';
import { createEnvironment } from '../env/index.js';
import { createCharacter, defineClip, invalidateClips } from '../char/index.js';
import { attachGlow, configureTextureSets } from '../char/materials.js';
import { kael } from '../fighters/kael/design.js';
import { iska } from '../fighters/iska/design.js';
import { vorn, vornLow } from '../fighters/vorn/design.js';
import '../char/clips/demo.js';
import { auditClip } from '../char/qa.js';

const DESIGNS = { vorn, vornLow, kael };

// ---- lab-only spear poses (held clips; fighter-frame metres, README section 4 conventions) -----------------------------------
const POSES = {
  // sentinel rest: spear upright at the right side, butt on the floor (the vertical line of the silhouette)
  'vornlab.rest': {
    hips: { pos: [-0.01, -0.02, 0], rot: [0, -16, 0] },
    bones: { spine: [0, -4, 1], chest: [-1, -4, 2], neck: [0, 8, 0], head: [0, 12, -3], upperArmL: [-10, 8, 6], foreArmL: [0, 0, 22], handL: [0, 0, 6] },
    ik: {
      handR: { pos: [0.33, 1.06, 0.26], aim: [0.1, 1, 0.04], up: [-1, 0.1, 0] },
      footL: { pos: [0.13, 0, -0.13], rot: [0, 10, 0] }, footR: { pos: [-0.05, 0, 0.15], rot: [0, -22, 0] },
    },
    grip: 0, curl: [0.7, 1],
  },
  // portrait: spear upright at the right side, a little behind the shoulder (clear of the face in close-ups)
  'vornlab.portrait': {
    hips: { pos: [-0.01, -0.02, 0], rot: [0, -12, 0] },
    bones: { spine: [0, -3, 1], chest: [-1, -3, 2], neck: [0, 6, 0], head: [0, 8, -2], upperArmL: [-10, 8, 6], foreArmL: [0, 0, 22], handL: [0, 0, 6] },
    ik: {
      handR: { pos: [-0.05, 1.07, 0.37], aim: [-0.06, 1, 0.03], up: [-1, -0.06, 0] },
      footL: { pos: [0.12, 0, -0.13], rot: [0, 10, 0] }, footR: { pos: [-0.04, 0, 0.15], rot: [0, -18, 0] },
    },
    grip: 0, curl: [0.7, 1],
  },
  // two-handed guard: spear forward and up at the opponent's head, rear (left) hand on the grip
  'vornlab.guard': {
    hips: { pos: [-0.05, -0.13, 0], rot: [0, -32, 0] },
    bones: { spine: [0, -8, -6], chest: [2, -10, -4], neck: [0, 14, 4], head: [0, 22, -2] },
    ik: {
      handR: { pos: [0.46, 1.15, 0.2], aim: [0.9, 0.36, -0.22], up: [-0.36, 0.93, 0] },
      footL: { pos: [0.36, 0, -0.17], rot: [0, 16, 0] }, footR: { pos: [-0.38, 0, 0.18], rot: [0, -42, 0] },
    },
    grip: 1, curl: [1, 1],
  },
  // lunging thrust: long reach, spear level
  'vornlab.thrust': {
    hips: { pos: [0.16, -0.17, 0], rot: [0, -8, -6] },
    bones: { spine: [0, -6, -10], chest: [0, -8, -8], neck: [0, 6, 8], head: [0, 8, 4] },
    ik: {
      handR: { pos: [0.86, 1.26, 0.1], aim: [1, 0.04, -0.06], up: [-0.04, 1, 0] },
      footL: { pos: [0.66, 0, -0.14], rot: [0, 8, 0] }, footR: { pos: [-0.5, 0, 0.17], rot: [0, -50, 0] },
    },
    grip: 1, curl: [1, 1],
  },
  // stormfall: spear raised to the sky in both hands
  'vornlab.sky': {
    hips: { pos: [0.0, -0.06, 0], rot: [0, -20, 0] },
    bones: { spine: [0, -6, 6], chest: [0, -6, 8], neck: [0, 8, 10], head: [0, 10, 18] },
    ik: {
      handR: { pos: [0.1, 2.2, 0.16], aim: [0.12, 1, -0.06], up: [-1, 0.1, 0] },
      footL: { pos: [0.24, 0, -0.16], rot: [0, 12, 0] }, footR: { pos: [-0.22, 0, 0.17], rot: [0, -34, 0] },
    },
    grip: 1, curl: [1, 1],
  },
  // low brace: crouched behind the heavy left shoulder, spear low and forward (choke grip)
  'vornlab.brace': {
    hips: { pos: [-0.06, -0.24, 0], rot: [0, -24, 0] },
    bones: { spine: [0, -8, -14], chest: [0, -10, -10], neck: [0, 10, 8], head: [0, 16, 12] },
    ik: {
      handR: { pos: [0.4, 0.94, 0.2], aim: [0.95, 0.2, -0.22], up: [-0.2, 0.98, 0] },
      footL: { pos: [0.46, 0, -0.18], rot: [0, 18, 0] }, footR: { pos: [-0.42, 0, 0.2], rot: [0, -48, 0] },
    },
    grip: 1, curl: [1, 1],
  },
};
const GRIP_AT = { 'vornlab.brace': 'choke' };
let posesDefined = false;
function definePoses() {
  if (posesDefined) return;
  for (const [name, ch] of Object.entries(POSES)) defineClip(name, { duration: 2, loop: true, gripAt: GRIP_AT[name] || 'grip', breath: 0.6, keys: [{ t: 0, ...ch }] });
  posesDefined = true;
}

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

createLab({
  stage: false,
  view: { target: [0, 1.1, 0], dist: 5.4, yaw: 28, pitch: 6, fov: 35 },
  async setup(ctx, lab) {
    const { scene, renderer } = ctx;
    if (ctx.flags.tex) configureTextureSets({ size: Number(ctx.flags.tex) });
    definePoses();
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

    const id = String(ctx.flags.design || 'vorn');
    const design = DESIGNS[id] || vorn;
    const char = createCharacter(ctx, design, { name: id });
    const glow = design.attach ? design.attach(char) : design.glow ? attachGlow(char, design.glow) : null;
    lab.char = char; lab.design = design; lab.glow = glow;
    lab.idle = 'vornlab.rest';
    lab.ox = lab.arena ? -2.5 : 0;
    char.play(lab.idle, { fade: 0 });
    char.update(0, 0);
    window.__ED.char = char;
    console.log('[ed] art_vorn design', id, JSON.stringify(char.stats));

    const st = { spin: null, t: 0, hold: null };
    lab.st = st;
    lab.others = [];
    ctx.onUpdate((dg, dr) => {
      st.t += dg;
      if (st.spin) lab.view({ yaw: st.spin.yaw0 + Math.floor(st.t / st.spin.every + 1e-6) * st.spin.step });
      if (st.hold != null) char.setClipTime(st.hold);
      if (char.root.visible) char.update(dg, dr);
      for (const o of lab.others) if (o.root.visible) o.update(dg, dr);
    }, ORDER.CHAR);
  },
  scenarios: {
    full(ctx, lab, pose) { reset(lab, pose); lab.view({ target: [lab.ox + 0, 1.1, 0], dist: 5.4, yaw: 28, pitch: 5, fov: 35 }); },
    bust(ctx, lab, yaw = 32, pose = 'vornlab.portrait') { reset(lab, pose); lab.view({ target: [lab.ox + 0.02, 1.72, 0], dist: 1.4, yaw, pitch: 3, fov: 35 }); },
    face(ctx, lab, yaw = 20, pose = 'vornlab.portrait') { reset(lab, pose); lab.view({ target: [lab.ox + 0.04, 1.92, 0], dist: 0.95, yaw, pitch: 2, fov: 35 }); },
    front(ctx, lab, yaw = 90, pose = 'vornlab.portrait', dist = 1.5, ty = 1.78) { reset(lab, pose); lab.view({ target: [lab.ox + 0.04, ty, 0], dist, yaw, pitch: 3, fov: 35 }); },
    turntable(ctx, lab, every = 0.25, pose) { reset(lab, pose); lab.st.t = 0; lab.st.spin = { yaw0: 0, step: 45, every }; lab.view({ target: [lab.ox + 0, 1.15, 0], dist: 5.6, yaw: 0, pitch: 4, fov: 35 }); },
    back(ctx, lab, pose) { reset(lab, pose); lab.view({ target: [lab.ox + 0, 1.15, 0], dist: 3.8, yaw: 200, pitch: 8, fov: 35 }); },
    side(ctx, lab, pose) { reset(lab, pose); lab.view({ target: [lab.ox + 0, 1.15, 0], dist: 4.6, yaw: 0, pitch: 3, fov: 35 }); },
    fight(ctx, lab, pose = 'vornlab.guard') {
      reset(lab, pose);
      if (lab.arena) lab.view({ target: [-1.2, 1.2, 0], dist: 6.4, yaw: 0, pitch: 5, fov: 40 });
      else lab.view({ target: [lab.ox + 0, 1.15, 0], dist: 7.2, yaw: 0, pitch: 6, fov: 40 });
    },
    pose(ctx, lab, name = 'vornlab.guard', yaw = 24, dist = 4.6, ty = 1.15) {
      reset(lab, name);
      lab.view({ target: [lab.ox + 0.2, ty, 0], dist, yaw, pitch: 4, fov: 35 });
    },
    clip(ctx, lab, name = 'demo.combo1') { reset(lab); lab.char.play(name, { fade: 0.05, restart: true }); },
    silhouette(ctx, lab, pose) {
      reset(lab, pose);
      silhouette(ctx, lab, [lab.char]);
      lab.view({ target: [lab.ox + 0, 1.15, 0], dist: 5.8, yaw: 0, pitch: 3, fov: 35 });
    },
    lineup(ctx, lab, sil = true) {
      // KAEL - VORN - ISKA at fight-camera framing (side view): the three silhouettes must read apart in black
      reset(lab);
      if (!lab.cast) {
        lab.cast = [[kael, -1.9], [iska, 1.75]].map(([d, x]) => {
          const c = createCharacter(ctx, d, { name: d.id });
          d.attach(c);
          lab.others.push(c);
          return { c, d, x };
        });
      }
      for (const { c, d, x } of lab.cast) {
        c.setVisible(true);
        c.root.position.set(x, 0, 0); c.setFacing(1);
        c.play(d.idle || 'demo.idle', { fade: 0, restart: true });
        c.update(0, 0); c.teleport();
      }
      lab.char.root.position.set(0, 0, 0); lab.char.teleport();
      if (sil) silhouette(ctx, lab, [lab.char, ...lab.cast.map((x) => x.c)]);
      lab.view({ target: [0, 1.15, 0], dist: 7.4, yaw: 0, pitch: 3, fov: 35 });
    },
    glow(ctx, lab) { reset(lab); if (lab.glow) lab.glow.flare('all', 2.5, 0.8); lab.view({ target: [lab.ox + 0.02, 1.55, 0], dist: 2.4, yaw: 30, pitch: 3, fov: 35 }); },
    joints(ctx, lab, yaw = 30) {
      defineClip('vornlab.joints', {
        duration: 2, loop: true, keys: [{
          t: 0, hips: { pos: [0, -0.12, 0], rot: [0, -20, 0] },
          bones: {
            spine: [0, 20, -10], chest: [6, 22, -8], neck: [0, -20, 10], head: [10, -25, 12],
            shoulderR: [-12, 0, 8], upperArmR: [-75, 20, 35], foreArmR: [0, 70, 130], handR: [30, 60, -20],
            shoulderL: [-15, 0, 0], upperArmL: [-10, -30, 165], foreArmL: [0, -60, 95], handL: [-20, 0, 40],
            thighR: [-10, 15, 105], shinR: [0, 0, -135], footR: [0, 0, -30],
            thighL: [-35, -20, -25], shinL: [0, 0, -60], footL: [0, 0, 20],
          },
          grip: 0, curl: [0.3, 1],
        }],
      });
      invalidateClips();
      reset(lab, 'vornlab.joints');
      lab.view({ target: [lab.ox + 0, 1.15, 0], dist: 4.2, yaw, pitch: 4, fov: 35 });
    },
    feet(ctx, lab, yaw = 30, pose) { reset(lab, pose); lab.view({ target: [lab.ox + 0.02, 0.18, 0], dist: 1.25, yaw, pitch: 6, fov: 35 }); },
    hands(ctx, lab, pose = 'vornlab.guard', yaw = 30) { reset(lab, pose); lab.view({ target: [lab.ox + 0.3, 1.08, 0.15], dist: 1.5, yaw, pitch: 6, fov: 35 }); },
    stats(ctx, lab) { return { ...lab.char.stats, design: lab.design.id }; },
    /** Off-hand grip error (m) for each grip point x each two-handed pose, after the rig settles. */
    grip(ctx, lab) {
      const out = {};
      const c = lab.char, g = c.weapon.grips, wR = c.bones.weaponR, wL = c.bones.weaponL;
      const p = new THREE.Vector3(), q = new THREE.Vector3();
      for (const pose of ['vornlab.guard', 'vornlab.thrust', 'vornlab.sky', 'vornlab.brace']) {
        for (const gp of Object.keys(g)) {
          defineClip('vornlab.gtest', { duration: 2, loop: true, gripAt: gp, keys: [{ t: 0, ...POSES[pose] }] });
          invalidateClips();
          reset(lab, 'vornlab.gtest');
          for (let i = 0; i < 30; i++) c.update(1 / 60, 1 / 60);
          wR.updateWorldMatrix(true, false); wL.updateWorldMatrix(true, false);
          p.set(g[gp].pos[0], g[gp].pos[1], g[gp].pos[2]).applyMatrix4(wR.matrixWorld);
          q.setFromMatrixPosition(wL.matrixWorld);
          out[pose.slice(8) + '@' + gp] = +p.distanceTo(q).toFixed(4);
        }
      }
      reset(lab);
      return out;
    },
    /** Sole / toe heights over the floor in the rest and guard poses (world y of the lowest sole vertex per foot). */
    feetContact(ctx, lab) {
      const out = {};
      const c = lab.char, mesh = c.meshes.plate, geo = mesh.geometry, P = geo.attributes.position, SI = geo.attributes.skinIndex;
      const fi = ['footR', 'footL', 'toeR', 'toeL'].map((n) => c.rig.index[n]);
      const v = new THREE.Vector3();
      for (const pose of ['vornlab.rest', 'vornlab.guard', 'vornlab.thrust']) {
        reset(lab, pose);
        for (let i = 0; i < 30; i++) c.update(1 / 60, 1 / 60);
        c.root.updateMatrixWorld(true);
        const lo = {};
        for (let i = 0; i < P.count; i++) {
          const b = SI.getX(i);
          const k = fi.indexOf(b);
          if (k < 0) continue;
          v.fromBufferAttribute(P, i);
          mesh.applyBoneTransform(i, v);
          v.applyMatrix4(mesh.matrixWorld);
          const name = ['footR', 'footL', 'toeR', 'toeL'][k];
          lo[name] = Math.min(lo[name] ?? 9, v.y);
        }
        out[pose.slice(8)] = Object.fromEntries(Object.entries(lo).map(([k, x]) => [k, +x.toFixed(4)]));
      }
      reset(lab);
      return out;
    },
    /** Rig QA (src/char/qa.js) over the demo clips and the lab poses with VORN's proportions + spear. */
    qa(ctx, lab, clips = ['demo.idle', 'demo.guard', 'demo.combo1', 'demo.combo2', 'demo.combo3', 'demo.slam', 'demo.walkF', 'vornlab.rest', 'vornlab.guard', 'vornlab.thrust', 'vornlab.sky', 'vornlab.brace']) {
      const out = {};
      for (const cl of clips) {
        const a = auditClip(lab.char, cl);
        out[cl] = {
          nan: a.nan, floor: Object.fromEntries(Object.entries(a.floor).map(([k, v]) => [k, v.min])),
          below: Object.fromEntries(Object.entries(a.floor).filter(([, v]) => v.below > 0).map(([k, v]) => [k, v.below])),
          hits: a.intersections.slice(0, 4).map((x) => x.pair + ':' + x.depth),
          limits: Array.isArray(a.limits) ? a.limits.length : Object.keys(a.limits || {}).length,
          cpu: a.cpu.mean,
        };
      }
      reset(lab);
      return out;
    },
  },
});

/** Black shapes on grey: lights / environment / glow off, alpha cut-outs kept. */
function silhouette(ctx, lab, chars) {
  ctx.scene.background = new THREE.Color(0xd8d8d8);
  ctx.scene.fog = null;
  lab.floor.visible = false;
  lab.sil = { env: ctx.scene.environmentIntensity, lights: [], mats: [] };
  ctx.scene.traverse((o) => { if (o.isLight) { lab.sil.lights.push([o, o.intensity]); o.intensity = 0; } });
  ctx.scene.environmentIntensity = 0;
  for (const c of chars) {
    if (c.glow) c.glow.gain = 0;
    for (const m of Object.values(c.materials)) { m.userData.kit.uRim.value.w += 100; m.userData.kit.uGlowScale.value = 0; lab.sil.mats.push(m); }
    lab.sil.chars = chars;
  }
}

function reset(lab, pose) {
  const ctx = lab.ctx;
  lab.st.spin = null; lab.st.hold = null;
  ctx.scene.background = lab.bg.background;
  ctx.scene.fog = lab.bg.fog;
  if (lab.sil) {
    for (const [l, i] of lab.sil.lights) l.intensity = i;
    ctx.scene.environmentIntensity = lab.sil.env;
    for (const m of lab.sil.mats) { m.userData.kit.uRim.value.w -= 100; m.userData.kit.uGlowScale.value = 1; }
    for (const c of lab.sil.chars || []) if (c.glow) c.glow.gain = 1;
    lab.sil = null;
  }
  lab.floor.visible = !lab.arena;
  for (const x of lab.cast || []) x.c.setVisible(false);
  lab.char.setVisible(true);
  lab.ox = lab.arena ? -2.5 : 0;
  lab.char.root.position.set(lab.ox, 0, 0);
  lab.char.setFacing(1);
  lab.char.play(pose || lab.idle, { fade: 0, restart: true });
  lab.char.update(0, 0);
  lab.char.teleport();
}
