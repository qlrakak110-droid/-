// Camera lab: two 1.9 m dummy fighters on a dressed stage (arena boundary posts at |x| = 9, a colonnade for parallax,
// an eclipse in the sky), driven by scripted motions so fight framing, shake / kicks / zoom, every shot-vocabulary
// entry and a full sample ultimate can be captured.
//
// Flags: #hud (mock fight HUD to judge headroom), #scope (live plot of shake / kick / framing channels).
//   __ED.lab.play('mid' | 'walk' | 'swap' | 'shot_orbitSweep' | 'shotM_orbitSweep' | 'ult' | 'ultM' | 'overview' ...)

import * as THREE from 'three';
import { createLab } from '../core/lab.js';
import { clamp, lerp, Ease, DEG } from '../core/math.js';
import { createCameraDirector } from '../cam/index.js';
import * as shots from '../cam/shots.js';

const CHEST = 1.35;

// ---- dummy fighters ------------------------------------------------------------------------------------------------
function makeDummy(scene, { accent, visor, metal }) {
  const root = new THREE.Group();
  const body = new THREE.Group();          // pivots at the hips so knock-backs tilt naturally
  body.position.y = 1.0;
  root.add(body);
  const mArmour = new THREE.MeshStandardMaterial({ color: metal, metalness: 0.75, roughness: 0.38 });
  const mSuit = new THREE.MeshStandardMaterial({ color: 0x17181d, metalness: 0.2, roughness: 0.75 });
  const mAccent = new THREE.MeshStandardMaterial({ color: accent, metalness: 0.4, roughness: 0.5, emissive: accent, emissiveIntensity: 0.15 });
  const mGlow = new THREE.MeshBasicMaterial({ color: new THREE.Color(visor[0], visor[1], visor[2]) });
  const add = (geo, mat, x, y, z, parent = body) => { const m = new THREE.Mesh(geo, mat); m.position.set(x, y, z); m.castShadow = true; parent.add(m); return m; };

  // fighting stance: front / back leg split along f so the silhouette reads side-on
  const leg = new THREE.CapsuleGeometry(0.075, 0.74, 4, 10);
  add(leg, mSuit, 0.13, -0.5, 0.09).rotation.z = 0.2;
  add(leg, mSuit, -0.15, -0.5, -0.09).rotation.z = -0.24;
  const torso = add(new THREE.CapsuleGeometry(0.2, 0.3, 6, 16), mArmour, 0.02, 0.27, 0);
  torso.scale.set(0.85, 1, 1.18);
  add(new THREE.BoxGeometry(0.22, 0.08, 0.56), mAccent, 0.02, 0.5, 0);                // pauldron bar
  add(new THREE.BoxGeometry(0.3, 0.07, 0.42), mAccent, 0.0, -0.02, 0);                 // belt
  add(new THREE.SphereGeometry(0.115, 20, 14), mArmour, 0.03, 0.74, 0);                // head
  add(new THREE.BoxGeometry(0.05, 0.03, 0.15), mGlow, 0.135, 0.755, 0);                // visor: shows facing
  add(new THREE.ConeGeometry(0.045, 0.2, 10), mAccent, -0.03, 0.89, 0).rotation.z = 0.4; // crest, leans back
  const arm = add(new THREE.CapsuleGeometry(0.06, 0.36, 4, 8), mSuit, 0.17, 0.32, 0.25);
  arm.rotation.z = 0.75;
  // weapon: pivot at the camera-side hand; blade along +Y of the pivot
  const weapon = new THREE.Group();
  weapon.position.set(0.28, 0.14, 0.27);
  body.add(weapon);
  add(new THREE.BoxGeometry(0.045, 0.3, 0.045), mSuit, 0, 0.0, 0, weapon);            // grip
  add(new THREE.BoxGeometry(0.06, 0.035, 0.24), mAccent, 0, 0.16, 0, weapon);         // guard
  add(new THREE.BoxGeometry(0.075, 1.15, 0.014), mArmour, 0, 0.75, 0, weapon);        // blade
  add(new THREE.BoxGeometry(0.012, 1.1, 0.018), mGlow, 0.04, 0.75, 0, weapon);        // hot edge

  const chest = new THREE.Object3D();
  chest.position.set(0, CHEST - 1.0, 0);
  body.add(chest);
  scene.add(root);
  const d = {
    root, body, weapon, chest,
    x: 0, y: 0, facing: 1, weaponDeg: 35, tilt: 0, lean: 0,
    apply() {
      root.position.set(d.x, d.y, 0);
      root.rotation.y = d.facing > 0 ? 0 : Math.PI;
      root.scale.z = d.facing > 0 ? 1 : -1;           // true mirror: the weapon stays on the camera side
      body.rotation.z = d.tilt * DEG - d.lean * DEG;
      weapon.rotation.z = (d.weaponDeg - 90) * DEG;
    },
  };
  return d;
}

