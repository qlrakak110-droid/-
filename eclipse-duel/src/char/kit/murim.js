// Murim kit: parametric builders for cloth-first martial masters (see MURIM.md). Layered robes with crossed collars,
// sashes, skirt panels and sleeves; wrapped limbs, cloth boots, gloves; lamellar (찰갑) accents, a beast-face pauldron,
// bracers; hanging ornaments. Heads (hats, masks, wraps, hair) live in ./head.js.
//
// Conventions (as armor.js): metres, degrees in options. Rigid pieces are authored in a bone's zero-pose frame (+X
// forward, +Y up, +Z the fighter's right / camera side) and returned as geometry for put() / putPair(). Garments that
// bend with the spine are built in bind space on a `tailor()` and carry per-vertex skin weights (geometry.userData.W):
// add them with T.put(slot, geo, look). Trims are band() strips with the `brocade` uv set (look MURIM.trim + a motif
// code). Things that swing (sash ends, skirt panels, sleeve drapes, tassels, pendants) hang on spring-bone chains
// declared with hang() / skirtRig(): spread their `bones` and `springs` into the design.
//
//   const SASH = hang('sash', 'hips', [0.13, 0.03, 0.1], { n: 3, len: 0.5 });
//   export const hero = { bones: [...SASH.bones], springs: [...SASH.springs],
//     build(kit) { const T = tailor(kit); const R = robe(T, {}); T.put('robe', R.body, SILK); ... sashTail(kit, 'robe', SASH, SILK); } };

import * as THREE from 'three';
import { fnOf } from '../shapes.js';
import { surfDetail } from '../materials.js';
import { plate, sweep, lathe, extrude, band, ribbon, merge, mk, fixWinding, circle, rrect, curve, studs, onSurface, withUvw, weightsOf, putSkinned, place, mirror } from './geo.js';
import { hoop, se } from './armor.js';

const DEG = Math.PI / 180;
const lerp = (a, b, t) => a + (b - a) * t;
const clamp = (x, a, b) => (x < a ? a : x > b ? b : x);
const sstep = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
const norm3 = (v) => { const l = Math.hypot(v[0], v[1], v[2]) || 1; return [v[0] / l, v[1] / l, v[2] / l]; };

// ---- spring-chain hooks ---------------------------------------------------------------------------------------------------

/**
 * A chain of spring bones hanging from `parent`: sash ends, sleeve drapes, hair tails, tassels, pendants, veil strands.
 * Spread `.bones` and `.springs` into the design; hand the object to the builder that skins a piece to it.
 * @param {string} name    bone name prefix (bones are name1 .. nameN; do not end it in R / L unless the pair is mirrored)
 * @param {string} parent  bone the chain hangs from
 * @param {number[]} at    root position in the parent's zero frame
 * @param {object} o  n=3 (bones)  len=0.3 (m, total)  dir=[0,-1,0] (rest direction in the parent frame)
 *   stiffness=24, damping=2.8, gravity=0.9, limit=70 (deg), radius=0.02, collide=true, inertia=1  (src/char/spring.js)
 * @returns {{ name, names: string[], bones: object[], springs: object[], seg: number, len: number, dir: number[], at: number[], parent: string }}
 */
export function hang(name, parent, at, o = {}) {
  const n = o.n ?? 3, len = o.len ?? 0.3, d = norm3(o.dir || [0, -1, 0]), seg = len / n;
  const names = Array.from({ length: n }, (_, i) => name + (i + 1));
  const step = [d[0] * seg, d[1] * seg, d[2] * seg];
  const bones = names.map((nm, i) => ({ name: nm, parent: i ? names[i - 1] : parent, at: i ? step : at, side: 0 }));
  const springs = [{
    bones: names, tip: step, stiffness: o.stiffness ?? 24, damping: o.damping ?? 2.8, gravity: o.gravity ?? 0.9,
    limit: o.limit ?? 70, radius: o.radius ?? 0.02, collide: o.collide ?? true, inertia: o.inertia ?? 1,
  }];
  return { name, names, bones, springs, seg, len, dir: d, at, parent, n };
}

/**
 * Skin weights along a hang() chain: s = 0 at the root .. 1 at the tip. Each bone carries its own segment; the joints
 * blend over the middle of the neighbouring segments so a ribbon bends smoothly. `rootBlend` > 0 leaves the first
 * `rootBlend` of the length on the parent (a tail that grows out of the body).
 */
export function chainWeights(H, s, rootBlend = 0) {
  const n = H.n, x = clamp(s, 0, 1) * n, i = Math.min(n - 1, Math.floor(x)), f = x - i;
  const out = [];
  if (f > 0.5 && i < n - 1) { const b = (f - 0.5); out.push([H.names[i], 1 - b], [H.names[i + 1], b]); }
  else if (f < 0.5 && i > 0) { const b = (0.5 - f); out.push([H.names[i], 1 - b], [H.names[i - 1], b]); }
  else out.push([H.names[i], 1]);
  if (rootBlend > 0 && s < rootBlend) {
    const k = 1 - s / rootBlend;
    return [[H.parent, k], ...out.map(([b, w]) => [b, w * (1 - k)])];
  }
  return out;
}

/** Bind-space points of a hang() chain: root, joints, tip (n + 1 points) — the path a tail / ribbon is built along. */
export function chainPath(kit, H) {
  const pts = H.names.map((nm) => kit.bonePos(nm));
  const a = pts[pts.length - 1], b = pts.length > 1 ? pts[pts.length - 2] : null;
  // the tip continues the last segment (bind pose)
  let d;
  if (b) d = norm3([a[0] - b[0], a[1] - b[1], a[2] - b[2]]);
  else { const q = kit.bind.mq, i = kit.rig.index[H.names[0]] * 4, v = new THREE.Vector3(...H.dir).applyQuaternion(new THREE.Quaternion(q[i], q[i + 1], q[i + 2], q[i + 3])); d = [v.x, v.y, v.z]; }
  pts.push([a[0] + d[0] * H.seg, a[1] + d[1] * H.seg, a[2] + d[2] * H.seg]);
  return pts;
}

/**
 * Bones + springs of a skirt / coat panel that follows a leg: a follower bone at the waist (takes `k` x the thigh's
 * swing, like a tasset) and a spring chain below it for the lag of the hem. Panels without `follow` (back panels, coat
 * tails) are a plain spring chain from the hips.
 * @param {string} name  bone prefix (name0 = follower, name1.. = chain)
 * @param {object} o  a0, a1 (deg sector around the hips; 0 = front, 90 = the fighter's right)   y=0.03 (top, hips frame)
 *   len=0.7   rx=0.15, rz=0.185 (waist radii)   follow='thighR' | 'thighL' | null   k=0.62   n=2 (spring bones)
 *   rigid=0.34 (share of the length on the follower)   stiffness=34, damping=3.6, gravity=0.85, limit=50, radius=0.05
 */
export function skirtRig(name, o = {}) {
  const a0 = o.a0 ?? -40, a1 = o.a1 ?? 40, am = ((a0 + a1) / 2) * DEG, y = o.y ?? 0.03, len = o.len ?? 0.7;
  const rx = o.rx ?? 0.15, rz = o.rz ?? 0.185, n = o.n ?? 2, rigid = o.follow ? (o.rigid ?? 0.34) : 0;
  const [x, z] = se(am, rx, rz, 2.2);
  const at = [x, y, z], seg = (len * (1 - rigid)) / n;
  const bones = [], names = Array.from({ length: n }, (_, i) => name + (i + 1));
  if (o.follow) bones.push({ name: name + '0', parent: 'hips', at, follow: { bone: o.follow, k: o.k ?? 0.62 }, side: 0 });
  names.forEach((nm, i) => bones.push({ name: nm, parent: i ? names[i - 1] : (o.follow ? name + '0' : 'hips'), at: i ? [0, -seg, 0] : (o.follow ? [0, -len * rigid, 0] : at), side: 0 }));
  const springs = [{
    bones: names, tip: [0, -seg, 0], stiffness: o.stiffness ?? 34, damping: o.damping ?? 3.6, gravity: o.gravity ?? 0.85,
    limit: o.limit ?? 50, radius: o.radius ?? 0.05, collide: o.collide ?? true, inertia: o.inertia ?? 1,
  }];
  return { name, names, bones, springs, a0, a1, y, len, rx, rz, n, rigid, seg, follow: o.follow || null, root: o.follow ? name + '0' : 'hips' };
}

// ---- tailor: the torso's garment frame -------------------------------------------------------------------------------------

/** Default torso cross-section by chest-frame height (m at body scale 1): [y, radius]. */
const BODY_RX = [[-0.4, 0.118], [-0.3, 0.126], [-0.2, 0.112], [-0.1, 0.118], [0.0, 0.132], [0.08, 0.14], [0.15, 0.132], [0.2, 0.112], [0.245, 0.082], [0.3, 0.064]];
const BODY_RZ = [[-0.4, 0.172], [-0.3, 0.168], [-0.2, 0.148], [-0.1, 0.155], [0.0, 0.172], [0.08, 0.186], [0.15, 0.19], [0.2, 0.166], [0.245, 0.094], [0.3, 0.068]];
const BODY_OX = [[-0.4, -0.006], [-0.2, 0.0], [0.05, 0.012], [0.2, 0.0], [0.3, -0.004]];

/**
 * Garment frame of the torso: its cross-section by height and the skin weights every torso garment shares, so robe,
 * collar bands, sash and lamellar rows deform as one piece of clothing when the spine bends.
 * @param {object} kit  the build kit
 * @param {object} o  body: { rx, rz, ox: curves over the chest-frame height (m, body scale 1), n } (default: an
 *   athletic torso)   width=1, depth=1 (quick build: 1.1 heavy, 0.88 slender)   shoulder=0.55 (share of the clavicle
 *   near the armholes)
 * @returns T: { K, yc, at(aDeg, y, grow) -> { p, n }, weights(x, y, z) -> [[bone, w]...], put(slot, geo, look, o),
 *   ring(y, grow, n) -> frames }  (y = height in the chest frame, metres at this body's scale; a = 0 front, 90 right)
 */
