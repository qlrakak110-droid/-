// Seoul skyline headless preview: boots the empty-place studio player (tools/studio_empty.html, made by
// make_preview_studio.py), injects src/ServerStorage/SeoulSkyline (+ optional client scripts), runs Build(),
// draws the recorded terrain ops (the player only draws terrain from its static export), then renders
// named camera shots to PNG.
//
//   node seoul-skyline/tools/preview.js [--only Landmark,Skyline] [--shots hero,landmark] [--out dir]
//        [--cam name=x,y,z:lx,ly,lz:fov]... [--w 1280 --h 720] [--client] [--quality high] [--settle 3]
//
// Shots: see SHOTS below. Output: <out>/<shot>.png (default out: seoul-skyline/shots).
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const args = process.argv.slice(2);
const opt = { only: null, shots: null, out: path.join(ROOT, 'shots'), w: 1280, h: 720, client: false, quality: 'high', settle: 3, cams: {}, timeout: 900, prefix: '' };
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  const v = () => args[++i];
  if (a === '--only') opt.only = v().split(',').filter(Boolean);
  else if (a === '--shots') opt.shots = v().split(',').filter(Boolean);
  else if (a === '--out') opt.out = path.resolve(v());
  else if (a === '--w') opt.w = +v();
  else if (a === '--h') opt.h = +v();
  else if (a === '--client') opt.client = true;
  else if (a === '--quality') opt.quality = v();
  else if (a === '--settle') opt.settle = +v();
  else if (a === '--timeout') opt.timeout = +v();
  else if (a === '--prefix') opt.prefix = v();
  else if (a === '--eval') opt.evalLuau = v();
  else if (a === '--dump') opt.dump = path.resolve(v()); // 빌드된 파트 전체를 JSON 으로 저장(tools/audit_geom.py 입력)
  else if (a === '--dump-filter') opt.dumpFilter = v(); // 루아 패턴: 경로(GetFullName)가 맞는 파트만
  else if (a === '--shotfile') { for (const ln of fs.readFileSync(v(), 'utf8').split('\n')) { const t = ln.trim(); if (!t || t.startsWith('#')) continue; const [n, spec] = t.split('='); opt.cams[n.trim()] = spec.trim(); } }
  else if (a === '--pick') opt.pick = v().split(';').map((q) => q.split(',').map(Number));
  else if (a === '--cam') { const [n, spec] = v().split('='); opt.cams[n] = spec; }
}

// name -> "x,y,z:lx,ly,lz:fov"
const SHOTS = {
  hero: '240,342,1433:-170,250,-1667:62', // 사진 구도 (Config.Viewpoint)
  wide: '0,867,3500:-167,200,-2333:60',
  landmark: '-200,183,-933:-717,700,-1967:65', // 타워 + 몰 근경
  tower_top: '-433,1500,-1367:-717,1700,-1967:55',
  bridge: '750,117,600:417,50,-667:65',
  park: '267,117,1433:-367,10,867:68', // 가까운 강변 공원
  deck: '-67,213,1167:-333,267,-1667:70', // 전망대에서 플레이어 눈높이
  skyline_right: '500,267,250:1067,433,-1750:62',
  skyline_left: '-833,267,250:-2000,400,-1833:62',
  city: '0,700,-3167:0,100,-6333:65',
  behind: '-67,233,1167:333,100,4333:70', // 뒤쪽(가까운 쪽 도시)
  aerial: '0,4333,3667:0,0,-1500:55',
  promenade: '-500,17,867:-167,67,-1000:70',
};

