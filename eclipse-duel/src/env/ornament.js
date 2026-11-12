// Carved stone detail without geometry: a GPU-baked relief atlas (4x4 cells of carved motifs: eclipse roundels,
// robed processional figures, egg-and-dart, dentils, glyph bands, keystone masks, leaves ...) stored as tangent-space
// normal + height + cavity, and a tiling weather map (cracks, rain streaks, lichen, moss). The stone material reads
// the per-vertex `orn` attribute (cell u, v, cell index, relief amount) written by Builder({ orn: true }).
//
//   const orn = bakeOrnament(renderer, 1024)   -> { atlas: WebGLRenderTarget, weather: WebGLRenderTarget }
//   ORN.<name>                                  cell indices for Builder opts.orn.cell

import * as THREE from 'three';
import { NOISE } from './glsl.js';
import { bakeTarget } from './bake.js';

/** Relief atlas cells (Builder opts.orn.cell). Bands tile along u; the others are single panels (u, v in 0..1). */
export const ORN = {
  roundel: 0,     // eclipse disc: black sun, corona ring, sixteen rays, beaded frame
  figure: 1,      // hooded figure walking right with an eclipse staff (procession; mirror u for the other way)
  orant: 2,       // hooded figure, arms raised, holding the eclipse overhead
  rosette: 3,     // eight-lobed sunburst rosette
  eggDart: 4,     // egg-and-dart band (one egg per unit u)
  dentil: 5,      // dentil band (one dentil per unit u)
  guilloche: 6,   // two interlaced strands (one crossing per unit u)
  phases: 7,      // eclipse-phase band: a disc being swallowed, one per unit u
  mask: 8,        // keystone mask: the hooded guardian's face with an eclipse on the brow
  leaf: 9,        // carved leaf (capitals): mid rib, lobes, curled tip
  glyphs: 10,     // inscription band: six sunk glyphs of the eclipse cult per unit u
  panel: 11,      // sunk panel with a raised frame
  scales: 12,     // imbricated scales (tiles in u and v)
  laurel: 13,     // leaf torus: overlapping leaves along u
  crescent: 14,   // metope: crescent and three stars
  flute: 15,      // procedural flutes (not baked): u = flute count around, v = height
};
/** Panel mode for a cell: relief only where 0 <= v <= 1 (a single motif on part of a face); u still tiles. */
export const panel = (cell) => cell + 16;

