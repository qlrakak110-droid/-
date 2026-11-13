// Character material kit: one MeshStandardMaterial per slot (= one draw call), extended so a single draw call can carry
// many surface types. Per-vertex attributes written by the build system (src/char/build.js):
//   color (vec3)  albedo (linear)
//   surf  (vec4)  x roughness, y metalness, z texture set + detail amount (see surfDetail()), w cavity / edge:
//                 w < 1 crevice / occlusion (darker, grimier), w = 1 neutral, 1 < w <= 2 convex edge (edge wear)
//   glow  (vec3)  legacy mode: emissive HDR radiance. Channel mode (material option `glow`): masks of the three glow
//                 channels (x inlay, y vein (x the set's mask: cracks, engraved grooves, woven figure, stitches), z eye).
//                 UV sets (fur, hair, brocade, lamellar, bamboo, gauze, blade) and torn cloth carry (u, v, code) there
//                 instead: the mesh's own texture coordinates plus a per-piece code (motif + glow, opacity, hamon ...).
//
// Fragment shader (onBeforeCompile on MeshStandardMaterial, one shared program for every character):
//   * texture sets (src/char/kit/textures.js): triplanar albedo / roughness variation and whiteout-blended normal maps
//     sampled in bind-pose space (sticks to the surface), or sampled through the mesh uv for the UV sets
//   * murim cloth: matte silk (anisotropic satin sheen across the warp, a weave only a close-up resolves), hemp, figured
//     damask, embroidered brocade bands (eight motifs, metal thread, glow seeping through the thread), soft wrapped
//     terminator and light through thin cut-out cloth, open-weave gauze held by a screen-door dither at distance
//   * lacquer (deep clear coat, undercoat showing on worn edges, glowing craquelure), laced lamellar plates, woven
//     bamboo, hair ribbons with strand highlights, forged blades (bright honed edge, misty temper line, flowing grain),
//     aged bronze with verdigris, jade
//   * edge wear on convex edges (bare metal, chipped by noise), crevice grime from vertex cavity + micro cavity
//   * heat tint around cracks (scorched set), emissive inlay / vein / eye channels whose colour and intensity are
//     uniforms (animate them at runtime without recompiling: createGlowControl / attachGlow)
//   * fresnel rim term (silhouettes against the dark arena) and the fresnel-weighted hit flash (uFlash)
//   * cutout materials (option `cutout`): torn and burnt cloth hems with ember-lit edges, fur / hair strand alpha, gauze
// Surface value 0..1 in surf.z keeps the original behaviour (legacy detail texture), so older designs render unchanged.

import * as THREE from 'three';
import { makeRng } from '../core/math.js';
import { getTextureSets, requireTextureSet, SET, SET_COUNT, SET_SCALE, SET_BUMP, SET_LAYER, configureTextureSets } from './kit/textures.js';

export { SET, configureTextureSets };

let detailTex = null;

/** Shared 256x256 tileable detail texture (legacy set 0): R mottling fbm, G scratches, B hammered cells (height), A fine grain. */
export function getDetailTexture() {
  if (detailTex) return detailTex;
  const N = 256;
  const rng = makeRng(90210);
  const data = new Uint8Array(N * N * 4);
  // periodic value noise
  const lattice = (P) => { const a = new Float32Array(P * P); for (let i = 0; i < a.length; i++) a[i] = rng(); return a; };
  const octs = [8, 16, 32, 64].map((P) => ({ P, L: lattice(P) }));
  const vnoise = (o, x, y) => {
    const P = o.P, fx = (x / N) * P, fy = (y / N) * P;
    const ix = Math.floor(fx), iy = Math.floor(fy), tx = fx - ix, ty = fy - iy;
    const sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty);
    const g = (a, b) => o.L[((b % P) + P) % P * P + ((a % P) + P) % P];
    const a = g(ix, iy) + (g(ix + 1, iy) - g(ix, iy)) * sx;
    const b = g(ix, iy + 1) + (g(ix + 1, iy + 1) - g(ix, iy + 1)) * sx;
    return a + (b - a) * sy;
  };
  // worley cells (periodic), 12x12 feature points
  const C = 12, pts = new Float32Array(C * C * 2);
  for (let i = 0; i < C * C; i++) { pts[i * 2] = rng(); pts[i * 2 + 1] = rng(); }
  const worley = (x, y) => {
    const fx = (x / N) * C, fy = (y / N) * C, ix = Math.floor(fx), iy = Math.floor(fy);
    let d1 = 9;
    for (let oy = -1; oy <= 1; oy++) for (let ox = -1; ox <= 1; ox++) {
      const cx = ix + ox, cy = iy + oy, w = (((cy % C) + C) % C) * C + (((cx % C) + C) % C);
      const dx = cx + pts[w * 2] - fx, dy = cy + pts[w * 2 + 1] - fy, d = dx * dx + dy * dy;
      if (d < d1) d1 = d;
    }
    return Math.sqrt(d1);
  };
  // scratches: accumulate thin lines into a float buffer (wrapping)
  const scr = new Float32Array(N * N);
  for (let k = 0; k < 220; k++) {
    const x0 = rng() * N, y0 = rng() * N;
    const ang = rng() < 0.6 ? 0.35 + (rng() - 0.5) * 0.5 : rng() * Math.PI;
    const len = 6 + rng() * rng() * 70, val = (rng() < 0.5 ? -1 : 1) * (0.25 + rng() * 0.75);
    for (let s = 0; s < len; s += 0.5) {
      const x = Math.floor(x0 + Math.cos(ang) * s), y = Math.floor(y0 + Math.sin(ang) * s);
      scr[((y % N) + N) % N * N + ((x % N) + N) % N] += val * (1 - s / len * 0.5);
    }
  }
  for (let y = 0; y < N; y++) {
    for (let x = 0; x < N; x++) {
      let f = 0, amp = 0.55, sum = 0;
      for (const o of octs) { f += vnoise(o, x, y) * amp; sum += amp; amp *= 0.55; }
      f /= sum;
      const w = worley(x, y);
      const i = (y * N + x) * 4;
      data[i] = Math.round(Math.min(1, Math.max(0, (f - 0.5) * 1.6 + 0.5)) * 255);
      data[i + 1] = Math.round(Math.min(1, Math.max(0, 0.5 + scr[y * N + x] * 0.5)) * 255);
      data[i + 2] = Math.round(Math.min(1, w * w * 1.6) * 255);
      data[i + 3] = Math.round(rng() * 255);
    }
  }
  detailTex = new THREE.DataTexture(data, N, N, THREE.RGBAFormat, THREE.UnsignedByteType);
  detailTex.wrapS = detailTex.wrapT = THREE.RepeatWrapping;
  detailTex.magFilter = THREE.LinearFilter;
  detailTex.minFilter = THREE.LinearMipmapLinearFilter;
  detailTex.generateMipmaps = true;
  detailTex.colorSpace = THREE.NoColorSpace;
  detailTex.needsUpdate = true;
  return detailTex;
}

/**
 * Encode a texture set and its detail amount into the `detail` surface option (surf.z); the set's texture layers are
 * generated on first use (requireTextureSet).
 * set 0 (legacy) keeps the 0..1 meaning; set k >= 1 -> 2k + 0.25 + 0.5 * amount (robust to interpolation error).
 * @param {number|string} set  SET id or name ('hammered', 'scorched', 'engraved', 'leather', 'cloth', 'fur', 'mail',
 *   'quilted', 'silk', 'hemp', 'damask', 'brocade', 'lacquer', 'lamellar', 'bamboo', 'gauze', 'hair', 'blade', 'bronze', 'jade')
 * @param {number} amount 0..1 (scales normal, albedo and roughness variation of the set)
 */
export function surfDetail(set, amount = 1) {
  const k = typeof set === 'string' ? SET[set] : set;
  if (!k) return Math.max(0, Math.min(1, amount));
  requireTextureSet(k);
  return 2 * k + 0.25 + 0.5 * Math.max(0, Math.min(1, amount));
}

/** Decode surf.z back into { set, amount } (tools / tests). */
export function decodeDetail(z) {
  if (z < 1.5) return { set: 0, amount: z };
  const set = Math.floor(z * 0.5);
  return { set, amount: Math.max(0, Math.min(1, (z - 2 * set - 0.25) * 2)) };
}

