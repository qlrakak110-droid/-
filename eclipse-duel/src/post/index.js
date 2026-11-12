// Post-processing pipeline (HDR scene -> bloom -> composite with screen FX -> canvas).
//
//   const post = createPost(ctx)
//   post.fx            live parameters (see DEFAULT_FX). Set them directly for a persistent look ...
//   post.to({...}, s)  ... or tween persistent values over s seconds (mood shifts: world dims during an ultimate)
//   post.pulse(k,a,o)  transient additive spike on a numeric key (chroma / radial / exposure / bloom ...)
//   post.flash(c,a,o)  full-screen colour flash
//   post.impactFrame() 1-4 frame high-contrast (inverted / monochrome) impact frame
//   post.distortionScene   a THREE.Scene rendered with the main camera into the distortion buffer. Meshes in it output
//                          a screen-space UV offset in .rg (additive, signed, ~ +-0.05) -> heat haze / shockwave refraction.
//
// The scene is rendered in linear HDR (half float). Emissive / VFX colours above 1.0 feed the bloom; tone mapping (ACES)
// and sRGB encoding happen in the composite pass, so every material in the scene stays linear and `toneMapped` is moot.

import * as THREE from 'three';
import { clamp, ease as resolveEase } from '../core/math.js';

const VERT = /* glsl */ `
varying vec2 vUv;
void main() { vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }`;

const TAPS13 = /* glsl */ `
  vec3 a = S(vUv + uTexel * vec2(-2.0,  2.0));
  vec3 b = S(vUv + uTexel * vec2( 0.0,  2.0));
  vec3 c = S(vUv + uTexel * vec2( 2.0,  2.0));
  vec3 d = S(vUv + uTexel * vec2(-2.0,  0.0));
  vec3 e = S(vUv);
  vec3 f = S(vUv + uTexel * vec2( 2.0,  0.0));
  vec3 g = S(vUv + uTexel * vec2(-2.0, -2.0));
  vec3 h = S(vUv + uTexel * vec2( 0.0, -2.0));
  vec3 i = S(vUv + uTexel * vec2( 2.0, -2.0));
  vec3 j = S(vUv + uTexel * vec2(-1.0,  1.0));
  vec3 k = S(vUv + uTexel * vec2( 1.0,  1.0));
  vec3 l = S(vUv + uTexel * vec2(-1.0, -1.0));
  vec3 m = S(vUv + uTexel * vec2( 1.0, -1.0));`;

const PREFILTER = /* glsl */ `
precision highp float;
uniform sampler2D tSrc; uniform vec2 uTexel; uniform float uThreshold; uniform float uKnee;
varying vec2 vUv;
vec3 S(vec2 uv) { return min(texture2D(tSrc, uv).rgb, vec3(48.0)); }
float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
vec3 thresh(vec3 c) {
  float br = max(c.r, max(c.g, c.b));
  float soft = clamp(br - uThreshold + uKnee, 0.0, 2.0 * uKnee);
  soft = soft * soft / (4.0 * uKnee + 1e-4);
  return c * (max(soft, br - uThreshold) / max(br, 1e-4));
}
void main() {
  ${TAPS13}
  // Karis-weighted groups kill single-pixel fireflies
  vec3 g0 = (a + b + d + e) * 0.25, g1 = (b + c + e + f) * 0.25, g2 = (d + e + g + h) * 0.25, g3 = (e + f + h + i) * 0.25, g4 = (j + k + l + m) * 0.25;
  float w0 = 0.125 / (1.0 + luma(g0)), w1 = 0.125 / (1.0 + luma(g1)), w2 = 0.125 / (1.0 + luma(g2)), w3 = 0.125 / (1.0 + luma(g3)), w4 = 0.5 / (1.0 + luma(g4));
  vec3 col = (g0 * w0 + g1 * w1 + g2 * w2 + g3 * w3 + g4 * w4) / (w0 + w1 + w2 + w3 + w4);
  gl_FragColor = vec4(thresh(max(col, vec3(0.0))), 1.0);
}`;

const DOWN = /* glsl */ `
precision highp float;
uniform sampler2D tSrc; uniform vec2 uTexel;
varying vec2 vUv;
vec3 S(vec2 uv) { return texture2D(tSrc, uv).rgb; }
void main() {
  ${TAPS13}
  vec3 col = e * 0.125 + (a + c + g + i) * 0.03125 + (b + d + f + h) * 0.0625 + (j + k + l + m) * 0.125;
  gl_FragColor = vec4(col, 1.0);
}`;

