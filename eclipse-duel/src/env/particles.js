// Ambient particles, one instanced draw call, motion fully analytic in the vertex shader (no CPU work per frame):
//   type 0  ash flakes drifting down through the arena volume (premultiplied "over"), tumbling glints
//   type 1  stray embers carried across the arena by the wind (HDR additive, velocity-stretched)
//   type 2  brazier embers rising from the four bowls and cooling as they climb
// Floor pulses (env.pulse) push nearby particles outward with the ring.

import * as THREE from 'three';

const VERT = /* glsl */ `
attribute vec4 aSeed;  // 4 randoms
attribute vec4 aInfo;  // x type, y size, z life, w brazier index
uniform float uTime;
uniform vec3 uWind;
uniform vec4 uBrazTop[4];
uniform vec4 uPulseP[4];
uniform vec4 uPulseC[4];
varying vec2 vUv;
varying vec4 vCol;
varying float vType;
vec3 boxWrap(vec3 p, vec3 mn, vec3 sz) { return mn + mod(p - mn, sz); }
void main() {
  float type = aInfo.x;
  float t = uTime;
  vec3 p, vel;
  float alpha = 1.0;
  vec4 col;
  if (type < 0.5) {
    vec3 mn = vec3(-19.0, -0.2, -22.0), sz = vec3(38.0, 13.0, 33.0);
    vel = vec3(uWind.x * 0.45, -0.28 - aSeed.w * 0.22, uWind.z * 0.45);
    vec3 sw = vec3(sin(t * 0.37 + aSeed.x * 40.0), sin(t * 0.61 + aSeed.y * 30.0) * 0.5, cos(t * 0.29 + aSeed.z * 50.0)) * 0.9;
    p = boxWrap(mn + aSeed.xyz * sz + vel * t + sw, mn, sz);
    vec3 q = (p - mn) / sz;
    alpha = smoothstep(0.0, 0.05, q.x) * smoothstep(1.0, 0.95, q.x) * smoothstep(0.0, 0.04, q.y) * smoothstep(1.0, 0.85, q.y) * smoothstep(0.0, 0.05, q.z) * smoothstep(1.0, 0.95, q.z);
    float glint = 0.35 + 0.65 * abs(sin(t * (1.5 + aSeed.w * 3.0) + aSeed.x * 20.0));
    col = vec4(vec3(0.075, 0.074, 0.078) * glint, 0.85 * alpha);
  } else if (type < 1.5) {
    float life = aInfo.z;
    float ph = fract(t / life + aSeed.w);
    float age = ph * life;
    vec3 start = vec3(-18.0 + aSeed.x * 34.0, 0.2 + aSeed.y * 5.0, -17.0 + aSeed.z * 21.0);
    vel = vec3(uWind.x * 1.2, 0.18 + aSeed.y * 0.25, uWind.z * 1.2) + vec3(sin(t * 1.7 + aSeed.x * 30.0), sin(t * 2.3 + aSeed.y * 20.0), cos(t * 1.9 + aSeed.z * 25.0)) * 0.35;
    p = start + vec3(uWind.x * 1.2, 0.18 + aSeed.y * 0.25, uWind.z * 1.2) * age + vec3(sin(age * 1.3 + aSeed.x * 30.0), sin(age * 2.0 + aSeed.y * 9.0) * 0.4, cos(age * 1.1 + aSeed.z * 25.0)) * 0.6;
    alpha = sin(ph * 3.14159);
    float fl = 0.55 + 0.45 * sin(t * (9.0 + aSeed.x * 8.0) + aSeed.y * 40.0);
    col = vec4(vec3(3.2, 0.9, 0.18) * fl * alpha, 0.0);
  } else {
    vec4 B = uBrazTop[int(aInfo.w)];
    float life = aInfo.z;
    float ph = fract(t / life + aSeed.w);
    float age = ph * life;
    float rise = 1.3 + aSeed.x * 1.4;
    vec3 drift = uWind * (0.25 + 0.2 * age);
    p = B.xyz + vec3((aSeed.y - 0.5) * 0.7, 0.1, (aSeed.z - 0.5) * 0.7)
      + vec3(0.0, rise * age - 0.12 * age * age, 0.0) + drift * age
      + vec3(sin(age * 3.0 + aSeed.x * 20.0), 0.0, cos(age * 2.6 + aSeed.y * 20.0)) * 0.22 * age;
    vel = vec3(0.0, rise - 0.24 * age, 0.0) + drift + vec3(cos(age * 3.0 + aSeed.x * 20.0) * 0.66, 0.0, -sin(age * 2.6 + aSeed.y * 20.0) * 0.57) * age;
    float cool = ph;
    alpha = smoothstep(0.0, 0.05, ph) * (1.0 - smoothstep(0.55, 1.0, ph));
    float fl = 0.6 + 0.4 * sin(t * (11.0 + aSeed.x * 9.0) + aSeed.z * 30.0);
    vec3 c = mix(vec3(6.0, 2.6, 0.6), vec3(1.4, 0.18, 0.03), cool);
    col = vec4(c * fl * alpha * B.w, 0.0);
  }
  // floor pulses shove particles outward as the ring passes
  for (int i = 0; i < 4; i++) {
    vec4 P = uPulseP[i];
    if (P.w <= 0.0) continue;
    vec2 d = p.xz - P.xy;
    float dist = length(d) + 1e-3;
    float R = P.z * uPulseC[i].w;
    float wave = exp(-pow((dist - R) / 1.6, 2.0)) * exp(-P.z * 1.2) * P.w * exp(-p.y * 0.25);
    p.xz += d / dist * wave * 0.9;
    p.y += wave * 0.4;
  }
  vec4 mv = viewMatrix * vec4(p, 1.0);
  float size = aInfo.y;
  vec2 corner = position.xy;
  vec2 off;
  if (type < 0.5) {
    float a = t * (0.6 + aSeed.w) + aSeed.x * 6.28;
    off = mat2(cos(a), sin(a), -sin(a), cos(a)) * corner * vec2(size, size * 0.6);
  } else {
    vec3 vv = (viewMatrix * vec4(vel, 0.0)).xyz;
    vec2 sd = vv.xy / max(-mv.z, 0.5);
    float sl = length(sd);
    vec2 ax = sl > 1e-4 ? sd / sl : vec2(0.0, 1.0);
    float stretch = 1.0 + min(sl * 2.2, 6.0);
    off = ax * corner.y * size * stretch + vec2(-ax.y, ax.x) * corner.x * size;
  }
  mv.xy += off;
  float near = smoothstep(0.8, 2.5, -mv.z);
  vCol = col * near;
  vType = type;
  vUv = corner;
  gl_Position = projectionMatrix * mv;
}`;

