#!/usr/bin/env python3
# Builds a temp-studio HTML with GwangalliPasses injected (shared -> RS, Script -> SSS, LocalScript -> PlayerScripts).
# Test build only: pass Ids are set to 1 so the live code path runs; admin-free grants ownership.
import json, os, sys
sys.path.insert(0, '/home/user/-/tools')
from build_studio import walk, to_luau, BUILD
SRC = '/home/user/-/src'
SRC_HTML = '/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/v7zip/x/Gwangalli_Studio_v7-1.html'
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'passes.html')
shared = walk(os.path.join(SRC, 'ReplicatedStorage/GwangalliPassesShared'))
for c in shared['children']:
    if c['name'] == 'Config':
        c['src'] = c['src'].replace('\t\tId = 0, -- 대시보드 게임패스 번호', '\t\tId = 1,').replace('\t\tId = 0,\n', '\t\tId = 1,\n')
server = walk(os.path.join(SRC, 'ServerScriptService/GwangalliPasses'))
client = walk(os.path.join(SRC, 'StarterPlayer/StarterPlayerScripts/GwangalliPasses'))
code_shared = BUILD + "local t = " + to_luau(shared) + '''
local RS; Sched.runIn(Env.serverCtx, function() RS = S.game:GetService("ReplicatedStorage")
  S.game.Workspace:SetAttribute("GwPassesAdminFree", true)
  if S.player then S.player:SetAttribute("GwangalliAdmin", true) end
end)
if RS:FindFirstChild("GwangalliPassesShared") then return "already" end
put(t, RS) return "ok"'''
code_server = BUILD + "local t = " + to_luau(server) + '''
local SSS; Sched.runIn(Env.serverCtx, function() SSS = S.game:GetService("ServerScriptService") end)
if SSS:FindFirstChild("GwangalliPasses") then return "already" end
put(t, SSS)
local sc = SSS:FindFirstChild("GwangalliPasses")
local ran = Env.ran[sc]
if not ran then Sched.runIn(Env.serverCtx, function() Env.runScript(sc, Env.peers.server) end) Sched.flush() end
return "ok ran=" .. tostring(ran)'''
code_client = BUILD + "local t = " + to_luau(client) + '''
local ps; Sched.runIn(Env.serverCtx, function() ps = S.player and S.player:FindFirstChildOfClass("PlayerScripts") end)
if not ps then return "no PlayerScripts" end
if ps:FindFirstChild("GwangalliPasses") then return "already" end
put(t, ps)
local sc = ps:FindFirstChild("GwangalliPasses")
return "ok ran=" .. tostring(Env.ran[sc])'''
js = '''<script>
(function () {
  var codes = %s;
  function wait(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }
  async function run() {
    for (var i = 0; i < 600; i++) { if (window.GW && GW.engine && GW.engine.running && GW.engine.eval) break; await wait(500); }
    if (!(window.GW && GW.engine && GW.engine.running)) { console.warn('[GP] engine not running'); return; }
    await wait(2500);
    try {
      console.log('[GP] shared:', await GW.engine.eval(codes[0]));
      console.log('[GP] server:', await GW.engine.eval(codes[1]));
      await wait(4000);
      for (var k = 0; k < 40; k++) { var r = await GW.engine.eval(codes[2]); console.log('[GP] client:', r); if (String(r).indexOf('ok') === 0 || r === 'already') break; await wait(3000); }
      window.__gpInjected = true;
    } catch (e) { console.error('[GP] inject failed', e); }
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
