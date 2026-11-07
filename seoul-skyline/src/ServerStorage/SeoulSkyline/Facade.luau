--!strict
-- SeoulSkyline / Facade
-- 건물 파사드 생성기 — 모든 고층/아파트/원경 건물이 같은 "야경 언어"를 쓰도록 하는 공용 모듈.
--
-- 핵심 기법 (z-fighting 0, 파트 수 최소):
--   * 안쪽 "조명 코어"(Neon, 층 묶음마다 다른 색/밝기 = 켜진 사무실/집)를 외벽보다 inset 만큼 들여서 놓고
--   * 층마다 코어를 감싸는 "층 슬래브"(유리/콘크리트 띠)가 바깥으로 튀어나와 가로 띠를 만들고
--   * 건물을 관통하는 "멀리언/벽 핀" 하나가 마주 보는 두 면의 세로선을 동시에 만들어 창 격자를 완성
--   * 관통하는 어두운 "꺼진 창" 패치가 불 꺼진 집/사무실을 랜덤하게 표현
--   모든 표면은 서로 최소 0.3 stud 이상 떨어져 있어 원거리에서도 깜빡임이 없음.
--
--   Facade.tower(parent, spec) -> Model     (style = "curtain" | "round" | "apartment" | "mid" | "far")
--   spec: TowerSpec (아래)
--   반환 모델의 Attribute: Height, Style
--   실제 스케일(1 stud = 0.3 m): 오피스 층고 4.0 m, 아파트 층고 2.9 m — Config.Real 참조.

local Config = require(script.Parent.Config)
local Kit = require(script.Parent.Kit)

local P = Config.Palette
local Facade = {}

export type TowerSpec = {
	name: string?,
	cf: CFrame, -- 건물 바닥 중심(지면 높이) + 방향(yaw)
	w: number, -- 로컬 X 폭
	d: number, -- 로컬 Z 깊이
	h: number, -- 높이(지면 → 지붕)
	style: string,
	rng: Random,
	floorH: number?,
	bay: number?, -- 멀리언/세대 벽 간격
	glass: Color3?, -- 층 슬래브(외피) 색
	frame: Color3?, -- 멀리언 색
	lit: { Color3 }?, -- 켜진 층 색 후보
	litChance: number?, -- 0..1 켜진 비율
	crown: string?, -- "flat" | "led" | "spire" | "helipad" | "box" | "frame" | "slant" | "none"
	ledColor: Color3?,
	tiers: number?, -- curtain: 1~3 단 셋백
	label: string?, -- apartment: 측벽 동 번호
	accent: Color3?, -- apartment: 측벽 슈퍼그래픽 색
	collide: boolean?, -- 기본 true
	beacon: boolean?, -- 기본: h >= 200 이면 true
	glint: boolean?, -- true: 수면 반사 스트릭 생성 (강변 건물)
	lobbyColor: Color3?, -- 로비(1~2층) 발광 색. 기본: 따뜻한 은은한 빛
	terraceLed: boolean?, -- 셋백 테라스 LED 띠 (기본 true)
}

local LIT_OFFICE = { P.WindowCool, P.WindowCool, P.WindowCoolDim, P.WindowWarm, P.WindowWarmDim }
local LIT_HOME = { P.WindowWarm, P.WindowWarm, P.WindowWarmDim, P.WindowGold, P.WindowCoolDim }

Facade.LIT_OFFICE = LIT_OFFICE
Facade.LIT_HOME = LIT_HOME