const FRAG = /* glsl */ `
uniform vec4 uMood;
varying vec2 vUv;
varying vec4 vCol;
varying float vType;
void main() {
  float r = length(vUv) * 2.0;
  float a = smoothstep(1.0, 0.2, r);
  float d = uMood.a;
  vec3 c = vCol.rgb * a * (vType < 0.5 ? (1.0 - 0.8 * d) : (1.0 - 0.35 * d));
  gl_FragColor = vec4(c * (vType < 0.5 ? vCol.a : 1.0), vCol.a * a);
}`;

/** @returns {THREE.Mesh} */
export function createParticles(U, rng, tier, brazierTops, floorUniforms) {
  const quad = new THREE.PlaneGeometry(1, 1);
  const g = new THREE.InstancedBufferGeometry();
  g.index = quad.index;
  g.setAttribute('position', quad.attributes.position);
  const seeds = [], info = [];
  const n0 = tier.ash, nE = tier.embers;
  const nAmb = Math.round(nE * 0.35), nBraz = nE - nAmb;
  for (let i = 0; i < n0; i++) { seeds.push(rng(), rng(), rng(), rng()); info.push(0, rng.range(0.018, 0.05), 0, 0); }
  for (let i = 0; i < nAmb; i++) { seeds.push(rng(), rng(), rng(), rng()); info.push(1, rng.range(0.012, 0.024), rng.range(5, 9), 0); }
  for (let i = 0; i < nBraz; i++) { seeds.push(rng(), rng(), rng(), rng()); info.push(2, rng.range(0.01, 0.022), rng.range(1.6, 3.4), i % brazierTops.length); }
  g.setAttribute('aSeed', new THREE.InstancedBufferAttribute(new Float32Array(seeds), 4));
  g.setAttribute('aInfo', new THREE.InstancedBufferAttribute(new Float32Array(info), 4));
  g.instanceCount = n0 + nE;
  const tops = brazierTops.map((b) => new THREE.Vector4(b.x, b.y + 0.35, b.z, 1));
  while (tops.length < 4) tops.push(new THREE.Vector4(0, -50, 0, 0));
  const mat = new THREE.ShaderMaterial({
    name: 'env.particles',
    vertexShader: VERT,
    fragmentShader: FRAG,
    uniforms: { uTime: U.uTime, uWind: U.uWind, uMood: U.uMood, uBrazTop: { value: tops }, uPulseP: floorUniforms.uPulseP, uPulseC: floorUniforms.uPulseC },
    transparent: true,
    depthWrite: false,
    blending: THREE.CustomBlending,
    blendSrc: THREE.OneFactor,
    blendDst: THREE.OneMinusSrcAlphaFactor,
  });
  const mesh = new THREE.Mesh(g, mat);
  mesh.frustumCulled = false;
  mesh.name = 'env.particles';
  mesh.renderOrder = 40;
  return mesh;
}
