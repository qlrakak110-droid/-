const { chromium } = require('playwright');
(async () => {
  const [html] = process.argv.slice(2);
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  const p = await b.newPage({ viewport: { width: 640, height: 360 } });
  p.on('console', m => { const t = m.text(); if (/CarInterior|luau/.test(t)) console.log('[c]', t.slice(0, 400)); });
  await p.goto('file://' + html);
  await p.waitForFunction(() => window.GW && GW.engine && GW.engine.running, null, { timeout: 300000 });
  await p.waitForTimeout(15000);
  const ev = (code) => p.evaluate((c) => GW.engine.eval(c).then((r) => String(r)).catch((e) => 'ERR ' + e), code);
  console.log('1', await ev('return 1+1'));
  console.log('2', await ev('local S = GW.require("services").S return tostring(S.workspace) .. " " .. tostring(S.player) .. " " .. tostring(S.game)'));
  console.log('3', await ev('local S = GW.require("services").S local n = 0 for _, d in S.workspace:GetChildren() do n += 1 end return n'));
  console.log('4', await ev('return tostring(game) .. tostring(workspace)'));
  console.log('5', await ev('local Sched = GW.require("sched") local Env = GW.require("env") local S = GW.require("services").S local out = "?" Sched.runIn(Env.serverCtx, function() out = "ran " .. tostring(#S.workspace:GetChildren()) end) Sched.flush() return out'));
  console.log('6', await ev('local Sched = GW.require("sched") local Env = GW.require("env") local S = GW.require("services").S local out = "?" Sched.runIn(Env.serverCtx, function() local ok, e = pcall(function() local n = 0 for _, d in S.workspace:GetDescendants() do n += 1 end out = "desc " .. n end) if not ok then out = "err " .. tostring(e) end end) Sched.flush() return out'));
  await b.close();
})();
