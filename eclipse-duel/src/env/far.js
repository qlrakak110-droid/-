// Far layer: the sea of cloud below the cliff, ink-painting peaks in layered aerial perspective (all the way round:
// the action-RPG mode turns 360 degrees), a distant pagoda, and the two colossal guardian statues of armoured
// martial deities (수호무신상) standing in the clouds either side of the eclipse: stern masked faces under a flared
// helmet / a flame crown, layered lamellar skirts, one hand on a planted glaive or great sabre, the other raised in a
// warding gesture, a celestial scarf arching behind the head; weathered, one of them damaged. Built to hold up in a
// telephoto hero shot. Far silhouettes use one cheap shader (sky ambient + eclipse rim + sky-matched haze); the mesh
// is drawn in three groups (backdrop, statue 0, statue 1) so that a statue can be hidden (env.statues[i].visible).

import * as THREE from 'three';
import { DEG } from '../core/math.js';
import { NOISE, SKY_BASE, FOG } from './glsl.js';
import { Builder, latheGrid, addAll, trs, noise3, fbm3, flatNormals, chamferBox, tube, sweep, prism } from './geometry.js';
import { LAYOUT } from './config.js';

const FAR_VERT = /* glsl */ `
attribute vec3 color;
attribute float glow;  // Builder's glow channel, used here as "less haze" (0 = full aerial perspective)
varying vec3 vW; varying vec3 vN; varying vec3 vC; varying float vHaze; varying vec2 vS;
void main() {
  vec4 w = modelMatrix * vec4(position, 1.0);
  vW = w.xyz; vN = normalize(mat3(modelMatrix) * normal); vC = color; vHaze = 1.0 - glow;
  vS = uv;  // x: carved statue stone (weathering), y: ember glow
  gl_Position = projectionMatrix * viewMatrix * w;
}`;
const FAR_FRAG = /* glsl */ `
${NOISE}
${SKY_BASE}
${FOG}
uniform vec3 uFarCol, uCorona, uRim, uKeyDir;
uniform vec2 uEyes;   // eye glow of statue 0 / statue 1
uniform float uCloudY, uTime;
varying vec3 vW; varying vec3 vN; varying vec3 vC; varying float vHaze; varying vec2 vS;
void main() {
  vec3 n = normalize(vN);
  vec3 toCam = cameraPosition - vW;
  float dist = length(toCam);
  vec3 v = toCam / dist;
  vec3 dir = -v;
  float statue = vS.x;
  vec3 alb = vC;
  if (statue > 0.5) {
    // weathering on the statues: rain streaks down the vertical faces, pale lichen crusts on what faces the sky,
    // grime in the hollows; lit a little more by the key so the armour reads in a telephoto shot
    float vert = 1.0 - abs(n.y);
    float st = vnoise(vec2((vW.x + vW.z) * 0.55, vW.y * 0.045)) * 0.7 + vnoise(vec2((vW.x - vW.z) * 1.7, vW.y * 0.12)) * 0.3;
    alb *= 1.0 - 0.45 * smoothstep(0.5, 0.82, st) * vert;
    float lich = smoothstep(0.55, 0.8, vnoise(vW.xz * 0.6 + vW.y * 0.3)) * smoothstep(0.2, 0.8, n.y);
    alb *= 1.0 + 0.9 * lich;
    alb *= 0.85 + 0.3 * vnoise(vW.xy * 1.3 + vW.z);
  }
  // dark stone: sky dome from above, a little key, warm horizon glow bouncing up from the cloud sea
  vec3 col = uFarCol * alb * (0.45 + 0.55 * max(n.y * 0.5 + 0.5, 0.0));
  col += uFarCol * alb * (0.7 + 2.2 * statue) * max(dot(n, uKeyDir), 0.0);
  col += uGlow * 0.25 * smoothstep(uCloudY + 25.0, uCloudY, vW.y) * vC;
  // aerial perspective; feet dissolve into the cloud sea
  float f = 1.0 - exp(-dist * 0.0042 * vHaze);
  f = max(f, smoothstep(uCloudY + 9.0, uCloudY - 1.0, vW.y));
  vec3 fc = skyBase(vec3(dir.x, max(dir.y, 0.003), dir.z));
  col = mix(col, fc, clamp(f, 0.0, 0.97));
  // eclipse light grazing past the silhouettes (scattered toward the camera, so added after the haze): a rim on the
  // edges that turn toward the sun, and a thin glow on every edge close to the sun on screen
  float ndl = dot(n, uSunDir);
  float fres = ((1.0 - max(dot(n, v), 0.0)) * (1.0 - max(dot(n, v), 0.0)));
  float back = pow(max(dot(dir, uSunDir), 0.0), 6.0);
  float edge = pow(max(1.0 - abs(dot(n, v)), 0.0), 3.0);
  float lift = smoothstep(uCloudY, uCloudY + 30.0, vW.y);
  col += (uRim * max(ndl + 0.2, 0.0) * fres + uCorona * 0.1 * edge * back) * (1.0 - 0.55 * f) * lift;
  // the eye slits of the masks: a faint smoulder (uv.y = 1: statue 0, 2: statue 1)
  col += vec3(1.9, 0.52, 0.11) * step(0.5, vS.y) * (vS.y > 1.5 ? uEyes.y : uEyes.x) * (1.0 - 0.5 * f) * (0.85 + 0.15 * sin(uTime * 1.3 + vW.x));
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
  // billow tops catch the horizon glow, troughs stay dark; a glitter path of forward-scattered corona light runs
  // across the tops toward the eclipse (the leading line from the arena edge to the black sun)
  float tops = smoothstep(0.42, 0.8, hh);
  vec2 hd = normalize(dir.xz), hs = normalize(uSunDir.xz);
  float path = pow(max(dot(hd, hs), 0.0), 90.0) + 0.25 * pow(max(dot(hd, hs), 0.0), 12.0);
  vec3 col = mix(uCloudDark, uCloudLit, smoothstep(0.3, 0.75, hh));
  col += uCorona * (0.05 * fwd * (0.3 + sun) + 0.22 * path * (0.35 + sun)) * tops;
  col += uGlow * 0.24 * tops * (0.6 + 0.4 * sun);
  col *= 0.8 + 0.4 * smoothstep(-0.3, 0.6, n.x * hs.x + n.z * hs.y);
  float f = 1.0 - exp(-dist * 0.003);
  vec3 fc = skyBase(vec3(dir.x, 0.006, dir.z));
  col = mix(col, fc, clamp(f, 0.0, 1.0));
  gl_FragColor = vec4(moodApply(col, 1.0), 1.0);
}`;

