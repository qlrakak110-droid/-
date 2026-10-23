// node smoke.js <html> <inject.json> <outDir>: boots the temp studio, inserts GwangalliPlus.server (Script) and
// GwangalliPlus.client (LocalScript), logs every add-on message / error for a few minutes, takes screenshots.
const { chromium } = require('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/harness/node_modules/playwright');
const fs = require('fs');
(async () => {
  const [html, inj, outDir] = process.argv.slice(2);
  fs.mkdirSync(outDir, { recursive: true });
  const codes = JSON.parse(fs.readFileSync(inj, 'utf8'));
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const p = await b.newPage({ viewport: { width: 960, height: 540 } });
  p.setDefaultTimeout(900000);
  const T0 = Date.now();
  const lines = [];
  const log = (...a) => { const s = `[${((Date.now() - T0) / 1000).toFixed(0)}s] ` + a.join(' '); lines.push(s); console.log(s); };
  p.on('pageerror', e => log('[pageerror]', e.message.slice(0, 400)));
  p.on('console', m => { const t = m.text(); if (/Gwangalli|오류|rror|warn|WARN|stack|Stack|traceback|nil value|attempt to/i.test(t)) log('[c]', t.slice(0, 700)); });
  await p.goto('file://' + html);
  await p.waitForFunction(() => window.GW && GW.engine && GW.engine.running, null, { timeout: 600000 });
  log('engine running');
  await p.waitForTimeout(8000);
  const ev = (code) => p.evaluate((c) => GW.engine.eval(c).then((r) => String(r)).catch((e) => 'ERR ' + e), code);
  log('server inject', await ev(codes[0]));
  await p.waitForTimeout(8000);
  log('client inject', await ev(codes[1]));
  const PRE = 'local Sched = GW.require("sched") local Env = GW.require("env") local S = GW.require("services").S local out = "?"\n';
  const srv = (body) => ev(PRE + `Sched.runIn(Env.serverCtx, function() local ok, e = pcall(function() local game = S.game ${body} end) if not ok then out = "ERR " .. tostring(e) end end) Sched.flush() return out`);
  const shot = async (n) => { await p.screenshot({ path: `${outDir}/${n}.png` }); log('shot', n); };
  for (let i = 1; i <= 6; i++) {
    await p.waitForTimeout(30000);
    log('state', await srv(`local RS = game:GetService("ReplicatedStorage") local SSS = game:GetService("ServerScriptService")
      local m = RS:FindFirstChild("GwangalliPlus") local t = {}
      for _, c in SSS:GetChildren() do if c:GetAttribute("GwVMod") then table.insert(t, c.Name) end end
      local ps = S.player and S.player:FindFirstChildOfClass("PlayerScripts") local u = {}
      if ps then for _, c in ps:GetChildren() do if c:GetAttribute("GwVMod") then table.insert(u, c.Name) end end end
      local w = game:GetService("Workspace"):FindFirstChild("GwInteriorDetailLocal")
      out = "marker=" .. tostring(m ~= nil) .. " server=" .. table.concat(t, ",") .. " client=" .. table.concat(u, ",") .. " interiorParts=" .. tostring(w and #w:GetDescendants() or -1)`));
    if (i === 2 || i === 6) await shot('spawn_' + i);
  }
  const tp = async (x, y, z, n) => {
    const r = await p.evaluate((q) => { try { if (window.Character && Character.teleport) { Character.teleport(q); return 'js'; } } catch (e) { return 'jsERR ' + e; } return 'nojs'; }, [x, y, z]);
    log('tp', n, r);
    await p.waitForTimeout(60000);
    await shot(n);
  };
  await tp(-124, 9, 377, 'club_main');
  fs.writeFileSync(`${outDir}/log.txt`, lines.join('\n'));
  await b.close();
})().catch(e => { console.log('FATAL', e); process.exit(1); });
