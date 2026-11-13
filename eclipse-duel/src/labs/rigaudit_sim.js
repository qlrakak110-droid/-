// Rig audit lab, lens SIM: cloth, spring bones, robustness and performance (auditor's sandbox, READ-ONLY on src/char).
// The runtime is measured as shipped. The prototype hooks below only observe (capture the Cloth / SpringChain
// instances of a character, count cloth resets) or replace a solver with a no-op for differential CPU timing; they are
// always restored before any measured simulation. experiment() runs a lab-only COPY of Cloth.update with candidate fixes.
//
//   node tools/shot.mjs rigaudit_sim --eval "__ED.sim.run('spin')"        one stress scenario -> metrics summary
//        run(name, { clip: 'audit.spin' })  the spin family on combo3 with the swing-foot circle pulled in (no pelvis pops)
//        run(name, { series: ['t', 'cape.rpen', 'hipsStep'] })  per-frame values;  __ED.sim.list() names every scenario
//   node tools/shot.mjs rigaudit_sim --eval "__ED.sim.all({ clip: 'audit.spin' })"   every scenario (compact table)
//   node tools/shot.mjs rigaudit_sim --eval "__ED.sim.dtCompare()"        same move at 30 / 60 / 120 Hz, 0.1x slow motion,
//                                                                         slow motion entered mid-swing, hit-stop, dt spike
//   node tools/shot.mjs rigaudit_sim --eval "__ED.sim.decay()"            free swing after a root jolt at 30 / 60 / 120 Hz / 0.1x
//   node tools/shot.mjs rigaudit_sim --eval "__ED.sim.robust()"           API abuse: play spam / 4-state eviction, unknown names,
//                                                                         NaN / huge dt, impulse accumulation, teleport cost
//   node tools/shot.mjs rigaudit_sim --eval "__ED.sim.memory(20)"         create + dispose 20 characters: renderer.info deltas
//   node tools/shot.mjs rigaudit_sim --eval "__ED.sim.cpu({ n: 3000 })"   ms per char.update (+ --hash q=low for the low tier)
//   node tools/shot.mjs rigaudit_sim --eval "__ED.sim.parts()"            cost of the pieces around update (matrices, skeleton,
//                                                                         teleport settle, clip compile, character creation)
//   node tools/shot.mjs rigaudit_sim --eval "__ED.sim.draw()"             draw calls / triangles / shadow pass per character
//   node tools/shot.mjs rigaudit_sim --eval "__ED.sim.experiment()"       candidate cloth fixes (capsule lerp, collision in the
//                                                                         iterations, 1/240 s substeps, time-based damping)
//   captures:  --do "__ED.sim.stage('spin', { view: '34', clip: 'audit.spin' })" --at ... --sheet-only --out shots/char/rig/sim_x
//              views: fight | 34 | back34 | side | top | close | closeBack | { dist, yaw, pitch, ty }
//   allocations: node tools/shot.mjs rigaudit_sim --scenario <cdp script> calling __ED.sim.allocPrep() / allocRun(n) around
//              HeapProfiler sampling or Runtime.getHeapUsage (CDP session from page.context().newCDPSession(page))
//
// Per-frame cloth metrics (model = the character's root frame, where cloth and springs are simulated):
//   pen / depth     free cloth particles inside a body capsule (radius r, no margin, 2 mm tolerance), max depth (m)
//   legs / torso / arms   the same count split by the capsule that holds the particle
//   rpen / rdepth   rendered cloth vertices (skinned exactly like the GPU, rows next to the pins excluded) inside a capsule
//   edges           structural cloth edges (both ends free) whose segment passes through a capsule core (a limb poking
//                   through the sheet between particles)
//   floor / floorMin  particles below the world floor y = 0 / lowest rendered cloth vertex (world y, m)
//   stretch         max structural edge length / rest length;  vmax: max particle speed in the model frame (m/s)
//   ke              kinetic energy of the free particles (unit mass, model frame);  jit: max |p(t) - 2p(t-1) + p(t-2)| (mm)
//   plume / tasset  max depth of spring-bone tips inside body capsules (plume: torso / shoulders / arms; tassets: thighs)
//   nan             any non-finite bone transform, cloth particle or spring tip;  snaps: cloth resets (failsafe / teleport)

import * as THREE from 'three';
import { createLab, ORDER } from '../core/lab.js';
import { createCharacter, listClips, definePose, defineClip, invalidateClips } from '../char/index.js';
import { Cloth } from '../char/cloth.js';
import { SpringChain } from '../char/spring.js';
import { pushOutCapsules } from '../char/collide.js';
import { getClip, getClipDef } from '../char/anim.js';
import { knight } from '../char/designs/knight.js';
import '../char/clips/demo.js';

// ---- observation hooks (restored after use) -------------------------------------------------------------------------
const ORIG = { cloth: Cloth.prototype.update, write: Cloth.prototype.write, snap: Cloth.prototype._snap, spring: SpringChain.prototype.update };
const HOOK = { cloths: [], springs: [], snaps: 0 };
Cloth.prototype._snap = function (mq, mp) { HOOK.snaps++; return ORIG.snap.call(this, mq, mp); };
function hookCapture(on) {
  Cloth.prototype.update = on ? function (dt, mq, mp, g, w, caps, fy, time, settling) {
    if (!settling && !HOOK.cloths.includes(this)) HOOK.cloths.push(this);
    return ORIG.cloth.call(this, dt, mq, mp, g, w, caps, fy, time, settling);
  } : ORIG.cloth;
  SpringChain.prototype.update = on ? function (dt, lq, lp, mq, mp, g, caps) {
    if (!HOOK.springs.includes(this)) HOOK.springs.push(this);
    return ORIG.spring.call(this, dt, lq, lp, mq, mp, g, caps);
  } : ORIG.spring;
}
/** Replace a solver by a no-op (differential timing): 'cloth' (sim + write), 'spring', or null (restore). */
function hookNoop(which) {
  const noop = function () {};
  Cloth.prototype.update = which === 'cloth' ? noop : ORIG.cloth;
  Cloth.prototype.write = which === 'cloth' ? noop : ORIG.write;
  SpringChain.prototype.update = which === 'spring' ? noop : ORIG.spring;
}

