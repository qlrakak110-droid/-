#!/usr/bin/env python3
"""차량 유리 AAA 패치: 스튜디오 HTML(어느 버전이든)에 studio/car_glass.js 를 넣고 차량 모델 3개 파일에 연결합니다.

    python3 tools/patch_car_glass.py <input studio.html> <output.html>

What it does (all inside the embedded "core" pack: base64(gzip("GWPK" u32 headerLen, header JSON, bytes))):
  * adds js/car_glass.js (from studio/car_glass.js) and loads it right before js/carskin_model.js (manifest "modules")
  * js/taxi_model.js     glass / glass_dark roles -> GWCarGlass materials, per-window data on the glass geometry,
                         an inside (BackSide) glass mesh next to every high-detail glass mesh (cabin view)
  * js/carskin_model.js  legacy sedan glass -> GWCarGlass (double sided); mergeLow puts glass in its own "glass" bucket
  * js/render3d.js       far LOD: a 4th instanced mesh with the gloss-black glass material
Every hook is anchored on the original code and marked with "/*gw-carglass*/", so running it again (or on an already
patched file) changes nothing. If a newer studio changed one of the anchored lines, the script stops and names the hook
instead of writing a half-patched file.
"""
import base64, gzip, json, os, re, struct, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MARK = "/*gw-carglass*/"
MODULE = "js/car_glass.js"
CG = "root.GWCarGlass"

# (file, hook name, anchor, replacement) -- the replacement must contain MARK
HOOKS = [
    ("js/taxi_model.js", "glass material",
     "function material(role){if(mats.has(role))return mats.get(role);",
     "function material(role){" + MARK + "if((role==='glass'||role==='glass_dark')&&" + CG + ")return " + CG + ".material(role);if(mats.has(role))return mats.get(role);"),
    ("js/taxi_model.js", "glass window data",
     "if(!c.geo.has(pc.n))c.geo.set(pc.n,piece(c.bytes,c.dv,pc));",
     "if(!c.geo.has(pc.n)){" + MARK + "const g=piece(c.bytes,c.dv,pc);if(" + CG + "&&(pc.r==='glass'||pc.r==='glass_dark'))" + CG + ".prepare(g,pc.r);c.geo.set(pc.n,g);}"),
    ("js/taxi_model.js", "inside glass pass",
     "pivot.add(mesh);if(/interior",
     MARK + "if(" + CG + "&&opts.detail!=='low'&&" + CG + ".isGlass(mesh.material)){const gi=new THREE.Mesh(mesh.geometry," + CG + ".inner(pc.r));gi.position.copy(mesh.position);pivot.add(gi);}pivot.add(mesh);if(/interior"),
    ("js/carskin_model.js", "legacy glass material",
     "glass: adopt(new THREE.MeshPhysicalMaterial({ color: 0x1b2630, metalness: 0, roughness: 0.05, transparent: true, opacity: 0.4, side: THREE.DoubleSide, depthWrite: false })),",
     "glass: " + MARK + " root.GWCarGlass ? root.GWCarGlass.both('glass') : adopt(new THREE.MeshPhysicalMaterial({ color: 0x1b2630, metalness: 0, roughness: 0.05, transparent: true, opacity: 0.4, side: THREE.DoubleSide, depthWrite: false })),"),
    ("js/carskin_model.js", "legacy glass window data",
     "const ghMesh = gh.build({ paint, glass: hi ? MAT.glass : MAT.trimGloss, trim: MAT.trimGloss }, ['paint', 'trim', 'glass']);",
     "const ghMesh = gh.build({ paint, glass: hi ? MAT.glass : MAT.trimGloss, trim: MAT.trimGloss }, ['paint', 'trim', 'glass']); " + MARK + " if (hi && root.GWCarGlass) root.GWCarGlass.prepare(ghMesh.geometry, 'glass', { constant: true });"),
    ("js/carskin_model.js", "legacy door glass data",
     "const g = gm.build({ glass: MAT.glass }, ['glass']); g.renderOrder = 2; pivot.add(g);",
     "const g = gm.build({ glass: MAT.glass }, ['glass']); g.renderOrder = 2; pivot.add(g); " + MARK + " if (root.GWCarGlass) root.GWCarGlass.prepare(g.geometry, 'glass', { constant: true });"),
    ("js/carskin_model.js", "LOD glass bucket",
     "const out = { paint: [], dark: [], lamp: [] };",
     "const out = { paint: [], dark: [], lamp: [], glass: [] }; " + MARK + " const cgl = root.GWCarGlass;"),
    ("js/carskin_model.js", "LOD glass key",
     "const key = isPaint ? 'paint' : em ? 'lamp' : 'dark';",
     "if (cgl && cgl.isInner(mat)) return; " + MARK + "\n      const key = isPaint ? 'paint' : em ? 'lamp' : cgl && cgl.isGlass(mat) ? 'glass' : 'dark';"),
    ("js/carskin_model.js", "LOD glass geometry",
     "for (const key of ['paint', 'dark', 'lamp']) {",
     "for (const key of ['paint', 'dark', 'lamp', 'glass']) { " + MARK),
    ("js/render3d.js", "LOD glass mesh",
     "lamp: mk(geos.lamp, new T.MeshBasicMaterial({ vertexColors: true }), cap),",
     "lamp: mk(geos.lamp, new T.MeshBasicMaterial({ vertexColors: true }), cap),\n      " + MARK + " glass: geos.glass && geos.glass.attributes.position.count && root.GWCarGlass ? mk(geos.glass, root.GWCarGlass.lowMaterial(), cap) : null,"),
    ("js/render3d.js", "LOD glass matrices",
     "low.paint.setMatrixAt(n,SK.tmpM);low.dark.setMatrixAt(n,SK.tmpM);low.lamp.setMatrixAt(n,SK.tmpM);",
     "low.paint.setMatrixAt(n,SK.tmpM);low.dark.setMatrixAt(n,SK.tmpM);low.lamp.setMatrixAt(n,SK.tmpM);if(low.glass)low.glass.setMatrixAt(n,SK.tmpM);" + MARK),
    ("js/render3d.js", "LOD glass counts",
     "for (const k of ['paint','dark','lamp']) {low[k].count=low.used||0;low[k].instanceMatrix.needsUpdate=true;}",
     "for (const k of ['paint','dark','lamp','glass']) {if(!low[k])continue;" + MARK + "low[k].count=low.used||0;low[k].instanceMatrix.needsUpdate=true;}"),
]


