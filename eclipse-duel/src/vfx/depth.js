// Scene-depth link for the VFX materials: soft particles / mist that fade where they meet scene geometry, and
// refraction (heat haze, shocks) that leaves whatever stands in front of it alone.
//
// The post pipeline (src/post) keeps a half-res LINEAR view depth (metres) of the last rendered frame in
// ctx.post.depthUniforms.tSceneDepth (a 1x1 "far" texture on tiers without scene depth). In-scene materials must not
// sample the depth buffer they are drawing into, so everything here reads that previous-frame texture:
//
//   vfxSoft(invSoftness)   1 in open air -> 0 where the fragment touches the opaque scene behind it
//   vfxVisible(softness)   1 in front of the scene -> 0 behind it (for the distortion pass, which has no depth buffer)
//   vfxRefract(offset, s)  vfxVisible, and 0 where the refracted fetch would land on something nearer than the fragment
//
// A previous-frame depth is wrong for one frame after a camera cut and stale when frames were skipped (the capture
// harness advances many frames per render): `uDepthOn` drops to 0 for those frames, so effects fall back to their
// un-faded look instead of showing holes shaped like last frame's silhouettes. Tiers without scene depth compile the
// helpers to constants (no texture fetch).

import * as THREE from 'three';

/** GLSL helpers (fragment stage). Define VFX_DEPTH to enable; VFX_DEPTH_SCALE = 2.0 in the half-res distortion pass. */
export const DEPTH_FADE_GLSL = /* glsl */ `
#ifdef VFX_DEPTH
uniform sampler2D tSceneDepth;
uniform vec2 uSceneRes;
uniform vec2 uCamNearFar;
uniform float uDepthOn;
float vfxFragDepth() { return uCamNearFar.x * uCamNearFar.y / (uCamNearFar.y - gl_FragCoord.z * (uCamNearFar.y - uCamNearFar.x)); }
float vfxSceneDepth() { return texture2D(tSceneDepth, gl_FragCoord.xy * VFX_DEPTH_SCALE / uSceneRes).r; }
float vfxSoft(float invSoft) { return mix(1.0, clamp((vfxSceneDepth() - vfxFragDepth()) * invSoft, 0.0, 1.0), uDepthOn); }
float vfxVisible(float soft) { return mix(1.0, clamp((vfxSceneDepth() - vfxFragDepth()) / soft + 1.0, 0.0, 1.0), uDepthOn); }
// refraction: o is the UV offset this fragment asks the composite to apply. If the pixel it would fetch belongs to
// something in front of the refracting surface (a fighter before the heat), the fetch would smear that body outward:
// 0 there, 1 otherwise
float vfxRefract(vec2 o, float soft) {
  float d = texture2D(tSceneDepth, gl_FragCoord.xy * VFX_DEPTH_SCALE / uSceneRes + o).r;
  return vfxVisible(soft) * mix(1.0, clamp((d - vfxFragDepth()) / soft + 1.0, 0.0, 1.0), uDepthOn);
}
#else
float vfxSoft(float invSoft) { return 1.0; }
float vfxVisible(float soft) { return 1.0; }
float vfxRefract(vec2 o, float soft) { return 1.0; }
#endif
`;

/**
 * Create the depth link: { enabled, uniforms, defines(scale), dispose() }.
 * `uniforms` are stable uniform objects to spread into a ShaderMaterial; `defines(scale)` returns the defines for a
 * material drawn into the scene target (scale 1) or the half-res distortion target (scale 2).
 * @param {object} ctx  app context
 */
export function createDepthLink(ctx) {
  const post = ctx.post;
  const enabled = !!(post && post.depthUniforms && post.features && post.features.depth && !(ctx.flags && ctx.flags.nosoft));
  const uDepthOn = { value: 0 };
  const uniforms = enabled
    ? { tSceneDepth: post.depthUniforms.tSceneDepth, uSceneRes: post.depthUniforms.uSceneRes, uCamNearFar: post.depthUniforms.uCamNearFar, uDepthOn }
    : {};
  const lastPos = new THREE.Vector3(1e9, 0, 0), lastDir = new THREE.Vector3(0, 0, -1), dir = new THREE.Vector3(), pos = new THREE.Vector3();
  let lastReal = -1e9, off = null, offUpdate = null;
  if (enabled) {
    // remember when (and from where) the depth texture was last rendered
    off = post.onAfterScene((renderer, target, camera) => {
      lastReal = ctx.time.real;
      lastPos.setFromMatrixPosition(camera.matrixWorld);
      camera.getWorldDirection(lastDir);
    });
    // after the camera moved this frame: is last frame's depth still a fair picture of this frame?
    offUpdate = ctx.onUpdate(() => {
      const cam = ctx.camera;
      cam.getWorldDirection(dir);
      pos.setFromMatrixPosition(cam.matrixWorld);
      const fresh = ctx.time.real - lastReal < 0.055;
      const steady = pos.distanceToSquared(lastPos) < 0.5 * 0.5 && dir.dot(lastDir) > 0.975;
      uDepthOn.value = fresh && steady ? 1 : 0;
    }, ctx.ORDER.CAM + 5);
  }
  return {
    enabled, uniforms,
    /** Defines for a material: scene pass (scale 1) or half-res distortion pass (scale 2). */
    defines(scale = 1) { return enabled ? { VFX_DEPTH: 1, VFX_DEPTH_SCALE: scale === 2 ? '2.0' : '1.0' } : {}; },
    dispose() { if (off) off(); if (typeof offUpdate === 'function') offUpdate(); },
  };
}
