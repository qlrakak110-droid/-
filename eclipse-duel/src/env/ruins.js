// The colosseum ruins, built from code and carved with the relief atlas (ornament.js): a podium wall with an
// inscribed plinth, a torus base moulding, a processional frieze and a dentilled cornice; a colonnade of fluted
// columns on Attic bases with egg-and-dart capitals carrying arches (voussoirs, carved keystones, archivolts) and
// moulded entablatures; the broken seating tier (irregular, settled seats, stairways, a parapet walk, slumped and
// collapsed sections over exposed vaults); the broken cliff edge of the vista gap; fallen and toppled pieces and
// rubble. Dressing (candles, chains, cages, vines, weapons ...) lives in dressing.js.
// Returns merged geometries (one draw call per material) plus anchor points.

import * as THREE from 'three';
import { DEG, smoothstep, clamp } from '../core/math.js';
import { Builder, chamferBox, ashlar, latheGrid, rock, addAll, trs, noise3, fbm3, flatNormals, setOrnUv, frontFace, sweep, arcPath, linePath, brokenBlock } from './geometry.js';
import { LAYOUT } from './config.js';
import { ORN, panel } from './ornament.js';
import { dressRuins } from './dressing.js';

const ringPos = (r, th, y = 0) => new THREE.Vector3(r * Math.sin(th), y, -r * Math.cos(th));

/** Seat block: only the faces the arena can see (top, worn front edge, riser, ends; `back` adds the rear). 12-14 tris. */
function seatBlock(L, h, d, bev, back) {
  const x0 = -L / 2, x1 = L / 2, yb = -h / 2, yt = h / 2, zf = d / 2, zb = -d / 2;
  const out = [];
  const q = (a, b, c, e) => out.push(...a, ...b, ...c, ...a, ...c, ...e);
  q([x0, yb, zf], [x1, yb, zf], [x1, yt - bev, zf], [x0, yt - bev, zf]);
  q([x0, yt - bev, zf], [x1, yt - bev, zf], [x1, yt, zf - bev], [x0, yt, zf - bev]);
  q([x0, yt, zf - bev], [x1, yt, zf - bev], [x1, yt, zb], [x0, yt, zb]);
  if (back) q([x1, yb, zb], [x0, yb, zb], [x0, yt, zb], [x1, yt, zb]);
  for (const [x, s] of [[x0, -1], [x1, 1]]) {
    const P = [[x, yb, zf], [x, yt - bev, zf], [x, yt, zf - bev], [x, yt, zb], [x, yb, zb]];
    const tri = (a, b, c) => out.push(...P[a], ...P[b], ...P[c]);
    if (s > 0) { tri(0, 4, 1); tri(1, 4, 2); tri(2, 4, 3); } else { tri(0, 1, 4); tri(1, 2, 4); tri(2, 3, 4); }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(out, 3));
  return flatNormals(g);
}

/** Relief mapping on the four vertical faces of a box (u runs to the right as seen from outside each face). */
const sideFaces = (w, h, d) => (p, n) => {
  if (Math.abs(n.y) > 0.5) return null;
  if (Math.abs(n.z) >= Math.abs(n.x)) return [Math.sign(n.z) * p.x / w + 0.5, p.y / h + 0.5, Math.abs(n.z) > 0.9 ? 1 : 0];
  return [-Math.sign(n.x) * p.z / d + 0.5, p.y / h + 0.5, Math.abs(n.x) > 0.9 ? 1 : 0];
};

/**
 * @param {Function} rng   deterministic rng (makeRng)
 * @param {object} tier    tierSettings()
 * @returns {{stone, metal, props: THREE.BufferGeometry, banners: Array, braziers: THREE.Vector3[], flames: Array, sections: object}}
 */
