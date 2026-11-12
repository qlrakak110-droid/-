// Screen-space refraction sprites rendered into ctx.post.distortionScene (fragment .rg = signed UV offset):
//   shock  expanding refractive ring (camera-facing, or flat with a world normal: ground shockwaves)
//   heat   rising heat haze (flow-noise driven shimmer in a soft disc)
//   lens   bulge (strength > 0) or pinch (strength < 0) lens, for charge-ups and gravity wells
// One instanced draw; the mesh is hidden whenever nothing is alive, so the post pass skips the distortion buffer.

import * as THREE from 'three';
import { InstanceRing } from './instanced.js';
import { EffectPool } from './pool.js';
import { toVec3 } from './util.js';

const KIND = { shock: 0, heat: 1, lens: 2 };
const LAYOUT = { iPosT: 4, iNrmL: 4, iShape: 4, iMisc: 4 };

const VERT = /* glsl */ `
precision highp float;
uniform float uTime, uTimeReal;
attribute vec4 iPosT, iNrmL, iShape, iMisc;
varying vec2 vP;
varying vec4 vK;
varying vec4 vS;      // screen-space images of the local axes (x axis .xy, y axis .zw)
varying float vT;
void main() {
  float life = abs(iNrmL.w);
  float tau = (iNrmL.w < 0.0 ? uTimeReal : uTime) - iPosT.w;
  if (tau < 0.0 || tau >= life) { gl_Position = vec4(0.0, 0.0, 2.0, 1.0); return; }
  float t = tau / life;
  int kind = int(iShape.x + 0.5);
  float grow = kind == 0 ? 1.0 - pow(1.0 - t, 4.0) : 1.0 - pow(2.0, -8.0 * t);
  float R = mix(iShape.y, iShape.z, grow);
  float half_ = kind == 0 ? R * (1.0 + iMisc.x * 2.5) + 0.05 : R;
  vec2 c = position.xy;
  vec3 n = iNrmL.xyz;
  vec4 clip;
  if (dot(n, n) > 1e-6) {
    vec3 T = normalize(cross(n, abs(n.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
    vec3 B = cross(n, T);
    vec3 wp = iPosT.xyz + (T * c.x + B * c.y) * half_;
    clip = projectionMatrix * viewMatrix * vec4(wp, 1.0);
    vec4 c0 = projectionMatrix * viewMatrix * vec4(iPosT.xyz, 1.0);
    vec4 cx = projectionMatrix * viewMatrix * vec4(iPosT.xyz + T * 0.05, 1.0);
    vec4 cy = projectionMatrix * viewMatrix * vec4(iPosT.xyz + B * 0.05, 1.0);
    vS = vec4(cx.xy / cx.w - c0.xy / c0.w, cy.xy / cy.w - c0.xy / c0.w);
  } else {
    vec4 mv = viewMatrix * vec4(iPosT.xyz, 1.0);
    mv.xy += c * half_;
    clip = projectionMatrix * mv;
    vS = vec4(1.0, 0.0, 0.0, 1.0);
  }
  gl_Position = clip;
  vP = c;
  float atk = iMisc.y;
  float env = tau < atk ? tau / max(atk, 1e-4) : pow(max(0.0, 1.0 - (tau - atk) / max(life - atk, 1e-4)), iMisc.z);
  // a ring cannot push pixels further than its own size: strength ramps in as a shock expands
  float ramp = kind == 0 ? smoothstep(0.0, 0.45, grow) : 1.0;
  vK = vec4(iShape.x, iShape.w * env * ramp, R / half_, iMisc.x);
  vT = tau + iMisc.w * 17.0;
}`;

const FRAG = /* glsl */ `
precision highp float;
uniform sampler2D uFlow;
varying vec2 vP;
varying vec4 vK;
varying vec4 vS;
varying float vT;
void main() {
  int kind = int(vK.x + 0.5);
  float r = length(vP);
  vec2 dirL = r > 1e-4 ? vP / r : vec2(0.0);
  vec2 dirS = dirL.x * vS.xy + dirL.y * vS.zw;
  float ls = length(dirS);
  dirS = ls > 1e-6 ? dirS / ls : vec2(0.0);
  vec2 o = vec2(0.0);
  if (kind == 0) {
    float w = max(vK.w, 0.02);
    float d = (r - vK.z) / (w * vK.z + 1e-3);
    o = dirS * (d * exp(-d * d)) * 1.6 * vK.y;
  } else if (kind == 1) {
    vec2 f = texture2D(uFlow, vP * 0.35 + vec2(0.0, -vT * 0.45)).ba * 2.0 - 1.0;
    vec2 f2 = texture2D(uFlow, vP * 0.8 + vec2(0.37, -vT * 0.9)).ba * 2.0 - 1.0;
    float m = smoothstep(1.0, 0.25, r);
    o = (f * 0.7 + f2 * 0.5) * m * vK.y;
  } else {
    float m = r < 1.0 ? r * pow(1.0 - r * r, 2.0) : 0.0;
    o = -dirS * m * 2.0 * vK.y;
  }
  gl_FragColor = vec4(o, 0.0, 0.0);
}`;