export function tailor(kit, o = {}) {
  const K = kit.rig.k, B = o.body || {};
  const RXc = fnOf(B.rx || BODY_RX), RZc = fnOf(B.rz || BODY_RZ), OXc = fnOf(B.ox || BODY_OX), NE = B.n ?? 2.3;
  const wd = o.width ?? 1, dp = o.depth ?? 1, shK = o.shoulder ?? 0.55;
  const c = kit.bonePos('chest'), yc = c[1], yh = kit.bonePos('hips')[1], ys = kit.bonePos('spine')[1], yn = kit.bonePos('neck')[1], yhd = kit.bonePos('head')[1];
  const RX = (y) => RXc(y / K) * K * dp, RZ = (y) => RZc(y / K) * K * wd, OX = (y) => OXc(y / K) * K;
  const pt = (a, y, grow) => { const [x, z] = se(a * DEG, RX(y) + grow, RZ(y) + grow, NE); return [c[0] + OX(y) + x, yc + y, c[2] + z]; };
  const at = (a, y, grow = 0) => {
    const p = pt(a, y, grow), pa = pt(a + 1.5, y, grow), pb = pt(a - 1.5, y, grow), pu = pt(a, y + 0.004, grow), pd = pt(a, y - 0.004, grow);
    const ta = [pa[0] - pb[0], pa[1] - pb[1], pa[2] - pb[2]], ty = [pu[0] - pd[0], pu[1] - pd[1], pu[2] - pd[2]];
    let n = [ty[1] * ta[2] - ty[2] * ta[1], ty[2] * ta[0] - ty[0] * ta[2], ty[0] * ta[1] - ty[1] * ta[0]];
    n = norm3(n);
    if (n[0] * (p[0] - c[0]) + n[2] * (p[2] - c[2]) < 0) n = [-n[0], -n[1], -n[2]];
    return { p, n };
  };
  // skin stations by bind height: [y, bone]; smooth blend between consecutive stations
  const st = [[yh + 0.02 * K, 'hips'], [ys - 0.012 * K, 'spine'], [ys + 0.09 * K, 'spine'], [yc + 0.03 * K, 'chest'], [yc + 0.2 * K, 'chest'], [yn + 0.03 * K, 'neck'], [yn + 0.075 * K, 'neck'], [yhd + 0.01 * K, 'head']];
  const weights = (x, y, z) => {
    let out;
    if (y <= st[0][0]) out = [['hips', 1]];
    else if (y >= st[st.length - 1][0]) out = [['head', 1]];
    else {
      for (let i = 0; i < st.length - 1; i++) {
        if (y > st[i + 1][0]) continue;
        const t = sstep(st[i][0], st[i + 1][0], y);
        out = st[i][1] === st[i + 1][1] || t <= 0 ? [[st[i][1], 1]] : t >= 1 ? [[st[i + 1][1], 1]] : [[st[i][1], 1 - t], [st[i + 1][1], t]];
        break;
      }
    }
    const sh = shK * sstep(0.105 * K * wd, 0.2 * K * wd, Math.abs(z - c[2])) * sstep(yc + 0.06 * K, yc + 0.16 * K, y) * (1 - sstep(yn + 0.01 * K, yn + 0.05 * K, y));
    if (sh > 0.001) return [...out.map(([b, w]) => [b, w * (1 - sh)]), [z > c[2] ? 'shoulderR' : 'shoulderL', sh]];
    return out;
  };
  const T = {
    kit, K, yc, c, at, weights, RX, RZ, OX, n: NE,
    /** Weights of a garment point given in the chest frame. */
    weightsAt: (p) => weights(p[0], p[1], p[2]),
    /** putSkinned with the geometry's own weights (userData.W) or the tailor's height weights (bind-space geometry). */
    put(slot, geo, look, opts = {}) { return putSkinned(kit, slot, geo, look, geo.userData.W ? weightsOf(geo.userData.W) : weights, opts); },
    /** Surface frames around the torso at height y (closed ring of n frames, each with its skin weights). */
    ring(y, grow = 0, n = 40, a0 = -180, a1 = 180) {
      const closed = a1 - a0 >= 360, m = closed ? n : n + 1, out = [];
      for (let i = 0; i < m; i++) { const f = at(lerp(a0, a1, i / n), typeof y === 'function' ? y(lerp(a0, a1, i / n)) : y, grow); f.w = weights(f.p[0], f.p[1], f.p[2]); out.push(f); }
      return out;
    },
    /** Surface frames along a path of [aDeg, y] points (each with its skin weights). */
    path(pts, grow = 0) { return pts.map(([a, y]) => { const f = at(a, y, grow); f.w = weights(f.p[0], f.p[1], f.p[2]); return f; }); },
  };
  return T;
}

/**
 * Crossed-collar robe torso (무복 / 장포 upper body), left panel over right: a closed shell from the neck to below the
 * waist whose neckline is the Y of the crossed collar, with the two collar bands (brocade uv) lying along it and the
 * over-panel's edge running on to the waist on the fighter's right (camera side). Wear two (an inner one with a
 * higher crossing and a pale band) for layered collars.
 * @param {object} T  tailor()
 * @param {object} o  yTop=0.285 (back of the neck, chest frame x body scale)   yBot=-0.33   grow=0.014 (ease over the body)
 *   cross: { y: 0.04, a: 5, spread: 64 }  crossing point (height, deg toward the right) and where the V meets the neck
 *   lapel: { a: 46, y: yBot + 0.1 }  where the over edge ends at the waist      blouse=0.012 (gathered pleats above the sash)
 *   sashY=-0.2   bandW=0.044   motif=0 (brocade code of the bands)   under=true (build the under band)   nu=44, nv=20
 * @returns {{ body, bandOver, bandUnder, top(a), line(y) }} geometries with skin weights (add with T.put)
 */
export function robe(T, o = {}) {
  const K = T.K, yTop = (o.yTop ?? 0.285) * K, yBot = (o.yBot ?? -0.33) * K, grow = o.grow ?? 0.014;
  const X = { y: 0.04, a: 5, spread: 64, ...(o.cross || {}) }, yX = X.y * K, ySide = yTop - 0.018 * K;
  const L = { a: 46, y: (o.yBot ?? -0.33) + 0.1, ...(o.lapel || {}) }, sashY = (o.sashY ?? -0.2) * K, blouse = o.blouse ?? 0.012;
  const bw = (o.bandW ?? 0.044) * K;
  const top = (a) => {
    if (a >= -X.spread && a <= X.a) return lerp(yX, ySide, Math.pow((X.a - a) / (X.a + X.spread), 0.85));
    if (a > X.a && a <= X.spread) return lerp(yX, ySide, Math.pow((a - X.a) / (X.spread - X.a), 0.85));
    return lerp(ySide, yTop, sstep(X.spread, 150, Math.abs(a)));
  };
  // the over panel's edge below the crossing: angle as a function of height
  const line = (y) => lerp(X.a, L.a, Math.pow(clamp((yX - y) / (yX - L.y * K), 0, 1), 0.9));
  const S = (u, v) => {
    const a = lerp(-180, 180, u), yt = top(a), y = lerp(yt, yBot, v);
    // gathered above the sash: soft vertical pleats that fade toward the chest and under the sash
    const g = Math.exp(-(((y - sashY - 0.07 * K) / (0.075 * K)) ** 2));
    const pleat = blouse * g * (0.55 + 0.45 * Math.sin(a * DEG * 9 + 1.3) * Math.sin(a * DEG * 4 + 0.4));
    // the over panel lies one cloth thickness above the under panel
    const over = y < yX ? 0.004 * (1 - sstep(line(y) - 5, line(y) + 2, a)) * sstep(-170, -150, a) : 0;
    return T.at(a, y, grow + pleat + over).p;
  };
  const body = plate(S, { nu: o.nu ?? 44, nv: o.nv ?? 20, thick: 0.004, closeU: true, edgeSegs: 2, axis: [T.c[0], T.c[2]], curv: 0.002, edgeWear: 0.3 });
  const N = 30, over = [], under = [];
  for (let i = 0; i <= N; i++) { const a = lerp(-180, X.a, i / N); over.push([a, top(a)]); }
  const yEnd = L.y * K;
  for (let i = 1; i <= 14; i++) { const y = lerp(yX, yEnd, i / 14); over.push([line(y), y]); }
  for (let i = 0; i <= 22; i++) { const a = lerp(180, X.a + 3, i / 22); under.push([a, top(a)]); }
  const code = o.motif ?? 0;
  const mk2 = (pts, lift, flip) => band(T.path(pts, grow + 0.001), { width: bw, shift: 0.5, side: [0, -1, 0], lift, thick: 0.003, crown: 0.0015, code, flipV: flip });
  const out = { body, bandOver: mk2(over, 0.0045, false), top, line, S };
  if (o.under !== false) out.bandUnder = mk2(under, 0.0005, true);
  return out;
}

/**
 * Wide sash (요대) wound around the waist: a soft band with wrap folds; knot() ties it and sashTail() hangs its ends.
 * @param {object} T  tailor()
 * @param {object} o  y=-0.2 (centre height, chest frame x body scale)   h=0.115   grow=0.026   wraps=3 (fold lines)
 *   tilt=0.012 (the front sits lower)   nu=40
 * @returns geometry with skin weights (T.put); userData.frame(aDeg, dy) -> { p, n, w } on the sash surface
 */