// ---- stage dressing ------------------------------------------------------------------------------------------------
function dressStage(scene) {
  const stone = new THREE.MeshStandardMaterial({ color: 0x3a3833, roughness: 0.85, metalness: 0.02 });
  const n = 22, R = 13.5;
  const pillars = new THREE.InstancedMesh(new THREE.CylinderGeometry(0.42, 0.5, 7, 12), stone, n);
  const m = new THREE.Matrix4();
  let k = 0;
  for (let i = 0; i < n; i++) {
    const a = Math.PI * (0.42 + (1.16 * i) / (n - 1));    // the far half of the ring (z < 0) and the flanks
    const h = 0.55 + 0.45 * Math.abs(Math.sin(i * 2.7));    // ruined: uneven heights
    m.compose(new THREE.Vector3(Math.sin(a) * R, 3.5 * h, Math.cos(a) * R), new THREE.Quaternion(), new THREE.Vector3(1, h, 1));
    pillars.setMatrixAt(k++, m);
  }
  pillars.castShadow = true;
  scene.add(pillars);
  const wall = new THREE.Mesh(new THREE.CylinderGeometry(17, 17, 4.5, 64, 1, true, Math.PI * 0.5, Math.PI), new THREE.MeshStandardMaterial({ color: 0x24221f, roughness: 0.95, side: THREE.BackSide }));
  wall.position.y = 2.25;
  scene.add(wall);
  // arena limits |x| = 9: amber posts
  const postMat = new THREE.MeshBasicMaterial({ color: new THREE.Color(0.75, 0.3, 0.08) });
  const posts = new THREE.InstancedMesh(new THREE.BoxGeometry(0.06, 2.6, 0.06), postMat, 4);
  [[-9, 0.6], [-9, -0.6], [9, 0.6], [9, -0.6]].forEach(([x, z], i) => { m.makeTranslation(x, 1.3, z); posts.setMatrixAt(i, m); });
  scene.add(posts);
  const lineMat = new THREE.MeshBasicMaterial({ color: new THREE.Color(0.6, 0.24, 0.07) });
  const lines = new THREE.InstancedMesh(new THREE.BoxGeometry(0.04, 0.01, 1.4), lineMat, 2);
  [-9, 9].forEach((x, i) => { m.makeTranslation(x, 0.006, 0); lines.setMatrixAt(i, m); });
  scene.add(lines);
  // eclipse: black disc with an HDR corona
  const ecl = new THREE.Group();
  ecl.position.set(0, 21, -70);
  const corona = new THREE.Mesh(new THREE.RingGeometry(4.6, 9, 64), new THREE.ShaderMaterial({
    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
    vertexShader: 'varying vec2 vP; void main(){ vP = position.xy; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }',
    fragmentShader: 'varying vec2 vP; void main(){ float r = length(vP); float a = atan(vP.y, vP.x); float k = exp(-(r-4.6)*1.1) * (0.75 + 0.25*sin(a*7.0)*sin(a*3.0+1.0)); gl_FragColor = vec4(vec3(3.2,2.6,2.0)*k, 1.0); }',
  }));
  const disc = new THREE.Mesh(new THREE.CircleGeometry(4.6, 64), new THREE.MeshBasicMaterial({ color: 0x000000 }));
  disc.position.z = 0.01;
  ecl.add(corona, disc);
  scene.add(ecl);
}

