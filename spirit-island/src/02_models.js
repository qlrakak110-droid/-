// ============================================================================
//  models: procedural toon spirits, the two legends, people
// ============================================================================
const OL = 0x1a1026;

function newRig() {
  const root = new THREE.Group();
  const body = grp(root);
  return { root, body, blink: [], wig: [], spin: [], fns: [], float: 0, floatAmp: 0.07, hopAmp: 1, t: Math.random() * 10, nb: rand(1, 4), bt: 0, size: 1.3, moving: 0, walkPhase: 0, olw: 0.03 };
}
function rigUpdate(r, dt) {
  r.t += dt; const t = r.t, mv = r.moving;
  r.walkPhase += dt * (6 + mv * 7) * (mv > 0.05 ? 1 : 0.4);
  const hop = mv > 0.05 && !r.float ? Math.abs(Math.sin(r.walkPhase)) * 0.09 * r.hopAmp * mv : 0;
  r.body.position.y = (r.float ? r.float + Math.sin(t * 2.1) * r.floatAmp : 0) + hop;
  if (!r.noBreath) r.body.scale.set(1 - Math.sin(t * 2.4) * 0.012, 1 + Math.sin(t * 2.4) * 0.022, 1);
  r.nb -= dt;
  if (r.nb < 0) { r.bt = 0.13; r.nb = rand(2.2, 5); }
  if (r.bt > 0) r.bt -= dt;
  const ey = r.bt > 0 ? 0.12 : 1;
  for (const e of r.blink) e.scale.y = ey;
  if (r.blinkU) for (const u of r.blinkU) u.value = damp(u.value, r.bt > 0 ? 1 : 0, 40, dt);
  for (const w of r.wig) {
    const amp = w.walk ? w.amp * mv : w.amp * (1 + mv * 0.6);
    const ph = w.walk ? r.walkPhase * (w.f || 1) : t * w.f;
    w.o.rotation[w.ax] = w.base + Math.sin(ph + w.ph) * amp;
  }
  for (const s of r.spin) s.o.rotation[s.ax] += s.v * dt;
  for (const f of r.fns) f(t, dt, mv);
}
const wig = (r, o, ax, amp, f, ph = 0, walk = false) => { r.wig.push({ o, ax, amp, f, ph, base: o.rotation[ax], walk }); };
const spin = (r, o, ax, v) => r.spin.push({ o, ax, v });

function eyes(r, parent, { x = 0.15, y = 0.04, z = 0.28, rad = 0.075, pupil = 0x1b1030, iris = null, glowc = null, tilt = 0 } = {}) {
  for (const s of [-1, 1]) {
    const g = grp(parent, [s * x, y, z], [0, s * 0.25, s * tilt]);
    if (glowc) {
      part(GEO.sphere, E(glowc, 2.6), g, [0, 0, 0], [rad, rad * 0.75, rad * 0.5]).userData.noOl = true;
      part(GEO.box, new THREE.MeshBasicMaterial({ color: 0x0a0612 }), g, [0, 0, rad * 0.45], [rad * 0.18, rad * 1.2, rad * 0.1]);
    } else {
      const w = part(GEO.sphere, M(0xffffff), g, [0, 0, 0], [rad, rad * 1.18, rad * 0.55]); w.userData.noOl = true;
      if (iris) part(GEO.sphere, M(iris), g, [0, -rad * 0.05, rad * 0.3], [rad * 0.78, rad * 0.95, rad * 0.4]).userData.noOl = true;
      part(GEO.sphere, new THREE.MeshBasicMaterial({ color: pupil }), g, [0, -rad * 0.05, rad * 0.42], [rad * 0.52, rad * 0.68, rad * 0.32]);
      part(GEO.sphere, E(0xffffff, 1.4), g, [rad * 0.28, rad * 0.35, rad * 0.62], rad * 0.24);
      part(GEO.sphere, E(0xffffff, 1.1), g, [-rad * 0.22, -rad * 0.3, rad * 0.62], rad * 0.1);
    }
    r.blink.push(g);
  }
}
function blush(parent, x, y, z, s = 0.06) {
  for (const k of [-1, 1]) { const b = part(GEO.sphere, M(0xff8fa6, { transparent: true, opacity: 0.55 }), parent, [k * x, y, z], [s, s * 0.55, s * 0.3], [0, k * 0.5, 0]); b.userData.noOl = true; }
}
// animated billboard flame: noise-driven fire shape on a camera-facing quad (additive)
let _flameMat = null;
function flameMat() {
  if (_flameMat) return _flameMat;
  _flameMat = new THREE.ShaderMaterial({
    uniforms: { uTime: Shared.time },
    vertexShader: `attribute float aSeed; varying vec2 vUv; varying float vSeed;
      void main(){ vUv = uv; vSeed = aSeed;
        vec4 mv = modelViewMatrix * vec4(0.0, 0.0, 0.0, 1.0);
        vec3 sx = vec3(length(modelMatrix[0].xyz), length(modelMatrix[1].xyz), 1.0);
        mv.xy += vec2(position.x * sx.x, (position.y + 0.32) * sx.y);
        gl_Position = projectionMatrix * mv; }`,
    fragmentShader: `uniform float uTime; varying vec2 vUv; varying float vSeed;
      ${GLSL_NOISE}
      void main(){
        vec2 p = vUv; float t = uTime * 2.6 + vSeed * 17.0;
        float n = vnoise(vec2(p.x * 5.0 + vSeed * 9.0, p.y * 4.0 - t)) * 0.6 + vnoise(vec2(p.x * 11.0, p.y * 9.0 - t * 1.7)) * 0.4;
        float w = (1.0 - p.y) * 0.62 + 0.04;
        float dx = abs(p.x - 0.5 + (n - 0.5) * 0.28 * p.y);
        float body = smoothstep(w, w * 0.25, dx) * smoothstep(0.0, 0.12, p.y) * smoothstep(1.0, 0.45 + n * 0.25, p.y);
        float core = smoothstep(w * 0.55, 0.0, dx) * smoothstep(0.75, 0.1, p.y) * smoothstep(0.0, 0.1, p.y);
        vec3 col = mix(vec3(0.9, 0.16, 0.02), vec3(1.0, 0.5, 0.08), body) + vec3(1.0, 0.8, 0.35) * core * 0.6;
        float a = clamp(body * 0.9 + core * 0.6, 0.0, 1.0);
        if (a < 0.01) discard;
        gl_FragColor = vec4(col * a * 1.15, 1.0);
      }`,
    blending: THREE.AdditiveBlending, transparent: true, depthWrite: false, side: THREE.DoubleSide,
  });
  return _flameMat;
}
let _flameGeo = null;
function flame(r, parent, pos, s = 1) {
  if (!_flameGeo) { _flameGeo = new THREE.PlaneGeometry(0.42, 0.95); _flameGeo.setAttribute('aSeed', new THREE.BufferAttribute(new Float32Array(4), 1)); }
  const g = grp(parent, pos);
  const geo = _flameGeo.clone(); const seed = Math.random(); geo.attributes.aSeed.array.fill(seed);
  const m = new THREE.Mesh(geo, flameMat()); m.scale.setScalar(s); m.renderOrder = 5; m.frustumCulled = false; g.add(m);
  const glow = part(GEO.sphere, E(0xff9a3a, 1.5), g, [0, 0.03 * s, 0], 0.05 * s);
  const ph = Math.random() * 9;
  r.fns.push((t) => { m.scale.set(s * (1 + Math.sin(t * 9 + ph) * 0.06), s * (1 + Math.sin(t * 13 + ph) * 0.1), s); glow.scale.setScalar(0.07 * s * (1 + Math.sin(t * 11 + ph) * 0.15)); });
  return g;
}
function legs4(r, B, { x = 0.2, y = 0.36, z = 0.22, len = 0.2, w = 0.1, col, paw }) {
  for (const [sx, sz] of [[-1, 1], [1, 1], [-1, -1], [1, -1]]) {
    const p = grp(B, [sx * x, y, sz * z]);
    part(GEO.sphere, M(col), p, [0, -len * 0.75, 0], [w, len, w]);
    if (paw) part(GEO.sphere, M(paw), p, [0, -len * 1.6, 0.02], [w * 1.08, w * 0.62, w * 1.25]);
    wig(r, p, 'x', 0.55, 1, (sx * sz > 0 ? 0 : Math.PI), true);
  }
}

