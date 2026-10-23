# gen.py <module dir> <out.luau>: bundle GwangalliBuildingInterior modules for the offline sim (lazy requires)
import re, sys, os
src, out = sys.argv[1], sys.argv[2]
REQ = re.compile(r'require\(\s*script(?:\.Parent)?\s*:\s*WaitForChild\(\s*"([A-Za-z0-9_]+)"\s*\)\s*\)')
mods = {}
for e in sorted(os.listdir(src)):
    if e.endswith('.luau') and not e.startswith('init.'):
        mods[e[:-5]] = open(os.path.join(src, e), encoding='utf-8').read()
G = ['game', 'workspace', 'Workspace', 'Instance', 'task', 'Enum', 'CFrame', 'Vector3', 'Color3', 'UDim2', 'UDim', 'Vector2',
     'NumberRange', 'NumberSequence', 'NumberSequenceKeypoint', 'ColorSequence', 'ColorSequenceKeypoint', 'TweenInfo', 'BrickColor',
     'Ray', 'RaycastParams', 'OverlapParams', 'Random', 'Font', 'Region3', 'Rect', 'PhysicalProperties', 'DateTime', 'typeof', 'tick', 'time', 'warn']
o = ['--!nocheck', 'local R = require("../lib/rbx")', 'local E = R.env']
o.append('local ' + ', '.join(G) + ' = ' + ', '.join('E.' + g for g in G))
o.append('local __defs, __cache = {}, {}')
o.append('local function __require(n) local v = __cache[n] if v == nil then local f = __defs[n] if not f then error("no module " .. n) end v = f() __cache[n] = v end return v end')
ONLY = os.environ.get('ONLY')  # e.g. T_cafe: other T_* modules become empty stubs (isolation while agents edit in parallel)
for name, text in mods.items():
    if ONLY and name.startswith('T_') and name not in ONLY.split(','):
        text = 'return { types = {} }'
    text = REQ.sub(lambda m: '__require("%s")' % m.group(1), text)
    text = '\n'.join(l for l in text.split('\n') if not l.startswith('--!'))
    o.append('__defs["%s"] = function()\nlocal script = { Name = "%s" }\n%s\nend' % (name, name, text))
o.append('return __require')
open(out, 'w', encoding='utf-8').write('\n'.join(o))
print(out, len(mods), 'modules')
