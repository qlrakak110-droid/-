--!nocheck
-- GwangalliGameplay/WorkCafe: the CAFE station system (스타벅스 광안리점) of the 알바 simulation.
-- Driven by Work.luau (shift, pay, client state); this module owns the bar:
--
--   POS (주문 받기) · 창고 선반 (보충 박스 / 행주) · 컵 (ICE/HOT, 톨/그란데) · 얼음통 · 에스프레소 머신
--   1~2대 (헤드 2개씩, 예열 / 추출 타이머 / 청소 표시등) · 스팀 피처 1~2개 (라떼 스팀 / 거품, 타이머,
--   오래 두면 탐) · 우유 냉장고 · 정수기 (물 / 뜨거운 물) · 시럽 · 뚜껑 · 작업대 (컵 3개 임시 보관) ·
--   픽업대 (4칸, 주문 번호 연결 → 호출) · 쓰레기통 (8개 차면 비우기) · 바닥에 쏟은 음료 (행주로 닦기)
--
-- Every step changes a real object: the cup in the hand gets ice cubes / liquid / a lid, stock
-- stacks shrink, machine lights change colour, cups sit under the group head while extracting.
-- Stations come from the building when it provides them (parts tagged "GwWorkStation" with the
-- attributes Store = "starbucks", Station = <id> — docs/WORK_SIM.md "건물 연결"); otherwise the
-- equipment is built here from LAYOUT (offsets in the store Destination's frame, measured from the
-- current 스타벅스 광안리점 interior).

local CollectionService = game:GetService("CollectionService")

local Cafe = {}
Cafe.kind = "cafe"

local C: any
local WS: any
local Props: any
local Orders: any
local W: any -- Work (callbacks: credit, toast, hold, release, levelOf, dirty, newItem, destroyItem ...)

function Cafe.init(cfg: any, ws: any, props: any, orders: any, work: any)
	C = cfg
	WS = ws
	Props = props
	Orders = orders
	W = work
end

-------------------------------------------------------------------------------------------------
-- Layout (Destination frame of "스타벅스 광안리점"): front counter local z ≈ 29-31 (customers on the
-- smaller z side), staff lane z ≈ 32.3, back counter z ≈ 35-36. y = the surface the thing sits on.
-------------------------------------------------------------------------------------------------
local LAYOUT = {
	stations = {
		timeclock = { at = { 7.16, -4.2, 30.83 }, face = "side", label = "출퇴근" },
		pos = { at = { 3.35, -1.0, 28.93 }, face = "front", label = "POS" },
		storage = { at = { 5.65, -1.2, 34.51 }, face = "back", label = "창고 선반" },
		work = { at = { -4.44, -1.0, 29.35 }, face = "front", label = "작업대", slots = { { -5.84, -1.0, 29.42 }, { -4.54, -1.0, 29.35 }, { -3.24, -1.0, 29.28 } } },
		cups = { at = { -9.32, -1.2, 35.32 }, face = "back", label = "컵" },
		steam = { at = { -11.23, -1.0, 29.71 }, face = "front", label = "스팀", slots = { { -11.92, -1.0, 29.85 }, { -10.62, -1.0, 29.78 } } },
		ice = { at = { -12.82, -1.2, 35.5 }, face = "back", label = "얼음" },
		machine1 = { at = { -15.61, -1.0, 30.25 }, face = "front", label = "머신 1", body = { -15.64, 0.15, 29.65 }, slots = { { -14.9, -0.7, 30.26 }, { -16.3, -0.7, 30.33 } } },
		milk = { at = { -16.51, -1.2, 35.7 }, face = "back", label = "우유" },
		water = { at = { -19.91, -1.2, 35.89 }, face = "back", label = "정수기" },
		syrup = { at = { -22.9, -1.2, 36.05 }, face = "back", label = "시럽" },
		machine2 = { at = { -23.59, -1.0, 30.68 }, face = "front", label = "머신 2", body = { -23.68, 0.15, 29.08 }, slots = { { -22.89, -0.7, 30.69 }, { -24.29, -0.7, 30.76 } } },
		lids = { at = { -26.3, -1.2, 36.23 }, face = "back", label = "뚜껑" },
		pickup = { at = { -30.61, -1.0, 30.55 }, face = "front", label = "픽업대", slots = { { -32.21, -1.0, 30.54 }, { -31.16, -1.0, 30.48 }, { -30.12, -1.0, 30.42 }, { -29.07, -1.0, 30.37 } } },
		trash = { at = { -33.0, -4.2, 34.58 }, face = "side", label = "쓰레기통" },
	},
	laneZ = 32.25,
	posCustomer = { 3.21, -4.2, 26.23 },
	pickupCustomer = { -30.76, -4.2, 27.76 },
}
Cafe.LAYOUT = LAYOUT

local SUPPLY_FOR = { -- stock id -> where it is refilled
	cup_ice = "cups",
	cup_hot = "cups",
	lid = "lids",
	ice = "ice",
	milk = "milk",
	beans = "machine",
	vanilla = "syrup",
	caramel = "syrup",
}
local SUPPLY_LOOK = {
	cup_ice = { color = { 200, 225, 240 }, text = "ICE 컵" },
	cup_hot = { color = { 240, 236, 226 }, text = "HOT 컵" },
	lid = { color = { 235, 235, 235 }, text = "뚜껑" },
	ice = { color = { 190, 225, 245 }, text = "얼음" },
	milk = { color = { 245, 245, 240 }, text = "우유" },
	beans = { color = { 90, 60, 40 }, text = "원두" },
	vanilla = { color = { 230, 200, 140 }, text = "바닐라" },
	caramel = { color = { 190, 120, 50 }, text = "카라멜" },
}

-------------------------------------------------------------------------------------------------
-- Build
-------------------------------------------------------------------------------------------------
local function lcf(store: any, v: { number }): CFrame
	return store.cf * CFrame.new(v[1], v[2], v[3])
end

local function worldAt(store: any, v: { number }): Vector3
	return lcf(store, v).Position
end

-- an existing interior part near a point (EspressoBody, PosScreenBack ...)
local function findNear(store: any, name: string, pos: Vector3, radius: number): BasePart?
	local best, bestD = nil, radius
	local root = store.dest.Parent
	if not root then
		return nil
	end
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and d.Name == name then
			local dd = (d.Position - pos).Magnitude
			if dd < bestD then
				best, bestD = d, dd
			end
		end
	end
	return best
end

local function stockLabel(store: any, id: string): string
	local s = store.stock[id] or 0
	local def = C.CAFE.stock[id]
	return string.format("%s %d/%d", def and def.label or id, s, def and def.max or 0)
end