export function sash(T, o = {}) {
  const K = T.K, y = (o.y ?? -0.2) * K, h = (o.h ?? 0.115) * K, grow = o.grow ?? 0.026, wraps = o.wraps ?? 3, tilt = (o.tilt ?? 0.012) * K;
  const yAt = (a, v) => y + h * (0.5 - v) - tilt * Math.cos(a * DEG);
  const gAt = (a, v) => grow + 0.007 * Math.sin(Math.PI * v) + 0.0035 * Math.abs(Math.sin(Math.PI * wraps * (v + 0.04 * Math.sin(a * DEG * 2))));
  const S = (u, v) => { const a = lerp(-180, 180, u); return T.at(a, yAt(a, v), gAt(a, v)).p; };
  const g = plate(S, { nu: o.nu ?? 40, nv: 2 * wraps, thick: 0.005, closeU: true, edgeSegs: 2, axis: [T.c[0], T.c[2]], curv: 0.0025, edgeWear: 0.35 });
  g.userData.frame = (a, dy = 0) => { const f = T.at(a, y + dy - tilt * Math.cos(a * DEG), grow + 0.008); f.w = T.weights(f.p[0], f.p[1], f.p[2]); return f; };
  return g;
}

/**
 * Knot of a sash / headband / cord, tied at a surface frame: a wrapped centre and two drooping loops.
 * @param {object} f  frame { p, n, w? } (sash.userData.frame(a), or any point + outward normal)
 * @param {object} o  size=0.05   loops=2 (0 = a plain wrap)   up=[0,1,0]   droop=0.5
 * @returns geometry (bind space when the frame is; userData.W when the frame has weights)
 */
export function knot(f, o = {}) {
  const s = o.size ?? 0.05, n = new THREE.Vector3(...f.n), up = new THREE.Vector3(...(o.up || [0, 1, 0]));
  up.addScaledVector(n, -up.dot(n)).normalize();
  const sd = new THREE.Vector3().crossVectors(up, n).normalize();
  const P = new THREE.Vector3(...f.p);
  const L = (x, y, z) => P.clone().addScaledVector(sd, x * s).addScaledVector(up, y * s).addScaledVector(n, z * s);
  const parts = [];
  // centre wrap: a flattened lump, the cloth crossing over itself
  const cpts = [];
  for (let i = 0; i <= 8; i++) { const a = (i / 8) * Math.PI; cpts.push(L(0.04 * Math.cos(a * 2), 0.42 * Math.cos(a), 0.26 + 0.14 * Math.sin(a))); }
  parts.push(sweep(cpts, rrect(1, 1, 0.5, 2), { scale: (t) => [s * (0.2 + 0.1 * Math.sin(t * Math.PI)), s * (0.3 + 0.12 * Math.sin(t * Math.PI))], up: [n.x, n.y, n.z], caps: true }));
  const droop = o.droop ?? 0.5;
  for (let k = 0; k < (o.loops ?? 2); k++) {
    const sg = k ? -1 : 1, lp = [];
    for (let i = 0; i <= 12; i++) { const t = i / 12, a = t * Math.PI * 2; lp.push(L(sg * (0.2 + 0.62 * (1 - Math.cos(a)) * 0.5), 0.3 * Math.sin(a) - droop * 0.5 * (1 - Math.cos(a)) * 0.5, 0.22 + 0.12 * Math.sin(a * 0.5))); }
    parts.push(sweep(lp, rrect(1, 1, 0.4, 1), { scale: (t) => [s * 0.07, s * (0.2 + 0.08 * Math.sin(t * Math.PI))], up: [n.x, n.y, n.z], caps: true }));
  }
  const g = merge(parts);
  if (f.w) g.userData.W = new Array(g.attributes.position.count).fill(f.w);
  return g;
}

/**
 * Hanging end of a sash / headband / ribbon on a hang() chain: a tapered cloth strip with a soft fold, optionally
 * finished with a fringe. Single sheet: put it on a double-sided (or cut-out) slot.
 * @param {object} kit
 * @param {object} H   hang() chain
 * @param {object} o   width=0.085 (m | fn(t))   normal=[1,0,0] (face normal hint)   camber=0.14   nu=3   segs=4 (per bone)
 *   start=0 (m above the root: the strip begins this far up, on the parent)   wave=0.012 (a slight S along its length)
 * @returns geometry with skin weights (putSkinned(kit, slot, geo, look, weightsOf(geo.userData.W)))
 */
export function sashTail(kit, H, o = {}) {
  const path = chainPath(kit, H), n = H.n, segs = o.segs ?? 4, pts = [], ts = [];
  const nrm = norm3(o.normal || [1, 0, 0]), wave = o.wave ?? 0.012;
  for (let i = 0; i <= n * segs; i++) {
    const s = i / (n * segs), x = s * n, k = Math.min(n - 1, Math.floor(x)), f = x - k;
    const a = path[k], b = path[k + 1], w = wave * Math.sin(s * Math.PI * 2.2) * s;
    pts.push([lerp(a[0], b[0], f) + nrm[0] * w, lerp(a[1], b[1], f) + nrm[1] * w, lerp(a[2], b[2], f) + nrm[2] * w]);
    ts.push(s);
  }
  const W = typeof o.width === 'function' ? o.width : ((w) => (t) => w * (1 - 0.18 * t))(o.width ?? 0.085);
  return ribbon(pts, { width: W, normal: nrm, camber: o.camber ?? 0.14, nu: o.nu ?? 3, weights: (t) => chainWeights(H, t, o.rootBlend ?? 0.04), code: o.code ?? 0 });
}

/**
 * Skirt / coat panel on a skirtRig(): a sector of cloth hanging from the waist with soft pleats and a shaped hem. It
 * follows its leg through the follower bone and lags at the hem through the spring chain. Single sheet (double-sided
 * slot). Returns { panel, hem (brocade band along the hem), edgeL, edgeR (bands along the side slits) } with weights.
 * @param {object} kit
 * @param {object} R  skirtRig()
 * @param {object} o  flare=0.1 (radius gained at the hem)   pleats=3, pleat=0.016 (fold depth at the hem)
 *   hem: fn(u) -> length factor (0..1.2; u = 0 at a0 .. 1 at a1; default 1)   lift=0.01 (above the waist ring)
 *   bandW=0.05, motif=0 (hem band; bandW 0 = none)   sideW=0 (side bands)   nu=10, nv=12   wrap=0 (deg the panel
 *   overlaps past a0 / a1)
 */
export function skirtPanel(kit, R, o = {}) {
  const hb = kit.bonePos('hips'), flare = o.flare ?? 0.1, np = o.pleats ?? 3, pd = o.pleat ?? 0.016, hem = o.hem || (() => 1);
  const a0 = R.a0 - (o.wrap ?? 0), a1 = R.a1 + (o.wrap ?? 0), lift = o.lift ?? 0.01;
  const S = (u, v) => {
    const a = lerp(a0, a1, u) * DEG, len = R.len * hem(u) * v;
    const fold = pd * Math.sin(u * Math.PI * np * 2 + 0.7) * (0.15 + 0.85 * v) + 0.006 * Math.sin(u * Math.PI * 7 + 2) * v;
    const [x, z] = se(a, R.rx + lift + flare * Math.pow(v, 1.2) + fold, R.rz + lift + flare * Math.pow(v, 1.2) + fold, 2.2);
    return [hb[0] + x, hb[1] + R.y - len, hb[2] + z];
  };
  // weights by distance down the panel: hips at the waistband, the follower, then the chain
  const names = R.follow ? [R.name + '0', ...R.names] : R.names;
  const stops = R.follow ? [0.1, ...R.names.map((_, i) => R.rigid + ((1 - R.rigid) * (i + 0.15)) / R.n)] : R.names.map((_, i) => (i + 0.2) / R.n * 0.9 + 0.05);
  const wAt = (v) => {
    if (v <= 0.03) return [['hips', 1]];
    let prev = 'hips', pv = 0.03;
    for (let i = 0; i < names.length; i++) {
      const hi = stops[i] + 0.14;
      if (v < hi) { const t = sstep(pv, hi, v); return t >= 1 ? [[names[i], 1]] : [[prev, 1 - t], [names[i], t]]; }
      prev = names[i]; pv = hi;
    }
    return [[prev, 1]];
  };
  const nu = o.nu ?? 10, nv = o.nv ?? 12;
  const grid = (lyr) => {
    const pos = [], nor = [], idx = [], W = [], e = 1e-3;
    for (let j = 0; j <= nv; j++) for (let i = 0; i <= nu; i++) {
      const u = i / nu, v = j / nv, p = S(u, v), pu = S(Math.min(1, u + e), v), pm = S(Math.max(0, u - e), v), pv2 = S(u, Math.min(1, v + e)), pw = S(u, Math.max(0, v - e));
      const du = [pu[0] - pm[0], pu[1] - pm[1], pu[2] - pm[2]], dv = [pv2[0] - pw[0], pv2[1] - pw[1], pv2[2] - pw[2]];
      let nn = norm3([dv[1] * du[2] - dv[2] * du[1], dv[2] * du[0] - dv[0] * du[2], dv[0] * du[1] - dv[1] * du[0]]);
      if (nn[0] * (p[0] - hb[0]) + nn[2] * (p[2] - hb[2]) < 0) nn = [-nn[0], -nn[1], -nn[2]];
      pos.push(p[0] + nn[0] * lyr, p[1] + nn[1] * lyr, p[2] + nn[2] * lyr); nor.push(...nn); W.push(wAt(v));
    }
    for (let j = 0; j < nv; j++) for (let i = 0; i < nu; i++) { const a = j * (nu + 1) + i, b = a + 1, c = a + nu + 1, d = c + 1; idx.push(a, c, b, b, c, d); }
    const g = fixWinding(mk(pos, nor, idx));
    g.userData.W = W;
    return g;
  };
  const out = { panel: grid(0), S, wAt };
  const frame = (u, v) => {
    const e = 2e-3, p = S(u, v), pu = S(Math.min(1, u + e), v), pm = S(Math.max(0, u - e), v), pa = S(u, Math.min(1, v + e)), pb = S(u, Math.max(0, v - e));
    const du = [pu[0] - pm[0], pu[1] - pm[1], pu[2] - pm[2]], dv = [pa[0] - pb[0], pa[1] - pb[1], pa[2] - pb[2]];
    let nn = norm3([dv[1] * du[2] - dv[2] * du[1], dv[2] * du[0] - dv[0] * du[2], dv[0] * du[1] - dv[1] * du[0]]);
    if (nn[0] * (p[0] - hb[0]) + nn[2] * (p[2] - hb[2]) < 0) nn = [-nn[0], -nn[1], -nn[2]];
    return { p, n: nn, w: wAt(v) };
  };
  out.frame = frame;
  const bw = o.bandW ?? 0.05, code = o.motif ?? 0;
  if (bw > 0) {
    const fr = [];
    for (let i = 0; i <= nu * 2; i++) fr.push(frame(i / (nu * 2), 1));
    out.hem = band(fr, { width: bw, shift: -0.5, side: [0, -1, 0], flat: true, lift: 0.0012, thick: 0.0006, crown: 0.0008, code, flipV: true });
  }
  const sw = o.sideW ?? 0;
  if (sw > 0) {
    for (const [key, u, sh] of [['edgeL', 0, 0.5], ['edgeR', 1, -0.5]]) {
      const fr = [];
      for (let j = 0; j <= nv; j++) fr.push(frame(u, (j / nv) * (bw > 0 ? 1 - bw / (R.len * hem(u)) : 1)));
      const tng = norm3([S(1, 0.5)[0] - S(0, 0.5)[0], 0, S(1, 0.5)[2] - S(0, 0.5)[2]]);
      out[key] = band(fr, { width: sw, shift: sh, side: tng, flat: true, lift: 0.0012, thick: 0.0006, crown: 0.0008, code });
    }
  }
  return out;
}

