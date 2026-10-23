// node render.js <scene.json> <outDir>: renders parts with the studio's Render3D (same as bprev/preview.js)
// scene = { parts: [{shape, size:[x,y,z], cf:[12], col:[r,g,b] (0..1), mat, t}], lights: [{part, cls, c, b, range, face, angle}],
//           cams: [{name, eye, at, fov, w, h}], clock }
const { chromium } = require('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/harness/node_modules/playwright');
const fs = require('fs');
const SP = '/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev';
const scene = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const outDir = process.argv[3];
fs.mkdirSync(outDir, { recursive: true });
const SHAPE = { Block: 0, Wedge: 1, CornerWedge: 2, Cylinder: 3, Ball: 4 };
const rgbInt = (c) => ((Math.round(c[0] * 255) & 255) << 16) | ((Math.round(c[1] * 255) & 255) << 8) | (Math.round(c[2] * 255) & 255);
const materials = []; const matIdx = {};
const mi = (m) => { if (matIdx[m] === undefined) { matIdx[m] = materials.length; materials.push(m); } return matIdx[m]; };
const rows = [], ids = [];
scene.parts.forEach((p, i) => {
  const cf = p.cf, s = p.size;
  rows.push([SHAPE[p.shape] || 0, s[0], s[1], s[2], cf[0], cf[1], cf[2], cf[3], cf[4], cf[5], cf[6], cf[7], cf[8], cf[9], cf[10], cf[11], rgbInt(p.col), mi(p.mat || 'Plastic'), p.t || 0, 0, 0]);
  ids.push(1000 + i);
});
const lighting = JSON.parse(fs.readFileSync(`${SP}/lighting.json`, 'utf8'));
lighting.ClockTime = scene.clock == null ? 14 : scene.clock;
const lights = (scene.lights || []).map((L, i) => ({ id: i + 1, className: L.cls || 'PointLight', part: 1000 + L.part, face: L.face || 'Top', color: rgbInt(L.c), brightness: L.b, range: L.range, angle: L.angle || 90, enabled: true }));
(async () => {
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const p = await b.newPage({ viewport: { width: 1280, height: 720 } });
  p.on('pageerror', (e) => console.log('[pageerror]', e.message));
  await p.goto('file://' + SP + '/preview.html');
  const r = await p.evaluate((sc) => window.PREVIEW(sc), { rows, materials, ids, signs: [], lights, lighting, quality: 'high' });
  console.log(r, 'lights', lights.length);
  for (const cam of scene.cams) {
    await p.evaluate(([c, k]) => window.SHOT(c, k), [cam, lighting.ClockTime]);
    await p.screenshot({ path: `${outDir}/${cam.name}.png`, timeout: 300000 });
    console.log('shot', `${outDir}/${cam.name}.png`);
  }
  await b.close();
})().catch((e) => { console.log('[render error]', e && e.message); process.exit(1); });
