// vfx.spikes: lit shards that erupt from the floor (ice crystals, rock spires, magic crystals, magma rock) in a line,
// a cluster or a ring, with staggered timing and an overshooting punch up, a hold, then a shatter (cracks flare, the
// shard dissolves, debris + shard particles + glints fly) or a sink back into the ground.
// One instanced mesh (ONE draw call); three irregular faceted crystal variants are merged in the template and every
// instance collapses the two it does not use. The material is a MeshStandardMaterial extended in onBeforeCompile:
// flat-shaded facets, real lighting (scene lights, pooled VFX lights, scene.environment reflections), plus emissive
// craft: a fresnel rim, parallax interior fractures (noise layers sampled deeper along the view ray: depth inside the
// crystal), environment "refraction" when scene.environment is set, a glowing base, and crack glow before it breaks.

import * as THREE from 'three';
import { InstanceRing } from './instanced.js';
import { GLSL_COMMON } from './glsl.js';
import { toVec3, toColor, sampleRange } from './util.js';
import { opt } from './meshfx.js';
import { makeRng, TAU, DEG } from '../core/math.js';
import { LIB } from './library.js';

const KIND = { ice: 0, rock: 1, crystal: 2, magma: 3 };

/** Per-kind defaults (see README "Spikes"). albedo linear, emit HDR (interior / rim colour). */
export const SPIKE_KINDS = {
  ice: { albedo: [0.012, 0.04, 0.09], rough: 0.2, emit: [0.35, 1.3, 3.2], glow: 0.45, debris: 'ice', palette: 'frost', end: 'shatter' },
  rock: { albedo: [0.15, 0.135, 0.12], rough: 0.9, emit: [0, 0, 0], glow: 0, debris: 'rock', palette: 'dust', end: 'sink' },
  crystal: { albedo: [0.025, 0.007, 0.06], rough: 0.22, emit: [1.6, 0.8, 4], glow: 0.5, debris: 'crystal', palette: 'volt', end: 'shatter' },
  magma: { albedo: [0.05, 0.042, 0.038], rough: 0.85, emit: [8, 3, 0.6], glow: 0.6, debris: 'ember', palette: 'ember', end: 'sink' },
};

const LAYOUT = { iPosT: 4, iQuat: 4, iDim: 4, iTime: 4, iKind: 4, iAlb: 4, iEmit: 4 };

/** Three irregular faceted crystals (base y = 0, tip y = 1, base radius ~1), merged; aVar tags each vertex. */
function crystalGeometry() {
  const rng = makeRng(4242);
  const pos = [], vv = [];
  const conf = [{ n: 6, shoulder: 0.66, tip: [0.06, 0.04] }, { n: 5, shoulder: 0.58, tip: [-0.08, 0.05] }, { n: 7, shoulder: 0.72, tip: [0.03, -0.07] }];
  conf.forEach((c, vi) => {
    const R0 = [], R1 = [];
    for (let i = 0; i < c.n; i++) { R0.push(0.85 + rng() * 0.3); R1.push((0.75 + rng() * 0.3) * 0.9); }
    const ring = (y, R, k) => { const a = (k / c.n) * TAU + (vi * 0.3); return [Math.cos(a) * R[k % c.n], y, Math.sin(a) * R[k % c.n]]; };
    const tri = (a, b, d) => { pos.push(...a, ...b, ...d); vv.push(vi, vi, vi); };
    const tip = [c.tip[0], 1, c.tip[1]];
    for (let k = 0; k < c.n; k++) {
      const a0 = ring(-0.05, R0, k), a1 = ring(-0.05, R0, k + 1);
      const b0 = ring(c.shoulder + (rng() - 0.5) * 0.1, R1, k), b1 = ring(c.shoulder + (rng() - 0.5) * 0.1, R1, k + 1);
      // keep shoulder heights consistent between neighbouring faces
      b0[1] = c.shoulder + Math.sin(k * 2.1 + vi) * 0.05; b1[1] = c.shoulder + Math.sin((k + 1) * 2.1 + vi) * 0.05;
      tri(a0, b0, a1); tri(a1, b0, b1);
      tri(b0, tip, b1);
    }
  });
  const g = new THREE.InstancedBufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('aVar', new THREE.Float32BufferAttribute(vv, 1));
  const tmp = new THREE.BufferGeometry();
  tmp.setAttribute('position', g.getAttribute('position'));
  tmp.computeVertexNormals();
  g.setAttribute('normal', tmp.getAttribute('normal'));
  g.instanceCount = 0;
  return g;
}