const MODELS = {};

// ---------- 화르르 / 염호 : flame fox
function buildFox(r, st) {
  const S = st === 2 ? 1.32 : 1;
  const B = grp(r.body); B.scale.setScalar(S);
  const OR = 0xff8a3d, CR = 0xfff0d8, DK = 0x4a2016;
  const L = st === 2 ? 1.25 : 1;
  part(GEO.sphere, M(OR), B, [0, 0.5 * L, 0], [0.37, 0.33, st === 2 ? 0.55 : 0.46]);
  part(GEO.sphere, M(CR), B, [0, 0.55 * L, 0.27], [0.26, 0.26, 0.22]);
  legs4(r, B, { x: 0.19, y: 0.38 * L, z: st === 2 ? 0.3 : 0.22, len: 0.2 * L, w: 0.1, col: OR, paw: DK });
  const H = grp(B, [0, 0.98 * L, st === 2 ? 0.38 : 0.3]);
  part(GEO.sphere, M(OR), H, [0, 0, 0], [0.36, 0.33, 0.33]);
  part(GEO.sphere, M(CR), H, [0, -0.11, 0.1], [0.31, 0.19, 0.24]);
  part(GEO.sphere, M(CR), H, [0, -0.09, 0.29], [0.13, 0.09, 0.13]);
  part(GEO.sphere, M(DK), H, [0, -0.05, 0.41], 0.045).userData.noOl = true;
  eyes(r, H, { x: 0.15, y: 0.05, z: 0.27, rad: st === 2 ? 0.068 : 0.078, iris: st === 2 ? 0xffb02e : null, tilt: st === 2 ? 0.18 : 0 });
  blush(H, 0.23, -0.06, 0.24);
  for (const s of [-1, 1]) {
    const e = grp(H, [s * 0.19, 0.24, -0.02], [0, 0, -s * 0.32]);
    part(GEO.cone, M(OR), e, [0, 0.15, 0], [0.13, 0.36 * (st === 2 ? 1.2 : 1), 0.09]);
    part(GEO.cone, M(CR), e, [0, 0.11, 0.05], [0.07, 0.22, 0.03]).userData.noOl = true;
    part(GEO.cone, M(DK), e, [0, 0.32 * (st === 2 ? 1.15 : 1), 0], [0.06, 0.1, 0.05]);
    wig(r, e, 'z', 0.08, 2.3, s);
  }
  wig(r, H, 'y', 0.08, 0.9);
  const tails = st === 2 ? [-0.55, 0, 0.55] : [0];
  for (const a of tails) {
    const tp = grp(B, [0, 0.55 * L, -0.4 * (st === 2 ? 1.2 : 1)], [0.85, a, 0]);
    part(GEO.sphere, M(OR), tp, [0, 0, -0.28], [0.14, 0.14, 0.34]);
    part(GEO.sphere, M(CR), tp, [0, 0, -0.55], [0.1, 0.1, 0.1]);
    const f = flame(r, tp, [0, 0, -0.62], st === 2 ? 1.1 : 1); f.rotation.x = -0.85;
    wig(r, tp, 'y', 0.3, 3, a * 2);
  }
  if (st === 2) {
    for (let i = 0; i < 7; i++) {
      const a = (i / 7) * Math.PI * 2;
      const f = flame(r, B, [Math.cos(a) * 0.26, 0.82 * L + Math.sin(a) * 0.05, 0.2 + Math.sin(a) * 0.12], 0.62);
      f.rotation.set(Math.sin(a) * 0.4, 0, -Math.cos(a) * 0.6);
    }
    part(GEO.octa, E(0xffd25a, 2.6), H, [0, 0.18, 0.3], [0.05, 0.08, 0.03]);
  }
  r.size = 1.35 * S; r.olw = 0.03;
}
MODELS.hwarr = (r) => buildFox(r, 1);
MODELS.yeomho = (r) => buildFox(r, 2);

