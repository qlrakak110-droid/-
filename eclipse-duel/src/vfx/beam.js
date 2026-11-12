// vfx.beam: energy beams between two points. An instanced strip template is laid along the axis and turned to face
// the camera around it in the vertex shader (it reads as a volume from any side angle); the beam extends from the
// source with an eased head, wiggles, pulses and tapers, and is shaded as a hot core inside a streaky scrolling sheath.
// It sustains until stop() (or for `life`), then releases: the width collapses while noise erodes it. End points can
// be moved every frame (h.setEnds) or follow Object3Ds / functions. Looks: energy, fire, frost, volt, eclipse.
// All beams share ONE draw call (end flares, when asked for, use the flare layer).

import * as THREE from 'three';
import { MeshLayer, gridGeometry, PREMUL, resolveColors, makeColors, opt } from './meshfx.js';
import { GLSL_COMMON, GLSL_VORONOI, CULL } from './glsl.js';
import { toVec3, RENDER_ORDER } from './util.js';

const LOOK_ID = { energy: 0, fire: 1, frost: 2, volt: 3, eclipse: 4 };

/** Look presets (per-call options override any field; see README "Beam"). */
export const BEAM_LOOKS = {
  energy: { palette: 'ember', width: 0.45, coreWidth: 0.16, wiggle: 0.04, extend: 0.08, release: 0.25, noise: 0.5, scroll: 9, taper: [0.4, 0.5], tailAdditive: 1 },
  fire: { palette: 'ember', tailFrom: 'smoke', width: 0.7, coreWidth: 0.18, wiggle: 0.08, extend: 0.12, release: 0.35, noise: 0.7, scroll: 7, taper: [0.5, 0.7], tailAdditive: 0.2 },
  frost: { palette: 'frost', width: 0.5, coreWidth: 0.2, wiggle: 0.02, extend: 0.1, release: 0.35, noise: 0.5, scroll: 4, taper: [0.4, 0.5], tailAdditive: 0.6 },
  volt: { palette: 'volt', width: 0.5, coreWidth: 0.1, wiggle: 0.06, extend: 0.04, release: 0.18, noise: 0.5, scroll: 16, taper: [0.3, 0.4], tailAdditive: 1 },
  eclipse: { palette: 'eclipse', tailFrom: 'smoke', width: 0.6, coreWidth: 0.3, wiggle: 0.03, extend: 0.12, release: 0.4, noise: 0.5, scroll: 5, taper: [0.5, 0.6], tailAdditive: 0 },
};

const LAYOUT = { iA: 4, iB: 4, iDim: 4, iTime: 4, iCore: 4, iMid: 4, iTail: 4, iLook: 4 };
const FOREVER = 1e6;

const VERT = /* glsl */ `
precision highp float;
uniform float uTime, uTimeReal;
attribute vec4 iA, iB, iDim, iTime, iCore, iMid, iTail, iLook;
varying vec4 vA;   // s (m along), x (-1..1), age, length shown
varying vec4 vB;   // release progress, seed, look, core width
varying vec4 vCore, vMid, vTail, vL;
${GLSL_COMMON}
void main() {
  float life = abs(iB.w);
  float age = (iB.w < 0.0 ? uTimeReal : uTime) - iA.w;
  if (life <= 0.0 || age < 0.0 || age >= life) { ${CULL} }
  vec3 A = iA.xyz, B = iB.xyz;
  vec3 AB = B - A;
  float len = max(length(AB), 1e-3);
  vec3 D = AB / len;
  float ext = outExpo(age / max(iTime.x, 1e-3));
  float rel = sat((age - iTime.y) / max(iTime.z, 1e-3));
  float u = position.x * ext;
  float x = position.y * 2.0 - 1.0;
  float s = u * len;
  vec3 P = A + AB * u;
  vec3 toCam = cameraPosition - P;
  vec3 side = cross(D, toCam);
  float sl = length(side);
  side = sl > 1e-5 ? side / sl : vec3(0.0, 1.0, 0.0);
  vec3 up2 = cross(side, D);
  // lateral wiggle (zero at both ends), width taper + pulse, release collapse
  float env = sin(PI * u / max(ext, 1e-3));
  float seed = iDim.w;
  vec2 wg = vec2(sin(s * 2.3 - age * 9.0 + seed * 20.0) + 0.5 * sin(s * 5.1 + age * 13.0), cos(s * 1.7 - age * 7.0 + seed * 9.0)) * iDim.z * env;
  float head = ext * len;
  float W = iDim.x * mix(0.55, 1.0, smoothstep(0.0, iLook.z, s)) * (1.0 - 0.75 * smoothstep(head - iLook.w, head, s) * (1.0 - ext * 0.6));
  W *= (1.0 + 0.12 * sin(age * 38.0 + s * 4.0)) * (1.0 - rel * rel) * (1.0 + 0.5 * exp(-age * 25.0));
  P += side * wg.x + up2 * wg.y + side * x * W * 0.5;
  gl_Position = projectionMatrix * viewMatrix * vec4(P, 1.0);
  vA = vec4(s, x, age, head);
  vB = vec4(rel, seed, iTime.w, iDim.y);
  vCore = vec4(iCore.rgb * iCore.w, iMid.w);
  vMid = vec4(iMid.rgb * iCore.w, iTail.w);
  vTail = vec4(iTail.rgb * iCore.w, 0.0);
  vL = iLook;
}`;