-- the visible amount of each stock (stacks / fill levels), refreshed when stock changes
local function refreshStockVisuals(store: any)
	local v = store.visual
	if not v then
		return
	end
	local function stack(part: BasePart?, n: number, max: number, h: number, base: Vector3)
		if not part then
			return
		end
		local frac = math.clamp(n / math.max(1, max), 0, 1)
		local height = math.max(0.05, h * frac)
		part.Size = Vector3.new(height, part.Size.Y, part.Size.Z)
		part.CFrame = CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		part.Transparency = if n <= 0 then 1 else (part:GetAttribute("BaseT") or 0)
	end
	local S = store.stock
	local M = C.CAFE.stock
	stack(v.cupIce, S.cup_ice, M.cup_ice.max, 1.6, v.cupIceBase)
	stack(v.cupHot, S.cup_hot, M.cup_hot.max, 1.6, v.cupHotBase)
	stack(v.lids, S.lid, M.lid.max, 0.9, v.lidBase)
	if v.iceFill then
		local frac = math.clamp(S.ice / M.ice.max, 0, 1)
		local h = math.max(0.03, 0.5 * frac)
		v.iceFill.Size = Vector3.new(1.4, h, 0.85)
		v.iceFill.CFrame = CFrame.new(v.iceBase + Vector3.new(0, 0.06 + h / 2, 0)) * v.rot
		v.iceFill.Transparency = if S.ice <= 0 then 1 else 0.15
	end
	if v.cartons then
		for i, c in v.cartons do
			c.Transparency = if i <= S.milk then 0 else 1
		end
	end
	if v.syrupV then
		local f = math.clamp(S.vanilla / M.vanilla.max, 0, 1)
		v.syrupV.Size = Vector3.new(math.max(0.05, 0.8 * f), 0.32, 0.32)
		v.syrupV.CFrame = CFrame.new(v.syrupVBase + Vector3.new(0, math.max(0.05, 0.8 * f) / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		local f2 = math.clamp(S.caramel / M.caramel.max, 0, 1)
		v.syrupC.Size = Vector3.new(math.max(0.05, 0.8 * f2), 0.32, 0.32)
		v.syrupC.CFrame = CFrame.new(v.syrupCBase + Vector3.new(0, math.max(0.05, 0.8 * f2) / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	end
	if v.beans then
		for i, m in store.machines do
			if m.hopper then
				local f = math.clamp(S.beans / M.beans.max, 0, 1)
				m.hopper.Color = Color3.fromRGB(math.floor(200 - 120 * f), math.floor(190 - 130 * f), math.floor(180 - 140 * f))
			end
			local _ = i
		end
	end
	if v.trashFill then
		local f = math.clamp(store.trash / 8, 0, 1)
		v.trashFill.Size = Vector3.new(1.05, math.max(0.05, 1.6 * f), 1.05)
		v.trashFill.CFrame = CFrame.new(v.trashBase + Vector3.new(0, 0.1 + math.max(0.05, 1.6 * f) / 2, 0))
		v.trashFill.Transparency = if store.trash <= 0 then 1 else 0
	end
	for id, lab in v.labels do
		if id == "cups" then
			lab.Text = string.format("컵 ICE %d · HOT %d", S.cup_ice, S.cup_hot)
		elseif id == "ice" then
			lab.Text = stockLabel(store, "ice")
		elseif id == "milk" then
			lab.Text = stockLabel(store, "milk")
		elseif id == "lids" then
			lab.Text = stockLabel(store, "lid")
		elseif id == "syrup" then
			lab.Text = string.format("시럽 바닐라 %d · 카라멜 %d", S.vanilla, S.caramel)
		elseif id == "trash" then
			lab.Text = string.format("쓰레기 %d/8", store.trash)
		end
	end
end
Cafe.refreshStockVisuals = refreshStockVisuals

local function buildEquipment(store: any)
	local f = store.folder
	local rot = store.cf - store.cf.Position
	store.visual = { labels = {}, rot = rot }
	local v = store.visual
	local L = LAYOUT.stations
	local function at(id: string): Vector3
		return worldAt(store, L[id].at)
	end
	local function label(id: string, text: string, part: BasePart, y: number?)
		v.labels[id] = Props.label(part, text, { name = "StationLabel", size = UDim2.fromOffset(120, 20), offset = Vector3.new(0, y or 1.6, 0), maxDistance = 16, bgTransparency = 0.35 })
	end
	local white, steel, dark = Color3.fromRGB(240, 240, 238), Color3.fromRGB(150, 156, 162), Color3.fromRGB(40, 42, 46)
	-- cups: two stacks
	do
		local p = at("cups")
		v.cupIceBase = p + rot * Vector3.new(-0.45, 0, 0)
		v.cupHotBase = p + rot * Vector3.new(0.45, 0, 0)
		v.cupIce = Props.cylinder(f, "CupStackIce", 1.6, 0.66, v.cupIceBase + Vector3.new(0, 0.8, 0), Color3.fromRGB(220, 235, 245), { transparency = 0.45, material = Enum.Material.Glass })
		v.cupIce:SetAttribute("BaseT", 0.45)
		v.cupHot = Props.cylinder(f, "CupStackHot", 1.6, 0.66, v.cupHotBase + Vector3.new(0, 0.8, 0), white)
		local mat = Props.part(f, "CupMat", Vector3.new(2.0, 0.04, 0.9), CFrame.new(p + Vector3.new(0, 0.02, 0)) * rot, dark)
		label("cups", "", mat, 2.2)
	end
	-- ice bin
	do
		local p = at("ice")
		v.iceBase = p
		Props.part(f, "IceBinBottom", Vector3.new(1.6, 0.06, 1.0), CFrame.new(p + Vector3.new(0, 0.03, 0)) * rot, steel, { material = Enum.Material.Metal })
		for i, off in { Vector3.new(-0.78, 0.3, 0), Vector3.new(0.78, 0.3, 0) } do
			Props.part(f, "IceBinSide" .. i, Vector3.new(0.05, 0.6, 1.0), CFrame.new(p + rot * off) * rot, steel, { material = Enum.Material.Metal })
		end
		for i, off in { Vector3.new(0, 0.3, -0.48), Vector3.new(0, 0.3, 0.48) } do
			Props.part(f, "IceBinEnd" .. i, Vector3.new(1.6, 0.6, 0.05), CFrame.new(p + rot * off) * rot, steel, { material = Enum.Material.Metal })
		end
		v.iceFill = Props.part(f, "IceFill", Vector3.new(1.4, 0.3, 0.85), CFrame.new(p) * rot, Color3.fromRGB(225, 242, 252), { material = Enum.Material.Glass, transparency = 0.15 })
		Props.part(f, "IceScoop", Vector3.new(0.18, 0.12, 0.7), CFrame.new(p + rot * Vector3.new(0.5, 0.65, 0.2)) * rot, steel, { material = Enum.Material.Metal })
		label("ice", "", v.iceFill, 1.4)
	end
	-- milk fridge (glass door, cartons inside)
	do
		local p = at("milk")
		Props.part(f, "FridgeBody", Vector3.new(1.6, 1.5, 1.0), CFrame.new(p + Vector3.new(0, 0.75, 0)) * rot, white)
		local glass = Props.part(f, "FridgeGlass", Vector3.new(1.4, 1.3, 0.05), CFrame.new(p + rot * Vector3.new(0, 0.75, -0.52)) * rot, Color3.fromRGB(200, 225, 240), { transparency = 0.55, material = Enum.Material.Glass })
		v.cartons = {}
		for i = 1, 10 do
			local row = (i - 1) // 5
			local col = (i - 1) % 5
			local c = Props.part(f, "MilkCarton", Vector3.new(0.22, 0.42, 0.22), CFrame.new(p + rot * Vector3.new(-0.5 + col * 0.25, 0.32 + row * 0.6, -0.15)) * rot, Color3.fromRGB(245, 245, 250))
			Props.part(f, "MilkCap", Vector3.new(0.22, 0.06, 0.22), CFrame.new(p + rot * Vector3.new(-0.5 + col * 0.25, 0.56 + row * 0.6, -0.15)) * rot, Color3.fromRGB(40, 110, 200))
			table.insert(v.cartons, c)
		end
		label("milk", "", glass, 1.3)
	end
	-- water tower
	do
		local p = at("water")
		local body = Props.part(f, "WaterTower", Vector3.new(0.9, 1.5, 0.8), CFrame.new(p + Vector3.new(0, 0.75, 0)) * rot, Color3.fromRGB(225, 228, 232))
		Props.part(f, "TapCold", Vector3.new(0.12, 0.12, 0.2), CFrame.new(p + rot * Vector3.new(-0.2, 0.9, -0.45)) * rot, Color3.fromRGB(60, 130, 230))
		Props.part(f, "TapHot", Vector3.new(0.12, 0.12, 0.2), CFrame.new(p + rot * Vector3.new(0.2, 0.9, -0.45)) * rot, Color3.fromRGB(220, 60, 50))
		Props.part(f, "WaterDrip", Vector3.new(0.7, 0.05, 0.4), CFrame.new(p + rot * Vector3.new(0, 0.05, -0.55)) * rot, steel, { material = Enum.Material.Metal })
		label("water", "정수기 (물 / 뜨거운 물)", body, 1.4)
	end
	-- syrups
	do
		local p = at("syrup")
		v.syrupVBase = p + rot * Vector3.new(-0.3, 0, 0)
		v.syrupCBase = p + rot * Vector3.new(0.3, 0, 0)
		Props.cylinder(f, "SyrupBottleV", 1.0, 0.36, v.syrupVBase + Vector3.new(0, 0.5, 0), Color3.fromRGB(240, 240, 240), { transparency = 0.6, material = Enum.Material.Glass })
		Props.cylinder(f, "SyrupBottleC", 1.0, 0.36, v.syrupCBase + Vector3.new(0, 0.5, 0), Color3.fromRGB(240, 240, 240), { transparency = 0.6, material = Enum.Material.Glass })
		Props.part(f, "PumpV", Vector3.new(0.1, 0.35, 0.1), CFrame.new(v.syrupVBase + Vector3.new(0, 1.15, 0)), dark)
		Props.part(f, "PumpC", Vector3.new(0.1, 0.35, 0.1), CFrame.new(v.syrupCBase + Vector3.new(0, 1.15, 0)), dark)
		v.syrupV = Props.cylinder(f, "SyrupV", 0.8, 0.32, v.syrupVBase + Vector3.new(0, 0.4, 0), Color3.fromRGB(230, 200, 140))
		v.syrupC = Props.cylinder(f, "SyrupC", 0.8, 0.32, v.syrupCBase + Vector3.new(0, 0.4, 0), Color3.fromRGB(190, 120, 50))
		label("syrup", "", v.syrupV, 1.6)
	end
	-- lids
	do
		local p = at("lids")
		v.lidBase = p
		v.lids = Props.cylinder(f, "LidStack", 0.9, 0.72, p + Vector3.new(0, 0.45, 0), white)
		label("lids", "", v.lids, 1.5)
	end
	-- trash bin
	do
		local p = at("trash")
		v.trashBase = p
		Props.cylinder(f, "TrashBin", 2.0, 1.2, p + Vector3.new(0, 1.0, 0), Color3.fromRGB(60, 64, 70), { transparency = 0.2 })
		v.trashFill = Props.part(f, "TrashFill", Vector3.new(1.05, 0.1, 1.05), CFrame.new(p + Vector3.new(0, 0.15, 0)), Color3.fromRGB(110, 90, 70))
		local top = Props.cylinder(f, "TrashRim", 0.08, 1.25, p + Vector3.new(0, 2.02, 0), dark)
		label("trash", "", top, 0.8)
	end
	-- storage shelf with supply boxes
	do
		local p = at("storage")
		local shelf = Props.part(f, "StorageShelf", Vector3.new(2.4, 0.08, 1.0), CFrame.new(p + Vector3.new(0, 0.04, 0)) * rot, Color3.fromRGB(150, 120, 90), { material = Enum.Material.Wood })
		local x = -0.9
		for _, id in { "milk", "ice", "cup_ice", "beans" } do
			Props.part(f, "SupplyBox_" .. id, Vector3.new(0.55, 0.5, 0.7), CFrame.new(p + rot * Vector3.new(x, 0.33, 0)) * rot, Props.rgb(SUPPLY_LOOK[id].color), { material = Enum.Material.Cardboard })
			x += 0.6
		end
		Props.part(f, "Rag", Vector3.new(0.5, 0.06, 0.4), CFrame.new(p + rot * Vector3.new(0.6, 0.6, 0.2)) * rot, Color3.fromRGB(80, 140, 200), { material = Enum.Material.Fabric })
		label("storage", "창고 선반 (재료 보충 · 행주)", shelf, 1.4)
	end
	-- steam station (wand + pitcher slots)
	do
		local p = at("steam")
		local pad = Props.part(f, "SteamPad", Vector3.new(2.0, 0.04, 0.8), CFrame.new(p + Vector3.new(0, 0.02, 0)) * rot, steel, { material = Enum.Material.Metal })
		Props.part(f, "SteamWand", Vector3.new(0.08, 1.2, 0.08), CFrame.new(p + rot * Vector3.new(-0.3, 1.0, 0.25)) * rot * CFrame.Angles(math.rad(15), 0, 0), steel, { material = Enum.Material.Metal })
		v.steamLight = Props.part(f, "SteamLight", Vector3.new(0.2, 0.2, 0.2), CFrame.new(p + rot * Vector3.new(0.9, 0.2, 0.3)), Color3.fromRGB(90, 90, 90), { material = Enum.Material.Neon, shape = Enum.PartType.Ball })
		label("steam", "스팀 피처", pad, 1.8)
	end
	-- work mat, pickup pads
	do
		local p = at("work")
		local mat = Props.part(f, "WorkMat", Vector3.new(3.8, 0.03, 0.7), CFrame.new(p + Vector3.new(0, 0.015, 0)) * rot, Color3.fromRGB(30, 80, 60))
		label("work", "작업대 (컵 임시 보관)", mat, 1.4)
		local q = at("pickup")
		local pad = Props.part(f, "PickupMat", Vector3.new(4.4, 0.03, 0.8), CFrame.new(q + Vector3.new(0, 0.015, 0)) * rot, Color3.fromRGB(20, 20, 24))
		v.pickupNums = {}
		for i, s in LAYOUT.stations.pickup.slots do
			local sp = worldAt(store, s)
			local n = Props.part(f, "PickupSlot" .. i, Vector3.new(0.9, 0.02, 0.7), CFrame.new(sp + Vector3.new(0, 0.03, 0)) * rot, Color3.fromRGB(60, 60, 66))
			table.insert(v.pickupNums, n)
		end
		label("pickup", "픽업대", pad, 1.6)
	end
	-- POS screen
	do
		local p = at("pos")
		local screen = findNear(store, "CustomerDisplay", p + Vector3.new(0, 1.2, 0), 2.5) or findNear(store, "PosScreenBack", p + Vector3.new(0, 1.2, 0), 2.5)
		if not screen then
			Props.part(f, "PosBase", Vector3.new(1.4, 0.4, 1.0), CFrame.new(p + Vector3.new(0, 0.2, 0)) * rot, dark)
			screen = Props.part(f, "PosScreen", Vector3.new(1.4, 0.9, 0.08), CFrame.new(p + rot * Vector3.new(0, 0.9, 0.2)) * rot, dark)
		end
		local disp = Props.part(f, "PosDisplay", Vector3.new(1.1, 0.7, 0.04), CFrame.new(p + rot * Vector3.new(0, 1.25, 0.65)) * rot * CFrame.Angles(math.rad(-15), 0, 0), Color3.fromRGB(15, 20, 28), { material = Enum.Material.Neon })
		v.posScreen = Props.screen(disp, "CLOSED", { face = Enum.NormalId.Back, color = Color3.fromRGB(150, 150, 160) })
		v.posDisplay = disp
		label("pos", "POS", disp, 1.0)
		-- the test-customer notice (removed when an NPC provider connects)
		v.testSign = Props.label(disp, "", { name = "TestSign", size = UDim2.fromOffset(190, 22), offset = Vector3.new(0, 2.0, 0), maxDistance = 40, bg = Color3.fromRGB(120, 70, 200), bgTransparency = 0.1 })
	end
	-- time clock kiosk at the staff entrance
	do
		local p = at("timeclock")
		local stand = Props.part(f, "TimeClockStand", Vector3.new(0.35, 3.6, 0.35), CFrame.new(p + Vector3.new(0, 1.8, 0)) * rot, Color3.fromRGB(58, 62, 70), { material = Enum.Material.Metal })
		local head = Props.part(f, "TimeClock", Vector3.new(1.5, 1.1, 0.35), CFrame.new(p + Vector3.new(0, 4.0, 0)) * rot * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(32, 36, 44))
		local scr = Props.part(f, "TimeClockScreen", Vector3.new(1.2, 0.75, 0.04), head.CFrame * CFrame.new(0, 0.05, -0.19), Color3.fromRGB(20, 120, 90), { material = Enum.Material.Neon })
		Props.screen(scr, "출퇴근\n체크", { face = Enum.NormalId.Front })
		Props.label(stand, "STAFF ONLY", { name = "StaffSign", size = UDim2.fromOffset(110, 20), offset = Vector3.new(0, 3.2, 0), maxDistance = 30, bg = Color3.fromRGB(0, 98, 65) })
	end
	-- espresso machines: existing bodies get status lights (built if missing)
	store.machines = {}
	for mi, id in { "machine1", "machine2" } do
		local def = LAYOUT.stations[id]
		local bodyPos = worldAt(store, def.body)
		local body = findNear(store, "EspressoBody", bodyPos, 2.5)
		if not body then
			body = Props.part(f, "EspressoBody", Vector3.new(2.4, 1.6, 1.4), CFrame.new(bodyPos) * rot, Color3.fromRGB(190, 192, 196), { material = Enum.Material.Metal })
		end
		local light = Props.part(f, "MachineLight" .. mi, Vector3.new(0.28, 0.28, 0.28), CFrame.new(body.Position + Vector3.new(0, body.Size.Y / 2 + 0.2, 0)), Color3.fromRGB(70, 70, 70), { material = Enum.Material.Neon, shape = Enum.PartType.Ball })
		local heads = {}
		for hi, s in def.slots do
			local sp = worldAt(store, s)
			local hl = Props.part(f, "HeadLight" .. mi .. "_" .. hi, Vector3.new(0.14, 0.14, 0.14), CFrame.new(sp + Vector3.new(0, 1.05, 0)), Color3.fromRGB(70, 70, 70), { material = Enum.Material.Neon, shape = Enum.PartType.Ball })
			table.insert(heads, { item = nil, untilT = nil, shots = 0, owner = nil, light = hl, stopLoop = nil })
		end
		local hopper = findNear(store, "GrinderHopper", bodyPos, 4)
		table.insert(store.machines, { index = mi, station = id, body = body, light = light, heads = heads, warm = false, warmUntil = nil, shots = 0, hopper = hopper, locked = mi == 2 })
	end
	v.beans = true
	-- steam pitchers (items on the steam slots)
	store.pitchers = {}
	for i, s in LAYOUT.stations.steam.slots do
		local item = W.newItem(store, "pitcher", { milk = "empty", slotIndex = i })
		table.insert(store.pitchers, item.id)
		Props.create(item, f, lcf(store, s))
		item.loc = { type = "slot", station = "steam", slot = i }
		store.slots.steam[i] = item.id
	end
end

-------------------------------------------------------------------------------------------------
-- Stations from the building (tag GwWorkStation, attrs Store/Station) override the layout positions
-------------------------------------------------------------------------------------------------
local function taggedStations(storeId: string): { [string]: BasePart }
	local out = {}
	for _, inst in CollectionService:GetTagged("GwWorkStation") do
		if inst:IsA("BasePart") and inst:GetAttribute("Store") == storeId and type(inst:GetAttribute("Station")) == "string" then
			out[inst:GetAttribute("Station")] = inst
		end
	end
	return out
end

function Cafe.build(store: any)
	store.stock = {}
	for id, def in C.CAFE.stock do
		store.stock[id] = def.start
	end
	store.trash = 0
	store.slots = { work = {}, steam = {}, pickup = {} }
	store.puddles = {}
	store.close = {}
	for _, id in C.CAFE.closeTasks do
		store.close[id] = false
	end
	-- where each station is used from (world positions)
	store.stationList = {}
	local tagged = taggedStations(store.id)
	for id, def in LAYOUT.stations do
		local pos = if tagged[id] then tagged[id].Position else worldAt(store, def.at)
		table.insert(store.stationList, { id = id, label = def.label, pos = pos, face = def.face })
	end
	buildEquipment(store)
	refreshStockVisuals(store)
	Cafe.refreshLights(store)
end

-------------------------------------------------------------------------------------------------
-- Visual state of lights / screens
-------------------------------------------------------------------------------------------------
local LIGHT = {
	off = Color3.fromRGB(70, 70, 70),
	cold = Color3.fromRGB(220, 60, 50),
	warming = Color3.fromRGB(250, 190, 40),
	ready = Color3.fromRGB(60, 220, 110),
	clean = Color3.fromRGB(170, 90, 240),
	extracting = Color3.fromRGB(255, 150, 40),
	done = Color3.fromRGB(80, 230, 255),
}

function Cafe.refreshLights(store: any)
	local level = store.level or 1
	for _, m in store.machines or {} do
		m.locked = m.index == 2 and not WS.cafeUnlocks(level).tools.machine2
		local col = LIGHT.off
		if store.open and not m.locked then
			if m.warmUntil then
				col = LIGHT.warming
			elseif not m.warm then
				col = LIGHT.cold
			elseif m.shots >= C.CAFE.cleanAfterShots then
				col = LIGHT.clean
			else
				col = LIGHT.ready
			end
		end
		m.light.Color = col
		for _, h in m.heads do
			h.light.Color = if h.item and h.untilT then LIGHT.extracting elseif h.item then LIGHT.done else LIGHT.off
		end
	end
	local v = store.visual
	if v and v.posScreen then
		local unconfirmed = 0
		for _, o in Orders.open(store.id) do
			if not o.confirmed then
				unconfirmed += 1
			end
		end
		v.posScreen.Text = if not store.open then "CLOSED" elseif unconfirmed > 0 then string.format("주문 대기 %d", unconfirmed) else "OPEN"
		v.posScreen.TextColor3 = if not store.open then Color3.fromRGB(150, 150, 160) elseif unconfirmed > 0 then Color3.fromRGB(255, 210, 90) else Color3.fromRGB(110, 240, 160)
		v.testSign.Text = if store.open and not Orders.hasProvider(store.id) then "🧪 테스트 손님 모드 · NPC 연결 전" else ""
		;(v.testSign.Parent :: BillboardGui).Enabled = v.testSign.Text ~= ""
	end
	if v and v.steamLight then
		local busy = false
		for _, pid in store.pitchers or {} do
			local p = store.items[pid]
			if p and p.milk == "steaming" then
				busy = true
			end
		end
		v.steamLight.Color = if not store.open then LIGHT.off elseif busy then LIGHT.extracting else LIGHT.ready
	end
	if v and v.pickupNums then
		for i, part in v.pickupNums do
			part.Color = if store.slots.pickup[i] then Color3.fromRGB(255, 200, 80) else Color3.fromRGB(60, 60, 66)
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Open / close
-------------------------------------------------------------------------------------------------
function Cafe.activate(store: any)
	store.open = true
	Cafe.refreshLights(store)
end

function Cafe.deactivate(store: any)
	store.open = false
	-- every loose cup / supply / rag is cleared; pitchers are emptied; machines cool down
	for id, item in store.items do
		if item.kind ~= "pitcher" then
			W.destroyItem(store, item)
		else
			item.milk = "empty"
			item.untilT = nil
			Props.refresh(item)
		end
	end
	store.slots.work = {}
	store.slots.pickup = {}
	for _, m in store.machines do
		m.warm = false
		m.warmUntil = nil
		for _, h in m.heads do
			h.item = nil
			h.untilT = nil
			if h.stopLoop then
				h.stopLoop()
				h.stopLoop = nil
			end
		end
	end
	for _, p in store.puddles do
		if p.part then
			p.part:Destroy()
		end
	end
	store.puddles = {}
	for id, def in C.CAFE.stock do
		store.stock[id] = def.start
	end
	store.trash = 0
	for k in store.close do
		store.close[k] = false
	end
	refreshStockVisuals(store)
	Cafe.refreshLights(store)
end

-------------------------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------------------------
local function held(store: any, sess: any, i: number?): any?
	local id = sess.held[i or 1]
	return id and store.items[id] or nil
end

local function hasLiquid(cup: any): boolean
	for _, id in cup.parts or {} do
		local ing = WS.INGREDIENTS[id]
		if ing and ing.liquid then
			return true
		end
	end
	return false
end

local function slotCF(store: any, station: string, i: number): CFrame
	local def = LAYOUT.stations[station]
	if station == "machine1" or station == "machine2" then
		return lcf(store, def.slots[i])
	end
	return lcf(store, def.slots[i])
end

local function placeOn(store: any, item: any, station: string, i: number)
	Props.put(item, store.folder, slotCF(store, station, i))
	item.loc = { type = "slot", station = station, slot = i }
end

local function freeSlot(list: { any }, n: number): number?
	for i = 1, n do
		if list[i] == nil then
			return i
		end
	end
	return nil
end

local function cupText(cup: any): string
	local t = string.format("%s %s 컵", WS.TEMP_LABEL[cup.temp] or "", WS.SIZE_LABEL[cup.size] or "")
	if cup.sticker then
		t = cup.sticker .. " " .. t
	end
	return t
end

-- the order item a fresh cup gets stickered for (focused order first)
local function claimFor(store: any, sess: any, temp: string, size: string): (any?, number?)
	local function try(o: any): number?
		if not o or not o.confirmed or not WS.isOpen(o.state) or o.state == "ready" then
			return nil
		end
		for i, it in o.items do
			if not it.itemId and not it.cupId and it.spec.temp == temp then
				return i
			end
		end
		return nil
	end
	local f = Orders.get(sess.focus)
	local i = try(f)
	if i then
		return f, i
	end
	for _, o in Orders.open(store.id) do
		local k = try(o)
		if k then
			return o, k
		end
	end
	return nil, nil
end

local function unclaim(cup: any)
	if cup.orderId then
		local o = Orders.get(cup.orderId)
		local it = o and o.items[cup.itemIndex]
		if it and it.cupId == cup.id then
			it.cupId = nil
		end
	end
end

local function canTake(store: any, sess: any): boolean
	local cap = if WS.cafeUnlocks(sess.level).tools.tray then 2 else 1
	if #sess.held == 0 then
		return true
	end
	if #sess.held < cap then
		-- the tray only carries lidded cups
		local a = held(store, sess)
		return a ~= nil and a.kind == "cup" and a.lid == true
	end
	return false
end

local function addPart(store: any, cup: any, ing: string)
	table.insert(cup.parts, ing)
	Props.refresh(cup)
end

local function useStock(store: any, id: string, n: number?): boolean
	local k = n or 1
	if (store.stock[id] or 0) < k then
		return false
	end
	store.stock[id] -= k
	refreshStockVisuals(store)
	return true
end

-------------------------------------------------------------------------------------------------
-- Action list for a station (what the nearby station can do right now). Each action:
--   { id, label, icon?, dur (s), enabled, reason?, primary? }
-------------------------------------------------------------------------------------------------
local function A(id: string, label: string, dur: number, enabled: boolean, reason: string?, icon: string?): any
	return { id = id, label = label, dur = dur, enabled = enabled, reason = reason, icon = icon }
end

local function stockReason(store: any, id: string): string?
	if (store.stock[id] or 0) <= 0 then
		return (C.CAFE.stock[id] and C.CAFE.stock[id].label or id) .. " 없음 · 창고에서 보충"
	end
	return nil
end

function Cafe.actions(store: any, player: Player, sess: any, station: string): { any }
	local out = {}
	local h = held(store, sess)
	local cup = if h and h.kind == "cup" then h else nil
	local open = cup and not cup.lid and not cup.spilled
	local u = WS.cafeUnlocks(sess.level)
	if not store.open then
		return out
	end
	if station == "timeclock" then
		table.insert(out, A("clockout", "퇴근하기 (정산)", 0.3, true, nil, "🏁"))
		return out
	end
	if station == "pos" then
		local waiting = nil
		for _, o in Orders.open(store.id) do
			if not o.confirmed and (not waiting or o.createdAt < waiting.createdAt) then
				waiting = o
			end
		end
		if waiting then
			local names = {}
			for _, it in waiting.items do
				table.insert(names, WS.specText(it.spec))
			end
			table.insert(out, A("confirm:" .. waiting.id, string.format("주문 받기 #%d (%d잔)", waiting.number, #waiting.items), 0.5, true, nil, "🧾"))
		else
			table.insert(out, A("none", "주문 대기 중인 손님 없음", 0, false, nil, "🧾"))
		end
		return out
	end
	if station == "storage" then
		if h and h.kind == "supply" then
			table.insert(out, A("putback", h.text .. " 박스 내려놓기", 0.3, true, nil, "📦"))
		elseif h and h.kind == "rag" then
			table.insert(out, A("putback", "행주 걸어두기", 0.2, true, nil, "🧽"))
		elseif #sess.held == 0 then
			local list = { "milk", "ice", "cup_ice", "cup_hot", "lid", "beans" }
			if table.find(u.menus, "vanilla_latte") then
				table.insert(list, "vanilla")
			end
			if table.find(u.menus, "caramel_macchiato") then
				table.insert(list, "caramel")
			end
			for _, id in list do
				local def = C.CAFE.stock[id]
				local s = store.stock[id] or 0
				local low = s <= def.max * C.CAFE.lowStockShare
				table.insert(out, A("supply:" .. id, string.format("%s 보충 박스%s", SUPPLY_LOOK[id].text, if low then " ⚠️" else ""), 0.4, s < def.max, if s >= def.max then "가득 차 있어요" else nil, "📦"))
			end
			table.insert(out, A("rag", "행주 들기 (청소)", 0.2, true, nil, "🧽"))
		else
			table.insert(out, A("none", "손에 든 걸 먼저 내려놓아요", 0, false, nil, "✋"))
		end
		return out
	end
	if station == "cups" then
		if h and h.kind == "supply" and (h.stock == "cup_ice" or h.stock == "cup_hot") then
			table.insert(out, A("fill", h.text .. " 채우기", 0.6, true, nil, "📥"))
		elseif cup and #cup.parts == 0 and not cup.lid and not cup.sticker then
			table.insert(out, A("return", "빈 컵 되돌려 놓기", 0.2, true, nil, "↩️"))
		elseif #sess.held == 0 or canTake(store, sess) then
			local sizes = if u.options.size then { "tall", "grande" } else { "tall" }
			for _, temp in { "ice", "hot" } do
				for _, size in sizes do
					local stockId = WS.cupStock(temp)
					local reason = stockReason(store, stockId)
					if #sess.held > 0 then
						reason = "손이 비어 있어야 해요"
					end
					table.insert(out, A(string.format("cup:%s:%s", temp, size), string.format("%s 컵 %s", WS.TEMP_LABEL[temp], WS.SIZE_LABEL[size]), 0.3, reason == nil, reason, if temp == "ice" then "🥤" else "☕"))
				end
			end
		else
			table.insert(out, A("none", "손이 꽉 찼어요", 0, false, nil, "✋"))
		end
		return out
	end
	if station == "ice" then
		if h and h.kind == "supply" and h.stock == "ice" then
			table.insert(out, A("fill", "얼음 채우기", 0.7, true, nil, "📥"))
		elseif open then
			table.insert(out, A("add:ice", "얼음 담기", 0.4, store.stock.ice > 0, stockReason(store, "ice"), "🧊"))
		else
			table.insert(out, A("none", if cup and cup.lid then "뚜껑 닫힌 컵이에요" else "컵을 들고 오세요", 0, false, nil, "🧊"))
		end
		return out
	end
	if station == "milk" then
		if h and h.kind == "supply" and h.stock == "milk" then
			table.insert(out, A("fill", "우유 채우기", 0.7, true, nil, "📥"))
		elseif open then
			table.insert(out, A("add:milk", "차가운 우유 붓기", 0.5, store.stock.milk > 0, stockReason(store, "milk"), "🥛"))
		else
			table.insert(out, A("none", "컵을 들고 오세요 (스팀 우유는 스팀 피처)", 0, false, nil, "🥛"))
		end
		return out
	end
	if station == "water" then
		if open then
			table.insert(out, A("add:water", "물 붓기", 0.5, true, nil, "💧"))
			table.insert(out, A("add:hotwater", "뜨거운 물 붓기", 0.5, true, nil, "♨️"))
		else
			table.insert(out, A("none", "컵을 들고 오세요", 0, false, nil, "💧"))
		end
		return out
	end
	if station == "syrup" then
		if h and h.kind == "supply" and (h.stock == "vanilla" or h.stock == "caramel") then
			table.insert(out, A("fill", h.text .. " 채우기", 0.6, true, nil, "📥"))
		elseif open then
			if table.find(u.menus, "vanilla_latte") then
				table.insert(out, A("add:vanilla", "바닐라 시럽 펌프", 0.35, store.stock.vanilla > 0, stockReason(store, "vanilla"), "🍯"))
			end
			if table.find(u.menus, "caramel_macchiato") then
				table.insert(out, A("add:caramel", "카라멜 드리즐", 0.45, store.stock.caramel > 0, stockReason(store, "caramel"), "🍮"))
			end
			if #out == 0 then
				table.insert(out, A("none", "시럽 메뉴는 숙련도 Lv.2부터", 0, false, nil, "🍯"))
			end
		else
			table.insert(out, A("none", "컵을 들고 오세요", 0, false, nil, "🍯"))
		end
		return out
	end
	if station == "lids" then
		if h and h.kind == "supply" and h.stock == "lid" then
			table.insert(out, A("fill", "뚜껑 채우기", 0.5, true, nil, "📥"))
		elseif open then
			local reason = stockReason(store, "lid")
			if not hasLiquid(cup) then
				reason = "빈 컵이에요"
			end
			table.insert(out, A("lid", "뚜껑 닫기", 0.35, reason == nil, reason, "🔒"))
		else
			table.insert(out, A("none", if cup and cup.lid then "이미 닫혔어요" else "컵을 들고 오세요", 0, false, nil, "🔒"))
		end
		return out
	end
	if station == "trash" then
		if h then
			local full = store.trash >= 8
			local what = if h.kind == "cup" then "컵 버리기 (폐기)" elseif h.kind == "pitcher" then "피처 비우기" else "버리기"
			if h.kind == "supply" or h.kind == "rag" then
				table.insert(out, A("none", "보충품은 버리지 않아요", 0, false, nil, "🗑️"))
			else
				table.insert(out, A("discard", what, 0.3, not full, if full then "쓰레기통이 꽉 찼어요 → 비우기" else nil, "🗑️"))
			end
		end
		if #sess.held == 0 then
			table.insert(out, A("empty", string.format("쓰레기통 비우기 (%d/8)", store.trash), 1.0, store.trash > 0, if store.trash <= 0 then "비어 있어요" else nil, "🗑️"))
		end
		if #out == 0 then
			table.insert(out, A("none", "쓰레기통", 0, false, nil, "🗑️"))
		end
		return out
	end
	if station == "steam" then
		local n = if u.tools.steam2 then 2 else 1
		for i = 1, n do
			local pid = store.slots.steam[i]
			local p = pid and store.items[pid]
			local tag = if n > 1 then string.format(" (%d)", i) else ""
			if not p then
				if h and h.kind == "pitcher" then
					table.insert(out, A("putpitcher:" .. i, "피처 내려놓기" .. tag, 0.2, true, nil, "🫙"))
				end
			elseif p.milk == "empty" then
				local reason = stockReason(store, "milk")
				if #sess.held > 0 and h and h.kind ~= "cup" then
					reason = "손에 든 걸 먼저 내려놓아요"
				end
				table.insert(out, A("steam:" .. i .. ":steamed", "우유 스팀 (라떼)" .. tag, 0.4, reason == nil, reason, "♨️"))
				if table.find(u.menus, "cappuccino") then
					table.insert(out, A("steam:" .. i .. ":foam", "거품 스팀 (카푸치노)" .. tag, 0.4, reason == nil, reason, "☁️"))
				end
			elseif p.milk == "steaming" then
				local left = math.max(0, math.ceil((p.untilT or 0) - os.clock()))
				table.insert(out, A("wait", string.format("스팀 중 %d초%s", left, tag), 0, false, nil, "♨️"))
			elseif p.milk == "burnt" then
				table.insert(out, A("burnt:" .. i, "탄 우유 버리기" .. tag, 0.4, true, nil, "🔥"))
			else
				local what = if p.milk == "foam" then "거품 올리기" else "스팀 우유 붓기"
				table.insert(out, A("pour:" .. i, what .. tag, 0.5, open == true, if not open then "컵을 들고 오세요" else nil, "🥛"))
			end
		end
		return out
	end
	if station == "machine1" or station == "machine2" then
		local m = store.machines[if station == "machine1" then 1 else 2]
		if m.locked then
			table.insert(out, A("none", string.format("잠김 · %s Lv.%d 도구", "카페", C.CAFE.tools.machine2.level), 0, false, nil, "🔒"))
			return out
		end
		if h and h.kind == "supply" and h.stock == "beans" then
			table.insert(out, A("fill", "원두 채우기", 0.6, true, nil, "📥"))
			return out
		end
		if not m.warm then
			if m.warmUntil then
				table.insert(out, A("wait", string.format("예열 중 %d초", math.max(0, math.ceil(m.warmUntil - os.clock()))), 0, false, nil, "🔥"))
			else
				table.insert(out, A("warm", "머신 예열", 0.4, true, nil, "🔥"))
			end
			return out
		end
		for hi, hd in m.heads do
			local tag = if hi == 1 then "A" else "B"
			if hd.item then
				local item = store.items[hd.item]
				if hd.untilT then
					table.insert(out, A("wait", string.format("%s 추출 중 %d초", tag, math.max(0, math.ceil(hd.untilT - os.clock()))), 0, false, nil, "☕"))
					table.insert(out, A("stop:" .. hi, tag .. " 추출 멈추기", 0.2, true, nil, "⏹️"))
				else
					table.insert(out, A("take:" .. hi, string.format("%s %s 가져가기", tag, if item then cupText(item) else "컵"), 0.3, canTake(store, sess), if not canTake(store, sess) then "손이 꽉 찼어요" else nil, "✋"))
				end
			elseif open then
				local reason = nil
				if store.stock.beans < 1 then
					reason = "원두 없음 · 창고에서 보충"
				end
				table.insert(out, A(string.format("extract:%d:1", hi), string.format("%s에 컵 올리고 샷 1잔", tag), 0.35, reason == nil, reason, "☕"))
				table.insert(out, A(string.format("extract:%d:2", hi), string.format("%s 샷 2잔", tag), 0.35, reason == nil and store.stock.beans >= 2, reason or (if store.stock.beans < 2 then "원두 부족" else nil), "☕"))
			end
		end
		local busy = false
		for _, hd in m.heads do
			if hd.item then
				busy = true
			end
		end
		if m.shots >= C.CAFE.cleanAfterShots or (W.phaseOf(store) == "close" and not store.close.clean_machine) then
			table.insert(out, A("clean", "머신 청소" .. (if m.shots >= C.CAFE.cleanAfterShots then " ⚠️" else " (마감)"), 1.6, not busy and #sess.held == 0, if busy then "추출 중인 컵을 먼저 빼요" elseif #sess.held > 0 then "손을 비워요" else nil, "🧽"))
		end
		return out
	end
	if station == "work" then
		if h and h.kind == "rag" and W.phaseOf(store) == "close" and not store.close.wipe_counter then
			table.insert(out, A("wipe", "카운터 닦기 (마감)", 1.4, true, nil, "🧽"))
		end
		if h and (h.kind == "cup" or h.kind == "pitcher") then
			local i = freeSlot(store.slots.work, 3)
			table.insert(out, A("putwork", "작업대에 내려놓기", 0.2, i ~= nil, if not i then "작업대가 꽉 찼어요" else nil, "⬇️"))
		end
		for i = 1, 3 do
			local id = store.slots.work[i]
			local it = id and store.items[id]
			if it then
				table.insert(out, A("takework:" .. i, (if it.kind == "cup" then cupText(it) else "피처") .. " 집기", 0.2, canTake(store, sess), if not canTake(store, sess) then "손이 꽉 찼어요" else nil, "✋"))
			end
		end
		if #out == 0 then
			table.insert(out, A("none", "작업대 (컵 임시 보관)", 0, false, nil, "⬇️"))
		end
		return out
	end
	if station == "pickup" then
		if cup then
			if not cup.lid then
				table.insert(out, A("none", "뚜껑부터 닫아요", 0, false, nil, "🔒"))
			else
				local slot = freeSlot(store.slots.pickup, C.CAFE.pickupSlots)
				local list = {}
				for _, o in Orders.open(store.id) do
					if o.confirmed and o.state ~= "ready" then
						for i, it in o.items do
							if not it.itemId then
								table.insert(list, { o = o, i = i, it = it })
							end
						end
					end
				end
				-- the sticker's order first
				table.sort(list, function(a, b)
					local sa = if cup.orderId == a.o.id and cup.itemIndex == a.i then 0 else 1
					local sb = if cup.orderId == b.o.id and cup.itemIndex == b.i then 0 else 1
					if sa ~= sb then
						return sa < sb
					end
					return a.o.createdAt < b.o.createdAt
				end)
				for k, e in list do
					if k > 4 then
						break
					end
					table.insert(out, A(string.format("serve:%s:%d", e.o.id, e.i), string.format("#%d %s 자리에 놓기", e.o.number, WS.specText(e.it.spec)), 0.3, slot ~= nil, if not slot then "픽업대가 꽉 찼어요" else nil, "🔔"))
				end
				if #list == 0 then
					table.insert(out, A("none", "기다리는 주문이 없어요 (작업대에 보관)", 0, false, nil, "🔔"))
				end
			end
		end
		for i = 1, C.CAFE.pickupSlots do
			local id = store.slots.pickup[i]
			local it = id and store.items[id]
			if it and #sess.held == 0 then
				local o = it.servedFor and Orders.get(it.servedFor)
				if not o or o.state ~= "ready" then
					table.insert(out, A("unserve:" .. i, string.format("%s 다시 집기", cupText(it)), 0.2, true, nil, "✋"))
				end
			end
		end
		if #out == 0 then
			table.insert(out, A("none", "완성된 음료를 들고 오세요", 0, false, nil, "🔔"))
		end
		return out
	end
	if string.sub(station, 1, 7) == "puddle:" then
		if h and h.kind == "rag" then
			table.insert(out, A("mop", "쏟은 음료 닦기", 1.4, true, nil, "🧽"))
		else
			table.insert(out, A("none", "행주가 필요해요 (창고 선반)", 0, false, nil, "🧽"))
		end
		return out
	end
	return out
end

-------------------------------------------------------------------------------------------------
-- Perform an action (server truth). -> ok, message?
-------------------------------------------------------------------------------------------------
local function startExtraction(store: any, m: any, hi: number, shots: number, player: Player, sess: any)
	local hd = m.heads[hi]
	local speed = (if m.shots >= C.CAFE.cleanAfterShots then 1.5 else 1) * (if WS.cafeUnlocks(sess.level).tools.grinder then 0.75 else 1)
	hd.untilT = os.clock() + C.CAFE.extractSeconds * speed
	hd.shots = shots
	hd.owner = player
	hd.stopLoop = Props.loop(m.body, "extract", 0.35)
	m.shots += shots
end

function Cafe.act(store: any, player: Player, sess: any, station: string, action: string, _arg: any?): (boolean, string?)
	local valid = false
	for _, a in Cafe.actions(store, player, sess, station) do
		if a.id == action then
			if not a.enabled then
				return false, a.reason or "지금은 할 수 없어요"
			end
			valid = true
			break
		end
	end
	if not valid then
		return false, "지금은 할 수 없어요"
	end
	local parts = string.split(action, ":")
	local verb = parts[1]
	local h = held(store, sess)
	local sfxAt = W.stationPart(store, station)
	if verb == "clockout" then
		W.requestEnd(player)
		return true
	elseif verb == "confirm" then
		local o = Orders.get(parts[2] .. (if parts[3] then ":" .. parts[3] else ""))
		if not o then
			return false, "주문이 없어요"
		end
		Orders.confirm(o)
		sess.focus = sess.focus or o.id
		Props.sound(store.visual.posDisplay, "ready", 0.5)
		W.toast(player, string.format("🧾 #%d 주문 접수 · %s", o.number, W.orderSummary(o)), "order")
		W.xp(player, sess, 1)
		return true
	elseif verb == "supply" then
		local id = parts[2]
		local look = SUPPLY_LOOK[id]
		local item = W.newItem(store, "supply", { stock = id, text = look.text, color = look.color, boxSize = Vector3.new(1.2, 0.8, 0.9) })
		Props.create(item, store.folder, CFrame.new(sfxAt and sfxAt.Position or store.cf.Position))
		W.hold(player, sess, item)
		Props.sound(sfxAt, "pickup", 0.4)
		return true
	elseif verb == "rag" then
		local item = W.newItem(store, "rag", { color = { 80, 140, 200 }, size3 = Vector3.new(0.5, 0.08, 0.4), material = Enum.Material.Fabric })
		Props.create(item, store.folder, CFrame.new(sfxAt and sfxAt.Position or store.cf.Position))
		W.hold(player, sess, item)
		return true
	elseif verb == "putback" then
		W.drop(player, sess)
		return true
	elseif verb == "fill" then
		local id = h.stock
		local def = C.CAFE.stock[id]
		store.stock[id] = math.min(def.max, (store.stock[id] or 0) + def.refill)
		W.drop(player, sess)
		refreshStockVisuals(store)
		Props.sound(sfxAt, "place", 0.5)
		W.task(player, sess, "restock", C.CVS.perfTask * 0.5)
		if id == "cup_ice" or id == "cup_hot" then
			if W.phaseOf(store) == "close" and store.stock.cup_ice >= def.max * 0.75 and store.stock.cup_hot >= def.max * 0.75 then
				W.closeTask(store, player, sess, "restock_cups")
			end
		end
		return true
	elseif verb == "cup" then
		local temp, size = parts[2], parts[3]
		if not useStock(store, WS.cupStock(temp)) then
			return false, "컵이 없어요"
		end
		local item = W.newItem(store, "cup", { temp = temp, size = size, parts = {}, lid = false, maker = player })
		local o, idx = claimFor(store, sess, temp, size)
		if o and idx then
			item.orderId = o.id
			item.itemIndex = idx
			item.spec = o.items[idx].spec
			item.sticker = "#" .. o.number
			o.items[idx].cupId = item.id
			if o.state == "received" then
				Orders.move(o, "preparing")
			end
		end
		Props.create(item, store.folder, CFrame.new(sfxAt and sfxAt.Position or store.cf.Position))
		W.hold(player, sess, item)
		Props.sound(sfxAt, "pickup", 0.4)
		return true
	elseif verb == "return" then
		store.stock[WS.cupStock(h.temp)] += 1
		unclaim(h)
		W.dropDestroy(player, sess)
		refreshStockVisuals(store)
		return true
	elseif verb == "add" then
		local ing = parts[2]
		local def = WS.INGREDIENTS[ing]
		if def and def.stock and def.stock ~= "beans" then
			if not useStock(store, def.stock) then
				return false, stockReason(store, def.stock)
			end
		end
		addPart(store, h, ing)
		Props.sound(sfxAt, if ing == "ice" then "ice" else "pour", 0.45)
		W.afterStep(player, sess, h)
		return true
	elseif verb == "lid" then
		if not useStock(store, "lid") then
			return false, "뚜껑이 없어요"
		end
		h.lid = true
		Props.refresh(h)
		Props.sound(sfxAt, "place", 0.5)
		W.afterStep(player, sess, h)
		return true
	elseif verb == "warm" then
		local m = store.machines[if station == "machine1" then 1 else 2]
		m.warmUntil = os.clock() + C.CAFE.warmupSeconds
		Props.sound(m.body, "steam", 0.3)
		Cafe.refreshLights(store)
		return true
	elseif verb == "extract" then
		local m = store.machines[if station == "machine1" then 1 else 2]
		local hi, shots = tonumber(parts[2]), tonumber(parts[3])
		if not useStock(store, "beans", shots) then
			return false, "원두가 부족해요"
		end
		local cup = W.take(player, sess)
		m.heads[hi].item = cup.id
		placeOn(store, cup, station, hi)
		startExtraction(store, m, hi, shots, player, sess)
		Cafe.refreshLights(store)
		return true
	elseif verb == "stop" then
		local m = store.machines[if station == "machine1" then 1 else 2]
		local hd = m.heads[tonumber(parts[2])]
		hd.untilT = nil
		hd.shots = 0
		if hd.stopLoop then
			hd.stopLoop()
			hd.stopLoop = nil
		end
		Cafe.refreshLights(store)
		W.toast(player, "추출을 멈췄어요 (샷은 들어가지 않았어요)", "info")
		return true
	elseif verb == "take" then
		local m = store.machines[if station == "machine1" then 1 else 2]
		local hd = m.heads[tonumber(parts[2])]
		local cup = store.items[hd.item]
		hd.item = nil
		hd.owner = nil
		if cup then
			W.hold(player, sess, cup)
		end
		Cafe.refreshLights(store)
		return true
	elseif verb == "clean" then
		local m = store.machines[if station == "machine1" then 1 else 2]
		m.shots = 0
		Props.sound(m.body, "steam", 0.4)
		if W.phaseOf(store) == "close" then
			W.closeTask(store, player, sess, "clean_machine")
		else
			W.task(player, sess, "clean", C.CVS.perfTask * 0.5)
		end
		Cafe.refreshLights(store)
		return true
	elseif verb == "steam" then
		local i, mode = tonumber(parts[2]), parts[3]
		local p = store.items[store.slots.steam[i]]
		if not useStock(store, "milk") then
			return false, "우유가 없어요"
		end
		p.milk = "steaming"
		p.mode = mode
		p.untilT = os.clock() + C.CAFE.steamSeconds
		p.owner = player
		p.stopLoop = Props.loop(p.model and p.model.PrimaryPart or sfxAt, "steam", 0.35)
		Props.refresh(p)
		Cafe.refreshLights(store)
		return true
	elseif verb == "pour" then
		local p = store.items[store.slots.steam[tonumber(parts[2])]]
		addPart(store, h, if p.milk == "foam" then "foam" else "steamed")
		p.milk = "empty"
		p.doneAt = nil
		Props.refresh(p)
		Props.sound(sfxAt, "pour", 0.45)
		W.afterStep(player, sess, h)
		return true
	elseif verb == "burnt" then
		local p = store.items[store.slots.steam[tonumber(parts[2])]]
		p.milk = "empty"
		p.doneAt = nil
		Props.refresh(p)
		store.trash = math.min(8, store.trash + 1)
		refreshStockVisuals(store)
		return true
	elseif verb == "putpitcher" then
		local p = W.take(player, sess)
		store.slots.steam[tonumber(parts[2])] = p.id
		placeOn(store, p, "steam", tonumber(parts[2]))
		return true
	elseif verb == "discard" then
		local item = W.take(player, sess)
		if item.kind == "cup" then
			unclaim(item)
			sess.waste += 1
			store.trash = math.min(8, store.trash + 1)
			W.destroyItem(store, item)
			W.toast(player, "🗑️ 폐기했어요 · 다시 만들면 돼요", "info")
		elseif item.kind == "pitcher" then
			item.milk = "empty"
			Props.refresh(item)
			W.hold(player, sess, item)
		else
			W.destroyItem(store, item)
		end
		refreshStockVisuals(store)
		Props.sound(sfxAt, "place", 0.5)
		return true
	elseif verb == "empty" then
		store.trash = 0
		refreshStockVisuals(store)
		if W.phaseOf(store) == "close" then
			W.closeTask(store, player, sess, "empty_trash")
		else
			W.task(player, sess, "trash", C.CVS.perfTask * 0.5)
		end
		return true
	elseif verb == "putwork" then
		local i = freeSlot(store.slots.work, 3)
		local item = W.take(player, sess)
		store.slots.work[i] = item.id
		placeOn(store, item, "work", i)
		Props.sound(sfxAt, "place", 0.4)
		return true
	elseif verb == "takework" then
		local i = tonumber(parts[2])
		local item = store.items[store.slots.work[i]]
		store.slots.work[i] = nil
		if item then
			W.hold(player, sess, item)
		end
		return true
	elseif verb == "wipe" then
		W.closeTask(store, player, sess, "wipe_counter")
		return true
	elseif verb == "serve" then
		local oid = parts[2] .. (if #parts > 3 then ":" .. parts[3] else "")
		local idx = tonumber(parts[#parts])
		local o = Orders.get(oid)
		if not o or not o.items[idx] or o.items[idx].itemId then
			return false, "이미 놓은 주문이에요"
		end
		local i = freeSlot(store.slots.pickup, C.CAFE.pickupSlots)
		local cup = W.take(player, sess)
		-- a cup stickered for another order item gives that item back its claim
		if cup.orderId and (cup.orderId ~= o.id or cup.itemIndex ~= idx) then
			unclaim(cup)
		end
		cup.servedFor = o.id
		cup.servedIndex = idx
		cup.sticker = "#" .. o.number
		o.items[idx].itemId = cup.id
		o.items[idx].cupId = cup.id
		store.slots.pickup[i] = cup.id
		placeOn(store, cup, "pickup", i)
		Props.refresh(cup)
		Props.sound(sfxAt, "place", 0.5)
		if o.state == "received" then
			Orders.move(o, "preparing")
		end
		if Orders.call(o) then
			Props.sound(sfxAt, "ready", 0.8)
			W.announce(store, string.format("🔔 %d번 고객님, 주문하신 음료 나왔습니다!", o.number))
			W.calledOrder(store, o)
		else
			local left = 0
			for _, it in o.items do
				if not it.itemId then
					left += 1
				end
			end
			W.toast(player, string.format("#%d 픽업대에 놓았어요 · %d잔 남음", o.number, left), "info")
		end
		Cafe.refreshLights(store)
		return true
	elseif verb == "unserve" then
		local i = tonumber(parts[2])
		local cup = store.items[store.slots.pickup[i]]
		store.slots.pickup[i] = nil
		if cup then
			local o = cup.servedFor and Orders.get(cup.servedFor)
			if o and o.items[cup.servedIndex] and o.items[cup.servedIndex].itemId == cup.id then
				o.items[cup.servedIndex].itemId = nil
			end
			cup.servedFor = nil
			W.hold(player, sess, cup)
		end
		Cafe.refreshLights(store)
		return true
	elseif verb == "mop" then
		local id = string.sub(station, 8)
		for k, p in store.puddles do
			if p.id == id then
				if p.part then
					p.part:Destroy()
				end
				table.remove(store.puddles, k)
				break
			end
		end
		W.removeStation(store, station)
		W.task(player, sess, "mop", C.CVS.perfTask * 0.5)
		W.toast(player, "🧽 깨끗하게 닦았어요", "good")
		return true
	end
	return false, "알 수 없는 작업"
end

-------------------------------------------------------------------------------------------------
-- Tick: timers (warm-up, extraction, steaming), spills
-------------------------------------------------------------------------------------------------
function Cafe.tick(store: any, now: number)
	local changed = false
	for _, m in store.machines do
		if m.warmUntil and now >= m.warmUntil then
			m.warmUntil = nil
			m.warm = true
			changed = true
			W.storeToast(store, string.format("☕ 머신 %d 예열 완료", m.index))
		end
		for hi, hd in m.heads do
			if hd.item and hd.untilT and now >= hd.untilT then
				hd.untilT = nil
				if hd.stopLoop then
					hd.stopLoop()
					hd.stopLoop = nil
				end
				local cup = store.items[hd.item]
				if cup then
					for _ = 1, hd.shots do
						table.insert(cup.parts, "shot")
					end
					Props.refresh(cup)
				end
				Props.sound(m.body, "ready", 0.35, 1.4)
				changed = true
				if hd.owner then
					W.toast(hd.owner, string.format("☕ 머신 %d-%s 추출 완료", m.index, if hi == 1 then "A" else "B"), "info")
				end
			end
		end
	end
	for _, pid in store.pitchers do
		local p = store.items[pid]
		if p and p.milk == "steaming" and now >= (p.untilT or 0) then
			p.milk = if p.mode == "foam" then "foam" else "steamed"
			p.doneAt = now
			if p.stopLoop then
				p.stopLoop()
				p.stopLoop = nil
			end
			Props.refresh(p)
			changed = true
			if p.owner then
				W.toast(p.owner, if p.milk == "foam" then "☁️ 거품 완성 · 식기 전에 올려요" else "🥛 스팀 우유 완성 · 식기 전에 부어요", "info")
			end
		elseif p and (p.milk == "steamed" or p.milk == "foam") and p.doneAt and now - p.doneAt > 20 then
			p.milk = "burnt"
			Props.refresh(p)
			changed = true
			if p.owner then
				W.toast(p.owner, "🔥 스팀 우유를 너무 오래 둬서 탔어요 · 버리고 다시 스팀", "warn")
			end
		end
	end
	if changed then
		Cafe.refreshLights(store)
		W.dirty(store)
	end
end

-- running with an open cup that has liquid in it spills it (warned in the hint line beforehand)
function Cafe.checkSpill(store: any, player: Player, sess: any, speed: number, dt: number)
	local cup = held(store, sess)
	if not cup or cup.kind ~= "cup" or cup.lid or cup.spilled or not hasLiquid(cup) then
		sess.runT = 0
		return
	end
	if speed > C.CAFE.spillSpeed then
		sess.runT = (sess.runT or 0) + dt
		if sess.runT >= C.CAFE.spillSeconds then
			sess.runT = 0
			cup.spilled = true
			cup.parts = {}
			Props.refresh(cup)
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root then
				local pos = root.Position - Vector3.new(0, 2.9, 0)
				local id = "p" .. tostring(math.floor(os.clock() * 1000) % 100000)
				local part = Props.part(store.folder, "Puddle", Vector3.new(0.06, 2.4, 2.4), CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(120, 80, 45), { shape = Enum.PartType.Cylinder, transparency = 0.2 })
				table.insert(store.puddles, { id = id, part = part })
				W.addStation(store, { id = "puddle:" .. id, label = "쏟은 음료", pos = pos })
			end
			Props.sound(cup.model and cup.model.PrimaryPart, "error", 0.5)
			W.toast(player, "💦 뛰다가 음료를 쏟았어요! 컵은 버리고 행주로 바닥을 닦아요", "warn")
			W.dirty(store)
		end
	else
		sess.runT = 0
	end
end

-------------------------------------------------------------------------------------------------
-- Orders: judge the cups at the pick-up point; after the result clear what the customer took
-------------------------------------------------------------------------------------------------
function Cafe.judge(store: any, o: any)
	for _, it in o.items do
		local cup = it.itemId and store.items[it.itemId]
		if cup then
			local j = WS.judgeCup(cup, it.spec)
			it.accuracy = j.accuracy
			it.exact = j.exact
			it.issues = j.issues
		else
			it.accuracy = 0
			it.exact = false
		end
	end
end

function Cafe.onResolved(store: any, o: any, result: any)
	for i, id in store.slots.pickup do
		local cup = store.items[id]
		if cup and cup.servedFor == o.id then
			local it = o.items[cup.servedIndex]
			local keep = result.remake and it and it.itemId == cup.id
			if not keep then
				store.slots.pickup[i] = nil
				W.destroyItem(store, cup)
			end
		end
	end
	Cafe.refreshLights(store)
end

-- the stickered cups of a cancelled order stay usable for other orders (sticker removed)
function Cafe.onCancelled(store: any, o: any)
	for _, item in store.items do
		if item.kind == "cup" and (item.orderId == o.id or item.servedFor == o.id) then
			item.orderId = nil
			item.itemIndex = nil
			item.sticker = nil
			item.servedFor = nil
			Props.refresh(item)
		end
	end
	for i, id in store.slots.pickup do
		local cup = store.items[id]
		if cup and not cup.servedFor then
			-- leave it on the pick-up counter; the worker can pick it up again
			local _ = i
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Hints (what to do next for the focused order) and close tasks
-------------------------------------------------------------------------------------------------
function Cafe.hint(store: any, sess: any): (string?, string?)
	local h = held(store, sess)
	local phase = W.phaseOf(store)
	if h and h.kind == "supply" then
		return string.format("%s 박스 → %s에 채우기", h.text, ({ cups = "컵 선반", lids = "뚜껑", ice = "얼음통", milk = "우유 냉장고", machine = "에스프레소 머신", syrup = "시럽" })[SUPPLY_FOR[h.stock]] or "선반"), SUPPLY_FOR[h.stock]
	end
	if h and h.kind == "rag" then
		if #store.puddles > 0 then
			return "쏟은 음료 자리로 가서 닦기", "puddle:" .. store.puddles[1].id
		end
		if phase == "close" and not store.close.wipe_counter then
			return "작업대 카운터 닦기", "work"
		end
		return "행주는 창고 선반에 걸어두기", "storage"
	end
	if h and h.kind == "cup" then
		if h.spilled then
			return "쏟은 컵은 쓰레기통에 버리기", "trash"
		end
		local spec = h.spec
		if not spec then
			local o = Orders.get(sess.focus)
			spec = o and o.items[1] and o.items[1].spec
		end
		if spec then
			local step = WS.cafeNextStep(h, spec)
			if step then
				local label = WS.STEP_LABEL[step] or step
				if (step == "steamed" or step == "foam") then
					label = if step == "foam" then "스팀 피처에서 거품 스팀 → 컵에 올리기" else "스팀 피처에서 우유 스팀 → 붓기"
				end
				if not h.lid and step ~= "lid" and step ~= "pickup" and step ~= "discard" then
					label ..= " · 뚜껑 없이 뛰면 쏟아요"
				end
				return string.format("%s: %s", h.sticker or "컵", label), WS.STEP_STATION[step]
			end
		end
		return "완성된 컵은 픽업대에 · 다른 주문용이면 작업대에", "pickup"
	end
	if h and h.kind == "pitcher" then
		return "피처는 스팀 자리에 내려놓기", "steam"
	end
	-- empty hands
	for _, m in store.machines do
		if not m.locked and not m.warm and not m.warmUntil then
			return string.format("오픈 준비: 에스프레소 머신 %d 예열", m.index), m.station
		end
	end
	for _, m in store.machines do
		for hi, hd in m.heads do
			if hd.item and not hd.untilT then
				return string.format("머신 %d-%s 추출 완료 컵 가져가기", m.index, if hi == 1 then "A" else "B"), m.station
			end
		end
	end
	for _, pid in store.pitchers do
		local p = store.items[pid]
		if p and p.milk == "burnt" then
			return "탄 우유 버리고 다시 스팀", "steam"
		end
	end
	for _, o in Orders.open(store.id) do
		if not o.confirmed then
			return string.format("POS에서 #%d 주문 받기", o.number), "pos"
		end
	end
	if #store.puddles > 0 then
		return "바닥에 쏟은 음료 · 창고 선반에서 행주 들기", "storage"
	end
	if store.trash >= 7 then
		return "쓰레기통이 거의 찼어요 · 비우기", "trash"
	end
	local low = nil
	for id, def in C.CAFE.stock do
		if (store.stock[id] or 0) <= def.max * C.CAFE.lowStockShare and (id ~= "vanilla" or table.find(WS.cafeUnlocks(sess.level).menus, "vanilla_latte")) and (id ~= "caramel" or table.find(WS.cafeUnlocks(sess.level).menus, "caramel_macchiato")) then
			low = id
			break
		end
	end
	local o = Orders.get(sess.focus)
	if o and WS.isOpen(o.state) and o.state ~= "ready" then
		for _, it in o.items do
			if not it.itemId and not it.cupId then
				return string.format("#%d %s: 컵부터", o.number, WS.specText(it.spec)), "cups"
			end
		end
	end
	for _, oo in Orders.open(store.id) do
		if oo.confirmed and oo.state ~= "ready" then
			for _, it in oo.items do
				if not it.itemId and not it.cupId then
					return string.format("#%d %s: 컵부터", oo.number, WS.specText(it.spec)), "cups"
				end
			end
		end
	end
	if low then
		return string.format("%s 부족 · 창고 선반에서 보충", C.CAFE.stock[low].label), "storage"
	end
	if phase == "close" then
		for _, id in C.CAFE.closeTasks do
			if not store.close[id] then
				local where = ({ clean_machine = "machine1", wipe_counter = "storage", empty_trash = "trash", restock_cups = "storage" })[id]
				return "마감: " .. Cafe.CLOSE_LABEL[id], where
			end
		end
		return "마감 완료 · 출퇴근 단말기에서 퇴근 (정산)", "timeclock"
	end
	return nil, nil
end

Cafe.CLOSE_LABEL = {
	clean_machine = "에스프레소 머신 청소",
	wipe_counter = "작업대 카운터 닦기 (행주)",
	empty_trash = "쓰레기통 비우기",
	restock_cups = "컵 채워 두기 (다음 근무자용)",
}

function Cafe.closeTasks(store: any): { any }
	local out = {}
	for _, id in C.CAFE.closeTasks do
		table.insert(out, { id = id, label = Cafe.CLOSE_LABEL[id], done = store.close[id] == true })
	end
	return out
end

function Cafe.stockView(store: any): { any }
	local out = {}
	for _, id in { "cup_ice", "cup_hot", "lid", "ice", "milk", "beans", "vanilla", "caramel" } do
		local def = C.CAFE.stock[id]
		table.insert(out, { id = id, label = def.label, n = store.stock[id], max = def.max, low = store.stock[id] <= def.max * C.CAFE.lowStockShare })
	end
	return out
end

-- describe a held item for the client hand card
function Cafe.itemView(store: any, item: any): any
	if item.kind == "cup" then
		local parts = {}
		local counts = {}
		for _, id in item.parts do
			counts[id] = (counts[id] or 0) + 1
		end
		for _, id in { "vanilla", "ice", "shot", "water", "hotwater", "milk", "steamed", "foam", "caramel" } do
			if counts[id] then
				local ing = WS.INGREDIENTS[id]
				table.insert(parts, ing.icon .. (if counts[id] > 1 then "×" .. counts[id] else ""))
			end
		end
		local spec = item.spec
		local judge = spec and WS.judgeCup(item, spec) or nil
		local problems = {}
		if judge then
			for _, iss in judge.issues do
				if iss.severity ~= "todo" then
					table.insert(problems, iss.text)
				end
			end
		end
		return {
			kind = "cup",
			title = cupText(item),
			parts = parts,
			lid = item.lid,
			spilled = item.spilled,
			target = spec and WS.specText(spec) or nil,
			steps = spec and WS.cafeSteps(spec) or nil,
			done = item.parts,
			problems = problems,
			fixable = judge and judge.fixable,
		}
	elseif item.kind == "supply" then
		return { kind = "supply", title = item.text .. " 보충 박스" }
	elseif item.kind == "rag" then
		return { kind = "rag", title = "행주" }
	elseif item.kind == "pitcher" then
		return { kind = "pitcher", title = "스팀 피처" }
	end
	return { kind = item.kind, title = item.kind }
end

-- a test customer's order (no NPC provider)
function Cafe.genOrder(store: any, rand: (number) -> number, level: number, group: boolean): { any }
	local n = if group then 3 + rand(2) - 1 else (if rand(4) == 1 and level >= 2 then 2 else 1)
	local items = {}
	for _ = 1, n do
		table.insert(items, WS.genCafeItem(rand, level))
	end
	return items
end

-- 주문 변경: a different option for an item still being made
function Cafe.changeSpec(spec: any, rand: (number) -> number, level: number): (any?, string?)
	local u = WS.cafeUnlocks(level)
	local new = table.clone(spec)
	local choices = {}
	if u.options.size then
		table.insert(choices, "size")
	end
	if u.options.shot and spec.extraShot == 0 then
		table.insert(choices, "shot")
	end
	if #WS.CAFE_MENU[spec.menu].temps > 1 and u.options.temp then
		table.insert(choices, "temp")
	end
	if #choices == 0 then
		if spec.menu == "americano" then
			new.menu = "latte"
			return new, "아메리카노 말고 라떼로 바꿔도 될까요?"
		end
		return nil, nil
	end
	local c = choices[rand(#choices)]
	if c == "size" then
		new.size = if spec.size == "tall" then "grande" else "tall"
		return new, string.format("사이즈 %s(으)로 바꿔 주세요!", WS.SIZE_LABEL[new.size])
	elseif c == "shot" then
		new.extraShot = 1
		return new, "샷 하나 추가해 주실 수 있어요?"
	else
		new.temp = if spec.temp == "ice" then "hot" else "ice"
		return new, string.format("%s(으)로 바꿔 주세요", if new.temp == "ice" then "아이스" else "따뜻한 걸")
	end
end

return Cafe
