// vfx.afterimage: fading ghost copies of an Object3D hierarchy (dashes, teleports, blur-fast strikes).
// A snapshot copies the world matrix of every Mesh in the hierarchy and, for a SkinnedMesh, the current bone matrices
// into a frozen skeleton, so the ghost keeps the pose of that instant while the character moves on. Ghosts share the
// source geometry (no copies); every ghost slot is pooled (a plain Mesh and a SkinnedMesh with a preallocated frozen
// 64-bone skeleton and its own material instance of ONE shared program), so a snapshot allocates nothing.
// Look: additive fresnel shell (rim-lit silhouette with a faint fill) in HDR core -> mid colours, drifting, eroding
// away with world-space noise. Each ghost mesh is one draw call: budget about (meshes per character x ghosts alive).

import * as THREE from 'three';
import { GLSL_COMMON } from './glsl.js';
import { toVec3, RENDER_ORDER } from './util.js';
import { resolveColors, makeColors, opt } from './meshfx.js';

const MAXB = 64;

const VERT = /* glsl */ `
#include <common>
#include <skinning_pars_vertex>
uniform vec4 uGhost;   // t0, life (signed), drift speed (m/s), swell (m)
uniform vec3 uDrift;
uniform float uTime, uTimeReal;
varying vec3 vN, vW;
varying float vT;
void main() {
  #include <skinbase_vertex>
  #include <beginnormal_vertex>
  #include <skinnormal_vertex>
  #include <begin_vertex>
  #include <skinning_vertex>
  float life = abs(uGhost.y);
  float age = (uGhost.y < 0.0 ? uTimeReal : uTime) - uGhost.x;
  float t = clamp(age / max(life, 1e-4), 0.0, 1.0);
  vec3 n = normalize(mat3(modelMatrix) * objectNormal);
  vec4 wp = modelMatrix * vec4(transformed, 1.0);
  wp.xyz += uDrift * age + n * uGhost.w * t;
  vN = n;
  vW = wp.xyz;
  vT = t;
  gl_Position = projectionMatrix * viewMatrix * wp;
}`;

const FRAG = /* glsl */ `
precision highp float;
uniform sampler2D uNoise;
uniform vec3 uCore, uMid;
uniform vec4 uLook;    // fill, fresnel power, alpha, erosion scale
varying vec3 vN, vW;
varying float vT;
${GLSL_COMMON}
void main() {
  vec3 V = normalize(cameraPosition - vW);
  float ndv = abs(dot(normalize(vN), V));
  float fres = pow(1.0 - ndv, uLook.y);
  float n = texture2D(uNoise, vW.xy * uLook.w + vW.z * 0.37).r * 0.7 + texture2D(uNoise, vW.zy * uLook.w * 2.3 + 0.5).a * 0.3;
  float th = mix(-0.15, 1.0, pow(vT, 1.3));
  float vis = smoothstep(th - 0.08, th + 0.08, n * 0.85 + fres * 0.15);
  float edge = (1.0 - smoothstep(th, th + 0.12, n * 0.85 + fres * 0.15)) * vis;
  // layered armour stacks several shells per ghost and ghosts overlap: keep each one dim (mid colour, core on the rim)
  vec3 col = mix(mix(uMid * 0.5, uCore * 0.32, fres * (1.0 - vT)), uMid * 0.25, smoothstep(0.2, 0.9, vT));
  float I = (fres * 0.9 + uLook.x) * (1.0 - vT) * (1.0 - vT * 0.3);
  vec3 rgb = col * I * vis * uLook.z + uCore * edge * 0.6 * (1.0 - vT);
  if (dot(rgb, rgb) < 1e-6) discard;
  gl_FragColor = vec4(rgb, 0.0);
}`;

/**
 * @param {object} vfx
 * @param {object} shared
 */
