// Art lab: character look-dev under a moody lighting rig (warm key, cold rims, warm ember bounce, procedural studio
// environment) with framing scenarios for turntables, close-ups, weapons, the back / cape, combat poses and the fight
// camera. Design by flag: #design=kael (default) | iska | vorn | knight  (iska / vorn: stand-in body holding their
// weapons until their designs land).
//
//   node tools/shot.mjs art --hash design=kael --do "__ED.lab.play('bust')" --at 0.5 --out shots/art/kael_bust
//   node tools/shot.mjs art --do "__ED.lab.play('turntable')" --at 0,0.25,0.5,0.75,1,1.25,1.5,1.75 --sheet-only --out shots/art/kael_turn
//
// Scenarios: full, bust, turntable (8 x 45 deg, one per 0.25 s), back, weapon(name), weapons, combat(clip, t), fight,
// silhouette, glow (flare cycle), kit (helm / weapon catalogue), stats.

import * as THREE from 'three';
import { createLab, ORDER } from '../core/lab.js';
import { createCharacter } from '../char/index.js';
import { createKitMaterial, attachGlow } from '../char/materials.js';
import { knight } from '../char/designs/knight.js';
import { kael } from '../fighters/kael/design.js';
import { createStaticKit } from '../char/kit/static.js';
import { greatsword, crescents, spear, WEAPON_SPECS, WEAPON_MATERIALS } from '../char/weapons.js';
import * as A from '../char/kit/armor.js';
import { put } from '../char/kit/geo.js';
import { LOOKS } from '../char/kit/looks.js';
import '../char/clips/demo.js';

/** Stand-in body for designs that do not exist yet: the knight's armour with another weapon set. */
function standIn(id, weapon) {
  return {
    ...knight, id, name: id.toUpperCase() + ' (stand-in body)',
    weapon: Array.isArray(WEAPON_SPECS[weapon]) ? undefined : WEAPON_SPECS[weapon],
    weapons: Array.isArray(WEAPON_SPECS[weapon]) ? WEAPON_SPECS[weapon] : undefined,
    materials: { ...knight.materials, blade: WEAPON_MATERIALS[weapon] },
    build(kit, S, rig) {
      const k2 = Object.create(kit);
      k2.add = (slot, ...a) => (slot === 'blade' ? k2 : kit.add(slot, ...a));
      knight.build(k2, S, rig);
      ({ crescents, spear })[weapon](kit, { slot: 'blade' });
    },
  };
}

const DESIGNS = { kael, knight, iska: standIn('iska', 'crescents'), vorn: standIn('vorn', 'spear') };

/** Procedural studio environment: dark dome, warm key softbox, cold rim strips, ember floor bounce. */
function studioEnv(renderer) {
  const scene = new THREE.Scene();
  scene.add(new THREE.Mesh(new THREE.SphereGeometry(30, 48, 24), new THREE.ShaderMaterial({
    side: THREE.BackSide, depthWrite: false,
    vertexShader: 'varying vec3 vP; void main(){ vP = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }',
    fragmentShader: `varying vec3 vP; void main(){
      float y = vP.y;
      vec3 zen = vec3(0.012, 0.016, 0.026), hor = vec3(0.05, 0.045, 0.05), flo = vec3(0.012, 0.008, 0.006);
      vec3 c = y > 0.0 ? mix(hor, zen, pow(y, 0.5)) : mix(hor * 0.6, flo, pow(-y, 0.35));
      // faint warm glow low on the horizon toward the front (ember light from the floor)
      c += vec3(0.12, 0.05, 0.015) * pow(max(0.0, 1.0 - abs(y + 0.08) * 5.0), 3.0) * max(0.0, vP.z);
      gl_FragColor = vec4(c, 1.0); }`,
  })));
  const panel = (w, h, col, pos, look = [0, 1.2, 0]) => {
    const m = new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshBasicMaterial({ color: new THREE.Color(...col), side: THREE.DoubleSide }));
    m.position.set(...pos); m.lookAt(...look); scene.add(m);
  };
  panel(5, 3.5, [2.2, 1.85, 1.5], [6, 8, 7]);           // warm key softbox (front-right-high)
  panel(1.2, 9, [0.8, 1.1, 1.9], [-9, 3, -6]);         // cold rim strip (back-left)
  panel(1.2, 9, [0.6, 0.85, 1.5], [9, 3, -7]);         // cold rim strip (back-right)
  panel(10, 1.0, [0.9, 0.38, 0.12], [0, -0.6, 9]);     // ember bounce (low front)
  panel(3, 3, [0.25, 0.3, 0.42], [0, 12, 0]);          // dim top
  const pmrem = new THREE.PMREMGenerator(renderer);
  const tex = pmrem.fromScene(scene, 0.02).texture;
  pmrem.dispose();
  return tex;
}

