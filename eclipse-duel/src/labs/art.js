// Art lab: character look-dev of the roster under a moody lighting rig (warm key, cold rims, warm ember bounce,
// procedural studio environment) or the real arena (#arena). Reviews the three heroes while their designs are being
// rewritten for 흑일무림 (MURIM.md), and the murim kit itself: reference outfits, material swatches, kit parts, weapons.
//
//   node tools/shot.mjs art --hash design=iska --do "__ED.lab.play('turntable')" --at 0,0.25,0.5,0.75,1,1.25,1.5,1.75 --sheet 4 --sheet-only --out shots/murim/chars/x/turn
//   node tools/shot.mjs art --hash design=kael --do "__ED.lab.play('bust')" --at 0.5 --out shots/murim/chars/x/bust
//   node tools/shot.mjs art --do "__ED.lab.play('lineup','sil')" --at 0.5 --out shots/murim/chars/x/sil
//   node tools/shot.mjs art --hash arena --do "__ED.lab.play('lineup','fight')" --at 1 --out shots/murim/chars/x/arena
//   node tools/shot.mjs art --hash "arena&design=kael" --do "__ED.lab.play('duel','iska')" --at 1 --out shots/murim/chars/x/duel
//   node tools/shot.mjs art --do "__ED.lab.play('swatches',0)" --at 0.2 --out shots/murim/chars/x/swatch
//   node tools/shot.mjs art --eval "__ED.lab.play('budget')"        (also 'dispose', 'cpu', 'texgen')
//
// Flags: #design=kael (default) | iska | vorn | heavy | slender | tall | knight   (heavy / slender / tall: the kit's
// reference outfits on the rigs of KAEL / ISKA / VORN), #kit (line-ups and duels use the reference outfits), #arena (the
// arena backdrop and lights), #tex=256|512, #q=low|mid|high.
// Scenarios: full(yaw), turntable(every), bust(yaw), face(yaw), back(yaw), side, fight, pose(name, yaw, dist, ty),
// hero(yaw), combat(clip | pose, t, yaw), clip(name), sil / silhouette, lineup('sil' | 'lit' | 'fight', kind) (alias
// roster), duel(other, kind), glow, weapon(name, 'all' | 'hilt' | 'tip'), weapons, swatches(page, zoom, item),
// parts(page), sway (secondary motion check), stats, budget, dispose / leaks, cpu, texgen, contact, qa(clips).
// A hero design that throws while it is being rewritten is replaced by its reference outfit (the error is logged).
// Lab-only poses (artlab.<id>.hero / .combat / .strike) exist to judge the designs; fighter clips belong to the content team.

import * as THREE from 'three';
import { createLab, ORDER } from '../core/lab.js';
import { createEnvironment } from '../env/index.js';
import { createCharacter, definePose } from '../char/index.js';
import { createKitMaterial, attachGlow, configureTextureSets } from '../char/materials.js';
import * as TEX from '../char/kit/textures.js';
import { knight } from '../char/designs/knight.js';
import { kael } from '../fighters/kael/design.js';
import { iska } from '../fighters/iska/design.js';
import { vorn } from '../fighters/vorn/design.js';
import { createStaticKit } from '../char/kit/static.js';
import { greatsword, crescents, spear, WEAPON_MATERIALS } from '../char/weapons.js';
import { put } from '../char/kit/geo.js';
import { MURIM } from '../char/kit/looks.js';
import { buildSwatches, SWATCH_MATERIAL } from '../char/kit/swatch.js';
import { mannequin } from '../char/kit/mannequin.js';
import * as M from '../char/kit/murim.js';
import * as H from '../char/kit/head.js';
import '../char/clips/demo.js';
import { auditClip } from '../char/qa.js';

const HEROES = { kael, iska, vorn };
/** The kit's reference outfits, each on the rig of the hero whose archetype it is. */
const OUTFITS = { heavy: mannequin('heavy', kael), slender: mannequin('slender', iska), tall: mannequin('tall', vorn) };
const FALLBACK = { kael: 'heavy', iska: 'slender', vorn: 'tall' };
const DESIGNS = { ...HEROES, ...OUTFITS, knight };
/** Pose set (artlab.<id>.*) a design is shown in. */
const POSE_ID = { kael: 'kael', iska: 'iska', vorn: 'vorn', 'murim-heavy': 'kael', 'murim-slender': 'iska', 'murim-tall': 'vorn' };

