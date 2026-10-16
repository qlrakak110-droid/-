--!strict
-- GwangalliBuildingInterior/Hosp_Roof: 옥상 정원 · 휴게 공간 (설계 §7.8, 옥상 윗면 y 25.20).
--   데크 · 퍼걸러 + 줄 조명(밤) · 원형 테이블과 의자 · 벤치 · 화단(가을 단풍) · 전망 데크 · 광안대교 망원경 ·
--   보행로 + 볼라드 조명 · 기계실 펜스 · 유리 안전 난간 + 보이지 않는 막이 · 안내판
-- 망원경: 화면이 원형 시야로 바뀌고 카메라가 광안대교를 당겨 봄. 앞 건물이 시야를 가리면 눈높이를 올려서 찾음.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")

local here = script.Parent
local Lib = require(here:WaitForChild("Hosp_Lib"))
local Look = require(here:WaitForChild("Look"))
local Props = require(here:WaitForChild("Props"))
local Interact = require(here:WaitForChild("Interact"))

local RF = {}

local CF, V3, ANG = CFrame.new, Vector3.new, CFrame.Angles
local PI = math.pi
local M = Enum.Material
local C3 = Color3.fromRGB
local rad = math.rad

local Geo = Lib.Geo
local C = Geo.C
local SND = Geo.SND
local Y = Geo.ROOF -- 25.20

local LK = {
	deck = Look.of(150, 110, 78, M.WoodPlanks),
	teak = Look.of(168, 120, 80, M.Wood),
	darkWood = Look.of(92, 66, 46, M.Wood),
	corten = Look.of(120, 72, 48, M.CorrodedMetal),
	soil = Look.soil,
	paver = Look.of(184, 180, 172, M.Pavement),
	alu = Look.alu,
	steel = Look.steel,
	glass = Look.of(200, 220, 226, M.Glass, { t = 0.5, r = 0.1 }),
	fence = Look.of(150, 154, 158, M.Fabric, { t = 0.55 }),
	bulb = Look.neon(C3(255, 206, 140)),
	bulbOff = Look.of(230, 220, 200, M.Glass, { t = 0.2 }),
	wire = Look.of(30, 30, 32),
}

local function night(): boolean
	local t = Lighting.ClockTime
	return t >= 18.5 or t < 6
end

-- 안전 난간 (네 면 코핑 위) + 보이지 않는 막이 ------------------------------------------------------

local function rails(K: any)
	local yc = 28.42
	local detail = K.detail
	local step = if detail == "high" then 6 elseif detail == "mid" then 10 else 15
	local glass = detail ~= "low"
	-- 각 면: { 시작 점, 끝 점 } (코핑 가운데 선)
	local sides = {
		{ V3(-59.74, yc, -36.12), V3(59.56, yc, -36.12) },
		{ V3(-59.74, yc, 39.22), V3(59.56, yc, 39.22) },
		{ V3(59.56, yc, -36.12), V3(59.56, yc, 39.22) },
		{ V3(-59.74, yc, -36.12), V3(-59.74, yc, 39.22) },
	}
	K:free(function()
		for si, s in sides do
			local a, b = s[1], s[2]
			local len = (b - a).Magnitude
			local n = math.max(1, math.floor(len / step + 0.5))
			for i = 0, n do
				local p = a:Lerp(b, i / n)
				Lib.ab(K, "RailPost", p.X - 0.075, yc, p.Z - 0.075, p.X + 0.075, yc + 1.32, p.Z + 0.075, LK.steel)
				if glass and i < n then
					local q = a:Lerp(b, (i + 1) / n)
					local m = (p + q) / 2
					local alongX = math.abs(q.X - p.X) > math.abs(q.Z - p.Z)
					local l = (q - p).Magnitude - 0.2
					if alongX then
						Lib.ab(K, "RailGlass", m.X - l / 2, yc + 0.05, m.Z - 0.03, m.X + l / 2, yc + 1.20, m.Z + 0.03, LK.glass)
					else
						Lib.ab(K, "RailGlass", m.X - 0.03, yc + 0.05, m.Z - l / 2, m.X + 0.03, yc + 1.20, m.Z + l / 2, LK.glass)
					end
				end
			end
			K:seg("RailTop", a + V3(0, 1.28, 0), b + V3(0, 1.28, 0), 0.18, LK.steel)
			-- 보이지 않는 막이 (난간 위로 뛰어넘지 않게)
			local alongX = math.abs(b.X - a.X) > math.abs(b.Z - a.Z)
			if alongX then
				Lib.guard(K, "RoofGuard" .. si, a.X, yc, a.Z - 0.3, b.X, 34.0, a.Z + 0.3)
			else
				Lib.guard(K, "RoofGuard" .. si, a.X - 0.3, yc, a.Z, a.X + 0.3, 34.0, b.Z)
			end
		end
	end)
	-- 경고 문구 3 곳
	for _, w in { { -40.0, -35.71, -1 }, { -10.0, -35.71, -1 }, { -45.0, 38.86, 1 } } do
		Lib.tx(K, "RailWarn", 3.4, 0.36, Lib.face(w[1], 27.6, w[2], 0, -w[3]), "난간에 기대거나 올라가지 마세요", C.WHITE, C.RED, { font = Lib.FONT_B })
	end
