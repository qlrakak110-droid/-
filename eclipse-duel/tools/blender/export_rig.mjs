// Rig export for the Blender asset pipeline: runs the real character runtime headless in Node and writes everything a
// DCC needs to know about a hero's rig to tools/blender/rigs/<hero>.json.
//
//   node tools/blender/export_rig.mjs                     kael, iska, vorn and the pilot
//   node tools/blender/export_rig.mjs vorn pilot          some of them
//   node tools/blender/export_rig.mjs myhero --design src/fighters/x/design.js#x [--clips src/fighters/x/clips/index.js]
//   flags: --poses "vorn.idle@0,vorn.walkF@0.3"   extra sampled poses (name@seconds)      --no-poses
//          --out dir                              output directory (default tools/blender/rigs)
//
// What is exported (game space: metres, +X forward, +Y up, +Z the fighter's right; matrices column-major 4x4):
//   bones[]     every bone of the rig the design produces, parents first: name, parent, side, kind, deform, auto,
//               head / tail (bind space), matrix (bind, model space), zero (zero-pose model matrix), offset / restRot /
//               bindRot (local), length
//   sockets, weapons (grip frames, grip points, base / tip, measured extent of the current weapon geometry),
//   colliders (capsules: bone + offset and bind-space end points), springs, cloth (panel grids: cols, rows, rest
//   positions, anchor bones, bone prefix), proportions, landmark heights, materials (slot names), poses (sampled clips)
// The design module is bundled with esbuild first, so designs that import embedded assets (assets/chars/<hero>/index.js)
// export too; an asset that does not exist yet is replaced by an empty stub (bootstrap of a new hero).

import { build } from 'esbuild';
import fs from 'node:fs';
import path from 'node:path';
import url from 'node:url';

const ROOT = path.resolve(path.dirname(url.fileURLToPath(import.meta.url)), '../..');
const argv = process.argv.slice(2);
const VALUE = new Set(['design', 'clips', 'poses', 'out']);
const pos = [], o = {};
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a.startsWith('--')) { const k = a.slice(2); if (VALUE.has(k)) o[k] = argv[++i]; else o[k] = true; } else pos.push(a);
}

/** Known heroes: design module (#export), clip registry, default poses. */
const HEROES = {
  kael: { design: 'src/fighters/kael/design.js#default', clips: 'src/fighters/kael/clips/index.js' },
  iska: { design: 'src/fighters/iska/design.js#default', clips: 'src/fighters/iska/clips/index.js' },
  vorn: { design: 'src/fighters/vorn/design.js#default', clips: 'src/fighters/vorn/clips/index.js' },
  pilot: { design: 'src/char/asset_pilot.js#pilot', clips: 'src/fighters/vorn/clips/index.js', prefix: 'vorn' },
};
const names = pos.length ? pos : Object.keys(HEROES).filter((h) => fs.existsSync(path.join(ROOT, HEROES[h].design.split('#')[0])));
const outDir = path.resolve(ROOT, o.out || 'tools/blender/rigs');
fs.mkdirSync(outDir, { recursive: true });

const r5 = (x) => Math.round(x * 1e5) / 1e5;
const arr = (a) => Array.from(a, r5);

/** Bundle the runtime + one design (+ clips) for Node and import it. */
async function load(hero, spec) {
  const [file, exp = 'default'] = spec.design.split('#');
  const entry = [
    `export { createCharacter, listClips } from ${JSON.stringify(path.join(ROOT, 'src/char/index.js'))};`,
    `export { createRig, bindMatrices, fk, HELPER_NAMES, bodyScale } from ${JSON.stringify(path.join(ROOT, 'src/char/skeleton.js'))};`,
    `export { clothLayout } from ${JSON.stringify(path.join(ROOT, 'src/char/cloth.js'))};`,
    `export { getClipDef } from ${JSON.stringify(path.join(ROOT, 'src/char/anim.js'))};`,
    `import * as D from ${JSON.stringify(path.join(ROOT, file))};`,
    spec.clips && fs.existsSync(path.join(ROOT, spec.clips)) ? `import ${JSON.stringify(path.join(ROOT, spec.clips))};` : '',
    `export const design = D[${JSON.stringify(exp)}];`,
  ].join('\n');
  const stubAssets = {
    name: 'stub-missing-assets',
    setup(b) {
      b.onResolve({ filter: /assets\/chars\/[^/]+\/index\.js$/ }, (args) => {
        const p = path.resolve(args.resolveDir, args.path);
        return fs.existsSync(p) ? null : { path: p, namespace: 'missing-asset' };
      });
      b.onLoad({ filter: /.*/, namespace: 'missing-asset' }, () => ({ contents: 'export default null;', loader: 'js' }));
    },
  };
  const res = await build({
    absWorkingDir: ROOT, stdin: { contents: entry, resolveDir: ROOT, loader: 'js' }, bundle: true, format: 'esm', platform: 'node',
    write: false, loader: { '.glsl': 'text', '.css': 'text', '.svg': 'text', '.txt': 'text', '.edm': 'binary' },
    define: { __DEV__: 'false', __TARGET__: JSON.stringify('rig') }, plugins: [stubAssets], logLevel: 'warning',
  });
  const tmp = path.join(ROOT, 'build', `_rig_${hero}_${process.pid}.mjs`);
  fs.mkdirSync(path.dirname(tmp), { recursive: true });
  fs.writeFileSync(tmp, res.outputFiles[0].text);
  try { return await import(url.pathToFileURL(tmp).href); } finally { fs.unlinkSync(tmp); }
}