// ---- studio environment (same look as the char lab) --------------------------------------------------------------
function studioEnv(renderer) {
  const scene = new THREE.Scene();
  const dome = new THREE.Mesh(new THREE.SphereGeometry(20, 32, 16), new THREE.ShaderMaterial({
    side: THREE.BackSide, depthWrite: false,
    vertexShader: 'varying vec3 vP; void main(){ vP = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }',
    fragmentShader: `varying vec3 vP; void main(){
      float y = vP.y;
      vec3 top = vec3(0.05, 0.065, 0.09), hor = vec3(0.16, 0.12, 0.1), flo = vec3(0.012, 0.011, 0.012);
      vec3 c = y > 0.0 ? mix(hor, top, pow(max(y, 0.0), 0.6)) : mix(hor * 0.4, flo, pow(max(-y, 0.0), 0.4));
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

// ---- geometry helpers ------------------------------------------------------------------------------------------------
const TOL = 0.002;
const clamp01 = (x) => (x < 0 ? 0 : x > 1 ? 1 : x);
/** Squared distance from point p to segment ab. */
function segPoint2(px, py, pz, ax, ay, az, bx, by, bz) {
  const ex = bx - ax, ey = by - ay, ez = bz - az, ee = ex * ex + ey * ey + ez * ez;
  const t = ee > 1e-12 ? clamp01(((px - ax) * ex + (py - ay) * ey + (pz - az) * ez) / ee) : 0;
  const qx = px - ax - ex * t, qy = py - ay - ey * t, qz = pz - az - ez * t;
  return qx * qx + qy * qy + qz * qz;
}
/** Distance between segments p1q1 and p2q2 (Ericson, Real-Time Collision Detection 5.1.9). */
function segSeg(p1x, p1y, p1z, q1x, q1y, q1z, p2x, p2y, p2z, q2x, q2y, q2z) {
  const d1x = q1x - p1x, d1y = q1y - p1y, d1z = q1z - p1z, d2x = q2x - p2x, d2y = q2y - p2y, d2z = q2z - p2z;
  const rx = p1x - p2x, ry = p1y - p2y, rz = p1z - p2z;
  const a = d1x * d1x + d1y * d1y + d1z * d1z, e = d2x * d2x + d2y * d2y + d2z * d2z, f = d2x * rx + d2y * ry + d2z * rz;
  let s, t;
  if (a <= 1e-12 && e <= 1e-12) { s = 0; t = 0; } else if (a <= 1e-12) { s = 0; t = clamp01(f / e); } else {
    const c = d1x * rx + d1y * ry + d1z * rz;
    if (e <= 1e-12) { t = 0; s = clamp01(-c / a); } else {
      const b = d1x * d2x + d1y * d2y + d1z * d2z, den = a * e - b * b;
      s = den > 1e-12 ? clamp01((b * f - c * e) / den) : 0;
      t = (b * s + f) / e;
      if (t < 0) { t = 0; s = clamp01(-c / a); } else if (t > 1) { t = 1; s = clamp01((b - c) / a); }
    }
  }
  const x = p1x + d1x * s - (p2x + d2x * t), y = p1y + d1y * s - (p2y + d2y * t), z = p1z + d1z * s - (p2z + d2z * t);
  return Math.sqrt(x * x + y * y + z * z);
}
/** Deepest penetration (r - dist, > 0 = inside) of a point into a capsule set (stride 7: a, b, r). Returns [depth, index]. */
const penOut = [0, -1];
function capPen(caps, nc, x, y, z, mask) {
  let best = -1e9, which = -1;
  for (let i = 0; i < nc; i++) {
    if (mask && !mask[i]) continue;
    const o = i * 7;
    const d = caps[o + 6] - Math.sqrt(segPoint2(x, y, z, caps[o], caps[o + 1], caps[o + 2], caps[o + 3], caps[o + 4], caps[o + 5]));
    if (d > best) { best = d; which = i; }
  }
  penOut[0] = best; penOut[1] = which;
  return penOut;
}

// ---- character inspection -----------------------------------------------------------------------------------------
const _m = new THREE.Matrix4(), _inv = new THREE.Matrix4(), _v = new THREE.Vector3();

/** Find the Cloth / SpringChain instances of a character and precompute what the metrics need. */
function inspect(char) {
  HOOK.cloths.length = 0; HOOK.springs.length = 0;
  hookCapture(true);
  try { char.update(0, 0); } finally { hookCapture(false); }
  const defs = char.design.colliders || [];
  const cat = defs.map((d) => (/^(thigh|shin)/.test(d.name) ? 'legs' : /^(torso|pelvis)/.test(d.name) ? 'torso' : 'arms'));
  const info = {
    char, defs, cat, ncap: defs.length, caps: new Float32Array(defs.length * 7), wcaps: new Float32Array(defs.length * 7),
    cloths: [], springs: [],
  };
  const firstCloth = Math.min(...HOOK.cloths.filter((c) => c.rig === char.rig).map((c) => c.first), char.rig.count);
  info.firstCloth = firstCloth;
  info.boneM = new Float32Array((char.rig.count - firstCloth) * 16);
  for (const cl of HOOK.cloths.filter((c) => c.rig === char.rig)) {
    const C = cl.C, pinN = C * cl.layout.pinRows;
    const edges = [];
    for (let c = 0; c < cl.cons.length; c += 4) {
      const a = cl.cons[c], b = cl.cons[c + 1], d = Math.abs(b - a);
      if (d === 1 || d === C) edges.push(a, b, cl.cons[c + 2]);
    }
    // rendered vertices of this cloth in its slot mesh (all weights on this cloth's particle bones)
    const mesh = char.meshes[cl.layout.spec.slot || 'suit'];
    const g = mesh.geometry, si = g.attributes.skinIndex, sw = g.attributes.skinWeight, pos = g.attributes.position;
    const verts = [];
    for (let v = 0; v < pos.count; v++) {
      const b0 = si.getX(v);
      if (b0 < cl.first || b0 >= cl.first + cl.n) continue;
      let nearPin = false;
      const ids = [si.getX(v), si.getY(v), si.getZ(v), si.getW(v)], ws = [sw.getX(v), sw.getY(v), sw.getZ(v), sw.getW(v)];
      for (let k = 0; k < 4; k++) if (ws[k] > 1e-4 && ids[k] - cl.first < pinN + C) nearPin = true; // pinned row + first free row
      verts.push(v);
      verts.push(nearPin ? 1 : 0);
    }
    info.cloths.push({
      c: cl, name: cl.layout.spec.name, pinN, edges: Float32Array.from(edges), mesh, verts: Int32Array.from(verts),
      prev1: new Float32Array(cl.n * 3), prev2: new Float32Array(cl.n * 3), have: 0,
    });
  }
  for (const s of HOOK.springs.filter((x) => x.rig === char.rig)) {
    const name = char.rig.names[s.idx[0]];
    // plume: collide = false in the design; test against the back / shoulders / arms. tassets: against the thighs.
    const mask = new Uint8Array(defs.length);
    defs.forEach((d, i) => { mask[i] = /^tasset/.test(name) ? (/^thigh/.test(d.name) ? 1 : 0) : (/^(torso|shoulder|upperArm|foreArm)/.test(d.name) ? 1 : 0); });
    info.springs.push({ s, name, mask, prev1: new Float32Array(s.p.length), prev2: new Float32Array(s.p.length), have: 0 });
  }
  return info;
}

/** Body capsules of a character in its model frame (and the world frame). Bone matrices must be current. */
function updateCaps(info) {
  const c = info.char;
  _inv.copy(c.root.matrixWorld).invert();
  for (let i = 0; i < info.ncap; i++) {
    const d = info.defs[i], o = i * 7;
    for (let e = 0; e < 2; e++) {
      const [bn, off] = e === 0 ? d.a : d.b;
      _v.fromArray(off || [0, 0, 0]).applyMatrix4(c.bones[bn].matrixWorld);
      info.wcaps[o + e * 3] = _v.x; info.wcaps[o + e * 3 + 1] = _v.y; info.wcaps[o + e * 3 + 2] = _v.z;
      _v.applyMatrix4(_inv);
      info.caps[o + e * 3] = _v.x; info.caps[o + e * 3 + 1] = _v.y; info.caps[o + e * 3 + 2] = _v.z;
    }
    info.caps[o + 6] = info.wcaps[o + 6] = d.r;
  }
}

/** Skin one cloth's rendered vertices on the CPU exactly like the GPU (model frame) into out (Float32Array n*3). */
function skinCloth(info, C, out) {
  const ch = info.char, bones = ch.skeleton.bones, inv = ch.skeleton.boneInverses, f0 = info.firstCloth, M = info.boneM;
  for (let b = f0; b < bones.length; b++) {
    _m.multiplyMatrices(bones[b].matrix, inv[b]); // cloth bones are root children: local matrix = model matrix
    M.set(_m.elements, (b - f0) * 16);
  }
  const g = C.mesh.geometry, si = g.attributes.skinIndex, sw = g.attributes.skinWeight, P = g.attributes.position;
  for (let k = 0; k < C.verts.length; k += 2) {
    const v = C.verts[k], x = P.getX(v), y = P.getY(v), z = P.getZ(v);
    let ox = 0, oy = 0, oz = 0;
    for (let j = 0; j < 4; j++) {
      const w = j === 0 ? sw.getX(v) : j === 1 ? sw.getY(v) : j === 2 ? sw.getZ(v) : sw.getW(v);
      if (w <= 0) continue;
      const b = (j === 0 ? si.getX(v) : j === 1 ? si.getY(v) : j === 2 ? si.getZ(v) : si.getW(v)) - f0, e = b * 16;
      ox += w * (M[e] * x + M[e + 4] * y + M[e + 8] * z + M[e + 12]);
      oy += w * (M[e + 1] * x + M[e + 5] * y + M[e + 9] * z + M[e + 13]);
      oz += w * (M[e + 2] * x + M[e + 6] * y + M[e + 10] * z + M[e + 14]);
    }
    out[(k / 2) * 3] = ox; out[(k / 2) * 3 + 1] = oy; out[(k / 2) * 3 + 2] = oz;
  }
  return out;
}

function finiteChar(info) {
  for (const b of info.char.skeleton.bones) {
    const e = b.matrixWorld.elements;
    for (let i = 0; i < 16; i++) if (!Number.isFinite(e[i])) return false;
  }
  for (const C of info.cloths) for (let i = 0; i < C.c.p.length; i++) if (!Number.isFinite(C.c.p[i])) return false;
  for (const S of info.springs) for (let i = 0; i < S.s.p.length; i++) if (!Number.isFinite(S.s.p[i])) return false;
  return true;
}

const skinBuf = new Float32Array(30000);
/** Per-frame metrics of one character (see the header). dt = the dt of the update that just ran. */
function measure(info, dt) {
  updateCaps(info);
  const ch = info.char, e = ch.root.matrixWorld.elements, caps = info.caps, nc = info.ncap;
  const out = { nan: !finiteChar(info) };
  { // animation pop detector: hips displacement in the model frame this frame (mm)
    _v.setFromMatrixPosition(ch.bones.hips.matrixWorld).applyMatrix4(_inv);
    if (!info.prevHips) info.prevHips = new THREE.Vector3().copy(_v);
    out.hipsStep = _v.distanceTo(info.prevHips) * 1000;
    info.prevHips.copy(_v);
  }
  for (const C of info.cloths) {
    const cl = C.c, p = cl.p, n = cl.n;
    const r = { pen: 0, depth: 0, legs: 0, torso: 0, arms: 0, rpen: 0, rdepth: 0, edges: 0, floor: 0, floorMin: 1e9, stretch: 0, vmax: 0, ke: 0, jit: 0 };
    for (let k = C.pinN; k < n; k++) {
      const x = p[k * 3], y = p[k * 3 + 1], z = p[k * 3 + 2];
      const [d, which] = capPen(caps, nc, x, y, z);
      if (d > TOL) { r.pen++; r[info.cat[which]]++; if (d > r.depth) r.depth = d; }
      if (e[1] * x + e[5] * y + e[9] * z + e[13] < 0) r.floor++;
      if (C.have >= 1 && dt > 0) {
        const vx = x - C.prev1[k * 3], vy = y - C.prev1[k * 3 + 1], vz = z - C.prev1[k * 3 + 2];
        const v = Math.sqrt(vx * vx + vy * vy + vz * vz) / dt;
        if (v > r.vmax) r.vmax = v;
        r.ke += 0.5 * v * v;
      }
      if (C.have >= 2) {
        const jx = x - 2 * C.prev1[k * 3] + C.prev2[k * 3], jy = y - 2 * C.prev1[k * 3 + 1] + C.prev2[k * 3 + 1], jz = z - 2 * C.prev1[k * 3 + 2] + C.prev2[k * 3 + 2];
        const j = Math.sqrt(jx * jx + jy * jy + jz * jz) * 1000;
        if (j > r.jit) r.jit = j;
      }
    }
    for (let k = 0; k < C.edges.length; k += 3) {
      const a = C.edges[k] * 3, b = C.edges[k + 1] * 3;
      const dx = p[b] - p[a], dy = p[b + 1] - p[a + 1], dz = p[b + 2] - p[a + 2];
      const L = Math.sqrt(dx * dx + dy * dy + dz * dz) / C.edges[k + 2];
      if (L > r.stretch) r.stretch = L;
      if (C.edges[k] < C.pinN || C.edges[k + 1] < C.pinN) continue;
      for (let i = 0; i < nc; i++) {
        const o = i * 7;
        if (segSeg(p[a], p[a + 1], p[a + 2], p[b], p[b + 1], p[b + 2], caps[o], caps[o + 1], caps[o + 2], caps[o + 3], caps[o + 4], caps[o + 5]) < caps[o + 6] - TOL) { r.edges++; break; }
      }
    }
    const sk = skinCloth(info, C, skinBuf);
    for (let k = 0; k < C.verts.length; k += 2) {
      const x = sk[(k / 2) * 3], y = sk[(k / 2) * 3 + 1], z = sk[(k / 2) * 3 + 2];
      const wy = e[1] * x + e[5] * y + e[9] * z + e[13];
      if (wy < r.floorMin) r.floorMin = wy;
      if (C.verts[k + 1]) continue;
      const [d] = capPen(caps, nc, x, y, z);
      if (d > TOL) { r.rpen++; if (d > r.rdepth) r.rdepth = d; }
    }
    C.prev2.set(C.prev1); C.prev1.set(p); C.have = dt > 0 || C.have === 0 ? C.have + 1 : C.have;
    out[C.name] = r;
  }
  for (const S of info.springs) {
    const s = S.s, p = s.p, n = p.length / 3, key = /^plume/.test(S.name) ? 'plume' : 'tasset';
    const r = out[key] || (out[key] = { depth: 0, vmax: 0, jit: 0 });
    for (let k = 0; k < n; k++) {
      const x = p[k * 3], y = p[k * 3 + 1], z = p[k * 3 + 2];
      const [d] = capPen(caps, nc, x, y, z, S.mask);
      if (d > r.depth) r.depth = d;
      if (S.have >= 1 && dt > 0) {
        const vx = x - S.prev1[k * 3], vy = y - S.prev1[k * 3 + 1], vz = z - S.prev1[k * 3 + 2];
        const v = Math.sqrt(vx * vx + vy * vy + vz * vz) / dt;
        if (v > r.vmax) r.vmax = v;
      }
      if (S.have >= 2) {
        const jx = x - 2 * S.prev1[k * 3] + S.prev2[k * 3], jy = y - 2 * S.prev1[k * 3 + 1] + S.prev2[k * 3 + 1], jz = z - 2 * S.prev1[k * 3 + 2] + S.prev2[k * 3 + 2];
        const j = Math.sqrt(jx * jx + jy * jy + jz * jz) * 1000;
        if (j > r.jit) r.jit = j;
      }
    }
    S.prev2.set(S.prev1); S.prev1.set(p); S.have = dt > 0 || S.have === 0 ? S.have + 1 : S.have;
  }
  return out;
}

/** Cloth of `ia` (world) inside the body capsules of `ib` (world): particles and rendered vertices. */
function crossPen(ia, ib) {
  const e = ia.char.root.matrixWorld.elements, caps = ib.wcaps, nc = ib.ncap;
  const r = { pen: 0, depth: 0, rpen: 0 };
  for (const C of ia.cloths) {
    const p = C.c.p;
    for (let k = C.pinN; k < C.c.n; k++) {
      const x = p[k * 3], y = p[k * 3 + 1], z = p[k * 3 + 2];
      const wx = e[0] * x + e[4] * y + e[8] * z + e[12], wy = e[1] * x + e[5] * y + e[9] * z + e[13], wz = e[2] * x + e[6] * y + e[10] * z + e[14];
      const [d] = capPen(caps, nc, wx, wy, wz);
      if (d > TOL) { r.pen++; if (d > r.depth) r.depth = d; }
    }
  }
  return r;
}

// ---- scenarios ---------------------------------------------------------------------------------------------------------
let lab = null, ctx = null;
const CH = [];        // [info A, info B]
const FPS60 = 1 / 60;

function charA() { return CH[0]; }
function charB() {
  if (!CH[1]) {
    const b = createCharacter(ctx, knight, { name: 'p2' });
    b.play('demo.idle', { fade: 0 });
    CH[1] = inspect(b);
  }
  CH[1].char.setVisible(true);
  return CH[1];
}

/** Put a character on the line at x facing f, holding a pose / clip, cloth reset and settled for `frames` frames. */
function settle(info, clip, { x = 0, facing = 1, frames = 90 } = {}) {
  const c = info.char;
  c.root.position.set(x, 0, 0); c.root.rotation.set(0, 0, 0); c.setFacing(facing);
  c.breath.depth = 1; c.wind = [0, 0, 0];
  c.lookAt(null);
  c.teleport();
  c.play(clip, { fade: 0, restart: true });
  for (let i = 0; i < frames; i++) c.update(FPS60, FPS60);
  for (const C of info.cloths) C.have = 0;
  for (const S of info.springs) S.have = 0;
  info.prevHips = null;
}

const spinStart = (S) => settle(S.A, 'demo.c2end');
const playSpin = (S) => S.a.play(S.o.clip || 'demo.combo3', { fade: 0.06, restart: true });

/**
 * 'audit.spin' = demo.combo3 with the swinging right foot's circle pulled toward the pivot (factor k) so the automatic
 * pelvis drop never triggers: isolates cloth / spring behaviour from the shipped clip's 0.5 m pelvis pops.
 */
function cleanSpin(k = 0.4) {
  const def = structuredClone(getClipDef('demo.combo3'));
  const piv = [0.42, 0, -0.15];
  for (const key of def.keys) {
    const f = key.ik && key.ik.footR;
    if (!f || f.space !== 'origin' || key.t < 0.29 || key.t > 0.73) continue;
    f.pos = [piv[0] + (f.pos[0] - piv[0]) * k, f.pos[1], piv[2] + (f.pos[2] - piv[2]) * k];
  }
  defineClip('audit.spin', { ...def, name: undefined });
  invalidateClips();
  return 'audit.spin';
}
cleanSpin();
/** Scenario table: setup (unmeasured), T (game seconds measured), dt(S) for the next frame, events [[gameTime, fn]]. */
const SCEN = {
  rest: { T: 6, note: 'held stance pose, breathing off: pure solver jitter', setup(S) { settle(S.A, 'demo.stance'); S.a.breath.depth = 0; } },
  idle: { T: 5, note: 'demo.idle loop', setup(S) { settle(S.A, 'demo.idle'); } },
  walk: { T: 3.04, note: 'demo.walkF with root motion', setup(S) { settle(S.A, 'demo.stance'); }, events: [[0, (S) => S.a.play('demo.walkF', { fade: 0.15 })]] },
  hit: { T: 1.2, note: 'demo.hit + impulse 1.2', setup(S) { settle(S.A, 'demo.stance'); }, events: [[0, (S) => { S.a.play('demo.hit', { fade: 0.04, restart: true }); S.a.impulse({ dir: [-1, 0.1, 0.2], amount: 1.2 }); }]] },
  spin: { T: 1.6, note: 'demo.combo3 spinning sweep finisher', setup: spinStart, events: [[0, playSpin]] },
  slam: { T: 2.0, note: 'demo.slam overhead slam', setup(S) { settle(S.A, 'demo.stance'); }, events: [[0, (S) => S.a.play('demo.slam', { fade: 0.08, restart: true })]] },
  chain: { T: 5.2, note: 'combo1 > combo2 > combo3 > slam', setup(S) { settle(S.A, 'demo.stance'); S.queue = ['demo.combo2', 'demo.combo3', 'demo.slam']; }, events: [[0, (S) => S.a.play('demo.combo1', { fade: 0.08, restart: true })]] },
  flip: { T: 1.6, note: 'spin with instant facing flips at 0.30 / 0.55 / 0.90', setup: spinStart, events: [[0, playSpin], [0.3, (S) => S.a.setFacing(-S.a.facing)], [0.55, (S) => S.a.setFacing(-S.a.facing)], [0.9, (S) => S.a.setFacing(-S.a.facing)]] },
  flipTurn: { T: 1.6, note: 'spin with timed facing flips (turn 0.15 s) at 0.30 / 0.80', setup: spinStart, events: [[0, playSpin], [0.3, (S) => S.a.setFacing(-S.a.facing, { turn: 0.15 })], [0.8, (S) => S.a.setFacing(-S.a.facing, { turn: 0.15 })]] },
  teleport: { T: 1.6, note: 'spin, root moved +3 m at 0.45 (automatic detection, no teleport() call)', setup: spinStart, events: [[0, playSpin], [0.45, (S) => { S.a.root.position.x += 3 * S.a.facing; }]] },
  teleportReset: { T: 1.6, note: 'spin, root moved +3 m and teleport() called at 0.45 (torso turned ~150 deg)', setup: spinStart, events: [[0, playSpin], [0.45, (S) => { S.a.root.position.x += 3 * S.a.facing; S.a.teleport(); }]] },
  spike: { T: 1.6, note: 'spin with dt = 1/15 frames at 0.36 and 0.60', setup: spinStart, events: [[0, playSpin]],
    dt(S) { if (!S.k1 && S.gt >= 0.36) { S.k1 = 1; return 1 / 15; } if (!S.k2 && S.gt >= 0.6) { S.k2 = 1; return 1 / 15; } return FPS60; } },
  hitstop: { T: 1.6, note: 'spin, dt = 0 for 2 s (120 frames) at 0.36, then resume', setup: spinStart, events: [[0, playSpin]],
    dt(S) { if (S.gt >= 0.36 && (S.hold || 0) < 120) { S.hold = (S.hold || 0) + 1; return 0; } return FPS60; } },
  slowmo: { T: 1.6, note: 'spin, 0.1x slow motion (dt 1/600) for 3 s real between game 0.30 and 0.60', setup: spinStart, events: [[0, playSpin]],
    dt(S) { return S.gt >= 0.3 - 1e-9 && S.gt < 0.6 - 1e-9 ? 1 / 600 : FPS60; } },
  slowmoSlam: { T: 2.0, note: 'slam, 0.1x slow motion between game 0.55 and 0.85 (impact at 0.63)', setup(S) { settle(S.A, 'demo.stance'); }, events: [[0, (S) => S.a.play('demo.slam', { fade: 0.08, restart: true })]],
    dt(S) { return S.gt >= 0.55 - 1e-9 && S.gt < 0.85 - 1e-9 ? 1 / 600 : FPS60; } },
  hz120: { T: 1.6, note: 'spin stepped at 120 Hz', setup: spinStart, events: [[0, playSpin]], dt: () => 1 / 120 },
  hz30: { T: 1.6, note: 'spin stepped at 30 Hz', setup: spinStart, events: [[0, playSpin]], dt: () => 1 / 30 },
  crossup: { T: 2.0, two: true, note: 'B walks through A (cross-up): cloth vs the other body', setup(S) { settle(S.A, 'demo.idle'); settle(S.B, 'demo.walkF', { x: -1.1 }); S.noRoot = new Set([S.b]); },
    each(S) { S.b.root.position.x = -1.1 + 2.2 * Math.min(1, S.gt / 2.0); } },
  spinNear: { T: 1.6, two: true, note: 'A spins with B standing 0.9 m in front', setup(S) { spinStart(S); settle(S.B, 'demo.guard', { x: 0.9, facing: -1 }); S.noRoot = new Set([S.b]); }, events: [[0, playSpin]] },
};

function start(name, o = {}) {
  const sc = SCEN[name];
  if (!sc) throw new Error('no scenario ' + name + ' (have: ' + Object.keys(SCEN).join(' ') + ')');
  hookNoop(null);
  const S = { name, sc, A: charA(), a: charA().char, gt: 0, f: 0, fired: new Set(), rec: [], queue: null, noRoot: new Set(), o };
  if (sc.two) { S.B = charB(); S.b = S.B.char; } else if (CH[1]) CH[1].char.setVisible(false);
  sc.setup(S);
  S.snaps0 = HOOK.snaps;
  S.x0 = S.a.root.position.x;
  return S;
}

function step(S) {
  const sc = S.sc;
  (sc.events || []).forEach(([t, fn], i) => { if (!S.fired.has(i) && S.gt >= t - 1e-9) { S.fired.add(i); fn(S); } });
  if (sc.each) sc.each(S);
  const dt = typeof sc.dt === 'function' ? sc.dt(S) : FPS60;
  const list = S.B ? [S.A, S.B] : [S.A];
  for (const I of list) {
    const c = I.char;
    c.update(dt, FPS60);
    if (!S.noRoot.has(c)) c.root.position.x += c.rootDelta.f * c.facing;
  }
  if (S.queue && S.queue.length && S.a.finished) S.a.play(S.queue.shift(), { fade: 0.06, restart: true });
  S.gt += dt; S.f++;
  const m = measure(S.A, dt);
  if (S.B) { measure(S.B, dt); m.cross = { AinB: crossPen(S.A, S.B), BinA: crossPen(S.B, S.A) }; }
  m.t = +S.gt.toFixed(4); m.dt = dt; m.snaps = HOOK.snaps - S.snaps0;
  S.rec.push(m);
  return m;
}

const done = (S) => S.gt >= S.sc.T - 1e-9 || S.f >= 4000;

/** Max (or min for floorMin) of a metric path over records; with the time of the extreme and the count of frames > 0. */
function agg(rec, path, mode = 'max') {
  let best = mode === 'max' ? -Infinity : Infinity, at = null, n = 0;
  for (const m of rec) {
    let v = m;
    for (const k of path.split('.')) v = v == null ? undefined : v[k];
    if (v === undefined) continue;
    if (typeof v === 'boolean') v = v ? 1 : 0;
    if (mode === 'max' ? v > best : v < best) { best = v; at = m.t; }
    if (v > 0) n++;
  }
  return { v: Number.isFinite(best) ? +best.toFixed(4) : null, at, frames: n };
}

function summary(S) {
  const r = S.rec, out = { scenario: S.name, clip: S.o.clip || null, note: S.sc.note, frames: r.length, gameT: +S.gt.toFixed(3), snaps: r.length ? r[r.length - 1].snaps : 0, nanFrames: agg(r, 'nan').frames, hipsStepMM: agg(r, 'hipsStep') };
  for (const cl of ['cape', 'tabard']) {
    if (!r[0] || !r[0][cl]) continue;
    out[cl] = {};
    for (const k of ['pen', 'depth', 'legs', 'torso', 'arms', 'rpen', 'rdepth', 'edges', 'floor', 'stretch', 'vmax', 'ke', 'jit']) out[cl][k] = agg(r, cl + '.' + k);
    out[cl].floorMin = agg(r, cl + '.floorMin', 'min');
  }
  for (const k of ['plume', 'tasset']) if (r[0] && r[0][k]) out[k] = { depth: agg(r, k + '.depth'), vmax: agg(r, k + '.vmax'), jit: agg(r, k + '.jit') };
  if (r[0] && r[0].cross) out.cross = { AinB: agg(r, 'cross.AinB.pen'), AinBdepth: agg(r, 'cross.AinB.depth'), BinA: agg(r, 'cross.BinA.pen'), BinAdepth: agg(r, 'cross.BinA.depth') };
  return out;
}

/** Run a scenario synchronously. opts.series: list of metric paths to return per frame (e.g. ['cape.pen','t']). */
function run(name, opts = {}) {
  const S = start(name, opts);
  while (!done(S)) step(S);
  const out = summary(S);
  if (name === 'rest') { // solver noise once settled: last 2 s
    const tail = S.rec.filter((m) => m.t >= S.sc.T - 2);
    out.restTail = {};
    for (const k of ['cape', 'tabard']) out.restTail[k] = { jitMM: agg(tail, k + '.jit').v, moveMMperFrame: +(agg(tail, k + '.vmax').v * 1000 / 60).toFixed(4), pen: agg(tail, k + '.pen').v };
    for (const k of ['plume', 'tasset']) out.restTail[k] = { jitMM: agg(tail, k + '.jit').v, moveMMperFrame: +(agg(tail, k + '.vmax').v * 1000 / 60).toFixed(4) };
  }
  if (opts.series) out.series = S.rec.map((m) => opts.series.map((p) => { let v = m; for (const k of p.split('.')) v = v == null ? undefined : v[k]; return typeof v === 'number' ? +v.toFixed(4) : v; }));
  return out;
}

function all(opts = {}) {
  const rows = {};
  for (const n of Object.keys(SCEN)) {
    const s = run(n, opts);
    const row = { frames: s.frames, snaps: s.snaps, nan: s.nanFrames, hipsStepMM: s.hipsStepMM.v + '@' + s.hipsStepMM.at };
    for (const cl of ['cape', 'tabard']) if (s[cl]) {
      const c = s[cl];
      row[cl] = `pen ${c.pen.v}@${c.pen.at} (${c.pen.frames}f) legs ${c.legs.v} torso ${c.torso.v} arms ${c.arms.v} d ${c.depth.v} | rpen ${c.rpen.v} d ${c.rdepth.v} | edges ${c.edges.v} (${c.edges.frames}f) | floor ${c.floor.v} min ${c.floorMin.v} | str ${c.stretch.v}@${c.stretch.at} | v ${c.vmax.v} ke ${c.ke.v} jit ${c.jit.v}`;
    }
    for (const k of ['plume', 'tasset']) if (s[k]) row[k] = `depth ${s[k].depth.v}@${s[k].depth.at} (${s[k].depth.frames}f) v ${s[k].vmax.v} jit ${s[k].jit.v}`;
    if (s.cross) row.cross = s.cross;
    rows[n] = row;
  }
  return rows;
}

// ---- dt independence ---------------------------------------------------------------------------------------------------
/** Snapshot (model frame) of the cape / tabard particles, plume and tasset tips and the weapon tip. */
function snapshot(info) {
  const parts = {};
  for (const C of info.cloths) parts[C.name] = Float32Array.from(C.c.p);
  for (const S of info.springs) {
    const k = /^plume/.test(S.name) ? 'plume' : 'tasset';
    parts[k] = parts[k] ? Float32Array.from([...parts[k], ...S.s.p]) : Float32Array.from(S.s.p);
  }
  const c = info.char;
  c.sockets.weaponTip.getWorldPosition(_v);
  _inv.copy(c.root.matrixWorld).invert();
  _v.applyMatrix4(_inv);
  parts.weaponTip = Float32Array.from([_v.x, _v.y, _v.z]);
  return parts;
}

/**
 * Runs a scenario with snapshots every `every` game seconds (exact frame multiples). Returns [{t, parts}].
 */
function trace(name, every = 1 / 30, o = {}) {
  const S = start(name, o);
  const snaps = [{ t: 0, parts: snapshot(S.A) }];
  let next = every;
  while (!done(S)) {
    step(S);
    if (S.gt >= next - 1e-7) { snaps.push({ t: +S.gt.toFixed(4), parts: snapshot(S.A), slow: S.rec[S.rec.length - 1].dt < 1 / 100 }); next += every; }
  }
  return snaps;
}

function diff(ref, tst, { from = 0, to = 99 } = {}) {
  const out = {};
  const n = Math.min(ref.length, tst.length);
  for (const key of Object.keys(ref[0].parts)) {
    let mx = 0, sum = 0, cnt = 0, at = null, hem = 0;
    for (let i = 0; i < n; i++) {
      if (ref[i].t < from - 1e-6 || ref[i].t > to + 1e-6) continue;
      const a = ref[i].parts[key], b = tst[i].parts[key];
      for (let k = 0; k < a.length; k += 3) {
        const d = Math.hypot(a[k] - b[k], a[k + 1] - b[k + 1], a[k + 2] - b[k + 2]);
        if (d > mx) { mx = d; at = ref[i].t; }
        sum += d * d; cnt++;
      }
      if (key === 'cape') { // bottom row (hem) mean deviation
        const C = CH[0].cloths.find((c) => c.name === 'cape').c, j0 = (C.R - 1) * C.C;
        for (let k = j0; k < C.n; k++) hem = Math.max(hem, Math.hypot(a[k * 3] - b[k * 3], a[k * 3 + 1] - b[k * 3 + 1], a[k * 3 + 2] - b[k * 3 + 2]));
      }
    }
    out[key] = { max: +mx.toFixed(4), rms: +Math.sqrt(sum / Math.max(1, cnt)).toFixed(4), at, ...(key === 'cape' ? { hemMax: +hem.toFixed(4) } : {}) };
  }
  return out;
}

/** Speed (game-time units, m/s) of the cape hem / plume tip between consecutive snapshots in a window. */
function speeds(tr, from, to) {
  const C = CH[0].cloths.find((c) => c.name === 'cape').c, j0 = (C.R - 1) * C.C;
  let hem = 0, plume = 0;
  for (let i = 1; i < tr.length; i++) {
    if (tr[i].t < from || tr[i].t > to) continue;
    const dt = tr[i].t - tr[i - 1].t, a = tr[i - 1].parts, b = tr[i].parts;
    for (let k = j0; k < C.n; k++) hem = Math.max(hem, Math.hypot(a.cape[k * 3] - b.cape[k * 3], a.cape[k * 3 + 1] - b.cape[k * 3 + 1], a.cape[k * 3 + 2] - b.cape[k * 3 + 2]) / dt);
    const pl = a.plume.length - 3;
    plume = Math.max(plume, Math.hypot(a.plume[pl] - b.plume[pl], a.plume[pl + 1] - b.plume[pl + 1], a.plume[pl + 2] - b.plume[pl + 2]) / dt);
  }
  return { hemMax: +hem.toFixed(3), plumeTipMax: +plume.toFixed(3) };
}

/**
 * The same move (combo3) under different time steps, compared to the 60 Hz run at equal GAME times (every 1/30 s).
 * Animation (weaponTip) is time-exact by construction, so any cloth / spring deviation is solver dt-dependence.
 */
function dtCompare(o = { clip: 'audit.spin' }) {
  const ref = trace('spin', 1 / 30, o);
  const runs = { hz120: trace('hz120', 1 / 30, o), hz30: trace('hz30', 1 / 30, o), spike: trace('spike', 1 / 30, o), hitstop: trace('hitstop', 1 / 30, o), slowmo: trace('slowmo', 1 / 30, o) };
  // uniform 0.1x for the whole move (pure integrator check), sampled at the same game times
  SCEN.slowAll = { T: 1.6, note: 'spin, whole move at 0.1x', setup: spinStart, events: [[0, playSpin]], dt: () => 1 / 600 };
  runs.slowAll = trace('slowAll', 1 / 30, o);
  delete SCEN.slowAll;
  const out = {};
  for (const [k, tr] of Object.entries(runs)) out[k] = diff(ref, tr);
  out.slowmoWindow = { during: diff(ref, runs.slowmo, { from: 0.3, to: 0.6 }), after: diff(ref, runs.slowmo, { from: 0.6, to: 1.6 }) };
  out.speedInWindow030_060 = { ref60: speeds(ref, 0.3, 0.6), slowmo: speeds(runs.slowmo, 0.3, 0.6), slowAll: speeds(runs.slowAll, 0.3, 0.6), hz120: speeds(runs.hz120, 0.3, 0.6), hz30: speeds(runs.hz30, 0.3, 0.6) };
  out.speedFirst50msOfSlowmo = { ref60: speeds(ref, 0.3, 0.3501), slowmo: speeds(runs.slowmo, 0.3, 0.3501) };
  return out;
}

/** Free-swing damping test: hold a pose, kick the cape sideways with a root jolt, measure the decay at several dt. */
function decay() {
  const res = {};
  for (const [k, dt] of [['hz30', 1 / 30], ['hz60', 1 / 60], ['hz120', 1 / 120], ['slow01', 1 / 600]]) {
    const A = charA(), a = A.char;
    settle(A, 'demo.stance');
    a.breath.depth = 0;
    // jolt: move the root 0.25 m along -Z over one 60 Hz-equivalent step (inertia kicks the cloth / springs)
    const C = A.cloths.find((c) => c.name === 'cape').c, j0 = (C.R - 1) * C.C;
    const hem0 = () => { let z = 0; for (let i = j0; i < C.n; i++) z += C.p[i * 3 + 2]; return z / (C.n - j0); };
    const plumeS = A.springs.find((s) => /^plume/.test(s.name)).s;
    const rest = hem0(), restP = plumeS.p[plumeS.p.length - 1];
    a.root.position.z -= 0.25;
    let t = 0, peak = 0, peakP = 0, settleT = null, settleP = null;
    const curve = [];
    while (t < 3 - 1e-9) {
      a.update(dt, dt); t += dt;
      const dz = hem0() - rest, dp = plumeS.p[plumeS.p.length - 1] - restP;
      peak = Math.max(peak, Math.abs(dz)); peakP = Math.max(peakP, Math.abs(dp));
      if (Math.abs(dz) > 0.1 * peak) settleT = null; else if (settleT === null) settleT = t;
      if (Math.abs(dp) > 0.1 * peakP) settleP = null; else if (settleP === null) settleP = t;
      if (Math.abs((t * 20) - Math.round(t * 20)) < 1e-6) curve.push(+dz.toFixed(4));
    }
    a.root.position.z = 0;
    res[k] = { capeHemPeak: +peak.toFixed(4), capeSettle10pct: settleT && +settleT.toFixed(3), plumePeak: +peakP.toFixed(4), plumeSettle10pct: settleP && +settleP.toFixed(3), capeHemZ_every50ms: curve.slice(0, 30) };
  }
  return res;
}

// ---- robustness --------------------------------------------------------------------------------------------------------
function tipPos(c) { c.sockets.weaponTip.getWorldPosition(_v); return [_v.x, _v.y, _v.z]; }

/** Max per-frame weapon-tip jump (m) and max per-frame bone rotation (deg) over n frames of fn(frame) + update. */
function popTest(A, n, fn) {
  const c = A.char, bones = c.skeleton.bones.slice(0, A.firstCloth);
  const prevQ = bones.map((b) => b.quaternion.clone());
  let tip = tipPos(c), maxTip = 0, maxRot = 0, rotBone = null;
  for (let f = 0; f < n; f++) {
    fn(f);
    c.update(FPS60, FPS60);
    const t2 = tipPos(c);
    maxTip = Math.max(maxTip, Math.hypot(t2[0] - tip[0], t2[1] - tip[1], t2[2] - tip[2]));
    tip = t2;
    bones.forEach((b, i) => {
      const a = (2 * Math.acos(Math.min(1, Math.abs(b.quaternion.dot(prevQ[i]))))) * 180 / Math.PI;
      if (a > maxRot) { maxRot = a; rotBone = b.name; }
      prevQ[i].copy(b.quaternion);
    });
  }
  return { maxTipJumpM: +maxTip.toFixed(4), maxBoneRotDegPerFrame: +maxRot.toFixed(2), bone: rotBone, finite: finiteChar(A) };
}

/** A throw-away character (robustness tests that may poison state). */
function fresh() {
  const c = createCharacter(ctx, knight, { name: 'fresh', parent: null });
  c.play('demo.idle', { fade: 0 });
  const I = inspect(c);
  settle(I, 'demo.idle');
  return I;
}
const kill = (I) => I.char.dispose();

function robust() {
  const A = charA(), a = A.char, out = {};
  const T = (name, fn) => { try { out[name] = { ...(fn() || {}) }; } catch (e) { out[name] = { threw: String(e && e.message || e) }; } };
  /** Poisoning test on a fresh character: inject, then 120 frames of idle + teleport(), report finiteness. */
  const P = (name, inject) => T(name, () => {
    const I = fresh(), c = I.char;
    try {
      inject(c);
      c.update(FPS60, FPS60);
      const r = { finiteAfterInject: finiteChar(I) };
      c.play('demo.idle', { fade: 0.1, restart: true });
      for (let i = 0; i < 60; i++) c.update(FPS60, FPS60);
      r.finiteAfterIdle1s = finiteChar(I);
      c.teleport();
      for (let i = 0; i < 60; i++) c.update(FPS60, FPS60);
      r.finiteAfterTeleportPlus1s = finiteChar(I);
      const bad = [];
      for (const b of c.skeleton.bones) if (!b.matrixWorld.elements.every(Number.isFinite)) bad.push(b.name);
      r.nonFiniteBones = bad.length; r.examples = bad.slice(0, 6).join(' ');
      return r;
    } finally { kill(I); }
  });
  // per-clip intrinsic pops (content / IK), so the mixer tests below can be judged against them
  T('clip_pops', () => {
    const r = {};
    for (const n of ['demo.idle', 'demo.guard', 'demo.walkF', 'demo.hit', 'demo.combo1', 'demo.combo2', 'demo.combo3', 'demo.slam']) {
      settle(A, 'demo.stance');
      a.play(n, { fade: 0.08, restart: true });
      const p = popTest(A, Math.round(getClip(a.rig, n).duration * 60), () => {});
      r[n] = p.maxTipJumpM + 'm ' + p.maxBoneRotDegPerFrame + 'deg ' + p.bone;
    }
    return r;
  });
  const CALM = ['demo.idle', 'demo.guard', 'demo.hit', 'demo.walkF'];
  T('calm_reference_crossfades_every_20f', () => { settle(A, 'demo.idle'); return popTest(A, 120, (f) => { if (f % 20 === 0) a.play(CALM[(f / 20) % CALM.length], { fade: 0.1, restart: true }); }); });
  T('spam_calm_every_frame', () => { settle(A, 'demo.idle'); return popTest(A, 120, (f) => a.play(CALM[f % CALM.length], { fade: 0.1, restart: true })); });
  T('spam_restart_same_every_frame', () => { settle(A, 'demo.idle'); return popTest(A, 120, () => a.play('demo.hit', { fade: 0.1, restart: true })); });
  T('five_plays_in_one_frame', () => {
    settle(A, 'demo.idle');
    return popTest(A, 30, (f) => { if (f === 10) for (const n of ['demo.guard', 'demo.hit', 'demo.walkF', 'demo.guard', 'demo.hit']) a.play(n, { fade: 0.2, restart: true }); });
  });
  // 4-state cap: long fades (0.5 s) started every 2 frames; per-frame tip motion should stay small until a state is evicted
  T('mixer_eviction', () => {
    settle(A, 'demo.idle'); a.breath.depth = 0;
    const L = ['demo.guard', 'demo.hit', 'demo.walkF', 'demo.guard', 'demo.hit'];
    const steps = [];
    let tip = tipPos(a);
    for (let f = 0; f < 12; f++) {
      if (f % 2 === 0 && f / 2 < L.length) a.play(L[f / 2], { fade: 0.5, restart: true });
      a.update(FPS60, FPS60);
      const t2 = tipPos(a);
      steps.push(+Math.hypot(t2[0] - tip[0], t2[1] - tip[1], t2[2] - tip[2]).toFixed(3));
      tip = t2;
    }
    a.breath.depth = 1;
    return { tipStepPerFrameM: steps.join(' '), note: 'plays at frames 0,2,4,6,8; the 5th play (frame 8) evicts the fully weighted base' };
  });
  T('play_unknown_clip', () => { a.play('no.such.clip'); return { threw: false }; });
  T('layer_unknown_clip', () => { a.layer('x', 'no.such.clip'); return { threw: false }; });
  T('after_throws_still_updates', () => { settle(A, 'demo.idle'); for (let i = 0; i < 10; i++) a.update(FPS60, FPS60); return { finite: finiteChar(A), clip: a.clip }; });
  P('setClipTime_NaN', (c) => { c.play('demo.combo1', { fade: 0, restart: true }); c.setClipTime(NaN); });
  P('play_speed_NaN', (c) => { c.play('demo.combo1', { fade: 0.1, speed: NaN, restart: true }); });
  P('update_dt_NaN_and_negative', (c) => { c.update(NaN, NaN); c.update(-1 / 60, -1 / 60); });
  P('impulse_amount_NaN', (c) => { c.impulse({ amount: NaN }); });
  P('impulse_dir_NaN', (c) => { c.impulse({ dir: [NaN, 0, 0] }); });
  P('lookAt_NaN_target', (c) => { c.lookAt(new THREE.Vector3(NaN, 1, 0)); });
  P('root_position_NaN_one_frame', (c) => { c.root.position.x = NaN; c.update(FPS60, FPS60); c.root.position.x = 0; });
  P('wind_NaN', (c) => { c.wind = [NaN, 0, 0]; c.update(FPS60, FPS60); c.wind = [0, 0, 0]; });
  T('update_dt_1e4_loopclip', () => {
    const I = fresh(), c = I.char;
    settle(I, 'demo.walkF');
    let ev = 0; const off = c.onEvent(() => { ev++; });
    const t0 = performance.now(); c.update(1e4, 1e4); const ms = performance.now() - t0;
    off();
    const r = { ms: +ms.toFixed(1), eventsEmittedInOneUpdate: ev, finite: finiteChar(I), note: 'Infinity never returns: while (s.time >= d) s.time -= d (index.js advance)' };
    kill(I);
    return r;
  });
  T('negative_speed_loop', () => { settle(A, 'demo.idle'); a.play('demo.idle', { speed: -1, restart: true, fade: 0 }); for (let i = 0; i < 120; i++) a.update(FPS60, FPS60); const r = { clipTimeAfter2s: +a.clipTime.toFixed(3) }; settle(A, 'demo.idle'); return r; });
  T('impulse_unknown_bone_zero_dir', () => { settle(A, 'demo.idle'); a.impulse({ bone: 'nope' }); a.impulse({ dir: [0, 0, 0] }); for (let i = 0; i < 10; i++) a.update(FPS60, FPS60); return { finite: finiteChar(A) }; });
  // multi-hit: impulses accumulate (no clamp). Max chest / head deviation from the same frames without impulses.
  const flinch = (every, hits, amount) => {
    const seq = (withHits) => {
      settle(A, 'demo.stance'); a.breath.depth = 0;
      const qs = [];
      let k = 0;
      for (let f = 0; f < 120; f++) {
        if (withHits && f % every === 0 && k < hits) { a.impulse({ dir: [-1, 0.1, 0.2], amount }); k++; }
        a.update(FPS60, FPS60);
        qs.push([a.bones.chest.getWorldQuaternion(new THREE.Quaternion()), a.bones.head.getWorldQuaternion(new THREE.Quaternion()), a.bones.hips.getWorldPosition(new THREE.Vector3())]);
      }
      return qs;
    };
    const ref = seq(false), hit = seq(true);
    let mc = 0, mh = 0, mp = 0;
    const ang = (x, y) => 2 * Math.acos(Math.min(1, Math.abs(x.dot(y)))) * 180 / Math.PI;
    for (let i = 0; i < ref.length; i++) { mc = Math.max(mc, ang(ref[i][0], hit[i][0])); mh = Math.max(mh, ang(ref[i][1], hit[i][1])); mp = Math.max(mp, ref[i][2].distanceTo(hit[i][2])); }
    a.breath.depth = 1;
    return { chestMaxDeg: +mc.toFixed(1), headMaxDeg: +mh.toFixed(1), hipsShoveM: +mp.toFixed(3) };
  };
  T('impulse_single_heavy', () => flinch(1000, 1, 1));
  T('impulse_launcher_amount3', () => flinch(1000, 1, 3));
  T('impulse_9_hits_every_6_frames', () => flinch(6, 9, 1));
  T('impulse_6_hits_every_4_frames', () => flinch(4, 6, 1));
  T('impulse_every_frame_30', () => flinch(1, 30, 1));
  T('setFacing_0_and_spam', () => { settle(A, 'demo.idle'); a.setFacing(0); const f0 = a.facing; for (let i = 0; i < 30; i++) { a.setFacing(i % 2 ? 1 : -1); a.update(FPS60, FPS60); } a.setFacing(1); return { facingAfterSetFacing0: f0, finite: finiteChar(A) }; });
  T('teleport_cost', () => {
    settle(A, 'demo.idle');
    const t = [];
    for (let i = 0; i < 20; i++) { a.teleport(); const t0 = performance.now(); a.update(FPS60, FPS60); t.push(performance.now() - t0); }
    const n = [];
    for (let i = 0; i < 20; i++) { const t0 = performance.now(); a.update(FPS60, FPS60); n.push(performance.now() - t0); }
    const avg = (x) => +(x.reduce((s, v) => s + v, 0) / x.length).toFixed(3);
    return { updateAfterTeleportMs: avg(t), normalUpdateMs: avg(n) };
  });
  T('spring_bone_keyed_rotation', () => {
    // README section 7: spring bones are "pulled to the animated direction". Key tassetR / plume1 hard and compare.
    const PN = 'audit.sim.springKeyed';
    definePose(PN, { bones: { tassetR: [0, 0, 60], plume1: [0, 0, 70] } });
    invalidateClips();
    settle(A, 'neutral', { frames: 180 });
    const q0 = a.bones.tassetR.quaternion.clone(), p0 = a.bones.plume1.quaternion.clone();
    settle(A, PN, { frames: 180 });
    const q1 = a.bones.tassetR.quaternion.clone(), p1 = a.bones.plume1.quaternion.clone();
    const ang = (x, y) => +(2 * Math.acos(Math.min(1, Math.abs(x.dot(y)))) * 180 / Math.PI).toFixed(2);
    return { tassetR_changeDeg_for60degKey: ang(q0, q1), plume1_changeDeg_for70degKey: ang(p0, p1) };
  });
  settle(A, 'demo.idle');
  return out;
}

// ---- memory ----------------------------------------------------------------------------------------------------------
function memory(n = 20) {
  const r = ctx.renderer;
  const mem = () => ({ geometries: r.info.memory.geometries, textures: r.info.memory.textures, programs: (r.info.programs || []).length, sceneChildren: ctx.scene.children.length });
  __ED.render();
  const base = mem();
  const rows = [];
  let createMs = 0, peak = null;
  const heap0 = performance.memory ? performance.memory.usedJSHeapSize : null;
  for (let i = 0; i < n; i++) {
    const t0 = performance.now();
    const c = createCharacter(ctx, knight, { name: 'tmp' + i });
    createMs += performance.now() - t0;
    c.root.position.set(2.5, 0, 0);
    c.play(i % 2 ? 'demo.combo1' : 'demo.idle');
    for (let k = 0; k < 3; k++) c.update(FPS60, FPS60);
    __ED.render();
    const live = mem();
    if (!peak) peak = live;
    c.dispose();
    __ED.render();
    rows.push({ live, after: mem() });
  }
  const heap1 = performance.memory ? performance.memory.usedJSHeapSize : null;
  return { base, firstLive: peak, final: mem(), delta: Object.fromEntries(Object.keys(base).map((k) => [k, mem()[k] - base[k]])), perCycleAfter: rows.map((x) => x.after.geometries + '/' + x.after.textures + '/' + x.after.programs), createMsAvg: +(createMs / n).toFixed(1), heapDeltaMB_coarse: heap0 != null ? +((heap1 - heap0) / 1048576).toFixed(2) : null };
}

// ---- CPU ---------------------------------------------------------------------------------------------------------------
function chainDriver(a) {
  const L = ['demo.combo1', 'demo.combo2', 'demo.combo3', 'demo.slam', 'demo.walkF', 'demo.hit', 'demo.idle'];
  const opt = { fade: 0.06, restart: true };
  let i = 0, t = 0;
  return () => {
    t++;
    if (a.finished || (t > 150 && L[i % L.length] === 'demo.walkF') || (t > 180 && L[i % L.length] === 'demo.idle')) { i++; t = 0; a.play(L[i % L.length], opt); }
  };
}

function timeUpdates(infos, n, batch = 10) {
  const drivers = infos.map((I) => chainDriver(I.char));
  infos.forEach((I) => { I.char.play('demo.combo1', { fade: 0.06, restart: true }); });
  for (let i = 0; i < 300; i++) for (let k = 0; k < infos.length; k++) { drivers[k](); infos[k].char.update(FPS60, FPS60); }
  const per = [];
  let total = 0;
  for (let i = 0; i < n; i += batch) {
    const t0 = performance.now();
    for (let j = 0; j < batch; j++) for (let k = 0; k < infos.length; k++) { drivers[k](); infos[k].char.update(FPS60, FPS60); }
    const dt = performance.now() - t0;
    total += dt; per.push(dt / batch / infos.length);
  }
  per.sort((x, y) => x - y);
  const q = (p) => +per[Math.min(per.length - 1, Math.floor(p * per.length))].toFixed(4);
  return { msPerUpdate: +(total / n / infos.length).toFixed(4), best: +per[0].toFixed(4), p10: q(0.1), p50: q(0.5), p95: q(0.95), p99: q(0.99), max: +per[per.length - 1].toFixed(4), batch };
}

/** ms per char.update (combat chain loop). opts: { n = 2000, chars = 1 }. Differential breakdown cloth / springs. */
function cpu({ n = 2000, chars = 1 } = {}) {
  const infos = [charA()];
  if (chars > 1) infos.push(charB());
  infos.forEach((I, k) => settle(I, 'demo.stance', { x: k ? 2.5 : -2.5, facing: k ? -1 : 1 }));
  hookNoop(null);
  const full = timeUpdates(infos, n);
  hookNoop('cloth');
  const noCloth = timeUpdates(infos, n);
  hookNoop('spring');
  const noSpring = timeUpdates(infos, n);
  hookNoop(null);
  const full2 = timeUpdates(infos, n);
  const c0 = infos[0].char;
  return {
    tier: ctx.quality.tier, clothQuality: ctx.quality.cloth, bones: c0.stats.bones,
    cloth: infos[0].cloths.map((C) => `${C.name} ${C.c.C}x${C.c.R} iters ${C.c.iters} cons ${C.c.cons.length / 4}`),
    full, full2, noCloth, noSpring,
    clothMs_p10: +(Math.min(full.p10, full2.p10) - noCloth.p10).toFixed(4), springMs_p10: +(Math.min(full.p10, full2.p10) - noSpring.p10).toFixed(4),
  };
}

/** Costs around update(): world matrices, skeleton upload prep, teleport settle, clip compile, creation. */
function parts() {
  const A = charA(), a = A.char;
  settle(A, 'demo.idle');
  const time = (n, fn) => { const t0 = performance.now(); for (let i = 0; i < n; i++) fn(i); return +((performance.now() - t0) / n).toFixed(4); };
  const out = {};
  out.updateMatrixWorldTrueMs = time(2000, () => a.root.updateMatrixWorld(true));
  out.skeletonUpdateMs = time(2000, () => a.skeleton.update());
  out.objectsUnderRoot = (() => { let k = 0; a.root.traverse(() => { k++; }); return k; })();
  out.updateMs_idle = time(1000, () => a.update(FPS60, FPS60));
  // teleport(): the next update pre-settles every cloth (24 steps each)
  out.updateAfterTeleportMs = time(50, () => { a.teleport(); a.update(FPS60, FPS60); });
  // clip compile (lazy, per rig, on first play): fresh character
  const fresh = createCharacter(ctx, knight, { name: 'fresh', parent: null });
  const comp = {};
  let tot = 0;
  for (const name of listClips()) {
    const t0 = performance.now(); getClip(fresh.rig, name); const ms = performance.now() - t0;
    comp[name] = +ms.toFixed(2); tot += ms;
  }
  out.clipCompileMs = comp; out.clipCompileTotalMs = +tot.toFixed(1);
  const t1 = performance.now(); const f2 = createCharacter(ctx, knight, { name: 'fresh2', parent: null }); const f2t = performance.now() - t1;
  const t2 = performance.now(); f2.play('demo.combo3'); f2.update(FPS60, FPS60); out.firstPlayAndUpdateMs_combo3_freshRig = +(performance.now() - t2).toFixed(2);
  const t3 = performance.now(); f2.play('demo.slam'); f2.update(FPS60, FPS60); out.firstPlayAndUpdateMs_slam_freshRig = +(performance.now() - t3).toFixed(2);
  out.createCharacterMs = +f2t.toFixed(1);
  fresh.dispose(); f2.dispose();
  return out;
}

/** Draw calls / triangles for one character (main + shadow pass), and relative render time with / without its shadow. */
function draw() {
  const A = charA(), a = A.char;
  settle(A, 'demo.stance');
  if (CH[1]) CH[1].char.setVisible(false);
  const r = ctx.renderer;
  const stat = () => { __ED.render(); return { calls: r.info.render.calls, tris: r.info.render.triangles }; };
  a.setVisible(true);
  const withChar = stat();
  for (const m of Object.values(a.meshes)) m.castShadow = false;
  const noShadow = stat();
  for (const m of Object.values(a.meshes)) m.castShadow = true;
  a.setVisible(false);
  const without = stat();
  a.setVisible(true);
  const time = (n) => { const t0 = performance.now(); for (let i = 0; i < n; i++) __ED.render(); return +((performance.now() - t0) / n).toFixed(2); };
  const tOn = time(6);
  for (const m of Object.values(a.meshes)) m.castShadow = false;
  const tOff = time(6);
  for (const m of Object.values(a.meshes)) m.castShadow = true;
  a.setVisible(false);
  const tNone = time(6);
  a.setVisible(true);
  const verts = Object.fromEntries(Object.entries(a.meshes).map(([k, m]) => [k, m.geometry.attributes.position.count]));
  return {
    tier: ctx.quality.tier, shadows: !!ctx.quality.shadows, stats: a.stats, verts,
    charCalls: withChar.calls - without.calls, charTris: withChar.tris - without.tris,
    shadowCalls: withChar.calls - noShadow.calls, shadowTris: withChar.tris - noShadow.tris,
    boneTexture: a.skeleton.boneTexture ? a.skeleton.boneTexture.image.width + 'x' + a.skeleton.boneTexture.image.height : null,
    swiftshaderRenderMs: { charWithShadow: tOn, charNoShadow: tOff, noChar: tNone },
  };
}

// ---- allocation profiling hooks (driven by a CDP scenario script) --------------------------------------------------------
let allocDrv = null;
function allocPrep(withLayer = false) {
  const A = charA(), a = A.char;
  settle(A, 'demo.stance');
  hookNoop(null);
  allocDrv = chainDriver(a);
  a.lookAt(new THREE.Vector3(3, 1.6, 0));
  if (withLayer) a.layer('upper', 'demo.guard', { mask: 'upper', weight: 0.5 });
  for (let i = 0; i < 600; i++) { allocDrv(); a.update(FPS60, FPS60); }
  return true;
}
function allocRun(n = 2000) {
  const a = charA().char;
  for (let i = 0; i < n; i++) { allocDrv(); a.update(FPS60, FPS60); }
  return true;
}

// ---- fix experiments (lab-only copy of Cloth.update; the runtime is untouched) ------------------------------------------
/**
 * Variant switches: substepH (fixed max substep length, s) | capLerp (interpolate body capsules across substeps like the
 * pins) | collideIters (n: push particles out of capsules inside the last n constraint iterations) | timeDamp (damping
 * per second + time-corrected Verlet when the substep length changes).
 */
const EXP = { substepH: 0, capLerp: false, collideIters: 0, timeDamp: false };
function expClothUpdate(dt, mq, mp, gravity, wind, capsules, floorY, time, settling = false) {
  if (!this.ready && !settling) { this._settleG = gravity; this._caps = capsules; this._floor = floorY; this._snap(mq, mp); }
  const s = this.spec, C = this.C, n = this.n, p = this.p, pp = this.pp, inv = this.inv;
  const pinN = C * this.layout.pinRows;
  this.anchorStart.set(p.subarray(0, pinN * 3));
  this._anchors(mq, mp, this.anchorTarget);
  const capOn = EXP.capLerp && capsules && capsules.count;
  if (capOn && (!this._capPrev || this._capPrev.length !== capsules.data.length || settling)) {
    this._capPrev = Float32Array.from(capsules.data);
    this._capTmp = { count: capsules.count, data: new Float32Array(capsules.data.length) };
  }
  if (dt <= 0) { p.set(this.anchorTarget, 0); pp.set(this.anchorTarget, 0); if (capOn) this._capPrev.set(capsules.data); return; }
  dt = Math.min(dt, 1 / 30);
  const steps = EXP.substepH ? Math.max(1, Math.ceil(dt / EXP.substepH - 1e-6)) : dt > 1 / 55 ? 3 : 2, h = dt / steps, h2 = h * h;
  const damp = EXP.timeDamp ? Math.pow(1 - s.damping, h * 120) : 1 - s.damping;
  const vmax = s.maxSpeed * h;
  const cons = this.cons, nc = cons.length;
  for (let st = 1; st <= steps; st++) {
    const f = st / steps;
    let caps = capsules;
    if (capOn) {
      const a = this._capPrev, b = capsules.data, o = this._capTmp.data;
      for (let i = 0; i < o.length; i++) o[i] = a[i] + (b[i] - a[i]) * f;
      caps = this._capTmp;
    }
    for (let k = 0; k < pinN; k++) {
      const o = k * 3;
      pp[o] = p[o]; pp[o + 1] = p[o + 1]; pp[o + 2] = p[o + 2];
      p[o] = this.anchorStart[o] + (this.anchorTarget[o] - this.anchorStart[o]) * f;
      p[o + 1] = this.anchorStart[o + 1] + (this.anchorTarget[o + 1] - this.anchorStart[o + 1]) * f;
      p[o + 2] = this.anchorStart[o + 2] + (this.anchorTarget[o + 2] - this.anchorStart[o + 2]) * f;
    }
    const vs = EXP.timeDamp && st === 1 && this._hPrev ? h / this._hPrev : 1;
    const tt = time + h * st;
    for (let k = pinN; k < n; k++) {
      const o = k * 3, i = k % C, j = (k / C) | 0;
      let vx = (p[o] - pp[o]) * damp * vs, vy = (p[o + 1] - pp[o + 1]) * damp * vs, vz = (p[o + 2] - pp[o + 2]) * damp * vs;
      const vl = Math.sqrt(vx * vx + vy * vy + vz * vz);
      if (vl > vmax) { const c = vmax / vl; vx *= c; vy *= c; vz *= c; }
      const gust = s.wind * (0.65 + 0.35 * Math.sin(tt * 1.7 + i * 0.45 + j * 0.3) * Math.sin(tt * 0.63 + j * 0.21));
      pp[o] = p[o]; pp[o + 1] = p[o + 1]; pp[o + 2] = p[o + 2];
      p[o] += vx + (gravity[0] * s.gravity + wind[0] * gust) * h2;
      p[o + 1] += vy + (gravity[1] * s.gravity + wind[1] * gust) * h2;
      p[o + 2] += vz + (gravity[2] * s.gravity + wind[2] * gust) * h2;
    }
    for (let it = 0; it < this.iters; it++) {
      for (let c = 0; c < nc; c += 4) {
        const a = cons[c] * 3, b = cons[c + 1] * 3, wa = inv[cons[c]], wb = inv[cons[c + 1]], ws = wa + wb;
        if (ws === 0) continue;
        const dx = p[b] - p[a], dy = p[b + 1] - p[a + 1], dz = p[b + 2] - p[a + 2];
        const l = Math.sqrt(dx * dx + dy * dy + dz * dz);
        if (l < 1e-7) continue;
        const corr = ((l - cons[c + 2]) / (l * ws)) * cons[c + 3];
        p[a] += dx * corr * wa; p[a + 1] += dy * corr * wa; p[a + 2] += dz * corr * wa;
        p[b] -= dx * corr * wb; p[b + 1] -= dy * corr * wb; p[b + 2] -= dz * corr * wb;
      }
      if (EXP.collideIters && caps && it >= this.iters - EXP.collideIters) for (let k = pinN; k < n; k++) pushOutCapsules(p, k * 3, caps, s.margin);
    }
    for (let k = pinN; k < n; k++) {
      const o = k * 3, t = (k % C) * 3, maxd = this.tether[k] * s.tether;
      const dx = p[o] - p[t], dy = p[o + 1] - p[t + 1], dz = p[o + 2] - p[t + 2];
      const l = Math.sqrt(dx * dx + dy * dy + dz * dz);
      if (l > maxd) { const c = maxd / l; p[o] = p[t] + dx * c; p[o + 1] = p[t + 1] + dy * c; p[o + 2] = p[t + 2] + dz * c; }
      if (caps) pushOutCapsules(p, o, caps, s.margin);
      const fy = floorY + s.margin * 0.6;
      if (p[o + 1] < fy) { p[o + 1] = fy; pp[o] += (p[o] - pp[o]) * 0.6; pp[o + 2] += (p[o + 2] - pp[o + 2]) * 0.6; }
    }
  }
  this._hPrev = h;
  if (capOn) this._capPrev.set(capsules.data);
  for (let k = 0; k < n * 3; k++) if (!(Math.abs(p[k]) < 50)) { this.ready = false; break; }
}

/** Run the clean spin (+ decay test) with a cloth variant. variants: { name: EXP settings }. */
function experiment(variants = {
  shipped: null,
  copyOfShipped: {},
  capLerp: { capLerp: true },
  collideIters3: { collideIters: 3 },
  substep240: { substepH: 1 / 240 },
  capLerp_collide3: { capLerp: true, collideIters: 3 },
  capLerp_collide3_sub240: { capLerp: true, collideIters: 3, substepH: 1 / 240 },
  timeDamp: { timeDamp: true },
  all: { capLerp: true, collideIters: 3, substepH: 1 / 240, timeDamp: true },
}, { decayToo = true } = {}) {
  const out = {};
  for (const [name, v] of Object.entries(variants)) {
    Object.assign(EXP, { substepH: 0, capLerp: false, collideIters: 0, timeDamp: false }, v || {});
    const install = () => { Cloth.prototype.update = v ? expClothUpdate : ORIG.cloth; };
    const r = {};
    for (const sc of ['spin', 'hz30', 'spike', 'flipTurn']) {
      const S = start(sc, { clip: 'audit.spin' });
      install();
      while (!done(S)) step(S);
      const m = summary(S).cape;
      r[sc] = `rpen ${m.rpen.v} (${m.rpen.frames}f) d ${m.rdepth.v} | edges ${m.edges.v} (${m.edges.frames}f) | stretch ${m.stretch.v} | pen ${m.pen.v}`;
    }
    // CPU (combat chain), same variant
    const A = charA();
    settle(A, 'demo.stance');
    install();
    const t = timeUpdates([A], 1000);
    r.cpu = `p10 ${t.p10} p50 ${t.p50} best ${t.best} ms`;
    if (decayToo) {
      const d = decay();
      r.decay = Object.fromEntries(Object.entries(d).map(([k, x]) => [k, `peak ${x.capeHemPeak} settle ${x.capeSettle10pct} zero-cross ${(() => { const c = x.capeHemZ_every50ms; const i = c.findIndex((z) => z < 0); return i < 0 ? 'none' : ((i + 1) * 0.05).toFixed(2) + 's'; })()}`]));
    }
    Cloth.prototype.update = ORIG.cloth;
    out[name] = r;
  }
  Object.assign(EXP, { substepH: 0, capLerp: false, collideIters: 0, timeDamp: false });
  return out;
}

// ---- captures ------------------------------------------------------------------------------------------------------------
const VIEWS = {
  fight: { dist: 4.6, yaw: 0, pitch: 4, ty: 1.0 },
  34: { dist: 4.2, yaw: 40, pitch: 6, ty: 1.0 },
  back34: { dist: 4.2, yaw: -130, pitch: 10, ty: 1.0 },
  side: { dist: 4.0, yaw: 90, pitch: 5, ty: 1.0 },
  top: { dist: 4.5, yaw: 20, pitch: 70, ty: 0.8 },
  close: { dist: 2.4, yaw: 25, pitch: 2, ty: 0.75 },
  closeBack: { dist: 2.4, yaw: -120, pitch: 4, ty: 0.75 },
};
/** Stage a scenario for the capture harness: the lab's update loop steps it frame by frame (same code path as run()). */
function stage(name, { view = 'fight', follow = true, clip } = {}) {
  const S = start(name, { clip });
  const v = typeof view === 'object' ? { ...VIEWS.fight, ...view } : VIEWS[view] || VIEWS.fight;
  const aim = () => lab.view({ target: [S.a.root.position.x, v.ty, 0], dist: v.dist, yaw: v.yaw, pitch: v.pitch });
  aim();
  lab.st.driver = () => { if (!done(S)) step(S); if (follow) aim(); };
  lab.st.S = S;
  return { scenario: name, note: S.sc.note };
}

createLab({
  view: { target: [0, 1.0, 0], dist: 4.6, yaw: 0, pitch: 4, fov: 40 },
  setup(c, l) {
    ctx = c; lab = l;
    ctx.scene.environment = studioEnv(ctx.renderer);
    ctx.scene.environmentIntensity = 1;
    lab.lights.key.intensity = 2.6;
    lab.lights.rim.intensity = 2.2;
    const a = createCharacter(ctx, knight, { name: 'p1' });
    a.play('demo.idle', { fade: 0 });
    CH[0] = inspect(a);
    lab.st = { driver: null };
    ctx.onUpdate((dg, dr) => {
      if (lab.st.driver) { lab.st.driver(); return; }
      for (const I of CH) if (I && I.char.root.visible) I.char.update(dg, dr);
    }, ORDER.CHAR);
    window.__ED.sim = {
      SCEN, run, all, dtCompare, decay, robust, memory, cpu, parts, draw, stage, allocPrep, allocRun, start, step, done, settle, cleanSpin, experiment, EXP,
      list: () => Object.fromEntries(Object.entries(SCEN).map(([k, v]) => [k, v.note])),
      last: () => lab.st.S && summary(lab.st.S),
      chars: CH,
    };
  },
  scenarios: {
    stage(c, l, name, opts) { return stage(name, opts); },
    reset() { lab.st.driver = null; settle(charA(), 'demo.idle'); },
  },
});

