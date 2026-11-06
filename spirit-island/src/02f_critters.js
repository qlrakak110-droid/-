// ============================================================================
//  critters: sculpted (signed-distance) bodies for every regular spirit,
//  soft PBR "vinyl figure" skin with fur sheen and hand-drawn anime eyes
// ============================================================================
function animeEyeMat(iris = 0x2a1a4a, iris2 = 0x7a5aff) {
  const k = 'eye' + iris + '_' + iris2;
  if (_mc.has(k)) return _mc.get(k);
  const m = new THREE.ShaderMaterial({
    uniforms: THREE.UniformsUtils.merge([THREE.UniformsLib.fog, { uIris: { value: new THREE.Color(iris) }, uIris2: { value: new THREE.Color(iris2) } }]),
    vertexShader: `varying vec3 vN; ${FOG_V}
      void main(){ vN = normalize(position); vec4 mvPosition = modelViewMatrix * vec4(position, 1.0); gl_Position = projectionMatrix * mvPosition;
        #include <fog_vertex>
      }`,
    fragmentShader: `uniform vec3 uIris, uIris2; varying vec3 vN; ${FOG_F}
      void main(){
        vec3 n = normalize(vN);
        float rr = length(n.xy);
        vec3 col = vec3(0.97, 0.97, 1.0) * (0.82 + 0.18 * n.y);
        if (n.z > 0.0 && rr < 0.66) {
          float t = rr / 0.66;
          vec3 ic = mix(uIris2 * 1.25, uIris, smoothstep(-0.55, 0.55, n.y));
          ic *= 0.85 + 0.15 * sin(atan(n.y, n.x) * 22.0 + t * 6.0);
          ic = mix(ic, uIris * 0.25, smoothstep(0.78, 1.0, t));
          col = ic;
          if (rr < 0.3) col = vec3(0.02, 0.012, 0.04);
        }
        col = mix(col, vec3(1.25), smoothstep(0.15, 0.11, length(n.xy - vec2(0.2, 0.3))) * step(0.0, n.z));
        col = mix(col, vec3(1.05), smoothstep(0.075, 0.05, length(n.xy - vec2(-0.2, -0.24))) * step(0.0, n.z) * 0.9);
        col *= mix(0.62, 1.0, smoothstep(0.88, 0.58, n.y));
        gl_FragColor = vec4(col, 1.0);
        #include <fog_fragment>
      }`,
    fog: true,
  });
  _mc.set(k, m); return m;
}
function critterKit() {
  const prims = [], c = (h) => hexRGB(h);
  return {
    prims,
    el(p, r, col, o = {}) { prims.push(SDF.el(p, r, Object.assign({ k: 0.06, s0: 0.5, s1: 0.5, col: c(col) }, o))); },
    rc(a, b, r1, r2, col, o = {}) { prims.push(SDF.rc(a, b, r1, r2, Object.assign({ k: 0.05, s0: 0.5, s1: 0.5, col: c(col) }, o))); },
    sub(p, r, k = 0.03) { prims.push(SDF.el(p, r, { k, sub: true })); },
  };
}
const HEAD = { s0: 1, s1: 1 };
const add3 = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
const _critterDesigns = {};
function critter(key, fn) { if (!_critterDesigns[key]) _critterDesigns[key] = fn(); return _critterDesigns[key]; }

function buildCritter(r, cfg) {
  const D = cfg.design;
  r.olw = 0; r.hopAmp = cfg.hop ?? 0.6;
  if (cfg.float) { r.float = cfg.float; r.floatAmp = cfg.floatAmp ?? 0.1; }
  const B = grp(r.body); B.scale.setScalar(cfg.scale ?? 1);
  const DD = Object.assign({ jawHinge: [0, 0, 0], tailStart: 0.32, neckStart: 0.9 }, D);
  const geo = dragonGeometry('c_' + cfg.key, DD, 0.021, 0.03);
  const mat = dragonMaterial(Object.assign({ scaleFreq: 0, rough: 0.55, metal: 0, coat: 0.25, coatRough: 0.4, sheen: 0.35, sheenCol: 0xfff0e0, rim: 0xffffff, rimAmt: 0.1, waveAmp: 0.1, waveFreq: 3.2, waveSpeed: 3.4, soft: 0.16, fuzz: 0.12, hipY: D.hipY ?? 0.5, env: 0.35, sat: 1.35 }, cfg.mat), DD);
  const U = mat.userData.U; U.uSway.value = cfg.sway ?? 0.3;
  const body = new THREE.Mesh(geo, mat); body.castShadow = true; body.receiveShadow = true; B.add(body);
  const follow = [];
  const glue = (obj, s) => follow.push({ obj, base: obj.position.clone(), s });
  for (const e of D.eyes || []) {
    const g = grp(B, e.p, [e.pitch || 0, e.yaw || 0, e.roll || 0]);
    if (cfg.glowEye) { part(GEO.sphere, E(cfg.glowEye, 2.8), g, [0, 0, 0], [e.r, e.r * 0.7, e.r * 0.55]).userData.noOl = true; part(GEO.box, new THREE.MeshBasicMaterial({ color: 0x0a0612 }), g, [0, 0, e.r * 0.42], [e.r * 0.16, e.r * 1.1, e.r * 0.1]); }
    else part(GEO.sphere, animeEyeMat(cfg.iris ?? 0x2a1a4a, cfg.iris2 ?? 0x8a6aff), g, [0, 0, 0], [e.r, e.r * 1.18, e.r * 0.62]);
    r.blink.push(g); glue(g, 1);
  }
  r.fns.push((t) => {
    U.uWalk.value = r.walkPhase; U.uStride.value = (D.stride ?? 0.12) * r.moving;
    for (const f of follow) f.obj.position.copy(f.base).add(dragonOffset(U, f.s, Shared.time.value).multiplyScalar(1));
  });
  r.glue = glue; r.B = B; r.critter = { U, mat };
  r.size = (D.height ?? 1.3) * (cfg.scale ?? 1);
  return B;
}