export function buildRuins(rng, tier) {
  const S = new Builder({ orn: true });   // stone
  const M = new Builder();                // iron
  const P = new Builder();                // wax, wood, dead vegetation
  const mid = tier.detail >= 1;
  const braziers = LAYOUT.braziers.map(([deg, r]) => ringPos(r, deg * DEG, 0));
  const glow = (p) => {
    let g = 0;
    for (const b of braziers) {
      const dx = p.x - b.x, dy = p.y - 1.5, dz = p.z - b.z;
      g += Math.exp(-(dx * dx + dy * dy * 0.6 + dz * dz) / 7.5);
    }
    return Math.min(g, 1.2);
  };
  // albedo multiplier: big discolouration patches, grime + rain streaks toward the ground, moss on tops
  const stoneColor = (tint) => (p, n, out) => {
    const v = 0.8 + 0.4 * fbm3(p.x * 0.13, p.y * 0.13, p.z * 0.13, 2);
    const ground = 0.5 + 0.5 * smoothstep(-0.5, 3.0, p.y);
    const streak = 0.86 + 0.14 * noise3(p.x * 2.1 + p.z * 1.7, p.y * 0.16, 0.5);
    const up = Math.max(0, n.y);
    const moss = up > 0.55 ? smoothstep(0.45, 0.7, fbm3(p.x * 0.6, p.y * 0.6, p.z * 0.6, 2)) * 0.7 : 0;
    const k = v * ground * streak * tint;
    out[0] = k * (1 - moss * 0.45);
    out[1] = k * (1 - moss * 0.2);
    out[2] = k * (1 - moss * 0.55);
  };
  const blockTint = () => rng.range(0.78, 1.18);
  const st = (tint, extra) => ({ color: stoneColor(tint), glow, uv: 'box', uvScale: 2.2, ...extra });
  const erosion = () => (rng.chance(0.18) ? rng.range(0.15, 0.4) : rng.range(0.65, 1.0));

  const { wallR, wallT, pillarR, gap, thetaMax } = LAYOUT;

  // ---- podium wall ----------------------------------------------------------------------------------------------
  // plinth (inscribed), ashlar courses, the frieze course (procession converging on the vista), then the cornice
  S.section('podium');
  const courseHs = [0.68, 0.5, 0.62, 0.48, 0.62], courses = courseHs.length;
  const courseY = [0];
  for (const ch of courseHs) courseY.push(courseY[courseY.length - 1] + ch);
  const friezeCourse = 4;
  const wallRc = wallR + wallT / 2;
  const coursesAt = (th) => {
    const a = Math.abs(th);
    // the vista: a knee-high broken kerb in the middle (the cloud sea shows behind the fighters' heads), rising to
    // broken stubs toward the shoulders
    if (a < gap) return Math.round(clamp(-0.35 + 1.25 * noise3(th * 9, 1.3, 0.2) + Math.pow(a / gap, 2) * 2.7, 0, 3));
    const dip = noise3(th * 5 + 4, 7.7, 0.3);
    let c = courses + 1;
    if (dip > 0.66) c = Math.round(2 + (1 - dip) * 6);
    if (a < gap + 7 * DEG) c = Math.min(c, Math.round(2 + (a - gap) / (7 * DEG) * 3));
    return c;
  };
  let friezeK = 0;
  // the blocks actually laid on each course, [theta0, theta1, broken top]: a block (or a moulding run) is laid only
  // where the course under it is solid, so nothing bridges a gap where the wall below has fallen
  const laid = [];
  const overlap = (list, a, b, solidOnly) => {
    let s = 0;
    for (const [t0, t1, top] of list) if (!solidOnly || !top) s += Math.max(0, Math.min(b, t1) - Math.max(a, t0));
    return s / (b - a);
  };
  const solidUnder = (c, a, b, k) => overlap(laid[c], a, b, true) >= k;
  const wallBlocks = [];
  for (let c = 0; c < courses; c++) {
    laid.push([]);
    let th = -thetaMax - rng.range(0, 1.2) / wallRc;
    while (th < thetaMax) {
      const L = rng.range(0.95, 1.75);
      const dth = L / wallRc;
      const tc = th + dth / 2;
      th += dth;
      const n = coursesAt(tc);
      if (c >= n || (c > 0 && !solidUnder(c - 1, th - dth, th, 0.8))) continue;
      const top = c === n - 1 && n < courses + 1;
      laid[c].push([th - dth, th, top]);
      wallBlocks.push({ c, a: th - dth, b: th, tc, L, top });
    }
  }
  // then cut them, knowing what actually lies above and beside each one: interior blocks show only their face, a
  // block keeps its top / ends wherever they are exposed
  for (const { c, a, b, tc, L, top } of wallBlocks) {
    const plinth = c === 0;
    const h = courseHs[c];
    const y0 = courseY[c];
    const fallen = top && rng.chance(0.25);
    const hh = top ? h * rng.range(0.55, 1) : h;
    const depth = plinth ? wallT + 0.16 : wallT;
    const rr = plinth ? wallRc - 0.08 : wallRc;
    const jitter = fallen ? rng.range(-0.25, 0.25) : rng.range(-0.012, 0.012);
    const p = ringPos(rr + jitter, tc, y0 + hh / 2);
    const m = trs(p.x, p.y, p.z, -tc + rng.range(-0.01, 0.01) + (fallen ? rng.range(-0.2, 0.2) : 0), fallen ? rng.range(-0.15, 0.15) : 0, fallen ? rng.range(-0.1, 0.1) : rng.range(-0.004, 0.004));
    const capped = c + 1 < courses && overlap(laid[c + 1], a, b, false) > 0.97;
    const e = 0.004 / wallRc;
    const ends = overlap(laid[c], a - 2 * e, a - e, false) < 0.5 || overlap(laid[c], b + e, b + 2 * e, false) < 0.5;
    const geo = top && rng.chance(0.55) ? brokenBlock(L - 0.025, hh - 0.012, depth, rng, { jag: 0.5, nx: 3, nz: 2 })
      : top || fallen ? chamferBox(L - 0.025, hh - 0.012, depth, 0.045, rng, top ? 0.5 : 0.12)
        : ashlar(L - 0.025, hh - 0.012, depth, 0.045, rng, 0.12, { top: !capped, ends });
    let orn = null;
    // procession: figures walk toward the vista on both sides (mirrored on the right), an eclipse roundel every
    // fourth block, an orant every seventh
    if (c === friezeCourse && !top) {
      friezeK++;
      const kind = friezeK % 4 === 0 ? ORN.roundel : friezeK % 7 === 0 ? ORN.orant : ORN.figure;
      const nrep = Math.max(1, Math.round(L / (kind === ORN.roundel ? 0.6 : 0.5)));
      const mirror = kind === ORN.figure && tc > 0;
      orn = { cell: kind, amount: erosion() * 1.15, su: mirror ? -nrep : nrep, ou: mirror ? nrep : 0, sv: 1, fn: frontFace(L - 0.025, hh - 0.012) };
    } else if (plinth && !top) {
      orn = { cell: ORN.glyphs, amount: erosion() * 0.8, su: L / 0.95, sv: 1, fn: frontFace(L - 0.025, hh - 0.012) };
    } else if (!top && rng.chance(0.12)) {
      orn = { cell: ORN.panel, amount: 0.5, su: 1, sv: 1, fn: frontFace(L - 0.025, hh - 0.012) };
    }
    S.add(geo, m, st(blockTint(), orn ? { orn } : {}));
  }
  // base moulding on the plinth (torus with a laurel wrap + cavetto), and the cornice (egg-and-dart fascia, dentils,
  // corona, cyma crown), each laid in block-length runs that stop where the wall has fallen
  const baseProf = [[0.15, 0.0], [0.175, 0.02, false], [0.185, 0.05, false], [0.175, 0.085, false], [0.14, 0.1], [0.125, 0.1], [0.115, 0.13], [0.07, 0.155, false], [0.03, 0.2, false], [0.01, 0.26], [0.0, 0.3]];
  const baseOrn = { 0: [0, 0.25], 1: [0.25, 0.5], 2: [0.5, 0.75], 3: [0.75, 1] };
  const corProf = [[0.0, 0.0], [0.06, 0.0], [0.06, 0.16], [0.1, 0.16], [0.1, 0.3], [0.14, 0.3], [0.3, 0.33], [0.32, 0.36], [0.32, 0.48], [0.345, 0.5, false], [0.335, 0.56, false], [0.28, 0.6, false], [0.22, 0.655, false], [0.205, 0.7], [-1.12, 0.73]];
  const corOrn = { 1: [0, 1, ORN.eggDart, 1 / 0.17], 3: [0, 1, ORN.dentil, 1 / 0.13] };
  const runs = (r, onCourse, y, prof, ornMap, cells, lenRange, fallChance) => {
    const out = [];
    let th = -thetaMax;
    while (th < thetaMax) {
      const L = rng.range(lenRange[0], lenRange[1]);
      const dth = L / r;
      const t0 = th, t1 = th + dth;
      th = t1 + 0.012 / r;
      const tc = (t0 + t1) / 2;
      if (!solidUnder(onCourse, t0, t1, 0.9) || rng.chance(fallChance)) continue;
      const g = sweep(prof, arcPath(r, t0, t1, y, 3), { orn: ornMap });
      const tilt = rng.chance(0.15) ? rng.range(-0.025, 0.025) : 0;
      const m = new THREE.Matrix4().makeRotationAxis(ringPos(1, tc, 0), tilt);
      // relief: dentils / eggs in metres along the run; one cell per ornament repeat
      S.add(g, m, st(blockTint() * 0.95, { uv: 'keep', orn: { cell: cells[0], amount: erosion(), su: 1 / cells[1], sv: 1 } }));
      out.push([t0, t1, false]);
    }
    return out;
  };
  runs(wallR, 0, courseY[1], baseProf, baseOrn, [ORN.laurel, 0.42], [1.2, 2.2], 0.08);
  S.section('cornice');
  const corniceRuns = runs(wallR, courses - 1, courseY[courses], corProf, corOrn, [ORN.dentil, 1], [1.4, 2.1], 0.1);
  /** Height of the standing wall top at theta (top of the cornice where a run survives, else of the highest course). */
  const wallTopAt = (th) => {
    if (overlap(corniceRuns, th - 0.2 / wallR, th + 0.2 / wallR, false) > 0.99) return courseY[courses] + 0.73;
    for (let c = courses - 1; c >= 0; c--) if (overlap(laid[c], th - 0.2 / wallRc, th + 0.2 / wallRc, true) > 0.99) return courseY[c + 1];
    return 0;
  };
  S.section('podium');

  // pilasters break the long courses into bays (none near the vista); carved panel on the face, broken where the
  // wall has fallen
  for (let th = -thetaMax + 5 * DEG; th < thetaMax - 3 * DEG; th += 12.5 * DEG) {
    if (Math.abs(th) < gap + 9 * DEG) continue;
    const n = coursesAt(th);
    if (n < 3) continue;
    const H = n > courses ? courseY[courses] + 0.73 : courseY[n];
    const broken = n <= courses || rng.chance(0.3);
    const top = broken ? H - rng.range(0.15, 0.8) : H + 0.45;
    const tint = blockTint();
    const a = ringPos(wallR - 0.36, th, 0), b = ringPos(wallR - 0.3, th, 0);
    S.add(chamferBox(1.3, 0.55, 0.92, 0.05, rng, 0.25), trs(a.x, 0.275, a.z, -th), st(tint * 0.96));
    const ph = top - 0.55;
    const shaft = broken ? brokenBlock(0.98, ph, 0.66, rng, { jag: 0.25 }) : chamferBox(0.98, ph, 0.66, 0.05, rng, 0.2);
    S.add(shaft, trs(b.x, 0.55 + ph / 2, b.z, -th, 0, rng.range(-0.006, 0.006)), st(tint * 0.96, { orn: { cell: ORN.panel, amount: erosion() * 0.6, su: 1, sv: Math.max(1, Math.round(ph / 1.3)), fn: frontFace(0.98, ph) } }));
    if (!broken) S.add(chamferBox(1.2, 0.24, 0.86, 0.04, rng, 0.2), trs(a.x, top + 0.12, a.z, -th), st(tint * 0.96, { orn: { cell: ORN.eggDart, amount: 0.8, su: 1.2 / 0.2, sv: 1, fn: frontFace(1.2, 0.24) } }));
  }

  // ---- outer ground and the broken cliff edge -----------------------------------------------------------------------
  S.section('ground');
  const edgeR = (th) => {
    const a = Math.abs(th);
    const inGap = 1 - smoothstep(gap - 2 * DEG, gap + 9 * DEG, a);
    return 31 - inGap * (31 - (17.1 + 1.6 * noise3(th * 7, 0.5, 2.2) + 0.9 * noise3(th * 23, 1.5, 0.2)));
  };
  {
    const segs = 128, rows = 6;
    const pos = [], idx = [];
    for (let i = 0; i <= segs; i++) {
      const th = -thetaMax + (2 * thetaMax * i) / segs;
      const re = edgeR(th);
      for (let j = 0; j <= rows; j++) {
        const r = wallR - 0.1 + (re - wallR + 0.1) * (j / rows);
        const p = ringPos(r, th, 0);
        pos.push(p.x, j === rows ? -0.06 : -0.012, p.z); // just under the floor disc: no z-fight where they overlap
      }
    }
    for (let i = 0; i < segs; i++) for (let j = 0; j < rows; j++) {
      const a = i * (rows + 1) + j, b = a + 1, c = a + rows + 1, d = c + 1;
      idx.push(a, b, c, b, d, c);
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    g.setIndex(idx);
    g.computeVertexNormals();
    S.add(g, new THREE.Matrix4(), { color: stoneColor(0.8), glow, uv: 'box', uvScale: 3 });
    // cliff face under the edge (only where it can be seen: the gap and its shoulders)
    const cpos = [], cidx = [];
    const crow = 10;
    const thA = gap + 16 * DEG;
    const cseg = 72;
    for (let i = 0; i <= cseg; i++) {
      const th = -thA + (2 * thA * i) / cseg;
      const re = edgeR(th);
      for (let j = 0; j <= crow; j++) {
        const t = j / crow;
        const y = -0.05 - t * t * 40;
        const out = t * 6 + (fbm3(th * 6, y * 0.12, 1.0, 3) - 0.5) * 3.2 * (0.3 + t);
        const p = ringPos(re + out - 0.2 * (1 - t), th, y);
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
    const flat = flatNormals(cg.toNonIndexed());
    S.add(flat, new THREE.Matrix4(), { color: (p, n, o) => { const k = 0.55 * (0.7 + 0.5 * noise3(p.x * 0.3, p.y * 0.3, p.z * 0.3)); o[0] = k; o[1] = k * 0.98; o[2] = k * 0.95; }, uv: 'box', uvScale: 4 });
  }

  // ---- colonnade -------------------------------------------------------------------------------------------------
  // per slot: H = height (null = gone), cap = intact with capital
  S.section('columns');
  const slotDeg = 360 / LAYOUT.pillarCount;
  const slotState = {
    3: { H: 5.6 }, 4: { cap: true }, 5: { cap: true }, 6: { cap: true }, 7: { cap: true }, 8: { H: 5.9 }, 9: { H: 4.4 },
    10: { H: 1.7 }, 11: null, 12: { H: 6.6 }, 13: { cap: true }, 14: { cap: true }, 15: { H: 10.8 }, 16: { cap: true },
    17: { cap: true }, 18: { H: 3.1 },
  };
  const capH = 8.0, pierR = 0.95, FLUTES = 20, FSEG = 40;
  const pillars = [];
  const drum = 1.55;
  const fluteOrn = (amount) => ({ cell: ORN.flute, amount, su: 1, sv: 1 });
  // u counts flutes around the shaft, v runs 0..1 up the drum (the shader carves the V-joint at both ends)
  const fluted = (g, segs, y0, h) => setOrnUv(g, (p, n, i) => [((i % (segs + 1)) / segs) * FLUTES, (p.y - y0) / h, 1]);
  for (const key of Object.keys(slotState)) {
    const i = Number(key);
    const state = slotState[i];
    const th = (i - 10.5) * slotDeg * DEG;
    const base = ringPos(pillarR, th, 0);
    pillars.push({ i, th, pos: base, state });
    if (!state) continue;
    const tint = blockTint();
    const col = { color: stoneColor(tint), glow, uv: 'keep', uvScale: 2.4 };
    const rot = -th + Math.PI / FLUTES * 0.5;
    // square plinth + Attic base (torus, scotia, torus); mostly hidden behind the podium wall, so kept light
    S.add(chamferBox(2.5, 0.55, 2.5, 0.06, rng, 0.2), trs(base.x, 0.275, base.z, -th), st(tint * 0.95));
    const baseP = (t) => {
      const y = 0.55 + t * 0.42;
      const r = t < 0.35 ? pierR + 0.2 + 0.07 * Math.sin((t / 0.35) * Math.PI) : t < 0.65 ? pierR + 0.08 - 0.05 * Math.sin(((t - 0.35) / 0.3) * Math.PI) : pierR + 0.1 + 0.05 * Math.sin(((t - 0.65) / 0.35) * Math.PI) - 0.06 * ((t - 0.65) / 0.35);
      return [r, y];
    };
    addAll(S, latheGrid({ rows: 7, segs: 24, profile: baseP }), trs(base.x, 0, base.z, rot), col);
    // shaft in drums: 20 flutes (geometry alternates arris / channel, the shader carves the concave channels),
    // entasis, V-jointed drum ends, slight misalignment, chips; jagged top if broken
    const H = state.cap ? capH - 0.5 : state.H;
    let y = 0.95;
    let dx = 0, dz = 0;
    let first = true;
    while (y < H - 0.05) {
      // the lowest 2.4 m hide behind the podium wall: one tall drum there; never leave a sliver of a drum on top
      let h = Math.min(first ? 2.4 : drum, H - y);
      if (H - y - h < 0.7) h = H - y;
      first = false;
      const last = y + h >= H - 0.05;
      dx += rng.range(-0.025, 0.025); dz += rng.range(-0.025, 0.025);
      const y0 = y;
      const seed = rng.range(0, 50);
      const chunk = rng.chance(0.22) ? rng.range(0, Math.PI * 2) : -9;
      const broken = last && !state.cap;
      // a broken top: a sheared fracture plane (the classic slanted silhouette) roughened by noise, at most ~60% of
      // the drum deep
      const jag = Math.min(1, h / 1.8);
      const shear = rng.range(0.55, 1.25) * jag, sdir = rng.range(0, Math.PI * 2);
      const rTop = (t) => pierR * (1 - 0.1 * t * t);
      const parts = latheGrid({
        rows: 1, segs: FSEG,
        profile: (t) => { const yy = y0 + t * h; return [rTop(yy / Math.max(H, 6)), yy]; },
        rmod: (phi, yy) => {
          const flute = (Math.round((phi / (Math.PI * 2)) * FSEG) % 2) ? 0.95 : 1.0;
          let m = flute * (1 + (noise3(Math.cos(phi) * 2 + seed, yy * 1.2, Math.sin(phi) * 2) - 0.5) * 0.05);
          if (chunk > -1) { const dphi = Math.abs(((phi - chunk + Math.PI * 3) % (Math.PI * 2)) - Math.PI); if (dphi < 0.6) m *= 1 - 0.22 * (1 - dphi / 0.6); }
          return m;
        },
        topY: broken ? (phi) => y0 + h - 0.05 - (0.5 + 0.5 * Math.cos(phi - sdir)) * shear - Math.abs(noise3(Math.cos(phi) * 1.5 + seed, Math.sin(phi) * 1.5, 3.3) - 0.35) * 0.8 * jag : null,
        capTop: broken ? y0 + h - 0.05 - shear * 0.5 - rng.range(0.1, 0.3) * jag : true,
      });
      fluted(parts[0], FSEG, y0, h);
      addAll(S, parts, trs(base.x + dx, 0, base.z + dz, rot + rng.range(-0.01, 0.01)), { ...col, orn: fluteOrn(chunk > -1 ? 0.75 : 1) });
      y += h;
    }
    if (state.cap) {
      // astragal bead, egg-and-dart echinus, abacus with an eclipse-phase band on every face
      const cx = base.x + dx, cz = base.z + dz;
      addAll(S, latheGrid({ rows: 3, segs: 28, profile: (t) => [pierR * 0.9 + 0.07 * Math.sin(t * Math.PI), H + t * 0.14] }), trs(cx, 0, cz, rot), { ...col, orn: { cell: ORN.laurel, amount: 0.7, su: 1, sv: 1, fn: null } });
      const ech = latheGrid({ rows: 4, segs: 32, profile: (t) => [pierR * 0.88 + 0.44 * Math.sin(t * Math.PI * 0.5) * (0.75 + 0.25 * t), H + 0.14 + t * 0.36], capTop: false });
      setOrnUv(ech[0], (p, n, k) => [((k % 33) / 32) * 14, Math.floor(k / 33) / 4, 1]);
      addAll(S, ech, trs(cx, 0, cz, rot), { ...col, orn: { cell: ORN.eggDart, amount: erosion() * 1.1, su: 1, sv: 1 } });
      const ab = chamferBox(2.45, 0.38, 2.45, 0.05, rng, 0.25);
      setOrnUv(ab, sideFaces(2.45, 0.38, 2.45));
      S.add(ab, trs(cx, H + 0.5 + 0.19, cz, -th), st(tint, { orn: { cell: ORN.phases, amount: erosion(), su: 6, sv: 1 } }));
    }
  }

  // ---- arches between intact neighbours: voussoirs, a carved keystone, an archivolt band, moulded entablature --------
  S.section('arches');
  const archPairs = [[4, 5], [5, 6], [6, 7], [13, 14], [16, 17]];
  const halfArch = [[7, 8]]; // a broken arch springing from slot 7 toward the fallen top of 8
  const springY = capH + 0.38;
  const arches = [];
  const voussoir = (pa, pb, count, keep) => {
    const A = pillars.find((p) => p.i === pa).pos, B = pillars.find((p) => p.i === pb).pos;
    const C = A.clone().add(B).multiplyScalar(0.5);
    const u = B.clone().sub(A); const chord = u.length(); u.normalize();
    const w = new THREE.Vector3().crossVectors(new THREE.Vector3(0, 1, 0), u).normalize(); // outward
    const rIn = (chord - 2.45) / 2, thk = 0.78, rMid = rIn + thk / 2;
    for (let k = 0; k < count; k++) {
      if (k >= keep) break;
      const a = Math.PI - ((k + 0.5) / count) * Math.PI;
      const rdir = u.clone().multiplyScalar(Math.cos(a)).add(new THREE.Vector3(0, Math.sin(a), 0));
      const t = u.clone().multiplyScalar(-Math.sin(a)).add(new THREE.Vector3(0, Math.cos(a), 0));
      const m = new THREE.Matrix4().makeBasis(t, rdir, w);
      const key = k === (count - 1) / 2;
      const c = C.clone().addScaledVector(rdir, rMid + (key ? 0.08 : 0)).addScaledVector(w, key ? -0.06 : 0); c.y += springY;
      m.setPosition(c);
      const arc = (Math.PI * rMid) / count;
      if (key) {
        // keystone: taller, projecting, the guardian's mask carved on the arena side
        const kg = chamferBox(arc * 1.25, thk * 1.35, 1.7, 0.05, rng, 0.1);
        setOrnUv(kg, (p, n) => (n.z < -0.9 ? [0.5 - p.x / (arc * 1.25), p.y / (thk * 1.35) + 0.5, 1] : null));
        S.add(kg, m, st(blockTint(), { orn: { cell: ORN.mask, amount: erosion() * 1.1, su: 1, sv: 1 } }));
      } else S.add(chamferBox(arc - 0.02, thk, 1.55, 0.04, rng, 0.15), m, st(blockTint()));
    }
    // archivolt: a moulded band around the intrados on the arena face
    const n = Math.max(2, Math.round(12 * keep / count));
    const path = [];
    for (let k = 0; k <= n; k++) {
      const a = Math.PI - (k / 12) * Math.PI;
      const rdir = u.clone().multiplyScalar(Math.cos(a)).add(new THREE.Vector3(0, Math.sin(a), 0));
      const p = C.clone().addScaledVector(rdir, rIn + 0.04).addScaledVector(w, -0.775);
      p.y += springY;
      path.push({ p, side: w.clone().negate(), up: rdir });
    }
    if (keep === count) S.add(sweep([[0, 0], [0.05, 0.0], [0.05, 0.12], [0.08, 0.15], [0.08, 0.26], [0.0, 0.3]], path, { orn: { 3: [0, 1] } }), new THREE.Matrix4(), st(blockTint() * 0.95, { uv: 'keep', orn: { cell: ORN.laurel, amount: 0.8, su: 1 / 0.4, sv: 1 } }));
    const res = { A, B, C, u, w, chord, top: springY + rIn + thk };
    arches.push(res);
    return res;
  };
  const entabTop = {}; // pillar slot -> top of the entablature resting on it (the second storey stands there)
  for (const [a, b] of archPairs) {
    const r = voussoir(a, b, 9, 9);
    // spandrels over the capitals (an eclipse roundel each), and a moulded entablature across: architrave with two
    // fasciae, a frieze of eclipse phases, dentils and a corona
    const ang = Math.atan2(r.u.z, r.u.x);
    for (const s of [-1, 1]) {
      const p = r.C.clone().addScaledVector(r.u, s * (r.chord / 2 - 0.55));
      const sh = r.top - springY;
      const g = chamferBox(1.25, sh, 1.55, 0.05, rng, 0.2);
      setOrnUv(g, (q, n) => (n.z > 0.9 ? [q.x / 1.25 + 0.5, (q.y - sh / 2 + 1.2) / 1.15, 1] : null));
      S.add(g, trs(p.x, springY + sh / 2, p.z, -ang), st(blockTint(), { orn: { cell: panel(ORN.rosette), amount: erosion() * 0.9, su: 1, sv: 1 } }));
    }
    if (rng.chance(0.8)) {
      const prof = [[-0.9, 0], [0.9, 0], [0.9, 0.22], [0.95, 0.22], [0.95, 0.45], [1.0, 0.49], [0.94, 0.52], [0.94, 0.95], [0.99, 0.98], [1.03, 1.0], [1.03, 1.12], [1.2, 1.15], [1.23, 1.18], [1.23, 1.3], [1.26, 1.33, false], [1.22, 1.38, false], [1.12, 1.42], [-0.9, 1.42]];
      const half = r.chord / 2 + 0.45;
      const broken = rng.chance(0.35);
      const pieces = broken ? [[-half, rng.range(-0.6, 0.4)], [rng.range(0.9, 1.6), half]] : [[-half, half]];
      entabTop[a] = entabTop[b] = r.top + 1.42;
      for (const [s0, s1] of pieces) {
        const a0 = r.C.clone().addScaledVector(r.u, s0), a1 = r.C.clone().addScaledVector(r.u, s1);
        a0.y = a1.y = r.top;
        const g = sweep(prof, linePath(a0, a1, r.w.clone().negate(), 1), { orn: { 3: [0.1, 0.9, ORN.glyphs, 1 / 1.1], 6: [0, 1, ORN.phases, 1 / 0.5], 9: [0, 1, ORN.dentil, 1 / 0.13] } });
        const sag = broken && s1 < half ? new THREE.Matrix4().makeRotationAxis(r.w, rng.range(0.03, 0.08)) : new THREE.Matrix4();
        if (broken && s1 < half) sag.premultiply(new THREE.Matrix4().makeTranslation(a0.x, a0.y, a0.z)).multiply(new THREE.Matrix4().makeTranslation(-a0.x, -a0.y, -a0.z));
        S.add(g, sag, st(blockTint() * 0.95, { uv: 'keep', orn: { cell: ORN.phases, amount: erosion(), su: 1, sv: 1 } }));
      }
    }
  }
  for (const [a, b] of halfArch) voussoir(a, b, 9, 4);

  // second storey fragments on the best preserved bays
  for (const i of [5, 6, 16]) {
    const y0 = entabTop[i];
    if (!y0) continue; // nothing to stand on
    const p = pillars.find((q) => q.i === i).pos;
    const h = i === 6 ? 2.6 : rng.range(3.5, 5.0);
    const parts = latheGrid({
      rows: 4, segs: 24, profile: (t) => [0.62 * (1 - 0.08 * t), y0 - 0.05 + t * h],
      rmod: (phi) => ((Math.round(phi / (Math.PI * 2) * 24) % 2) ? 0.95 : 1),
      topY: (phi) => y0 + h - Math.abs(noise3(Math.cos(phi) + i, Math.sin(phi), 0) - 0.4) * 1.2, capTop: y0 + h - 0.5,
    });
    setOrnUv(parts[0], (q, n, k) => [((k % 25) / 24) * 12, 0.5, 1]);
    addAll(S, parts, trs(p.x, 0, p.z, 0), { color: stoneColor(blockTint()), glow, uv: 'keep', uvScale: 2.4, orn: fluteOrn(0.9) });
  }

  // ---- seating tier (cavea): settled irregular seats, stairways, a parapet walk, slumps and collapses -----------------
  S.section('tier');
  const steps = 11, stepD = (LAYOUT.tierR1 - LAYOUT.tierR0) / steps, stepH = 0.52, tierBase = 3.6;
  const walk = 5; // the praecinctio: row 5 is a walkway with a carved parapet behind it
  const tierLimit = (th) => {
    const a = Math.abs(th);
    const g0 = th < 0 ? gap + 9 * DEG : gap + 5 * DEG;
    if (a < g0) return 0;
    return Math.min(steps, Math.floor(((a - g0) / (16 * DEG)) * steps + 2.4 * noise3(th * 11, 2.0, 0.0) + 1.2 * noise3(th * 37, 5.0, 1.0) - 0.6));
  };
  // slumps: zones where the upper rows have slid down into the lower ones
  const slump = (th, k) => {
    const s = noise3(th * 4.3 + 11, 0.7, 2.2) + 0.25 * noise3(th * 13 + 2, k * 0.4, 5.5);
    return s > 0.6 ? clamp((s - 0.6) / 0.22, 0, 1) * smoothstep(1, 6, k) : 0;
  };
  // holes: a few blocks gone together (robbed for stone), with their neighbours settled into the gap
  const hole = (th, k) => noise3(th * 21 + 7, k * 0.55, 9.1) > 0.7;
  const stairEvery = 9.5 * DEG;
  const isStair = (th) => { const f = ((th / stairEvery) % 1 + 1) % 1; return f < 0.6 / (LAYOUT.tierR0 * stairEvery) * 1.6; };
  const tumbled = [];
  for (let k = 0; k < steps; k++) {
    const r0 = LAYOUT.tierR0 + k * stepD;
    const rc = r0 + stepD / 2;
    const top0 = tierBase + (k + 1) * stepH;
    let th = -thetaMax;
    while (th < thetaMax) {
      const L = rng.range(0.8, 2.6);
      const dth = L / rc;
      const tc = th + dth / 2;
      th += dth + rng.range(0.004, 0.05) / rc;
      const lim = tierLimit(tc);
      if (k >= lim) {
        // the ragged collapse edge: blocks that slid off lie tumbled on the rows below
        if (k === lim && k > 0 && rng.chance(0.45)) tumbled.push({ r: rc - stepD * rng.range(0.6, 2.2), th: tc + rng.range(-0.01, 0.01), k: Math.max(0, k - rng.int(1, 3)), L });
        continue;
      }
      const sl = slump(tc, k);
      if (sl > 0.75 || hole(tc, k) || rng.chance(0.045 + sl * 0.3)) {
        if (rng.chance(0.5)) tumbled.push({ r: rc - stepD * rng.range(0.4, 2.5), th: tc, k: Math.max(0, k - rng.int(1, 3)), L });
        continue;
      }
      const nearHole = hole(tc + dth, k) || hole(tc - dth, k);
      const settle = rng.range(-0.1, 0.04) - sl * rng.range(0.2, 0.6) - (nearHole ? rng.range(0.05, 0.2) : 0);
      const h = top0 + settle;
      const fwd = sl * rng.range(0.1, 0.5);
      const p = ringPos(rc - fwd, tc, h / 2);
      const tiltX = sl > 0 ? rng.range(0.02, 0.12) * sl : rng.range(-0.03, 0.02);
      const tiltZ = rng.range(-0.025, 0.025) + sl * rng.range(-0.08, 0.08) + (nearHole ? rng.range(-0.06, 0.06) : 0);
      const yaw = -tc + rng.range(-0.025, 0.025) + sl * rng.range(-0.08, 0.08);
      const m = trs(p.x, p.y, p.z, yaw, tiltX, tiltZ);
      const back = k === steps - 1 || k + 1 >= lim || sl > 0;
      const tint = blockTint() * 0.9;
      if (k === walk) {
        // walkway slab, deeper, then the parapet with an inscribed coping
        S.add(seatBlock(L - 0.03, h, stepD + 0.02, 0.05, back), m, st(tint));
        continue;
      }
      if (isStair(tc) && k !== walk) {
        // stairway: two half-height treads in the seat's depth
        for (let s = 0; s < 2; s++) {
          const hh = h - stepH * 0.5 * (1 - s);
          const pp = ringPos(rc - stepD * 0.25 + s * stepD * 0.5, tc, hh / 2);
          S.add(seatBlock(Math.min(L, 1.1), hh, stepD * 0.5, 0.03, s === 1 && back), trs(pp.x, pp.y, pp.z, yaw), st(tint * 1.05));
        }
        continue;
      }
      const g = sl > 0.3 || rng.chance(0.05) ? chamferBox(L - 0.04, h, stepD + 0.02, 0.05, rng, 0.45) : seatBlock(L - 0.04, h, stepD + 0.02, rng.range(0.05, 0.12), back);
      S.add(g, m, st(tint));
    }
  }
  // the parapet behind the walkway: blocks with a glyph band, broken in places
  {
    const r = LAYOUT.tierR0 + (walk + 1) * stepD + 0.15;
    const y0 = tierBase + (walk + 1) * stepH;
    let th = -thetaMax;
    while (th < thetaMax) {
      const L = rng.range(1.6, 2.6);
      const dth = L / r;
      const tc = th + dth / 2;
      th += dth + 0.01 / r;
      if (tierLimit(tc) <= walk + 1 || slump(tc, walk) > 0.2 || rng.chance(0.12)) continue;
      const hh = rng.chance(0.2) ? rng.range(0.4, 0.8) : 0.95;
      const p = ringPos(r, tc, y0 + hh / 2);
      const g = hh < 0.9 ? brokenBlock(L - 0.03, hh, 0.32, rng, { jag: 0.4 }) : chamferBox(L - 0.03, hh, 0.32, 0.03, rng, 0.2);
      S.add(g, trs(p.x, p.y, p.z, -tc), st(blockTint() * 0.88, { orn: { cell: ORN.glyphs, amount: erosion(), su: L / 1.0, sv: 1, ov: 0, fn: frontFace(L - 0.03, hh) } }));
    }
  }
  // what a tumbled block lands on: the top of a surviving seat row under it, else the ground of the collapse
  const tierTop = (r, th) => {
    const k = Math.floor((r - LAYOUT.tierR0) / stepD);
    if (k < 0 || k >= steps || k >= tierLimit(th) || slump(th, k) > 0.75 || hole(th, k)) return 0;
    return tierBase + (k + 1) * stepH;
  };
  for (const t of tumbled) {
    const L = Math.min(t.L, rng.range(0.8, 1.8));
    const bh = stepH * rng.range(0.7, 1);
    const p = ringPos(t.r, t.th, tierTop(t.r, t.th) + bh * 0.32);
    S.add(rng.chance(0.5) ? chamferBox(L, bh, stepD * rng.range(0.8, 1.1), 0.05, rng, 0.6) : brokenBlock(L, bh, stepD, rng, { jag: 0.6, bottom: true }), trs(p.x, p.y, p.z, -t.th + rng.range(-0.6, 0.6), rng.range(-0.3, 0.3), rng.range(-0.25, 0.25)), st(blockTint() * 0.85));
  }
  // exposed substructure where the tier has collapsed: radial vault walls with arched openings
  S.section('vaults');
  for (const sgn of [-1, 1]) {
    for (const off of [3.5, 9.5, 15.5]) {
      const th = sgn * (gap + off * DEG);
      const lim = tierLimit(th);
      if (lim > 7) continue;
      const tint = blockTint() * 0.7;
      const r0 = LAYOUT.tierR0 + 0.4, r1 = LAYOUT.tierR1 - 0.5;
      const Hw = tierBase + Math.max(1, lim) * stepH;
      // two piers and a round arch between them (in the radial plane), the wall above broken
      const ux = Math.sin(th), uz = -Math.cos(th);
      const dirR = new THREE.Vector3(ux, 0, uz);
      const side = new THREE.Vector3(-uz, 0, ux);
      const yaw = Math.atan2(-dirR.z, dirR.x);
      const span = r1 - r0, pierW = 1.1, open = span - 2 * pierW;
      for (const [rr, w] of [[r0 + pierW / 2, pierW], [r1 - pierW / 2, pierW]]) {
        const p = dirR.clone().multiplyScalar(rr);
        S.add(brokenBlock(w, Hw, 0.9, rng, { jag: 0.15 }), trs(p.x, Hw / 2, p.z, yaw), st(tint));
      }
      const C = dirR.clone().multiplyScalar((r0 + r1) / 2);
      const rA = open / 2;
      const yS = Math.min(Hw - rA - 0.6, 2.2);
      const n = 9;
      for (let k = 0; k < n; k++) {
        if (rng.chance(0.15)) continue;
        const a = Math.PI - ((k + 0.5) / n) * Math.PI;
        const rd = dirR.clone().multiplyScalar(Math.cos(a)).add(new THREE.Vector3(0, Math.sin(a), 0));
        const t = dirR.clone().multiplyScalar(-Math.sin(a)).add(new THREE.Vector3(0, Math.cos(a), 0));
        const m = new THREE.Matrix4().makeBasis(t, rd, side);
        const c = C.clone().addScaledVector(rd, rA + 0.3); c.y += yS;
        m.setPosition(c);
        S.add(chamferBox((Math.PI * (rA + 0.3)) / n - 0.03, 0.6, 0.85, 0.04, rng, 0.3), m, st(tint));
      }
      // rubble fill and the masonry above the arch, broken off
      const fillH = Math.max(0.4, Hw - (yS + rA + 0.6));
      const fp = C.clone(); fp.y = yS + rA + 0.6 + fillH / 2;
      S.add(brokenBlock(open + 0.6, fillH, 0.85, rng, { jag: 0.7, nx: 4, nz: 1 }), trs(fp.x, fp.y, fp.z, yaw), st(tint * 0.9));
    }
  }
  // outer facade fragments rising above the tier on the flanks (piers and recessed bays, broken tops, a string course)
  S.section('facade');
  for (const [d0, d1, h] of [[-112, -64, 13.5], [52, 98, 12.6]]) {
    const R = LAYOUT.tierR1 + 0.6;
    let th = d0 * DEG;
    while (th < d1 * DEG) {
      const L = rng.range(2.2, 3.4);
      const dth = L / R;
      const t0 = th, tc = th + dth / 2;
      th += dth;
      const hh = h * (0.55 + 0.45 * noise3(tc * 6, 0.3, 4.4)) + rng.range(-0.5, 0.5);
      const pier = Math.round(tc / (6 * DEG)) % 2 === 0;
      const depth = pier ? 1.6 : 1.1, rc = R + (pier ? 0 : 0.25);
      const p = ringPos(rc, tc, hh / 2);
      S.add(brokenBlock(L - 0.05, hh, depth, rng, { jag: 0.12, nx: 2, nz: 1 }), trs(p.x, p.y, p.z, -tc), st(blockTint() * 0.85));
      // string courses on this block's inner face, only below the lowest point of its broken top
      if (mid) {
        for (const yy of [8.2, 11.4]) {
          if (hh * 0.88 > yy + 0.4 && rng.chance(0.85)) S.add(sweep([[0, 0], [0.12, 0.04], [0.14, 0.18], [0.1, 0.24], [0, 0.26]], arcPath(rc - depth / 2 + 0.01, t0 + 0.02 / R, t0 + (L - 0.07) / R, yy, 2)), new THREE.Matrix4(), st(0.8, { uv: 'keep' }));
        }
      }
    }
  }

  // ---- fallen and toppled pieces -----------------------------------------------------------------------------------
  S.section('fallen');
  // a fallen column drum (axis +Y from 0 to len): the standing shafts' 20 flutes (40 segments), but weathered from
  // lying in the open: shallow worn channels, a chunk knocked off one arris; `broken` shatters the top end
  const drumGeo = (len, seed, broken = false) => {
    const segs = FSEG;
    const bite = rng.range(0, Math.PI * 2), biteW = rng.range(0.4, 0.8);
    const parts = latheGrid({
      rows: 2, segs, profile: (t) => [pierR * 0.97, t * len],
      rmod: (phi, yy) => {
        let m = ((Math.round(phi / (Math.PI * 2) * segs) % 2) ? 0.97 : 1) * (1 + (noise3(Math.cos(phi) * 2 + seed, yy * 1.2, Math.sin(phi) * 2) - 0.5) * 0.08);
        const d = Math.abs(((phi - bite + Math.PI * 3) % (Math.PI * 2)) - Math.PI);
        if (d < biteW) m *= 1 - 0.16 * (1 - d / biteW) * (0.6 + 0.4 * Math.sin((yy / len) * Math.PI));
        return m;
      },
      topY: broken ? (phi) => len - 0.05 - (0.5 + 0.5 * Math.cos(phi - bite)) * 0.5 - Math.abs(noise3(Math.cos(phi) * 1.5 + seed, Math.sin(phi) * 1.5, 3.3) - 0.35) * 0.5 : null,
      capTop: broken ? len - 0.4 : true, capBottom: true,
    });
    setOrnUv(parts[0], (q, n, k) => [((k % (segs + 1)) / segs) * FLUTES, q.y / len, 1]);
    return parts;
  };
  const drumOpt = () => ({ color: stoneColor(blockTint()), glow, uv: 'box', uvScale: 2.4, orn: fluteOrn(0.65) });
  /**
   * A drum lying on its side, centre `sink` m below its resting height, its axis across the line of sight from the
   * fight-camera side (+ `yaw` radians) so the camera sees its fluted flank, not its end (`axis`: an absolute yaw
   * instead); or standing on end.
   */
  const layDrum = (x, z, yaw, len, sink, { upright = false, broken = false, roll = 0, axis = null } = {}) => {
    const seed = rng.range(0, 40);
    const ry = axis !== null ? axis : Math.atan2(0.6 * x, z - 9) + yaw;
    const m = upright
      ? trs(x, -sink, z, ry, rng.range(-0.16, 0.16), rng.range(0.1, 0.2))
      : trs(x, pierR * 0.97 - sink, z, ry, roll, Math.PI / 2 + rng.range(-0.06, 0.06)).multiply(trs(0, -len / 2, 0));
    addAll(S, drumGeo(len, seed, broken), m, drumOpt());
  };
  // none in the middle of the vista (a 1.9 m drum on the horizon reads as a parked lump); poses vary so they never
  // read as a row of identical crates
  // the vista shoulders: end-on to the fight camera, so their silhouettes stay low and small against the horizon
  layDrum(-6.3, -14.0, 0, 1.2, 0.35, { broken: true, axis: 0.75 });
  layDrum(6.6, -16.8, 0, 1.5, 0.55, { axis: 2.3 });
  layDrum(-7.4, -17.4, 0, 1.4, 0.6, { axis: 0.9 });
  layDrum(5.6, -13.9, 0, 1.0, 0.3, { broken: true, axis: 2.6 });
  // by the right wall: one landed on its end (its top shattered), two lying
  layDrum(12.4, -7.6, 0, 1.6, 0.3, { upright: true, broken: true });
  layDrum(13.4, -4.7, 0.25, 1.4, 0.12);
  layDrum(13.0, -1.9, -0.45, 0.95, 0.3, { roll: 0.6 });
  layDrum(-13.0, -6.2, 0.35, 1.3, 0.1);
  // a toppled column by the left wall: its drums still roughly in line, settled at different depths (the last one the
  // broken top of the shaft), and its capital upside down on the floor behind them, clear of the fight line
  {
    const start = new THREE.Vector3(-14.5, 0, 2.1), dir = new THREE.Vector3(0.83, 0, -0.56).normalize();
    const yaw = Math.atan2(-dir.z, dir.x);
    const side = new THREE.Vector3(-dir.z, 0, dir.x);
    let s = 0;
    for (let k = 0; k < 3; k++) {
      const len = k === 2 ? 1.1 : rng.range(1.35, 1.6);
      const c = start.clone().addScaledVector(dir, s + len / 2 + k * 0.1).addScaledVector(side, [0, 0.22, -0.3][k]);
      layDrum(c.x, c.z, 0, len, [0.38, 0.5, 0.3][k], { broken: k === 2, roll: [0, 0.4, 2.1][k], axis: yaw + [0.04, -0.12, 0.2][k] });
      s += len;
    }
    // capital, fallen upside down: abacus sunk into the floor, egg-and-dart echinus and the astragal above it, a
    // stub of the shaft still on top
    const cap = new THREE.Vector3(-12.3, 0, -3.3);
    const place = trs(cap.x, -0.12, cap.z, yaw + 0.5, 0.1, -0.07);
    const ab = chamferBox(2.3, 0.38, 2.3, 0.05, rng, 0.5);
    setOrnUv(ab, sideFaces(2.3, 0.38, 2.3));
    S.add(ab, place.clone().multiply(trs(0, 0.19, 0)), st(blockTint(), { orn: { cell: ORN.phases, amount: 0.8, su: 6, sv: 1 } }));
    const ech = latheGrid({ rows: 4, segs: 32, profile: (t) => { const u = 1 - t; return [pierR * 0.88 + 0.44 * Math.sin(u * Math.PI * 0.5) * (0.75 + 0.25 * u), 0.38 + t * 0.36]; } });
    setOrnUv(ech[0], (p, n, k) => [((k % 33) / 32) * 14, 1 - Math.floor(k / 33) / 4, 1]);
    const tint = blockTint();
    addAll(S, ech, place, { color: stoneColor(tint), glow, uv: 'box', uvScale: 2.4, orn: { cell: ORN.eggDart, amount: 0.9, su: 1, sv: 1 } });
    addAll(S, latheGrid({ rows: 3, segs: 28, profile: (t) => [pierR * 0.9 + 0.07 * Math.sin(t * Math.PI), 0.74 + t * 0.14] }), place, { color: stoneColor(tint), glow, uv: 'box', uvScale: 2.4 });
    addAll(S, drumGeo(0.75, rng.range(0, 40), true), place.clone().multiply(trs(0, 0.86, 0)), drumOpt());
  }
  // fallen voussoirs under the broken half arch, fallen cornice runs and a keystone at the wall base
  {
    const A = pillars.find((p) => p.i === 8).pos;
    for (let k = 0; k < 4; k++) {
      const p = A.clone().multiplyScalar(rng.range(0.88, 0.95)).add(new THREE.Vector3(rng.range(-1.2, 1.2), 0, rng.range(-1.2, 1.2)));
      S.add(chamferBox(0.9, 0.78, 1.5, 0.04, rng, 0.6), trs(p.x, 0.32, p.z, rng.range(0, 6), rng.range(-0.4, 0.4), rng.range(1.0, 1.4)), st(blockTint()));
    }
    for (const th of [-62, -18.5, 34, 71, 101].map((d) => d * DEG)) {
      // a cornice block lying on its back at the wall base, half in the gutter
      const c = ringPos(rng.range(14.4, 14.9), th, 0);
      const g = sweep(corProf, linePath(new THREE.Vector3(-0.85, 0, 0), new THREE.Vector3(0.85, 0, 0), new THREE.Vector3(0, 0, 1), 1), { orn: corOrn });
      S.add(g, trs(c.x, 0.02, c.z, -th + rng.range(-0.5, 0.5), rng.range(-1.35, -0.95), rng.range(-0.15, 0.15)), st(blockTint() * 0.8, { uv: 'keep', orn: { cell: ORN.dentil, amount: 0.8, su: 1, sv: 1 } }));
    }
  }

  // ---- rubble -----------------------------------------------------------------------------------------------------
  S.section('rubble');
  const rubbleN = Math.round(170 * tier.rubble);
  for (let i = 0; i < rubbleN; i++) {
    let p, s, blockChance = 0.35;
    const roll = rng();
    if (roll < 0.45) { // along the wall base, inside the arena (keeps clear of the fight line)
      const th = rng.range(-thetaMax * 0.9, thetaMax * 0.9);
      const a = Math.abs(th);
      const near = a < gap ? 0.75 : 0.35;
      if (!rng.chance(near)) continue;
      p = ringPos(rng.range(14.2, 15.4), th, 0); s = rng.range(0.12, a < gap ? 0.7 : 0.45);
    } else if (roll < 0.75) { // the gap: on the outer ground up to the edge, low in the middle of the vista
      const th = rng.range(-gap - 6 * DEG, gap + 6 * DEG);
      const mid2 = 1 - smoothstep(0.35, 0.8, Math.abs(th) / gap);
      p = ringPos(rng.range(15.8, edgeR(th) - 0.3), th, 0); s = rng.range(0.2, 0.95) * (1 - 0.6 * mid2);
      blockChance = 0.75; // broken ashlar, not boulders: this rubble is silhouetted against the horizon
    } else { // at broken pillar feet and tier breaks
      const pl = rng.pick(pillars.filter((q) => !q.state || !q.state.cap));
      const a = rng.range(0, Math.PI * 2), d = rng.range(1.0, 3.2);
      p = pl.pos.clone().add(new THREE.Vector3(Math.cos(a) * d, 0, Math.sin(a) * d));
      if (p.length() < 15.2) continue;
      s = rng.range(0.25, 1.1);
    }
    const isBlock = rng.chance(blockChance);
    const g = isBlock ? (rng.chance(0.5) ? brokenBlock(s * rng.range(1.2, 2.2), s * rng.range(0.6, 1.0), s * rng.range(0.9, 1.4), rng, { jag: 0.5, nx: 2, nz: 1, bottom: true }) : chamferBox(s * rng.range(1.2, 2.2), s * rng.range(0.6, 1.0), s * rng.range(0.9, 1.4), 0.04, rng, 0.6)) : rock(s, rng, { detail: s > 0.5 ? 1 : 0, squash: rng.range(0.45, 0.8) });
    S.add(g, trs(p.x, s * (isBlock ? 0.3 : 0.25), p.z, rng.range(0, 6), rng.range(-0.3, 0.3), rng.range(-0.3, 0.3)), st(blockTint() * 0.9));
  }
  // chips and grit drifted against the wall base and around the piers (small, many, cheap)
  const chipN = Math.round(160 * tier.rubble);
  for (let i = 0; i < chipN; i++) {
    const th = rng.range(-thetaMax * 0.95, thetaMax * 0.95);
    const r = 15.55 - Math.pow(rng(), 2.2) * 1.6;
    const p = ringPos(r, th + rng.range(-0.01, 0.01), 0);
    if (Math.abs(p.z) < 3 && Math.abs(p.x) < 13) continue;
    const s = rng.range(0.04, 0.16);
    S.add(rock(s, rng, { detail: 0, squash: rng.range(0.4, 0.8), rough: 0.45 }), trs(p.x, s * 0.2, p.z, rng.range(0, 6)), st(blockTint() * 0.85));
  }

  // ---- braziers: carved stone pedestals (iron bowls go in the metal builder) ------------------------------------------
  S.section('braziers');
  const brazierTops = [];
  for (const b of braziers) {
    const th = Math.atan2(b.x, -b.z);
    S.add(chamferBox(1.05, 0.22, 1.05, 0.04, rng, 0.2), trs(b.x, 0.11, b.z, -th), st(0.9));
    const ped = latheGrid({ rows: 7, segs: 16, profile: (t) => [0.32 - 0.08 * Math.sin(t * Math.PI) + (t > 0.85 ? 0.08 : 0) + (t < 0.12 ? 0.06 * (1 - t / 0.12) : 0), 0.22 + t * 0.78], capTop: true });
    setOrnUv(ped[0], (p, n, k) => [((k % 17) / 16) * 4, (p.y - 0.42) / 0.36, 1]);
    addAll(S, ped, trs(b.x, 0, b.z, Math.PI / 8), { color: stoneColor(0.85), glow, uv: 'box', orn: { cell: panel(ORN.phases), amount: 0.9, su: 1, sv: 1 } });
    // iron bowl with a rolled rim and three claws
    addAll(M, latheGrid({ rows: 6, segs: 20, profile: (t) => [0.18 + 0.42 * Math.sin(t * Math.PI * 0.5), 1.0 + t * 0.34] }), trs(b.x, 0, b.z), { color: [1, 1, 1] });
    addAll(M, latheGrid({ rows: 4, segs: 20, profile: (t) => [0.6 + 0.04 * Math.sin(t * Math.PI * 2), 1.34 + 0.04 * Math.cos(t * Math.PI * 2)] }), trs(b.x, 0, b.z), { color: [1, 1, 1] });
    for (let k = 0; k < 3; k++) {
      const a = (k / 3) * Math.PI * 2 + th;
      const g = chamferBox(0.07, 0.62, 0.12, 0.02);
      M.add(g, trs(b.x + Math.cos(a) * 0.36, 1.12, b.z + Math.sin(a) * 0.36, -a, 0, 0.5 * (k % 2 ? 1 : -1) * 0.2), { color: [1, 1, 1] });
    }
    brazierTops.push(new THREE.Vector3(b.x, 1.36, b.z));
  }

  // ---- banners: hang points + iron poles -----------------------------------------------------------------------------
  const banners = [];
  const onPillar = [5, 7, 13, 16, 4, 14, 17, 6];
  for (const i of onPillar.slice(0, tier.banners)) {
    const pl = pillars.find((q) => q.i === i);
    const inward = pl.pos.clone().setY(0).normalize().multiplyScalar(-1);
    const top = pl.pos.clone().addScaledVector(inward, pierR + 0.18);
    top.y = 7.35;
    banners.push({ top, normal: inward.clone(), width: rng.range(1.25, 1.5), length: rng.range(3.7, 4.0), seed: rng.range(0, 100) });
    const ang = Math.atan2(inward.z, inward.x);
    M.add(chamferBox(1.9, 0.07, 0.07, 0.015), trs(top.x, top.y + 0.05, top.z, -ang + Math.PI / 2), { color: [0.8, 0.8, 0.8] });
    M.add(chamferBox(0.05, 0.05, 0.42, 0.01), trs(top.x - inward.x * 0.2, top.y + 0.05, top.z - inward.z * 0.2, -ang + Math.PI / 2), { color: [0.8, 0.8, 0.8] });
  }

  // ---- dressing ------------------------------------------------------------------------------------------------------
  const flames = dressRuins({ S, M, P, rng, tier, braziers, pillars, arches, stoneColor, glow, wallTopAt, courseY, courses, ringPos });

  const sections = { ...S.tris };
  for (const [k, v] of Object.entries(M.tris)) sections['iron.' + k] = v;
  for (const [k, v] of Object.entries(P.tris)) sections['props.' + k] = v;
  return { stone: S.build(), metal: M.build(), props: P.build(), banners, braziers: brazierTops, flames, sections };
}
