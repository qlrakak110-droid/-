// Far layer: the sea of cloud below the cliff, jagged rock spires in layered aerial perspective, and two colossal
// hooded guardian statues (weathered, broken) standing in the clouds either side of the eclipse.
// Far silhouettes use one cheap shader (sky ambient + eclipse rim + sky-matched haze): one draw call for all of them.

import * as THREE from 'three';
import { DEG } from '../core/math.js';
import { NOISE, SKY_BASE, FOG } from './glsl.js';
import { Builder, latheGrid, addAll, trs, noise3, fbm3, flatNormals, chamferBox } from './geometry.js';
import { LAYOUT } from './config.js';

const FAR_VERT = /* glsl */ `
attribute vec3 color;
varying vec3 vW; varying vec3 vN; varying vec3 vC;
void main() {
  vec4 w = modelMatrix * vec4(position, 1.0);
  vW = w.xyz; vN = normalize(mat3(modelMatrix) * normal); vC = color;
  gl_Position = projectionMatrix * viewMatrix * w;
}`;
const FAR_FRAG = /* glsl */ `
${SKY_BASE}
${FOG}
uniform vec3 uFarCol, uCorona, uRim, uKeyDir;
uniform float uCloudY;
varying vec3 vW; varying vec3 vN; varying vec3 vC;
void main() {
  vec3 n = normalize(vN);
  vec3 toCam = cameraPosition - vW;
  float dist = length(toCam);
  vec3 v = toCam / dist;
  float ndl = dot(n, uSunDir);
  vec3 col = uFarCol * vC * (0.45 + 0.55 * max(n.y * 0.5 + 0.5, 0.0));
  float fres = pow(1.0 - max(dot(n, v), 0.0), 2.5);
  col += uRim * max(ndl, 0.0) * (0.04 + 0.9 * fres) * smoothstep(-25.0, 10.0, vW.y);
  col += uGlow * 0.25 * smoothstep(uCloudY + 25.0, uCloudY, vW.y) * vC;
  col += uFarCol * vC * 1.6 * max(dot(n, uKeyDir), 0.0);
  vec3 dir = -v;
  float f = 1.0 - exp(-dist * 0.0042);
  f = max(f, smoothstep(uCloudY + 9.0, uCloudY - 1.0, vW.y));
  vec3 fc = skyBase(vec3(dir.x, max(dir.y, 0.003), dir.z));
  col = mix(col, fc, clamp(f, 0.0, 0.97));
  gl_FragColor = vec4(moodApply(col, 1.0), 1.0);
}`;

const CLOUD_VERT = /* glsl */ `
varying vec3 vW;
void main() { vec4 w = modelMatrix * vec4(position, 1.0); vW = w.xyz; gl_Position = projectionMatrix * viewMatrix * w; }`;
const CLOUD_FRAG = /* glsl */ `
${NOISE}
${SKY_BASE}
${FOG}
uniform float uTime;
uniform vec3 uWind, uCloudDark, uCloudLit, uCorona;
varying vec3 vW;
#ifndef OCT
#define OCT 4
#endif
float cl(vec2 p) { return fbm2(p, OCT); }
void main() {
  vec3 toP = vW - cameraPosition;
  float dist = length(toP);
  vec3 dir = toP / dist;
  vec2 p = vW.xz * 0.011 + uWind.xz * uTime * 0.0015;
  float h = cl(p);
  float h2 = vnoise(p * 4.0 - uWind.xz * uTime * 0.003);
  float hh = h * 0.8 + h2 * 0.2;
  vec2 e = vec2(0.06, 0.0);
  vec2 g = vec2(cl(p + e.xy) - h, cl(p + e.yx) - h) / e.x;
  vec3 n = normalize(vec3(-g.x * 0.35, 1.0, -g.y * 0.35));
  float sun = max(dot(n, uSunDir), 0.0);
  float fwd = pow(max(dot(dir, uSunDir), 0.0), 5.0);
  vec3 col = mix(uCloudDark, uCloudLit, smoothstep(0.3, 0.75, hh));
  col += uCorona * 0.05 * fwd * (0.3 + sun) * smoothstep(0.4, 0.8, hh);
  col += uGlow * 0.18 * smoothstep(0.35, 0.8, hh);
  float f = 1.0 - exp(-dist * 0.0042);
  vec3 fc = skyBase(vec3(dir.x, 0.006, dir.z));
  col = mix(col, fc, clamp(f, 0.0, 1.0));
  gl_FragColor = vec4(moodApply(col, 1.0), 1.0);
}`;