function walk(dir) {
  const entries = fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name));
  const kids = [];
  let init = null, cls = 'Folder';
  for (const e of entries) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) { kids.push(walk(p)); continue; }
    if (!/\.luau?$/.test(e.name)) continue;
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
const lstr = (s) => { let eq = '======'; while (s.includes(']' + eq + ']')) eq += '='; return '[' + eq + '[' + s + ']' + eq + ']'; };
const toLuau = (n) => '{name=' + JSON.stringify(n.name) + ',cls="' + n.cls + '",src=' + (n.src != null ? lstr(n.src) : 'nil') + ',children={' + n.children.map(toLuau).join(',') + '}}';
const BUILD = `
local I = GW.require("instance")
local Sched = GW.require("sched")
local Env = GW.require("env")
local S = GW.require("services").S
local Insert = GW.require("insert")
local function build(n)
  local inst
  if n.cls == "Folder" then inst = I.create("Folder", { name = n.name })
  else inst = I.create(n.cls, { name = n.name, props = { Source = n.src or "" }, newDefaults = true }) end
  for _, c in n.children do local ci = build(c) Sched.runIn(Env.serverCtx, I.setParent, ci, inst) end
  return inst
end
local function put(tree, parent) local inst = build(tree) Sched.runIn(Env.serverCtx, I.setParent, inst, parent) Sched.flush() return inst end
local function svc(name) local s; Sched.runIn(Env.serverCtx, function() s = S.game:GetService(name) end) return s end
`;

const CAM_SCRIPT = `
local RunService = game:GetService("RunService")
local cam = workspace.CurrentCamera
RunService.RenderStepped:Connect(function()
  local s = workspace:GetAttribute("PreviewCam")
  if typeof(s) ~= "string" then return end
  local v = string.split(s, ",")
  cam = workspace.CurrentCamera
  cam.CameraType = Enum.CameraType.Scriptable
  cam.FieldOfView = tonumber(v[7]) or 70
  cam.CFrame = CFrame.lookAt(Vector3.new(tonumber(v[1]), tonumber(v[2]), tonumber(v[3])), Vector3.new(tonumber(v[4]), tonumber(v[5]), tonumber(v[6])))
end)
`;

function buildScript(only) {
  const onlyT = only ? '{' + only.map((n) => '["' + n + '"]=true').join(',') + '}' : 'nil';
  return `
local Players = game:GetService("Players")
local SS = game:GetService("ServerStorage")
task.spawn(function()
  local plr = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
  local char = plr.Character or plr.CharacterAdded:Wait()
  local hrp = char:WaitForChild("HumanoidRootPart")
  hrp.Anchored = true
  char:PivotTo(CFrame.new(0, -400, 9000))
end)
local Map = require(SS:WaitForChild("SeoulSkyline"))
local t0 = os.clock()
local ok, err = pcall(Map.Build, { only = ${onlyT} })
if not ok then print("BUILD_ERROR " .. tostring(err)) end
local Kit = Map.Kit
local rows = {}
for _, o in Kit.terrainOps do
  local c = { o.cf:GetComponents() }
  table.insert(rows, string.format('["%s",%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,"%s"]', o.kind, o.size.X, o.size.Y, o.size.Z, c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12], o.material.Name))
end
print("TERRAIN_JSON[" .. table.concat(rows, ",") .. "]")
print(string.format("BUILD_DONE parts=%d lights=%d beacons=%d secs=%.1f", Kit.stats.parts, Kit.stats.lights, Kit.stats.beacons, os.clock() - t0))
`;
}