local function pick<T>(rng: Random, t: { T }): T
	return t[rng:NextInteger(1, #t)]
end

local function jitter(rng: Random, c: Color3, amt: number): Color3
	local k = 1 + (rng:NextNumber() * 2 - 1) * amt
	return Color3.new(math.clamp(c.R * k, 0, 1), math.clamp(c.G * k, 0, 1), math.clamp(c.B * k, 0, 1))
end

------------------------------------------------------------------------------------------------------
-- 공통: 조명 코어 (층 묶음으로 나눈 Neon 블록)
------------------------------------------------------------------------------------------------------
local function litCore(m: Model, base: CFrame, cw: number, cd: number, y0: number, y1: number, floorH: number, rng: Random, lit: { Color3 }, litChance: number, round: boolean, offColor: Color3)
	local y = y0
	while y < y1 - 0.01 do
		local floors = rng:NextInteger(2, 7)
		local hgt = math.min(floors * floorH, y1 - y)
		local on = rng:NextNumber() < math.clamp(litChance + 0.15, 0, 1)
		local c = if on then jitter(rng, pick(rng, lit), 0.08) else offColor
		local cf = base * CFrame.new(0, y + hgt / 2, 0)
		local opts = {
			name = "Core",
			material = if on then Enum.Material.Neon else Enum.Material.Glass,
			color = c,
			collide = false,
			query = false,
			shadow = false,
			glow = on,
			dayMaterial = Enum.Material.Glass,
			dayColor = P.GlassDeep,
		}
		if round then
			Kit.cylAlongY(m, cf, hgt, cw, c, nil, opts)
		else
			Kit.part(m, cf, Vector3.new(cw, hgt, cd), opts)
		end
		y += hgt
	end
end

------------------------------------------------------------------------------------------------------
-- 크라운 / 옥상
------------------------------------------------------------------------------------------------------
local function crown(m: Model, base: CFrame, w: number, d: number, top: number, spec: TowerSpec, rng: Random, round: boolean)
	local kind = spec.crown or "flat"
	local frame = spec.frame or P.Mullion
	local led = spec.ledColor or P.LedGold
	local roofC = P.ConcreteDark
	-- 지붕 슬래브
	if round then
		Kit.cylAlongY(m, base * CFrame.new(0, top + 1, 0), 2, w, roofC, Enum.Material.Concrete, { name = "Roof" })
	else
		Kit.box(m, base * CFrame.new(0, top + 1, 0), Vector3.new(w, 2, d), roofC, Enum.Material.Concrete, { name = "Roof" })
	end
	local crownTop = top + 2
	if kind == "led" or kind == "frame" then
		-- 꼭대기 LED 띠(건물 외곽을 따라 빛나는 링) + 파라펫
		local ph = math.clamp(spec.h * 0.03, 7, 27)
		if round then
			Kit.cylAlongY(m, base * CFrame.new(0, top + ph / 2, 0), ph, w + 0.6, frame, Enum.Material.Glass, { name = "Parapet", reflectance = 0.15 })
			Kit.cylAlongY(m, base * CFrame.new(0, top + ph + 0.8, 0), 1.6, w + 2, led, Enum.Material.Neon, { name = "Led", glow = true, collide = false })
		else
			Kit.box(m, base * CFrame.new(0, top + ph / 2, 0), Vector3.new(w + 0.6, ph, d + 0.6), frame, Enum.Material.Glass, { name = "Parapet", reflectance = 0.15 })
			Kit.box(m, base * CFrame.new(0, top + ph + 0.8, 0), Vector3.new(w + 2, 1.6, d + 2), led, Enum.Material.Neon, { name = "Led", glow = true, collide = false })
			if kind == "frame" then
				-- 옥상 장식 프레임(한국 고층 아파트/오피스 특유의 왕관 프레임)
				local fh = math.clamp(spec.h * 0.07, 17, 56)
				for _, sx in { -1, 1 } do
					Kit.box(m, base * CFrame.new(sx * (w / 2 - 1.6), top + ph + fh / 2, 0), Vector3.new(3.2, fh, d * 0.9), frame, Enum.Material.Metal, { name = "CrownFrame" })
				end
				Kit.box(m, base * CFrame.new(0, top + ph + fh, 0), Vector3.new(w, 3.2, d * 0.9), frame, Enum.Material.Metal, { name = "CrownFrame" })
				Kit.box(m, base * CFrame.new(0, top + ph + fh + 2.2, 0), Vector3.new(w + 0.6, 1.3, d * 0.9 + 0.6), led, Enum.Material.Neon, { name = "Led", glow = true, collide = false })
				crownTop = top + ph + fh + 3
			else
				crownTop = top + ph + 1.6
			end
		end
	elseif kind == "spire" then
		local sh = math.clamp(spec.h * 0.16, 40, 150)
		Kit.box(m, base * CFrame.new(0, top + 10, 0), Vector3.new(w * 0.45, 20, d * 0.45), frame, Enum.Material.Metal, { name = "SpireBase" })
		Kit.cylAlongY(m, base * CFrame.new(0, top + 20 + sh / 2, 0), sh, 3.6, P.MullionLight, Enum.Material.Metal, { name = "Spire" })
		Kit.box(m, base * CFrame.new(0, top + 20.8, 0), Vector3.new(w * 0.45 + 1, 1.6, d * 0.45 + 1), led, Enum.Material.Neon, { name = "Led", glow = true, collide = false })
		crownTop = top + 20 + sh
	elseif kind == "helipad" then
		local r = math.min(w, d) * 0.8
		Kit.cylAlongY(m, base * CFrame.new(0, top + 7, 0), 2, r, P.ConcreteGrey, Enum.Material.Concrete, { name = "Helipad" })
		Kit.cylAlongY(m, base * CFrame.new(0, top + 8.2, 0), 0.4, r * 0.6, P.LaneYellow, Enum.Material.Neon, { name = "HeliRing", glow = true, collide = false, transparency = 0.35 })
		Kit.box(m, base * CFrame.new(0, top + 3.4, 0), Vector3.new(w * 0.5, 6.8, d * 0.5), P.ConcreteDark, Enum.Material.Concrete, { name = "HeliBase" })
		crownTop = top + 8.5
	elseif kind == "slant" then
		-- 비스듬히 잘린 지붕(웨지) + 엣지 LED
		local sh = math.clamp(spec.h * 0.1, 20, 100)
		local wd = Kit.wedge(m, base * CFrame.new(0, top + sh / 2, 0) * CFrame.Angles(0, if rng:NextNumber() < 0.5 then 0 else math.pi, 0), Vector3.new(w, sh, d), spec.glass or P.GlassBlue, Enum.Material.Glass, { name = "SlantRoof", reflectance = 0.2 })
		wd.CastShadow = true
		Kit.box(m, base * CFrame.new(0, top + 1.4, 0), Vector3.new(w + 1.2, 1.3, d + 1.2), led, Enum.Material.Neon, { name = "Led", glow = true, collide = false })
		crownTop = top + sh
	elseif kind == "box" then
		-- 기계실 + 물탱크
		local bw, bd = w * rng:NextNumber(0.35, 0.6), d * rng:NextNumber(0.35, 0.6)
		local bh = rng:NextNumber(9, 16)
		Kit.box(m, base * CFrame.new(rng:NextNumber(-0.15, 0.15) * w, top + 2 + bh / 2, rng:NextNumber(-0.15, 0.15) * d), Vector3.new(bw, bh, bd), P.ConcreteGrey, Enum.Material.Concrete, { name = "Mech" })
		crownTop = top + 2 + bh
	end
	-- 항공장애등
	local wantBeacon = if spec.beacon == nil then spec.h >= 330 else spec.beacon -- 항공장애등: 높이 100 m 이상
	if wantBeacon then
		Kit.beacon(m, (base * CFrame.new(0, crownTop + 2.6, 0)).Position, 4.2)
		if not round and spec.h >= 540 then
			for _, s in { { -1, -1 }, { 1, 1 } } do
				Kit.beacon(m, (base * CFrame.new(s[1] * (w / 2 - 1.6), top + 4, s[2] * (d / 2 - 1.6))).Position, 3.4)
			end
		end
	end
	return crownTop
end

------------------------------------------------------------------------------------------------------
-- 커튼월 오피스 (사각)
------------------------------------------------------------------------------------------------------
local function curtainBlock(m: Model, base: CFrame, w: number, d: number, y0: number, y1: number, spec: TowerSpec, rng: Random)
	local floorH = spec.floorH or Config.Real.OfficeFloor
	local bay = spec.bay or (if w > 90 then 12 else 10)
	local glass = spec.glass or P.GlassDeep
	local frame = spec.frame or P.Mullion
	local lit = spec.lit or LIT_OFFICE
	local litChance = spec.litChance or 0.7
	local inset = 1.4
	local slabRatio = 0.4
	local h = y1 - y0
	-- 1) 조명 코어
	litCore(m, base, w - inset * 2, d - inset * 2, y0, y1, floorH, rng, lit, litChance, false, P.WindowOff)
	-- 2) 층 슬래브 (반사 유리 띠)
	local slabH = floorH * slabRatio
	local nFloors = math.floor(h / floorH)
	for i = 0, nFloors - 1 do
		local yb = y0 + i * floorH
		Kit.box(m, base * CFrame.new(0, yb + slabH / 2, 0), Vector3.new(w, slabH, d), glass, Enum.Material.Glass, {
			name = "Slab",
			reflectance = 0.18,
			collide = (spec.collide ~= false) and i == 0,
			shadow = false,
		})
	end
	-- 상단 마감 슬래브
	Kit.box(m, base * CFrame.new(0, y1 - slabH / 2, 0), Vector3.new(w + 0.4, slabH, d + 0.4), glass, Enum.Material.Glass, { name = "SlabTop", reflectance = 0.18, shadow = false })
	-- 3) 멀리언 (관통 핀 → 마주 보는 두 면에 동시에 세로선)
	local finW, out = 1.1, 0.5
	local nx = math.max(1, math.floor(w / bay))
	for i = 1, nx - 1 do
		local x = -w / 2 + i * (w / nx)
		Kit.box(m, base * CFrame.new(x, y0 + h / 2, 0), Vector3.new(finW, h, d + out * 2), frame, Enum.Material.Metal, { name = "Fin", collide = false, query = false, shadow = false })
	end
	local nz = math.max(1, math.floor(d / bay))
	for i = 1, nz - 1 do
		local z = -d / 2 + i * (d / nz)
		Kit.box(m, base * CFrame.new(0, y0 + h / 2, z), Vector3.new(w + out * 2, h, finW), frame, Enum.Material.Metal, { name = "Fin", collide = false, query = false, shadow = false })
	end
	-- 모서리 기둥
	for _, s in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		Kit.box(m, base * CFrame.new(s[1] * (w / 2), y0 + h / 2, s[2] * (d / 2)), Vector3.new(2.2, h, 2.2), frame, Enum.Material.Metal, { name = "Corner", collide = false, shadow = false })
	end
	-- 4) 꺼진 창 패치 (관통)
	local cells = nFloors * (nx + nz)
	local nPatch = math.clamp(math.floor(cells * (1 - litChance) / 9), 0, 26)
	for _ = 1, nPatch do
		local alongX = rng:NextNumber() < (w / (w + d))
		local fl = rng:NextInteger(1, math.max(1, nFloors - 2))
		local nfl = rng:NextInteger(1, 3)
		local hh = math.min(nfl, nFloors - fl) * floorH - slabH
		if hh > 0.5 then
			local yc = y0 + fl * floorH + slabH + hh / 2
			if alongX then
				local nb = rng:NextInteger(1, 3)
				local i0 = rng:NextInteger(0, math.max(0, nx - nb))
				local bw = nb * (w / nx) - finW
				local x = -w / 2 + (i0 + nb / 2) * (w / nx)
				Kit.box(m, base * CFrame.new(x, yc, 0), Vector3.new(bw, hh, d - inset * 2 + 1.6), P.WindowOff, Enum.Material.Glass, { name = "Off", collide = false, query = false, shadow = false, reflectance = 0.1 })
			else
				local nb = rng:NextInteger(1, 3)
				local i0 = rng:NextInteger(0, math.max(0, nz - nb))
				local bd = nb * (d / nz) - finW
				local z = -d / 2 + (i0 + nb / 2) * (d / nz)
				Kit.box(m, base * CFrame.new(0, yc, z), Vector3.new(w - inset * 2 + 1.6, hh, bd), P.WindowOff, Enum.Material.Glass, { name = "Off", collide = false, query = false, shadow = false, reflectance = 0.1 })
			end
		end
	end
	-- 충돌용 보이지 않는 몸체 (가벼운 단일 박스)
	if spec.collide ~= false then
		Kit.box(m, base * CFrame.new(0, y0 + h / 2, 0), Vector3.new(w - inset * 2, h, d - inset * 2), P.WindowOff, Enum.Material.SmoothPlastic, { name = "Collision", transparency = 1, shadow = false })
	end
