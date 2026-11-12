// KAEL's own kit pieces (composed from the shared kit, src/char/kit): forged flame fins for the helm crest and the
// right pauldron, a lighter helm detail set (rivets, breaths) that pays for them, all in bone zero-pose frames
// (+X forward, +Y up, +Z the fighter's right / camera side).
//
//   flameOutline(segments)        smooth flame edge with sharp tips / notches -> { at(t), sharp: [t...] }
//   forgedFin(base, top, o)       double-faced forged plate between a root curve and a flame edge: swollen beaded edge,
//                                 hard ridges running up into every tongue, optional cup (curl) -> geometry
//   flameCrest(H, o)              swept flame crest on a greatHelm (root on the crown's sagittal line, tail past the nape)
//   pauldronFin(o)                flame wing flaring up and out of the right pauldron (deltoidR frame), streaming back
//   finTrim(fin, o)               engraved band following a fin's top line (front face), from its root to the first tip
//   helmRivets(H, n), helmBreaths(H, o)   cheaper replacements for greatHelm's rivets / breath holes

import * as THREE from 'three';
import { plate, lathe, merge, studs, onSurface, curve, strip } from '../../char/kit/geo.js';

const lerp = (a, b, t) => a + (b - a) * t;
const clamp = (x, a, b) => (x < a ? a : x > b ? b : x);

/**
 * Flame edge from smooth segments joined at sharp points (tips, notches).
 * segments: [[[x,y,z], ...], ...] consecutive segments share their end / start point; each is Catmull-Rom smoothed.
 * Returns { at(t) -> [x,y,z] (arc-length parameter 0..1), sharp: [t of every joint] }.
 */
export function flameOutline(segments, density = 10) {
  const pts = [], sharpIdx = [];
  segments.forEach((seg, k) => {
    const c = seg.length > 2 ? curve(seg, density) : seg;
    c.forEach((p, i) => { if (k > 0 && i === 0) return; pts.push(p); });
    if (k < segments.length - 1) sharpIdx.push(pts.length - 1);
  });
  return polyline(pts, sharpIdx);
}

/** Arc-length parametrised polyline: { at(t), sharp: [t at the given vertex indices] }. */
export function polyline(pts, sharpIdx = []) {
  const s = [0];
  for (let i = 1; i < pts.length; i++) s.push(s[i - 1] + Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1], pts[i][2] - pts[i - 1][2]));
  const L = s[s.length - 1] || 1;
  const at = (t) => {
    const d = clamp(t, 0, 1) * L;
    let i = 1;
    while (i < s.length - 1 && s[i] < d) i++;
    const f = (d - s[i - 1]) / ((s[i] - s[i - 1]) || 1);
    return [lerp(pts[i - 1][0], pts[i][0], f), lerp(pts[i - 1][1], pts[i][1], f), lerp(pts[i - 1][2], pts[i][2], f)];
  };
  return { at, sharp: sharpIdx.map((i) => s[i] / L), length: L };
}

/**
 * Double-faced forged fin: a ruled plate from a root curve (hidden in the part it grows from) to a flame edge.
 * base, top: { at(t) } curves (t 0..1, matched by parameter); o: { normal [x,y,z] (front face direction), thick=0.008,
 * edgeR=0.006, nu=24, nv=4, sharp: [t] (hard ridges from the root into each tip / notch), ridge=0.0035 (ridge height),
 * ridgeW=0.06 (half width in t), cup(u, v) -> m (displacement along the normal: curl), edgeSegs=2 }
 */
export function forgedFin(base, top, o = {}) {
  const N = new THREE.Vector3(...(o.normal || [0, 0, 1])).normalize();
  const t = o.thick ?? 0.008, rh = o.ridge ?? 0.0035, rw = o.ridgeW ?? 0.06;
  const tips = o.tips || [];
  const relief = (u, v) => {
    let k = 0;
    for (const c of tips) { const d = Math.abs(u - c) / rw; if (d < 1) k = Math.max(k, Math.pow(1 - d, 1.3)); }
    return rh * k * Math.pow(Math.sin(Math.PI * clamp(v, 0, 1)), 0.6) * (1 - 0.4 * v);
  };
  const cup = o.cup || (() => 0);
  const S = (side) => (u, v) => {
    const b = base.at(u), p = top.at(u);
    const off = side * (t / 2 + relief(u, v)) + cup(u, v);
    return [lerp(b[0], p[0], v) + N.x * off, lerp(b[1], p[1], v) + N.y * off, lerp(b[2], p[2], v) + N.z * off];
  };
  const common = { nu: o.nu ?? 24, nv: o.nv ?? 4, creaseU: [...new Set([...(o.sharp || []), ...tips])].filter((x) => x > 0.01 && x < 0.99) };
  const front = plate(S(1), {
    ...common, thick: t, edgeR: o.edgeR ?? 0.006, edgeSegs: o.edgeSegs ?? 2, edge: { v0: 'none' }, ridgeWear: 0.9,
    out: () => [N.x, N.y, N.z], occ: (u, v) => 0.62 + 0.38 * Math.min(1, v * 3),
  });
  const back = plate(S(-1), { ...common, thick: 0, out: () => [-N.x, -N.y, -N.z], occ: (u, v) => 0.62 + 0.38 * Math.min(1, v * 3) });
  const g = merge([front, back]);
  g.userData.front = front.userData;
  g.userData.tips = tips;
  return g;
}

