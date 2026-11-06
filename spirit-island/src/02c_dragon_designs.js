// ============================================================================
//  dragon designs: signed-distance blueprints for the six legendary dragons
//  (pure data → primitives; materials and wings are added in 02d_dragons.js)
// ============================================================================
const hexRGB = (h) => [((h >> 16) & 255) / 255, ((h >> 8) & 255) / 255, (h & 255) / 255];
const mirrorX = (p) => [-p[0], p[1], p[2]];

// Western dragon: four legs, two wings, long neck and tail. Faces +z, stands on y = 0.
function designWestern(o) {
  const C = Object.assign({ body: 0x333333, belly: 0x555555, horn: 0xdddddd, spike: 0x999999, claw: 0x222222, glowHorn: 0 }, o.colors || {});
  const col = (h) => hexRGB(h);
  const bulk = o.bulk || 1, neck = o.neck || 1, tail = o.tail || 1;
  const prims = [];
  const P = (p) => prims.push(p);
  // ---- spine (tail tip → head base)
  const ctrl = [
    [0, 0.42, -3.5 - 2.2 * tail], [0.18, 0.56, -3.0 - 1.6 * tail], [0.12, 0.88, -2.75 - 0.7 * tail], [0, 1.25, -2.3],
    [0, 1.55, -1.3], [0, 1.72, -0.25], [0, 1.88, 0.7], [0, 2.3, 1.32], [0, 2.78 + 0.25 * (neck - 1), 1.74 + 0.2 * (neck - 1)], [0, 3.02 + 0.4 * (neck - 1), 2.18 + 0.3 * (neck - 1)],
  ];
  const rad = [0.05, 0.12, 0.23, 0.37, 0.6, 0.64, 0.62, 0.48, 0.37, 0.31].map((r, i) => (i >= 3 && i <= 6 ? r * bulk : r));
  const sp = spinePath(ctrl, rad, 4);
  for (let i = 0; i < sp.length - 1; i++) {
    const a = sp[i], b = sp[i + 1];
    P(SDF.rc(a.p, b.p, a.r, b.r, { k: 0.08, s0: a.s, s1: b.s, col: col(C.body), belly: 1 }));
  }
  const sAt = (z) => { let best = sp[0]; for (const q of sp) if (Math.abs(q.p[2] - z) < Math.abs(best.p[2] - z) && q.p[1] < 2.4) best = q; return best; };
  // ---- torso masses
  const sChest = sAt(0.75).s, sBelly = sAt(-0.3).s, sHip = sAt(-1.25).s;
  P(SDF.el([0, 1.72, 0.55], [0.56 * bulk, 0.66 * bulk, 0.82], { k: 0.32, s0: sChest, s1: sChest, col: col(C.body), belly: 1 }));
  P(SDF.el([0, 1.56, -0.45], [0.52 * bulk, 0.56 * bulk, 0.86], { k: 0.3, s0: sBelly, s1: sBelly, col: col(C.body), belly: 1 }));
  P(SDF.el([0, 1.55, -1.25], [0.46 * bulk, 0.48 * bulk, 0.55], { k: 0.25, s0: sHip, s1: sHip, col: col(C.body), belly: 1 }));
  for (const sx of [-1, 1]) {
    P(SDF.el([sx * 0.38 * bulk, 1.98, 0.82], [0.27, 0.32, 0.38], { k: 0.2, s0: sChest, s1: sChest, col: col(C.body) }));
    P(SDF.el([sx * 0.38 * bulk, 1.45, -1.2], [0.3, 0.4, 0.42], { k: 0.22, s0: sHip, s1: sHip, col: col(C.body) }));
  }
  // ---- head
  const hs = o.headScale || 1.28;
  const hb = ctrl[ctrl.length - 1], H = (x, y, z) => [x * hs, hb[1] + y * hs, hb[2] + z * hs];
  const sH = 1;
  const head = { col: col(C.body), s0: sH, s1: sH };
  P(SDF.el(H(0, 0.08, 0.27), [0.25 * hs, 0.2 * hs, 0.38 * hs], Object.assign({ k: 0.12 }, head)));
  P(SDF.rc(H(0, 0.04, 0.4), H(0, -0.06, 1.2), 0.18 * hs, 0.095 * hs, Object.assign({ k: 0.12 }, head)));
  P(SDF.el(H(0, -0.03, 1.15), [0.11 * hs, 0.075 * hs, 0.11 * hs], Object.assign({ k: 0.06 }, head)));
  for (const sx of [-1, 1]) P(SDF.el(H(sx * 0.07, 0.02, 1.16), [0.04 * hs, 0.035 * hs, 0.05 * hs], Object.assign({ k: 0.03 }, head)));
  P(SDF.rc(H(0, -0.16, 0.3), H(0, -0.22, 1.12), 0.13 * hs, 0.065 * hs, { k: 0.06, s0: sH, s1: sH, col: col(C.belly), jaw: 1 }));
  for (const sx of [-1, 1]) {
    P(SDF.el(H(sx * 0.19, 0.0, 0.36), [0.085 * hs, 0.08 * hs, 0.17 * hs], Object.assign({ k: 0.07 }, head)));
    P(SDF.rc(H(sx * 0.09, 0.2, 0.66), H(sx * 0.22, 0.28, 0.2), 0.06 * hs, 0.05 * hs, Object.assign({ k: 0.05 }, head)));
    P(SDF.el(H(sx * 0.16, 0.12, 0.52), [0.05 * hs, 0.04 * hs, 0.06 * hs], { k: 0.035, sub: true }));
    P(SDF.el(H(sx * 0.07, 0.04, 1.24), [0.025 * hs, 0.02 * hs, 0.03 * hs], { k: 0.02, sub: true }));
    // cheek frills and chin spikes
    P(SDF.rc(H(sx * 0.22, 0.02, 0.26), H(sx * 0.44, 0.08, -0.02), 0.05, 0.004, { k: 0.04, s0: sH, s1: sH, col: col(C.spike) }));
    P(SDF.rc(H(sx * 0.2, -0.08, 0.12), H(sx * 0.4, -0.12, -0.12), 0.04, 0.003, { k: 0.04, s0: sH, s1: sH, col: col(C.spike) }));
    P(SDF.rc(H(sx * 0.1, -0.28, 0.42), H(sx * 0.16, -0.42, 0.24), 0.035, 0.003, { k: 0.03, s0: sH, s1: sH, col: col(C.spike), jaw: 1 }));
  }
  // ---- horns
  const hornCol = col(C.horn), hg = C.glowHorn;
  const ridged = o.horns !== 'crystal';
  const hornChain = (pts, r0, r1, k = 0.04) => {
    const n = pts.length;
    for (let i = 0; i < n - 1; i++) {
      const ra = (r0 + (r1 - r0) * (i / (n - 1))) * hs, rb = (r0 + (r1 - r0) * ((i + 1) / (n - 1))) * hs;
      P(SDF.rc(pts[i], pts[i + 1], ra, rb, { k: i === 0 ? 0.06 : k, s0: sH, s1: sH, col: hornCol, glow: hg * ((i + 1) / (n - 1)) }));
      if (ridged && ra > 0.04) {
        const a = pts[i], b = pts[i + 1], d = [b[0] - a[0], b[1] - a[1], b[2] - a[2]], L = Math.hypot(d[0], d[1], d[2]);
        for (const t of [0.2, 0.45, 0.7]) {
          const p0 = [a[0] + d[0] * t, a[1] + d[1] * t, a[2] + d[2] * t], rr = (ra + (rb - ra) * t);
          const e = [d[0] / L * 0.018, d[1] / L * 0.018, d[2] / L * 0.018];
          P(SDF.rc([p0[0] - e[0], p0[1] - e[1], p0[2] - e[2]], [p0[0] + e[0], p0[1] + e[1], p0[2] + e[2]], rr * 1.16, rr * 1.12, { k: 0.012, s0: sH, s1: sH, col: hornCol, glow: hg * ((i + t) / (n - 1)) }));
        }
      }
    }
  };
  for (const sx of [-1, 1]) {
    if (o.horns === 'crown') {
      hornChain([H(sx * 0.13, 0.28, 0.2), H(sx * 0.2, 0.62, 0.08), H(sx * 0.28, 0.9, -0.15), H(sx * 0.3, 1.05, -0.45)], 0.085, 0.006);
      hornChain([H(sx * 0.22, 0.2, 0.08), H(sx * 0.42, 0.36, -0.12), H(sx * 0.6, 0.42, -0.4)], 0.06, 0.005);
      hornChain([H(sx * 0.25, 0.08, 0.0), H(sx * 0.48, 0.1, -0.2), H(sx * 0.62, 0.04, -0.42)], 0.045, 0.004);
    } else if (o.horns === 'crystal') {
      hornChain([H(sx * 0.12, 0.26, 0.18), H(sx * 0.25, 0.75, -0.15), H(sx * 0.33, 1.08, -0.42)], 0.07, 0.0, 0.02);
      hornChain([H(sx * 0.22, 0.14, 0.05), H(sx * 0.45, 0.42, -0.2)], 0.045, 0.0, 0.02);
    } else {
      hornChain([H(sx * 0.13, 0.26, 0.2), H(sx * 0.22, 0.48, -0.05), H(sx * 0.3, 0.58, -0.4), H(sx * 0.33, 0.52, -0.78)], 0.085, 0.007);
      hornChain([H(sx * 0.22, 0.12, 0.1), H(sx * 0.4, 0.16, -0.12), H(sx * 0.5, 0.08, -0.38)], 0.05, 0.005);
    }
  }
  if (o.horns === 'crown') hornChain([H(0, 0.3, 0.12), H(0, 0.55, -0.05), H(0, 0.68, -0.3)], 0.05, 0.004);
  const IV = col(0xf2ead4);
  for (const sx of [-1, 1]) {
    P(SDF.rc(H(sx * 0.1, -0.08, 0.98), H(sx * 0.105, -0.2, 1.0), 0.026 * hs, 0.003, { k: 0.01, s0: sH, s1: sH, col: IV }));
    P(SDF.rc(H(sx * 0.12, -0.08, 0.74), H(sx * 0.125, -0.17, 0.75), 0.02 * hs, 0.003, { k: 0.01, s0: sH, s1: sH, col: IV }));
    P(SDF.rc(H(sx * 0.07, -0.17, 0.9), H(sx * 0.075, -0.07, 0.92), 0.02 * hs, 0.003, { k: 0.01, s0: sH, s1: sH, col: IV, jaw: 1 }));
    P(SDF.rc(H(sx * 0.17, 0.22, 0.6), H(sx * 0.25, 0.25, 0.3), 0.045 * hs, 0.03 * hs, Object.assign({ k: 0.03 }, head)));
  }
  // ---- musculature
  for (const sx of [-1, 1]) {
    for (const t of [0.35, 0.65]) {
      const a = ctrl[7], b = ctrl[9], p0 = [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
      P(SDF.el([sx * 0.15, p0[1] - 0.05, p0[2] - 0.02], [0.13, 0.24, 0.17], { k: 0.14, s0: 0.8 + t * 0.15, s1: 0.8 + t * 0.15, col: col(C.body), belly: 0.6 }));
    }
    P(SDF.el([sx * 0.26 * bulk, 1.52, 1.02], [0.26, 0.24, 0.2], { k: 0.15, s0: sChest, s1: sChest, col: col(C.body), belly: 1 }));
    for (let i = 0; i < 5; i++) P(SDF.el([sx * 0.5 * bulk, 1.62 - i * 0.02, 0.32 - i * 0.24], [0.07, 0.3, 0.065], { k: 0.11, s0: sBelly, s1: sBelly, col: col(C.body) }));
  }
  // ---- legs
  const leg = (pts, radii, sLeg) => { for (let i = 0; i < pts.length - 1; i++) P(SDF.rc(pts[i], pts[i + 1], radii[i], radii[i + 1], { k: i === 0 ? 0.16 : 0.07, s0: sLeg, s1: sLeg, col: col(C.body) })); };
  const claws = (base, fw, sLeg) => { for (let c = -1; c <= 1; c++) P(SDF.rc([base[0] + c * 0.09, base[1] + 0.02, base[2]], [base[0] + c * 0.12, 0.012, base[2] + fw * 1.25], 0.055, 0.004, { k: 0.025, s0: sLeg, s1: sLeg, col: col(C.claw) })); };
  for (const sx of [-1, 1]) {
    const fx = sx * 0.5 * bulk;
    leg([[fx, 1.75, 0.82], [fx * 1.2, 1.05, 0.66], [fx * 1.24, 0.36, 0.98], [fx * 1.27, 0.12, 1.18]], [0.27, 0.17, 0.12, 0.11], sChest);
    P(SDF.el([fx * 1.12, 1.35, 0.78], [0.2, 0.3, 0.22], { k: 0.12, s0: sChest, s1: sChest, col: col(C.body) }));
    P(SDF.el([fx * 1.23, 0.74, 0.8], [0.12, 0.22, 0.13], { k: 0.1, s0: sChest, s1: sChest, col: col(C.body) }));
    claws([fx * 1.27, 0.1, 1.24], 0.2, sChest);
    const hx = sx * 0.46 * bulk;
    leg([[hx, 1.45, -1.15], [hx * 1.32, 0.95, -0.7], [hx * 1.32, 0.42, -1.25], [hx * 1.34, 0.12, -0.96]], [0.36, 0.19, 0.12, 0.11], sHip);
    P(SDF.el([hx * 1.18, 1.18, -0.95], [0.26, 0.4, 0.36], { k: 0.14, s0: sHip, s1: sHip, col: col(C.body) }));
    P(SDF.el([hx * 1.31, 0.66, -1.02], [0.12, 0.2, 0.15], { k: 0.1, s0: sHip, s1: sHip, col: col(C.body) }));
    claws([hx * 1.34, 0.1, -0.9], 0.2, sHip);
  }
  // ---- dorsal spikes along the spine (neck → tail tip)
  if (o.spikes !== false) {
    for (let i = 3; i < sp.length - 4; i += 2) {
      const q = sp[i]; if (q.p[2] > 1.9) continue;
      const hgt = (0.13 + 0.34 * Math.min(1, q.r / 0.5)) * (o.spikeScale || 1);
      P(SDF.rc([q.p[0], q.p[1] + q.r * 0.8, q.p[2]], [q.p[0], q.p[1] + q.r * 0.8 + hgt, q.p[2] - hgt * 0.75], q.r * 0.22 + 0.025, 0.003, { k: 0.04, s0: q.s, s1: q.s, col: col(C.spike), glow: o.spikeGlow || 0 }));
      if (q.s > 0.55) for (const sx of [-1, 1]) P(SDF.rc([q.p[0] + sx * q.r * 0.45, q.p[1] + q.r * 0.65, q.p[2]], [q.p[0] + sx * (q.r * 0.45 + hgt * 0.35), q.p[1] + q.r * 0.65 + hgt * 0.55, q.p[2] - hgt * 0.6], q.r * 0.13 + 0.015, 0.003, { k: 0.03, s0: q.s, s1: q.s, col: col(C.spike), glow: (o.spikeGlow || 0) * 0.6 }));
    }
  }
  // ---- tail blade
  if (o.tailBlade) {
    const t0 = ctrl[0];
    P(SDF.el([t0[0], t0[1], t0[2] - 0.25], [0.32, 0.035, 0.36], { k: 0.05, s0: 0, s1: 0, col: col(C.spike), glow: o.spikeGlow || 0 }));
    for (const sx of [-1, 1]) P(SDF.rc([t0[0], t0[1], t0[2] - 0.05], [t0[0] + sx * 0.42, t0[1] + 0.02, t0[2] + 0.22], 0.04, 0.003, { k: 0.03, s0: 0, s1: 0, col: col(C.spike), glow: o.spikeGlow || 0 }));
  }
  const bounds = [-1.5, -0.05, ctrl[0][2] - 0.8, 1.5, hb[1] + 1.6 * hs, hb[2] + 1.6 * hs];
  return {
    prims, bounds, kind: 'western',
    eyes: [-1, 1].map((sx) => H(sx * 0.158, 0.118, 0.525)), eyeR: 0.045 * hs,
    wingRoot: [0.34 * bulk, 2.1, 0.78], chest: [0, 1.72, 1.32], head: H(0, 0.1, 0.5), mouth: H(0, -0.12, 1.15), jawHinge: H(0, -0.12, 0.25),
    sHead: sH, sChest, tailStart: sp.find((q) => q.p[2] > -2.3).s, neckStart: sAt(1.4).s, height: hb[1] + 1.1, length: hb[2] + 1.2 - ctrl[0][2],
  };
}

// Eastern dragon / sea serpent: long sinuous body; optional short legs, antlers or fins.
function designEastern(o) {
  const C = Object.assign({ body: 0xaa2233, belly: 0xf0c060, horn: 0xf2c35a, spike: 0xff8844, claw: 0xf2c35a }, o.colors || {});
  const col = (h) => hexRGB(h);
  const prims = [], P = (p) => prims.push(p);
  const L = o.length || 13;
  const ctrl = [];
  const N = 12;
  for (let i = 0; i < N; i++) {
    const u = i / (N - 1);
    ctrl.push([Math.sin(u * Math.PI * 1.6 + 0.4) * 0.9 * (1 - u * 0.4), 1.25 + Math.sin(u * Math.PI) * 0.5 + u * u * 1.0, -L * 0.72 + u * L * 0.93]);
  }
  const R = o.radius || 0.36;
  const rad = ctrl.map((_, i) => { const u = i / (N - 1); return Math.max(0.035, R * Math.min(1, (u + 0.04) * 2.6) * (u > 0.9 ? 0.92 : 1)); });
  const sp = spinePath(ctrl, rad, 4);
  for (let i = 0; i < sp.length - 1; i++) {
    const a = sp[i], b = sp[i + 1];
    P(SDF.rc(a.p, b.p, a.r, b.r, { k: 0.06, s0: a.s, s1: b.s, col: col(C.body), belly: 1 }));
  }
  const hb = ctrl[N - 1], H = (x, y, z) => [x + hb[0], hb[1] + y, hb[2] + z];
  const sH = 1, head = { col: col(C.body), s0: sH, s1: sH };
  if (o.head === 'whale') {
    P(SDF.el(H(0, 0.06, 0.55), [0.5, 0.42, 0.78], Object.assign({ k: 0.15 }, head)));
    P(SDF.rc(H(0, 0.02, 0.6), H(0, -0.06, 1.42), 0.4, 0.22, Object.assign({ k: 0.15 }, head)));
    P(SDF.rc(H(0, -0.24, 0.45), H(0, -0.3, 1.36), 0.26, 0.13, { k: 0.06, s0: sH, s1: sH, col: col(C.belly), jaw: 1 }));
    for (const sx of [-1, 1]) {
      P(SDF.rc(H(sx * 0.3, 0.28, 0.75), H(sx * 0.45, 0.32, 0.25), 0.07, 0.04, Object.assign({ k: 0.05 }, head)));
      for (let k = 0; k < 4; k++) P(SDF.rc(H(sx * 0.42, 0.05 - k * 0.05, 0.25 - k * 0.04), H(sx * (0.85 + k * 0.05), 0.12 - k * 0.12, -0.15 - k * 0.1), 0.05, 0.006, { k: 0.04, s0: sH, s1: sH, col: col(C.spike), glow: (o.ridgeGlow || 0) * 0.7 }));
      for (const z of [1.05, 0.85]) P(SDF.rc(H(sx * 0.18, -0.12, z), H(sx * 0.19, -0.26, z + 0.02), 0.035, 0.004, { k: 0.01, s0: sH, s1: sH, col: hexRGB(0xdff4ff) }));
    }
    for (const sx of [-1, 1]) for (let k = 0; k < 3; k++) P(SDF.el(H(sx * (0.33 - k * 0.02), 0.12 - k * 0.07, 0.95 - k * 0.2), [0.05, 0.045, 0.05], { k: 0.03, sub: true }));
  } else {
    P(SDF.el(H(0, 0.1, 0.3), [0.3, 0.27, 0.42], Object.assign({ k: 0.12 }, head)));
    P(SDF.rc(H(0, 0.05, 0.45), H(0, -0.02, 1.2), 0.22, 0.13, Object.assign({ k: 0.12 }, head)));
    P(SDF.el(H(0, 0.02, 1.17), [0.15, 0.1, 0.12], Object.assign({ k: 0.07 }, head)));
    P(SDF.rc(H(0, -0.17, 0.35), H(0, -0.2, 1.1), 0.15, 0.08, { k: 0.06, s0: sH, s1: sH, col: col(C.belly), jaw: 1 }));
    for (const sx of [-1, 1]) {
      P(SDF.rc(H(sx * 0.12, 0.27, 0.62), H(sx * 0.25, 0.3, 0.3), 0.07, 0.05, Object.assign({ k: 0.05 }, head)));
      P(SDF.el(H(sx * 0.17, 0.16, 0.62), [0.055, 0.05, 0.055], { k: 0.035, sub: true }));
      P(SDF.el(H(sx * 0.07, 0.04, 1.27), [0.03, 0.025, 0.03], { k: 0.02, sub: true }));
      P(SDF.rc(H(sx * 0.2, -0.05, 0.25), H(sx * 0.42, -0.25, -0.1), 0.05, 0.004, { k: 0.04, s0: sH, s1: sH, col: col(C.spike) }));
    }
  }
  // antlers (dawn dragon) or crest fins (abyss)
  if (o.antlers) {
    for (const sx of [-1, 1]) {
      const base = H(sx * 0.15, 0.3, 0.12), mid = H(sx * 0.3, 0.75, -0.2), top = H(sx * 0.38, 1.1, -0.55);
      P(SDF.rc(base, mid, 0.06, 0.045, { k: 0.05, s0: sH, s1: sH, col: col(C.horn) }));
      P(SDF.rc(mid, top, 0.045, 0.012, { k: 0.03, s0: sH, s1: sH, col: col(C.horn) }));
      P(SDF.rc(mid, H(sx * 0.6, 0.95, -0.05), 0.035, 0.008, { k: 0.03, s0: sH, s1: sH, col: col(C.horn) }));
      P(SDF.rc(H(sx * 0.33, 0.95, -0.38), H(sx * 0.2, 1.25, -0.4), 0.03, 0.006, { k: 0.02, s0: sH, s1: sH, col: col(C.horn) }));
    }
  }
  // dorsal sail and lateral fins (sea dragon)
  if (o.sail) {
    for (let i = 5; i < sp.length - 4; i++) {
      const q = sp[i], h = 0.26 * Math.min(1, q.r / 0.4) * (0.6 + 0.4 * Math.sin(q.s * Math.PI));
      P(SDF.el([q.p[0], q.p[1] + q.r * 0.85 + h * 0.75, q.p[2]], [0.03, h, 0.17], { k: 0.04, s0: q.s, s1: q.s, col: col(C.spike), glow: (o.ridgeGlow || 0) * 0.5 }));
      if (i % 4 === 0 && q.s > 0.12 && q.s < 0.85) for (const sx of [-1, 1]) P(SDF.el([q.p[0] + sx * (q.r + 0.16), q.p[1] - q.r * 0.15, q.p[2]], [0.22, 0.034, 0.15], { k: 0.05, s0: q.s, s1: q.s, col: col(C.spike), glow: (o.ridgeGlow || 0) * 0.45 }));
    }
  }
  // dorsal ridge
  for (let i = 4; i < sp.length - 3; i += 2) {
    if (o.sail) break;
    const q = sp[i], hgt = (o.ridge || 0.16) * Math.min(1, q.r / 0.3);
    P(SDF.rc([q.p[0], q.p[1] + q.r * 0.8, q.p[2]], [q.p[0], q.p[1] + q.r * 0.8 + hgt, q.p[2] - hgt * 0.8], q.r * 0.14 + 0.015, 0.003, { k: 0.035, s0: q.s, s1: q.s, col: col(C.spike), glow: o.ridgeGlow || 0 }));
  }
  // short legs
  if (o.legs) {
    for (const u of [0.78, 0.42]) {
      const q = sp[Math.round(u * (sp.length - 1))];
      for (const sx of [-1, 1]) {
        const a = [q.p[0] + sx * q.r * 0.7, q.p[1] - q.r * 0.2, q.p[2]], b = [a[0] + sx * 0.28, a[1] - 0.35, a[2] + 0.1], c = [b[0] + sx * 0.05, b[1] - 0.3, b[2] + 0.18];
        P(SDF.rc(a, b, 0.1, 0.075, { k: 0.08, s0: q.s, s1: q.s, col: col(C.body) }));
        P(SDF.rc(b, c, 0.075, 0.06, { k: 0.05, s0: q.s, s1: q.s, col: col(C.body) }));
        for (let k = -1; k <= 1; k++) P(SDF.rc([c[0] + k * 0.05, c[1], c[2]], [c[0] + k * 0.07, c[1] - 0.06, c[2] + 0.14], 0.025, 0.003, { k: 0.02, s0: q.s, s1: q.s, col: col(C.claw) }));
      }
    }
  }
  // tail tuft / fluke
  const t0 = ctrl[0];
  if (o.fluke) for (const sx of [-1, 1]) P(SDF.el([t0[0] + sx * 0.35, t0[1], t0[2] - 0.1], [0.42, 0.035, 0.22], { k: 0.04, s0: 0, s1: 0, col: col(C.spike), glow: o.ridgeGlow || 0 }));
  let bx0 = 1e9, by0 = 1e9, bz0 = 1e9, bx1 = -1e9, by1 = -1e9, bz1 = -1e9;
  for (const q of sp) { bx0 = Math.min(bx0, q.p[0]); bx1 = Math.max(bx1, q.p[0]); by0 = Math.min(by0, q.p[1]); by1 = Math.max(by1, q.p[1]); bz0 = Math.min(bz0, q.p[2]); bz1 = Math.max(bz1, q.p[2]); }
  const bounds = [bx0 - 1.0, Math.max(-0.1, by0 - 1.0), bz0 - 0.7, bx1 + 1.0, by1 + 1.5, bz1 + 1.55];
  const eyes = o.head === 'whale' ? [] : [-1, 1].map((sx) => H(sx * 0.168, 0.158, 0.625));
  return {
    prims, bounds, kind: 'eastern', spine: sp,
    eyes, eyeRows: o.head === 'whale' ? [-1, 1].flatMap((sx) => [0, 1, 2].map((k) => H(sx * (0.33 - k * 0.02), 0.12 - k * 0.07, 0.95 - k * 0.2))) : [],
    head: H(0, 0.1, 0.6), mouth: H(0, -0.1, 1.15), jawHinge: H(0, -0.15, 0.35), whiskerRoots: [-1, 1].map((sx) => H(sx * 0.12, -0.02, 1.15)),
    sHead: sH, tailStart: 0.55, neckStart: 0.9, height: by1 + 1.2, length: bz1 - bz0 + 2,
  };
}
