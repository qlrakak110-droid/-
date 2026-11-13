// 「천무대 天武臺」: the ruined summit duelling terrace of the Heaven-Martial Sect. See README.md for the API and the art guide.
//
//   const env = createEnvironment(ctx, { detail, seed, post })
//   env.setFocus(midX); env.setMood({ darken: 0.8, tint: 0x8aa0ff, duration: 0.3 }); env.setMood(null);
//   env.pulse([x, 0, z], [3, 1.2, 0.3], 1);

import * as THREE from 'three';
import { makeRng, clamp, lerp } from '../core/math.js';
import { SUN_DIR, RIM_DIR, KEY_DIR, WIND, LAYOUT, PALETTE, tierSettings, rimR } from './config.js';
import { bakeFloor, bakeStone, bakeBanner, bakeFoliage, bakeWood, releaseBakeQuad } from './bake.js';
import { createSky } from './sky.js';
import { buildRuins } from './ruins.js';
import { createStoneMaterial, createTimberMaterial, createMetalMaterial, createFoliageMaterial } from './materials.js';
import { createFloor, createReflectionOverlay } from './floor.js';
import { bakeOrnament } from './ornament.js';
import { createFar } from './far.js';
import { createAtmosphere } from './atmosphere.js';
import { createParticles } from './particles.js';
import { createBanners, createFire } from './props.js';

const COPY_FRAG = /* glsl */ `
uniform sampler2D tSrc;
varying vec2 vUv;
void main() { gl_FragColor = vec4(min(texture2D(tSrc, vUv).rgb, vec3(24.0)), 1.0); }`;

const toColor = (c, out) => {
  if (c === undefined || c === null) return out.setRGB(1, 1, 1);
  if (c.isColor) return out.copy(c);
  if (Array.isArray(c)) return out.setRGB(c[0], c[1], c[2]);
  return out.set(c);
};
const toVec3 = (p, out) => (Array.isArray(p) ? out.set(p[0], p[1], p[2]) : out.copy(p));

/**
 * Build the 천무대 arena and register it as ctx.env.
 * @param {object} ctx  app context
 * @param {object} [opts]
 * @param {number} [opts.detail]  override ctx.quality.envDetail (0..2)
 * @param {number} [opts.seed]    layout seed (default fixed: the arena is authored)
 * @param {boolean} [opts.post]   apply the arena's post baseline (default true)
 * @returns {object} env
 */
