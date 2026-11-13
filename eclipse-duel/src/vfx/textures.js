// Procedural VFX textures, generated once at start-up on the GPU (one generator program, one quad per atlas cell,
// rendered into mipmapped render targets — a few milliseconds instead of seconds of CPU rasterising on a phone).
//
//   atlas  1024x1152 RGBA8 sprite atlas. Channels are masks, not colour (colour comes from ramps):
//            R  shade   - form / lighting / internal detail, multiplies the colour (def.shade blends it in)
//            G  heat    - hot core mask: shifts the colour lookup toward the birth colour (def.heat)
//            B  order   - dissolve order: low values erode first (def.erode)
//            A  alpha   - coverage
//   noise  256x256 RGBA8, tiling:  R perlin fbm | G cellular F1 (bubbles) | B cellular F2-F1 (cracks) | A fine grain fbm
//   flow   256x256 RGBA8, tiling:  R streaks along U | G domain-warped swirl fbm | BA divergence-free flow vector (0.5 = 0)
//
// SPRITES lists every atlas entry (name -> rect in UV + variant count). Group names ('smoke', 'flame', 'shard' ...)
// cover consecutive variants; a particle picks one at random. Random shape parameters (blob lists, polygons, rune
// strokes) are drawn from a fixed-seed RNG in JS and passed as uniforms, so the atlas is identical on every run.

import * as THREE from 'three';
import { makeRng, TAU } from '../core/math.js';

const ATLAS = 1024;          // atlas width (px)
const ATLAS_H = 1152;        // atlas height: 2 rows of 256 px cells, 5 rows of 128 px cells
const NOISE = 256;
const MAXP = 128;

// generator kinds (must match GEN_FRAG)
const K = { smoke: 1, flame: 2, burst: 3, glow: 4, glowHard: 5, disc: 6, spark: 7, ember: 8, dust: 9, star: 10, ring: 11, shard: 12, snow: 13, ash: 14, petal: 15, lines: 16, wisp: 17, streak: 18, dot: 19, hex: 20, pebble: 21, crescent: 22, talisman: 23, leaf: 24, ink: 25, brush: 26, enso: 27, noise: 40, flow: 41 };

const GEN_VERT = /* glsl */ `
varying vec2 vUv;
void main() { vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }`;

