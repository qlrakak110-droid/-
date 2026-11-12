// Eclipse Ruins (일식의 폐허): the arena environment. See README.md for the API and the art guide.
//
//   const env = createEnvironment(ctx, { detail, seed, post })
//   env.setFocus(midX); env.setMood({ darken: 0.8, tint: 0x8aa0ff, duration: 0.3 }); env.setMood(null);
//   env.pulse([x, 0, z], [3, 1.2, 0.3], 1);

import * as THREE from 'three';
import { makeRng, clamp, lerp } from '../core/math.js';
import { SUN_DIR, KEY_DIR, WIND, LAYOUT, PALETTE, tierSettings } from './config.js';
import { bakeFloor, bakeStone, bakeBanner } from './bake.js';
import { createSky } from './sky.js';
import { buildRuins } from './ruins.js';
import { createStoneMaterial, createIronMaterial } from './materials.js';
import { createFloor } from './floor.js';
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
 * Build the Eclipse Ruins arena and register it as ctx.env.
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
  };

  // ---- baked textures ----------------------------------------------------------------------------------------------
  const floorMaps = bakeFloor(renderer, tier.floorTex);
  const stoneMaps = bakeStone(renderer, tier.stoneTex);
  const bannerRT = bakeBanner(renderer);
  owned.rt.push(floorMaps.a, floorMaps.b, stoneMaps.a, stoneMaps.b, bannerRT);

  // ---- ruins -------------------------------------------------------------------------------------------------------
  const ruins = buildRuins(rng, tier);
  const stoneMat = createStoneMaterial(U, stoneMaps);
  const ironMat = createIronMaterial(U);
  const stone = new THREE.Mesh(ruins.stone, stoneMat);
  stone.name = 'env.ruins';
  const iron = new THREE.Mesh(ruins.metal, ironMat);
  iron.name = 'env.iron';
  root.add(stone, iron);

  const floor = createFloor(U, floorMaps, stoneMaps, tier, ruins.braziers);
  root.add(floor.mesh);

  const far = createFar(U, rng, tier);
  root.add(far.far, far.clouds);

  const banners = createBanners(U, ruins.banners, bannerRT.texture);
  const fire = createFire(U, ruins.braziers, rng);
  const atmosphere = createAtmosphere(U, rng, tier);
  const particles = createParticles(U, rng, tier, ruins.braziers, floor.uniforms);
  root.add(banners, fire, atmosphere, particles);

  const sky = createSky(U, { octaves: tier.skyOctaves });
  root.add(sky);

  // ---- lights (fixed set, created once) ------------------------------------------------------------------------------
  const base = { key: 3.0, rim: 2.6, hemi: 0.65, point: 20 };
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
  // brazier lights: the first `pointLights` braziers (the +-37 degree pair in frame comes first); the rest are baked
  const points = [];
  for (let i = 0; i < tier.pointLights; i++) {
    const b = ruins.braziers[i];
    const l = new THREE.PointLight(PALETTE.fire, base.point, 16, 2);
    l.name = 'env.brazier' + i;
    l.position.set(b.x, b.y + 0.55, b.z);
    l.userData.brazier = i;
    points.push(l);
    root.add(l);
  }
  floor.setBrazierPool(ruins.braziers.map((b, i) => (points.some((p) => p.userData.brazier === i) ? 0.15 : 0.6)));

  const R = new THREE.Vector3().crossVectors(new THREE.Vector3(0, 1, 0), KEY_DIR).normalize();
  const Uc = new THREE.Vector3().crossVectors(KEY_DIR, R).normalize();
  const tmpT = new THREE.Vector3();
  let focusX = 0;
  /** Keep the shadow frustum on the fighters (texel-snapped so shadows never crawl). */
  function setFocus(x) {
    focusX = clamp(Number(x) || 0, LAYOUT.floorR * -0.8, LAYOUT.floorR * 0.8);
    U.uKeyMask.value.x = focusX;
    tmpT.set(focusX, 1.0, 0);
    const texel = sun.castShadow ? (sun.shadow.camera.right - sun.shadow.camera.left) / sun.shadow.mapSize.x : 0.01;
    const a = Math.round(tmpT.dot(R) / texel) * texel, b = Math.round(tmpT.dot(Uc) / texel) * texel, c = tmpT.dot(KEY_DIR);
    target.position.copy(R).multiplyScalar(a).addScaledVector(Uc, b).addScaledVector(KEY_DIR, c);
    sun.position.copy(target.position).addScaledVector(KEY_DIR, 22);
    rim.position.copy(target.position).addScaledVector(SUN_DIR, 22);
    target.updateMatrixWorld();
  }
  setFocus(0);

  // ---- environment map (PMREM of the sky + ring silhouette + light cards) ----------------------------------------------
  const envRT = buildEnvMap(renderer, U, ruins.braziers);
  const envMap = envRT.texture;
  owned.rt.push(envRT);
  scene.environment = envMap;
  scene.environmentIntensity = 1;
  scene.fog = new THREE.FogExp2(PALETTE.fogNear.clone(), 0.008);
  scene.background = PALETTE.zenith.clone();
  scene.add(root);

  // ---- post baseline ---------------------------------------------------------------------------------------------
  const baseline = { exposure: 1.1, vignette: 0.4, grain: 0.032, saturation: 0.94, contrast: 1.05, bloom: 0.95, bloomThreshold: 1.0, bloomKnee: 0.55, bloomRadius: 1.0, tint: new THREE.Color(1.0, 0.985, 1.0), lift: new THREE.Color(0.0025, 0.003, 0.0055) };
  if (opts.post !== false && ctx.post) ctx.post.setBaseline(baseline);

  // ---- reflection (high tier): previous frame's HDR scene, re-projected by the floor shader ------------------------------
  let refl = null;
  if (tier.reflection && ctx.post) {
    const rt = new THREE.WebGLRenderTarget(4, 4, { type: THREE.HalfFloatType, generateMipmaps: true, minFilter: THREE.LinearMipmapLinearFilter, magFilter: THREE.LinearFilter, depthBuffer: false });
    const mat = new THREE.ShaderMaterial({ vertexShader: 'varying vec2 vUv; void main() { vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }', fragmentShader: COPY_FRAG, uniforms: { tSrc: { value: null } }, depthTest: false, depthWrite: false });
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(new Float32Array([-1, -1, 0, 3, -1, 0, -1, 3, 0]), 3));
    g.setAttribute('uv', new THREE.BufferAttribute(new Float32Array([0, 0, 2, 0, 0, 2]), 2));
    const q = new THREE.Mesh(g, mat);
    q.frustumCulled = false;
    const qs = new THREE.Scene();
    qs.add(q);
    refl = { rt, mat, g, qs, cam: new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1), vp: new THREE.Matrix4(), valid: false };
    owned.rt.push(rt); owned.mat.add(mat); owned.geo.add(g);
    floor.uniforms.tRefl.value = rt.texture;
  }
  const vpNow = new THREE.Matrix4();
  /** Copy the last rendered HDR frame for the puddle reflection (automatic each frame; `renderFirst` for tests). */
  function captureReflection(renderFirst = false) {
    if (!refl) return;
    const cam = ctx.camera;
    if (renderFirst) { ctx.resize(); ctx.post.render(scene, cam); refl.valid = true; }
    const src = ctx.post.sceneTarget;
    if (!src || !refl.valid) { floor.uniforms.uWet.value.w = 0; }
    else {
      const w = Math.max(2, src.width >> 1), h = Math.max(2, src.height >> 1);
      if (refl.rt.width !== w || refl.rt.height !== h) refl.rt.setSize(w, h);
      refl.mat.uniforms.tSrc.value = src.texture;
      const prev = renderer.getRenderTarget();
      renderer.setRenderTarget(refl.rt);
      renderer.render(refl.qs, refl.cam);
      renderer.setRenderTarget(prev);
      floor.uniforms.uReflVP.value.copy(refl.vp);
      floor.uniforms.uWet.value.w = 1;
    }
    cam.updateMatrixWorld();
    vpNow.multiplyMatrices(cam.projectionMatrix, cam.matrixWorldInverse);
    refl.vp.copy(vpNow);
    refl.valid = true;
  }

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
    scene.fog.color.copy(PALETTE.fogNear).multiply(tmpC.copy(white).lerp(mood.tint, d)).multiplyScalar(1 - 0.86 * d);
    if (refl) captureReflection(false);
  }
  const off = ctx.onUpdate(update, ctx.ORDER.ENV);

  const env = {
    root, tier, uniforms: U,
    envMap, sun, rim, hemi, points,
    bounds: { minX: -9, maxX: 9 },
    floorY: 0,
    /** unit vector toward the eclipse (also the rim light direction) */
    sunDir: SUN_DIR.clone(),
    /** unit vector toward the key light */
    keyDir: KEY_DIR.clone(),
    /** ambient wind, m/s (match smoke / cloth drift to it) */
    wind: WIND.clone(),
    /** brazier bowl centres (world) */
    braziers: ruins.braziers.map((b) => b.clone()),
    baseline,
    get focusX() { return focusX; },
    get mood() { return { darken: mood.d, tint: mood.tint.clone() }; },
    setFocus, setMood, pulse, captureReflection, update,
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
        calls += 1;
        tris += (n / 3) * inst;
      });
      return { calls: calls + (refl ? 1 : 0), tris: Math.round(tris), tier: tier.detail, pointLights: points.length };
    },
    dispose() {
      off();
      scene.remove(root);
      if (scene.environment === envMap) scene.environment = null;
      root.traverse((o) => { if (o.geometry) owned.geo.add(o.geometry); if (o.material) owned.mat.add(o.material); });
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

/** PMREM environment: the sky in env mode, a dark broken ring + wet floor for metals to reflect, a few light cards. */
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
    const gapK = Math.abs(th) < LAYOUT.gap ? 0.15 : 1;
    const h = y > 0 ? (3 + 7 * gapK * (0.6 + 0.4 * Math.sin(th * 11) * Math.sin(th * 5.3))) : 0;
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