/** Rotate a tube (lathe along +Y from 0..len) so it runs from a to b. */
function tubeMatrix(a, b) {
  const d = b.clone().sub(a);
  const len = d.length();
  const q = new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(0, 1, 0), d.normalize());
  return { m: new THREE.Matrix4().compose(a, q, new THREE.Vector3(1, 1, 1)), len };
}

function statue(B, rng, mirror, damage, place) {
  const col = (k) => (p, n, o) => { const v = k * (0.75 + 0.5 * noise3(p.x * 0.08, p.y * 0.08, p.z * 0.08)); o[0] = v; o[1] = v; o[2] = v * 1.02; };
  const M = (m) => place.clone().multiply(m);
  const s = mirror;
  const flat = (parts) => parts.map((g) => flatNormals(g.index ? g.toNonIndexed() : g));
  // robe: wide hem, folds deepening toward the ground, broad mantle at the shoulders
  const prof = [[0, 5.4], [3, 4.6], [9, 4.0], [15, 3.75], [20, 4.0], [23.5, 4.6], [26.2, 5.3], [27.6, 4.2], [28.6, 2.6]];
  const lerpProf = (y) => { for (let i = 1; i < prof.length; i++) if (y <= prof[i][0]) { const a = prof[i - 1], b = prof[i]; const t = (y - a[0]) / (b[0] - a[0]); return a[1] + (b[1] - a[1]) * t; } return prof[prof.length - 1][1]; };
  addAll(B, flat(latheGrid({
    rows: 18, segs: 22, squash: 0.64,
    profile: (t) => { const y = t * 28.6; return [lerpProf(y), y]; },
    rmod: (phi, y) => {
      const foldAmt = 0.09 * (1 - y / 30);
      let m = 1 + foldAmt * Math.sin(phi * 9 + 1.3 * noise3(y * 0.2, phi, 0)) + (noise3(Math.cos(phi) * 3, y * 0.4, Math.sin(phi) * 3) - 0.5) * 0.08;
      if (damage.shoulder && y > 22 && y < 28 && Math.cos(phi - (s > 0 ? 0 : Math.PI)) > 0.7) m *= 0.78;
      return m;
    },
    capTop: true,
  })), M(new THREE.Matrix4()), { color: col(1) });
  // hood, bowed forward
  const hood = latheGrid({
    rows: 10, segs: 18, squash: 1.0,
    profile: (t) => { const y = t * 6.6; const r = t < 0.45 ? 2.75 - t * 0.6 : 2.48 * Math.cos((t - 0.45) / 0.55 * Math.PI * 0.5) + 0.12; return [r, y]; },
    rmod: (phi, y) => (damage.hood && y > 4.6 ? 0.55 : 1) * (1 + (noise3(Math.cos(phi) * 2, y, Math.sin(phi) * 2) - 0.5) * 0.08),
    capTop: true,
  });
  addAll(B, flat(hood), M(trs(0, 27.6, 0.5, 0, 0.32, 0)), { color: col(1) });
  // shadowed face opening
  const face = new THREE.SphereGeometry(1.25, 10, 8);
  B.add(flatNormals(face.toNonIndexed()), M(trs(0, 30.0, 2.6, 0, 0.32, 0, 1.0, 1.35, 0.55)), { color: [0.18, 0.18, 0.2] });
  // arms: shoulder -> elbow -> hands on the pommel
  for (const side of [-1, 1]) {
    if (damage.arm === side) {
      // broken stump at the elbow
      const { m, len } = tubeMatrix(new THREE.Vector3(side * 4.3, 25.6, 0.6), new THREE.Vector3(side * 3.9, 21.8, 1.8));
      addAll(B, flat(latheGrid({ rows: 3, segs: 9, profile: (t) => [1.5 - t * 0.2, t * len], topY: (phi) => len - Math.abs(noise3(Math.cos(phi), Math.sin(phi), 4)) * 1.2, capTop: len - 0.6 })), M(m), { color: col(0.95) });
      continue;
    }
    const sh = new THREE.Vector3(side * 4.4, 25.4, 0.5), el = new THREE.Vector3(side * 5.0, 19.6, 1.9), ha = new THREE.Vector3(side * 0.9, 21.4, 3.9);
    for (const [a, b, r0, r1] of [[sh, el, 1.6, 1.45], [el, ha, 1.45, 1.1]]) {
      const { m, len } = tubeMatrix(a, b);
      addAll(B, flat(latheGrid({ rows: 3, segs: 9, profile: (t) => [r0 + (r1 - r0) * t, t * len], capTop: true, capBottom: true })), M(m), { color: col(0.95) });
    }
    B.add(flatNormals(new THREE.SphereGeometry(1.0, 8, 6).toNonIndexed()), M(trs(side * 0.75, 21.6, 3.95, 0, 0, 0, 1.0, 1.2, 1.0)), { color: col(0.9) });
  }
  // the sword planted point-down
  B.add(flatNormals(new THREE.SphereGeometry(1.05, 8, 6).toNonIndexed()), M(trs(0, 23.2, 3.95)), { color: col(0.85) });
  addAll(B, flat(latheGrid({ rows: 1, segs: 6, profile: (t) => [0.42, 19.9 + t * 2.4] })), M(new THREE.Matrix4().makeTranslation(0, 0, 3.95)), { color: col(0.85) });
  const guardL = damage.guard ? 2.4 : 4.4;
  B.add(chamferBox(4.4 + guardL, 0.9, 1.0, 0.14), M(trs((guardL - 4.4) / 2, 19.5, 3.95, 0, 0, 0)), { color: col(0.9) });
  addAll(B, flat(latheGrid({ rows: 4, segs: 4, squash: 0.26, profile: (t) => [1.25 * (1 - t) + 0.15 * t, 19.1 - t * 19.0], capTop: true })), M(trs(0, 0, 3.95, Math.PI / 4)), { color: col(0.9) });
}