// ---------------- 화르르 / 염호
function dFox(st) {
  return critter('fox' + st, () => {
    const K = critterKit(), O = st === 2 ? 0xf25a16 : 0xff6e1e, CR = 0xfff1dc, DK = 0x4a2016;
    const L = st === 2 ? 1.22 : 1, by = 0.5 * L, bz = st === 2 ? 0.5 : 0.42;
    K.el([0, by, 0], [0.32, 0.3, bz], O, { k: 0.1 });
    K.el([0, by + 0.04, 0.24], [0.24, 0.25, 0.22], CR, { k: 0.12 });
    K.el([0, by - 0.12, -0.04], [0.22, 0.14, bz * 0.8], CR, { k: 0.12 });
    for (const [sx, sz] of [[-1, 1], [1, 1], [-1, -1], [1, -1]]) {
      const hip = [sx * 0.16, by - 0.06, sz * (bz * 0.55)], paw = [sx * 0.18, 0.07, sz * (bz * 0.55) + 0.05];
      K.rc(hip, paw, 0.1, 0.07, O, { k: 0.07, leg: sx * sz > 0 ? 1 : -1 });
      K.el([paw[0], 0.055, paw[2] + 0.02], [0.085, 0.055, 0.1], DK, { k: 0.04, leg: sx * sz > 0 ? 1 : -1 });
    }
    const hc = [0, 0.98 * L, bz * 0.72];
    K.rc([0, by + 0.1, bz * 0.5], add3(hc, [0, -0.08, -0.05]), 0.17, 0.16, O, { k: 0.1, s0: 0.7, s1: 0.95 });
    K.el(hc, [0.33, 0.3, 0.29], O, Object.assign({ k: 0.08 }, HEAD));
    for (const sx of [-1, 1]) K.el(add3(hc, [sx * 0.2, -0.1, 0.06]), [0.16, 0.12, 0.14], CR, Object.assign({ k: 0.07 }, HEAD));
    K.el(add3(hc, [0, -0.09, 0.24]), [0.13, 0.09, 0.14], CR, Object.assign({ k: 0.06 }, HEAD));
    K.el(add3(hc, [0, -0.05, 0.37]), [0.045, 0.033, 0.03], DK, Object.assign({ k: 0.02 }, HEAD));
    const eh = st === 2 ? 1.18 : 1;
    for (const sx of [-1, 1]) {
      K.rc(add3(hc, [sx * 0.14, 0.18, -0.02]), add3(hc, [sx * 0.27, 0.5 * eh, -0.06]), 0.11, 0.012, O, Object.assign({ k: 0.05 }, HEAD));
      K.rc(add3(hc, [sx * 0.235, 0.4 * eh, -0.052]), add3(hc, [sx * 0.27, 0.51 * eh, -0.06]), 0.04, 0.008, DK, Object.assign({ k: 0.02 }, HEAD));
    }
    const tails = st === 2 ? [-0.22, 0, 0.22] : [0];
    for (const tx of tails) {
      const p0 = [tx * 0.3, by + 0.05, -bz * 0.85], p1 = [tx, by + 0.28, -bz - 0.22], p2 = [tx * 1.2, by + 0.58, -bz - 0.32], p3 = [tx * 1.3, by + 0.8, -bz - 0.25];
      K.rc(p0, p1, 0.1, 0.16, O, { k: 0.07, s0: 0.32, s1: 0.22 });
      K.rc(p1, p2, 0.16, 0.15, O, { k: 0.06, s0: 0.22, s1: 0.1 });
      K.rc(p2, p3, 0.15, 0.06, CR, { k: 0.05, s0: 0.1, s1: 0.0 });
    }
    return { prims: K.prims, bounds: [-0.75, -0.05, -bz - 0.75, 0.75, 1.75 * L, bz + 0.75], hipY: by, height: 1.45 * L, stride: 0.12,
      eyes: [-1, 1].map((sx) => ({ p: add3(hc, [sx * 0.135, 0.04, 0.255]), r: 0.08, yaw: sx * 0.28 })), tails: tails.map((tx) => [tx * 1.3, by + 0.86, -bz - 0.25]), hc };
  });
}
function foxModel(r, st) {
  const D = dFox(st);
  const B = buildCritter(r, { key: 'fox' + st, design: D, scale: st === 2 ? 1.25 : 1, iris: st === 2 ? 0x7a2a08 : 0x3a1a10, iris2: st === 2 ? 0xffb02e : 0xff9a4a, mat: { sheenCol: 0xffb070 } });
  for (const tp of D.tails) { const f = flame(r, B, tp, st === 2 ? 0.72 : 0.8); r.glue(f, 0); }
  if (st === 2) {
    for (let i = 0; i < 7; i++) { const a = (i / 7) * Math.PI * 2; const f = flame(r, B, [Math.cos(a) * 0.24, 0.78 + Math.sin(a) * 0.05, 0.42 + Math.sin(a) * 0.1], 0.6); f.rotation.set(Math.sin(a) * 0.4, 0, -Math.cos(a) * 0.6); r.glue(f, 0.8); }
    const gem = part(GEO.octa, E(0xffd25a, 2.6), B, add3(D.hc, [0, 0.16, 0.27]), [0.045, 0.07, 0.03]); r.glue(gem, 1);
  }
  r.size = 1.4 * (st === 2 ? 1.25 : 1);
}
MODELS.hwarr = (r) => foxModel(r, 1);
MODELS.yeomho = (r) => foxModel(r, 2);

