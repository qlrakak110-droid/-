// vfx.slash: crescent slash arcs. One instanced arc-strip template (u along the arc, x across the band) shaped in the
// vertex shader: crescent width profile with soft tips, sweep reveal that follows the blade (each point of the arc is
// "born" when the head passes it and then cools and erodes on its own clock), travel / expansion for projectile waves.
// The fragment shader carries every look in one program (razor, flame, ice, electric, eclipse), so all slashes share
// ONE draw call; an optional refraction twin (same instances) bends the background in post.distortionScene.

import * as THREE from 'three';
import { MeshLayer, gridGeometry, PREMUL, ADDITIVE, resolveColors, makeColors, planeQuat, opt } from './meshfx.js';
import { GLSL_COMMON, GLSL_VORONOI, CULL } from './glsl.js';
import { toVec3, RENDER_ORDER } from './util.js';
import { DEG } from '../core/math.js';

const LOOK_ID = { razor: 0, flame: 1, ice: 2, electric: 3, eclipse: 0 };

/** Look presets: every field can be overridden per call (see README "Slash"). */
export const SLASH_LOOKS = {
  /** clean razor arc: thin white-hot edge, streaked body that breaks into lines along the arc */
  razor: { palette: 'ember', life: 0.34, sweep: 0.07, width: 0.42, over: 0.2, taper: 0.75, peak: 0.62, thin: 0.55, noise: 0.35, noiseScale: 0.55, scroll: 1.4, edgeWidth: 0.05, heat: 0.38, tailAdditive: 1, body: 1.5 },
  /** ragged flame arc: licking tongues off the edge, hot rim, cools into dark smoke (alpha) */
  flame: { palette: 'ember', tailFrom: 'smoke', life: 0.6, sweep: 0.09, width: 0.6, over: 0.75, taper: 0.55, peak: 0.55, thin: 0.25, noise: 0.6, noiseScale: 0.7, scroll: 2.4, edgeWidth: 0.12, heat: 0.42, tailAdditive: 0.05, body: 1.2 },
  /** icy arc: crystalline cells with bright fracture lines and glints; shatters cell by cell */
  ice: { palette: 'frost', life: 0.62, sweep: 0.07, width: 0.45, over: 0.32, taper: 0.8, peak: 0.6, thin: 0.2, noise: 0.55, noiseScale: 1.0, scroll: 0.25, edgeWidth: 0.05, heat: 0.5, tailAdditive: 0.5, body: 1.3 },
  /** electric arc: crackling jagged filaments inside a faint glow band, flickering and re-jagging at 30 Hz */
  electric: { palette: 'volt', life: 0.4, sweep: 0.06, width: 0.45, over: 0.4, taper: 0.6, peak: 0.58, thin: 0.35, noise: 0.5, noiseScale: 0.6, scroll: 2.0, edgeWidth: 0.04, heat: 0.3, tailAdditive: 1, body: 1.4 },
  /** eclipse arc: black occluding body under a gold-white corona edge */
  eclipse: { palette: 'eclipse', tailFrom: 'smoke', life: 0.5, sweep: 0.08, width: 0.5, over: 0.25, taper: 0.7, peak: 0.6, thin: 0.35, noise: 0.4, noiseScale: 0.5, scroll: 1.0, edgeWidth: 0.06, heat: 0.12, tailAdditive: 0, body: 1.6 },
};

const LAYOUT = { iPosT: 4, iQuat: 4, iArc: 4, iLife: 4, iMove: 4, iCore: 4, iMid: 4, iTail: 4, iShape: 4, iLook: 4, iLook2: 4, iLook3: 4 };

