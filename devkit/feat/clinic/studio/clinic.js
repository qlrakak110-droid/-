// node clinic.js <html> <outDir>: injects GwangalliClinic into the temp studio and drives a full visit
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
  p.on('pageerror', e => console.log('[pageerror]', e.message.slice(0, 300)));
  p.on('console', m => { const t = m.text(); if (/Clinic|clinic/.test(t)) console.log('[c]', t.slice(0, 500)); });
  await p.goto('file://' + html);
  await p.waitForFunction(() => window.GW && GW.engine && GW.engine.running, null, { timeout: 400000 });
  console.log('engine running');
  await p.waitForTimeout(12000);
  const ev = (code) => p.evaluate((c) => GW.engine.eval(c).then((r) => String(r)).catch((e) => 'ERR ' + e), code);
  console.log('shared', await ev(codes[0]));
  console.log('server', await ev(codes[1]));
  await p.waitForTimeout(3000);
  console.log('client', await ev(codes[2]));
  console.log('helper', await ev(codes[3]));
  const PRE = 'local Sched = GW.require("sched") local Env = GW.require("env") local S = GW.require("services").S local DT = GW.require("datatypes").globals local CFrame, Vector3 = DT.CFrame, DT.Vector3 local out = "?"\n';
  const srv = (body) => ev(PRE + `Sched.runIn(Env.serverCtx, function() local ok, e = pcall(function()
    local game = S.game
    local RS = game:GetService("ReplicatedStorage")
    local SS = game:GetService("ServerStorage")
    local HS = game:GetService("HttpService")
    local P = S.player
    ${body}
  end) if not ok then out = "ERR " .. tostring(e) end end) Sched.flush() return out`);
  // run an op through the injected ClinicTest helper (async), poll the JSON result
  let seq = 0;
  async function op(kind, aLua, bLua, cLua, timeout) {
    seq += 1;
    const key = 'T' + seq;
    const r = await srv(`out = SS.ClinicTest:Invoke("${kind}", "${key}", ${aLua || 'nil'}, ${bLua || 'nil'}, ${cLua || 'nil'})`);
    if (!String(r).startsWith('spawned')) { console.log('op spawn failed', r); return {}; }
    for (let i = 0; i < (timeout || 30) * 2; i++) {
      await p.waitForTimeout(500);
      const v = await srv(`out = SS.ClinicTest:GetAttribute("${key}") or "?"`);
      if (v !== '?') { try { return JSON.parse(v) || {}; } catch (e) { return { raw: v }; } }
    }
    return { timeout: true };
  }
  const inv = (opName, payloadLua) => op('clinic', '"invoke"', `"${opName}"`, payloadLua || '{}');
  const visit = async () => { const v = await op('clinic', '"visit"'); return (v && v.step) ? v : { none: true }; };
  const state = () => op('state');
  const tp = async (anchor, dz) => JSON.stringify(await op('tp', `"${anchor}"`, String(dz || 0)));
  const j = (x, n) => JSON.stringify(x === undefined ? null : x).slice(0, n || 600);
  async function waitStep(steps, secs) {
    for (let i = 0; i < secs; i++) {
      const v = await visit();
      if (steps.includes(v.step) || (steps.includes('none') && v.none)) return v;
      await p.waitForTimeout(1000);
    }
    return await visit();
  }
  async function shot(name, eye, at) {
    await p.evaluate(() => { try { CameraCtl.suspend(); } catch (e) {} });
    for (let k = 0; k < 8; k++) {
      await p.evaluate(([e, a]) => { const cam = Render3D.camera; cam.position.fromArray(e); cam.up.set(0, 1, 0); cam.lookAt(...a); cam.fov = 70; cam.near = 0.05; cam.updateProjectionMatrix(); }, [eye, at]);
      await p.waitForTimeout(200);
    }
    await p.screenshot({ path: `${outDir}/${name}.png` });
    console.log('shot', name);
    await p.evaluate(() => { try { CameraCtl.resume && CameraCtl.resume(); } catch (e) {} });
  }
  // ---- boot
  let st = '?';
  for (let i = 0; i < 40; i++) {
    st = await srv(`local sh = RS:FindFirstChild("GwangalliClinicShared") local s = sh and sh:FindFirstChild("State") out = "active=" .. tostring(s and s:GetAttribute("Active"))`);
    if (st === 'active=true') break;
    await p.waitForTimeout(4000);
  }
  console.log('boot', st);
  console.log('world', j(await op('world'), 1500));
  console.log('setup', j(await op('gp', '"earn"', '400000', '"test"')), j(await op('health', '"setFatigue"', '91')), j(await op('health', '"makeIll"', '"cold"')));
  console.log('state0', j(await state()));
  console.log('health', j(await op('clinic', '"health"'), 1200));
  console.log('tp', await tp('Kiosk', -2));
  await p.waitForTimeout(3000);
  let r = await inv('ticket', '{ dept = "fm" }');
  console.log('ticket', j({ ok: r.ok, code: r.code, msg: r.message, ticket: r.ticket, rerouted: r.rerouted, step: r.visit && r.visit.step, dept: r.visit && r.visit.dept, prio: r.visit && r.visit.prio }));
  await p.waitForTimeout(2500);
  await shot('01_lobby_led', [-506, 12.5, 271], [-510.8, 14.6, 291.7]);
  let v = await waitStep(['desk_called'], 45);
  console.log('called', v.step, 'win', v.window, 'target', v.target);
  console.log('tp', await tp(v.target || 'Win1', 0));
  await p.waitForTimeout(1500);
  r = await inv('desk'); console.log('desk', r.ok, r.code, r.message, r.visit && r.visit.step);
  r = await inv('register', '{ purpose = "ill", symptoms = { "runny", "cough", "sore" } }'); console.log('register', r.ok, r.code, r.message, r.visit && r.visit.step);
  await shot('02_wait_tv', [-462, 11, 281], [-468.8, 14.2, 293]);
  v = await waitStep(['consult_called'], 70);
  console.log('consult called', v.step);
  console.log('tp', await tp('ConsultSeat', 0));
  await p.waitForTimeout(1500);
  r = await inv('enter'); console.log('enter', r.ok, r.code, r.message, r.visit && r.visit.step, j(r.visit && r.visit.exams));
  console.log('seated', j(await state()));
  const exams = (r.visit && r.visit.exams) || [];
  for (const k of exams) {
    await p.waitForTimeout(1300);
    const e = await inv('exam', `{ kind = "${k}" }`);
    console.log('exam', k, e.ok, e.code, j(e.result), e.done);
    if (e.done && e.visit) { console.log('dx', j(e.visit.dx, 900)); console.log('plans', j(e.visit.plans, 1200)); }
  }
  await p.waitForTimeout(7000);
  await shot('03_consult', [-551.6, 12.6, 284.6], [-554.3, 10.2, 276.4]);
  r = await inv('plan', '{ id = "A" }'); console.log('plan', r.ok, r.code, r.message, r.visit && r.visit.step);
  console.log('tp', await tp('ExamBed', -2.5));
  await p.waitForTimeout(1200);
  r = await inv('treat', '{ action = "start" }'); console.log('treat', r.ok, r.code, r.message, r.fee, r.visit && r.visit.step);
  await p.waitForTimeout(2000);
  console.log('during', j(await state()));
  await shot('04_exam_bed', [-566, 12.5, 278], [-569.6, 9.2, 283.2]);
  v = await waitStep(['pay_go', 'iv_go'], 15);
  console.log('after treat', v.step, j(await state()));
  console.log('tp', await tp('Win1', 0));
  await p.waitForTimeout(1200);
  r = await inv('pay', '{ action = "view" }'); console.log('bill', r.ok, r.code, r.message, j(r.bill && { rows: r.bill.rows, sum: r.bill.sum, how: r.bill.paidHow }, 1500));
  const billId = r.bill && r.bill.id;
  r = await inv('pay', `{ action = "pay", method = "card", bill = "${billId}" }`); console.log('pay', r.ok, r.code, r.message, r.rx && r.rx.no, r.visit && r.visit.step);
  await p.waitForTimeout(1500);
  await shot('05_receipt_ui', [-512, 12, 276], [-514, 10, 284]);
  console.log('tp', await tp('Pharmacy', 0));
  await p.waitForTimeout(1200);
  r = await inv('pharmacy', '{ action = "submit" }'); console.log('submit', r.ok, r.code, r.message, r.visit && r.visit.step);
  await p.waitForTimeout(3000);
  await shot('06_pharmacy_screen', [-538, 11, 292], [-535.5, 11.7, 299.3]);
  v = await waitStep(['pharm_ready'], 20); console.log('rx', v.step);
  r = await inv('pharmacy', '{ action = "collect" }'); console.log('collect', r.ok, r.code, r.message, j(r.meds));
  r = await inv('dose'); console.log('dose', r.ok, r.code, r.message, j(r.dose));
  await p.waitForTimeout(2500);
  await shot('07_after_visit', [-540, 12, 288], [-545, 10, 296]);
  // ---- checkup course
  console.log('tp', await tp('CheckDesk', 0));
  await p.waitForTimeout(2000);
  r = await inv('checkup', '{ action = "start" }'); console.log('chk start', r.ok, r.code, r.message, r.visit && r.visit.step);
  for (const [sid, anchor] of [['height', 'CheckScale'], ['bp', 'CheckBP'], ['eye', 'CheckEye'], ['ear', 'CheckEar'], ['ecg', 'CheckECG']]) {
    console.log('tp', await tp(anchor, 0));
    await p.waitForTimeout(900);
    const bg = await inv('checkup', `{ action = "begin", station = "${sid}" }`);
    console.log('begin', sid, bg.ok, bg.code, bg.message, j(bg.measure || null));
    let answers = 'nil';
    if (bg.challenge && bg.challenge.seq) answers = '{' + bg.challenge.seq.map((x, i) => '"' + (i % 5 === 4 ? 'up' : x.dir) + '"').join(',') + '}';
    if (bg.challenge && bg.challenge.tones) answers = '{' + bg.challenge.tones.map(x => '"' + x.ear + '"').join(',') + '}';
    if (sid === 'ecg') { await p.waitForTimeout(1000); console.log('ecg state', j(await state())); await shot('08_ecg_lying', [-561, 25.5, 326], [-566, 23.2, 329.5]); }
    await p.waitForTimeout(3800);
    const fin = await inv('checkup', `{ action = "station", station = "${sid}", result = { answers = ${answers} } }`);
    console.log('station', sid, fin.ok, fin.code, fin.message, fin.text, fin.left);
  }
  console.log('tp', await tp('CheckDesk', 0));
  await p.waitForTimeout(1000);
  r = await inv('checkup', '{ action = "finish" }'); console.log('report', r.ok, r.code, r.message, j(r.report && { grade: r.report.grade, notes: r.report.notes, advice: r.report.advice, fee: r.report.fee }, 900));
  await p.waitForTimeout(2000);
  await shot('09_report_ui', [-533, 25.5, 292], [-535, 23.5, 300]);
  // ---- healthy + tired: vitamin + IV, defer the extra, then the ward bill
  console.log('tired', j(await op('health', '"setFatigue"', '82')));
  console.log('tp', await tp('Kiosk', -2));
  await p.waitForTimeout(1500);
  r = await inv('ticket', '{ dept = "fm" }'); console.log('ticket2', r.ok, r.code, r.message, r.visit && r.visit.dept);
  v = await waitStep(['desk_called'], 45); console.log('tp', await tp(v.target || 'Win1', 0));
  await p.waitForTimeout(1000);
  await inv('desk');
  r = await inv('register', '{ purpose = "tired", symptoms = { "tired" } }'); console.log('register2', r.ok, r.visit && r.visit.dept);
  v = await waitStep(['consult_called'], 70); console.log('tp', await tp('ConsultSeat', 0));
  await p.waitForTimeout(1000);
  r = await inv('enter'); console.log('enter2', r.ok, r.code, r.message);
  for (const k of ((r.visit && r.visit.exams) || [])) { await p.waitForTimeout(1300); const e = await inv('exam', `{ kind = "${k}" }`); if (e.done && e.visit) console.log('plans2', j((e.visit.plans || []).map(x => [x.id, x.title, x.total, x.short]), 900)); }
  await p.waitForTimeout(9000);
  r = await inv('plan', '{ id = "M" }'); console.log('plan M', r.ok, r.code, r.message, r.visit && r.visit.step);
  console.log('tp', await tp('ExamBed', -2.5)); await p.waitForTimeout(1000);
  r = await inv('treat', '{ action = "start" }'); console.log('treat2', r.ok, r.code, r.message, r.fee);
  v = await waitStep(['iv_go'], 15); console.log('iv_go bed', v.step, v.target);
  console.log('tp', await tp(v.target || 'TreatBed1', -3)); await p.waitForTimeout(1000);
  r = await inv('treat', '{ action = "start" }'); console.log('iv start', r.ok, r.code, r.message, r.visit && r.visit.step);
  console.log('lying', j(await state()));
  await p.waitForTimeout(2500);
  await shot('10_iv_bed', [-470.5, 13, 302], [-465.3, 9.3, 309]);
  r = await inv('treat', '{ action = "nap" }'); console.log('nap', r.ok, r.code);
  v = await waitStep(['pay_go'], 40); console.log('after iv', v.step, j(await state()));
  console.log('tp', await tp('Win2', 0)); await p.waitForTimeout(1000);
  r = await inv('pay', '{ action = "view" }'); console.log('bill2', j(r.bill && r.bill.sum));
  r = await inv('pay', `{ action = "defer", bill = "${r.bill && r.bill.id}" }`); console.log('defer', r.ok, r.code, r.message);
  console.log('debt', j((await op('clinic', '"health"')).debt));
  r = await inv('pay', '{ action = "view" }'); console.log('ward bill', r.ok, r.code, r.message, j(r.bill && r.bill.sum));
  r = await inv('pay', `{ action = "pay", method = "cash", bill = "${r.bill && r.bill.id}" }`); console.log('ward pay', r.ok, r.code, r.message);
  console.log('debt after', j((await op('clinic', '"health"')).debt));
  console.log('tp', await tp('Ward1A', -2)); await p.waitForTimeout(1000);
  r = await inv('ward', '{ action = "rest" }'); console.log('rest', r.ok, r.code, r.message);
  r = await inv('ward', '{ action = "call" }'); console.log('call', r.ok, r.code, r.message);
  await p.waitForTimeout(8000);
  console.log('ward state', j(await state()));
  await shot('11_ward', [-472, 26, 286], [-466.5, 23, 279]);
  await b.close();
})();
