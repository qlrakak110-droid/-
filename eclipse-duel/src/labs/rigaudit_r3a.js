// Rig audit lab, round 3, lens "deformation, range of motion, cloth and contact (re-audit)" (auditor's sandbox,
// READ-ONLY on src/char and on the fighter art / clip files: they are imported, never modified).
//
// Extends the round-2 lens lab (rigaudit_r2a: same body cores, same cloth / plate / contact metrics, so round-2 numbers
// are comparable) with what round 2 did not measure, on the REAL fighter designs playing their REAL clips:
//
//   band 1     rendered cloth vertices between the first and second free particle rows (round 2 excluded them; the
//              round-3 cloth lets that row ignore the capsules it rests in, so this is where it can now pass the body)
//   mask       free particles deeper in a design capsule than the cloth's own per-particle allowance (solver failure)
//   shear      largest shear-edge stretch (the strain limit covers shear edges too)
//   pop        largest 2nd difference of a structural edge vector (mm / frame^2): one particle snapping against its
//              neighbours (collision / strain-limit pops), independent of the whole sheet's motion
//   blade      weapon (blade slot) vertices inside a body core (the blade through the wielder's own body)
//   wcloth     free cloth particles inside the weapon's volume (cape / tails cut by the weapon: cloth ignores weapons)
//   body floor plate / suit vertices below the floor (lying / kneeling poses sinking into the ground)
//   legs       left / right thigh + shin cores overlapping (legs through each other)
//   arm>torso  arm plate / suit vertices inside the spine / chest / hips cores; tasset>torso: tasset plates in them
//
//   __ED.r3a.scan(id, clips?, opts)          per-clip summary (opts: { hz = 60, pre = idle clip, tail = 0.25 s, full })
//   __ED.r3a.hold(id, clip, t, opts)         run a clip from 0 to t at 60 Hz (cloth evolves) and hold it (captures)
//   __ED.r3a.dt(id, clip)                    cloth + spring tips at 30 / 120 Hz, alternating, 0.1x, hit-stop vs 60 Hz
//   __ED.r3a.rest(id)                        still pose: cloth / spring jitter and creep after settling
//   __ED.r3a.recover(id, clip)               clip then idle: cloth distance from the settled idle cloth after 1 / 2 s
//   __ED.r3a.volume(id, poses)               elbow / knee suit volume (round-2 R2A-08 measurement)
//   __ED.r3a.cpu(id, chain, replays)         ms per update: mean of per-frame minima, the reset (re-hang) frame, max
//   __ED.r3a.queue(items) + --each "__ED.r3a.step()"   captures: [id, clip, t, focus, yaw, dist, pitch, holes, slots, fade]

import * as THREE from 'three';
import { createLab, ORDER } from '../core/lab.js';
import { createCharacter, definePose, invalidateClips, listClips } from '../char/index.js';
import { Cloth } from '../char/cloth.js';
import { SpringChain } from '../char/spring.js';
import { getClip } from '../char/anim.js';
import { knight } from '../char/designs/knight.js';
import { kael } from '../fighters/kael/design.js';
import { iska } from '../fighters/iska/design.js';
import { vorn } from '../fighters/vorn/design.js';
import '../char/clips/demo.js';
import '../fighters/kael/clips/index.js';
import '../fighters/iska/clips/index.js';
import '../fighters/vorn/clips/index.js';

const DESIGNS = { knight, kael, iska, vorn };
const IDLE = { knight: 'demo.idle', kael: 'kael.idle', iska: 'iska.idle', vorn: 'vorn.idle' };
const HULL_SHRINK = 0.85;
const HULL_BONES = /^(hips|spine|chest|neck|head|upperArm[RL]|upperArmTwist[RL]|elbow[RL]|foreArm[RL]|foreArmTwist[RL]|thigh[RL]|knee[RL]|shin[RL]|deltoid[RL])$/;
const ARM_BONES = /^(upperArm|upperArmTwist|elbow|elbowVol|foreArm|foreArmTwist|hand|fingers|fingerTips|thumb)[RL]$/;

// ---- observation hook: capture the Cloth / SpringChain instances of a character (restored after use) ------------------
const ORIG = { cloth: Cloth.prototype.update, spring: SpringChain.prototype.update };
const HOOK = { cloths: [], springs: [] };
function hookCapture(on) {
  Cloth.prototype.update = on ? function (...a) { if (!a[8] && !HOOK.cloths.includes(this)) HOOK.cloths.push(this); return ORIG.cloth.apply(this, a); } : ORIG.cloth;
  SpringChain.prototype.update = on ? function (...a) { if (!HOOK.springs.includes(this)) HOOK.springs.push(this); return ORIG.spring.apply(this, a); } : ORIG.spring;
}

const _m = new THREE.Matrix4(), _inv = new THREE.Matrix4(), _v = new THREE.Vector3();
const pct = (arr, q) => { const s2 = Float64Array.from(arr).sort(); return s2[Math.min(s2.length - 1, Math.floor(q * s2.length))]; };
const r4 = (x) => +(+x).toFixed(4);

