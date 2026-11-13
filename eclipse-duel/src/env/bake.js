// One-time GPU texture baking: a fragment shader is rendered into a render target (with mipmaps) at start-up.
// Much faster than per-pixel canvas loops on phones, and still fully procedural.
//
//   bakeFloor(renderer, size)   -> { a, b }   arena floor maps covering [-E, E]^2 (E = LAYOUT.floorTexExtent)
//                                  a: sRGB albedo + puddle mask (alpha), b: linear normal.xz / roughness / metalness
//   bakeStone(renderer, size)   -> { a, b }   tiling stone detail: sRGB albedo variation, linear normal + cavity
//   bakeBanner(renderer)        -> target     cloth atlas (CLOTH regions): sRGB colour, alpha = tattered coverage
//   bakeFoliage(renderer)       -> target     foliage atlas (FOLIAGE cells): grey value, alpha = coverage
//   bakeWood(renderer, size)    -> { a, b }   tiling timber detail (grain along v)

import * as THREE from 'three';
import { NOISE, GLYPHS } from './glsl.js';
import { LAYOUT, IMPACT } from './config.js';

const DEG = Math.PI / 180;
/** brazier floor positions as GLSL vec2 constants (ash spilled around their bases) */
const BRAZ_GLSL = LAYOUT.braziers.map(([d, r]) => `vec2(${(r * Math.sin(d * DEG)).toFixed(3)}, ${(-r * Math.cos(d * DEG)).toFixed(3)})`).join(', ');

const VERT = /* glsl */ `varying vec2 vUv; void main() { vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }`;

let fsGeo = null;
function fullscreen() {
  if (!fsGeo) {
    fsGeo = new THREE.BufferGeometry();
    fsGeo.setAttribute('position', new THREE.BufferAttribute(new Float32Array([-1, -1, 0, 3, -1, 0, -1, 3, 0]), 3));
    fsGeo.setAttribute('uv', new THREE.BufferAttribute(new Float32Array([0, 0, 2, 0, 0, 2]), 2));
  }
  return fsGeo;
}

/** Free the bake pass's fullscreen triangle once an environment has finished baking (rebuilt on the next bake). */
export function releaseBakeQuad() {
  if (fsGeo) { fsGeo.dispose(); fsGeo = null; }
}

/**
 * Render `frag` into a new RGBA8 render target.
 * @returns {THREE.WebGLRenderTarget}
 */
export function bakeTarget(renderer, { width, height = width, frag, uniforms = {}, srgb = false, mipmaps = true, repeat = false, float = false, defines = {} }) {
  const rt = new THREE.WebGLRenderTarget(width, height, {
    type: float ? THREE.HalfFloatType : THREE.UnsignedByteType,
    format: THREE.RGBAFormat,
    colorSpace: srgb ? THREE.SRGBColorSpace : THREE.NoColorSpace,
    generateMipmaps: mipmaps,
    minFilter: mipmaps ? THREE.LinearMipmapLinearFilter : THREE.LinearFilter,
    magFilter: THREE.LinearFilter,
    wrapS: repeat ? THREE.RepeatWrapping : THREE.ClampToEdgeWrapping,
    wrapT: repeat ? THREE.RepeatWrapping : THREE.ClampToEdgeWrapping,
    anisotropy: Math.min(8, renderer.capabilities.getMaxAnisotropy()),
    depthBuffer: false,
  });
  const mat = new THREE.ShaderMaterial({ vertexShader: VERT, fragmentShader: frag, uniforms, defines, depthTest: false, depthWrite: false });
  const mesh = new THREE.Mesh(fullscreen(), mat);
  mesh.frustumCulled = false;
  const scene = new THREE.Scene();
  scene.add(mesh);
  const cam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
  const prev = renderer.getRenderTarget();
  renderer.setRenderTarget(rt);
  renderer.render(scene, cam);
  renderer.setRenderTarget(prev);
  mat.dispose();
  return rt;
}

