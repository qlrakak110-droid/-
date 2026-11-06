// ============================================================================
//  people: sculpted anime adventurers — one smooth body, separate spiky hair,
//  anime eyes with lids, brows and mouth, animated outline, swinging limbs
// ============================================================================
function personKey(C) { return JSON.stringify([C.skin, C.hair, C.top, C.shirt, C.trim, C.bottom, C.shoe, C.glove, C.accent, C.robe, C.beard, C.long, C.pack, C.kid]); }
function designPersonBody(C) {
  const K = critterKit(), hd = { s0: 1, s1: 1 };
  K.el([0, 1.52, 0], [0.35, 0.34, 0.33], C.skin, Object.assign({ k: 0.06 }, hd));
  K.el([0, 1.36, 0.07], [0.22, 0.13, 0.2], C.skin, Object.assign({ k: 0.12 }, hd));
  K.el([0, 1.47, 0.33], [0.025, 0.022, 0.02], C.skin, Object.assign({ k: 0.02 }, hd));
  for (const sx of [-1, 1]) K.el([sx * 0.34, 1.5, 0.02], [0.05, 0.075, 0.05], C.skin, Object.assign({ k: 0.04 }, hd));
  if (C.beard) { K.el([0, 1.33, 0.2], [0.22, 0.19, 0.14], C.beard, Object.assign({ k: 0.06 }, hd)); K.rc([0, 1.22, 0.24], [0, 1.02, 0.26], 0.13, 0.04, C.beard, Object.assign({ k: 0.05 }, hd)); }
  K.rc([0, 1.24, 0], [0, 1.3, 0.02], 0.08, 0.075, C.skin, { k: 0.05, s0: 0.9, s1: 0.9 });
  // torso: jacket over shirt, trim, belt
  K.rc([0, 0.76, 0], [0, 1.1, 0], 0.22, 0.24, C.top, { k: 0.1 });
  K.el([0, 0.98, 0.05], [0.25, 0.21, 0.2], C.top, { k: 0.1 });
  K.el([0, 0.98, 0.2], [0.09, 0.18, 0.06], C.shirt, { k: 0.04 });
  // jacket opening: two trim bands that sit on the surface, a leather strap across the chest, a belt pouch
  for (const sx of [-1, 1]) K.rc([sx * 0.065, 1.14, 0.215], [sx * 0.115, 0.8, 0.228], 0.026, 0.022, C.trim, { k: 0.012 });
  if (!C.robe) {
    K.rc([0.17, 1.12, 0.15], [-0.17, 0.79, 0.205], 0.026, 0.026, 0x6a4430, { k: 0.008 });
    K.el([0.03, 0.96, 0.245], [0.035, 0.035, 0.018], 0xd8b060, { k: 0.006 });
    K.el([0.2, 0.69, 0.15], [0.075, 0.07, 0.055], 0x7a5038, { k: 0.02 });
    K.el([0.2, 0.735, 0.19], [0.07, 0.022, 0.03], 0x5a3a26, { k: 0.01 });
  }
  K.el([0, 1.18, 0.0], [0.21, 0.07, 0.2], C.trim, { k: 0.04 });
  K.el([0, 0.74, 0.0], [0.245, 0.05, 0.21], 0x5a3a26, { k: 0.03 });
  K.el([0, 0.74, 0.205], [0.05, 0.04, 0.025], 0xf2c35a, { k: 0.015 });
  // arms with sleeves, cuffs and gloves (swing channel 2)
  for (const sx of [-1, 1]) {
    K.el([sx * 0.25, 1.1, 0], [0.11, 0.1, 0.11], C.top, { k: 0.06, leg: sx * 2 });
    K.rc([sx * 0.26, 1.08, 0], [sx * 0.33, 0.76, 0.03], 0.085, 0.072, C.top, { k: 0.05, leg: sx * 2 });
    K.el([sx * 0.335, 0.74, 0.03], [0.08, 0.035, 0.08], C.trim, { k: 0.02, leg: sx * 2 });
    K.el([sx * 0.345, 0.65, 0.045], [0.07, 0.08, 0.07], C.glove, { k: 0.03, leg: sx * 2 });
  }
  if (C.robe) {
    K.rc([0, 0.95, 0], [0, 0.1, 0], 0.24, 0.44, C.top, { k: 0.08 });
    for (const a of [0.5, 1.6, 2.7, 3.8, 4.9]) K.el([Math.cos(a) * 0.38, 0.22, Math.sin(a) * 0.36], [0.06, 0.14, 0.06], C.trim, { k: 0.08 });
    K.el([0, 0.06, 0.06], [0.33, 0.06, 0.3], C.shoe, { k: 0.04 });
  } else {
    K.el([0, 0.64, 0], [0.23, 0.13, 0.18], C.bottom, { k: 0.08 });
    for (const sx of [-1, 1]) {
      K.rc([sx * 0.11, 0.62, 0], [sx * 0.12, 0.42, 0.01], 0.1, 0.085, C.bottom, { k: 0.05, leg: sx });
      K.rc([sx * 0.12, 0.42, 0.01], [sx * 0.12, 0.22, 0.02], 0.07, 0.065, C.kid ? C.skin : C.bottom, { k: 0.04, leg: sx });
      K.rc([sx * 0.12, 0.3, 0.02], [sx * 0.12, 0.1, 0.03], 0.085, 0.08, C.shoe, { k: 0.04, leg: sx });
      K.el([sx * 0.12, 0.3, 0.02], [0.1, 0.035, 0.1], 0x8a5a3a, { k: 0.02, leg: sx });
      K.el([sx * 0.12, 0.07, 0.08], [0.095, 0.065, 0.15], C.shoe, { k: 0.04, leg: sx });
    }
  }
  if (C.pack) {
    K.el([0, 0.94, -0.27], [0.19, 0.21, 0.11], 0x8a5a3c, { k: 0.05 });
    K.el([0, 1.07, -0.33], [0.17, 0.06, 0.05], 0xa8754e, { k: 0.03 });
    for (const sx of [-1, 1]) K.rc([sx * 0.15, 1.15, 0.12], [sx * 0.17, 0.82, 0.19], 0.025, 0.025, 0x5a3a26, { k: 0.02 });
  }
  return { prims: K.prims, bounds: [-0.62, -0.05, -0.6, 0.62, 1.95, 0.6], hipY: 0.62, height: 1.95 };
}
function designHair(C) {
  const K = critterKit(), H = C.hair, hd = { s0: 1, s1: 1 }, o = (k = 0.04) => Object.assign({ k }, hd);
  K.el([0, 1.6, -0.04], [0.395, 0.385, 0.385], H, o(0.05));
  K.sub([0, 1.43, 0.24], [0.33, 0.31, 0.3], 0.04);
  for (const [x, len, tw] of [[-0.22, 0.24, -0.08], [-0.11, 0.3, -0.03], [0.0, 0.27, 0.02], [0.11, 0.31, 0.05], [0.22, 0.23, 0.09]]) K.rc([x * 0.9, 1.86, 0.2], [x + tw, 1.86 - len, 0.33], 0.075, 0.012, H, o(0.035));
  for (const sx of [-1, 1]) {
    K.rc([sx * 0.29, 1.72, 0.12], [sx * 0.34, 1.34, 0.2], 0.09, 0.018, H, o(0.04));
    K.rc([sx * 0.33, 1.66, -0.05], [sx * 0.4, 1.4, -0.08], 0.08, 0.015, H, o(0.04));
  }
  for (const [x, y] of [[-0.15, 1.62], [0.15, 1.62], [0, 1.72], [0, 1.5]]) K.rc([x * 0.6, y + 0.08, -0.25], [x, y - 0.12, -0.5], 0.11, 0.015, H, o(0.05));
  K.rc([0.03, 1.95, 0.0], [0.14, 2.12, 0.16], 0.04, 0.006, H, o(0.03));
  if (C.long) { K.el([0, 1.3, -0.2], [0.34, 0.4, 0.2], H, o(0.08)); K.rc([0, 1.2, -0.22], [0, 0.88, -0.26], 0.22, 0.08, H, o(0.06)); }
  return { prims: K.prims, bounds: [-0.55, 0.75, -0.75, 0.55, 2.2, 0.6], hipY: 0, height: 2 };
}
// a strip of cloth hanging from its top edge; bends back, flutters and lifts with speed (vertex shader)
function clothRibbon(parent, o) {
  const L = o.length, seg = 8, taper = o.taper ?? 0.3, stiff = o.stiff ?? 1;
  const g = new THREE.PlaneGeometry(o.width, L, 1, seg); g.translate(0, -L / 2, 0);
  const p = g.attributes.position, s = new Float32Array(p.count);
  for (let i = 0; i < p.count; i++) { const t = -p.getY(i) / L; s[i] = t; p.setX(i, p.getX(i) * (1 - t * taper)); }
  g.setAttribute('aS', new THREE.BufferAttribute(s, 1));
  const uMove = { value: 0 }, uPh = { value: o.ph || 0 };
  const mat = toonMat({ color: o.color, side: THREE.DoubleSide });
  const prev = mat.onBeforeCompile;
  mat.onBeforeCompile = (sh, rr) => {
    prev(sh, rr);
    sh.uniforms.uTime = Shared.time; sh.uniforms.uMove = uMove; sh.uniforms.uPh = uPh;
    sh.vertexShader = 'attribute float aS; uniform float uTime, uMove, uPh;\n' + sh.vertexShader.replace('#include <begin_vertex>', `#include <begin_vertex>
      float cs = aS * aS;
      transformed.z += sin(uTime * 4.2 + uPh - aS * 5.0) * (0.03 + uMove * 0.07) * aS;
      transformed.x += sin(uTime * 3.1 + uPh * 1.7 - aS * 4.0) * 0.022 * aS;
      transformed.z -= cs * (0.05 + uMove * 0.42) * ${stiff.toFixed(2)};
      transformed.y += cs * uMove * 0.15 * ${stiff.toFixed(2)};`);
  };
  mat.customProgramCacheKey = () => 'cloth' + stiff.toFixed(2);
  const m = new THREE.Mesh(g, mat); m.position.set(...o.pos); m.rotation.set(...o.rot); m.castShadow = true;
  parent.add(m);
  return { mesh: m, uMove };
}
function buildPerson(o = {}) {
  const C = Object.assign({ skin: 0xffdcc6, hair: 0x2a2238, top: 0x2c4a8a, shirt: 0xf2f2f6, trim: 0xf4f0e6, bottom: 0x2a2e3e, shoe: 0x6a4026, glove: 0x3a2a20, accent: 0x8b5cff, pack: true }, o);
  if (o.top !== undefined && o.trim === undefined) C.trim = 0xf4ecd8;
  const r = newRig(); r.hopAmp = 0.35; r.olw = 0; r.person = true;
  const key = personKey(C), B = grp(r.body);
  const DB = Object.assign({ jawHinge: [0, 0, 0], tailStart: 0.01, neckStart: 0.95 }, designPersonBody(C));
  const body = new THREE.Mesh(dragonGeometry('pb_' + key, DB, 0.016, 0.026), sculptToonMaterial({ hipY: 0.62, shoulderY: 1.12, sat: 1.05, rimAmt: 0.3, warm: 1 }, DB));
  body.castShadow = true; body.receiveShadow = true; B.add(body);
  sculptOutline(body, 0.013, 0x1a1220);
  const DH = Object.assign({ jawHinge: [0, 0, 0], tailStart: 0.01, neckStart: 0.95 }, designHair(C));
  const hair = new THREE.Mesh(dragonGeometry('ph_' + key, DH, 0.015, 0.024), sculptToonMaterial({ sat: 1.05, rimAmt: 0.25, hairRing: 1.76, warm: 0.55 }, DH));
  hair.castShadow = true; B.add(hair);
  sculptOutline(hair, 0.012, 0x1a1220);
  const U = body.material.userData.U, UH = hair.material.userData.U;
  U.uSway.value = UH.uSway.value = 0.2;
  const face = grp(B, [0, 0, 0]);
  for (const sx of [-1, 1]) {
    const em = animeEye({ iris: C.eye ?? 0x2a2a6a, iris2: C.eye2 ?? 0x7a9aff, skin: C.skin, lash: 0x1a1020, side: sx });
    const g = grp(face, [sx * 0.128, 1.49, 0.302], [0, sx * 0.32, 0]);
    part(GEO.sphere, em, g, [0, 0, 0], [0.072, 0.088, 0.04]);
    (r.blinkU = r.blinkU || []).push(em.userData.blink);
    part(GEO.box, M(C.hair), face, [sx * 0.13, 1.6, 0.318], [0.095, 0.018, 0.02], [0, sx * 0.3, -sx * 0.12]);
  }
  part(new THREE.TorusGeometry(0.03, 0.007, 6, 14, Math.PI), M(0x8a3a3a), face, [0, 1.395, 0.322], 1, [0, 0, Math.PI]);
  for (const sx of [-1, 1]) part(GEO.sphere, M(0xff8fa6, { transparent: true, opacity: 0.42 }), face, [sx * 0.2, 1.43, 0.28], [0.05, 0.026, 0.02], [0, sx * 0.5, 0]).userData.noOl = true;
  // scarf knot with two cloth tails, and coat tails behind the belt: they trail and lift when running
  part(GEO.torusFat, M(C.accent), B, [0, 1.2, 0], [0.18, 0.18, 0.16], [Math.PI / 2, 0, 0]);
  part(GEO.sphere, M(C.accent), B, [0.03, 1.19, -0.17], [0.06, 0.05, 0.045]);
  const cloth = [
    clothRibbon(B, { pos: [0.06, 1.19, -0.18], rot: [0.28, 0.2, 0.1], length: 0.52, width: 0.105, color: C.accent, ph: 0 }),
    clothRibbon(B, { pos: [0.0, 1.19, -0.185], rot: [0.22, -0.18, -0.07], length: 0.4, width: 0.09, color: C.accent, ph: 1.7 }),
  ];
  if (!C.robe) for (const sx of [-1, 1]) cloth.push(clothRibbon(B, { pos: [sx * 0.105, 0.77, -0.2], rot: [0.14, sx * 0.12, sx * 0.07], length: 0.3, width: 0.16, color: C.top, ph: sx * 1.3, stiff: 0.45, taper: 0.1 }));
  if (C.pin) part(GEO.octa, E(C.pin, 2.4), B, [0.27, 1.76, 0.18], [0.05, 0.08, 0.03]);
  if (o.pendant !== false && !C.robe) part(GEO.octa, E(0xb48cff, 2.2), B, [0, 1.06, 0.255], [0.035, 0.055, 0.02]);
  if (C.hat === 'hood') part(GEO.sphere, M(C.accent), B, [0, 1.62, -0.14], [0.44, 0.44, 0.38]).castShadow = true;
  if (C.hat === 'wide') { part(GEO.cyl, M(C.accent), B, [0, 1.92, 0], [0.6, 0.04, 0.6]); part(GEO.cylT, M(C.accent), B, [0, 2.06, 0], [0.25, 0.28, 0.25]); }
  if (C.hat === 'band') part(GEO.torusFat, M(C.accent), B, [0, 1.74, 0], [0.37, 0.37, 0.25], [Math.PI / 2 - 0.15, 0, 0]);
  if (C.staff) { const st = grp(B, [0.38, 0.62, 0.08]); part(GEO.cyl, M(0x5a3b26), st, [0, 0.3, 0], [0.025, 1.6, 0.025]); part(GEO.octa, E(C.staff, 2.6), st, [0, 1.12, 0], [0.09, 0.15, 0.09]); }
  r.fns.push((t, dt, mv) => {
    for (const c of cloth) c.uMove.value = damp(c.uMove.value, mv, 5, dt);
    U.uWalk.value = UH.uWalk.value = r.walkPhase; U.uStride.value = 0.17 * mv;
    face.position.copy(dragonOffset(U, 1, Shared.time.value));
  });
  r.size = 1.95;
  return r;
}
