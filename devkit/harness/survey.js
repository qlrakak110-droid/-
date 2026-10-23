// node survey.js <html> -> every model with a VehicleKind attribute: name / CarModel / kind / has Interior / count
const { chromium } = require('playwright');
(async () => {
  const [html] = process.argv.slice(2);
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const p = await b.newPage({ viewport: { width: 640, height: 360 } });
  p.setDefaultTimeout(600000);
  await p.goto('file://' + html);
  await p.waitForFunction(() => window.GW && GW.engine && GW.engine.running, null, { timeout: 300000 });
  await p.waitForTimeout(8000);
  const ev = (code) => p.evaluate((c) => GW.engine.eval(c).then((r) => String(r)).catch((e) => 'ERR ' + e), code);
  const PRE = 'local Sched = GW.require("sched") local Env = GW.require("env") local S = GW.require("services").S local out = "?"\n';
  const r = await ev(PRE + `Sched.runIn(Env.serverCtx, function() local ok, e = pcall(function()
    local cnt, ex = {}, {}
    for _, d in S.workspace:GetDescendants() do
      if d:IsA("Model") and d:GetAttribute("VehicleKind") ~= nil then
        local int = d:FindFirstChild("Interior")
        local nParts = 0
        if int then for _, q in int:GetDescendants() do if q:IsA("BasePart") then nParts += 1 end end end
        local key = d.Name .. " | CarModel=" .. tostring(d:GetAttribute("CarModel")) .. " | kind=" .. tostring(d:GetAttribute("VehicleKind")) .. " | style=" .. tostring(d:GetAttribute("InteriorStyle")) .. " | interior=" .. tostring(int ~= nil) .. "(" .. nParts .. ")"
        cnt[key] = (cnt[key] or 0) + 1
        if not ex[key] then ex[key] = d:GetFullName() end
      end
    end
    local t = {}
    for k, n in cnt do table.insert(t, n .. "x " .. k .. " @ " .. ex[k]) end
    table.sort(t)
    out = table.concat(t, " ;; ")
  end) if not ok then out = "ERR " .. tostring(e) end end) Sched.flush() return out`);
  console.log(r.split(' ;; ').join('\n'));
  await b.close();
})();
