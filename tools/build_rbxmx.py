#!/usr/bin/env python3
"""Builds Roblox model files (.rbxmx) from src/ (Rojo layout) for drag-and-drop into Roblox Studio.

    python3 tools/build_rbxmx.py        -> build/*.rbxmx

  build/MiniGames_ReplicatedStorage.rbxmx  -> drop into ReplicatedStorage
  build/MiniGames_Server.rbxmx             -> drop into ServerScriptService.GwangalliGameplay (the Folder)
  build/MiniGames_StarterPlayerScripts.rbxmx -> drop into StarterPlayer.StarterPlayerScripts
Layout rules (same as Rojo): a folder with init.luau is a ModuleScript (init.server.luau -> Script,
init.client.luau -> LocalScript) whose children are the other files; a folder without init is a
Folder; x.luau -> ModuleScript, x.server.luau -> Script, x.client.luau -> LocalScript.
"""
import os
import sys
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ref = [0]


def nid():
    ref[0] += 1
    return "RBX%08X" % ref[0]


def item(cls, name, source, children):
    out = ['<Item class="%s" referent="%s"><Properties><string name="Name">%s</string>' % (cls, nid(), escape(name))]
    if source is not None:
        # CDATA cannot contain "]]>": split it
        src = source.replace("]]>", "]]]]><![CDATA[>")
        out.append('<ProtectedString name="Source"><![CDATA[%s]]></ProtectedString>' % src)
    out.append("</Properties>")
    out.extend(children)
    out.append("</Item>")
    return "".join(out)


def kind(fname):
    base = fname[: -len(".luau")] if fname.endswith(".luau") else fname[: -len(".lua")]
    if base.endswith(".server"):
        return "Script", base[:-7]
    if base.endswith(".client"):
        return "LocalScript", base[:-7]
    return "ModuleScript", base


def walk(path):
    name = os.path.basename(path)
    cls, source, kids = "Folder", None, []
    for e in sorted(os.listdir(path)):
        p = os.path.join(path, e)
        if os.path.isdir(p):
            kids.append(walk(p))
            continue
        if not (e.endswith(".luau") or e.endswith(".lua")):
            continue
        c, n = kind(e)
        text = open(p, encoding="utf-8").read()
        if n == "init":
            cls, source = c, text
        else:
            kids.append(item(c, n, text, []))
    return item(cls, name, source, kids)


def write(out, tree):
    os.makedirs(os.path.join(ROOT, "build"), exist_ok=True)
    with open(os.path.join(ROOT, "build", out), "w", encoding="utf-8") as f:
        f.write('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" version="4">')
        f.write(tree)
        f.write("</roblox>")
    print("build/" + out)


def main():
    ref[0] = 0
    write("MiniGames_ReplicatedStorage.rbxmx", walk(os.path.join(ROOT, "src/ReplicatedStorage/GwangalliMiniGamesShared")))
    write("MiniGames_Server.rbxmx", walk(os.path.join(ROOT, "src/ServerScriptService/GwangalliGameplay/MiniGames")))
    write("MiniGames_StarterPlayerScripts.rbxmx", walk(os.path.join(ROOT, "src/StarterPlayer/StarterPlayerScripts/GwangalliMiniGames")))


if __name__ == "__main__":
    sys.exit(main())