// ---- lab-only poses (fighter frame; README section 4 conventions) ---------------------------------------------------------
const FOOT = (pos, yaw, pitch = 0) => ({ pos, rot: [0, yaw, pitch] });
// KAEL: greatsword resting on the right shoulder (his idle in MOVES.md), a heavy two-handed high guard, the overhead strike
definePose('artlab.kael.hero', {
  hips: { pos: [-0.02, -0.04, 0], rot: [0, -18, 0] },
  bones: { spine: [0, -4, 1], chest: [-1, -5, 3], neck: [0, 8, -2], head: [0, 12, -4], upperArmL: [-12, 6, 4], foreArmL: [0, 0, 18] },
  ik: {
    handR: { pos: [0.22, 1.3, 0.36], aim: [-0.62, 0.78, -0.06], up: [0, 0, -1] },
    footL: FOOT([0.16, 0, -0.15], 12), footR: FOOT([-0.12, 0, 0.17], -26),
  },
  grip: 0, curl: [0.75, 1],
});
definePose('artlab.kael.combat', {
  hips: { pos: [-0.06, -0.14, 0], rot: [0, -34, 0] },
  bones: { spine: [0, -8, -6], chest: [2, -10, -4], neck: [0, 16, 4], head: [0, 24, -2] },
  ik: {
    handR: { pos: [0.3, 1.12, 0.2], aim: [0.72, 0.66, -0.2], up: [-0.66, 0.74, 0.06] },
    footL: FOOT([0.36, 0, -0.18], 16), footR: FOOT([-0.4, 0, 0.19], -44),
  },
  grip: 1, curl: [1, 1],
});
definePose('artlab.kael.strike', {
  hips: { pos: [0.1, -0.2, 0], rot: [-2, 14, -4] },
  bones: { spine: [-2, 8, -14], chest: [-2, 8, -10], neck: [0, -8, 10], head: [0, -10, 6] },
  ik: {
    handR: { pos: [0.58, 0.96, 0.06], aim: [0.84, -0.5, -0.2], up: [0.5, 0.86, 0] },
    footL: FOOT([0.52, 0, -0.17], 12), footR: FOOT([-0.42, 0, 0.2], -48),
  },
  grip: 1, curl: [1, 1],
});
// ISKA: light stance on the toes with the blades crossed low, the wide cross-body slash, the crossed high guard
definePose('artlab.iska.hero', {
  hips: { pos: [-0.03, -0.07, 0], rot: [0, -22, 0] },
  bones: { spine: [2, -4, -2], chest: [0, -6, -1], neck: [0, 6, 2], head: [0, 10, -4] },
  ik: {
    handR: { pos: [0.2, 0.9, 0.11], aim: [0.5, -0.66, -0.56], up: [0.86, 0.5, 0.1] },
    handL: { pos: [0.25, 0.93, -0.07], aim: [0.52, -0.62, 0.58], up: [0.84, 0.54, -0.1] },
    footL: FOOT([0.22, 0.04, -0.12], 14, -16), footR: FOOT([-0.24, 0.04, 0.14], -38, -16),
  },
  grip: 0, curl: [1, 1],
});
definePose('artlab.iska.combat', {
  hips: { pos: [0.08, -0.14, 0], rot: [-4, 30, -6] },
  bones: { spine: [-4, 14, -10], chest: [-6, 16, -6], neck: [0, -14, 6], head: [0, -20, 4] },
  ik: {
    handR: { pos: [0.62, 1.18, -0.12], aim: [0.62, 0.22, -0.75], up: [0.2, 0.96, 0.1] },
    handL: { pos: [-0.36, 0.9, -0.22], aim: [-0.8, -0.3, -0.5], up: [0.1, 0.9, -0.4] },
    footL: FOOT([0.46, 0, -0.14], 12), footR: FOOT([-0.36, 0.052, 0.16], -46, -22),
  },
  grip: 0, curl: [1, 1],
});
definePose('artlab.iska.strike', {
  hips: { pos: [-0.04, -0.1, 0], rot: [0, -20, 0] },
  bones: { spine: [0, -6, -6], chest: [0, -8, -4], neck: [0, 8, 6], head: [0, 12, 2] },
  ik: {
    handR: { pos: [0.3, 1.36, 0.08], aim: [0.3, 0.75, -0.6], up: [0.9, -0.1, 0.4] },
    handL: { pos: [0.3, 1.34, -0.04], aim: [0.3, 0.75, 0.6], up: [0.9, -0.1, -0.4] },
    footL: FOOT([0.26, 0, -0.13], 14), footR: FOOT([-0.28, 0, 0.15], -44),
  },
  grip: 0, curl: [1, 1],
});
// VORN: sentinel rest (spear upright, butt on the floor), two-handed guard, lunging thrust
definePose('artlab.vorn.hero', {
  hips: { pos: [-0.01, -0.02, 0], rot: [0, -16, 0] },
  bones: { spine: [0, -4, 1], chest: [-1, -4, 2], neck: [0, 8, 0], head: [0, 12, -3], upperArmL: [-10, 8, 6], foreArmL: [0, 0, 22], handL: [0, 0, 6] },
  ik: {
    handR: { pos: [0.33, 1.06, 0.26], aim: [0.1, 1, 0.04], up: [-1, 0.1, 0] },
    footL: FOOT([0.13, 0, -0.13], 10), footR: FOOT([-0.05, 0, 0.15], -22),
  },
  grip: 0, curl: [0.7, 1],
});
definePose('artlab.vorn.combat', {
  hips: { pos: [-0.05, -0.13, 0], rot: [0, -32, 0] },
  bones: { spine: [0, -8, -6], chest: [2, -10, -4], neck: [0, 14, 4], head: [0, 22, -2] },
  ik: {
    handR: { pos: [0.46, 1.15, 0.2], aim: [0.9, 0.36, -0.22], up: [-0.36, 0.93, 0] },
    footL: FOOT([0.36, 0, -0.17], 16), footR: FOOT([-0.38, 0, 0.18], -42),
  },
  grip: 1, curl: [1, 1],
});
definePose('artlab.vorn.strike', {
  hips: { pos: [0.16, -0.17, 0], rot: [0, -8, -6] },
  bones: { spine: [0, -6, -10], chest: [0, -8, -8], neck: [0, 6, 8], head: [0, 8, 4] },
  ik: {
    handR: { pos: [0.86, 1.26, 0.1], aim: [1, 0.04, -0.06], up: [-0.04, 1, 0] },
    footL: FOOT([0.66, 0, -0.14], 8), footR: FOOT([-0.5, 0, 0.17], -50),
  },
  grip: 1, curl: [1, 1],
});
/** The lab pose of a design (kind: 'hero' | 'combat' | 'strike'); designs without lab poses use the demo clips. */
const poseOf = (d, kind) => (POSE_ID[d.id] ? `artlab.${POSE_ID[d.id]}.${kind}` : (kind === 'hero' ? d.idle || 'demo.idle' : 'demo.guard'));

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
    if (ctx.flags.tex) configureTextureSets({ size: Number(ctx.flags.tex) });
    lab.arena = !!ctx.flags.arena;
    lab.kitRoster = !!ctx.flags.kit;
    if (lab.arena) {
      createEnvironment(ctx, {});
    } else {
      scene.background = new THREE.Color(0x07080c);
      scene.fog = new THREE.FogExp2(0x07080c, 0.03);
      scene.environment = studioEnv(renderer);
      scene.environmentIntensity = 0.75;
      // lighting rig (fixed set): warm key, two cold rims, warm ember bounce, dim sky
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
    floor.rotation.x = -Math.PI / 2; floor.receiveShadow = true;
    floor.visible = !lab.arena;
    scene.add(floor);
    lab.floor = floor;

    const id = String(ctx.flags.design || 'kael');
    const { char, design } = spawn(ctx, DESIGNS[id] || kael, id);
    lab.char = char; lab.design = design; lab.glow = char.glow || null;
    lab.others = [];
    lab.hero = poseOf(design, 'hero');
    char.play(lab.hero, { fade: 0 });
    char.update(0, 0);
    lab.headY = headHeight(char);
    window.__ED.char = char;
    window.__ED.textures = TEX;
    console.log('[ed] art lab design', design.id, JSON.stringify(char.stats));

    const st = { spin: null, t: 0, hold: null, sway: null };
    lab.st = st;
    ctx.onUpdate((dg, dr) => {
      st.t += dg;
      if (st.spin) lab.view({ yaw: st.spin.yaw0 + Math.floor(st.t / st.spin.every + 1e-6) * st.spin.step });
      if (st.hold != null) char.setClipTime(st.hold);
      if (st.sway) st.sway(st.t);
      if (char.root.visible) char.update(dg, dr);
      for (const o of lab.others) if (o.root.visible) o.update(dg, dr);
    }, ORDER.CHAR);
    lab.displays = {};
    lab.show = (what) => {
      char.setVisible(what === 'char');
      for (const [k, g] of Object.entries(lab.displays)) g.visible = k === what;
      floor.visible = what === 'char' && !lab.arena;
    };
  },
  scenarios: {
    full(ctx, lab, yaw = 28) { reset(lab); lab.view({ target: [lab.ox, lab.headY * 0.62, 0], dist: lab.headY * 2.5, yaw, pitch: 5, fov: 35 }); },
    turntable(ctx, lab, every = 0.25) {
      reset(lab);
      lab.st.t = 0; lab.st.spin = { yaw0: 0, step: 45, every };
      lab.view({ target: [lab.ox, lab.headY * 0.62, 0], dist: lab.headY * 2.5, yaw: 0, pitch: 4, fov: 35 });
    },
    bust(ctx, lab, yaw = 32) { reset(lab); lab.view({ target: [lab.ox + 0.02, lab.headY - 0.03, 0], dist: 1.5, yaw, pitch: 3, fov: 35 }); },
    face(ctx, lab, yaw = 30) { reset(lab); lab.view({ target: [lab.ox + 0.04, lab.headY + 0.09, 0], dist: 0.85, yaw, pitch: 2, fov: 35 }); },
    back(ctx, lab, yaw = 200) { reset(lab); lab.view({ target: [lab.ox, lab.headY * 0.62, 0], dist: lab.headY * 2.3, yaw, pitch: 8, fov: 35 }); },
    side(ctx, lab) { reset(lab); lab.view({ target: [lab.ox, lab.headY * 0.62, 0], dist: lab.headY * 2.5, yaw: 0, pitch: 3, fov: 35 }); },
    /** Waist and skirt close-up (sash, knot, hanging ends, panels, ornaments). */
    waist(ctx, lab, yaw = 30) { reset(lab); lab.view({ target: [lab.ox + 0.02, lab.headY * 0.56, 0], dist: 1.7, yaw, pitch: 4, fov: 35 }); },
    fight(ctx, lab) {
      reset(lab, poseOf(lab.design, 'combat'));
      if (lab.arena) lab.view({ target: [-1.2, 1.2, 0], dist: 6.4, yaw: 0, pitch: 5, fov: 40 });
      else lab.view({ target: [0, 1.15, 0], dist: 7.2, yaw: 0, pitch: 6, fov: 40 });
    },
    /** Hold a pose or clip start: camera yaw / distance / target height (default: the design's combat pose). */
    pose(ctx, lab, name, yaw = 24, dist = 4.4, ty = 1.1) {
      reset(lab, name || poseOf(lab.design, 'combat'));
      lab.view({ target: [lab.ox + 0.2, ty, 0], dist, yaw, pitch: 4, fov: 35 });
    },
    feet(ctx, lab, yaw = 35, kind = 'hero') { reset(lab, poseOf(lab.design, kind)); lab.view({ target: [lab.ox + 0.02, 0.16, 0], dist: 1.3, yaw, pitch: 8, fov: 35 }); },
    hands(ctx, lab, yaw = 30, kind = 'combat') { reset(lab, poseOf(lab.design, kind)); lab.view({ target: [lab.ox + 0.3, 1.1, 0.12], dist: 1.4, yaw, pitch: 6, fov: 35 }); },
    hero(ctx, lab, yaw = 40) { reset(lab); lab.view({ target: [lab.ox, lab.headY * 0.62, 0], dist: lab.headY * 2.4, yaw, pitch: 4, fov: 35 }); },
    /** A clip held at time t, or a design pose kind ('combat' | 'strike'). */
    combat(ctx, lab, clip = 'combat', t = 0.25, yaw = 20) {
      const name = clip === 'combat' || clip === 'strike' ? poseOf(lab.design, clip) : clip;
      reset(lab, name);
      if (name === clip) lab.st.hold = t;
      lab.view({ target: [lab.ox + 0.25, lab.headY * 0.58, 0], dist: lab.headY * 2.55, yaw, pitch: 4, fov: 35 });
    },
    clip(ctx, lab, clip = 'demo.combo1') { reset(lab); lab.char.play(clip, { fade: 0.05, restart: true }); },
    /** Secondary motion: the hero turns and steps side to side in a breeze (sleeves, sash ends, hair, veil, tassels). */
    sway(ctx, lab, yaw = 24) {
      reset(lab, poseOf(lab.design, 'combat'));
      const c = lab.char;
      c.wind = [3.5, 0, 1.5];
      lab.st.t = 0;
      lab.st.sway = (t) => { c.root.position.x = lab.ox + 0.5 * Math.sin(t * 5.2); c.root.rotation.y = 0.5 * Math.sin(t * 3.1); };
      lab.view({ target: [lab.ox, lab.headY * 0.6, 0], dist: lab.headY * 2.7, yaw, pitch: 4, fov: 35 });
    },
    silhouette: silOne,
    sil: silOne,
    /**
     * The roster side by side, each in its hero pose (or 'combat' poses with mode 'fight'): 'sil' black on grey,
     * 'lit' under the lab lights, 'fight' at the fight camera's distance (in the arena with #arena). #kit (or
     * set = 'kit'): the reference outfits instead of the heroes.
     */
    lineup,
    roster(ctx, lab, mode = 'lit', kind = 'hero', set) { return lineup(ctx, lab, mode, kind, set); },
    /** Two heroes facing each other at the fight-camera distance (P1 = this design at x -2.5, P2 = other at +2.5). */
    duel(ctx, lab, other = 'vorn', kind = 'combat') {
      const d2 = (lab.kitRoster && OUTFITS[FALLBACK[other]]) || DESIGNS[other] || vorn;
      const [c2] = castOf(ctx, lab, [d2]);
      reset(lab, poseOf(lab.design, kind));
      lab.char.root.position.set(-2.5, 0, 0);
      c2.setVisible(true);
      c2.root.position.set(2.5, 0, 0); c2.setFacing(-1);
      c2.play(poseOf(c2.design, kind), { fade: 0, restart: true });
      c2.update(0, 0); c2.teleport();
      lab.view({ target: [0, 1.2, 0], dist: 7.6, yaw: 0, pitch: 5, fov: 40 });
    },
    /** Every glow channel flaring (amount, seconds): inner energy at full burn. */
    glow(ctx, lab, amount = 2.5, dur = 0.8) { reset(lab); if (lab.glow) lab.glow.flare('all', amount, dur); lab.view({ target: [lab.ox + 0.02, lab.headY - 0.3, 0], dist: 2.6, yaw: 30, pitch: 3, fov: 35 }); },
    weapon(ctx, lab, name = 'greatsword', part = 'all', yaw = 12) {
      const g = weaponDisplay(ctx, lab, name);
      lab.show(name);
      const box = new THREE.Box3().setFromObject(g);
      const c = box.getCenter(new THREE.Vector3()), s = box.getSize(new THREE.Vector3());
      if (part === 'hilt') lab.view({ target: [c.x - s.x * 0.36, c.y, 0], dist: 0.8, yaw: 16, pitch: 8, fov: 35 });
      else if (part === 'tip') lab.view({ target: [c.x + s.x * 0.3, c.y, 0], dist: 0.85, yaw: 16, pitch: 8, fov: 35 });
      else if (part === 'mid') lab.view({ target: [c.x, c.y, 0], dist: 0.8, yaw: 10, pitch: 6, fov: 35 });
      else lab.view({ target: [c.x, c.y, 0], dist: Math.max(s.x, s.y) * 1.15, yaw, pitch: 6, fov: 35 });
    },
    weapons(ctx, lab) {
      const gs = ['greatsword', 'crescents', 'spear'].map((n) => weaponDisplay(ctx, lab, n));
      lab.show('none');
      gs.forEach((g, i) => { g.visible = true; g.position.set(0, 1.95 - i * 0.48, 0); });
      lab.view({ target: [0.3, 1.45, 0], dist: 3.3, yaw: 8, pitch: 4, fov: 35 });
    },
    /** Material swatches, four per page (the last page is the brocade sampler); zoom > 1 moves in; item = one swatch. */
    swatches(ctx, lab, page = 0, zoom = 1, item = null) {
      const g = swatchDisplay(ctx, lab), info = g.userData.info;
      lab.show('swatches');
      const last = page >= info.pages - 1;
      const cx = last ? info.brocadeX : item != null ? info.xOf(item) : (page * 4 + 1.5) * info.pitch;
      lab.view({ target: [cx, 1.0 + (last ? 0.26 : 0.235), 0], dist: (last ? 1.25 : item != null ? 0.85 : 1.72) / zoom, yaw: 8, pitch: 3, fov: 35 });
      return last ? info.labels.slice(-8) : info.labels.slice(page * 4, page * 4 + 4);
    },
    /** Kit parts on a rack: page 0 heads (masks, hats, wraps, hair), page 1 armour accents and ornaments. */
    parts(ctx, lab, page = 0, yaw = 18) {
      const g = partsDisplay(ctx, lab);
      lab.show('parts');
      lab.view({ target: [0.0, page ? 0.62 : 1.5, 0], dist: 2.05, yaw, pitch: 4, fov: 35 });
    },
    kit(ctx, lab, page = 0) { return lab.play('parts', page); },
    stats(ctx, lab) { return { ...lab.char.stats, design: lab.design.id, bodyScale: lab.char.bodyScale, headY: +lab.headY.toFixed(3) }; },
    /** Triangles / draw calls / bones of every design at the high and low tiers (built off-scene, then disposed). */
    budget(ctx) {
      const out = {};
      for (const tier of ['high', 'low']) {
        const q = { ...ctx.quality, tier, cloth: tier === 'low' ? 0.5 : 1 };
        for (const [id, d] of Object.entries(DESIGNS)) {
          try {
            const c = createCharacter({ ...ctx, quality: q }, d, { parent: null, name: 'budget' });
            out[id + '@' + tier] = { ...c.stats, springs: (d.springs || []).reduce((n, s) => n + s.bones.length, 0), cloths: (d.cloth || []).length, ok: c.stats.triangles <= 60000 && c.stats.drawCalls <= 6 };
            c.dispose();
          } catch (e) { out[id + '@' + tier] = { error: String(e.message || e) }; }
        }
      }
      return out;
    },
    /** Create / dispose cycle of every design: GPU geometries / textures / programs before and after. */
    leaks(ctx, lab, n = 3) {
      const info = () => ({ geo: ctx.renderer.info.memory.geometries, tex: ctx.renderer.info.memory.textures, prog: ctx.renderer.info.programs.length });
      lab.show('none');
      ctx.renderer.render(ctx.scene, ctx.camera);
      const before = info();
      for (let k = 0; k < n; k++) {
        for (const d of [...Object.values(HEROES), ...Object.values(OUTFITS)]) {
          const { char: c, design } = spawn(ctx, d, 'leak');
          c.play(poseOf(design, 'hero'), { fade: 0 });
          c.update(1 / 60, 1 / 60);
          ctx.renderer.render(ctx.scene, ctx.camera);
          c.dispose();
        }
      }
      ctx.renderer.render(ctx.scene, ctx.camera);
      const after = info();
      lab.show('char');
      return { before, after, leaked: after.geo - before.geo + (after.tex - before.tex) + (after.prog - before.prog) };
    },
    dispose(ctx, lab, n = 3) { return lab.play('leaks', n); },
    /**
     * CPU cost of char.update() for every design (ms per update at 60 Hz over a combat chain with turns, steps and
     * wind): mean, and the mean of each frame's fastest of `runs` passes (the uncontended cost on a shared machine).
     * Budget: <= 1.0 ms per character on desktop.
     */
    cpu(ctx, lab, frames = 240, runs = 5, ids = null) {
      const out = {};
      for (const [id, d] of Object.entries(DESIGNS)) {
        if (ids && !ids.includes(id)) continue;
        let c;
        try { c = createCharacter(ctx, d, { parent: null, name: 'cpu' }); } catch (e) { out[id] = { error: String(e.message || e) }; continue; }
        if (d.attach) d.attach(c);
        const chain = ['demo.combo1', 'demo.combo2', 'demo.slam', 'demo.walkF', 'demo.guard', poseOf(d, 'combat'), poseOf(d, 'strike')];
        const best = new Float64Array(frames).fill(1e9);
        let sum = 0;
        for (let r = 0; r < runs; r++) {
          c.root.position.set(0, 0, 0); c.setFacing(1); c.play(poseOf(d, 'hero'), { fade: 0, restart: true }); c.update(0, 0); c.teleport();
          c.wind = [3, 0, 1.5];
          for (let f = 0; f < frames; f++) {
            if (f % 34 === 0) c.play(chain[(f / 34) % chain.length | 0], { fade: 0.08, restart: true });
            if (f % 90 === 45) c.setFacing(-c.facing);
            c.root.position.x = 0.6 * Math.sin(f * 0.09);
            const t0 = performance.now();
            c.update(1 / 60, 1 / 60);
            const dt = performance.now() - t0;
            sum += dt; if (dt < best[f]) best[f] = dt;
          }
        }
        let b = 0; for (let f = 0; f < frames; f++) b += best[f];
        out[id] = { ms: +(b / frames).toFixed(3), mean: +(sum / (frames * runs)).toFixed(3), springBones: (d.springs || []).reduce((n, s) => n + s.bones.length, 0), cloths: (d.cloth || []).length, bones: c.stats.bones, ok: b / frames <= 1.0 };
        c.dispose();
      }
      return out;
    },
    /** Texture set generation: ms per set generated so far (sets are generated on first use); all = generate every set first. */
    texgen(ctx, lab, all = false) {
      if (all) TEX.prewarmTextureSets();
      const t = TEX.textureSetTimings();
      return { sets: t, total: +Object.values(t).reduce((a, b) => a + b, 0).toFixed(1) };
    },
    /** Lowest world y (m) of the footwear geometry (foot / toe bones) in the design's poses: soles on the floor, nothing under it. */
    contact(ctx, lab) {
      const out = {}, c = lab.char, v = new THREE.Vector3(), names = ['footR', 'footL', 'toeR', 'toeL'];
      const fi = names.map((n) => c.rig.index[n]);
      for (const kind of ['hero', 'combat', 'strike']) {
        reset(lab, poseOf(lab.design, kind));
        for (let i = 0; i < 30; i++) c.update(1 / 60, 1 / 60);
        c.root.updateMatrixWorld(true);
        const lo = {};
        for (const mesh of Object.values(c.meshes)) {
          const P = mesh.geometry.attributes.position, SI = mesh.geometry.attributes.skinIndex, SW = mesh.geometry.attributes.skinWeight;
          for (let i = 0; i < P.count; i++) {
            const k = fi.indexOf(SI.getX(i));
            if (k < 0 || SW.getX(i) < 0.99) continue;
            v.fromBufferAttribute(P, i); mesh.applyBoneTransform(i, v); v.applyMatrix4(mesh.matrixWorld);
            lo[names[k]] = Math.min(lo[names[k]] ?? 9, v.y);
          }
        }
        out[kind] = Object.fromEntries(Object.entries(lo).map(([k, x]) => [k, +x.toFixed(4)]));
      }
      reset(lab);
      return out;
    },
    /** Rig QA (src/char/qa.js) of the design's proportions + weapon over the demo clips and its lab poses. */
    qa(ctx, lab, clips) {
      const list = clips || ['demo.idle', 'demo.guard', 'demo.combo1', 'demo.combo2', 'demo.slam', 'demo.walkF', poseOf(lab.design, 'hero'), poseOf(lab.design, 'combat'), poseOf(lab.design, 'strike')];
      const out = {};
      for (const c of list) {
        const a = auditClip(lab.char, c);
        out[c] = {
          nan: a.nan, floor: Object.fromEntries(Object.entries(a.floor).map(([k, v]) => [k, v.min])),
          below: Object.fromEntries(Object.entries(a.floor).filter(([, v]) => v.below > 0).map(([k, v]) => [k, v.below])),
          hits: a.intersections.slice(0, 4).map((x) => x.pair + ':' + x.depth),
          limits: Array.isArray(a.limits) ? a.limits.length : Object.keys(a.limits || {}).length,
        };
      }
      reset(lab);
      return out;
    },
  },
});

