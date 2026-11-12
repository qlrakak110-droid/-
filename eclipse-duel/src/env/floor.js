// Arena floor: baked flagstone maps (world-space), wet stone + puddles, worn contact band under the fight line,
// floor pulses (glow ring + ripples), brazier light pools, and on the high tier a cheap "planar" puddle reflection
// (createReflectionOverlay): right after the HDR scene render (post.onAfterScene) the frame is copied and the
// puddles in front of the fight line are re-shaded in a second, depth-tested pass that re-projects this same frame
// through the mirror, assuming reflected content stands on the fight line plane (z = 0). No frame of lag, correct on
// cuts. Elsewhere puddles reflect the PMREM sky (which contains the ring silhouettes).

import * as THREE from 'three';
import { patchStandard } from './materials.js';
import { SKY_BASE, FOG } from './glsl.js';
import { LAYOUT } from './config.js';

const MAX_PULSES = 4;
/** Share of a puddle's reflection scattered by ripples, and the roughness of that scattered part. */
const SCATTER = 0.4, SCATTER_ROUGH = 0.45;

const FRAG_HEAD = /* glsl */ `
uniform sampler2D tFloorA, tFloorB, tDetailA, tDetailB;
uniform float uFloorE;
uniform vec4 uWet;        // x extra wetness on top of the baked damp (0 = as baked), y puddle scale, z ripple amount, w unused
uniform vec4 uBand;       // x sigma (m), y darkening, z, w unused (the key pool is envFloorKey in materials.js)
uniform vec4 uPulseP[${MAX_PULSES}];   // x, z, age (s), strength
uniform vec4 uPulseC[${MAX_PULSES}];   // rgb colour, ring speed (m/s)
uniform vec4 uBraz[4];    // brazier x, z, pool strength, -
uniform vec4 uContactP[4];  // body on the floor: x, z, foot radius (m), height (m)
uniform vec4 uContactW;     // per-slot strength (0 = off)
uniform vec4 uContactK;     // xy: blob-shadow direction on the floor (away from the key), z: blob strength, w: AO strength
float envPuddle, envRough, envRoughStone, envMetal, envOcc, envBlob;
vec3 envEmissive;
vec3 envNW;
`;

