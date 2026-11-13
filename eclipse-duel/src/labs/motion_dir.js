// Motion review lab (animation director). Lays any list of clips out as contact sheets and measures them, one browser
// session for the whole batch. Usage and the reading guide: src/fighters/MOTION.md, section "Review harness".
//
//   node tools/motion.mjs kael kael.light1 kael.sweep            sheets + audit table -> shots/murim/motion/dir/
//   node tools/motion.mjs iska moves --frames 10 --tag before   every move clip of a hero ("all" | "moves" | "states" | "ult" | "generic")
//   node tools/shot.mjs motion_dir --size 960x540 --do "await __ED.lab.play('sheet','vorn','vorn.flash_jab')" --at 0 --out shots/x
//
// In the page (window.__ED.motion):
//   sheet(hero, clip, opts)   -> { png (data URL), meta }: 8 side frames + 4 three-quarter frames (opts.frames / cols /
//                                cell / views / times / body / xray / audit), event markers in the frame labels, the weapon
//                                tip path as a ghost trail (bright = travelled so far, one dot per 1/60 s frame = spacing)
//   audit(hero, clips)        -> rows of qa.auditClip numbers (+ weapon clearance of head / hat / hair keep-outs)
//   table(rows)               -> the rows as a fixed-width text table
//   clips(hero, group)        -> registered clip names ('all' | 'moves' | 'states' | 'ult' | 'generic')
//   actor(hero, body)         -> the character ('design' = the hero's real design, 'mannequin' = colour-coded limbs)
// Heroes: kael | iska | vorn | knight (the demo knight: generic game.* / demo.* clips at their authored proportions).
// A lab copy for a private build: src/labs/motion_<label>.js containing `import './motion_dir.js';`.

import * as THREE from 'three';
import { createLab } from '../core/lab.js';
import { createCharacter, defineClip, definePose, invalidateClips, listClips, hasClip } from '../char/index.js';
import { getClip, getClipDef } from '../char/anim.js';
import { createRig } from '../char/skeleton.js';
import * as qa from '../char/qa.js';
import { knight } from '../char/designs/knight.js';
import '../char/clips/demo.js';
import { GENERIC, twinVariant } from '../game/clips.js';
import { kael } from '../fighters/kael/design.js';
import { iska } from '../fighters/iska/design.js';
import { vorn } from '../fighters/vorn/design.js';
import '../fighters/kael/clips/index.js';
import '../fighters/iska/clips/index.js';
import '../fighters/vorn/clips/index.js';

/**
 * Keep-out volumes the weapon must not cut through, beyond the body capsules: the head, and the silhouette pieces of
 * the murim costumes (MURIM.md section 2). Capsules [bone, a, b, radius] in the bone's zero frame (metres, x body scale).
 * A design may override them with `design.keepOut` (same format).
 */
const KEEP_OUT = {
  kael: [['head', 'head', [0.02, 0.09, 0], [0.02, 0.12, 0], 0.125], ['topknot', 'head', [-0.03, 0.2, 0], [-0.05, 0.28, 0], 0.06]],
  iska: [['head', 'head', [0.02, 0.08, 0], [0.02, 0.11, 0], 0.115], ['hairTail', 'head', [-0.1, 0.1, 0], [-0.2, 0.02, 0], 0.07]],
  vorn: [['head', 'head', [0.02, 0.09, 0], [0.02, 0.12, 0], 0.125], ['hatBrim', 'head', [-0.2, 0.17, 0], [0.24, 0.17, 0], 0.2], ['hatCone', 'head', [0.02, 0.2, 0], [0.02, 0.36, 0], 0.09]],
  knight: [['head', 'head', [0.02, 0.09, 0], [0.02, 0.12, 0], 0.125]],
};
const HEROES = {
  kael: { design: kael, prefix: 'kael.' },
  iska: { design: iska, prefix: 'iska.' },
  vorn: { design: vorn, prefix: 'vorn.' },
  knight: { design: knight, prefix: 'demo.' },
};
const VIEWS = { side: { yaw: 0, pitch: 4 }, q: { yaw: 52, pitch: 12 }, front: { yaw: 90, pitch: 4 }, rear: { yaw: -128, pitch: 12 }, top: { yaw: 0, pitch: 82 } };
const EVENT_COLORS = { impact: '#ff5a4a', hit: '#ff5a4a', trailOn: '#59d7ff', trailOff: '#3f8fb0', step: '#8be28b' };
const r = (x, d = 3) => (Number.isFinite(x) ? Math.round(x * 10 ** d) / 10 ** d : x);

let CTX = null, LAB = null;
const cast = new Map();

