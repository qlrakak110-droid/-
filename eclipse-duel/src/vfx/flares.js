// Camera-facing flares: procedural (resolution independent) glow / star / anamorphic streak / ring / flash shapes with
// an analytic life envelope. All flares share one instanced draw call; only following flares are rewritten per frame.

import * as THREE from 'three';
import { InstanceRing } from './instanced.js';
import { EffectPool } from './pool.js';
import { toVec3, toColor, RENDER_ORDER } from './util.js';

const KIND = { glow: 0, star: 1, streak: 2, ring: 3, flash: 4 };
const LAYOUT = { iPosT: 4, iColL: 4, iShape: 4, iEnv: 4, iDir: 4 };

const VERT = /* glsl */ `
precision highp float;
uniform float uTime, uTimeReal;
attribute vec4 iPosT, iColL, iShape, iEnv, iDir;
varying vec2 vP;
varying vec4 vCol;
varying vec4 vK;
void main() {
  float life = abs(iColL.w);
  float tau = (iColL.w < 0.0 ? uTimeReal : uTime) - iPosT.w;
  if (tau < 0.0 || tau >= life) { gl_Position = vec4(0.0, 0.0, 2.0, 1.0); return; }
  float t = tau / life;
  // envelope: attack (s) then a power fall-off over the rest of the life
  float atk = iEnv.x;
  float env = tau < atk ? smoothstep(0.0, 1.0, tau / max(atk, 1e-4)) : pow(max(0.0, 1.0 - (tau - atk) / max(life - atk, 1e-4)), iEnv.y);
  float grow = 1.0 - pow(2.0, -10.0 * t);   // outExpo
  float size = mix(iShape.y, iShape.z, grow);
  vec4 mv = viewMatrix * vec4(iPosT.xyz, 1.0);
  float pull = min(iEnv.w, max(-mv.z - 0.3, 0.0));
  mv.xyz += normalize(-mv.xyz) * pull;
  float zc = max(-mv.z, 0.05);
  float hs = iDir.w > 0.5 ? size * zc / projectionMatrix[1][1] : size * 0.5;
  float aspect = iShape.w;
  float rot = iEnv.z;
  if (dot(iDir.xyz, iDir.xyz) > 1e-6) { vec3 d = mat3(viewMatrix) * iDir.xyz; rot += atan(d.y, d.x); }
  vec2 c = position.xy;
  vec2 q = vec2(c.x * hs * aspect, c.y * hs);
  float cr = cos(rot), sr = sin(rot);
  mv.xy += vec2(q.x * cr - q.y * sr, q.x * sr + q.y * cr);
  gl_Position = projectionMatrix * mv;
  vP = c;
  vCol = vec4(iColL.rgb * env, t);
  vK = vec4(iShape.x, aspect, grow, 0.0);
}`;

const FRAG = /* glsl */ `
precision highp float;
varying vec2 vP;
varying vec4 vCol;
varying vec4 vK;
void main() {
  int kind = int(vK.x + 0.5);
  vec2 p = vP;
  float r = length(p), I = 0.0;
  float edge = max(0.0, 1.0 - r * r);
  if (kind == 0) {            // glow: white-hot pin + soft halo
    I = exp(-r * r * 90.0) * 2.5 + exp(-r * r * 14.0) * 0.6 + exp(-r * 4.5) * 0.35;
    I *= edge * edge;
  } else if (kind == 1) {     // star: four long rays, four short diagonals, hot core
    vec2 a = abs(p);
    float rx = exp(-a.y * 70.0 / max(0.05, 1.0 - a.x)) * pow(max(0.0, 1.0 - a.x), 2.5);
    float ry = exp(-a.x * 70.0 / max(0.05, 1.0 - a.y)) * pow(max(0.0, 1.0 - a.y), 2.5);
    vec2 d = vec2(p.x + p.y, p.x - p.y) * 0.7071;
    vec2 ad = abs(d);
    float dg = (exp(-ad.y * 90.0 / max(0.05, 1.0 - ad.x * 1.8)) * pow(max(0.0, 1.0 - ad.x * 1.8), 3.0) + exp(-ad.x * 90.0 / max(0.05, 1.0 - ad.y * 1.8)) * pow(max(0.0, 1.0 - ad.y * 1.8), 3.0)) * 0.45;
    I = (rx + ry) * 1.3 + dg + exp(-r * r * 120.0) * 2.5 + exp(-r * 6.0) * 0.3 * edge;
  } else if (kind == 2) {     // anamorphic streak (quad is wide: p.x spans the length)
    float ax = abs(p.x), ay = abs(p.y);
    float along = pow(max(0.0, 1.0 - ax), 1.6);
    I = exp(-ay * ay * 60.0) * along * 1.4 + exp(-ay * ay * 900.0) * pow(max(0.0, 1.0 - ax), 0.7) * 1.8;
    float rr = length(vec2(p.x * vK.y, p.y));
    I += exp(-rr * rr * 2.5) * 1.6;
  } else if (kind == 3) {     // ring
    float w = 0.06 + 0.1 * (1.0 - vK.z);
    I = exp(-pow((r - 0.86) / w, 2.0)) * 1.2 + exp(-pow((r - 0.86) / (w * 0.3), 2.0)) * 0.8;
  } else {                    // flash: wide soft bloom
    I = exp(-r * r * 3.0) * edge;
  }
  gl_FragColor = vec4(vCol.rgb * I, 0.0);
}`;

