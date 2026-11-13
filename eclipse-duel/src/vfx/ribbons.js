// Ribbons: weapon trails between two sockets (vfx.trail) and camera-facing ribbons that follow one point (vfx.ribbon).
// Every live ribbon is re-tessellated each frame into ONE shared dynamic mesh (one draw call for all of them, plus one
// for the optional refraction twin in ctx.post.distortionScene). Samples are joined with centripetal Catmull-Rom
// splines and adaptively subdivided, so a fast swing that moves 40 cm per frame still draws a smooth arc.
// Styles (colour over age, width / erosion curves, noise, edge) are rows of a ParamTable shared by all ribbons.

import * as THREE from 'three';
import { ParamTable, tableGlsl } from './table.js';
import { toVec3, toColor, toCurveFn, toRampFn, defKey, RENDER_ORDER } from './util.js';
import { smoothstep } from '../core/math.js';
import { DEPTH_FADE_GLSL } from './depth.js';

const VMAX = 8192;
const CAP = 64; // samples per ribbon

const VERT = /* glsl */ `
precision highp float;
uniform float uTime, uTimeReal;
uniform sampler2D uStyles;
attribute vec3 aOther;
attribute vec4 aA;   // birth time, v across (0 base / 1 tip), style row, distance along (m)
attribute vec4 aB;   // speed factor, side (-1 / +1, camera-facing ribbons), width scale, mode (0 trail, 1 ribbon) + 2 realtime
varying vec4 vCol;
varying vec4 vV;     // v, dist, t, additive
varying vec3 vEdge;
varying vec4 vS;     // noise scale u, noise scale v, scroll, noise amount
varying vec4 vS2;    // erosion threshold, softness, fade base, edge width
varying float vSeed;
varying float vDist;
varying float vGrad;
varying vec2 vInk;   // ink underlay amount, dry-brush amount
${tableGlsl('uStyles', 's')}
void main() {
  int row = int(aA.z + 0.5);
  bool rt = aB.w >= 1.5;
  float mode = rt ? aB.w - 2.0 : aB.w;
  vec4 P0 = sParam(0, row), P1 = sParam(1, row), P2 = sParam(2, row), P4 = sParam(4, row);
  float age = (rt ? uTimeReal : uTime) - aA.x;
  float t = clamp(age / P0.x, 0.0, 1.0);
  vec4 cv = sCurve(t, row);
  vec3 p = position;
  if (mode < 0.5) {
    if (aA.y < 0.5) p = mix(aOther, position, cv.x);
  } else {
    vec3 toCam = normalize(cameraPosition - position);
    vec3 side = cross(aOther, toCam);
    float sl = length(side);
    side = sl > 1e-5 ? side / sl : vec3(0.0, 1.0, 0.0);
    p = position + side * aB.y * 0.5 * P4.x * cv.x * aB.z;
  }
  gl_Position = projectionMatrix * viewMatrix * vec4(p, 1.0);
  vec4 col = sRamp(t, row);
  vCol = vec4(col.rgb * cv.w, col.a * aB.x * (age < 0.0 ? 0.0 : 1.0));
  vV = vec4(aA.y, aA.w, t, cv.z);
  vEdge = P1.rgb * (1.0 - t) * (1.0 - t);
  vS = vec4(P0.y, P0.z, P0.w, P2.z);
  vS2 = vec4(cv.y, max(P2.w, 0.02), P2.x, P1.w);
  vSeed = aA.z * 0.37;
  vec4 P3 = sParam(3, row);
  vDist = P3.x;
  vInk = P3.yz;
  vGrad = P2.y;
}`;