// ---- sleeves, trousers ---------------------------------------------------------------------------------------------------

/**
 * Sleeves (both arms): a smooth-skinned tube from inside the shoulder to the wrist, the elbow or mid forearm, with
 * bunched folds. Fitted sleeves end in a cuff; a wide sleeve ends at the elbow / mid forearm under a sleeveBell().
 * @param {object} kit
 * @param {string} slot
 * @param {object} look  surface look (MURIM.silk ...)
 * @param {object} o  to='wrist' | 'mid' | 'elbow'   r: [shoulder, biceps, elbow, forearm, wrist] radii (m, body scale 1)
 *   folds=0.004 (ring folds, deepest around the elbow)   side='both' | 'R' (right arm only)   segs=[12, 22]
 */
export function sleeve(kit, slot, look, o = {}) {
  const P = kit.rig.P, K = kit.rig.k, r = (o.r || [0.058, 0.068, 0.06, 0.056, 0.044]).map((x) => x * K), to = o.to ?? 'wrist', folds = o.folds ?? 0.004;
  const full = [['shoulderR', [-0.005 * K, -0.045 * K, P.clavicle * 0.55]], ['upperArmR', [0, -0.01 * K, 0]], ['upperArmR', [0, -P.upperArm * 0.5, 0]], ['foreArmR', [0, 0, 0]], ['foreArmR', [0, -P.foreArm * 0.52, 0]], ['handR', [0, 0, 0]], ['handR', [0, -0.03 * K, 0]]];
  const wts = [[0, 'shoulderR'], [0.7, 'deltoidR'], [1.15, 'upperArmTwistR'], [1.9, 'upperArmR'], [2.75, 'upperArmR'], [3, 'elbowR'], [3.25, 'foreArmR'], [3.6, 'foreArmR'], [4.4, 'foreArmTwistR'], [4.85, 'foreArmTwistR'], [5.15, 'handR']];
  let path = full, weights = wts, end = 6;
  if (to === 'elbow') { path = [...full.slice(0, 4), ['foreArmR', [0, -0.045 * K, 0]]]; end = 4; }
  else if (to === 'mid') { path = full.slice(0, 5); end = 4; }
  weights = wts.filter(([k]) => k <= end + 0.3).map(([k, b]) => [Math.min(k, end), b]);
  const base = [[0, r[0]], [1, r[1]], [2, r[1] * 0.97], [3, r[2]], [4, r[3]], [5, r[4]], [6, r[4] * 0.96]].filter(([k]) => k <= end);
  const RB = fnOf(base);
  const fold = (f) => folds * Math.sin(f * 21 + 0.6) * Math.exp(-(((f - 3) / 0.9) ** 2)) + folds * 0.5 * Math.sin(f * 13 + 2) * Math.exp(-(((f - 1.2) / 0.7) ** 2));
  const spec = { path, weights, rx: (f) => RB(f) + fold(f), rz: (f) => RB(f) * 1.04 + fold(f), segs: o.segs || [12, to === 'wrist' ? 26 : 18], caps: [true, to === 'wrist'] };
  const opts = lookOpts(look);
  if (o.side === 'R') kit.loft(slot, spec, opts); else kit.loftPair(slot, spec, opts);
  return spec;
}

/** Look -> kit.loft surface options (lofts carry no per-vertex cavity). */
export function lookOpts(look) {
  return { color: look.color, rough: look.rough ?? 0.5, metal: look.metal ?? 0, detail: detailOf(look), cavity: 1, glow: [look.inlay ?? 0, look.vein ?? 0, look.eye ?? 0] };
}
const detailOf = (look) => surfDetail(look.set ?? 0, look.amt ?? 1);

/**
 * Bell of a wide sleeve (광수), rigid on the forearm (`foreArmR` frame; mirror with putPair(kit, slot, 'foreArm', ...)):
 * a cone that opens toward the wrist, hanging lower at the back so the opening is a long drooping mouth, with a trim
 * band along it. The upper sleeve (sleeve({ to: 'elbow' })) disappears into its top. Single sheet (double-sided slot).
 * @param {object} o  len=0.24 (below the elbow)   r0=0.07 (top radius)   r1=0.115 (mouth)   drop=0.16 (how far the mouth
 *   hangs at the back)   back=0.035 (mouth shifted to the back of the arm)   top=0.045 (above the elbow)
 *   bandW=0.04, motif=0   nu=20, nv=7
 * @returns {{ bell, trim }}
 */
export function sleeveBell(o = {}) {
  const len = o.len ?? 0.24, r0 = o.r0 ?? 0.07, r1 = o.r1 ?? 0.115, drop = o.drop ?? 0.16, back = o.back ?? 0.035, top = o.top ?? 0.045;
  const hang = (a) => Math.pow(0.5 - 0.5 * Math.cos((a - 0) * DEG), 1.6);      // 0 at the front (+X) .. 1 at the back (-X)
  const bell = hoop({
    y0: top, y1: -len, closed: true,
    rx: [[0, r0], [0.3, lerp(r0, r1, 0.3)], [1, r1 * 1.05]], rz: [[0, r0 * 1.03], [0.3, lerp(r0, r1, 0.34)], [1, r1 * 0.9]],
    ox: [[0, 0], [0.4, -back * 0.3], [1, -back]], n: 2.1,
    bot: (a) => -drop * hang(a),
    bulge: (u, v) => 0.006 * Math.sin(u * Math.PI * 10 + 1) * v * v + 0.004 * Math.sin(v * 9 + u * 5) * (1 - v),
    nu: o.nu ?? 20, nv: o.nv ?? 7, thick: 0, curv: 0.002,
  });
  const out = { bell };
  const bw = o.bandW ?? 0.04;
  if (bw > 0) {
    const fr = [], n = (o.nu ?? 20) * 2, F = bell.userData.normalAt;
    for (let i = 0; i < n; i++) { const f = F(i / n, 0.999); fr.push({ p: f.p, n: f.n }); }
    out.trim = band(fr, { width: bw, shift: -0.5, side: [0, -1, 0], closed: true, lift: 0.0012, thick: 0.0018, crown: 0.001, code: o.motif ?? 0, flipV: true });
  }
  return out;
}

/**
 * Cuff band of a fitted sleeve / trouser leg / boot top: a closed brocade band around a limb (bone frame, around +Y).
 * @param {object} o  y=-0.2 (height in the bone frame)   rx=0.05, rz=0.052   w=0.035   tilt=0   motif=0   n=20   thick=0.003
 */
export function cuff(o = {}) {
  const y = o.y ?? -0.2, rx = o.rx ?? 0.05, rz = o.rz ?? rx * 1.04, n = o.n ?? 20, fr = [];
  for (let i = 0; i < n; i++) {
    const a = (i / n) * Math.PI * 2, [x, z] = se(a, rx, rz, 2.1), nn = norm3([x / (rx * rx), 0, z / (rz * rz)]);
    fr.push({ p: [(o.ox ?? 0) + x, y + (o.tilt ?? 0) * Math.cos(a), (o.oz ?? 0) + z], n: nn });
  }
  return band(fr, { width: o.w ?? 0.035, closed: true, side: [0, -1, 0], lift: 0.0006, thick: o.thick ?? 0.003, crown: 0.0012, code: o.motif ?? 0 });
}

/**
 * Trouser legs (both): smooth-skinned, loose above the knee, gathered into the boot / shin wrap below it.
 * @param {object} o  r: [hip, thigh, knee, calf, ankle] radii (m, body scale 1)   folds=0.005   to='ankle' | 'calf'
 */
