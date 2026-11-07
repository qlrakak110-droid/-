// Smoke test for dist/SeoulSkyline_Studio.html: boots it headless, waits for SEOUL_READY, saves a screenshot.
//   node seoul-skyline/tools/test_studio.js <html> <out.png> [timeoutSec]
const { chromium } = require('playwright');
(async () => {
  const [html, out, tsec] = process.argv.slice(2);
  const b = await chromium.launch({ args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const p = await b.newPage({ viewport: { width: 1280, height: 720 } });
  let ready = false; const errs = [];
  p.on('console', (m) => { const t = m.text(); if (t.includes('SEOUL_READY')) ready = true;
    if (/TERRAIN_JSON|GL Driver|quality tier/.test(t)) return;
    if (/SeoulSkyline|error|Error|실패/.test(t)) { console.log(t.slice(0, 600)); if (/error|Error|실패/.test(t)) errs.push(t); } });
  p.on('pageerror', (e) => { console.log('[pageerror]', e.message); errs.push(e.message); });
  await p.goto('file://' + require('path').resolve(html) + '#quality=high&pr=1');
  const t0 = Date.now();
  while (!ready && Date.now() - t0 < (+tsec || 600) * 1000) await p.waitForTimeout(1000);
  console.log(ready ? 'READY' : 'TIMEOUT', ((Date.now() - t0) / 1000).toFixed(1) + 's');
  await p.waitForTimeout(6000);
  await p.screenshot({ path: out });
  console.log('errors', errs.length);
  await b.close();
})();