const FRAG = /* glsl */ `
precision highp float;
uniform sampler2D uNoise, uFlow;
varying vec4 vA, vB, vCore, vMid, vTail, vL;
${GLSL_COMMON}
${GLSL_VORONOI}
void main() {
  float s = vA.x, x = vA.y, age = vA.z, head = vA.w;
  float rel = vB.x, seed = vB.y, cw = vB.w;
  int look = int(vB.z + 0.5);
  float noiseAmt = vL.x, scroll = vL.y;
  float ax = abs(x);
  float st = texture2D(uFlow, vec2(s * 0.35 - age * scroll * 0.35, x * 0.45 + seed)).r;
  float st2 = texture2D(uFlow, vec2(s * 0.9 - age * scroll * 0.8, x * 0.9 + seed * 2.0 + 0.3)).r;
  float fb = texture2D(uNoise, vec2(s * 0.45 - age * scroll * 0.15, x * 0.6 + seed)).r;
  float core = exp(-(x * x) / (cw * cw));
  float sheath = exp(-x * x * 2.2) * (1.0 - smoothstep(0.82, 1.0, ax));
  float dens, k, gain = 1.0, flick = 1.0;
  vec3 extra = vec3(0.0);
  float erodeN = fb * 0.6 + st * 0.4;
  float shD = sheath * (0.12 + 0.88 * st * st2) * noiseAmt * 0.9;
  if (look == 1) {
    float f1 = texture2D(uFlow, vec2(s * 0.5 - age * scroll * 0.5, x * 0.6 + age * 0.7) + seed).g;
    float f2 = texture2D(uFlow, vec2(s * 1.3 - age * scroll, x * 1.4 - age * 1.2) + seed * 3.0).g;
    float xe = ax - (f1 * 0.6 + f2 * 0.4 - 0.45) * noiseAmt * 1.2;
    shD = exp(-xe * xe * 3.0) * (0.25 + 1.1 * f1 * f2) * (1.0 - smoothstep(0.85, 1.0, ax));
    erodeN = f1 * 0.6 + fb * 0.4;
  } else if (look == 2) {
    vec3 vo = voronoi(vec2(s * 4.0 - age * scroll * 0.6, x * 2.2 + seed * 7.0));
    float crack = 1.0 - smoothstep(0.0, 0.08, vo.y - vo.x);
    shD = sheath * (0.3 + 0.9 * h11(vo.z * 91.7) + crack * 0.8) * 0.7;
    erodeN = vo.z * 0.7 + fb * 0.3;
    extra += vCore.rgb * pow(h11(vo.z * 37.0 + floor(age * 14.0)), 12.0) * exp(-vo.x * vo.x * 50.0) * 2.5 * sheath;
  } else if (look == 3) {
    float fr = floor(age * 30.0);
    float bolts = 0.0;
    for (int i = 0; i < 3; i++) {
      float fi = float(i);
      float jag = (lnoise(s * 4.0 + fr * 7.0 + fi * 19.0) - 0.5) * 1.1 + (lnoise(s * 15.0 + fr * 3.0 + fi * 5.0) - 0.5) * 0.35;
      float dd = abs(x - jag) * 0.5;
      float on = step(0.3, h11(fr * 1.9 + fi * 4.3 + seed));
      bolts += on * (exp(-dd / 0.012) + exp(-dd / 0.07) * 0.2);
    }
    shD *= 0.35;
    flick = 0.75 + 0.25 * h11(fr * 2.7 + seed);
    extra += vCore.rgb * bolts * 0.9 * (1.0 - rel);
  }
  // energy pulses travelling from the source to the impact
  float pulse = look == 0 || look == 3 ? pow(sat(1.0 - abs(fract(s * 0.45 - age * scroll * 0.2 + seed) - 0.5) * 6.0), 2.0) : 0.0;
  dens = core * (0.7 + 0.5 * st + pulse * 0.8) + shD * (1.0 + pulse);
  k = 0.12 + (1.0 - core) * 0.5 + rel * 0.5 + (1.0 - st2) * 0.12;
  float th = mix(-0.2, 1.05, rel);
  float vis = smoothstep(th - 0.08, th + 0.08, erodeN * 0.7 + core * 0.3);
  // muzzle and head glow
  float ends = exp(-s * 3.0) * 0.5 + exp(-max(head - s, 0.0) * 3.5) * 0.4;
  vec3 rgb = heat3(k - ends * 0.3, vCore.rgb, vMid.rgb, vTail.rgb, 0.4) * gain * flick;
  float a = sat(dens + ends * core) * vis * vCore.a;
  float addF = mix(vMid.a, 1.0, sat(1.0 - k * 1.1));
  if (look == 4) {
    // eclipse: black occluding core, gold corona around it
    float rd = (ax - cw * 1.4) / 0.18;
    float rim = exp(-rd * rd) * (0.5 + 0.8 * st);
    rgb = mix(vTail.rgb, heat3(0.3 + rel * 0.5, vCore.rgb, vMid.rgb, vTail.rgb, 0.4), sat(rim * 2.0 - core));
    a = sat(core * 1.3 + rim + shD * 0.3) * vis * vCore.a;
    addF = sat(rim * 1.5 - core);
  }
  extra *= (1.0 - smoothstep(0.85, 1.0, ax)) * vCore.a;
  if (a <= 0.002 && dot(extra, extra) < 1e-4) discard;
  gl_FragColor = vec4(rgb * a + extra, a * (1.0 - addF));
}`;

