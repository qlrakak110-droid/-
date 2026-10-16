#!/usr/bin/env python3
"""차량 실내 + 건물 실내를 복사-붙여넣기용 LocalScript 한 파일로 묶습니다.

    python3 tools/bundle_all.py build/GwangalliInterior.client.luau

src/StarterPlayer/StarterPlayerScripts/ 아래 GwangalliCarInterior, GwangalliBuildingInterior 폴더(Rojo 형식:
init.client.luau + ModuleScript 형제들)를 각자 이름공간으로 넣고, 두 시스템의 init 을 각각 task.spawn 으로 돌립니다.
require(script:WaitForChild("X")) / require(script.Parent:WaitForChild("X")) 는 같은 시스템 안의 모듈을 부르도록 바뀝니다.
결과는 StarterPlayerScripts 에 LocalScript 하나로 넣으면 됩니다 (스크립트 속성 MaxCabins · MaxVenues · Debug 그대로 사용).
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = os.path.join(ROOT, "src/StarterPlayer/StarterPlayerScripts")
SYSTEMS = [("Car", "GwangalliCarInterior"), ("Bld", "GwangalliBuildingInterior")]
REQ = re.compile(r'require\(\s*script(?:\.Parent)?\s*:\s*WaitForChild\(\s*"([A-Za-z0-9_]+)"\s*\)\s*\)')


def load(folder):
    init, mods = None, {}
    for e in sorted(os.listdir(folder)):
        if not e.endswith(".luau"):
            continue
        text = open(os.path.join(folder, e), encoding="utf-8").read()
        if e == "init.client.luau":
            init = text
        elif not e.startswith("init."):
            mods[e[: -len(".luau")]] = text
    if init is None:
        raise SystemExit("no init.client.luau in " + folder)
    return init, mods


def banner_of(init):
    head = init.split("\n")
    banner = []
    while head and head[0].startswith("--"):
        if not head[0].startswith("--!"):
            banner.append(head[0])
        head.pop(0)
    return banner, "\n".join(head)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build/GwangalliInterior.client.luau")
    parts = ["--!nocheck",
             "-- GwangalliInterior (LocalScript, StarterPlayerScripts): 광안리 AAA 실내 — 차량 실내 + 건물(매장) 실내 한 파일 버전.",
             "-- (tools/bundle_all.py 가 GwangalliCarInterior · GwangalliBuildingInterior 폴더를 묶은 것. StarterPlayerScripts 에 LocalScript 로 넣으세요)",
             "-- 스크립트 속성: MaxCabins (차량 실내 수) · MaxVenues (건물 실내 수) · Debug (true = 로그) · Enabled (false = 건물 실내 끔)",
             ""]
    runs = []
    for tag, name in SYSTEMS:
        folder = os.path.join(BASE, name)
        if not os.path.isdir(folder):
            continue
        init, mods = load(folder)
        banner, body = banner_of(init)
        parts += ["-- " + "=" * 100, "-- " + name] + banner + [""]
        parts += [
            "local __defs%s, __cache%s = {}, {}" % (tag, tag),
            "local function __require%s(name)" % tag,
            "\tlocal v = __cache%s[name]" % tag,
            "\tif v == nil then",
            "\t\tv = __defs%s[name]()" % tag,
            "\t\t__cache%s[name] = v" % tag,
            "\tend",
            "\treturn v",
            "end",
            "",
        ]

        def fix(text, tag=tag, mods=mods):
            text = REQ.sub(lambda m: '__require%s("%s")' % (tag, m.group(1)) if m.group(1) in mods else m.group(0), text)
            return "\n".join(l for l in text.split("\n") if not l.startswith("--!"))

        for mname, text in mods.items():
            parts.append('__defs%s["%s"] = function()' % (tag, mname))
            parts.append(fix(text))
            parts.append("end")
            parts.append("")
        parts.append("local function __run%s()" % tag)
        parts.append(fix(body))
        parts.append("end")
        parts.append("")
        runs.append(tag)
    parts.append("-- " + "=" * 100)
    for tag in runs:
        parts.append("task.spawn(function()")
        parts.append("\tlocal ok, err = pcall(__run%s)" % tag)
        parts.append("\tif not ok then")
        parts.append('\t\twarn("[GwangalliInterior] %s: " .. tostring(err))' % tag)
        parts.append("\tend")
        parts.append("end)")
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    open(out, "w", encoding="utf-8").write("\n".join(parts) + "\n")
    print(out, os.path.getsize(out), "bytes,", ", ".join(runs))


if __name__ == "__main__":
    main()