/** A colour-coded mannequin on the hero's rig data (right limbs warm, left limbs cool): limbs never hide under robes. */
function mannequin(id) {
  const d = HEROES[id].design;
  const rig0 = createRig(d.proportions || {});
  const std = new Set(rig0.names);
  const weapons = d.weapons || (d.weapon ? [d.weapon] : []);
  return {
    id: 'mq_' + id, idle: 'neutral.hold', proportions: d.proportions || {}, gripAngle: d.gripAngle ?? (d.weapon && d.weapon.gripAngle) ?? 0,
    clipScale: d.clipScale, maxPelvisDrop: d.maxPelvisDrop, materials: { suit: { envMapIntensity: 0.3 } }, bones: [], springs: [], cloth: [], sockets: {},
    colliders: (d.colliders || []).filter((cl) => std.has(cl.a[0]) && std.has(cl.b[0])),
    ...(d.weapons ? { weapons: d.weapons } : { weapon: d.weapon }),
    build(kit, S, rig) {
      const P = rig.P, L = rig.lengths, k = rig.k || 1;
      const G = 0x9a9ca6, RC = 0xe08a3a, LC = 0x4f8fe0, DK = 0x3a3c44;
      const limb = (bone, len, r0, r1, color) => kit.add('suit', bone, S.cylinder(r0 * k, r1 * k, len, 10), { at: [0, -len / 2, 0], color, rough: 0.7 });
      kit.add('suit', 'hips', S.box(0.17 * k, 0.16 * k, (P.hipWidth * 2 + 0.1 * k), 0.04 * k), { at: [0, -0.02 * k, 0], color: G, rough: 0.7 });
      kit.add('suit', 'spine', S.cylinder(0.105 * k, 0.115 * k, P.spine + 0.04 * k, 10), { at: [0, P.spine / 2, 0], color: DK, rough: 0.7 });
      kit.add('suit', 'chest', S.box(0.2 * k, P.chest + 0.1 * k, 0.34 * k, 0.07 * k), { at: [0, (P.chest + 0.06 * k) / 2, 0], color: G, rough: 0.7 });
      kit.add('suit', 'neck', S.cylinder(0.05 * k, 0.055 * k, 0.12 * k, 8), { at: [0, 0.05 * k, 0], color: DK, rough: 0.7 });
      kit.add('suit', 'head', S.sphere(0.105 * k, 14, 10), { at: [0.02 * k, 0.1 * k, 0], color: G, rough: 0.6 });
      kit.add('suit', 'head', S.box(0.07 * k, 0.035 * k, 0.11 * k, 0.01 * k), { at: [0.105 * k, 0.1 * k, 0], color: 0xfff2c0, rough: 0.4 });   // visor: where the eyes look
      for (const s of ['R', 'L']) {
        const c = s === 'R' ? RC : LC;
        limb('upperArm' + s, L.upperArm, 0.055, 0.045, c);
        limb('foreArm' + s, L.foreArm, 0.045, 0.036, c);
        kit.add('suit', 'hand' + s, S.box(0.07 * k, P.hand + 0.03 * k, 0.045 * k, 0.015 * k), { at: [0, -P.hand * 0.55, 0], color: DK, rough: 0.6 });
        limb('thigh' + s, L.thigh, 0.085, 0.062, c);
        limb('shin' + s, L.shin, 0.058, 0.042, c);
        kit.add('suit', 'foot' + s, S.box(P.footLength + P.heelLength, 0.06 * k, 0.09 * k, 0.02 * k), { at: [(P.footLength - P.heelLength) / 2, -(P.ankleHeight - 0.03 * k), 0], color: DK, rough: 0.6 });
        kit.add('suit', 'toe' + s, S.box(P.toeLength, 0.04 * k, 0.085 * k, 0.015 * k), { at: [P.toeLength / 2, -(P.ankleHeight - P.footDrop - 0.02 * k), 0], color: c, rough: 0.6 });
      }
      for (const w of weapons) {
        const bone = 'weapon' + (w.hand || 'R');
        const back = Math.min(-0.08, ...Object.values(w.grips || {}).map((g) => g.pos[0] - 0.06));
        const b = w.base, t = w.tip, dx = t[0] - b[0], dy = t[1] - b[1], len = Math.hypot(dx, dy);
        kit.add('suit', bone, S.box(b[0] - back, 0.03, 0.03, 0.01), { at: [(b[0] + back) / 2, 0, 0], color: 0x5a4636, rough: 0.8 });
        kit.add('suit', bone, S.box(len, len > 1 ? 0.085 : 0.06, 0.014, 0.004), { at: [(b[0] + t[0]) / 2, (b[1] + t[1]) / 2, 0], rot: [0, 0, (Math.atan2(dy, dx) * 180) / Math.PI], color: 0xd8dde6, rough: 0.3, metal: 0.8 });
      }
    },
  };
}

