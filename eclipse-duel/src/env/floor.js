// Arena floor: baked flagstone maps (world-space), wet stone + puddles, worn contact band under the fight line,
// floor pulses (glow ring + ripples), brazier light pools, and on the high tier a cheap "planar" puddle reflection:
// the previous frame's HDR scene is re-projected through the mirror assuming reflected content stands on the fight
// line plane (z = 0). Elsewhere puddles reflect the PMREM sky (which contains the ring silhouettes).

import * as THREE from 'three';
import { patchStandard } from './materials.js';
import { LAYOUT } from './config.js';

const MAX_PULSES = 4;

const FRAG_HEAD = /* glsl */ `
uniform sampler2D tFloorA, tFloorB, tDetailB, tRefl;
uniform float uFloorE;
uniform vec4 uWet;        // x dampness, y puddle scale, z ripple amount, w reflection on
uniform vec4 uBand;       // x sigma (m), y darkening, z key outside band, w key at the far floor
uniform vec4 uPulseP[${MAX_PULSES}];   // x, z, age (s), strength
uniform vec4 uPulseC[${MAX_PULSES}];   // rgb colour, ring speed (m/s)
uniform vec4 uBraz[4];    // brazier x, z, pool strength, -
uniform mat4 uReflVP;
float envPuddle, envRough, envMetal;
vec3 envEmissive;
vec3 envNW;
`;

const MAP = /* glsl */ `
vec2 fuv = vEnvWorld.xz / (2.0 * uFloorE) + 0.5;
vec4 fA = texture2D(tFloorA, fuv);
vec4 fB = texture2D(tFloorB, fuv);
vec4 dB = texture2D(tDetailB, vEnvWorld.xz / 1.3);
envPuddle = fA.a * uWet.y;
float band = exp(-vEnvWorld.z * vEnvWorld.z / (2.0 * uBand.x * uBand.x)) * (1.0 - smoothstep(9.5, 13.0, abs(vEnvWorld.x)));
vec3 alb = fA.rgb;
alb *= mix(1.0, 1.0 - uBand.y, band);
alb *= mix(1.0, 0.7, uWet.x);
alb = mix(alb, alb * 0.42, envPuddle);
diffuseColor.rgb *= alb;
envRough = mix(fB.b, fB.b * 0.62, uWet.x) * mix(1.0, 0.85, band);
envRough = mix(envRough, 0.045, envPuddle);
envMetal = fB.a * (1.0 - envPuddle);

// normal (world): baked macro + tiling detail, flattened by water, rippled by wind and pulses
vec2 nxz = fB.rg * 2.0 - 1.0;
nxz += (dB.rg * 2.0 - 1.0) * 0.22 * (1.0 - envPuddle);
nxz *= 1.0 - envPuddle * 0.94;
vec2 wp = vEnvWorld.xz;
float t = uTime;
vec2 rip = vec2(sin(wp.x * 7.0 + wp.y * 3.0 + t * 1.7) + sin(wp.x * 3.1 - wp.y * 8.3 - t * 1.3), sin(wp.y * 6.3 - wp.x * 2.0 + t * 1.9) + sin(wp.y * 2.9 + wp.x * 7.7 - t * 1.1));
nxz += rip * 0.006 * uWet.z * envPuddle;
envEmissive = vec3(0.0);
for (int i = 0; i < ${MAX_PULSES}; i++) {
  vec4 P = uPulseP[i];
  if (P.w <= 0.0) continue;
  vec2 d = wp - P.xy;
  float dist = length(d) + 1e-4;
  float age = P.z;
  float R = age * uPulseC[i].w;
  float width = 0.22 + age * 0.55;
  float ring = exp(-pow((dist - R) / width, 2.0)) * exp(-age * 1.6);
  float core = exp(-dist * dist / (0.5 + age * 3.0)) * exp(-age * 3.5);
  float wetBoost = 0.45 + 0.55 * max(uWet.x, envPuddle);
  envEmissive += uPulseC[i].rgb * P.w * (ring * 0.35 + core * 0.9) * wetBoost;
  nxz += (d / dist) * sin((dist - R) * 13.0) * ring * P.w * 0.22 * (0.3 + 0.7 * envPuddle);
}
// brazier light pools (bounce + baked warmth; the real point lights add the speculars)
for (int i = 0; i < 4; i++) {
  vec2 d = wp - uBraz[i].xy;
  envEmissive += uFire.rgb * alb * uBraz[i].z * exp(-dot(d, d) / 7.0);
}
float ny = sqrt(max(1.0 - dot(nxz, nxz), 0.05));
envNW = normalize(vec3(nxz.x, ny, nxz.y));
`;

const NORMAL = /* glsl */ `
normal = normalize((viewMatrix * vec4(envNW, 0.0)).xyz);
`;

