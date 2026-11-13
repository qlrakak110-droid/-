// vfx.afterimage: fading ghost copies of an Object3D hierarchy: the light-foot (경공) trails of dashes, blinks and
// blur-fast strikes. A snapshot copies the current bone matrices into a frozen skeleton, so the ghost keeps the pose of
// that instant while the character moves on.
//
// PROXY (default for skinned characters): a hero is ~58k triangles in several skinned meshes; re-drawing all of that
// per ghost made ultimates spike by hundreds of thousands of triangles. The first afterimage of a character (or
// vfx.afterimageProxy(root) while loading) builds ONE decimated silhouette mesh from every SkinnedMesh that shares the
// character's skeleton: vertices are clustered on a grid in the bind pose (per dominant bone, so limbs never fuse),
// degenerate and duplicate triangles are dropped, and the cell size is raised until the mesh fits the tier's triangle
// budget (9k / 6k / 3.5k). A ghost is then one draw call of that proxy. Ghosts per character are capped (4 / 3 / 2):
// the oldest is recycled first.
// Without a proxy (plain meshes, `proxy: false`) a snapshot copies the world matrix of every Mesh and shares its
// geometry, one draw per mesh, as before.
// Every ghost slot is pooled (a plain Mesh and a SkinnedMesh with a preallocated frozen skeleton and its own material
// instance of ONE shared program), so a snapshot allocates nothing.
// Look: additive fresnel shell (rim-lit silhouette with a faint fill) in HDR core -> mid colours, drifting, dissolving
// in brush-like streaks along its height.

import * as THREE from 'three';
import { GLSL_COMMON } from './glsl.js';
import { toVec3, RENDER_ORDER } from './util.js';
import { resolveColors, makeColors, opt } from './meshfx.js';

const MAXB = 64;

const VERT = /* glsl */ `
#include <common>
#include <skinning_pars_vertex>
uniform vec4 uGhost;   // t0, life (signed), drift speed (m/s), swell (m)
uniform vec3 uDrift;
uniform float uTime, uTimeReal;
varying vec3 vN, vW;
varying float vT;
void main() {
  #include <skinbase_vertex>
  #include <beginnormal_vertex>
  #include <skinnormal_vertex>
  #include <begin_vertex>
  #include <skinning_vertex>
  float life = abs(uGhost.y);
  float age = (uGhost.y < 0.0 ? uTimeReal : uTime) - uGhost.x;
  float t = clamp(age / max(life, 1e-4), 0.0, 1.0);
  vec3 n = normalize(mat3(modelMatrix) * objectNormal);
  vec4 wp = modelMatrix * vec4(transformed, 1.0);
  wp.xyz += uDrift * age + n * uGhost.w * t;
  vN = n;
  vW = wp.xyz;
  vT = t;
  gl_Position = projectionMatrix * viewMatrix * wp;
}`;

const FRAG = /* glsl */ `
precision highp float;
uniform sampler2D uNoise;
uniform vec3 uCore, uMid;
uniform vec4 uLook;    // fill, fresnel power, alpha, erosion scale
varying vec3 vN, vW;
varying float vT;
${GLSL_COMMON}
void main() {
  vec3 V = normalize(cameraPosition - vW);
  float ndv = abs(dot(normalize(vN), V));
  float fres = pow(max(1.0 - ndv, 0.0), uLook.y);
  // dry-brush dissolve: noise stretched along the height, so the ghost breaks into vertical bristle streaks
  float n = texture2D(uNoise, vec2(vW.x + vW.z * 0.37, vW.y * 0.22) * uLook.w).r * 0.7 + texture2D(uNoise, vec2(vW.z + vW.x * 0.5, vW.y * 0.3) * uLook.w * 2.3 + 0.5).a * 0.3;
  float th = mix(-0.15, 1.0, pow(max(vT, 0.0), 1.3));
  float vis = smoothstep(th - 0.08, th + 0.08, n * 0.85 + fres * 0.15);
  float edge = (1.0 - smoothstep(th, th + 0.12, n * 0.85 + fres * 0.15)) * vis;
  // layered armour stacks several shells per ghost and ghosts overlap: keep each one dim (mid colour, core on the rim)
  vec3 col = mix(mix(uMid * 0.5, uCore * 0.32, fres * (1.0 - vT)), uMid * 0.25, smoothstep(0.2, 0.9, vT));
  float I = (fres * 0.9 + uLook.x) * (1.0 - vT) * (1.0 - vT * 0.3);
  vec3 rgb = col * I * vis * uLook.z + uCore * edge * 0.6 * (1.0 - vT);
  if (!(dot(rgb, rgb) >= 1e-6)) discard;      // also drops NaN
  gl_FragColor = vec4(rgb, 0.0);
}`;

