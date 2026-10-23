// node hosp.js <html> <outDir> : HospitalPlus functional test in the temp studio (walk-through doors, lift, portals) + screenshots
const { chromium } = require('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/harness/node_modules/playwright');
const fs = require('fs');
const [html, outDir] = process.argv.slice(2);
fs.mkdirSync(outDir, { recursive: true });
const X = [0.999465, 0, 0.032713], Z = [-0.032713, 0, 0.999465];
const W = (x, y, z) => [-515 + x * X[0] + z * Z[0], 6.9 + y, 300 + x * X[2] + z * Z[2]];
const v = (a) => `Vector3.new(${a[0].toFixed(3)}, ${a[1].toFixed(3)}, ${a[2].toFixed(3)})`;
(async () => {
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const p = await b.newPage({ viewport: { width: 1280, height: 720 } });
  p.setDefaultTimeout(600000);
  p.on('pageerror', (e) => console.log('[pageerror]', e.message));
  p.on('console', (m) => { const t = m.text(); if (/HospitalPlus|Hosp_|BuildingInterior|warn|rror/.test(t) && !/dbus|DataStore/.test(t)) console.log('[c]', t.slice(0, 500)); });
  await p.goto('file://' + html);
  await p.waitForFunction(() => window.GW && GW.engine && GW.engine.running, null, { timeout: 300000 });
  console.log('engine running');
  await p.waitForTimeout(10000);
  const ev = (code) => p.evaluate((c) => GW.engine.eval(c).then((r) => String(r)).catch((e) => 'ERR ' + e), code);
  const PRE = 'local Sched = GW.require("sched") local Env = GW.require("env") local S = GW.require("services").S local DT = GW.require("datatypes").globals local CFrame, Vector3 = DT.CFrame, DT.Vector3 local out = "?"\n';
  const srv = (body) => ev(PRE + `Sched.runIn(Env.serverCtx, function() local ok, e = pcall(function()\n${body}\nend) if not ok then out = "ERR " .. tostring(e) end end) Sched.flush() return out`);
  // wait for the injected scripts
  for (let i = 0; i < 80; i++) {
    const r = await srv(`local ps = S.player and S.player:FindFirstChildOfClass("PlayerScripts") local sc = ps and ps:FindFirstChild("GwangalliBuildingInterior") out = if sc then "yes" else "no"`);
    if (r === 'yes') break;
    await p.waitForTimeout(3000);
  }
  const SC = `local sc = S.player:FindFirstChildOfClass("PlayerScripts"):FindFirstChild("GwangalliBuildingInterior")`;
  await srv(`${SC} sc:SetAttribute("Debug", true) sc:SetAttribute("FocusPoint", nil) out = "ok"`);
  const dbg = async (cmd) => {
    await srv(`${SC} sc:SetAttribute("HospDebugOut", "") sc:SetAttribute("HospDebug", "") sc:SetAttribute("HospDebug", ${JSON.stringify(cmd)}) out = "sent"`);
    await p.waitForTimeout(400);
    return srv(`${SC} out = tostring(sc:GetAttribute("HospDebugOut"))`);
  };
  // teleport (unanchored), optional face direction (world look point)
  const tp = (pos, look) => srv(`local ch = S.player.Character local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    hrp.Anchored = false
    local p0 = ${v(pos)} + Vector3.new(0, 3.2, 0)
    ch:PivotTo(CFrame.lookAt(p0, ${look ? v(look) : 'p0 + Vector3.new(0, 0, 1)'} * Vector3.new(1, 0, 1) + Vector3.new(0, p0.Y, 0)))
    hrp.AssemblyLinearVelocity = Vector3.zero
    out = "tp " .. tostring(hrp.Position)`);
  const moveTo = (pos) => srv(`local ch = S.player.Character local hum = ch:FindFirstChildOfClass("Humanoid") hum:MoveTo(${v(pos)}) out = "moving"`);
  const where = () => srv(`local hrp = S.player.Character.HumanoidRootPart local q = hrp.Position
    local d = q - Vector3.new(-515, 6.9, 300)
    local lx = d.X * 0.999465 + d.Z * 0.032713
    local lz = -d.X * 0.032713 + d.Z * 0.999465
    out = string.format("L(%.2f, %.2f, %.2f)", lx, d.Y, lz)`);
  const shot = async (name, eye, at, fov) => {
    await p.evaluate(() => CameraCtl.suspend());
    for (let k = 0; k < 8; k++) {
      await p.evaluate((s) => { const cam = Render3D.camera; cam.position.fromArray(s.eye); cam.up.set(0, 1, 0); cam.lookAt(...s.at); cam.fov = s.fov || 70; cam.near = 0.05; cam.updateProjectionMatrix(); }, { eye, at, fov });
      await p.waitForTimeout(200);
    }
    await p.waitForTimeout(1200);
    await p.screenshot({ path: `${outDir}/${name}.png` });
    await p.evaluate(() => { try { CameraCtl.resume(); } catch (e) {} });
    console.log('shot', name);
  };
  const results = [];
  const check = (name, ok, info) => { results.push(`${ok ? 'PASS' : 'FAIL'} ${name} ${info}`); console.log(ok ? 'PASS' : 'FAIL', name, info); };
  const parseL = (s) => { const m = /L\(([-\d.]+), ([-\d.]+), ([-\d.]+)\)/.exec(s); return m ? [parseFloat(m[1]), parseFloat(m[2]), parseFloat(m[3])] : null; };

  const me = async () => { const r = await dbg('me'); const a = r.split(',').map(Number); return a.length === 3 && !a.some(isNaN) ? a : null; };
  const TP = async (x, y, z, lx, lz) => {
    await dbg(`tp ${x} ${y} ${z} ${lx} ${lz}`);
    await p.waitForTimeout(800);
    let m = await me();
    if (!m || Math.abs(m[0] - x) + Math.abs(m[2] - z) > 3) {
      const a = W(x, y + 3.1, z), c = W(lx, y + 3.1, lz);
      console.log('client tp failed', JSON.stringify(m), '-> server tp');
      await srv(`local hrp = S.player.Character.HumanoidRootPart hrp.CFrame = CFrame.lookAt(${v(a)}, ${v(c)}) hrp.AssemblyLinearVelocity = Vector3.zero hrp.Anchored = true out = "ok"`);
      await p.waitForTimeout(800);
      await srv(`S.player.Character.HumanoidRootPart.Anchored = false out = "ok"`);
      await p.waitForTimeout(500);
      m = await me();
    }
    return m;
  };
  const WALK = async (x, y, z, ms) => { await dbg(`walk ${x} ${y} ${z}`); await p.waitForTimeout(ms || 4500); return me(); };
  // 0) 이동 방법 실험
  const srvPos = () => srv(`local q = S.player.Character.HumanoidRootPart.Position out = string.format("%.1f,%.1f,%.1f", q.X, q.Y, q.Z)`);
  console.log('globals', await p.evaluate(() => Object.keys(window).filter((k) => /char|Char|Ctl|ctl|Player|Avatar/.test(k)).join(',')));
  console.log('GW keys', await p.evaluate(() => Object.keys(window.GW || {}).join(',')));
  {
    const a = W(-20, 3.1, 30);
    await srv(`local hrp = S.player.Character.HumanoidRootPart hrp.CFrame = CFrame.new(${v(a)}) hrp.Anchored = true out = "ok"`);
    await p.waitForTimeout(2000);
    console.log('EXP A anchored: srv', await srvPos(), 'cli', await dbg('me'));
    await srv(`S.player.Character.HumanoidRootPart.Anchored = false out = "ok"`);
    await p.waitForTimeout(2000);
    console.log('EXP B unanchored: srv', await srvPos(), 'cli', await dbg('me'));
    await dbg('tp -25 0 30 -40 30');
    await p.waitForTimeout(2000);
    console.log('EXP C client tp: srv', await srvPos(), 'cli', await dbg('me'));
    await p.keyboard.down('w'); await p.waitForTimeout(1200); await p.keyboard.up('w');
    await p.waitForTimeout(500);
    console.log('EXP D key W: srv', await srvPos(), 'cli', await dbg('me'));
    await dbg('walk -30 0 30');
    await p.waitForTimeout(2500);
    console.log('EXP E client MoveTo: srv', await srvPos(), 'cli', await dbg('me'));
  }
  // 1) 후면 홀로 가서 짓기 기다림
  console.log('tp', await TP(-20, 0, 30, -40, 30));
  await srv(`${SC} sc:SetAttribute("FocusPoint", ${v(W(-20, 3, 30))}) out = "fp"`);
  for (let i = 0; i < 30; i++) {
    await p.waitForTimeout(4000);
    const z = await dbg('zones');
    console.log('zones', z, '|', await dbg('probe'), '|', JSON.stringify(await me()));
    if (/exits/.test(z) && /lift/.test(z) && /hall1/.test(z) && /doors/.test(z) && /level2/.test(z)) break;
  }
  console.log('status', await dbg('status'));
  if (!/hall1/.test(await dbg('zones'))) { console.log('FAIL build (no zones)'); await b.close(); process.exit(2); }
  let L;
  // 2) 화장실 입구 (여자) 걸어 들어가기 / 나오기
  console.log('tp', await TP(-49.9, 0, 24.2, -49.9, 31));
  L = await WALK(-49.9, 0, 30.6);
  check('restroom_enter', L && L[2] > 28.5, JSON.stringify(L));
  await shot('rr_women_in', W(-49.6, 6.2, 30.8), W(-57, 3, 36), 74);
  L = await WALK(-49.9, 0, 23.8);
  check('restroom_exit', L && L[2] < 26.5, JSON.stringify(L));
  // 3) 엘리베이터 1 → 2 → R → 1
  console.log('tp', await TP(-32.09, 0, 36.0, -32.09, 30));
  await p.waitForTimeout(1000);
  console.log('lift', await dbg('lift'));
  await dbg('call 2');
  await p.waitForTimeout(9000);
  L = await me();
  console.log('lift', await dbg('lift'));
  check('lift_1to2', L && L[1] > 15 && L[1] < 20, JSON.stringify(L));
  await dbg('call 3');
  await p.waitForTimeout(9000);
  L = await me();
  check('lift_2toR', L && L[1] > 26 && L[1] < 31, JSON.stringify(L) + ' ' + (await dbg('lift')));
  L = await WALK(-32.09, 25.2, 30.0, 4000);
  check('lift_exit_roof', L && L[2] < 32.8 && L[1] > 25, JSON.stringify(L));
  await shot('roof_lift', W(-32.5, 31.5, 22.0), W(-32.1, 29.5, 33.5), 70);
  await dbg('call 3');
  await p.waitForTimeout(1500);
  L = await WALK(-32.09, 25.2, 36.0, 3500);
  console.log('back in cabin', JSON.stringify(L), await dbg('lift'));
  await dbg('call 1');
  await p.waitForTimeout(11000);
  L = await me();
  check('lift_Rto1', L && L[1] > 0 && L[1] < 6, JSON.stringify(L) + ' ' + (await dbg('lift')));
  // 4) 숨은 방: 직원 휴게실 들어갔다 나오기
  console.log('tp', await TP(-12.09, 0, 35.6, -12.09, 40));
  await p.waitForTimeout(3000);
  await dbg('go staff hall');
  await p.waitForTimeout(5000);
  L = await me();
  check('portal_staff_in', L && L[1] < -40, JSON.stringify(L));
  await shot('p1_live', W(-3.5, -45.5, 34.5), W(-20, -48, 25), 74);
  await dbg('back staff hall');
  await p.waitForTimeout(4000);
  L = await me();
  check('portal_staff_out', L && L[1] > -1 && L[1] < 6 && L[2] > 33, JSON.stringify(L));
  // 비상계단: 2F 문 → 계단 걸어 올라가기는 생략, 위 문으로 옥상
  console.log('tp', await TP(-5.95, 14.15, 36.0, -5.95, 40));
  await p.waitForTimeout(2500);
  await dbg('go stair hall');
  await p.waitForTimeout(5000);
  L = await me();
  check('portal_stair_in', L && L[1] < -40, JSON.stringify(L));
  L = await WALK(-8.0, -44.475, -9.0, 6000);
  check('stair_walk_mid', L && L[1] > -45, JSON.stringify(L));
  await dbg('back stair roof');
  await p.waitForTimeout(4000);
  L = await me();
  check('portal_stair_roof', L && L[1] > 25 && L[0] > 30, JSON.stringify(L));
  // 5) 응급실 출입구: 처치실 → 밖 → 안
  console.log('tp', await TP(55.0, 0, 14.5, 62, 14.5));
  L = await WALK(64.0, -0.34, 14.5, 5000);
  check('er_out', L && L[0] > 61, JSON.stringify(L));
  await shot('er_live', W(68, 5.5, 8), W(59.5, 4, 14.5), 70);
  L = await WALK(55.0, 0, 14.5, 5000);
  check('er_in', L && L[0] < 58.5, JSON.stringify(L));
  // 6) 비상구: 안에서 밀고 나가기
  console.log('tp', await TP(56.5, 0, 29.6, 62, 29.6));
  L = await WALK(63.0, -0.34, 29.6, 5000);
  check('fire_exit_out', L && L[0] > 60.5, JSON.stringify(L));
  await WALK(70.0, -0.34, 29.6, 3000);
  await p.waitForTimeout(6000);
  L = await WALK(55.0, 0, 29.6, 6000);
  check('fire_exit_closed_blocks', L && L[0] > 59.5, JSON.stringify(L));
  // 7) 2F 계단홀 → 복도
  console.log('tp', await TP(-5.8, 14.15, 1.0, -5.8, -8));
  L = await WALK(-5.8, 14.15, -7.0, 5000);
  check('landing_passage', L && L[2] < -5.0 && L[1] > 14, JSON.stringify(L));
  await shot('pass_live', W(-2.0, 19.5, -8.0), W(-6.0, 17.5, -3.5), 74);
  // 8) 유리 자동문 (진료실 1)
  console.log('tp', await TP(-20.1, 0, -3.5, -20.1, -10));
  await p.waitForTimeout(2000);
  await shot('glass_live', W(-15.5, 5.5, -2.5), W(-21, 4, -6.5), 70);
  L = await WALK(-20.1, 0, -9.0, 4000);
  check('glass_door_pass', L && L[2] < -7.0, JSON.stringify(L));
  console.log('final status', await dbg('status'));
  fs.writeFileSync(`${outDir}/results.txt`, results.join('\n') + '\n');
  await b.close();
})().catch((e) => { console.log('FATAL', e); process.exit(1); });
