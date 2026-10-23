const { chromium } = require('playwright');
(async () => {
  const [html, secs, tele] = process.argv.slice(2);
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  const p = await b.newPage({ viewport: { width: 640, height: 360 } });
  p.on('console', m => { const t = m.text(); if (/OOM|Abort|CarInterior\] [^i]/.test(t)) console.log('[c]', t.slice(0, 200)); });
  await p.goto('file://' + html + '#fps');
  await p.waitForFunction(() => window.GW && GW.engine && GW.engine.running, null, { timeout: 300000 });
  const ev = (code) => p.evaluate((c) => GW.engine.eval(c).then((r) => String(r)).catch((e) => 'ERR ' + e), code);
  const t0 = Date.now();
  let teleported = false;
  while (Date.now() - t0 < +secs * 1000) {
    await p.waitForTimeout(10000);
    if (tele && !teleported && Date.now() - t0 > 50000) { teleported = true; await p.evaluate(() => Character.teleport([-289.9, 10.3, 69.8])); console.log('teleported'); }
    const r = await ev('local S = GW.require("services").S local ps = S.player and S.player:FindFirstChildOfClass("PlayerScripts") local sc = ps and ps:FindFirstChild("GwangalliCarInterior") return string.format("luauKB=%d cabins=%s nearest=%s tags=%d", gcinfo(), tostring(sc and sc:GetAttribute("Cabins")), tostring(sc and sc:GetAttribute("Nearest")), #GW.require("services").S.game:GetService("CollectionService"):GetTagged("NearLOD"))');
    const js = await p.evaluate(() => { const c = Character.getState(); return (document.getElementById('gw-perf') ? document.getElementById('gw-perf').textContent.replace(/\s+/g, ' ').slice(-60) : '') + ' hrp=' + c.position.map((v) => v.toFixed(1)).join(',') + ' jsHeapMB=' + Math.round((performance.memory && performance.memory.usedJSHeapSize || 0) / 1048576); });
    console.log(Math.round((Date.now() - t0) / 1000) + 's', r, js);
  }
  await b.close();
})();
