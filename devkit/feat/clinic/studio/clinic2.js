// node clinic2.js <html> <outDir>: injects GwangalliClinic into the temp studio and drives a REAL visit through
// the client UI (prompt handlers + mouse clicks on our buttons), the avatar moved with Character.teleport (JS).
const { chromium } = require('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/harness/node_modules/playwright');
const fs = require('fs');
const path = require('path');
(async () => {
  const [html, outDir] = process.argv.slice(2);
  fs.mkdirSync(outDir, { recursive: true });
  const codes = JSON.parse(fs.readFileSync(path.join(__dirname, 'inject.json'), 'utf8'));
  codes[0] = codes[0].replace('Config.Debug = false', 'Config.Debug = true');
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const p = await b.newPage({ viewport: { width: 1280, height: 720 } });
  p.setDefaultTimeout(600000);
  const T0 = Date.now();
  const log = (...a) => console.log(`[${((Date.now() - T0) / 1000).toFixed(0)}s]`, ...a);
  p.on('pageerror', e => log('[pageerror]', e.message.slice(0, 300)));
  p.on('console', m => { const t = m.text(); if (/Clinic|clinic/.test(t)) log('[c]', t.slice(0, 400)); });
  await p.goto('file://' + html);
  await p.waitForFunction(() => window.GW && GW.engine && GW.engine.running, null, { timeout: 400000 });
  log('engine running');
  await p.waitForTimeout(10000);
  const ev = (code) => p.evaluate((c) => GW.engine.eval(c).then((r) => String(r)).catch((e) => 'ERR ' + e), code);
  log('shared', await ev(codes[0]));
  log('server', await ev(codes[1]));
  await p.waitForTimeout(3000);
  log('client', await ev(codes[2]));
  log('helper', await ev(codes[3]));
  log('client helper', await ev(codes[4]));
  const PRE = 'local Sched = GW.require("sched") local Env = GW.require("env") local S = GW.require("services").S local DT = GW.require("datatypes").globals local CFrame, Vector3 = DT.CFrame, DT.Vector3 local out = "?"\n';
  const srv = (body) => ev(PRE + `Sched.runIn(Env.serverCtx, function() local ok, e = pcall(function()
    local game = S.game
    local workspace = game:GetService("Workspace")
    local RS = game:GetService("ReplicatedStorage")
    local SS = game:GetService("ServerStorage")
    local P = S.player
    ${body}
  end) if not ok then out = "ERR " .. tostring(e) end end) Sched.flush() return out`);
  const CC = `local CC = Env.clientCtx or (Env.peers and Env.peers.client and (Env.peers.client.ctx or Env.peers.client))`;
  const cli = (body) => ev(PRE + CC + `\nif not CC then return "NOCLIENT" end Sched.runIn(CC, function() local ok, e = pcall(function()
    local game = S.game
    local RS = game:GetService("ReplicatedStorage")
    local P = S.player
    local PS = P:FindFirstChildOfClass("PlayerScripts")
    ${body}
  end) if not ok then out = "ERR " .. tostring(e) end end) Sched.flush() return out`);
  // commands for the client helper LocalScript (runs inside the client VM, can require our modules)
  let cseq = 0;
  async function ccmd(cmd, arg, timeout) {
    cseq += 1;
    const key = 'C' + cseq;
    const r = await cli(`PS.ClinicClientTest:SetAttribute("Cmd", ${JSON.stringify(key + '|' + cmd + '|' + (arg || ''))}) out = "sent"`);
    if (r !== 'sent') return 'ERR ' + r;
    for (let i = 0; i < (timeout || 20) * 4; i++) {
      await p.waitForTimeout(250);
      const v = await cli(`out = tostring(PS.ClinicClientTest:GetAttribute("${key}") or "?")`);
      if (v !== '?') return v;
    }
    return 'TIMEOUT';
  }
  const call = (fn, arg) => ccmd('call', fn + (arg ? '|' + arg : ''));
  let seq = 0;
  async function op(kind, aLua, bLua, cLua, timeout) {
    seq += 1;
    const key = 'T' + seq;
    const r = await srv(`out = SS.ClinicTest:Invoke("${kind}", "${key}", ${aLua || 'nil'}, ${bLua || 'nil'}, ${cLua || 'nil'})`);
    if (!String(r).startsWith('spawned')) { log('op spawn failed', r); return {}; }
    for (let i = 0; i < (timeout || 30) * 2; i++) {
      await p.waitForTimeout(500);
      const v = await srv(`out = SS.ClinicTest:GetAttribute("${key}") or "?"`);
      if (v !== '?') { try { return JSON.parse(v) || {}; } catch (e) { return { raw: v }; } }
    }
    return { timeout: true };
  }
  const visit = async () => { const v = await op('clinic', '"visit"'); return (v && v.step) ? v : { none: true }; };
  const state = () => op('state');
  const j = (x, n) => JSON.stringify(x === undefined ? null : x).slice(0, n || 600);
  async function waitStep(steps, secs) {
    for (let i = 0; i < secs; i++) {
      const v = await visit();
      if (steps.includes(v.step) || (steps.includes('none') && v.none)) return v;
      await p.waitForTimeout(1000);
    }
    return await visit();
  }
  // avatar: the studio's JS character controller owns the avatar (the server sees it a moment later)
  async function tp(anchor, dx, dz) {
    const pos = await srv(`local a = workspace.GwangalliClinic.Anchors:FindFirstChild("${anchor}") out = a and string.format("%.2f,%.2f,%.2f", a.Position.X, a.Position.Y, a.Position.Z) or "none"`);
    if (!/^-?\d/.test(pos)) { log('tp no anchor', anchor, pos); return; }
    const w = pos.split(',').map(Number);
    w[0] += dx || 0; w[2] += dz || 0;
    const r = await p.evaluate((q) => { try { if (window.Character && Character.teleport) { Character.teleport(q); return 'js'; } } catch (e) { return 'jsERR ' + e; } return 'nojs'; }, [w[0], w[1] + 1.5, w[2]]);
    await p.waitForTimeout(2500);
    const st = await state();
    log('tp', anchor, r, 'server pos', st.pos);
  }
  async function shot(name, eye, at) {
    if (eye) {
      await p.evaluate(() => { try { CameraCtl.suspend(); } catch (e) {} });
      for (let k = 0; k < 6; k++) {
        await p.evaluate(([e, a]) => { const cam = Render3D.camera; cam.position.fromArray(e); cam.up.set(0, 1, 0); cam.lookAt(...a); cam.fov = 70; cam.near = 0.05; cam.updateProjectionMatrix(); }, [eye, at]);
        await p.waitForTimeout(200);
      }
    } else {
      await p.waitForTimeout(600);
    }
    await p.screenshot({ path: `${outDir}/${name}.png` });
    log('shot', name);
    if (eye) await p.evaluate(() => { try { CameraCtl.resume && CameraCtl.resume(); } catch (e) {} });
  }
  // finds a visible button of our ScreenGui whose text (or a descendant label's) contains `pat`; returns screen coords
  async function findBtn(pat) {
    const r = await ccmd('find', pat, 6);
    if (!/^\d/.test(r)) return null;
    const [x, y, iy] = r.split(',').map(Number);
    return { x, y: y + iy };
  }
  async function click(pat, tries) {
    for (let i = 0; i < (tries || 12); i++) {
      const c = await findBtn(pat);
      if (c) { await p.mouse.click(c.x, c.y); log('click', pat, c.x, c.y); await p.waitForTimeout(700); return true; }
      await p.waitForTimeout(700);
    }
    log('click FAILED', pat);
    return false;
  }
  async function hold(pat, ms) {
    for (let i = 0; i < 12; i++) {
      const c = await findBtn(pat);
      if (c) { await p.mouse.move(c.x, c.y); await p.mouse.down(); await p.waitForTimeout(ms); await p.mouse.up(); log('hold', pat); await p.waitForTimeout(500); return true; }
      await p.waitForTimeout(700);
    }
    log('hold FAILED', pat);
    return false;
  }
  const hideGameUi = async () => 'helper hides popups';
  // ---- boot
  let st = '?';
  for (let i = 0; i < 40; i++) {
    st = await srv(`local sh = RS:FindFirstChild("GwangalliClinicShared") local s = sh and sh:FindFirstChild("State") out = "active=" .. tostring(s and s:GetAttribute("Active"))`);
    if (st === 'active=true') break;
    await p.waitForTimeout(4000);
  }
  log('boot', st);
  log('world', j(await op('world'), 900));
  log('setup', j(await op('gp', '"earn"', '400000', '"test"')), j(await op('health', '"setFatigue"', '91')), j(await op('health', '"makeIll"', '"cold"')));
  log('hide', await hideGameUi());
  for (let i = 0; i < 30; i++) { const r = await cli(`out = tostring(PS:FindFirstChild("ClinicClientTest") and PS.ClinicClientTest:GetAttribute("Ready"))`); if (r === 'true') { log('client helper ready'); break; } await p.waitForTimeout(1000); }
  // ---- A. 번호표
  await tp('Kiosk', 0, -1.5);
  await p.waitForTimeout(3000);
  log('hide', await hideGameUi());
  await shot('00_lobby', [-505, 13.5, 268], [-508, 12, 290]);
  log('kiosk', await call('Desk.openKiosk'));
  await p.waitForTimeout(2500);
  await shot('01_kiosk');
  await click('내과');
  await p.waitForTimeout(2000);
  await shot('02_ticket');
  log('v', j(await visit(), 300));
  await click('대기실에서 기다릴게요');
  // ---- B. 창구 호출 → 접수
  let v = await waitStep(['desk_called'], 60);
  log('called', v.step, v.window, v.target);
  await p.waitForTimeout(500);
  await shot('03_call_banner', [-504, 12.5, 270], [-510.8, 14.6, 291.7]);
  await tp(v.target || 'Win1', 0, -1);
  log('register', await call('Desk.beginRegister'));
  await click('신분증');
  await click('네');
  await click('알겠어요', 3);
  await p.waitForTimeout(1500);
  await shot('04_form');
  await click('문진표 제출');
  v = await visit(); log('after register', v.step, v.deptName);
  // ---- C. 대기 → 잡지
  await tp('Magazine', 0, -2);
  log('mag', await call('Lounge.openMagazine'));
  await p.waitForTimeout(1500);
  await shot('05_magazine');
  await ccmd('close');
  await shot('06_wait_tv', [-462, 11, 281], [-468.8, 14.2, 293]);
  v = await waitStep(['consult_called'], 90);
  log('consult called', v.step);
  // ---- D. 진료실
  await tp('ConsultSeat', 0, 0);
  log('enter', await call('Consult.enter'));
  await p.waitForTimeout(2500);
  await click('있어요');
  await click('부터요');
  await p.waitForTimeout(2500);
  for (let k = 0; k < 14; k++) {
    v = await visit();
    if (v.step !== 'consult' || (v.exams && v.examIdx > v.exams.length)) break;
    const kind = v.exams && v.exams[v.examIdx - 1];
    log('exam', v.examIdx, kind);
    if (kind === 'throat') await hold('아~', 1800);
    else if (kind === 'stetho') { await hold('들이쉬기 1/2', 1700); await p.waitForTimeout(1500); await hold('들이쉬기 2/2', 1700); }
    else if (kind === 'bp') { for (let t = 0; t < 7; t++) { await click('펌프', 2); } }
    else if (kind === 'palp') { await click('명치', 2); await click('오른쪽 아래', 2); await click('왼쪽 아래', 2); await click('아파요', 3); await click('괜찮아요', 2); }
    else if (kind === 'talk') { await click('알바', 3); await click('적당히', 2); }
    else await p.waitForTimeout(3000);
    if (k === 2) await shot('07_consult_exam');
  }
  await p.waitForTimeout(4000);
  await shot('08_dx');
  await click('치료 계획 보기');
  await p.waitForTimeout(1500);
  await shot('09_plans');
  await click('권장');
  v = await waitStep(['treat_go', 'iv_go', 'pay_go'], 25); log('after plan', v.step, j(v.plan && { id: v.plan.id, total: v.plan.total }));
  // ---- E. 처치
  await tp('ExamBed', 0, -2.5);
  log('treat', await call('Treat.start'));
  await p.waitForTimeout(1500);
  await shot('10_inject');
  await click('힘 빼기', 4);
  await p.waitForTimeout(1500);
  log('during', j(await state()));
  v = await waitStep(['pay_go', 'iv_go'], 20); log('after treat', v.step, j(await state()));
  // ---- F. 수납
  await tp('Win1', 0, -1);
  log('bill', await call('Desk.openBill'));
  await p.waitForTimeout(2500);
  await shot('11_receipt');
  if (!(await click('체크카드', 3))) await click('영수증 받기', 3);
  await p.waitForTimeout(2000);
  await shot('12_rx');
  await click('약국으로 가기', 3);
  // ---- G. 약국
  await tp('Pharmacy', 0, -1);
  log('rx', await call('Pharmacy.submit'));
  await p.waitForTimeout(2500);
  await shot('13_pharmacy_screen', [-538, 11.5, 290], [-536, 11.5, 299.3]);
  v = await waitStep(['pharm_ready'], 25); log('rx ready', v.step);
  log('collect', await call('Pharmacy.collect'));
  await p.waitForTimeout(2500);
  await shot('14_bag');
  await click('지금 한 번 먹기', 3);
  await p.waitForTimeout(2000);
  await shot('15_summary');
  log('state after visit', j(await state()), j(await op('clinic', '"health"'), 500));
  await click('확인', 3);
  // ---- H. 건강검진 (2F)
  await tp('CheckDesk', 0, -1.5);
  log('chk', await call('Checkup.desk'));
  await click('네', 4);
  await p.waitForTimeout(1500);
  v = await visit(); log('chk step', v.step);
  for (const [sid, anchor] of [['height', 'CheckScale'], ['bp', 'CheckBP'], ['eye', 'CheckEye'], ['ear', 'CheckEar'], ['ecg', 'CheckECG']]) {
    await tp(anchor, 0, 0);
    log('station', sid, await call('Checkup.station', sid));
    await p.waitForTimeout(2500);
    if (sid === 'eye') {
      v = await visit();
      const seqs = (v.chk && v.chk.cur && v.chk.cur.challenge && v.chk.cur.challenge.seq) || [];
      const arrow = { up: '↑', down: '↓', left: '←', right: '→' };
      await shot('16_eye');
      for (const it of seqs) await click(arrow[it.dir], 2);
    } else if (sid === 'ear') {
      await shot('17_ear');
      await p.waitForTimeout(16000);
    } else if (sid === 'ecg') {
      await shot('18_ecg');
      await p.waitForTimeout(6000);
    } else {
      await p.waitForTimeout(6000);
    }
    v = await visit();
    log('after', sid, j(v.chk && v.chk.stations.map(s => s.id + ':' + s.done + ':' + s.text)));
  }
  await tp('CheckDesk', 0, -1.5);
  log('chk result', await call('Checkup.desk'));
  await p.waitForTimeout(3500);
  await shot('19_report');
  await click('확인', 3);
  // ---- I. 병실 휴식
  await tp('Ward1A', 0, -2);
  log('rest', await ccmd('net', 'ward|{"action":"rest"}'));
  await p.waitForTimeout(3000);
  log('call', await ccmd('net', 'ward|{"action":"call"}'));
  await p.waitForTimeout(2000);
  await shot('20_ward', [-470, 26.5, 287], [-466.5, 23.5, 279]);
  log('final', j(await state()), j(await op('clinic', '"health"'), 400));
  // ---- J. alt flows through the server router (same checks): tired → 영양수액 (IV + nap) → 미납 → 퇴원 수속
  if (Date.now() - T0 < 1050000) {
    const inv = (opName, payloadLua) => op('clinic', '"invoke"', `"${opName}"`, payloadLua || '{}');
    log('leave rest', j(await inv('ward', '{ action = "leave" }')));
    log('tired', j(await op('health', '"setFatigue"', '82')));
    await tp('Kiosk', 0, -1.5);
    let r = await inv('ticket', '{ dept = "fm" }'); log('ticket2', r.ok, r.code, r.message, r.visit && r.visit.dept);
    r = await inv('cancel'); log('cancel free', r.ok, r.code, j(await visit(), 80));
    r = await inv('ticket', '{ dept = "fm" }'); log('ticket3', r.ok, r.code, r.message);
    v = await waitStep(['desk_called'], 60); await tp(v.target || 'Win1', 0, -1);
    r = await inv('desk'); log('desk2', r.ok, r.code, r.message);
    r = await inv('register', '{ purpose = "tired", symptoms = { "tired", "shoulder" } }'); log('register2', r.ok, r.code, r.visit && r.visit.dept);
    v = await waitStep(['consult_called'], 90); await tp('ConsultSeat', 0, 0);
    r = await inv('enter'); log('enter2', r.ok, r.code, r.message);
    for (const k of ((r.visit && r.visit.exams) || [])) { await p.waitForTimeout(1300); const e = await inv('exam', `{ kind = "${k}" }`); if (e.done && e.visit) log('plans2', j((e.visit.plans || []).map(x => [x.id, x.title, x.total, x.short]), 900)); }
    await p.waitForTimeout(9000);
    r = await inv('plan', '{ id = "M" }'); log('plan M', r.ok, r.code, r.message, r.visit && r.visit.step);
    await tp('ExamBed', 0, -2.5);
    r = await inv('treat', '{ action = "start" }'); log('treat2', r.ok, r.code, r.message, r.fee);
    v = await waitStep(['iv_go'], 20); log('iv_go bed', v.step, v.target);
    await tp(v.target || 'TreatBed1', 0, -3);
    r = await inv('treat', '{ action = "start" }'); log('iv start', r.ok, r.code, r.message, r.visit && r.visit.step);
    await p.waitForTimeout(2500);
    log('lying', j(await state()));
    await shot('21_iv_bed', [-470.5, 13, 302], [-465.3, 9.3, 309]);
    r = await inv('treat', '{ action = "nap" }'); log('nap', r.ok, r.code);
    v = await waitStep(['pay_go'], 45); log('after iv', v.step, j(await state()));
    await tp('Win2', 0, -1);
    r = await inv('pay', '{ action = "view" }'); log('bill2', j(r.bill && r.bill.sum));
    r = await inv('pay', `{ action = "defer", bill = "${r.bill && r.bill.id}" }`); log('defer', r.ok, r.code, r.message);
    log('debt', j((await op('clinic', '"health"')).debt));
    r = await inv('pay', '{ action = "view" }'); log('ward bill', r.ok, r.code, r.message, j(r.bill && r.bill.sum));
    r = await inv('pay', `{ action = "pay", method = "cash", bill = "${r.bill && r.bill.id}" }`); log('ward pay', r.ok, r.code, r.message);
    log('debt after', j((await op('clinic', '"health"')).debt), j(await state()));
  }
  await b.close();
  log('done');
})().catch((e) => { console.log('FATAL', e); process.exit(1); });
