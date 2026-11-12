// Headless capture harness (Chromium + SwiftShader). Builds a target, loads it in deterministic test mode (#test: no
// rAF loop, time is advanced in fixed 1/60 s steps) and captures frames at exact simulation times.
//
//   node tools/shot.mjs <target> [options]
//     <target>             game | <lab name>  (labs: src/labs/<name>.js)
//     --do "<js>"          JS run in the page once it is ready (may be an async expression; __ED is the test API)
//     --at 0,0.1,0.25      simulation times in seconds AFTER --do at which to capture (default "0")
//     --each "<js>"        JS run before every capture
//     --out shots/name     output prefix -> shots/name_0.100.png (default shots/<target>)
//     --sheet [cols]       also write <out>_sheet.png: one contact sheet of all frames with time labels (use this to
//                          review a whole sequence with a single image); --sheet-only deletes the single frames
//     --sheet-width 480    width of each frame on the sheet
//     --size 1280x720      viewport (CSS px)
//     --view "tx,ty,tz,dist,yaw,pitch[,fov]"   lab camera
//     --hash "q=low&x=1"   extra URL flags
//     --touch              emulate a touch phone
//     --eval "<js>"        JS evaluated after the captures; the JSON result is printed
//     --scenario f.mjs     custom script: export default async ({ page, evalJs, advance, shot, log }) => {...}
//     --no-build           skip the build step,  --dev  unminified build
//     --realtime 3         instead of test mode: run the real rAF loop for N seconds, then capture once
//
// Page console errors / warnings and uncaught exceptions are printed (shader compile errors show up here).

import fs from 'node:fs';
import path from 'node:path';
import url from 'node:url';
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';

const ROOT = path.resolve(path.dirname(url.fileURLToPath(import.meta.url)), '..');
let chromium;
try { ({ chromium } = await import('playwright')); } catch (e) { ({ chromium } = createRequire('/opt/node-tools/node_modules/')('playwright')); }

const argv = process.argv.slice(2);
const target = argv[0] && !argv[0].startsWith('--') ? argv[0] : 'game';
const opt = (name, def) => { const i = argv.indexOf('--' + name); if (i < 0) return def; const v = argv[i + 1]; return v === undefined || v.startsWith('--') ? true : v; };
const has = (name) => argv.includes('--' + name);

if (!has('no-build')) execFileSync(process.execPath, [path.join(ROOT, 'tools/build.mjs'), target, ...(has('dev') ? ['--dev'] : [])], { stdio: 'inherit' });
const file = target === 'game' ? path.join(ROOT, 'dist/eclipse-duel.html') : path.join(ROOT, `build/${target}.html`);
const [W, H] = String(opt('size', '1280x720')).split('x').map(Number);
const out = path.resolve(ROOT, String(opt('out', 'shots/' + target)));
fs.mkdirSync(path.dirname(out), { recursive: true });
const realtime = opt('realtime', null);
const flags = [realtime ? '' : 'test', opt('view', null) ? 'view=' + opt('view') : '', opt('hash', '') === true ? '' : opt('hash', '')].filter(Boolean).join('&');

const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required'] });
const touch = has('touch');
const page = await browser.newPage({ viewport: { width: W, height: H }, hasTouch: touch, isMobile: touch, deviceScaleFactor: 1 });
page.setDefaultTimeout(120000);
let errors = 0;
page.on('console', (m) => {
  const t = m.type();
  if (t === 'error' || t === 'warning') { const s = m.text(); if (/GPU stall|GL Driver Message|Automatic fallback to software/.test(s)) return; errors += t === 'error' ? 1 : 0; console.log(`[page ${t}]`, s.slice(0, 1800)); }
  else if (has('verbose') || m.text().startsWith('[ed]')) console.log('[page]', m.text().slice(0, 1800));
});
page.on('pageerror', (e) => { errors++; console.log('[page exception]', String(e.stack || e.message).slice(0, 1800)); });

