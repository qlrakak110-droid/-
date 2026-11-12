// vfx.bolt: lightning. Each bolt owns a fixed slot of one merged dynamic buffer (one draw call for every bolt): a
// main channel built by 3D midpoint displacement (fractal: the offset of each midpoint scales with its segment length)
// plus forked branches and sub-branches that taper to their tips. Strips are expanded to face the camera in the vertex
// shader, so the thin white-hot core and its wide glow sheath read from any angle. The CPU writes a slot only when the
// bolt (re)strikes: a stepped leader races from the source on the first stroke, return strokes re-flash the same
// channel (coarse shape kept, fine detail and branches re-drawn), the brightness flickers every frame in the shader,
// and after the last stroke the channel cools into an afterglow that erodes along its length.
// Per stroke it can also flash an impact flare and a pooled light.

import * as THREE from 'three';
import { EffectPool } from './pool.js';
import { GLSL_COMMON, CULL } from './glsl.js';
import { toVec3, RENDER_ORDER } from './util.js';
import { PREMUL, resolveColors, makeColors, opt, first, second } from './meshfx.js';

const SLOTS = 24;
const MAXP = 360;           // points per slot (main channel + branches)
const VPS = MAXP * 2;       // vertices per slot
const IPS = (MAXP - 1) * 6; // indices per slot

const VERT = /* glsl */ `
precision highp float;
uniform float uTime, uTimeReal;
attribute vec4 aTan;    // tangent xyz, side (-1 / +1)
attribute vec4 aInfo;   // width (m), intensity, reveal coordinate along the main channel (0..1), along own polyline (0..1)
attribute vec4 aTime;   // stroke time, birth time, life (signed: < 0 real time), seed
attribute vec4 aLook;   // last stroke (1), leader time (s), core fraction, flicker amount
attribute vec4 aCore;   // core rgb, glow amount
attribute vec4 aMid;    // glow rgb, afterglow cooling time (s)
varying vec4 vA;        // side, along, intensity, core fraction
varying vec4 vB;        // brightness, afterglow, cool, seed
varying vec3 vCore, vMid;
${GLSL_COMMON}
void main() {
  float life = abs(aTime.z);
  float now = aTime.z < 0.0 ? uTimeReal : uTime;
  float age = now - aTime.y;
  float sa = now - aTime.x;
  if (life <= 0.0 || age < 0.0 || age >= life || sa < -1e-4) { ${CULL} }
  sa = max(sa, 0.0);
  // stepped leader (first stroke): the channel grows from the source; its tip glows while it travels
  float lead = aLook.y > 0.0 ? sat(sa / aLook.y) : 1.0;
  if (aInfo.z > lead + 0.002) { ${CULL} }
  float tipGlow = lead < 1.0 ? exp(-max(lead - aInfo.z, 0.0) * 25.0) * 1.5 : 0.0;
  // stroke: a one-frame flash decaying fast, then flicker; the last stroke cools into an eroding afterglow
  float stroke = exp(-sa * 24.0) * 0.8 + exp(-sa * 5.0) * 0.35;
  float fr = floor(now * 30.0);
  float flick = 1.0 - aLook.w * h11(fr * 1.31 + aTime.w * 17.0) * (1.0 - exp(-sa * 40.0));
  float rest = life - (aTime.x - aTime.y);
  float after = aLook.x > 0.5 ? sat(1.0 - sa / max(rest, 1e-3)) : 1.0;
  float cool = aLook.x > 0.5 ? sat(sa / max(aMid.w, 1e-3)) : 0.0;
  vec3 P = position;
  vec3 side = cross(aTan.xyz, cameraPosition - P);
  float sl = length(side);
  side = sl > 1e-6 ? side / sl : vec3(0.0, 1.0, 0.0);
  float w = aInfo.x * (1.0 + 0.7 * exp(-sa * 30.0)) * (0.6 + 0.4 * after);
  P += side * aTan.w * w * 0.5;
  gl_Position = projectionMatrix * viewMatrix * vec4(P, 1.0);
  vA = vec4(aTan.w, aInfo.w, aInfo.y, aLook.z);
  vB = vec4(max(stroke * flick, 0.22 * after) + tipGlow, after, cool, aTime.w);
  vCore = aCore.rgb;
  vMid = aMid.rgb * aCore.w;
}`;

