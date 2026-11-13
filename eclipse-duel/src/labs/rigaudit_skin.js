// Rig audit lab, lens "skinning, deformation and range of motion" (auditor's sandbox, read-only on src/char).
// Drives every joint through its range one at a time and in hard combinations, on several body types, and measures
// the deformation with numbers rather than opinions.
//
//   __ED.audit.variant(key)            build / show a body type: kael | iska | vorn | giantP (proportions + geometry x4.2)
//                                      | giantR (default knight, root.scale 4.2)
//   __ED.audit.pose(name)              hold a ROM pose on the current body type (cloth / springs settled); 'clip@t'
//                                      runs a clip from 0 to t at 60 fps and holds it (e.g. 'demo.slam@0.633')
//   __ED.audit.measure()               metrics of the current pose vs bind / rest (see METRICS below)
//   __ED.audit.rom(key, names?, opts)  metrics table over the ROM set ({ holes: true } adds GPU see-through counts)
//   __ED.audit.queue(items) + --each "__ED.audit.step()"     capture sequences: items = [variant, pose, focus, view, dist, holes?]
//                                      focus = bone name or 'w<x>_<y>_<z>' (fixed point); view = front | 34 | side | frontL | back34
//   __ED.audit.holes()                 see-through pixels (front-face render vs double-sided silhouette) + magenta overlay
//   __ED.audit.show(['suit'])          show only some material slots (judge the under-suit skinning); exposure(v) brightens
//   __ED.audit.twistScan(clip, opts)   per-frame helper-bone / IK continuity (twist helpers, deltoid, elbow jumps, grip)
//   __ED.audit.helperSweep(...)        upper-arm twist extraction vs swing (singularity check)
//   __ED.audit.cpu(clip, frames)       ms per char.update()
//   __ED.audit.axes()                  README axis table check (+30 deg per axis -> tip direction)
//
// METRICS
//   ring     loft cross-section area (Newell) / bind area, per ring; min ratio near each joint = volume loss
//   axis     min distance of joint-region suit vertices to the posed bone polyline / the same in bind
//   flips    suit triangles whose posed face normal opposes the skinned vertex normals (folds -> culled holes)
//   cross    side flips vs rest against analytic plate solids (superellipse shells, bone frame):
//            suit -> plate = suit pokes through a plate that covered it at rest; plate -> plate = a plate sinks into /
//            pokes out of another plate (depth in m past the surface)
//   cores    vertices of one body segment inside another segment's core capsule, depth increase vs rest (> 5 mm)
//   cloth    cloth render vertices inside a plate's inner surface / a body core (cloth through the body)
//   holes    pixels where the double-sided silhouette shows geometry but the normal front-face render shows background
//   nan      any non-finite bone matrix

import * as THREE from 'three';
import { createLab, ORDER } from '../core/lab.js';
import { createCharacter, definePose, defineClip, invalidateClips, shapes as S0 } from '../char/index.js';
import { DEFAULT_PROPORTIONS } from '../char/skeleton.js';
import { knight } from '../char/designs/knight.js';
import '../char/clips/demo.js';

const D2R = Math.PI / 180;

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

// ---- body types ----------------------------------------------------------------------------------------------------
const VARIANTS = {
  kael: { label: 'KAEL knight ~1.9', proportions: {}, K: 1, rootScale: 1, h: 1.9 },
  iska: {
    label: 'ISKA slender female ~1.78', K: 1, rootScale: 1, h: 1.78,
    proportions: { hipHeight: 0.93, pelvisDrop: 0.058, hipWidth: 0.098, spine: 0.1, chest: 0.15, neck: 0.23, head: 0.098, shoulderHeight: 0.185, clavicleRoot: 0.028, clavicle: 0.165, upperArm: 0.28, foreArm: 0.245, hand: 0.078, footLength: 0.122, ankleHeight: 0.08, heelLength: 0.06, toeLength: 0.072 },
  },
  vorn: {
    label: 'VORN tall ~2.02', K: 1, rootScale: 1, h: 2.02,
    proportions: { hipHeight: 1.06, pelvisDrop: 0.065, hipWidth: 0.105, spine: 0.12, chest: 0.18, neck: 0.27, head: 0.11, shoulderHeight: 0.21, clavicle: 0.2, upperArm: 0.325, foreArm: 0.29, hand: 0.09, footLength: 0.145 },
  },
  giantP: { label: 'giant: proportions + geometry x4.2', proportions: {}, K: 4.2, rootScale: 1, h: 1.9 * 4.2 },
  giantR: { label: 'giant: root.scale 4.2', proportions: {}, K: 1, rootScale: 4.2, h: 1.9 * 4.2 },
};

const scaleCurve = (c, K) => (c === undefined ? undefined : typeof c === 'function' ? (v) => c(v) * K : Array.isArray(c) ? c.map(([k, x]) => [k, x * K]) : c * K);
const sv = (a, K) => (a ? a.map((x) => x * K) : a);

/**
 * Wrap a design so its build records every kit piece (slot, vertex range, bone, shell params, opts) and optionally
 * scales all geometry and design data by K (a giant built through proportions instead of root.scale).
 */
function recordingDesign(base, V, key) {
  const K = V.K;
  const P = { ...DEFAULT_PROPORTIONS, ...(base.proportions || {}), ...(V.proportions || {}) };
  if (K !== 1) for (const k of Object.keys(P)) if (k !== 'thighRatio') P[k] *= K;
  const rec = { pieces: [], cursor: {} };
  const S = { ...S0, shell: (o) => { const g = S0.shell(o); g.userData.shell = o; return g; } };
  const sGeo = (g) => { if (K === 1) return g; const c = g.clone(); c.applyMatrix4(new THREE.Matrix4().makeScale(K, K, K)); return c; };
  const sOpt = (o = {}) => (K === 1 ? o : { ...o, at: sv(o.at, K) });
  const sSpec = (s) => (K === 1 ? s : { ...s, path: s.path.map(([b, o]) => [b, sv(o, K)]), rx: scaleCurve(s.rx, K), rz: scaleCurve(s.rz, K), ox: scaleCurve(s.ox, K), oz: scaleCurve(s.oz, K) });
  const loftCount = (s) => { const W = ((s.segs && s.segs[0]) || 16) + 1, H = ((s.segs && s.segs[1]) || 24) + 1, caps = s.caps || [true, true]; return W * H + (caps[0] ? W + 1 : 0) + (caps[1] ? W + 1 : 0); };
  const swap = (b) => (typeof b === 'string' && b.endsWith('R') ? b.slice(0, -1) + 'L' : b);
  const push = (slot, n, info) => { const start = rec.cursor[slot] || 0; rec.pieces.push({ slot, start, count: n, id: rec.pieces.length, ...info }); rec.cursor[slot] = start + n; };
  const design = {
    ...base,
    id: key,
    proportions: P,
    bones: (base.bones || []).map((b) => ({ ...b, at: sv(b.at, K) })),
    springs: (base.springs || []).map((s) => { const t = { ...s }; if (s.tip) t.tip = sv(s.tip, K); if (s.radius !== undefined) t.radius = s.radius * K; return t; }),
    colliders: (base.colliders || []).map((c) => ({ ...c, a: [c.a[0], sv(c.a[1], K)], b: [c.b[0], sv(c.b[1], K)], r: c.r * K })),
    cloth: (base.cloth || []).map((c) => ({ ...c, top: c.top.map(([b, o]) => [b, sv(o, K)]), length: (c.length ?? 1) * K, thickness: (c.thickness ?? 0.012) * K, margin: (c.margin ?? 0.025) * K, offset: c.offset ? (u, v) => sv(c.offset(u, v), K) : undefined })),
    weapon: base.weapon ? { ...base.weapon, base: sv(base.weapon.base, K), tip: sv(base.weapon.tip, K), grips: Object.fromEntries(Object.entries(base.weapon.grips || {}).map(([n, g]) => [n, { ...g, pos: sv(g.pos, K) }])) } : undefined,
    build(kit, S1, rig) {
      const W = {
        rig: kit.rig, bind: kit.bind,
        bonePos: (b) => kit.bonePos(b),
        add(slot, bone, geo, opts = {}) {
          const g = sGeo(geo);
          push(slot, g.attributes.position.count, { kind: 'rigid', bone, shell: geo.userData.shell, opts, mirror: false });
          kit.add(slot, bone, g, sOpt(opts)); return W;
        },
        addPair(slot, b0, geo, opts = {}) {
          let b = b0;
          if (kit.rig.index[b + 'R'] === undefined && /R$/.test(b)) b = b.slice(0, -1);
          const g = sGeo(geo), n = g.attributes.position.count;
          push(slot, n, { kind: 'rigid', bone: b + 'R', shell: geo.userData.shell, opts, mirror: false });
          push(slot, n, { kind: 'rigid', bone: b + 'L', shell: geo.userData.shell, opts, mirror: true });
          kit.addPair(slot, b0, g, sOpt(opts)); return W;
        },
        addBlend(slot, frame, geo, weights, opts = {}) {
          const g = sGeo(geo);
          push(slot, g.attributes.position.count, { kind: 'blend', bone: frame, opts });
          kit.addBlend(slot, frame, g, weights, sOpt(opts)); return W;
        },
        addSkinned(slot, geo, fn, opts = {}) {
          const g = sGeo(geo);
          push(slot, g.attributes.position.count, { kind: 'skinned', bone: opts.frame || null, opts });
          kit.addSkinned(slot, g, fn, sOpt(opts)); return W;
        },
        loft(slot, spec, opts = {}) {
          const s = sSpec(spec);
          push(slot, loftCount(s), { kind: 'loft', spec: s, name: s.path[0][0] + '..' + s.path[s.path.length - 1][0] });
          kit.loft(slot, s, opts); return W;
        },
        loftPair(slot, spec, opts = {}) {
          const s = sSpec(spec), n = loftCount(s);
          push(slot, n, { kind: 'loft', spec: s, name: s.path[0][0] + '..' + s.path[s.path.length - 1][0] });
          push(slot, n, { kind: 'loft', spec: s, mirror: true, name: swap(s.path[0][0]) + '..' + swap(s.path[s.path.length - 1][0]) });
          kit.loftPair(slot, s, opts); return W;
        },
      };
      base.build(W, S, rig);
    },
  };
  return { design, rec };
}

