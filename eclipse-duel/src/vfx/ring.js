// vfx.ring: expanding shockwave rings. An instanced polar band (u around, x across the band) expands with an eased
// radius (fast, then slow), its width and colour animate over life and it breaks up with seamless polar noise. Ground
// aligned, camera facing or on any plane; looks: shock (energy), dust (alpha, a low rolling curtain hugging the
// floor), fire, frost (crystalline), volt (crackling filaments). Optional screen refraction through vfx.distort.
// All rings share ONE draw call.

import * as THREE from 'three';
import { MeshLayer, gridGeometry, PREMUL, resolveColors, makeColors, planeQuat, opt, first, second } from './meshfx.js';
import { GLSL_COMMON, GLSL_VORONOI, CULL } from './glsl.js';
import { toVec3, RENDER_ORDER } from './util.js';

const LOOK_ID = { shock: 0, dust: 1, fire: 2, frost: 3, volt: 4 };

/** Look presets (per-call options override any field; see README "Ring"). */
export const RING_LOOKS = {
  /** energy shockwave: hot broken leading edge over a wide soft wake (a thin clean band reads as a UI circle) */
  shock: { palette: 'ember', life: 0.45, radius: [0.2, 3], width: [0.55, 1.5], ease: 4, height: 0.16, fill: 2.2, over: 0.3, noise: 0.65, tiles: 6, edgeWidth: 0.11, erodeStart: 0.15, tailAdditive: 1 },
  /** ground dust wave: billowing alpha band, densest at the rolling front, rises as a low curtain */
  dust: { palette: 'dust', life: 1.1, radius: [0.3, 3.2], width: [0.5, 1.4], ease: 3, height: 0.5, fill: 2.2, over: 0.45, noise: 0.9, tiles: 3, edgeWidth: 0.25, erodeStart: 0.1, tailAdditive: 0 },
  /** fire ring: flame tongues licking outward from a hot front, cooling into smoke */
  fire: { palette: 'ember', tailFrom: 'smoke', life: 0.7, radius: [0.3, 3], width: [0.6, 1.1], ease: 3, height: 0.55, fill: 1.3, over: 0.7, noise: 0.7, tiles: 6, edgeWidth: 0.12, erodeStart: 0.15, tailAdditive: 0.1 },
  /** frost ring: crystalline cells and fracture lines with a cold glowing front */
  frost: { palette: 'frost', life: 0.75, radius: [0.25, 2.8], width: [0.45, 0.9], ease: 4, height: 0.3, fill: 1.4, over: 0.3, noise: 0.6, tiles: 8, edgeWidth: 0.07, erodeStart: 0.2, tailAdditive: 0.55 },
  /** volt ring: jagged crackling filaments running around a faint band, flickering */
  volt: { palette: 'volt', life: 0.4, radius: [0.2, 2.6], width: [0.4, 0.6], ease: 4, height: 0.18, fill: 2, over: 0.45, noise: 0.5, tiles: 7, edgeWidth: 0.05, erodeStart: 0.3, tailAdditive: 1 },
};

const LAYOUT = { iPosT: 4, iQuat: 4, iRad: 4, iLife: 4, iCore: 4, iMid: 4, iTail: 4, iShape: 4, iLook: 4 };

