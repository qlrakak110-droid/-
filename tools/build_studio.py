#!/usr/bin/env python3
"""Embeds src/ into the 광안리 임시 스튜디오 HTML: after the engine boots, the minigame tree is inserted
(ReplicatedStorage / ServerScriptService.GwangalliGameplay / the local PlayerScripts) and the core
script's FEATURE_MODULES gets "MiniGames" (hot reload), exactly like tools/harness.js.

    python3 tools/build_studio.py <input studio.html> <output.html>
"""
import json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def walk(path):
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
local function build(n)
  local inst
  if n.cls == "Folder" then inst = I.create("Folder", { name = n.name })
  else inst = I.create(n.cls, { name = n.name, props = { Source = n.src or "" }, newDefaults = true }) end
  for _, c in n.children do Sched.runIn(Env.serverCtx, I.setParent, build(c), inst) end
  return inst
end
local function put(tree, parent) Sched.runIn(Env.serverCtx, I.setParent, build(tree), parent) Sched.flush() end
'''


def main():
    src_html, out_html = sys.argv[1], sys.argv[2]
    src = os.path.join(ROOT, "src")
    shared = walk(os.path.join(src, "ReplicatedStorage/GwangalliMiniGamesShared"))
    server = walk(os.path.join(src, "ServerScriptService/GwangalliGameplay/MiniGames"))
    client = walk(os.path.join(src, "StarterPlayer/StarterPlayerScripts/GwangalliMiniGames"))
    code_shared = BUILD + "local t = " + to_luau(shared) + '''
local RS; Sched.runIn(Env.serverCtx, function() RS = S.game:GetService("ReplicatedStorage") end)
if RS:FindFirstChild("GwangalliMiniGamesShared") then return "already" end
put(t, RS) return "ok"'''
    code_server = BUILD + "local t = " + to_luau(server) + '''
local folder, core
Sched.runIn(Env.serverCtx, function()
  for _, c in S.game:GetService("ServerScriptService"):GetChildren() do
    if c.Name == "GwangalliGameplay" and c:IsA("Folder") then folder = c end
    if c.Name == "GwangalliGameplay" and c:IsA("Script") then core = c end
  end
end)
if not folder or not core then return "no GwangalliGameplay" end
if folder:FindFirstChild("MiniGames") then return "already" end
put(t, folder)
local src = Env.sourceOf(core)
local n
src, n = string.gsub(src, 'local FEATURE_MODULES = { "Bank",', 'local FEATURE_MODULES = { "MiniGames", "Bank",')
local r = GW.require("insert").hotReload(core, src, { force = true })
return "patched=" .. tostring(n) .. " ok=" .. tostring(r and r.ok)'''
    code_client = BUILD + "local t = " + to_luau(client) + '''
local ps; Sched.runIn(Env.serverCtx, function() ps = S.player and S.player:FindFirstChildOfClass("PlayerScripts") end)
if not ps then return "no PlayerScripts" end
if ps:FindFirstChild("GwangalliMiniGames") then return "already" end
put(t, ps) return "ok"'''
    js = '''<script>
/* 광안리 해변 미니게임 거리: injects the MiniGames scripts into the running place (tools/build_studio.py) */
(function () {
  var codes = %s;
  function wait(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }
  async function run() {
    for (var i = 0; i < 600; i++) {
      if (window.GW && GW.engine && GW.engine.running && GW.engine.eval) break;
      await wait(500);
    }
    if (!(window.GW && GW.engine && GW.engine.running)) { console.warn('[MiniGames] engine not running; not injected'); return; }
    await wait(2500);
    try {
      console.log('[MiniGames] shared:', await GW.engine.eval(codes[0]));
      console.log('[MiniGames] server:', await GW.engine.eval(codes[1]));
      await wait(4000);
      console.log('[MiniGames] client:', await GW.engine.eval(codes[2]));
    } catch (e) { console.error('[MiniGames] inject failed', e); }
  }
  run();
})();
</script>
''' % json.dumps([code_shared, code_server, code_client], ensure_ascii=False).replace("</", "<\\/")
    html = open(src_html, encoding="utf-8").read()
    i = html.rfind("</body>")
    html = html[:i] + js + html[i:] if i >= 0 else html + js
    html = html.replace("<title>광안리 임시 스튜디오 1.0 v2.0</title>", "<title>광안리 임시 스튜디오 1.0 v2.0 + 해변 미니게임</title>")
    open(out_html, "w", encoding="utf-8").write(html)
    print(out_html, os.path.getsize(out_html))


if __name__ == "__main__":
    main()