const V = (x, y, z) => new THREE.Vector3(x, y, z);
const FRONT = Math.PI / 2;            // latheGrid: phi = pi/2 faces +Z
const sm = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t); };
/** Piecewise-linear lathe profile through [r, y] points (rows = points - 1). */
const poly = (pts) => (t) => { const k = Math.min(pts.length - 1, Math.round(t * (pts.length - 1))); return pts[k]; };
/** Mirror a convex outline across x (keeps it counter-clockwise). */
const mirrorX = (pts, s) => (s > 0 ? pts : pts.map(([x, y]) => [-x, y]).reverse());

/** Statue proportions in its own frame (units; world = units x scale). Shared with the README and env.statues. */
export const STATUE = { plinthTop: 2.0, plinthR: 6.0, belt: 17.6, shoulder: 26.4, eyes: 30.2, helmTop: 33.3, crestTop: 38.4, glaiveTop: 44.9 };

/**
 * One colossal guardian (local frame: plinth centre at the origin, facing +Z, ~38 units to the crest).
 * Smooth normals (the backlit rim needs continuous silhouettes); `haze` < 1 stands it a layer in front of the peaks.
 * @param {Builder} B
 * @param {object} o  { place: Matrix4, haze, q: detail tier, W: +1 | -1 weapon side (local x), weapon: 'glaive' | 'sabre',
 *                      crown: bool (flame crown instead of the flared helmet), damage: { arm, scarf, crown, chest }, eye: 1 | 2 }
 */
