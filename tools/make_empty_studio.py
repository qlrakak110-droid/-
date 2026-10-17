#!/usr/bin/env python3
"""Make the empty 임시 스튜디오 template from a full Gwangalli studio HTML.

Keeps the shell, engine, Luau VM and physics packs untouched and replaces the game data:
  * place pack -> a fresh place with only the services, lighting, a baseplate and a spawn
  * static pack (pre-baked map parts the renderer and physics draw / collide with) -> just the baseplate + spawn
  * the embedded 광안리 플레이 콘텐츠 injector -> removed
  * adds a content slot near the top of <head>: <script type="text/x-luau" data-path="..."> blocks that are
    created in the place after boot, so other workers can add a game by pasting Luau into the HTML

    python3 tools/make_empty_studio.py <Gwangalli_Studio_*.html> [dist/TempStudio_Empty.html]
"""
import base64
import gzip
import json
import re
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gwpb  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
TITLE = "임시 스튜디오 · 빈 버전"
KEEP_SERVICES = {"Workspace", "Lighting", "MaterialService", "StarterPlayer", "ReplicatedStorage",
                 "ServerStorage", "ServerScriptService"}
KEEP_UNDER = {"Workspace": {"Terrain"}, "Terrain": {"Clouds"}, "StarterPlayer": {"StarterPlayerScripts", "StarterCharacterScripts"}}


def read_pack(text):
    raw = gzip.decompress(base64.b64decode(text))
    assert raw[:4] == b"GWPK"
    hl = struct.unpack("<I", raw[4:8])[0]
    header = json.loads(raw[8:8 + hl])
    return {f["n"]: raw[8 + hl + f["o"]:8 + hl + f["o"] + f["l"]] for f in header}


def write_pack(files):
    header, body = [], b""
    for n, data in files.items():
        header.append({"n": n, "o": len(body), "l": len(data)})
        body += data
    hj = json.dumps(header, separators=(",", ":")).encode()
    raw = b"GWPK" + struct.pack("<I", len(hj)) + hj + body
    gz = gzip.compress(raw, 9)
    return base64.b64encode(gz).decode(), len(raw), len(gz)


def _kept(inst, parent):
    if parent is None:
        return inst["cls"] == "DataModel"
    if parent["cls"] == "DataModel":
        return inst["cls"] in KEEP_SERVICES
    if parent["cls"] == "Lighting":
        return True
    return inst["cls"] == inst["name"] and inst["name"] in KEEP_UNDER.get(parent["cls"], set())


def _static_bin(insts):
    """GWST v1 (see decodeStatic in the shell): JSON header + instance ids + 21-float rows
    [shape, sx, sy, sz, x, y, z, r00..r22, rgb, material, transparency, group, canCollide]."""
    mats, rows, ids, spawn = [], [], [], None
    for inst in insts:
        if inst["cls"] not in ("Part", "SpawnLocation"):
            continue
        pr = inst["props"]
        size = struct.unpack("<3f", pr["Size"][1])
        cf = struct.unpack("<3f", pr["CFrame"][1][:12])
        r, g, b = pr["Color"][1]
        mat = pr["Material"][2]
        if mat not in mats:
            mats.append(mat)
        rows.append([0, *size, *cf, 1, 0, 0, 0, 1, 0, 0, 0, 1, (r << 16) | (g << 8) | b, mats.index(mat), 0, 0, 1])
        ids.append(inst["id"])
        if inst["cls"] == "SpawnLocation":
            spawn = [cf[0], cf[1] + size[1] / 2, cf[2], inst["id"]]
    head = {"format": "gwangalli-static", "version": "1", "spawn": spawn, "materials": mats, "groups": [],
            "attrs": [], "signs": [], "tags": {}, "terrain": []}
    hj = json.dumps(head, separators=(",", ":")).encode()
    out = b"GWST" + struct.pack("<IIII", 1, len(rows), 21, len(hj)) + hj
    out += b"\x00" * ((4 - len(out) % 4) % 4)
    out += struct.pack("<%di" % len(ids), *ids)
    for row in rows:
        out += struct.pack("<21f", *row)
    return out


def _new_parts():
    return [
        {"cls": "Part", "name": "Baseplate", "attrs": {}, "tags": [], "props": {
            "Anchored": gwpb.BOOL(True), "CFrame": gwpb.CF(0, -4, 0), "Color": gwpb.RGB(91, 154, 76),
            "Locked": gwpb.BOOL(True), "Material": gwpb.ENUM("Material", "Grass"), "Size": gwpb.V3(2048, 8, 2048),
            "TopSurface": gwpb.ENUM("SurfaceType", "Smooth")}},
        {"cls": "SpawnLocation", "name": "SpawnLocation", "attrs": {}, "tags": [], "props": {
            "Anchored": gwpb.BOOL(True), "CFrame": gwpb.CF(0, 1, 38), "Color": gwpb.RGB(163, 162, 165),
            "Duration": (5, b"\x00"), "Material": gwpb.ENUM("Material", "SmoothPlastic"), "Size": gwpb.V3(12, 1, 12),
            "TopSurface": gwpb.ENUM("SurfaceType", "Smooth")}},
    ]


