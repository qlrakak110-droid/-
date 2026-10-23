// node hosp8.js <html> <outDir> : HospitalPlus live check in the temp studio (build, state machine, portal rooms, screenshots).
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

  // 옥상 정원 · 응급실 간판 · 숨은 방 3 곳 (짧은 실행)
  await focus(W(-32, 26, 20));
  log('avatar', await avatar(W(-32, 25.2, 20)));
  let zones = '';
  for (let i = 0; i < 50; i++) {
    await p.waitForTimeout(3000);
    zones = await dbg('zones');
    if (/roof/.test(zones) && /exits/.test(zones) && /doors/.test(zones)) break;
  }
  check('build_roof_exits_doors', /roof/.test(zones) && /exits/.test(zones) && /doors/.test(zones), zones);
  await shot('roof_garden', L(-20, 35, -8), L(-40, 27, 14), 70);
  await shot('roof_pergola', L(-27, 30.5, 2.5), L(-42, 28.5, 16), 74);
  await shot('roof_view', L(-37, 30.5, -27), L(-37, 28.6, -36), 70);
  await shot('er_blade', L(66, 7, -14), L(61, 9.5, 12), 60);
  for (const [id, side, eye, at, door] of [
    ['staff', 'hall', L(-3.2, -45.0, 34.8), L(-20, -48, 25), W(-12.09, 0, 35.6)],
    ['store', 'hall', L(-16.0, -45.0, 12.8), L(-28, -48.5, 4), W(-22.09, 0, 35.6)],
    ['stair', 'hall', L(-2.2, -36.5, -8.5), L(-8, -46, -18), W(-5.95, 14.15, 36.0)],
  ]) {
    await avatar(door);
    await focus(door);
    await p.waitForTimeout(2500);
    log('go', id, await dbg(`go ${id} ${side}`));
    await p.waitForTimeout(3000);
    const s2 = await dbg('status');
    check(`portal_${id}_built`, /rooms=[1-3]/.test(s2), s2 + ' me=' + (await dbg('me')));
    await shot(`p_${id}`, eye, at, 76);
    log('back', id, await dbg(`back ${id} ${side}`));
    await p.waitForTimeout(2000);
    log('after back me=', await dbg('me'), await dbg('status'));
  }
  log('final status', await dbg('status'));
  await b.close();
})().catch((e) => { log('FATAL', String(e).slice(0, 500)); process.exit(1); });