const HEIGHT = /* glsl */ `
${NOISE}
varying vec2 vUv;
const float TAU = 6.28318530718;
float bump(float d, float w) { float b = clamp(-d / w, 0.0, 1.0); return 1.0 - (1.0 - b) * (1.0 - b); }
float sdBox(vec2 p, vec2 b) { vec2 d = abs(p) - b; return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0); }
float sdSeg(vec2 p, vec2 a, vec2 b) { vec2 pa = p - a, ba = b - a; float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0); return length(pa - ba * h); }
float sdTrap(vec2 p, float r1, float r2, float he) {
  vec2 k1 = vec2(r2, he), k2 = vec2(r2 - r1, 2.0 * he);
  p.x = abs(p.x);
  vec2 ca = vec2(p.x - min(p.x, (p.y < 0.0) ? r1 : r2), abs(p.y) - he);
  vec2 cb = p - k1 + k2 * clamp(dot(k1 - p, k2) / dot(k2, k2), 0.0, 1.0);
  float s = (cb.x < 0.0 && ca.y < 0.0) ? -1.0 : 1.0;
  return s * sqrt(min(dot(ca, ca), dot(cb, cb)));
}
float smin(float a, float b, float k) { float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0); return mix(b, a, h) - k * h * (1.0 - h); }
float fillets(vec2 c) { return max(bump(0.06 - c.y, 0.02), bump(c.y - 0.94, 0.02)) * 0.75; }

// a hooded robed figure facing +x; returns height, writes the face cavity mask
float figure(vec2 c, out float face) {
  vec2 p = c - vec2(0.48, 0.0);
  float hem = 0.07 + 0.012 * sin(c.x * 70.0);
  float body = sdTrap(p - vec2(0.0, 0.36), 0.17, 0.095, 0.29);
  body = max(body, hem - c.y);
  float hood = length((c - vec2(0.5, 0.74)) / vec2(1.0, 1.15)) - 0.085;
  hood = smin(hood, sdSeg(c, vec2(0.47, 0.76), vec2(0.4, 0.86)) - 0.03, 0.03);
  float arm = sdSeg(c, vec2(0.5, 0.6), vec2(0.66, 0.47)) - 0.032;
  float staff = sdSeg(c, vec2(0.69, 0.06), vec2(0.69, 0.84)) - 0.011;
  float fin = abs(length(c - vec2(0.69, 0.89)) - 0.04) - 0.012;
  float d = smin(smin(body, hood, 0.04), arm, 0.03);
  float h = bump(d, 0.05) * 0.8;
  // robe folds: soft vertical grooves fanning toward the hem
  float fold = sin((c.x - 0.48) * 70.0 / (0.6 + c.y) + c.y * 3.0);
  h -= 0.07 * fold * step(d, 0.0) * smoothstep(0.65, 0.2, c.y);
  h = max(h, max(bump(staff, 0.012), bump(fin, 0.012)) * 0.75);
  face = (1.0 - smoothstep(-0.005, 0.01, length((c - vec2(0.535, 0.725)) / vec2(0.75, 1.0)) - 0.05));
  h -= face * 0.55;
  return h;
}

float cellHeight(int id, vec2 c, out float dark) {
  dark = 0.0;
  float h = 0.3;
  vec2 q = c - 0.5;
  float r = length(q) * 2.0;
  float a = atan(q.y, q.x);
  if (id == 0) { // eclipse roundel
    float frame = bump(abs(r - 0.91) - 0.05, 0.04);
    float beads = bump(length(vec2(fract(a / TAU * 40.0) - 0.5, (r - 0.8) * 9.0)) - 0.32, 0.18) * step(abs(r - 0.8), 0.05);
    float ray = abs(fract(a / TAU * 16.0) - 0.5) * 2.0;
    float rw = mix(0.32, 0.04, clamp((r - 0.52) / 0.24, 0.0, 1.0));
    float rays = bump(ray - rw, 0.12) * step(0.5, r) * step(r, 0.76);
    float corona = bump(abs(r - 0.43) - 0.06, 0.04);
    h = 0.3 + max(max(frame * 0.6, beads * 0.55), max(rays * 0.5, corona * 0.65));
    float disc = 1.0 - smoothstep(0.33, 0.36, r);
    h = mix(h, 0.02, disc);
    dark = disc;
  } else if (id == 1) {
    float face;
    h = 0.25 + figure(c, face);
    dark = face;
  } else if (id == 2) { // orant: symmetric, arms raised holding the eclipse
    vec2 p = vec2(abs(c.x - 0.5), c.y);
    float body = sdTrap(c - vec2(0.5, 0.33), 0.16, 0.09, 0.26);
    body = max(body, 0.07 - c.y);
    float hood = length((c - vec2(0.5, 0.64)) / vec2(1.0, 1.2)) - 0.075;
    float arm = sdSeg(p, vec2(0.07, 0.55), vec2(0.11, 0.78)) - 0.028;
    float d = smin(smin(body, hood, 0.04), arm, 0.03);
    h = 0.25 + bump(d, 0.05) * 0.8;
    h -= 0.07 * sin((c.x - 0.5) * 80.0) * step(d, 0.0) * smoothstep(0.5, 0.15, c.y);
    float ringD = abs(length(c - vec2(0.5, 0.86)) - 0.075) - 0.018;
    h = max(h, 0.25 + bump(ringD, 0.015) * 0.7);
    float disc = 1.0 - smoothstep(0.05, 0.06, length(c - vec2(0.5, 0.86)));
    float face = 1.0 - smoothstep(0.03, 0.045, length((c - vec2(0.5, 0.63)) / vec2(1.0, 1.3)));
    h -= (disc + face) * 0.45;
    dark = max(disc, face);
  } else if (id == 3) { // rosette
    float lobes = 0.62 + 0.16 * cos(a * 8.0);
    float pet = bump(r - lobes, 0.2);
    float vein = 1.0 - smoothstep(0.0, 0.05, abs(fract(a / TAU * 8.0 + 0.5) - 0.5));
    h = 0.3 + pet * 0.55 - vein * 0.12 * pet + bump(r - 0.2, 0.08) * 0.25;
    h = mix(h, 0.1, (1.0 - smoothstep(0.08, 0.1, r)));
  } else if (id == 4) { // egg and dart
    vec2 e = (c - vec2(0.5, 0.5)) / vec2(0.3, 0.36);
    float egg = length(e) - 1.0;
    float shell = abs(length((c - vec2(0.5, 0.52)) / vec2(0.38, 0.42)) - 1.0) - 0.06;
    float dart = sdSeg(vec2(min(c.x, 1.0 - c.x), c.y), vec2(0.0, 0.2), vec2(0.0, 0.84)) - 0.035 * (1.0 - c.y * 0.6);
    h = 0.35 + bump(egg, 0.6) * 0.55;
    float channel = 1.0 - smoothstep(0.0, 0.05, abs(length((c - vec2(0.5, 0.5)) / vec2(0.35, 0.41)) - 1.0) - 0.03);
    h = mix(h, 0.08, channel * step(0.0, egg));
    dark = channel * step(0.0, egg) * 0.6;
    h = max(h, 0.3 + bump(shell, 0.03) * 0.45);
    h = max(h, 0.3 + bump(dart, 0.02) * 0.5);
    h = max(h, 0.3 + fillets(c) * 0.6);
  } else if (id == 5) { // dentils
    float b = sdBox(c - vec2(0.5, 0.58), vec2(0.32, 0.4));
    h = 0.1 + bump(b, 0.04) * 0.85;
    h = max(h, 0.1 + bump(0.12 - c.y, 0.03) * 0.6);
    dark = 1.0 - bump(b, 0.08);
  } else if (id == 6) { // guilloche
    float s1 = abs(c.y - (0.5 + 0.28 * sin(TAU * c.x))) - 0.07;
    float s2 = abs(c.y - (0.5 - 0.28 * sin(TAU * c.x))) - 0.07;
    float over = step(0.0, sin(TAU * c.x * 0.5 + 0.0) * cos(TAU * c.x * 0.5));
    float h1 = bump(s1, 0.05) * (0.7 + 0.2 * over), h2 = bump(s2, 0.05) * (0.9 - 0.2 * over);
    h = 0.25 + max(h1, h2) * 0.7;
    float boss = bump(length((c - vec2(0.5, 0.5)) * vec2(1.0, 1.0)) - 0.09, 0.05);
    boss = max(boss, bump(length(vec2(min(c.x, 1.0 - c.x), c.y - 0.5)) - 0.09, 0.05));
    h = max(h, 0.25 + boss * 0.6);
    h = max(h, 0.25 + fillets(c) * 0.6);
  } else if (id == 7) { // eclipse phases
    float disc = length(c - vec2(0.5, 0.5)) - 0.27;
    float bite = length(c - vec2(0.62, 0.56)) - 0.24;
    h = 0.3 + bump(disc, 0.05) * 0.55;
    float sw = (1.0 - smoothstep(-0.01, 0.01, bite)) * step(disc, 0.0);
    h = mix(h, 0.12, sw);
    dark = sw;
    h = max(h, 0.3 + fillets(c) * 0.6);
  } else if (id == 8) { // keystone mask: hood arch, deep face, brow eclipse
    vec2 p = c - vec2(0.5, 0.45);
    float hood = sdTrap(p, 0.26, 0.1, 0.36);
    hood = smin(hood, length(p - vec2(0.0, 0.24)) - 0.17, 0.08);
    float cav = length((p - vec2(0.0, 0.02)) / vec2(0.8, 1.15)) - 0.15;
    h = 0.2 + bump(hood, 0.08) * 0.75;
    float fc = 1.0 - smoothstep(-0.01, 0.02, cav);
    h -= fc * 0.6;
    dark = fc;
    float eyes = bump(length(vec2(abs(p.x) - 0.06, p.y - 0.04)) - 0.022, 0.015);
    h += eyes * fc * 0.25;
    float brow = abs(length(p - vec2(0.0, 0.27)) - 0.055) - 0.014;
    h = max(h, 0.2 + bump(brow, 0.012) * 0.95);
  } else if (id == 9) { // leaf
    vec2 p = c - vec2(0.5, 0.0);
    float w = 0.3 * sin(clamp(c.y / 0.92, 0.0, 1.0) * 3.14159) * (1.0 - 0.25 * c.y);
    float lob = 0.035 * sin(c.y * 40.0);
    float leaf = abs(p.x) - (w + lob);
    leaf = max(leaf, c.y - 0.92);
    float rib = 1.0 - smoothstep(0.0, 0.025, abs(p.x));
    float veins = 1.0 - smoothstep(0.0, 0.02, abs(fract(c.y * 6.0 - abs(p.x) * 4.0) - 0.5) - 0.42);
    h = 0.2 + bump(leaf, 0.06) * (0.65 + 0.25 * c.y) + rib * 0.12 * step(leaf, 0.0) - veins * 0.08 * step(leaf, 0.0);
    float tip = bump(length(c - vec2(0.5, 0.88)) - 0.07, 0.05);
    h = max(h, 0.2 + tip * 0.95);
  } else if (id == 10) { // glyph band (sunk strokes)
    float g = floor(c.x * 6.0);
    vec2 p = vec2(fract(c.x * 6.0) - 0.5, (c.y - 0.5) * 6.0 / 2.6);
    float hs = hash12(vec2(g, 4.7)), hs2 = hash12(vec2(g, 9.1));
    float d = 1e3;
    d = min(d, abs(length(p - vec2(0.0, 0.12)) - 0.16) - 0.035);
    if (hs > 0.5) d = min(d, sdSeg(p, vec2(0.0, -0.32), vec2(0.0, 0.32)) - 0.035);
    else d = min(d, sdSeg(p, vec2(-0.22, -0.3), vec2(0.22, -0.3)) - 0.035);
    if (hs2 > 0.35) d = min(d, sdSeg(p, vec2(-0.2, -0.12), vec2(0.2, -0.12 + (hs2 - 0.6) * 0.4)) - 0.032);
    if (hs2 < 0.6) d = min(d, length(p - vec2(0.18 * sign(hs - 0.5), 0.33)) - 0.05);
    h = 0.5 - (1.0 - smoothstep(0.0, 0.02, d)) * 0.4;
    dark = 1.0 - smoothstep(0.0, 0.02, d);
    h = max(h, 0.5 + fillets(c) * 0.4);
  } else if (id == 11) { // sunk panel with a raised frame
    float outer = sdBox(q, vec2(0.46));
    float inner = sdBox(q, vec2(0.36));
    h = 0.45 + bump(outer, 0.03) * 0.35 * (1.0 - bump(inner, 0.04)) - bump(inner, 0.05) * 0.25;
  } else if (id == 12) { // imbricated scales
    vec2 s = vec2(c.x * 3.0 + 0.5 * step(0.5, fract(c.y * 2.0)), fract(c.y * 2.0) * 1.0);
    vec2 f = vec2(fract(s.x) - 0.5, s.y);
    float sc = length(f * vec2(1.0, 1.4)) - 0.5;
    h = 0.3 + bump(sc, 0.25) * 0.5 * (0.6 + 0.4 * (1.0 - s.y));
  } else if (id == 13) { // laurel torus: overlapping leaves running along u
    vec2 p = vec2(fract(c.x * 2.0), c.y);
    float l1 = length((p - vec2(0.45, 0.68)) * mat2(0.8, -0.6, 0.6, 0.8) / vec2(0.36, 0.13)) - 1.0;
    float l2 = length((p - vec2(0.45, 0.32)) * mat2(0.8, 0.6, -0.6, 0.8) / vec2(0.36, 0.13)) - 1.0;
    h = 0.3 + max(bump(l1, 0.6), bump(l2, 0.6)) * 0.55;
    float berry = bump(length(p - vec2(0.9, 0.5)) - 0.06, 0.04);
    h = max(h, 0.3 + berry * 0.6);
  } else if (id == 14) { // crescent and stars
    float m = length(q - vec2(-0.02, 0.02)) - 0.28;
    float cut = length(q - vec2(0.09, 0.08)) - 0.24;
    h = 0.3 + bump(max(m, -cut), 0.04) * 0.6;
    for (int i = 0; i < 3; i++) {
      vec2 sp = vec2(0.22 + 0.06 * float(i), 0.25 - 0.17 * float(i));
      vec2 d = q - sp;
      float ang = atan(d.y, d.x);
      float star = length(d) - 0.04 * (0.6 + 0.4 * cos(ang * 4.0));
      h = max(h, 0.3 + bump(star, 0.02) * 0.6);
    }
    h = max(h, 0.3 + bump(abs(sdBox(q, vec2(0.46))) - 0.025, 0.02) * 0.4);
  }
  return h;
}

vec4 sampleCell(vec2 uv) {
  vec2 cellF = floor(uv * 4.0);
  int id = int(cellF.y * 4.0 + cellF.x);
  vec2 c = fract(uv * 4.0);
  // the runtime samples [0.02, 0.98] of each cell; stretch that range over the motif
  c = clamp((c - 0.02) / 0.96, 0.0, 1.0);
  float dark;
  float h = cellHeight(id, c, dark);
  // carving tool noise
  h += (vnoise(c * 90.0) - 0.5) * 0.012;
  return vec4(h, dark, 0.0, 1.0);
}
void main() { gl_FragColor = sampleCell(vUv); }
`;