/**
 * @param {object} vfx
 * @param {object} shared
 */
export function installDistort(vfx, shared) {
  const { ctx, clock, uniforms, textures } = shared;
  const CAP = 24;
  const ring = new InstanceRing(CAP, LAYOUT);
  const pool = new EffectPool(shared, CAP);
  const mat = new THREE.ShaderMaterial({
    vertexShader: VERT, fragmentShader: FRAG,
    uniforms: { uTime: uniforms.uTime, uTimeReal: uniforms.uTimeReal, uFlow: { value: textures.flow } },
    transparent: true, depthWrite: false, depthTest: false,
    blending: THREE.CustomBlending, blendSrc: THREE.OneFactor, blendDst: THREE.OneFactor, blendSrcAlpha: THREE.OneFactor, blendDstAlpha: THREE.OneFactor,
  });
  const mesh = new THREE.Mesh(ring.geometry, mat);
  mesh.frustumCulled = false;
  mesh.visible = false;
  mesh.name = 'vfx.distort';
  ctx.post.distortionScene.add(mesh);
  const v = new THREE.Vector3();
  let maxDeath = -1, maxDeathReal = -1;
  pool.onFree = (s) => { ring.f32[s.i * ring.stride + 7] = 0; ring.dirty(s.i, 1); };

  /**
   * Screen-space refraction.
   * opts: pos, kind ('shock' | 'heat' | 'lens', default 'shock'), radius (m; or [start, end]: shock default [0.2, 2.5],
   * heat/lens default 0.8), strength (UV offset, shock 0.035, heat 0.012, lens 0.04; lens < 0 pinches), width (shock
   * band width as a fraction of the radius, 0.18), life (s: shock 0.45, heat 1.2, lens 0.6), attack (s), decay (power),
   * normal ([x, y, z] world normal for a flat ring, omit for camera-facing), follow, offset, realtime.
   * Returns { kill(), stop(), follow(obj, offset), alive }.
   */
  function distort(opts = {}) {
    const kind = KIND[opts.kind || 'shock'];
    if (kind == null) throw new Error('vfx: unknown distort kind "' + opts.kind + '"');
    const realtime = !!opts.realtime;
    const life = opts.life != null ? opts.life : kind === 0 ? 0.45 : kind === 1 ? 1.2 : 0.6;
    const { slot, handle } = pool.alloc({ life, realtime });
    toVec3(opts.pos, slot.pos);
    if (opts.follow) { slot.follow = opts.follow; if (opts.offset) toVec3(opts.offset, slot.offset); pool.place(slot); }
    const rad = opts.radius != null ? opts.radius : kind === 0 ? [0.2, 2.5] : 0.8;
    const r0 = Array.isArray(rad) ? rad[0] : rad, r1 = Array.isArray(rad) ? rad[1] : rad;
    const strength = opts.strength != null ? opts.strength : kind === 0 ? 0.035 : kind === 1 ? 0.012 : 0.04;
    const f = ring.f32, k = slot.i * ring.stride;
    if (opts.normal) toVec3(opts.normal, v).normalize(); else v.set(0, 0, 0);
    f[k] = slot.pos.x; f[k + 1] = slot.pos.y; f[k + 2] = slot.pos.z; f[k + 3] = slot.t0;
    f[k + 4] = v.x; f[k + 5] = v.y; f[k + 6] = v.z; f[k + 7] = realtime ? -life : life;
    f[k + 8] = kind; f[k + 9] = r0; f[k + 10] = r1; f[k + 11] = strength;
    f[k + 12] = opts.width != null ? opts.width : 0.18;
    f[k + 13] = opts.attack != null ? opts.attack : kind === 0 ? 0.0 : 0.15;
    f[k + 14] = opts.decay != null ? opts.decay : kind === 0 ? 1.5 : 1.2;
    f[k + 15] = shared.rng();
    ring.dirty(slot.i, 1);
    ring.highWater = Math.max(ring.highWater, slot.i + 1);
    const end = slot.t0 + life;
    if (realtime) maxDeathReal = Math.max(maxDeathReal, end); else maxDeath = Math.max(maxDeath, end);
    ring.commit();
    mesh.visible = true;
    return handle;
  }

  return {
    name: 'distort',
    api: { distort },
    update() {
      pool.forEach((s) => {
        if (s.stopping) {
          const k = s.i * ring.stride, nl = Math.min(s.life, pool.age(s) + 0.15);
          ring.f32[k + 7] = s.realtime ? -nl : nl; s.life = nl; s.stopping = false;
          ring.dirty(s.i, 1);
        }
        if (pool.place(s)) {
          const k = s.i * ring.stride;
          ring.f32[k] = s.pos.x; ring.f32[k + 1] = s.pos.y; ring.f32[k + 2] = s.pos.z;
          ring.dirty(s.i, 1);
        }
      });
      ring.commit();
      mesh.visible = pool.live > 0 && (clock.game < maxDeath || clock.real < maxDeathReal);
    },
    clear() { pool.clear(); maxDeath = maxDeathReal = -1; mesh.visible = false; },
    dispose() { ring.dispose(); mat.dispose(); mesh.removeFromParent(); },
  };
}
