// Moving props: hanging cloth (sect banners, pennants, hemp strips and paper talismans from the cloth atlas; motion
// entirely in the vertex shader, analytic normals, backlit translucency toward the eclipse) and the fires (lantern
// flames, smouldering censers, incense tips: camera-facing tongues + soft glows, one draw call).

import * as THREE from 'three';
import { NOISE } from './glsl.js';
import { patchStandard } from './materials.js';

// ---- cloth: banners, pennants, hemp strips, paper talismans ----------------------------------------------------------
const CLOTH_HEAD = /* glsl */ `
attribute vec4 aCloth;   // x: metres below the top edge, y: across (-0.5..0.5), z: seed, w: cloth length
attribute vec3 aAcross;  // vector across the cloth (to the viewer's right), length = cloth width
uniform vec3 uWind;
uniform float uTime;
vec3 clothOff(float hang, float u, vec3 N, vec3 X) {
  float t = uTime;
  float s = aCloth.z, Ls = aCloth.w;
  float k = hang / Ls;
  // amplitudes are authored for a 3.8 m banner; short strips swing through a wider angle and flutter faster
  float sc = clamp(Ls / 3.8, 0.06, 1.2) * (Ls < 1.0 ? 2.2 : 1.0);
  float fq = mix(2.4, 1.0, clamp(Ls / 2.0, 0.0, 1.0));
  float pin = smoothstep(0.0, 0.09, k);
  float gust = 0.55 + 0.45 * sin(t * 0.63 + s) * sin(t * 0.37 + s * 1.7);
  float billow = (0.22 + 0.42 * gust) * k * k;
  float wave = sin(k * 7.2 - t * 2.6 * fq + s + u * 1.2) * (0.06 + 0.2 * k) * gust;
  float flutter = sin(k * 21.0 - t * 6.8 * fq + u * 5.0 + s * 2.0) * 0.045 * k * k * (0.4 + gust);
  float side = sin(t * 0.8 * fq + s * 0.7) * 0.18 * k * k + sin(k * 8.7 - t * 3.3 * fq + s) * 0.06 * k;
  float curl = (u * u - 0.08) * 0.25 * k;
  return (N * (billow + wave + flutter + curl) + X * side + vec3(0.0, -0.06 * k * k * gust, 0.0)) * pin * sc;
}
`;
const CLOTH_NORMAL = /* glsl */ `
vec3 cN = normalize(normal);
float cW = length(aAcross);
vec3 cX = aAcross / cW;
float cDh = 0.021 * aCloth.w;
vec3 o0 = clothOff(aCloth.x, aCloth.y, cN, cX);
vec3 oh = clothOff(aCloth.x + cDh, aCloth.y, cN, cX);
vec3 ou = clothOff(aCloth.x, aCloth.y + 0.08, cN, cX);
vec3 dPdh = vec3(0.0, -cDh, 0.0) + (oh - o0);
vec3 dPdu = cX * 0.08 * cW + (ou - o0);
vec3 objectNormal = normalize(cross(dPdh, dPdu));
#ifdef USE_TANGENT
vec3 objectTangent = vec3( tangent.xyz );
#endif
`;

/**
 * Build all hanging cloth as one mesh (a grid per piece, rest pose in world space).
 * spec: { top: Vector3 (centre of the top edge), normal: Vector3, width, length, seed, uv: [u0, v0, u1, v1]
 *         (region of the cloth atlas, v0 at the hem), cols = 7, rows = 20 }
 */