const FRAG = /* glsl */ `
precision highp float;
uniform float uTime;
uniform sampler2D uFlow, uNoise;
varying vec4 vCol, vV, vS, vS2;
varying vec3 vEdge;
varying float vSeed;
varying float vGrad;
varying vec2 vInk;
void main() {
  float v = vV.x;
  vec2 nuv = vec2(vV.y * vS.x - uTime * vS.z, v * vS.y + vSeed);
  float streak = texture2D(uFlow, nuv).r * 0.6 + texture2D(uFlow, nuv * vec2(2.3, 1.7) + 0.5).r * 0.4;
  float grain = texture2D(uNoise, nuv * vec2(0.5, 1.0) + 0.3).r;
  float a = vCol.a;
  float fb = smoothstep(0.0, max(vS2.z, 1e-3), v);
  a *= fb * fb * (1.0 - smoothstep(0.95, 1.0, v));
  a *= mix(1.0, smoothstep(0.15, 0.85, streak) * 1.5, vS.w);
  float th = vS2.x * (1.0 + vS2.y) - vS2.y;
  a *= smoothstep(th, th + vS2.y, grain * 0.7 + (1.0 - vV.z) * 0.3);
  // brush stroke: bristle streaks along the trail; the hilt side and the old end dry out into separate hairs
  vec2 buv = vec2(vV.y * 0.3 + vSeed * 3.0, v * 0.4 + vSeed * 7.0);
  float bristle = texture2D(uFlow, buv).r;
  float dryT = mix(0.72, 0.12, smoothstep(0.0, 0.95, v)) + vV.z * 0.3 - 0.08;
  float env = a;
  a *= mix(1.0, smoothstep(dryT - 0.07, dryT + 0.07, bristle), vInk.y);
  vec3 rgb = vCol.rgb * mix(1.0 - vGrad, 1.0, v * v) + vEdge * smoothstep(1.0 - vS2.w, 0.975, v) * (1.0 - smoothstep(0.975, 1.0, v));
  a = clamp(a, 0.0, 1.0);
  // ink underlay on the trailing side (dark, alpha blended, under the light)
  float inkBrush = smoothstep(dryT - 0.24, dryT - 0.04, bristle * 0.65 + texture2D(uFlow, buv * vec2(0.7, 0.6) + 0.37).r * 0.35);
  float ink = vInk.x * clamp(env * 1.6, 0.0, 1.0) * inkBrush * (1.0 - smoothstep(0.55, 0.92, v)) * (1.0 - vV.z * vV.z);
  float ga = a * (1.0 - vV.w);
  gl_FragColor = vec4(rgb * a + vec3(0.005, 0.005, 0.007) * ink * (1.0 - ga), ga + ink * (1.0 - ga));
}`;

const FRAG_DISTORT = /* glsl */ `
precision highp float;
uniform float uTime;
uniform sampler2D uFlow;
varying vec4 vCol, vV;
varying float vSeed;
varying float vDist;
${DEPTH_FADE_GLSL}
void main() {
  vec2 f = texture2D(uFlow, vec2(vV.y * 0.5 - uTime * 0.3, vV.x * 0.5 + vSeed)).ba * 2.0 - 1.0;
  float a = clamp(vCol.a, 0.0, 1.0) * smoothstep(0.0, 0.4, vV.x) * (1.0 - vV.z);
  vec2 o = f * a * vDist;
  gl_FragColor = vec4(o * vfxRefract(o, 0.3), 0.0, 0.0);
}`;

/**
 * @param {object} vfx
 * @param {object} shared
 */