// ---------- 물롱 / 파도롱 : tide seal
function buildSeal(r, st) {
  const S = st === 2 ? 1.38 : 1;
  const B = grp(r.body); B.scale.setScalar(S);
  const BL = st === 2 ? 0x3aa6ef : 0x5cc8ff, WH = 0xe8f8ff, FN = 0x8fe3ff;
  part(GEO.sphere, M(BL), B, [0, 0.45, 0], [0.48, 0.42, 0.56]);
  part(GEO.sphere, M(WH), B, [0, 0.4, 0.18], [0.36, 0.33, 0.4]);
  const H = grp(B, [0, 0.92, 0.22]);
  part(GEO.sphere, M(BL), H, [0, 0, 0], [0.4, 0.37, 0.37]);
  part(GEO.sphere, M(WH), H, [0, -0.11, 0.24], [0.21, 0.14, 0.16]);
  part(GEO.sphere, M(0x163049), H, [0, -0.06, 0.39], [0.05, 0.035, 0.03]).userData.noOl = true;
  for (const s of [-1, 1]) for (const k of [0, 1]) part(GEO.sphere, M(0x163049), H, [s * (0.07 + k * 0.05), -0.12 - k * 0.02, 0.37], 0.012).userData.noOl = true;
  eyes(r, H, { x: 0.17, y: 0.06, z: 0.3, rad: 0.085 });
  blush(H, 0.26, -0.05, 0.26);
  for (const s of [-1, 1]) {
    const e = grp(H, [s * 0.34, 0.12, -0.02], [0, 0, s * 0.45]);
    part(GEO.sphere, M(FN), e, [s * 0.12, 0, 0], [0.2 * (st === 2 ? 1.3 : 1), 0.055, 0.13]);
    wig(r, e, 'z', 0.18, 2.6, s);
    const f = grp(B, [s * 0.4, 0.22, 0.22], [0, s * -0.4, s * -0.5]);
    part(GEO.sphere, M(BL), f, [s * 0.1, 0, 0], [0.22, 0.06, 0.13]);
    wig(r, f, 'z', 0.25, 3.2, s * 2, true);
  }
  const tl = grp(B, [0, 0.22, -0.52]);
  for (const s of [-1, 1]) part(GEO.sphere, M(FN), tl, [s * 0.13, 0, -0.06], [0.19, 0.05, 0.12], [0, s * 0.5, 0]);
  wig(r, tl, 'y', 0.3, 3);
  const orb = grp(H, [0, 0.5, -0.04]);
  part(GEO.sphere, toonMat({ color: 0xa6f0ff, transparent: true, opacity: 0.55 }), orb, [0, 0, 0], 0.15);
  part(GEO.sphere, E(0x9cf0ff, 2.2), orb, [0, 0, 0], 0.06);
  part(GEO.sphere, E(0xffffff, 1.8), orb, [0.05, 0.06, 0.08], 0.025);
  r.fns.push((t) => { orb.position.y = 0.5 + Math.sin(t * 2.5) * 0.04; });
  if (st === 2) {
    for (let i = 0; i < 3; i++) part(GEO.cone, M(0x2d7fd4), H, [0, 0.3 - i * 0.04, -0.12 - i * 0.12], [0.07, 0.3 - i * 0.05, 0.05], [-0.5 - i * 0.2, 0, 0]);
    const ring = grp(B, [0, 0.5, 0], [Math.PI / 2, 0, 0]);
    part(GEO.torus, E(0x7fe8ff, 2.0), ring, [0, 0, 0], 0.82);
    for (let i = 0; i < 6; i++) { const a = i / 6 * Math.PI * 2; part(GEO.sphere, E(0xbff6ff, 2.4), ring, [Math.cos(a) * 0.82, Math.sin(a) * 0.82, 0], 0.045); }
    spin(r, ring, 'z', 0.8);
    r.fns.push((t) => { ring.rotation.x = Math.PI / 2 + Math.sin(t * 0.8) * 0.12; });
  }
  r.size = 1.45 * S;
}
MODELS.mullong = (r) => buildSeal(r, 1);
MODELS.padolong = (r) => buildSeal(r, 2);

// ---------- 새싹뿔 / 숲뿔사슴 : sprout fawn
function buildFawn(r, st) {
  const S = st === 2 ? 1.3 : 1;
  const B = grp(r.body); B.scale.setScalar(S);
  const FW = st === 2 ? 0xa36a40 : 0xc58a56, CR = 0xfff1d8, LF = 0x6ee06a, DK = 0x3a2416;
  const LL = st === 2 ? 1.2 : 1;
  part(GEO.sphere, M(FW), B, [0, 0.78 * LL, 0], [0.3, 0.29, 0.48]);
  part(GEO.sphere, M(CR), B, [0, 0.71 * LL, 0.04], [0.22, 0.2, 0.38]);
  for (const [x, z] of [[0.1, 0.1], [-0.12, -0.05], [0.06, -0.22], [-0.05, 0.25], [0.14, -0.12]]) part(GEO.sphere, M(CR), B, [x, 0.78 * LL + 0.26, z], 0.045).userData.noOl = true;
  for (const [sx, sz] of [[-1, 1], [1, 1], [-1, -1], [1, -1]]) {
    const p = grp(B, [sx * 0.15, 0.64 * LL, sz * 0.27]);
    part(GEO.cyl, M(FW), p, [0, -0.28 * LL, 0], [0.055, 0.56 * LL, 0.055]);
    part(GEO.sphere, M(DK), p, [0, -0.57 * LL, 0.01], [0.065, 0.05, 0.075]);
    wig(r, p, 'x', 0.5, 1, sx * sz > 0 ? 0 : Math.PI, true);
  }
  part(GEO.cyl, M(FW), B, [0, 1.03 * LL, 0.3], [0.1, 0.42, 0.1], [0.5, 0, 0]);
  const H = grp(B, [0, 1.27 * LL, 0.43]);
  part(GEO.sphere, M(FW), H, [0, 0, 0], [0.25, 0.24, 0.27]);
  part(GEO.sphere, M(CR), H, [0, -0.07, 0.2], [0.13, 0.11, 0.14]);
  part(GEO.sphere, M(DK), H, [0, -0.04, 0.33], 0.035).userData.noOl = true;
  eyes(r, H, { x: 0.13, y: 0.05, z: 0.19, rad: 0.07 });
  blush(H, 0.17, -0.06, 0.17, 0.045);
  for (const s of [-1, 1]) {
    const e = grp(H, [s * 0.22, 0.08, -0.03], [0, 0, s * 0.4]);
    part(GEO.sphere, M(LF), e, [s * 0.13, 0, 0], [0.17, 0.045, 0.08]);
    wig(r, e, 'z', 0.15, 2.2, s);
  }
  const sp = grp(H, [0, 0.22, 0]);
  part(GEO.cyl, M(0x4fbf5f), sp, [0, 0.08, 0], [0.02, 0.18, 0.02]);
  for (const s of [-1, 1]) part(GEO.sphere, M(LF), sp, [s * 0.08, 0.18, 0], [0.1, 0.03, 0.06], [0, 0, s * 0.5]);
  wig(r, sp, 'z', 0.15, 2.8);
  part(GEO.sphere, M(0xffffff), B, [0, 0.86 * LL, -0.48], 0.075);
  if (st === 2) {
    for (const s of [-1, 1]) {
      const a = grp(H, [s * 0.1, 0.2, -0.04], [0, 0, -s * 0.35]);
      const brown = M(0x6b4a2e);
      part(GEO.cyl, brown, a, [0, 0.25, 0], [0.03, 0.5, 0.03]);
      const b1 = grp(a, [0, 0.22, 0], [0, 0, -s * 0.8]); part(GEO.cyl, brown, b1, [0, 0.14, 0], [0.022, 0.28, 0.022]);
      const b2 = grp(a, [0, 0.38, 0], [0.5, 0, s * 0.6]); part(GEO.cyl, brown, b2, [0, 0.12, 0], [0.02, 0.24, 0.02]);
      for (const [g, y] of [[a, 0.52], [b1, 0.3], [b2, 0.26]]) {
        part(GEO.ico1, M(0x4fbf5f), g, [0, y, 0], 0.09);
        part(GEO.sphere, E(pick([0xffb3e6, 0xfff4b0, 0xc8b3ff]), 2.3), g, [0.05, y + 0.05, 0.05], 0.035);
      }
    }
    for (let i = 0; i < 6; i++) { const ang = (i / 6) * Math.PI - Math.PI / 2; part(GEO.sphere, M(LF), B, [Math.sin(ang) * 0.14, 1.05 * LL, 0.28 + Math.cos(ang) * 0.02], [0.08, 0.03, 0.12], [0.4, ang, 0]); }
  }
  r.size = 1.6 * S;
}
MODELS.saessak = (r) => buildFawn(r, 1);
MODELS.supppul = (r) => buildFawn(r, 2);

