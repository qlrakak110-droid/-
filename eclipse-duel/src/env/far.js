// Far layer: the sea of cloud below the cliff, jagged rock spires in layered aerial perspective, and two colossal
// hooded guardian statues standing in the clouds either side of the eclipse: draped robes with deep fanning folds
// under a cape, both hands clasped on the hilt of a sword planted point-down, a deep cowl with faint ember eyes in
// its shadow, a broken spiked halo, rain streaks and lichen. Built to hold up in a telephoto hero shot.
// Far silhouettes use one cheap shader (sky ambient + eclipse rim + sky-matched haze): one draw call for all of them.

import * as THREE from 'three';
import { DEG } from '../core/math.js';
import { NOISE, SKY_BASE, FOG } from './glsl.js';
import { Builder, latheGrid, addAll, trs, noise3, fbm3, flatNormals, chamferBox, tube, sweep } from './geometry.js';
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
    // weathering on the colossi: rain streaks down the vertical faces, pale lichen crusts on what faces the sky,
    // grime in the hollows; lit a little more by the key so the drapery reads in a telephoto shot
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
  float fres = pow(1.0 - max(dot(n, v), 0.0), 2.0);
  float back = pow(max(dot(dir, uSunDir), 0.0), 6.0);
  float edge = pow(1.0 - abs(dot(n, v)), 3.0);
  float lift = smoothstep(uCloudY, uCloudY + 30.0, vW.y);
  col += (uRim * max(ndl + 0.2, 0.0) * fres + uCorona * 0.1 * edge * back) * (1.0 - 0.55 * f) * lift;
  // ember eyes deep in the cowls: faint, they smoulder rather than shine
  col += vec3(1.9, 0.52, 0.11) * vS.y * (1.0 - 0.5 * f) * (0.85 + 0.15 * sin(uTime * 1.3 + vW.x));
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

/**
 * One colossal hooded guardian (local frame: base at the origin, facing +Z, ~39 m to the halo top before `place`).
 * Smooth normals (the backlit rim needs continuous silhouettes); `haze` < 1 stands it a layer in front of the spires.
 * `q` = detail tier (0..2) scales the tessellation.
 */
