// vfx.decal: procedural floor decals (flat instanced quads just above y = 0 with polygon offset; ONE draw call for all).
//   crack   branching ground cracks: a radially stretched, domain-warped polar voronoi network that propagates out
//           from the impact, dark crack interiors with lit lips, a shattered crater, optional emissive magma that
//           cools from white-yellow through orange and red to black
//   scorch  burnt blast mark with radial streaks, a ragged edge and smouldering embers that die out
//   frost   frost spreading from the centre: crystalline lines, milky patches, a cold glowing front and twinkles;
//           melts away with noise erosion
//   rune    (alias 'formation') formation diagram (진법) brushed in ink with inner energy running through it: outer
//           ring, eight groups of three whole / broken bars, a ring of star points joined into constellations, a band
//           of square seal-script glyphs and the black sun at the centre; drawn on layer by layer by a sweeping brush,
//           each layer turning at its own rate, eroding away at the end
//   glow    soft flickering light pool on the floor
//   ink     ink splash: a blot with dry-brush rays and drops, a dying rim of element energy
// Premultiplied output: dark parts occlude (alpha), hot parts add (glow), in the same fragment.

import * as THREE from 'three';
import { MeshLayer, PREMUL, resolveColors, makeColors, opt } from './meshfx.js';
import { makeQuadGeometry } from './instanced.js';
import { GLSL_COMMON, GLSL_VORONOI, CULL } from './glsl.js';
import { toVec3, RENDER_ORDER } from './util.js';

const KIND = { crack: 0, scorch: 1, frost: 2, rune: 3, formation: 3, glow: 4, ink: 5 };

/** Per-kind defaults (per-call options override any field; see README "Decal"). */
export const DECAL_KINDS = {
  crack: { palette: 'ember', radius: 1.8, life: 4, fadeIn: 0, fadeOut: 1.2, reveal: 0.14, cool: 2.2, magma: 0, spin: 0, density: 1, dark: [0.012, 0.01, 0.009] },
  scorch: { palette: 'ember', radius: 1.4, life: 5, fadeIn: 0.05, fadeOut: 1.5, reveal: 0.08, cool: 1.4, magma: 1, spin: 0, density: 1, dark: [0.014, 0.011, 0.009] },
  frost: { palette: 'frost', radius: 2, life: 4, fadeIn: 0, fadeOut: 1.3, reveal: 0.45, cool: 0.6, magma: 1, spin: 0, density: 1, dark: [0.32, 0.44, 0.58] },
  rune: { palette: 'eclipse', radius: 1.6, life: 2.5, fadeIn: 0.1, fadeOut: 0.5, reveal: 0.45, cool: 1, magma: 1, spin: 0.7, density: 1, dark: [0, 0, 0] },
  glow: { palette: 'ember', radius: 2, life: 1, fadeIn: 0.02, fadeOut: 0.7, reveal: 0, cool: 1, magma: 1, spin: 0, density: 1, dark: [0, 0, 0] },
  ink: { palette: 'eclipse', radius: 1.2, life: 5, fadeIn: 0, fadeOut: 1.6, reveal: 0.07, cool: 0.9, magma: 1, spin: 0, density: 1, dark: [0.005, 0.005, 0.007] },
};
/** 'formation' (진법) is the murim name of the diagram; 'rune' stays as the identifier older content uses. */
DECAL_KINDS.formation = DECAL_KINDS.rune;

const LAYOUT = { iPosT: 4, iSize: 4, iLife: 4, iCore: 4, iMid: 4, iTail: 4, iDark: 4, iParam: 4 };

