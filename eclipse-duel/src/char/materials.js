// Character material kit: one MeshStandardMaterial per slot (= one draw call), extended so a single draw call can carry
// many surface types. Per-vertex attributes written by the build system (src/char/build.js):
//   color (vec3)  albedo (linear)
//   surf  (vec4)  x roughness, y metalness, z texture set + detail amount (see surfDetail()), w cavity / edge:
//                 w < 1 crevice / occlusion (darker, grimier), w = 1 neutral, 1 < w <= 2 convex edge (edge wear)
//   glow  (vec3)  legacy mode: emissive HDR radiance. Channel mode (material option `glow`): masks of the three glow
//                 channels (x inlay, y vein (x the set's vein mask: cracks / engraved grooves), z eye). Cloth and fur
//                 sets: (u, v, edge code) of the cloth surface (torn / burnt hems, fur strand alpha) instead.
//
// Fragment shader (onBeforeCompile on MeshStandardMaterial, one shared program for every character):
//   * texture sets (src/char/kit/textures.js): triplanar albedo / roughness variation and whiteout-blended normal maps
//     sampled in bind-pose space (sticks to the surface), per-set tiling and bump strength
//   * edge wear on convex edges (bare metal, chipped by noise), crevice grime from vertex cavity + micro cavity
//   * heat tint around cracks (scorched set), emissive inlay / vein / eye channels whose colour and intensity are
//     uniforms (animate them at runtime without recompiling: createGlowControl / attachGlow)
//   * fresnel rim term (silhouettes against the dark arena) and the fresnel-weighted hit flash (uFlash)
//   * cutout materials (option `cutout`): torn and burnt cloth hems with ember-lit edges, fur strand alpha
// Surface value 0..1 in surf.z keeps the original behaviour (legacy detail texture), so older designs render unchanged.

import * as THREE from 'three';
import { makeRng } from '../core/math.js';
import { getTextureSets, SET, SET_SCALE, SET_BUMP, configureTextureSets } from './kit/textures.js';

export { SET, configureTextureSets };

let detailTex = null;

/** Shared 256x256 tileable detail texture (legacy set 0): R mottling fbm, G scratches, B hammered cells (height), A fine grain. */
export function getDetailTexture() {
  if (detailTex) return detailTex;
  const N = 256;
  const rng = makeRng(90210);
  const data = new Uint8Array(N * N * 4);
  // periodic value noise
  const lattice = (P) => { const a = new Float32Array(P * P); for (let i = 0; i < a.length; i++) a[i] = rng(); return a; };
  const octs = [8, 16, 32, 64].map((P) => ({ P, L: lattice(P) }));
  const vnoise = (o, x, y) => {
    const P = o.P, fx = (x / N) * P, fy = (y / N) * P;
    const ix = Math.floor(fx), iy = Math.floor(fy), tx = fx - ix, ty = fy - iy;
    const sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty);
    const g = (a, b) => o.L[((b % P) + P) % P * P + ((a % P) + P) % P];
    const a = g(ix, iy) + (g(ix + 1, iy) - g(ix, iy)) * sx;
    const b = g(ix, iy + 1) + (g(ix + 1, iy + 1) - g(ix, iy + 1)) * sx;
    return a + (b - a) * sy;
  };
  // worley cells (periodic), 12x12 feature points
  const C = 12, pts = new Float32Array(C * C * 2);
  for (let i = 0; i < C * C; i++) { pts[i * 2] = rng(); pts[i * 2 + 1] = rng(); }
  const worley = (x, y) => {
    const fx = (x / N) * C, fy = (y / N) * C, ix = Math.floor(fx), iy = Math.floor(fy);
    let d1 = 9;
    for (let oy = -1; oy <= 1; oy++) for (let ox = -1; ox <= 1; ox++) {
      const cx = ix + ox, cy = iy + oy, w = (((cy % C) + C) % C) * C + (((cx % C) + C) % C);
      const dx = cx + pts[w * 2] - fx, dy = cy + pts[w * 2 + 1] - fy, d = dx * dx + dy * dy;
      if (d < d1) d1 = d;
    }
    return Math.sqrt(d1);
  };
  // scratches: accumulate thin lines into a float buffer (wrapping)
  const scr = new Float32Array(N * N);
  for (let k = 0; k < 220; k++) {
    const x0 = rng() * N, y0 = rng() * N;
    const ang = rng() < 0.6 ? 0.35 + (rng() - 0.5) * 0.5 : rng() * Math.PI;
    const len = 6 + rng() * rng() * 70, val = (rng() < 0.5 ? -1 : 1) * (0.25 + rng() * 0.75);
    for (let s = 0; s < len; s += 0.5) {
      const x = Math.floor(x0 + Math.cos(ang) * s), y = Math.floor(y0 + Math.sin(ang) * s);
      scr[((y % N) + N) % N * N + ((x % N) + N) % N] += val * (1 - s / len * 0.5);
    }
  }
  for (let y = 0; y < N; y++) {
    for (let x = 0; x < N; x++) {
      let f = 0, amp = 0.55, sum = 0;
      for (const o of octs) { f += vnoise(o, x, y) * amp; sum += amp; amp *= 0.55; }
      f /= sum;
      const w = worley(x, y);
      const i = (y * N + x) * 4;
      data[i] = Math.round(Math.min(1, Math.max(0, (f - 0.5) * 1.6 + 0.5)) * 255);
      data[i + 1] = Math.round(Math.min(1, Math.max(0, 0.5 + scr[y * N + x] * 0.5)) * 255);
      data[i + 2] = Math.round(Math.min(1, w * w * 1.6) * 255);
      data[i + 3] = Math.round(rng() * 255);
    }
  }
  detailTex = new THREE.DataTexture(data, N, N, THREE.RGBAFormat, THREE.UnsignedByteType);
  detailTex.wrapS = detailTex.wrapT = THREE.RepeatWrapping;
  detailTex.magFilter = THREE.LinearFilter;
  detailTex.minFilter = THREE.LinearMipmapLinearFilter;
  detailTex.generateMipmaps = true;
  detailTex.colorSpace = THREE.NoColorSpace;
  detailTex.needsUpdate = true;
  return detailTex;
}