const VERT = /* glsl */ `
precision highp float;
uniform float uTime, uTimeReal;
attribute vec4 iPosT, iQuat, iArc, iLife, iMove, iCore, iMid, iTail, iShape, iLook, iLook2, iLook3;
varying vec4 vA;    // u, x (across: -1 inner, 0 edge, > 0 outside), age, t
varying vec4 vB;    // born time of u, sweep, head u, arc length (m)
varying vec4 vC;    // local width (m), look, seed, life
varying vec4 vCore; // core rgb, alpha
varying vec4 vMid;  // mid rgb, tail additive
varying vec4 vTail; // tail rgb, heat (cooling time / life)
varying vec4 vL;    // noise, noise scale, scroll, edge width
varying vec4 vP;    // tip profile, distortion strength, body density power, sweep progress
varying vec2 vRad;  // screen-space outward (radial) direction
${GLSL_COMMON}
void main() {
  float life = abs(iLife.x);
  float age = (iLife.x < 0.0 ? uTimeReal : uTime) - iPosT.w;
  if (life <= 0.0 || age < 0.0 || age >= life) { ${CULL} }
  float t = age / life;
  float u = position.x;
  float x = mix(-1.0, iShape.x, position.y);
  float sweep = max(iLife.y, 1e-3);
  float hx = sat(age / sweep);
  float headU = 1.0 - (1.0 - hx) * (1.0 - hx);              // blade head: fast, easing into the end
  float born = sweep * (1.0 - sqrt(max(1.0 - u, 0.0)));     // when the head passed u
  float pk = clamp(iShape.z, 0.05, 0.95);
  float pu = u < pk ? u / pk : (1.0 - u) / (1.0 - pk);
  float prof = pow(sin(sat(pu) * PI * 0.5), iShape.y);      // crescent: 0 at both tips
  float le = sat((age - born) / max(life - born, 1e-3));
  float k = iLook2.y;
  float tt = k > 1e-3 ? (1.0 - exp(-k * age)) / k : age;
  float S = 1.0 + iMove.w * tt;
  float W = iArc.w * S * prof * (1.0 - iShape.w * le * le); // the body thins toward the edge as it ages
  float R = iArc.z * S;
  float th = mix(iArc.x, iArc.y, u);
  vec2 cs = vec2(cos(th), sin(th));
  float r = max(R + x * W, 0.0);
  vec3 lp = vec3(cs * r, iLook2.z * W * max(-x, 0.0));
  vec3 wp = iPosT.xyz + iMove.xyz * tt + qrot(iQuat, lp);
  vec4 clip = projectionMatrix * viewMatrix * vec4(wp, 1.0);
  gl_Position = clip;
  vec4 c2 = projectionMatrix * viewMatrix * vec4(wp + qrot(iQuat, vec3(cs, 0.0)) * 0.05, 1.0);
  vec2 d = c2.xy / c2.w - clip.xy / clip.w;
  vRad = dot(d, d) > 1e-12 ? normalize(d) : vec2(0.0);
  vA = vec4(u, x, age, t);
  vB = vec4(born, sweep, headU, abs(iArc.y - iArc.x) * R);
  vC = vec4(W, iLife.w, iLife.z, life);
  vCore = vec4(iCore.rgb * iCore.w, iMid.w);
  vMid = vec4(iMid.rgb * iCore.w, iTail.w);
  vTail = vec4(iTail.rgb * iCore.w, iLook2.w);
  vL = iLook;
  vP = vec4(prof, iLook2.x, iLook3.x, hx);
}`;