// ---- analytic plate solids (superellipse shells in their bone frame) ----------------------------------------------
const _m = new THREE.Matrix4(), _q = new THREE.Quaternion(), _e = new THREE.Euler();
function compileShell(piece, K) {
  const o = piece.shell, op = piece.opts || {};
  const f = S0.fnOf;
  _e.set(((op.rot && op.rot[0]) || 0) * D2R, ((op.rot && op.rot[1]) || 0) * D2R, ((op.rot && op.rot[2]) || 0) * D2R, 'ZXY');
  _q.setFromEuler(_e).invert();
  const s = op.scale ?? 1;
  const A0 = f(o.a0, 0), A1 = f(o.a1, 360);
  return {
    K, mirror: piece.mirror, at: (op.at || [0, 0, 0]).map((x) => x * K), qi: [_q.x, _q.y, _q.z, _q.w], sc: Array.isArray(s) ? s : [s, s, s],
    y0: o.y0 ?? 0, y1: o.y1 ?? -0.3, RX: f(o.rx, 0.1), RZ: f(o.rz ?? o.rx, 0.1), OX: f(o.ox, 0), OZ: f(o.oz, 0), NE: f(o.n, 2), A0, A1,
    closed: Math.abs(A1(0.5) - A0(0.5)) >= 359.9, dy: o.dy || null, thick: o.thick ?? 0.006,
  };
}
const qv = new Float32Array(3);
function qrotArr(q, x, y, z) {
  const qx = q[0], qy = q[1], qz = q[2], qw = q[3];
  const tx = 2 * (qy * z - qz * y), ty = 2 * (qz * x - qx * z), tz = 2 * (qx * y - qy * x);
  qv[0] = x + qw * tx + qy * tz - qz * ty; qv[1] = y + qw * ty + qz * tx - qx * tz; qv[2] = z + qw * tz + qx * ty - qy * tx;
}
/** Evaluate point (bone frame of the shell's bone) against a compiled shell. out = [inCoverage, sOuter, sInner]. */
function shellEval(c, x, y, z, out, vm = 0.03, am = 3) {
  if (c.mirror) z = -z;
  x -= c.at[0]; y -= c.at[1]; z -= c.at[2];
  qrotArr(c.qi, x, y, z);
  x = qv[0] / (c.sc[0] * c.K); y = qv[1] / (c.sc[1] * c.K); z = qv[2] / (c.sc[2] * c.K);
  let v = (c.y0 - y) / (c.y0 - c.y1);
  let rx, rz, dx, dz, n, t, d = 0, span = 360;
  for (let it = 0; it < (c.dy ? 3 : 1); it++) {
    const vv = Math.max(0, Math.min(1, v));
    rx = c.RX(vv); rz = c.RZ(vv); n = c.NE(vv);
    dx = x - c.OX(vv); dz = z - c.OZ(vv);
    const h = n / 2;
    t = Math.atan2(Math.sign(dz) * Math.pow(Math.abs(dz / rz), h), Math.sign(dx) * Math.pow(Math.abs(dx / rx), h)) / D2R;
    const a0 = c.A0(vv), a1 = c.A1(vv);
    span = a1 - a0;
    d = (((t - a0) % 360) + 360) % 360;
    if (c.dy) v = (c.y0 - (y - c.dy(Math.max(0, Math.min(1, d / span)), vv, a0 + d))) / (c.y0 - c.y1);
  }
  const inA = c.closed || (d >= am && d <= span - am);
  out[0] = v >= vm && v <= 1 - vm && inA ? 1 : 0;
  const dist = Math.hypot(dx, dz) * c.K;
  const lam = Math.pow(Math.pow(Math.abs(dx / rx), n) + Math.pow(Math.abs(dz / rz), n), 1 / n);
  const ti = c.thick;
  const lamI = Math.pow(Math.pow(Math.abs(dx / Math.max(1e-3, rx - ti)), n) + Math.pow(Math.abs(dz / Math.max(1e-3, rz - ti)), n), 1 / n);
  out[1] = lam > 1e-6 ? dist * (1 - 1 / lam) : -rx * c.K;
  out[2] = lamI > 1e-6 ? dist * (1 - 1 / lamI) : -rx * c.K;
  return out;
}

// ---- body segments and core capsules ------------------------------------------------------------------------------
function segOf(name) {
  if (name === 'hips') return 'pelvis';
  if (name === 'spine') return 'abdomen';
  if (name === 'chest' || /^shoulder[RL]$/.test(name)) return 'thorax';
  if (name === 'neck') return 'neck';
  if (name === 'head' || /^plume/.test(name)) return 'head';
  let m = name.match(/^(deltoid|upperArm|upperArmTwist)([RL])$/); if (m) return 'upperArm' + m[2];
  m = name.match(/^elbow([RL])$/); if (m) return 'elbow' + m[1];
  m = name.match(/^(foreArm|foreArmTwist)([RL])$/); if (m) return 'foreArm' + m[2];
  m = name.match(/^(hand|fingers|fingerTips|thumb|weapon)([RL])$/); if (m) return 'hand' + m[2];
  m = name.match(/^(thigh|tasset)([RL])$/); if (m) return 'thigh' + m[2];
  m = name.match(/^knee([RL])$/); if (m) return 'knee' + m[1];
  m = name.match(/^shin([RL])$/); if (m) return 'shin' + m[1];
  m = name.match(/^(foot|toe)([RL])$/); if (m) return 'foot' + m[2];
  return 'cloth';
}
const TORSO = new Set(['pelvis', 'abdomen', 'thorax', 'neck', 'head']);
function coreDefs(rig) {
  const L = rig.lengths, k = rig.P.upperArm / 0.3; // radii follow the build scale (giantP)
  const s = rig.P.hipHeight / 0.98;
  const out = [
    { seg: 'pelvis', a: ['hips', [-0.01, -0.08, -0.06]], b: ['hips', [-0.01, -0.08, 0.06]], r: 0.1 },
    { seg: 'abdomen', a: ['spine', [0, -0.02, 0]], b: ['chest', [0, 0.0, 0]], r: 0.1 },
    { seg: 'thorax', a: ['chest', [0, 0.08, -0.06]], b: ['chest', [0, 0.08, 0.06]], r: 0.105 },
    { seg: 'neck', a: ['neck', [0, 0.0, 0]], b: ['neck', [0, 0.09, 0]], r: 0.042 },
    { seg: 'head', a: ['head', [0.01, 0.07, 0]], b: ['head', [0.01, 0.12, 0]], r: 0.09 },
  ].map((c) => ({ ...c, a: [c.a[0], sv(c.a[1], s)], b: [c.b[0], sv(c.b[1], s)], r: c.r * s }));
  for (const S of ['R', 'L']) {
    out.push({ seg: 'upperArm' + S, a: ['upperArm' + S, [0, -0.05 * k, 0]], b: ['upperArm' + S, [0, -(L.upperArm - 0.045 * k), 0]], r: 0.045 * k });
    out.push({ seg: 'foreArm' + S, a: ['foreArm' + S, [0, -0.045 * k, 0]], b: ['foreArm' + S, [0, -(L.foreArm - 0.03 * k), 0]], r: 0.036 * k });
    out.push({ seg: 'thigh' + S, a: ['thigh' + S, [0, -0.07 * k, 0]], b: ['thigh' + S, [0, -(L.thigh - 0.07 * k), 0]], r: 0.07 * k });
    out.push({ seg: 'shin' + S, a: ['shin' + S, [0, -0.06 * k, 0]], b: ['shin' + S, [0, -(L.shin - 0.05 * k), 0]], r: 0.045 * k });
  }
  return out;
}
/** Is segment `s` (a vertex's) exempt from being tested against core `c`? */
function exempt(s, c) {
  if (s === c || s === 'cloth') return true;
  if (TORSO.has(s) && TORSO.has(c)) return true;
  const side = c.slice(-1);
  if (/^(upperArm|foreArm)/.test(c) && s === 'elbow' + side) return true;
  if (/^(thigh|shin)/.test(c) && s === 'knee' + side) return true;
  if (c === 'thigh' + side && s === 'pelvis') return true; // hip joint region is shared
  return false;
}