const FRAG = /* glsl */ `
precision highp float;
uniform sampler2D uNoise;
varying vec4 vA, vB;
varying vec3 vCore, vMid;
${GLSL_COMMON}
void main() {
  float x = abs(vA.x), along = vA.y, inten = vA.z, cw = vA.w;
  float br = vB.x, after = vB.y, cool = vB.z;
  float core = 1.0 - smoothstep(cw * 0.4, cw, x);
  float glow = exp(-x * 6.0) * 0.5 + exp(-x * x * 50.0) * 0.4;
  // afterglow: erodes along the channel, faster toward the tips
  float n = texture2D(uNoise, vec2(along * 2.3 + vB.w, vB.w * 0.37 + x * 0.05)).r;
  float vis = after >= 0.999 ? 1.0 : smoothstep(1.0 - after - 0.12, 1.0 - after + 0.12, n * 0.75 + 0.25 * (1.0 - along));
  vec3 hot = vCore * 1.5 + vec3(dot(vCore, vec3(0.333)) * 0.8);
  vec3 cc = mix(hot, vCore * 0.6 + vMid * 0.4, cool);
  vec3 gc = mix(vMid, vMid * 0.25, cool);
  vec3 rgb = (cc * core + gc * glow * (1.0 - core)) * br * inten;
  float a = sat(core + glow) * vis * (1.0 - smoothstep(0.8, 1.0, x));
  if (a <= 0.002) discard;
  gl_FragColor = vec4(rgb * a, 0.0);
}`;

/**
 * @param {object} vfx
 * @param {object} shared
 */
