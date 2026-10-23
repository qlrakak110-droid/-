// [reskin copy: --scene <file> (default feat/reskin/fx/<key>.scene.json), gen/out default under feat/reskin]
// node preview.js <key> [--gen gen.json] [--cams cams.json] [--out dir] [--clock 14] [--night] [--only name,name]
// Renders fx/<key>.scene.json (+ generated parts from the Luau sim) with the studio's own Render3D + RblxGfx.
const { chromium } = require('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/harness/node_modules/playwright');
const fs = require('fs');
const path = require('path');
const SP = '/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev';
const argv = process.argv.slice(2);
const key = argv[0];
const opt = (n, d) => { const i = argv.indexOf('--' + n); return i >= 0 ? argv[i + 1] : d; };
const flag = (n) => argv.includes('--' + n);
const RS = '/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/reskin';
const scene = JSON.parse(fs.readFileSync(opt('scene', `${RS}/fx/${key}.scene.json`), 'utf8'));
const genFile = opt('gen', `${RS}/out/${key}.gen.json`);
const gen = fs.existsSync(genFile) && !flag('base') ? JSON.parse(fs.readFileSync(genFile, 'utf8')) : null;
const outDir = opt('out', `${RS}/shots/${key}${gen ? '' : '_base'}`);
const clock = +opt('clock', flag('night') ? 21 : 14);
fs.mkdirSync(outDir, { recursive: true });
const lighting = JSON.parse(fs.readFileSync(`${SP}/lighting.json`, 'utf8'));
lighting.ClockTime = clock;

