// The stone of 「천무대」: the raised court around the round terrace (a carved retaining wall under a lotus-post
// balustrade, broken at the vista shoulders and breached on the east side), the two recessed stair flights, the
// court's paving, the cliff under the fallen rim, the last posts of the rim's own balustrade, rubble, and the
// shattered slabs around the old impact. Goes into C.S (see ruins.js for the build context C).

import * as THREE from 'three';
import { DEG, smoothstep, clamp } from '../core/math.js';
import { chamferBox, ashlar, latheGrid, rock, addAll, trs, noise3, fbm3, flatNormals, setOrnUv, frontFace, sweep, arcPath, brokenBlock, prism, ringM, tube } from './geometry.js';
import { LAYOUT, STAIRS, IMPACT, rimR } from './config.js';
import { ORN, panel } from './ornament.js';

const V = (x, y, z) => new THREE.Vector3(x, y, z);
const ringPos = (r, th, y = 0) => V(r * Math.sin(th), y, -r * Math.cos(th));
const T = (m, x, y, z, ry = 0, rx = 0, rz = 0, s = 1) => m.clone().multiply(trs(x, y, z, ry, rx, rz, s));
const wrap = (a) => Math.atan2(Math.sin(a), Math.cos(a));

/** Lotus-bud finial on a post top (보주). */
function finial(C, m, s = 1) {
  const g = latheGrid({ rows: 4, segs: 6, profile: (t) => [s * (t < 0.2 ? 0.06 : 0.035 + 0.075 * Math.sin(Math.pow((t - 0.2) / 0.8, 0.8) * Math.PI)), t * 0.24 * s], capTop: true });
  addAll(C.S, g, m, C.st(1));
}
/** Balustrade post (동자주) with its finial; `h` < full height: broken stub. */
function post(C, m, h, full) {
  const tint = C.blockTint();
  if (h < full - 0.05) { C.S.add(brokenBlock(0.2, h, 0.2, C.rng, { jag: 0.35, nx: 1, nz: 1 }), T(m, 0, h / 2, 0), C.st(tint)); return; }
  C.S.add(C.tier.detail >= 2 ? chamferBox(0.2, h, 0.2, 0.025, C.rng, 0.3) : new THREE.BoxGeometry(0.2, h, 0.2), T(m, 0, h / 2, 0), C.st(tint));
  C.S.add(new THREE.BoxGeometry(0.26, 0.05, 0.26), T(m, 0, h + 0.02, 0), C.st(tint));
  finial(C, T(m, 0, h + 0.04, 0));
}
/** Rails and the carved panel between two post positions (world points on the post axes at the rail base height). */
function railSpan(C, a, b, cell) {
  const L = a.distanceTo(b) - 0.2;
  const mid = a.clone().add(b).multiplyScalar(0.5);
  const yaw = Math.atan2(-(b.z - a.z), b.x - a.x);
  const m = trs(mid.x, mid.y, mid.z, yaw);
  const tint = C.blockTint();
  addAll(C.S, [tube([V(-L / 2, 0.86, 0), V(L / 2, 0.86, 0)], 0.062, { sides: 6 })], m, C.st(tint));
  const g = new THREE.BoxGeometry(L, 0.42, 0.075);
  setOrnUv(g, (p, n) => (Math.abs(n.z) > 0.9 ? [Math.sign(n.z) * p.x / 0.42, p.y / 0.42 + 0.5, 1] : null));
  C.S.add(g, T(m, 0, 0.5, 0), C.st(tint * 0.95, { orn: { cell, amount: C.erosion() * 1.05, su: cell === ORN.wave ? 2 : 1, sv: cell === ORN.wave ? 2 : 1 } }));
  C.S.add(new THREE.BoxGeometry(L, 0.11, 0.13), T(m, 0, 0.2, 0), C.st(tint));
}

/**
 * @param {object} C build context
 * @returns {{ segments: Array<[number, number]>, stairs: Array }}  wall segments (radians) and stair descriptors
 */