/**
 * @param {object} vfx
 * @param {object} shared
 */
export function installBeam(vfx, shared) {
  const { uniforms, textures } = shared;
  const U = { uTime: uniforms.uTime, uTimeReal: uniforms.uTimeReal, uNoise: { value: textures.noise }, uFlow: { value: textures.flow } };
  const layer = new MeshLayer(shared, {
    name: 'beam', capacity: 12, layout: LAYOUT, geometry: gridGeometry(64, 6), lifeAt: 7, renderOrder: RENDER_ORDER.meshBeam,
    material: new THREE.ShaderMaterial({ vertexShader: VERT, fragmentShader: FRAG, uniforms: U, side: THREE.DoubleSide, ...PREMUL }),
  });
  const C = makeColors();
  const va = new THREE.Vector3(), vb = new THREE.Vector3();

  function writeEnds(s) {
    const f = layer.ring.f32, k = s.i * layer.ring.stride;
    f[k] = s.a.x; f[k + 1] = s.a.y; f[k + 2] = s.a.z;
    f[k + 4] = s.b.x; f[k + 5] = s.b.y; f[k + 6] = s.b.z;
    layer.ring.dirty(s.i, 1);
  }
  function sampleEnds(s) {
    let moved = false;
    if (s.srcA) { readEnd(s.srcA, va); if (!va.equals(s.a)) { s.a.copy(va); moved = true; } }
    if (s.srcB) { readEnd(s.srcB, vb); if (!vb.equals(s.b)) { s.b.copy(vb); moved = true; } }
    return moved;
  }
  function readEnd(src, out) {
    if (src.isObject3D) { src.updateWorldMatrix(true, false); return out.setFromMatrixPosition(src.matrixWorld); }
    return toVec3(src, out);
  }
  function release(s, age) {
    const f = layer.ring.f32, k = s.i * layer.ring.stride;
    const rel = f[k + 14];
    if (f[k + 13] > age) f[k + 13] = age;
    layer.setLife(s, Math.min(s.life, f[k + 13] + rel + 1e-3));
  }

  layer.visit = (s, age) => {
    if (s.stopping) { s.stopping = false; release(s, age); if (s.flares) for (const fl of s.flares) fl.stop(); }
    if (sampleEnds(s)) writeEnds(s);
    placeHead(s, age);
  };
  // the impact flare rides the beam head while it extends (same outExpo as the shader)
  function placeHead(s, age) {
    const x = Math.min(1, age / Math.max(s.extend, 1e-3));
    s.head.copy(s.a).lerp(s.b, x >= 1 ? 1 : 1 - Math.pow(2, -10 * x));
  }
  layer.onFree = (s) => { s.srcA = s.srcB = null; if (s.flares) { for (const fl of s.flares) fl.kill(); s.flares = null; } };

  /**
   * Beam between two points. See README "Beam". Returns { setEnds(a, b), kill(), stop(), alive }.
   */
  function beam(opts = {}) {
    const lookName = opts.look || 'energy';
    const look = BEAM_LOOKS[lookName];
    if (!look) throw new Error('vfx.beam: unknown look "' + lookName + '" (have: ' + Object.keys(BEAM_LOOKS).join(', ') + ')');
    const life = opts.life != null && Number.isFinite(opts.life) ? opts.life : Infinity;
    const { slot, handle, f, k } = layer.alloc(life, opts.realtime);
    if (!slot.a) { slot.a = new THREE.Vector3(); slot.b = new THREE.Vector3(); slot.head = new THREE.Vector3(); }
    const isLive = (v) => v && (v.isObject3D || typeof v === 'function');
    slot.srcA = isLive(opts.from) ? opts.from : null;
    slot.srcB = isLive(opts.to) ? opts.to : null;
    if (slot.srcA) readEnd(slot.srcA, slot.a); else toVec3(opts.from, slot.a);
    if (slot.srcB) readEnd(slot.srcB, slot.b); else toVec3(opts.to, slot.b);
    resolveColors(opts, look, C);
    const sc = opt(opts.scale, 1);
    const tp = opt(opts.taper, look.taper);
    const rel = opt(opts.release, look.release);
    const fin = Number.isFinite(life);
    writeEnds(slot);
    f[k + 3] = slot.t0; f[k + 7] = (opts.realtime ? -1 : 1) * (fin ? life : FOREVER);
    f[k + 8] = opt(opts.width, look.width) * sc; f[k + 9] = opt(opts.coreWidth, look.coreWidth); f[k + 10] = opt(opts.wiggle, look.wiggle) * sc; f[k + 11] = shared.rng();
    f[k + 12] = opt(opts.extend, look.extend); f[k + 13] = fin ? Math.max(0, life - rel) : FOREVER; f[k + 14] = rel; f[k + 15] = LOOK_ID[lookName];
    f[k + 16] = C.core.r; f[k + 17] = C.core.g; f[k + 18] = C.core.b; f[k + 19] = opt(opts.intensity, 1);
    f[k + 20] = C.mid.r; f[k + 21] = C.mid.g; f[k + 22] = C.mid.b; f[k + 23] = opt(opts.alpha, 1);
    f[k + 24] = C.tail.r; f[k + 25] = C.tail.g; f[k + 26] = C.tail.b; f[k + 27] = opt(opts.tailAdditive, look.tailAdditive);
    f[k + 28] = opt(opts.noise, look.noise); f[k + 29] = opt(opts.scroll, look.scroll); f[k + 30] = tp[0] * sc; f[k + 31] = tp[1] * sc;
    layer.commit(slot);
    slot.extend = opt(opts.extend, look.extend);
    placeHead(slot, 0);
    slot.flares = null;
    if (opts.flares !== false && vfx.flare) {
      // glow at the muzzle and a bigger one at the impact, following the live ends (killed with the beam)
      const fs = opt(opts.flareSize, 1) * opt(opts.width, look.width) * sc;
      const fl = [
        vfx.flare({ kind: 'glow', follow: () => slot.a, size: fs * 1.5, life: fin ? life : 1e6, color: C.core.toArray(), intensity: 0.25 * opt(opts.intensity, 1), realtime: opts.realtime }),
        vfx.flare({ kind: 'glow', follow: () => slot.head, size: fs * 2.0, life: fin ? life : 1e6, color: C.core.toArray(), intensity: 0.3 * opt(opts.intensity, 1), realtime: opts.realtime }),
      ];
      slot.flares = fl;
    }
    const my = slot.serial;
    handle.setEnds = (a, b) => {
      if (slot.serial !== my) return handle;
      if (a != null) { slot.srcA = isLive(a) ? a : null; if (slot.srcA) readEnd(a, slot.a); else toVec3(a, slot.a); }
      if (b != null) { slot.srcB = isLive(b) ? b : null; if (slot.srcB) readEnd(b, slot.b); else toVec3(b, slot.b); }
      writeEnds(slot);
      return handle;
    };
    return handle;
  }

  return {
    name: 'beam',
    api: { beam, beamLooks: BEAM_LOOKS },
    update() { layer.update(); },
    clear() { layer.clear(); },
    dispose() { layer.dispose(); },
    layer,
  };
}
