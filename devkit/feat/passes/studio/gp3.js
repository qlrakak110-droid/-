// node gp.js <html> <outDir> : GwangalliPasses functional test in the temp studio
const { chromium } = require('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/harness/node_modules/playwright');
const fs = require('fs');
const [html, outDir] = process.argv.slice(2);
fs.mkdirSync(outDir, { recursive: true });
(async () => {
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const p = await b.newPage({ viewport: { width: 1280, height: 720 } });
  p.setDefaultTimeout(600000);
  p.on('pageerror', (e) => console.log('[pageerror]', e.message.slice(0, 300)));
  p.on('console', (m) => { const t = m.text(); if (/GwangalliPasses|\[GP\]|Passes/.test(t)) console.log('[c]', t.slice(0, 500)); });
  await p.goto('file://' + html);
  await p.waitForFunction(() => window.GW && GW.engine && GW.engine.running, null, { timeout: 400000 });
  console.log('engine running');
  await p.waitForFunction(() => window.__gpInjected === true, null, { timeout: 400000 });
  console.log('injected');
  const ev = (code) => p.evaluate((c) => GW.engine.eval(c).then((r) => String(r)).catch((e) => 'ERR ' + e), code);
  const PRE = 'local Sched = GW.require("sched") local Env = GW.require("env") local S = GW.require("services").S local DT = GW.require("datatypes").globals local CFrame, Vector3 = DT.CFrame, DT.Vector3 local out = "?"\n';
  const srv = (body) => ev(PRE + `Sched.runIn(Env.serverCtx, function() local ok, e = pcall(function()\n${body}\nend) if not ok then out = "ERR " .. tostring(e) end end) Sched.flush() return out`);
  const cliCtx = `local CC = Env.clientCtx or (Env.peers and Env.peers.client and (Env.peers.client.ctx or Env.peers.client))`;
  const cli = (body) => ev(PRE + cliCtx + `\nif not CC then return "NOCLIENT" end Sched.runIn(CC, function() local ok, e = pcall(function()\n${body}\nend) if not ok then out = "ERR " .. tostring(e) end end) Sched.flush() return out`);
  const shot = async (name, eye, at, fov) => {
    if (eye) {
      await p.evaluate(() => CameraCtl.suspend());
      for (let k = 0; k < 8; k++) {
        await p.evaluate((s) => { const cam = Render3D.camera; cam.position.fromArray(s.eye); cam.up.set(0, 1, 0); cam.lookAt(...s.at); cam.fov = s.fov || 50; cam.near = 0.05; cam.updateProjectionMatrix(); }, { eye, at, fov });
        await p.waitForTimeout(250);
      }
    }
    await p.screenshot({ path: `${outDir}/${name}.png` });
    if (eye) await p.evaluate(() => { try { CameraCtl.resume(); } catch (e) {} });
    console.log('shot', name);
  };
  const tp = (x, y, z, lx, lz) => srv(`local ch = S.player.Character local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    hrp.Anchored = false
    ch:PivotTo(CFrame.lookAt(Vector3.new(${x}, ${y}, ${z}), Vector3.new(${lx}, ${y}, ${lz})))
    hrp.AssemblyLinearVelocity = Vector3.zero
    out = "tp " .. tostring(hrp.Position)`);
  const API = `local SS = S.game:GetService("ServerStorage") local api = SS:FindFirstChild("GwangalliPassesAPI")`;
  // A. wait for the features
  let ready = '';
  for (let i = 0; i < 90; i++) {
    ready = await srv(`local f = S.game:GetService("ReplicatedStorage"):FindFirstChild("GwangalliPassesRemotes") out = tostring(f and f:GetAttribute("GwPassesReady"))`);
    if (/"garage":true/.test(ready) && /"market":true/.test(ready) && /"ko":true/.test(ready)) break;
    await p.waitForTimeout(3000);
  }
  console.log('A ready', ready);
  console.log('A env', await ev(PRE + cliCtx + ` return "clientCtx=" .. tostring(CC ~= nil) .. " studio=" .. tostring(S.game:GetService("RunService"):IsStudio())`));
  // B. state
  console.log('B', await srv(`local SS = S.game:GetService("ServerStorage") local t = SS:FindFirstChild("GwangalliPassesTemplates")
    local names = {} for _, m in (t and t:GetChildren() or {}) do local n = 0 for _, d in m:GetDescendants() do if d:IsA("BasePart") then n += 1 end end table.insert(names, m.Name .. "=" .. n .. ":" .. tostring(m:GetAttribute("VehicleKind"))) end
    local pv = S.game:GetService("ReplicatedStorage"):FindFirstChild("GwangalliPassesPreviews")
    local st = S.game.Workspace:FindFirstChild("GwangalliPassesWorld")
    local body = st and st:FindFirstChild("Body", true)
    local own = {} for _, k in { "PremiumGarage", "Convenience", "Flex" } do table.insert(own, k .. "=" .. tostring(S.player:GetAttribute("GwPass_" .. k))) end
    out = "templates " .. table.concat(names, " ") .. " | previews " .. tostring(pv and #pv:GetChildren()) .. " | station " .. tostring(body and body.Position) .. " | " .. table.concat(own, " ") .. " | atGarage " .. tostring(S.player:GetAttribute("GwPassAtGarage"))`));
  await shot('00_station', [-536, 12, 492], [-542, 9, 477], 50);

  const req = (op, payload) => cli(`local rf = S.game:GetService("ReplicatedStorage").GwangalliPassesRemotes.Request local r = rf:InvokeServer("${op}", ${payload || 'nil'})
    local bits = {} for k, v in r do if type(v) ~= "table" then table.insert(bits, tostring(k) .. "=" .. tostring(v)) end end table.sort(bits) out = table.concat(bits, " ")`);
  // D. 원격 차고 lock (no pass) far from the 정비소: refused before any spawn
  console.log('D noadmin', await srv(`S.player:SetAttribute("GwangalliAdmin", false) out = "ok"`));
  await p.waitForTimeout(1500);
  console.log('D give', await srv(`local g = S.game:GetService("ServerStorage").GwangalliGarageAPI local v = g:Invoke("give", S.player, "sedan") out = tostring(v and v.id) .. " pass=" .. tostring(S.player:GetAttribute("GwPass_PremiumGarage"))`));
  console.log('D tp far', await tp(-513, 10, 245, -513, 200));
  await p.waitForTimeout(2500);
  console.log('D call far', await srv(`local g = S.game:GetService("ServerStorage").GwangalliGarageAPI local cars = g:Invoke("cars", S.player) local id = cars and cars[#cars] and cars[#cars].id
    local r = g:Invoke("request", S.player, "call", { id = id }) out = "atGarage=" .. tostring(S.player:GetAttribute("GwPassAtGarage")) .. " ok=" .. tostring(r and r.ok) .. " msg=" .. tostring(r and r.message)`));
  console.log('D state locked', await req('garage'));
  console.log('D tp station', await tp(-542, 10, 482, -542, 470));
  await p.waitForTimeout(2500);
  console.log('D atGarage', await srv(`out = tostring(S.player:GetAttribute("GwPassAtGarage"))`));
  console.log('D admin back', await srv(`S.player:SetAttribute("GwangalliAdmin", true) out = "ok"`));
  await p.waitForTimeout(1500);
  // E. state / market
  console.log('E state', await req('state'));
  console.log('E garage', await req('garage'));
  console.log('E tp street', await tp(-430, 10, 470, -430, 520));
  await p.waitForTimeout(2500);
  console.log('E marketState', await req('marketState'));
  console.log('E market', await req('market', '{ tab = "basic" }'));
  await p.waitForTimeout(2000);
  console.log('E shopui', await srv(`local pg = S.player:FindFirstChildOfClass("PlayerGui") local g = pg and pg:FindFirstChild("GwangalliArmsShop") out = "shop gui=" .. tostring(g ~= nil) .. " enabled=" .. tostring(g and g.Enabled)`));
  await shot('03_market_shop');
  console.log('E close shop', await cli(`local pg = S.player:FindFirstChildOfClass("PlayerGui") local g = pg and pg:FindFirstChild("GwangalliArmsShop") if g then g.Enabled = false end out = "ok"`));
  // F. plate
  console.log('F setPlate', await req('setPlate', '{ text = "광안 1004", style = "gold" }'));
  console.log('F setPlate bad', await req('setPlate', '{ text = "<b>x</b>", style = "neon" }'));
  console.log('F attrs', await srv(`out = tostring(S.player:GetAttribute("GwVanityPlate")) .. " / " .. tostring(S.player:GetAttribute("GwPlateStyle"))`));
  // G. neon
  console.log('G setNeon', await req('setNeon', '{ palette = "bridge" }'));
  console.log('G setKoFx', await req('setKoFx', '{ fx = "lightning" }'));
  await p.waitForTimeout(1500);
  console.log('G tags', await srv(`local pg = S.player:FindFirstChildOfClass("PlayerGui") local t = pg and pg:FindFirstChild("GwangalliPassesTags") out = "tags=" .. tostring(t and #t:GetChildren()) .. " neon=" .. tostring(S.player:GetAttribute("GwNeonName")) .. " humDisplay=" .. tostring(S.player.Character.Humanoid.DisplayDistanceType)`));
  console.log('G tp', await tp(-556, 10, 487, -556, 520));
  await p.waitForTimeout(4000);
  await shot('04_neon_tag', [-556, 15, 497], [-556, 13, 487], 40);
  // H. KO effect previews
  for (const fx of ['fireworks', 'lightning', 'stamp', 'skull', 'money', 'stars']) {
    console.log('H preview', fx, await req('previewKo', `{ fx = "${fx}" }`));
    await p.waitForTimeout(fx === 'fireworks' ? 1100 : 450);
    const pos = await srv(`local r = S.player.Character.HumanoidRootPart local q = r.Position + Vector3.new(r.CFrame.LookVector.X, 0, r.CFrame.LookVector.Z).Unit * 9 out = string.format("%.1f,%.1f,%.1f", q.X, q.Y, q.Z)`);
    const [x, y, z] = pos.split(',').map(Number);
    await shot('05_fx_' + fx, [x + 14, y + 8, z + 18], [x, y + (fx === 'fireworks' ? 10 : 3), z], 60);
    await p.waitForTimeout(3300);
  }
  // I. KO halving: knocked out, the 병원으로 이송 request at 6 s (refused) and at 11 s (allowed with the pass)
  console.log('I ko', await srv(`local A = S.game:GetService("ServerStorage").GwangalliArmsAPI local r = A:Invoke("knockOut", S.player, { byKind = "env" }) out = "down=" .. tostring(r) .. " GwKO=" .. tostring(S.player.Character:GetAttribute("GwKO")) .. " end-now=" .. tostring((S.player:GetAttribute("GwPassQoLKOEnd") or 0) - S.game.Workspace:GetServerTimeNow())`));
  await p.waitForTimeout(6000);
  console.log('I help@6', await cli(`S.game:GetService("ReplicatedStorage").GwangalliArms.Action:FireServer("koHelp", { want = "hospital" }) out = "sent"`));
  await p.waitForTimeout(1500);
  console.log('I state@7', await srv(`out = tostring(S.player.Character:GetAttribute("ArmsKO"))`));
  await shot('06_ko_screen');
  await p.waitForTimeout(3500);
  console.log('I help@11', await cli(`S.game:GetService("ReplicatedStorage").GwangalliArms.Action:FireServer("koHelp", { want = "hospital" }) out = "sent"`));
  await p.waitForTimeout(1500);
  console.log('I state@12', await srv(`out = tostring(S.player.Character:GetAttribute("ArmsKO")) .. " GwKO=" .. tostring(S.player.Character:GetAttribute("GwKO"))`));
  await p.waitForTimeout(9000);
  console.log('I after', await srv(`out = "GwKO=" .. tostring(S.player.Character and S.player.Character:GetAttribute("GwKO"))`));
  // J. phone + app
  console.log('J phone', await cli(`local ev = S.player:FindFirstChild("GwangalliPhoneOpen") if ev then ev:Fire() end out = "fired=" .. tostring(ev ~= nil)`));
  await p.waitForTimeout(3000);
  console.log('J dock', await srv(`local pg = S.player:FindFirstChildOfClass("PlayerGui") local ph = pg and pg:FindFirstChild("GwangalliPhone") local d = ph and ph:FindFirstChild("Dock", true) out = "phone=" .. tostring(ph and ph.Enabled) .. " vip=" .. tostring(d and d:FindFirstChild("App_vip") ~= nil)`));
  await shot('07_phone_dock');
  console.log('J click vip', await cli(`local pg = S.player:FindFirstChildOfClass("PlayerGui") local ph = pg and pg:FindFirstChild("GwangalliPhone") local b = ph and ph:FindFirstChild("App_vip", true) local ev = S.player:FindFirstChild("GwangalliPassesOpen") if ev then ev:Fire("pass") end out = "vip=" .. tostring(b ~= nil) .. " ev=" .. tostring(ev ~= nil)`));
  await p.waitForTimeout(4000);
  await shot('08_hub_pass');
  for (const tab of ['garage', 'market', 'flex']) {
    console.log('J hub', tab, await cli(`local ev = S.player:FindFirstChild("GwangalliPassesOpen") ev:Fire("${tab}") out = "ok"`));
    await p.waitForTimeout(5000);
    await shot('08_hub_' + tab);
  }
  console.log('J callcar sheet', await cli(`local pg = S.player:FindFirstChildOfClass("PlayerGui") local ph = pg and pg:FindFirstChild("GwangalliPhone") if ph then ph.Enabled = false end out = "ok"`));
  await p.waitForTimeout(1500);
  console.log('J noadmin2', await srv(`S.player:SetAttribute("GwangalliAdmin", false) out = "ok"`));
  console.log('J tp far2', await tp(-513, 10, 245, -513, 200));
  await p.waitForTimeout(3000);
  console.log('J open sheet', await cli(`local ps = S.player:FindFirstChildOfClass("PlayerScripts") local ev = S.player:FindFirstChild("GwangalliFeaturesOpen") if ev then ev:Fire("callcar") end out = "features=" .. tostring(ev ~= nil)`));
  await p.waitForTimeout(5000);
  await shot('09_callcar_locked');
  // K. last: one premium summon (car spawns may exhaust this engine's memory)
  console.log('K admin', await srv(`S.player:SetAttribute("GwangalliAdmin", true) out = "ok"`));
  console.log('K tp', await tp(-556, 10, 487, -556, 520));
  await p.waitForTimeout(4000);
  const r = await srv(`${API} local ok, msg = api:Invoke("summon", S.player, "hyper", "here")
      local f = S.game.Workspace:FindFirstChild("GwangalliPlayerCars") local m = nil
      for _, c in (f and f:GetChildren() or {}) do if c:GetAttribute("GwPremiumCar") == "hyper" then m = c end end
      local pos = m and m:GetPivot().Position
      out = string.format("ok=%s msg=%s rigged=%s kind=%s plate=%s", tostring(ok), tostring(msg), tostring(m and m:GetAttribute("DriveRigged")), tostring(m and m:GetAttribute("VehicleKind")), tostring(m and m:GetAttribute("DrivePlate")))
      if pos then out ..= string.format(" @%.1f,%.1f,%.1f", pos.X, pos.Y, pos.Z) end`);
  console.log('K hyper', r);
  const m = r.match(/@(-?[\d.]+),(-?[\d.]+),(-?[\d.]+)/);
  if (m) {
    const [x, y, z] = [Number(m[1]), Number(m[2]), Number(m[3])];
    await p.waitForTimeout(2500);
    await shot('10_car_hyper', [x + 11, y + 5, z + 11], [x, y + 1.5, z], 45);
  }
  console.log('done');
  await b.close();
})();
