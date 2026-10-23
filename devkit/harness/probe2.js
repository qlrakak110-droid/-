const { chromium } = require('playwright');
(async () => {
  const [html] = process.argv.slice(2);
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  const p = await b.newPage({ viewport: { width: 640, height: 360 } });
  let ready = false;
  p.on('console', m => { const t = m.text(); if (/CarInterior/.test(t)) console.log('[c]', t.slice(0, 500)); if (/CarInterior\] ready/.test(t)) ready = true; });
  p.on('pageerror', e => console.log('[pageerror]', e.message));
  await p.goto('file://' + html);
  await p.waitForFunction(() => window.GW && GW.engine && GW.engine.running, null, { timeout: 300000 });
  for (let i = 0; i < 120 && !ready; i++) await p.waitForTimeout(1000);
  const ev = (code) => p.evaluate((c) => GW.engine.eval(c).then((r) => String(r)).catch((e) => 'ERR ' + e), code);
  const PRE = 'local Sched = GW.require("sched") local Env = GW.require("env") local S = GW.require("services").S local DT = GW.require("datatypes").globals local CFrame, Vector3 = DT.CFrame, DT.Vector3 local out = "?"\n';
  const run = (body) => ev(PRE + 'Sched.runIn(Env.serverCtx, function() local ok, e = pcall(function()\n' + body + '\nend) if not ok then out = "ERR " .. tostring(e) end end) Sched.flush() return out');
  console.log('cam', await run('local c = S.workspace.CurrentCamera out = tostring(c and c.CFrame.Position)'));
  console.log('tele', await run(`
    local best, bd = nil, 1e9
    for _, d in S.workspace:GetDescendants() do
      if d:IsA("Model") and d:GetAttribute("VehicleKind") == "sedan" and d:FindFirstChild("Interior") then
        local u = d:FindFirstChild("Underbody")
        if u then local dd = (u.Position - Vector3.new(-302.9, 6.76, 69.5)).Magnitude if dd < bd then bd, best = dd, d end end
      end
    end
    Env.__shotCar = best
    local u = best:FindFirstChild("Underbody")
    S.player.Character:PivotTo(u.CFrame * CFrame.new(9, 3, 0))
    out = best:GetFullName() .. " " .. tostring(u.Position) .. " anchored=" .. tostring(u.Anchored)`));
  for (let i = 0; i < 12; i++) {
    await p.waitForTimeout(5000);
    console.log(i, await run(`local m = Env.__shotCar local ps = S.player:FindFirstChildOfClass("PlayerScripts") local sc = ps and ps:FindFirstChild("GwangalliCarInterior")
      out = "cam=" .. tostring(S.workspace.CurrentCamera.CFrame.Position) .. " cabins=" .. tostring(sc and sc:GetAttribute("Cabins")) .. " err=" .. tostring(m:GetAttribute("GwCabinError")) .. " parts=" .. tostring(m:GetAttribute("GwCabinParts")) .. " cabin=" .. tostring(m:FindFirstChild("CabinAAA"))`));
  }
  await b.close();
})();