/**
 * Encode a texture set and its detail amount into the `detail` surface option (surf.z).
 * set 0 (legacy) keeps the 0..1 meaning; set k >= 1 -> 2k + 0.25 + 0.5 * amount (robust to interpolation error).
 * @param {number|string} set  SET id or name ('hammered', 'scorched', 'engraved', 'leather', 'cloth', 'fur', 'mail', 'quilted')
 * @param {number} amount 0..1 (scales normal, albedo and roughness variation of the set)
 */
export function surfDetail(set, amount = 1) {
  const k = typeof set === 'string' ? SET[set] : set;
  if (!k) return Math.max(0, Math.min(1, amount));
  return 2 * k + 0.25 + 0.5 * Math.max(0, Math.min(1, amount));
}

/** Decode surf.z back into { set, amount } (tools / tests). */
export function decodeDetail(z) {
  if (z < 1.5) return { set: 0, amount: z };
  const set = Math.floor(z * 0.5);
  return { set, amount: Math.max(0, Math.min(1, (z - 2 * set - 0.25) * 2)) };
}

const VERT_PARS = /* glsl */ `
attribute vec4 surf;
attribute vec3 glow;
varying vec4 vSurf;
varying vec3 vGlow;
varying vec3 vRestPos;
varying vec3 vB0;
varying vec3 vB1;
varying vec3 vB2;
`;
const VERT_MAIN = /* glsl */ `
  vSurf = surf; vGlow = glow; vRestPos = position;
`;
// bind-pose -> view rotation (skinning x normal matrix): maps triplanar rest-space normals into view space
const VERT_NORMAL = /* glsl */ `
  {
    mat3 edM = mat3(normalMatrix);
    #ifdef USE_SKINNING
      edM = edM * mat3(skinMatrix);
    #endif
    vB0 = edM[0]; vB1 = edM[1]; vB2 = edM[2];
  }
`;