/** One hero as a black shape on grey. */
function silOne(ctx, lab) {
  reset(lab);
  silhouette(ctx, lab, [lab.char]);
  lab.view({ target: [lab.ox, lab.headY * 0.62, 0], dist: lab.headY * 2.6, yaw: 0, pitch: 3, fov: 35 });
}

function lineup(ctx, lab, mode = 'sil', kind = 'hero', set = lab.kitRoster ? 'kit' : 'heroes') {
  const cast = castOf(ctx, lab, set === 'kit' ? Object.values(OUTFITS) : Object.values(HEROES));
  reset(lab);
  lab.char.setVisible(false);
  const xs = [-1.85, 0, 1.85];
  cast.forEach((c, i) => {
    c.setVisible(true);
    c.root.position.set(xs[i], 0, 0); c.setFacing(1);
    c.play(poseOf(c.design, mode === 'fight' ? 'combat' : kind), { fade: 0, restart: true });
    c.update(0, 0); c.teleport();
  });
  if (mode === 'sil') silhouette(ctx, lab, cast);
  if (mode === 'fight') lab.view({ target: [0, 1.15, 0], dist: 8.4, yaw: 0, pitch: 5, fov: 40 });
  else lab.view({ target: [0, 1.14, 0], dist: 6.9, yaw: mode === 'lit' ? 14 : 0, pitch: 3, fov: 35 });
}

