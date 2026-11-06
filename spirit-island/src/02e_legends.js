// ============================================================================
//  the six legendary dragons
// ============================================================================
const _legendDesigns = {};
function legendDesign(sp) {
  if (_legendDesigns[sp]) return _legendDesigns[sp];
  let d;
  switch (sp) {
    case 'nihilos': d = designWestern({ horns: 'crown', bulk: 1.1, tail: 1.15, tailBlade: true, spikeScale: 1.35, spikeGlow: 0.7, colors: { body: 0x1a1226, belly: 0x2a1d45, horn: 0x140d1e, spike: 0x22172f, claw: 0x0c0814, glowHorn: 0.9 } }); break;
    case 'ensia': d = designWestern({ horns: 'swept', bulk: 1.0, neck: 1.2, spikeScale: 0.8, colors: { body: 0xf3eee6, belly: 0xead7ac, horn: 0xe2b85a, spike: 0xeccf86, claw: 0xc9a24a, glowHorn: 0.35 } }); break;
    case 'asterion': d = designWestern({ horns: 'crystal', bulk: 0.9, neck: 1.35, tail: 1.25, spikeScale: 1.1, spikeGlow: 1.0, colors: { body: 0x111a48, belly: 0x1d2e66, horn: 0xa8ecff, spike: 0x8fd8ff, claw: 0x9fe0ff, glowHorn: 1.2 } }); break;
    case 'limina': d = designWestern({ horns: 'swept', bulk: 1.0, neck: 1.1, tail: 1.1, tailBlade: true, spikeGlow: 0.5, colors: { body: 0xe9e2f4, belly: 0xe8d8b8, horn: 0xffd27a, spike: 0xf0d8a0, claw: 0xffd27a, glowHorn: 0.6 } }); break;
    case 'danha': d = designEastern({ antlers: true, legs: true, length: 13, radius: 0.36, ridge: 0.18, ridgeGlow: 0.7, colors: { body: 0xc21d38, belly: 0xf2c35a, horn: 0xf2c35a, spike: 0xff7a2a, claw: 0xf2c35a } }); break;
    case 'abyssea': d = designEastern({ head: 'whale', fluke: true, sail: true, radius: 0.56, length: 12.5, ridge: 0.24, ridgeGlow: 0.9, colors: { body: 0x0b2846, belly: 0x2a6a8a, spike: 0x1a6a8e } }); break;
  }
  _legendDesigns[sp] = d; return d;
}
const VOID_WING = { style: 'void', mem: 0x0a0612, edge: 0xb04bff, bone: 0x1a1226, scale: 1.12 };
const GOLD_WING = { style: 'feather', mem: 0xfff6e6, edge: 0xffd27a, bone: 0xe2b85a, scale: 1.05 };

