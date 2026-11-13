// Atmosphere cards, merged into one draw call (premultiplied alpha: "over" for haze, additive for light):
//   kind 0  distant haze plane: cylindrical billboard, dense near the cloud sea, separates the silhouette layers
//   kind 1  light shaft: axial billboard along the eclipse light, soft edges, dusty streaks
//   kind 2  mist sheet: static horizontal sheet a little above the floor near the wall and over the broken edge
//           (seen from above only: they fade out at grazing angles)
//   kind 3  incense smoke: a thin axial billboard rising from a censer, bending away with the wind
// Cards fade out as the camera gets close so they never read as planes in close-ups.

import * as THREE from 'three';
import { DEG } from '../core/math.js';
import { NOISE, SKY_BASE, FOG } from './glsl.js';
import { LAYOUT, SUN_DIR, SUN_RADIUS } from './config.js';

const VERT = /* glsl */ `
attribute vec3 aC;     // card anchor (base centre / shaft start)
attribute vec4 aK;     // x kind, y seed, z opacity, w length (shafts)
attribute vec3 aD;     // shaft axis
attribute vec2 aSize;  // width, height
uniform float uTime;
uniform vec3 uWind;
varying vec2 vUv;
varying vec4 vK;
varying vec3 vW;
varying float vFade;
void main() {
  vec3 wp;
  float kind = aK.x;
  if (kind < 0.5) {
    vec3 toCam = cameraPosition - aC; toCam.y = 0.0; toCam = normalize(toCam);
    vec3 right = vec3(toCam.z, 0.0, -toCam.x);
    wp = aC + right * position.x * aSize.x + vec3(0.0, position.y * aSize.y, 0.0);
    vUv = vec2(position.x + 0.5, position.y);
  } else if (kind < 1.5) {
    vec3 axis = normalize(aD);
    vec3 mid = aC + axis * aK.w * 0.5;
    vec3 side = normalize(cross(axis, normalize(cameraPosition - mid)));
    float w = aSize.x * (0.6 + 0.8 * position.y);
    wp = aC + axis * position.y * aK.w + side * position.x * w;
    vUv = vec2(position.x + 0.5, position.y);
  } else if (kind < 2.5) {
    wp = position;
    vUv = position.xz;
  } else {
    // smoke: rises straight, then leans with the wind and wanders
    float y = position.y;
    float h = y * aK.w;
    vec3 c = aC + vec3(0.0, h, 0.0);
    c.xz += uWind.xz * (0.12 * h * h) + vec2(sin(uTime * 0.7 + aK.y + h * 1.3), cos(uTime * 0.53 + aK.y * 1.7 + h * 1.1)) * 0.07 * h;
    vec3 toCam = cameraPosition - c; toCam.y = 0.0; toCam = normalize(toCam);
    vec3 right = vec3(toCam.z, 0.0, -toCam.x);
    wp = c + right * position.x * aSize.x * (0.25 + 1.6 * y);
    vUv = vec2(position.x + 0.5, y);
  }
  float cd = length(cameraPosition - wp);
  vFade = kind < 1.5 ? smoothstep(4.0, 12.0, cd) : kind < 2.5 ? smoothstep(1.0, 4.0, cd) : smoothstep(0.8, 2.5, cd);
  vK = aK;
  vW = wp;
  gl_Position = projectionMatrix * viewMatrix * vec4(wp, 1.0);
}`;

