// Motion review batch (animation director's harness): contact sheets + the auditClip table for any list of clips, in
// one browser session. The lab is src/labs/motion_dir.js; the reading guide is src/fighters/MOTION.md.
//
//   node tools/motion.mjs <hero> [clips ...] [options]
//     <hero>               kael | iska | vorn | knight
//     clips                clip names, or a group: all | moves | states | ult | generic  (default: all)
//     --frames 8           side-view frames per sheet (the first impact is always one of them)
//     --times 0,0.1,0.14   explicit frame times (s) instead of --frames
//     --cols 4             cells per row         --cell 240x180   cell size (px)      --ss 2   supersampling
//     --views side,q       first view: every frame; further views: every second frame (side | q | front | rear | top)
//     --every 2            the further views show every N-th frame (1 = all)
//     --body design        design | mannequin (colour-coded limbs: right warm, left cool)
//     --no-xray            no stick figure over the body          --no-trail   no weapon-tip ghost trail
//     --tag before         file name suffix: <out>/<clip>_<tag>.png
//     --out shots/murim/motion/dir     output directory
//     --audit              print the audit table (and draw each row under its sheet); --audit-only: no sheets
//     --json file.json     write the audit rows as JSON
//     --lab motion_dir     lab entry (a private copy: src/labs/motion_<label>.js with `import './motion_dir.js';`)
//     --no-build           reuse build/<lab>.html      --hash "q=mid"   extra URL flags
//
//   node tools/motion.mjs kael kael.light1 kael.sweep --audit --tag before
//   node tools/motion.mjs iska moves --frames 10 --audit --json /tmp/iska_moves.json

import fs from 'node:fs';
import path from 'node:path';
import url from 'node:url';
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';

const ROOT = path.resolve(path.dirname(url.fileURLToPath(import.meta.url)), '..');
let chromium;
try { ({ chromium } = await import('playwright')); } catch (e) { ({ chromium } = createRequire('/opt/node-tools/node_modules/')('playwright')); }

const argv = process.argv.slice(2);
const VALUE = new Set(['frames', 'times', 'cols', 'cell', 'ss', 'views', 'every', 'body', 'tag', 'out', 'json', 'lab', 'hash']);
const pos = [], o = {};
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a.startsWith('--')) { const k = a.slice(2); if (VALUE.has(k)) o[k] = argv[++i]; else o[k] = true; } else pos.push(a);
}
const hero = pos[0];
if (!hero) { console.error('usage: node tools/motion.mjs <hero> [clips ... | all | moves | states | ult | generic] [--frames 8] [--audit] [--tag t] [--out dir]'); process.exit(1); }
const lab = o.lab || 'motion_dir';
if (!o['no-build']) execFileSync(process.execPath, [path.join(ROOT, 'tools/build.mjs'), lab], { stdio: 'inherit' });
const outDir = path.resolve(ROOT, o.out || 'shots/murim/motion/dir');
fs.mkdirSync(outDir, { recursive: true });

const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const page = await browser.newPage({ viewport: { width: 960, height: 540 }, deviceScaleFactor: 1 });
page.setDefaultTimeout(1800000);
let errors = 0;
page.on('console', (m) => {
  const t = m.type();
  if (t === 'error' || t === 'warning') { const s = m.text(); if (/GPU stall|GL Driver Message|Automatic fallback to software/.test(s)) return; errors += t === 'error' ? 1 : 0; console.log(`[page ${t}]`, s.slice(0, 600)); }
  else if (m.text().startsWith('[ed]')) console.log('[page]', m.text().slice(0, 600));
});
page.on('pageerror', (e) => { errors++; console.log('[page exception]', String(e.stack || e.message).slice(0, 1500)); });
await page.goto('file://' + path.join(ROOT, `build/${lab}.html`) + '#test&' + (o.hash || 'q=mid'), { waitUntil: 'commit', timeout: 900000 });
await page.waitForFunction(() => window.__ED && window.__ED.ready && window.__ED.motion, null, { timeout: 900000, polling: 500 });

