// Shadow-frustum manager: fits the key light's orthographic shadow camera to the shadow casters every frame.
//
//   ctx.shadows.setKey(env.sun)            the managed directional light (auto: the first castShadow DirectionalLight)
//   ctx.shadows.mode = 'auto'              fit to every visible castShadow mesh (skinned: its sampled bones)
//   ctx.shadows.focus(center, radius)      'manual': fit to this sphere instead (kept until the next call)
//   ctx.shadows.mode = 'off'               leave the light's shadow camera / bias alone
//
// Runs inside the main scene render (scene.onBeforeRender: world matrices are fresh, the shadow pass has not run yet).
// The window is a square in light space, sized in quantised steps with hysteresis (grows at once, shrinks after it has
// been too big for `shrinkDelay` seconds) and snapped to a world-fixed texel grid, so moving fighters never make the
// shadow edges crawl. Bias and normal bias are set in texels of the current window: crisp contact, no acne, no
// peter-panning. Only the shadow camera bounds, near/far and bias are touched; the light's position, target, colour
// and intensity stay with their owner (env).

import * as THREE from 'three';

const UP = new THREE.Vector3(0, 1, 0);

/**
 * @param {object} ctx  app context (reads ctx.quality, ctx.env.floorY when present)
 * @returns {object} shadows (stored on ctx.shadows by createApp)
 */