// ---------- 찌릿파리 : storm jelly
MODELS.jjirit = (r) => {
  r.float = 0.95; r.floatAmp = 0.12;
  const B = grp(r.body);
  const dome = toonMat({ color: 0xffd84a, transparent: true, opacity: 0.86 });
  part(GEO.hemi, dome, B, [0, 0, 0], [0.5, 0.44, 0.5]);
  part(GEO.torus, E(0xfff09a, 1.6), B, [0, 0.01, 0], [0.5, 0.5, 0.5], [Math.PI / 2, 0, 0]);
  const core = part(GEO.sphere, E(0xfff6c8, 3.2), B, [0, 0.16, 0], 0.15);
  r.fns.push((t) => core.scale.setScalar(0.15 * (1 + Math.sin(t * 9) * 0.15 * Math.max(0, Math.sin(t * 1.3)))));
  eyes(r, B, { x: 0.16, y: 0.2, z: 0.38, rad: 0.075 });
  blush(B, 0.27, 0.1, 0.37, 0.05);
  for (let i = 0; i < 9; i++) { const a = (i / 9) * Math.PI * 2; part(GEO.sphere, M(0xffbf2e), B, [Math.cos(a) * 0.46, -0.02, Math.sin(a) * 0.46], 0.085); }
  for (let i = 0; i < 6; i++) {
    const a = (i / 6) * Math.PI * 2 + 0.3;
    let p = grp(B, [Math.cos(a) * 0.25, -0.04, Math.sin(a) * 0.25]);
    for (let k = 0; k < 4; k++) {
      part(GEO.cyl, E(0xfff0a0, 1.25), p, [0, -0.1, 0], [0.024 - k * 0.003, 0.2, 0.024 - k * 0.003]);
      wig(r, p, 'x', 0.22, 2.4, i + k * 0.8); wig(r, p, 'z', 0.18, 1.9, i * 2 + k);
      const n = grp(p, [0, -0.2, 0]); p = n;
    }
    part(GEO.sphere, E(0xfffbd0, 3), p, [0, 0, 0], 0.035);
  }
  for (const s of [-1, 1]) {
    const an = grp(B, [s * 0.12, 0.4, 0], [0, 0, -s * 0.3]);
    part(GEO.cyl, M(0xffbf2e), an, [0, 0.08, 0], [0.018, 0.16, 0.018]);
    part(GEO.octa, E(0xffffff, 3), an, [0, 0.19, 0], 0.04);
    wig(r, an, 'z', 0.2, 4, s);
  }
  r.size = 1.6;
};

// ---------- 바위몽 : rock golem
MODELS.bawimong = (r) => {
  r.hopAmp = 0.5;
  const B = grp(r.body);
  const RK = M(0x8c8378);
  part(GEO.dodeca, RK, B, [0, 0.55, 0], [0.56, 0.48, 0.52]);
  part(GEO.dodeca, M(0xa59c90), B, [0, 0.58, 0.28], [0.36, 0.3, 0.2]);
  eyes(r, B, { x: 0.16, y: 0.62, z: 0.45, rad: 0.075 });
  part(GEO.box, new THREE.MeshBasicMaterial({ color: 0x2a1f1a }), B, [0, 0.47, 0.49], [0.12, 0.025, 0.02]);
  part(GEO.sphere, M(0x5f9a4a), B, [0.05, 0.98, 0.12], [0.26, 0.07, 0.2]);
  const cry = [[0, 1.02, -0.18, 0.13, 0.36, -0.3, 0], [-0.24, 0.9, -0.26, 0.1, 0.27, -0.5, 0.5], [0.26, 0.88, -0.24, 0.1, 0.25, -0.5, -0.5], [0.05, 0.72, -0.5, 0.08, 0.22, -1.2, 0]];
  for (const [x, y, z, w, h, rx, rz] of cry) part(GEO.cone6, E(0x9b7bff, 1.9), B, [x, y, z], [w, h, w], [rx, 0, rz]);
  for (const s of [-1, 1]) {
    const a = grp(B, [s * 0.56, 0.56, 0.04]);
    part(GEO.dodeca, RK, a, [s * 0.06, -0.08, 0], 0.18);
    wig(r, a, 'x', 0.5, 1, s > 0 ? 0 : Math.PI, true); wig(r, a, 'z', 0.06, 1.4, s);
    const f = grp(B, [s * 0.25, 0.16, 0.05]);
    part(GEO.dodeca, M(0x766d63), f, [0, -0.04, 0.04], [0.17, 0.13, 0.2]);
    wig(r, f, 'x', 0.45, 1, s > 0 ? Math.PI : 0, true);
  }
  r.size = 1.3; r.olw = 0.032;
};

// ---------- 반디루 : lantern firefly
MODELS.bandiru = (r) => {
  r.float = 0.9; r.floatAmp = 0.1;
  const B = grp(r.body);
  part(GEO.sphere, M(0xfff0c9), B, [0, 0, 0], [0.31, 0.29, 0.31]);
  part(GEO.sphere, M(0xffe2a0), B, [0, -0.14, 0], [0.31, 0.12, 0.3]);
  eyes(r, B, { x: 0.12, y: 0.05, z: 0.25, rad: 0.085 });
  blush(B, 0.19, -0.04, 0.24, 0.05);
  for (const s of [-1, 1]) {
    const an = grp(B, [s * 0.1, 0.25, 0.08], [0.3, 0, -s * 0.35]);
    part(GEO.cyl, M(0x3a2c22), an, [0, 0.13, 0], [0.014, 0.26, 0.014]);
    part(GEO.sphere, E(0xfff3a0, 3), an, [0, 0.28, 0], 0.045);
    wig(r, an, 'z', 0.15, 3, s);
  }
  const wingM = toonMat({ color: 0xe6f8ff, transparent: true, opacity: 0.5, side: THREE.DoubleSide });
  for (const s of [-1, 1]) for (const k of [0, 1]) {
    const w = grp(B, [s * 0.12, 0.18 - k * 0.08, -0.1 - k * 0.04], [0, 0, s * (0.35 - k * 0.6)]);
    part(GEO.sphere, wingM, w, [s * 0.3, 0, 0], [0.32 - k * 0.08, 0.02, 0.15]);
    wig(r, w, 'z', 0.45, 22, k * 1.5 + (s > 0 ? 0 : Math.PI));
  }
  const ab = part(GEO.sphere, E(0xfff2a0, 3.2), B, [0, -0.1, -0.33], [0.2, 0.19, 0.26]);
  r.fns.push((t) => ab.scale.setScalar(1 + Math.sin(t * 3) * 0.08).multiply(new THREE.Vector3(0.2, 0.19, 0.26)));
  r.size = 1.35;
};