const FRAG_PARS = /* glsl */ `
uniform sampler2D uDetail;
uniform highp sampler2DArray uSets;
uniform float uDetailScale;
uniform float uBump;
uniform vec3 uFlash;
uniform float uGlowScale;
uniform float uGlowMode;
uniform vec3 uGlowA;
uniform vec3 uGlowB;
uniform vec3 uGlowC;
uniform vec4 uRim;
uniform vec4 uWear;
uniform vec3 uWearColor;
uniform vec3 uGrimeColor;
uniform vec3 uHeatColor;
uniform vec4 uEmber;
uniform float uSetScale[9];
uniform float uSetBump[9];
uniform float uDetailMul;
varying vec4 vSurf;
varying vec3 vGlow;
varying vec3 vRestPos;
varying vec3 vB0;
varying vec3 vB1;
varying vec3 vB2;
vec4 edTriplanar(vec3 p, vec3 n) {
  vec3 w = pow(abs(n), vec3(4.0));
  w /= max(1e-4, w.x + w.y + w.z);
  return texture2D(uDetail, p.zy) * w.x + texture2D(uDetail, p.xz) * w.y + texture2D(uDetail, p.xy) * w.z;
}
vec3 edPerturb(vec3 surfPos, vec3 surfNorm, vec2 dHdxy, float faceDir) {
  vec3 vSigmaX = normalize(dFdx(surfPos));
  vec3 vSigmaY = normalize(dFdy(surfPos));
  vec3 vN = surfNorm;
  vec3 R1 = cross(vSigmaY, vN);
  vec3 R2 = cross(vN, vSigmaX);
  float fDet = dot(vSigmaX, R1) * faceDir;
  vec3 vGrad = sign(fDet) * (dHdxy.x * R1 + dHdxy.y * R2);
  return normalize(abs(fDet) * surfNorm - vGrad);
}
vec4 edSet(vec2 uv, float layer) { return texture(uSets, vec3(uv, layer)); }
vec3 edTn(vec4 b, float k) { vec2 xy = (b.xy * 2.0 - 1.0) * k; return vec3(xy, sqrt(max(0.0, 1.0 - dot(xy, xy)))); }
`;

