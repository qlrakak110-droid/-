// Carved and painted detail without geometry: a GPU-baked relief atlas (8 x 4 cells of our own East Asian motifs:
// the black-sun roundel, curling clouds, wave scales, lotus and peony rosettes, lotus-petal bands, thunder meanders,
// tiger stripes, dragon scales, a guardian mask, roof tiles, door lattice, seal-script bands, formation bar groups,
// the brush characters 天 / 武 ...) stored as tangent-space normal + height + cavity, and a tiling weather map
// (cracks, rain streaks, lichen, moss). Materials read the per-vertex `orn` attribute (cell u, v, cell index, relief
// amount) written by Builder({ orn: true }). On the painted timber the same cells drive the faded 단청 colours.
//
//   const orn = bakeOrnament(renderer, 1024)   -> { atlas: WebGLRenderTarget (2:1), weather: WebGLRenderTarget }
//   ORN.<name>                                  cell indices for Builder opts.orn.cell

import * as THREE from 'three';
import { NOISE, GLYPHS } from './glsl.js';
import { bakeTarget } from './bake.js';

const COLS = 8, ROWS = 4;

/** Relief atlas cells (Builder opts.orn.cell). Bands tile along u; tiles repeat in u and v; the rest are single panels. */
export const ORN = {
  sunDisc: 0,     // the black sun: sunk disc, corona ring, flame rays, beaded frame (the sect's emblem)
  cloud: 1,       // band of curling clouds (운문), tiles along u
  wave: 2,        // wave scales: overlapping arcs with concentric ridges (tiles in u and v)
  lotus: 3,       // lotus rosette: eight pointed petals, eight behind, seed pod
  petal: 4,       // band of upright lotus petals (연판), one per unit u
  meander: 5,     // thunder-pattern band (뇌문): one square spiral per unit u
  peony: 6,       // peony rosette: three rings of ruffled petals
  phases: 7,      // eclipse-phase band: a disc being swallowed, one per unit u
  mask: 8,        // guardian mask (귀면): horned brow, bulging eyes, fanged mouth
  tile: 9,        // roof pan tiles (기와): concave channel across u, tile courses along v
  seal: 10,       // inscription band: three sunk seal-script glyphs of our own per unit u
  panel: 11,      // sunk panel with a raised frame
  scales: 12,     // dragon scales (tiles in u and v)
  lattice: 13,    // door lattice (창살): thin stiles, three groups of rails, torn paper behind; one leaf per unit u, v
  bars: 14,       // formation marks: three groups of three bars (whole / split) per unit u
  tiger: 15,      // tiger-stripe band: tapered wavy stripes, three per unit u
  tian: 16,       // 天 (raised brush character)
  mu: 17,         // 武 (raised brush character)
  dragon: 18,     // dragon band: a scaled body undulating through cloud puffs, one wave per unit u
  cloudPanel: 19, // a single large cloud scroll for wall panels
  studs: 20,      // 4 x 4 domed studs (gate leaves, drum rims)
  rope: 21,       // twisted rope / cord band along u
  crest: 22,      // sect crest: the black sun over three peaks in a ring
  flame: 23,      // band of upright flame tongues, two per unit u
  danHead: 24,    // 단청 beam-end fan: half lotus at u = 0, wave bands toward u = 1
  brocade: 25,    // interlocked-circle brocade (tiles in u and v)
  plank: 26,      // four vertical planks per unit u with gaps and nail heads
  seal2: 27,      // three more seal glyphs
};
/** Panel mode for a cell: relief only where 0 <= v <= 1 (a single motif on part of a face); u still tiles. */
export const panel = (cell) => cell + 32;