// shared fragment body: computes rgb, a, addF (and the pieces the distortion twin needs)
const FRAG_BODY = /* glsl */ `
  float u = vA.x, x = vA.y, age = vA.z;
  float born = vB.x, sweep = vB.y, headU = vB.z, arcLen = vB.w;
  float W = max(vC.x, 1e-4), seed = vC.z, life = vC.w;
  int look = int(vC.y + 0.5);
  float prof = vP.x;
  float s = u * arcLen;                       // metres along the arc
  float xm = x * W;                           // metres across (0 at the edge, < 0 inside)
  float behind = (headU - u) * arcLen;        // metres behind the blade head
  float reveal = smoothstep(-0.012, 0.045, behind);
  float sweeping = 1.0 - smoothstep(0.0, 0.08, age - sweep);
  float la = max(age - born, 0.0);
  float le = sat(la / max(life - born, 1e-3));
  float cool = sat(la / max(vTail.w * life, 1e-3));
  float noiseAmt = vL.x, ns = vL.y, scroll = vL.z, edgeW = vL.w;
  vec2 fuv = vec2(s * ns - age * scroll, xm * 0.9 + seed * 7.0);
  float streak = texture2D(uFlow, fuv * vec2(0.5, 1.0)).r;
  float streak2 = texture2D(uFlow, fuv * vec2(1.3, 2.1) + vec2(0.37, 0.11)).r;
  float fb = texture2D(uNoise, vec2(s * ns * 0.7 - age * scroll * 0.3, xm * 1.4) + seed).r;
  float xe = x, gain = 1.0, erodeN = streak * 0.7 + streak2 * 0.3, hot = 0.0, flick = 1.0, glint = 0.0;
  vec3 extra = vec3(0.0);
  if (look == 1) {
    // flame: two scrolling swirl octaves push the edge out into licking tongues; the inside stays dense
    float f1 = texture2D(uFlow, vec2(s * ns * 0.8 + age * scroll * 0.5, xm * 0.7 - age * 1.1) + seed).g;
    float f2 = texture2D(uFlow, vec2(s * ns * 2.2 + age * scroll, xm * 1.9 - age * 2.6) + seed * 3.0).g;
    float tongue = (f1 * 0.62 + f2 * 0.38 - 0.42) * 2.4;
    xe = x - tongue * noiseAmt * (0.25 + 0.75 * sat(1.0 + x));
    gain = 0.6 + 0.8 * f2;
    erodeN = f1 * 0.55 + fb * 0.45;
    hot = sat(tongue) * 0.25;
  } else if (look == 2) {
    // ice: crystalline cells, bright fracture lines, per-cell facet shading and glints; cells vanish whole (shatter)
    vec3 vo = voronoi(vec2(s, xm * 1.6) * ns * 7.0 + seed * 13.0);
    float cid = vo.z;
    float crack = 1.0 - smoothstep(0.0, 0.07, vo.y - vo.x);
    xe = x + (cid - 0.5) * noiseAmt * 0.9 - crack * 0.05;
    gain = (0.45 + 0.9 * h11(cid * 91.7)) + crack * 0.9;
    erodeN = cid * 0.8 + fb * 0.2;
    float gl = pow(h11(cid * 37.0 + floor(age * 14.0)), 30.0) * step(xe, 0.0);
    extra += vCore.rgb * gl * 2.5;
    hot = crack * 0.5;
    glint = 1.0;
  } else if (look == 3) {
    // electric: faint band + three jagged filaments re-drawn at 30 Hz, each flickering on and off
    float fr = floor(age * 30.0);
    float bolts = 0.0;
    for (int i = 0; i < 3; i++) {
      float fi = float(i);
      float base = -0.1 - fi * 0.27;
      float jag = (lnoise(s * 7.0 + fr * 7.13 + fi * 31.0 + seed * 50.0) - 0.5) * 0.55 + (lnoise(s * 29.0 + fr * 3.7 + fi * 17.0) - 0.5) * 0.2;
      float dd = abs(x - base - jag) * W;
      float on = step(0.28, h11(fr * 1.7 + fi * 5.3 + seed * 11.0));
      bolts += on * (exp(-dd / 0.004) + exp(-dd / 0.028) * 0.22) * (1.0 - fi * 0.22);
    }
    xe = x + (lnoise(s * 18.0 + fr * 5.0) - 0.5) * noiseAmt * 0.3;
    gain = 0.3 + 0.35 * streak;
    flick = 0.78 + 0.22 * h11(fr * 3.1 + seed);
    extra += vCore.rgb * bolts * 1.3 * (1.0 - le * le);
    erodeN = streak * 0.5 + fb * 0.5;
  } else {
    gain = 0.42 + 0.95 * streak * (0.6 + 0.4 * streak2);
  }
  // density across the band: 0 at the inner edge, 1 at the cutting edge, a short glow outside it
  float inner = sat(1.0 + xe);
  float edgeness = inner * inner;
  float dens = xe <= 0.0 ? pow(inner, vP.z) : exp(-xe * 7.0) * 0.55;
  float line = exp(-(xe * xe) / (edgeW * edgeW));
  // erosion: rises with local age; the inside and the tips go first, the edge last
  float th = mix(-0.2, 1.08, pow(le, 1.25)) + (1.0 - prof) * 0.25;
  float resist = erodeN * 0.62 + edgeness * 0.28 + line * 0.15;
  float vis = smoothstep(th - 0.06, th + 0.06, resist);
  float smear = exp(-max(behind, 0.0) / (0.12 + arcLen * 0.08)) * sweeping;
  float k = cool + (1.0 - edgeness) * 0.38 - smear * 0.4 - hot;
  vec3 rgb = heat3(k, vCore.rgb, vMid.rgb, vTail.rgb, 0.42) * gain * flick;
  rgb += vCore.rgb * line * (1.25 - cool * 0.85) * flick;
  rgb += vCore.rgb * smear * 0.6;
  float dissolveEdge = (1.0 - smoothstep(th, th + 0.1, resist)) * vis;
  rgb += vCore.rgb * dissolveEdge * (look == 1 ? 0.9 : look == 2 ? 1.2 : 0.4) * (1.0 - le);
  float tips = smoothstep(0.0, 0.22, prof);
  float a = sat(dens * (0.75 + 0.5 * line) + smear * 0.25) * vis * reveal * tips * vCore.a;
  extra *= reveal * tips * vCore.a * mix(1.0, vis, glint);
  float addF = mix(vMid.a, 1.0, sat(1.0 - k * 1.1));
`;