const MAP = /* glsl */ `
vec2 fuv = vEnvWorld.xz / (2.0 * uFloorE) + 0.5;
vec4 fA = texture2D(tFloorA, fuv);
vec4 fB = texture2D(tFloorB, fuv);
vec4 dB = texture2D(tDetailB, vEnvWorld.xz / 1.3);
vec3 dA = texture2D(tDetailA, vEnvWorld.xz / 1.3).rgb;
envPuddle = fA.a * uWet.y;
float band = exp(-vEnvWorld.z * vEnvWorld.z / (2.0 * uBand.x * uBand.x)) * (1.0 - smoothstep(9.5, 13.0, abs(vEnvWorld.x)));
vec3 alb = fA.rgb * clamp(1.0 + (dA - vec3(0.6)) * 2.4, 0.5, 1.5);
alb *= mix(1.0, 1.0 - uBand.y, band);
alb *= mix(1.0, 0.7, uWet.x);
alb = mix(alb, alb * 0.72, envPuddle);
diffuseColor.rgb *= alb;
envRough = mix(fB.b, fB.b * 0.8, uWet.x) * mix(1.0, 0.88, band);
envRough = clamp(envRough + (dB.a - 0.5) * 0.25, 0.05, 1.0);
envRoughStone = envRough;
envRough = mix(envRough, 0.045, envPuddle);
envMetal = fB.a * (1.0 - envPuddle);

// normal (world): baked macro + tiling detail, flattened by water, rippled by wind and pulses
vec2 nxz = fB.rg * 2.0 - 1.0;
nxz += (dB.rg * 2.0 - 1.0) * 0.7 * (1.0 - envPuddle);
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
  float wetBoost = 0.45 + 0.55 * max(1.0 - envRough, envPuddle);
  envEmissive += uPulseC[i].rgb * P.w * (ring * 0.4 + core * 1.5) * wetBoost;
  nxz += (d / dist) * sin((dist - R) * 13.0) * ring * P.w * 0.22 * (0.3 + 0.7 * envPuddle);
}
// ground contact: soft occlusion under each body, and (tiers without a shadow map) a blob shadow away from the key
envOcc = 0.0; envBlob = 0.0;
for (int i = 0; i < 4; i++) {
  float cw = uContactW[i];
  if (cw <= 0.0) continue;
  vec4 C = uContactP[i];
  vec2 d = wp - C.xy;
  envOcc = max(envOcc, cw * exp(-dot(d, d) / (C.z * C.z * 2.4)));
  float L = C.w * 0.8;
  float tb = clamp(dot(d, uContactK.xy) / L, 0.0, 1.0);
  float rb = C.z * (1.0 + 1.5 * tb);
  float sd = length(d - uContactK.xy * tb * L);
  envBlob = max(envBlob, cw * (1.0 - smoothstep(rb * 0.3, rb * 1.3, sd)) * (1.0 - 0.7 * tb));
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

// The stone under a puddle's thin water film still scatters the key broadly (shadowed like everything else): without
// it a puddle mirroring the black zenith loses the sheen of the stones around it and reads as a hole in the floor.
// The mirror reflection itself stays sharp (IBL, and the screen reflection on high).
const UNDER_FILM = /* glsl */ `
if ( UNROLLED_LOOP_INDEX == 0 && envPuddle > 0.01 ) {
  PhysicalMaterial envStone = material;
  envStone.roughness = max( envRoughStone, 0.0525 );
  reflectedLight.directSpecular += envPuddle * 0.75 * saturate( dot( geometryNormal, directLight.direction ) ) * directLight.color * BRDF_GGX( directLight.direction, geometryViewDir, geometryNormal, envStone );
}
`;

const REFLECT = /* glsl */ `
#include <lights_fragment_maps>
radiance *= uWet.w;
#if defined( USE_ENVMAP ) && defined( RE_IndirectSpecular )
// wind ripples scatter part of a puddle's mirror image: it keeps a soft sheen of the sky glow and the braziers instead
// of reading as a hole where it mirrors the dark walls (the reflection overlay keeps this share)
radiance = mix(radiance, getIBLRadiance(geometryViewDir, geometryNormal, ${SCATTER_ROUGH.toFixed(3)}), envPuddle * ${SCATTER.toFixed(3)});
#endif
irradiance *= 1.0 - envOcc * uContactK.w;
iblIrradiance *= 1.0 - envOcc * uContactK.w;
radiance *= 1.0 - envOcc * uContactK.w * 0.8;
`;

/**
 * Build the floor mesh.
 * @returns {{ mesh, uniforms, pulse(pos, color, strength, speed), update(dtGame), setBrazierPool(strengths) }}
 */
export function createFloor(U, maps, stoneMaps, tier, brazierPos) {
  const pulseP = [], pulseC = [];
  for (let i = 0; i < MAX_PULSES; i++) { pulseP.push(new THREE.Vector4(0, 0, 0, 0)); pulseC.push(new THREE.Vector4(1, 1, 1, 9)); }
  const braz = brazierPos.map((b) => new THREE.Vector4(b.x, b.z, 0, 0));
  while (braz.length < 4) braz.push(new THREE.Vector4(0, 0, 0, 0));
  const extra = {
    tFloorA: { value: maps.a.texture },
    tFloorB: { value: maps.b.texture },
    tDetailA: { value: stoneMaps.a.texture },
    tDetailB: { value: stoneMaps.b.texture },
    uFloorE: { value: LAYOUT.floorTexExtent },
    uWet: { value: new THREE.Vector4(0.0, 1.0, 1.0, 1) },
    uBand: { value: new THREE.Vector4(LAYOUT.fightBand, 0.2, 0.14, 1) },
    uPulseP: { value: pulseP },
    uPulseC: { value: pulseC },
    uBraz: { value: braz },
    uContactP: { value: [0, 1, 2, 3].map(() => new THREE.Vector4(0, 0, 0.35, 1.9)) },
    uContactW: { value: new THREE.Vector4(0, 0, 0, 0) },
    uContactK: { value: new THREE.Vector4(1, 0, tier.blobShadow, 0.8) },
  };
  const mat = new THREE.MeshStandardMaterial({ name: 'env.floor', color: 0xffffff, roughness: 1, metalness: 0, envMapIntensity: 0.85 });
  patchStandard(mat, U, {
    key: 'floor',
    extraUniforms: extra,
    fragHead: FRAG_HEAD,
    keyMask: false,
    // key light: full on the fight band, dimmer toward the far floor and the wall
    keyMaskExtra: 'envRimMask = uBand.z; envKeyMask = envFloorKey(vEnvWorld) * uBand.w * (1.0 - envBlob * uContactK.z) * (1.0 - envOcc * 0.35);',
    dirLight: UNDER_FILM,
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
    mesh, uniforms: extra,
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
    /** Ground contact slot i: floor point (x, z), height above the floor y, foot radius, body height (metres). */
    setContact(i, x, y, z, radius, height) {
      const air = Math.max(0, y);
      extra.uContactP.value[i].set(x, z, radius * (1 + air * 0.6), height);
      extra.uContactW.value.setComponent(i, Math.exp(-air * 1.4));
    },
    clearContact(i) { extra.uContactW.value.setComponent(i, 0); },
  };
}

const OVERLAY_VERT = /* glsl */ `
varying vec3 vW;
void main() {
  vec4 mvPosition = modelViewMatrix * vec4(position, 1.0);
  gl_Position = projectionMatrix * mvPosition;
  vW = (modelMatrix * vec4(position, 1.0)).xyz;
}`;
const OVERLAY_FRAG = /* glsl */ `
#include <common>
#include <cube_uv_reflection_fragment>
uniform sampler2D tFloorA, tFloorB, tDetailB, tRefl, envMap;
uniform float uFloorE, uTime, uEnvI;
uniform vec4 uWet, uBand;
uniform mat4 uVP;
varying vec3 vW;
${SKY_BASE}
${FOG}
vec2 dfgApprox(float dotNV, float roughness) {
  const vec4 c0 = vec4(-1.0, -0.0275, -0.572, 0.022);
  const vec4 c1 = vec4(1.0, 0.0425, 1.04, -0.04);
  vec4 r = roughness * c0 + c1;
  float a004 = min(r.x * r.x, exp2(-9.28 * dotNV)) * r.x + r.y;
  return vec2(-1.04, 1.04) * a004 + r.zw;
}
void main() {
  vec3 F = vW;
  if (F.z < 0.08) discard;
  vec2 fuv = F.xz / (2.0 * uFloorE) + 0.5;
  vec4 fA = texture2D(tFloorA, fuv);
  vec4 fB = texture2D(tFloorB, fuv);
  vec4 dB = texture2D(tDetailB, F.xz / 1.3);
  // the same surface the floor pass shaded (MAP in floor.js)
  float puddle = fA.a * uWet.y;
  float band = exp(-F.z * F.z / (2.0 * uBand.x * uBand.x)) * (1.0 - smoothstep(9.5, 13.0, abs(F.x)));
  float rough = mix(fB.b, fB.b * 0.8, uWet.x) * mix(1.0, 0.88, band);
  rough = clamp(rough + (dB.a - 0.5) * 0.25, 0.05, 1.0);
  rough = mix(rough, 0.045, puddle);
  float wetness = max(puddle, clamp(1.0 - rough * 1.7, 0.0, 1.0) + uWet.x * 0.55);
  if (wetness < 0.01) discard;
  vec2 nxz = fB.rg * 2.0 - 1.0;
  nxz += (dB.rg * 2.0 - 1.0) * 0.7 * (1.0 - puddle);
  nxz *= 1.0 - puddle * 0.94;
  vec2 wp = F.xz;
  vec2 rip = vec2(sin(wp.x * 7.0 + wp.y * 3.0 + uTime * 1.7) + sin(wp.x * 3.1 - wp.y * 8.3 - uTime * 1.3), sin(wp.y * 6.3 - wp.x * 2.0 + uTime * 1.9) + sin(wp.y * 2.9 + wp.x * 7.7 - uTime * 1.1));
  nxz += rip * 0.006 * uWet.z * puddle;
  vec3 N = normalize(vec3(nxz.x, sqrt(max(1.0 - dot(nxz, nxz), 0.05)), nxz.y));
  // mirror ray from the camera reflected in the floor plane, intersected with the fight line plane z = 0
  vec3 Cm = vec3(cameraPosition.x, -cameraPosition.y, cameraPosition.z);
  vec3 rd = normalize(F - Cm);
  rd.xz += N.xz * 0.9;
  float tq = -F.z / min(rd.z, -1e-3);
  vec3 Q = F + rd * tq;
  vec4 clip = uVP * vec4(Q, 1.0);
  vec2 suv = clip.xy / max(clip.w, 1e-3) * 0.5 + 0.5;
  float edge = smoothstep(0.0, 0.06, suv.x) * smoothstep(1.0, 0.94, suv.x) * smoothstep(0.0, 0.05, suv.y) * smoothstep(1.0, 0.92, suv.y);
  float w = step(0.0, clip.w) * smoothstep(0.08, 0.45, F.z) * (1.0 - smoothstep(2.4, 3.6, Q.y)) * edge;
  // where the camera ray through Q lands on the floor behind, the copied pixel is (most likely) floor, not a fighter
  if (Q.y < cameraPosition.y - 0.02) {
    vec3 hit = cameraPosition + (Q - cameraPosition) * (cameraPosition.y / (cameraPosition.y - Q.y));
    w *= mix(0.1, 1.0, smoothstep(13.5, 17.0, length(hit.xz)));
  }
  w *= wetness;
  if (w < 0.003) discard;
  vec3 rc = textureLod(tRefl, suv, clamp(rough * 9.0, 0.0, 5.0)).rgb;
  // replace (not add to) the mirror part of the sky reflection the floor pass used: same PMREM lookup, same specular
  // weight; the share the ripples scatter (floor.js REFLECT) stays as the floor pass shaded it
  w *= 1.0 - puddle * ${SCATTER.toFixed(3)};
  vec3 V = normalize(cameraPosition - F);
  vec3 R = normalize(mix(reflect(-V, N), N, rough * rough));
  vec3 env = textureCubeUV(envMap, R, rough).rgb * uEnvI;
  vec2 fab = dfgApprox(clamp(dot(N, V), 0.0, 1.0), rough);
  float spec = 0.04 * fab.x + fab.y;
  vec3 dir;
  float fog = fogAmount(F, dir);
  vec3 delta = (rc - env) * spec * w * (1.0 - fog) * (1.0 - 0.86 * uMood.a);
  gl_FragColor = vec4(delta, 0.0);
}`;

/**
 * High tier: the puddle reflection pass. A second draw of the floor disc, depth-tested against the frame just
 * rendered (fighters in front occlude it), adding (reflected frame - sky reflection) x specular weight on wet floor
 * in front of the fight line. Signed output, additive blend into the HDR target (half float keeps negatives).
 * @param {object} floor     createFloor() result
 * @param {THREE.Texture} envMap  the PMREM the floor reflects (scene.environment)
 * @param {THREE.Texture} reflTex the copied HDR frame (mipmapped)
 * @returns {{ mesh: THREE.Mesh, uniforms: object }}
 */
export function createReflectionOverlay(U, floor, envMap, reflTex) {
  const e = floor.uniforms;
  const h = envMap.image.height;
  const maxMip = Math.log2(h) - 2;
  const uniforms = {
    tFloorA: e.tFloorA, tFloorB: e.tFloorB, tDetailB: e.tDetailB, uFloorE: e.uFloorE, uWet: e.uWet, uBand: e.uBand,
    tRefl: { value: reflTex }, envMap: { value: envMap }, uEnvI: { value: 1 }, uVP: { value: new THREE.Matrix4() },
    uTime: U.uTime, uFogP: U.uFogP, uFogNear: U.uFogNear, uMood: U.uMood,
    uZenith: U.uZenith, uSkyMid: U.uSkyMid, uHorizon: U.uHorizon, uGlow: U.uGlow, uSunHalo: U.uSunHalo, uSunDir: U.uSunDir,
  };
  const mat = new THREE.ShaderMaterial({
    name: 'env.floorReflection',
    vertexShader: OVERLAY_VERT,
    fragmentShader: OVERLAY_FRAG,
    uniforms,
    defines: { ENVMAP_TYPE_CUBE_UV: '', CUBEUV_TEXEL_WIDTH: 1 / (3 * Math.max(Math.pow(2, maxMip), 7 * 16)), CUBEUV_TEXEL_HEIGHT: 1 / h, CUBEUV_MAX_MIP: maxMip.toFixed(1) },
    depthTest: true,
    depthWrite: false,
    depthFunc: THREE.LessEqualDepth,
    polygonOffset: true,
    polygonOffsetFactor: -1,
    polygonOffsetUnits: -2,
    transparent: true,
    blending: THREE.CustomBlending,
    blendEquation: THREE.AddEquation,
    blendSrc: THREE.OneFactor,
    blendDst: THREE.OneFactor,
    blendSrcAlpha: THREE.ZeroFactor,
    blendDstAlpha: THREE.OneFactor,
  });
  const mesh = new THREE.Mesh(floor.mesh.geometry, mat);
  mesh.name = 'env.floorReflection';
  mesh.frustumCulled = false;
  return { mesh, uniforms };
}