end

-- 화단 ---------------------------------------------------------------------------------------------

local function planter(K: any, x0: number, z0: number, x1: number, z1: number, h: number)
	Lib.wall(K, "PlanterBox", x0, Y, z0, x1, Y + h, z1, LK.corten)
	K:free(function()
		Lib.ab(K, "PlanterSoil", x0 + 0.15, Y + h - 0.2, z0 + 0.15, x1 - 0.15, Y + h - 0.05, z1 - 0.15, LK.soil)
		Lib.ab(K, "PlanterCap", x0 - 0.05, Y + h, z0 - 0.05, x1 + 0.05, Y + h + 0.08, z1 + 0.05, LK.teak)
	end)
end

local function shrubs(K: any, x0: number, z0: number, x1: number, z1: number, top: number, n: number, kind: string)
	local rng = Random.new(math.floor(x0 * 7 + z0 * 13))
	for i = 1, n do
		local x = x0 + (x1 - x0) * ((i - 0.5) / n) + rng:NextNumber(-0.3, 0.3)
		local z = (z0 + z1) / 2 + rng:NextNumber(-(z1 - z0) * 0.25, (z1 - z0) * 0.25)
		if (x1 - x0) < (z1 - z0) then
			x = (x0 + x1) / 2 + rng:NextNumber(-(x1 - x0) * 0.25, (x1 - x0) * 0.25)
			z = z0 + (z1 - z0) * ((i - 0.5) / n) + rng:NextNumber(-0.3, 0.3)
		end
		if kind == "flower" then
			local cols = { C3(220, 60, 80), C3(250, 200, 60), C3(240, 240, 240), C3(170, 90, 200), C3(250, 140, 60) }
			K:ell("FlowerLeaf", V3(0.9, 0.5, 0.9), CF(x, top + 0.2, z), Look.leaf)
			K:ball("Flower", 0.45, CF(x + 0.1, top + 0.5, z - 0.1), { c = cols[i % #cols + 1], m = M.SmoothPlastic })
		elseif kind == "grass" then
			for k = 0, 2 do
				local a = k * 2.1 + i
				K:ell("Grass", V3(0.15, 1.8, 0.15), CF(x + math.cos(a) * 0.25, top + 0.8, z + math.sin(a) * 0.25) * ANG(math.cos(a) * 0.25, 0, math.sin(a) * 0.25), Look.of(150, 160, 90, M.Grass))
			end
		else
			local s = rng:NextNumber(1.3, 1.9)
			K:ell("Shrub", V3(s, s * 0.8, s), CF(x, top + s * 0.35, z), if i % 2 == 0 then Look.leafDark else Look.leaf)
		end
	end
end

local function maple(K: any, x: number, z: number)
	K:vcyl("TreePot", 2.0, 3.2, CF(x, Y + 1.0, z), LK.corten)
	K:disc("TreeSoil", 2.9, 0.05, CF(x, Y + 1.95, z), LK.soil)
	local top = V3(x, Y + 5.2, z)
	K:seg("TreeTrunk", V3(x, Y + 1.9, z), top, 0.35, Look.of(96, 70, 50, M.Wood))
	K:seg("TreeBranch", top - V3(0, 1.0, 0), top + V3(1.0, 0.6, 0.4), 0.18, Look.of(96, 70, 50, M.Wood))
	local cols = { C3(180, 60, 40), C3(214, 120, 40), C3(196, 80, 36), C3(226, 150, 60) }
	for i, o in { V3(0, 1.0, 0), V3(1.0, 0.6, 0.6), V3(-0.8, 0.4, -0.5), V3(0.3, 1.8, -0.3) } do
		K:ell("MapleCanopy", V3(2.6, 2.0, 2.6) * (1 - i * 0.08), CF(top + o), { c = cols[i], m = M.Grass })
	end
end

-- 벤치 (pcf 바닥 가운데, +Z = 앉은 사람이 보는 쪽). 길이 len. 반환: 좌판
local function bench(K: any, pcf: CFrame, len: number): BasePart
	local seat = K:box("BenchSeat", V3(len, 0.2, 1.5), pcf * CF(0, 1.8, 0), LK.teak)
	Lib.solid(seat, true)
	K:free(function()
		for i = 0, 3 do
			K:box("BenchSlat", V3(len, 0.24, 0.12), pcf * CF(0, 2.45 + i * 0.35, -0.72) * ANG(rad(-8), 0, 0), LK.teak)
		end
		for _, sx in { -len / 2 + 0.4, len / 2 - 0.4 } do
			K:box("BenchLeg", V3(0.14, 1.7, 1.4), pcf * CF(sx, 0.85, 0), Look.blackMetal)
			K:box("BenchBackPost", V3(0.12, 1.6, 0.12), pcf * CF(sx, 2.6, -0.78), Look.blackMetal)
		end
	end)
	return seat
end

-- 망원경 시야 --------------------------------------------------------------------------------------

local function bridgeTarget(): (Vector3, Instance?)
	local g = Workspace:FindFirstChild("Gwangalli")
	local b = g and g:FindFirstChild("bridge")
	if b then
		for _, m in b:GetChildren() do
			if m:IsA("Model") and string.find(m.Name, "현수교") and not string.find(m.Name, "상세") then
				local ok, cf, size = pcall(function()
					return m:GetBoundingBox()
				end)
				if ok and cf then
					return cf.Position + V3(0, (size :: Vector3).Y * 0.15, 0), b
				end
			end
		end
	end
	return V3(0, 230, -3300), b
end

local function telescopeView(K: any, env: any, eye: BasePart)
	local UI = env.UI
	local cam = Workspace.CurrentCamera
	if not cam or not eye.Parent then
		return
	end
	local hrp = Lib.localRoot()
	if not hrp then
		return
	end
	local active = true
	local prev = { type = cam.CameraType, fov = cam.FieldOfView, cf = cam.CFrame, subject = cam.CameraSubject }
	local target, bridge = bridgeTarget()
	-- 눈높이 찾기: 앞 건물에 막히면 올림
	local E = eye.Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ex: { Instance } = { env.folder }
	for _, pl in Players:GetPlayers() do
		if pl.Character then
			table.insert(ex, pl.Character)
		end
	end
	params.FilterDescendantsInstances = ex
	local lift = 0
	for _ = 0, 8 do
		local dir = target - (E + V3(0, lift, 0))
		local hit = Workspace:Raycast(E + V3(0, lift, 0), dir, params)
		if not hit or (bridge and hit.Instance:IsDescendantOf(bridge)) then
			break
		end
		lift += 15
	end
	E += V3(0, lift, 0)
	local start = hrp.Position
	local t0 = os.clock()
	cam.CameraType = Enum.CameraType.Scriptable
	local base = CFrame.lookAt(E, target)
	cam.CFrame = base
	cam.FieldOfView = 70
	TweenService:Create(cam, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = 22 }):Play()
	local conn: RBXScriptConnection? = nil
	local function close()
		if not active then
			return
		end
		active = false
		if conn then
			conn:Disconnect()
		end
		pcall(function()
			ContextActionService:UnbindAction("GwHospScope")
		end)
		UI.scope(false)
		cam.CameraType = prev.type
		cam.FieldOfView = prev.fov
		if prev.subject then
			cam.CameraSubject = prev.subject
		end
		cam.CFrame = prev.cf
	end
	UI.scope(true, close, "광안대교 Gwangan Bridge")
	UI.toast("광안대교 · 총연장 7,420m · 2002년 개통 · 밤에는 경관조명이 켜져요", 4)
	Lib.sfx2d(SND.click, { vol = 0.4, speed = 0.8 })
	pcall(function()
		ContextActionService:BindActionAtPriority("GwHospScope", function(_n, state)
			if state == Enum.UserInputState.Begin then
				close()
				return Enum.ContextActionResult.Sink
			end
			return Enum.ContextActionResult.Pass
		end, false, 3000, Enum.KeyCode.Space, Enum.KeyCode.ButtonA, Enum.KeyCode.ButtonB)
	end)
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		local h = Lib.localRoot()
		if not h or (h.Position - start).Magnitude > 3 or t > 30 or not eye.Parent then
			close()
			return
		end
		local pan = math.sin(t * 2 * PI * 0.08) * rad(4)
		cam.CFrame = base * ANG(0, pan, 0)
	end)
	table.insert(K.conns, conn)
	Lib.onClean(K, close)
	K.scopeClose = close
end

-- 짓기 ---------------------------------------------------------------------------------------------

function RF.build(K: any, env: any)
	local detail = K.detail
	local high = detail == "high"
	local low = detail == "low"
	-- 1) 안전 먼저: 난간 · 막이
	rails(K)
	-- 2) 바닥: 데크 · 전망 데크 · 보행로
	Lib.wall(K, "RoofDeck", -50.0, Y, 4.0, -22.0, Y + 0.30, 26.0, LK.deck)
	K:free(function()
		Lib.ab(K, "DeckTrim", -50.05, Y, 3.95, -21.95, Y + 0.32, 4.05, LK.alu)
		Lib.ab(K, "DeckTrim", -50.05, Y, 25.95, -21.95, Y + 0.32, 26.05, LK.alu)
		Lib.ab(K, "DeckTrim", -22.05, Y, 4.0, -21.95, Y + 0.32, 26.0, LK.alu)
	end)
	Lib.wall(K, "ViewDeck", -50.0, Y, -35.2, -24.0, Y + 0.25, -29.5, LK.deck)
	Lib.wall(K, "LiftPavers", -34.6, Y, 26.0, -29.6, Y + 0.14, 33.3, LK.paver)
	Lib.wall(K, "GardenPath", -38.0, Y, -29.5, -35.0, Y + 0.14, 4.0, LK.paver)
	Lib.wall(K, "RoofDoorPath", -35.0, Y, -5.4, 36.0, Y + 0.12, -4.0, LK.paver)
	-- 3) 망원경 (전망 데크)
	local tcf = CF(-37.0, Y + 0.25, -34.2)
	K:vcyl("TeleBase", 0.3, 1.6, tcf * CF(0, 0.15, 0), Look.blackMetal)
	K:vcyl("TelePost", 3.0, 0.5, tcf * CF(0, 1.8, 0), Look.of(40, 120, 110, M.Metal))
	K:box("TeleHead", V3(1.4, 0.8, 1.6), tcf * CF(0, 3.6, 0), Look.of(40, 120, 110, M.Metal))
	for _, sx in { -0.35, 0.35 } do
		K:cyl("TeleBarrel", 0.9, 0.36, tcf * CF(sx, 3.65, -0.9) * ANG(0, PI / 2, 0), Look.blackMetal)
	end
	local eye = K:box("TeleEyepiece", V3(1.0, 0.3, 0.3), tcf * CF(0, 3.7, 0.9), Look.black)
	Lib.tx(K, "TeleLabel", 1.2, 0.3, Lib.face(-37.0, Y + 3.4, -33.39, 0, 1), "광안대교 망원경 · 무료", C.WHITE, C.TEAL, { font = Lib.FONT_B })
	Interact.prompt(K, eye, { action = "광안대교 보기", object = "망원경", sound = SND.click, fn = function()
		if K.scopeClose then
			local c = K.scopeClose
			K.scopeClose = nil
			c()
			return
		end
		telescopeView(K, env, eye)
	end })
	Lib.tx(K, "ViewBoard", 2.8, 1.6, Lib.face(-30.0, Y + 2.0, -35.2, 0, 1), "광안리 해변 · 광안대교 방향\n↓ 남쪽 (약 3.5 km)", C.WHITE, C.NAVY, { font = Lib.FONT_B })
	-- 4) 벤치 (데크 북쪽 2 · 전망 데크 2)
	local benches = {
		{ CF(-43.5, Y + 0.30, 23.6) * ANG(0, PI, 0), 7.0, "벤치" },
		{ CF(-34.5, Y + 0.30, 23.6) * ANG(0, PI, 0), 7.0, "벤치" },
		{ CF(-44.0, Y + 0.25, -31.5) * ANG(0, PI, 0), 6.0, "전망 벤치" },
		{ CF(-30.0, Y + 0.25, -31.5) * ANG(0, PI, 0), 6.0, "전망 벤치" },
	}
	for _, b in benches do
		local pcf: CFrame = b[1] :: CFrame
		local len: number = b[2] :: number
		bench(K, pcf, len)
		for _, sx in { -len / 4 - 0.2, len / 4 + 0.2 } do
			local sp = pcf * CF(sx, 1.9, 0)
			local anchor = K:box("BenchSeatSpot", V3(0.4, 0.05, 0.4), sp, { c = Color3.new(1, 1, 1), t = 1, free = true })
			Lib.seatPrompt(K, anchor, sp, b[3] :: string)
		end
	end
	-- 5) 퍼걸러
	K:free(function()
		for _, p in { { -46, 8 }, { -46, 20 }, { -32, 8 }, { -32, 20 } } do
			Lib.solid(Lib.ab(K, "PergolaPost", p[1] - 0.3, Y + 0.3, p[2] - 0.3, p[1] + 0.3, 33.1, p[2] + 0.3, LK.darkWood), true)
		end
		for _, z in { 8, 20 } do
			Lib.ab(K, "PergolaBeam", -46.5, 32.6, z - 0.25, -31.5, 33.4, z + 0.25, LK.darkWood)
		end
		for i = 0, 10 do
			local x = -46.5 + i * 1.5
			Lib.ab(K, "PergolaRafter", x - 0.125, 33.4, 7.25, x + 0.125, 33.9, 20.75, LK.darkWood)
		end
	end)
	-- 6) 원형 테이블 + 의자 4 씩
	for _, tp in { { -42.0, 14.0 }, { -36.0, 14.0 } } do
		local x, z = tp[1], tp[2]
		K:free(function()
			Lib.solid(K:disc("TableTop", 3.2, 0.12, CF(x, Y + 0.3 + 2.55, z), LK.teak), true)
			K:vcyl("TablePedestal", 2.4, 0.25, CF(x, Y + 0.3 + 1.3, z), LK.alu)
			K:disc("TableFoot", 1.4, 0.08, CF(x, Y + 0.34, z), LK.alu)
		end)
		for k = 0, 3 do
			local a = k * PI / 2 + PI / 4
			local cx, cz = x + math.cos(a) * 2.3, z + math.sin(a) * 2.3
			local pcf = CFrame.lookAt(V3(cx, Y + 0.3, cz), V3(x, Y + 0.3, z))
			-- Props.chair: +Z = 앉은 사람이 보는 쪽 → lookAt 의 -Z 가 테이블이므로 180° 돌림
			pcf = pcf * ANG(0, PI, 0)
			Props.chair(K, pcf, { style = "shell", frame = LK.alu, seat = LK.teak, back = LK.teak, detail = "low" })
			local sp = pcf * CF(0, 1.9, 0)
			local anchor = K:box("ChairSeatSpot", V3(0.4, 0.05, 0.4), sp, { c = Color3.new(1, 1, 1), t = 1, free = true })
			Lib.seatPrompt(K, anchor, sp, "의자")
		end
	end
	-- 7) 화단 · 나무
	planter(K, -52.5, 4.0, -50.0, 26.0, 2.4)
	planter(K, -50.0, 1.0, -26.0, 3.6, 1.6)
	planter(K, -50.0, 26.2, -36.0, 28.0, 1.8)
	if not low then
		shrubs(K, -52.3, 4.2, -50.2, 25.8, Y + 2.2, if high then 8 else 5, "shrub")
		shrubs(K, -52.3, 5.0, -50.2, 25.0, Y + 2.2, if high then 5 else 3, "grass")
		shrubs(K, -49.8, 1.2, -26.2, 3.4, Y + 1.4, if high then 12 else 6, "flower")
		K:free(function()
			Lib.ab(K, "Hedge", -49.8, Y + 1.6, 26.4, -36.2, Y + 3.0, 27.8, Look.of(56, 96, 52, M.Grass))
		end)
		maple(K, -24.0, 6.0)
		maple(K, -24.0, 23.0)
	end
	-- 8) 기계실 펜스 (물탱크 · 실외기)
	local function fence(x0: number, z0: number, x1: number, z1: number, gateLabel: string)
		local h = 4.4
		for _, s in { { x0, z0, x1, z0 }, { x0, z1, x1, z1 }, { x0, z0, x0, z1 }, { x1, z0, x1, z1 } } do
			local alongX = s[2] == s[4]
			if alongX then
				Lib.solid(Lib.ab(K, "FenceMesh", s[1], Y, s[2] - 0.03, s[3], Y + h, s[2] + 0.03, LK.fence), true)
				Lib.ab(K, "FenceRail", s[1], Y + h - 0.1, s[2] - 0.06, s[3], Y + h, s[2] + 0.06, LK.alu)
			else
				Lib.solid(Lib.ab(K, "FenceMesh", s[1] - 0.03, Y, s[2], s[1] + 0.03, Y + h, s[4], LK.fence), true)
				Lib.ab(K, "FenceRail", s[1] - 0.06, Y + h - 0.1, s[2], s[1] + 0.06, Y + h, s[4], LK.alu)
			end
		end
		K:free(function()
			for _, c in { { x0, z0 }, { x1, z0 }, { x0, z1 }, { x1, z1 } } do
				Lib.ab(K, "FencePost", c[1] - 0.1, Y, c[2] - 0.1, c[1] + 0.1, Y + h + 0.1, c[2] + 0.1, LK.alu)
			end
		end)
		Lib.tx(K, "FenceSign", 2.8, 0.6, Lib.face((x0 + x1) / 2, Y + 2.6, z0 - 0.04, 0, -1), gateLabel, C.WHITE, C.RED, { font = Lib.FONT_B })
	end
	K:free(function()
		fence(-14.0, 16.5, -5.5, 25.5, "기계실 · 관계자 외 출입금지")
		fence(-18.5, -19.0, -5.0, -12.5, "기계실 · 관계자 외 출입금지")
	end)
	-- 9) 안내판 · 금연
	local pb = Lib.face(-36.20, Y + 3.1, 35.5, -1, 0)
	K:plate("GardenBoardBack", 3.0, 2.6, 0.06, pb, Look.of(250, 250, 248))
	Lib.tx(K, "GardenBoardTitle", 2.8, 0.6, pb * CF(0, 0.9, 0.065), "하늘정원 · 옥상 휴게공간", C.WHITE, C.TEAL, { font = Lib.FONT_K })
	Lib.tx(K, "GardenBoardText", 2.8, 1.6, pb * CF(0, -0.3, 0.065), "이용 시간 09:00 ~ 21:00\n금연 · 음주 금지\n환자분은 보호자와 함께\n이용해 주세요", C.INK, nil, { font = Lib.FONT_M })
	local function noSmoke(x: number, z: number, yaw: number)
		local c = CF(x, Y, z) * ANG(0, yaw, 0)
		K:box("SignPost", V3(0.12, 3.0, 0.12), c * CF(0, 1.5, 0), Look.blackMetal)
		K:box("SignPanel", V3(1.6, 1.1, 0.06), c * CF(0, 3.4, 0), Look.white)
		Lib.tx(K, "NoSmokeSign", 1.5, 1.0, c * CF(0, 3.4, 0.031), "🚭 금연 구역\n위반 시 과태료 10만원\n(국민건강증진법)", C.RED, nil, { font = Lib.FONT_B })
	end
	noSmoke(-23.0, 2.0, 0)
	noSmoke(35.0, -6.6, 0)
	-- 10) 볼라드 조명 (보행로)
	local bollards = {}
	for i = 0, 7 do
		local x = 32.0 - i * 9.0
		local bz = -6.0
		K:vcyl("Bollard", 1.2, 0.35, CF(x, Y + 0.6, bz), Look.of(60, 62, 66, M.Metal))
		table.insert(bollards, K:vcyl("BollardCap", 0.2, 0.33, CF(x, Y + 1.0, bz), LK.bulbOff))
	end
	-- 11) 줄 조명 (퍼걸러, 밤에 켜짐)
	local bulbs: { BasePart } = {}
	local runs = if high then { -44.0, -40.0, -36.0, -33.5 } elseif detail == "mid" then { -42.0, -35.0 } else {}
	for _, rx in runs do
		local pts = {}
		local n = 9
		for i = 0, n do
			local z = 8.3 + (20 - 8.3 - 0.3) * i / n
			local sag = 0.9 * (1 - ((z - 14) / 6) ^ 2)
			table.insert(pts, V3(rx, 32.55 - sag, z))
		end
		K:free(function()
			for i = 1, #pts - 1 do
				K:seg("LightWire", pts[i], pts[i + 1], 0.03, LK.wire)
			end
			for i = 2, #pts - 1 do
				table.insert(bulbs, K:ball("StringBulb", 0.22, CF(pts[i] - V3(0, 0.14, 0)), LK.bulbOff))
			end
		end)
	end
	local lights = {}
	if bulbs[3] then
		table.insert(lights, K:light(bulbs[3], "PointLight", { Range = 18, Brightness = 0.8, Color = Look.warmLight, Enabled = false }))
	end
	if #bulbs > 12 then
		table.insert(lights, K:light(bulbs[#bulbs - 3], "PointLight", { Range = 18, Brightness = 0.8, Color = Look.warmLight, Enabled = false }))
	end
	local lastNight: boolean? = nil
	Lib.onSec(K, function()
		local nt = night()
		if nt == lastNight then
			return
		end
		lastNight = nt
		for _, b in bulbs do
			if b.Parent then
				b.Material = if nt then M.Neon else M.Glass
				b.Color = if nt then C3(255, 206, 140) else C3(230, 220, 200)
				b.Transparency = if nt then 0 else 0.2
			end
		end
		for _, b in bollards do
			if b.Parent then
				b.Material = if nt then M.Neon else M.Glass
				b.Color = if nt then C3(255, 230, 190) else C3(230, 220, 200)
			end
		end
		for _, l in lights do
			if l then
				l.Enabled = nt
			end
		end
	end)
end

function RF.ready(_env: any): boolean
	return Lib.building() ~= nil
end

return RF