export function trousers(kit, slot, look, o = {}) {
  const P = kit.rig.P, K = kit.rig.k, r = (o.r || [0.108, 0.1, 0.076, 0.07, 0.05]).map((x) => x * K), folds = o.folds ?? 0.005;
  const leg = P.hipHeight - P.ankleHeight, thigh = leg * P.thighRatio, shin = leg - thigh;
  const path = [['hips', [0, -0.03 * K, P.hipWidth * 0.78]], ['thighR', [0, 0, 0]], ['thighR', [0, -thigh * 0.52, 0]], ['shinR', [0, 0, 0]], ['shinR', [0, -shin * 0.5, 0]], ['footR', [0, 0, 0]], ['footR', [0, -0.04 * K, 0]]];
  const weights = [[0, 'hips'], [0.75, 'hips'], [1.3, 'thighR'], [2.75, 'thighR'], [3, 'kneeR'], [3.25, 'shinR'], [4.8, 'shinR'], [5.15, 'footR']];
  const end = o.to === 'calf' ? 4 : 6;
  const RB = fnOf([[0, r[0]], [1, r[0] * 0.98], [2, r[1]], [3, r[2]], [4, r[3]], [5, r[4]], [6, r[4] * 0.95]].filter(([k]) => k <= end));
  const fold = (f) => folds * Math.sin(f * 17 + 0.4) * Math.exp(-(((f - 3) / 1.0) ** 2)) + folds * 0.7 * Math.sin(f * 11) * Math.exp(-(((f - 4.4) / 0.6) ** 2));
  kit.loftPair(slot, {
    path: path.slice(0, end + 1), weights: weights.filter(([k]) => k <= end + 0.3).map(([k, b]) => [Math.min(k, end), b]),
    rx: (f) => RB(f) + fold(f), rz: (f) => RB(f) * 0.97 + fold(f), ox: [[0, 0], [4, -0.006 * K], [5, 0]], segs: o.segs || [12, 24], caps: [true, end === 6],
  }, lookOpts(look));
}

// ---- wraps, bracers, boots, gloves ---------------------------------------------------------------------------------------

/**
 * Cloth bandage wound around a forearm or shin (bone frame, around +Y; author for the R bone and putPair). Shingled
 * turns, each lapping the one below, tapering with the limb.
 * @param {object} o  y0=0.0, y1=-0.2 (extent)   r0=0.05, r1=0.04 (radius at y0 / y1; or r: fn(t))   rz=1.05 (side / front
 *   ratio)   turns=7   width (band width; default pitch x 1.5)   thick=0.0028   seg=10 (samples per turn)   ox, oz
 */
export function limbWrap(o = {}) {
  const y0 = o.y0 ?? 0, y1 = o.y1 ?? -0.2, turns = o.turns ?? 7, seg = o.seg ?? 10, n = Math.ceil(turns * seg);
  const R = typeof o.r === 'function' ? o.r : (t) => lerp(o.r0 ?? 0.05, o.r1 ?? 0.04, t);
  const rzK = o.rz ?? 1.05, pitch = Math.abs(y1 - y0) / turns, w = o.width ?? pitch * 1.55, th = o.thick ?? 0.0028, dir = Math.sign(y1 - y0) || -1;
  const across = [-0.5, -0.15, 0.3, 0.5], lift = [0.1, 0.5, 0.95, 1.0];
  const pos = [], nor = [], idx = [], cav = [];
  for (let i = 0; i <= n; i++) {
    const t = i / n, a = t * turns * Math.PI * 2, yc = lerp(y0, y1, t), c = Math.cos(a), s = Math.sin(a), r = R(t);
    for (let k = 0; k < 4; k++) {
      const rr = r + th * lift[k];
      pos.push((o.ox ?? 0) + c * rr, yc - dir * across[k] * w, (o.oz ?? 0) + s * rr * rzK);
      const tilt = k === 3 ? 0.75 : k === 0 ? -0.2 : 0.1, l = Math.hypot(tilt, 1);
      nor.push(c / l, (dir * tilt) / l * -1, s / l);
      cav.push(k === 3 ? 1.25 : k === 0 ? 0.5 : 1);
    }
  }
  for (let i = 0; i < n; i++) for (let k = 0; k < 3; k++) { const a = i * 4 + k, b = a + 1, c = a + 4, d = c + 1; idx.push(a, c, b, b, c, d); }
  return fixWinding(mk(pos, nor, idx, cav));
}

/**
 * Bracer (`foreArmTwist` frame, like armor.vambrace): a lacquered or leather forearm guard open on the inside, with
 * raised splints, two strap bands and studs.
 * @param {object} o  r=0.052   y0=0.11, y1=-0.105   splints=3   splintH=0.004   open=70 (deg gap on the inside of the arm)
 * @returns {{ plate, straps, studs }}
 */
export function bracer(o = {}) {
  const r = o.r ?? 0.052, y0 = o.y0 ?? 0.11, y1 = o.y1 ?? -0.105, ns = o.splints ?? 3, open = o.open ?? 70;
  const a0 = -90 + open / 2, a1 = 270 - open / 2;                   // the gap faces -Z (toward the body for the R arm)
  const ridges = [];
  for (let k = 0; k < ns; k++) ridges.push({ at: lerp(a0 + 50, a1 - 50, ns === 1 ? 0.5 : k / (ns - 1)), h: o.splintH ?? 0.004, w: 13, crease: false });
  const pl = hoop({
    y0, y1, a0, a1, rx: [[0, r * 1.02], [0.4, r * 1.03], [1, r * 0.82]], rz: [[0, r * 1.08], [0.4, r * 1.08], [1, r * 0.86]], n: 2.15,
    nu: 20, nv: 5, thick: 0.005, edgeR: 0.004, ridges, top: (a) => 0.016 * Math.pow(Math.max(0, Math.sin(a * DEG)), 2),
  });
  const straps = [];
  for (const v of [0.22, 0.74]) {
    const fr = [], yy = lerp(y0, y1, v), rr = lerp(r * 1.03, r * 0.84, v) + 0.0055;
    for (let i = 0; i < 20; i++) { const a = (i / 20) * Math.PI * 2, [x, z] = se(a, rr, rr * 1.05, 2.15); fr.push({ p: [x, yy, z], n: norm3([x, 0, z]) }); }
    straps.push(band(fr, { width: 0.017, closed: true, side: [0, -1, 0], thick: 0.0025, crown: 0.0006 }));
  }
  const uv = [];
  for (let k = 0; k < 5; k++) { uv.push([0.08 + k * 0.21, 0.1]); uv.push([0.08 + k * 0.21, 0.9]); }
  return { plate: pl, straps: merge(straps), studs: studs(onSurface(pl.userData, uv, -0.0006), { r: 0.0042, h: 0.003, segs: 6 }) };
}

/**
 * Cloth boot (화 / 목화) fitted to the rig's foot: soft upper over the instep, heel cup, a toe that turns up to a small
 * point (버선코), layered pale sole, and a shaft up the shin. Pass P: rig.P. Soles end 1 mm above the floor.
 * @param {object} o  P (rig proportions)   width=0.046 (half width at the ball)   upturn=0.014 (toe tip rise)
 *   shaft=0.2 (height of the shaft above the ankle; 0 = a low shoe)   shaftR=0.062   scale=1
 * @returns {{ upper, heel (foot), toe (toe), sole (foot), toeSole (toe), shaft (shin), top (shin: band frames ring at the shaft top) }}
 */
