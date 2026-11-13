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
  c += uSunHalo * (pow(max(s, 0.0), 6.0) * 0.8 + pow(max(s, 0.0), 40.0) * 2.0);
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
  vec3 near = uFogNear + uSunHalo * pow(max(s, 0.0), 8.0) * 0.6;
  return mix(near, far, smoothstep(22.0, 110.0, dist));
}
vec3 applyEnvFog(vec3 col, vec3 wp) {
  vec3 dir;
  float f = fogAmount(wp, dir);
  return mix(col, moodApply(envFogColor(dir, length(wp - cameraPosition)), 1.0), f);
}
`;

/**
 * Brush and seal glyphs of the Heaven-Martial Sect (천무문), as signed-distance-ish fields in a unit cell
 * (p in 0..1, y up; negative inside the ink). Needs NOISE.
 *   glyphTian(p)  天      glyphMu(p)  武       (brush strokes with tapered ends)
 *   sealGlyph(p, id)      an invented seal-script-like character (mirror-symmetric strokes of one width)
 *   barGroup(p, id)       a formation mark: three stacked bars, each whole, split in two or split in three
 */
export const GLYPHS = /* glsl */ `
float gSeg(vec2 p, vec2 a, vec2 b, float r0, float r1) {
  vec2 pa = p - a, ba = b - a;
  float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h) - mix(r0, r1, h);
}
float glyphTian(vec2 p) {
  float d = gSeg(p, vec2(0.25, 0.745), vec2(0.75, 0.765), 0.042, 0.036);
  d = min(d, gSeg(p, vec2(0.13, 0.515), vec2(0.87, 0.545), 0.046, 0.04));
  d = min(d, gSeg(p, vec2(0.5, 0.765), vec2(0.455, 0.45), 0.044, 0.046));
  d = min(d, gSeg(p, vec2(0.455, 0.45), vec2(0.33, 0.24), 0.046, 0.036));
  d = min(d, gSeg(p, vec2(0.33, 0.24), vec2(0.12, 0.09), 0.036, 0.012));
  d = min(d, gSeg(p, vec2(0.5, 0.53), vec2(0.63, 0.3), 0.034, 0.046));
  d = min(d, gSeg(p, vec2(0.63, 0.3), vec2(0.9, 0.1), 0.046, 0.062));
  return d;
}
float glyphMu(vec2 p) {
  float d = gSeg(p, vec2(0.2, 0.845), vec2(0.5, 0.865), 0.04, 0.034);
  d = min(d, gSeg(p, vec2(0.07, 0.665), vec2(0.73, 0.695), 0.044, 0.038));
  d = min(d, gSeg(p, vec2(0.385, 0.62), vec2(0.385, 0.15), 0.04, 0.04));
  d = min(d, gSeg(p, vec2(0.385, 0.405), vec2(0.57, 0.415), 0.036, 0.03));
  d = min(d, gSeg(p, vec2(0.2, 0.47), vec2(0.2, 0.15), 0.036, 0.038));
  d = min(d, gSeg(p, vec2(0.05, 0.115), vec2(0.62, 0.155), 0.044, 0.038));
  d = min(d, gSeg(p, vec2(0.6, 0.93), vec2(0.655, 0.62), 0.036, 0.042));
  d = min(d, gSeg(p, vec2(0.655, 0.62), vec2(0.76, 0.32), 0.042, 0.046));
  d = min(d, gSeg(p, vec2(0.76, 0.32), vec2(0.905, 0.1), 0.046, 0.05));
  d = min(d, gSeg(p, vec2(0.905, 0.1), vec2(0.935, 0.27), 0.046, 0.01));
  d = min(d, gSeg(p, vec2(0.775, 0.905), vec2(0.845, 0.815), 0.03, 0.046));
  return d;
}
// invented seal script: four bar levels and three stems on a mirror-symmetric lattice, some corners rounded
float sealGlyph(vec2 p, float id) {
  vec2 q = vec2(abs(p.x - 0.5), p.y);
  float w = 0.034;
  float d = 1e3;
  float h1 = hash12(vec2(id, 1.7)), h2 = hash12(vec2(id, 5.3)), h3 = hash12(vec2(id, 9.1)), h4 = hash12(vec2(id, 13.9));
  float y0 = 0.14, y1 = 0.38, y2 = 0.62, y3 = 0.86;
  float xa = 0.16 + 0.1 * step(0.5, h4), xb = 0.34;
  // bars (each level: full, inner half, outer tick or none)
  if (h1 > 0.25) d = min(d, gSeg(q, vec2(0.0, y3), vec2(h1 > 0.6 ? xb : xa, y3), w, w));
  if (h2 > 0.3) d = min(d, gSeg(q, vec2(h2 > 0.7 ? xa : 0.0, y2), vec2(xb, y2), w, w));
  if (h3 > 0.35) d = min(d, gSeg(q, vec2(0.0, y1), vec2(h3 > 0.7 ? xb : xa, y1), w, w));
  if (h4 > 0.2) d = min(d, gSeg(q, vec2(h1 < 0.5 ? xa : 0.0, y0), vec2(xb, y0), w, w));
  // stems: the centre stem over part of the height, side stems joining the bars
  float c0 = h2 > 0.5 ? y0 : y1, c1 = h3 > 0.45 ? y3 : y2;
  if (h1 + h3 > 0.7) d = min(d, gSeg(q, vec2(0.0, c0), vec2(0.0, c1), w, w));
  d = min(d, gSeg(q, vec2(xb, h4 > 0.55 ? y0 : y1), vec2(xb, h2 > 0.4 ? y2 : y3), w, w));
  if (h3 < 0.6) d = min(d, gSeg(q, vec2(xa, h1 > 0.5 ? y2 : y1), vec2(xa, h1 > 0.5 ? y3 : y2), w, w));
  // a hooked foot or a dot
  if (h4 > 0.6) d = min(d, gSeg(q, vec2(xb, y0), vec2(xb + 0.08, y0 - 0.07), w, w * 0.6));
  else if (h2 < 0.35) d = min(d, length(q - vec2(0.0, 0.5 * (y0 + y1))) - w * 1.3);
  return d;
}
// formation mark: three stacked bars in a cell (p in 0..1); bar k is whole, split in two, or split in three
float barGroup(vec2 p, float id) {
  float d = 1e3;
  for (int k = 0; k < 3; k++) {
    float y = 0.22 + 0.28 * float(k);
    float kind = floor(hash12(vec2(id * 1.31 + 0.7, float(k) * 3.7 + 2.1)) * 3.0);
    float x = abs(p.x - 0.5);
    float dx;
    if (kind < 0.5) dx = x - 0.4;
    else if (kind < 1.5) dx = max(x - 0.4, 0.07 - x);
    else dx = min(x - 0.1, max(x - 0.4, 0.2 - x));
    vec2 e = vec2(dx, abs(p.y - y) - 0.075);
    d = min(d, length(max(e, 0.0)) + min(max(e.x, e.y), 0.0));
  }
  return d;
}
`;
