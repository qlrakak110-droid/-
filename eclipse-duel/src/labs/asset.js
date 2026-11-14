// Asset lab: the Blender asset pipeline in the real renderer. Shows the pilot (src/char/asset_pilot.js: VORN's rig
// wearing the Blender-built asset assets/chars/pilot) next to the current kit-built VORN, under the art lab's moody
// rig or the arena (#arena), and measures it.
//
//   node tools/shot.mjs asset --do "__ED.lab.play('pair')" --at 0.5 --out shots/blender/pilot/pair
//   node tools/shot.mjs asset --do "__ED.lab.play('turntable')" --at 0,0.25,0.5,0.75,1,1.25,1.5,1.75 --sheet 4 --sheet-only --out shots/blender/pilot/turn
//   node tools/shot.mjs asset --do "__ED.lab.play('bust')" --at 0.5 --out shots/blender/pilot/bust
//   node tools/shot.mjs asset --do "__ED.lab.play('sil')" --at 0.5 --out shots/blender/pilot/sil
//   node tools/shot.mjs asset --do "__ED.lab.play('clip','vorn.walkF')" --at 0,0.2,0.4,0.6,0.8,1 --sheet 3 --sheet-only --out shots/blender/pilot/walk
//   node tools/shot.mjs asset --at 0 --eval "__ED.lab.play('stats')"
//
// Flags: #arena (arena backdrop and lights), #q=low|mid|high, #solo (the pilot alone, centred), #kit (only the kit VORN).
// Scenarios: pair(yaw), turntable(every), bust(yaw, who), face(yaw), waist(yaw), sil, clip(name, yaw, who), pose(name, t,
// yaw), hands(yaw), stats, cpu(frames), dispose.

import * as THREE from 'three';
import { createLab, ORDER } from '../core/lab.js';
import { createEnvironment } from '../env/index.js';
import { createCharacter } from '../char/index.js';
import { getAsset, assetStats } from '../char/assets.js';
import { pilot } from '../char/asset_pilot.js';
import { vorn } from '../fighters/vorn/design.js';
import '../fighters/vorn/clips/index.js';
import '../char/clips/demo.js';