end

local function curtain(m: Model, spec: TowerSpec, rng: Random): number
	local base = spec.cf
	local tiers = math.clamp(spec.tiers or 1, 1, 3)
	local w, d = spec.w, spec.d
	local y = 0
	local h = spec.h
	-- 로비 (밝은 1~2층 + 캐노피)
	local lobbyH = math.min(20, h * 0.06) -- 로비 6 m
	Kit.box(m, base * CFrame.new(0, lobbyH / 2, 0), Vector3.new(w - 4, lobbyH, d - 4), spec.lobbyColor or P.WindowWarmDim, Enum.Material.Neon, { name = "Lobby", glow = true })
	Kit.box(m, base * CFrame.new(0, lobbyH + 0.8, 0), Vector3.new(w + 6, 1.6, d + 6), P.ConcreteDark, Enum.Material.Concrete, { name = "Canopy", shadow = false })
	y = lobbyH + 1.6
	local remaining = h - y
	for t = 1, tiers do
		local frac = if t == tiers then 1 else (if tiers == 2 then 0.62 else (if t == 1 then 0.5 else 0.6))
		local th = if t == tiers then h - y else math.floor(remaining * frac)
		curtainBlock(m, base, w, d, y, y + th, spec, rng)
		y += th
		remaining = h - y
		if t < tiers then
			-- 셋백 테라스 (LED 테두리)
			if spec.terraceLed ~= false then
				Kit.box(m, base * CFrame.new(0, y + 0.7, 0), Vector3.new(w + 1, 1.3, d + 1), spec.ledColor or P.LedGold, Enum.Material.Neon, { name = "Led", glow = true, collide = false })
			end
			w *= 0.78
			d *= 0.78
		end
	end
	return crown(m, base, w, d, h, spec, rng, false)
