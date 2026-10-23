// node bld.js <html> <outDir> <shots.json>
// shots: [{name, pos:[x,y,z] (teleport the character here, world), eye:[x,y,z], at:[x,y,z] (world), fov, clock, wait}]
const { chromium } = require('playwright');
const fs = require('fs');
(async () => {
  const [html, outDir, shotsFile] = process.argv.slice(2);
  const shots = JSON.parse(fs.readFileSync(shotsFile, 'utf8'));
  fs.mkdirSync(outDir, { recursive: true });
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const p = await b.newPage({ viewport: { width: 1280, height: 720 } });
  p.setDefaultTimeout(600000);
  p.on('pageerror', e => console.log('[pageerror]', e.message));
  p.on('console', m => { const t = m.text(); if (/Interior|error|Error|GwangalliBuilding/.test(t)) console.log('[c]', t.slice(0, 400)); });
  await p.goto('file://' + html);
  await p.waitForFunction(() => window.GW && GW.engine && GW.engine.running, null, { timeout: 300000 });
  await p.waitForTimeout(15000);
  await p.evaluate(() => {
    const st = document.createElement('style'); st.textContent = '#gw-gui,#gw-hud,#gw-controls,#gw-prompts,#gw-toasts,#gw-chips,#gw-badge,canvas~div{display:none!important}'; document.head.appendChild(st);
    const R = Render3D, orig = R.applyChanges;
    R.applyChanges = function (list) { if (window.__clock != null && list) for (const c of list) if (c && c.op === 'lighting') { const pr = c.props || c; if (pr.ClockTime !== undefined) pr.ClockTime = window.__clock; if (pr.TimeOfDay !== undefined) delete pr.TimeOfDay; } return orig.call(this, list); };
  });
  const ev = (code) => p.evaluate((c) => GW.engine.eval(c).then((r) => String(r)).catch((e) => 'ERR ' + e), code);
  const PRE = 'local Sched = GW.require("sched") local Env = GW.require("env") local S = GW.require("services").S local DT = GW.require("datatypes").globals local CFrame, Vector3 = DT.CFrame, DT.Vector3 local out = "?"\n';
  let lastPos = null;
  for (const s of shots) {
    const key = JSON.stringify(s.pos);
    if (key !== lastPos) {
      lastPos = key;
      let r = 'ERR';
      for (let tries = 0; tries < 40 && !String(r).startsWith('tp'); tries++) {
        if (tries) await p.waitForTimeout(3000);
        r = await ev(PRE + `Sched.runIn(Env.serverCtx, function() local ok, e = pcall(function()
        local ch = S.player.Character
        local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
        if hrp then hrp.CFrame = CFrame.new(${s.pos[0]}, ${s.pos[1]}, ${s.pos[2]}) hrp.Anchored = true end
        local ps = S.player:FindFirstChildOfClass("PlayerScripts")
        for _, n in { "GwangalliCarInterior", "GwangalliBuildingInterior" } do
          local sc = ps and ps:FindFirstChild(n)
          if sc then sc:SetAttribute("FocusPoint", Vector3.new(${s.pos[0]}, ${s.pos[1]}, ${s.pos[2]})) sc:SetAttribute("Debug", true) end
        end
        out = if hrp then "tp " .. tostring(hrp.Position) else "ERR nohrp"
      end) if not ok then out = "ERR " .. tostring(e) end end) Sched.flush() return out`);
      }
      console.log(s.name, r);
      // our client scripts may be injected later than the player spawns: wait until they exist, then point them here
      for (let tries = 0; tries < 60; tries++) {
        const q = await ev(PRE + `Sched.runIn(Env.serverCtx, function() local ok, e = pcall(function()
          local ps = S.player and S.player:FindFirstChildOfClass("PlayerScripts")
          local n = 0
          for _, nm in { "GwangalliCarInterior", "GwangalliBuildingInterior" } do
            local sc = ps and ps:FindFirstChild(nm)
            if sc then n += 1 sc:SetAttribute("FocusPoint", Vector3.new(${s.pos[0]}, ${s.pos[1]}, ${s.pos[2]})) sc:SetAttribute("Debug", true) end
          end
          out = "scripts " .. n
        end) if not ok then out = "ERR " .. tostring(e) end end) Sched.flush() return out`);
        if (String(q) === 'scripts 2' || (s.needScripts === 1 && String(q) !== 'scripts 0')) { console.log('focus', q); break; }
        await p.waitForTimeout(3000);
      }
      await p.waitForTimeout(s.settle || 20000);
    }
    await p.evaluate(() => CameraCtl.suspend());
    await p.evaluate((c) => { window.__clock = c; Render3D.setLighting({ ClockTime: c }); }, s.clock != null ? s.clock : 14);
    for (let k = 0; k < 12; k++) {
      await p.evaluate((s) => { const cam = Render3D.camera; cam.position.fromArray(s.eye); cam.up.set(0, 1, 0); cam.lookAt(...s.at); cam.fov = s.fov || 70; cam.near = 0.05; cam.updateProjectionMatrix(); }, s);
      await p.waitForTimeout(250);
    }
    await p.waitForTimeout(s.wait || 1500);
    await p.screenshot({ path: `${outDir}/${s.name}.png` });
    console.log('shot', s.name);
  }
  await b.close();
})();
