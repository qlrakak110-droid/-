// vfx.pillar: vertical energy columns (eruptions, sky strikes). One instanced template holds two cylinder shells, a
// narrow core and a wide sheath; both are shaped in the vertex shader (rise from the ground or descent from the sky,
// flared base, organic wobble, twist, swelling decay) and shaded volumetrically from the view-facing ratio of the
// cylinder (bright core line, soft shell with rim). Scrolling vertical streak noise, ragged top, noise erosion.
// Looks: fire, frost, volt, eclipse. All pillars share ONE draw call.

import * as THREE from 'three';
import { MeshLayer, gridGeometry, PREMUL, resolveColors, makeColors, axisQuat, opt } from './meshfx.js';
import { GLSL_COMMON, GLSL_VORONOI, CULL } from './glsl.js';
import { toVec3, RENDER_ORDER } from './util.js';

const LOOK_ID = { fire: 0, frost: 1, volt: 2, eclipse: 3 };

/** Look presets (per-call options override any field; see README "Pillar"). */
export const PILLAR_LOOKS = {
  /** eruption: white-hot core, turbulent flame sheath climbing fast, top breaking into licks and dark smoke */
  fire: { palette: 'ember', tailFrom: 'smoke', life: 1.0, radius: 0.55, height: 4.5, rise: 0.12, fade: 0.45, flare: 0.8, twist: 0.6, spin: 1.5, from: 'ground', noise: 0.6, scroll: 6, sheath: 2.1, tailAdditive: 0.15 },
  /** frost column: cold white core inside a crystalline faceted sheath with glints */
  frost: { palette: 'frost', life: 1.1, radius: 0.5, height: 4, rise: 0.1, fade: 0.5, flare: 0.6, twist: 0.25, spin: 0.6, from: 'ground', noise: 0.5, scroll: 2.5, sheath: 2.0, tailAdditive: 0.6 },
  /** sky strike: blinding thin core from the sky, violet sheath with crackling vertical filaments, flicker */
  volt: { palette: 'volt', life: 0.55, radius: 0.3, height: 9, rise: 0.05, fade: 0.25, flare: 1.2, twist: 0.1, spin: 0, from: 'sky', noise: 0.5, scroll: 14, sheath: 2.4, tailAdditive: 1 },
  /** eclipse column: a black occluding core wrapped in a gold-white corona */
  eclipse: { palette: 'eclipse', tailFrom: 'smoke', life: 1.4, radius: 0.6, height: 6, rise: 0.15, fade: 0.55, flare: 0.5, twist: 0.4, spin: 0.8, from: 'ground', noise: 0.5, scroll: 3, sheath: 1.7, tailAdditive: 0 },
};

const LAYOUT = { iPosT: 4, iQuat: 4, iDim: 4, iLife: 4, iTime: 4, iCore: 4, iMid: 4, iTail: 4, iLook: 4 };

