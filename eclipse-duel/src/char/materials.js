// Character material kit: one MeshStandardMaterial per slot, extended so a single draw call can carry many surface
// types. Per-vertex attributes written by the build system:
//   color (vec3)  albedo (linear)               surf (vec4)  x roughness, y metalness, z detail amount, w cavity/AO
//   glow  (vec3)  emissive HDR radiance (linear, added on top of lighting)
// The fragment shader adds triplanar procedural detail (hammered dents -> bump, scratches -> roughness, mottling ->
// albedo) sampled in bind-pose space so it sticks to the surface, and a fresnel-weighted hit flash (uFlash).

import * as THREE from 'three';
import { makeRng } from '../core/math.js';

let detailTex = null;

/** Shared 256x256 tileable detail texture: R mottling fbm, G scratches, B hammered cells (height), A fine grain. */
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

const VERT_PARS = /* glsl */ `
attribute vec4 surf;
attribute vec3 glow;
varying vec4 vSurf;
varying vec3 vGlow;
varying vec3 vRestPos;
varying vec3 vRestNrm;
`;
const VERT_MAIN = /* glsl */ `
  vSurf = surf; vGlow = glow; vRestPos = position; vRestNrm = normal;
`;
const FRAG_PARS = /* glsl */ `
uniform sampler2D uDetail;
uniform float uDetailScale;
uniform float uBump;
uniform vec3 uFlash;
uniform float uGlowScale;
varying vec4 vSurf;
varying vec3 vGlow;
varying vec3 vRestPos;
varying vec3 vRestNrm;
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
`;

/**
 * Create a kit material for one slot.
 * @param {object} o  { color=0xffffff (multiplies vertex colour), roughness=1, metalness=1 (multiplied by surf),
 *                      envMapIntensity=1, detailScale=9 (tiles per metre), bump=0.6, side='front'|'double',
 *                      glowScale=1, flatShading=false }
 */
export function createKitMaterial(o = {}) {
  const mat = new THREE.MeshStandardMaterial({
    color: o.color ?? 0xffffff,
    roughness: o.roughness ?? 1,
    metalness: o.metalness ?? 1,
    envMapIntensity: o.envMapIntensity ?? 1,
    vertexColors: true,
    side: o.side === 'double' ? THREE.DoubleSide : THREE.FrontSide,
    flatShading: !!o.flatShading,
  });
  const uniforms = {
    uDetail: { value: getDetailTexture() },
    uDetailScale: { value: o.detailScale ?? 9 },
    uBump: { value: o.bump ?? 0.6 },
    uFlash: { value: new THREE.Color(0, 0, 0) },
    uGlowScale: { value: o.glowScale ?? 1 },
  };
  mat.userData.kit = uniforms;
  mat.onBeforeCompile = (shader) => {
    Object.assign(shader.uniforms, uniforms);
    shader.vertexShader = shader.vertexShader
      .replace('#include <common>', '#include <common>\n' + VERT_PARS)
      .replace('#include <begin_vertex>', '#include <begin_vertex>\n' + VERT_MAIN);
    shader.fragmentShader = shader.fragmentShader
      .replace('#include <common>', '#include <common>\n' + FRAG_PARS)
      .replace('#include <color_fragment>', `#include <color_fragment>
  vec4 edDet = edTriplanar(vRestPos * uDetailScale, normalize(vRestNrm));
  float edAmt = vSurf.z;
  diffuseColor.rgb *= mix(1.0, 0.72 + 0.56 * edDet.r, edAmt) * vSurf.w;`)
      .replace('#include <roughnessmap_fragment>', `#include <roughnessmap_fragment>
  roughnessFactor = clamp(roughnessFactor * vSurf.x * (1.0 + (edDet.r - 0.5) * 0.5 * edAmt) + (edDet.g - 0.5) * 0.45 * edAmt, 0.045, 1.0);`)
      .replace('#include <metalnessmap_fragment>', `#include <metalnessmap_fragment>
  metalnessFactor *= vSurf.y;`)
      .replace('#include <normal_fragment_maps>', `#include <normal_fragment_maps>
  {
    float edH = edDet.b + (edDet.a - 0.5) * 0.12;
    vec2 edD = vec2(dFdx(edH), dFdy(edH)) * uBump * edAmt;
    normal = edPerturb(-vViewPosition, normal, edD, faceDirection);
  }`)
      .replace('#include <emissivemap_fragment>', `#include <emissivemap_fragment>
  {
    float edFres = pow(1.0 - saturate(dot(normal, normalize(vViewPosition))), 2.0);
    totalEmissiveRadiance += vGlow * uGlowScale + uFlash * (0.3 + 0.7 * edFres);
  }`);
  };
  mat.customProgramCacheKey = () => 'edkit-v1';
  return mat;
}