export function createEnvironment(ctx, opts = {}) {
  const { renderer, scene, quality } = ctx;
  const tier = tierSettings(quality, opts.detail);
  const rng = makeRng(opts.seed !== undefined ? opts.seed : 0xec1195);
  const root = new THREE.Group();
  root.name = 'env';
  const owned = { geo: new Set(), mat: new Set(), rt: [] };

  // ---- shared uniforms ---------------------------------------------------------------------------------------------
  const U = {
    uTime: { value: 0 },
    uSunDir: { value: SUN_DIR.clone() },
    uWind: { value: WIND.clone() },
    uZenith: { value: PALETTE.zenith.clone() },
    uSkyMid: { value: PALETTE.skyMid.clone() },
    uHorizon: { value: PALETTE.horizon.clone() },
    uGlow: { value: PALETTE.glow.clone() },
    uSunHalo: { value: PALETTE.sunHalo.clone() },
    uCorona: { value: PALETTE.corona.clone() },
    uChromo: { value: PALETTE.chromo.clone() },
    uRim: { value: PALETTE.rim.clone().multiplyScalar(0.5) },
    uRimFar: { value: new THREE.Color(0.3, 0.34, 0.44) },
    uKeyDir: { value: KEY_DIR.clone() },
    // density at y=0, height falloff, far boost, max
    uFogP: { value: new THREE.Vector4(0.03, 0.1, 0.6, 0.92) },
    uFogNear: { value: PALETTE.fogNear.clone() },
    uMood: { value: new THREE.Vector4(1, 1, 1, 0) },
    uFire: { value: new THREE.Vector4(PALETTE.fire.r, PALETTE.fire.g, PALETTE.fire.b, tier.pointLights > 0 ? 0.3 : 1.1) },
    uKeyMask: { value: new THREE.Vector4(0, 8.5, 16.5, 0.12) },
    uFocusZ: { value: 0 },
  };

  // ---- baked textures ----------------------------------------------------------------------------------------------
  const floorMaps = bakeFloor(renderer, tier.floorTex);
  const stoneMaps = bakeStone(renderer, tier.stoneTex);
  const bannerRT = bakeBanner(renderer);
  const ornMaps = bakeOrnament(renderer, tier.ornTex);
  const woodMaps = bakeWood(renderer, tier.detail >= 1 ? 512 : 256);
  const foliageRT = bakeFoliage(renderer, tier.detail >= 1 ? 512 : 256);
  releaseBakeQuad();
  owned.rt.push(floorMaps.a, floorMaps.b, stoneMaps.a, stoneMaps.b, bannerRT, ornMaps.atlas, ornMaps.weather, woodMaps.a, woodMaps.b, foliageRT);

  // ---- the ruined summit: stone, timber, metal, foliage ---------------------------------------------------------------
  const ruins = buildRuins(rng, tier);
  const stoneMat = createStoneMaterial(U, stoneMaps, ornMaps, [1, tier.detail >= 1 ? 1 : 0.7, 1, 1]);
  const metalMat = createMetalMaterial(U, stoneMaps, ornMaps);
  const timberMat = createTimberMaterial(U, woodMaps, ornMaps);
  const foliageMat = createFoliageMaterial(U, foliageRT.texture, {
    amb: PALETTE.hemiSky.clone().multiplyScalar(1.6), key: PALETTE.key.clone().multiplyScalar(3.0), rim: PALETTE.rim.clone().multiplyScalar(0.6),
  });
  const stone = new THREE.Mesh(ruins.stone, stoneMat);
  stone.name = 'env.ruins';
  const iron = new THREE.Mesh(ruins.metal, metalMat);
  iron.name = 'env.metal';
  const props = new THREE.Mesh(ruins.props, timberMat);
  props.name = 'env.timber';
  const foliage = new THREE.Mesh(ruins.foliage, foliageMat);
  foliage.name = 'env.foliage';
  foliage.frustumCulled = false;
  root.add(stone, iron, props, foliage);

  // warm floor pools: the four fires of env.braziers, then the lit lanterns that stand on the terrace floor
  const poolAt = [...ruins.braziers, ...ruins.lamps.filter((p) => p.y < 2.2)];
  const floor = createFloor(U, floorMaps, stoneMaps, tier, poolAt);
  root.add(floor.mesh);

  const far = createFar(U, rng, tier);
  root.add(far.far, far.clouds);

  const banners = createBanners(U, ruins.banners, bannerRT.texture);
  const fire = createFire(U, ruins.flames, rng);
  const atmosphere = createAtmosphere(U, rng, tier, ruins.smokes);
  const censers = ruins.braziers.filter((b, i) => LAYOUT.braziers[i][2] === 'censer');
  const particles = createParticles(U, rng, tier, censers, floor.uniforms);
  root.add(banners, fire, atmosphere, particles);

  const sky = createSky(U, { octaves: tier.skyOctaves });
  root.add(sky);

  // ---- lights (fixed set, created once) ------------------------------------------------------------------------------
  const base = { key: 3.0, rim: 4.2, hemi: 0.5, point: 20 };
  const target = new THREE.Object3D();
  target.name = 'env.lightTarget';
  target.position.set(0, 1, 0);
  const sun = new THREE.DirectionalLight(PALETTE.key, base.key);
  sun.name = 'env.sun';
  sun.target = target;
  sun.castShadow = !!quality.shadows;
  if (sun.castShadow) {
    const size = quality.shadowSize || 1024;
    sun.shadow.mapSize.set(size, size);
    const c = sun.shadow.camera;
    c.left = -8.5; c.right = 8.5; c.top = 6.5; c.bottom = -5.5; c.near = 2; c.far = 46;
    c.updateProjectionMatrix();
    sun.shadow.bias = -0.00035;
    sun.shadow.normalBias = 0.025;
  }
  const rim = new THREE.DirectionalLight(PALETTE.rim, base.rim);
  rim.name = 'env.rim';
  rim.target = target;
  const hemi = new THREE.HemisphereLight(PALETTE.hemiSky, PALETTE.hemiGround, base.hemi);
  hemi.name = 'env.hemi';
  // key first: directional light #0 is the key in every env shader (shadow casters sort first as well)
  root.add(target, sun, rim, hemi);
  // fire lights: the first `pointLights` of env.braziers (the two lit lanterns on the vista shoulders come first, then
  // the censers); every other fire is baked glow + a floor pool
  const points = [];
  for (let i = 0; i < tier.pointLights; i++) {
    const b = ruins.braziers[i];
    const l = new THREE.PointLight(PALETTE.fire, base.point, 16, 2);
    l.name = 'env.brazier' + i;
    l.position.set(b.x, b.y + 0.12, b.z);
    l.userData.brazier = i;
    points.push(l);
    root.add(l);
  }
  floor.setBrazierPool(poolAt.map((b, i) => (points.some((p) => p.userData.brazier === i) ? 0.15 : i < 4 ? 0.6 : 0.42)));
  {
    const k = Math.hypot(KEY_DIR.x, KEY_DIR.z);
    floor.uniforms.uContactK.value.x = -KEY_DIR.x / k;
    floor.uniforms.uContactK.value.y = -KEY_DIR.z / k;
  }

  const R = new THREE.Vector3().crossVectors(new THREE.Vector3(0, 1, 0), KEY_DIR).normalize();
  const Uc = new THREE.Vector3().crossVectors(KEY_DIR, R).normalize();
  const tmpT = new THREE.Vector3();
  let focusX = 0;
  /**
   * Keep the key light on the action (texel-snapped so shadows never crawl). `z` is 0 in the duel; a mode that
   * leaves the fight line (the action-RPG) passes the hero's z as well and the floor's key pool follows.
   */
  function setFocus(x, z = 0) {
    focusX = clamp(Number(x) || 0, LAYOUT.floorR * -0.8, LAYOUT.floorR * 0.8);
    const focusZ = clamp(Number(z) || 0, LAYOUT.floorR * -0.9, LAYOUT.floorR * 0.9);
    U.uKeyMask.value.x = focusX;
    U.uFocusZ.value = focusZ;
    tmpT.set(focusX, 1.0, focusZ);
    const texel = sun.castShadow ? (sun.shadow.camera.right - sun.shadow.camera.left) / sun.shadow.mapSize.x : 0.01;
    const a = Math.round(tmpT.dot(R) / texel) * texel, b = Math.round(tmpT.dot(Uc) / texel) * texel, c = tmpT.dot(KEY_DIR);
    target.position.copy(R).multiplyScalar(a).addScaledVector(Uc, b).addScaledVector(KEY_DIR, c);
    sun.position.copy(target.position).addScaledVector(KEY_DIR, 22);
    rim.position.copy(target.position).addScaledVector(RIM_DIR, 22);
    target.updateMatrixWorld();
  }
  setFocus(0);

  // ---- environment map (PMREM of the sky + ring silhouette + light cards) ----------------------------------------------
  const envRT = buildEnvMap(renderer, U, ruins.braziers);
  const envMap = envRT.texture;
  owned.rt.push(envRT);
  const prevScene = { fog: scene.fog, background: scene.background, environmentIntensity: scene.environmentIntensity };
  // bind the PMREM on the env's own materials: with only scene.environment, three r170 replaces every material's
  // envMapIntensity by scene.environmentIntensity, and the authored strengths (stone 0.35 ...) would be lost.
  // update() scales them with the mood like scene.environmentIntensity.
  const envMats = [];
  root.traverse((o) => { const m = o.material; if (m && m.isMeshStandardMaterial && !envMats.some((e) => e.m === m)) envMats.push({ m, k: m.envMapIntensity }); });
  for (const e of envMats) { e.m.envMap = envMap; e.m.needsUpdate = true; }
  scene.environment = envMap;
  scene.environmentIntensity = 1;
  scene.fog = new THREE.FogExp2(PALETTE.fogNear.clone(), 0.008);
  scene.background = PALETTE.zenith.clone();
  scene.add(root);

  // ---- post baseline ---------------------------------------------------------------------------------------------
  const baseline = { exposure: 1.1, vignette: 0.4, grain: 0.032, saturation: 0.94, contrast: 1.05, bloom: 0.95, bloomThreshold: 1.0, bloomKnee: 0.55, bloomRadius: 1.0, tint: new THREE.Color(1.0, 0.985, 1.0), lift: new THREE.Color(0.0025, 0.003, 0.0055) };
  if (opts.post !== false && ctx.post) ctx.post.setBaseline(baseline);

  // ---- reflection (high tier): this frame's HDR scene, copied and re-projected onto the puddles ------------------------
  // post.onAfterScene runs right after the scene render (MSAA already resolved into sceneTarget.texture): copy it at
  // half resolution with mips, then draw the puddle pass into the same (multisampled) target, depth-tested against
  // the scene; post resolves again before bloom. No frame of lag, correct on camera cuts.
  let refl = null;
  if (tier.reflection && ctx.post && ctx.post.onAfterScene) {
    const rt = new THREE.WebGLRenderTarget(4, 4, { type: THREE.HalfFloatType, generateMipmaps: true, minFilter: THREE.LinearMipmapLinearFilter, magFilter: THREE.LinearFilter, depthBuffer: false });
    const mat = new THREE.ShaderMaterial({ vertexShader: 'varying vec2 vUv; void main() { vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }', fragmentShader: COPY_FRAG, uniforms: { tSrc: { value: null } }, depthTest: false, depthWrite: false });
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(new Float32Array([-1, -1, 0, 3, -1, 0, -1, 3, 0]), 3));
    g.setAttribute('uv', new THREE.BufferAttribute(new Float32Array([0, 0, 2, 0, 0, 2]), 2));
    const q = new THREE.Mesh(g, mat);
    q.frustumCulled = false;
    const qs = new THREE.Scene();
    qs.add(q);
    const overlay = createReflectionOverlay(U, floor, envMap, rt.texture);
    const os = new THREE.Scene();
    os.add(overlay.mesh);
    refl = { rt, mat, g, qs, os, overlay, cam: new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1), off: null };
    owned.rt.push(rt); owned.mat.add(mat); owned.mat.add(overlay.mesh.material); owned.geo.add(g);
    refl.off = ctx.post.onAfterScene((r, target, camera) => {
      if (!target || camera !== ctx.camera || !root.visible) return;
      const w = Math.max(2, target.width >> 1), h = Math.max(2, target.height >> 1);
      if (rt.width !== w || rt.height !== h) rt.setSize(w, h);
      mat.uniforms.tSrc.value = target.texture;
      const prevAuto = r.autoClear;
      r.setRenderTarget(rt);
      r.render(qs, refl.cam);
      camera.updateMatrixWorld();
      overlay.uniforms.uVP.value.multiplyMatrices(camera.projectionMatrix, camera.matrixWorldInverse);
      overlay.uniforms.uEnvI.value = floor.mesh.material.envMapIntensity;
      r.autoClear = false;
      r.setRenderTarget(target);
      r.render(os, camera);
      r.autoClear = prevAuto;
    });
  }
  /** Kept for compatibility: the puddle reflection is now taken from the current frame (post.onAfterScene). */
  function captureReflection() {}

  // ---- mood --------------------------------------------------------------------------------------------------------
  const white = new THREE.Color(1, 1, 1);
  const mood = { d: 0, tint: new THREE.Color(1, 1, 1), fromD: 0, toD: 0, fromT: new THREE.Color(1, 1, 1), toT: new THREE.Color(1, 1, 1), t: 1, dur: 1 };
  const tmpC = new THREE.Color();
  /**
   * Dim / tint the whole world for ultimates; setMood(null) restores.
   * @param {{darken?: number, tint?: any, duration?: number}|null} m
   */
  function setMood(m) {
    mood.fromD = mood.d; mood.fromT.copy(mood.tint);
    if (m) { mood.toD = clamp(m.darken !== undefined ? m.darken : 0.75); toColor(m.tint !== undefined ? m.tint : 0xffffff, mood.toT); }
    else { mood.toD = 0; mood.toT.copy(white); }
    mood.t = 0;
    mood.dur = Math.max(1e-3, m && m.duration !== undefined ? m.duration : m ? 0.3 : 0.45);
  }

  // ---- pulse -------------------------------------------------------------------------------------------------------
  const pv = new THREE.Vector3(), pc = new THREE.Color();
  /**
   * Brief floor glow + ripple (and a shove of the ambient particles) at a world position.
   * @param {THREE.Vector3|number[]} pos
   * @param {THREE.Color|number|string|number[]} [color]  linear HDR (e.g. [3, 1.2, 0.3])
   * @param {number} [strength] 0..2
   */
  function pulse(pos, color = [3, 1.3, 0.35], strength = 1) {
    toVec3(pos, pv);
    toColor(color, pc);
    const m = Math.max(pc.r, pc.g, pc.b, 1e-3);
    pc.multiplyScalar(Math.min(1, 2.2 / m) * 0.45);
    floor.pulse(pv, pc, clamp(strength, 0, 2), 9.5);
  }

  // ---- ground contact ------------------------------------------------------------------------------------------------
  /**
   * Ground a body on the floor: soft contact occlusion under it and, on tiers without a shadow map, a blob shadow
   * cast away from the key light. Call every frame per fighter (cheap: four uniform writes). Fades as `pos.y` rises.
   * @param {number} i              slot 0..3
   * @param {THREE.Vector3|number[]|null} pos  root / floor point of the body (null clears the slot)
   * @param {number} [radius=0.35]  footprint radius (m)
   * @param {number} [height=1.9]   body height (m), sets the blob-shadow length
   */
  function setContact(i, pos, radius = 0.35, height = 1.9) {
    if (!(i >= 0 && i < 4)) return;
    if (!pos) { floor.clearContact(i); return; }
    toVec3(pos, pv);
    floor.setContact(i, pv.x, pv.y, pv.z, radius, height);
  }

  // ---- per-frame -----------------------------------------------------------------------------------------------------
  let envTime = 0;
  const flick = [1, 1, 1, 1];
  function update(dtGame, dtReal) {
    envTime += dtGame;
    if (envTime > 3600) envTime -= 3600;
    U.uTime.value = envTime;
    floor.update(dtGame);
    // mood (real time: transitions run through hit-stop and slow motion)
    if (mood.t < mood.dur) {
      mood.t = Math.min(mood.dur, mood.t + dtReal);
      const k = mood.t / mood.dur;
      const e = k * k * (3 - 2 * k);
      mood.d = lerp(mood.fromD, mood.toD, e);
      mood.tint.copy(mood.fromT).lerp(mood.toT, e);
    }
    const d = mood.d;
    U.uMood.value.set(mood.tint.r, mood.tint.g, mood.tint.b, d);
    // fire flicker drives the brazier lights, baked glow and flame tint together
    const t = envTime;
    for (let i = 0; i < 4; i++) flick[i] = 1 + 0.1 * Math.sin(t * 11.3 + i * 1.7) * Math.sin(t * 5.1 + i) + 0.06 * Math.sin(t * 23.0 + i * 4.1);
    const fireDim = 1 - 0.75 * d;
    for (const l of points) l.intensity = base.point * flick[l.userData.brazier] * fireDim;
    U.uFire.value.w = (points.length ? 0.3 : 1.1) * (0.5 * (flick[0] + flick[1])) * (1 - 0.7 * d);
    sun.intensity = base.key * (1 - 0.62 * d);
    hemi.intensity = base.hemi * (1 - 0.8 * d);
    rim.intensity = base.rim * (1 - 0.1 * d);
    rim.color.copy(PALETTE.rim).lerp(tmpC.copy(mood.tint).multiplyScalar(0.8), d * 0.6);
    scene.environmentIntensity = 1 - 0.65 * d;
    for (let i = 0; i < envMats.length; i++) envMats[i].m.envMapIntensity = envMats[i].k * scene.environmentIntensity;
    scene.fog.color.copy(PALETTE.fogNear).multiply(tmpC.copy(white).lerp(mood.tint, d)).multiplyScalar(1 - 0.86 * d);
  }
  const off = ctx.onUpdate(update, ctx.ORDER.ENV);

  // ---- colliders (data for modes that leave the fight line) ---------------------------------------------------------------
  const colliders = {
    circles: ruins.colliders.circles, boxes: ruins.colliders.boxes, stairs: ruins.stairs,
    radius: LAYOUT.floorR, platformY: LAYOUT.platY,
    /** radius of the terrace floor's edge at ring angle theta (radians from -Z toward +X): the wall, or the broken rim */
    rim: (theta) => rimR(theta),
    /**
     * Keep a body of radius `r` standing on the terrace floor out of everything solid: pushes (x, z) out of the
     * circles and boxes that reach the floor and back inside the wall / the rim (`margin` m short of the drop).
     * Writes the corrected point to `out` ({x, z} or a Vector3) and returns it. No allocation.
     */
    resolve(x, z, r = 0.4, out = { x: 0, z: 0 }, margin = 0.15) {
      for (let pass = 0; pass < 2; pass++) {
        for (let i = 0; i < colliders.circles.length; i++) {
          const c = colliders.circles[i];
          if (c.y0 > 0.5) continue;
          const dx = x - c.x, dz = z - c.z, d = Math.hypot(dx, dz), m = c.r + r;
          if (d < m && d > 1e-5) { x = c.x + (dx / d) * m; z = c.z + (dz / d) * m; }
        }
        for (let i = 0; i < colliders.boxes.length; i++) {
          const b = colliders.boxes[i];
          if (b.y0 > 0.5) continue;
          const cs = Math.cos(b.yaw), sn = Math.sin(b.yaw);
          const dx = x - b.x, dz = z - b.z;
          const lx = dx * cs - dz * sn, lz = dx * sn + dz * cs;          // into the box frame
          const px = b.hx + r - Math.abs(lx), pz = b.hz + r - Math.abs(lz);
          if (px > 0 && pz > 0) {
            let nx = lx, nz = lz;
            if (px < pz) nx = Math.sign(lx || 1) * (b.hx + r); else nz = Math.sign(lz || 1) * (b.hz + r);
            x = b.x + nx * cs + nz * sn; z = b.z - nx * sn + nz * cs;
          }
        }
        const d = Math.hypot(x, z), lim = rimR(Math.atan2(x, -z)) - r - (rimR(Math.atan2(x, -z)) < LAYOUT.floorR - 1e-3 ? margin : 0.02);
        if (d > lim) { x *= lim / d; z *= lim / d; }
      }
      out.x = x; out.z = z;
      return out;
    },
  };

  const env = {
    root, tier, uniforms: U,
    envMap, sun, rim, hemi, points,
    bounds: { minX: -9, maxX: 9 },
    floorY: 0,
    /** unit vector toward the eclipse */
    sunDir: SUN_DIR.clone(),
    /** unit vector toward the cold rim light (env.rim) */
    rimDir: RIM_DIR.clone(),
    /** unit vector toward the key light */
    keyDir: KEY_DIR.clone(),
    /** ambient wind, m/s (match smoke / cloth drift to it) */
    wind: WIND.clone(),
    /** the four fire sources (world): the flames of the two lit stone lanterns, then the two censers' bowls */
    braziers: ruins.braziers.map((b) => b.clone()),
    /** flames of the other lit stone lanterns (baked glow, no real light) */
    lamps: ruins.lamps.map((b) => b.clone()),
    /** solid things for a free-roaming mode (README "Colliders"): circles, boxes, the terrace's edge, the stairs, `resolve()` */
    colliders,
    /** named places (README "Landmarks") */
    landmarks: ruins.landmarks,
    /** the two guardian statues in the vista (README "The guardian statues"): positions, sizes, plinths, `visible`, `eyeGlow` */
    statues: far.statues,
    baseline,
    get focusX() { return focusX; },
    get mood() { return { darken: mood.d, tint: mood.tint.clone() }; },
    setFocus, setMood, pulse, setContact, captureReflection, update,
    /** Compile every env program now (call again after all modules have added their lights). */
    prewarm(camera = ctx.camera) { renderer.compile(scene, camera); },
    /** Draw calls / triangles the env submits per frame (main pass; the env casts no shadows). */
    stats() {
      let calls = 0, tris = 0;
      root.traverse((o) => {
        if (!o.isMesh || !o.visible) return;
        const g = o.geometry;
        const n = g.index ? g.index.count : g.attributes.position.count;
        const inst = g.isInstancedBufferGeometry ? g.instanceCount : 1;
        if (Array.isArray(o.material)) {
          // drawn group by group (the far layer: backdrop + the two statues); hidden groups cost nothing
          for (const gr of g.groups) if (o.material[gr.materialIndex].visible) { calls += 1; tris += gr.count / 3; }
          return;
        }
        calls += 1;
        tris += (n / 3) * inst;
      });
      // + the reflection copy and the puddle pass (high tier)
      if (refl) { calls += 2; tris += 1 + floor.mesh.geometry.index.count / 3; }
      return { calls, tris: Math.round(tris), tier: tier.detail, pointLights: points.length, sections: ruins.sections };
    },
    dispose() {
      off();
      if (refl && refl.off) refl.off();
      scene.remove(root);
      if (scene.environment === envMap) scene.environment = null;
      scene.fog = prevScene.fog;
      scene.background = prevScene.background;
      scene.environmentIntensity = prevScene.environmentIntensity;
      root.traverse((o) => { if (o.geometry) owned.geo.add(o.geometry); if (o.material) for (const m of [].concat(o.material)) owned.mat.add(m); });
      if (refl) refl.os.remove(refl.overlay.mesh);
      for (const g of owned.geo) g.dispose();
      for (const m of owned.mat) m.dispose();
      for (const r of owned.rt) r.dispose();
      if (ctx.env === env) ctx.env = null;
    },
  };
  ctx.env = env;
  renderer.compile(scene, ctx.camera);
  return env;
}