function guardian(B, o) {
  const { place, haze, q, W, damage } = o;
  const O = -W;
  const tone = (k) => (p, n, c) => { const v = k * (0.75 + 0.5 * noise3(p.x * 0.08, p.y * 0.08, p.z * 0.08)); c[0] = v; c[1] = v; c[2] = v * 1.02; };
  const opt = (k, ember = 0) => ({ color: typeof k === 'number' ? tone(k) : k, glow: () => 1 - haze, uv: [1, ember] });
  const M = (m) => (m ? place.clone().multiply(m) : place);
  const hi = q >= 1;
  const inv = place.clone().invert();
  const lp = V(0, 0, 0);
  // lamellar: rows of small plates laced together, each row shading the one under it
  const lamellar = (k, y0, rowH) => (p, n, c) => {
    lp.copy(p).applyMatrix4(inv);
    const row = (lp.y - y0) / rowH;
    const f = row - Math.floor(row);
    const v = k * (0.74 + 0.5 * noise3(p.x * 0.08, p.y * 0.08, p.z * 0.08)) * (0.66 + 0.5 * f);
    c[0] = v; c[1] = v; c[2] = v * 1.02;
  };

  // ---- plinth: an octagonal step under a lotus pedestal -------------------------------------------------------------
  addAll(B, latheGrid({ rows: 6, segs: hi ? 24 : 16, profile: poly([[9.0, -3.2], [9.0, -1.0], [8.0, -0.8], [7.3, 0.1], [7.9, 0.95], [7.0, 1.6], [6.0, 2.0]]), rmod: (phi, y) => (y > 0 && y < 1.7 ? 1 + 0.05 * Math.pow(Math.abs(Math.sin(phi * 8)), 0.6) : 1), capTop: true }), M(), opt(0.9));

  // ---- boots under the hem ------------------------------------------------------------------------------------------
  for (const sx of [-1, 1]) B.add(new THREE.SphereGeometry(1, 8, 6), M(trs(sx * 2.5, 3.0, 1.5, sx * 0.2, 0, 0, 1.6, 1.25, 2.6)), opt(0.8));

  // ---- armour skirts: three flaring tiers of lamellar, the lowest split in front --------------------------------------
  const segs = hi ? 40 : 26;
  const skirt = (y0, y1, r0, r1, flare, rows, plates, k, arc = null) => addAll(B, latheGrid({
    rows, segs: arc ? Math.max(6, Math.round(segs * (arc[1] - arc[0]) / (Math.PI * 2))) : segs, squash: 0.7, arc,
    profile: (t) => [r0 + (r1 - r0) * t + flare * Math.pow(1 - t, 3), y0 + (y1 - y0) * t],
    bottomY: (phi) => y0 - 0.32 * Math.pow(Math.abs(Math.sin(phi * plates * 0.5)), 0.7),
    rmod: (phi, y, j) => {
      let m = 1 + (j % 2 ? 0.014 : 0) + 0.012 * Math.sign(Math.sin(phi * plates));
      const d = Math.abs(phi - FRONT);
      if (!arc && d < 0.2) m *= 0.9 + 0.5 * d;                         // the front seam
      m *= 1 + (noise3(Math.cos(phi) * 3, y * 0.35, Math.sin(phi) * 3) - 0.5) * 0.035;
      return m;
    },
  }), M(), opt(lamellar(k, y0, (y1 - y0) / (rows / 2))));
  skirt(3.4, 12.6, 5.25, 4.1, 0.95, hi ? 10 : 6, 22, 0.95);
  skirt(9.0, 15.6, 4.85, 4.2, 0.8, hi ? 8 : 6, 20, 1.02);
  // tassets: four flaps over the hips and thighs
  for (const [c, w] of [[FRONT - 0.72, 0.5], [FRONT + 0.72, 0.5], [FRONT + Math.PI * 0.5 + 0.35, 0.62], [FRONT - Math.PI * 0.5 - 0.35, 0.62]]) skirt(13.0, 17.5, 4.75, 4.2, 0.62, 4, 14, 1.08, [c - w, c + w]);
  // the apron hanging from the belt, a boss at its point
  B.add(prism([[-1.05, 0], [1.05, 0], [1.2, -5.6], [0, -7.4], [-1.2, -5.6]].reverse(), 0.45), M(trs(0, 17.2, 3.55, 0, -0.1, 0)), opt(1.12));
  B.add(new THREE.SphereGeometry(0.62, 8, 6), M(trs(0, 11.6, 4.25)), opt(1.15));

  // ---- belt and buckle, cuirass with the black-sun mirror on the chest, gorget ------------------------------------------
  addAll(B, latheGrid({ rows: 3, segs, squash: 0.7, profile: poly([[4.2, 16.9], [4.5, 17.3], [4.5, 18.0], [4.2, 18.4]]) }), M(), opt(1.12));
  B.add(new THREE.CylinderGeometry(1.4, 1.4, 0.5, hi ? 12 : 8), M(trs(0, 17.65, 3.2, 0, Math.PI / 2, 0)), opt(1.2));
  B.add(new THREE.SphereGeometry(0.6, 8, 6), M(trs(0, 17.65, 3.5)), opt(0.5));
  addAll(B, latheGrid({
    rows: 7, segs, squash: 0.66, profile: poly([[4.1, 18.2], [4.2, 19.8], [4.75, 22.0], [5.05, 24.0], [4.65, 25.8], [3.4, 27.0], [2.2, 27.7], [1.9, 28.3]]),
    rmod: (phi, y) => (damage.chest && y > 21 && y < 26.5 && Math.cos(phi - (FRONT + O * 0.9)) > 0.8 ? 0.86 : 1) * (1 + (noise3(Math.cos(phi) * 3, y * 0.4, Math.sin(phi) * 3) - 0.5) * 0.03),
    capTop: true,
  }), M(), opt(lamellar(1.0, 18.2, 1.3)));
  addAll(B, [new THREE.TorusGeometry(1.25, 0.24, 5, hi ? 16 : 10)], M(trs(0, 23.3, 3.33, 0, -0.12, 0)), opt(1.2));
  B.add(new THREE.CylinderGeometry(1.05, 1.05, 0.2, hi ? 12 : 8), M(trs(0, 23.3, 3.25, 0, Math.PI / 2 - 0.12, 0)), opt(0.3));
  addAll(B, latheGrid({ rows: 2, segs: hi ? 16 : 10, profile: poly([[2.9, 26.4], [2.6, 27.2], [2.2, 27.9]]) }), M(), opt(1.1));

  // ---- pauldrons: three rounded lames down each shoulder, each with a rolled edge -------------------------------------------
  for (const sx of [-1, 1]) {
    for (let k = 0; k < 3; k++) {
      const R = 3.05 - k * 0.38, h = 1.9 - k * 0.22;
      const m = M(trs(sx * (5.35 + k * 0.78), 25.75 - k * 1.55, 0.15, 0, 0, -sx * (0.34 + k * 0.24)));
      B.add(new THREE.SphereGeometry(1, hi ? 14 : 10, hi ? 5 : 4, 0, Math.PI * 2, 0, Math.PI / 2), m.clone().multiply(trs(0, 0, 0, 0, 0, 0, R, h, R * 0.92)), opt(1.14 - k * 0.07));
      if (hi) addAll(B, [new THREE.TorusGeometry(R, 0.17, 4, 14)], m.clone().multiply(trs(0, 0.02, 0, 0, Math.PI / 2, 0, 1, 0.92, 1)), opt(1.0 - k * 0.05));
    }
  }

  // ---- arms ---------------------------------------------------------------------------------------------------------------
  const armSides = hi ? 9 : 6;
  const limb = (a, b, r0, r1, k, bracer = false) => addAll(B, [tube([a, a.clone().lerp(b, 0.5), b], (t) => r0 + (r1 - r0) * t + (bracer ? 0.3 * Math.pow(1 - t, 4) + 0.12 * Math.pow(t, 6) : 0), { sides: armSides, caps: true })], M(), opt(k));
  const finger = (pts, r) => addAll(B, [tube(pts, (t) => r * (1.1 - 0.3 * t), { sides: hi ? 5 : 4, caps: true })], M(), opt(1.3));
  const glaive = o.weapon === 'glaive';
  // weapon arm
  const shW = V(W * 5.9, 25.6, 0.3);
  const shaft = V(W * 8.1, 0, 3.7);                       // glaive: where the shaft stands
  const hilt = V(W * 3.4, 0, 5.6);                        // sabre: planted in front of the weapon-side foot
  if (glaive) {
    const el = V(W * 8.0, 21.2, 0.9), wr = V(shaft.x - W * 0.5, 19.2, shaft.z - 0.35);
    limb(shW, el, 1.5, 1.25, 1.0);
    limb(el, wr, 1.2, 0.95, 1.1, true);
    B.add(new THREE.SphereGeometry(1, 8, 6), M(trs(shaft.x - W * 0.55, 19.0, shaft.z - 0.1, 0, 0, 0, 0.75, 0.95, 0.9)), opt(1.3));
    for (let k = 0; k < 4; k++) {
      const y = 18.35 + k * 0.42, rr = 0.36 + 0.2;
      const pts = [];
      for (let i = 0; i <= 5; i++) { const a = (W > 0 ? Math.PI : 0) - W * (i / 5) * 4.0; pts.push(V(shaft.x + Math.cos(a) * rr, y - i * 0.015, shaft.z + Math.sin(a) * rr)); }
      finger(pts, 0.2);
    }
  } else {
    const el = V(W * 7.0, 22.6, 2.4), wr = V(hilt.x + W * 0.6, 21.7, hilt.z - 0.5);
    limb(shW, el, 1.5, 1.25, 1.0);
    limb(el, wr, 1.2, 0.95, 1.1, true);
    // the hand rests on the ring pommel, fingers over its front
    B.add(new THREE.SphereGeometry(1, 8, 6), M(trs(hilt.x, 21.45, hilt.z - 0.1, 0, 0.2, 0, 0.95, 0.45, 0.95)), opt(1.3));
    for (let k = 0; k < 4; k++) {
      const x = hilt.x + (k - 1.5) * 0.34;
      finger([V(x, 21.5, hilt.z + 0.4), V(x, 21.4, hilt.z + 0.9), V(x, 21.0, hilt.z + 1.1), V(x, 20.55, hilt.z + 1.0)], 0.19 - Math.abs(k - 1.5) * 0.012);
    }
  }
  // warding arm: forearm raised, palm out toward whoever climbs the terrace
  const shO = V(O * 5.9, 25.6, 0.3), elO = V(O * 7.2, 21.6, 2.3), palm = V(O * 5.3, 25.3, 5.4);
  limb(shO, elO, 1.5, 1.25, 1.0);
  if (damage.arm) {
    // snapped above the wrist: a ragged stump
    const stump = elO.clone().lerp(palm, 0.36);
    addAll(B, latheGrid({ rows: 2, segs: 8, profile: (t) => [1.15 - 0.1 * t, t * 2.0], topY: (phi) => 2.0 - Math.abs(Math.sin(phi * 1.5 + 0.7)) * 0.9, capTop: 1.4 }), M(new THREE.Matrix4().compose(elO, new THREE.Quaternion().setFromUnitVectors(V(0, 1, 0), stump.clone().sub(elO).normalize()), V(1, 1, 1))), opt(1.05));
  } else {
    const wrO = palm.clone().add(V(0, -1.5, -0.6));
    limb(elO, wrO, 1.2, 0.9, 1.1, true);
    B.add(chamferBox(1.9, 2.1, 0.62, 0.2), M(trs(palm.x, palm.y, palm.z, 0, -0.12, 0)), opt(1.32));
    for (let k = 0; k < 4; k++) {
      const x = palm.x + (k - 1.5) * 0.47;
      const len = 1.9 - Math.abs(k - 1.4) * 0.22;
      finger([V(x, palm.y + 0.95, palm.z - 0.1), V(x, palm.y + 0.95 + len * 0.55, palm.z - 0.2), V(x, palm.y + 0.95 + len, palm.z - 0.42)], 0.27);
    }
    finger([V(palm.x + W * 0.95, palm.y - 0.5, palm.z), V(palm.x + W * 1.5, palm.y + 0.1, palm.z + 0.1), V(palm.x + W * 1.65, palm.y + 0.85, palm.z)], 0.25);
  }

  // ---- the weapon -----------------------------------------------------------------------------------------------------------
  if (glaive) {
    // a great glaive planted at the side: shaft, collar with a tassel ring, a broad curved blade with a back hook
    addAll(B, [tube([V(shaft.x, -1.2, shaft.z), V(shaft.x, 17, shaft.z), V(shaft.x, 34.2, shaft.z)], 0.5, { sides: 6, caps: true })], M(), opt(0.82));
    addAll(B, latheGrid({ rows: 3, segs: 8, profile: poly([[0.55, 33.0], [1.05, 33.5], [1.05, 34.0], [0.6, 34.6]]) }), M(trs(shaft.x, 0, shaft.z)), opt(1.0));
    addAll(B, [new THREE.TorusGeometry(0.75, 0.16, 4, 10)], M(trs(shaft.x + W * 0.2, 32.1, shaft.z + 0.5, 0, 0.5, 0)), opt(0.95));
    B.add(prism(mirrorX([[-0.5, 0], [0.6, 0], [2.7, 2.1], [3.45, 5.2], [2.8, 8.3], [0.65, 10.6], [-0.2, 7.0], [-0.6, 3.3]], W), 0.7), M(trs(shaft.x, 34.3, shaft.z)), opt(0.9));
    B.add(prism(mirrorX([[-0.5, 1.0], [-2.0, 2.9], [-1.2, 3.3], [-0.4, 2.7]], W), 0.5), M(trs(shaft.x, 34.3, shaft.z)), opt(0.9));
  } else {
    // a great sabre planted point-down: broad single-edged blade, disc guard, wrapped grip, ring pommel
    const pts = mirrorX([[-0.25, -1.4], [0.65, 0.4], [1.25, 5.5], [1.3, 15.2], [-0.8, 15.2], [-0.8, 3.0]], W);
    B.add(prism(pts, 0.46), M(trs(hilt.x, 0, hilt.z)), opt(0.88));
    B.add(new THREE.CylinderGeometry(1.6, 1.6, 0.42, hi ? 12 : 8), M(trs(hilt.x, 15.4, hilt.z)), opt(0.95));
    addAll(B, latheGrid({ rows: 5, segs: 8, profile: (t) => [0.42 + 0.05 * Math.abs(Math.sin(t * Math.PI * 5)), 15.6 + t * 4.0] }), M(trs(hilt.x, 0, hilt.z)), opt(0.85));
    addAll(B, [new THREE.TorusGeometry(0.72, 0.22, 5, hi ? 14 : 10)], M(trs(hilt.x, 20.5, hilt.z)), opt(0.9));
  }

  // ---- the head: a stern mask under the helmet ------------------------------------------------------------------------------
  const hy = 30.0, hz = 0.5;
  B.add(new THREE.SphereGeometry(1, hi ? 12 : 8, hi ? 9 : 6), M(trs(0, hy, hz, 0, 0, 0, 2.0, 2.3, 1.75)), opt(1.12));
  // brow: a heavy V ridge; a long nose wedge; cheekbones; a wide downturned mouth; a jutting chin
  addAll(B, [tube([V(-1.95, hy + 0.95, hz + 0.45), V(-0.95, hy + 0.72, hz + 1.3), V(0, hy + 0.3, hz + 1.56), V(0.95, hy + 0.72, hz + 1.3), V(1.95, hy + 0.95, hz + 0.45)], 0.42, { sides: 5, caps: true })], M(), opt(1.26));
  B.add(prism([[-0.46, 0], [0.46, 0], [0.15, 1.5], [-0.15, 1.5]], 0.9), M(trs(0, hy - 1.05, hz + 1.42, 0, -0.26, 0)), opt(1.28));
  addAll(B, [tube([V(-1.05, hy - 1.68, hz + 1.02), V(-0.5, hy - 1.42, hz + 1.38), V(0, hy - 1.34, hz + 1.48), V(0.5, hy - 1.42, hz + 1.38), V(1.05, hy - 1.68, hz + 1.02)], 0.13, { sides: 4, caps: true })], M(), opt(0.16));
  for (const sx of [-1, 1]) {
    B.add(new THREE.BoxGeometry(0.86, 0.19, 0.3), M(trs(sx * 0.86, hy + 0.2, hz + 1.25, sx * -0.32, 0, sx * 0.2)), opt(0.08, o.eye));
    B.add(new THREE.SphereGeometry(0.7, 6, 5), M(trs(sx * 1.22, hy - 0.62, hz + 0.98, 0, 0, 0, 1, 0.75, 0.6)), opt(1.22));
  }
  B.add(new THREE.SphereGeometry(0.7, 6, 5), M(trs(0, hy - 2.0, hz + 0.75, 0, 0, 0, 1.3, 0.7, 0.9)), opt(1.2));
  if (!o.crown) {
    // a long beard combed to a point over the gorget
    B.add(prism([[-1.15, 0], [-0.8, -2.3], [0, -3.7], [0.8, -2.3], [1.15, 0]], 0.75), M(trs(0, hy - 1.95, hz + 1.2, 0, -0.2, 0)), opt((p, n, c) => { const v = 1.02 * (0.7 + 0.5 * noise3(p.x * 2.2, p.y * 0.25, p.z * 0.6)); c[0] = v; c[1] = v; c[2] = v * 1.02; }));
  }
  if (!o.crown) {
    // helmet: bowl, a broad brim flaring up at the rim (top and underside), a lamellar neck guard, stem / bud / spike
    const hs = hi ? 18 : 12;
    addAll(B, latheGrid({ rows: 4, segs: hs, profile: (t) => [2.4 * Math.cos(t * Math.PI / 2), 30.9 + 2.4 * Math.sin(t * Math.PI / 2)], capTop: true }), M(trs(0, 0, 0.2)), opt(1.0));
    addAll(B, latheGrid({ rows: 3, segs: hs, profile: poly([[4.8, 32.05], [4.3, 31.25], [3.2, 30.85], [2.3, 31.05]]), rmod: (phi) => 1 + 0.12 * Math.pow(Math.abs(Math.cos(phi)), 3) }), M(trs(0, 0, 0.2)), opt(1.08));
    addAll(B, latheGrid({ rows: 3, segs: hs, profile: poly([[2.3, 30.6], [3.3, 30.45], [4.3, 30.95], [4.8, 31.95]]), rmod: (phi) => 1 + 0.12 * Math.pow(Math.abs(Math.cos(phi)), 3) }), M(trs(0, 0, 0.2)), opt(0.7));
    addAll(B, latheGrid({ rows: 4, segs: hi ? 14 : 9, arc: [FRONT + 0.95, FRONT + Math.PI * 2 - 0.95], profile: poly([[3.9, 26.9], [3.3, 28.2], [2.8, 29.5], [2.5, 30.7], [2.4, 31.0]]) }), M(trs(0, 0, 0.1)), opt(lamellar(0.98, 26.9, 1.0)));
    addAll(B, [tube([V(0, 33.2, 0.2), V(0, 35.2, 0.2)], 0.36, { sides: 6 })], M(), opt(0.95));
    addAll(B, latheGrid({ rows: 5, segs: 8, profile: (t) => [t < 0.15 ? 0.5 : 0.25 + 0.75 * Math.sin(Math.pow((t - 0.15) / 0.85, 0.75) * Math.PI) * (1 - 0.3 * t), 35.1 + t * 3.3], capTop: true }), M(trs(0, 0, 0.2)), opt(1.0));
    addAll(B, [new THREE.TorusGeometry(0.62, 0.17, 4, 10)], M(trs(0, 32.1, 2.45, 0, -0.5, 0)), opt(1.15));
  } else {
    // crown: a headband, a topknot, flame points round the brow (two snapped off), lappets down the cheeks
    const hs = hi ? 16 : 10;
    addAll(B, latheGrid({ rows: 3, segs: hs, profile: (t) => [2.2 * Math.cos(t * Math.PI / 2 * 0.92), 31.0 + 2.2 * Math.sin(t * Math.PI / 2 * 0.92)], capTop: true }), M(trs(0, 0, 0.15)), opt(0.92));
    addAll(B, latheGrid({ rows: 2, segs: hs, profile: poly([[2.3, 30.75], [2.6, 31.3], [2.45, 32.0]]) }), M(trs(0, 0, 0.2)), opt(1.12));
    B.add(new THREE.SphereGeometry(1, 8, 6), M(trs(0, 33.9, -0.1, 0, 0, 0, 1.15, 1.35, 1.15)), opt(0.95));
    const flame = (h) => [[-0.62, 0], [0.62, 0], [0.8, h * 0.38], [0.28, h * 0.72], [0, h], [-0.3, h * 0.7], [-0.82, h * 0.36]];
    [[0, 4.6], [0.72, 3.5], [-0.72, damage.crown ? 1.3 : 3.5], [1.4, damage.crown ? 0.9 : 2.5], [-1.4, 2.5]].forEach(([a, h]) => {
      B.add(prism(flame(h), 0.34), M(trs(Math.sin(a) * 2.5, 31.7, 0.2 + Math.cos(a) * 2.5, a, -0.14, 0)), opt(1.1));
    });
    for (const sx of [-1, 1]) addAll(B, [tube([V(sx * 2.2, 31.0, 0.3), V(sx * 2.7, 29.0, 0.5), V(sx * 2.9, 27.0, 1.1)], (t) => 0.42 - 0.1 * t, { sides: 5, caps: true })], M(), opt(1.0));
  }

  // ---- the celestial scarf: a broad ribbon arching behind the head, its ends trailing past the hips ------------------------------
  {
    const pts = [V(W * 8.9, 8.0, 1.2), V(W * 8.4, 13.5, 0.2), V(W * 8.3, 20.0, -1.0), V(W * 6.9, 27.6, -2.0), V(W * 3.6, 33.6, -2.7), V(0, 35.6, -2.9),
      V(O * 3.6, 33.6, -2.7), V(O * 6.9, 27.6, -2.0), V(O * 8.2, 20.5, -1.0), V(O * 8.5, 13.0, 0.3), V(O * 9.2, 7.0, 1.4)];
    const curve = new THREE.CatmullRomCurve3(pts);
    const n = hi ? 40 : 24;
    const stop = damage.scarf ? 0.6 : 1;                       // the far half broken away
    const path = [];
    for (let i = 0; i <= n; i++) {
      const t = (i / n) * stop;
      const p = curve.getPoint(t), tg = curve.getTangent(t);
      const side = V(0, 0, 1).cross(tg).normalize();
      // the ends widen and flutter outward
      const e = Math.min(t, 1 - t);
      path.push({ p: p.add(V(0, 0, 0.5 * Math.sin(t * 19))), side, up: V(0, 0, 1), w: 0.85 + 0.9 * sm(0.22, 0.0, e) });
    }
    const prof = [[-1, -0.17], [1, -0.17], [1, 0.17], [-1, 0.17], [-1, -0.17]];
    const g = sweep(prof, path.map((s) => ({ p: s.p, side: s.side.multiplyScalar(s.w), up: s.up })));
    g.computeVertexNormals();
    B.add(g, M(), opt(0.94));
  }
}

