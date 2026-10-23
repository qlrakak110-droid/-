# bundle2.py out.luau name=path ...: modules as functions with Roblox globals taken from E (mock env)
import sys
out = sys.argv[1]
mods = [a.split('=',1) for a in sys.argv[2:]]
G = ['game','workspace','Instance','task','Enum','CFrame','Vector3','Color3','UDim2','UDim','Vector2','NumberSequence','ColorSequence','TweenInfo','RaycastParams','OverlapParams','Random','typeof','warn','Font','Rect','NumberRange']
w = ['--!nocheck','return function(E, extra)','local MODS, CACHE = {}, {}',
'local function tok(name) return { __mod = name, Name = name } end',
'local function mkscript(name) local s = { Name = name }; s.Parent = { WaitForChild = function(_, n) return tok(n) end, FindFirstChild = function(_, n) return tok(n) end }; s.WaitForChild = function(_, n) return tok(n) end; return s end',
'local function req(t) if type(t) == "table" and t.__mod then local n = t.__mod; if CACHE[n] == nil then CACHE[n] = MODS[n](mkscript(n)) end return CACHE[n] end if extra and extra[t] then return extra[t] end error("bad require "..tostring(t)) end']
loc = 'local ' + ', '.join(G) + ' = ' + ', '.join('E.' + g for g in G)
for name, path in mods:
    src = open(path, encoding='utf-8').read()
    w.append('MODS[%s] = function(script)\n local require = req\n %s\n%s\nend' % ('"%s"' % name, loc, src))
w.append('return { req = req, tok = tok }')
w.append('end')
open(out,'w',encoding='utf-8').write('\n'.join(w))