const VERT = /* glsl */ `
precision highp float;
uniform float uTime, uTimeReal;
attribute vec4 iPosT, iQuat, iRad, iLife, iCore, iMid, iTail, iShape, iLook;
varying vec4 vA;    // u, x, age, t
varying vec4 vB;    // radius, band width, seed, look
varying vec4 vCore, vMid, vTail, vL, vS;
${GLSL_COMMON}
void main() {
  float life = abs(iLife.x);
  float age = (iLife.x < 0.0 ? uTimeReal : uTime) - iPosT.w;
  if (life <= 0.0 || age < 0.0 || age >= life) { ${CULL} }
  float t = age / life;
  float e = 1.0 - pow(max(1.0 - t, 0.0), iShape.x);
  float R = mix(iRad.x, iRad.y, e);
  float Wd = mix(iRad.z, iRad.w, e);
  float x = mix(-1.0, iShape.w, position.y);
  float th = position.x * TAU;
  float r = max(R + x * Wd, 0.0);
  vec2 cs = vec2(cos(th), sin(th));
  float h = iShape.y * sat(1.0 + x) * sat(1.0 + x) * (0.5 + 0.5 * e) * (1.0 - smoothstep(0.0, 1.0, x / max(iShape.w, 1e-3)) * 0.5);
  if (iLife.y > 0.5) {
    vec4 mv = viewMatrix * vec4(iPosT.xyz, 1.0);
    mv.xy += cs * r;
    gl_Position = projectionMatrix * mv;
  } else {
    vec3 wp = iPosT.xyz + qrot(iQuat, vec3(cs * r, h));
    gl_Position = projectionMatrix * viewMatrix * vec4(wp, 1.0);
  }
  vA = vec4(position.x, x, age, t);
  vB = vec4(R, Wd, iLife.z, iLife.w);
  vCore = vec4(iCore.rgb * iCore.w, iMid.w);
  vMid = vec4(iMid.rgb * iCore.w, iTail.w);
  vTail = vec4(iTail.rgb * iCore.w, iShape.z);
  vL = iLook;
  vS = vec4(iShape.w, e, 0.0, 0.0);
}`;