export function createShadows(ctx) {
  const params = {
    margin: 0.35,          // m added around the casters
    minExtent: 4.5,        // m, smallest window side
    maxExtent: 40,         // m, largest window side
    step: 1.12,            // window sizes are minExtent * step^k
    shrinkDelay: 0.6,      // s the window must be too big before it shrinks one or more steps
    biasTexels: 0.6,       // depth bias, in texels of the window (along the light)
    normalBiasTexels: 1.4, // receiver offset along its normal, in texels
    bonePad: 0.32,         // m around sampled bones of skinned casters (armour, cloth)
    depthPad: 0.6,         // m added to near / far
  };
  const R = new THREE.Vector3(), U = new THREE.Vector3(), Z = new THREE.Vector3();
  const eye = new THREE.Vector3(), tgt = new THREE.Vector3(), p = new THREE.Vector3();
  const manual = { center: new THREE.Vector3(), radius: 0, set: false };
  const casters = [];
  const seenSkel = new Set();
  let key = null, keyAuto = true, frame = 0, scanAt = -1e9;
  let extent = 0, shrinkT = 0, lastT = -1;
  // light-space bounds accumulated per frame (absolute projections on R / U / F)
  let x0 = 0, x1 = 0, y0 = 0, y1 = 0, d0 = 0, d1 = 0, n = 0, floorReach = 0;
  const info = { mode: 'auto', extent: 0, texel: 0, near: 0, far: 0, casters: 0, fitted: false };

  const visit = (o) => {
    if (o.isMesh && o.castShadow) casters.push(o);
    if (keyAuto && !key && o.isDirectionalLight && o.castShadow) key = o;
  };
  function scan(scene) {
    casters.length = 0;
    if (keyAuto) key = null;
    scene.traverse(visit);
    scanAt = frame;
  }
  const visibleChain = (o) => { for (; o; o = o.parent) if (!o.visible) return false; return true; };

  function addPoint(P, pad) {
    const xa = P.x * R.x + P.y * R.y + P.z * R.z;
    const ya = P.x * U.x + P.y * U.y + P.z * U.z;
    // depth along the light (F = -Z), relative to the eye
    const da = -((P.x - eye.x) * Z.x + (P.y - eye.y) * Z.y + (P.z - eye.z) * Z.z);
    if (n === 0) { x0 = xa - pad; x1 = xa + pad; y0 = ya - pad; y1 = ya + pad; d0 = da - pad; d1 = da + pad; }
    else {
      if (xa - pad < x0) x0 = xa - pad; if (xa + pad > x1) x1 = xa + pad;
      if (ya - pad < y0) y0 = ya - pad; if (ya + pad > y1) y1 = ya + pad;
      if (da - pad < d0) d0 = da - pad; if (da + pad > d1) d1 = da + pad;
    }
    // where the shadow of this point lands on the floor (the floor must stay inside near..far)
    const fy = ctx.env && Number.isFinite(ctx.env.floorY) ? ctx.env.floorY : 0;
    const t = (P.y + pad - fy) / Math.max(0.05, Z.y);
    if (da + t > floorReach) floorReach = da + t;
    n++;
  }

  const shadows = {
    params, info,
    get enabled() { return !!ctx.quality.shadows; },
    /** 'auto' (fit to castShadow meshes) | 'manual' (fit to focus()) | 'off' (do not touch the light) */
    mode: 'auto',
    /** The managed light (null until found). */
    get key() { return key; },
    /** Manage this DirectionalLight (null: go back to auto-detection of the first castShadow DirectionalLight). */
    setKey(light) { key = light || null; keyAuto = !light; scanAt = -1e9; },
    /**
     * Fit the shadow window to a sphere (world) instead of the auto caster set; switches mode to 'manual'.
     * @param {THREE.Vector3|number[]} center
     * @param {number} radius  m
     */
    focus(center, radius = 1.5) {
      if (Array.isArray(center)) manual.center.set(center[0], center[1], center[2]); else manual.center.copy(center);
      manual.radius = Math.max(0.1, radius);
      manual.set = true;
      shadows.mode = 'manual';
    },
    /** Force a re-scan of the casters (call after adding a new shadow-casting object; otherwise every 30 frames). */
    rescan() { scanAt = -1e9; },

    /** Called by post.render from scene.onBeforeRender (matrices fresh, shadow pass not drawn yet). */
    update(scene) {
      frame++;
      info.mode = shadows.mode;
      info.fitted = false;
      if (!ctx.quality.shadows || shadows.mode === 'off') return;
      if (frame - scanAt >= 30 || (key && !key.parent)) scan(scene);
      if (!key || !key.castShadow || !key.shadow || !key.shadow.camera.isOrthographicCamera) return;

      eye.setFromMatrixPosition(key.matrixWorld);
      tgt.setFromMatrixPosition(key.target.matrixWorld);
      Z.subVectors(eye, tgt);
      if (Z.lengthSq() < 1e-8) return;
      Z.normalize();
      R.crossVectors(UP, Z);
      if (R.lengthSq() < 1e-8) return;
      R.normalize();
      U.crossVectors(Z, R);

      n = 0; floorReach = -1e9;
      if (shadows.mode === 'manual' && manual.set) {
        addPoint(manual.center, manual.radius + params.margin);
      } else {
        seenSkel.clear();
        let count = 0;
        for (let i = 0; i < casters.length; i++) {
          const o = casters[i];
          if (!visibleChain(o)) continue;
          count++;
          if (o.isSkinnedMesh && o.skeleton) {
            if (seenSkel.has(o.skeleton)) continue;
            seenSkel.add(o.skeleton);
            const bones = o.skeleton.bones;
            const stride = Math.max(1, Math.ceil(bones.length / 48));
            for (let b = 0; b < bones.length; b += stride) addPoint(p.setFromMatrixPosition(bones[b].matrixWorld), params.bonePad + params.margin);
          } else {
            const g = o.geometry;
            if (!g.boundingSphere) g.computeBoundingSphere();
            const s = g.boundingSphere;
            p.copy(s.center).applyMatrix4(o.matrixWorld);
            addPoint(p, s.radius * o.matrixWorld.getMaxScaleOnAxis() + params.margin);
          }
        }
        info.casters = count;
      }
      if (n === 0) return;

      // quantised square window with hysteresis
      const need = Math.min(params.maxExtent, Math.max(params.minExtent, x1 - x0, y1 - y0));
      const steps = Math.ceil(Math.log(need / params.minExtent) / Math.log(params.step) - 1e-6);
      const want = params.minExtent * Math.pow(params.step, Math.max(0, steps));
      const now = ctx.time ? ctx.time.real : frame / 60;
      const dt = lastT < 0 ? 0 : Math.min(0.1, Math.max(0, now - lastT));
      lastT = now;
      if (want > extent + 1e-6 || extent === 0) { extent = want; shrinkT = 0; }
      else if (want < extent / params.step + 1e-6) { shrinkT += dt; if (shrinkT >= params.shrinkDelay) { extent = want; shrinkT = 0; } }
      else shrinkT = 0;

      const cam = key.shadow.camera;
      const size = key.shadow.mapSize.x || 1024;
      const texel = extent / size;
      const ex = eye.dot(R), ey = eye.dot(U);
      const left = Math.floor(((x0 + x1) * 0.5 - extent * 0.5) / texel) * texel;
      const bottom = Math.floor(((y0 + y1) * 0.5 - extent * 0.5) / texel) * texel;
      cam.left = left - ex; cam.right = cam.left + extent;
      cam.bottom = bottom - ey; cam.top = cam.bottom + extent;
      cam.near = d0 - params.depthPad;
      cam.far = Math.max(d1, floorReach) + params.depthPad;
      cam.updateProjectionMatrix();
      const range = Math.max(0.5, cam.far - cam.near);
      key.shadow.bias = -params.biasTexels * texel / range;
      key.shadow.normalBias = params.normalBiasTexels * texel;
      info.extent = extent; info.texel = texel; info.near = cam.near; info.far = cam.far; info.fitted = true;
    },
  };
  return shadows;
}
