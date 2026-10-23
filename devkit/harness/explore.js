const { chromium } = require('playwright');
(async () => {
  const [html] = process.argv.slice(2);
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const p = await b.newPage({ viewport: { width: 1280, height: 720 } });
  p.setDefaultTimeout(300000);
  p.on('pageerror', e => console.log('[pageerror]', e.message));
  await p.goto('file://' + html);
  await p.waitForFunction(() => window.GW && GW.engine && GW.engine.running, null, { timeout: 300000 });
  for (let i = 0; i < 24; i++) { await p.waitForTimeout(5000); const s = await p.evaluate(() => JSON.stringify(Render3D.carSkinStats())); console.log(i*5+5, "s", s); if (JSON.parse(s).cars > 3 && i > 4) break; }
  const info = await p.evaluate(() => {
    const R = window.Render3D;
    return { tier: R._st().tier, stats: R.carSkinStats(), cam: R.camera.position.toArray(), cars: R.carSkinCars().sort((a,b)=>a.dist-b.dist).slice(0, 25), env: !!R.scene.environment, mods: Object.keys(GW.modules), q: R._st().cfg && R._st().cfg.name };
  });
  console.log(JSON.stringify(info, null, 0));
  await b.close();
})();
