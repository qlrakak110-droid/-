# mkcat.py: bundle the shared Kit + Furniture modules (place dump) for the offline mock runtime -> cat_mods.luau
import sys, re
SRC = '/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/src/ReplicatedStorage/GwangalliBuildingsShared/'
G = ['game', 'workspace', 'Workspace', 'Instance', 'task', 'Enum', 'CFrame', 'Vector3', 'Color3', 'UDim2', 'UDim', 'Vector2', 'TweenInfo', 'typeof', 'warn']
o = ['--!nocheck', 'local R = require("../../../bprev/lib/rbx")', 'local E = R.env']
o.append('local ' + ', '.join(G) + ' = ' + ', '.join('E.' + g for g in G))
o.append('local __CS = { AddTag = function(_, i, t) i:AddTag(t) end, HasTag = function(_, i, t) return i:HasTag(t) end, RemoveTag = function(_, i, t) i:RemoveTag(t) end }')
for name in ['Kit', 'Furniture']:
    t = open(SRC + name + '.ModuleScript.luau', encoding='utf-8').read()
    t = t.replace('require(script.Parent.Kit)', '__Kit')
    t = t.replace('game:GetService("CollectionService")', '__CS')
    t = '\n'.join(l for l in t.split('\n') if not l.startswith('--!'))
    o.append('local __%s = (function()\n%s\nend)()' % (name, t))
o.append('return { Kit = __Kit, Furniture = __Furniture, R = R }')
open(sys.argv[1], 'w', encoding='utf-8').write('\n'.join(o))
