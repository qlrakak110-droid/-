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
function flame(r, parent, pos, s = 1) {
  const g = grp(parent, pos);
  const o = part(GEO.cone, E(0xff5a1a, 2.4), g, [0, 0.16 * s, 0], [0.16 * s, 0.44 * s, 0.16 * s]);
  const i = part(GEO.cone, E(0xffc94a, 3.2), g, [0, 0.11 * s, 0.02 * s], [0.09 * s, 0.3 * s, 0.09 * s]);
  part(GEO.sphere, E(0xfff3c0, 3.6), g, [0, 0.02 * s, 0], 0.075 * s);
  const ph = Math.random() * 9;
  r.fns.push((t) => {
    const k = 1 + Math.sin(t * 17 + ph) * 0.08 + Math.sin(t * 29 + ph) * 0.06;
    o.scale.y = 0.44 * s * k; i.scale.y = 0.3 * s * (2 - k); o.rotation.z = Math.sin(t * 7 + ph) * 0.12;
  });
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

// ---------- 엔시아 : Being
MODELS.ensia = (r) => {
  r.float = 1.55; r.floatAmp = 0.12; r.noBreath = true; r.olw = 0.028;
  const B = grp(r.body);
  const PEARL = M(0xf7f3ff), GOLD = M(0xe8c063);
  const prof = [[0.0, -1.45], [0.1, -1.25], [0.24, -0.85], [0.38, -0.35], [0.47, 0.1], [0.45, 0.48], [0.36, 0.78], [0.21, 0.98], [0.0, 1.06]].map(([x, y]) => new THREE.Vector2(x, y));
  const lathe = new THREE.LatheGeometry(prof, 40);
  part(lathe, PEARL, B, [0, 0, 0]);
  part(GEO.torus, GOLD, B, [0, 0.1, 0], [0.47, 0.47, 1.4], [Math.PI / 2, 0, 0]);
  part(GEO.torus, GOLD, B, [0, -0.6, 0], [0.33, 0.33, 1.4], [Math.PI / 2, 0, 0]);
  part(GEO.torus, GOLD, B, [0, 0.82, 0], [0.33, 0.33, 1.2], [Math.PI / 2, 0, 0]);
  const core = grp(B, [0, 0.44, 0.41]);
  const cs = part(GEO.sphere, E(0xffefb8, 4.2), core, [0, 0, 0], 0.16);
  part(GEO.torus, E(0xffd27a, 2.6), core, [0, 0, 0], 0.26);
  for (let i = 0; i < 4; i++) part(GEO.octa, E(0xffe9a8, 3), core, [Math.cos(i * Math.PI / 2) * 0.34, Math.sin(i * Math.PI / 2) * 0.34, 0], [0.03, 0.06, 0.02], [0, 0, i * Math.PI / 2]);
  spin(r, core, 'z', 0.6);
  r.fns.push((t) => cs.scale.setScalar(0.16 * (1 + Math.sin(t * 2.2) * 0.12)));
  // arms
  for (const s of [-1, 1]) {
    const a = grp(B, [s * 0.4, 0.78, 0.05], [0.2, 0, s * 0.42]);
    part(GEO.capsule, PEARL, a, [0, -0.32, 0], [0.12, 0.38, 0.12]);
    part(GEO.torus, GOLD, a, [0, -0.5, 0], [0.075, 0.075, 0.6], [Math.PI / 2, 0, 0]);
    part(GEO.sphere, PEARL, a, [0, -0.7, 0.02], [0.07, 0.09, 0.06]);
    wig(r, a, 'x', 0.1, 0.8, s);
  }
  // head
  const H = grp(B, [0, 1.36, 0.04]);
  part(GEO.sphere, PEARL, H, [0, 0, 0], [0.25, 0.3, 0.27]);
  part(GEO.sphere, GOLD, H, [0, 0.02, 0.17], [0.2, 0.24, 0.12]);
  const eg = grp(H, [0, 0.03, 0.28]);
  for (const s of [-1, 1]) part(GEO.sphere, E(0xfff8e0, 3.8), eg, [s * 0.08, 0, 0], [0.062, 0.02, 0.02], [0, 0, s * 0.18]);
  part(GEO.octa, E(0xfff3c4, 3.4), H, [0, 0.17, 0.27], [0.03, 0.06, 0.02]);
  r.blink.push(eg);
  // crown of rays
  for (let i = 0; i < 9; i++) {
    const a = lerp(-1.25, 1.25, i / 8), L = i % 2 ? 0.42 : 0.62;
    const ray = grp(H, [Math.sin(a) * 0.24, Math.cos(a) * 0.26, -0.1], [0, 0, -a]);
    part(GEO.cone, GOLD, ray, [0, L / 2, 0], [0.045, L, 0.03]);
    part(GEO.sphere, E(0xffe4a0, 3), ray, [0, L + 0.03, 0], 0.035);
  }
  const halo = grp(H, [0, 0.05, -0.32]);
  part(GEO.torus, E(0xffe2a0, 2.6), halo, [0, 0, 0], 0.95);
  const h2 = grp(halo); part(GEO.torus, E(0xfff0c8, 1.8), h2, [0, 0, 0], [1.18, 1.18, 0.5]);
  for (let i = 0; i < 12; i++) { const a = (i / 12) * Math.PI * 2; part(GEO.octa, E(0xffd98a, 2.6), h2, [Math.cos(a) * 1.18, Math.sin(a) * 1.18, 0], [0.035, 0.08, 0.03], [0, 0, a]); }
  spin(r, h2, 'z', 0.25);
  r.fns.push((t) => { halo.rotation.y = Math.sin(t * 0.5) * 0.15; });
  // wings (two pairs of feather fans)
  const featherM = M(0xfffcf4);
  for (const s of [-1, 1]) {
    for (const pair of [0, 1]) {
      const w = grp(B, [s * 0.28, pair ? 0.15 : 0.72, -0.22]);
      const n = pair ? 5 : 7;
      for (let i = 0; i < n; i++) {
        const k = i / (n - 1);
        const a = pair ? lerp(-0.25, -1.1, k) : lerp(0.05, 1.35, k);
        const L = (pair ? lerp(1.0, 0.6, k) : lerp(1.75, 0.95, k));
        const f = grp(w, [0, 0, -i * 0.012], [0, 0, s > 0 ? a : Math.PI - a]);
        part(GEO.sphere, featherM, f, [L / 2, 0, 0], [L / 2, 0.085, 0.03]);
        part(GEO.sphere, GOLD, f, [L * 0.62, 0.05, 0], [L * 0.32, 0.025, 0.035]);
        part(GEO.sphere, E(0xffe7a8, 2.8), f, [L * 0.98, 0, 0], [0.06, 0.04, 0.03]);
      }
      w.rotation.y = s * (pair ? 0.35 : 0.45);
      const base = w.rotation.y;
      r.fns.push((t) => { w.rotation.y = base + s * Math.sin(t * 1.4 + pair) * 0.18; w.rotation.z = s * Math.sin(t * 1.4 + pair + 0.6) * 0.06; });
    }
  }
  // tail streamers
  for (const s of [-1, 1]) {
    let p = grp(B, [s * 0.05, -1.4, -0.02], [0.3, 0, s * 0.25]);
    for (let k = 0; k < 6; k++) {
      part(GEO.sphere, E(0xffe7a8, 1 + k * 0.35), p, [0, -0.08, 0], [0.07 - k * 0.008, 0.12, 0.04]);
      wig(r, p, 'z', 0.18, 1.6, s + k * 0.5); wig(r, p, 'x', 0.1, 1.2, k * 0.4);
      p = grp(p, [0, -0.17, 0]);
    }
  }
  motes(r, B, 70, 0xffd98a, 1.8, 3.2);
  r.size = 3.7;
};

// ---------- 니힐로스 : Void
MODELS.nihilos = (r) => {
  r.float = 1.7; r.floatAmp = 0.15; r.noBreath = true; r.olw = 0;
  const B = grp(r.body);
  const VM = voidMat(0xb055ff, 2.4), VM2 = voidMat(0xff4fd8, 3.0, 0x05030a, 2.0);
  // serpent body
  const segs = [];
  for (let i = 0; i < 18; i++) {
    const u = i / 17;
    const rad = lerp(0.42, 0.07, Math.pow(u, 0.8));
    const m = part(GEO.sphere, VM, B, [0, 0, 0], rad);
    segs.push({ m, u, rad });
    if (i < 12 && i % 2 === 0) part(GEO.cone, VM2, m, [0, 0.95, -0.2], [0.25, 0.9, 0.25], [-0.4, 0, 0]);
  }
  const place = (t) => {
    for (const s of segs) {
      const u = s.u, a = u * 4.2;
      s.m.position.set(Math.sin(a + t * 0.9) * 0.75 * (0.4 + u), 0.9 - u * 2.6 + Math.sin(t * 1.3 + u * 6) * 0.05, -0.2 - u * 0.9 + Math.cos(a + t * 0.9) * 0.55 * u);
    }
  };
  place(0); r.fns.push((t) => place(t));
  // head
  const H = grp(B, [0, 1.35, 0.35]);
  part(GEO.sphere, VM, H, [0, 0, 0], [0.56, 0.5, 0.58]);
  part(GEO.sphere, VM, H, [0, -0.28, 0.2], [0.36, 0.2, 0.34]);
  for (const [x, y, z, rx, rz, L] of [[0.28, 0.32, -0.15, -0.9, -0.35, 1.0], [-0.28, 0.32, -0.15, -0.9, 0.35, 1.0], [0.44, 0.04, -0.12, -0.6, -1.15, 0.75], [-0.44, 0.04, -0.12, -0.6, 1.15, 0.75], [0, 0.42, -0.3, -1.3, 0, 0.6]]) {
    const h = grp(H, [x, y, z], [rx, 0, rz]);
    part(GEO.cone, VM2, h, [0, L / 2, 0], [0.09, L, 0.09]);
  }
  // the hollow face: event horizon + accretion rings + singular eye
  const face = grp(H, [0, 0.02, 0.56]);
  part(GEO.circle, new THREE.MeshBasicMaterial({ color: 0x000000 }), face, [0, 0, 0.01], 0.32);
  const ring1 = grp(face); part(GEO.torus, E(0xd06bff, 3.2), ring1, [0, 0, 0], [0.34, 0.34, 1.2]);
  const ring2 = grp(face); part(GEO.torus, E(0xff6ad5, 2.2), ring2, [0, 0, 0], [0.44, 0.44, 0.5]);
  const ring3 = grp(face); part(GEO.torus, E(0x8a5cff, 1.6), ring3, [0, 0, 0], [0.55, 0.55, 0.35]);
  const eye = part(GEO.sphere, E(0xffffff, 6), face, [0, 0, 0.03], 0.035);
  r.blink.push(eye);
  r.fns.push((t) => {
    ring1.rotation.set(Math.sin(t * 0.7) * 0.25, Math.cos(t * 0.5) * 0.25, t * 0.8);
    ring2.rotation.set(Math.cos(t * 0.6) * 0.5, Math.sin(t * 0.4) * 0.5, -t * 0.5);
    ring3.rotation.set(1.1 + Math.sin(t * 0.3) * 0.2, 0, t * 0.3);
    eye.scale.setScalar(0.035 * (1 + Math.max(0, Math.sin(t * 1.7)) * 0.8));
  });
  wig(r, H, 'x', 0.06, 0.9); wig(r, H, 'z', 0.05, 0.7, 1);
  // claws
  for (const s of [-1, 1]) {
    const a = grp(B, [s * 0.5, 0.75, 0.25], [0.4, 0, s * 0.8]);
    part(GEO.sphere, VM, a, [0, -0.3, 0], [0.1, 0.35, 0.1]);
    for (let k = -1; k <= 1; k++) part(GEO.cone, VM2, a, [k * 0.05, -0.72, 0.03], [0.035, 0.25, 0.035], [0, 0, Math.PI + k * 0.25]);
    wig(r, a, 'z', 0.15, 1.1, s);
  }
  // orbiting shards + orbit ring
  const orb = grp(B, [0, 0.3, 0]);
  for (let i = 0; i < 9; i++) {
    const a = (i / 9) * Math.PI * 2, R = 1.7 + (i % 3) * 0.25;
    const sh = part(GEO.octa, i % 3 ? VM : VM2, orb, [Math.cos(a) * R, Math.sin(a * 3) * 0.6, Math.sin(a) * R], [0.1 + (i % 3) * 0.05, 0.22 + (i % 2) * 0.1, 0.1]);
    spin(r, sh, 'y', 1 + i * 0.2); spin(r, sh, 'x', 0.7);
  }
  spin(r, orb, 'y', -0.35);
  const oring = grp(B, [0, 0.35, 0], [1.2, 0, 0.2]);
  part(GEO.torus, E(0x8a3dff, 1.5), oring, [0, 0, 0], [2.2, 2.2, 0.5]);
  spin(r, oring, 'z', 0.2);
  const pm = motes(r, H, 140, 0xb04bff, 1.8, 1.6, true);
  pm.position.set(0, 0, 0.6);
  r.size = 3.9;
};

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

// ---------- 아스테리온 : the star stag
MODELS.asterion = (r) => {
  r.olw = 0; r.hopAmp = 0.3;
  const B = grp(r.body); B.scale.setScalar(1.85);
  const CM = cosmicMat(), LINE = E(0xbfeaff, 2.4), NODE = E(0xffffff, 3.6);
  part(GEO.sphere, CM, B, [0, 0.98, 0], [0.34, 0.33, 0.6]);
  part(GEO.sphere, CM, B, [0, 1.06, 0.4], [0.3, 0.34, 0.3]);
  part(GEO.sphere, CM, B, [0, 1.0, -0.42], [0.28, 0.3, 0.28]);
  for (const [sx, sz] of [[-1, 1], [1, 1], [-1, -1], [1, -1]]) {
    const hip = grp(B, [sx * 0.18, 0.92, sz * 0.4]);
    part(GEO.cyl, CM, hip, [0, -0.22, 0], [0.075, 0.46, 0.075]);
    const knee = grp(hip, [0, -0.45, 0], [sz > 0 ? 0.12 : -0.22, 0, 0]);
    part(GEO.cyl, CM, knee, [0, -0.22, 0], [0.05, 0.44, 0.05]);
    part(GEO.octa, NODE, knee, [0, -0.47, 0], [0.06, 0.05, 0.06]);
    part(GEO.torus, E(0x8fe0ff, 2.2), knee, [0, -0.44, 0], [0.07, 0.07, 0.07], [Math.PI / 2, 0, 0]);
    wig(r, hip, 'x', 0.5, 1, sx * sz > 0 ? 0 : Math.PI, true);
  }
  part(GEO.cyl, CM, B, [0, 1.4, 0.58], [0.1, 0.62, 0.1], [0.55, 0, 0]);
  const H = grp(B, [0, 1.7, 0.78]);
  part(GEO.sphere, CM, H, [0, 0, 0], [0.16, 0.17, 0.25]);
  part(GEO.sphere, CM, H, [0, -0.05, 0.2], [0.1, 0.09, 0.15]);
  for (const sd of [-1, 1]) {
    const eg = grp(H, [sd * 0.11, 0.04, 0.14], [0, sd * 0.6, sd * 0.2]);
    part(GEO.sphere, E(0xcff6ff, 3.8), eg, [0, 0, 0], [0.036, 0.018, 0.03]);
    r.blink.push(eg);
    const e = grp(H, [sd * 0.13, 0.12, -0.08], [0, 0, -sd * 0.9]);
    part(GEO.cone, CM, e, [0, 0.08, 0], [0.05, 0.18, 0.03]);
    wig(r, e, 'z', 0.1, 2, sd);
  }
  const branch = (parent, depth, len, sd) => {
    part(GEO.cyl, LINE, parent, [0, len / 2, 0], [0.011, len, 0.011]);
    part(GEO.sphere, NODE, parent, [0, len, 0], depth === 0 ? 0.03 : 0.02);
    if (depth > 0) {
      branch(grp(parent, [0, len, 0], [0.25, 0, -sd * 0.55]), depth - 1, len * 0.74, sd);
      branch(grp(parent, [0, len, 0], [-0.2, 0, sd * 0.42]), depth - 1, len * 0.62, sd);
    }
  };
  for (const sd of [-1, 1]) branch(grp(H, [sd * 0.07, 0.13, -0.05], [-0.3, 0, -sd * 0.45]), 3, 0.3, sd);
  const pts = [[0, 1.31, -0.5], [0.12, 1.33, -0.1], [-0.05, 1.34, 0.25], [0.16, 1.25, 0.48], [-0.2, 1.12, 0.2], [0.25, 1.0, -0.3], [-0.24, 1.05, -0.55]];
  for (let i = 0; i < pts.length; i++) { part(GEO.sphere, NODE, B, pts[i], 0.022); if (i > 0) beamBetween(B, pts[i - 1], pts[i], LINE, 0.008); }
  let p = grp(B, [0, 1.15, -0.62], [0.9, 0, 0]);
  for (let k = 0; k < 7; k++) {
    part(GEO.sphere, E([0x8a6aff, 0x6a9aff, 0xb48cff][k % 3], 1.1 + k * 0.15, { transparent: true, opacity: 0.6, depthWrite: false }), p, [0, 0, -0.08], 0.12 - k * 0.012).userData.noOl = true;
    wig(r, p, 'y', 0.25, 1.6, -k * 0.6);
    p = grp(p, [0, 0, -0.14], [-0.15, 0, 0]);
  }
  const halo = grp(B, [0, 2.15, 0.1]);
  for (let i = 0; i < 12; i++) { const a = (i / 12) * Math.PI * 2; part(GEO.octa, NODE, halo, [Math.cos(a) * 0.5, 0, Math.sin(a) * 0.5], [0.025, 0.05, 0.025]); }
  part(GEO.ring, E(0x8fe0ff, 1.8), halo, [0, 0, 0], [0.5, 0.5, 2], [Math.PI / 2, 0, 0]);
  spin(r, halo, 'y', 0.5);
  motes(r, B, 60, 0x9fd8ff, 0.9, 2.0);
  r.size = 3.9;
};

// ---------- 아비세아 : the abyssal whale
MODELS.abyssea = (r) => {
  r.float = 1.5; r.floatAmp = 0.22; r.noBreath = true; r.olw = 0;
  const B = grp(r.body); B.scale.setScalar(1.05);
  const SKIN = M(0x16365e), BELLY = M(0x3a7aa0), DARK = M(0x0b1e38);
  const GL = E(0x5ff4ff, 2.8), GL2 = E(0xa98bff, 2.4);
  const segs = [];
  for (let i = 0; i < 15; i++) {
    const u = i / 14, rad = lerp(0.82, 0.13, Math.pow(u, 0.85));
    const g = grp(B);
    part(GEO.sphere, SKIN, g, [0, 0, 0], [rad * 1.15, rad * 0.92, rad * 1.25]);
    part(GEO.sphere, BELLY, g, [0, -rad * 0.38, 0.02], [rad * 0.95, rad * 0.55, rad * 1.1]);
    if (i % 2 === 0) for (const sx of [-1, 1]) part(GEO.sphere, GL, g, [sx * rad * 1.05, rad * 0.08, 0], rad * 0.1);
    if (i > 0 && i < 12) part(GEO.box, GL2, g, [0, rad * 0.9, 0], [rad * 0.07, rad * 0.07, rad * 1.0]);
    if (i % 3 === 1) part(GEO.cone, DARK, g, [0, rad * 1.0, -rad * 0.2], [rad * 0.25, rad * 0.7, rad * 0.4], [-0.7, 0, 0]);
    segs.push({ g, u, rad });
  }
  const tail = segs[segs.length - 1].g;
  for (const sx of [-1, 1]) {
    part(GEO.sphere, SKIN, tail, [sx * 0.5, 0, -0.25], [0.62, 0.045, 0.32], [0, sx * 0.6, 0]);
    part(GEO.box, GL, tail, [sx * 0.62, 0.03, -0.35], [0.7, 0.012, 0.012], [0, sx * 0.6, 0]);
  }
  const place = (t) => {
    for (const sg of segs) {
      const u = sg.u;
      sg.g.position.set(Math.sin(t * 0.7 - u * 3.2) * 0.35 * u, Math.sin(t * 1.2 - u * 4.5) * 0.38 * u, 0.2 - u * 6.4);
      sg.g.rotation.x = Math.cos(t * 1.2 - u * 4.5) * 0.35 * u; sg.g.rotation.y = Math.cos(t * 0.7 - u * 3.2) * 0.22 * u;
    }
  };
  place(0); r.fns.push(place);
  const H = grp(B, [0, 0.05, 0.75]);
  part(GEO.sphere, SKIN, H, [0, 0, 0], [0.95, 0.78, 1.15]);
  part(GEO.sphere, BELLY, H, [0, -0.32, 0.1], [0.85, 0.48, 1.05]);
  part(GEO.box, E(0x2fd8ff, 1.8), H, [0, -0.2, 1.1], [0.9, 0.02, 0.02]);
  for (const sx of [-1, 1]) for (let k = 0; k < 3; k++) {
    const eg = grp(H, [sx * (0.7 - k * 0.04), 0.2 - k * 0.14, 0.72 - k * 0.24]);
    part(GEO.sphere, E(0xbff8ff, 3.8), eg, [0, 0, 0], 0.075 - k * 0.015);
    r.blink.push(eg);
  }
  for (let k = 0; k < 5; k++) part(GEO.cone, GL2, H, [(k - 2) * 0.16, 0.72 - Math.abs(k - 2) * 0.06, -0.2], [0.04, 0.5, 0.04], [-1.0, 0, (k - 2) * 0.15]);
  let lp = grp(H, [0, 0.72, 0.5], [0.4, 0, 0]);
  for (let k = 0; k < 4; k++) { part(GEO.cyl, DARK, lp, [0, 0.12, 0], [0.025, 0.24, 0.025]); wig(r, lp, 'x', 0.18, 1.4, k * 0.7); lp = grp(lp, [0, 0.24, 0], [0.25, 0, 0]); }
  part(GEO.sphere, E(0x8ffcff, 3.8), lp, [0, 0.06, 0], 0.11);
  part(GEO.torus, E(0x5ff4ff, 2), lp, [0, 0.06, 0], 0.17, [Math.PI / 2, 0, 0]);
  const finM = toonMat({ color: 0x2a7ab8, transparent: true, opacity: 0.62, side: THREE.DoubleSide });
  for (const sx of [-1, 1]) {
    const f = grp(B, [sx * 0.85, -0.25, -0.1], [0, sx * 0.25, sx * -0.25]);
    part(GEO.sphere, finM, f, [sx * 1.3, 0, -0.3], [1.5, 0.04, 0.7]);
    for (let k = 0; k < 3; k++) part(GEO.box, GL, f, [sx * (0.7 + k * 0.1), 0.02, -0.3 + (k - 1) * 0.25], [1.3 - k * 0.2, 0.012, 0.012], [0, sx * (k - 1) * 0.25, 0]);
    wig(r, f, 'z', 0.28, 1.1, sx > 0 ? 0 : Math.PI);
  }
  motes(r, B, 70, 0x7ff0ff, 2.6, 3.2);
  r.size = 3.0;
};

// ---------- 단하 : the dawn dragon
MODELS.danha = (r) => {
  r.float = 1.7; r.floatAmp = 0.18; r.noBreath = true; r.olw = 0.018;
  const B = grp(r.body);
  const RED = M(0xd2283f), RED2 = M(0xb21d34), GOLD = M(0xf2c35a), CREAM = M(0xffe2a8);
  const segs = [];
  for (let i = 0; i < 28; i++) {
    const u = i / 27, rad = lerp(0.3, 0.07, Math.pow(u, 0.9));
    const g = grp(B);
    part(GEO.sphere, i % 2 ? RED : RED2, g, [0, 0, 0], [rad, rad, rad * 1.3]);
    part(GEO.sphere, CREAM, g, [0, -rad * 0.45, 0], [rad * 0.75, rad * 0.5, rad * 1.15]);
    if (i % 2 === 0 && i < 25) { const f = flame(r, g, [0, rad * 0.8, -rad * 0.2], Math.max(0.5, rad * 2.8)); f.rotation.x = -0.5; }
    segs.push({ g, u, rad });
  }
  flame(r, segs[27].g, [0, 0, -0.08], 1.1).rotation.x = -1.4;
  const legAt = (sg, sx) => {
    const L = grp(sg.g, [sx * sg.rad * 0.9, -sg.rad * 0.4, 0], [0.3, 0, sx * 0.6]);
    part(GEO.capsule, RED, L, [0, -0.15, 0], [0.08, 0.16, 0.08]);
    for (let k = -1; k <= 1; k++) part(GEO.cone, GOLD, L, [k * 0.035, -0.33, 0.04], [0.025, 0.09, 0.025], [0.3, 0, Math.PI + k * 0.3]);
    wig(r, L, 'x', 0.4, 2.2, sx); return L;
  };
  const fl = legAt(segs[3], 1); legAt(segs[3], -1); legAt(segs[13], 1); legAt(segs[13], -1);
  const pearl = grp(fl, [0, -0.38, 0.1]);
  part(GEO.sphere, E(0xffeab0, 3.8), pearl, [0, 0, 0], 0.13);
  part(GEO.torus, E(0xffc04a, 2.2), pearl, [0, 0, 0], 0.2);
  spin(r, pearl, 'y', 1.5);
  const puffM = toonMat({ color: 0xfff0e6, transparent: true, opacity: 0.92 });
  for (const [si, sx] of [[7, 1], [15, -1], [21, 1], [25, -1]]) {
    const c = grp(segs[si].g, [sx * 0.3, -0.25, 0]);
    for (let k = 0; k < 4; k++) part(GEO.sphere, puffM, c, [k * 0.14 * sx, Math.sin(k) * 0.05, (k % 2) * 0.1], 0.13 + (k % 2) * 0.05);
  }
  const H = grp(B);
  part(GEO.sphere, RED, H, [0, 0, 0], [0.3, 0.25, 0.36]);
  part(GEO.sphere, RED2, H, [0, -0.04, 0.32], [0.2, 0.15, 0.3]);
  part(GEO.sphere, GOLD, H, [0, 0.0, 0.6], [0.06, 0.05, 0.05]);
  const jaw = grp(H, [0, -0.12, 0.1]);
  part(GEO.sphere, CREAM, jaw, [0, 0, 0.18], [0.17, 0.07, 0.32]);
  for (const sx of [-1, 1]) part(GEO.cone, M(0xffffff), jaw, [sx * 0.08, 0.06, 0.38], [0.02, 0.06, 0.02], [Math.PI, 0, 0]);
  wig(r, jaw, 'x', 0.12, 1.4);
  eyes(r, H, { x: 0.17, y: 0.08, z: 0.2, rad: 0.055, glowc: 0xffc24a, tilt: 0.35 });
  for (const sx of [-1, 1]) {
    part(GEO.cone, GOLD, H, [sx * 0.17, 0.15, 0.18], [0.03, 0.12, 0.03], [-1.2, 0, -sx * 0.4]);
    const a = grp(H, [sx * 0.12, 0.18, -0.08], [-0.55, 0, -sx * 0.35]);
    part(GEO.cyl, GOLD, a, [0, 0.25, 0], [0.028, 0.5, 0.028]);
    const b1 = grp(a, [0, 0.22, 0], [0.2, 0, -sx * 0.9]); part(GEO.cyl, GOLD, b1, [0, 0.12, 0], [0.02, 0.24, 0.02]);
    const b2 = grp(a, [0, 0.38, 0], [-0.3, 0, sx * 0.7]); part(GEO.cyl, GOLD, b2, [0, 0.1, 0], [0.018, 0.2, 0.018]);
    let w = grp(H, [sx * 0.14, -0.06, 0.48], [0, 0, -sx * 1.2]);
    for (let k = 0; k < 7; k++) { part(GEO.cyl, E(0xffd27a, 1.5), w, [0, 0.07, 0], [0.008, 0.14, 0.008]); wig(r, w, 'z', 0.25, 1.8, k * 0.6 + sx); w = grp(w, [0, 0.14, 0], [0.15, 0, -sx * 0.12]); }
    const mf = flame(r, H, [sx * 0.14, 0.1, -0.25], 0.8); mf.rotation.set(-1.0, 0, sx * 0.6);
  }
  flame(r, H, [0, 0.2, -0.22], 0.9).rotation.x = -1.1;
  for (let k = -1; k <= 1; k++) part(GEO.cone, CREAM, H, [k * 0.06, -0.24, 0.2], [0.03, 0.14, 0.03], [Math.PI - 0.3, 0, k * 0.2]);
  const fwd = new THREE.Vector3(0, 0, 1), dir = new THREE.Vector3();
  const place = (t) => {
    for (const sg of segs) {
      const u = sg.u, a = u * 6.2 + t * 1.1;
      sg.g.position.set(Math.sin(a) * (0.45 + u * 0.95), 0.35 + Math.cos(a * 0.9) * 0.45 * u - u * 0.7, 0.35 - u * 3.1 + Math.cos(a) * 0.35 * u);
    }
    for (let i = 0; i < segs.length; i++) {
      const a = segs[Math.max(0, i - 1)].g.position, b = segs[Math.min(segs.length - 1, i + 1)].g.position;
      dir.subVectors(a, b); if (dir.lengthSq() > 1e-6) segs[i].g.quaternion.setFromUnitVectors(fwd, dir.normalize());
    }
    H.quaternion.copy(segs[0].g.quaternion);
    H.position.copy(segs[0].g.position).add(new THREE.Vector3(0, 0.08, 0.22).applyQuaternion(H.quaternion));
  };
  place(0); r.fns.push(place);
  r.size = 3.5;
};

// ---------- 리미나 : the boundary manta (half Being, half Void)
let _mantaGeo = null;
function mantaGeo() {
  if (_mantaGeo) return _mantaGeo;
  const g = new THREE.SphereGeometry(1, 96, 48), p = g.attributes.position;
  for (let i = 0; i < p.count; i++) {
    const x = p.getX(i), y = p.getY(i), z = p.getZ(i), ax = Math.abs(x);
    p.setXYZ(i, x * 2.9, y * 0.36 * (1 - ax * ax * 0.8) + (1 - ax * ax) * 0.06, z * 1.3 * (1 - ax * 0.62) - Math.pow(ax, 1.7) * 1.15 + 0.35 * (1 - ax));
  }
  g.computeVertexNormals(); _mantaGeo = g; return g;
}
function mantaMat() {
  if (_mc.has('manta')) return _mc.get('manta');
  const m = new THREE.ShaderMaterial({
    uniforms: THREE.UniformsUtils.merge([THREE.UniformsLib.fog, { uSun: { value: new THREE.Vector3(-0.4, 0.8, 0.4).normalize() }, uPearl: { value: new THREE.Color(0xd8cfe8) }, uGold: { value: new THREE.Color(0xffd27a) }, uViolet: { value: new THREE.Color(0xb04bff) }, uPx: { value: 1 }, uTime: { value: 0 } }]),
    vertexShader: `uniform float uTime; varying vec3 vN; varying vec3 vV; varying vec3 vO; varying vec3 vWN; ${FOG_V}
      void main(){
        vec3 p = position; float ax = abs(p.x) / 2.9; float ph = uTime * 1.5 - ax * 2.4;
        p.y += sin(ph) * ax * ax * 0.95; p.z += cos(ph) * ax * 0.08;
        vec3 n = normal; n.x -= sign(position.x) * cos(ph) * ax * 0.7; n = normalize(n);
        vN = normalize(normalMatrix * n); vWN = normalize(mat3(modelMatrix) * n); vO = position;
        vec4 mvPosition = modelViewMatrix * vec4(p, 1.0); vV = normalize(-mvPosition.xyz);
        gl_Position = projectionMatrix * mvPosition;
        #include <fog_vertex>
      }`,
    fragmentShader: `uniform vec3 uSun, uPearl, uGold, uViolet; uniform float uTime, uPx; varying vec3 vN; varying vec3 vV; varying vec3 vO; varying vec3 vWN;
      ${GLSL_NOISE}
      ${FOG_F}
      void main(){
        float side = smoothstep(-0.03, 0.03, vO.x);
        float nl = max(dot(vWN, normalize(uSun)), 0.0);
        float toon = nl > 0.55 ? 1.0 : (nl > 0.18 ? 0.78 : 0.58);
        float top = step(0.0, vO.y);
        float rings = sin(length(vO.xz * vec2(1.0, 1.7)) * 13.0 - uTime * 0.8);
        float fil = smoothstep(0.9, 1.0, rings) * top;
        float spots = smoothstep(0.82, 0.86, vnoise(vO.xz * 3.0)) * top;
        vec3 being = uPearl * toon * (0.75 + 0.25 * top) + uGold * (fil * 1.6 + spots * 0.9);
        vec2 fc = gl_FragCoord.xy / uPx; float h = hash12(floor(fc / 3.0));
        float star = step(0.975, h) * smoothstep(0.55, 0.0, length(fract(fc / 3.0) - 0.5)) * (0.5 + 0.5 * sin(uTime * 2.0 + h * 70.0));
        vec3 voidc = vec3(0.015, 0.008, 0.035) + uViolet * (fil * 2.0 + spots * 0.8) + vec3(1.5) * star * top;
        vec3 col = mix(being, voidc, side);
        float fr = pow(1.0 - max(dot(normalize(vN), normalize(vV)), 0.0), 2.4);
        col += mix(uGold * 1.7, uViolet * 2.2, side) * fr;
        col += mix(uGold, uViolet, 0.5) * exp(-abs(vO.x) * 22.0) * 3.2 * top;
        gl_FragColor = vec4(col, 1.0);
        #include <fog_fragment>
      }`,
    fog: true,
  });
  m.uniforms.uTime = Shared.time; m.uniforms.uPx.value = renderer.getPixelRatio();
  _mc.set('manta', m); return m;
}
MODELS.limina = (r) => {
  r.float = 2.0; r.floatAmp = 0.25; r.noBreath = true; r.olw = 0;
  const B = grp(r.body); B.scale.setScalar(1.15);
  const body = new THREE.Mesh(mantaGeo(), mantaMat()); B.add(body);
  const PEARL = M(0xf4eefc), VM = voidMat(0xb055ff, 2.2);
  for (const sx of [-1, 1]) {
    const c = grp(B, [sx * 0.42, 0.05, 1.0], [0, -sx * 0.2, 0]);
    part(GEO.cone, sx < 0 ? PEARL : VM, c, [0, 0, 0.22], [0.09, 0.5, 0.09], [Math.PI / 2 - 0.4, 0, 0]);
    part(GEO.cone, sx < 0 ? E(0xffd27a, 2.4) : E(0xc77dff, 2.4), c, [0, -0.13, 0.46], [0.04, 0.16, 0.04], [Math.PI / 2 + 0.6, 0, 0]);
    wig(r, c, 'x', 0.15, 1.5, sx);
  }
  const eye = grp(B, [0, 0.33, 0.55], [-1.2, 0, 0]);
  part(GEO.circle, new THREE.MeshBasicMaterial({ color: 0x000000 }), eye, [0, 0, 0], 0.13);
  part(new THREE.TorusGeometry(0.16, 0.025, 8, 32, Math.PI), E(0xffd27a, 3), eye, [0, 0, 0.01], 1, [0, 0, Math.PI / 2]);
  part(new THREE.TorusGeometry(0.16, 0.025, 8, 32, Math.PI), E(0xc77dff, 3), eye, [0, 0, 0.01], 1, [0, 0, -Math.PI / 2]);
  const pup = part(GEO.sphere, E(0xffffff, 5), eye, [0, 0, 0.02], 0.03);
  r.blink.push(eye);
  r.fns.push((t) => pup.scale.setScalar(0.03 * (1 + Math.max(0, Math.sin(t * 1.3)) * 0.7)));
  let tp = grp(B, [0, 0.0, -1.35]);
  for (let k = 0; k < 9; k++) {
    part(GEO.sphere, k % 2 ? E(0xffd27a, 1.6) : voidMat(0xb055ff, 2.4), tp, [0, 0, -0.1], 0.05 - k * 0.003);
    wig(r, tp, 'y', 0.16, 1.5, -k * 0.5); wig(r, tp, 'x', 0.08, 1.5, -k * 0.5 + 1);
    tp = grp(tp, [0, 0, -0.2]);
  }
  const orb = grp(tp, [0, 0, -0.05]);
  part(new THREE.SphereGeometry(0.13, 20, 12, 0, Math.PI), E(0xffeab0, 3), orb, [0, 0, 0], 1, [0, Math.PI / 2, 0]);
  part(new THREE.SphereGeometry(0.13, 20, 12, 0, Math.PI), voidMat(0xd06bff, 1.8), orb, [0, 0, 0], 1, [0, -Math.PI / 2, 0]);
  spin(r, orb, 'z', 1.4);
  const halo = grp(B, [0, 0.95, -0.15]);
  part(new THREE.TorusGeometry(1.1, 0.03, 8, 64, Math.PI), E(0xffd27a, 2.4), halo, [0, 0, 0], 1, [Math.PI / 2, 0, 0]);
  part(new THREE.TorusGeometry(1.1, 0.03, 8, 64, Math.PI), E(0xc77dff, 2.6), halo, [0, 0, 0], 1, [Math.PI / 2, 0, Math.PI]);
  for (let i = 0; i < 8; i++) { const a = (i / 8) * Math.PI * 2; part(GEO.octa, i < 4 ? E(0xffe7a8, 2.8) : E(0xd9a6ff, 2.8), halo, [Math.cos(a) * 1.1, 0, Math.sin(a) * 1.1], [0.04, 0.08, 0.04]); }
  spin(r, halo, 'y', 0.35);
  motes(r, B, 50, 0xffd98a, 2.4, 1.6);
  motes(r, B, 50, 0xb04bff, 2.4, 1.6);
  r.size = 3.0;
};

// ---------- people
function buildPerson(o = {}) {
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

function makeSpiritModel(sp) {
  const r = newRig();
  (MODELS[sp] || MODELS.somgu)(r);
  if (r.olw > 0) addOutlines(r.body, r.olw);
  r.body.traverse((m) => { if (m.isMesh && !m.userData.isOl && m.material && !m.material.isMeshBasicMaterial && !m.material.transparent && !m.material.isShaderMaterial) m.castShadow = true; });
  r.sp = sp;
  return r;
}

// white hit-flash by swapping materials for a moment
const FLASH_MAT = new THREE.MeshBasicMaterial({ color: new THREE.Color(2.2, 2.2, 2.2) });
function flashRig(r, on, mat = FLASH_MAT) {
  r.root.traverse((o) => {
    if (!o.isMesh || o.userData.isOl) return;
    if (on) { if (!o.userData.m0) o.userData.m0 = o.material; o.material = mat; }
    else if (o.userData.m0) { o.material = o.userData.m0; o.userData.m0 = null; }
  });
}
function disposeRig(r) { if (r && r.root.parent) r.root.parent.remove(r.root); }

// ---------- portrait icons (offscreen renderer, cached data URLs)
const Icons = {
  cache: {}, rnd: null, scene: null, cam: null,
  get(sp) {
    if (this.cache[sp]) return this.cache[sp];
    try {
      if (!this.rnd) {
        this.rnd = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: true });
        this.rnd.setSize(160, 160, false); this.rnd.setPixelRatio(1);
        this.rnd.outputColorSpace = THREE.SRGBColorSpace; this.rnd.toneMapping = THREE.ACESFilmicToneMapping;
        this.scene = new THREE.Scene();
        this.scene.add(new THREE.HemisphereLight(0xdcd6ff, 0x4a3a5a, 1.6));
        const d = new THREE.DirectionalLight(0xffffff, 2.2); d.position.set(2, 3, 4); this.scene.add(d);
        this.cam = new THREE.PerspectiveCamera(30, 1, 0.1, 50);
      }
      const r = makeSpiritModel(sp);
      rigUpdate(r, 0.01);
      const s = r.size;
      r.root.rotation.y = 0.45;
      this.scene.add(r.root);
      const cy = (r.float || 0) + s * 0.42;
      this.cam.position.set(0, cy + s * 0.08, s * 2.35); this.cam.lookAt(0, cy, 0);
      this.rnd.render(this.scene, this.cam);
      this.cache[sp] = this.rnd.domElement.toDataURL('image/png');
      this.scene.remove(r.root);
    } catch (e) { this.cache[sp] = ''; }
    return this.cache[sp];
  },
};