createLab({
  view: { target: [0, 1.05, 0], dist: 3.2, yaw: 30, pitch: 6, fov: 40 },
  setup(ctx, lab) {
    lab.lights.key.intensity = 2.6;
    lab.lights.rim.intensity = 2.2;
    const built = {};
    let cur = null;

    function use(id) {
      if (!built[id]) built[id] = prepare(id);
      for (const C of Object.values(built)) C.ch.setVisible(C.id === id);
      cur = built[id];
      return id;
    }

    function prepare(id) {
      const ch = createCharacter(ctx, DESIGNS[id], { name: 'r3a_' + id });
      ch.play(IDLE[id], { fade: 0 });
      HOOK.cloths.length = 0; HOOK.springs.length = 0;
      hookCapture(true);
      try { ch.update(1 / 60, 1 / 60); } finally { hookCapture(false); }
      const rig = ch.rig, N = rig.count;
      const cloths = HOOK.cloths.filter((c) => c.rig === rig), springs = HOOK.springs.filter((s) => s.rig === rig);
      const firstCloth = Math.min(N, ...cloths.map((c) => c.first));
      const isCloth = (b) => b >= firstCloth;
      const slots = {};
      for (const [slot, mesh] of Object.entries(ch.meshes)) {
        const g = mesh.geometry, n = g.attributes.position.count, I = g.attributes.skinIndex.array, W = g.attributes.skinWeight.array;
        const dom = new Int32Array(n);
        for (let v = 0; v < n; v++) { let b = 0, bw = -1; for (let k = 0; k < 4; k++) if (W[v * 4 + k] > bw) { bw = W[v * 4 + k]; b = I[v * 4 + k]; } dom[v] = b; }
        slots[slot] = { mesh, g, n, dom };
      }
      // cloth vertices: band 0 = touches the pinned row(s) (skipped), 1 = touches the first free row, 2 = below
      const clothVerts = [];
      const clothOf = (b) => cloths.find((c) => b >= c.first && b < c.first + c.n);
      for (const [slot, S] of Object.entries(slots)) {
        const I = S.g.attributes.skinIndex.array, W = S.g.attributes.skinWeight.array;
        for (let v = 0; v < S.n; v++) {
          if (!isCloth(S.dom[v])) continue;
          const cl = clothOf(S.dom[v]);
          let band = 2;
          for (let k = 0; k < 4; k++) {
            const b = I[v * 4 + k];
            if (!(W[v * 4 + k] > 1e-4) || !cl || b < cl.first || b >= cl.first + cl.n) continue;
            const row = ((b - cl.first) / cl.C) | 0;
            if (row < cl.layout.pinRows) band = 0; else if (row < cl.layout.pinRows + 1 && band > 1) band = 1;
          }
          clothVerts.push({ slot, v, band, cloth: cl ? cl.layout.spec.name : '?' });
        }
      }
      // body cores (identical to rigaudit_r2a, so round-2 numbers compare)
      const inv = ch.skeleton.boneInverses;
      const acc = new Map();
      for (const [slot, S] of Object.entries(slots)) {
        if (slot !== 'plate' && slot !== 'suit') continue;
        const P = S.g.attributes.position.array;
        for (let v = 0; v < S.n; v++) {
          const b = S.dom[v];
          if (isCloth(b) || !HULL_BONES.test(rig.names[b])) continue;
          _v.fromArray(P, v * 3).applyMatrix4(inv[b]);
          let a = acc.get(b);
          if (!a) { a = []; acc.set(b, a); }
          a.push(_v.x, _v.y, _v.z);
        }
      }
      const hulls = [];
      for (const [b, a] of acc) {
        const n = a.length / 3;
        if (n < 30) continue;
        const xs = [], ys = [], zs = [];
        for (let i = 0; i < n; i++) { xs.push(a[i * 3]); ys.push(a[i * 3 + 1]); zs.push(a[i * 3 + 2]); }
        const cx = pct(xs, 0.5), cz = pct(zs, 0.5), y0 = pct(ys, 0.1), y1 = pct(ys, 0.9);
        const rad = [];
        for (let i = 0; i < n; i++) rad.push(Math.hypot(xs[i] - cx, zs[i] - cz));
        const r = pct(rad, 0.35) * HULL_SHRINK;
        hulls.push({ bone: b, name: rig.names[b], a: [cx, y0, cz], b: [cx, y1, cz], r, n });
      }
      // vertex sets that must stay out of some cores (vertices already inside in the bind pose excluded)
      const sets = [];
      const addSet = (label, slotList, srcRe, hullRe, every = 1) => {
        const targets = hulls.filter((h) => hullRe.test(h.name));
        for (const slot of slotList) {
          const S = slots[slot];
          if (!S) continue;
          const P0 = S.g.attributes.position.array, verts = [];
          for (let v = 0; v < S.n; v += every) {
            const b = S.dom[v];
            if (isCloth(b) || !srcRe.test(rig.names[b])) continue;
            let inBind = false;
            for (const h of targets) {
              if (h.bone === b) { inBind = true; break; }
              _v.fromArray(P0, v * 3).applyMatrix4(inv[h.bone]);
              if (ell(h, _v.x, _v.y, _v.z) > 0) inBind = true;
            }
            if (!inBind) verts.push(v);
          }
          sets.push({ label, slot, verts: Int32Array.from(verts), targets });
        }
      };
      addSet('tasset->thigh', ['plate'], /^tasset[RL]$/, /^thigh[RL]$/);
      addSet('arm->chest', ['plate'], /^(upperArm|upperArmTwist|elbow|foreArm|foreArmTwist)[RL]$/, /^chest$/);
      addSet('arm->torso', ['plate', 'suit'], ARM_BONES, /^(hips|spine|chest)$/, 2);
      addSet('arm->legs', ['plate', 'suit'], ARM_BONES, /^(thigh|shin)[RL]$/, 2);
      addSet('tasset->torso', ['plate'], /^tasset[RL]$/, /^(hips|spine)$/);
      addSet('legR->legL', ['plate', 'suit'], /^(thigh|thighTwist|knee|kneeVol|shin|foot|toe)R$/, /^(thigh|shin)L$/, 2);
      addSet('legL->legR', ['plate', 'suit'], /^(thigh|thighTwist|knee|kneeVol|shin|foot|toe)L$/, /^(thigh|shin)R$/, 2);
      // blade vertices (every slot vertex dominated by a weapon bone) vs every core
      const blade = [];
      for (const [slot, S] of Object.entries(slots)) {
        if (slot === 'cloth') continue;
        for (let v = 0; v < S.n; v += 2) if (/^weapon[RL]$/.test(rig.names[S.dom[v]])) blade.push([slot, v]);
      }
      // body vertices for the floor test (plate / suit, non-cloth), every 3rd
      const floorV = [];
      for (const slot of ['plate', 'suit']) { const S = slots[slot]; if (!S) continue; for (let v = 0; v < S.n; v += 3) if (!isCloth(S.dom[v]) && !/^(weapon|foot|toe)/.test(rig.names[S.dom[v]])) floorV.push([slot, v]); }
      // weapon segments (weapon bone frame): from the furthest-back grip point to the tip socket
      const wspecs = DESIGNS[id].weapons || (DESIGNS[id].weapon ? [DESIGNS[id].weapon] : []);
      const wsegs = wspecs.map((w) => {
        const back = Math.min(0, ...Object.values(w.grips || {}).map((g) => g.pos[0]));
        return { bone: rig.index['weapon' + (w.hand || 'R')], a: [back, 0, 0], b: w.tip.slice(), r: w.name === 'spear' ? 0.025 : 0.035 };
      });
      const C = { id, ch, rig, cloths, springs, firstCloth, slots, clothVerts, hulls, sets, blade, floorV, wsegs, idle: IDLE[id] };
      C.BM = new Float32Array(N * 16); C.SM = new Float32Array(N * 16);
      C.prevE = cloths.map((c) => [new Float32Array(c.edges.length / 2 * 3), new Float32Array(c.edges.length / 2 * 3)]);
      C.nPrev = 0;
      return C;
    }

    function ell(h, x, y, z) {
      const ay = h.a[1], by = h.b[1];
      const ty = y < ay ? ay : y > by ? by : y;
      return h.r - Math.hypot(x - h.a[0], y - ty, z - h.a[2]);
    }
    function matrices(C) {
      const ch = C.ch, bones = ch.skeleton.bones, inv = ch.skeleton.boneInverses;
      ch.root.updateMatrixWorld(true);
      _inv.copy(ch.root.matrixWorld).invert();
      let nan = 0;
      for (let i = 0; i < bones.length; i++) {
        _m.multiplyMatrices(_inv, bones[i].matrixWorld);
        C.BM.set(_m.elements, i * 16);
        _m.multiply(inv[i]);
        C.SM.set(_m.elements, i * 16);
        for (let k = 0; k < 16; k++) if (!Number.isFinite(C.BM[i * 16 + k])) nan++;
      }
      return nan;
    }
    const sk = new Float32Array(3);
    function skinV(C, slot, v) {
      const g = C.slots[slot].g, P = g.attributes.position.array, I = g.attributes.skinIndex.array, W = g.attributes.skinWeight.array, SM = C.SM;
      const px = P[v * 3], py = P[v * 3 + 1], pz = P[v * 3 + 2];
      let x = 0, y = 0, z = 0;
      for (let k = 0; k < 4; k++) {
        const w = W[v * 4 + k];
        if (!w) continue;
        const o = I[v * 4 + k] * 16;
        x += w * (SM[o] * px + SM[o + 4] * py + SM[o + 8] * pz + SM[o + 12]);
        y += w * (SM[o + 1] * px + SM[o + 5] * py + SM[o + 9] * pz + SM[o + 13]);
        z += w * (SM[o + 2] * px + SM[o + 6] * py + SM[o + 10] * pz + SM[o + 14]);
      }
      sk[0] = x; sk[1] = y; sk[2] = z;
      return sk;
    }
    const bf = new Float32Array(3);
    function toBone(C, b, x, y, z) {
      const BM = C.BM, o = b * 16;
      x -= BM[o + 12]; y -= BM[o + 13]; z -= BM[o + 14];
      bf[0] = BM[o] * x + BM[o + 1] * y + BM[o + 2] * z;
      bf[1] = BM[o + 4] * x + BM[o + 5] * y + BM[o + 6] * z;
      bf[2] = BM[o + 8] * x + BM[o + 9] * y + BM[o + 10] * z;
      return bf;
    }
    const fb = new Float32Array(3);
    function fromBone(C, b, x, y, z) {
      const BM = C.BM, o = b * 16;
      fb[0] = BM[o] * x + BM[o + 4] * y + BM[o + 8] * z + BM[o + 12];
      fb[1] = BM[o + 1] * x + BM[o + 5] * y + BM[o + 9] * z + BM[o + 13];
      fb[2] = BM[o + 2] * x + BM[o + 6] * y + BM[o + 10] * z + BM[o + 14];
      return fb;
    }
    function segPt(ax, ay, az, bx, by, bz, x, y, z) {
      const ex = bx - ax, ey = by - ay, ez = bz - az, ee = ex * ex + ey * ey + ez * ez;
      let t = ee > 1e-12 ? ((x - ax) * ex + (y - ay) * ey + (z - az) * ez) / ee : 0;
      t = t < 0 ? 0 : t > 1 ? 1 : t;
      return Math.hypot(x - ax - ex * t, y - ay - ey * t, z - az - ez * t);
    }
    function segSeg(p1, q1, p2, q2) { // distance between two segments (sampled + refined: robust, cheap enough)
      let best = 1e9;
      for (let i = 0; i <= 16; i++) {
        const t = i / 16;
        const x = p1[0] + (q1[0] - p1[0]) * t, y = p1[1] + (q1[1] - p1[1]) * t, z = p1[2] + (q1[2] - p1[2]) * t;
        best = Math.min(best, segPt(p2[0], p2[1], p2[2], q2[0], q2[1], q2[2], x, y, z));
      }
      return best;
    }
    function hullModel(C, h) {
      const a = fromBone(C, h.bone, h.a[0], h.a[1], h.a[2]).slice();
      const b = fromBone(C, h.bone, h.b[0], h.b[1], h.b[2]).slice();
      return [a, b];
    }

    /** Metrics of the current frame. */
    function frame(C) {
      const ch = C.ch, out = { nan: matrices(C) };
      const e = ch.root.matrixWorld.elements, K = C.rig.k;
      const wy = (p) => e[1] * p[0] + e[5] * p[1] + e[9] * p[2] + e[13];
      // cloth vertices in body cores, by band
      const byHull = {};
      let n = 0, n1 = 0, depth = 0, depth1 = 0, floorMin = 1e9, headN = 0, headD = 0;
      for (const cv of C.clothVerts) {
        const p = skinV(C, cv.slot, cv.v);
        const y = wy(p);
        if (y < floorMin) floorMin = y;
        if (cv.band === 0) continue;
        for (const h of C.hulls) {
          const b = toBone(C, h.bone, p[0], p[1], p[2]);
          const d = ell(h, b[0], b[1], b[2]);
          if (d < 0.004 * K) continue;
          if (cv.band === 1) { n1++; depth1 = Math.max(depth1, d); } else { n++; depth = Math.max(depth, d); }
          const key = cv.cloth + (cv.band === 1 ? '#1' : '') + '>' + h.name;
          byHull[key] = (byHull[key] || 0) + 1;
          if (h.name === 'head' || h.name === 'neck') { headN++; headD = Math.max(headD, d); }
          break;
        }
      }
      out.clothIn = n; out.clothDepth = depth; out.clothIn1 = n1; out.clothDepth1 = depth1; out.clothBy = byHull; out.clothHead = headN; out.clothHeadDepth = headD; out.floorMin = floorMin;
      // particles vs design capsules: raw, and beyond each particle's own allowance (solver failure); stretch; pops
      let pn = 0, pd = 0, pm = 0, pmd = 0, str = 0, strAt = '', sh = 0, pop = 0, popAt = '';
      const caps = ch._r3aCaps || (ch._r3aCaps = capsulesOf(C));
      updateCaps(C, caps);
      C.cloths.forEach((cl, ci) => {
        const p = cl.p, pinN = cl.C * cl.layout.pinRows, nc = caps.count, mask = cl.mask;
        for (let k = pinN; k < cl.n; k++) {
          let raw = 0, beyond = 0;
          for (let i = 0; i < nc; i++) {
            const ad = axisDist(caps.data, i, p[k * 3], p[k * 3 + 1], p[k * 3 + 2]);
            const d = caps.data[i * 7 + 6] - ad;
            if (d > 0.002 * K) raw = Math.max(raw, d);
            const allow = mask ? mask[k * nc + i] : 0;
            if (allow < 0) continue;
            const lim = allow > 0 ? allow : caps.data[i * 7 + 6];
            const db = lim - ad;
            if (db > 0.002 * K) beyond = Math.max(beyond, db);
          }
          if (raw > 0) { pn++; pd = Math.max(pd, raw); }
          if (beyond > 0) { pm++; pmd = Math.max(pmd, beyond); }
        }
        const cons = cl.cons;
        for (let c = 0; c < cons.length; c += 4) {
          const a = cons[c], b = cons[c + 1], dd = Math.abs(b - a);
          const L = Math.hypot(p[b * 3] - p[a * 3], p[b * 3 + 1] - p[a * 3 + 1], p[b * 3 + 2] - p[a * 3 + 2]) / cons[c + 2];
          if (dd === 1 || dd === cl.C) { if (L > str) { str = L; strAt = cl.layout.spec.name + ' ' + (a % cl.C) + ',' + ((a / cl.C) | 0) + (dd === 1 ? ' h' : ' v') + ' rest ' + (cons[c + 2] * 1000).toFixed(1) + 'mm'; } }
          else if (dd === cl.C + 1 || dd === cl.C - 1) sh = Math.max(sh, L);
        }
        // pops: 2nd difference of structural edge vectors of the rendered particles (mm / frame^2)
        const E = cl.edges, rp = cl.rp, [e1, e2] = C.prevE[ci];
        for (let k = 0, q = 0; k < E.length; k += 2, q += 3) {
          const a = E[k] * 3, b = E[k + 1] * 3;
          if (E[k] < pinN && E[k + 1] < pinN) continue;
          const x = rp[b] - rp[a], y = rp[b + 1] - rp[a + 1], z = rp[b + 2] - rp[a + 2];
          if (C.nPrev >= 2) {
            const d2 = Math.hypot(x - 2 * e1[q] + e2[q], y - 2 * e1[q + 1] + e2[q + 1], z - 2 * e1[q + 2] + e2[q + 2]) * 1000;
            if (d2 > pop) { pop = d2; popAt = cl.layout.spec.name + ' ' + (E[k] % cl.C) + ',' + ((E[k] / cl.C) | 0); }
          }
          e2[q] = e1[q]; e2[q + 1] = e1[q + 1]; e2[q + 2] = e1[q + 2];
          e1[q] = x; e1[q + 1] = y; e1[q + 2] = z;
        }
      });
      C.nPrev++;
      out.partIn = pn; out.partDepth = pd; out.partBeyond = pm; out.partBeyondDepth = pmd; out.stretch = str; out.strAt = strAt; out.shear = sh; out.pop = pop; out.popAt = popAt;
      // vertex sets vs cores
      for (const S of C.sets) {
        let cnt = 0, dmax = 0;
        for (let k = 0; k < S.verts.length; k++) {
          const p = skinV(C, S.slot, S.verts[k]);
          const x = p[0], y = p[1], z = p[2];
          for (const h of S.targets) {
            const b = toBone(C, h.bone, x, y, z);
            const d = ell(h, b[0], b[1], b[2]);
            if (d > 0.004 * K) { cnt++; dmax = Math.max(dmax, d); break; }
          }
        }
        const o = out[S.label] || (out[S.label] = { n: 0, d: 0 });
        o.n += cnt; o.d = Math.max(o.d, dmax);
      }
      // blade vertices in body cores, blade lowest point
      {
        let cnt = 0, dmax = 0, low = 1e9; const by = {};
        for (const [slot, v] of C.blade) {
          const p = skinV(C, slot, v);
          low = Math.min(low, wy(p));
          for (const h of C.hulls) {
            const b = toBone(C, h.bone, p[0], p[1], p[2]);
            const d = ell(h, b[0], b[1], b[2]);
            if (d > 0.006 * K) { cnt++; dmax = Math.max(dmax, d); by[h.name] = (by[h.name] || 0) + 1; break; }
          }
        }
        out.blade = { n: cnt, d: dmax, by }; out.bladeLow = low;
      }
      // body vertices below the floor
      {
        let cnt = 0, low = 1e9, lowBone = '';
        for (const [slot, v] of C.floorV) {
          const y = wy(skinV(C, slot, v));
          if (y < low) { low = y; lowBone = C.rig.names[C.slots[slot].dom[v]]; }
          if (y < -0.005) cnt++;
        }
        out.bodyFloor = { n: cnt, low, bone: lowBone };
      }
      // weapon volume vs free cloth particles
      {
        let cnt = 0, dmax = 0;
        for (const ws of C.wsegs) {
          const a = fromBone(C, ws.bone, ...ws.a).slice(), b = fromBone(C, ws.bone, ...ws.b).slice();
          for (const cl of C.cloths) {
            const p = cl.p, pinN = cl.C * cl.layout.pinRows;
            for (let k = pinN; k < cl.n; k++) {
              const d = ws.r - segPt(a[0], a[1], a[2], b[0], b[1], b[2], p[k * 3], p[k * 3 + 1], p[k * 3 + 2]);
              if (d > 0) { cnt++; dmax = Math.max(dmax, d); }
            }
          }
        }
        out.wcloth = { n: cnt, d: dmax };
      }
      // legs: thigh / shin cores of the two sides overlapping
      {
        const H = {};
        for (const h of C.hulls) if (/^(thigh|shin)[RL]$/.test(h.name)) H[h.name] = { h, s: hullModel(C, h) };
        let ov = 0, at = '';
        for (const [a, b] of [['thighR', 'thighL'], ['shinR', 'shinL'], ['thighR', 'shinL'], ['shinR', 'thighL']]) {
          if (!H[a] || !H[b]) continue;
          const d = H[a].h.r + H[b].h.r - segSeg(H[a].s[0], H[a].s[1], H[b].s[0], H[b].s[1]);
          if (d > ov) { ov = d; at = a + '/' + b; }
        }
        out.legs = { d: ov, at };
      }
      // feet: heel / sole / ball (centre line + edges) / toe tip vs the world floor (lowest of both feet)
      const P = C.rig.P, fw = 0.045 * K;
      let low = 1e9, lowAt = '';
      for (const s of ['R', 'L']) {
        const f = ch.rig.index['foot' + s], t = ch.rig.index['toe' + s];
        for (const [b, off, nm] of [[f, [-P.heelLength, -P.ankleHeight, 0], 'heel'], [f, [0, -P.ankleHeight, 0], 'sole'], [f, [P.footLength, -P.ankleHeight, 0], 'ball'], [f, [P.footLength, -P.ankleHeight, fw], 'ballOut'], [f, [P.footLength, -P.ankleHeight, -fw], 'ballIn'], [f, [-P.heelLength, -P.ankleHeight, fw], 'heelOut'], [f, [-P.heelLength, -P.ankleHeight, -fw], 'heelIn'], [t, [P.toeLength, -(P.ankleHeight - P.footDrop), 0], 'toeTip'], [t, [0, -(P.ankleHeight - P.footDrop), 0], 'toePad']]) {
          _v.fromArray(off).applyMatrix4(ch.skeleton.bones[b].matrixWorld);
          if (_v.y < low) { low = _v.y; lowAt = s + nm; }
        }
      }
      out.soleMin = low; out.soleAt = lowAt;
      out.gripErr = ch.diag.gripErr; out.drop = ch.diag.drop;
      // spring tips (model)
      out.springTips = C.springs.map((s) => Array.from(s.p.subarray(s.p.length - 3)));
      return out;
    }
    function axisDist(data, i, x, y, z) {
      const o = i * 7, ax = data[o], ay = data[o + 1], az = data[o + 2];
      return segPt(ax, ay, az, data[o + 3], data[o + 4], data[o + 5], x, y, z);
    }
    function capsulesOf(C) {
      // the capsules the runtime uses (design colliders + the rig's default head / neck): rebuilt from the cloth mask size
      const defs = (C.ch.design.colliders || []);
      return { count: defs.length, defs, data: new Float32Array(defs.length * 7) };
    }
    function updateCaps(C, caps) {
      const ch = C.ch;
      for (let i = 0; i < caps.count; i++) {
        const d = caps.defs[i];
        for (let e = 0; e < 2; e++) {
          const [bn, off] = e === 0 ? d.a : d.b;
          _v.fromArray(off || [0, 0, 0]).applyMatrix4(ch.bones[bn].matrixWorld).applyMatrix4(_inv);
          caps.data[i * 7 + e * 3] = _v.x; caps.data[i * 7 + e * 3 + 1] = _v.y; caps.data[i * 7 + e * 3 + 2] = _v.z;
        }
        caps.data[i * 7 + 6] = d.r;
      }
    }

    // ---- clip runs ----
    function prime(C, pre = C.idle, frames = 45) {
      const ch = C.ch;
      ch.root.position.set(0, 0, 0); ch.root.rotation.set(0, 0, 0); ch.setFacing(1);
      ch.wind = [0, 0, 0]; ch.lookAt(null);
      ch.teleport();
      ch.play(pre, { fade: 0, restart: true });
      for (let i = 0; i < frames; i++) ch.update(1 / 60, 1 / 60);
      C.nPrev = 0;
    }
    function runClip(C, clip, o = {}) {
      const ch = C.ch, hz = o.hz || 60, dt = 1 / hz;
      prime(C, o.pre);
      ch.play(clip, { fade: o.fade ?? 0.08, restart: true });
      const dur = getClip(ch.rig, clip).duration;
      const n = Math.ceil((dur + (o.tail ?? 0.25)) * hz);
      const rec = [];
      for (let f = 0; f < n; f++) {
        const h = typeof o.dt === 'function' ? o.dt(f) : dt;
        ch.update(h, h);
        ch.root.position.x += ch.rootDelta.f * ch.facing;
        if (o.measure === false) continue;
        const m = frame(C);
        m.t = +((f + 1) * dt).toFixed(4);
        rec.push(m);
      }
      return rec;
    }
    function agg(rec, key, sub) {
      let v = -Infinity, at = null, frames = 0;
      for (const m of rec) {
        const x = sub ? m[key][sub] : m[key];
        if (x > v) { v = x; at = m.t; }
        if (x > 0) frames++;
      }
      return { v: r4(v), at, frames };
    }
    function minOf(rec, f) { let v = Infinity, at = null; for (const m of rec) { const x = f(m); if (x < v) { v = x; at = m.t; } } return { v: r4(v), at }; }
    function summarize(C, clip, rec) {
      const s = { clip, frames: rec.length };
      s.nan = agg(rec, 'nan').frames;
      for (const k of ['clothIn', 'clothDepth', 'clothIn1', 'clothDepth1', 'clothHead', 'clothHeadDepth', 'partIn', 'partDepth', 'partBeyond', 'partBeyondDepth', 'stretch', 'shear', 'pop']) s[k] = agg(rec, k);
      const w = rec.find((m) => m.t === s.clothIn.at), w1 = rec.find((m) => m.t === s.clothIn1.at);
      s.clothBy = w ? Object.entries(w.clothBy).filter(([k]) => !k.includes('#1')).sort((a, b) => b[1] - a[1]).slice(0, 3).map(([k, v]) => k + ':' + v).join(' ') : '';
      s.clothBy1 = w1 ? Object.entries(w1.clothBy).filter(([k]) => k.includes('#1')).sort((a, b) => b[1] - a[1]).slice(0, 3).map(([k, v]) => k + ':' + v).join(' ') : '';
      { const w2 = rec.find((m) => m.t === s.stretch.at); s.stretchEdge = w2 ? w2.strAt : ''; const w3 = rec.find((m) => m.t === s.pop.at); s.popEdge = w3 ? w3.popAt : ''; }
      s.clothFloorMin = minOf(rec, (m) => m.floorMin);
      for (const S of C.sets) if (!s[S.label]) { s[S.label] = agg(rec, S.label, 'n'); s[S.label + ' depth'] = agg(rec, S.label, 'd'); }
      s.blade = agg(rec, 'blade', 'n'); s.bladeDepth = agg(rec, 'blade', 'd');
      { const wb = rec.find((m) => m.t === s.blade.at); s.bladeBy = wb ? Object.entries(wb.blade.by).map(([k, v]) => k + ':' + v).join(' ') : ''; }
      s.bladeLow = minOf(rec, (m) => m.bladeLow);
      s.bodyFloor = agg(rec, 'bodyFloor', 'n'); s.bodyLow = minOf(rec, (m) => m.bodyFloor.low);
      { const wb = rec.find((m) => m.t === s.bodyLow.at); s.bodyLowBone = wb ? wb.bodyFloor.bone : ''; }
      s.wcloth = agg(rec, 'wcloth', 'n'); s.wclothDepth = agg(rec, 'wcloth', 'd');
      s.legs = agg(rec, 'legs', 'd'); { const wl = rec.find((m) => m.t === s.legs.at); s.legsAt = wl ? wl.legs.at : ''; s.legsFrames = rec.filter((m) => m.legs.d > 0.01 * C.rig.k).length; }
      s.soleMin = minOf(rec, (m) => m.soleMin); { const ws = rec.find((m) => m.t === s.soleMin.at); s.soleAt = ws ? ws.soleAt : ''; }
      s.soleBelowFrames = rec.filter((m) => m.soleMin < -0.003).length;
      s.gripErr = agg(rec, 'gripErr'); s.drop = agg(rec, 'drop');
      return s;
    }
    function compact(s) {
      const f = (a) => (a.v > 0 ? `${a.v}@${a.at}(${a.frames}f)` : '0');
      const mm = (a) => (a.v * 1000).toFixed(0);
      const set = (k) => (s[k] && s[k].v > 0 ? `${k} ${f(s[k])} d${mm(s[k + ' depth'])}` : null);
      return [
        `${s.clip}: cloth ${f(s.clothIn)} d${mm(s.clothDepth)} [${s.clothBy}] band1 ${f(s.clothIn1)} d${mm(s.clothDepth1)} [${s.clothBy1}] head ${f(s.clothHead)} d${mm(s.clothHeadDepth)}`,
        `part ${f(s.partIn)} beyond ${f(s.partBeyond)} d${mm(s.partBeyondDepth)} | str ${s.stretch.v}@${s.stretch.at} (${s.stretchEdge}) shear ${s.shear.v} | pop ${s.pop.v.toFixed(1)}mm@${s.pop.at} (${s.popEdge}) | clothFloor ${s.clothFloorMin.v}`,
        ['tasset->thigh', 'arm->chest', 'arm->torso', 'arm->legs', 'tasset->torso', 'legR->legL', 'legL->legR'].map(set).filter(Boolean).join(' | '),
        `blade ${f(s.blade)} d${mm(s.bladeDepth)} [${s.bladeBy}] low ${s.bladeLow.v} | wcloth ${f(s.wcloth)} d${mm(s.wclothDepth)} | bodyFloor ${f(s.bodyFloor)} low ${s.bodyLow.v}@${s.bodyLow.at} ${s.bodyLowBone} | legs ${mm(s.legs)}mm@${s.legs.at} ${s.legsAt} (${s.legsFrames}f>1cm)`,
        `sole ${s.soleMin.v}@${s.soleMin.at} ${s.soleAt} (${s.soleBelowFrames}f<-3mm) | grip ${s.gripErr.v}@${s.gripErr.at} | drop ${s.drop.v}`,
      ].filter(Boolean).join('\n   ');
    }
    function clipsOf(id) {
      const pre = id === 'knight' ? 'demo.' : id + '.';
      return listClips().filter((n) => n.startsWith(pre));
    }
    function scan(id, clips, o = {}) {
      use(id);
      const list = clips || clipsOf(id);
      const out = [];
      for (const clip of list) {
        try {
          const rec = runClip(cur, clip, o);
          const s = summarize(cur, clip, rec);
          if (o.series) s.series = rec.map((m) => o.series.map((k) => { const v = k.includes('.') ? m[k.split('.')[0]][k.split('.')[1]] : m[k]; return typeof v === 'number' ? r4(v) : v; }));
          out.push(o.full ? s : compact(s));
        } catch (e) { out.push(clip + ': THREW ' + String(e && e.stack || e).slice(0, 300)); }
      }
      return out;
    }
    /** Totals over a scan (o.full = true results) for the summary table. */
    function totals(id, clips, o = {}) {
      const res = scan(id, clips, { ...o, full: true }).filter((s) => typeof s === 'object');
      const T = { clips: res.length };
      const top = (key, sub = 'v', n = 3) => res.filter((s) => s[key] && s[key][sub] > 0).sort((a, b) => b[key][sub] - a[key][sub]).slice(0, n).map((s) => `${s.clip}:${s[key][sub]}@${s[key].at}`);
      for (const k of ['clothIn', 'clothIn1', 'clothHead', 'partBeyond', 'stretch', 'shear', 'pop', 'blade', 'wcloth', 'bodyFloor', 'legs', 'drop', 'gripErr']) {
        T[k] = { clips: res.filter((s) => s[k] && s[k].v > (k === 'stretch' || k === 'shear' ? 1.3 : k === 'pop' ? 15 : k === 'legs' ? 0.01 : 0)).length, frames: res.reduce((a, s) => a + ((s[k] && s[k].frames) || 0), 0), top: top(k) };
      }
      for (const k of ['tasset->thigh', 'arm->chest', 'arm->torso', 'arm->legs', 'tasset->torso', 'legR->legL', 'legL->legR']) T[k] = { clips: res.filter((s) => s[k] && s[k].v > 0).length, frames: res.reduce((a, s) => a + ((s[k] && s[k].frames) || 0), 0), top: top(k), depth: top(k + ' depth') };
      T.clothFloorMin = res.map((s) => [s.clip, s.clothFloorMin.v]).sort((a, b) => a[1] - b[1]).slice(0, 4);
      T.bodyLow = res.map((s) => [s.clip, s.bodyLow.v, s.bodyLowBone]).sort((a, b) => a[1] - b[1]).slice(0, 4);
      T.soleMin = res.map((s) => [s.clip, s.soleMin.v, s.soleAt, s.soleBelowFrames]).sort((a, b) => a[1] - b[1]).slice(0, 5);
      T.soleBelowFrames = res.reduce((a, s) => a + s.soleBelowFrames, 0);
      T.bladeLow = res.map((s) => [s.clip, s.bladeLow.v]).sort((a, b) => a[1] - b[1]).slice(0, 3);
      T.cloth1Depth = top('clothDepth1'); T.clothDepth = top('clothDepth'); T.bladeDepth = top('bladeDepth'); T.wclothDepth = top('wclothDepth');
      T.bladeBy = res.filter((s) => s.blade.v > 0).sort((a, b) => b.blade.v - a.blade.v).slice(0, 5).map((s) => `${s.clip}@${s.blade.at} ${s.bladeBy} d${(s.bladeDepth.v * 1000).toFixed(0)}mm`);
      T.popEdge = res.filter((s) => s.pop.v > 15).sort((a, b) => b.pop.v - a.pop.v).slice(0, 5).map((s) => `${s.clip}@${s.pop.at} ${s.pop.v.toFixed(1)}mm ${s.popEdge}`);
      return T;
    }

    function hold(id, clip, t, o = {}) {
      use(id);
      const C = cur, ch = C.ch;
      prime(C, o.pre);
      ch.play(clip, { fade: o.fade ?? 0, restart: true });
      const n = Math.round(t * 60);
      let m = null;
      for (let f = 0; f < n; f++) { ch.update(1 / 60, 1 / 60); if (o.root !== false) ch.root.position.x += ch.rootDelta.f * ch.facing; if (o.measureAll || f === n - 1) m = frame(C); }
      return m || frame(C);
    }

    // ---- camera ----
    function look(focus = 'chest', yaw = 30, dist = 1.4, pitch = 6) {
      const C = cur, b = C.ch.bones[focus];
      const w = typeof focus === 'string' && focus[0] === 'w' ? focus.slice(1).split('_').map(Number) : null;
      const p = w ? new THREE.Vector3(...w).applyMatrix4(C.ch.root.matrixWorld) : b ? b.getWorldPosition(new THREE.Vector3()) : C.ch.root.getWorldPosition(new THREE.Vector3());
      lab.view({ target: [p.x, p.y, p.z], dist, yaw, pitch });
    }

    // ---- frame-rate dependence of cloth + spring tips on a real clip (equal game times vs the 60 Hz run) ----
    function dt(id, clip, every = 1 / 30) {
      use(id);
      const C = cur;
      const snapAt = (o, perturb = 0) => {
        const snaps = [];
        const ch = C.ch;
        prime(C);
        ch.wind = [perturb, 0, 0];
        ch.play(clip, { fade: 0.08, restart: true });
        const dur = getClip(ch.rig, clip).duration + 0.4;
        let t = 0, next = every, f = 0, guard = 0;
        while (t < dur - 1e-9 && guard++ < 40000) {
          const h = o(f++, t);
          ch.update(h, h); t += h;
          ch.root.position.x += ch.rootDelta.f * ch.facing;
          if (t >= next - 1e-7) { snaps.push({ t: +t.toFixed(4), p: C.cloths.map((c) => Float32Array.from(c.rp)), s: C.springs.map((s) => Float32Array.from(s.p)) }); next += every; }
        }
        return snaps;
      };
      const ref = snapAt(() => 1 / 60);
      let hs = 0;
      const runs = {
        hz60_breeze001: snapAt(() => 1 / 60, 0.01), hz30: snapAt(() => 1 / 30), hz120: snapAt(() => 1 / 120), alt60_30: snapAt((f) => (f % 2 ? 1 / 30 : 1 / 60)), slow01: snapAt(() => 1 / 600),
        hitstop: (hs = 0, snapAt((f, t) => (t >= 0.3 - 1e-9 && hs < 20 ? (hs++, 0) : 1 / 60))),
      };
      C.ch.wind = [0, 0, 0];
      const res = {};
      for (const [k, tr] of Object.entries(runs)) {
        let mx = 0, at = null, sum = 0, cnt = 0, smx = 0, sat = null;
        const n = Math.min(ref.length, tr.length);
        for (let i = 0; i < n; i++) {
          if (Math.abs(ref[i].t - tr[i].t) > 1e-3) continue;
          for (let c = 0; c < ref[i].p.length; c++) {
            const a = ref[i].p[c], b = tr[i].p[c];
            for (let k2 = 0; k2 < a.length; k2 += 3) { const d = Math.hypot(a[k2] - b[k2], a[k2 + 1] - b[k2 + 1], a[k2 + 2] - b[k2 + 2]); sum += d * d; cnt++; if (d > mx) { mx = d; at = ref[i].t; } }
          }
          for (let c = 0; c < ref[i].s.length; c++) {
            const a = ref[i].s[c], b = tr[i].s[c];
            for (let k2 = 0; k2 < a.length; k2 += 3) { const d = Math.hypot(a[k2] - b[k2], a[k2 + 1] - b[k2 + 1], a[k2 + 2] - b[k2 + 2]); if (d > smx) { smx = d; sat = ref[i].t; } }
          }
        }
        res[k] = { cloth: { max: r4(mx), rms: r4(Math.sqrt(sum / Math.max(1, cnt))), at }, springs: { max: r4(smx), at: sat }, samples: n };
      }
      return res;
    }

    // ---- still pose: jitter and creep of cloth and spring tips after settling ----
    function rest(id, seconds = 6) {
      use(id);
      const C = cur, ch = C.ch;
      const breath = ch.breath.depth;
      ch.breath.depth = 0;
      prime(C, C.idle, 1);
      ch.setClipTime(0);
      const n = Math.round(seconds * 60), last = 60;
      const hist = [];
      for (let f = 0; f < n; f++) {
        ch.setClipTime(0);
        ch.update(1 / 60, 1 / 60);
        if (f >= n - last - 2) hist.push({ p: C.cloths.map((c) => Float32Array.from(c.rp)), s: C.springs.map((s) => Float32Array.from(s.p)) });
      }
      ch.breath.depth = breath;
      let vmax = 0, vsum = 0, vcnt = 0, smax = 0, creep = 0, acc = 0;
      for (let i = 1; i < hist.length; i++) {
        hist[i].p.forEach((a, c) => { const b = hist[i - 1].p[c]; for (let k = 0; k < a.length; k += 3) { const d = Math.hypot(a[k] - b[k], a[k + 1] - b[k + 1], a[k + 2] - b[k + 2]); vmax = Math.max(vmax, d); vsum += d; vcnt++; } });
        hist[i].s.forEach((a, c) => { const b = hist[i - 1].s[c]; for (let k = 0; k < a.length; k += 3) smax = Math.max(smax, Math.hypot(a[k] - b[k], a[k + 1] - b[k + 1], a[k + 2] - b[k + 2])); });
        if (i >= 2) hist[i].p.forEach((a, c) => { const b = hist[i - 1].p[c], d0 = hist[i - 2].p[c]; for (let k = 0; k < a.length; k += 3) acc = Math.max(acc, Math.hypot(a[k] - 2 * b[k] + d0[k], a[k + 1] - 2 * b[k + 1] + d0[k + 1], a[k + 2] - 2 * b[k + 2] + d0[k + 2])); });
      }
      hist[hist.length - 1].p.forEach((a, c) => { const b = hist[0].p[c]; for (let k = 0; k < a.length; k += 3) creep = Math.max(creep, Math.hypot(a[k] - b[k], a[k + 1] - b[k + 1], a[k + 2] - b[k + 2])); });
      const m = frame(C);
      return { id, clothStepMaxMm: +(vmax * 1000).toFixed(3), clothStepMeanMm: +(vsum / Math.max(1, vcnt) * 1000).toFixed(4), clothAccMaxMm: +(acc * 1000).toFixed(3), creepOverLastSecMm: +(creep * 1000).toFixed(3), springStepMaxMm: +(smax * 1000).toFixed(3), stretch: r4(m.stretch), strAt: m.strAt, shear: r4(m.shear), clothIn: m.clothIn, clothIn1: m.clothIn1, partBeyond: m.partBeyond };
    }

    // ---- recovery: after a clip, the idle cloth returns to the idle drape? (distance to a settled idle cloth) ----
    function recover(id, clip, waits = [0.5, 1, 2, 3]) {
      use(id);
      const C = cur, ch = C.ch;
      const snap = () => C.cloths.map((c) => Float32Array.from(c.rp));
      const dist = (A, B) => { let mx = 0, s = 0, n = 0; A.forEach((a, c) => { const b = B[c]; for (let k = 0; k < a.length; k += 3) { const d = Math.hypot(a[k] - b[k], a[k + 1] - b[k + 1], a[k + 2] - b[k + 2]); mx = Math.max(mx, d); s += d * d; n++; } }); return { max: r4(mx), rms: r4(Math.sqrt(s / n)) }; };
      // reference: the idle at the same idle clip time (breathing off so the phase does not matter)
      const breath = ch.breath.depth; ch.breath.depth = 0;
      const dur = getClip(ch.rig, clip).duration;
      const out = { clip };
      for (const w of waits) {
        prime(C);
        ch.play(clip, { fade: 0.08, restart: true });
        for (let f = 0; f < Math.round(dur * 60); f++) { ch.update(1 / 60, 1 / 60); }
        ch.root.position.set(0, 0, 0);
        ch.play(C.idle, { fade: 0.2, restart: true });
        for (let f = 0; f < Math.round(w * 60); f++) { ch.setClipTime(0); ch.update(1 / 60, 1 / 60); }
        const A = snap();
        prime(C, C.idle, 1);
        for (let f = 0; f < 240; f++) { ch.setClipTime(0); ch.update(1 / 60, 1 / 60); }
        out['after' + w + 's'] = dist(A, snap());
      }
      ch.breath.depth = breath;
      return out;
    }

    // ---- elbow / knee volume (R2A-08 measurement): the shipped helper offset vs forced to rest ----
    function volume(id, poses) {
      use(id);
      const C = cur, ch = C.ch, rig = C.rig, out = [];
      const S = C.slots.suit, g = S.g, P = g.attributes.position.array, idx = g.index.array;
      const bonePos = (M, i) => new THREE.Vector3(M[i * 16 + 12], M[i * 16 + 13], M[i * 16 + 14]);
      const segD = (p, a, b) => { const e = b.clone().sub(a), t = Math.max(0, Math.min(1, p.clone().sub(a).dot(e) / e.lengthSq())); return [p.distanceTo(a.clone().addScaledVector(e, t)), a.clone().addScaledVector(e, t)]; };
      const near2 = (p, A, B, Cc) => { const d1 = segD(p, A, B), d2 = segD(p, B, Cc); return d1[0] < d2[0] ? d1 : d2; };
      const bindM = ch.skeleton.boneInverses.map((m) => m.clone().invert().elements);
      const bindPos = (i) => new THREE.Vector3(bindM[i][12], bindM[i][13], bindM[i][14]);
      for (const [name, bones, joint] of poses) {
        definePose('r3a.vol', { bones });
        invalidateClips();
        ch.teleport();
        ch.play('r3a.vol', { fade: 0, restart: true });
        for (let i = 0; i < 3; i++) ch.update(1 / 60, 1 / 60);
        const j = rig.index[joint], par = rig.parent[j], c1 = rig.index[{ foreArmR: 'handR', shinR: 'footR' }[joint]];
        const B0 = [bindPos(par), bindPos(j), bindPos(c1)];
        const reg = new Uint8Array(S.n), d0 = new Float32Array(S.n);
        let wVol = 0;
        const helper = rig.index[{ foreArmR: 'elbowVolR', shinR: 'kneeVolR' }[joint]];
        const SW = g.attributes.skinWeight.array, SI = g.attributes.skinIndex.array;
        for (let v = 0; v < S.n; v++) {
          if (S.dom[v] >= C.firstCloth) continue;
          const p = new THREE.Vector3().fromArray(P, v * 3);
          if (p.distanceTo(B0[1]) > 0.07 * rig.k) continue;
          reg[v] = 1; d0[v] = near2(p, ...B0)[0];
          for (let k = 0; k < 4; k++) if (SI[v * 4 + k] === helper && SW[v * 4 + k] > 0.05) { wVol++; break; }
        }
        const measureNow = () => {
          matrices(C);
          const B1 = [bonePos(C.BM, par), bonePos(C.BM, j), bonePos(C.BM, c1)];
          const pos = new Float32Array(S.n * 3);
          let minR = 1e9, minRatio = 1e9, maxR = 0, maxRatio = 0, n = 0;
          for (let v = 0; v < S.n; v++) {
            if (!reg[v]) continue;
            const q = skinV(C, 'suit', v); pos[v * 3] = q[0]; pos[v * 3 + 1] = q[1]; pos[v * 3 + 2] = q[2];
            const d1 = near2(new THREE.Vector3(q[0], q[1], q[2]), ...B1)[0];
            minR = Math.min(minR, d1); maxR = Math.max(maxR, d1);
            if (d0[v] > 0.02 * rig.k) { minRatio = Math.min(minRatio, d1 / d0[v]); maxRatio = Math.max(maxRatio, d1 / d0[v]); }
            n++;
          }
          let folds = 0, tris = 0;
          const fn = (pp, a, b2, c2, B) => {
            const A = new THREE.Vector3(pp[a * 3], pp[a * 3 + 1], pp[a * 3 + 2]), Bv = new THREE.Vector3(pp[b2 * 3], pp[b2 * 3 + 1], pp[b2 * 3 + 2]), Cv = new THREE.Vector3(pp[c2 * 3], pp[c2 * 3 + 1], pp[c2 * 3 + 2]);
            const nrm = Bv.clone().sub(A).cross(Cv.clone().sub(A));
            const ctr = A.add(Bv).add(Cv).multiplyScalar(1 / 3);
            return nrm.dot(ctr.clone().sub(near2(ctr, ...B)[1]));
          };
          for (let t = 0; t < idx.length; t += 3) {
            const a2 = idx[t], b2 = idx[t + 1], c2 = idx[t + 2];
            if (!reg[a2] || !reg[b2] || !reg[c2]) continue;
            if (fn(P, a2, b2, c2, B0) <= 0) continue;
            tris++;
            if (fn(pos, a2, b2, c2, B1) < 0) folds++;
          }
          return { n, minR: +(minR * 1000).toFixed(1), minRatio: +minRatio.toFixed(3), maxR: +(maxR * 1000).toFixed(1), maxRatio: +maxRatio.toFixed(3), folds, tris };
        };
        const shipped = measureNow();
        const hb = ch.skeleton.bones[helper];
        const hp = hb.position.clone();
        hb.position.fromArray(rig.offset, helper * 3); ch.root.updateMatrixWorld(true);
        const noOffset = measureNow();
        hb.position.copy(hp); ch.root.updateMatrixWorld(true);
        out.push({ pose: name, regionVerts: shipped.n, volWeighted: wVol, shipped, noCreaseOffset: noOffset });
      }
      return out;
    }

    // ---- capture queue ----
    let queue = [];
    const label = document.createElement('div');
    label.style.cssText = 'position:fixed;left:8px;top:8px;z-index:21;font:bold 15px/1.35 monospace;color:#fff;background:rgba(0,0,0,.6);padding:4px 8px;border-radius:4px;white-space:pre;pointer-events:none';
    document.body.appendChild(label);
    function step() {
      const it = queue.shift();
      if (!it) return null;
      const [id, clip, t, focus, yaw, dist, pitch = 6, , showSlots = null, fade = 0, pre] = it;
      const m = hold(id, clip, t, { fade, pre });
      for (const C of Object.values(built)) for (const [k, mm] of Object.entries(C.ch.meshes)) mm.visible = C === cur && (!showSlots || showSlots.includes(k));
      look(focus, yaw, dist, pitch);
      const txt = `${id} ${clip}@${t} yaw ${yaw}  cloth ${m.clothIn}+${m.clothIn1}(row1) blade ${m.blade.n} bodyFloor ${(m.bodyFloor.low * 1000).toFixed(0)}mm str ${m.stretch.toFixed(2)}`;
      label.textContent = txt;
      return txt;
    }

    // ---- CPU: char.update of a real design over a clip chain, replayed ----
    function cpu(id, chain, replays = 6) {
      use(id);
      const C = cur, ch = C.ch, per = [], first = [], worst = [];
      for (let r = 0; r < replays; r++) {
        prime(C);
        ch.teleport();
        let f = 0;
        for (const clip of chain) {
          ch.play(clip, { fade: 0.08, restart: true });
          const n = Math.round(getClip(ch.rig, clip).duration * 60);
          for (let k = 0; k < n; k++, f++) {
            const t0 = performance.now();
            ch.update(1 / 60, 1 / 60);
            const d = performance.now() - t0;
            if (f === 0) { first.push(d); continue; }
            per[f] = r === 0 ? d : Math.min(per[f], d);
            worst[f] = r === 0 ? d : Math.max(worst[f], d);
          }
        }
      }
      const vals = per.filter((x) => x !== undefined), s = vals.slice().sort((a, b) => a - b);
      return { id, tier: ctx.quality.tier, clothQ: ctx.quality.cloth, frames: vals.length, clothParticles: C.cloths.reduce((a, c) => a + c.n, 0), iters: C.cloths.map((c) => c.iters), springs: C.springs.length,
        meanOfMin: +(vals.reduce((a, b) => a + b, 0) / vals.length).toFixed(3), p50: +s[s.length >> 1].toFixed(3), p95: +s[Math.floor(s.length * 0.95)].toFixed(3), maxOfMin: +s[s.length - 1].toFixed(3),
        resetFrameMin: +Math.min(...first).toFixed(2), resetFrameMed: +first.slice().sort((a, b) => a - b)[first.length >> 1].toFixed(2) };
    }
    /** Cost of the cloth part alone: cloth update + write per frame over a clip (min over replays). */
    function clothCost(id, clip, replays = 5) {
      use(id);
      const C = cur, ch = C.ch, per = [];
      const o1 = Cloth.prototype.update;
      let acc = 0;
      Cloth.prototype.update = function (...a) { const t0 = performance.now(); const r = o1.apply(this, a); acc += performance.now() - t0; return r; };
      try {
        for (let r = 0; r < replays; r++) {
          prime(C);
          ch.play(clip, { fade: 0.08, restart: true });
          const n = Math.round(getClip(ch.rig, clip).duration * 60);
          for (let k = 0; k < n; k++) { acc = 0; ch.update(1 / 60, 1 / 60); per[k] = r === 0 ? acc : Math.min(per[k], acc); }
        }
      } finally { Cloth.prototype.update = o1; }
      return { id, clip, clothMsMeanOfMin: +(per.reduce((a, b) => a + b, 0) / per.length).toFixed(3) };
    }

    /**
     * Hand on the handle: per side, the weapon's handle radius around the fist (median radial distance of the weapon
     * vertices within +-6 cm of the fist centre, weapon frame) vs the finger / tip / thumb / palm vertices' distance to
     * the handle axis: vertices inside the handle (fingers through the grip) and each finger segment's closest vertex
     * minus the handle radius (> ~1 cm: a fist floating around the handle).
     */
    function fist(id, clip, t, o = {}) {
      hold(id, clip, t, o);
      const C = cur, ch = C.ch, rig = C.rig, out = { clip, t };
      matrices(C);
      const weapons = C.wsegs;
      for (const side of ['R', 'L']) {
        // which weapon axis this hand holds: its own weapon, or the main weapon's grip when this is the gripping off hand
        let ws = weapons.find((w) => rig.names[w.bone] === 'weapon' + side);
        const gripping = !ws && ch.diag && weapons.length === 1;
        if (!ws && gripping) ws = weapons[0];
        if (!ws) continue;
        const own = rig.names[ws.bone] === 'weapon' + side;
        // the fist centre in the weapon frame (own: origin; off hand: its weapon bone's origin projected)
        const wb = rig.index['weapon' + side];
        const oc = toBone(C, ws.bone, C.BM[wb * 16 + 12], C.BM[wb * 16 + 13], C.BM[wb * 16 + 14]).slice();
        const rads = [];
        for (const [slot, v] of C.blade) {
          if (C.slots[slot].dom[v] !== ws.bone) continue;
          const p = skinV(C, slot, v), q = toBone(C, ws.bone, p[0], p[1], p[2]);
          if (Math.abs(q[0] - oc[0]) < 0.06) rads.push(Math.hypot(q[1], q[2]));
        }
        const hr = rads.length ? pct(rads, 0.5) : NaN;
        const seg = {};
        let inside = 0, deepest = 0;
        for (const slot of ['plate', 'suit']) {
          const S = C.slots[slot]; if (!S) continue;
          for (let v = 0; v < S.n; v++) {
            const nm = rig.names[S.dom[v]];
            if (!new RegExp('^(fingers|fingerTips|thumb|hand)' + side + '$').test(nm)) continue;
            const p = skinV(C, slot, v), q = toBone(C, ws.bone, p[0], p[1], p[2]);
            if (Math.abs(q[0] - oc[0]) > 0.07) continue;
            const d = Math.hypot(q[1], q[2]);
            const k = nm.replace(side, '');
            seg[k] = Math.min(seg[k] ?? 1e9, d);
            if (d < hr - 0.002) { inside++; deepest = Math.max(deepest, hr - d); }
          }
        }
        out[side] = { own, handleR: +(hr * 1000).toFixed(1), insideVerts: inside, deepestMm: +(deepest * 1000).toFixed(1), closestMinusR: Object.fromEntries(Object.entries(seg).map(([k, d]) => [k, +((d - hr) * 1000).toFixed(1)])), fistOffAxisMm: +(Math.hypot(oc[1], oc[2]) * 1000).toFixed(1) };
      }
      return out;
    }

    /** R2A-02: a crossfade from `from` into `to`, held at t, for several breathing phases (prime lengths). */
    function fadeCase(id, from, to, t, fade = 0.08, primes = [45, 60, 75, 90, 105, 120, 135, 150]) {
      use(id);
      const C = cur, ch = C.ch, out = [];
      for (const pf of primes) {
        prime(C, from, pf);
        ch.play(to, { fade, restart: true });
        let worst = { n: 0, d: 0 }, worstT = 0, worstTorso = { n: 0, d: 0 };
        for (let f = 0; f < Math.round(t * 60); f++) {
          ch.update(1 / 60, 1 / 60);
          const m = frame(C);
          if (m['arm->chest'].n > worst.n) { worst = m['arm->chest']; worstT = (f + 1) / 60; }
          if (m['arm->torso'].n > worstTorso.n) worstTorso = m['arm->torso'];
        }
        out.push(`prime ${pf}f: arm->chest max ${worst.n} verts d${(worst.d * 1000).toFixed(0)}mm @${worstT.toFixed(3)}; arm->torso max ${worstTorso.n} d${(worstTorso.d * 1000).toFixed(0)}mm`);
      }
      return out;
    }

    /** SIM-09: a timed facing turn (setFacing(-f, { turn })) during idle: cloth metrics over the next `dur` s vs an instant flip. */
    function turnTest(id, turn = 0.15, dur = 0.8, clip = null) {
      use(id);
      const C = cur, ch = C.ch, res = {};
      for (const tt of [0, turn]) {
        prime(C, clip || C.idle);
        ch.setFacing(-1, { turn: tt });
        let str = 0, cin = 0, cin1 = 0, beyond = 0, pop = 0, vmax = 0;
        const prev = C.cloths.map((c) => Float32Array.from(c.p));
        for (let f = 0; f < Math.round(dur * 60); f++) {
          ch.update(1 / 60, 1 / 60);
          const m = frame(C);
          str = Math.max(str, m.stretch); cin = Math.max(cin, m.clothIn); cin1 = Math.max(cin1, m.clothIn1); beyond = Math.max(beyond, m.partBeyond); pop = Math.max(pop, m.pop);
          C.cloths.forEach((c, i) => { for (let k = 0; k < c.p.length; k += 3) vmax = Math.max(vmax, Math.hypot(c.p[k] - prev[i][k], c.p[k + 1] - prev[i][k + 1], c.p[k + 2] - prev[i][k + 2]) * 60); prev[i].set(c.p); });
        }
        res[tt ? 'turn' + tt : 'instant'] = { stretch: r4(str), clothIn: cin, clothIn1: cin1, partBeyond: beyond, popMm: +pop.toFixed(1), vmaxModel: +vmax.toFixed(2) };
      }
      ch.setFacing(1);
      return res;
    }

    window.__ED.r3a = {
      fist, fadeCase, turnTest,
      DESIGNS, use, get cur() { return cur; }, built, clips: clipsOf, scan, totals, hold, frame: () => frame(cur), look, dt, rest, recover, volume, cpu, clothCost,
      queue(items) { queue = items.slice(); return queue.length; }, step,
      hullInfo: (id) => { use(id); return cur.hulls.map((h) => ({ bone: h.name, a: h.a.map((x) => +x.toFixed(3)), b: h.b.map((x) => +x.toFixed(3)), r: +h.r.toFixed(3), n: h.n })); },
      setInfo: (id) => { use(id); return { sets: cur.sets.map((s) => `${s.label}/${s.slot}: ${s.verts.length}`), blade: cur.blade.length, floorV: cur.floorV.length, cloth: cur.clothVerts.length, band1: cur.clothVerts.filter((c) => c.band === 1).length, wsegs: cur.wsegs, cloths: cur.cloths.map((c) => `${c.layout.spec.name} ${c.C}x${c.R} iters ${c.iters}`), mask: cur.cloths.map((c) => { let ign = 0, red = 0; if (c.mask) for (const x of c.mask) { if (x < 0) ign++; else if (x > 0) red++; } return `${c.layout.spec.name}: ignore ${ign} reduced ${red}`; }), colliders: (cur.ch.design.colliders || []).map((c) => c.name) }; },
      show(slots) { for (const C of Object.values(built)) for (const [k, m] of Object.entries(C.ch.meshes)) m.visible = !slots || slots.includes(k); return slots; },
      label(t) { label.textContent = t; return t; },
      run: runClip, prime,
    };
    ctx.onUpdate((dg, dr) => { if (cur && cur.live) cur.ch.update(dg, dr); }, ORDER.CHAR);
    use('kael');
  },
  scenarios: {},
});