/** The review character of a hero: 'design' (falls back to the mannequin when the design throws) or 'mannequin'. */
function actor(id, body = 'design') {
  const H = HEROES[id];
  if (!H) throw new Error('motion: unknown hero ' + id + ' (have ' + Object.keys(HEROES).join(', ') + ')');
  const key = id + ':' + body;
  if (cast.has(key)) return cast.get(key);
  let c = null;
  if (body === 'design') {
    try {
      c = createCharacter(CTX, H.design, { name: 'md_' + id });
      if (typeof H.design.attach === 'function') { try { H.design.attach(c); } catch (e) { /* glow control only */ } }
    } catch (e) {
      console.warn('[ed] motion: design of ' + id + ' failed (' + (e && e.message) + '): mannequin instead');
      c = null;
    }
  }
  if (!c) {
    if (cast.has(id + ':mannequin')) { cast.set(key, cast.get(id + ':mannequin')); return cast.get(key); }
    c = createCharacter(CTX, mannequin(id), { name: 'mq_' + id });
    c.isMannequin = true;
    cast.set(id + ':mannequin', c);
  }
  c.root.traverse((o) => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; o.frustumCulled = false; } });
  c.heroId = id;
  c.weaponSockets = [];
  for (let k = 0; ; k++) {
    const sfx = k === 0 ? '' : String(k + 1);
    const a = c.sockets['weaponBase' + sfx], b = c.sockets['weaponTip' + sfx];
    if (!a || !b) break;
    c.weaponSockets.push({ a, b });
  }
  c.setVisible(false);
  cast.set(key, c);
  return c;
}

/** The clip a hero really plays for `name`: generic / demo clips get their twin-blade variant on a twin design. */
function clipFor(c, name) {
  if (!hasClip(name)) throw new Error('motion: unknown clip ' + name);
  return c.weaponSockets.length > 1 && /^(game|demo)\./.test(name) ? twinVariant(name) : name;
}

/** Registered clip names of a hero by group. */
function clips(id, group = 'all') {
  if (group === 'generic') {
    return [...new Set([...listClips().filter((n) => n.startsWith('game.') && !n.includes('@')), ...Object.values(GENERIC)])].filter((n) => hasClip(n)).sort();
  }
  const p = HEROES[id].prefix;
  const all = listClips().filter((n) => n.startsWith(p) && !n.includes('@'));
  const isUlt = (n) => n.includes('.ult.');
  const isMove = (n) => { const d = getClipDef(n); return !isUlt(n) && !!d && Array.isArray(d.events) && d.events.some((e) => e.name === 'impact' || e.name === 'hit' || e.name === 'trailOn'); };
  if (group === 'ult') return all.filter(isUlt);
  if (group === 'moves') return all.filter(isMove);
  if (group === 'states') return all.filter((n) => !isUlt(n) && !isMove(n));
  return all;
}

// ---- measuring pass: 60 Hz trace of weapon tips, body extents, keep-out clearance ------------------------------------
const _v = new THREE.Vector3(), _a = new THREE.Vector3(), _b = new THREE.Vector3(), _c = new THREE.Vector3(), _d = new THREE.Vector3();
const EXTENT_BONES = ['head', 'handR', 'handL', 'footR', 'footL', 'toeR', 'toeL', 'hips', 'chest', 'foreArmR', 'foreArmL', 'shinR', 'shinL'];
const STICK = [['hips', 'spine'], ['spine', 'chest'], ['chest', 'neck'], ['neck', 'head'],
  ['chest', 'upperArmR'], ['upperArmR', 'foreArmR'], ['foreArmR', 'handR'], ['chest', 'upperArmL'], ['upperArmL', 'foreArmL'], ['foreArmL', 'handL'],
  ['hips', 'thighR'], ['thighR', 'shinR'], ['shinR', 'footR'], ['footR', 'toeR'], ['hips', 'thighL'], ['thighL', 'shinL'], ['shinL', 'footL'], ['footL', 'toeL']];

function segSeg(p1, q1, p2, q2) { return qa.segDist([p1.x, p1.y, p1.z], [q1.x, q1.y, q1.z], [p2.x, p2.y, p2.z], [q2.x, q2.y, q2.z]); }

function keepOuts(c) {
  const k = c.bodyScale || 1, list = c.design.keepOut || KEEP_OUT[c.heroId] || KEEP_OUT.knight;
  return list.map(([name, bone, a, b, rad]) => ({ name, bone: c.bones[bone], a: new THREE.Vector3(...a).multiplyScalar(k), b: new THREE.Vector3(...b).multiplyScalar(k), r: rad * k }));
}

