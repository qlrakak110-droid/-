#!/usr/bin/env python3
# Builds logic_test.luau: the pass add-on's pure / server modules inlined over the mock Roblox runtime.
import os, re
SRC = '/home/user/-/src'
HERE = os.path.dirname(os.path.abspath(__file__))
SH = os.path.join(SRC, 'ReplicatedStorage/GwangalliPassesShared')
SV = os.path.join(SRC, 'ServerScriptService/GwangalliPasses')
mods = {
    'Config': os.path.join(SH, 'Config.luau'), 'Lines': os.path.join(SH, 'Lines.luau'), 'Plates': os.path.join(SH, 'Plates.luau'),
    'Neon': os.path.join(SH, 'Neon.luau'), 'KoFx': os.path.join(SH, 'KoFx.luau'), 'Cars': os.path.join(SH, 'Cars.luau'),
    'P': os.path.join(SH, 'init.luau'),
    'Util': os.path.join(SV, 'Util.luau'), 'Net': os.path.join(SV, 'Net.luau'), 'Waits': os.path.join(SV, 'Waits.luau'),
    'Plate': os.path.join(SV, 'Plate.luau'),
}
out = ['--!nocheck', 'local R = require("../t/lib/rbx")', 'local E = R.env']
out.append('local game, workspace, Instance, Enum, CFrame, Vector3, Color3, UDim2, UDim, Vector2, task = E.game, E.workspace, E.Instance, E.Enum, E.CFrame, E.Vector3, E.Color3, E.UDim2, E.UDim, E.Vector2, E.task')
out.append('local NumberSequence, NumberSequenceKeypoint, ColorSequence, ColorSequenceKeypoint, Random, typeof, warn = E.NumberSequence, E.NumberSequenceKeypoint, E.ColorSequence, E.ColorSequenceKeypoint, E.Random, E.typeof, E.warn')
out.append('local _ = typeof')
out.append('local RaycastParams, OverlapParams = E.RaycastParams, E.OverlapParams')
out.append('local __typeof = typeof')
out.append('typeof = function(v) if type(v) == "table" and rawget(v, "_p") ~= nil then return "Instance" end return E.typeof(v) end')
out.append('local __defs, __cache = {}, {}')
out.append('local function __req(n) if __cache[n] == nil then __cache[n] = __defs[n]() end return __cache[n] end')
for name, path in mods.items():
    src = open(path, encoding='utf-8').read()
    src = re.sub(r'require\(script\.Parent:WaitForChild\("(\w+)"\)\)', lambda m: '__req("%s")' % m.group(1), src)
    src = re.sub(r'require\(script:WaitForChild\("(\w+)"\)\)', lambda m: '__req("%s")' % m.group(1), src)
    src = src.replace('require(script:WaitForChild(name))', '__req(name)')
    out.append('__defs["%s"] = function()\n%s\nend' % (name, src))
out.append(open(os.path.join(HERE, 'body.luau'), encoding='utf-8').read())
open(os.path.join(HERE, 'logic_test.luau'), 'w', encoding='utf-8').write('\n'.join(out))
print('ok')