/**
 * @param {object} vfx
 * @param {object} shared
 */
export function installFlares(vfx, shared) {
  const { clock, root, uniforms } = shared;
  const CAP = 64;
  const ring = new InstanceRing(CAP, LAYOUT);
  const pool = new EffectPool(shared, CAP);
  const mat = new THREE.ShaderMaterial({
    vertexShader: VERT, fragmentShader: FRAG, uniforms: { uTime: uniforms.uTime, uTimeReal: uniforms.uTimeReal },
    transparent: true, depthWrite: false, depthTest: true,
    blending: THREE.CustomBlending, blendSrc: THREE.OneFactor, blendDst: THREE.OneFactor, blendSrcAlpha: THREE.OneFactor, blendDstAlpha: THREE.OneFactor,
  });
  const mesh = new THREE.Mesh(ring.geometry, mat);
  mesh.frustumCulled = false;
  mesh.renderOrder = RENDER_ORDER.flares;
  mesh.visible = false;
  mesh.name = 'vfx.flares';
  root.add(mesh);
  const col = new THREE.Color();
  const v = new THREE.Vector3();
  let maxDeath = -1, maxDeathReal = -1;
  pool.onFree = (s) => { ring.f32[s.i * ring.stride + 7] = 0; ring.dirty(s.i, 1); };

  /**
   * Camera-facing flare.
   * opts: pos, kind ('glow' | 'star' | 'streak' | 'ring' | 'flash', default 'glow'), color (HDR, default [6, 4, 2.5]),
   * intensity (multiplier, 1), size (m; or [start, end] grown with outExpo), aspect (width / height; default 1, streak 8),
   * life (s, 0.25), attack (s, 0), decay (fall-off power, 2), rotation (rad), dir (world direction the long axis
   * follows on screen), pull (m toward the camera, 0.3), screen (size is a fraction of the screen height), follow, offset,
   * realtime. Returns { kill(), stop(), follow(obj, offset), alive }.
   */
  function flare(opts = {}) {
    const realtime = !!opts.realtime;
    const life = Math.min(opts.life != null ? opts.life : 0.25, 1e6);
    const { slot, handle } = pool.alloc({ life, realtime });
    const kind = KIND[opts.kind || 'glow'];
    if (kind == null) throw new Error('vfx: unknown flare kind "' + opts.kind + '"');
    toVec3(opts.pos, slot.pos);
    if (opts.follow) { slot.follow = opts.follow; if (opts.offset) toVec3(opts.offset, slot.offset); pool.place(slot); }
    toColor(opts.color != null ? opts.color : [6, 4, 2.5], col);
    const inten = opts.intensity != null ? opts.intensity : 1;
    const size = opts.size != null ? opts.size : 0.6;
    const s0 = Array.isArray(size) ? size[0] : size, s1 = Array.isArray(size) ? size[1] : size;
    const aspect = opts.aspect != null ? opts.aspect : kind === 2 ? 8 : 1;
    const f = ring.f32, k = slot.i * ring.stride;
    f[k] = slot.pos.x; f[k + 1] = slot.pos.y; f[k + 2] = slot.pos.z; f[k + 3] = slot.t0;
    f[k + 4] = col.r * inten; f[k + 5] = col.g * inten; f[k + 6] = col.b * inten; f[k + 7] = realtime ? -life : life;
    f[k + 8] = kind; f[k + 9] = s0; f[k + 10] = s1; f[k + 11] = aspect;
    f[k + 12] = opts.attack != null ? opts.attack : 0; f[k + 13] = opts.decay != null ? opts.decay : 2; f[k + 14] = opts.rotation || 0; f[k + 15] = opts.pull != null ? opts.pull : 0.3;
    if (opts.dir) toVec3(opts.dir, v).normalize(); else v.set(0, 0, 0);
    f[k + 16] = v.x; f[k + 17] = v.y; f[k + 18] = v.z; f[k + 19] = opts.screen ? 1 : 0;
    ring.dirty(slot.i, 1);
    ring.highWater = Math.max(ring.highWater, slot.i + 1);
    const end = slot.t0 + life;
    if (realtime) maxDeathReal = Math.max(maxDeathReal, end); else maxDeath = Math.max(maxDeath, end);
    ring.commit();
    mesh.visible = true;
    return handle;
  }

  function visit(s) {
      if (s.stopping) {
        // stop(): shorten the life so the shader's fall-off finishes over 0.12 s
        const k = s.i * ring.stride, age = pool.age(s);
        const nl = Math.min(s.life, age + 0.12);
        ring.f32[k + 7] = s.realtime ? -nl : nl; s.life = nl; s.stopping = false;
        ring.dirty(s.i, 1);
      }
      if (pool.place(s)) {
        const k = s.i * ring.stride;
        ring.f32[k] = s.pos.x; ring.f32[k + 1] = s.pos.y; ring.f32[k + 2] = s.pos.z;
        ring.dirty(s.i, 1);
      }
  }

  return {
    name: 'flares',
    api: { flare },
    update() {
      pool.forEach(visit);
      ring.commit();
      mesh.visible = pool.live > 0 && (clock.game < maxDeath || clock.real < maxDeathReal);
    },
    clear() { pool.clear(); maxDeath = maxDeathReal = -1; mesh.visible = false; },
    dispose() { ring.dispose(); mat.dispose(); mesh.removeFromParent(); },
  };
}
