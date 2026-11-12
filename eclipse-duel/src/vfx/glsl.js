// Shared GLSL for the shader-driven mesh effects (slash, ring, pillar, beam, bolt, decal, spikes, debris ...).
// Plain strings, concatenated into each module's shaders. Hashes are sin-free (stable on mobile GPUs).

/** Constants, hashes, value noise, easing, quaternion rotation, 3-colour heat ramp. */
export const GLSL_COMMON = /* glsl */ `
#ifndef PI
#define PI 3.14159265359
#endif
#define TAU 6.28318530718
float sat(float x) { return clamp(x, 0.0, 1.0); }
float h11(float p) { p = fract(p * 0.1031); p *= p + 33.33; p *= p + p; return fract(p); }
float h12(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
vec2 h22(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973)); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.xx + p3.yz) * p3.zy); }
float h13(vec3 p3) { p3 = fract(p3 * 0.1031); p3 += dot(p3, p3.zyx + 31.32); return fract((p3.x + p3.y) * p3.z); }
// smooth value noise in [0, 1]
float vnoise(vec2 p) {
  vec2 i = floor(p), f = p - i;
  vec2 w = f * f * (3.0 - 2.0 * f);
  return mix(mix(h12(i), h12(i + vec2(1.0, 0.0)), w.x), mix(h12(i + vec2(0.0, 1.0)), h12(i + vec2(1.0, 1.0)), w.x), w.y);
}
// jagged 1D noise in [0, 1]: piecewise-linear between random knots (lightning, cracks)
float lnoise(float x) { float i = floor(x); return mix(h11(i), h11(i + 1.0), x - i); }
float outQuad(float x) { x = sat(x); return 1.0 - (1.0 - x) * (1.0 - x); }
float outCubic(float x) { x = 1.0 - sat(x); return 1.0 - x * x * x; }
float outQuart(float x) { x = 1.0 - sat(x); x *= x; return 1.0 - x * x; }
float outExpo(float x) { x = sat(x); return x >= 1.0 ? 1.0 : 1.0 - exp2(-10.0 * x); }
float inQuad(float x) { x = sat(x); return x * x; }
float inCubic(float x) { x = sat(x); return x * x * x; }
float outBack(float x, float s) { x = sat(x) - 1.0; return 1.0 + (s + 1.0) * x * x * x + s * x * x; }
vec3 qrot(vec4 q, vec3 v) { return v + 2.0 * cross(q.xyz, cross(q.xyz, v) + q.w * v); }
vec3 qrotInv(vec4 q, vec3 v) { return qrot(vec4(-q.xyz, q.w), v); }
vec3 rotAxis(vec3 v, vec3 a, float ang) { float c = cos(ang), s = sin(ang); return v * c + cross(a, v) * s + a * dot(a, v) * (1.0 - c); }
// heat ramp: k = 0 white-hot core -> 'mid' at k = m -> 'tail' at 1 (core is pushed toward white at k = 0)
vec3 heat3(float k, vec3 core, vec3 mid, vec3 tail, float m) {
  k = sat(k);
  vec3 hot = core * 1.25 + vec3(dot(core, vec3(0.3333)) * 0.35);
  if (k < 0.08) return mix(hot, core, k / 0.08);
  if (k < m) return mix(core, mid, (k - 0.08) / max(m - 0.08, 1e-3));
  return mix(mid, tail, (k - m) / max(1.0 - m, 1e-3));
}
`;

/** Procedural cellular noise: voronoi(p) -> (F1, F2, cell id hash in [0,1)). 3x3 search, crisp at any scale. */
export const GLSL_VORONOI = /* glsl */ `
vec3 voronoi(vec2 p) {
  vec2 i = floor(p), f = p - i;
  float f1 = 8.0, f2 = 8.0, id = 0.0;
  for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
    vec2 g = vec2(float(x), float(y));
    vec2 o = h22(i + g);
    vec2 r = g + o - f;
    float d = dot(r, r);
    if (d < f1) { f2 = f1; f1 = d; id = h12(i + g + 0.37); } else if (d < f2) f2 = d;
  }
  return vec3(sqrt(f1), sqrt(f2), id);
}
// periodic in x with period 'per' cells (seamless around rings and cylinders)
vec3 voronoiP(vec2 p, float per) {
  vec2 i = floor(p), f = p - i;
  float f1 = 8.0, f2 = 8.0, id = 0.0;
  for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
    vec2 g = vec2(float(x), float(y));
    vec2 c = vec2(mod(i.x + g.x, per), i.y + g.y);
    vec2 r = g + h22(c) - f;
    float d = dot(r, r);
    if (d < f1) { f2 = f1; f1 = d; id = h12(c + 0.37); } else if (d < f2) f2 = d;
  }
  return vec3(sqrt(f1), sqrt(f2), id);
}
// periodic jagged 1D noise (period 'per' knots)
float lnoiseP(float x, float per) { float i = floor(x); return mix(h11(mod(i, per)), h11(mod(i + 1.0, per)), x - i); }
`;

/** Analytic ballistics with linear drag and exact floor bounces (same model as the particle system). */
export const GLSL_BALLISTIC = /* glsl */ `
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
float impact(float y, float vy, float gy, float k, float tmax) {
  if (yAt(y, vy, gy, k, tmax) > 0.0) return 1e9;
  float t = tmax;
  for (int i = 0; i < 6; i++) t -= yAt(y, vy, gy, k, t) / min(vyAt(vy, gy, k, t), -1e-3);
  return max(t, 0.0);
}
`;

/** Culled vertex (outside the clip volume). */
export const CULL = 'gl_Position = vec4(0.0, 0.0, 2.0, 1.0); return;';