const GAP = 0.85;   // half distance between the two figures (m)

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
      lab.lights = { key, rim, rim2, bounce, hemi };
    }
    lab.bg = { background: scene.background, fog: scene.fog };
    const floor = new THREE.Mesh(new THREE.CircleGeometry(12, 64), new THREE.MeshLambertMaterial({ color: 0x0a0a0c }));
    floor.rotation.x = -Math.PI / 2; floor.receiveShadow = true; floor.visible = !lab.arena;
    scene.add(floor);
    lab.floor = floor;

    // decode + build timing (the asset decodes once; a second character shares it)
    const t0 = performance.now();
    const asset = getAsset('pilot');
    const t1 = performance.now();
    const p = createCharacter(ctx, pilot, { name: 'pilot' });
    pilot.attach(p, ctx.quality);
    const t2 = performance.now();
    const p2 = createCharacter(ctx, pilot, { name: 'pilot2', parent: null });
    const t3 = performance.now();
    const k = createCharacter(ctx, vorn, { name: 'vorn' });
    const t4 = performance.now();
    lab.timing = { decodeHeaderMs: +(t1 - t0).toFixed(2), firstPilotMs: +(t2 - t1).toFixed(1), secondPilotMs: +(t3 - t2).toFixed(1), kitVornMs: +(t4 - t3).toFixed(1), partDecodeMs: +asset.stats.partMs.toFixed(1) };
    p2.dispose();
    lab.pilot = p; lab.kit = k;
    const solo = !!ctx.flags.solo, kitOnly = !!ctx.flags.kit;
    lab.pos = { pilot: solo ? 0 : -GAP, kit: solo || kitOnly ? 0 : GAP };
    p.setVisible(!kitOnly); k.setVisible(!solo);
    window.__ED.char = p; window.__ED.kitChar = k;
    lab.headY = Math.max(headHeight(p), headHeight(k));
    lab.st = { spin: null, t: 0, hold: null };
    reset(lab);
    console.log('[ed] asset lab', JSON.stringify({ pilot: p.stats, vorn: k.stats, timing: lab.timing }));
    ctx.onUpdate((dg, dr) => {
      const st = lab.st;
      st.t += dg;
      if (st.spin) {
        const yaw = Math.floor(st.t / st.spin.every + 1e-6) * st.spin.step;
        for (const c of [p, k]) c.root.rotation.y = yaw * Math.PI / 180;
      }
      for (const c of [p, k]) {
        if (!c.root.visible) continue;
        if (st.hold != null) c.setClipTime(st.hold);
        c.update(dg, dr);
      }
    }, ORDER.CHAR);
  },
  scenarios: {
    /** Both figures side by side in the idle (pilot left, kit VORN right). */
    pair(ctx, lab, yaw = 20) { reset(lab); lab.view({ target: [0, lab.headY * 0.55, 0], dist: lab.headY * 2.9, yaw, pitch: 4, fov: 35 }); },
    /** Both figures turn in 45 deg steps every `every` seconds (8 frames = one sheet). */
    turntable(ctx, lab, every = 0.25) {
      reset(lab, 'vorn.idle', 0);
      lab.st.t = 0; lab.st.spin = { step: 45, every };
      lab.view({ target: [0, lab.headY * 0.55, 0], dist: lab.headY * 2.9, yaw: 0, pitch: 4, fov: 35 });
    },
    bust(ctx, lab, yaw = 32, who = 'pilot') {
      reset(lab);
      lab.view({ target: [lab.pos[who] + 0.02, lab.headY - 0.36, 0], dist: 1.55, yaw, pitch: 3, fov: 35 });
    },
    face(ctx, lab, yaw = 30, who = 'pilot') { reset(lab); lab.view({ target: [lab.pos[who] + 0.04, lab.headY - 0.25, 0], dist: 0.9, yaw, pitch: 2, fov: 35 }); },
    waist(ctx, lab, yaw = 30, who = 'pilot') { reset(lab); lab.view({ target: [lab.pos[who], lab.headY * 0.48, 0], dist: 1.9, yaw, pitch: 4, fov: 35 }); },
    hands(ctx, lab, yaw = 30, who = 'pilot') { reset(lab); lab.view({ target: [lab.pos[who] + 0.25, 1.0, 0.15], dist: 1.25, yaw, pitch: 6, fov: 35 }); },
    /** Black silhouettes on grey, side view (the game's fight view). */
    sil(ctx, lab) {
      reset(lab);
      const black = new THREE.MeshBasicMaterial({ color: 0x000000 });
      for (const c of [lab.pilot, lab.kit]) c.root.traverse((o) => { if (o.isMesh) { o.userData.mat = o.userData.mat || o.material; o.material = black; } });
      ctx.scene.background = new THREE.Color(0x9a9a9a); ctx.scene.fog = null; ctx.scene.environment = null;
      lab.floor.visible = false;
      lab.view({ target: [0, lab.headY * 0.55, 0], dist: lab.headY * 2.9, yaw: 0, pitch: 2, fov: 35 });
    },
    /** Play a clip on both (sampled with --at), optionally only one figure ('pilot' | 'kit'). */
    clip(ctx, lab, name = 'vorn.walkF', yaw = 20, who = 'both') {
      reset(lab, name, null, true);
      if (who !== 'both') { lab.pilot.setVisible(who === 'pilot'); lab.kit.setVisible(who === 'kit'); }
      const x = who === 'both' ? 0 : lab.pos[who];
      lab.view({ target: [x, lab.headY * 0.52, 0], dist: lab.headY * (who === 'both' ? 2.9 : 2.2), yaw, pitch: 4, fov: 35 });
    },
    /** A clip held at time t. */
    pose(ctx, lab, name = 'vorn.idle', t = 0, yaw = 20) { reset(lab, name, t); lab.view({ target: [0, lab.headY * 0.55, 0], dist: lab.headY * 2.9, yaw, pitch: 4, fov: 35 }); },
    /** Triangles, draw calls, bones, asset bytes, decode / build ms, char.update ms (pilot vs kit VORN). */
    stats(ctx, lab) {
      const cpu = (c) => {
        reset(lab, 'vorn.walkF');
        const ts = [];
        for (let r = 0; r < 5; r++) {
          c.play('vorn.walkF', { fade: 0, restart: true }); c.update(0, 0); c.teleport();
          let best = 1e9;
          for (let f = 0; f < 120; f++) { const a = performance.now(); c.update(1 / 60, 1 / 60); const d = performance.now() - a; if (f > 10) best = Math.min(best, d); ts.push(d); }
        }
        ts.sort((a, b) => a - b);
        return { medianMs: +ts[Math.floor(ts.length / 2)].toFixed(3), p90Ms: +ts[Math.floor(ts.length * 0.9)].toFixed(3) };
      };
      return { pilot: { ...lab.pilot.stats, cpu: cpu(lab.pilot) }, vorn: { ...lab.kit.stats, cpu: cpu(lab.kit) }, asset: assetStats('pilot'), timing: lab.timing, quality: ctx.quality.tier };
    },
    /** GPU objects before / after creating and disposing the pilot n times. */
    dispose(ctx, lab, n = 3) {
      const info = () => ({ geometries: ctx.renderer.info.memory.geometries, textures: ctx.renderer.info.memory.textures, programs: ctx.renderer.info.programs.length });
      ctx.renderer.render(ctx.scene, ctx.camera);
      const before = info();
      for (let i = 0; i < n; i++) {
        const c = createCharacter(ctx, pilot, { name: 'tmp' + i });
        c.update(1 / 60, 1 / 60); ctx.renderer.render(ctx.scene, ctx.camera); c.dispose();
      }
      ctx.renderer.render(ctx.scene, ctx.camera);
      return { before, after: info() };
    },
  },
});

/** Back to the idle side by side (or clip `name` held at `t`; t null = playing). */
function reset(lab, name = 'vorn.idle', t = 0, play = false) {
  const { pilot: p, kit: k } = lab;
  lab.st.spin = null; lab.st.hold = null; lab.st.t = 0;
  const ctx = p.ctx || null;
  for (const c of [p, k]) {
    c.root.traverse((o) => { if (o.isMesh && o.userData.mat) o.material = o.userData.mat; });
    c.root.rotation.y = 0;
  }
  if (lab.bg && lab.bg.background) { const sc = p.root.parent; if (sc && sc.isScene) { sc.background = lab.bg.background; sc.fog = lab.bg.fog; } }
  lab.floor.visible = !lab.arena;
  p.root.position.set(lab.pos.pilot, 0, 0);
  k.root.position.set(lab.pos.kit, 0, 0);
  for (const c of [p, k]) {
    c.setFacing(1);
    c.play(name, { fade: 0, restart: true });
    c.update(0, 0); c.teleport();
    c.update(1 / 60, 1 / 60);
  }
  if (!play && t != null) lab.st.hold = t;
  void ctx;
}