end

------------------------------------------------------------------------------------------------------
-- 원형 타워
------------------------------------------------------------------------------------------------------
local function roundTower(m: Model, spec: TowerSpec, rng: Random): number
	local base = spec.cf
	local dia = math.min(spec.w, spec.d)
	local h = spec.h
	local floorH = spec.floorH or Config.Real.OfficeFloor
	local glass = spec.glass or P.GlassBlue
	local lit = spec.lit or LIT_OFFICE
	local inset = 1.6
	local lobbyH = math.min(20, h * 0.06)
	Kit.cylAlongY(m, base * CFrame.new(0, lobbyH / 2, 0), lobbyH, dia - 4, spec.lobbyColor or P.WindowWarmDim, Enum.Material.Neon, { name = "Lobby", glow = true })
	litCore(m, base, dia - inset * 2, dia - inset * 2, lobbyH, h, floorH, rng, lit, spec.litChance or 0.7, true, P.WindowOff)
	local slabH = floorH * 0.42
	local n = math.floor((h - lobbyH) / floorH)
	for i = 0, n - 1 do
		Kit.cylAlongY(m, base * CFrame.new(0, lobbyH + i * floorH + slabH / 2, 0), slabH, dia, glass, Enum.Material.Glass, { name = "Slab", reflectance = 0.2, shadow = false, collide = i == 0 })
	end
	-- 세로 핀 4개(관통): 원형에서도 리듬감
	local frame = spec.frame or P.Mullion
	for k = 0, 3 do
		local a = k * math.pi / 4
		Kit.box(m, base * CFrame.Angles(0, a, 0) * CFrame.new(0, lobbyH + (h - lobbyH) / 2, 0), Vector3.new(1.3, h - lobbyH, dia + 1), frame, Enum.Material.Metal, { name = "Fin", collide = false, query = false, shadow = false })
	end
	Kit.cylAlongY(m, base * CFrame.new(0, (h + lobbyH) / 2, 0), h - lobbyH, dia - inset * 2, P.WindowOff, Enum.Material.SmoothPlastic, { name = "Collision", transparency = 1, shadow = false })
	return crown(m, base, dia, dia, h, spec, rng, true)
