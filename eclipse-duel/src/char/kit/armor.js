// Parametric plate-armour builders. Each returns geometry (or a named set of geometries) in a bone's zero-pose frame:
// +X forward, +Y up, +Z the fighter's right / camera side. Right-side limb pieces are authored for the R bone and
// mirrored with putPair(). Lengths in metres, angles in degrees. "curve" = number | [[t, value], ...] | fn(t).
//
// Big -> medium -> small: every assembled piece is a main plate with a sculpted silhouette (ridges, flutes, flares),
// secondary plates (lames, wings, rims) and small detail (rivets, inlay strips, buckles) that the design can colour.

import * as THREE from 'three';
import { fnOf } from '../shapes.js';
import { plate, sweep, lathe, extrude, strip, studs, onSurface, merge, circle, rrect, curve, occlude, mk, fixWinding, autoCav } from './geo.js';

const DEG = Math.PI / 180;
const lerp = (a, b, t) => a + (b - a) * t;
const clamp = (x, a, b) => (x < a ? a : x > b ? b : x);
const sstep = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };

/** Superellipse point at angle a (rad; 0 = +X, pi/2 = +Z): [x, z]. */
export function se(a, rx, rz, n = 2) {
  const c = Math.cos(a), s = Math.sin(a), e = 2 / n;
  return [rx * Math.sign(c) * Math.pow(Math.abs(c), e), rz * Math.sign(s) * Math.pow(Math.abs(s), e)];
}

// ---- generic shapes ---------------------------------------------------------------------------------------------------

/**
 * Hoop plate around the local Y axis (cuirass, faulds, rerebraces, vambraces, greaves, helm shells ...).
 * o: y0, y1 (top / bottom at the centre line), a0=-180, a1=180 (deg coverage, 0 = +X front), closed (full hoop)
 *    rx, rz, ox, oz, n=2.2 (curves over v: 0 = y0 edge, 1 = y1 edge)
 *    top(a) / bot(a) -> extra y offset of the y0 / y1 edges (shaped necklines, points, scallops; a in deg)
 *    ridge { at=0, h, w=20 (deg half width), crease=true }  raised ridge (medial ridge, shin ridge)
 *    flutes { n, h, a0, a1 } parallel flutes      bulge(u, v) -> radial m
 *    + plate() options: nu, nv, thick, edge, edgeR, roll, occ, creaseU
 */
export function hoop(o) {
  const closed = o.closed ?? (o.a0 === undefined && o.a1 === undefined);
  const a0 = o.a0 ?? (closed ? -180 : -100), a1 = o.a1 ?? (closed ? 180 : 100);
  const RX = fnOf(o.rx, 0.1), RZ = fnOf(o.rz ?? o.rx, 0.1), OX = fnOf(o.ox, 0), OZ = fnOf(o.oz, 0), NE = fnOf(o.n, 2.2);
  const top = o.top || (() => 0), bot = o.bot || (() => 0);
  const ridges = o.ridges || (o.ridge ? [o.ridge] : []);
  const S = (u, v) => {
    const a = lerp(a0, a1, u), ar = a * DEG;
    const y = lerp(o.y0 + top(a), o.y1 + bot(a), v);
    const rx = RX(v), rz = RZ(v);
    const [x, z] = se(ar, rx, rz, NE(v));
    let k = o.bulge ? o.bulge(u, v) : 0;
    for (const r of ridges) {
      const d = Math.abs(((a - (r.at ?? 0) + 540) % 360) - 180) / (r.w ?? 20);
      const h = typeof r.h === 'function' ? r.h(v) : r.h;
      if (d < 1) k += h * Math.pow(1 - d, r.pow ?? 1.4);
    }
    if (o.flutes) {
      const F = o.flutes, t = (a - F.a0) / (F.a1 - F.a0);
      if (t > 0 && t < 1) k += F.h * Math.pow(Math.abs(Math.sin(t * Math.PI * F.n)), 0.7) * Math.sin(t * Math.PI) * (F.fade ? F.fade(v) : 1);
    }
    const r = Math.hypot(x, z) || 1;
    return [OX(v) + x * (1 + k / r), y, OZ(v) + z * (1 + k / r)];
  };
  const creaseU = [...(o.creaseU || [])];
  for (const r of ridges) if (r.crease !== false) { const u = ((r.at ?? 0) - a0) / (a1 - a0); if (u > 0 && u < 1) creaseU.push(u); }
  return plate(S, { ...o, closeU: closed, creaseU, axis: [0, 0] });
}

/**
 * Plate swept along X around the X axis (pauldron cops and lames, sabaton lames, helm crests).
 * o: x0, x1 (curves over v, back / front ends), al0, al1 (deg, curves over u: 0 = +Y up, 90 = +Z out, 180 = down)
 *    r (curve over v), taper=0.4 (radius loss toward the x ends), cy, cz (centre), ridge { at (deg), h, w },
 *    flare (curve over v: extra radius), + plate() options
 */
export function sweepPlate(o) {
  const X0 = fnOf(o.x0, -0.1), X1 = fnOf(o.x1, 0.1), A0 = fnOf(o.al0, 0), A1 = fnOf(o.al1, 120);
  const R = fnOf(o.r, 0.12), taper = o.taper ?? 0.4, cy = o.cy ?? 0, cz = o.cz ?? 0, xc = o.xc ?? 0;
  const ridges = o.ridges || (o.ridge ? [o.ridge] : []);
  const S = (u, v) => {
    const x = lerp(X0(v), X1(v), u);
    const al = lerp(A0(u), A1(u), v);
    const half = (X1(v) - X0(v)) / 2 || 1, e = (x - (X0(v) + X1(v)) / 2) / half;
    let r = R(v) * (1 - taper * e * e) * (o.dome ? Math.sqrt(Math.max(0.05, 1 - o.dome * e * e)) : 1);
    for (const rd of ridges) {
      const d = Math.abs(al - rd.at) / (rd.w ?? 14);
      if (d < 1) r += (typeof rd.h === 'function' ? rd.h(u) : rd.h) * Math.pow(1 - d, 1.4) * Math.sin(Math.PI * clamp(u, 0, 1)) ** 0.4;
    }
    return [x + xc, cy + r * Math.cos(al * DEG), cz + r * Math.sin(al * DEG)];
  };
  const creaseV = [...(o.creaseV || [])];
  for (const rd of ridges) if (rd.crease !== false) { const v = (rd.at - A0(0.5)) / (A1(0.5) - A0(0.5)); if (v > 0 && v < 1) creaseV.push(v); }
  return plate(S, { ...o, creaseV, out: (p) => [0, p[1] - cy, p[2] - cz] });
}

/**
 * Dome / cop (elbow, knee, rivet boss, pommel cap): lathe of a thick shell around +Y.
 * o: r (rim radius), h (height), thick=0.006, rim=0 (rolled bead radius), segs=20, sx / sz (scale), lip=0 (rim flare)
 */
