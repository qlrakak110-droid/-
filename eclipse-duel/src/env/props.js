// Moving props: tattered banners (cloth motion entirely in the vertex shader, analytic normals, backlit
// translucency toward the eclipse) and brazier fire (camera-facing flame tongues + a soft heat glow, one draw call).

import * as THREE from 'three';
import { NOISE } from './glsl.js';
import { patchStandard } from './materials.js';

// ---- banners -----------------------------------------------------------------------------------------------------
const CLOTH_HEAD = /* glsl */ `
attribute vec4 aCloth;   // x: metres below the bar, y: across (-0.5..0.5), z: seed, w: banner length
attribute vec3 aAcross;  // unit vector across the banner (to the viewer's right)
uniform vec3 uWind;
uniform float uTime;
vec3 clothOff(float hang, float u, vec3 N, vec3 X) {
  float t = uTime;
  float s = aCloth.z;
  float k = hang / aCloth.w;
  float pin = smoothstep(0.0, 0.35, hang);
  float gust = 0.55 + 0.45 * sin(t * 0.63 + s) * sin(t * 0.37 + s * 1.7);
  float billow = (0.22 + 0.42 * gust) * k * k;
  float wave = sin(hang * 1.9 - t * 2.6 + s + u * 1.2) * (0.06 + 0.2 * k) * gust;
  float flutter = sin(hang * 5.5 - t * 6.8 + u * 5.0 + s * 2.0) * 0.045 * k * k * (0.4 + gust);
  float side = sin(t * 0.8 + s * 0.7) * 0.18 * k * k + sin(hang * 2.3 - t * 3.3 + s) * 0.06 * k;
  float curl = (u * u - 0.08) * 0.25 * k;
  return (N * (billow + wave + flutter + curl) + X * side + vec3(0.0, -0.06 * k * k * gust, 0.0)) * pin;
}
`;
const CLOTH_NORMAL = /* glsl */ `
vec3 cN = normalize(normal);
vec3 cX = normalize(aAcross);
vec3 o0 = clothOff(aCloth.x, aCloth.y, cN, cX);
vec3 oh = clothOff(aCloth.x + 0.08, aCloth.y, cN, cX);
vec3 ou = clothOff(aCloth.x, aCloth.y + 0.08, cN, cX);
vec3 dPdh = vec3(0.0, -0.08, 0.0) + (oh - o0);
vec3 dPdu = cX * 0.08 + (ou - o0);
vec3 objectNormal = normalize(cross(dPdh, dPdu));
#ifdef USE_TANGENT
vec3 objectTangent = vec3( tangent.xyz );
#endif
`;

/** Build all banners as one mesh (grid per banner, rest pose in world space). */
export function createBanners(U, specs, tex) {
  const cols = 7, rows = 20;
  const pos = [], nrm = [], uv = [], cloth = [], across = [], idx = [];
  for (const b of specs) {
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
        uv.push(i / cols, 1 - v);
        cloth.push(hang, u, b.seed, b.length);
        across.push(X.x, X.y, X.z);
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
 * Flames for the brazier bowls (positions = bowl rims) plus small tongues for votive candles
 * (`candles`: [{ pos, w, h, i }] from the ruins dressing).
 */
export function createFire(U, tops, rng, candles = []) {
  const quad = new THREE.PlaneGeometry(1, 1);
  quad.translate(0, 0.5, 0);
  const g = new THREE.InstancedBufferGeometry();
  g.index = quad.index;
  g.setAttribute('position', quad.attributes.position);
  const fire = [], shape = [];
  for (const p of tops) {
    fire.push(p.x, p.y + 0.35, p.z, rng.range(0, 50)); shape.push(2.2, 0, 1, 0.7);
    fire.push(p.x, p.y - 0.06, p.z, rng.range(0, 50)); shape.push(0.8, 1.0, 0, 0.75);
    fire.push(p.x + 0.12, p.y - 0.04, p.z + 0.05, rng.range(0, 50)); shape.push(0.6, 0.75, 0, 0.6);
    fire.push(p.x - 0.14, p.y - 0.05, p.z - 0.04, rng.range(0, 50)); shape.push(0.5, 0.6, 0, 0.55);
  }
  for (const c of candles) { fire.push(c.pos.x, c.pos.y, c.pos.z, rng.range(0, 50)); shape.push(c.w, c.h, 0, c.i); }
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
