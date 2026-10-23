#!/usr/bin/env python3
# Temp-studio HTML with GwangalliClubPlus injected (shared -> RS, Script -> SSS, LocalScript -> PlayerScripts).
import json, os, sys
sys.path.insert(0, '/home/user/-/tools')
from build_studio import walk, to_luau, BUILD
SRC = '/home/user/-/src'
SRC_HTML = '/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/v7zip/x/Gwangalli_Studio_v7-1.html'
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'club.html')
shared = walk(os.path.join(SRC, 'ReplicatedStorage/GwangalliClubPlusShared'))
# test build only: the temp studio's JS engine is slow, so every tier uses the low budget
shared['src'] = shared['src'].replace('\t\thigh = { lasers = 4, beams = 10, hz = 30, heads = 8,', '\t\thigh = { lasers = 2, beams = 6, hz = 15, heads = 3,').replace('\t\tmid = { lasers = 3, beams = 8, hz = 30, heads = 6,', '\t\tmid = { lasers = 2, beams = 6, hz = 15, heads = 3,')
server = walk(os.path.join(SRC, 'ServerScriptService/GwangalliClubPlus'))
client = walk(os.path.join(SRC, 'StarterPlayer/StarterPlayerScripts/GwangalliClubPlus'))
code_shared = BUILD + "local t = " + to_luau(shared) + '''
local RS; Sched.runIn(Env.serverCtx, function() RS = S.game:GetService("ReplicatedStorage") end)
if RS:FindFirstChild("GwangalliClubPlusShared") then return "already" end
put(t, RS) return "ok"'''
code_server = BUILD + "local t = " + to_luau(server) + '''
local SSS; Sched.runIn(Env.serverCtx, function() SSS = S.game:GetService("ServerScriptService") end)
if SSS:FindFirstChild("GwangalliClubPlus") then return "already" end
put(t, SSS)
local sc = SSS:FindFirstChild("GwangalliClubPlus")
local ran = Env.ran[sc]
if not ran then Sched.runIn(Env.serverCtx, function() Env.runScript(sc, Env.peers.server) end) Sched.flush() end
return "ok ran=" .. tostring(ran)'''
code_client = BUILD + "local t = " + to_luau(client) + '''
local ps; Sched.runIn(Env.serverCtx, function() ps = S.player and S.player:FindFirstChildOfClass("PlayerScripts") end)
if not ps then return "no PlayerScripts" end
if ps:FindFirstChild("GwangalliClubPlus") then return "already" end
put(t, ps)
local sc = ps:FindFirstChild("GwangalliClubPlus")
return "ok ran=" .. tostring(Env.ran[sc])'''
js = '''<script>
(function () {
  var codes = %s;
  function wait(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }
  async function run() {
    for (var i = 0; i < 600; i++) { if (window.GW && GW.engine && GW.engine.running && GW.engine.eval) break; await wait(500); }
    if (!(window.GW && GW.engine && GW.engine.running)) { console.warn('[CP] engine not running'); return; }
    await wait(2500);
    try {
      console.log('[CP] shared:', await GW.engine.eval(codes[0]));
      console.log('[CP] server:', await GW.engine.eval(codes[1]));
      await wait(4000);
      for (var k = 0; k < 40; k++) { var r = await GW.engine.eval(codes[2]); console.log('[CP] client:', r); if (String(r).indexOf('ok') === 0 || r === 'already') break; await wait(3000); }
      window.__cpInjected = true;
    } catch (e) { console.error('[CP] inject failed', e); }
  }
  run();
})();
</script>
''' % json.dumps([code_shared, code_server, code_client], ensure_ascii=False).replace("</", "<\\/")
html = open(SRC_HTML, encoding='utf-8').read()
i = html.rfind('</body>')
html = html[:i] + js + html[i:]
open(OUT, 'w', encoding='utf-8').write(html)
print(OUT, os.path.getsize(OUT))
