// GPU particles: instanced quads in ring buffers, analytic motion in the vertex shader. Every emitter definition is a
// row of a shared ParamTable (colour ramp, curves, motion and look parameters), so any number of particle types share
// ONE draw call per blend layer:
//   alpha    premultiplied-alpha layer (smoke, dust, debris; can be partially additive over life: fire -> smoke)
//   add      additive layer (sparks, embers, glows)
//   distort  screen-space refraction particles drawn into ctx.post.distortionScene (heat haze)
// The CPU writes 24 floats per particle once, at spawn; nothing per particle afterwards.
//
// Public API (installed on vfx): burst(def, at), emitter(def, at), particleDef(name, def), particles.* (internals).
// The definition format is documented in README.md ("Particle definitions").

import * as THREE from 'three';
import { InstanceRing } from './instanced.js';
import { ParamTable, tableGlsl } from './table.js';
import { toCurveFn, toRampFn, toVec3, sampleRange, rangeMax, makeFrame, normalizeAt, makeAt, defKey, RENDER_ORDER } from './util.js';
import { TAU, DEG } from '../core/math.js';
import { DEPTH_FADE_GLSL } from './depth.js';

const LAYOUT = { iPosT: 4, iVelL: 4, iOrgD: 4, iAxisS: 4, iMisc: 4, iTint: 4 };
const ALIGN = { billboard: 0, velocity: 1, flat: 2, axis: 3, velocityAxis: 4 };
const EMIT = { axis: 0, radial: 1, random: 2, inward: 3, tangent: 4, normal: 5 };
const CHANNEL = { fbm: [1, 0, 0, 0], cells: [0, 1, 0, 0], cracks: [0, 0, 1, 0], grain: [0, 0, 0, 1] };