// ---------------------------------------------------------------------------------------------------------------------
// Floor: the terrace's formation diagram (진법도). From the centre: the black-sun disc, a bronze limb and an engraved
// corona; a ring of eight formation marks (three stacked bars each: whole, split in two, split in three) with star
// studs between them; a star chart (studs joined by engraved lines); a band of our own seal script; an outer ring of
// sixteen marks; flagstone rows between, a gutter at the wall. On top of it: wear along the fight line, damp hollows
// and puddles, settlement cracks, the scars of an older duel (a crater, long crescent blade gashes, stamped
// footprints, scorch blooms) and the stones breaking up toward the fallen rim.
// ---------------------------------------------------------------------------------------------------------------------
const FLOOR_FIELD = /* glsl */ `
${NOISE}
${GLYPHS}
uniform float uExtent;
uniform vec2 uTexel;
varying vec2 vUv;
const float TAU = 6.28318530718;

// distance to the nearest cell edge; cell receives the nearest cell's integer id
float voronoiCell(vec2 x, out vec2 cell) {
  vec2 n = floor(x), f = fract(x), mg = vec2(0.0), mr = vec2(0.0);
  float md = 8.0;
  for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
    vec2 g = vec2(float(i), float(j)); vec2 r = g + hash22(n + g) - f; float d = dot(r, r);
    if (d < md) { md = d; mr = r; mg = g; }
  }
  md = 8.0;
  for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
    vec2 g = mg + vec2(float(i), float(j)); vec2 r = g + hash22(n + g) - f;
    if (dot(mr - r, mr - r) > 1e-5) md = min(md, dot(0.5 * (mr + r), normalize(r - mr)));
  }
  cell = n + mg;
  return md;
}
float voronoiEdge(vec2 x) { vec2 c; return voronoiCell(x, c); }

// an old impact behind the fight line, left of centre (where a palm of inner force once struck): centre, radius
const vec3 IMPACT = vec3(${IMPACT[0].toFixed(2)}, ${IMPACT[1].toFixed(2)}, ${IMPACT[2].toFixed(2)});

// the broken rim across the vista: the same curve as rimR() in config.js (theta from -Z toward +X)
float rimRadius(vec2 p) {
  float th = atan(p.x, -p.y);
  float a = abs(th);
  float g = ${LAYOUT.gap.toFixed(5)};
  if (a >= g + 0.05236) return ${LAYOUT.floorR.toFixed(2)};
  float k = 1.0 - clamp((a - (g - 0.08727)) / 0.13963, 0.0, 1.0);
  float s = k * k * (3.0 - 2.0 * k);
  float n = 0.5 + 0.5 * sin(th * 23.0 + 1.3) * sin(th * 9.7 + 0.4) + 0.35 * sin(th * 61.0 + 2.1);
  float big = 0.5 + 0.5 * sin(th * 5.3 + 0.9);
  return ${LAYOUT.floorR.toFixed(2)} - s * (0.35 + 0.75 * big + 0.42 * max(0.0, n));
}

// deliberate puddles (x, z, radius): in front of the fight line so fighters / VFX reflect, and behind it
float blobs(vec2 p) {
  float s = 0.0;
  s += smoothstep(1.0, 0.2, length((p - vec2(-3.6, 2.3)) / vec2(1.5, 0.9)));
  s += smoothstep(1.0, 0.2, length((p - vec2(1.4, 3.3)) / vec2(1.8, 0.8)));
  s += smoothstep(1.0, 0.2, length((p - vec2(5.6, 1.8)) / vec2(1.3, 0.8)));
  s += smoothstep(1.0, 0.2, length((p - vec2(-6.8, 3.6)) / vec2(1.4, 1.0)));
  s += smoothstep(1.0, 0.2, length((p - vec2(-0.6, 1.9)) / vec2(0.9, 0.55)));
  s += smoothstep(1.0, 0.2, length((p - vec2(-1.8, -3.4)) / vec2(2.2, 1.2)));
  s += smoothstep(1.0, 0.2, length((p - vec2(3.8, -5.6)) / vec2(2.4, 1.3)));
  s += smoothstep(1.0, 0.2, length((p - vec2(-5.5, -7.8)) / vec2(2.6, 1.4)));
  s += smoothstep(1.0, 0.2, length((p - vec2(1.2, -9.6)) / vec2(3.0, 1.5)));
  s += smoothstep(1.0, 0.2, length((p - vec2(7.8, -2.2)) / vec2(1.6, 1.2)));
  // the south half (seen in the action-RPG mode): by the gate stairs and in front of the hall
  s += smoothstep(1.0, 0.2, length((p - vec2(2.6, 9.4)) / vec2(2.2, 1.3)));
  s += smoothstep(1.0, 0.2, length((p - vec2(-4.8, 11.2)) / vec2(1.9, 1.2)));
  s += smoothstep(1.0, 0.2, length((p - vec2(-10.6, 4.4)) / vec2(1.4, 1.8)));
  s += smoothstep(1.0, 0.2, length((p - vec2(9.6, 7.2)) / vec2(1.7, 1.2)));
  return s;
}

struct Fl { float h; vec3 alb; float rough; float metal; float puddle; };

// small weathered blade nicks scattered over the floor (a few in threes), tapering at both ends
float gouges(vec2 p, out float lip) {
  float g = 0.0; lip = 0.0;
  vec2 cell = floor(p / 2.3);
  for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
    vec2 c = cell + vec2(float(i), float(j));
    float hs = hash12(c * 1.37 + 4.1);
    if (hs > 0.3) continue;
    vec2 o = (c + hash22(c + 2.7)) * 2.3;
    float ang = hash12(c + 9.3) * 6.2832;
    vec2 d = vec2(cos(ang), sin(ang));
    float len = mix(0.35, 0.85, hash12(c + 1.9));
    int n = hs < 0.06 ? 3 : 1;
    for (int k = 0; k < 3; k++) {
      if (k >= n) break;
      vec2 q = p - o - vec2(-d.y, d.x) * (float(k) - float(n - 1) * 0.5) * 0.1;
      float t = clamp(dot(q, d) / len, -1.0, 1.0);
      float along = 1.0 - t * t;
      float dist = length(q - d * t * len);
      float w = 0.008 + 0.012 * along;
      g = max(g, (1.0 - smoothstep(0.0, w, dist)) * along);
      lip = max(lip, smoothstep(w * 3.0, w, dist) * smoothstep(w * 0.8, w * 1.4, dist) * along);
    }
  }
  return g;
}
// a long crescent gash left by blade energy: an arc of radius R about c from angle a0 to a1; returns the groove
// (1 in the cut), lip = the chipped shoulder beside it; the cut is deepest in the middle and feathers out
float gash(vec2 p, vec2 c, float R, float a0, float a1, float wid, out float lip) {
  vec2 q = p - c;
  float a = atan(q.y, q.x);
  float t = clamp((a - a0) / (a1 - a0), 0.0, 1.0);
  float aa = mix(a0, a1, t);
  float dist = length(q - R * vec2(cos(aa), sin(aa)));
  float along = sin(t * 3.14159);
  float w = wid * (0.25 + 0.75 * along) * (0.8 + 0.4 * vnoise(p * 9.0));
  lip = smoothstep(w * 3.4, w * 1.2, dist) * smoothstep(w * 0.7, w * 1.3, dist) * along;
  return (1.0 - smoothstep(w * 0.45, w, dist)) * smoothstep(0.0, 0.08, along);
}
// three stacked bars centred on the origin (a formation mark): bar k is whole, split in two or split in three
float bars3(vec2 p, float id, float hl, float ht, float pt) {
  float d = 1e3;
  for (int k = 0; k < 3; k++) {
    float y = (float(k) - 1.0) * pt;
    float kind = floor(hash12(vec2(id * 1.31 + 0.7, float(k) * 3.7 + 2.1)) * 3.0);
    float x = abs(p.x), dx;
    if (kind < 0.5) dx = x - hl;
    else if (kind < 1.5) dx = max(x - hl, hl * 0.14 - x);
    else dx = min(x - hl * 0.25, max(x - hl, hl * 0.46 - x));
    vec2 e = vec2(dx, abs(p.y - y) - ht);
    d = min(d, length(max(e, 0.0)) + min(max(e.x, e.y), 0.0));
  }
  return d;
}
// star chart: 24 studs in six constellations between r = 5.2 and 7.7; returns the distance to the nearest stud
// and writes the distance to the nearest joining line
float starChart(vec2 p, out float lineD) {
  float d = 1e3; lineD = 1e3;
  for (int g = 0; g < 6; g++) {
    vec2 prev = vec2(0.0);
    for (int j = 0; j < 4; j++) {
      float id = float(g) * 4.0 + float(j);
      float ang = (float(g) + 0.5) / 6.0 * TAU + 0.31 + (float(j) - 1.5) * 0.2 + (hash12(vec2(id, 3.1)) - 0.5) * 0.14;
      float rr = 5.25 + 2.4 * hash12(vec2(id, 8.7));
      vec2 s = rr * vec2(cos(ang), sin(ang));
      d = min(d, length(p - s));
      if (j > 0) { vec2 pa = p - prev, ba = s - prev; lineD = min(lineD, length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0))); }
      prev = s;
    }
  }
  return d;
}
const vec2 BRAZ[4] = vec2[4](${BRAZ_GLSL});

Fl floorField(vec2 p) {
  Fl o;
  float r0 = length(p);
  float a0 = atan(p.y, p.x);
  float aaw = 2.0 * uExtent * uTexel.x; // one texel in metres
  // irregular joints: wobble the polar coordinates a little
  float r = r0 + (vnoise(p * 2.3) - 0.5) * 0.045;
  float a = a0 + (vnoise(p * 2.1 + 5.0) - 0.5) * 0.04 / max(r0, 0.5);
  float an = a / TAU + 0.5;
  float an0 = a0 / TAU + 0.5;

  // 0 stone rows, 1 bronze ring, 2 seal band, 3 black-sun disc, 4 gutter, 5 formation ring, 6 corona band
  float kind = 0.0;
  float ra = 0.0, rb = 1.0, rows = 1.0, sec = 0.0, stoneL = 0.0;
  if (r < 1.18) { kind = 3.0; }
  else if (r < 1.30) { kind = 1.0; }
  else if (r < 2.25) { kind = 6.0; ra = 1.30; rb = 2.25; sec = 1.0; stoneL = 1.4; }
  else if (r < 2.32) { kind = 1.0; }
  else if (r < 3.45) { ra = 2.32; rb = 3.45; rows = 2.0; sec = 2.0; }
  else if (r < 4.55) { kind = 5.0; ra = 3.45; rb = 4.55; sec = 3.0; stoneL = 1.571; }
  else if (r < 4.62) { kind = 1.0; }
  else if (r < 8.14) { ra = 4.62; rb = 8.14; rows = 5.0; sec = 4.0; }
  else if (r < 8.2) { kind = 1.0; }
  else if (r < 9.06) { kind = 2.0; ra = 8.2; rb = 9.06; sec = 5.0; stoneL = 1.57; }
  else if (r < 9.12) { kind = 1.0; }
  else if (r < 12.3) { ra = 9.12; rb = 12.3; rows = 5.0; sec = 6.0; }
  else if (r < 13.3) { kind = 5.0; ra = 12.3; rb = 13.3; sec = 7.0; stoneL = 1.675; }
  else if (r < 13.37) { kind = 1.0; }
  else if (r < 14.65) { ra = 13.37; rb = 14.65; rows = 2.0; sec = 8.0; }
  else { kind = 4.0; ra = 14.65; rb = 16.5; rows = 1.0; sec = 9.0; }

  float w = (rb - ra) / rows;
  float k = floor((r - ra) / w);
  float rr0 = ra + k * w, rr1 = rr0 + w;
  float rowId = sec * 16.0 + k;
  float rmid = 0.5 * (rr0 + rr1);
  float L = stoneL > 0.0 ? stoneL : 0.9 + 0.45 * hash12(vec2(rowId, 3.7));
  float cnt = max(6.0, floor(TAU * rmid / L + 0.5));
  float s = an * cnt + (stoneL > 0.0 ? 0.5 : hash12(vec2(rowId, 9.1)));
  float jm = mod(floor(s), cnt);
  float fs = fract(s);
  float arc = TAU * r / cnt;
  float dj = min(min(r - rr0, rr1 - r), min(fs, 1.0 - fs) * arc);
  vec2 id = vec2(rowId, jm);
  float hs = hash12(id + 0.37), hs2 = hash12(id + 7.13), hs3 = hash12(id + 2.71);
  vec2 lc = vec2(r - rmid, (fs - 0.5) * arc);

  // fight line: stones there are more worn and flatter
  float worn = 1.0 - smoothstep(0.6, 2.2, abs(p.y));
  // the stones break up toward the fallen rim
  float rimD = rimRadius(p) - r0;
  float rimK = (1.0 - smoothstep(0.0, 2.6, rimD)) * step(rimRadius(p), ${(LAYOUT.floorR - 0.02).toFixed(2)});

  // ---- height --------------------------------------------------------------------------------------------------
  float h = (hs - 0.5) * 0.007 * (1.0 - 0.6 * worn) + dot((hash22(id) - 0.5) * 0.014, lc);
  // edge wear: rounded by a different amount on every stone and along each edge, chipped in places
  float edgeN = vnoise(p * 7.0 + hs * 40.0);
  float bev = mix(0.05, 0.2, hs2) * (0.55 + 0.9 * edgeN);
  h += 0.0045 * smoothstep(0.0, bev, dj);
  float chip = smoothstep(0.6, 0.8, vnoise(p * 11.0 + hs3 * 17.0)) * (1.0 - smoothstep(0.0, 0.08, dj));
  h -= 0.011 * (1.0 - smoothstep(0.004, 0.03 + aaw, dj)) + chip * 0.007;
  float grain = fbm2(p * 6.5 + hs * 13.0, 4);
  h += (grain - 0.5) * 0.005 * (1.0 - 0.5 * worn) + (vnoise(p * 34.0) - 0.5) * 0.0012;
  float sunk = step(0.955 - rimK * 0.25, hs2) * step(1.5, kind == 0.0 ? 2.0 : 0.0);
  h -= sunk * (0.022 + 0.012 * fbm2(p * 9.0, 3)) * (1.0 + rimK);
  float ve = voronoiEdge(p * 1.7 + hs * 31.0);
  float crack = (1.0 - smoothstep(0.0, 0.018, ve)) * step(0.62 - rimK * 0.45, hs3) * smoothstep(0.02, 0.06, dj) * (kind == 0.0 || kind == 4.0 ? 1.0 : 0.4);
  crack *= smoothstep(0.35, 0.6, vnoise(p * 1.1 + 4.0) + rimK * 0.5);
  // long settlement cracks that run across many stones (an isoline of warped noise, broken into segments)
  vec2 wq = p * 0.32 + vec2(vnoise(p * 0.9), vnoise(p * 0.9 + 7.7)) * 0.6;
  float iso = abs(fbm2(wq + 31.0, 3) - 0.5);
  float longCrack = (1.0 - smoothstep(0.0, 0.0045 + aaw * 0.08, iso)) * smoothstep(0.5, 0.62, vnoise(p * 0.22 + 9.0) + rimK * 0.3);
  crack = max(crack, longCrack * (1.0 - worn * 0.5));
  // the impact: radial depression, the flagstones shattered into tilted fragments with dark earth in the gaps
  vec2 ip = p - IMPACT.xy;
  float iD = length(ip) + (vnoise(p * 1.4) - 0.5) * 0.9;
  float imp = 1.0 - smoothstep(IMPACT.z * 0.35, IMPACT.z, iD);
  vec2 cellId;
  float fe = voronoiCell(p * 3.4 + 3.3, cellId) / 3.4;
  vec2 ch = hash22(cellId + 0.5);
  float gapW = mix(0.002, 0.016, imp) * (0.6 + 0.8 * ch.x);
  float shard = (1.0 - smoothstep(gapW * 0.5, gapW + aaw * 1.5, fe)) * smoothstep(0.1, 0.35, imp);
  vec2 cc = (cellId + hash22(cellId)) / 3.4 - 3.3 / 3.4;
  h += imp * ((ch.y - 0.5) * 0.016 + dot(ch - 0.5, p - cc) * 0.03) - imp * imp * 0.022;
  h -= shard * 0.02;
  crack = max(crack, shard);
  // long radial fractures running out of the crater, and a ring fracture at its lip
  float iang = atan(ip.y, ip.x);
  float rad = abs(fract(iang / TAU * 13.0 + (vnoise(vec2(iD * 1.3, iang * 2.0)) - 0.5) * 0.35) - 0.5) * TAU * iD / 13.0;
  float radial = (1.0 - smoothstep(0.004, 0.012 + aaw, rad)) * smoothstep(IMPACT.z * 0.5, IMPACT.z * 0.8, iD) * (1.0 - smoothstep(IMPACT.z * 1.3, IMPACT.z * 2.1, iD)) * step(0.35, hash12(vec2(floor(iang / TAU * 13.0 + 0.5), 3.0)));
  float ringF = (1.0 - smoothstep(0.006, 0.016 + aaw, abs(iD - IMPACT.z * 1.04))) * step(0.3, vnoise(vec2(iang * 5.0, 1.0)));
  crack = max(crack, max(radial, ringF));
  // the edge of the broken rim: the last stones tilt outward and split
  h -= rimK * rimK * 0.03 * (0.4 + vnoise(p * 1.9));
  h -= crack * 0.008;

  // ---- albedo ---------------------------------------------------------------------------------------------------
  vec3 stone = vec3(0.056, 0.058, 0.064) * (0.62 + 0.76 * hs);
  stone *= 0.62 + 0.6 * fbm2(p * 0.33 + 1.7, 3);
  stone *= mix(1.0, 0.68, smoothstep(9.0, 14.8, r0));
  stone *= mix(vec3(1.0), vec3(1.09, 1.0, 0.9), hs3);
  stone *= 0.82 + 0.36 * fbm2(p * 2.6 + hs * 9.0, 3);
  float rough = mix(0.88, 0.74, worn) + (grain - 0.5) * 0.16;
  float metal = 0.0;
  // surface condition: damp hollows (dark, satin) and dry dusty stones (pale, matt)
  float damp = smoothstep(0.44, 0.64, fbm2(p * 0.26 + 11.0, 3) + (hs2 - 0.5) * 0.3);
  float dust = smoothstep(0.52, 0.76, fbm2(p * 0.45 + 23.0, 3) + smoothstep(10.5, 15.0, r0) * 0.3 - worn * 0.3) * (1.0 - damp);

  // ---- the diagram: bronze inlay (strip) and engraved lines (engr) ------------------------------------------------
  float strip = 0.0;   // bronze inlay coverage
  float engr = 0.0;    // engraved groove
  float pale = 0.0;    // engraving packed with pale grit (reads light on the dark courses)
  float soft = aaw * 1.2;
  if (kind == 1.0) strip = 1.0;
  if (kind == 3.0) {
    // the black sun: one polished black slab, a hairline ring, nothing else
    float disc = smoothstep(1.16 + soft, 1.16 - soft, r0);
    stone = mix(stone * 0.75, vec3(0.011, 0.0115, 0.013) * (0.8 + 0.4 * fbm2(p * 3.0, 3)), disc);
    rough = mix(rough, 0.24 + 0.2 * fbm2(p * 5.0 + 2.0, 3), disc);
    h = mix(h, 0.003 + (vnoise(p * 20.0) - 0.5) * 0.0006, disc);
    engr = (1.0 - smoothstep(0.012, 0.012 + soft, abs(r0 - 0.62))) * 0.6;
    dj = max(dj, 0.06);
    crack *= 0.5;
  }
  if (kind == 6.0) {
    // the corona: flame tongues radiating from the limb, alternately long and short, leaning one way
    stone *= 0.7; rough -= 0.1;
    float kk = an0 * 24.0 + (r0 - 1.3) * 0.5;
    float tng = abs(fract(kk) - 0.5) * 2.0;
    float len = mod(floor(kk), 2.0) < 0.5 ? 2.2 : 1.9;
    float u = clamp((r0 - 1.33) / (len - 1.33), 0.0, 1.0);
    float wdt = mix(0.6, 0.0, u * u);
    float ray = smoothstep(wdt + 0.12, wdt - 0.02, tng) * step(1.33, r0) * step(r0, len);
    float core = smoothstep(wdt * 0.4 + 0.1, wdt * 0.4 - 0.02, tng) * step(1.33, r0) * step(r0, len - 0.12);
    pale = max(pale, ray - core * 0.6);
    engr = max(engr, core * 0.5);
  }
  if (kind == 5.0) {
    // a ring of formation marks on a dark polished course; star studs sit between the marks
    stone *= 0.64; rough -= 0.12;
    float n = sec < 5.0 ? 8.0 : 16.0;
    float cell = an0 * n + 0.5;
    float gid = mod(floor(cell), n) + sec * 20.0;
    vec2 pm = vec2((fract(cell) - 0.5) * TAU * r0 / n, r0 - 0.5 * (ra + rb));
    float hl = sec < 5.0 ? 1.02 : 1.55, ht = sec < 5.0 ? 0.088 : 0.07, pt = sec < 5.0 ? 0.3 : 0.27;
    float bd = bars3(pm, gid, hl, ht, pt);
    float bar = 1.0 - smoothstep(-soft * 0.5, soft * 0.7, bd);
    pale = max(pale, bar * (sec < 5.0 ? 1.0 : 0.85));
    // the inner ring's marks are edged with bronze; the outer ring's with a cut line
    float edge = 1.0 - smoothstep(0.014, 0.014 + soft, abs(bd - 0.05));
    if (sec < 5.0) strip = max(strip, edge); else engr = max(engr, edge * 0.5);
    // star stud on the cell border: a bronze dome in an engraved ring
    vec2 sm = vec2((abs(fract(cell) - 0.5) - 0.5) * TAU * r0 / n, pm.y);
    float sd = length(sm);
    float stud = 1.0 - smoothstep(0.085 - soft, 0.085 + soft, sd);
    strip = max(strip, stud);
    h += stud * 0.004 * (1.0 - sd / 0.085);
    engr = max(engr, 1.0 - smoothstep(0.012, 0.012 + soft, abs(sd - 0.17)));
  }
  if (kind == 2.0) {
    // the seal band: a dark polished course, our own seal script cut into it and packed with pale grit
    stone *= 0.6; rough -= 0.14;
    float n = 70.0;
    float cell = an0 * n;
    float gid = mod(floor(cell), n);
    vec2 gp = vec2((fract(cell) - 0.5) * TAU * r0 / n / 0.56 + 0.5, (r0 - 8.63) / 0.7 + 0.5);
    float gd = sealGlyph(gp, gid + 40.0) * 0.6;
    float m = 1.0 - smoothstep(-soft * 0.4, soft * 0.8, gd);
    m *= 1.0 - smoothstep(0.5, 0.74, vnoise(p * 1.7 + 3.0));
    pale = max(pale, m * 0.8);
    engr = max(engr, m * 0.35);
  }
  if (kind == 0.0 && sec == 4.0) {
    // the star chart between the inner ring and the seal band
    float lineD;
    float sd = starChart(p, lineD);
    float stud = 1.0 - smoothstep(0.07 - soft, 0.07 + soft, sd);
    strip = max(strip, stud);
    h += stud * 0.003;
    float ln = (1.0 - smoothstep(0.011, 0.011 + soft, lineD)) * smoothstep(0.1, 0.14, sd);
    engr = max(engr, max(ln, 1.0 - smoothstep(0.011, 0.011 + soft, abs(sd - 0.14))));
  }
  if (kind == 0.0 && sec == 6.0) {
    // eight spokes: paired hairlines from the seal band to the outer ring
    float sp = abs(fract(an0 * 8.0 + 0.5) - 0.5) * TAU * r0 / 8.0;
    engr = max(engr, 1.0 - smoothstep(0.011, 0.011 + soft, abs(sp - 0.07)));
  }
  // bronze: worn through in places, verdigris in others
  {
    float gone = smoothstep(0.6, 0.7, vnoise(vec2(an0 * 70.0, r0 * 3.0)) * 0.6 + vnoise(p * 2.2 + 8.0) * 0.4 + rimK * 0.25);
    float verd = smoothstep(0.5, 0.75, fbm2(p * 3.5, 3));
    vec3 bronze = vec3(0.26, 0.17, 0.09);
    vec3 inlay = mix(bronze * (0.6 + 0.5 * grain), vec3(0.045, 0.075, 0.068), verd);
    stone = mix(stone, vec3(0.018), strip * gone);
    h -= strip * (0.0006 + gone * 0.003);
    float live = strip * (1.0 - gone);
    stone = mix(stone, inlay, live);
    metal = live * (1.0 - verd);
    rough = mix(rough, mix(0.36, 0.8, verd), live);
    dj = max(dj, strip * 0.05);
    // engraving: worn shallow on the fight line, full of dirt elsewhere
    float ew = engr * (1.0 - 0.55 * worn) * (1.0 - smoothstep(0.55, 0.8, vnoise(p * 1.3 + 17.0)) * 0.7);
    h -= ew * 0.0045;
    stone = mix(stone, stone * 0.45, ew * 0.8);
    float pw = pale * (1.0 - 0.45 * worn) * (0.55 + 0.45 * vnoise(p * 6.0 + 1.0));
    h -= pw * 0.0025;
    stone = mix(stone, vec3(0.17, 0.16, 0.14) * (0.75 + 0.5 * grain), pw * 0.8);
    rough = mix(rough, 0.9, pw * 0.7);
  }
  if (kind == 4.0) {
    // gutter: big slabs, then a drainage channel against the wall
    float gch = smoothstep(14.98, 15.02, r0) * (1.0 - smoothstep(15.28, 15.32, r0));
    h -= gch * 0.035;
    stone *= mix(1.0, 0.6, gch);
  }

  // dirt in joints (pale grit where it is dry), moss toward the outer rows
  float joint = 1.0 - smoothstep(0.0, 0.028, dj);
  stone = mix(stone, mix(vec3(0.017, 0.016, 0.015), vec3(0.07, 0.066, 0.06), dust), joint * 0.85);
  stone = mix(stone, stone * 0.7, chip * 0.6);
  float mossZone = smoothstep(9.0, 14.5, r0) * 0.7 + 0.3 + rimK * 0.5;
  float moss = smoothstep(0.45, 0.72, fbm2(p * 1.2 + 7.0, 3)) * mossZone * (joint * 0.9 + 0.25 * (1.0 - worn));
  stone = mix(stone, vec3(0.024, 0.032, 0.018), clamp(moss, 0.0, 0.85));
  stone = mix(stone, vec3(0.012), crack * 0.8);
  stone = mix(stone, stone * 0.55 + vec3(0.01), sunk);
  rough = mix(rough, 0.42, joint);

  // ---- puddles ----------------------------------------------------------------------------------------------------
  float zone = clamp((fbm2(p * 0.17 + 3.1, 3) - 0.5) * 3.5, 0.0, 1.0) + blobs(p);
  zone *= 1.0 - 0.75 * (1.0 - smoothstep(0.3, 0.9, abs(p.y)));
  zone *= 1.0 - rimK;
  float level = mix(-0.014, 0.008, clamp(zone, 0.0, 1.0)) + (kind == 4.0 ? 0.012 : 0.0);
  o.puddle = smoothstep(0.0, 0.0035, level - h);
  damp = max(damp, smoothstep(0.15, 0.7, zone) * 0.85);
  dust *= 1.0 - smoothstep(0.1, 0.5, zone);

  // ---- apply the surface condition ---------------------------------------------------------------------------------
  stone = mix(stone, stone * 0.58, damp);
  rough = mix(rough, rough * 0.6, damp);
  stone = mix(stone, vec3(0.1, 0.094, 0.084) * (0.75 + 0.5 * grain), dust * 0.5);
  rough = mix(rough, 0.96, dust);
  // soot around the impact (a wide halo), a fused glassy core, pale ejecta rays beyond the halo, grit in the fractures
  float halo = 1.0 - smoothstep(IMPACT.z * 0.6, IMPACT.z * 1.9, iD + (vnoise(p * 1.7) - 0.5) * 0.8);
  float soot = max(imp, halo * 0.75) * (0.55 + 0.45 * vnoise(p * 3.0));
  stone = mix(stone, stone * 0.4 + vec3(0.003, 0.0028, 0.0025), soot * 0.75);
  float core = 1.0 - smoothstep(IMPACT.z * 0.18, IMPACT.z * 0.42, iD);
  stone = mix(stone, vec3(0.008, 0.0075, 0.008), core * 0.85);
  rough = mix(rough, 0.3, core * 0.8);
  float rays = smoothstep(0.55, 0.85, vnoise(vec2(iang * 7.0, 0.5)) * 0.7 + vnoise(vec2(iang * 23.0, iD * 0.4)) * 0.3);
  rays *= smoothstep(IMPACT.z * 1.0, IMPACT.z * 1.5, iD) * (1.0 - smoothstep(IMPACT.z * 1.8, IMPACT.z * 3.4, iD + vnoise(p * 2.0) * 0.6));
  stone = mix(stone, vec3(0.1, 0.095, 0.088) * (0.8 + 0.4 * grain), rays * 0.6);
  rough = mix(rough, 0.95, rays * 0.6);
  stone = mix(stone, vec3(0.016, 0.013, 0.011), shard * 0.9);
  rough = mix(rough, 0.97, shard);
  // the older duel: scattered nicks, three long crescent gashes of blade energy, two stamped footprints
  float lip, lip2;
  float gg = gouges(p, lip) * (1.0 - smoothstep(10.5, 13.5, r0)) * (1.0 - step(r0, 1.3));
  float cut = gash(p, vec2(0.5, 7.4), 12.6, -2.44, -1.75, 0.05, lip2); lip = max(lip, lip2);
  cut = max(cut, gash(p, vec2(9.2, 2.2), 7.4, -2.93, -2.18, 0.042, lip2)); lip = max(lip, lip2);
  cut = max(cut, gash(p, vec2(-11.5, -4.0), 9.8, 0.42, 1.0, 0.045, lip2)); lip = max(lip, lip2);
  h -= gg * 0.006 + cut * 0.02;
  stone = mix(stone, stone * 0.42, gg * 0.85);
  stone = mix(stone, vec3(0.011, 0.01, 0.01), cut * 0.9);
  stone = mix(stone, stone * 1.3 + vec3(0.006), lip * 0.55);
  rough = mix(rough, 0.95, max(gg * 0.5, cut));
  h += lip * 0.002;
  for (int i = 0; i < 2; i++) {
    // stamped stance (진각): a foot-shaped hollow, the stone crazed around it
    vec2 fc = i == 0 ? vec2(2.35, -2.2) : vec2(3.2, -2.75);
    vec2 fq = mat2(0.88, 0.47, -0.47, 0.88) * (p - fc);
    float fd = length(fq / vec2(0.2, 0.085)) - 1.0 + 0.25 * fq.x / 0.2;
    float foot = 1.0 - smoothstep(-0.3, 0.1, fd);
    h -= foot * 0.014;
    stone = mix(stone, stone * 0.5, foot * 0.7);
    float craze = (1.0 - smoothstep(0.0, 0.02, voronoiEdge(p * 6.0 + 9.0))) * (1.0 - smoothstep(0.1, 3.2, fd)) * step(0.0, fd);
    h -= craze * 0.004;
    stone = mix(stone, vec3(0.012), craze * 0.7);
  }
  float scorch = 0.0;
  scorch = max(scorch, 1.0 - smoothstep(0.2, 1.5, length(p - vec2(5.4, -3.6)) + (vnoise(p * 2.2) - 0.5) * 0.7));
  scorch = max(scorch, 1.0 - smoothstep(0.2, 1.2, length(p - vec2(-7.8, 2.4)) + (vnoise(p * 2.6 + 3.0) - 0.5) * 0.7));
  scorch = max(scorch, (1.0 - smoothstep(0.1, 0.9, length((p - vec2(2.9, 5.6)) * vec2(1.0, 1.8)) + (vnoise(p * 3.0 + 1.0) - 0.5) * 0.5)) * 0.8);
  stone = mix(stone, stone * 0.35 + vec3(0.002), scorch * 0.7);
  rough = mix(rough, 0.97, scorch * 0.5);
  // drifts: dust and fallen needles against the wall base, incense ash spilled around the two censers
  float ashW = smoothstep(13.4, 15.3, r0 + (fbm2(p * 0.7 + 5.0, 3) - 0.5) * 1.8) * smoothstep(0.32, 0.62, fbm2(vec2(p.x * 0.9 - p.y * 0.4, p.y * 2.1 + p.x * 0.5) + 13.0, 3));
  float ashB = 0.0;
  for (int i = 2; i < 4; i++) { vec2 d = p - BRAZ[i]; ashB = max(ashB, exp(-dot(d, d) / 1.1) * (0.6 + 0.4 * vnoise(p * 4.0 + float(i)))); }
  float ash = clamp(ashW + ashB * 0.85 + halo * 0.25 * smoothstep(0.5, 0.8, vnoise(p * 1.4 + 7.0)), 0.0, 1.0) * (1.0 - smoothstep(0.1, 0.5, zone));
  stone = mix(stone, mix(vec3(0.105, 0.1, 0.094), vec3(0.075, 0.062, 0.042), ashW * (1.0 - ashB)) * (0.8 + 0.4 * grain), ash * 0.7);
  rough = mix(rough, 0.97, ash);
  h += ash * 0.0035;
  // raw earth and rubble showing at the very edge of the break
  stone = mix(stone, vec3(0.02, 0.017, 0.014) * (0.7 + 0.6 * grain), smoothstep(0.55, 1.0, rimK) * 0.8);
  rough = mix(rough, 0.95, smoothstep(0.5, 1.0, rimK));

  o.h = h;
  o.alb = stone;
  o.rough = clamp(rough, 0.05, 1.0);
  o.metal = metal;
  return o;
}

vec2 worldP() { return (vUv * 2.0 - 1.0) * uExtent; }
`;