// all per-surface work happens right after the vertex colour is applied (normal-independent inputs are ready there)
const FRAG_SURFACE = /* glsl */ `
  float edFace = gl_FrontFacing ? 1.0 : -1.0;
  mat3 edM = mat3(normalize(vB0), normalize(vB1), normalize(vB2));
  vec3 edNv = normalize(vNormal);
  #ifdef DOUBLE_SIDED
    edNv *= edFace;
  #endif
  vec3 edNr = normalize(edNv * edM);
  float edSz = vSurf.z;
  float edSetF = edSz < 1.5 ? 0.0 : floor(edSz * 0.5);
  int edSi = int(edSetF + 0.5);
  float edAmt = edSz < 1.5 ? edSz : clamp((edSz - 2.0 * edSetF - 0.25) * 2.0, 0.0, 1.0);
  float edCav = vSurf.w;
  float edOcc = min(edCav, 1.0);
  float edEdge = max(edCav - 1.0, 0.0);
  float edRoughMul = 1.0, edRoughAdd = 0.0, edMetalMul = 1.0;
  vec3 edNrP = edNr;
  vec3 edEmis = vec3(0.0);
  vec4 edDet = vec4(0.5);
  if (edSi == 0) {
    edDet = edTriplanar(vRestPos * uDetailScale, edNr);
    diffuseColor.rgb *= mix(1.0, 0.72 + 0.56 * edDet.r, edAmt) * vSurf.w;
    edEmis = vGlow * uGlowScale;
  } else {
    float edL = (edSetF - 1.0) * 2.0;
    bool edUv = edSi == 5 || edSi == 6;
    vec4 edA, edB;
    if (edSi == 6) {
      // fur cards: u across the card, v root -> tip
      vec2 fuv = vec2(vGlow.x * 3.0, vGlow.y * 0.55);
      edA = edSet(fuv, edL); edB = edSet(fuv, edL + 1.0);
      edNrP = edNr;
      #ifdef ED_CUTOUT
        float strand = edB.a;
        if (strand < vGlow.y * 0.9 + 0.08) discard;
      #endif
      diffuseColor.rgb *= mix(0.25, 1.15, smoothstep(0.0, 0.85, vGlow.y)) * (0.75 + 0.5 * edA.r);
    } else {
      vec3 p = vRestPos * (uSetScale[edSi] * uDetailMul);
      vec3 w = pow(abs(edNr), vec3(4.0));
      w /= max(1e-4, w.x + w.y + w.z);
      vec4 aX = edSet(p.zy, edL), aY = edSet(p.xz, edL), aZ = edSet(p.xy, edL);
      vec4 bX = edSet(p.zy, edL + 1.0), bY = edSet(p.xz, edL + 1.0), bZ = edSet(p.xy, edL + 1.0);
      edA = aX * w.x + aY * w.y + aZ * w.z;
      edB = bX * w.x + bY * w.y + bZ * w.z;
      float k = uSetBump[edSi] * uBump * edAmt;
      vec3 tX = edTn(bX, k), tY = edTn(bY, k), tZ = edTn(bZ, k);
      tX = vec3(tX.xy + edNr.zy, abs(tX.z) * edNr.x);
      tY = vec3(tY.xy + edNr.xz, abs(tY.z) * edNr.y);
      tZ = vec3(tZ.xy + edNr.xy, abs(tZ.z) * edNr.z);
      edNrP = normalize(tX.zyx * w.x + tY.xzy * w.y + tZ.xyz * w.z);
    }
    float edMicro = mix(1.0, edB.b, edAmt);
    // cloth hems: torn, charred, ember-lit edges (u, v, code in vGlow)
    float edChar = 0.0;
    #ifdef ED_CUTOUT
    if (edSi == 5) {
      vec2 cuv = vGlow.xy;
      float code = vGlow.z;
      float sides = floor(code * 0.5 + 0.01);
      float burn = clamp(code - 2.0 * sides, 0.0, 1.0);
      float e1 = edSet(vec2(cuv.x * 0.83 + 0.13, 0.27), 0.0).a;
      float e2 = edSet(vec2(cuv.x * 3.7 + 0.4, 0.61), 0.0).a;
      float e3 = edSet(vec2(cuv.x * 11.0, 0.13), 0.0).a;
      float rip = pow(clamp(e1 * 1.5 - 0.35, 0.0, 1.0), 2.5);
      float depth = burn * (0.03 + 0.07 * e2 + 0.03 * e3 + 0.42 * rip);
      float d = (1.0 - depth) - cuv.y;
      if (mod(sides, 2.0) > 0.5) {
        float s1 = edSet(vec2(0.71, cuv.y * 1.9), 0.0).a;
        d = min(d, cuv.x - burn * (0.02 + 0.09 * s1 * s1) * smoothstep(0.15, 0.9, cuv.y));
      }
      if (sides > 1.5) {
        float s2 = edSet(vec2(0.37, cuv.y * 2.3 + 0.5), 0.0).a;
        d = min(d, (1.0 - cuv.x) - burn * (0.02 + 0.09 * s2 * s2) * smoothstep(0.15, 0.9, cuv.y));
      }
      float hn = edSet(cuv * vec2(1.1, 1.6) + vec2(0.31, 0.77), 0.0).a;
      float holeT = 0.86 - 0.16 * burn * smoothstep(0.35, 1.0, cuv.y);
      d = min(d, (holeT - hn) * 0.45);
      if (d < 0.0) discard;
      edChar = (1.0 - smoothstep(0.0, 0.02 + 0.07 * burn, d)) * burn;
      float ember = (1.0 - smoothstep(0.0, 0.006 + 0.004 * burn, d)) * burn;
      float fl = 0.65 + 0.35 * sin(uEmber.x * 3.1 + cuv.x * 37.0 + cuv.y * 11.0);
      edEmis += uGlowB * ember * fl * 0.55;
    }
    #endif
    // albedo: variation, heat tint near cracks, chipped edge wear, crevice grime, occlusion
    vec3 base = diffuseColor.rgb * (1.0 + (edA.r - 0.5) * uWear.z * edAmt * 2.0);
    float metal = vSurf.y;
    if (edSi == 2) {
      float heat = edA.b * uWear.w;
      base = mix(base, uHeatColor * (0.35 + 0.65 * dot(base, vec3(0.3333)) * 3.0), heat * 0.55);
    }
    float chip = edA.a;
    float edgeW = edEdge * uWear.x;
    float wear = smoothstep(0.5, 0.62, edgeW * 1.1 + (chip - 0.5) * 0.85 * min(1.0, edgeW * 2.5));
    vec3 worn = mix(base * 1.7 + 0.025, uWearColor, metal);
    base = mix(base, worn, wear);
    float grime = clamp((1.0 - edOcc) * 1.25 + (1.0 - edMicro) * 0.9, 0.0, 1.0) * uWear.y;
    base = mix(base, base * uGrimeColor, grime);
    base *= mix(1.0, edOcc, 0.7);
    base = mix(base, vec3(0.014, 0.011, 0.01), edChar * 0.94);
    diffuseColor.rgb = base;
    edRoughMul = (1.0 + (edA.g - 0.5) * 1.1 * edAmt) * (1.0 - 0.5 * wear);
    edRoughAdd = grime * 0.22 + edChar * 0.35;
    if (!edUv && uGlowMode > 0.5) {
      float vein = edB.a;
      float fl = 0.82 + 0.18 * sin(uEmber.x * uEmber.y + edA.a * 9.0 + edA.r * 5.0);
      float veinK = vGlow.y * (vein + edA.b * uEmber.w);
      edEmis += vGlow.x * uGlowA + veinK * fl * uGlowB + vGlow.z * uGlowC;
      // glowing fissures are open cracks: dark, rough, not metallic
      float vk = clamp(vGlow.y * vein * 1.6, 0.0, 1.0);
      diffuseColor.rgb *= 1.0 - 0.9 * vk;
      edRoughAdd += 0.45 * vk;
      edMetalMul = 1.0 - 0.8 * vk;
      edEmis *= uGlowScale;
    } else if (!edUv) {
      edEmis += vGlow * uGlowScale;
    }
  }
`;