const UP = /* glsl */ `
precision highp float;
uniform sampler2D tSrc; uniform vec2 uTexel; uniform float uRadius; uniform float uWeight;
varying vec2 vUv;
void main() {
  vec2 o = uTexel * uRadius;
  vec3 col = texture2D(tSrc, vUv).rgb * 4.0;
  col += (texture2D(tSrc, vUv + vec2(-o.x, 0.0)).rgb + texture2D(tSrc, vUv + vec2(o.x, 0.0)).rgb + texture2D(tSrc, vUv + vec2(0.0, -o.y)).rgb + texture2D(tSrc, vUv + vec2(0.0, o.y)).rgb) * 2.0;
  col += texture2D(tSrc, vUv + vec2(-o.x, -o.y)).rgb + texture2D(tSrc, vUv + vec2(o.x, -o.y)).rgb + texture2D(tSrc, vUv + vec2(-o.x, o.y)).rgb + texture2D(tSrc, vUv + vec2(o.x, o.y)).rgb;
  gl_FragColor = vec4(col * (uWeight / 16.0), 1.0);
}`;

const COMPOSITE = /* glsl */ `
precision highp float;
uniform sampler2D tScene; uniform sampler2D tBloom; uniform sampler2D tDist;
uniform vec2 uRes; uniform float uTime;
uniform float uBloom, uExposure, uChroma, uRadial, uVignette, uGrain, uSat, uContrast, uInvert, uMono, uLetterbox, uDist, uFlash, uUseDist, uHdr;
uniform vec2 uRadialCenter; uniform vec3 uTint, uLift, uFlashColor;
varying vec2 vUv;

float hash12(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
vec3 RRTAndODTFit(vec3 v) { vec3 a = v * (v + 0.0245786) - 0.000090537; vec3 b = v * (0.983729 * v + 0.4329510) + 0.238081; return a / b; }
vec3 ACESFilmic(vec3 color) {
  const mat3 ACESInputMat = mat3(vec3(0.59719, 0.07600, 0.02840), vec3(0.35458, 0.90834, 0.13383), vec3(0.04823, 0.01566, 0.83777));
  const mat3 ACESOutputMat = mat3(vec3(1.60475, -0.10208, -0.00327), vec3(-0.53108, 1.10813, -0.07276), vec3(-0.07367, -0.00605, 1.07602));
  color *= 1.0 / 0.6;
  color = ACESInputMat * color; color = RRTAndODTFit(color); color = ACESOutputMat * color;
  return clamp(color, 0.0, 1.0);
}
vec3 lin2srgb(vec3 c) { return mix(c * 12.92, 1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c)); }

void main() {
  vec2 uv = vUv;
  if (uUseDist > 0.5) uv += texture2D(tDist, uv).rg * uDist;
  vec3 col;
  if (uRadial > 0.001) {
    vec2 toC = uv - uRadialCenter;
    float jitter = hash12(vUv * uRes + uTime * 61.0);
    float wsum = 0.0; col = vec3(0.0);
    for (int n = 0; n < 10; n++) {
      float f = (float(n) + jitter) / 10.0;
      float w = 1.0 - f * 0.6;
      col += texture2D(tScene, uRadialCenter + toC * (1.0 - uRadial * 0.35 * f)).rgb * w; wsum += w;
    }
    col /= wsum;
  } else {
    col = texture2D(tScene, uv).rgb;
  }
  vec3 bloom = texture2D(tBloom, uv).rgb;
  if (uChroma > 0.001) {
    vec2 c = uv - 0.5;
    vec2 off = c * uChroma * 0.03 * (0.3 + length(c));
    col.r = mix(col.r, texture2D(tScene, uv + off).r, 0.85);
    col.b = mix(col.b, texture2D(tScene, uv - off).b, 0.85);
    bloom.r = texture2D(tBloom, uv + off * 1.5).r;
    bloom.b = texture2D(tBloom, uv - off * 1.5).b;
  }
  col += bloom * uBloom;
  col *= uExposure;
  col = col * uTint + uLift;
  if (uHdr > 0.5) col = ACESFilmic(col); else col = clamp(col, 0.0, 1.0);
  col = lin2srgb(col);
  float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
  col = mix(vec3(l), col, uSat);
  col = (col - 0.5) * uContrast + 0.5;
  if (uMono > 0.001) col = mix(col, vec3(smoothstep(0.28, 0.52, l)), uMono);
  if (uInvert > 0.001) col = mix(col, 1.0 - col, uInvert);
  col = mix(col, uFlashColor, clamp(uFlash, 0.0, 1.0));
  vec2 vc = vUv - 0.5;
  col *= 1.0 - uVignette * smoothstep(0.3, 0.95, length(vc) * 1.3);
  col += (hash12(vUv * uRes + fract(uTime) * 517.0) - 0.5) * uGrain;
  if (uLetterbox > 0.001) {
    float bar = uLetterbox * 0.115;
    col *= smoothstep(bar - 0.0015, bar + 0.0015, min(vUv.y, 1.0 - vUv.y));
  }
  gl_FragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}`;

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
};
const NUM_KEYS = Object.keys(DEFAULT_FX);

