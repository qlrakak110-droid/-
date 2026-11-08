--!strict
-- SeoulSkyline / LandmarkInterior
-- 롯데월드타워 모티브 타워 + 몰의 "걸어 들어가는" 실내 (Landmark 바로 다음에 빌드, Landmark.layout 을 읽음).
-- 실제 스케일 1 stud = 0.3 m. 모든 치수는 Config.m(미터) / Config.Real.
--
--   1) 타워 로비 (지상, 강 쪽 +Z 로컬 면 가운데): 32 × 25 m, 천장 12.6 m 대리석 2개 층 높이 홀.
--      자동 미닫이문 2곳(유효 2.4 × 2.7 m) + 방풍실, 안내 데스크(1.1 m), 보안 게이트 7대(차선 1.1 m), 라운지 2조,
--      미디어 아트 월(28 × 6 m Neon 타일), 실내 나무 4 그루, 한/영 안내 사인, 엘리베이터 알코브(8.4 × 10 m, 천장 4.2 m):
--      양쪽 3대씩 + 끝벽 서울스카이 직행 셔틀(호출 버튼 = 태그 SeoulElevator → 전망대).
--   2) 서울스카이 전망대 (본체 꼭대기 유리 띠): 118F 전망 홀(천장 ≈ 8.6 m) — 광택 바닥, 스카이데크 유리 바닥(7.2 × 3.6 m,
--      빛나는 무한 거울 구덩이 아래 "500 m 아래 야경"), 파노라마 벤치, 망원경, 카페 카운터 + 메뉴판, 기념품숍,
--      반환 엘리베이터 / 123F 스카이 라운지(바 + 라운지 의자)로 가는 엘리베이터.
--      천장·바닥·코어(밖에서 보이는 밝은 유리 띠의 내용)는 Persistent 그룹 → 원경에서도 띠가 밝게 읽힘.
--   3) 몰 아트리움 (파란 곡면 지붕 홀): 정면 입구 통로(자동문) → 66 × 21.6 m 2개 층 갤러리아.
--      양쪽 2개 층 상점 27곳(진열창 + 한글 간판), 에스컬레이터 한 쌍(보이는 계단 + 숨은 경사로), 유리 난간 메자닌 + 다리 2,
--      앉음 섬(나무 화분), 팝업 키오스크, 행잉 배너, 미디어 스크린, 지붕을 열어 실내에서 보이는 파란 볼트 + 리브.
--   광원 30개 이하(로비 8 · 전망대 9 · 몰 12), 파트 ≈ 2000.


local Config = require(script.Parent.Config)
local Kit = require(script.Parent.Kit)
local Landmark = require(script.Parent.Landmark) :: any
local IK = require(script.Parent.InteriorKit)
local TowerLobby = require(script.Parent.TowerLobby)
local SeoulSkyInterior = require(script.Parent.SeoulSkyInterior)
local MallInterior = require(script.Parent.MallInterior)

local LandmarkInterior = {}
local CORE_H = SeoulSkyInterior.CORE_H

------------------------------------------------------------------------------------------------------
-- 진입점
------------------------------------------------------------------------------------------------------
function LandmarkInterior.build(ctx: any)
	local L = Landmark.layout
	if not L or not L.lobby or not L.obs or not L.hall then
		warn("[SeoulSkyline] LandmarkInterior: Landmark.layout 이 없습니다 — Landmark 를 먼저 빌드하세요")
		return
	end
	local lights = 0
	local rng: Random = ctx.rng
	local root: Model = ctx.model
	local TF: CFrame = L.TF
	local Lb, Ob, Hl = L.lobby, L.obs, L.hall
	-- 엘리베이터 도착 지점(캐릭터 피벗 = 바닥 + 3.5, SeoulSkylineBoot 가 -Z 를 보게 세움)
	local obsT = (TF * CFrame.new(0, Ob.yA + 0.15 + 3.5, -CORE_H - 9)).Position
	local loungeT = (TF * CFrame.new(0, Ob.yB + 0.15 + 3.5, -CORE_H - 9)).Position
	local lobbyT = (TF * CFrame.new(0, Lb.floorY + 3.5, Lb.ZB + 22)).Position
	local p0 = Kit.stats.parts
	IK.resetLights(14) -- 로비 광원 상한
	TowerLobby.build(Kit.group(root, "TowerLobby", Config.InteriorStreaming), TF, Lb, obsT, rng)
	local p1 = Kit.stats.parts
	lights += IK.lightsUsed()
	IK.resetLights(18) -- 전망대 + 라운지
	SeoulSkyInterior.build(Kit.group(root, "SeoulSky", Config.InteriorStreaming), Kit.group(root, "SeoulSkyGlow"), TF, Ob, lobbyT, obsT, loungeT, rng)
	local p2 = Kit.stats.parts
	lights += IK.lightsUsed()
	IK.resetLights(22) -- 몰 아트리움
	MallInterior.build(Kit.group(root, "MallAtrium", Config.InteriorStreaming), Hl, rng)
	local p3 = Kit.stats.parts
	lights += IK.lightsUsed()
	-- 다른 도구/디버그용 좌표
	root:SetAttribute("LobbyEntrance", (TF * CFrame.new(0, Lb.floorY + 3.5, Lb.W + 8)).Position)
	root:SetAttribute("LobbyArrival", lobbyT)
	root:SetAttribute("ObservatoryArrival", obsT)
	root:SetAttribute("LoungeArrival", loungeT)
	root:SetAttribute("MallEntrance", (Hl.cf * CFrame.new(0, Hl.FY1 + 3.5, Hl.HZ + 8)).Position)
	root:SetAttribute("Parts", string.format("lobby %d / observatory %d / mall %d", p1 - p0, p2 - p1, p3 - p2))
	root:SetAttribute("Lights", lights)
end

return LandmarkInterior
