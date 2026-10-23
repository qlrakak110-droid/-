// usage: node boot.js <html> <outPrefix> [hash]
const { chromium } = require('playwright');
(async () => {
  const [html, out, hash] = process.argv.slice(2);
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const p = await b.newPage({ viewport: { width: 1280, height: 720 } });
  p.setDefaultTimeout(300000);
  const logs = [];
  p.on('console', m => { const t = m.text(); logs.push(t); if (/error|Error|warn/i.test(t) && logs.length < 400) console.log('[c]', t.slice(0, 300)); });
  p.on('pageerror', e => console.log('[pageerror]', e.message));
  const t0 = Date.now();
  await p.goto('file://' + html + (hash ? '#' + hash : ''));
  await p.waitForFunction(() => window.GW && GW.engine && GW.engine.running, null, { timeout: 300000 });
  console.log('engine running after', (Date.now() - t0) / 1000, 's');
  await p.waitForTimeout(8000);
  const info = await p.evaluate(() => ({ tier: GW.render && GW.render.tier, stats: (window.Render3D || GW.modules.render3d) && (GW.modules.render3d.carSkinStats ? GW.modules.render3d.carSkinStats() : null), keys: Object.keys(GW.modules || {}) }));
  console.log(JSON.stringify(info));
  await p.screenshot({ path: out + '_boot.png' });
  await b.close();
})();
