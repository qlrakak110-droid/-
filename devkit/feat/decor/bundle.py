# bundle.py <out.luau> <alias>=<dir> [...]: bundles Rojo-style module folders (init.luau + siblings) for the
# offline mock runtime. Every module body becomes a function with its own fake `script` (Name, Parent,
# FindFirstChild / WaitForChild resolving to sibling module tokens) and a `require` that loads tokens.
# The bundle returns { load = function(alias, name?) -> module, R = mock runtime }.
import os, sys
out = sys.argv[1]
pkgs = [a.split('=', 1) for a in sys.argv[2:]]
G = ['game', 'workspace', 'Workspace', 'Instance', 'task', 'Enum', 'CFrame', 'Vector3', 'Color3', 'UDim2', 'UDim', 'Vector2',
     'NumberRange', 'NumberSequence', 'NumberSequenceKeypoint', 'ColorSequence', 'ColorSequenceKeypoint', 'TweenInfo', 'BrickColor',
     'Ray', 'RaycastParams', 'OverlapParams', 'Random', 'Font', 'Region3', 'Rect', 'PhysicalProperties', 'DateTime', 'typeof', 'tick', 'time', 'warn']
o = ['--!nocheck', 'local R = require("%s")' % os.environ.get('RBX', '../../../bprev/lib/rbx'), 'local E = R.env',
     'local ' + ', '.join(G) + ' = ' + ', '.join('E.' + g for g in G),
     'local __defs, __cache, __tok = {}, {}, {}',
     'local __realRequire = require',
     'local function __load(key) local v = __cache[key] if v == nil then local f = __defs[key] if not f then error("no module " .. key) end v = f() if v == nil then v = true end __cache[key] = v end return v end',
     'local function __mkTok(key, name, parent) local t = { Name = name, Parent = parent, __key = key, __kids = {} }',
     '  function t:FindFirstChild(n) return self.__kids[n] end',
     '  function t:WaitForChild(n, timeout) local c = self.__kids[n] if not c and timeout == nil then error("WaitForChild " .. n .. " missing under " .. self.Name) end return c end',
     '  function t:GetChildren() local o = {} for _, c in self.__kids do table.insert(o, c) end return o end',
     '  function t:IsA(c) return c == "ModuleScript" or c == "Instance" end',
     '  function t:GetFullName() return self.Name end',
     '  return t end',
     'local function require(x) if type(x) == "table" and x.__key then return __load(x.__key) end return __realRequire(x) end',
     'local __pkg = {}']
for alias, d in pkgs:
    files = sorted(f for f in os.listdir(d) if f.endswith('.luau'))
    init = None
    for f in files:
        if f.startswith('init.'):
            init = f
    o.append('do local P = __mkTok("%s/init", "%s", nil) __pkg["%s"] = P' % (alias, alias, alias))
    for f in files:
        if f.startswith('init.'):
            continue
        n = f[:-5]
        o.append('P.__kids["%s"] = __mkTok("%s/%s", "%s", P)' % (n, alias, n, n))
    o.append('end')
    for f in files:
        text = open(os.path.join(d, f), encoding='utf-8').read()
        text = '\n'.join(l for l in text.split('\n') if not l.startswith('--!'))
        if f.startswith('init.'):
            key = '%s/init' % alias
            sc = '__pkg["%s"]' % alias
        else:
            n = f[:-5]
            key = '%s/%s' % (alias, n)
            sc = '__pkg["%s"].__kids["%s"]' % (alias, n)
        o.append('__defs["%s"] = function()\nlocal script = %s\n%s\nend' % (key, sc, text))
o.append('return { R = R, pkg = __pkg, load = function(alias, name) return __load(alias .. "/" .. (name or "init")) end }')
open(out, 'w', encoding='utf-8').write('\n'.join(o))
print(out, sum(1 for l in o if l.startswith('__defs')), 'modules')