def empty_place(src):
    place = gwpb.read(src)
    kids = {}
    for inst in place["insts"]:
        kids.setdefault(inst["parent"], []).append(inst)
    out, remap = [], {}

    def emit(inst, parent_new):
        name = "Sky" if inst["cls"] == "Sky" else inst["name"]
        node = {"id": len(out) + 1, "cls": inst["cls"], "name": name, "parent": parent_new,
                "props": dict(inst["props"]), "attrs": {k: v for k, v in inst["attrs"].items() if not k.startswith("Gw")},
                "tags": []}
        out.append(node)
        if "id" in inst:
            remap[inst["id"]] = node["id"]
        for k in kids.get(inst.get("id"), []):
            if _kept(k, inst):
                emit(k, node["id"])
        if inst["cls"] == "Workspace":
            for part in _new_parts():
                emit(part, node["id"])

    emit(place["insts"][0], 0)
    for node in out:
        for k, v in node["props"].items():
            if v[0] == 25:
                node["props"][k] = (25, remap[v[1]]) if v[1] in remap else (0, b"")
    meta = json.loads(place["meta"])
    meta = {"classdb": meta.get("classdb"), "generator": "tools/make_empty_studio.py", "instances": len(out),
            "source": "empty"}
    return gwpb.write({"meta": json.dumps(meta, ensure_ascii=False), "rot": place["rot"], "insts": out}), out


SLOT = """<!-- ================================================================================================
  CONTENT SLOT (콘텐츠 넣는 곳) — 이 빈 임시 스튜디오에 게임을 넣으려면 아래에 블록을 추가하세요.

  <script type="text/x-luau" data-class="Script" data-path="ServerScriptService/MyServer">
  print("서버 시작")
  </script>

  data-class : Script | LocalScript | ModuleScript
  data-path  : 서비스/폴더/이름  (중간 폴더는 자동 생성)
               ServerScriptService · ServerStorage · ReplicatedStorage · Workspace · StarterPlayerScripts
               (StarterPlayerScripts 아래 LocalScript 는 현재 플레이어에게도 바로 실행됩니다)
  위에서부터 순서대로 만들어집니다: ModuleScript 를 require 하는 스크립트보다 먼저 두세요.
  Luau 코드 안에 '</' + 'script>' 문자열은 쓸 수 없습니다.
================================================================================================= -->
<!-- CONTENT:BEGIN -->
<!-- CONTENT:END -->
"""

RUNNER = r"""<script>
/* CONTENT SLOT runner: creates every <script type="text/x-luau"> block of the page inside the running place. */
(function () {
  var LUA = [
    'local I = GW.require("instance") local Sched = GW.require("sched") local Env = GW.require("env")',
    'local S = GW.require("services").S',
    'local args = ...',
    'local cls, path, src = args[1], args[2], args[3]',
    'local function run(f, ...) local r; Sched.runIn(Env.serverCtx, function(...) r = f(...) end, ...) return r end',
    'local parts = string.split(path, "/")',
    'local svcName = table.remove(parts, 1)',
    'local name = table.remove(parts)',
    'local roots = {}',
    'if svcName == "StarterPlayerScripts" then',
    '  table.insert(roots, run(function() return S.game:GetService("StarterPlayer"):FindFirstChildOfClass("StarterPlayerScripts") end))',
    '  if cls == "LocalScript" or cls == "ModuleScript" then',
    '    local ps = run(function() return S.player and S.player:FindFirstChildOfClass("PlayerScripts") end)',
    '    if not ps then return "no parent" end',
    '    roots = { ps }',
    '  end',
    'else',
    '  local ok, svc = pcall(run, function() return S.game:GetService(svcName) end)',
    '  if not ok or not svc then return "ERR unknown service " .. tostring(svcName) end',
    '  roots = { svc }',
    'end',
    'for _, root in roots do',
    '  local parent = root',
    '  for _, folder in parts do',
    '    local f = run(function() return parent:FindFirstChild(folder) end)',
    '    if not f then f = I.create("Folder", { name = folder }) run(I.setParent, f, parent) end',
    '    parent = f',
    '  end',
    '  if run(function() return parent:FindFirstChild(name) end) then return "already" end',
    '  local inst = I.create(cls, { name = name, props = { Source = src }, newDefaults = true })',
    '  run(I.setParent, inst, parent)',
    'end',
    'Sched.flush()',
    'return "ok"'
  ].join('\n');
  var blocks = [].slice.call(document.querySelectorAll('script[type="text/x-luau"]')).map(function (el) {
    return { cls: el.getAttribute('data-class') || 'Script', path: el.getAttribute('data-path') || '', src: el.textContent };
  });
  if (!blocks.length) return;
  function wait(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }
  function q(s) { return '"' + s.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n').replace(/\r/g, '\\r') + '"'; }
  async function run() {
    for (var i = 0; i < 900; i++) { if (window.GW && GW.engine && GW.engine.running && GW.engine.eval) break; await wait(500); }
    if (!(window.GW && GW.engine && GW.engine.running)) { console.warn('[Content] engine not running'); return; }
    await wait(1500);
    var failed = 0;
    for (var k = 0; k < blocks.length; k++) {
      var b = blocks[k], r = '';
      if (b.path.split('/').length < 2) { failed++; console.warn('[Content] bad data-path: ' + b.path); continue; }
      var code = 'return (function(...)\n' + LUA + '\nend)({' + q(b.cls) + ',' + q(b.path) + ',' + q(b.src) + '})';
      for (var t = 0; t < 40; t++) {
        try { r = String(await GW.engine.eval(code)); } catch (e) { r = 'ERR ' + e; }
        if (!/^no parent/.test(r)) break;
        await wait(1000);
      }
      if (!/^(ok|already)/.test(r)) { failed++; console.warn('[Content] ' + b.path + ': ' + r); }
    }
    console.log('[Content] created ' + (blocks.length - failed) + '/' + blocks.length + ' scripts');
  }
  run();
})();
</script>
"""


