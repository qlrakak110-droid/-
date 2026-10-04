// Gwangalli studio harness: boot the place headless, inject the repo's src/ tree (Rojo layout), patch
// GwangalliGameplay.server's FEATURE_MODULES, run test Luau, capture output + screenshots.
// usage: node harness.js <repoDir> <seconds> [testScript.luau|-] [shotPrefix] [--client-test file]
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

function walk(dir) {
  // returns node {name, cls, src, children}
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  const kids = [];
  let init = null, cls = 'Folder';
  for (const e of entries) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) { kids.push(walk(p)); continue; }
    if (!e.name.endsWith('.luau') && !e.name.endsWith('.lua')) continue;
    const base = e.name.replace(/\.luau?$/, '');
    if (base === 'init') { init = fs.readFileSync(p, 'utf8'); cls = 'ModuleScript'; continue; }
    if (base === 'init.server') { init = fs.readFileSync(p, 'utf8'); cls = 'Script'; continue; }
    if (base === 'init.client') { init = fs.readFileSync(p, 'utf8'); cls = 'LocalScript'; continue; }
    let c = 'ModuleScript', n = base;
    if (base.endsWith('.server')) { c = 'Script'; n = base.slice(0, -7); }
    if (base.endsWith('.client')) { c = 'LocalScript'; n = base.slice(0, -7); }
    kids.push({ name: n, cls: c, src: fs.readFileSync(p, 'utf8'), children: [] });
  }
  return { name: path.basename(dir), cls, src: init, children: kids };
}
function lstr(s) { let eq = '======'; while (s.includes(']' + eq + ']')) eq += '='; return '[' + eq + '[' + s + ']' + eq + ']'; }
function toLuau(n) {
  return '{name=' + JSON.stringify(n.name) + ',cls="' + n.cls + '",src=' + (n.src != null ? lstr(n.src) : 'nil') + ',children={' + n.children.map(toLuau).join(',') + '}}';
}
const BUILD = `
local I = GW.require("instance")
local Sched = GW.require("sched")
local Env = GW.require("env")
local S = GW.require("services").S
local function build(n)
  local inst
  if n.cls == "Folder" then inst = I.create("Folder", { name = n.name })
  else inst = I.create(n.cls, { name = n.name, props = { Source = n.src or "" }, newDefaults = true }) end
  for _, c in n.children do
    local ci = build(c)
    Sched.runIn(Env.serverCtx, I.setParent, ci, inst)
  end
  return inst
end
local function put(tree, parent)
  local inst = build(tree)
  Sched.runIn(Env.serverCtx, I.setParent, inst, parent)
  Sched.flush()
end
`;
(async () => {
  const [repo, secs, testFile, shot] = process.argv.slice(2);
  const src = path.join(repo, 'src');
  const shared = walk(path.join(src, 'ReplicatedStorage/GwangalliMiniGamesShared'));
  const server = walk(path.join(src, 'ServerScriptService/GwangalliGameplay/MiniGames'));
  const client = walk(path.join(src, 'StarterPlayer/StarterPlayerScripts/GwangalliMiniGames'));
  const b = await chromium.launch({ args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader'] });
  const p0 = 0; const p = await b.newPage({ viewport: { width: +(process.env.W || 1280), height: +(process.env.H || 720) }, hasTouch: !!process.env.TOUCH, isMobile: !!process.env.TOUCH });
  p.setDefaultTimeout(240000);
  p.on('console', m => { const t = m.text(); if (t.startsWith('[luau]') && !/GwangalliVenues\] module missing|quality tier/.test(t)) console.log(t.slice(0, 1500)); });
  p.on('pageerror', e => console.log('[pageerror]', e.message));
  await p.goto('file://' + __dirname + '/studio.html' + (process.env.HASH ? '#' + process.env.HASH : ''));
  await p.waitForFunction(() => window.GW && GW.engine && GW.engine.running, null, { timeout: 120000 });
  await p.waitForTimeout(2500);
  const ev = c => p.evaluate(c => GW.engine.eval(c).then(r => String(r)).catch(e => 'ERR ' + e), c);
  console.log('inject shared:', await ev(BUILD + `local t = ${toLuau(shared)}
    local RS; Sched.runIn(Env.serverCtx, function() RS = S.game:GetService("ReplicatedStorage") end)
    put(t, RS) return "ok"`));
  console.log('inject server:', await ev(BUILD + `local t = ${toLuau(server)}
    local folder, core
    Sched.runIn(Env.serverCtx, function()
      local sss = S.game:GetService("ServerScriptService")
      for _, c in sss:GetChildren() do
        if c.Name == "GwangalliGameplay" and c:IsA("Folder") then folder = c end
        if c.Name == "GwangalliGameplay" and c:IsA("Script") then core = c end
      end
    end)
    put(t, folder)
    local src = Env.sourceOf(core)
    local n
    src, n = string.gsub(src, 'local FEATURE_MODULES = { "Bank",', 'local FEATURE_MODULES = { "MiniGames", "Bank",')
    local Insert = GW.require("insert")
    local r = Insert.hotReload(core, src, { force = true })
    return "patched=" .. tostring(n) .. " reload ok=" .. tostring(r and r.ok) .. " " .. tostring(r and r.err)`));
  await p.waitForTimeout(4000);
  if (fs.existsSync(path.join(src, 'StarterPlayer/StarterPlayerScripts/GwangalliMiniGames'))) {
    console.log('inject client:', await ev(BUILD + `local t = ${toLuau(client)}
      local ps; Sched.runIn(Env.serverCtx, function() ps = S.player:FindFirstChildOfClass("PlayerScripts") end)
      put(t, ps) return "ok"`));
  }
  await p.waitForTimeout(3000);
  if (testFile && testFile !== '-') {
    const code = fs.readFileSync(testFile, 'utf8');
    console.log('test:', await ev(BUILD + `local Insert = GW.require("insert")
      local sss; Sched.runIn(Env.serverCtx, function() sss = S.game:GetService("ServerScriptService") end)
      local ok, e = pcall(Insert.createScript, sss, "Script", "MiniGamesTest", ${lstr(code)})
      return tostring(ok) .. tostring(e)`));
  }
  const probe = `local S = GW.require("services").S local Sched = GW.require("sched") local Env = GW.require("env") local t Sched.runIn(Env.serverCtx, function() t = S.game:GetService("Workspace").DistributedGameTime end) return tostring(t)`;
  console.log('gametime', await ev(probe)); await p.waitForTimeout(2000); console.log('gametime', await ev(probe));
  const total = (+secs || 10) * 1000; const step = 5000; let k = 0;
  for (let t = 0; t < total; t += step) {
    await p.waitForTimeout(Math.min(step, total - t));
    if (shot) await p.screenshot({ path: `${shot}_${k++}.png` });
  }
  await b.close();
})();