def read_pack(html, name):
    m = re.search(r'(<script type="application/x-gw-pack" id="gw-pack-%s">)([^<]*)(</script>)' % name, html)
    if not m:
        raise SystemExit("pack %r not found (is this a gw-player studio HTML?)" % name)
    raw = gzip.decompress(base64.b64decode(m.group(2)))
    if raw[:4] != b"GWPK":
        raise SystemExit("pack %r: bad magic" % name)
    hl = struct.unpack("<I", raw[4:8])[0]
    header = json.loads(raw[8:8 + hl].decode("utf-8"))
    base = 8 + hl
    files = {f["n"]: raw[base + f["o"]:base + f["o"] + f["l"]] for f in header}
    return m, [f["n"] for f in header], files


def write_pack(order, files):
    header, blobs, off = [], [], 0
    for n in order:
        b = files[n]
        header.append({"n": n, "o": off, "l": len(b)})
        blobs.append(b)
        off += len(b)
    hj = json.dumps(header, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    raw = b"GWPK" + struct.pack("<I", len(hj)) + hj + b"".join(blobs)
    gz = gzip.compress(raw, compresslevel=9, mtime=0)
    return raw, gz, base64.b64encode(gz).decode("ascii")


def patch(html, extra_hooks=(), extra_modules=()):
    """Applies the glass module + HOOKS (+ extra_hooks / extra_modules [(path, bytes, before)]) to a studio HTML string.
    Returns (html, report). Raises SystemExit naming every hook that does not match (nothing is changed then)."""
    mm = re.search(r'(<script id="gw-manifest" type="application/json">)(.*?)(</script>)', html, re.S)
    if not mm:
        raise SystemExit("gw-manifest not found")
    manifest = json.loads(mm.group(2))
    m, order, files = read_pack(html, "core")

    module = open(os.path.join(ROOT, "studio", "car_glass.js"), encoding="utf-8").read().encode("utf-8")
    report = []
    mods = manifest.get("modules") or []
    for path, data, before in [(MODULE, module, "js/carskin_model.js")] + list(extra_modules):
        if path not in files:
            order.append(path)
            report.append("+ " + path)
        elif files[path] != data:
            report.append("~ " + path + " (updated)")
        files[path] = data
        if path.endswith(".js") and path not in mods:
            at = mods.index(before) if before in mods else (mods.index("js/taxi_model.js") if "js/taxi_model.js" in mods else len(mods))
            mods.insert(at, path)
    manifest["modules"] = mods

    # hooks a different patcher revision already applied (their text differs): refuse instead of patching twice
    prev = set((manifest.get("carGlass") or {}).get("hooks") or [])
    missing = []
    for fn, name, anchor, repl in list(HOOKS) + list(extra_hooks):
        if fn not in files:
            missing.append("%s: %s (file missing)" % (fn, name)); continue
        text = files[fn].decode("utf-8")
        if repl in text:
            report.append("= %s: %s (already patched)" % (fn, name)); continue
        if name in prev:
            missing.append("%s: %s (applied by a different patcher version - start from the unpatched studio build)" % (fn, name)); continue
        n = text.count(anchor)
        if n != 1:
            missing.append("%s: %s (anchor found %d times)" % (fn, name, n)); continue
        files[fn] = text.replace(anchor, repl).encode("utf-8")
        report.append("+ %s: %s" % (fn, name))
    if missing:
        raise SystemExit("these hooks do not match this studio build (nothing written):\n  " + "\n  ".join(missing))

    raw, gz, b64 = write_pack(order, files)
    core = manifest.setdefault("packs", {}).setdefault("core", {})
    core.update({"raw": len(raw), "gz": len(gz), "files": order})
    manifest["carGlass"] = {"version": 2, "module": MODULE, "hooks": sorted(prev | {h[1] for h in list(HOOKS) + list(extra_hooks)})}

    mj = json.dumps(manifest, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")
    html = html[:m.start(2)] + b64 + html[m.end(2):]
    mm = re.search(r'(<script id="gw-manifest" type="application/json">)(.*?)(</script>)', html, re.S)
    html = html[:mm.start(2)] + mj + html[mm.end(2):]
    return html, report


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    src, dst = sys.argv[1], sys.argv[2]
    html, report = patch(open(src, encoding="utf-8").read())
    open(dst, "w", encoding="utf-8").write(html)
    print("\n".join(report))
    print(dst, os.path.getsize(dst), "bytes")


if __name__ == "__main__":
    main()