const NORMAL = /* glsl */ `
uniform sampler2D tH; uniform vec2 uTexel;
varying vec2 vUv;
void main() {
  // derivatives stay inside the cell (cells are baked independently)
  vec2 cell = floor(vUv * 4.0);
  vec2 lo = (cell + 0.5 * uTexel * 4.0) / 4.0, hi = (cell + 1.0 - 0.5 * uTexel * 4.0) / 4.0;
  float hx1 = texture2D(tH, clamp(vUv + vec2(uTexel.x, 0.0), lo, hi)).r, hx0 = texture2D(tH, clamp(vUv - vec2(uTexel.x, 0.0), lo, hi)).r;
  float hy1 = texture2D(tH, clamp(vUv + vec2(0.0, uTexel.y), lo, hi)).r, hy0 = texture2D(tH, clamp(vUv - vec2(0.0, uTexel.y), lo, hi)).r;
  vec4 c = texture2D(tH, vUv);
  // relief depth: ~1/7 of the cell width at height 1
  float k = 0.145 / (2.0 * uTexel.x * 4.0);
  vec3 n = normalize(vec3(-(hx1 - hx0) * k, -(hy1 - hy0) * k, 1.0));
  // cavity: height against its neighbourhood (a few taps on a ring), plus the carved dark recesses
  float avg = 0.0;
  for (int i = 0; i < 8; i++) {
    float a = float(i) * 0.785398;
    avg += texture2D(tH, clamp(vUv + vec2(cos(a), sin(a)) * uTexel * 5.0, lo, hi)).r;
  }
  avg /= 8.0;
  float cav = clamp(1.0 + (c.r - avg) * 3.5 - c.g * 0.45 - (0.3 - min(c.r, 0.3)) * 1.2, 0.15, 1.0);
  gl_FragColor = vec4(n.xy * 0.5 + 0.5, c.r, cav);
}
`;

