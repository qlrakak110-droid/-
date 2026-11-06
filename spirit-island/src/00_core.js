// ============================================================================
//  존재와 공허 — core: renderer, post-processing, math, tweens, input, audio
// ============================================================================
import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js';
import { GTAOPass } from 'three/addons/postprocessing/GTAOPass.js';
import { mergeVertices, mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

const $ = (s) => document.querySelector(s);
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const lerp = (a, b, t) => a + (b - a) * t;
const smooth = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
const rand = (a, b) => a + Math.random() * (b - a);
const randi = (a, b) => Math.floor(rand(a, b + 1));
const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const damp = (a, b, l, dt) => lerp(a, b, 1 - Math.exp(-l * dt));
const angDiff = (a, b) => { let d = (b - a) % (Math.PI * 2); if (d > Math.PI) d -= Math.PI * 2; if (d < -Math.PI) d += Math.PI * 2; return d; };
const dampAngle = (a, b, l, dt) => a + angDiff(a, b) * (1 - Math.exp(-l * dt));
const ease = {
  lin: (k) => k,
  inOut: (k) => (k < 0.5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2),
  out: (k) => 1 - Math.pow(1 - k, 3),
  in: (k) => k * k * k,
  back: (k) => { const c = 1.70158; return 1 + (c + 1) * Math.pow(k - 1, 3) + c * Math.pow(k - 1, 2); },
};

function mulberry32(a) {
  return function () {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
function hash2(x, y) {
  let h = (Math.imul(x | 0, 374761393) + Math.imul(y | 0, 668265263)) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  h ^= h >>> 16;
  return (h >>> 0) / 4294967296;
}
function vnoise(x, y) {
  const xi = Math.floor(x), yi = Math.floor(y), xf = x - xi, yf = y - yi;
  const u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf);
  return lerp(lerp(hash2(xi, yi), hash2(xi + 1, yi), u), lerp(hash2(xi, yi + 1), hash2(xi + 1, yi + 1), u), v);
}
function fbm(x, y, o = 4) { let s = 0, a = 0.5, f = 1; for (let i = 0; i < o; i++) { s += a * vnoise(x * f, y * f); f *= 2.03; a *= 0.5; } return s; }

// ---------------------------------------------------------------- settings
const isTouch = (matchMedia('(pointer: coarse)').matches || 'ontouchstart' in window);
const Settings = { high: !isTouch || Math.min(screen.width, screen.height) > 700, ultra: !isTouch, sound: true };
try { const s = JSON.parse(localStorage.getItem('void-being-settings') || 'null'); if (s) Object.assign(Settings, s); } catch (e) {}
function saveSettings() { try { localStorage.setItem('void-being-settings', JSON.stringify(Settings)); } catch (e) {} }

// ---------------------------------------------------------------- renderer
const canvas = $('#gl');
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, powerPreference: 'high-performance' });
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.0;
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;

// multisampled HDR target so the post-processed image keeps clean edges
const composer = new EffectComposer(renderer, new THREE.WebGLRenderTarget(4, 4, { type: THREE.HalfFloatType, samples: isTouch ? 2 : 4 }));
const renderPass = new RenderPass(new THREE.Scene(), new THREE.PerspectiveCamera());
composer.addPass(renderPass);
// ground-truth ambient occlusion (ultra tier): contact shadows and crevices, computed at half resolution
const aoCam = new THREE.PerspectiveCamera(50, 1, 0.1, 1600);
const gtaoPass = new GTAOPass(new THREE.Scene(), aoCam, 256, 256, undefined, { radius: 0.9, distanceExponent: 1.4, thickness: 1.2, scale: 1.15, samples: 12, distanceFallOff: 1, screenSpaceRadius: false }, { lumaPhi: 10, depthPhi: 2, normalPhi: 3, radius: 6, rings: 2, samples: 12 });
gtaoPass.blendIntensity = 0.85;
{
  const setSz = gtaoPass.setSize.bind(gtaoPass);
  gtaoPass.setSize = (w, h) => setSz(Math.max(1, Math.floor(w / 2)), Math.max(1, Math.floor(h / 2)));
  gtaoPass.overrideVisibility = function () {
    const cache = this._visibilityCache;
    this.scene.traverse((o) => { cache.set(o, o.visible); if (o.isPoints || o.isLine || o.isSprite || (o.material && (o.material.transparent || o.material.userData.noAO || o.material.isShaderMaterial && !o.material.userData.ao))) o.visible = false; });
  };
}
composer.addPass(gtaoPass);
const bloomPass = new UnrealBloomPass(new THREE.Vector2(256, 256), 0.8, 0.55, 0.86);
composer.addPass(bloomPass);
composer.addPass(new OutputPass());

// final cinematic pass (display space): shockwave ripple, chromatic aberration, sun shafts, grade, vignette, grain
const Post = {
  U: {
    tDiffuse: { value: null }, uTime: { value: 0 }, uRes: { value: new THREE.Vector2(1, 1) },
    uVig: { value: 0.34 }, uCA: { value: 0 }, uGrain: { value: 0.03 }, uSat: { value: 1.1 }, uLift: { value: new THREE.Vector3(0.012, 0.0, 0.035) },
    uShock: { value: new THREE.Vector4(0.5, 0.5, -1, 0) }, uSun: { value: new THREE.Vector3(0.5, 0.5, 0) }, uTint: { value: new THREE.Vector3(1, 1, 1) },
  },
  shockT: -1, shockAmp: 0, caKick: 0,
  shock(world, cam, amp = 1) {
    const v = world.clone().project(cam);
    this.U.uShock.value.set((v.x + 1) / 2, (v.y + 1) / 2, 0, amp); this.shockT = 0; this.shockAmp = amp;
  },
  kick(ca = 0.02) { this.caKick = Math.max(this.caKick, ca); },
  update(dt) {
    this.U.uTime.value += dt;
    if (this.shockT >= 0) { this.shockT += dt * 1.25; if (this.shockT >= 1) { this.shockT = -1; this.U.uShock.value.z = -1; } else this.U.uShock.value.z = this.shockT; }
    this.caKick = Math.max(0, this.caKick - dt * 0.08);
    this.U.uCA.value = this.caKick;
  },
};
const finalPass = new ShaderPass(new THREE.ShaderMaterial({
  uniforms: Post.U,
  vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }',
  fragmentShader: `uniform sampler2D tDiffuse; uniform float uTime, uVig, uCA, uGrain, uSat; uniform vec2 uRes; uniform vec4 uShock; uniform vec3 uSun, uLift, uTint; varying vec2 vUv;
    void main(){
      vec2 uv = vUv;
      if (uShock.z >= 0.0) {
        vec2 d = uv - uShock.xy; d.x *= uRes.x / uRes.y; float r = length(d);
        float band = smoothstep(0.11, 0.0, abs(r - uShock.z * 0.9)) * (1.0 - uShock.z);
        uv -= normalize(uv - uShock.xy + 1e-5) * band * uShock.w * 0.035;
      }
      vec2 c = uv - 0.5;
      float ca = uCA + 0.0018 * dot(c, c) * 4.0;
      vec3 col = vec3(texture2D(tDiffuse, uv + c * ca).r, texture2D(tDiffuse, uv).g, texture2D(tDiffuse, uv - c * ca).b);
      if (uSun.z > 0.001) {
        vec2 dl = (uv - uSun.xy) / 30.0; vec2 sp = uv; float decay = 1.0; vec3 acc = vec3(0.0);
        for (int i = 0; i < 30; i++) { sp -= dl; vec3 s = texture2D(tDiffuse, clamp(sp, 0.001, 0.999)).rgb; float l = max(dot(s, vec3(0.299, 0.587, 0.114)) - 0.7, 0.0); acc += s * l * decay; decay *= 0.935; }
        col += acc * uSun.z * 0.075 * vec3(1.0, 0.86, 0.7);
      }
      float lum = dot(col, vec3(0.299, 0.587, 0.114));
      col = mix(vec3(lum), col, uSat);
      col = col + uLift * (1.0 - col);
      col *= uTint;
      float v = smoothstep(0.95, 0.25, length(c * vec2(1.0, 0.9)));
      col *= mix(1.0 - uVig, 1.0, v);
      float g = fract(sin(dot(vUv * uRes + fract(uTime) * 61.0, vec2(12.9898, 78.233))) * 43758.5453);
      col += (g - 0.5) * uGrain;
      gl_FragColor = vec4(col, 1.0);
    }`,
}));
composer.addPass(finalPass);

