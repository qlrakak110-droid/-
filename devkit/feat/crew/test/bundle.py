# bundle.py <out.luau>: GwangalliShopCrew shared + chosen server modules + ShopLife Scan/StreetShops for offline tests
import re, sys, os
S='/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad'
REPO='/home/user/-/src'
out=sys.argv[1]
mods={}
sh=REPO+'/ReplicatedStorage/GwangalliShopCrewShared'
for e in os.listdir(sh):
    if e.endswith('.luau'):
        mods['CS_'+(e[:-5] if e!='init.luau' else 'init')]=open(os.path.join(sh,e),encoding='utf-8').read()
sv=REPO+'/ServerScriptService/GwangalliShopCrew'
for e in os.listdir(sv):
    if e.endswith('.luau') and not e.startswith('init.'):
        mods['SV_'+e[:-5]]=open(os.path.join(sv,e),encoding='utf-8').read()
mods['SS']=open(S+'/bld/eff/ReplicatedStorage/GwangalliBuildingsShared/StreetShops.luau',encoding='utf-8').read()
mods['Scan']=open(S+'/bld/eff/ServerScriptService/GwangalliBuildings/ShopLife/Scan.luau',encoding='utf-8').read()
G=['game','workspace','Workspace','Instance','task','Enum','CFrame','Vector3','Color3','UDim2','UDim','Vector2','NumberRange','NumberSequence','NumberSequenceKeypoint','ColorSequence','ColorSequenceKeypoint','TweenInfo','BrickColor','Ray','RaycastParams','OverlapParams','Random','Region3','Rect','DateTime','typeof','tick','time','warn']
o=['--!nocheck','local R = require("../../../bprev/lib/rbx")','local E = R.env']
o.append('local '+', '.join(G)+' = '+', '.join('E.'+g for g in G))
o.append('do local _t = typeof; typeof = function(v) if type(v) == "table" and rawget(v, "_p") ~= nil then return "Instance" end return _t(v) end end')
if len(sys.argv) > 2 and sys.argv[2] == '--sim':
    o.append(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/crew/test/simhead.luau', encoding='utf-8').read())
o.append('local __defs, __cache = {}, {}')
o.append('local function __require(n) local v = __cache[n] if v == nil then local f = __defs[n] if not f then error("no module " .. n) end v = f() __cache[n] = v end return v end')
for name,text in mods.items():
    pre = 'CS_' if name.startswith('CS_') else ('SV_' if name.startswith('SV_') else '')
    text=re.sub(r'require\(\s*script(?:\.Parent)?\s*:\s*WaitForChild\(\s*"([A-Za-z0-9_]+)"\s*\)\s*\)', lambda m: '__require("%s%s")'%(pre if pre else '', m.group(1)) if pre else '__require("%s")'%m.group(1), text)
    text=text.replace('require(ReplicatedStorage:WaitForChild("GwangalliBuildingsShared"))','{ StreetShops = __require("SS") }')
    text='\n'.join(l for l in text.split('\n') if not l.startswith('--!'))
    o.append('__defs["%s"] = function()\nlocal script = { Name = "%s" }\n%s\nend'%(name,name,text))
o.append('return { req = __require, R = R, SIM = rawget(_G, "__SIM") or SIM }')
open(out,'w',encoding='utf-8').write('\n'.join(o))
print(out,len(mods))
