// Material patches shared by the lit environment surfaces (MeshStandardMaterial + onBeforeCompile):
//  - world position varying, sky-matched height fog (replaces three's fog), mood darkening
//  - key-light mask: the key (directional light #0 = env.sun) falls off away from the arena so the backdrop is
//    carried by silhouettes, rims and brazier pools instead of flat front light
//  - baked brazier warmth (per-vertex `glow`) as flickering emissive (stronger on tiers without point lights)

import * as THREE from 'three';
import { SKY_BASE, FOG } from './glsl.js';
import { ORN_VERT_HEAD, ORN_VERT_MAIN, ORN_FRAG_HEAD, ORN_MAP, ORN_NORMAL } from './ornament.js';

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
const SHARED = ['uZenith', 'uSkyMid', 'uHorizon', 'uGlow', 'uSunHalo', 'uSunDir', 'uFogP', 'uFogNear', 'uMood', 'uFire', 'uKeyMask', 'uTime'];

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
// the key light's pool on the arena floor: full on the fight band around the focus, 24% elsewhere
float envFloorKey(vec3 w) { return mix(0.24, 0.95, exp(-w.z * w.z / 11.0) * (1.0 - smoothstep(5.0, 12.0, abs(w.x - uKeyMask.x)))); }
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

/**
 * Ruined stone (merged ruins geometry: vertex colour multiplier + glow attribute + tiling detail maps). With `orn`
 * ({ atlas, weather } from bakeOrnament) the geometry's `orn` attribute carves relief from the atlas and the surface
 * weathers (cracks, rain streaks, lichen, moss); `ornK` = [relief, weathering, moss, lichen] strengths.
 */
export function createStoneMaterial(U, stoneMaps, orn = null, ornK = [1, 1, 1, 1]) {
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
  if (!orn) return patchStandard(mat, U, { key: 'stone', glow: true });
  return patchStandard(mat, U, {
    key: 'stone-orn',
    glow: true,
    extraUniforms: { tOrn: { value: orn.atlas.texture }, tWeather: { value: orn.weather.texture }, uOrnK: { value: new THREE.Vector4(...ornK) } },
    vertexHead: ORN_VERT_HEAD,
    vertexMain: ORN_VERT_MAIN,
    fragHead: ORN_FRAG_HEAD,
    fragReplace: { map_fragment: ORN_MAP, normal_fragment_maps: ORN_NORMAL },
  });
}

/**
 * Dressing that is not stone or iron (wax candles, dead vines and roots, wood, cloth offerings): albedo from the
 * vertex colour, warm translucency from the `glow` attribute (wax near a flame glows from inside).
 */
export function createPropMaterial(U) {
  const mat = new THREE.MeshStandardMaterial({ name: 'env.props', color: 0xffffff, roughness: 0.82, metalness: 0, vertexColors: true, envMapIntensity: 0.3 });
  return patchStandard(mat, U, { key: 'props', glow: true });
}

/** Wrought iron for brazier bowls and banner poles. */
export function createIronMaterial(U) {
  const mat = new THREE.MeshStandardMaterial({ name: 'env.iron', color: new THREE.Color(0.09, 0.08, 0.075), roughness: 0.5, metalness: 0.85, vertexColors: true, envMapIntensity: 0.8 });
  return patchStandard(mat, U, { key: 'iron' });
}
