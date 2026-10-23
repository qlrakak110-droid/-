import json, os, sys
sys.path.insert(0, '/home/user/-/tools')
import importlib.util
spec = importlib.util.spec_from_file_location('bs', '/home/user/-/tools/build_studio.py')
bs = importlib.util.module_from_spec(spec); spec.loader.exec_module(bs)
src = '/home/user/-/src'
shared = bs.walk(os.path.join(src, 'ReplicatedStorage/GwangalliClinicShared'))
server = bs.walk(os.path.join(src, 'ServerScriptService/GwangalliClinic'))
client = bs.walk(os.path.join(src, 'StarterPlayer/StarterPlayerScripts/GwangalliClinic'))
B = bs.BUILD
code_shared = B + 'local t = ' + bs.to_luau(shared) + '''
local RS; Sched.runIn(Env.serverCtx, function() RS = S.game:GetService("ReplicatedStorage") end)
if RS:FindFirstChild("GwangalliClinicShared") then return "already" end
put(t, RS) return "ok"'''
code_server = B + 'local t = ' + bs.to_luau(server) + '''
local SSS; Sched.runIn(Env.serverCtx, function() SSS = S.game:GetService("ServerScriptService") end)
if SSS:FindFirstChild("GwangalliClinic") then return "already" end
put(t, SSS) return "ok"'''
code_client = B + 'local t = ' + bs.to_luau(client) + '''
local ps; Sched.runIn(Env.serverCtx, function() ps = S.player and S.player:FindFirstChildOfClass("PlayerScripts") end)
if not ps then return "no PlayerScripts" end
if ps:FindFirstChild("GwangalliClinic") then return "already" end
put(t, ps) return "ok"'''
helper = {"name": "ClinicTest", "cls": "Script", "src": open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'helper/ClinicTest.server.luau')).read(), "children": []}
code_helper = B + 'local t = ' + bs.to_luau(helper) + '''
local SSS; Sched.runIn(Env.serverCtx, function() SSS = S.game:GetService("ServerScriptService") end)
if SSS:FindFirstChild("ClinicTest") then return "already" end
put(t, SSS) return "ok"'''
chelper = {"name": "ClinicClientTest", "cls": "LocalScript", "src": open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'helper/ClinicClientTest.client.luau')).read(), "children": []}
code_chelper = B + 'local t = ' + bs.to_luau(chelper) + '''
local ps; Sched.runIn(Env.serverCtx, function() ps = S.player and S.player:FindFirstChildOfClass("PlayerScripts") end)
if not ps then return "no PlayerScripts" end
if ps:FindFirstChild("ClinicClientTest") then return "already" end
put(t, ps) return "ok"'''
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'inject.json')
json.dump([code_shared, code_server, code_client, code_helper, code_chelper], open(out, 'w'), ensure_ascii=False)
print(out, os.path.getsize(out))