// ---------- 그림냥 : shade cat
MODELS.geurim = (r) => {
  const B = grp(r.body);
  const SH = 0x3a2a5c, SD = 0x281c44;
  part(GEO.sphere, M(SH), B, [0, 0.45, 0], [0.32, 0.29, 0.46]);
  legs4(r, B, { x: 0.17, y: 0.34, z: 0.24, len: 0.19, w: 0.085, col: SH, paw: SD });
  const H = grp(B, [0, 0.86, 0.28]);
  part(GEO.sphere, M(SH), H, [0, 0, 0], [0.34, 0.3, 0.3]);
  part(GEO.sphere, M(0x4b3a72), H, [0, -0.1, 0.18], [0.16, 0.1, 0.12]);
  eyes(r, H, { x: 0.13, y: 0.04, z: 0.26, rad: 0.085, glowc: 0xffd84a, tilt: 0.22 });
  for (const s of [-1, 1]) {
    const e = grp(H, [s * 0.19, 0.22, -0.02], [0, 0, -s * 0.25]);
    part(GEO.cone, M(SH), e, [0, 0.13, 0], [0.13, 0.3, 0.1]);
    part(GEO.cone, E(0x9b6bff, 1.4), e, [0, 0.1, 0.05], [0.06, 0.18, 0.02]).userData.noOl = true;
    wig(r, e, 'z', 0.1, 1.7, s * 3);
  }
  part(GEO.torus, E(0xb48cff, 1.8), B, [0, 0.7, 0.2], [0.21, 0.21, 0.21], [1.25, 0, 0]);
  let p = grp(B, [0, 0.52, -0.42], [0.9, 0, 0]);
  const tailMats = [M(SH), M(SH), M(0x4b3a72), M(0x5b3f8f), E(0x7a4bd6, 1.4), E(0xa77bff, 2)];
  for (let k = 0; k < 6; k++) {
    part(GEO.sphere, tailMats[k], p, [0, 0, -0.08], 0.1 - k * 0.012);
    wig(r, p, 'y', 0.28, 2.2, -k * 0.7);
    p = grp(p, [0, 0, -0.15], [-0.12, 0, 0]);
  }
  r.size = 1.3;
};

// ---------- 솜구름 : cloud lamb
MODELS.somgu = (r) => {
  const B = grp(r.body);
  const W = M(0xf6f3ff);
  const pts = [[0, 0.62, 0, 0.42], [0.25, 0.7, 0.1, 0.25], [-0.25, 0.7, 0.1, 0.25], [0.2, 0.85, -0.15, 0.26], [-0.2, 0.85, -0.15, 0.26], [0, 0.95, 0.05, 0.27], [0.3, 0.5, -0.2, 0.22], [-0.3, 0.5, -0.2, 0.22], [0, 0.6, -0.35, 0.26], [0, 0.82, 0.25, 0.2]];
  for (const [x, y, z, s] of pts) part(GEO.sphere, W, B, [x, y, z], s);
  const H = grp(B, [0, 0.66, 0.4]);
  part(GEO.sphere, M(0xcfc4f2), H, [0, 0, 0], [0.24, 0.22, 0.2]);
  eyes(r, H, { x: 0.09, y: 0.03, z: 0.16, rad: 0.058 });
  blush(H, 0.15, -0.05, 0.14, 0.04);
  const horn = new THREE.TorusGeometry(0.1, 0.035, 8, 18, Math.PI * 1.35);
  for (const s of [-1, 1]) {
    part(horn, M(0xe6c27a), H, [s * 0.2, 0.12, -0.04], 1, [0, s * 1.3, s > 0 ? 0.5 : 2.6]);
    const ear = grp(H, [s * 0.22, 0.0, -0.02], [0, 0, s * 0.9]);
    part(GEO.sphere, M(0xcfc4f2), ear, [s * 0.08, 0, 0], [0.1, 0.04, 0.06]);
    wig(r, ear, 'z', 0.2, 2.5, s);
  }
  for (const [sx, sz] of [[-1, 1], [1, 1], [-1, -1], [1, -1]]) {
    const p = grp(B, [sx * 0.18, 0.3, sz * 0.18]);
    part(GEO.cyl, M(0x4a4368), p, [0, -0.13, 0], [0.06, 0.26, 0.06]);
    wig(r, p, 'x', 0.5, 1, sx * sz > 0 ? 0 : Math.PI, true);
  }
  r.size = 1.35;
};

// ---------- 버섯콩 : mushroom sprite
MODELS.beoseot = (r) => {
  const B = grp(r.body);
  part(GEO.sphere, M(0xf8ead2), B, [0, 0.38, 0], [0.3, 0.36, 0.28]);
  eyes(r, B, { x: 0.11, y: 0.42, z: 0.24, rad: 0.07 });
  blush(B, 0.18, 0.33, 0.22, 0.05);
  part(GEO.box, new THREE.MeshBasicMaterial({ color: 0x5a2a2a }), B, [0, 0.32, 0.275], [0.05, 0.016, 0.01]);
  const cap = grp(B, [0, 0.64, 0]);
  part(GEO.hemi, M(0xe8475a), cap, [0, 0, 0], [0.58, 0.44, 0.58]);
  part(GEO.circle, M(0xf2d6b0, { side: THREE.DoubleSide }), cap, [0, 0.005, 0], 0.56, [Math.PI / 2, 0, 0]).userData.noOl = true;
  const spots = [[0, 0.95], [0.9, 0.55], [2.1, 0.6], [3.3, 0.5], [4.4, 0.62], [5.4, 0.55], [1.5, 1.05], [3.9, 1.0]];
  for (const [a, ph] of spots) part(GEO.sphere, M(0xfff6ea), cap, [Math.cos(a) * Math.sin(ph) * 0.56, Math.cos(ph) * 0.42 + 0.02, Math.sin(a) * Math.sin(ph) * 0.56], [0.08, 0.05, 0.08]).userData.noOl = true;
  wig(r, cap, 'z', 0.05, 2);
  for (const s of [-1, 1]) {
    const f = grp(B, [s * 0.13, 0.1, 0.03]);
    part(GEO.sphere, M(0xd9b98f), f, [0, -0.04, 0.03], [0.1, 0.07, 0.13]);
    wig(r, f, 'x', 0.5, 1, s > 0 ? 0 : Math.PI, true);
    const a = grp(B, [s * 0.29, 0.38, 0], [0, 0, s * 0.5]);
    part(GEO.sphere, M(0xf8ead2), a, [s * 0.04, -0.04, 0], [0.06, 0.1, 0.06]);
    wig(r, a, 'z', 0.25, 2.4, s);
  }
  r.size = 1.2;
};