const FLOOR_A = FLOOR_FIELD + /* glsl */ `
void main() {
  Fl f = floorField(worldP());
  gl_FragColor = vec4(f.alb, f.puddle);
}`;
const FLOOR_H = FLOOR_FIELD + /* glsl */ `
void main() {
  Fl f = floorField(worldP());
  gl_FragColor = vec4(f.h, f.rough, f.metal, 1.0);
}`;
const FLOOR_B = /* glsl */ `
uniform sampler2D tH; uniform vec2 uTexel; uniform float uExtent;
varying vec2 vUv;
void main() {
  vec4 c = texture2D(tH, vUv);
  float hx = texture2D(tH, vUv + vec2(uTexel.x, 0.0)).r - texture2D(tH, vUv - vec2(uTexel.x, 0.0)).r;
  float hz = texture2D(tH, vUv + vec2(0.0, uTexel.y)).r - texture2D(tH, vUv - vec2(0.0, uTexel.y)).r;
  float m = 2.0 * uExtent * uTexel.x * 2.0; // metres between the two taps
  vec3 n = normalize(vec3(-hx / m, 1.0, -hz / m));
  gl_FragColor = vec4(n.x * 0.5 + 0.5, n.z * 0.5 + 0.5, c.g, c.b);
}`;

/** Bake the arena floor maps. */
export function bakeFloor(renderer, size) {
  const E = LAYOUT.floorTexExtent;
  const texel = new THREE.Vector2(1 / size, 1 / size);
  const a = bakeTarget(renderer, { width: size, frag: FLOOR_A, uniforms: { uExtent: { value: E }, uTexel: { value: texel } }, srgb: true });
  const hrt = bakeTarget(renderer, { width: size, frag: FLOOR_H, uniforms: { uExtent: { value: E }, uTexel: { value: texel } }, mipmaps: false, float: true });
  const b = bakeTarget(renderer, { width: size, frag: FLOOR_B, uniforms: { tH: { value: hrt.texture }, uTexel: { value: texel }, uExtent: { value: E } } });
  hrt.dispose();
  return { a, b };
}