const VERT_PARS = /* glsl */ `
uniform float uTime, uTimeReal;
attribute float aVar;
attribute vec4 iPosT, iQuat, iDim, iTime, iKind, iAlb, iEmit;
varying vec4 vSp;      // y (0 base .. 1 tip), crack glow, dissolve threshold, kind
varying vec3 vLocal, vViewL, vAlb;
varying vec4 vEmitK;   // emissive rgb, glow
varying float vRough, vSeed;
${GLSL_COMMON}
`;
const VERT_MOTION = /* glsl */ `
  float sLife = abs(iTime.x);
  float sAge = (iTime.x < 0.0 ? uTimeReal : uTime) - iPosT.w - iDim.z;
  bool sOn = sLife > 0.0 && sAge >= 0.0 && sAge < sLife - iDim.z && abs(aVar - iKind.z) < 0.5;
  float sRise = max(iTime.y, 1e-3);
  float sG = outBack(sAge / sRise, iDim.w);                 // punch up with overshoot
  float sEnd = sat((sAge - iTime.z) / max(iTime.w, 1e-3));  // end phase progress
  float sW = 0.55 + 0.45 * outCubic(sAge / (sRise * 1.4));  // girth fills in just behind the tip
  float sH = sG;
  float sDrop = 0.0, sCrack = 0.0, sDis = -1.0;
  if (iKind.y < 0.5) {
    // shatter: cracks flare over the first 35 %, then the shard dissolves from the inside out, swelling slightly
    sCrack = smoothstep(0.0, 0.35, sEnd) * (1.0 - smoothstep(0.75, 1.0, sEnd));
    sDis = sEnd < 0.3 ? -1.0 : mix(-0.1, 1.1, (sEnd - 0.3) / 0.7);
    sW *= 1.0 + 0.08 * sEnd; sH *= 1.0 + 0.04 * sEnd;
  } else {
    // sink back into the ground, eroding at the end
    sDrop = inQuad(sEnd) * 1.05;
    sDis = sEnd < 0.6 ? -1.0 : mix(-0.1, 1.1, (sEnd - 0.6) / 0.4);
  }
  float sSc = sOn ? 1.0 : 0.0;
  vec3 sP = vec3(position.x * iDim.x * sW, (position.y * sH - (1.0 - min(sG, 1.0)) * 0.35 - sDrop) * iDim.y, position.z * iDim.x * sW) * sSc;
  vec3 sWorld = iPosT.xyz + qrot(iQuat, sP);
  vSp = vec4(position.y, sCrack, sDis, iKind.x);
  vLocal = position * vec3(iDim.x, iDim.y, iDim.x);
  vViewL = qrotInv(iQuat, cameraPosition - sWorld);
  vAlb = iAlb.rgb;
  vRough = iAlb.w;
  vEmitK = iEmit;
  vSeed = iKind.w;
`;
const VERT_NORMAL = /* glsl */ `
  vec3 objectNormal = qrot(iQuat, normal);
  #ifdef USE_TANGENT
    vec3 objectTangent = vec3( tangent.xyz );
  #endif
`;
const VERT_BEGIN = /* glsl */ `
  vec3 transformed = sWorld;
`;

