// One-time GPU texture baking: a fragment shader is rendered into a render target (with mipmaps) at start-up.
// Much faster than per-pixel canvas loops on phones, and still fully procedural.
//
//   bakeFloor(renderer, size)   -> { a, b }   arena floor maps covering [-E, E]^2 (E = LAYOUT.floorTexExtent)
//                                  a: sRGB albedo + puddle mask (alpha), b: linear normal.xz / roughness / metalness
//   bakeStone(renderer, size)   -> { a, b }   tiling stone detail: sRGB albedo variation, linear normal + cavity
//   bakeBanner(renderer)        -> texture    sRGB cloth colour, alpha = tattered coverage

import * as THREE from 'three';
import { NOISE } from './glsl.js';
import { LAYOUT } from './config.js';

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
// Floor: concentric flagstone rows, worn bronze inlay rings, an engraved glyph band, a black-sun medallion, gutter.
// ---------------------------------------------------------------------------------------------------------------------
const FLOOR_FIELD = /* glsl */ `
${NOISE}
uniform float uExtent;
uniform vec2 uTexel;
varying vec2 vUv;
const float TAU = 6.28318530718;

float voronoiEdge(vec2 x) {
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
  return md;
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
  return s;
}

struct Fl { float h; vec3 alb; float rough; float metal; float puddle; };

Fl floorField(vec2 p) {
  Fl o;
  float r0 = length(p);
  float a0 = atan(p.y, p.x);
  // irregular joints: wobble the polar coordinates a little
  float r = r0 + (vnoise(p * 2.3) - 0.5) * 0.045;
  float a = a0 + (vnoise(p * 2.1 + 5.0) - 0.5) * 0.04 / max(r0, 0.5);
  float an = a / TAU + 0.5;

  float kind = 0.0; // 0 stone row, 1 bronze ring, 2 glyph band, 3 medallion, 4 gutter
  float ra = 0.0, rb = 1.0, rows = 1.0, sec = 0.0;
  if (r < 1.22) { kind = 3.0; }
  else if (r < 1.30) { kind = 1.0; }
  else if (r < 3.62) { ra = 1.30; rb = 3.62; rows = 4.0; sec = 1.0; }
  else if (r < 3.70) { kind = 1.0; }
  else if (r < 4.30) { kind = 2.0; ra = 3.70; rb = 4.30; sec = 2.0; }
  else if (r < 4.38) { kind = 1.0; }
  else if (r < 8.30) { ra = 4.38; rb = 8.30; rows = 6.0; sec = 3.0; }
  else if (r < 8.37) { kind = 1.0; }
  else if (r < 12.55) { ra = 8.37; rb = 12.55; rows = 6.0; sec = 4.0; }
  else if (r < 12.63) { kind = 1.0; }
  else if (r < 13.25) { kind = 2.0; ra = 12.63; rb = 13.25; sec = 5.0; }
  else if (r < 13.33) { kind = 1.0; }
  else if (r < 14.65) { ra = 13.33; rb = 14.65; rows = 2.0; sec = 6.0; }
  else { kind = 4.0; ra = 14.65; rb = 16.5; rows = 1.0; sec = 7.0; }

  float w = (rb - ra) / rows;
  float k = floor((r - ra) / w);
  float rr0 = ra + k * w, rr1 = rr0 + w;
  float rowId = sec * 16.0 + k;
  float rmid = 0.5 * (rr0 + rr1);
  float L = (kind == 2.0 ? 0.82 : 0.9 + 0.45 * hash12(vec2(rowId, 3.7)));
  float cnt = max(6.0, floor(TAU * rmid / L));
  float s = an * cnt + hash12(vec2(rowId, 9.1));
  float jm = mod(floor(s), cnt);
  float fs = fract(s);
  float arc = TAU * r / cnt;
  float dj = min(min(r - rr0, rr1 - r), min(fs, 1.0 - fs) * arc);
  vec2 id = vec2(rowId, jm);
  float hs = hash12(id + 0.37), hs2 = hash12(id + 7.13), hs3 = hash12(id + 2.71);
  vec2 lc = vec2(r - rmid, (fs - 0.5) * arc);

  // fight line: stones there are more worn and flatter
  float worn = 1.0 - smoothstep(0.6, 2.2, abs(p.y));

  // ---- height --------------------------------------------------------------------------------------------------
  float h = (hs - 0.5) * 0.007 * (1.0 - 0.6 * worn) + dot((hash22(id) - 0.5) * 0.014, lc);
  h += 0.0045 * smoothstep(0.0, 0.1, dj);
  h -= 0.017 * (1.0 - smoothstep(0.003, 0.02, dj));
  float grain = fbm2(p * 6.5 + hs * 13.0, 4);
  h += (grain - 0.5) * 0.005 * (1.0 - 0.5 * worn) + (vnoise(p * 34.0) - 0.5) * 0.0012;
  float sunk = step(0.955, hs2) * step(1.5, kind == 0.0 ? 2.0 : 0.0);
  h -= sunk * (0.022 + 0.012 * fbm2(p * 9.0, 3));
  float ve = voronoiEdge(p * 1.7 + hs * 31.0);
  float crack = (1.0 - smoothstep(0.0, 0.018, ve)) * step(0.62, hs3) * smoothstep(0.02, 0.06, dj) * (kind == 0.0 || kind == 4.0 ? 1.0 : 0.4);
  crack *= smoothstep(0.35, 0.6, vnoise(p * 1.1 + 4.0));
  h -= crack * 0.008;

  // ---- albedo ---------------------------------------------------------------------------------------------------
  vec3 stone = vec3(0.064, 0.066, 0.073) * (0.72 + 0.56 * hs);
  stone *= mix(vec3(1.0), vec3(1.09, 1.0, 0.9), hs3);
  stone *= 0.82 + 0.36 * fbm2(p * 2.6 + hs * 9.0, 3);
  float rough = mix(0.72, 0.5, worn) + (grain - 0.5) * 0.2;
  float metal = 0.0;

  if (kind == 1.0 || kind == 3.0) {
    // bronze inlay (rings, medallion details): worn through in places, verdigris in others
    float strip = 1.0;
    vec3 bronze = vec3(0.42, 0.27, 0.13);
    if (kind == 3.0) {
      float rays = abs(fract(an * 16.0 + 0.25) - 0.5);
      strip = 0.0;
      strip = max(strip, step(abs(r0 - 0.6), 0.045));
      strip = max(strip, step(rays, 0.05 * (1.15 - r0)) * step(0.72, r0) * step(r0, 1.12));
      stone = mix(stone * 0.75, vec3(0.02, 0.021, 0.024), step(r0, 0.36));
      rough = mix(rough, 0.3, step(r0, 0.36));
      h += 0.002 * step(r0, 0.36);
    }
    float gone = smoothstep(0.62, 0.7, vnoise(vec2(an * 70.0, r0 * 3.0)));
    float verd = smoothstep(0.5, 0.75, fbm2(p * 3.5, 3));
    strip *= 1.0 - gone;
    h -= strip * 0.001 + gone * 0.004 * (kind == 1.0 ? 1.0 : 0.0);
    vec3 inlay = mix(bronze * (0.75 + 0.4 * grain), vec3(0.06, 0.13, 0.11), verd);
    stone = mix(stone, inlay, strip);
    if (kind == 1.0) stone = mix(stone, vec3(0.02), gone);
    metal = strip * (1.0 - verd);
    rough = mix(rough, mix(0.36, 0.8, verd), strip);
    dj = max(dj, 0.05);
  }
  if (kind == 2.0) {
    // engraved glyph band: a dark polished course with worn sigils
    stone *= 0.62;
    rough -= 0.12;
    float seg = fract(fs * 2.0);
    vec2 g = vec2((r - ra) / (rb - ra), seg) - 0.5;
    float which = floor(hash12(id + floor(fs * 2.0)) * 5.0);
    float m = 0.0;
    if (which < 1.0) m = step(abs(length(g) - 0.24), 0.04);
    else if (which < 2.0) m = step(abs(g.y), 0.045) * step(abs(g.x), 0.3);
    else if (which < 3.0) m = step(abs(length(g) - 0.24), 0.04) * step(0.0, g.y + 0.1 * g.x);
    else if (which < 4.0) m = step(abs(abs(g.y) - abs(g.x) * 0.7 - 0.05), 0.04) * step(abs(g.x), 0.3);
    else m = step(length(g - vec2(0.0, 0.15)), 0.07) + step(length(g + vec2(0.0, 0.15)), 0.07);
    m *= 1.0 - smoothstep(0.45, 0.7, vnoise(p * 2.0 + 3.0));
    h -= m * 0.004;
    stone = mix(stone, vec3(0.09, 0.088, 0.082), m * 0.7);
  }
  if (kind == 4.0) {
    // gutter: big slabs, then a drainage channel against the wall
    float ch = smoothstep(14.98, 15.02, r0) * (1.0 - smoothstep(15.28, 15.32, r0));
    h -= ch * 0.035;
    stone *= mix(1.0, 0.6, ch);
  }

  // dirt in joints, moss toward the outer rows
  float joint = 1.0 - smoothstep(0.0, 0.028, dj);
  stone = mix(stone, vec3(0.017, 0.016, 0.015), joint * 0.85);
  float mossZone = smoothstep(9.0, 14.5, r0) * 0.7 + 0.3;
  float moss = smoothstep(0.45, 0.72, fbm2(p * 1.2 + 7.0, 3)) * mossZone * (joint * 0.9 + 0.25 * (1.0 - worn));
  stone = mix(stone, vec3(0.024, 0.032, 0.018), clamp(moss, 0.0, 0.85));
  stone = mix(stone, vec3(0.012), crack * 0.8);
  stone = mix(stone, stone * 0.55 + vec3(0.01), sunk);
  rough = mix(rough, 0.32, joint);

  // ---- puddles ----------------------------------------------------------------------------------------------------
  float zone = clamp((fbm2(p * 0.17 + 3.1, 3) - 0.5) * 3.5, 0.0, 1.0) + blobs(p);
  zone *= 1.0 - 0.75 * (1.0 - smoothstep(0.3, 0.9, abs(p.y)));
  float level = mix(-0.014, 0.008, clamp(zone, 0.0, 1.0)) + (kind == 4.0 ? 0.012 : 0.0);
  o.puddle = smoothstep(0.0, 0.0035, level - h);

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
  float big = pfbm(uv * 4.0, 4.0);
  float pits = smoothstep(0.62, 0.75, pnoise(uv * 24.0 + 3.0, 24.0));
  float grit = pnoise(uv * 64.0, 64.0);
  float streak = pnoise(vec2(uv.x * 40.0, uv.y * 3.0), 40.0);
  return big * 0.6 + grit * 0.12 - pits * 0.25 + streak * 0.1;
}
`;
const STONE_A = STONE_FIELD + /* glsl */ `
void main() {
  vec2 uv = vUv;
  float h = stoneH(uv);
  float tone = pfbm(uv * 3.0 + 11.0, 3.0);
  vec3 c = vec3(0.6) * (0.78 + 0.38 * h) * (0.85 + 0.3 * tone);
  float lichen = smoothstep(0.6, 0.78, pfbm(uv * 5.0 + 4.0, 5.0));
  c = mix(c, vec3(0.62, 0.6, 0.46), lichen * 0.45);
  c *= mix(vec3(1.0), vec3(1.05, 1.0, 0.94), pnoise(uv * 2.0, 2.0));
  gl_FragColor = vec4(c, 1.0);
}`;
const STONE_B = STONE_FIELD + /* glsl */ `
void main() {
  vec2 e = uTexel;
  float hx = stoneH(vUv + vec2(e.x, 0.0)) - stoneH(vUv - vec2(e.x, 0.0));
  float hy = stoneH(vUv + vec2(0.0, e.y)) - stoneH(vUv - vec2(0.0, e.y));
  vec3 n = normalize(vec3(-hx * 18.0, -hy * 18.0, 1.0));
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
// Banner cloth: oxblood weave, a faded eclipse sigil, grime toward the hem, torn edges and moth holes (alpha).
// uv: u across, v = 0 at the hem, 1 at the top bar.
// ---------------------------------------------------------------------------------------------------------------------
const BANNER = /* glsl */ `
${NOISE}
varying vec2 vUv;
void main() {
  vec2 uv = vUv;
  vec2 p = vec2(uv.x, uv.y * 2.6);
  float weave = 0.9 + 0.1 * sin(uv.x * 900.0) * sin(uv.y * 2200.0);
  vec3 cloth = vec3(0.16, 0.024, 0.028) * (0.75 + 0.45 * fbm2(p * 6.0, 4)) * weave;
  // border stripes
  float border = step(abs(uv.x - 0.5), 0.44) * (1.0 - step(abs(uv.x - 0.5), 0.40));
  cloth = mix(cloth, vec3(0.2, 0.14, 0.06), border * 0.8);
  // the eclipse sigil: ring + black disc + rays, faded gold
  vec2 c = vec2((uv.x - 0.5) * 1.0, (uv.y - 0.68) * 2.6);
  float rr = length(c);
  float ang = atan(c.y, c.x);
  float ring = smoothstep(0.03, 0.0, abs(rr - 0.2));
  float rays = smoothstep(0.25, 0.1, abs(fract(ang / 6.2831853 * 12.0) - 0.5) * 2.0 + (rr - 0.32) * 2.0) * step(0.25, rr) * step(rr, 0.38);
  float sig = max(ring, rays) * (0.55 + 0.45 * vnoise(p * 30.0));
  cloth = mix(cloth, vec3(0.3, 0.2, 0.08), sig * 0.85);
  cloth = mix(cloth, vec3(0.012, 0.01, 0.01), smoothstep(0.19, 0.17, rr) * 0.9);
  // grime and bleaching toward the hem
  cloth *= mix(0.35, 1.0, smoothstep(0.0, 0.55, uv.y));
  cloth = mix(cloth, vec3(0.05, 0.045, 0.04), (1.0 - smoothstep(0.0, 0.3, uv.y)) * 0.4);
  // tattered hem: long ragged tongues
  float tongues = 0.18 + 0.22 * fbm2(vec2(uv.x * 9.0, 0.5), 3) + 0.1 * sin(uv.x * 23.0);
  float hem = smoothstep(tongues - 0.01, tongues + 0.01, uv.y + 0.05 * vnoise(vec2(uv.x * 60.0, uv.y * 8.0)));
  // frayed sides and holes
  float side = smoothstep(0.0, 0.03, min(uv.x, 1.0 - uv.x) + 0.02 * (vnoise(vec2(uv.y * 40.0, 1.0)) - 0.6));
  float holes = smoothstep(0.74, 0.79, fbm2(p * 4.0 + 2.0, 4)) * smoothstep(0.95, 0.5, uv.y);
  float alpha = hem * side * (1.0 - holes);
  gl_FragColor = vec4(cloth, alpha);
}`;

/** Bake the banner cloth texture. */
export function bakeBanner(renderer) {
  return bakeTarget(renderer, { width: 256, height: 512, frag: BANNER, srgb: true });
}
