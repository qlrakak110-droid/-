import json, os, sys, importlib.util
spec = importlib.util.spec_from_file_location('bs', '/home/user/-/tools/build_studio.py')
bs = importlib.util.module_from_spec(spec); spec.loader.exec_module(bs)
srv, cli, out = sys.argv[1], sys.argv[2], sys.argv[3]
B = bs.BUILD
def node(name, cls, path):
    return {"name": name, "cls": cls, "src": open(path, encoding="utf-8").read(), "children": []}
code_server = B + 'local t = ' + bs.to_luau(node("GwangalliPlus", "Script", srv)) + '''
local SSS; Sched.runIn(Env.serverCtx, function() SSS = S.game:GetService("ServerScriptService") end)
put(t, SSS) return "ok"'''
code_client = B + 'local t = ' + bs.to_luau(node("GwangalliPlus", "LocalScript", cli)) + '''
local ps; Sched.runIn(Env.serverCtx, function() ps = S.player and S.player:FindFirstChildOfClass("PlayerScripts") end)
if not ps then return "no PlayerScripts" end
put(t, ps) return "ok"'''
json.dump([code_server, code_client], open(out, 'w'), ensure_ascii=False)
print(out, os.path.getsize(out))