export function dome(o) {
  const r = o.r ?? 0.06, h = o.h ?? 0.04, t = o.thick ?? 0.006, rim = o.rim ?? 0, lip = o.lip ?? 0;
  const prof = [];
  const K = 6;
  for (let k = 0; k <= K; k++) { const a = (k / K) * (Math.PI / 2); prof.push([r * Math.sin(a) + lip * Math.pow(k / K, 6), h * Math.cos(a)]); }
  const rb = Math.max(rim, t * 0.6);
  const [er, ey] = prof[prof.length - 1];
  for (let k = 1; k <= 4; k++) { const a = (k / 4) * Math.PI; prof.push([er + Math.sin(a) * rb, ey - rb + Math.cos(a) * rb]); }
  for (let k = K; k >= 0; k--) { const a = (k / K) * (Math.PI / 2); prof.push([(r - t) * Math.sin(a) + lip * Math.pow(k / K, 6), (h - t) * Math.cos(a) - rb * 2 * (k / K)]); }
  const g = lathe(prof.map(([x, y]) => [x, y]), { segs: o.segs ?? 20 });
  const C = g.attributes.cav.array, P = g.attributes.position.array;
  for (let i = 0; i < C.length; i++) if (P[i * 3 + 1] < ey - rb * 1.2) C[i] = Math.min(C[i], 0.45);
  if (o.sx || o.sz) g.scale(o.sx ?? 1, 1, o.sz ?? 1);
  return g;
}

/**
 * Fan plate (couter / poleyn wing): a cupped, fluted shell spreading from a hinge, facing +Z.
 * o: r0=0.015, r1=0.07 (inner / outer radius), a0=-70, a1=70 (deg spread, 0 = +X), cup=0.012, flutes=5, fluteH=0.003,
 *    scallop=0.006 (outer edge scallops), thick, roll
 */
export function fan(o = {}) {
  const r0 = o.r0 ?? 0.015, r1 = o.r1 ?? 0.07, a0 = o.a0 ?? -70, a1 = o.a1 ?? 70, cup = o.cup ?? 0.012;
  const nF = o.flutes ?? 5, fh = o.fluteH ?? 0.003, sc = o.scallop ?? 0.006;
  const S = (u, v) => {
    const a = lerp(a0, a1, u) * DEG, t = (u * nF) % 1;
    const rr = lerp(r0, r1 - sc * (1 - Math.cos(t * Math.PI * 2)) * 0.5, v);
    const fl = fh * Math.pow(Math.sin(u * Math.PI * nF), 2) * sstep(0.1, 0.6, v);
    const z = cup * (1 - v * v) + fl;
    return [rr * Math.cos(a), rr * Math.sin(a), z];
  };
  return plate(S, { nu: o.nu ?? nF * 4, nv: o.nv ?? 4, thick: o.thick ?? 0.004, roll: o.roll ?? { v1: 0.0035 }, out: () => [0, 0, 1], curv: 0.003 });
}

// ---- torso ------------------------------------------------------------------------------------------------------------

/**
 * Torso cross-section used by every torso plate: radii as functions of the chest-frame height y.
 * body: { rx: [[y, r]...], rz: [[y, r]...], ox: [[y, x]...] }  (y ascending)
 */
export function torsoShape(body) {
  return { RX: fnOf(body.rx, 0.15), RZ: fnOf(body.rz, 0.19), OX: fnOf(body.ox, 0), n: body.n ?? 2.3 };
}

/**
 * Plate following the torso shape between heights (chest frame). o: { body: torsoShape, yTop, yBot, a0, a1, grow (m),
 * neck { dip, k }, arm { drop, from, to } (top edge drops toward the armholes), point (bottom point at the centre),
 * topPoint (top edge rises at the centre), ridge, flutes, + plate options }
 */
export function torsoPlate(o) {
  const B = o.body, grow = fnOf(o.grow, 0);
  return hoop({
    ...o,
    y0: 0, y1: 1,
    top: (a) => {
      const c = Math.max(0, Math.cos(a * DEG));
      let y = o.yTop;
      if (o.neck) y -= o.neck.dip * Math.pow(c, o.neck.k ?? 5);
      if (o.arm) y -= o.arm.drop * sstep(o.arm.from, o.arm.to, Math.abs(a));
      if (o.topPoint) y += o.topPoint * Math.pow(c, o.topK ?? 8);
      return y;
    },
    bot: (a) => {
      const c = Math.max(0, Math.cos(a * DEG));
      let y = o.yBot - 1;
      if (o.point) y -= o.point * Math.pow(c, o.pointK ?? 6);
      if (o.botBack) y -= o.botBack * Math.pow(Math.max(0, -Math.cos(a * DEG)), 4);
      return y;
    },
    // radii follow the absolute height: evaluate at the plate's centre-line height for this v
    rx: (v) => B.RX(lerp(o.yTop, o.yBot, v)) + grow(v),
    rz: (v) => B.RZ(lerp(o.yTop, o.yBot, v)) + grow(v),
    ox: (v) => B.OX(lerp(o.yTop, o.yBot, v)),
    n: o.n ?? B.n,
  });
}

/**
 * Breastplate with a medial ridge, pigeon-breast swell and armhole cuts (plate geometry; userData.S / normalAt).
 * o: body, yTop=0.21, yBot=-0.12, a0=-104, a1=104, ridgeH=0.012, swell=0.012, neck dip, arm drop, thick=0.007, roll
 */
export function breastplate(o) {
  const { ridgeH = 0.012, swell = 0.012, ...rest } = o;
  return torsoPlate({
    a0: -104, a1: 104, nu: 28, nv: 12, thick: 0.007, edgeR: 0.005,
    neck: { dip: 0.055, k: 6 }, arm: { drop: 0.085, from: 55, to: 95 },
    ridge: { at: 0, h: (v) => ridgeH * (0.4 + 0.6 * Math.sin(Math.PI * clamp(v * 1.1, 0, 1))), w: 26 },
    bulge: (u, v) => swell * Math.sin(Math.PI * clamp(v * 1.4, 0, 1)) * Math.pow(Math.cos((u - 0.5) * Math.PI * 1.1), 2),
    roll: { v0: 0.0065 },
    ...rest,
  });
}

/** Plackart: belly plate over the lower breastplate, pointed top (ember rune sits in the point). */
export function plackart(o) {
  return torsoPlate({
    a0: -88, a1: 88, nu: 24, nv: 6, thick: 0.007, edgeR: 0.0045, grow: 0.011,
    topPoint: 0.1, topK: 7, ridge: { at: 0, h: 0.008, w: 22 },
    roll: { v0: 0.005 },
    occ: (u, v) => 1 - 0.25 * sstep(0.75, 1, v),
    ...o,
  });
}

/** Backplate (a around 180). */
export function backplate(o) {
  return torsoPlate({
    a0: 98, a1: 262, nu: 20, nv: 10, thick: 0.007, edgeR: 0.0045,
    neck: undefined, arm: undefined,
    ridges: [{ at: 180, h: 0.006, w: 14 }],
    roll: { v0: 0.0055 },
    ...o,
  });
}

/**
 * Faulds: overlapping hooped lames below the waist (each lower lame wider). Returns [geometry...] top -> bottom.
 * o: body (hips-frame shape or explicit radii), y0 (top), lame=0.06 (height), overlap=0.014, count=3, a0, a1,
 *    grow per lame, point (centre point of the bottom edge), rx, rz (base radii at the top) + flare per lame
 */
