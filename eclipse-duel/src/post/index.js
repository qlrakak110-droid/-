// Post-processing pipeline: HDR scene (+ depth) -> AO / light shafts / DOF / bloom -> composite (fog, grade, screen FX).
// Full reference with option tables and examples: src/post/README.md. Budgets per tier: CONTRACT.md "Post and quality".
//
//   const post = createPost(ctx)                 (createApp does this: ctx.post; it also creates ctx.shadows)
//   post.fx                 live parameters (DEFAULT_FX + colour keys). Set them for a persistent look ...
//   post.to({...}, s)       ... or tween persistent values over s real seconds (numbers and colour keys)
//   post.pulse(k, a, o)     transient additive spike on a numeric key (chroma / radial / exposure / bloom / ao ...)
//   post.flash(c, a, o)     full-screen colour flash;   post.impactFrame({ duration, invert, mono })
//   post.grade(name|{...}, s)   colour grade: 'night' (default) | 'eclipse' | 'ember' | 'frost' | 'storm' | 'victory' | 'neutral'
//   post.setSun(dirOrPos, color, strength, { point })   the light the fog scatters and the light shafts radiate from
//   post.fog({ density, falloff, haze, ... }, s)        height + distance fog with sun in-scattering and point-light glow
//   post.fogLights(list | null)                        explicit fog lights, null = the scene's strongest PointLights
//   post.shafts({ strength, threshold, ... })          screen-space light shafts (god rays) from the sun
//   post.dof({ focus, aperture, range, near }, s) / post.dof(null, s)   cinematic depth of field (off by default)
//   post.distortionScene    meshes drawn with the main camera into a half-res buffer: fragment .rg = screen UV offset
//   post.onAfterScene(fn)   fn(renderer, sceneTarget, camera) right after the scene render (MSAA resolved, depth valid)
//   post.depthTexture       THREE.DepthTexture of the current frame's scene (raw [0,1]; valid in onAfterScene and later)
//   post.depthUniforms      { tSceneDepth, uSceneRes, uCamNearFar, uCamProj } stable uniform objects for ShaderMaterials
//   post.DEPTH_GLSL         helpers for in-scene materials: edSceneDepth(), edFragDepth(), edSoftFade(softness)
//
// The scene is rendered in linear HDR (half float). Emissive / VFX colours above 1.0 feed the bloom; tone mapping (ACES),
// sRGB encoding and the grade happen in the composite, so every material in the scene stays linear.
// Per-tier features come from ctx.quality (depth, ao, fog, shafts, dof: see src/core/util.js); every program is compiled
// in prewarm() at start-up, runtime toggles are uniforms (no shader compiles mid-fight).

import * as THREE from 'three';
import { clamp, ease as resolveEase } from '../core/math.js';
import * as G from './shaders.js';
import { GRADES, GRADE_COLOR_KEYS } from './grade.js';

export { GRADES };

export const DEFAULT_FX = {
  bloom: 1.0,           // bloom strength
  bloomThreshold: 1.0,  // HDR luminance where bloom starts
  bloomKnee: 0.6,
  bloomRadius: 1.0,
  exposure: 1.0,
  chroma: 0.0,          // chromatic aberration 0..1 (pulse to ~0.6-1 on heavy hits)
  radial: 0.0,          // radial blur 0..1 toward radialCenter
  vignette: 0.32,
  grain: 0.03,
  saturation: 1.0,
  contrast: 1.0,
  flash: 0.0,           // 0..1 mix toward flashColor
  invert: 0.0,          // 0..1 (impact frames)
  mono: 0.0,            // 0..1 high-contrast monochrome (impact frames)
  letterbox: 0.0,       // 0..1 cinematic bars
  distortion: 1.0,      // distortion buffer scale
  ao: 1.0,              // ambient-occlusion strength 0..1.5 (tiers with quality.ao)
  fog: 1.0,             // post fog opacity scale 0..2 (tiers with quality.fog)
  shafts: 1.0,          // light-shaft strength scale 0..3 (tiers with quality.shafts)
  sharpen: 0.0,         // extra sharpening 0..1 (dynamic resolution adds its own below 100 %)
  toneAmount: GRADES.night.toneAmount,   // split-toning strength
  toneBalance: GRADES.night.toneBalance, // split-toning crossover -1..1
};
const NUM_KEYS = Object.keys(DEFAULT_FX);
/** Colour-valued fx keys (tweened by post.to as THREE.Color; arrays are linear rgb, hex / css are sRGB). */
export const COLOR_KEYS = ['tint', 'lift', ...GRADE_COLOR_KEYS];

const setColor = (out, v) => {
  if (v === undefined || v === null) return out;
  if (v.isColor) return out.copy(v);
  if (Array.isArray(v)) return out.setRGB(v[0], v[1], v[2]);
  if (typeof v === 'object' && 'r' in v) return out.setRGB(v.r, v.g, v.b);
  return out.set(v);
};
const setVec3 = (out, v) => (Array.isArray(v) ? out.set(v[0], v[1], v[2]) : out.copy(v));

