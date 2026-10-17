#!/usr/bin/env python3
"""Build dist/TempStudio_TrendFishing.html: the empty 임시 스튜디오 template + the TREND FISHING scripts.

The studio boots a Roblox place in the browser; this adds a <script> block that, once the engine
is running, creates ServerScriptService.TrendFishingServer (Script) and
PlayerScripts.TrendFishingClient (LocalScript) from the Rojo sources in src/. Re-run after editing src/.

    python3 tools/build_studio.py [template.html] [output.html]
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEMPLATE = ROOT / "dist" / "TempStudio_Empty.html"
OUTPUT = ROOT / "dist" / "TempStudio_TrendFishing.html"
BEGIN = "<!-- TREND_FISHING:BEGIN -->"
END = "<!-- TREND_FISHING:END -->"

PRELUDE = """
local I = GW.require("instance") local Sched = GW.require("sched") local Env = GW.require("env")
local S = GW.require("services").S
local function svc(n) local r; Sched.runIn(Env.serverCtx, function() r = S.game:GetService(n) end) return r end
local function kid(parent, name)
  local r
  Sched.runIn(Env.serverCtx, function() r = parent:FindFirstChild(name) end)
  return r
end
local function localScripts()
  local ps
  Sched.runIn(Env.serverCtx, function() ps = S.player and S.player:FindFirstChildOfClass("PlayerScripts") end)
  return ps
end
"""

PLACE = """
local parent = {parent}
if not parent then return "no parent" end
if kid(parent, "{name}") then return "already" end
local inst = I.create("{cls}", {{ name = "{name}", props = {{ Source = [======[{src}]======] }}, newDefaults = true }})
Sched.runIn(Env.serverCtx, I.setParent, inst, parent) Sched.flush() return "ok"
"""

SCRIPTS = [
    ("server:TrendFishingServer", "Script", "TrendFishingServer", 'svc("ServerScriptService")',
     "src/server/TrendFishingServer.server.lua"),
    ("client:TrendFishingClient", "LocalScript", "TrendFishingClient", "localScripts()",
     "src/client/TrendFishingClient.client.lua"),
]

RUNNER = """<script>
/* TREND FISHING: injected into the running place after boot. Built by tools/build_studio.py from src/. */
(function () {
  var chunks = %s;
  function wait(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }
  async function evalc(code) { try { return String(await GW.engine.eval(code)); } catch (e) { return 'ERR ' + e; } }
  async function run() {
    for (var i = 0; i < 900; i++) {
      if (window.GW && GW.engine && GW.engine.running && GW.engine.eval) break;
      await wait(500);
    }
    if (!(window.GW && GW.engine && GW.engine.running)) { console.warn('[TrendFishing] engine not running; not injected'); return; }
    await wait(2500);
    var failed = 0;
    for (var k = 0; k < chunks.length; k++) {
      var c = chunks[k], r = '';
      for (var t = 0; t < 40; t++) {
        r = await evalc(c.code);
        if (!/^no parent/.test(r)) break;
        await wait(1000);
      }
      if (!/^(ok|already)/.test(r)) { failed++; console.warn('[TrendFishing] ' + c.label + ': ' + r); }
    }
    console.log('[TrendFishing] injected ' + (chunks.length - failed) + '/' + chunks.length + ' scripts');
  }
  run();
})();
</script>"""


def chunk(label, cls, name, parent, path):
    src = (ROOT / path).read_text(encoding="utf-8")
    assert "]======]" not in src, path
    return {"label": label, "code": PRELUDE + PLACE.format(parent=parent, name=name, cls=cls, src=src)}


def main():
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else TEMPLATE
    dst = Path(sys.argv[2]) if len(sys.argv) > 2 else OUTPUT
    html = src.read_text(encoding="utf-8")
    html = re.sub(re.escape(BEGIN) + ".*?" + re.escape(END) + "\n?", "", html, flags=re.S)
    chunks = [chunk(*s) for s in SCRIPTS]
    payload = json.dumps(chunks, ensure_ascii=False).replace("</", "<\\/")
    block = BEGIN + "\n" + RUNNER % payload + "\n" + END + "\n"
    idx = html.rindex("</body>")
    html = html[:idx] + block + html[idx:]
    html = re.sub(r"<title>(.*?)</title>", r"<title>\1 + TREND FISHING</title>", html, count=1)
    dst.write_text(html, encoding="utf-8")
    print("injected %d scripts -> %s" % (len(chunks), dst))


if __name__ == "__main__":
    main()