export function faulds(o) {
  const out = [];
  const n = o.count ?? 3, H = o.lame ?? 0.06, ov = o.overlap ?? 0.014;
  for (let k = 0; k < n; k++) {
    const y0 = o.y0 - k * (H - ov), y1 = y0 - H;
    const g = o.grow ?? 0.008;
    out.push(hoop({
      y0, y1, a0: o.a0 ?? -150, a1: o.a1 ?? 150, closed: o.a0 === undefined && o.a1 === undefined ? false : undefined,
      rx: [[0, o.rx + g * k], [1, o.rx + g * k + (o.flare ?? 0.008)]],
      rz: [[0, o.rz + g * k], [1, o.rz + g * k + (o.flare ?? 0.008)]],
      ox: o.ox ?? 0, n: o.n ?? 2.3, nu: o.nu ?? 26, nv: 2, thick: 0.006, edgeR: 0.004,
      bot: (a) => -(o.point ?? 0) * Math.pow(Math.max(0, Math.cos(a * DEG)), 6) * (k === n - 1 ? 1 : 0.4),
      roll: { v1: o.roll ?? 0.0045 },
      occ: (u, v) => 0.62 + 0.38 * sstep(0.1, 0.55, v),
    }));
  }
  return out;
}

/**
 * Tasset (thigh guard hanging from the faulds), authored on a tasset bone at the top of the plate.
 * o: count=3 lames, w=0.15 (width), h=0.085 per lame, r=0.15 (curvature radius), cx=-0.06 (curve centre x), cut (taper)
 */
export function tasset(o = {}) {
  const out = [];
  const n = o.count ?? 3, H = o.h ?? 0.085, ov = o.overlap ?? 0.018, r = o.r ?? 0.15;
  for (let k = 0; k < n; k++) {
    const y0 = -k * (H - ov), last = k === n - 1;
    out.push(hoop({
      y0, y1: y0 - H, a0: o.a0 ?? -34, a1: o.a1 ?? 62,
      rx: r + k * 0.005, rz: r + k * 0.005, ox: o.cx ?? -0.075, oz: o.cz ?? -0.01, n: 2,
      bot: (a) => (last ? -(o.point ?? 0.03) * Math.pow(Math.cos(((a - 14) / 48) * Math.PI * 0.5), 2) : -0.006 * Math.cos(((a - 14) / 48) * Math.PI * 0.5)),
      nu: 12, nv: 2, thick: 0.006, edgeR: 0.0045, roll: { v1: 0.0042 },
      ridge: { at: 14, h: 0.004, w: 16 },
      occ: (u, v) => 0.6 + 0.4 * sstep(0.15, 0.6, v),
    }));
  }
  return out;
}

/** Gorget: 2-3 hooped lames flaring from the neck to the collar (author in the neck frame). */
export function gorget(o = {}) {
  const out = [];
  const n = o.count ?? 3, rTop = o.rTop ?? 0.075, rBot = o.rBot ?? 0.15, y0 = o.y0 ?? 0.065, y1 = o.y1 ?? -0.08;
  for (let k = 0; k < n; k++) {
    const t0 = k / n, t1 = (k + 1) / n + 0.08;
    const ya = lerp(y0, y1, t0), yb = lerp(y0, y1, Math.min(1, t1));
    const ra = lerp(rTop, rBot, Math.pow(t0, 1.6)), rb = lerp(rTop, rBot, Math.pow(Math.min(1, t1), 1.6));
    out.push(hoop({
      y0: ya, y1: yb, closed: true, rx: [[0, ra * 0.95 + k * 0.003], [1, rb * 0.95 + k * 0.003]], rz: [[0, ra + k * 0.003], [1, rb + k * 0.003]],
      ox: 0.004, n: 2.1, nu: 28, nv: 2, thick: 0.006, edgeR: 0.004, roll: { v1: k === n - 1 ? 0.006 : 0.0035 },
      bot: (a) => -(o.point ?? 0.02) * Math.pow(Math.max(0, Math.cos(a * DEG)), 4) * (k === n - 1 ? 1 : 0.3) - 0.012 * Math.pow(Math.max(0, -Math.cos(a * DEG)), 3),
      occ: (u, v) => 0.62 + 0.38 * sstep(0.05, 0.5, v),
    }));
  }
  return out;
}

// ---- shoulders & arms ---------------------------------------------------------------------------------------------------

/**
 * Pauldron (deltoid frame of the R side; origin = shoulder joint). Cop = spherical cap over the shoulder (axis tilted
 * outward, elongated front-back, closed by a boss at the apex), optional flared over-plate (heavy side), lames wrapping
 * the outside of the arm (hoops around the arm's Y axis, open toward the body), optional standing haute-piece.
 * o: R=0.115 (cap radius), cy=0.012, cz=-0.008 (cap centre), tilt=32 (deg outward), elong=1.18 (front-back), cover=74
 *    (deg, cap rim), lames=3, lameH=0.052, lameStep=0.04, flare=0 (over-plate flare, m), haute=0 (height), nu, nv
 * Returns { cop, boss, over, lames: [...], haute, rivets, copS }
 */
export function pauldron(o = {}) {
  const R = o.R ?? 0.115, cy = o.cy ?? 0.012, cz = o.cz ?? -0.008;
  const tilt = (o.tilt ?? 32) * DEG, ex = o.elong ?? 1.18, th0 = 0.09, th1 = (o.cover ?? 74) * DEG;
  const out = { lames: [] };
  // cap frame: axis d = up tilted outward (+Z), e1 = +X (front), e2 = d x e1
  const d = [0, Math.cos(tilt), Math.sin(tilt)], e1 = [1, 0, 0], e2 = [0, d[2], -d[1]];
  const cap = (Rf, phiA, phiB, thA, thB, flare = 0, drop = 0) => (u, v) => {
    const ph = lerp(phiA, phiB, u) * DEG, th = lerp(thA, thB, v);
    // neck side (e2 negative = toward -Z?) sits lower and tighter; outer side drops further (drop)
    const side = Math.sin(ph);                          // +1 outward-down side, -1 neck side
    const r = Rf + flare * v * v * Math.max(0, 0.4 + 0.6 * side);
    const thx = th * (1 + drop * Math.max(0, side) * v);
    const s = Math.sin(thx) * r, c = Math.cos(thx) * r;
    const a = Math.cos(ph) * s * ex, b = side * s;
    return [a * e1[0] + b * e2[0] + c * d[0], cy + a * e1[1] + b * e2[1] + c * d[1], cz + a * e1[2] + b * e2[2] + c * d[2]];
  };
  out.cop = plate(cap(R, -180, 180, th0, th1, 0, 0.12), {
    closeU: true, nu: o.nu ?? 24, nv: o.nv ?? 9, thick: 0.008, edgeR: 0.006, roll: { v1: 0.0065 }, edge: { v0: 'none' },
    out: (p) => [p[0], p[1] - cy, p[2] - cz], creaseU: o.ridgeH === 0 ? [] : [],
  });
  // apex boss closing the cap
  const boss = dome({ r: R * Math.sin(th0) + 0.012, h: 0.014, thick: 0.004, rim: 0.003, segs: 12 });
  const q = new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(0, 1, 0), new THREE.Vector3(...d));
  boss.applyQuaternion(q);
  boss.translate(d[0] * R * Math.cos(th0) * 0.985, cy + d[1] * R * Math.cos(th0) * 0.985, cz + d[2] * R * Math.cos(th0) * 0.985);
  out.boss = boss;
  if (o.flare) {
    // over-plate: wing over the outer half, flaring out over the lames
    out.over = plate(cap(R + 0.014, -150, 150, 0.32, th1 + 0.12, o.flare, 0.18), {
      nu: o.nu ?? 22, nv: 7, thick: 0.008, edgeR: 0.0065, roll: { v1: 0.0075, v0: 0.005 }, inner: true,
      out: (p) => [p[0], p[1] - cy, p[2] - cz],
      occ: (u, v) => 0.8 + 0.2 * sstep(0.0, 0.3, v),
    });
  }
  // lames: hoops around the arm, open toward the body (a ~ 270 = -Z), stepping down and out
  const nL = o.lames ?? 3, LH = o.lameH ?? 0.052, LS = o.lameStep ?? 0.04;
  for (let k = 0; k < nL; k++) {
    const y0 = -0.03 - k * LS, rr = R * 0.7 + 0.005 * k + (o.flare ? 0.008 : 0);
    out.lames.push(hoop({
      y0, y1: y0 - LH, a0: -70, a1: 250,
      rx: [[0, rr * 0.94], [1, rr * 0.97 + 0.004]], rz: [[0, rr], [1, rr + 0.007]], ox: -0.002, oz: 0.008 + 0.002 * k, n: 2.1,
      bot: (a) => -0.012 * Math.pow(Math.max(0, Math.sin(a * DEG)), 2),
      nu: 18, nv: 2, thick: 0.006, edgeR: 0.0045, roll: { v1: 0.0045 },
      occ: (u, v) => 0.58 + 0.42 * sstep(0.15, 0.6, v),
    }));
  }
  // haute-piece: standing neck guard rising from the cap's neck-side rim, flaring outward at the top
  if (o.haute) {
    const H = o.haute, base = cap(R, -180, 180, th0, th1, 0, 0.12);
    out.haute = plate((u, v) => {
      const p = base(lerp(0.62, 0.88, u), 0.72);
      const e = 2 * u - 1, hgt = H * Math.pow(Math.max(0, 1 - e * e), 0.45) * (1 - 0.2 * e);
      return [p[0], p[1] + v * hgt, p[2] - 0.01 + 0.022 * v * v];
    }, { nu: 14, nv: 4, thick: 0.007, edgeR: 0.0055, roll: { v1: 0.0065 }, out: () => [0, 0, -1], edge: { v0: 'none' } });
  }
  const ruv = [];
  for (let i = 0; i < 9; i++) ruv.push([o.flare ? 0.12 + i * 0.095 : i / 9, 0.86]);
  out.rivets = studs(onSurface((out.over || out.cop).userData, ruv, -0.001), { r: 0.0068, h: 0.0042 });
  out.copS = out.cop.userData;
  return out;
}

