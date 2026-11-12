// Character lab: the knight design on the neutral stage with a studio environment map. Scenarios cover pose / clip
// playback by name, turntables, facing flips, a cloth stress test and two fighters facing each other.
//
//   __ED.lab.play('clip', 'demo.combo1')          play a clip from the start (lab applies root motion)
//   __ED.lab.play('pose', 'demo.combo1', 0.3)     freeze a clip at a time
//   __ED.lab.play('chain', ['demo.combo1', ...], [0.4, 0.44])  play clips back to back; each starts when the previous
//                                                 finishes or reaches its cancel time (optional array)
//   __ED.lab.play('turn', 45)                     orbit the camera around the fighter (degrees)
//   __ED.lab.play('flip') / ('duel') / ('cloth') / ('reset')
//   __ED.lab.play('joints') / ('bones')           joint torture pose / toggle the skeleton overlay
//   __ED.char, __ED.chars                         the characters
//   __ED.anim                                     defineClip / definePose / ... for live authoring (call invalidateClips()
//                                                 after re-defining a clip, then play it again)

import * as THREE from 'three';
import { createLab, ORDER } from '../core/lab.js';
import { createCharacter, defineClip, definePose, mirrorClip, mirrorPose, invalidateClips, listClips, listPoses } from '../char/index.js';
import { knight } from '../char/designs/knight.js';
import '../char/clips/demo.js';

function studioEnv(renderer) {
  // dark arena-like studio: cool sky dome, warm low key panel, cool rim panels, near-black floor
  const scene = new THREE.Scene();
  const dome = new THREE.Mesh(new THREE.SphereGeometry(20, 32, 16), new THREE.ShaderMaterial({
    side: THREE.BackSide, depthWrite: false,
    vertexShader: 'varying vec3 vP; void main(){ vP = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }',
    fragmentShader: `varying vec3 vP; void main(){
      float y = vP.y;
      vec3 top = vec3(0.05, 0.065, 0.09), hor = vec3(0.16, 0.12, 0.1), flo = vec3(0.012, 0.011, 0.012);
      vec3 c = y > 0.0 ? mix(hor, top, pow(y, 0.6)) : mix(hor * 0.4, flo, pow(-y, 0.4));
      gl_FragColor = vec4(c, 1.0); }`,
  }));
  scene.add(dome);
  const panel = (w, h, col, pos) => {
    const m = new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshBasicMaterial({ color: new THREE.Color(...col), side: THREE.DoubleSide }));
    m.position.set(...pos); m.lookAt(0, 1.2, 0); scene.add(m);
  };
  panel(6, 3, [2.4, 1.9, 1.4], [-6, 7, 8]);
  panel(3, 6, [0.5, 0.75, 1.5], [7, 3, -8]);
  panel(8, 1.2, [0.9, 0.55, 0.3], [0, 1.5, 12]);
  panel(2, 5, [0.35, 0.5, 1.0], [-9, 2, -4]);
  const pmrem = new THREE.PMREMGenerator(renderer);
  const tex = pmrem.fromScene(scene, 0.035).texture;
  pmrem.dispose();
  return tex;
}

