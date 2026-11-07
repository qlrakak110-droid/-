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
const bloomPass = new UnrealBloomPass(new THREE.Vector2(256, 256), 0.95, 0.55, 0.95);
// soft-knee bloom threshold: the part of a pixel ABOVE the threshold glows (not the whole pixel), so sunlit walls,
// sand and sky just over the line stay crisp while emissive glows, sparks and the sun still bloom generously.
bloomPass.highPassUniforms.smoothWidth.value = 0.55; // = knee width
bloomPass.materialHighPassFilter.fragmentShader = `uniform sampler2D tDiffuse; uniform vec3 defaultColor; uniform float defaultOpacity; uniform float luminosityThreshold; uniform float smoothWidth; varying vec2 vUv;
  void main(){
    vec3 c = min(texture2D(tDiffuse, vUv).rgb, vec3(14.0));
    float br = max(c.r, max(c.g, c.b));
    float knee = max(smoothWidth, 1e-3);
    float rq = clamp(br - luminosityThreshold + knee, 0.0, 2.0 * knee);
    rq = rq * rq / (4.0 * knee);
    float w = max(rq, br - luminosityThreshold) / max(br, 1e-4);
    // the blend uses this alpha as a weight: keep it a tight mask around the threshold so broad mid-bright areas
    // (sky, pale stone) never amplify nearby glows into a wash
    float a = smoothstep(luminosityThreshold - knee * 0.25, luminosityThreshold + knee * 0.5, br);
    // soft-compress very hot sources (lit-up stone, big emissive columns) so one object can't flood the frame
    vec3 cw = c * w; cw /= 1.0 + max(cw.r, max(cw.g, cw.b)) * 0.25;
    gl_FragColor = vec4(cw, a);
  }`;
bloomPass.materialHighPassFilter.needsUpdate = true;
composer.addPass(bloomPass);
composer.addPass(new OutputPass());

// LOW path (phones: renderer.render straight to the screen, no extra targets): the same filmic grade is folded into
// the tone-mapping function itself, so every material ends graded at no extra cost.
THREE.ShaderChunk.tonemapping_pars_fragment = THREE.ShaderChunk.tonemapping_pars_fragment.replace(
  'vec3 CustomToneMapping( vec3 color ) { return color; }',
  `vec3 CustomToneMapping( vec3 color ) {
    vec3 g = sqrt( ACESFilmicToneMapping( color ) );
    float L = dot( g, vec3( 0.299, 0.587, 0.114 ) );
    float sat = max( g.r, max( g.g, g.b ) ) - min( g.r, min( g.g, g.b ) );
    g = clamp( mix( vec3( L ), g, 1.02 + 0.16 * ( 1.0 - smoothstep( 0.05, 0.55, sat ) ) * smoothstep( 0.02, 0.2, L ) ), 0.0, 1.0 );
    g += 0.22 * g * ( 1.0 - g ) * ( 2.0 * g - 1.0 );
    float L2 = dot( g, vec3( 0.299, 0.587, 0.114 ) );
    g += vec3( -0.006, 0.004, 0.022 ) * ( 1.0 - smoothstep( 0.04, 0.5, L2 ) );
    g *= 1.0 + vec3( 0.05, 0.016, -0.045 ) * smoothstep( 0.42, 0.95, L2 );
    g = max( g + vec3( 0.008, 0.0, 0.02 ) * ( 1.0 - g ), 0.0 );
    return g * g;
  }`);

// final cinematic pass (display space): shockwave ripple, chromatic aberration, sun shafts + lens flare,
// filmic grade (contrast curve, vibrance, split-toning), vignette, grain.
// Look presets per mode (world / battle / legend) are picked automatically in renderScene() and eased in update();
// Post.setMode('legend') forces one, Post.setMode(null) returns to automatic.
const Post = {
  U: {
    tDiffuse: { value: null }, uTime: { value: 0 }, uRes: { value: new THREE.Vector2(1, 1) },
    uVig: { value: 0.3 }, uCA: { value: 0 }, uGrain: { value: 0.026 }, uSat: { value: 1.05 }, uLift: { value: new THREE.Vector3(0.01, 0.0, 0.024) },
    uShock: { value: new THREE.Vector4(0.5, 0.5, -1, 0) }, uSun: { value: new THREE.Vector3(0.5, 0.5, 0) }, uTint: { value: new THREE.Vector3(1, 1, 1) },
    uCon: { value: 0.28 }, uVib: { value: 0.22 }, uWarm: { value: new THREE.Vector3(0.05, 0.016, -0.045) }, uCool: { value: new THREE.Vector3(-0.006, 0.004, 0.024) },
    uFlare: { value: 1 },
  },
  presets: {
    world:  { con: 0.28, vib: 0.22, sat: 1.05, vig: 0.3,  warm: [0.05, 0.016, -0.045], cool: [-0.006, 0.004, 0.024], lift: [0.01, 0.0, 0.024], flare: 1.0, bloom: 1.05, thr: 0.95, knee: 0.55, tint: [1.0, 0.93, 0.82] },
    battle: { con: 0.33, vib: 0.26, sat: 1.07, vig: 0.34, warm: [0.055, 0.018, -0.05], cool: [-0.008, 0.004, 0.03], lift: [0.01, 0.0, 0.026], flare: 0.85, bloom: 1.1, thr: 0.92, knee: 0.55, tint: [1.0, 0.95, 0.86] },
    legend: { con: 0.36, vib: 0.18, sat: 1.04, vig: 0.42, warm: [0.04, 0.012, -0.035], cool: [-0.006, 0.006, 0.034], lift: [0.012, 0.004, 0.03], flare: 0.9, bloom: 1.15, thr: 0.9, knee: 0.55, tint: [1.0, 0.97, 0.94] },
  },
  // per-arena accents layered on the legend look
  themes: {
    void:     { warm: [0.02, 0.0, 0.0], cool: [0.004, -0.004, 0.03], vig: 0.48, tint: [0.96, 0.9, 1.0] },
    being:    { warm: [0.07, 0.03, -0.05], tint: [1.0, 0.94, 0.8] },
    star:     { cool: [-0.008, 0.006, 0.04], tint: [0.94, 0.97, 1.0] },
    abyss:    { warm: [0.0, 0.02, 0.0], cool: [-0.01, 0.012, 0.035], tint: [0.88, 1.0, 1.0] },
    dawn:     { warm: [0.07, 0.022, -0.05], con: 0.32, tint: [1.0, 0.9, 0.78] },
    boundary: { con: 0.4, vig: 0.46 },
  },
  mode: 'world', theme: null, forced: null, _snap: true,
  setMode(m) { this.forced = m && this.presets[m] ? m : null; },
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
    // ease the look toward the active preset (snaps on the first frame)
    const m = this.forced || this.mode, base = this.presets[m] || this.presets.world, U = this.U;
    const P = m === 'legend' && this.themes[this.theme] ? Object.assign({}, base, this.themes[this.theme]) : base;
    const k = this._snap ? 1 : 1 - Math.exp(-2.2 * dt); this._snap = false;
    U.uCon.value = lerp(U.uCon.value, P.con, k); U.uVib.value = lerp(U.uVib.value, P.vib, k); U.uSat.value = lerp(U.uSat.value, P.sat, k);
    U.uVig.value = lerp(U.uVig.value, P.vig, k); U.uFlare.value = lerp(U.uFlare.value, P.flare, k);
    const v3 = (u, a) => { u.x = lerp(u.x, a[0], k); u.y = lerp(u.y, a[1], k); u.z = lerp(u.z, a[2], k); };
    v3(U.uWarm.value, P.warm); v3(U.uCool.value, P.cool); v3(U.uLift.value, P.lift);
    bloomPass.strength = lerp(bloomPass.strength, P.bloom, k); bloomPass.threshold = lerp(bloomPass.threshold, P.thr, k);
    const hk = bloomPass.highPassUniforms.smoothWidth; hk.value = lerp(hk.value, P.knee, k);
    // the wide bloom mips carry a warm golden-hour tint, the tight ones stay neutral so glows keep their colour
    const T = bloomPass.bloomTintColors;
    for (let i = 0; i < T.length; i++) { const f = i / (T.length - 1); T[i].set(lerp(1, P.tint[0], f), lerp(1, P.tint[1], f), lerp(1, P.tint[2], f)); }
  },
};
const finalPass = new ShaderPass(new THREE.ShaderMaterial({
  uniforms: Post.U,
  vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }',
  fragmentShader: `uniform sampler2D tDiffuse; uniform float uTime, uVig, uCA, uGrain, uSat, uCon, uVib, uFlare; uniform vec2 uRes; uniform vec4 uShock;
    uniform vec3 uSun, uLift, uTint, uWarm, uCool; varying vec2 vUv;
    float luma(vec3 c){ return dot(c, vec3(0.299, 0.587, 0.114)); }
    float sunL(vec2 p){ return luma(texture2D(tDiffuse, clamp(p, 0.001, 0.999)).rgb); }
    // one soft lens ghost: filled disc + faint rim, centre c, radius r
    vec3 ghost(vec2 p, vec2 c, float r, vec3 col){ float d = length(p - c); return col * (smoothstep(r, r * 0.45, d) * 0.6 + smoothstep(r * 0.08, 0.0, abs(d - r * 0.92)) * 0.5); }
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
        // god rays: march toward the sun, but only bright pixels NEAR the sun emit, so we get real shafts between
        // occluders instead of a uniform haze over every bright surface
        float asp0 = uRes.x / uRes.y;
        vec2 dl = (uv - uSun.xy) / 30.0; vec2 sp = uv; float decay = 1.0; vec3 acc = vec3(0.0);
        for (int i = 0; i < 30; i++) {
          sp -= dl; vec3 s = texture2D(tDiffuse, clamp(sp, 0.001, 0.999)).rgb;
          float near = 1.0 - smoothstep(0.03, 0.32, length((sp - uSun.xy) * vec2(asp0, 1.0)));
          acc += s * max(luma(s) - 0.74, 0.0) * near * decay; decay *= 0.962;
        }
        col += acc * uSun.z * 0.11 * vec3(1.0, 0.84, 0.66);
        // procedural lens flare: only while the sun disc itself is on screen and not hidden behind something
        vec2 ndc = uSun.xy * 2.0 - 1.0;
        float onS = 1.0 - smoothstep(0.92, 1.1, max(abs(ndc.x), abs(ndc.y)));
        if (onS * uFlare > 0.001) {
          float asp = uRes.x / uRes.y; vec2 o = vec2(0.006 / asp, 0.006);
          float occ = (sunL(uSun.xy) * 2.0 + sunL(uSun.xy + vec2(o.x, 0.0)) + sunL(uSun.xy - vec2(o.x, 0.0)) + sunL(uSun.xy + vec2(0.0, o.y)) + sunL(uSun.xy - vec2(0.0, o.y))) / 6.0;
          float vis = smoothstep(0.8, 0.97, occ) * onS * min(uSun.z * 1.6, 1.0) * uFlare;
          if (vis > 0.001) {
            vec2 p = vec2(c.x * asp, c.y), s = vec2((uSun.x - 0.5) * asp, uSun.y - 0.5), d = p - s;
            float r = length(d);
            vec3 fl = vec3(1.0, 0.68, 0.4) * (exp(-abs(d.y) * 240.0) * exp(-abs(d.x) * 2.4) * 0.5 + exp(-abs(d.y) * 55.0) * exp(-abs(d.x) * 4.5) * 0.1);
            fl += vec3(1.0, 0.78, 0.52) * exp(-r * 10.0) * 0.16;
            float far = 0.6 + 0.4 * smoothstep(0.0, 0.5, length(s));
            fl += ghost(p, s * -0.32, 0.028, vec3(0.45, 0.85, 0.75)) * 0.07 * far;
            fl += ghost(p, s * -0.62, 0.055, vec3(0.62, 0.45, 1.0)) * 0.06 * far;
            fl += ghost(p, s * -1.0, 0.11, vec3(1.0, 0.72, 0.38)) * 0.045 * far;
            fl += ghost(p, s * -1.38, 0.035, vec3(1.0, 0.5, 0.55)) * 0.07 * far;
            fl += ghost(p, s * 0.42, 0.04, vec3(0.7, 0.9, 0.55)) * 0.05 * far;
            col += fl * vis;
          }
        }
      }
      // filmic grade (display space): vibrance + saturation, S-curve contrast, split-toning, lifted blacks
      col = max(col, 0.0);
      float L = luma(col);
      float sat = max(col.r, max(col.g, col.b)) - min(col.r, min(col.g, col.b));
      col = clamp(mix(vec3(L), col, uSat + uVib * (1.0 - smoothstep(0.05, 0.55, sat)) * smoothstep(0.02, 0.2, L)), 0.0, 1.0);
      col += uCon * col * (1.0 - col) * (2.0 * col - 1.0);
      float L2 = luma(col);
      col += uCool * (1.0 - smoothstep(0.04, 0.5, L2));
      col *= 1.0 + uWarm * smoothstep(0.42, 0.95, L2);
      col = max(col + uLift * (1.0 - col), 0.0);
      col *= uTint;
      float v = smoothstep(0.95, 0.25, length(c * vec2(1.0, 0.9)));
      col *= mix(vec3(1.0 - uVig) * vec3(1.0, 0.97, 1.04), vec3(1.0), v);
      float g = fract(sin(dot(vUv * uRes + fract(uTime) * 61.0, vec2(12.9898, 78.233))) * 43758.5453);
      col += (g - 0.5) * uGrain * (1.0 - 0.5 * L2);
      gl_FragColor = vec4(col, 1.0);
    }`,
}));
composer.addPass(finalPass);