// ---------------- 물롱 / 파도롱
function dSeal(st) {
  return critter('seal' + st, () => {
    const K = critterKit(), BL = st === 2 ? 0x3aa6ef : 0x5cc8ff, WH = 0xeaf8ff, FN = 0x8fe3ff, DK = 0x163049;
    K.el([0, 0.44, 0], [0.46, 0.4, 0.55], BL, { k: 0.12 });
    K.el([0, 0.36, 0.14], [0.35, 0.29, 0.42], WH, { k: 0.12 });
    K.rc([0, 0.36, -0.38], [0, 0.2, -0.62], 0.25, 0.1, BL, { k: 0.1, s0: 0.3, s1: 0.1 });
    for (const sx of [-1, 1]) {
      K.el([sx * 0.15, 0.17, -0.7], [0.17, 0.045, 0.12], FN, { k: 0.05, s0: 0.05, s1: 0.05 });
      K.el([sx * 0.5, 0.17, 0.22], [0.2, 0.05, 0.12], BL, { k: 0.07, leg: sx });
    }
    const hc = [0, 0.9, 0.2];
    K.el(hc, [0.38, 0.35, 0.35], BL, Object.assign({ k: 0.14 }, HEAD));
    K.el(add3(hc, [0, -0.12, 0.24]), [0.2, 0.13, 0.15], WH, Object.assign({ k: 0.06 }, HEAD));
    K.el(add3(hc, [0, -0.06, 0.38]), [0.05, 0.035, 0.03], DK, Object.assign({ k: 0.02 }, HEAD));
    for (const sx of [-1, 1]) K.el(add3(hc, [sx * 0.36, 0.1, -0.02]), [0.22 * (st === 2 ? 1.25 : 1), 0.055, 0.13], FN, Object.assign({ k: 0.05 }, HEAD));
    if (st === 2) for (let i = 0; i < 3; i++) K.rc(add3(hc, [0, 0.3 - i * 0.04, -0.08 - i * 0.12]), add3(hc, [0, 0.56 - i * 0.06, -0.28 - i * 0.14]), 0.06, 0.008, 0x2d7fd4, Object.assign({ k: 0.04 }, HEAD));
    return { prims: K.prims, bounds: [-0.85, -0.05, -0.95, 0.85, 1.4, 0.75], hipY: 0.3, height: 1.4, stride: 0.06,
      eyes: [-1, 1].map((sx) => ({ p: add3(hc, [sx * 0.16, 0.06, 0.295]), r: 0.088, yaw: sx * 0.3 })), hc };
  });
}
function sealModel(r, st) {
  const D = dSeal(st);
  const B = buildCritter(r, { key: 'seal' + st, design: D, scale: st === 2 ? 1.36 : 1, hop: 0.5, iris: 0x0a2a5a, iris2: 0x3fb8ff, mat: { coat: 0.6, coatRough: 0.15, sheen: 0.3, rough: 0.35 } });
  const orb = grp(B, add3(D.hc, [0, 0.5, -0.04]));
  part(GEO.sphere, toonMat({ color: 0xa6f0ff, transparent: true, opacity: 0.5 }), orb, [0, 0, 0], 0.15);
  part(GEO.sphere, E(0x9cf0ff, 2.2), orb, [0, 0, 0], 0.06);
  part(GEO.sphere, E(0xffffff, 1.8), orb, [0.05, 0.06, 0.08], 0.025);
  r.fns.push((t) => { orb.userData.bob = Math.sin(t * 2.5) * 0.04; });
  r.glue(orb, 1);
  if (st === 2) {
    const ring = grp(B, [0, 0.5, 0], [Math.PI / 2, 0, 0]);
    part(GEO.torus, E(0x7fe8ff, 2.0), ring, [0, 0, 0], 0.82);
    for (let i = 0; i < 6; i++) { const a = (i / 6) * Math.PI * 2; part(GEO.sphere, E(0xbff6ff, 2.4), ring, [Math.cos(a) * 0.82, Math.sin(a) * 0.82, 0], 0.045); }
    spin(r, ring, 'z', 0.8);
  }
  r.size = 1.45 * (st === 2 ? 1.36 : 1);
}
MODELS.mullong = (r) => sealModel(r, 1);
MODELS.padolong = (r) => sealModel(r, 2);