export function createPost(ctx) {
  const renderer = ctx.renderer;
  const q = ctx.quality;
  const hdr = renderer.extensions.has('EXT_color_buffer_float') || renderer.extensions.has('EXT_color_buffer_half_float');
  const texType = hdr ? THREE.HalfFloatType : THREE.UnsignedByteType;

  const fx = { ...DEFAULT_FX, radialCenter: new THREE.Vector2(0.5, 0.5), tint: new THREE.Color(1, 1, 1), lift: new THREE.Color(0, 0, 0), flashColor: new THREE.Color(1, 1, 1) };
  const baseline = { ...DEFAULT_FX, tint: new THREE.Color(1, 1, 1), lift: new THREE.Color(0, 0, 0) };
  if (!hdr) { fx.bloomThreshold = baseline.bloomThreshold = 0.82; }

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
  const mkMat = (frag, uniforms, extra = {}) => new THREE.ShaderMaterial({ vertexShader: VERT, fragmentShader: frag, uniforms, depthTest: false, depthWrite: false, toneMapped: false, ...extra });

  const mPre = mkMat(PREFILTER, { tSrc: { value: null }, uTexel: { value: new THREE.Vector2() }, uThreshold: { value: 1 }, uKnee: { value: 0.5 } });
  const mDown = mkMat(DOWN, { tSrc: { value: null }, uTexel: { value: new THREE.Vector2() } });
  const mUp = mkMat(UP, { tSrc: { value: null }, uTexel: { value: new THREE.Vector2() }, uRadius: { value: 1 }, uWeight: { value: 1 } }, { blending: THREE.AdditiveBlending, transparent: true });
  const U = {
    tScene: { value: null }, tBloom: { value: null }, tDist: { value: null }, uRes: { value: new THREE.Vector2(1, 1) }, uTime: { value: 0 },
    uBloom: { value: 1 }, uExposure: { value: 1 }, uChroma: { value: 0 }, uRadial: { value: 0 }, uVignette: { value: 0 }, uGrain: { value: 0 },
    uSat: { value: 1 }, uContrast: { value: 1 }, uInvert: { value: 0 }, uMono: { value: 0 }, uLetterbox: { value: 0 }, uDist: { value: 1 },
    uFlash: { value: 0 }, uUseDist: { value: 0 }, uHdr: { value: hdr ? 1 : 0 },
    uRadialCenter: { value: new THREE.Vector2(0.5, 0.5) }, uTint: { value: new THREE.Color(1, 1, 1) }, uLift: { value: new THREE.Color(0, 0, 0) }, uFlashColor: { value: new THREE.Color(1, 1, 1) },
  };
  const mComp = mkMat(COMPOSITE, U);

  let rtScene = null, rtDist = null, mips = [];
  let cw = 1, ch = 1, renderScale = 1;
  const distortionScene = new THREE.Scene();

  function alloc() {
    const w = Math.max(2, Math.round(cw * renderScale)), h = Math.max(2, Math.round(ch * renderScale));
    if (rtScene) rtScene.dispose();
    rtScene = mkRT(w, h, { depthBuffer: true, samples: q.msaa || 0 });
    if (rtDist) rtDist.dispose();
    rtDist = hdr ? mkRT(Math.ceil(w / 2), Math.ceil(h / 2)) : null;
    for (const m of mips) m.dispose();
    mips = [];
    let mw = Math.ceil(w / 2), mh = Math.ceil(h / 2);
    for (let i = 0; i < (q.bloomLevels || 5) && mw >= 4 && mh >= 4; i++) {
      mips.push(mkRT(mw, mh));
      mw = Math.ceil(mw / 2); mh = Math.ceil(mh / 2);
    }
  }

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

  const afterScene = [];
  const post = {
    fx, baseline, hdr, distortionScene,
    /** Register fn(renderer, sceneTarget, camera) called right after the HDR scene render each frame. Returns off(). */
    onAfterScene(fn) { afterScene.push(fn); return () => { const i = afterScene.indexOf(fn); if (i >= 0) afterScene.splice(i, 1); }; },
    get sceneTarget() { return rtScene; },

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
    /** Tween persistent fx values (numbers; tint/lift colours) over `duration` real seconds. */
    to(params, duration = 0.3, easing = 'inOutQuad') {
      for (const k in params) {
        // a newer tween on the same key replaces the running one (it starts from the current value)
        for (let i = tweens.length - 1; i >= 0; i--) if (tweens[i].key === k) tweens.splice(i, 1);
        if (k === 'tint' || k === 'lift') tweens.push({ key: k, color: true, from: fx[k].clone(), to: new THREE.Color().set(params[k]), t: 0, dur: Math.max(1e-4, duration), ease: resolveEase(easing) });
        else if (k in DEFAULT_FX) tweens.push({ key: k, from: fx[k], to: params[k], t: 0, dur: Math.max(1e-4, duration), ease: resolveEase(easing) });
      }
    },
    /** Change the neutral look (the environment calls this once) - reset() returns to it. */
    setBaseline(params) {
      for (const k in params) {
        if (k === 'tint' || k === 'lift') { baseline[k].set(params[k]); fx[k].copy(baseline[k]); }
        else if (k in DEFAULT_FX) { baseline[k] = params[k]; fx[k] = params[k]; }
      }
    },
    /** Tween every persistent value back to the baseline. */
    reset(duration = 0.4) {
      const p = {};
      for (const k of NUM_KEYS) p[k] = baseline[k];
      p.tint = baseline.tint; p.lift = baseline.lift;
      post.to(p, duration);
    },
    /** Put the radial-blur centre on a world position. */
    radialAt(worldPos) {
      tmpV.copy(worldPos).project(ctx.camera);
      fx.radialCenter.set(clamp(tmpV.x * 0.5 + 0.5, -0.2, 1.2), clamp(tmpV.y * 0.5 + 0.5, -0.2, 1.2));
    },

    update(dtReal) {
      for (let i = tweens.length - 1; i >= 0; i--) {
        const tw = tweens[i];
        tw.t += dtReal;
        const k = tw.ease(clamp(tw.t / tw.dur));
        if (tw.color) fx[tw.key].copy(tw.from).lerp(tw.to, k);
        else fx[tw.key] = tw.from + (tw.to - tw.from) * k;
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
    },

    render(scene, camera) {
      const prevAuto = renderer.autoClear;
      renderer.autoClear = true;
      renderer.setRenderTarget(rtScene);
      renderer.render(scene, camera);
      // post-scene hooks (e.g. the arena copies the HDR frame for its puddle reflection without a one-frame lag)
      for (let i = 0; i < afterScene.length; i++) afterScene[i](renderer, rtScene, camera);

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

      // bloom: prefilter + downsample chain, then additive tent upsample back up
      const n = mips.length;
      if (n > 0 && eff.bloom > 0.001) {
        mPre.uniforms.tSrc.value = rtScene.texture;
        mPre.uniforms.uTexel.value.set(1 / rtScene.width, 1 / rtScene.height);
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

      U.tScene.value = rtScene.texture;
      U.tBloom.value = n > 0 ? mips[0].texture : null;
      U.tDist.value = rtDist ? rtDist.texture : null;
      U.uUseDist.value = useDist;
      U.uRes.value.set(cw, ch);
      U.uTime.value = ctx.time.real % 1000;
      U.uBloom.value = n > 0 ? Math.max(0, eff.bloom) / Math.max(1, n * 0.5) : 0;
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
      pass(mComp, null);
      renderer.autoClear = prevAuto;
    },

    dispose() { if (rtScene) rtScene.dispose(); if (rtDist) rtDist.dispose(); for (const m of mips) m.dispose(); },
  };
  const tmpV = new THREE.Vector3();
  return post;
}