await page.goto('file://' + file + (flags ? '#' + flags : ''));
await page.waitForFunction(() => window.__ED && window.__ED.ready, null, { timeout: 120000 }).catch(() => { console.log('[harness] page never became ready (window.__ED.ready)'); });

const evalJs = (code) => page.evaluate(async (c) => { const r = await (0, eval)('(async () => { return (' + c + '\n); })()'); try { return r === undefined ? null : JSON.parse(JSON.stringify(r)); } catch (e) { return String(r); } }, code);
const evalStmt = (code) => page.evaluate(async (c) => { await (0, eval)('(async () => { ' + c + '\n })()'); }, code);
const run = async (code) => { try { return await evalJs(code); } catch (e) { if (/SyntaxError/.test(String(e))) return evalStmt(code); throw e; } };
const frames = [];
let simT = 0;
const advance = async (sec) => { if (sec > 1e-6) { await page.evaluate((s) => window.__ED.advance(s), sec); simT += sec; } };
const shot = async (label) => {
  if (!realtime) await page.evaluate(() => { window.__ED.render(); });
  await page.evaluate(() => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))));
  const p = `${out}_${label}.png`;
  await page.screenshot({ path: p });
  frames.push({ p, label });
  return p;
};
const log = (...a) => console.log('[scenario]', ...a);

try {
  if (opt('scenario', null)) {
    const mod = await import(url.pathToFileURL(path.resolve(String(opt('scenario')))).href);
    await mod.default({ page, evalJs: run, advance, shot, log });
  } else if (realtime) {
    if (opt('do', null)) await run(String(opt('do')));
    await page.waitForTimeout(Number(realtime) * 1000);
    await shot('rt');
  } else {
    if (opt('do', null)) await run(String(opt('do')));
    const times = String(opt('at', '0')).split(',').map(Number).filter((x) => !Number.isNaN(x)).sort((a, b) => a - b);
    for (const t of times) {
      await advance(t - simT);
      if (opt('each', null)) await run(String(opt('each')));
      await shot(t.toFixed(3));
    }
  }
  if (opt('eval', null)) console.log('[eval]', JSON.stringify(await run(String(opt('eval')))));
} catch (e) {
  errors++;
  console.log('[harness error]', String(e.stack || e).slice(0, 2500));
}

if ((has('sheet') || has('sheet-only')) && frames.length > 0) {
  const colsOpt = opt('sheet', true);
  const cols = colsOpt === true ? Math.min(frames.length, frames.length <= 4 ? frames.length : frames.length <= 9 ? 3 : 4) : Number(colsOpt);
  const fw = Number(opt('sheet-width', 480));
  const fh = Math.round((fw * H) / W);
  const sp = await browser.newPage({ viewport: { width: cols * (fw + 4) + 4, height: 100 } });
  const cells = frames.map((f) => `<div class="c"><img src="data:image/png;base64,${fs.readFileSync(f.p).toString('base64')}" width="${fw}" height="${fh}"><span>${f.label}</span></div>`).join('');
  await sp.setContent(`<style>body{margin:0;background:#111;display:grid;grid-template-columns:repeat(${cols},${fw}px);gap:4px;padding:4px}.c{position:relative;line-height:0}.c span{position:absolute;left:4px;top:4px;font:bold 13px/1 monospace;color:#fff;background:rgba(0,0,0,.65);padding:3px 5px;border-radius:3px}</style>${cells}`);
  await sp.screenshot({ path: `${out}_sheet.png`, fullPage: true });
  console.log('sheet:', path.relative(ROOT, `${out}_sheet.png`), `(${frames.length} frames)`);
  if (has('sheet-only')) for (const f of frames) fs.unlinkSync(f.p);
}
if (!has('sheet-only')) for (const f of frames) console.log('frame:', path.relative(ROOT, f.p));
await browser.close();
if (errors) console.log(`[harness] ${errors} page error(s)`);
process.exit(0);