export function clothBoot(o = {}) {
  const P = o.P || {};
  const AH = P.ankleHeight ?? 0.085, FL = P.footLength ?? 0.135, FD = P.footDrop ?? 0.055, TL = P.toeLength ?? 0.08, HL = P.heelLength ?? 0.065;
  const k = o.scale ?? 1, W = (o.width ?? 0.046) * k, ST = 0.012, yb = -AH + ST, up = o.upturn ?? 0.014;
  const top = (x) => lerp(0.02 * k, -FD + 0.034 * k, sstep(-0.01, FL + 0.01, x));
  const half = (x) => lerp(W * 0.9, W, sstep(0, FL, x));
  const arch = (x, t, base, h, w) => { const a = (t * Math.PI) / 2, c = Math.cos(a), s = Math.sin(a), e = 2 / 2.4; return [x, base + h * Math.pow(Math.abs(c), e), w * Math.sign(s) * Math.pow(Math.abs(s), e)]; };
  const upper = plate((u, v) => { const x = lerp(-0.012, FL + 0.004, v); return arch(x, u * 2 - 1, yb, top(x) - yb + 0.002 * Math.sin(v * 16) * (1 - v), half(x)); },
    { nu: 10, nv: 6, thick: 0, out: (p) => [0, p[1] - yb, p[2]], curv: 0.002 });
  const heel = hoop({ y0: top(0) + 0.012 * k, y1: yb, a0: 80, a1: 280, rx: [[0, HL * 0.74], [1, HL * 0.86]], rz: [[0, W * 0.84], [1, W * 0.93]], ox: -0.004, n: 2.3, nu: 10, nv: 3, thick: 0 });
  const ytb = -(AH - FD) + ST, xs = -0.006, xt = TL + 0.004, h0 = top(FL) + FD - ytb;
  const toe = plate((u, v) => {
    const x = lerp(xs, xt, v), q = clamp((x - TL * 0.2) / (xt - TL * 0.2), 0, 1), taper = lerp(Math.sqrt(Math.max(0, 1 - q * q)), 1 - q, 0.4);
    const h = h0 * lerp(1, 0.5, sstep(xs, xt, x)) * lerp(1, Math.max(taper, 0.3), 0.55);
    const p = arch(x, u * 2 - 1, ytb + up * q * q, h, W * Math.max(taper, 0.01));
    return p;
  }, { nu: 10, nv: 5, thick: 0, out: (p) => [0.3, p[1] - ytb, p[2]], curv: 0.002 });
  const outline = (x0, x1, wf, m) => { const A = [], B = []; for (let i = 0; i <= m; i++) { const x = lerp(x0, x1, i / m), w = wf(x); A.push([x, -w]); B.push([x, w]); } return [...A, ...B.reverse()]; };
  const sole = extrude(outline(-HL * 0.9, FL - 0.002, (x) => (x < -HL * 0.45 ? half(0) * 0.82 * Math.sqrt(Math.max(0.15, 1 - ((x + HL * 0.45) / (HL * 0.45)) ** 2)) : half(x)) + 0.004, 6), { depth: ST - 0.002, bevel: 0.002, bevelSegs: 1 });
  sole.rotateX(-90 * DEG); sole.translate(0, -AH + ST / 2 + 0.002, 0);
  const toeSole = extrude(outline(-0.004, xt - 0.004, (x) => { const q = clamp((x - TL * 0.2) / (xt - TL * 0.2), 0, 1); return W * Math.max(0.14, lerp(Math.sqrt(Math.max(0, 1 - q * q)), 1 - q, 0.4)) + 0.004; }, 5), { depth: ST - 0.002, bevel: 0.002, bevelSegs: 1 });
  toeSole.rotateX(-90 * DEG); toeSole.translate(0, -(AH - FD) + ST / 2 + 0.002, 0);
  const out = { upper, heel, toe, sole, toeSole };
  const sh = o.shaft ?? 0.2;
  if (sh > 0) {
    const r = (o.shaftR ?? 0.062) * k, leg = (P.hipHeight ?? 0.98) - AH, shin = leg * (1 - (P.thighRatio ?? 0.52));
    // shin frame: the ankle is at y = -shin
    out.shaft = hoop({
      y0: -shin + sh, y1: -shin - 0.012, closed: true, rx: [[0, r * 1.06], [0.5, r * 0.9], [1, r * 0.82]], rz: [[0, r * 1.02], [0.5, r * 0.86], [1, r * 0.8]], ox: [[0, -0.006], [1, 0.004]], n: 2.1,
      bulge: (u, v) => 0.003 * Math.sin(v * 22 + u * 4) * sstep(0.35, 1, v), nu: 14, nv: 8, thick: 0, curv: 0.002,
    });
    const fr = [], F = out.shaft.userData.normalAt;
    for (let i = 0; i < 20; i++) { const f = F(i / 20, 0.001); fr.push({ p: f.p, n: f.n }); }
    out.top = band(fr, { width: 0.03, closed: true, shift: 0.5, side: [0, -1, 0], thick: 0.003, crown: 0.001, code: o.motif ?? 0 });
  }
  return out;
}

/**
 * Soft glove / wrapped hand (hand, fingers, fingerTips, thumb frames of the R side; mirror with putPair): a rounded
 * palm block, four fingers in two segments and a thumb. ~0.5k triangles per hand.
 * @returns {{ palm, fingers, tips, thumb, wrist }}
 */
export function glove(o = {}) {
  const k = o.scale ?? 1, out = {};
  out.wrist = hoop({ y0: 0.04, y1: -0.03, closed: true, rx: [[0, 0.04 * k], [1, 0.043 * k]], rz: [[0, 0.043 * k], [1, 0.046 * k]], n: 2.1, nu: 12, nv: 2, thick: 0 });
  out.palm = hoop({ y0: -0.012, y1: -0.102, closed: true, rx: [[0, 0.041 * k], [0.5, 0.047 * k], [1, 0.044 * k]], rz: [[0, 0.03 * k], [0.5, 0.031 * k], [1, 0.026 * k]], oz: -0.005, n: 2.5, nu: 12, nv: 3, thick: 0.002, edge: 'round', edgeR: 0.012, edgeSegs: 2 });
  const fingers = [], tips = [];
  for (let f = 0; f < 4; f++) {
    const x = 0.027 - f * 0.018, w = (f === 3 ? 0.0084 : 0.0096) * k;
    fingers.push(hoop({ y0: 0.008, y1: -0.05, closed: true, rx: w, rz: 0.0108 * k, ox: x, n: 2.3, nu: 6, nv: 1, thick: 0 }));
    tips.push(lathe([[0, 0.006], [w, 0.004], [w * 0.94, -0.03 + f * 0.002], [w * 0.5, -0.04 + f * 0.002], [0, -0.042 + f * 0.002]], { segs: 6 }).translate(x, 0, 0));
  }
  out.fingers = merge(fingers);
  out.tips = merge(tips);
  out.thumb = sweep(curve([[0, 0.006, 0], [0.012, -0.03, -0.006], [0.019, -0.062, -0.012]], 5), circle(6), { scale: (t) => [0.0128 * k - t * 0.004, 0.0112 * k - t * 0.003], caps: true });
  return out;
}

// ---- lamellar (찰갑) -----------------------------------------------------------------------------------------------------

/**
 * Rows of laced lamellar plates on a hoop sector around +Y (any bone frame): each row a thin strip of plates leaning
 * out at its lower rim, the next row tucked under it. The `lamellar` uv set draws the plates and the lacing; pass
 * `code` (0..0.95) to let inner energy glow through the cords.
 * @param {object} o  rows=4   rowH=0.04   lap=0.28 (overlap, share of rowH)   y0=0 (top)   a0=-70, a1=70 (deg)
 *   rx=0.15, rz=0.19 (top radii; numbers or fn(row))   ox=0, oz=0   n=2.2   flare=0.004 (radius gained per row)
 *   lean=0.005 (lower rim stands off)   plateW=0.024   scallop=true (rounded plate ends cut into the lower rim)
 *   thick=0.003   code=0   closed=false
 * @returns geometry[] (one per row, top to bottom) with `uvw`
 */
export function lamellarRows(o = {}) {
  const rows = o.rows ?? 4, H = o.rowH ?? 0.04, lap = o.lap ?? 0.28, y0 = o.y0 ?? 0, a0 = o.a0 ?? -70, a1 = o.a1 ?? 70;
  const closed = !!o.closed, flare = o.flare ?? 0.004, lean = o.lean ?? 0.005, pw = o.plateW ?? 0.024, code = o.code ?? 0;
  const RX = typeof o.rx === 'function' ? o.rx : () => o.rx ?? 0.15, RZ = typeof o.rz === 'function' ? o.rz : () => o.rz ?? 0.19;
  const out = [];
  for (let r = 0; r < rows; r++) {
    const yt = y0 - r * H * (1 - lap), rx = RX(r) + flare * r, rz = RZ(r) + flare * r;
    // arc length of the sector (ellipse approximation) -> whole plates
    const arc = ((a1 - a0) * DEG) * Math.sqrt((rx * rx + rz * rz) / 2), plates = Math.max(2, Math.round(arc / pw));
    const sc = o.scallop === false ? 0 : 0.2 * H;
    // uv: 4 plates per u unit, 2 rows per v unit; odd rows shift half a plate (as the texture's second row does)
    const g = hoop({
      y0: yt, y1: yt - H, a0, a1, closed, rx: [[0, rx], [1, rx + lean]], rz: [[0, rz], [1, rz + lean]], ox: o.ox ?? 0, oz: o.oz ?? 0, n: o.n ?? 2.2,
      bot: sc ? (a) => { const f = ((((a - a0) / (a1 - a0)) * plates + (r & 1) * 0.5) % 1 + 1) % 1; return sc * Math.pow(Math.abs(2 * f - 1), 2.4); } : undefined,
      nu: Math.min(96, plates * (sc ? 3 : 1)), nv: 2, thick: o.thick ?? 0.003, edgeSegs: 2, edgeR: 0.002, curv: 0.002, edgeWear: 0.5,
      occ: (u, v) => 0.55 + 0.45 * sstep(0.0, 0.5, v),
      uvw: (u, v) => [(u * plates) / 4, (r & 1) * 0.5 + v * 0.5, code],
    });
    out.push(g);
  }
  return out;
}

/**
 * Lamellar cuirass rows around the torso (bind space, skinned through the tailor): a wrap of laced rows from under the
 * arms to the waist, open at one side, plus optional breast rows that climb the chest between the armholes.
 * @param {object} T  tailor()
 * @param {object} o  yTop=0.07, yBot=-0.17 (chest frame x body scale)   rowH=0.042   grow=0.022   gap=0 (deg opening at
 *   `gapAt`=-90)   breast=2 (extra rows above yTop, front only: a0..a1 = -58..58)   back=0 (same on the back)
 *   plateW=0.025   code=0   lap=0.28
 * @returns geometry (merged rows) with `uvw` and skin weights (T.put)
 */
export function lamellarCuirass(T, o = {}) {
  const K = T.K, H = (o.rowH ?? 0.042) * K, lap = o.lap ?? 0.28, grow = o.grow ?? 0.022, pw = (o.plateW ?? 0.025) * K, code = o.code ?? 0;
  const yTop = (o.yTop ?? 0.07) * K, yBot = (o.yBot ?? -0.17) * K, step = H * (1 - lap);
  const parts = [];
  const row = (yt, a0, a1, r, closed) => {
    const mid = T.at(0, yt - H / 2, grow).p, side = T.at(90, yt - H / 2, grow).p;
    const arc = ((a1 - a0) * DEG) * Math.sqrt(((mid[0] - T.c[0]) ** 2 + (side[2] - T.c[2]) ** 2) / 2), plates = Math.max(2, Math.round(arc / pw));
    const sc = 0.2 * H;
    const S = (u, v) => {
      const a = lerp(a0, a1, u), f = ((u * plates + (r & 1) * 0.5) % 1 + 1) % 1;
      const yb = yt - H + sc * Math.pow(Math.abs(2 * f - 1), 2.4);
      return T.at(a, lerp(yt, yb, v), grow + 0.005 * v).p;
    };
    const g = plate(S, {
      nu: Math.min(110, plates * 3), nv: 2, thick: 0.003, closeU: closed, edgeSegs: 2, edgeR: 0.002, axis: [T.c[0], T.c[2]], curv: 0.002, edgeWear: 0.5,
      occ: (u, v) => 0.55 + 0.45 * sstep(0, 0.5, v), uvw: (u, v) => [(u * plates) / 4, (r & 1) * 0.5 + v * 0.5, code],
    });
    parts.push(g);
  };
  let r = 0;
  const gap = o.gap ?? 0, ga = o.gapAt ?? -90;
  for (let k = (o.breast ?? 2); k >= 1; k--) row(yTop + k * step, -58 + (k - 1) * 6, 58 - (k - 1) * 6, r++, false);
  const backRows = o.back ?? 0, r0 = r;
  for (let yt = yTop; yt - H >= yBot - 1e-6; yt -= step) row(yt, gap ? ga + gap / 2 : -180, gap ? ga + 360 - gap / 2 : 180, r++, !gap);
  for (let k = backRows; k >= 1; k--) row(yTop + k * step, 122 + (k - 1) * 6, 238 - (k - 1) * 6, r0 - k + 100, false);
  return merge(parts);
}