const HEIGHT = /* glsl */ `
${NOISE}
${GLYPHS}
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
float line(float d, float w) { return 1.0 - smoothstep(w * 0.6, w, abs(d)); }

// a curling cloud (ruyi head): three lobes with spiral grooves and a tapering tail to the right; p around the head
float cloudCurl(vec2 p, float s, out float groove) {
  p /= s;
  float d = length(p) - 0.17;
  d = smin(d, length(p - vec2(0.2, 0.07)) - 0.13, 0.05);
  d = smin(d, length(p - vec2(-0.17, -0.07)) - 0.11, 0.05);
  d = smin(d, sdSeg(p, vec2(0.1, -0.12), vec2(0.62, -0.26)) - mix(0.085, 0.012, clamp((p.x - 0.1) / 0.52, 0.0, 1.0)), 0.05);
  float a = atan(p.y, p.x);
  float sp = abs(length(p) - (0.06 + 0.035 * a / TAU)) - 0.012;
  vec2 q = p - vec2(0.2, 0.07);
  float sp2 = abs(length(q) - 0.065) - 0.011;
  groove = max(1.0 - smoothstep(0.0, 0.012, sp), (1.0 - smoothstep(0.0, 0.012, sp2)) * step(q.y, 0.03));
  groove *= step(d, -0.02);
  return d * s;
}

float cellHeight(int id, vec2 c, out float dark) {
  dark = 0.0;
  float h = 0.3;
  vec2 q = c - 0.5;
  float r = length(q) * 2.0;
  float a = atan(q.y, q.x);
  if (id == 0) { // black-sun roundel
    float frame = bump(abs(r - 0.91) - 0.05, 0.04);
    float beads = bump(length(vec2(fract(a / TAU * 36.0) - 0.5, (r - 0.8) * 9.0)) - 0.32, 0.18) * step(abs(r - 0.8), 0.05);
    // flame rays: twelve tongues leaning one way, alternately long and short
    float k = a / TAU * 12.0 + (r - 0.45) * 0.9;
    float tng = abs(fract(k) - 0.5) * 2.0;
    float len = mod(floor(k), 2.0) < 0.5 ? 0.76 : 0.66;
    float rw = mix(0.42, 0.02, clamp((r - 0.5) / (len - 0.5), 0.0, 1.0));
    float rays = bump(tng - rw, 0.14) * step(0.5, r) * step(r, len);
    float corona = bump(abs(r - 0.43) - 0.06, 0.04);
    h = 0.3 + max(max(frame * 0.6, beads * 0.55), max(rays * 0.5, corona * 0.65));
    float disc = 1.0 - smoothstep(0.33, 0.36, r);
    h = mix(h, 0.02, disc);
    dark = disc;
  } else if (id == 1) { // cloud band
    float g1, g2;
    float d1 = cloudCurl(c - vec2(0.27, 0.58), 0.9, g1);
    float d2 = cloudCurl(vec2(0.93 - c.x, 0.9 - c.y) - vec2(0.2, 0.52), 0.62, g2);
    h = 0.28 + max(bump(d1, 0.05) * 0.6 - g1 * 0.22, bump(d2, 0.04) * 0.5 - g2 * 0.2);
    h = max(h, 0.28 + fillets(c) * 0.6);
  } else if (id == 2) { // wave scales
    vec2 s = vec2(c.x * 2.0 + 0.5 * step(0.5, fract(c.y * 2.0)), fract(c.y * 2.0));
    vec2 f = vec2(fract(s.x) - 0.5, s.y);
    float sc = length(f * vec2(1.0, 1.25)) - 0.5;
    float rings = 0.5 + 0.5 * cos(length(f * vec2(1.0, 1.25)) * 44.0);
    h = 0.25 + bump(sc, 0.3) * 0.3 * (1.0 - 0.5 * s.y) + rings * 0.28 * step(sc, 0.0);
    dark = (1.0 - smoothstep(0.0, 0.03, abs(sc))) * 0.5;
  } else if (id == 3) { // lotus rosette
    float t = fract(a / TAU * 8.0) - 0.5;
    float t2 = fract(a / TAU * 8.0 + 0.5) - 0.5;
    float e1 = 0.9 * (0.66 + 0.34 * (1.0 - pow(abs(2.0 * t), 1.5)));
    float e2 = 0.58 * (0.7 + 0.3 * (1.0 - pow(abs(2.0 * t2), 1.5)));
    float p1 = bump(r - e1, 0.22) * (0.55 + 0.25 * (1.0 - abs(2.0 * t)));
    float p2 = bump(r - e2, 0.18) * (0.75 + 0.2 * (1.0 - abs(2.0 * t2)));
    float crease = (1.0 - smoothstep(0.0, 0.05, 0.5 - abs(t))) * step(r, e1) * step(0.58, r);
    h = 0.24 + max(p1 * 0.6 - crease * 0.2, p2 * 0.62 * step(r, 0.62));
    float rib = (1.0 - smoothstep(0.0, 0.03, abs(t) * r)) * step(0.62, r) * step(r, e1 - 0.05);
    h -= rib * 0.07;
    float pod = bump(r - 0.2, 0.06);
    float seeds = bump(length(vec2(fract(a / TAU * 6.0) - 0.5, (r - 0.115) * 6.0)) - 0.28, 0.1) * step(abs(r - 0.115), 0.05);
    h = max(h, 0.24 + pod * 0.5 + seeds * 0.2);
  } else if (id == 4) { // upright lotus petals
    float yy = clamp(c.y / 0.93, 0.0, 1.0);
    float w = 0.47 * pow(max(sin(yy * 3.14159), 0.0), 0.62) * (1.0 - 0.34 * yy);
    float d = abs(c.x - 0.5) - w;
    d = max(d, c.y - 0.93);
    // the petal behind, seen between two front petals
    float xb = min(c.x, 1.0 - c.x);
    float yb = clamp(c.y / 0.98, 0.0, 1.0);
    float db = xb - 0.3 * pow(max(sin(yb * 3.14159), 0.0), 0.7) * (1.0 - 0.4 * yb);
    h = 0.2 + bump(db, 0.1) * 0.32;
    float front = bump(d, 0.14) * (0.62 + 0.2 * yy);
    float inner = line(d + 0.075, 0.016) * step(d, -0.03);
    float rib = (1.0 - smoothstep(0.0, 0.02, abs(c.x - 0.5))) * step(d, -0.04) * step(c.y, 0.8);
    h = max(h, 0.2 + front - inner * 0.13 - rib * 0.08);
    dark = (1.0 - smoothstep(0.0, 0.025, abs(d))) * 0.4;
  } else if (id == 5) { // thunder meander
    float d = sdSeg(c, vec2(-0.1, 0.2), vec2(0.86, 0.2));
    d = min(d, sdSeg(c, vec2(0.86, 0.2), vec2(0.86, 0.8)));
    d = min(d, sdSeg(c, vec2(0.86, 0.8), vec2(0.14, 0.8)));
    d = min(d, sdSeg(c, vec2(0.14, 0.8), vec2(0.14, 0.41)));
    d = min(d, sdSeg(c, vec2(0.14, 0.41), vec2(0.62, 0.41)));
    d = min(d, sdSeg(c, vec2(0.62, 0.41), vec2(0.62, 0.61)));
    d = min(d, sdSeg(c, vec2(0.62, 0.61), vec2(0.38, 0.61)));
    d = min(d, sdSeg(c, vec2(1.0, 0.2), vec2(1.1, 0.2)));
    h = 0.28 + bump(d - 0.05, 0.03) * 0.55;
    h = max(h, 0.28 + fillets(c) * 0.6);
  } else if (id == 6) { // peony rosette
    h = 0.22;
    float e3 = 0.9 * (1.0 + 0.1 * cos(a * 7.0 + 0.4) + 0.05 * cos(a * 21.0));
    float e2 = 0.62 * (1.0 + 0.12 * cos(a * 6.0 + 1.9) + 0.06 * cos(a * 18.0 + 0.7));
    float e1 = 0.36 * (1.0 + 0.14 * cos(a * 5.0 + 3.1) + 0.07 * cos(a * 15.0));
    h += bump(r - e3, 0.2) * 0.26 + bump(r - e2, 0.16) * 0.22 + bump(r - e1, 0.12) * 0.2;
    float cr3 = 1.0 - smoothstep(0.0, 0.08, abs(fract(a / TAU * 7.0 + 0.06) - 0.5) * 2.0 - 0.0);
    h -= cr3 * 0.1 * step(e2, r) * step(r, e3);
    float cr2 = 1.0 - smoothstep(0.0, 0.1, abs(fract(a / TAU * 6.0 + 0.3) - 0.5) * 2.0);
    h -= cr2 * 0.1 * step(e1, r) * step(r, e2);
    h += bump(r - 0.12, 0.05) * 0.12;
    dark = (1.0 - smoothstep(0.0, 0.03, min(abs(r - e2), abs(r - e1)))) * 0.35;
  } else if (id == 7) { // eclipse phases
    float disc = length(c - vec2(0.5, 0.5)) - 0.27;
    float bite = length(c - vec2(0.62, 0.56)) - 0.24;
    h = 0.3 + bump(disc, 0.05) * 0.55;
    float sw = (1.0 - smoothstep(-0.01, 0.01, bite)) * step(disc, 0.0);
    h = mix(h, 0.12, sw);
    dark = sw;
    h = max(h, 0.3 + fillets(c) * 0.6);
  } else if (id == 8) { // guardian mask
    vec2 p = vec2(abs(q.x), q.y);
    float face = sdTrap(q - vec2(0.0, -0.02), 0.27, 0.36, 0.3) - 0.07;
    h = 0.2 + bump(face, 0.1) * 0.5;
    // brow: a heavy V ridge, horns curling up from its ends
    float brow = sdSeg(p, vec2(0.0, 0.1), vec2(0.3, 0.22)) - 0.055;
    float horn = sdSeg(p, vec2(0.26, 0.26), vec2(0.36, 0.43)) - mix(0.05, 0.012, clamp((q.y - 0.26) / 0.17, 0.0, 1.0));
    h = max(h, 0.2 + bump(min(brow, horn), 0.04) * 0.78);
    // eyes: bulging, a sunk pupil
    float eye = length((p - vec2(0.15, 0.04)) / vec2(1.2, 1.0)) - 0.075;
    h = max(h, 0.2 + bump(eye, 0.05) * 0.72);
    float pupil = 1.0 - smoothstep(0.02, 0.032, length(p - vec2(0.15, 0.035)));
    h -= pupil * 0.4; dark = pupil;
    // nose: a broad wedge; mouth: a wide slot with four fangs
    float nose = sdTrap(q - vec2(0.0, -0.06), 0.085, 0.04, 0.09);
    h = max(h, 0.2 + bump(nose, 0.05) * 0.74);
    float mouth = sdBox(q - vec2(0.0, -0.235), vec2(0.21, 0.05)) - 0.02;
    float mm = 1.0 - smoothstep(-0.01, 0.01, mouth);
    float fang = min(sdTrap(vec2(p.x - 0.075, -(q.y + 0.215)), 0.03, 0.004, 0.045), sdTrap(vec2(p.x - 0.165, q.y + 0.255), 0.028, 0.004, 0.04));
    h = mix(h, 0.08, mm * step(0.0, fang));
    dark = max(dark, mm * step(0.0, fang));
    // mane: three curls down each cheek
    for (int i = 0; i < 3; i++) {
      vec2 cp = vec2(0.37 + 0.03 * float(i), 0.08 - 0.15 * float(i));
      h = max(h, 0.2 + bump(abs(length(p - cp) - 0.045) - 0.02, 0.02) * 0.55);
    }
  } else if (id == 9) { // roof pan tiles
    float x = abs(c.x - 0.5) * 2.0;
    float v = fract(c.y);
    h = 0.16 + 0.5 * x * x + 0.2 * v;
    float joint = 1.0 - smoothstep(0.0, 0.06, v);
    dark = joint * 0.7;
    h -= joint * 0.1;
  } else if (id == 10 || id == 27) { // seal-script band (sunk strokes)
    float g = floor(c.x * 3.0);
    vec2 p = vec2(fract(c.x * 3.0), (c.y - 0.5) * 1.18 + 0.5);
    p.x = (p.x - 0.5) * 1.18 + 0.5;
    float d = sealGlyph(p, g + (id == 27 ? 11.0 : 0.0) + 3.0);
    float m = 1.0 - smoothstep(-0.004, 0.012, d);
    h = 0.52 - m * 0.42;
    dark = m;
    h = max(h, 0.52 + fillets(c) * 0.4);
  } else if (id == 11) { // sunk panel with a raised frame
    float outer = sdBox(q, vec2(0.46));
    float inner = sdBox(q, vec2(0.36));
    h = 0.45 + bump(outer, 0.03) * 0.35 * (1.0 - bump(inner, 0.04)) - bump(inner, 0.05) * 0.25;
  } else if (id == 12) { // dragon scales
    vec2 s = vec2(c.x * 3.0 + 0.5 * step(0.5, fract(c.y * 2.0)), fract(c.y * 2.0));
    vec2 f = vec2(fract(s.x) - 0.5, s.y);
    float sc = length(f * vec2(1.0, 1.4)) - 0.5;
    h = 0.3 + bump(sc, 0.25) * 0.5 * (0.6 + 0.4 * (1.0 - s.y));
    h -= (1.0 - smoothstep(0.0, 0.03, abs(f.x))) * step(sc, -0.05) * 0.06;
  } else if (id == 13) { // door lattice
    float stile = abs(fract(c.x * 6.0 + 0.5) - 0.5) / 6.0 - 0.014;
    float rail = 1e3;
    for (int i = 0; i < 3; i++) {
      float y0 = 0.16 + 0.34 * float(i);
      for (int k = -1; k <= 1; k++) rail = min(rail, abs(c.y - y0 - float(k) * 0.045) - 0.012);
    }
    float frame = -sdBox(q, vec2(0.47, 0.475));
    float bars = min(min(stile, rail), frame - 0.03);
    float torn = smoothstep(0.52, 0.62, vnoise(c * 5.0 + 3.0) * 0.6 + vnoise(c * 13.0) * 0.4);
    h = 0.24 + 0.05 * vnoise(c * 40.0) - torn * 0.2;
    dark = 0.35 + torn * 0.65;
    float bm = bump(bars, 0.012);
    h = mix(h, 0.8, bm);
    dark *= 1.0 - bm;
  } else if (id == 14) { // formation bar groups
    float g = floor(c.x * 3.0);
    vec2 p = vec2(fract(c.x * 3.0), c.y);
    p.x = (p.x - 0.5) * 1.12 + 0.5;
    float d = barGroup(p, g + 2.0);
    h = 0.3 + bump(d, 0.03) * 0.55;
  } else if (id == 15) { // tiger stripes
    float k = floor(c.x * 3.0);
    float hs = hash12(vec2(k, 7.3));
    float s = c.x * 3.0 + 0.3 * sin(c.y * 5.2 + k * 2.1) + 0.12 * sin(c.y * 13.0 + k);
    float f = abs(fract(s) - 0.5);
    float yy = clamp((c.y - 0.06 - 0.1 * hs) / (0.8 + 0.1 * hs), 0.0, 1.0);
    float w = 0.2 * pow(max(sin(yy * 3.14159), 0.0), 0.8);
    h = 0.3 + bump(f - w, 0.09) * 0.5 * step(0.001, w);
    h = max(h, 0.3 + fillets(c) * 0.6);
  } else if (id == 16 || id == 17) { // brush characters
    vec2 p = (c - 0.5) * 1.06 + 0.5;
    float d = id == 16 ? glyphTian(p) : glyphMu(p);
    d += (vnoise(c * 22.0) - 0.5) * 0.012;
    h = 0.3 + bump(d, 0.035) * 0.58;
  } else if (id == 18) { // dragon band
    float yc = 0.5 + 0.2 * sin(TAU * c.x);
    float slope = 0.2 * TAU * cos(TAU * c.x);
    float d = abs(c.y - yc) / sqrt(1.0 + slope * slope) - 0.12;
    float along = c.x * 9.0;
    float sc = abs(fract(along + abs(c.y - yc) * 3.0) - 0.5);
    h = 0.26 + bump(d, 0.07) * (0.5 + 0.12 * smoothstep(0.1, 0.4, sc));
    // spine fins on the upper edge, belly bands on the lower
    float fin = max(c.y - yc - 0.12 - 0.07 * (1.0 - abs(fract(c.x * 8.0) - 0.5) * 2.0), yc + 0.1 - c.y);
    h = max(h, 0.26 + bump(fin, 0.03) * 0.42);
    float g1;
    h = max(h, 0.26 + bump(cloudCurl(c - vec2(0.2, 0.17), 0.42, g1), 0.03) * 0.36);
    h = max(h, 0.26 + bump(cloudCurl(vec2(0.95 - c.x, c.y) - vec2(0.2, 0.84), 0.42, g1), 0.03) * 0.36);
    h = max(h, 0.26 + fillets(c) * 0.6);
  } else if (id == 19) { // large cloud scroll
    float g1, g2, g3;
    float d1 = cloudCurl(c - vec2(0.36, 0.56), 1.25, g1);
    float d2 = cloudCurl(vec2(1.0 - c.x, c.y) - vec2(0.3, 0.3), 0.8, g2);
    float d3 = cloudCurl(vec2(c.x, 1.0 - c.y) - vec2(0.7, 0.2), 0.6, g3);
    h = 0.26 + max(max(bump(d1, 0.06) * 0.62 - g1 * 0.22, bump(d2, 0.05) * 0.5 - g2 * 0.2), bump(d3, 0.04) * 0.42 - g3 * 0.18);
    h = max(h, 0.26 + bump(abs(sdBox(q, vec2(0.47))) - 0.02, 0.02) * 0.4);
  } else if (id == 20) { // studs
    vec2 f = fract(c * 4.0) - 0.5;
    h = 0.3 + bump(length(f) - 0.26, 0.2) * 0.6;
  } else if (id == 21) { // rope
    float tw = abs(fract(c.x * 4.0 - (c.y - 0.5) * 1.6) - 0.5) * 2.0;
    float body = abs(c.y - 0.5) - 0.34;
    h = 0.2 + bump(body, 0.2) * (0.35 + 0.35 * (1.0 - tw * tw));
    dark = (1.0 - smoothstep(0.0, 0.2, 1.0 - tw)) * step(body, 0.0) * 0.5;
  } else if (id == 22) { // sect crest
    float ring = bump(abs(r - 0.86) - 0.05, 0.035);
    h = 0.3 + ring * 0.55;
    // three peaks
    float pk = min(min(sdTrap(q - vec2(0.0, -0.1), 0.16, 0.012, 0.2), sdTrap(q - vec2(-0.2, -0.17), 0.12, 0.01, 0.13)), sdTrap(q - vec2(0.2, -0.17), 0.12, 0.01, 0.13));
    h = max(h, 0.3 + bump(pk, 0.035) * 0.5);
    float sun = length(q - vec2(0.0, 0.2)) - 0.11;
    h = max(h, 0.3 + bump(abs(sun - 0.035) - 0.017, 0.014) * 0.6);
    float disc = 1.0 - smoothstep(-0.01, 0.005, sun);
    h = mix(h, 0.08, disc);
    dark = disc;
  } else if (id == 23) { // flame band
    float k = floor(c.x * 2.0);
    vec2 p = vec2(fract(c.x * 2.0) - 0.5, c.y);
    p.x += 0.12 * sin(p.y * 4.5 + k * 3.0) * p.y;
    float w = 0.36 * (1.0 - p.y / 0.92) * (0.6 + 0.4 * sin(p.y * 3.14159));
    float d = max(abs(p.x) - w, p.y - 0.92);
    float d2 = max(abs(p.x) - w * 0.45, p.y - 0.6);
    h = 0.26 + bump(d, 0.1) * 0.42 + bump(d2, 0.06) * 0.2;
    h = max(h, 0.26 + bump(0.05 - c.y, 0.02) * 0.5);
  } else if (id == 24) { // beam-end fan
    vec2 p = vec2(c.x * 1.55, c.y - 0.5);
    float rr = length(p) * 2.0, aa = atan(p.y, p.x);
    float t = fract((aa / 3.14159 + 0.5) * 5.0) - 0.5;
    float pod = bump(rr - 0.3, 0.08);
    float pet = bump(rr - 0.86 * (0.7 + 0.3 * (1.0 - pow(abs(2.0 * t), 1.6))), 0.18) * step(0.3, rr);
    h = 0.26 + max(pod * 0.6, pet * 0.5 - (1.0 - smoothstep(0.0, 0.05, 0.5 - abs(t))) * 0.15 * step(rr, 0.8));
    // wave bands beyond the fan
    float wv = sin((c.x - 0.62) * 34.0 + cos(c.y * TAU) * 1.6);
    float band = smoothstep(0.6, 0.66, c.x) * step(1.0, rr);
    h = mix(h, 0.3 + 0.32 * smoothstep(-0.3, 0.3, wv), band);
    h = max(h, 0.26 + fillets(c) * 0.55);
  } else if (id == 25) { // brocade
    vec2 f = fract(c * 3.0) - 0.5;
    float d = min(min(abs(length(f - vec2(0.5, 0.0)) - 0.5), abs(length(f + vec2(0.5, 0.0)) - 0.5)), min(abs(length(f - vec2(0.0, 0.5)) - 0.5), abs(length(f + vec2(0.0, 0.5)) - 0.5)));
    h = 0.3 + bump(d - 0.035, 0.03) * 0.45 + bump(length(f) - 0.09, 0.05) * 0.5;
  } else if (id == 26) { // planks
    float k = floor(c.x * 4.0);
    float f = fract(c.x * 4.0);
    float gap = min(f, 1.0 - f);
    h = 0.5 + (hash12(vec2(k, 3.3)) - 0.5) * 0.1 + (vnoise(vec2(c.x * 60.0, c.y * 3.0)) - 0.5) * 0.06;
    float gm = 1.0 - smoothstep(0.0, 0.05, gap);
    h -= gm * 0.36; dark = gm * 0.8;
    float nail = min(length(vec2((f - 0.5) / 4.0, c.y - 0.08)), length(vec2((f - 0.5) / 4.0, c.y - 0.92))) - 0.022;
    h = max(h, 0.5 + bump(nail, 0.02) * 0.35);
  }
  return h;
}

vec4 sampleCell(vec2 uv) {
  vec2 grid = vec2(${COLS}.0, ${ROWS}.0);
  vec2 cellF = floor(uv * grid);
  int id = int(cellF.y * grid.x + cellF.x);
  vec2 c = fract(uv * grid);
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
  vec2 grid = vec2(${COLS}.0, ${ROWS}.0);
  vec2 cell = floor(vUv * grid);
  vec2 lo = (cell + 0.5 * uTexel * grid) / grid, hi = (cell + 1.0 - 0.5 * uTexel * grid) / grid;
  float hx1 = texture2D(tH, clamp(vUv + vec2(uTexel.x, 0.0), lo, hi)).r, hx0 = texture2D(tH, clamp(vUv - vec2(uTexel.x, 0.0), lo, hi)).r;
  float hy1 = texture2D(tH, clamp(vUv + vec2(0.0, uTexel.y), lo, hi)).r, hy0 = texture2D(tH, clamp(vUv - vec2(0.0, uTexel.y), lo, hi)).r;
  vec4 c = texture2D(tH, vUv);
  // relief depth: ~1/7 of the cell width at height 1
  float k = 0.145 / (2.0 * uTexel.y * ${ROWS}.0);
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
 * Bake the relief atlas (2 * `size` x `size`, 8 x 4 cells) and the tiling weather map.
 * @returns {{atlas: THREE.WebGLRenderTarget, weather: THREE.WebGLRenderTarget}}
 */
export function bakeOrnament(renderer, size = 1024) {
  const w = size * 2, hgt = size;
  const texel = new THREE.Vector2(1 / w, 1 / hgt);
  const h = bakeTarget(renderer, { width: w, height: hgt, frag: HEIGHT, mipmaps: false, float: true });
  const atlas = bakeTarget(renderer, { width: w, height: hgt, frag: NORMAL, uniforms: { tH: { value: h.texture }, uTexel: { value: texel } } });
  h.dispose();
  const ws = Math.max(256, size >> 1);
  const weather = bakeTarget(renderer, { width: ws, frag: WEATHER, uniforms: { uTexel: { value: new THREE.Vector2(1 / ws, 1 / ws) } }, repeat: true });
  return { atlas, weather };
}

/**
 * Material patch chunks: relief from the atlas, cavity darkening and weathering. Inserted into patchStandard's
 * options by the material factories (materials.js). `ornMap(kind)`: 'stone' | 'timber' | 'metal'.
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
uniform vec3 uPaintA, uPaintB, uPaintC, uBare;  // timber: 단청 accents (ochre line, red, jade) and the bare wood under the paint
varying vec4 vOrn;
varying vec3 vEnvNrmW;
vec2 envOrnN;         // tangent-space relief slope (u, v)
float envOrnMask;
float envRoughK;      // roughness multiplier from the surface condition
`;