/**
 * Swept flame crest for a greatHelm (head frame). The root follows the crown's front-back line (sunk `sink` m into the
 * shell), the edge rises from the brow into one tall tongue leaning back and two lower ones, the last trailing past the
 * nape. o: { scale=1 (height), sink=0.009, thick, nu, nv }
 */
export function flameCrest(H, o = {}) {
  const C = H.S.crown;
  const k = o.scale ?? 1;
  // crown sagittal line: front (u = 0.5) from just above the brow over the apex, then down the back (u = 0)
  const root = [];
  const sink = o.sink ?? 0.009;
  const onCrown = (u, v) => { const f = C.normalAt(u, v); return [f.p.x - f.n.x * sink, f.p.y - f.n.y * sink, 0]; };
  for (let i = 0; i <= 12; i++) root.push(onCrown(0.5, lerp(0.22, 0.995, i / 12)));
  for (let i = 12; i >= 0; i--) root.push(onCrown(0.0005, lerp(0.06, 0.995, i / 12)));
  const base = polyline(root);
  const f0 = base.at(0), f1 = base.at(1);
  const top = (x, y) => [x, y, 0];
  const Y = (y) => 0.268 + (y - 0.268) * k; // heights above the crown apex scale with k
  const edge = flameOutline([
    // one smooth top line: off the brow, high over the crown, streaming back into a long tail that lifts at its point
    // (the tail stays under the corridor where the resting greatsword passes behind the helm)
    [top(f0[0] + 0.008, f0[1] + 0.01), top(0.152, Y(0.238)), top(0.11, Y(0.306)), top(0.04, Y(0.35)), top(-0.04, Y(0.372)), top(-0.12, Y(0.374)), top(-0.19, Y(0.36)), top(-0.245, Y(0.346)), top(-0.3, Y(0.356))],
    // underside: flame licks trailing back, each notch cutting toward the shell
    [top(-0.3, Y(0.356)), top(-0.262, Y(0.33)), top(-0.232, Y(0.322))],
    [top(-0.232, Y(0.322)), top(-0.255, Y(0.3)), top(-0.276, Y(0.278))],
    [top(-0.276, Y(0.278)), top(-0.232, Y(0.28)), top(-0.196, Y(0.272))],
    [top(-0.196, Y(0.272)), top(-0.212, Y(0.252)), top(-0.23, Y(0.232))],
    [top(-0.23, Y(0.232)), top(-0.185, Y(0.236)), top(-0.152, Y(0.228))],
    [top(-0.152, Y(0.228)), top(-0.135, Y(0.207)), top(-0.124, Y(0.186)), top(f1[0] - 0.01, f1[1] + 0.004)],
  ], 10);
  const tips = [edge.sharp[0], edge.sharp[2], edge.sharp[4]];
  return forgedFin(base, edge, {
    normal: [0, 0, 1], thick: o.thick ?? 0.009, edgeR: 0.0065, nu: o.nu ?? 30, nv: o.nv ?? 4,
    sharp: edge.sharp, tips, ridge: 0.004, ridgeW: 0.07,
  });
}

/**
 * Flame wing on the right pauldron (deltoidR frame: origin at the shoulder joint): rooted along the outer flank of the
 * cap and flaring up and out, its smooth top line streaming back past the shoulder into a lifted point, with two flame
 * licks trailing under it. It stays outside the corridor where the resting greatsword lies over the pauldron (KAEL's
 * stance), and leans away from the helm. o: { R, cy, cz, elong (as pauldron()), at=55 (deg: root azimuth from the cap
 * centre, up -> out), lean=44 (deg: fin plane from vertical toward +Z), yaw=20 (deg: the streaming part turns out,
 * toward the camera, so the wing also reads from the front), height=0.27 (scale), sink=0.02, thick, nu, nv }
 */