const VERT_PARS = /* glsl */ `
attribute vec4 surf;
attribute vec3 glow;
uniform float uShadowNB;
varying vec4 vSurf;
varying vec3 vGlow;
varying vec3 vRestPos;
varying vec3 vB0;
varying vec3 vB1;
varying vec3 vB2;
`;
const VERT_MAIN = /* glsl */ `
  vSurf = surf; vGlow = glow; vRestPos = position;
`;
// bind-pose -> view rotation (skinning x normal matrix): maps triplanar rest-space normals into view space
const VERT_NORMAL = /* glsl */ `
  {
    mat3 edM = mat3(normalMatrix);
    #ifdef USE_SKINNING
      edM = edM * mat3(skinMatrix);
    #endif
    vB0 = edM[0]; vB1 = edM[1]; vB2 = edM[2];
  }
`;
// shadow lookup: the light's normal bias plus the material's own (uShadowNB, metres along the normal): armour self-shadows
// without acne on the grazing sides of plates whatever the key light's settings
const SHADOW_VERTEX = THREE.ShaderChunk.shadowmap_vertex
  .replace(/directionalLightShadows\[ i \]\.shadowNormalBias/g, '( directionalLightShadows[ i ].shadowNormalBias + uShadowNB )')
  .replace(/pointLightShadows\[ i \]\.shadowNormalBias/g, '( pointLightShadows[ i ].shadowNormalBias + uShadowNB )')
  .replace(/spotLightShadows\[ i \]\.shadowNormalBias/g, '( spotLightShadows[ i ].shadowNormalBias + uShadowNB )');

const FRAG_PARS = /* glsl */ `
#define ED_SETS ${SET_COUNT + 1}
uniform sampler2D uDetail;
uniform highp sampler2DArray uSets;
uniform float uSetsN;
uniform float uDetailScale;
uniform float uBump;
uniform vec3 uFlash;
uniform float uGlowScale;
uniform float uGlowMode;
uniform vec3 uGlowA;
uniform vec3 uGlowB;
uniform vec3 uGlowC;
uniform vec4 uRim;
uniform vec2 uRimFade;
uniform vec4 uWear;
uniform vec3 uWearColor;
uniform vec3 uGrimeColor;
uniform vec3 uHeatColor;
uniform vec4 uEmber;
uniform vec4 uPulse;
uniform vec4 uFinish;
uniform vec4 uAniso;
uniform vec4 uSheen;
uniform vec3 uFrostColor;
uniform vec3 uPatinaColor;
uniform vec4 uDust;
uniform vec4 uThread;
uniform vec4 uLace;
uniform vec4 uUnder;
uniform vec4 uVerd;
uniform vec4 uTrans;
uniform float uSetScale[ED_SETS];
uniform float uSetBump[ED_SETS];
uniform float uSetLayer[ED_SETS];
uniform float uDetailMul;
varying vec4 vSurf;
varying vec3 vGlow;
varying vec3 vRestPos;
varying vec3 vB0;
varying vec3 vB1;
varying vec3 vB2;
// per-pixel shading inputs written in main() and read by the kit BRDF (RE_Direct_ED / RE_IndirectSpecular_ED)
vec3 edTb = vec3(0.0, 1.0, 0.0);   // bind space: direction the highlight stretches along (anisotropy)
vec3 edAT = vec3(1.0, 0.0, 0.0);   // view space: rough (stretch) direction
vec3 edAB = vec3(0.0, 0.0, 1.0);   // view space: sharp direction
float edAniso = 0.0;               // 0 isotropic .. 1
float edPolish = 0.0;              // weight of the sharp polish lobe (metals, lacquer, jade)
float edPolishR = 0.2;             // its roughness
vec3 edSheenC = vec3(0.0);         // fuzz sheen colour (cloth, fur, leather wax, pearl satin)
float edSheenR = 0.5;
vec3 edSpecAdd = vec3(0.0);        // extra specular colour of the base lobe (the dyed lustre of silk, hair)
float edWrap = 0.0;                // wrapped diffuse terminator (cloth, jade)
float edTrans = 0.0;               // light through thin cloth lit from behind
float edAO = 1.0;                  // occlusion of indirect light (crevices, inner skins, fur roots)
float edFilm = 0.0;                // view-dependent oxide / nacre film on the specular colour
float edFilmKind = 0.0;            // 0 pearl (pastel nacre), 1 patina (violet-teal oxide)
float edRoughT = 0.2;              // roughness target ...
float edRoughW = 0.0;              // ... and its weight (worn edges, frost, honed blade edges)
float edMetalT = 0.0;              // metalness target ...
float edMetalW = 0.0;              // ... and its weight (embroidery thread, lacing cords)
float edInlayK = 0.0, edEyeK = 0.0;
vec3 edRadP = vec3(0.0);
vec4 edTriplanar(vec3 p, vec3 n) {
  vec3 w = pow(abs(n), vec3(4.0));
  w /= max(1e-4, w.x + w.y + w.z);
  return texture2D(uDetail, p.zy) * w.x + texture2D(uDetail, p.xz) * w.y + texture2D(uDetail, p.xy) * w.z;
}
vec3 edPerturb(vec3 surfPos, vec3 surfNorm, vec2 dHdxy, float faceDir) {
  vec3 vSigmaX = normalize(dFdx(surfPos));
  vec3 vSigmaY = normalize(dFdy(surfPos));
  vec3 vN = surfNorm;
  vec3 R1 = cross(vSigmaY, vN);
  vec3 R2 = cross(vN, vSigmaX);
  float fDet = dot(vSigmaX, R1) * faceDir;
  vec3 vGrad = sign(fDet) * (dHdxy.x * R1 + dHdxy.y * R2);
  return normalize(abs(fDet) * surfNorm - vGrad);
}
vec4 edSet(vec2 uv, float layer) { return texture(uSets, vec3(uv, layer)); }
vec3 edTn(vec4 b, float k) { vec2 xy = (b.xy * 2.0 - 1.0) * k; return vec3(xy, sqrt(max(0.0, 1.0 - dot(xy, xy)))); }
// direction in which s increases across the surface (from screen derivatives q0 / q1 of the position and s0 / s1 of s)
vec3 edGrad(vec3 q0, vec3 q1, float s0, float s1, vec3 N) { return cross(q1, N) * s0 + cross(N, q0) * s1; }
// emission ramp: deep, saturated colour where the mask is low, the channel colour, then whiter and brighter at the core
vec3 edHot(vec3 c, float m) {
  float mx = max(c.r, max(c.g, c.b));
  vec3 deep = c * (c / max(mx, 1e-4));
  vec3 col = mix(deep, c, smoothstep(0.0, 0.55, m));
  col = mix(col, vec3(mx), 0.3 * smoothstep(0.55, 1.0, m));
  return col * m;
}
// temper (heat tint) film colours from the cool fringe (straw) to the hot rim of a crack (blue, then burnt oxide)
vec3 edTemper(float t) {
  vec3 c = mix(vec3(0.66, 0.52, 0.26), vec3(0.52, 0.25, 0.09), smoothstep(0.18, 0.4, t));
  c = mix(c, vec3(0.36, 0.12, 0.4), smoothstep(0.4, 0.6, t));
  c = mix(c, vec3(0.13, 0.22, 0.5), smoothstep(0.6, 0.8, t));
  return mix(c, uHeatColor * 2.0, smoothstep(0.82, 1.0, t));
}
`;