/**
 * Beast-face pauldron (수면 견갑), `deltoidR` frame (origin = shoulder joint; mirror() for the left): a domed cap sculpted
 * into a guardian beast's face looking out from the shoulder — furrowed brows, deep eye pits, a broad snout over bared
 * fangs, a ruff of mane lappets around the rim — with glowing eyes and a ring in its jaws.
 * @param {object} o  R=0.12 (cap radius)   tilt=30 (deg outward)   relief=1 (sculpt depth)   mane=10 (lappets)
 *   nu=40, nv=18   fangs=true   ring=true
 * @returns {{ cop, eyes, pits, fangs, ring, S }}  cop = the face plate, eyes = glow lozenges (eye look), pits = dark sockets
 */
export function beastPauldron(o = {}) {
  const R = o.R ?? 0.12, tilt = (o.tilt ?? 30) * DEG, rel = (o.relief ?? 1) * R, nM = o.mane ?? 10;
  const cy = 0.012, cz = -0.006, th1 = 1.36;
  // cap frame: axis d (up, tilted outward), e1 = +X (the face's left-right), e2 = outward-down (the face's chin)
  const d = [0, Math.cos(tilt), Math.sin(tilt)], e2 = [0, -d[2], d[1]];
  // sculpt: height over the dome as a function of face coordinates (p along e1, q along e2), in cap radians
  const bump = (p, q, p0, q0, sp, sq) => Math.exp(-(((p - p0) / sp) ** 2) - (((q - q0) / sq) ** 2));
  const face = (p, q) => {
    const ap = Math.abs(p);
    let h = 0;
    h += 0.16 * bump(ap, q, 0.3, -0.36 + 0.3 * ap, 0.3, 0.1);            // brows, pulled down toward the middle (a scowl)
    h += 0.07 * bump(p, q, 0, -0.58, 0.16, 0.2);                          // forehead knot
    h -= 0.13 * bump(ap, q, 0.33, -0.13, 0.13, 0.085);                    // eye pits
    h += 0.2 * bump(p, q, 0, 0.12, 0.2, 0.26);                            // snout
    h += 0.09 * bump(ap, q, 0.13, 0.3, 0.075, 0.07);                      // nostrils
    h += 0.1 * bump(ap, q, 0.52, 0.1, 0.17, 0.2);                         // cheeks
    h += 0.07 * bump(ap, q, 0.3, 0.52, 0.22, 0.06);                       // upper lip curling off the fangs
    h -= 0.05 * bump(p, q, 0, 0.42, 0.05, 0.1);                           // philtrum
    return h;
  };
  const S = (u, v) => {
    const ph = lerp(-180, 180, u) * DEG, th = lerp(0.02, th1, v);
    const p = th * Math.cos(ph), q = th * Math.sin(ph);
    // mane: lappets around the rim (scalloped, fluted)
    const lob = Math.pow(Math.abs(Math.sin(ph * nM / 2 + 0.4)), 0.6);
    const rim = sstep(0.82, 1.2, th);
    const r = R + rel * face(p, q) * (1 - 0.8 * rim) + 0.012 * rim * lob;
    const thx = th + 0.1 * rim * lob;
    const s = Math.sin(thx) * r, c = Math.cos(thx) * r, a = Math.cos(ph) * s * 1.12, b = Math.sin(ph) * s;
    return [a, cy + b * e2[1] + c * d[1], cz + b * e2[2] + c * d[2]];
  };
  const cop = plate(S, { closeU: true, nu: o.nu ?? 40, nv: o.nv ?? 18, thick: 0.007, edgeR: 0.005, edge: { v0: 'none' }, out: (p) => [p[0], p[1] - cy, p[2] - cz], curv: 0.005 });
  const F = cop.userData.normalAt;
  const uvOf = (p, q) => [(Math.atan2(q, p) / DEG + 180) / 360, (Math.hypot(p, q) - 0.02) / (th1 - 0.02)];
  const out = { cop, S: cop.userData };
  // eyes: dark almond pits with a glowing slit
  const pits = [], eyes = [];
  for (const sg of [1, -1]) {
    const f = F(...uvOf(sg * 0.33, -0.13));
    // eye frame on the surface: t along the eye (slanted toward the brow's scowl), b across it
    const t = new THREE.Vector3(1, 0, 0).applyAxisAngle(f.n, sg * 0.4); t.addScaledVector(f.n, -t.dot(f.n)).normalize();
    const b = new THREE.Vector3().crossVectors(f.n, t), M = new THREE.Matrix4().makeBasis(t, f.n, b);
    const almond = (w, h, lift) => { const g = lathe([[0, 0.0016], [w * 0.6, 0.0013], [w, 0]], { segs: 10 }); g.scale(1, 1, h / w); g.applyMatrix4(M); g.translate(f.p.x + f.n.x * lift, f.p.y + f.n.y * lift, f.p.z + f.n.z * lift); return g; };
    pits.push(almond(0.021, 0.011, 0.0008));
    eyes.push(almond(0.013, 0.0042, 0.0022));
  }
  out.pits = merge(pits); out.eyes = merge(eyes);
  if (o.fangs !== false) {
    const fg = [];
    for (const [p, q, len, r] of [[0.27, 0.55, 0.034, 0.0075], [-0.27, 0.55, 0.034, 0.0075], [0.11, 0.56, 0.018, 0.005], [-0.11, 0.56, 0.018, 0.005], [0.0, 0.57, 0.014, 0.0045]]) {
      const f = F(...uvOf(p, q)), dn = new THREE.Vector3(...e2).multiplyScalar(0.8).addScaledVector(f.n, 0.45).normalize();
      const g = lathe([[r, 0], [r * 0.8, len * 0.45], [r * 0.3, len * 0.9], [0, len]], { segs: 6 });
      g.applyQuaternion(new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(0, 1, 0), dn));
      g.translate(f.p.x - f.n.x * 0.002, f.p.y - f.n.y * 0.002, f.p.z - f.n.z * 0.002);
      fg.push(g);
    }
    out.fangs = merge(fg);
  }
  if (o.ring !== false) {
    const f = F(...uvOf(0, 0.44)), c = f.p.clone().addScaledVector(f.n, 0.008).addScaledVector(new THREE.Vector3(...e2), 0.03), rr = 0.03;
    const pts = [];
    for (let i = 0; i < 18; i++) { const a = (i / 18) * Math.PI * 2; pts.push([c.x + Math.cos(a) * rr, c.y + e2[1] * Math.sin(a) * rr + f.n.y * 0.004 * Math.cos(a) * 0, c.z + e2[2] * Math.sin(a) * rr]); }
    out.ring = sweep(pts, circle(6), { scale: 0.0052, closed: true, up: [f.n.x, f.n.y, f.n.z] });
  }
  return out;
}

/**
 * Lamellar shoulder guard (`deltoidR` frame): laced rows wrapped around the outside of the upper arm under a
 * lacquered cap, open toward the body. Pair it with a beastPauldron() on the other shoulder, or wear two.
 * @param {object} o  R=0.085 (arm radius it wraps)   rows=3   rowH=0.046   y0=-0.02   code=0   cap=true
 * @returns {{ rows: geometry[], cap }}
 */
export function lamellarSpaulder(o = {}) {
  const R = o.R ?? 0.085, rows = lamellarRows({ rows: o.rows ?? 3, rowH: o.rowH ?? 0.046, y0: o.y0 ?? -0.02, a0: -62, a1: 242, rx: R * 0.96, rz: R, oz: 0.012, flare: 0.006, lean: 0.007, plateW: o.plateW ?? 0.024, code: o.code ?? 0 });
  const out = { rows };
  if (o.cap !== false) {
    // lacquered cap over the top of the shoulder
    out.cap = plate((u, v) => {
      const ph = lerp(-180, 180, u) * DEG, th = lerp(0.04, 1.3, v), r = R * 1.2, s = Math.sin(th) * r;
      return [Math.cos(ph) * s * 1.1, Math.cos(th) * r * 0.72 - 0.012, 0.012 + Math.sin(ph) * s];
    }, { closeU: true, nu: 20, nv: 6, thick: 0.006, edgeR: 0.004, edge: { v0: 'none' }, roll: { v1: 0.004 }, out: (p) => [p[0], p[1] + 0.06, p[2] - 0.012], curv: 0.004 });
  }
  return out;
}

/**
 * Waist guard (요갑), authored on a tasset bone at the top of the panel (a `tasset*` bone follows its thigh): a hanging
 * panel of lamellar rows under a leather head band, finished with a trim band.
 * @param {object} o  rows=4   rowH=0.046   w (deg sector) a0=-36, a1=62   r=0.155   cx=-0.075, cz=-0.01   code=0   motif=0
 * @returns {{ rows: geometry[], head, trim }}
 */
