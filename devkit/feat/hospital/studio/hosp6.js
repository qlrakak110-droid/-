// node hosp6.js <html> <outDir> : HospitalPlus functional test in the temp studio.
// Movement goes through the HospitalPlus dev console (client side): tp = HumanoidRootPart CFrame, walk = Humanoid:MoveTo.
const { chromium } = require('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/harness/node_modules/playwright');
const fs = require('fs');
const [html, outDir] = process.argv.slice(2);
fs.mkdirSync(outDir, { recursive: true });
const X = [0.999465, 0, 0.032713], Z = [-0.032713, 0, 0.999465];
const W = (x, y, z) => [-515 + x * X[0] + z * Z[0], 6.9 + y, 300 + x * X[2] + z * Z[2]];
(async () => {
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const p = await b.newPage({ viewport: { width: 1280, height: 720 } });
  p.setDefaultTimeout(600000);
  p.on('pageerror', (e) => console.log('[pageerror]', e.message));
  p.on('console', (m) => { const t = m.text(); if (/HospitalPlus|Hosp_/.test(t) && !/dbus/.test(t)) console.log('[c]', t.slice(0, 400)); });
  await p.goto('file://' + html);
  await p.waitForFunction(() => window.GW && GW.engine && GW.engine.running, null, { timeout: 300000 });
  console.log('engine running');
  await p.waitForTimeout(8000);
  const ev = (code) => p.evaluate((c) => GW.engine.eval(c).then((r) => String(r)).catch((e) => 'ERR ' + e), code);
  const PRE = 'local Sched = GW.require("sched") local Env = GW.require("env") local S = GW.require("services").S local DT = GW.require("datatypes").globals local CFrame, Vector3 = DT.CFrame, DT.Vector3 local out = "?"\n';
  const srv = (body) => ev(PRE + `Sched.runIn(Env.serverCtx, function() local ok, e = pcall(function()\n${body}\nend) if not ok then out = "ERR " .. tostring(e) end end) Sched.flush() return out`);
  for (let i = 0; i < 80; i++) {
    const r = await srv(`local ps = S.player and S.player:FindFirstChildOfClass("PlayerScripts") local sc = ps and ps:FindFirstChild("GwangalliBuildingInterior") out = if sc then "yes" else "no"`);
    if (r === 'yes') break;
    await p.waitForTimeout(3000);
  }
  const SC = `local sc = S.player:FindFirstChildOfClass("PlayerScripts"):FindFirstChild("GwangalliBuildingInterior")`;
  await srv(`${SC} sc:SetAttribute("Debug", true) out = "ok"`);
  let nonce = 0;
  const dbg = async (cmd, ms) => {
    nonce += 1;
    const tag = 'n' + nonce;
    await srv(`${SC} sc:SetAttribute("HospDebug", ${JSON.stringify(cmd + '|' + tag)}) out = "sent"`);
    const t0 = Date.now();
    while (Date.now() - t0 < (ms || 15000)) {
      await p.waitForTimeout(250);
      const r = await srv(`${SC} out = tostring(sc:GetAttribute("HospDebugOut"))`);
      if (r.startsWith(tag + ':')) return r.slice(tag.length + 1);
    }
    return 'TIMEOUT';
  };
  const me = async () => { const r = await dbg('me'); const a = r.split(',').map(Number); return a.length === 3 && !a.some(isNaN) ? a : null; };
  const until = async (cond, ms) => { const t0 = Date.now(); let m = null; while (Date.now() - t0 < ms) { m = await me(); if (m && cond(m)) return m; await p.waitForTimeout(500); } return m; };
  const TP = async (x, y, z, lx, lz) => { await dbg(`tp ${x} ${y} ${z} ${lx} ${lz}`); return until((m) => Math.abs(m[0] - x) + Math.abs(m[2] - z) < 2.5, 6000); };
  const WALK = async (x, y, z, cond, ms) => { await dbg(`walk ${x} ${y} ${z}`); return until(cond, ms || 12000); };
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
  const check = (name, ok, info) => { results.push(`${ok ? 'PASS' : 'FAIL'} ${name} ${info}`); console.log(ok ? 'PASS' : 'FAIL', name, info); fs.writeFileSync(`${outDir}/results.txt`, results.join('\n') + '\n'); };
  const J = (a) => JSON.stringify(a && a.map((x) => Math.round(x * 100) / 100));

  // 1) 후면 홀로 이동 → 짓기
  await srv(`${SC} sc:SetAttribute("FocusPoint", Vector3.new(${W(-20, 3, 30).map((x) => x.toFixed(2)).join(', ')})) out = "fp"`);
  console.log('wake walk', await dbg('walk 230 0 -280'));
  await p.waitForTimeout(2500);
  console.log('tp', J(await TP(-20, 0, 30, -40, 30)));
  for (let i = 0; i < 40; i++) {
    await p.waitForTimeout(3000);
    const z = await dbg('zones');
    console.log('zones', z, '|', await dbg('probe'));
    if (/exits/.test(z) && /lift/.test(z) && /hall1/.test(z) && /doors/.test(z) && /level2/.test(z)) break;
  }
  if (!/hall1/.test(await dbg('zones'))) { console.log('FAIL build (no zones)'); await b.close(); process.exit(2); }
  let L;
  // 2) 여자 화장실: 입구 문 열리고 들어감 → 나옴
  await TP(-49.9, 0, 24.0, -49.9, 31);
  L = await WALK(-49.9, 0, 31.0, (m) => m[2] > 29.0);
  check('restroom_enter', L && L[2] > 29.0, J(L));
  await shot('rr_women_in', W(-49.6, 6.2, 30.8), W(-57, 3, 36), 74);
  L = await WALK(-49.9, 0, 23.8, (m) => m[2] < 25.5);
  check('restroom_exit', L && L[2] < 25.5, J(L));
  // 3) 엘리베이터 1 → 2 → R → 1 (카 안)
  await TP(-32.09, 0, 36.0, -32.09, 30);
  await p.waitForTimeout(1500);
  console.log('lift', await dbg('lift'));
  await dbg('call 2');
  L = await until((m) => m[1] > 15 && m[1] < 20, 25000);
  check('lift_1to2', L && L[1] > 15 && L[1] < 20, J(L) + ' ' + (await dbg('lift')));
  await dbg('call 3');
  L = await until((m) => m[1] > 26 && m[1] < 31, 25000);
  check('lift_2toR', L && L[1] > 26 && L[1] < 31, J(L) + ' ' + (await dbg('lift')));
  L = await WALK(-32.09, 25.2, 29.5, (m) => m[2] < 32.6, 12000);
  check('lift_exit_roof', L && L[2] < 32.6 && L[1] > 25, J(L) + ' ' + (await dbg('lift')));
  await shot('roof_lift', W(-32.5, 31.5, 22.0), W(-32.1, 29.5, 33.5), 70);
  await dbg('call 3');
  L = await WALK(-32.09, 25.2, 36.0, (m) => m[2] > 35, 12000);
  console.log('back in cabin', J(L), await dbg('lift'));
  await dbg('call 1');
  L = await until((m) => m[1] > 0 && m[1] < 6, 30000);
  check('lift_Rto1', L && L[1] > 0 && L[1] < 6, J(L) + ' ' + (await dbg('lift')));
  // 4) 직원 휴게실 (숨은 방) 들어갔다 나오기
  await TP(-12.09, 0, 35.6, -12.09, 40);
  await p.waitForTimeout(2500);
  await dbg('go staff hall');
  L = await until((m) => m[1] < -40, 15000);
  check('portal_staff_in', L && L[1] < -40 && Math.abs(L[0] + 12.1) < 2 && Math.abs(L[2] - 24.6) < 2, J(L));
  await shot('p1_live', W(-3.5, -45.5, 34.5), W(-20, -48, 25), 74);
  await p.waitForTimeout(1500);
  await dbg('back staff hall');
  L = await until((m) => m[1] > -1 && m[1] < 6, 15000);
  check('portal_staff_out', L && L[1] > -1 && L[1] < 6 && L[2] > 33, J(L));
  // 비상계단: 2F 문 → 계단으로 중간참까지 걸어 올라감 → 위 문으로 옥상
  await TP(-5.95, 14.15, 36.0, -5.95, 40);
  await p.waitForTimeout(2500);
  await dbg('go stair hall');
  L = await until((m) => m[1] < -40, 15000);
  check('portal_stair_in', L && L[1] < -40 && Math.abs(L[0] + 8.0) < 2, J(L));
  L = await WALK(-8.0, -44.475, -9.0, (m) => m[1] > -42, 15000);
  check('stair_walk_mid', L && L[1] > -42, J(L));
  await shot('p3_live', W(-2.0, -36, -9.0), W(-8, -46, -18), 74);
  await dbg('back stair roof');
  L = await until((m) => m[1] > 25, 15000);
  check('portal_stair_roof', L && L[1] > 25 && L[0] > 30, J(L));
  // 5) 응급실 출입구: 처치실 → 밖 → 안
  await TP(55.0, 0, 14.5, 62, 14.5);
  L = await WALK(64.0, -0.34, 14.5, (m) => m[0] > 61.5, 12000);
  check('er_out', L && L[0] > 61.5, J(L));
  await shot('er_live', W(68, 5.5, 8), W(59.5, 4, 14.5), 70);
  L = await WALK(55.0, 0, 14.5, (m) => m[0] < 58.0, 12000);
  check('er_in', L && L[0] < 58.0, J(L));
  // 6) 비상구: 안에서 걸어가면 패닉바가 밀려 열리고 나감. 멀리 갔다가 닫힌 뒤 다시 들어오려 하면 막힘
  await TP(56.5, 0, 29.6, 62, 29.6);
  L = await WALK(63.0, -0.34, 29.6, (m) => m[0] > 61.0, 12000);
  check('fire_exit_out', L && L[0] > 61.0, J(L));
  await WALK(72.0, -0.34, 29.6, (m) => m[0] > 70, 8000);
  await p.waitForTimeout(6000);
  L = await WALK(55.0, 0, 29.6, (m) => m[0] < 59.0, 8000);
  check('fire_exit_closed_blocks', L && L[0] > 59.5, J(L));
  // 7) 2F 계단홀 → 복도 (새 통로)
  await TP(-5.8, 14.15, 1.0, -5.8, -8);
  L = await WALK(-5.8, 14.15, -7.0, (m) => m[2] < -5.0, 12000);
  check('landing_passage', L && L[2] < -5.0 && L[1] > 14, J(L));
  await shot('pass_live', W(-2.0, 19.5, -8.0), W(-6.0, 17.5, -3.5), 74);
  // 8) 유리 자동문 (진료실 1)
  await TP(-20.1, 0, -3.5, -20.1, -10);
  await p.waitForTimeout(2500);
  await shot('glass_live', W(-15.5, 5.5, -2.5), W(-21, 4, -6.5), 70);
  L = await WALK(-20.1, 0, -9.0, (m) => m[2] < -7.0, 12000);
  check('glass_door_pass', L && L[2] < -7.0, J(L));
  console.log('final status', await dbg('status'));
  await b.close();
})().catch((e) => { console.log('FATAL', e); process.exit(1); });