const FRAG = /* glsl */ `
precision highp float;
uniform sampler2D uNoise, uFlow;
varying vec4 vA, vB, vCore, vMid, vTail, vL, vS;
${GLSL_COMMON}
${GLSL_VORONOI}
void main() {
  float u = vA.x, x = vA.y, age = vA.z, t = vA.w;
  float R = vB.x, Wd = max(vB.y, 1e-3), seed = vB.z;
  int look = int(vB.w + 0.5);
  float noiseAmt = vL.x, tiles = vL.y, edgeW = vL.z, erodeStart = vL.w;
  float over = vS.x;
  float xm = x * Wd;
  vec2 nuv = vec2(u * tiles, xm * 0.3 - age * 0.2 + seed);
  float n1 = texture2D(uNoise, nuv).r;
  float n2 = texture2D(uNoise, nuv * vec2(3.0, 2.6) + vec2(0.31, age * 0.15)).r;
  float xe = x - (n1 - 0.5) * noiseAmt * 0.7;
  float gain = 0.55 + 0.9 * n2, hot = 0.0, flick = 1.0, glint = 0.0;
  float erodeN = n2 * 0.7 + n1 * 0.3;
  vec3 extra = vec3(0.0);
  float shade = 1.0;
  if (look == 1) {
    // dust: two swirl octaves for billows; brighter tops where the density rises
    float b1 = texture2D(uFlow, vec2(u * tiles, xm * 0.25 - age * 0.35) + seed).g;
    float b2 = texture2D(uFlow, vec2(u * tiles * 2.0, xm * 0.6 - age * 0.6) + seed * 2.0).g;
    xe = x - (b1 - 0.45) * noiseAmt * 1.1;
    gain = (0.1 + 1.1 * smoothstep(0.3, 0.75, b1 * 0.7 + b2 * 0.3)) * (0.6 + 0.5 * n2);
    shade = 0.55 + 0.75 * smoothstep(0.35, 0.8, b2);
    erodeN = b1 * 0.5 + n2 * 0.5;
  } else if (look == 2) {
    float f1 = texture2D(uFlow, vec2(u * tiles, xm * 0.5 - age * 1.6) + seed).g;
    float f2 = texture2D(uFlow, vec2(u * tiles * 2.0, xm * 1.3 - age * 2.8) + seed * 3.0).g;
    float tongue = (f1 * 0.6 + f2 * 0.4 - 0.4) * 2.6;
    xe = x - tongue * noiseAmt * (0.3 + 0.7 * sat(1.0 + x));
    gain = 0.4 + 1.0 * f1 * f2 + 0.2 * n2;
    erodeN = f1 * 0.55 + n1 * 0.45;
    hot = sat(tongue) * 0.25;
  } else if (look == 3) {
    float per = tiles * 3.0;
    vec3 vo = voronoiP(vec2(u * per, xm * 4.0 + seed * 9.0), per);
    float cid = vo.z;
    float crack = 1.0 - smoothstep(0.0, 0.08, vo.y - vo.x);
    xe = x + (cid - 0.5) * noiseAmt * 0.8;
    gain = 0.45 + 0.85 * h11(cid * 91.7) + crack * 0.8;
    erodeN = cid * 0.8 + n2 * 0.2;
    extra += vCore.rgb * pow(h11(cid * 37.0 + floor(age * 14.0)), 12.0) * exp(-vo.x * vo.x * 60.0) * 3.0 * step(xe, 0.0);
    glint = 1.0;
    hot = crack * 0.45;
  } else if (look == 4) {
    float fr = floor(age * 30.0);
    float bolts = 0.0, per = floor(tiles * 6.0);
    for (int i = 0; i < 2; i++) {
      float fi = float(i);
      float jag = (lnoiseP(u * per + fr * 3.0 + fi * 11.0, per) - 0.5) * 0.7 + (lnoiseP(u * per * 4.0 + fr * 7.0, per * 4.0) - 0.5) * 0.25;
      float dd = abs(x + 0.15 + fi * 0.35 - jag) * Wd;
      float on = step(0.25, h11(fr * 1.7 + fi * 5.3 + seed * 11.0));
      bolts += on * (exp(-dd / 0.005) + exp(-dd / 0.03) * 0.2) * (1.0 - fi * 0.3);
    }
    gain = 0.3 + 0.4 * n2;
    flick = 0.75 + 0.25 * h11(fr * 3.1 + seed);
    extra += vCore.rgb * bolts * 1.3 * (1.0 - t * t);
  }
  float inner = sat(1.0 + xe);
  float dens = xe <= 0.0 ? pow(max(inner, 0.0), vTail.w) : exp(-xe * (look == 1 ? 3.0 : 8.0)) * (look == 1 ? 0.9 : 0.5);
  dens *= 1.0 - smoothstep(0.45, 1.0, x / max(over, 1e-3));
  float line = exp(-(xe * xe) / (edgeW * edgeW));
  float te = sat((t - erodeStart) / max(1.0 - erodeStart, 1e-3));
  float th = mix(-0.2, 1.05, pow(max(te, 0.0), 1.2));
  float resist = erodeN * 0.6 + inner * inner * 0.25 + line * 0.15;
  float vis = smoothstep(th - 0.08, th + 0.08, resist);
  float k = 0.3 + t * 0.75 + (1.0 - inner) * 0.3 - line * 0.25 - hot;
  vec3 rgb;
  if (look == 1) {
    rgb = mix(vTail.rgb, mix(vMid.rgb, vCore.rgb, sat(shade - 0.5)), sat(1.0 - t * 0.7)) * shade;
  } else {
    rgb = heat3(k, vCore.rgb, vMid.rgb, vTail.rgb, 0.45) * gain * flick;
    rgb += vCore.rgb * line * (1.0 - t) * flick;
  }
  rgb += vCore.rgb * (1.0 - smoothstep(th, th + 0.1, resist)) * vis * (look == 2 || look == 3 ? 0.8 : 0.0) * (1.0 - t);
  float a = sat(dens * (0.75 + 0.4 * line) * (look == 1 ? gain * 0.75 : 1.0)) * vis * vCore.a;
  extra *= vCore.a * mix(1.0, vis, glint) * smoothstep(-1.0, -0.6, x) * (1.0 - smoothstep(0.0, over, x));
  float addF = mix(vMid.a, 1.0, sat(1.0 - k * 1.1));
  if (look == 1) addF = 0.0;
  if (a <= 0.002 && dot(extra, extra) < 1e-4) discard;
  gl_FragColor = vec4(rgb * a + extra, a * (1.0 - addF));
}`;

/**
 * @param {object} vfx
 * @param {object} shared
 */