// ---- overlays ------------------------------------------------------------------------------------------------------
function hudMock() {
  const el = document.createElement('div');
  el.style.cssText = 'position:absolute;inset:0;pointer-events:none;font:600 11px system-ui;color:#ddd';
  const bar = (side) => `<div style="position:absolute;top:3.2%;${side}:3%;width:38%;height:2.6%;border:1px solid rgba(255,255,255,.35);background:linear-gradient(${side === 'left' ? 'to left' : 'to right'},#5a1a1a 0 20%,#c8283c 20%);opacity:.8"></div>`;
  el.innerHTML = bar('left') + bar('right') + '<div style="position:absolute;top:2%;left:50%;transform:translateX(-50%);width:5%;height:6%;border:1px solid rgba(255,255,255,.35);background:rgba(0,0,0,.4)"></div>';
  document.getElementById('ui').appendChild(el);
}

function makeScope(cam) {
  const W = 420, H = 150, N = 240;
  const cv = document.createElement('canvas');
  cv.width = W; cv.height = H;
  cv.style.cssText = `position:absolute;left:8px;bottom:8px;width:${W}px;height:${H}px;background:rgba(6,8,12,.78);border:1px solid #333;pointer-events:none`;
  document.getElementById('ui').appendChild(cv);
  const g = cv.getContext('2d');
  const ch = [
    { name: 'yaw', col: '#ff8a5c', get: () => cam.debug.shake.yaw / DEG, s: 1.2 },
    { name: 'pitch', col: '#7fd4ff', get: () => cam.debug.shake.pitch / DEG, s: 1.2 },
    { name: 'roll', col: '#d8b46a', get: () => (cam.debug.shake.roll + cam.debug.shake.kroll) / DEG, s: 1.2 },
    { name: 'kfov', col: '#b48cff', get: () => cam.debug.shake.fov, s: 0.25 },
    { name: 'dist', col: '#9ee6a0', get: () => cam.debug.rig.dist - 7, s: 0.25 },
    { name: 'focus', col: '#ffffff', get: () => cam.debug.rig.focus, s: 0.25 },
  ];
  const buf = ch.map(() => new Float32Array(N));
  let head = 0;
  return () => {
    for (let i = 0; i < ch.length; i++) buf[i][head] = ch[i].get();
    head = (head + 1) % N;
    g.clearRect(0, 0, W, H);
    g.strokeStyle = '#2a2d36'; g.beginPath(); g.moveTo(0, H / 2); g.lineTo(W, H / 2); g.stroke();
    for (let i = 0; i < ch.length; i++) {
      g.strokeStyle = ch[i].col; g.beginPath();
      for (let j = 0; j < N; j++) {
        const v = buf[i][(head + j) % N] * ch[i].s;
        const y = H / 2 - clamp(v, -1, 1) * (H / 2 - 4);
        if (j) g.lineTo((j / (N - 1)) * W, y); else g.moveTo(0, y);
      }
      g.stroke();
      g.fillStyle = ch[i].col; g.fillText(ch[i].name, 6 + i * 52, 12);
    }
  };
}

// ---- motions -------------------------------------------------------------------------------------------------------
const seg = (t, a, b, e = Ease.inOutSine) => e(clamp((t - a) / (b - a)));

/**
 * Sample ultimate choreography (game time), written in the anchor's local frame so it mirrors. `ev(at, fn)` runs fn
 * once when the scenario clock passes `at` (impacts: event-driven cut + hit-stop).
 */
