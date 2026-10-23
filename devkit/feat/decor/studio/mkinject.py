# mkinject.py: Luau injection codes for the temp studio -> inject.json
#   [shared, server, client, serverHelper, clientHelper]
import json, os, sys
sys.path.insert(0, '/home/user/-/tools')
import importlib.util
spec = importlib.util.spec_from_file_location('bs', '/home/user/-/tools/build_studio.py')
bs = importlib.util.module_from_spec(spec); spec.loader.exec_module(bs)
ROOT = '/home/user/-/src'
HERE = os.path.dirname(os.path.abspath(__file__))
shared = bs.walk(os.path.join(ROOT, 'ReplicatedStorage/GwangalliDecorShared'))
server = bs.walk(os.path.join(ROOT, 'ServerScriptService/GwangalliDecorPlus'))
client = bs.walk(os.path.join(ROOT, 'StarterPlayer/StarterPlayerScripts/GwangalliDecorPlus'))
def single(name, cls, path):
    return {"name": name, "cls": cls, "src": open(path, encoding='utf-8').read(), "children": []}
sh = single('DecorTestServer', 'Script', os.path.join(HERE, 'helper_server.luau'))
ch = single('DecorTestClient', 'LocalScript', os.path.join(HERE, 'helper_client.luau'))
B = bs.BUILD
codes = [
  B + 'local t = ' + bs.to_luau(shared) + '\nlocal RS; Sched.runIn(Env.serverCtx, function() RS = S.game:GetService("ReplicatedStorage") end)\nif RS:FindFirstChild("GwangalliDecorShared") then return "already" end\nput(t, RS) return "ok"',
  B + 'local t = ' + bs.to_luau(server) + '\nlocal SSS; Sched.runIn(Env.serverCtx, function() SSS = S.game:GetService("ServerScriptService") end)\nif SSS:FindFirstChild("GwangalliDecorPlus") then return "already" end\nput(t, SSS) return "ok"',
  B + 'local t = ' + bs.to_luau(client) + '\nlocal ps; Sched.runIn(Env.serverCtx, function() ps = S.player and S.player:FindFirstChildOfClass("PlayerScripts") end)\nif not ps then return "no PlayerScripts" end\nif ps:FindFirstChild("GwangalliDecorPlus") then return "already" end\nput(t, ps) return "ok"',
  B + 'local t = ' + bs.to_luau(sh) + '\nlocal SSS; Sched.runIn(Env.serverCtx, function() SSS = S.game:GetService("ServerScriptService") end)\nput(t, SSS) return "ok"',
  B + 'local t = ' + bs.to_luau(ch) + '\nlocal ps; Sched.runIn(Env.serverCtx, function() ps = S.player and S.player:FindFirstChildOfClass("PlayerScripts") end)\nif not ps then return "no PlayerScripts" end\nput(t, ps) return "ok"',
]
json.dump(codes, open(os.path.join(HERE, 'inject.json'), 'w'), ensure_ascii=False)
print('ok', [len(c) for c in codes])