function statue(B, mirror, damage, place, haze, q) {
  const tone = (k) => (p, n, o) => { const v = k * (0.75 + 0.5 * noise3(p.x * 0.08, p.y * 0.08, p.z * 0.08)); o[0] = v; o[1] = v; o[2] = v * 1.02; };
  const opt = (k, ember = 0) => ({ color: typeof k === 'number' ? tone(k) : k, glow: () => 1 - haze, uv: [1, ember] });
  const M = (m) => place.clone().multiply(m);
  const s = mirror;
  const FRONT = Math.PI / 2;            // latheGrid: phi = pi/2 faces +Z
  const sm = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t); };
  const V = (x, y, z) => new THREE.Vector3(x, y, z);
  const rows = q >= 1 ? 34 : 20, segs = q >= 1 ? 46 : 30;
  const inv = place.clone().invert();
  const lp = new THREE.Vector3();
  const pleatAt = (phi, y) => {
    const lower = sm(19.5, 1.5, y);
    const front = sm(-0.25, 0.6, Math.sin(phi));
    const fan = (phi - FRONT) / (0.5 + 0.5 * lower);
    const pleat = Math.pow(Math.abs(Math.sin(fan * 4.6 + noise3(y * 0.07, phi * 0.5, 1) * 1.3)), 0.55);
    const back = Math.sin(phi * 7 + 1.4 * noise3(y * 0.09, phi, 3));
    return { front, lower, pleat, back };
  };
  // drapery shading: valleys of the folds darker (baked occlusion), ridges catch more light
  const robeTone = (k, sq) => (p, n, o) => {
    lp.copy(p).applyMatrix4(inv);
    const phi = Math.atan2(lp.z / sq, lp.x);
    const f = pleatAt(phi, lp.y);
    const ridge = f.front * (f.pleat - 0.62) * (0.3 + 1.6 * f.lower) + (1 - f.front) * f.back * 0.35 * (0.35 + 0.65 * f.lower);
    const v = k * (0.78 + 0.45 * noise3(p.x * 0.08, p.y * 0.08, p.z * 0.08)) * Math.max(0.35, 1 + ridge * 0.9);
    o[0] = v; o[1] = v; o[2] = v * 1.02;
  };

  // ---- robe: heavy pleats fanning down from the clasped hands, broad folds behind, pooling at the hem ----------------
  const prof = [[0, 6.7], [1.0, 6.1], [3.5, 5.2], [9, 4.25], [14, 3.8], [17.5, 3.6], [20.2, 3.95], [22.8, 4.7], [24.9, 5.45], [26.4, 5.0], [27.7, 3.6], [28.7, 2.4]];
  const lerpProf = (y) => { for (let i = 1; i < prof.length; i++) if (y <= prof[i][0]) { const a = prof[i - 1], b = prof[i]; const t = (y - a[0]) / (b[0] - a[0]); return a[1] + (b[1] - a[1]) * t; } return prof[prof.length - 1][1]; };
  addAll(B, latheGrid({
    rows, segs, squash: 0.62,
    profile: (t) => { const y = t * 28.7; return [lerpProf(y), y]; },
    bottomY: (phi) => -0.4 - 0.5 * noise3(Math.cos(phi) * 3, Math.sin(phi) * 3, 7),
    rmod: (phi, y) => {
      const { front, lower, pleat, back } = pleatAt(phi, y);
      let m = 1 + (pleat - 0.62) * (0.025 + 0.15 * lower) * front;
      m += back * 0.06 * (1 - front) * (0.35 + 0.65 * lower);
      // drapery sagging between the shoulders and the hands
      if (y > 19.5 && y < 24.8) m += 0.04 * Math.sin((y - 19.5) * 2.1 + Math.abs(phi - FRONT) * 3.2) * front * sm(24.8, 22, y);
      // hem pooling on the plinth
      if (y < 1.6) m += (noise3(Math.cos(phi) * 4, y, Math.sin(phi) * 4) - 0.5) * 0.14 * (1.6 - y);
      m *= 1 + (noise3(Math.cos(phi) * 3, y * 0.35, Math.sin(phi) * 3) - 0.5) * 0.045;
      if (damage.shoulder && y > 22 && y < 28 && Math.cos(phi - (s > 0 ? 0 : Math.PI)) > 0.72) m *= 0.84;
      return m;
    },
    capTop: true,
  }), M(new THREE.Matrix4()), opt(robeTone(1, 0.62)));

  // ---- cape: over the shoulders and down the back, folds deepening toward a tattered hem -----------------------------
  const cprof = [[10.5, 4.9], [15, 4.45], [19, 4.25], [22.5, 5.0], [24.6, 5.8], [25.7, 5.95], [26.9, 4.9], [27.9, 3.5]];
  const lerpC = (y) => { for (let i = 1; i < cprof.length; i++) if (y <= cprof[i][0]) { const a = cprof[i - 1], b = cprof[i]; return a[1] + (b[1] - a[1]) * (y - a[0]) / (b[0] - a[0]); } return cprof[cprof.length - 1][1]; };
  addAll(B, latheGrid({
    rows: q >= 1 ? 18 : 10, segs: q >= 1 ? 30 : 18, squash: 0.66, arc: [FRONT + 0.72, FRONT + Math.PI * 2 - 0.72],
    profile: (t) => { const y = 10.5 + t * 17.4; return [lerpC(y), y]; },
    bottomY: (phi) => 10.5 + 2.2 * noise3(Math.cos(phi) * 2.5, Math.sin(phi) * 2.5, 11) + Math.abs(Math.cos(phi)) * 1.8,
    rmod: (phi, y) => {
      const low = sm(22, 11, y);
      let m = 1 + Math.sin(phi * 9 + noise3(y * 0.1, phi, 5) * 1.6) * 0.06 * low + 0.03;
      if (damage.shoulder && y > 22 && Math.cos(phi - (s > 0 ? 0 : Math.PI)) > 0.7) m *= 0.86;
      return m;
    },
  }), M(new THREE.Matrix4()), opt((p, n, o) => {
    lp.copy(p).applyMatrix4(inv);
    const phi = Math.atan2(lp.z / 0.66, lp.x);
    const v = 0.9 * (0.78 + 0.45 * noise3(p.x * 0.08, p.y * 0.08, p.z * 0.08)) * (1 + Math.sin(phi * 9 + noise3(lp.y * 0.1, phi, 5) * 1.6) * 0.35 * sm(22, 11, lp.y));
    o[0] = v; o[1] = v; o[2] = v * 1.02;
  }));

  // ---- cowl: bowed forward, open at the face, a thick rolled rim; the face a void with two embers ---------------------
  {
    const hm = M(trs(0, 27.5, 0.45, 0, 0.3, 0));
    const H = 6.9, gap = 0.82;
    const hood = latheGrid({
      rows: q >= 1 ? 12 : 8, segs: q >= 1 ? 22 : 14, arc: [FRONT + gap, FRONT + Math.PI * 2 - gap],
      profile: (t) => [t < 0.3 ? 3.05 - t * 0.5 : t < 0.86 ? 2.9 * Math.cos(((t - 0.3) / 0.56) * Math.PI * 0.42) + 0.15 : 1.25 * (1 - (t - 0.86) / 0.14) + 0.12, t * H],
      rmod: (phi, y) => (damage.hood && y > 5.0 ? 0.6 : 1) * (1 + (noise3(Math.cos(phi) * 2, y * 0.8, Math.sin(phi) * 2) - 0.5) * 0.08),
    })[0];
    // the peak leans forward over the brow
    const hp = hood.attributes.position;
    const rim = [[], []];
    for (let i = 0; i < hp.count; i++) {
      const y = hp.getY(i);
      hp.setZ(i, hp.getZ(i) + Math.pow(y / H, 2) * 1.1);
    }
    hood.computeVertexNormals();
    const sg = q >= 1 ? 22 : 14;
    for (let j = 0; j < hp.count / (sg + 1); j++) { const a = j * (sg + 1); rim[0].push(V(hp.getX(a), hp.getY(a), hp.getZ(a))); rim[1].push(V(hp.getX(a + sg), hp.getY(a + sg), hp.getZ(a + sg))); }
    B.add(hood, hm, opt(1));
    const rimPts = [...rim[0], ...rim[1].reverse()].filter((p, i, a) => i === 0 || p.distanceTo(a[i - 1]) > 0.05);
    addAll(B, [tube(rimPts, 0.34, { sides: q >= 1 ? 6 : 4 })], hm, opt(1.05));
    // the void: a dark recessed face, two faint embers
    B.add(new THREE.SphereGeometry(1.0, 10, 8), hm.clone().multiply(trs(0, 2.35, 1.3, 0, 0, 0, 1.55, 2.0, 0.9)), opt(0.12));
    if (!damage.blind) for (const ex of [-0.48, 0.48]) B.add(new THREE.SphereGeometry(0.15, 6, 4), hm.clone().multiply(trs(ex, 2.75, 2.12, 0, 0, 0, 1.4, 0.8, 0.6)), opt(0.12, 1));
  }

  // ---- arms in hanging sleeves; hands clasped on the hilt -------------------------------------------------------------
  const gripX = 0, gripZ = 4.75, guardY = 18.4, pommelY = 21.55;
  const sleeve = (sh, el, wr) => {
    addAll(B, [tube([sh, sh.clone().lerp(el, 0.5).add(V(0, 0, 0.2)), el], (t) => 1.55 - t * 0.2, { sides: q >= 1 ? 9 : 6 })], M(new THREE.Matrix4()), opt(1.25));
    const pts = [];
    for (let i = 0; i <= 6; i++) pts.push(el.clone().lerp(wr, i / 6));
    const g = tube(pts, (t) => 1.15 + t * 0.55, { sides: q >= 1 ? 12 : 8 });
    // the sleeve hangs: vertices under the forearm drop with gravity, more toward the wrist
    const p = g.attributes.position, axis = wr.clone().sub(el).normalize();
    const c = q >= 1 ? 13 : 9;
    for (let i = 0; i < p.count; i++) {
      const t = Math.floor(i / c) / 6;
      const base = el.clone().lerp(wr, t);
      const d = V(p.getX(i), p.getY(i), p.getZ(i)).sub(base);
      d.addScaledVector(axis, -d.dot(axis));
      const down = Math.max(0, -d.y / (d.length() || 1));
      p.setY(i, p.getY(i) - down * down * (0.6 + 2.4 * t));
    }
    g.computeVertexNormals();
    B.add(g, M(new THREE.Matrix4()), opt(1.3));
  };
  // lower hand grips the grip; the upper hand rests over the pommel ring
  const wA = V(s * 1.35, 19.7, 4.15), wB = V(-s * 1.05, 22.1, 3.95);
  if (damage.arm === 1) {
    // a broken forearm: the sleeve ends in a stump, the stone hand still clasps the hilt
    addAll(B, [tube([V(s * 5.2, 25.0, 0.4), V(s * 5.9, 20.6, 1.7)], (t) => 1.55 - t * 0.15, { sides: 8 })], M(new THREE.Matrix4()), opt(0.95));
    addAll(B, [tube([V(s * 5.9, 20.6, 1.7), V(s * 4.6, 20.2, 2.6)], 1.25, { sides: 8, caps: true })], M(new THREE.Matrix4()), opt(0.9));
    addAll(B, [tube([wA.clone().add(V(s * 0.9, 0.05, -0.5)), wA], (t) => 0.55 + t * 0.05, { sides: 6, caps: true })], M(new THREE.Matrix4()), opt(0.9));
  } else sleeve(V(s * 5.2, 25.0, 0.4), V(s * 5.9, 20.4, 1.7), wA);
  sleeve(V(-s * 5.2, 25.0, 0.4), V(-s * 5.5, 21.3, 1.5), wB);
  const finger = (pts, r) => addAll(B, [tube(pts, (t) => r * 1.12 * (1 - 0.25 * t), { sides: q >= 1 ? 5 : 4, caps: true })], M(new THREE.Matrix4()), opt(1.45));
  // hand A: palm on the outer side of the grip, four fingers wrapped around its front, the thumb over them
  B.add(new THREE.SphereGeometry(1, 8, 6), M(trs(gripX + s * 0.68, 19.75, gripZ - 0.05, 0, 0, 0, 0.5, 0.9, 0.78)), opt(1.45));
  for (let k = 0; k < 4; k++) {
    const y = 19.25 + k * 0.3, rr = 0.42 + 0.17;
    const pts = [];
    for (let i = 0; i <= 5; i++) { const a = (s > 0 ? 0 : Math.PI) + s * (i / 5) * 4.0; pts.push(V(gripX + Math.cos(a) * rr, y - i * 0.015, gripZ + Math.sin(a) * rr)); }
    finger(pts, 0.17);
  }
  finger([V(gripX + s * 0.75, 20.3, gripZ + 0.35), V(gripX + s * 0.35, 20.42, gripZ + 0.62), V(gripX - s * 0.15, 20.35, gripZ + 0.68)], 0.18);
  // hand B: palm over the pommel ring, fingers draped over its front edge
  B.add(new THREE.SphereGeometry(1, 8, 6), M(trs(gripX - s * 0.05, pommelY + 0.98, gripZ - 0.15, 0, 0.25, 0, 0.85, 0.42, 0.85)), opt(1.45));
  for (let k = 0; k < 4; k++) {
    const x = gripX + (k - 1.5) * 0.3 - s * 0.05;
    finger([V(x, pommelY + 0.98, gripZ + 0.35), V(x, pommelY + 0.92, gripZ + 0.78), V(x, pommelY + 0.6, gripZ + 1.0), V(x, pommelY + 0.22, gripZ + 0.95)], 0.16 - Math.abs(k - 1.5) * 0.012);
  }
  finger([V(gripX - s * 0.7, pommelY + 0.8, gripZ + 0.2), V(gripX - s * 0.62, pommelY + 0.45, gripZ + 0.62)], 0.17);

  // ---- the sword: eclipse-ring pommel, wrapped grip, drooping quillons, a long fullered blade into the plinth ---------
  addAll(B, [new THREE.TorusGeometry(0.62, 0.21, 6, q >= 1 ? 18 : 12)], M(trs(gripX, pommelY + 0.2, gripZ, 0, 0, 0)), opt(0.88));
  B.add(new THREE.CylinderGeometry(0.42, 0.42, 0.22, 12, 1), M(trs(gripX, pommelY + 0.2, gripZ, 0, Math.PI / 2, 0)), opt(0.25));
  addAll(B, latheGrid({ rows: 6, segs: 8, profile: (t) => [0.4 + 0.05 * Math.abs(Math.sin(t * Math.PI * 6)), guardY + 0.35 + t * (pommelY - guardY - 0.55)] }), M(trs(gripX, 0, gripZ)), opt(0.85));
  {
    const span = 3.7, half = damage.guard ? 1.8 : span;
    const path = [];
    for (let i = 0; i <= 8; i++) {
      const x = -span + (i / 8) * (span + half);
      const droop = 0.85 * Math.pow(Math.abs(x) / span, 2.2);
      path.push({ p: V(gripX + x, guardY - droop, gripZ), side: V(0, 0, 1), up: V(0, 1, 0) });
    }
    const pr = [[-0.32, -0.3], [0.32, -0.3], [0.38, 0], [0.32, 0.3], [-0.32, 0.3], [-0.38, 0], [-0.32, -0.3]];
    B.add(sweep(pr, path), M(new THREE.Matrix4()), opt(0.88));
    B.add(chamferBox(1.5, 1.1, 1.0, 0.15), M(trs(gripX, guardY, gripZ)), opt(0.88));
  }
  addAll(B, latheGrid({
    rows: 5, segs: 8, squash: 0.2,
    profile: (t) => { const u = 1 - t; const y = -1.05 + t * (guardY - 0.45 + 1.05); return [Math.max(0.12, 1.05 * (1 - Math.pow(u, 3) * 0.75) - (u > 0.88 ? (u - 0.88) * 5 : 0)), y]; },
    rmod: (phi) => (Math.abs(Math.cos(phi)) > 0.92 ? 1 : 0.78 + 0.22 * Math.abs(Math.cos(phi))),
  }), M(trs(gripX, 0, gripZ)), opt(0.85));

  // ---- the broken halo: a spiked corona ring behind the cowl on a short stem -----------------------------------------
  {
    const cy = 31.4, cz = -2.5, R = 7.5;
    const brk = damage.hood ? 0.27 : 0.11;
    const a0 = (damage.hood ? 0.9 : -0.35) + brk * Math.PI * 2, a1 = a0 + (1 - brk) * Math.PI * 2;
    const n = q >= 1 ? 40 : 24;
    const path = [];
    for (let i = 0; i <= n; i++) { const a = a0 + (i / n) * (a1 - a0); const r = V(Math.cos(a), Math.sin(a), 0); path.push({ p: V(r.x * R, cy + r.y * R, cz), side: r, up: V(0, 0, 1) }); }
    const pr = [[-0.55, -0.24], [0.55, -0.24], [0.66, 0], [0.55, 0.24], [-0.55, 0.24], [-0.66, 0], [-0.55, -0.24]];
    B.add(sweep(pr, path), M(new THREE.Matrix4()), opt(0.86));
    for (let k = 0; k < 16; k++) {
      const a = (k / 16) * Math.PI * 2 + 0.1;
      const rel = ((a - a0) % (Math.PI * 2) + Math.PI * 2) % (Math.PI * 2);
      if (rel > a1 - a0 - 0.05) continue;
      const len = (k % 2 ? 1.6 : 3.0) * (noise3(k, 1, 2) > 0.8 ? 0.45 : 1);
      const base = V(Math.cos(a) * (R + 0.5), cy + Math.sin(a) * (R + 0.5), cz);
      const q2 = new THREE.Quaternion().setFromUnitVectors(V(0, 1, 0), V(Math.cos(a), Math.sin(a), 0));
      const m = new THREE.Matrix4().compose(base, q2, V(1, 1, 1));
      addAll(B, latheGrid({ rows: 1, segs: 4, squash: 0.45, profile: (t) => [0.5 * (1 - t) + 0.02, t * len], capBottom: true }), M(m), opt(0.86));
    }
    // spokes from the back of the cowl to the ring (the ones in the broken arc snapped off short)
    for (const a of [Math.PI * 1.22, Math.PI * 1.78, Math.PI * 0.5]) {
      const rel = ((a - a0) % (Math.PI * 2) + Math.PI * 2) % (Math.PI * 2);
      const reach = rel > a1 - a0 ? 0.45 : 1;
      const end = V(Math.cos(a) * R * reach, cy + Math.sin(a) * R * reach, cz);
      addAll(B, [tube([V(Math.cos(a) * 1.6, cy - 1.2 + Math.sin(a) * 1.6, cz + 0.6), end], (t) => 0.42 - t * 0.12, { sides: 5, caps: true })], M(new THREE.Matrix4()), opt(0.86));
    }
  }
}