const WEATHER = /* glsl */ `
${NOISE}
uniform vec2 uTexel;
varying vec2 vUv;
float pnoise(vec2 p, float per) {
  vec2 i = floor(p), f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash12(mod(i, per)), hash12(mod(i + vec2(1.0, 0.0), per)), u.x), mix(hash12(mod(i + vec2(0.0, 1.0), per)), hash12(mod(i + vec2(1.0, 1.0), per)), u.x), u.y);
}
float pfbm(vec2 p, float per) { float s = 0.0, a = 0.5, n = 0.0; for (int i = 0; i < 4; i++) { s += a * pnoise(p, per); n += a; p *= 2.0; per *= 2.0; a *= 0.5; } return s / n; }
// periodic voronoi edge distance
float pvor(vec2 x, float per) {
  vec2 n = floor(x), f = fract(x), mr = vec2(0.0), mg = vec2(0.0);
  float md = 8.0;
  for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
    vec2 g = vec2(float(i), float(j)); vec2 o = hash22(mod(n + g, per)); vec2 r = g + o - f; float d = dot(r, r);
    if (d < md) { md = d; mr = r; mg = g; }
  }
  md = 8.0;
  for (int j = -2; j <= 2; j++) for (int i = -2; i <= 2; i++) {
    vec2 g = mg + vec2(float(i), float(j)); vec2 o = hash22(mod(n + g, per)); vec2 r = g + o - f;
    if (dot(mr - r, mr - r) > 1e-5) md = min(md, dot(0.5 * (mr + r), normalize(r - mr)));
  }
  return md;
}
void main() {
  vec2 uv = vUv;
  // R: cracks (a wandering voronoi network, only where a mask allows, thinner in places)
  vec2 w = vec2(pfbm(uv * 4.0, 4.0), pfbm(uv * 4.0 + 7.0, 4.0)) - 0.5;
  float e1 = pvor(uv * 5.0 + w * 0.9, 5.0);
  float e2 = pvor(uv * 11.0 + w * 1.4 + 3.0, 11.0);
  // only a few long cracks survive the masks: most of the stone is sound
  float m1 = smoothstep(0.6, 0.7, pfbm(uv * 3.0 + 2.0, 3.0));
  float m2 = smoothstep(0.62, 0.7, pfbm(uv * 6.0 + 5.0, 6.0)) * m1;
  float crack = max((1.0 - smoothstep(0.0, 0.016, e1)) * m1, (1.0 - smoothstep(0.0, 0.012, e2)) * m2 * 0.7);
  // G: rain streaks (stretched noise; sample with a stretched uv on walls)
  float streak = pfbm(vec2(uv.x * 16.0, uv.y * 2.0), 16.0);
  // B: lichen rosettes
  float lich = smoothstep(0.62, 0.72, pfbm(uv * 9.0 + 1.3, 9.0)) * (0.6 + 0.4 * pnoise(uv * 64.0, 64.0));
  // A: moss blotches (large)
  float moss = pfbm(uv * 3.0 + 9.0, 3.0);
  gl_FragColor = vec4(crack, streak, lich, moss);
}
`;

