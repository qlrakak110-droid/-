// node crew.js <html> <outDir> : GwangalliShopCrew live check in the temp studio
const { chromium } = require('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/harness/node_modules/playwright');
const fs = require('fs');
const [html, outDir, shopName] = process.argv.slice(2);
const SHOP = shopName || '광안 돼지국밥';
fs.mkdirSync(outDir, { recursive: true });
const T0 = Date.now(); const log = (...a) => { const s = ((Date.now() - T0) / 1000).toFixed(0) + 's ' + a.join(' '); console.log(s); fs.appendFileSync(`${outDir}/log.txt`, s + '\n'); };
(async () => {
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const p = await b.newPage({ viewport: { width: 1280, height: 720 } });
  p.setDefaultTimeout(600000);
  p.on('pageerror', (e) => log('[pageerror]', e.message.slice(0, 300)));
  p.on('crash', () => log('[crash] page crashed'));
  p.on('console', (m) => { const t = m.text(); if (/ShopCrew|\[SC\]|ShopService|ShopLife bus|Crew_|crew/.test(t) && !/dbus|favicon|net::/.test(t)) log('[c]', t.slice(0, 600)); });
  await p.goto('file://' + html);
  await p.waitForFunction(() => window.GW && GW.engine && GW.engine.running, null, { timeout: 400000 });
  log('engine running');
  await p.waitForFunction(() => window.__scInjected === true, null, { timeout: 400000 });
  log('injected');
  const ev = (code) => p.evaluate((c) => GW.engine.eval(c).then((r) => String(r)).catch((e) => 'ERR ' + e), code);
  const PRE = 'local Sched = GW.require("sched") local Env = GW.require("env") local S = GW.require("services").S local DT = GW.require("datatypes").globals local CFrame, Vector3 = DT.CFrame, DT.Vector3 local out = "?"\n';
  const srv = (body) => ev(PRE + `Sched.runIn(Env.serverCtx, function() local ok, e = pcall(function()\n${body}\nend) if not ok then out = "ERR " .. tostring(e) end end) Sched.flush() return out`);
  const cliCtx = `local CC = Env.clientCtx or (Env.peers and Env.peers.client and (Env.peers.client.ctx or Env.peers.client))`;
  const cli = (body) => ev(PRE + cliCtx + `\nif not CC then return "NOCLIENT" end Sched.runIn(CC, function() local ok, e = pcall(function()\n${body}\nend) if not ok then out = "ERR " .. tostring(e) end end) Sched.flush() return out`);
  const shot = async (name, eye, at, fov, hideGui) => {
    if (hideGui !== false) await p.evaluate(() => { let st = document.getElementById('sc-hide'); if (!st) { st = document.createElement('style'); st.id = 'sc-hide'; document.head.appendChild(st); } st.textContent = '#gw-hud,#gw-controls,#gw-chips,#gw-badge{display:none!important}'; });
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
  const SVC = `local SSS = S.game:GetService("ServerScriptService") local SS = S.game:GetService("ServerStorage") local HS = S.game:GetService("HttpService")
    local HOOK = SS:FindFirstChild("GwCrewTestHook")
    local API = SS:FindFirstChild("GwangalliShopCrew") local BUS = SS:FindFirstChild("GwangalliShopLife")
    local function V(v) return string.format("%.1f,%.1f,%.1f", v.X, v.Y, v.Z) end`;

  // A. ready
  let a = '';
  for (let i = 0; i < 200; i++) {
    a = await srv(`${SVC} out = "ready=" .. tostring(API and API:GetAttribute("Ready")) .. " bus=" .. tostring(BUS ~= nil) .. " gwb=" .. tostring(S.game.Workspace:GetAttribute("GwB_Ready")) .. " svc=" .. tostring(SSS:FindFirstChild("GwangalliShopService") and SSS.GwangalliShopService.Enabled) .. " hook=" .. tostring(HOOK ~= nil)`);
    if (a.includes('ready=true') && a.includes('hook=true')) break;
    await p.waitForTimeout(3000);
  }
  log('A', a);
  // B. the shop
  let info = 'none';
  for (let i = 0; i < 40 && !info.includes('|'); i++) { info = await srv(`${SVC} out = HOOK:Invoke("find", "${SHOP}")`); if (!info.includes('|')) await p.waitForTimeout(3000); }
  log('B', info);
  const [KEY, C, D, FY] = info.split('|');
  const c = C.split(',').map(Number), d = D.split(',').map(Number), fy = Number(FY);
  const dir = [d[0] - c[0], d[2] - c[2]]; const L = Math.hypot(dir[0], dir[1]) || 1; dir[0] /= L; dir[1] /= L;
  const inside = [c[0] + dir[0] * 3, fy + 3, c[2] + dir[1] * 3];
  const eye = [c[0] + dir[0] * 8.5, fy + 7.5, c[2] + dir[1] * 8.5];
  const at = [c[0] - dir[0] * 4, fy + 1.5, c[2] - dir[1] * 4];
  const tp = async (pos, look) => {
    const js = await p.evaluate((q) => { try { if (window.Character && Character.teleport) { Character.teleport(q); return 'js'; } } catch (e) { return 'jsERR ' + e; } return 'nojs'; }, pos);
    const r = await srv(`local ch = S.player.Character local hrp = ch and ch:FindFirstChild("HumanoidRootPart") ch:PivotTo(CFrame.lookAt(Vector3.new(${pos[0]}, ${pos[1]}, ${pos[2]}), Vector3.new(${look[0]}, ${pos[1]}, ${look[2]}))) hrp.Anchored = true hrp.AssemblyLinearVelocity = Vector3.zero out = "tp " .. tostring(hrp.Position)`);
    return js + ' ' + r;
  };
  log('tp', await tp(inside, c));
  await p.waitForTimeout(4000);
  log('where', await srv(`${SVC} out = HOOK:Invoke("session") .. " pos=" .. tostring(S.player.Character.HumanoidRootPart.Position)`));
  const status = async (tag) => {
    const s = await srv(`${SVC} local st = API.API:Invoke("status") local bits = {}
      for _, cr in st.crews do local r = {} for role, x in cr.rigs do table.insert(r, role .. ":" .. x.job .. "/" .. x.queue) end table.insert(bits, cr.name .. "[" .. table.concat(r, " ") .. "] sm=" .. tostring(cr.staffMode) .. " err=" .. cr.errors .. " " .. tostring(cr.lastError)) end
      local site = st.sites["${KEY}"]
      local e = {} for k, v in st.errors do table.insert(e, k .. "=" .. v) end
      local hp = S.player.Character and S.player.Character:FindFirstChild("HumanoidRootPart")
      out = "pos=" .. (hp and V(hp.Position) or "-") .. " sess=" .. HOOK:Invoke("session") .. " crews=" .. #st.crews .. " rigs=" .. st.rigs .. " diners=" .. st.diners .. " aug=" .. st.augmented .. " active=" .. st.activeShops .. " site=" .. (site and (tostring(site.ok) .. "/" .. tostring(site.why) .. "/roles " .. site.roles) or "-") .. " errs " .. table.concat(e, ",") .. " last=" .. tostring(st.lastError) .. " serve=" .. HS:JSONEncode(st.serve) .. " || " .. table.concat(bits, " ; ")`);
    log(tag, s);
    return s;
  };
  for (let i = 0; i < 12; i++) { await p.waitForTimeout(3000); const s = await status('C' + i); if (/crews=[1-9]/.test(s) && s.includes(SHOP)) break; }
  await p.waitForTimeout(4000);
  await shot('01_crew', eye, at, 70);
  log('rigs', await srv(`${SVC} local f = S.game.Workspace:FindFirstChild("GwShopCrew") local bits = {}
    if f and f:FindFirstChild("Staff") then for _, m in f.Staff:GetChildren() do table.insert(bits, m.Name .. "@" .. V(m:GetPivot().Position) .. " act=" .. tostring(m:GetAttribute("NpcAct")) .. " av=" .. tostring(m:GetAttribute("AvatarId"))) end end
    out = table.concat(bits, " ; ")`));
  // D. sit
  log('sit', await srv(`${SVC} out = "sat=" .. HOOK:Invoke("sit", "${KEY}", 1) .. " " .. HOOK:Invoke("session")`));
  for (let i = 0; i < 6; i++) { await p.waitForTimeout(2000); await status('D' + i); }
  await shot('02_welcome', eye, at, 70, false);
  log('dialog', await cli(`local pg = S.game:GetService("Players").LocalPlayer.PlayerGui local g = pg:FindFirstChild("GwangalliShopCrewUI") local bits = {}
    if g then for _, x in g:GetDescendants() do if x:IsA("TextLabel") and x.Visible and x.Text ~= "" and #bits < 12 then table.insert(bits, x.Name .. "=" .. x.Text) end end end
    out = "gui=" .. tostring(g ~= nil) .. " hide=" .. tostring(g and g:GetAttribute("HideGwangalliHUD")) .. " " .. table.concat(bits, " | ")`));
  // E. order
  log('order', await srv(`${SVC} out = HOOK:Invoke("order", "${KEY}")`));
  let shotTray = false;
  for (let i = 0; i < 18; i++) {
    await p.waitForTimeout(2500);
    const s = await status('E' + i);
    const lg = await srv(`${SVC} out = HOOK:Invoke("session")`);
    log('sess', lg);
    if (!shotTray && /waiter:serve/.test(s)) { shotTray = true; await p.waitForTimeout(1500); await shot('03_tray', eye, at, 70); }
    if (shotTray && /waiter:(idle|-)/.test(s) && i > 4) { await p.waitForTimeout(3000); break; }
  }
  await shot('04_served', eye, at, 70);
  // F. talk via the remote (client)
  await cli(`task.spawn(function() local ok, err = pcall(function() local RS = S.game:GetService("ReplicatedStorage") local rf = RS.GwangalliShopCrewNet.Request
    local id = nil for _, m in S.game:GetService("CollectionService"):GetTagged("GwShopCrew") do if m:GetAttribute("CrewRole") == "waiter" then id = m:GetAttribute("NpcId") end end
    local r = rf:InvokeServer("talk", { crew = id }) local bits = { "ok=" .. tostring(r.ok) }
    if r.dialog then table.insert(bits, r.dialog.name .. ": " .. r.dialog.text) for _, ch in r.dialog.choices do table.insert(bits, ch.id) end
      local r2 = rf:InvokeServer("choose", { crew = id, token = r.dialog.token, choice = "more" })
      if r2.dialog then table.insert(bits, "MORE " .. r2.dialog.text)
        local r3 = rf:InvokeServer("choose", { crew = id, token = r2.dialog.token, choice = "dirs" })
        if r3.dialog then table.insert(bits, "DIRS " .. r3.dialog.text .. " " .. (r3.dialog.choices[1] and r3.dialog.choices[1].label or "-"))
          local r4 = rf:InvokeServer("choose", { crew = id, token = r3.dialog.token, choice = "d_1" })
          table.insert(bits, "D1 " .. tostring(r4.dialog and r4.dialog.text))
          local r5 = rf:InvokeServer("choose", { crew = id, token = r3.dialog.token, choice = "d_1" })
          table.insert(bits, "stale=" .. tostring(r5.ok) .. "/" .. tostring(r5.close))
        end
      end
    end
    S.game:GetService("Players").LocalPlayer:SetAttribute("CrewTalkTest", table.concat(bits, " | "))
    end) if not ok then S.game:GetService("Players").LocalPlayer:SetAttribute("CrewTalkTest", "ERR " .. tostring(err)) end end) out = "spawned"`);
  for (let i = 0; i < 20; i++) { await p.waitForTimeout(1500); const t = await cli(`out = tostring(S.game:GetService("Players").LocalPlayer:GetAttribute("CrewTalkTest"))`); if (t !== 'nil') { log('talk', t); break; } }
  await p.waitForTimeout(1500);
  // G. pay
  log('pay', await srv(`${SVC} out = HOOK:Invoke("pay", "${KEY}")`));
  await p.waitForTimeout(2500);
  log('stand', await srv(`${SVC} out = HOOK:Invoke("stand")`));
  for (let i = 0; i < 6; i++) { await p.waitForTimeout(3000); await status('G' + i); }
  // H. stand-down on shift
  log('shift', await srv(`S.player:SetAttribute("OnShift", true) out = "on"`));
  await p.waitForTimeout(6000);
  await status('H');
  log('staff', await srv(`${SVC} out = "staff=" .. HOOK:Invoke("staff", "${KEY}")`));
  log('shift', await srv(`S.player:SetAttribute("OnShift", nil) out = "off"`));
  await b.close();
})();