function ultMotion(an, tg, facing, ax0, tx0, onImpact) {
  const d0 = Math.abs(tx0 - ax0);
  const X = (f, x0) => x0 + f * facing;
  return (t, ev) => {
    // anchor: power-up (0-0.7), dash-slash (0.7-1.13), leap (1.6-2.05), hang, meteor slam (2.4-2.6), settle
    let af = 0, ay = 0, aw = lerp(35, 128, seg(t, 0.05, 0.7)), al = -8 * seg(t, 0.05, 0.7);
    af = lerp(0, d0 - 1.35, seg(t, 0.7, 1.05, Ease.outCubic));
    if (t > 0.98) aw = lerp(128, -38, seg(t, 0.98, 1.13, Ease.inQuad));
    if (t > 1.13) { aw = lerp(-38, 60, seg(t, 1.13, 1.6)); al = lerp(18, 0, seg(t, 1.13, 1.6)); }
    if (t > 1.6) { const k = seg(t, 1.6, 2.05, Ease.outCubic); ay = 3.1 * k; af = lerp(d0 - 1.35, d0 + 0.6, k); aw = lerp(60, 150, seg(t, 1.6, 2.2)); }
    if (t > 2.05) ay = 3.1 + 0.08 * Math.sin((t - 2.05) * 6);
    if (t > 2.35) aw = lerp(150, -55, seg(t, 2.35, 2.58, Ease.inQuad));
    if (t > 2.4) { const k = seg(t, 2.4, 2.6, Ease.inQuad); ay = lerp(3.1, 0, k); af = d0 + 0.6 + 0.3 * k; al = 20 * k; }
    if (t > 2.6) { al = lerp(20, 8, seg(t, 2.6, 3.2)); aw = -55; }
    an.x = X(af, ax0); an.y = ay; an.weaponDeg = aw; an.lean = al;
    // target (f from the anchor's start): struck (1.16), knocked back, launched (1.36-2.05), hang, slammed (2.4-2.6)
    let tf = d0 + 0.5 * seg(t, 1.16, 1.3, Ease.outCubic), ty = 0, tt = 25 * seg(t, 1.16, 1.3, Ease.outCubic);
    if (t > 1.36) { const k = clamp((t - 1.36) / 0.69); ty = 3.4 * (1 - (1 - k) * (1 - k)); tf = d0 + 0.5 + 0.7 * k; tt = lerp(25, 75, k); }
    if (t > 2.05) ty = 3.4 - 0.15 * seg(t, 2.05, 2.4);
    if (t > 2.4) { const k = seg(t, 2.4, 2.6, Ease.inQuad); ty = lerp(3.25, 0.02, k); tt = lerp(75, 90, k); }
    tg.x = X(tf, ax0); tg.y = ty; tg.tilt = -tt; tg.weaponDeg = -60;
    ev(1.16, () => onImpact(0.12, true));
    ev(2.6, () => onImpact(0.1, false));
  };
}

/** The 4-second sample ultimate: 5 shots, event-driven cut on the first impact, a blend, slow-motion, letterbox. */
function ultShots() {
  return [
    shots.heroPushIn({ dur: 0.7, roll: 6, letterbox: true }),
    shots.weaponFollow({ dur: 0.45, hold: true }),
    shots.impactPunchIn({ dur: 0.3 }),
    shots.groundSkim({
      dur: 0.9, cut: 0.22, slowmo: { scale: 0.35, dur: 0.45, easeIn: 0.06, easeOut: 0.2 }, follow: 'look', followY: true,
      from: [-1.5, 0.28, 3.6], fromSpace: 'mid', to: [0.2, 0.34, 3.2], toSpace: 'mid',
      look: [[0, 1.45, 0], [0.3, 1.4, 0]], lookSpace: 'mid', fov: [54, 48], roll: [-3, -7],
    }),
    shots.topDownSlam({ dur: 0.85, shake: { amount: 1.0, at: 0.25, freq: 13, decay: 1.4, dir: [0, 1, 0] }, kick: { fov: 6, roll: 4, at: 0.25, duration: 0.5 } }),
  ];
}