MODELS.nihilos = (r) => {
  const D = legendDesign('nihilos');
  const B = buildDragon(r, {
    key: 'nihilos', design: D, scale: 0.62, float: 1.15, eye: 0xead2ff,
    mat: { rough: 0.26, metal: 0.55, coat: 0.85, coatRough: 0.18, irid: 0.9, belly: 0x2a1d45, glow: 0xb04bff, vein: 1.2, glowAmt: 3.2, rim: 0x9b5cff, rimAmt: 0.6, scaleFreq: 5.5, bump: 0.32 },
    wings: [VOID_WING, VOID_WING],
  });
  const ch = grp(B, [0, D.chest[1], D.chest[2] + 0.06]);
  part(GEO.circle, new THREE.MeshBasicMaterial({ color: 0x000000 }), ch, [0, 0, 0.02], 0.25);
  const r1 = grp(ch); part(GEO.torus, E(0xd06bff, 3.2), r1, [0, 0, 0], [0.27, 0.27, 1.1]);
  const r2 = grp(ch); part(GEO.torus, E(0xff6ad5, 2.2), r2, [0, 0, 0], [0.36, 0.36, 0.5]);
  const pt = part(GEO.sphere, E(0xffffff, 6), ch, [0, 0, 0.04], 0.03);
  r.fns.push((t) => { r1.rotation.set(Math.sin(t * 0.7) * 0.3, Math.cos(t * 0.5) * 0.3, t * 0.9); r2.rotation.set(Math.cos(t * 0.6) * 0.5, Math.sin(t * 0.4) * 0.5, -t * 0.5); pt.scale.setScalar(0.03 * (1 + Math.max(0, Math.sin(t * 1.7)) * 0.8)); });
  r.glue(ch, D.sChest);
  const orb = grp(B, [0, 2.2, -0.6]);
  for (let i = 0; i < 9; i++) { const a = (i / 9) * Math.PI * 2, R = 2.6 + (i % 3) * 0.4; const s = part(GEO.octa, voidMat(i % 2 ? 0xb055ff : 0xff4fd8, 2.4), orb, [Math.cos(a) * R, Math.sin(a * 3) * 0.8, Math.sin(a) * R], [0.12, 0.3, 0.12]); spin(r, s, 'x', 0.8 + i * 0.1); }
  spin(r, orb, 'y', -0.3);
  const pm = motes(r, ch, 140, 0xb04bff, 2.4, 2.0, true);
  r.size = 3.0;
};
MODELS.ensia = (r) => {
  const D = legendDesign('ensia');
  const B = buildDragon(r, {
    key: 'ensia', design: D, scale: 0.62, float: 1.25, eye: 0xfff2c4,
    mat: { rough: 0.3, metal: 0.25, coat: 1.0, coatRough: 0.12, sheen: 0.6, sheenCol: 0xffe2a0, irid: 0.3, belly: 0xead7ac, glow: 0xffd27a, vein: 0.5, glowAmt: 2.6, rim: 0xffe6b0, rimAmt: 0.42, scaleFreq: 9, bump: 0.22 },
    wings: [GOLD_WING, GOLD_WING],
  });
  const halo = grp(B, [D.head[0], D.head[1] + 0.25, D.head[2] - 0.55]);
  part(GEO.torus, E(0xffe2a0, 2.6), halo, [0, 0, 0], [0.95, 0.95, 0.9]);
  const h2 = grp(halo); part(GEO.torus, E(0xfff0c8, 1.8), h2, [0, 0, 0], [1.2, 1.2, 0.5]);
  for (let i = 0; i < 16; i++) { const a = (i / 16) * Math.PI * 2; part(GEO.octa, E(0xffd98a, 2.6), h2, [Math.cos(a) * 1.2, Math.sin(a) * 1.2, 0], [0.04, i % 2 ? 0.16 : 0.09, 0.03], [0, 0, a + Math.PI / 2]); }
  spin(r, h2, 'z', 0.25);
  r.glue(halo, 1);
  const core = grp(B, [0, D.chest[1], D.chest[2] + 0.05]);
  const cs = part(GEO.sphere, E(0xffefb8, 4.2), core, [0, 0, 0], 0.15);
  part(GEO.torus, E(0xffd27a, 2.6), core, [0, 0, 0], 0.24);
  r.fns.push((t) => cs.scale.setScalar(0.15 * (1 + Math.sin(t * 2.2) * 0.12)));
  r.glue(core, D.sChest);
  motes(r, B, 80, 0xffd98a, 3.2, 4.0);
  r.size = 3.1;
};
MODELS.asterion = (r) => {
  const D = legendDesign('asterion');
  const B = buildDragon(r, {
    key: 'asterion', design: D, scale: 0.6, float: 0.95, eye: 0xd4f6ff,
    mat: { rough: 0.2, metal: 0.35, coat: 1.0, coatRough: 0.08, irid: 1.0, belly: 0x1d2e66, glow: 0x8fe0ff, vein: 0.9, glowAmt: 3.4, rim: 0x7fd8ff, rimAmt: 0.7, stars: 0.7, scaleFreq: 6.5, bump: 0.28 },
    wings: [{ style: 'nebula', mem: 0x0e1650, edge: 0x8fe0ff, bone: 0x9fe8ff, scale: 1.08 }, { style: 'nebula', mem: 0x0e1650, edge: 0x8fe0ff, bone: 0x9fe8ff, scale: 1.08 }],
  });
  const halo = grp(B, [D.head[0], D.head[1] + 1.2, D.head[2] - 0.6]);
  for (let i = 0; i < 12; i++) { const a = (i / 12) * Math.PI * 2; part(GEO.octa, E(0xffffff, 3.6), halo, [Math.cos(a) * 0.7, 0, Math.sin(a) * 0.7], [0.03, 0.07, 0.03]); }
  part(GEO.ring, E(0x8fe0ff, 1.8), halo, [0, 0, 0], [0.7, 0.7, 2.5], [Math.PI / 2, 0, 0]);
  spin(r, halo, 'y', 0.5); r.glue(halo, 1);
  motes(r, B, 90, 0x9fd8ff, 3.5, 4.0);
  r.size = 3.2;
};
MODELS.limina = (r) => {
  const D = legendDesign('limina');
  const B = buildDragon(r, {
    key: 'limina', design: D, scale: 0.62, float: 1.3, eye: 0xffffff,
    mat: { rough: 0.3, metal: 0.3, coat: 0.95, coatRough: 0.15, irid: 0.55, belly: 0xe8d8b8, glow: 0xffd27a, vein: 0.55, glowAmt: 2.4, rim: 0xffe6b0, rimAmt: 0.5, split: true, voidCol: 0x07050d, scaleFreq: 6, bump: 0.28 },
    wings: [GOLD_WING, VOID_WING],
  });
  const halo = grp(B, [D.head[0], D.head[1] + 0.3, D.head[2] - 0.6]);
  part(new THREE.TorusGeometry(1.0, 0.035, 8, 64, Math.PI), E(0xffd27a, 2.6), halo, [0, 0, 0], 1, [0, 0, Math.PI / 2]);
  part(new THREE.TorusGeometry(1.0, 0.035, 8, 64, Math.PI), E(0xc77dff, 2.8), halo, [0, 0, 0], 1, [0, 0, -Math.PI / 2]);
  for (let i = 0; i < 10; i++) { const a = (i / 10) * Math.PI * 2; part(GEO.octa, Math.cos(a) < 0 ? E(0xffe7a8, 2.8) : E(0xd9a6ff, 2.8), halo, [Math.cos(a) * 1.0, Math.sin(a) * 1.0, 0], [0.035, 0.08, 0.035], [0, 0, a]); }
  r.glue(halo, 1);
  motes(r, B, 60, 0xffd98a, 3, 3.5); motes(r, B, 60, 0xb04bff, 3, 3.5);
  r.size = 3.1;
};
MODELS.danha = (r) => {
  const D = legendDesign('danha');
  const B = buildDragon(r, {
    key: 'danha', design: D, scale: 0.6, float: 1.45, eye: 0xffc24a,
    mat: { rough: 0.28, metal: 0.4, coat: 0.9, coatRough: 0.2, sheen: 0.35, sheenCol: 0xffb070, belly: 0xf2c35a, glow: 0xff8a3d, vein: 0.6, glowAmt: 2.8, rim: 0xffa860, rimAmt: 0.45, serp: 1, waveAmp: 0.32, waveFreq: 8.5, waveSpeed: 1.5, scaleFreq: 6.5, bump: 0.3 },
  });
  for (const q of D.spine) {
    if (q.s < 0.12 || Math.round(q.s * 60) % 3 !== 0) continue;
    const f = flame(r, B, [q.p[0], q.p[1] + q.r * 0.9, q.p[2]], Math.max(0.55, q.r * 2.6) * (q.s > 0.82 ? 1.4 : 1)); f.rotation.x = -0.55;
    r.glue(f, q.s);
  }
  for (const [i, wr] of D.whiskerRoots.entries()) {
    const sx = i ? 1 : -1;
    let w = grp(B, wr, [0, 0, -sx * 1.25]); const root = w;
    for (let k = 0; k < 8; k++) { part(GEO.cyl, E(0xffd27a, 1.6), w, [0, 0.08, 0], [0.012, 0.16, 0.012]); wig(r, w, 'z', 0.22, 1.7, k * 0.6 + sx); wig(r, w, 'x', 0.12, 1.3, k * 0.5); w = grp(w, [0, 0.16, 0], [0.12, 0, -sx * 0.1]); }
    r.glue(root, 1);
  }
  const front = D.spine[Math.round(0.78 * (D.spine.length - 1))];
  const pearl = grp(B, [front.p[0] + 0.55, front.p[1] - 0.75, front.p[2] + 0.35]);
  part(GEO.sphere, E(0xffeab0, 4), pearl, [0, 0, 0], 0.17);
  part(GEO.torus, E(0xffc04a, 2.4), pearl, [0, 0, 0], 0.26); spin(r, pearl, 'y', 1.4);
  r.glue(pearl, front.s);
  const puff = toonMat({ color: 0xfff0e6, transparent: true, opacity: 0.9 });
  for (const u of [0.15, 0.32, 0.55, 0.7]) {
    const q = D.spine[Math.round(u * (D.spine.length - 1))], c = grp(B, [q.p[0] + (u > 0.4 ? 0.5 : -0.5), q.p[1] - 0.45, q.p[2]]);
    for (let k = 0; k < 4; k++) part(GEO.sphere, puff, c, [k * 0.2 - 0.3, Math.sin(k) * 0.07, (k % 2) * 0.15], 0.2 + (k % 2) * 0.08);
    r.glue(c, q.s);
  }
  motes(r, B, 60, 0xffa860, 3.5, 3);
  r.size = 3.0;
};
MODELS.abyssea = (r) => {
  const D = legendDesign('abyssea');
  const B = buildDragon(r, {
    key: 'abyssea', design: D, scale: 0.62, float: 1.3, eye: 0x9ff8ff,
    mat: { rough: 0.1, metal: 0.12, coat: 1.0, coatRough: 0.04, belly: 0x2a6a8a, glow: 0x4ff0ff, vein: 0.25, glowAmt: 3.2, rim: 0x3fd8ff, rimAmt: 0.55, serp: 1, waveAmp: 0.3, waveFreq: 7, waveSpeed: 1.1, stripes: 1.0, scaleFreq: 9, bump: 0.14 },
  });
  const neck = D.spine[Math.round(0.86 * (D.spine.length - 1))];
  for (const side of [-1, 1]) {
    const wm = wingMaterial({ style: 'fin', mem: 0x1a6a9a, edge: 0x4ff0ff, bone: 0x0c2b4c }, side);
    const mesh = new THREE.Mesh(getWing('membrane', side), wm);
    const pv = grp(B, [neck.p[0] + side * neck.r * 0.85, neck.p[1] - 0.15, neck.p[2]]); pv.scale.setScalar(0.42); pv.add(mesh);
    r.dragon.wings.push(wm); r.glue(pv, neck.s);
  }
  r.setFlight('glide');
  const H = D.head;
  let lp = grp(B, [H[0], H[1] + 0.42, H[2] + 0.1], [0.5, 0, 0]); const lroot = lp;
  for (let k = 0; k < 5; k++) { part(GEO.cyl, M(0x0c2b4c), lp, [0, 0.12, 0], [0.025, 0.24, 0.025]); wig(r, lp, 'x', 0.15, 1.3, k * 0.6); lp = grp(lp, [0, 0.24, 0], [0.28, 0, 0]); }
  part(GEO.sphere, E(0x8ffcff, 4), lp, [0, 0.06, 0], 0.12);
  part(GEO.torus, E(0x5ff4ff, 2), lp, [0, 0.06, 0], 0.18, [Math.PI / 2, 0, 0]);
  r.glue(lroot, 1);
  motes(r, B, 80, 0x7ff0ff, 4, 3);
  r.size = 2.6;
};