const VERT = /* glsl */ `
precision highp float;
uniform float uTime, uTimeReal;
attribute vec4 iPosT, iSize, iLife, iCore, iMid, iTail, iDark, iParam;
varying vec2 vP;     // unit coordinates (pattern space, rotated)
varying vec4 vA;     // age, life, radius (m), kind
varying vec4 vB;     // fade in, fade out, spin, seed
varying vec4 vCore, vMid, vTail, vDark, vPar;
void main() {
  float life = abs(iLife.x);
  float age = (iLife.x < 0.0 ? uTimeReal : uTime) - iPosT.w;
  if (life <= 0.0 || age < 0.0 || age >= life) { ${CULL} }
  vec2 c = position.xy;
  float R = iSize.x;
  vec3 wp = vec3(iPosT.x + c.x * R, iPosT.y, iPosT.z - c.y * R);
  gl_Position = projectionMatrix * viewMatrix * vec4(wp, 1.0);
  float cr = cos(iSize.y), sr = sin(iSize.y);
  vP = vec2(c.x * cr - c.y * sr, c.x * sr + c.y * cr);
  vA = vec4(age, life, R, iSize.z);
  vB = vec4(iLife.y, iLife.z, iLife.w, iSize.w);
  vCore = vec4(iCore.rgb * iCore.w, iMid.w);
  vMid = vec4(iMid.rgb * iCore.w, iTail.w);
  vTail = vec4(iTail.rgb * iCore.w, 0.0);
  vDark = iDark;
  vPar = iParam;
}`;