// ---------------- 새싹뿔 / 숲뿔사슴
function dFawn(st) {
  return critter('fawn' + st, () => {
    const K = critterKit(), FW = st === 2 ? 0xa36a40 : 0xc58a56, CR = 0xfff1d8, LF = 0x6ee06a, DK = 0x3a2416;
    const LL = st === 2 ? 1.18 : 1;
    K.el([0, 0.78 * LL, 0], [0.29, 0.27, 0.47], FW, { k: 0.1 });
    K.el([0, 0.7 * LL, 0.04], [0.21, 0.17, 0.37], CR, { k: 0.1 });
    for (const [x, z] of [[0.1, 0.1], [-0.12, -0.05], [0.06, -0.22], [-0.05, 0.25], [0.14, -0.12]]) K.el([x, 0.78 * LL + 0.25, z], [0.045, 0.02, 0.045], CR, { k: 0.02 });
    for (const [sx, sz] of [[-1, 1], [1, 1], [-1, -1], [1, -1]]) {
      const hip = [sx * 0.15, 0.66 * LL, sz * 0.26], hoof = [sx * 0.15, 0.07, sz * 0.27];
      K.rc(hip, hoof, 0.075, 0.045, FW, { k: 0.06, leg: sx * sz > 0 ? 1 : -1 });
      K.el([hoof[0], 0.045, hoof[2] + 0.01], [0.055, 0.045, 0.065], DK, { k: 0.02, leg: sx * sz > 0 ? 1 : -1 });
    }
    const hc = [0, 1.27 * LL, 0.45];
    K.rc([0, 0.9 * LL, 0.3], add3(hc, [0, -0.08, -0.06]), 0.12, 0.1, FW, { k: 0.08, s0: 0.7, s1: 0.95 });
    K.el(hc, [0.24, 0.23, 0.26], FW, Object.assign({ k: 0.07 }, HEAD));
    K.el(add3(hc, [0, -0.07, 0.2]), [0.13, 0.11, 0.14], CR, Object.assign({ k: 0.06 }, HEAD));
    K.el(add3(hc, [0, -0.04, 0.33]), [0.04, 0.03, 0.025], DK, Object.assign({ k: 0.02 }, HEAD));
    for (const sx of [-1, 1]) K.el(add3(hc, [sx * 0.29, 0.07, -0.03]), [0.17, 0.04, 0.085], LF, Object.assign({ k: 0.05 }, HEAD));
    if (st === 2) {
      for (const sx of [-1, 1]) {
        const a = add3(hc, [sx * 0.1, 0.18, -0.06]), b = add3(hc, [sx * 0.24, 0.62, -0.18]), c2 = add3(hc, [sx * 0.3, 0.85, -0.3]);
        K.rc(a, b, 0.035, 0.028, 0x6b4a2e, Object.assign({ k: 0.03 }, HEAD));
        K.rc(b, c2, 0.028, 0.012, 0x6b4a2e, Object.assign({ k: 0.02 }, HEAD));
        K.rc(add3(hc, [sx * 0.17, 0.4, -0.12]), add3(hc, [sx * 0.42, 0.55, -0.05]), 0.022, 0.01, 0x6b4a2e, Object.assign({ k: 0.02 }, HEAD));
        K.rc(add3(hc, [sx * 0.22, 0.55, -0.16]), add3(hc, [sx * 0.15, 0.78, -0.08]), 0.02, 0.008, 0x6b4a2e, Object.assign({ k: 0.02 }, HEAD));
      }
    }
    K.el([0, 0.86 * LL, -0.48], [0.07, 0.085, 0.06], 0xffffff, { k: 0.04, s0: 0.2, s1: 0.2 });
    return { prims: K.prims, bounds: [-0.7, -0.05, -0.75, 0.7, (st === 2 ? 2.4 : 1.75) * LL, 0.95], hipY: 0.66 * LL, height: 1.6 * LL, stride: 0.14,
      eyes: [-1, 1].map((sx) => ({ p: add3(hc, [sx * 0.125, 0.05, 0.19]), r: 0.072, yaw: sx * 0.32 })), hc };
  });
}
function fawnModel(r, st) {
  const D = dFawn(st);
  const B = buildCritter(r, { key: 'fawn' + st, design: D, scale: st === 2 ? 1.25 : 1, iris: 0x1a3a10, iris2: 0x7ad86a, mat: { sheenCol: 0xffe6c0 } });
  const sp = grp(B, add3(D.hc, [0, 0.22, 0]));
  part(GEO.cyl, M(0x4fbf5f), sp, [0, 0.08, 0], [0.02, 0.18, 0.02]);
  for (const s of [-1, 1]) part(GEO.sphere, M(0x6ee06a), sp, [s * 0.08, 0.18, 0], [0.1, 0.03, 0.06], [0, 0, s * 0.5]);
  wig(r, sp, 'z', 0.15, 2.8); r.glue(sp, 1);
  if (st === 2) {
    for (const sx of [-1, 1]) for (const [x, y, z] of [[0.3, 0.88, -0.3], [0.42, 0.58, -0.05], [0.15, 0.8, -0.08]]) {
      const g = grp(B, add3(D.hc, [sx * x, y, z]));
      part(GEO.ico1, M(0x4fbf5f), g, [0, 0, 0], 0.09);
      part(GEO.sphere, E(pick([0xffb3e6, 0xfff4b0, 0xc8b3ff]), 2.3), g, [0.05, 0.05, 0.05], 0.035);
      r.glue(g, 1);
    }
  }
  r.size = 1.6 * (st === 2 ? 1.25 : 1);
}
MODELS.saessak = (r) => fawnModel(r, 1);
MODELS.supppul = (r) => fawnModel(r, 2);