/**
 * createCharacter + the design's glow control (design.attach, or attachGlow with design.glow). A hero design that
 * throws (it is being rewritten) is replaced by its reference outfit; the error is logged once.
 * @returns {{ char, design }}
 */
function spawn(ctx, design, name) {
  let c, d = design;
  try { c = createCharacter(ctx, d, { name }); } catch (e) {
    const fb = OUTFITS[FALLBACK[design.id]];
    console.error(`[ed] art lab: design ${design.id} failed to build (${e && e.message}); showing ${fb ? fb.id : 'nothing'}`);
    if (!fb) throw e;
    d = fb; c = createCharacter(ctx, d, { name });
  }
  if (d.attach) d.attach(c); else if (d.glow) attachGlow(c, d.glow);
  return { char: c, design: d };
}

/** World height of the head bone pivot (skull base) in the current pose: framing reference per design. */
function headHeight(char) {
  char.root.updateMatrixWorld(true);
  return char.bones.head.getWorldPosition(new THREE.Vector3()).y;
}

/** Extra characters (lineup / duel), created once per design and kept hidden. */
function castOf(ctx, lab, designs) {
  lab.cast = lab.cast || {};
  return designs.map((d) => {
    if (d === lab.design) return lab.char;
    if (!lab.cast[d.id]) { const { char } = spawn(ctx, d, d.id); lab.cast[d.id] = char; lab.others.push(char); }
    return lab.cast[d.id];
  });
}