function applyQuality() {
  const dpr = window.devicePixelRatio || 1;
  renderer.setPixelRatio(Math.min(dpr, Settings.high ? (isTouch ? 1.75 : 2) : 1));
  renderer.shadowMap.enabled = Settings.high || !isTouch;
  composer.setPixelRatio(renderer.getPixelRatio());
  onResize();
}
function onResize() {
  const w = window.innerWidth, h = window.innerHeight;
  renderer.setSize(w, h, false);
  composer.setSize(w, h);
  bloomPass.resolution.set(w, h);
  Post.U.uRes.value.set(w * renderer.getPixelRatio(), h * renderer.getPixelRatio());
  for (const c of Cams) { c.aspect = w / h; c.updateProjectionMatrix(); }
}
const Cams = [];
window.addEventListener('resize', onResize);

function renderScene(scene, camera) {
  if (Settings.high) {
    renderPass.scene = scene; renderPass.camera = camera;
    gtaoPass.enabled = !!Settings.ultra;
    if (gtaoPass.enabled) { gtaoPass.scene = scene; gtaoPass.camera = camera; }
    composer.render();
  } else {
    renderer.render(scene, camera);
  }
}

// game-time scale: hit-stop freezes and slow motion for cinematic beats
const Time = { scale: 1, stopUntil: 0, slow: 0.05 };
function hitStop(sec, slow = 0.04) { Time.stopUntil = performance.now() + sec * 1000; Time.slow = slow; }
function timeScale() { return performance.now() < Time.stopUntil ? Time.slow : Time.scale; }

// ---------------------------------------------------------------- tweens (game-time)
const Tw = {
  list: [],
  add(dur, fn, e = ease.inOut) {
    return new Promise((res) => { this.list.push({ t: 0, dur: Math.max(dur, 1e-4), fn, e, res }); });
  },
  update(dt) {
    const L = this.list;
    for (let i = L.length - 1; i >= 0; i--) {
      const w = L[i]; if (!w) continue;
      w.t += dt;
      const k = Math.min(w.t / w.dur, 1);
      try { w.fn(w.e(k), k); } catch (err) { console.error(err); }
      if (k >= 1) { L.splice(i, 1); w.res(); }
    }
  },
};
const wait = (s) => Tw.add(s, () => {});

// ---------------------------------------------------------------- materials & geometry kit
const toonGrad = (() => {
  const d = new Uint8Array([70, 150, 215, 255]);
  const t = new THREE.DataTexture(d, 4, 1, THREE.RedFormat);
  t.minFilter = t.magFilter = THREE.NearestFilter; t.needsUpdate = true; return t;
})();
const Look = { rim: { value: new THREE.Color(0xbcd4ff) }, rimStr: { value: 0.45 }, spec: { value: 0.55 } };
function setLook(rim, str = 0.55) { Look.rim.value.set(rim); Look.rimStr.value = str; }
function patchToon(m) {
  m.onBeforeCompile = (sh) => {
    sh.uniforms.uRim = Look.rim; sh.uniforms.uRimStr = Look.rimStr; sh.uniforms.uSpec = Look.spec;
    sh.fragmentShader = 'uniform vec3 uRim; uniform float uRimStr; uniform float uSpec;\n' + sh.fragmentShader.replace('#include <opaque_fragment>', `
      {
        vec3 vdir = normalize(vViewPosition);
        float fr = pow(1.0 - clamp(dot(normal, vdir), 0.0, 1.0), 3.0);
        outgoingLight += uRim * fr * uRimStr * (0.55 + 0.45 * diffuseColor.rgb);
        #if NUM_DIR_LIGHTS > 0
          vec3 hv = normalize(directionalLights[0].direction + vdir);
          float sp = smoothstep(0.962, 0.978, dot(normal, hv));
          outgoingLight += directionalLights[0].color * sp * uSpec * 0.35;
        #endif
      }
      #include <opaque_fragment>`);
  };
  m.customProgramCacheKey = () => 'toonRim1';
  return m;
}
function toonMat(o) { return patchToon(new THREE.MeshToonMaterial(Object.assign({ gradientMap: toonGrad }, o))); }
const _mc = new Map();
function M(color, extra) {
  const k = 't' + color + (extra ? JSON.stringify(extra) : '');
  if (!_mc.has(k)) _mc.set(k, toonMat(Object.assign({ color }, extra || {})));
  return _mc.get(k);
}
function E(color, intensity = 2.5, extra) {
  const k = 'e' + color + '_' + intensity + (extra ? JSON.stringify(extra) : '');
  if (!_mc.has(k)) _mc.set(k, new THREE.MeshBasicMaterial(Object.assign({ color: new THREE.Color(color).multiplyScalar(intensity) }, extra || {})));
  return _mc.get(k);
}
const FOG_V = '\n#include <fog_pars_vertex>\n';
const FOG_F = '\n#include <fog_pars_fragment>\n';

