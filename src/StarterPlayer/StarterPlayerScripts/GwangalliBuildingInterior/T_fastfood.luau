--!strict
-- GwangalliBuildingInterior/T_fastfood: 유형 (chicken burger snack) 실내.
--   치킨집 (치킨호프 · 옛날통닭 · 비비큐 같은 프랜차이즈), 버거 (수제버거 · SUBWAY · 타코), 분식 (분식집 · 떡볶이 · 오뎅바)
--   style(V) -> S  Common 에 줄 공통 마감 스타일 (Common.luau 머리말의 S 필드)
--   build(K, V, S) 유형별 디테일 (메뉴판 · 진열 · 주방 · 간판 · 소품 · 상호작용)
--
-- 배치 원칙
--   * 바닥 소품: floorSpot = 벽을 따라 후보 자리를 훑으며 K:spot (keep · 기존 가구 · 새 소품) + 벽 부착물 · 천장 행거 ·
--     간판 · 우리 금지 구역(주방 패스 앞, 키오스크 앞, 입구 -> 패스/키오스크/화장실 동선, NPC 주변)을 검사.
--   * 벽 장식: wallSpot (빈 벽 구간 - K.wallUsed 를 정확히 뺌; 벽돌 · 타일 마감은 장애물로 안 봄),
--     바닥 소품이 쓰는 벽 구간도 K.wallUsed 에 기록해 겹치지 않게. 좁으면 wallSpotFit 으로 작은 판.
--   * 맵 게임플레이 파트 (KitchenPass · PassLedge · OrderKiosk/KioskScreen · Fryer/Hood · 벤치 Seat · 분식 조리대 음식):
--     같은 자리 · 같은 범위 덮개 + 원본 숨김 (K:free). 의자 · 테이블 · 카운터는 Common 이 S 스타일로.
--   * Sign_* 파트는 절대 건드리지 않음 (R10) — 뒤 액자 · 아래 LED · 위 스포트만.
--   * 상호작용은 프롬프트가 되는 자리(Interact.canPrompt: 서버 앵커 6.5 스터드 밖)를 먼저 차지하도록 먼저 놓음:
--     치킨 = TV 채널 · 네온 켜기 · 잔 냉동고 문 · 음료 냉장고 문, 버거 = TV · 네온 · 주크박스 곡 · 냉장고 문,
--     분식 = 선풍기 켜기 · 순대 찜기 뚜껑 · TV, 오뎅바 = 네온 · 사케 냉장고 문. 자리가 없으면 화면은 저절로 순환.

local Look = require(script.Parent:WaitForChild("Look"))
local Props = require(script.Parent:WaitForChild("Props"))
local Interact = require(script.Parent:WaitForChild("Interact"))
local Common = require(script.Parent:WaitForChild("Common"))
local Scan = require(script.Parent:WaitForChild("Scan"))

local TweenService = game:GetService("TweenService")

local T = {}
T.types = { "chicken", "burger", "snack" }

local CF, V3 = CFrame.new, Vector3.new
local ANG = CFrame.Angles
local PI = math.pi
local M = Enum.Material
local F = Enum.Font
local L = Look
local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

-- 작은 도구 ------------------------------------------------------------------------------------------
local function hash(s: string): number
	local h = 7
	for i = 1, #s do
		h = (h * 31 + string.byte(s, i)) % 2147483629
	end
	return h
end

local function mkRand(seed: number): (number?, number?) -> number
	local s = seed % 2147483646 + 1
	return function(a: number?, b: number?): number
		s = (s * 16807) % 2147483647
		local f = (s - 1) / 2147483646
		if a == nil then
			return f
		end
		if b == nil then
			return math.floor(f * (a :: number)) + 1
		end
		return (a :: number) + ((b :: number) - (a :: number)) * f
	end
end

local function pl(c: Color3, m: Enum.Material?, extra: any?): any
	local t: any = { c = c, m = m or M.SmoothPlastic }
	if extra then
		for k, v in extra do
			t[k] = v
		end
	end
	return t
end
local function dark(c: Color3, f: number): Color3
	return c:Lerp(BLACK, f)
end
local function light(c: Color3, f: number): Color3
	return c:Lerp(WHITE, f)
end
local function neon(c: Color3): any
	return { c = c, m = M.Neon }
end

local function ov(a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3, e: number): boolean
	return a0.X < b1.X - e and a1.X > b0.X + e and a0.Y < b1.Y - e and a1.Y > b0.Y + e and a0.Z < b1.Z - e and a1.Z > b0.Z + e
end

local function laabb(lcf: CFrame, size: Vector3): (Vector3, Vector3)
	local h = size / 2
	local ex = math.abs(lcf.XVector.X) * h.X + math.abs(lcf.YVector.X) * h.Y + math.abs(lcf.ZVector.X) * h.Z
	local ey = math.abs(lcf.XVector.Y) * h.X + math.abs(lcf.YVector.Y) * h.Y + math.abs(lcf.ZVector.Y) * h.Z
	local ez = math.abs(lcf.XVector.Z) * h.X + math.abs(lcf.YVector.Z) * h.Y + math.abs(lcf.ZVector.Z) * h.Z
	local p = lcf.Position
	return V3(p.X - ex, p.Y - ey, p.Z - ez), V3(p.X + ex, p.Y + ey, p.Z + ez)
end

-- 맵 간판 글자 모으기 (메뉴판 가격 · 상호를 우리 포스터에 똑같이 쓰려고). 읽기만.
local function signTexts(V: any): string
	local out = { V.name or "" }
	for _, r in V.parts do
		if string.sub(r.name, 1, 5) == "Sign_" then
			table.insert(out, string.sub(r.name, 6))
			pcall(function()
				for _, d in r.part:GetDescendants() do
					if d:IsA("TextLabel") then
						table.insert(out, (d :: TextLabel).Text)
					end
				end
			end)
		end
	end
	return table.concat(out, " | ")
end

-- "후라이드 20,000 · 양념 21,000" 에서 품목 다음 가격 (가운데 점 · 줄바꿈을 넘지 않음)
local function priceIn(txt: string, item: string, default: string): string
	local init = 1
	for _ = 1, 12 do
		local i, j = string.find(txt, item, init, true)
		if not i or not j then
			return default
		end
		local rest = string.sub(txt, j + 1, j + 30)
		local a, _, num = string.find(rest, "(%d[%d,]*%d)")
		if a then
			local between = string.sub(rest, 1, a - 1)
			if not string.find(between, "·", 1, true) and not string.find(between, "|", 1, true) and not string.find(between, "\n", 1, true) then
				return num
			end
		end
		init = j + 1
	end
	return default
end

local function has(s: string, w: string): boolean
	return string.find(s, w, 1, true) ~= nil
end

-- 세부 유형 -----------------------------------------------------------------------------------------
local function subKind(V: any, signs: string?): string
	local n = (V.name or "") .. " " .. (if V.model then V.model.Name else "")
	local up = string.upper(n)
	local m = V.menu
	local s = signs or ""
	if V.type == "chicken" or m == "chicken" or m == "tongdak" then
		if m == "tongdak" or has(n, "통닭") then
			return "tongdak"
		end
		return "chicken"
	elseif V.type == "burger" then
		if m == "sub" or has(up, "SUBWAY") or has(n, "써브웨이") then
			return "sub"
		end
		if m == "taco" or has(n, "타코") or has(up, "TACO") then
			return "taco"
		end
		-- 맵에서 버거로 분류됐지만 실제 간판 · 메뉴가 치킨인 가게 (예: BBQ 민락점)
		if (has(s, "치킨") or has(s, "후라이드")) and not has(s, "버거") then
			return "chicken"
		end
		return "burger"
	else
		if m == "odeng" or has(n, "오뎅") or has(n, "어묵") then
			return "odeng"
		end
		return "bunsik"
	end
end
T.subKind = subKind

-- 팔레트 ------------------------------------------------------------------------------------------
local CHICKEN_PAL = {
	-- 노랑 · 빨강 (호프형 치킨집)
	{ key = "yellow", wall = rgb(244, 206, 96), wall2 = rgb(250, 240, 222), accent = rgb(204, 34, 30), ink = rgb(40, 28, 20), gold = rgb(255, 196, 40), wood = L.oak, lowerL = L.walnut, floor = rgb(150, 112, 78), floorM = M.WoodPlanks, chair = "padded", seat = L.leatherBrown, table = L.oak },
	-- 화이트 · 레드 (깔끔한 프랜차이즈)
	{ key = "red", wall = rgb(238, 234, 228), wall2 = rgb(200, 30, 38), accent = rgb(200, 30, 38), ink = rgb(30, 30, 30), gold = rgb(255, 210, 60), wood = L.lightOak, lowerL = L.white, floor = rgb(196, 194, 190), floorM = M.CeramicTiles, chair = "shell", seat = L.plywood, table = L.lightOak },
	-- 블랙 · 골드 (프리미엄 치킨 & 펍)
	{ key = "black", wall = rgb(92, 80, 70), wall2 = rgb(70, 62, 56), accent = rgb(212, 168, 74), ink = rgb(246, 236, 210), gold = rgb(228, 186, 90), wood = L.walnut, lowerL = L.darkWood, floor = rgb(84, 80, 76), floorM = M.Slate, chair = "padded", seat = L.leatherBlack, table = L.walnut },
}
local TONGDAK_PAL = { key = "tongdak", wall = rgb(246, 226, 168), wall2 = rgb(252, 244, 226), accent = rgb(196, 40, 30), ink = rgb(70, 40, 20), gold = rgb(250, 190, 40), wood = L.pine, lowerL = L.pine, floor = rgb(160, 120, 84), floorM = M.WoodPlanks, chair = "bentwood", seat = L.walnut, table = L.pine }

local BURGER_PAL = {
	-- 아메리칸 다이너 (빨강 · 크림 · 체커)
	{ key = "diner", wall = rgb(166, 30, 34), wall2 = rgb(246, 240, 226), accent = rgb(220, 36, 40), ink = rgb(24, 24, 26), gold = rgb(255, 196, 48), checker = true, tile = rgb(246, 246, 242), neonC = rgb(255, 70, 90), chair = "diner", seat = L.leatherRed, table = L.marbleWhite },
	-- 인더스트리얼 (블랙 · 콘크리트 · 오렌지)
	{ key = "industrial", wall = rgb(112, 112, 114), wall2 = rgb(160, 158, 154), accent = rgb(244, 120, 32), ink = rgb(240, 236, 228), gold = rgb(255, 170, 40), checker = false, tile = rgb(238, 238, 234), neonC = rgb(255, 150, 50), chair = "shell", seat = L.plywood, table = L.walnut },
	-- 브루클린 (벽돌 · 블랙 · 머스터드)
	{ key = "brick", wall = rgb(150, 82, 62), wall2 = rgb(36, 36, 38), accent = rgb(236, 176, 40), ink = rgb(250, 244, 230), gold = rgb(236, 176, 40), checker = false, brick = true, tile = rgb(30, 30, 32), neonC = rgb(255, 200, 70), chair = "padded", seat = L.leatherBlack, table = L.oak },
}
local SUB_PAL = { key = "sub", wall = rgb(0, 132, 61), wall2 = rgb(244, 240, 230), accent = rgb(255, 194, 14), ink = rgb(255, 255, 255), gold = rgb(255, 194, 14), green = rgb(0, 132, 61), chair = "shell", seat = L.lightOak, table = L.lightOak }
local TACO_PAL = { key = "taco", wall = rgb(236, 110, 60), wall2 = rgb(250, 226, 160), accent = rgb(30, 140, 120), ink = rgb(40, 24, 20), gold = rgb(255, 200, 60), checker = false, tile = rgb(230, 120, 70), neonC = rgb(80, 230, 200), chair = "shell", seat = L.plywood, table = L.pine }

local SNACK_PAL = {
	-- 빨강 · 노랑 분식 (떡볶이집)
	{ key = "red", wall = rgb(250, 238, 214), wall2 = rgb(210, 40, 36), accent = rgb(214, 38, 34), ink = rgb(30, 26, 24), gold = rgb(255, 200, 40), tile = rgb(240, 240, 236), tileAcc = rgb(206, 44, 40), chair = "cushion", seat = L.leatherRed, table = L.of(232, 230, 222) },
	-- 민트 · 화이트 (요즘 분식 프랜차이즈)
	{ key = "mint", wall = rgb(236, 246, 240), wall2 = rgb(40, 160, 130), accent = rgb(236, 90, 40), ink = rgb(24, 40, 36), gold = rgb(255, 196, 60), tile = rgb(244, 244, 240), tileAcc = rgb(60, 170, 140), chair = "cushion", seat = L.of(60, 150, 124, M.Leather), table = L.of(244, 242, 236) },
}
local ODENG_PAL = { key = "odeng", wall = rgb(120, 70, 40), wall2 = rgb(40, 30, 26), accent = rgb(196, 40, 36), ink = rgb(250, 238, 214), gold = rgb(236, 196, 120), wood = L.of(150, 106, 66, M.Wood) }

-- style ----------------------------------------------------------------------------------------------
function T.style(V: any): any
	local signs = signTexts(V)
	local sk = subKind(V, signs)
	local seed = hash(V.key or V.name or "x")
	local gw = V.kind == "gwshop"
	local S: any
	if sk == "chicken" or sk == "tongdak" then
		local P = if sk == "tongdak" then TONGDAK_PAL else CHICKEN_PAL[seed % #CHICKEN_PAL + 1]
		if has(signs, "비비큐") or has(string.upper(V.name or ""), "BBQ") then
			P = CHICKEN_PAL[2]
		end
		S = {
			chair = { style = P.chair, frame = if P.chair == "bentwood" then L.walnut else L.blackMetal, seat = P.seat, back = P.seat },
			stool = { style = "cushion", seat = L.leatherRed },
			table = { top = P.table, base = L.blackMetal, thick = 0.16 },
			counter = { front = "wood", frontL = P.wood, topL = L.of(60, 58, 56, M.Granite), led = rgb(255, 200, 140) },
			ceiling = { grid = false, skin = if P.key == "black" then L.of(120, 88, 60, M.WoodPlanks) else L.of(244, 240, 232, M.Plaster) },
			lower = { kind = if P.key == "red" then "tile" else "louver", h = 3.3, look = if P.key == "red" then L.tileWhite else P.lowerL, back = L.charcoal, walls = { "left", "right", "back" }, tw = 0.8, th = 0.4 },
			floor = { look = L.of(P.floor.R * 255, P.floor.G * 255, P.floor.B * 255, P.floorM), tile = if P.floorM == M.WoodPlanks then 0 else 2.0, grout = L.of(120, 116, 110) },
			base = L.walnut,
			pendant = { shade = "dome", look = L.with(L.blackMetal, { c = dark(P.accent, 0.2) }) },
			lights = { kind = "downlight", n = if P.key == "black" then 6 else 4, color = L.warmLight },
			mat = { look = L.of(60, 40, 30, M.Fabric), text = "어서 오세요" },
			plants = { "snake", "olive" },
		}
		S.pal = P
	elseif sk == "sub" then
		local P = SUB_PAL
		S = {
			chair = { style = "shell", frame = L.blackMetal, seat = L.of(0, 120, 56, M.Plastic), back = L.of(0, 120, 56, M.Plastic) },
			stool = { style = "bar", frame = L.blackMetal, seat = L.of(0, 110, 52, M.Leather) },
			table = { top = L.lightOak, base = L.blackMetal, barStyle = "steel" },
			counter = { front = "wood", frontL = L.lightOak, topL = L.of(70, 72, 74, M.Granite), led = rgb(255, 230, 170) },
			ceiling = { grid = true, tile = 2.0 },
			lower = { kind = "louver", h = 3.4, look = L.lightOak, back = L.of(0, 110, 52), walls = { "left", "right", "back" }, pitch = 0.5 },
			floor = { look = L.of(196, 192, 184, M.CeramicTiles), tile = 2.0, grout = L.of(150, 146, 140) },
			base = L.of(0, 100, 50),
			lights = { kind = "panel", n = 4 },
			mat = { look = L.of(0, 96, 46, M.Fabric), text = "SUBWAY" },
			plants = { "snake", "olive" },
		}
		S.pal = P
	elseif sk == "burger" or sk == "taco" then
		local P = if sk == "taco" then TACO_PAL else BURGER_PAL[seed % #BURGER_PAL + 1]
		S = {
			chair = { style = P.chair, frame = if P.chair == "diner" then L.chrome else L.blackMetal, seat = P.seat, back = P.seat },
			stool = { style = "bar", frame = L.chrome, seat = P.seat },
			table = { top = P.table, base = if P.chair == "diner" then L.chrome else L.blackMetal, edge = if P.chair == "diner" then L.chrome else nil },
			counter = { front = "tile", frontL = L.tileWhite, topL = L.of(36, 36, 38, M.Granite), led = rgb(255, 210, 160) },
			ceiling = { grid = false, skin = if P.key == "diner" then L.of(244, 240, 230, M.Plaster) else L.of(52, 52, 54, M.Concrete) },
			lower = { kind = "tile", h = 3.6, look = L.of(P.tile.R * 255, P.tile.G * 255, P.tile.B * 255, M.CeramicTiles), grout = L.of(170, 168, 162), walls = { "left", "right", "back" }, tw = 0.66, th = 0.33 },
			floor = if P.checker then false else { look = L.of(120, 118, 114, M.Slate), tile = 2.4, grout = L.of(90, 88, 86) },
			base = L.black,
			pendant = { shade = "bulb" },
			lights = { kind = "downlight", n = 4, color = L.warmLight },
			mat = { look = L.of(30, 30, 30, M.Fabric), text = "WELCOME" },
			plants = { "snake", "bamboo" },
		}
		S.pal = P
	elseif sk == "odeng" then
		local P = ODENG_PAL
		S = {
			chair = false, -- 벤치 · 의자는 아래에서 직접 (벤치형 Seat 를 의자로 덮지 않게)
			stool = { style = "wood", frame = L.walnut, seat = L.walnut },
			table = { top = L.of(150, 106, 66, M.Wood), base = L.blackMetal },
			counter = { front = "wood", frontL = L.of(120, 80, 50, M.Wood), topL = L.of(176, 132, 88, M.Wood), kickL = L.black, led = rgb(255, 190, 120) },
			ceiling = { grid = false, skin = L.of(44, 34, 28, M.Wood) },
			lower = { kind = "louver", h = 3.4, look = L.of(110, 74, 48, M.Wood), back = L.of(40, 30, 26), walls = { "left", "right" }, pitch = 0.42 },
			floor = false,
			base = L.darkWood,
			pendant = { shade = "drum", look = L.of(236, 226, 200, M.Fabric) },
			lights = { kind = "none" },
			mat = { look = L.of(40, 30, 24, M.Fabric), text = "어서 오세요" },
			plants = { "bamboo", "snake" },
		}
		S.pal = P
	else
		local P = if gw then SNACK_PAL[1] else SNACK_PAL[seed % #SNACK_PAL + 1]
		S = {
			chair = { style = "padded", frame = L.chrome, seat = P.seat, back = P.seat },
			stool = { style = "cushion", frame = L.chrome, seat = P.seat },
			table = { top = P.table, base = L.chrome, edge = L.steel, thick = 0.12 },
			counter = { front = "tile", frontL = L.of(P.tileAcc.R * 255, P.tileAcc.G * 255, P.tileAcc.B * 255, M.CeramicTiles), topL = L.steel, led = false },
			ceiling = { grid = true, tile = 2.0 },
			lower = { kind = "tile", h = 3.6, look = L.of(P.tile.R * 255, P.tile.G * 255, P.tile.B * 255, M.CeramicTiles), grout = L.of(188, 186, 180), walls = { "left", "right", "back" }, tw = 0.6, th = 0.6 },
			floor = { look = L.of(170, 166, 158, M.Granite), tile = 2.0, grout = L.of(130, 126, 120) },
			base = L.of(P.tileAcc.R * 255, P.tileAcc.G * 255, P.tileAcc.B * 255),
			lights = { kind = "panel", n = 4 },
			mat = { look = L.of(150, 30, 30, M.Fabric), text = "어서 오세요" },
			plants = { "snake" },
		}
		S.pal = P
	end
	if gw then
		-- GwShop 은 맵이 이미 마감한 곳 위주: 벽 아랫단 · 천장 그리드 · 현관 매트는 맵 것 그대로
		S.lower = false
		if V:has("TBar") > 0 then
			S.ceiling = { grid = true }
		end
		if V:has("DoorMat") > 0 then
			S.mat = false
		end
	end
	S.sk = sk
	S.signs = signs
	-- 벽시계는 우리가 (Common 시계는 맵 Sign_ 메뉴판과 겹칠 때가 있어서: 간판을 피하는 wallSpot 으로 따로)
	S.clock = false
	return S
end

-- 빌드 문맥 ----------------------------------------------------------------------------------------
local function ctxNew(K: any, V: any, S: any): any
	local signs = S.signs or signTexts(V)
	local ctx: any = {
		K = K,
		V = V,
		S = S,
		sk = S.sk or subKind(V, signs),
		pal = S.pal or CHICKEN_PAL[1],
		signs = signs,
		rand = mkRand(hash(V.key or V.name or "x")),
		no = {},
		wallSigns = {},
		low = K.detail == "low",
		high = K.detail == "high",
		gw = V.kind == "gwshop",
		stats = {},
		toggles = 0,
	}
	for _, r in V.parts do
		if string.sub(r.name, 1, 5) == "Sign_" and r.size.Y < 6 then
			table.insert(ctx.wallSigns, r)
		end
	end
	return ctx
end

-- 긴 자리 찾기 루프 중 프레임 양보 (Kit:tick 과 같은 시간 분할)
local function yieldMaybe(K: any)
	if K.sliceT and os.clock() - K.sliceT > (K.slice or 0.0025) then
		task.wait()
		K.sliceT = os.clock()
	end
end

local function addNo(ctx: any, mn: Vector3, mx: Vector3)
	table.insert(ctx.no, { min = mn, max = mx })
end

-- a -> b (바닥 xz) 폭 w 동선을 금지 구역으로
local function corridor(ctx: any, a: Vector3, b: Vector3, w: number)
	local d = V3(b.X - a.X, 0, b.Z - a.Z)
	local len = d.Magnitude
	local n = math.max(1, math.ceil(len / 1.2))
	for i = 0, n do
		local p = a:Lerp(b, i / n)
		addNo(ctx, V3(p.X - w / 2, 0.05, p.Z - w / 2), V3(p.X + w / 2, 7, p.Z + w / 2))
	end
end

local function wallBusy(K: any, wn: string, a: number, b: number, y0: number, y1: number): boolean
	for _, u in K.wallUsed or {} do
		if u.w == wn and u.a < b and u.b > a and u.y0 < y1 and u.y1 > y0 then
			return true
		end
	end
	return false
end

local function markWall(K: any, wn: string, a: number, b: number, y0: number, y1: number)
	K.wallUsed = K.wallUsed or {}
	table.insert(K.wallUsed, { w = wn, a = a, b = b, y0 = y0, y1 = y1 })
end

local function blockedBy(ctx: any, mn: Vector3, mx: Vector3): boolean
	for _, z in ctx.no do
		if ov(mn, mx, z.min, z.max, 0.02) then
			return true
		end
	end
	local V = ctx.V
	for _, list in { V.wallItems, V.hang, ctx.wallSigns } do
		for _, r in list do
			if ov(mn, mx, r.min, r.max, 0.02) then
				return true
			end
		end
	end
	return false
end

-- 옆벽의 뒤쪽 / 앞쪽 끝 u
local function uEnd(V: any, wn: string, which: string): number
	local wl = V.walls[wn]
	if wn == "left" then
		return if which == "back" then wl.b else wl.a
	elseif wn == "right" then
		return if which == "back" then wl.a else wl.b
	elseif wn == "back" then
		return if which == "left" then wl.a else wl.b
	end
	return 0
end

-- 벽에 붙여 세우는 바닥 소품 자리. o = { walls, w, h, d, pref = { [wall] = u | "back" | "front" | "left" | "right" | "mid" },
--   front (앞 여유, 기본 0.9), prompt (true = 프롬프트 가능한 자리 먼저), kind, step }
-- 반환 pcf (+Z = 방 쪽 = 소품 정면), wall, u
local function floorSpot(ctx: any, o: any): (CFrame?, string?, number?)
	local K, V = ctx.K, ctx.V
	-- 파트 예산: 반쯤 지어진 소품이 남지 않게 여유가 없으면 아예 안 놓음
	if #K.parts > K.maxParts - (o.cost or 160) then
		return nil, nil, nil
	end
	local w, h, d = o.w, o.h, o.d
	local gap = o.gap or 0.06
	local front = o.front or 0.9
	local cands = {}
	for wi, wn in o.walls do
		local wl = V.walls[wn]
		if wl then
			local pref = o.pref and o.pref[wn]
			local target: number
			if type(pref) == "number" then
				target = pref
			elseif pref == "back" or pref == "front" or pref == "left" or pref == "right" then
				target = uEnd(V, wn, pref)
			else
				target = (wl.a + wl.b) / 2
			end
			local lo, hi = wl.a + w / 2 + 0.1, wl.b - w / 2 - 0.1
			local step = o.step or 0.4
			local u = lo
			while u <= hi + 1e-6 do
				table.insert(cands, { wn = wn, u = u, s = wi * 1000 + math.abs(u - target) })
				u += step
			end
		end
	end
	table.sort(cands, function(a, b)
		return a.s < b.s
	end)
	for pass = 1, (if o.prompt then 2 else 1) do
		for _, c in cands do
			yieldMaybe(K)
			local pcf = V:wall(c.wn, c.u, 0, d / 2 + gap)
			local mn, mx = laabb(pcf * CF(0, h / 2, 0), V3(w, h, d))
			if wallBusy(K, c.wn, c.u - w / 2 - 0.05, c.u + w / 2 + 0.05, 0, h) or blockedBy(ctx, mn, mx) then
				continue
			end
			if pass == 1 and o.prompt then
				local any = false
				for _, px in { -w / 2 + 0.4, 0, w / 2 - 0.4 } do
					if Interact.canPrompt(K, (pcf * CF(px, 3, d / 2 + 0.2)).Position) then
						any = true
						break
					end
				end
				if not any then
					continue
				end
			end
			-- 앞 여유까지 포함해 예약 (소품 앞에 다른 소품이 막지 않게)
			if K:spot(pcf * CF(0, 0, front / 2), V3(w, h, d + front), 0, o.kind or "ff") then
				markWall(K, c.wn, c.u - w / 2, c.u + w / 2, 0, h + (o.above or 0))
				return pcf, c.wn, c.u
			end
		end
	end
	ctx.miss = (ctx.miss or "") .. string.format(" F%.1fx%.1f", w, d)
	return nil, nil, nil
end

-- 벽 빈 구간 (V:spans 와 같은 계산이지만 벽 마감재 — 벽돌 · 타일 · 걸레받이 — 는 장애물로 보지 않음)
local FINISH = { BrickWall = true, WallTiles = true, TileStripe = true, WainscotCap = true, Skirting = true, Baseboard = true, WallPanel = true, AccentWall = true }
local function spans(ctx: any, name: string, y0: number, y1: number, depth: number?): { { number } }
	local V = ctx.V
	local w = V.walls[name]
	if not w then
		return {}
	end
	local dep = depth or 1.0
	local cuts: { { number } } = {}
	local function cutBox(mn: Vector3, mx: Vector3, pad: number)
		if mx.Y < y0 or mn.Y > y1 then
			return
		end
		local umin, umax, dmin, dmax = math.huge, -math.huge, math.huge, -math.huge
		for _, x in { mn.X, mx.X } do
			for _, z in { mn.Z, mx.Z } do
				local u, d = V:wallCoord(name, V3(x, 0, z))
				umin = math.min(umin, u)
				umax = math.max(umax, u)
				dmin = math.min(dmin, d)
				dmax = math.max(dmax, d)
			end
		end
		if dmin > dep or dmax < 0.02 then
			return -- 벽에서 먼 것 · 벽 뒤(옆 가게 · 주방)에 있는 것은 상관없음
		end
		table.insert(cuts, { umin - pad, umax + pad })
	end
	for _, r in V.parts do
		if (not r.shell or r.door) and not FINISH[r.name] then
			cutBox(r.min, r.max, 0.25)
		elseif string.sub(r.name, 1, 5) == "Sign_" and r.size.Y < 6 then
			cutBox(r.min, r.max, 0.2)
		end
	end
	for _, k in V.keep do
		if k.kind ~= "table" and k.kind ~= "seat" then
			cutBox(k.min, k.max, 0)
		end
	end
	table.sort(cuts, function(a, b)
		return a[1] < b[1]
	end)
	local out = {}
	local cur = w.a + 0.3
	for _, c in cuts do
		if c[1] > cur then
			table.insert(out, { cur, math.min(c[1], w.b - 0.3) })
		end
		cur = math.max(cur, c[2])
	end
	if cur < w.b - 0.3 then
		table.insert(out, { cur, w.b - 0.3 })
	end
	local res = {}
	for _, s in out do
		if s[2] - s[1] > 0.6 then
			table.insert(res, s)
		end
	end
	return res
end

-- 벽 구간 [a, b] x [y0, y1] 이 비었나 (맵 물건 · 간판 · keep · K.wallUsed 모두)
local function spanFree(ctx: any, wn: string, a: number, b: number, y0: number, y1: number, ignoreUsed: boolean?): boolean
	if not ignoreUsed and wallBusy(ctx.K, wn, a, b, y0, y1) then
		return false
	end
	for _, sp in spans(ctx, wn, y0, y1, 1.0) do
		if sp[1] <= a + 0.01 and sp[2] >= b - 0.01 then
			return true
		end
	end
	return false
end

-- 벽 장식 자리: 빈 구간에서 K.wallUsed (Common · 우리 기록) 를 정확히 빼고 prefer 에 가장 가까운 곳.
-- (Common.wallSpot 은 한 구간이 둘로 갈릴 때 앞 조각을 뒤 기록과 다시 비교하지 않아 겹칠 수 있어 따로 둠)
local function wallSpot(ctx: any, walls: { string }, w: number, y0: number, y1: number, prefer: number?): (CFrame?, string?)
	local K, V = ctx.K, ctx.V
	if #K.parts > K.maxParts - 60 then
		return nil, nil
	end
	K.wallUsed = K.wallUsed or {}
	for _, wn in walls do
		local free = {}
		for _, s in spans(ctx, wn, y0, y1, 1.0) do
			table.insert(free, { s[1], s[2] })
		end
		for _, u in K.wallUsed do
			if u.w == wn and u.y1 > y0 and u.y0 < y1 then
				local nxt = {}
				for _, f in free do
					if u.b <= f[1] or u.a >= f[2] then
						table.insert(nxt, f)
					else
						if u.a > f[1] then
							table.insert(nxt, { f[1], u.a })
						end
						if u.b < f[2] then
							table.insert(nxt, { u.b, f[2] })
						end
					end
				end
				free = nxt
			end
		end
		local best, bd = nil, math.huge
		local target = prefer or 0
		for _, f in free do
			if f[2] - f[1] >= w then
				local u = math.clamp(target, f[1] + w / 2, f[2] - w / 2)
				local dd = math.abs(u - target)
				if dd < bd then
					best, bd = u, dd
				end
			end
		end
		if best then
			table.insert(K.wallUsed, { w = wn, a = best - w / 2 - 0.2, b = best + w / 2 + 0.2, y0 = y0, y1 = y1 })
			return V:wall(wn, best, (y0 + y1) / 2, 0.0), wn
		end
	end
	ctx.miss = (ctx.miss or "") .. string.format(" w%.1f@%.1f-%.1f", w, y0, y1)
	return nil, nil
end

-- 프롬프트를 둘 수 있는 벽 구간 (서버 앵커 6.5 밖): { { wall, a, b } } 긴 것부터
local function promptIntervals(ctx: any, walls: { string }): { any }
	local K, V = ctx.K, ctx.V
	local out = {}
	for _, wn in walls do
		local wl = V.walls[wn]
		if not wl then
			continue
		end
		local run0: number? = nil
		local u = wl.a + 0.3
		yieldMaybe(K)
		while u <= wl.b - 0.3 + 1e-6 do
			local p = V:wall(wn, u, 3, 0.4).Position
			local okp = Interact.canPrompt(K, p)
			if okp and not run0 then
				run0 = u
			elseif not okp and run0 then
				table.insert(out, { wn, run0, u - 0.25 })
				run0 = nil
			end
			u += 0.25
		end
		if run0 then
			table.insert(out, { wn, run0, wl.b - 0.3 })
		end
	end
	table.sort(out, function(a, b)
		return (a[3] - a[2]) > (b[3] - b[2])
	end)
	return out
end

-- 프롬프트 되는 벽 자리 먼저 (없으면 nil): 반환 dcf, wall
local function promptWallSpot(ctx: any, walls: { string }, w: number, y0: number, y1: number): (CFrame?, string?)
	local K = ctx.K
	for _, iv in promptIntervals(ctx, walls) do
		local mid = (iv[2] + iv[3]) / 2
		local dcf, wn = wallSpot(ctx, { iv[1] }, w, y0, y1, mid)
		if dcf then
			if Interact.canPrompt(K, dcf.Position) then
				return dcf, wn
			end
			-- 프롬프트는 안 되지만 자리는 이미 잡았으니 그대로 씀
			return dcf, wn
		end
	end
	return nil, nil
end

-- 프롬프트가 꼭 되는 벽 자리만 (안 되면 nil 이고 자리도 안 잡음)
-- edges = 프롬프트를 붙일 수 있는 부품의 가로 위치들 (가운데 기준, 예: TV 버튼 = ±(w/2-0.25)); 하나라도 되면 OK
local function promptSpotStrict(ctx: any, walls: { string }, w: number, y0: number, y1: number, edges: { number }?): (CFrame?, string?)
	local K = ctx.K
	for _, iv in promptIntervals(ctx, walls) do
		local mid = (iv[2] + iv[3]) / 2
		local missBefore = ctx.miss
		local dcf, wn = wallSpot(ctx, { iv[1] }, w, y0, y1, mid)
		if dcf then
			for _, ex in edges or { 0 } do
				if Interact.canPrompt(K, (dcf * CF(ex, 0, 0.4)).Position) then
					return dcf, wn
				end
			end
			table.remove(K.wallUsed, #K.wallUsed)
		end
		ctx.miss = missBefore
	end
	return nil, nil
end

-- 폭 후보를 차례로 (큰 것부터): 반환 dcf, 고른 폭
local function wallSpotFit(ctx: any, walls: { string }, ws: { number }, y0: number, y1: number, prefer: number?): (CFrame?, number)
	for _, w in ws do
		local d = wallSpot(ctx, walls, w, y0, y1, prefer)
		if d then
			return d, w
		end
	end
	return nil, 0
end

-- 2D 그림 (포스터 · 라이트박스 위 색 블록): items = { { "e"|"b", x, y, w, h, Color3, rot?, mat? } } (dcf 기준 스터드)
local function art(K: any, dcf: CFrame, items: { any }, z0: number?)
	local z = z0 or 0.004
	for i, it in items do
		local cf = dcf * CF(it[2], it[3], z + i * 0.004) * ANG(0, 0, it[7] or 0)
		local look = { c = it[6], m = it[8] or M.SmoothPlastic }
		if it[1] == "e" then
			K:ell("FfArt", V3(it[4], it[5], 0.012), cf * CF(0, 0, 0.006), look)
		else
			K:box("FfArt", V3(it[4], it[5], 0.012), cf * CF(0, 0, 0.006), look)
		end
	end
	return z + (#items + 1) * 0.004
end

-- 음식 그림 (중심 x, y, 크기 s) ---------------------------------------------------------------------
local function artChicken(x: number, y: number, s: number): { any }
	local g1, g2, g3 = rgb(200, 122, 44), rgb(176, 98, 32), rgb(222, 150, 66)
	return {
		{ "e", x - 0.05 * s, y - 0.32 * s, 1.5 * s, 0.32 * s, rgb(236, 236, 230) }, -- 접시 (바구니 종이)
		{ "e", x - 0.42 * s, y - 0.05 * s, 0.62 * s, 0.46 * s, g2, 0.3 },
		{ "e", x + 0.1 * s, y + 0.08 * s, 0.7 * s, 0.52 * s, g1, -0.2 },
		{ "e", x + 0.46 * s, y - 0.1 * s, 0.56 * s, 0.42 * s, g3, 0.4 },
		{ "e", x - 0.1 * s, y - 0.18 * s, 0.6 * s, 0.36 * s, g1, 0.1 },
		{ "e", x - 0.62 * s, y + 0.18 * s, 0.2 * s, 0.14 * s, rgb(240, 230, 210), 0.5 }, -- 닭다리 뼈
		{ "e", x + 0.18 * s, y + 0.2 * s, 0.14 * s, 0.08 * s, dark(g1, 0.3), 0.3 },
		{ "e", x - 0.25 * s, y + 0.02 * s, 0.12 * s, 0.07 * s, dark(g2, 0.25), -0.4 },
		{ "e", x + 0.42 * s, y - 0.02 * s, 0.1 * s, 0.06 * s, light(g3, 0.3), 0.2 },
	}
end

local function artYangnyeom(x: number, y: number, s: number): { any }
	local r1, r2 = rgb(170, 40, 24), rgb(196, 62, 30)
	return {
		{ "e", x, y - 0.3 * s, 1.5 * s, 0.32 * s, rgb(240, 236, 228) },
		{ "e", x - 0.35 * s, y - 0.02 * s, 0.6 * s, 0.46 * s, r1, 0.3 },
		{ "e", x + 0.15 * s, y + 0.08 * s, 0.66 * s, 0.5 * s, r2, -0.2 },
		{ "e", x + 0.45 * s, y - 0.12 * s, 0.5 * s, 0.4 * s, r1, 0.5 },
		{ "e", x - 0.05 * s, y + 0.18 * s, 0.07 * s, 0.05 * s, rgb(250, 246, 230) }, -- 깨
		{ "e", x + 0.25 * s, y + 0.05 * s, 0.07 * s, 0.05 * s, rgb(250, 246, 230) },
		{ "e", x - 0.3 * s, y + 0.1 * s, 0.07 * s, 0.05 * s, rgb(250, 246, 230) },
		{ "e", x + 0.1 * s, y + 0.22 * s, 0.16 * s, 0.06 * s, light(r2, 0.4), 0.2 }, -- 윤기
	}
end

local function artBeer(x: number, y: number, s: number): { any }
	return {
		{ "b", x + 0.33 * s, y - 0.02 * s, 0.14 * s, 0.6 * s, rgb(220, 226, 228) }, -- 손잡이
		{ "b", x, y - 0.08 * s, 0.56 * s, 0.86 * s, rgb(236, 168, 30) },
		{ "b", x - 0.14 * s, y - 0.08 * s, 0.07 * s, 0.7 * s, rgb(252, 214, 110) }, -- 빛
		{ "e", x, y + 0.38 * s, 0.66 * s, 0.3 * s, rgb(252, 250, 244) }, -- 거품
		{ "e", x + 0.16 * s, y + 0.44 * s, 0.32 * s, 0.22 * s, rgb(252, 250, 244) },
		{ "e", x + 0.1 * s, y - 0.25 * s, 0.05 * s, 0.05 * s, rgb(255, 236, 170) },
		{ "e", x - 0.05 * s, y + 0.05 * s, 0.04 * s, 0.04 * s, rgb(255, 236, 170) },
	}
end

local function artBurger(x: number, y: number, s: number): { any }
	return {
		{ "e", x, y + 0.2 * s, 1.0 * s, 0.56 * s, rgb(214, 140, 60) }, -- 윗빵
		{ "e", x - 0.18 * s, y + 0.36 * s, 0.06 * s, 0.035 * s, rgb(250, 240, 210) },
		{ "e", x + 0.12 * s, y + 0.4 * s, 0.06 * s, 0.035 * s, rgb(250, 240, 210) },
		{ "e", x + 0.3 * s, y + 0.3 * s, 0.06 * s, 0.035 * s, rgb(250, 240, 210) },
		{ "e", x - 0.02 * s, y - 0.02 * s, 1.1 * s, 0.14 * s, rgb(90, 170, 60) }, -- 양상추
		{ "b", x, y - 0.08 * s, 0.96 * s, 0.07 * s, rgb(210, 50, 40) }, -- 토마토
		{ "b", x + 0.02 * s, y - 0.14 * s, 1.0 * s, 0.07 * s, rgb(250, 196, 40), 0.04 }, -- 치즈
		{ "e", x, y - 0.24 * s, 1.04 * s, 0.2 * s, rgb(92, 52, 30) }, -- 패티
		{ "e", x, y - 0.4 * s, 0.98 * s, 0.2 * s, rgb(206, 132, 56) }, -- 아랫빵
	}
end

local function artFries(x: number, y: number, s: number): { any }
	local out = {}
	for i = -3, 3 do
		table.insert(out, { "b", x + i * 0.07 * s, y + 0.12 * s + math.abs(i) * -0.02 * s, 0.06 * s, 0.6 * s, rgb(250, 204, 70), i * 0.06 })
	end
	table.insert(out, { "b", x, y - 0.16 * s, 0.56 * s, 0.5 * s, rgb(210, 30, 36) })
	table.insert(out, { "b", x, y - 0.1 * s, 0.3 * s, 0.12 * s, rgb(255, 210, 60) })
	return out
end

local function artCola(x: number, y: number, s: number): { any }
	return {
		{ "b", x + 0.06 * s, y + 0.52 * s, 0.04 * s, 0.34 * s, rgb(240, 240, 240), -0.2 },
		{ "b", x, y + 0.32 * s, 0.5 * s, 0.07 * s, rgb(240, 240, 240) },
		{ "b", x, y, 0.44 * s, 0.6 * s, rgb(200, 28, 36) },
		{ "b", x, y + 0.02 * s, 0.44 * s, 0.1 * s, rgb(250, 250, 250) },
	}
end

local function artTteok(x: number, y: number, s: number): { any }
	local out = {
		{ "e", x, y - 0.06 * s, 1.5 * s, 0.6 * s, rgb(248, 246, 240) },
		{ "e", x, y - 0.03 * s, 1.26 * s, 0.46 * s, rgb(206, 52, 28) },
	}
	for i = 0, 6 do
		local a = i * 0.9
		table.insert(out, { "b", x + math.cos(a) * 0.36 * s, y + math.sin(a) * 0.1 * s, 0.32 * s, 0.09 * s, rgb(236, 120, 96), a * 0.3 })
	end
	table.insert(out, { "e", x + 0.32 * s, y + 0.06 * s, 0.24 * s, 0.18 * s, rgb(250, 246, 236) }) -- 삶은 달걀
	table.insert(out, { "e", x + 0.32 * s, y + 0.06 * s, 0.1 * s, 0.08 * s, rgb(250, 200, 60) })
	table.insert(out, { "b", x - 0.3 * s, y + 0.08 * s, 0.3 * s, 0.14 * s, rgb(214, 150, 96), 0.4 }) -- 어묵
	table.insert(out, { "b", x - 0.05 * s, y + 0.14 * s, 0.14 * s, 0.03 * s, rgb(80, 160, 60), 0.6 }) -- 파
	return out
end

local function artGimbap(x: number, y: number, s: number): { any }
	local out = {}
	for i = 0, 2 do
		local cx = x + (i - 1) * 0.42 * s
		table.insert(out, { "e", cx, y, 0.4 * s, 0.4 * s, rgb(28, 32, 26) })
		table.insert(out, { "e", cx, y, 0.34 * s, 0.34 * s, rgb(248, 246, 238) })
		table.insert(out, { "b", cx - 0.06 * s, y + 0.04 * s, 0.06 * s, 0.06 * s, rgb(250, 210, 40) })
		table.insert(out, { "b", cx + 0.05 * s, y + 0.04 * s, 0.06 * s, 0.06 * s, rgb(240, 120, 40) })
		table.insert(out, { "b", cx, y - 0.05 * s, 0.07 * s, 0.05 * s, rgb(60, 140, 50) })
	end
	return out
end

local function artSandwich(x: number, y: number, s: number): { any }
	return {
		{ "e", x, y - 0.14 * s, 1.6 * s, 0.3 * s, rgb(214, 160, 92) },
		{ "e", x - 0.02 * s, y - 0.02 * s, 1.56 * s, 0.14 * s, rgb(240, 150, 150) }, -- 햄
		{ "b", x, y + 0.04 * s, 1.44 * s, 0.07 * s, rgb(250, 210, 60), 0.02 }, -- 치즈
		{ "e", x, y + 0.1 * s, 1.5 * s, 0.12 * s, rgb(100, 180, 60) }, -- 양상추
		{ "e", x - 0.4 * s, y + 0.14 * s, 0.26 * s, 0.1 * s, rgb(210, 50, 40) }, -- 토마토
		{ "e", x + 0.2 * s, y + 0.15 * s, 0.26 * s, 0.1 * s, rgb(210, 50, 40) },
		{ "e", x + 0.5 * s, y + 0.13 * s, 0.2 * s, 0.08 * s, rgb(60, 130, 50) }, -- 오이
		{ "e", x, y + 0.28 * s, 1.58 * s, 0.32 * s, rgb(222, 168, 98) }, -- 윗빵
		{ "e", x - 0.2 * s, y + 0.36 * s, 0.6 * s, 0.06 * s, rgb(236, 196, 130) },
	}
end

local function artTaco(x: number, y: number, s: number): { any }
	return {
		{ "e", x, y - 0.05 * s, 1.2 * s, 0.7 * s, rgb(236, 190, 90) },
		{ "e", x, y + 0.12 * s, 1.0 * s, 0.3 * s, rgb(110, 60, 36) },
		{ "e", x - 0.2 * s, y + 0.2 * s, 0.4 * s, 0.14 * s, rgb(90, 170, 60) },
		{ "e", x + 0.2 * s, y + 0.22 * s, 0.3 * s, 0.12 * s, rgb(210, 50, 40) },
		{ "e", x + 0.05 * s, y + 0.26 * s, 0.3 * s, 0.08 * s, rgb(250, 230, 160) },
	}
end

-- 포스터 · 액자 -----------------------------------------------------------------------------------
-- o = { bg, frame (look | false), art (items), texts = { { s, x, y, w, h, fg, font, align?, glow? } }, glass, lit (bg 가 빛나는 라이트박스), depth }
local function poster(ctx: any, dcf: CFrame, w: number, h: number, o: any)
	local K = ctx.K
	local fr = o.frame
	local b = o.border or 0.08
	local dep = o.depth or 0.08
	if fr ~= false then
		local fl = fr or L.blackMetal
		K:plate("FfFrame", w, b, dep, dcf * CF(0, h / 2 - b / 2, 0), fl)
		K:plate("FfFrame", w, b, dep, dcf * CF(0, -h / 2 + b / 2, 0), fl)
		K:plate("FfFrame", b, h - 2 * b, dep, dcf * CF(-w / 2 + b / 2, 0, 0), fl)
		K:plate("FfFrame", b, h - 2 * b, dep, dcf * CF(w / 2 - b / 2, 0, 0), fl)
	end
	local iw, ih = w - (if fr ~= false then 2 * b else 0), h - (if fr ~= false then 2 * b else 0)
	local face = dcf * CF(0, 0, 0.03)
	if o.lit then
		K:text("FfLightbox", iw, ih, dcf * CF(0, 0, 0.0), "", { bg = o.bg, glow = o.lit, d = 0.03 })
	else
		K:plate("FfPosterBg", iw, ih, 0.03, dcf, pl(o.bg or WHITE))
	end
	local z = 0.004
	if o.art then
		z = art(K, face, o.art, z)
	end
	for i, t in o.texts or {} do
		K:text("FfPosterText", t[4], t[5], face * CF(t[2], t[3], z + i * 0.003), t[1], { fg = t[6], font = t[7] or F.GothamBlack, align = t[8], glow = t[9] or o.textGlow, d = 0.006 })
	end
	if o.glass and not ctx.low then
		K:plate("FfPosterGlass", iw, ih, 0.01, dcf * CF(0, 0, dep - 0.012), { c = rgb(230, 236, 240), m = M.Glass, t = 0.9, r = 0.2 })
	end
end

-- 추가 음식 그림 -------------------------------------------------------------------------------------
local function artGanjang(x: number, y: number, s: number): { any }
	local a = artChicken(x, y, s)
	for i, q in a do
		if i ~= 1 and i ~= 6 then
			q[6] = (q[6] :: Color3):Lerp(rgb(110, 60, 24), 0.55)
		end
	end
	table.insert(a, { "e", x + 0.1 * s, y + 0.2 * s, 0.2 * s, 0.06 * s, rgb(230, 170, 90), 0.2 })
	return a
end

local function artPadak(x: number, y: number, s: number): { any }
	local a = artChicken(x, y - 0.05 * s, s * 0.9)
	for i = -3, 3 do
		table.insert(a, { "b", x + i * 0.12 * s, y + 0.25 * s, 0.05 * s, 0.5 * s, if i % 2 == 0 then rgb(120, 190, 70) else rgb(230, 240, 210), i * 0.3 })
	end
	return a
end

local function artBalls(x: number, y: number, s: number, c: Color3): { any }
	local out = { { "e", x, y - 0.25 * s, 1.3 * s, 0.3 * s, rgb(240, 236, 228) } }
	for i = 0, 5 do
		local a = i * 1.05
		table.insert(out, { "e", x + math.cos(a) * 0.32 * s, y + math.sin(a) * 0.14 * s, 0.36 * s, 0.36 * s, if i % 2 == 0 then c else dark(c, 0.12) })
	end
	return out
end

local function artSundae(x: number, y: number, s: number): { any }
	local out = { { "e", x, y - 0.1 * s, 1.4 * s, 0.5 * s, rgb(244, 242, 236) } }
	for i = -2, 2 do
		table.insert(out, { "e", x + i * 0.24 * s, y, 0.26 * s, 0.26 * s, rgb(50, 36, 42) })
		table.insert(out, { "e", x + i * 0.24 * s, y, 0.14 * s, 0.14 * s, rgb(96, 70, 76) })
	end
	table.insert(out, { "b", x + 0.45 * s, y - 0.2 * s, 0.3 * s, 0.14 * s, rgb(110, 50, 40), 0.3 })
	return out
end

local function artTwigim(x: number, y: number, s: number): { any }
	local out = { { "b", x, y - 0.25 * s, 1.4 * s, 0.14 * s, rgb(246, 240, 220) } }
	local cols = { rgb(206, 150, 70), rgb(222, 176, 96), rgb(214, 140, 60), rgb(196, 150, 70) }
	for i = 0, 4 do
		table.insert(out, { "e", x + (i - 2) * 0.26 * s, y + (i % 2) * 0.1 * s - 0.05 * s, 0.4 * s, 0.26 * s, cols[i % 4 + 1], (i - 2) * 0.3 })
	end
	return out
end

local function artEomuk(x: number, y: number, s: number): { any }
	local out = { { "e", x, y - 0.3 * s, 1.2 * s, 0.34 * s, rgb(200, 160, 100) } }
	for i = -1, 1 do
		table.insert(out, { "b", x + i * 0.3 * s, y + 0.1 * s, 0.03 * s, 0.9 * s, rgb(214, 182, 130), i * 0.15 })
		table.insert(out, { "e", x + i * 0.3 * s, y + 0.02 * s, 0.3 * s, 0.22 * s, rgb(214, 166, 110), i * 0.15 })
		table.insert(out, { "e", x + i * 0.3 * s, y - 0.16 * s, 0.3 * s, 0.22 * s, rgb(200, 150, 96), i * 0.15 })
	end
	return out
end

local function artNoodle(x: number, y: number, s: number, broth: Color3, top: Color3?): { any }
	local out = {
		{ "e", x, y - 0.05 * s, 1.4 * s, 0.6 * s, rgb(40, 40, 44) },
		{ "e", x, y, 1.2 * s, 0.46 * s, broth },
	}
	for i = -2, 2 do
		table.insert(out, { "b", x + i * 0.15 * s, y + 0.02 * s, 0.08 * s, 0.32 * s, rgb(244, 220, 150), 0.5 + i * 0.2 })
	end
	if top then
		table.insert(out, { "e", x + 0.25 * s, y + 0.08 * s, 0.3 * s, 0.14 * s, top })
	end
	table.insert(out, { "e", x - 0.25 * s, y + 0.1 * s, 0.22 * s, 0.16 * s, rgb(250, 246, 236) })
	table.insert(out, { "e", x - 0.25 * s, y + 0.1 * s, 0.1 * s, 0.08 * s, rgb(250, 200, 60) })
	return out
end

-- 사진 메뉴 띠 (라이트박스 한 줄): items = { { 이름, 가격, art } }
local function photoStrip(ctx: any, dcf: CFrame, w: number, h: number, items: { any }, o: any?)
	local K = ctx.K
	local oo: any = o or {}
	local n = #items
	local frameL = oo.frame or L.of(30, 30, 32, M.Metal)
	K:plate("FfStripBox", w + 0.16, h + 0.16, 0.22, dcf, frameL)
	local pw = w / n
	for i, it in items do
		local c = dcf * CF(-w / 2 + pw * (i - 0.5), 0, 0.22)
		K:text("FfStripPanel", pw - 0.06, h, c, "", { bg = oo.bg or rgb(252, 250, 244), glow = 1.1, d = 0.01 })
		local face = c * CF(0, 0, 0.012)
		local s = math.min(pw * 0.62, h * 0.55)
		art(K, face, it[3], 0.002)
		K:text("FfStripName", pw - 0.2, h * 0.17, face * CF(0, -h * 0.3, 0.06), it[1], { fg = oo.fg or rgb(40, 30, 20), font = F.GothamBlack, d = 0.004 })
		K:text("FfStripPrice", pw - 0.3, h * 0.14, face * CF(0, -h * 0.43, 0.06), it[2], { fg = oo.priceC or rgb(200, 30, 30), font = F.GothamBlack, d = 0.004 })
		if i < n then
			K:plate("FfStripDiv", 0.04, h, 0.03, dcf * CF(-w / 2 + pw * i, 0, 0.22), frameL)
		end
		local _ = s
	end
	if oo.title then
		K:text("FfStripTitle", math.min(w * 0.5, 4), 0.34, dcf * CF(0, h / 2 + 0.3, 0.02), oo.title, { fg = WHITE, bg = oo.titleBg or rgb(200, 30, 30), font = F.GothamBlack, d = 0.04 })
	end
end

-- 천장 원목 보 (장애물 · keep 피해 잘라서). axis = "x" (가로 보) | "z" (세로 보)
local function ceilingBeams(ctx: any, axis: string, n: number, look: any, depth: number?)
	local K, V = ctx.K, ctx.V
	local dep = depth or 0.42
	local y = V.H - dep / 2 - 0.01
	local boxes = {}
	for _, r in V.hang do
		table.insert(boxes, r)
	end
	for _, r in V.parts do
		if (r.name == "CassetteAC" or r.name == "Downlight" or r.name == "TBar" or r.name == "LightPanel" or r.name == "LightFrame") then
			table.insert(boxes, r)
		end
	end
	for _, k in V.keep do
		if k.max.Y > V.H - 0.8 then
			table.insert(boxes, { min = k.min, max = k.max })
		end
	end
	for _, q in K.ceilUsed or {} do
		table.insert(boxes, { min = q - V3(0.5, 0, 0.5) + V3(0, V.H - 1, 0), max = q + V3(0.5, 0, 0.5) + V3(0, V.H + 1, 0) })
	end
	for i = 1, n do
		local f = (i - 0.5) / n
		local a0, a1, c
		if axis == "x" then
			c = V.z0 + V.D * f
			a0, a1 = V.x0 + 0.05, V.x1 - 0.05
		else
			c = V.x0 + V.W * f
			a0, a1 = V.z0 + 0.05, V.z1 - 2.0
		end
		-- 이 보와 겹치는 구간 빼기
		local cuts = {}
		for _, b in boxes do
			local lo, hi, cmin, cmax
			if axis == "x" then
				lo, hi, cmin, cmax = b.min.X, b.max.X, b.min.Z, b.max.Z
			else
				lo, hi, cmin, cmax = b.min.Z, b.max.Z, b.min.X, b.max.X
			end
			if b.max.Y > y - dep / 2 and cmin < c + 0.3 and cmax > c - 0.3 then
				table.insert(cuts, { lo - 0.15, hi + 0.15 })
			end
		end
		table.sort(cuts, function(p, q)
			return p[1] < q[1]
		end)
		local cur = a0
		local segs = {}
		for _, ct in cuts do
			if ct[1] > cur then
				table.insert(segs, { cur, math.min(ct[1], a1) })
			end
			cur = math.max(cur, ct[2])
		end
		if cur < a1 then
			table.insert(segs, { cur, a1 })
		end
		for _, sg in segs do
			local len = sg[2] - sg[1]
			if len > 1.2 then
				local m = (sg[1] + sg[2]) / 2
				local cf = if axis == "x" then CF(m, y, c) else CF(c, y, m)
				K:box("FfBeam", if axis == "x" then V3(len, dep, 0.36) else V3(0.36, dep, len), cf, look)
				-- 펜던트 · 조명이 보를 뚫지 않게 천장 사용 기록
				local t = sg[1]
				while t <= sg[2] do
					if axis == "x" then
						Common.useCeil(K, t, c)
					else
						Common.useCeil(K, c, t)
					end
					t += 0.6
				end
			end
		end
	end
end

-- 벽 글씨 (페인트 레터링 슈퍼그래픽): 남은 빈 벽 윗부분을 채움
local function wallMural(ctx: any, walls: { string }, line1: string, line2: string?, c: Color3, c2: Color3?)
	local K = ctx.K
	local dcf, w = wallSpotFit(ctx, walls, { 8.0, 6.2, 4.6 }, 6.4, 8.9, 0)
	if not dcf then
		return
	end
	local tw = w - 0.6
	K:text("FfMural", tw, 1.2, dcf * CF(0, 0.45, 0.012), line1, { fg = c, font = F.GothamBlack, d = 0.006, free = true })
	K:plate("FfMuralRule", tw * 0.8, 0.07, 0.012, dcf * CF(0, -0.25, 0.012), pl(c2 or c))
	if line2 then
		K:text("FfMural2", tw * 0.8, 0.5, dcf * CF(0, -0.68, 0.012), line2, { fg = c2 or c, font = F.GothamBold, d = 0.006, free = true })
	end
end

-- 종이 · 아크릴 안내문 (한 판 + 글자)
local function notice(ctx: any, dcf: CFrame, w: number, h: number, text: string, o: any?)
	local K = ctx.K
	local oo: any = o or {}
	if oo.frame ~= false then
		K:plate("FfNoticeBack", w + 0.08, h + 0.08, 0.03, dcf, oo.frame or L.of(220, 220, 216))
	end
	K:text("FfNotice", w, h, dcf * CF(0, 0, 0.03), text, { fg = oo.fg or rgb(30, 30, 30), bg = oo.bg or rgb(252, 252, 248), font = oo.font or F.GothamBold, d = 0.02, glow = oo.glow })
end

-- 작은 위생 · 결제 스티커 줄 (dcf 가운데, 가로로 n 개)
local function stickerRow(ctx: any, dcf: CFrame, items: { any }, size: number)
	local n = #items
	local gap = size * 0.12
	local total = n * size + (n - 1) * gap
	for i, it in items do
		local x = -total / 2 + size / 2 + (i - 1) * (size + gap)
		ctx.K:text("FfSticker", size, size * (it.h or 0.62), dcf * CF(x, 0, 0), it[1], { fg = it[3] or WHITE, bg = it[2], font = F.GothamBlack, d = 0.012 })
	end
end

-- 원산지 표시판 (음식점 의무 표시)
local function originBoard(ctx: any, dcf: CFrame, w: number, lines: { string })
	local K = ctx.K
	local h = 0.55 + #lines * 0.36
	K:plate("FfOriginBack", w + 0.1, h + 0.1, 0.04, dcf, L.of(40, 60, 120))
	K:text("FfOriginTitle", w, 0.46, dcf * CF(0, h / 2 - 0.25, 0.04), "원 산 지 표 시", { fg = WHITE, bg = rgb(40, 60, 120), font = F.GothamBlack, d = 0.01 })
	K:text("FfOriginBody", w - 0.1, h - 0.6, dcf * CF(0, -0.27, 0.04), table.concat(lines, "\n"), { fg = rgb(20, 24, 40), bg = rgb(250, 250, 246), font = F.GothamBold, align = "Left", d = 0.01 })
	return h
end

-- 와이파이 안내 (아이콘 + 글자)
local function wifiSign(ctx: any, dcf: CFrame, ssid: string, pw: string)
	local K = ctx.K
	K:plate("FfWifiBack", 1.3, 0.62, 0.03, dcf, L.of(250, 250, 248))
	if not ctx.low then
		for i = 1, 3 do
			K:ring("FfWifiArc", dcf * CF(-0.42, -0.12, 0.04), 0.07 * i, 0.03, 4, L.of(40, 120, 220), PI * 0.25, PI * 0.75)
		end
		K:disc("FfWifiDot", 0.05, 0.02, dcf * CF(-0.42, -0.12, 0.04) * ANG(PI / 2, 0, 0), L.of(40, 120, 220))
	end
	K:text("FfWifiText", 0.86, 0.5, dcf * CF(0.16, 0, 0.04), "Wi-Fi  " .. ssid .. "\nPW  " .. pw, { fg = rgb(30, 40, 60), font = F.GothamBold, align = "Left", d = 0.01 })
end

-- 프롬프트를 달 파트 고르기: 후보 중 서버 앵커 6.5 밖에 있는 첫 파트
local function pickAnchor(K: any, parts: { any }): BasePart?
	for _, p in parts do
		if p and p.Parent and Interact.canPrompt(K, K.cf:PointToObjectSpace(p.Position)) then
			return p
		end
	end
	return nil
end

-- 벽걸이 TV (채널 바꾸기 / 자동 순환). chans = { { name, bg, items (art), text, text2? } }
local function tvSet(ctx: any, dcf: CFrame, w: number, chans: { any }, objName: string?)
	local K = ctx.K
	local h = w * 9 / 16
	K:plate("FfTVMount", w * 0.3, h * 0.3, 0.12, dcf, L.blackMetal)
	K:plate("FfTVBody", w + 0.14, h + 0.14, 0.14, dcf * CF(0, 0, 0.12), L.black)
	K:plate("FfTVLogo", 0.24, 0.04, 0.01, dcf * CF(0, -h / 2 - 0.035, 0.265), L.chrome)
	if not ctx.low then
		-- 전원 · HDMI 케이블 (벽 몰딩 덮개로 내려가 콘센트로)
		K:plate("FfTVCableCover", 0.12, 1.4, 0.05, dcf * CF(w * 0.2, -h / 2 - 0.7, 0), L.of(236, 236, 232))
		K:plate("FfTVOutlet", 0.3, 0.4, 0.04, dcf * CF(w * 0.2, -h / 2 - 1.55, 0), L.white)
		K:plate("FfSettopShelf", 0.9, 0.05, 0.46, dcf * CF(-w * 0.3, -h / 2 - 0.4, 0), L.of(30, 30, 32, M.Glass, { t = 0.3 }))
		K:plate("FfSettopBracket", 0.06, 0.25, 0.04, dcf * CF(-w * 0.3, -h / 2 - 0.53, 0), L.blackMetal)
		K:plate("FfSettopBox", 0.7, 0.16, 0.38, dcf * CF(-w * 0.3, -h / 2 - 0.295, 0.02), L.of(30, 30, 32))
		K:plate("FfSettopLed", 0.05, 0.03, 0.01, dcf * CF(-w * 0.3 + 0.25, -h / 2 - 0.295, 0.4), L.ledGreen)
	end
	if not ctx.low then
		K:disc("FfTVLed", 0.04, 0.01, dcf * CF(w / 2 - 0.1, -h / 2 - 0.04, 0.265) * ANG(PI / 2, 0, 0), L.ledRed)
	end
	local screen = K:plate("FfTVScreen", w, h, 0.02, dcf * CF(0, 0, 0.26), { c = chans[1][2], m = M.Neon })
	local face = dcf * CF(0, 0, 0.28)
	local groups = {}
	local labels = {}
	for ci, ch in chans do
		local parts = {}
		for i, it in ch[3] or {} do
			local cf = face * CF(it[2] * w, it[3] * h, i * 0.003) * ANG(0, 0, it[7] or 0)
			local p
			if it[1] == "e" then
				p = K:ell("FfTVArt", V3(it[4] * w, it[5] * h, 0.01), cf, { c = it[6], m = M.Neon })
			else
				p = K:box("FfTVArt", V3(it[4] * w, it[5] * h, 0.01), cf, { c = it[6], m = M.Neon })
			end
			if ci ~= 1 then
				p.Transparency = 1
			end
			table.insert(parts, p)
		end
		local lab = nil
		if ch[4] then
			local tp, tl = K:text("FfTVText", w * 0.92, h * 0.16, face * CF(0, h * 0.4, 0.04), ch[4], { fg = WHITE, glow = 1.4, font = F.GothamBold, d = 0.004 })
			lab = tl
			if ci ~= 1 then
				tl.Visible = false
			end
			table.insert(labels, tl)
		end
		if ch[5] then
			local _, tl2 = K:text("FfTVText2", w * 0.92, h * 0.13, face * CF(0, -h * 0.4, 0.04), ch[5], { fg = WHITE, glow = 1.4, font = F.GothamBold, d = 0.004 })
			if ci ~= 1 then
				tl2.Visible = false
			end
			table.insert(parts, tl2 :: any)
		end
		groups[ci] = { parts = parts, label = lab, bg = ch[2] }
	end
	local function show(i: number)
		for gi, g in groups do
			for _, p in g.parts do
				if typeof(p) == "Instance" and (p :: Instance):IsA("TextLabel") then
					(p :: any).Visible = gi == i
				elseif (p :: any).Parent then
					(p :: any).Transparency = if gi == i then 0 else 1
				end
			end
			if g.label then
				g.label.Visible = gi == i
			end
		end
		if screen.Parent then
			screen.Color = groups[i].bg
		end
	end
	local items = {}
	for i = 1, #chans do
		items[i] = i
	end
	local pr = nil
	-- 전원 버튼 (아래 양 모서리) 도 프롬프트 후보
	local bl = K:plate("FfTVButton", 0.12, 0.05, 0.03, dcf * CF(-w / 2 + 0.25, -h / 2 - 0.04, 0.26), L.of(60, 60, 64))
	local br = K:plate("FfTVButton", 0.12, 0.05, 0.03, dcf * CF(w / 2 - 0.25, -h / 2 - 0.04, 0.26), L.of(60, 60, 64))
	local anchor = pickAnchor(K, { screen, bl, br })
	if anchor then
		pr = Interact.cycle(K, anchor, items, { object = objName or "TV", action = "채널 바꾸기", on = function(i)
			show(i)
		end })
	end
	if not pr then
		-- 프롬프트를 둘 수 없는 자리: 채널이 저절로 돔
		local last = 1
		Interact.anim(K, function(t)
			local i = math.floor(t / 9) % #chans + 1
			if i ~= last then
				last = i
				show(i)
			end
		end)
	end
	return screen
end

-- 네온사인 (글자 + 선택 네온관 그림) + 켜기/끄기
local function neonSign(ctx: any, dcf: CFrame, w: number, h: number, text: string, c: Color3, o: any?): any
	local K = ctx.K
	local oo: any = o or {}
	local tubes = {}
	local anchors = {}
	if oo.backer ~= false then
		K:plate("FfNeonBacker", w + 0.3, h + 0.24, 0.05, dcf, oo.backerLook or { c = rgb(26, 26, 30), m = M.Glass, t = 0.4 })
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				table.insert(anchors, K:cyl("FfNeonStandoff", 0.16, 0.08, dcf * CF(sx * (w / 2 + 0.05), sy * (h / 2 + 0.02), 0.13) * ANG(0, PI / 2, 0), L.chrome))
			end
		end
	end
	local tw = oo.textW or w
	local plate, label = K:text("FfNeonText", tw, h, dcf * CF(oo.textX or 0, 0, 0.08), text, { fg = c, glow = 2.4, font = oo.font or F.GothamBlack })
	for _, sg in oo.shapes or {} do
		-- sg = { a = Vector2, b = Vector2 } 표시면 좌표의 네온관
		local pa = (dcf * CF(sg[1], sg[2], 0.1)).Position
		local pb = (dcf * CF(sg[3], sg[4], 0.1)).Position
		local p = K:seg("FfNeonTube", pa, pb, 0.07, neon(sg[5] or c), 0.06)
		if p then
			table.insert(tubes, p)
		end
	end
	local lt = nil
	if oo.light ~= false then
		lt = K:light(plate, "SurfaceLight", { Face = Enum.NormalId.Front, Range = 6, Brightness = 0.55, Angle = 70, Color = c })
	end
	local rec = { plate = plate, label = label, tubes = tubes, light = lt, c = c }
	if oo.toggle ~= false and plate.Parent and ctx.toggles < 2 then
		table.insert(anchors, 1, plate)
		local anchor = pickAnchor(K, anchors)
		if anchor then
			local pr = Interact.toggle(K, anchor, {
				object = oo.object or "네온사인",
				state = true,
				on = function(state)
					label.TextColor3 = if state then c else dark(c, 0.65)
					local g = label.Parent :: any
					if g then
						g.Brightness = if state then 2.4 else 1
						g.LightInfluence = if state then 0 else 1
					end
					for _, t in tubes do
						t.Material = if state then M.Neon else M.SmoothPlastic
						t.Color = if state then c else dark(c, 0.5)
					end
					if lt then
						lt.Enabled = state
					end
				end,
			})
			if pr then
				ctx.toggles += 1
			end
		end
	end
	return rec
end

-- 벽걸이 선풍기 (좌우 회전 + 날개 회전, 켜기/끄기). dcf = 벽 표면 브래킷 가운데
local function wallFan(ctx: any, dcf: CFrame, o: any?)
	local K = ctx.K
	local oo: any = o or {}
	local body = oo.body or L.of(238, 238, 234, M.Plastic)
	local bladeL = oo.blade or { c = rgb(120, 190, 230), m = M.Plastic, t = 0.25 }
	K:plate("FfFanBracket", 0.5, 0.7, 0.08, dcf, body)
	local pivot = dcf * CF(0, -0.2, 0.55)
	K:bar("FfFanArm", (dcf * CF(0, 0, 0.08)).Position, pivot.Position, 0.14, 0.14, body)
	local head = {}
	local blades = {}
	local tilt = ANG(0.22, 0, 0)
	local hcf = pivot * tilt
	table.insert(head, K:ell("FfFanMotor", V3(0.5, 0.5, 0.72), hcf * CF(0, 0, 0.1), body))
	local cageC = hcf * CF(0, 0, 0.62)
	table.insert(head, K:cyl("FfFanCageBack", 0.04, 1.34, cageC * CF(0, 0, -0.16) * ANG(0, PI / 2, 0), { c = rgb(220, 222, 224), m = M.Metal, t = 0.72 }))
	for _, p in K:ring("FfFanCage", cageC * CF(0, 0, 0.12), 0.66, 0.04, if ctx.low then 8 else 12, L.of(226, 228, 230, M.Metal)) do
		table.insert(head, p)
	end
	if not ctx.low then
		for i = 0, 3 do
			local a = i * PI / 4
			table.insert(head, K:box("FfFanWire", V3(1.3, 0.025, 0.025), cageC * CF(0, 0, 0.14) * ANG(0, 0, a), L.of(226, 228, 230, M.Metal)))
		end
	end
	table.insert(head, K:cyl("FfFanBadge", 0.06, 0.26, cageC * CF(0, 0, 0.16) * ANG(0, PI / 2, 0), oo.badge or L.of(40, 110, 200)))
	local hub = cageC * CF(0, 0, -0.02)
	table.insert(head, K:cyl("FfFanHub", 0.14, 0.2, hub * ANG(0, PI / 2, 0), body))
	for i = 0, 2 do
		local a = i * 2 * PI / 3
		local b = K:ell("FfFanBlade", V3(0.26, 0.56, 0.04), hub * ANG(0, 0, a) * CF(0, 0.3, 0) * ANG(0, 0.35, 0), bladeL)
		table.insert(blades, { p = b, a = a })
	end
	-- 상대 자세 기록
	local wp = K.cf * pivot
	local rel = {}
	for _, p in head do
		if p.Parent then
			table.insert(rel, { p = p, r = wp:ToObjectSpace(p.CFrame) })
		end
	end
	local hubRel = (pivot):ToObjectSpace(hub)
	local on = true
	local spin = 0
	local yawT = 0
	local lastT: number? = nil
	Interact.anim(K, function(t)
		local dt = if lastT then math.clamp(t - (lastT :: number), 0, 0.3) else 0.1
		lastT = t
		if not on then
			return
		end
		yawT += dt
		spin += dt * 11
		local yaw = math.sin(yawT * 0.55) * 0.55
		local base = wp * ANG(0, yaw, 0)
		for _, r in rel do
			if r.p.Parent then
				r.p.CFrame = base * r.r
			end
		end
		local hw = base * hubRel
		for _, b in blades do
			if b.p.Parent then
				b.p.CFrame = hw * ANG(0, 0, b.a + spin) * CF(0, 0.3, 0) * ANG(0, 0.35, 0)
			end
		end
	end)
	local motor = head[1]
	if motor and motor.Parent and ctx.toggles < 3 then
		local lp = K.cf:PointToObjectSpace(motor.Position)
		if Interact.canPrompt(K, lp) then
			local pr = Interact.toggle(K, motor, { object = "선풍기", state = true, on = function(s)
				on = s
			end })
			if pr then
				ctx.toggles += 1
			end
		end
	end
end

-- 여러 문짝을 한 프롬프트로 여닫기 (냉장고 2~3칸)
local function swingDoors(ctx: any, doors: { any }, object: string, extra: { BasePart }?)
	local K = ctx.K
	local recs = {}
	local handle: BasePart? = nil
	for _, d in doors do
		local parts = {}
		for _, p in d.model:GetDescendants() do
			if p:IsA("BasePart") then
				table.insert(parts, { p = p, cf = p.CFrame })
				if string.find(p.Name, "Handle") and not handle and Interact.canPrompt(K, K.cf:PointToObjectSpace(p.Position)) then
					handle = p
				end
			end
		end
		table.insert(recs, { parts = parts, hinge = d.hinge, angle = d.angle })
	end
	if not handle then
		for _, r in recs do
			for _, q in r.parts do
				if not handle and string.find(q.p.Name, "Frame") and Interact.canPrompt(K, K.cf:PointToObjectSpace(q.p.Position)) then
					handle = q.p
				end
			end
		end
	end
	if not handle then
		for _, q in extra or {} do
			if not handle and q.Parent and Interact.canPrompt(K, K.cf:PointToObjectSpace(q.Position)) then
				handle = q
			end
		end
	end
	if not handle or not (handle :: BasePart).Parent then
		return nil
	end
	local open = false
	local axis = (K.cf.UpVector :: Vector3)
	local function set(o: boolean)
		for _, r in recs do
			local rot = CFrame.new(r.hinge) * CFrame.fromAxisAngle(axis, if o then r.angle else 0) * CFrame.new(-r.hinge)
			for _, q in r.parts do
				if q.p.Parent then
					TweenService:Create(q.p, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = rot * q.cf }):Play()
				end
			end
		end
	end
	return Interact.prompt(K, handle :: BasePart, {
		action = "열기",
		object = object,
		sound = "rbxasset://sounds/clickfast.wav",
		fn = function(_n, p)
			open = not open
			set(open)
			p.ActionText = if open then "닫기" else "열기"
		end,
	})
end

-- 음료 쇼케이스 냉장고 (속이 보이는 빈 몸체: 옆판 · 뒤판 · 천장 · 받침 + 선반 + 병/캔 + 유리문)
-- items = { { Color3, "can"|"bottle"|"pet"|"soju", cap? } } 순서대로 채움
local function drinkFridge(ctx: any, pcf: CFrame, o: any): any
	local K = ctx.K
	local nd = o.doors or 2
	local dw = o.doorW or 2.0
	local w = nd * dw + 0.3
	local h = o.h or 6.4
	local d = o.d or 2.0
	local body = o.body or L.of(34, 36, 40, M.Metal)
	local inner = L.of(236, 240, 242)
	-- 몸체 (빈 상자)
	K:box("FfFridgeSide", V3(0.15, h, d), pcf * CF(-w / 2 + 0.075, h / 2, 0), body)
	K:box("FfFridgeSide", V3(0.15, h, d), pcf * CF(w / 2 - 0.075, h / 2, 0), body)
	K:box("FfFridgeBack", V3(w - 0.3, h, 0.12), pcf * CF(0, h / 2, -d / 2 + 0.06), body)
	K:box("FfFridgeKick", V3(w - 0.3, 0.6, d), pcf * CF(0, 0.3, 0), body)
	local headH = 0.75
	K:box("FfFridgeTop", V3(w - 0.3, headH, d), pcf * CF(0, h - headH / 2, 0), body)
	K:text("FfFridgeHeader", w - 0.2, headH - 0.14, pcf * CF(0, h - headH / 2, d / 2 + 0.005), o.header or "시원한 음료", { fg = o.headerFg or WHITE, bg = o.headerBg or rgb(200, 30, 36), glow = 1.3, font = F.GothamBlack, d = 0.02 })
	local innerH = h - headH - 0.6
	local y0 = 0.6
	K:box("FfFridgeInner", V3(w - 0.32, innerH, 0.03), pcf * CF(0, y0 + innerH / 2, -d / 2 + 0.135), inner)
	-- 안쪽 LED (문 사이 · 양옆 세로)
	local lamp = K:box("FfFridgeLamp", V3(w - 0.4, 0.06, 0.08), pcf * CF(0, y0 + innerH - 0.06, d / 2 - 0.3), neon(rgb(236, 246, 255)))
	if o.light ~= false then
		K:light(lamp, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 7, Brightness = 0.7, Angle = 140, Color = L.coolLight })
	end
	for i = 0, nd do
		local x = -w / 2 + 0.15 + i * dw
		K:box("FfFridgeLedV", V3(0.05, innerH - 0.1, 0.05), pcf * CF(x + (if i == 0 then 0.05 elseif i == nd then -0.05 else 0), y0 + innerH / 2, d / 2 - 0.2), neon(rgb(230, 242, 255)))
	end
	-- 선반 + 음료
	local shelves = o.shelves or 4
	local items = o.items
	local k = 0
	local depthRows = if ctx.low then 1 else 2
	for s = 1, shelves do
		local y = y0 + (s - 1) * innerH / shelves + 0.04
		K:box("FfFridgeShelf", V3(w - 0.34, 0.04, d - 0.4), pcf * CF(0, y, 0.0), L.of(210, 214, 218, M.Metal))
		if not ctx.low then
			K:box("FfFridgePriceRail", V3(w - 0.34, 0.12, 0.02), pcf * CF(0, y - 0.02, d / 2 - 0.2), L.of(250, 250, 250))
		end
		local x = -w / 2 + 0.32
		local maxH = innerH / shelves - 0.2
		while x < w / 2 - 0.3 do
			k += 1
			local it = items[(k - 1) % #items + 1]
			local kind = it[2]
			local dia = if kind == "can" then 0.24 elseif kind == "pet" then 0.32 elseif kind == "soju" then 0.24 else 0.26
			local ht = math.min(maxH, if kind == "can" then 0.44 elseif kind == "pet" then 1.05 elseif kind == "soju" then 0.78 else 0.82)
			for r = 1, depthRows do
				local z = d / 2 - 0.42 - (r - 1) * 0.42
				local base = pcf * CF(x, y + 0.02, z)
				if kind == "can" then
					K:vcyl("FfCan", ht, dia, base * CF(0, ht / 2, 0), { c = it[1], m = M.Metal })
					if r == 1 and not ctx.low then
						K:vcyl("FfCanTop", 0.03, dia * 0.86, base * CF(0, ht + 0.015, 0), L.alu)
					end
				else
					local glass = kind == "soju" or kind == "bottle"
					local bl = if glass then { c = it[1], m = M.Glass, t = 0.2, r = 0.08 } else { c = it[1], m = M.Plastic, t = 0.1 }
					K:vcyl("FfBottle", ht * 0.66, dia, base * CF(0, ht * 0.33, 0), bl)
					K:vcyl("FfBottleNeck", ht * 0.3, dia * 0.42, base * CF(0, ht * 0.66 + ht * 0.15, 0), bl)
					if r == 1 then
						K:vcyl("FfBottleLabel", ht * 0.24, dia + 0.01, base * CF(0, ht * 0.34, 0), pl(it[3] or WHITE))
					end
				end
			end
			x += dia + 0.06
		end
	end
	-- 문 (프레임 + 유리 + 손잡이), 경첩 = 각 문 왼쪽 (짝수 칸은 오른쪽)
	local doors = {}
	for i = 1, nd do
		local x0 = -w / 2 + 0.15 + (i - 1) * dw
		local leftHinge = (i % 2 == 1)
		local zf = d / 2 + 0.05
		local m = K:group("FfFridgeDoor_" .. i, function()
			local c = pcf * CF(x0 + dw / 2, y0 + innerH / 2, zf)
			local fl = L.of(26, 26, 28, M.Metal)
			K:box("FfFridgeDoorFrame", V3(dw - 0.02, 0.12, 0.1), c * CF(0, innerH / 2 - 0.06, 0), fl)
			K:box("FfFridgeDoorFrame", V3(dw - 0.02, 0.12, 0.1), c * CF(0, -innerH / 2 + 0.06, 0), fl)
			K:box("FfFridgeDoorFrame", V3(0.1, innerH - 0.24, 0.1), c * CF(-dw / 2 + 0.06, 0, 0), fl)
			K:box("FfFridgeDoorFrame", V3(0.1, innerH - 0.24, 0.1), c * CF(dw / 2 - 0.06, 0, 0), fl)
			K:box("FfFridgeDoorGlass", V3(dw - 0.2, innerH - 0.24, 0.03), c, { c = rgb(214, 232, 238), m = M.Glass, t = 0.78, r = 0.15 })
			local hx = if leftHinge then dw / 2 - 0.2 else -dw / 2 + 0.2
			K:box("FfFridgeDoorHandle", V3(0.07, innerH * 0.55, 0.07), c * CF(hx, 0, 0.14), L.chrome)
			K:box("FfFridgeDoorHandle", V3(0.05, 0.05, 0.12), c * CF(hx, innerH * 0.27, 0.08), L.chrome)
			K:box("FfFridgeDoorHandle", V3(0.05, 0.05, 0.12), c * CF(hx, -innerH * 0.27, 0.08), L.chrome)
		end)
		local hx = if leftHinge then x0 else x0 + dw
		table.insert(doors, { model = m, hinge = (K.cf * pcf * CF(hx, 0, zf)).Position, angle = if leftHinge then -1.75 else 1.75 })
	end
	if not ctx.low then
		K:plate("FfFridgeVent", w * 0.7, 0.32, 0.02, pcf * CF(0, 0.3, d / 2), L.of(60, 60, 64, M.DiamondPlate))
		K:text("FfFridgeBrand", 0.9, 0.18, pcf * CF(-w / 2 + 0.7, 0.3, d / 2 + 0.025), o.brand or "SHOWCASE", { fg = rgb(220, 220, 220), font = F.GothamBold, d = 0.005 })
	end
	return { doors = doors, w = w, h = h, d = d }
end

-- 냉장고 놓기: 2칸 -> 1칸 순서로 자리 찾기 (맵에 냉장고가 이미 있으면 건너뜀)
local function placeFridge(ctx: any, o: any): any
	local V = ctx.V
	if not o.force and (V:has("FridgeDoor") > 0 or V:has("Fridge") > 0 or V:has("OpenChiller") > 0) then
		return nil
	end
	for _, nd in { 2, 1 } do
		local w = nd * 2.0 + 0.3
		local pcf = floorSpot(ctx, { walls = o.walls or { "back", "right", "left" }, w = w, h = 6.15, d = 2.0, pref = o.pref or { back = "right", right = "back", left = "back" }, prompt = true, front = 1.2 })
		if pcf then
			local oo = table.clone(o)
			oo.doors = nd
			oo.h = 6.1
			local fr = drinkFridge(ctx, pcf, oo)
			swingDoors(ctx, fr.doors, o.object or "음료 냉장고")
			return fr
		end
	end
	return nil
end

-- 천장에서 매다는 펜던트 (테이블 위). 맵 펜던트가 있는 매장은 Common 이 이미 바꿨으므로 건너뜀
local function tablePendants(ctx: any, o: any)
	local K, V = ctx.K, ctx.V
	local mapPend = {}
	for _, nm in { "PendantShade", "PendantGlobe" } do
		for _, r in V.byName[nm] or {} do
			table.insert(mapPend, r.c)
		end
	end
	local nLight = 0
	for _, t in V.tables do
		if t.kind ~= "table" then
			continue
		end
		local covered = false
		for _, c in mapPend do
			if c.X > t.min.X - 0.8 and c.X < t.max.X + 0.8 and c.Z > t.min.Z - 0.8 and c.Z < t.max.Z + 0.8 then
				covered = true
			end
		end
		if covered then
			continue -- 맵 펜던트가 이미 있는 테이블 (Common 이 바꿈)
		end
		local cx, cz = (t.min.X + t.max.X) / 2, (t.min.Z + t.max.Z) / 2
		local alongX = (t.max.X - t.min.X) >= (t.max.Z - t.min.Z)
		local spots = {}
		if o.pair and alongX and (t.max.X - t.min.X) > 3 then
			spots = { { cx - 0.85, cz }, { cx + 0.85, cz } }
		else
			spots = { { cx, cz } }
		end
		for _, sp in spots do
			local x, z = sp[1], sp[2]
			-- 형광등 · 에어컨 피해 앞뒤로 조금씩 옮겨 보기
			local placed = false
			for _, dz in { 0, 0.5, -0.5, 0.9, -0.9 } do
				local zz = math.clamp(z + dz, t.min.Z + 0.2, t.max.Z - 0.2)
				local drop = math.clamp(V.H - 6.6, 1.6, 3.6)
				local r0 = (o.dia or 1.15) / 2 + 0.1
				if Common.ceilFree(K, x, zz, 0.55) and not K:hitsKeep(V3(x - r0, V.H - drop - 0.4, zz - r0), V3(x + r0, V.H, zz + r0)) then
					local withLight = nLight < (o.lights or 1) and #K.lights < (V.maxLights or 8) - 2
					K:free(function()
						Props.pendant(K, V3(x, V.H, zz), drop, { shade = o.shade or "dome", dia = o.dia or 1.15, look = o.look, glow = o.glow, light = withLight, range = 12, bright = 0.6 })
					end)
					if withLight then
						nLight += 1
					end
					Common.useCeil(K, x, zz)
					placed = true
					break
				end
			end
			if not placed then
				continue
			end
		end
	end
end

-- 벽 위쪽 칠 (맵 벽 조각이 있는 곳만: 주방 창 · 문 구멍은 피함). 벽면 0.012 앞
local function upperPaint(ctx: any, walls: { string }, y0: number, look: any, y1: number?)
	local K, V = ctx.K, ctx.V
	local top = y1 or (V.H - 0.02)
	local names = {
		back = { "ShopBackWall", "BackWall" },
		left = { "ShopPartition", "ShopWall", "Partition", "SideWall", "Wall" },
		right = { "ShopPartition", "ShopWall", "Partition", "SideWall", "Wall" },
	}
	for _, wn in walls do
		local wl = V.walls[wn]
		if not wl then
			continue
		end
		for _, nm in names[wn] do
			for _, r in V.byName[nm] or {} do
				local plane: number, face: number
				if wn == "back" then
					plane, face = V.z0, r.max.Z
				elseif wn == "left" then
					plane, face = V.x0, r.max.X
				else
					plane, face = V.x1, r.min.X
				end
				if math.abs(face - plane) > 0.3 then
					continue
				end
				local umin, umax = math.huge, -math.huge
				for _, x in { r.min.X, r.max.X } do
					for _, z in { r.min.Z, r.max.Z } do
						local u = V:wallCoord(wn, V3(x, 0, z))
						umin = math.min(umin, u)
						umax = math.max(umax, u)
					end
				end
				umin = math.max(umin, wl.a)
				umax = math.min(umax, wl.b)
				local ya, yb = math.max(y0, r.min.Y), math.min(top, r.max.Y)
				if umax - umin > 0.3 and yb - ya > 0.2 then
					K:free(function()
						K:plate("FfWallPaint", umax - umin, yb - ya, 0.02, V:wall(wn, (umin + umax) / 2, (ya + yb) / 2, 0.012), look)
					end)
				end
			end
		end
	end
end

-- 몰딩 띠 (벽 따라 수평 한 줄, 문 · 창 · 기존 물건은 V:spans 로 피함)
local function wallBand(ctx: any, walls: { string }, y: number, hgt: number, dep: number, look: any)
	local K, V = ctx.K, ctx.V
	for _, wn in walls do
		for _, s in V:spans(wn, y - hgt / 2, y + hgt / 2, 0.3) do
			K:free(function()
				K:plate("FfWallBand", s[2] - s[1], hgt, dep, V:wall(wn, (s[1] + s[2]) / 2, y, 0.02), look)
			end)
		end
	end
end

-- 주방 패스 (KitchenPass + PassLedge) 덮개 + 노렌/후드 -----------------------------------------------
-- o = { trim (look), inner (Color3), lamp (Color3), header = "noren" | "hood" | "pickup" | nil, norenText, norenColor, hoodText }
local function passDress(ctx: any, o: any)
	local K, V = ctx.K, ctx.V
	for _, r in V.byName.KitchenPass or {} do
		if r.c.Z > V.z0 + 1.0 or r.size.X < 1 then
			continue
		end
		local w, h = r.size.X, r.size.Y
		local face = CFrame.fromMatrix(V3(r.c.X, r.c.Y, r.max.Z), Vector3.xAxis, Vector3.yAxis, Vector3.zAxis)
		K:free(function()
			-- 같은 자리 · 같은 크기 덮개 (주방 안쪽처럼 보이는 어두운 스테인리스)
			K:box("FfPassCover", r.size + V3(0.004, 0.004, 0.004), CF(r.c), L.of(46, 48, 52, M.Metal))
			local z = 0.004
			-- 안쪽 벽 타일 (조금 그늘진 흰 타일 + 줄눈) + 아래 스테인리스 조리대 띠 + 위 따뜻한 빛
			K:plate("FfPassTile", w - 0.12, h - 0.62, 0.006, face * CF(0, -0.18, z), L.of(204, 206, 204, M.CeramicTiles))
			K:plate("FfPassCounter", w - 0.12, h * 0.2, 0.012, face * CF(0, -h / 2 + h * 0.1 + 0.02, z + 0.004), L.of(150, 154, 158, M.Metal))
			K:plate("FfPassCounterEdge", w - 0.12, 0.05, 0.016, face * CF(0, -h / 2 + h * 0.2 + 0.02, z + 0.006), L.chrome)
			K:plate("FfPassGlow", w - 0.2, h * 0.34, 0.004, face * CF(0, h * 0.12, z + 0.014), { c = rgb(255, 176, 96), m = M.Neon, t = 0.86 })
			if not ctx.low then
				-- 선반 위 양념통 · 바구니 실루엣
				local cols = o.shelfColors or { rgb(200, 40, 30), rgb(240, 196, 40), rgb(246, 244, 236), rgb(200, 40, 30), rgb(60, 60, 64) }
				for i, c in cols do
					local tx = -w / 2 + 0.45 + (i - 1) * (w - 0.9) / math.max(1, #cols - 1)
					K:plate("FfPassJar", 0.32, 0.4, 0.01, face * CF(tx, h * 0.06 + 0.26, z + 0.012), pl(c))
				end
			end
			if not ctx.low then
				for i = 1, 3 do
					K:plate("FfPassGrout", w - 0.12, 0.02, 0.008, face * CF(0, -0.18 - (h - 0.62) / 2 + i * (h - 0.62) / 4, z), L.of(170, 172, 170))
				end
				for i = 1, math.floor(w / 0.8) do
					K:plate("FfPassGrout", 0.02, h - 0.62, 0.008, face * CF(-w / 2 + 0.06 + i * 0.8, -0.18, z), L.of(170, 172, 170))
				end
			end
			-- 주방 선반 (스테인리스) + 위 후드 그림자 띠
			K:plate("FfPassShelf", w - 0.12, 0.12, 0.03, face * CF(0, h * 0.06, z + 0.006), L.steel)
			K:plate("FfPassHoodBand", w, 0.5, 0.02, face * CF(0, h / 2 - 0.25, z), L.of(70, 72, 76, M.Metal))
			-- 열 램프 (주황 네온 2줄)
			local lampC = o.lamp or rgb(255, 150, 70)
			for _, sx in { -1, 1 } do
				K:plate("FfPassHeatLamp", w * 0.36, 0.07, 0.04, face * CF(sx * w * 0.22, h / 2 - 0.55, z + 0.01), neon(lampC))
			end
			-- 주문서 레일 + 주문서
			K:plate("FfTicketRail", w - 0.3, 0.07, 0.05, face * CF(0, h / 2 - 0.78, z + 0.01), L.chrome)
			local nT = if ctx.low then 2 else 4
			for i = 1, nT do
				local tx = -w / 2 + 0.5 + (i - 1) * (w - 1.0) / math.max(1, nT - 1)
				K:plate("FfTicket", 0.3, 0.46, 0.008, face * CF(tx, h / 2 - 1.04, z + 0.06) * ANG(0, 0, (i % 2 - 0.5) * 0.06), L.paper)
				if not ctx.low then
					for j = 1, 3 do
						K:plate("FfTicketLine", 0.22, 0.025, 0.004, face * CF(tx, h / 2 - 0.9 - j * 0.09, z + 0.068), L.of(60, 60, 60))
					end
				end
			end
			-- 안쪽 소품 실루엣 (국자 · 튀김망 · 뒤집개)
			if not ctx.low then
				for i = 1, 3 do
					local tx = -w / 2 + w * (0.25 + (i - 1) * 0.25)
					K:plate("FfPassUtensil", 0.06, 0.6, 0.008, face * CF(tx, -0.15, z + 0.012), L.of(150, 152, 156, M.Metal))
					if o.utensil == "basket" then
						K:plate("FfPassUtensil", 0.42, 0.3, 0.008, face * CF(tx, -0.55, z + 0.012), L.of(120, 122, 126, M.DiamondPlate))
					else
						K:ell("FfPassUtensil", V3(0.26, 0.18, 0.008), face * CF(tx, -0.5, z + 0.016), L.of(150, 152, 156, M.Metal))
					end
				end
			end
			-- 둘레 몰딩 (벽 마감)
			local tl = o.trim or L.steel
			local tw = 0.16
			K:plate("FfPassTrim", w + 2 * tw, tw, 0.1, face * CF(0, h / 2 + tw / 2, 0), tl)
			K:plate("FfPassTrim", tw, h, 0.1, face * CF(-w / 2 - tw / 2, 0, 0), tl)
			K:plate("FfPassTrim", tw, h, 0.1, face * CF(w / 2 + tw / 2, 0, 0), tl)
		end)
		Scan.hide(K.hidden, r.part)
		-- 헤더
		local topY = r.max.Y
		local hd = o.header
		if hd == "noren" then
			for _, n in V.byName.Noren or {} do
				Scan.hide(K.hidden, n.part)
			end
			local txt = o.norenText or { "분", "식" }
			local n = #txt
			local nw = (w + 0.2) / n
			local col = o.norenColor or rgb(30, 40, 90)
			K:free(function()
				local rodY = topY + 0.3
				K:cyl("FfNorenRod", w + 0.7, 0.12, face * CF(0, rodY - r.c.Y, 0.22), L.of(120, 84, 50, M.Wood))
				for _, sx in { -1, 1 } do
					K:box("FfNorenHook", V3(0.06, 0.2, 0.22), face * CF(sx * (w / 2 + 0.25), rodY - r.c.Y + 0.08, 0.11), L.brass)
				end
				for i = 1, n do
					local x = -w / 2 - 0.1 + nw * (i - 0.5)
					local pcf = face * CF(x, rodY - r.c.Y - 0.62, 0.22)
					K:box("FfNoren", V3(nw - 0.08, 1.16, 0.03), pcf, { c = col, m = M.Fabric })
					K:box("FfNorenHem", V3(nw - 0.08, 0.08, 0.04), pcf * CF(0, 0.54, 0), { c = dark(col, 0.3), m = M.Fabric })
					K:text("FfNorenText", (nw - 0.08) * 0.8, 0.7, pcf * CF(0, -0.06, 0.016), txt[i], { fg = WHITE, font = F.GothamBlack, d = 0.004 })
				end
			end)
		elseif hd == "hood" or hd == "pickup" then
			for _, n in V.byName.Noren or {} do
				Scan.hide(K.hidden, n.part)
			end
			local hw = w + 0.5
			local hh = math.min(0.75, (V.H - topY) - 2.2)
			-- 위쪽 메뉴 간판 (Sign_) 아래까지만
			for _, sg in ctx.wallSigns do
				if sg.min.Y > topY and sg.min.X < r.max.X + 2.2 and sg.max.X > r.min.X - 0.3 then
					hh = math.min(hh, sg.min.Y - 0.1 - (topY + 0.12))
				end
			end
			if hh > 0.3 then
				local hc = face * CF(0, topY - r.c.Y + 0.12 + hh / 2, 0)
				local hl = o.hoodLook or L.steel
				K:free(function()
					K:box("FfPassHood", V3(hw, hh, 0.55), hc * CF(0, 0, 0.275), hl)
					K:box("FfPassHoodLip", V3(hw, 0.06, 0.6), hc * CF(0, -hh / 2 - 0.03, 0.3), dark(hl.c, 0.2) and L.with(hl, { c = dark(hl.c, 0.2) }))
					local txt = o.hoodText or "PICK UP"
					K:text("FfPassHoodText", hw * 0.7, hh * 0.62, hc * CF(0, 0, 0.553), txt, { fg = o.hoodFg or rgb(255, 80, 60), glow = 1.8, font = F.GothamBlack, d = 0.01 })
					if hd == "pickup" and not ctx.low then
						-- 주문번호 호출 모니터 (번호가 바뀜)
						local mw = 1.5
						local mcf = hc * CF(hw / 2 + mw / 2 + 0.3, 0, 0)
						K:plate("FfPickupMon", mw + 0.1, hh + 0.1, 0.12, mcf, L.black)
						local scr, lab = K:text("FfPickupNum", mw, hh, mcf * CF(0, 0, 0.12), "주문번호\n0127", { fg = rgb(255, 210, 60), bg = rgb(16, 16, 20), glow = 1.6, font = F.GothamBlack, d = 0.01 })
						local nums = { "0127", "0128", "0131", "0132", "0135" }
						Interact.anim(K, function(t)
							local i = math.floor(t / 6) % #nums + 1
							lab.Text = "주문번호\n" .. nums[i]
						end)
					end
				end)
			end
		end
	end
	-- 패스 선반: 같은 윗면 · 같은 범위 스테인리스 덮개 (앞 모서리 둥글게)
	for _, r in V.byName.PassLedge or {} do
		local w, d, t = r.size.X, r.size.Z, r.size.Y
		if w < 0.8 or d < 0.3 then
			continue
		end
		K:free(function()
			K:box("FfPassLedge", V3(w, t, d - t / 2), CF(r.c.X, r.c.Y, r.c.Z - t / 4), L.of(196, 200, 204, M.Metal, { r = 0.1 }))
			K:cyl("FfPassLedgeNose", w, t, CF(r.c.X, r.c.Y, r.max.Z - t / 2), L.of(196, 200, 204, M.Metal, { r = 0.1 }))
			if not ctx.low then
				K:box("FfPassLedgeLine", V3(w - 0.1, 0.02, 0.04), CF(r.c.X, r.max.Y + 0.004, r.max.Z - t - 0.08), L.of(150, 154, 158, M.Metal))
			end
		end)
		Scan.hide(K.hidden, r.part)
	end
end

-- 메뉴판 (Sign_메  뉴 / Sign_MENU) 둘레 액자 + 아래 LED 띠 + 위 스포트 (간판 자체는 안 건드림)
local function menuSignDress(ctx: any, look: any, ledC: Color3?)
	local K, V = ctx.K, ctx.V
	for _, r in ctx.wallSigns do
		local nm = r.name
		if not (has(nm, "메  뉴") or has(nm, "MENU") or has(nm, "SUB OF") or has(nm, "SALAD") or has(nm, "15cm")) then
			continue
		end
		if r.c.Z > V.z0 + 0.8 or r.size.X < 2 then
			continue -- 뒷벽 메뉴판만
		end
		local w, h = r.size.X, r.size.Y
		local dcf = CFrame.fromMatrix(V3(r.c.X, r.c.Y, V.z0), Vector3.xAxis, Vector3.yAxis, Vector3.zAxis)
		K:free(function()
			K:plate("FfMenuBacker", w + 0.4, h + 0.36, 0.035, dcf, look)
			if ledC then
				K:plate("FfMenuLED", w - 0.3, 0.05, 0.05, dcf * CF(0, -h / 2 - 0.14, 0.06), neon(ledC))
			end
		end)
		-- 위에서 비추는 작은 스포트 2개 (레일 없이 벽 암)
		if not ctx.low and r.max.Y < V.H - 0.5 then
			for _, sx in { -0.3, 0.3 } do
				local base = dcf * CF(sx * w, h / 2 + 0.35, 0)
				K:free(function()
					K:plate("FfSpotPlate", 0.24, 0.24, 0.04, base, L.blackMetal)
					local tip = base * CF(0, 0.05, 0.7)
					K:bar("FfSpotArm", (base * CF(0, 0, 0.04)).Position, tip.Position, 0.05, 0.05, L.blackMetal)
					local hcf = CFrame.lookAt(tip.Position, (dcf * CF(sx * w, 0, 0)).Position)
					K:cyl("FfSpotHead", 0.36, 0.22, hcf * CF(0, 0, -0.1) * ANG(0, PI / 2, 0), L.blackMetal)
					K:disc("FfSpotLens", 0.17, 0.02, hcf * CF(0, 0, -0.29) * ANG(PI / 2, 0, 0), L.lampWarm)
				end)
			end
		end
	end
end

-- 무인 주문 키오스크 (OrderKiosk + KioskScreen): 같은 자리 · 같은 크기 덮개 (세로형 터치스크린 + 카드 단말 + 영수증)
local function kioskOverlay(ctx: any, brand: string, accent: Color3, tiles: { Color3 }?)
	local K, V = ctx.K, ctx.V
	local scr = V:first("KioskScreen")
	for _, r in V.byName.OrderKiosk or {} do
		-- 화면이 있는 면 = 정면
		local face = V3(0, 0, 1)
		if scr then
			local d = scr.c - r.c
			if math.abs(d.X) > math.abs(d.Z) then
				face = V3(math.sign(d.X), 0, 0)
			else
				face = V3(0, 0, if d.Z < 0 then -1 else 1)
			end
		end
		local w = if math.abs(face.X) > 0.5 then r.size.Z else r.size.X
		local d = if math.abs(face.X) > 0.5 then r.size.X else r.size.Z
		local h = r.size.Y
		local base = CFrame.lookAt(V3(r.c.X, r.min.Y, r.c.Z), V3(r.c.X, r.min.Y, r.c.Z) - face)
		K:free(function()
			K:box("FfKioskPlinth", V3(w, 0.22, d), base * CF(0, 0.11, 0), L.of(30, 30, 32, M.Metal))
			K:box("FfKioskBody", V3(w - 0.04, h - 0.22, d - 0.04), base * CF(0, 0.22 + (h - 0.22) / 2, 0), L.of(40, 42, 46))
			K:box("FfKioskSide", V3(0.06, h - 0.3, d), base * CF(-w / 2 + 0.03, 0.22 + (h - 0.3) / 2, 0), L.of(200, 202, 206, M.Metal))
			K:box("FfKioskSide", V3(0.06, h - 0.3, d), base * CF(w / 2 - 0.03, 0.22 + (h - 0.3) / 2, 0), L.of(200, 202, 206, M.Metal))
			local fz = d / 2 + 0.005
			-- 머리 로고
			K:text("FfKioskBrand", w - 0.2, 0.4, base * CF(0, h - 0.32, fz), brand, { fg = WHITE, bg = accent, glow = 1.4, font = F.GothamBlack, d = 0.02 })
			-- 화면 (맵 화면 자리)
			local sy = if scr then scr.c.Y else h * 0.73
			local sh = if scr then scr.size.Y else 2.2
			local sw = math.min(w - 0.2, if scr then math.max(scr.size.X, scr.size.Z) else w - 0.3)
			local sc = base * CF(0, sy, fz)
			K:text("FfKioskUI", sw, sh, sc, "", { bg = rgb(250, 250, 252), glow = 1.25, d = 0.02 })
			K:text("FfKioskTop", sw, sh * 0.13, sc * CF(0, sh * 0.435, 0.022), "주문하실 메뉴를 선택하세요", { fg = WHITE, bg = accent, glow = 1.3, font = F.GothamBold, d = 0.004 })
			local cols = tiles or { rgb(214, 140, 60), rgb(200, 30, 36), rgb(250, 196, 40), rgb(90, 170, 60), rgb(150, 90, 50), rgb(60, 120, 200) }
			if not ctx.low then
				for i = 0, 5 do
					local cx = (i % 2 - 0.5) * sw * 0.46
					local cy = sh * 0.24 - math.floor(i / 2) * sh * 0.22
					K:text("FfKioskTile", sw * 0.42, sh * 0.18, sc * CF(cx, cy, 0.022), "", { bg = cols[i % #cols + 1], glow = 1.1, d = 0.004 })
				end
			end
			K:text("FfKioskPay", sw * 0.9, sh * 0.1, sc * CF(0, -sh * 0.43, 0.022), "결제하기", { fg = WHITE, bg = rgb(30, 30, 34), glow = 1.2, font = F.GothamBlack, d = 0.004 })
			-- 카드 단말 · NFC · 영수증
			local py = sy - sh / 2 - 0.45
			K:box("FfKioskCard", V3(0.6, 0.36, 0.1), base * CF(-w * 0.18, py, fz + 0.05), L.of(20, 20, 22))
			K:box("FfKioskCardSlot", V3(0.46, 0.04, 0.02), base * CF(-w * 0.18, py - 0.08, fz + 0.11), L.of(70, 70, 74))
			K:text("FfKioskNFC", 0.36, 0.2, base * CF(w * 0.2, py, fz + 0.01), "IC · NFC", { fg = rgb(120, 220, 255), bg = rgb(20, 24, 30), glow = 1.2, font = F.GothamBold, d = 0.01 })
			K:box("FfKioskReceipt", V3(0.5, 0.04, 0.02), base * CF(0, py - 0.45, fz + 0.01), L.of(20, 20, 22))
			K:text("FfKioskReceiptLbl", 0.6, 0.12, base * CF(0, py - 0.58, fz + 0.005), "영수증", { fg = rgb(200, 200, 200), font = F.GothamBold, d = 0.004 })
			-- 뒷면: 밝은 서비스 커버 · 통풍 슬롯 · 안내 스티커 · 전원선
			local bk = base * ANG(0, PI, 0)
			K:plate("FfKioskBackCover", w - 0.26, h * 0.62, 0.012, bk * CF(0, h * 0.52, fz - 0.01), L.of(86, 88, 94, M.Metal))
			if not ctx.low then
				for i = 0, 4 do
					K:plate("FfKioskVent", w * 0.5, 0.04, 0.008, bk * CF(0, h * 0.78 - i * 0.12, fz), L.of(30, 30, 34))
				end
				K:text("FfKioskBackSticker", w * 0.6, 0.32, bk * CF(0, h * 0.42, fz + 0.002), "셀프 주문 키오스크\n주문은 앞 화면에서", { fg = rgb(40, 40, 44), bg = rgb(236, 236, 232), font = F.GothamBold, d = 0.004 })
				K:seg("FfKioskCable", (bk * CF(w * 0.3, 0.6, fz + 0.03)).Position, (bk * CF(w * 0.3, 0.03, fz + 0.3)).Position, 0.06, L.black)
			end
		end)
		Scan.hide(K.hidden, r.part)
	end
	if scr then
		Scan.hide(K.hidden, scr.part)
	end
end

-- 금지 구역: 주방 패스 앞, 키오스크 · 카운터 앞, 입구 -> 각 서비스 지점 동선, 화장실 문 앞, NPC 2 스터드
local function setupZones(ctx: any)
	local V = ctx.V
	local doorIn = V3(V.door.x, 0, V.z1 - 2.6)
	local targets = {}
	for _, nm in { "KitchenPass", "PassLedge" } do
		for _, r in V.byName[nm] or {} do
			addNo(ctx, V3(r.min.X - 1.0, 0.05, V.z0 - 0.5), V3(r.max.X + 1.0, 8, math.max(r.max.Z, V.z0) + 3.2))
			table.insert(targets, V3(r.c.X, 0, math.max(r.max.Z, V.z0) + 2.5))
		end
	end
	for _, nm in { "OrderKiosk", "KioskScreen", "PosBase" } do
		for _, r in V.byName[nm] or {} do
			addNo(ctx, V3(r.min.X - 1.2, 0.05, r.min.Z - 2.6), V3(r.max.X + 1.2, 8, r.max.Z + 2.6))
			table.insert(targets, V3(r.c.X, 0, r.c.Z))
		end
	end
	for _, g in V.counters do
		local alongX = (g.max.X - g.min.X) >= (g.max.Z - g.min.Z)
		-- 카운터 뒤 (직원 쪽 ~ 벽): 바닥 소품 금지 (벽 선반 · 6.5 위만 허용)
		if alongX then
			if g.min.Z - V.z0 < 8 then
				addNo(ctx, V3(g.min.X - 0.6, 0.05, V.z0 - 0.5), V3(g.max.X + 0.6, 6.5, g.min.Z + 0.05))
			end
		else
			local cx = (g.min.X + g.max.X) / 2
			if cx < 0 and g.min.X - V.x0 < 8 then
				addNo(ctx, V3(V.x0 - 0.5, 0.05, g.min.Z - 0.6), V3(g.min.X + 0.05, 6.5, g.max.Z + 0.6))
			elseif cx >= 0 and V.x1 - g.max.X < 8 then
				addNo(ctx, V3(g.max.X - 0.05, 0.05, g.min.Z - 0.6), V3(V.x1 + 0.5, 6.5, g.max.Z + 0.6))
			end
		end
		if alongX then
			addNo(ctx, V3(g.min.X - 0.5, 0.05, g.max.Z), V3(g.max.X + 0.5, 8, g.max.Z + 2.8))
			table.insert(targets, V3((g.min.X + g.max.X) / 2, 0, g.max.Z + 1.5))
		else
			local cx = (g.min.X + g.max.X) / 2
			if cx > 0 then
				addNo(ctx, V3(g.min.X - 2.8, 0.05, g.min.Z - 0.5), V3(g.min.X, 8, g.max.Z + 0.5))
			else
				addNo(ctx, V3(g.max.X, 0.05, g.min.Z - 0.5), V3(g.max.X + 2.8, 8, g.max.Z + 0.5))
			end
		end
	end
	for _, nm in { "DoorLeaf", "StaffDoor" } do
		for _, r in V.byName[nm] or {} do
			local p = V3(r.c.X, 0, r.c.Z)
			if r.size.X >= r.size.Z then
				p = V3(r.c.X, 0, r.c.Z + (if r.c.Z < 0 then 2.4 else -2.4))
			else
				p = V3(r.c.X + (if r.c.X < 0 then 2.4 else -2.4), 0, r.c.Z)
			end
			addNo(ctx, V3(r.min.X - 0.6, 0.05, r.min.Z - 0.6), V3(r.max.X + 0.6, 8, r.max.Z + 0.6))
			table.insert(targets, p)
		end
	end
	-- 맵 냉장고 · 정수기 · 셀프바 앞
	for _, nm in { "FridgeDoor", "Purifier", "SelfTop", "WaterStand", "SelfCounter", "BrothUrn", "OpenChiller" } do
		for _, r in V.byName[nm] or {} do
			addNo(ctx, r.min - V3(1.2, 0, 1.2), r.max + V3(1.2, 0, 1.2))
		end
	end
	for _, t in targets do
		corridor(ctx, doorIn, t, 2.8)
	end
	-- NPC 모형 (맵 고정 직원 · 분식 이모): 2.5 스터드 비움 (Kit keep 으로 넣어 모든 새 파트가 피함)
	for _, r in V.byName.HumanoidRootPart or {} do
		V:addKeep(V3(r.min.X - 2.5, 0.05, r.min.Z - 2.5), V3(r.max.X + 2.5, 7, r.max.Z + 2.5), "npc")
	end
end

-- 영업 안내 소품 묶음 (영업시간 · 와이파이 · 결제 · 원산지 · 스티커)
local function infoSet(ctx: any, o: any)
	local K = ctx.K
	local walls = o.walls or { "right", "left", "back" }
	local dcf = wallSpot(ctx, walls, 2.0, 4.2 + 0.0, 6.6, o.originPrefer)
	if dcf then
		originBoard(ctx, dcf, 1.8, o.origin)
	end
	local d2 = wallSpot(ctx, walls, 1.5, 4.6, 5.6, o.hoursPrefer)
	if d2 then
		notice(ctx, d2, 1.4, 0.9, o.hours or "영업시간\n11:00 - 24:00", { bg = rgb(250, 250, 246), font = F.GothamBold })
	end
	local d3 = wallSpot(ctx, walls, 1.4, 4.0, 4.7, o.wifiPrefer)
	if d3 then
		wifiSign(ctx, d3, o.ssid or "SHOP_5G", o.pw or "12345678")
	end
	local d4 = wallSpot(ctx, walls, 2.6, 3.7, 4.3, o.stickerPrefer)
	if d4 then
		local items = o.stickers or {
			{ "카드 · 페이\n결제 가능", rgb(40, 90, 200) },
			{ "현금영수증\n발행", rgb(60, 60, 64) },
			{ "포장 주문\n환영", rgb(220, 60, 40) },
		}
		stickerRow(ctx, d4, items, 0.78)
	end
end

-- 바닥에 세우는 낮은 장식장 몸체 (상판 · 문짝 · 걸레받이). 반환 상판 높이
local function cabinet(ctx: any, pcf: CFrame, w: number, h: number, d: number, bodyL: any, topL: any, o: any?): number
	local K = ctx.K
	local oo: any = o or {}
	K:box("FfCabBody", V3(w, h - 0.36, d - 0.06), pcf * CF(0, 0.3 + (h - 0.36) / 2 - 0.15, -0.03), bodyL)
	K:box("FfCabKick", V3(w - 0.1, 0.3, d - 0.2), pcf * CF(0, 0.15, -0.1), L.black)
	K:box("FfCabTop", V3(w + 0.06, 0.12, d + 0.04), pcf * CF(0, h - 0.06, 0), topL)
	local nd = oo.doors or math.max(1, math.floor(w / 1.2))
	if not ctx.low then
		local dw = (w - 0.1) / nd
		for i = 1, nd do
			local x = -w / 2 + 0.05 + dw * (i - 0.5)
			K:plate("FfCabDoorGap", 0.03, h - 0.62, 0.012, pcf * CF(x + dw / 2, 0.3 + (h - 0.62) / 2, d / 2 - 0.06), L.of(40, 40, 40))
			K:box("FfCabHandle", V3(0.05, 0.42, 0.06), pcf * CF(x + (if i % 2 == 0 then -dw / 2 + 0.16 else dw / 2 - 0.16), h - 0.75, d / 2 - 0.03), oo.handle or L.chrome)
		end
	end
	return h
end

-- 치킨집 소품 ----------------------------------------------------------------------------------------
local function beerMug(K: any, base: CFrame, full: boolean, frost: boolean?)
	local gl = { c = if frost then rgb(232, 240, 244) else rgb(220, 232, 236), m = M.Glass, t = if frost then 0.25 else 0.5, r = 0.1 }
	K:vcyl("FfMug", 0.52, 0.3, base * CF(0, 0.26, 0), gl)
	if full then
		K:vcyl("FfMugBeer", 0.4, 0.26, base * CF(0, 0.2, 0), { c = rgb(236, 168, 30), m = M.Glass, t = 0.15 })
		K:vcyl("FfMugFoam", 0.1, 0.27, base * CF(0, 0.46, 0), L.of(252, 250, 244))
	end
	K:bar("FfMugHandle", (base * CF(0.15, 0.4, 0)).Position, (base * CF(0.26, 0.26, 0)).Position, 0.05, 0.05, gl)
	K:bar("FfMugHandle", (base * CF(0.26, 0.26, 0)).Position, (base * CF(0.15, 0.1, 0)).Position, 0.05, 0.05, gl)
end

-- 생맥주 셀프 · 서빙 스테이션 (냉각 캐비닛 + 맥주 타워 + 잔 냉동고 + 잔)
local function beerStation(ctx: any, pcf: CFrame, w: number)
	local K = ctx.K
	local P = ctx.pal
	local h, d = 3.3, 1.5
	local top = cabinet(ctx, pcf, w, h, d, L.of(60, 62, 66, M.Metal), L.of(196, 200, 204, M.Metal, { r = 0.1 }), { doors = 2 })
	-- 왼쪽 잔 냉동고 유리문 (성에 낀 잔)
	local gx = -w / 2 + 0.75
	local door = K:group("FfFrosterDoor", function()
		K:plate("FfFrosterGlass", 1.2, 1.8, 0.03, pcf * CF(gx, 1.4, d / 2 + 0.1), { c = rgb(220, 236, 244), m = M.Glass, t = 0.5, r = 0.15 })
		K:plate("FfFrosterFrame", 1.26, 0.08, 0.16, pcf * CF(gx, 2.31, d / 2 - 0.03), L.of(40, 42, 46, M.Metal))
		K:plate("FfFrosterFrame", 1.26, 0.08, 0.16, pcf * CF(gx, 0.49, d / 2 - 0.03), L.of(40, 42, 46, M.Metal))
		K:plate("FfFrosterFrame", 0.08, 1.74, 0.16, pcf * CF(gx - 0.59, 1.4, d / 2 - 0.03), L.of(40, 42, 46, M.Metal))
		K:plate("FfFrosterFrame", 0.08, 1.74, 0.16, pcf * CF(gx + 0.59, 1.4, d / 2 - 0.03), L.of(40, 42, 46, M.Metal))
		K:plate("FfFrosterHandle", 0.06, 0.9, 0.08, pcf * CF(gx + 0.48, 1.4, d / 2 + 0.13), L.chrome)
	end)
	K:plate("FfFrosterInner", 1.1, 1.7, 0.01, pcf * CF(gx, 1.4, d / 2 - 0.055), L.of(230, 242, 250))
	local hp = door:FindFirstChild("FfFrosterHandle") :: BasePart?
	if hp and hp.Parent and pickAnchor(K, { hp }) then
		Interact.swing(K, door, (K.cf * pcf * CF(gx - 0.6, 0, d / 2)).Position, K.cf.UpVector, -1.5, { object = "잔 냉동고", openText = "문 열기", closeText = "문 닫기" })
	end
	if not ctx.low then
		for row = 0, 1 do
			for i = -1, 1 do
				K:vcyl("FfFrostMug", 0.44, 0.24, pcf * CF(gx + i * 0.34, 0.8 + row * 0.8, d / 2 - 0.05), { c = rgb(240, 246, 250), m = M.Glass, t = 0.25 })
			end
		end
	end
	-- 맥주 타워 (서리 낀 크롬 기둥 + T 바 + 탭 2개 + 손잡이)
	local tx = w / 2 - 1.0
	local tb = pcf * CF(tx, top, -0.1)
	K:disc("FfTowerBase", 0.5, 0.06, tb * CF(0, 0.03, 0), L.chrome)
	K:vcyl("FfTowerCol", 1.25, 0.24, tb * CF(0, 0.66, 0), { c = rgb(224, 232, 238), m = M.Metal, r = 0.2 })
	K:vcyl("FfTowerFrost", 0.7, 0.27, tb * CF(0, 0.75, 0), { c = rgb(240, 246, 250), m = M.Ice, t = 0.25 })
	K:cyl("FfTowerBar", 1.1, 0.16, tb * CF(0, 1.3, 0), L.chrome)
	for _, sx in { -1, 1 } do
		local tap = tb * CF(sx * 0.4, 1.3, 0)
		K:cyl("FfTapSpout", 0.24, 0.07, tap * CF(0, -0.02, 0.12) * ANG(0, PI / 2, 0), L.chrome)
		K:vcyl("FfTapNozzle", 0.14, 0.05, tap * CF(0, -0.1, 0.22), L.chrome)
		K:vcyl("FfTapHandle", 0.5, 0.08, tap * CF(0, 0.32, 0.12), L.black)
		K:vcyl("FfTapKnob", 0.16, 0.13, tap * CF(0, 0.6, 0.12), if sx < 0 then L.of(30, 90, 190) else L.of(30, 140, 70))
	end
	K:box("FfDripTray", V3(1.2, 0.06, 0.42), tb * CF(0, 0.03, 0.3), L.of(60, 62, 66, M.Metal))
	if not ctx.low then
		K:box("FfDripGrate", V3(1.12, 0.012, 0.36), tb * CF(0, 0.066, 0.3), L.of(150, 154, 158, M.DiamondPlate))
	end
	-- 엎어 놓은 500cc 잔 (고무 매트 위)
	local mx = -w / 2 + 0.75
	K:box("FfBarMat", V3(1.2, 0.03, 0.8), pcf * CF(mx, top + 0.015, 0.05), L.of(30, 30, 32, M.Rubber))
	local n = if ctx.low then 2 else 6
	for i = 1, n do
		local col = (i - 1) % 3
		local row = math.floor((i - 1) / 3)
		local base = pcf * CF(mx - 0.36 + col * 0.36, top + 0.03, -0.18 + row * 0.36)
		K:vcyl("FfMugUp", 0.5, 0.3, base * CF(0, 0.25, 0), { c = rgb(222, 234, 238), m = M.Glass, t = 0.45 })
	end
	-- 가격 꽂이
	local sp = pcf * CF(0.1, top, 0.4)
	K:box("FfPriceStandBase", V3(0.6, 0.04, 0.24), sp * CF(0, 0.02, 0), L.acrylicWhite)
	K:text("FfPriceStand", 0.56, 0.4, sp * CF(0, 0.25, 0) * ANG(math.rad(-10), 0, 0), "생맥주\n500cc " .. priceIn(ctx.signs, "생맥주", "4,500"), { fg = rgb(30, 30, 30), bg = rgb(255, 214, 60), d = 0.02, font = F.GothamBlack })
	-- 캐비닛 앞 브랜드 띠
	K:text("FfBeerBand", w - 0.3, 0.32, pcf * CF(0, h - 0.4, d / 2 + 0.005), "생맥주  DRAFT BEER", { fg = WHITE, bg = P.accent, font = F.GothamBlack, d = 0.01 })
end

-- 셀프 코너 (치킨무 · 소스 · 물티슈 · 비닐장갑 · 앞치마)
local function selfBar(ctx: any, pcf: CFrame, w: number, o: any?)
	local K = ctx.K
	local P = ctx.pal
	local oo: any = o or {}
	local h, d = 3.1, 1.3
	local top = cabinet(ctx, pcf, w, h, d, oo.body or L.with(P.wood or L.oak, {}), L.marbleWhite, { doors = 2 })
	local y = top
	-- 치킨무 통 (반투명 사각 통 + 하얀 무 + 집게)
	local mu = pcf * CF(-w / 2 + 0.55, y, 0)
	K:box("FfRadishTub", V3(0.75, 0.42, 0.6), mu * CF(0, 0.21, 0), { c = rgb(236, 244, 240), m = M.Glass, t = 0.4 })
	K:box("FfRadish", V3(0.66, 0.3, 0.52), mu * CF(0, 0.17, 0), L.of(250, 250, 238))
	K:box("FfRadishLid", V3(0.8, 0.04, 0.64), mu * CF(-0.05, 0.44, -0.05) * ANG(0, 0.12, 0), L.of(230, 70, 60, M.Plastic))
	K:bar("FfTongs", (mu * CF(0.25, 0.46, 0.1)).Position, (mu * CF(0.45, 0.48, 0.42)).Position, 0.05, 0.03, L.steel)
	if not ctx.low then
		K:text("FfRadishLabel", 0.5, 0.16, mu * CF(0, 0.24, 0.305), "치킨무", { fg = WHITE, bg = rgb(220, 60, 50), d = 0.005, font = F.GothamBlack })
	end
	-- 소스 통 3 (양념 · 머스터드 · 마요)
	for i, c in { rgb(190, 40, 30), rgb(240, 196, 40), rgb(246, 244, 236) } do
		local b = pcf * CF(-w / 2 + 1.15 + (i - 1) * 0.26, y, -0.25)
		K:vcyl("FfSauceBottle", 0.5, 0.2, b * CF(0, 0.25, 0), L.of(c.R * 255, c.G * 255, c.B * 255, M.Plastic))
		K:vcyl("FfSauceTip", 0.14, 0.07, b * CF(0, 0.57, 0), L.of(240, 240, 240, M.Plastic))
	end
	-- 물티슈 더미 + 비닐장갑 상자 + 종이컵
	if w > 2.2 then
		local wt = pcf * CF(w / 2 - 0.55, y, -0.2)
		for i = 0, 2 do
			K:box("FfWetWipe", V3(0.5, 0.06, 0.36), wt * CF(0, 0.03 + i * 0.065, 0) * ANG(0, i * 0.2, 0), L.of(250, 250, 250))
			if not ctx.low then
				K:box("FfWetWipeBand", V3(0.2, 0.065, 0.37), wt * CF(0, 0.03 + i * 0.065, 0) * ANG(0, i * 0.2, 0), L.of(60, 150, 210))
			end
		end
		local gb = pcf * CF(w / 2 - 0.55, y, 0.3)
		K:box("FfGloveBox", V3(0.6, 0.3, 0.32), gb * CF(0, 0.15, 0), L.of(250, 250, 250))
		K:text("FfGloveLabel", 0.5, 0.18, gb * CF(0, 0.15, 0.165), "위생장갑", { fg = rgb(30, 90, 190), d = 0.005, font = F.GothamBlack })
		K:vcyl("FfCupStack", 0.7, 0.26, pcf * CF(0.25, y + 0.35, -0.3), L.of(250, 250, 246))
		K:vcyl("FfCupStackRim", 0.03, 0.29, pcf * CF(0.25, y + 0.7, -0.3), L.of(240, 240, 236))
	end
	-- 수저통 (스테인리스 원통 + 숟가락 · 젓가락)
	local sj = pcf * CF(0.25, y, 0.25)
	K:vcyl("FfSpoonPot", 0.5, 0.3, sj * CF(0, 0.25, 0), L.steel)
	if not ctx.low then
		for i = 0, 4 do
			local a = i * 1.25
			K:seg("FfSpoon", (sj * CF(math.cos(a) * 0.06, 0.45, math.sin(a) * 0.06)).Position, (sj * CF(math.cos(a) * 0.12, 0.85, math.sin(a) * 0.12)).Position, 0.03, L.chrome)
		end
	end
	-- 벽 안내판 + 앞치마 걸이
	local wcf = pcf * CF(0, 0, -d / 2 - 0.06)
	local sgn = wcf * CF(0, h + 1.15, 0)
	K:text("FfSelfSign", math.min(w - 0.2, 2.4), 0.55, sgn, "셀프 코너", { fg = WHITE, bg = P.accent, font = F.GothamBlack, d = 0.04 })
	K:text("FfSelfSign2", math.min(w - 0.2, 2.4), 0.3, sgn * CF(0, -0.45, 0), "치킨무 · 소스 · 물티슈 · 앞치마", { fg = rgb(40, 30, 20), bg = rgb(250, 246, 236), font = F.GothamBold, d = 0.04 })
	if not ctx.low and w > 2.2 then
		local hr = wcf * CF(0, h + 0.38, 0)
		K:plate("FfApronRail", w - 0.4, 0.12, 0.06, hr, L.walnut)
		for i, c in { rgb(30, 30, 32), rgb(196, 40, 36) } do
			local x = -w / 2 + 0.6 + (i - 1) * 0.65
			K:plate("FfApronHook", 0.05, 0.12, 0.16, hr * CF(x, 0, 0.06), L.chrome)
			K:plate("FfApron", 0.5, 0.75, 0.03, hr * CF(x, -0.42, 0.1), { c = c, m = M.Fabric })
			K:plate("FfApronStrap", 0.3, 0.08, 0.03, hr * CF(x, -0.02, 0.1), { c = c, m = M.Fabric })
		end
	end
end

-- 포장 박스 랙 (철제 선반 + 치킨 박스 · 1.25L 콜라 · 비닐봉투)
local function boxRack(ctx: any, pcf: CFrame, w: number, brand: string)
	local K = ctx.K
	local P = ctx.pal
	local h, d = 5.2, 1.2
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			K:vcyl("FfRackPost", h, 0.08, pcf * CF(sx * (w / 2 - 0.05), h / 2, sz * (d / 2 - 0.05)), L.chrome)
		end
	end
	for i, y in { 0.3, 1.9, 3.5, 5.0 } do
		K:box("FfRackShelf", V3(w, 0.06, d), pcf * CF(0, y, 0), L.of(200, 204, 208, M.DiamondPlate))
		if i < 4 then
			local n = math.max(1, math.floor((w - 0.2) / 1.05))
			for j = 1, n do
				local x = -w / 2 + 0.1 + (w - 0.2) * (j - 0.5) / n
				if i == 1 and j == n then
					-- 콜라 1.25L 묶음
					for k = 0, 2 do
						K:vcyl("FfColaPet", 1.0, 0.3, pcf * CF(x - 0.32 + k * 0.32, y + 0.53, 0.1), { c = rgb(60, 24, 20), m = M.Plastic, t = 0.1 })
						K:vcyl("FfColaLabel", 0.26, 0.31, pcf * CF(x - 0.32 + k * 0.32, y + 0.5, 0.1), L.of(210, 30, 36))
						K:vcyl("FfColaCap", 0.07, 0.12, pcf * CF(x - 0.32 + k * 0.32, y + 1.06, 0.1), L.of(210, 30, 36))
					end
				else
					local stack = if i == 3 then 2 else 4
					for k = 0, stack - 1 do
						K:box("FfChickenBox", V3(0.95, 0.34, 0.95), pcf * CF(x, y + 0.2 + k * 0.35, 0) * ANG(0, (k % 2) * 0.05, 0), L.of(250, 248, 242, M.Cardboard))
						K:box("FfChickenBoxBand", V3(0.96, 0.12, 0.96), pcf * CF(x, y + 0.24 + k * 0.35, 0) * ANG(0, (k % 2) * 0.05, 0), pl(P.accent))
					end
					if not ctx.low then
						K:text("FfChickenBoxLogo", 0.7, 0.14, pcf * CF(x, y + 0.2 + (stack - 1) * 0.35 + 0.08, 0.485), brand, { fg = P.accent, font = F.GothamBlack, d = 0.004 })
					end
				end
			end
		end
	end
	-- 비닐봉투 롤
	if not ctx.low then
		K:cyl("FfBagRoll", w - 0.5, 0.3, pcf * CF(0, 4.6, 0.2), L.of(236, 236, 232, M.Plastic))
	end
end

-- 닭 마스코트 입간판 (FRP 조형: 노란 몸 · 빨간 볏 · 앞치마 · 손에 든 안내판)
local function mascot(ctx: any, pcf: CFrame, sign: string)
	local K = ctx.K
	local P = ctx.pal
	local yel = L.of(255, 206, 60, M.SmoothPlastic, { r = 0.05 })
	K:disc("FfMascotBase", 1.5, 0.12, pcf * CF(0, 0.06, 0), L.of(40, 40, 42))
	for _, sx in { -1, 1 } do
		K:vcyl("FfMascotLeg", 0.6, 0.16, pcf * CF(sx * 0.25, 0.42, 0), L.of(240, 140, 40))
		K:ell("FfMascotFoot", V3(0.36, 0.14, 0.5), pcf * CF(sx * 0.25, 0.16, 0.12), L.of(240, 140, 40))
	end
	K:ell("FfMascotBody", V3(1.35, 1.7, 1.2), pcf * CF(0, 1.55, 0), yel)
	K:ell("FfMascotBelly", V3(0.95, 1.1, 0.4), pcf * CF(0, 1.4, 0.45), L.of(255, 236, 170))
	K:plate("FfMascotApron", 0.8, 0.7, 0.04, pcf * CF(0, 1.25, 0.62), pl(P.accent))
	K:text("FfMascotApronText", 0.7, 0.3, pcf * CF(0, 1.3, 0.665), "치킨", { fg = WHITE, font = F.GothamBlack, d = 0.004 })
	K:ball("FfMascotHead", 1.05, pcf * CF(0, 2.85, 0.05), yel)
	for i = -1, 1 do
		K:ell("FfMascotComb", V3(0.18, 0.36, 0.3), pcf * CF(0, 3.42 + (1 - math.abs(i)) * 0.06, i * 0.16), L.of(220, 40, 30))
	end
	K:wedge("FfMascotBeak", V3(0.22, 0.16, 0.3), pcf * CF(0, 2.78, 0.66) * ANG(0, PI, 0), L.of(250, 150, 40))
	K:ell("FfMascotWattle", V3(0.14, 0.22, 0.1), pcf * CF(0, 2.56, 0.56), L.of(220, 40, 30))
	for _, sx in { -1, 1 } do
		K:ball("FfMascotEye", 0.24, pcf * CF(sx * 0.2, 3.0, 0.5), L.white)
		K:ball("FfMascotPupil", 0.12, pcf * CF(sx * 0.2, 3.0, 0.6), L.black)
		K:ell("FfMascotCheek", V3(0.18, 0.1, 0.04), pcf * CF(sx * 0.32, 2.78, 0.5), L.of(250, 140, 140))
		-- 날개 (팔)
		K:ell("FfMascotWing", V3(0.3, 0.9, 0.6), pcf * CF(sx * 0.7, 1.75, 0.1) * ANG(0, 0, sx * 0.35), yel)
	end
	-- 손에 든 안내판
	K:bar("FfMascotStick", (pcf * CF(0.78, 1.4, 0.4)).Position, (pcf * CF(0.9, 2.6, 0.45)).Position, 0.06, 0.06, L.walnut)
	K:text("FfMascotSign", 1.0, 0.7, pcf * CF(0.95, 2.9, 0.5) * ANG(0, -0.25, 0), sign, { fg = rgb(40, 24, 10), bg = rgb(255, 250, 236), font = F.GothamBlack, d = 0.05 })
end

-- 맥주 · 치킨 네온 (맥주잔 네온관 그림 + 글자)
local function chimaekNeon(ctx: any, dcf: CFrame, w: number, txt: string, c: Color3, c2: Color3)
	local s = 0.55
	local x0 = -w / 2 + 0.55
	local shapes = {
		{ x0 - s * 0.45, -s, x0 + s * 0.45, -s, c2 },
		{ x0 - s * 0.45, -s, x0 - s * 0.5, s * 0.8, c2 },
		{ x0 + s * 0.45, -s, x0 + s * 0.5, s * 0.8, c2 },
		{ x0 - s * 0.6, s * 0.8, x0 + s * 0.6, s * 0.8, WHITE },
		{ x0 + s * 0.5, s * 0.4, x0 + s * 0.85, s * 0.3, c2 },
		{ x0 + s * 0.85, s * 0.3, x0 + s * 0.85, -s * 0.4, c2 },
		{ x0 + s * 0.85, -s * 0.4, x0 + s * 0.48, -s * 0.5, c2 },
	}
	return neonSign(ctx, dcf, w, 1.0, txt, c, { shapes = shapes, object = "네온사인", textX = 0.6, textW = w - 1.4 })
end

local CHICKEN_DRINKS = {
	{ rgb(200, 24, 32), "can", rgb(200, 24, 32) }, -- 콜라
	{ rgb(40, 150, 70), "can" }, -- 사이다
	{ rgb(30, 70, 170), "can" }, -- 맥주 (블루)
	{ rgb(20, 20, 22), "can" }, -- 제로
	{ rgb(36, 110, 50), "soju", rgb(240, 250, 240) }, -- 소주
	{ rgb(60, 120, 40), "bottle", rgb(30, 110, 40) }, -- 맥주 (녹색 병)
	{ rgb(236, 120, 30), "can" }, -- 환타
	{ rgb(200, 230, 240), "pet", rgb(40, 120, 210) }, -- 생수
}

local function baseballChannels(): { any }
	return {
		{ "야구", rgb(30, 100, 46), {
			{ "b", 0, -0.18, 0.34, 0.34, rgb(150, 100, 56), PI / 4 },
			{ "b", 0, -0.18, 0.2, 0.2, rgb(40, 120, 54), PI / 4 },
			{ "b", 0, -0.42, 0.04, 0.06, rgb(240, 240, 240), PI / 4 },
			{ "b", 0.12, -0.18, 0.04, 0.06, rgb(240, 240, 240), PI / 4 },
			{ "b", 0, 0.38, 1.0, 0.18, rgb(16, 26, 70) },
		}, "롯데 3 : 2 두산   7회말 1사 2루", "사직야구장 LIVE · 2026 KBO" },
		{ "뉴스", rgb(20, 46, 110), {
			{ "b", 0, -0.2, 0.7, 0.18, rgb(40, 40, 50) },
			{ "e", 0, 0.05, 0.12, 0.2, rgb(220, 180, 150) },
			{ "b", 0, -0.08, 0.22, 0.16, rgb(30, 30, 40) },
			{ "b", 0, -0.42, 1.0, 0.12, rgb(200, 24, 32) },
		}, "부산 MBC 뉴스", "[속보] 광안리 불꽃축제 11월 8일 개최" },
		{ "먹방", rgb(240, 160, 50), {
			{ "e", 0, -0.12, 0.5, 0.36, rgb(250, 246, 236) },
			{ "e", -0.06, -0.1, 0.24, 0.18, rgb(200, 122, 44) },
			{ "e", 0.08, -0.06, 0.22, 0.16, rgb(176, 98, 32) },
			{ "e", 0.04, -0.16, 0.2, 0.14, rgb(170, 40, 24) },
		}, "치킨 먹방 특집", "오늘 밤 야식은 반반 치킨!" },
		{ "날씨", rgb(60, 140, 210), {
			{ "e", -0.25, 0.0, 0.22, 0.38, rgb(255, 210, 60) },
			{ "e", 0.1, -0.05, 0.3, 0.22, rgb(250, 250, 250) },
			{ "e", 0.22, -0.02, 0.22, 0.18, rgb(250, 250, 250) },
		}, "부산 날씨  맑음 22°C", "광안리 해수욕장 파도 0.5m" },
	}
end

-- 주방 튀김기 · 후드 (맵 Fryer / Hood 자리 그대로 스테인리스 덮개: GwShop 주방 창으로 보임)
local function fryerOverlay(ctx: any)
	local K, V = ctx.K, ctx.V
	local steel = L.of(196, 200, 204, M.Metal, { r = 0.1 })
	for _, r in V.byName.Fryer or {} do
		local w, h, d = r.size.X, r.size.Y, r.size.Z
		-- 정면 = 방(+Z) 쪽
		local base = CF(r.c.X, r.min.Y, r.c.Z)
		K:free(function()
			K:box("FfFryerBody", V3(w, h - 0.12, d), base * CF(0, (h - 0.12) / 2, 0), steel)
			K:box("FfFryerTop", V3(w, 0.12, d), base * CF(0, h - 0.06, 0), L.of(170, 174, 178, M.Metal))
			K:box("FfFryerKick", V3(w - 0.1, 0.4, 0.04), base * CF(0, 0.2, d / 2 + 0.01), L.black)
			K:box("FfFryerPanel", V3(w - 0.2, 0.7, 0.04), base * CF(0, h - 0.55, d / 2 + 0.01), L.of(40, 42, 46))
			for i = -1, 1 do
				K:cyl("FfFryerKnob", 0.08, 0.22, base * CF(i * w * 0.25, h - 0.55, d / 2 + 0.06) * ANG(0, PI / 2, 0), L.black)
			end
			K:box("FfFryerLed", V3(0.08, 0.08, 0.02), base * CF(w / 2 - 0.25, h - 0.42, d / 2 + 0.04), neon(rgb(255, 60, 40)))
			K:box("FfFryerLed", V3(0.08, 0.08, 0.02), base * CF(w / 2 - 0.4, h - 0.42, d / 2 + 0.04), neon(rgb(60, 230, 120)))
			K:box("FfFryerDoorGap", V3(0.03, h - 1.4, 0.02), base * CF(0, (h - 1.4) / 2 + 0.45, d / 2 + 0.01), L.of(90, 92, 96))
			K:text("FfFryerLabel", w * 0.5, 0.18, base * CF(0, h - 1.05, d / 2 + 0.02), "가스 튀김기 · 18L", { fg = rgb(40, 40, 40), bg = rgb(230, 232, 234), d = 0.005, font = F.GothamBold })
		end)
		Scan.hide(K.hidden, r.part)
	end
	for _, r in V.byName.FryerOil or {} do
		K:free(function()
			K:box("FfFryerOil", r.size, CF(r.c), { c = rgb(214, 150, 40), m = M.Glass, t = 0.12, r = 0.2 })
			K:box("FfFryerRim", V3(r.size.X + 0.1, 0.06, 0.06), CF(r.c.X, r.max.Y, r.max.Z + 0.03), L.chrome)
			K:box("FfFryerRim", V3(r.size.X + 0.1, 0.06, 0.06), CF(r.c.X, r.max.Y, r.min.Z - 0.03), L.chrome)
		end)
		Scan.hide(K.hidden, r.part)
	end
	for _, r in V.byName.FryBasket or {} do
		K:free(function()
			local c = CF(r.c)
			K:box("FfBasketMesh", r.size - V3(0.04, 0.04, 0.04), c, { c = rgb(170, 174, 178), m = M.DiamondPlate, t = 0.25 })
			K:box("FfBasketRim", V3(r.size.X, 0.05, 0.05), c * CF(0, r.size.Y / 2 - 0.03, r.size.Z / 2), L.chrome)
			K:box("FfBasketRim", V3(r.size.X, 0.05, 0.05), c * CF(0, r.size.Y / 2 - 0.03, -r.size.Z / 2), L.chrome)
			K:box("FfBasketRim", V3(0.05, 0.05, r.size.Z), c * CF(r.size.X / 2, r.size.Y / 2 - 0.03, 0), L.chrome)
			K:box("FfBasketRim", V3(0.05, 0.05, r.size.Z), c * CF(-r.size.X / 2, r.size.Y / 2 - 0.03, 0), L.chrome)
			-- 튀김 중인 치킨 몇 조각
			for i = 0, 2 do
				K:ell("FfFryingChicken", V3(0.3, 0.2, 0.26), c * CF((i - 1) * 0.26, 0.12, (i % 2) * 0.2 - 0.1), L.of(206, 140, 56))
			end
		end)
		Scan.hide(K.hidden, r.part)
	end
	for _, r in V.byName.BasketHandle or {} do
		K:free(function()
			K:box("FfBasketHandle", r.size, CF(r.c), L.of(30, 30, 32, M.Rubber))
		end)
		Scan.hide(K.hidden, r.part)
	end
	for _, r in V.byName.Hood or {} do
		K:free(function()
			local c = CF(r.c)
			K:box("FfHoodBox", V3(r.size.X, r.size.Y * 0.55, r.size.Z), c * CF(0, r.size.Y * 0.225, 0), steel)
			K:wedge("FfHoodSlope", V3(r.size.X, r.size.Y * 0.45, 0.5), c * CF(0, -r.size.Y * 0.275, r.size.Z / 2 - 0.25) * ANG(0, PI, 0), steel)
			K:box("FfHoodBack", V3(r.size.X, r.size.Y * 0.45, r.size.Z - 0.5), c * CF(0, -r.size.Y * 0.275, -0.25), L.of(150, 154, 158, M.Metal))
			local n = math.max(3, math.floor(r.size.X / 1.0))
			for i = 1, n do
				K:box("FfHoodFilter", V3(r.size.X / n - 0.1, 0.03, r.size.Z - 0.7), c * CF(-r.size.X / 2 + (i - 0.5) * r.size.X / n, -r.size.Y / 2 + 0.03, -0.2), L.of(120, 124, 128, M.DiamondPlate))
			end
			K:box("FfHoodLamp", V3(r.size.X - 0.6, 0.04, 0.12), c * CF(0, -r.size.Y / 2 + 0.02, r.size.Z / 2 - 0.35), neon(rgb(255, 236, 200)))
		end)
		Scan.hide(K.hidden, r.part)
	end
	for _, nm in { "HoodFilter", "FryerDial" } do
		for _, r in V.byName[nm] or {} do
			Scan.hide(K.hidden, r.part)
		end
	end
end

local function chickenBuild(ctx: any)
	local K, V, S = ctx.K, ctx.V, ctx.S
	local P = ctx.pal
	local tong = ctx.sk == "tongdak"
	local nm = V.name or "치킨"
	if nm == "SideShop" then
		nm = if tong then "옛날통닭" else "치킨"
	end
	local pF = priceIn(ctx.signs, "후라이드", "20,000")
	local pY = priceIn(ctx.signs, "양념", "21,000")
	local pB = priceIn(ctx.signs, "반반", pY)
	-- 벽 위쪽 칠 + 몰딩 (GwShop 은 맵 마감 유지)
	if not ctx.gw then
		local lh = if S.lower then S.lower.h else 0.45
		upperPaint(ctx, { "left", "right" }, lh + 0.08, pl(P.wall, M.Plaster))
		upperPaint(ctx, { "back" }, lh + 0.08, pl(P.wall2, M.Plaster))
		wallBand(ctx, { "left", "right" }, V.H - 0.9, 0.22, 0.05, pl(P.accent))
		if S.lower then
			wallBand(ctx, { "left", "right", "back" }, S.lower.h + 0.04, 0.14, 0.16, if P.key == "red" then L.of(200, 30, 38) else L.darkWood)
		end
		if P.key ~= "red" then
			ceilingBeams(ctx, "x", math.max(2, math.floor(V.D / 3.4)), if P.key == "black" then L.of(30, 28, 26, M.Wood) else L.of(120, 84, 52, M.Wood))
		end
	end
	-- 주방 패스 + 메뉴판
	passDress(ctx, { trim = L.steel, header = "hood", hoodText = if tong then "옛날통닭 · 주방" else "PICK UP · 포장", hoodFg = P.gold, hoodLook = L.of(40, 40, 42, M.Metal), utensil = "basket" })
	menuSignDress(ctx, pl(dark(P.accent, 0.35)), P.gold)
	kioskOverlay(ctx, nm, P.accent, { rgb(200, 122, 44), rgb(170, 40, 24), rgb(222, 150, 66), rgb(236, 168, 30), rgb(200, 30, 36), rgb(250, 196, 40) })
	fryerOverlay(ctx)
	-- 상호작용 벽 장식 먼저 (프롬프트 되는 자리를 차지하게): TV (야구) · 네온
	if V:has("TVBezel") == 0 and V:has("TV") == 0 then
		local tvw = if V.D > 14 then 3.6 else 3.0
		local th = tvw * 9 / 16 + 0.3
		local d = promptSpotStrict(ctx, { "left", "right", "back" }, tvw + 0.3, 6.25, 6.25 + th, { 0, -tvw / 2 + 0.25, tvw / 2 - 0.25 })
		if not d then
			d = wallSpot(ctx, { "left", "right", "back" }, tvw + 0.3, 6.25, 6.25 + th, 0)
		end
		if d then
			tvSet(ctx, d, tvw, baseballChannels(), "TV")
		end
	end
	-- 네온: 프롬프트 되는 자리 (위 -> 눈높이 순, 큰 것 -> 작은 것), 없으면 아무 빈 벽
	local nd, nw = nil, 3.2
	for _, c in { { 3.6, 6.6, 8.2 }, { 2.6, 6.6, 8.2 }, { 3.6, 4.2, 5.6 }, { 2.6, 4.2, 5.6 } } do
		nd = promptSpotStrict(ctx, { "right", "left", "back" }, c[1], c[2], c[3], { 0, -c[1] / 2 + 0.2, c[1] / 2 - 0.2 })
		if nd then
			nw = c[1] - 0.4
			break
		end
	end
	if not nd then
		local fw
		nd, fw = wallSpotFit(ctx, { "right", "left", "back" }, { 3.6, 2.6 }, 6.6, 8.2, 0)
		nw = fw - 0.4
	end
	if nd then
		chimaekNeon(ctx, nd, nw, if tong then "옛날통닭" elseif nw < 3 then "치맥" else "치킨 & 맥주", rgb(255, 120, 170), rgb(255, 200, 60))
	end
	-- 옛날통닭: 벽걸이 선풍기 (좌우 회전, 프롬프트 되면 켜기/끄기)
	if tong then
		for i = 1, 2 do
			local fd = promptSpotStrict(ctx, { "left", "right", "back" }, 1.6, 6.9, 8.5)
			if not fd then
				fd = wallSpot(ctx, { if i == 1 then "right" else "left", if i == 1 then "left" else "right" }, 1.6, 6.9, 8.5, (i * 2 - 3) * 2)
			end
			if fd then
				wallFan(ctx, fd * CF(0, 0.4, 0))
			end
		end
	end
	-- 바닥 소품: 음료 냉장고 · 생맥주 스테이션 · 셀프 코너 · 포장 박스 랙
	placeFridge(ctx, { header = "시원한 음료 · 주류", headerBg = P.accent, items = CHICKEN_DRINKS, brand = "SHOWCASE" })
	local bw = if V.W > 22 then 3.6 else 3.2
	local bpcf, bwn, bu = floorSpot(ctx, { walls = { "back", "left", "right" }, w = bw, h = 4.8, d = 1.5, pref = { back = "left", left = "back", right = "back" }, front = 1.0 })
	if bpcf and bwn and bu and not wallBusy(K, bwn, bu - 1.4, bu + 1.4, 5.3, 7.5) and #spans(ctx, bwn, 5.3, 7.5, 1.0) > 0 then
		markWall(K, bwn, bu - 1.4, bu + 1.4, 5.3, 7.5)
	else
		bwn = nil
	end
	if bpcf then
		beerStation(ctx, bpcf, bw)
	end
	if bpcf and bwn then
		-- 위 벽: 생맥주 포스터
		local wc = bpcf * CF(0, 0, -0.75 - 0.06)
		poster(ctx, wc * CF(0, 6.4, 0), 2.6, 2.0, {
			bg = rgb(20, 60, 140),
			art = artBeer(-0.6, -0.05, 1.2),
			texts = {
				{ "치킨엔\n생맥주", 0.45, 0.25, 1.3, 0.9, WHITE, F.GothamBlack },
				{ "500cc " .. priceIn(ctx.signs, "생맥주", "4,500") .. "원", 0.45, -0.55, 1.3, 0.34, rgb(255, 214, 60), F.GothamBlack },
			},
		})
	end
	local spcf = if V:has("SelfCabinet") > 0 or V:has("SelfTop") > 0 then nil else floorSpot(ctx, { walls = { "left", "right", "back" }, w = 2.8, h = 4.9, d = 1.3, pref = { left = "back", right = "back", back = 0 }, front = 1.0 })
	if spcf then
		selfBar(ctx, spcf, 2.8)
	end
	if not ctx.gw then
		local rpcf = floorSpot(ctx, { walls = { "right", "left", "back" }, w = 2.3, h = 5.3, d = 1.2, pref = { right = "back", left = "back" }, front = 0.9 })
		if rpcf then
			boxRack(ctx, rpcf, 2.3, nm)
		end
	end
	-- 마스코트 입간판 (입구 쪽 옆벽 앞)
	if not ctx.gw then
		local mp = floorSpot(ctx, { walls = { "left", "right" }, w = 1.6, h = 3.7, d = 1.4, pref = { left = "front", right = "front" }, front = 0.4 })
		if mp then
			mascot(ctx, mp, if tong then "옛날 그 맛\n통닭!" else "어서 오닭!")
		end
	end
	-- 테이블 위 펜던트
	tablePendants(ctx, { shade = "dome", look = if tong then L.of(44, 96, 66, M.SmoothPlastic, { r = 0.05 }) else (S.pendant and S.pendant.look), lights = 2, dia = 1.2 })
	-- 사진 메뉴 띠 (옆벽 위쪽 라이트박스)
	local sw0 = math.min(9.6, math.max(V.D - 5.5, V.W - 6))
	if sw0 > 5 then
		local sd, fw = wallSpotFit(ctx, { "right", "left", "back" }, { sw0 + 0.3, 7.8, 6.3 }, 7.0, 8.95, 0)
		local sw = fw - 0.3
		if sd and sw > 4.5 then
			local items = {
				{ "후라이드", pF, artChicken(0, 0.22, 0.62) },
				{ "양념치킨", pY, artYangnyeom(0, 0.22, 0.62) },
				{ "간장치킨", priceIn(ctx.signs, "간장", pY), artGanjang(0, 0.22, 0.62) },
				{ "파닭", "22,000", artPadak(0, 0.22, 0.62) },
				{ "치즈볼", "5,000", artBalls(0, 0.2, 0.55, rgb(240, 196, 80)) },
				{ "감자튀김", "5,000", artFries(0, 0.22, 0.75) },
			}
			local n = math.clamp(math.floor(sw / 1.55), 3, 6)
			while #items > n do
				table.remove(items)
			end
			photoStrip(ctx, sd, sw, 1.8, items, { priceC = P.accent })
		end
	end
	-- 큰 음식 포스터 2 (후라이드 · 양념): 자리가 좁으면 작은 판
	local p1, w1 = wallSpotFit(ctx, { "left", "right" }, { 2.6, 2.0 }, 3.9, 7.0, -2)
	if p1 then
		local k = (w1 - 0.2) / 2.4
		poster(ctx, p1, 2.4 * k, 3.0 * k, {
			bg = P.accent,
			frame = L.blackMetal,
			glass = true,
			art = artChicken(0, -0.1 * k, 1.25 * k),
			texts = {
				{ "바삭한", 0, 1.05 * k, 1.6 * k, 0.36 * k, WHITE, F.GothamBold },
				{ "후라이드", 0, 0.68 * k, 2.0 * k, 0.5 * k, P.gold, F.GothamBlack },
				{ pF .. "원", 0, -1.05 * k, 1.6 * k, 0.42 * k, WHITE, F.GothamBlack },
			},
		})
	end
	local p2, w2 = wallSpotFit(ctx, { "right", "left", "back" }, { 2.6, 2.0 }, 3.9, 7.0, 2)
	if p2 then
		local k = (w2 - 0.2) / 2.4
		poster(ctx, p2, 2.4 * k, 3.0 * k, {
			bg = rgb(250, 236, 200),
			frame = L.blackMetal,
			glass = true,
			art = artYangnyeom(0, -0.1 * k, 1.25 * k),
			texts = {
				{ "달콤 매콤", 0, 1.05 * k, 1.7 * k, 0.34 * k, rgb(120, 30, 20), F.GothamBold },
				{ "양념치킨", 0, 0.68 * k, 2.0 * k, 0.5 * k, rgb(190, 30, 24), F.GothamBlack },
				{ pY .. "원", 0, -1.05 * k, 1.6 * k, 0.42 * k, rgb(60, 30, 20), F.GothamBlack },
			},
		})
	end
	-- 유머 문구 포스터 (치킨집 단골 문구)
	local p3 = wallSpot(ctx, { "left", "right", "back" }, 2.2, 4.0, 6.2, -5)
	if p3 then
		local sbg = if P.key == "red" then P.gold else rgb(34, 30, 28)
		local sfg = if P.key == "red" then rgb(40, 24, 10) else rgb(255, 236, 180)
		poster(ctx, p3, 2.0, 1.9, {
			bg = sbg,
			frame = L.of(220, 200, 160, M.Wood),
			border = 0.06,
			texts = (function()
				local sl = ({
					{ "치킨은 살 안 쪄요", "살은 내가 쪄요", "오늘도 1인 1닭" },
					{ "치킨 먹을 이유?", "오늘이니까!", "치맥은 국룰" },
					{ "치킨은", "언제나 옳다", "반반 무 많이" },
					{ "야구 볼 땐", "치킨에 맥주", "롯데 화이팅!" },
				})[ctx.rand(4)]
				return {
					{ sl[1], 0, 0.42, 1.7, 0.34, sfg, F.GothamBlack },
					{ sl[2], 0, 0.0, 1.7, 0.36, sfg, F.GothamBlack },
					{ sl[3], 0, -0.5, 1.5, 0.28, if P.key == "red" then P.accent else P.gold, F.GothamBold },
				}
			end)(),
		})
	end
	-- 메뉴 사진 줄 (작은 액자 3: 후라이드 · 양념 · 반반)
	local mrow = wallSpot(ctx, { "right", "left", "back" }, 4.6, 4.2, 5.8, 4)
	if mrow then
		local items = { { "후라이드", pF, artChicken }, { "양념", pY, artYangnyeom }, { "반반", pB, nil } }
		for i, it in items do
			local c = mrow * CF((i - 2) * 1.5, 0, 0)
			local a = it[3] and (it[3] :: any)(0, 0.05, 0.62) or nil
			if not a then
				a = artChicken(-0.25, 0.05, 0.5)
				for _, q in artYangnyeom(0.28, 0.05, 0.5) do
					table.insert(a, q)
				end
			end
			poster(ctx, c, 1.36, 1.5, {
				bg = rgb(250, 248, 242),
				frame = L.walnut,
				border = 0.06,
				art = a,
				texts = { { it[1] .. "  " .. it[2], 0, -0.52, 1.1, 0.24, rgb(40, 30, 20), F.GothamBlack } },
			})
		end
	end
	wallMural(ctx, { "left", "right", "back" }, if tong then "옛날 그 맛 그대로" else "CHICKEN & BEER", if tong then "가마솥에 튀긴 시장 통닭" else "바삭하게 · 시원하게 · 광안리에서", P.accent, P.ink)
	infoSet(ctx, {
		origin = { "닭고기 : 국내산", "쌀(치킨무 제외) : 국내산", "배추김치 : 국내산", "치킨무(무) : 국내산", "감자 : 미국산" },
		hours = if has(ctx.signs, "01:00") then "영업시간\n11:00 - 01:00" else "영업시간\n16:00 - 02:00",
		ssid = string.upper(string.gsub(nm, "%s", "")) .. "_5G",
		pw = "chicken1234",
		stickers = {
			{ "19세 미만\n주류 판매 금지", rgb(200, 30, 36) },
			{ "카드 · 페이\n결제 가능", rgb(40, 90, 200) },
			{ "포장 2,000원\n할인", rgb(240, 160, 30), rgb(40, 24, 10) },
		},
		originPrefer = -3,
	})
	-- 배달앱 스티커 (입구 쪽 옆벽)
	local dl = wallSpot(ctx, { "left", "right" }, 2.6, 3.9, 4.6, if V.walls.left then V.walls.left.a + 2 else 0)
	if dl then
		stickerRow(ctx, dl, {
			{ "배달의민족", rgb(42, 193, 188) },
			{ "쿠팡이츠", rgb(30, 130, 230) },
			{ "요기요", rgb(250, 10, 80) },
		}, 0.78)
	end
end

-- 버거 · 서브웨이 · 타코 ----------------------------------------------------------------------------
local function burger3D(K: any, base: CFrame, s: number)
	K:disc("FfBurgerBunB", 1.0 * s, 0.22 * s, base * CF(0, 0.11 * s, 0), L.of(206, 136, 60))
	K:disc("FfBurgerPatty", 1.06 * s, 0.22 * s, base * CF(0, 0.33 * s, 0), L.of(86, 50, 30))
	K:box("FfBurgerCheese", V3(1.0 * s, 0.05 * s, 1.0 * s), base * CF(0, 0.46 * s, 0) * ANG(0, PI / 4, 0), L.of(250, 196, 40))
	K:disc("FfBurgerTomato", 0.92 * s, 0.08 * s, base * CF(0, 0.52 * s, 0), L.of(210, 50, 40))
	K:disc("FfBurgerLettuce", 1.1 * s, 0.06 * s, base * CF(0, 0.58 * s, 0), L.of(100, 180, 60, M.Grass))
	K:ell("FfBurgerBunT", V3(1.0 * s, 0.62 * s, 1.0 * s), base * CF(0, 0.62 * s, 0), L.of(214, 140, 60))
	K:box("FfBurgerBunCut", V3(1.02 * s, 0.31 * s, 1.02 * s), base * CF(0, 0.47 * s, 0), { c = rgb(0, 0, 0), m = M.SmoothPlastic, t = 1 })
	if s > 0.5 then
		for i = 0, 5 do
			local a = i * 1.1
			K:ell("FfSesame", V3(0.06 * s, 0.03 * s, 0.1 * s), base * CF(math.cos(a) * 0.22 * s, 0.9 * s, math.sin(a) * 0.22 * s) * ANG(0, a, 0.5), L.of(250, 240, 210))
		end
	end
end

-- 음료 셀프바 (탄산 디스펜서 + 컵 · 뚜껑 · 빨대)
local function sodaStation(ctx: any, pcf: CFrame, w: number)
	local K = ctx.K
	local P = ctx.pal
	local h, d = 3.3, 1.6
	local top = cabinet(ctx, pcf, w, h, d, L.of(36, 36, 38), L.of(200, 204, 208, M.Metal, { r = 0.1 }), { doors = 2 })
	-- 디스펜서 본체
	local mw = math.min(2.2, w - 1.0)
	local m = pcf * CF(-w / 2 + mw / 2 + 0.15, top, -0.15)
	K:box("FfFountain", V3(mw, 2.0, 1.1), m * CF(0, 1.0, 0), L.of(200, 204, 208, M.Metal))
	K:text("FfFountainPanel", mw - 0.1, 0.9, m * CF(0, 1.45, 0.555), "", { bg = rgb(200, 28, 36), glow = 1.1, d = 0.01 })
	local brands = { { "콜라", rgb(200, 28, 36) }, { "제로", rgb(20, 20, 22) }, { "사이다", rgb(40, 150, 70) }, { "환타", rgb(236, 120, 30) } }
	local n = if mw > 1.8 then 4 else 3
	for i = 1, n do
		local x = -mw / 2 + mw * (i - 0.5) / n
		K:text("FfFountainBrand", mw / n - 0.08, 0.36, m * CF(x, 1.5, 0.57), brands[i][1], { fg = WHITE, bg = brands[i][2], font = F.GothamBlack, d = 0.01 })
		K:box("FfFountainLever", V3(0.16, 0.36, 0.1), m * CF(x, 0.8, 0.6), L.of(30, 30, 32))
		K:vcyl("FfFountainNozzle", 0.12, 0.1, m * CF(x, 0.9, 0.45), L.chrome)
	end
	K:box("FfFountainDrip", V3(mw, 0.08, 0.5), m * CF(0, 0.04, 0.6), L.of(60, 62, 66, M.DiamondPlate))
	K:box("FfFountainIce", V3(mw - 0.2, 0.3, 0.06), m * CF(0, 1.95, 0.56), L.of(230, 236, 240, M.Metal))
	-- 컵 · 뚜껑 · 빨대
	local cx = w / 2 - 0.5
	for i, sz in { 0.26, 0.32 } do
		K:vcyl("FfCupTower", 0.9, sz, pcf * CF(cx - 0.2 + (i - 1) * 0.4, top + 0.45, -0.2), L.of(250, 250, 246))
		K:vcyl("FfCupTowerBand", 0.12, sz + 0.01, pcf * CF(cx - 0.2 + (i - 1) * 0.4, top + 0.5, -0.2), pl(P.accent))
	end
	K:box("FfLidBox", V3(0.5, 0.3, 0.4), pcf * CF(cx, top + 0.15, 0.35), L.of(40, 40, 42))
	K:vcyl("FfStrawCup", 0.5, 0.24, pcf * CF(cx - 0.45, top + 0.25, 0.4), L.of(240, 240, 236, M.Glass, { t = 0.3 }))
	if not ctx.low then
		for i = 0, 5 do
			local a = i * 1.05
			K:seg("FfStraw", (pcf * CF(cx - 0.45 + math.cos(a) * 0.05, top + 0.2, 0.4 + math.sin(a) * 0.05)).Position, (pcf * CF(cx - 0.45 + math.cos(a) * 0.12, top + 0.95, 0.4 + math.sin(a) * 0.12)).Position, 0.03, pl(if i % 2 == 0 then rgb(240, 240, 240) else P.accent))
		end
	end
	local wc = pcf * CF(0, 0, -d / 2 - 0.06)
	K:text("FfSodaSign", math.min(w - 0.3, 2.6), 0.5, wc * CF(0, top + 2.5, 0), "음료 리필 셀프 · REFILL", { fg = WHITE, bg = rgb(26, 26, 28), font = F.GothamBlack, d = 0.04 })
end

-- 소스 · 냅킨 스테이션 (펌프 소스 + 냅킨 + 포크 · 물티슈 + 반납대)
local function sauceStation(ctx: any, pcf: CFrame, w: number)
	local K = ctx.K
	local P = ctx.pal
	local h, d = 3.2, 1.3
	local top = cabinet(ctx, pcf, w, h, d, pl(P.wall2), L.of(36, 36, 38, M.Granite), { doors = 2 })
	local sauces = { { "케첩", rgb(196, 30, 30) }, { "머스터드", rgb(240, 190, 30) }, { "마요", rgb(246, 242, 230) }, { "핫소스", rgb(150, 30, 20) } }
	local n = if w > 2.4 then 4 else 3
	for i = 1, n do
		local b = pcf * CF(-w / 2 + 0.4 + (i - 1) * 0.5, top, -0.25)
		local c = sauces[i][2]
		K:vcyl("FfPumpJar", 0.62, 0.36, b * CF(0, 0.31, 0), L.of(c.R * 255, c.G * 255, c.B * 255, M.Plastic))
		K:vcyl("FfPumpHead", 0.22, 0.12, b * CF(0, 0.73, 0), L.of(40, 40, 42))
		K:box("FfPumpNozzle", V3(0.06, 0.06, 0.24), b * CF(0, 0.8, 0.12), L.of(40, 40, 42))
		if not ctx.low then
			K:text("FfPumpLabel", 0.32, 0.12, b * CF(0, 0.34, 0.185), sauces[i][1], { fg = WHITE, bg = dark(c, 0.3), d = 0.004, font = F.GothamBlack })
		end
	end
	local nb = pcf * CF(w / 2 - 0.5, top, 0.0)
	K:box("FfNapkinDisp", V3(0.55, 0.5, 0.5), nb * CF(0, 0.25, 0), L.steel)
	K:box("FfNapkinPaper", V3(0.4, 0.06, 0.3), nb * CF(0, 0.53, 0.05), L.paper)
	K:vcyl("FfForkCup", 0.45, 0.24, pcf * CF(w / 2 - 0.5, top + 0.22, 0.45), L.steel)
	-- 아래 반납대 칸 (쟁반 꽂이)
	K:box("FfTrayReturn", V3(w - 0.4, 0.9, 0.1), pcf * CF(0, 1.2, d / 2 - 0.02), L.of(26, 26, 28))
	K:text("FfTrayReturnText", w - 0.6, 0.36, pcf * CF(0, 1.2, d / 2 + 0.035), "식기 · 쟁반 반납", { fg = WHITE, font = F.GothamBlack, d = 0.005 })
end

-- 레트로 주크박스 (곡 바꾸기)
local function jukebox(ctx: any, pcf: CFrame)
	local K = ctx.K
	local P = ctx.pal
	local w, h, d = 2.2, 4.6, 1.3
	K:box("FfJukeBody", V3(w, h - 1.1, d), pcf * CF(0, (h - 1.1) / 2, 0), L.of(120, 40, 30, M.Wood))
	K:cyl("FfJukeArch", d, w, pcf * CF(0, h - 1.1, 0) * ANG(0, PI / 2, 0), L.of(120, 40, 30, M.Wood))
	-- 무지개 아치 네온
	local arcs = { rgb(255, 70, 90), rgb(255, 196, 48), rgb(80, 220, 120), rgb(70, 160, 255) }
	for i, c in arcs do
		K:ring("FfJukeNeon", pcf * CF(0, h - 1.1, d / 2 + 0.02), w / 2 - 0.12 - (i - 1) * 0.14, 0.07, if ctx.low then 5 else 9, neon(c), 0, PI)
	end
	K:plate("FfJukeGrille", w - 0.5, 1.2, 0.04, pcf * CF(0, 1.0, d / 2), L.of(190, 160, 80, M.DiamondPlate))
	local scr, lab = K:text("FfJukeScreen", w - 0.6, 0.9, pcf * CF(0, 2.5, d / 2 + 0.005), "♪ Fly Me To The Moon", { fg = rgb(255, 230, 160), bg = rgb(30, 20, 16), glow = 1.5, font = F.GothamBold, d = 0.02 })
	for i = -2, 2 do
		K:box("FfJukeButton", V3(0.2, 0.12, 0.08), pcf * CF(i * 0.3, 1.85, d / 2 + 0.03), L.of(250, 240, 220))
	end
	K:box("FfJukeFoot", V3(w + 0.1, 0.12, d + 0.1), pcf * CF(0, 0.06, 0), L.chrome)
	local songs = { "♪ Fly Me To The Moon", "♪ 부산 갈매기", "♪ Johnny B. Goode", "♪ 해운대 연가", "♪ Don't Stop Me Now" }
	if scr.Parent then
		local lp = K.cf:PointToObjectSpace(scr.Position)
		if Interact.canPrompt(K, lp) then
			Interact.cycle(K, scr, songs, { object = "주크박스", action = "다음 곡", on = function(_i, s)
				lab.Text = s
			end })
		end
	end
end

-- 메뉴 라이트박스 3칸 (세트 사진 = 색 블록 + 이름 + 가격)
local function burgerLightboxes(ctx: any, dcf: CFrame, w: number, combos: { any })
	local n = #combos
	local pw = (w - 0.2 * (n - 1)) / n
	local ph = 2.0
	local k = math.min(1, pw / 2.3)
	for i, cb in combos do
		local c = dcf * CF(-w / 2 + pw / 2 + (i - 1) * (pw + 0.2), 0, 0)
		local a = artBurger(-0.35 * pw / 2.2, 0.05, 0.85 * k)
		for _, q in artFries(0.36 * pw / 2.2, 0.0, 0.7 * k) do
			table.insert(a, q)
		end
		for _, q in artCola(0.74 * pw / 2.2, 0.02, 0.6 * k) do
			table.insert(a, q)
		end
		poster(ctx, c, pw, ph, {
			bg = cb.bg or rgb(26, 26, 28),
			lit = 1.1,
			frame = L.blackMetal,
			border = 0.06,
			art = a,
			texts = {
				{ cb[1], 0, ph / 2 - 0.33, pw - 0.3, 0.32, WHITE, F.GothamBlack },
				{ cb[2], 0, -ph / 2 + 0.3, pw - 0.6, 0.34, ctx.pal.gold, F.GothamBlack },
			},
		})
	end
end

local BURGER_DRINKS = {
	{ rgb(200, 24, 32), "can", rgb(200, 24, 32) },
	{ rgb(20, 20, 22), "can" },
	{ rgb(40, 150, 70), "can" },
	{ rgb(236, 120, 30), "can" },
	{ rgb(60, 24, 20), "pet", rgb(200, 28, 36) },
	{ rgb(200, 230, 240), "pet", rgb(40, 120, 210) },
	{ rgb(250, 210, 60), "bottle", rgb(250, 250, 250) },
}

local function musicChannels(): { any }
	return {
		{ "MV", rgb(110, 30, 140), {
			{ "e", -0.2, -0.05, 0.3, 0.5, rgb(255, 120, 200) },
			{ "e", 0.2, -0.05, 0.3, 0.5, rgb(80, 220, 255) },
			{ "b", 0, -0.42, 1.0, 0.1, rgb(20, 10, 30) },
		}, "MUSIC TOP 10", "♪ 이번 주 1위 · 부산 갈매기 리믹스" },
		{ "스포츠", rgb(30, 100, 46), {
			{ "b", 0, -0.18, 0.34, 0.34, rgb(150, 100, 56), PI / 4 },
			{ "b", 0, 0.38, 1.0, 0.18, rgb(16, 26, 70) },
		}, "롯데 5 : 4 LG   9회초", "사직야구장 LIVE" },
		{ "광고", rgb(200, 30, 36), {
			{ "e", 0, -0.08, 0.36, 0.3, rgb(214, 140, 60) },
			{ "b", 0, -0.14, 0.38, 0.06, rgb(92, 52, 30) },
			{ "b", 0, -0.06, 0.36, 0.03, rgb(100, 180, 60) },
		}, "NEW 더블 스매시 버거", "세트 주문 시 감자튀김 L 업그레이드" },
	}
end

local function burgerBuild(ctx: any)
	local K, V, S = ctx.K, ctx.V, ctx.S
	local P = ctx.pal
	local taco = ctx.sk == "taco"
	local nm = V.name or "BURGER"
	if nm == "SideShop" then
		nm = if taco then "TACO" else "BURGER"
	end
	local pB = priceIn(ctx.signs, "수제버거", "9,800")
	local pFr = priceIn(ctx.signs, "감자튀김", "3,500")
	local pSh = priceIn(ctx.signs, "쉐이크", "5,500")
	if not ctx.gw then
		local lh = if S.lower then S.lower.h else 0.45
		if P.brick then
			upperPaint(ctx, { "left", "right" }, lh + 0.08, L.of(150, 82, 62, M.Brick))
		else
			upperPaint(ctx, { "left", "right" }, lh + 0.08, pl(P.wall, M.Plaster))
		end
		upperPaint(ctx, { "back" }, lh + 0.08, pl(P.wall2, M.Plaster))
		wallBand(ctx, { "left", "right", "back" }, lh + 0.06, 0.14, 0.08, L.black)
	end
	-- 체커 바닥 (다이너)
	if P.checker and not ctx.low then
		local t = 2.0
		local nx, nz = math.floor(V.W / t), math.floor(V.D / t)
		K:free(function()
			K:box("FfCheckerBase", V3(V.W - 0.02, 0.02, V.D - 0.02), CF((V.x0 + V.x1) / 2, 0.01, (V.z0 + V.z1) / 2), L.of(240, 238, 232, M.CeramicTiles))
			local x0 = V.x0 + (V.W - nx * t) / 2
			local z0 = V.z0 + (V.D - nz * t) / 2
			for i = 0, nx - 1 do
				for j = 0, nz - 1 do
					if (i + j) % 2 == 0 then
						K:box("FfChecker", V3(t - 0.03, 0.024, t - 0.03), CF(x0 + (i + 0.5) * t, 0.012, z0 + (j + 0.5) * t), L.of(28, 28, 30, M.CeramicTiles))
					end
				end
			end
		end)
	end
	passDress(ctx, { trim = L.of(30, 30, 32, M.Metal), header = "pickup", hoodText = if taco then "TAQUERÍA · PICK UP" else "PICK UP", hoodFg = P.neonC, hoodLook = L.of(30, 30, 32, M.Metal), utensil = "spatula", lamp = rgb(255, 120, 60) })
	menuSignDress(ctx, L.of(24, 24, 26), P.neonC)
	kioskOverlay(ctx, nm, P.accent, { rgb(214, 140, 60), rgb(92, 52, 30), rgb(250, 196, 40), rgb(210, 30, 36), rgb(90, 170, 60), rgb(250, 204, 70) })
	-- 천장: 노출 덕트 (인더스트리얼 · 벽돌) 또는 에디슨 전구 펜던트
	if not P.checker and not ctx.low then
		local x = V.x1 - 2.2
		local za, zb = V.z0 + 0.8, V.z1 - 5.0
		if zb - za > 4 and Common.ceilFree(K, x, (za + zb) / 2, 0.2) then
			local y = V.H - 1.0
			local ok = true
			for _, r in V.hang do
				if r.max.X > x - 0.8 and r.min.X < x + 0.8 and r.min.Y < y + 0.7 then
					ok = false
				end
			end
			if ok then
				K:seg("FfDuct", V3(x, y, za), V3(x, y, zb), 1.1, L.of(176, 180, 184, M.Metal))
				local nseg = math.floor((zb - za) / 2.0)
				for i = 1, nseg do
					local z = za + i * (zb - za) / (nseg + 1)
					K:ring("FfDuctSeam", CFrame.lookAt(V3(x, y, z), V3(x, y, z + 1)), 0.56, 0.05, 8, L.of(150, 154, 158, M.Metal))
					K:seg("FfDuctHanger", V3(x, y + 0.55, z), V3(x, V.H, z), 0.05, L.blackMetal)
				end
				for i = 1, 2 do
					local z = za + i * (zb - za) / 3
					K:box("FfDuctGrille", V3(0.7, 0.06, 0.5), CF(x - 0.2, y - 0.56, z), L.of(130, 134, 138, M.DiamondPlate))
				end
			end
		end
	end
	tablePendants(ctx, { shade = "bulb", lights = 1, dia = 0.8, pair = true })
	-- 상호작용 벽 장식 먼저 (프롬프트 되는 자리): TV · 네온
	if V:has("TV") == 0 then
		local d = promptWallSpot(ctx, { "left", "right", "back" }, 3.4, 6.3, 8.4)
		if not d then
			d = wallSpot(ctx, { "left", "right", "back" }, 3.4, 6.3, 8.4, 3)
		end
		if d then
			tvSet(ctx, d, 3.0, musicChannels(), "TV")
		end
	end
	local nd = promptWallSpot(ctx, { "right", "left", "back" }, 4.0, 5.2, 7.6)
	if not nd then
		nd = wallSpot(ctx, { "right", "left", "back" }, 4.0, 5.2, 7.6, 0)
	end
	if nd then
		local s = 0.7
		local x0 = -1.45
		local shapes = {
			{ x0 - s * 0.6, s * 0.1, x0 + s * 0.6, s * 0.1, rgb(255, 196, 48) },
			{ x0 - s * 0.6, s * 0.1, x0 - s * 0.3, s * 0.6, rgb(255, 196, 48) },
			{ x0 - s * 0.3, s * 0.6, x0 + s * 0.3, s * 0.6, rgb(255, 196, 48) },
			{ x0 + s * 0.3, s * 0.6, x0 + s * 0.6, s * 0.1, rgb(255, 196, 48) },
			{ x0 - s * 0.65, -s * 0.12, x0 + s * 0.65, -s * 0.12, rgb(80, 230, 120) },
			{ x0 - s * 0.6, -s * 0.34, x0 + s * 0.6, -s * 0.34, rgb(255, 90, 60) },
			{ x0 - s * 0.6, -s * 0.56, x0 + s * 0.6, -s * 0.56, rgb(255, 196, 48) },
		}
		local rec = neonSign(ctx, nd * CF(0.55, 0, 0), 2.4, 1.3, if taco then "TACO\nTIME" else "BURGER\nTIME", P.neonC, { shapes = {}, object = "네온사인" })
		-- 버거 그림 네온관 (왼쪽)
		for _, sg in shapes do
			local p = K:seg("FfNeonTube", (nd * CF(sg[1], sg[2], 0.1)).Position, (nd * CF(sg[3], sg[4], 0.1)).Position, 0.08, neon(sg[5]), 0.07)
			if p then
				table.insert(rec.tubes, p)
			end
		end
	end
	-- 바닥 소품
	placeFridge(ctx, { header = "COLD DRINKS · 음료", headerBg = rgb(26, 26, 28), headerFg = P.neonC, items = BURGER_DRINKS, brand = "SHOWCASE" })
	local sw = 3.4
	local sp = floorSpot(ctx, { walls = { "back", "left", "right" }, w = sw, h = 5.6, d = 1.6, pref = { back = "left", left = "back", right = "back" }, front = 1.0 })
	if sp then
		sodaStation(ctx, sp, sw)
	end
	local sp2 = floorSpot(ctx, { walls = { "left", "right", "back" }, w = 2.6, h = 4.4, d = 1.3, pref = { left = "back", right = "back" }, front = 1.0 })
	if sp2 then
		sauceStation(ctx, sp2, 2.6)
	end
	do
		local jp = floorSpot(ctx, { walls = { "right", "left", "back" }, w = 2.2, h = 4.6, d = 1.3, pref = { right = "front", left = "front" }, prompt = true, front = 1.0 })
		if jp then
			jukebox(ctx, jp)
		end
	end
	-- 벽: 메뉴 라이트박스 (세트 3칸) · 네온 · 포스터 · TV
	local combos = if taco then {
		{ "비프 타코 세트", "10,900" },
		{ "치킨 부리또 세트", "11,900" },
		{ "나초 & 살사", "7,500" },
	} else {
		{ "클래식 치즈버거 세트", "12,900" },
		{ "더블 스매시 세트", "15,900" },
		{ "베이컨 BBQ 세트", "14,500" },
	}
	local lbw = math.min(7.2, V.D - 6)
	local lb = wallSpot(ctx, { "left", "right" }, lbw, 5.9, 8.1, -1)
	if lb then
		burgerLightboxes(ctx, lb, lbw, combos)
	end
	local p1 = wallSpot(ctx, { "right", "left" }, 2.4, 3.9, 6.9, 2)
	if p1 then
		poster(ctx, p1, 2.2, 2.9, {
			bg = rgb(250, 240, 220),
			frame = L.blackMetal,
			glass = true,
			art = if taco then artTaco(0, 0.0, 1.3) else artBurger(0, 0.05, 1.3),
			texts = {
				{ if taco then "AUTHENTIC" else "100% BEEF", 0, 1.0, 1.8, 0.4, P.accent, F.GothamBlack },
				{ if taco then "매일 굽는 또르띠야" else "매일 아침 직접 만드는 수제 패티", 0, -0.82, 1.9, 0.26, rgb(40, 30, 20), F.GothamBold },
				{ if taco then "비프 타코 4,900" else "수제버거 " .. pB, 0, -1.12, 1.6, 0.3, rgb(40, 30, 20), F.GothamBlack },
			},
		})
	end
	local p2 = wallSpot(ctx, { "left", "right", "back" }, 2.4, 3.9, 6.9, -4)
	if p2 then
		local a = artFries(-0.45, 0.1, 1.2)
		for _, q in artCola(0.55, 0.05, 1.0) do
			table.insert(a, q)
		end
		poster(ctx, p2, 2.2, 2.9, {
			bg = rgb(28, 28, 30),
			frame = L.of(200, 200, 204, M.Metal),
			glass = true,
			art = a,
			texts = {
				{ "FRIES & SHAKE", 0, 1.02, 1.9, 0.34, P.gold, F.GothamBlack },
				{ "감자튀김 " .. pFr .. "  ·  쉐이크 " .. pSh, 0, -1.05, 1.95, 0.26, WHITE, F.GothamBold },
			},
		})
	end
	-- 3D 버거 조형 (벽 선반 위)
	if not taco then
		local sh = wallSpot(ctx, { "right", "left", "back" }, 2.2, 6.9, 8.4, -3)
		if sh then
			local at = Props.shelf(K, sh * CF(0, -0.6, 0), 2.0, { depth = 1.1, look = L.walnut })
			burger3D(K, at * CF(0, 0, -0.05), 0.95)
		end
	end
	wallMural(ctx, { "left", "right", "back" }, if taco then "TACOS & BEER" else "HANDMADE BURGER", if taco then "광안리 타코 · 매일 굽는 또르띠야" else "매일 아침 굽는 번 · 100% 소고기 패티", P.gold, P.ink)
	if V.W > 22 then
		-- 넓은 가게: 뒷벽 빈 곳에 두 번째 레터링 + 세트 라이트박스
		wallMural(ctx, { "back" }, if taco then "GWANGALLI TAQUERIA" else "SMASH · GRILL · SHAKE", "광안리 바다 앞 수제버거", P.accent, P.ink)
		local lb2 = wallSpot(ctx, { "back", "left", "right" }, 7.4, 4.0, 6.3, 0)
		if lb2 then
			burgerLightboxes(ctx, lb2, 7.2, {
				{ "치즈 프라이", "5,900", bg = rgb(40, 20, 16) },
				{ "어니언 링", "5,500", bg = rgb(40, 20, 16) },
				{ "밀크쉐이크", pSh, bg = rgb(40, 20, 16) },
			})
		end
	end
	infoSet(ctx, {
		origin = if taco then { "소고기 : 호주산", "닭고기 : 국내산", "돼지고기 : 국내산", "쌀 : 국내산" } else { "소고기(패티) : 호주산", "돼지고기(베이컨) : 미국산", "닭고기 : 국내산", "감자 : 미국산" },
		hours = if has(ctx.signs, "24 HOURS") then "OPEN 24 HOURS\n연중무휴" else "영업시간\n10:30 - 22:00",
		ssid = "BURGER_FREE",
		pw = "burger2026",
		stickers = {
			{ "키오스크\n주문", rgb(30, 30, 32) },
			{ "카드 · 페이\n결제", rgb(40, 90, 200) },
			{ "포장\n가능", rgb(220, 60, 40) },
		},
	})
end

-- SUBWAY ---------------------------------------------------------------------------------------------
-- 앞 카운터 위 재료 칸 (맵 Ingredient 납작 상자 자리 그대로 스테인리스 1/6 팬 + 재료 덩어리)
local INGREDIENTS = {
	{ rgb(110, 180, 60), "leaf" }, -- 양상추
	{ rgb(210, 50, 40), "slice" }, -- 토마토
	{ rgb(60, 130, 50), "slice" }, -- 오이
	{ rgb(236, 230, 220), "ring" }, -- 양파
	{ rgb(250, 200, 40), "slice" }, -- 피망(노랑)
	{ rgb(40, 40, 30), "dot" }, -- 올리브
	{ rgb(140, 170, 50), "ring" }, -- 할라피뇨
	{ rgb(120, 150, 60), "slice" }, -- 피클
	{ rgb(250, 220, 120), "cube" }, -- 치즈
	{ rgb(232, 150, 150), "slice" }, -- 햄
	{ rgb(240, 236, 220), "cube" }, -- 에그마요
}

local function veggieWells(ctx: any)
	local K, V = ctx.K, ctx.V
	local list = V.byName.Ingredient or {}
	if #list == 0 then
		return
	end
	local rnd = ctx.rand
	K:free(function()
		for i, r in list do
			local ing = INGREDIENTS[(i - 1) % #INGREDIENTS + 1]
			local c: Color3 = ing[1]
			local w, d = r.size.X, r.size.Z
			local base = CF(r.c.X, r.min.Y, r.c.Z)
			-- 스테인리스 팬 (테두리) + 속 재료
			K:box("FfWellRim", V3(w, 0.1, d), base * CF(0, 0.05, 0), L.of(200, 204, 208, M.Metal, { r = 0.12 }))
			K:box("FfWellFill", V3(w - 0.08, 0.06, d - 0.08), base * CF(0, 0.09, 0), pl(c))
			if not ctx.low then
				local n = if ctx.high then 4 else 2
				for k = 1, n do
					local x = (rnd() - 0.5) * (w - 0.3)
					local z = (rnd() - 0.5) * (d - 0.3)
					local p = base * CF(x, 0.12, z) * ANG(0, rnd() * PI, 0)
					local lc = if (k % 2) == 0 then light(c, 0.15) else dark(c, 0.12)
					if ing[2] == "leaf" then
						K:ell("FfIng", V3(0.3, 0.06, 0.22), p, { c = lc, m = M.Grass })
					elseif ing[2] == "slice" then
						K:disc("FfIng", 0.22, 0.03, p, pl(lc))
					elseif ing[2] == "ring" then
						K:disc("FfIng", 0.2, 0.025, p, pl(lc))
					elseif ing[2] == "dot" then
						K:ball("FfIng", 0.1, p, pl(lc))
					else
						K:box("FfIng", V3(0.1, 0.06, 0.1), p, pl(lc))
					end
				end
			end
			Scan.hide(K.hidden, r.part)
		end
		-- 재료 칸 사이 스테인리스 레일 (앞뒤)
		local mn, mx = list[1].min, list[1].max
		for _, r in list do
			mn = mn:Min(r.min)
			mx = mx:Max(r.max)
		end
		K:box("FfWellRailF", V3(mx.X - mn.X + 0.1, 0.05, 0.06), CF((mn.X + mx.X) / 2, mn.Y + 0.12, mx.Z + 0.03), L.chrome)
		K:box("FfWellRailB", V3(mx.X - mn.X + 0.1, 0.05, 0.06), CF((mn.X + mx.X) / 2, mn.Y + 0.12, mn.Z - 0.03), L.chrome)
	end)
end

local function sneezeGuard(ctx: any)
	local K, V = ctx.K, ctx.V
	for _, r in V.byName.SneezeGuard or {} do
		-- 가드가 올라간 카운터 (뒷모서리 = 직원 쪽)
		local g = nil
		for _, c in V.counters do
			if r.c.X > c.min.X - 0.5 and r.c.X < c.max.X + 0.5 and r.c.Z > c.min.Z - 0.5 and r.c.Z < c.max.Z + 0.5 then
				g = c
			end
		end
		local topY = if g then g.y else r.min.Y - 1.3
		local zb = if g then g.min.Z + 0.12 else r.min.Z
		local zf = r.max.Z
		local w = r.size.X
		local yTop = r.max.Y + 0.25
		K:free(function()
			-- 직원 쪽 기둥 + 위 선반 (조명) + 손님 쪽으로 기울어 내려오는 유리
			local n = math.max(2, math.floor(w / 3.2))
			for i = 0, n do
				local x = r.min.X + w * i / n
				K:vcyl("FfGuardPost", yTop - topY, 0.08, CF(x, topY + (yTop - topY) / 2, zb), L.chrome)
				K:bar("FfGuardArm", V3(x, yTop, zb), V3(x, yTop, zb + 0.9), 0.05, 0.05, L.chrome)
			end
			K:box("FfGuardShelf", V3(w + 0.1, 0.05, 1.0), CF(r.c.X, yTop + 0.03, zb + 0.5), { c = rgb(220, 236, 240), m = M.Glass, t = 0.55, r = 0.2 })
			K:box("FfGuardLED", V3(w - 0.2, 0.03, 0.08), CF(r.c.X, yTop - 0.02, zb + 0.85), neon(rgb(255, 244, 220)))
			local a = V3(r.c.X, yTop, zb + 0.95)
			local b = V3(r.c.X, math.max(topY + 0.95, r.min.Y - 0.25), zf)
			local mid = (a + b) / 2
			local dir = (b - a).Unit
			local len = (b - a).Magnitude
			local cf = CFrame.lookAt(mid, mid + dir) 
			K:box("FfGuardGlass", V3(w, 0.04, len), cf * ANG(PI / 2, 0, 0) * ANG(-PI / 2, 0, 0), { c = rgb(220, 236, 240), m = M.Glass, t = 0.72, r = 0.18 })
			K:box("FfGuardEdge", V3(w, 0.05, 0.05), CF(b), L.chrome)
		end)
		Scan.hide(K.hidden, r.part)
	end
end

-- 칩 진열대 (철제 랙 + 봉지)
local function chipsRack(ctx: any, pcf: CFrame)
	local K = ctx.K
	local w, h, d = 1.6, 4.6, 1.0
	K:box("FfChipBase", V3(w, 0.2, d), pcf * CF(0, 0.1, 0), L.of(0, 120, 56))
	K:vcyl("FfChipPost", h, 0.1, pcf * CF(-w / 2 + 0.1, h / 2, -d / 2 + 0.1), L.blackMetal)
	K:vcyl("FfChipPost", h, 0.1, pcf * CF(w / 2 - 0.1, h / 2, -d / 2 + 0.1), L.blackMetal)
	K:text("FfChipHeader", w, 0.5, pcf * CF(0, h - 0.25, -d / 2 + 0.16), "CHIPS · 쿠키", { fg = WHITE, bg = rgb(0, 120, 56), font = F.GothamBlack, d = 0.04 })
	local cols = { rgb(250, 200, 40), rgb(200, 30, 36), rgb(40, 90, 200), rgb(30, 150, 70), rgb(120, 40, 140) }
	for row = 0, 3 do
		local y = 0.6 + row * 0.95
		K:box("FfChipBar", V3(w - 0.1, 0.05, 0.05), pcf * CF(0, y + 0.72, -d / 2 + 0.16), L.blackMetal)
		for i = 0, 2 do
			local c = cols[(row * 3 + i) % #cols + 1]
			K:ell("FfChipBag", V3(0.42, 0.66, 0.2), pcf * CF(-0.5 + i * 0.5, y + 0.36, -d / 2 + 0.32), L.of(c.R * 255, c.G * 255, c.B * 255, M.Foil))
		end
	end
end

local function subwayBuild(ctx: any)
	local K, V = ctx.K, ctx.V
	local P = ctx.pal
	local g = P.green
	-- 벽: 흰 위쪽 + 초록 포인트 벽 (오른쪽 벽) + 노란 화살표 띠
	upperPaint(ctx, { "back" }, 3.5, pl(rgb(244, 240, 230), M.Plaster))
	upperPaint(ctx, { "left" }, 3.5, pl(rgb(244, 240, 230), M.Plaster))
	upperPaint(ctx, { "right" }, 3.5, pl(g, M.Plaster))
	wallBand(ctx, { "left", "back" }, 3.52, 0.16, 0.05, pl(P.accent))
	-- 카운터: 재료 칸 · 재채기 가드 · 뒤 오븐
	veggieWells(ctx)
	sneezeGuard(ctx)
	for _, nm in { "ToasterOven" } do
		for _, r in V.byName[nm] or {} do
			K:free(function()
				local c = CF(r.c.X, r.min.Y, r.c.Z)
				local w, h, d = r.size.X, r.size.Y, r.size.Z
				local face = (r.max.Z > -8) -- 문은 카운터 앞쪽 (+Z)
				K:box("FfOvenBody", V3(w, h, d), c * CF(0, h / 2, 0), L.of(190, 194, 198, M.Metal, { r = 0.08 }))
				K:box("FfOvenWindow", V3(w * 0.66, h * 0.42, 0.03), c * CF(-w * 0.1, h * 0.5, d / 2 + 0.015), { c = rgb(40, 30, 24), m = M.Glass, t = 0.25 })
				K:box("FfOvenGlow", V3(w * 0.6, h * 0.08, 0.02), c * CF(-w * 0.1, h * 0.62, d / 2 + 0.005), neon(rgb(255, 140, 60)))
				K:box("FfOvenPanel", V3(w * 0.2, h * 0.7, 0.03), c * CF(w * 0.36, h * 0.5, d / 2 + 0.015), L.of(30, 30, 32))
				K:box("FfOvenDisplay", V3(w * 0.14, h * 0.12, 0.02), c * CF(w * 0.36, h * 0.72, d / 2 + 0.035), neon(rgb(80, 220, 120)))
				K:box("FfOvenHandle", V3(w * 0.6, 0.06, 0.08), c * CF(-w * 0.1, h * 0.8, d / 2 + 0.05), L.chrome)
				K:box("FfOvenFoot", V3(w - 0.1, 0.06, d - 0.1), c * CF(0, 0.03, 0), L.black)
				local _ = face
			end)
			Scan.hide(K.hidden, r.part)
		end
	end
	for _, r in V.byName.BreadCabinet or {} do
		K:free(function()
			local c = CF(r.c.X, r.min.Y, r.c.Z)
			local w, h, d = r.size.X, r.size.Y, r.size.Z
			-- 빵 발효기: 스테인리스 틀 + 유리문 + 안쪽 따뜻한 불빛 (빵은 맵 Loaf 그대로)
			K:box("FfProoferBack", V3(w, h, 0.08), c * CF(0, h / 2, -d / 2 + 0.04), L.of(190, 194, 198, M.Metal))
			K:box("FfProoferSide", V3(0.08, h, d), c * CF(-w / 2 + 0.04, h / 2, 0), L.of(190, 194, 198, M.Metal))
			K:box("FfProoferSide", V3(0.08, h, d), c * CF(w / 2 - 0.04, h / 2, 0), L.of(190, 194, 198, M.Metal))
			K:box("FfProoferTop", V3(w, 0.1, d), c * CF(0, h - 0.05, 0), L.of(190, 194, 198, M.Metal))
			K:box("FfProoferBottom", V3(w, 0.08, d), c * CF(0, 0.04, 0), L.of(190, 194, 198, M.Metal))
			K:box("FfProoferShelf", V3(w - 0.16, 0.04, d - 0.1), c * CF(0, h * 0.4, 0), L.of(200, 204, 208, M.Metal))
			K:box("FfProoferGlow", V3(w - 0.2, 0.04, 0.06), c * CF(0, h - 0.14, d / 2 - 0.12), neon(rgb(255, 200, 140)))
			K:box("FfProoferGlass", V3(w - 0.12, h - 0.2, 0.03), c * CF(0, h / 2, d / 2 - 0.02), { c = rgb(230, 220, 200), m = M.Glass, t = 0.75, r = 0.15 })
			K:text("FfProoferLabel", w * 0.6, 0.22, c * CF(0, h - 0.3, d / 2 + 0.0), "FRESH BAKED", { fg = rgb(0, 120, 56), font = F.GothamBlack, d = 0.005 })
		end)
		Scan.hide(K.hidden, r.part)
	end
	-- 뒷벽 메뉴판 3개 (Sign_) 뒤 액자 + 아래 노란 LED
	menuSignDress(ctx, L.of(30, 34, 32), P.accent)
	local tvd = promptWallSpot(ctx, { "left", "right", "back" }, 3.4, 6.2, 8.3)
	if not tvd then
		tvd = wallSpot(ctx, { "left", "right" }, 3.4, 6.2, 8.3, 6)
	end
	if tvd then
		tvSet(ctx, tvd, 3.0, {
			{ "메뉴", g, { { "e", -0.18, -0.05, 0.6, 0.3, rgb(214, 160, 92) }, { "e", -0.18, 0.0, 0.58, 0.08, rgb(100, 180, 60) } }, "오늘의 써브  ·  에그마요 5,900", "Sub of the Day" },
			{ "쿠키", P.accent, { { "e", -0.2, -0.05, 0.26, 0.4, rgb(150, 100, 60) }, { "e", 0.18, -0.05, 0.26, 0.4, rgb(110, 70, 40) } }, "갓 구운 쿠키 3개 4,500", "초코칩 · 화이트 마카다미아" },
		}, "메뉴 화면")
	end
	-- 프롬프트 되는 빈 벽: 초록 · 노랑 네온 (켜기/끄기)
	local snd = promptSpotStrict(ctx, { "back", "left", "right" }, 3.4, 6.4, 7.9)
	if snd then
		neonSign(ctx, snd, 3.0, 1.0, "FRESH · 매일 굽는 빵", P.accent, {
			object = "네온사인",
			shapes = { { -1.45, -0.62, 1.45, -0.62, rgb(80, 220, 120) } },
		})
	end
	-- 초록 벽 큰 글자 + 노란 화살표
	local sg = wallSpot(ctx, { "right", "left" }, 7.0, 7.0, 9.6, 0)
	if sg then
		K:text("FfSubLogo", 6.0, 1.5, sg * CF(0, 0.45, 0.02), "SUBWAY", { fg = WHITE, font = F.GothamBlack, d = 0.04 })
		K:text("FfSubSlogan", 5.0, 0.5, sg * CF(0, -0.75, 0.02), "신선한 재료를 매일 아침 준비합니다", { fg = P.accent, font = F.GothamBold, d = 0.02 })
		for _, sx in { -1, 1 } do
			K:plate("FfSubArrow", 0.9, 0.16, 0.04, sg * CF(sx * 3.2, 0.45, 0.02) * ANG(0, 0, sx * 0.5), pl(P.accent))
		end
	end
	-- 뒤 카운터 위 얕은 벽 선반 (포장 봉투 · 컵 · 냅킨 묶음)
	local bs = wallSpot(ctx, { "back" }, 4.4, 5.2, 6.6, 2)
	if bs then
		local at = Props.shelf(K, bs * CF(0, -0.4, 0), 4.2, { depth = 0.8, look = L.lightOak })
		for i = 0, 3 do
			K:box("FfSubBag", V3(0.7, 0.9, 0.3), at * CF(-1.6 + i * 0.75, 0.45, -0.1) * ANG(0, (i % 2) * 0.08, 0), L.of(196, 162, 118, M.Cardboard))
			K:plate("FfSubBagLogo", 0.5, 0.18, 0.01, at * CF(-1.6 + i * 0.75, 0.55, 0.05), pl(rgb(0, 132, 61)))
		end
		for i = 0, 2 do
			K:vcyl("FfSubCups", 0.8, 0.34, at * CF(1.4 + (i - 1) * 0.0 + i * 0.0, 0.4, 0.0) * CF((i - 1) * 0.36, 0, 0), L.of(250, 250, 246))
			K:vcyl("FfSubCupBand", 0.14, 0.35, at * CF(1.4 + (i - 1) * 0.36, 0.5, 0.0), pl(rgb(255, 194, 14)))
		end
	end
	-- 주문 방법 5단계 포스터 (써브웨이 대표 안내)
	local st = wallSpot(ctx, { "left", "right" }, 5.4, 4.2, 7.0, 0)
	if st then
		local steps = { { "1", "빵 선택" }, { "2", "메인 재료" }, { "3", "치즈 · 토스팅" }, { "4", "야채 선택" }, { "5", "소스 선택" } }
		K:plate("FfStepsBack", 5.3, 2.6, 0.04, st, pl(rgb(250, 248, 240)))
		K:text("FfStepsTitle", 4.6, 0.46, st * CF(0, 0.95, 0.045), "주문 방법  HOW TO ORDER", { fg = g, font = F.GothamBlack, d = 0.01 })
		for i, s in steps do
			local x = -2.1 + (i - 1) * 1.05
			K:disc("FfStepDot", 0.62, 0.04, st * CF(x, 0.15, 0.06) * ANG(PI / 2, 0, 0), pl(if i % 2 == 1 then g else P.accent))
			K:text("FfStepNum", 0.4, 0.4, st * CF(x, 0.15, 0.085), s[1], { fg = WHITE, font = F.GothamBlack, d = 0.005 })
			K:text("FfStepText", 0.98, 0.3, st * CF(x, -0.45, 0.045), s[2], { fg = rgb(30, 30, 30), font = F.GothamBold, d = 0.005 })
			if i < 5 and not ctx.low then
				K:plate("FfStepArrow", 0.3, 0.06, 0.02, st * CF(x + 0.52, 0.15, 0.05), pl(P.accent))
			end
		end
		K:text("FfStepsFoot", 4.8, 0.3, st * CF(0, -0.98, 0.045), "15cm " .. priceIn(ctx.signs, "15cm", "6,900") .. "  ·  30cm " .. priceIn(ctx.signs, "30cm", "11,900"), { fg = rgb(60, 60, 60), font = F.GothamBold, d = 0.01 })
	end
	-- 샌드위치 사진 포스터 2
	for i, pr in { { "이탈리안 비엠티", "15cm 7,400" }, { "로티세리 바비큐 치킨", "15cm 7,900" } } do
		local pd = wallSpot(ctx, { "left", "right", "back" }, 2.6, 3.9, 6.6, -4 + (i - 1) * 7)
		if pd then
			poster(ctx, pd, 2.4, 2.4, {
				bg = if i == 1 then rgb(250, 246, 236) else rgb(0, 120, 56),
				frame = L.of(220, 220, 220, M.Metal),
				glass = true,
				art = artSandwich(0, 0.05, 1.25),
				texts = {
					{ pr[1], 0, 0.85, 2.0, 0.34, if i == 1 then g else WHITE, F.GothamBlack },
					{ pr[2], 0, -0.82, 1.6, 0.3, P.accent, F.GothamBlack },
				},
			})
		end
	end
	-- 샌드위치 사진 메뉴 띠 (흰 벽 위쪽)
	local sd, fw = wallSpotFit(ctx, { "left", "right", "back" }, { 9.6, 7.8, 6.3, 4.4, 3.5 }, 7.0, 8.95, 0)
	if sd then
		local items = {
			{ "에그마요", "5,900", artSandwich(0, 0.22, 0.6) },
			{ "이탈리안 비엠티", "7,400", artSandwich(0, 0.22, 0.6) },
			{ "써브웨이 클럽", "7,900", artSandwich(0, 0.22, 0.6) },
			{ "스테이크 & 치즈", "8,900", artSandwich(0, 0.22, 0.6) },
			{ "로티세리 치킨", "7,900", artSandwich(0, 0.22, 0.6) },
			{ "쉬림프", "8,200", artSandwich(0, 0.22, 0.6) },
		}
		local n = math.clamp(math.floor((fw - 0.3) / 1.4), 2, 6)
		while #items > n do
			table.remove(items)
		end
		-- 재료 색 바꿔 메뉴마다 다르게
		local meat = { rgb(240, 236, 210), rgb(200, 90, 80), rgb(236, 170, 150), rgb(150, 90, 60), rgb(220, 170, 110), rgb(250, 160, 120) }
		for i, it in items do
			it[3][2][6] = meat[i]
		end
		photoStrip(ctx, sd, fw - 0.3, 1.8, items, { priceC = rgb(0, 120, 56), frame = L.of(0, 100, 50) })
	end
	-- 칩 랙 (계산대 근처 손님 쪽) + 음료 냉장고는 맵 것
	local cp = floorSpot(ctx, { walls = { "right", "left", "back" }, w = 1.6, h = 4.6, d = 1.0, pref = { right = "back", left = "back" }, front = 0.8 })
	if cp then
		chipsRack(ctx, cp)
	end
	placeFridge(ctx, { walls = { "right", "left", "back" }, pref = { right = "back" }, header = "DRINKS", headerBg = g, items = BURGER_DRINKS })
	local sp = floorSpot(ctx, { walls = { "left", "right", "back" }, w = 3.4, h = 5.6, d = 1.6, pref = { left = "front", right = "front" }, front = 1.0 })
	if sp then
		sodaStation(ctx, sp, 3.4)
	end
	infoSet(ctx, {
		origin = { "닭고기 : 국내산", "돼지고기(햄 · 베이컨) : 미국산", "소고기 : 호주산", "계란 : 국내산" },
		hours = "OPEN 24 HOURS\n연중무휴",
		ssid = "SUBWAY_FREE",
		pw = "subway2026",
	})
	tablePendants(ctx, { shade = "drum", look = L.of(0, 120, 56), lights = 1, dia = 1.1 })
end

-- 분식 ----------------------------------------------------------------------------------------------
-- 떡볶이 철판: 사각 팬 + 빨간 소스 + 떡 · 어묵 · 달걀 · 파. base = 팬 바닥 가운데 (조리대 윗면)
local function tteokPan(ctx: any, base: CFrame, w: number, d: number)
	local K = ctx.K
	local rnd = ctx.rand
	local wall = 0.06
	K:box("FfPanBase", V3(w, 0.06, d), base * CF(0, 0.03, 0), L.of(70, 72, 76, M.Metal))
	K:box("FfPanWall", V3(w, 0.32, wall), base * CF(0, 0.16, d / 2 - wall / 2), L.of(150, 154, 158, M.Metal))
	K:box("FfPanWall", V3(w, 0.32, wall), base * CF(0, 0.16, -d / 2 + wall / 2), L.of(150, 154, 158, M.Metal))
	K:box("FfPanWall", V3(wall, 0.32, d), base * CF(w / 2 - wall / 2, 0.16, 0), L.of(150, 154, 158, M.Metal))
	K:box("FfPanWall", V3(wall, 0.32, d), base * CF(-w / 2 + wall / 2, 0.16, 0), L.of(150, 154, 158, M.Metal))
	K:box("FfPanSauce", V3(w - 0.12, 0.05, d - 0.12), base * CF(0, 0.22, 0), { c = rgb(222, 72, 34), m = M.SmoothPlastic, r = 0.12 })
	local n = if ctx.low then 8 elseif ctx.high then 26 else 16
	for i = 1, n do
		local x = (rnd() - 0.5) * (w - 0.4)
		local z = (rnd() - 0.5) * (d - 0.4)
		K:cyl("FfTteok", 0.42, 0.12, base * CF(x, 0.26, z) * ANG(0, rnd() * PI, 0.05), L.of(244, 136, 104))
	end
	local nf = if ctx.low then 3 else 7
	for i = 1, nf do
		local x = (rnd() - 0.5) * (w - 0.5)
		local z = (rnd() - 0.5) * (d - 0.5)
		K:wedge("FfFishCake", V3(0.04, 0.26, 0.36), base * CF(x, 0.27, z) * ANG(0, rnd() * PI, PI / 2), L.of(206, 120, 80))
	end
	for i = 1, (if ctx.low then 1 else 3) do
		local x = (rnd() - 0.5) * (w - 0.6)
		local z = (rnd() - 0.5) * (d - 0.6)
		K:ell("FfEgg", V3(0.26, 0.2, 0.34), base * CF(x, 0.28, z) * ANG(0, rnd() * PI, 0), L.of(244, 220, 200))
	end
	if not ctx.low then
		for i = 1, 8 do
			local x = (rnd() - 0.5) * (w - 0.4)
			local z = (rnd() - 0.5) * (d - 0.4)
			K:cyl("FfScallion", 0.14, 0.04, base * CF(x, 0.27, z) * ANG(0, rnd() * PI, 0), L.of(90, 170, 60))
		end
		-- 큰 국자 (손잡이 걸쳐 둠)
		K:bar("FfLadle", (base * CF(w / 2 - 0.3, 0.3, d / 2 - 0.4)).Position, (base * CF(w / 2 + 0.2, 0.8, d / 2 - 0.2)).Position, 0.05, 0.04, L.steel)
		K:ell("FfLadleCup", V3(0.3, 0.12, 0.3), base * CF(w / 2 - 0.35, 0.28, d / 2 - 0.42), L.steel)
	end
end

-- 어묵 국물통: 칸막이 사각 통 + 국물 + 꼬치 (기대어 꽂힘)
local function eomukTank(ctx: any, base: CFrame, w: number, d: number, h: number?)
	local K = ctx.K
	local rnd = ctx.rand
	local hh = h or 0.7
	K:box("FfTankBody", V3(w, hh, d), base * CF(0, hh / 2, 0), L.of(196, 194, 188, M.Metal))
	K:box("FfTankBroth", V3(w - 0.1, 0.03, d - 0.1), base * CF(0, hh - 0.06, 0), { c = rgb(196, 146, 74), m = M.SmoothPlastic, r = 0.04 })
	K:box("FfTankRim", V3(w + 0.04, 0.05, 0.05), base * CF(0, hh + 0.02, d / 2), L.chrome)
	K:box("FfTankRim", V3(w + 0.04, 0.05, 0.05), base * CF(0, hh + 0.02, -d / 2), L.chrome)
	local nDiv = math.max(1, math.floor(w / 1.1))
	for i = 1, nDiv - 1 do
		K:box("FfTankDivider", V3(0.04, 0.2, d - 0.06), base * CF(-w / 2 + i * w / nDiv, hh - 0.04, 0), L.chrome)
	end
	local n = if ctx.low then 6 elseif ctx.high then 16 else 11
	for i = 1, n do
		local x = -w / 2 + 0.2 + (w - 0.4) * (i - 0.5) / n
		local z = (rnd() - 0.5) * (d - 0.4) - d * 0.12
		-- 손님 쪽(+Z) 테두리에 기대 꽂힌 꼬치: 아래는 국물 속, 위 손잡이는 테두리 밖으로
		local lean = ANG(0.55 + rnd() * 0.2, 0, (rnd() - 0.5) * 0.25)
		local sk = base * CF(x, hh - 0.08, z) * lean
		K:cyl("FfSkewer", 1.2, 0.04, sk * CF(0, 0.45, 0) * ANG(0, 0, PI / 2), L.of(214, 182, 130, M.Wood))
		if i % 4 == 0 then
			-- 긴 막대 어묵
			K:cyl("FfEomukStick", 0.7, 0.2, sk * CF(0, 0.18, 0) * ANG(0, 0, PI / 2), L.of(214, 160, 100))
		else
			-- 지그재그로 접어 꽂은 납작 어묵 (얇은 판 4겹, 번갈아 기울임)
			for k = 0, 3 do
				local c = if k % 2 == 0 then L.of(226, 186, 128) else L.of(212, 168, 108)
				K:box("FfEomuk", V3(0.5, 0.2, 0.05), sk * CF(0, -0.05 + k * 0.15, 0) * ANG(if k % 2 == 0 then 0.75 else -0.75, 0, 0), c)
			end
		end
	end
	-- 국물 위 무 · 곤약 · 달걀
	if not ctx.low then
		for i = 1, math.max(2, math.floor(w / 0.8)) do
			local x = -w / 2 + 0.3 + (w - 0.6) * rnd()
			local z = (rnd() - 0.5) * (d - 0.3)
			local k = i % 3
			if k == 0 then
				K:cyl("FfRadish", 0.14, 0.34, base * CF(x, hh - 0.06, z) * ANG(0, 0, PI / 2), L.of(236, 220, 180))
			elseif k == 1 then
				K:box("FfKonjac", V3(0.24, 0.1, 0.18), base * CF(x, hh - 0.05, z) * ANG(0, rnd() * PI, 0), L.of(120, 110, 104))
			else
				K:ell("FfOdengEgg", V3(0.24, 0.18, 0.3), base * CF(x, hh - 0.05, z), L.of(214, 170, 110))
			end
		end
	end
	K:bar("FfTankLadle", (base * CF(w / 2 - 0.2, hh, -d / 2 + 0.15)).Position, (base * CF(w / 2 + 0.1, hh + 0.7, -d / 2 - 0.05)).Position, 0.05, 0.04, L.steel)
end

-- 순대 찜기 (둥근 솥 + 뚜껑 + 손잡이) + 도마 위 썬 순대. 반환 뚜껑 Model (여닫기)
local function sundaeSteamer(ctx: any, base: CFrame, dia: number): any
	local K = ctx.K
	local h = 0.8
	K:vcyl("FfSteamerPot", h, dia, base * CF(0, h / 2, 0), L.of(190, 194, 198, M.Metal, { r = 0.1 }))
	K:vcyl("FfSteamerBand", 0.08, dia + 0.04, base * CF(0, h - 0.06, 0), L.chrome)
	for _, sx in { -1, 1 } do
		K:box("FfSteamerEar", V3(0.24, 0.06, 0.14), base * CF(sx * (dia / 2 + 0.08), h - 0.18, 0), L.chrome)
	end
	-- 안쪽 순대 (뚜껑 열면 보임)
	K:disc("FfSteamerInner", dia - 0.1, 0.02, base * CF(0, h - 0.12, 0), L.of(70, 60, 56))
	for i = 0, 2 do
		K:ring("FfSundaeCoil", base * CF(0, h - 0.08, 0) * ANG(PI / 2, 0, 0), dia * (0.14 + i * 0.1), 0.11, 6, L.of(46, 34, 40), 0, PI * 1.6)
	end
	local lid = K:group("FfSteamerLid", function()
		K:ell("FfSteamerLidDome", V3(dia + 0.04, 0.36, dia + 0.04), base * CF(0, h + 0.02, 0), L.of(200, 204, 208, M.Metal, { r = 0.12 }))
		K:vcyl("FfSteamerLidKnob", 0.12, 0.16, base * CF(0, h + 0.22, 0), L.black)
		K:box("FfSteamerLidHandle", V3(0.3, 0.06, 0.08), base * CF(0, h + 0.3, 0), L.black)
	end)
	return { lid = lid, hinge = (K.cf * base * CF(0, h + 0.02, -dia / 2)).Position, axis = (K.cf * base).RightVector }
end

local function sundaeBoard(ctx: any, base: CFrame)
	local K = ctx.K
	K:box("FfCutBoard", V3(1.1, 0.08, 0.75), base * CF(0, 0.04, 0), L.of(220, 200, 160, M.Wood))
	if not ctx.low then
		for i = 0, 5 do
			K:cyl("FfSundaeSlice", 0.08, 0.2, base * CF(-0.35 + i * 0.1, 0.18, 0.05) * ANG(0, 0, 0.2), L.of(50, 36, 42))
		end
		K:box("FfLiver", V3(0.22, 0.08, 0.16), base * CF(0.3, 0.12, -0.15), L.of(110, 50, 40))
		K:box("FfLiver", V3(0.2, 0.07, 0.14), base * CF(0.32, 0.12, 0.1), L.of(96, 44, 36))
		K:box("FfKnife", V3(0.5, 0.02, 0.1), base * CF(0.1, 0.09, -0.27), L.chrome)
		K:box("FfKnifeGrip", V3(0.24, 0.05, 0.08), base * CF(0.46, 0.1, -0.27), L.black)
	end
end

-- 튀김 진열대: 철망 트레이 + 튀김 (김말이 · 오징어 · 고구마 · 야채) + 유리 덮개 + 열 램프
local function twigimCase(ctx: any, base: CFrame, w: number, d: number, o: any?)
	local K = ctx.K
	local rnd = ctx.rand
	local oo: any = o or {}
	K:box("FfTwigimTray", V3(w, 0.08, d), base * CF(0, 0.04, 0), L.of(190, 194, 198, M.Metal))
	K:box("FfTwigimPaper", V3(w - 0.2, 0.012, d - 0.2), base * CF(0, 0.086, 0), L.of(246, 240, 220, M.Fabric))
	local n = if ctx.low then 8 elseif ctx.high then 20 else 14
	for i = 1, n do
		local x = -w / 2 + 0.3 + (w - 0.6) * ((i - 1) % 5 + 0.5) / 5
		local z = -d / 2 + 0.3 + (d - 0.6) * (math.floor((i - 1) / 5) + 0.5) / math.ceil(n / 5)
		local k = i % 4
		local p = base * CF(x + (rnd() - 0.5) * 0.12, 0.16, z) * ANG(0, (rnd() - 0.5) * 0.5, 0)
		if k == 0 then
			K:cyl("FfGimmari", 0.5, 0.16, p, L.of(206, 150, 70)) -- 김말이
		elseif k == 1 then
			K:ell("FfSquidFry", V3(0.5, 0.16, 0.26), p, L.of(222, 176, 96)) -- 오징어
		elseif k == 2 then
			K:ell("FfSweetPotato", V3(0.42, 0.12, 0.3), p, L.of(214, 140, 60)) -- 고구마
		else
			K:ell("FfVegFry", V3(0.44, 0.2, 0.4), p, L.of(196, 150, 70)) -- 야채
		end
	end
	if oo.cover ~= false then
		local ch = 0.9
		K:box("FfTwigimGlassF", V3(w, ch, 0.03), base * CF(0, 0.08 + ch / 2, d / 2) * ANG(-0.2, 0, 0), { c = rgb(224, 236, 240), m = M.Glass, t = 0.75, r = 0.15 })
		K:box("FfTwigimGlassT", V3(w, 0.03, d * 0.6), base * CF(0, 0.08 + ch, -d * 0.2), { c = rgb(224, 236, 240), m = M.Glass, t = 0.75, r = 0.15 })
		K:box("FfTwigimLamp", V3(w - 0.2, 0.05, 0.08), base * CF(0, 0.06 + ch, -d * 0.2), neon(rgb(255, 160, 80)))
		for _, sx in { -1, 1 } do
			K:box("FfTwigimSide", V3(0.04, ch, d), base * CF(sx * w / 2, 0.08 + ch / 2, 0), L.chrome)
		end
	end
end

-- 김밥 말이대: 도마 + 김발 + 말아 놓은 김밥 + 썬 김밥 + 재료 칸
local function gimbapStation(ctx: any, base: CFrame, w: number, d: number)
	local K = ctx.K
	K:box("FfGimbapBoard", V3(w, 0.1, d), base * CF(0, 0.05, 0), L.of(214, 184, 140, M.Wood))
	K:box("FfBambooMat", V3(0.9, 0.03, 0.7), base * CF(-w / 2 + 0.6, 0.115, 0.05), L.of(150, 170, 90, M.Wood))
	K:box("FfGim", V3(0.8, 0.012, 0.6), base * CF(-w / 2 + 0.6, 0.135, 0.05), L.of(24, 30, 22))
	K:box("FfRice", V3(0.7, 0.03, 0.4), base * CF(-w / 2 + 0.6, 0.15, 0.1), L.of(248, 246, 238))
	for i = 0, 2 do
		K:cyl("FfGimbapRoll", 1.0, 0.24, base * CF(0.0, 0.22, -d / 2 + 0.22 + i * 0.27), L.of(26, 30, 24))
	end
	if not ctx.low then
		for i = 0, 6 do
			local p = base * CF(w / 2 - 0.9 + i * 0.13, 0.2, d / 2 - 0.25) * ANG(0, 0, PI / 2)
			K:cyl("FfGimbapSlice", 0.1, 0.24, p * ANG(0, 0, 0), L.of(26, 30, 24))
			K:cyl("FfGimbapRice", 0.104, 0.19, p, L.of(248, 246, 238))
			K:cyl("FfGimbapCore", 0.108, 0.08, p, L.of(240, 180, 40))
		end
	end
	-- 재료 칸 (단무지 · 당근 · 시금치 · 햄 · 계란)
	local cols = { rgb(250, 214, 40), rgb(236, 120, 40), rgb(60, 140, 50), rgb(236, 140, 140), rgb(250, 230, 120) }
	local n = if ctx.low then 3 else 5
	for i = 1, n do
		local x = -w / 2 + 0.3 + (i - 1) * 0.42
		local p = base * CF(x, 0.1, -d / 2 + 0.05)
		K:box("FfFillPan", V3(0.38, 0.14, 0.32), p * CF(0, 0.07, 0.16), L.steel)
		K:box("FfFill", V3(0.32, 0.04, 0.26), p * CF(0, 0.13, 0.16), pl(cols[i]))
	end
end

-- 분식 조리대 (벽에 붙은 스테인리스 작업대 + 모듈들). pcf 앞 = 방 쪽. len 길이
local function snackStation(ctx: any, pcf: CFrame, len: number, o: any?): any
	local K = ctx.K
	local P = ctx.pal
	local h, d = 3.2, 2.0
	-- 본체 (타일 앞판 + 스테인리스 상판 + 아래 선반)
	K:box("FfStationBody", V3(len, h - 0.4, d - 0.1), pcf * CF(0, 0.3 + (h - 0.4) / 2 - 0.1, -0.05), L.of(190, 194, 198, M.Metal))
	K:box("FfStationKick", V3(len - 0.1, 0.3, d - 0.3), pcf * CF(0, 0.15, -0.15), L.black)
	K:box("FfStationTop", V3(len + 0.06, 0.1, d + 0.04), pcf * CF(0, h - 0.05, 0), L.of(206, 210, 214, M.Metal, { r = 0.1 }))
	local fh = h - 0.75
	K:plate("FfStationFront", len - 0.1, fh, 0.04, pcf * CF(0, 0.35 + fh / 2, d / 2 - 0.08), L.of(P.tileAcc.R * 255, P.tileAcc.G * 255, P.tileAcc.B * 255, M.CeramicTiles))
	if not ctx.low then
		for i = 1, 2 do
			K:plate("FfStationGrout", len - 0.1, 0.025, 0.045, pcf * CF(0, 0.35 + fh * i / 3, d / 2 - 0.08), L.of(240, 236, 230))
		end
	end
	K:text("FfStationBand", len - 0.4, 0.36, pcf * CF(0, h - 0.32, d / 2 - 0.035), "즉석 떡볶이 · 튀김 · 순대 · 김밥 · 어묵", { fg = WHITE, bg = dark(P.accent, 0.1), font = F.GothamBlack, d = 0.01 })
	local y = h
	-- 모듈 배치: 순대 찜기는 방 구석 쪽 끝 (손님이 뚜껑을 열어 볼 수 있게), 이어서 튀김 · 떡볶이 · 어묵 · 김밥
	local mods = {}
	local out: any = {}
	local flip = (o and o.steamerRight) == true
	local x = -len / 2 + 0.15
	local function take(wd: number): number?
		if x + wd > len / 2 - 0.15 then
			return nil
		end
		local c = x + wd / 2
		x += wd + 0.12
		return if flip then -c else c
	end
	local order = { "sundae", "twigim", "pan", "eomuk", "gimbap" }
	for _, m in order do
		if m == "sundae" then
			local sc = take(1.25)
			if sc then
				out.steamer = sundaeSteamer(ctx, pcf * CF(sc, y, -0.25), 1.1)
				sundaeBoard(ctx, pcf * CF(sc, y, 0.62))
				table.insert(mods, m)
			end
		elseif m == "twigim" then
			local tc = take(2.2)
			if tc then
				twigimCase(ctx, pcf * CF(tc, y, 0.05), 2.1, 1.5)
				table.insert(mods, m)
			end
		elseif m == "pan" then
			local pc = take(2.8)
			if pc then
				tteokPan(ctx, pcf * CF(pc, y, 0.05), 2.7, 1.6)
				K:box("FfPanBurner", V3(2.7, 0.06, 1.6), pcf * CF(pc, y + 0.0, 0.05), L.of(40, 40, 42, M.Metal))
				table.insert(mods, m)
			end
		elseif m == "eomuk" then
			local ec = take(2.0)
			if ec then
				eomukTank(ctx, pcf * CF(ec, y, 0.0), 1.9, 1.4)
				table.insert(mods, m)
			end
		else
			local gc = take(2.1)
			if gc then
				gimbapStation(ctx, pcf * CF(gc, y, 0.1), 2.0, 1.4)
				table.insert(mods, m)
			end
		end
	end
	out.mods = mods
	-- 뒤 벽 아래 받침 선반 위 양념 통 (고춧가루 · 물엿)
	if not ctx.low then
		local wc = pcf * CF(0, 0, -d / 2 - 0.06)
		local sh = Props.shelf(K, wc * CF(0, h + 1.6, 0), math.min(len - 0.6, 5), { depth = 0.6, look = L.steel, bracket = L.steel })
		local cols = { rgb(190, 40, 24), rgb(236, 190, 90), rgb(60, 40, 30), rgb(250, 250, 246), rgb(190, 40, 24) }
		local n = math.min(5, math.floor((math.min(len - 0.6, 5) - 0.4) / 0.6))
		for i = 1, n do
			local xx = -(n - 1) * 0.3 + (i - 1) * 0.6
			K:vcyl("FfSeasoning", 0.55, 0.4, sh * CF(xx, 0.275, 0), { c = cols[i], m = M.Plastic, t = 0.05 })
			K:vcyl("FfSeasoningLid", 0.08, 0.42, sh * CF(xx, 0.59, 0), L.of(230, 60, 50, M.Plastic))
		end
	end
	return out
end

-- 손글씨 가격판 (화이트보드 + 마커 글씨)
local function priceBoard(ctx: any, dcf: CFrame, w: number, h: number, title: string, items: { any })
	local K = ctx.K
	local P = ctx.pal
	K:plate("FfBoardFrame", w + 0.16, h + 0.16, 0.06, dcf, L.alu)
	K:plate("FfBoard", w, h, 0.07, dcf, L.of(252, 252, 250))
	K:text("FfBoardTitle", w * 0.8, 0.5, dcf * CF(0, h / 2 - 0.36, 0.075), title, { fg = P.accent, font = F.PermanentMarker, d = 0.004 })
	local rows = #items
	local rh = (h - 0.9) / rows
	for i, it in items do
		local y = h / 2 - 0.75 - rh * (i - 0.5)
		local c = if i % 3 == 0 then rgb(30, 70, 170) else rgb(30, 30, 30)
		K:text("FfBoardItem", w * 0.55, rh * 0.8, dcf * CF(-w * 0.2, y, 0.075), it[1], { fg = c, font = F.PermanentMarker, align = "Left", d = 0.004 })
		K:text("FfBoardPrice", w * 0.32, rh * 0.8, dcf * CF(w * 0.3, y, 0.075), it[2], { fg = c, font = F.PermanentMarker, align = "Right", d = 0.004 })
	end
	if not ctx.low then
		K:box("FfMarkerTray", V3(w * 0.6, 0.06, 0.18), dcf * CF(0, -h / 2 - 0.05, 0.09), L.alu)
		for i, c in { rgb(200, 30, 30), rgb(30, 70, 170), rgb(30, 30, 30) } do
			K:cyl("FfMarker", 0.4, 0.07, dcf * CF(-0.4 + i * 0.3, -h / 2 + 0.01, 0.1), pl(c))
		end
		-- 자석 쿠폰 · 메모
		K:plate("FfBoardMemo", 0.5, 0.5, 0.008, dcf * CF(w / 2 - 0.4, -h / 2 + 0.45, 0.075) * ANG(0, 0, 0.08), L.of(255, 236, 120))
		K:text("FfBoardMemoText", 0.44, 0.42, dcf * CF(w / 2 - 0.4, -h / 2 + 0.45, 0.085) * ANG(0, 0, 0.08), "쿠폰 10장\n= 떡볶이\n1인분", { fg = rgb(60, 40, 20), font = F.PermanentMarker, d = 0.002 })
	end
end

-- 셀프 단무지 · 물 · 컵 소독기
local function danmujiSelf(ctx: any, pcf: CFrame, w: number)
	local K = ctx.K
	local P = ctx.pal
	local h, d = 3.0, 1.2
	local top = cabinet(ctx, pcf, w, h, d, L.of(P.tileAcc.R * 255, P.tileAcc.G * 255, P.tileAcc.B * 255), L.steel, { doors = 2 })
	local dj = pcf * CF(-w / 2 + 0.55, top, 0)
	K:box("FfDanmujiTub", V3(0.8, 0.4, 0.62), dj * CF(0, 0.2, 0), { c = rgb(236, 244, 236), m = M.Glass, t = 0.4 })
	K:box("FfDanmuji", V3(0.7, 0.28, 0.54), dj * CF(0, 0.16, 0), L.of(250, 214, 40))
	K:bar("FfDanmujiTongs", (dj * CF(0.3, 0.42, 0.1)).Position, (dj * CF(0.48, 0.44, 0.4)).Position, 0.05, 0.03, L.steel)
	K:text("FfDanmujiLabel", 0.6, 0.18, dj * CF(0, 0.22, 0.315), "셀프 단무지", { fg = WHITE, bg = P.accent, font = F.GothamBlack, d = 0.004 })
	-- 물병 · 종이컵
	for i = 0, 1 do
		local b = pcf * CF(0.0 + i * 0.36, top, -0.2)
		K:vcyl("FfWaterBottle", 0.75, 0.28, b * CF(0, 0.375, 0), { c = rgb(200, 220, 240), m = M.Plastic, t = 0.35 })
		K:vcyl("FfWaterCap", 0.1, 0.16, b * CF(0, 0.8, 0), L.of(40, 120, 220, M.Plastic))
	end
	K:vcyl("FfPaperCups", 0.6, 0.24, pcf * CF(0.2, top + 0.3, 0.3), L.of(250, 250, 246))
	-- 벽에 컵 소독기 (UV 자외선 · 한국 식당 필수품): 스테인리스 틀 + 보라빛 유리문 + 안의 컵 선반
	local wc = pcf * CF(0, 0, -d / 2 - 0.06)
	local uv = wc * CF(w / 2 - 0.8, h + 1.5, 0)
	local st = L.of(196, 200, 204, M.Metal, { r = 0.1 })
	K:plate("FfUVBack", 1.3, 1.5, 0.06, uv, st)
	K:plate("FfUVSide", 0.06, 1.5, 0.62, uv * CF(-0.62, 0, 0), st)
	K:plate("FfUVSide", 0.06, 1.5, 0.62, uv * CF(0.62, 0, 0), st)
	K:plate("FfUVTop", 1.3, 0.12, 0.62, uv * CF(0, 0.69, 0), st)
	K:plate("FfUVBottom", 1.3, 0.12, 0.62, uv * CF(0, -0.69, 0), st)
	K:plate("FfUVShelf", 1.18, 0.04, 0.5, uv * CF(0, -0.05, 0.06), L.chrome)
	K:plate("FfUVGlow", 1.1, 0.04, 0.03, uv * CF(0, 0.58, 0.1), neon(rgb(150, 110, 255)))
	if not ctx.low then
		for row = 0, 1 do
			for i = 0, 2 do
				K:vcyl("FfUVCup", 0.34, 0.24, uv * CF(-0.38 + i * 0.38, -0.45 + row * 0.42, 0.3), L.steel)
			end
		end
	end
	K:plate("FfUVGlass", 1.18, 1.26, 0.03, uv * CF(0, 0, 0.6), { c = rgb(160, 130, 255), m = M.Glass, t = 0.55, r = 0.15 })
	K:plate("FfUVHandle", 0.5, 0.06, 0.06, uv * CF(0, 0.5, 0.63), L.chrome)
	K:text("FfUVLabel", 1.0, 0.16, uv * CF(0, -0.62, 0.63), "자외선 컵 소독기", { fg = rgb(40, 40, 50), bg = rgb(236, 238, 240), font = F.GothamBold, d = 0.004 })
end

-- 분식 벽 포스터 묶음
local function snackPosters(ctx: any)
	local P = ctx.pal
	local pT = priceIn(ctx.signs, "떡볶이", "4,500")
	local p1, w1 = wallSpotFit(ctx, { "left", "right", "back" }, { 2.6, 2.0 }, 3.9, 6.9, -2)
	if p1 then
		local k = (w1 - 0.2) / 2.4
		poster(ctx, p1, 2.4 * k, 2.9 * k, {
			bg = P.accent,
			frame = L.of(250, 250, 250),
			glass = true,
			art = artTteok(0, -0.05 * k, 1.3 * k),
			texts = {
				{ "국물 떡볶이", 0, 1.0 * k, 2.0 * k, 0.44 * k, WHITE, F.GothamBlack },
				{ "매일 직접 만든 양념장", 0, 0.62 * k, 1.9 * k, 0.24 * k, rgb(255, 230, 160), F.GothamBold },
				{ "1인분 " .. pT .. "원", 0, -1.02 * k, 1.8 * k, 0.38 * k, P.gold, F.GothamBlack },
			},
		})
	end
	local p2, w2 = wallSpotFit(ctx, { "right", "left", "back" }, { 2.6, 2.0 }, 3.9, 6.9, 2)
	if p2 then
		local k = (w2 - 0.2) / 2.4
		local a = artTteok(-0.5 * k, 0.15 * k, 0.8 * k)
		for _, q in artGimbap(0.4 * k, -0.25 * k, 0.8 * k) do
			table.insert(a, q)
		end
		poster(ctx, p2, 2.4 * k, 2.9 * k, {
			bg = rgb(255, 236, 170),
			frame = L.of(250, 250, 250),
			glass = true,
			art = a,
			texts = {
				{ "떡튀순 세트", 0, 1.02 * k, 2.0 * k, 0.44 * k, rgb(190, 30, 24), F.GothamBlack },
				{ "떡볶이 + 튀김 + 순대", 0, 0.62 * k, 1.9 * k, 0.26 * k, rgb(60, 40, 20), F.GothamBold },
				{ "12,000원", 0, -1.02 * k, 1.6 * k, 0.4 * k, rgb(190, 30, 24), F.GothamBlack },
			},
		})
	end
	-- 매운맛 단계 안내
	local p3 = wallSpot(ctx, { "left", "right", "back" }, 2.4, 4.0, 6.2, -5)
	if p3 then
		local K = ctx.K
		K:plate("FfSpicyBack", 2.3, 2.0, 0.04, p3, pl(rgb(30, 26, 24)))
		K:text("FfSpicyTitle", 2.0, 0.42, p3 * CF(0, 0.7, 0.045), "매운맛 단계", { fg = P.gold, font = F.GothamBlack, d = 0.005 })
		for i, s in { { "순한맛", rgb(250, 190, 60) }, { "보통맛", rgb(240, 120, 40) }, { "매운맛", rgb(220, 40, 30) }, { "지옥맛", rgb(120, 10, 10) } } do
			local x = -0.84 + (i - 1) * 0.56
			K:disc("FfSpicyDot", 0.46, 0.04, p3 * CF(x, 0.05, 0.06) * ANG(PI / 2, 0, 0), pl(s[2]))
			K:text("FfSpicyText", 0.54, 0.22, p3 * CF(x, -0.42, 0.045), s[1], { fg = WHITE, font = F.GothamBold, d = 0.005 })
		end
		K:text("FfSpicyFoot", 2.0, 0.24, p3 * CF(0, -0.78, 0.045), "주문 시 말씀해 주세요", { fg = rgb(200, 200, 196), font = F.GothamBold, d = 0.005 })
	end
end

local function bunsikBuild(ctx: any)
	local K, V, S = ctx.K, ctx.V, ctx.S
	local P = ctx.pal
	local pT = priceIn(ctx.signs, "떡볶이", "4,500")
	local pG = priceIn(ctx.signs, "김밥", "3,500")
	local pE = priceIn(ctx.signs, "어묵", "1,000")
	if not ctx.gw then
		local lh = if S.lower then S.lower.h else 0.45
		upperPaint(ctx, { "left", "right" }, lh + 0.08, pl(P.wall, M.Plaster))
		upperPaint(ctx, { "back" }, lh + 0.08, pl(dark(P.wall2, 0.08), M.Plaster))
		wallBand(ctx, { "left", "right", "back" }, lh + 0.05, 0.2, 0.06, pl(if P.key == "red" then rgb(30, 26, 24) else P.wall2))
		wallBand(ctx, { "left", "right" }, V.H - 0.7, 0.3, 0.05, pl(P.wall2))
	end
	passDress(ctx, { trim = L.steel, header = "noren", norenText = { "분", "식", "주", "방" }, norenColor = if P.key == "mint" then rgb(30, 120, 100) else rgb(30, 40, 90), utensil = "ladle" })
	menuSignDress(ctx, pl(P.wall2), nil)
	for i = 1, 2 do
		local fd = if i == 1 then promptWallSpot(ctx, { "left", "right", "back" }, 1.6, 6.9, 8.5) else nil
		if not fd then
			fd = wallSpot(ctx, { if i == 1 then "left" else "right", if i == 1 then "right" else "left" }, 1.6, 6.9, 8.5, (i * 2 - 3) * 1.5)
		end
		if fd then
			wallFan(ctx, fd * CF(0, 0.4, 0))
		end
	end
	local gwStation = V:has("Pan") > 0 or V:has("EomukTank") > 0
	local stationRec: any = nil
	if gwStation then
		-- GwShop 조리대: 맵 음식 파트 자리에 같은 크기로 다시 (원본 숨김)
		K:free(function()
			for _, r in V.byName.Pan or {} do
				tteokPan(ctx, CF(r.c.X, r.min.Y, r.c.Z), r.size.X, r.size.Z)
				Scan.hide(K.hidden, r.part)
			end
			for _, nm in { "Sauce", "Tteok", "FishCake" } do
				for _, r in V.byName[nm] or {} do
					Scan.hide(K.hidden, r.part)
				end
			end
			for _, r in V.byName.EomukTank or {} do
				eomukTank(ctx, CF(r.c.X, r.min.Y, r.c.Z) * ANG(0, PI / 2, 0), r.size.Z, r.size.X, r.size.Y)
				Scan.hide(K.hidden, r.part)
			end
			for _, nm in { "EomukBroth", "Skewer", "Eomuk" } do
				for _, r in V.byName[nm] or {} do
					Scan.hide(K.hidden, r.part)
				end
			end
			for _, r in V.byName.SundaeSteamer or {} do
				stationRec = { steamer = sundaeSteamer(ctx, CF(r.c.X, r.min.Y, r.c.Z), math.min(r.size.X, r.size.Z)) }
				Scan.hide(K.hidden, r.part)
			end
			for _, r in V.byName.SteamerLid or {} do
				Scan.hide(K.hidden, r.part)
			end
			for _, r in V.byName.GimbapBoard or {} do
				gimbapStation(ctx, CF(r.c.X, r.min.Y, r.c.Z) * ANG(0, PI / 2, 0), r.size.Z, r.size.X)
				Scan.hide(K.hidden, r.part)
			end
			for _, r in V.byName.GimbapRoll or {} do
				Scan.hide(K.hidden, r.part)
			end
			for _, r in V.byName.CasePaper or {} do
				twigimCase(ctx, CF(r.c.X, r.min.Y - 0.08, r.c.Z) * ANG(0, PI / 2, 0), r.size.Z, r.size.X, { cover = false })
				Scan.hide(K.hidden, r.part)
			end
			for _, r in V.byName.Twigim or {} do
				Scan.hide(K.hidden, r.part)
			end
		end)
	else
		local len = math.clamp(V.W * 0.42, 6.5, 11.5)
		local spcf = nil
		local tries = { len, 9.0, 7.6, 6.4 }
		for _, l in tries do
			if l <= len + 0.01 then
				spcf = floorSpot(ctx, { walls = { "back", "left", "right" }, w = l, h = 5.4, d = 2.0, pref = { back = "left", left = "back", right = "back" }, front = 1.2, above = 2.4 })
				if spcf then
					len = l
					break
				end
			end
		end
		if spcf then
			-- 찜기를 가까운 구석 쪽 끝에 (pcf 의 +X 쪽이 방 오른쪽 구석이면 오른쪽)
			local rightEnd = (spcf * CF(len / 2, 0, 0)).Position
			local leftEnd = (spcf * CF(-len / 2, 0, 0)).Position
			local function cornerDist(p: Vector3): number
				return math.min(math.abs(p.X - V.x0), math.abs(p.X - V.x1)) + math.min(math.abs(p.Z - V.z0), math.abs(p.Z - V.z1))
			end
			stationRec = snackStation(ctx, spcf, len, { steamerRight = cornerDist(rightEnd) < cornerDist(leftEnd) })
			-- 조리대 위 벽: 손글씨 가격판 (간판 · 다른 장식과 겹치면 다른 빈 벽으로)
			local wc = spcf * CF(0, 0, -1.0 - 0.06)
			local bw = math.min(3.4, len / 2 - 0.3)
			local _, swn, su = nil, nil, nil
			local bcf = wc * CF(-len / 4, 6.9, 0)
			local pw = math.min(3.2, len / 2 - 0.4)
			local pcf2 = wc * CF(len / 4, 6.9, 0)
			for _, wn in { "back", "left", "right" } do
				local u, dd = V:wallCoord(wn, bcf.Position)
				if math.abs(dd) < 0.3 then
					swn, su = wn, u
				end
			end
			local okB = swn ~= nil and spanFree(ctx, swn :: string, (su :: number) - bw / 2 - 0.1, (su :: number) + bw / 2 + 0.1, 5.6, 8.2, true)
			local okP = false
			if swn then
				local u2 = V:wallCoord(swn :: string, pcf2.Position)
				okP = spanFree(ctx, swn :: string, u2 - pw / 2 - 0.1, u2 + pw / 2 + 0.1, 5.7, 8.1, true)
				if okP then
					markWall(K, swn :: string, u2 - pw / 2 - 0.1, u2 + pw / 2 + 0.1, 5.7, 8.1)
				end
				if okB then
					markWall(K, swn :: string, (su :: number) - bw / 2 - 0.1, (su :: number) + bw / 2 + 0.1, 5.6, 8.2)
				end
			end
			if not okB then
				bcf = wallSpot(ctx, { "left", "right", "back" }, bw + 0.2, 5.6, 8.2, 0) :: any
			end
			if not okP then
				pcf2 = wallSpot(ctx, { "right", "left", "back" }, pw + 0.2, 5.7, 8.1, 0) :: any
			end
			if bcf then
			priceBoard(ctx, bcf, bw, 2.3, "오늘의 메뉴", {
				{ "떡볶이", pT },
				{ "순대", "5,000" },
				{ "튀김 (3개)", "4,000" },
				{ "김밥", pG },
				{ "어묵 (1개)", pE },
			})
			end
			-- 오른쪽 위: 메뉴 사진 액자
			if pcf2 then
			poster(ctx, pcf2, pw, 2.2, {
				bg = rgb(250, 246, 236),
				frame = L.of(220, 220, 220, M.Metal),
				art = artTteok(-0.7, 0.1, 0.9),
				texts = {
					{ "라볶이 6,500", 0.65, 0.35, 1.4, 0.32, rgb(190, 30, 24), F.GothamBlack },
					{ "쫄면 7,000", 0.65, -0.05, 1.4, 0.32, rgb(40, 30, 20), F.GothamBlack },
					{ "참치김밥 4,500", 0.65, -0.45, 1.4, 0.3, rgb(40, 30, 20), F.GothamBlack },
				},
			})
			end
		end
	end
	-- 순대 찜기 뚜껑 열기 (상호작용)
	if stationRec and stationRec.steamer then
		local st = stationRec.steamer
		local knob = nil
		for _, p in st.lid:GetDescendants() do
			if p:IsA("BasePart") and string.find(p.Name, "Handle") then
				knob = p
			end
		end
		if knob and Interact.canPrompt(K, K.cf:PointToObjectSpace(knob.Position)) then
			Interact.swing(K, st.lid, st.hinge, st.axis, -1.1, { object = "순대 찜기", openText = "뚜껑 열기", closeText = "뚜껑 닫기" })
		end
	end
	-- 음료 냉장고 (콜라 · 사이다 · 쿨피스)
	if not ctx.gw then
		placeFridge(ctx, { walls = { "back", "right", "left" }, pref = { back = "right", right = "back", left = "back" }, header = "음료수 · 쿨피스", headerBg = P.accent, items = {
			{ rgb(200, 24, 32), "can", rgb(200, 24, 32) },
			{ rgb(40, 150, 70), "can" },
			{ rgb(250, 160, 190), "pet", rgb(250, 120, 160) },
			{ rgb(236, 120, 30), "can" },
			{ rgb(200, 230, 240), "pet", rgb(40, 120, 210) },
			{ rgb(250, 230, 120), "can" },
		}, brand = "SHOWCASE" })
	end
	-- 셀프 단무지 · 물 (옆벽 앞쪽)
	local dp = floorSpot(ctx, { walls = { "left", "right", "back" }, w = 2.4, h = 5.2, d = 1.2, pref = { left = "back", right = "back" }, front = 1.0 })
	if dp then
		danmujiSelf(ctx, dp, 2.4)
	end
	-- 벽: 선풍기 2 · TV · 포스터 · 안내
	-- 사진 메뉴 띠 (옆벽 위)
	local sw0 = math.min(12.4, math.max(V.D - 5.5, V.W - 6))
	if sw0 > 5 then
		local sd, fw = wallSpotFit(ctx, { "right", "left", "back" }, { sw0 + 0.3, 9.3, 6.3 }, 7.0, 8.95, 0)
		if not sd and V.H > 9.4 then
			-- 조리대 위 선반 물건이 7 높이까지 올라오는 가게: 조금 더 높은 띠
			sd, fw = wallSpotFit(ctx, { "left", "right", "back" }, { sw0 + 0.3, 9.3, 6.3 }, 7.25, 9.2, 0)
		end
		local sw = fw - 0.3
		if sd and sw > 4.5 then
			local items = {
				{ "떡볶이", pT, artTteok(0, 0.2, 0.6) },
				{ "순대", "5,000", artSundae(0, 0.2, 0.6) },
				{ "모듬튀김", "4,000", artTwigim(0, 0.2, 0.6) },
				{ "김밥", pG, artGimbap(0, 0.2, 0.55) },
				{ "어묵", pE, artEomuk(0, 0.2, 0.6) },
				{ "라볶이", "6,500", artNoodle(0, 0.2, 0.55, rgb(196, 50, 28), nil) },
				{ "쫄면", "7,000", artNoodle(0, 0.2, 0.55, rgb(220, 90, 50), rgb(90, 170, 60)) },
				{ "라면", "4,500", artNoodle(0, 0.2, 0.55, rgb(200, 90, 40), rgb(250, 230, 120)) },
			}
			local n = math.clamp(math.floor(sw / 1.5), 3, 8)
			while #items > n do
				table.remove(items)
			end
			photoStrip(ctx, sd, sw, 1.8, items, { priceC = P.accent, frame = pl(dark(P.wall2, 0.1)) })
		end
	end
	if V:has("TV") == 0 and V:has("MonitorScreen") == 0 then
		local d = wallSpot(ctx, { "left", "right", "back" }, 3.4, 6.2, 8.3, 4)
		if d then
			tvSet(ctx, d, 3.0, {
				{ "예능", rgb(90, 60, 150), {
					{ "b", 0, -0.05, 1.0, 0.5, rgb(240, 120, 160) },
					{ "e", -0.22, 0.0, 0.16, 0.26, rgb(250, 214, 180) },
					{ "b", -0.22, -0.2, 0.2, 0.2, rgb(40, 90, 200) },
					{ "e", 0.18, 0.0, 0.16, 0.26, rgb(240, 200, 170) },
					{ "b", 0.18, -0.2, 0.2, 0.2, rgb(250, 200, 40) },
					{ "b", 0, -0.36, 0.8, 0.12, rgb(255, 230, 40) },
				}, "분식 먹방 대결!", "떡볶이 10인분 도전 ㅋㅋㅋ" },
				{ "드라마", rgb(60, 50, 90), { { "e", 0, -0.05, 0.3, 0.6, rgb(230, 200, 180) } }, "주말 드라마 · 부산 사나이", "본방 사수!" },
				{ "뉴스", rgb(20, 46, 110), { { "b", 0, -0.42, 1.0, 0.12, rgb(200, 24, 32) } }, "부산 날씨  맑음 22°C", "광안리 불꽃축제 11월 8일 개최" },
			}, "TV")
		end
	end
	snackPosters(ctx)
	wallMural(ctx, { "left", "right", "back" }, "떡볶이는 사랑입니다", "1998년부터 같은 맛 · 매일 아침 뽑는 쌀떡", P.accent, P.ink)
	infoSet(ctx, {
		origin = { "쌀 : 국내산", "떡(쌀) : 국내산", "어묵(연육) : 수입산", "순대(돼지 창자) : 국내산", "배추김치 : 국내산", "고춧가루 : 국내산" },
		hours = "영업시간\n10:00 - 22:00",
		ssid = "BUNSIK_5G",
		pw = "tteok4500",
		stickers = {
			{ "카드 · 페이\n결제 가능", rgb(40, 90, 200) },
			{ "포장 · 배달\n가능", rgb(220, 60, 40) },
			{ "셀프\n물 · 단무지", rgb(40, 150, 90) },
		},
	})
end

-- 오뎅바 ----------------------------------------------------------------------------------------------
-- 나무 메뉴 패 (이자카야식 세로 나무판 줄)
local function woodPlaques(ctx: any, dcf: CFrame, items: { any }, o: any?)
	local K = ctx.K
	local oo: any = o or {}
	local n = #items
	local pw, ph = 0.62, 2.2
	local gap = 0.1
	local total = n * pw + (n - 1) * gap
	K:plate("FfPlaqueRail", total + 0.4, 0.12, 0.08, dcf * CF(0, ph / 2 + 0.12, 0), L.darkWood)
	for i, it in items do
		local x = -total / 2 + pw / 2 + (i - 1) * (pw + gap)
		local c = dcf * CF(x, 0, 0.0)
		K:plate("FfPlaque", pw, ph, 0.06, c, L.of(222, 196, 150, M.Wood))
		K:text("FfPlaqueName", pw - 0.1, ph * 0.66, c * CF(0, 0.3, 0.065), it[1], { fg = rgb(30, 20, 14), font = F.GothamBlack, d = 0.004, wrap = true })
		K:text("FfPlaquePrice", pw - 0.08, 0.32, c * CF(0, -ph / 2 + 0.3, 0.065), it[2], { fg = oo.priceC or rgb(180, 30, 24), font = F.GothamBold, d = 0.004 })
		if not ctx.low then
			K:cyl("FfPlaqueNail", 0.06, 0.06, c * CF(0, ph / 2 - 0.1, 0.09) * ANG(0, PI / 2, 0), L.brass)
		end
	end
end

-- 빨간 제등 (종이 등): 천장에서 끈으로
local function lantern(ctx: any, top: Vector3, drop: number, text: string, c: Color3?)
	local K = ctx.K
	local col = c or rgb(200, 36, 30)
	local p = top - V3(0, drop, 0)
	K:seg("FfLanternCord", top, p + V3(0, 0.75, 0), 0.04, L.black)
	K:disc("FfLanternCap", 0.42, 0.1, CF(p + V3(0, 0.7, 0)), L.black)
	local body = K:ell("FfLantern", V3(0.95, 1.3, 0.95), CF(p), { c = col, m = M.Neon, t = 0.25 })
	K:disc("FfLanternCap", 0.42, 0.1, CF(p - V3(0, 0.66, 0)), L.black)
	if not ctx.low then
		for i = -1, 1 do
			K:disc("FfLanternRib", 0.96 - math.abs(i) * 0.22, 0.02, CF(p + V3(0, i * 0.34, 0)), { c = dark(col, 0.45), m = M.SmoothPlastic })
		end
		K:seg("FfLanternTassel", p - V3(0, 0.7, 0), p - V3(0, 1.05, 0), 0.06, L.black)
	end
	-- 글자 (양면)
	K:text("FfLanternText", 0.5, 0.8, CF(p + V3(0, 0, 0.47)), text, { fg = rgb(30, 10, 8), font = F.GothamBlack, d = 0.005 })
	return body
end

-- 오뎅 통 (카운터 뒤쪽 3분의 1, 상판에 묻힌 사각 통 + 칸막이 + 꼬치)
local function odengTrough(ctx: any)
	local K, V = ctx.K, ctx.V
	local g = V.counters[1]
	if not g then
		return
	end
	local alongX = (g.max.X - g.min.X) >= (g.max.Z - g.min.Z)
	if not alongX then
		return
	end
	-- 맥주 탭 · 드립 트레이 자리는 피함
	local avoid0, avoid1 = math.huge, -math.huge
	for _, nm in { "TapPost", "TapBar", "DripTray", "TapHandle" } do
		for _, r in V.byName[nm] or {} do
			avoid0 = math.min(avoid0, r.min.X - 0.6)
			avoid1 = math.max(avoid1, r.max.X + 0.6)
		end
	end
	local a, b = g.min.X + 0.6, g.max.X - 0.6
	-- 탭에서 먼 쪽의 넓은 구간
	local segs = {}
	if avoid0 < avoid1 then
		table.insert(segs, { a, math.min(b, avoid0) })
		table.insert(segs, { math.max(a, avoid1), b })
	else
		table.insert(segs, { a, b })
	end
	table.sort(segs, function(p, q)
		return (p[2] - p[1]) > (q[2] - q[1])
	end)
	local s = segs[1]
	local len = math.min(7.5, s[2] - s[1])
	if len < 2.5 then
		return
	end
	local cx = (s[1] + s[2]) / 2
	-- 손님 쪽 = +Z (입구) 가정: 통은 뒤쪽 (min.Z 쪽) 0.95 폭
	local dd = 0.95
	local cz = g.min.Z + 0.12 + dd / 2
	local y = g.y
	K:free(function()
		-- 바에 묻힌 스테인리스 통 (테두리만 0.3 위로): 국물 · 꼬치가 보이게
		local base = CF(cx, y - 0.4, cz)
		eomukTank(ctx, base, len, dd, 0.7)
		local lw = 0.1
		for _, sz in { -1, 1 } do
			K:box("FfTroughLip", V3(len + 0.2, 0.04, lw), CF(cx, y + 0.32, cz + sz * (dd / 2 + 0.05)), L.chrome)
			K:box("FfTroughLip", V3(lw, 0.04, dd + 0.2), CF(cx + sz * (len / 2 + 0.05), y + 0.32, cz), L.chrome)
		end
	end)
end

-- 벤치 (Seat 3 + Base + Backrest + Arm + Plinth): 같은 자리 덮개 (가죽 쿠션 + 원목 프레임)
local function benchOverlay(ctx: any)
	local K, V = ctx.K, ctx.V
	local seats = {}
	for _, r in V.byName.Seat or {} do
		if r.part:IsA("Seat") or true then
			table.insert(seats, r)
		end
	end
	if #seats == 0 then
		return
	end
	K:free(function()
		for _, nm in { "Plinth", "Base", "Backrest", "Arm" } do
			for _, r in V.byName[nm] or {} do
				local look = if nm == "Plinth" then L.black elseif nm == "Base" then L.of(120, 80, 50, M.Wood) elseif nm == "Arm" then L.of(110, 74, 46, M.Wood) else L.of(120, 40, 30, M.Leather)
				if nm == "Backrest" then
					K:rbox("FfBenchBack", r.size, 0.1, CF(r.c) * ANG(0, PI / 2, 0), look)
					local n = math.max(2, math.floor(math.max(r.size.X, r.size.Z) / 1.2))
					local alongZ = r.size.Z > r.size.X
					for i = 1, n - 1 do
						local off = -math.max(r.size.X, r.size.Z) / 2 + i * math.max(r.size.X, r.size.Z) / n
						K:box("FfBenchTuft", if alongZ then V3(r.size.X + 0.02, r.size.Y - 0.4, 0.04) else V3(0.04, r.size.Y - 0.4, r.size.Z + 0.02), CF(r.c) * (if alongZ then CF(0, 0, off) else CF(off, 0, 0)), L.of(90, 30, 24, M.Leather))
					end
				else
					K:box("FfBench" .. nm, r.size, CF(r.c), look)
				end
				Scan.hide(K.hidden, r.part)
			end
		end
		for _, r in seats do
			K:rbox("FfBenchCushion", r.size, 0.12, CF(r.c) * ANG(0, PI / 2, 0), L.of(150, 46, 36, M.Leather))
			Scan.hide(K.hidden, r.part)
		end
	end)
end

local function odengBuild(ctx: any)
	local K, V, S = ctx.K, ctx.V, ctx.S
	local P = ctx.pal
	-- 일반 의자 (Seat 가 아닌 ChairSeat 등)는 직접: 벤치형 Seat 는 benchOverlay
	local hasBench = V:has("Backrest") > 0
	if not hasBench then
		Common.chairs(K, V, { chair = { style = "bentwood", frame = L.walnut, seat = L.walnut } })
	else
		benchOverlay(ctx)
		-- 벤치 Seat 가 아닌 의자만
		local chairs = {}
		for _, ch in V.chairs do
			if ch.seat.name ~= "Seat" then
				table.insert(chairs, ch)
			end
		end
		if #chairs > 0 then
			local Vc = setmetatable({ chairs = chairs }, { __index = V })
			Common.chairs(K, Vc, { chair = { style = "bentwood", frame = L.walnut, seat = L.walnut } })
		end
	end
	upperPaint(ctx, { "back" }, 0.45, pl(rgb(60, 40, 30), M.Wood))
	wallBand(ctx, { "left", "right" }, V.H - 0.6, 0.3, 0.1, L.darkWood)
	odengTrough(ctx)
	-- 카운터 위 천장: 빨간 제등 줄 (카운터 길이 따라)
	local g = V.counters[1]
	if g then
		local n = math.clamp(math.floor((g.max.X - g.min.X) / 3.2), 2, 6)
		local texts = { "오\n뎅", "사\n케", "어\n묵", "酒", "오\n뎅", "사\n케" }
		for i = 1, n do
			local x = g.min.X + (g.max.X - g.min.X) * (i - 0.5) / n
			local z = (g.min.Z + g.max.Z) / 2
			if Common.ceilFree(K, x, z, 0.5) then
				local body = lantern(ctx, V3(x, V.H, z), math.clamp(V.H - 7.4, 1.6, 2.8), texts[i], if i % 2 == 0 then rgb(236, 220, 190) else nil)
				if i <= 2 then
					K:light(body, "PointLight", { Range = 10, Brightness = 0.7, Color = rgb(255, 170, 110) })
				end
				Common.useCeil(K, x, z)
			end
		end
	end
	-- 테이블 · 벤치 위 한지 드럼 펜던트 (따뜻한 불빛)
	tablePendants(ctx, { shade = "drum", look = L.of(240, 226, 196, M.Fabric), glow = L.neon(rgb(255, 200, 140)), lights = 2, dia = 1.2 })
	-- 뒷벽 · 옆벽: 나무 메뉴 패
	local items = {
		{ "모둠\n어묵탕", "18,000" },
		{ "어묵\n꼬치", "2,000" },
		{ "곤약\n무", "2,500" },
		{ "계란\n말이", "15,000" },
		{ "타코\n와사비", "13,000" },
		{ "정종\n대포", "9,000" },
		{ "사케\n1병", "32,000" },
		{ "하이\n볼", "8,000" },
	}
	local wp = wallSpot(ctx, { "back", "left", "right" }, #items * 0.72 + 0.6, 5.8, 8.4, 0)
	if wp then
		woodPlaques(ctx, wp, items)
	end
	local wp2 = wallSpot(ctx, { "left", "right" }, 5 * 0.72 + 0.6, 5.6, 8.2, 0)
	if wp2 then
		woodPlaques(ctx, wp2, { { "생맥주", "5,000" }, { "소주", "5,500" }, { "맥주\n병", "6,000" }, { "어묵\n우동", "8,000" }, { "볶음\n우동", "12,000" } })
	end
	-- 사케 병 (일되병) 줄 + 나무 술통: 벽 선반
	local sh = wallSpot(ctx, { "right", "left", "back" }, 4.2, 6.6, 8.2, -2)
	if sh then
		local at = Props.shelf(K, sh * CF(0, -0.7, 0), 4.0, { depth = 0.9, look = L.darkWood })
		for i = 0, 5 do
			local x = -1.6 + i * 0.55
			local c = if i % 2 == 0 then rgb(40, 80, 50) else rgb(90, 50, 30)
			K:vcyl("FfSakeBottle", 0.9, 0.32, at * CF(x, 0.45, -0.1), { c = c, m = M.Glass, t = 0.15 })
			K:vcyl("FfSakeNeck", 0.35, 0.14, at * CF(x, 1.07, -0.1), { c = c, m = M.Glass, t = 0.15 })
			K:vcyl("FfSakeLabel", 0.4, 0.33, at * CF(x, 0.45, -0.1), L.of(246, 240, 226))
		end
	end
	local barrelSpot = floorSpot(ctx, { walls = { "left", "right", "back" }, w = 1.6, h = 2.4, d = 1.6, pref = { left = "front", right = "front" }, front = 0.6 })
	if barrelSpot then
		local b = barrelSpot
		K:vcyl("FfBarrel", 2.0, 1.5, b * CF(0, 1.0, 0), L.of(150, 106, 66, M.Wood))
		for _, y in { 0.3, 1.0, 1.7 } do
			K:vcyl("FfBarrelHoop", 0.1, 1.54, b * CF(0, y, 0), L.blackMetal)
		end
		K:disc("FfBarrelTop", 1.4, 0.06, b * CF(0, 2.02, 0), L.of(170, 126, 80, M.Wood))
		K:plate("FfBarrelLabel", 0.8, 0.9, 0.02, b * CF(0, 1.0, 0.75), L.of(246, 240, 226))
		K:text("FfBarrelText", 0.7, 0.8, b * CF(0, 1.0, 0.775), "大\n吟醸", { fg = rgb(30, 20, 14), font = F.GothamBlack, d = 0.004 })
	end
	-- 사케 · 소주 냉장고 + 네온 (손님이 닿는 자리에 상호작용)
	placeFridge(ctx, { walls = { "left", "right", "back" }, pref = { left = "back", right = "back" }, header = "사케 · 소주 · 맥주", headerBg = rgb(40, 30, 26), headerFg = P.gold, items = {
		{ rgb(40, 80, 50), "bottle", rgb(246, 240, 226) },
		{ rgb(90, 50, 30), "bottle", rgb(246, 240, 226) },
		{ rgb(36, 110, 50), "soju", rgb(240, 250, 240) },
		{ rgb(60, 120, 40), "bottle", rgb(30, 110, 40) },
		{ rgb(30, 70, 170), "can" },
		{ rgb(236, 230, 214), "bottle", rgb(180, 30, 24) },
	}, brand = "SAKE", object = "사케 냉장고" })
	local nd = promptWallSpot(ctx, { "left", "right", "back" }, 3.4, 6.4, 7.8)
	if not nd then
		nd = wallSpot(ctx, { "left", "right", "back" }, 3.4, 6.4, 7.8, 0)
	end
	if nd then
		neonSign(ctx, nd, 3.0, 1.0, "오뎅 · 사케", rgb(255, 150, 90), { object = "네온사인" })
	end
	-- 레트로 소주 포스터 · 안내
	local p1 = wallSpot(ctx, { "left", "right", "back" }, 2.2, 3.9, 6.6, -4)
	if p1 then
		poster(ctx, p1, 2.0, 2.6, {
			bg = rgb(240, 232, 210),
			frame = L.darkWood,
			art = {
				{ "b", 0, -0.1, 0.36, 1.1, rgb(40, 120, 60) },
				{ "b", 0, 0.55, 0.14, 0.3, rgb(40, 120, 60) },
				{ "b", 0, -0.1, 0.38, 0.4, rgb(240, 240, 230) },
			},
			texts = {
				{ "부산 소주 한 잔", 0, 0.98, 1.7, 0.3, rgb(30, 80, 50), F.GothamBlack },
				{ "어묵탕엔 역시", 0, -0.86, 1.6, 0.26, rgb(60, 40, 30), F.GothamBold },
			},
		})
	end
	if V:has("TVScreen") > 0 then
		for _, r in V.byName.TVScreen do
			-- 맵 TV 화면 위에 같은 크기로 채널 화면 (자동 순환)
			local d = CFrame.fromMatrix(V3(r.c.X, r.c.Y, r.max.Z), Vector3.xAxis, Vector3.yAxis, Vector3.zAxis)
			K:free(function()
				local scr, lab = K:text("FfOdengTV", r.size.X - 0.04, r.size.Y - 0.04, d * CF(0, 0, 0.005), "롯데 3 : 2 두산\n7회말 1사 2루", { fg = WHITE, bg = rgb(30, 100, 46), glow = 1.3, font = F.GothamBold, d = 0.01 })
				local frames = {
					{ c = rgb(30, 100, 46), text = "롯데 3 : 2 두산\n7회말 1사 2루" },
					{ c = rgb(20, 46, 110), text = "부산 뉴스\n광안리 불꽃축제 11월 8일" },
					{ c = rgb(60, 26, 22), text = "심야 식당 (재방송)\n오늘의 안주 : 모둠 어묵" },
				}
				local last = 0
				Interact.anim(K, function(t)
					local i = math.floor(t / 8) % #frames + 1
					if i ~= last then
						last = i
						lab.Text = frames[i].text
						lab.BackgroundColor3 = frames[i].c
					end
				end)
			end)
		end
	end
	infoSet(ctx, {
		origin = { "어묵(연육) : 수입산", "무 : 국내산", "계란 : 국내산", "쌀(사케 제외) : 국내산" },
		hours = "영업시간\n17:00 - 03:00",
		ssid = "ODENG_BAR",
		pw = "oden0000",
		stickers = {
			{ "19세 미만\n주류 판매 금지", rgb(200, 30, 36) },
			{ "카드 · 페이\n결제 가능", rgb(40, 90, 200) },
		},
	})
end

-- build ----------------------------------------------------------------------------------------------
-- 맵 소품 재진열 ----------------------------------------------------------------------------------
-- 맵의 단순 원통 병 · 네온 뒤판 · 상자 · 통을 같은 자리 · 같은 범위 안의 진짜 같은 상품으로 (원본 숨김, 장식 파트만).
-- FridgeDoor (게임플레이 냉장고 문) 는 그대로 두고 안쪽만 바꿈.
local DRINK: { [string]: any } = {
	cola = { kind = "can", c = rgb(196, 14, 28), band = WHITE },
	cider = { kind = "can", c = rgb(24, 140, 72), band = WHITE },
	pepsi = { kind = "can", c = rgb(18, 58, 160), band = rgb(222, 30, 40) },
	milkis = { kind = "can", c = rgb(236, 240, 246), band = rgb(40, 110, 200) },
	grape = { kind = "can", c = rgb(104, 40, 120), band = rgb(240, 200, 60) },
	hite = { kind = "can", c = rgb(30, 70, 160), band = rgb(236, 236, 236) },
	soju = { kind = "soju", c = rgb(64, 150, 84), label = WHITE, band = rgb(30, 80, 170), cap = rgb(40, 110, 60) },
	soju2 = { kind = "soju", c = rgb(64, 150, 84), label = rgb(238, 246, 238), band = rgb(30, 130, 70), cap = rgb(40, 110, 60) },
	beer = { kind = "beer", c = rgb(96, 54, 22), label = rgb(30, 70, 160), band = WHITE, cap = rgb(196, 196, 196) },
	beer2 = { kind = "beer", c = rgb(44, 100, 52), label = rgb(20, 84, 40), band = rgb(230, 200, 120), cap = rgb(196, 196, 196) },
	petCola = { kind = "pet", c = rgb(56, 24, 14), label = rgb(196, 14, 28), cap = rgb(196, 14, 28) },
	petCider = { kind = "pet", c = rgb(200, 232, 204), label = rgb(24, 140, 72), cap = rgb(24, 140, 72) },
	water = { kind = "pet", c = rgb(220, 236, 246), label = rgb(40, 120, 210), cap = rgb(40, 120, 210), slim = true },
	coolpis = { kind = "carton", c = rgb(250, 164, 176), label = rgb(255, 222, 96) },
	coolpis2 = { kind = "carton", c = rgb(252, 226, 116), label = rgb(240, 120, 40) },
	sake = { kind = "sake", c = rgb(92, 60, 24), label = rgb(246, 242, 230), band = rgb(190, 30, 30), cap = rgb(200, 170, 90) },
	sake2 = { kind = "sake", c = rgb(40, 76, 50), label = rgb(246, 242, 230), band = rgb(20, 20, 20), cap = rgb(30, 30, 30) },
	cheongju = { kind = "sake", c = rgb(226, 232, 230), label = rgb(196, 30, 36), band = rgb(240, 210, 120), cap = rgb(196, 30, 36), clear = true },
	whisky = { kind = "square", c = rgb(176, 96, 30), label = rgb(240, 232, 210), band = rgb(30, 30, 30), cap = rgb(30, 30, 30) },
	maehwa = { kind = "soju", c = rgb(170, 214, 190), label = rgb(250, 240, 246), band = rgb(220, 90, 140), cap = rgb(230, 230, 230) },
}

-- 음료 하나: base = 바닥 가운데 (+Z = 정면), maxH = 높이 한도. 반환 = 실제 높이
local function drink(K: any, base: CFrame, def: any, maxH: number, detail: boolean): number
	local kind = def.kind
	local function glassL(c: Color3, clear: boolean?): any
		return { c = c, m = M.Glass, t = if clear then 0.45 else 0.18, r = 0.1 }
	end
	if kind == "can" then
		local h, d = math.min(0.42, maxH), 0.22
		K:vcyl("FfCan", h, d, base * CF(0, h / 2, 0), { c = def.c, m = M.Metal, r = 0.15 })
		if detail then
			K:vcyl("FfCanTop", 0.03, d * 0.84, base * CF(0, h + 0.015, 0), L.alu)
			K:vcyl("FfCanBand", h * 0.22, d + 0.008, base * CF(0, h * 0.55, 0), pl(def.band))
		end
		return h
	elseif kind == "carton" then
		local h = math.min(0.86, maxH)
		local w = 0.3
		K:box("FfCarton", V3(w, h * 0.86, w), base * CF(0, h * 0.43, 0), pl(def.c))
		K:wedge("FfCartonTop", V3(w, h * 0.12, w / 2), base * CF(0, h * 0.86 + h * 0.06, w / 4), pl(light(def.c, 0.3)))
		K:wedge("FfCartonTop", V3(w, h * 0.12, w / 2), base * CF(0, h * 0.86 + h * 0.06, -w / 4) * ANG(0, PI, 0), pl(light(def.c, 0.3)))
		if detail then
			K:box("FfCartonLabel", V3(w * 0.8, h * 0.3, 0.02), base * CF(0, h * 0.42, w / 2 + 0.01), pl(def.label))
			K:ball("FfCartonFruit", w * 0.36, base * CF(0, h * 0.42, w / 2 + 0.03), pl(if def.label == rgb(255, 222, 96) then rgb(250, 140, 100) else rgb(250, 200, 60)))
		end
		return h
	elseif kind == "square" then
		local h = math.min(1.0, maxH)
		local w = 0.3
		K:box("FfBottle", V3(w, h * 0.62, w * 0.7), base * CF(0, h * 0.31, 0), glassL(def.c))
		K:vcyl("FfBottleNeck", h * 0.22, 0.1, base * CF(0, h * 0.62 + h * 0.11, 0), glassL(def.c))
		K:vcyl("FfBottleCap", h * 0.1, 0.12, base * CF(0, h * 0.89, 0), pl(def.cap, M.Metal))
		K:box("FfBottleLabel", V3(w * 0.84, h * 0.24, 0.02), base * CF(0, h * 0.3, w * 0.35 + 0.01), pl(def.label))
		if detail then
			K:box("FfBottleBand", V3(w * 0.84, h * 0.05, 0.022), base * CF(0, h * 0.44, w * 0.35 + 0.012), pl(def.band))
		end
		return h
	end
	-- 둥근 병: soju (0.78) · beer (0.86) · pet (1.0) · sake (1.15)
	local H = if kind == "soju" then 0.78 elseif kind == "beer" then 0.86 elseif kind == "pet" then (if def.slim then 0.92 else 1.02) else 1.15
	local D = if kind == "soju" then 0.26 elseif kind == "beer" then 0.27 elseif kind == "pet" then (if def.slim then 0.28 else 0.34) else 0.32
	local k = math.min(1, maxH / H)
	H *= k
	local body = H * (if kind == "pet" then 0.7 else 0.6)
	local gl = if kind == "pet" then { c = def.c, m = M.Glass, t = if def.slim then 0.5 else 0.12, r = 0.15 } else glassL(def.c, def.clear)
	K:vcyl("FfBottle", body, D, base * CF(0, body / 2, 0), gl)
	K:ell("FfBottleShoulder", V3(D, H * 0.16, D), base * CF(0, body, 0), gl)
	local neckH = H - body - H * 0.06
	K:vcyl("FfBottleNeck", neckH, D * 0.4, base * CF(0, body + neckH / 2, 0), gl)
	K:vcyl("FfBottleCap", H * 0.06, D * 0.44, base * CF(0, H - H * 0.03, 0), pl(def.cap, if kind == "pet" then M.Plastic else M.Metal))
	K:vcyl("FfBottleLabel", body * (if kind == "sake" then 0.5 else 0.36), D + 0.012, base * CF(0, body * (if kind == "sake" then 0.5 else 0.45), 0), pl(def.label))
	if detail and def.band then
		K:vcyl("FfBottleBand", body * 0.08, D + 0.016, base * CF(0, body * (if kind == "sake" then 0.66 else 0.56), 0), pl(def.band))
	end
	return H
end

-- 축 성분 꺼내기 / 넣기
local function axv(v: Vector3, ax: string): number
	return if ax == "X" then v.X else v.Z
end

-- 맵 냉장고 (FridgeDoor + FridgeGlow + WireShelf + Bottle) 속 다시 채우기
local function restockFridges(ctx: any): number
	local K, V = ctx.K, ctx.V
	local n = 0
	local bottles = V.byName.Bottle or {}
	local used: { [any]: boolean } = {}
	local sk = ctx.sk
	local plans: { { string } }
	if sk == "chicken" or sk == "tongdak" then
		plans = { { "cola", "cider" }, { "soju", "soju2" }, { "beer", "beer2" }, { "petCola", "petCider" } }
	elseif sk == "bunsik" or sk == "odeng" then
		plans = { { "cola", "cider", "milkis" }, { "coolpis", "coolpis2" }, { "petCider", "petCola" }, { "water" } }
	else
		plans = { { "cola", "pepsi", "cider" }, { "milkis", "grape" }, { "petCola", "petCider" }, { "water" } }
	end
	for _, dr in V.byName.FridgeDoor or {} do
		local ax = if dr.size.X < dr.size.Z then "X" else "Z"
		local ox = if ax == "X" then "Z" else "X"
		local doorA = axv(dr.c, ax)
		local half = axv(dr.size, ox) / 2
		-- 깊이 방향 = 문 -> 뒤판(FridgeGlow)
		local dir = 0
		local glowRec: any = nil
		for _, g in V.byName.FridgeGlow or {} do
			if math.abs(axv(g.c, ox) - axv(dr.c, ox)) < half and math.abs(axv(g.c, ax) - doorA) < 5 then
				dir = if axv(g.c, ax) > doorA then 1 else -1
				glowRec = g
			end
		end
		if dir == 0 then
			continue
		end
		local depthLimit = if glowRec then math.abs(axv(glowRec.c, ax) - doorA) - axv(glowRec.size, ax) / 2 else 3
		-- 선반별로 병 모으기
		local shelves: { [number]: { any } } = {}
		local ys = {}
		for _, b in bottles do
			if used[b] then
				continue
			end
			local da = (axv(b.c, ax) - doorA) * dir
			if da > 0 and da < depthLimit and math.abs(axv(b.c, ox) - axv(dr.c, ox)) < half then
				local yk = math.floor(b.min.Y * 2 + 0.5)
				if not shelves[yk] then
					shelves[yk] = {}
					table.insert(ys, yk)
				end
				table.insert(shelves[yk], b)
				used[b] = true
			end
		end
		table.sort(ys, function(a, b)
			return a > b
		end)
		-- 정면 (+Z) = 문 쪽: 회전
		local face = if ax == "X" then (if dir > 0 then ANG(0, -PI / 2, 0) else ANG(0, PI / 2, 0)) else (if dir > 0 then CFrame.identity else ANG(0, PI, 0))
		local rowsN = if ctx.low then 1 else 2
		K:free(function()
			for si, yk in ys do
				local plan = plans[math.min(si, #plans)]
				local list = shelves[yk]
				table.sort(list, function(a, b)
					return axv(a.c, ox) < axv(b.c, ox)
				end)
				local gap = 1.5
				for _, other in ys do
					if other < yk then
						gap = math.min(gap, (yk - other) / 2)
					end
				end
				for bi, b in list do
					local def = DRINK[plan[(bi - 1) % #plan + 1]]
					local maxH = math.max(0.5, gap - 0.16)
					local da0 = (axv(b.c, ax) - doorA) * dir
					for r = 0, rowsN - 1 do
						local da = da0 + r * 0.44
						if da + 0.2 > depthLimit then
							break
						end
						local pa = doorA + da * dir
						local p = if ax == "X" then V3(pa, b.min.Y, b.c.Z) else V3(b.c.X, b.min.Y, pa)
						local base = CF(p) * face
						if def.kind == "can" then
							for s = -1, 1, 2 do
								drink(K, base * CF(s * 0.135, 0, 0), def, maxH, r == 0 and not ctx.low)
							end
						else
							drink(K, base, def, maxH, r == 0 and not ctx.low)
						end
					end
					-- 가격표 (선반 앞)
					if not ctx.low and bi % 2 == 1 then
						local pp = if ax == "X" then V3(doorA + 0.3 * dir, b.min.Y + 0.06, b.c.Z) else V3(b.c.X, b.min.Y + 0.06, doorA + 0.3 * dir)
						K:box("FfFridgeTag", V3(0.26, 0.09, 0.02), CF(pp) * face, pl(rgb(255, 230, 60)))
					end
					Scan.hide(K.hidden, b.part)
					n += 1
				end
			end
			-- 뒤판: 눈부신 네온 판 -> 밝은 무광 판 + 양옆 LED
			if glowRec then
				local g = glowRec
				K:box("FfFridgeBackPanel", g.size, CF(g.c), L.of(226, 232, 238, M.SmoothPlastic))
				-- 문 안쪽 위 LED 바 + 아래로 비추는 빛 (안이 어둡지 않게)
				local tp = if ax == "X" then V3(doorA + 0.35 * dir, g.c.Y + g.size.Y / 2 - 0.25, g.c.Z) else V3(g.c.X, g.c.Y + g.size.Y / 2 - 0.25, doorA + 0.35 * dir)
				local bar = K:box("FfFridgeLEDTop", if ax == "X" then V3(0.06, 0.05, axv(g.size, ox) - 0.3) else V3(axv(g.size, ox) - 0.3, 0.05, 0.06), CF(tp), neon(rgb(236, 246, 255)))
				K:light(bar, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 7, Brightness = 0.9, Angle = 150, Color = L.coolLight })
				local w = axv(g.size, ox)
				for s = -1, 1, 2 do
					local o = s * (w / 2 - 0.06)
					local front = -dir * (axv(g.size, ax) / 2 + 0.02)
					local p = if ax == "X" then V3(g.c.X + front, g.c.Y, g.c.Z + o) else V3(g.c.X + o, g.c.Y, g.c.Z + front)
					K:box("FfFridgeLED", if ax == "X" then V3(0.04, g.size.Y - 0.2, 0.06) else V3(0.06, g.size.Y - 0.2, 0.04), CF(p), neon(rgb(236, 246, 255)))
				end
				Scan.hide(K.hidden, g.part)
			end
		end)
	end
	return n
end

-- 바 뒤 선반 병 (맵 Bottle 이 냉장고 밖에 있는 것): 같은 자리 · 같은 높이 안에서 진짜 술병으로
local function restockBarBottles(ctx: any): number
	local K, V = ctx.K, ctx.V
	local n = 0
	local set: { string }
	if ctx.sk == "odeng" then
		set = { "sake", "soju", "cheongju", "soju2", "sake2", "maehwa", "whisky", "soju", "beer" }
	elseif ctx.sk == "chicken" or ctx.sk == "tongdak" then
		set = { "soju", "beer", "soju2", "beer2", "maehwa" }
	else
		set = { "soju", "cola", "cider" }
	end
	local i = 0
	K:free(function()
		for _, b in V.byName.Bottle or {} do
			if not b.part or K.hidden[b.part] then
				continue
			end
			i += 1
			-- 이웃한 두 병씩 같은 술 (가로 1.25 칸 + 선반 높이로 묶음)
			local grp = math.floor((b.c.X + b.c.Z) / 1.25) + math.floor(b.min.Y * 2) * 3
			local def = DRINK[set[grp % #set + 1]]
			if def.kind == "can" then
				def = DRINK.soju
			end
			-- 정면 = 방 가운데 쪽 (뒷벽 선반이면 +Z)
			local toC = V3(-b.c.X, 0, -b.c.Z)
			local face = if math.abs(toC.Z) > math.abs(toC.X) then (if toC.Z > 0 then CFrame.identity else ANG(0, PI, 0)) else (if toC.X > 0 then ANG(0, PI / 2, 0) else ANG(0, -PI / 2, 0))
			drink(K, CF(b.c.X, b.min.Y, b.c.Z) * face, def, b.size.Y + 0.12, not ctx.low)
			Scan.hide(K.hidden, b.part)
			n += 1
		end
	end)
	return n
end

-- 공급품 통 · 라면 상자 · 포장 상자 · 치킨무 통 · 물티슈 · 국물통 · 정수기 (같은 범위 덮개)
local function restockSupplies(ctx: any)
	local K, V = ctx.K, ctx.V
	local nm = V.name or ""
	K:free(function()
		-- 주방 선반 통 (원통 0.9): 고추장 통 · 물엿 · 육수 냄비 · 일회용 용기
		local si = 0
		for _, r in V.byName.SupplyTub or {} do
			si += 1
			local s = r.size
			local base = CF(r.c.X, r.min.Y, r.c.Z)
			local d = math.min(s.X, s.Z)
			local kind = si % 4
			if kind == 1 then
				-- 태양초 고추장 통 (빨강 통 + 뚜껑 + 라벨)
				K:vcyl("FfGochujang", s.Y * 0.84, d * 0.94, base * CF(0, s.Y * 0.42, 0), pl(rgb(190, 30, 26), M.Plastic))
				K:vcyl("FfGochujangLid", s.Y * 0.14, d, base * CF(0, s.Y * 0.91, 0), pl(rgb(200, 36, 30), M.Plastic))
				K:vcyl("FfGochujangLabel", s.Y * 0.36, d * 0.94 + 0.012, base * CF(0, s.Y * 0.42, 0), pl(rgb(250, 214, 60)))
			elseif kind == 2 then
				-- 물엿 · 올리고당 통 (반투명 호박색 + 손잡이)
				K:box("FfSyrup", V3(d * 0.8, s.Y * 0.8, d * 0.6), base * CF(0, s.Y * 0.4, 0), { c = rgb(224, 160, 60), m = M.Glass, t = 0.25, r = 0.1 })
				K:vcyl("FfSyrupCap", s.Y * 0.12, d * 0.3, base * CF(-d * 0.18, s.Y * 0.86, 0), pl(rgb(230, 230, 230), M.Plastic))
				K:box("FfSyrupHandle", V3(d * 0.12, s.Y * 0.4, d * 0.24), base * CF(d * 0.3, s.Y * 0.72, 0), { c = rgb(224, 160, 60), m = M.Glass, t = 0.25 })
				K:box("FfSyrupLabel", V3(d * 0.6, s.Y * 0.3, 0.02), base * CF(0, s.Y * 0.4, d * 0.3 + 0.01), pl(rgb(246, 240, 226)))
			elseif kind == 3 then
				-- 스테인리스 육수 냄비 (손잡이 + 뚜껑)
				K:vcyl("FfStockPot", s.Y * 0.7, d * 0.92, base * CF(0, s.Y * 0.35, 0), L.of(200, 204, 208, M.Metal, { r = 0.15 }))
				K:vcyl("FfStockLid", 0.05, d * 0.94, base * CF(0, s.Y * 0.72, 0), L.of(186, 190, 194, M.Metal))
				K:vcyl("FfStockKnob", 0.08, 0.16, base * CF(0, s.Y * 0.78, 0), L.black)
				for k = -1, 1, 2 do
					K:box("FfStockHandle", V3(0.1, 0.06, 0.2), base * CF(k * (d * 0.46 + 0.04), s.Y * 0.6, 0), L.of(186, 190, 194, M.Metal))
				end
			else
				-- 일회용 포장 용기 묶음 (흰 그릇 탑 + 비닐)
				local nb = math.max(4, math.floor(s.Y / 0.14))
				for k = 1, nb do
					K:vcyl("FfTakeoutBowl", 0.1, d * (0.8 + 0.08 * (k % 2)), base * CF(0, (k - 0.5) * (s.Y * 0.9 / nb), 0), pl(rgb(246, 246, 242), M.Plastic))
				end
				K:vcyl("FfTakeoutWrap", s.Y * 0.9, d * 0.92, base * CF(0, s.Y * 0.45, 0), { c = rgb(236, 240, 244), m = M.Glass, t = 0.7 })
			end
			Scan.hide(K.hidden, r.part)
		end
		-- 라면 상자 (빨강 · 검정 띠 · 辛)
		for _, r in V.byName.RamenPack or {} do
			local s = r.size
			local c = CF(r.c)
			local toC = V3(-r.c.X, 0, -r.c.Z)
			local face = if math.abs(toC.Z) > math.abs(toC.X) then (if toC.Z > 0 then CFrame.identity else ANG(0, PI, 0)) else (if toC.X > 0 then ANG(0, PI / 2, 0) else ANG(0, -PI / 2, 0))
			local fs = if math.abs(toC.Z) > math.abs(toC.X) then V3(s.X, s.Y, s.Z) else V3(s.Z, s.Y, s.X)
			local fc = c * face
			K:box("FfRamenBox", fs - V3(0.02, 0.02, 0.02), fc, L.of(214, 30, 26, M.Cardboard))
			K:box("FfRamenBand", V3(fs.X - 0.01, fs.Y * 0.2, fs.Z - 0.01), fc * CF(0, fs.Y * 0.3, 0), L.of(24, 20, 20, M.Cardboard))
			K:text("FfRamenText", fs.X * 0.8, fs.Y * 0.44, fc * CF(0, -fs.Y * 0.12, fs.Z / 2), "얼큰라면\n5개입", { fg = WHITE, font = F.GothamBlack, d = 0.005 })
			Scan.hide(K.hidden, r.part)
		end
		-- 치킨 포장 상자 더미 (흰 상자 + 빨강 띠 + 뚜껑 상호)
		for _, r in V.byName.BoxStack or {} do
			local s = r.size
			local c = CF(r.c)
			K:box("FfChickenBox", s - V3(0.04, 0.02, 0.04), c, L.of(246, 242, 232, M.Cardboard))
			K:box("FfChickenBoxBand", V3(s.X - 0.02, s.Y * 0.36, s.Z - 0.02), c * CF(0, -s.Y * 0.12, 0), L.of(196, 30, 34, M.Cardboard))
			K:box("FfChickenBoxVent", V3(s.X * 0.5, 0.02, 0.1), c * CF(0, s.Y / 2 - 0.005, s.Z * 0.3), L.of(120, 20, 24))
			K:text("FfChickenBoxLid", s.X * 0.8, s.Z * 0.42, c * CF(0, s.Y / 2 - 0.01, -s.Z * 0.05) * ANG(-PI / 2, 0, 0), (if has(nm, "치킨") then nm else "치킨") .. "\n바삭하게 튀겼닭!", { fg = rgb(196, 30, 34), font = F.GothamBlack, d = 0.004 })
			-- 옆면 상호 (방 쪽)
			local toC = V3(-r.c.X, 0, -r.c.Z)
			local face = if math.abs(toC.Z) > math.abs(toC.X) then (if toC.Z > 0 then CFrame.identity else ANG(0, PI, 0)) else (if toC.X > 0 then ANG(0, PI / 2, 0) else ANG(0, -PI / 2, 0))
			local half = if math.abs(toC.Z) > math.abs(toC.X) then s.Z / 2 else s.X / 2
			K:text("FfChickenBoxSide", math.min(s.X, s.Z) * 0.7, s.Y * 0.3, c * face * CF(0, -s.Y * 0.12, half - 0.005), if has(nm, "치킨") then nm else "CHICKEN", { fg = WHITE, font = F.GothamBlack, d = 0.004 })
			Scan.hide(K.hidden, r.part)
		end
		-- 치킨무 통 (흰 원통 + 반투명 뚜껑 + 라벨)
		for _, r in V.byName.RadishTub or {} do
			local s = r.size
			local base = CF(r.c.X, r.min.Y, r.c.Z)
			local d = math.min(s.X, s.Z)
			K:vcyl("FfRadishTub", s.Y * 0.82, d * 0.96, base * CF(0, s.Y * 0.41, 0), pl(rgb(246, 246, 242), M.Plastic))
			K:vcyl("FfRadishCubes", 0.04, d * 0.86, base * CF(0, s.Y * 0.8, 0), pl(rgb(250, 248, 220)))
			K:vcyl("FfRadishLid", s.Y * 0.12, d, base * CF(0, s.Y * 0.88, 0), { c = rgb(236, 240, 236), m = M.Glass, t = 0.4 })
			K:vcyl("FfRadishLabel", s.Y * 0.26, d * 0.96 + 0.012, base * CF(0, s.Y * 0.4, 0), pl(rgb(60, 160, 90)))
			Scan.hide(K.hidden, r.part)
		end
		-- 물티슈 상자 (흰 상자 + 파랑 띠 + 뽑는 구멍)
		for _, r in V.byName.WetWipeBox or {} do
			local s = r.size
			local c = CF(r.c)
			K:box("FfWipeBox", s - V3(0.02, 0.02, 0.02), c, pl(rgb(250, 250, 250)))
			K:box("FfWipeBand", V3(s.X - 0.01, s.Y * 0.36, s.Z - 0.01), c * CF(0, -s.Y * 0.1, 0), pl(rgb(60, 140, 220)))
			K:box("FfWipeSlot", V3(s.X * 0.5, 0.02, 0.08), c * CF(0, s.Y / 2 - 0.005, 0), pl(rgb(40, 90, 160)))
			K:ell("FfWipeSheet", V3(0.2, 0.12, 0.12), c * CF(0, s.Y / 2 + 0.04, 0), pl(rgb(252, 252, 252)))
			Scan.hide(K.hidden, r.part)
		end
		-- 정수기 (흰 몸체 · 검정 유리 조작부 · 크롬 코크 · 물받이)
		for _, r in V.byName.Purifier or {} do
			local s = r.size
			local pnl: any = nil
			for _, q in V.byName.PurifierPanel or {} do
				if (q.c - r.c).Magnitude < 2 then
					pnl = q
				end
			end
			if not pnl then
				continue
			end
			local dv = pnl.c - r.c
			local face = if math.abs(dv.Z) > math.abs(dv.X) then (if dv.Z > 0 then CFrame.identity else ANG(0, PI, 0)) else (if dv.X > 0 then ANG(0, PI / 2, 0) else ANG(0, -PI / 2, 0))
			local fs = if math.abs(dv.Z) > math.abs(dv.X) then s else V3(s.Z, s.Y, s.X)
			local c = CF(r.c) * face
			local white = L.of(246, 246, 244, M.SmoothPlastic, { r = 0.1 })
			K:box("FfPurifierBody", fs - V3(0.06, 0, 0.06), c, white)
			for _, sx in { -1, 1 } do
				K:vcyl("FfPurifierEdge", fs.Y, 0.12, c * CF(sx * (fs.X / 2 - 0.06), 0, fs.Z / 2 - 0.06), white)
			end
			K:box("FfPurifierTop", V3(fs.X - 0.1, 0.06, fs.Z - 0.1), c * CF(0, fs.Y / 2 - 0.03, 0), L.of(220, 222, 224))
			K:box("FfPurifierFace", V3(fs.X * 0.62, fs.Y * 0.3, 0.03), c * CF(0, fs.Y * 0.2, fs.Z / 2), L.of(20, 22, 26, M.Glass, { r = 0.2 }))
			K:box("FfPurifierLed", V3(0.12, 0.05, 0.01), c * CF(-fs.X * 0.16, fs.Y * 0.26, fs.Z / 2 + 0.02), neon(rgb(255, 70, 50)))
			K:box("FfPurifierLed", V3(0.12, 0.05, 0.01), c * CF(0, fs.Y * 0.26, fs.Z / 2 + 0.02), neon(rgb(70, 170, 255)))
			K:box("FfPurifierLed", V3(0.12, 0.05, 0.01), c * CF(fs.X * 0.16, fs.Y * 0.26, fs.Z / 2 + 0.02), neon(rgb(230, 240, 255)))
			K:text("FfPurifierLabel", fs.X * 0.58, 0.14, c * CF(0, fs.Y * 0.12, fs.Z / 2 + 0.02), "온수 · 냉수 · 정수", { fg = rgb(220, 224, 230), font = F.GothamMedium, d = 0.003 })
			K:box("FfPurifierRecess", V3(fs.X * 0.5, fs.Y * 0.3, 0.04), c * CF(0, -fs.Y * 0.16, fs.Z / 2 - 0.01), L.of(200, 202, 204))
			K:box("FfPurifierTap", V3(0.1, 0.18, 0.12), c * CF(0, -fs.Y * 0.04, fs.Z / 2 + 0.06), L.chrome)
			K:box("FfPurifierTray", V3(fs.X * 0.46, 0.05, 0.3), c * CF(0, -fs.Y / 2 + 0.03, fs.Z / 2 + 0.1), L.of(150, 154, 160, M.DiamondPlate))
			Scan.hide(K.hidden, r.part)
			Scan.hide(K.hidden, pnl.part)
			for _, q in V.byName.Tap or {} do
				if (q.c - r.c).Magnitude < 2 then
					Scan.hide(K.hidden, q.part)
				end
			end
		end
		-- 국물통 (어묵 국물 셀프): 스테인리스 보온통 + 뚜껑 손잡이 + 라벨
		for _, r in V.byName.BrothUrn or {} do
			local s = r.size
			local base = CF(r.c.X, r.min.Y, r.c.Z)
			local d = math.min(s.X, s.Z)
			K:vcyl("FfUrnBody", s.Y * 0.86, d * 0.96, base * CF(0, s.Y * 0.43, 0), L.of(206, 210, 214, M.Metal, { r = 0.2 }))
			K:vcyl("FfUrnBand", 0.06, d * 0.98, base * CF(0, s.Y * 0.1, 0), L.of(150, 154, 158, M.Metal))
			K:vcyl("FfUrnLid", s.Y * 0.08, d * 0.9, base * CF(0, s.Y * 0.9, 0), L.of(186, 190, 194, M.Metal))
			K:vcyl("FfUrnKnob", s.Y * 0.06, 0.2, base * CF(0, s.Y * 0.97, 0), L.black)
			K:vcyl("FfUrnLabel", s.Y * 0.2, d * 0.96 + 0.012, base * CF(0, s.Y * 0.56, 0), pl(rgb(214, 38, 34)))
			Scan.hide(K.hidden, r.part)
		end
	end)
end

-- 셀프 코너 수납장 (맵 SelfCabinet): 같은 범위 덮개 + 여닫는 두 문 + 안쪽 비품 (냅킨 · 물티슈 · 치킨무 컵 · 비닐봉투)
local function selfCabinetOverlay(ctx: any): number
	local K, V = ctx.K, ctx.V
	local made = 0
	for _, r in V.byName.SelfCabinet or {} do
		local s = r.size
		-- 정면 = 방 가운데 쪽 (가까운 벽의 반대)
		local dx = math.min(math.abs(r.c.X - V.x0), math.abs(r.c.X - V.x1))
		local dz = math.abs(r.c.Z - V.z0)
		local face, fw, fd
		if dx < dz then
			face = if r.c.X > 0 then ANG(0, -PI / 2, 0) else ANG(0, PI / 2, 0)
			fw, fd = s.Z, s.X
		else
			face = CFrame.identity
			fw, fd = s.X, s.Z
		end
		local h = s.Y
		local pcf = CF(r.c.X, r.min.Y, r.c.Z) * face
		local wood = L.of(150, 104, 64, M.Wood)
		local inner = L.of(236, 232, 224, M.SmoothPlastic)
		local doors = {}
		local extra = {}
		K:free(function()
			-- 몸통 (속이 빈 상자): 옆판 · 뒤판 · 바닥 · 천판 밑 · 가운데 칸막이 · 선반
			local t = 0.08
			K:box("FfSelfCabSide", V3(t, h - 0.3, fd), pcf * CF(-fw / 2 + t / 2, 0.3 + (h - 0.3) / 2, 0), wood)
			K:box("FfSelfCabSide", V3(t, h - 0.3, fd), pcf * CF(fw / 2 - t / 2, 0.3 + (h - 0.3) / 2, 0), wood)
			table.insert(extra, K:box("FfSelfCabBack", V3(fw - 2 * t, h - 0.3, t), pcf * CF(0, 0.3 + (h - 0.3) / 2, -fd / 2 + t / 2), inner))
			K:box("FfSelfCabFloor", V3(fw - 2 * t, t, fd - t), pcf * CF(0, 0.3 + t / 2, t / 2), inner)
			K:box("FfSelfCabCeil", V3(fw - 2 * t, t, fd - t), pcf * CF(0, h - t / 2, t / 2), inner)
			K:box("FfSelfCabMid", V3(t, h - 0.3 - 2 * t, fd - t - 0.1), pcf * CF(0, 0.3 + (h - 0.3) / 2, -0.05 + t / 2), inner)
			local shelfY = 0.3 + (h - 0.3) * 0.52
			K:box("FfSelfCabShelf", V3(fw - 2 * t, 0.05, fd - t - 0.12), pcf * CF(0, shelfY, -0.02), inner)
			K:box("FfSelfCabKick", V3(fw - 0.1, 0.3, fd - 0.12), pcf * CF(0, 0.15, -0.06), L.black)
			-- 안쪽 비품
			local hw = fw / 4
			local y1 = 0.3 + t
			-- 아래 왼쪽: 물티슈 상자 묶음
			for i = 0, 2 do
				K:box("FfSpareWipes", V3(hw * 1.4, 0.24, 0.5), pcf * CF(-hw, y1 + 0.12 + i * 0.25, -fd / 2 + 0.4), pl(if i % 2 == 0 then rgb(250, 250, 250) else rgb(120, 190, 240)))
			end
			-- 아래 오른쪽: 비닐봉투 롤 · 냅킨 박스
			K:cyl("FfBagRoll", hw * 1.3, 0.5, pcf * CF(hw, y1 + 0.25, -fd / 2 + 0.45), pl(rgb(240, 240, 236), M.Plastic))
			K:box("FfNapkinCase", V3(hw * 1.4, 0.6, 0.6), pcf * CF(hw, y1 + 0.8, -fd / 2 + 0.45), L.of(196, 156, 110, M.Cardboard))
			-- 위 칸: 치킨무 일회용 컵 탑 · 젓가락 묶음 · 소스 컵
			for i = -1, 1 do
				K:vcyl("FfRadishCupStack", 0.7, 0.3, pcf * CF(-hw + i * 0.34, shelfY + 0.38, -fd / 2 + 0.4), { c = rgb(246, 246, 244), m = M.Glass, t = 0.3 })
			end
			K:box("FfChopstickPack", V3(hw * 1.2, 0.18, 0.4), pcf * CF(hw, shelfY + 0.12, -fd / 2 + 0.4), pl(rgb(232, 210, 160)))
			K:box("FfSauceCups", V3(hw * 1.0, 0.3, 0.4), pcf * CF(hw, shelfY + 0.38, -fd / 2 + 0.4), pl(rgb(250, 250, 250)))
			-- 문 두 짝 (바깥 모서리 경첩)
			for i = 1, 2 do
				local left = i == 1
				local dw = fw / 2 - 0.02
				local cx = if left then -fw / 4 else fw / 4
				local zf = fd / 2 - 0.03
				local m = K:group("FfSelfCabDoor_" .. i, function()
					local c = pcf * CF(cx, 0.3 + (h - 0.3) / 2, zf)
					K:box("FfSelfCabDoorFrame", V3(dw, h - 0.34, 0.06), c, wood)
					K:box("FfSelfCabDoorPanel", V3(dw - 0.3, h - 0.7, 0.02), c * CF(0, 0, 0.035), L.of(170, 122, 78, M.Wood))
					K:box("FfSelfCabDoorHandle", V3(0.06, 0.5, 0.06), c * CF(if left then dw / 2 - 0.16 else -dw / 2 + 0.16, h * 0.18, 0.07), L.blackMetal)
				end)
				local hx = if left then -fw / 2 + 0.02 else fw / 2 - 0.02
				table.insert(doors, { model = m, hinge = (K.cf * pcf * CF(hx, 0, zf)).Position, angle = if left then -1.6 else 1.6 })
			end
			K:text("FfSelfCabLabel", math.min(1.8, fw * 0.5), 0.26, pcf * CF(0, h - 0.32, fd / 2 + 0.06), "셀프 비품 · 냅킨 · 물티슈", { fg = rgb(60, 40, 24), bg = rgb(246, 236, 210), font = F.GothamBold, d = 0.01 })
		end)
		Scan.hide(K.hidden, r.part)
		if swingDoors(ctx, doors, "셀프 수납장", extra) then
			made += 1
		end
	end
	return made
end

-- 남은 빈 벽 채우기: 유형별 액자 포스터 (가로형, 폭 w · 높이 h). 반환 = poster() 옵션
local function posterPool(ctx: any): { (number, number) -> any }
	local sk = ctx.sk
	local sg = ctx.signs or ""
	local G, GB, GM = F.GothamBlack, F.GothamBold, F.GothamMedium
	if sk == "chicken" or sk == "tongdak" then
		local pF = priceIn(sg, "후라이드", "20,000")
		return {
			function(w, h)
				return { bg = rgb(250, 196, 40), frame = L.blackMetal, glass = true, art = artChicken(-w * 0.24, -h * 0.04, w * 0.28), texts = {
					{ "오늘은\n치킨이닭", w * 0.2, h * 0.12, w * 0.5, h * 0.44, rgb(120, 24, 16), G },
					{ "후라이드 " .. pF .. "원", w * 0.2, -h * 0.3, w * 0.52, h * 0.14, rgb(196, 30, 34), GB },
				} }
			end,
			function(w, h)
				return { bg = rgb(16, 30, 74), frame = L.of(196, 30, 40), border = 0.07, art = { { "b", 0, h * 0.42, w - 0.16, h * 0.06, rgb(214, 30, 40) }, { "b", 0, -h * 0.42, w - 0.16, h * 0.06, rgb(214, 30, 40) } }, texts = {
					{ "최강 롯데!", 0, h * 0.16, w * 0.8, h * 0.3, WHITE, G },
					{ "부산 갈매기 · 사직에서 만나요", 0, -h * 0.1, w * 0.84, h * 0.13, rgb(255, 210, 60), GB },
					{ "롯데 경기 있는 날 생맥주 500cc 1+1 (19시~)", 0, -h * 0.28, w * 0.86, h * 0.09, rgb(240, 240, 240), GM },
				} }
			end,
			function(w, h)
				return { bg = rgb(20, 62, 146), frame = L.chrome, glass = true, art = artBeer(-w * 0.26, -h * 0.02, w * 0.3), texts = {
					{ "시원한\n생맥주", w * 0.2, h * 0.12, w * 0.48, h * 0.42, WHITE, G },
					{ "500cc " .. priceIn(sg, "생맥주", "4,500") .. "원", w * 0.2, -h * 0.3, w * 0.5, h * 0.14, rgb(255, 214, 60), G },
				} }
			end,
			function(w, h)
				return { bg = rgb(250, 246, 236), frame = L.walnut, texts = {
					{ "포장 · 배달 주문", 0, h * 0.28, w * 0.8, h * 0.16, rgb(40, 30, 20), G },
					{ "포장하면 콜라 1.25L 서비스", 0, h * 0.04, w * 0.86, h * 0.14, rgb(196, 30, 34), GB },
					{ "☎ 051-752-8282", 0, -h * 0.2, w * 0.7, h * 0.16, rgb(40, 30, 20), G },
					{ "배민 · 쿠팡이츠 · 요기요", 0, -h * 0.38, w * 0.7, h * 0.09, rgb(90, 80, 70), GM },
				} }
			end,
		}
	elseif sk == "sub" then
		return {
			function(w, h)
				return { bg = rgb(0, 120, 56), frame = L.of(255, 194, 14), border = 0.06, art = artSandwich(-w * 0.24, -h * 0.02, w * 0.3), texts = {
					{ "FRESH\nVEGGIES", w * 0.2, h * 0.12, w * 0.5, h * 0.42, WHITE, G },
					{ "매일 아침 손질하는 채소", w * 0.2, -h * 0.3, w * 0.5, h * 0.12, rgb(255, 214, 60), GB },
				} }
			end,
			function(w, h)
				local a = {}
				for i = -1, 1 do
					table.insert(a, { "e", -w * 0.26 + i * w * 0.1, -h * 0.02 + (i % 2) * h * 0.06, w * 0.13, w * 0.13, rgb(170, 112, 60) })
					table.insert(a, { "e", -w * 0.26 + i * w * 0.1 + w * 0.02, h * 0.0 + (i % 2) * h * 0.06, w * 0.03, w * 0.025, rgb(70, 40, 24) })
				end
				return { bg = rgb(250, 236, 200), frame = L.of(0, 110, 52), border = 0.06, art = a, texts = {
					{ "갓 구운 쿠키", w * 0.2, h * 0.14, w * 0.5, h * 0.2, rgb(90, 50, 24), G },
					{ "3개 4,500원", w * 0.2, -h * 0.14, w * 0.5, h * 0.18, rgb(0, 110, 52), G },
				} }
			end,
		}
	elseif sk == "burger" or sk == "taco" then
		if sk == "taco" then
			return {
				function(w, h)
					return { bg = rgb(250, 200, 60), frame = L.of(30, 140, 120), border = 0.07, art = artTaco(-w * 0.24, 0, w * 0.3), texts = {
						{ "TACO\nTUESDAY", w * 0.2, h * 0.12, w * 0.5, h * 0.42, rgb(180, 40, 30), G },
						{ "화요일 타코 2+1", w * 0.2, -h * 0.3, w * 0.5, h * 0.13, rgb(30, 100, 90), GB },
					} }
				end,
			}
		end
		return {
			function(w, h)
				return { bg = rgb(246, 238, 220), frame = L.blackMetal, glass = true, art = artBurger(-w * 0.22, -h * 0.02, w * 0.32), texts = {
					{ "BURGER ANATOMY", w * 0.2, h * 0.32, w * 0.52, h * 0.14, rgb(30, 30, 30), G },
					{ "브리오슈 번\n체다 치즈\n소고기 패티 150g\n양상추 · 토마토", w * 0.2, -h * 0.08, w * 0.5, h * 0.56, rgb(150, 40, 30), GB },
				} }
			end,
			function(w, h)
				return { bg = rgb(250, 190, 200), frame = L.chrome, art = artCola(-w * 0.26, -h * 0.04, w * 0.3), texts = {
					{ "MILK\nSHAKE", w * 0.18, h * 0.12, w * 0.5, h * 0.42, rgb(150, 30, 70), G },
					{ "바닐라 · 딸기 · 초코 5,500원", w * 0.18, -h * 0.3, w * 0.56, h * 0.11, rgb(60, 30, 40), GB },
				} }
			end,
			function(w, h)
				return { bg = rgb(26, 26, 28), frame = L.of(212, 168, 74, M.Metal), border = 0.06, texts = {
					{ "100% BEEF", 0, h * 0.18, w * 0.8, h * 0.28, rgb(236, 190, 90), G },
					{ "매일 아침 직접 다진 패티", 0, -h * 0.1, w * 0.8, h * 0.13, WHITE, GB },
					{ "호주산 소고기 · 냉장 숙성", 0, -h * 0.3, w * 0.7, h * 0.1, rgb(180, 176, 168), GM },
				} }
			end,
			function(w, h)
				return { bg = rgb(220, 36, 40), frame = L.blackMetal, art = artFries(-w * 0.24, -h * 0.02, w * 0.36), texts = {
					{ "FRIES", w * 0.2, h * 0.16, w * 0.5, h * 0.28, rgb(255, 214, 60), G },
					{ "감자튀김 3,500 · 치즈 +1,000", w * 0.2, -h * 0.22, w * 0.54, h * 0.12, WHITE, GB },
				} }
			end,
		}
	elseif sk == "odeng" then
		local wood = L.of(150, 106, 66, M.Wood)
		return {
			function(w, h)
				return { bg = rgb(236, 220, 186), frame = wood, border = 0.1, art = artEomuk(-w * 0.26, 0, w * 0.32), texts = {
					{ "모둠 어묵탕", w * 0.18, h * 0.16, w * 0.52, h * 0.22, rgb(90, 30, 20), G },
					{ "2인 15,000원", w * 0.18, -h * 0.16, w * 0.5, h * 0.18, rgb(180, 30, 26), G },
				} }
			end,
			function(w, h)
				return { bg = rgb(30, 24, 22), frame = wood, border = 0.1, texts = {
					{ "오늘의 사케", 0, h * 0.26, w * 0.7, h * 0.18, rgb(236, 196, 120), G },
					{ "월계관 300ml 18,000\n백화수복 15,000\n하이볼 7,000", 0, -h * 0.12, w * 0.8, h * 0.5, rgb(246, 238, 214), GB },
				} }
			end,
		}
	end
	-- 분식
	return {
		function(w, h)
			return { bg = rgb(250, 244, 230), frame = L.of(214, 38, 34), border = 0.07, art = artGimbap(-w * 0.24, 0, w * 0.3), texts = {
				{ "김밥 한 줄", w * 0.2, h * 0.16, w * 0.5, h * 0.22, rgb(40, 30, 20), G },
				{ priceIn(sg, "김밥", "3,500") .. "원 · 참치 4,500", w * 0.2, -h * 0.16, w * 0.52, h * 0.14, rgb(214, 38, 34), GB },
			} }
		end,
		function(w, h)
			return { bg = rgb(255, 214, 80), frame = L.blackMetal, art = artTwigim(-w * 0.24, 0, w * 0.3), texts = {
				{ "모둠 튀김", w * 0.2, h * 0.16, w * 0.5, h * 0.22, rgb(150, 40, 20), G },
				{ "5개 " .. priceIn(sg, "튀김", "5,000") .. "원", w * 0.2, -h * 0.16, w * 0.5, h * 0.16, rgb(40, 24, 10), G },
			} }
		end,
		function(w, h)
			return { bg = rgb(40, 110, 170), frame = L.chrome, art = artEomuk(-w * 0.24, 0, w * 0.3), texts = {
				{ "부산 어묵", w * 0.2, h * 0.16, w * 0.5, h * 0.22, WHITE, G },
				{ "1꼬치 1,000원 · 국물 셀프", w * 0.2, -h * 0.16, w * 0.54, h * 0.12, rgb(255, 220, 90), GB },
			} }
		end,
		function(w, h)
			return { bg = rgb(250, 238, 214), frame = L.walnut, art = artNoodle(-w * 0.24, 0, w * 0.3, rgb(214, 70, 40), rgb(240, 200, 80)), texts = {
				{ "라볶이", w * 0.2, h * 0.16, w * 0.5, h * 0.22, rgb(190, 40, 30), G },
				{ "6,500원 · 치즈 추가 1,000", w * 0.2, -h * 0.16, w * 0.54, h * 0.12, rgb(60, 40, 24), GB },
			} }
		end,
	}
end

local function fillWalls(ctx: any): number
	local K, V = ctx.K, ctx.V
	if ctx.low or #K.parts > K.maxParts - 200 then
		return 0
	end
	local pool = posterPool(ctx)
	local per = (V.W + V.D) * 2
	local maxN = math.clamp(math.floor(per / 16), 2, 4)
	local n = 0
	local pick = ctx.rand(#pool) - 1
	local missBefore = ctx.miss
	for _, band in { { 5.5, 7.5 }, { 3.9, 5.5 } } do
		for _, wn in { "left", "right", "back" } do
			for _ = 1, 2 do
				if n >= maxN then
					break
				end
				local d, fw = wallSpotFit(ctx, { wn }, { 3.1, 2.5 }, band[1], band[2], 0)
				if not d then
					break
				end
				local w = fw - 0.4
				local h = math.min(band[2] - band[1] - 0.25, w * 0.7)
				pick += 1
				local o = pool[(pick - 1) % #pool + 1](w, h)
				poster(ctx, d, w, h, o)
				n += 1
			end
		end
	end
	ctx.miss = missBefore
	return n
end

-- 넓은 분식집: 홀 위에 줄로 매단 양면 안내판 (천장 조명 · 에어컨 · 맵 매단 것 · 우리 위쪽 파트와 안 겹치게)
local function hangingBoards(ctx: any): number
	local K, V = ctx.K, ctx.V
	if ctx.low or V.W * V.D < 500 or V.H < 9 then
		return 0
	end
	local P = ctx.pal
	local bw, bh = 3.4, 0.95
	local y = V.H - 1.55
	local function clear(x: number, z: number): boolean
		yieldMaybe(K)
		local mn = V3(x - bw / 2 - 0.6, y - bh / 2 - 0.3, z - 0.8)
		local mx = V3(x + bw / 2 + 0.6, V.H + 0.1, z + 0.8)
		for _, r in V.parts do
			if r.name ~= "TBar" and r.name ~= "ShopCeiling" and r.name ~= "Ceiling" and not (r.shell and not r.door) and r.max.Y > mn.Y and ov(r.min, r.max, mn, mx, 0) then
				return false
			end
		end
		for _, p in K.parts do
			if p.Parent and p:IsA("BasePart") then
				local a, b = laabb(K.cf:ToObjectSpace(p.CFrame), p.Size)
				if b.Y > mn.Y - 0.2 and ov(a, b, mn, mx, 0) then
					return false
				end
			end
		end
		return true
	end
	local texts = {
		{ "매운맛 도전!", "1단계 순한맛 ~ 5단계 지옥맛", "포장 · 배달 환영", "전화 주문 051-753-4500" },
		{ "떡튀순 세트 " .. priceIn(ctx.signs or "", "떡튀순", "9,000") .. "원", "떡볶이 + 모둠튀김 + 순대", "카드 · 페이 결제 OK", "현금영수증 발행 가능" },
	}
	local n = 0
	local zs = { { V.z0 + V.D * 0.34, V.z0 + V.D * 0.42, V.z0 + V.D * 0.28 }, { V.z0 + V.D * 0.62, V.z0 + V.D * 0.55, V.z0 + V.D * 0.7 } }
	local xs = { -V.W * 0.18, V.W * 0.18, 0, -V.W * 0.3, V.W * 0.3 }
	for zi, zl in zs do
		for _, z in zl do
			for _, x in xs do
			if n < zi and clear(x, z) then
				n += 1
				local t = texts[n]
				local c = CF(x, y, z)
				K:box("FfHangBoardRim", V3(bw + 0.12, bh + 0.12, 0.06), c, pl(P.gold))
				K:box("FfHangBoard", V3(bw, bh, 0.1), c, pl(P.accent))
				for side = 0, 1 do
					local d = c * ANG(0, side * PI, 0) * CF(0, 0, 0.051)
					K:text("FfHangBoardTitle", bw - 0.2, bh * 0.5, d * CF(0, bh * 0.18, 0), if side == 0 then t[1] else t[3], { fg = WHITE, font = F.GothamBlack, d = 0.004 })
					K:text("FfHangBoardSub", bw - 0.3, bh * 0.28, d * CF(0, -bh * 0.26, 0), if side == 0 then t[2] else t[4], { fg = rgb(255, 230, 120), font = F.GothamBold, d = 0.004 })
				end
				for _, sx in { -1, 1 } do
					local px = x + sx * (bw / 2 - 0.3)
					K:seg("FfHangWire", V3(px, y + bh / 2 + 0.06, z), V3(px, V.H - 0.02, z), 0.025, L.steel)
					K:box("FfHangClip", V3(0.14, 0.06, 0.14), CF(px, V.H - 0.03, z), L.steel)
				end
				break
			end
			end
			if n >= zi then
				break
			end
		end
	end
	return n
end

-- 벽시계: 간판 · 장식을 피한 빈 벽 (높이 7.6 -> 6.4 순), 게임 시각으로 도는 바늘
local function placeClock(ctx: any)
	local K, V = ctx.K, ctx.V
	if V:has("ClockFace") > 0 or V:has("ClockRim") > 0 or V:has("Clock") > 0 then
		return -- 맵에 이미 시계
	end
	local hs = { math.min(V.H - 1.4, 7.6), 6.4 }
	for _, h in hs do
		local missBefore = ctx.miss
		local d = wallSpot(ctx, { "back", "left", "right" }, 1.6, h - 0.8, h + 0.8, 0)
		ctx.miss = missBefore
		if d then
			local hr, mn = Props.clock(K, d, 1.4, nil)
			if hr and mn then
				Interact.clock(K, hr, mn, d, 1.4)
			end
			return
		end
	end
end

function T.build(K: any, V: any, S: any)
	local ctx = ctxNew(K, V, S)
	local ok, err = pcall(setupZones, ctx)
	if not ok then
		K:note("ff zones error: " .. tostring(err))
	end
	local t0 = #K.parts
	-- 벽 아랫단 마감 (타일 · 루버) 뒤 바탕: 콘센트 · 소화기 등으로 끊긴 틈에 맨 벽이 보이지 않게
	if S.lower and not ctx.gw then
		local lw = S.lower
		local base = if lw.kind == "louver" then (lw.back or L.charcoal) else (lw.grout or L.of(150, 148, 144))
		pcall(upperPaint, ctx, lw.walls or { "left", "right" }, 0.42, base, lw.h)
	end
	local fn = if ctx.sk == "chicken" or ctx.sk == "tongdak" then chickenBuild elseif ctx.sk == "sub" then subwayBuild elseif ctx.sk == "burger" or ctx.sk == "taco" then burgerBuild elseif ctx.sk == "odeng" then odengBuild else bunsikBuild
	local ok2, err2 = pcall(fn, ctx)
	if not ok2 then
		K:note("ff build error: " .. tostring(err2))
	end
	-- 맵 소품 재진열 (냉장고 속 · 바 선반 병 · 통 · 상자 · 정수기)
	local ok3, err3 = pcall(function()
		local nf = restockFridges(ctx)
		local nb = restockBarBottles(ctx)
		restockSupplies(ctx)
		selfCabinetOverlay(ctx)
		placeClock(ctx)
		if ctx.sk == "bunsik" then
			local nh = hangingBoards(ctx)
			if nh > 0 then
				K:note("ff hanging boards: " .. nh)
			end
		end
		local nfw = fillWalls(ctx)
		if nfw > 0 then
			K:note("ff fill posters: " .. nfw)
		end
		if nf + nb > 0 then
			K:note(string.format("ff restock: fridge %d, bar %d", nf, nb))
		end
	end)
	if not ok3 then
		K:note("ff restock error: " .. tostring(err3))
	end
	K:note(string.format("ff %s/%s: +%d parts, toggles %d", ctx.sk, ctx.pal.key or "?", #K.parts - t0, ctx.toggles))
	if ctx.miss then
		K:note("ff miss:" .. string.sub(ctx.miss, 1, 200))
	end
end

return T