/**
 * Create a kit material for one slot.
 * @param {object} o
 *   color=0xffffff        multiplies the vertex colour            roughness=1, metalness=1   multiplied by surf
 *   envMapIntensity=1     side='front'|'double'                    flatShading=false
 *   detailScale=9         legacy set 0: detail tiles per metre    bump=0.6   normal / bump strength (all sets)
 *   detailMul=1           scales the tiling of every texture set (SET_SCALE per set)
 *   glowScale=1           emissive multiplier
 *   glow                  channel mode: { inlay: [r,g,b], vein: [r,g,b], eye: [r,g,b] } HDR colours (vertex glow = masks)
 *   rim=[0,0,0,3]         fresnel rim: [r, g, b, power] HDR colour (0 = off)
 *   wear=[0.9, 0.8, 0.35, 0.6]   [edge wear, crevice grime, albedo variation, heat tint] strengths
 *   wearColor=0x8a8d93    bare-metal colour revealed by edge wear (sRGB hex or linear [r,g,b])
 *   grimeColor=[0.28,0.24,0.21]  albedo multiplier in crevices      heatColor=[0.16,0.1,0.18] temper tint near cracks
 *   ember=[0, 2.2, 0, 0.12]      [time, flicker speed, -, vein halo glow]
 *   cutout=false          alpha-tested cloth / fur (torn hems, strand alpha); separate program
 */