export function waistGuard(o = {}) {
  const r = o.r ?? 0.155, a0 = o.a0 ?? -36, a1 = o.a1 ?? 62, ox = o.cx ?? -0.075, oz = o.cz ?? -0.01, n = o.rows ?? 4, H = o.rowH ?? 0.046;
  const rows = lamellarRows({ rows: n, rowH: H, y0: -0.022, a0, a1, rx: r, rz: r, ox, oz, n: 2, flare: 0.004, plateW: o.plateW ?? 0.024, code: o.code ?? 0 });
  const ring = (y, grow) => { const fr = []; for (let i = 0; i <= 14; i++) { const a = lerp(a0 - 2, a1 + 2, i / 14) * DEG; fr.push({ p: [ox + Math.cos(a) * (r + grow), y, oz + Math.sin(a) * (r + grow)], n: [Math.cos(a), 0, Math.sin(a)] }); } return fr; };
  const yb = -0.022 - (n - 1) * H * 0.72 - H;
  return {
    rows,
    head: band(ring(-0.004, 0.004), { width: 0.04, side: [0, -1, 0], thick: 0.004, crown: 0.001 }),
    trim: band(ring(yb + 0.012, 0.006 + 0.004 * n), { width: 0.026, side: [0, -1, 0], thick: 0.003, crown: 0.001, code: o.motif ?? 0 }),
  };
}

// ---- hanging ornaments (authored hanging down -Y from the origin; put them on the last bone of a hang() chain) -----------

/**
 * Tassel (술): a bound head and a skirt of strands (hair uv set; cut-out slot for wispy ends).
 * @param {object} o  len=0.09   r=0.011 (skirt radius at the binding)   flare=1.5   strands=9   head=0.008 (bead radius)   thin=0.55
 * @returns {{ head, strands }}
 */
export function tassel(o = {}) {
  const len = o.len ?? 0.09, r = o.r ?? 0.011, n = o.strands ?? 9, hd = o.head ?? 0.008, fl = o.flare ?? 1.5;
  const head = lathe([[0, hd * 1.2], [hd * 0.7, hd * 0.9], [hd, 0], [hd * 0.8, -hd * 0.9], [r * 0.9, -hd * 1.5], [r, -hd * 2.2], [r * 0.9, -hd * 2.6]], { segs: 8 });
  const st = [];
  for (let k = 0; k < n; k++) {
    const a = (k / n) * Math.PI * 2 + 0.3, c = Math.cos(a), s = Math.sin(a), y0 = -hd * 2.2;
    st.push(ribbon([[c * r * 0.9, y0, s * r * 0.9], [c * r * (1 + 0.5 * (fl - 1)), y0 - len * 0.5, s * r * (1 + 0.5 * (fl - 1))], [c * r * fl, y0 - len * (0.9 + 0.1 * Math.sin(k * 2.4)), s * r * fl]],
      { width: (t) => r * 1.5 * (1 - 0.25 * t), normal: [c, 0, s], camber: 0.2, nu: 2, u0: k * 0.37, du: 0.35, code: o.thin ?? 0.55 }));
  }
  return { head, strands: merge(st) };
}

/**
 * Jade pendant (노리개): cord, a decorative knot, a jade ring and a tassel. Hangs 0.2 m by default.
 * @param {object} o  ring=0.024 (jade ring radius)   cord=0.05   tassel=0.085
 * @returns {{ cord, knot, jade, tasselHead, strands }}
 */
export function pendant(o = {}) {
  const rr = o.ring ?? 0.024, cl = o.cord ?? 0.05, tl = o.tassel ?? 0.085;
  const cord = sweep([[0, 0, 0], [0, -cl, 0]], circle(5), { scale: 0.0022, caps: true });
  const yk = -cl - 0.012;
  const knotG = merge([0, 1, 2].map((k) => { const a = k * Math.PI / 1.5; const pts = []; for (let i = 0; i < 10; i++) { const t = (i / 10) * Math.PI * 2; pts.push([Math.cos(a) * 0.006 + Math.cos(t) * 0.009 * Math.cos(a), yk + Math.sin(t) * 0.011, Math.sin(a) * 0.006 + Math.cos(t) * 0.009 * Math.sin(a)]); } return sweep(pts, circle(4), { scale: 0.0026, closed: true }); }));
  const yj = yk - 0.014 - rr;
  const jade = lathe([[rr * 0.42, 0.003], [rr * 0.6, 0.0052], [rr * 0.9, 0.0048], [rr, 0.0015], [rr, -0.0015], [rr * 0.9, -0.0048], [rr * 0.6, -0.0052], [rr * 0.42, -0.003], [rr * 0.42, 0.003]], { segs: 18, auto: false });
  jade.rotateX(90 * DEG); jade.translate(0, yj, 0);
  const T = tassel({ len: tl, r: 0.009, strands: 8 });
  const ty = yj - rr - 0.012;
  T.head.translate(0, ty, 0); T.strands.translate(0, ty, 0);
  return { cord, knot: knotG, jade, tasselHead: T.head, strands: T.strands, length: -ty + tl + 0.02 };
}

/**
 * Gourd bottle (호리병) on a cord: two bulbs, a stopper and a waist cord. Hangs from its strap at the origin.
 * @param {object} o  size=0.085 (height)
 * @returns {{ body, stopper, cord }}
 */
export function gourd(o = {}) {
  const s = (o.size ?? 0.085) / 0.085, y0 = -0.03;
  const prof = [[0, 0.0], [0.012, -0.002], [0.016, -0.012], [0.02, -0.022], [0.0185, -0.031], [0.0135, -0.038], [0.013, -0.042], [0.021, -0.05], [0.029, -0.062], [0.0305, -0.074], [0.026, -0.085], [0.014, -0.092], [0, -0.094]].map(([r, y]) => [r * s, y0 + y * s]);
  const body = lathe(prof, { segs: 14 });
  const stopper = lathe([[0, y0 + 0.014 * s], [0.006 * s, y0 + 0.013 * s], [0.0075 * s, y0 + 0.004 * s], [0.0105 * s, y0 + 0.002 * s], [0.0105 * s, y0 - 0.001 * s]], { segs: 8 });
  const ring = []; for (let i = 0; i < 12; i++) { const a = (i / 12) * Math.PI * 2; ring.push([Math.cos(a) * 0.0145 * s, y0 - 0.04 * s, Math.sin(a) * 0.0145 * s]); }
  const cord = merge([sweep(ring, circle(4), { scale: 0.0024, closed: true }), sweep([[0, 0, 0], [0.006, y0 * 0.5, 0], [0.013 * s, y0 - 0.036 * s, 0]], circle(4), { scale: 0.002, caps: true }), sweep([[0, 0, 0], [-0.006, y0 * 0.5, 0], [-0.013 * s, y0 - 0.036 * s, 0]], circle(4), { scale: 0.002, caps: true })]);
  return { body, stopper, cord };
}

/**
 * Spear tassel (창영): a bronze collar and a thick fall of horsehair around the shaft, skinned to a hang() chain on the
 * weapon bone (hang('tassel', 'weaponR', [x, 0, 0], { dir: [-1, 0, 0], n: 2, len: 0.2 })) so it trails the spear head.
 * Authored in the WEAPON frame (+X toward the tip); strands hang back along the shaft from x.
 * @param {object} kit
 * @param {object} H   hang() chain rooted on the weapon bone at the collar
 * @param {object} o   r=0.021 (shaft radius + cover)   len=H.len   strands=14   layers=2   flare=2.2   thin=0.45
 * @returns {{ collar (rigid: put on the weapon bone), strands (skinned: weightsOf(strands.userData.W), bind space) }}
 */
export function spearTassel(kit, H, o = {}) {
  const r = o.r ?? 0.021, len = o.len ?? H.len, n = o.strands ?? 14, layers = o.layers ?? 2, fl = o.flare ?? 2.2;
  const x0 = H.at[0];
  const collar = lathe([[r * 0.9, -0.012], [r * 1.1, -0.009], [r * 1.18, 0], [r * 1.1, 0.009], [r * 0.9, 0.012]], { segs: 12 });
  collar.rotateZ(-90 * DEG); collar.translate(x0 + 0.004, 0, 0);
  // strands are built in the weapon bone's bind frame: positions from the chain's bind path
  const rig = kit.rig, bi = rig.index[H.parent], m = new THREE.Matrix4().fromArray(kit.bind.matrices, bi * 16);
  const st = [];
  for (let L = 0; L < layers; L++) for (let k = 0; k < n; k++) {
    const a = ((k + 0.5 * L) / n) * Math.PI * 2, c = Math.cos(a), s = Math.sin(a), ll = len * (1 - 0.2 * L) * (0.88 + 0.12 * Math.sin(k * 3.1 + L));
    const rr = r * (1.05 + 0.25 * L), pts = [];
    for (let i = 0; i <= 4; i++) { const t = i / 4, e = rr * (1 + (fl - 1) * Math.pow(t, 0.8)); pts.push(new THREE.Vector3(x0 - t * ll, c * e, s * e).applyMatrix4(m)); }
    const nrm = new THREE.Vector3(0, c, s).transformDirection(m);
    st.push(ribbon(pts, { width: (t) => rr * 2.6 * (1 - 0.3 * t) * (Math.PI / n) * 2.2, normal: [nrm.x, nrm.y, nrm.z], camber: 0.16, nu: 2, u0: k * 0.31 + L * 0.5, du: 0.4, code: o.thin ?? 0.45, weights: (t) => chainWeights(H, t * (ll / H.len), 0.06) }));
  }
  return { collar, strands: merge(st) };
}

export { place, mirror };