const FRAG = /* glsl */ `
precision highp float;
uniform sampler2D uNoise, uFlow;
varying vec4 vA, vB, vC, vCore, vMid, vTail, vL, vP;
varying vec2 vRad;
${GLSL_COMMON}
${GLSL_VORONOI}
void main() {
${FRAG_BODY}
  if (a <= 0.002 && dot(extra, extra) < 1e-4) discard;
  gl_FragColor = vec4(rgb * a + extra, a * (1.0 - addF));
}`;

const FRAG_DISTORT = /* glsl */ `
precision highp float;
uniform sampler2D uNoise, uFlow;
varying vec4 vA, vB, vC, vCore, vMid, vTail, vL, vP;
varying vec2 vRad;
${GLSL_COMMON}
void main() {
  float u = vA.x, x = vA.y, age = vA.z;
  float born = vB.x, headU = vB.z, arcLen = vB.w, life = vC.w;
  float reveal = smoothstep(-0.01, 0.08, (headU - u) * arcLen);
  float le = sat((age - born) / max(life - born, 1e-3));
  float bell = exp(-pow((x + 0.25) / 0.55, 2.0));
  float n = texture2D(uFlow, vec2(u * arcLen * 0.6 - age, x * 0.5 + vC.z)).r;
  float env = (1.0 - le) * (1.0 - le) * reveal * smoothstep(0.0, 0.3, vP.x);
  gl_FragColor = vec4(vRad * bell * env * vP.y * (0.6 + 0.8 * n), 0.0, 0.0);
}`;

/**
 * @param {object} vfx
 * @param {object} shared
 */
