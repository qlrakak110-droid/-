// ParamTable: a float RGBA data texture where every row describes one effect definition (an emitter type, a ribbon
// style ...). Many definitions then share ONE material / ONE draw call: each instance stores its row index and the
// shaders fetch ramps and parameters with texelFetch.
//
// Row layout (texel columns):
//   [0, 32)   colour ramp  RGBA (rgb linear HDR, a alpha) sampled at t = (i/31)^2 (denser near birth: flashes)
//   [32, 48)  scalar curves RGBA (4 curves) sampled the same way
//   [48, 64)  free parameters (16 vec4), meaning defined by the owning module
// GLSL helpers live in TABLE_GLSL (uniform name given at include time).

import * as THREE from 'three';

export const TABLE_W = 64;
export const RAMP_N = 32;
export const CURVE_N = 16;
export const CURVE_X = 32;
export const PARAM_X = 48;

/** Warped sample time of ramp sample i of n (sqrt-warped: more samples early in life). */
export const warpT = (i, n) => { const u = i / (n - 1); return u * u; };

export class ParamTable {
  /**
   * @param {number} rows   maximum number of definitions
   * @param {string} label  for warnings
   */
  constructor(rows, label = 'table') {
    this.rows = rows;
    this.label = label;
    this.data = new Float32Array(TABLE_W * rows * 4);
    this.texture = new THREE.DataTexture(this.data, TABLE_W, rows, THREE.RGBAFormat, THREE.FloatType);
    this.texture.minFilter = this.texture.magFilter = THREE.NearestFilter;
    this.texture.generateMipmaps = false;
    this.texture.needsUpdate = true;
    this.used = 0;
    this.busyUntil = new Float64Array(rows); // per-row game time until which live instances may still read the row
    this.owners = new Array(rows).fill(null);
    this.dirty = false;
    this._warned = false;
  }

  /**
   * Allocate a row. When the table is full, the least recently used row whose instances are all dead is recycled
   * (its previous owner gets `onEvict()`); returns -1 when nothing can be recycled.
   */
  alloc(owner, now) {
    if (this.used < this.rows) { this.owners[this.used] = owner; return this.used++; }
    let best = -1, bestT = Infinity;
    for (let i = 0; i < this.rows; i++) if (this.busyUntil[i] < now && this.busyUntil[i] < bestT) { bestT = this.busyUntil[i]; best = i; }
    if (best < 0) {
      if (!this._warned) { console.warn('[vfx] ' + this.label + ' full (' + this.rows + ' rows): define effects once at module scope'); this._warned = true; }
      return -1;
    }
    const prev = this.owners[best];
    if (prev && prev.onEvict) prev.onEvict();
    this.owners[best] = owner;
    return best;
  }

  /** Mark row `row` as read by instances until game time `t`. */
  touch(row, t) { if (t > this.busyUntil[row]) this.busyUntil[row] = t; }

  /** Write one texel. */
  set(row, x, a = 0, b = 0, c = 0, d = 0) {
    const o = (row * TABLE_W + x) * 4;
    const D = this.data;
    D[o] = a; D[o + 1] = b; D[o + 2] = c; D[o + 3] = d;
    this.dirty = true;
  }

  /** Bake a ramp function f(t, out4) into the colour section. */
  writeRamp(row, fn) {
    const o4 = [0, 0, 0, 1];
    for (let i = 0; i < RAMP_N; i++) {
      o4[0] = 0; o4[1] = 0; o4[2] = 0; o4[3] = 1;
      fn(warpT(i, RAMP_N), o4);
      this.set(row, i, o4[0], o4[1], o4[2], o4[3]);
    }
  }

  /** Bake up to four scalar curve functions (t -> v) into the curve section (channels x, y, z, w). */
  writeCurves(row, fx, fy, fz, fw) {
    for (let i = 0; i < CURVE_N; i++) {
      const t = warpT(i, CURVE_N);
      this.set(row, CURVE_X + i, fx ? fx(t) : 1, fy ? fy(t) : 0, fz ? fz(t) : 0, fw ? fw(t) : 0);
    }
  }

  /** Write parameter vec4 number k (0..15). */
  param(row, k, a = 0, b = 0, c = 0, d = 0) { this.set(row, PARAM_X + k, a, b, c, d); }

  /** Upload pending changes (call once per frame). */
  commit() {
    if (this.dirty) { this.texture.needsUpdate = true; this.dirty = false; }
  }

  dispose() { this.texture.dispose(); }
}

/** GLSL accessors for a ParamTable bound to sampler `name`. Defines tRow/tRamp/tCurve/tParam with the given prefix. */
export function tableGlsl(name, prefix) {
  return /* glsl */ `
vec4 ${prefix}Row(int x, int row) { return texelFetch(${name}, ivec2(x, row), 0); }
vec4 ${prefix}Lookup(int base, int n, float t, int row) {
  float u = sqrt(clamp(t, 0.0, 1.0)) * float(n - 1);
  int i = int(floor(u));
  int j = min(i + 1, n - 1);
  return mix(${prefix}Row(base + i, row), ${prefix}Row(base + j, row), u - float(i));
}
vec4 ${prefix}Ramp(float t, int row) { return ${prefix}Lookup(0, ${RAMP_N}, t, row); }
vec4 ${prefix}Curve(float t, int row) { return ${prefix}Lookup(${CURVE_X}, ${CURVE_N}, t, row); }
vec4 ${prefix}Param(int k, int row) { return ${prefix}Row(${PARAM_X} + k, row); }
`;
}