// all per-surface work happens right after the vertex colour is applied (normal-independent inputs are ready there)
const FRAG_SURFACE = /* glsl */ `
  float edFace = gl_FrontFacing ? 1.0 : -1.0;
  mat3 edM = mat3(normalize(vB0), normalize(vB1), normalize(vB2));
  vec3 edNv = normalize(vNormal);
  #ifdef DOUBLE_SIDED
    edNv *= edFace;
  #endif
  vec3 edNr = normalize(edNv * edM);
  // screen derivatives in uniform control flow: footprint, the mesh uv frame, cavity gradient (plate edges)
  vec3 edQ0 = dFdx(vRestPos), edQ1 = dFdy(vRestPos);
  float edPix = max(length(edQ0), length(edQ1));
  vec2 edG0 = dFdx(vGlow.xy), edG1 = dFdy(vGlow.xy);
  float edC0 = dFdx(vSurf.w), edC1 = dFdy(vSurf.w);
  float edSz = vSurf.z;
  float edSetF = edSz < 1.5 ? 0.0 : floor(edSz * 0.5);
  int edSi = int(edSetF + 0.5);
  float edAmt = edSz < 1.5 ? edSz : clamp((edSz - 2.0 * edSetF - 0.25) * 2.0, 0.0, 1.0);
  float edCav = vSurf.w;
  float edOcc = min(edCav, 1.0);
  float edEdge = max(edCav - 1.0, 0.0);
  float edRoughMul = 1.0, edRoughAdd = 0.0, edMetalMul = 1.0;
  vec3 edNrP = edNr;
  vec3 edEmis = vec3(0.0);
  vec4 edDet = vec4(0.5);
  // brushing frame: highlights stretch along the bone axis (bind +Y: limbs hang in the bind pose), radially on caps
  edTb = normalize(vec3(0.0, 1.0, 0.0) - edNr * edNr.y + vec3(1e-4, 0.0, 0.0));
  if (edSi == 0) {
    edDet = edTriplanar(vRestPos * uDetailScale, edNr);
    diffuseColor.rgb *= mix(1.0, 0.72 + 0.56 * edDet.r, edAmt) * vSurf.w;
    edEmis = vGlow * uGlowScale;
  } else {
    float edL = uSetLayer[edSi];
    float edScale = uSetScale[edSi] * uDetailMul;
    // sets textured through the mesh uv (fur, brocade, lamellar, bamboo, gauze, hair); woven fabrics
    bool edUvT = edSi == 6 || edSi == 12 || (edSi >= 14 && edSi <= 17);
    bool edFab = edSi == 5 || (edSi >= 9 && edSi <= 11);
    bool edSilk = edSi == 9 || edSi == 11;
    bool edTorn = edSi == 5;
    #ifdef ED_CUTOUT
      edTorn = edFab && (edSi == 5 || vGlow.z > 0.0005);
    #endif
    // vGlow = (u, v, code) instead of glow channel masks
    bool edUv = edUvT || edSi == 18 || edTorn;
    float edCode = vGlow.z;
    float edLod = 0.0;
    float edThread = 0.0;                 // embroidery thread / lacing cord coverage
    vec3 edThreadC = vec3(0.0);
    float edCodeGlow = 0.0;               // glow amount carried by the uv code
    float edVeinDark = 1.0;               // glowing cracks are dark and rough; glowing thread is not
    vec4 edA = vec4(0.5), edB = vec4(0.5, 0.5, 1.0, 0.0);
    float metal = vSurf.y;
    if (edUvT) {
      // frame of the mesh uv on the surface (bind space)
      float sg = dot(edQ0, cross(edQ1, edNr)) < 0.0 ? -1.0 : 1.0;
      vec3 Tu = edGrad(edQ0, edQ1, edG0.x, edG1.x, edNr) * sg;
      vec3 Tv = edGrad(edQ0, edQ1, edG0.y, edG1.y, edNr) * sg;
      Tu = normalize(Tu - edNr * dot(edNr, Tu) + vec3(0.0, 1e-6, 0.0));
      Tv = normalize(Tv - edNr * dot(edNr, Tv) + vec3(1e-6, 0.0, 0.0));
      vec2 uv = vGlow.xy * edScale;
      if (edSi == 6) uv = vec2(vGlow.x * 3.0, vGlow.y * 0.55);
      if (edSi == 17) uv = vec2(vGlow.x, vGlow.y * 0.3);
      edLod = smoothstep(0.8, 5.0, max(length(edG0), length(edG1)) * edScale * uSetsN);
      float k = uSetBump[edSi] * uBump * edAmt * (1.0 - 0.6 * edLod);
      if (edSi == 12) {
        // brocade band: one of eight embroidery motifs (height fields, one per channel of the two layers), embossed
        float m = floor(edCode + 0.002);
        edCodeGlow = clamp(edCode - m, 0.0, 1.0);
        float lay = edL + step(3.5, m);
        int ch = int(m - 4.0 * step(3.5, m) + 0.5);
        float e = 1.5 / uSetsN;
        float h0 = texture(uSets, vec3(uv, lay))[ch];
        float hu = texture(uSets, vec3(uv + vec2(e, 0.0), lay))[ch];
        float hv = texture(uSets, vec3(uv + vec2(0.0, e), lay))[ch];
        float halo = texture(uSets, vec3(uv, lay), 2.6)[ch];
        edThread = smoothstep(0.2, 0.55, h0);
        // satin stitches laid across the stroke: a fine hatch in close-ups; the ground is a ribbed silk tape
        float hatch = sin((uv.x + uv.y) * uSetsN * 1.3) * (1.0 - edLod);
        float rib = sin(uv.y * uSetsN * 1.57) * (1.0 - edLod);
        edNrP = normalize(edNr - (Tu * (hu - h0) + Tv * (hv - h0)) * k * 5.0 + (Tu + Tv) * hatch * edThread * 0.1 * k + Tv * rib * (1.0 - edThread) * 0.06 * k);
        edA = vec4(0.5 + 0.12 * hatch * edThread + 0.05 * rib * (1.0 - edThread), 0.5 - 0.1 * edThread, halo, 0.5);
        edB = vec4(0.5, 0.5, 1.0 - 0.55 * clamp(halo * 1.6 - h0, 0.0, 1.0) * (1.0 - edThread), 0.0);
        edThreadC = uThread.rgb;
        edMetalT = uThread.a; edMetalW = edThread;
        edVeinDark = 0.0;
        edTb = normalize(Tu + Tv);
      } else {
        edA = edSet(uv, edL); edB = edSet(uv, edL + 1.0);
        vec2 tn = (edB.xy * 2.0 - 1.0) * k;
        if (edSi == 6) {
          // fur cards: u across the card, v root -> tip
          #ifdef ED_CUTOUT
            if (edB.a < vGlow.y * 0.9 + 0.08) discard;
          #endif
          // strand frame from the card's (u, v): the lock shades as a rounded bundle of strands, not a flat card
          vec3 across = edGrad(edQ0, edQ1, edG0.x, edG1.x, edNr);
          across = normalize(across - edNr * dot(edNr, across) + vec3(0.0, 1e-5, 0.0));
          float tip = smoothstep(0.45, 1.0, vGlow.y);
          edNrP = normalize(edNr + across * ((vGlow.x - 0.5) * 1.2 + (edB.x - 0.5) * 1.1 * (1.0 - edLod)));
          edTb = across;                      // the highlight band runs across the strands
          edAniso = uAniso.z;
          vec3 c = diffuseColor.rgb * mix(0.3, 1.05, smoothstep(0.0, 0.75, vGlow.y)) * (0.68 + 0.64 * edA.r);
          float lum = dot(c, vec3(0.3333));
          diffuseColor.rgb = mix(c, vec3(lum) * vec3(1.25, 1.12, 1.0) * 1.5 + 0.003, tip * 0.5);   // bleached, warmer guard-hair tips
          edAO = mix(0.3, 1.0, smoothstep(0.0, 0.7, vGlow.y));
          edSheenC = clamp(diffuseColor.rgb * 3.0 + 0.01, 0.0, 0.35) * uSheen.x;
          edSheenR = 0.45;
          edRoughAdd = (1.0 - edA.a) * 0.08;
          edA = vec4(0.5, 0.5, edA.b, edA.a); edB.b = 1.0;
        } else if (edSi == 17) {
          // hair ribbons / cards: u across the lock (strand units), v root -> tip; code = where the lock thins out
          #ifdef ED_CUTOUT
            if (edCode > 0.0005 && edB.a < smoothstep(edCode, 1.0, vGlow.y) * 0.94 - 0.02) discard;
          #endif
          edNrP = normalize(edNr + Tu * (edB.x - 0.5) * 2.2 * k);
          edTb = Tu;                          // the highlight band runs across the strands
          edAniso = uAniso.z;
          diffuseColor.rgb *= (0.62 + 0.76 * edA.r) * mix(0.7, 1.0, edB.a);
          edAO = mix(0.6, 1.0, smoothstep(0.0, 0.18, vGlow.y)) * mix(0.75, 1.0, edB.a);
          edSpecAdd = clamp(diffuseColor.rgb * 2.0 + 0.01, 0.0, 0.1) * edB.a;
          edSheenC = clamp(diffuseColor.rgb * 2.0 + 0.008, 0.0, 0.2) * uSheen.x;
          edSheenR = 0.4;
          edA = vec4(0.5, 0.5, 0.0, 0.5); edB.b = 1.0;
        } else {
          edNrP = normalize(edNr + Tu * tn.x + Tv * tn.y);
          if (edSi == 14) {
            // lamellar: lacing cords over small plates; the plate rims wear
            edThread = edB.a;
            edThreadC = uLace.rgb;
            edMetalT = 0.0; edMetalW = edThread;
            edCodeGlow = fract(edCode);
            edEdge = max(edEdge, edA.b * 0.75);
            edVeinDark = 0.0;
          } else if (edSi == 15) {
            // woven bamboo: light (or inner energy) leaks through the pinholes of the plait
            edCodeGlow = fract(edCode);
            edVeinDark = 0.0;
            diffuseColor.rgb *= 1.0 - 0.75 * edB.a;
          } else {
            // gauze: open weave cut from the hemp weave height; a screen-door dither holds its opacity at distance
            float op = clamp(edCode, 0.06, 1.0);
            #ifdef ED_CUTOUT
              float th = 1.0 - op;
              float cov = mix(smoothstep(th - 0.1, th + 0.1, edA.b), op, edLod);
              float dz = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));
              if (cov < dz * 0.96 + 0.02) discard;
            #endif
            edTrans = uTrans.z;
            edWrap = uTrans.x;
            edSheenC = clamp(diffuseColor.rgb * 3.0 + 0.015, 0.0, 0.3) * uSheen.x; edSheenR = uSheen.y;
            edB.a = 0.0;
          }
        }
      }
    } else {
      // texels of the set per pixel: > 1 the detail is sub-pixel (weave and dents fade, their variance becomes roughness)
      edLod = smoothstep(0.8, 5.0, edPix * edScale * uSetsN);
      vec3 p = vRestPos * edScale;
      vec3 w = pow(abs(edNr), vec3(4.0));
      w /= max(1e-4, w.x + w.y + w.z);
      vec4 aX = edSet(p.zy, edL), aY = edSet(p.xz, edL), aZ = edSet(p.xy, edL);
      vec4 bX = edSet(p.zy, edL + 1.0), bY = edSet(p.xz, edL + 1.0), bZ = edSet(p.xy, edL + 1.0);
      edA = aX * w.x + aY * w.y + aZ * w.z;
      edB = bX * w.x + bY * w.y + bZ * w.z;
      float k = uSetBump[edSi] * uBump * edAmt * (edFab ? 1.0 - 0.8 * edLod : 1.0 - 0.35 * edLod);
      vec3 tX = edTn(bX, k), tY = edTn(bY, k), tZ = edTn(bZ, k);
      tX = vec3(tX.xy + edNr.zy, abs(tX.z) * edNr.x);
      tY = vec3(tY.xy + edNr.xz, abs(tY.z) * edNr.y);
      tZ = vec3(tZ.xy + edNr.xy, abs(tZ.z) * edNr.z);
      edNrP = normalize(tX.zyx * w.x + tY.xzy * w.y + tZ.xyz * w.z);
      // detail normals below a pixel: their spread goes into roughness (no sparkling armour at fight distance)
      edRoughAdd += 0.1 * edLod * k * metal;
      if (edSi >= 18) edB.a = 0.0;          // blade / bronze / jade reuse the hammered layers: no vein mask
    }
    float edMicro = mix(1.0, edB.b, edAmt);
    // macro field (one planar lookup, low frequency): vertical grime streaks (A) and soot / dust / dye patches (R)
    // (side / front projections cross-fade over a narrow band of normals: one lookup almost everywhere, never a seam)
    float edMw = smoothstep(-0.12, 0.12, abs(edNr.x) - abs(edNr.z));
    vec4 edMac = vec4(0.0);
    if (edMw > 0.0) edMac = textureLod(uSets, vec3(vRestPos.zy * vec2(1.1, 0.14) + vec2(0.37, 0.11), 0.0), 1.0) * edMw;
    if (edMw < 1.0) edMac += textureLod(uSets, vec3(vRestPos.xy * vec2(1.1, 0.14) + vec2(0.37, 0.11), 0.0), 1.0) * (1.0 - edMw);
    // cloth hems: torn, charred, frayed, ember-lit edges (u, v, code in vGlow)
    float edChar = 0.0, edSoot = 0.0;
    #ifdef ED_CUTOUT
    if (edTorn) {
      vec2 cuv = vGlow.xy;
      float code = vGlow.z;
      float sides = floor(code * 0.5 + 0.01);
      float burn = clamp(code - 2.0 * sides, 0.0, 1.0);
      float e1 = edSet(vec2(cuv.x * 0.83 + 0.13, 0.27), 0.0).a;
      float e2 = edSet(vec2(cuv.x * 3.7 + 0.4, 0.61), 0.0).a;
      float e3 = edSet(vec2(cuv.x * 11.0, 0.13), 0.0).a;
      float rip = pow(clamp(e1 * 1.5 - 0.35, 0.0, 1.0), 2.5);
      float depth = burn * (0.03 + 0.07 * e2 + 0.03 * e3 + 0.42 * rip);
      float d = (1.0 - depth) - cuv.y;
      if (mod(sides, 2.0) > 0.5) {
        float s1 = edSet(vec2(0.71, cuv.y * 1.9), 0.0).a;
        d = min(d, cuv.x - burn * (0.02 + 0.09 * s1 * s1) * smoothstep(0.15, 0.9, cuv.y));
      }
      if (sides > 1.5) {
        float s2 = edSet(vec2(0.37, cuv.y * 2.3 + 0.5), 0.0).a;
        d = min(d, (1.0 - cuv.x) - burn * (0.02 + 0.09 * s2 * s2) * smoothstep(0.15, 0.9, cuv.y));
      }
      float hn = edSet(cuv * vec2(1.1, 1.6) + vec2(0.31, 0.77), 0.0).a;
      float holeT = mix(1.05, 0.86, smoothstep(0.02, 0.3, burn)) - 0.16 * burn * smoothstep(0.35, 1.0, cuv.y);
      d = min(d, (holeT - hn) * 0.45);
      float thread = 0.0;
      if (d < 0.0) {
        // frayed warp threads hanging past the torn line, close-ups only (the fringe shrinks with the pixel footprint)
        float vpix = max(abs(edG0.y), abs(edG1.y));
        float fringe = 0.016 * burn * (0.4 + 0.6 * e3) * (1.0 - smoothstep(0.002, 0.007, vpix));
        float th = abs(fract(cuv.x * 240.0 + e2 * 3.0) - 0.5);
        if (d < -fringe || th > 0.16 * (1.0 + d / max(fringe, 1e-4))) discard;
        thread = 1.0;
      }
      float charK = smoothstep(0.1, 0.45, burn);    // a clean cut frays; only a burnt hem chars and glows
      edChar = max((1.0 - smoothstep(0.0, 0.02 + 0.07 * burn, d)) * burn * charK, thread * charK);
      edSoot = burn * charK * smoothstep(0.3, 1.0, cuv.y) * (0.55 + 0.45 * e2);
      float ember = (1.0 - smoothstep(0.0, 0.006 + 0.004 * burn, max(d, 0.0))) * burn * charK * smoothstep(0.2, 0.55, cuv.y) * (1.0 - 0.7 * thread);
      float fl = 0.65 + 0.35 * sin(uEmber.x * 3.1 + cuv.x * 37.0 + cuv.y * 11.0);
      edEmis += edHot(uGlowB, 0.6 + 0.4 * ember) * ember * fl * 0.6;
    }
    #endif
    // albedo: variation, heat tint near cracks, chipped edge wear, crevice grime and streaks, soot, occlusion
    vec3 base = diffuseColor.rgb * (1.0 + (edA.r - 0.5) * uWear.z * edAmt * 2.0);
    if (edFab) base *= 1.0 + (edMac.r - 0.5) * uWear.z * 0.7;          // uneven dye, fading (the weave itself is sub-pixel)
    float isMetal = smoothstep(0.35, 0.8, metal);
    float bmax = max(base.r, max(base.g, base.b)), bmin = min(base.r, min(base.g, base.b));
    float steel = isMetal * (1.0 - smoothstep(0.22, 0.45, (bmax - bmin) / max(bmax, 1e-4)));   // gold / bronze are saturated
    if (edSi == 2 && uWear.w > 0.0) {
      float heat = edA.b;
      vec3 film = edTemper(heat) * max(bmax, 0.05) * 2.4;
      base = mix(base, film, smoothstep(0.12, 0.5, heat) * uWear.w * 0.62);
    }
    // lacquer: a clear coat over the colour; worn rims show the undercoat
    bool edLacq = edSi == 13 || (edSi == 14 && metal < 0.5);
    float chip = edA.a;
    float edgeW = edEdge * uWear.x;
    float wear = smoothstep(0.5, 0.62, edgeW * 1.1 + (chip - 0.5) * 0.85 * min(1.0, edgeW * 2.5)) * (1.0 - edThread);
    vec3 worn = edSi == 4 ? base * 0.75 : mix(base * 1.7 + 0.025, uWearColor, metal);   // leather burnishes darker
    if (edLacq) worn = uUnder.rgb * (0.7 + 0.6 * edA.r);
    base = mix(base, worn, wear);
    float streak = smoothstep(0.52, 0.85, edMac.a) * (1.0 - abs(edNr.y)) * (1.0 - wear);
    float grime = clamp((1.0 - edOcc) * 1.25 + (1.0 - edMicro) * 0.9 + streak * 0.45, 0.0, 1.0) * uWear.y;
    base = mix(base, base * uGrimeColor, grime);
    base *= mix(1.0, edOcc, 0.45);
    base *= 1.0 - 0.6 * edSoot;
    base = mix(base, vec3(0.014, 0.011, 0.01), edChar * 0.94);
    // embroidery thread / lacing cords over the ground
    base = mix(base, edThreadC * (0.8 + 0.4 * edA.r) * mix(1.0, edOcc, 0.5), edThread);
    // settled dust / ash on up-facing surfaces (lighter, rougher, not metallic)
    float dust = uDust.w * smoothstep(0.3, 0.85, edNr.y) * smoothstep(0.35, 0.75, edMac.r + (1.0 - edMicro) * 0.4) * (1.0 - wear) * (1.0 - edChar);
    base = mix(base, uDust.rgb, dust);
    // ISKA: frost blooming out of the crevices, lame overlaps and plate edges (lacy front, dielectric rime, faint cold glow)
    float frost = 0.0;
    if (uFinish.x > 0.0) {
      float src = (1.0 - edOcc) * 1.5 + edEdge * 0.55 + (1.0 - edMicro) * 0.8 + max(0.0, -edNr.y) * 0.25;
      frost = smoothstep(0.42, 0.62, src * 0.75 + (edMac.a - 0.5) * 0.9 + (edA.a - 0.5) * 0.5) * uFinish.x;
      base = mix(base, uFrostColor * (0.8 + 0.4 * edA.r), frost);
      edMetalMul *= 1.0 - frost;
      float fe = frost * (1.0 - frost) * 4.0;
      edEmis += edHot(uGlowB, 0.35) * fe * 0.05;
    }
    // VORN: oxide patina on the bare steel (storm-violet in the hollows and broad mottled patches; gold stays gilt)
    float patina = 0.0;
    if (uFinish.z > 0.0) {
      patina = steel * uFinish.z * smoothstep(0.35, 0.8, (1.0 - edOcc) * 1.2 + (edMac.r - 0.5) * 1.3 + (1.0 - edMicro) * 0.7 + 0.3) * (1.0 - wear);
      base = mix(base, uPatinaColor * (0.65 + 0.7 * edA.r), patina);
      edRoughAdd += patina * 0.1;
    }
    // aged bronze: verdigris creeping out of the hollows and across mottled patches (matt, chalky, not metallic)
    if (edSi == 19) {
      float verd = uVerd.a * smoothstep(0.5, 0.82, (1.0 - edOcc) * 1.4 + (edMac.r - 0.5) * 2.6 + (1.0 - edMicro) * 1.2 + (edA.a - 0.5) * 1.3 + 0.2) * (1.0 - wear);
      base = mix(base, uVerd.rgb * (0.55 + 0.9 * edA.r), verd);
      edMetalMul *= 1.0 - 0.9 * verd;
      edRoughAdd += 0.32 * verd;
    }
    float edHard = 0.0;
    float edNioi = 0.0;
    if (edSi == 18) {
      // forged blade (u along the blade in metres, v 0 at the cutting edge .. 1 at the back, code = height of the temper
      // line): the hardened edge zone is a pale satin band that reads bright from every angle, closed by a misty,
      // undulating boundary; the body above it is darker, polished, with a flowing forge grain; the very edge is honed
      float bu = vGlow.x, bv = vGlow.y;
      float n1 = textureLod(uDetail, vec2(bu * 0.83, 0.37), 3.5).r, n2 = textureLod(uDetail, vec2(bu * 2.3, 0.71), 2.5).r;
      float line = edCode * (0.66 + 0.68 * n1 + 0.1 * sin(bu * 31.0 + n2 * 9.0));
      float on = step(0.001, edCode);
      edHard = (1.0 - smoothstep(line - 0.025, line + 0.03, bv)) * on;
      edNioi = exp(-pow((bv - line) / 0.045, 2.0)) * on;
      float grain = sin(bv * 52.0 + (n1 - 0.5) * 16.0 + (n2 - 0.5) * 7.0 + (edA.r - 0.5) * 5.0);
      base *= 1.0 + 0.12 * grain * (1.0 - edHard) * (1.0 - edLod);
      vec3 honed = uWearColor * 1.3 + 0.03;
      base = mix(base, honed, edHard * (1.0 - 0.8 * wear));
      base = mix(base, honed * 1.2 + 0.05, edNioi * 0.6);
      edRoughAdd += 0.05 * grain * (1.0 - edHard);
    }
    if (edSi == 20) {
      // jade: clouded and veined, waxy gloss; light sinks in and comes back soft
      float cloud = edMac.r * 0.6 + edA.r * 0.4;
      base *= 0.35 + 1.3 * cloud;
      base = mix(base, base * 0.6 + vec3(0.36, 0.4, 0.34) * bmax, smoothstep(0.56, 0.8, edMac.a * 0.55 + edA.a * 0.45) * 0.55);
      edWrap = 0.4; edTrans = 0.14;
    }
    diffuseColor.rgb = base;
    edRoughMul *= (1.0 + (edA.g - 0.5) * 1.1 * edAmt) * (1.0 - 0.3 * wear * (1.0 - isMetal));
    edRoughAdd += grime * 0.22 + edChar * 0.35 + dust * 0.35;
    edMetalMul *= 1.0 - dust;
    // worn metal edges are polished bright: they catch the rim, the key and the braziers as crisp lines
    edRoughT = mix(0.18, 0.62, frost);
    edRoughW = max(wear * isMetal * 0.85, frost * 0.8);
    if (edSi == 18) {
      // satin temper band (0.4), frosted boundary (0.5), mirror-honed cutting edge (0.1)
      float hone = (1.0 - smoothstep(0.02, 0.07, vGlow.y)) * step(0.001, edCode);
      edRoughT = mix(mix(0.4, 0.5, edNioi), 0.1, hone);
      edRoughW = max(max(edHard, edNioi * 0.8), hone) * 0.92;
    }
    edAO *= mix(1.0, edOcc, 0.85) * mix(1.0, edMicro, 0.45);
    // layered polish: a sharp lobe over the base lobe on clean metal (smoother patches, fresh wear), none under grime
    float smooth_ = smoothstep(0.62, 0.36, edA.g);
    edPolish = clamp(uFinish.w * isMetal * (0.4 + 0.6 * smooth_) * (1.0 - grime) * (1.0 - frost) * (1.0 - dust) + wear * isMetal * 0.4, 0.0, 1.0) * (1.0 - 0.8 * edHard);
    if (edLacq) edPolish = max(edPolish, uUnder.a * (0.55 + 0.45 * smooth_) * (1.0 - grime * 0.8) * (1.0 - wear) * (1.0 - edThread) * (1.0 - dust));
    if (edSi == 20) edPolish = max(edPolish, 0.8 * (1.0 - grime));
    if (edSi == 15) edPolish = max(edPolish, 0.08 * (1.0 - edB.a) * (1.0 - grime));
    // brushed anisotropy: polish lines around the limbs (highlights stretch along them); fresh wear is polished along
    // the edge (highlights stretch across it)
    if (!edUvT && !edFab) {
      vec3 gc = edGrad(edQ0, edQ1, edC0, edC1, edNr);
      float gl = length(gc);
      float onEdge = smoothstep(0.04, 0.3, edEdge) * step(1e-9, gl);
      edTb = normalize(mix(edTb, gc / max(gl, 1e-9), onEdge));
      edAniso = (edSi == 7 ? 0.0 : 1.0) * isMetal * mix(uAniso.x * (1.0 - 0.6 * grime) * (1.0 - smoothstep(0.88, 0.99, abs(edNr.y))), uAniso.y, onEdge * wear) * (1.0 - frost);
    }
    // sheen: fuzz at grazing angles on cloth and quilting, wax on leather, a satin nacre glow on pearl metal
    if (edFab || edSi == 8) {
      edSheenC = clamp(base * 3.0 + 0.012, 0.0, 0.3) * uSheen.x * (1.0 - edChar); edSheenR = uSheen.y;
      edWrap = uTrans.x;
      #ifdef ED_CUTOUT
        edTrans = uTrans.y;
      #endif
      if (edSilk) {
        // satin: the floats run with the warp (bind +Y), so the highlight lies across them and slides over the folds;
        // the lustre takes the colour of the dye; a woven figure (damask) is smoother still
        float fig = edSi == 11 ? edB.a : 0.0;
        edTb = normalize(cross(edNr, vec3(0.0, 1.0, 0.0)) + vec3(1e-4, 0.0, 1e-4));
        edAniso = uAniso.w * (1.0 - edChar);
        edSheenR = 0.42;
        edSheenC *= 0.6;
        edSpecAdd = clamp(base * 1.6 + 0.008, 0.0, 0.09) * uSheen.w * (1.0 + 1.2 * fig) * (1.0 - grime) * (1.0 - edChar);
      }
    }
    if (edSi == 4) { edSheenC = vec3(0.035) * uSheen.z * (1.0 - grime); edSheenR = 0.35; }
    if (edSi == 12) {
      edSheenC = clamp(base * 3.0 + 0.012, 0.0, 0.3) * uSheen.x * (1.0 - edThread); edSheenR = 0.45;
      edWrap = uTrans.x;
      edAniso = 0.35 * edThread;
    }
    if (uFinish.y > 0.0) {
      edSheenC += vec3(0.42, 0.48, 0.62) * 0.22 * uFinish.y * isMetal * (1.0 - frost);
      edSheenR = mix(edSheenR, 0.55, isMetal);
      edFilm = uFinish.y * isMetal * (1.0 - frost);
      edFilmKind = 0.0;
    }
    if (patina > 0.0) { edFilm = patina * 0.8; edFilmKind = 1.0; }
    if (uGlowMode > 0.5 && (!edUv || edCodeGlow > 0.0)) {
      // the vein channel: inner energy seeping through cracks, grooves, the woven figure, embroidery thread, lacing
      float vsrc = edUv ? edCodeGlow : vGlow.y;
      float vein = edThread > 0.0 || edSi == 12 ? edThread : edB.a;
      float halo = edSi == 14 || edSi == 15 ? vein * 0.3 : edA.b;
      float fl = 0.82 + 0.18 * sin(uEmber.x * uEmber.y + edA.a * 9.0 + edA.r * 5.0);
      // pulses climbing through the channel (breathing embers, not a static line)
      float pulse = 1.0 + uPulse.x * sin(uEmber.x * uPulse.y - vRestPos.y * uPulse.z + edA.r * 4.0 + edMac.r * 3.0);
      float core = vsrc * vein;
      edEmis += (edHot(uGlowB, clamp(vein * 1.15, 0.0, 1.0)) * (1.0 + 0.3 * vein) * vsrc
        + edHot(uGlowB, 0.2) * pow(halo, 1.8) * vsrc * uEmber.w * 5.0) * fl * pulse;
      if (!edUv) { edInlayK = vGlow.x; edEyeK = vGlow.z; }
      // glowing fissures are open cracks: dark, rough, not metallic (glowing thread keeps its body)
      float vk = clamp(core * 1.6, 0.0, 1.0) * edVeinDark * (edFab ? 0.0 : 1.0);
      diffuseColor.rgb *= 1.0 - 0.9 * vk;
      edRoughAdd += 0.45 * vk;
      edMetalMul *= 1.0 - 0.8 * vk;
      edPolish *= 1.0 - vk;
    } else if (!edUv) {
      edEmis += vGlow;
    }
    edEmis *= uGlowScale;
  }
`;