/**
 * Build far silhouettes + cloud sea.
 * @returns {{ far: THREE.Mesh, clouds: THREE.Mesh }}
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
    addAll(B, g.map((x) => flatNormals(x.index ? x.toNonIndexed() : x)), trs(p.x, p.y, p.z, rng.range(0, 6)), { color: rockCol(k), uv: [0, 0] });
  };
  // [az, dist, height above clouds, base radius]
  const spires = [
    [-38, 150, 44, 14], [-47, 125, 30, 11], [-58, 175, 70, 18], [-70, 140, 38, 12], [-84, 210, 92, 24], [-102, 160, 55, 16], [-121, 190, 40, 14],
    [36, 170, 52, 15], [49, 140, 34, 10], [61, 200, 84, 22], [74, 155, 46, 13], [90, 230, 66, 20], [108, 170, 50, 15], [124, 200, 36, 12],
    [-16, 420, 30, 16], [12, 470, 24, 14], [-27, 330, 46, 18], [25, 360, 40, 16], [-64, 380, 110, 30], [70, 420, 120, 34],
    [-12, 230, 30, 12], [10.5, 255, 24, 10], [-3, 390, 17, 12], [16, 300, 34, 13],
  ];
  for (const [az, d, h, r] of spires) spire(az, d, h, r, rng.range(0, 50), d > 300 ? 0.8 : 1);

  // colossi on their rock pedestals, facing the arena
  // they flank the eclipse inside the vista window between the gap pillars, standing in the cloud sea so that their
  // halos top out ~8.5 degrees up (the fight camera's frame ends ~12 degrees up)
  for (const [az, mirror, damage] of [[-13.5, -1, { arm: 1, hood: true }], [15.5, 1, { shoulder: true, guard: true }]]) {
    // left: the cowl's peak and a third of the halo are gone, the right forearm broken off (the hand still holds);
    // right: a shoulder sheared away, one quillon snapped
    const dist = 230;
    const base = new THREE.Vector3(Math.sin(az * DEG) * dist, -14, -Math.cos(az * DEG) * dist);
    const face = Math.atan2(-base.x, -base.z);
    const place = trs(base.x, base.y, base.z, face, 0, 0, 1.3);
    statue(B, mirror, damage, place, 0.54, tier.detail);
    // rock pedestal rising from the cloud sea
    const g = latheGrid({
      rows: 6, segs: 12,
      profile: (t) => [9.5 + (1 - t) * 6, -26 + t * 26.5],
      rmod: (phi, y) => 1 + (fbm3(Math.cos(phi) * 1.6 + az, y * 0.08, Math.sin(phi) * 1.6, 2) - 0.5) * 0.5,
      capTop: true,
    });
    addAll(B, g.map((x) => flatNormals(x.index ? x.toNonIndexed() : x)), trs(base.x, base.y, base.z), { color: rockCol(0.9), glow: () => 0.38, uv: [0, 0] });
  }
  // a distant broken watchtower on the far right spire
  {
    const p = new THREE.Vector3(Math.sin(61 * DEG) * 200, cy - 6 + 84 + 6 - 4, -Math.cos(61 * DEG) * 200);
    addAll(B, latheGrid({ rows: 6, segs: 10, profile: (t) => [3.2 - t * 0.6, t * 20], topY: (phi) => 20 - Math.abs(Math.sin(phi * 2.5)) * 6, capTop: 15 }).map((x) => flatNormals(x.index ? x.toNonIndexed() : x)), trs(p.x, p.y, p.z), { color: rockCol(0.85), uv: [0, 0] });
  }

  const farMat = new THREE.ShaderMaterial({
    name: 'env.far',
    vertexShader: FAR_VERT,
    fragmentShader: FAR_FRAG,
    uniforms: {
      uZenith: U.uZenith, uSkyMid: U.uSkyMid, uHorizon: U.uHorizon, uGlow: U.uGlow, uSunHalo: U.uSunHalo, uSunDir: U.uSunDir,
      uFogP: U.uFogP, uFogNear: U.uFogNear, uMood: U.uMood, uCorona: U.uCorona, uRim: U.uRimFar, uKeyDir: U.uKeyDir, uTime: U.uTime,
      uFarCol: { value: new THREE.Color(0.006, 0.0065, 0.009) },
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
  return { far, clouds };
}
