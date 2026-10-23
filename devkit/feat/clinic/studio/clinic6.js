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
  // the loaded machine runs the studio at a few fps: stretch the clinic's patience timers for the test
  for (const [a, bb] of [['ConsultTimeout = 300', 'ConsultTimeout = 1500'], ['RegisterTimeout = 240', 'RegisterTimeout = 1500'], ['GoTimeout = 180', 'GoTimeout = 1500'], ['CallTimeout = 60', 'CallTimeout = 900']]) {
    if (!codes[0].includes(a)) console.log('config override missing', a);
    codes[0] = codes[0].replace(a, bb);
  }
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const p = await b.newPage({ viewport: { width: 960, height: 540 } });
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
    await op('allow', '900');
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
  // the studio samples input once per (slow) frame: hold each key long enough to be seen
  const key = async (k, wait) => { await p.keyboard.down(k); await p.waitForTimeout(950); await p.keyboard.up(k); log('key', k); await p.waitForTimeout(wait || 900); };
  // waits until a visible button with this text exists (a dialog choice / sheet button), then presses the key
  const pick = async (pat, k, secs) => {
    for (let i = 0; i < (secs || 25); i++) { if (await findBtn(pat)) { await p.waitForTimeout(400); await key(k || 'Digit1', 1200); return true; } await p.waitForTimeout(700); }
    log('pick FAILED', pat); return false;
  };
  const holdKey = async (k, ms) => { await p.keyboard.down(k); await p.waitForTimeout(ms); await p.keyboard.up(k); log('holdKey', k, ms); await p.waitForTimeout(600); };
  const camInfo = () => cli(`local cam = game:GetService("Workspace").CurrentCamera out = tostring(cam.CameraType) .. " " .. tostring(cam.CFrame.Position)`);
  // ---- boot
  let st = '?';
  for (let i = 0; i < 40; i++) {
    st = await srv(`local sh = RS:FindFirstChild("GwangalliClinicShared") local s = sh and sh:FindFirstChild("State") out = "active=" .. tostring(s and s:GetAttribute("Active"))`);
    if (st === 'active=true') break;
    await p.waitForTimeout(4000);
  }
  log('boot', st);
  log('setup', j(await op('gp', '"earn"', '400000', '"test"')), j(await op('health', '"setFatigue"', '91')), j(await op('health', '"makeIll"', '"cold"')));
  for (let i = 0; i < 30; i++) { const r = await cli(`out = tostring(PS:FindFirstChild("ClinicClientTest") and PS.ClinicClientTest:GetAttribute("Ready"))`); if (r === 'true') { log('client helper ready'); break; } await p.waitForTimeout(1000); }
  const inv = (opName, payloadLua) => op('clinic', '"invoke"', `"${opName}"`, payloadLua || '{}');
  const fix = async () => { const st0 = await state(); if (String(st0.pos).includes('nan')) { log('respawn (studio NaN)', j(await op('respawn'))); await p.waitForTimeout(3000); } };
  await p.mouse.click(480, 120);
  const money0 = await state(); log('money0', money0.cash, money0.bank);
  // ---- A. 번호표 → 창구 (router)
  await tp('Kiosk', 0, -1.5);
  let r = await inv('ticket', '{ dept = "fm" }'); log('ticket', r.ok, r.code, r.message, 'rerouted', r.rerouted, r.visit && r.visit.dept, 'prio', r.visit && r.visit.prio, 'ticket', r.ticket);
  let v = await waitStep(['desk_called'], 60); log('called', v.step, v.window);
  await tp(v.target || 'Win1', 0, -1);
  r = await inv('desk'); log('desk', r.ok, r.code, r.message);
  r = await inv('register', '{ purpose = "ill", symptoms = { "runny", "cough", "fever" } }'); log('register', r.ok, r.code, r.visit && r.visit.step, r.visit && r.visit.deptName);
  // ---- B. 대기실 잡지 (UI)
  await tp('Magazine', 0, -2.5);
  log('magazine', await call('Lounge.openMagazine'));
  await p.waitForTimeout(2500);
  await shot('M1_magazine');
  await ccmd('close');
  // ---- C. 진료실 (router; the client runs its own dialog flow meanwhile)
  v = await waitStep(['consult_called'], 90); log('consult called', v.step);
  await tp('ConsultSeat', 0, 0);
  r = await inv('enter'); log('enter', r.ok, r.code, r.message);
  for (const k of ((r.visit && r.visit.exams) || [])) { await p.waitForTimeout(1300); const e = await inv('exam', `{ kind = "${k}" }`); log('exam', k, e.ok, e.code, j(e.result, 160)); if (e.done && e.visit) { log('dx', j(e.visit.dx && { name: e.visit.dx.name, code: e.visit.dx.code, cause: e.visit.dx.cause, advice: e.visit.dx.advice }, 700)); log('plans', j((e.visit.plans || []).map(x => [x.id, x.title, x.total, x.op, x.extra]), 700)); } }
  await p.waitForTimeout(2500);
  await shot('C1_consult');
  await p.waitForTimeout(6000);
  r = await inv('plan', '{ id = "A" }'); log('plan A', r.ok, r.code, r.message, r.visit && r.visit.step);
  log('emr', await srv(`out = tostring(RS.GwangalliClinicShared.State:GetAttribute("EMR"))`));
  // ---- D. 진찰대 주사 (client → Health's own treat op)
  await tp('ExamBed', 0, -2.5);
  log('treat ui', await call('Treat.start'));
  await p.waitForTimeout(2500);
  await shot('T1_inject');
  await key('KeyF', 800);
  v = await waitStep(['pay_go', 'iv_go'], 25); const st1 = await state(); log('after treat', v.step, 'illness', st1.illness, 'fatigue', st1.fatigue, 'walk', st1.walk, 'cash', st1.cash, 'bank', st1.bank);
  await fix();
  // ---- E. 수납 (UI receipt, Enter = 체크카드)
  await tp('Win1', 0, -1);
  log('bill', await call('Desk.openBill'));
  await p.waitForTimeout(3000);
  await shot('R1_receipt');
  const bv = await inv('pay', '{ action = "view" }'); log('bill view', j(bv.bill && { rows: bv.bill.rows.map(x => [x.label, x.amount, x.cover, x.paid]), sum: bv.bill.sum, how: bv.bill.paidHow }, 900));
  await key('Enter', 2500);
  v = await visit();
  if (v.step === 'pay_go') { r = await inv('pay', `{ action = "pay", method = "card", bill = "${bv.bill && bv.bill.id}" }`); log('pay api', r.ok, r.code, r.message); }
  v = await visit(); log('after pay', v.step, j(v.rx && v.rx.items, 300));
  await ccmd('close');
  // ---- F. 약국
  await tp('Pharmacy', 0, -1);
  r = await inv('pharmacy', '{ action = "submit" }'); log('submit', r.ok, r.code, r.message);
  v = await waitStep(['pharm_ready'], 30); log('rx ready', v.step);
  log('collect', await call('Pharmacy.collect'));
  await p.waitForTimeout(3000);
  await shot('P1_bag');
  await key('Enter', 2500);
  log('meds', j((await op('clinic', '"health"')).meds));
  await ccmd('close');
  // ---- G. 건강검진 (router; 결과지 opens on the client)
  await tp('CheckDesk', 0, -1.5);
  r = await inv('checkup', '{ action = "start" }'); log('chk start', r.ok, r.code, r.message, r.visit && r.visit.step);
  for (const [sid, anchor] of [['height', 'CheckScale'], ['bp', 'CheckBP'], ['eye', 'CheckEye'], ['ear', 'CheckEar'], ['ecg', 'CheckECG']]) {
    await tp(anchor, 0, 0);
    const bg = await inv('checkup', `{ action = "begin", station = "${sid}" }`);
    log('begin', sid, bg.ok, bg.code, bg.message);
    let answers = 'nil';
    if (bg.challenge && bg.challenge.seq) answers = '{' + bg.challenge.seq.map((x, i) => '"' + (i % 5 === 4 ? 'up' : x.dir) + '"').join(',') + '}';
    if (bg.challenge && bg.challenge.tones) answers = '{' + bg.challenge.tones.map(x => '"' + x.ear + '"').join(',') + '}';
    await p.waitForTimeout(3800);
    const fin = await inv('checkup', `{ action = "station", station = "${sid}", result = { answers = ${answers} } }`);
    log('station', sid, fin.ok, fin.code, fin.message, fin.text, fin.left);
    await fix();
  }
  await ccmd('close');
  await tp('CheckDesk', 0, -1.5);
  r = await inv('checkup', '{ action = "finish" }'); log('report', r.ok, r.code, r.message, j(r.report && { grade: r.report.grade, notes: r.report.notes, fee: r.report.fee, bmi: r.report.bmi, vision: r.report.vision }, 600));
  await p.waitForTimeout(3000);
  await shot('K1_report');
  await ccmd('close');
  // ---- H. tired → 영양수액 (IV + nap) → 미납 → 퇴원 수속
  log('tired', j(await op('health', '"setFatigue"', '82')));
  await tp('Kiosk', 0, -1.5);
  r = await inv('ticket', '{ dept = "fm" }'); log('ticket2', r.ok, r.code, r.message, r.visit && r.visit.dept);
  r = await inv('cancel'); log('cancel free', r.ok, r.code, (await visit()).none);
  r = await inv('ticket', '{ dept = "fm" }'); log('ticket3', r.ok, r.code, r.message);
  v = await waitStep(['desk_called'], 60); await tp(v.target || 'Win1', 0, -1);
  r = await inv('desk'); r = await inv('register', '{ purpose = "tired", symptoms = { "tired", "shoulder" } }'); log('register2', r.ok, r.code, r.visit && r.visit.dept);
  v = await waitStep(['consult_called'], 90); await tp('ConsultSeat', 0, 0);
  r = await inv('enter'); log('enter2', r.ok, r.code, r.message);
  for (const k of ((r.visit && r.visit.exams) || [])) { await p.waitForTimeout(1300); const e = await inv('exam', `{ kind = "${k}" }`); if (e.done && e.visit) log('plans2', j((e.visit.plans || []).map(x => [x.id, x.title, x.total, x.short]), 700)); }
  await p.waitForTimeout(8000);
  r = await inv('plan', '{ id = "M" }'); log('plan M', r.ok, r.code, r.message, r.visit && r.visit.step);
  await tp('ExamBed', 0, -2.5);
  r = await inv('treat', '{ action = "start" }'); log('treat2', r.ok, r.code, r.message, r.fee);
  v = await waitStep(['iv_go'], 25); log('iv_go bed', v.step, v.target);
  await fix();
  await tp(v.target || 'TreatBed1', 0, -3);
  r = await inv('treat', '{ action = "start" }'); log('iv start', r.ok, r.code, r.message, r.visit && r.visit.step);
  await p.waitForTimeout(2500);
  log('lying', j(await state()));
  await shot('I1_iv', [-470.5, 13, 302], [-465.3, 9.3, 309]);
  r = await inv('treat', '{ action = "nap" }'); log('nap', r.ok, r.code);
  v = await waitStep(['pay_go'], 60); log('after iv', v.step, j(await state()));
  await fix();
  await tp('Win2', 0, -1);
  r = await inv('pay', '{ action = "view" }'); log('bill2', j(r.bill && r.bill.sum));
  r = await inv('pay', `{ action = "defer", bill = "${r.bill && r.bill.id}" }`); log('defer', r.ok, r.code, r.message);
  log('debt', j((await op('clinic', '"health"')).debt));
  r = await inv('pay', '{ action = "view" }'); log('ward bill', r.ok, r.code, r.message, j(r.bill && r.bill.sum));
  r = await inv('pay', `{ action = "pay", method = "cash", bill = "${r.bill && r.bill.id}" }`); log('ward pay', r.ok, r.code, r.message);
  log('debt after', j((await op('clinic', '"health"')).debt), j(await state()));
  // ---- I. 병실 휴식 + 간호사 호출
  await tp('Ward1A', 0, -2);
  r = await inv('ward', '{ action = "rest" }'); log('rest', r.ok, r.code, r.message);
  r = await inv('ward', '{ action = "call" }'); log('call', r.ok, r.code, r.message);
  await p.waitForTimeout(7000);
  log('ward state', j(await state()));
  await b.close();
  log('done');
})().catch((e) => { console.log('FATAL', e); process.exit(1); });