createLab({
  view: { target: [0, 1.05, 0], dist: 5.4, yaw: 0, pitch: 4, fov: 40 },
  setup(ctx, lab) {
    ctx.scene.environment = studioEnv(ctx.renderer);
    ctx.scene.environmentIntensity = 1;
    lab.lights.key.intensity = 2.6;
    lab.lights.rim.intensity = 2.2;
    const a = createCharacter(ctx, knight, { name: 'p1' });
    const chars = [a];
    const st = { followRoot: true, chain: null, chainIdx: 0, stress: null, applyRoot: true };
    lab.st = st;
    ctx.onUpdate((dg, dr) => {
      for (const c of chars) {
        c.update(dg, dr);
        if (st.applyRoot && c.root.visible) {
          c.root.position.x += c.rootDelta.f * c.facing;
          if (Math.abs(c.root.position.x) > 8) c.root.position.x = Math.sign(c.root.position.x) * 8;
        }
      }
      // chains advance when the clip finishes, or at its cancel time (game-style combo cancel)
      if (st.chain && (a.finished || (st.chainAt && st.chainAt[st.chainIdx] !== undefined && a.clipTime >= st.chainAt[st.chainIdx]))) {
        st.chainIdx++;
        if (st.chainIdx < st.chain.length) a.play(st.chain[st.chainIdx], { fade: 0.06, restart: true });
        else st.chain = null;
      }
      if (st.stress) st.stress(dg);
    }, ORDER.CHAR);
    window.__ED.char = a;
    window.__ED.chars = chars;
    window.__ED.anim = { defineClip, definePose, mirrorClip, mirrorPose, invalidateClips, listClips, listPoses };
    lab.chars = chars;
    lab.makeSecond = () => {
      if (chars.length > 1) return chars[1];
      const b = createCharacter(ctx, knight, { name: 'p2' });
      chars.push(b);
      return b;
    };
    a.play('demo.idle', { fade: 0 });
    a.update(0, 0);
  },
  scenarios: {
    reset(ctx, lab) {
      const a = lab.chars[0];
      lab.st.chain = null; lab.st.stress = null; lab.st.applyRoot = true;
      a.root.position.set(0, 0, 0); a.setFacing(1); a.teleport();
      a.play('demo.idle', { fade: 0 });
      for (let i = 1; i < lab.chars.length; i++) lab.chars[i].setVisible(false);
      lab.view({ target: [0, 1.05, 0], dist: 5.4, yaw: 0, pitch: 4 });
    },
    clip(ctx, lab, name, speed = 1) {
      const a = lab.chars[0];
      lab.st.chain = null;
      a.play(name, { fade: 0.1, speed, restart: true });
    },
    pose(ctx, lab, name, t = 0) {
      const a = lab.chars[0];
      lab.st.chain = null; lab.st.applyRoot = false;
      a.play(name, { fade: 0, restart: true });
      a.setClipTime(t);
    },
    chain(ctx, lab, names, cancelAt = null) {
      const a = lab.chars[0];
      lab.st.chain = names; lab.st.chainIdx = 0; lab.st.chainAt = cancelAt;
      a.play(names[0], { fade: 0.1, restart: true });
    },
    turn(ctx, lab, deg = 45, dist) {
      lab.view({ yaw: deg, ...(dist ? { dist } : {}) });
    },
    flip(ctx, lab, turn = 0) {
      const a = lab.chars[0];
      a.setFacing(-a.facing, { turn });
    },
    duel(ctx, lab) {
      const a = lab.chars[0], b = lab.makeSecond();
      b.setVisible(true);
      a.root.position.set(-1.6, 0, 0); a.setFacing(1); a.teleport();
      b.root.position.set(1.6, 0, 0); b.setFacing(-1); b.teleport();
      lab.st.applyRoot = false;
      a.play('demo.guard', { fade: 0 }); b.play('demo.idle', { fade: 0 });
      a.lookAt(b.sockets.head); b.lookAt(a.sockets.head);
      lab.view({ target: [0, 1.1, 0], dist: 7.2, yaw: 0, pitch: 5 });
    },
    joints(ctx, lab) {
      // extreme FK angles on every major joint: checks skin blending, twist distribution, plate overlaps
      definePose('lab.joints', {
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
      invalidateClips();
      lab.chars[0].play('lab.joints', { fade: 0, restart: true });
    },
    bones(ctx, lab) {
      if (!lab.skel) { lab.skel = new THREE.SkeletonHelper(lab.chars[0].root); ctx.scene.add(lab.skel); }
      else lab.skel.visible = !lab.skel.visible;
    },
    cloth(ctx, lab) {
      // stress: run back and forth, teleport, flip facing, while attacking
      const a = lab.chars[0];
      lab.st.applyRoot = false;
      let t = 0;
      a.root.position.set(0, 0, 0);
      a.play('demo.combo3', { fade: 0.05, restart: true });
      lab.st.stress = (dt) => {
        t += dt;
        a.root.position.x = Math.sin(t * 5) * 1.2 + (t > 1.2 ? 1.5 : 0);
        if (t > 0.6 && t - dt <= 0.6) a.setFacing(-1);
        if (t > 1.2 && t - dt <= 1.2) a.setFacing(1);
        if (t > 1.6 && t - dt <= 1.6) a.play('demo.slam', { restart: true });
        if (a.finished) a.play('demo.combo3', { restart: true });
      };
    },
  },
});