const GEN_FRAG = /* glsl */ `
precision highp float;
precision highp int;
uniform int uKind;
uniform int uVar;
uniform int uCount;
uniform float uSeed;
uniform vec4 uP[${MAXP}];
varying vec2 vUv;

#define TAU 6.28318530718
uint pcg(uint v) { uint s = v * 747796405u + 2891336453u; uint w = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u; return (w >> 22u) ^ w; }
float h21(vec2 c) { uvec2 q = uvec2(ivec2(c) + 8192); return float(pcg(q.x ^ pcg(q.y + uint(uSeed * 977.0)))) / 4294967296.0; }
vec2 grad(vec2 c) { float a = h21(c) * TAU; return vec2(cos(a), sin(a)); }
// gradient noise in ~[-1, 1], periodic with period per (lattice units)
float gnoise(vec2 p, vec2 per) {
  vec2 i = floor(p), f = p - i;
  vec2 i0 = mod(i, per), i1 = mod(i + 1.0, per);
  float a = dot(grad(i0), f), b = dot(grad(vec2(i1.x, i0.y)), f - vec2(1.0, 0.0));
  float c = dot(grad(vec2(i0.x, i1.y)), f - vec2(0.0, 1.0)), d = dot(grad(i1), f - 1.0);
  vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 1.414;
}
float fbmP(vec2 p, int oct, vec2 per, float gain) {
  float s = 0.0, a = 1.0, n = 0.0;
  for (int o = 0; o < 6; o++) { if (o >= oct) break; s += a * gnoise(p, per); n += a; a *= gain; p *= 2.0; per *= 2.0; }
  return s / n;
}
float fbm(vec2 p, int oct) { return fbmP(p, oct, vec2(4096.0), 0.5); }
float n01(vec2 p, int oct) { return fbm(p, oct) * 0.5 + 0.5; }
vec2 cellular(vec2 p, float per) {
  vec2 i = floor(p);
  float f1 = 9.0, f2 = 9.0;
  for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
    vec2 c = i + vec2(x, y);
    vec2 w = mod(c, per);
    vec2 o = vec2(h21(w), h21(w + 517.0));
    float d = length(c + o - p);
    if (d < f1) { f2 = f1; f1 = d; } else if (d < f2) f2 = d;
  }
  return vec2(f1, f2);
}
float sdSeg(vec2 p, vec2 a, vec2 b) { vec2 pa = p - a, ba = b - a; float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-8), 0.0, 1.0); return length(pa - ba * h); }
// signed polygon distance over uP[0..n) (xy), negative inside
float sdPoly(vec2 p, int n) {
  float d = 1e3; bool inside = false;
  for (int i = 0; i < 24; i++) {
    if (i >= n) break;
    int j = i == 0 ? n - 1 : i - 1;
    vec2 a = uP[i].xy, b = uP[j].xy;
    d = min(d, sdSeg(p, a, b));
    if ((a.y > p.y) != (b.y > p.y) && p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x) inside = !inside;
  }
  return inside ? -d : d;
}
float sat(float x) { return clamp(x, 0.0, 1.0); }
float edgeFade(vec2 p, float inner) { return 1.0 - smoothstep(inner, 0.985, max(abs(p.x), abs(p.y))); }
// a lit line: x = core, y = coverage with glow
vec2 lineLight(float d, float w, float k, float amt) { float core = 1.0 - smoothstep(w * 0.35, w, d); return vec2(core, max(core, exp(-d * k) * amt)); }

// --- smoke: sum of gaussian lobes, billowed and warped, lit from the upper left through the density gradient ------
float smokeD(vec2 p) {
  vec4 cfg = uP[100];
  vec2 q = p + cfg.x * vec2(fbm(p * 1.6 + 3.1, 4), fbm(p * 1.6 + 17.7, 4));
  float d = 0.0;
  for (int k = 0; k < 24; k++) { if (k >= uCount) break; vec4 b = uP[k]; vec2 dd = q - b.xy; d += b.w * exp(-dot(dd, dd) / (b.z * b.z)); }
  float n = n01(q * cfg.w + 7.3, 4);
  return d * mix(1.0, 0.3 + 1.2 * n * n, cfg.z);
}
vec4 genSmoke(vec2 p) {
  vec4 cfg = uP[100], cfg2 = uP[101];
  float e = 3.0 / 256.0;
  float d = smokeD(p), dx = smokeD(p + vec2(e, 0.0)), dy = smokeD(p + vec2(0.0, e));
  float dxm = smokeD(p - vec2(e, 0.0)), dym = smokeD(p - vec2(0.0, e));
  vec3 n = normalize(vec3(-(dx - dxm) / (2.0 * e) * cfg2.x, -(dy - dym) / (2.0 * e) * cfg2.x, 1.0));
  vec3 L = normalize(vec3(-0.5, 0.75, 0.45));
  float lit = sat((dot(n, L) + 0.45) / 1.45);
  float fine = n01(p * 9.0 + 1.3, 4);
  float big = n01(p * 2.3 + 4.0, 3);
  float a = smoothstep(0.0, 1.0, sat((d - cfg.y + (fine - 0.5) * 0.12) / cfg2.y));
  a *= 0.5 + 0.5 * smoothstep(0.2, 0.75, big + (fine - 0.5) * 0.5);
  float thick = sat(d * 0.75);
  float shade = (0.26 + 0.74 * lit * lit) * mix(1.0, 0.74, thick) * (0.9 + 0.2 * fine);
  float order = sat(d * 0.6 + big * 0.25 + fine * 0.25 - 0.1);
  return vec4(sat(shade), smoothstep(0.55, 1.25, d), order, sat(a * 0.92) * edgeFade(p, 0.74));
}

// --- flame licks: teardrop tongues bent by noise, ragged tips, hot core ---------------------------------------------
vec4 genFlame(vec2 p) {
  float yy = (p.y + 1.0) * 0.5;
  float a = 0.0, g = 0.0;
  for (int k = 0; k < 4; k++) {
    if (k >= uCount) break;
    vec4 t = uP[k];            // cx, height, width, phase
    float s = (yy - 0.03) / t.y;
    if (s <= 0.0 || s >= 1.0) continue;
    float bend = 0.09 * sin(s * 3.4 + t.w) * s + 0.34 * pow(max(s, 0.0), 1.4) * fbm(vec2(p.x * 1.2 + t.w, yy * 2.0 - uSeed), 4);
    float xw = p.x - t.x - bend;
    float w = t.z * 1.55 * pow(max(s, 0.0), 0.42) * (1.0 - s);
    float lick = n01(vec2(xw * 3.6 + 4.0, yy * 3.0 - t.w), 4);
    float tear = n01(vec2(xw * 7.0 - t.w, yy * 6.0 + uSeed), 3);
    float m = smoothstep(0.0, 0.06 + 0.07 * s, w - abs(xw) - (lick - 0.5) * 0.16 * (0.3 + s));
    m *= smoothstep(0.0, 0.18, (1.0 - s) * 1.1 + 0.1 - lick * 0.62 * s);
    m *= 1.0 - smoothstep(0.5, 0.8, tear) * smoothstep(0.35, 0.8, s) * 0.85;   // holes that tear the upper flame apart
    a = max(a, m);
    g = max(g, smoothstep(0.0, 0.1, w * 0.5 - abs(xw)) * pow(max(1.0 - s, 0.0), 0.5));
  }
  float streak = n01(vec2(p.x * 9.0, yy * 1.6 - uSeed * 0.3), 4);
  return vec4(sat((0.32 + 0.68 * streak) * (0.8 + 0.2 * (1.0 - yy))), sat(g * (0.7 + 0.6 * streak)),
              sat((1.0 - yy) * 0.6 + 0.4 * n01(p * 4.0 + 2.0, 3)), sat(a * (0.72 + 0.28 * streak)));
}

// --- burst: radial flash with uneven rays --------------------------------------------------------------------------
vec4 genBurst(vec2 p) {
  float r = length(p), th = atan(p.y, p.x), ray = 0.0;
  for (int k = 0; k < 40; k++) {
    if (k >= uCount) break;
    vec4 q = uP[k];          // angle, width, length
    float d = abs(th - q.x); d = min(d, TAU - d);
    float dist = r * d;
    ray = max(ray, exp(-(dist * dist) / (q.y * q.y)) * pow(sat(1.0 - r / q.z), 1.6));
  }
  float core = exp(-r * r * 30.0);
  float halo = exp(-r * 4.2) * 0.42 * (0.85 + 0.3 * n01(vec2(th * 2.5, r * 3.0), 2)) * (1.0 - smoothstep(0.55, 0.95, r));
  return vec4(1.0, sat(core * 1.2 + ray * 0.4), sat(1.0 - r * 1.1), sat(core + halo + ray * 0.85) * edgeFade(p, 0.9));
}

vec4 genGlow(vec2 p) {
  float r2 = dot(p, p);
  float e = exp(-r2 * 5.5) * 0.75 + 0.25 / (1.0 + r2 * 40.0);
  float k = max(0.0, 1.0 - r2);
  return vec4(1.0, exp(-r2 * 28.0), sat(1.0 - sqrt(r2)), sat(e * k * k));
}
vec4 genGlowHard(vec2 p) {
  float r = length(p);
  float core = 1.0 - smoothstep(0.1, 0.17, r), mid = exp(-r * 9.0) * 0.7, halo = exp(-r * 3.2) * 0.22;
  float k = max(0.0, 1.0 - r * r);
  return vec4(1.0, sat(core + mid * 0.4), sat(1.0 - r), sat((core + mid + halo) * k * k));
}
vec4 genDisc(vec2 p) {
  float r = length(p);
  return vec4(0.85 + 0.15 * (1.0 - r), 1.0 - smoothstep(0.0, 0.6, r), sat(1.0 - r), 1.0 - smoothstep(0.66, 0.84, r));
}
vec4 genSpark(vec2 p) {
  float head = 0.52;
  float along = p.x < head ? pow(sat((p.x + 0.92) / (head + 0.92)), 1.7) : exp(-(p.x - head) * 14.0);
  float w = 0.09 + 0.2 * along;
  float cross = exp(-(p.y * p.y) / (w * w));
  float hot = exp(-(p.x - head) * (p.x - head) * 30.0 - p.y * p.y * 90.0);
  return vec4(1.0, sat(hot + along * cross * 0.35), sat(along), sat(cross * along * 1.15));
}
vec4 genEmber(vec2 p) {
  float r = length(p), th = atan(p.y, p.x);
  float edge = 0.3 + 0.07 * fbm(vec2(cos(th), sin(th)) * 1.5 + 3.0, 2);
  float body = 1.0 - smoothstep(edge - 0.08, edge + 0.02, r);
  float core = 1.0 - smoothstep(0.0, edge * 0.75, r);
  float halo = exp(-r * 6.0) * 0.45;
  return vec4(sat(0.7 + 0.3 * n01(p * 6.0, 2)), core, sat(1.0 - r * 1.6), sat(max(body, halo) * pow(max(0.0, 1.0 - r * r), 1.5)));
}
vec4 genDust(vec2 p) {
  vec2 w = p + 0.18 * vec2(fbm(p * 2.0 + 5.0, 3), fbm(p * 2.0 + 11.0, 3));
  float r = length(w);
  float n = n01(p * 5.0 + 3.0, 4);
  return vec4(sat(0.62 + 0.28 * n + 0.14 * p.y), sat((1.0 - smoothstep(0.0, 0.4, r)) * n), sat((1.0 - r) * 0.6 + n * 0.4),
              sat((1.0 - smoothstep(0.1, 0.75, r)) * (0.5 + 0.6 * n)) * edgeFade(p, 0.85));
}
vec4 genStar(vec2 p) {
  float r = length(p), a = 0.0;
  for (int k = 0; k < 8; k++) {
    if (k >= uCount) break;
    vec4 q = uP[k];          // angle, length, width
    float ca = cos(q.x), sa = sin(q.x);
    float u = p.x * ca + p.y * sa, v = -p.x * sa + p.y * ca;
    float fall = pow(sat(1.0 - abs(u) / q.y), 2.2);
    float ww = q.z * (0.35 + 0.65 * fall);
    a = max(a, exp(-(v * v) / (ww * ww)) * fall);
  }
  float core = exp(-r * r * 60.0), glow = exp(-r * 7.0) * 0.5;
  return vec4(1.0, sat(core + a * 0.5), sat(1.0 - r), sat(a + core + glow));
}
vec4 genRing(vec2 p) {
  float r = length(p), R = 0.78, w = 0.05;
  float ring = exp(-((r - R) * (r - R)) / (w * w));
  float inner = smoothstep(0.2, R, r) * (1.0 - smoothstep(R, R + 0.04, r)) * 0.18;
  return vec4(1.0, exp(-((r - R) * (r - R)) / (w * w * 0.2)), sat(ring), sat(ring + inner));
}
// shard: polygon uP[0..n), ridges uP[30] (tip.xy, base.xy), uP[31] (mid.xy)
vec4 genShard(vec2 p) {
  float d = sdPoly(p, uCount);
  float inside = 1.0 - smoothstep(-0.012, 0.012, d);
  vec2 tip = uP[30].xy, base = uP[30].zw, mid = uP[31].xy;
  float s1 = (base.x - tip.x) * (p.y - tip.y) - (base.y - tip.y) * (p.x - tip.x);
  float s2 = (base.x - mid.x) * (p.y - mid.y) - (base.y - mid.y) * (p.x - mid.x);
  float shade = s1 > 0.0 ? 0.42 : 0.95;
  if (s1 <= 0.0 && s2 > 0.0) shade = 0.7;
  shade *= 0.88 + 0.24 * (p.y * 0.5 + 0.5);
  float ridge = min(sdSeg(p, tip, base), sdSeg(p, mid, base));
  float edge = max(1.0 - smoothstep(0.0, 0.07, -d), 1.0 - smoothstep(0.004, 0.03, ridge));
  float glow = exp(-max(0.0, d) * 16.0) * 0.35;
  return vec4(sat(shade), sat(edge * inside + glow * 0.6), sat(0.3 + 0.7 * smoothstep(0.0, 0.3, -d)), sat(max(inside * 0.92, glow)));
}
vec4 genSnow(vec2 p) {
  float r = length(p), th = atan(p.y, p.x);
  float sec = TAU / 6.0;
  th = mod(th, sec); if (th > sec * 0.5) th = sec - th;
  vec2 q = r * vec2(cos(th), sin(th));
  if (uVar == 0) {
    float d = sdSeg(q, vec2(0.0), vec2(0.86, 0.0));
    d = min(d, sdSeg(q, vec2(0.3, 0.0), vec2(0.3, 0.0) + 0.26 * vec2(0.5, 0.866)));
    d = min(d, sdSeg(q, vec2(0.52, 0.0), vec2(0.52, 0.0) + 0.22 * vec2(0.5, 0.866)));
    d = min(d, sdSeg(q, vec2(0.7, 0.0), vec2(0.7, 0.0) + 0.13 * vec2(0.5, 0.866)));
    d = min(d, sdSeg(q, vec2(0.17, 0.0), vec2(0.085, 0.147)));
    vec2 l = lineLight(d, 0.04, 15.0, 0.4);
    return vec4(sat(0.75 + 0.25 * (1.0 - r)), l.x, sat(1.0 - r * 0.8), sat(l.y));
  }
  // stellar plate: hexagonal plate + six arms ending in small plates, with facet ridges
  float plate = dot(q, vec2(0.866, 0.5)) - 0.27;
  float arm = max(abs(q.y) - 0.05, q.x - 0.84);
  float tipP = abs(q.x - 0.66) * 0.55 + abs(q.y) - 0.11;
  float side = sdSeg(q, vec2(0.42, 0.0), vec2(0.42, 0.0) + 0.17 * vec2(0.5, 0.866)) - 0.03;
  float body = min(min(plate, arm), min(tipP, side));
  float fill = 1.0 - smoothstep(-0.01, 0.012, body);
  float ridge = min(abs(q.y), sdSeg(q, vec2(0.0), vec2(0.234, 0.135)));
  float edge = 1.0 - smoothstep(0.0, 0.03, abs(body));
  float glow = exp(-max(0.0, body) * 16.0) * 0.32;
  float rl = (1.0 - smoothstep(0.0, 0.016, ridge)) * fill;
  return vec4(sat(0.55 + 0.45 * rl + 0.2 * (1.0 - r)), sat(max(edge * fill, rl)), sat(1.0 - r * 0.8), sat(max(fill * 0.5 + edge * 0.5 + rl * 0.3, glow)));
}
vec4 genAsh(vec2 p) {
  float th = atan(p.y, p.x);
  float r = length(p * vec2(uVar == 1 ? 1.25 : 1.0, 1.0));
  vec2 c = vec2(cos(th), sin(th));
  float rad = 0.52 + 0.2 * fbm(c * 1.3 + uSeed, 4) + 0.06 * fbm(c * 5.0 + uSeed, 2);
  float d = r - rad;
  float inside = 1.0 - smoothstep(-0.015, 0.015, d);
  float n = n01(p * 7.0 + uSeed, 3);
  return vec4(sat(0.35 + 0.65 * n * n), sat((1.0 - smoothstep(0.0, 0.14, -d)) * inside), sat(smoothstep(0.0, 0.45, -d) * 0.8 + n * 0.2), sat(inside * (0.82 + 0.18 * n)));
}
vec4 genPetal(vec2 p) {
  float s = (p.y + 0.82) / 1.64;
  float w = (s > 0.0 && s < 1.0) ? 0.44 * pow(max(sin(3.14159 * pow(max(s, 0.0), 0.8)), 0.0), 0.75) : -1.0;
  float xx = p.x - 0.08 * sin(s * 3.0);
  float notch = length(vec2(xx, p.y - 0.86)) - 0.13;
  float d = max(abs(xx) - w, -notch);
  float inside = 1.0 - smoothstep(-0.015, 0.015, d);
  float vein = exp(-(xx * xx) / 0.0006) * 0.25;
  return vec4(sat((0.62 + 0.38 * s) * (1.0 - vein) * (0.9 + 0.1 * n01(p * vec2(8.0, 3.0), 2))), sat((1.0 - smoothstep(0.0, 0.08, -d)) * inside * 0.7),
              sat(smoothstep(0.0, 0.3, -d)), inside);
}
// line art: uP[2k] = (ax, ay, bx, by) segment | (cx, cy, r, a0) arc | (cx, cy, r, 0) dot ; uP[2k+1] = (weight, type, a1, 0)
vec4 genLines(vec2 p) {
  float d = 9.0, core = 0.0, a = 0.0;
  vec4 cfg = uP[127];       // line width, glow k, glow amount, fade ends along x
  for (int k = 0; k < 63; k++) {
    if (k >= uCount) break;
    vec4 e = uP[k * 2], f = uP[k * 2 + 1];
    float dk;
    if (f.y < 0.5) dk = sdSeg(p, e.xy, e.zw);
    else if (f.y < 1.5) {
      vec2 dd = p - e.xy;
      float th = atan(dd.y, dd.x);
      float a0 = e.w, a1 = f.z;
      float t = mod(th - a0, TAU);
      if (t <= a1 - a0) dk = abs(length(dd) - e.z);
      else dk = min(length(dd - e.z * vec2(cos(a0), sin(a0))), length(dd - e.z * vec2(cos(a1), sin(a1))));
    } else dk = max(0.0, length(p - e.xy) - e.z);
    float w = cfg.x * f.x + 0.004;
    core = max(core, (1.0 - smoothstep(w * 0.35, w, dk)) * min(1.0, f.x));
    a = max(a, exp(-dk * cfg.y) * cfg.z * min(1.0, f.x));
  }
  float fade = cfg.w > 0.5 ? pow(max(0.0, 1.0 - p.x * p.x), 0.5) : 1.0;
  return vec4(1.0, sat(core * fade), sat((1.0 - length(p) * 0.7) * fade), sat(max(core, a) * fade));
}
// wisp: a tendril along the polyline uP[0..n) (xy, z = t along)
vec4 genWisp(vec2 p) {
  float best = 9.0, bt = 0.0;
  for (int k = 0; k < 40; k++) {
    if (k + 1 >= uCount) break;
    float d = sdSeg(p, uP[k].xy, uP[k + 1].xy);
    if (d < best) { best = d; bt = uP[k].z; }
  }
  float th = 0.03 + 0.13 * pow(max(sin(3.14159 * bt), 0.0), 0.8);
  float n = n01(p * 4.0 + uSeed, 3);
  float dens = exp(-(best * best) / (th * th)) * (0.55 + 0.6 * n);
  return vec4(sat(0.6 + 0.4 * n), sat(exp(-(best * best) / (th * th * 0.2)) * sin(3.14159 * bt)), sat(sin(3.14159 * bt) * 0.6 + n * 0.4), sat(dens) * edgeFade(p, 0.86));
}
vec4 genStreak(vec2 p) {
  float along = ((max(0.0, 1.0 - p.x * p.x)) * (max(0.0, 1.0 - p.x * p.x)));
  float w = 0.035 + 0.06 * along;
  return vec4(1.0, sat(exp(-(p.y * p.y) / (w * w * 0.15)) * along), along, sat(exp(-(p.y * p.y) / (w * w)) * along));
}
vec4 genDot(vec2 p) {
  float r = length(p);
  return vec4(1.0, 1.0 - smoothstep(0.0, 0.22, r), 1.0 - r, sat(1.0 - smoothstep(0.2, 0.26, r) + exp(-r * 9.0) * 0.35 * (1.0 - r)));
}
vec4 genHex(vec2 p) {
  vec2 a = abs(p);
  float d = max(a.x * 0.866 + a.y * 0.5, a.y) - 0.6;
  float fill = 1.0 - smoothstep(-0.015, 0.015, d);
  float rim = exp(-(d * d) / 0.0012);
  return vec4(1.0, sat(rim), sat(1.0 - length(p)), sat(fill * 0.42 + rim * 0.75 + exp(-max(0.0, d) * 14.0) * 0.15));
}
// pebble: polygon uP[0..n), height from the inside distance, lit
float pebH(vec2 p) { return sqrt(clamp(-sdPoly(p, uCount) / 0.3, 0.0, 1.0)); }
vec4 genPebble(vec2 p) {
  float d = sdPoly(p, uCount);
  float e = 2.0 / 128.0;
  float h = pebH(p);
  vec3 n = normalize(vec3(-(pebH(p + vec2(e, 0.0)) - h) / e * 0.25, -(pebH(p + vec2(0.0, e)) - h) / e * 0.25, 1.0));
  float lit = sat(dot(n, normalize(vec3(-0.5, 0.62, 0.6))));
  float nn = n01(p * 9.0 + uSeed, 3);
  return vec4(sat((0.18 + 0.82 * lit) * (0.75 + 0.35 * nn)), sat((1.0 - smoothstep(0.0, 0.08, -d)) * 0.5), nn, 1.0 - smoothstep(-0.015, 0.015, d));
}
vec4 genCrescent(vec2 p) {
  float d1 = length(p) - 0.78, d2 = length(p - vec2(0.2, 0.12)) - 0.7;
  float d = max(d1, -d2);
  float fill = 1.0 - smoothstep(-0.012, 0.012, d);
  float inner = exp(-(d2 * d2) / 0.002) * step(d1, 0.0);
  return vec4(1.0, sat(inner + fill * 0.3), sat(fill * (0.5 - p.x * 0.5)), sat(fill + exp(-max(0.0, d) * 12.0) * 0.35));
}

// --- murim accents -------------------------------------------------------------------------------------------------
// talisman: a paper slip with brushed script and a seal. R paper tone (marks darker), G script mask (glows / burns
// with def.heat), B dissolve order (edges burn first), A coverage with a torn lower edge
vec4 genTalisman(vec2 p) {
  float torn = 0.06 * fbm(vec2(p.x * 5.0, 3.0 + uSeed), 3);
  float dx = abs(p.x) - 0.3, dy = max(p.y - 0.86, -(p.y + 0.84 + torn));
  float d = max(dx, dy);
  float inside = 1.0 - smoothstep(-0.012, 0.012, d);
  float m = 1e3;
  for (int k = 0; k < 12; k++) { if (k >= uCount) break; m = min(m, sdSeg(p, uP[k].xy, uP[k].zw)); }
  float mark = 1.0 - smoothstep(0.028, 0.05, m + 0.02 * fbm(p * 9.0, 2));
  float seal = 1.0 - smoothstep(0.1, 0.12, max(abs(p.x), abs(p.y + 0.58)));
  float fibre = n01(p * vec2(26.0, 5.0) + uSeed, 3);
  float script = max(mark, seal * (0.55 + 0.45 * n01(p * 14.0, 2)));
  return vec4(sat((0.78 + 0.22 * fibre) * (1.0 - 0.7 * script)), sat(script), sat(smoothstep(0.0, 0.3, -d) * 0.75 + fibre * 0.25), inside);
}
// leaf: variant 0 a narrow bamboo leaf, variant 1 a broad serrated leaf; midrib and side veins in the shade channel
vec4 genLeaf(vec2 p) {
  float s = (p.y + 0.86) / 1.72;
  float bend = (uVar == 0 ? 0.1 : 0.05) * sin(s * 2.6 + uSeed);
  float xx = p.x - bend;
  float w = -1.0;
  if (s > 0.0 && s < 1.0) w = uVar == 0 ? 0.16 * pow(max(sin(3.14159 * pow(max(s, 0.0), 0.62)), 0.0), 0.9) : 0.4 * pow(max(sin(3.14159 * pow(max(s, 0.0), 0.85)), 0.0), 0.8) * (0.9 + 0.1 * sin(s * 44.0));
  float d = abs(xx) - w;
  float inside = 1.0 - smoothstep(-0.014, 0.014, d);
  float rib = exp(-(xx * xx) / 0.0005);
  float veins = uVar == 0 ? 0.0 : pow(abs(sin((s * 9.0 - abs(xx) * 7.0) * 3.14159)), 14.0) * 0.5;
  float tone = n01(p * vec2(7.0, 3.0) + uSeed, 3);
  return vec4(sat((0.55 + 0.4 * s) * (1.0 - 0.35 * rib - 0.3 * veins) * (0.82 + 0.3 * tone)), sat((1.0 - smoothstep(0.0, 0.07, -d)) * inside * 0.8),
              sat(smoothstep(0.0, 0.25, -d) * 0.7 + tone * 0.3), inside);
}
// ink: variant 0 a thrown blot with satellite drops, variant 1 a splash flung along +X (velocity-stretched strokes)
vec4 genInk(vec2 p) {
  vec2 q = uVar == 1 ? vec2((p.x - 0.25) * 0.62, p.y * 1.5) : p;
  float r = length(q), th = atan(q.y, q.x);
  vec2 c = vec2(cos(th), sin(th));
  float lobes = 0.2 * fbm(c * 1.6 + uSeed, 3) + 0.1 * fbm(c * 5.0 + uSeed * 2.0, 2);
  float spikes = pow(n01(c * 3.2 + uSeed * 3.0, 2), 5.0) * 1.1;
  float d = r - (0.34 + lobes + spikes * (uVar == 1 ? 0.25 + 0.75 * sat(-c.x) : 0.5));
  float blot = 1.0 - smoothstep(-0.02, 0.02, d);
  float drops = 0.0;
  for (int k = 0; k < 16; k++) { if (k >= uCount) break; vec4 b = uP[k]; drops = max(drops, 1.0 - smoothstep(b.z * 0.7, b.z, length(p - b.xy))); }
  float dry = uVar == 1 ? smoothstep(0.35, 0.6, n01(vec2(p.x * 1.5, p.y * 22.0) + uSeed, 3) + sat(p.x + 0.4) * 0.5) : 1.0;
  float a = max(blot * dry, drops);
  return vec4(1.0, sat((1.0 - smoothstep(0.0, 0.1, -d)) * blot), sat(smoothstep(0.0, 0.4, -d) * 0.7 + 0.3 * n01(p * 5.0, 2)), sat(a));
}
// brush: a dry-brush stroke along X, wet and full at the head (+X), splitting into separate hairs toward the tail
vec4 genBrush(vec2 p) {
  float s = (p.x + 0.92) / 1.84;                       // 0 tail -> 1 head
  float w = (uVar == 1 ? 0.3 : 0.17) * pow(sat(s), 0.45) * (1.0 - smoothstep(0.9, 1.0, s)) + 0.012;
  float y = p.y + 0.05 * sin(s * 3.0 + uSeed);
  float band = 1.0 - smoothstep(w * 0.8, w, abs(y));
  float hair = n01(vec2(p.x * 1.1 + uSeed, y / max(w, 0.02) * 4.5 + uSeed * 3.0), 3);
  float dry = smoothstep(0.0, 0.16, hair - mix(0.66, 0.2, pow(sat(s), 0.8)));
  float fine = n01(vec2(p.x * 3.0, y * 60.0) + uSeed, 2);
  float a = band * dry * (0.8 + 0.2 * fine) * smoothstep(0.0, 0.08, s);
  return vec4(1.0, sat(exp(-(y * y) / (w * w * 0.12)) * s * a), sat(s * 0.8 + hair * 0.2), sat(a));
}
// enso: a ring drawn with one loaded brush stroke: swelling and thinning line, an open end, dry streaks along the turn
vec4 genEnso(vec2 p) {
  float r = length(p), th = atan(p.y, p.x);
  float t = fract(th / TAU + 0.63);                    // 0 start of the stroke -> 1 its dry end
  float R = 0.7 + 0.025 * sin(t * 9.0 + uSeed);
  float w = 0.085 * (0.45 + 0.85 * sin(3.14159 * pow(max(t, 0.0), 0.7))) * (1.0 - smoothstep(0.9, 0.97, t)) * smoothstep(0.0, 0.03, t);
  float band = 1.0 - smoothstep(w * 0.75, w, abs(r - R));
  float hair = n01(vec2(t * 7.0 + uSeed, (r - R) / max(w, 0.01) * 3.2), 3);
  float dry = smoothstep(0.0, 0.14, hair - mix(0.15, 0.62, t * t));
  float a = band * dry;
  return vec4(1.0, sat(exp(-(((r - R) / max(w * 0.35, 0.004)) * ((r - R) / max(w * 0.35, 0.004)))) * a), sat(1.0 - t), sat(a));
}

// --- tiling noise textures -----------------------------------------------------------------------------------------
vec4 genNoise(vec2 uv) {
  float r = fbmP(uv * 4.0, 5, vec2(4.0), 0.5);
  vec2 c = cellular(uv * 8.0, 8.0);
  float a = fbmP(uv * 16.0, 3, vec2(16.0), 0.5);
  return vec4(sat(r * 0.85 + 0.5), sat(1.0 - c.x * 1.35), sat((c.y - c.x) * 2.2), sat(a * 0.9 + 0.5));
}
float psi(vec2 uv) { return gnoise(uv * 4.0, vec2(4.0)) + 0.5 * gnoise(uv * 8.0, vec2(8.0)); }
vec4 genFlow(vec2 uv) {
  float s = fbmP(uv * vec2(2.0, 24.0), 4, vec2(2.0, 24.0), 0.55);
  vec2 w = vec2(fbmP(uv * 4.0 + 0.3, 3, vec2(4.0), 0.5), fbmP(uv * 4.0 + 0.7, 3, vec2(4.0), 0.5));
  float sw = fbmP(uv * 4.0 + w * 0.9, 4, vec2(4.0), 0.5);
  float e = 1.0 / 256.0;
  vec2 curl = vec2(psi(uv + vec2(0.0, e)) - psi(uv - vec2(0.0, e)), -(psi(uv + vec2(e, 0.0)) - psi(uv - vec2(e, 0.0)))) / (2.0 * e);
  return vec4(sat(s * 0.9 + 0.5), sat(sw * 0.9 + 0.5), clamp(curl * 0.022 + 0.5, 0.0, 1.0));
}

void main() {
  vec2 p = vUv * 2.0 - 1.0;
  vec4 o;
  if (uKind == ${K.noise}) o = genNoise(vUv);
  else if (uKind == ${K.flow}) o = genFlow(vUv);
  else if (uKind == ${K.smoke}) o = genSmoke(p);
  else if (uKind == ${K.flame}) o = genFlame(p);
  else if (uKind == ${K.burst}) o = genBurst(p);
  else if (uKind == ${K.glow}) o = genGlow(p);
  else if (uKind == ${K.glowHard}) o = genGlowHard(p);
  else if (uKind == ${K.disc}) o = genDisc(p);
  else if (uKind == ${K.spark}) o = genSpark(p);
  else if (uKind == ${K.ember}) o = genEmber(p);
  else if (uKind == ${K.dust}) o = genDust(p);
  else if (uKind == ${K.star}) o = genStar(p);
  else if (uKind == ${K.ring}) o = genRing(p);
  else if (uKind == ${K.shard}) o = genShard(p);
  else if (uKind == ${K.snow}) o = genSnow(p);
  else if (uKind == ${K.ash}) o = genAsh(p);
  else if (uKind == ${K.petal}) o = genPetal(p);
  else if (uKind == ${K.lines}) o = genLines(p);
  else if (uKind == ${K.wisp}) o = genWisp(p);
  else if (uKind == ${K.streak}) o = genStreak(p);
  else if (uKind == ${K.dot}) o = genDot(p);
  else if (uKind == ${K.hex}) o = genHex(p);
  else if (uKind == ${K.pebble}) o = genPebble(p);
  else if (uKind == ${K.talisman}) o = genTalisman(p);
  else if (uKind == ${K.leaf}) o = genLeaf(p);
  else if (uKind == ${K.ink}) o = genInk(p);
  else if (uKind == ${K.brush}) o = genBrush(p);
  else if (uKind == ${K.enso}) o = genEnso(p);
  else o = genCrescent(p);
  if (uKind < ${K.noise}) o.a *= edgeFade(p, 0.8);
  gl_FragColor = clamp(o, 0.0, 1.0);
}`;

