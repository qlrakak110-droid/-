// Material patches shared by the lit environment surfaces (MeshStandardMaterial + onBeforeCompile):
//  - world position varying, sky-matched height fog (replaces three's fog), mood darkening
//  - key-light mask: the key (directional light #0 = env.sun) falls off away from the arena so the backdrop is
//    carried by silhouettes, rims and brazier pools instead of flat front light
//  - baked brazier warmth (per-vertex `glow`) as flickering emissive (stronger on tiers without point lights)

import * as THREE from 'three';
import { SKY_BASE, FOG } from './glsl.js';
import { NOISE } from './glsl.js';
import { ORN_VERT_HEAD, ORN_VERT_MAIN, ORN_FRAG_HEAD, ORN_NORMAL, ornMap } from './ornament.js';
import { PALETTE } from './config.js';

/** lights_fragment_begin with a per-fragment multiplier on directional light 0 (the key). */
export const LIGHTS_BEGIN_KEYMASK = THREE.ShaderChunk.lights_fragment_begin.replace(
  'getDirectionalLightInfo( directionalLight, directLight );',
  'getDirectionalLightInfo( directionalLight, directLight );\n\t\tif ( UNROLLED_LOOP_INDEX == 0 ) directLight.color *= envKeyMask;\n\t\tif ( UNROLLED_LOOP_INDEX == 1 ) directLight.color *= envRimMask;',
);
if (LIGHTS_BEGIN_KEYMASK === THREE.ShaderChunk.lights_fragment_begin) throw new Error('env: lights chunk patch failed');

const RE_DIRECT = 'RE_Direct( directLight, geometryPosition, geometryNormal, geometryViewDir, geometryClearcoatNormal, material, reflectedLight );';
/** The light chunk with `code` run after each directional light's RE_Direct (directLight holds that light, shadowed). */
function lightsBegin(code) {
  if (!code) return LIGHTS_BEGIN_KEYMASK;
  const at = LIGHTS_BEGIN_KEYMASK.indexOf(RE_DIRECT, LIGHTS_BEGIN_KEYMASK.indexOf('getDirectionalLightInfo('));
  if (at < 0) throw new Error('env: directional light loop not found');
  return LIGHTS_BEGIN_KEYMASK.slice(0, at + RE_DIRECT.length) + '\n' + code + LIGHTS_BEGIN_KEYMASK.slice(at + RE_DIRECT.length);
}

const WORLD_VARYING_VERT = /* glsl */ `
  vec4 envWp = vec4(transformed, 1.0);
  #ifdef USE_INSTANCING
  envWp = instanceMatrix * envWp;
  #endif
  vEnvWorld = (modelMatrix * envWp).xyz;
`;

/**
 * Default key mask: the key falls off with distance from the arena centre, except that anything resting on the arena
 * floor (rubble, fallen drums, impact slabs, candles, weapons) takes the floor's own key pool, so it is never lit
 * brighter than the stones it lies on.
 */
const KEY_MASK = /* glsl */ `
envKeyMask = mix(uKeyMask.w, 1.0, 1.0 - smoothstep(uKeyMask.y, uKeyMask.z, length(vEnvWorld.xz)));
envKeyMask = mix(envKeyMask, envFloorKey(vEnvWorld), (1.0 - smoothstep(1.5, 3.5, vEnvWorld.y)) * (1.0 - smoothstep(14.6, 15.3, length(vEnvWorld.xz))));
`;

/** Uniform names every patched material receives from the shared env uniform object. */
const SHARED = ['uZenith', 'uSkyMid', 'uHorizon', 'uGlow', 'uSunHalo', 'uSunDir', 'uFogP', 'uFogNear', 'uMood', 'uFire', 'uKeyMask', 'uFocusZ', 'uTime'];

/**
 * Patch a MeshStandardMaterial for the environment.
 * @param {THREE.MeshStandardMaterial} mat
 * @param {object} U         shared uniforms
 * @param {object} o         { key: string (program cache key), glow: bool, keyMask: bool, keyMaskExtra, dirLight (GLSL run after
 *                           each directional light is applied), extraUniforms, vertexHead, vertexMain, fragHead, fragReplace: {chunk: code} }
 */