export function pauldronFin(o = {}) {
  const R = o.R ?? 0.136, cy = o.cy ?? 0.012, cz = o.cz ?? -0.008, ex = o.elong ?? 1.18;
  const az = ((o.at ?? 55) * Math.PI) / 180, lean = ((o.lean ?? 44) * Math.PI) / 180, k = (o.height ?? 0.27) / 0.27;
  const yaw = Math.tan(((o.yaw ?? 20) * Math.PI) / 180);
  const D = [Math.cos(az), Math.sin(az)];                         // root direction from the cap centre (y, z)
  const W = [0, Math.cos(lean), Math.sin(lean)];                  // fin "up": tilted out
  const Nn = [0, -W[2], W[1]];                                    // front face (out / down, toward the camera)
  const sink = o.sink ?? 0.02;
  const rootAt = (x) => { const r = Math.sqrt(Math.max(0, R * R - (x / ex) ** 2)) - sink; return [x, cy + D[0] * r, cz + D[1] * r]; };
  const A0 = rootAt(0);
  const P = (x, w) => [x, A0[1] + W[1] * w * k, A0[2] + W[2] * w * k - Math.min(0, x) * yaw * Math.min(1, w / 0.12)];
  const root = [];
  for (let i = 0; i <= 12; i++) root.push(rootAt(lerp(0.035, -0.12, i / 12)));
  const base = polyline(root);
  const r1 = base.at(1);
  const edge = flameOutline([
    // top line: off the front of the cap, rising out and back, streaming past the shoulder into a lifted point
    [P(0.042, 0.016), P(0.034, 0.07), P(0.008, 0.128), P(-0.035, 0.182), P(-0.095, 0.228), P(-0.17, 0.26), P(-0.25, 0.275), P(-0.33, 0.3)],
    // licks trailing under it
    [P(-0.33, 0.3), P(-0.29, 0.262), P(-0.255, 0.245)],
    [P(-0.255, 0.245), P(-0.28, 0.215), P(-0.3, 0.19)],
    [P(-0.3, 0.19), P(-0.25, 0.19), P(-0.21, 0.175)],
    [P(-0.21, 0.175), P(-0.225, 0.145), P(-0.24, 0.12)],
    [P(-0.24, 0.12), P(-0.19, 0.11), P(-0.155, 0.075), [r1[0] - 0.004, r1[1] + 0.004, r1[2] + 0.003]],
  ], 10);
  const tips = [edge.sharp[0], edge.sharp[2], edge.sharp[4]];
  return forgedFin(base, edge, {
    normal: Nn, thick: o.thick ?? 0.009, edgeR: 0.0065, nu: o.nu ?? 26, nv: o.nv ?? 4,
    sharp: edge.sharp, tips, ridge: 0.004, ridgeW: 0.075,
    cup: (u, v) => 0.012 * v * v, // the edge curls over, away from the body
  });
}

/**
 * Engraved band on a forgedFin's front face, running under its top line from the root end (u0) to the first tip.
 * o: { v=0.84 (0 root .. 1 edge), u0=0.035, width=0.012, n=36 }
 */
export function finTrim(fin, o = {}) {
  const u1 = fin.userData.tips[0] - 0.015, u0 = o.u0 ?? 0.035, v = o.v ?? 0.84, n = o.n ?? 36, path = [];
  for (let i = 0; i <= n; i++) path.push([lerp(u0, u1, i / n), v]);
  return strip(fin.userData.front, path, { width: o.width ?? 0.012, lift: 0.0012, bead: 0.001, smooth: 1 });
}

/** n rivets along a greatHelm's brow band (replaces H.rivets: 11 studs). */
export function helmRivets(H, n = 7, o = {}) {
  const uv = [];
  for (let i = 0; i < n; i++) uv.push([0.06 + (i / (n - 1)) * 0.88, 0.5]);
  return studs(onSurface(H.S.brow, uv), { r: o.r ?? 0.0058, h: o.h ?? 0.0036, segs: o.segs ?? 7 });
}

/** Breath holes on both cheeks of a greatHelm's face plate in a flame-shaped cluster (replaces H.breaths). */
export function helmBreaths(H, o = {}) {
  const fS = H.S.face;
  const hole = lathe([[0.0052, 0.0], [0.005, 0.0004], [0.0036, 0.0003], [0.0034, -0.0016], [0.0, -0.0016]], { segs: o.segs ?? 8, hard: [3], auto: false });
  const cluster = o.cluster || [[0, 0], [1, 0], [2, 0], [0.5, 1], [1.5, 1], [1, 2], [2, 2.2]];
  const out = [];
  for (const side of [1, -1]) for (const [cx, cy] of cluster) {
    const f = fS.normalAt(0.5 + side * (0.17 + cx * 0.046), 0.25 + cy * 0.13);
    const g = hole.clone();
    g.applyMatrix4(new THREE.Matrix4().compose(f.p.clone().addScaledVector(f.n, 0.0006), new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(0, 1, 0), f.n), new THREE.Vector3(1, 1, 1)));
    out.push(g);
  }
  return merge(out);
}

