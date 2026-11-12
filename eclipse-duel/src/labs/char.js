// Character lab: the knight design on the neutral stage with a studio environment map. Scenarios cover pose / clip
// playback by name, turntables, facing flips, a cloth stress test and two fighters facing each other.
//
//   __ED.lab.play('clip', 'demo.combo1')          play a clip from the start (lab applies root motion)
//   __ED.lab.play('pose', 'demo.combo1', 0.3)     freeze a clip at a time
//   __ED.lab.play('chain', ['demo.combo1', ...])  play clips back to back (each starts when the previous finishes)
//   __ED.lab.play('turn', 45)                     orbit the camera around the fighter (degrees)
//   __ED.lab.play('flip') / ('duel') / ('cloth') / ('reset')
//   __ED.char, __ED.chars                         the characters

import * as THREE from 'three';
import { createLab, ORDER } from '../core/lab.js';
import { createCharacter } from '../char/index.js';
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
      if (st.chain && a.finished) {
        st.chainIdx++;
        if (st.chainIdx < st.chain.length) a.play(st.chain[st.chainIdx], { fade: 0.08 });
        else st.chain = null;
      }
      if (st.stress) st.stress(dg);
    }, ORDER.CHAR);
    window.__ED.char = a;
    window.__ED.chars = chars;
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
    chain(ctx, lab, names) {
      const a = lab.chars[0];
      lab.st.chain = names; lab.st.chainIdx = 0;
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