// kit BRDF: anisotropic GGX with a second sharp polish lobe, Charlie sheen, wrapped diffuse and thin-cloth transmission;
// idle lights (zero colour: the VFX pool at rest) skip it. Indirect: anisotropic bent-normal IBL, the polish lobe's own
// sharper lookup, sheen, cavity occlusion.
const FRAG_BRDF = /* glsl */ `
float edDGGXA(float aT, float aB, float NoH, float ToH, float BoH) {
  float a2 = aT * aB;
  highp vec3 v = vec3(aB * ToH, aT * BoH, a2 * NoH);
  highp float v2 = dot(v, v);
  float w2 = a2 / v2;
  return RECIPROCAL_PI * a2 * w2 * w2;
}
float edVGGXA(float aT, float aB, float ToV, float BoV, float ToL, float BoL, float NoV, float NoL) {
  float gv = NoL * length(vec3(aT * ToV, aB * BoV, NoV));
  float gl = NoV * length(vec3(aT * ToL, aB * BoL, NoL));
  return saturate(0.5 / (gv + gl));
}
float edCharlie(float r, float NoH) {
  float inv = 1.0 / (r * r);
  float s2 = max(1.0 - NoH * NoH, 0.0078125);
  return (2.0 + inv) * pow(s2, inv * 0.5) / (2.0 * PI);
}
void RE_Direct_ED(const in IncidentLight directLight, const in vec3 geometryPosition, const in vec3 geometryNormal, const in vec3 geometryViewDir, const in vec3 geometryClearcoatNormal, const in PhysicalMaterial material, inout ReflectedLight reflectedLight) {
  if (directLight.color.r + directLight.color.g + directLight.color.b <= 0.0) return;
  vec3 L = directLight.direction, N = geometryNormal, V = geometryViewDir;
  float NoLr = dot(N, L);
  float NoL = saturate(NoLr);
  vec3 diff = material.diffuseColor;
  float sheenMax = max(edSheenC.r, max(edSheenC.g, edSheenC.b));
  diff *= 1.0 - 0.157 * sheenMax;
  // cloth: a soft wrapped terminator, and light coming through a thin sheet lit from behind
  float dif = edWrap > 0.0 ? saturate((NoLr + edWrap) / (1.0 + edWrap)) : NoL;
  dif += edTrans * saturate(-NoLr);
  reflectedLight.directDiffuse += directLight.color * dif * BRDF_Lambert(diff);
  if (NoL <= 0.0) return;
  vec3 irradiance = NoL * directLight.color;
  vec3 H = normalize(L + V);
  float NoV = saturate(dot(N, V)) + 1e-4, NoH = saturate(dot(N, H)), VoH = saturate(dot(V, H));
  vec3 F = F_Schlick(material.specularColor, material.specularF90, VoH);
  float a = pow2(material.roughness);
  float aT = max(a * (1.0 + edAniso), 0.002), aB = max(a * (1.0 - edAniso), 0.002);
  float ToL = dot(edAT, L), ToV = dot(edAT, V), ToH = dot(edAT, H);
  float BoL = dot(edAB, L), BoV = dot(edAB, V), BoH = dot(edAB, H);
  vec3 spec = (F + edSpecAdd) * (edVGGXA(aT, aB, ToV, BoV, ToL, BoL, NoV, NoL) * edDGGXA(aT, aB, NoH, ToH, BoH));
  if (edPolish > 0.0) {
    float a2 = pow2(edPolishR);
    spec = mix(spec, F * (V_GGX_SmithCorrelated(a2, NoL, NoV) * D_GGX(a2, NoH)), edPolish);
  }
  reflectedLight.directSpecular += irradiance * spec;
  if (sheenMax > 0.0) {
    float vis = saturate(1.0 / (4.0 * (NoL + NoV - NoL * NoV)));
    reflectedLight.directSpecular += irradiance * edSheenC * (edCharlie(edSheenR, NoH) * vis);
  }
}
void RE_IndirectSpecular_ED(const in vec3 radiance, const in vec3 irradiance, const in vec3 clearcoatRadiance, const in vec3 geometryPosition, const in vec3 geometryNormal, const in vec3 geometryViewDir, const in vec3 geometryClearcoatNormal, const in PhysicalMaterial material, inout ReflectedLight reflectedLight) {
  vec3 singleScattering = vec3(0.0);
  vec3 multiScattering = vec3(0.0);
  vec3 cosineWeightedIrradiance = irradiance * RECIPROCAL_PI;
  computeMultiscattering(geometryNormal, geometryViewDir, material.specularColor, material.specularF90, material.roughness, singleScattering, multiScattering);
  vec3 totalScattering = singleScattering + multiScattering;
  vec3 diffuse = material.diffuseColor * (1.0 - max(max(totalScattering.r, totalScattering.g), totalScattering.b));
  reflectedLight.indirectSpecular += mix(radiance, edRadP, edPolish) * (singleScattering + edSpecAdd * 0.5 * (1.0 - edPolish));
  reflectedLight.indirectSpecular += multiScattering * cosineWeightedIrradiance;
  reflectedLight.indirectSpecular += irradiance * edSheenC * IBLSheenBRDF(geometryNormal, geometryViewDir, edSheenR);
  reflectedLight.indirectDiffuse += diffuse * cosineWeightedIrradiance;
}
#undef RE_Direct
#undef RE_IndirectSpecular
#define RE_Direct RE_Direct_ED
#define RE_IndirectSpecular RE_IndirectSpecular_ED
`;