const SAMPLE = /* glsl */ `
envOrnN = vec2(0.0);
envOrnMask = 0.0;
envRoughK = 1.0;
float envCav = 1.0;
float envH = 0.0;     // relief height where a motif is carved (0 elsewhere)
float envPaint = 0.0; // > 0: the motif is painted
{
  vec2 ou = vOrn.xy;
  vec2 gx = dFdx(ou), gy = dFdy(ou);
  float cell = floor(vOrn.z + 0.5);
  float amt = abs(vOrn.w) * uOrnK.x;
  if (cell > 31.5) { cell -= 32.0; amt *= step(0.0, ou.y) * step(ou.y, 1.0); ou.y = clamp(ou.y, 0.0, 0.999); }
  if (amt > 0.001) {
    vec2 grid = vec2(${COLS}.0, ${ROWS}.0);
    vec2 cxy = vec2(mod(cell, grid.x), floor(cell / grid.x));
    vec2 auv = (cxy + 0.02 + 0.96 * fract(ou)) / grid;
    vec4 o = textureGrad(tOrn, auv, gx * 0.96 / grid, gy * 0.96 / grid);
    envOrnN = (o.xy * 2.0 - 1.0) * amt;
    envCav = 1.0 - (1.0 - o.a) * min(amt, 1.0);
    envOrnMask = min(amt, 1.0);
    envH = o.b;
    envPaint = step(0.0, vOrn.w) * envOrnMask;
  }
}
`;

