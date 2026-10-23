// node pickprobe.js <html> <shots.json> <shotName> x,y x,y ...  -> what part is under each pixel (1280x720)
const { chromium } = require('playwright');
const fs = require('fs');
(async () => {
  const [html, shotsFile, shotName, ...pts] = process.argv.slice(2);
  const s = JSON.parse(fs.readFileSync(shotsFile, 'utf8')).find((x) => x.name === shotName);
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const p = await b.newPage({ viewport: { width: 1280, height: 720 } });
  p.setDefaultTimeout(600000);
  let ready = false;
  p.on('console', m => { const t = m.text(); if (/\[CarInterior\] ready/.test(t)) ready = true; });
  await p.goto('file://' + html);
  await p.waitForFunction(() => window.GW && GW.engine && GW.engine.running, null, { timeout: 300000 });
  for (let i = 0; i < 150 && !ready; i++) await p.waitForTimeout(1000);
  const ev = (code) => p.evaluate((c) => GW.engine.eval(c).then((r) => String(r)).catch((e) => 'ERR ' + e), code);
  const PRE = 'local Sched = GW.require("sched") local Env = GW.require("env") local S = GW.require("services").S local DT = GW.require("datatypes").globals local I = GW.require("instance") local CFrame, Vector3 = DT.CFrame, DT.Vector3 local out = "?"\n';
  const [x, y, z] = s.car.near;
  await ev(PRE + `Sched.runIn(Env.serverCtx, function()
    local best, bd = nil, 1e9
    for _, int in S.game:GetService("CollectionService"):GetTagged("NearLOD") do
      local d = int.Parent
      if int.Name == "Interior" and d and d:IsA("Model") and d:GetAttribute("VehicleKind") == "${s.car.kind}" then
        local u = d:FindFirstChild("Underbody") or d:FindFirstChild("Chassis", true)
        if u then local dd = (u.Position - Vector3.new(${x}, ${y}, ${z})).Magnitude if dd < bd then bd, best = dd, d end end
      end
    end
    Env.__shotCar = best
    local u = best:FindFirstChild("Underbody") or best:FindFirstChild("Chassis", true)
    local ps = S.player:FindFirstChildOfClass("PlayerScripts")
    local sc = ps and ps:FindFirstChild("GwangalliCarInterior")
    if sc then sc:SetAttribute("FocusPoint", u.Position) end
  end) Sched.flush() return "ok"`);
  let U = null;
  for (let i = 0; i < 120; i++) {
    await p.waitForTimeout(1000);
    const info = await ev(PRE + `Sched.runIn(Env.serverCtx, function()
      local m = Env.__shotCar
      local c = m and m:FindFirstChild("CabinAAA")
      local u = m and (m:FindFirstChild("Underbody") or m:FindFirstChild("Chassis", true))
      if not c or not m:GetAttribute("GwCabinParts") then out = "wait" return end
      local a = { u.CFrame:GetComponents() }
      for k, v in a do a[k] = string.format("%.5f", v) end
      out = table.concat(a, ",")
    end) Sched.flush() return out`);
    if (info !== 'wait' && info !== '?' && !info.startsWith('ERR')) { U = info.split(',').map(Number); break; }
  }
  console.log('U', U && U.slice(0, 3));
  const q = await ev(PRE + `local res = {} Sched.runIn(Env.serverCtx, function()
    local m = Env.__shotCar
    local u = m:FindFirstChild("Underbody") or m:FindFirstChild("Chassis", true)
    local int = m:FindFirstChild("Interior")
    local rim = int and int:FindFirstChild("SteeringWheel", true)
    for _, d in m:GetDescendants() do
      if d:IsA("BasePart") and not d:IsDescendantOf(m:FindFirstChild("CabinAAA")) then
        local lp = u.CFrame:PointToObjectSpace(d.Position)
        if string.find(d.Name, "${process.env.PAT || 'Wheel'}") or false then
          table.insert(res, d:GetFullName():gsub("^.-Car_", "") .. " size=" .. tostring(d.Size) .. " lp=" .. string.format("%.2f,%.2f,%.2f", lp.X, lp.Y, lp.Z) .. " T=" .. d.Transparency .. " LTM=" .. d.LocalTransparencyModifier .. " col=" .. tostring(d.Color) .. " GwT=" .. tostring(d:GetAttribute("GwCabinT")))
        end
      end
      if d:IsA("SurfaceGui") then
        local t = {}
        for _, l in d:GetDescendants() do if l:IsA("TextLabel") then table.insert(t, l.Text .. (l.Visible and "" or "(hidden)")) end end
        table.insert(res, "GUI " .. d:GetFullName():gsub("^.-Car_", "") .. " [" .. table.concat(t, "|") .. "]")
      end
    end
  end) Sched.flush() return table.concat(res, " ;; ")`);
  console.log(q);
  await b.close();
})();
