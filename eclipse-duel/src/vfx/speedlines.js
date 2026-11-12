// vfx.speedlines: full-screen anime speed / focus lines, camera attached (built directly in clip space).
//   focus        radial wedges converging on a screen point (or a world position projected every frame), leaving a
//                clear centre; drawn on a screen-space annulus so the clear centre costs no fill
//   directional  parallel streaks across the screen along a screen direction, scrolling
// Every line has its own random width, start radius / length and brightness, re-drawn ("boiling") at an anime frame
// rate. 'light' lines add HDR light; 'ink' lines are dark and alpha blended (manga). ONE draw call for all.

import * as THREE from 'three';
import { MeshLayer, gridGeometry, PREMUL, opt } from './meshfx.js';
import { GLSL_COMMON, CULL } from './glsl.js';
import { toVec3, toColor } from './util.js';

const LAYOUT = { iCen: 4, iLook: 4, iDir: 4, iCol: 4, iEnv: 4 };

const VERT = /* glsl */ `
precision highp float;
uniform float uTime, uTimeReal;
attribute vec4 iCen, iLook, iDir, iCol, iEnv;
varying vec4 vA;   // focus: angle (0..1), radius (screen half-heights) | directional: screen x, y (half-heights)
varying vec4 vB;   // age, life, mode, density
varying vec4 vC, vD, vE;
${GLSL_COMMON}
void main() {
  float life = abs(iCen.w);
  float age = (iCen.w < 0.0 ? uTimeReal : uTime) - iCen.z;
  if (life <= 0.0 || age < 0.0 || age >= life) { ${CULL} }
  float aspect = projectionMatrix[1][1] / projectionMatrix[0][0];
  vec2 c = iCen.xy;                 // centre in NDC
  vec2 ndc;
  if (iLook.x < 0.5) {
    float a = position.x * TAU;
    float r = mix(iLook.z, 2.4 + length(c * vec2(aspect, 1.0)), position.y);
    ndc = c + vec2(cos(a) / aspect, sin(a)) * r;
    vA = vec4(position.x, r, 0.0, 0.0);
  } else {
    ndc = position.xy * 2.0 - 1.0;
    vA = vec4(ndc.x * aspect, ndc.y, 0.0, 0.0);
  }
  gl_Position = vec4(ndc, 0.0, 1.0);
  vB = vec4(age, life, iLook.x, iLook.y);
  vC = vec4(iLook.z, iLook.w, iDir.z, iDir.w);   // inner radius, boil rate, speed, seed
  vD = iCol;
  vE = vec4(iEnv.xy, iEnv.z, iEnv.w);            // attack, release, ink, thickness
  if (iLook.x > 0.5) vC.xy = iDir.xy;            // directional: screen direction
}`;

const FRAG = /* glsl */ `
precision highp float;
varying vec4 vA, vB, vC, vD, vE;
${GLSL_COMMON}
void main() {
  float age = vB.x, life = vB.y, N = vB.w, seed = vC.w;
  float env = (vE.x > 0.0 ? sat(age / vE.x) : 1.0) * (1.0 - smoothstep(life - vE.y, life, age));
  float thick = vE.w;
  float line = 0.0;
  if (vB.z < 0.5) {
    // focus: angular bins, each holding at most one wedge; re-randomised every boil frame
    float boil = floor(age * vC.y + 0.5);
    float x = vA.x * N;
    float bin = floor(x), fx = fract(x);
    float r = vA.y;
    vec2 k = vec2(bin, boil) + seed;
    float h1 = h12(k), h2 = h12(k + 17.31), h3 = h12(k + 41.7), h4 = h12(k + 73.1);
    float on = step(0.45, h1);
    float r0 = vC.x + h3 * h3 * 0.75;               // where this line starts (its thin inner end)
    float w = (0.035 + 0.22 * h2 * h2 * h2) * thick * smoothstep(r0, r0 + 0.3 + 0.5 * h4, r);
    float cpos = 0.3 + 0.4 * h4;
    float d = abs(fx - cpos);
    float aa = fwidth(x) * 1.2 + 1e-4;
    line = on * (1.0 - smoothstep(w - aa, w + aa, d)) * (0.25 + 0.75 * h3 * h3) * smoothstep(r0, r0 + 0.5, r);
  } else {
    // directional: streak segments scrolling along the direction
    vec2 dir = normalize(vC.xy + vec2(1e-5, 0.0));
    vec2 nrm = vec2(-dir.y, dir.x);
    vec2 p = vA.xy;
    float across = dot(p, nrm) * N * 0.5;
    float bin = floor(across), fx = fract(across);
    float h1 = h11(bin * 1.37 + seed), h2 = h11(bin * 7.1 + seed), h3 = h11(bin * 3.3 + seed * 2.0);
    float along = dot(p, dir) + age * vC.z * (0.6 + 0.8 * h2) + h3 * 9.0;
    float per = 1.4 + 1.6 * h1;
    float m = fract(along / per);
    float len = 0.25 + 0.5 * h2;
    float seg = smoothstep(0.0, 0.1, m) * (1.0 - smoothstep(len - 0.25 * len, len, m));
    float w = (0.04 + 0.16 * h1 * h1) * thick;
    float aa = fwidth(across) * 1.2 + 1e-4;
    line = step(0.4, h3) * seg * (1.0 - smoothstep(w - aa, w + aa, abs(fx - 0.5)));
  }
  float a = line * env * vD.w;
  if (a <= 0.002) discard;
  if (vE.z > 0.5) gl_FragColor = vec4(vD.rgb * a, a);
  else gl_FragColor = vec4(vD.rgb * a, 0.0);
}`;