// ---------------------------------------------------------------------------------------------------------------------
// Tiling stone detail for the architecture (also used as micro detail on the floor).
// ---------------------------------------------------------------------------------------------------------------------
const STONE_FIELD = /* glsl */ `
${NOISE}
uniform vec2 uTexel;
varying vec2 vUv;
float pnoise(vec2 p, float per) {
  vec2 i = floor(p), f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash12(mod(i, per)), hash12(mod(i + vec2(1.0, 0.0), per)), u.x), mix(hash12(mod(i + vec2(0.0, 1.0), per)), hash12(mod(i + vec2(1.0, 1.0), per)), u.x), u.y);
}
float pfbm(vec2 p, float per) {
  float s = 0.0, a = 0.5, n = 0.0;
  for (int i = 0; i < 5; i++) { s += a * pnoise(p, per); n += a; p *= 2.0; per *= 2.0; a *= 0.5; }
  return s / n;
}
float stoneH(vec2 uv) {
  float big = pfbm(uv * 3.0, 3.0);
  float mid = pfbm(uv * 12.0 + 5.0, 12.0);
  float pits = pnoise(uv * 32.0 + 3.0, 32.0);
  pits = pits * pits * pits;
  float grit = pnoise(uv * 96.0, 96.0);
  return big * 0.5 + mid * 0.22 + grit * 0.06 - pits * 0.12;
}
`;
const STONE_A = STONE_FIELD + /* glsl */ `
void main() {
  vec2 uv = vUv;
  float h = stoneH(uv);
  float tone = pfbm(uv * 3.0 + 11.0, 3.0);
  vec3 c = vec3(0.6) * (0.78 + 0.38 * h) * (0.85 + 0.3 * tone);
  float lichen = smoothstep(0.6, 0.78, pfbm(uv * 5.0 + 4.0, 5.0));
  c = mix(c, vec3(0.58, 0.58, 0.5), lichen * 0.3);
  c *= mix(vec3(1.0), vec3(1.05, 1.0, 0.94), pnoise(uv * 2.0, 2.0));
  gl_FragColor = vec4(c, 1.0);
}`;
const STONE_B = STONE_FIELD + /* glsl */ `
void main() {
  vec2 e = uTexel;
  float hx = stoneH(vUv + vec2(e.x, 0.0)) - stoneH(vUv - vec2(e.x, 0.0));
  float hy = stoneH(vUv + vec2(0.0, e.y)) - stoneH(vUv - vec2(0.0, e.y));
  vec3 n = normalize(vec3(-hx * 10.0, -hy * 10.0, 1.0));
  float cav = clamp(0.5 + (stoneH(vUv) - 0.45) * 1.6, 0.0, 1.0);
  gl_FragColor = vec4(n * 0.5 + 0.5, cav);
}`;