/**
 * Build far silhouettes + cloud sea.
 * @returns {{ far: THREE.Mesh, clouds: THREE.Mesh, statues: Array }}
 */
export function createFar(U, rng, tier) {
  const B = new Builder();
  const cy = LAYOUT.cloudY;
  const rockCol = (k) => (p, n, o) => { const v = k * (0.7 + 0.6 * fbm3(p.x * 0.02, p.y * 0.03, p.z * 0.02, 2)); o[0] = v; o[1] = v * 0.98; o[2] = v * 1.03; };
  // an ink-painting peak: a needle with stepped shoulders, flat-shaded; satellites lean against the main needle
  const needle = (x, z, h, r, seed, k, rows = 9, segs = 8) => {
    const g = latheGrid({
      rows, segs,
      profile: (t) => {
        // a broad foot in the mist, shoulders that step in, a blunt crown
        const step = 1 + 0.3 * (t < 0.34 ? 1 : t < 0.62 ? 0.45 : 0) + 0.2 * noise3(t * 6, seed, 0);
        return [r * (0.16 + 0.84 * Math.pow(1 - t, 1.15)) * step, t * (h + 8)];
      },
      rmod: (phi, y) => Math.max(0.35, 1 + (fbm3(Math.cos(phi) * 1.4 + seed, y * 0.045, Math.sin(phi) * 1.4, 3) - 0.5) * 1.2),
      topY: (phi) => h + 8 - Math.abs(noise3(Math.cos(phi) * 2 + seed, Math.sin(phi) * 2, 1)) * r * 0.5,
      capTop: h + 8 - r * 0.12,
    });
    addAll(B, g.map((q) => flatNormals(q.index ? q.toNonIndexed() : q)), trs(x, cy - 8, z, rng.range(0, 6)), { color: rockCol(k), uv: [0, 0] });
  };
  const peak = (az, dist, h, r, kTone = 1) => {
    const x = Math.sin(az * DEG) * dist, z = -Math.cos(az * DEG) * dist;
    const seed = rng.range(0, 50);
    needle(x, z, h, r, seed, kTone);
    const sats = tier.detail >= 1 && dist < 320 ? 2 : 1;
    for (let i = 0; i < sats; i++) {
      const a = rng.range(0, Math.PI * 2), d = r * rng.range(0.75, 1.2);
      needle(x + Math.cos(a) * d, z + Math.sin(a) * d, h * rng.range(0.42, 0.78), r * rng.range(0.5, 0.75), seed + 7 + i, kTone, 6, 6);
    }
  };
  // [az, dist, height above the clouds, base radius]: flanks first, the far layers, then the ring behind the gate
  const peaks = [
    [-38, 160, 46, 20], [-47, 135, 30, 15], [-58, 185, 66, 26], [-70, 150, 38, 17], [-84, 220, 84, 32], [-102, 170, 50, 22], [-121, 200, 40, 20],
    [36, 180, 52, 20], [49, 150, 33, 15], [61, 210, 78, 28], [74, 165, 44, 18], [90, 240, 64, 27], [108, 180, 48, 20], [124, 210, 38, 18],
    [-16, 420, 34, 20], [12, 470, 28, 18], [-27, 330, 52, 22], [25, 360, 46, 20], [-64, 380, 110, 38], [70, 420, 120, 42],
    [-12, 250, 26, 13], [9.5, 290, 22, 12], [-3, 400, 19, 15], [19, 320, 30, 15],
    [142, 190, 54, 22], [158, 250, 80, 30], [176, 175, 42, 19], [-170, 220, 70, 27], [-152, 180, 46, 20], [-138, 270, 92, 32],
  ];
  for (const [az, d, h, r] of peaks) peak(az, d, h, r, d > 300 ? 0.75 : 0.85);

  // a distant pagoda on a far peak, left of the eclipse: seven diminishing storeys under flared eaves, a mast
  {
    const az = -6.6, dist = 440, top = cy + 15;
    const x = Math.sin(az * DEG) * dist, z = -Math.cos(az * DEG) * dist;
    needle(x, z, 15, 13, 3.3, 0.8, 6, 7);
    let y = top - 1.5, w = 4.6, hgt = 5.4;
    for (let k = 0; k < 7; k++) {
      addAll(B, latheGrid({ rows: 1, segs: 6, profile: (t) => [w, y + t * hgt] }).map((q) => flatNormals(q.toNonIndexed())), trs(x, 0, z), { color: rockCol(0.8), uv: [0, 0] });
      const yy = y + hgt, ww = w, hh = hgt;
      addAll(B, latheGrid({ rows: 2, segs: 6, profile: poly([[ww * 2.05, yy - hh * 0.02], [ww * 1.5, yy + hh * 0.1], [ww * 0.78, yy + hh * 0.42]]) }).map((q) => flatNormals(q.toNonIndexed())), trs(x, 0, z), { color: rockCol(0.7), uv: [0, 0] });
      y += hgt * 1.18; w *= 0.87; hgt *= 0.9;
    }
    addAll(B, [tube([V(x, y - 1, z), V(x, y + 7.5, z)], (t) => 0.5 - 0.4 * t, { sides: 4, caps: true })], new THREE.Matrix4(), { color: rockCol(0.7), uv: [0, 0] });
  }

  // the two guardians on rock pedestals rising from the cloud sea, facing the terrace. They flank the eclipse inside
  // the vista window; the left one stands nearer. Their crests top out ~8 degrees up (the fight camera's frame ends
  // ~12 degrees up).
  const defs = [
    { id: 'west', az: -13.5, dist: 205, scale: 1.2, baseY: -15.5, W: -1, weapon: 'glaive', crown: false, damage: {}, eye: 1 },
    { id: 'east', az: 15.5, dist: 250, scale: 1.4, baseY: -16.5, W: 1, weapon: 'sabre', crown: true, damage: { arm: true, scarf: true, crown: true, chest: true }, eye: 2 },
  ];
  const groups = [];
  const statues = [];
  for (const d of defs) {
    const base = V(Math.sin(d.az * DEG) * d.dist, d.baseY, -Math.cos(d.az * DEG) * d.dist);
    // rock pedestal (part of the backdrop group: it stays when the statue is hidden)
    const g = latheGrid({
      rows: 6, segs: 12,
      profile: (t) => [(8.6 + (1 - t) * 6) * d.scale, -30 + t * (30 - 3.0 * d.scale)],
      rmod: (phi, y) => 1 + (fbm3(Math.cos(phi) * 1.6 + d.az, y * 0.08, Math.sin(phi) * 1.6, 2) - 0.5) * 0.5,
      capTop: true,
    });
    addAll(B, g.map((q) => flatNormals(q.index ? q.toNonIndexed() : q)), trs(base.x, base.y, base.z), { color: rockCol(0.9), glow: () => 0.38, uv: [0, 0] });
  }
  groups.push([0, B.idx.length]);
  for (const d of defs) {
    const base = V(Math.sin(d.az * DEG) * d.dist, d.baseY, -Math.cos(d.az * DEG) * d.dist);
    const yaw = Math.atan2(-base.x, -base.z);
    const place = trs(base.x, base.y, base.z, yaw, 0, 0, d.scale);
    const start = B.idx.length;
    guardian(B, { place, haze: 0.54, q: tier.detail, W: d.W, weapon: d.weapon, crown: d.crown, damage: d.damage, eye: d.eye });
    groups.push([start, B.idx.length - start]);
    const at = (x, y, z) => V(x, y, z).applyMatrix4(place);
    statues.push({
      id: d.id, azimuth: d.az, distance: d.dist, scale: d.scale, yaw,
      position: base.clone(), weapon: d.weapon, weaponSide: d.W, damaged: !!d.damage.arm,
      height: (d.crown ? 36.3 : STATUE.crestTop) * d.scale,
      plinth: { center: at(0, STATUE.plinthTop, 0), radius: STATUE.plinthR * d.scale, topY: base.y + STATUE.plinthTop * d.scale },
      head: at(0, 30, 0.5), eyes: at(0, STATUE.eyes, 2.0), chest: at(0, 23.3, 3.3),
      palm: at(-d.W * 5.3, 25.3, 5.4), weaponTop: d.weapon === 'glaive' ? at(d.W * 8.1, STATUE.glaiveTop, 3.7) : at(d.W * 3.4, 21.2, 5.6),
      weaponFoot: d.weapon === 'glaive' ? at(d.W * 8.1, STATUE.plinthTop, 3.7) : at(d.W * 3.4, STATUE.plinthTop, 5.6),
    });
  }

  const eyes = new THREE.Vector2(0.4, 0.4);
  const farMat = new THREE.ShaderMaterial({
    name: 'env.far',
    vertexShader: FAR_VERT,
    fragmentShader: FAR_FRAG,
    uniforms: {
      uZenith: U.uZenith, uSkyMid: U.uSkyMid, uHorizon: U.uHorizon, uGlow: U.uGlow, uSunHalo: U.uSunHalo, uSunDir: U.uSunDir,
      uFogP: U.uFogP, uFogNear: U.uFogNear, uMood: U.uMood, uCorona: U.uCorona, uRim: U.uRimFar, uKeyDir: U.uKeyDir, uTime: U.uTime,
      uFarCol: { value: new THREE.Color(0.006, 0.0065, 0.009) },
      uCloudY: { value: cy },
      uEyes: { value: eyes },
    },
  });
  const hidden = new THREE.MeshBasicMaterial({ visible: false });
  const geo = B.build();
  groups.forEach(([start, count], i) => geo.addGroup(start, count, i));
  const far = new THREE.Mesh(geo, [farMat, farMat, farMat, hidden]);
  far.name = 'env.far';
  far.frustumCulled = false;
  far.renderOrder = 10;
  statues.forEach((s, i) => {
    const group = geo.groups[i + 1];
    Object.defineProperty(s, 'visible', { get: () => group.materialIndex !== 3, set: (v) => { group.materialIndex = v ? i + 1 : 3; }, enumerable: true });
    Object.defineProperty(s, 'eyeGlow', { get: () => eyes.getComponent(i), set: (v) => { eyes.setComponent(i, Math.max(0, Number(v) || 0)); }, enumerable: true });
    s.triangles = group.count / 3;
  });

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
  return { far, clouds, statues, materials: [farMat, hidden] };
}