/**
 * Bake the relief atlas (`size`^2, 4x4 cells) and the tiling weather map.
 * @returns {{atlas: THREE.WebGLRenderTarget, weather: THREE.WebGLRenderTarget}}
 */
export function bakeOrnament(renderer, size = 1024) {
  const texel = new THREE.Vector2(1 / size, 1 / size);
  const h = bakeTarget(renderer, { width: size, frag: HEIGHT, mipmaps: false, float: true });
  const atlas = bakeTarget(renderer, { width: size, frag: NORMAL, uniforms: { tH: { value: h.texture }, uTexel: { value: texel } } });
  h.dispose();
  const ws = Math.max(256, size >> 1);
  const weather = bakeTarget(renderer, { width: ws, frag: WEATHER, uniforms: { uTexel: { value: new THREE.Vector2(1 / ws, 1 / ws) } }, repeat: true });
  return { atlas, weather };
}

/**
 * Stone material patch: relief from the atlas (or procedural flutes), cavity darkening, and weathering masks.
 * Inserted into patchStandard's options by createStoneMaterial.
 */
export const ORN_VERT_HEAD = /* glsl */ `
attribute vec4 orn;
varying vec4 vOrn;
varying vec3 vEnvNrmW;
`;
export const ORN_VERT_MAIN = /* glsl */ `
vOrn = orn;
vEnvNrmW = normalize(mat3(modelMatrix) * objectNormal);
`;
export const ORN_FRAG_HEAD = /* glsl */ `
uniform sampler2D tOrn, tWeather;
uniform vec4 uOrnK;   // x relief strength, y weathering strength, z moss, w lichen
varying vec4 vOrn;
varying vec3 vEnvNrmW;
vec2 envOrnN;         // tangent-space relief slope (u, v)
float envOrnMask;
`;
// map stage: sample relief + weather, modulate albedo / roughness inputs
export const ORN_MAP = /* glsl */ `
#include <map_fragment>
envOrnN = vec2(0.0);
envOrnMask = 0.0;
float envCav = 1.0;
{
  vec2 ou = vOrn.xy;
  vec2 gx = dFdx(ou), gy = dFdy(ou);
  float cell = floor(vOrn.z + 0.5);
  float amt = vOrn.w * uOrnK.x;
  if (cell > 15.5) { cell -= 16.0; amt *= step(0.0, ou.y) * step(ou.y, 1.0); ou.y = clamp(ou.y, 0.0, 0.999); }
  if (amt > 0.001) {
    if (cell > 14.5) {
      // flutes: concave channels separated by narrow arrises; u counts flutes around the shaft
      float x = fract(ou.x);
      float t = clamp((x - 0.07) / 0.86, 0.0, 1.0) * 2.0 - 1.0;
      float inCh = step(0.07, x) * step(x, 0.93);
      float slope = t / sqrt(max(1.0 - t * t, 0.04));
      // drum joints: a V-chamfer at both ends of every drum (v runs 0..1 up the drum)
      float vj = ou.y;
      float jb = 1.0 - smoothstep(0.0, 0.022, vj), jt = smoothstep(0.978, 1.0, vj);
      envOrnN = vec2(-slope * 0.32 * inCh, (jb - jt) * 0.9);
      envCav = mix(1.0, 0.82 + 0.18 * (1.0 - abs(t)), inCh) * (1.0 - 0.45 * max(jb, jt));
      envCav = 1.0 - (1.0 - envCav) * min(amt, 1.0);
      envOrnN *= min(amt, 1.0);
    } else {
      vec2 cxy = vec2(mod(cell, 4.0), floor(cell / 4.0));
      vec2 auv = (cxy + 0.02 + 0.96 * fract(ou)) / 4.0;
      vec4 o = textureGrad(tOrn, auv, gx * 0.24, gy * 0.24);
      envOrnN = (o.xy * 2.0 - 1.0) * amt;
      envCav = 1.0 - (1.0 - o.a) * min(amt, 1.0);
    }
    envOrnMask = min(amt, 1.0);
  }
}
// weathering (world space box uv): cracks, rain streaks under ledges, lichen rosettes, moss on tops and the base
{
  vec4 W = texture2D(tWeather, vMapUv * 0.42);
  float streakS = texture2D(tWeather, vec2(vMapUv.x * 0.9, vMapUv.y * 0.11)).g;
  vec3 nW = normalize(vEnvNrmW);
  float vert = 1.0 - abs(nW.y);
  float up = smoothstep(0.35, 0.85, nW.y);
  float k = uOrnK.y;
  float crack = W.r * k;
  float streak = smoothstep(0.42, 0.8, streakS) * vert * k;
  float base = 1.0 - smoothstep(0.0, 1.4, vEnvWorld.y);
  float moss = smoothstep(0.5, 0.72, W.a + up * 0.22 + base * 0.18 + (1.0 - envCav) * 0.35) * (up * 0.85 + base * 0.6 + 0.12) * uOrnK.z;
  float lich = W.b * (0.35 + 0.65 * vert) * uOrnK.w * (1.0 - moss);
  diffuseColor.rgb *= envCav * (1.0 - 0.55 * crack) * (1.0 - 0.32 * streak);
  diffuseColor.rgb = mix(diffuseColor.rgb, diffuseColor.rgb * vec3(0.62, 0.7, 0.5) + vec3(0.003, 0.0045, 0.002), clamp(moss, 0.0, 0.8));
  diffuseColor.rgb = mix(diffuseColor.rgb, diffuseColor.rgb * vec3(1.45, 1.42, 1.18) + vec3(0.012, 0.012, 0.008), lich * 0.75);
  envOrnMask = max(envOrnMask, crack * 0.5);
}
`;
// normal stage: apply the relief slope with a derivative tangent frame built on the relief uv
export const ORN_NORMAL = /* glsl */ `
#include <normal_fragment_maps>
vec3 envQ0 = dFdx(-vViewPosition), envQ1 = dFdy(-vViewPosition);
vec2 envSt0 = dFdx(vOrn.xy), envSt1 = dFdy(vOrn.xy);
if (dot(envOrnN, envOrnN) > 1e-6) {
  vec3 q0 = envQ0, q1 = envQ1;
  vec2 st0 = envSt0, st1 = envSt1;
  vec3 N = normal;
  vec3 q1perp = cross(q1, N), q0perp = cross(N, q0);
  vec3 T = q1perp * st0.x + q0perp * st1.x;
  vec3 B = q1perp * st0.y + q0perp * st1.y;
  float lt = length(T), lb = length(B);
  if (lt > 1e-12 && lb > 1e-12) normal = normalize(N + (T / lt) * envOrnN.x + (B / lb) * envOrnN.y);
}
`;
