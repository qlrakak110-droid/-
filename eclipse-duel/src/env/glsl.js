// Shared GLSL for the environment: hashing / value noise / fbm, the sky gradient used by both the dome and the fog,
// and the height + in-scatter fog every env material applies (so silhouettes fade into exactly the sky behind them).

/** Hashes and value noise (2D / 3D) plus fbm helpers. No textures. */
export const NOISE = /* glsl */ `
float hash12(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
float hash13(vec3 p3) { p3 = fract(p3 * 0.1031); p3 += dot(p3, p3.zyx + 31.32); return fract((p3.x + p3.y) * p3.z); }
vec2 hash22(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973)); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.xx + p3.yz) * p3.zy); }
vec3 hash33(vec3 p3) { p3 = fract(p3 * vec3(0.1031, 0.1030, 0.0973)); p3 += dot(p3, p3.yxz + 33.33); return fract((p3.xxy + p3.yxx) * p3.zyx); }
float vnoise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}
float vnoise3(vec3 p) {
  vec3 i = floor(p), f = fract(p);
  vec3 u = f * f * (3.0 - 2.0 * f);
  float a = mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), u.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), u.x), u.y);
  float b = mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), u.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), u.x), u.y);
  return mix(a, b, u.z);
}
float fbm2(vec2 p, int oct) {
  float s = 0.0, a = 0.5, n = 0.0;
  for (int i = 0; i < 6; i++) { if (i >= oct) break; s += a * vnoise(p); n += a; p = mat2(1.6, 1.2, -1.2, 1.6) * p + 17.1; a *= 0.5; }
  return s / n;
}
float fbm3(vec3 p, int oct) {
  float s = 0.0, a = 0.5, n = 0.0;
  for (int i = 0; i < 6; i++) { if (i >= oct) break; s += a * vnoise3(p); n += a; p = p * 2.03 + vec3(11.7, 3.1, 7.3); a *= 0.5; }
  return s / n;
}
`;

/**
 * Sky gradient shared by the dome and the fog colour. Needs uniforms:
 *   uZenith, uSkyMid, uHorizon, uGlow, uSunHalo (vec3), uSunDir (vec3)
 */
export const SKY_BASE = /* glsl */ `
uniform vec3 uZenith, uSkyMid, uHorizon, uGlow, uSunHalo, uSunDir;
vec3 skyBase(vec3 dir) {
  float h = dir.y;
  float az = atan(dir.x, -dir.z);
  vec3 c = mix(uHorizon, uSkyMid, smoothstep(0.0, 0.22, h));
  c = mix(c, uZenith, smoothstep(0.18, 0.85, h));
  // the 360-degree "eclipse sunset": a thin warm band hugging the horizon, a little uneven in azimuth
  float band = exp(-abs(h - 0.012) * (h > 0.012 ? 22.0 : 9.0));
  float var = 0.75 + 0.25 * sin(az * 2.0 + 0.8) * sin(az * 3.0 - 0.4);
  c += uGlow * band * var;
  // broad cool in-scatter around the eclipse
  float s = max(dot(dir, uSunDir), 0.0);
  c += uSunHalo * (pow(s, 6.0) * 0.8 + pow(s, 40.0) * 2.0);
  return c;
}
`;

/**
 * Height fog with sky-matched colour, applied by every env material. Needs SKY_BASE and uniforms:
 *   uFogP  (x: density at y = 0, y: height falloff 1/m, z: far-distance boost, w: max opacity)
 *   uMood  (rgb: tint, a: darken 0..1)
 */
export const FOG = /* glsl */ `
uniform vec4 uFogP;
uniform vec4 uMood;
uniform vec3 uFogNear;
vec3 moodApply(vec3 c, float strength) {
  float d = uMood.a * strength;
  return c * mix(vec3(1.0), uMood.rgb, d) * (1.0 - 0.86 * d);
}
float fogAmount(vec3 wp, out vec3 dir) {
  vec3 d = wp - cameraPosition;
  float dist = length(d);
  dir = d / max(dist, 1e-4);
  float y0 = cameraPosition.y, y1 = wp.y;
  float b = uFogP.y;
  float dy = y1 - y0;
  // integral of exp(-b y) along the ray, normalised by the ray length
  float hInt = abs(dy) > 0.01 ? (exp(-b * max(y0, -6.0)) - exp(-b * max(y1, -6.0))) / (b * dy) : exp(-b * max(y0, -6.0));
  float od = uFogP.x * dist * hInt + uFogP.z * max(dist - 40.0, 0.0) * 0.001;
  return min(1.0 - exp(-od), uFogP.w);
}
vec3 envFogColor(vec3 dir, float dist) {
  vec3 far = skyBase(vec3(dir.x, max(dir.y, 0.003), dir.z));
  float s = max(dot(dir, uSunDir), 0.0);
  vec3 near = uFogNear + uSunHalo * pow(s, 8.0) * 0.6;
  return mix(near, far, smoothstep(22.0, 110.0, dist));
}
vec3 applyEnvFog(vec3 col, vec3 wp) {
  vec3 dir;
  float f = fogAmount(wp, dir);
  return mix(col, moodApply(envFogColor(dir, length(wp - cameraPosition)), 1.0), f);
}
`;