/** Bake the tiling stone detail maps. */
export function bakeStone(renderer, size) {
  const texel = new THREE.Vector2(1 / size, 1 / size);
  const a = bakeTarget(renderer, { width: size, frag: STONE_A, uniforms: { uTexel: { value: texel } }, srgb: true, repeat: true });
  const b = bakeTarget(renderer, { width: size, frag: STONE_B, uniforms: { uTexel: { value: texel } }, repeat: true });
  return { a, b };
}

// ---------------------------------------------------------------------------------------------------------------------
// Cloth atlas (512 x 512, alpha = tattered coverage). Regions (u0, v0, u1, v1), v = 0 at the hem:
//   CLOTH.banner    (0, 0, 0.5, 1)        the sect's standing banner: faded oxblood, 天 over 武 in worn cream, the black sun
//   CLOTH.pennant   (0.75, 0, 1, 0.5)     a narrow jade pennant with the black sun
//   CLOTH.hemp      (0.5, 0, 0.75, 0.5)   a plain bleached hemp strip
//   CLOTH.talisman  (0.5, 0.5, 0.75, 1)   yellow paper talisman (부적) with our own red seal strokes
//   CLOTH.talisman2 (0.75, 0.5, 1, 1)     a second talisman
// ---------------------------------------------------------------------------------------------------------------------
export const CLOTH = {
  banner: [0, 0, 0.5, 1], pennant: [0.75, 0, 1, 0.5], hemp: [0.5, 0, 0.75, 0.5], talisman: [0.5, 0.5, 0.75, 1], talisman2: [0.75, 0.5, 1, 1],
};
const BANNER = /* glsl */ `
${NOISE}
${GLYPHS}
varying vec2 vUv;
float tatter(vec2 uv, float depth, float seed) {
  // ragged hem tongues, frayed sides and moth holes -> coverage
  float tongues = depth * (0.45 + 0.55 * fbm2(vec2(uv.x * 9.0 + seed, 0.5), 3)) + depth * 0.25 * sin(uv.x * 23.0 + seed);
  float hem = smoothstep(tongues - 0.01, tongues + 0.01, uv.y + 0.05 * vnoise(vec2(uv.x * 60.0, uv.y * 8.0)));
  float side = smoothstep(0.0, 0.035, min(uv.x, 1.0 - uv.x) + 0.02 * (vnoise(vec2(uv.y * 40.0, seed)) - 0.6));
  float holes = smoothstep(0.74, 0.79, fbm2(vec2(uv.x, uv.y * 2.6) * 4.0 + 2.0 + seed, 4)) * smoothstep(0.95, 0.5, uv.y);
  return hem * side * (1.0 - holes);
}
void main() {
  vec2 A = vUv;
  vec3 cloth; float alpha;
  if (A.x < 0.5) {
    // standing banner: 4.2 : 1
    vec2 uv = vec2(A.x * 2.0, A.y);
    vec2 p = vec2(uv.x, uv.y * 4.2);
    float weave = 0.9 + 0.1 * sin(uv.x * 700.0) * sin(uv.y * 2400.0);
    cloth = vec3(0.082, 0.017, 0.018) * (0.72 + 0.5 * fbm2(p * 5.0, 4)) * weave;
    float border = step(abs(uv.x - 0.5), 0.445) * (1.0 - step(abs(uv.x - 0.5), 0.405));
    cloth = mix(cloth, vec3(0.1, 0.08, 0.05), border * 0.65);
    vec3 ink = vec3(0.17, 0.15, 0.115);
    float wear = 0.5 + 0.5 * vnoise(p * 26.0) * (0.6 + 0.4 * vnoise(p * 7.0));
    // the black sun at the head
    vec2 c = vec2((uv.x - 0.5), (uv.y - 0.875) * 4.2);
    float rr = length(c);
    float ring = smoothstep(0.03, 0.0, abs(rr - 0.2));
    float rays = smoothstep(0.3, 0.1, abs(fract(atan(c.y, c.x) / 6.2831853 * 12.0 + rr * 1.2) - 0.5) * 2.0 + (rr - 0.3) * 4.0) * step(0.24, rr) * step(rr, 0.36);
    cloth = mix(cloth, ink * 0.9, max(ring, rays) * wear * 0.85);
    cloth = mix(cloth, vec3(0.012, 0.01, 0.01), smoothstep(0.19, 0.17, rr) * 0.9);
    // 天 over 武, brushed
    vec2 g1 = vec2((uv.x - 0.5) / 0.62 + 0.5, (uv.y - 0.565) * 4.2 / 0.62);
    vec2 g2 = vec2((uv.x - 0.5) / 0.62 + 0.5, (uv.y - 0.375) * 4.2 / 0.62);
    float d = 1e3;
    if (g1.y > -0.1 && g1.y < 1.1) d = min(d, glyphTian(g1));
    if (g2.y > -0.1 && g2.y < 1.1) d = min(d, glyphMu(g2));
    d += (vnoise(p * 30.0) - 0.5) * 0.02;
    float glyph = 1.0 - smoothstep(-0.01, 0.012, d);
    cloth = mix(cloth, ink, glyph * (0.55 + 0.45 * wear));
    // grime and bleaching toward the hem
    cloth *= mix(0.35, 1.0, smoothstep(0.0, 0.5, uv.y));
    cloth = mix(cloth, vec3(0.05, 0.045, 0.04), (1.0 - smoothstep(0.0, 0.28, uv.y)) * 0.4);
    alpha = tatter(uv, 0.2, 0.0);
  } else if (A.y < 0.5) {
    bool hemp = A.x < 0.75;
    vec2 uv = vec2((A.x - (hemp ? 0.5 : 0.75)) * 4.0, A.y * 2.0);
    vec2 p = vec2(uv.x, uv.y * 4.0);
    float weave = 0.88 + 0.12 * sin(uv.x * 260.0) * sin(uv.y * 900.0);
    if (hemp) {
      cloth = vec3(0.16, 0.15, 0.125) * (0.6 + 0.6 * fbm2(p * 4.0, 4)) * weave;
      cloth *= mix(0.45, 1.0, smoothstep(0.0, 0.6, uv.y));
      alpha = tatter(uv, 0.3, 7.0);
    } else {
      cloth = vec3(0.02, 0.05, 0.046) * (0.7 + 0.5 * fbm2(p * 5.0, 4)) * weave;
      vec2 c = vec2(uv.x - 0.5, (uv.y - 0.72) * 3.0);
      float rr = length(c);
      cloth = mix(cloth, vec3(0.14, 0.125, 0.09), smoothstep(0.035, 0.0, abs(rr - 0.24)) * 0.8);
      cloth = mix(cloth, vec3(0.01), smoothstep(0.22, 0.2, rr) * 0.9);
      cloth *= mix(0.4, 1.0, smoothstep(0.0, 0.5, uv.y));
      // swallow-tail hem
      alpha = tatter(uv, 0.12, 3.0) * step(0.3 * (1.0 - abs(uv.x - 0.5) * 2.0), uv.y);
    }
  } else {
    // paper talismans: 1 : 2.6
    float which = A.x < 0.75 ? 0.0 : 1.0;
    vec2 uv = vec2((A.x - 0.5 - 0.25 * which) * 4.0, (A.y - 0.5) * 2.0);
    vec2 p = vec2(uv.x, uv.y * 2.6);
    cloth = vec3(0.3, 0.22, 0.085) * (0.72 + 0.4 * fbm2(p * 6.0 + which * 5.0, 4));
    cloth = mix(cloth, vec3(0.12, 0.1, 0.07), smoothstep(0.5, 0.8, fbm2(p * 2.5 + 3.0 + which, 3)) * 0.6);
    vec3 red = vec3(0.2, 0.022, 0.016);
    float d = 1e3;
    for (int i = 0; i < 3; i++) {
      vec2 g = vec2((uv.x - 0.5) / 0.74 + 0.5, (uv.y - (0.7 - 0.27 * float(i))) * 2.6 / 0.62 + 0.5);
      if (g.y > -0.05 && g.y < 1.05) d = min(d, sealGlyph(g, 60.0 + which * 9.0 + float(i) * 3.0));
    }
    // a red frame line and a seal block at the head
    float frame = abs(max(abs(uv.x - 0.5) - 0.4, abs(uv.y - 0.5) - 0.465)) - 0.012;
    d = min(d, frame);
    float ink = (1.0 - smoothstep(-0.006, 0.012, d)) * (0.6 + 0.4 * vnoise(p * 30.0));
    cloth = mix(cloth, red, ink * 0.9);
    float torn = smoothstep(0.02, 0.06, uv.y + 0.05 * (vnoise(vec2(uv.x * 14.0, which)) - 0.5));
    float side = smoothstep(0.0, 0.05, min(uv.x, 1.0 - uv.x) + 0.03 * (vnoise(vec2(uv.y * 20.0, which + 4.0)) - 0.6));
    float bite = 1.0 - smoothstep(0.7, 0.76, fbm2(p * 3.0 + which * 11.0, 3)) * step(uv.y, 0.6);
    alpha = torn * side * bite;
  }
  gl_FragColor = vec4(cloth, alpha);
}`;