// IBL lookups (replaces lights_fragment_maps): anisotropic bent normal, the polish lobe's sharper reflection
const FRAG_IBL = /* glsl */ `
#if defined( RE_IndirectDiffuse ) && defined( USE_ENVMAP ) && defined( STANDARD ) && defined( ENVMAP_TYPE_CUBE_UV )
  iblIrradiance += getIBLIrradiance( geometryNormal );
#endif
#if defined( USE_ENVMAP ) && defined( RE_IndirectSpecular )
  {
    vec3 edC = cross(edAB, geometryViewDir);
    vec3 edBent = dot(edC, edC) > 1e-8 ? normalize(cross(edC, edAB)) : geometryNormal;
    edBent = normalize(mix(edBent, geometryNormal, pow2(pow2(1.0 - edAniso * (1.0 - material.roughness)))));
    radiance += getIBLRadiance( geometryViewDir, edBent, material.roughness );
    edRadP = edPolish > 0.0 ? getIBLRadiance( geometryViewDir, geometryNormal, edPolishR ) : radiance;
  }
#endif
`;

/**
 * Create a kit material for one slot.
 * @param {object} o
 *   color=0xffffff        multiplies the vertex colour            roughness=1, metalness=1   multiplied by surf
 *   envMapIntensity=1     side='front'|'double'                    flatShading=false
 *   detailScale=9         legacy set 0: detail tiles per metre    bump=0.6   normal / bump strength (all sets)
 *   detailMul=1           scales the tiling of every texture set (SET_SCALE per set)
 *   glowScale=1           emissive multiplier
 *   glow                  channel mode: { inlay: [r,g,b], vein: [r,g,b], eye: [r,g,b] } HDR colours (vertex glow = masks)
 *   rim=[0,0,0,3]         fresnel rim: [r, g, b, power] HDR colour (0 = off)
 *   rimFade=[0.1, 0.62]   bind-space heights (m) over which the rim fades in from the floor (scale with the body: a giant
 *                         sets its own)
 *   wear=[0.9, 0.8, 0.35, 0.6]   [edge wear, crevice grime, albedo variation, heat tint] strengths
 *   wearColor=0x8a8d93    bare-metal colour revealed by edge wear; also the honed edge of the `blade` set
 *   grimeColor=[0.28,0.24,0.21]  albedo multiplier in crevices      heatColor=[0.16,0.1,0.18] burnt oxide at a crack's rim
 *   ember=[0, 2.2, 0, 0.05]      [time, flicker speed, -, vein halo glow]
 *   pulse=[0.12, 1.3, 4, 0]      pulses climbing through the vein channel: [amount, speed (rad/s), climb (rad/m), -]
 *   polish=0.35           weight of the sharp polish lobe on clean metal
 *   aniso=[0.45, 0.3, 0.75, 0.5]  anisotropy 0..1: brushed metal, worn edges, fur / hair strands, silk satin
 *   sheen=[1, 0.55, 1, 1] [cloth / fur fuzz, its roughness, leather wax, silk lustre]
 *   thread=[0.5, 0.33, 0.1], threadMetal=1   embroidery thread of the `brocade` set (linear [r,g,b] or hex) + its metalness
 *   lace=[0.25, 0.02, 0.015]     lacing cords of the `lamellar` set
 *   undercoat=[0.16, 0.03, 0.014], lacquer=0.85   colour under worn lacquer rims; gloss of the lacquer clear coat (0..1)
 *   verdigris=[0.07, 0.2, 0.15], verdigrisAmount=1   patina of the `bronze` set
 *   cloth=[0.3, 0.3, 0.45]       [wrapped diffuse of cloth, light through thin cut-out cloth, through gauze]
 *   dust=[0.075, 0.07, 0.064, 0]  settled dust colour + amount on up-facing surfaces
 *   frost=0, frostColor   rime blooming from crevices and edges                pearl=0  nacre film + satin sheen on metal
 *   patina=0, patinaColor oxide patina on bare (unsaturated) steel
 *   shadowBias=0.004      extra shadow normal bias (m) of this material's receivers (on top of the light's)
 *   cutout=false          alpha-tested cloth / fur / hair / gauze (torn hems, strand alpha, open weave); separate program
 */
