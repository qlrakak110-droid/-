// node kp.js <html> <outDir> : GwangalliKaraokePlus functional test in the temp studio
const { chromium } = require('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/harness/node_modules/playwright');
const fs = require('fs');
const [html, outDir, song = 's54'] = process.argv.slice(2);
fs.mkdirSync(outDir, { recursive: true });
(async () => {
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required'] });
  const p = await b.newPage({ viewport: { width: 1280, height: 720 } });
  p.setDefaultTimeout(600000);
  p.on('pageerror', (e) => console.log('[pageerror]', e.message));
  p.on('console', (m) => { const t = m.text(); if (/KaraokePlus|\[KP\]|GwKP|Karaoke/.test(t) && !/dbus/.test(t)) console.log('[c]', t.slice(0, 600)); });
  await p.goto('file://' + html);
  await p.waitForFunction(() => window.GW && GW.engine && GW.engine.running, null, { timeout: 300000 });
  console.log('engine running');
  await p.waitForFunction(() => window.__kpInjected === true, null, { timeout: 300000 });
  console.log('injected');
  const ev = (code) => p.evaluate((c) => GW.engine.eval(c).then((r) => String(r)).catch((e) => 'ERR ' + e), code);
  const PRE = 'local Sched = GW.require("sched") local Env = GW.require("env") local S = GW.require("services").S local DT = GW.require("datatypes").globals local CFrame, Vector3 = DT.CFrame, DT.Vector3 local out = "?"\n';
  const srv = (body) => ev(PRE + `Sched.runIn(Env.serverCtx, function() local ok, e = pcall(function()\n${body}\nend) if not ok then out = "ERR " .. tostring(e) end end) Sched.flush() return out`);
  const SC = `local sc = S.player:FindFirstChildOfClass("PlayerScripts"):FindFirstChild("GwangalliKaraokePlus")`;
  const cli = async (cmd, waitMs = 600) => {
    await srv(`${SC} sc:SetAttribute("KPDebugOut", "") sc:SetAttribute("KPDebug", "") sc:SetAttribute("KPDebug", ${JSON.stringify(cmd)}) out = "sent"`);
    for (let i = 0; i < 30; i++) {
      await p.waitForTimeout(waitMs);
      const r = await srv(`${SC} out = tostring(sc:GetAttribute("KPDebugOut"))`);
      if (r && r !== '' && r !== 'nil') return r;
    }
    return 'timeout';
  };
  const shot = async (name, eye, at, fov) => {
    if (eye) {
      await p.evaluate(() => CameraCtl.suspend());
      for (let k = 0; k < 6; k++) {
        await p.evaluate((s) => { const cam = Render3D.camera; cam.position.fromArray(s.eye); cam.up.set(0, 1, 0); cam.lookAt(...s.at); cam.fov = s.fov || 60; cam.near = 0.05; cam.updateProjectionMatrix(); }, { eye, at, fov });
        await p.waitForTimeout(200);
      }
    }
    await p.screenshot({ path: `${outDir}/${name}.png` });
    if (eye) await p.evaluate(() => { try { CameraCtl.resume(); } catch (e) {} });
    console.log('shot', name);
  };
  // wait for the server to be active
  for (let i = 0; i < 60; i++) {
    const r = await srv(`local RS = S.game:GetService("ReplicatedStorage") local sh = RS:FindFirstChild("GwangalliKaraokeShared") out = tostring(sh and sh:GetAttribute("Active"))`);
    if (r === 'true') break;
    await p.waitForTimeout(2000);
  }
  console.log('server', await srv(`local RS = S.game:GetService("ReplicatedStorage") local sh = RS.GwangalliKaraokeShared local st = sh:FindFirstChild("State")
    local n = 0 for _, c in (st and st:GetChildren() or {}) do n += 1 end
    local b1 = nil for _, d in S.game.Workspace:GetDescendants() do if d.Name == "Booth_01" then b1 = d break end end
    local pr = b1 and b1:FindFirstChild("GwangalliKaraokePrompt", true)
    out = string.format("rooms=%d legacyPrompt=%s enabled=%s KRenter=%s GwKP=%s", n, tostring(pr ~= nil), tostring(pr and pr.Enabled), tostring(b1 and b1:GetAttribute("KRenter")), tostring(S.game.Workspace:GetAttribute("GwKaraokePlus")))`));
  // corridor shot of booth 01 panel / tv lite
  const tp = async (x, y, z, lx, lz) => {
    await srv(`pcall(function()
      for _, c in S.game:GetService("ServerScriptService"):GetChildren() do
        if c.Name == "GwangalliGameplay" and c:IsA("Folder") then local L = require(c.VenueLife) if L.ctx then L.ctx.allowTeleport(S.player, 600) end end
      end
    end) out = "ok"`);
    await p.evaluate((q) => Character.teleport(q), [x, y, z]);
    await p.waitForTimeout(1500);
    return srv(`local hrp = S.player.Character.HumanoidRootPart out = "tp " .. tostring(hrp.Position)`);
  };
  console.log(await tp(31.5, 9.9, 300.5, 40, 299));
  await p.waitForTimeout(4000);
  console.log('inside', await cli('state'));
  await shot('A1_idle_tv', [33.0, 12.6, 299.0], [40.5, 13.1, 299.0], 55);
  console.log('buy', await cli('req buy {"room":1,"pack":"p4","rid":"lean1"}', 800));
  console.log('tempo', await cli('req set {"room":1,"tempo":4}'));
  console.log('reserve', await cli(`req reserve {"room":1,"song":"${song}"}`));
  let shots = {};
  for (let i = 0; i < 90; i++) {
    await p.waitForTimeout(800);
    const st = await cli('state', 250);
    const m = /state=(\w+).*?st=(-?[\d.]+)/.exec(st);
    if (!m) continue;
    const state = m[1], t = parseFloat(m[2]);
    if (i % 5 === 0) console.log('t', i, st.slice(0, 300));
    if (state === 'play' && !shots.title) { shots.title = 1; await shot('A2_title', [33.0, 12.6, 299.0], [40.5, 13.1, 299.0], 55); }
    else if (state === 'play' && t > 8 && !shots.lyr) { shots.lyr = 1; await shot('A3_lyrics', [33.0, 12.6, 299.0], [40.5, 13.1, 299.0], 55); }
    else if ((state === 'settle') && !shots.settle) { shots.settle = 1; await shot('A4_settle', [33.0, 12.6, 299.0], [40.5, 13.1, 299.0], 55); }
    else if (state === 'score' && !shots.score) { shots.score = 1; await p.waitForTimeout(2000); await shot('A5_score', [33.0, 12.6, 299.0], [40.5, 13.1, 299.0], 55); console.log('score', st.slice(0, 400)); break; }
  }
  console.log('server after song', await srv(`local RS = S.game:GetService("ReplicatedStorage") local st = RS.GwangalliKaraokeShared.State
    local r = st:FindFirstChild("Room_01")
    out = string.format("Result=%s Credits=%s King=%s Chart=%s", tostring(r:GetAttribute("Result")), tostring(r:GetAttribute("Credits")), tostring(st:GetAttribute("King")), string.sub(tostring(st:GetAttribute("Chart")), 1, 80))
    local led = nil for _, d in S.game.Workspace:GetDescendants() do if d.Name == "LEDScreen" then led = d break end end
    out ..= " LED=" .. tostring(led and led:GetAttribute("Messages"))`));
  console.log('cheer', await cli('req cheer {"room":1,"kind":"fire"}'));
  await p.waitForTimeout(600);
  await shot('A6_fx', [26.5, 13.5, 302.5], [38, 11, 298], 70);
  await b.close();
})();