const VERT = /* glsl */ `
precision highp float;
uniform float uTime, uTimeReal;
attribute vec4 iPosT, iQuat, iDim, iLife, iTime, iCore, iMid, iTail, iLook;
varying vec4 vA;   // u, y (m), shell, age
varying vec4 vB;   // y / height, decay progress, seed, look
varying vec3 vN, vV;
varying vec4 vCore, vMid, vTail, vL;
${GLSL_COMMON}
void main() {
  float life = abs(iLife.x);
  float age = (iLife.x < 0.0 ? uTimeReal : uTime) - iPosT.w;
  if (life <= 0.0 || age < 0.0 || age >= life) { ${CULL} }
  float t = age / life;
  float u = position.x, v = position.y, shell = position.z;
  float H = iDim.y;
  float rise = max(iTime.x, 1e-3) * (shell > 0.5 ? 1.5 : 1.0);
  float g = outExpo(age / rise);
  float y = iTime.z < 0.5 ? v * H * g : H * (1.0 - (1.0 - v) * g);
  float yn = y / H;
  float td = sat((t - iTime.y) / max(1.0 - iTime.y, 1e-3));
  float R = iDim.x * (shell > 0.5 ? iLook.z : 1.0);
  float wob = vnoise(vec2(u * 4.0 + iLife.z * 13.0, y * 0.9 - age * 2.5)) - 0.5;
  float wob2 = vnoise(vec2(u * 9.0 - iLife.z * 7.0, y * 2.3 - age * 4.0)) - 0.5;
  R *= (1.0 + iDim.z * exp(-yn * 7.0)) * (1.0 + (wob * 0.6 + wob2 * 0.3) * (shell > 0.5 ? iLook.x : 0.15));
  R *= shell > 0.5 ? (0.55 + 0.45 * outCubic(age / (rise * 2.0))) * (1.0 + td * 0.7) : (1.0 - td * 0.9) * (1.0 + 0.6 * exp(-age * 18.0));
  float th = u * TAU + iDim.w * y + iTime.w * age * (shell > 0.5 ? 1.0 : -0.5);
  vec3 radial = vec3(cos(th), 0.0, sin(th));
  vec3 wp = iPosT.xyz + qrot(iQuat, vec3(radial.x * R, y, radial.z * R));
  vec4 mv = viewMatrix * vec4(wp, 1.0);
  gl_Position = projectionMatrix * mv;
  vN = mat3(viewMatrix) * qrot(iQuat, radial);
  vV = -mv.xyz;
  vA = vec4(u, y, shell, age);
  vB = vec4(yn, td, iLife.z, iLife.w);
  vCore = vec4(iCore.rgb * iCore.w, iMid.w);
  vMid = vec4(iMid.rgb * iCore.w, iTail.w);
  vTail = vec4(iTail.rgb * iCore.w, t);
  vL = iLook;
}`;

