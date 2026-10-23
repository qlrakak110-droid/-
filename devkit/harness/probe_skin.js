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
  await p.evaluate(() => CameraCtl.suspend());
  await p.evaluate(({ s, U }) => {
    const R = Render3D, T = R.THREE;
    const m = new T.Matrix4().set(U[3], U[4], U[5], U[0], U[6], U[7], U[8], U[1], U[9], U[10], U[11], U[2], 0, 0, 0, 1);
    window.__shotCam = { eye: new T.Vector3(...s.eye).applyMatrix4(m).toArray(), at: new T.Vector3(...s.at).applyMatrix4(m).toArray(), fov: s.fov || 70 };
  }, { s, U });
  for (let k = 0; k < 10; k++) {
    await p.evaluate(() => { const c = window.__shotCam; const cam = Render3D.camera; cam.position.fromArray(c.eye); cam.up.set(0, 1, 0); cam.lookAt(...c.at); cam.fov = c.fov; cam.near = 0.05; cam.updateProjectionMatrix(); });
    await p.waitForTimeout(300);
  }
  await p.screenshot({ path: '/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/shots/pick.png' });
  const groups = [['base', null], ['trim', /trim/], ['chrome', /chrome/], ['int', /int_/], ['gloss', /gloss_black/], ['body', /^body_/], ['all_skin', /^(body_|W_|lens_)/]];
  for (const [tag, re] of groups) {
    const n = await p.evaluate((src) => {
      const re = src ? new RegExp(src) : null; let n = 0;
      Render3D.scene.traverse((o) => { if (o.userData.__v === undefined) o.userData.__v = o.visible; o.visible = o.userData.__v; });
      if (re) Render3D.scene.traverse((o) => { if (o.name && re.test(o.name)) { o.visible = false; n++; } });
      return n;
    }, re ? re.source : null);
    await p.waitForTimeout(600);
    await p.screenshot({ path: '/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/shots/skin_' + tag + '.png', clip: { x: 300, y: 380, width: 600, height: 240 } });
    console.log('group', tag, n);
  }
  const names = await p.evaluate(() => { const s = new Set(); Render3D.scene.traverse((o) => { if (o.isMesh && o.name) s.add(o.name); }); return [...s].slice(0, 200).join(' '); });
  console.log('names', names);
  await b.close();
})();
