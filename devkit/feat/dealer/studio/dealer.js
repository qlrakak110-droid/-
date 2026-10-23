// node dealer.js <html> <outDir>: injects GwangalliCarDealer into the temp studio and drives the flow
const { chromium } = require('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/harness/node_modules/playwright');
const fs = require('fs');
const path = require('path');
(async () => {
  const [html, outDir] = process.argv.slice(2);
  fs.mkdirSync(outDir, { recursive: true });
  const codes = JSON.parse(fs.readFileSync(path.join(__dirname, 'inject.json'), 'utf8'));
  codes[0] = codes[0].replace('C.Debug = false', 'C.Debug = true');
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const p = await b.newPage({ viewport: { width: 1280, height: 720 } });
  p.setDefaultTimeout(600000);
  const T0 = Date.now();
  const log = (...a) => console.log(`[${((Date.now() - T0) / 1000).toFixed(0)}s]`, ...a);
  p.on('pageerror', e => log('[pageerror]', e.message.slice(0, 300)));
  p.on('console', m => { const t = m.text(); if (/CarDealer|DealerClient/.test(t)) log('[c]', t.slice(0, 500)); });
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
    local P = S.player
    local PS = P:FindFirstChildOfClass("PlayerScripts")
    ${body}
  end) if not ok then out = "ERR " .. tostring(e) end end) Sched.flush() return out`);
  let cseq = 0;
  async function ccmd(cmd, arg, timeout) {
    cseq += 1;
    const key = 'C' + cseq;
    const r = await cli(`PS.DealerClientTest:SetAttribute("Cmd", ${JSON.stringify(key + '|' + cmd + '|' + (arg || ''))}) out = "sent"`);
    if (r !== 'sent') return 'ERR ' + r;
    for (let i = 0; i < (timeout || 25) * 4; i++) {
      await p.waitForTimeout(250);
      const v = await cli(`out = tostring(PS.DealerClientTest:GetAttribute("${key}") or "?")`);
      if (v !== '?') return v;
    }
    return 'TIMEOUT';
  }
  const call = (fn, args) => ccmd('call', fn + (args !== undefined ? '|' + JSON.stringify(args) : ''));
  const net = (op, payload) => ccmd('net', op + '|' + JSON.stringify(payload || {}), 40);
  async function shot(name, eye, at) {
    if (eye) {
      await p.evaluate(() => { try { CameraCtl.suspend(); } catch (e) {} });
      for (let k = 0; k < 6; k++) {
        await p.evaluate(([e, a]) => { const cam = Render3D.camera; cam.position.fromArray(e); cam.up.set(0, 1, 0); cam.lookAt(...a); cam.fov = 60; cam.near = 0.05; cam.updateProjectionMatrix(); }, [eye, at]);
        await p.waitForTimeout(250);
      }
    } else {
      await p.waitForTimeout(600);
    }
    await p.screenshot({ path: `${outDir}/${name}.png` });
    log('shot', name);
    if (eye) await p.evaluate(() => { try { CameraCtl.resume && CameraCtl.resume(); } catch (e) {} });
  }
  async function findBtn(pat) {
    const r = await ccmd('find', pat, 8);
    if (!/^\d/.test(r)) return null;
    const [x, y, iy] = r.split(',').map(Number);
    return { x, y: y + iy };
  }
  async function click(pat, tries) {
    for (let i = 0; i < (tries || 12); i++) {
      const c = await findBtn(pat);
      if (c) { await p.mouse.click(c.x, c.y); log('click', pat, c.x, c.y); await p.waitForTimeout(900); return true; }
      await p.waitForTimeout(800);
    }
    log('click FAILED', pat);
    return false;
  }
  async function hold(pat, ms) {
    for (let i = 0; i < 12; i++) {
      const c = await findBtn(pat);
      if (c) { await p.mouse.move(c.x, c.y); await p.mouse.down(); await p.waitForTimeout(ms); await p.mouse.up(); log('hold', pat); await p.waitForTimeout(600); return true; }
      await p.waitForTimeout(800);
    }
    log('hold FAILED', pat);
    return false;
  }
  // ---- boot checks
  let w = '?';
  for (let i = 0; i < 45; i++) {
    w = await srv(`local f = workspace:FindFirstChild("GwangalliCarDealer") local pv = RS:FindFirstChild("GwangalliCarDealerPreviews")
      local parts = {}
      if f then for _, c in f:GetChildren() do local pos = if c:IsA("Model") then c:GetPivot().Position elseif c:IsA("BasePart") then c.Position else nil table.insert(parts, c.Name .. "@" .. (pos and string.format("%.1f,%.1f,%.1f", pos.X, pos.Y, pos.Z) or "?")) end end
      out = "npc=" .. table.concat(parts, ";") .. " previews=" .. tostring(pv and #pv:GetChildren()) .. " ready=" .. tostring(pv and pv:GetAttribute("Ready")) .. " remotes=" .. tostring(RS:FindFirstChild("GwangalliCarDealerRemotes") ~= nil) .. " garageApi=" .. tostring(SS:FindFirstChild("GwangalliGarageAPI") ~= nil)`);
    if (/consult/.test(w) && /ready=true/.test(w)) break;
    await p.waitForTimeout(4000);
  }
  log('world', w);
  log('rigs', await srv(`local out2 = {} for _, r in game:GetService("CollectionService"):GetTagged("GarageStaff") do table.insert(out2, r.Name .. " role=" .. tostring(r:GetAttribute("Role")) .. " dealer=" .. tostring(r:GetAttribute("GwDealerNpc"))) end out = table.concat(out2, " | ")`));
  for (let i = 0; i < 30; i++) { const r = await cli(`out = tostring(PS:FindFirstChild("DealerClientTest") and PS.DealerClientTest:GetAttribute("Ready"))`); if (r === 'true') { log('client helper ready'); break; } await p.waitForTimeout(1000); }
  log('earn', await srv(`out = tostring(SS.GwangalliGameplayAPI:Invoke("earn", P, 3000000, "딜러 테스트"))`));
  const m = /GwangalliCarDealer_NPC_consult@([-\d.]+),([-\d.]+),([-\d.]+)/.exec(w);
  const npc = m ? [Number(m[1]), Number(m[2]), Number(m[3])] : [-568.2, 9.7, 426.8];
  const r0 = await p.evaluate((q) => { try { if (window.Character && Character.teleport) { Character.teleport(q); return 'js'; } } catch (e) { return 'jsERR ' + e; } return 'nojs'; }, [npc[0] + 1, npc[1], npc[2] + 7]);
  log('tp', r0);
  await p.waitForTimeout(12000);
  log('state0', await ccmd('state'));
  await shot('A_npc', [npc[0] - 3, npc[1] + 3, npc[2] + 11], [npc[0], npc[1] + 1, npc[2]]);
  await shot('A_wide', [-566, 16, 478], [-570, 7, 430]);
  // ---- dialog
  log('dialog', await call('Dialog.open', [{ id: 'consult', name: '한서윤 대리', role: '영업 컨설턴트', voice: 'consult', icon: '👩‍💼', ours: true }]));
  await p.waitForTimeout(9000);
  await shot('B_dialog');
  await click('이달의 특가');
  await p.waitForTimeout(7000);
  await shot('B_special');
  await click('다른 것도');
  await p.waitForTimeout(4000);
  await click('예산에 맞는');
  await p.waitForTimeout(5000);
  await click('150만 원');
  await p.waitForTimeout(7000);
  await shot('B_budget');
  await click('전체 차량 보기');
  await p.waitForTimeout(10000);
  log('state1', await ccmd('state'));
  await shot('C_catalog');
  await click('SUV');
  await p.waitForTimeout(3000);
  await shot('C_catalog_suv');
  log('detail', await call('Catalog.openDetail', ['kit:suv:new']));
  await p.waitForTimeout(6000);
  await shot('D_detail');
  await click('할부로 살게요');
  await p.waitForTimeout(3000);
  await shot('D_detail_loan');
  await click('계약하기');
  await p.waitForTimeout(4000);
  await shot('E_contract');
  await hold('길게 눌러', 2600);
  await p.waitForTimeout(9000);
  await shot('F_ceremony');
  log('state2', await ccmd('state'));
  log('cars', await srv(`local st = SS.GwangalliGarageAPI:Invoke("status", P) local t = {} for _, c in st.cars do table.insert(t, tostring(c.label) .. ":" .. tostring(c.plate) .. ":" .. tostring(c.grade) .. ":" .. tostring(c.loan ~= nil)) end out = "owned=" .. tostring(st.owned) .. " bank=" .. tostring(st.bank) .. " cash=" .. tostring(st.cash) .. " " .. table.concat(t, ", ")`));
  await click('나중에 탈게요');
  await p.waitForTimeout(2500);
  // a used car with the level benefit / special, straight through the remote
  log('buy2', (await net('buy', { entry: 'kit:compact:used', color: 'mint', loan: false, nonce: 'dealerTest2' })).slice(0, 600));
  log('buy2 again (idempotent)', (await net('buy', { entry: 'kit:compact:used', color: 'mint', loan: false, nonce: 'dealerTest2' })).slice(0, 200));
  log('bad1', (await net('buy', { entry: 'kit:../x', nonce: 'n3' })).slice(0, 200));
  log('bad2', (await net('testdrive', { entry: 'model:nope' })).slice(0, 200));
  log('wish', (await net('wish', { entry: 'kit:luxury:new', on: true })).slice(0, 200));
  await p.waitForTimeout(2500);
  // ---- test drive (garage path)
  log('test', (await net('testdrive', { entry: 'kit:sedan:new', color: 'red' })).slice(0, 300));
  await p.waitForTimeout(12000);
  await shot('G_test');
  log('endtest', (await net('endtest', {})).slice(0, 200));
  await p.waitForTimeout(12000);
  await shot('G_report');
  // ---- phone
  await p.setViewportSize({ width: 844, height: 390 });
  await p.waitForTimeout(3000);
  log('phone catalog', await call('Catalog.open', [{ cat: 'all' }]));
  await p.waitForTimeout(9000);
  await shot('H_phone_catalog');
  log('phone detail', await call('Catalog.openDetail', ['kit:sedan:used']));
  await p.waitForTimeout(5000);
  await shot('H_phone_detail');
  log('close', await call('Catalog.close'));
  await p.waitForTimeout(1500);
  log('phone dialog', await call('Dialog.open', [{ id: 'boss', name: '박사장', role: '광안 오토 대표', voice: 'boss', icon: '👨‍💼' }]));
  await p.waitForTimeout(9000);
  await shot('H_phone_dialog');
  await b.close();
  log('done');
})();