const FRAG = /* glsl */ `
precision highp float;
uniform sampler2D uNoise, uFlow;
varying vec4 vA, vB;
varying vec3 vN, vV;
varying vec4 vCore, vMid, vTail, vL;
${GLSL_COMMON}
${GLSL_VORONOI}
void main() {
  float u = vA.x, y = vA.y, age = vA.w;
  bool core = vA.z < 0.5;
  float yn = vB.x, td = vB.y, seed = vB.z, t = vTail.w;
  int look = int(vB.w + 0.5);
  float noiseAmt = vL.x, scroll = vL.y;
  float f = abs(dot(normalize(vN), normalize(vV)));
  float st = texture2D(uFlow, vec2(y * 0.22 - age * scroll * 0.12, u * 3.0 + seed)).r;
  float st2 = texture2D(uFlow, vec2(y * 0.6 - age * scroll * 0.3, u * 6.0 + seed * 2.0)).r;
  float fb = texture2D(uNoise, vec2(u * 2.0 + seed, y * 0.22 - age * scroll * 0.06)).r;
  float sw = texture2D(uFlow, vec2(u * 3.0 + seed, y * 0.3 - age * scroll * 0.1)).g;
  // ragged top, soft ground contact
  float top = 1.0 - smoothstep(0.42, 0.95, yn + (fb - 0.5) * 0.7 * noiseAmt + (sw - 0.5) * 0.3);
  float bot = smoothstep(0.0, 0.035, yn);
  float dens, k, gain = 1.0, hot = 0.0, addF, flick = 1.0;
  vec3 extra = vec3(0.0);
  float erodeN = fb * 0.6 + st * 0.4;
  if (core) {
    float w = look == 2 ? 9.0 : 2.4;
    dens = pow(f, w) * (0.55 + 0.75 * st) * (look == 2 ? 1.0 - smoothstep(0.0, 0.35, age) * 0.4 : 1.0);
    k = 0.12 + td * 0.6 + (1.0 - f) * 0.35 + yn * 0.15;
    // fire: white-hot only at the vent, the column above cools to orange (a full-height white tube reads as a lamp)
    if (look == 0) { dens *= 0.8; k += 0.08 + yn * 0.3 - (1.0 - smoothstep(0.0, 0.18, yn)) * 0.08; }
  } else {
    float shellD = smoothstep(0.0, 0.75, f) * (1.0 - f * 0.35);
    dens = shellD * (0.25 + 1.0 * fb * st2) * 0.8;
    k = 0.42 + td * 0.45 + yn * 0.3 * (1.0 - t * 0.5);
    gain = 0.5 + 0.9 * st2;
    if (look == 0) {
      float tongue = smoothstep(0.38, 0.75, sw * 0.65 + st2 * 0.35 + (1.0 - yn) * 0.12);
      dens *= 0.1 + 1.4 * tongue;
      hot = (tongue - 0.5) * 0.25;
      k += yn * 0.45 + (1.0 - tongue) * 0.25;
      erodeN = sw * 0.6 + fb * 0.4;
    } else if (look == 1) {
      vec3 vo = voronoiP(vec2(u * 18.0, y * 2.4 + seed * 7.0), 18.0);
      float crack = 1.0 - smoothstep(0.0, 0.08, vo.y - vo.x);
      gain = 0.45 + 0.9 * h11(vo.z * 91.7) + crack * 0.9;
      erodeN = vo.z * 0.75 + fb * 0.25;
      extra += vCore.rgb * pow(h11(vo.z * 37.0 + floor(age * 14.0)), 12.0) * exp(-vo.x * vo.x * 50.0) * 2.5 * f;
    } else if (look == 2) {
      float fr = floor(age * 30.0);
      float bolts = 0.0;
      for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float c = h11(fi * 7.1 + seed * 3.0) * 12.0;
        float jag = (lnoise(y * 2.2 + fr * 5.0 + fi * 13.0) - 0.5) * 1.4 + (lnoise(y * 9.0 + fr * 3.0) - 0.5) * 0.4;
        float dd = abs(fract((u * 12.0 - c - jag) / 12.0 + 0.5) - 0.5) * 12.0;
        float on = step(0.3, h11(fr * 1.3 + fi * 4.7 + seed));
        bolts += on * (exp(-dd / 0.05) + exp(-dd / 0.35) * 0.15);
      }
      dens *= 0.22;
      k += 0.15;
      flick = 0.7 + 0.3 * h11(fr * 2.3 + seed);
      extra += vCore.rgb * bolts * f * (1.0 - td);
    } else {
      // eclipse corona: bright rim where the shell turns away from the eye
      float rim = pow(1.0 - f, 2.2);
      dens = rim * 1.5 * (0.35 + 0.9 * st2);
      k = 0.35 + td * 0.5 + yn * 0.25 - rim * 0.2;
    }
  }
  float th = mix(-0.2, 1.05, pow(td, 1.1)) + (core ? 0.05 : 0.0);
  float vis = smoothstep(th - 0.1, th + 0.1, erodeN * 0.75 + f * 0.25);
  vec3 rgb = heat3(k - hot, vCore.rgb, vMid.rgb, vTail.rgb, 0.45) * gain * flick;
  float a = sat(dens) * vis * top * bot * vCore.a;
  addF = mix(vMid.a, 1.0, sat(1.0 - k * 1.1));
  if (look == 3 && core) { rgb = vTail.rgb; a = sat(pow(f, 0.6) * 1.2) * top * bot * vis * vCore.a; addF = 0.0; }
  extra *= top * bot * vCore.a;
  if (a <= 0.002 && dot(extra, extra) < 1e-4) discard;
  gl_FragColor = vec4(rgb * a + extra, a * (1.0 - addF));
}`;

/**
 * @param {object} vfx
 * @param {object} shared
 */