const SHAPE = { Block: 0, Wedge: 1, CornerWedge: 2, Cylinder: 3, Ball: 4 };
const MESH = { Sphere: 5, Cylinder: 3, Wedge: 1, Brick: 0, Head: 3, Torso: 0, FileMesh: 0, CylinderMesh: 3 };
const rgbInt = (c) => ((Math.round(c[0] * 255) & 255) << 16) | ((Math.round(c[1] * 255) & 255) << 8) | (Math.round(c[2] * 255) & 255);
const materials = []; const matIdx = {};
const mi = (m) => { if (matIdx[m] === undefined) { matIdx[m] = materials.length; materials.push(m); } return matIdx[m]; };
const rows = [], ids = [], rowOf = new Map();
const hidden = new Set(gen ? gen.hidden || [] : []);
function addPart(p) {
  if (hidden.has(p.id)) return;
  let shape = p.cls === 'WedgePart' ? 1 : p.cls === 'CornerWedgePart' ? 2 : SHAPE[p.shape] !== undefined ? SHAPE[p.shape] : 0;
  if (p.mesh && MESH[p.mesh.type] !== undefined) shape = MESH[p.mesh.type];
  const cf = p.cf, s = p.size;
  const t = p.t || 0;
  rowOf.set(p.id, rows.length);
  rows.push([shape, s[0], s[1], s[2], cf[0], cf[1], cf[2], cf[3], cf[4], cf[5], cf[6], cf[7], cf[8], cf[9], cf[10], cf[11], rgbInt(p.col), mi(p.mat || 'Plastic'), t, 0, 0]);
  ids.push(p.id);
}
for (const p of scene.parts) addPart(p);
if (gen) for (const p of gen.parts) addPart(p);
function stripRich(t) { return String(t).replace(/<[^>]+>/g, ''); }
function signOf(g) {
  const texts = []; let fg = null, bg = null;
  const walk = (n) => {
    for (const k of n.kids || []) {
      if ((k.cls === 'TextLabel' || k.cls === 'TextButton') && k.vis !== false) {
        const t = stripRich(k.text || '');
        if (t !== '') { texts.push(t); if (!fg) fg = k.tc; if (!bg && (k.bgT ?? 0) < 1) bg = k.bg; }
      } else if (k.cls === 'Frame' && !bg && k.vis !== false && (k.bgT ?? 0) < 1) bg = k.bg;
      walk(k);
    }
  };
  walk(g);
  return [texts.join('\n'), fg ? rgbInt(fg) : -1, bg ? rgbInt(bg) : -1];
}
const signs = [];
for (const g of scene.guis.concat(gen ? gen.guis || [] : [])) {
  const r = rowOf.get(g.part); if (r === undefined) continue;
  const [text, fg, bg] = signOf(g);
  if (!text && bg < 0) continue;
  signs.push([r, g.face || 'Front', text, fg, bg]);
}
const lights = [];
let lid = 1;
const night = flag('night');
for (const L of scene.lights.concat(gen ? gen.lights || [] : [])) {
  if (!rowOf.has(L.part)) continue;
  lights.push({ id: lid++, className: L.cls, part: L.part, face: L.face, color: rgbInt(L.c), brightness: L.b, range: L.range, angle: L.angle, enabled: night || !!L.on || !!L.gen });
}
// cameras
let cams = [];
const camFile = opt('cams');
if (camFile) cams = JSON.parse(fs.readFileSync(camFile, 'utf8'));
else if (gen && gen.cams && gen.cams.length) cams = gen.cams;
else if (scene.venue.floor || scene.venue.bounds) {
  const f = scene.venue.floor || Object.assign({}, scene.venue.bounds, { size: [scene.venue.bounds.size[0], 0, scene.venue.bounds.size[2]], cf: [scene.venue.bounds.cf[0], scene.venue.bounds.cf[1] - scene.venue.bounds.size[1] / 2].concat(scene.venue.bounds.cf.slice(2)) }), c = f.cf, W = f.size[0], D = f.size[2];
  const w = (x, y, z) => [c[0] + c[3] * x + c[4] * y + c[5] * z, c[1] + c[6] * x + c[7] * y + c[8] * z, c[2] + c[9] * x + c[10] * y + c[11] * z];
  const fy = f.size[1] / 2;
  cams = [
    { name: 'entry', eye: w(0, fy + 5.4, D / 2 - 1.2), at: w(0, fy + 3.6, -D / 2), fov: 74 },
    { name: 'back', eye: w(0, fy + 5.8, -D / 2 + 1.4), at: w(0, fy + 3.2, D / 2), fov: 74 },
    { name: 'cornerL', eye: w(W / 2 - 1.0, fy + 6.6, D / 2 - 1.0), at: w(-W / 4, fy + 2.4, -D / 4), fov: 74 },
    { name: 'cornerR', eye: w(-W / 2 + 1.0, fy + 6.6, D / 2 - 1.0), at: w(W / 4, fy + 2.4, -D / 4), fov: 74 },
  ];
}
// --lcams file.json: cameras in the VENUE frame ({name, eye:[x,y,z], at:[x,y,z], fov}; +Z = entrance, -Z = back wall, y = height above floor)
const lcf = opt('lcams');
if (lcf && gen && gen.vcf) {
  const c = gen.vcf;
  const w = (v) => [c[0] + c[3] * v[0] + c[4] * v[1] + c[5] * v[2], c[1] + c[6] * v[0] + c[7] * v[1] + c[8] * v[2], c[2] + c[9] * v[0] + c[10] * v[1] + c[11] * v[2]];
  cams = JSON.parse(fs.readFileSync(lcf, 'utf8')).map((k) => ({ name: k.name, eye: w(k.eye), at: w(k.at), fov: k.fov || 70 }));
}
const only = opt('only'); if (only) cams = cams.filter((c) => only.split(',').includes(c.name));
// global render queue: at most SLOTS chromium renders at once on this 4-core box (many agents render in parallel;
// oversubscription made every render 20x slower). A slot is a directory holding the owner pid; dead owners are reclaimed.
const SLOTS = +(process.env.RENDER_SLOTS || 3);
const LOCKS = SP + '/.render_slots';
fs.mkdirSync(LOCKS, { recursive: true });
let mySlot = null;
function alive(pid) { try { process.kill(pid, 0); return true; } catch (e) { return false; } }
async function acquire() {
  const t0 = Date.now();
  for (;;) {
    for (let i = 0; i < SLOTS; i++) {
      const d = `${LOCKS}/slot${i}`;
      try { fs.mkdirSync(d); fs.writeFileSync(`${d}/pid`, String(process.pid)); mySlot = d; return Date.now() - t0; } catch (e) {
        try { const pid = +fs.readFileSync(`${d}/pid`, 'utf8'); if (pid && !alive(pid)) { fs.rmSync(d, { recursive: true, force: true }); } } catch (e2) {
          try { const st = fs.statSync(d); if (Date.now() - st.mtimeMs > 20000) fs.rmSync(d, { recursive: true, force: true }); } catch (e3) {}
        }
      }
    }
    await new Promise((r) => setTimeout(r, 400));
  }
}
function release() { if (mySlot) { try { fs.rmSync(mySlot, { recursive: true, force: true }); } catch (e) {} mySlot = null; } }
process.on('exit', release);
process.on('SIGINT', () => { release(); process.exit(130); });
process.on('SIGTERM', () => { release(); process.exit(143); });
(async () => {
  const waited = await acquire();
  if (waited > 1500) console.log('queued', Math.round(waited / 1000) + 's');
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const VW = +(process.env.PREVIEW_W || 960); const p = await b.newPage({ viewport: { width: VW, height: Math.round(VW * 9 / 16) } });
  p.on('pageerror', (e) => console.log('[pageerror]', e.message));
  p.on('console', (m) => { const t = m.text(); if (/error|Error|warn/i.test(t)) console.log('[c]', t.slice(0, 300)); });
  await p.goto('file://' + SP + '/preview.html');
  const r = await p.evaluate((sc) => window.PREVIEW(sc), { rows, materials, ids, signs, lights, lighting, quality: opt('q', 'high') });
  console.log(r, 'signs', signs.length, 'lights', lights.length, 'hidden', hidden.size, 'gen', gen ? gen.parts.length : 0);
  for (const cam of cams) {
    await p.evaluate(([c, k]) => window.SHOT(c, k), [cam, clock]);
    const t0 = Date.now(); await p.screenshot({ path: `${outDir}/${cam.name}.png`, timeout: 300000 }); console.log('ms', Date.now() - t0);
    console.log('shot', `${outDir}/${cam.name}.png`);
  }
  await b.close();
  release();
})().catch((e) => { console.log('[preview error]', e && e.message); release(); process.exit(1); });