/** Black shapes on grey: lights / environment / glow off, alpha cut-outs kept. */
function silhouette(ctx, lab, chars) {
  ctx.scene.background = new THREE.Color(0xd8d8d8);
  ctx.scene.fog = null;
  lab.floor.visible = false;
  lab.sil = { env: ctx.scene.environmentIntensity, lights: [], mats: [], chars };
  ctx.scene.traverse((o) => { if (o.isLight) { lab.sil.lights.push([o, o.intensity]); o.intensity = 0; } });
  ctx.scene.environmentIntensity = 0;
  for (const c of chars) {
    if (c.glow) c.glow.gain = 0;
    for (const m of Object.values(c.materials)) { m.userData.kit.uRim.value.w += 100; m.userData.kit.uGlowScale.value = 0; lab.sil.mats.push(m); }
  }
}

function reset(lab, pose) {
  const ctx = lab.ctx;
  lab.st.spin = null; lab.st.hold = null; lab.st.sway = null;
  lab.show('char');
  ctx.scene.background = lab.bg.background;
  ctx.scene.fog = lab.bg.fog;
  if (lab.sil) {
    for (const [l, i] of lab.sil.lights) l.intensity = i;
    ctx.scene.environmentIntensity = lab.sil.env;
    for (const m of lab.sil.mats) { m.userData.kit.uRim.value.w -= 100; m.userData.kit.uGlowScale.value = 1; }
    for (const c of lab.sil.chars) if (c.glow) c.glow.gain = 1;
    lab.sil = null;
  }
  for (const c of lab.others) c.setVisible(false);
  lab.ox = lab.arena ? -2.5 : 0;
  lab.char.root.position.set(lab.ox, 0, 0);
  lab.char.root.rotation.y = 0;
  lab.char.wind = [0, 0, 0];
  lab.char.setFacing(1);
  lab.char.play(pose || lab.hero, { fade: 0, restart: true });
  lab.char.update(0, 0);
  lab.char.teleport();
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
  return g;
}