end

------------------------------------------------------------------------------------------------------
-- 한국형 판상 아파트 (발코니 격자 + 측벽 동 번호)
------------------------------------------------------------------------------------------------------
local function apartment(m: Model, spec: TowerSpec, rng: Random): number
	local base = spec.cf
	local w, d, h = spec.w, spec.d, spec.h
	local floorH = spec.floorH or Config.Real.HomeFloor
	local unit = spec.bay or 15 -- 세대 폭 4.5 m
	local wall = spec.glass or P.ConcreteLight
	local lit = spec.lit or LIT_HOME
	local litChance = spec.litChance or 0.55
	local inset = 1.8
	local pilotis = floorH * 1.2 -- 필로티(1층 비움)
	-- 필로티 기둥 + 1층 로비 불빛
	Kit.box(m, base * CFrame.new(0, pilotis / 2, 0), Vector3.new(w * 0.3, pilotis, d - 6), spec.lobbyColor or P.WindowWarmDim, Enum.Material.Neon, { name = "Lobby", glow = true })
	for _, sx in { -0.42, -0.14, 0.14, 0.42 } do
		Kit.box(m, base * CFrame.new(sx * w, pilotis / 2, 0), Vector3.new(3.4, pilotis, d - 3), wall, Enum.Material.Concrete, { name = "Pilotis" })
	end
	-- 조명 코어 (긴 면만 보이도록 끝벽이 덮음)
	litCore(m, base, w - 4, d - inset * 2, pilotis, h, floorH, rng, lit, litChance, false, Color3.fromRGB(44, 46, 54))
	-- 층 슬래브 (발코니 난간 띠: 콘크리트)
	local slabH = floorH * 0.38
	local n = math.floor((h - pilotis) / floorH)
	for i = 0, n do
		local yb = pilotis + i * floorH
		if yb + slabH > h + 0.01 then
			break
		end
		Kit.box(m, base * CFrame.new(0, yb + slabH / 2, 0), Vector3.new(w, slabH, d), wall, Enum.Material.Concrete, { name = "Slab", shadow = false, collide = i == 0 })
	end
	-- 세대 벽(관통 핀)
	local nu = math.max(2, math.floor(w / unit))
	for i = 1, nu - 1 do
		local x = -w / 2 + i * (w / nu)
		Kit.box(m, base * CFrame.new(x, pilotis + (h - pilotis) / 2, 0), Vector3.new(1.5, h - pilotis, d + 1), wall, Enum.Material.Concrete, { name = "Wall", collide = false, query = false, shadow = false })
	end
	-- 측벽(끝벽): 두꺼운 콘크리트 + 슈퍼그래픽 띠 + 동 번호
	local endW = 2.6
	for _, sx in { -1, 1 } do
		local e = Kit.box(m, base * CFrame.new(sx * (w / 2 - endW / 2 + 0.5), (h + pilotis) / 2, 0), Vector3.new(endW, h - pilotis, d + 0.7), wall, Enum.Material.Concrete, { name = "EndWall" })
		if spec.accent then
			Kit.box(m, base * CFrame.new(sx * (w / 2 + 0.95), h * 0.55, d * 0.18), Vector3.new(0.5, h * 0.6, d * 0.22), spec.accent, Enum.Material.SmoothPlastic, { name = "Accent", collide = false, shadow = false })
		end
		if spec.label and sx == 1 then
			local sign = Kit.box(m, base * CFrame.new(w / 2 + 0.95, h - floorH * 2.2, -d * 0.1), Vector3.new(0.3, floorH * 2.2, d * 0.62), wall, Enum.Material.SmoothPlastic, { name = "NumberPlate", collide = false, shadow = false, transparency = 1 })
			Kit.label(sign, Enum.NormalId.Right, spec.label, { color = Color3.fromRGB(250, 244, 230), glow = true, pixelsPerStud = 6, maxDistance = 3000 })
		end
		local _ = e
	end
	-- 꺼진 세대 패치(관통)
	local cells = n * nu
	local nPatch = math.clamp(math.floor(cells * (1 - litChance) / 3), 0, 30)
	for _ = 1, nPatch do
		local fl = rng:NextInteger(0, math.max(0, n - 1))
		local nb = rng:NextInteger(1, 2)
		local i0 = rng:NextInteger(0, math.max(0, nu - nb))
		local bw = nb * (w / nu) - 1.5
		local x = -w / 2 + (i0 + nb / 2) * (w / nu)
		local hh = floorH - slabH
		local yc = pilotis + fl * floorH + slabH + hh / 2
		if yc + hh / 2 <= h then
			Kit.box(m, base * CFrame.new(x, yc, 0), Vector3.new(bw, hh, d - inset * 2 + 2), Color3.fromRGB(46, 48, 56), Enum.Material.SmoothPlastic, { name = "Off", collide = false, query = false, shadow = false })
		end
	end
	-- 충돌 몸체
	Kit.box(m, base * CFrame.new(0, (h + pilotis) / 2, 0), Vector3.new(w - 4, h - pilotis, d - inset * 2), wall, Enum.Material.SmoothPlastic, { name = "Collision", transparency = 1, shadow = false })
	-- 옥상: 엘리베이터 탑 + (선택) 왕관 프레임
	if spec.crown == "frame" or spec.crown == "led" then
		return crown(m, base, w, d, h, spec, rng, false)
	end
	Kit.box(m, base * CFrame.new(0, h + 0.8, 0), Vector3.new(w, 1.6, d), P.ConcreteGrey, Enum.Material.Concrete, { name = "Roof" })
	Kit.box(m, base * CFrame.new(rng:NextNumber(-0.25, 0.25) * w, h + 7, 0), Vector3.new(14, 12, d * 0.7), wall, Enum.Material.Concrete, { name = "ElevatorHouse" })
	return h + 13