export function patchStandard(mat, U, o = {}) {
  mat.fog = false;
  mat.customProgramCacheKey = () => 'env-' + (o.key || 'std');
  mat.onBeforeCompile = (shader) => {
    for (const k of SHARED) shader.uniforms[k] = U[k];
    Object.assign(shader.uniforms, o.extraUniforms || {});
    let vs = shader.vertexShader;
    vs = vs.replace('#include <common>', `#include <common>
varying vec3 vEnvWorld;
${o.glow ? 'attribute float glow; varying float vGlow;' : ''}
${o.vertexHead || ''}`);
    vs = vs.replace('#include <begin_vertex>', `#include <begin_vertex>
${o.vertexMain || ''}`);
    vs = vs.replace('#include <project_vertex>', `#include <project_vertex>
${WORLD_VARYING_VERT}
${o.glow ? 'vGlow = glow;' : ''}`);
    shader.vertexShader = vs;

    let fs = shader.fragmentShader;
    fs = fs.replace('#include <common>', `#include <common>
varying vec3 vEnvWorld;
${o.glow ? 'varying float vGlow;' : ''}
uniform vec4 uFire;     // rgb fire colour * flicker, a: baked glow strength
uniform vec4 uKeyMask;  // x focus, y inner radius, z outer radius, w min factor
uniform float uTime;
uniform float uFocusZ;  // focus z (0 in the duel; the action-RPG mode moves it with the hero)
// the key light's pool on the terrace floor: full on the fight band around the focus, 24% elsewhere
float envFloorKey(vec3 w) { float dz = w.z - uFocusZ; return mix(0.24, 0.95, exp(-dz * dz / 11.0) * (1.0 - smoothstep(5.0, 12.0, abs(w.x - uKeyMask.x)))); }
${SKY_BASE}
${FOG}
${o.fragHead || ''}`);
    fs = fs.replace('#include <lights_fragment_begin>', `
float envKeyMask = 1.0;
float envRimMask = 1.0;
${o.keyMask === false ? '' : KEY_MASK}
${o.keyMaskExtra || ''}
${lightsBegin(o.dirLight)}`);
    if (o.glow) {
      fs = fs.replace('#include <emissivemap_fragment>', `#include <emissivemap_fragment>
totalEmissiveRadiance += diffuseColor.rgb * uFire.rgb * (vGlow * uFire.a);`);
    }
    for (const [chunk, code] of Object.entries(o.fragReplace || {})) {
      const tag = `#include <${chunk}>`;
      if (!fs.includes(tag)) throw new Error('env patch: missing chunk ' + chunk);
      fs = fs.replace(tag, code);
    }
    fs = fs.replace('#include <fog_fragment>', 'gl_FragColor.rgb = applyEnvFog(gl_FragColor.rgb, vEnvWorld);');
    shader.fragmentShader = fs;
  };
  return mat;
}

const ornUniforms = (orn, ornK) => ({
  tOrn: { value: orn.atlas.texture }, tWeather: { value: orn.weather.texture }, uOrnK: { value: new THREE.Vector4(...ornK) },
  uPaintA: { value: new THREE.Color(...PALETTE.ochre) }, uPaintB: { value: new THREE.Color(0.24, 0.04, 0.028) },
  uPaintC: { value: new THREE.Color(0.036, 0.095, 0.078) }, uBare: { value: new THREE.Color(0.072, 0.066, 0.06) },
});

/**
 * Weathered stone and fired roof tiles (merged geometry: vertex colour multiplier + glow attribute + tiling detail
 * maps). The geometry's `orn` attribute carves relief from the atlas ({ atlas, weather } from bakeOrnament) and the
 * surface weathers (cracks, rain streaks, lichen, moss); `ornK` = [relief, weathering, moss, lichen] strengths.
 */
