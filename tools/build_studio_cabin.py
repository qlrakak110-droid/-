#!/usr/bin/env python3
"""임시 스튜디오(HTML)에 차량 AAA 실내(Luau) + 틴팅 유리(JS)를 함께 넣습니다.

    python3 tools/build_studio_cabin.py <input studio.html> <output.html>

  * tools/patch_car_glass.py 의 유리 패치 전부 (studio/car_glass.js + 차량 모델 연결)
  * engine/bridge.luau  : 실사 차체 스킨(carskin)이 GwSkinKeep 속성이 있는 모델(CabinAAA)은 숨기지 않음
  * js/render3d.js      : Luau 실내가 켜져 있으면(window.GWCabinLuau) 스킨 자체의 단순 좌석 메시는 숨김
  * js/taxi_model.js    : 실사 스킨의 실내 플라스틱(도어 안쪽 · 대시)도 실내 그룹으로 보내 같이 숨김
  * 엔진이 뜬 뒤 src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior 트리(LocalScript + ModuleScript)를
    PlayerScripts 에 넣음 (tools/build_studio.py 의 미니게임 주입과 같은 방식) -> 실제 로블록스와 같은 코드가 돎
"""
import json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import patch_car_glass as pcg  # noqa: E402
from build_studio import walk, to_luau, BUILD  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MARK = pcg.MARK

CABIN_HOOKS = [
    ("engine/bridge.luau", "skin keeps CabinAAA",
     "local function csWalk(node, rec, depth)\n\tfor _, c in I.children(node) do\n\t\tlocal cls = I.classOf(c)",
     "local function csWalk(node, rec, depth)\n\tfor _, c in I.children(node) do\n\t\tif c:GetAttribute(\"GwSkinKeep\") then continue end -- " + MARK + "\n\t\tlocal cls = I.classOf(c)"),
    ("js/render3d.js", "skin seats off with Luau cabin",
     "if (slot.model.interior) slot.model.interior.visible = car.dist < 45;",
     "if (slot.model.interior) slot.model.interior.visible = car.dist < 45 && !root.GWCabinLuau; " + MARK),
    # 실사 스킨의 실내 플라스틱(도어 안쪽 · 대시)도 실내 그룹으로: Luau 실내가 있으면 같이 숨김
    ("js/taxi_model.js", "skin interior plastic with Luau cabin",
     "if(/interior|leather|fabric|carpet|alcantara|screen|seat/i.test(pc.r+' '+pc.n))interior.add(pivot);",
     "if(/interior|leather|fabric|carpet|alcantara|screen|seat/i.test(pc.r+' '+pc.n)||(pc.r==='int_plastic'&&typeof window!=='undefined'&&window.GWCabinLuau))interior.add(pivot);/*" + MARK.strip('/*') + "*/"),
]


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    src_html, out_html = sys.argv[1], sys.argv[2]
    html, report = pcg.patch(open(src_html, encoding="utf-8").read(), extra_hooks=CABIN_HOOKS)
    tree = walk(os.environ.get("CABIN_SRC") or os.path.join(ROOT, "src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior"))
    code = BUILD + "local t = " + to_luau(tree) + '''
local ps; Sched.runIn(Env.serverCtx, function() ps = S.player and S.player:FindFirstChildOfClass("PlayerScripts") end)
if not ps then return "no PlayerScripts" end
if ps:FindFirstChild("GwangalliCarInterior") then return "already" end
put(t, ps)
-- 임시 스튜디오(브라우저 엔진, wasm 메모리 2 GB)에서는 실내를 한 대(+ 내가 탄 차)만 유지
local sc = ps:FindFirstChild("GwangalliCarInterior")
if sc then sc:SetAttribute("MaxCabins", 1) end
return "ok"'''
    js = '''<script>
/* 차량 AAA 실내 + 틴팅 유리: GwangalliCarInterior (Luau) 를 실행 중인 place 에 넣음 (tools/build_studio_cabin.py) */
(function () {
  window.GWCabinLuau = true;
  var code = %s;
  function wait(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }
  async function run() {
    for (var i = 0; i < 600; i++) {
      if (window.GW && GW.engine && GW.engine.running && GW.engine.eval) break;
      await wait(500);
    }
    if (!(window.GW && GW.engine && GW.engine.running)) { console.warn('[CarInterior] engine not running; not injected'); return; }
    await wait(1500);
    // 플레이어(PlayerScripts)가 아직 없으면 생길 때까지 다시 시도 (느린 기기에서 로딩이 길 때)
    for (var k = 0; k < 180; k++) {
      var r;
      try { r = await GW.engine.eval(code); } catch (e) { console.error('[CarInterior] inject failed', e); return; }
      if (r !== 'no PlayerScripts') { console.log('[CarInterior] inject:', r); return; }
      await wait(1000);
    }
    console.warn('[CarInterior] no PlayerScripts; not injected');
  }
  run();
})();
</script>
''' % json.dumps(code, ensure_ascii=False).replace("</", "<\\/")
    i = html.rfind("</body>")
    html = html[:i] + js + html[i:] if i >= 0 else html + js
    open(out_html, "w", encoding="utf-8").write(html)
    print("\n".join(report))
    print(out_html, os.path.getsize(out_html), "bytes")


if __name__ == "__main__":
    main()
