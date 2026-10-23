// node decor.js <html> <outDir>: injects GwangalliDecorPlus into the temp studio, rents + enters a home,
// runs the server scenario (place / stack / move / colour / remove / restore / finish / presets / exploits)
// and drives the client editor for screenshots (landscape + portrait).
const { chromium } = require('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/harness/node_modules/playwright');
const fs = require('fs');
const path = require('path');
(async () => {
  const [html, outDir, tier] = process.argv.slice(2);
  fs.mkdirSync(outDir, { recursive: true });
  const codes = JSON.parse(fs.readFileSync(path.join(__dirname, 'inject.json'), 'utf8'));
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const p = await b.newPage({ viewport: { width: 1280, height: 720 } });
  p.setDefaultTimeout(600000);
  const T0 = Date.now();
  const log = (...a) => console.log(`[${((Date.now() - T0) / 1000).toFixed(0)}s]`, ...a);
  p.on('pageerror', e => log('[pageerror]', e.message.slice(0, 300)));
  p.on('console', m => { const t = m.text(); if (/Decor|decor|DecorPlus/.test(t)) log('[c]', t.slice(0, 500)); });
  await p.goto('file://' + html);
  await p.waitForFunction(() => window.GW && GW.engine && GW.engine.running, null, { timeout: 400000 });
  log('engine running');
  await p.waitForTimeout(12000);
  const ev = (code) => p.evaluate((c) => GW.engine.eval(c).then((r) => String(r)).catch((e) => 'ERR ' + e), code);
  log('shared', await ev(codes[0]));
  log('server', await ev(codes[1]));
  await p.waitForTimeout(2000);
  log('helper', await ev(codes[3]));
  const PRE = 'local Sched = GW.require("sched") local Env = GW.require("env") local S = GW.require("services").S local DT = GW.require("datatypes").globals local CFrame, Vector3 = DT.CFrame, DT.Vector3 local out = "?"\n';
  const srv = (body) => ev(PRE + `Sched.runIn(Env.serverCtx, function() local ok, e = pcall(function()
    local game = S.game
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
  let seq = 0;
  async function op(kind, aLua, timeout) {
    seq += 1;
    const key = 'T' + seq;
    const r = await srv(`out = SS.DecorTest:Invoke("${kind}", "${key}", ${aLua || 'nil'})`);
    if (!String(r).startsWith('spawned')) { log('op spawn failed', r); return {}; }
    for (let i = 0; i < (timeout || 60) * 2; i++) {
      await p.waitForTimeout(500);
      const v = await srv(`out = SS.DecorTest:GetAttribute("${key}") or "?"`);
      if (v !== '?') { try { return JSON.parse(v) || {}; } catch (e) { return { raw: v }; } }
    }
    return { timeout: true };
  }
  let cseq = 0;
  async function ccmd(cmd, arg, timeout) {
    cseq += 1;
    const key = 'C' + cseq;
    const r = await cli(`PS.DecorTestClient:SetAttribute("Cmd", ${JSON.stringify(key + '|' + cmd + '|' + (arg || ''))}) out = "sent"`);
    if (r !== 'sent') return 'ERR ' + r;
    for (let i = 0; i < (timeout || 30) * 4; i++) {
      await p.waitForTimeout(250);
      const v = await cli(`out = tostring(PS.DecorTestClient:GetAttribute("${key}") or "?")`);
      if (v !== '?') return v;
    }
    return 'TIMEOUT';
  }
  const ready = await srv(`local f = RS:FindFirstChild("GwangalliDecorPlusRemotes") out = tostring(f and f:GetAttribute("Ready"))`);
  log('remotes ready', ready);
  const home = await op('home', `"${tier || 'oneroom'}"`, 90);
  log('home', JSON.stringify(home).slice(0, 400));
  log('client', await ev(codes[2]));
  await p.waitForTimeout(4000);
  log('client helper', await ev(codes[4]));
  await p.waitForTimeout(3000);
  const run = await op('run', null, 240);
  if (run.log) for (const l of run.log) log('  ' + l); else log('run', JSON.stringify(run).slice(0, 800));
  const shot = async (name) => { await p.screenshot({ path: path.join(outDir, name + '.png') }); log('shot', name); };
  // client editor
  await p.waitForTimeout(3000);
  log('guis before', await ccmd('guis'));
  await shot('00_home_pill');
  log('open', await ccmd('open', '', 40));
  await p.waitForTimeout(6000);
  log('guis', await ccmd('guis'));
  await shot('01_editor');
  log('pick', await ccmd('pick', 'lv_chesterfield'));
  await p.waitForTimeout(4000);
  await shot('02_placing');
  log('cancel', await ccmd('cancel'));
  log('select', await ccmd('select'));
  await p.waitForTimeout(2500);
  await shot('03_selected');
  log('finish', await ccmd('finish'));
  await p.waitForTimeout(3000);
  await shot('04_finish');
  log('close modal', await ccmd('closeModal'));
  log('goals', await ccmd('goals'));
  await p.waitForTimeout(2500);
  await shot('05_goals');
  log('close modal', await ccmd('closeModal'));
  log('orbit', await ccmd('orbit', '35,-10,0.8'));
  await p.waitForTimeout(3000);
  await p.evaluate(() => { const st = document.createElement('style'); st.id = 'dp-hide'; st.textContent = '#gw-gui{display:none!important}'; document.head.appendChild(st); });
  await p.waitForTimeout(1500);
  await shot('06_world');
  await p.evaluate(() => { const st = document.getElementById('dp-hide'); if (st) st.remove(); });
  await p.setViewportSize({ width: 430, height: 900 });
  await p.waitForTimeout(5000);
  await shot('07_portrait');
  await p.setViewportSize({ width: 1280, height: 720 });
  await p.waitForTimeout(3000);
  log('close', await ccmd('close'));
  await p.waitForTimeout(2000);
  const rb = await op('rebuild', null, 90);
  log('rebuild', JSON.stringify(rb));
  await p.waitForTimeout(3000);
  await shot('08_after_rebuild');
  await b.close();
  log('done');
})().catch((e) => { console.log('[fatal]', e && e.message); process.exit(1); });