function applyQuality() {
  const dpr = window.devicePixelRatio || 1;
  renderer.setPixelRatio(Math.min(dpr, Settings.high ? (isTouch ? 1.75 : 2) : 1));
  renderer.shadowMap.enabled = Settings.high || !isTouch;
  // high: ACES here, graded in the final pass. low: ACES + grade inside every material (CustomToneMapping above)
  renderer.toneMapping = Settings.high ? THREE.ACESFilmicToneMapping : THREE.CustomToneMapping;
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
  const ps = _pScale(); for (const m of PSETS) m.uniforms.uScale.value = ps;
}
const Cams = [];
window.addEventListener('resize', onResize);

function renderScene(scene, camera) {
  // pick the look preset from what is being drawn (no other file has to call anything)
  let mode = 'world';
  try { if (scene === Battle.scene) { mode = Battle.cfg && Battle.cfg.kind === 'legend' ? 'legend' : 'battle'; Post.theme = Battle.theme; } } catch (e) {}
  Post.mode = mode;
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
// same four toon bands as before (70 / 150 / 215 / 255), but on a 64-texel linear ramp whose steps are slightly
// feathered, so band edges on curved surfaces are smooth instead of stair-stepped
const toonGrad = (() => {
  const N = 64, d = new Uint8Array(N), st = (e0, e1, x) => { const t = clamp((x - e0) / (e1 - e0), 0, 1); return t * t * (3 - 2 * t); };
  for (let i = 0; i < N; i++) {
    const x = (i + 0.5) / N, w = 0.028;
    d[i] = Math.round(70 + 80 * st(0.25 - w, 0.25 + w, x) + 65 * st(0.5 - w, 0.5 + w, x) + 40 * st(0.75 - w, 0.75 + w, x));
  }
  const t = new THREE.DataTexture(d, N, 1, THREE.RedFormat);
  t.minFilter = t.magFilter = THREE.LinearFilter; t.generateMipmaps = false; t.needsUpdate = true; return t;
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
          vec3 ld = directionalLights[0].direction;
          // how much of the key light actually reaches this pixel (0 inside cast shadows) — keeps highlights out of shade
          float litK = clamp(dot(reflectedLight.directDiffuse, vec3(0.333)) / max(dot(diffuseColor.rgb * directionalLights[0].color, vec3(0.333)) * 0.3183, 1e-3), 0.0, 1.0);
          vec3 hv = normalize(ld + vdir);
          float sp = smoothstep(0.962, 0.978, dot(normal, hv));
          outgoingLight += directionalLights[0].color * sp * uSpec * 0.35 * (0.25 + 0.75 * litK);
          // sun-kissed edge: a warm sheen on silhouettes that face the key light, so shapes read against the background
          float edge = smoothstep(0.45, 0.95, 1.0 - clamp(dot(normal, vdir), 0.0, 1.0));
          outgoingLight += directionalLights[0].color * diffuseColor.rgb * edge * smoothstep(-0.05, 0.55, dot(normal, ld)) * litK * 0.075;
        #endif
      }
      #include <opaque_fragment>`);
  };
  m.customProgramCacheKey = () => 'toonRim2';
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
// point sizes are in pixels: scale them with the drawing-buffer height so sparks keep the same size relative to the
// scene on every screen (tuned at 480 px; a 1440p monitor would otherwise show them 3x too small)
const PSETS = [];
function _pScale() { return clamp(renderer.getDrawingBufferSize(_pv2).y / 480, 0.75, 5); }
const _pv2 = new THREE.Vector2();
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
      // white-hot core: the centre of each spark burns brighter and whiter than its coloured halo
      fragmentShader: `uniform sampler2D uTex; varying vec3 vC; varying float vA;
        void main(){ vec4 t = texture2D(uTex, gl_PointCoord); float core = smoothstep(0.62, 1.0, t.a);
          gl_FragColor = vec4((vC * t.a + core * (vC * 0.3 + 0.22)) * vA, 1.0); }`,
      blending: THREE.AdditiveBlending, depthWrite: false, transparent: true,
    });
    this.points = new THREE.Points(g, m); this.points.frustumCulled = false; this.points.renderOrder = 10;
    scene.add(this.points);
    m.uniforms.uScale.value = _pScale(); PSETS.push(m);
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

