// vfx.debris: chunky lit fragments. One instanced mesh (ONE draw call) of faceted chunks: three irregular shape
// variants are merged into the template and every instance collapses the two it does not use, so chunks vary in shape
// as well as size and proportions. The material is a MeshStandardMaterial extended in onBeforeCompile, so the chunks
// take the scene's lights (including the pooled VFX lights) and scene.environment. Motion is analytic in the vertex
// shader (written once at spawn, no per-chunk CPU work after): ballistic flight with drag, exact bounces on the floor
// (the chunk's centre rests at its radius), spin that dies on landing, a quick pop-in and a shrink-out at the end.
// Kinds: rock, ice (cold fresnel rim), ember (hot glowing cracks that cool to black), crystal (inner glow).
// Optional dust puffs where the bigger chunks first land.

import * as THREE from 'three';
import { InstanceRing } from './instanced.js';
import { GLSL_COMMON, GLSL_BALLISTIC } from './glsl.js';
import { toColor, sampleRange, normalizeAt, makeAt, makeFrame } from './util.js';
import { opt } from './meshfx.js';
import { makeRng, TAU, DEG } from '../core/math.js';
import { LIB } from './library.js';

const KIND = { rock: 0, ice: 1, ember: 2, crystal: 3 };

/** Per-kind defaults (see README "Debris"). albedo is linear; emit is the HDR emissive colour. */
export const DEBRIS_KINDS = {
  rock: { albedo: [0.16, 0.145, 0.13], rough: 0.92, emit: [0, 0, 0], heat: 0, gravity: -15, bounce: 0.32, life: [1.6, 2.6], dust: true },
  ice: { albedo: [0.1, 0.2, 0.32], rough: 0.12, emit: [0.3, 1.2, 3], heat: 0, gravity: -14, bounce: 0.4, life: [1.2, 2.0], dust: false },
  ember: { albedo: [0.045, 0.037, 0.032], rough: 0.8, emit: [8, 3, 0.6], heat: 1, gravity: -13, bounce: 0.3, life: [1.6, 2.8], dust: true },
  crystal: { albedo: [0.06, 0.03, 0.11], rough: 0.1, emit: [1.6, 0.8, 4], heat: 0, gravity: -13, bounce: 0.38, life: [1.2, 2.2], dust: false },
};

const LAYOUT = { iPosT: 4, iVelL: 4, iRot: 4, iShape: 4, iPhys: 4, iQuat: 4, iAlb: 4, iEmit: 4 };

