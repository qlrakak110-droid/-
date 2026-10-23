#!/usr/bin/env python3
# Temp-studio HTML with GwangalliShopCrew injected (shared -> RS, Script -> SSS, LocalScript -> PlayerScripts).
import json, os, sys
sys.path.insert(0, '/home/user/-/tools')
from build_studio import walk, to_luau, BUILD
SRC = '/home/user/-/src'
SRC_HTML = '/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/v7zip/x/Gwangalli_Studio_v7-1.html'
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'crew.html')
shared = walk(os.path.join(SRC, 'ReplicatedStorage/GwangalliShopCrewShared'))
server = walk(os.path.join(SRC, 'ServerScriptService/GwangalliShopCrew'))
client = walk(os.path.join(SRC, 'StarterPlayer/StarterPlayerScripts/GwangalliShopCrew'))
code_shared = BUILD + "local t = " + to_luau(shared) + '''
local RS; Sched.runIn(Env.serverCtx, function() RS = S.game:GetService("ReplicatedStorage") end)
if RS:FindFirstChild("GwangalliShopCrewShared") then return "already" end
put(t, RS) return "ok"'''
code_server = BUILD + "local t = " + to_luau(server) + '''
local SSS; Sched.runIn(Env.serverCtx, function() SSS = S.game:GetService("ServerScriptService") end)
if SSS:FindFirstChild("GwangalliShopCrew") then return "already" end
put(t, SSS)
local sc = SSS:FindFirstChild("GwangalliShopCrew")
local ran = Env.ran[sc]
if not ran then Sched.runIn(Env.serverCtx, function() Env.runScript(sc, Env.peers.server) end) Sched.flush() end
return "ok ran=" .. tostring(ran)'''
hook = {"name": "GwCrewTestHook", "cls": "Script", "src": open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'hook.server.luau'), encoding='utf-8').read(), "children": []}
code_hook = BUILD + "local t = " + to_luau(hook) + '''
local SSS; Sched.runIn(Env.serverCtx, function() SSS = S.game:GetService("ServerScriptService") end)
if SSS:FindFirstChild("GwCrewTestHook") then return "already" end
put(t, SSS)
local sc = SSS:FindFirstChild("GwCrewTestHook")
if not Env.ran[sc] then Sched.runIn(Env.serverCtx, function() Env.runScript(sc, Env.peers.server) end) Sched.flush() end
return "ok"'''
code_client = BUILD + "local t = " + to_luau(client) + '''
local ps; Sched.runIn(Env.serverCtx, function() ps = S.player and S.player:FindFirstChildOfClass("PlayerScripts") end)
if not ps then return "no PlayerScripts" end
if ps:FindFirstChild("GwangalliShopCrew") then return "already" end
put(t, ps)
local sc = ps:FindFirstChild("GwangalliShopCrew")
return "ok ran=" .. tostring(Env.ran[sc])'''
js = '''<script>
(function () {
  var codes = %s;
  function wait(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }
  async function run() {
    for (var i = 0; i < 600; i++) { if (window.GW && GW.engine && GW.engine.running && GW.engine.eval) break; await wait(500); }
    if (!(window.GW && GW.engine && GW.engine.running)) { console.warn('[SC] engine not running'); return; }
    await wait(2500);
    try {
      console.log('[SC] shared:', await GW.engine.eval(codes[0]));
      console.log('[SC] server:', await GW.engine.eval(codes[1]));
      console.log('[SC] hook:', await GW.engine.eval(codes[3]));
      await wait(4000);
      for (var k = 0; k < 40; k++) { var r = await GW.engine.eval(codes[2]); console.log('[SC] client:', r); if (String(r).indexOf('ok') === 0 || r === 'already') break; await wait(3000); }
      window.__scInjected = true;
    } catch (e) { console.error('[SC] inject failed', e); }
  }
  run();
})();
</script>
''' % json.dumps([code_shared, code_server, code_client, code_hook], ensure_ascii=False).replace("</", "<\\/")
html = open(SRC_HTML, encoding='utf-8').read()
i = html.rfind('</body>')
html = html[:i] + js + html[i:]
open(OUT, 'w', encoding='utf-8').write(html)
print(OUT, os.path.getsize(OUT))