export function installRibbons(vfx, shared) {
  const { ctx, clock, root, uniforms, textures, depth } = shared;
  const table = new ParamTable(64, 'ribbon styles');
  const geo = new THREE.BufferGeometry();
  const pos = new Float32Array(VMAX * 3), oth = new Float32Array(VMAX * 3), A = new Float32Array(VMAX * 4), B = new Float32Array(VMAX * 4);
  const idx = new Uint16Array(VMAX * 3);
  const attr = (arr, n) => { const a = new THREE.BufferAttribute(arr, n); a.setUsage(THREE.DynamicDrawUsage); return a; };
  const aPos = attr(pos, 3), aOth = attr(oth, 3), aA = attr(A, 4), aB = attr(B, 4), aIdx = attr(idx, 1);
  const ATTRS = [aPos, aOth, aA, aB, aIdx];
  geo.setAttribute('position', aPos); geo.setAttribute('aOther', aOth); geo.setAttribute('aA', aA); geo.setAttribute('aB', aB);
  geo.setIndex(aIdx);
  geo.setDrawRange(0, 0);
  const U = { uTime: uniforms.uTime, uTimeReal: uniforms.uTimeReal, uStyles: { value: table.texture }, uFlow: { value: textures.flow }, uNoise: { value: textures.noise } };
  const mat = new THREE.ShaderMaterial({
    vertexShader: VERT, fragmentShader: FRAG, uniforms: U, transparent: true, depthWrite: false, depthTest: true, side: THREE.DoubleSide,
    blending: THREE.CustomBlending, blendSrc: THREE.OneFactor, blendDst: THREE.OneMinusSrcAlphaFactor, blendSrcAlpha: THREE.OneFactor, blendDstAlpha: THREE.OneMinusSrcAlphaFactor,
  });
  const mesh = new THREE.Mesh(geo, mat);
  mesh.frustumCulled = false;
  mesh.renderOrder = RENDER_ORDER.ribbons;
  mesh.visible = false;
  mesh.name = 'vfx.ribbons';
  root.add(mesh);
  const dmat = new THREE.ShaderMaterial({
    vertexShader: VERT, fragmentShader: FRAG_DISTORT,
    uniforms: { ...U, ...depth.uniforms }, defines: depth.defines(2), transparent: true, depthWrite: false, depthTest: false, side: THREE.DoubleSide,
    blending: THREE.CustomBlending, blendSrc: THREE.OneFactor, blendDst: THREE.OneFactor, blendSrcAlpha: THREE.OneFactor, blendDstAlpha: THREE.OneFactor,
  });
  const dmesh = new THREE.Mesh(geo, dmat);
  dmesh.frustumCulled = false;
  dmesh.visible = false;
  dmesh.name = 'vfx.ribbons.distort';
  ctx.post.distortionScene.add(dmesh);

  // ---- styles ------------------------------------------------------------------------------------------------------
  const styles = new Map();
  const STYLE_KEYS = ['color', 'alpha', 'intensity', 'width', 'widthOverLife', 'erode', 'additive', 'life', 'noise', 'edge', 'edgeWidth', 'fadeBase', 'gradient', 'erodeSoft', 'distort', 'blend', 'ink', 'dry'];
  function style(o, ribbonMode) {
    const pick = { m: ribbonMode };
    for (const k of STYLE_KEYS) if (o[k] !== undefined) pick[k] = o[k];
    const key = defKey(pick);
    let st = styles.get(key);
    if (st && st.row >= 0) return st;
    st = { row: -1, onEvict() { st.row = -1; } };
    st.row = table.alloc(st, clock.game);
    if (st.row < 0) st.row = 0;
    const r = st.row;
    const life = o.life != null ? o.life : ribbonMode ? 0.45 : 0.2;
    const defRamp = ribbonMode ? [[0, 5, 2.4, 0.8, 1], [0.15, 3, 1, 0.2, 0.9], [0.5, 1, 0.2, 0.03, 0.6], [1, 0.15, 0.03, 0.01, 0]] : [[0, 2.6, 1.0, 0.25, 0.8], [0.12, 1.5, 0.38, 0.05, 0.5], [0.45, 0.6, 0.1, 0.015, 0.22], [1, 0.1, 0.02, 0.0, 0]];
    table.writeRamp(r, toRampFn(o.color != null ? o.color : defRamp, o.alpha));
    const inten = o.intensity != null ? o.intensity : 1;
    const wc = toCurveFn(ribbonMode ? (o.widthOverLife != null ? o.widthOverLife : [[0, 1], [1, 0.1]]) : (o.width != null ? o.width : [[0, 1], [0.35, 0.75], [1, 0.12]]), 1);
    const ec = toCurveFn(o.erode != null ? o.erode : [[0, 0], [0.35, 0.05], [1, 0.85]], 0);
    const ac = toCurveFn(o.blend === 'alpha' ? (o.additive != null ? o.additive : 0) : 1, 1);
    table.writeCurves(r, wc, ec, ac, () => inten);
    const nz = o.noise || {};
    const ns = nz.scale || [ribbonMode ? 1.2 : 0.9, 0.55];
    table.param(r, 0, life, ns[0], ns[1], nz.speed != null ? nz.speed : 1.2);
    const edge = o.edge === false ? [0, 0, 0] : o.edge != null ? toColor(o.edge).toArray() : ribbonMode ? [0, 0, 0] : [8, 4, 1.2];
    table.param(r, 1, edge[0], edge[1], edge[2], o.edgeWidth != null ? o.edgeWidth : 0.07);
    table.param(r, 2, o.fadeBase != null ? o.fadeBase : ribbonMode ? 0.0 : 0.6, o.gradient != null ? o.gradient : ribbonMode ? 0 : 0.75, nz.amount != null ? nz.amount : 0.4, o.erodeSoft != null ? o.erodeSoft : 0.25);
    // murim brush look: dark ink underlay on the trailing side + dry-brush bristle breakup (0 = the plain ribbon)
    table.param(r, 3, o.distort || 0, o.ink != null ? o.ink : ribbonMode ? 0.2 : 0.45, o.dry != null ? o.dry : ribbonMode ? 0.4 : 0.7, 0);
    table.param(r, 4, o.width != null && ribbonMode ? o.width : 0.15, 0, 0, 0);
    st.life = life;
    styles.set(key, st);
    return st;
  }

  // ---- ribbon objects ------------------------------------------------------------------------------------------------
  const live = [];
  const va = new THREE.Vector3(), vb = new THREE.Vector3();

  function makeRibbon(o, ribbonMode) {
    const st = style(o, ribbonMode);
    const r = {
      mode: ribbonMode ? 1 : 0, st, realtime: !!o.realtime, life: st.life,
      a: o.a || null, b: o.b || null, followObj: o.follow || null, offset: o.offset ? toVec3(o.offset) : new THREE.Vector3(),
      point: o.pos != null ? toVec3(o.pos) : new THREE.Vector3(),
      minSpeed: o.minSpeed != null ? o.minSpeed : ribbonMode ? 0 : 3,
      segLen: o.segLen || 0.05, maxSub: o.maxSub || 8,
      width: o.widthScale || 1,
      sampling: o.autoStart !== false, dead: false, distort: (o.distort || 0) > 0,
      // sample ring: base xyz, tip xyz (ribbons: point xyz twice), time, speed factor
      P: new Float32Array(CAP * 3), Q: new Float32Array(CAP * 3), T: new Float32Array(CAP), S: new Float32Array(CAP),
      head: 0, count: 0, lastT: -1e9, dist0: 0,
    };
    const h = {
      get alive() { return !r.dead && (r.sampling || r.count > 1 && newestAge(r) < r.life); },
      get sampling() { return r.sampling; },
      start() { if (!r.dead) { r.sampling = true; } return h; },
      stop() { r.sampling = false; return h; },
      kill() { r.dead = true; r.count = 0; },
      setPosition(v) { toVec3(v, r.point); r.followObj = null; return h; },
      follow(obj, offset) { r.followObj = obj; if (offset) toVec3(offset, r.offset); return h; },
      setSockets(a, b) { r.a = a; r.b = b; return h; },
    };
    r.h = h;
    live.push(r);
    if (r.sampling) sample(r, true);
    shared.track(h);
    return h;
  }

  function now(r) { return r.realtime ? clock.real : clock.game; }
  function newestAge(r) { return r.count ? now(r) - r.T[(r.head - 1 + CAP) % CAP] : 1e9; }

  function readPoint(src, off, out) {
    if (src && src.isObject3D) { src.updateWorldMatrix(true, false); return out.copy(off).applyMatrix4(src.matrixWorld); }
    return toVec3(src, out).add(off);
  }

  /** take the current socket positions; a new sample when enough time passed, else move the head sample */
  function sample(r, force) {
    const t = now(r);
    if (r.mode === 0) {
      if (r.a && r.a.isObject3D) { r.a.updateWorldMatrix(true, false); va.setFromMatrixPosition(r.a.matrixWorld); } else toVec3(r.a, va);
      if (r.b && r.b.isObject3D) { r.b.updateWorldMatrix(true, false); vb.setFromMatrixPosition(r.b.matrixWorld); } else toVec3(r.b, vb);
    } else {
      if (r.followObj) readPoint(r.followObj, r.offset, va); else va.copy(r.point);
      vb.copy(va);
    }
    const minDt = r.life / 40;
    let i;
    if (!force && r.count > 0 && t - r.lastT < minDt) {
      i = (r.head - 1 + CAP) % CAP;   // move the head sample (slow motion / tiny steps)
    } else {
      i = r.head;
      r.head = (r.head + 1) % CAP;
      r.count = Math.min(CAP, r.count + 1);
      r.lastT = t;
    }
    // speed factor from the tip motion since the previous sample
    let spd = 1;
    if (r.minSpeed > 0) {
      const p = (i - 1 + CAP) % CAP;
      if (r.count > 1) {
        const dt = Math.max(1e-4, t - r.T[p]);
        const dx = vb.x - r.Q[p * 3], dy = vb.y - r.Q[p * 3 + 1], dz = vb.z - r.Q[p * 3 + 2];
        spd = smoothstep(r.minSpeed, r.minSpeed * 2.5, Math.sqrt(dx * dx + dy * dy + dz * dz) / dt);
      } else spd = 0;
    }
    r.P[i * 3] = va.x; r.P[i * 3 + 1] = va.y; r.P[i * 3 + 2] = va.z;
    r.Q[i * 3] = vb.x; r.Q[i * 3 + 1] = vb.y; r.Q[i * 3 + 2] = vb.z;
    r.T[i] = t; r.S[i] = spd;
  }

  // ---- tessellation --------------------------------------------------------------------------------------------------
  let nv = 0, ni = 0;
  const K = new Float32Array(4);
  /** centripetal Catmull-Rom on component arrays: points i0..i3 of arr (xyz), parameter u in [0,1] between i1 and i2 */
  function knot(arr, a, b) {
    const x = arr[a * 3] - arr[b * 3], y = arr[a * 3 + 1] - arr[b * 3 + 1], z = arr[a * 3 + 2] - arr[b * 3 + 2];
    return Math.max(1e-4, Math.pow(x * x + y * y + z * z, 0.25));
  }
  function crKnots(arr, i0, i1, i2, i3) {
    K[0] = 0; K[1] = knot(arr, i0, i1); K[2] = K[1] + knot(arr, i1, i2); K[3] = K[2] + knot(arr, i2, i3);
  }
  const out3 = new Float32Array(3);
  function crEval(arr, i0, i1, i2, i3, u) {
    const t0 = K[0], t1 = K[1], t2 = K[2], t3 = K[3];
    const t = t1 + (t2 - t1) * u;
    for (let c = 0; c < 3; c++) {
      const p0 = arr[i0 * 3 + c], p1 = arr[i1 * 3 + c], p2 = arr[i2 * 3 + c], p3 = arr[i3 * 3 + c];
      const a1 = ((t1 - t) * p0 + (t - t0) * p1) / (t1 - t0);
      const a2 = ((t2 - t) * p1 + (t - t1) * p2) / (t2 - t1);
      const a3 = ((t3 - t) * p2 + (t - t2) * p3) / (t3 - t2);
      const b1 = ((t2 - t) * a1 + (t - t0) * a2) / (t2 - t0);
      const b2 = ((t3 - t) * a2 + (t - t1) * a3) / (t3 - t1);
      out3[c] = ((t2 - t) * b1 + (t - t1) * b2) / (t2 - t1);
    }
    return out3;
  }

  const ordered = new Int32Array(CAP);
  const bx = new Float32Array(3), tx = new Float32Array(3), prevTip = new Float32Array(3);
  function emitRow(r, base, tip, other, birth, speed, dist) {
    if (nv + 2 > VMAX) return false;
    const mode = r.mode + (r.realtime ? 2 : 0);
    for (let k = 0; k < 2; k++) {
      const j = nv + k;
      const p = r.mode === 0 ? (k === 0 ? base : tip) : base;
      const q = r.mode === 0 ? (k === 0 ? tip : base) : other;
      pos[j * 3] = p[0]; pos[j * 3 + 1] = p[1]; pos[j * 3 + 2] = p[2];
      oth[j * 3] = q[0]; oth[j * 3 + 1] = q[1]; oth[j * 3 + 2] = q[2];
      A[j * 4] = birth; A[j * 4 + 1] = k; A[j * 4 + 2] = r.st.row; A[j * 4 + 3] = dist;
      B[j * 4] = speed; B[j * 4 + 1] = k === 0 ? -1 : 1; B[j * 4 + 2] = r.width; B[j * 4 + 3] = mode;
    }
    nv += 2;
    return true;
  }

  function tessellate(r) {
    // drop expired samples, order oldest -> newest
    const t = now(r);
    let n = 0;
    for (let k = r.count - 1; k >= 0; k--) {
      const i = (r.head - 1 - k + CAP * 2) % CAP;
      if (t - r.T[i] < r.life) ordered[n++] = i;
    }
    if (n < 2) return;
    const firstRow = nv;
    let dist = 0;
    for (let s = 0; s < n - 1; s++) {
      const i0 = ordered[Math.max(0, s - 1)], i1 = ordered[s], i2 = ordered[s + 1], i3 = ordered[Math.min(n - 1, s + 2)];
      // subdivisions from the tip travel of this segment
      const dx = r.Q[i2 * 3] - r.Q[i1 * 3], dy = r.Q[i2 * 3 + 1] - r.Q[i1 * 3 + 1], dz = r.Q[i2 * 3 + 2] - r.Q[i1 * 3 + 2];
      const len = Math.sqrt(dx * dx + dy * dy + dz * dz);
      const sub = Math.max(1, Math.min(r.maxSub, Math.ceil(len / r.segLen)));
      const last = s === n - 2;
      for (let k = 0; k < sub + (last ? 1 : 0); k++) {
        const u = k / sub;
        crKnots(r.P, i0, i1, i2, i3);
        const pb = crEval(r.P, i0, i1, i2, i3, u); bx[0] = pb[0]; bx[1] = pb[1]; bx[2] = pb[2];
        crKnots(r.Q, i0, i1, i2, i3);
        const pt = crEval(r.Q, i0, i1, i2, i3, u); tx[0] = pt[0]; tx[1] = pt[1]; tx[2] = pt[2];
        if (nv > firstRow) dist += Math.hypot(tx[0] - prevTip[0], tx[1] - prevTip[1], tx[2] - prevTip[2]);
        prevTip[0] = tx[0]; prevTip[1] = tx[1]; prevTip[2] = tx[2];
        const birth = r.T[i1] + (r.T[i2] - r.T[i1]) * u;
        const spd = r.S[i1] + (r.S[i2] - r.S[i1]) * u;
        let ok;
        if (r.mode === 0) ok = emitRow(r, bx, tx, null, birth, spd, dist);
        else {
          // tangent from the neighbouring samples
          const ia = ordered[s], ib = ordered[s + 1];
          tx[0] = r.P[ib * 3] - r.P[ia * 3]; tx[1] = r.P[ib * 3 + 1] - r.P[ia * 3 + 1]; tx[2] = r.P[ib * 3 + 2] - r.P[ia * 3 + 2];
          const l = Math.hypot(tx[0], tx[1], tx[2]) || 1;
          tx[0] /= l; tx[1] /= l; tx[2] /= l;
          ok = emitRow(r, bx, bx, tx, birth, spd, dist);
        }
        if (!ok) break;
      }
    }
    // indices: quads between consecutive rows of this ribbon
    const rows = (nv - firstRow) / 2;
    for (let k = 0; k < rows - 1 && ni + 6 <= idx.length; k++) {
      const v0 = firstRow + k * 2;
      idx[ni++] = v0; idx[ni++] = v0 + 1; idx[ni++] = v0 + 2;
      idx[ni++] = v0 + 1; idx[ni++] = v0 + 3; idx[ni++] = v0 + 2;
    }
  }

  return {
    name: 'ribbons',
    api: {
      /**
       * Weapon trail between two sockets. See README.md for every option. Returns
       * { start(), stop(), kill(), setSockets(a, b), alive, sampling }.
       */
      trail(o) { if (!o || o.a == null || o.b == null) throw new Error('vfx.trail needs { a, b } sockets'); return makeRibbon(o, false); },
      /** Camera-facing ribbon following one point. Returns { setPosition(v), follow(obj, offset), start(), stop(), kill(), alive }. */
      ribbon(o = {}) { return makeRibbon(o, true); },
      ribbons: { live, table },
    },
    update(dtGame, dtReal) {
      nv = 0; ni = 0;
      let anyDistort = false;
      for (let i = live.length - 1; i >= 0; i--) {
        const r = live[i];
        if (!r.h.alive) { live.splice(i, 1); continue; }
        const dt = r.realtime ? dtReal : dtGame;
        if (r.sampling && dt > 0) sample(r, false);
        tessellate(r);
        if (r.distort) anyDistort = true;
      }
      table.commit();
      geo.setDrawRange(0, ni);
      if (ni > 0) {
        for (let k = 0; k < ATTRS.length; k++) {
          const a = ATTRS[k];
          a.clearUpdateRanges(); a.addUpdateRange(0, a === aIdx ? ni : nv * a.itemSize); a.needsUpdate = true;
        }
      }
      mesh.visible = ni > 0;
      dmesh.visible = ni > 0 && anyDistort;
    },
    clear() { for (const r of live) r.dead = true; live.length = 0; mesh.visible = dmesh.visible = false; geo.setDrawRange(0, 0); },
    dispose() { geo.dispose(); mat.dispose(); dmat.dispose(); table.dispose(); mesh.removeFromParent(); dmesh.removeFromParent(); },
  };
}