// ---------------------------------------------------------------------------------------------------------------
// per-sprite parameters (drawn from a fixed-seed RNG so the atlas never changes)

function smokeParams(rng, variant) {
  const conf = [
    { n: 9, sx: 0.36, sy: 0.3, rMin: 0.2, rMax: 0.34, warp: 0.13, thr: 0.12, soft: 0.7, bil: 0.7, bf: 1.7, bump: 0.15 },   // round billow
    { n: 11, sx: 0.5, sy: 0.24, rMin: 0.17, rMax: 0.3, warp: 0.15, thr: 0.12, soft: 0.7, bil: 0.7, bf: 2.0, bump: 0.14 },   // wide
    { n: 7, sx: 0.38, sy: 0.38, rMin: 0.14, rMax: 0.3, warp: 0.3, thr: 0.1, soft: 0.8, bil: 0.95, bf: 1.6, bump: 0.1 },  // wispy
    { n: 16, sx: 0.42, sy: 0.38, rMin: 0.11, rMax: 0.22, warp: 0.1, thr: 0.16, soft: 0.6, bil: 0.55, bf: 3.0, bump: 0.15 }, // lumpy
  ][variant];
  const P = [[0, -0.02, 0.42 + rng() * 0.06, 0.95]];
  for (let k = 1; k < conf.n; k++) {
    const a = rng() * TAU, d = Math.sqrt(rng());
    const r = conf.rMin + (conf.rMax - conf.rMin) * Math.pow(rng(), 1.3) * (1 - d * 0.4);
    P.push([Math.cos(a) * d * conf.sx, Math.sin(a) * d * conf.sy + 0.03, r, 0.55 + 0.45 * rng()]);
  }
  const p = { count: P.length, list: P, extra: { 100: [conf.warp, conf.thr, conf.bil, conf.bf], 101: [conf.bump, conf.soft, 0, 0] } };
  return p;
}
function burstParams(rng) {
  const L = [];
  for (let k = 0; k < 28; k++) L.push([rng() * TAU, 0.006 + 0.022 * Math.pow(rng(), 2), 0.35 + 0.6 * Math.pow(rng(), 0.7), 0]);
  return { count: L.length, list: L };
}
function shardParams(rng, variant) {
  const shapes = [
    [0, 0.9, 0.2, 0.42, 0.24, -0.38, 0.07, -0.86, -0.15, -0.8, -0.25, -0.26, -0.17, 0.44],
    [0.06, 0.92, 0.3, 0.1, 0.18, -0.7, -0.08, -0.88, -0.28, -0.42, -0.2, 0.3],
    [-0.05, 0.86, 0.17, 0.55, 0.35, -0.1, 0.12, -0.84, -0.22, -0.66, -0.34, 0.05, -0.16, 0.6],
  ];
  const pts = shapes[variant].map((v) => v * 0.95 + (rng() - 0.5) * 0.03);
  const list = [];
  for (let i = 0; i < pts.length; i += 2) list.push([pts[i], pts[i + 1], 0, 0]);
  const bi = variant === 1 ? 3 : 4;
  const tip = [pts[0], pts[1]], base = [pts[bi * 2] * 0.5, pts[bi * 2 + 1] * 0.9];
  const mid = [pts[2] * 0.25 + pts[pts.length - 2] * 0.1, (pts[3] + pts[pts.length - 1]) * 0.25];
  return { count: list.length, list, extra: { 30: [tip[0], tip[1], base[0], base[1]], 31: [mid[0], mid[1], 0, 0] } };
}
function pebbleParams(rng, variant) {
  const n = 8 + variant, list = [];
  for (let k = 0; k < n; k++) {
    const a = (k / n) * TAU + (rng() - 0.5) * 0.5;
    const r = (0.5 + rng() * 0.25) * (variant === 2 ? (k % 2 ? 0.8 : 1.05) : 1);
    list.push([Math.cos(a) * r * (variant === 1 ? 1.15 : 1), Math.sin(a) * r * (variant === 1 ? 0.75 : 1), 0, 0]);
  }
  return { count: n, list };
}
function flameParams(variant) {
  const t = [
    [[0, 0.94, 0.44, 0]],
    [[-0.15, 0.93, 0.38, 0.6], [0.22, 0.68, 0.28, 2.1]],
    [[0.02, 0.82, 0.52, 1.2], [-0.34, 0.58, 0.26, 2.9], [0.35, 0.66, 0.26, 4.4]],
  ][variant];
  return { count: t.length, list: t.map((x) => [...x]) };
}
/** line-art builder: seg / arc / dot elements -> uniform list */
function lineArt(width, glowK, glowAmt, fadeEnds, build) {
  const list = [];
  const L = {
    seg(ax, ay, bx, by, w = 1) { list.push([ax, ay, bx, by], [w, 0, 0, 0]); },
    arc(cx, cy, r, a0 = 0, a1 = TAU, w = 1) { list.push([cx, cy, r, a0], [w, 1, a1, 0]); },
    dot(cx, cy, r = 0.025, w = 1) { list.push([cx, cy, r, 0], [w, 2, 0, 0]); },
  };
  build(L);
  return { count: list.length / 2, list, extra: { 127: [width, glowK, glowAmt, fadeEnds ? 1 : 0] } };
}
function runeParams(variant) {
  return lineArt(0.04, 15, 0.38, false, (L) => {
    if (variant === 0) {
      // bar seal: a ring around three stacked bars, the middle one broken (our own mark, not a set trigram chart)
      L.arc(0, 0, 0.86); L.arc(0, 0, 0.74, 0.5, 2.6, 0.6); L.arc(0, 0, 0.74, 3.64, 5.74, 0.6);
      L.seg(-0.44, 0.34, 0.44, 0.34, 1.5); L.seg(-0.44, 0, -0.1, 0, 1.5); L.seg(0.1, 0, 0.44, 0, 1.5); L.seg(-0.44, -0.34, 0.44, -0.34, 1.5);
    } else if (variant === 1) {
      // seal-script glyph: square strokes inside an open frame, a hooked corner and a dot
      L.seg(-0.62, 0.66, 0.62, 0.66, 1.2); L.seg(-0.62, 0.66, -0.62, -0.7, 1.2); L.seg(0.62, 0.66, 0.62, -0.3, 1.2);
      L.seg(-0.3, 0.3, 0.3, 0.3); L.seg(0, 0.3, 0, -0.34); L.seg(-0.3, -0.02, 0.3, -0.02); L.seg(-0.3, -0.34, 0.3, -0.34);
      L.seg(-0.62, -0.7, 0.2, -0.7, 1.2); L.seg(0.62, -0.3, 0.4, -0.52);
      L.dot(0.5, -0.74, 0.05);
    } else {
      // star chart: seven stars of unequal weight joined into a bent chain, inside a ring with four ticks
      const S = [[-0.56, 0.3], [-0.26, 0.5], [0.08, 0.36], [0.3, 0.06], [0.12, -0.28], [0.4, -0.5], [-0.3, -0.42]];
      L.arc(0, 0, 0.88, 0, TAU, 0.7);
      for (let k = 0; k < 4; k++) { const a = (k / 4) * TAU + 0.4; L.seg(Math.cos(a) * 0.78, Math.sin(a) * 0.78, Math.cos(a) * 0.88, Math.sin(a) * 0.88, 0.8); }
      for (let k = 0; k < S.length - 2; k++) L.seg(S[k][0], S[k][1], S[k + 1][0], S[k + 1][1], 0.55);
      L.seg(S[4][0], S[4][1], S[6][0], S[6][1], 0.55);
      S.forEach((q, k) => L.dot(q[0], q[1], k % 3 === 0 ? 0.07 : 0.045));
    }
  });
}
function talismanParams(rng) {
  // brushed script: a column of short strokes (horizontals, a long vertical, hooks) on the slip
  const list = [];
  let y = 0.66;
  for (let k = 0; k < 7; k++) {
    const w = 0.08 + rng() * 0.12, tilt = (rng() - 0.5) * 0.08;
    list.push([-w, y + tilt, w, y - tilt]);
    if (rng() < 0.6) list.push([(rng() - 0.5) * 0.2, y + 0.02, (rng() - 0.5) * 0.24, y - 0.13]);
    y -= 0.14 + rng() * 0.04;
    if (list.length >= 11) break;
  }
  list.push([0, 0.7, 0.02, -0.32]);
  return { count: list.length, list };
}
function inkParams(rng, variant) {
  const list = [];
  for (let k = 0; k < 12; k++) {
    const a = variant ? Math.PI + (rng() - 0.5) * 1.5 : rng() * TAU, d = 0.55 + rng() * 0.32;
    list.push([Math.cos(a) * d * (variant ? 0.95 : 1) + (variant ? 0.15 : 0), Math.sin(a) * d * (variant ? 0.6 : 1), 0.02 + 0.05 * Math.pow(rng(), 2), 0]);
  }
  return { count: list.length, list };
}
function arcParams(rng, variant) {
  let pts = [[-0.9, (rng() - 0.5) * 0.2], [0.9, (rng() - 0.5) * 0.2]];
  let disp = 0.44;
  for (let it = 0; it < 5; it++) {
    const np = [];
    for (let k = 0; k < pts.length - 1; k++) {
      const a = pts[k], b = pts[k + 1];
      np.push(a, [(a[0] + b[0]) / 2 + (rng() - 0.5) * disp * 0.3, (a[1] + b[1]) / 2 + (rng() - 0.5) * disp]);
    }
    np.push(pts[pts.length - 1]);
    pts = np;
    disp *= 0.56;
  }
  return lineArt(0.018, 16, 0.5, true, (L) => {
    for (let k = 0; k < pts.length - 1; k++) L.seg(pts[k][0], pts[k][1], pts[k + 1][0], pts[k + 1][1], 1);
    let bp = pts[10 + Math.floor(rng() * 12)], ang = (rng() < 0.5 ? 1 : -1) * (0.5 + rng() * 0.5);
    for (let k = 0; k < 7 + variant * 2; k++) {
      ang += (rng() - 0.5) * 0.9;
      const np = [bp[0] + Math.cos(ang) * 0.09, bp[1] + Math.sin(ang) * 0.09];
      L.seg(bp[0], bp[1], np[0], np[1], 0.6 * (1 - k / 12));
      bp = np;
    }
  });
}
function wispParams(rng, variant) {
  const ph = rng() * TAU, amp = variant ? 0.32 : 0.2, fr = variant ? 1.4 : 0.9, list = [];
  for (let k = 0; k <= 32; k++) {
    const t = k / 32;
    list.push([-0.82 + 1.64 * t, amp * Math.sin(t * TAU * fr * 0.5 + ph) * Math.sin(Math.PI * t) + (variant ? -0.1 + 0.25 * t : 0), t, 0]);
  }
  return { count: list.length, list };
}
const starParams = (rays) => ({ count: rays.length, list: rays.map((r) => [r[0], r[1], r[2], 0]) });