/** Material swatches (src/char/kit/swatch.js) on two slots: opaque and cut-out. */
function swatchDisplay(ctx, lab) {
  if (lab.displays.swatches) return lab.displays.swatches;
  const sk = createStaticKit();
  const info = buildSwatches(sk, 'swatch');
  const g = sk.finish({ swatch: createKitMaterial(SWATCH_MATERIAL), swatchCut: createKitMaterial({ ...SWATCH_MATERIAL, cutout: true }) });
  g.userData.info = info;
  g.position.set(0, 1.0, 0);
  ctx.scene.add(g);
  lab.displays.swatches = g;
  return g;
}

/** Rack of kit parts (static): heads on the upper shelf (y 1.5), armour accents and ornaments on the lower (y 0.6). */
function partsDisplay(ctx, lab) {
  if (lab.displays.parts) return lab.displays.parts;
  const sk = createStaticKit();
  const P = (g, look, at, rot) => g && put(sk, look.set === 'hair' || look.set === 'gauze' ? 'cut' : 'gear', null, g, look, { at, rot });
  const wrapL = { ...MURIM.hempInk, color: [0.03, 0.028, 0.028] }, HAIR = MURIM.hair;
  const head = (x, y = 1.4) => { const w = H.headWrap({}); P(w.wrap, wrapL, [x, y, 0]); P(w.turns, wrapL, [x, y, 0]); P(w.slot, MURIM.dark, [x, y, 0]); return [x, y, 0]; };
  // heads: demon mask + topknot, silver mask + wide hat, face wrap + cone hat, bare wrap + eyes + headband
  let at = head(-0.9);
  const dm = H.demonMask({});
  P(dm.face, { ...MURIM.ironCharred, vein: 0.7 }, at); P(dm.pits, MURIM.dark, at); P(dm.eyes, MURIM.eye, at); P(dm.fangs, MURIM.bronze, at); P(dm.horns, MURIM.iron, at);
  P(H.hairCap({}), HAIR, at); const tk = H.topknot({}); P(tk.bun, HAIR, at); P(tk.tie, MURIM.cord, at); P(tk.pin, MURIM.bronze, at);
  at = head(-0.3);
  const sm = H.silverMask({});
  P(sm.face, MURIM.silverPlain, at); P(sm.pits, MURIM.dark, at); P(sm.eyes, MURIM.eye, at); P(sm.ridge, MURIM.silver, at);
  const wide = H.bambooHat({ R: 0.33, h: 0.075, y: 0.2, crown: 0.34, dip: 0.07 });
  P(wide.shell, MURIM.bamboo, at, [0, 0, -6]); P(wide.knob, MURIM.silverPlain, at, [0, 0, -6]); P(wide.cords, MURIM.cord, at, [0, 0, -6]);
  at = head(0.3);
  P(H.faceWrap({}), { ...MURIM.hempInk, color: [0.03, 0.022, 0.04] }, at); P(H.eyes({ grow: 0.0052 }).glow, MURIM.eye, at);
  const cone = H.bambooHat({ R: 0.285, h: 0.2, y: 0.118, bell: 0.92 });
  P(cone.shell, MURIM.bambooDark, at, [0, 0, -9]); P(cone.knob, MURIM.bronze, at, [0, 0, -9]); P(cone.cords, MURIM.cord, at, [0, 0, -9]);
  at = head(0.9);
  const ey = H.eyes({}); P(ey.glow, MURIM.eye, at);
  P(H.headband({ motif: 2 }).band, { ...MURIM.trim, color: [0.12, 0.01, 0.008] }, at);
  // armour accents and ornaments
  const bp = M.beastPauldron({});
  at = [-0.95, 0.62, 0];
  P(bp.cop, { ...MURIM.ironCharred, vein: 0.4 }, at, [-20, 0, 0]); P(bp.pits, MURIM.dark, at, [-20, 0, 0]); P(bp.eyes, MURIM.eye, at, [-20, 0, 0]); P(bp.fangs, MURIM.bronze, at, [-20, 0, 0]); P(bp.ring, MURIM.bronze, at, [-20, 0, 0]);
  const sp = M.lamellarSpaulder({ code: 0.15 });
  sp.rows.forEach((g) => P(g, MURIM.lamellar, [-0.6, 0.7, 0])); P(sp.cap, MURIM.lacquer, [-0.6, 0.7, 0]);
  const wg = M.waistGuard({ code: 0.15 });
  wg.rows.forEach((g) => P(g, MURIM.lamellarIron, [-0.22, 0.74, -0.1], [0, -76, 0])); P(wg.head, MURIM.leather, [-0.22, 0.74, -0.1], [0, -76, 0]); P(wg.trim, { ...MURIM.trim, color: [0.1, 0.01, 0.008] }, [-0.22, 0.74, -0.1], [0, -76, 0]);
  const br = M.bracer({});
  P(br.plate, MURIM.lacquer, [0.08, 0.64, 0], [0, 60, 0]); P(br.straps, MURIM.leather, [0.08, 0.64, 0], [0, 60, 0]); P(br.studs, MURIM.bronze, [0.08, 0.64, 0], [0, 60, 0]);
  P(M.limbWrap({ y0: 0.1, y1: -0.12 }), MURIM.wrap, [0.26, 0.64, 0]);
  const bt = M.clothBoot({});
  const BOOT = { ...MURIM.hempInk };
  for (const [g, o] of [[bt.upper, 0], [bt.heel, 0], [bt.sole, 1], [bt.shaft, 2], [bt.top, 3]]) P(g, o === 1 ? MURIM.hemp : o === 3 ? MURIM.trim : BOOT, [0.48, o >= 2 ? 0.6 + 0.085 + 0.43 : 0.6 + 0.085, 0]);
  P(bt.toe, BOOT, [0.48 + 0.135, 0.6 + 0.03, 0]); P(bt.toeSole, MURIM.hemp, [0.48 + 0.135, 0.6 + 0.03, 0]);
  const gd = M.gourd({});
  P(gd.body, { ...MURIM.lacquerRed, color: [0.14, 0.05, 0.016] }, [0.78, 0.76, 0]); P(gd.stopper, MURIM.wood, [0.78, 0.76, 0]); P(gd.cord, MURIM.cord, [0.78, 0.76, 0]);
  const pd = M.pendant({});
  for (const [g, look] of [[pd.cord, MURIM.cord], [pd.knot, MURIM.cord], [pd.jade, MURIM.jade], [pd.tasselHead, MURIM.gilt], [pd.strands, MURIM.horsehair]]) P(g, look, [0.94, 0.8, 0]);
  const ts = M.tassel({});
  P(ts.head, MURIM.gilt, [1.06, 0.78, 0]); P(ts.strands, MURIM.horsehair, [1.06, 0.78, 0]);
  const mat = { ...SWATCH_MATERIAL, glow: { inlay: [5, 3, 1], vein: [4.5, 1.3, 0.2], eye: [8, 3, 0.7] } };
  const g = sk.finish({ gear: createKitMaterial(mat), cut: createKitMaterial({ ...mat, cutout: true }) });
  ctx.scene.add(g);
  lab.displays.parts = g;
  return g;
}