export function createKitMaterial(o = {}) {
  const mat = new THREE.MeshStandardMaterial({
    color: o.color ?? 0xffffff,
    roughness: o.roughness ?? 1,
    metalness: o.metalness ?? 1,
    envMapIntensity: o.envMapIntensity ?? 1,
    vertexColors: true,
    side: o.side === 'double' || o.cutout ? THREE.DoubleSide : THREE.FrontSide,
    flatShading: !!o.flatShading,
  });
  // every face casts: open shells (pauldron caps, fins, crests) shade what they cover; the receivers' normal bias keeps
  // the lit faces free of acne
  mat.shadowSide = THREE.DoubleSide;
  const lin = (c, def) => {
    if (c === undefined) return new THREE.Color(...def);
    if (Array.isArray(c)) return new THREE.Color(c[0], c[1], c[2]);
    return new THREE.Color(c);
  };
  const v4 = (c, def, w) => { const k = lin(c, def); return new THREE.Vector4(k.r, k.g, k.b, w); };
  const g = o.glow || null;
  const rim = o.rim || [0, 0, 0, 3];
  const wear = o.wear || [0.9, 0.8, 0.35, 0.6];
  const aniso = o.aniso ?? [0.45, 0.3, 0.75, 0.5];
  const sheen = o.sheen ?? [1, 0.55, 1, 1];
  const dust = o.dust ?? [0.075, 0.07, 0.064, 0];
  const cl = o.cloth ?? [0.3, 0.3, 0.45];
  const sets = getTextureSets();
  const uniforms = {
    uDetail: { value: getDetailTexture() },
    uSets: { value: sets },
    uSetsN: { value: sets.image.width },
    uDetailScale: { value: o.detailScale ?? 9 },
    uDetailMul: { value: o.detailMul ?? 1 },
    uBump: { value: o.bump ?? 0.6 },
    uFlash: { value: new THREE.Color(0, 0, 0) },
    uGlowScale: { value: o.glowScale ?? 1 },
    uGlowMode: { value: g ? 1 : 0 },
    uGlowA: { value: lin(g && g.inlay, [0, 0, 0]) },
    uGlowB: { value: lin(g && g.vein, [0, 0, 0]) },
    uGlowC: { value: lin(g && g.eye, [0, 0, 0]) },
    uRim: { value: new THREE.Vector4(rim[0], rim[1], rim[2], rim[3] ?? 3) },
    uRimFade: { value: new THREE.Vector2(...(o.rimFade || [0.1, 0.62])) },
    uWear: { value: new THREE.Vector4(wear[0], wear[1], wear[2], wear[3]) },
    uWearColor: { value: lin(o.wearColor, [0.26, 0.27, 0.29]) },
    uGrimeColor: { value: lin(o.grimeColor, [0.28, 0.24, 0.21]) },
    uHeatColor: { value: lin(o.heatColor, [0.16, 0.1, 0.18]) },
    uEmber: { value: new THREE.Vector4(...(o.ember || [0, 2.2, 0, 0.05])) },
    uPulse: { value: new THREE.Vector4(...(o.pulse || [0.12, 1.3, 4, 0])) },
    uFinish: { value: new THREE.Vector4(o.frost ?? 0, o.pearl ?? 0, o.patina ?? 0, o.polish ?? 0.35) },
    uAniso: { value: new THREE.Vector4(aniso[0] ?? 0.45, aniso[1] ?? 0.3, aniso[2] ?? 0.75, aniso[3] ?? 0.5) },
    uSheen: { value: new THREE.Vector4(sheen[0] ?? 1, sheen[1] ?? 0.55, sheen[2] ?? 1, sheen[3] ?? 1) },
    uDust: { value: new THREE.Vector4(dust[0], dust[1], dust[2], dust[3] ?? 0) },
    uThread: { value: v4(o.thread, [0.5, 0.33, 0.1], o.threadMetal ?? 1) },
    uLace: { value: v4(o.lace, [0.25, 0.02, 0.015], 0) },
    uUnder: { value: v4(o.undercoat, [0.16, 0.03, 0.014], o.lacquer ?? 0.85) },
    uVerd: { value: v4(o.verdigris, [0.07, 0.2, 0.15], o.verdigrisAmount ?? 1) },
    uTrans: { value: new THREE.Vector4(cl[0] ?? 0.3, cl[1] ?? 0.3, cl[2] ?? 0.45, 0) },
    uFrostColor: { value: lin(o.frostColor, [0.6, 0.7, 0.84]) },
    uPatinaColor: { value: lin(o.patinaColor, [0.12, 0.08, 0.2]) },
    uShadowNB: { value: o.shadowBias ?? 0.004 },
    uSetScale: { value: SET_SCALE.slice() },
    uSetBump: { value: SET_BUMP.slice() },
    uSetLayer: { value: SET_LAYER.slice() },
  };
  if (o.wearColor !== undefined && !Array.isArray(o.wearColor)) uniforms.uWearColor.value.set(o.wearColor);
  mat.userData.kit = uniforms;
  if (o.cutout) mat.defines = { ED_CUTOUT: '' };
  mat.onBeforeCompile = (shader) => {
    Object.assign(shader.uniforms, uniforms);
    shader.vertexShader = shader.vertexShader
      .replace('#include <common>', '#include <common>\n' + VERT_PARS)
      .replace('#include <begin_vertex>', '#include <begin_vertex>\n' + VERT_MAIN)
      .replace('#include <defaultnormal_vertex>', '#include <defaultnormal_vertex>\n' + VERT_NORMAL)
      .replace('#include <shadowmap_vertex>', SHADOW_VERTEX);
    shader.fragmentShader = shader.fragmentShader
      .replace('#include <common>', '#include <common>\n' + FRAG_PARS)
      .replace('#include <lights_physical_pars_fragment>', '#include <lights_physical_pars_fragment>\n' + FRAG_BRDF)
      .replace('#include <color_fragment>', '#include <color_fragment>\n' + FRAG_SURFACE)
      .replace('#include <roughnessmap_fragment>', `#include <roughnessmap_fragment>
  if (edSi == 0) roughnessFactor = clamp(roughnessFactor * vSurf.x * (1.0 + (edDet.r - 0.5) * 0.5 * edAmt) + (edDet.g - 0.5) * 0.45 * edAmt, 0.045, 1.0);
  else roughnessFactor = mix(clamp(roughnessFactor * vSurf.x * edRoughMul + edRoughAdd, 0.045, 1.0), edRoughT, edRoughW);
  edPolishR = clamp(roughnessFactor * 0.4, 0.07, 0.3);`)
      .replace('#include <metalnessmap_fragment>', `#include <metalnessmap_fragment>
  metalnessFactor = mix(metalnessFactor * vSurf.y * edMetalMul, edMetalT, edMetalW);`)
      .replace('#include <normal_fragment_maps>', `#include <normal_fragment_maps>
  if (edSi == 0) {
    float edH = edDet.b + (edDet.a - 0.5) * 0.12;
    vec2 edD = vec2(dFdx(edH), dFdy(edH)) * uBump * edAmt;
    normal = edPerturb(-vViewPosition, normal, edD, faceDirection);
  } else {
    normal = normalize(edM * edNrP);
  }
  {
    vec3 edTv = edM * edTb;
    edAT = normalize(edTv - normal * dot(normal, edTv) + vec3(1e-5, 0.0, 0.0));
    edAB = cross(normal, edAT);
  }`)
      .replace('#include <emissivemap_fragment>', `#include <emissivemap_fragment>
  {
    float edNdV = saturate(dot(normal, normalize(vViewPosition)));
    float edFres = pow(1.0 - edNdV, 2.0);
    // inlays and eyes: a hot core where the raised strip faces the eye, deeper colour toward its flanks
    float edProf = 0.8 + 0.35 * edNdV * edNdV;
    edEmis += (edHot(uGlowA, clamp(edInlayK * edProf, 0.0, 1.3)) + edHot(uGlowC, clamp(edEyeK * edProf, 0.0, 1.3))) * uGlowScale;
    totalEmissiveRadiance += edEmis + uFlash * (0.3 + 0.7 * edFres);
    // rim: silhouettes against the dark arena. Faded out near the floor (the grazing tops of the feet / sabatons lit up
    // pale at the fight camera's low angle) and only slightly biased toward up-facing normals (no hot shoulder caps)
    float edRimK = smoothstep(uRimFade.x, uRimFade.y, vRestPos.y) * saturate(0.8 + 0.2 * normal.y - 0.3 * abs(normal.y));
    totalEmissiveRadiance += uRim.rgb * pow(1.0 - edNdV, uRim.w) * edRimK * edOcc;
  }`)
      .replace('#include <lights_physical_fragment>', `#include <lights_physical_fragment>
  if (edFilm > 0.0) {
    // thin oxide / nacre film: the specular colour drifts with the viewing angle (pearl: pastel; patina: violet <-> teal)
    float edF = 1.0 - saturate(dot(normal, normalize(vViewPosition)));
    vec3 edPearl = 0.82 + 0.3 * cos(6.2831 * (vec3(0.0, 0.33, 0.67) + edF * 1.3 + 0.1));
    vec3 edOx = mix(vec3(1.25, 0.85, 1.6), vec3(0.55, 1.15, 1.25), smoothstep(0.15, 0.85, edF));
    material.specularColor *= mix(vec3(1.0), mix(edPearl, edOx, edFilmKind), edFilm);
  }`)
      .replace('#include <lights_fragment_maps>', FRAG_IBL)
      .replace('#include <aomap_fragment>', `#include <aomap_fragment>
  reflectedLight.indirectDiffuse *= edAO;
  reflectedLight.indirectSpecular *= computeSpecularOcclusion(saturate(dot(geometryNormal, geometryViewDir)), edAO, material.roughness);`);
  };
  mat.customProgramCacheKey = () => (o.cutout ? 'edkit-v4-cut' : 'edkit-v4');
  return mat;
}