export function installAfterimage(vfx, shared) {
  const { ctx, root, uniforms, textures, clock } = shared;
  const N = ctx.quality.tier === 'low' ? 16 : ctx.quality.tier === 'mid' ? 28 : 40;
  // one material instance per slot (per-ghost uniforms), all from the same source: ONE program
  const uNoise = { value: textures.noise };
  const makeMat = () => new THREE.ShaderMaterial({
    vertexShader: VERT, fragmentShader: FRAG,
    uniforms: {
      uTime: uniforms.uTime, uTimeReal: uniforms.uTimeReal, uNoise,
      uGhost: { value: new THREE.Vector4() }, uDrift: { value: new THREE.Vector3() }, uCore: { value: new THREE.Color() }, uMid: { value: new THREE.Color() }, uLook: { value: new THREE.Vector4() },
    },
    transparent: true, depthWrite: false, depthTest: true, side: THREE.FrontSide,
    blending: THREE.CustomBlending, blendSrc: THREE.OneFactor, blendDst: THREE.OneMinusSrcAlphaFactor, blendSrcAlpha: THREE.OneFactor, blendDstAlpha: THREE.OneMinusSrcAlphaFactor,
  });
  const dummy = new THREE.BufferGeometry();
  dummy.setAttribute('position', new THREE.Float32BufferAttribute([0, 0, 0, 0, 0, 0, 0, 0, 0], 3));
  dummy.setAttribute('normal', new THREE.Float32BufferAttribute([0, 1, 0, 0, 1, 0, 0, 1, 0], 3));
  dummy.setAttribute('skinIndex', new THREE.Uint16BufferAttribute([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], 4));
  dummy.setAttribute('skinWeight', new THREE.Float32BufferAttribute([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0], 4));
  const bones = [];
  for (let i = 0; i < MAXB; i++) bones.push(new THREE.Bone());
  const noop = () => {};
  const frozen = (n) => {
    const sk = new THREE.Skeleton(n === MAXB ? bones : Array.from({ length: n }, () => new THREE.Bone()));
    sk.update = noop;          // the renderer calls update() every frame: keep the snapshot
    sk.computeBoneTexture();
    return sk;
  };
  const slots = [];
  for (let i = 0; i < N; i++) {
    const mat = makeMat();
    const plain = new THREE.Mesh(dummy, mat);
    const skinned = new THREE.SkinnedMesh(dummy, mat);
    const skel = frozen(MAXB);
    skinned.bind(skel, new THREE.Matrix4());
    for (const m of [plain, skinned]) {
      m.matrixAutoUpdate = false;
      m.frustumCulled = false;
      m.visible = false;
      m.renderOrder = RENDER_ORDER.meshBeam;
      m.name = 'vfx.afterimage' + i;
      root.add(m);
    }
    slots.push({ i, mat, plain, skinned, skel, live: false, obj: null, t0: 0, life: 0, realtime: false, serial: 0 });
  }
  let serial = 1;
  const lists = new WeakMap();
  const C = makeColors();
  const drift = new THREE.Vector3();

  function meshesOf(obj, filter) {
    let l = lists.get(obj);
    if (!l) {
      l = [];
      obj.traverse((o) => { if ((o.isMesh || o.isSkinnedMesh) && !o.isInstancedMesh && o.geometry && o.geometry.getAttribute('position') && (!filter || filter(o))) l.push(o); });
      lists.set(obj, l);
    }
    return l;
  }

  function take() {
    let s = null;
    for (const x of slots) if (!x.live) { s = x; break; }
    if (!s) { s = slots[0]; for (const x of slots) if (x.t0 < s.t0) s = x; free(s); }
    return s;
  }
  function free(s) {
    if (!s.live) return;
    s.live = false;
    s.serial = 0;
    s.plain.visible = s.skinned.visible = false;
    s.plain.geometry = s.skinned.geometry = dummy;
  }

  /** Snapshot every mesh of `obj` into ghost slots. Returns the slots used. */
  function snap(obj, o, out) {
    obj.updateMatrixWorld(true);
    const list = meshesOf(obj, o.filter);
    const now = o.realtime ? clock.real : clock.game;
    let used = 0;
    for (const m of list) {
      if (used >= o.maxMeshes) break;
      if (!m.visible || m.material === undefined) continue;
      let vis = true;
      for (let p = m.parent; p && p !== obj.parent; p = p.parent) if (!p.visible) { vis = false; break; }
      if (!vis) continue;
      const s = take();
      const g = m.isSkinnedMesh ? s.skinned : s.plain;
      g.geometry = m.geometry;
      g.matrix.copy(m.matrixWorld);
      g.matrixWorld.copy(m.matrixWorld);
      if (m.isSkinnedMesh) {
        const src = m.skeleton;
        src.update();
        const nb = src.bones.length;
        if (nb > s.skel.bones.length) { s.skel.dispose(); s.skel = frozen(nb); }
        s.skel.boneMatrices.set(src.boneMatrices.subarray(0, Math.min(nb * 16, s.skel.boneMatrices.length)));
        s.skel.boneTexture.needsUpdate = true;
        g.skeleton = s.skel;
        g.bindMode = m.bindMode;
        g.bindMatrix.copy(m.bindMatrix);
        g.bindMatrixInverse.copy(m.bindMatrixInverse);
      }
      const U = s.mat.uniforms;
      U.uGhost.value.set(now, o.realtime ? -o.life : o.life, 0, o.swell);
      U.uDrift.value.copy(drift);
      U.uCore.value.copy(C.core).multiplyScalar(o.intensity);
      U.uMid.value.copy(C.mid).multiplyScalar(o.intensity);
      U.uLook.value.set(o.fill, o.fresnel, o.alpha, o.erodeScale);
      g.visible = true;
      s.live = true;
      s.t0 = now;
      s.life = o.life;
      s.realtime = o.realtime;
      s.serial = serial++;
      out.push(s, s.serial);
      used++;
    }
  }

  /**
   * Ghost copies of a (skinned) Object3D hierarchy. See README "Afterimage".
   * Returns { kill(), stop(), alive } (stop() cancels pending snapshots; existing ghosts fade out).
   */
  function afterimage(obj, opts = {}) {
    if (!obj || !obj.isObject3D) throw new Error('vfx.afterimage needs an Object3D');
    resolveColors(opts, { palette: 'frost' }, C);
    if (opts.drift) toVec3(opts.drift, drift); else drift.set(0, 0, 0);
    const o = {
      life: opt(opts.life, 0.35), realtime: !!opts.realtime, intensity: opt(opts.intensity, 1), swell: opt(opts.swell, 0.03),
      fill: opt(opts.fill, 0.05), fresnel: opt(opts.fresnel, 2.6), alpha: opt(opts.alpha, 1), erodeScale: opt(opts.erodeScale, 1.6),
      maxMeshes: opt(opts.maxMeshes, 8), filter: opts.filter || null,
    };
    const count = Math.max(1, opt(opts.count, 1));
    const interval = opt(opts.interval, 0.045);
    const ghosts = [];
    snap(obj, o, ghosts);
    const pending = [];
    for (let i = 1; i < count && Number.isFinite(count); i++) pending.push(vfx.schedule(i * interval, () => snap(obj, o, ghosts), { realtime: o.realtime }));
    const h = {
      get alive() {
        for (let i = 0; i < ghosts.length; i += 2) if (ghosts[i].live && ghosts[i].serial === ghosts[i + 1]) return true;
        for (const p of pending) if (p.alive) return true;
        return false;
      },
      stop() { for (const p of pending) p.kill(); },
      kill() { h.stop(); for (let i = 0; i < ghosts.length; i += 2) if (ghosts[i].serial === ghosts[i + 1]) free(ghosts[i]); },
    };
    shared.track(h);
    return h;
  }

  return {
    name: 'afterimage',
    api: { afterimage },
    update() {
      for (const s of slots) {
        if (!s.live) continue;
        if ((s.realtime ? clock.real : clock.game) - s.t0 >= s.life) free(s);
      }
    },
    clear() { for (const s of slots) free(s); },
    /** upload every slot's frozen bone texture now (no texture upload on the first ghost) */
    prewarm() { for (const s of slots) ctx.renderer.initTexture(s.skel.boneTexture); },
    dispose() { for (const s of slots) { s.mat.dispose(); s.skel.dispose(); s.plain.removeFromParent(); s.skinned.removeFromParent(); } dummy.dispose(); },
  };
}
