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


  const TVEYE = [33.0, 12.6, 299.0], TVAT = [40.5, 13.1, 299.0];
  console.log(await tp(31.5, 9.9, 300.5, 40, 299));
  await p.waitForTimeout(4000);
  const cam = async () => {
    await p.evaluate(() => CameraCtl.suspend());
    await p.evaluate((s) => { const c = Render3D.camera; c.position.fromArray(s.eye); c.up.set(0, 1, 0); c.lookAt(...s.at); c.fov = 55; c.near = 0.05; c.updateProjectionMatrix(); }, { eye: TVEYE, at: TVAT });
  };
  const snap = async (name) => { await cam(); await p.waitForTimeout(400); await cam(); await p.waitForTimeout(300); await p.screenshot({ path: `${outDir}/${name}.png` }); console.log('shot', name); };
  const stOf = async () => { const st = await cli('state', 200); const m = /state=(\w+).*?st=(-?[\d.]+)/.exec(st); return { st, state: m ? m[1] : '?', t: m ? parseFloat(m[2]) : 0 }; };
  console.log('buy', await cli('req buy {"room":1,"pack":"p4","rid":"r9a"}', 600));
  await p.waitForTimeout(2000);
  await snap('S1_ready');
  console.log('reserve', await cli(`req reserve {"room":1,"song":"${song}"}`));
  let phase = 0;
  for (let i = 0; i < 300 && phase < 9; i++) {
    const s = await stOf();
    if (i % 10 === 0) console.log('t', i, s.st.slice(0, 380));
    if (phase === 0 && s.state === 'play') {
      let r = '';
      for (let k = 0; k < 60; k++) { r = await cli('req pause {"room":1}', 120); if (/"paused":true/.test(r)) break; }
      console.log('pause', r);
      await snap('S2_title'); console.log('title', (await stOf()).st.slice(0, 380));
      console.log('resume', await cli('req pause {"room":1}', 200));
      console.log('autotap', await cli('autotap', 200));
      phase = 1;
    } else if (phase === 1 && s.state === 'play' && s.t >= 12) {
      console.log('pause', await cli('req pause {"room":1}', 200));
      console.log('petal', await cli('req cheer {"room":1,"kind":"petal"}', 200));
      await snap('S3_lyrics'); console.log('lyrics', (await stOf()).st.slice(0, 380));
      console.log('resume', await cli('req pause {"room":1}', 200));
      phase = 2;
    } else if (phase >= 1 && s.state === 'score') {
      await p.waitForTimeout(2500);
      await snap('S4_score'); console.log('end', (await stOf()).st.slice(0, 420));
      phase = 9;
    }
  }
  await b.close();
})();