/** atlas layout: [name, kind, params, variant]; 8 cells of 256 px then 40 cells of 128 px */
function layout() {
  const rng = makeRng(7177);
  const BIG = [
    ['smoke1', K.smoke, smokeParams(rng, 0)], ['smoke2', K.smoke, smokeParams(rng, 1)], ['smoke3', K.smoke, smokeParams(rng, 2)], ['smoke4', K.smoke, smokeParams(rng, 3)],
    ['flame1', K.flame, flameParams(0)], ['flame2', K.flame, flameParams(1)], ['flame3', K.flame, flameParams(2)], ['burst', K.burst, burstParams(rng)],
  ];
  const SMALL = [
    ['glow', K.glow], ['glowHard', K.glowHard], ['disc', K.disc], ['spark', K.spark], ['ember', K.ember], ['dust', K.dust],
    ['star4', K.star, starParams([[0, 0.95, 0.03], [Math.PI / 2, 0.95, 0.03]])],
    ['glint', K.star, starParams([[0, 0.98, 0.02], [Math.PI / 2, 0.98, 0.02], [Math.PI / 4, 0.5, 0.016], [-Math.PI / 4, 0.5, 0.016]])],
    ['ring', K.ring], ['shard1', K.shard, shardParams(rng, 0)], ['shard2', K.shard, shardParams(rng, 1)], ['shard3', K.shard, shardParams(rng, 2)],
    ['snow1', K.snow, null, 0], ['snow2', K.snow, null, 1], ['ash1', K.ash, null, 0], ['ash2', K.ash, null, 1],
    ['petal', K.petal], ['rune1', K.lines, runeParams(0)], ['rune2', K.lines, runeParams(1)], ['rune3', K.lines, runeParams(2)],
    ['wisp1', K.wisp, wispParams(rng, 0)], ['wisp2', K.wisp, wispParams(rng, 1)], ['streak', K.streak], ['dot', K.dot],
    ['hex', K.hex], ['arc1', K.lines, arcParams(rng, 0)], ['arc2', K.lines, arcParams(rng, 1)], ['arc3', K.lines, arcParams(rng, 2)],
    ['pebble1', K.pebble, pebbleParams(rng, 0)], ['pebble2', K.pebble, pebbleParams(rng, 1)], ['pebble3', K.pebble, pebbleParams(rng, 2)], ['crescent', K.crescent],
    // murim accents (row 5)
    ['talisman', K.talisman, talismanParams(rng)], ['leaf1', K.leaf, null, 0], ['leaf2', K.leaf, null, 1], ['ink1', K.ink, inkParams(rng, 0), 0],
    ['ink2', K.ink, inkParams(rng, 1), 1], ['brush1', K.brush, null, 0], ['brush2', K.brush, null, 1], ['enso', K.enso],
  ];
  const cells = [];
  BIG.forEach((e, k) => cells.push({ e, size: 256, x: (k % 4) * 256, y: Math.floor(k / 4) * 256 }));
  SMALL.forEach((e, k) => cells.push({ e, size: 128, x: (k % 8) * 128, y: 512 + Math.floor(k / 8) * 128 }));
  return cells;
}