end

------------------------------------------------------------------------------------------------------
-- 중경 LOD: 몸체 + 링 밴드 몇 개 (3~8 파트)
------------------------------------------------------------------------------------------------------
local BODY_MID = { P.ConcreteDark, P.GlassDeep, P.ConcreteGrey, P.GlassTeal, P.GlassBronze, Color3.fromRGB(70, 74, 84) }

local function mid(m: Model, spec: TowerSpec, rng: Random): number
	local base = spec.cf
	local w, d, h = spec.w, spec.d, spec.h
	local body = spec.glass or pick(rng, BODY_MID)
	Kit.box(m, base * CFrame.new(0, h / 2, 0), Vector3.new(w, h, d), body, if rng:NextNumber() < 0.5 then Enum.Material.Concrete else Enum.Material.Glass, { name = "Body", collide = spec.collide ~= false, reflectance = 0.05 })
	local lit = spec.lit or LIT_HOME
	local nb = math.clamp(math.floor(h / 36), 1, 6)
	for _ = 1, nb do
		if rng:NextNumber() < (spec.litChance or 0.75) then
			local bh = rng:NextNumber(2.6, 7.5)
			local y = rng:NextNumber(7, math.max(8, h - 7))
			local c = jitter(rng, pick(rng, lit), 0.12) :: Color3
			c = c:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.45))
			Kit.box(m, base * CFrame.new(0, y, 0), Vector3.new(w + 1, bh, d + 1), c, Enum.Material.Neon, { name = "Band", glow = true, collide = false, query = false, dayColor = body })
		end
	end
	if spec.crown == "led" then
		Kit.box(m, base * CFrame.new(0, h + 0.7, 0), Vector3.new(w + 1.3, 1.3, d + 1.3), spec.ledColor or P.LedGold, Enum.Material.Neon, { name = "Led", glow = true, collide = false })
	end
	if (spec.beacon == nil and h >= 330) or spec.beacon then
		Kit.beacon(m, (base * CFrame.new(0, h + 3.4, 0)).Position, 4)
	end
	return h