const FOG_DEFAULTS = {
  density: 0.026,       // 1/m extinction at the floor
  falloff: 0.55,        // 1/m: density halves every ~1.3 m of height (ground mist)
  haze: 0.0032,         // 1/m height-independent haze
  maxOpacity: 0.62,     // cap of the fog opacity
  floorY: 0,            // m
  start: 1.5,           // m: no fog closer than this to the camera
  far: 36,              // m: the fog integrates up to here (the arena's own shaders fog the far distance)
  skyDistance: 60,      // m: sky pixels count as this far
  color: [0.0045, 0.0055, 0.0085],   // ambient in-scatter (linear HDR)
  sunPhase: 0.8,        // Henyey-Greenstein g of the sun lobe (forward scattering)
  sunScatter: 0.006,    // sun colour * strength * this = in-scatter of the lobe
  lightScale: 1.0,      // point-light glow multiplier (physical: candela * density / 4pi)
  lightRadius: 0.35,    // m: core radius of a fog light (avoids the 1/d singularity)
  dim: 0,               // 0..1 manual mood dimming (added to the env mood when auto)
};
const SHAFT_DEFAULTS = {
  strength: 0.55,       // HDR multiplier of the shafts
  threshold: 0.32,      // scene brightness above which a far pixel radiates
  radius: 0.62,         // uv (aspect-corrected) around the sun that radiates
  length: 0.9,          // fraction of the way to the sun each pixel samples
  decay: 0.965,         // per-sample weight decay
  glow: 0.35,           // synthetic sun glow added to the mask (a dark eclipse disc still radiates)
  skyDepth: 26,         // m: pixels farther than this (to 2x) count as sky / far backdrop
};