createLab({
  stage: false,
  view: { target: [0, 1.05, 0], dist: 5.2, yaw: 28, pitch: 6, fov: 35 },
  async setup(ctx, lab) {
    const { scene, renderer } = ctx;
    scene.background = new THREE.Color(0x07080c);
    scene.fog = new THREE.FogExp2(0x07080c, 0.03);
    scene.environment = studioEnv(renderer);
    scene.environmentIntensity = 0.75;
    // lighting rig (fixed set)
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
    lab.lights = { key, rim, rim2, bounce, hemi };
    // floor: dark stone disc fading into the fog
    const floor = new THREE.Mesh(new THREE.CircleGeometry(12, 64), new THREE.MeshStandardMaterial({ color: 0x08080a, roughness: 0.95, metalness: 0.0, envMapIntensity: 0.15 }));
    floor.rotation.x = -Math.PI / 2; floor.receiveShadow = true;
    scene.add(floor);
    lab.floor = floor;

    const id = String(ctx.flags.design || 'kael');
    const design = DESIGNS[id] || kael;
    const char = createCharacter(ctx, design, { name: id });
    const glow = design.attach ? design.attach(char) : design.glow ? attachGlow(char, design.glow) : null;
    char.play(design.idle || 'demo.idle', { fade: 0 });
    char.update(0, 0);
    lab.char = char; lab.design = design; lab.glow = glow;
    window.__ED.char = char;
    console.log('[ed] art lab design', id, JSON.stringify(char.stats));

    const st = { spin: null, t: 0, hold: null };
    lab.st = st;
    ctx.onUpdate((dg, dr) => {
      st.t += dg;
      if (st.spin) lab.view({ yaw: st.spin.yaw0 + Math.floor(st.t / st.spin.every + 1e-6) * st.spin.step });
      if (st.hold) char.setClipTime(st.hold);
      if (lab.char.root.visible) char.update(dg, dr);
      if (lab.display) lab.display.rotation.y += 0;
    }, ORDER.CHAR);
    lab.displays = {};
    lab.show = (what) => {
      char.setVisible(what === 'char');
      for (const [k, g] of Object.entries(lab.displays)) g.visible = k === what;
      floor.visible = what === 'char';
    };
  },
  scenarios: {
    full(ctx, lab) { reset(lab); lab.view({ target: [0, 1.0, 0], dist: 5.0, yaw: 28, pitch: 5, fov: 35 }); },
    bust(ctx, lab, yaw = 32) { reset(lab); lab.view({ target: [0.02, 1.62, 0], dist: 1.35, yaw, pitch: 3, fov: 35 }); },
    face(ctx, lab, yaw = 20) { reset(lab); lab.view({ target: [0.04, 1.76, 0], dist: 0.78, yaw, pitch: 2, fov: 35 }); },
    turntable(ctx, lab, every = 0.25) { reset(lab); lab.st.t = 0; lab.st.spin = { yaw0: 0, step: 45, every }; lab.view({ target: [0, 1.0, 0], dist: 5.0, yaw: 0, pitch: 4, fov: 35 }); },
    back(ctx, lab) { reset(lab); lab.view({ target: [0, 1.15, 0], dist: 3.6, yaw: 200, pitch: 8, fov: 35 }); },
    fight(ctx, lab) { reset(lab); lab.view({ target: [0, 1.15, 0], dist: 7.2, yaw: 0, pitch: 6, fov: 40 }); },
    combat(ctx, lab, clip = 'demo.combo1', t = 0.25, yaw = 20) {
      reset(lab);
      lab.char.play(clip, { fade: 0, restart: true });
      lab.st.hold = t;
      lab.view({ target: [0.2, 1.05, 0], dist: 4.4, yaw, pitch: 4, fov: 35 });
    },
    clip(ctx, lab, clip = 'demo.combo1') { reset(lab); lab.char.play(clip, { fade: 0.05, restart: true }); },
    silhouette(ctx, lab) {
      reset(lab);
      ctx.scene.background = new THREE.Color(0xd8d8d8);
      ctx.scene.fog = null;
      lab.floor.visible = false;
      const black = new THREE.MeshBasicMaterial({ color: 0x000000 });
      for (const m of Object.values(lab.char.meshes)) { m.userData.mat = m.material; m.material = black; }
      lab.view({ target: [0, 1.0, 0], dist: 5.4, yaw: 0, pitch: 3, fov: 35 });
    },
    glow(ctx, lab) { reset(lab); if (lab.glow) lab.glow.flare('all', 2.5, 0.8); lab.view({ target: [0.02, 1.45, 0], dist: 2.2, yaw: 30, pitch: 3, fov: 35 }); },
    weapon(ctx, lab, name = 'greatsword', part = 'all') {
      const g = weaponDisplay(ctx, lab, name);
      lab.show(name);
      const box = new THREE.Box3().setFromObject(g);
      const c = box.getCenter(new THREE.Vector3()), s = box.getSize(new THREE.Vector3());
      if (part === 'hilt') lab.view({ target: [c.x - s.x * 0.33, c.y, 0], dist: 0.75, yaw: 22, pitch: 10, fov: 35 });
      else if (part === 'tip') lab.view({ target: [c.x + s.x * 0.3, c.y, 0], dist: 0.8, yaw: 22, pitch: 10, fov: 35 });
      else lab.view({ target: [c.x, c.y, 0], dist: Math.max(s.x, s.y) * 1.25, yaw: 12, pitch: 8, fov: 35 });
    },
    weapons(ctx, lab) {
      const gs = ['greatsword', 'crescents', 'spear'].map((n) => weaponDisplay(ctx, lab, n));
      lab.char.setVisible(false); lab.floor.visible = false;
      gs.forEach((g, i) => { g.visible = true; g.position.set(0, 1.9 - i * 0.5, 0); });
      lab.view({ target: [0.3, 1.4, 0], dist: 3.2, yaw: 10, pitch: 6, fov: 35 });
    },
    kit(ctx, lab) {
      const g = kitDisplay(ctx, lab);
      lab.show('kit');
      g.visible = true;
      lab.view({ target: [0.0, 0.18, 0], dist: 1.6, yaw: 25, pitch: 10, fov: 35 });
    },
    stats(ctx, lab) { return { ...lab.char.stats, design: lab.design.id }; },
  },
});