// ---------------------------------------------------------------- audio: synth + sequencer
// everything is synthesized: a small orchestra of WebAudio voices (pads, strings, choir, harp, brass, drums…) through
// a stereo hall reverb and a ping-pong echo. Public API: init(), play(name), stop(), fx(name, opt), setOn(on).
const Snd = {
  ctx: null, master: null, music: null, sfx: null, verb: null, echo: null, song: null, step: 0, nextT: 0, timer: null, musicVol: 0.42,
  init() {
    if (this.ctx) { if (this.ctx.state === 'suspended') this.ctx.resume(); return; }
    const AC = window.AudioContext || window.webkitAudioContext; if (!AC) return;
    let c; try { c = new AC(); } catch (e) { return; }
    this.ctx = c;
    this.master = c.createGain(); this.master.gain.value = Settings.sound ? 0.8 : 0; this.master.connect(c.destination);
    const comp = c.createDynamicsCompressor(); comp.threshold.value = -15; comp.knee.value = 12; comp.ratio.value = 3.5; comp.attack.value = 0.005; comp.release.value = 0.2; comp.connect(this.master);
    // music bus with a touch of warmth and air
    const lo = c.createBiquadFilter(); lo.type = 'lowshelf'; lo.frequency.value = 170; lo.gain.value = 2.5;
    const hi = c.createBiquadFilter(); hi.type = 'highshelf'; hi.frequency.value = 7000; hi.gain.value = 2;
    this.music = c.createGain(); this.music.gain.value = this.musicVol; this.music.connect(lo); lo.connect(hi); hi.connect(comp);
    this.sfx = c.createGain(); this.sfx.gain.value = 0.8; this.sfx.connect(comp);
    // hall reverb: pre-delay → long stereo tail that darkens as it decays → low-cut return
    this.verb = c.createGain();
    const pre = c.createDelay(0.2); pre.delayTime.value = 0.024;
    const conv = c.createConvolver(); conv.buffer = this.impulse(3.9);
    const vhp = c.createBiquadFilter(); vhp.type = 'highpass'; vhp.frequency.value = 160;
    const vg = c.createGain(); vg.gain.value = 0.62;
    this.verb.connect(pre); pre.connect(conv); conv.connect(vhp); vhp.connect(vg); vg.connect(comp);
    // ping-pong echo (left, then right, fading and darkening) for harps, bells and plucks
    this.echo = c.createGain();
    const dL = c.createDelay(1.5), dR = c.createDelay(1.5), fb = c.createGain(), elp = c.createBiquadFilter(), mg = c.createChannelMerger(2), eg = c.createGain();
    dL.delayTime.value = 0.33; dR.delayTime.value = 0.33; fb.gain.value = 0.36; elp.type = 'lowpass'; elp.frequency.value = 2800; eg.gain.value = 0.42;
    this.echo.connect(dL); dL.connect(elp); elp.connect(dR); dR.connect(fb); fb.connect(dL);
    dL.connect(mg, 0, 0); dR.connect(mg, 0, 1); mg.connect(eg); eg.connect(comp);
    const ev = c.createGain(); ev.gain.value = 0.3; eg.connect(ev); ev.connect(this.verb);
    // music-side sends follow the music fader, so song changes and fades take their reverb/echo tails with them
    this.mverb = c.createGain(); this.mverb.gain.value = this.musicVol * 2; this.mverb.connect(this.verb);
    this.mecho = c.createGain(); this.mecho.gain.value = this.musicVol * 2; this.mecho.connect(this.echo);
    this.noiseBuf = c.createBuffer(1, c.sampleRate, c.sampleRate);
    const nd = this.noiseBuf.getChannelData(0); for (let i = 0; i < nd.length; i++) nd[i] = Math.random() * 2 - 1;
    this.timer = setInterval(() => { try { this.tick(); } catch (e) { console.warn(e); this.song = null; } }, 25);
  },
  // stereo impulse response: early reflections + noise tail whose high end decays faster than its body
  impulse(sec) {
    const c = this.ctx, sr = c.sampleRate, len = Math.floor(sr * sec), buf = c.createBuffer(2, len, sr);
    for (let ch = 0; ch < 2; ch++) {
      const d = buf.getChannelData(ch); let y = 0;
      for (let i = 0; i < len; i++) {
        const k = i / len, a = 0.9 - 0.8 * Math.pow(k, 0.55);
        y += a * ((Math.random() * 2 - 1) - y);
        d[i] = y * Math.pow(1 - k, 2.1) * Math.min(1, i / (sr * 0.004));
      }
      for (let r = 0; r < 8; r++) { const at = Math.floor(sr * (0.007 + r * 0.0105 + Math.random() * 0.005)); if (at < len) d[at] += (Math.random() < 0.5 ? -1 : 1) * (0.55 - r * 0.05); }
    }
    return buf;
  },
  setOn(on) { Settings.sound = on; saveSettings(); if (this.master) this.master.gain.setTargetAtTime(on ? 0.8 : 0, this.ctx.currentTime, 0.05); },
  mf(m) { return 440 * Math.pow(2, (m - 69) / 12); },
  env(g, t, a, peak, d, sus = 0.0001) {
    g.gain.cancelScheduledValues(t); g.gain.setValueAtTime(0.0001, t);
    g.gain.linearRampToValueAtTime(Math.max(peak, 0.0001), t + a); g.gain.exponentialRampToValueAtTime(Math.max(sus, 0.0001), t + a + d);
  },
  // attack → hold → release envelope for sustained instruments
  ahr(g, t, a, peak, hold, rel) {
    peak = Math.max(peak, 0.0001);
    g.gain.setValueAtTime(0.0001, t); g.gain.linearRampToValueAtTime(peak, t + a);
    g.gain.setValueAtTime(peak, t + Math.max(a, hold)); g.gain.linearRampToValueAtTime(0.0001, t + Math.max(a, hold) + rel);
  },
  pan(node, p) {
    const c = this.ctx; if (!p || !c.createStereoPanner) return node;
    const s = c.createStereoPanner(); s.pan.value = clamp(p, -1, 1); node.connect(s); return s;
  },
  voice(inst, midi, t, dur, vol = 1, out, o) {
    const c = this.ctx; if (!c) return; out = out || this.music; o = o || {};
    const f = this.mf(midi); if (!isFinite(f) || !isFinite(t) || !isFinite(dur) || !isFinite(vol)) return;
    const isM = out === this.music, VB = isM ? this.mverb : this.verb, EB = isM ? this.mecho : this.echo;
    const send = (node, amt, echo) => { const bus = echo ? EB : VB; if (amt > 0 && bus) { const s = c.createGain(); s.gain.value = amt; node.connect(s); s.connect(bus); } };
    const osc = (type, fr, det) => { const x = c.createOscillator(); x.type = type; x.frequency.value = fr; if (det) x.detune.value = det; return x; };
    const filt = (type, fr, q) => { const x = c.createBiquadFilter(); x.type = type; x.frequency.value = fr; x.Q.value = q ?? 0.7; return x; };
    const gain = (v) => { const g = c.createGain(); g.gain.value = v ?? 1; return g; };
    const noiseSrc = () => { const s = c.createBufferSource(); s.buffer = this.noiseBuf; s.loop = true; return s; };
    const lfos = [];
    // delayed vibrato: returns the scaled LFO output to connect to one or more detune params
    const vib = (rate, depth, at) => { const l = osc('sine', rate), lg = gain(0); lg.gain.setValueAtTime(0, t); lg.gain.linearRampToValueAtTime(depth, t + at); l.connect(lg); l.start(t); lfos.push(l); return lg; };
    const stopL = (e) => lfos.forEach((l) => l.stop(e));
    const P = o.pan || 0;
    switch (inst) {
      case 'pluck': {
        const g = gain(0); this.env(g, t, 0.004, 0.2 * vol, dur * 1.5);
        const lp = filt('lowpass', 0, 1.2); lp.frequency.setValueAtTime(Math.min(f * 7, 9000), t); lp.frequency.exponentialRampToValueAtTime(Math.max(f * 1.4, 180), t + Math.max(dur, 0.08) * 0.9);
        const a = osc('sawtooth', f), b = osc('triangle', f, 5), bg = gain(0.9);
        a.connect(lp); b.connect(bg); bg.connect(lp); lp.connect(g); const n = this.pan(g, P); n.connect(out); send(n, 0.28); send(n, 0.2, true);
        const e = t + dur * 1.7 + 0.15; a.start(t); b.start(t); a.stop(e); b.stop(e); break;
      }
      case 'harp': {
        const g = gain(0); this.env(g, t, 0.003, 0.22 * vol, dur * 2.2);
        const g2 = gain(0); this.env(g2, t, 0.002, 0.07 * vol, dur * 0.5);
        const a = osc('triangle', f), b = osc('sine', f * 2), lp = filt('lowpass', Math.min(f * 5, 7000));
        a.connect(lp); lp.connect(g); b.connect(g2); g2.connect(g); const n = this.pan(g, P); n.connect(out); send(n, 0.42); send(n, 0.22, true);
        const e = t + dur * 2.4 + 0.15; a.start(t); b.start(t); a.stop(e); b.stop(e); break;
      }
      case 'celesta': {
        const g = gain(0); this.env(g, t, 0.002, 0.14 * vol, dur * 1.8);
        const g2 = gain(0); this.env(g2, t, 0.001, 0.05 * vol, 0.12);
        const a = osc('sine', f), b = osc('sine', f * 4.01);
        a.connect(g); b.connect(g2); g2.connect(g); const n = this.pan(g, P); n.connect(out); send(n, 0.5); send(n, 0.32, true);
        const e = t + dur * 2 + 0.15; a.start(t); b.start(t); a.stop(e); b.stop(e); break;
      }
      case 'lead': {
        const g = gain(0); this.ahr(g, t, 0.02, 0.17 * vol, dur, 0.22);
        const a = osc('square', f), b = osc('sawtooth', f, 6), lp = filt('lowpass', 2400, 1.6), bg = gain(0.55);
        a.connect(lp); b.connect(bg); bg.connect(lp); lp.connect(g);
        const vb = vib(5.6, 14, 0.25); vb.connect(a.detune); vb.connect(b.detune);
        const n = this.pan(g, P); n.connect(out); send(n, 0.35); send(n, 0.12, true);
        const e = t + dur + 0.3; a.start(t); b.start(t); a.stop(e); b.stop(e); stopL(e); break;
      }
      case 'flute': {
        const g = gain(0); this.ahr(g, t, 0.07, 0.16 * vol, dur, 0.25);
        const a = osc('sine', f), b = osc('triangle', f * 2), bg = gain(0.12);
        a.connect(g); b.connect(bg); bg.connect(g);
        const ns = noiseSrc(), bp = filt('bandpass', Math.min(f * 2, 8000), 2), ng = gain(0); this.ahr(ng, t, 0.05, 0.035 * vol, dur * 0.6, 0.2);
        ns.connect(bp); bp.connect(ng); ng.connect(g);
        const vb = vib(5.2, 12, 0.35); vb.connect(a.detune); vb.connect(b.detune);
        const n = this.pan(g, P); n.connect(out); send(n, 0.45); send(n, 0.15, true);
        const e = t + dur + 0.35; a.start(t); b.start(t); ns.start(t, Math.random() * 0.5); a.stop(e); b.stop(e); ns.stop(e); stopL(e); break;
      }
      case 'brass': {
        const g = gain(0); this.ahr(g, t, 0.035, 0.15 * vol, dur, 0.22);
        const lp = filt('lowpass', 0, 2.2);
        lp.frequency.setValueAtTime(380, t); lp.frequency.exponentialRampToValueAtTime(Math.min(f * 9, 5200), t + 0.07); lp.frequency.exponentialRampToValueAtTime(Math.min(f * 4, 3000), t + 0.35);
        const a = osc('sawtooth', f, -7), b = osc('sawtooth', f, 7), s = osc('square', f / 2), sg = gain(0.25);
        a.connect(lp); b.connect(lp); s.connect(sg); sg.connect(lp); lp.connect(g);
        const n = this.pan(g, P); n.connect(out); send(n, 0.4);
        const e = t + dur + 0.3; a.start(t); b.start(t); s.start(t); a.stop(e); b.stop(e); s.stop(e); break;
      }
      case 'pad': {
        const g = gain(0); const at = Math.min(0.9, dur * 0.4); this.ahr(g, t, at, 0.06 * vol, dur, 1.6);
        const lp = filt('lowpass', 0, 0.9); lp.frequency.setValueAtTime(420, t); lp.frequency.linearRampToValueAtTime(1500, t + at + 0.4); lp.frequency.linearRampToValueAtTime(800, t + dur + 1.6);
        const a = osc('sawtooth', f, -10), b = osc('sawtooth', f, 10), s = osc('triangle', f / 2), sg = gain(0.6);
        this.pan(a, -0.55).connect(lp); this.pan(b, 0.55).connect(lp); s.connect(sg); sg.connect(lp); lp.connect(g);
        const n = this.pan(g, P); n.connect(out); send(n, 0.8);
        const e = t + dur + 1.7; a.start(t); b.start(t); s.start(t); a.stop(e); b.stop(e); s.stop(e); break;
      }
      case 'strings': {
        const g = gain(0); this.ahr(g, t, Math.min(0.35, dur * 0.3), 0.05 * vol, dur, 0.9);
        const lp = filt('lowpass', 2600, 0.8), hp = filt('highpass', 180);
        const os = [osc('sawtooth', f, -12), osc('sawtooth', f, 0), osc('sawtooth', f, 11)];
        const vb = vib(5.1, 9, 0.4);
        os.forEach((x, i) => { vb.connect(x.detune); this.pan(x, (i - 1) * 0.6).connect(lp); });
        lp.connect(hp); hp.connect(g); const n = this.pan(g, P); n.connect(out); send(n, 0.65);
        const e = t + dur + 1; os.forEach((x) => { x.start(t); x.stop(e); }); stopL(e); break;
      }
      case 'choir': {
        const g = gain(0); this.ahr(g, t, Math.min(0.8, dur * 0.4), 0.075 * vol, dur * 0.85, 1.0);
        const f1 = filt('bandpass', 650, 4), f2 = filt('bandpass', 1080, 5), f2g = gain(0.6), lp = filt('lowpass', 1800);
        const os = [osc('sawtooth', f, -9), osc('sawtooth', f, 0), osc('sawtooth', f, 8)];
        const vb = vib(4.6, 11, 0.6);
        os.forEach((x) => { vb.connect(x.detune); x.connect(f1); x.connect(f2); });
        f2.connect(f2g); f1.connect(lp); f2g.connect(lp); lp.connect(g);
        const n = this.pan(g, P); n.connect(out); send(n, 0.95);
        const e = t + dur + 1.1; os.forEach((x) => { x.start(t); x.stop(e); }); stopL(e); break;
      }
      case 'drone': {
        const g = gain(0); this.ahr(g, t, 1.4, 0.09 * vol, dur, 2.0);
        const lp = filt('lowpass', 260, 2.5);
        const lfo = osc('sine', 0.13), lg = gain(170); lfo.connect(lg); lg.connect(lp.frequency);
        const a = osc('sawtooth', f, -6), b = osc('sawtooth', f * 1.004, 6), s = osc('sine', f / 2), sg = gain(1.4);
        this.pan(a, -0.5).connect(lp); this.pan(b, 0.5).connect(lp); s.connect(sg); sg.connect(g); lp.connect(g);
        g.connect(out); send(g, 0.7);
        const e = t + dur + 2.1; [a, b, s, lfo].forEach((x) => { x.start(t); x.stop(e); }); break;
      }
      case 'glide': { // whale-song lead: slow portamento from o.from to the note
        const g = gain(0); this.ahr(g, t, 0.35, 0.16 * vol, dur * 0.8, dur * 0.4);
        const a = osc('sine', f), b = osc('triangle', f, 4), bg = gain(0.25);
        const f0 = this.mf(o.from ?? midi - 5);
        a.frequency.setValueAtTime(f0, t); a.frequency.exponentialRampToValueAtTime(f, t + dur * 0.35);
        b.frequency.setValueAtTime(f0, t); b.frequency.exponentialRampToValueAtTime(f, t + dur * 0.35);
        a.connect(g); b.connect(bg); bg.connect(g); const vb = vib(4.2, 18, dur * 0.4); vb.connect(a.detune); vb.connect(b.detune);
        const n = this.pan(g, P); n.connect(out); send(n, 1.0); send(n, 0.25, true);
        const e = t + dur * 1.25 + 0.1; a.start(t); b.start(t); a.stop(e); b.stop(e); stopL(e); break;
      }
      case 'bass': {
        const a = osc('sawtooth', f), s = osc('sine', f), sg = gain(0.7);
        const lp = filt('lowpass', 0, 3); lp.frequency.setValueAtTime(900, t); lp.frequency.exponentialRampToValueAtTime(170, t + Math.max(dur, 0.08));
        const g = gain(0); this.env(g, t, 0.008, 0.26 * vol, Math.max(dur, 0.08));
        a.connect(lp); lp.connect(g); s.connect(sg); sg.connect(g); g.connect(out);
        const e = t + dur + 0.15; a.start(t); s.start(t); a.stop(e); s.stop(e); break;
      }
      case 'sub': {
        const a = osc('sine', f), g = gain(0); this.ahr(g, t, 0.04, 0.22 * vol, dur * 0.8, dur * 0.3 + 0.2);
        a.connect(g); g.connect(out); a.start(t); a.stop(t + dur * 1.1 + 0.3); break;
      }
      case 'bell': {
        for (const [mul, amp, dd] of [[1, 0.15, 2.5], [2.76, 0.05, 1.4], [5.4, 0.022, 0.8], [0.5, 0.03, 2.8]]) {
          const a = osc('sine', f * mul), g = gain(0); this.env(g, t, 0.004, amp * vol, dur * dd);
          a.connect(g); const n = this.pan(g, P); n.connect(out); send(n, 0.6); if (mul === 1) send(n, 0.25, true);
          a.start(t); a.stop(t + dur * dd + 0.12);
        }
        break;
      }
      case 'kick': {
        const a = osc('sine', 165), g = gain(0);
        a.frequency.setValueAtTime(165, t); a.frequency.exponentialRampToValueAtTime(42, t + 0.13);
        this.env(g, t, 0.002, 0.85 * vol, 0.34); a.connect(g); g.connect(out); a.start(t); a.stop(t + 0.42);
        const ns = noiseSrc(), hp = filt('highpass', 2800), ng = gain(0); this.env(ng, t, 0.001, 0.16 * vol, 0.018);
        ns.connect(hp); hp.connect(ng); ng.connect(out); ns.start(t, Math.random() * 0.5); ns.stop(t + 0.05); break;
      }
      case 'snare': {
        const ns = noiseSrc(), bp = filt('bandpass', 1900, 0.8), g = gain(0); this.env(g, t, 0.001, 0.32 * vol, 0.17);
        ns.connect(bp); bp.connect(g); const n = this.pan(g, P); n.connect(out); send(n, 0.3);
        const b = osc('triangle', 200), bg = gain(0); b.frequency.setValueAtTime(200, t); b.frequency.exponentialRampToValueAtTime(140, t + 0.08);
        this.env(bg, t, 0.001, 0.22 * vol, 0.08); b.connect(bg); bg.connect(out);
        ns.start(t, Math.random() * 0.5); ns.stop(t + 0.3); b.start(t); b.stop(t + 0.15); break;
      }
      case 'hat': case 'ohat': {
        const open = inst === 'ohat';
        const ns = noiseSrc(), hp = filt('highpass', open ? 6500 : 7800), g = gain(0); this.env(g, t, 0.001, (open ? 0.07 : 0.085) * vol, open ? 0.22 : 0.045);
        ns.connect(hp); hp.connect(g); const n = this.pan(g, P || (open ? 0.2 : -0.15)); n.connect(out); if (open) send(n, 0.2);
        ns.start(t, Math.random() * 0.5); ns.stop(t + (open ? 0.3 : 0.08)); break;
      }
      case 'tom': {
        const a = osc('sine', f), g = gain(0); a.frequency.setValueAtTime(f * 1.4, t); a.frequency.exponentialRampToValueAtTime(f * 0.75, t + 0.3);
        this.env(g, t, 0.003, 0.5 * vol, 0.38); a.connect(g); const n = this.pan(g, P); n.connect(out); send(n, 0.35); a.start(t); a.stop(t + 0.45); break;
      }
      case 'taiko': {
        const a = osc('sine', 110), g = gain(0); a.frequency.setValueAtTime(115, t); a.frequency.exponentialRampToValueAtTime(46, t + 0.4);
        this.env(g, t, 0.003, 0.8 * vol, 0.9); a.connect(g); g.connect(out); send(g, 0.55); a.start(t); a.stop(t + 1.0);
        const ns = noiseSrc(), lp = filt('lowpass', 520), ng = gain(0); this.env(ng, t, 0.002, 0.35 * vol, 0.25);
        ns.connect(lp); lp.connect(ng); ng.connect(out); send(ng, 0.4); ns.start(t, Math.random() * 0.5); ns.stop(t + 0.35); break;
      }
      case 'timp': {
        const a = osc('sine', f * 1.5), g = gain(0); a.frequency.setValueAtTime(f * 1.5, t); a.frequency.exponentialRampToValueAtTime(f, t + 0.08);
        this.env(g, t, 0.004, 0.55 * vol, 1.4); a.connect(g); g.connect(out); send(g, 0.5); a.start(t); a.stop(t + 1.6);
        const ns = noiseSrc(), lp = filt('lowpass', 700), ng = gain(0); this.env(ng, t, 0.002, 0.12 * vol, 0.12);
        ns.connect(lp); lp.connect(ng); ng.connect(out); ns.start(t, Math.random() * 0.5); ns.stop(t + 0.2); break;
      }
      case 'crash': {
        const ns = noiseSrc(), hp = filt('highpass', 4200), g = gain(0); this.env(g, t, 0.002, 0.13 * vol, 1.7);
        ns.connect(hp); hp.connect(g); g.connect(out); send(g, 0.45); ns.start(t, Math.random() * 0.5); ns.stop(t + 1.8); break;
      }
      case 'swell': { // reverse cymbal / air riser leading into the next bar
        const d = Math.max(dur, 0.3), ns = noiseSrc(), bp = filt('bandpass', 700, 1.4), g = gain(0);
        bp.frequency.setValueAtTime(700, t); bp.frequency.exponentialRampToValueAtTime(6500, t + d);
        g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(0.14 * Math.max(vol, 0.01), t + d); g.gain.linearRampToValueAtTime(0.0001, t + d + 0.06);
        ns.connect(bp); bp.connect(g); g.connect(out); send(g, 0.6); ns.start(t, Math.random() * 0.5); ns.stop(t + d + 0.1); break;
      }
    }
  },
  play(name) {
    if (!this.ctx) return;
    if (this.song && this.song.name === name) return;
    const next = SONGS[name]; if (!next) return;
    const now = this.ctx.currentTime;
    for (const [g, v] of [[this.music, this.musicVol], [this.mverb, this.musicVol * 2], [this.mecho, this.musicVol * 2]]) {
      g.gain.cancelScheduledValues(now); g.gain.setValueAtTime(0.0, now); g.gain.linearRampToValueAtTime(v, now + 1.2);
    }
    this.song = Object.assign({ name }, next); this.step = 0; this.nextT = now + 0.12;
  },
  stop() { this.song = null; },
  tick() {
    const c = this.ctx; if (!c || !this.song) return;
    const s = this.song, spb = 60 / s.bpm / 4;
    if (this.nextT < c.currentTime - 0.5) this.nextT = c.currentTime + 0.05; // tab was asleep: don't burst-play the backlog
    while (this.nextT < c.currentTime + 0.14) {
      const at = this.nextT;
      s.seq(this.step, at, spb, (inst, m, d, v, o) => this.voice(inst, m, at + ((o && o.at) || 0) * spb, d, v, null, o));
      this.step++; this.nextT += spb;
      if (s.once && this.step >= s.len) { this.song = null; if (s.then) this.play(s.then); return; }
    }
  },
  // one-shot effects
  fx(name, opt = {}) {
    const c = this.ctx; if (!c) return; const t = c.currentTime + 0.01; const o = this.sfx;
    const tone = (type, f0, f1, dur, vol, at = 0, verb = 0.25, pan = 0) => {
      const os = c.createOscillator(); os.type = type; os.frequency.setValueAtTime(f0, t + at); os.frequency.exponentialRampToValueAtTime(Math.max(f1, 1), t + at + dur);
      const g = c.createGain(); this.env(g, t + at, 0.005, vol, dur); os.connect(g); const n = this.pan(g, pan); n.connect(o); os.start(t + at); os.stop(t + at + dur + 0.05);
      if (verb > 0) { const sg = c.createGain(); sg.gain.value = verb; n.connect(sg); sg.connect(this.verb); }
    };
    const noise = (f0, f1, dur, vol, type = 'bandpass', at = 0, q = 1, verb = 0, pan = 0) => {
      const s = c.createBufferSource(); s.buffer = this.noiseBuf; s.loop = true;
      const bf = c.createBiquadFilter(); bf.type = type; bf.Q.value = q; bf.frequency.setValueAtTime(f0, t + at); bf.frequency.exponentialRampToValueAtTime(Math.max(f1, 20), t + at + dur);
      const g = c.createGain(); this.env(g, t + at, 0.01, vol, dur); s.connect(bf); bf.connect(g); const n = this.pan(g, pan); n.connect(o);
      if (verb > 0) { const sg = c.createGain(); sg.gain.value = verb; n.connect(sg); sg.connect(this.verb); }
      s.start(t + at, Math.random() * 0.5); s.stop(t + at + dur + 0.05);
    };
    // short low "body" thump that gives impacts weight
    const thump = (f0, f1, dur, vol, at = 0) => tone('sine', f0, f1, dur, vol, at, 0.06);
    const crack = (vol, at = 0) => noise(9000, 3500, 0.035, vol, 'highpass', at, 0.7);
    const sparkle = (base, n, step, vol, at = 0) => { for (let i = 0; i < n; i++) tone('sine', base * Math.pow(1.335, i), base * Math.pow(1.335, i) * 1.003, 0.35, vol, at + i * step, 0.55, (i % 2 ? 0.35 : -0.35)); };
    switch (name) {
      case 'select': tone('sine', 1320, 1320, 0.05, 0.11, 0, 0.12); tone('triangle', 2640, 2600, 0.03, 0.035, 0, 0); break;
      case 'confirm': tone('triangle', 784, 784, 0.08, 0.15, 0, 0.2); tone('sine', 1175, 1175, 0.22, 0.15, 0.06, 0.35); tone('sine', 2350, 2350, 0.16, 0.035, 0.06, 0.4); break;
      case 'back': tone('triangle', 660, 440, 0.12, 0.14, 0, 0.15); tone('sine', 330, 300, 0.1, 0.06); break;
      case 'talk': tone('square', 520 + Math.random() * 80, 500, 0.025, 0.028, 0, 0); tone('sine', 1040 + Math.random() * 120, 1000, 0.02, 0.02, 0, 0); break;
      case 'hit': noise(3200, 420, 0.18, 0.55, 'bandpass', 0, 0.8, 0.15); thump(150, 44, 0.24, 0.62); crack(0.28); tone('square', 210, 70, 0.1, 0.1, 0, 0.1); break;
      case 'crit': noise(5200, 280, 0.34, 0.8, 'bandpass', 0, 0.7, 0.3); thump(120, 30, 0.5, 0.9); crack(0.45); tone('sawtooth', 340, 40, 0.32, 0.24, 0, 0.3); noise(1600, 300, 0.6, 0.25, 'lowpass', 0.05, 1, 0.5); sparkle(1760, 3, 0.03, 0.03, 0.05); break;
      case 'weak': noise(1400, 480, 0.15, 0.32); thump(110, 70, 0.1, 0.22); break;
      case 'whoosh': noise(380, 3200, 0.28, 0.34, 'bandpass', 0, 2, 0.15, -0.4); noise(900, 5200, 0.22, 0.12, 'bandpass', 0.05, 3, 0, 0.4); break;
      case 'fire':
        noise(900, 170, 0.62, 0.55, 'lowpass', 0, 1, 0.25); noise(3200, 1100, 0.45, 0.2, 'bandpass', 0, 1, 0.2); thump(90, 40, 0.3, 0.35);
        for (let i = 0; i < 6; i++) noise(5000 + Math.random() * 3000, 2500, 0.03, 0.12 + Math.random() * 0.1, 'highpass', 0.05 + Math.random() * 0.45, 1, 0.1, rand(-0.6, 0.6));
        break;
      case 'water':
        noise(520, 2600, 0.45, 0.4, 'bandpass', 0, 3, 0.35); tone('sine', 300, 900, 0.3, 0.1, 0, 0.3);
        for (let i = 0; i < 5; i++) { const f = 500 + Math.random() * 700; tone('sine', f, f * 2.2, 0.06, 0.07, 0.08 + i * 0.07 + Math.random() * 0.04, 0.4, rand(-0.6, 0.6)); }
        break;
      case 'grass': noise(3000, 6500, 0.32, 0.24, 'highpass', 0, 1, 0.2); tone('triangle', 700, 1100, 0.2, 0.08, 0, 0.3); tone('sine', 1400, 1650, 0.25, 0.05, 0.08, 0.5, 0.3); break;
      case 'thunder': crack(0.6); noise(6000, 900, 0.12, 0.5, 'bandpass', 0, 0.8, 0.3); noise(4200, 80, 0.9, 0.7, 'lowpass', 0.03, 1, 0.5); tone('sawtooth', 95, 38, 0.6, 0.28, 0, 0.3); thump(80, 30, 0.7, 0.5, 0.04); break;
      case 'earth': noise(320, 55, 0.7, 0.85, 'lowpass', 0, 1, 0.3); thump(75, 26, 0.6, 0.75); noise(2400, 600, 0.35, 0.18, 'bandpass', 0.08, 1, 0.2); break;
      case 'light': for (let i = 0; i < 5; i++) tone('sine', 1200 + i * 300, 1600 + i * 300, 0.3, 0.055, i * 0.04, 0.5, (i - 2) * 0.25); noise(6000, 9000, 0.4, 0.06, 'highpass', 0, 1, 0.5); break;
      case 'shadow': tone('sawtooth', 220, 65, 0.55, 0.17, 0, 0.4); noise(800, 180, 0.55, 0.24, 'bandpass', 0, 1.5, 0.4); noise(2400, 700, 0.5, 0.08, 'bandpass', 0.1, 6, 0.6, 0.4); thump(70, 35, 0.4, 0.3); break;
      case 'void': tone('sine', 420, 28, 1.25, 0.45, 0, 0.5); noise(2000, 40, 1.15, 0.4, 'lowpass', 0, 1, 0.5); tone('sawtooth', 55, 28, 1.25, 0.15, 0, 0.3); thump(60, 24, 1.0, 0.5, 0.05); noise(300, 4000, 0.8, 0.06, 'bandpass', 0.2, 8, 0.7, -0.5); break;
      case 'genesis':
        for (let i = 0; i < 7; i++) tone('sine', 440 * Math.pow(1.26, i), 440 * Math.pow(1.26, i) * 1.01, 1.5, 0.065, i * 0.07, 0.7, (i - 3) * 0.2);
        noise(800, 6500, 1.2, 0.2, 'bandpass', 0, 1, 0.5); thump(90, 40, 0.8, 0.45); break;
      case 'aura': tone('sine', 300, 900, 0.5, 0.14, 0, 0.5); tone('triangle', 450, 1350, 0.5, 0.05, 0.03, 0.5, 0.3); noise(2000, 6000, 0.5, 0.05, 'bandpass', 0, 2, 0.5); break;
      case 'heal': for (let i = 0; i < 4; i++) { const f = 660 * Math.pow(1.25, i); tone('sine', f, f, 0.35, 0.09, i * 0.08, 0.6, (i - 1.5) * 0.3); tone('sine', f * 2, f * 2, 0.2, 0.025, i * 0.08 + 0.01, 0.6); } break;
      case 'faint': tone('triangle', 520, 75, 0.75, 0.24, 0, 0.4); noise(1200, 200, 0.6, 0.12, 'lowpass', 0.1, 1, 0.3); thump(90, 35, 0.4, 0.35, 0.5); break;
      case 'throw': noise(480, 2600, 0.35, 0.3, 'bandpass', 0, 3, 0.2); tone('sine', 600, 1100, 0.2, 0.04, 0.05, 0.3); break;
      case 'absorb': tone('sine', 200, 1400, 0.5, 0.22, 0, 0.5); sparkle(1320, 3, 0.07, 0.035, 0.25); break;
      case 'wobble': tone('triangle', 300, 220, 0.12, 0.24, 0, 0.15); noise(900, 400, 0.1, 0.2); thump(120, 80, 0.08, 0.2); break;
      case 'caught': [0, 4, 7, 12].forEach((s, i) => tone('triangle', this.mf(72 + s), this.mf(72 + s), 0.28, 0.17, i * 0.09, 0.35)); tone('sine', this.mf(96), this.mf(96), 0.6, 0.06, 0.36, 0.7); sparkle(2093, 4, 0.05, 0.025, 0.4); break;
      case 'break': noise(6500, 800, 0.4, 0.5, 'highpass', 0, 1, 0.3); tone('square', 600, 200, 0.2, 0.1); for (let i = 0; i < 5; i++) tone('sine', 2500 + Math.random() * 3000, 2400, 0.12, 0.04, Math.random() * 0.15, 0.4, rand(-0.6, 0.6)); break;
      case 'levelup': [0, 4, 7, 12, 16].forEach((s, i) => { tone('square', this.mf(76 + s), this.mf(76 + s), 0.15, 0.07, i * 0.07, 0.3); tone('sine', this.mf(88 + s), this.mf(88 + s), 0.25, 0.03, i * 0.07, 0.5); }); break;
      case 'encounter': tone('sawtooth', 220, 880, 0.35, 0.17, 0, 0.3); noise(200, 4500, 0.4, 0.3, 'bandpass', 0, 1, 0.3); thump(110, 40, 0.35, 0.5, 0.35); crack(0.25, 0.35); break;
      case 'fragment': [0, 7, 12, 19, 24].forEach((s, i) => tone('sine', this.mf(67 + s), this.mf(67 + s), 0.9, 0.11, i * 0.12, 0.7, (i - 2) * 0.25)); noise(5000, 9000, 1.0, 0.04, 'highpass', 0.2, 1, 0.6); break;
      case 'rumble': noise(140, 40, 2.5, 0.9, 'lowpass', 0, 1, 0.3); tone('sine', 50, 28, 2.4, 0.5); break;
      case 'step': noise(900, 500, 0.05, 0.05); break;
      case 'stepStone': noise(3200, 1600, 0.035, 0.06, 'bandpass', 0, 2.5); tone('sine', 190, 120, 0.04, 0.025, 0, 0); break;
      case 'stepGrass': noise(2600, 5200, 0.14, 0.045, 'highpass'); break;
      case 'roar': {
        const os = c.createOscillator(); os.type = 'sawtooth'; os.frequency.setValueAtTime(140, t); os.frequency.linearRampToValueAtTime(220, t + 0.25); os.frequency.exponentialRampToValueAtTime(55, t + 1.6);
        const lfo = c.createOscillator(); lfo.frequency.value = 23; const lg = c.createGain(); lg.gain.value = 30; lfo.connect(lg); lg.connect(os.frequency);
        const lp = c.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.setValueAtTime(900, t); lp.frequency.exponentialRampToValueAtTime(260, t + 1.6);
        const g = c.createGain(); this.env(g, t, 0.06, 0.55, 1.6); os.connect(lp); lp.connect(g); g.connect(o);
        const sg = c.createGain(); sg.gain.value = 0.6; g.connect(sg); sg.connect(this.verb);
        os.start(t); lfo.start(t); os.stop(t + 1.8); lfo.stop(t + 1.8); noise(600, 120, 1.4, 0.5, 'lowpass', 0, 1, 0.4); thump(70, 30, 1.2, 0.5, 0.05); break;
      }
      case 'whale': {
        for (const [f0, f1, d, at] of [[180, 320, 1.4, 0], [320, 140, 1.8, 1.2]]) {
          const os = c.createOscillator(); os.type = 'sine'; os.frequency.setValueAtTime(f0, t + at); os.frequency.exponentialRampToValueAtTime(f1, t + at + d);
          const vb = c.createOscillator(); vb.frequency.value = 5; const vg = c.createGain(); vg.gain.value = 6; vb.connect(vg); vg.connect(os.frequency);
          const g = c.createGain(); g.gain.setValueAtTime(0.0001, t + at); g.gain.linearRampToValueAtTime(0.32, t + at + 0.4); g.gain.linearRampToValueAtTime(0.0001, t + at + d);
          os.connect(g); g.connect(o); const sg = c.createGain(); sg.gain.value = 1.2; g.connect(sg); sg.connect(this.verb);
          os.start(t + at); vb.start(t + at); os.stop(t + at + d + 0.1); vb.stop(t + at + d + 0.1);
        }
        break;
      }
      case 'meteor': tone('sine', 2400, 300, 0.45, 0.12, 0, 0.3); noise(6000, 400, 0.45, 0.2, 'bandpass', 0, 4, 0.2); noise(300, 50, 0.6, 0.7, 'lowpass', 0.4, 1, 0.4); thump(90, 32, 0.6, 0.6, 0.4); crack(0.3, 0.4); break;
      case 'boom': noise(200, 40, 1.2, 1.0, 'lowpass', 0, 1, 0.4); thump(70, 24, 1.1, 0.75); crack(0.25); break;
      case 'chime': [0, 7, 12, 16, 19].forEach((s, i) => tone('sine', this.mf(79 + s), this.mf(79 + s), 1.3, 0.065, i * 0.06, 0.7, (i - 2) * 0.25)); break;
      case 'wave': noise(300, 1800, 1.3, 0.7, 'bandpass', 0, 0.8, 0.4); noise(5000, 2000, 1.2, 0.25, 'highpass', 0.3, 1, 0.4); thump(60, 30, 1.0, 0.3, 0.2); break;
    }
  },
};