(async () => {
  fs.mkdirSync(opt.out, { recursive: true });
  const html = path.join(__dirname, 'studio_empty.html');
  if (!fs.existsSync(html)) { console.error('missing ' + html + ' — run: python3 seoul-skyline/tools/make_preview_studio.py'); process.exit(1); }
  const mapTree = walk(path.join(ROOT, 'src/ServerStorage/SeoulSkyline'));
  const clientDir = path.join(ROOT, 'src/StarterPlayer/StarterPlayerScripts/SeoulSkylineClient');
  const b = await chromium.launch({ args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const p = await b.newPage({ viewport: { width: opt.w, height: opt.h } });
  p.setDefaultTimeout(opt.timeout * 1000);
  let terrain = null, done = null;
  const errors = [];
  p.on('console', (m) => {
    const t = m.text();
    if (t.includes('TERRAIN_JSON[')) { terrain = JSON.parse(t.slice(t.indexOf('TERRAIN_JSON[') + 12)); return; }
    if (t.includes('BUILD_DONE')) done = t;
    if (t.includes('DUMP_ROWS[')) return;
    if (/GL Driver|quality tier/.test(t)) return;
    if (t.startsWith('[luau]') || t.startsWith('[shell]')) {
      if (/error|Error|실패|ERROR/.test(t)) errors.push(t);
      console.log(t.slice(0, 2000));
    }
  });
  p.on('pageerror', (e) => console.log('[pageerror]', e.message));
  await p.goto('file://' + html + '#quality=' + opt.quality + '&pr=1');
  await p.waitForFunction(() => window.GW && GW.engine && GW.engine.running, null, { timeout: 120000 });
  await p.waitForTimeout(1500);
  // the player culls small/dynamic parts by a size-based reach (phone tuning, capped at 3000 studs): Roblox at high
  // graphics quality draws the whole skyline, so widen the reach for previews
  await p.evaluate(() => {
    const R = GW.modules.render, T = R.TIERS;
    for (const k of Object.keys(T)) Object.assign(T[k], { base: 2400, k: 40, far: 16000, clip: 26000 });
    R.setQuality(R.getQuality());
    // the player's light halo sprites (phone substitute for bloom around lamps) do not exist in Roblox
    if (window.RblxGfx && RblxGfx._ && RblxGfx._.cfg) RblxGfx._.cfg.glow = 0;
  });
  const ev = (c) => p.evaluate((c) => GW.engine.eval(c).then((r) => String(r)).catch((e) => 'ERR ' + e), c);
  console.log('inject map:', await ev(BUILD + `local t = ${toLuau(mapTree)} put(t, svc("ServerStorage")) return "ok"`));
  // the local player may not exist yet right after boot: wait for its PlayerScripts before injecting client scripts
  for (let i = 0; i < 120; i++) { const r = await ev(BUILD + `local ok; Sched.runIn(Env.serverCtx, function() ok = S.player ~= nil and S.player:FindFirstChildOfClass("PlayerScripts") ~= nil end) return tostring(ok)`); if (r === 'true') break; await p.waitForTimeout(500); }
  console.log('inject cam:', await ev(BUILD + `local ps; Sched.runIn(Env.serverCtx, function() ps = S.player:FindFirstChildOfClass("PlayerScripts") end)
    local ok, e = pcall(Insert.createScript, ps, "LocalScript", "PreviewCam", ${lstr(CAM_SCRIPT)}) return tostring(ok) .. tostring(e)`));
  const t0 = Date.now();
  console.log('run build:', await ev(BUILD + `local ok, e = pcall(Insert.createScript, svc("ServerScriptService"), "Script", "PreviewBuild", ${lstr(buildScript(opt.only))}) return tostring(ok) .. tostring(e)`));
  while (!done && Date.now() - t0 < opt.timeout * 1000) await p.waitForTimeout(1000);
  console.log(done || 'BUILD TIMEOUT', 'wall', ((Date.now() - t0) / 1000).toFixed(1) + 's');
  if (opt.client && fs.existsSync(clientDir)) {
    console.log('inject client:', await ev(BUILD + `local t = ${toLuau(walk(clientDir))}
      local ps; Sched.runIn(Env.serverCtx, function() ps = S.player:FindFirstChildOfClass("PlayerScripts") end) put(t, ps) return "ok"`));
  }
  if (terrain && terrain.length) {
    const n = await p.evaluate((ops) => {
      const R = GW.modules.render, T = R.THREE, G = window.RblxGfx;
      const wedge = (() => {
        const v = [[-0.5, -0.5, -0.5], [0.5, -0.5, -0.5], [0.5, -0.5, 0.5], [-0.5, -0.5, 0.5], [-0.5, 0.5, 0.5], [0.5, 0.5, 0.5]];
        const f = [[0, 1, 2], [0, 2, 3], [3, 2, 5], [3, 5, 4], [0, 5, 1], [0, 4, 5], [0, 3, 4], [1, 5, 2]];
        const pos = []; for (const t of f) for (const i of t) pos.push(...v[i]);
        const g = new T.BufferGeometry(); g.setAttribute('position', new T.Float32BufferAttribute(pos, 3)); g.computeVertexNormals(); return g;
      })();
      const geos = { Block: new T.BoxGeometry(1, 1, 1), Ball: new T.IcosahedronGeometry(0.5, 3), Cylinder: new T.CylinderGeometry(0.5, 0.5, 1, 32), Wedge: wedge };
      let n = 0;
      for (const o of ops) {
        if (o[16] === 'Water' || o[16] === 'Air') continue;
        const mesh = new T.Mesh(geos[o[0]] || geos.Block, G.terrainMaterialFor(o[16]));
        const [sx, sy, sz, x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22] = o.slice(1, 16);
        mesh.matrixAutoUpdate = false;
        mesh.matrix.set(r00 * sx, r01 * sy, r02 * sz, x, r10 * sx, r11 * sy, r12 * sz, y, r20 * sx, r21 * sy, r22 * sz, z, 0, 0, 0, 1);
        mesh.receiveShadow = true; mesh.frustumCulled = false;
        R.scene.add(mesh); n++;
      }
      G.createWater(ops);
      return n;
    }, terrain);
    console.log('terrain meshes', n, 'ops', terrain.length);
  }
  // 에뮬레이터 한정: 빌드 중 부모가 늦게 붙은 SurfaceGui 는 글자 텍스처를 만들지 않음 → Enabled 를 껐다 켜서 다시 그리게 함
  {
    const TOGGLE = `
local root = workspace:WaitForChild("SeoulSkyline")
local guis = {}
for _, g in root:GetDescendants() do if g:IsA("SurfaceGui") then g.Enabled = false table.insert(guis, g) end end
task.wait(0.2)
for _, g in guis do g.Enabled = true end
print("GUI_TOGGLED " .. #guis)
`;
    let toggled = false;
    const onT = (m) => { if (m.text().includes('GUI_TOGGLED')) toggled = true; };
    p.on('console', onT);
    await ev(BUILD + `local ok, e = pcall(Insert.createScript, svc("ServerScriptService"), "Script", "PreviewGuiToggle", ${lstr(TOGGLE)}) return tostring(ok)`);
    for (let i = 0; i < 60 && !toggled; i++) await p.waitForTimeout(250);
    p.off('console', onT);
  }
  if (opt.dump) {
    // 파트 덤프: 한 줄에 200 개씩 DUMP_ROWS[...] 로 출력 → 합쳐서 JSON 저장
    const filt = opt.dumpFilter ? lstr(opt.dumpFilter) : 'nil';
    const DUMP = `
local root = workspace:WaitForChild("SeoulSkyline")
local filt = ${filt}
local rows, n = {}, 0
local function flush() if #rows > 0 then print("DUMP_ROWS[" .. table.concat(rows, ",") .. "]") rows = {} end end
for _, p in root:GetDescendants() do
  if p:IsA("BasePart") then
    local full = string.gsub(p:GetFullName(), '[%c"' .. string.char(92) .. ']', "_")
    if filt == nil or string.find(full, filt) then
      local c = { p.CFrame:GetComponents() }
      local shape = "Block"
      if p:IsA("WedgePart") then shape = "Wedge" elseif p:IsA("CornerWedgePart") then shape = "Corner" elseif p:IsA("Part") then shape = p.Shape.Name end
      if p:FindFirstChildOfClass("SpecialMesh") then shape = "Mesh" end
      local col = p.Color
      table.insert(rows, string.format('["%s","%s",%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%q,%.2f,%d,%d,%d,%d,%d]',
        full, shape, p.Size.X, p.Size.Y, p.Size.Z, c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12],
        p.Material.Name, p.Transparency, math.floor(col.R * 255 + 0.5), math.floor(col.G * 255 + 0.5), math.floor(col.B * 255 + 0.5), p.CanCollide and 1 or 0, #p:GetChildren()))
      n += 1
      if #rows >= 200 then flush() end
    end
  end
end
flush()
print("DUMP_DONE " .. n)
`;
    const dumpRows = []; let dumpDone = false;
    const onMsg = (m) => { const t = m.text(); const i = t.indexOf('DUMP_ROWS['); if (i >= 0) dumpRows.push(...JSON.parse(t.slice(i + 9))); else if (t.includes('DUMP_DONE')) dumpDone = true; };
    p.on('console', onMsg);
    await ev(BUILD + `local ok, e = pcall(Insert.createScript, svc("ServerScriptService"), "Script", "PreviewDump", ${lstr(DUMP)}) return tostring(ok)`);
    for (let i = 0; i < 600 && !dumpDone; i++) await p.waitForTimeout(500);
    p.off('console', onMsg);
    const cols = ['path', 'shape', 'sx', 'sy', 'sz', 'x', 'y', 'z', 'r00', 'r01', 'r02', 'r10', 'r11', 'r12', 'r20', 'r21', 'r22', 'material', 'transparency', 'r', 'g', 'b', 'collide', 'children'];
    fs.writeFileSync(opt.dump, JSON.stringify({ cols, rows: dumpRows }));
    console.log('dump', opt.dump, dumpRows.length, dumpDone ? 'parts' : 'parts (INCOMPLETE)');
  }
  if (opt.evalLuau) console.log('eval:', await ev(BUILD + `local ok, e = pcall(Insert.createScript, svc("ServerScriptService"), "Script", "PreviewEval", ${lstr(opt.evalLuau)}) return tostring(ok)`));
  await p.addStyleTag({ content: '*{visibility:hidden !important} canvas.gw-shot{visibility:visible !important}' });
  await p.evaluate(() => { const c = GW.modules.render.canvas; c.classList.add('gw-shot'); });
  const names = opt.shots || Object.keys(opt.cams).length ? (opt.shots || []).concat(Object.keys(opt.cams)) : ['hero'];
  for (const name of names) {
    const spec = opt.cams[name] || SHOTS[name];
    if (!spec) { console.log('unknown shot', name); continue; }
    const [a, l, f] = spec.split(':');
    const s = a + ',' + l + ',' + (f || '70');
    await ev(BUILD + `Sched.runIn(Env.serverCtx, function() S.game:GetService("Workspace"):SetAttribute("PreviewCam", "${s}") end) return "ok"`);
    await p.waitForTimeout(opt.settle * 1000);
    const file = path.join(opt.out, opt.prefix + name + '.png');
    await p.screenshot({ path: file });
    const sun = await p.evaluate(() => { const R = GW.modules.render; const d = RblxGfx.sunDirection(); const v = d.clone().multiplyScalar(20000).add(R.camera.position).project(R.camera);
      return { dir: [d.x, d.y, d.z].map((n) => +n.toFixed(3)), screen: [Math.round((v.x + 1) / 2 * innerWidth), Math.round((1 - v.y) / 2 * innerHeight)], inFront: v.z < 1, glow: RblxGfx._.cfg && RblxGfx._.cfg.glow }; });
    console.log('  sun', JSON.stringify(sun));
    for (const [x, y] of opt.pick || []) {
      const id = await p.evaluate(([x, y]) => { const h = GW.modules.render.pick(x, y, { includeTransparent: true }); return h && (h.id != null ? h.id : h); }, [x, y]);
      const info = id != null ? await ev(BUILD + `local inst; Sched.runIn(Env.serverCtx, function() inst = I.byId(${JSON.stringify(id)}) end) return inst and inst:GetFullName() .. " " .. inst.ClassName .. " " .. tostring(inst.Material) .. " " .. tostring(inst.Size) or "?"`) : 'none';
      console.log('  pick', x, y, '->', JSON.stringify(id), info);
    }
    console.log('shot', file);
  }
  const st = await p.evaluate(() => GW.modules.render.stats());
  console.log('render stats', JSON.stringify({ calls: st.calls, triangles: st.triangles, dynamicParts: st.dynamicParts, lights: st.lights, frameMs: st.frameMs }));
  if (errors.length) console.log('ERRORS:\n' + errors.join('\n'));
  await b.close();
})();