/** Start `clip` from a clean state (no look-at, no wind) with root motion applied to the root. */
function begin(c, clip) {
  qa.resetForQA(c, clip, { breath: 1 });
  c.applyRootMotion = true;
}

/**
 * Play the clip once at 60 Hz and record what the sheet and the clearance check need.
 * @returns {{ n, tips: Float32Array[], rootX: Float32Array, box: {min, max} (root-relative), clear: { min, t, part, weapon } }}
 */
function trace(c, clip, dur) {
  const n = Math.round(dur * 60) + 1, W = c.weaponSockets.length;
  const tips = c.weaponSockets.map(() => new Float32Array(n * 3)), rootX = new Float32Array(n);
  const min = new THREE.Vector3(1e9, 1e9, 1e9), max = new THREE.Vector3(-1e9, -1e9, -1e9);
  const KO = keepOuts(c), clear = { min: Infinity, t: 0, part: '', weapon: 0 };
  begin(c, clip);
  for (let f = 0; f < n; f++) {
    if (f > 0) c.update(1 / 60, 1 / 60);
    const rx = c.root.position.x;
    rootX[f] = rx;
    const grow = (v) => { _v.copy(v); _v.x -= rx; min.min(_v); max.max(_v); };
    for (const b of EXTENT_BONES) if (c.bones[b]) grow(c.bones[b].getWorldPosition(_a));
    _a.setFromMatrixPosition(c.bones.head.matrixWorld); _a.y += 0.24 * (c.bodyScale || 1); grow(_a);
    for (let w = 0; w < W; w++) {
      const S = c.weaponSockets[w];
      S.a.getWorldPosition(_a); S.b.getWorldPosition(_b);
      tips[w][f * 3] = _b.x; tips[w][f * 3 + 1] = _b.y; tips[w][f * 3 + 2] = _b.z;
      grow(_a); grow(_b);
      for (const ko of KO) {
        _c.copy(ko.a).applyMatrix4(ko.bone.matrixWorld); _d.copy(ko.b).applyMatrix4(ko.bone.matrixWorld);
        const d = segSeg(_a, _b, _c, _d) - ko.r - 0.02;
        if (d < clear.min) { clear.min = d; clear.t = f / 60; clear.part = ko.name; clear.weapon = w; }
      }
    }
  }
  c.applyRootMotion = false;
  return { n, tips, rootX, box: { min, max }, clear: { min: r(clear.min), t: r(clear.t), part: clear.part, weapon: clear.weapon } };
}

// ---- overlays: tip trails + x-ray stick figure -------------------------------------------------------------------------
const TRAIL_COLORS = [[1.0, 0.86, 0.25], [0.35, 0.9, 1.0]];
let overlay = null;
function overlays(nMax) {
  if (overlay && overlay.cap >= nMax) return overlay;
  if (overlay) { for (const o of overlay.all) { CTX.scene.remove(o); o.geometry.dispose(); o.material.dispose(); } }
  const all = [], trails = [];
  for (let w = 0; w < 2; w++) {
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(nMax * 3), 3));
    const col = new THREE.Color(...TRAIL_COLORS[w]);
    const mk = (Cls, mat) => { const o = new Cls(g, mat); o.frustumCulled = false; o.renderOrder = 999; CTX.scene.add(o); all.push(o); return o; };
    const future = mk(THREE.Line, new THREE.LineBasicMaterial({ color: col.clone().multiplyScalar(0.22), depthTest: false, depthWrite: false, transparent: true }));
    const g2 = new THREE.BufferGeometry(); g2.setAttribute('position', g.getAttribute('position'));
    const past = new THREE.Line(g2, new THREE.LineBasicMaterial({ color: col, depthTest: false, depthWrite: false, transparent: true }));
    const dots = new THREE.Points(g2, new THREE.PointsMaterial({ color: col, size: 4, sizeAttenuation: false, depthTest: false, depthWrite: false, transparent: true }));
    for (const o of [past, dots]) { o.frustumCulled = false; o.renderOrder = 1000; CTX.scene.add(o); all.push(o); }
    trails.push({ g, g2, future, past, dots });
  }
  const sg = new THREE.BufferGeometry();
  sg.setAttribute('position', new THREE.BufferAttribute(new Float32Array(STICK.length * 6), 3));
  const sc = new Float32Array(STICK.length * 6);
  STICK.forEach(([, b], i) => { const col = b.endsWith('R') ? [1, 0.55, 0.2] : b.endsWith('L') ? [0.3, 0.6, 1] : [0.85, 0.85, 0.85]; sc.set(col, i * 6); sc.set(col, i * 6 + 3); });
  sg.setAttribute('color', new THREE.BufferAttribute(sc, 3));
  const stick = new THREE.LineSegments(sg, new THREE.LineBasicMaterial({ vertexColors: true, depthTest: false, depthWrite: false, transparent: true, opacity: 0.85 }));
  stick.frustumCulled = false; stick.renderOrder = 998; CTX.scene.add(stick); all.push(stick);
  overlay = { cap: nMax, trails, stick, all };
  return overlay;
}
function hideOverlays() { if (overlay) for (const o of overlay.all) o.visible = false; }