const VERT = /* glsl */ `
precision highp float;
uniform float uTime, uTimeReal, uMaxScreen, uLayerAdd;
uniform sampler2D uDefs;
attribute vec4 iPosT, iVelL, iOrgD, iAxisS, iMisc, iTint;
varying vec2 vUv, vUv2, vLocal;
varying vec4 vCol, vF, vE, vN, vCh;
varying vec3 vHot;
varying float vSoft;
${tableGlsl('uDefs', 'd')}

void integ(inout vec3 p, inout vec3 v, vec3 g, float k, float t) {
  if (k < 1e-3) { p += v * t + 0.5 * g * t * t; v += g * t; }
  else { float e = exp(-k * t); vec3 vt = g / k; p += vt * t + (v - vt) * (1.0 - e) / k; v = vt + (v - vt) * e; }
}
float yAt(float y, float vy, float gy, float k, float t) {
  if (k < 1e-3) return y + vy * t + 0.5 * gy * t * t;
  float vt = gy / k; return y + vt * t + (vy - vt) * (1.0 - exp(-k * t)) / k;
}
float vyAt(float vy, float gy, float k, float t) {
  if (k < 1e-3) return vy + gy * t;
  float vt = gy / k; return vt + (vy - vt) * exp(-k * t);
}
// first time the height reaches 0 within [0, tmax] (Newton from the right: y is concave and falling there)
float impact(float y, float vy, float gy, float k, float tmax) {
  if (yAt(y, vy, gy, k, tmax) > 0.0) return 1e9;
  float t = tmax;
  for (int i = 0; i < 6; i++) t -= yAt(y, vy, gy, k, t) / min(vyAt(vy, gy, k, t), -1e-3);
  return max(t, 0.0);
}
// integrated sum-of-sines velocity field: smooth, spatially coherent meandering (bounded displacement)
vec3 turb(vec3 q, float t, float spd, float seed) {
  vec3 ph1 = vec3(dot(q, vec3(1.0, 0.6, -0.8)), dot(q, vec3(-0.7, 1.1, 0.5)), dot(q, vec3(0.4, -0.9, 1.2))) + vec3(0.0, 2.1, 4.2) + seed * 3.0;
  vec3 ph2 = 2.03 * vec3(dot(q, vec3(-0.5, 0.9, 1.0)), dot(q, vec3(1.2, 0.3, -0.6)), dot(q, vec3(-0.8, -0.7, 0.9))) + vec3(1.3, 5.0, 2.7) + seed * 7.0;
  float w1 = 1.3 * spd, w2 = 2.9 * spd;
  return (cos(ph1) - cos(ph1 + w1 * t)) / w1 + 0.5 * (cos(ph2) - cos(ph2 + w2 * t)) / w2;
}
vec3 rotAxis(vec3 v, vec3 a, float ang) { float c = cos(ang), s = sin(ang); return v * c + cross(a, v) * s + a * dot(a, v) * (1.0 - c); }
float hash11(float x) { return fract(sin(x * 127.1) * 43758.5453); }

// def parameters (see particles.js writeDef)
vec4 P0, P1, P2, P4;
vec3 simPos(float tau, float life, vec3 p0, vec3 v0, float s, vec3 org, vec3 axis, float seed) {
  vec3 p = p0, v = v0 * s, g = P0.xyz * s;
  float k = P0.w;
  if (P2.z >= 0.0) {
    float tr = tau;
    for (int b = 0; b < 3; b++) {
      float ti = impact(p.y, v.y, g.y, k, tr);
      if (ti >= tr) break;
      integ(p, v, g, k, ti);
      p.y = 0.0; v.y = -v.y * P2.z; v.xz *= P2.w; tr -= ti;
      if (v.y < 0.2) { v.y = 0.0; break; }
    }
    integ(p, v, g, k, tr);
  } else integ(p, v, g, k, tau);
  if (P1.x > 0.0) p += turb(p0 * P1.y, tau, P1.z, seed) * P1.x * s;
  if (P1.w != 0.0) p = org + rotAxis(p - org, axis, P1.w * tau);
  if (P2.x > 0.0) p = mix(p, org, P2.x * pow(clamp(tau / life, 0.0, 1.0), P2.y));
  if (P2.z >= 0.0) p.y = max(p.y, 0.0);
  return p;
}

void main() {
  float life = abs(iVelL.w);
  bool rt = iVelL.w < 0.0;
  float tau = (rt ? uTimeReal : uTime) - iPosT.w;
  if (tau < 0.0 || tau >= life) { gl_Position = vec4(0.0, 0.0, 2.0, 1.0); return; }
  int row = int(iOrgD.w + 0.5);
  float t = tau / life;
  P0 = dParam(0, row); P1 = dParam(1, row); P2 = dParam(2, row); P4 = dParam(4, row);
  vec4 P3 = dParam(3, row), P5 = dParam(5, row), P6 = dParam(6, row), P7 = dParam(7, row), P9 = dParam(9, row);
  float s = iAxisS.w, seed = iMisc.w;
  vec3 axis = iAxisS.xyz;
  vec3 pos = simPos(tau, life, iPosT.xyz, iVelL.xyz, s, iOrgD.xyz, axis, seed);
  vec4 cv = dCurve(t, row);           // x size, y erosion threshold, z additive fraction, w intensity
  int align = int(P4.w + 0.5);
  vec3 vel = vec3(0.0);
  if (align == 1 || align == 4) {
    float e = 0.012;
    vec3 q = simPos(max(tau - e, 0.0), life, iPosT.xyz, iVelL.xyz, s, iOrgD.xyz, axis, seed);
    if (tau < e) { q = pos; pos = simPos(tau + e, life, iPosT.xyz, iVelL.xyz, s, iOrgD.xyz, axis, seed); }
    vel = (pos - q) / e;
    if (tau < e) pos = q;
  }
  vec4 mv = viewMatrix * vec4(pos, 1.0);
  if (P9.w > 0.0) mv.xyz += normalize(-mv.xyz) * min(P9.w, max(-mv.z - 0.3, 0.0));
  float size = iMisc.x * cv.x;
  float zc = max(-mv.z, 0.05);
  float sc = min(1.0, uMaxScreen * 2.0 * zc / projectionMatrix[1][1] / max(size, 1e-4));
  vec2 hs = vec2(size * 0.5 * P7.y, size * 0.5) * sc;
  vec2 c = position.xy;
  float rot = iMisc.y + iMisc.z * tau;
  vec2 cr = vec2(cos(rot), sin(rot));
  vec3 offs = vec3(0.0);
  mat3 vm = mat3(viewMatrix);
  if (align == 1) {
    vec2 d = (vm * vel).xy;
    float L = length(d);
    vec2 dir = L > 1e-4 ? d / L : vec2(cr.x, cr.y);
    float sl = min(L * P4.z, P7.z) * sc;
    float hl = hs.x + sl * 0.5;
    offs.xy = dir * (c.x * hl - sl * 0.5) + vec2(-dir.y, dir.x) * (c.y * hs.y);
  } else if (align == 2) {
    vec3 T = normalize(cross(axis, abs(axis.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
    vec3 B = cross(axis, T);
    vec2 r2 = vec2(c.x * hs.x * cr.x - c.y * hs.y * cr.y, c.x * hs.x * cr.y + c.y * hs.y * cr.x);
    offs = vm * (T * r2.x + B * r2.y);
  } else if (align >= 3) {
    vec3 up = align == 3 ? axis : (length(vel) > 1e-4 ? normalize(vel) : axis);
    vec3 a = normalize(vm * up);
    vec3 side = cross(a, vec3(0.0, 0.0, 1.0));
    float sl = length(side);
    side = sl > 1e-3 ? side / sl : vec3(1.0, 0.0, 0.0);
    offs = side * (c.x * hs.x) + a * (c.y * hs.y);
  } else {
    offs.xy = vec2(c.x * hs.x * cr.x - c.y * hs.y * cr.y, c.x * hs.x * cr.y + c.y * hs.y * cr.x);
  }
  mv.xyz += offs;
  gl_Position = projectionMatrix * mv;
  float wy = pos.y + (transpose(vm) * offs).y;

  // atlas frame (random variant per particle, or a cycling flipbook with cross-fade)
  float frames = P4.x, fps = P4.y;
  float f = fps > 0.0 ? tau * fps + seed * frames : floor(seed * frames * 0.999);
  float fi = floor(f);
  vLocal = c * 0.5 + 0.5;
  vec2 lq = mix(vec2(0.006), vec2(0.994), vLocal);
  vUv = P3.xy + (lq + vec2(mod(fi, frames), 0.0)) * P3.zw;
  vUv2 = P3.xy + (lq + vec2(mod(fi + 1.0, frames), 0.0)) * P3.zw;

  vec4 col = dRamp(t, row);
  vec3 hot = dRamp(max(t - P6.w, 0.0), row).rgb;
  float fl = 1.0;
  if (P5.y > 0.0) { float x = tau * P5.z + seed * 61.0; fl = 1.0 - P5.y * mix(hash11(floor(x)), hash11(floor(x) + 1.0), smoothstep(0.0, 1.0, fract(x))); }
  float near = smoothstep(P5.w, P5.w * 3.0 + 0.05, zc);
  vCol = vec4(col.rgb * iTint.rgb * cv.w * fl, col.a * iTint.a * near * (0.5 + 0.5 * fl));
  vHot = hot * iTint.rgb * cv.w * fl;
  vF = vec4(cv.y, max(P6.y, 0.01), uLayerAdd > 0.5 ? 1.0 : clamp(cv.z, 0.0, 1.0), fps > 0.0 ? fract(f) : 0.0);
  vE = vec4(P5.x > 0.0 ? 1.0 / P5.x : 1e5, wy, P6.z, P7.x);
  vN = vec4(vec2(hash11(seed * 13.7), hash11(seed * 29.3)) + P9.xy * tau, P6.x, P7.w);
  vCh = dParam(8, row);
  vSoft = P9.z > 0.0 ? 1.0 / (P9.z * max(s, 0.3)) : 0.0;   // soft particles: 1 / fade distance (m) against scene depth
}`;