end

------------------------------------------------------------------------------------------------------
-- 원경 LOD: 몸체 1개 + (확률) 밴드 1개
------------------------------------------------------------------------------------------------------
local function far(m: Model, spec: TowerSpec, rng: Random): number
	local base = spec.cf
	local w, d, h = spec.w, spec.d, spec.h
	local body = spec.glass or pick(rng, BODY_MID)
	Kit.box(m, base * CFrame.new(0, h / 2, 0), Vector3.new(w, h, d), body, Enum.Material.Concrete, { name = "Body", collide = false, shadow = false })
	if rng:NextNumber() < (spec.litChance or 0.6) then
		local c = jitter(rng, pick(rng, spec.lit or LIT_HOME), 0.15):Lerp(Color3.new(0, 0, 0), rng:NextNumber(0.35, 0.7))
		local bh = math.max(3.4, h * rng:NextNumber(0.1, 0.3))
		Kit.box(m, base * CFrame.new(0, rng:NextNumber(bh / 2 + 3, math.max(bh / 2 + 3, h - bh / 2 - 3)), 0), Vector3.new(w + 1.3, bh, d + 1.3), c, Enum.Material.Neon, { name = "Band", glow = true, collide = false, query = false, dayColor = body, transparency = 0.15 })
	end
	if spec.beacon then
		Kit.beacon(m, (base * CFrame.new(0, h + 3.4, 0)).Position, 5)
	end
	return h