/** Rerebrace (upper arm tube, author on upperArmTwist): closed tube with a turned bottom rim. */
export function rerebrace(o = {}) {
  return hoop({
    y0: o.y0 ?? -0.06, y1: o.y1 ?? -0.2, closed: true,
    rx: [[0, (o.r ?? 0.062) * 1.02], [1, (o.r ?? 0.062) * 0.94]], rz: [[0, (o.r ?? 0.062) * 1.06], [1, (o.r ?? 0.062) * 0.97]],
    oz: 0.004, n: 2.1, nu: 22, nv: 3, thick: 0.006, edgeR: 0.004, roll: { v1: 0.0045 },
    ridge: { at: 90, h: 0.004, w: 18 },
    bot: (a) => -0.012 * Math.pow(Math.max(0, Math.sin(a * DEG)), 2),
  });
}

/** Couter (elbow frame): cop + fan wing on the outside + two articulation lames. Returns { cop, wing, lames } */
export function couter(o = {}) {
  const r = o.r ?? 0.062;
  const cop = dome({ r, h: r * 0.9, thick: 0.006, rim: 0.0045, segs: 16, lip: 0.004 });
  cop.rotateZ(90 * DEG); // dome axis +Y -> -X (point of the elbow toward the back)
  cop.translate(-0.004, 0, 0);
  const wing = fan({ r0: 0.01, r1: o.wing ?? 0.072, a0: -75, a1: 80, cup: 0.014, flutes: 5, fluteH: 0.0032, scallop: 0.006 });
  wing.translate(-0.012, 0, r * 0.62);
  const lames = [];
  for (const [y0, y1] of [[0.065, 0.028], [-0.03, -0.068]]) {
    lames.push(hoop({ y0, y1, closed: true, rx: r * 0.98, rz: r, n: 2.1, nu: 18, nv: 1, thick: 0.005, edgeR: 0.0035 }));
  }
  return { cop, wing, lames };
}

/** Vambrace (forearm twist frame): tapered tube, outer ridge, flared cuff at the wrist. */
export function vambrace(o = {}) {
  const r = o.r ?? 0.055;
  return hoop({
    y0: o.y0 ?? 0.12, y1: o.y1 ?? -0.11, closed: true,
    rx: [[0, r * 0.98], [0.35, r * 1.02], [0.85, r * 0.84], [1, r * 0.9]],
    rz: [[0, r * 1.04], [0.35, r * 1.08], [0.85, r * 0.88], [1, r * 0.95]],
    n: 2.15, nu: 22, nv: 6, thick: 0.006, edgeR: 0.0045, roll: { v0: 0.005 },
    ridge: { at: 90, h: 0.007, w: 22 },
    top: (a) => 0.018 * Math.pow(Math.max(0, Math.sin(a * DEG)), 2),
  });
}

/**
 * Articulated gauntlet (hand / fingers / fingerTips / thumb frames of the R side). Returns
 * { cuff, back, knuckle, palm, fingers, tips, thumb, rivets } — fingers / tips are on the finger bones.
 */
export function gauntlet(o = {}) {
  const out = {};
  out.cuff = hoop({
    y0: 0.035, y1: -0.045, closed: true, rx: [[0, 0.046], [1, 0.064]], rz: [[0, 0.05], [1, 0.07]], n: 2.1,
    nu: 18, nv: 2, thick: 0.005, edgeR: 0.004, roll: { v1: 0.005 },
    bot: (a) => -0.03 * Math.pow(Math.max(0, Math.sin(a * DEG)), 3),
  });
  // back of the hand (faces +Z for the R hand), two overlapping metacarpal plates
  out.back = merge([0, 1].map((k) => hoop({
    y0: -0.03 - k * 0.032, y1: -0.07 - k * 0.032, a0: 10, a1: 170, rx: 0.048, rz: 0.034 + k * 0.002, oz: -0.006, n: 2.3,
    nu: 10, nv: 2, thick: 0.004, edgeR: 0.003, ridge: { at: 90, h: 0.003, w: 30 },
    occ: (u, v) => 0.65 + 0.35 * sstep(0.1, 0.6, v),
  })));
  out.palm = hoop({ y0: -0.035, y1: -0.098, a0: 190, a1: 350, rx: 0.044, rz: 0.03, oz: -0.004, n: 2.3, nu: 8, nv: 2, thick: 0.004, edgeR: 0.003, edgeSegs: 2 });
  // finger plates: 4 fingers laid along X; each segment two small overlapping lames
  const fingers = [], tips = [];
  for (let f = 0; f < 4; f++) {
    const x = 0.027 - f * 0.018, w = f === 3 ? 0.0082 : 0.0094;
    for (let s = 0; s < 2; s++) {
      const y0 = 0.006 - s * 0.024, y1 = y0 - 0.03;
      fingers.push(hoop({ y0, y1, closed: true, rx: w, rz: 0.0108 - s * 0.0006, ox: x, n: 2.4, nu: 6, nv: 1, thick: 0.0025, edgeR: 0.002, edgeSegs: 2 }));
    }
    tips.push(hoop({ y0: 0.004, y1: -0.04 + f * 0.002, closed: true, rx: [[0, w], [0.8, w * 0.85], [1, w * 0.45]], rz: [[0, 0.0098], [0.8, 0.009], [1, 0.005]], ox: x, n: 2.4, nu: 6, nv: 2, thick: 0.0025, edgeR: 0.002, edgeSegs: 2, edge: { v1: 'none' } }));
  }
  out.fingers = merge(fingers);
  out.tips = merge(tips);
  out.thumb = sweep(curve([[0, 0.004, 0], [0.012, -0.03, -0.006], [0.019, -0.06, -0.012]], 5), rrect(1, 1, 0.45, 1),
    { scale: (t) => [0.0125 - t * 0.004, 0.011 - t * 0.003], hard: [], caps: true });
  const ruv = [[0.25, 0.5], [0.75, 0.5]];
  out.rivets = studs(onSurface(out.cuff.userData, ruv), { r: 0.004, h: 0.003 });
  return out;
}