/**
 * @param {object} vfx
 * @param {object} shared
 */
export function installAfterimage(vfx, shared) {
  const { ctx, root, uniforms, textures, clock } = shared;
  // ghost mesh slots: every ghost re-draws a whole character mesh (a hero is ~58k triangles in 3-4 meshes), so the pool
  // is the per-tier cap on ghost geometry; when full, the oldest ghost mesh is recycled first
  const tier = ctx.quality.tier;
  const N = tier === 'low' ? 4 : tier === 'mid' ? 8 : 10;
  const MAXM = tier === 'low' ? 2 : tier === 'mid' ? 3 : 4;
  /** live ghosts per source object (the oldest is recycled first) */
  const MAXG = tier === 'low' ? 2 : tier === 'mid' ? 3 : 4;
  /** triangle budget of a character's silhouette proxy */
  const PROXY_TRIS = tier === 'low' ? 3500 : tier === 'mid' ? 6000 : 9000;
  // one material instance per slot (per-ghost uniforms), all from the same source: ONE program
  const uNoise = { value: textures.noise };
  const makeMat = () => new THREE.ShaderMaterial({
    vertexShader: VERT, fragmentShader: FRAG,
    uniforms: {
      uTime: uniforms.uTime, uTimeReal: uniforms.uTimeReal, uNoise,
      uGhost: { value: new THREE.Vector4() }, uDrift: { value: new THREE.Vector3() }, uCore: { value: new THREE.Color() }, uMid: { value: new THREE.Color() }, uLook: { value: new THREE.Vector4() },
    },
    transparent: true, depthWrite: false, depthTest: true, side: THREE.FrontSide,
    blending: THREE.CustomBlending, blendSrc: THREE.OneFactor, blendDst: THREE.OneMinusSrcAlphaFactor, blendSrcAlpha: THREE.OneFactor, blendDstAlpha: THREE.OneMinusSrcAlphaFactor,
  });
  const dummy = new THREE.BufferGeometry();
  dummy.setAttribute('position', new THREE.Float32BufferAttribute([0, 0, 0, 0, 0, 0, 0, 0, 0], 3));
  dummy.setAttribute('normal', new THREE.Float32BufferAttribute([0, 1, 0, 0, 1, 0, 0, 1, 0], 3));
  dummy.setAttribute('skinIndex', new THREE.Uint16BufferAttribute([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], 4));
  dummy.setAttribute('skinWeight', new THREE.Float32BufferAttribute([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0], 4));
  const bones = [];
  for (let i = 0; i < MAXB; i++) bones.push(new THREE.Bone());
  const noop = () => {};
  const frozen = (n) => {
    const sk = new THREE.Skeleton(n === MAXB ? bones : Array.from({ length: n }, () => new THREE.Bone()));
    sk.update = noop;          // the renderer calls update() every frame: keep the snapshot
    sk.computeBoneTexture();
    return sk;
  };
  const slots = [];
  for (let i = 0; i < N; i++) {
    const mat = makeMat();
    const plain = new THREE.Mesh(dummy, mat);
    const skinned = new THREE.SkinnedMesh(dummy, mat);
    const skel = frozen(MAXB);
    skinned.bind(skel, new THREE.Matrix4());
    for (const m of [plain, skinned]) {
      m.matrixAutoUpdate = false;
      m.frustumCulled = false;
      m.visible = false;
      m.renderOrder = RENDER_ORDER.meshBeam;
      m.name = 'vfx.afterimage' + i;
      root.add(m);
    }
    slots.push({ i, mat, plain, skinned, skel, live: false, obj: null, t0: 0, life: 0, realtime: false, serial: 0 });
  }

  // ---- silhouette proxies ----------------------------------------------------------------------------------------------
  const proxies = new Map();      // root Object3D -> { geo, mesh (a source SkinnedMesh: skeleton + bind), triangles, source }
  const inScene = (o) => { for (let p = o; p; p = p.parent) if (p === ctx.scene) return true; return false; };

  /** Cluster-decimate the merged skinned geometry: returns { pos, nor, si, sw, idx, tris }. */
  function cluster(P, Nn, SI, SW, I, nv, cell, min) {
    const inv = 1 / cell;
    const ids = new Map();
    const cid = new Int32Array(nv);
    const cp = [], cn = [], cc = [], rep = [];
    for (let v = 0; v < nv; v++) {
      let b = 0, bw = -1;
      for (let k = 0; k < 4; k++) if (SW[v * 4 + k] > bw) { bw = SW[v * 4 + k]; b = SI[v * 4 + k]; }
      const ix = Math.floor((P[v * 3] - min[0]) * inv), iy = Math.floor((P[v * 3 + 1] - min[1]) * inv), iz = Math.floor((P[v * 3 + 2] - min[2]) * inv);
      const key = ((ix * 2048 + iy) * 2048 + iz) * 512 + (b & 511);
      let id = ids.get(key);
      if (id === undefined) { id = rep.length; ids.set(key, id); rep.push(v); cp.push(0, 0, 0); cn.push(0, 0, 0); cc.push(0); }
      cid[v] = id;
      cp[id * 3] += P[v * 3]; cp[id * 3 + 1] += P[v * 3 + 1]; cp[id * 3 + 2] += P[v * 3 + 2];
      cn[id * 3] += Nn[v * 3]; cn[id * 3 + 1] += Nn[v * 3 + 1]; cn[id * 3 + 2] += Nn[v * 3 + 2];
      cc[id]++;
    }
    const nc = rep.length;
    const seen = new Set();
    const out = [];
    for (let t = 0; t < I.length; t += 3) {
      const a = cid[I[t]], b = cid[I[t + 1]], c = cid[I[t + 2]];
      if (a === b || b === c || a === c) continue;
      const lo = Math.min(a, b, c), hi = Math.max(a, b, c), mid = a + b + c - lo - hi;
      const key = (lo * nc + mid) * nc + hi;
      if (seen.has(key)) continue;
      seen.add(key);
      out.push(a, b, c);
    }
    return { nc, rep, cp, cn, cc, out };
  }

  /**
   * Build (or fetch) the silhouette proxy of a skinned hierarchy. Returns null when it has no SkinnedMesh.
   * Proxies of roots that left the scene are disposed here (lazy sweep), so sessions do not leak geometry.
   */
  function proxyOf(obj) {
    let pr = proxies.get(obj);
    if (pr !== undefined) return pr;
    for (const [o, p] of proxies) if (!inScene(o)) { if (p) p.geo.dispose(); proxies.delete(o); }
    const meshes = [];
    let skeleton = null;
    obj.updateMatrixWorld(true);
    obj.traverse((o) => {
      if (!o.isSkinnedMesh || !o.geometry || !o.geometry.index || !o.geometry.getAttribute('skinIndex')) return;
      if (!skeleton) skeleton = o.skeleton;
      if (o.skeleton === skeleton) meshes.push(o);
    });
    if (!meshes.length) { proxies.set(obj, null); return null; }
    let nv = 0, ni = 0, source = 0;
    for (const m of meshes) { nv += m.geometry.getAttribute('position').count; ni += m.geometry.index.count; }
    source = ni / 3;
    const P = new Float32Array(nv * 3), Nn = new Float32Array(nv * 3), SI = new Uint16Array(nv * 4), SW = new Float32Array(nv * 4), I = new Uint32Array(ni);
    const v3 = new THREE.Vector3(), nm = new THREE.Matrix3();
    const min = [1e9, 1e9, 1e9];
    let vo = 0, io = 0;
    for (const m of meshes) {
      const g = m.geometry, gp = g.getAttribute('position'), gn = g.getAttribute('normal'), gi = g.getAttribute('skinIndex'), gw = g.getAttribute('skinWeight');
      nm.getNormalMatrix(m.bindMatrix);
      for (let v = 0; v < gp.count; v++) {
        v3.fromBufferAttribute(gp, v).applyMatrix4(m.bindMatrix);      // into the shared bind space
        const k = (vo + v) * 3;
        P[k] = v3.x; P[k + 1] = v3.y; P[k + 2] = v3.z;
        if (v3.x < min[0]) min[0] = v3.x; if (v3.y < min[1]) min[1] = v3.y; if (v3.z < min[2]) min[2] = v3.z;
        if (gn) { v3.fromBufferAttribute(gn, v).applyMatrix3(nm); Nn[k] = v3.x; Nn[k + 1] = v3.y; Nn[k + 2] = v3.z; }
        const q = (vo + v) * 4;
        SI[q] = gi.getX(v); SI[q + 1] = gi.getY(v); SI[q + 2] = gi.getZ(v); SI[q + 3] = gi.getW(v);
        SW[q] = gw.getX(v); SW[q + 1] = gw.getY(v); SW[q + 2] = gw.getZ(v); SW[q + 3] = gw.getW(v);
      }
      const ia = g.index.array;
      for (let i = 0; i < ia.length; i++) I[io + i] = ia[i] + vo;
      vo += gp.count; io += ia.length;
    }
    // raise the cell size until the silhouette fits the budget (triangles fall roughly with 1 / cell^2)
    let cell = 0.03, c = null;
    for (let it = 0; it < 5; it++) {
      c = cluster(P, Nn, SI, SW, I, nv, cell, min);
      const tris = c.out.length / 3;
      if (tris <= PROXY_TRIS) break;
      cell *= Math.min(2.2, Math.max(1.12, Math.sqrt(tris / PROXY_TRIS) * 1.06));
    }
    const nc = c.nc;
    const pos = new Float32Array(nc * 3), nor = new Float32Array(nc * 3), si = new Uint16Array(nc * 4), sw = new Float32Array(nc * 4);
    for (let i = 0; i < nc; i++) {
      const n = c.cc[i], r = c.rep[i];
      pos[i * 3] = c.cp[i * 3] / n; pos[i * 3 + 1] = c.cp[i * 3 + 1] / n; pos[i * 3 + 2] = c.cp[i * 3 + 2] / n;
      let x = c.cn[i * 3], y = c.cn[i * 3 + 1], z = c.cn[i * 3 + 2];
      let l = Math.hypot(x, y, z);
      if (l < 0.2 * n) { x = Nn[r * 3]; y = Nn[r * 3 + 1]; z = Nn[r * 3 + 2]; l = Math.hypot(x, y, z) || 1; }   // both faces of a thin sheet cancel
      nor[i * 3] = x / l; nor[i * 3 + 1] = y / l; nor[i * 3 + 2] = z / l;
      for (let k = 0; k < 4; k++) { si[i * 4 + k] = SI[r * 4 + k]; sw[i * 4 + k] = SW[r * 4 + k]; }
    }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    geo.setAttribute('normal', new THREE.BufferAttribute(nor, 3));
    geo.setAttribute('skinIndex', new THREE.BufferAttribute(si, 4));
    geo.setAttribute('skinWeight', new THREE.BufferAttribute(sw, 4));
    geo.setIndex(new THREE.BufferAttribute(nc > 65535 ? new Uint32Array(c.out) : new Uint16Array(c.out), 1));
    pr = { geo, mesh: meshes[0], skeleton, triangles: c.out.length / 3, source, cell };
    proxies.set(obj, pr);
    // the frozen skeletons must hold this character's bones (cloth bones included) before the first ghost
    const nb = skeleton.bones.length;
    for (const s of slots) if (nb > s.skel.bones.length) { s.skel.dispose(); s.skel = frozen(nb); ctx.renderer.initTexture(s.skel.boneTexture); }
    return pr;
  }
  let serial = 1;
  const lists = new WeakMap();
  const C = makeColors();
  const drift = new THREE.Vector3();

  function meshesOf(obj, filter) {
    let l = lists.get(obj);
    if (!l) {
      l = [];
      obj.traverse((o) => { if ((o.isMesh || o.isSkinnedMesh) && !o.isInstancedMesh && o.geometry && o.geometry.getAttribute('position') && (!filter || filter(o))) l.push(o); });
      lists.set(obj, l);
    }
    return l;
  }

  function take() {
    let s = null;
    for (const x of slots) if (!x.live) { s = x; break; }
    if (!s) { s = slots[0]; for (const x of slots) if (x.t0 < s.t0) s = x; free(s); }
    return s;
  }
  /** Keep at most MAXG - 1 ghosts of `obj` alive before a new one is taken (proxy ghosts: one slot each). */
  function capFor(obj) {
    for (;;) {
      let n = 0, old = null;
      for (const x of slots) if (x.live && x.obj === obj) { n++; if (!old || x.t0 < old.t0) old = x; }
      if (n < MAXG) return;
      free(old);
    }
  }
  function freeze(s, g, m) {
    const src = m.skeleton;
    src.update();
    const nb = src.bones.length;
    if (nb > s.skel.bones.length) { s.skel.dispose(); s.skel = frozen(nb); }
    s.skel.boneMatrices.set(src.boneMatrices.subarray(0, Math.min(nb * 16, s.skel.boneMatrices.length)));
    s.skel.boneTexture.needsUpdate = true;
    g.skeleton = s.skel;
    g.bindMode = m.bindMode;
    g.bindMatrix.copy(m.bindMatrix);
    g.bindMatrixInverse.copy(m.bindMatrixInverse);
  }
  function arm(s, g, obj, o, now, out) {
    const U = s.mat.uniforms;
    U.uGhost.value.set(now, o.realtime ? -o.life : o.life, 0, o.swell);
    U.uDrift.value.copy(drift);
    U.uCore.value.copy(C.core).multiplyScalar(o.intensity);
    U.uMid.value.copy(C.mid).multiplyScalar(o.intensity);
    U.uLook.value.set(o.fill, o.fresnel, o.alpha, o.erodeScale);
    g.visible = true;
    s.live = true;
    s.obj = obj;
    s.t0 = now;
    s.life = o.life;
    s.realtime = o.realtime;
    s.serial = serial++;
    out.push(s, s.serial);
  }
  function free(s) {
    if (!s.live) return;
    s.live = false;
    s.obj = null;
    s.serial = 0;
    s.plain.visible = s.skinned.visible = false;
    s.plain.geometry = s.skinned.geometry = dummy;
  }

  /** Snapshot every mesh of `obj` into ghost slots. Returns the slots used. */
  function snap(obj, o, out) {
    obj.updateMatrixWorld(true);
    const now = o.realtime ? clock.real : clock.game;
    const pr = o.proxy ? proxyOf(obj) : null;
    if (pr) {
      // one draw of the decimated silhouette, posed by the frozen skeleton
      const m = pr.mesh;
      if (!m.visible) return;
      for (let p = m.parent; p && p !== obj.parent; p = p.parent) if (!p.visible) return;
      capFor(obj);
      const s = take();
      const g = s.skinned;
      g.geometry = pr.geo;
      g.matrix.copy(m.matrixWorld);
      g.matrixWorld.copy(m.matrixWorld);
      freeze(s, g, m);
      g.bindMatrix.identity();          // the proxy's vertices are already in the shared bind space
      arm(s, g, obj, o, now, out);
      return;
    }
    const list = meshesOf(obj, o.filter);
    let used = 0;
    for (const m of list) {
      if (used >= o.maxMeshes) break;
      if (!m.visible || m.material === undefined) continue;
      let vis = true;
      for (let p = m.parent; p && p !== obj.parent; p = p.parent) if (!p.visible) { vis = false; break; }
      if (!vis) continue;
      const s = take();
      const g = m.isSkinnedMesh ? s.skinned : s.plain;
      g.geometry = m.geometry;
      g.matrix.copy(m.matrixWorld);
      g.matrixWorld.copy(m.matrixWorld);
      if (m.isSkinnedMesh) freeze(s, g, m);
      arm(s, g, obj, o, now, out);
      used++;
    }
  }

  /**
   * Ghost copies of a (skinned) Object3D hierarchy. See README "Afterimage".
   * Returns { kill(), stop(), alive } (stop() cancels pending snapshots; existing ghosts fade out).
   */
  function afterimage(obj, opts = {}) {
    if (!obj || !obj.isObject3D) throw new Error('vfx.afterimage needs an Object3D');
    resolveColors(opts, { palette: 'frost' }, C);
    if (opts.drift) toVec3(opts.drift, drift); else drift.set(0, 0, 0);
    const o = {
      life: opt(opts.life, 0.35), realtime: !!opts.realtime, intensity: opt(opts.intensity, 1), swell: opt(opts.swell, 0.03),
      fill: opt(opts.fill, 0.05), fresnel: opt(opts.fresnel, 2.6), alpha: opt(opts.alpha, 1), erodeScale: opt(opts.erodeScale, 1.6),
      maxMeshes: Math.min(opt(opts.maxMeshes, MAXM), MAXM), filter: opts.filter || null,
      proxy: opts.proxy !== false && !opts.filter,
    };
    const count = Math.max(1, opt(opts.count, 1));
    const interval = opt(opts.interval, 0.045);
    const ghosts = [];
    snap(obj, o, ghosts);
    const pending = [];
    for (let i = 1; i < count && Number.isFinite(count); i++) pending.push(vfx.schedule(i * interval, () => snap(obj, o, ghosts), { realtime: o.realtime }));
    const h = {
      get alive() {
        for (let i = 0; i < ghosts.length; i += 2) if (ghosts[i].live && ghosts[i].serial === ghosts[i + 1]) return true;
        for (const p of pending) if (p.alive) return true;
        return false;
      },
      stop() { for (const p of pending) p.kill(); },
      kill() { h.stop(); for (let i = 0; i < ghosts.length; i += 2) if (ghosts[i].serial === ghosts[i + 1]) free(ghosts[i]); },
    };
    shared.track(h);
    return h;
  }

  /**
   * Build the silhouette proxy of a skinned character now (call while loading: clustering ~58k triangles takes a few
   * milliseconds). Returns { triangles, source, cell } or null when `obj` has no SkinnedMesh.
   */
  function afterimageProxy(obj) {
    const pr = obj && obj.isObject3D ? proxyOf(obj) : null;
    return pr ? { triangles: pr.triangles, source: pr.source, cell: pr.cell } : null;
  }

  return {
    name: 'afterimage',
    api: { afterimage, afterimageProxy, afterimageLimits: { ghostsPerObject: MAXG, proxyTriangles: PROXY_TRIS, slots: N } },
    update() {
      for (const s of slots) {
        if (!s.live) continue;
        if ((s.realtime ? clock.real : clock.game) - s.t0 >= s.life) free(s);
      }
    },
    clear() { for (const s of slots) free(s); },
    /** upload every slot's frozen bone texture now (no texture upload on the first ghost) */
    prewarm() { for (const s of slots) ctx.renderer.initTexture(s.skel.boneTexture); },
    dispose() {
      for (const s of slots) { s.mat.dispose(); s.skel.dispose(); s.plain.removeFromParent(); s.skinned.removeFromParent(); }
      for (const p of proxies.values()) if (p) p.geo.dispose();
      proxies.clear();
      dummy.dispose();
    },
  };
}