export function installBolt(vfx, shared) {
  const { uniforms, textures, rng, root } = shared;
  const geo = new THREE.BufferGeometry();
  const N = SLOTS * VPS;
  const pos = new Float32Array(N * 3), tan = new Float32Array(N * 4), info = new Float32Array(N * 4), time = new Float32Array(N * 4);
  const look = new Float32Array(N * 4), cor = new Float32Array(N * 4), mid = new Float32Array(N * 4);
  const idx = new Uint16Array(SLOTS * IPS);
  const mk = (arr, n) => { const a = new THREE.BufferAttribute(arr, n); a.setUsage(THREE.DynamicDrawUsage); return a; };
  const A = { position: mk(pos, 3), aTan: mk(tan, 4), aInfo: mk(info, 4), aTime: mk(time, 4), aLook: mk(look, 4), aCore: mk(cor, 4), aMid: mk(mid, 4) };
  for (const k in A) geo.setAttribute(k, A[k]);
  const aIdx = mk(idx, 1);
  geo.setIndex(aIdx);
  geo.setDrawRange(0, 0);
  const mat = new THREE.ShaderMaterial({
    vertexShader: VERT, fragmentShader: FRAG,
    uniforms: { uTime: uniforms.uTime, uTimeReal: uniforms.uTimeReal, uNoise: { value: textures.noise } },
    side: THREE.DoubleSide, ...PREMUL,
  });
  const mesh = new THREE.Mesh(geo, mat);
  mesh.frustumCulled = false;
  mesh.visible = false;
  mesh.renderOrder = RENDER_ORDER.meshBolt;
  mesh.name = 'vfx.bolt';
  root.add(mesh);

  const pool = new EffectPool(shared, SLOTS, () => ({
    // channel memory: per main point, offsets in the (e1, e2) plane and along the axis (re-strokes keep the coarse shape)
    ox: new Float32Array(257), oy: new Float32Array(257), oz: new Float32Array(257),
    P: new Float32Array(MAXP * 3), np: 0, lines: [], children: [], A: new THREE.Vector3(), B: new THREE.Vector3(), core: new THREE.Color(), mid: new THREE.Color(),
  }));
  pool.onFree = (s) => {
    for (const c of s.children) c.kill();
    s.children.length = 0;
    const base = s.i * VPS;
    for (let v = 0; v < VPS; v++) time[(base + v) * 4 + 2] = 0;
    upload(s.i, VPS, false);
    s.srcA = s.srcB = null;
  };

  function upload(slot, nv, withIndex) {
    const v0 = slot * VPS;
    for (const k in A) { const a = A[k]; a.addUpdateRange(v0 * a.itemSize, nv * a.itemSize); a.needsUpdate = true; }
    if (withIndex) { aIdx.addUpdateRange(slot * IPS, IPS); aIdx.needsUpdate = true; }
  }

  const gauss = () => (rng() + rng() + rng() + rng() - 2) * 1.73;
  const dir = new THREE.Vector3(), e1 = new THREE.Vector3(), e2 = new THREE.Vector3(), T = new THREE.Vector3(), Q = new THREE.Vector3(), R = new THREE.Vector3();

  function frame(d) {
    e1.set(0, 1, 0);
    if (Math.abs(d.dot(e1)) > 0.9) e1.set(1, 0, 0);
    e1.crossVectors(d, e1).normalize();
    e2.crossVectors(d, e1).normalize();
  }

  const bx = new Float32Array(257), by = new Float32Array(257), bz = new Float32Array(257);
  /**
   * Midpoint-displace a polyline of 2^lev segments from a to b into s.P starting at point index p0 (offsets in the
   * slot's channel memory for the main channel, in scratch arrays for branches). Returns the point count.
   */
  function displace(s, p0, a, b, lev, rough, keepCoarse, main) {
    const n = 1 << lev;
    dir.subVectors(b, a);
    const L = dir.length();
    dir.multiplyScalar(1 / Math.max(L, 1e-6));
    frame(dir);
    const ox = main ? s.ox : bx, oy = main ? s.oy : by, oz = main ? s.oz : bz;
    if (!keepCoarse) { ox[0] = oy[0] = oz[0] = ox[n] = oy[n] = oz[n] = 0; }
    for (let step = n; step >= 2; step >>= 1) {
      // re-strokes keep the coarse levels (the same channel lights up again) and re-jag the fine ones
      if (keepCoarse && step > n / 32) continue;
      const amp = rough * (step / n) * L * (step === n ? 0.6 : 1);
      for (let i = step >> 1; i < n; i += step) {
        const l = i - (step >> 1), r = i + (step >> 1);
        ox[i] = (ox[l] + ox[r]) * 0.5 + gauss() * amp;
        oy[i] = (oy[l] + oy[r]) * 0.5 + gauss() * amp;
        oz[i] = (oz[l] + oz[r]) * 0.5 + gauss() * amp * 0.25;
      }
    }
    const P = s.P;
    for (let i = 0; i <= n; i++) {
      const t = i / n;
      const k = (p0 + i) * 3;
      P[k] = a.x + dir.x * (t * L + oz[i]) + e1.x * ox[i] + e2.x * oy[i];
      P[k + 1] = a.y + dir.y * (t * L + oz[i]) + e1.y * ox[i] + e2.y * oy[i];
      P[k + 2] = a.z + dir.z * (t * L + oz[i]) + e1.z * ox[i] + e2.z * oy[i];
    }
    return n + 1;
  }

  /** Write the vertices of polyline [p0, p0 + n) of slot s. */
  function writeLine(s, p0, n, o) {
    const base = s.i * VPS, P = s.P;
    for (let i = 0; i < n; i++) {
      const pi = p0 + i;
      const ia = p0 + Math.max(0, i - 1), ib = p0 + Math.min(n - 1, i + 1);
      T.set(P[ib * 3] - P[ia * 3], P[ib * 3 + 1] - P[ia * 3 + 1], P[ib * 3 + 2] - P[ia * 3 + 2]).normalize();
      const along = i / (n - 1);
      const wd = o.width * (o.taper ? Math.pow(1 - along, 0.7) * 0.9 + 0.1 : 1 - 0.3 * along);
      const inten = o.inten * (0.82 + 0.18 * rng());
      const reveal = o.reveal0 + along * o.revealSpan;
      for (let sd = 0; sd < 2; sd++) {
        const v = base + pi * 2 + sd;
        pos[v * 3] = P[pi * 3]; pos[v * 3 + 1] = P[pi * 3 + 1]; pos[v * 3 + 2] = P[pi * 3 + 2];
        tan[v * 4] = T.x; tan[v * 4 + 1] = T.y; tan[v * 4 + 2] = T.z; tan[v * 4 + 3] = sd ? 1 : -1;
        info[v * 4] = wd; info[v * 4 + 1] = inten; info[v * 4 + 2] = reveal; info[v * 4 + 3] = along;
        time[v * 4] = o.strikeT; time[v * 4 + 1] = s.t0; time[v * 4 + 2] = s.realtime ? -s.lifeS : s.lifeS; time[v * 4 + 3] = s.seed;
        look[v * 4] = o.last; look[v * 4 + 1] = o.leader; look[v * 4 + 2] = s.coreFrac; look[v * 4 + 3] = s.flicker;
        cor[v * 4] = s.core.r; cor[v * 4 + 1] = s.core.g; cor[v * 4 + 2] = s.core.b; cor[v * 4 + 3] = s.glow;
        mid[v * 4] = s.mid.r; mid[v * 4 + 1] = s.mid.g; mid[v * 4 + 2] = s.mid.b; mid[v * 4 + 3] = s.coolT;
      }
    }
  }

  function readEnd(src, out) {
    if (src && src.isObject3D) { src.updateWorldMatrix(true, false); return out.setFromMatrixPosition(src.matrixWorld); }
    return toVec3(src, out);
  }

  // reusable polyline options (no allocation per stroke)
  const lo = { strikeT: 0, last: 0, leader: 0, width: 0, inten: 1, taper: false, reveal0: 0, revealSpan: 1 };
  function line(width, inten, taper, reveal0, revealSpan) {
    lo.width = width; lo.inten = inten; lo.taper = taper; lo.reveal0 = reveal0; lo.revealSpan = revealSpan;
    return lo;
  }

  /** (Re)strike slot s at absolute clock time `at`. */
  function strike(s, at) {
    const first = s.strokes === 0;
    s.strokes++;
    const last = s.strokes >= s.strokeCount ? 1 : 0;
    if (s.srcA) readEnd(s.srcA, s.A);
    if (s.srcB) readEnd(s.srcB, s.B);
    const L = s.A.distanceTo(s.B);
    const lev = s.levels;
    const nMain = displace(s, 0, s.A, s.B, lev, s.rough, !first, true);
    lo.strikeT = at; lo.last = last; lo.leader = first ? s.leader : 0;
    writeLine(s, 0, nMain, line(s.width, 1, false, 0, 1));
    // branches: forks from random main points, angled away from the channel, tapering to their tips
    s.lines.length = 0;
    s.lines.push(0, nMain);
    let used = nMain;
    const nb = Math.round(first ? s.branches : s.branches * (0.5 + 0.5 * rng()));
    for (let b = 0; b < nb; b++) {
      const bl = Math.min(5, s.levels - 2);
      if (used + (1 << bl) + 1 > MAXP) break;
      const ri = Math.floor(((1 << lev) * (0.06 + 0.8 * Math.pow(rng(), 1.3))));
      const P = s.P;
      R.set(P[ri * 3], P[ri * 3 + 1], P[ri * 3 + 2]);
      const rj = Math.min(ri + 2, (1 << lev));
      T.set(P[rj * 3] - R.x, P[rj * 3 + 1] - R.y, P[rj * 3 + 2] - R.z).normalize();
      frame(T);
      const ang = (0.35 + 0.6 * rng()) * (rng() < 0.5 ? -1 : 1), phi = rng() * Math.PI * 2;
      Q.copy(T).multiplyScalar(Math.cos(ang)).addScaledVector(e1, Math.sin(ang) * Math.cos(phi)).addScaledVector(e2, Math.sin(ang) * Math.sin(phi));
      const lb = L * (0.12 + 0.28 * rng()) * (1 - (ri / (1 << lev)) * 0.5);
      Q.multiplyScalar(lb).add(R);
      const n = displace(s, used, R, Q, bl, s.rough * 1.15, false, false);
      const r0 = ri / (1 << lev);
      writeLine(s, used, n, line(s.width * 0.5, 0.6, true, r0, (lb / Math.max(L, 1e-3)) * 0.9));
      s.lines.push(used, n);
      const bStart = used;
      used += n;
      // a sub-branch off half of the branches
      if (rng() < 0.55 && used + 9 <= MAXP) {
        const si = bStart + 2 + Math.floor(rng() * (n - 4));
        R.set(P[si * 3], P[si * 3 + 1], P[si * 3 + 2]);
        T.set(P[(si + 1) * 3] - R.x, P[(si + 1) * 3 + 1] - R.y, P[(si + 1) * 3 + 2] - R.z).normalize();
        frame(T);
        const a2 = (0.5 + 0.5 * rng()) * (rng() < 0.5 ? -1 : 1);
        Q.copy(T).multiplyScalar(Math.cos(a2)).addScaledVector(e1, Math.sin(a2)).multiplyScalar(lb * (0.3 + 0.3 * rng())).add(R);
        const n2 = displace(s, used, R, Q, 3, s.rough * 1.2, false, false);
        writeLine(s, used, n2, line(s.width * 0.28, 0.4, true, r0 + 0.05, 0.1));
        s.lines.push(used, n2);
        used += n2;
      }
    }
    // indices for every polyline of the slot; the rest of the slot's index block is degenerate
    const ib = s.i * IPS, vb = s.i * VPS;
    let w = 0;
    for (let l = 0; l < s.lines.length; l += 2) {
      const p0 = s.lines[l], n = s.lines[l + 1];
      for (let i = 0; i < n - 1; i++) {
        const a = vb + (p0 + i) * 2, c = a + 2;
        idx[ib + w++] = a; idx[ib + w++] = a + 1; idx[ib + w++] = c;
        idx[ib + w++] = a + 1; idx[ib + w++] = c + 1; idx[ib + w++] = c;
      }
    }
    for (; w < IPS; w++) idx[ib + w] = vb;
    // stale vertices beyond `used` keep their old data: mark them dead
    for (let v = used * 2; v < s.np * 2; v++) time[(vb + v) * 4 + 2] = 0;
    upload(s.i, Math.max(used, s.np) * 2, true);
    s.np = used;
    s.nextAt += s.interval[0] + (s.interval[1] - s.interval[0]) * rng();
    // per-stroke light and impact flare (the first one when the leader connects)
    if (first && s.leader > 0 && vfx.schedule) { const my = s.serial; s.children.push(vfx.schedule(s.leader, () => { if (s.serial === my) flash(s, true); }, { realtime: s.realtime })); }
    else flash(s, first);
    mesh.visible = true;
    drawMax = Math.max(drawMax, s.i + 1);
    geo.setDrawRange(0, drawMax * IPS);
  }
  function flash(s, first) {
    if (!s.live) return;
    const ch = s.children;
    if (ch.length > 24) ch.splice(0, ch.length - 12);
    if (s.lightI > 0 && vfx.light) ch.push(vfx.light({ pos: s.B, color: s.core, intensity: s.lightI * (first ? 1 : 0.7), range: s.lightRange, duration: 0.14, realtime: s.realtime }));
    if (s.impact && vfx.flare) {
      ch.push(vfx.flare({ kind: 'glow', pos: s.B, size: s.width * 7, life: 0.09, color: s.core, intensity: first ? 0.7 : 0.45, realtime: s.realtime }));
      if (first) ch.push(vfx.flare({ kind: 'flash', pos: s.B, size: s.width * 26, life: 0.12, color: s.mid, intensity: 0.35, realtime: s.realtime }));
    }
  }
  let drawMax = 0;
  const C = makeColors();
  const visit = (s, age) => { while (s.strokes < s.strokeCount && age >= s.nextAt) strike(s, s.t0 + s.nextAt); };

  /**
   * Lightning bolt with branches, flicker and re-strokes. See README "Bolt". Returns { kill(), stop(), alive }.
   */
  function bolt(opts = {}) {
    const life = opt(opts.life, 0.5);
    const { slot: s, handle } = pool.alloc({ life, realtime: !!opts.realtime });
    const live = (v) => v && (v.isObject3D || typeof v === 'function');
    s.srcA = live(opts.from) ? opts.from : null;
    s.srcB = live(opts.to) ? opts.to : null;
    readEnd(opts.from, s.A);
    readEnd(opts.to, s.B);
    resolveColors(opts, { palette: 'volt' }, C);
    const inten = opt(opts.intensity, 1);
    s.core.copy(C.core).multiplyScalar(inten);
    s.mid.copy(C.mid).multiplyScalar(inten);
    const sc = opt(opts.scale, 1);
    s.lifeS = life;
    s.width = opt(opts.width, 0.32) * sc;
    s.coreFrac = opt(opts.core, 0.11);
    s.glow = opt(opts.glow, 1);
    s.levels = Math.max(4, Math.min(8, opt(opts.detail, 7)));
    s.rough = opt(opts.roughness, 0.24);
    s.branches = opt(opts.branches, 5);
    s.strokeCount = Math.max(1, opt(opts.strikes, 3));
    const iv = opt(opts.interval, [0.05, 0.11]);
    s.interval = [first(iv), second(iv)];
    s.leader = opt(opts.leader, 0.035);
    s.flicker = opt(opts.flicker, 0.55);
    s.coolT = opt(opts.cool, 0.25);
    s.seed = rng() * 100;
    s.lightI = opts.light === false ? 0 : opt(opts.light, 0);
    s.lightRange = opt(opts.lightRange, 8);
    s.impact = opts.impact !== false;
    s.strokes = 0;
    s.nextAt = 0;
    s.np = s.np || 0;
    strike(s, s.t0);
    return handle;
  }

  return {
    name: 'bolt',
    api: { bolt },
    update() {
      pool.forEach(visit);
      if (pool.live === 0) { mesh.visible = false; drawMax = 0; geo.setDrawRange(0, 0); }
    },
    clear() { pool.clear(); mesh.visible = false; drawMax = 0; geo.setDrawRange(0, 0); },
    dispose() { geo.dispose(); mat.dispose(); mesh.removeFromParent(); },
  };
}