export function createStoneMaterial(U, stoneMaps, orn, ornK = [1, 1, 1, 1]) {
  const mat = new THREE.MeshStandardMaterial({
    name: 'env.stone',
    color: new THREE.Color(0.13, 0.136, 0.152),
    map: stoneMaps.a.texture,
    normalMap: stoneMaps.b.texture,
    normalScale: new THREE.Vector2(0.75, 0.75),
    roughness: 0.84,
    metalness: 0,
    vertexColors: true,
    envMapIntensity: 0.7,
  });
  return patchStandard(mat, U, {
    key: 'stone-orn',
    glow: true,
    extraUniforms: ornUniforms(orn, ornK),
    vertexHead: ORN_VERT_HEAD,
    vertexMain: ORN_VERT_MAIN,
    fragHead: ORN_FRAG_HEAD,
    fragReplace: { map_fragment: ornMap('stone'), normal_fragment_maps: ORN_NORMAL },
  });
}

/**
 * Painted timber and everything else that is not stone or metal (bare wood, bark, rope, hide): albedo = vertex
 * colour x a grain map running along v; the relief atlas carves and, where the builder gives a positive amount,
 * paints the faded 단청 patterns; lacquer flakes off to grey wood. `ornK` = [relief, checks, moss, flaking].
 */
export function createTimberMaterial(U, woodMaps, orn, ornK = [1, 1, 0.6, 1]) {
  const mat = new THREE.MeshStandardMaterial({
    name: 'env.timber',
    color: new THREE.Color(1.32, 1.32, 1.32),
    map: woodMaps.a.texture,
    normalMap: woodMaps.b.texture,
    normalScale: new THREE.Vector2(0.6, 0.6),
    roughness: 0.74,
    metalness: 0,
    vertexColors: true,
    envMapIntensity: 0.45,
  });
  return patchStandard(mat, U, {
    key: 'timber',
    glow: true,
    extraUniforms: ornUniforms(orn, ornK),
    vertexHead: ORN_VERT_HEAD,
    vertexMain: ORN_VERT_MAIN,
    fragHead: ORN_FRAG_HEAD,
    fragReplace: {
      color_fragment: ornMap('timber'),
      roughnessmap_fragment: 'float roughnessFactor = clamp(roughness * envRoughK, 0.05, 1.0);',
      normal_fragment_maps: ORN_NORMAL,
    },
  });
}

/**
 * Bronze and iron (censers, fittings, blades): metal whose albedo is the vertex colour, with relief from the atlas
 * and verdigris / rust that kills the metallic response where it has taken hold.
 */
export function createMetalMaterial(U, stoneMaps, orn, ornK = [1, 1, 0, 0]) {
  const mat = new THREE.MeshStandardMaterial({
    name: 'env.metal',
    color: new THREE.Color(1.6, 1.6, 1.6),
    map: stoneMaps.a.texture,
    roughness: 0.46,
    metalness: 0.9,
    vertexColors: true,
    envMapIntensity: 0.85,
  });
  return patchStandard(mat, U, {
    key: 'metal',
    extraUniforms: ornUniforms(orn, ornK),
    vertexHead: ORN_VERT_HEAD,
    vertexMain: ORN_VERT_MAIN,
    fragHead: ORN_FRAG_HEAD,
    fragReplace: {
      color_fragment: ornMap('metal'),
      roughnessmap_fragment: 'float roughnessFactor = clamp(roughness * envRoughK, 0.05, 1.0);',
      metalnessmap_fragment: 'float metalnessFactor = metalness * (1.0 - 0.8 * envOrnMask);',
      normal_fragment_maps: ORN_NORMAL,
    },
  });
}

