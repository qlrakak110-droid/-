// VORN asset lab: 뇌진천 (src/fighters/vorn/design.js wearing the Blender asset assets/chars/vorn) in the real renderer,
// with his real clips (src/fighters/vorn/clips), the line-up against KAEL and ISKA, and the numbers (budgets, decode /
// build ms, char.update ms, dispose). A copy of src/labs/iska_asset.js with VORN as the subject.
//
//   node tools/shot.mjs vorn_asset --do "__ED.lab.play('turntable')" --at 0,0.25,0.5,0.75,1,1.25,1.5,1.75 --sheet 4 --sheet-only --out shots/blender/vorn/eng_turn
//   node tools/shot.mjs vorn_asset --do "__ED.lab.play('bust')" --at 0.5 --out shots/blender/vorn/eng_bust
//   node tools/shot.mjs vorn_asset --do "__ED.lab.play('lineup','sil')" --at 0.5 --out shots/blender/vorn/eng_sil
//   node tools/shot.mjs vorn_asset --do "__ED.lab.play('clip','vorn.walkF')" --at 0,0.15,0.3,0.45,0.6,0.75 --sheet 6 --sheet-only --out shots/blender/vorn/walk
//   node tools/shot.mjs vorn_asset --at 0 --eval "__ED.lab.play('stats')"      (also 'dispose')
//
// Flags: #arena (arena backdrop and lights), #q=low|mid|high.
// Scenarios: full(yaw), turntable(every), bust(yaw), face(yaw), back(yaw), waist(yaw), hands(yaw, clip, t), feet(yaw),
// pose(clip, t, yaw, dist, ty), clip(name, yaw, dist), lineup('sil' | 'lit'), stats, dispose(n), glow.

import * as THREE from 'three';
import { createLab, ORDER } from '../core/lab.js';
import { createEnvironment } from '../env/index.js';
import { createCharacter } from '../char/index.js';
import { getAsset, assetStats } from '../char/assets.js';
import vornAsset from '../../assets/chars/vorn/index.js';
import { kael } from '../fighters/kael/design.js';
import { iska } from '../fighters/iska/design.js';
import { vorn } from '../fighters/vorn/design.js';
import '../fighters/kael/clips/index.js';
import '../fighters/iska/clips/index.js';
import '../fighters/vorn/clips/index.js';

/** Procedural studio environment (the art lab's): dark dome, warm key softbox, cold rim strips, ember floor bounce. */
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
  const panel = (w, h, col, pos) => {
    const m = new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshBasicMaterial({ color: new THREE.Color(...col), side: THREE.DoubleSide }));
    m.position.set(...pos); m.lookAt(0, 1.2, 0); scene.add(m);
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

/** VORN's ultimate opener clip (stats). */
const ULT = 'vorn.ninefold_storm';
const IDLE = { kael: 'kael.idle', iska: 'iska.idle', vorn: 'vorn.idle' };

function headHeight(char) {
  char.root.updateMatrixWorld(true);
  return char.bones.head.getWorldPosition(new THREE.Vector3()).y + 0.2;
}