/** Bake the cloth atlas (banners, pennants, hemp strips, talismans). */
export function bakeBanner(renderer) {
  return bakeTarget(renderer, { width: 512, height: 512, frag: BANNER, srgb: true });
}

// ---------------------------------------------------------------------------------------------------------------------
// Foliage atlas (2 x 2 cells, alpha = coverage): ink-brush silhouettes.
//   FOLIAGE.pineSide (0,0)  a needle pad seen from the side: flat underside, tufted top
//   FOLIAGE.pineTop  (1,0)  a needle pad seen from below / above: a ragged round mass
//   FOLIAGE.bamboo   (0,1)  a spray of bamboo leaves hanging from a twig at the top centre
//   FOLIAGE.grass    (1,1)  a tuft of dry grass rising from the bottom centre
// ---------------------------------------------------------------------------------------------------------------------
export const FOLIAGE = { pineSide: [0, 0], pineTop: [1, 0], bamboo: [0, 1], grass: [1, 1] };
const FOLIAGE_FRAG = /* glsl */ `
${NOISE}
varying vec2 vUv;
float sdSeg(vec2 p, vec2 a, vec2 b) { vec2 pa = p - a, ba = b - a; float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0); return length(pa - ba * h); }
// a lanceolate leaf from a to b, widest at 40%
float leaf(vec2 p, vec2 a, vec2 b, float w) {
  vec2 ba = b - a; float L = length(ba); vec2 d = ba / L; vec2 q = p - a;
  float t = clamp(dot(q, d) / L, 0.0, 1.0);
  float x = dot(q, vec2(-d.y, d.x));
  float prof = w * pow(max(sin(pow(max(t, 0.0), 0.7) * 3.14159), 0.0), 0.9);
  float e = abs(x) - prof;
  return max(e, max(-dot(q, d), dot(q, d) - L));
}
void main() {
  vec2 cellI = floor(vUv * 2.0);
  vec2 c = fract(vUv * 2.0);
  c = clamp((c - 0.03) / 0.94, 0.0, 1.0);
  float a = 0.0;
  vec3 col = vec3(0.5);
  if (cellI.y < 0.5 && cellI.x < 0.5) {
    // pine pad, side: lumps along a flat bough line, needles bristling up and out
    float d = 1e3;
    for (int i = 0; i < 6; i++) {
      float fi = float(i);
      vec2 o = vec2(0.14 + 0.145 * fi, 0.3 + 0.1 * sin(fi * 2.3) + 0.06 * hash12(vec2(fi, 2.0)));
      d = min(d, length((c - o) / vec2(1.25, 0.8)) - (0.1 + 0.04 * hash12(vec2(fi, 5.0))));
    }
    d = max(d, 0.2 - c.y - 0.03 * sin(c.x * 30.0));
    float ang = atan(c.y - 0.1, c.x - 0.5);
    float spike = (vnoise(vec2(ang * 46.0, 1.0)) - 0.35) * 0.07 + (vnoise(vec2(c.x * 70.0, c.y * 9.0)) - 0.5) * 0.05;
    a = 1.0 - smoothstep(-0.012, 0.012, d - spike * step(0.2, c.y));
    col = vec3(0.42 + 0.5 * smoothstep(0.25, 0.55, c.y)) * (0.75 + 0.5 * vnoise(c * 30.0));
  } else if (cellI.y < 0.5) {
    // pine pad, plan view
    vec2 q = c - 0.5;
    float ang = atan(q.y, q.x);
    float rr = length(q);
    float edge = 0.36 + 0.07 * sin(ang * 3.0 + 1.0) + 0.05 * sin(ang * 7.0) + (vnoise(vec2(ang * 40.0, 3.0)) - 0.4) * 0.09;
    a = 1.0 - smoothstep(-0.012, 0.012, rr - edge);
    a *= 1.0 - smoothstep(0.62, 0.72, vnoise(c * 9.0 + 2.0)) * smoothstep(0.1, 0.3, rr);
    col = vec3(0.5 + 0.3 * vnoise(c * 24.0));
  } else if (cellI.x < 0.5) {
    // bamboo spray: a twig from the top centre, leaves drooping to both sides
    float d = sdSeg(c, vec2(0.5, 1.0), vec2(0.47, 0.55)) - 0.007;
    d = min(d, sdSeg(c, vec2(0.48, 0.7), vec2(0.28, 0.56)) - 0.005);
    d = min(d, sdSeg(c, vec2(0.485, 0.8), vec2(0.7, 0.68)) - 0.005);
    d = min(d, leaf(c, vec2(0.47, 0.56), vec2(0.4, 0.1), 0.05));
    d = min(d, leaf(c, vec2(0.47, 0.58), vec2(0.62, 0.2), 0.045));
    d = min(d, leaf(c, vec2(0.28, 0.56), vec2(0.06, 0.3), 0.045));
    d = min(d, leaf(c, vec2(0.29, 0.57), vec2(0.22, 0.14), 0.04));
    d = min(d, leaf(c, vec2(0.3, 0.6), vec2(0.04, 0.6), 0.035));
    d = min(d, leaf(c, vec2(0.7, 0.68), vec2(0.93, 0.4), 0.045));
    d = min(d, leaf(c, vec2(0.69, 0.68), vec2(0.8, 0.26), 0.04));
    d = min(d, leaf(c, vec2(0.7, 0.7), vec2(0.97, 0.72), 0.033));
    d = min(d, leaf(c, vec2(0.49, 0.86), vec2(0.3, 0.86), 0.03));
    a = 1.0 - smoothstep(-0.006, 0.006, d);
    col = vec3(0.55 + 0.35 * vnoise(c * 14.0));
  } else {
    // dry grass: thin curved blades fanning from the root
    float d = 1e3;
    for (int i = 0; i < 9; i++) {
      float fi = float(i);
      float lean = (fi - 4.0) * 0.085 + (hash12(vec2(fi, 1.0)) - 0.5) * 0.08;
      float len = 0.55 + 0.4 * hash12(vec2(fi, 7.0));
      float t = clamp(c.y / len, 0.0, 1.0);
      float x = 0.5 + lean * t + lean * 1.6 * t * t;
      float w = 0.02 * (1.0 - t * t) + 0.002;
      d = min(d, max(abs(c.x - x) - w, c.y - len));
    }
    a = 1.0 - smoothstep(-0.005, 0.005, d);
    col = vec3(0.6 + 0.4 * c.y);
  }
  gl_FragColor = vec4(col, a);
}`;
/** Bake the foliage atlas. */
export function bakeFoliage(renderer, size = 512) {
  return bakeTarget(renderer, { width: size, height: size, frag: FOLIAGE_FRAG, srgb: false });
}