// ---- legs -----------------------------------------------------------------------------------------------------------------

/** Cuisse (thigh frame): open shell over front and outside of the thigh with a ridge. */
export function cuisse(o = {}) {
  const r = o.r ?? 0.105;
  return hoop({
    y0: o.y0 ?? -0.03, y1: o.y1 ?? -0.39, a0: -112, a1: 128,
    rx: [[0, r * 1.02], [0.5, r * 0.94], [1, r * 0.8]], rz: [[0, r * 1.04], [0.5, r * 0.95], [1, r * 0.8]], ox: 0.006, n: 2.15,
    nu: 22, nv: 7, thick: 0.007, edgeR: 0.005, roll: { v0: 0.0055 },
    ridge: { at: 8, h: 0.008, w: 20 },
    top: (a) => 0.03 * Math.pow(Math.max(0, Math.sin(a * DEG)), 2) - 0.02 * Math.pow(Math.max(0, Math.cos(a * DEG)), 2),
  });
}

/** Poleyn (knee frame): cop + side wing + articulation lames. Returns { cop, wing, lames } */
export function poleyn(o = {}) {
  const r = o.r ?? 0.074;
  const cop = dome({ r, h: r * 0.82, thick: 0.007, rim: 0.005, segs: 16, lip: 0.005 });
  cop.rotateZ(-90 * DEG); // axis +Y -> +X (front of the knee)
  cop.translate(0.02, 0, 0);
  const wing = fan({ r0: 0.012, r1: o.wing ?? 0.085, a0: -80, a1: 80, cup: 0.016, flutes: 5, fluteH: 0.0034, scallop: 0.007 });
  wing.translate(-0.005, 0, r * 0.66);
  const lames = [];
  for (const [y0, y1, k] of [[0.08, 0.035, 1], [-0.03, -0.075, -1]]) {
    lames.push(hoop({ y0, y1, a0: -115, a1: 125, rx: r * 1.12, rz: r * 1.06, ox: 0.008, n: 2.1, nu: 16, nv: 1, thick: 0.006, edgeR: 0.0045 }));
  }
  return { cop, wing, lames };
}

/** Greave (shin frame): closed tube, calf swell, shin ridge, flared ankle. */
export function greave(o = {}) {
  const r = o.r ?? 0.068;
  return hoop({
    y0: o.y0 ?? -0.06, y1: o.y1 ?? -0.405, closed: true,
    rx: [[0, r], [0.28, r * 1.08], [0.75, r * 0.84], [1, r * 0.88]],
    rz: [[0, r * 0.96], [0.28, r * 1.02], [0.75, r * 0.8], [1, r * 0.84]],
    ox: [[0, -0.004], [0.3, -0.012], [1, 0.002]],
    bulge: (u, v) => 0.012 * Math.pow(Math.max(0, -Math.cos((u * 360 - 180) * DEG)), 2) * Math.sin(Math.PI * clamp(v * 1.3, 0, 1)),
    n: 2.1, nu: 24, nv: 8, thick: 0.006, edgeR: 0.0045, roll: { v0: 0.005 },
    ridge: { at: 0, h: 0.009, w: 22 },
    bot: (a) => 0.012 * Math.pow(Math.max(0, Math.cos(a * DEG)), 2),
  });
}

/** Sabaton (foot / toe frames): overlapping lames along the foot + pointed toe cap. Returns { lames, toe, sole } */
export function sabaton(o = {}) {
  const lames = [];
  for (let k = 0; k < 4; k++) {
    const x0 = -0.01 + k * 0.034, r = 0.072 - k * 0.008;
    lames.push(sweepPlate({
      x0, x1: x0 + 0.046, al0: -95, al1: 95, r: [[0, r], [1, r]], taper: 0, cy: -0.05, cz: 0,
      nu: 2, nv: 8, thick: 0.005, edgeR: 0.0035,
      occ: (u) => 0.65 + 0.35 * sstep(0.1, 0.6, u),
    }));
  }
  const toe = sweepPlate({
    x0: -0.012, x1: 0.1, al0: -96, al1: 96, r: [[0, 0.05], [1, 0.05]], taper: 0, cy: -0.026, cz: 0,
    nu: 6, nv: 10, thick: 0.005, edgeR: 0.0035,
  });
  // taper the toe to a blunt point
  {
    const P = toe.attributes.position.array;
    for (let i = 0; i < P.length; i += 3) {
      const t = clamp((P[i] + 0.012) / 0.112, 0, 1), k = 1 - 0.72 * Math.pow(t, 1.6);
      P[i + 1] = -0.026 + (P[i + 1] + 0.026) * k - 0.012 * t * t; P[i + 2] *= k;
    }
    toe.computeVertexNormals();
    autoCav(toe);
  }
  return { lames, toe };
}

// ---- belts, straps, buckles, rivets ----------------------------------------------------------------------------------------

/** Belt band around an ellipse (rx, rz at height y, centre ox): rounded rectangle section. */
export function belt(o) {
  const pts = [];
  const n = o.segs ?? 40;
  for (let i = 0; i < n; i++) { const a = (i / n) * Math.PI * 2; pts.push([(o.ox ?? 0) + Math.cos(a) * o.rx, o.y + (o.tilt ?? 0) * Math.cos(a), Math.sin(a) * o.rz]); }
  return sweep(pts, rrect(o.t ?? 0.006, (o.h ?? 0.026) / 2, 0.0025, 1), { closed: true, up: [0, 1, 0] });
}

/** Strap along a path (thin leather band, `w` wide, `t` thick). up: hint for the band's flat normal. */
export function strap(path, o = {}) {
  return sweep(o.smooth === false ? path : curve(path, o.n ?? 16), rrect(o.t ?? 0.0025, (o.w ?? 0.022) / 2, 0.001, 1), { up: o.up || [1, 0, 0], caps: true });
}

