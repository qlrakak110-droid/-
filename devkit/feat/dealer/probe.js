const { chromium } = require('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/harness/node_modules/playwright');
const fs = require('fs');
(async () => {
  const [html, luaFile, waitS] = process.argv.slice(2);
  const code = fs.readFileSync(luaFile, 'utf8');
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const p = await b.newPage({ viewport: { width: 1280, height: 720 } });
  p.setDefaultTimeout(900000);
  p.on('pageerror', e => console.log('[pageerror]', e.message));
  p.on('console', m => { const t = m.text(); if (/Showroom|Garage|Bike|error/i.test(t)) console.log('[c]', t.slice(0, 300)); });
  await p.goto('file://' + html);
  await p.waitForFunction(() => window.GW && GW.engine && GW.engine.running, null, { timeout: 600000 });
  console.log('running');
  await p.waitForTimeout(Number(waitS || 60) * 1000);
  const PRE = 'local Sched = GW.require("sched") local Env = GW.require("env") local S = GW.require("services").S local DT = GW.require("datatypes").globals local CFrame, Vector3 = DT.CFrame, DT.Vector3 local out = "?"\n';
  const r = await p.evaluate((c) => GW.engine.eval(c).then((r) => String(r)).catch((e) => 'ERR ' + e), PRE + 'Sched.runIn(Env.serverCtx, function() local ok, e = pcall(function()\n' + code + '\nend) if not ok then out = "ERR " .. tostring(e) end end) Sched.flush() return out');
  console.log(r);
  await b.close();
})();