const REFLECT = /* glsl */ `
#include <lights_fragment_maps>
#ifdef ENV_SSR
if (uWet.w > 0.5) {
  vec3 F = vEnvWorld;
  vec3 Cm = vec3(cameraPosition.x, -cameraPosition.y, cameraPosition.z);
  vec3 rd = normalize(F - Cm);
  rd.xz += envNW.xz * 0.9;
  float tq = -F.z / min(rd.z, -1e-3);
  vec3 Q = F + rd * tq;
  vec4 clip = uReflVP * vec4(Q, 1.0);
  vec2 suv = clip.xy / max(clip.w, 1e-3) * 0.5 + 0.5;
  float edge = smoothstep(0.0, 0.06, suv.x) * smoothstep(1.0, 0.94, suv.x) * smoothstep(0.0, 0.05, suv.y) * smoothstep(1.0, 0.92, suv.y);
  float w = step(0.0, clip.w) * smoothstep(0.08, 0.45, F.z) * (1.0 - smoothstep(2.4, 3.6, Q.y)) * edge;
  float lod = clamp(envRough * 9.0, 0.0, 5.0);
  vec3 rc = textureLod(tRefl, suv, lod).rgb;
  float wetness = max(envPuddle, uWet.x * 0.55);
  radiance = mix(radiance, rc, w * wetness);
}
#endif
`;

/**
 * Build the floor mesh.
 * @returns {{ mesh, material, pulse(pos,color,strength), update(dtGame), setReflection(texture, viewProj) }}
 */
export function createFloor(U, maps, stoneMaps, tier, brazierPos) {
  const pulseP = [], pulseC = [];
  for (let i = 0; i < MAX_PULSES; i++) { pulseP.push(new THREE.Vector4(0, 0, 0, 0)); pulseC.push(new THREE.Vector4(1, 1, 1, 9)); }
  const braz = brazierPos.map((b) => new THREE.Vector4(b.x, b.z, 0, 0));
  while (braz.length < 4) braz.push(new THREE.Vector4(0, 0, 0, 0));
  const extra = {
    tFloorA: { value: maps.a.texture },
    tFloorB: { value: maps.b.texture },
    tDetailB: { value: stoneMaps.b.texture },
    tRefl: { value: null },
    uFloorE: { value: LAYOUT.floorTexExtent },
    uWet: { value: new THREE.Vector4(0.6, 1.0, 1.0, 0) },
    uBand: { value: new THREE.Vector4(LAYOUT.fightBand, 0.2, 1.0, 0.45) },
    uPulseP: { value: pulseP },
    uPulseC: { value: pulseC },
    uBraz: { value: braz },
    uReflVP: { value: new THREE.Matrix4() },
  };
  const mat = new THREE.MeshStandardMaterial({ name: 'env.floor', color: 0xffffff, roughness: 1, metalness: 0, envMapIntensity: 1.0 });
  if (tier.reflection) mat.defines = { ENV_SSR: '' };
  patchStandard(mat, U, {
    key: tier.reflection ? 'floor-ssr' : 'floor',
    extraUniforms: extra,
    fragHead: FRAG_HEAD,
    keyMask: false,
    // key light: full on the fight band, dimmer toward the far floor and the wall
    keyMaskExtra: 'envKeyMask = mix(uBand.w, 1.0, max(exp(-vEnvWorld.z * vEnvWorld.z / 18.0), 1.0 - smoothstep(4.0, 15.0, length(vEnvWorld.xz)))) * mix(uBand.z, 1.0, band);',
    fragReplace: {
      map_fragment: MAP,
      roughnessmap_fragment: 'float roughnessFactor = envRough;',
      metalnessmap_fragment: 'float metalnessFactor = envMetal;',
      normal_fragment_maps: NORMAL,
      emissivemap_fragment: '#include <emissivemap_fragment>\ntotalEmissiveRadiance += envEmissive;',
      lights_fragment_maps: REFLECT,
    },
  });
  const geo = new THREE.CircleGeometry(LAYOUT.floorR + 0.15, 128, 0, Math.PI * 2);
  geo.rotateX(-Math.PI / 2);
  const mesh = new THREE.Mesh(geo, mat);
  mesh.name = 'env.floor';
  mesh.receiveShadow = true;
  mesh.renderOrder = -10;

  let next = 0;
  const pulses = pulseP.map(() => ({ age: 99, strength: 0 }));
  return {
    mesh, material: mat, uniforms: extra,
    /** Start a floor pulse (oldest slot is recycled). */
    pulse(pos, color, strength, speed) {
      const i = next; next = (next + 1) % MAX_PULSES;
      pulses[i].age = 0; pulses[i].strength = strength;
      pulseP[i].set(pos.x, pos.z, 0, strength);
      pulseC[i].set(color.r, color.g, color.b, speed);
    },
    update(dt) {
      for (let i = 0; i < MAX_PULSES; i++) {
        const p = pulses[i];
        p.age += dt;
        pulseP[i].z = p.age;
        pulseP[i].w = p.age < 3.5 ? p.strength : 0;
      }
    },
    setBrazierPool(strengths) { for (let i = 0; i < braz.length; i++) braz[i].z = strengths[i] || 0; },
  };
}