createLab({
  stage: false,
  view: { target: [0, 1.05, 0], dist: 5.2, yaw: 20, pitch: 5, fov: 35 },
  async setup(ctx, lab) {
    const { scene, renderer } = ctx;
    lab.arena = !!ctx.flags.arena;
    if (lab.arena) createEnvironment(ctx, {});
    else {
      scene.background = new THREE.Color(0x07080c);
      scene.fog = new THREE.FogExp2(0x07080c, 0.03);
      scene.environment = studioEnv(renderer);
      scene.environmentIntensity = 0.75;
      const key = new THREE.DirectionalLight(new THREE.Color(1.0, 0.86, 0.72), 3.4);
      key.position.set(4, 7, 5.5);
      key.castShadow = !!ctx.quality.shadows;
      if (key.castShadow) {
        key.shadow.mapSize.set(2048, 2048);
        const c = key.shadow.camera; c.left = -4; c.right = 4; c.top = 3.5; c.bottom = -1; c.near = 1; c.far = 25;
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
    lab.bg = { background: scene.background, fog: scene.fog, environment: scene.environment };
    const floor = new THREE.Mesh(new THREE.CircleGeometry(12, 64), new THREE.MeshLambertMaterial({ color: 0x0a0a0c }));
    floor.rotation.x = -Math.PI / 2; floor.receiveShadow = true; floor.visible = !lab.arena;
    scene.add(floor);
    lab.floor = floor;

    // decode + build timing (the asset decodes once; a second character shares it)
    const t0 = performance.now();
    const asset = vornAsset ? getAsset(vornAsset) : null;
    const t1 = performance.now();
    const k = createCharacter(ctx, vorn, { name: 'vorn' });
    const glow = vorn.attach ? vorn.attach(k, ctx.quality) : null;
    const t2 = performance.now();
    const k2 = createCharacter(ctx, vorn, { name: 'vorn2', parent: null });
    const t3 = performance.now();
    k2.dispose();
    lab.timing = { decodeHeaderMs: +(t1 - t0).toFixed(2), firstVornMs: +(t2 - t1).toFixed(1), secondVornMs: +(t3 - t2).toFixed(1), partDecodeMs: asset ? +asset.stats.partMs.toFixed(1) : 0 };
    lab.char = k; lab.glow = glow;
    lab.others = {};
    lab.headY = headHeight(k);
    window.__ED.char = k;
    lab.st = { spin: null, t: 0, hold: null };
    reset(lab);
    console.log('[ed] vorn asset lab', JSON.stringify({ vorn: k.stats, timing: lab.timing }));
    ctx.onUpdate((dg, dr) => {
      const st = lab.st;
      st.t += dg;
      if (st.spin) k.root.rotation.y = Math.floor(st.t / st.spin.every + 1e-6) * st.spin.step * Math.PI / 180;
      if (st.hold != null) k.setClipTime(st.hold);
      if (k.root.visible) k.update(dg, dr);
      for (const o of Object.values(lab.others)) if (o.root.visible) { if (o.hold != null) o.setClipTime(o.hold); o.update(dg, dr); }
    }, ORDER.CHAR);
  },
  scenarios: {
    full(ctx, lab, yaw = 28) { reset(lab); lab.view({ target: [0, lab.headY * 0.55, 0], dist: lab.headY * 2.35, yaw, pitch: 4, fov: 35 }); },
    turntable(ctx, lab, every = 0.25) {
      reset(lab);
      lab.st.t = 0; lab.st.spin = { step: 45, every };
      lab.view({ target: [0, lab.headY * 0.55, 0], dist: lab.headY * 2.35, yaw: 0, pitch: 4, fov: 35 });
    },
    bust(ctx, lab, yaw = 32) { reset(lab); lab.view({ target: [0.02, lab.headY - 0.36, 0], dist: 1.55, yaw, pitch: 3, fov: 35 }); },
    face(ctx, lab, yaw = 30) { reset(lab); lab.view({ target: [0.04, lab.headY - 0.22, 0], dist: 0.85, yaw, pitch: 2, fov: 35 }); },
    back(ctx, lab, yaw = 200) { reset(lab); lab.view({ target: [0, lab.headY * 0.55, 0], dist: lab.headY * 2.25, yaw, pitch: 8, fov: 35 }); },
    waist(ctx, lab, yaw = 30) { reset(lab); lab.view({ target: [0, lab.headY * 0.47, 0], dist: 1.9, yaw, pitch: 4, fov: 35 }); },
    feet(ctx, lab, yaw = 35) { reset(lab); lab.view({ target: [0.02, 0.2, 0], dist: 1.4, yaw, pitch: 8, fov: 35 }); },
    /** Hands on the weapon (a clip held at t; default the idle stance). */
    hands(ctx, lab, yaw = 30, clip = 'vorn.idle', t = 0) { reset(lab, clip, t); lab.view({ target: [0.15, 1.05, 0.15], dist: 1.1, yaw, pitch: 6, fov: 35 }); },
    /** A clip held at time t. */
    pose(ctx, lab, name = 'vorn.idle', t = 0, yaw = 20, dist = null, ty = null) {
      reset(lab, name, t);
      lab.view({ target: [0, ty ?? lab.headY * 0.55, 0], dist: dist ?? lab.headY * 2.4, yaw, pitch: 4, fov: 35 });
    },
    /** Play a clip (sample with --at). */
    clip(ctx, lab, name = 'vorn.walkF', yaw = 20, dist = null) {
      reset(lab, name, null, true);
      lab.view({ target: [0, lab.headY * 0.52, 0], dist: dist ?? lab.headY * 2.5, yaw, pitch: 4, fov: 35 });
    },
    glow(ctx, lab, amount = 2.5, dur = 0.8) { reset(lab); if (lab.glow) lab.glow.flare('all', amount, dur); lab.view({ target: [0.02, lab.headY - 0.35, 0], dist: 2.4, yaw: 30, pitch: 3, fov: 35 }); },
    /**
     * The roster side by side in their idles (the fight camera's side view): 'sil' black on grey, 'lit' lab lights.
     * Order: VORN, ISKA, KAEL (ISKA in the middle).
     */
    lineup(ctx, lab, mode = 'sil', yaw = 0) {
      const others = ensureOthers(ctx, lab);
      reset(lab);
      const order = [['vorn', lab.char, -1.45], ['iska', others.iska, 0], ['kael', others.kael, 1.45]];
      for (const [id, c, x] of order) {
        c.setVisible(true);
        c.root.position.set(x, 0, 0);
        c.setFacing(1);
        c.play(IDLE[id], { fade: 0, restart: true }); c.update(0, 0); c.teleport(); c.update(1 / 60, 1 / 60);
      }
      const black = new THREE.MeshBasicMaterial({ color: 0x000000 });
      if (mode === 'sil') {
        for (const [, c] of order) c.root.traverse((o) => { if (o.isMesh) { o.userData.mat = o.userData.mat || o.material; o.material = black; } });
        ctx.scene.background = new THREE.Color(0x9a9a9a); ctx.scene.fog = null; ctx.scene.environment = null;
        lab.floor.visible = false;
      }
      lab.view({ target: [0, 1.0, 0], dist: 6.4, yaw, pitch: 2, fov: 35 });
    },
    /** Triangles, draw calls, bones, asset bytes, decode / build ms, char.update ms. */
    stats(ctx, lab) {
      const c = lab.char;
      const run = (name) => {
        const ts = [];
        for (let r = 0; r < 5; r++) {
          c.play(name, { fade: 0, restart: true }); c.update(0, 0); c.teleport();
          for (let f = 0; f < 120; f++) { const a = performance.now(); c.update(1 / 60, 1 / 60); ts.push(performance.now() - a); }
        }
        ts.sort((a, b) => a - b);
        return { medianMs: +ts[Math.floor(ts.length / 2)].toFixed(3), p90Ms: +ts[Math.floor(ts.length * 0.9)].toFixed(3) };
      };
      return { vorn: c.stats, cpu: { idle: run('vorn.idle'), walkF: run('vorn.walkF'), ult: run(ULT) }, asset: vornAsset ? assetStats(vornAsset) : null, timing: lab.timing, quality: ctx.quality.tier };
    },
    /** GPU objects before / after creating and disposing VORN n times. */
    dispose(ctx, lab, n = 3) {
      const info = () => ({ geometries: ctx.renderer.info.memory.geometries, textures: ctx.renderer.info.memory.textures, programs: ctx.renderer.info.programs.length });
      ctx.renderer.render(ctx.scene, ctx.camera);
      const before = info();
      for (let i = 0; i < n; i++) {
        const c = createCharacter(ctx, vorn, { name: 'tmp' + i });
        if (vorn.attach) vorn.attach(c, ctx.quality);
        c.update(1 / 60, 1 / 60); ctx.renderer.render(ctx.scene, ctx.camera); c.dispose();
      }
      ctx.renderer.render(ctx.scene, ctx.camera);
      return { before, after: info() };
    },
  },
});

function ensureOthers(ctx, lab) {
  if (!lab.others.kael) {
    lab.others.kael = createCharacter(ctx, kael, { name: 'kael' });
    if (kael.attach) kael.attach(lab.others.kael, ctx.quality);
    lab.others.iska = createCharacter(ctx, iska, { name: 'iska' });
    if (iska.attach) iska.attach(lab.others.iska, ctx.quality);
  }
  return lab.others;
}

/** Back to the idle (or clip `name` held at `t`; t null = playing). */
function reset(lab, name = 'vorn.idle', t = 0, play = false) {
  const k = lab.char;
  lab.st.spin = null; lab.st.hold = null; lab.st.t = 0;
  for (const c of [k, ...Object.values(lab.others)]) {
    c.root.traverse((o) => { if (o.isMesh && o.userData.mat) o.material = o.userData.mat; });
    c.root.rotation.y = 0;
  }
  for (const o of Object.values(lab.others)) o.setVisible(false);
  const sc = k.root.parent;
  if (sc && sc.isScene && lab.bg) { sc.background = lab.bg.background; sc.fog = lab.bg.fog; sc.environment = lab.bg.environment; }
  lab.floor.visible = !lab.arena;
  k.root.position.set(0, 0, 0);
  k.setVisible(true);
  k.setFacing(1);
  k.play(name, { fade: 0, restart: true });
  k.update(0, 0); k.teleport();
  k.update(1 / 60, 1 / 60);
  if (!play && t != null) lab.st.hold = t;
}