export function createKitMaterial(o = {}) {
  const mat = new THREE.MeshStandardMaterial({
    color: o.color ?? 0xffffff,
    roughness: o.roughness ?? 1,
    metalness: o.metalness ?? 1,
    envMapIntensity: o.envMapIntensity ?? 1,
    vertexColors: true,
    side: o.side === 'double' || o.cutout ? THREE.DoubleSide : THREE.FrontSide,
    flatShading: !!o.flatShading,
  });
  const lin = (c, def) => {
    if (c === undefined) return new THREE.Color(...def);
    if (Array.isArray(c)) return new THREE.Color(c[0], c[1], c[2]);
    return new THREE.Color(c);
  };
  const g = o.glow || null;
  const rim = o.rim || [0, 0, 0, 3];
  const wear = o.wear || [0.9, 0.8, 0.35, 0.6];
  const uniforms = {
    uDetail: { value: getDetailTexture() },
    uSets: { value: getTextureSets() },
    uDetailScale: { value: o.detailScale ?? 9 },
    uDetailMul: { value: o.detailMul ?? 1 },
    uBump: { value: o.bump ?? 0.6 },
    uFlash: { value: new THREE.Color(0, 0, 0) },
    uGlowScale: { value: o.glowScale ?? 1 },
    uGlowMode: { value: g ? 1 : 0 },
    uGlowA: { value: lin(g && g.inlay, [0, 0, 0]) },
    uGlowB: { value: lin(g && g.vein, [0, 0, 0]) },
    uGlowC: { value: lin(g && g.eye, [0, 0, 0]) },
    uRim: { value: new THREE.Vector4(rim[0], rim[1], rim[2], rim[3] ?? 3) },
    uWear: { value: new THREE.Vector4(wear[0], wear[1], wear[2], wear[3]) },
    uWearColor: { value: lin(o.wearColor, [0.26, 0.27, 0.29]) },
    uGrimeColor: { value: lin(o.grimeColor, [0.28, 0.24, 0.21]) },
    uHeatColor: { value: lin(o.heatColor, [0.16, 0.1, 0.18]) },
    uEmber: { value: new THREE.Vector4(...(o.ember || [0, 2.2, 0, 0.05])) },
    uSetScale: { value: SET_SCALE.slice() },
    uSetBump: { value: SET_BUMP.slice() },
  };
  if (o.wearColor !== undefined && !Array.isArray(o.wearColor)) uniforms.uWearColor.value.set(o.wearColor);
  mat.userData.kit = uniforms;
  if (o.cutout) mat.defines = { ED_CUTOUT: '' };
  mat.onBeforeCompile = (shader) => {
    Object.assign(shader.uniforms, uniforms);
    shader.vertexShader = shader.vertexShader
      .replace('#include <common>', '#include <common>\n' + VERT_PARS)
      .replace('#include <begin_vertex>', '#include <begin_vertex>\n' + VERT_MAIN)
      .replace('#include <defaultnormal_vertex>', '#include <defaultnormal_vertex>\n' + VERT_NORMAL);
    shader.fragmentShader = shader.fragmentShader
      .replace('#include <common>', '#include <common>\n' + FRAG_PARS)
      .replace('#include <color_fragment>', '#include <color_fragment>\n' + FRAG_SURFACE)
      .replace('#include <roughnessmap_fragment>', `#include <roughnessmap_fragment>
  if (edSi == 0) roughnessFactor = clamp(roughnessFactor * vSurf.x * (1.0 + (edDet.r - 0.5) * 0.5 * edAmt) + (edDet.g - 0.5) * 0.45 * edAmt, 0.045, 1.0);
  else roughnessFactor = clamp(roughnessFactor * vSurf.x * edRoughMul + edRoughAdd, 0.045, 1.0);`)
      .replace('#include <metalnessmap_fragment>', `#include <metalnessmap_fragment>
  metalnessFactor *= vSurf.y * edMetalMul;`)
      .replace('#include <normal_fragment_maps>', `#include <normal_fragment_maps>
  if (edSi == 0) {
    float edH = edDet.b + (edDet.a - 0.5) * 0.12;
    vec2 edD = vec2(dFdx(edH), dFdy(edH)) * uBump * edAmt;
    normal = edPerturb(-vViewPosition, normal, edD, faceDirection);
  } else {
    normal = normalize(edM * edNrP);
  }`)
      .replace('#include <emissivemap_fragment>', `#include <emissivemap_fragment>
  {
    float edNdV = saturate(dot(normal, normalize(vViewPosition)));
    float edFres = pow(1.0 - edNdV, 2.0);
    totalEmissiveRadiance += edEmis + uFlash * (0.3 + 0.7 * edFres);
    totalEmissiveRadiance += uRim.rgb * pow(1.0 - edNdV, uRim.w) * saturate(normal.y * 0.55 + 0.6) * edOcc;
  }`);
  };
  mat.customProgramCacheKey = () => (o.cutout ? 'edkit-v2-cut' : 'edkit-v2');
  return mat;
}

// ---- glow control ---------------------------------------------------------------------------------------------------

const CHANNELS = { inlay: 'uGlowA', vein: 'uGlowB', eye: 'uGlowC' };