// ---------- 틈벌레 : void mite
MODELS.teum = (r) => {
  r.float = 1.0; r.floatAmp = 0.09;
  const B = grp(r.body);
  part(GEO.sphere, voidMat(0xb055ff, 2.4), B, [0, 0, 0], 0.38);
  const eg = grp(B, [0, 0.04, 0.33]);
  part(GEO.torus, E(0xff4fd8, 2.8), eg, [0, 0, 0], [0.17, 0.17, 0.4]);
  part(GEO.circle, new THREE.MeshBasicMaterial({ color: 0x000000 }), eg, [0, 0, 0.012], 0.15);
  part(GEO.sphere, E(0xffffff, 3), eg, [0.04, 0.05, 0.03], 0.022);
  r.blink.push(eg);
  for (const [rx, ry, rz] of [[0.3, 0.6, 0.2], [-0.5, -0.9, 1.1], [1.2, 2.2, -0.4]]) {
    const c = grp(B, [0, 0, 0], [rx, ry, rz]);
    part(GEO.box, E(0xc77dff, 2.4), c, [0, 0, 0.375], [0.012, 0.22, 0.012]);
  }
  const orb = grp(B);
  for (let i = 0; i < 5; i++) { const a = i / 5 * Math.PI * 2; part(GEO.tetra, voidMat(0xb055ff, 2), orb, [Math.cos(a) * 0.62, Math.sin(a * 2) * 0.12, Math.sin(a) * 0.62], 0.08, [a, a * 2, 0]); }
  spin(r, orb, 'y', 1.2);
  for (let i = 0; i < 4; i++) {
    const a = (i / 4) * Math.PI * 2 + 0.78;
    const l = grp(B, [Math.cos(a) * 0.2, -0.28, Math.sin(a) * 0.2], [Math.sin(a) * 0.4, 0, -Math.cos(a) * 0.4]);
    part(GEO.cone, voidMat(0xb055ff, 2), l, [0, -0.1, 0], [0.04, 0.22, 0.04], [Math.PI, 0, 0]);
    wig(r, l, 'x', 0.25, 4, i);
  }
  r.size = 1.45;
};

// ---------- 별씨 : starseed
MODELS.byeolssi = (r) => {
  r.float = 1.0; r.floatAmp = 0.12;
  const B = grp(r.body);
  const star = grp(B);
  for (let i = 0; i < 5; i++) {
    const a = (i / 5) * Math.PI * 2 + Math.PI / 2;
    part(GEO.cone, M(0xffe08a), star, [Math.cos(a) * 0.36, Math.sin(a) * 0.36, -0.04], [0.13, 0.3, 0.1], [0, 0, a - Math.PI / 2]);
  }
  spin(r, star, 'z', 0.5);
  part(GEO.sphere, M(0xfff3d0), B, [0, 0, 0], [0.32, 0.31, 0.3]);
  eyes(r, B, { x: 0.11, y: 0.04, z: 0.25, rad: 0.068, iris: 0xffb84a });
  blush(B, 0.19, -0.05, 0.24, 0.045);
  const halo = part(GEO.torus, E(0xffe08a, 2.4), B, [0, 0.5, 0], 0.2, [Math.PI / 2, 0, 0]);
  r.fns.push((t) => { halo.position.y = 0.5 + Math.sin(t * 3) * 0.03; });
  part(GEO.sphere, E(0xfff0b0, 1.2, { transparent: true, opacity: 0.35, depthWrite: false }), B, [0, 0, -0.05], 0.55).userData.noOl = true;
  r.size = 1.6;
};

// ---------- motes used by both legends
function motes(r, parent, n, color, radius, ysp, toCenter = false) {
  const g = new THREE.BufferGeometry();
  const pos = new Float32Array(n * 3), ph = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    const a = Math.random() * Math.PI * 2, rr = radius * (0.5 + Math.random() * 0.6);
    pos[i * 3] = Math.cos(a) * rr; pos[i * 3 + 1] = (Math.random() - 0.5) * ysp; pos[i * 3 + 2] = Math.sin(a) * rr; ph[i] = Math.random();
  }
  g.setAttribute('position', new THREE.BufferAttribute(pos, 3)); g.setAttribute('ph', new THREE.BufferAttribute(ph, 1));
  const m = new THREE.ShaderMaterial({
    uniforms: { uTime: Shared.time, uColor: { value: new THREE.Color(color).multiplyScalar(2.6) }, uTex: { value: TEX.dot }, uIn: { value: toCenter ? 1 : 0 } },
    vertexShader: `attribute float ph; uniform float uTime; uniform float uIn; varying float vA;
      void main(){ vec3 p = position; float k = fract(uTime*0.35 + ph);
        if(uIn > 0.5){ p = mix(p, vec3(0.0), k); vA = sin(k*3.14159); }
        else { float a = uTime*(0.3+ph*0.4); float c=cos(a), s=sin(a); p.xz = mat2(c,-s,s,c)*p.xz; p.y += sin(uTime*1.3+ph*20.0)*0.15; vA = 0.55+0.45*sin(uTime*3.0+ph*30.0); }
        vec4 mv = modelViewMatrix*vec4(p,1.0); gl_PointSize = (0.9+ph)*70.0/-mv.z; gl_Position = projectionMatrix*mv; }`,
    fragmentShader: `uniform vec3 uColor; uniform sampler2D uTex; varying float vA;
      void main(){ float a = texture2D(uTex, gl_PointCoord).a * vA; gl_FragColor = vec4(uColor*a, 1.0); }`,
    blending: THREE.AdditiveBlending, transparent: true, depthWrite: false,
  });
  const p = new THREE.Points(g, m); p.frustumCulled = false; parent.add(p); return p;
}

