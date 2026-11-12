// Building blocks shared by the shader-driven mesh effects (slash, ring, pillar, beam, decal, speedlines):
//   gridGeometry   instanced template grid (position = (u, v, layer) in [0, 1]; the vertex shader builds the shape)
//   MeshLayer      one pooled instanced mesh per effect type (+ optional refraction twin in post.distortionScene):
//                  EffectPool slot i <-> instance i, analytic life in the shader, one draw call for every live instance
//   materials      premultiplied / additive / distortion ShaderMaterial presets (CONTRACT blending conventions)
//   resolveColors  look + palette + overrides -> core / mid / tail HDR colours
//   planeQuat      orientation from { quat } or { normal, forward, roll, facing }

import * as THREE from 'three';
import { InstanceRing } from './instanced.js';
import { EffectPool } from './pool.js';
import { toVec3, toColor } from './util.js';
import { PALETTE } from './library.js';
import { DEG } from '../core/math.js';

/**
 * Instanced template grid: (nu + 1) x (nv + 1) vertices per layer with position = (u, v, layer), u, v in [0, 1].
 * Quads are indexed (two triangles each). Several layers are stacked in one geometry (pillar core + sheath shells).
 */
export function gridGeometry(nu, nv, layers = 1) {
  const g = new THREE.InstancedBufferGeometry();
  const nvert = (nu + 1) * (nv + 1);
  const pos = new Float32Array(nvert * layers * 3);
  const idx = [];
  for (let l = 0; l < layers; l++) {
    const base = l * nvert;
    for (let j = 0; j <= nv; j++) {
      for (let i = 0; i <= nu; i++) {
        const k = (base + j * (nu + 1) + i) * 3;
        pos[k] = i / nu; pos[k + 1] = j / nv; pos[k + 2] = l;
      }
    }
    for (let j = 0; j < nv; j++) {
      for (let i = 0; i < nu; i++) {
        const a = base + j * (nu + 1) + i, b = a + 1, c = a + nu + 1, d = c + 1;
        idx.push(a, b, d, a, d, c);
      }
    }
  }
  g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  g.setIndex(idx);
  g.instanceCount = 0;
  return g;
}

/** Premultiplied blending (output vec4(rgb * a, a * (1 - additive))): additive, alpha or anything between. */
export const PREMUL = {
  transparent: true, depthWrite: false, depthTest: true,
  blending: THREE.CustomBlending, blendEquation: THREE.AddEquation,
  blendSrc: THREE.OneFactor, blendDst: THREE.OneMinusSrcAlphaFactor, blendSrcAlpha: THREE.OneFactor, blendDstAlpha: THREE.OneMinusSrcAlphaFactor,
};
/** Pure additive (distortion buffer: signed UV offsets add up). */
export const ADDITIVE = {
  transparent: true, depthWrite: false, depthTest: false,
  blending: THREE.CustomBlending, blendEquation: THREE.AddEquation,
  blendSrc: THREE.OneFactor, blendDst: THREE.OneFactor, blendSrcAlpha: THREE.OneFactor, blendDstAlpha: THREE.OneFactor,
};

/**
 * One instanced mesh per effect type. Slot i of the EffectPool owns instance i of the ring; the life float at
 * `lifeAt` (signed: < 0 = real time) is zeroed when a slot is freed so the shader culls it. Hidden when idle.
 */
export class MeshLayer {
  /**
   * @param {object} shared  vfx shared resources
   * @param {object} o  { name, capacity, layout, geometry, material, renderOrder, lifeAt, distortMaterial?, parent? }
   */
  constructor(shared, o) {
    this.shared = shared;
    this.ring = new InstanceRing(o.capacity, o.layout, o.geometry);
    this.pool = new EffectPool(shared, o.capacity);
    this.lifeAt = o.lifeAt;
    this.visit = null;
    const mesh = new THREE.Mesh(this.ring.geometry, o.material);
    mesh.frustumCulled = false;
    mesh.renderOrder = o.renderOrder || 0;
    mesh.visible = false;
    mesh.name = 'vfx.' + o.name;
    (o.parent || shared.root).add(mesh);
    this.mesh = mesh;
    this.dmesh = null;
    if (o.distortMaterial) {
      const d = new THREE.Mesh(this.ring.geometry, o.distortMaterial);
      d.frustumCulled = false;
      d.visible = false;
      d.name = 'vfx.' + o.name + '.distort';
      shared.ctx.post.distortionScene.add(d);
      this.dmesh = d;
    }
    const ring = this.ring;
    this.pool.onFree = (s) => {
      ring.f32[s.i * ring.stride + this.lifeAt] = 0;
      ring.dirty(s.i, 1);
      s.distort = false;
      if (this.onFree) this.onFree(s);
    };
  }

  /** Take a slot: returns { slot, handle, f (Float32Array), k (float offset of the slot) }. */
  alloc(life, realtime) {
    const { slot, handle } = this.pool.alloc({ life, realtime: !!realtime });
    const ring = this.ring;
    ring.highWater = Math.max(ring.highWater, slot.i + 1);
    slot.distort = false;
    return { slot, handle, f: ring.f32, k: slot.i * ring.stride };
  }

  /** Upload a written slot and show the mesh. */
  commit(slot) {
    this.ring.dirty(slot.i, 1);
    this.ring.commit();
    this.mesh.visible = true;
    if (slot.distort && this.dmesh) this.dmesh.visible = true;
  }

