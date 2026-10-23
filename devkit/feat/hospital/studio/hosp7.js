// node hosp7.js <html> <outDir> : HospitalPlus live check in the temp studio (build, state machine, portal rooms, screenshots).
// The avatar is moved with the studio's own Character.teleport (JS) when it exists; builds follow the FocusPoint attribute.
const { chromium } = require('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/harness/node_modules/playwright');
const fs = require('fs');
const [html, outDir] = process.argv.slice(2);
fs.mkdirSync(outDir, { recursive: true });
const X = [0.999465, 0, 0.032713], Z = [-0.032713, 0, 0.999465];
const W = (x, y, z) => [-515 + x * X[0] + z * Z[0], 6.9 + y, 300 + x * X[2] + z * Z[2]];
const log = (...a) => { const s = a.join(' '); console.log(s); fs.appendFileSync(`${outDir}/log.txt`, s + '\n'); };
(async () => {
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const p = await b.newPage({ viewport: { width: 1280, height: 720 } });
  p.setDefaultTimeout(600000);
  p.on('pageerror', (e) => log('[pageerror]', e.message.slice(0, 300)));
  p.on('crash', () => log('[crash] page crashed'));
  p.on('console', (m) => { const t = m.text(); if (/HospitalPlus|Hosp_|BuildingInterior\] inject/.test(t) && !/dbus/.test(t)) log('[c]', t.slice(0, 400)); });
  await p.goto('file://' + html);
  await p.waitForFunction(() => window.GW && GW.engine && GW.engine.running, null, { timeout: 300000 });
  log('engine running');
  await p.waitForTimeout(6000);
  const api = await p.evaluate(() => {
    const C = window.Character; if (!C) return 'none';
    const ks = new Set(Object.getOwnPropertyNames(C)); let pr = Object.getPrototypeOf(C);
    while (pr && pr !== Object.prototype) { Object.getOwnPropertyNames(pr).forEach((k) => ks.add(k)); pr = Object.getPrototypeOf(pr); }
    return [...ks].filter((k) => { try { return typeof C[k] === 'function'; } catch (e) { return false; } }).join(',');
  });
  log('Character api:', api.slice(0, 600));
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
      await p.waitForTimeout(300);
      const r = await srv(`${SC} out = tostring(sc:GetAttribute("HospDebugOut"))`);
      if (r.startsWith(tag + ':')) return r.slice(tag.length + 1);
    }
    return 'TIMEOUT';
  };
  const focus = (w) => srv(`${SC} sc:SetAttribute("FocusPoint", Vector3.new(${w.map((x) => x.toFixed(2)).join(', ')})) out = "fp"`);
  const avatar = async (w) => {
    const r = await p.evaluate((pos) => { try { if (window.Character && Character.teleport) { Character.teleport(pos); return 'js'; } } catch (e) { return 'jsERR ' + e; } return 'nojs'; }, [w[0], w[1] + 3, w[2]]);
    await srv(`local hrp = S.player.Character and S.player.Character:FindFirstChild("HumanoidRootPart") if hrp then hrp.CFrame = CFrame.new(${w[0]}, ${w[1] + 3}, ${w[2]}) end out = "s"`);
    return r;
  };
  const shot = async (name, eye, at, fov) => {
    await p.evaluate(() => { try { CameraCtl.suspend(); } catch (e) {} });
    for (let k = 0; k < 6; k++) {
      await p.evaluate((s) => { const cam = Render3D.camera; cam.position.fromArray(s.eye); cam.up.set(0, 1, 0); cam.lookAt(...s.at); cam.fov = s.fov || 70; cam.near = 0.05; cam.updateProjectionMatrix(); }, { eye, at, fov });
      await p.waitForTimeout(250);
    }
    await p.waitForTimeout(1500);
    await p.screenshot({ path: `${outDir}/${name}.png` });
    await p.evaluate(() => { try { CameraCtl.resume(); } catch (e) {} });
    log('shot', name);
  };
  const results = [];
  const check = (name, ok, info) => { results.push(`${ok ? 'PASS' : 'FAIL'} ${name} ${info || ''}`); log(ok ? 'PASS' : 'FAIL', name, info || ''); fs.writeFileSync(`${outDir}/results.txt`, results.join('\n') + '\n'); };
  const L = (x, y, z) => W(x, y, z);

  // 1) 후면 홀로 → 모든 구역 짓기
  await focus(W(-20, 3, 30));
  log('avatar', await avatar(W(-20, 0, 30)));
  let zones = '';
  for (let i = 0; i < 50; i++) {
    await p.waitForTimeout(3000);
    zones = await dbg('zones');
    if (/exits/.test(zones) && /lift/.test(zones) && /hall1/.test(zones) && /doors/.test(zones) && /level2/.test(zones) && /roof/.test(zones)) break;
    if (i % 5 === 0) log('zones', zones, '|', await dbg('probe'));
  }
  check('build_all_zones', /exits/.test(zones) && /lift/.test(zones) && /hall1/.test(zones) && /doors/.test(zones) && /level2/.test(zones) && /roof/.test(zones), zones);
  log('status', await dbg('status'));
  log('me after avatar tp', await dbg('me'));

  // 2) 화장실 · 승강장 · 출입구 · 유리문 스크린숏
  await shot('rr_hall', L(-30, 5.5, 24.5), L(-50, 4, 27.5), 70);
  await shot('rr_women', L(-49.2, 6.4, 28.0), L(-56.5, 3, 35.5), 78);
  await shot('rr_men', L(-46.4, 6.4, 28.0), L(-38.5, 3.5, 36.5), 78);
  await shot('lift_1f', L(-24, 6, 26), L(-32, 4.2, 34), 70);
  await shot('lift_cabin_in', L(-30.0, 6.2, 34.2), L(-34.2, 4.0, 37.8), 80);
  await shot('er_out', L(70, 6, 5), L(59.5, 4.5, 14.5), 70);
  await shot('er_in', L(49, 5.5, 14.5), L(59, 4.5, 14.5), 70);
  await shot('fe_out', L(68, 5.5, 34), L(59.5, 4, 29.6), 70);
  await shot('fe_in', L(51, 5.5, 29.6), L(59, 4, 29.6), 70);
  await shot('glass_consult', L(-15.5, 5.5, -2.5), L(-21, 4, -6.5), 70);
  await shot('pass_2f', L(-2.0, 19.5, -8.0), L(-6, 17.5, -3.5), 74);
  await shot('glass_check2f', L(-15, 19.5, -8.5), L(-25, 18, -4.5), 70);
  await shot('stair2f_door', L(-5.9, 19.6, 30.0), L(-5.9, 18, 38.9), 72);

  // 3) 엘리베이터 상태 기계 (카 밖에서 호출: 카만 이동)
  log('lift0', await dbg('lift'));
  await dbg('call 2');
  let st = '';
  for (let i = 0; i < 20; i++) { await p.waitForTimeout(1000); st = await dbg('lift'); if (/floor=2 mode=open/.test(st)) break; }
  check('lift_to_2_open', /floor=2 mode=(open|opening)/.test(st), st);
  await shot('lift_2f_open', L(-24, 20, 26), L(-32, 18.2, 34), 70);
  await dbg('call 3');
  for (let i = 0; i < 20; i++) { await p.waitForTimeout(1000); st = await dbg('lift'); if (/floor=3 mode=open/.test(st)) break; }
  check('lift_to_R_open', /floor=3 mode=(open|opening)/.test(st), st);
  await focus(W(-32, 26, 20));
  await shot('lift_rf_open', L(-32, 31.5, 21.5), L(-32.1, 29.5, 33.5), 70);
  await shot('roof_garden', L(-20, 35, -8), L(-40, 27, 14), 70);
  await shot('roof_view', L(-37, 30.5, -27), L(-37, 28.6, -36), 70);
  await shot('roof_door', L(30, 30.5, -10), L(38, 28.5, -2.3), 70);
  await dbg('call 1');
  for (let i = 0; i < 20; i++) { await p.waitForTimeout(1000); st = await dbg('lift'); if (/floor=1 mode=(open|idle)/.test(st)) break; }
  check('lift_back_to_1', /floor=1/.test(st), st);

  // 4) 숨은 방 (페이드 이동). 스튜디오 아바타가 Luau HRP 이동을 따르지 않을 수 있어 방이 지어졌는지와 화면으로 확인
  await focus(W(-12, 3, 34));
  for (const [id, side, eye, at] of [
    ['staff', 'hall', L(-3.2, -45.0, 34.8), L(-20, -48, 25)],
    ['store', 'hall', L(-16.0, -45.0, 12.8), L(-28, -48.5, 4)],
    ['stair', 'hall', L(-2.2, -36.5, -8.5), L(-8, -46, -18)],
  ]) {
    const door = id === 'staff' ? W(-12.09, 0, 35.6) : id === 'store' ? W(-22.09, 0, 35.6) : W(-5.95, 14.15, 36.0);
    await avatar(door);
    await focus(door);
    await p.waitForTimeout(2500);
    log('go', id, await dbg(`go ${id} ${side}`));
    await p.waitForTimeout(2500);
    const s2 = await dbg('status');
    check(`portal_${id}_built`, /rooms=[1-3]/.test(s2), s2 + ' me=' + (await dbg('me')));
    await focus(W(-12, -45, 20));
    await shot(`p_${id}`, eye, at, 76);
    log('back', id, await dbg(`back ${id} ${side}`));
    await p.waitForTimeout(2500);
  }
  await focus(W(-20, 3, 30));
  await p.waitForTimeout(2000);
  log('final status', await dbg('status'));
  await b.close();
})().catch((e) => { log('FATAL', String(e).slice(0, 500)); process.exit(1); });