/** Merge three jittered polyhedra into one non-indexed template; aVar tags the variant of every vertex. */
function chunkGeometry() {
  const rng = makeRng(9917);
  const variants = [
    { g: new THREE.IcosahedronGeometry(1, 0), s: [1, 0.55, 0.82], j: 0.22 },
    { g: new THREE.DodecahedronGeometry(1, 0), s: [1.05, 0.78, 0.7], j: 0.18 },
    { g: new THREE.OctahedronGeometry(1, 0), s: [0.55, 1.15, 0.5], j: 0.16 },
  ];
  const pos = [], vv = [];
  variants.forEach((v, vi) => {
    const p = (v.g.index ? v.g.toNonIndexed() : v.g).getAttribute('position');
    const jit = new Map();
    for (let i = 0; i < p.count; i++) {
      const x = p.getX(i), y = p.getY(i), z = p.getZ(i);
      const key = Math.round(x * 1000) + ',' + Math.round(y * 1000) + ',' + Math.round(z * 1000);
      if (!jit.has(key)) jit.set(key, [(rng() - 0.5) * v.j, (rng() - 0.5) * v.j, (rng() - 0.5) * v.j]);
      const j = jit.get(key);
      pos.push((x + j[0]) * v.s[0] * 0.62, (y + j[1]) * v.s[1] * 0.62, (z + j[2]) * v.s[2] * 0.62);
      vv.push(vi);
    }
    v.g.dispose();
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
attribute vec4 iPosT, iVelL, iRot, iShape, iPhys, iQuat, iAlb, iEmit;
varying vec4 vDeb;     // heat (0..1), kind, seed, t
varying vec3 vLocal, vAlb, vEmit;
varying float vRough;
${GLSL_COMMON}
${GLSL_BALLISTIC}
`;

// runs at <beginnormal_vertex> (before <begin_vertex>): motion, rotation and scale shared by normal and position
const VERT_MOTION = /* glsl */ `
  float dLife = abs(iVelL.w);
  float dAge = (iVelL.w < 0.0 ? uTimeReal : uTime) - iPosT.w;
  bool dOn = dLife > 0.0 && dAge >= 0.0 && dAge < dLife && abs(aVar - iShape.y) < 0.5;
  dAge = clamp(dAge, 0.0, dLife);
  float dT = dAge / max(dLife, 1e-4);
  float dR = iShape.x * 0.5;                // the chunk's centre rests one radius above the floor
  vec3 dp = iPosT.xyz - vec3(0.0, dR, 0.0), dv = iVelL.xyz;
  vec3 dg = vec3(0.0, iPhys.x, 0.0);
  float dk = iPhys.y, dLand = 1e9, dRest = dAge;
  for (int b = 0; b < 3; b++) {
    float ti = impact(dp.y, dv.y, dg.y, dk, dRest);
    if (ti >= dRest) break;
    integ(dp, dv, dg, dk, ti);
    if (dLand > 1e8) dLand = dAge - dRest + ti;
    dp.y = 0.0; dv.y = -dv.y * iPhys.z; dv.xz *= iPhys.w; dRest -= ti;
    if (dv.y < 0.25) { dv.y = 0.0; dg.y = 0.0; break; }
  }
  integ(dp, dv, dg, dk, dRest);
  dp.y = max(dp.y, 0.0) + dR;
  // spin: full rate in flight, dies quickly after the first landing
  float dAng = iRot.w * (min(dAge, dLand) + (dAge > dLand ? (1.0 - exp(-5.0 * (dAge - dLand))) * 0.07 : 0.0));
  float dSc = dOn ? iShape.x * smoothstep(0.0, 0.035, dAge) * (1.0 - smoothstep(0.72, 1.0, dT)) : 0.0;
  vec3 dAxis = iRot.xyz;
  vDeb = vec4(iEmit.w * (1.0 - dT), iShape.z, iShape.w, dT);
  vLocal = position * 1.6 + iShape.w;
  vAlb = iAlb.rgb;
  vEmit = iEmit.rgb;
  vRough = iAlb.w;
`;

const VERT_NORMAL = /* glsl */ `
  vec3 objectNormal = rotAxis(qrot(iQuat, normal), dAxis, dAng);
  #ifdef USE_TANGENT
    vec3 objectTangent = vec3( tangent.xyz );
  #endif
`;
const VERT_BEGIN = /* glsl */ `
  vec3 transformed = rotAxis(qrot(iQuat, position * dSc), dAxis, dAng) + dp;
`;

const FRAG_PARS = /* glsl */ `
uniform sampler2D uNoise;
varying vec4 vDeb;
varying vec3 vLocal, vAlb, vEmit;
varying float vRough;
`;
const FRAG_EMISSIVE = /* glsl */ `
  {
    int kind = int(vDeb.y + 0.5);
    float fres = pow(1.0 - clamp(dot(normal, normalize(vViewPosition)), 0.0, 1.0), 3.0);
    float nz = texture2D(uNoise, vLocal.xy * 0.35 + vLocal.z * 0.21).b;
    float nf = texture2D(uNoise, vLocal.yz * 0.5 + vLocal.x * 0.13).r;
    if (kind == 2) {
      // ember: glowing fissures and a hot skin that cool over life (core -> orange -> deep red -> black)
      float h = vDeb.x * sqrt(vDeb.x);
      float cracks = smoothstep(0.55, 0.85, 1.0 - nz) * 0.9 + 0.2 * nf * nf;
      vec3 hc = mix(vec3(0.5, 0.04, 0.008), vEmit, h * h);
      totalEmissiveRadiance += hc * (cracks * h + h * h * h * h * 0.18);
    } else if (kind == 1) {
      totalEmissiveRadiance += vEmit * (fres * 0.6 + 0.04 + smoothstep(0.6, 0.9, nf) * 0.08) * (1.0 - vDeb.w * 0.5);
    } else if (kind == 3) {
      totalEmissiveRadiance += vEmit * (fres * 0.5 + 0.12 * nf + 0.05) * (1.0 - vDeb.w * 0.5);
    }
  }
`;

/**
 * @param {object} vfx
 * @param {object} shared
 */
export function installDebris(vfx, shared) {
  const { ctx, root, uniforms, textures, rng, clock } = shared;
  const q = ctx.quality;
  const CAP = q.tier === 'low' ? 128 : q.tier === 'mid' ? 192 : 256;
  const ring = new InstanceRing(CAP, LAYOUT, chunkGeometry());
  const mat = new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.9, metalness: 0.0, flatShading: true, envMapIntensity: 0.6 });
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
      .replace('#include <color_fragment>', '#include <color_fragment>\n  diffuseColor.rgb = vAlb;')
      .replace('#include <roughnessmap_fragment>', '#include <roughnessmap_fragment>\n  roughnessFactor = vRough;')
      .replace('#include <emissivemap_fragment>', '#include <emissivemap_fragment>\n' + FRAG_EMISSIVE);
  };
  mat.customProgramCacheKey = () => 'vfx.debris';
  const mesh = new THREE.Mesh(ring.geometry, mat);
  mesh.frustumCulled = false;
  mesh.visible = false;
  mesh.castShadow = false;
  mesh.name = 'vfx.debris';
  root.add(mesh);

  let serial = 1;
  const active = [];
  const atN = makeAt();
  const X = new THREE.Vector3(), Y = new THREE.Vector3(), Z = new THREE.Vector3(), D = new THREE.Vector3(), P = new THREE.Vector3(), A = new THREE.Vector3();
  const qa = new THREE.Quaternion(), alb = new THREE.Color(), emit = new THREE.Color();
  const dustDef = { ...LIB.dustRing, count: 4, shape: { type: 'sphere', radius: 0.08, hemi: true }, emit: 'radial', spread: 70, lift: 0.5, speed: [0.4, 1.4], size: [0.25, 0.55], life: [0.5, 1.0], groundFade: 0.15 };

  /** first time the chunk centre reaches its resting height (CPU mirror of the shader, for dust puffs) */
  function landing(y, vy, gy, k) {
    const yAt = (t) => (k < 1e-3 ? y + vy * t + 0.5 * gy * t * t : y + (gy / k) * t + (vy - gy / k) * (1 - Math.exp(-k * t)) / k);
    // search after the apex, where the height only falls
    const ta = vy > 0 ? (k < 1e-3 ? vy / -gy : Math.log((vy - gy / k) / (-gy / k)) / k) : 0;
    let lo = ta, hi = ta + 4;
    if (yAt(hi) > 0) return -1;
    for (let i = 0; i < 30; i++) { const m = (lo + hi) / 2; if (yAt(m) > 0) lo = m; else hi = m; }
    return hi;
  }
  const xzAt = (x, v, k, t) => (k < 1e-3 ? x + v * t : x + v * (1 - Math.exp(-k * t)) / k);

  /**
   * Burst of lit fragments. See README "Debris". `opts` takes the `at` fields too (pos, dir, scale, vel, realtime).
   * Returns { kill(), alive }.
   */
  function debris(opts = {}) {
    const kindName = opts.kind || 'rock';
    const kd = DEBRIS_KINDS[kindName];
    if (!kd) throw new Error('vfx.debris: unknown kind "' + kindName + '" (have: ' + Object.keys(DEBRIS_KINDS).join(', ') + ')');
    normalizeAt(opts, atN);
    if (!atN.hasDir) atN.dir.set(0, 1, 0);
    const sc = atN.scale;
    const n = Math.min(CAP, Math.max(1, Math.round(opt(opts.count, 12) * q.particleScale)));
    const realtime = atN.realtime;
    const now = realtime ? clock.real : clock.game;
    const s0 = ring.alloc(n);
    const own = serial++;
    makeFrame(atN.dir, atN.side, 1, X, Y, Z);
    toColor(opt(opts.albedo, kd.albedo), alb);
    toColor(opt(opts.emissive, kd.emit), emit);
    const heat = opt(opts.heat, kd.heat);
    const rough = opt(opts.roughness, kd.rough);
    const shape = opts.shape || { type: 'disc', radius: 0.25 };
    const spread = opt(opts.spread, 50), sizeR = opt(opts.size, [0.05, 0.2, 2]), speedR = opt(opts.speed, [3, 8, 1.3]);
    const lifeR = opt(opts.life, kd.life), spinR = opt(opts.spin, [3, 14]);
    const grav = opt(opts.gravity, kd.gravity), drag = opt(opts.drag, 0.4), bounce = opt(opts.bounce, kd.bounce), fric = opt(opts.friction, 0.55);
    const dust = opt(opts.dust, kd.dust) && vfx.burst;
    let end = now, dusts = 0;
    const children = [];
    const f = ring.f32, st = ring.stride;
    for (let i = 0; i < n; i++) {
      const j = (s0 + i) % CAP, k = j * st;
      // spawn point in the shape (local XZ disc / sphere / point), velocity in a cone around dir
      let lx = 0, ly = 0, lz = 0;
      if (shape.type === 'sphere') { A.set(rng() * 2 - 1, rng() * 2 - 1, rng() * 2 - 1).normalize().multiplyScalar((shape.radius || 0.3) * Math.cbrt(rng())); lx = A.x; ly = A.y; lz = A.z; }
      else if (shape.type === 'disc') { const a = rng() * TAU, r = (shape.radius || 0.25) * Math.sqrt(rng()); lx = Math.cos(a) * r; lz = Math.sin(a) * r; }
      P.set(0, 0, 0).addScaledVector(X, lx).addScaledVector(Y, ly).addScaledVector(Z, lz).multiplyScalar(sc).add(atN.pos);
      const th = Math.acos(1 - rng() * (1 - Math.cos(spread * DEG))), ph = rng() * TAU;
      D.copy(Y).multiplyScalar(Math.cos(th)).addScaledVector(X, Math.sin(th) * Math.cos(ph)).addScaledVector(Z, Math.sin(th) * Math.sin(ph));
      const sp = sampleRange(rng, speedR) * Math.sqrt(sc);
      const size = sampleRange(rng, sizeR) * sc;
      const life = Math.max(0.05, sampleRange(rng, lifeR));
      const t0 = now + rng() * opt(opts.stagger, 0.02);
      const vx = D.x * sp + atN.vel.x, vy = D.y * sp + atN.vel.y, vz = D.z * sp + atN.vel.z;
      f[k] = P.x; f[k + 1] = Math.max(P.y, size * 0.5); f[k + 2] = P.z; f[k + 3] = t0;
      f[k + 4] = vx; f[k + 5] = vy; f[k + 6] = vz; f[k + 7] = realtime ? -life : life;
      A.set(rng() * 2 - 1, rng() * 2 - 1, rng() * 2 - 1).normalize();
      f[k + 8] = A.x; f[k + 9] = A.y; f[k + 10] = A.z; f[k + 11] = sampleRange(rng, spinR) * (rng() < 0.5 ? -1 : 1);
      f[k + 12] = size; f[k + 13] = Math.floor(rng() * 3); f[k + 14] = KIND[kindName]; f[k + 15] = rng() * 40;
      f[k + 16] = grav; f[k + 17] = drag; f[k + 18] = bounce; f[k + 19] = fric;
      qa.setFromAxisAngle(A.set(rng() * 2 - 1, rng() * 2 - 1, rng() * 2 - 1).normalize(), rng() * TAU);
      f[k + 20] = qa.x; f[k + 21] = qa.y; f[k + 22] = qa.z; f[k + 23] = qa.w;
      const vary = 0.75 + 0.5 * rng();
      f[k + 24] = alb.r * vary; f[k + 25] = alb.g * vary; f[k + 26] = alb.b * vary; f[k + 27] = rough;
      f[k + 28] = emit.r; f[k + 29] = emit.g; f[k + 30] = emit.b; f[k + 31] = heat * (0.7 + 0.3 * rng());
      ring.owner[j] = own;
      end = Math.max(end, t0 + life);
      // a puff of dust where the bigger chunks first land
      if (dust && dusts < 4 && size > 0.1 * sc) {
        const tl = landing(f[k + 1] - size * 0.5, vy, grav, drag);
        if (tl > 0.05) {
          dusts++;
          const lp = [xzAt(P.x, vx, drag, tl), 0.02, xzAt(P.z, vz, drag, tl)];
          children.push(vfx.schedule(t0 - now + tl, (v) => { children.push(v.burst(dustDef, { pos: lp, dir: [0, 1, 0], scale: Math.min(1.5, size * 6), realtime })); }, { realtime }));
        }
      }
    }
    ring.dirty(s0, n);
    ring.commit();
    mesh.visible = true;
    const h = {
      _dead: false,
      get alive() { return !h._dead && (realtime ? clock.real : clock.game) < end; },
      kill() {
        if (h._dead) return;
        h._dead = true;
        for (const c of children) c.kill();
        for (let i = 0; i < n; i++) { const j = (s0 + i) % CAP; if (ring.owner[j] === own) f[j * st + 7] = 0; }
        ring.dirty(s0, n);
      },
      stop() {},
    };
    active.push(h);
    shared.track(h);
    return h;
  }

  return {
    name: 'debris',
    api: { debris, debrisKinds: DEBRIS_KINDS },
    update() {
      for (let i = active.length - 1; i >= 0; i--) if (!active[i].alive) active.splice(i, 1);
      ring.commit();
      mesh.visible = active.length > 0;
    },
    clear() {
      for (let i = 0; i < CAP; i++) ring.f32[i * ring.stride + 7] = 0;
      ring.dirty(0, CAP);
      ring.commit();
      for (const h of active) h._dead = true;
      active.length = 0;
      mesh.visible = false;
    },
    dispose() { ring.dispose(); mat.dispose(); mesh.removeFromParent(); },
    mesh,
  };
}
