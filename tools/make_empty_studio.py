#!/usr/bin/env python3
"""Make the empty 임시 스튜디오 template from a full Gwangalli studio HTML.

Keeps the shell, engine, Luau VM and physics packs untouched and replaces the game data:
  * place pack -> a fresh place with only the services, lighting, a baseplate and a spawn
  * static pack (pre-baked map parts the renderer and physics draw / collide with) -> just the baseplate + spawn
  * the embedded 광안리 플레이 콘텐츠 injector -> removed

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

    html = re.sub(r"<title>.*?</title>", "<title>%s</title>" % TITLE, html, count=1)
    html = html.replace('<h1 class="gw-title">광안리 임시 스튜디오<span class="ver">1.0 v2.0</span></h1>',
                        '<h1 class="gw-title">임시 스튜디오<span class="ver">빈 버전</span></h1>')
    html = html.replace("'— 빌드: 광안리 임시 스튜디오 '", "'— 빌드: 임시 스튜디오 '")
    dst.write_text(html, encoding="utf-8")
    print("%s: %d instances, place %d B, %.1f MB" % (dst, len(insts), raw_len, len(html) / 1e6))


if __name__ == "__main__":
    main()