export function installPillar(vfx, shared) {
  const { uniforms, textures } = shared;
  const U = { uTime: uniforms.uTime, uTimeReal: uniforms.uTimeReal, uNoise: { value: textures.noise }, uFlow: { value: textures.flow } };
  const layer = new MeshLayer(shared, {
    name: 'pillar', capacity: 16, layout: LAYOUT, geometry: gridGeometry(40, 32, 2), lifeAt: 12, renderOrder: RENDER_ORDER.meshPillar,
    material: new THREE.ShaderMaterial({ vertexShader: VERT, fragmentShader: FRAG, uniforms: U, side: THREE.FrontSide, ...PREMUL }),
  });
  const q = new THREE.Quaternion();
  const C = makeColors();
  layer.visit = (s, age) => {
    if (s.stopping) {
      // stop(): jump to the decay phase now (fade start rewritten so the shader eases out over 0.3 s)
      s.stopping = false;
      const nl = Math.min(s.life, age + 0.3);
      const f = layer.ring.f32, k = s.i * layer.ring.stride;
      f[k + 17] = Math.min(f[k + 17], age / nl);
      layer.setLife(s, nl);
    }
    layer.follow(s, 0);
  };

  /**
   * Vertical energy column. See README "Pillar". Returns { kill(), stop(), follow(obj, offset), alive }.
   */
  function pillar(opts = {}) {
    const lookName = opts.look || 'fire';
    const look = PILLAR_LOOKS[lookName];
    if (!look) throw new Error('vfx.pillar: unknown look "' + lookName + '" (have: ' + Object.keys(PILLAR_LOOKS).join(', ') + ')');
    const life = opt(opts.life, look.life);
    const { slot, handle, f, k } = layer.alloc(life, opts.realtime);
    toVec3(opts.pos, slot.pos);
    if (opts.follow) { slot.follow = opts.follow; if (opts.offset) toVec3(opts.offset, slot.offset); layer.pool.place(slot); }
    axisQuat(opts.dir || [0, 1, 0], q);
    resolveColors(opts, look, C);
    const sc = opt(opts.scale, 1);
    const p = slot.pos;
    f[k] = p.x; f[k + 1] = p.y; f[k + 2] = p.z; f[k + 3] = slot.t0;
    f[k + 4] = q.x; f[k + 5] = q.y; f[k + 6] = q.z; f[k + 7] = q.w;
    f[k + 8] = opt(opts.radius, look.radius) * sc; f[k + 9] = opt(opts.height, look.height) * sc; f[k + 10] = opt(opts.flare, look.flare); f[k + 11] = opt(opts.twist, look.twist) / sc;
    f[k + 12] = opts.realtime ? -life : life; f[k + 13] = 0; f[k + 14] = shared.rng(); f[k + 15] = LOOK_ID[lookName];
    f[k + 16] = opt(opts.rise, look.rise); f[k + 17] = opt(opts.fade, look.fade); f[k + 18] = opt(opts.from, look.from) === 'sky' ? 1 : 0; f[k + 19] = opt(opts.spin, look.spin);
    f[k + 20] = C.core.r; f[k + 21] = C.core.g; f[k + 22] = C.core.b; f[k + 23] = opt(opts.intensity, 1);
    f[k + 24] = C.mid.r; f[k + 25] = C.mid.g; f[k + 26] = C.mid.b; f[k + 27] = opt(opts.alpha, 1);
    f[k + 28] = C.tail.r; f[k + 29] = C.tail.g; f[k + 30] = C.tail.b; f[k + 31] = opt(opts.tailAdditive, look.tailAdditive);
    f[k + 32] = opt(opts.noise, look.noise); f[k + 33] = opt(opts.scroll, look.scroll); f[k + 34] = opt(opts.sheath, look.sheath); f[k + 35] = 0;
    layer.commit(slot);
    return handle;
  }

  return {
    name: 'pillar',
    api: { pillar, pillarLooks: PILLAR_LOOKS },
    update() { layer.update(); },
    clear() { layer.clear(); },
    dispose() { layer.dispose(); },
    layer,
  };
}