// ---- the contact sheet ---------------------------------------------------------------------------------------------------
/**
 * One contact sheet of a clip.
 * opts: { frames = 8 (side frames, evenly spaced, the first impact snapped in), times: [s...] (overrides frames),
 *         cols = 4, cell = [240, 180], ss = 2 (supersampling), views = ['side', 'q'] (the second view shows every
 *         `every`-th sample; any of side | q | front | rear | top), every = 2, body = 'design' | 'mannequin',
 *         xray (stick figure over the body; default: on for designs), trail = true, cycles = 1 (loops),
 *         audit: row (drawn as a footer line), title }
 * @returns {{ png: string, meta: object }} png = data URL of the sheet (also shown over the page for screenshots)
 */
function sheet(id, clipName, opts = {}) {
  const c = actor(id, opts.body || 'design');
  const clip = clipFor(c, clipName);
  const cc = getClip(c.rig, clip), def = getClipDef(clip) || {};
  const dur = cc.duration * (cc.loop ? (opts.cycles || 1) : 1);
  const [cw, ch] = opts.cell || [240, 180], ss = opts.ss || 2, cols = opts.cols || 4;
  const views = opts.views || ['side', 'q'], every = opts.every || 2;
  const events = (def.events || []).map((e) => ({ t: e.t, name: e.name })).sort((a, b) => a.t - b.t);
  // sample frames (whole 1/60 s frames)
  let times = opts.times;
  if (!times) {
    const N = Math.max(2, opts.frames || 8);
    times = Array.from({ length: N }, (_, i) => (dur * i) / (N - 1));
    const imp = events.find((e) => e.name === 'impact' || e.name === 'hit');
    // the impact is shown on the first whole frame at / after it (the frame the hit-stop holds)
    if (imp) { const ti = Math.ceil(imp.t * 60 - 1e-6) / 60; let best = 1; for (let i = 1; i < N - 1; i++) if (Math.abs(times[i] - ti) < Math.abs(times[best] - ti)) best = i; times[best] = ti; }
  }
  const fr = [...new Set(times.map((t) => Math.max(0, Math.min(Math.round(dur * 60), Math.round(t * 60 - 1e-6)))))].sort((a, b) => a - b);

  for (const o of cast.values()) o.setVisible(false);
  c.setVisible(true);
  const tr = trace(c, clip, dur);
  const ov = overlays(tr.n + 2);
  const useTrail = opts.trail !== false, xray = opts.xray ?? !c.isMannequin;
  ov.trails.forEach((T, w) => {
    const on = useTrail && w < tr.tips.length;
    T.future.visible = T.past.visible = T.dots.visible = on;
    if (on) { T.g.getAttribute('position').array.set(tr.tips[w]); T.g.getAttribute('position').needsUpdate = true; T.g.setDrawRange(0, tr.n); }
  });
  ov.stick.visible = xray;

  // camera fit on the root-relative extents
  const ctr = tr.box.min.clone().add(tr.box.max).multiplyScalar(0.5), half = tr.box.max.clone().sub(tr.box.min).multiplyScalar(0.5);
  ctr.y = Math.max(ctr.y, 0.2); half.y = Math.max(half.y, 0.9);
  const cam = CTX.camera, aspect = cw / ch, fov = 30, tanH = Math.tan((fov * Math.PI) / 360);
  const corners = [];
  for (let i = 0; i < 8; i++) corners.push(new THREE.Vector3(ctr.x + (i & 1 ? half.x : -half.x), ctr.y + (i & 2 ? half.y : -half.y), ctr.z + (i & 4 ? half.z : -half.z)));
  const fits = {};
  /** Smallest camera distance that keeps the whole extent box inside the cell for a view (bisection on the 8 corners). */
  const fit = (view) => {
    if (fits[view]) return fits[view];
    const V = VIEWS[view] || VIEWS.side, yaw = (V.yaw * Math.PI) / 180, pitch = (V.pitch * Math.PI) / 180;
    const dirc = new THREE.Vector3(Math.sin(yaw) * Math.cos(pitch), Math.sin(pitch), Math.cos(yaw) * Math.cos(pitch));
    const right = new THREE.Vector3(Math.cos(yaw), 0, -Math.sin(yaw)), up = new THREE.Vector3().crossVectors(dirc, right);
    const inside = (dist) => corners.every((p) => {
      _v.copy(p).sub(ctr);
      const z = dist - _v.dot(dirc);
      return z > 0.2 && Math.abs(_v.dot(right)) <= z * tanH * aspect * 0.94 && Math.abs(_v.dot(up)) <= z * tanH * 0.9;
    });
    let lo = 0.5, hi = 60;
    for (let i = 0; i < 24; i++) { const m = (lo + hi) / 2; if (inside(m)) hi = m; else lo = m; }
    return (fits[view] = { dirc, dist: hi });
  };
  const place = (view, rx) => {
    const { dirc, dist } = fit(view);
    cam.fov = fov; cam.aspect = aspect; cam.near = 0.1; cam.updateProjectionMatrix();
    cam.position.set(ctr.x + rx + dirc.x * dist, ctr.y + dirc.y * dist, ctr.z + dirc.z * dist);
    cam.lookAt(ctr.x + rx, ctr.y, ctr.z);
  };

  // GL canvas at the cell size (supersampled); the sheet is composed on a 2D canvas shown over the page
  const gl = CTX.canvas;
  const old = { w: gl.style.width, h: gl.style.height };
  gl.style.width = cw * ss + 'px'; gl.style.height = ch * ss + 'px';
  CTX.resize();
  const cells = [];
  fr.forEach((f, i) => { cells.push({ f, view: views[0] }); });
  if (views[1]) fr.forEach((f, i) => { if (i % every === (every > 1 ? 1 : 0) || every === 1) cells.push({ f, view: views[1] }); });
  if (views[2]) fr.forEach((f, i) => { if (i % every === (every > 1 ? 1 : 0) || every === 1) cells.push({ f, view: views[2] }); });
  const rows = Math.ceil(cells.length / cols), head = 18, foot = opts.audit ? 16 : 0;
  const cv = LAB.sheetCanvas, g = cv.getContext('2d');
  cv.width = cols * cw; cv.height = head + rows * ch + foot;
  cv.style.display = 'block';
  g.fillStyle = '#0d0f14'; g.fillRect(0, 0, cv.width, cv.height);

  // render pass: replay from a clean reset, draw each requested frame
  begin(c, clip);
  const want = new Map();
  cells.forEach((cell, k) => { if (!want.has(cell.f)) want.set(cell.f, []); want.get(cell.f).push(k); });
  const stickPos = ov.stick.geometry.getAttribute('position');
  let prevF = -1;
  for (let f = 0; f < tr.n; f++) {
    if (f > 0) c.update(1 / 60, 1 / 60);
    if (!want.has(f)) continue;
    if (useTrail) ov.trails.forEach((T, w) => { if (w < tr.tips.length) T.g2.setDrawRange(0, f + 1); });
    if (xray) {
      STICK.forEach(([a, b], i) => {
        c.bones[a].getWorldPosition(_a); c.bones[b].getWorldPosition(_b);
        stickPos.setXYZ(i * 2, _a.x, _a.y, _a.z); stickPos.setXYZ(i * 2 + 1, _b.x, _b.y, _b.z);
      });
      stickPos.needsUpdate = true;
    }
    const t = f / 60;
    const crossed = events.filter((e) => e.t > prevF / 60 + 1e-6 && e.t <= t + 1e-6);
    for (const k of want.get(f)) {
      const cell = cells[k];
      place(cell.view, c.root.position.x);
      CTX.renderer.info.reset();
      CTX.post.render(CTX.scene, cam);
      const x = (k % cols) * cw, y = head + Math.floor(k / cols) * ch;
      g.drawImage(gl, 0, 0, gl.width, gl.height, x, y, cw, ch);
      g.strokeStyle = '#000'; g.lineWidth = 1; g.strokeRect(x + 0.5, y + 0.5, cw - 1, ch - 1);
      g.font = 'bold 11px ui-monospace,Menlo,Consolas,monospace'; g.textBaseline = 'top';
      const lab = t.toFixed(3) + (cell.view !== views[0] ? ' ' + cell.view : '');
      g.fillStyle = 'rgba(0,0,0,.6)'; g.fillRect(x + 2, y + 2, g.measureText(lab).width + 6, 14);
      g.fillStyle = '#fff'; g.fillText(lab, x + 5, y + 4);
      let ex = x + g.measureText(lab).width + 12;
      for (const e of crossed) {
        const w = g.measureText(e.name).width + 6;
        g.fillStyle = 'rgba(0,0,0,.6)'; g.fillRect(ex, y + 2, w, 14);
        g.fillStyle = EVENT_COLORS[e.name] || '#ffd36a'; g.fillText(e.name, ex + 3, y + 4);
        ex += w + 2;
      }
    }
    prevF = f;
  }
  c.applyRootMotion = false;
  hideOverlays();
  gl.style.width = old.w; gl.style.height = old.h;
  CTX.resize();
  LAB.view();

  // header + footer
  g.font = 'bold 12px ui-monospace,Menlo,Consolas,monospace'; g.textBaseline = 'top';
  g.fillStyle = '#ffe9a8';
  const title = (opts.title ? opts.title + '  ' : '') + id + ' · ' + clipName + (clip !== clipName ? ' (' + clip + ')' : '') + ' · ' + r(cc.duration, 3) + ' s' + (cc.loop ? ' loop' : '') +
    (Math.abs(tr.rootX[tr.n - 1]) > 0.005 ? ' · root ' + r(tr.rootX[tr.n - 1], 2) + ' m' : '');
  g.fillText(title, 5, 3);
  const tw = g.measureText(title).width;
  const evs = events.map((e) => e.name + ' ' + r(e.t, 3)).join('  ');
  g.font = '11px ui-monospace,Menlo,Consolas,monospace'; g.fillStyle = '#9fb4c8';
  const ew = g.measureText(evs).width;
  if (tw + 24 + ew < cv.width) g.fillText(evs, cv.width - 5 - ew, 4);
  if (opts.audit) {
    g.fillStyle = '#c8d0da';
    g.fillText(auditLine(opts.audit), 5, head + rows * ch + 2);
  }
  const meta = { hero: id, clip: clipName, played: clip, duration: r(cc.duration), loop: cc.loop, frames: fr.map((f) => r(f / 60)), events, rootEnd: r(tr.rootX[tr.n - 1]), clear: tr.clear, mannequin: !!c.isMannequin, size: [cv.width, cv.height] };
  return { png: cv.toDataURL('image/png'), meta };
}

