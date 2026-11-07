#!/usr/bin/env python3
"""Builds a playable HTML (광안리 임시 스튜디오 엔진, empty place) with the Seoul skyline map: when the engine is up, the
SeoulSkyline module tree goes into ServerStorage, SeoulSkylineBoot into ServerScriptService (it builds the map) and the client
effects into the local PlayerScripts. The player draws terrain only from a static export, so the recorded terrain ops
(Kit.terrainOps) are turned into meshes + the water surface by this page (same as tools/preview.js).

    python3 seoul-skyline/tools/make_studio.py [out.html]      (default: seoul-skyline/dist/SeoulSkyline_Studio.html)
needs seoul-skyline/tools/studio_empty.html (python3 seoul-skyline/tools/make_preview_studio.py)
"""
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(ROOT, "src")


def walk(path):
    if os.path.isfile(path):
        base = os.path.basename(path).rsplit(".", 1)[0]
        c, n = "ModuleScript", base
        if base.endswith(".server"): c, n = "Script", base[:-7]
        if base.endswith(".client"): c, n = "LocalScript", base[:-7]
        return {"name": n, "cls": c, "src": open(path, encoding="utf-8").read(), "children": []}
    kids, cls, src = [], "Folder", None
    for e in sorted(os.listdir(path)):
        p = os.path.join(path, e)
        if os.path.isdir(p):
            kids.append(walk(p)); continue
        if not e.endswith(".luau"):
            continue
        base = e[:-5]
        text = open(p, encoding="utf-8").read()
        c, n = "ModuleScript", base
        if base.endswith(".server"): c, n = "Script", base[:-7]
        if base.endswith(".client"): c, n = "LocalScript", base[:-7]
        if n == "init":
            cls, src = c, text
        else:
            kids.append({"name": n, "cls": c, "src": text, "children": []})
    return {"name": os.path.basename(path), "cls": cls, "src": src, "children": kids}


def lstr(s):
    eq = "======"
    while ("]" + eq + "]") in s:
        eq += "="
    return "[" + eq + "[" + s + "]" + eq + "]"


def to_luau(n):
    return '{name=%s,cls="%s",src=%s,children={%s}}' % (json.dumps(n["name"], ensure_ascii=False), n["cls"], lstr(n["src"]) if n["src"] is not None else "nil", ",".join(to_luau(c) for c in n["children"]))


BUILD = '''
local I = GW.require("instance")
local Sched = GW.require("sched")
local Env = GW.require("env")
local S = GW.require("services").S
local Insert = GW.require("insert")
local function build(n)
  local inst
  if n.cls == "Folder" then inst = I.create("Folder", { name = n.name })
  else inst = I.create(n.cls, { name = n.name, props = { Source = n.src or "" }, newDefaults = true }) end
  for _, c in n.children do Sched.runIn(Env.serverCtx, I.setParent, build(c), inst) end
  return inst
end
local function put(tree, parent) Sched.runIn(Env.serverCtx, I.setParent, build(tree), parent) Sched.flush() end
local function svc(name) local s; Sched.runIn(Env.serverCtx, function() s = S.game:GetService(name) end) return s end
'''

# holds the character on the deck while the map builds, then prints the terrain ops for the page
HELPER = r'''
local Players = game:GetService("Players")
local SS = game:GetService("ServerStorage")
local Map = require(SS:WaitForChild("SeoulSkyline"))
local V = Map.Config.Viewpoint
task.spawn(function()
  local plr = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
  local char = plr.Character or plr.CharacterAdded:Wait()
  local hrp = char:WaitForChild("HumanoidRootPart")
  hrp.Anchored = true
  char:PivotTo(CFrame.lookAt(Vector3.new(V.DeckCenter.X, V.DeckHeight + 4, V.DeckCenter.Z), Vector3.new(V.DeckCenter.X, V.DeckHeight + 4, V.DeckCenter.Z - 100)))
  local root = workspace:WaitForChild(Map.Config.ROOT_NAME, 600)
  task.wait(1)
  local spawn = root and root:FindFirstChildWhichIsA("SpawnLocation", true)
  if spawn then char:PivotTo(spawn.CFrame * CFrame.new(0, 4, 0)) end
  hrp.Anchored = false
  local rows = {}
  for _, o in Map.Kit.terrainOps do
    local c = { o.cf:GetComponents() }
    table.insert(rows, string.format('["%s",%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,"%s"]', o.kind, o.size.X, o.size.Y, o.size.Z, c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12], o.material.Name))
  end
  print("TERRAIN_JSON[" .. table.concat(rows, ",") .. "]")
  print("SEOUL_READY")
end)
'''