/** p' = M * [x, y, z, 1] for a column-major 4x4 at offset o. */
function mulPoint(m, o, p) {
  return [m[o] * p[0] + m[o + 4] * p[1] + m[o + 8] * p[2] + m[o + 12], m[o + 1] * p[0] + m[o + 5] * p[1] + m[o + 9] * p[2] + m[o + 13], m[o + 2] * p[0] + m[o + 6] * p[1] + m[o + 10] * p[2] + m[o + 14]];
}
function mulDir(m, o, p) {
  return [m[o] * p[0] + m[o + 4] * p[1] + m[o + 8] * p[2], m[o + 1] * p[0] + m[o + 5] * p[1] + m[o + 9] * p[2], m[o + 2] * p[0] + m[o + 6] * p[1] + m[o + 10] * p[2]];
}
/** Inverse of a rigid (rotation + translation) column-major matrix applied to a point. */
function invPoint(m, o, p) {
  const d = [p[0] - m[o + 12], p[1] - m[o + 13], p[2] - m[o + 14]];
  return [m[o] * d[0] + m[o + 1] * d[1] + m[o + 2] * d[2], m[o + 4] * d[0] + m[o + 5] * d[1] + m[o + 6] * d[2], m[o + 8] * d[0] + m[o + 9] * d[1] + m[o + 10] * d[2]];
}