  /** Per frame: free expired slots, call `this.visit(slot, age)` on live ones, upload, toggle visibility. */
  update() {
    const pool = this.pool, slots = pool.slots;
    let anyD = false;
    for (let i = 0; i < slots.length; i++) {
      const s = slots[i];
      if (!s.live) continue;
      const age = pool.age(s);
      if (age >= s.life) { pool._free(s); continue; }
      if (this.visit) this.visit(s, age);
      if (s.distort) anyD = true;
    }
    this.ring.commit();
    this.mesh.visible = pool.live > 0;
    if (this.dmesh) this.dmesh.visible = anyD;
  }

  /** Write the slot position from its follow target (if any). Returns true when it moved. */
  follow(s, at = 0) {
    if (!this.pool.place(s)) return false;
    const f = this.ring.f32, k = s.i * this.ring.stride + at;
    f[k] = s.pos.x; f[k + 1] = s.pos.y; f[k + 2] = s.pos.z;
    this.ring.dirty(s.i, 1);
    return true;
  }

  /** Rewrite the signed life of slot s (stop(): shorten an infinite life). */
  setLife(s, life) {
    s.life = life;
    this.ring.f32[s.i * this.ring.stride + this.lifeAt] = s.realtime ? -life : life;
    this.ring.dirty(s.i, 1);
  }

  clear() { this.pool.clear(); this.ring.commit(); this.mesh.visible = false; if (this.dmesh) this.dmesh.visible = false; }

  dispose() {
    this.ring.dispose();
    this.mesh.material.dispose();
    this.mesh.removeFromParent();
    if (this.dmesh) { this.dmesh.material.dispose(); this.dmesh.removeFromParent(); }
  }
}

const _c = new THREE.Color();
/**
 * Colours of a mesh effect: palette (name in vfx.palette or { core, mid, tail, smoke }) chosen by opts.palette, then
 * the look's default; individual overrides opts.core / opts.color (alias opts.mid) / opts.tail. `tailFrom` lets a look
 * take its tail from another palette entry ('smoke' for fire that cools into dark smoke).
 * Writes HDR linear values into out = { core: Color, mid: Color, tail: Color }.
 */
export function resolveColors(opts, look, out) {
  const pn = opts.palette != null ? opts.palette : look.palette || 'ember';
  const pal = typeof pn === 'string' ? PALETTE[pn] : pn;
  if (!pal) throw new Error('vfx: unknown palette "' + pn + '" (have: ' + Object.keys(PALETTE).join(', ') + ')');
  toColor(opts.core != null ? opts.core : look.core || pal.core, out.core);
  toColor(opts.color != null ? opts.color : opts.mid != null ? opts.mid : look.mid || pal.mid, out.mid);
  const tf = look.tailFrom && pal[look.tailFrom] ? pal[look.tailFrom] : pal.tail;
  toColor(opts.tail != null ? opts.tail : look.tail || tf, out.tail);
  return out;
}
export function makeColors() { return { core: new THREE.Color(), mid: new THREE.Color(), tail: new THREE.Color() }; }

const _f = new THREE.Vector3(), _n = new THREE.Vector3(), _y = new THREE.Vector3(), _m = new THREE.Matrix4();
/**
 * Orientation of a planar effect (local X = forward, local Z = plane normal, local Y = Z x X):
 *   opts.quat                          THREE.Quaternion | [x, y, z, w] (used as is), else
 *   opts.normal  (default defNormal)   plane normal
 *   opts.forward (default [1, 0, 0])   in-plane direction of angle 0 (made orthogonal to the normal)
 *   opts.roll    (deg, 0)              rotation of the plane around forward
 *   opts.facing  (±1)                  -1 mirrors across the fighter's YZ plane (P2): forward.x and the normal flip
 */
export function planeQuat(opts, out, defNormal = [0, 0, 1]) {
  if (opts.quat) {
    if (opts.quat.isQuaternion) return out.copy(opts.quat);
    return out.set(opts.quat[0], opts.quat[1], opts.quat[2], opts.quat[3]).normalize();
  }
  toVec3(opts.forward != null ? opts.forward : [1, 0, 0], _f);
  toVec3(opts.normal != null ? opts.normal : defNormal, _n);
  if (opts.facing != null && opts.facing < 0) { _f.x = -_f.x; _n.x = -_n.x; _n.negate(); }
  if (_n.lengthSq() < 1e-10) _n.set(0, 0, 1);
  _n.normalize();
  _f.addScaledVector(_n, -_f.dot(_n));
  if (_f.lengthSq() < 1e-8) { _f.set(1, 0, 0).addScaledVector(_n, -_n.x); if (_f.lengthSq() < 1e-8) _f.set(0, 1, 0).addScaledVector(_n, -_n.y); }
  _f.normalize();
  if (opts.roll) _n.applyAxisAngle(_f, opts.roll * DEG);
  _y.crossVectors(_n, _f);
  _m.makeBasis(_f, _y, _n);
  return out.setFromRotationMatrix(_m);
}

/** Quaternion that turns local +Y into `dir` (columns, beams on an axis). */
export function axisQuat(dir, out) {
  toVec3(dir, _y);
  if (_y.lengthSq() < 1e-10) _y.set(0, 1, 0);
  _y.normalize();
  return out.setFromUnitVectors(_UP, _y);
}
const _UP = new THREE.Vector3(0, 1, 0);

/** Value or fallback (null / undefined). */
export const opt = (v, d) => (v != null ? v : d);
/** First value of a scalar-or-[a, b] option, and its second value. */
export const first = (v) => (Array.isArray(v) ? v[0] : v);
export const second = (v) => (Array.isArray(v) ? v[1] : v);