// ---- audit ---------------------------------------------------------------------------------------------------------------
/** qa.auditClip of one clip on the hero's rig, reduced to the review row (see MOTION.md "Reading the audit table"). */
function auditRow(id, clipName) {
  const c = actor(id, 'mannequin');
  const clip = clipFor(c, clipName);
  for (const o of cast.values()) o.setVisible(false);
  const cc = getClip(c.rig, clip);
  const a = qa.auditClip(c, clip);
  const tr = trace(c, clip, cc.duration);
  const fl = a.floor, mm = (v) => (v === undefined ? null : Math.round(Math.min(0, v.min) * -1000));
  const body = a.intersections.filter((x) => !x.blade), blade = a.intersections.filter((x) => x.blade);
  const swings = a.tip || [];
  const row = {
    clip: clipName, dur: a.duration, loop: !!a.loop, nan: a.nan ? 1 : 0,
    drift: r(a.feet.maxDrift * 100, 1), skid: r(a.feet.maxSkid * 100, 1), plants: a.feet.plants.length,
    floorFeet: mm(fl.feet), floorBlade: mm(fl.blade), floorBody: Math.max(mm(fl.hands) || 0, mm(fl.knees) || 0, mm(fl.pommel) || 0),
    limits: a.limits.length, limitWorst: a.limits[0] ? a.limits[0].joint + '.' + a.limits[0].axis + ' +' + a.limits[0].over + '@' + a.limits[0].t : '',
    isect: body.length, isectWorst: body[0] ? body[0].pair + ' ' + r(body[0].depth * 100, 1) + 'cm@' + body[0].t : '',
    blade: blade.length, bladeWorst: blade[0] ? blade[0].pair + ' ' + r(blade[0].depth * 100, 1) + 'cm@' + blade[0].t : '',
    clear: r(tr.clear.min * 100, 1), clearAt: tr.clear.part + '@' + tr.clear.t,
    pops: a.angular.pops.length, popWorst: a.angular.pops[0] ? a.angular.pops[0].bone + ' ' + a.angular.pops[0].step + '@' + a.angular.pops[0].t : '',
    over: a.angular.over.length, overWorst: a.angular.over[0] ? a.angular.over[0].bone + ' ' + a.angular.over[0].maxW : '',
    unsup: r(a.balance.unsupportedFrac, 2), comOut: r(a.balance.maxOutside * 100, 1),
    aim: Math.max(a.aim.R.max, a.aim.L.max), aim30: r(a.aim.R.over30 + a.aim.L.over30, 3),
    tipPeak: r(Math.max(0, ...swings.map((s) => s.peak)), 1), kinks: swings.reduce((n, s) => n + s.kinks, 0), straight: r(Math.max(0, ...swings.map((s) => s.straight)), 2),
    keyBreaks: Array.isArray(a.keys) ? a.keys.length : (a.keys && a.keys.breaks ? a.keys.breaks.length : 0),
    rootEnd: a.rootEnd[0],
  };
  return row;
}