function reset(lab) {
  const ctx = lab.ctx;
  lab.st.spin = null; lab.st.hold = null;
  lab.show('char');
  ctx.scene.background = new THREE.Color(0x07080c);
  ctx.scene.fog = new THREE.FogExp2(0x07080c, 0.03);
  for (const m of Object.values(lab.char.meshes)) if (m.userData.mat) { m.material = m.userData.mat; m.userData.mat = null; }
  lab.char.root.position.set(0, 0, 0);
  lab.char.setFacing(1);
  lab.char.play(lab.design.idle || 'demo.idle', { fade: 0, restart: true });
}

/** Static display of a weapon with its sockets (base = blue, tip = red) and grip points (yellow). */
function weaponDisplay(ctx, lab, name) {
  if (lab.displays[name]) return lab.displays[name];
  const sk = createStaticKit();
  const spec = ({ greatsword, crescents, spear })[name](sk, { slot: 'blade' });
  const mat = createKitMaterial(WEAPON_MATERIALS[name]);
  const g = sk.finish({ blade: mat });
  const specs = Array.isArray(spec) ? [spec[0]] : [spec];
  const dot = (p, col, r = 0.008) => {
    const m = new THREE.Mesh(new THREE.SphereGeometry(r, 10, 8), new THREE.MeshBasicMaterial({ color: col }));
    m.position.set(...p); m.renderOrder = 2; g.add(m);
  };
  for (const s of specs) {
    dot(s.base, 0x2060ff); dot(s.tip, 0xff2020);
    for (const gp of Object.values(s.grips || {})) dot(gp.pos, 0xffd020, 0.006);
  }
  g.position.set(0, 1.2, 0);
  ctx.scene.add(g);
  lab.displays[name] = g;
  g.userData.glow = attachMaterialGlow(mat, WEAPON_MATERIALS[name].glow);
  return g;
}

function attachMaterialGlow(mat, glow) { return glow; }

/** Catalogue of kit pieces (helms) on plinths. */
function kitDisplay(ctx, lab) {
  if (lab.displays.kit) return lab.displays.kit;
  const sk = createStaticKit();
  const look = LOOKS.blackSteel, trim = LOOKS.bronze;
  const H = A.greatHelm({});
  for (const k of ['crown', 'brow', 'face', 'back', 'crest']) put(sk, 'plate', null, H[k], k === 'brow' ? LOOKS.scorchedSteel : look, { at: [-0.32, 0, 0] });
  put(sk, 'plate', null, H.slit, LOOKS.slit, { at: [-0.32, 0, 0] });
  put(sk, 'plate', null, H.eye, { ...LOOKS.slit, eye: 1 }, { at: [-0.32, 0, 0] });
  put(sk, 'plate', null, H.rivets, trim, { at: [-0.32, 0, 0] });
  const St = A.stormHelm({});
  for (const k of ['skull', 'visor', 'horns', 'wings']) put(sk, 'plate', null, St[k], k === 'horns' ? LOOKS.bronze : LOOKS.blueSteel, { at: [0, 0, 0] });
  put(sk, 'plate', null, St.slits, { ...LOOKS.slit, eye: 1 });
  put(sk, 'plate', null, St.rivets, LOOKS.gold);
  const Ho = A.hoodedMask({});
  put(sk, 'plate', null, Ho.hood, { ...LOOKS.cloth, color: [0.03, 0.05, 0.09] }, { at: [0.32, 0, 0] });
  put(sk, 'plate', null, Ho.mask, LOOKS.silver, { at: [0.32, 0, 0] });
  put(sk, 'plate', null, Ho.circlet, LOOKS.silver, { at: [0.32, 0, 0] });
  put(sk, 'plate', null, Ho.gem, { ...LOOKS.silver, inlay: 1 }, { at: [0.32, 0, 0] });
  const mat = createKitMaterial({ envMapIntensity: 1.1, bump: 1, glow: { inlay: [1.5, 4, 8], vein: [3, 1, 0.2], eye: [8, 3, 0.7] }, rim: [0.2, 0.27, 0.42, 3.2] });
  const g = sk.finish({ plate: mat });
  g.position.set(0, 0, 0);
  ctx.scene.add(g);
  lab.displays.kit = g;
  return g;
}