const FOLIAGE_VERT = /* glsl */ `
attribute vec3 color;
attribute vec3 aSway;   // x: sway amplitude (m) at this vertex, y: phase, z: flutter amount
uniform float uTime;
uniform vec3 uWind;
varying vec2 vUv; varying vec3 vC; varying vec3 vW; varying vec3 vN;
void main() {
  vec3 p = position;
  float amp = aSway.x, ph = aSway.y;
  vec2 wd = normalize(uWind.xz);
  float gust = 0.55 + 0.45 * sin(uTime * 0.63 + p.x * 0.11 + p.z * 0.07) * sin(uTime * 0.37 + ph);
  float sw = sin(uTime * 1.25 + ph + p.y * 0.25) * 0.6 + sin(uTime * 2.7 + ph * 1.7) * 0.22;
  p.xz += wd * amp * (0.35 * gust + sw * (0.4 + 0.6 * gust));
  p.xz += vec2(-wd.y, wd.x) * amp * 0.35 * sin(uTime * 0.9 + ph * 2.3);
  p += vec3(sin(uTime * 5.3 + p.x * 3.1 + ph), sin(uTime * 4.1 + p.z * 2.7 + ph) * 0.5, cos(uTime * 4.7 + p.y * 2.9 + ph)) * 0.03 * aSway.z * min(amp * 6.0 + 0.15, 1.0);
  vec4 w = modelMatrix * vec4(p, 1.0);
  vW = w.xyz; vUv = uv; vC = color; vN = normalize(mat3(modelMatrix) * normal);
  gl_Position = projectionMatrix * viewMatrix * w;
}`;
const FOLIAGE_FRAG = /* glsl */ `
${NOISE}
${SKY_BASE}
${FOG}
uniform sampler2D tFol;
uniform vec3 uAmb, uKeyCol, uKeyDir, uRimCol;
uniform vec4 uKeyMask, uFire;
varying vec2 vUv; varying vec3 vC; varying vec3 vW; varying vec3 vN;
void main() {
  vec4 t = texture2D(tFol, vUv);
  if (t.a < 0.5) discard;
  vec3 alb = vC * (0.55 + 0.9 * t.r);
  vec3 n = normalize(vN);
  float mask = mix(uKeyMask.w, 1.0, 1.0 - smoothstep(uKeyMask.y, uKeyMask.z, length(vW.xz)));
  vec3 col = alb * (uAmb * (0.6 + 0.4 * n.y) + uKeyCol * mask * (0.3 + 0.7 * max(dot(n, uKeyDir), 0.0))) * 0.3183;
  // looking toward the eclipse through the needles: a cold edge light
  vec3 vd = normalize(vW - cameraPosition);
  col += alb * uRimCol * pow(max(dot(vd, uSunDir), 0.0), 5.0) * 0.5;
  col *= 1.0 - 0.75 * uMood.a;
  col *= mix(vec3(1.0), uMood.rgb, uMood.a);
  gl_FragColor = vec4(applyEnvFog(col, vW), 1.0);
}`;

/**
 * Ink-silhouette vegetation (pine needle pads, bamboo, dry grass): alpha-tested cards from the foliage atlas,
 * swaying in the vertex shader, lit by the sky and what little key reaches them, fogged like everything else.
 * `lights`: { amb: Color, key: Color (colour x intensity), keyDir: Vector3, rim: Color }
 */
export function createFoliageMaterial(U, tex, lights) {
  return new THREE.ShaderMaterial({
    name: 'env.foliage',
    vertexShader: FOLIAGE_VERT,
    fragmentShader: FOLIAGE_FRAG,
    uniforms: {
      uZenith: U.uZenith, uSkyMid: U.uSkyMid, uHorizon: U.uHorizon, uGlow: U.uGlow, uSunHalo: U.uSunHalo, uSunDir: U.uSunDir,
      uFogP: U.uFogP, uFogNear: U.uFogNear, uMood: U.uMood, uTime: U.uTime, uWind: U.uWind, uKeyMask: U.uKeyMask, uFire: U.uFire,
      tFol: { value: tex }, uAmb: { value: lights.amb }, uKeyCol: { value: lights.key }, uKeyDir: U.uKeyDir, uRimCol: { value: lights.rim },
    },
    side: THREE.DoubleSide,
  });
}