// ---- lab -----------------------------------------------------------------------------------------------------------
createLab({
  view: { target: [0, 1.2, 0], dist: 8, yaw: 0, pitch: 8 },
  setup(ctx, lab) {
    const { scene } = ctx;
    dressStage(scene);
    const p1 = makeDummy(scene, { accent: 0x8a3a18, visor: [6, 1.8, 0.35], metal: 0x6e6a66 });
    const p2 = makeDummy(scene, { accent: 0x2a5a8a, visor: [0.5, 2.2, 6], metal: 0x7a808c });
    const cam = createCameraDirector(ctx);
    cam.setTargets(p1.chest, p2.chest);
    lab.cam = cam; lab.p1 = p1; lab.p2 = p2;
    if (ctx.flags.hud) hudMock();
    const scope = ctx.flags.scope ? makeScope(cam) : null;

    // debug overview: a proxy of the director's camera + its path, seen from a free orbit view
    const proxy = new THREE.PerspectiveCamera(40, 16 / 9, 0.3, 2.2);
    const helper = new THREE.CameraHelper(proxy);
    helper.visible = false;
    const trailN = 900, trailPos = new Float32Array(trailN * 3);
    const trailGeo = new THREE.BufferGeometry();
    trailGeo.setAttribute('position', new THREE.BufferAttribute(trailPos, 3));
    trailGeo.setDrawRange(0, 0);
    const trail = new THREE.Line(trailGeo, new THREE.LineBasicMaterial({ color: new THREE.Color(3, 2.2, 0.6) }));
    trail.frustumCulled = false;
    trail.visible = false;
    scene.add(helper, trail);
    let trailCount = 0;
    /** Show / hide the director-camera proxy and restart its path. */
    lab.debugView = (on) => { helper.visible = trail.visible = on; trailCount = 0; trailGeo.setDrawRange(0, 0); };

    const S = { t: 0, motion: null, fired: new Set() };
    /** Run fn once when the scenario clock passes `at`. */
    const ev = (at, fn) => { if (S.t >= at && !S.fired.has(at)) { S.fired.add(at); fn(); } };
    ctx.onUpdate((dg) => {
      S.t += dg;
      if (S.motion) S.motion(S.t, ev);
      p1.apply(); p2.apply();
    }, ctx.ORDER.GAME);
    ctx.onUpdate(() => {
      if (helper.visible) {
        proxy.position.copy(cam.state.pos); proxy.quaternion.copy(cam.state.quat); proxy.fov = cam.state.fov; proxy.aspect = ctx.camera.aspect;
        proxy.updateProjectionMatrix(); proxy.updateMatrixWorld(); helper.update();
        if (trailCount < trailN) { cam.state.pos.toArray(trailPos, trailCount * 3); trailCount++; trailGeo.setDrawRange(0, trailCount); trailGeo.attributes.position.needsUpdate = true; }
      }
      if (scope) scope();
    }, ctx.ORDER.UI);

    lab.S = S;
    /** Put both dummies somewhere, stop everything, snap the framing. */
    lab.reset = (x1 = -2.5, x2 = 2.5, motion = null) => {
      cam.stop(0);
      cam.clearFx();
      cam.setMode('fight', 0);
      cam.letterbox(0, 0);
      lab.debugView(false);
      S.t = 0; S.fired.clear(); S.motion = motion;
      for (const [d, x, f] of [[p1, x1, x1 <= x2 ? 1 : -1], [p2, x2, x1 <= x2 ? -1 : 1]]) { d.x = x; d.y = 0; d.facing = f; d.weaponDeg = 35; d.tilt = 0; d.lean = 0; }
      if (motion) motion(0, () => {});
      p1.apply(); p2.apply();
      cam.snap();
    };
    lab.reset();
  },
  scenarios: buildScenarios(),
});