// procedural songs (step = 16th note). v(inst, midi, durSec, vol, { pan, at, from }). Chord tables in MIDI.
// melody tables: per bar, [step, midi, lengthInSteps]
const _mel = (v, tbl, bar, s, spb, inst, vol, shift = 0, o) => { for (const [p, m, l] of tbl[bar] || []) if (s === p) v(inst, m + shift, spb * l, vol, o); };
const SONGS = {
  title: {
    bpm: 66,
    seq(st, t, spb, v) {
      const bar = Math.floor(st / 16) % 4, s = st % 16, cyc = Math.floor(st / 64) % 2;
      const ch = [[50, 57, 62, 66, 69], [47, 54, 59, 62, 66], [43, 50, 55, 59, 62], [45, 52, 57, 61, 64]][bar];
      if (s === 0) { v('pad', ch[1], spb * 16, 0.8, { pan: -0.3 }); v('pad', ch[3], spb * 16, 0.65, { pan: 0.3 }); v('strings', ch[2] + 12, spb * 16, 0.4); v('sub', ch[0] - 12, spb * 15, 0.5); }
      if (s % 2 === 0) { const arp = [ch[1], ch[2], ch[3], ch[4], ch[2] + 12, ch[3] + 12, ch[4] + 12, ch[3] + 12]; v('harp', arp[s / 2], spb * 3, 0.3, { pan: (s / 2 - 3.5) * 0.12 }); }
      if (cyc === 1 && (s === 0 || s === 6 || s === 8)) v('bell', ch[2 + ((s / 2 + bar) % 3)] + 12, spb * 6, 0.28);
      if (bar === 3 && s === 8) v('swell', 0, spb * 8, 0.5);
    },
  },
  world: {
    bpm: 92,
    seq(st, t, spb, v) {
      const bar = Math.floor(st / 16) % 8, s = st % 16, cyc = Math.floor(st / 128) % 2;
      const prog = [[50, 57, 62, 66, 69], [47, 54, 59, 62, 66], [43, 50, 55, 59, 62], [45, 52, 57, 61, 64], [50, 57, 62, 66, 69], [42, 49, 54, 57, 61], [43, 50, 55, 59, 62], [45, 52, 57, 61, 64]];
      const ch = prog[bar];
      if (s === 0) { v('pad', ch[1], spb * 16, 0.62, { pan: -0.35 }); v('pad', ch[3], spb * 16, 0.5, { pan: 0.35 }); v('strings', ch[2] + 12, spb * 16, 0.28); }
      if (s === 0) v('bass', ch[0] - 12, spb * 5, 0.58);
      if (s === 10) v('bass', ch[0] - 12, spb * 3, 0.42);
      if (s === 14) v('bass', ch[1] - 12, spb * 2, 0.32);
      if (s % 2 === 0) v('pluck', ch[[1, 2, 3, 4, 3, 2, 3, 4][(s / 2) % 8]] + 12, spb * 2, 0.42, { pan: (s / 2) % 2 ? 0.35 : -0.35 });
      // light hand-percussion groove
      if (s % 2 === 0) v('hat', 0, 0, s % 4 === 2 ? 0.32 : 0.16);
      if (cyc === 1 && (s === 0 || s === 8)) v('kick', 0, 0, 0.32);
      if (cyc === 1 && s === 12) v('snare', 0, 0, 0.14);
      if (cyc === 0) {
        const mel = [[0, 74], [6, 76], [8, 78], [12, 81]];
        if (bar % 4 === 1) for (const [p, m] of mel) if (s === p) v('bell', m, spb * 4, 0.28);
        if (bar % 4 === 3 && s === 0) v('bell', 81, spb * 8, 0.28);
        if (bar % 4 === 3 && s === 8) v('bell', 78, spb * 8, 0.23);
      } else {
        _mel(v, [
          [[0, 74, 6], [6, 76, 2], [8, 78, 4], [12, 81, 4]], [[0, 78, 6], [6, 76, 2], [8, 74, 4], [12, 71, 4]],
          [[0, 71, 4], [4, 74, 4], [8, 79, 6], [14, 78, 2]], [[0, 76, 8], [8, 73, 4], [12, 76, 4]],
          [[0, 74, 6], [6, 76, 2], [8, 78, 4], [12, 81, 4]], [[0, 85, 6], [6, 83, 2], [8, 81, 4], [12, 78, 4]],
          [[0, 79, 4], [4, 78, 4], [8, 76, 4], [12, 74, 4]], [[0, 76, 6], [6, 74, 2], [8, 73, 8]],
        ], bar, s, spb, 'flute', 0.55);
        if (s === 4 && bar % 2 === 1) v('celesta', ch[4] + 12, spb * 4, 0.18, { pan: 0.4 });
      }
      if (bar === 7 && s === 8) v('swell', 0, spb * 8, 0.3);
    },
  },
  battle: {
    bpm: 152,
    seq(st, t, spb, v) {
      const bar = Math.floor(st / 16) % 8, s = st % 16, cyc = Math.floor(st / 128) % 2;
      const r = [45, 41, 43, 40, 45, 41, 38, 40][bar];
      const minor = (r === 45 || r === 40 || r === 38) ? 3 : 4;
      // syncopated bass + drum groove
      const bl = { 0: 0, 3: 0, 6: 12, 8: 0, 10: 7, 11: 0, 14: 12 };
      if (bl[s] !== undefined) v('bass', r - 12 + bl[s], spb * (s === 0 ? 2 : 1.3), s === 0 || s === 8 ? 0.95 : 0.7);
      if (s === 0 || s === 6 || s === 8 || (s === 11 && bar % 2)) v('kick', 0, 0, s === 0 ? 1 : 0.82);
      if (s === 4 || s === 12) v('snare', 0, 0, 0.75);
      if (bar % 2 === 1 && (s === 7 || s === 15)) v('snare', 0, 0, 0.16);
      v(s === 14 ? 'ohat' : 'hat', 0, 0, s % 4 === 2 ? 0.62 : s % 2 === 0 ? 0.42 : 0.22);
      if (bar === 0 && s === 0) v('crash', 0, 0, 0.75);
      // brass stabs on the push, strings under the lead
      if (bar < 4 && (s === 0 || s === 3 || s === 10)) { const d = spb * (s === 10 ? 3 : 1.4); v('brass', r + 12, d, 0.42, { pan: -0.25 }); v('brass', r + 19, d, 0.34, { pan: 0.25 }); v('brass', r + 12 + minor, d, 0.26); }
      if (bar >= 4 && s === 0) { v('strings', r + 12 + minor, spb * 16, 0.45, { pan: -0.3 }); v('strings', r + 19, spb * 16, 0.4, { pan: 0.3 }); }
      if (s === 0) v('pad', r + 12 + minor, spb * 16, 0.35);
      const arp = [0, 7, 12, minor + 12, 7, 12, minor + 24, 12];
      v('pluck', r + 12 + arp[s % 8], spb * 1.2, 0.2, { pan: s % 2 ? 0.45 : -0.45 });
      const lead = cyc === 0 ? [[0, 76], [3, 79], [6, 81], [8, 79], [10, 76], [12, 74]] : [[0, 81], [2, 79], [4, 76], [6, 79], [8, 84], [11, 83], [14, 79]];
      if (bar % 2 === 0 && bar >= 4) for (const [p, m] of lead) if (s === p) { v('lead', m - (bar === 6 ? 2 : 0), spb * 2.5, 0.42); v('brass', m - 12 - (bar === 6 ? 2 : 0), spb * 2.5, 0.18); }
      if ((bar === 5 || bar === 7) && (s === 8 || s === 10 || s === 12)) v('lead', r + 24 + [7, minor + 12, 12][(s - 8) / 2], spb * 2, 0.26, { pan: 0.3 });
      if (bar === 7 && s >= 12) v('tom', [55, 52, 48, 45][s - 12], spb * 2, 0.7, { pan: [-0.4, -0.1, 0.1, 0.4][s - 12] });
      if (bar === 3 && s === 8) v('swell', 0, spb * 8, 0.45);
    },
  },
  void: {
    bpm: 72,
    seq(st, t, spb, v) {
      const bar = Math.floor(st / 16) % 4, s = st % 16, cyc = Math.floor(st / 64) % 2;
      const r = [37, 33, 38, 36][bar];
      if (s === 0) {
        v('drone', r - 12, spb * 16, 0.85);
        v('choir', r + 24, spb * 16, 0.8, { pan: -0.3 }); v('choir', r + 27, spb * 16, 0.62, { pan: 0.3 }); v('choir', r + 31 + (bar === 3 ? 1 : 0), spb * 16, 0.5);
        if (cyc) v('choir', r + 25, spb * 16, 0.26, { pan: 0.5 });
        v('sub', r - 12, spb * 14, 0.6); v('taiko', 0, 0, 1);
      }
      if (s === 3) v('taiko', 0, 0, 0.5);
      if (s === 8 || s === 14) v('timp', r - 12, 0, 0.7);
      if (s % 4 === 2) v('pluck', r + 24 + [0, 3, 7, 6][(s / 4 | 0) % 4], spb * 3, 0.26, { pan: [-0.5, 0.5, -0.2, 0.2][(s / 4 | 0) % 4] });
      if (s === 6 && bar % 2) v('bell', r + 36 + 6, spb * 8, 0.32);
      if (s % 2 === 0) v('hat', 0, 0, 0.26);
      if (s === 4 || s === 12) v('snare', 0, 0, 0.4);
      if (bar === 3 && s === 8) v('swell', 0, spb * 8, 0.7);
    },
  },
  being: {
    bpm: 80,
    seq(st, t, spb, v) {
      const bar = Math.floor(st / 16) % 4, s = st % 16, cyc = Math.floor(st / 64) % 2;
      const ch = [[40, 52, 56, 59, 64], [47, 54, 59, 63, 66], [37, 49, 52, 56, 61], [45, 52, 57, 61, 64]][bar];
      if (s === 0) {
        v('choir', ch[2] + 12, spb * 16, 0.72, { pan: -0.3 }); v('choir', ch[3] + 12, spb * 16, 0.62, { pan: 0.3 }); v('pad', ch[1], spb * 16, 0.6);
        v('sub', ch[0] - 12, spb * 16, 0.6); v('timp', ch[0] - 12, 0, 0.9); v('brass', ch[0], spb * 6, 0.32, { pan: -0.2 }); v('brass', ch[1], spb * 6, 0.28, { pan: 0.2 });
      }
      const arp = [ch[1], ch[2], ch[3], ch[4], ch[2] + 12, ch[3] + 12, ch[4] + 12, ch[3] + 12];
      v('harp', arp[s % 8] + (s >= 8 ? 12 : 0), spb * 2, 0.18, { pan: ((s % 8) - 3.5) * 0.12 });
      if (s === 4 || s === 12) v('bell', ch[1 + ((s / 4 + bar) % 4)] + 24, spb * 4, 0.18);
      if (s === 8) v('timp', ch[0] - 12, 0, 0.55);
      if (bar === 3 && s >= 12) v('timp', ch[0] - 12, 0, 0.3 + (s - 12) * 0.14);
      if (s % 4 === 2) v('hat', 0, 0, 0.24);
      if (cyc === 1) {
        const tbl = [[[0, 76, 8], [8, 78, 4], [12, 80, 4]], [[0, 78, 8], [8, 75, 8]], [[0, 76, 4], [4, 73, 4], [8, 80, 8]], [[0, 81, 8], [8, 80, 4], [12, 78, 4]]];
        _mel(v, tbl, bar, s, spb, 'strings', 0.6); _mel(v, tbl, bar, s, spb, 'flute', 0.3, 12);
      }
    },
  },
  star: {
    bpm: 68,
    seq(st, t, spb, v) {
      const bar = Math.floor(st / 16) % 4, s = st % 16, cyc = Math.floor(st / 64) % 2;
      const ch = [[50, 57, 64, 66, 71], [48, 55, 62, 64, 69], [53, 60, 67, 69, 74], [52, 59, 66, 68, 73]][bar];
      if (s === 0) { v('pad', ch[1], spb * 16, 0.55, { pan: -0.4 }); v('pad', ch[2], spb * 16, 0.45, { pan: 0.4 }); v('choir', ch[3] + 12, spb * 16, 0.42); v('sub', ch[0] - 12, spb * 16, 0.45); }
      if (s % 2 === 0) { const n = ch[(s / 2 + bar) % 5]; v('celesta', n + (n > 64 ? 12 : 24), spb * 3, 0.3, { pan: (s / 2) % 2 ? 0.45 : -0.45 }); }
      if (s === 6 || s === 14) v('bell', ch[4] + 31, spb * 6, 0.13);
      if (cyc === 1) _mel(v, [[[0, 78, 6], [6, 81, 2], [8, 83, 8]], [[0, 79, 8], [8, 76, 8]], [[0, 81, 6], [6, 79, 2], [8, 77, 4], [12, 74, 4]], [[0, 76, 8], [8, 80, 8]]], bar, s, spb, 'flute', 0.42);
      if (bar === 3 && s === 8) v('swell', 0, spb * 8, 0.3);
    },
  },
  abyss: {
    bpm: 58,
    seq(st, t, spb, v) {
      const bar = Math.floor(st / 16) % 4, s = st % 16, cyc = Math.floor(st / 64) % 2;
      const r = [38, 34, 36, 33][bar];
      if (s === 0) { v('drone', r - 12, spb * 16, 0.9); v('choir', r + 12, spb * 16, 0.7, { pan: -0.3 }); v('choir', r + 19, spb * 16, 0.52, { pan: 0.3 }); v('sub', r - 12, spb * 16, 0.7); v('taiko', 0, 0, 0.7); }
      if (s === 10) v('timp', r - 12, 0, 0.45);
      if (s % 4 === 2) v('pluck', r + 24 + [0, 3, 7, 10][(s / 4 | 0) % 4], spb * 4, 0.2, { pan: [-0.4, 0.4, -0.1, 0.1][(s / 4 | 0) % 4] });
      const drip = [3, 7, 13].indexOf(s);
      if (drip >= 0 && (bar + s) % 3 !== 0) v('celesta', r + 36 + [0, 7, 3][drip], spb * 2, 0.13, { pan: [-0.6, 0.6, 0.2][drip] });
      if (bar % 2 === 1 && s === 0) v('glide', r + 26, spb * 12, 0.34, { from: r + 19, pan: -0.2 });
      if (cyc && bar === 2 && s === 4) v('glide', r + 31, spb * 10, 0.26, { from: r + 36, pan: 0.3 });
      if (s === 8 && bar % 2 === 0) v('bell', r + 36, spb * 10, 0.2);
    },
  },
  dawn: {
    bpm: 128,
    seq(st, t, spb, v) {
      const bar = Math.floor(st / 16) % 8, s = st % 16;
      const prog = [[45, 57, 61, 64], [41, 53, 57, 60], [43, 55, 59, 62], [40, 52, 56, 59], [45, 57, 61, 64], [38, 50, 54, 57], [41, 53, 57, 60], [43, 55, 59, 62]];
      const ch = prog[bar];
      // galloping war drums
      if (s === 0 || s === 8) v('kick', 0, 0, 0.85);
      if (s === 0) v('taiko', 0, 0, 0.6);
      if (s === 3 || s === 6 || s === 11 || s === 14) v('tom', s < 8 ? 50 : 45, spb * 2, 0.38, { pan: s < 8 ? -0.3 : 0.3 });
      if (s === 0 || s === 6 || s === 10) v('timp', ch[0] - 12, 0, s === 0 ? 0.9 : 0.6);
      if (s === 4 || s === 12) v('snare', 0, 0, 0.55);
      if (s % 2 === 1) v('hat', 0, 0, 0.4);
      if (bar === 0 && s === 0) v('crash', 0, 0, 0.7);
      if (bar === 7 && s >= 12) v('snare', 0, 0, 0.25 + (s - 12) * 0.15);
      v('bass', ch[0] - 12 + (s % 4 === 2 ? 12 : 0), spb * 1.5, s % 4 === 0 ? 0.8 : 0.5);
      if (s % 2 === 0) v('pluck', ch[1 + ((s / 2) % 3)] + 12, spb * 1.5, 0.16, { pan: (s / 2) % 2 ? 0.4 : -0.4 });
      if (s === 0) { v('pad', ch[1] + 12, spb * 16, 0.55, { pan: -0.3 }); v('pad', ch[2] + 12, spb * 16, 0.45, { pan: 0.3 }); v('strings', ch[3] + 12, spb * 16, 0.32); }
      const mel = bar % 2 === 0 ? [[0, 76], [3, 79], [6, 81], [8, 83], [12, 81]] : [[0, 79], [4, 76], [8, 74], [12, 76]];
      for (const [p, m] of mel) if (s === p) { v('brass', m, spb * 3, 0.5); v('brass', m - 4, spb * 3, 0.26); if (bar >= 4) v('flute', m + 12, spb * 3, 0.35); }
    },
  },
  limina: {
    bpm: 92,
    seq(st, t, spb, v) {
      const bar = Math.floor(st / 16) % 8, s = st % 16;
      const voidBar = Math.floor(bar / 2) % 2 === 1;
      const ch = voidBar ? [[37, 49, 52, 56], [33, 45, 48, 52]][bar % 2] : [[40, 52, 56, 59], [45, 57, 61, 64]][bar % 2];
      if (s === 0) {
        v('choir', ch[2] + 12, spb * 16, 0.68, { pan: -0.3 }); v('choir', ch[3] + 12, spb * 16, 0.55, { pan: 0.3 });
        if (voidBar) v('drone', ch[0] - 12, spb * 16, 0.6); else v('pad', ch[0] + 12, spb * 16, 0.55);
        v('sub', ch[0] - 12, spb * 16, 0.6); v(voidBar ? 'taiko' : 'timp', ch[0] - 12, 0, 0.9);
      }
      if (s === 8) v('timp', ch[0] - 12, 0, 0.6);
      if (s === 0 || s === 10) v('kick', 0, 0, 0.55);
      if (s % 2 === 0) v(voidBar ? 'pluck' : 'harp', ch[1 + ((s / 2) % 3)] + 24, spb * 2.5, voidBar ? 0.26 : 0.24, { pan: (s / 2) % 2 ? 0.4 : -0.4 });
      if (!voidBar && (s === 4 || s === 12)) v('bell', ch[3] + 24, spb * 6, 0.15);
      if (voidBar && s === 6) v('bell', ch[0] + 42, spb * 8, 0.2);
      if (s === 4 || s === 12) v('snare', 0, 0, 0.35);
      if (s % 2 === 1) v('hat', 0, 0, 0.28);
      if (bar % 2 === 1 && s === 8) v('swell', 0, spb * 8, 0.4);
    },
  },
  victory: {
    bpm: 140, once: true, len: 32, then: 'world',
    seq(st, t, spb, v) {
      const notes = { 0: 72, 2: 76, 4: 79, 6: 84, 10: 83, 12: 84 };
      if (notes[st] !== undefined) { const d = spb * (st === 12 ? 12 : 2); v('brass', notes[st], d, 0.5); v('lead', notes[st] + 12, d, 0.2); }
      if (st === 0 || st === 12) { v('pad', 60, spb * 12, 0.6, { pan: -0.3 }); v('pad', 64, spb * 12, 0.5, { pan: 0.3 }); v('strings', 67, spb * 12, 0.35); v('bass', 48, spb * 10, 0.7); v('timp', 36, 0, 0.9); }
      if (st === 12) v('crash', 0, 0, 0.6);
      if (st % 2 === 0 && st < 12) v('snare', 0, 0, 0.2 + st * 0.03);
      if (st >= 14 && st < 30 && st % 2 === 0) v('harp', [72, 76, 79, 84, 88, 84, 79, 76][(st - 14) / 2], spb * 3, 0.2, { pan: ((st - 14) / 2 - 3.5) * 0.12 });
    },
  },
};