const FRAG = /* glsl */ `
precision highp float;
uniform sampler2D uAtlas, uNoise;
varying vec2 vUv, vUv2, vLocal;
varying vec4 vCol, vF, vE, vN, vCh;
varying vec3 vHot;
varying float vSoft;
${DEPTH_FADE_GLSL}
void main() {
  vec4 s = texture2D(uAtlas, vUv);
  if (vF.w > 0.001) s = mix(s, texture2D(uAtlas, vUv2), vF.w);
  float a = s.a * vCol.a;
  vec3 rgb = mix(vCol.rgb, vHot, s.g) * mix(1.0, s.r, vE.w);
  if (vF.x > 0.0) {
    float n = dot(texture2D(uNoise, vLocal * vN.z + vN.xy), vCh);
    float o = mix(s.b, n, vE.z);
    float th = vF.x * (1.0 + vF.y) - vF.y;
    float k = smoothstep(th, th + vF.y, o);
    rgb += vHot * vN.w * (1.0 - smoothstep(th + vF.y * 0.5, th + vF.y * 2.0, o));
    a *= k;
  }
  a *= clamp(vE.y * vE.x, 0.0, 1.0);
  if (vSoft > 0.0) a *= vfxSoft(vSoft);
  if (a <= 0.0005) discard;
  gl_FragColor = vec4(rgb * a, a * (1.0 - vF.z));
}`;

const FRAG_DISTORT = /* glsl */ `
precision highp float;
uniform sampler2D uAtlas, uFlow;
varying vec2 vUv, vUv2, vLocal;
varying vec4 vCol, vF, vE, vN, vCh;
varying vec3 vHot;
varying float vSoft;
${DEPTH_FADE_GLSL}
void main() {
  vec4 s = texture2D(uAtlas, vUv);
  float a = s.a * vCol.a;
  vec2 f = texture2D(uFlow, vLocal * vN.z + vN.xy).ba * 2.0 - 1.0;
  a *= clamp(vE.y * vE.x, 0.0, 1.0) * vfxVisible(0.3);   // haze behind a body does not bend the body
  gl_FragColor = vec4(f * a * vCol.r, 0.0, 0.0);
}`;

/**
 * Install the particle system on `vfx`.
 * @param {object} vfx     the facade
 * @param {object} shared  shared resources (ctx, textures, clock, root, track ...)
 */
