// node cabin.js <html> <outDir> <shots.json>
// shots: [{name, car:{near:[x,y,z], kind}, eye:[lx,ly,lz], at:[lx,ly,lz] (Underbody-local studs), fov, clock}]
const { chromium } = require('playwright');
const fs = require('fs');
(async () => {
  const [html, outDir, shotsFile] = process.argv.slice(2);
  const shots = JSON.parse(fs.readFileSync(shotsFile, 'utf8'));
  fs.mkdirSync(outDir, { recursive: true });
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const p = await b.newPage({ viewport: { width: +(process.env.W || 1280), height: +(process.env.H || 720) } });
  p.setDefaultTimeout(600000);
  let ready = false;
  p.on('pageerror', e => console.log('[pageerror]', e.message));
  p.on('console', m => { const t = m.text(); if (process.env.LOGALL && !/Venues|quality tier/.test(t)) console.log('[all]', (Date.now() / 1000 % 10000).toFixed(1), m.type(), t.slice(0, 300)); if (/CarInterior|carglass|Shader|shader|WebGLProgram/.test(t)) console.log('[c]', t.slice(0, 600)); if (/\[CarInterior\] ready/.test(t)) ready = true; });
  await p.goto('file://' + html);
  await p.waitForFunction(() => window.GW && GW.engine && GW.engine.running, null, { timeout: 300000 });
  for (let i = 0; i < 120 && !ready; i++) await p.waitForTimeout(1000);
  console.log('ready', ready);
  await p.evaluate(() => {
    const st = document.createElement('style'); st.textContent = '#gw-gui,#gw-hud,#gw-controls,#gw-prompts,#gw-toasts,#gw-chips,#gw-badge{display:none!important}'; document.head.appendChild(st);
    const R = Render3D, orig = R.applyChanges;
    R.applyChanges = function (list) { if (window.__clock != null && list) for (const c of list) if (c && c.op === 'lighting') { const pr = c.props || c; if (pr.ClockTime !== undefined) pr.ClockTime = window.__clock; if (pr.TimeOfDay !== undefined) delete pr.TimeOfDay; } return orig.call(this, list); };
  });
  const ev = (code) => p.evaluate((c) => GW.engine.eval(c).then((r) => String(r)).catch((e) => 'ERR ' + e), code);
  const PRE = 'local Sched = GW.require("sched") local Env = GW.require("env") local S = GW.require("services").S local DT = GW.require("datatypes").globals local CFrame, Vector3 = DT.CFrame, DT.Vector3 local out = "?"\n';
  let lastCar = null, U = null;
  for (const s of shots) {
    const key = JSON.stringify(s.car);
    if (key !== lastCar) {
      lastCar = key;
      // teleport the character next to the car, wait for its cabin, read the Underbody frame
      const [x, y, z] = s.car.near;
      const r = await ev(PRE + `Sched.runIn(Env.serverCtx, function() local ok, e = pcall(function()
        local best, bd = nil, 1e9
        -- via the server's NearLOD tags on car interiors (walking the whole workspace would load the lazy place into memory)
        for _, int in S.game:GetService("CollectionService"):GetTagged("NearLOD") do
          local d = int.Parent
          if int.Name == "Interior" and d and d:IsA("Model") and d:GetAttribute("VehicleKind") == "${s.car.kind}" then
            local u = d:FindFirstChild("Underbody") or d:FindFirstChild("Chassis", true)
            if u then local dd = (u.Position - Vector3.new(${x}, ${y}, ${z})).Magnitude if dd < bd then bd, best = dd, d end end
          end
        end
        if not best then out = "nocar" return end
        Env.__shotCar = best
        ${Object.entries(s.car.attrs || {}).map(([k, v]) => `best:SetAttribute("GwCabinParts", nil) best:SetAttribute(${JSON.stringify(k)}, ${JSON.stringify(v)})`).join(' ')}
        local u = best:FindFirstChild("Underbody") or best:FindFirstChild("Chassis", true)
        local ps = S.player:FindFirstChildOfClass("PlayerScripts")
        local sc = ps and ps:FindFirstChild("GwangalliCarInterior")
        if sc then sc:SetAttribute("FocusPoint", u.Position) end
        out = best:GetFullName() .. " d=" .. math.floor(bd) .. "|" .. tostring((u.CFrame * CFrame.new(0, 7.5, 1)).Position)
      end) if not ok then out = "ERR " .. tostring(e) end end) Sched.flush() return out`);
      console.log('car', r);
      const tp = (r.split('|')[1] || '').split(',').map(Number);

      p.evaluate(() => CameraCtl.resume && CameraCtl.resume());
      let info = '';
      for (let i = 0; i < 90; i++) {
        await p.waitForTimeout(1000);
        info = await ev(PRE + `Sched.runIn(Env.serverCtx, function()
          local m = Env.__shotCar
          local c = m and m:FindFirstChild("CabinAAA")
          local u = m and (m:FindFirstChild("Underbody") or m:FindFirstChild("Chassis", true))
          if not u then
            local ps = S.player:FindFirstChildOfClass("PlayerScripts")
            local sc = ps and ps:FindFirstChild("GwangalliCarInterior")
            local ch = S.player.Character
            local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
            out = "wait cabins=" .. tostring(sc and sc:GetAttribute("Cabins")) .. " nearest=" .. tostring(sc and sc:GetAttribute("Nearest")) .. " err=" .. tostring(m and m:GetAttribute("GwCabinError")) .. " hrp=" .. tostring(hrp and hrp.Position) .. " u=" .. tostring(u and u.Position)
            return
          end
          if false and m:GetAttribute("GwCabinParts") == nil ${s.car.style ? `or m:GetAttribute("GwCabinStyle") ~= "${s.car.style}"` : ''} then out = "wait building " .. #c:GetChildren() return end
          local cf = u.CFrame
          local a = { cf:GetComponents() }
          for k, v in a do a[k] = string.format("%.5f", v) end
          local cnt = {}
          for _, p in (c and c:GetChildren() or {}) do local n = string.gsub(p.Name, "%d+$", "") cnt[n] = (cnt[n] or 0) + 1 end
          local arr = {}
          for n, k in cnt do table.insert(arr, { n, k }) end
          table.sort(arr, function(x, y) return x[2] > y[2] end)
          local top = {}
          for i = 1, math.min(30, #arr) do table.insert(top, arr[i][1] .. "=" .. arr[i][2]) end
          out = (c and #c:GetChildren() or 0) .. " style=" .. tostring(m:GetAttribute("GwCabinStyle")) .. " [" .. table.concat(top, " ") .. "]|" .. table.concat(a, ",")
        end) Sched.flush() return out`);
        if (!info.startsWith('wait') && !info.startsWith('ERR') && info !== '?') break; if (i % 10 === 0) console.log('  ', info.slice(0, 300));
      }
      console.log('cabin', info.split('|')[0]);
      const parts = info.split('|');
      U = parts.length > 1 ? parts[1].split(',').map(Number) : null;
      if (!U) { console.log('no cabin for', s.name); lastCar = null; continue; }
      await p.evaluate(() => CameraCtl.suspend());
    }
    // 밤 사진: 실내등 미리보기 (스크립트 속성 DomeLights)
    await ev(PRE + `Sched.runIn(Env.serverCtx, function() local ps = S.player:FindFirstChildOfClass("PlayerScripts") local sc = ps and ps:FindFirstChild("GwangalliCarInterior") if sc then local nt = ${s.clock != null && (s.clock >= 18 || s.clock < 6) ? 'true' : 'false'} sc:SetAttribute("DomeLights", nt) sc:SetAttribute("NightOverride", nt) end
      pcall(function() S.game:GetService("Lighting").ClockTime = ${s.clock != null ? s.clock : 14} end) end) Sched.flush() return "ok"`);
    window_set: {
      await p.evaluate(({ s, U }) => {
        const R = Render3D, T = R.THREE;
        window.__clock = s.clock != null ? s.clock : 14; R.setLighting({ ClockTime: window.__clock });
        const m = new T.Matrix4().set(U[3], U[4], U[5], U[0], U[6], U[7], U[8], U[1], U[9], U[10], U[11], U[2], 0, 0, 0, 1);
        const eye = new T.Vector3(...s.eye).applyMatrix4(m), at = new T.Vector3(...s.at).applyMatrix4(m);
        window.__shotCam = { eye: eye.toArray(), at: at.toArray(), fov: s.fov || 70 };
      }, { s, U });
    }
    const t0 = Date.now();
    while (Date.now() - t0 < (s.wait || 3500)) {
      await p.evaluate(() => { const c = window.__shotCam; const cam = Render3D.camera; cam.position.fromArray(c.eye); cam.up.set(0, 1, 0); cam.lookAt(...c.at); cam.fov = c.fov; cam.near = 0.05; cam.updateProjectionMatrix(); });
      await p.waitForTimeout(300);
    }
    await p.screenshot({ path: outDir + '/' + s.name + '.png' });
    console.log('shot', s.name);
  }
  await b.close();
})();