const FRAG = /* glsl */ `
precision highp float;
uniform sampler2D uNoise, uFlow;
varying vec2 vP;
varying vec4 vA, vB, vCore, vMid, vTail, vDark, vPar;
${GLSL_COMMON}
${GLSL_VORONOI}
float sdSeg(vec2 p, vec2 a, vec2 b) { vec2 pa = p - a, ba = b - a; float h = sat(dot(pa, ba) / max(dot(ba, ba), 1e-8)); return length(pa - ba * h); }
void main() {
  float age = vA.x, life = vA.y, R = vA.z;
  int kind = int(vA.w + 0.5);
  float fadeIn = vB.x, fadeOut = vB.y, spin = vB.z, seed = vB.w;
  float reveal = vPar.x, cool = vPar.y, magma = vPar.z, dens = vPar.w;
  vec2 p = vP;
  float r = length(p);
  if (r > 1.0) discard;
  vec2 q = p * R;                      // metres
  float rm = r * R;
  float ang = atan(p.y, p.x);
  float fin = fadeIn > 0.0 ? sat(age / fadeIn) : 1.0;
  float fo = sat((age - (life - fadeOut)) / max(fadeOut, 1e-3));   // fade-out progress (erosion)
  float fb = texture2D(uNoise, q * 0.18 + seed).r;
  float fb2 = texture2D(uNoise, q * 0.55 + seed * 1.7).r;
  vec3 dark = vDark.rgb;
  float aDark = 0.0;
  vec3 glow = vec3(0.0);
  if (kind == 0) {
    // ---- cracks: radially stretched polar voronoi, propagating outward -----------------------------------------
    vec2 w = q + (vec2(vnoise(q * 2.2 + seed), vnoise(q * 2.2 + seed + 7.3)) - 0.5) * 0.28;
    float rw = length(w);
    float K = floor(7.0 + 5.0 * dens);
    vec2 pc = vec2((atan(w.y, w.x) / TAU + 0.5) * K, log(rw + 0.2) * 2.1);
    vec3 vo = voronoiP(pc + vec2(0.0, seed * 3.0), K);
    float cell = (rw + 0.2) / 2.1;                         // metres per radial cell unit
    float dm = (vo.y - vo.x) * cell * 0.5;                  // metres to the nearest crack
    // fine shattering in the crater
    vec3 vc = voronoi(q * 9.0 + seed * 5.0);
    float dc = (vc.y - vc.x) / 9.0 * 0.5;
    float crater = 1.0 - smoothstep(0.12, 0.3, r + (fb - 0.5) * 0.15);
    dm = mix(dm, min(dm, dc), crater);
    float front = R * outExpo(age / max(reveal, 1e-3)) * (0.75 + 0.45 * fb);
    float alive = 1.0 - smoothstep(front * 0.85, front, rm);
    float reach = 1.0 - smoothstep(0.55, 1.0, r + (fb2 - 0.5) * 0.35 + vo.z * 0.25);
    float wd = mix(0.028, 0.004, sat(r * 1.15)) * (0.7 + 0.6 * h11(vo.z * 13.0));
    float crack = (1.0 - smoothstep(wd * 0.5, wd, dm)) * alive * reach;
    float lip = (smoothstep(wd * 0.6, wd * 1.4, dm) - smoothstep(wd * 1.4, wd * 3.0, dm)) * alive * reach;
    float th = mix(-0.1, 1.05, fo);
    float vis = smoothstep(th - 0.08, th + 0.08, fb * 0.6 + (1.0 - r) * 0.4);
    aDark = (crack * 0.92 + crater * 0.35 * (0.6 + 0.4 * fb2) + lip * 0.12) * vis;
    dark = mix(dark, vec3(0.06, 0.055, 0.05), lip * (1.0 - crack));
    if (magma > 0.0) {
      float cl = sat(age / max(cool, 1e-3) * (0.6 + 0.9 * r));
      vec3 mc = heat3(cl * 1.1 + 0.1, vCore.rgb, vMid.rgb, vTail.rgb, 0.35) * (1.0 - smoothstep(0.85, 1.0, cl));
      float inner = 1.0 - smoothstep(0.0, wd * 0.9, dm);
      float halo = exp(-dm / (wd * 2.5 + 0.01)) * 0.16 * (1.0 - r);
      glow = mc * (inner * crack + halo * alive * reach + crater * 0.08 * (1.0 - cl)) * magma * vis;
    }
  } else if (kind == 1) {
    // ---- scorch: burnt core, ragged edge, radial blast streaks, smouldering embers ---------------------------------
    float edge = r + (fb - 0.5) * 0.5 + (fb2 - 0.5) * 0.15;
    float burn = 1.0 - smoothstep(0.3, 0.95, edge);
    float rays = texture2D(uFlow, vec2(r * 0.6 - seed, (ang / TAU + 0.5) * 5.0)).r;
    float streak = smoothstep(0.45, 0.85, rays) * smoothstep(0.25, 0.6, r) * (1.0 - smoothstep(0.75, 1.0, r));
    float th = mix(-0.1, 1.05, fo);
    float vis = smoothstep(th - 0.1, th + 0.1, fb * 0.7 + (1.0 - r) * 0.3);
    float grow = outExpo(age / max(reveal, 1e-3));
    aDark = sat(burn * 0.9 + streak * 0.45) * vis * smoothstep(r - 0.05, r + 0.05, grow * 1.05);
    dark = mix(dark, vec3(0.07, 0.045, 0.025), smoothstep(0.35, 0.9, edge));
    float cl = sat(age / max(cool, 1e-3));
    float specks = smoothstep(0.7, 0.85, texture2D(uNoise, q * 1.4 + seed * 3.0).a) * burn;
    float centre = exp(-r * r * 16.0);
    glow = heat3(cl * 1.1 + 0.2, vCore.rgb, vMid.rgb, vTail.rgb, 0.35) * (specks * (1.0 - cl) * 1.1 + centre * (1.0 - cl) * (1.0 - cl) * 0.3) * magma * vis;
  } else if (kind == 2) {
    // ---- frost: crystalline spread with a glowing front, twinkles, melting erosion ----------------------------------
    float front = R * outCubic(age / max(reveal, 1e-3)) * (0.8 + 0.35 * fb);
    float inside = 1.0 - smoothstep(front - 0.18, front, rm);
    vec3 vo = voronoi(q * 3.2 + seed * 4.0);
    float lines = 1.0 - smoothstep(0.0, 0.05, vo.y - vo.x);
    float dendr = smoothstep(0.55, 0.9, texture2D(uFlow, vec2(rm * 0.8 - seed, (ang / TAU + 0.5) * 7.0)).r);
    float patchy = 0.35 + 0.65 * smoothstep(0.25, 0.75, fb2);
    float th = mix(-0.15, 1.05, fo);
    float vis = smoothstep(th - 0.1, th + 0.1, fb * 0.6 + (1.0 - r) * 0.25 + lines * 0.15);
    float edgeFade = 1.0 - smoothstep(0.7, 1.0, r + (fb - 0.5) * 0.3);
    aDark = inside * (patchy * 0.38 + lines * 0.3 + dendr * 0.18) * vis * edgeFade;
    float frontGlow = exp(-pow(abs(rm - front) / 0.12, 2.0)) * (1.0 - smoothstep(reveal, reveal * 1.6, age));
    vec2 gc = floor(q * 9.0);
    vec2 gf = fract(q * 9.0) - 0.5 - (h22(gc + seed) - 0.5) * 0.6;
    float tw = pow(h12(gc + floor(age * 7.0) * 3.1 + seed), 22.0) * exp(-dot(gf, gf) * 120.0);
    glow = vCore.rgb * (lines * 0.1 * inside + frontGlow * 0.28 * edgeFade + tw * 2.5 * inside) * vis + vMid.rgb * dendr * inside * 0.12 * vis;
    dark = mix(dark, dark * 1.25 + 0.1, lines);
  } else if (kind == 3) {
    // ---- formation diagram (진법): brushed in ink on the stone, inner energy running through the strokes. Outer ring,
    //      eight groups of three stacked bars (whole or broken: our own patterns, re-rolled per decal), a ring of star
    //      points joined into small constellations, a band of square seal-script glyphs, the black sun at the centre.
    //      Each layer is drawn on in turn by a sweeping brush and turns at its own rate.
    float t0 = age;
    float sweepA = mod(ang + PI * 0.5, TAU);
    #define ON(k) step(sweepA, sat((t0 - float(k) * reveal * 0.18) / max(reveal, 1e-3)) * TAU + 0.001)
    float d = 1e3;     // hairlines
    float db = 1e3;    // filled brush strokes (distance to their outline, 0 inside)
    db = min(db, max(abs(r - 0.955) - 0.007, 0.0) + (1.0 - ON(0)) * 9.0);
    d = min(d, abs(r - 0.915) + (1.0 - ON(0)) * 9.0);
    {
      float a1 = ang + t0 * spin * 0.45;
      float gu = (a1 / TAU + 0.5) * 8.0;
      float gi = mod(floor(gu), 8.0);
      float al = (fract(gu) - 0.5) * (TAU / 8.0);
      float halfW = TAU / 8.0 * 0.3;
      for (int k = 0; k < 3; k++) {
        float fk = float(k);
        float dr = abs(r - (0.775 + fk * 0.045)) - 0.011;
        float dt = (abs(al) - halfW) * r;
        if (h11(gi * 5.31 + fk * 2.17 + seed) > 0.5) dt = max(dt, (halfW * 0.24 - abs(al)) * r);
        db = min(db, length(max(vec2(dr, dt), 0.0)) + (1.0 - ON(1)) * 9.0);
      }
    }
    d = min(d, abs(r - 0.7) + (1.0 - ON(2)) * 9.0);
    {
      float a2 = ang - t0 * spin * 0.3;
      float su = (a2 / TAU + 0.5) * 12.0;
      float si = floor(su);
      vec2 pr = r * vec2(cos(a2), sin(a2));
      float ds = 1e3, dd = 1e3;
      vec2 prev = vec2(0.0);
      for (int k = -1; k <= 2; k++) {
        float idx = mod(si + float(k), 12.0);
        float sa = ((idx + 0.5 + (h11(idx * 3.7 + seed) - 0.5) * 0.5) / 12.0 - 0.5) * TAU;
        vec2 sp = (0.535 + 0.12 * h11(idx * 9.1 + seed * 1.3)) * vec2(cos(sa), sin(sa));
        dd = min(dd, length(pr - sp) - (0.011 + 0.012 * h11(idx * 5.3 + seed)));
        if (k > -1 && h11(idx * 7.7 + seed * 2.0) > 0.24) ds = min(ds, sdSeg(pr, prev, sp));
        prev = sp;
      }
      d = min(d, ds * 1.25 + (1.0 - ON(2)) * 9.0);
      db = min(db, max(dd, 0.0) + (1.0 - ON(2)) * 9.0);
    }
    d = min(d, abs(r - 0.47) + (1.0 - ON(3)) * 9.0);
    d = min(d, abs(r - 0.33) + (1.0 - ON(3)) * 9.0);
    {
      float a3 = ang + t0 * spin * 0.8;
      float gu = (a3 / TAU + 0.5) * 16.0;
      float gi = mod(floor(gu), 16.0);
      vec2 gp = vec2((fract(gu) - 0.5) * (TAU * 0.4 / 16.0), r - 0.4) / 0.05;
      if (abs(gp.y) < 1.3 && abs(gp.x) < 1.3) {
        float gd = 1e3;
        for (int k = 0; k < 5; k++) {
          float fk = float(k);
          float h1 = h11(gi * 7.13 + fk * 3.7 + seed), h2 = h11(gi * 3.31 + fk * 9.1 + seed * 2.0), h3 = h11(gi * 1.71 + fk * 5.9 + seed * 3.0);
          vec2 ga = vec2(floor(h1 * 3.0) - 1.0, floor(h2 * 3.0) - 1.0);
          vec2 gdir = fract(h3 * 7.0) > 0.5 ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
          vec2 gb = clamp(ga + gdir * (h3 > 0.5 ? 2.0 : 1.0) * (dot(ga, gdir) > 0.5 ? -1.0 : 1.0), -1.0, 1.0);
          gd = min(gd, sdSeg(gp, ga * 0.78, gb * 0.78));
        }
        db = min(db, max(gd * 0.05 - 0.0055, 0.0) + (1.0 - ON(3)) * 9.0);
      }
    }
    float sun = (1.0 - smoothstep(0.12, 0.14, r)) * ON(4);
    db = min(db, max(abs(r - 0.158) - 0.008, 0.0) + (1.0 - ON(4)) * 9.0);
    {
      float ru = ((ang - t0 * spin * 1.2) / TAU + 0.5) * 8.0;
      float tl = abs(fract(ru) - 0.5) / 8.0 * TAU * r;
      if (r > 0.195 && r < (mod(floor(ru), 2.0) < 0.5 ? 0.285 : 0.24)) d = min(d, tl + (1.0 - ON(4)) * 9.0);
    }
    float bn = texture2D(uNoise, q * 1.3 + seed * 2.3).r;              // brush pressure
    float dryN = texture2D(uNoise, q * 3.4 + seed).a;                  // dry-brush grain
    float lw = (0.0032 + 0.0022 * dens) * (1.6 / max(R, 0.5)) * (0.65 + 0.75 * bn);
    float aa = min(fwidth(d), lw * 2.5) + 1e-4;
    float ab = min(fwidth(db), 0.01) + 1e-4;
    float dryM = mix(1.0, smoothstep(0.24, 0.52, dryN * 0.7 + bn * 0.4), 0.75);
    float line = max(1.0 - smoothstep(lw - aa, lw + aa, d), 1.0 - smoothstep(lw * 0.4 - ab, lw * 0.4 + ab, db)) * dryM;
    float dmin = min(d, db);
    float halo = exp(-dmin / 0.016) * 0.12 + exp(-dmin / 0.06) * 0.018;
    float flowP = 0.8 + 0.2 * sin(t0 * 5.0 - r * 14.0 + ang * 2.0);
    float th = mix(-0.15, 1.05, fo);
    float vis = smoothstep(th - 0.08, th + 0.08, fb * 0.65 + fb2 * 0.35);
    // flash of the freshly drawn stroke behind the sweeping brush
    float fresh = exp(-max(sat(t0 / max(reveal, 1e-3)) * TAU - sweepA, 0.0) * 3.0) * (1.0 - step(reveal * 1.8, t0));
    glow = (mix(vMid.rgb, vCore.rgb, 0.2 + 0.8 * fresh) * line * (0.42 + 0.5 * fresh) + vMid.rgb * halo) * flowP * vis * fin;
    glow += vCore.rgb * exp(-pow((r - 0.158) / 0.03, 2.0)) * 0.12 * ON(4) * vis * fin;      // corona of the black sun
    float inkL = max(1.0 - smoothstep(lw * 1.4, lw * 3.4, d), 1.0 - smoothstep(lw * 0.6, lw * 2.6, db)) * (0.55 + 0.45 * dryM);
    aDark = sat(inkL * 0.62 + sun * 0.88) * vis;
    dark = vec3(0.004, 0.004, 0.006);
  } else if (kind == 5) {
    // ---- ink splash: a blot thrown on the stone with dry-brush rays and satellite drops; a rim of element energy
    //      dies out over cool seconds, the ink stays until the erosion takes it
    float rays = texture2D(uFlow, vec2(r * 0.33 - seed, (ang / TAU + 0.5) * 3.0 + seed)).r;
    float rays2 = texture2D(uFlow, vec2(r * 0.6 + seed, (ang / TAU + 0.5) * 7.0)).r;
    float blot = 1.0 - smoothstep(0.16, 0.4, r + (fb - 0.5) * 0.4);
    float reach = 1.0 - smoothstep(0.5, 1.0, r + (fb2 - 0.5) * 0.35);
    float strokes = smoothstep(0.5, 0.66, rays * 0.7 + rays2 * 0.3) * reach * smoothstep(0.08, 0.3, r);
    float drops = smoothstep(0.86, 0.93, texture2D(uNoise, q * 2.6 + seed * 2.0).g) * reach * smoothstep(0.3, 0.5, r);
    float grow = outExpo(age / max(reveal, 1e-3));
    float th = mix(-0.1, 1.05, fo);
    float vis = smoothstep(th - 0.1, th + 0.1, fb * 0.7 + (1.0 - r) * 0.3) * smoothstep(r - 0.08, r + 0.02, grow * 1.1);
    aDark = sat(blot * 0.94 + strokes * 0.85 + drops * 0.8) * vis;
    float cl = sat(age / max(cool, 1e-3));
    float rim = sat(blot * (1.0 - blot) * 4.0) + strokes * 0.5;
    glow = mix(vCore.rgb, vMid.rgb, sat(cl * 2.0)) * rim * (1.0 - cl) * (1.0 - cl) * 0.55 * magma * vis;
  } else {
    // ---- soft light pool ---------------------------------------------------------------------------------------------
    float fl = 0.85 + 0.15 * sin(age * 17.0 + seed * 9.0) * sin(age * 7.3);
    float I = exp(-r * r * 4.0) * (0.75 + 0.5 * fb) * (1.0 - smoothstep(0.8, 1.0, r));
    glow = mix(vMid.rgb, vCore.rgb, exp(-r * r * 14.0) * 0.5) * I * fl * (1.0 - fo) * fin;
  }
  float a = sat(aDark) * fin * vCore.a;
  glow *= vCore.a;
  if (a <= 0.002 && dot(glow, glow) < 1e-5) discard;
  gl_FragColor = vec4(dark * a + glow, a);
}`;