// ---- glow control ---------------------------------------------------------------------------------------------------

const CHANNELS = { inlay: 'uGlowA', vein: 'uGlowB', eye: 'uGlowC' };
/** Default breathing of the glow channels at rest: [amount (fraction of the intensity), period (game seconds)]. */
export const BREATHE = { inlay: [0.1, 3.7], vein: [0.16, 4.6], eye: [0.07, 3.1] };

/**
 * Runtime control of the emissive channels of a set of kit materials (one character). Colours are HDR linear; nothing
 * recompiles. `update(dtGame, dtReal)` advances the ember flicker clock (game time) and the flare envelopes.
 *
 *   const glow = createGlowControl(char.materials, { inlay: [6, 2, 0.4], vein: [7, 2.2, 0.4], eye: [9, 3.4, 0.9] });
 *   glow.set('vein', [9, 3, 0.5], 1.5);         // colour, intensity
 *   glow.flare('all', 2.5, 0.6);                // +250% for 0.6 s (attack 0.06 s, quadratic release)
 *   glow.gain = 0.4;                            // master multiplier (e.g. KO: cracks cool down)
 *   glow.rim([0.5, 0.65, 1.0], 3.2);           // rim colour / power of every material
 *   glow.breath = 0;                            // steady glow (default 1: every channel breathes slowly at rest)
 *
 * @param {object|THREE.Material[]} materials  { slot: material } (char.materials) or an array
 * @param {object} spec  { inlay, vein, eye: [r,g,b] HDR base colours, slots?: [names] (default: all with channel mode),
 *   breathe?: { inlay: [amount, period s], vein: [...], eye: [...] } slow breathing at rest (default BREATHE) }
 */