/** PMREM environment: the sky in env mode, the summit's dark skyline + wet floor for metals to reflect, a few light cards. */
function buildEnvMap(renderer, U, braziers) {
  const s = new THREE.Scene();
  const sky = createSky(U, { envMode: true });
  s.add(sky);
  const eye = 1.4;
  const ringMat = new THREE.MeshBasicMaterial({ color: new THREE.Color(0.006, 0.0065, 0.008), side: THREE.BackSide, fog: false });
  const ring = new THREE.CylinderGeometry(19, 19, 1, 64, 1, true);
  const p = ring.attributes.position;
  for (let i = 0; i < p.count; i++) {
    const x = p.getX(i), z = p.getZ(i), y = p.getY(i);
    const th = Math.atan2(x, -z);
    // the summit's skyline: nothing across the vista, the hall's roof on the west, the gate on the south, the
    // gallery and the bamboo elsewhere
    const a = Math.abs(th), deg = th * 180 / Math.PI;
    let top = 4.6 + 2.2 * Math.sin(th * 11) * Math.sin(th * 5.3);
    if (deg > -112 && deg < -46) top = 10.5;
    if (a > 2.74) top = 9.5;
    if (a < LAYOUT.gap) top = 0.3;
    const h = y > 0 ? top : 0;
    p.setY(i, (y > 0 ? h : 0) - eye);
  }
  const ringMesh = new THREE.Mesh(ring, ringMat);
  s.add(ringMesh);
  const floorMat = new THREE.MeshBasicMaterial({ color: new THREE.Color(0.01, 0.01, 0.012), fog: false });
  const floor = new THREE.Mesh(new THREE.CircleGeometry(19, 48), floorMat);
  floor.rotation.x = -Math.PI / 2;
  floor.position.y = -eye;
  s.add(floor);
  const cardGeo = new THREE.PlaneGeometry(1, 1);
  const cards = [];
  const card = (pos, w, h, color) => {
    const m = new THREE.Mesh(cardGeo, new THREE.MeshBasicMaterial({ color, side: THREE.DoubleSide, fog: false }));
    m.position.copy(pos);
    m.scale.set(w, h, 1);
    m.lookAt(0, 0, 0);
    s.add(m);
    cards.push(m);
  };
  card(KEY_DIR.clone().multiplyScalar(30), 16, 10, new THREE.Color(0.3, 0.32, 0.37));
  for (const b of braziers) card(new THREE.Vector3(b.x, b.y + 0.4 - eye, b.z), 1.4, 1.6, new THREE.Color(6, 2.4, 0.6));
  const pmrem = new THREE.PMREMGenerator(renderer);
  const rt = pmrem.fromScene(s, 0, 0.1, 1000);
  pmrem.dispose();
  sky.geometry.dispose(); sky.material.dispose(); ring.dispose(); ringMat.dispose(); floor.geometry.dispose(); floorMat.dispose(); cardGeo.dispose();
  for (const c of cards) c.material.dispose();
  return rt;
}