/** Buckle: rectangular frame + prong, lying in the XY plane facing +Z (size w x h). */
export function buckle(o = {}) {
  const w = o.w ?? 0.034, h = o.h ?? 0.04, r = o.r ?? 0.0032;
  const frame = [[-w / 2, -h / 2, 0], [w / 2, -h / 2, 0], [w / 2, h / 2, 0], [-w / 2, h / 2, 0]];
  const ring = sweep(curve(frame, 28, true), circle(6), { scale: r, closed: true, up: [0, 0, 1] });
  const bar = sweep([[0, -h / 2, 0], [0, h / 2, 0]], circle(6), { scale: r * 0.8 });
  const plateG = extrude([[-w / 2 - 0.004, -h / 2 - 0.004], [w / 2 + 0.004, -h / 2 - 0.004], [w / 2 + 0.004, h / 2 + 0.004], [-w / 2 - 0.004, h / 2 + 0.004]], { depth: 0.002, bevel: 0.001, bevelSegs: 1 });
  plateG.translate(0, 0, -0.003);
  return merge([ring, bar, plateG]);
}

/** Rivet row on a plate geometry at (u, v) positions. */
export function rivets(plateGeo, uvs, o = {}) { return studs(onSurface(plateGeo.userData, uvs, o.inset ?? -0.0008), o); }

// ---- engraving / runes ---------------------------------------------------------------------------------------------------

/**
 * Original angular glyph alphabet (unit box, strokes [[x0,y0],[x1,y1],...]). Used for glowing inlays.
 */
export const GLYPHS = [
  [[[0.5, 0], [0.5, 1]], [[0.5, 0.65], [0.15, 0.95]], [[0.5, 0.35], [0.85, 0.05]]],
  [[[0.2, 0], [0.5, 1], [0.8, 0]], [[0.32, 0.4], [0.68, 0.4]]],
  [[[0.2, 1], [0.8, 0.5], [0.2, 0]], [[0.5, 0.65], [0.5, 0.35]]],
  [[[0.5, 0], [0.5, 1]], [[0.15, 0.7], [0.5, 0.45], [0.85, 0.7]]],
  [[[0.2, 0], [0.2, 1], [0.8, 0.75], [0.2, 0.5]], [[0.2, 0.5], [0.8, 0]]],
  [[[0.5, 1], [0.15, 0.5], [0.5, 0], [0.85, 0.5], [0.5, 1]], [[0.5, 0.3], [0.5, 0.7]]],
  [[[0.15, 1], [0.85, 0]], [[0.85, 1], [0.5, 0.5]], [[0.15, 0.25], [0.4, 0.25]]],
  [[[0.5, 0], [0.5, 1]], [[0.2, 0.8], [0.8, 0.8]], [[0.2, 0.2], [0.8, 0.2]]],
];

/**
 * Rune band on a plate surface: glyph strokes laid out in a (u, v) box. Returns one strip geometry.
 * o: u0, u1, v0, v1 (box in the surface parameters), glyphs [indices] (default cycles), width (m), gap (fraction)
 */
export function runes(plateGeo, o) {
  const S = plateGeo.userData, list = o.glyphs || [0, 3, 5, 1, 6, 2, 7, 4];
  const n = list.length, gap = o.gap ?? 0.25, out = [];
  const cw = (o.u1 - o.u0) / n;
  list.forEach((gi, k) => {
    const gl = GLYPHS[gi % GLYPHS.length];
    const ub = o.u0 + k * cw + cw * gap * 0.5, ue = ub + cw * (1 - gap);
    for (const stroke of gl) {
      const uv = stroke.map(([x, y]) => [lerp(ub, ue, x), lerp(o.v1, o.v0, y)]);
      out.push(strip(S, uv, { width: o.width ?? 0.003, lift: o.lift ?? 0.0006, bead: 0.0004, smooth: 3 }));
    }
  });
  return merge(out);
}

/** A flowing inlay line on a plate surface: uv control points -> smooth strip. */
export function inlayLine(plateGeo, uvPts, o = {}) {
  const pts = curve(uvPts.map(([u, v]) => [u, v, 0]), o.n ?? 24).map((p) => [p[0], p[1]]);
  return strip(plateGeo.userData, pts, { width: o.width ?? 0.004, lift: o.lift ?? 0.0007, bead: o.bead ?? 0.0005, smooth: 2 });
}

// ---- helms ------------------------------------------------------------------------------------------------------------------

/**
 * Great helm (head frame): tall ogival crown, brow band, recessed glowing visor slit, prow-ridged face plate with
 * breaths, back plate, forged crest. Returns named geometries:
 * { crown, brow, face, back, slit (dark recess), eye (glow strip), crest, breaths, rivets, skirt }
 * o: rx=0.128, rz=0.112 (max half depth / width), top=0.29 (crown apex y), bottom=-0.07, slitY=0.075 (centre), slitH=0.016,
 *    crest=true (fin), crestH=0.05, prow=0.022 (face ridge height), flare=0.016 (skirt flare)
 */