const FRAG_PARS = /* glsl */ `
uniform sampler2D uNoise;
varying vec4 vSp;
varying vec3 vLocal, vViewL, vAlb;
varying vec4 vEmitK;
varying float vRough, vSeed;
`;
// albedo: per-shard variation; frosted, whiter patches climbing from the base of ice
const FRAG_ALBEDO = /* glsl */ `
  {
    float an = texture2D(uNoise, vLocal.xy * 0.9 + vLocal.z * 0.5 + vSeed * 0.7).r;
    diffuseColor.rgb = vAlb * (0.75 + 0.5 * an);
    if (int(vSp.w + 0.5) == 0) diffuseColor.rgb = mix(diffuseColor.rgb, vec3(0.22, 0.3, 0.38), smoothstep(0.62, 0.82, an + (0.2 - vSp.x) * 0.9) * 0.6);
  }
`;
// dissolve (discard) right after the clipping planes, before any shading
const FRAG_DISSOLVE = /* glsl */ `
  float spN = texture2D(uNoise, vLocal.xz * 1.3 + vLocal.y * 0.45 + vSeed).r * 0.65 + texture2D(uNoise, vLocal.xy * 2.1 + vSeed * 0.3).a * 0.35;
  float spTh = vSp.z;
  if (spTh > -0.5 && spN < spTh) discard;
`;
const FRAG_EMISSIVE = /* glsl */ `
  {
    int kind = int(vSp.w + 0.5);
    vec3 V = normalize(vViewPosition);
    float ndv = clamp(dot(normal, V), 0.0, 1.0);
    float fres = pow(1.0 - ndv, 3.0);
    vec3 E = vEmitK.rgb;
    float glow = vEmitK.w;
    float y = vSp.x;
    // parallax interior: noise layers sampled deeper along the local view ray read as fractures inside the crystal
    vec3 vl = normalize(vViewL);
    float inner = 0.0;
    for (int i = 1; i <= 3; i++) {
      float dpt = float(i) * 0.12;
      vec2 uv = (vLocal.xz - vl.xz * dpt) * 1.7 + vec2(vLocal.y * 0.6 - vl.y * dpt, 0.0) + vSeed + float(i) * 0.37;
      float c = texture2D(uNoise, uv).b;
      inner += (1.0 - smoothstep(0.0, 0.06, c)) * (1.0 - float(i) * 0.25);
    }
    float cracksS = 1.0 - smoothstep(0.0, 0.05, texture2D(uNoise, vLocal.xy * 1.6 + vLocal.z * 0.7 + vSeed).b);
    float base = exp(-y * 4.0);
    if (kind == 1) {
      totalEmissiveRadiance += E * cracksS * vSp.y * 2.0;
    } else if (kind == 3) {
      // magma rock: glowing fissures, a hot base
      totalEmissiveRadiance += E * (cracksS * (0.35 + 0.65 * base) * 0.5 + base * 0.08 + cracksS * vSp.y);
    } else {
      // stylised facet lighting: every facet catches a different amount of an implied sky, so the crystal reads as cut
      vec3 nW = inverseTransformDirection(normal, viewMatrix);
      float facet = pow(clamp(dot(nW, normalize(vec3(-0.35, 0.75, 0.55))) * 0.5 + 0.5, 0.0, 1.0), 3.0);
      vec3 rim = E * fres * 0.8;
      vec3 body = E * (inner * 0.5 + base * 0.45 + 0.015) * glow + E * facet * 0.06;
      totalEmissiveRadiance += rim + body + E * (cracksS * vSp.y * 2.2);
      #if defined( USE_ENVMAP ) && defined( ENVMAP_TYPE_CUBE_UV )
        // fake refraction: the environment seen through the crystal, bent by the facets and tinted
        vec3 vW = inverseTransformDirection(V, viewMatrix);
        vec3 rd = refract(-vW, nW, 0.75);
        vec3 envT = textureCubeUV(envMap, envMapRotation * rd, 0.12).rgb;
        totalEmissiveRadiance += envT * normalize(E + 1e-3) * 0.6 * (1.0 - fres);
      #endif
    }
    if (vSp.z > -0.5) totalEmissiveRadiance += (E + vec3(0.6)) * (1.0 - smoothstep(vSp.z, vSp.z + 0.08, spN)) * 2.0;
  }
`;

/**
 * @param {object} vfx
 * @param {object} shared
 */
