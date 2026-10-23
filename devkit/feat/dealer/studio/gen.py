import json, os, sys
import importlib.util
spec = importlib.util.spec_from_file_location('bs', '/home/user/-/tools/build_studio.py')
bs = importlib.util.module_from_spec(spec); spec.loader.exec_module(bs)
src = '/home/user/-/src'
here = os.path.dirname(os.path.abspath(__file__))
shared = bs.walk(os.path.join(src, 'ReplicatedStorage/GwangalliCarDealerShared'))
server = bs.walk(os.path.join(src, 'ServerScriptService/GwangalliCarDealer'))
client = bs.walk(os.path.join(src, 'StarterPlayer/StarterPlayerScripts/GwangalliCarDealer'))
B = bs.BUILD
def into(tree, where, name):
    if where == 'RS':
        loc = 'local P0; Sched.runIn(Env.serverCtx, function() P0 = S.game:GetService("ReplicatedStorage") end)'
    elif where == 'SSS':
        loc = 'local P0; Sched.runIn(Env.serverCtx, function() P0 = S.game:GetService("ServerScriptService") end)'
    else:
        loc = 'local P0; Sched.runIn(Env.serverCtx, function() P0 = S.player and S.player:FindFirstChildOfClass("PlayerScripts") end) if not P0 then return "no PlayerScripts" end'
    return B + 'local t = ' + bs.to_luau(tree) + '\n' + loc + '\nif P0:FindFirstChild("%s") then return "already" end\nput(t, P0) return "ok"' % name
helper = {"name": "DealerClientTest", "cls": "LocalScript", "src": open(os.path.join(here, 'helper/DealerClientTest.client.luau')).read(), "children": []}
codes = [into(shared, 'RS', 'GwangalliCarDealerShared'), into(server, 'SSS', 'GwangalliCarDealer'), into(client, 'PS', 'GwangalliCarDealer'), into(helper, 'PS', 'DealerClientTest')]
json.dump(codes, open(os.path.join(here, 'inject.json'), 'w'), ensure_ascii=False)
print('ok', sum(len(c) for c in codes))