export function installRing(vfx, shared) {
  const { uniforms, textures } = shared;
  const U = { uTime: uniforms.uTime, uTimeReal: uniforms.uTimeReal, uNoise: { value: textures.noise }, uFlow: { value: textures.flow } };
  const layer = new MeshLayer(shared, {
    name: 'ring', capacity: 32, layout: LAYOUT, geometry: gridGeometry(128, 6), lifeAt: 12, renderOrder: RENDER_ORDER.meshRing,
    material: new THREE.ShaderMaterial({ vertexShader: VERT, fragmentShader: FRAG, uniforms: U, side: THREE.DoubleSide, ...PREMUL }),
  });
  const q = new THREE.Quaternion();
  const C = makeColors();
  const n = new THREE.Vector3();
  layer.visit = (s, age) => {
    if (s.stopping) { s.stopping = false; layer.setLife(s, Math.min(s.life, age + 0.12)); }
    layer.follow(s, 0);
  };

  /**
   * Expanding shockwave ring. See README "Ring". Returns { kill(), stop(), follow(obj, offset), alive }.
   */
  function ring(opts = {}) {
    const lookName = opts.look || 'shock';
    const look = RING_LOOKS[lookName];
    if (!look) throw new Error('vfx.ring: unknown look "' + lookName + '" (have: ' + Object.keys(RING_LOOKS).join(', ') + ')');
    const life = opt(opts.life, look.life);
    const { slot, handle, f, k } = layer.alloc(life, opts.realtime);
    const orient = opts.normal != null || opts.quat != null ? 'plane' : opts.orient || 'ground';
    toVec3(opts.pos, slot.pos);
    if (orient === 'ground') slot.pos.y = Math.max(slot.pos.y, 0) + opt(opts.lift, 0.025);
    if (opts.follow) { slot.follow = opts.follow; if (opts.offset) toVec3(opts.offset, slot.offset); layer.pool.place(slot); }
    if (orient === 'ground') planeQuat({ normal: [0, 1, 0], forward: [1, 0, 0] }, q); else planeQuat(opts, q, [0, 0, 1]);
    resolveColors(opts, look, C);
    const sc = opt(opts.scale, 1);
    const rad = opt(opts.radius, look.radius), wid = opt(opts.width, look.width);
    const p = slot.pos;
    f[k] = p.x; f[k + 1] = p.y; f[k + 2] = p.z; f[k + 3] = slot.t0;
    f[k + 4] = q.x; f[k + 5] = q.y; f[k + 6] = q.z; f[k + 7] = q.w;
    f[k + 8] = first(rad) * sc; f[k + 9] = second(rad) * sc; f[k + 10] = first(wid) * sc; f[k + 11] = second(wid) * sc;
    f[k + 12] = opts.realtime ? -life : life; f[k + 13] = orient === 'camera' ? 1 : 0; f[k + 14] = shared.rng(); f[k + 15] = LOOK_ID[lookName];
    f[k + 16] = C.core.r; f[k + 17] = C.core.g; f[k + 18] = C.core.b; f[k + 19] = opt(opts.intensity, 1);
    f[k + 20] = C.mid.r; f[k + 21] = C.mid.g; f[k + 22] = C.mid.b; f[k + 23] = opt(opts.alpha, 1);
    f[k + 24] = C.tail.r; f[k + 25] = C.tail.g; f[k + 26] = C.tail.b; f[k + 27] = opt(opts.tailAdditive, look.tailAdditive);
    f[k + 28] = opt(opts.ease, look.ease); f[k + 29] = opt(opts.height, look.height) * sc; f[k + 30] = opt(opts.fill, look.fill); f[k + 31] = opt(opts.over, look.over);
    f[k + 32] = opt(opts.noise, look.noise); f[k + 33] = Math.max(1, Math.round(opt(opts.tiles, look.tiles))); f[k + 34] = opt(opts.edgeWidth, look.edgeWidth); f[k + 35] = opt(opts.erodeStart, look.erodeStart);
    layer.commit(slot);
    // screen refraction: a matching shock band in the distortion buffer (killed with the ring)
    const ds = opt(opts.distort, 0);
    if (ds > 0 && vfx.distort) {
      if (orient === 'camera') n.set(0, 0, 0); else n.set(0, 0, 1).applyQuaternion(q);
      const dh = vfx.distort({ kind: 'shock', pos: p, normal: orient === 'camera' ? null : n.toArray(), radius: [first(rad) * sc, second(rad) * sc], life: life * 0.85, strength: ds, width: 0.22, realtime: opts.realtime, follow: opts.follow, offset: opts.offset });
      const kill = handle.kill;
      handle.kill = () => { kill(); dh.kill(); };
    }
    return handle;
  }

  return {
    name: 'ring',
    api: { ring, ringLooks: RING_LOOKS },
    update() { layer.update(); },
    clear() { layer.clear(); },
    dispose() { layer.dispose(); },
    layer,
  };
}