/**
 * Albedo-stage chunk: sample relief + weather and modulate the albedo. The stone chunk replaces `map_fragment`;
 * the timber and metal chunks replace `color_fragment` (they need the vertex colour applied first).
 * @param {'stone'|'timber'|'metal'} kind
 */
export function ornMap(kind) {
  if (kind === 'timber') {
    return /* glsl */ `
#include <color_fragment>
${SAMPLE}
{
  vec3 ground = vColor.rgb;
  float mx = max(ground.r, max(ground.g, ground.b)), mn = min(ground.r, min(ground.g, ground.b));
  float sat = (mx - mn) / max(mx, 1e-4);
  // the detail map's brightness (albedo = vertex colour x map)
  float tv = dot(diffuseColor.rgb, vec3(1.0)) / max(dot(ground, vec3(1.0)), 1e-4);
  // 단청: raised lines in ochre, the motif's body in the complement of the ground (red on jade, jade on red)
  if (envPaint > 0.0) {
    vec3 body = ground.r > ground.g * 1.4 ? uPaintC : uPaintB;
    float mB = smoothstep(0.36, 0.46, envH), mA = smoothstep(0.64, 0.74, envH);
    vec3 p = mix(ground, body, mB * 0.85);
    p = mix(p, uPaintA, mA * 0.9);
    diffuseColor.rgb = mix(diffuseColor.rgb, p * tv, envPaint);
  }
  // weather: checks along the grain, water stains, paint flaking off to grey wood, moss on tops
  vec4 W = texture2D(tWeather, vMapUv * vec2(0.9, 0.2));
  vec4 W2 = texture2D(tWeather, vMapUv * 0.37 + 0.31);
  vec3 nW = normalize(vEnvNrmW);
  float up = smoothstep(0.35, 0.85, nW.y);
  float k = uOrnK.y;
  float crack = W.r * k;
  float flake = smoothstep(0.6, 0.78, W2.a * 0.75 + W2.b * 0.5 + W.g * 0.22 + (1.0 - smoothstep(0.0, 1.2, vEnvWorld.y - 1.44)) * 0.12) * smoothstep(0.12, 0.4, max(sat, envPaint * 0.6)) * uOrnK.w;
  vec3 bare = uBare * tv * (0.7 + 0.6 * W.g);
  diffuseColor.rgb = mix(diffuseColor.rgb, bare, flake * 0.85);
  diffuseColor.rgb *= envCav * (1.0 - 0.6 * crack) * (0.78 + 0.22 * smoothstep(0.3, 0.7, W.g));
  float moss = smoothstep(0.5, 0.7, W2.a + up * 0.2) * up * uOrnK.z;
  diffuseColor.rgb = mix(diffuseColor.rgb, diffuseColor.rgb * vec3(0.6, 0.7, 0.5) + vec3(0.002, 0.004, 0.002), clamp(moss, 0.0, 0.75));
  envRoughK = mix(0.86, 1.2, max(flake, moss));
  envOrnN *= 0.55 + 0.45 * (1.0 - envPaint);
  envOrnMask = max(envOrnMask, crack * 0.5);
}
`;
  }
  if (kind === 'metal') {
    return /* glsl */ `
#include <color_fragment>
${SAMPLE}
{
  // bronze / iron: verdigris or rust creeping out of the recesses and down the flanks
  vec4 W = texture2D(tWeather, vMapUv * 0.9);
  float streakS = texture2D(tWeather, vec2(vMapUv.x * 1.6, vMapUv.y * 0.2)).g;
  vec3 nW = normalize(vEnvNrmW);
  float vert = 1.0 - abs(nW.y);
  float pat = smoothstep(0.42, 0.7, W.a * 0.7 + W.b * 0.6 + (1.0 - envCav) * 0.7 + smoothstep(0.45, 0.8, streakS) * vert * 0.4) * uOrnK.y;
  float bronze = step(vColor.g * 1.2, vColor.r);
  float tv = dot(diffuseColor.rgb, vec3(1.0)) / max(dot(vColor.rgb, vec3(1.0)), 1e-4);
  diffuseColor.rgb *= envCav;
  vec3 patina = mix(vec3(0.07, 0.034, 0.02), vec3(0.03, 0.072, 0.06), bronze) * tv;
  diffuseColor.rgb = mix(diffuseColor.rgb, patina * (0.7 + 0.6 * W.g), pat * 0.85);
  envRoughK = mix(1.0, 1.9, pat);
  envOrnMask = pat;   // lowers the metalness where the surface has corroded
}
`;
  }
  return /* glsl */ `
#include <map_fragment>
${SAMPLE}
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
}
/** Kept for older imports: the stone map chunk. */
export const ORN_MAP = ornMap('stone');

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