function buildScenarios() {
  const idle = (lab) => (t) => {
    lab.p1.lean = 3 * Math.sin(t * 2.1); lab.p2.lean = 3 * Math.sin(t * 2.1 + 1.3);
  };
  const place = (x1, x2) => (ctx, lab) => lab.reset(x1, x2, idle(lab));
  const sc = {
    clinch: place(-0.35, 0.35),
    near: place(-0.6, 0.6),
    mid: place(-2.5, 2.5),
    far: place(-5, 5),
    veryFar: place(-8.4, 8.4),
    edgeL: place(-8.6, -5.6),
    edgeR: place(5.6, 8.6),
    offCentre: place(1.5, 6.5),

    /** Fighters approach from far, clinch, then back off while drifting across the arena. */
    walk(ctx, lab) {
      lab.reset(-6, 6, (t) => {
        const k1 = seg(t, 0, 3), k2 = seg(t, 3.6, 6.5);
        const half = lerp(lerp(6, 0.45, k1), 3.5, k2);
        const midX = lerp(0, -1.5, k1) + lerp(0, 4.5, k2);
        lab.p1.x = midX - half; lab.p2.x = midX + half;
        lab.p1.lean = 6 * Math.sin(t * 5); lab.p2.lean = 6 * Math.sin(t * 5 + 2);
      });
    },
    /** P1 walks both into the left corner, then they fight back out. */
    corner(ctx, lab) {
      lab.reset(-3.5, -0.5, (t) => {
        const k = seg(t, 0, 2.5) - seg(t, 3.2, 5);
        lab.p1.x = lerp(-3.5, -8.7, k); lab.p2.x = lerp(-0.5, -6.6, k);
      });
    },
    /** Cross-up: P1 jumps over P2 and lands behind; facings swap mid-air. */
    swap(ctx, lab) {
      lab.reset(-1.6, 1.0, (t) => {
        const k = seg(t, 0.3, 1.2, Ease.linear);
        lab.p1.x = lerp(-1.6, 2.4, Ease.inOutSine(k));
        lab.p1.y = 2.0 * Math.sin(Math.PI * k);
        const swapped = lab.p1.x > lab.p2.x;
        lab.p1.facing = swapped ? -1 : 1; lab.p2.facing = swapped ? 1 : -1;
        lab.p2.x = 1.0 - 0.6 * seg(t, 1.25, 1.6);
      });
    },
    /** P2 launched high, P1 jumps after, both come down. */
    launch(ctx, lab) {
      lab.reset(-1.8, 0.4, (t) => {
        const k = clamp((t - 0.2) / 1.6);
        lab.p2.y = 4.0 * Math.sin(Math.PI * k);
        lab.p2.x = 0.4 + 1.2 * k;
        lab.p2.tilt = -60 * Math.sin(Math.PI * k);
        const j = clamp((t - 0.6) / 1.1);
        lab.p1.y = 2.8 * Math.sin(Math.PI * j);
        lab.p1.x = -1.8 + 1.6 * j;
      });
    },
    /** P1 blinks 9 m in 0.15 s past P2 (worst case for the lag: the hard pass must keep both in frame). */
    dash(ctx, lab) {
      lab.reset(-5, 2, (t) => {
        lab.p1.x = lerp(-5, 6, seg(t, 0.3, 0.45, Ease.linear));
        const sw = lab.p1.x > lab.p2.x;
        lab.p1.facing = sw ? -1 : 1; lab.p2.facing = sw ? 1 : -1;
      });
    },

    shakeLight(ctx, lab) { lab.reset(); ctx.cam.shake(0.15); },
    shakeHeavy(ctx, lab) { lab.reset(); ctx.cam.shake(0.35); },
    shakeSkill(ctx, lab) { lab.reset(); ctx.cam.shake(0.5); },
    shakeUlt(ctx, lab) { lab.reset(); ctx.cam.shake(1.0, { freq: 12, decay: 1.1 }); },
    shakeDir(ctx, lab) { lab.reset(); ctx.cam.shake(0.8, { dir: [0, 1, 0], freq: 11 }); },
    /** Three overlapping shakes during hit-stop and slow-motion (shake runs on real time). */
    shakeStack(ctx, lab) {
      lab.reset(-2.5, 2.5, idle(lab));
      ctx.cam.shake(0.35);
      ctx.time.hitstop(0.25);
      ctx.time.slowmo(0.3, 1.2);
      setTimeoutGame(lab, 0.15, () => ctx.cam.shake(0.5, { freq: 20 }));
      setTimeoutGame(lab, 0.4, () => ctx.cam.shake(0.3, { dir: [1, 0, 0], freq: 8, duration: 0.8 }));
    },
    kickFov(ctx, lab) { lab.reset(); ctx.cam.kick({ fov: -5, duration: 0.4 }); },
    kickPush(ctx, lab) { lab.reset(); ctx.cam.kick({ push: 1.2, duration: 0.45 }); },
    kickRoll(ctx, lab) { lab.reset(); ctx.cam.kick({ roll: 5, duration: 0.5 }); },
    zoom(ctx, lab) { lab.reset(-1.6, 1.6, idle(lab)); ctx.cam.zoom(0.72, 1.0, { focus: 0 }); },
    letterbox(ctx, lab) { lab.reset(-2.5, 2.5, idle(lab)); ctx.cam.letterbox(true, 0.4); },

    ult(ctx, lab) { playUlt(ctx, lab, false); },
    ultM(ctx, lab) { playUlt(ctx, lab, true); },
    /** A top-down slam stopped half-way, blending back to the fight framing from a vertical view. */
    blendBack(ctx, lab) {
      lab.reset(-2.5, 2.5, idle(lab));
      const h = ctx.cam.play([shots.topDownSlam({ dur: 2 })], { anchor: 0, blendOut: false });
      setTimeoutGame(lab, 0.5, () => h.stop(0.8));
    },
    /** Free orbit view from above showing the director's camera (frustum + path) while the ultimate plays. */
    overview(ctx, lab, mirror = false) {
      playUlt(ctx, lab, mirror);
      ctx.cam.setMode('free');
      lab.view({ target: [1, 0, 3], dist: 140, yaw: 0, pitch: 89.9, fov: 6 }); // near-orthographic plan view
      lab.debugView(true);
    },
  };
  for (const name of Object.keys(shots.SHOTS)) {
    sc['shot_' + name] = (ctx, lab) => playShot(ctx, lab, name, false);
    sc['shotM_' + name] = (ctx, lab) => playShot(ctx, lab, name, true);
  }
  return sc;
}

