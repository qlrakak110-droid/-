// Rig audit lab, round 2, lens "deformation, range of motion, cloth and contact" (auditor's sandbox, READ-ONLY on
// src/char and on the fighter art / clip files: they are imported, never modified).
//
// The round-1 labs (rigaudit_skin / rigaudit_sim) measure the demo knight against its own design data. This lab measures
// the shipped runtime on the REAL fighter designs (src/fighters/<id>/design.js) playing their REAL clips, against the
// rendered geometry instead of the collision capsules the solver itself uses:
//
//   cores      per body bone, a capsule along the bone's Y axis fitted to the plate / suit geometry that bone dominates
//              (bind frame; y from the 10th to the 90th percentile, radius HULL_SHRINK x the 35th percentile of the
//              distance from the axis): a cloth / plate vertex inside one is visibly inside the body
//   cloth      rendered cloth vertices (CPU-skinned exactly like the GPU, all slots, first two particle rows excluded)
//              inside a body hull; cloth particles inside the design's own capsules (solver failure); max structural
//              stretch; lowest rendered cloth vertex (floor)
//   tassets    plate vertices of tasset bones inside a thigh hull (vertices already inside in the bind pose excluded)
//   arms       plate vertices of upper-arm / elbow / forearm bones inside the chest hull (bind-inside excluded)
//   contact    char.diag.gripErr (two-handed grip), char.diag.drop (automatic pelvis drop), sole / toe tips below y = 0
//
//   __ED.r2a.use(id)                         kael | iska | vorn | knight (built once, others hidden)
//   __ED.r2a.clips(id)                       clip names registered by that fighter
//   __ED.r2a.scan(id, clips?, opts)          per-clip summary (opts: { hz = 60, pre = idle clip, tail = 0.25 s, series })
//   __ED.r2a.hold(id, clip, t)               run a clip from 0 to t at 60 Hz (cloth evolves) and hold it (captures)
//   __ED.r2a.look(focus, yaw, dist, pitch)   camera on a bone ('w<x>_<y>_<z>' = fixed model point)
//   __ED.r2a.holes(slots?)                   GPU see-through pixels (front faces vs double-sided silhouette) + overlay
//   __ED.r2a.show(slots)                     show only some material slots
//   __ED.r2a.hullInfo(id)                    the fitted body cores (bone, axis ends, radius)

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

// ---- observation hook: capture the Cloth / SpringChain instances of a character (restored after use) ------------------
const ORIG = { cloth: Cloth.prototype.update, spring: SpringChain.prototype.update };
const HOOK = { cloths: [], springs: [] };
function hookCapture(on) {
  Cloth.prototype.update = on ? function (...a) { if (!a[8] && !HOOK.cloths.includes(this)) HOOK.cloths.push(this); return ORIG.cloth.apply(this, a); } : ORIG.cloth;
  SpringChain.prototype.update = on ? function (...a) { if (!HOOK.springs.includes(this)) HOOK.springs.push(this); return ORIG.spring.apply(this, a); } : ORIG.spring;
}