// ---------------- 찌릿파리 : storm jelly (glassy)
MODELS.jjirit = (r) => {
  const D = critter('jelly', () => {
    const K = critterKit(), Y = 0xffd84a;
    K.el([0, 0.05, 0], [0.5, 0.45, 0.5], Y, { k: 0.08 });
    K.sub([0, -0.36, 0], [0.62, 0.36, 0.62], 0.09);
    for (let i = 0; i < 10; i++) { const a = (i / 10) * Math.PI * 2; K.el([Math.cos(a) * 0.45, -0.02, Math.sin(a) * 0.45], [0.08, 0.06, 0.08], 0xffb02e, { k: 0.05 }); }
    return { prims: K.prims, bounds: [-0.65, -0.25, -0.65, 0.65, 0.6, 0.65], hipY: 0, height: 1.0, eyes: [-1, 1].map((sx) => ({ p: [sx * 0.16, 0.22, 0.4], r: 0.08, yaw: sx * 0.3, pitch: -0.2 })) };
  });
  const B = buildCritter(r, { key: 'jelly', design: D, float: 1.0, floatAmp: 0.12, iris: 0x3a2a00, iris2: 0xffd84a, mat: { rough: 0.15, coat: 1.0, coatRough: 0.05, sheen: 0, soft: 0.45, fuzz: 0.0, rimAmt: 0.45, rim: 0xfff2a0 } });
  const core = part(GEO.sphere, E(0xfff6c8, 3.2), B, [0, 0.16, 0], 0.13);
  r.fns.push((t) => core.scale.setScalar(0.13 * (1 + Math.sin(t * 9) * 0.15 * Math.max(0, Math.sin(t * 1.3)))));
  for (let i = 0; i < 6; i++) {
    const a = (i / 6) * Math.PI * 2 + 0.3;
    let p = grp(B, [Math.cos(a) * 0.24, -0.06, Math.sin(a) * 0.24]);
    for (let k = 0; k < 4; k++) { part(GEO.cyl, E(0xfff0a0, 1.25), p, [0, -0.1, 0], [0.024 - k * 0.003, 0.2, 0.024 - k * 0.003]); wig(r, p, 'x', 0.22, 2.4, i + k * 0.8); wig(r, p, 'z', 0.18, 1.9, i * 2 + k); p = grp(p, [0, -0.2, 0]); }
    part(GEO.sphere, E(0xfffbd0, 3), p, [0, 0, 0], 0.035);
  }
  for (const s of [-1, 1]) { const an = grp(B, [s * 0.12, 0.45, 0], [0, 0, -s * 0.3]); part(GEO.cyl, M(0xffbf2e), an, [0, 0.08, 0], [0.018, 0.16, 0.018]); part(GEO.octa, E(0xffffff, 3), an, [0, 0.19, 0], 0.04); wig(r, an, 'z', 0.2, 4, s); }
  r.size = 1.6;
};