// ---- poses ---------------------------------------------------------------------------------------------------------
// Each: [name, focus bone, close-up distance, channels]. Right side unless the name says L. Base = 'neutral'.
const FEET = (k) => ({ footL: { pos: [0.3 * k, 0, -0.14 * k], rot: [0, 14, 0] }, footR: { pos: [-0.3 * k, 0, 0.17 * k], rot: [0, -45, 0] } });
function romPoses(k) {
  const P = (x) => x.map((v) => v * k);
  return [
    ['rest', 'chest', 2.6, {}],
    // ---- arm ----
    ['elbow090', 'foreArmR', 0.9, { bones: { upperArmR: [0, 0, 30], foreArmR: [0, 0, 90] } }],
    ['elbow150', 'foreArmR', 0.9, { bones: { upperArmR: [0, 0, 30], foreArmR: [0, 0, 150] } }],
    ['shFlex090', 'upperArmR', 1.0, { bones: { upperArmR: [0, 0, 90] } }],
    ['shFlex175', 'upperArmR', 1.0, { bones: { upperArmR: [0, 0, 175] } }],
    ['shAbd090', 'upperArmR', 1.0, { bones: { upperArmR: [-90, 0, 0] } }],
    ['shAbd175', 'upperArmR', 1.0, { bones: { upperArmR: [-175, 0, 0] } }],
    ['shAbd175f10', 'upperArmR', 1.0, { bones: { upperArmR: [-175, 0, 10] } }],
    ['shExt060', 'upperArmR', 1.0, { bones: { upperArmR: [0, 0, -60] } }],
    ['acrossChest', 'upperArmR', 1.0, { bones: { upperArmR: [60, 0, 90], foreArmR: [0, 0, 60] } }],
    ['hugChest', 'upperArmR', 1.0, { bones: { upperArmR: [45, 80, 75], foreArmR: [0, 0, 120] } }],
    ['wristTw+90', 'handR', 0.7, { bones: { upperArmR: [0, 0, 40], foreArmR: [0, 0, 90], handR: [0, 90, 0] } }],
    ['wristTw-90', 'handR', 0.7, { bones: { upperArmR: [0, 0, 40], foreArmR: [0, 0, 90], handR: [0, -90, 0] } }],
    ['foreTw+90', 'handR', 0.7, { bones: { upperArmR: [0, 0, 40], foreArmR: [0, 90, 90] } }],
    ['foreTw178', 'handR', 0.7, { bones: { upperArmR: [0, 0, 40], foreArmR: [0, 178, 90] } }],
    ['foreTw182', 'handR', 0.7, { bones: { upperArmR: [0, 0, 40], foreArmR: [0, 182, 90] } }],
    ['wristFlex+70', 'handR', 0.7, { bones: { upperArmR: [0, 0, 40], foreArmR: [0, 0, 90], handR: [70, 0, 0] } }],
    ['wristFlex-70', 'handR', 0.7, { bones: { upperArmR: [0, 0, 40], foreArmR: [0, 0, 90], handR: [-70, 0, 0] } }],
    ['uaRot+90', 'upperArmR', 1.0, { bones: { upperArmR: [0, 90, 30], foreArmR: [0, 0, 90] } }],
    ['uaRot-90', 'upperArmR', 1.0, { bones: { upperArmR: [0, -90, 30], foreArmR: [0, 0, 90] } }],
    ['handBehindHead', 'upperArmR', 1.0, { bones: { upperArmR: [-10, 0, 170], foreArmR: [0, 0, 140] } }],
    ['shrugReach', 'upperArmR', 1.0, { bones: { shoulderR: [-20, 10, 0], upperArmR: [-20, 0, 175] } }],
    ['armCombo', 'upperArmR', 1.0, { bones: { upperArmR: [60, 60, 120], foreArmR: [0, 90, 140], handR: [40, 0, 0] } }],
    // ---- leg ----
    ['knee090', 'shinR', 1.0, { bones: { shinR: [0, 0, -90] } }],
    ['knee155', 'shinR', 1.0, { bones: { shinR: [0, 0, -155] } }],
    ['highKnee', 'thighR', 1.1, { bones: { thighR: [0, 0, 125], shinR: [0, 0, -110], footR: [0, 0, -20] } }],
    ['kickStraight', 'thighR', 1.1, { bones: { thighR: [0, 0, 95], shinR: [0, 0, -5] } }],
    ['hipExt30', 'thighR', 1.1, { bones: { thighR: [0, 0, -30], shinR: [0, 0, -30] } }],
    ['hipAbd45', 'thighR', 1.1, { bones: { thighR: [-45, 0, 0] } }],
    ['hipRot+40', 'thighR', 1.1, { bones: { thighR: [0, 40, 90], shinR: [0, 0, -90] } }],
    ['hipRot-40', 'thighR', 1.1, { bones: { thighR: [0, -40, 90], shinR: [0, 0, -90] } }],
    ['ankle+30', 'footR', 0.7, { bones: { shinR: [0, 0, -40], footR: [0, 0, 30] } }],
    ['ankle-50', 'footR', 0.7, { bones: { footR: [0, 0, -50] } }],
    ['squatDeep', 'hips', 1.6, { hips: { pos: P([-0.17, -0.54, 0]) }, bones: { spine: [0, 0, -18], chest: [0, 0, -14], neck: [0, 0, 12], head: [0, 0, 14], upperArmR: [-10, 0, 70], upperArmL: [-10, 0, 70] },
      ik: { footR: { pos: P([0, 0, 0.17]), rot: [0, -12, 0] }, footL: { pos: P([0, 0, -0.17]), rot: [0, 12, 0] } } }],
    ['sideLunge', 'hips', 1.6, { hips: { pos: P([-0.05, -0.34, 0.24]), rot: [-12, 0, 0] }, bones: { spine: [6, 0, -10], chest: [4, 0, -8] },
      ik: { footR: { pos: P([0.04, 0, 0.6]), rot: [0, -30, 0] }, footL: { pos: P([0, 0, -0.24]), rot: [0, 10, 0] } } }],
    ['frontLunge', 'hips', 1.6, { hips: { pos: P([0.08, -0.4, 0]) }, bones: { spine: [0, 0, -6] },
      ik: { footL: { pos: P([0.55, 0, -0.12]), rot: [0, 10, 0] }, footR: { pos: P([-0.62, 0.08, 0.14]), rot: [0, -10, -40] } } }],
    // ---- torso ----
    ['twist+60', 'chest', 1.4, { bones: { spine: [0, 30, 0], chest: [0, 30, 0] } }],
    ['twist-60', 'chest', 1.4, { bones: { spine: [0, -30, 0], chest: [0, -30, 0] } }],
    ['bend+30', 'chest', 1.4, { bones: { spine: [15, 0, 0], chest: [15, 0, 0] } }],
    ['bend-30', 'chest', 1.4, { bones: { spine: [-15, 0, 0], chest: [-15, 0, 0] } }],
    ['fwd60', 'chest', 1.4, { bones: { spine: [0, 0, -30], chest: [0, 0, -30] } }],
    ['arch30', 'chest', 1.4, { bones: { spine: [0, 0, 15], chest: [0, 0, 15] } }],
    ['twistBendFwd', 'chest', 1.4, { bones: { spine: [10, 30, -15], chest: [10, 30, -15] } }],
    // ---- neck ----
    ['neckYaw+70', 'head', 0.9, { bones: { neck: [0, 30, 0], head: [0, 40, 0] } }],
    ['neckYaw-70', 'head', 0.9, { bones: { neck: [0, -30, 0], head: [0, -40, 0] } }],
    ['neckDown60', 'head', 0.9, { bones: { neck: [0, 0, -30], head: [0, 0, -30] } }],
    ['neckUp55', 'head', 0.9, { bones: { neck: [0, 0, 25], head: [0, 0, 30] } }],
    ['neckTilt+35', 'head', 0.9, { bones: { neck: [17, 0, 0], head: [18, 0, 0] } }],
    ['neckYawDown', 'head', 0.9, { bones: { neck: [0, 30, -20], head: [0, 40, -25] } }],
    // ---- greatsword (IK, two-handed grip) ----
    ['overheadWindup', 'chest', 1.7, { hips: { pos: P([-0.1, -0.1, 0]), rot: [0, -12, 0] }, bones: { spine: [0, -4, 12], chest: [0, -4, 16], neck: [0, 4, -10], head: [0, 6, -14] },
      ik: { handR: { pos: P([-0.1, 1.92, 0.04]), aim: [-0.45, -0.89, 0.05], up: [0.89, -0.45, 0] }, ...FEET(k) }, grip: 1, curl: [1, 1] }],
    ['overheadHigh', 'chest', 1.7, { hips: { pos: P([-0.08, -0.08, 0]), rot: [0, -12, 0] }, bones: { spine: [0, -4, 10], chest: [0, -4, 12] },
      ik: { handR: { pos: P([0.05, 2.02, 0.03]), aim: [-0.2, 0.98, 0.02], up: [-0.98, -0.2, 0] }, ...FEET(k) }, grip: 1, curl: [1, 1] }],
    ['followLowBehindL', 'chest', 1.7, { hips: { pos: P([0.05, -0.16, -0.02]), rot: [-4, 48, -4] }, bones: { spine: [-4, 18, -16], chest: [-4, 18, -12], neck: [0, -16, 6], head: [0, -20, 8] },
      ik: { handR: { pos: P([-0.12, 0.78, -0.32]), aim: [-0.6, -0.55, -0.58], up: [0.6, -0.1, -0.79] }, footL: { pos: P([0.45, 0, -0.15]), rot: [0, 10, 0] }, footR: { pos: P([-0.3, 0, 0.17]), rot: [0, -30, 0] } }, grip: 1, curl: [1, 1] }],
    ['followLowBehindR', 'chest', 1.7, { hips: { pos: P([-0.02, -0.14, 0.02]), rot: [3, -55, 3] }, bones: { spine: [3, -18, -14], chest: [3, -18, -10], neck: [0, 18, 4], head: [0, 22, 6] },
      ik: { handR: { pos: P([-0.25, 0.7, 0.36]), aim: [-0.55, -0.55, 0.62], up: [-0.6, 0.0, -0.8] }, ...FEET(k) }, grip: 1, curl: [1, 1] }],
    ['thrustHigh', 'chest', 1.7, { hips: { pos: P([0.1, -0.14, 0]), rot: [0, 10, 0] }, bones: { spine: [0, 6, -6] },
      ik: { handR: { pos: P([0.62, 1.55, 0.05]), aim: [0.9, 0.42, 0.0], up: [-0.42, 0.9, 0] }, ...FEET(k) }, grip: 1, curl: [1, 1] }],
  ];
}