// ---------- shared helpers for the legends
function beamBetween(parent, a, b, mat, rad = 0.012) {
  const A = new THREE.Vector3(...a), Bv = new THREE.Vector3(...b), d = Bv.clone().sub(A), L = d.length();
  const m = new THREE.Mesh(GEO.cyl, mat); m.position.copy(A).addScaledVector(d, 0.5);
  m.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), d.normalize()); m.scale.set(rad, L, rad);
  parent.add(m); return m;
}
// a body you can look *into*: screen-space starfield + drifting nebula + rim light
function cosmicMat(rim = 0x8fe0ff, deep = 0x060a24, neb = 0x4a3a9a, neb2 = 0x1a6aa8) {
  const k = 'c' + rim + '_' + deep + '_' + neb;
  if (_mc.has(k)) { _mc.get(k).uniforms.uPx.value = renderer.getPixelRatio(); return _mc.get(k); }
  const m = new THREE.ShaderMaterial({
    uniforms: THREE.UniformsUtils.merge([THREE.UniformsLib.fog, { uRim: { value: new THREE.Color(rim).multiplyScalar(2.3) }, uDeep: { value: new THREE.Color(deep) }, uNeb: { value: new THREE.Color(neb) }, uNeb2: { value: new THREE.Color(neb2) }, uPx: { value: renderer.getPixelRatio() }, uTime: { value: 0 } }]),
    vertexShader: `varying vec3 vN; varying vec3 vV; ${FOG_V}
      void main(){ vec4 mvPosition = modelViewMatrix * vec4(position, 1.0); vN = normalize(normalMatrix * normal); vV = normalize(-mvPosition.xyz);
        gl_Position = projectionMatrix * mvPosition;
        #include <fog_vertex>
      }`,
    fragmentShader: `uniform vec3 uRim, uDeep, uNeb, uNeb2; uniform float uTime, uPx; varying vec3 vN; varying vec3 vV;
      ${GLSL_NOISE}
      ${FOG_F}
      void main(){
        vec2 fc = gl_FragCoord.xy / uPx;
        float h = hash12(floor(fc / 3.0));
        float star = step(0.978, h) * smoothstep(0.55, 0.0, length(fract(fc / 3.0) - 0.5)) * (0.5 + 0.5 * sin(uTime * 2.4 + h * 90.0));
        float hb = hash12(floor(fc / 11.0) + 7.0);
        float big = step(0.993, hb) * smoothstep(0.5, 0.0, length(fract(fc / 11.0) - 0.5));
        vec2 q = fc * 0.0035 + vec2(uTime * 0.012, uTime * 0.004);
        float n = vnoise(q * 3.0) * 0.6 + vnoise(q * 7.0 + 3.0) * 0.4;
        vec3 col = mix(uDeep, uNeb, smoothstep(0.42, 0.85, n));
        col = mix(col, uNeb2, smoothstep(0.55, 0.95, vnoise(q * 4.0 + 9.0)) * 0.65);
        col += vec3(1.7) * star + vec3(1.3, 1.6, 2.4) * big * 1.8;
        float fr = pow(1.0 - max(dot(normalize(vN), normalize(vV)), 0.0), 2.3);
        col += uRim * fr;
        gl_FragColor = vec4(col, 1.0);
        #include <fog_fragment>
      }`,
    fog: true,
  });
  m.uniforms.uTime = Shared.time;
  _mc.set(k, m); return m;
}

// ---------- people
function buildPersonToon(o = {}) {
  const r = newRig(); r.hopAmp = 0.45; r.olw = 0.024; r.person = true;
  const C = Object.assign({ skin: 0xffdcc6, hair: 0x2a2238, top: 0xeef1f8, bottom: 0x2b2f4a, accent: 0x8b5cff, shoe: 0x22202e, pack: true }, o);
  const B = r.body;
  const legs = [];
  for (const s of [-1, 1]) {
    const p = grp(B, [s * 0.12, 0.56, 0]);
    part(GEO.capsule, M(C.bottom), p, [0, -0.25, 0], [0.17, 0.25, 0.17]);
    part(GEO.sphere, M(C.shoe), p, [0, -0.52, 0.04], [0.1, 0.07, 0.14]);
    legs.push(p);
  }
  if (C.robe) part(GEO.cone, M(C.top), B, [0, 0.55, 0], [0.42, 1.0, 0.4]);
  part(GEO.capsule, M(C.top), B, [0, 0.92, 0], [0.42, 0.25, 0.32]);
  part(GEO.torusFat, M(C.accent), B, [0, 1.17, 0], [0.19, 0.19, 0.19], [Math.PI / 2, 0, 0]);
  const scarf = grp(B, [0.1, 1.12, -0.12], [0.3, 0, 0.15]);
  part(GEO.box, M(C.accent), scarf, [0, -0.15, 0], [0.09, 0.3, 0.03]);
  wig(r, scarf, 'x', 0.15, 3.1);
  const arms = [];
  for (const s of [-1, 1]) {
    const p = grp(B, [s * 0.26, 1.1, 0], [0, 0, s * 0.12]);
    part(GEO.capsule, M(C.top), p, [0, -0.2, 0], [0.13, 0.19, 0.13]);
    part(GEO.sphere, M(C.skin), p, [0, -0.42, 0.01], 0.07);
    arms.push(p);
  }
  if (C.staff) {
    const st = grp(arms[1], [0, -0.42, 0.06]);
    part(GEO.cyl, M(0x5a3b26), st, [0, 0.25, 0], [0.025, 1.5, 0.025]);
    part(GEO.octa, E(C.staff, 2.6), st, [0, 1.05, 0], [0.09, 0.15, 0.09]);
  }
  if (C.pack) {
    part(GEO.box, M(0x8a5a3c), B, [0, 0.95, -0.24], [0.34, 0.38, 0.16]);
    part(GEO.box, M(0xa8754e), B, [0, 1.07, -0.3], [0.3, 0.12, 0.06]);
  }
  const H = grp(B, [0, 1.52, 0]);
  part(GEO.sphere, M(C.skin), H, [0, 0, 0], 0.35);
  part(GEO.sphere, M(C.hair), H, [0, 0.07, -0.05], [0.38, 0.36, 0.37]);
  part(GEO.sphere, M(C.hair), H, [0, 0.2, 0.17], [0.33, 0.13, 0.2], [0.35, 0, 0]);
  if (C.long) part(GEO.sphere, M(C.hair), H, [0, -0.22, -0.16], [0.33, 0.36, 0.2]);
  if (C.beard) part(GEO.sphere, M(C.beard), H, [0, -0.24, 0.18], [0.22, 0.2, 0.14]);
  const eg = grp(H, [0, 0.0, 0.31]);
  for (const s of [-1, 1]) part(GEO.sphere, new THREE.MeshBasicMaterial({ color: 0x231a33 }), eg, [s * 0.12, 0, 0], [0.038, 0.062, 0.02]);
  r.blink.push(eg);
  blush(H, 0.2, -0.09, 0.27, 0.045);
  if (C.pin) part(GEO.octa, E(C.pin, 2.4), H, [0.26, 0.2, 0.12], [0.05, 0.08, 0.03]);
  if (C.hat === 'hood') part(GEO.sphere, M(C.accent), H, [0, 0.07, -0.1], [0.41, 0.41, 0.36]);
  if (C.hat === 'wide') { part(GEO.cyl, M(C.accent), H, [0, 0.28, 0], [0.55, 0.04, 0.55]); part(GEO.cylT, M(C.accent), H, [0, 0.42, 0], [0.24, 0.26, 0.24]); }
  if (C.hat === 'band') part(GEO.torusFat, M(C.accent), H, [0, 0.16, 0], [0.33, 0.33, 0.25], [Math.PI / 2 - 0.15, 0, 0]);
  r.fns.push((t, dt, mv) => {
    const sw = Math.sin(r.walkPhase) * 0.7 * mv;
    legs[0].rotation.x = sw; legs[1].rotation.x = -sw;
    arms[0].rotation.x = -sw * 0.8; arms[1].rotation.x = sw * 0.8;
    H.rotation.z = Math.sin(t * 1.3) * 0.03;
  });
  addOutlines(B, r.olw);
  B.traverse((m) => { if (m.isMesh && !m.userData.isOl && m.material && !m.material.isMeshBasicMaterial && !m.material.transparent) m.castShadow = true; });
  r.size = 1.9;
  return r;
}

