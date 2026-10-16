--!strict
-- GwangalliBuildingInterior/Build: 한 매장 짓기. V (Scan.fit) -> K (Kit, 만든 파트 · 숨긴 원본 · 불빛 · 프롬프트)
--   유형 모듈 T_* : { types = { "cafe", ... }, style = function(V) -> S, build = function(K, V, S) }
--   순서: Common.run(K, V, S) (공통 마감 + 리스킨) -> T.build (유형별 디테일) -> 정리.
-- 각 단계는 pcall: 한 단계가 실패해도 나머지는 지어지고 K.log 에 남습니다.

local Kit = require(script.Parent:WaitForChild("Kit"))
local Look = require(script.Parent:WaitForChild("Look"))
local Common = require(script.Parent:WaitForChild("Common"))

local Build = {}

local MODULES = {
	require(script.Parent:WaitForChild("T_cafe")),
	require(script.Parent:WaitForChild("T_pub")),
	require(script.Parent:WaitForChild("T_korean")),
	require(script.Parent:WaitForChild("T_grill")),
	require(script.Parent:WaitForChild("T_seafood")),
	require(script.Parent:WaitForChild("T_fastfood")),
	require(script.Parent:WaitForChild("T_store")),
	require(script.Parent:WaitForChild("T_service")),
	require(script.Parent:WaitForChild("T_style")),
	-- 큰 시설의 방 (Venues)
	require(script.Parent:WaitForChild("T_pc")),
	require(script.Parent:WaitForChild("T_karaoke")),
	require(script.Parent:WaitForChild("T_gs25")),
	require(script.Parent:WaitForChild("T_delivery")),
	require(script.Parent:WaitForChild("T_arcade")),
	require(script.Parent:WaitForChild("T_bowling")),
	require(script.Parent:WaitForChild("T_billiards")),
	require(script.Parent:WaitForChild("T_gym")), -- T_style 의 gym 보다 뒤 (덮어씀)
	require(script.Parent:WaitForChild("T_club")),
	require(script.Parent:WaitForChild("T_facility")),
}
local BY_TYPE: { [string]: any } = {}
for _, m in MODULES do
	for _, t in m.types or {} do
		BY_TYPE[t] = m
	end
end
Build.BY_TYPE = BY_TYPE

-- 유형을 모르는 매장: 깔끔한 기본 마감만
local GENERIC = {
	style = function(V: any): any
		if V.kind == "venue" then
			-- 전용 모듈이 없는 큰 시설의 방: 기존 가구는 그대로, 천장 설비만
			return { chair = false, stool = false, table = false, counter = false, base = false, lower = false, mat = false, clock = false, license = false, cctv = false, ceiling = {}, lights = { kind = "none" }, skip = { upgrades = true, fixtures = true } }
		end
		return {
			chair = { style = "padded", frame = Look.blackMetal, seat = Look.fabricGrey },
			stool = {},
			table = { top = Look.oak, base = Look.blackMetal },
			counter = { front = "panel", frontL = Look.white, topL = Look.marbleWhite },
			ceiling = { grid = false },
			lights = { kind = "downlight" },
		}
	end,
	build = function() end,
}

function Build.moduleFor(t: string?): any
	return (t and BY_TYPE[t]) or GENERIC
end

function Build.run(V: any, parent: Instance): any
	local K = Kit.new(V, parent)
	K.hidden = {}
	local T = Build.moduleFor(V.type)
	local S: any = {}
	local ok, res = pcall(T.style, V)
	if ok and type(res) == "table" then
		S = res
	elseif not ok then
		K:note("style error: " .. tostring(res))
	end
	K.style = S
	Common.run(K, V, S)
	if T.build then
		local ok2, err = pcall(T.build, K, V, S)
		if not ok2 then
			K:note("build error: " .. tostring(err))
		end
	end
	K:finish()
	return K
end

return Build