JS = r'''<script>
/* 서울 한강 야경 맵 (seoul-skyline/tools/make_studio.py): injects the map scripts into the running empty place */
(function () {
  var codes = %(codes)s;
  var overlay = document.createElement('div');
  overlay.style.cssText = 'position:fixed;left:50%%;top:18px;transform:translateX(-50%%);z-index:99999;padding:10px 18px;border-radius:14px;background:rgba(12,16,28,.78);color:#eef1f8;font:600 14px system-ui,"Noto Sans KR",sans-serif;backdrop-filter:blur(8px);box-shadow:0 8px 24px rgba(0,0,0,.4);pointer-events:none;transition:opacity .6s';
  overlay.textContent = '서울 한강 야경 맵 준비 중…';
  function wait(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }
  var terrainDone = false;
  function buildTerrain(ops) {
    var R = GW.modules.render, T = R.THREE, G = window.RblxGfx;
    var v = [[-0.5, -0.5, -0.5], [0.5, -0.5, -0.5], [0.5, -0.5, 0.5], [-0.5, -0.5, 0.5], [-0.5, 0.5, 0.5], [0.5, 0.5, 0.5]];
    var f = [[0, 1, 2], [0, 2, 3], [3, 2, 5], [3, 5, 4], [0, 5, 1], [0, 4, 5], [0, 3, 4], [1, 5, 2]];
    var pos = []; f.forEach(function (t) { t.forEach(function (i) { pos.push(v[i][0], v[i][1], v[i][2]); }); });
    var wedge = new T.BufferGeometry(); wedge.setAttribute('position', new T.Float32BufferAttribute(pos, 3)); wedge.computeVertexNormals();
    var geos = { Block: new T.BoxGeometry(1, 1, 1), Ball: new T.IcosahedronGeometry(0.5, 3), Cylinder: new T.CylinderGeometry(0.5, 0.5, 1, 32), Wedge: wedge };
    ops.forEach(function (o) {
      if (o[16] === 'Water' || o[16] === 'Air') return;
      var mesh = new T.Mesh(geos[o[0]] || geos.Block, G.terrainMaterialFor(o[16]));
      var sx = o[1], sy = o[2], sz = o[3];
      mesh.matrixAutoUpdate = false;
      mesh.matrix.set(o[7] * sx, o[8] * sy, o[9] * sz, o[4], o[10] * sx, o[11] * sy, o[12] * sz, o[5], o[13] * sx, o[14] * sy, o[15] * sz, o[6], 0, 0, 0, 1);
      mesh.receiveShadow = true; mesh.frustumCulled = false;
      R.scene.add(mesh);
    });
    G.createWater(ops);
  }
  var origLog = console.log;
  console.log = function () {
    try {
      var t = String(arguments[0] || '');
      if (t.indexOf('TERRAIN_JSON[') >= 0 && !terrainDone) { terrainDone = true; buildTerrain(JSON.parse(t.slice(t.indexOf('TERRAIN_JSON[') + 12))); return; }
      if (t.indexOf('SEOUL_READY') >= 0) { overlay.textContent = '서울 한강 야경 · 전망대의 📷 포토 스팟에서 사진 구도'; setTimeout(function () { overlay.style.opacity = '0'; }, 5000); }
      else if (t.indexOf('[SeoulSkyline]') >= 0 && t.indexOf('완료') >= 0) overlay.textContent = '맵 생성 완료 · 지형 그리는 중…';
    } catch (e) { /* */ }
    return origLog.apply(console, arguments);
  };
  async function run() {
    for (var i = 0; i < 600; i++) {
      if (window.GW && GW.engine && GW.engine.running && GW.engine.eval) break;
      await wait(500);
    }
    if (!(window.GW && GW.engine && GW.engine.running)) { console.warn('[SeoulSkyline] engine not running; not injected'); return; }
    // real-scale skyline (1 stud = 0.3 m, tower 1850 studs, city to ~11 km): widen the player's size-based draw reach
    try {
      var R = GW.modules.render, T = R.TIERS;
      Object.keys(T).forEach(function (k) { T[k].far = Math.max(T[k].far, 14000); T[k].base = Math.max(T[k].base, 900); T[k].k = Math.max(T[k].k, 28); T[k].clip = Math.max(T[k].clip, 26000); });
      R.setQuality(R.getQuality());
    } catch (e) { /* */ }
    document.body.appendChild(overlay);
    overlay.textContent = '서울 한강 야경 맵 생성 중… (수십 초)';
    await wait(800);
    try {
      for (var k = 0; k < codes.length; k++) console.log('[SeoulSkyline] inject ' + k + ':', await GW.engine.eval(codes[k]));
    } catch (e) { console.error('[SeoulSkyline] inject failed', e); overlay.textContent = '맵 주입 실패: ' + e; }
  }
  run();
})();
</script>
'''


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "dist", "SeoulSkyline_Studio.html")
    base = os.path.join(HERE, "studio_empty.html")
    mod = walk(os.path.join(SRC, "ServerStorage/SeoulSkyline"))
    client_dir = os.path.join(SRC, "StarterPlayer/StarterPlayerScripts/SeoulSkylineClient")
    boot = open(os.path.join(SRC, "ServerScriptService/SeoulSkylineBoot.server.luau"), encoding="utf-8").read()
    codes = [
        BUILD + "local t = " + to_luau(mod) + '\nput(t, svc("ServerStorage")) return "map module ok"',
        BUILD + 'local ok, e = pcall(Insert.createScript, svc("ServerScriptService"), "Script", "SeoulSkylineHelper", ' + lstr(HELPER) + ') return "helper " .. tostring(ok)',
        BUILD + 'local ok, e = pcall(Insert.createScript, svc("ServerScriptService"), "Script", "SeoulSkylineBoot", ' + lstr(boot) + ') return "boot " .. tostring(ok)',
    ]
    if os.path.isdir(client_dir):
        codes.append(BUILD + "local t = " + to_luau(walk(client_dir)) + '''
local ps; Sched.runIn(Env.serverCtx, function() ps = S.player and S.player:FindFirstChildOfClass("PlayerScripts") end)
if not ps then return "no PlayerScripts" end
put(t, ps) return "client ok"''')
    js = JS % {"codes": json.dumps(codes, ensure_ascii=False).replace("</", "<\\/")}
    html = open(base, encoding="utf-8").read()
    i = html.rfind("</body>")
    html = html[:i] + js + html[i:] if i >= 0 else html + js
    import re
    html = re.sub(r"<title>.*?</title>", "<title>서울 한강 야경 · 잠실 (Roblox 맵 미리보기)</title>", html, count=1, flags=re.S)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    open(out, "w", encoding="utf-8").write(html)
    print(out, os.path.getsize(out))


if __name__ == "__main__":
    main()