function audit(id, names) {
  const out = [];
  for (const n of names) { try { out.push(auditRow(id, n)); } catch (e) { out.push({ clip: n, error: String((e && e.message) || e) }); } }
  return out;
}

const COLS = [['clip', 30], ['dur', 5], ['drift', 6], ['skid', 5], ['floorFeet', 5], ['floorBlade', 5], ['floorBody', 5], ['limits', 4], ['isect', 4], ['blade', 4], ['clear', 6], ['pops', 4], ['over', 4], ['unsup', 5], ['comOut', 6], ['aim', 5], ['tipPeak', 6], ['kinks', 4]];
const HEADS = { clip: 'clip', dur: 'dur', drift: 'drift', skid: 'skid', floorFeet: 'flFt', floorBlade: 'flBl', floorBody: 'flBd', limits: 'lim', isect: 'isx', blade: 'bld', clear: 'clear', pops: 'pop', over: 'ovr', unsup: 'unsup', comOut: 'comOut', aim: 'aim', tipPeak: 'tip', kinks: 'knk' };
/** Fixed-width text table of audit rows (units: cm for drift / skid / clear / comOut, mm for floor*, deg for aim, m/s tip). */
function table(rows) {
  const pad = (s, n, left) => { s = String(s ?? ''); return left ? s.padEnd(n) : s.padStart(n); };
  const lines = [COLS.map(([k, n], i) => pad(HEADS[k], n, i === 0)).join(' ')];
  for (const row of rows) {
    if (row.error) { lines.push(pad(row.clip, 30, true) + ' ERROR ' + row.error); continue; }
    lines.push(COLS.map(([k, n], i) => pad(row[k], n, i === 0)).join(' '));
  }
  return lines.join('\n');
}
function auditLine(row) {
  if (!row || row.error) return row ? 'audit error: ' + row.error : '';
  return `drift ${row.drift}cm skid ${row.skid}cm | floor feet ${row.floorFeet} blade ${row.floorBlade} body ${row.floorBody} mm | limits ${row.limits} ${row.limitWorst} | isect ${row.isect} blade ${row.blade} clear ${row.clear}cm ${row.clearAt} | pops ${row.pops} | unsup ${row.unsup} | aim ${row.aim}`;
}