// ---------------- 바위몽 : rock golem (displaced stone)
MODELS.bawimong = (r) => {
  const D = critter('rock', () => {
    const K = critterKit(), RK = 0x8c8378, RK2 = 0xa59c90;
    K.el([0, 0.55, 0], [0.55, 0.47, 0.51], RK, { k: 0.1, nz: 0.08, nf: 5.5 });
    K.el([0, 0.58, 0.27], [0.34, 0.29, 0.2], RK2, { k: 0.08, nz: 0.03, nf: 8, s0: 1, s1: 1 });
    K.el([0.05, 0.96, 0.1], [0.27, 0.07, 0.21], 0x5f9a4a, { k: 0.05, nz: 0.03, nf: 10 });
    for (const sx of [-1, 1]) {
      K.el([sx * 0.58, 0.46, 0.04], [0.18, 0.2, 0.18], RK, { k: 0.08, nz: 0.05, nf: 7, leg: sx });
      K.el([sx * 0.25, 0.12, 0.05], [0.17, 0.12, 0.2], 0x766d63, { k: 0.06, nz: 0.03, nf: 8, leg: -sx });
    }
    return { prims: K.prims, bounds: [-0.85, -0.05, -0.65, 0.85, 1.1, 0.7], hipY: 0.3, height: 1.3, stride: 0.08, eyes: [-1, 1].map((sx) => ({ p: [sx * 0.15, 0.63, 0.44], r: 0.074, yaw: sx * 0.25 })) };
  });
  const B = buildCritter(r, { key: 'rock', design: D, hop: 0.35, iris: 0x1a1030, iris2: 0x9b7bff, sway: 0.15, mat: { rough: 0.85, sheen: 0.1, coat: 0, soft: 0.25, fuzz: 0.05 } });
  part(GEO.box, new THREE.MeshBasicMaterial({ color: 0x2a1f1a }), B, [0, 0.48, 0.47], [0.12, 0.025, 0.02]);
  for (const [x, y, z, w, h, rx, rz] of [[0, 1.02, -0.18, 0.13, 0.36, -0.3, 0], [-0.24, 0.9, -0.26, 0.1, 0.27, -0.5, 0.5], [0.26, 0.88, -0.24, 0.1, 0.25, -0.5, -0.5], [0.05, 0.72, -0.5, 0.08, 0.22, -1.2, 0]]) part(GEO.cone6, E(0x9b7bff, 1.9), B, [x, y, z], [w, h, w], [rx, 0, rz]);
  r.size = 1.3;
};

// ---------------- 반디루 : lantern firefly
MODELS.bandiru = (r) => {
  const D = critter('firefly', () => {
    const K = critterKit();
    K.el([0, 0, 0], [0.31, 0.29, 0.31], 0xfff0c9, { k: 0.08, s0: 1, s1: 1 });
    K.el([0, -0.14, 0], [0.31, 0.12, 0.3], 0xffe2a0, { k: 0.08 });
    K.el([0, -0.08, -0.22], [0.16, 0.15, 0.16], 0xffe9b0, { k: 0.08, s0: 0.2, s1: 0.2 });
    return { prims: K.prims, bounds: [-0.45, -0.35, -0.5, 0.45, 0.4, 0.45], hipY: 0, height: 1.0, eyes: [-1, 1].map((sx) => ({ p: [sx * 0.12, 0.05, 0.25], r: 0.088, yaw: sx * 0.3 })) };
  });
  const B = buildCritter(r, { key: 'firefly', design: D, float: 0.9, floatAmp: 0.1, iris: 0x2a1a00, iris2: 0xffb84a, mat: { sheenCol: 0xfff2c0, fuzz: 0.3, soft: 0.3 } });
  for (const s of [-1, 1]) { const an = grp(B, [s * 0.1, 0.25, 0.08], [0.3, 0, -s * 0.35]); part(GEO.cyl, M(0x3a2c22), an, [0, 0.13, 0], [0.014, 0.26, 0.014]); part(GEO.sphere, E(0xfff3a0, 3), an, [0, 0.28, 0], 0.045); wig(r, an, 'z', 0.15, 3, s); }
  const wingM = toonMat({ color: 0xe6f8ff, transparent: true, opacity: 0.5, side: THREE.DoubleSide });
  for (const s of [-1, 1]) for (const k of [0, 1]) { const w = grp(B, [s * 0.12, 0.18 - k * 0.08, -0.1 - k * 0.04], [0, 0, s * (0.35 - k * 0.6)]); part(GEO.sphere, wingM, w, [s * 0.3, 0, 0], [0.32 - k * 0.08, 0.02, 0.15]); wig(r, w, 'z', 0.45, 22, k * 1.5 + (s > 0 ? 0 : Math.PI)); }
  const ab = part(GEO.sphere, E(0xfff2a0, 3.2), B, [0, -0.1, -0.36], [0.2, 0.19, 0.25]);
  r.fns.push((t) => { const k = 1 + Math.sin(t * 3) * 0.08; ab.scale.set(0.2 * k, 0.19 * k, 0.25 * k); });
  r.size = 1.35;
};