async function exportHero(hero) {
  const spec = { ...(HEROES[hero] || {}) };
  if (o.design) spec.design = o.design;
  if (o.clips) spec.clips = o.clips;
  if (!spec.design) throw new Error(`unknown hero ${hero}: pass --design file.js#export`);
  const warn = console.warn, info = console.info;
  console.warn = () => {}; console.info = () => {};
  const R = await load(hero, spec);
  const design0 = R.design;
  if (!design0) throw new Error(`${spec.design}: export not found`);
  const quality = { tier: 'high', cloth: 1 };
  const char = R.createCharacter({ quality, scene: null }, design0, { parent: null, name: 'export' });
  console.warn = warn; console.info = info;
  const rig = char.rig, design = char.design, N = rig.count, P = rig.P, K = rig.k;
  const bind = R.bindMatrices(rig);
  // zero pose (every authored rotation 0): locals = rest rotations
  const zq = new Float32Array(N * 4), zp = new Float32Array(N * 3);
  R.fk(rig, rig.restRot, rig.offset, zq, zp);

  // ---- bone classification ----------------------------------------------------------------------------------------
  const extra = new Map((design.bones || []).map((b) => [b.name, b]));
  const springOf = new Map();
  (design.springs || []).forEach((s, k) => s.bones.forEach((b, i) => springOf.set(b, { chain: k, i, n: s.bones.length })));
  // cloth panels: recomputed exactly as createCharacter does (the layout carries the anchors and the particle frames)
  const rig0 = R.createRig(design.proportions, design.bones || [], { gripAngle: design.gripAngle });
  const bind0 = R.bindMatrices(rig0);
  const anchorPos = (bone, off) => mulPoint(bind0.matrices, rig0.index[bone] * 16, off);
  const layouts = (design.cloth || []).map((s) => R.clothLayout(s, quality.cloth, anchorPos, (n) => rig0.index[n]));
  const clothOf = new Map();
  layouts.forEach((L, k) => L.bones.forEach((b, i) => clothOf.set(b.name, { panel: k, i: i % L.C, j: Math.floor(i / L.C) })));
  const children = Array.from({ length: N }, () => []);
  for (let i = 0; i < N; i++) if (rig.parent[i] >= 0) children[rig.parent[i]].push(i);
  const kindOf = (name, i) => {
    if (clothOf.has(name)) return 'cloth';
    if (springOf.has(name)) return 'spring';
    if (rig.helper[i]) return 'helper';
    if (/^weapon[RL]$/.test(name)) return 'weapon';
    if (/^(fingers|fingerTips|thumb)[RL]$/.test(name)) return 'finger';
    if (extra.has(name)) return extra.get(name).follow ? 'follow' : 'extra';
    return 'core';
  };
  const headOf = (i) => [bind.mp[i * 3], bind.mp[i * 3 + 1], bind.mp[i * 3 + 2]];
  const bindPt = (i, p) => mulPoint(bind.matrices, i * 16, p);
  const kh = P.hand / 0.085;
  /** Tail of a bone in bind space: where the limb segment it stands for ends (Blender bone-heat and display). */
  const tailOf = (name, i) => {
    const ix = (n) => rig.index[n], s = name.slice(-1), base = name.replace(/[RL]$/, '');
    const to = (n) => headOf(ix(n));
    switch (/[RL]$/.test(name) ? base : name) {
      case 'hips': return to('spine');
      case 'spine': return to('chest');
      case 'chest': return to('neck');
      case 'neck': return to('head');
      case 'head': return bindPt(i, [0, 0.215 * K, 0]);
      case 'shoulder': return to('upperArm' + s);
      case 'upperArm': return to('foreArm' + s);
      case 'foreArm': return to('hand' + s);
      case 'hand': return to('fingers' + s);
      case 'fingers': return to('fingerTips' + s);
      case 'fingerTips': return bindPt(i, [0, -0.052 * kh, 0]);
      case 'thumb': return bindPt(i, [0.03 * kh, -0.05 * kh, 0]);
      case 'weapon': return bindPt(i, [0.2, 0, 0]);
      case 'thigh': return to('shin' + s);
      case 'shin': return to('foot' + s);
      case 'foot': return to('toe' + s);
      case 'toe': return bindPt(i, [P.toeLength, 0, 0]);
      case 'deltoid': return bindPt(ix('upperArm' + s), [0, -0.1 * K, 0]);
      case 'upperArmTwist': return bindPt(ix('upperArm' + s), [0, -P.upperArm * 0.5, 0]);
      case 'elbow': case 'elbowVol': return bindPt(i, [0, -0.05 * K, 0]);
      case 'foreArmTwist': return to('hand' + s);
      case 'knee': case 'kneeVol': return bindPt(i, [0, -0.06 * K, 0]);
      case 'hipJoint': return bindPt(ix('thigh' + s), [0, -0.12 * K, 0]);
      case 'thighTwist': return bindPt(ix('thigh' + s), [0, -rig.lengths.thigh * 0.45, 0]);
      default: break;
    }
    if (clothOf.has(name)) return bindPt(i, [0, -0.03, 0]);
    const sp = springOf.get(name);
    if (children[i].length) return headOf(children[i][0]);
    if (sp) return bindPt(i, design.springs[sp.chain].tip || [0, -0.1, 0]);
    return bindPt(i, [0, -0.08 * K, 0]);
  };
  const bones = rig.names.map((name, i) => {
    const head = headOf(i), tail = tailOf(name, i), kind = kindOf(name, i);
    const b = {
      name, parent: rig.parent[i] >= 0 ? rig.names[rig.parent[i]] : null, side: rig.side[i], kind,
      deform: true,                                               // every rig bone may carry skin weights
      auto: kind === 'core' || kind === 'finger',                 // part of the default bone-heat set (the anatomical chain)
      head: arr(head), tail: arr(tail), length: r5(Math.hypot(tail[0] - head[0], tail[1] - head[1], tail[2] - head[2])),
      matrix: arr(bind.matrices.subarray(i * 16, i * 16 + 16)),
      zero: arr(compose(zq, i * 4, zp, i * 3)),
      offset: arr(rig.offset.subarray(i * 3, i * 3 + 3)), restRot: arr(rig.restRot.subarray(i * 4, i * 4 + 4)), bindRot: arr(rig.bindLocal.subarray(i * 4, i * 4 + 4)),
    };
    if (kind === 'cloth') b.cloth = clothOf.get(name);
    if (kind === 'spring') b.spring = springOf.get(name);
    if (kind === 'follow') b.follow = extra.get(name).follow;
    return b;
  });

  // ---- sockets, weapons, colliders, springs, cloth -----------------------------------------------------------------
  const sockets = {};
  for (const [name, obj] of Object.entries(char.sockets)) {
    const bone = obj.parent.name, off = obj.position.toArray();
    sockets[name] = { bone, offset: arr(off), bind: arr(bindPt(rig.index[bone], off)), zero: arr(mulPoint(compose(zq, rig.index[bone] * 4, zp, rig.index[bone] * 3), 0, off)) };
  }
  const weaponList = design.weapons || (design.weapon ? [design.weapon] : []);
  const weapons = weaponList.map((w, k) => {
    const bone = 'weapon' + (w.hand || 'R'), bi = rig.index[bone];
    // extent of the current weapon geometry in the weapon-bone frame (vertices bound 100% to the weapon bone)
    const lo = [1e9, 1e9, 1e9], hi = [-1e9, -1e9, -1e9];
    let count = 0;
    for (const mesh of Object.values(char.meshes)) {
      const g = mesh.geometry, Pp = g.attributes.position.array, SI = g.attributes.skinIndex.array, SW = g.attributes.skinWeight.array;
      for (let v = 0; v < Pp.length / 3; v++) {
        if (SI[v * 4] !== bi || SW[v * 4] < 0.999) continue;
        const q = invPoint(bind.matrices, bi * 16, [Pp[v * 3], Pp[v * 3 + 1], Pp[v * 3 + 2]]);
        for (let a = 0; a < 3; a++) { lo[a] = Math.min(lo[a], q[a]); hi[a] = Math.max(hi[a], q[a]); }
        count++;
      }
    }
    const grips = {};
    for (const [n, g] of Object.entries(w.grips || {})) grips[n] = { pos: arr(g.pos || [0, 0, 0]), rot: arr(g.rot || [0, 0, 0]), bind: arr(bindPt(bi, g.pos || [0, 0, 0])) };
    return {
      name: w.name || bone, hand: w.hand || 'R', bone, slot: w.slot || 'blade', socketSuffix: k === 0 ? '' : String(k + 1),
      base: arr(w.base || [0.1, 0, 0]), tip: arr(w.tip || [1, 0, 0]), grips,
      frame: arr(bind.matrices.subarray(bi * 16, bi * 16 + 16)),   // weapon-bone bind matrix: +X grip axis toward the tip, -Y true edge, +-Z flats
      extent: count ? { min: arr(lo), max: arr(hi), vertices: count } : null,
    };
  });
  const colliders = (design.colliders || []).map((c) => ({
    name: c.name || '', r: r5(c.r),
    a: { bone: c.a[0], offset: arr(c.a[1] || [0, 0, 0]), bind: arr(bindPt(rig.index[c.a[0]], c.a[1] || [0, 0, 0])) },
    b: { bone: c.b[0], offset: arr(c.b[1] || [0, 0, 0]), bind: arr(bindPt(rig.index[c.b[0]], c.b[1] || [0, 0, 0])) },
  }));
  const springs = (design.springs || []).map((s) => ({ ...s, tipBind: arr(bindPt(rig.index[s.bones[s.bones.length - 1]], s.tip || [0, -0.1, 0])) }));
  const cloth = layouts.map((L) => {
    const s = L.spec, plain = {};
    for (const [k, v] of Object.entries(s)) if (typeof v !== 'function' && k !== 'surface') plain[k] = v;
    return {
      ...plain, cols: L.C, rows: L.R, pinRows: L.pinRows, bonePrefix: s.name + '_',   // bone of particle (i, j): `${name}_${i}_${j}`, i across (left -> right), j down
      anchorBones: Array.from(L.anchorBone, (b) => rig0.names[b]),
      rest: arr(L.rest),                                              // cols * rows * 3, row-major (j * cols + i), bind space
      frames: arr(L.frames),                                          // particle rest quaternions (X = surface normal, Y = up the cloth, Z = across)
    };
  });

  // ---- sampled poses (model-space bone matrices of animated bones; cloth particles are simulated, not exported) ------
  const poses = {};
  if (!o['no-poses']) {
    const clips = new Set(R.listClips());
    const prefix = spec.prefix || hero;
    const wanted = [];
    if (o.poses) for (const p of String(o.poses).split(',')) { const [n, t] = p.split('@'); wanted.push([n.replace(/\W+/g, '_') + '_' + (t || 0), n, Number(t || 0)]); }
    else {
      if (clips.has(prefix + '.idle')) wanted.push(['idle', prefix + '.idle', 0]);
      if (clips.has(prefix + '.walkF')) wanted.push(['walk', prefix + '.walkF', 0.3], ['walk2', prefix + '.walkF', 0.75]);
      if (clips.has(prefix + '.guard')) wanted.push(['guard', prefix + '.guard', 0.3]);
      // the first move clips with an impact marker: wind-up and impact frames
      let found = 0;
      for (const n of clips) {
        if (!n.startsWith(prefix + '.') || found >= 2) continue;
        const d = R.getClipDef(n), e = d && (d.events || []).find((x) => x.name === 'impact' || x.name === 'hit');
        if (!e) continue;
        wanted.push([`attack${found + 1}_windup`, n, Math.max(0, e.t * 0.5)], [`attack${found + 1}_impact`, n, e.t]);
        found++;
      }
    }
    const animBones = bones.filter((b) => b.kind !== 'cloth').map((b) => b.name);
    for (const [key, clip, t] of wanted) {
      if (!clips.has(clip)) { console.warn(`  pose ${key}: no clip ${clip}`); continue; }
      char.root.position.set(0, 0, 0); char.setFacing(1);
      char.play(clip, { fade: 0, restart: true });
      char.update(0, 0); char.teleport();
      for (let f = 0, n = Math.round(t * 60); f < n; f++) char.update(1 / 60, 1 / 60);
      char.update(0, 0);
      char.root.updateMatrixWorld(true);
      const m = {};
      for (const n of animBones) m[n] = arr(char.bones[n].matrixWorld.elements);
      poses[key] = { clip, time: t, bones: m };
    }
  }

  const heights = {};
  for (const n of ['hips', 'spine', 'chest', 'neck', 'head', 'upperArmR', 'foreArmR', 'handR', 'weaponR', 'thighR', 'shinR', 'footR', 'toeR']) heights[n] = arr([zp[rig.index[n] * 3], zp[rig.index[n] * 3 + 1], zp[rig.index[n] * 3 + 2]]);
  const out = {
    format: 'ed-rig/1', hero, design: spec.design, designId: design.id || hero,
    axes: {
      units: 'metres', forward: '+X', up: '+Y', right: '+Z (the fighter\'s right hand, the camera side)',
      matrices: 'column-major 4x4, model (fighter-local) space, bind pose unless noted',
      blender: 'edlib converts once: blender (x, y, z) = game (-z, -x, y); game (x, y, z) = blender (-y, z, -x). In Blender the hero faces -Y, Z is up, the right hand is at -X',
      bind: 'A-pose the meshes are authored in (arms 28 deg abducted, 8 deg forward, elbows 14 deg; thighs 3 deg out)',
      zero: 'every authored rotation 0: limbs hang straight down, bone frames parallel to the model axes',
    },
    scale: design.scale ?? 1, bodyScale: r5(K), gripAngle: design.gripAngle ?? 0,
    proportions: Object.fromEntries(Object.entries(P).map(([k, v]) => [k, r5(v)])),
    lengths: Object.fromEntries(Object.entries(rig.lengths).map(([k, v]) => [k, r5(v)])),
    zeroPose: heights,
    stats: char.stats, materials: Object.keys(design.materials || {}),
    bones, sockets, weapons, colliders, springs, cloth, poses,
  };
  char.dispose?.();
  const file = path.join(outDir, hero + '.json');
  fs.writeFileSync(file, JSON.stringify(out));
  const kinds = {};
  for (const b of bones) kinds[b.kind] = (kinds[b.kind] || 0) + 1;
  console.log(`${path.relative(ROOT, file)}  ${(fs.statSync(file).size / 1024).toFixed(0)} KB  bones ${N} ${JSON.stringify(kinds)}  cloth ${cloth.map((c) => `${c.name} ${c.cols}x${c.rows}`).join(', ') || '-'}  poses ${Object.keys(poses).join(', ') || '-'}`);
}

/** Column-major rigid matrix from a quaternion (array + offset) and a position. */
function compose(q, qo, p, po) {
  const x = q[qo], y = q[qo + 1], z = q[qo + 2], w = q[qo + 3];
  const x2 = x + x, y2 = y + y, z2 = z + z, xx = x * x2, xy = x * y2, xz = x * z2, yy = y * y2, yz = y * z2, zz = z * z2, wx = w * x2, wy = w * y2, wz = w * z2;
  return [1 - (yy + zz), xy + wz, xz - wy, 0, xy - wz, 1 - (xx + zz), yz + wx, 0, xz + wy, yz - wx, 1 - (xx + yy), 0, p[po], p[po + 1], p[po + 2], 1];
}

for (const h of names) {
  try { await exportHero(h); } catch (e) { console.error(`rig export ${h} failed:`, e.stack || e); process.exitCode = 1; }
}