/**
 * Runtime control of the emissive channels of a set of kit materials (one character). Colours are HDR linear; nothing
 * recompiles. `update(dtGame, dtReal)` advances the ember flicker clock (game time) and the flare envelopes.
 *
 *   const glow = createGlowControl(char.materials, { inlay: [6, 2, 0.4], vein: [7, 2.2, 0.4], eye: [9, 3.4, 0.9] });
 *   glow.set('vein', [9, 3, 0.5], 1.5);         // colour, intensity
 *   glow.flare('all', 2.5, 0.6);                // +250% for 0.6 s (attack 0.06 s, quadratic release)
 *   glow.gain = 0.4;                            // master multiplier (e.g. KO: cracks cool down)
 *   glow.rim([0.5, 0.65, 1.0], 3.2);           // rim colour / power of every material
 *
 * @param {object|THREE.Material[]} materials  { slot: material } (char.materials) or an array
 * @param {object} spec  { inlay, vein, eye: [r,g,b] HDR base colours, slots?: [names] (default: all with channel mode) }
 */
export function createGlowControl(materials, spec = {}) {
  const list = (Array.isArray(materials) ? materials : Object.entries(materials)
    .filter(([slot]) => !spec.slots || spec.slots.includes(slot)).map(([, m]) => m))
    .filter((m) => m && m.userData && m.userData.kit);
  const ch = {};
  for (const name of Object.keys(CHANNELS)) {
    const c = spec[name] || [0, 0, 0];
    ch[name] = { base: new THREE.Color(c[0], c[1], c[2]), intensity: 1, flare: 0, fT: 1, fDur: 0.5, fAtk: 0.06 };
  }
  const tmp = new THREE.Color();
  let time = 0;
  const ctl = {
    gain: 1,
    channels: ch,
    /** Set a channel's base colour ([r,g,b] HDR | hex | THREE.Color) and intensity multiplier. */
    set(name, color, intensity = 1) {
      const c = ch[name];
      if (!c) return ctl;
      if (color != null) { if (Array.isArray(color)) c.base.setRGB(color[0], color[1], color[2]); else c.base.set(color); }
      c.intensity = intensity;
      ctl.apply();
      return ctl;
    },
    /** Temporary boost: intensity x (1 + amount * envelope) over dur seconds (game time). name: channel | 'all'. */
    flare(name, amount = 2, dur = 0.5, { attack = 0.06 } = {}) {
      for (const n of name === 'all' ? Object.keys(ch) : [name]) {
        const c = ch[n];
        if (!c) continue;
        c.flare = amount; c.fT = 0; c.fDur = Math.max(1e-3, dur); c.fAtk = Math.min(attack, dur * 0.5);
      }
      return ctl;
    },
    /** Fresnel rim of every material: colour [r,g,b] HDR, power (2 broad .. 6 thin). */
    rim(color, power) {
      for (const m of list) {
        const u = m.userData.kit.uRim.value;
        if (color) { u.x = color[0]; u.y = color[1]; u.z = color[2]; }
        if (power) u.w = power;
      }
      return ctl;
    },
    /** Advance flicker time and flare envelopes. */
    update(dtGame = 0) {
      time += dtGame;
      for (const n in ch) {
        const c = ch[n];
        if (c.fT < 1) c.fT = Math.min(1, c.fT + dtGame / c.fDur);
      }
      ctl.apply();
      return ctl;
    },
    /** Write the uniforms now. */
    apply() {
      for (const n in ch) {
        const c = ch[n];
        let env = 0;
        if (c.fT < 1) {
          const t = c.fT * c.fDur;
          env = t < c.fAtk ? t / c.fAtk : (1 - (t - c.fAtk) / Math.max(1e-3, c.fDur - c.fAtk)) ** 2;
        }
        tmp.copy(c.base).multiplyScalar(c.intensity * ctl.gain * (1 + c.flare * env));
        for (const m of list) m.userData.kit[CHANNELS[n]].value.copy(tmp);
      }
      for (const m of list) m.userData.kit.uEmber.value.x = time;
      return ctl;
    },
    get time() { return time; },
  };
  ctl.apply();
  return ctl;
}

/**
 * Attach a glow control to a Character: char.glow = control, and char.update() also advances it (wraps the method,
 * until the rig calls design hooks itself). spec defaults to the design's `glow` (see createGlowControl).
 */
export function attachGlow(char, spec = char.design && char.design.glow) {
  if (char.glow) return char.glow;
  const ctl = createGlowControl(char.materials, spec || {});
  const update = char.update;
  char.update = function (dtGame, dtReal) {
    const r = update.call(char, dtGame, dtReal);
    ctl.update(dtGame || 0, dtReal || 0);
    return r;
  };
  char.glow = ctl;
  return ctl;
}
