// node baseprobe.js <html> : plain car spawn on the given place (polls for the character first)
const { chromium } = require('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/harness/node_modules/playwright');
(async () => {
  const [html] = process.argv.slice(2);
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const p = await b.newPage({ viewport: { width: 1280, height: 720 } });
  p.setDefaultTimeout(900000);
  p.on('pageerror', (e) => console.log('[pageerror]', e.message.slice(0, 200)));
  await p.goto('file://' + html);
  await p.waitForFunction(() => window.GW && GW.engine && GW.engine.running, null, { timeout: 600000 });
  console.log('running');
  const ev = (code) => p.evaluate((c) => GW.engine.eval(c).then((r) => String(r)).catch((e) => 'ERR ' + e), code);
  const PRE = 'local Sched = GW.require("sched") local Env = GW.require("env") local S = GW.require("services").S local DT = GW.require("datatypes").globals local CFrame, Vector3 = DT.CFrame, DT.Vector3 local out = "?"\n';
  const srv = (body) => ev(PRE + `Sched.runIn(Env.serverCtx, function() local ok, e = pcall(function()\n${body}\nend) if not ok then out = "ERR " .. tostring(e) end end) Sched.flush() return out`);
  for (let i = 0; i < 100; i++) {
    const r = await srv(`local ch = S.player and S.player.Character local hrp = ch and ch:FindFirstChild("HumanoidRootPart") local api = S.game:GetService("ServerStorage"):FindFirstChild("GwangalliVehiclesAPI") out = tostring(hrp ~= nil and api ~= nil)`);
    if (r === 'true') break;
    await p.waitForTimeout(3000);
  }
  await p.waitForTimeout(20000);
  for (let k = 1; k <= 2; k++) {
    console.log('spawn', k, await srv(`local ch = S.player.Character local hrp = ch.HumanoidRootPart hrp.Anchored = false ch:PivotTo(CFrame.new(-556, 10, 487))
      local f = S.game:GetService("ServerStorage").GwangalliVehiclesAPI
      local ok, msg = f:Invoke("spawnOwned", S.player, { id = "dbg" .. ${k}, kind = "luxury", plate = "12가 3456", cond = 100, label = "dbg" }, { force = true })
      local cars = S.game.Workspace:FindFirstChild("GwangalliPlayerCars")
      out = "ok=" .. tostring(ok) .. " msg=" .. tostring(msg) .. " cars=" .. tostring(cars and #cars:GetChildren())`));
    await p.waitForTimeout(10000);
  }
  await b.close();
})();