/**
 * @param {object} vfx
 * @param {object} shared
 */
export function installSpeedlines(vfx, shared) {
  const { ctx, uniforms } = shared;
  const layer = new MeshLayer(shared, {
    name: 'speedlines', capacity: 4, layout: LAYOUT, geometry: gridGeometry(96, 3), lifeAt: 3, renderOrder: 40,
    material: new THREE.ShaderMaterial({ vertexShader: VERT, fragmentShader: FRAG, uniforms: { uTime: uniforms.uTime, uTimeReal: uniforms.uTimeReal }, ...PREMUL, depthTest: false, side: THREE.DoubleSide }),
  });
  const v = new THREE.Vector3(), col = new THREE.Color();
  // a focus centre that tracks a world position is re-projected every frame
  layer.visit = (s, age) => {
    if (s.stopping) {
      s.stopping = false;
      const f = layer.ring.f32, k = s.i * layer.ring.stride;
      layer.setLife(s, Math.min(s.life, age + f[k + 17]));
    }
    if (s.track) project(s);
  };
  function project(s) {
    toVec3(s.track, v).project(ctx.camera);
    const f = layer.ring.f32, k = s.i * layer.ring.stride;
    f[k] = Math.max(-1.5, Math.min(1.5, v.x)); f[k + 1] = Math.max(-1.5, Math.min(1.5, v.y));
    layer.ring.dirty(s.i, 1);
  }

  /**
   * Full-screen speed / focus lines. See README "Speedlines". Returns { kill(), stop(), alive }.
   */
  function speedlines(opts = {}) {
    const mode = opts.mode === 'directional' ? 1 : 0;
    const life = opt(opts.life, 0.45);
    const { slot, handle, f, k } = layer.alloc(life, opts.realtime);
    const ink = opts.style === 'ink';
    toColor(opt(opts.color, ink ? [0.004, 0.004, 0.006] : [1.25, 1.22, 1.18]), col);
    const scr = opt(opts.screen, [0.5, 0.5]);
    slot.track = opts.pos != null ? opts.pos : null;
    f[k] = scr[0] * 2 - 1; f[k + 1] = scr[1] * 2 - 1; f[k + 2] = slot.t0; f[k + 3] = (opts.realtime ? -1 : 1) * (Number.isFinite(life) ? life : 1e6);
    f[k + 4] = mode; f[k + 5] = opt(opts.density, mode ? 26 : 150); f[k + 6] = opt(opts.inner, 0.55); f[k + 7] = opt(opts.boil, 20);
    const d = opt(opts.dir, [1, 0]);
    f[k + 8] = d[0]; f[k + 9] = d[1]; f[k + 10] = opt(opts.speed, 6); f[k + 11] = shared.rng() * 100;
    f[k + 12] = col.r; f[k + 13] = col.g; f[k + 14] = col.b; f[k + 15] = opt(opts.intensity, 1) * (ink ? opt(opts.alpha, 0.85) : 1);
    f[k + 16] = opt(opts.attack, 0.03); f[k + 17] = opt(opts.release, 0.18); f[k + 18] = ink ? 1 : 0; f[k + 19] = opt(opts.thickness, 1);
    if (slot.track) project(slot);
    layer.commit(slot);
    return handle;
  }

  return {
    name: 'speedlines',
    api: { speedlines },
    update() { layer.update(); },
    clear() { layer.clear(); },
    dispose() { layer.dispose(); },
    layer,
  };
}