export function createBanners(U, specs, tex) {
  const pos = [], nrm = [], uv = [], cloth = [], across = [], idx = [];
  for (const b of specs) {
    const cols = b.cols || 7, rows = b.rows || 20;
    const [u0, v0, u1, v1] = b.uv || [0, 0, 1, 1];
    const N = b.normal.clone().setY(0).normalize();
    const X = new THREE.Vector3().crossVectors(new THREE.Vector3(0, 1, 0), N).normalize();
    const base = pos.length / 3;
    for (let j = 0; j <= rows; j++) {
      const v = j / rows;
      const hang = v * b.length;
      for (let i = 0; i <= cols; i++) {
        const u = i / cols - 0.5;
        const p = b.top.clone().addScaledVector(X, u * b.width).add(new THREE.Vector3(0, -hang, 0));
        pos.push(p.x, p.y, p.z);
        nrm.push(N.x, N.y, N.z);
        uv.push(u0 + (u1 - u0) * (0.01 + 0.98 * (i / cols)), v0 + (v1 - v0) * (0.01 + 0.98 * (1 - v)));
        cloth.push(hang, u, b.seed, b.length);
        across.push(X.x * b.width, X.y * b.width, X.z * b.width);
      }
    }
    for (let j = 0; j < rows; j++) for (let i = 0; i < cols; i++) {
      const a = base + j * (cols + 1) + i, c = a + cols + 1;
      idx.push(a, c, a + 1, a + 1, c, c + 1);
    }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('normal', new THREE.Float32BufferAttribute(nrm, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  g.setAttribute('aCloth', new THREE.Float32BufferAttribute(cloth, 4));
  g.setAttribute('aAcross', new THREE.Float32BufferAttribute(across, 3));
  g.setIndex(idx);
  g.computeBoundingSphere();
  g.boundingSphere.radius += 3;

  const mat = new THREE.MeshStandardMaterial({ name: 'env.banner', color: 0xffffff, map: tex, alphaTest: 0.5, side: THREE.DoubleSide, roughness: 0.92, metalness: 0, envMapIntensity: 0.4 });
  patchStandard(mat, U, {
    key: 'banner',
    extraUniforms: { uWind: U.uWind, uRim: U.uRim },
    vertexHead: CLOTH_HEAD,
    fragHead: 'uniform vec3 uRim;',
    fragReplace: {
      emissivemap_fragment: `#include <emissivemap_fragment>
{ // light through the cloth when the eclipse is behind it
  vec3 vd = normalize(vEnvWorld - cameraPosition);
  float through = pow(max(dot(vd, uSunDir), 0.0), 3.0);
  totalEmissiveRadiance += diffuseColor.rgb * uRim * through * 1.3;
}`,
    },
  });
  // cloth deformation: replace the normal and displace the position
  const prev = mat.onBeforeCompile;
  mat.onBeforeCompile = (shader, r) => {
    prev(shader, r);
    shader.vertexShader = shader.vertexShader
      .replace('#include <beginnormal_vertex>', CLOTH_NORMAL)
      .replace('#include <begin_vertex>', '#include <begin_vertex>\ntransformed += o0;');
  };
  const mesh = new THREE.Mesh(g, mat);
  mesh.name = 'env.banners';
  mesh.frustumCulled = false;
  return mesh;
}

// ---- brazier fire ------------------------------------------------------------------------------------------------
const FIRE_VERT = /* glsl */ `
attribute vec4 aFire;  // xyz base, w seed
attribute vec4 aShape; // x width, y height, z kind (0 tongue, 1 glow), w intensity
uniform vec3 uWind;
uniform float uTime;
varying vec2 vUv;
varying vec4 vShape;
varying float vSeed;
void main() {
  vec3 base = aFire.xyz;
  vec3 toCam = cameraPosition - base;
  vec3 wp;
  if (aShape.z < 0.5) {
    toCam.y = 0.0; toCam = normalize(toCam);
    vec3 right = vec3(toCam.z, 0.0, -toCam.x);
    float y = position.y;
    wp = base + right * (position.x * aShape.x) + vec3(0.0, y * aShape.y, 0.0);
    wp.xz += uWind.xz * 0.12 * y * y * aShape.y + vec2(sin(uTime * 3.1 + aFire.w), cos(uTime * 2.7 + aFire.w)) * 0.04 * y * clamp(aShape.y * 2.0, 0.0, 1.0);
  } else {
    vec3 f = normalize(toCam);
    vec3 r = normalize(cross(vec3(0.0, 1.0, 0.0), f));
    vec3 u = cross(f, r);
    wp = base + (r * position.x + u * (position.y - 0.5)) * aShape.x;
  }
  vUv = vec2(position.x + 0.5, position.y);
  vShape = aShape;
  vSeed = aFire.w;
  gl_Position = projectionMatrix * viewMatrix * vec4(wp, 1.0);
}`;
const FIRE_FRAG = /* glsl */ `
${NOISE}
uniform float uTime;
uniform vec4 uMood;
uniform vec3 uFireTint;
varying vec2 vUv;
varying vec4 vShape;
varying float vSeed;
void main() {
  vec3 col;
  if (vShape.z < 0.5) {
    float x = (vUv.x - 0.5) * 2.0, y = vUv.y;
    float t = uTime;
    float n = fbm2(vec2(x * 1.6 + vSeed, y * 2.2 - t * 2.4), 3);
    float n2 = vnoise(vec2(x * 4.0 + vSeed * 3.0, y * 5.0 - t * 4.6));
    float xd = x + (n - 0.5) * 0.9 * y;
    float width = mix(0.8, 0.06, pow(y, 0.75)) * (0.7 + 0.6 * n);
    float shape = smoothstep(width, width * 0.25, abs(xd));
    shape *= smoothstep(0.0, 0.1, y) * (1.0 - smoothstep(0.45 + 0.4 * n2, 1.0, y));
    float dens = clamp(shape * (0.6 + 0.9 * n) * 1.4 - 0.25 * y, 0.0, 1.0);
    vec3 c1 = vec3(0.9, 0.12, 0.02), c2 = vec3(4.2, 1.45, 0.32), c3 = vec3(7.0, 4.6, 2.2);
    col = mix(c1, c2, smoothstep(0.1, 0.55, dens));
    col = mix(col, c3, smoothstep(0.7, 1.0, dens) * (1.0 - y));
    col *= dens * vShape.w;
  } else {
    vec2 c = vUv - 0.5;
    float r = length(c) * 2.0;
    col = vec3(0.32, 0.1, 0.025) * pow(max(1.0 - r, 0.0), 2.2) * vShape.w;
  }
  float d = uMood.a;
  col *= uFireTint * (1.0 - 0.6 * d);
  gl_FragColor = vec4(col, 1.0);
}`;

/**
 * The env's fires as one additive mesh. `flames`: [{ pos: Vector3, kind }] with kind
 *   'lantern'  a flame in a stone lantern's chamber: a tongue + a glow that spills out of the windows
 *   'censer'   smouldering incense in a bronze brazier: a low glow, a small tongue now and then
 *   'stick'    the ember at an incense stick's tip
 */
export function createFire(U, flames, rng) {
  const quad = new THREE.PlaneGeometry(1, 1);
  quad.translate(0, 0.5, 0);
  const g = new THREE.InstancedBufferGeometry();
  g.index = quad.index;
  g.setAttribute('position', quad.attributes.position);
  const fire = [], shape = [];
  for (const f of flames) {
    const p = f.pos;
    if (f.kind === 'lantern') {
      fire.push(p.x, p.y + 0.12, p.z, rng.range(0, 50)); shape.push(1.25, 0, 1, 1.0);
      fire.push(p.x, p.y - 0.13, p.z, rng.range(0, 50)); shape.push(0.2, 0.3, 0, 0.95);
      fire.push(p.x + 0.03, p.y - 0.13, p.z + 0.02, rng.range(0, 50)); shape.push(0.13, 0.2, 0, 0.7);
    } else if (f.kind === 'censer') {
      fire.push(p.x, p.y + 0.25, p.z, rng.range(0, 50)); shape.push(1.9, 0, 1, 0.5);
      fire.push(p.x, p.y - 0.05, p.z, rng.range(0, 50)); shape.push(0.5, 0.3, 0, 0.34);
      fire.push(p.x + 0.14, p.y - 0.05, p.z - 0.08, rng.range(0, 50)); shape.push(0.3, 0.2, 0, 0.28);
    } else {
      fire.push(p.x, p.y + 0.03, p.z, rng.range(0, 50)); shape.push(0.11, 0, 1, 9.0);
    }
  }
  g.setAttribute('aFire', new THREE.InstancedBufferAttribute(new Float32Array(fire), 4));
  g.setAttribute('aShape', new THREE.InstancedBufferAttribute(new Float32Array(shape), 4));
  g.instanceCount = fire.length / 4;
  const mat = new THREE.ShaderMaterial({
    name: 'env.fire',
    vertexShader: FIRE_VERT,
    fragmentShader: FIRE_FRAG,
    uniforms: { uTime: U.uTime, uWind: U.uWind, uMood: U.uMood, uFireTint: { value: new THREE.Color(1, 1, 1) } },
    transparent: true,
    depthWrite: false,
    blending: THREE.AdditiveBlending,
    side: THREE.DoubleSide,
  });
  const mesh = new THREE.Mesh(g, mat);
  mesh.frustumCulled = false;
  mesh.name = 'env.fire';
  mesh.renderOrder = 30;
  return mesh;
}