def main():
    src = Path(sys.argv[1])
    dst = Path(sys.argv[2]) if len(sys.argv) > 2 else ROOT / "dist" / "TempStudio_Empty.html"
    html = src.read_text(encoding="utf-8")

    m = re.search(r'(<script type="application/x-gw-pack" id="gw-pack-place">)(.*?)(</script>)', html, re.S)
    files = read_pack(m.group(2))
    place_bin, insts = empty_place(files["place.bin"])
    b64, raw_len, gz_len = write_pack({"place.bin": place_bin})
    html = html[:m.start(2)] + b64 + html[m.end(2):]

    m = re.search(r'(<script type="application/x-gw-pack" id="gw-pack-static">)(.*?)(</script>)', html, re.S)
    st_b64, st_raw, st_gz = write_pack({"static.bin": _static_bin(insts)})
    html = html[:m.start(2)] + st_b64 + html[m.end(2):]
    html = re.sub(r'<script>\n/\* 광안리 플레이 콘텐츠.*?</script>\n', "", html, flags=re.S)
    html = re.sub(r"<!-- TREND_FISHING:BEGIN -->.*?<!-- TREND_FISHING:END -->\n?", "", html, flags=re.S)

    m = re.search(r'(<script id="gw-manifest" type="application/json">)(.*?)(</script>)', html, re.S)
    man = json.loads(m.group(2))
    man["label"] = "빈 버전"
    man["place"] = {"instances": len(insts), "parts": sum(1 for i in insts if i["cls"] in ("Part", "SpawnLocation")),
                    "scripts": 0}
    man["packs"]["place"] = {"raw": raw_len, "gz": gz_len, "files": ["place.bin"]}
    man["packs"]["static"] = {"raw": st_raw, "gz": st_gz, "files": ["static.bin"]}
    man.pop("integration", None)
    html = html[:m.start(2)] + json.dumps(man, ensure_ascii=False, separators=(",", ":")) + html[m.end(2):]

    anchor = '<meta name="color-scheme" content="dark">\n'  # after <meta charset> (must stay in the first 1 KB)
    html = html.replace(anchor, anchor + SLOT, 1)
    idx = html.rindex("</body>")
    html = html[:idx] + RUNNER + html[idx:]
    html = re.sub(r"<title>.*?</title>", "<title>%s</title>" % TITLE, html, count=1)
    html = html.replace('<h1 class="gw-title">광안리 임시 스튜디오<span class="ver">1.0 v2.0</span></h1>',
                        '<h1 class="gw-title">임시 스튜디오<span class="ver">빈 버전</span></h1>')
    html = html.replace("'— 빌드: 광안리 임시 스튜디오 '", "'— 빌드: 임시 스튜디오 '")
    dst.write_text(html, encoding="utf-8")
    print("%s: %d instances, place %d B, %.1f MB" % (dst, len(insts), raw_len, len(html) / 1e6))


if __name__ == "__main__":
    main()