// ---------------------------------------------------------------------------------------------------------------------
// Tiling weathered timber detail: grain running along v (albedo variation, normal + cavity).
// ---------------------------------------------------------------------------------------------------------------------
const WOOD_FIELD = /* glsl */ `
${NOISE}
uniform vec2 uTexel;
varying vec2 vUv;
float pnoise(vec2 p, vec2 per) {
  vec2 i = floor(p), f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash12(mod(i, per)), hash12(mod(i + vec2(1.0, 0.0), per)), u.x), mix(hash12(mod(i + vec2(0.0, 1.0), per)), hash12(mod(i + vec2(1.0, 1.0), per)), u.x), u.y);
}
float woodH(vec2 uv) {
  float warp = pnoise(uv * vec2(3.0, 2.0), vec2(3.0, 2.0)) * 0.8;
  float g1 = pnoise(vec2(uv.x * 24.0 + warp * 2.0, uv.y * 2.0), vec2(24.0, 2.0));
  float g2 = pnoise(vec2(uv.x * 72.0 + warp * 5.0, uv.y * 4.0 + 3.0), vec2(72.0, 4.0));
  float fib = pnoise(vec2(uv.x * 220.0, uv.y * 10.0), vec2(220.0, 10.0));
  // checks: a few deep splits along the grain
  float chk = pnoise(vec2(uv.x * 14.0 + warp, uv.y * 1.0 + 7.0), vec2(14.0, 1.0));
  float split = smoothstep(0.08, 0.0, abs(chk - 0.5)) * smoothstep(0.45, 0.7, pnoise(uv * vec2(5.0, 2.0) + 9.0, vec2(5.0, 2.0)));
  return g1 * 0.5 + g2 * 0.28 + fib * 0.1 - split * 0.5;
}
`;
const WOOD_A = WOOD_FIELD + /* glsl */ `
void main() {
  float h = woodH(vUv);
  float tone = pnoise(vUv * vec2(4.0, 2.0) + 11.0, vec2(4.0, 2.0));
  vec3 c = vec3(0.76) * (0.72 + 0.5 * h) * (0.86 + 0.28 * tone);
  gl_FragColor = vec4(clamp(c, 0.0, 1.0), 1.0);
}`;
const WOOD_B = WOOD_FIELD + /* glsl */ `
void main() {
  vec2 e = uTexel;
  float hx = woodH(vUv + vec2(e.x, 0.0)) - woodH(vUv - vec2(e.x, 0.0));
  float hy = woodH(vUv + vec2(0.0, e.y)) - woodH(vUv - vec2(0.0, e.y));
  vec3 n = normalize(vec3(-hx * 7.0, -hy * 7.0, 1.0));
  float cav = clamp(0.5 + (woodH(vUv) - 0.4) * 1.6, 0.0, 1.0);
  gl_FragColor = vec4(n * 0.5 + 0.5, cav);
}`;
/** Bake the tiling timber detail maps. */
export function bakeWood(renderer, size = 512) {
  const texel = new THREE.Vector2(1 / size, 1 / size);
  const a = bakeTarget(renderer, { width: size, frag: WOOD_A, uniforms: { uTexel: { value: texel } }, srgb: true, repeat: true });
  const b = bakeTarget(renderer, { width: size, frag: WOOD_B, uniforms: { uTexel: { value: texel } }, repeat: true });
  return { a, b };
}