/** Run fn once game time passes `at` (scenario-relative). */
function setTimeoutGame(lab, at, fn) {
  const prev = lab.S.motion;
  lab.S.motion = (t, ev) => { if (prev) prev(t, ev); ev(at, fn); };
}

function playUlt(ctx, lab, mirror) {
  const [an, tg] = mirror ? [lab.p2, lab.p1] : [lab.p1, lab.p2];
  const facing = mirror ? -1 : 1;
  lab.reset(-2.5, 2.5, null);
  let h = null;
  lab.S.motion = ultMotion(an, tg, facing, an.x, tg.x, (hitstop, cut) => { if (cut) h.next(); ctx.time.hitstop(hitstop); });
  h = ctx.cam.play(ultShots(), { anchor: mirror ? 1 : 0, blendOut: 0.7 });
}

/** One vocabulary shot on the dummies (held on its last frame). Moving shots get a matching motion. */
function playShot(ctx, lab, name, mirror) {
  const [an, tg] = mirror ? [lab.p2, lab.p1] : [lab.p1, lab.p2];
  const f = mirror ? -1 : 1;
  lab.reset(-2.5, 2.5, null);
  lab.S.motion = (t) => {
    an.lean = 3 * Math.sin(t * 2.1); tg.lean = 3 * Math.sin(t * 2.1 + 1.3);
    if (name === 'weaponFollow') { an.x = -2.5 * f + 3.6 * f * seg(t, 0.0, 0.6, Ease.outCubic); an.weaponDeg = lerp(120, -30, seg(t, 0.35, 0.55)); }
    if (name === 'heroPushIn' || name === 'faceCloseUp') an.weaponDeg = lerp(35, 125, seg(t, 0, 1));
    if (name === 'topDownSlam') { tg.tilt = -90 * seg(t, 0, 0.2); tg.y = 0.0; }
    if (name === 'impactPunchIn') { tg.tilt = -28 * seg(t, 0, 0.12, Ease.outCubic); tg.x = 2.5 * f + 0.4 * f * seg(t, 0, 0.2, Ease.outCubic); }
  };
  ctx.cam.play([shots.SHOTS[name]()], { anchor: mirror ? 1 : 0, blendOut: false });
}

