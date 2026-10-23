// node club.js <html> <outDir> : GwangalliClubPlus live check in the temp studio
const { chromium } = require('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/harness/node_modules/playwright');
const fs = require('fs');
const [html, outDir] = process.argv.slice(2);
fs.mkdirSync(outDir, { recursive: true });
const T0 = Date.now(); const log = (...a) => { const s = ((Date.now() - T0) / 1000).toFixed(0) + 's ' + a.join(' '); console.log(s); fs.appendFileSync(`${outDir}/log.txt`, s + '\n'); };
(async () => {
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const p = await b.newPage({ viewport: { width: 1280, height: 720 } });
  p.setDefaultTimeout(600000);
  p.on('pageerror', (e) => log('[pageerror]', e.message.slice(0, 300)));
  p.on('crash', () => log('[crash] page crashed'));
  p.on('console', (m) => { const t = m.text(); if (/ClubPlus|\[CP\]|GwangalliClub|ClubLights|ClubShow|Error|error/.test(t) && !/dbus|favicon|net::/.test(t)) log('[c]', t.slice(0, 500)); });
  await p.goto('file://' + html);
  await p.waitForFunction(() => window.GW && GW.engine && GW.engine.running, null, { timeout: 400000 });
  log('engine running');
  await p.waitForFunction(() => window.__cpInjected === true, null, { timeout: 400000 });
  log('injected');
  const ev = (code) => p.evaluate((c) => GW.engine.eval(c).then((r) => String(r)).catch((e) => 'ERR ' + e), code);
  const PRE = 'local Sched = GW.require("sched") local Env = GW.require("env") local S = GW.require("services").S local DT = GW.require("datatypes").globals local CFrame, Vector3 = DT.CFrame, DT.Vector3 local out = "?"\n';
  const srv = (body) => ev(PRE + `Sched.runIn(Env.serverCtx, function() local ok, e = pcall(function()\n${body}\nend) if not ok then out = "ERR " .. tostring(e) end end) Sched.flush() return out`);
  const cliCtx = `local CC = Env.clientCtx or (Env.peers and Env.peers.client and (Env.peers.client.ctx or Env.peers.client))`;
  const cli = (body) => ev(PRE + cliCtx + `\nif not CC then return "NOCLIENT" end Sched.runIn(CC, function() local ok, e = pcall(function()\n${body}\nend) if not ok then out = "ERR " .. tostring(e) end end) Sched.flush() return out`);
  const shot = async (name, eye, at, fov, hideGui) => {
    if (hideGui !== false) await p.evaluate(() => { let st = document.getElementById('cp-hide'); if (!st) { st = document.createElement('style'); st.id = 'cp-hide'; document.head.appendChild(st); } st.textContent = '#gw-gui,#gw-hud,#gw-controls,#gw-prompts,#gw-toasts,#gw-chips,#gw-badge{display:none!important}'; });
    else await p.evaluate(() => { const st = document.getElementById('cp-hide'); if (st) st.textContent = ''; });
    if (eye) {
      await p.evaluate(() => { try { CameraCtl.suspend(); } catch (e) {} });
      for (let k = 0; k < 6; k++) {
        await p.evaluate((s) => { const cam = Render3D.camera; cam.position.fromArray(s.eye); cam.up.set(0, 1, 0); cam.lookAt(...s.at); cam.fov = s.fov || 70; cam.near = 0.05; cam.updateProjectionMatrix(); }, { eye, at, fov });
        await p.waitForTimeout(200);
      }
    }
    await p.screenshot({ path: `${outDir}/${name}.png` });
    log('shot', name);
  };
  const tp = async (x, y, z, lx, lz) => {
    const js = await p.evaluate((pos) => { try { if (window.Character && Character.teleport) { Character.teleport(pos); return 'js'; } } catch (e) { return 'jsERR ' + e; } return 'nojs'; }, [x, y, z]);
    const r = await srv(`local ch = S.player.Character local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    hrp.Anchored = false
    ch:PivotTo(CFrame.lookAt(Vector3.new(${x}, ${y}, ${z}), Vector3.new(${lx}, ${y}, ${lz})))
    hrp.AssemblyLinearVelocity = Vector3.zero
    out = "tp " .. tostring(hrp.Position)`);
    return js + ' ' + r;
  };
  const RS = `local RS = S.game:GetService("ReplicatedStorage") local F = RS:FindFirstChild("GwangalliClubPlus") local HS = S.game:GetService("HttpService")`;
  const state = () => cli(`local f = S.game.Workspace:FindFirstChild("GwangalliClubPlusLocal") local counts = {}
      if f then for _, c in f:GetChildren() do counts[c.Name] = (counts[c.Name] or 0) + 1 end end
      local bits = {} for k, v in counts do table.insert(bits, k .. "=" .. v) end table.sort(bits)
      local lp = S.game:GetService("Players").LocalPlayer local pg = lp:FindFirstChild("PlayerGui") local g = {}
      for _, c in pg:GetChildren() do if string.find(c.Name, "ClubPlus") then table.insert(g, c.Name) end end
      local ui = pg:FindFirstChild("GwangalliClubPlusUI") local rail = ui and ui:FindFirstChild("Rail")
      local hrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
      local sc = lp:FindFirstChildOfClass("PlayerScripts"):FindFirstChild("GwangalliClubPlus")
      out = table.concat(bits, " ") .. " | " .. table.concat(g, " ") .. " | rail=" .. tostring(rail and rail.Visible) .. " hrp=" .. tostring(hrp and hrp.Position) .. " zone=" .. tostring(sc and sc:GetAttribute("Zone"))`);

  // A. server up
  let a = '';
  for (let i = 0; i < 40; i++) {
    a = await srv(`${RS} local club = RS:FindFirstChild("GwangalliClubShow") local SS = S.game:GetService("ServerStorage")
      out = "folder=" .. tostring(F ~= nil) .. " active=" .. tostring(F and F:GetAttribute("Active")) .. " club=" .. tostring(club ~= nil) .. " hook=" .. tostring(SS:FindFirstChild("ClubShowHook") ~= nil) .. " wallet=" .. tostring(SS:FindFirstChild("GwangalliGameplayAPI") ~= nil) .. " ranking=" .. tostring(RS:FindFirstChild("GwangalliClubRanking") ~= nil) .. " boards=" .. tostring(F and F:GetAttribute("Boards"))`);
    if (/active=true/.test(a)) break;
    await p.waitForTimeout(3000);
  }
  log('A', a.slice(0, 600));
  log('A2', await srv(`local api = S.game:GetService("ServerStorage"):FindFirstChild("GwangalliGameplayAPI") local c, bk = api:Invoke("balance", S.player) out = "balance " .. tostring(c) .. " " .. tostring(bk)`));
  // B. into the club (wristband) -> main room, next to the dance floor
  log('B', await srv(`S.player:SetAttribute("ClubOceanWristbandUntil", S.game.Workspace:GetServerTimeNow() + 3000) S.player:SetAttribute("GwJourneyClub", "open") out = "band"`));
  log('B tp', await tp(-108, 11, 371, -73, 374));
  await p.waitForTimeout(12000);
  log('diag cli', await cli(`local lp = S.game:GetService("Players").LocalPlayer local ps = lp:FindFirstChildOfClass("PlayerScripts") local sc = ps:FindFirstChild("GwangalliClubPlus")
    local bits = {} for k, v in sc:GetAttributes() do table.insert(bits, k .. "=" .. tostring(v)) end table.sort(bits)
    local CS = S.game:GetService("CollectionService") local hrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    local ev = S.game:GetService("ReplicatedStorage").GwangalliClubPlus.Event
    ev.OnClientEvent:Connect(function(kind, payload) lp:SetAttribute("CPLast", tostring(kind) .. ":" .. tostring(type(payload) == "table" and (payload.status or payload.title) or "")) end)
    out = table.concat(bits, " ") .. " | tagged=" .. #CS:GetTagged("ClubZone") .. " hrp=" .. tostring(hrp and hrp.Position)`));
  log('C', await state());
  log('diag srv', await srv(`local CS = S.game:GetService("CollectionService") local ch = S.player.Character local hrp = ch and ch:FindFirstChild("HumanoidRootPart") local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    local inside = {} if hrp then for _, z in CS:GetTagged("ClubZone") do local lp = z.CFrame:PointToObjectSpace(hrp.Position) local h = z.Size * 0.5 if math.abs(lp.X) <= h.X and math.abs(lp.Y) <= h.Y + 2 and math.abs(lp.Z) <= h.Z then table.insert(inside, tostring(z:GetAttribute("Zone"))) end end end
    out = "hrp=" .. tostring(hrp and hrp.Position) .. " hum=" .. tostring(hum and hum.Health) .. " tagged=" .. #CS:GetTagged("ClubZone") .. " inside=" .. table.concat(inside, ",") .. " band=" .. tostring(S.player:GetAttribute("ClubOceanWristbandUntil")) .. " now=" .. tostring(S.game.Workspace:GetServerTimeNow()) .. " journey=" .. tostring(S.player:GetAttribute("GwJourneyClub"))`));
  await shot('01_idle_led', [-108, 17, 374], [-73, 22, 374], 72);
  // D. 후원 (VIP 300,000 -> tier 3)
  log('D', await cli(`local r = S.game:GetService("ReplicatedStorage").GwangalliClubPlus.Request r:FireServer("donate", { rid = "t1", amount = 300000, target = "all" }) out = "sent"`));
  await p.waitForTimeout(2500);
  log('D stage', (await srv(`${RS} out = tostring(F:GetAttribute("Stage"))`)).slice(0, 300));
  log('D last', await cli(`out = tostring(S.game:GetService("Players").LocalPlayer:GetAttribute("CPLast"))`));
  await shot('02_donate', [-108, 17, 374], [-73, 22, 374], 72);
  // E. legend order (fake club Show + Tables write)
  log('E', await srv(`local club = S.game:GetService("ReplicatedStorage"):FindFirstChild("GwangalliClubShow") local HS = S.game:GetService("HttpService")
    local now = S.game.Workspace:GetServerTimeNow()
    club:SetAttribute("Show", HS:JSONEncode({ id = 9001, tier = 5, item = "royal", label = "로열 스파클링 세트", table = "G2", owner = S.player.UserId, name = "테스터", staff = 3, at = now + 0.5, arriveAt = now + 10, endAt = now + 32, aa = true }))
    local t = HS:JSONDecode(club:GetAttribute("Tables") or "{}") or {}
    t.G2 = { owner = S.player.UserId, name = "테스터", tier = 5, set = "royal", at = now + 10, untilT = now + 900 }
    club:SetAttribute("Tables", HS:JSONEncode(t)) out = "show"`));
  await p.waitForTimeout(2000);
  await shot('03_order', [-108, 17, 374], [-73, 22, 374], 72);
  await p.waitForTimeout(1500);
  await shot('04_lasers', [-145, 22, 395], [-95, 14, 370], 78);
  log('C2', await state());
  log('diag2', await cli(`local ps = S.game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerScripts") local sc = ps:FindFirstChild("GwangalliClubPlus")
    local bits = {} for k, v in sc:GetAttributes() do table.insert(bits, k .. "=" .. tostring(v)) end table.sort(bits) out = table.concat(bits, " ")`));
  // F. side LED ranking boards
  await shot('05_side_boards', [-118, 17, 390], [-118, 23, 411.7], 75);
  log('C3', await state());
  await b.close();
})().catch((e) => { log('FATAL', String(e).slice(0, 500)); process.exit(1); });