export function installSlash(vfx, shared) {
  const { uniforms, textures } = shared;
  const U = { uTime: uniforms.uTime, uTimeReal: uniforms.uTimeReal, uNoise: { value: textures.noise }, uFlow: { value: textures.flow } };
  const layer = new MeshLayer(shared, {
    name: 'slash', capacity: 24, layout: LAYOUT, geometry: gridGeometry(96, 8), lifeAt: 12, renderOrder: RENDER_ORDER.meshAdd,
    material: new THREE.ShaderMaterial({ vertexShader: VERT, fragmentShader: FRAG, uniforms: U, side: THREE.DoubleSide, ...PREMUL }),
    distortMaterial: new THREE.ShaderMaterial({ vertexShader: VERT, fragmentShader: FRAG_DISTORT, uniforms: U, side: THREE.DoubleSide, ...ADDITIVE }),
  });
  const q = new THREE.Quaternion();
  const vel = new THREE.Vector3(), mid = new THREE.Vector3();
  const C = makeColors();

  layer.visit = (s, age) => {
    if (s.stopping) { s.stopping = false; layer.setLife(s, Math.min(s.life, age + 0.12)); }
    layer.follow(s, 0);
  };

  /**
   * Crescent slash arc. See README "Slash" for every option. Returns { kill(), stop(), follow(obj, offset), alive }.
   */
  function slash(opts = {}) {
    const lookName = opts.look || 'razor';
    const look = SLASH_LOOKS[lookName];
    if (!look) throw new Error('vfx.slash: unknown look "' + lookName + '" (have: ' + Object.keys(SLASH_LOOKS).join(', ') + ')');
    const life = opt(opts.life, look.life);
    const { slot, handle, f, k } = layer.alloc(life, opts.realtime);
    toVec3(opts.pos, slot.pos);
    if (opts.follow) { slot.follow = opts.follow; if (opts.offset) toVec3(opts.offset, slot.offset); layer.pool.place(slot); }
    planeQuat(opts, q);
    resolveColors(opts, look, C);
    const sc = opt(opts.scale, 1);
    const arc = opt(opts.arc, [-80, 80]);
    const a0 = arc[0] * DEG, a1 = arc[1] * DEG;
    // travel: explicit world velocity, plus `speed` along the arc's middle direction (projectile waves)
    if (opts.vel) toVec3(opts.vel, vel); else vel.set(0, 0, 0);
    if (opts.speed) { mid.set(Math.cos((a0 + a1) / 2), Math.sin((a0 + a1) / 2), 0).applyQuaternion(q); vel.addScaledVector(mid, opts.speed); }
    const inten = opt(opts.intensity, 1);
    const p = slot.pos;
    f[k] = p.x; f[k + 1] = p.y; f[k + 2] = p.z; f[k + 3] = slot.t0;
    f[k + 4] = q.x; f[k + 5] = q.y; f[k + 6] = q.z; f[k + 7] = q.w;
    f[k + 8] = a0; f[k + 9] = a1; f[k + 10] = opt(opts.radius, 1.4) * sc; f[k + 11] = opt(opts.width, look.width) * sc;
    f[k + 12] = opts.realtime ? -life : life; f[k + 13] = Math.min(opt(opts.sweep, look.sweep), life * 0.9); f[k + 14] = shared.rng(); f[k + 15] = LOOK_ID[lookName];
    f[k + 16] = vel.x; f[k + 17] = vel.y; f[k + 18] = vel.z; f[k + 19] = opt(opts.expand, 0);
    f[k + 20] = C.core.r; f[k + 21] = C.core.g; f[k + 22] = C.core.b; f[k + 23] = inten;
    f[k + 24] = C.mid.r; f[k + 25] = C.mid.g; f[k + 26] = C.mid.b; f[k + 27] = opt(opts.alpha, 1);
    f[k + 28] = C.tail.r; f[k + 29] = C.tail.g; f[k + 30] = C.tail.b; f[k + 31] = opt(opts.tailAdditive, look.tailAdditive);
    f[k + 32] = opt(opts.over, look.over); f[k + 33] = opt(opts.taper, look.taper); f[k + 34] = opt(opts.peak, look.peak); f[k + 35] = opt(opts.thin, look.thin);
    f[k + 36] = opt(opts.noise, look.noise); f[k + 37] = opt(opts.noiseScale, look.noiseScale) / sc; f[k + 38] = opt(opts.scroll, look.scroll); f[k + 39] = opt(opts.edgeWidth, look.edgeWidth);
    const dist = opt(opts.distort, 0);
    f[k + 40] = dist; f[k + 41] = opt(opts.drag, 0); f[k + 42] = opt(opts.cone, 0); f[k + 43] = opt(opts.heat, look.heat);
    f[k + 44] = opt(opts.body, look.body);
    slot.distort = dist > 0;
    layer.commit(slot);
    return handle;
  }

  return {
    name: 'slash',
    api: { slash, slashLooks: SLASH_LOOKS },
    update() { layer.update(); },
    clear() { layer.clear(); },
    dispose() { layer.dispose(); },
    layer,
  };
}
