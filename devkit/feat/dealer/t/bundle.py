# bundle.py out.luau name=path ... : wraps module sources as functions(script) for the luau CLI
import sys
out = sys.argv[1]
mods = [a.split('=',1) for a in sys.argv[2:]]
w = ['--!nocheck','local MODS, CACHE = {}, {}',
'local function tok(name) return { __mod = name, Name = name } end',
'local function mkscript(name) local s = { Name = name }; s.Parent = { WaitForChild = function(_, n) return tok(n) end, FindFirstChild = function(_, n) return tok(n) end }; s.WaitForChild = function(_, n) return tok(n) end; return s end',
'local function req(t) if type(t) == "table" and t.__mod then local n = t.__mod; if CACHE[n] == nil then CACHE[n] = MODS[n](mkscript(n)) end return CACHE[n] end error("bad require "..tostring(t)) end',
'_G.BREQ = req; _G.BTOK = tok']
for name, path in mods:
    src = open(path, encoding='utf-8').read()
    w.append('MODS[%r] = function(script)\n local require = req\n%s\nend' % (name, src))
w.append('return { req = req, tok = tok, MODS = MODS }')
open(out,'w',encoding='utf-8').write('\n'.join(w).replace("MODS['","MODS[\"").replace("'] = function","\"] = function"))