createLab({
  view: { target: [0, 1.05, 0], dist: 6, yaw: 0, pitch: 4, fov: 40 },
  setup(ctx, lab) {
    CTX = ctx; LAB = lab;
    // a mid-grey studio: dark robes and black lacquer must read as silhouettes
    ctx.scene.background = new THREE.Color(0x6a7180);
    ctx.scene.fog = null;
    lab.floor.material.color.set(0x8a8f99);
    lab.lights.hemi.intensity = 1.5;
    lab.lights.key.intensity = 2.8;
    lab.lights.rim.intensity = 2.0;
    const cv = document.createElement('canvas');
    cv.style.cssText = 'position:fixed;left:0;top:0;z-index:1000;display:none;image-rendering:auto';
    document.body.appendChild(cv);
    lab.sheetCanvas = cv;
    // live playback for the interactive page (the sheet path steps the character itself)
    lab.live = null;
    ctx.onUpdate((dg, dr) => {
      const c = lab.live;
      if (!c) return;
      c.update(dg, dr);
      c.root.position.x += c.rootDelta.f * c.facing;
      if (c.finished && lab.liveLoop) { c.root.position.x = 0; c.play(c.clip, { fade: 0, restart: true }); }
    }, ctx.ORDER.CHAR);
    window.__ED.motion = { sheet, audit, auditRow, table, clips, actor, heroes: Object.keys(HEROES), qa, defineClip, definePose, invalidateClips, listClips, hasClip, getClipDef, GENERIC, twinVariant, VIEWS };
  },
  scenarios: {
    /** One contact sheet, left on screen for a screenshot: __ED.lab.play('sheet', 'kael', 'kael.light1', { frames: 10 }). */
    sheet(ctx, lab, id, clip, opts) { return sheet(id, clip, opts).meta; },
    /** Audit rows of a list of clips (or a group name): __ED.lab.play('audit', 'iska', 'moves'). */
    audit(ctx, lab, id, names) { const rows = audit(id, Array.isArray(names) ? names : clips(id, names || 'all')); return { rows, table: table(rows) }; },
    /** Play a clip live (interactive page): __ED.lab.play('clip', 'vorn', 'vorn.idle'). */
    clip(ctx, lab, id, name, body = 'design') {
      lab.sheetCanvas.style.display = 'none';
      for (const o of cast.values()) o.setVisible(false);
      const c = actor(id, body);
      c.setVisible(true);
      qa.resetForQA(c, clipFor(c, name));
      lab.live = c; lab.liveLoop = true;
      return name;
    },
    list(ctx, lab, id, group) { return clips(id, group); },
  },
});
