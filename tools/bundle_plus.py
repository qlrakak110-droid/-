#!/usr/bin/env python3
"""광안리 추가 기능 전체를 붙여넣기용 두 파일로 묶습니다.

    python3 tools/bundle_plus.py [out_dir]       (기본 build/)
      -> GwangalliPlus.server.luau   ServerScriptService 에 Script 하나
      -> GwangalliPlus.client.luau   StarterPlayer > StarterPlayerScripts 에 LocalScript 하나

Rojo 폴더 구조(Script / LocalScript + 자식 ModuleScript, ReplicatedStorage 공용 모듈)를 실행 중에 그대로 다시 세웁니다:
  * 모듈 소스는 파일 안의 함수로 들어가고, 같은 이름 · 같은 위치의 빈 자리표시 인스턴스(ModuleScript · 꺼 둔 Script)를
    만들어 둡니다. 각 모듈의 require 는 자리표시(속성 GwVMod)를 받으면 파일 안의 함수를 부릅니다.
    그래서 require(script:WaitForChild("X")), require(ReplicatedStorage:WaitForChild("...Shared")), 동적 require,
    자리표시 아래 실행 중 만든 폴더(노래방 State 등)가 원래 구조와 똑같이 동작합니다.
  * 공용 모듈(ReplicatedStorage)의 자리표시는 서버가 만들고(클라이언트로 복제), 클라이언트는 기다렸다가 씁니다.
  * 서버 파일 맨 위 GW_CONFIG(게임패스 번호, 기능 끄기)는 ReplicatedStorage.GwangalliPlus 속성으로 클라이언트에도 갑니다.
  * 주석 · 빈 줄 · 들여쓰기는 tools/luau_strip.py 로 걷어 냄 (luau-ast 로 원본과 같은 구문 트리인지 확인 가능).
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import luau_strip  # noqa: E402

ROOT = os.environ.get("GW_SRC") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src")
SSS = os.path.join(ROOT, "ServerScriptService")
SPS = os.path.join(ROOT, "StarterPlayer", "StarterPlayerScripts")
RS = os.path.join(ROOT, "ReplicatedStorage")

# 묶는 기능 (순서 = 시작 순서). 차량 실내(GwangalliCarInterior) · 미니게임은 따로 관리하는 코드라 넣지 않음
FEATURES = [
    "GwangalliBuildingInterior",
    "GwangalliPasses",
    "GwangalliClinic",
    "GwangalliKaraokePlus",
    "GwangalliClubPlus",
    "GwangalliShopCrew",
    "GwangalliDecorPlus",
    "GwangalliCarDealer",
]
SHARED = [
    "GwangalliPassesShared",
    "GwangalliClinicShared",
    "GwangalliKaraokeShared",
    "GwangalliClubPlusShared",
    "GwangalliShopCrewShared",
    "GwangalliDecorShared",
    "GwangalliCarDealerShared",
]
NOT_BUNDLED = {"GwangalliGameplay", "GwangalliMiniGames", "GwangalliMiniGamesShared", "GwangalliCarInterior"}

FEATURE_KO = {
    "GwangalliBuildingInterior": "건물 · 가게 · 집 실내 (클라이언트 전용)",
    "GwangalliPasses": "게임패스 1 · 3 · 4번",
    "GwangalliClinic": "병원 진료 (접수 · 진료 · 처치 · 수납 · 약국)",
    "GwangalliKaraokePlus": "코인노래방",
    "GwangalliClubPlus": "클럽 OCEAN 쇼 (전광판 · 랭킹 · 합석)",
    "GwangalliShopCrew": "가게 NPC 직원 · 서빙",
    "GwangalliDecorPlus": "내 집 인테리어",
    "GwangalliCarDealer": "차량 매장 (NPC 카탈로그 · 구매)",
}


def walk(path, name, side):
    """Rojo 규칙으로 폴더/파일을 노드로: {name, cls, src, children}"""
    node = {"name": name, "cls": "Folder", "src": None, "children": []}
    if os.path.isfile(path):
        node["cls"], node["src"] = "ModuleScript", path
        return node
    entries = sorted(os.listdir(path))
    for init, cls in (("init.server.luau", "Script"), ("init.client.luau", "LocalScript"), ("init.luau", "ModuleScript")):
        if init in entries:
            node["cls"], node["src"] = cls, os.path.join(path, init)
            break
    for e in entries:
        p = os.path.join(path, e)
        if e.startswith("init.") and e.endswith(".luau"):
            continue
        if os.path.isdir(p):
            node["children"].append(walk(p, e, side))
        elif e.endswith(".server.luau") or e.endswith(".client.luau"):
            raise SystemExit("nested script not supported: " + p)
        elif e.endswith(".luau"):
            node["children"].append(walk(p, e[: -len(".luau")], side))
    return node


def flatten(node, base, out):
    nid = base + "/" + node["name"] if base else node["name"]
    node["id"] = nid
    if node["src"]:
        out.append(node)
    for c in node["children"]:
        flatten(c, nid, out)


def tree_lua(node):
    kids = ",".join(tree_lua(c) for c in node["children"])
    return '{"%s","%s","%s",{%s}}' % (node["name"], node["cls"], node["id"], kids)


def chunk(node):
    text = open(node["src"], encoding="utf-8").read()
    body = luau_strip.strip(text)
    lines = [l for l in body.split("\n") if not l.startswith("--!")]
    return '-- [%s]\n__defs["%s"] = function(script, require)\n%s\nend' % (node["id"], node["id"], "\n".join(lines))


SERVER_CONFIG = r'''-- ================================================================================================
--  광안리 추가 기능 (서버) — ServerScriptService 에 Script 로 넣으세요. 짝: GwangalliPlus.client.luau (LocalScript)
--  운영자 설정은 아래 GW_CONFIG 한 곳만 고치면 됩니다. 나머지는 손대지 않아도 됩니다.
-- ================================================================================================
local GW_CONFIG = {
	-- 게임패스 번호 (크리에이터 대시보드 > 수익 창출 > 패스 에서 만든 패스의 ID 숫자)
	--   0 = 아직 판매 준비 중: 라이브 서버에서는 상점에 안 보이고 잠금도 걸지 않음. 스튜디오에서는 테스트용으로 보임
	PassIds = {
		PremiumGarage = 0, -- 1번 프리미엄 차고: 프리미엄 차 + 어디서든 내 차 호출 (없으면 정비소에서만 호출)
		Convenience = 0, -- 3번 편의 패스: 유치장 · 기절 대기 50% 단축 + 폰 블랙마켓 앱
		Flex = 0, -- 4번 과시 패스: KO 피니시 이펙트 · 나만의 번호판 · 네온 닉네임
	},
	-- 끄고 싶은 기능만 false 로 (서버 · 클라이언트 둘 다 꺼짐)
	Features = {
%FEATURES%
	},
	-- (선택) 기능 스크립트 속성. 예) GwangalliShopCrew = { Diners = false }
	ScriptAttributes = {},
}
'''

PRELUDE = r'''
local __RS = game:GetService("ReplicatedStorage")
local __RUN = game:GetService("RunService")
local __IS_SERVER = __RUN:IsServer()
local __TAG = "[GwangalliPlus]"
local __defs, __cache, __loading, __failed, __post = {}, {}, {}, {}, {}
local __VERSION = "%VERSION%"

local function __req(x)
	if typeof(x) == "Instance" and x:IsA("ModuleScript") then
		local id = x:GetAttribute("GwVMod")
		if type(id) == "string" and __defs[id] then
			local v = __cache[id]
			if v ~= nil then
				return v
			end
			local th = __loading[id]
			if th ~= nil then
				if th == coroutine.running() then
					error(__TAG .. " 순환 require: " .. id, 2)
				end
				-- 다른 스레드가 로딩 중: 원래 require 처럼 끝날 때까지 기다림
				while __loading[id] ~= nil do
					task.wait()
				end
				if __failed[id] then
					error(__TAG .. " 모듈 로딩 실패: " .. id, 2)
				end
				return __cache[id]
			end
			__loading[id] = coroutine.running()
			local ok, res = xpcall(__defs[id], debug.traceback, x, __req)
			if ok and res == nil then
				ok, res = false, "모듈이 값을 돌려주지 않음"
			end
			if ok and __post[id] then
				__post[id](res)
			end
			__loading[id] = nil
			if not ok then
				__failed[id] = true
				error(__TAG .. " " .. id .. ": " .. tostring(res), 0)
			end
			__cache[id] = res
			return res
		end
	end
	return require(x)
end

-- 자리표시 트리: {이름, 클래스, id, {자식...}}
local function __build(t, parent)
	local cls = t[2]
	local inst = Instance.new(cls)
	inst.Name = t[1]
	if cls == "Script" or cls == "LocalScript" then
		inst.Enabled = false
	end
	if __defs[t[3]] then
		inst:SetAttribute("GwVMod", t[3])
	end
	for _, c in t[4] do
		__build(c, inst)
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function __waitTree(t, inst, timeout)
	for _, c in t[4] do
		local ch = inst:WaitForChild(c[1], timeout)
		if not ch then
			return false
		end
		if not __waitTree(c, ch, timeout) then
			return false
		end
	end
	return true
end

local function __run(id, holder, label)
	task.spawn(function()
		local ok, err = xpcall(__defs[id], debug.traceback, holder, __req)
		if not ok then
			warn(__TAG .. " " .. label .. " 오류: " .. tostring(err))
		end
	end)
end
'''

SERVER_MAIN = r'''
-- 게임패스 번호를 공용 Config 에 반영 (서버 · 클라이언트 같은 값)
__post["GwangalliPassesShared/Config"] = function(C)
	local m = __RS:FindFirstChild("GwangalliPlus")
	if type(C) == "table" and type(C.PASSES) == "table" and m then
		for key, pass in C.PASSES do
			local id = m:GetAttribute("PassId_" .. tostring(key))
			if type(id) == "number" and type(pass) == "table" then
				pass.Id = id
			end
		end
	end
end

local __SSS = game:GetService("ServerScriptService")
local __marker = __RS:FindFirstChild("GwangalliPlus")
if __marker then
	__marker:Destroy()
end
__marker = Instance.new("Folder")
__marker.Name = "GwangalliPlus"
__marker:SetAttribute("Version", __VERSION)
for key, id in GW_CONFIG.PassIds do
	__marker:SetAttribute("PassId_" .. key, tonumber(id) or 0)
end
for name, on in GW_CONFIG.Features do
	if on == false then
		__marker:SetAttribute("Off_" .. name, true)
	end
end

-- 1) 공용 모듈 자리표시 (ReplicatedStorage, 클라이언트로 복제)
for _, t in __SHARED do
	local old = __RS:FindFirstChild(t[1])
	if old and old:GetAttribute("GwVMod") == nil then
		warn(__TAG .. " ReplicatedStorage 에 예전에 넣은 " .. t[1] .. " 가 있습니다. 이 파일과 섞이지 않게 예전 것을 지우세요.")
	end
	if old and old:GetAttribute("GwVMod") ~= nil then
		old:Destroy()
	end
	__build(t, __RS)
end
__marker.Parent = __RS

-- 2) 서버 기능 시작 (ServerScriptService 에 같은 이름의 꺼 둔 Script 자리표시 + 자식 모듈)
for _, t in __SERVER do
	local name = t[1]
	if GW_CONFIG.Features[name] == false then
		continue
	end
	local old = __SSS:FindFirstChild(name)
	if old and old:GetAttribute("GwVMod") == nil then
		warn(__TAG .. " ServerScriptService 에 예전에 넣은 " .. name .. " 가 있어 그것을 씁니다 (두 번 돌지 않게). 새 버전을 쓰려면 예전 것을 지우세요.")
		continue
	end
	if old then
		old:Destroy()
	end
	local holder = __build(t, nil)
	local attrs = GW_CONFIG.ScriptAttributes[name]
	if type(attrs) == "table" then
		for k, v in attrs do
			holder:SetAttribute(k, v)
		end
	end
	holder.Parent = __SSS
	__run(t[3], holder, name)
end
print(__TAG .. " 서버 " .. __VERSION .. " 시작")
'''

CLIENT_MAIN = r'''
__post["GwangalliPassesShared/Config"] = function(C)
	local m = __RS:FindFirstChild("GwangalliPlus")
	if type(C) == "table" and type(C.PASSES) == "table" and m then
		for key, pass in C.PASSES do
			local id = m:GetAttribute("PassId_" .. tostring(key))
			if type(id) == "number" and type(pass) == "table" then
				pass.Id = id
			end
		end
	end
end

local __PS = script.Parent
local __marker = __RS:WaitForChild("GwangalliPlus", 45)
if not __marker then
	warn(__TAG .. " 서버 파일(GwangalliPlus.server)이 없거나 시작하지 않았습니다: 건물 실내만 켭니다.")
end
local __sharedOk = __marker ~= nil
if __marker then
	for _, t in __SHARED do
		local inst = __RS:WaitForChild(t[1], 30)
		if not inst or not __waitTree(t, inst, 30) then
			warn(__TAG .. " 공용 모듈 " .. t[1] .. " 를 받지 못했습니다")
			__sharedOk = false
		end
	end
end

for _, t in __CLIENT do
	local name = t[1]
	if __marker and __marker:GetAttribute("Off_" .. name) == true then
		continue
	end
	if not __sharedOk and name ~= "GwangalliBuildingInterior" then
		continue
	end
	local old = __PS:FindFirstChild(name)
	if old and old:GetAttribute("GwVMod") == nil then
		warn(__TAG .. " StarterPlayerScripts 에 예전에 넣은 " .. name .. " 가 있어 그것을 씁니다 (두 번 돌지 않게). 새 버전을 쓰려면 예전 것을 지우세요.")
		continue
	end
	if old then
		old:Destroy()
	end
	local holder = __build(t, __PS)
	__run(t[3], holder, name)
end
'''


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "..", "build")
    for base in (SSS, SPS, RS):
        for e in os.listdir(base):
            if e.startswith("Gwangalli") and e not in NOT_BUNDLED and e not in FEATURES and e not in SHARED:
                print("WARNING: folder not bundled (add it to FEATURES/SHARED?):", os.path.join(base, e))
    shared = [walk(os.path.join(RS, n), n, "shared") for n in SHARED if os.path.isdir(os.path.join(RS, n))]
    server = [walk(os.path.join(SSS, n), n, "server") for n in FEATURES if os.path.isfile(os.path.join(SSS, n, "init.server.luau"))]
    client = [walk(os.path.join(SPS, n), n, "client") for n in FEATURES if os.path.isfile(os.path.join(SPS, n, "init.client.luau"))]
    for n in shared + server + client:
        flatten(n, "", [])
    version = os.environ.get("GW_VERSION", "dev")

    def emit(side, roots, config):
        mods = []
        for r in shared + roots:
            flatten(r, "", mods)
        parts = ["--!nocheck"]
        if config:
            feats = "\n".join("\t\t%s = true, -- %s" % (n, FEATURE_KO.get(n, n)) for n in FEATURES)
            parts.append(SERVER_CONFIG.replace("%FEATURES%", feats).rstrip())
        else:
            parts.append(
                "-- ================================================================================================\n"
                "--  광안리 추가 기능 (클라이언트) — StarterPlayer > StarterPlayerScripts 에 LocalScript 로 넣으세요.\n"
                "--  짝: GwangalliPlus.server.luau (Script, ServerScriptService). 설정은 서버 파일 맨 위에서만 합니다.\n"
                "-- ================================================================================================"
            )
        parts.append(PRELUDE.replace("%VERSION%", version).rstrip())
        for m in mods:
            parts.append(chunk(m))
        parts.append("local __SHARED = {%s}" % ",".join(tree_lua(r) for r in shared))
        key = "__SERVER" if side == "server" else "__CLIENT"
        parts.append("local %s = {%s}" % (key, ",".join(tree_lua(r) for r in roots)))
        parts.append((SERVER_MAIN if side == "server" else CLIENT_MAIN).rstrip())
        path = os.path.join(out_dir, "GwangalliPlus.%s.luau" % side)
        os.makedirs(out_dir, exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(parts) + "\n")
        print("%s  %d bytes  %d modules  entries: %s" % (path, os.path.getsize(path), len(mods), ", ".join(r["name"] for r in roots)))

    emit("server", server, True)
    emit("client", client, False)


if __name__ == "__main__":
    main()
