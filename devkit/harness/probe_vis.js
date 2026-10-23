// node probe_fit.js <html> <cars.json> [names,...]  -> prints GwCabinFit / style per car
const { chromium } = require('playwright');
const fs = require('fs');
(async () => {
  const [html, carsFile, only] = process.argv.slice(2);
  const cars = JSON.parse(fs.readFileSync(carsFile, 'utf8'));
  const names = only ? only.split(',') : Object.keys(cars);
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const p = await b.newPage({ viewport: { width: 640, height: 360 } });
  p.setDefaultTimeout(600000);
  let ready = false;
  p.on('pageerror', e => console.log('[pageerror]', e.message));
  p.on('console', m => { const t = m.text(); if (/CarInterior/.test(t)) console.log('[c]', t.slice(0, 600)); if (/\[CarInterior\] ready/.test(t)) ready = true; });
  await p.goto('file://' + html);
  await p.waitForFunction(() => window.GW && GW.engine && GW.engine.running, null, { timeout: 300000 });
  for (let i = 0; i < 120 && !ready; i++) await p.waitForTimeout(1000);
  const ev = (code) => p.evaluate((c) => GW.engine.eval(c).then((r) => String(r)).catch((e) => 'ERR ' + e), code);
  const PRE = 'local Sched = GW.require("sched") local Env = GW.require("env") local S = GW.require("services").S local DT = GW.require("datatypes").globals local CFrame, Vector3 = DT.CFrame, DT.Vector3 local out = "?"\n';
  for (const n of names) {
    const c = cars[n];
    const [x, y, z] = c.near;
    const r = await ev(PRE + `Sched.runIn(Env.serverCtx, function() local ok, e = pcall(function()
      local best, bd = nil, 1e9
      for _, int in S.game:GetService("CollectionService"):GetTagged("NearLOD") do
        local d = int.Parent
        if int.Name == "Interior" and d and d:IsA("Model") and d:GetAttribute("VehicleKind") == "${c.kind}" then
          local u = d:FindFirstChild("Underbody") or d:FindFirstChild("Chassis", true)
          if u then local dd = (u.Position - Vector3.new(${x}, ${y}, ${z})).Magnitude if dd < bd then bd, best = dd, d end end
        end
      end
      if not best then out = "nocar" return end
      Env.__shotCar = best
      best:SetAttribute("GwCabinFit", nil)
      local u = best:FindFirstChild("Underbody") or best:FindFirstChild("Chassis", true)
      local ps = S.player:FindFirstChildOfClass("PlayerScripts")
      local sc = ps and ps:FindFirstChild("GwangalliCarInterior")
      if sc then sc:SetAttribute("Debug", true) sc:SetAttribute("FocusPoint", u.Position) end
      out = best:GetFullName() .. " d=" .. math.floor(bd) .. " model=" .. tostring(best:GetAttribute("CarModel"))
    end) if not ok then out = "ERR " .. tostring(e) end end) Sched.flush() return out`);
    console.log('=== ' + n + ' :: ' + r);
    let info = '';
    for (let i = 0; i < 90; i++) {
      await p.waitForTimeout(1000);
      info = await ev(PRE + `Sched.runIn(Env.serverCtx, function()
        local m = Env.__shotCar
        local f = m and m:GetAttribute("GwCabinFit")
        local parts = m and m:GetAttribute("GwCabinParts")
        local c = m and m:FindFirstChild("CabinAAA")
        if not f or not c or not parts then out = "wait err=" .. tostring(m and m:GetAttribute("GwCabinError")) .. " hide=" .. tostring(m and m:GetAttribute("GwHideState")) return end
        local vis = {}
        local int = m:FindFirstChild("Interior")
        for _, d in int:GetDescendants() do
          if d:IsA("BasePart") and d.Transparency < 0.99 then
            table.insert(vis, d.Name .. "<" .. d.ClassName .. ">" .. string.format("%.2f/%.2f", d.Transparency, d.LocalTransparencyModifier))
          end
        end
        out = "parts=" .. tostring(parts) .. " children=" .. #c:GetChildren() .. " style=" .. tostring(m:GetAttribute("GwCabinStyle")) .. "\\nVISIBLE " .. #vis .. ": " .. table.concat(vis, ", ")
      end) Sched.flush() return out`);
      if (!info.startsWith('wait') && !info.startsWith('ERR') && info !== '?') break;
      if (i % 15 === 14) console.log('  ', info.slice(0, 200));
    }
    console.log(info);
  }
  await b.close();
})();