// ---------------- 그림냥 : shade cat
MODELS.geurim = (r) => {
  const D = critter('cat', () => {
    const K = critterKit(), SH = 0x3a2a5c, SD = 0x281c44;
    K.el([0, 0.45, 0], [0.29, 0.26, 0.44], SH, { k: 0.1 });
    for (const [sx, sz] of [[-1, 1], [1, 1], [-1, -1], [1, -1]]) {
      const hip = [sx * 0.15, 0.4, sz * 0.24], paw = [sx * 0.16, 0.06, sz * 0.25 + 0.03];
      K.rc(hip, paw, 0.085, 0.06, SH, { k: 0.06, leg: sx * sz > 0 ? 1 : -1 });
      K.el([paw[0], 0.045, paw[2] + 0.02], [0.07, 0.045, 0.085], SD, { k: 0.03, leg: sx * sz > 0 ? 1 : -1 });
    }
    const hc = [0, 0.86, 0.3];
    K.rc([0, 0.55, 0.25], add3(hc, [0, -0.1, -0.05]), 0.15, 0.14, SH, { k: 0.08, s0: 0.7, s1: 0.95 });
    K.el(hc, [0.33, 0.28, 0.29], SH, Object.assign({ k: 0.08 }, HEAD));
    K.el(add3(hc, [0, -0.1, 0.18]), [0.15, 0.1, 0.12], 0x4b3a72, Object.assign({ k: 0.06 }, HEAD));
    for (const sx of [-1, 1]) K.rc(add3(hc, [sx * 0.15, 0.17, -0.02]), add3(hc, [sx * 0.24, 0.45, -0.04]), 0.11, 0.012, SH, Object.assign({ k: 0.05 }, HEAD));
    const t0 = [0, 0.5, -0.42], t1 = [0, 0.62, -0.62], t2 = [0.05, 0.9, -0.72], t3 = [0.12, 1.12, -0.62];
    K.rc(t0, t1, 0.08, 0.075, SH, { k: 0.05, s0: 0.32, s1: 0.22 });
    K.rc(t1, t2, 0.075, 0.065, SH, { k: 0.04, s0: 0.22, s1: 0.1 });
    K.rc(t2, t3, 0.065, 0.04, 0x4b3a72, { k: 0.04, s0: 0.1, s1: 0 });
    return { prims: K.prims, bounds: [-0.6, -0.05, -0.95, 0.6, 1.4, 0.75], hipY: 0.4, height: 1.3, stride: 0.12, tip: t3,
      eyes: [-1, 1].map((sx) => ({ p: add3(hc, [sx * 0.13, 0.03, 0.255]), r: 0.085, yaw: sx * 0.3, roll: sx * 0.22 })) };
  });
  const B = buildCritter(r, { key: 'cat', design: D, glowEye: 0xffd84a, mat: { sheenCol: 0xb48cff, sheen: 0.6, fuzz: 0.3, rim: 0xb48cff, rimAmt: 0.3 } });
  const smoke = grp(B, D.tip);
  for (let k = 0; k < 4; k++) part(GEO.sphere, E([0x7a4bd6, 0xa77bff, 0x5b3f8f, 0xc7a6ff][k], 1.2 + k * 0.2, { transparent: true, opacity: 0.55 - k * 0.1, depthWrite: false }), smoke, [Math.sin(k) * 0.05, k * 0.08, -k * 0.03], 0.07 - k * 0.012);
  wig(r, smoke, 'z', 0.3, 2); r.glue(smoke, 0);
  part(GEO.torus, E(0xb48cff, 1.8), B, [0, 0.68, 0.22], [0.19, 0.19, 0.19], [1.25, 0, 0]);
  r.size = 1.3;
};

// ---------------- 솜구름 : cloud lamb
MODELS.somgu = (r) => {
  const D = critter('lamb', () => {
    const K = critterKit(), W = 0xf6f3ff, LV = 0xcfc4f2;
    for (const [x, y, z, s] of [[0, 0.62, 0, 0.4], [0.25, 0.7, 0.1, 0.24], [-0.25, 0.7, 0.1, 0.24], [0.2, 0.85, -0.15, 0.25], [-0.2, 0.85, -0.15, 0.25], [0, 0.95, 0.05, 0.26], [0.3, 0.52, -0.2, 0.21], [-0.3, 0.52, -0.2, 0.21], [0, 0.6, -0.35, 0.25], [0, 0.84, 0.24, 0.2], [0.18, 0.5, 0.2, 0.2], [-0.18, 0.5, 0.2, 0.2]]) K.el([x, y, z], [s, s, s], W, { k: 0.05 });
    for (const [sx, sz] of [[-1, 1], [1, 1], [-1, -1], [1, -1]]) K.rc([sx * 0.17, 0.32, sz * 0.18], [sx * 0.18, 0.04, sz * 0.19], 0.065, 0.055, 0x4a4368, { k: 0.04, leg: sx * sz > 0 ? 1 : -1 });
    const hc = [0, 0.66, 0.42];
    K.el(hc, [0.22, 0.2, 0.18], LV, Object.assign({ k: 0.07 }, HEAD));
    for (const sx of [-1, 1]) K.el(add3(hc, [sx * 0.24, 0.0, -0.04]), [0.11, 0.04, 0.06], LV, Object.assign({ k: 0.04 }, HEAD));
    return { prims: K.prims, bounds: [-0.65, -0.05, -0.7, 0.65, 1.3, 0.75], hipY: 0.32, height: 1.3, stride: 0.08, hc, eyes: [-1, 1].map((sx) => ({ p: add3(hc, [sx * 0.085, 0.03, 0.155]), r: 0.058, yaw: sx * 0.32 })) };
  });
  const B = buildCritter(r, { key: 'lamb', design: D, iris: 0x2a2050, iris2: 0x9a8aff, mat: { rough: 0.8, sheen: 0.8, sheenCol: 0xffffff, coat: 0, fuzz: 0.35, soft: 0.3 } });
  const horn = new THREE.TorusGeometry(0.1, 0.035, 8, 18, Math.PI * 1.35);
  for (const s of [-1, 1]) { const h = part(horn, M(0xe6c27a), B, add3(D.hc, [s * 0.2, 0.12, -0.04]), 1, [0, s * 1.3, s > 0 ? 0.5 : 2.6]); r.glue(h, 1); }
  r.size = 1.35;
};