export function installSpikes(vfx, shared) {
  const { ctx, root, uniforms, textures, rng, clock } = shared;
  const CAP = 64;
  const ring = new InstanceRing(CAP, LAYOUT, crystalGeometry());
  const mat = new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.2, metalness: 0.0, flatShading: true, envMapIntensity: 1.0 });
  mat.onBeforeCompile = (sh) => {
    sh.uniforms.uTime = uniforms.uTime;
    sh.uniforms.uTimeReal = uniforms.uTimeReal;
    sh.uniforms.uNoise = { value: textures.noise };
    sh.vertexShader = sh.vertexShader
      .replace('#include <common>', '#include <common>\n' + VERT_PARS)
      .replace('#include <beginnormal_vertex>', VERT_MOTION + VERT_NORMAL)
      .replace('#include <begin_vertex>', VERT_BEGIN);
    sh.fragmentShader = sh.fragmentShader
      .replace('#include <common>', '#include <common>\n' + FRAG_PARS)
      .replace('#include <clipping_planes_fragment>', '#include <clipping_planes_fragment>\n' + FRAG_DISSOLVE)
      .replace('#include <color_fragment>', '#include <color_fragment>\n' + FRAG_ALBEDO)
      .replace('#include <roughnessmap_fragment>', '#include <roughnessmap_fragment>\n  roughnessFactor = vRough;')
      .replace('#include <emissivemap_fragment>', '#include <emissivemap_fragment>\n' + FRAG_EMISSIVE);
  };
  mat.customProgramCacheKey = () => 'vfx.spikes';
  const mesh = new THREE.Mesh(ring.geometry, mat);
  mesh.frustumCulled = false;
  mesh.visible = false;
  mesh.name = 'vfx.spikes';
  root.add(mesh);

  let maxDeath = -1, maxDeathReal = -1, serial = 1;
  const P = new THREE.Vector3(), D = new THREE.Vector3(), S = new THREE.Vector3(), A = new THREE.Vector3(), O = new THREE.Vector3();
  const qa = new THREE.Quaternion(), qb = new THREE.Quaternion(), alb = new THREE.Color(), emit = new THREE.Color();
  const UP = new THREE.Vector3(0, 1, 0);
  const shardDefs = {};
  function shardDef(kind, E) {
    if (shardDefs[kind]) return shardDefs[kind];
    const c = [E[0] + 0.4, E[1] + 0.4, E[2] + 0.4];
    shardDefs[kind] = {
      tex: 'shard', blend: 'add', count: 10, life: [0.3, 0.8, 1.4], shape: { type: 'sphere', radius: 0.15 }, emit: 'radial', spread: 70, lift: 0.4,
      speed: [1.5, 5.5, 1.3], size: [0.05, 0.16, 2], spin: [4, 14], gravity: -9, drag: 0.8, collide: 'ground', bounce: 0.3, erode: 'erodeLate', erodeChannel: 'cracks',
      color: [[0, c[0] * 2, c[1] * 2, c[2] * 2, 1], [0.15, ...c, 1], [1, E[0] * 0.2, E[1] * 0.2, E[2] * 0.2, 0]],
    };
    return shardDefs[kind];
  }
  const glintDef = { ...LIB.glitter, count: 10, life: [0.3, 0.9], speed: [0.3, 1.5], shape: { type: 'sphere', radius: 0.3 } };
  const dustDef = { ...LIB.dustRing, count: 5, shape: { type: 'ring', radius: 0.15, thickness: 0.1 }, speed: [1, 2.6], size: [0.3, 0.7], life: [0.5, 1.1] };

  /**
   * Shards erupting from the floor. See README "Spikes". Returns { kill(), stop(), alive } (stop() ends the hold now).
   */
  function spikes(opts = {}) {
    const kindName = opts.kind || 'ice';
    const kd = SPIKE_KINDS[kindName];
    if (!kd) throw new Error('vfx.spikes: unknown kind "' + kindName + '" (have: ' + Object.keys(SPIKE_KINDS).join(', ') + ')');
    const realtime = !!opts.realtime;
    const now = realtime ? clock.real : clock.game;
    const sc = opt(opts.scale, 1);
    const pattern = opts.pattern || 'line';
    const n = Math.max(1, Math.min(CAP, Math.round(opt(opts.count, pattern === 'cluster' ? 7 : pattern === 'ring' ? 10 : 7))));
    toVec3(opts.pos, O);
    O.y = opt(opts.y, 0);
    toVec3(opts.dir || [1, 0, 0], D);
    if (opts.facing != null && opts.facing < 0) D.x = -D.x;
    D.y = 0;
    if (D.lengthSq() < 1e-8) D.set(1, 0, 0);
    D.normalize();
    S.crossVectors(UP, D).normalize();
    const hR = opt(opts.height, pattern === 'line' ? [0.7, 1.5] : [0.8, 1.8]);
    const widthK = opt(opts.width, 0.2);
    const stagger = opt(opts.stagger, pattern === 'line' ? 0.04 : 0.025);
    const rise = opt(opts.rise, 0.09), over = opt(opts.overshoot, 2.2), hold = opt(opts.hold, 0.7);
    const end = opt(opts.end, kd.end) === 'sink' ? 1 : 0;
    const endT = opt(opts.endTime, end ? 0.45 : 0.22);
    const tilt = opt(opts.tilt, 16) * DEG;
    const grow = opt(opts.grow, pattern === 'line' ? [0.55, 1.15] : [1, 1]);
    toColor(opt(opts.albedo, kd.albedo), alb);
    toColor(opt(opts.emissive, kd.emit), emit);
    const glow = opt(opts.glow, kd.glow);
    const rough = opt(opts.roughness, kd.rough);
    const s0 = ring.alloc(n);
    const own = serial++;
    const f = ring.f32, st = ring.stride;
    let lastEnd = now;
    const sched = [], parts = [];
    const burstAt = (pt, delay) => vfx.schedule(delay, (v) => {
      if (opts.debris !== false && v.debris) v.debris({ kind: kd.debris, pos: pt.mid, dir: [0, 1, 0], count: Math.round(3 + pt.h * 5), size: [0.04, 0.05 + pt.r * 0.9, 1.6], speed: [1.5, 4.5], spread: 75, shape: { type: 'sphere', radius: pt.h * 0.3 }, realtime });
      if (opts.shards !== false && v.burst) {
        v.burst(shardDef(kindName, [emit.r, emit.g, emit.b]), { pos: pt.mid, dir: [0, 1, 0], count: Math.round(5 + pt.h * 6), realtime });
        v.burst(glintDef, { pos: pt.mid, color: [emit.r * 0.25 + 0.4, emit.g * 0.25 + 0.4, emit.b * 0.25 + 0.4], count: 6, realtime });
      }
    }, { realtime });
    for (let i = 0; i < n; i++) {
      const u = n > 1 ? i / (n - 1) : 0.5;
      let lean = A.set(0, 0, 0), hk = 1, delay = 0;
      if (pattern === 'line') {
        const len = opt(opts.length, 4) * sc;
        P.copy(O).addScaledVector(D, u * len).addScaledVector(S, (rng() - 0.5) * 0.35 * sc);
        lean.copy(D).multiplyScalar(0.6).addScaledVector(S, (rng() - 0.5) * 1.2);
        hk = grow[0] + (grow[1] - grow[0]) * u;
        delay = i * stagger;
      } else if (pattern === 'ring') {
        const a = (i / n) * TAU + rng() * 0.3, rr = opt(opts.radius, 1.2) * sc;
        A.set(Math.cos(a), 0, Math.sin(a));
        P.copy(O).addScaledVector(A, rr * (0.9 + 0.2 * rng()));
        lean.copy(A);
        delay = rng() * stagger * 3;
      } else {
        // cluster: a big centre spike, smaller ones around it leaning outward
        const a = rng() * TAU, rr = i === 0 ? 0 : opt(opts.radius, 0.7) * sc * Math.sqrt(0.2 + 0.8 * rng());
        A.set(Math.cos(a), 0, Math.sin(a));
        P.copy(O).addScaledVector(A, rr);
        lean.copy(A).multiplyScalar(i === 0 ? 0.2 : 1.4);
        hk = i === 0 ? 1.25 : 1 - 0.45 * (rr / Math.max(opt(opts.radius, 0.7) * sc, 1e-3));
        delay = i === 0 ? 0 : stagger * (1 + rng() * 3);
      }
      const h = sampleRange(rng, hR) * hk * sc;
      const r = h * widthK * (0.75 + 0.5 * rng());
      // orientation: lean away from the pattern centre / along the line, plus a random twist around the axis
      lean.y = 0;
      const tl = tilt * (0.5 + 0.5 * rng());
      if (lean.lengthSq() > 1e-6) { lean.normalize(); A.crossVectors(UP, lean).normalize(); qa.setFromAxisAngle(A, -tl); } else qa.identity();
      qb.setFromAxisAngle(UP, rng() * TAU);
      qa.multiply(qb);
      const life = delay + rise + hold + endT + 0.02;
      const j = (s0 + i) % CAP, k = j * st;
      f[k] = P.x; f[k + 1] = P.y; f[k + 2] = P.z; f[k + 3] = now;
      f[k + 4] = qa.x; f[k + 5] = qa.y; f[k + 6] = qa.z; f[k + 7] = qa.w;
      f[k + 8] = r; f[k + 9] = h; f[k + 10] = delay; f[k + 11] = over;
      f[k + 12] = realtime ? -life : life; f[k + 13] = rise; f[k + 14] = rise + hold; f[k + 15] = endT;
      f[k + 16] = KIND[kindName]; f[k + 17] = end; f[k + 18] = Math.floor(rng() * 3); f[k + 19] = rng() * 30;
      const vary = 0.8 + 0.4 * rng();
      f[k + 20] = alb.r * vary; f[k + 21] = alb.g * vary; f[k + 22] = alb.b * vary; f[k + 23] = rough;
      f[k + 24] = emit.r; f[k + 25] = emit.g; f[k + 26] = emit.b; f[k + 27] = glow;
      ring.owner[j] = own;
      lastEnd = Math.max(lastEnd, now + life);
      // ground interaction at the eruption, and the shatter burst
      const pos = [P.x, P.y + 0.02, P.z], mid = [P.x + Math.sin(tl) * lean.x * h * 0.4, P.y + h * 0.45, P.z + Math.sin(tl) * lean.z * h * 0.4];
      if (opts.dust !== false && vfx.burst) sched.push(vfx.schedule(delay, (v) => v.burst(dustDef, { pos, dir: [0, 1, 0], scale: 0.6 + h * 0.5, color: kindName === 'ice' ? [2.6, 3, 3.6] : null, realtime }), { realtime }));
      const pt = { j, mid, h, r, burst: null };
      if (!end) pt.burst = burstAt(pt, delay + rise + hold + endT * 0.3);
      parts.push(pt);
    }
    ring.dirty(s0, n);
    ring.commit();
    mesh.visible = true;
    if (realtime) maxDeathReal = Math.max(maxDeathReal, lastEnd); else maxDeath = Math.max(maxDeath, lastEnd);
    const h = {
      _dead: false,
      get alive() { return !h._dead && (realtime ? clock.real : clock.game) < lastEnd; },
      kill() {
        if (h._dead) return;
        h._dead = true;
        for (const s of sched) s.kill();
        for (const pt of parts) if (pt.burst) pt.burst.kill();
        for (let i = 0; i < n; i++) { const j = (s0 + i) % CAP; if (ring.owner[j] === own) f[j * st + 12] = 0; }
        ring.dirty(s0, n);
      },
      /** end the hold now: every shard that has risen starts its shatter / sink */
      stop() {
        if (h._dead) return;
        const t = (realtime ? clock.real : clock.game);
        for (const pt of parts) {
          const j = pt.j, k = j * st;
          if (ring.owner[j] !== own) continue;
          const age = t - f[k + 3] - f[k + 10];
          const e = Math.max(f[k + 13], age);
          if (e < f[k + 14]) {
            f[k + 14] = e;
            const life = f[k + 10] + e + f[k + 15] + 0.02;
            f[k + 12] = realtime ? -life : life;
            lastEnd = Math.min(lastEnd, Math.max(lastEnd - 1e9, f[k + 3] + life));
            if (pt.burst) { pt.burst.kill(); pt.burst = burstAt(pt, Math.max(0, f[k + 3] + f[k + 10] + e + f[k + 15] * 0.3 - t)); }
          }
        }
        ring.dirty(s0, n);
      },
    };
    shared.track(h);
    return h;
  }

  return {
    name: 'spikes',
    api: { spikes, spikeKinds: SPIKE_KINDS },
    update() {
      ring.commit();
      mesh.visible = clock.game < maxDeath || clock.real < maxDeathReal;
    },
    clear() {
      for (let i = 0; i < CAP; i++) ring.f32[i * ring.stride + 12] = 0;
      ring.dirty(0, CAP);
      ring.commit();
      maxDeath = maxDeathReal = -1;
      mesh.visible = false;
    },
    dispose() { ring.dispose(); mat.dispose(); mesh.removeFromParent(); },
    mesh,
  };
}