const _m = new THREE.Matrix4(), _inv = new THREE.Matrix4(), _v = new THREE.Vector3();

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
      const ch = createCharacter(ctx, DESIGNS[id], { name: 'r2a_' + id });
      ch.play(IDLE[id], { fade: 0 });
      HOOK.cloths.length = 0; HOOK.springs.length = 0;
      hookCapture(true);
      try { ch.update(1 / 60, 1 / 60); } finally { hookCapture(false); }
      const rig = ch.rig, N = rig.count;
      const cloths = HOOK.cloths.filter((c) => c.rig === rig), springs = HOOK.springs.filter((s) => s.rig === rig);
      const firstCloth = Math.min(N, ...cloths.map((c) => c.first));
      const isCloth = (b) => b >= firstCloth;
      // per slot: dominant bone, cloth row (for the near-pin exclusion)
      const slots = {};
      for (const [slot, mesh] of Object.entries(ch.meshes)) {
        const g = mesh.geometry, n = g.attributes.position.count, I = g.attributes.skinIndex.array, W = g.attributes.skinWeight.array;
        const dom = new Int32Array(n);
        for (let v = 0; v < n; v++) { let b = 0, bw = -1; for (let k = 0; k < 4; k++) if (W[v * 4 + k] > bw) { bw = W[v * 4 + k]; b = I[v * 4 + k]; } dom[v] = b; }
        slots[slot] = { mesh, g, n, dom };
      }
      // cloth vertices (dominant bone is a cloth particle), excluding those bound to the pinned row or the first free row
      const clothVerts = [];
      const clothOf = (b) => cloths.find((c) => b >= c.first && b < c.first + c.n);
      for (const [slot, S] of Object.entries(slots)) {
        const I = S.g.attributes.skinIndex.array, W = S.g.attributes.skinWeight.array;
        for (let v = 0; v < S.n; v++) {
          if (!isCloth(S.dom[v])) continue;
          const cl = clothOf(S.dom[v]);
          let near = false;
          for (let k = 0; k < 4; k++) { const b = I[v * 4 + k]; if (W[v * 4 + k] > 1e-4 && cl && b - cl.first < cl.C * (cl.layout.pinRows + 1)) near = true; }
          clothVerts.push({ slot, v, near, cloth: cl ? cl.layout.spec.name : '?' });
        }
      }
      // body cores: per body bone, a capsule along the bone's own Y axis fitted to the plate / suit geometry the bone
      // dominates (bind frame): ends at the 10th / 90th percentile of y, radius = HULL_SHRINK x the 35th percentile of
      // the distance from that axis (robust to crests, spikes and fur). A point inside is visibly inside the body.
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
      const pct = (arr, q) => { const s2 = Float64Array.from(arr).sort(); return s2[Math.min(s2.length - 1, Math.floor(q * s2.length))]; };
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
      // plate vertices that must stay out of a hull: tassets vs thighs, arm plates vs the chest
      const plateSets = [];
      const P0 = slots.plate ? slots.plate.g.attributes.position.array : null;
      const addSet = (label, srcRe, hullRe) => {
        if (!slots.plate) return;
        const S = slots.plate, verts = [];
        const targets = hulls.filter((h) => hullRe.test(h.name));
        for (let v = 0; v < S.n; v++) {
          if (!srcRe.test(rig.names[S.dom[v]])) continue;
          // bind-inside vertices excluded (the design overlaps them on purpose)
          let inBind = false;
          for (const h of targets) {
            _v.fromArray(P0, v * 3).applyMatrix4(inv[h.bone]);
            if (ell(h, _v.x, _v.y, _v.z) > 0) inBind = true;
          }
          if (!inBind) verts.push(v);
        }
        plateSets.push({ label, verts: Int32Array.from(verts), targets });
      };
      addSet('tasset->thigh', /^tasset[RL]$/, /^thigh[RL]$/);
      addSet('arm->chest', /^(upperArm|upperArmTwist|elbow|foreArm|foreArmTwist)[RL]$/, /^chest$/);
      const C = { id, ch, rig, cloths, springs, firstCloth, slots, clothVerts, hulls, plateSets, idle: IDLE[id] };
      C.BM = new Float32Array(N * 16); C.SM = new Float32Array(N * 16);
      return C;
    }

    /** Depth (m, > 0 = inside) of a bone-frame point in a core capsule. */
    function ell(h, x, y, z) {
      const ay = h.a[1], by = h.b[1];
      const ty = y < ay ? ay : y > by ? by : y;
      return h.r - Math.hypot(x - h.a[0], y - ty, z - h.a[2]);
    }

    // ---- per-frame matrices (model = root frame) ----
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
    function capPen(data, i, x, y, z) {
      const o = i * 7, ax = data[o], ay = data[o + 1], az = data[o + 2], ex = data[o + 3] - ax, ey = data[o + 4] - ay, ez = data[o + 5] - az;
      const ee = ex * ex + ey * ey + ez * ez;
      let t = ee > 1e-12 ? ((x - ax) * ex + (y - ay) * ey + (z - az) * ez) / ee : 0;
      t = t < 0 ? 0 : t > 1 ? 1 : t;
      return data[o + 6] - Math.hypot(x - ax - ex * t, y - ay - ey * t, z - az - ez * t);
    }

    /** Metrics of the current frame. */
    function frame(C) {
      const ch = C.ch, out = { nan: matrices(C) };
      const e = ch.root.matrixWorld.elements;
      // cloth vertices in body hulls
      const byHull = {};
      let n = 0, depth = 0, floorMin = 1e9, headN = 0, headD = 0;
      for (const cv of C.clothVerts) {
        const p = skinV(C, cv.slot, cv.v);
        const wy = e[1] * p[0] + e[5] * p[1] + e[9] * p[2] + e[13];
        if (wy < floorMin) floorMin = wy;
        if (cv.near) continue;
        const x = p[0], y = p[1], z = p[2];
        for (const h of C.hulls) {
          const b = toBone(C, h.bone, x, y, z);
          const d = ell(h, b[0], b[1], b[2]);
          if (d < 0.004 * C.rig.k) continue;
          n++; depth = Math.max(depth, d);
          const key = cv.cloth + '>' + h.name;
          byHull[key] = (byHull[key] || 0) + 1;
          if (h.name === 'head' || h.name === 'neck') { headN++; headD = Math.max(headD, d); }
          break;
        }
      }
      out.clothIn = n; out.clothDepth = depth; out.clothBy = byHull; out.clothHead = headN; out.clothHeadDepth = headD; out.floorMin = floorMin;
      // cloth particles vs the design capsules (what the solver is supposed to guarantee) + structural stretch
      let pn = 0, pd = 0, str = 0, strAt = '';
      const caps = ch._r2aCaps || (ch._r2aCaps = capsulesOf(C));
      updateCaps(C, caps);
      for (const cl of C.cloths) {
        const p = cl.p, pinN = cl.C * cl.layout.pinRows;
        for (let k = pinN; k < cl.n; k++) {
          for (let i = 0; i < caps.count; i++) {
            const d = capPen(caps.data, i, p[k * 3], p[k * 3 + 1], p[k * 3 + 2]);
            if (d > 0.002 * C.rig.k) { pn++; pd = Math.max(pd, d); break; }
          }
        }
        const cons = cl.cons;
        for (let c = 0; c < cons.length; c += 4) {
          const a = cons[c], b = cons[c + 1];
          if (Math.abs(b - a) !== 1 && Math.abs(b - a) !== cl.C) continue;
          const L = Math.hypot(p[b * 3] - p[a * 3], p[b * 3 + 1] - p[a * 3 + 1], p[b * 3 + 2] - p[a * 3 + 2]) / cons[c + 2];
          if (L > str) { str = L; strAt = cl.layout.spec.name + ' ' + (a % cl.C) + ',' + ((a / cl.C) | 0) + (Math.abs(b - a) === 1 ? ' h' : ' v') + ' rest ' + (cons[c + 2] * 1000).toFixed(1) + 'mm'; }
        }
      }
      out.partIn = pn; out.partDepth = pd; out.stretch = str; out.strAt = strAt;
      // plate sets
      for (const S of C.plateSets) {
        let cnt = 0, dmax = 0;
        for (let k = 0; k < S.verts.length; k++) {
          const p = skinV(C, 'plate', S.verts[k]);
          const x = p[0], y = p[1], z = p[2];
          for (const h of S.targets) {
            const b = toBone(C, h.bone, x, y, z);
            const d = ell(h, b[0], b[1], b[2]);
            if (d > 0.004 * C.rig.k) { cnt++; dmax = Math.max(dmax, d); break; }
          }
        }
        out[S.label] = { n: cnt, d: dmax };
      }
      // feet: heel / sole / ball / toe tip vs the world floor (lowest of both feet)
      const P = C.rig.P;
      let low = 1e9;
      for (const s of ['R', 'L']) {
        const f = ch.rig.index['foot' + s], t = ch.rig.index['toe' + s];
        for (const [b, off] of [[f, [-P.heelLength, -P.ankleHeight, 0]], [f, [0, -P.ankleHeight, 0]], [f, [P.footLength, -P.ankleHeight, 0]], [t, [P.toeLength, -(P.ankleHeight - P.footDrop), 0]]]) {
          _v.fromArray(off).applyMatrix4(ch.skeleton.bones[b].matrixWorld);
          low = Math.min(low, _v.y);
        }
      }
      out.soleMin = low;
      out.gripErr = ch.diag.gripErr; out.drop = ch.diag.drop;
      return out;
    }

    function capsulesOf(C) {
      const defs = C.ch.design.colliders || [];
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
    function prime(C, pre = C.idle) {
      const ch = C.ch;
      ch.root.position.set(0, 0, 0); ch.root.rotation.set(0, 0, 0); ch.setFacing(1);
      ch.wind = [0, 0, 0]; ch.lookAt(null);
      ch.teleport();
      ch.play(pre, { fade: 0, restart: true });
      for (let i = 0; i < 45; i++) ch.update(1 / 60, 1 / 60);
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
        let x = sub ? m[key][sub] : m[key];
        if (x > v) { v = x; at = m.t; }
        if (x > 0) frames++;
      }
      return { v: +(+v).toFixed(4), at, frames };
    }
    function summarize(C, clip, rec) {
      const s = { clip, frames: rec.length };
      s.nan = agg(rec, 'nan').frames;
      s.clothIn = agg(rec, 'clothIn'); s.clothDepth = agg(rec, 'clothDepth');
      s.clothHead = agg(rec, 'clothHead'); s.clothHeadDepth = agg(rec, 'clothHeadDepth');
      // where the worst cloth frame is
      const w = rec.find((m) => m.t === s.clothIn.at);
      s.clothBy = w ? Object.entries(w.clothBy).sort((a, b) => b[1] - a[1]).slice(0, 4).map(([k, v]) => k + ':' + v).join(' ') : '';
      s.partIn = agg(rec, 'partIn'); s.partDepth = agg(rec, 'partDepth'); s.stretch = agg(rec, 'stretch');
      { const w2 = rec.find((m) => m.t === s.stretch.at); s.stretchEdge = w2 ? w2.strAt : ''; }
      let fm = Infinity, fat = null; for (const m of rec) if (m.floorMin < fm) { fm = m.floorMin; fat = m.t; }
      s.clothFloorMin = { v: +fm.toFixed(4), at: fat };
      for (const S of C.plateSets) { s[S.label] = agg(rec, S.label, 'n'); s[S.label + ' depth'] = agg(rec, S.label, 'd'); }
      let sm = Infinity, sat = null; for (const m of rec) if (m.soleMin < sm) { sm = m.soleMin; sat = m.t; }
      s.soleMin = { v: +sm.toFixed(4), at: sat };
      s.gripErr = agg(rec, 'gripErr'); s.drop = agg(rec, 'drop');
      return s;
    }
    function compact(s) {
      const f = (a) => (a.v > 0 ? `${a.v}@${a.at}(${a.frames}f)` : '0');
      return `${s.clip}: cloth ${f(s.clothIn)} d${(s.clothDepth.v * 1000).toFixed(0)}mm [${s.clothBy}] head ${f(s.clothHead)} d${(s.clothHeadDepth.v * 1000).toFixed(0)} | part ${f(s.partIn)} d${(s.partDepth.v * 1000).toFixed(0)} | str ${s.stretch.v}@${s.stretch.at} (${s.stretchEdge}) | clothFloor ${s.clothFloorMin.v} | tasset ${f(s['tasset->thigh'] || { v: 0 })} d${(((s['tasset->thigh depth'] || { v: 0 }).v) * 1000).toFixed(0)} | arm>chest ${f(s['arm->chest'] || { v: 0 })} d${(((s['arm->chest depth'] || { v: 0 }).v) * 1000).toFixed(0)} | sole ${s.soleMin.v}@${s.soleMin.at} | grip ${s.gripErr.v}@${s.gripErr.at} | drop ${s.drop.v}`;
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
          if (o.series) s.series = rec.map((m) => o.series.map((k) => { const v = k.includes('.') ? m[k.split('.')[0]][k.split('.')[1]] : m[k]; return typeof v === 'number' ? +v.toFixed(4) : v; }));
          out.push(o.full ? s : compact(s));
        } catch (e) { out.push(clip + ': THREW ' + String(e && e.message || e)); }
      }
      return out;
    }

    function hold(id, clip, t, o = {}) {
      use(id);
      const C = cur, ch = C.ch;
      prime(C, o.pre);
      ch.play(clip, { fade: o.fade ?? 0, restart: true });
      const n = Math.round(t * 60);
      for (let f = 0; f < n; f++) { ch.update(1 / 60, 1 / 60); if (o.root !== false) ch.root.position.x += ch.rootDelta.f * ch.facing; }
      return frame(C);
    }

    // ---- camera ----
    function look(focus = 'chest', yaw = 30, dist = 1.4, pitch = 6) {
      const C = cur, b = C.ch.bones[focus];
      const w = typeof focus === 'string' && focus[0] === 'w' ? focus.slice(1).split('_').map(Number) : null;
      const p = w ? new THREE.Vector3(...w).applyMatrix4(C.ch.root.matrixWorld) : b ? b.getWorldPosition(new THREE.Vector3()) : C.ch.root.getWorldPosition(new THREE.Vector3());
      lab.view({ target: [p.x, p.y, p.z], dist, yaw, pitch });
    }

    // ---- GPU see-through holes ----
    const HW = 1280, HH = 720;
    const rt = new THREE.WebGLRenderTarget(HW, HH);
    const bufF = new Uint8Array(HW * HH * 4), bufD = new Uint8Array(HW * HH * 4);
    const maskF = new THREE.MeshBasicMaterial({ color: 0xffffff, side: THREE.FrontSide });
    const maskD = new THREE.MeshBasicMaterial({ color: 0xffffff, side: THREE.DoubleSide });
    const overlay = document.createElement('canvas');
    overlay.width = HW; overlay.height = HH;
    overlay.style.cssText = 'position:fixed;inset:0;width:100%;height:100%;pointer-events:none;z-index:20;image-rendering:pixelated';
    document.body.appendChild(overlay);
    const label = document.createElement('div');
    label.style.cssText = 'position:fixed;left:8px;top:8px;z-index:21;font:bold 15px/1.35 monospace;color:#fff;background:rgba(0,0,0,.6);padding:4px 8px;border-radius:4px;white-space:pre;pointer-events:none';
    document.body.appendChild(label);
    /**
     * Pixels where the double-sided silhouette has geometry but the front-face render shows background (only the given
     * slots are tested when `slots` is set; the materials' own `side` is ignored: this checks geometry orientation).
     */
    function holes(slots = null, drawOverlay = true) {
      const r = ctx.renderer, scene = ctx.scene;
      const hidden = [];
      const roots = new Set(Object.values(built).map((C) => C.ch.root));
      for (const o of scene.children) if (!roots.has(o) && o.visible && !o.isLight) { hidden.push(o); o.visible = false; }
      const meshVis = [];
      if (slots) for (const C of Object.values(built)) for (const [k, m] of Object.entries(C.ch.meshes)) { meshVis.push([m, m.visible]); m.visible = m.visible && slots.includes(k); }
      const bg = scene.background, fog = scene.fog, cc = r.getClearColor(new THREE.Color()), ca = r.getClearAlpha(), au = r.shadowMap.autoUpdate;
      scene.background = null; scene.fog = null; r.shadowMap.autoUpdate = false;
      const prevRT = r.getRenderTarget();
      r.setRenderTarget(rt); r.setClearColor(0x000000, 1);
      scene.overrideMaterial = maskF; r.clear(); r.render(scene, ctx.camera); r.readRenderTargetPixels(rt, 0, 0, HW, HH, bufF);
      scene.overrideMaterial = maskD; r.clear(); r.render(scene, ctx.camera); r.readRenderTargetPixels(rt, 0, 0, HW, HH, bufD);
      scene.overrideMaterial = null;
      r.setRenderTarget(prevRT); r.setClearColor(cc, ca); r.shadowMap.autoUpdate = au;
      scene.background = bg; scene.fog = fog;
      for (const o of hidden) o.visible = true;
      for (const [m, v] of meshVis) m.visible = v;
      const hole = new Uint8Array(HW * HH);
      let raw = 0, sil = 0;
      for (let i = 0; i < HW * HH; i++) { if (bufD[i * 4] > 128) sil++; if (bufD[i * 4] > 128 && bufF[i * 4] < 128) { hole[i] = 1; raw++; } }
      let clustered = 0;
      for (let y = 1; y < HH - 1; y++) for (let x = 1; x < HW - 1; x++) {
        const i = y * HW + x;
        if (hole[i] && hole[i - 1] + hole[i + 1] + hole[i - HW] + hole[i + HW] >= 2) clustered++;
      }
      const g = overlay.getContext('2d');
      g.clearRect(0, 0, HW, HH);
      if (drawOverlay && raw) {
        const img = g.createImageData(HW, HH);
        for (let y = 0; y < HH; y++) for (let x = 0; x < HW; x++) {
          const i = (HH - 1 - y) * HW + x;
          if (!hole[i]) continue;
          const o = (y * HW + x) * 4;
          img.data[o] = 255; img.data[o + 1] = 0; img.data[o + 2] = 255; img.data[o + 3] = 255;
        }
        g.putImageData(img, 0, 0);
      }
      return { raw, clustered, silhouette: sil };
    }

    // ---- elbow / knee volume helpers: the shipped helper scale vs the same pose with the scale forced to 1 ----
    /**
     * poses: [[name, bones (FK degrees), joint ('foreArmR' | 'shinR')], ...]. For the suit vertices within 7 cm (x body)
     * of the joint in bind: min / max distance to the bone polyline (and vs bind), triangles that face outward in bind
     * and inward when posed (folds), measured with the runtime's volume scale and again with it forced to 1.
     */
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
        definePose('r2a.vol', { bones });
        invalidateClips();
        ch.teleport();
        ch.play('r2a.vol', { fade: 0, restart: true });
        for (let i = 0; i < 3; i++) ch.update(1 / 60, 1 / 60);
        const j = rig.index[joint], par = rig.parent[j], c1 = rig.index[{ foreArmR: 'handR', shinR: 'footR', thighR: 'shinR', upperArmR: 'foreArmR' }[joint]];
        const helper = ch.skeleton.bones.find((b) => b.name === ({ foreArmR: 'elbowVolR', shinR: 'kneeVolR' }[joint]));
        const B0 = [bindPos(par), bindPos(j), bindPos(c1)];
        // region + bind data
        const reg = new Uint8Array(S.n), d0 = new Float32Array(S.n);
        for (let v = 0; v < S.n; v++) {
          if (S.dom[v] >= C.firstCloth) continue;
          const p = new THREE.Vector3().fromArray(P, v * 3);
          if (p.distanceTo(B0[1]) > 0.07 * rig.k) continue;
          reg[v] = 1; d0[v] = near2(p, ...B0)[0];
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
            const out2 = ctr.clone().sub(near2(ctr, ...B)[1]);
            return nrm.dot(out2);
          };
          for (let t = 0; t < idx.length; t += 3) {
            const a2 = idx[t], b2 = idx[t + 1], c2 = idx[t + 2];
            if (!reg[a2] || !reg[b2] || !reg[c2]) continue;
            if (fn(P, a2, b2, c2, B0) <= 0) continue; // only triangles that face away from the bone in bind
            tris++;
            if (fn(pos, a2, b2, c2, B1) < 0) folds++;
          }
          return { n, minR: +(minR * 1000).toFixed(1), minRatio: +minRatio.toFixed(3), maxR: +(maxR * 1000).toFixed(1), maxRatio: +maxRatio.toFixed(3), folds, tris };
        };
        const shipped = measureNow();
        if (!helper) { out.push({ pose: name, joint, shipped }); continue; }
        const hs = helper.scale.toArray().map((x) => +x.toFixed(3));
        helper.scale.set(1, 1, 1); ch.root.updateMatrixWorld(true);
        const unscaled = measureNow();
        helper.scale.fromArray(hs); ch.root.updateMatrixWorld(true);
        out.push({ pose: name, helperScale: hs, shipped, unscaled });
      }
      return out;
    }

    // ---- frame-rate dependence of the cloth on a real clip ----
    function dtCloth(id, clip, every = 1 / 30) {
      use(id);
      const C = cur;
      const snapAt = (o, perturb = 0) => {
        const snaps = [];
        const ch = C.ch;
        prime(C);
        ch.wind = [perturb, 0, 0];
        ch.play(clip, { fade: 0.08, restart: true });
        const dur = getClip(ch.rig, clip).duration + 0.4;
        let t = 0, next = every, f = 0;
        while (t < dur - 1e-9) {
          const h = o(f++);
          ch.update(h, h); t += h;
          ch.root.position.x += ch.rootDelta.f * ch.facing;
          if (t >= next - 1e-7) { snaps.push({ t: +t.toFixed(4), p: C.cloths.map((c) => Float32Array.from(c.p)) }); next += every; }
        }
        return snaps;
      };
      const ref = snapAt(() => 1 / 60);
      // chaos baseline: the same 60 Hz run with a 0.01 m/s^2 breeze (nothing visible): how far the sheet drifts on its own
      const runs = { hz60_breeze001: snapAt(() => 1 / 60, 0.01), hz30: snapAt(() => 1 / 30), hz120: snapAt(() => 1 / 120), alt60_30: snapAt((f) => (f % 2 ? 1 / 30 : 1 / 60)), slow01: snapAt(() => 1 / 600) };
      C.ch.wind = [0, 0, 0];
      const res = {};
      for (const [k, tr] of Object.entries(runs)) {
        let mx = 0, at = null, sum = 0, cnt = 0;
        const n = Math.min(ref.length, tr.length);
        for (let i = 0; i < n; i++) {
          if (Math.abs(ref[i].t - tr[i].t) > 1e-3) continue;
          for (let c = 0; c < ref[i].p.length; c++) {
            const a = ref[i].p[c], b = tr[i].p[c];
            for (let k2 = 0; k2 < a.length; k2 += 3) { const d = Math.hypot(a[k2] - b[k2], a[k2 + 1] - b[k2 + 1], a[k2 + 2] - b[k2 + 2]); sum += d * d; cnt++; if (d > mx) { mx = d; at = ref[i].t; } }
          }
        }
        res[k] = { max: +mx.toFixed(4), rms: +Math.sqrt(sum / Math.max(1, cnt)).toFixed(4), at, samples: n };
      }
      return res;
    }

    // ---- capture queue: items [id, clip, t, focus, yaw, dist, pitch, holes (true | slot list | false), showSlots] ----
    let queue = [];
    function step() {
      const it = queue.shift();
      if (!it) return null;
      const [id, clip, t, focus, yaw, dist, pitch = 6, withHoles = false, showSlots = null, fade = 0] = it;
      const m = hold(id, clip, t, { fade });
      for (const C of Object.values(built)) for (const [k, mm] of Object.entries(C.ch.meshes)) mm.visible = C === cur && (!showSlots || showSlots.includes(k));
      look(focus, yaw, dist, pitch);
      overlay.getContext('2d').clearRect(0, 0, HW, HH);
      let txt = `${id} ${clip}@${t} yaw ${yaw}`;
      if (withHoles) { const h = holes(withHoles === true ? null : withHoles, true); txt += `  holes ${h.clustered}px`; }
      txt += `  cloth-in ${m.clothIn} head ${m.clothHead}` + (m['arm->chest'] ? `  arm>chest ${m['arm->chest'].n} (${(m['arm->chest'].d * 1000).toFixed(0)}mm)` : '') + (fade ? `  fade ${fade}` : '');
      label.textContent = txt;
      return txt;
    }

    // ---- CPU: char.update of a real design over a clip chain, replayed; mean of each frame's fastest replay ----
    function cpu(id, chain, replays = 6) {
      use(id);
      const C = cur, ch = C.ch, per = [];
      for (let r = 0; r < replays; r++) {
        prime(C);
        let f = 0;
        for (const clip of chain) {
          ch.play(clip, { fade: 0.08, restart: true });
          const n = Math.round(getClip(ch.rig, clip).duration * 60);
          for (let k = 0; k < n; k++, f++) {
            const t0 = performance.now();
            ch.update(1 / 60, 1 / 60);
            const dt = performance.now() - t0;
            per[f] = r === 0 ? dt : Math.min(per[f], dt);
          }
        }
      }
      const s = per.slice().sort((a, b) => a - b);
      const cl = C.cloths.reduce((a, c) => a + c.n, 0);
      // frames whose fastest replay still costs > 3 ms (deterministic work, not contention): frame index and clip
      const bounds = []; let acc = 0; for (const clip of chain) { bounds.push([acc, clip]); acc += Math.round(getClip(ch.rig, clip).duration * 60); }
      const slow = per.map((v, i) => [i, v]).filter(([, v]) => v > 3).map(([i, v]) => { const b = bounds.filter(([a]) => a <= i).pop(); return `${b[1]}+${i - b[0]}f:${v.toFixed(1)}ms`; });
      return { id, slow, frames: per.length, clothParticles: cl, iters: C.cloths.map((c) => c.iters), meanOfMin: +(per.reduce((a, b) => a + b, 0) / per.length).toFixed(3), p50: +s[s.length >> 1].toFixed(3), p95: +s[Math.floor(s.length * 0.95)].toFixed(3) };
    }

    window.__ED.r2a = {
      cpu,
      queue(items) { queue = items.slice(); return queue.length; }, step,
      DESIGNS, use, get cur() { return cur; }, built, clips: clipsOf, scan, hold, frame: () => frame(cur), look, holes, volume, dtCloth,
      hullInfo: (id) => { use(id); return cur.hulls.map((h) => ({ bone: h.name, a: h.a.map((x) => +x.toFixed(3)), b: h.b.map((x) => +x.toFixed(3)), r: +h.r.toFixed(3), n: h.n })); },
      show(slots) { for (const C of Object.values(built)) for (const [k, m] of Object.entries(C.ch.meshes)) m.visible = !slots || slots.includes(k); return slots; },
      label(t) { label.textContent = t; return t; },
      clearOverlay() { overlay.getContext('2d').clearRect(0, 0, HW, HH); },
      run: runClip, prime,
    };
    // the lab's own clock keeps the visible character simulated (captures after hold())
    ctx.onUpdate((dg, dr) => { if (cur && cur.live) cur.ch.update(dg, dr); }, ORDER.CHAR);
    use('kael');
  },
  scenarios: {},
});