// ---------------- 버섯콩 : mushroom sprite
MODELS.beoseot = (r) => {
  const D = critter('shroom', () => {
    const K = critterKit(), RD = 0xe8475a, CR = 0xf8ead2;
    K.el([0, 0.38, 0], [0.29, 0.35, 0.27], CR, { k: 0.08 });
    K.el([0, 0.68, 0], [0.6, 0.42, 0.6], RD, { k: 0.06, s0: 0.9, s1: 0.9 });
    K.sub([0, 0.47, 0], [0.66, 0.2, 0.66], 0.05);
    K.el([0, 0.64, 0], [0.48, 0.035, 0.48], 0xf2d6b0, { k: 0.04 });
    for (const [a, ph] of [[0, 0.95], [0.9, 0.55], [2.1, 0.6], [3.3, 0.5], [4.4, 0.62], [5.4, 0.55], [1.5, 1.05], [3.9, 1.0]]) K.el([Math.cos(a) * Math.sin(ph) * 0.58, 0.68 + Math.cos(ph) * 0.42, Math.sin(a) * Math.sin(ph) * 0.58], [0.085, 0.05, 0.085], 0xfff6ea, { k: 0.02, s0: 0.9, s1: 0.9 });
    for (const sx of [-1, 1]) {
      K.el([sx * 0.13, 0.06, 0.05], [0.1, 0.07, 0.13], 0xd9b98f, { k: 0.05, leg: sx });
      K.el([sx * 0.3, 0.36, 0], [0.06, 0.1, 0.06], CR, { k: 0.05 });
    }
    return { prims: K.prims, bounds: [-0.75, -0.05, -0.75, 0.75, 1.2, 0.75], hipY: 0.2, height: 1.2, stride: 0.07, eyes: [-1, 1].map((sx) => ({ p: [sx * 0.11, 0.42, 0.24], r: 0.07, yaw: sx * 0.28 })) };
  });
  buildCritter(r, { key: 'shroom', design: D, iris: 0x3a1010, iris2: 0xff7a6a, sway: 0.2, mat: { rough: 0.5, coat: 0.5, coatRough: 0.3, sheen: 0.4, soft: 0.5 } });
  r.size = 1.2;
};

// ---------------- 별씨 : starseed plush
MODELS.byeolssi = (r) => {
  const D = critter('star', () => {
    const K = critterKit();
    K.el([0, 0, 0], [0.3, 0.3, 0.26], 0xfff3d0, { k: 0.1, s0: 1, s1: 1 });
    for (let i = 0; i < 5; i++) { const a = (i / 5) * Math.PI * 2 + Math.PI / 2; K.rc([0, 0, -0.02], [Math.cos(a) * 0.58, Math.sin(a) * 0.58, -0.04], 0.2, 0.06, 0xffe08a, { k: 0.12, s0: 1, s1: 1 }); }
    return { prims: K.prims, bounds: [-0.75, -0.75, -0.4, 0.75, 0.75, 0.4], hipY: 0, height: 1.2, eyes: [-1, 1].map((sx) => ({ p: [sx * 0.105, 0.04, 0.235], r: 0.066, yaw: sx * 0.3 })) };
  });
  const B = buildCritter(r, { key: 'star', design: D, float: 1.05, floatAmp: 0.12, iris: 0x4a2a00, iris2: 0xffc04a, mat: { sheenCol: 0xfff0b0, soft: 0.35, rim: 0xffe08a, rimAmt: 0.3 } });
  spin(r, B, 'z', 0.0);
  const halo = part(GEO.torus, E(0xffe08a, 2.4), B, [0, 0.62, 0], 0.2, [Math.PI / 2, 0, 0]);
  r.fns.push((t) => { halo.position.y = 0.62 + Math.sin(t * 3) * 0.03; B.rotation.z = Math.sin(t * 0.8) * 0.15; });
  r.size = 1.6;
};
