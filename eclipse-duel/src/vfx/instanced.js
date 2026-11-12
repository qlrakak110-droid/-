// InstanceRing: a fixed-capacity ring buffer of per-instance float data (one interleaved GPU buffer) behind a
// camera-facing quad. Writers fill slots once at spawn time; only the written ranges are uploaded (bufferSubData)
// and the pending ranges are kept until three actually uploads them (onUpload), so captures that advance many frames
// without rendering stay correct. This is the base of the particle layers, flares and distortion sprites, and the
// building block for any other instanced effect (one draw call per effect type).
//
//   const ring = new InstanceRing(capacity, { iPosT: 4, iVelL: 4 });      // attribute name -> float count (1..4)
//   const s = ring.alloc(n);   for k in 0..n-1: ring.f32[ring.offset(s + k) + j] = ...   ring.dirty(s, n)
//   mesh = new THREE.Mesh(ring.geometry, material)

import * as THREE from 'three';

/** Shared unit quad (corners -1..1 in `position.xy`, uv 0..1). */
export function makeQuadGeometry() {
  const g = new THREE.InstancedBufferGeometry();
  g.setAttribute('position', new THREE.BufferAttribute(new Float32Array([-1, -1, 0, 1, -1, 0, 1, 1, 0, -1, 1, 0]), 3));
  g.setIndex([0, 1, 2, 0, 2, 3]);
  return g;
}

export class InstanceRing {
  /**
   * @param {number} capacity  number of instance slots
   * @param {Object<string, number>} layout  attribute name -> component count; total is padded to a multiple of 4
   */
  constructor(capacity, layout) {
    let stride = 0;
    const offs = {};
    for (const k in layout) { offs[k] = stride; stride += layout[k]; }
    stride = Math.ceil(stride / 4) * 4;
    this.capacity = capacity;
    this.stride = stride;
    this.f32 = new Float32Array(capacity * stride);
    this.buffer = new THREE.InstancedInterleavedBuffer(this.f32, stride, 1);
    this.buffer.setUsage(THREE.DynamicDrawUsage);
    this.geometry = makeQuadGeometry();
    for (const k in layout) this.geometry.setAttribute(k, new THREE.InterleavedBufferAttribute(this.buffer, layout[k], offs[k]));
    this.geometry.instanceCount = 0;
    this.offsets = offs;
    this.head = 0;            // next slot to write
    this.highWater = 0;       // number of slots ever written (draw count until the ring wraps)
    this.owner = new Uint32Array(capacity); // serial of the spawn that wrote each slot (handle.kill safety)
    // ranges written since the last commit, and ranges committed but not yet uploaded ([start, count] slot pairs)
    this._pend = [];
    this._inflight = [];
    this.buffer.onUpload(() => { this._inflight.length = 0; });
  }

  /** Float offset of slot i in f32. */
  offset(i) { return i * this.stride; }

  /** Reserve n consecutive (ring-wrapped) slots; returns the first slot index. */
  alloc(n) {
    const s = this.head;
    this.head = (this.head + n) % this.capacity;
    this.highWater = Math.min(this.capacity, Math.max(this.highWater, s + n));
    return s;
  }

  /** Mark n slots starting at s (ring-wrapped) for upload. */
  dirty(s, n) {
    if (n <= 0) return;
    if (n >= this.capacity) { addRange(this._pend, 0, this.capacity, this.capacity); return; }
    const end = s + n;
    if (end > this.capacity) { addRange(this._pend, s, this.capacity - s, this.capacity); addRange(this._pend, 0, end - this.capacity, this.capacity); } else addRange(this._pend, s, n, this.capacity);
  }

  /** Push pending ranges to three (call once per frame, before rendering). */
  commit() {
    this.geometry.instanceCount = this.highWater;
    const p = this._pend, f = this._inflight;
    if (!p.length && !f.length) return;
    for (let i = 0; i < p.length; i += 2) addRange(f, p[i], p[i + 1], this.capacity);
    p.length = 0;
    const b = this.buffer;
    b.clearUpdateRanges();
    for (let i = 0; i < f.length; i += 2) b.addUpdateRange(f[i] * this.stride, f[i + 1] * this.stride);
    b.needsUpdate = true;
  }

  /** Forget every instance (data stays, callers make slots dead through their own time logic). */
  reset() { this.head = 0; }

  dispose() { this.geometry.dispose(); }
}

/** Append [s, n] to a flat range list, merging with an overlapping/adjacent range; collapses to "everything" past 32. */
function addRange(list, s, n, cap) {
  for (let i = 0; i < list.length; i += 2) {
    const ls = list[i], le = ls + list[i + 1];
    if (s <= le && s + n >= ls) { const ns = Math.min(ls, s); list[i + 1] = Math.max(le, s + n) - ns; list[i] = ns; return; }
  }
  if (list.length >= 64) { list.length = 0; list.push(0, cap); return; }
  list.push(s, n);
}