export function greatHelm(o = {}) {
  const rx = o.rx ?? 0.128, rz = o.rz ?? 0.112, top = o.top ?? 0.29, bottom = o.bottom ?? -0.07;
  const sy = o.slitY ?? 0.075, sh = o.slitH ?? 0.016, prow = o.prow ?? 0.022, flare = o.flare ?? 0.016;
  const ox = o.ox ?? 0.018;
  // radius profile over absolute height (head frame): widest around the cheekbones, ogival above the brow
  const RX = (y) => {
    if (y > 0.13) { const t = (y - 0.13) / (top - 0.13); return rx * Math.pow(Math.max(0, 1 - Math.pow(t, 2.6)), 0.5) * (1 - 0.06 * t); }
    const t = (0.13 - y) / (0.13 - bottom);
    return rx * (1 - 0.07 * t * t) + flare * Math.pow(t, 4);
  };
  const RZ = (y) => {
    if (y > 0.13) { const t = (y - 0.13) / (top - 0.13); return rz * Math.pow(Math.max(0, 1 - Math.pow(t, 2.4)), 0.5); }
    const t = (0.13 - y) / (0.13 - bottom);
    return rz * (1 - 0.05 * t * t) + flare * 0.8 * Math.pow(t, 4);
  };
  const N = (y) => (y > 0.13 ? 2.2 : y > sy ? 2.0 : 1.62);
  const ridgeK = (a, h) => h * Math.pow(Math.max(0, 1 - Math.abs(a) / 18), 1.5);
  const P = (a, y, grow = 0, ridge = 0) => {
    const ar = a * DEG;
    const [x, z] = se(ar, Math.max(1e-4, RX(y) + grow), Math.max(1e-4, RZ(y) + grow), N(y));
    const rr = Math.hypot(x, z) || 1, k = (ridgeK(((a + 540) % 360) - 180, ridge)) / rr;
    return [ox * (y > 0.13 ? 1 - (y - 0.13) / (top - 0.13) * 0.5 : 1) + x * (1 + k), y, z * (1 + k)];
  };
  const out = {};
  // crown: full hoop from just below the brow to near the apex, front-back ridge
  const yc0 = sy + sh * 0.5 + 0.026;
  out.crown = plate((u, v) => {
    const a = lerp(-180, 180, u), y = lerp(yc0, top - 0.004, Math.pow(v, 0.85));
    return P(a, y, 0, (o.crestRidge ?? 0.008) * (1 - v * 0.3));
  }, { closeU: true, nu: 32, nv: 10, thick: 0.008, edge: { v1: 'none' }, creaseU: [0.5], axis: [ox, 0] });
  // brow band: overlaps the crown's lower edge, thicker, wraps the front to the temples
  out.brow = plate((u, v) => {
    const a = lerp(-118, 118, u), y = lerp(yc0 + 0.012, sy + sh * 0.5 + 0.002, v);
    const p = P(a, y, 0.005 + 0.005 * v * v, prow * 0.3);
    p[1] += 0.008 * Math.pow(Math.max(0, Math.cos(a * DEG)), 6) * (1 - v);
    return p;
  }, { nu: 28, nv: 3, thick: 0.008, edgeR: 0.0055, roll: { v1: 0.0055 }, creaseU: [0.5], axis: [ox, 0] });
  // face plate: below the slit, prow ridge (crease), flares into the skirt
  const yf0 = sy - sh * 0.5 - 0.002;
  out.face = plate((u, v) => {
    const a = lerp(-112, 112, u), y = lerp(yf0, bottom, v);
    const p = P(a, y, 0.004, prow * (0.6 + 0.4 * Math.sin(Math.PI * clamp(v * 0.9 + 0.1, 0, 1))));
    return p;
  }, { nu: 28, nv: 9, thick: 0.008, edgeR: 0.005, roll: { v1: 0.006 }, creaseU: [0.5], axis: [ox, 0] });
  // back plate: from the slit height down to the nape, behind the face plate edges
  out.back = plate((u, v) => {
    const a = lerp(100, 260, u), y = lerp(yc0 + 0.004, bottom - 0.012, v);
    return P(a, y, 0.0015, 0.004);
  }, { nu: 16, nv: 8, thick: 0.007, edgeR: 0.0045, roll: { v1: 0.0055 }, creaseU: [0.5], axis: [ox, 0] });
  // slit recess: dark inner shell behind the opening
  out.slit = plate((u, v) => {
    const a = lerp(-104, 104, u), y = lerp(sy + sh * 0.9, sy - sh * 0.9, v);
    return P(a, y, -0.011, 0);
  }, { nu: 20, nv: 1, thick: 0, axis: [ox, 0] });
  // eye glow: a thin strip deeper in the slit (glowing), with a vertical breath slot below the centre
  out.eye = plate((u, v) => {
    const a = lerp(-62, 62, u), y = lerp(sy + sh * 0.22, sy - sh * 0.22, v);
    return P(a, y, -0.0085, 0);
  }, { nu: 16, nv: 1, thick: 0, axis: [ox, 0] });
  // breaths: dark round holes (inset discs with a lip) in a flame-shaped cluster on both cheeks
  const br = [];
  const fS = out.face.userData;
  const hole = lathe([[0.0, -0.0015], [0.0032, -0.0015], [0.0034, 0.0003], [0.0046, 0.0004], [0.0048, 0.0]], { segs: 8, hard: [1] });
  const cluster = [[0, 0], [1, 0], [2, 0], [0.5, 1], [1.5, 1], [2.5, 1], [1, 2], [2, 2], [1.5, 3], [2.5, 3]];
  for (const side of [1, -1]) for (const [cx, cy] of cluster) {
    const u = 0.5 + side * (0.16 + cx * 0.042), v = 0.24 + cy * 0.115;
    const f = fS.normalAt(u, v);
    const g = hole.clone();
    g.applyMatrix4(new THREE.Matrix4().compose(f.p.clone().addScaledVector(f.n, 0.0006), new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(0, 1, 0), f.n), new THREE.Vector3(1, 1, 1)));
    br.push(g);
  }
  out.breaths = merge(br);
  // crest: forged comb from the brow over the crown to the nape, notched like a row of flames leaning back
  if (o.crest !== false) {
    const H = o.crestH ?? 0.05, teeth = o.teeth ?? 6, th = o.crestT ?? 0.0045;
    const mid = [];
    for (let i = 0; i <= 10; i++) mid.push(P(0, lerp(yc0 + 0.03, top - 0.003, i / 10), 0, 0));
    for (let i = 9; i >= 0; i--) mid.push(P(180, lerp(0.1, top - 0.003, i / 10), 0, 0));
    const path = curve(mid, 64);
    const prof = (t) => {
      const env = Math.pow(Math.sin(Math.PI * Math.min(1, 0.12 + t * 0.95)), 0.6) * (1 - 0.3 * t);
      const saw = (t * teeth) % 1;
      const h = H * env * (0.55 + 0.45 * Math.pow(saw, 1.6)) + 0.004;
      return [[-0.004, -th], [h * 0.82, -th * 0.55], [h, 0], [h * 0.82, th * 0.55], [-0.004, th]];
    };
    out.crest = sweep(path, prof, { up: [1, 0.2, 0], hard: [1, 2, 3], caps: true, cavScale: 0.003 });
  }
  // rivets: along the brow band and the crown seam
  const ruv = [];
  for (let i = 0; i <= 10; i++) ruv.push([0.06 + i * 0.088, 0.5]);
  out.rivets = studs(onSurface(out.brow.userData, ruv), { r: 0.0055, h: 0.0035 });
  out.S = { crown: out.crown.userData, brow: out.brow.userData, face: out.face.userData, back: out.back.userData };
  return out;
}

/**
 * Storm helm (head frame): rounded close helm, visor with three slits, swept horns and feathered wings.
 * Returns { skull, visor, slits, horns, wings, rivets }
 */
export function stormHelm(o = {}) {
  const r = o.r ?? 0.118;
  const out = {};
  out.skull = hoop({
    y0: 0.27, y1: -0.04, closed: true,
    rx: [[0, 0.02], [0.08, r * 0.62], [0.3, r * 1.0], [0.6, r * 1.02], [1, r * 0.92]],
    rz: [[0, 0.02], [0.08, r * 0.58], [0.3, r * 0.92], [0.6, r * 0.93], [1, r * 0.86]],
    ox: 0.012, n: 2.1, nu: 36, nv: 16, thick: 0.007, edge: { v0: 'none' }, roll: { v1: 0.005 },
    ridge: { at: 0, h: 0.01, w: 16 },
  });
  out.visor = hoop({
    y0: 0.12, y1: -0.05, a0: -100, a1: 100,
    rx: [[0, r * 1.06], [0.5, r * 1.1], [1, r * 0.98]], rz: [[0, r * 0.98], [1, r * 0.92]], ox: 0.016, n: 2.0,
    nu: 30, nv: 10, thick: 0.007, edgeR: 0.005, roll: { v0: 0.005 }, ridge: { at: 0, h: 0.026, w: 30 },
    bot: (a) => -0.02 * Math.pow(Math.max(0, Math.cos(a * DEG)), 4),
  });
  const sl = [];
  for (let k = 0; k < 3; k++) {
    const y = 0.085 - k * 0.022, w = 0.06 - k * 0.012;
    const pts = [];
    for (let i = 0; i <= 10; i++) { const a = lerp(-w, w, i / 10) / (r * 1.1); const [x, z] = se(a, r * 1.1 + 0.016, r * 0.98, 2); pts.push([x + 0.017, y, z]); }
    sl.push(sweep(pts, rrect(0.004, 0.003, 0.001, 1), { up: [1, 0, 0] }));
  }
  out.slits = merge(sl);
  // horns: tapered, slightly twisted sweeps from the temples, back and up
  const horn = (s) => sweep(curve([[0.02, 0.17, s * 0.1], [-0.02, 0.24, s * 0.16], [-0.1, 0.3, s * 0.2], [-0.2, 0.32, s * 0.21], [-0.27, 0.36, s * 0.18]], 22),
    circle(10), { scale: (t) => [0.024 * Math.pow(1 - t, 0.9) + 0.0012, 0.019 * Math.pow(1 - t, 0.9) + 0.001], twist: (t) => t * 0.8, up: [0, 0, s] });
  out.horns = merge([horn(1), horn(-1)]);
  // wings: three feather blades on each side, fanned back
  const feathers = [];
  for (const s of [1, -1]) for (let k = 0; k < 3; k++) {
    const L = 0.16 - k * 0.03;
    const shape = [[0, -0.012], [L * 0.7, -0.016], [L, 0], [L * 0.75, 0.01], [0, 0.012]];
    const g = extrude(shape, { depth: 0.004, bevel: 0.0015, bevelSegs: 1 });
    g.rotateZ((150 - k * 22) * DEG);
    g.rotateX(s * 75 * DEG);
    g.translate(-0.04 - k * 0.008, 0.13 - k * 0.012, s * (r * 0.92));
    feathers.push(g);
  }
  out.wings = merge(feathers);
  out.rivets = studs(onSurface(out.visor.userData, [[0.1, 0.15], [0.9, 0.15], [0.1, 0.75], [0.9, 0.75]]), { r: 0.006, h: 0.004 });
  return out;
}