export function buildTerrace(C) {
  const { S, rng, tier } = C;
  const { wallR, platY, railH, gap, wallFrom, outerR } = LAYOUT;
  const hi = tier.detail >= 2, mid = tier.detail >= 1;

  // ---- where the wall runs: all the way round except the vista, the two stair mouths and the east breach ---------------
  const mouths = STAIRS.map((s) => ({ ...s, half: Math.asin((s.width / 2 + 0.38) / wallR) }));
  const breach = [97 * DEG, 109 * DEG];
  const inMouth = (th) => mouths.some((s) => Math.abs(wrap(th - s.th)) < s.half);
  const segs = [];
  {
    // cut the circle at the mouths
    const cuts = [[-wallFrom, wallFrom]];
    for (const s of mouths) cuts.push([wrap(s.th) - s.half, wrap(s.th) + s.half]);
    // unwrap into [wallFrom, 2 pi - wallFrom]
    const lo = wallFrom, hiA = Math.PI * 2 - wallFrom;
    const holes = cuts.slice(1).map(([a, b]) => { const c = ((a + b) / 2 + Math.PI * 2) % (Math.PI * 2); const h = (b - a) / 2; return [c - h, c + h]; }).sort((p, q) => p[0] - q[0]);
    let cur = lo;
    for (const [a, b] of holes) { if (a > cur) segs.push([cur, a]); cur = b; }
    if (cur < hiA) segs.push([cur, hiA]);
  }
  const capProf = [[0, 0], [0.1, 0], [0.17, 0.06], [0.17, 0.24], [0.11, 0.32], [-0.9, 0.32]];
  const capOrn = { 2: [0, 1, ORN.meander, 1 / 0.3] };
  const panelCells = [ORN.cloudPanel, ORN.wave, panel(ORN.lotus), ORN.dragon, ORN.cloudPanel, panel(ORN.peony), ORN.wave, panel(ORN.crest)];
  const railCells = [ORN.cloud, ORN.meander, ORN.wave, ORN.cloud, ORN.bars];
  let bayK = 0;
  const postAt = [];        // balustrade post slots: { th, state: 'ok' | 'stub' | 'none' }
  S.section('wall');
  for (const [a0, a1] of segs) {
    const n = Math.max(1, Math.round(((a1 - a0) * wallR) / 2.05));
    const dth = (a1 - a0) / n;
    for (let k = 0; k < n; k++) {
      const t0 = a0 + k * dth, t1 = t0 + dth, tc = wrap((t0 + t1) / 2);
      const w = dth * wallR;
      bayK++;
      const tcu = ((tc + Math.PI * 2) % (Math.PI * 2));
      const inBreach = tcu > breach[0] && tcu < breach[1];
      const nearShoulder = Math.abs(tc) < wallFrom + 7 * DEG;
      // shoulder: the courses step down toward the vista; breach: only the footing survives
      const courses = inBreach ? 1 : nearShoulder ? clamp(Math.round(1 + ((Math.abs(tc) - wallFrom) / (7 * DEG)) * 3 + rng.range(-0.4, 0.4)), 1, 3) : rng.chance(0.07) ? 2 : 3;
      const tint = C.blockTint();
      const m = (r, y, yaw = 0) => ringM(r, tc, y, yaw + rng.range(-0.006, 0.006));
      // footing
      S.add(ashlar(w - 0.02, 0.2, 0.5, 0.03, rng, 0.2, { top: true, ends: courses < 3 }), m(wallR + 0.19, 0.1), C.st(tint * 0.95));
      if (courses >= 2) {
        const full = courses === 3;
        const pw = w - 0.34, ph = 0.92;
        const cell = panelCells[bayK % panelCells.length];
        const isPanel = cell >= 32;
        const g = full ? ashlar(pw, ph, 0.4, 0.03, rng, 0.12, { ends: true }) : brokenBlock(pw, ph * rng.range(0.5, 0.9), 0.4, rng, { jag: 0.5, nx: 3, nz: 1 });
        const orn = full ? { cell, amount: C.erosion(), su: isPanel ? Math.max(1, Math.round(pw / ph)) : cell === ORN.wave ? pw / 0.46 : cell === ORN.dragon ? Math.max(1, Math.round(pw / 1.3)) : 1, sv: cell === ORN.wave ? 2 : 1, fn: frontFace(pw, ph) } : null;
        const y = full ? 0.2 + ph / 2 : 0.2 + ph * 0.35;
        S.add(g, ringM(wallR + 0.23, tc + 0.17 / wallR, y), C.st(tint, orn ? { orn } : {}));
        // the pilaster stone at the bay's start
        S.add(ashlar(0.32, ph, 0.46, 0.03, rng, 0.15, { ends: true, top: !full }), ringM(wallR + 0.2, t0 + 0.16 / wallR, 0.2 + ph / 2), C.st(tint * 1.05, { orn: { cell: ORN.bars, amount: C.erosion() * 0.8, su: 1 / 3, sv: 1, fn: frontFace(0.32, ph) } }));
      }
      const capped = courses === 3;
      if (capped) {
        const g = sweep(capProf, arcPath(wallR, t0 + 0.006 / wallR, t1 - 0.006 / wallR, 1.12, 2), { orn: capOrn });
        S.add(g, new THREE.Matrix4(), C.st(tint * 0.95, { uv: 'keep', orn: { cell: ORN.meander, amount: C.erosion(), su: 1, sv: 1 } }));
      }
      postAt.push({ th: t0, ok: capped, k: bayK, end: k === 0 });
      if (k === n - 1) postAt.push({ th: t1, ok: capped, k: bayK + 100, end: true });
      // rubble at the foot of what has fallen
      if (courses < 3) {
        const cnt = inBreach ? (hi ? 9 : 5) : 3;
        for (let j = 0; j < cnt; j++) {
          const rr = inBreach ? rng.range(13.4, 17.4) : rng.range(14.3, 15.5);
          const p = ringPos(rr, tc + rng.range(-0.5, 0.5) * dth, 0);
          const s = rng.range(0.25, inBreach ? 0.75 : 0.5);
          const yb = rr > wallR ? platY * smoothstep(wallR - 0.4, wallR + 1.6, rr) : inBreach ? 0.5 * smoothstep(13.4, 15.6, rr) : 0;
          const g = rng.chance(0.6) ? brokenBlock(s * rng.range(1.2, 2.2), s * rng.range(0.6, 1.0), s * rng.range(0.9, 1.4), rng, { jag: 0.5, nx: 2, nz: 1, bottom: true }) : rock(s, rng, { detail: s > 0.5 ? 1 : 0, squash: rng.range(0.5, 0.8) });
          S.add(g, trs(p.x, yb + s * 0.28, p.z, rng.range(0, 6), rng.range(-0.4, 0.4), rng.range(-0.4, 0.4)), C.st(C.blockTint() * 0.9));
        }
        if (inBreach) C.colliders.circles.push({ x: ringPos(14.9, tc).x, z: ringPos(14.9, tc).z, r: 1.0, y0: 0, h: 0.9, tag: 'rubble' });
      }
    }
  }

  // ---- balustrade on the cap --------------------------------------------------------------------------------------
  S.section('balustrade');
  {
    const rP = wallR + 0.2;
    const std = [];
    for (const q of postAt) {
      const gone = !q.ok || (!q.end && rng.chance(0.16));
      const stub = !gone && rng.chance(0.14);
      const lean = !gone && !stub && rng.chance(0.12);
      std.push({ ...q, gone, stub });
      if (gone) continue;
      const p = ringPos(rP, q.th, platY);
      post(C, trs(p.x, p.y, p.z, -q.th, lean ? rng.range(-0.12, 0.05) : 0, lean ? rng.range(-0.08, 0.08) : 0), stub ? rng.range(0.25, 0.6) : railH, railH);
    }
    for (let i = 0; i < std.length - 1; i++) {
      const a = std[i], b = std[i + 1];
      if (a.gone || b.gone || a.stub || b.stub || Math.abs(b.th - a.th) * wallR > 2.6) continue;
      if (rng.chance(0.18)) continue;
      railSpan(C, ringPos(rP, a.th, platY), ringPos(rP, b.th, platY), railCells[a.k % railCells.length]);
    }
  }

  // ---- the stair flights -------------------------------------------------------------------------------------------
  S.section('stairs');
  const stairs = [];
  for (const s of mouths) {
    const base = ringM(wallR - 0.02, s.th, 0);            // +Z toward the terrace centre, the flight climbs toward -Z
    const rise = platY / s.steps, tread = s.run / s.steps;
    for (let k = 0; k < s.steps; k++) {
      const g = chamferBox(s.width, rise, tread + 0.06, 0.022, rng, 0.25);
      S.add(g, T(base, rng.range(-0.01, 0.01), rise * (k + 0.5) - (k === 3 ? 0.03 : 0), -tread * (k + 0.5), rng.range(-0.006, 0.006), 0, k === 5 ? 0.012 : 0), C.st(C.blockTint() * 0.95, { uvScale: 1.6 }));
    }
    // landing slabs either side of the flight (the court's paving is a polar ring: these square it off)
    for (const sx of [-1, 1]) {
      const x0 = s.width / 2 + 0.3, x1 = (s.width / 2 + 0.38) * ((wallR + s.run) / wallR) + 0.5;
      S.add(new THREE.BoxGeometry(x1 - x0, 0.3, s.run + 0.5), T(base, sx * (x0 + x1) / 2, platY - 0.162, -s.run / 2 - 0.2), C.st(0.8, { uvScale: 3 }));
      // cheek (소맷돌): a sloped slab carved with clouds, a newel post at its head and foot
      const g = prism([[0, 0], [0.5, 0], [s.run + 0.4, platY - 0.1], [s.run + 0.4, platY + 0.34], [s.run - 0.1, platY + 0.34], [0, 0.5]], 0.36);
      setOrnUv(g, (p, n) => (Math.abs(n.z) > 0.9 ? [(p.x * 0.88 + p.y * 0.47) / 1.5, (p.y * 0.88 - p.x * 0.47 + 0.1) / 0.62, 1] : null));
      S.add(g, T(base, sx * (s.width / 2 + 0.18), 0, 0.05, Math.PI / 2), C.st(C.blockTint(), { orn: { cell: panel(ORN.cloud), amount: C.erosion() * 1.1, su: 1, sv: 1 } }));
      post(C, T(base, sx * (s.width / 2 + 0.18), 0.5, -0.12), 0.55, 0.55);
      post(C, T(base, sx * (s.width / 2 + 0.18), platY + 0.34, -s.run - 0.15), 0.7, 0.7);
    }
    const foot = V(0, 0, 0).applyMatrix4(base), up = ringPos(1, s.th, 0);
    stairs.push({ id: s.id, x: foot.x, z: foot.z, dirX: up.x, dirZ: up.z, width: s.width, run: s.run, rise: platY, steps: s.steps });
  }

  // ---- the court's paving, the ramp of spoil at the vista shoulders, the outer skirt -------------------------------------
  S.section('ground');
  const edgeOuter = (th) => wallR + (outerR - wallR) * smoothstep(gap - 2 * DEG, gap + 13 * DEG, Math.abs(th));
  const shoulderY = (th) => platY * smoothstep(gap, wallFrom + 1 * DEG, Math.abs(th));
  {
    const pos = [], idx = [];
    const rows = 4;
    // angular breakpoints: fine near the vista shoulders and the stair mouths
    const ths = [];
    for (let d = -180; d < 180; d += 3) ths.push(d * DEG);
    for (const s of mouths) { ths.push(wrap(s.th - s.half), wrap(s.th + s.half)); }
    ths.push(-gap + 2 * DEG, gap - 2 * DEG, -gap, gap, -wallFrom - 1 * DEG, wallFrom + 1 * DEG, breach[0] - 0.5 * DEG, breach[0] + 1.5 * DEG, breach[1] - 1.5 * DEG, breach[1] + 0.5 * DEG);
    ths.sort((a, b) => a - b);
    const cols = [];
    for (let i = 0; i < ths.length; i++) {
      const th = ths[i];
      if (Math.abs(th) < gap - 2 * DEG - 1e-6) { cols.push(null); continue; }
      const mouth = mouths.find((s) => Math.abs(wrap(th - s.th)) < s.half - 1e-4);
      // the vista shoulders and the east breach are ramps of spoil from the floor up to the court
      const inBreach = th > breach[0] && th < breach[1];
      const onShoulder = Math.abs(th) < wallFrom + 1 * DEG || inBreach;
      const r0 = mouth ? wallR + mouth.run + 0.05 : inBreach ? wallR + 0.1 : onShoulder ? rimR(th) - 0.02 : wallR + 0.75;
      const r1 = edgeOuter(th);
      const y = shoulderY(th);
      const base = pos.length / 3;
      for (let j = 0; j <= rows; j++) {
        let rr, yy;
        if (j === rows) { rr = r1 + 5 + 2 * noise3(th * 3, 1, 2); yy = y - 7; }
        else {
          const t = j / (rows - 1);
          rr = r0 + Math.max(0, r1 - r0) * Math.pow(t, 1.6);
          // the shoulder is a ramp of spoil: it starts at floor level on the terrace's edge
          yy = (onShoulder ? Math.max(inBreach ? 0.12 : 0, y * smoothstep(0, inBreach ? 0.3 : 0.45, t)) + 0.1 * noise3(th * 40, rr, 3) * smoothstep(0, 0.3, t) : y) - 0.004 - (j === rows - 1 ? 0.25 : 0);
        }
        const p = ringPos(rr, th, yy);
        pos.push(p.x, p.y, p.z);
      }
      cols.push(base);
    }
    for (let i = 0; i < ths.length; i++) {
      const a = cols[i], b = cols[(i + 1) % ths.length];
      if (a === null || b === null) continue;
      const d = wrap(ths[(i + 1) % ths.length] - ths[i]);
      if (d <= 0 || d > 0.2) continue;
      // a stair mouth: its two edge columns start at different radii; the landing slabs cover the seam
      for (let j = 0; j < rows; j++) idx.push(a + j, b + j, a + j + 1, a + j + 1, b + j, b + j + 1);
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    g.setIndex(idx);
    g.computeVertexNormals();
    S.add(g, new THREE.Matrix4(), { color: C.stoneColor(0.78), glow: C.glow, uv: 'box', uvScale: 3 });
  }
  // cliff face under the fallen rim and the shoulders
  {
    const cpos = [], cidx = [];
    const crow = 10, cseg = 84;
    const thA = gap + 19 * DEG;
    for (let i = 0; i <= cseg; i++) {
      const th = -thA + (2 * thA * i) / cseg;
      const a = Math.abs(th);
      const onRim = a < gap;
      const re = onRim ? rimR(th) : rimR(th) + (edgeOuter(th) - rimR(th)) * smoothstep(gap, gap + 2.5 * DEG, a);
      const y0 = onRim ? 0 : shoulderY(th) * smoothstep(gap, gap + 2.5 * DEG, a);
      for (let j = 0; j <= crow; j++) {
        const t = j / crow;
        const y = y0 - 0.02 - t * t * 40;
        const out = t * 6 + (fbm3(th * 6, y * 0.12, 1.0, 3) - 0.5) * 3.2 * (0.3 + t) - 0.35 * Math.sin(t * Math.PI) * (onRim ? 1 : 0);
        const p = ringPos(re + out, th, y);
        cpos.push(p.x, p.y, p.z);
      }
    }
    for (let i = 0; i < cseg; i++) for (let j = 0; j < crow; j++) {
      const a = i * (crow + 1) + j, b = a + 1, c = a + crow + 1, d = c + 1;
      cidx.push(a, c, b, b, c, d);
    }
    const cg = new THREE.BufferGeometry();
    cg.setAttribute('position', new THREE.Float32BufferAttribute(cpos, 3));
    cg.setIndex(cidx);
    S.add(flatNormals(cg.toNonIndexed()), new THREE.Matrix4(), { color: (p, n, o) => { const k = 0.55 * (0.7 + 0.5 * noise3(p.x * 0.3, p.y * 0.3, p.z * 0.3)); o[0] = k; o[1] = k * 0.98; o[2] = k * 0.95; }, uv: 'box', uvScale: 4 });
  }

  // ---- the rim: the terrace's own low balustrade, almost all of it gone over the edge ----------------------------------
  S.section('rim');
  {
    const spots = [[-24.5, 'ok'], [-18.5, 'lean'], [-11, 'stub'], [8.5, 'stub'], [15.5, 'lean'], [21.5, 'ok'], [26, 'ok']];
    const pts = [];
    for (const [deg, st] of spots) {
      const th = deg * DEG;
      const p = ringPos(rimR(th) - 0.32, th, 0);
      const m = trs(p.x, 0, p.z, -th, st === 'lean' ? -0.22 : 0, st === 'lean' ? 0.06 : 0);
      post(C, m, st === 'stub' ? 0.3 : 0.85, 0.85);
      pts.push({ p, st });
      C.colliders.circles.push({ x: p.x, z: p.z, r: 0.22, y0: 0, h: st === 'stub' ? 0.3 : 0.9, tag: 'rimpost' });
    }
    // one span of rail survives on each shoulder
    railSpan(C, pts[5].p.clone().setY(-0.14), pts[6].p.clone().setY(-0.14), ORN.wave);
    // slabs at the lip: heaved flagstones overhanging the drop, chips
    const n = hi ? 16 : mid ? 11 : 7;
    for (let k = 0; k < n; k++) {
      const th = rng.range(-gap + 2 * DEG, gap - 2 * DEG);
      const d = rng.range(-0.25, 0.45);
      const p = ringPos(rimR(th) - d, th, 0);
      const w = rng.range(0.5, 1.1), dd = rng.range(0.4, 0.8), h = rng.range(0.12, 0.2);
      S.add(brokenBlock(w, h, dd, rng, { jag: 0.4, nx: 2, nz: 2, bottom: true }), trs(p.x, d < 0 ? -0.1 : h * 0.3, p.z, -th + rng.range(-0.5, 0.5), d < 0 ? rng.range(0.15, 0.4) : rng.range(-0.08, 0.08), rng.range(-0.1, 0.1)), C.st(C.blockTint() * 0.6, { uvScale: 1.3 }));
    }
  }

  // ---- rubble and grit at the wall foot ---------------------------------------------------------------------------------
  S.section('rubble');
  const rubbleN = Math.round(70 * tier.rubble);
  for (let i = 0; i < rubbleN; i++) {
    const th = rng.range(-Math.PI, Math.PI);
    if (Math.abs(th) < gap + 2 * DEG || inMouth(th)) continue;
    const shoulder = Math.abs(th) < wallFrom + 3 * DEG;
    const p = ringPos(shoulder ? rng.range(14.6, 16.6) : rng.range(14.3, 15.4), th, 0);
    const s = rng.range(0.12, shoulder ? 0.6 : 0.4);
    const yb = shoulder ? shoulderY(th) * smoothstep(15.3, 16.2, Math.hypot(p.x, p.z)) : 0;
    const isBlock = rng.chance(0.5);
    const g = isBlock ? (rng.chance(0.5) ? brokenBlock(s * rng.range(1.2, 2.2), s * rng.range(0.6, 1.0), s * rng.range(0.9, 1.4), rng, { jag: 0.5, nx: 2, nz: 1, bottom: true }) : chamferBox(s * rng.range(1.2, 2.2), s * rng.range(0.6, 1.0), s * rng.range(0.9, 1.4), 0.04, rng, 0.6)) : rock(s, rng, { detail: s > 0.5 ? 1 : 0, squash: rng.range(0.45, 0.8) });
    S.add(g, trs(p.x, yb + s * (isBlock ? 0.3 : 0.25), p.z, rng.range(0, 6), rng.range(-0.3, 0.3), rng.range(-0.3, 0.3)), C.st(C.blockTint() * 0.9));
  }
  const chipN = Math.round(130 * tier.rubble);
  for (let i = 0; i < chipN; i++) {
    const th = rng.range(-Math.PI, Math.PI);
    const inGap = Math.abs(th) < gap;
    const r = inGap ? rimR(th) - 0.1 - Math.pow(rng(), 2) * 2.2 : 15.5 - Math.pow(rng(), 2.2) * 1.6;
    if (!inGap && inMouth(th)) continue;
    const p = ringPos(r, th, 0);
    if (Math.abs(p.z) < 3 && Math.abs(p.x) < 13) continue;
    const s = rng.range(0.04, 0.15);
    S.add(rock(s, rng, { detail: 0, squash: rng.range(0.4, 0.8), rough: 0.45 }), trs(p.x, s * 0.2, p.z, rng.range(0, 6)), C.st(C.blockTint() * 0.85));
  }

  // ---- the old impact: flagstones heaved up and shattered around the crater rim ----------------------------------------
  S.section('impact');
  {
    const [ix, iz, ir] = IMPACT;
    const n = hi ? 14 : mid ? 10 : 7;
    for (let k = 0; k < n; k++) {
      const a = (k / n) * Math.PI * 2 + rng.range(-0.2, 0.2);
      const d = ir * rng.range(0.55, 0.95);
      const x = ix + Math.cos(a) * d, z = iz + Math.sin(a) * d;
      const w = rng.range(0.55, 0.95), dd = rng.range(0.45, 0.75), h = rng.range(0.22, 0.34);
      const lift = rng.range(0.18, 0.5) * (1 - d / ir * 0.45);
      const g = brokenBlock(w, h, dd, rng, { jag: 0.4, nx: 3, nz: 2, bottom: true });
      const m = trs(x, -h * 0.3 + Math.sin(lift) * dd * 0.3, z, -a + Math.PI / 2 + rng.range(-0.3, 0.3), lift, rng.range(-0.15, 0.15));
      S.add(g, m, { color: C.stoneColor(rng.range(0.08, 0.13)), glow: C.glow, uv: 'box', uvScale: 1.3 });
    }
    for (let k = 0; k < (hi ? 30 : 14); k++) {
      const a = rng.range(0, Math.PI * 2), d = ir * Math.sqrt(rng()) * 1.25;
      const s = rng.range(0.05, 0.14);
      S.add(rock(s, rng, { detail: 0, squash: 0.5 }), trs(ix + Math.cos(a) * d, s * 0.2, iz + Math.sin(a) * d, rng.range(0, 6)), { color: C.stoneColor(0.22), glow: C.glow, uv: 'box', uvScale: 1.3 });
    }
  }
  return { segments: segs, stairs, edgeOuter, shoulderY };
}