// soft contact shadow (ambient-occlusion blob) under every spirit: grounds it on terrain, daises and phones without GTAO
let _contactTex = null, _contactGeo = null, _contactMat = null;
function contactShadow(r) {
  if (!_contactTex) {
    const c = document.createElement('canvas'); c.width = c.height = 128; const g = c.getContext('2d');
    const gr = g.createRadialGradient(64, 64, 0, 64, 64, 64);
    gr.addColorStop(0, 'rgba(0,0,0,0.62)'); gr.addColorStop(0.35, 'rgba(0,0,0,0.42)'); gr.addColorStop(0.7, 'rgba(0,0,0,0.12)'); gr.addColorStop(1, 'rgba(0,0,0,0)');
    g.fillStyle = gr; g.fillRect(0, 0, 128, 128);
    _contactTex = new THREE.CanvasTexture(c);
    _contactGeo = new THREE.PlaneGeometry(1, 1).rotateX(-Math.PI / 2);
    _contactMat = new THREE.MeshBasicMaterial({ map: _contactTex, transparent: true, depthWrite: false, toneMapped: false, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -4 });
  }
  const box = new THREE.Box3();
  r.body.updateMatrixWorld(true);
  r.body.traverse((o) => { if (o.isMesh && !o.userData.isOl && o.geometry) { o.geometry.computeBoundingBox(); box.union(o.geometry.boundingBox.clone().applyMatrix4(o.matrixWorld)); } });
  if (box.isEmpty()) return null;
  const w = clamp((box.max.x - box.min.x) * 0.72, 0.4, r.size * 3), d = clamp((box.max.z - box.min.z) * 0.72, 0.4, r.size * 3);
  const m = new THREE.Mesh(_contactGeo, _contactMat.clone());
  m.scale.set(w, 1, d); m.position.set((box.min.x + box.max.x) / 2, 0.025, (box.min.z + box.max.z) / 2);
  m.material.opacity = r.float ? clamp(1 - r.float * 0.35, 0.35, 0.8) : 1;
  m.userData.isOl = true; m.userData.noAO = true; m.castShadow = false; m.receiveShadow = false; m.renderOrder = 1; m.raycast = () => {};
  r.root.add(m); r.contact = m;
  return m;
}
function makeSpiritModel(sp) {
  const r = newRig();
  (MODELS[sp] || MODELS.somgu)(r);
  if (r.olw > 0) addOutlines(r.body, r.olw);
  r.body.traverse((m) => { if (m.isMesh && !m.userData.isOl && m.material && !m.material.isMeshBasicMaterial && !m.material.transparent && !m.material.isShaderMaterial) m.castShadow = true; });
  r.sp = sp;
  try { contactShadow(r); } catch (e) { console.warn(e); }
  return r;
}

// white hit-flash by swapping materials for a moment
const FLASH_MAT = new THREE.MeshBasicMaterial({ color: new THREE.Color(2.2, 2.2, 2.2) });
function flashRig(r, on, mat = FLASH_MAT) {
  r.root.traverse((o) => {
    if (!o.isMesh || o.userData.isOl) return;
    if (o.material && o.material.userData && o.material.userData.uFlash) { o.material.userData.uFlash.value = on ? 1 : 0; return; }
    if (on) { if (!o.userData.m0) o.userData.m0 = o.material; o.material = mat; }
    else if (o.userData.m0) { o.material = o.userData.m0; o.userData.m0 = null; }
  });
}
function disposeRig(r) { if (r && r.root.parent) r.root.parent.remove(r.root); }

// ---------- portrait icons (offscreen renderer, cached data URLs)
const Icons = {
  cache: {}, rnd: null, scene: null, cam: null,
  ensure() {
    if (this.rnd) return;
    this.rnd = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: true });
    this.rnd.setSize(160, 160, false); this.rnd.setPixelRatio(1);
    this.rnd.outputColorSpace = THREE.SRGBColorSpace; this.rnd.toneMapping = THREE.ACESFilmicToneMapping;
    this.scene = new THREE.Scene();
    this.scene.add(new THREE.HemisphereLight(0xdcd6ff, 0x4a3a5a, 1.6));
    const d = new THREE.DirectionalLight(0xffffff, 2.2); d.position.set(2, 3, 4); this.scene.add(d);
    const rim = new THREE.DirectionalLight(0xbcd4ff, 1.4); rim.position.set(-3, 2, -2); this.scene.add(rim);
    this.cam = new THREE.PerspectiveCamera(30, 1, 0.1, 50);
  },
  shot(root, fov, pos, look) {
    this.scene.add(root);
    this.cam.fov = fov; this.cam.updateProjectionMatrix();
    this.cam.position.set(pos[0], pos[1], pos[2]); this.cam.lookAt(look[0], look[1], look[2]);
    this.rnd.render(this.scene, this.cam);
    const url = this.rnd.domElement.toDataURL('image/png');
    this.scene.remove(root);
    return url;
  },
  get(sp) {
    if (sp in this.cache) return this.cache[sp];
    try {
      this.ensure();
      const r = makeSpiritModel(sp);
      if (r.contact) r.contact.visible = false;
      rigUpdate(r, 0.01);
      const s = r.size;
      r.root.rotation.y = 0.45;
      const cy = (r.float || 0) + s * 0.42;
      this.cache[sp] = this.shot(r.root, 30, [0, cy + s * 0.08, s * 2.35], [0, cy, 0]);
    } catch (e) { console.warn(e); this.cache[sp] = ''; }
    return this.cache[sp];
  },
  // head-and-shoulders portrait of a person (dialogue box)
  portrait(key, look) {
    const ck = 'person:' + key;
    if (ck in this.cache) return this.cache[ck];
    try {
      this.ensure();
      const r = buildPerson(look);
      rigUpdate(r, 0.01);
      r.root.rotation.y = 0.32;
      const top = look.hat === 'wide' ? 1.66 : 1.56;
      this.cache[ck] = this.shot(r.root, 26, [0.3, top + 0.05, 2.35], [0.02, top, 0]);
    } catch (e) { console.warn(e); this.cache[ck] = ''; }
    return this.cache[ck];
  },
};