/**
 * Hooded half-mask with circlet (head frame): cloth hood shell (open face, drapes to the shoulders), a sculpted mask
 * over the lower face, a thin circlet with a central star mount. Returns { hood, mask, circlet, gem }
 * The hood carries cloth uvw (u around, v down) so the cloth set can be used (static, not simulated).
 */
export function hoodedMask(o = {}) {
  const r = o.r ?? 0.125;
  const out = {};
  // hood: shell around the head, face opening at the front, peak at the top-front, drapes past the neck
  const hood = plate((u, v) => {
    const a = lerp(-128, 128, u) + 180;               // opening faces +X
    const y = lerp(0.3, -0.2, v);
    const cr = r * (v < 0.25 ? 0.75 + v : 1.0 + (v - 0.25) * 0.45) * (1 + 0.05 * Math.sin(u * Math.PI * 9) * v);
    const [x, z] = se(a * DEG, cr * 1.05, cr, 2);
    const peak = 0.035 * Math.pow(Math.max(0, 1 - v * 4), 2);
    return [x - 0.015 + peak, y + 0.02 * Math.cos(u * Math.PI * 2) * (1 - v), z];
  }, { nu: 32, nv: 14, thick: 0.006, edgeR: 0.004, axis: [-0.015, 0] });
  const n = hood.attributes.position.count, uvw = new Float32Array(n * 3);
  const Pp = hood.attributes.position.array;
  for (let i = 0; i < n; i++) { uvw[i * 3] = 0.5 + Math.atan2(Pp[i * 3 + 2], -Pp[i * 3]) / (Math.PI * 2); uvw[i * 3 + 1] = clamp((0.3 - Pp[i * 3 + 1]) / 0.5, 0, 1); uvw[i * 3 + 2] = 0; }
  hood.setAttribute('uvw', new THREE.BufferAttribute(uvw, 3));
  out.hood = hood;
  out.mask = hoop({
    y0: 0.07, y1: -0.05, a0: -78, a1: 78, rx: [[0, r * 0.98], [1, r * 0.86]], rz: [[0, r * 0.86], [1, r * 0.76]], ox: 0.02, n: 2.0,
    nu: 26, nv: 8, thick: 0.004, edgeR: 0.003, ridge: { at: 0, h: 0.016, w: 26 },
    top: (a) => -0.02 * Math.pow(Math.max(0, Math.cos(a * DEG)), 8) + 0.012 * Math.pow(Math.abs(Math.sin(a * DEG)), 2),
    bot: (a) => -0.025 * Math.pow(Math.max(0, Math.cos(a * DEG)), 3),
  });
  const cpts = [];
  for (let i = 0; i < 40; i++) { const a = (i / 40) * Math.PI * 2; const [x, z] = se(a, r * 0.96, r * 0.86, 2.1); cpts.push([x + 0.012, 0.14 + 0.012 * Math.cos(a), z]); }
  out.circlet = sweep(cpts, rrect(0.0022, 0.005, 0.0012, 1), { closed: true, up: [0, 1, 0] });
  // star mount: 8-point star extrusion facing +X at the brow
  const star = [];
  for (let k = 0; k < 16; k++) { const a = (k / 16) * Math.PI * 2, rr = k % 2 ? 0.006 : 0.016; star.push([Math.cos(a) * rr, Math.sin(a) * rr]); }
  const gem = extrude(star, { depth: 0.004, bevel: 0.0015, bevelSegs: 1 });
  gem.rotateY(90 * DEG);
  gem.translate(r * 0.96 + 0.016, 0.155, 0);
  out.gem = gem;
  return out;
}

/** Fur cards with uvw (u across, v root -> tip) for the fur set: a ring of overlapping tufts. */
export function furRing(o) {
  // o: center [x,y,z], rx, rz, a0, a1 (deg), count, len, droop, layers=2, width
  const out = [];
  const n = o.count ?? 24, layers = o.layers ?? 2;
  for (let L = 0; L < layers; L++) for (let k = 0; k < n; k++) {
    const t = (k + 0.5 * L) / n, a = lerp(o.a0 ?? -180, o.a1 ?? 180, t) * DEG;
    const [x, z] = se(a, o.rx, o.rz, 2);
    const base = new THREE.Vector3(o.center[0] + x, o.center[1] + (o.lift ?? 0) * L, o.center[2] + z);
    const outD = new THREE.Vector3(Math.cos(a), 0, Math.sin(a)).normalize();
    const len = (o.len ?? 0.09) * (0.8 + 0.4 * Math.abs(Math.sin(k * 12.9898 + L * 4.1))) * (1 - 0.12 * L);
    const w = (o.width ?? 0.06) * (1 + 0.2 * L);
    const tan = new THREE.Vector3(-Math.sin(a), 0, Math.cos(a));
    const rows = 4, cols = 3, pos = [], nor = [], idx = [], uvw = [];
    for (let j = 0; j <= rows; j++) {
      const v = j / rows;
      const c = base.clone().addScaledVector(outD, len * v * (0.65 + 0.15 * L)).add(new THREE.Vector3(0, -(o.droop ?? 0.6) * len * v * v - 0.01 * v, 0));
      for (let i = 0; i <= cols; i++) {
        const u = i / cols;
        const p = c.clone().addScaledVector(tan, (u - 0.5) * w * (1 - 0.35 * v)).addScaledVector(outD, 0.008 * Math.sin(u * Math.PI));
        pos.push(p.x, p.y, p.z);
        const nn = outD.clone().multiplyScalar(0.35).add(new THREE.Vector3(0, 1, 0)).normalize();
        nor.push(nn.x, nn.y, nn.z);
        uvw.push(((k * 0.37 + L * 0.5) % 1) * 0.6 + u * 0.4, v, 0);
      }
    }
    for (let j = 0; j < rows; j++) for (let i = 0; i < cols; i++) { const a0 = j * (cols + 1) + i, b = a0 + 1, d = a0 + cols + 1, c = d + 1; idx.push(a0, d, b, b, d, c); }
    const g = mk(pos, nor, idx, new Float32Array(pos.length / 3).fill(1), uvw);
    out.push(fixWinding(g));
  }
  return merge(out);
}

export { occlude };