/**
 * @param {object} vfx
 * @param {object} shared
 */
export function installDecal(vfx, shared) {
  const { uniforms, textures, util } = shared;
  const U = { uTime: uniforms.uTime, uTimeReal: uniforms.uTimeReal, uNoise: { value: textures.noise }, uFlow: { value: textures.flow } };
  const geo = makeQuadGeometry();
  const layer = new MeshLayer(shared, {
    name: 'decal', capacity: 48, layout: LAYOUT, geometry: geo, lifeAt: 8, renderOrder: RENDER_ORDER.meshAlpha,
    material: new THREE.ShaderMaterial({
      vertexShader: VERT, fragmentShader: FRAG, uniforms: U, ...PREMUL,
      polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -4,
    }),
  });
  const C = makeColors();
  const dk = new THREE.Color();
  layer.visit = (s, age) => {
    if (s.stopping) {
      // stop(): start the fade-out now
      s.stopping = false;
      const f = layer.ring.f32, k = s.i * layer.ring.stride;
      const fo = f[k + 10];
      layer.setLife(s, Math.min(s.life, age + fo));
    }
    if (layer.pool.place(s)) {
      const f = layer.ring.f32, k = s.i * layer.ring.stride;
      f[k] = s.pos.x; f[k + 2] = s.pos.z;
      layer.ring.dirty(s.i, 1);
    }
  };

  /**
   * Floor decal at y = 0. See README "Decal". Returns { kill(), stop(), follow(obj, offset), alive }.
   */
  function decal(opts = {}) {
    const kindName = opts.kind || 'crack';
    const d = DECAL_KINDS[kindName];
    if (!d) throw new Error('vfx.decal: unknown kind "' + kindName + '" (have: ' + Object.keys(DECAL_KINDS).join(', ') + ')');
    const life = opt(opts.life, d.life);
    const { slot, handle, f, k } = layer.alloc(life, opts.realtime);
    toVec3(opts.pos, slot.pos);
    if (opts.follow) { slot.follow = opts.follow; if (opts.offset) toVec3(opts.offset, slot.offset); layer.pool.place(slot); }
    resolveColors(opts, d, C);
    util.toColor(opt(opts.dark, d.dark), dk);
    const sc = opt(opts.scale, 1);
    const fadeOut = Math.min(opt(opts.fadeOut, d.fadeOut), life);
    const magma = opts.magma === true ? 1 : opts.magma === false ? 0 : opt(opts.magma, d.magma);
    f[k] = slot.pos.x; f[k + 1] = opt(opts.y, 0) + 0.006; f[k + 2] = slot.pos.z; f[k + 3] = slot.t0;
    f[k + 4] = opt(opts.radius, d.radius) * sc; f[k + 5] = opt(opts.rotation, shared.rng() * Math.PI * 2); f[k + 6] = KIND[kindName]; f[k + 7] = shared.rng() * 50;
    f[k + 8] = opts.realtime ? -life : life; f[k + 9] = opt(opts.fadeIn, d.fadeIn); f[k + 10] = fadeOut; f[k + 11] = opt(opts.spin, d.spin);
    f[k + 12] = C.core.r; f[k + 13] = C.core.g; f[k + 14] = C.core.b; f[k + 15] = opt(opts.intensity, 1);
    f[k + 16] = C.mid.r; f[k + 17] = C.mid.g; f[k + 18] = C.mid.b; f[k + 19] = opt(opts.alpha, 1);
    f[k + 20] = C.tail.r; f[k + 21] = C.tail.g; f[k + 22] = C.tail.b; f[k + 23] = 0;
    f[k + 24] = dk.r; f[k + 25] = dk.g; f[k + 26] = dk.b; f[k + 27] = 0;
    f[k + 28] = opt(opts.reveal, d.reveal); f[k + 29] = opt(opts.cool, d.cool); f[k + 30] = magma; f[k + 31] = opt(opts.density, d.density);
    layer.commit(slot);
    return handle;
  }

  return {
    name: 'decal',
    api: { decal, decalKinds: DECAL_KINDS },
    update() { layer.update(); },
    clear() { layer.clear(); },
    dispose() { layer.dispose(); },
    layer,
  };
}