// ---- lab -----------------------------------------------------------------------------------------------------------
createLab({
  view: { target: [0, 1.05, 0], dist: 3.2, yaw: 45, pitch: 6, fov: 40 },
  setup(ctx, lab) {
    ctx.scene.environment = studioEnv(ctx.renderer);
    lab.lights.key.intensity = 2.6;
    lab.lights.rim.intensity = 2.2;
    const built = {};
    let cur = null;
    const poseNames = {};

    function variant(key) {
      if (!built[key]) {
        const V = VARIANTS[key];
        const { design, rec } = recordingDesign(knight, V, key);
        const ch = createCharacter(ctx, design, { name: key });
        ch.root.scale.setScalar(V.rootScale);
        ch.breath.depth = 0;
        // scale = world size factor (camera distances); k = model-space factor for IK pose positions
        const C = { key, V, ch, rec, design, scale: V.h / 1.9, k: V.rootScale > 1 ? 1 : V.h / 1.9 };
        prepare(C);
        built[key] = C;
        // poses for this body type (IK positions scale with the body)
        poseNames[key] = [];
        for (const [name, focus, dist, def] of romPoses(C.k)) {
          const pn = 'audit.' + key + '.' + name;
          definePose(pn, def);
          poseNames[key].push({ name, pn, focus, dist });
        }
        invalidateClips();
      }
      for (const C of Object.values(built)) C.ch.setVisible(C.key === key);
      cur = built[key];
      if (window.__ED.audit && window.__ED.audit._slots) window.__ED.audit.show(window.__ED.audit._slots);
      return cur.key;
    }

    // per-character static data: slot ranges, segments per vertex, compiled shells, loft rings, rest snapshot
    function prepare(C) {
      const ch = C.ch, rig = ch.rig, names = rig.names;
      C.bindM = ch.skeleton.boneInverses.map((m) => m.clone().invert());
      C.slotGeo = {};
      for (const [slot, mesh] of Object.entries(ch.meshes)) {
        const g = mesh.geometry, n = g.attributes.position.count, I = g.attributes.skinIndex.array, W = g.attributes.skinWeight.array;
        const dom = new Int16Array(n);
        for (let v = 0; v < n; v++) { let b = 0, bw = -1; for (let k = 0; k < 4; k++) if (W[v * 4 + k] > bw) { bw = W[v * 4 + k]; b = I[v * 4 + k]; } dom[v] = b; }
        C.slotGeo[slot] = { g, n, dom, seg: Array.from(dom, (b) => segOf(names[b])) };
      }
      const pieces = C.rec.pieces;
      const suitDesign = pieces.filter((p) => p.slot === 'suit').reduce((m, p) => Math.max(m, p.start + p.count), 0);
      C.clothStart = suitDesign;
      C.lofts = pieces.filter((p) => p.kind === 'loft' && !/plume/.test(p.name));
      C.shells = pieces.filter((p) => p.slot === 'plate' && p.kind === 'rigid' && p.shell && p.shell.part !== 'rim').map((p) => ({ p, c: compileShell(p, C.V.K), bi: rig.index[p.bone] }));
      // bone-frame bounding spheres of the shells (rigid: constant)
      const geo = C.slotGeo.plate.g, Pa = geo.attributes.position.array;
      for (const s of C.shells) {
        const inv = ch.skeleton.boneInverses[s.bi];
        const v = new THREE.Vector3(), ctr = new THREE.Vector3();
        for (let i = 0; i < s.p.count; i++) ctr.add(v.fromArray(Pa, (s.p.start + i) * 3).applyMatrix4(inv));
        ctr.multiplyScalar(1 / s.p.count);
        let r = 0;
        for (let i = 0; i < s.p.count; i++) r = Math.max(r, v.fromArray(Pa, (s.p.start + i) * 3).applyMatrix4(inv).distanceTo(ctr));
        s.ctr = ctr.toArray(); s.r = r;
      }
      C.cores = coreDefs(rig).map((d) => ({ ...d, ia: rig.index[d.a[0]], ib: rig.index[d.b[0]] }));
      C.labels = pieces.map((p) => labelOf(p, pieces));
      C.bindSnap = bindSnapshot(C);
    }

    function labelOf(p, pieces) {
      const same = pieces.filter((q) => q.slot === p.slot && q.bone === p.bone && q.kind === p.kind);
      const i = same.indexOf(p);
      const sh = p.shell ? ` y${(p.shell.y0 ?? 0).toFixed(2)}..${(p.shell.y1 ?? -0.3).toFixed(2)}` : '';
      return `${p.slot}:${p.kind === 'loft' ? p.name : p.bone}#${i}${sh}${p.shell && p.shell.part === 'rim' ? ' rim' : ''}`;
    }

    // ---- snapshots (CPU skinning, model = root-local space) ----
    const tmpM = new THREE.Matrix4(), invRoot = new THREE.Matrix4();
    function snapshot(C) {
      const ch = C.ch, bones = ch.skeleton.bones, n = bones.length;
      ch.root.updateMatrixWorld(true);
      invRoot.copy(ch.root.matrixWorld).invert();
      const BM = new Float32Array(n * 16), SM = new Float32Array(n * 16);
      let nan = 0;
      for (let i = 0; i < n; i++) {
        tmpM.multiplyMatrices(invRoot, bones[i].matrixWorld);
        BM.set(tmpM.elements, i * 16);
        tmpM.multiply(ch.skeleton.boneInverses[i]);
        SM.set(tmpM.elements, i * 16);
        for (let k = 0; k < 16; k++) if (!Number.isFinite(BM[i * 16 + k])) nan++;
      }
      const pos = {}, nrm = {};
      for (const [slot, G] of Object.entries(C.slotGeo)) { const r = skin(G.g, SM); pos[slot] = r.p; nrm[slot] = r.n; }
      return { BM, SM, pos, nrm, nan };
    }
    function bindSnapshot(C) {
      const pos = {}, nrm = {};
      for (const [slot, G] of Object.entries(C.slotGeo)) { pos[slot] = G.g.attributes.position.array; nrm[slot] = G.g.attributes.normal.array; }
      const n = C.ch.skeleton.bones.length, BM = new Float32Array(n * 16);
      C.bindM.forEach((m, i) => BM.set(m.elements, i * 16));
      return { BM, pos, nrm };
    }
    function skin(g, SM) {
      const P = g.attributes.position.array, N = g.attributes.normal.array, I = g.attributes.skinIndex.array, W = g.attributes.skinWeight.array;
      const nv = P.length / 3, op = new Float32Array(nv * 3), on = new Float32Array(nv * 3);
      for (let v = 0; v < nv; v++) {
        const px = P[v * 3], py = P[v * 3 + 1], pz = P[v * 3 + 2], nx = N[v * 3], ny = N[v * 3 + 1], nz = N[v * 3 + 2];
        let x = 0, y = 0, z = 0, a = 0, b = 0, c = 0;
        for (let k = 0; k < 4; k++) {
          const w = W[v * 4 + k];
          if (!w) continue;
          const o = I[v * 4 + k] * 16;
          x += w * (SM[o] * px + SM[o + 4] * py + SM[o + 8] * pz + SM[o + 12]);
          y += w * (SM[o + 1] * px + SM[o + 5] * py + SM[o + 9] * pz + SM[o + 13]);
          z += w * (SM[o + 2] * px + SM[o + 6] * py + SM[o + 10] * pz + SM[o + 14]);
          a += w * (SM[o] * nx + SM[o + 4] * ny + SM[o + 8] * nz);
          b += w * (SM[o + 1] * nx + SM[o + 5] * ny + SM[o + 9] * nz);
          c += w * (SM[o + 2] * nx + SM[o + 6] * ny + SM[o + 10] * nz);
        }
        op[v * 3] = x; op[v * 3 + 1] = y; op[v * 3 + 2] = z;
        const l = Math.hypot(a, b, c) || 1;
        on[v * 3] = a / l; on[v * 3 + 1] = b / l; on[v * 3 + 2] = c / l;
      }
      return { p: op, n: on };
    }
    // model point -> bone frame (rigid inverse of BM)
    const bf = new Float32Array(3);
    function toBone(BM, bi, x, y, z) {
      const o = bi * 16;
      x -= BM[o + 12]; y -= BM[o + 13]; z -= BM[o + 14];
      bf[0] = BM[o] * x + BM[o + 1] * y + BM[o + 2] * z;
      bf[1] = BM[o + 4] * x + BM[o + 5] * y + BM[o + 6] * z;
      bf[2] = BM[o + 8] * x + BM[o + 9] * y + BM[o + 10] * z;
      return bf;
    }
    const bp = new Float32Array(3);
    function fromBone(BM, bi, x, y, z) {
      const o = bi * 16;
      bp[0] = BM[o] * x + BM[o + 4] * y + BM[o + 8] * z + BM[o + 12];
      bp[1] = BM[o + 1] * x + BM[o + 5] * y + BM[o + 9] * z + BM[o + 13];
      bp[2] = BM[o + 2] * x + BM[o + 6] * y + BM[o + 10] * z + BM[o + 14];
      return [bp[0], bp[1], bp[2]];
    }

    // ---- metric: loft rings ----
    function ringAreas(C, pos, piece, out) {
      const s = piece.spec, radial = (s.segs && s.segs[0]) || 16, rings = (s.segs && s.segs[1]) || 24, W = radial + 1;
      for (let j = 0; j <= rings; j++) {
        let cx = 0, cy = 0, cz = 0;
        for (let i = 0; i < radial; i++) { const v = (piece.start + j * W + i) * 3; cx += pos[v]; cy += pos[v + 1]; cz += pos[v + 2]; }
        cx /= radial; cy /= radial; cz /= radial;
        let ax = 0, ay = 0, az = 0;
        for (let i = 0; i < radial; i++) {
          const a = (piece.start + j * W + i) * 3, b = (piece.start + j * W + ((i + 1) % radial)) * 3;
          const x1 = pos[a] - cx, y1 = pos[a + 1] - cy, z1 = pos[a + 2] - cz, x2 = pos[b] - cx, y2 = pos[b + 1] - cy, z2 = pos[b + 2] - cz;
          ax += y1 * z2 - z1 * y2; ay += z1 * x2 - x1 * z2; az += x1 * y2 - y1 * x2;
        }
        out[j] = 0.5 * Math.hypot(ax, ay, az);
      }
      return rings + 1;
    }
    function ringLabel(C, piece, j) {
      const s = piece.spec, W = ((s.segs && s.segs[0]) || 16) + 1, G = C.slotGeo.suit.g, I = G.attributes.skinIndex.array, Wt = G.attributes.skinWeight.array;
      const v = piece.start + j * W, parts = [];
      for (let k = 0; k < 4; k++) if (Wt[v * 4 + k] > 0.05) parts.push(C.ch.rig.names[I[v * 4 + k]] + ':' + Wt[v * 4 + k].toFixed(2));
      return parts.join(' ');
    }

    // ---- metric: distance to the bone polyline near a joint ----
    const JOINTS = {
      elbowR: ['upperArmR', 'foreArmR', 'handR'], elbowL: ['upperArmL', 'foreArmL', 'handL'],
      shoulderR: ['shoulderR', 'upperArmR', 'foreArmR'], shoulderL: ['shoulderL', 'upperArmL', 'foreArmL'],
      wristR: ['foreArmR', 'handR', 'fingersR'], wristL: ['foreArmL', 'handL', 'fingersL'],
      kneeR: ['thighR', 'shinR', 'footR'], kneeL: ['thighL', 'shinL', 'footL'],
      hipR: ['hips', 'thighR', 'shinR'], hipL: ['hips', 'thighL', 'shinL'],
    };
    const segDist = (px, py, pz, a, b) => {
      const ex = b[0] - a[0], ey = b[1] - a[1], ez = b[2] - a[2], ee = ex * ex + ey * ey + ez * ez;
      let t = ee > 1e-12 ? ((px - a[0]) * ex + (py - a[1]) * ey + (pz - a[2]) * ez) / ee : 0;
      t = t < 0 ? 0 : t > 1 ? 1 : t;
      return Math.hypot(px - a[0] - ex * t, py - a[1] - ey * t, pz - a[2] - ez * t);
    };
    function axisRatio(C, snap, joint) {
      const [b0, b1, b2] = JOINTS[joint].map((n) => C.ch.rig.index[n]);
      const bpos = (S, i) => [S.BM[i * 16 + 12], S.BM[i * 16 + 13], S.BM[i * 16 + 14]];
      const B = C.bindSnap, A0 = bpos(B, b0), A1 = bpos(B, b1), A2 = bpos(B, b2), P0 = bpos(snap, b0), P1 = bpos(snap, b1), P2 = bpos(snap, b2);
      const G = C.slotGeo.suit, bp0 = B.pos.suit, pp = snap.pos.suit;
      const radius = Math.hypot(A1[0] - A0[0], A1[1] - A0[1], A1[2] - A0[2]) * 0.45;
      let min = Infinity, cnt = 0;
      const ratios = [];
      for (let v = 0; v < C.clothStart; v++) {
        const x = bp0[v * 3], y = bp0[v * 3 + 1], z = bp0[v * 3 + 2];
        if (Math.hypot(x - A1[0], y - A1[1], z - A1[2]) > radius) continue;
        const seg = G.seg[v];
        if (seg === 'head' || seg === 'cloth') continue;
        const d0 = Math.min(segDist(x, y, z, A0, A1), segDist(x, y, z, A1, A2));
        if (d0 < 0.02 * C.V.K) continue;
        const d1 = Math.min(segDist(pp[v * 3], pp[v * 3 + 1], pp[v * 3 + 2], P0, P1), segDist(pp[v * 3], pp[v * 3 + 1], pp[v * 3 + 2], P1, P2));
        const r = d1 / d0;
        ratios.push(r);
        if (r < min) min = r;
        cnt++;
      }
      ratios.sort((a, b) => a - b);
      return { min: +min.toFixed(3), p05: ratios.length ? +ratios[Math.floor(ratios.length * 0.05)].toFixed(3) : null, n: cnt };
    }

    // ---- metric: folded triangles ----
    function flips(C, snap) {
      const g = C.slotGeo.suit.g, idx = g.index.array, P = snap.pos.suit, N = snap.nrm.suit, PB = C.bindSnap.pos.suit, NB = C.bindSnap.nrm.suit;
      const by = {};
      let count = 0, collapsed = 0;
      const tri = (pp, a, b, c, out) => {
        const ux = pp[b * 3] - pp[a * 3], uy = pp[b * 3 + 1] - pp[a * 3 + 1], uz = pp[b * 3 + 2] - pp[a * 3 + 2];
        const vx = pp[c * 3] - pp[a * 3], vy = pp[c * 3 + 1] - pp[a * 3 + 1], vz = pp[c * 3 + 2] - pp[a * 3 + 2];
        out[0] = uy * vz - uz * vy; out[1] = uz * vx - ux * vz; out[2] = ux * vy - uy * vx;
        return Math.hypot(out[0], out[1], out[2]);
      };
      const f0 = [0, 0, 0], f1 = [0, 0, 0];
      for (let t = 0; t < idx.length; t += 3) {
        const a = idx[t], b = idx[t + 1], c = idx[t + 2];
        if (a >= C.clothStart) continue;
        const A0 = tri(PB, a, b, c, f0);
        if (A0 < 1e-9) continue;
        const nb = (f0[0] * (NB[a * 3] + NB[b * 3] + NB[c * 3]) + f0[1] * (NB[a * 3 + 1] + NB[b * 3 + 1] + NB[c * 3 + 1]) + f0[2] * (NB[a * 3 + 2] + NB[b * 3 + 2] + NB[c * 3 + 2])) / A0 / 3;
        if (nb < 0.3) continue;
        const A1 = tri(P, a, b, c, f1);
        const np = A1 > 1e-12 ? (f1[0] * (N[a * 3] + N[b * 3] + N[c * 3]) + f1[1] * (N[a * 3 + 1] + N[b * 3 + 1] + N[c * 3 + 1]) + f1[2] * (N[a * 3 + 2] + N[b * 3 + 2] + N[c * 3 + 2])) / A1 / 3 : 0;
        if (np < 0) { count++; const s = C.slotGeo.suit.seg[a] + '/' + C.ch.rig.names[C.slotGeo.suit.dom[a]]; by[s] = (by[s] || 0) + 1; }
        if (A1 / A0 < 0.1) collapsed++;
      }
      return { count, collapsed, by };
    }

    // ---- metric: side flips against analytic plate solids ----
    const ev = new Float32Array(3), ev0 = new Float32Array(3);
    const TOL = 0.002;
    const cls = (e) => (e[1] > TOL ? 1 : e[2] < -TOL ? -1 : 0);
    function crossTest(C, snap, rest, srcSlot, from, to, segFilter, res, kindLabel) {
      const P = snap.pos[srcSlot], PR = rest.pos[srcSlot], G = C.slotGeo[srcSlot];
      for (const s of C.shells) {
        const o = s.bi * 16, BM = snap.BM;
        // shell bounding sphere in model space
        const cx = BM[o] * s.ctr[0] + BM[o + 4] * s.ctr[1] + BM[o + 8] * s.ctr[2] + BM[o + 12];
        const cy = BM[o + 1] * s.ctr[0] + BM[o + 5] * s.ctr[1] + BM[o + 9] * s.ctr[2] + BM[o + 13];
        const cz = BM[o + 2] * s.ctr[0] + BM[o + 6] * s.ctr[1] + BM[o + 10] * s.ctr[2] + BM[o + 14];
        const r2 = (s.r + 0.01) ** 2;
        let n = 0, depth = 0, worst = -1;
        for (let v = from; v < to; v++) {
          if (segFilter && !segFilter(v, s)) continue;
          const x = P[v * 3], y = P[v * 3 + 1], z = P[v * 3 + 2];
          if ((x - cx) ** 2 + (y - cy) ** 2 + (z - cz) ** 2 > r2) continue;
          const b = toBone(snap.BM, s.bi, x, y, z);
          shellEval(s.c, b[0], b[1], b[2], ev);
          if (!ev[0]) continue;
          const c1 = cls(ev);
          if (!c1) continue;
          const b0 = toBone(rest.BM, s.bi, PR[v * 3], PR[v * 3 + 1], PR[v * 3 + 2]);
          shellEval(s.c, b0[0], b0[1], b0[2], ev0);
          if (!ev0[0]) continue;
          const c0 = cls(ev0);
          if (c0 * c1 !== -1) continue;
          const d = c1 > 0 ? ev[1] : -ev[2];
          n++;
          if (d > depth) { depth = d; worst = v; }
        }
        if (n) {
          const srcLabel = kindLabel(worst);
          res.push({ a: srcLabel, b: C.labels[s.p.id], n, depth: +depth.toFixed(4) });
        }
      }
    }
    function pieceOfVertex(C, slot, v) {
      for (const p of C.rec.pieces) if (p.slot === slot && v >= p.start && v < p.start + p.count) return p;
      return null;
    }
    function crossings(C, snap, rest) {
      const res = [];
      // suit (design lofts, not the plume) through plates
      crossTest(C, snap, rest, 'suit', 0, C.clothStart, (v) => C.slotGeo.suit.seg[v] !== 'head', res, (v) => {
        const p = pieceOfVertex(C, 'suit', v); return 'SUIT ' + (p ? p.name : '?') + ' @' + C.ch.rig.names[C.slotGeo.suit.dom[v]];
      });
      // plates (and blade) against plates on other bones
      for (const slot of ['plate', 'blade']) {
        if (!C.slotGeo[slot]) continue;
        const dom = C.slotGeo[slot].dom;
        crossTest(C, snap, rest, slot, 0, C.slotGeo[slot].n, (v, s) => dom[v] !== s.bi, res, (v) => {
          const p = pieceOfVertex(C, slot, v); return p ? C.labels[p.id] : slot + '?';
        });
      }
      // merge rows with the same a/b label prefix
      const m = new Map();
      for (const r of res) {
        const k = r.a + ' -> ' + r.b;
        const e = m.get(k);
        if (!e) m.set(k, { ...r }); else { e.n += r.n; e.depth = Math.max(e.depth, r.depth); }
      }
      return [...m.values()].sort((a, b) => b.depth - a.depth);
    }

    // ---- metric: body cores (segment into another segment) ----
    function capsuleDepth(px, py, pz, A, B, r) { return r - segDist(px, py, pz, A, B); }
    function coreEnds(C, snap) {
      return C.cores.map((c) => ({ seg: c.seg, r: c.r, A: fromBone(snap.BM, c.ia, ...c.a[1]), B: fromBone(snap.BM, c.ib, ...c.b[1]) }));
    }
    function coreTest(C, snap, rest) {
      const ce = coreEnds(C, snap), cr = coreEnds(C, rest);
      const agg = new Map();
      for (const slot of Object.keys(C.slotGeo)) {
        const G = C.slotGeo[slot], P = snap.pos[slot], PR = rest.pos[slot];
        const lim = slot === 'suit' ? C.clothStart : G.n;
        for (let v = 0; v < lim; v++) {
          const sg = G.seg[v];
          const x = P[v * 3], y = P[v * 3 + 1], z = P[v * 3 + 2];
          for (let k = 0; k < ce.length; k++) {
            const c = ce[k];
            if (exempt(sg, c.seg)) continue;
            const d1 = capsuleDepth(x, y, z, c.A, c.B, c.r);
            if (d1 <= 0.005 * C.V.K) continue;
            const d0 = capsuleDepth(PR[v * 3], PR[v * 3 + 1], PR[v * 3 + 2], cr[k].A, cr[k].B, cr[k].r);
            const dd = d1 - Math.max(0, d0);
            if (dd <= 0.005 * C.V.K) continue;
            const key = slot + ':' + sg + ' -> core ' + c.seg;
            const e = agg.get(key) || { a: slot + ':' + sg, core: c.seg, n: 0, depth: 0 };
            e.n++; e.depth = Math.max(e.depth, +dd.toFixed(4));
            agg.set(key, e);
          }
        }
      }
      return [...agg.values()].sort((a, b) => b.depth - a.depth);
    }

    // ---- metric: cloth inside plates / body ----
    function clothTest(C, snap) {
      const G = C.slotGeo.suit, P = snap.pos.suit, ce = coreEnds(C, snap);
      let inPlate = 0, inPlateMax = 0, inBody = 0, inBodyMax = 0;
      const where = {};
      for (let v = C.clothStart; v < G.n; v++) {
        const x = P[v * 3], y = P[v * 3 + 1], z = P[v * 3 + 2];
        for (const c of ce) {
          const d = capsuleDepth(x, y, z, c.A, c.B, c.r);
          if (d > 0.005 * C.V.K) { inBody++; inBodyMax = Math.max(inBodyMax, d); where['core ' + c.seg] = (where['core ' + c.seg] || 0) + 1; break; }
        }
        for (const s of C.shells) {
          const b = toBone(snap.BM, s.bi, x, y, z);
          if (Math.hypot(b[0] - s.ctr[0], b[1] - s.ctr[1], b[2] - s.ctr[2]) > s.r + 0.01) continue;
          shellEval(s.c, b[0], b[1], b[2], ev);
          if (ev[0] && ev[2] < -0.004 * C.V.K) {
            inPlate++; inPlateMax = Math.max(inPlateMax, -ev[2]);
            const l = C.labels[s.p.id]; where[l] = (where[l] || 0) + 1;
            break;
          }
        }
      }
      return { inPlate, inPlateMax: +inPlateMax.toFixed(4), inBody, inBodyMax: +inBodyMax.toFixed(4), total: G.n - C.clothStart, where };
    }

    // ---- GPU see-through holes ----
    const HW = 1280, HH = 720;
    const rt = new THREE.WebGLRenderTarget(HW, HH);
    const bufF = new Uint8Array(HW * HH * 4), bufD = new Uint8Array(HW * HH * 4);
    const maskF = new THREE.MeshBasicMaterial({ color: 0xffffff, side: THREE.FrontSide });
    const maskD = new THREE.MeshBasicMaterial({ color: 0xffffff, side: THREE.DoubleSide });
    const overlay = document.createElement('canvas');
    overlay.width = HW; overlay.height = HH;
    overlay.style.cssText = 'position:fixed;inset:0;width:100%;height:100%;pointer-events:none;z-index:20;image-rendering:pixelated';
    document.body.appendChild(overlay);
    const label = document.createElement('div');
    label.style.cssText = 'position:fixed;left:8px;top:8px;z-index:21;font:bold 15px/1.35 monospace;color:#fff;background:rgba(0,0,0,.6);padding:4px 8px;border-radius:4px;white-space:pre;pointer-events:none';
    document.body.appendChild(label);
    function holes(drawOverlay = true) {
      const r = ctx.renderer, scene = ctx.scene;
      const hidden = [];
      const roots = new Set(Object.values(built).map((C) => C.ch.root));
      for (const o of scene.children) if (!roots.has(o) && o.visible && !o.isLight) { hidden.push(o); o.visible = false; }
      const bg = scene.background, fog = scene.fog, cc = r.getClearColor(new THREE.Color()), ca = r.getClearAlpha(), au = r.shadowMap.autoUpdate;
      scene.background = null; scene.fog = null; r.shadowMap.autoUpdate = false;
      const prevRT = r.getRenderTarget();
      r.setRenderTarget(rt); r.setClearColor(0x000000, 1);
      scene.overrideMaterial = maskF; r.clear(); r.render(scene, ctx.camera); r.readRenderTargetPixels(rt, 0, 0, HW, HH, bufF);
      scene.overrideMaterial = maskD; r.clear(); r.render(scene, ctx.camera); r.readRenderTargetPixels(rt, 0, 0, HW, HH, bufD);
      scene.overrideMaterial = null;
      r.setRenderTarget(prevRT); r.setClearColor(cc, ca); r.shadowMap.autoUpdate = au;
      scene.background = bg; scene.fog = fog;
      for (const o of hidden) o.visible = true;
      const hole = new Uint8Array(HW * HH);
      let raw = 0, sil = 0;
      for (let i = 0; i < HW * HH; i++) { if (bufD[i * 4] > 128) sil++; if (bufD[i * 4] > 128 && bufF[i * 4] < 128) { hole[i] = 1; raw++; } }
      let clustered = 0;
      for (let y = 1; y < HH - 1; y++) for (let x = 1; x < HW - 1; x++) {
        const i = y * HW + x;
        if (!hole[i]) continue;
        if (hole[i - 1] + hole[i + 1] + hole[i - HW] + hole[i + HW] >= 2) clustered++;
      }
      const g = overlay.getContext('2d');
      g.clearRect(0, 0, HW, HH);
      if (drawOverlay && raw) {
        const img = g.createImageData(HW, HH);
        for (let y = 0; y < HH; y++) for (let x = 0; x < HW; x++) {
          const i = (HH - 1 - y) * HW + x; // GL rows are bottom-up
          if (!hole[i]) continue;
          const o = (y * HW + x) * 4;
          img.data[o] = 255; img.data[o + 1] = 0; img.data[o + 2] = 255; img.data[o + 3] = 255;
        }
        g.putImageData(img, 0, 0);
      }
      return { raw, clustered, silhouette: sil };
    }
    function clearOverlay() { overlay.getContext('2d').clearRect(0, 0, HW, HH); }

    // ---- pose control ----
    function settle(C, frames = 40) { C.ch.teleport(); for (let i = 0; i < frames; i++) C.ch.update(1 / 60, 1 / 60); }
    function pose(name, key = cur.key) {
      variant(key);
      if (name.includes('@')) { // 'clip@time': run the clip from 0 to time at 60 fps (cloth evolves naturally)
        const [clip, ts] = name.split('@'), t = Number(ts);
        cur.ch.play(clip, { fade: 0, restart: true });
        cur.ch.teleport();
        for (let tt = 0; tt <= t + 1e-6; tt += 1 / 60) { cur.ch.setClipTime(tt); cur.ch.update(1 / 60, 1 / 60); }
        cur.ch.setClipTime(t); cur.ch.update(0, 0);
        cur.poseName = name;
        return { name, focus: 'chest', dist: 1.6 };
      }
      const e = poseNames[key].find((p) => p.name === name);
      if (!e) throw new Error('no pose ' + name);
      cur.ch.play(e.pn, { fade: 0, restart: true });
      settle(cur);
      cur.poseName = name;
      return e;
    }
    function restOf(C) {
      if (!C.rest) {
        const keep = C.poseName;
        pose('rest', C.key);
        C.rest = snapshot(C);
        C.restRings = {};
        for (const p of C.lofts) { const a = new Float32Array(64); ringAreas(C, C.rest.pos.suit, p, a); C.restRings[p.id] = a; }
        C.bindRings = {};
        for (const p of C.lofts) { const a = new Float32Array(64); ringAreas(C, C.bindSnap.pos.suit, p, a); C.bindRings[p.id] = a; }
        if (keep && keep !== 'rest') pose(keep, C.key);
      }
      return C.rest;
    }
    function ringReport(C, snap) {
      const out = {};
      const a = new Float32Array(64);
      for (const p of C.lofts) {
        const n = ringAreas(C, snap.pos.suit, p, a), b = C.bindRings[p.id];
        let mn = Infinity, mj = 0, mx = 0, xj = 0;
        for (let j = 1; j < n - 1; j++) { const r = a[j] / b[j]; if (r < mn) { mn = r; mj = j; } if (r > mx) { mx = r; xj = j; } }
        out[p.name] = { min: +mn.toFixed(3), at: ringLabel(C, p, mj), max: +mx.toFixed(3), maxAt: ringLabel(C, p, xj) };
      }
      return out;
    }
    function measure(opts = {}) {
      const C = cur, rest = restOf(C);
      const snap = snapshot(C);
      const res = { variant: C.key, pose: C.poseName, nan: snap.nan };
      res.ring = ringReport(C, snap);
      res.axis = {};
      for (const j of opts.joints || Object.keys(JOINTS)) res.axis[j] = axisRatio(C, snap, j);
      res.flips = flips(C, snap);
      res.cross = crossings(C, snap, rest).slice(0, opts.top || 12);
      res.cores = coreTest(C, snap, rest).slice(0, opts.top || 12);
      res.cloth = clothTest(C, snap);
      const sk = C.ch.sockets, g = C.ch.weapon && C.ch.weapon.grips.grip;
      if (g && C.ch.clip && /overhead|follow|thrust/.test(C.poseName || '')) {
        const gp = new THREE.Vector3(...g.pos).applyMatrix4(C.ch.weapon.bone.matrixWorld);
        const hl = sk.handL.getWorldPosition(new THREE.Vector3());
        res.gripErr = +(gp.distanceTo(hl) / (C.V.rootScale)).toFixed(4);
      }
      return res;
    }
    function rom(key, names, opts = {}) {
      variant(key);
      const list = names || poseNames[key].map((p) => p.name);
      const out = [];
      for (const n of list) {
        const e = pose(n, key);
        const m = measure(opts);
        if (opts.holes) {
          m.holes = {};
          for (const view of opts.views || ['front', '34', 'side']) { look('spine', view, opts.holeDist || 2.6); m.holes[view] = holes(false); }
        }
        if (opts.compact) out.push(compact(m)); else out.push(m);
      }
      return out;
    }
    function compact(m) {
      const ring = Object.entries(m.ring).map(([k, v]) => `${k} ${v.min}@${v.at.split(' ')[0]}`).join(' | ');
      const ax = Object.entries(m.axis).filter(([, v]) => v.n).map(([k, v]) => `${k}:${v.min}/${v.p05}`).join(' ');
      return {
        pose: m.pose, nan: m.nan, ring, axis: ax, flips: m.flips.count, flipBy: m.flips.by, collapsed: m.flips.collapsed,
        cross: m.cross.slice(0, 6).map((r) => `${r.a} -> ${r.b} n${r.n} d${(r.depth * 1000).toFixed(0)}mm`),
        cores: m.cores.slice(0, 5).map((r) => `${r.a} -> ${r.core} n${r.n} d${(r.depth * 1000).toFixed(0)}mm`),
        cloth: `plate ${m.cloth.inPlate}(${(m.cloth.inPlateMax * 1000).toFixed(0)}mm) body ${m.cloth.inBody}(${(m.cloth.inBodyMax * 1000).toFixed(0)}mm)`,
        holes: m.holes ? Object.entries(m.holes).map(([k, v]) => `${k}:${v.clustered}`).join(' ') : undefined,
        gripErr: m.gripErr,
      };
    }

    // ---- camera ----
    const YAW = { front: 90, '34': 45, side: 0, back34: -45, back: -90, frontL: 135 };
    function look(focus, view = '34', dist = 1.2, pitch = 6) {
      const b = cur.ch.bones[focus];
      // focus 'w<x>_<y>_<z>' = fixed world point (model metres, scaled with the body)
      const w = typeof focus === 'string' && focus[0] === 'w' ? focus.slice(1).split('_').map(Number) : null;
      const p = w ? new THREE.Vector3(...w).multiplyScalar(cur.scale) : b ? b.getWorldPosition(new THREE.Vector3()) : cur.ch.root.getWorldPosition(new THREE.Vector3());
      lab.view({ target: [p.x, p.y, p.z], dist: dist * cur.scale, yaw: YAW[view] ?? view, pitch });
    }

    // ---- capture queue: items [variant, pose, focus, view, dist, holes] ----
    let queue = [];
    function step() {
      const it = queue.shift();
      if (!it) return null;
      const [key, name, focus, view, dist, withHoles] = it;
      const e = pose(name, key);
      look(focus || e.focus, view, dist || e.dist);
      let txt = `${key}  ${name}  [${view}]`;
      clearOverlay();
      if (withHoles) { const h = holes(true); txt += `  holes ${h.clustered}px`; }
      label.textContent = txt;
      return txt;
    }

    // ---- helper-bone / IK continuity scan over a clip ----
    const twist = (q) => { let w = q.w, p = q.y; if (w < 0) { w = -w; p = -p; } return 2 * Math.atan2(p, w) / D2R; };
    const ang = (q) => 2 * Math.acos(Math.min(1, Math.abs(q.w))) / D2R;
    function twistScan(clip, o = {}) {
      const C = cur, ch = C.ch, B = ch.bones, dt = o.dt || 1 / 60;
      ch.play(clip, { fade: 0, restart: true });
      settle(C, 2);
      const dur = ch.clipDuration, rows = [];
      const prev = {};
      const jumps = { utR: 0, deltR: 0, htR: 0, elbowR: 0, utL: 0, deltL: 0, htL: 0, elbowL: 0 };
      const max = { utR: 0, htR: 0, utL: 0, htL: 0, gripErr: 0 };
      const e = new THREE.Vector3();
      for (let t = 0; t <= dur + 1e-6; t += dt) {
        ch.setClipTime(t);
        ch.update(dt, dt);
        const r = { t: +t.toFixed(3) };
        for (const s of ['R', 'L']) {
          r['ut' + s] = twist(B['upperArm' + s].quaternion);
          r['twH' + s] = twist(B['upperArmTwist' + s].quaternion);
          r['delt' + s] = ang(B['deltoid' + s].quaternion);
          r['ht' + s] = twist(B['hand' + s].quaternion);
          r['fat' + s] = twist(B['foreArmTwist' + s].quaternion);
          B['foreArm' + s].getWorldPosition(e);
          r['el' + s] = e.toArray().map((x) => x / C.V.rootScale);
        }
        const g = ch.weapon && ch.weapon.grips[(o.gripAt || 'grip')];
        if (g) {
          const gp = new THREE.Vector3(...g.pos).applyMatrix4(ch.weapon.bone.matrixWorld);
          r.gripErr = gp.distanceTo(ch.sockets.handL.getWorldPosition(new THREE.Vector3())) / C.V.rootScale;
          max.gripErr = Math.max(max.gripErr, r.gripErr);
        }
        if (prev.t !== undefined) {
          for (const s of ['R', 'L']) {
            const wrap = (a) => Math.abs(((a + 540) % 360) - 180);
            jumps['ut' + s] = Math.max(jumps['ut' + s], wrap(r['ut' + s] - prev['ut' + s]));
            jumps['delt' + s] = Math.max(jumps['delt' + s], Math.abs(r['delt' + s] - prev['delt' + s]));
            jumps['ht' + s] = Math.max(jumps['ht' + s], wrap(r['ht' + s] - prev['ht' + s]));
            const d = Math.hypot(...r['el' + s].map((x, i) => x - prev['el' + s][i]));
            jumps['elbow' + s] = Math.max(jumps['elbow' + s], d);
          }
        }
        for (const s of ['R', 'L']) { max['ut' + s] = Math.max(max['ut' + s], Math.abs(r['ut' + s])); max['ht' + s] = Math.max(max['ht' + s], Math.abs(r['ht' + s])); }
        rows.push(r);
        Object.assign(prev, r);
      }
      const round = (o2) => Object.fromEntries(Object.entries(o2).map(([k, v]) => [k, +v.toFixed(3)]));
      return { clip, frames: rows.length, maxPerFrameJump: round(jumps), maxAbs: round(max), rows: o.rows ? rows.map((r) => ({ t: r.t, utR: +r.utR.toFixed(1), deltR: +r.deltR.toFixed(1), htR: +r.htR.toFixed(1), fatR: +r.fatR.toFixed(1), utL: +r.utL.toFixed(1), htL: +r.htL.toFixed(1), grip: r.gripErr !== undefined ? +r.gripErr.toFixed(3) : null })) : undefined };
    }

    /** Sweep one FK channel and report helper continuity: upper-arm twist extraction vs swing. */
    function helperSweep(bone = 'upperArmR', base = [0, 0, 10], axis = 0, from = 90, to = 185, stepDeg = 5) {
      const C = cur, out = [];
      for (let a = from; a <= to + 1e-6; a += stepDeg) {
        const r = base.slice(); r[axis] = -a;
        definePose('audit.sweep', { bones: { [bone]: r } });
        invalidateClips();
        C.ch.play('audit.sweep', { fade: 0, restart: true });
        settle(C, 2);
        const s = bone.slice(-1);
        out.push({ deg: a, ut: +twist(C.ch.bones['upperArm' + s].quaternion).toFixed(1), twistHelper: +twist(C.ch.bones['upperArmTwist' + s].quaternion).toFixed(1), deltoid: +ang(C.ch.bones['deltoid' + s].quaternion).toFixed(1) });
      }
      return out;
    }

    function cpu(clip = 'demo.combo3', frames = 240) {
      const ch = cur.ch;
      ch.play(clip, { fade: 0, restart: true, loop: true });
      for (let i = 0; i < 30; i++) ch.update(1 / 60, 1 / 60);
      const ts = [];
      for (let i = 0; i < frames; i++) { const t0 = performance.now(); ch.update(1 / 60, 1 / 60); ts.push(performance.now() - t0); }
      ts.sort((a, b) => a - b);
      return { clip, mean: +(ts.reduce((a, b) => a + b, 0) / ts.length).toFixed(3), p50: +ts[ts.length >> 1].toFixed(3), p95: +ts[Math.floor(ts.length * 0.95)].toFixed(3), max: +ts[ts.length - 1].toFixed(3) };
    }

    /** README axis table: +30 deg on one axis of a bone from the zero pose -> direction the bone's tip moves (fighter frame). */
    function axes(list) {
      const C = cur, ch = C.ch;
      const zero = { spine: [0, 0, 0], chest: [0, 0, 0], neck: [0, 0, 0], head: [0, 0, 0], shoulderR: [0, 0, 0], shoulderL: [0, 0, 0], upperArmR: [0, 0, 0], upperArmL: [0, 0, 0], foreArmR: [0, 0, 0], foreArmL: [0, 0, 0], handR: [0, 0, 0], handL: [0, 0, 0], thighR: [0, 0, 0], thighL: [0, 0, 0], shinR: [0, 0, 0], shinL: [0, 0, 0], footR: [0, 0, 0], footL: [0, 0, 0] };
      const tips = { upperArmR: 'foreArmR', upperArmL: 'foreArmL', foreArmR: 'handR', foreArmL: 'handL', thighR: 'shinR', thighL: 'shinL', shinR: 'footR', shinL: 'footL', footR: 'toeR', footL: 'toeL', handR: 'fingersR', handL: 'fingersL', shoulderR: 'upperArmR', shoulderL: 'upperArmL', chest: 'neck', spine: 'chest', neck: 'head', head: 'plume1' };
      const out = {};
      const tipPos = (b) => { const v = ch.bones[tips[b]].getWorldPosition(new THREE.Vector3()); ch.root.worldToLocal(v); return v; };
      for (const b of list || Object.keys(tips)) {
        definePose('audit.axis0', { bones: zero }); invalidateClips();
        ch.play('audit.axis0', { fade: 0, restart: true }); settle(C, 1);
        const p0 = tipPos(b);
        const row = {};
        for (let a = 0; a < 3; a++) {
          const r = [0, 0, 0]; r[a] = 30;
          definePose('audit.axis1', { bones: { ...zero, [b]: r } }); invalidateClips();
          ch.play('audit.axis1', { fade: 0, restart: true }); settle(C, 1);
          const d = tipPos(b).sub(p0);
          row['+XYZ'[a + 1]] = d.toArray().map((x) => +x.toFixed(3));
        }
        out[b] = row;
      }
      return out;
    }

    function finiteCheck() {
      let bad = 0;
      for (const b of cur.ch.skeleton.bones) for (const x of b.matrixWorld.elements) if (!Number.isFinite(x)) bad++;
      return bad;
    }

    window.__ED.audit = {
      VARIANTS, built, get cur() { return cur; }, variant, pose, measure, rom, holes, look, step, clearOverlay,
      queue(items) { queue = items.slice(); return queue.length; }, twistScan, helperSweep, cpu, axes, finiteCheck, snapshot: () => snapshot(cur),
      poseList: (key = cur.key) => poseNames[key].map((p) => p.name),
      label(t) { label.textContent = t; },
      /** Show only these material slots (e.g. ['suit']) on every body type; null shows all. */
      show(slots) { for (const C of Object.values(built)) for (const [k, m] of Object.entries(C.ch.meshes)) m.visible = !slots || slots.includes(k); return slots; },
      exposure(v) { if (ctx.post && ctx.post.fx) ctx.post.fx.exposure = v; return v; },
      defineClip, definePose, invalidateClips,
    };
    ctx.onUpdate((dg, dr) => { if (cur) cur.ch.update(dg, dr); }, ORDER.CHAR);
    variant('kael');
    pose('rest');
  },
  scenarios: {},
});