export function createPost(ctx) {
  const renderer = ctx.renderer;
  const q = ctx.quality;
  const hdr = renderer.extensions.has('EXT_color_buffer_float') || renderer.extensions.has('EXT_color_buffer_half_float');
  const texType = hdr ? THREE.HalfFloatType : THREE.UnsignedByteType;
  // depth consumers need a float colour target for the linear-depth / AO buffers
  const T = {
    depth: !!q.depth && hdr,
    ao: hdr && q.depth ? q.ao | 0 : 0,
    fog: hdr && q.depth ? q.fog | 0 : 0,
    shafts: hdr && q.depth ? q.shafts | 0 : 0,
    dof: hdr && q.depth ? q.dof | 0 : 0,
  };
  const FOG_LIGHTS = T.fog >= 2 ? 4 : T.fog >= 1 ? 2 : 0;

  const fx = { ...DEFAULT_FX, radialCenter: new THREE.Vector2(0.5, 0.5), flashColor: new THREE.Color(1, 1, 1) };
  const baseline = { ...DEFAULT_FX };
  for (const k of COLOR_KEYS) { fx[k] = new THREE.Color(); baseline[k] = new THREE.Color(); }
  fx.tint.setRGB(1, 1, 1); fx.lift.setRGB(0, 0, 0);
  for (const k of GRADE_COLOR_KEYS) setColor(fx[k], GRADES.night[k]);
  for (const k of COLOR_KEYS) baseline[k].copy(fx[k]);
  if (!hdr) { fx.bloomThreshold = baseline.bloomThreshold = 0.82; }

  const fog = { ...FOG_DEFAULTS, color: setColor(new THREE.Color(), FOG_DEFAULTS.color) };
  const shaft = { ...SHAFT_DEFAULTS };
  const sun = { dir: new THREE.Vector3(0, 0.1, -1).normalize(), pos: new THREE.Vector3(), point: false, color: new THREE.Color(0.82, 0.9, 1.0), strength: 1, auto: true };
  const dofS = { focus: 6, target: null, range: 0.6, near: 1, aperture: 0, from: 0, to: 0, t: 0, dur: 0, ease: resolveEase('inOutSine') };

  const mkRT = (w, h, opts = {}) => new THREE.WebGLRenderTarget(Math.max(1, w), Math.max(1, h), {
    type: texType, format: THREE.RGBAFormat, minFilter: THREE.LinearFilter, magFilter: THREE.LinearFilter,
    depthBuffer: false, stencilBuffer: false, generateMipmaps: false, ...opts,
  });

  const fsGeo = new THREE.BufferGeometry();
  fsGeo.setAttribute('position', new THREE.BufferAttribute(new Float32Array([-1, -1, 0, 3, -1, 0, -1, 3, 0]), 3));
  fsGeo.setAttribute('uv', new THREE.BufferAttribute(new Float32Array([0, 0, 2, 0, 0, 2]), 2));
  const fsCam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
  const fsMesh = new THREE.Mesh(fsGeo, null);
  fsMesh.frustumCulled = false;
  const fsScene = new THREE.Scene();
  fsScene.add(fsMesh);
  const mkMat = (frag, uniforms, extra = {}) => new THREE.ShaderMaterial({ vertexShader: G.VERT, fragmentShader: frag, uniforms, depthTest: false, depthWrite: false, toneMapped: false, ...extra });
  const v2 = () => ({ value: new THREE.Vector2() });

  // ---- materials ----------------------------------------------------------------------------------------------------
  const mPre = mkMat(G.PREFILTER, { tSrc: { value: null }, uTexel: v2(), uThreshold: { value: 1 }, uKnee: { value: 0.5 } });
  const mDown = mkMat(G.DOWN, { tSrc: { value: null }, uTexel: v2() });
  const mUp = mkMat(G.UP, { tSrc: { value: null }, uTexel: v2(), uRadius: { value: 1 }, uWeight: { value: 1 } }, { blending: THREE.AdditiveBlending, transparent: true });
  const uNearFar = { value: new THREE.Vector2(0.1, 800) };
  const uProj = { value: new THREE.Vector4(1, 1, 0, 0) };
  const mDepth = T.depth ? mkMat(G.DEPTH_DOWN, { tDepth: { value: null }, uTexel: v2(), uNearFar }) : null;
  const AO_TIER = T.ao >= 2 ? { n: 10, blur: 3 } : { n: 6, blur: 2 };
  const mAO = T.ao ? mkMat(G.AO, { tDepthH: { value: null }, uTexel: v2(), uRes: v2(), uProj, uAo: { value: new THREE.Vector4(0.55, 1.0, 0.002, 24) }, uFadeFar: { value: 40 } }, { defines: { AO_N: AO_TIER.n } }) : null;
  const mAOBlur = T.ao ? mkMat(G.AO_BLUR, { tSrc: { value: null }, uDir: v2() }, { defines: { AO_BLUR_R: AO_TIER.blur } }) : null;
  const uSunUv = { value: new THREE.Vector2(0.5, 0.8) };
  const SHAFT_N = T.shafts >= 2 ? 16 : 20;
  const mShaftMask = T.shafts ? mkMat(G.SHAFT_MASK, { tScene: { value: null }, tDepthH: { value: null }, uSunUv, uAspect: { value: 1 }, uShaftP: { value: new THREE.Vector4() }, uSunCol: { value: new THREE.Color() } }) : null;
  const mShaftBlur = T.shafts ? mkMat(G.SHAFT_BLUR, { tSrc: { value: null }, uSunUv, uLength: { value: 1 }, uDecay: { value: 0.96 } }, { defines: { SHAFT_N } }) : null;
  const uDof = { value: new THREE.Vector4(6, 0.6, 0, 1) };
  const DOF_N = T.dof >= 2 ? 32 : 16;
  const mDofPrep = T.dof ? mkMat(G.DOF_PREP, { tScene: { value: null }, tDepthH: { value: null }, uDof }) : null;
  const mDofGather = T.dof ? mkMat(G.DOF_GATHER, { tSrc: { value: null }, uTexel: v2(), uMaxR: { value: 8 } }, { defines: { DOF_N } }) : null;

  const U = {
    tScene: { value: null }, tBloom: { value: null }, tDist: { value: null }, uRes: { value: new THREE.Vector2(1, 1) }, uTime: { value: 0 },
    uBloom: { value: 1 }, uExposure: { value: 1 }, uChroma: { value: 0 }, uRadial: { value: 0 }, uVignette: { value: 0 }, uGrain: { value: 0 },
    uSat: { value: 1 }, uContrast: { value: 1 }, uInvert: { value: 0 }, uMono: { value: 0 }, uLetterbox: { value: 0 }, uDist: { value: 1 },
    uFlash: { value: 0 }, uUseDist: { value: 0 }, uHdr: { value: hdr ? 1 : 0 },
    uRadialCenter: { value: new THREE.Vector2(0.5, 0.5) }, uTint: { value: new THREE.Color(1, 1, 1) }, uLift: { value: new THREE.Color(0, 0, 0) }, uFlashColor: { value: new THREE.Color(1, 1, 1) },
    uSceneTexel: v2(), uSharpen: { value: 0 },
    uGLift: { value: new THREE.Color() }, uGGamma: { value: new THREE.Color() }, uGGain: { value: new THREE.Color() },
    uToneSh: { value: new THREE.Color() }, uToneHi: { value: new THREE.Color() }, uTone: v2(),
    uRay00: { value: new THREE.Vector3() }, uRay10: { value: new THREE.Vector3() }, uRay01: { value: new THREE.Vector3() },
    tDepth: { value: null }, uNearFar, uCamPos: { value: new THREE.Vector3() },
    tAO: { value: null }, uAoStr: { value: 0 },
    uFogA: { value: new THREE.Vector4() }, uFogB: { value: new THREE.Vector4() }, uFogCol: { value: new THREE.Color() },
    uSunDir: { value: new THREE.Vector3() }, uSunCol: { value: new THREE.Color() }, uSunG: { value: 0.7 }, uFogOn: { value: 0 },
    uFL: { value: Array.from({ length: Math.max(1, FOG_LIGHTS) }, () => new THREE.Vector4(0, -100, 0, 0.3)) },
    uFLc: { value: Array.from({ length: Math.max(1, FOG_LIGHTS) }, () => new THREE.Vector3()) },
    tShaft: { value: null }, uShaftTint: { value: new THREE.Color() }, uShaftOn: { value: 0 },
    tDof: { value: null }, uDof, uDofOn: { value: 0 }, uDebug: { value: 0 },
  };
  const defines = { FOG_LIGHTS };
  if (T.depth) defines.HAS_DEPTH = 1;
  if (T.ao) defines.HAS_AO = 1;
  if (T.fog) defines.HAS_FOG = 1;
  if (T.shafts) defines.HAS_SHAFTS = 1;
  if (T.dof) defines.HAS_DOF = 1;
  const mComp = mkMat(G.COMPOSITE, U, { vertexShader: G.VERT_RAY, defines });

  // ---- targets ------------------------------------------------------------------------------------------------------
  let rtScene = null, rtDist = null, mips = [];
  let rtDepthH = null, rtAO = null, rtAO2 = null, rtShaft = null, rtShaft2 = null, rtDof = null, rtDof2 = null;
  let cw = 1, ch = 1, renderScale = 1;
  const distortionScene = new THREE.Scene();
  const farTex = new THREE.DataTexture(new Uint16Array([THREE.DataUtils.toHalfFloat(800)]), 1, 1, THREE.RedFormat, THREE.HalfFloatType);
  farTex.needsUpdate = true;
  const depthUniforms = {
    tSceneDepth: { value: farTex },              // previous frame: half-res linear view depth (m) of the opaque scene
    uSceneRes: { value: new THREE.Vector2(1, 1) }, // scene target size in px (gl_FragCoord space of in-scene materials)
    uCamNearFar: uNearFar,                         // camera near / far
    uCamProj: uProj,                               // projection P[0], P[5], P[8], P[9]
  };

  function disposeTargets() {
    for (const r of [rtScene, rtDist, rtDepthH, rtAO, rtAO2, rtShaft, rtShaft2, rtDof, rtDof2]) if (r) r.dispose();
    for (const m of mips) m.dispose();
    mips = [];
  }
  function alloc() {
    const w = Math.max(2, Math.round(cw * renderScale)), h = Math.max(2, Math.round(ch * renderScale));
    disposeTargets();
    rtScene = mkRT(w, h, { depthBuffer: true, samples: q.msaa || 0 });
    if (T.depth) rtScene.depthTexture = new THREE.DepthTexture(w, h, THREE.UnsignedIntType);
    const hw = Math.ceil(w / 2), hh = Math.ceil(h / 2);
    rtDist = hdr ? mkRT(hw, hh) : null;
    rtDepthH = T.depth ? mkRT(hw, hh, { format: THREE.RedFormat }) : null;
    rtAO = T.ao ? mkRT(hw, hh, { format: THREE.RGFormat }) : null;
    rtAO2 = T.ao ? mkRT(hw, hh, { format: THREE.RGFormat }) : null;
    const qw = Math.ceil(w / 4), qh = Math.ceil(h / 4);
    rtShaft = T.shafts ? mkRT(qw, qh) : null;
    rtShaft2 = T.shafts ? mkRT(qw, qh) : null;
    rtDof = T.dof ? mkRT(hw, hh) : null;
    rtDof2 = T.dof ? mkRT(hw, hh) : null;
    let mw = hw, mh = hh;
    for (let i = 0; i < (q.bloomLevels || 5) && mw >= 4 && mh >= 4; i++) {
      mips.push(mkRT(mw, mh));
      mw = Math.ceil(mw / 2); mh = Math.ceil(mh / 2);
    }
    depthUniforms.uSceneRes.value.set(w, h);
    depthUniforms.tSceneDepth.value = rtDepthH ? rtDepthH.texture : farTex;
    depthValid = false;
  }
  let depthValid = false;

  function pass(mat, target) {
    fsMesh.material = mat;
    renderer.setRenderTarget(target);
    renderer.render(fsScene, fsCam);
  }

  // ---- transient pulses + persistent tweens -------------------------------------------------------------------------
  const pulses = [];
  const tweens = [];
  const eff = { ...DEFAULT_FX };
  const tmpColor = new THREE.Color();
  const clearCol = new THREE.Color();
  const tmpV = new THREE.Vector3(), tmpV2 = new THREE.Vector3(), camPos = new THREE.Vector3(), camFwd = new THREE.Vector3();

  /** Replace / add a tween of obj[key] (number or THREE.Color) toward `to`. */
  function tween(obj, key, to, duration, easing) {
    for (let i = tweens.length - 1; i >= 0; i--) if (tweens[i].obj === obj && tweens[i].key === key) tweens.splice(i, 1);
    const color = obj[key] && obj[key].isColor;
    const d = Math.max(1e-4, duration);
    if (color) tweens.push({ obj, key, color: true, from: obj[key].clone(), to: setColor(new THREE.Color(), to), t: 0, dur: d, ease: resolveEase(easing) });
    else tweens.push({ obj, key, from: obj[key], to, t: 0, dur: d, ease: resolveEase(easing) });
  }

  // ---- fog lights: the scene's point lights (cached list, rescanned every 2 s), strongest first ----------------------
  const pointLights = [];
  let lightScanAt = -1e9, frameNo = 0;
  let explicitLights = null;
  const visitLights = (o) => { if (o.isPointLight) pointLights.push(o); };
  const pick = new Array(Math.max(1, FOG_LIGHTS)).fill(null);
  const pickW = new Float64Array(Math.max(1, FOG_LIGHTS));
  const visibleChain = (o) => { for (; o; o = o.parent) if (!o.visible) return false; return true; };

  function updateFogLights(scene) {
    const FL = U.uFL.value, FLc = U.uFLc.value;
    const dim = 1 - 0.5 * atmoDim();
    const k = fog.lightScale * dim;
    if (explicitLights) {
      for (let i = 0; i < FOG_LIGHTS; i++) {
        const l = explicitLights[i];
        if (!l) { FLc[i].set(0, 0, 0); continue; }
        setVec3(tmpV, l.pos || [0, -100, 0]);
        FL[i].set(tmpV.x, tmpV.y, tmpV.z, l.radius ?? fog.lightRadius);
        setColor(tmpColor, l.color ?? [1, 0.6, 0.3]);
        FLc[i].set(tmpColor.r, tmpColor.g, tmpColor.b).multiplyScalar((l.intensity ?? 20) * k);
      }
      return;
    }
    if (frameNo - lightScanAt > 120) { pointLights.length = 0; scene.traverse(visitLights); lightScanAt = frameNo; }
    for (let i = 0; i < FOG_LIGHTS; i++) { pick[i] = null; pickW[i] = 0; }
    for (let j = 0; j < pointLights.length; j++) {
      const l = pointLights[j];
      const w = l.intensity * Math.max(l.color.r, l.color.g, l.color.b);
      if (!(w > 0.01) || !visibleChain(l)) continue;
      for (let i = 0; i < FOG_LIGHTS; i++) {
        if (w > pickW[i]) {
          for (let s = FOG_LIGHTS - 1; s > i; s--) { pick[s] = pick[s - 1]; pickW[s] = pickW[s - 1]; }
          pick[i] = l; pickW[i] = w;
          break;
        }
      }
    }
    for (let i = 0; i < FOG_LIGHTS; i++) {
      const l = pick[i];
      if (!l) { FLc[i].set(0, 0, 0); FL[i].set(0, -100, 0, fog.lightRadius); continue; }
      tmpV.setFromMatrixPosition(l.matrixWorld);
      FL[i].set(tmpV.x, tmpV.y, tmpV.z, fog.lightRadius);
      FLc[i].set(l.color.r, l.color.g, l.color.b).multiplyScalar(l.intensity * k);
    }
  }

  /** Mood dimming 0..1: the env's mood darkness (ultimates) plus fog.dim. */
  function atmoDim() {
    const m = ctx.env && ctx.env.uniforms && ctx.env.uniforms.uMood ? ctx.env.uniforms.uMood.value.w : 0;
    return clamp(m + fog.dim);
  }

  /** World-space view ray through an NDC corner, scaled to unit view depth (P = camPos + ray * linearDepth). */
  function viewRay(out, x, y, camera) {
    out.set(x, y, 0.5).unproject(camera).sub(camPos);
    return out.multiplyScalar(1 / Math.max(1e-6, out.dot(camFwd)));
  }

  function dofFocusDistance(camera) {
    const t = dofS.target;
    if (!t) return dofS.focus;
    if (typeof t === 'function') { const r = t(); if (typeof r === 'number') return r; setVec3(tmpV2, r); }
    else if (t.isObject3D) t.getWorldPosition(tmpV2);
    else setVec3(tmpV2, t);
    return Math.max(0.2, tmpV2.sub(camPos).dot(camFwd));
  }

  const afterScene = [];
  let hookPrev = null, hookScene = null;
  const shadowHook = (r, s, c, rt) => {
    if (hookPrev) hookPrev(r, s, c, rt);
    if (ctx.shadows && s === hookScene) ctx.shadows.update(s);
  };
  const stats = { passes: 0, msPost: 0 };

  const post = {
    fx, baseline, hdr, distortionScene,
    /** Features compiled for this tier: { depth, ao, fog, shafts, dof } (0 = off). */
    features: T,
    /** Live atmosphere parameters (prefer post.fog / post.shafts / post.setSun to change them). */
    atmosphere: { fog, shafts: shaft, sun },
    /** Register fn(renderer, sceneTarget, camera) called right after the HDR scene render each frame. Returns off(). */
    onAfterScene(fn) { afterScene.push(fn); return () => { const i = afterScene.indexOf(fn); if (i >= 0) afterScene.splice(i, 1); }; },
    get sceneTarget() { return rtScene; },
    /** Raw depth of the current frame's scene (THREE.DepthTexture, nearest filter); null on tiers without depth. */
    get depthTexture() { return rtScene ? rtScene.depthTexture || null : null; },
    /** Half-res linear view depth (m) of the last rendered frame (THREE.Texture, R16F); null on tiers without depth. */
    get linearDepth() { return rtDepthH ? rtDepthH.texture : null; },
    depthUniforms,
    DEPTH_GLSL: /* glsl */ `
uniform sampler2D tSceneDepth; uniform vec2 uSceneRes; uniform vec2 uCamNearFar;
float edSceneDepth() { return texture2D(tSceneDepth, gl_FragCoord.xy / uSceneRes).r; }
float edFragDepth() { return uCamNearFar.x * uCamNearFar.y / (uCamNearFar.y - gl_FragCoord.z * (uCamNearFar.y - uCamNearFar.x)); }
float edSoftFade(float softness) { return clamp((edSceneDepth() - edFragDepth()) / max(softness, 1e-3), 0.0, 1.0); }
`,
    stats,

    setSize(w, h) { cw = w; ch = h; alloc(); },
    setRenderScale(s) { s = clamp(s, 0.4, 1); if (Math.abs(s - renderScale) > 0.01) { renderScale = s; alloc(); } },
    get renderScale() { return renderScale; },

    /** Transient additive spike on a numeric fx key: rises over attack, holds, decays over release (real seconds). */
    pulse(key, amount, { attack = 0.015, hold = 0, release = 0.25 } = {}) {
      if (!(key in DEFAULT_FX)) return;
      pulses.push({ key, amount, attack, hold, release, t: 0 });
    },
    /** Full-screen colour flash (colour: THREE.Color | hex | css string). */
    flash(color = 0xffffff, amount = 1, opts = {}) {
      fx.flashColor.set(color);
      post.pulse('flash', amount, { attack: 0.0, hold: 0.02, release: 0.22, ...opts });
    },
    /** Stylised 1-4 frame impact frame (inverted high-contrast monochrome). */
    impactFrame({ duration = 0.05, invert = 1, mono = 1 } = {}) {
      if (mono) post.pulse('mono', mono, { attack: 0, hold: duration, release: 0.03 });
      if (invert) post.pulse('invert', invert, { attack: 0, hold: duration, release: 0.03 });
    },
    /** Tween persistent fx values (numbers; colour keys) over `duration` real seconds. */
    to(params, duration = 0.3, easing = 'inOutQuad') {
      for (const k in params) if (k in DEFAULT_FX || COLOR_KEYS.includes(k)) tween(fx, k, params[k], duration, easing);
    },
    /**
     * Colour grade: a preset name ('night' | 'eclipse' | 'ember' | 'frost' | 'storm' | 'victory' | 'neutral') or an
     * object of grade keys (gradeLift / gradeGamma / gradeGain / toneShadows / toneHighlights: [r,g,b];
     * toneAmount, toneBalance, optionally saturation / contrast), tweened over `duration` real seconds.
     */
    grade(preset = 'night', duration = 0.6, easing = 'inOutSine') {
      const g = typeof preset === 'string' ? GRADES[preset] : preset;
      if (!g) return;
      post.to(g, duration, easing);
    },
    /** Change the neutral look (the environment calls this once) - reset() returns to it. Accepts grade keys too. */
    setBaseline(params) {
      for (const k in params) {
        if (COLOR_KEYS.includes(k)) { setColor(baseline[k], params[k]); fx[k].copy(baseline[k]); }
        else if (k in DEFAULT_FX) { baseline[k] = params[k]; fx[k] = params[k]; }
      }
    },
    /** Tween every persistent value back to the baseline. */
    reset(duration = 0.4) {
      const p = {};
      for (const k of NUM_KEYS) p[k] = baseline[k];
      for (const k of COLOR_KEYS) p[k] = baseline[k];
      post.to(p, duration);
    },
    /** Put the radial-blur centre on a world position. */
    radialAt(worldPos) {
      tmpV.copy(worldPos).project(ctx.camera);
      fx.radialCenter.set(clamp(tmpV.x * 0.5 + 0.5, -0.2, 1.2), clamp(tmpV.y * 0.5 + 0.5, -0.2, 1.2));
    },

    /**
     * The light the fog scatters (forward lobe) and the light shafts radiate from.
     * @param {THREE.Vector3|number[]} dirOrPos  unit direction TOWARD the light (default) or a world position ({point: true})
     * @param {*} [color]      light colour (THREE.Color | [r,g,b] linear | hex)
     * @param {number} [strength=1]
     * @param {{point?: boolean}} [opts]
     * Until called, the sun follows ctx.env.sunDir (the eclipse) automatically.
     */
    setSun(dirOrPos, color, strength = 1, { point = false } = {}) {
      sun.auto = false;
      sun.point = !!point;
      if (point) setVec3(sun.pos, dirOrPos); else setVec3(sun.dir, dirOrPos).normalize();
      if (color !== undefined) setColor(sun.color, color);
      sun.strength = strength;
    },
    /** Fog parameters (see FOG_DEFAULTS in README); numbers / colour tween over `duration`. Returns the live object. */
    fog(params = {}, duration = 0) {
      for (const k in params) {
        if (!(k in fog)) continue;
        if (duration > 0 && (typeof fog[k] === 'number' || k === 'color')) tween(fog, k, params[k], duration, 'inOutSine');
        else if (k === 'color') setColor(fog.color, params[k]);
        else fog[k] = params[k];
      }
      return fog;
    },
    /** Explicit fog lights [{ pos, color, intensity (cd), radius }] (max 4 on high, 2 on mid) or null: auto. */
    fogLights(list) { explicitLights = list && list.length ? list : null; },
    /** Light-shaft parameters (strength, threshold, radius, length, decay, glow, skyDepth); numbers tween. */
    shafts(params = {}, duration = 0) {
      for (const k in params) if (k in shaft) { if (duration > 0) tween(shaft, k, params[k], duration, 'inOutSine'); else shaft[k] = params[k]; }
      return shaft;
    },
    /**
     * Cinematic depth of field (off by default; tiers with quality.dof).
     *   post.dof({ focus: 4.2 | Vector3 | Object3D | () => pos, aperture: 1, range: 0.6, near: 1 }, 0.4)
     *   post.dof(null, 0.4)   fade out
     * focus: metres along the view axis, or a world point / object kept in focus every frame.
     * aperture: 0..1.5 blur strength (1 = max bokeh radius ~2.8 % of the screen height in the far distance).
     * range: m in front of / behind the focus that stay sharp. near: foreground blur scale (0 = no near blur).
     */
    dof(opts, duration = 0.35) {
      if (!opts) { dofS.from = dofS.aperture; dofS.to = 0; dofS.t = 0; dofS.dur = Math.max(1e-4, duration); return; }
      if (opts.focus !== undefined) {
        if (typeof opts.focus === 'number') { dofS.focus = opts.focus; dofS.target = null; }
        else dofS.target = opts.focus;
      }
      if (opts.range !== undefined) dofS.range = opts.range;
      if (opts.near !== undefined) dofS.near = opts.near;
      dofS.from = dofS.aperture; dofS.to = opts.aperture ?? 1; dofS.t = 0; dofS.dur = Math.max(1e-4, duration);
    },
    get dofActive() { return T.dof > 0 && dofS.aperture > 0.005; },
    /** Show an intermediate buffer instead of the frame: 'ao' | 'depth' | 'shafts' | 'dof' | 'off' (tiers with depth). */
    debugView(mode = 'off') { U.uDebug.value = { ao: 1, depth: 2, shafts: 3, dof: 4 }[mode] || 0; },

    /** Compile every post program now (createPost does it once; call again after a context restore). */
    prewarm() {
      const mats = [mPre, mDown, mUp, mDepth, mAO, mAOBlur, mShaftMask, mShaftBlur, mDofPrep, mDofGather, mComp];
      for (const m of mats) { if (!m) continue; fsMesh.material = m; renderer.compile(fsScene, fsCam); }
    },

    update(dtReal) {
      for (let i = tweens.length - 1; i >= 0; i--) {
        const tw = tweens[i];
        tw.t += dtReal;
        const k = tw.ease(clamp(tw.t / tw.dur));
        if (tw.color) tw.obj[tw.key].copy(tw.from).lerp(tw.to, k);
        else tw.obj[tw.key] = tw.from + (tw.to - tw.from) * k;
        if (tw.t >= tw.dur) tweens.splice(i, 1);
      }
      for (const k of NUM_KEYS) eff[k] = fx[k];
      for (let i = pulses.length - 1; i >= 0; i--) {
        const p = pulses[i];
        p.t += dtReal;
        let a;
        if (p.t < p.attack) a = p.t / p.attack;
        else if (p.t < p.attack + p.hold) a = 1;
        else { const r = (p.t - p.attack - p.hold) / Math.max(1e-4, p.release); a = 1 - r; if (r >= 1) { pulses.splice(i, 1); continue; } a = a * a; }
        eff[p.key] += p.amount * a;
      }
      if (dofS.t < dofS.dur) {
        dofS.t = Math.min(dofS.dur, dofS.t + dtReal);
        dofS.aperture = dofS.from + (dofS.to - dofS.from) * dofS.ease(dofS.t / dofS.dur);
      }
    },

    render(scene, camera) {
      const prevAuto = renderer.autoClear;
      renderer.autoClear = true;
      frameNo++;
      // the shadow frustum is fitted inside the render: world matrices are fresh there, the shadow pass not drawn yet
      hookPrev = scene.onBeforeRender; hookScene = scene;
      scene.onBeforeRender = shadowHook;
      renderer.setRenderTarget(rtScene);
      renderer.render(scene, camera);
      scene.onBeforeRender = hookPrev;
      hookPrev = null; hookScene = null;
      // post-scene hooks (e.g. the arena copies the HDR frame for its puddle reflection without a one-frame lag)
      for (let i = 0; i < afterScene.length; i++) afterScene[i](renderer, rtScene, camera);
      const t0 = ctx.flags && ctx.flags.prof ? performance.now() : 0;
      const callsBefore = renderer.info.render.calls;

      let useDist = 0;
      if (rtDist && eff.distortion > 0) {
        let any = false;
        for (const c of distortionScene.children) if (c.visible) { any = true; break; }
        if (any) {
          renderer.getClearColor(clearCol);
          const a = renderer.getClearAlpha();
          renderer.setClearColor(0x000000, 0);
          renderer.setRenderTarget(rtDist);
          renderer.render(distortionScene, camera);
          renderer.setClearColor(clearCol, a);
          useDist = 1;
        }
      }

      // ---- camera-derived uniforms ----------------------------------------------------------------------------------
      const W = rtScene.width, H = rtScene.height;
      camPos.setFromMatrixPosition(camera.matrixWorld);
      camFwd.set(0, 0, -1).transformDirection(camera.matrixWorld);
      uNearFar.value.set(camera.near, camera.far);
      const pe = camera.projectionMatrix.elements;
      uProj.value.set(pe[0], pe[5], pe[8], pe[9]);
      viewRay(U.uRay00.value, -1, -1, camera); viewRay(U.uRay10.value, 1, -1, camera); viewRay(U.uRay01.value, -1, 1, camera);
      U.uCamPos.value.copy(camPos);
      // sun: explicit, or the env's eclipse direction
      if (sun.auto && ctx.env && ctx.env.sunDir) sun.dir.copy(ctx.env.sunDir);
      const dim = T.depth ? atmoDim() : 0;
      if (sun.point) tmpV.copy(sun.pos); else tmpV.copy(sun.dir).multiplyScalar(camera.far * 0.5).add(camPos);
      const sunFront = tmpV2.copy(tmpV).sub(camPos).normalize().dot(camFwd);
      tmpV.project(camera);
      uSunUv.value.set(tmpV.x * 0.5 + 0.5, tmpV.y * 0.5 + 0.5);
      const off = Math.max(Math.abs(tmpV.x) - 1, Math.abs(tmpV.y) - 1, 0);
      const sunVis = sunFront > 0 ? (1 - Math.min(1, off / 0.6)) * Math.min(1, sunFront / 0.25) : 0;

      // ---- depth-derived passes (half res) ----------------------------------------------------------------------------
      const aoOn = T.ao && eff.ao > 0.01;
      const shaftOn = T.shafts && eff.shafts * shaft.strength > 0.001 && sunVis > 0.001;
      const dofOn = T.dof && dofS.aperture > 0.005;
      if (T.depth) {
        mDepth.uniforms.tDepth.value = rtScene.depthTexture;
        mDepth.uniforms.uTexel.value.set(1 / W, 1 / H);
        pass(mDepth, rtDepthH);
        depthValid = true;
      }
      if (aoOn) {
        const hw = rtAO.width, hh = rtAO.height;
        mAO.uniforms.tDepthH.value = rtDepthH.texture;
        mAO.uniforms.uTexel.value.set(1 / hw, 1 / hh);
        mAO.uniforms.uRes.value.set(hw, hh);
        mAO.uniforms.uAo.value.w = Math.max(6, hh * 0.07);
        pass(mAO, rtAO);
        mAOBlur.uniforms.tSrc.value = rtAO.texture; mAOBlur.uniforms.uDir.value.set(1 / hw, 0); pass(mAOBlur, rtAO2);
        mAOBlur.uniforms.tSrc.value = rtAO2.texture; mAOBlur.uniforms.uDir.value.set(0, 1 / hh); pass(mAOBlur, rtAO);
      }
      if (shaftOn) {
        const su = mShaftMask.uniforms;
        su.tScene.value = rtScene.texture; su.tDepthH.value = rtDepthH.texture;
        su.uAspect.value = W / H;
        su.uShaftP.value.set(shaft.threshold, shaft.radius, shaft.skyDepth, shaft.glow);
        su.uSunCol.value.copy(sun.color).multiplyScalar(sun.strength);
        pass(mShaftMask, rtShaft);
        const bu = mShaftBlur.uniforms;
        bu.tSrc.value = rtShaft.texture; bu.uLength.value = shaft.length; bu.uDecay.value = shaft.decay;
        pass(mShaftBlur, rtShaft2);
        if (T.shafts >= 2) { bu.tSrc.value = rtShaft2.texture; bu.uLength.value = shaft.length * 0.16; bu.uDecay.value = 0.99; pass(mShaftBlur, rtShaft); }
      }
      let maxR = 0;
      if (dofOn) {
        const hw = rtDof.width, hh = rtDof.height;
        maxR = Math.min(T.dof >= 2 ? 22 : 14, hh * 0.028);
        uDof.value.set(dofFocusDistance(camera), dofS.range, maxR * Math.min(1.5, dofS.aperture), dofS.near);
        mDofPrep.uniforms.tScene.value = rtScene.texture; mDofPrep.uniforms.tDepthH.value = rtDepthH.texture;
        pass(mDofPrep, rtDof);
        mDofGather.uniforms.tSrc.value = rtDof.texture;
        mDofGather.uniforms.uTexel.value.set(1 / hw, 1 / hh);
        mDofGather.uniforms.uMaxR.value = maxR * Math.min(1.5, dofS.aperture);
        pass(mDofGather, rtDof2);
      }

      // ---- bloom: prefilter + downsample chain, then additive tent upsample back up ------------------------------------
      const n = mips.length;
      if (n > 0 && eff.bloom > 0.001) {
        mPre.uniforms.tSrc.value = rtScene.texture;
        mPre.uniforms.uTexel.value.set(1 / W, 1 / H);
        mPre.uniforms.uThreshold.value = eff.bloomThreshold;
        mPre.uniforms.uKnee.value = eff.bloomKnee;
        pass(mPre, mips[0]);
        for (let i = 1; i < n; i++) {
          mDown.uniforms.tSrc.value = mips[i - 1].texture;
          mDown.uniforms.uTexel.value.set(1 / mips[i - 1].width, 1 / mips[i - 1].height);
          pass(mDown, mips[i]);
        }
        renderer.autoClear = false;
        for (let i = n - 2; i >= 0; i--) {
          mUp.uniforms.tSrc.value = mips[i + 1].texture;
          mUp.uniforms.uTexel.value.set(1 / mips[i + 1].width, 1 / mips[i + 1].height);
          mUp.uniforms.uRadius.value = eff.bloomRadius;
          mUp.uniforms.uWeight.value = 1.0;
          pass(mUp, mips[i]);
        }
        renderer.autoClear = true;
      }

      // ---- composite ------------------------------------------------------------------------------------------------
      U.tScene.value = rtScene.texture;
      U.tBloom.value = n > 0 ? mips[0].texture : null;
      U.tDist.value = rtDist ? rtDist.texture : null;
      U.uUseDist.value = useDist;
      U.uRes.value.set(cw, ch);
      U.uTime.value = ctx.time.real % 1000;
      U.uBloom.value = n > 0 && eff.bloom > 0.001 ? Math.max(0, eff.bloom) / Math.max(1, n * 0.5) : 0;
      U.uExposure.value = Math.max(0, eff.exposure);
      U.uChroma.value = Math.max(0, eff.chroma);
      U.uRadial.value = clamp(eff.radial, 0, 1.5);
      U.uRadialCenter.value.copy(fx.radialCenter);
      U.uVignette.value = clamp(eff.vignette, 0, 1);
      U.uGrain.value = Math.max(0, eff.grain);
      U.uSat.value = Math.max(0, eff.saturation);
      U.uContrast.value = Math.max(0, eff.contrast);
      U.uInvert.value = clamp(eff.invert);
      U.uMono.value = clamp(eff.mono);
      U.uLetterbox.value = clamp(eff.letterbox);
      U.uDist.value = eff.distortion;
      U.uFlash.value = clamp(eff.flash);
      U.uTint.value.copy(fx.tint);
      U.uLift.value.copy(fx.lift);
      U.uFlashColor.value.copy(tmpColor.copy(fx.flashColor).convertLinearToSRGB());
      U.uSceneTexel.value.set(1 / W, 1 / H);
      U.uSharpen.value = clamp(eff.sharpen + (renderScale < 0.99 ? (1 - renderScale) * 1.8 : 0), 0, 1);
      U.uGLift.value.copy(fx.gradeLift); U.uGGamma.value.copy(fx.gradeGamma); U.uGGain.value.copy(fx.gradeGain);
      U.uToneSh.value.copy(fx.toneShadows); U.uToneHi.value.copy(fx.toneHighlights);
      U.uTone.value.set(Math.max(0, eff.toneAmount), clamp(eff.toneBalance, -1, 1));
      if (T.depth) U.tDepth.value = rtScene.depthTexture;
      if (T.ao) { U.tAO.value = rtAO.texture; U.uAoStr.value = aoOn ? clamp(eff.ao, 0, 1.5) * 0.85 : 0; }
      if (T.fog) {
        const fs = clamp(eff.fog, 0, 2);
        U.uFogOn.value = fs > 0.001 ? 1 : 0;
        U.uFogA.value.set(fog.density * fs, fog.falloff, fog.haze * fs, Math.min(0.98, fog.maxOpacity * Math.min(1, fs)));
        U.uFogB.value.set(fog.floorY, fog.start, fog.far, fog.skyDistance);
        U.uFogCol.value.copy(fog.color).multiplyScalar(1 - 0.75 * dim);
        U.uSunDir.value.copy(sun.point ? tmpV2.copy(sun.pos).sub(camPos).normalize() : sun.dir);
        U.uSunCol.value.copy(sun.color).multiplyScalar(sun.strength * fog.sunScatter * (1 - 0.5 * dim));
        U.uSunG.value = clamp(fog.sunPhase, 0, 0.95);
        if (FOG_LIGHTS) updateFogLights(scene);
      }
      if (T.shafts) {
        U.tShaft.value = rtShaft.texture;
        U.uShaftOn.value = shaftOn ? 1 : 0;
        U.uShaftTint.value.setRGB(1, 1, 1).multiplyScalar(shaft.strength * Math.max(0, eff.shafts) * sunVis * (1 - 0.35 * dim));
      }
      if (T.dof) { U.tDof.value = rtDof2.texture; U.uDofOn.value = dofOn ? 1 : 0; }
      pass(mComp, null);
      renderer.autoClear = prevAuto;
      stats.passes = renderer.info.render.calls - callsBefore;
      if (t0) stats.msPost = performance.now() - t0;
    },

    dispose() {
      disposeTargets();
      farTex.dispose();
      for (const m of [mPre, mDown, mUp, mDepth, mAO, mAOBlur, mShaftMask, mShaftBlur, mDofPrep, mDofGather, mComp]) if (m) m.dispose();
      fsGeo.dispose();
    },
  };
  post.prewarm();
  return post;
}