export function installParticles(vfx, shared) {
  const { ctx, textures, clock, rng, depth } = shared;
  const q = ctx.quality;
  const capScale = q.tier === 'low' ? 0.5 : q.tier === 'mid' ? 0.75 : 1;
  const table = new ParamTable(384, 'particle definitions');
  const U = {
    uTime: shared.uniforms.uTime, uTimeReal: shared.uniforms.uTimeReal,     uDefs: { value: table.texture }, uAtlas: { value: textures.atlas }, uNoise: { value: textures.noise }, uFlow: { value: textures.flow },
    uMaxScreen: { value: q.tier === 'low' ? 0.45 : 0.7 },
  };

  function makeLayer(name, cap, frag, order, target) {
    const ring = new InstanceRing(cap, LAYOUT);
    const mat = new THREE.ShaderMaterial({
      vertexShader: VERT, fragmentShader: frag,
      uniforms: { ...U, ...depth.uniforms, uLayerAdd: { value: name === 'add' ? 1 : 0 } },
      defines: depth.defines(name === 'distort' ? 2 : 1),
      transparent: true, depthWrite: false, depthTest: true,
      blending: THREE.CustomBlending, blendEquation: THREE.AddEquation,
      blendSrc: THREE.OneFactor, blendDst: name === 'distort' ? THREE.OneFactor : THREE.OneMinusSrcAlphaFactor,
      blendSrcAlpha: THREE.OneFactor, blendDstAlpha: name === 'distort' ? THREE.OneFactor : THREE.OneMinusSrcAlphaFactor,
    });
    const mesh = new THREE.Mesh(ring.geometry, mat);
    mesh.frustumCulled = false;
    mesh.renderOrder = order;
    mesh.visible = false;
    mesh.name = 'vfx.particles.' + name;
    target.add(mesh);
    return { name, ring, mat, mesh, maxDeath: -1, maxDeathReal: -1 };
  }
  const layers = {
    alpha: makeLayer('alpha', Math.round(4096 * capScale), FRAG, RENDER_ORDER.alphaParticles, shared.root),
    add: makeLayer('add', Math.round(8192 * capScale), FRAG, RENDER_ORDER.addParticles, shared.root),
    distort: makeLayer('distort', Math.round(512 * capScale), FRAG_DISTORT, 0, ctx.post.distortionScene),
  };

  // ---- definitions -------------------------------------------------------------------------------------------------
  const byObject = new WeakMap();
  const byKey = new Map();
  const named = new Map();

  function compile(def) {
    if (typeof def === 'string') {
      const d = named.get(def);
      if (!d) throw new Error('vfx: unknown particle definition "' + def + '"');
      return d.row >= 0 ? d : compile(d.src);
    }
    if (def.isCompiledParticleDef) return def.row >= 0 ? def : compile(def.src);
    let cd = byObject.get(def);
    if (cd && cd.row >= 0) return cd;
    const key = defKey(def);
    cd = byKey.get(key);
    if (!cd || cd.row < 0) {
      cd = buildDef(def, key);
      byKey.set(key, cd);
    }
    byObject.set(def, cd);
    return cd;
  }

  function buildDef(def, key) {
    const blend = def.blend || 'add';
    if (!layers[blend]) throw new Error('vfx: particle blend must be add | alpha | distort, got ' + blend);
    const cd = {
      isCompiledParticleDef: true, src: def, key, row: -1, layer: layers[blend],
      life: def.life != null ? def.life : [0.5, 1],
      count: def.count != null ? def.count : 16,
      rate: def.rate || 0,
      perMeter: def.perMeter || 0,
      duration: def.duration || 0,
      shape: def.shape || { type: 'point' },
      emit: EMIT[def.emit || 'axis'],
      spread: def.spread != null ? def.spread : (def.shape && def.shape.angle != null ? def.shape.angle : 25),
      spreadPow: def.spreadPow || 1,
      lift: def.lift || 0,
      speed: def.speed != null ? def.speed : [1, 3],
      size: def.size != null ? def.size : [0.05, 0.12],
      rotation: def.rotation != null ? def.rotation : [0, TAU],
      spin: def.spin != null ? def.spin : 0,
      spinBoth: def.spinBoth !== false,
      delay: def.delay || 0,
      inherit: def.inherit || 0,
      vel: def.vel ? toVec3(def.vel) : null,
      dir: def.dir ? toVec3(def.dir).normalize() : null,
      jitter: def.jitter || 0,
      realtime: !!def.realtime,
      onEvict() { cd.row = -1; },
    };
    cd.maxLife = rangeMax(cd.life, 1) + rangeMax(cd.delay, 0);
    const row = table.alloc(cd, clock.game);
    if (row < 0) throw new Error('vfx: particle definition table full');
    cd.row = row;
    writeDef(row, def, cd);
    return cd;
  }

  function writeDef(row, def, cd) {
    table.writeRamp(row, toRampFn(def.color != null ? def.color : [[0, 4, 2, 0.6, 1], [1, 1, 0.2, 0.02, 0]], def.alpha));
    const inten = def.intensity != null ? def.intensity : 1;
    const ic = toCurveFn(def.intensityOverLife, 1);
    table.writeCurves(row, toCurveFn(def.sizeOverLife, 1), toCurveFn(def.erode, 0), toCurveFn(def.additive, 0), (t) => ic(t) * inten);
    const g = def.gravity == null ? [0, 0, 0] : typeof def.gravity === 'number' ? [0, def.gravity, 0] : toVec3(def.gravity).toArray();
    table.param(row, 0, g[0], g[1], g[2], def.drag || 0);
    const tb = def.turbulence || {};
    table.param(row, 1, tb.amp || 0, tb.freq != null ? tb.freq : 1, tb.speed != null ? tb.speed : 1, def.swirl || 0);
    const collide = def.collide === 'ground' || def.bounce != null;
    table.param(row, 2, def.attract || 0, def.attractPow != null ? def.attractPow : 2, collide ? (def.bounce != null ? def.bounce : 0.4) : -1, def.friction != null ? def.friction : 0.7);
    const sp = textures.sprite(def.tex || 'glow');
    const frames = def.frames != null ? Math.min(def.frames, sp.frames) : sp.frames;
    table.param(row, 3, sp.u, sp.v, sp.w, sp.h);
    const align = ALIGN[def.align || (def.stretch ? 'velocity' : 'billboard')];
    if (align == null) throw new Error('vfx: unknown particle align "' + def.align + '"');
    table.param(row, 4, frames, def.fps || 0, def.stretch || 0, align);
    const fl = typeof def.flicker === 'number' ? { amount: def.flicker } : def.flicker || {};
    table.param(row, 5, def.groundFade != null ? def.groundFade : 0.12, fl.amount || 0, fl.rate || 18, def.nearFade != null ? def.nearFade : 0.25);
    table.param(row, 6, def.erodeScale != null ? def.erodeScale : 0.9, def.erodeSoft != null ? def.erodeSoft : 0.15, def.erodeNoise != null ? def.erodeNoise : 0.6, def.heat || 0);
    table.param(row, 7, def.shade != null ? def.shade : 1, def.aspect || 1, def.maxStretch != null ? def.maxStretch : 3, def.erodeGlow || 0);
    const ch = typeof def.erodeChannel === 'string' ? CHANNEL[def.erodeChannel] : def.erodeChannel || CHANNEL.fbm;
    table.param(row, 8, ch[0], ch[1], ch[2], ch[3]);
    const scroll = def.noiseScroll || [0, 0];
    // soft particles: fade distance against the scene depth (m). Default: a third of the largest quad (0.04 .. 0.45 m),
    // none for floor-aligned quads (they lie ON the depth they would fade against) and for specks under 4 cm
    const maxSize = rangeMax(cd.size, 0.1);
    const soft = def.soft != null ? def.soft : align === ALIGN.flat || maxSize < 0.12 ? 0 : Math.min(0.45, Math.max(0.04, maxSize * 0.33));
    table.param(row, 9, scroll[0], scroll[1], soft, def.pull || 0);
    if (def.blend === 'distort') {
      // distortion particles read the ramp red channel as strength multiplier; scale it by def.strength
      const st = def.strength != null ? def.strength : 0.02;
      const base = toRampFn(def.color != null ? def.color : [[0, 1, 1, 1, 0], [0.2, 1, 1, 1, 1], [1, 1, 1, 1, 0]], def.alpha);
      table.writeRamp(row, (t, o) => { base(t, o); o[0] *= st; });
    }
  }

  // ---- spawning ------------------------------------------------------------------------------------------------------
  const X = new THREE.Vector3(), Y = new THREE.Vector3(), Z = new THREE.Vector3();
  const vP = new THREE.Vector3(), vD = new THREE.Vector3(), vR = new THREE.Vector3(), vT = new THREE.Vector3();
  const vA = new THREE.Vector3(), vB = new THREE.Vector3(), vO = new THREE.Vector3(), vE = new THREE.Vector3();
  const tint = new THREE.Color();
  const atN = makeAt();
  let serial = 1;

  /** unit vector in a cone of half-angle `spread` (deg, or [degX, degZ] elliptical) around d; basis hints ex, ez */
  const cA = new THREE.Vector3(), cB = new THREE.Vector3(), cT = new THREE.Vector3();
  function coneDir(d, spread, pow, ex, ez, out) {
    const u = Math.pow(rng(), pow), phi = rng() * TAU;
    let th;
    if (Array.isArray(spread)) {
      const ax = Math.max(1e-3, spread[0] * DEG), az = Math.max(1e-3, spread[1] * DEG);
      const c = Math.cos(phi), s = Math.sin(phi);
      th = Math.sqrt(u) / Math.sqrt((c / ax) * (c / ax) + (s / az) * (s / az));
    } else {
      const cm = Math.cos(Math.min(180, spread) * DEG);
      th = Math.acos(1 - u * (1 - cm));
    }
    const st = Math.sin(th);
    // the ellipse axes must be orthogonal to d: project the hints, rebuild when degenerate
    cA.copy(ex).addScaledVector(d, -ex.dot(d));
    if (cA.lengthSq() < 1e-6) { cT.set(Math.abs(d.y) < 0.99 ? 0 : 1, Math.abs(d.y) < 0.99 ? 1 : 0, 0); cA.crossVectors(cT, d); }
    cA.normalize();
    cB.crossVectors(d, cA);
    if (cB.dot(ez) < 0) cB.negate();
    return out.copy(d).multiplyScalar(Math.cos(th)).addScaledVector(cA, st * Math.cos(phi)).addScaledVector(cB, st * Math.sin(phi));
  }
  function randUnit(out) {
    const z = rng() * 2 - 1, a = rng() * TAU, r = Math.sqrt(1 - z * z);
    return out.set(r * Math.cos(a), r * Math.sin(a), z);
  }

  /**
   * Write n particles. Emission point moves from pA to pB over [tA, tB] (sub-frame spawning for moving emitters).
   * Returns the first ring slot.
   */
  function spawn(cd, at, n, tA, tB, pA, pB, emVel, own) {
    const L = cd.layer, ring = L.ring, f32 = ring.f32, stride = ring.stride;
    n = Math.min(n, ring.capacity);
    const s0 = ring.alloc(n);
    const sh = cd.shape, type = sh.type || 'point';
    const scale = at.scale;
    makeFrame(cd.dir && !at.hasDir ? cd.dir : at.dir, at.side, at.facing, X, Y, Z);
    const realtime = at.realtime || cd.realtime;
    if (at.color) tint.copy(at.color); else tint.setRGB(1, 1, 1);
    const ti = at.intensity;
    const target = at.target ? toVec3(at.target, vO) : null;
    let maxDeath = 0;
    const lineLen = type === 'line' ? (at.hasTo ? vE.copy(at.to).sub(at.pos).length() : (sh.length || 1) * scale) : 0;
    for (let i = 0; i < n; i++) {
      const fr = n > 1 ? (i + rng()) / n : rng();
      const t0 = tA + (tB - tA) * fr + sampleRange(rng, cd.delay) + at.delay;
      vP.copy(pA).lerp(pB, fr);
      // shape: local offset (vD) and radial direction (vR), both in the local frame
      let lx = 0, ly = 0, lz = 0;
      switch (type) {
        case 'sphere': {
          randUnit(vR);
          if (sh.hemi && vR.y < 0) vR.y = -vR.y;
          const inner = sh.inner || 0;
          const r = (sh.radius || 0.5) * Math.cbrt(inner * inner * inner + (1 - inner * inner * inner) * rng());
          lx = vR.x * r; ly = vR.y * r; lz = vR.z * r;
          break;
        }
        case 'disc': case 'ring': {
          const a = rng() * TAU;
          let r;
          if (type === 'ring') r = (sh.radius || 0.5) + (rng() - 0.5) * (sh.thickness || 0);
          else { const inner = sh.inner || 0; r = (sh.radius || 0.5) * Math.sqrt(inner * inner + (1 - inner * inner) * rng()); }
          vR.set(Math.cos(a), 0, Math.sin(a));
          lx = vR.x * r; lz = vR.z * r;
          ly = sh.height ? (rng() - 0.5) * sh.height : 0;
          break;
        }
        case 'cone': {
          const a = rng() * TAU, r = (sh.radius || 0) * Math.sqrt(rng());
          vR.set(Math.cos(a), 0, Math.sin(a));
          lx = vR.x * r; lz = vR.z * r;
          break;
        }
        case 'box': {
          const b = sh.size || [1, 1, 1];
          lx = (rng() - 0.5) * b[0]; ly = (rng() - 0.5) * b[1]; lz = (rng() - 0.5) * b[2];
          vR.set(lx, ly, lz); if (vR.lengthSq() < 1e-8) vR.set(0, 1, 0); vR.normalize();
          break;
        }
        case 'line': {
          const u = sh.centered === false || at.hasTo ? rng() : rng() - 0.5;
          lx = u * (at.hasTo ? 0 : sh.length || 1);
          if (at.hasTo) { vT.copy(at.to).sub(at.pos).multiplyScalar(u); }
          randUnit(vR); vR.x = 0; if (vR.lengthSq() < 1e-6) vR.set(0, 1, 0); vR.normalize();
          break;
        }
        default:
          randUnit(vR);
      }
      // to world
      const pos = vD.set(0, 0, 0).addScaledVector(X, lx).addScaledVector(Y, ly).addScaledVector(Z, lz).multiplyScalar(scale).add(vP);
      if (type === 'line' && at.hasTo) pos.add(vT);
      if (cd.jitter) { randUnit(vT); pos.addScaledVector(vT, cd.jitter * scale * Math.cbrt(rng())); }
      // radial direction to world
      const rx = vR.x, ry = vR.y, rz = vR.z;
      vR.set(0, 0, 0).addScaledVector(X, rx).addScaledVector(Y, ry).addScaledVector(Z, rz).normalize();
      // velocity direction
      const sp = cd.spread;
      switch (cd.emit) {
        case 1: coneDir(vR, sp, cd.spreadPow, X, Z, vT); break;
        case 2: randUnit(vT); break;
        case 3: vR.negate(); coneDir(vR, sp, cd.spreadPow, X, Z, vT); break;
        case 4: vA.crossVectors(Y, vR); if (vA.lengthSq() < 1e-6) vA.copy(X); vA.normalize(); coneDir(vA, sp, cd.spreadPow, X, Z, vT); break;
        case 5: coneDir(type === 'sphere' ? vR : Y, sp, cd.spreadPow, X, Z, vT); break;
        default: coneDir(Y, sp, cd.spreadPow, X, Z, vT);
      }
      if (cd.lift) vT.addScaledVector(Y, cd.lift).normalize();
      const spd = sampleRange(rng, cd.speed);
      let vx = vT.x * spd, vy = vT.y * spd, vz = vT.z * spd;
      const inv = 1 / scale;
      if (cd.vel) { vx += cd.vel.x; vy += cd.vel.y; vz += cd.vel.z; }
      vx += at.vel.x * inv; vy += at.vel.y * inv; vz += at.vel.z * inv;
      if (emVel && cd.inherit) { vx += emVel.x * cd.inherit * inv; vy += emVel.y * cd.inherit * inv; vz += emVel.z * cd.inherit * inv; }
      const life = Math.max(1e-3, sampleRange(rng, cd.life));
      const org = target || at.pos;
      let spin = sampleRange(rng, cd.spin);
      if (cd.spinBoth && rng() < 0.5) spin = -spin;
      const k = ((s0 + i) % ring.capacity) * stride;
      f32[k] = pos.x; f32[k + 1] = pos.y; f32[k + 2] = pos.z; f32[k + 3] = t0;
      f32[k + 4] = vx; f32[k + 5] = vy; f32[k + 6] = vz; f32[k + 7] = realtime ? -life : life;
      f32[k + 8] = org.x; f32[k + 9] = org.y; f32[k + 10] = org.z; f32[k + 11] = cd.row;
      f32[k + 12] = Y.x; f32[k + 13] = Y.y; f32[k + 14] = Y.z; f32[k + 15] = scale;
      f32[k + 16] = sampleRange(rng, cd.size) * scale; f32[k + 17] = sampleRange(rng, cd.rotation); f32[k + 18] = spin; f32[k + 19] = rng();
      f32[k + 20] = tint.r * ti; f32[k + 21] = tint.g * ti; f32[k + 22] = tint.b * ti; f32[k + 23] = at.alpha;
      ring.owner[(s0 + i) % ring.capacity] = own;
      if (t0 + life > maxDeath) maxDeath = t0 + life;
    }
    ring.dirty(s0, n);
    ring.commit();
    L.mesh.visible = true;
    if (realtime) { if (maxDeath > L.maxDeathReal) L.maxDeathReal = maxDeath; table.touch(cd.row, clock.game + (maxDeath - clock.real)); }
    else { if (maxDeath > L.maxDeath) L.maxDeath = maxDeath; table.touch(cd.row, maxDeath); }
    return s0;
  }

  /** kill the slots written by spawn serial `own` within [s, s+n) */
  function killRange(L, s, n, own) {
    const ring = L.ring;
    for (let i = 0; i < n; i++) {
      const j = (s + i) % ring.capacity;
      if (ring.owner[j] === own) ring.f32[j * ring.stride + 7] = 0;
    }
    ring.dirty(s, n);
  }

  function scaledCount(c) {
    if (c <= 0) return 0;
    return Math.max(1, Math.round(c * q.particleScale));
  }

  /**
   * One-shot burst. `at` = { pos, dir?, side?, facing?, scale?, color?, intensity?, alpha?, count?, vel?, to?, target?, delay?, realtime? }
   * (or just a position). Returns a handle { kill(), alive }.
   */
  function burst(def, at) {
    const cd = compile(def);
    normalizeAt(at, atN);
    const n = scaledCount(atN.count != null ? atN.count : Math.round(sampleRange(rng, cd.count)));
    const now = (atN.realtime || cd.realtime) ? clock.real : clock.game;
    const own = serial++;
    const L = cd.layer;
    const s0 = n > 0 ? spawn(cd, atN, n, now, now, atN.pos, atN.pos, null, own) : 0;
    const end = now + cd.maxLife + atN.delay;
    const rtm = atN.realtime || cd.realtime;
    const h = {
      get alive() { return (rtm ? clock.real : clock.game) < end && !h._dead; },
      _dead: false,
      kill() { if (!h._dead) { h._dead = true; if (n) killRange(L, s0, n, own); } },
      stop() {},
    };
    shared.track(h);
    return h;
  }

  // ---- continuous emitters -----------------------------------------------------------------------------------------
  const emitters = [];
  const tmpV = new THREE.Vector3();

  /**
   * Continuous emitter. Returns h with: pos (Vector3, live), dir (Vector3, live), rate (particles/s before quality
   * scaling, live), scale, color (THREE.Color|null), intensity, follow(object3D, offset?), setPosition(v), stop(), kill(), alive.
   */
  function emitter(def, at) {
    const cd = compile(def);
    const a0 = normalizeAt(at, makeAt());
    const h = {
      pos: a0.pos.clone(), dir: a0.dir.clone(), rate: cd.rate, perMeter: cd.perMeter, scale: a0.scale,
      color: a0.color ? a0.color.clone() : null, intensity: a0.intensity, alpha: a0.alpha, facing: a0.facing,
      duration: at && at.duration != null ? at.duration : cd.duration,
      _cd: cd, _at: a0, _prev: a0.pos.clone(), _acc: 0, _accD: 0, _t: 0, _emitting: true, _dead: false, _follow: null,
      _offset: new THREE.Vector3(), _orient: false, _serial: serial++, _ranges: [], _end: 0,
      get alive() { return !h._dead && (h._emitting || (h._cd.realtime || a0.realtime ? clock.real : clock.game) < h._end); },
      follow(obj, offset, orient = false) { h._follow = obj; if (offset) toVec3(offset, h._offset); else h._offset.set(0, 0, 0); h._orient = orient; sampleFollow(h); h._prev.copy(h.pos); return h; },
      setPosition(v) { toVec3(v, h.pos); return h; },
      stop() { h._emitting = false; return h; },
      kill() {
        if (h._dead) return;
        h._dead = true; h._emitting = false;
        const r = h._ranges;
        for (let i = 0; i < r.length; i += 2) killRange(cd.layer, r[i], r[i + 1], h._serial);
        r.length = 0;
      },
    };
    emitters.push(h);
    shared.track(h);
    return h;
  }

  function sampleFollow(h) {
    const o = h._follow;
    if (!o) return;
    if (o.isObject3D) {
      o.updateWorldMatrix(true, false);
      h.pos.copy(h._offset).applyMatrix4(o.matrixWorld);
      if (h._orient) h.dir.set(0, 1, 0).transformDirection(o.matrixWorld);
    } else toVec3(o, h.pos).add(h._offset);
  }

  function updateEmitters(dtGame, dtReal) {
    for (let i = emitters.length - 1; i >= 0; i--) {
      const h = emitters[i];
      if (!h.alive) { emitters.splice(i, 1); continue; }
      if (!h._emitting) continue;
      const cd = h._cd, a = h._at;
      const rt = cd.realtime || a.realtime;
      const dt = rt ? dtReal : dtGame;
      sampleFollow(h);
      if (dt <= 0) { h._prev.copy(h.pos); continue; }
      h._t += dt;
      let n = 0;
      if (h.rate > 0) { const c = h.rate * q.particleScale * dt + h._acc; n = Math.floor(c); h._acc = c - n; }
      const dist = h._prev.distanceTo(h.pos);
      if (h.perMeter > 0) { const c = dist * h.perMeter * q.particleScale + h._accD; const m = Math.floor(c); h._accD = c - m; n += m; }
      if (n > 0) {
        const now = rt ? clock.real : clock.game;
        a.pos.copy(h.pos); a.dir.copy(h.dir); a.hasDir = true; a.scale = h.scale; a.intensity = h.intensity; a.alpha = h.alpha; a.facing = h.facing;
        a.color = h.color;
        tmpV.copy(h.pos).sub(h._prev).multiplyScalar(1 / dt);
        const s0 = spawn(cd, a, n, now - dt, now, h._prev, h.pos, tmpV, h._serial);
        const r = h._ranges;
        if (r.length >= 2 && (r[r.length - 2] + r[r.length - 1]) % cd.layer.ring.capacity === s0) r[r.length - 1] += n;
        else r.push(s0, n);
        if (r.length > 64) r.splice(0, 2);
        h._end = now + cd.maxLife;
      }
      h._prev.copy(h.pos);
      if (h.duration > 0 && h._t >= h.duration) h._emitting = false;
    }
  }

  /** Register a named definition (usable as a string in burst / emitter). Returns the compiled definition. */
  function particleDef(name, def) {
    const cd = compile(def);
    named.set(name, cd);
    return cd;
  }

  const api = {
    burst, emitter, particleDef,
    particles: { compile, layers, table, emitters, ALIGN, EMIT },
  };

  return {
    name: 'particles',
    api,
    update(dtGame, dtReal) {
      updateEmitters(dtGame, dtReal);
      table.commit();
      for (const k in layers) {
        const L = layers[k];
        L.ring.commit();
        L.mesh.visible = clock.game < L.maxDeath || clock.real < L.maxDeathReal;
      }
    },
    clear() {
      for (const h of emitters) { h._dead = true; h._emitting = false; }
      emitters.length = 0;
      // the facade rebases the clocks to 0 after clear(): kill every stored particle so none can be "reborn"
      for (const k in layers) {
        const L = layers[k], r = L.ring;
        for (let i = 0; i < r.capacity; i++) r.f32[i * r.stride + 7] = 0;
        r.dirty(0, r.capacity);
        L.maxDeath = -1; L.maxDeathReal = -1; L.mesh.visible = false;
      }
      table.busyUntil.fill(0);
    },
    meshes: [layers.alpha.mesh, layers.add.mesh, layers.distort.mesh],
    dispose() { for (const k in layers) { layers[k].ring.dispose(); layers[k].mat.dispose(); layers[k].mesh.removeFromParent(); } table.dispose(); },
  };
}