// black body with luminous rim — used by everything that belongs to the Void
function voidMat(rim = 0xb055ff, power = 2.6, base = 0x05030a, rimI = 2.4) {
  const k = 'v' + rim + '_' + power + '_' + base + '_' + rimI;
  if (_mc.has(k)) return _mc.get(k);
  const m = new THREE.ShaderMaterial({
    uniforms: THREE.UniformsUtils.merge([THREE.UniformsLib.fog, {
      uRim: { value: new THREE.Color(rim).multiplyScalar(rimI) }, uBase: { value: new THREE.Color(base) }, uPow: { value: power }, uTime: Shared.time,
    }]),
    vertexShader: `varying vec3 vN; varying vec3 vV; varying vec3 vW;
      ${FOG_V}
      void main(){
        vec4 mvPosition = modelViewMatrix * vec4(position,1.0);
        vN = normalize(normalMatrix * normal); vV = normalize(-mvPosition.xyz);
        vW = (modelMatrix * vec4(position,1.0)).xyz;
        gl_Position = projectionMatrix * mvPosition;
        #include <fog_vertex>
      }`,
    fragmentShader: `uniform vec3 uRim; uniform vec3 uBase; uniform float uPow; uniform float uTime;
      varying vec3 vN; varying vec3 vV; varying vec3 vW;
      ${FOG_F}
      void main(){
        float f = pow(1.0 - max(dot(normalize(vN), normalize(vV)), 0.0), uPow);
        float vein = smoothstep(0.93, 1.0, sin(vW.y*7.0 + sin(vW.x*5.0+uTime*0.9)*1.6 + uTime*0.6));
        vec3 c = uBase + uRim * (f + vein*0.18);
        gl_FragColor = vec4(c, 1.0);
        #include <fog_fragment>
      }`,
    fog: true,
  });
  m.uniforms.uTime = Shared.time;
  _mc.set(k, m); return m;
}

// inverted-hull outline material, cached per thickness
const _olm = new Map();
function outlineMat(th, color = 0x150d22) {
  const k = Math.round(th * 400) + '_' + color;
  if (_olm.has(k)) return _olm.get(k);
  const m = new THREE.ShaderMaterial({
    uniforms: THREE.UniformsUtils.merge([THREE.UniformsLib.fog, { uThick: { value: Math.round(th * 400) / 400 }, uColor: { value: new THREE.Color(color) } }]),
    vertexShader: `uniform float uThick;
      ${FOG_V}
      void main(){
        vec3 p = position + normal * uThick;
        vec4 mvPosition = modelViewMatrix * vec4(p,1.0);
        gl_Position = projectionMatrix * mvPosition;
        #include <fog_vertex>
      }`,
    fragmentShader: `uniform vec3 uColor;
      ${FOG_F}
      void main(){ gl_FragColor = vec4(uColor,1.0);
        #include <fog_fragment>
      }`,
    side: THREE.BackSide, fog: true,
  });
  _olm.set(k, m); return m;
}
const _smoothGeo = new Map();
function smoothGeo(g) {
  if (_smoothGeo.has(g.uuid)) return _smoothGeo.get(g.uuid);
  let s = g.clone(); s.deleteAttribute('normal'); if (s.attributes.uv) s.deleteAttribute('uv');
  s = mergeVertices(s, 1e-3); s.computeVertexNormals();
  _smoothGeo.set(g.uuid, s); return s;
}
// add outlines to every opaque toon mesh under root; `w` = outline width in root units
function addOutlines(root, w = 0.035, color) {
  const list = [];
  root.traverse((o) => { if (o.isMesh && !o.userData.noOl && !o.userData.isOl && o.material && o.material.isMeshToonMaterial && !o.material.transparent) list.push(o); });
  for (const o of list) {
    const s = (Math.abs(o.scale.x) + Math.abs(o.scale.y) + Math.abs(o.scale.z)) / 3 || 1;
    const geo = o.geometry.userData.flat ? smoothGeo(o.geometry) : o.geometry;
    const ol = new THREE.Mesh(geo, outlineMat(w / s, color));
    ol.userData.isOl = true; ol.castShadow = false; ol.raycast = () => {};
    o.add(ol);
  }
}

const GEO = {
  sphere: new THREE.SphereGeometry(1, 28, 20),
  sphereLo: new THREE.SphereGeometry(1, 12, 9),
  hemi: new THREE.SphereGeometry(1, 28, 14, 0, Math.PI * 2, 0, Math.PI / 2),
  cone: new THREE.ConeGeometry(1, 1, 20),
  cone4: new THREE.ConeGeometry(1, 1, 4),
  cone6: new THREE.ConeGeometry(1, 1, 6),
  cyl: new THREE.CylinderGeometry(1, 1, 1, 18),
  cylT: new THREE.CylinderGeometry(0.7, 1, 1, 14),
  box: new THREE.BoxGeometry(1, 1, 1),
  torus: new THREE.TorusGeometry(1, 0.06, 10, 64),
  ring: new THREE.TorusGeometry(1, 0.012, 6, 160),
  torusFat: new THREE.TorusGeometry(1, 0.22, 14, 40),
  ico: new THREE.IcosahedronGeometry(1, 0),
  ico1: new THREE.IcosahedronGeometry(1, 1),
  dodeca: new THREE.DodecahedronGeometry(1, 0),
  octa: new THREE.OctahedronGeometry(1, 0),
  tetra: new THREE.TetrahedronGeometry(1, 0),
  capsule: new THREE.CapsuleGeometry(0.5, 1, 6, 16),
  plane: new THREE.PlaneGeometry(1, 1),
  circle: new THREE.CircleGeometry(1, 48),
};
for (const k of ['ico', 'ico1', 'dodeca', 'octa', 'tetra', 'cone4', 'cone6']) GEO[k].userData.flat = true;

function part(geo, mat, parent, pos = [0, 0, 0], scl = 1, rot = [0, 0, 0]) {
  const m = new THREE.Mesh(geo, mat);
  m.position.set(pos[0], pos[1], pos[2]);
  if (Array.isArray(scl)) m.scale.set(scl[0], scl[1], scl[2]); else m.scale.setScalar(scl);
  m.rotation.set(rot[0], rot[1], rot[2]);
  m.castShadow = !(mat && (mat.isMeshBasicMaterial || mat.transparent));
  parent.add(m);
  return m;
}
function grp(parent, pos = [0, 0, 0], rot = [0, 0, 0]) {
  const g = new THREE.Group(); g.position.set(pos[0], pos[1], pos[2]); g.rotation.set(rot[0], rot[1], rot[2]);
  if (parent) parent.add(g); return g;
}

// shared time uniform for every animated shader
const Shared = { time: { value: 0 } };

// soft round sprite texture (particles, glows, clouds)
function makeSpriteTex(kind = 'dot') {
  const c = document.createElement('canvas'); c.width = c.height = 128;
  const g = c.getContext('2d');
  if (kind === 'cloud') {
    for (let i = 0; i < 14; i++) {
      const x = 30 + Math.random() * 68, y = 50 + Math.random() * 28, r = 18 + Math.random() * 26;
      const gr = g.createRadialGradient(x, y, 0, x, y, r);
      gr.addColorStop(0, 'rgba(255,255,255,.55)'); gr.addColorStop(1, 'rgba(255,255,255,0)');
      g.fillStyle = gr; g.beginPath(); g.arc(x, y, r, 0, 7); g.fill();
    }
  } else {
    const gr = g.createRadialGradient(64, 64, 0, 64, 64, 64);
    gr.addColorStop(0, 'rgba(255,255,255,1)'); gr.addColorStop(0.25, 'rgba(255,255,255,.75)');
    gr.addColorStop(0.6, 'rgba(255,255,255,.12)'); gr.addColorStop(1, 'rgba(255,255,255,0)');
    g.fillStyle = gr; g.fillRect(0, 0, 128, 128);
  }
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return t;
}
const TEX = { dot: makeSpriteTex('dot'), cloud: makeSpriteTex('cloud') };