const FRAG = /* glsl */ `
${NOISE}
const float SUN_COS_LIMB = ${Math.cos(SUN_RADIUS * 1.12).toFixed(7)};
const float SUN_COS_DISC = ${Math.cos(SUN_RADIUS * 0.97).toFixed(7)};
${SKY_BASE}
${FOG}
uniform float uTime;
uniform vec3 uWind, uShaft, uMist, uFire;
uniform float uCloudY;
varying vec2 vUv;
varying vec4 vK;
varying vec3 vW;
varying float vFade;
void main() {
  float kind = vK.x;
  float seed = vK.y;
  vec3 dir = normalize(vW - cameraPosition);
  vec4 o;
  if (kind < 0.5) {
    float y = vUv.y;
    float n = fbm2(vec2(vUv.x * 5.0 + seed + uTime * 0.01, y * 2.0 - uTime * 0.004), 4);
    float a = pow(1.0 - y, 1.6) * smoothstep(0.0, 0.25, vUv.x) * smoothstep(1.0, 0.75, vUv.x);
    a *= 0.45 + 0.75 * n;
    vec3 c = skyBase(vec3(dir.x, max(dir.y, 0.0) * 0.5 + 0.006, dir.z)) * 1.08;
    a = clamp(a * vK.z, 0.0, 1.0) * vFade;
    // never veil the black disc: the eclipse must read as a hole in the sky, not a hazy ball
    a *= 1.0 - smoothstep(SUN_COS_LIMB, SUN_COS_DISC, dot(dir, uSunDir));
    o = vec4(moodApply(c, 1.0) * a, a);
  } else if (kind < 1.5) {
    float x = abs(vUv.x - 0.5) * 2.0;
    float y = vUv.y;
    float streak = fbm2(vec2(vUv.x * 7.0 + seed, y * 1.2 - uTime * 0.02), 3);
    float dust = vnoise(vec2(vUv.x * 30.0, y * 14.0 - uTime * 0.15) + seed);
    float a = exp(-x * x * 3.5) * smoothstep(0.0, 0.12, y) * smoothstep(1.0, 0.35, y);
    a *= (0.35 + 0.9 * streak) * (0.85 + 0.3 * dust);
    float view = pow(max(dot(dir, uSunDir), 0.0), 2.0) * 0.7 + 0.3;
    a *= vK.z * vFade * view;
    o = vec4(moodApply(uShaft, 0.6) * a, 0.0);
  } else if (kind > 2.5) {
    float x = (vUv.x - 0.5) * 2.0, y = vUv.y;
    float n = fbm2(vec2(x * 1.4 + seed, y * 3.2 - uTime * 0.32), 4);
    float n2 = vnoise(vec2(x * 3.0 + seed * 2.0, y * 9.0 - uTime * 0.7));
    float xd = x + (n - 0.5) * 1.1 * (0.3 + y);
    float core = exp(-xd * xd * 5.0);
    float a = core * smoothstep(0.0, 0.05, y) * pow(1.0 - y, 1.3) * (0.4 + 0.9 * n) * (0.75 + 0.5 * n2);
    a = clamp(a * vK.z, 0.0, 0.8) * vFade;
    // pale against the dark, warmed a little at the root by the embers below
    vec3 c = uFogNear * 5.5 + uSunHalo * 0.9 + uFire * 0.05 * exp(-y * 9.0);
    o = vec4(moodApply(c, 1.0) * a, a);
  } else {
    vec2 p = vW.xz;
    vec2 w = uWind.xz * uTime * 0.12;
    float n = fbm2(p * 0.22 - w * 0.22 + seed, 4);
    float n2 = vnoise(p * 0.9 - w * 0.6 + seed * 3.0);
    float r = length(p);
    float a = smoothstep(0.42, 0.78, n * 0.8 + n2 * 0.3);
    a *= smoothstep(10.5, 13.5, r);
    a *= clamp(vK.w, 0.0, 1.0) > 0.5 ? smoothstep(31.0, 24.0, r) : smoothstep(15.7, 15.2, r);
    a *= vK.z * vFade;
    // a plane seen edge-on collapses into a hard horizontal line (a "glass shelf"), so the sheets only show from
    // above (crane / overview shots) and fade out at fight-camera grazing angles
    a *= smoothstep(0.08, 0.3, abs(dir.y)) * 1.6;
    a = clamp(a, 0.0, 0.85);
    vec3 c = uFogNear * 1.6 + uSunHalo * pow(max(dot(dir, uSunDir), 0.0), 6.0) * 0.8 + uMist;
    o = vec4(moodApply(c, 1.0) * a, a);
  }
  gl_FragColor = o;
}`;

/**
 * @param {Array<{pos: THREE.Vector3, h: number, w: number, k: number}>} [smokes] incense smoke sources
 * @returns {THREE.Mesh}
 */
