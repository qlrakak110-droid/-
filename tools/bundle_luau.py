#!/usr/bin/env python3
"""Rojo 폴더(LocalScript init.client.luau + ModuleScript 형제들)를 복사-붙여넣기용 LocalScript 한 파일로 묶습니다.

    python3 tools/bundle_luau.py src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior build/GwangalliCarInterior.client.luau

모듈은 지연 로딩 함수로 들어가고 require(script:WaitForChild("X")) / require(script.Parent:WaitForChild("X")) 는
같은 파일 안의 모듈을 부르도록 바뀝니다. 결과는 StarterPlayerScripts 에 LocalScript 하나로 넣으면 됩니다.
"""
import os
import re
import sys

REQ = re.compile(r'require\(\s*script(?:\.Parent)?\s*:\s*WaitForChild\(\s*"([A-Za-z0-9_]+)"\s*\)\s*\)')


def main():
    src, out = sys.argv[1], sys.argv[2]
    init = None
    mods = {}
    for e in sorted(os.listdir(src)):
        p = os.path.join(src, e)
        if not e.endswith(".luau"):
            continue
        text = open(p, encoding="utf-8").read()
        if e == "init.client.luau":
            init = text
        elif not e.startswith("init."):
            mods[e[: -len(".luau")]] = text
    if init is None:
        raise SystemExit("no init.client.luau in " + src)

    def fix(text):
        text = REQ.sub(lambda m: '__require("%s")' % m.group(1) if m.group(1) in mods else m.group(0), text)
        return "\n".join(l for l in text.split("\n") if not l.startswith("--!"))

    head = init.split("\n")
    banner = []
    while head and head[0].startswith("--"):
        if not head[0].startswith("--!"):
            banner.append(head[0])
        head.pop(0)
    parts = ["--!nocheck"] + banner + [
        "-- (한 파일 버전: tools/bundle_luau.py 가 " + os.path.basename(src) + " 폴더를 묶은 것. StarterPlayerScripts 에 LocalScript 로 넣으세요)",
        "",
        "local __defs, __cache = {}, {}",
        "local function __require(name)",
        "\tlocal v = __cache[name]",
        "\tif v == nil then",
        "\t\tv = __defs[name]()",
        "\t\t__cache[name] = v",
        "\tend",
        "\treturn v",
        "end",
        "",
    ]
    for name, text in mods.items():
        parts.append('__defs["%s"] = function()' % name)
        parts.append(fix(text))
        parts.append("end")
        parts.append("")
    parts.append(fix("\n".join(head)))
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    open(out, "w", encoding="utf-8").write("\n".join(parts))
    print(out, os.path.getsize(out), "bytes,", len(mods), "modules")


if __name__ == "__main__":
    main()