// ---------------------------------------------------------------- CPU particle system (bursts, trails, sparkles)
class Particles {
  constructor(scene, max = 2400) {
    this.max = max; this.n = 0; this.p = [];
    const g = new THREE.BufferGeometry();
    this.pos = new Float32Array(max * 3); this.col = new Float32Array(max * 3); this.size = new Float32Array(max); this.alpha = new Float32Array(max);
    g.setAttribute('position', new THREE.BufferAttribute(this.pos, 3).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('color', new THREE.BufferAttribute(this.col, 3).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('size', new THREE.BufferAttribute(this.size, 1).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('alpha', new THREE.BufferAttribute(this.alpha, 1).setUsage(THREE.DynamicDrawUsage));
    const m = new THREE.ShaderMaterial({
      uniforms: { uTex: { value: TEX.dot }, uScale: { value: 1 } },
      vertexShader: `attribute float size; attribute float alpha; attribute vec3 color; varying vec3 vC; varying float vA; uniform float uScale;
        void main(){ vC = color; vA = alpha; vec4 mv = modelViewMatrix * vec4(position,1.0);
          gl_PointSize = size * uScale * (300.0 / -mv.z); gl_Position = projectionMatrix * mv; }`,
      fragmentShader: `uniform sampler2D uTex; varying vec3 vC; varying float vA;
        void main(){ vec4 t = texture2D(uTex, gl_PointCoord); gl_FragColor = vec4(vC * t.a * vA, 1.0); }`,
      blending: THREE.AdditiveBlending, depthWrite: false, transparent: true,
    });
    this.points = new THREE.Points(g, m); this.points.frustumCulled = false; this.points.renderOrder = 10;
    scene.add(this.points);
  }
  emit(o) {
    if (this.p.length >= this.max) this.p.shift();
    const c = new THREE.Color(o.color ?? 0xffffff).multiplyScalar(o.intensity ?? 1.6);
    this.p.push({
      x: o.x, y: o.y, z: o.z, vx: o.vx || 0, vy: o.vy || 0, vz: o.vz || 0,
      life: 0, max: o.life || 1, size: o.size || 0.3, endSize: o.endSize ?? 0, r: c.r, g: c.g, b: c.b,
      grav: o.grav || 0, drag: o.drag ?? 1.5, to: o.to || null, toK: o.toK || 0,
    });
  }
  burst(at, n, o = {}) {
    for (let i = 0; i < n; i++) {
      const th = Math.random() * Math.PI * 2, ph = Math.acos(rand(-1, 1)), sp = rand(o.speedMin ?? 1, o.speed ?? 5);
      const dx = Math.sin(ph) * Math.cos(th), dy = Math.cos(ph), dz = Math.sin(ph) * Math.sin(th);
      this.emit(Object.assign({}, o, {
        x: at.x + dx * (o.spread || 0), y: at.y + dy * (o.spread || 0) * (o.flat ? 0.2 : 1), z: at.z + dz * (o.spread || 0),
        vx: dx * sp, vy: (o.flat ? Math.abs(dy) * 0.3 : dy) * sp + (o.up || 0), vz: dz * sp,
        life: rand((o.life || 1) * 0.6, o.life || 1), size: rand((o.size || 0.3) * 0.6, o.size || 0.3),
        color: Array.isArray(o.color) ? pick(o.color) : o.color,
      }));
    }
  }
  update(dt) {
    const P = this.p;
    for (let i = P.length - 1; i >= 0; i--) {
      const q = P[i]; q.life += dt;
      if (q.life >= q.max) { P.splice(i, 1); continue; }
      const dr = Math.exp(-q.drag * dt);
      q.vx *= dr; q.vy *= dr; q.vz *= dr; q.vy -= q.grav * dt;
      if (q.to) { q.vx += (q.to.x - q.x) * q.toK * dt; q.vy += (q.to.y - q.y) * q.toK * dt; q.vz += (q.to.z - q.z) * q.toK * dt; }
      q.x += q.vx * dt; q.y += q.vy * dt; q.z += q.vz * dt;
    }
    const n = Math.min(P.length, this.max);
    for (let i = 0; i < n; i++) {
      const q = P[i], k = q.life / q.max;
      this.pos[i * 3] = q.x; this.pos[i * 3 + 1] = q.y; this.pos[i * 3 + 2] = q.z;
      this.col[i * 3] = q.r; this.col[i * 3 + 1] = q.g; this.col[i * 3 + 2] = q.b;
      this.size[i] = lerp(q.size, q.endSize, k);
      this.alpha[i] = k < 0.15 ? k / 0.15 : 1 - smooth(0.5, 1, k);
    }
    const g = this.points.geometry; g.setDrawRange(0, n);
    for (const a of ['position', 'color', 'size', 'alpha']) g.attributes[a].needsUpdate = true;
  }
  clear() { this.p.length = 0; }
}

// ---------------------------------------------------------------- input
const Input = {
  keys: {}, joy: { x: 0, y: 0, active: false }, runToggle: false, actionQueued: false, waiters: [],
  dragDX: 0, zoom: 0,
  axis() {
    let x = 0, y = 0; const k = this.keys;
    if (k.KeyA || k.ArrowLeft) x -= 1; if (k.KeyD || k.ArrowRight) x += 1;
    if (k.KeyW || k.ArrowUp) y += 1; if (k.KeyS || k.ArrowDown) y -= 1;
    if (this.joy.active) { x = this.joy.x; y = this.joy.y; }
    const l = Math.hypot(x, y); if (l > 1) { x /= l; y /= l; }
    return { x, y, run: !!(k.ShiftLeft || k.ShiftRight) || this.runToggle };
  },
};
function nextAction() { return new Promise((r) => Input.waiters.push(r)); }
function fireAction() {
  if (Input.waiters.length) { const w = Input.waiters; Input.waiters = []; w.forEach((f) => f()); return; }
  Input.actionQueued = true;
}
window.addEventListener('keydown', (e) => {
  const ae = document.activeElement;
  const onButton = ae && ae.tagName === 'BUTTON' && ae !== canvas;
  if ((e.code === 'Space' || e.code === 'Enter') && onButton) return; // native click handles it
  Input.keys[e.code] = true;
  if (!e.repeat && (e.code === 'KeyE' || e.code === 'Space' || e.code === 'Enter' || e.code === 'KeyZ')) { fireAction(); e.preventDefault(); }
  if (['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Space'].includes(e.code)) e.preventDefault();
  if (!e.repeat && typeof onHotkey === 'function') onHotkey(e.code);
});
window.addEventListener('keyup', (e) => { Input.keys[e.code] = false; });
window.addEventListener('blur', () => { Input.keys = {}; });

// camera drag (mouse or a finger outside the joystick) + wheel/pinch zoom
(function setupDrag() {
  let dragId = null, lastX = 0;
  const pinch = new Map(); let pinchD = 0;
  canvas.addEventListener('pointerdown', (e) => {
    canvas.focus({ preventScroll: true });
    if (e.pointerType === 'touch') {
      pinch.set(e.pointerId, { x: e.clientX, y: e.clientY });
      if (pinch.size === 2) { const [a, b] = [...pinch.values()]; pinchD = Math.hypot(a.x - b.x, a.y - b.y); dragId = null; return; }
    }
    dragId = e.pointerId; lastX = e.clientX;
  });
  window.addEventListener('pointermove', (e) => {
    if (pinch.has(e.pointerId)) {
      pinch.set(e.pointerId, { x: e.clientX, y: e.clientY });
      if (pinch.size === 2) { const [a, b] = [...pinch.values()]; const d = Math.hypot(a.x - b.x, a.y - b.y); Input.zoom += (pinchD - d) * 0.03; pinchD = d; return; }
    }
    if (e.pointerId !== dragId) return;
    Input.dragDX += e.clientX - lastX; lastX = e.clientX;
  });
  const up = (e) => { pinch.delete(e.pointerId); if (e.pointerId === dragId) dragId = null; };
  window.addEventListener('pointerup', up); window.addEventListener('pointercancel', up);
  canvas.addEventListener('wheel', (e) => { Input.zoom += Math.sign(e.deltaY) * 1.2; e.preventDefault(); }, { passive: false });
})();

// virtual joystick
(function setupStick() {
  const stick = $('#stick'), knob = $('#knob');
  let id = null, cx = 0, cy = 0;
  stick.addEventListener('pointerdown', (e) => {
    id = e.pointerId; const r = stick.getBoundingClientRect(); cx = r.left + r.width / 2; cy = r.top + r.height / 2;
    stick.setPointerCapture(id); move(e); e.preventDefault();
  });
  const move = (e) => {
    if (e.pointerId !== id) return;
    let dx = e.clientX - cx, dy = e.clientY - cy; const R = 52, l = Math.hypot(dx, dy);
    if (l > R) { dx = dx / l * R; dy = dy / l * R; }
    knob.style.transform = `translate(${dx}px,${dy}px)`;
    Input.joy.x = dx / R; Input.joy.y = -dy / R; Input.joy.active = true;
  };
  stick.addEventListener('pointermove', move);
  const end = (e) => { if (e.pointerId !== id) return; id = null; knob.style.transform = ''; Input.joy.active = false; Input.joy.x = Input.joy.y = 0; };
  stick.addEventListener('pointerup', end); stick.addEventListener('pointercancel', end);
  $('#tA').addEventListener('pointerdown', (e) => { e.preventDefault(); fireAction(); });
  $('#tRun').addEventListener('click', () => { Input.runToggle = !Input.runToggle; $('#tRun').classList.toggle('on', Input.runToggle); });
})();

// ---------------------------------------------------------------- audio: tiny synth + sequencer
const Snd = {
  ctx: null, master: null, music: null, sfx: null, verb: null, song: null, step: 0, nextT: 0, timer: null,
  init() {
    if (this.ctx) { if (this.ctx.state === 'suspended') this.ctx.resume(); return; }
    const AC = window.AudioContext || window.webkitAudioContext; if (!AC) return;
    const c = this.ctx = new AC();
    this.master = c.createGain(); this.master.gain.value = Settings.sound ? 0.8 : 0; this.master.connect(c.destination);
    const comp = c.createDynamicsCompressor(); comp.threshold.value = -16; comp.ratio.value = 4; comp.connect(this.master);
    this.music = c.createGain(); this.music.gain.value = 0.42; this.music.connect(comp);
    this.sfx = c.createGain(); this.sfx.gain.value = 0.75; this.sfx.connect(comp);
    // reverb send
    this.verb = c.createConvolver();
    const len = c.sampleRate * 2.8, buf = c.createBuffer(2, len, c.sampleRate);
    for (let ch = 0; ch < 2; ch++) { const d = buf.getChannelData(ch); for (let i = 0; i < len; i++) d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / len, 2.6); }
    this.verb.buffer = buf;
    const vg = c.createGain(); vg.gain.value = 0.55; this.verb.connect(vg); vg.connect(comp);
    this.noiseBuf = c.createBuffer(1, c.sampleRate, c.sampleRate);
    const nd = this.noiseBuf.getChannelData(0); for (let i = 0; i < nd.length; i++) nd[i] = Math.random() * 2 - 1;
    this.timer = setInterval(() => this.tick(), 25);
  },
  setOn(on) { Settings.sound = on; saveSettings(); if (this.master) this.master.gain.setTargetAtTime(on ? 0.8 : 0, this.ctx.currentTime, 0.05); },
  mf(m) { return 440 * Math.pow(2, (m - 69) / 12); },
  env(g, t, a, peak, d, sus = 0.0001) {
    g.gain.cancelScheduledValues(t); g.gain.setValueAtTime(0.0001, t);
    g.gain.linearRampToValueAtTime(peak, t + a); g.gain.exponentialRampToValueAtTime(Math.max(sus, 0.0001), t + a + d);
  },
  voice(inst, midi, t, dur, vol = 1, out) {
    const c = this.ctx; if (!c) return; out = out || this.music;
    const f = this.mf(midi);
    const send = (node, amt) => { if (amt > 0) { const s = c.createGain(); s.gain.value = amt; node.connect(s); s.connect(this.verb); } };
    if (inst === 'pluck' || inst === 'lead') {
      const o = c.createOscillator(); o.type = inst === 'lead' ? 'square' : 'triangle'; o.frequency.value = f;
      const lp = c.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = inst === 'lead' ? 1800 : 3200;
      const g = c.createGain(); this.env(g, t, 0.006, 0.22 * vol, dur * 1.6);
      o.connect(lp); lp.connect(g); g.connect(out); send(g, 0.35); o.start(t); o.stop(t + dur * 1.8 + 0.1);
    } else if (inst === 'pad' || inst === 'choir') {
      const g = c.createGain(); const lp = c.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = inst === 'choir' ? 1500 : 900; lp.Q.value = inst === 'choir' ? 4 : 0.7;
      g.gain.setValueAtTime(0.0001, t); g.gain.linearRampToValueAtTime(0.07 * vol, t + Math.min(0.8, dur * 0.4));
      g.gain.setValueAtTime(0.07 * vol, t + dur * 0.8); g.gain.linearRampToValueAtTime(0.0001, t + dur + 0.9);
      for (const det of [-9, 0, 8]) { const o = c.createOscillator(); o.type = inst === 'choir' ? 'sawtooth' : 'sawtooth'; o.frequency.value = f; o.detune.value = det; o.connect(lp); o.start(t); o.stop(t + dur + 1); }
      lp.connect(g); g.connect(out); send(g, 0.8);
    } else if (inst === 'bass') {
      const o = c.createOscillator(); o.type = 'sawtooth'; o.frequency.value = f;
      const lp = c.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.setValueAtTime(700, t); lp.frequency.exponentialRampToValueAtTime(160, t + dur);
      const g = c.createGain(); this.env(g, t, 0.01, 0.28 * vol, dur);
      o.connect(lp); lp.connect(g); g.connect(out); o.start(t); o.stop(t + dur + 0.1);
    } else if (inst === 'bell') {
      for (const [mul, a] of [[1, 0.16], [2.76, 0.05], [5.4, 0.02]]) {
        const o = c.createOscillator(); o.type = 'sine'; o.frequency.value = f * mul;
        const g = c.createGain(); this.env(g, t, 0.004, a * vol, dur * 2.5);
        o.connect(g); g.connect(out); send(g, 0.6); o.start(t); o.stop(t + dur * 2.6 + 0.1);
      }
    } else if (inst === 'kick') {
      const o = c.createOscillator(); o.type = 'sine'; o.frequency.setValueAtTime(150, t); o.frequency.exponentialRampToValueAtTime(38, t + 0.16);
      const g = c.createGain(); this.env(g, t, 0.002, 0.8 * vol, 0.3); o.connect(g); g.connect(out); o.start(t); o.stop(t + 0.4);
    } else if (inst === 'hat' || inst === 'snare') {
      const s = c.createBufferSource(); s.buffer = this.noiseBuf;
      const hp = c.createBiquadFilter(); hp.type = inst === 'hat' ? 'highpass' : 'bandpass'; hp.frequency.value = inst === 'hat' ? 7500 : 1800;
      const g = c.createGain(); this.env(g, t, 0.001, (inst === 'hat' ? 0.09 : 0.3) * vol, inst === 'hat' ? 0.05 : 0.16);
      s.connect(hp); hp.connect(g); g.connect(out); if (inst === 'snare') send(g, 0.3); s.start(t); s.stop(t + 0.3);
    } else if (inst === 'timp') {
      const o = c.createOscillator(); o.type = 'sine'; o.frequency.setValueAtTime(f * 1.5, t); o.frequency.exponentialRampToValueAtTime(f, t + 0.08);
      const g = c.createGain(); this.env(g, t, 0.004, 0.55 * vol, 1.4); o.connect(g); g.connect(out); send(g, 0.5); o.start(t); o.stop(t + 1.6);
    }
  },
  play(name) {
    if (!this.ctx) return;
    if (this.song && this.song.name === name) return;
    const next = SONGS[name]; if (!next) return;
    this.music.gain.cancelScheduledValues(this.ctx.currentTime);
    this.music.gain.setValueAtTime(0.0, this.ctx.currentTime);
    this.music.gain.linearRampToValueAtTime(0.42, this.ctx.currentTime + 1.2);
    this.song = Object.assign({ name }, next); this.step = 0; this.nextT = this.ctx.currentTime + 0.12;
  },
  stop() { this.song = null; },
  tick() {
    const c = this.ctx; if (!c || !this.song) return;
    const s = this.song, spb = 60 / s.bpm / 4;
    while (this.nextT < c.currentTime + 0.14) {
      s.seq(this.step, this.nextT, spb, (inst, m, d, v) => this.voice(inst, m, this.nextT, d, v));
      this.step++; this.nextT += spb;
      if (s.once && this.step >= s.len) { this.song = null; if (s.then) this.play(s.then); return; }
    }
  },
  // one-shot effects
  fx(name, opt = {}) {
    const c = this.ctx; if (!c) return; const t = c.currentTime + 0.01; const o = this.sfx;
    const tone = (type, f0, f1, dur, vol, at = 0) => {
      const os = c.createOscillator(); os.type = type; os.frequency.setValueAtTime(f0, t + at); os.frequency.exponentialRampToValueAtTime(Math.max(f1, 1), t + at + dur);
      const g = c.createGain(); this.env(g, t + at, 0.005, vol, dur); os.connect(g); g.connect(o); os.start(t + at); os.stop(t + at + dur + 0.05);
      const sg = c.createGain(); sg.gain.value = 0.25; g.connect(sg); sg.connect(this.verb);
    };
    const noise = (f0, f1, dur, vol, type = 'bandpass', at = 0, q = 1) => {
      const s = c.createBufferSource(); s.buffer = this.noiseBuf;
      const bf = c.createBiquadFilter(); bf.type = type; bf.Q.value = q; bf.frequency.setValueAtTime(f0, t + at); bf.frequency.exponentialRampToValueAtTime(Math.max(f1, 20), t + at + dur);
      const g = c.createGain(); this.env(g, t + at, 0.01, vol, dur); s.connect(bf); bf.connect(g); g.connect(o); s.start(t + at); s.stop(t + at + dur + 0.05);
    };
    switch (name) {
      case 'select': tone('triangle', 880, 990, 0.06, 0.18); break;
      case 'confirm': tone('triangle', 660, 660, 0.07, 0.2); tone('triangle', 990, 990, 0.12, 0.2, 0.07); break;
      case 'back': tone('triangle', 660, 440, 0.1, 0.16); break;
      case 'talk': tone('square', 520 + Math.random() * 80, 500, 0.025, 0.035); break;
      case 'hit': noise(2400, 300, 0.22, 0.6); tone('square', 180, 60, 0.15, 0.25); break;
      case 'crit': noise(4000, 200, 0.35, 0.8); tone('sawtooth', 300, 40, 0.3, 0.3); break;
      case 'weak': noise(1200, 400, 0.15, 0.35); break;
      case 'whoosh': noise(400, 3000, 0.28, 0.35, 'bandpass', 0, 2); break;
      case 'fire': noise(800, 200, 0.5, 0.5, 'lowpass'); noise(3000, 1200, 0.4, 0.2); break;
      case 'water': noise(600, 2400, 0.45, 0.4, 'bandpass', 0, 3); tone('sine', 300, 900, 0.3, 0.12); break;
      case 'grass': noise(3000, 6000, 0.3, 0.25, 'highpass'); tone('triangle', 700, 1100, 0.2, 0.08); break;
      case 'thunder': noise(5000, 100, 0.6, 0.7, 'lowpass'); tone('sawtooth', 90, 40, 0.5, 0.3); break;
      case 'earth': noise(300, 60, 0.6, 0.8, 'lowpass'); tone('sine', 70, 30, 0.5, 0.5); break;
      case 'light': for (let i = 0; i < 5; i++) tone('sine', 1200 + i * 300, 1600 + i * 300, 0.25, 0.06, i * 0.04); break;
      case 'shadow': tone('sawtooth', 220, 70, 0.5, 0.18); noise(800, 200, 0.5, 0.25); break;
      case 'void': tone('sine', 400, 30, 1.2, 0.45); noise(2000, 40, 1.1, 0.4, 'lowpass'); tone('sawtooth', 55, 30, 1.2, 0.15); break;
      case 'genesis': for (let i = 0; i < 7; i++) tone('sine', 440 * Math.pow(1.26, i), 440 * Math.pow(1.26, i) * 1.01, 1.4, 0.07, i * 0.07); noise(800, 6000, 1.2, 0.2); break;
      case 'aura': tone('sine', 300, 900, 0.5, 0.15); break;
      case 'heal': for (let i = 0; i < 4; i++) tone('sine', 660 * Math.pow(1.25, i), 660 * Math.pow(1.25, i), 0.3, 0.1, i * 0.08); break;
      case 'faint': tone('triangle', 500, 80, 0.7, 0.25); break;
      case 'throw': noise(500, 2500, 0.35, 0.3, 'bandpass', 0, 3); break;
      case 'absorb': tone('sine', 200, 1400, 0.5, 0.25); break;
      case 'wobble': tone('triangle', 300, 220, 0.12, 0.25); noise(900, 400, 0.1, 0.2); break;
      case 'caught': [0, 4, 7, 12].forEach((s, i) => tone('triangle', this.mf(72 + s), this.mf(72 + s), 0.25, 0.18, i * 0.09)); break;
      case 'break': noise(6000, 800, 0.4, 0.5, 'highpass'); tone('square', 600, 200, 0.2, 0.12); break;
      case 'levelup': [0, 4, 7, 12, 16].forEach((s, i) => tone('square', this.mf(76 + s), this.mf(76 + s), 0.14, 0.08, i * 0.07)); break;
      case 'encounter': tone('sawtooth', 220, 880, 0.35, 0.18); noise(200, 4000, 0.4, 0.3); break;
      case 'fragment': [0, 7, 12, 19, 24].forEach((s, i) => tone('sine', this.mf(67 + s), this.mf(67 + s), 0.8, 0.12, i * 0.12)); break;
      case 'rumble': noise(140, 40, 2.5, 0.9, 'lowpass'); tone('sine', 50, 28, 2.4, 0.5); break;
      case 'step': noise(900, 500, 0.05, 0.05); break;
      case 'roar': {
        const os = c.createOscillator(); os.type = 'sawtooth'; os.frequency.setValueAtTime(140, t); os.frequency.linearRampToValueAtTime(220, t + 0.25); os.frequency.exponentialRampToValueAtTime(55, t + 1.6);
        const lfo = c.createOscillator(); lfo.frequency.value = 23; const lg = c.createGain(); lg.gain.value = 30; lfo.connect(lg); lg.connect(os.frequency);
        const lp = c.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.setValueAtTime(900, t); lp.frequency.exponentialRampToValueAtTime(260, t + 1.6);
        const g = c.createGain(); this.env(g, t, 0.06, 0.55, 1.6); os.connect(lp); lp.connect(g); g.connect(o);
        const sg = c.createGain(); sg.gain.value = 0.6; g.connect(sg); sg.connect(this.verb);
        os.start(t); lfo.start(t); os.stop(t + 1.8); lfo.stop(t + 1.8); noise(600, 120, 1.4, 0.5, 'lowpass'); break;
      }
      case 'whale': {
        for (const [f0, f1, d, at] of [[180, 320, 1.4, 0], [320, 140, 1.8, 1.2]]) {
          const os = c.createOscillator(); os.type = 'sine'; os.frequency.setValueAtTime(f0, t + at); os.frequency.exponentialRampToValueAtTime(f1, t + at + d);
          const vib = c.createOscillator(); vib.frequency.value = 5; const vg = c.createGain(); vg.gain.value = 6; vib.connect(vg); vg.connect(os.frequency);
          const g = c.createGain(); g.gain.setValueAtTime(0.0001, t + at); g.gain.linearRampToValueAtTime(0.32, t + at + 0.4); g.gain.linearRampToValueAtTime(0.0001, t + at + d);
          os.connect(g); g.connect(o); const sg = c.createGain(); sg.gain.value = 1.2; g.connect(sg); sg.connect(this.verb);
          os.start(t + at); vib.start(t + at); os.stop(t + at + d + 0.1); vib.stop(t + at + d + 0.1);
        }
        break;
      }
      case 'meteor': tone('sine', 2400, 300, 0.45, 0.12); noise(6000, 400, 0.45, 0.2, 'bandpass', 0, 4); noise(300, 50, 0.6, 0.7, 'lowpass', 0.4); tone('sine', 90, 35, 0.6, 0.5, 0.4); break;
      case 'boom': noise(200, 40, 1.2, 1.0, 'lowpass'); tone('sine', 70, 25, 1.1, 0.7); break;
      case 'chime': [0, 7, 12, 16, 19].forEach((s, i) => tone('sine', this.mf(79 + s), this.mf(79 + s), 1.2, 0.07, i * 0.06)); break;
      case 'wave': noise(300, 1800, 1.3, 0.7, 'bandpass', 0, 0.8); noise(5000, 2000, 1.2, 0.25, 'highpass', 0.3); break;
    }
  },
};

// procedural songs (step = 16th note). helper chord tables in MIDI.
const SONGS = {
  title: {
    bpm: 66,
    seq(st, t, spb, v) {
      const bar = Math.floor(st / 16) % 4, s = st % 16;
      const ch = [[50, 57, 62, 66, 69], [47, 54, 59, 62, 66], [43, 50, 55, 59, 62], [45, 52, 57, 61, 64]][bar];
      if (s === 0) { v('pad', ch[1], spb * 16, 0.9); v('pad', ch[3], spb * 16, 0.8); v('bass', ch[0] - 12, spb * 14, 0.5); }
      if (s % 4 === 0) v('bell', ch[2 + ((s / 4 + bar) % 3)] + 12, spb * 4, 0.35);
      if (s === 10 && bar % 2 === 1) v('bell', ch[4] + 12, spb * 6, 0.3);
    },
  },
  world: {
    bpm: 92,
    seq(st, t, spb, v) {
      const bar = Math.floor(st / 16) % 8, s = st % 16;
      const prog = [[50, 57, 62, 66, 69], [47, 54, 59, 62, 66], [43, 50, 55, 59, 62], [45, 52, 57, 61, 64], [50, 57, 62, 66, 69], [42, 49, 54, 57, 61], [43, 50, 55, 59, 62], [45, 52, 57, 61, 64]];
      const ch = prog[bar];
      if (s === 0) { v('pad', ch[1], spb * 16, 0.7); v('pad', ch[3], spb * 16, 0.55); }
      if (s === 0 || s === 10) v('bass', ch[0] - 12, spb * 5, 0.6);
      if (s % 2 === 0) v('pluck', ch[[1, 2, 3, 4, 3, 2, 3, 4][(s / 2) % 8]] + 12, spb * 2, 0.55);
      const mel = [[0, 74], [6, 76], [8, 78], [12, 81]];
      if (bar % 4 === 1) for (const [p, m] of mel) if (s === p) v('bell', m, spb * 4, 0.3);
      if (bar % 4 === 3 && s === 0) v('bell', 81, spb * 8, 0.3);
      if (bar % 4 === 3 && s === 8) v('bell', 78, spb * 8, 0.25);
    },
  },
  battle: {
    bpm: 152,
    seq(st, t, spb, v) {
      const bar = Math.floor(st / 16) % 8, s = st % 16;
      const prog = [45, 41, 43, 40, 45, 41, 38, 40];
      const r = prog[bar];
      v('bass', r - 12 + (s % 4 === 2 ? 12 : 0), spb * 1.5, s % 4 === 0 ? 0.9 : 0.6);
      if (s === 0 || s === 8 || (s === 14 && bar % 2)) v('kick', 0, 0, 0.9);
      if (s === 4 || s === 12) v('snare', 0, 0, 0.7);
      if (s % 2 === 1) v('hat', 0, 0, 0.6);
      const minor = (r === 45 || r === 40 || r === 38) ? 3 : 4;
      const arp = [0, 7, 12, minor + 12, 7, 12, minor + 24, 12];
      v('pluck', r + 12 + arp[s % 8], spb * 1.2, 0.35);
      if (s === 0) v('pad', r + 12 + minor, spb * 16, 0.5);
      const lead = [[0, 76], [3, 79], [6, 81], [8, 79], [10, 76], [12, 74]];
      if (bar % 2 === 0 && bar >= 4) for (const [p, m] of lead) if (s === p) v('lead', m - (bar === 6 ? 2 : 0), spb * 2.5, 0.4);
    },
  },
  void: {
    bpm: 72,
    seq(st, t, spb, v) {
      const bar = Math.floor(st / 16) % 4, s = st % 16;
      const prog = [37, 33, 38, 36];
      const r = prog[bar];
      if (s === 0) { v('choir', r + 24, spb * 16, 0.9); v('choir', r + 27, spb * 16, 0.7); v('choir', r + 31 + (bar === 3 ? 1 : 0), spb * 16, 0.6); v('bass', r - 12, spb * 16, 0.8); v('timp', r - 12, 0, 1); }
      if (s === 8 || s === 14) v('timp', r - 12, 0, 0.7);
      if (s % 4 === 2) v('pluck', r + 24 + [0, 3, 7, 6][(s / 4 | 0) % 4], spb * 3, 0.3);
      if (s === 6 && bar % 2) v('bell', r + 36 + 6, spb * 8, 0.35);
      if (s % 2 === 0) v('hat', 0, 0, 0.35);
      if (s === 4 || s === 12) v('snare', 0, 0, 0.45);
    },
  },
  being: {
    bpm: 80,
    seq(st, t, spb, v) {
      const bar = Math.floor(st / 16) % 4, s = st % 16;
      const prog = [[40, 52, 56, 59, 64], [47, 54, 59, 63, 66], [37, 49, 52, 56, 61], [45, 52, 57, 61, 64]];
      const ch = prog[bar];
      if (s === 0) { v('choir', ch[2] + 12, spb * 16, 0.8); v('choir', ch[3] + 12, spb * 16, 0.7); v('pad', ch[1], spb * 16, 0.7); v('bass', ch[0] - 12, spb * 16, 0.7); v('timp', ch[0] - 12, 0, 0.9); }
      if (s % 2 === 0) v('bell', ch[1 + ((s / 2) % 4)] + 24, spb * 3, 0.22);
      if (s === 8) v('timp', ch[0] - 12, 0, 0.6);
      if (s % 4 === 2) v('hat', 0, 0, 0.3);
    },
  },
  star: {
    bpm: 68,
    seq(st, t, spb, v) {
      const bar = Math.floor(st / 16) % 4, s = st % 16;
      const prog = [[50, 57, 64, 66, 71], [48, 55, 62, 64, 69], [53, 60, 67, 69, 74], [52, 59, 66, 68, 73]];
      const ch = prog[bar];
      if (s === 0) { v('pad', ch[1], spb * 16, 0.6); v('choir', ch[3] + 12, spb * 16, 0.5); v('bass', ch[0] - 12, spb * 16, 0.5); }
      if (s % 2 === 0) v('bell', ch[(s / 2 + bar) % 5] + 24, spb * 3, 0.2);
      if (s === 6 || s === 14) v('bell', ch[4] + 31, spb * 6, 0.16);
    },
  },
  abyss: {
    bpm: 58,
    seq(st, t, spb, v) {
      const bar = Math.floor(st / 16) % 4, s = st % 16;
      const r = [38, 34, 36, 33][bar];
      if (s === 0) { v('choir', r + 12, spb * 16, 0.8); v('choir', r + 19, spb * 16, 0.55); v('bass', r - 12, spb * 16, 0.9); v('timp', r - 12, 0, 0.8); }
      if (s === 10) v('timp', r - 12, 0, 0.5);
      if (s % 4 === 2) v('pluck', r + 24 + [0, 3, 7, 10][(s / 4 | 0) % 4], spb * 4, 0.22);
      if (s === 8 && bar % 2 === 0) v('bell', r + 36, spb * 10, 0.25);
    },
  },
  dawn: {
    bpm: 128,
    seq(st, t, spb, v) {
      const bar = Math.floor(st / 16) % 8, s = st % 16;
      const prog = [[45, 57, 61, 64], [41, 53, 57, 60], [43, 55, 59, 62], [40, 52, 56, 59], [45, 57, 61, 64], [38, 50, 54, 57], [41, 53, 57, 60], [43, 55, 59, 62]];
      const ch = prog[bar];
      if (s === 0 || s === 6 || s === 10) v('timp', ch[0] - 12, 0, s === 0 ? 1 : 0.7);
      if (s === 0 || s === 8) v('kick', 0, 0, 0.8);
      if (s === 4 || s === 12) v('snare', 0, 0, 0.55);
      v('bass', ch[0] - 12 + (s % 4 === 2 ? 12 : 0), spb * 1.5, s % 4 === 0 ? 0.8 : 0.5);
      if (s === 0) { v('pad', ch[1] + 12, spb * 16, 0.6); v('pad', ch[2] + 12, spb * 16, 0.5); }
      const mel = bar % 2 === 0 ? [[0, 76], [3, 79], [6, 81], [8, 83], [12, 81]] : [[0, 79], [4, 76], [8, 74], [12, 76]];
      for (const [p, m] of mel) if (s === p) v('lead', m + (bar >= 4 ? 0 : -12) + 12, spb * 3, 0.38);
      if (s % 2 === 1) v('hat', 0, 0, 0.45);
    },
  },
  limina: {
    bpm: 92,
    seq(st, t, spb, v) {
      const bar = Math.floor(st / 16) % 8, s = st % 16;
      const voidBar = Math.floor(bar / 2) % 2 === 1;
      const ch = voidBar ? [[37, 49, 52, 56], [33, 45, 48, 52]][bar % 2] : [[40, 52, 56, 59], [45, 57, 61, 64]][bar % 2];
      if (s === 0) { v('choir', ch[2] + 12, spb * 16, 0.75); v('choir', ch[3] + 12, spb * 16, 0.6); v('bass', ch[0] - 12, spb * 16, 0.8); v('timp', ch[0] - 12, 0, 0.9); }
      if (s === 8) v('timp', ch[0] - 12, 0, 0.6);
      if (s % 2 === 0) v(voidBar ? 'pluck' : 'bell', ch[1 + ((s / 2) % 3)] + 24, spb * 2.5, voidBar ? 0.3 : 0.2);
      if (s === 4 || s === 12) v('snare', 0, 0, 0.35);
      if (s % 2 === 1) v('hat', 0, 0, 0.3);
    },
  },
  victory: {
    bpm: 140, once: true, len: 32, then: 'world',
    seq(st, t, spb, v) {
      const notes = { 0: 72, 2: 76, 4: 79, 6: 84, 10: 83, 12: 84 };
      if (notes[st] !== undefined) v('lead', notes[st], spb * (st === 12 ? 10 : 2), 0.5);
      if (st === 0 || st === 12) { v('pad', 60, spb * 12, 0.7); v('pad', 64, spb * 12, 0.6); v('bass', 48, spb * 10, 0.7); }
      if (st % 2 === 0 && st < 16) v('hat', 0, 0, 0.5);
    },
  },
};