/** variant groups: name -> [first sprite, count] (variants are consecutive cells of one row) */
const GROUPS = { smoke: ['smoke1', 4], flame: ['flame1', 3], shard: ['shard1', 3], snow: ['snow1', 2], ash: ['ash1', 2], rune: ['rune1', 3], wisp: ['wisp1', 2], arc: ['arc1', 3], pebble: ['pebble1', 3],
  leaf: ['leaf1', 2], ink: ['ink1', 2], brush: ['brush1', 2] };

/**
 * Generate every VFX texture with `renderer`. Returns
 * { atlas, noise, flow (THREE.Texture), sprites: { name: { u, v, w, h, frames } }, sprite(name), dispose() }.
 */
export function createTextures(renderer) {
  const mkRT = (size, wrap, height = size) => {
    const rt = new THREE.WebGLRenderTarget(size, height, {
      type: THREE.UnsignedByteType, format: THREE.RGBAFormat, depthBuffer: false, stencilBuffer: false,
      generateMipmaps: true, minFilter: THREE.LinearMipmapLinearFilter, magFilter: THREE.LinearFilter, wrapS: wrap, wrapT: wrap,
    });
    rt.texture.colorSpace = THREE.NoColorSpace;
    return rt;
  };
  const rtAtlas = mkRT(ATLAS, THREE.ClampToEdgeWrapping, ATLAS_H);
  const rtNoise = mkRT(NOISE, THREE.RepeatWrapping);
  const rtFlow = mkRT(NOISE, THREE.RepeatWrapping);

  const scene = new THREE.Scene();
  const cam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
  const geos = [];
  const mats = [];
  const quad = (x0, y0, x1, y1) => {
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(new Float32Array([x0, y0, 0, x1, y0, 0, x1, y1, 0, x0, y1, 0]), 3));
    g.setAttribute('uv', new THREE.BufferAttribute(new Float32Array([0, 0, 1, 0, 1, 1, 0, 1]), 2));
    g.setIndex([0, 1, 2, 0, 2, 3]);
    geos.push(g);
    return g;
  };
  const material = (kind, params, variant, seed) => {
    const P = [];
    for (let i = 0; i < MAXP; i++) P.push(new THREE.Vector4());
    if (params) {
      params.list.forEach((v, i) => P[i].set(v[0], v[1], v[2] || 0, v[3] || 0));
      if (params.extra) for (const k in params.extra) P[k].fromArray(params.extra[k]);
    }
    const m = new THREE.ShaderMaterial({
      vertexShader: GEN_VERT, fragmentShader: GEN_FRAG, depthTest: false, depthWrite: false, blending: THREE.NoBlending,
      uniforms: { uKind: { value: kind }, uVar: { value: variant || 0 }, uCount: { value: params ? params.count : 0 }, uSeed: { value: seed }, uP: { value: P } },
    });
    mats.push(m);
    return m;
  };
  const sprites = {};
  const cells = layout();
  cells.forEach((c, i) => {
    const [name, kind, params, variant] = c.e;
    const x0 = (c.x / ATLAS) * 2 - 1, y0 = (c.y / ATLAS_H) * 2 - 1, x1 = ((c.x + c.size) / ATLAS) * 2 - 1, y1 = ((c.y + c.size) / ATLAS_H) * 2 - 1;
    const mesh = new THREE.Mesh(quad(x0, y0, x1, y1), material(kind, params, variant, 3 + i * 7));
    mesh.frustumCulled = false;
    scene.add(mesh);
    sprites[name] = { u: c.x / ATLAS, v: c.y / ATLAS_H, w: c.size / ATLAS, h: c.size / ATLAS_H, frames: 1 };
  });
  for (const g in GROUPS) sprites[g] = { ...sprites[GROUPS[g][0]], frames: GROUPS[g][1] };

  const prevRT = renderer.getRenderTarget();
  const prevAuto = renderer.autoClear;
  renderer.autoClear = false;
  renderer.setRenderTarget(rtAtlas);
  renderer.clear(true, false, false);
  renderer.render(scene, cam);
  // noise textures: one full-screen quad each
  scene.clear();
  const full = quad(-1, -1, 1, 1);
  const nMesh = new THREE.Mesh(full, material(K.noise, null, 0, 101));
  nMesh.frustumCulled = false;
  scene.add(nMesh);
  renderer.setRenderTarget(rtNoise);
  renderer.render(scene, cam);
  nMesh.material = material(K.flow, null, 0, 202);
  renderer.setRenderTarget(rtFlow);
  renderer.render(scene, cam);
  renderer.setRenderTarget(prevRT);
  renderer.autoClear = prevAuto;
  for (const g of geos) g.dispose();
  for (const m of mats) m.dispose();

  return {
    atlas: rtAtlas.texture, noise: rtNoise.texture, flow: rtFlow.texture, sprites,
    targets: { atlas: rtAtlas, noise: rtNoise, flow: rtFlow },
    sprite(name) {
      const s = sprites[name];
      if (!s) throw new Error('vfx: unknown sprite "' + name + '" (have: ' + Object.keys(sprites).join(', ') + ')');
      return s;
    },
    dispose() { rtAtlas.dispose(); rtNoise.dispose(); rtFlow.dispose(); },
  };
}