export function createAtmosphere(U, rng, tier, smokes = []) {
  const pos = [], aC = [], aK = [], aD = [], aSize = [], idx = [];
  const quad = (c, kind, seed, op, w, h, d = [0, 1, 0], len = 0) => {
    const b = pos.length / 3;
    for (const [x, y] of [[-0.5, 0], [0.5, 0], [0.5, 1], [-0.5, 1]]) {
      pos.push(x, y, 0); aC.push(c.x, c.y, c.z); aK.push(kind, seed, op, len); aD.push(d[0], d[1], d[2]); aSize.push(w, h);
    }
    idx.push(b, b + 1, b + 2, b, b + 2, b + 3);
  };
  const ring = (deg, dist, y) => new THREE.Vector3(Math.sin(deg * DEG) * dist, y, -Math.cos(deg * DEG) * dist);

  // far to near so in-mesh order composites correctly
  const cy = LAYOUT.cloudY;
  const haze = [
    [0, 330, 360, 46, 0.55], [-60, 260, 260, 40, 0.5], [62, 280, 280, 42, 0.5],
    [-20, 150, 190, 30, 0.42], [28, 160, 200, 30, 0.42], [-75, 120, 170, 26, 0.38], [80, 125, 170, 26, 0.38],
    [-5, 70, 120, 18, 0.32], [-40, 60, 90, 14, 0.28], [42, 62, 90, 14, 0.28],
  ];
  for (const [az, d, w, h, op] of haze) quad(ring(az, d, cy - 2), 0, rng.range(0, 40), op, w, h);

  // light shafts: corona light falling between the gallery columns and the pines onto the terrace's flanks. Steeper than the
  // 6-degree eclipse (a beam along the real sun line would run flat across the sky toward the camera) and kept off
  // the fight line and the vista.
  const shaftDir = new THREE.Vector3(-SUN_DIR.x, -0.42, -SUN_DIR.z).normalize();
  const shafts = [[-33, 8.5, 3.0], [33, 8.0, 2.8], [-49, 9.5, 2.4], [49, 8.5, 2.4], [-65, 8.5, 2.0], [64, 8.0, 2.0], [-80, 8.0, 1.8]];
  for (const [deg, y, w] of shafts.slice(0, tier.shafts)) {
    const start = ring(deg, LAYOUT.pillarR + 1.5, y);
    quad(start, 1, rng.range(0, 40), 0.065, w, 1, [shaftDir.x, shaftDir.y, shaftDir.z], 17);
  }

  // mist sheets (static world-space grids): around the wall base and pouring over the broken edge
  if (tier.fogCards) {
    const sheet = (y, r0, r1, th0, th1, seg, op, outer) => {
      const b = pos.length / 3;
      const rows = 4;
      const seed = rng.range(0, 40);
      for (let j = 0; j <= rows; j++) for (let i = 0; i <= seg; i++) {
        const th = th0 + (th1 - th0) * (i / seg);
        const r = r0 + (r1 - r0) * (j / rows);
        const yy = outer ? y - (r - r0) * 0.22 : y;
        pos.push(Math.sin(th) * r, yy, -Math.cos(th) * r);
        aC.push(0, 0, 0); aK.push(2, seed, op, outer ? 1 : 0); aD.push(0, 1, 0); aSize.push(0, 0);
      }
      for (let j = 0; j < rows; j++) for (let i = 0; i < seg; i++) {
        const a = b + j * (seg + 1) + i, c = a + seg + 1;
        idx.push(a, c, a + 1, a + 1, c, c + 1);
      }
    };
    const T = LAYOUT.thetaMax;
    sheet(0.3, 15.4, 30, -LAYOUT.gap - 8 * DEG, LAYOUT.gap + 8 * DEG, 24, 0.6, true);
    sheet(0.22, 10.5, 15.6, -T, T, 48, 0.6, false);
    sheet(0.6, 11.5, 15.6, -T, T, 48, 0.45, false);
    sheet(1.15, 12.5, 15.6, -T, T, 48, 0.3, false);
  }

  // incense smoke: tall thin strips (8 rows so they can bend)
  for (const sm of smokes) {
    const b = pos.length / 3, rows = 8, seed = rng.range(0, 40);
    for (let j = 0; j <= rows; j++) for (const x of [-0.5, 0.5]) {
      pos.push(x, j / rows, 0); aC.push(sm.pos.x, sm.pos.y, sm.pos.z); aK.push(3, seed, 0.5 * sm.k, sm.h); aD.push(0, 1, 0); aSize.push(sm.w, 1);
    }
    for (let j = 0; j < rows; j++) { const a = b + j * 2; idx.push(a, a + 1, a + 3, a, a + 3, a + 2); }
  }

  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('aC', new THREE.Float32BufferAttribute(aC, 3));
  g.setAttribute('aK', new THREE.Float32BufferAttribute(aK, 4));
  g.setAttribute('aD', new THREE.Float32BufferAttribute(aD, 3));
  g.setAttribute('aSize', new THREE.Float32BufferAttribute(aSize, 2));
  g.setIndex(idx);
  const mat = new THREE.ShaderMaterial({
    name: 'env.atmosphere',
    vertexShader: VERT,
    fragmentShader: FRAG,
    uniforms: {
      uZenith: U.uZenith, uSkyMid: U.uSkyMid, uHorizon: U.uHorizon, uGlow: U.uGlow, uSunHalo: U.uSunHalo, uSunDir: U.uSunDir,
      uFogP: U.uFogP, uFogNear: U.uFogNear, uMood: U.uMood, uTime: U.uTime, uWind: U.uWind,
      uShaft: { value: new THREE.Color(0.32, 0.38, 0.5) },
      uMist: { value: new THREE.Color(0.012, 0.015, 0.022) },
      uFire: { value: new THREE.Color(1.0, 0.5, 0.18) },
      uCloudY: { value: cy },
    },
    transparent: true,
    depthWrite: false,
    blending: THREE.CustomBlending,
    blendSrc: THREE.OneFactor,
    blendDst: THREE.OneMinusSrcAlphaFactor,
    side: THREE.DoubleSide,
  });
  const mesh = new THREE.Mesh(g, mat);
  mesh.frustumCulled = false;
  mesh.name = 'env.atmosphere';
  mesh.renderOrder = 5;
  return mesh;
}
