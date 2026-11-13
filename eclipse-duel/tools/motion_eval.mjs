// Evaluate one expression in the motion lab and print the JSON result (quick numeric checks while authoring a clip).
//   node tools/motion_eval.mjs "__ED.motion.aimTrace('kael','kael.light1')" [--lab motion_dir] [--no-build]
//   node tools/motion_eval.mjs "__ED.motion.auditRow('iska','iska.rime_flick')"
import path from 'node:path';
import url from 'node:url';
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';

const ROOT = path.resolve(path.dirname(url.fileURLToPath(import.meta.url)), '..');
let chromium;
try { ({ chromium } = await import('playwright')); } catch (e) { ({ chromium } = createRequire('/opt/node-tools/node_modules/')('playwright')); }
const argv = process.argv.slice(2);
const li = argv.indexOf('--lab');
const lab = li >= 0 ? argv[li + 1] : 'motion_dir';
const exprs = argv.filter((a, i) => !a.startsWith('--') && !(li >= 0 && i === li + 1));
if (!exprs.length) { console.error('usage: node tools/motion_eval.mjs "<js expression>" ... [--lab motion_dir] [--no-build]'); process.exit(1); }
if (!argv.includes('--no-build')) execFileSync(process.execPath, [path.join(ROOT, 'tools/build.mjs'), lab], { stdio: 'inherit' });
const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const page = await browser.newPage({ viewport: { width: 480, height: 270 }, deviceScaleFactor: 1 });
page.setDefaultTimeout(1800000);
page.on('pageerror', (e) => console.log('[page exception]', String(e.stack || e.message).slice(0, 1200)));
await page.goto('file://' + path.join(ROOT, `build/${lab}.html`) + '#test&q=low', { waitUntil: 'commit', timeout: 900000 });
await page.waitForFunction(() => window.__ED && window.__ED.ready && window.__ED.motion, null, { timeout: 900000, polling: 500 });
for (const x of exprs) {
  try { console.log(JSON.stringify(await page.evaluate((c) => (0, eval)('(' + c + ')'), x))); } catch (e) { console.log('[error]', String(e.message || e).split('\n')[0]); }
}
await browser.close();
process.exit(0);