/**
 * Build far silhouettes + cloud sea.
 * @returns {{ far: THREE.Mesh, clouds: THREE.Mesh, colossi: THREE.Vector3[] }}
 */
export function createFar(U, rng, tier) {
  const B = new Builder();
  const cy = LAYOUT.cloudY;
  const rockCol = (k) => (p, n, o) => { const v = k * (0.7 + 0.6 * fbm3(p.x * 0.02, p.y * 0.03, p.z * 0.02, 2)); o[0] = v; o[1] = v * 0.98; o[2] = v * 1.03; };
  const spire = (az, dist, h, r, seed, k = 1) => {
    const p = new THREE.Vector3(Math.sin(az * DEG) * dist, cy - 6, -Math.cos(az * DEG) * dist);
    const g = latheGrid({
      rows: 12, segs: 9,
      profile: (t) => [r * 0.6 * Math.pow(1 - t, 0.9) * (0.75 + 0.5 * noise3(t * 5, seed, 0)) + 0.4, t * (h + 6)],
      rmod: (phi, y) => Math.max(0.25, 1 + (fbm3(Math.cos(phi) * 1.4 + seed, y * 0.05, Math.sin(phi) * 1.4, 3) - 0.5) * 1.6),
      topY: (phi) => h + 6 - Math.abs(noise3(Math.cos(phi) * 2 + seed, Math.sin(phi) * 2, 1)) * r * 0.8,
      capTop: h + 6 - r * 0.2,
    });
    addAll(B, g.map((x) => flatNormals(x.index ? x.toNonIndexed() : x)), trs(p.x, p.y, p.z, rng.range(0, 6)), { color: rockCol(k) });
  };
  // [az, dist, height above clouds, base radius]
  const spires = [
    [-38, 150, 44, 14], [-47, 125, 30, 11], [-58, 175, 70, 18], [-70, 140, 38, 12], [-84, 210, 92, 24], [-102, 160, 55, 16], [-121, 190, 40, 14],
    [36, 170, 52, 15], [49, 140, 34, 10], [61, 200, 84, 22], [74, 155, 46, 13], [90, 230, 66, 20], [108, 170, 50, 15], [124, 200, 36, 12],
    [-16, 420, 30, 16], [12, 470, 24, 14], [-27, 330, 46, 18], [25, 360, 40, 16], [-64, 380, 110, 30], [70, 420, 120, 34],
  ];
  for (const [az, d, h, r] of spires) spire(az, d, h, r, rng.range(0, 50), d > 300 ? 0.8 : 1);

  // colossi on their rock pedestals, facing the arena
  const colossi = [];
  for (const [az, mirror, damage] of [[-21, -1, { arm: 1, hood: true }], [21.5, 1, { shoulder: true, guard: true }]]) {
    const dist = 160;
    const base = new THREE.Vector3(Math.sin(az * DEG) * dist, -2, -Math.cos(az * DEG) * dist);
    const face = Math.atan2(-base.x, -base.z);
    const place = trs(base.x, base.y, base.z, face, 0, 0, 1.35);
    statue(B, rng, mirror, damage, place);
    // rock pedestal rising from the cloud sea
    const g = latheGrid({
      rows: 6, segs: 12,
      profile: (t) => [9.5 + (1 - t) * 6, -26 + t * 26.5],
      rmod: (phi, y) => 1 + (fbm3(Math.cos(phi) * 1.6 + az, y * 0.08, Math.sin(phi) * 1.6, 2) - 0.5) * 0.5,
      capTop: true,
    });
    addAll(B, g.map((x) => flatNormals(x.index ? x.toNonIndexed() : x)), trs(base.x, base.y, base.z, 0, 0, 0, 1, 1, 1), { color: rockCol(0.9) });
    colossi.push(base);
  }
  // a distant broken watchtower on the far right spire
  {
    const p = new THREE.Vector3(Math.sin(61 * DEG) * 200, cy - 6 + 84 + 6 - 4, -Math.cos(61 * DEG) * 200);
    addAll(B, latheGrid({ rows: 6, segs: 10, profile: (t) => [3.2 - t * 0.6, t * 20], topY: (phi) => 20 - Math.abs(Math.sin(phi * 2.5)) * 6, capTop: 15 }).map((x) => flatNormals(x.index ? x.toNonIndexed() : x)), trs(p.x, p.y, p.z), { color: rockCol(0.85) });
  }

  const farMat = new THREE.ShaderMaterial({
    name: 'env.far',
    vertexShader: FAR_VERT,
    fragmentShader: FAR_FRAG,
    uniforms: {
      uZenith: U.uZenith, uSkyMid: U.uSkyMid, uHorizon: U.uHorizon, uGlow: U.uGlow, uSunHalo: U.uSunHalo, uSunDir: U.uSunDir,
      uFogP: U.uFogP, uFogNear: U.uFogNear, uMood: U.uMood, uCorona: U.uCorona, uRim: U.uRimFar, uKeyDir: U.uKeyDir,
      uFarCol: { value: new THREE.Color(0.012, 0.013, 0.018) },
      uCloudY: { value: cy },
    },
  });
  const far = new THREE.Mesh(B.build(), farMat);
  far.name = 'env.far';
  far.frustumCulled = false;
  far.renderOrder = 10;

  const cloudGeo = new THREE.RingGeometry(26, 760, 72, 10);
  cloudGeo.rotateX(-Math.PI / 2);
  const cloudMat = new THREE.ShaderMaterial({
    name: 'env.cloudsea',
    vertexShader: CLOUD_VERT,
    fragmentShader: CLOUD_FRAG,
    defines: { OCT: tier.detail >= 1 ? 4 : 3 },
    uniforms: {
      uZenith: U.uZenith, uSkyMid: U.uSkyMid, uHorizon: U.uHorizon, uGlow: U.uGlow, uSunHalo: U.uSunHalo, uSunDir: U.uSunDir,
      uFogP: U.uFogP, uFogNear: U.uFogNear, uMood: U.uMood, uCorona: U.uCorona, uTime: U.uTime, uWind: U.uWind,
      uCloudDark: { value: new THREE.Color(0.006, 0.007, 0.012) },
      uCloudLit: { value: new THREE.Color(0.03, 0.032, 0.045) },
    },
  });
  const clouds = new THREE.Mesh(cloudGeo, cloudMat);
  clouds.position.y = cy;
  clouds.name = 'env.cloudsea';
  clouds.frustumCulled = false;
  clouds.renderOrder = 20;
  return { far, clouds, colossi };
}