export function createGlowControl(materials, spec = {}) {
  const list = (Array.isArray(materials) ? materials : Object.entries(materials)
    .filter(([slot]) => !spec.slots || spec.slots.includes(slot)).map(([, m]) => m))
    .filter((m) => m && m.userData && m.userData.kit);
  const ch = {};
  Object.keys(CHANNELS).forEach((name, k) => {
    const c = spec[name] || [0, 0, 0];
    const b = (spec.breathe && spec.breathe[name]) || BREATHE[name];
    ch[name] = { base: new THREE.Color(c[0], c[1], c[2]), intensity: 1, flare: 0, fT: 1, fDur: 0.5, fAtk: 0.06, breathe: b, phase: k * 2.1 };
  });
  const tmp = new THREE.Color();
  let time = 0;
  const ctl = {
    gain: 1,
    /** Breathing depth (0 = steady, 1 = the spec's amounts). */
    breath: 1,
    channels: ch,
    /** Set a channel's base colour ([r,g,b] HDR | hex | THREE.Color) and intensity multiplier. */
    set(name, color, intensity = 1) {
      const c = ch[name];
      if (!c) return ctl;
      if (color != null) { if (Array.isArray(color)) c.base.setRGB(color[0], color[1], color[2]); else c.base.set(color); }
      c.intensity = intensity;
      ctl.apply();
      return ctl;
    },
    /** Temporary boost: intensity x (1 + amount * envelope) over dur seconds (game time). name: channel | 'all'. */
    flare(name, amount = 2, dur = 0.5, { attack = 0.06 } = {}) {
      for (const n of name === 'all' ? Object.keys(ch) : [name]) {
        const c = ch[n];
        if (!c) continue;
        c.flare = amount; c.fT = 0; c.fDur = Math.max(1e-3, dur); c.fAtk = Math.min(attack, dur * 0.5);
      }
      return ctl;
    },
    /** Fresnel rim of every material: colour [r,g,b] HDR, power (2 broad .. 6 thin). */
    rim(color, power) {
      for (const m of list) {
        const u = m.userData.kit.uRim.value;
        if (color) { u.x = color[0]; u.y = color[1]; u.z = color[2]; }
        if (power) u.w = power;
      }
      return ctl;
    },
    /** Advance flicker time and flare envelopes. */
    update(dtGame = 0) {
      time += dtGame;
      for (const n in ch) {
        const c = ch[n];
        if (c.fT < 1) c.fT = Math.min(1, c.fT + dtGame / c.fDur);
      }
      ctl.apply();
      return ctl;
    },
    /** Write the uniforms now. */
    apply() {
      for (const n in ch) {
        const c = ch[n];
        let env = 0;
        if (c.fT < 1) {
          const t = c.fT * c.fDur;
          env = t < c.fAtk ? t / c.fAtk : (1 - (t - c.fAtk) / Math.max(1e-3, c.fDur - c.fAtk)) ** 2;
        }
        const [amt, per] = c.breathe;
        const ph = (time / per) * Math.PI * 2 + c.phase;
        const br = 1 + ctl.breath * amt * (Math.sin(ph) + 0.3 * Math.sin(2 * ph + 0.9)) / 1.3;  // slow in, quicker out
        tmp.copy(c.base).multiplyScalar(c.intensity * ctl.gain * br * (1 + c.flare * env));
        for (const m of list) m.userData.kit[CHANNELS[n]].value.copy(tmp);
      }
      for (const m of list) m.userData.kit.uEmber.value.x = time;
      return ctl;
    },
    get time() { return time; },
  };
  ctl.apply();
  return ctl;
}

/**
 * Attach a glow control to a Character: char.glow = control, and char.update() also advances it (wraps the method,
 * until the rig calls design hooks itself). spec defaults to the design's `glow` (see createGlowControl).
 */
export function attachGlow(char, spec = char.design && char.design.glow) {
  if (char.glow) return char.glow;
  const ctl = createGlowControl(char.materials, spec || {});
  const update = char.update;
  char.update = function (dtGame, dtReal) {
    const r = update.call(char, dtGame, dtReal);
    ctl.update(dtGame || 0, dtReal || 0);
    return r;
  };
  char.glow = ctl;
  return ctl;
}