end

------------------------------------------------------------------------------------------------------
-- 진입점
------------------------------------------------------------------------------------------------------
function Facade.tower(parent: Instance, spec: TowerSpec): Model
	local m = Instance.new("Model")
	m.Name = spec.name or ("Bldg_" .. spec.style)
	local rng = spec.rng
	local top
	if spec.style == "curtain" then
		top = curtain(m, spec, rng)
	elseif spec.style == "round" then
		top = roundTower(m, spec, rng)
	elseif spec.style == "apartment" then
		top = apartment(m, spec, rng)
	elseif spec.style == "mid" then
		top = mid(m, spec, rng)
	else
		top = far(m, spec, rng)
	end
	m:SetAttribute("Height", top)
	m:SetAttribute("Style", spec.style)
	-- 강변 건물: 수면 반사 스트릭
	if spec.glint then
		local p = spec.cf.Position
		local lits = spec.lit or LIT_OFFICE
		local c = lits[(math.floor(math.abs(p.X * 3 + p.Z * 7)) % #lits) + 1] -- rng 를 쓰지 않음(글린트 유무가 배치를 바꾸지 않게)
		Kit.reflection(m, p.X, Config.FarBank.WaterEdge + 10, math.min(spec.w, spec.d) * 0.35, math.min(630, spec.h * 0.8), c, 0.72)
	end
	m.Parent = parent
	return m
end

return Facade