const GROUPS = new Set(['all', 'moves', 'states', 'ult', 'generic']);
let names = [];
for (const a of pos.slice(1).length ? pos.slice(1) : ['all']) {
  if (GROUPS.has(a)) names.push(...(await page.evaluate(([h, g]) => window.__ED.motion.clips(h, g), [hero, a])));
  else names.push(a);
}
names = [...new Set(names)];

const sheetOpts = {};
if (o.frames) sheetOpts.frames = Number(o.frames);
if (o.times) sheetOpts.times = String(o.times).split(',').map(Number);
if (o.cols) sheetOpts.cols = Number(o.cols);
if (o.cell) sheetOpts.cell = String(o.cell).split('x').map(Number);
if (o.ss) sheetOpts.ss = Number(o.ss);
if (o.views) sheetOpts.views = String(o.views).split(',');
if (o.every) sheetOpts.every = Number(o.every);
if (o.body) sheetOpts.body = o.body;
if (o['no-xray']) sheetOpts.xray = false;
if (o.xray) sheetOpts.xray = true;
if (o['no-trail']) sheetOpts.trail = false;

const wantAudit = !!(o.audit || o['audit-only'] || o.json);
const rows = [];
const t0 = Date.now();
for (const name of names) {
  let row = null;
  try {
    if (wantAudit) { row = await page.evaluate(([h, n]) => window.__ED.motion.auditRow(h, n), [hero, name]); rows.push(row); }
  } catch (e) { row = { clip: name, error: String(e.message || e).split('\n')[0] }; rows.push(row); }
  if (o['audit-only']) continue;
  try {
    const res = await page.evaluate(([h, n, so, a]) => window.__ED.motion.sheet(h, n, { ...so, audit: a || undefined }), [hero, name, sheetOpts, row]);
    const file = path.join(outDir, name.replace(/[^\w.@-]+/g, '_') + (o.tag ? '_' + o.tag : '') + '.png');
    fs.writeFileSync(file, Buffer.from(res.png.split(',')[1], 'base64'));
    console.log('sheet:', path.relative(ROOT, file), `${res.meta.size[0]}x${res.meta.size[1]}`, res.meta.mannequin && sheetOpts.body !== 'mannequin' ? '(mannequin: design failed)' : '', 'clear', res.meta.clear.min, res.meta.clear.part);
  } catch (e) { errors++; console.log('[sheet error]', name, String(e.message || e).split('\n')[0]); }
}
if (wantAudit) {
  console.log('\naudit (' + hero + '; cm: drift skid clear comOut · mm below the floor: flFt flBl flBd · counts: lim isx bld pop ovr knk · deg: aim · m/s: tip)');
  console.log(await page.evaluate((rs) => window.__ED.motion.table(rs), rows));
  const notes = rows.filter((x) => !x.error && (x.limitWorst || x.isectWorst || x.bladeWorst || x.popWorst || x.clear < 0));
  if (notes.length) {
    console.log('\nworst offenders');
    for (const x of notes) console.log(' ', x.clip.padEnd(30), [x.limitWorst && 'limit ' + x.limitWorst, x.isectWorst && 'isect ' + x.isectWorst, x.bladeWorst && 'blade ' + x.bladeWorst, x.clear < 0 && 'clear ' + x.clear + 'cm ' + x.clearAt, x.popWorst && 'pop ' + x.popWorst].filter(Boolean).join(' | '));
  }
  if (o.json) { fs.mkdirSync(path.dirname(path.resolve(o.json)), { recursive: true }); fs.writeFileSync(path.resolve(o.json), JSON.stringify({ hero, rows }, null, 1)); console.log('json:', o.json); }
}
console.log(`[motion] ${names.length} clip(s) in ${((Date.now() - t0) / 1000).toFixed(1)} s` + (errors ? `, ${errors} page error(s)` : ''));
await browser.close();
process.exit(0);
