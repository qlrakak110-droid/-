-- Interact: furniture & fixtures that really do something, plus the HOLD system (carried food / drinks).
--   bed (눕기 / 잠자기) · seat (앉기) · tv (켜기 · 채널) · fridge (꺼내 먹기) · microwave (데우기) · shower ·
--   bathtub · toilet (+ flush) · sink · washer (세탁 30초) · lamp · switch (방 조명) · aircon · fan ·
--   wardrobe (문 열기) · pc (미니게임) · wallpad (조명 · 엘리베이터 호출 · 인테리어) · massage · cook ·
--   exercise · water (온수: 컵라면) · dryer · vending
-- Rights: fixtures in a home follow Housing.rightsOf (owner / guest / open-house viewer); hotel rooms
-- follow the hotel booking; shop / Public fixtures are for everyone.
-- State lives in attributes on the fixture Model (On, Channel, Open, Busy, Fill ...) that clients turn
-- into screens, water, spinning drums, sounds and light.
--
-- HOLD: one carried item per player (attributes GwB_Hold / GwB_HoldLabel / GwB_HoldState + a small
-- model welded to the right hand). Interact.give(p, item) / Interact.drop(p) / "hold.use" (먹기 / 버리기).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = require(ReplicatedStorage:WaitForChild("GwangalliBuildingsShared"))
local Config = Shared.Config
local Kit = Shared.Kit
local Furniture = Shared.Furniture
local Menus = Shared.Menus

local Interact = {}

local Registry: any
local services: any

type Fx = { model: Instance, kind: string, prompts: { ProximityPrompt }, busyUntil: number?, floorKey: string? }
local fixtures: { [Instance]: Fx } = {}
local holds: { [Player]: any } = {}
local lying: { [Player]: Instance } = {}

-------------------------------------------------------------------------------------------------
-- rights
-------------------------------------------------------------------------------------------------
local function rightsOk(p: Player, m: Instance, need: string): (boolean, string?)
	if m:GetAttribute("Public") == true or m:GetAttribute("ShopId") ~= nil then
		return true, nil
	end
	local unitId = m:GetAttribute("UnitId")
	if not unitId then
		return true, nil
	end
	local u = Registry.unit(unitId)
	if u and Shared.Homes.TEMPLATES[u.template] and Shared.Homes.TEMPLATES[u.template].hotel then
		local S = services.ShopFlows
		if S and S.canEnterRoom(p, unitId) then
			return true, nil
		end
		return false, "투숙객만 사용할 수 있어요"
	end
	local H = services.Housing
	if not H then
		return true, nil
	end
	local role = H.rightsOf(p, unitId)
	if need == "anyone" then
		return true, nil
	elseif need == "owner" then
		if role == "owner" or role == "guest" then
			return true, nil
		end
		return false, "집주인만 사용할 수 있어요"
	end
	if role then
		return true, nil
	end
	return false, "이 집에 초대받지 않았어요"
end

-------------------------------------------------------------------------------------------------
-- HOLD (carried items)
-------------------------------------------------------------------------------------------------
local function handOf(c: Model): BasePart?
	return (c:FindFirstChild("RightHand") or c:FindFirstChild("Right Arm") or c:FindFirstChild("HumanoidRootPart")) :: any
end

local function holdModel(item: any): Model
	local m = Instance.new("Model")
	m.Name = "GwB_Held"
	local col = item.color or { 240, 240, 236 }
	local kind = item.kind or "food"
	local main: BasePart
	if kind == "drink" or kind == "cup" then
		main = Kit.part(m, CFrame.new(), Vector3.new(0.5, 0.9, 0.5), "Glass", { 240, 240, 246 }, { shape = "cyl", collide = false, tr = 0.3, name = "Cup" })
		main.CFrame = CFrame.Angles(0, 0, math.rad(90))
		local liquid = Kit.part(m, CFrame.new(0, -0.08, 0) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(0.7, 0.44, 0.44), "SmoothPlastic", col, { shape = "cyl", collide = false, name = "Liquid" })
		local _ = liquid
		Kit.part(m, CFrame.new(0.1, 0.55, 0), Vector3.new(0.06, 0.5, 0.06), "SmoothPlastic", { 250, 250, 250 }, { collide = false, name = "Straw" })
	elseif kind == "tray" then
		main = Kit.part(m, CFrame.new(), Vector3.new(2.2, 0.12, 1.6), "SmoothPlastic", { 120, 86, 60 }, { collide = false, name = "Tray" })
		Kit.part(m, CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(0.5, 1.0, 1.0), "SmoothPlastic", { 40, 30, 26 }, { shape = "cyl", collide = false, name = "Ttukbaegi" })
		Kit.part(m, CFrame.new(0, 0.52, 0) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(0.05, 0.85, 0.85), "SmoothPlastic", col, { shape = "cyl", collide = false, name = "Soup" })
		Kit.part(m, CFrame.new(0.75, 0.15, 0.4), Vector3.new(0.5, 0.15, 0.4), "SmoothPlastic", { 220, 90, 60 }, { collide = false, name = "Kkakdugi" })
	elseif kind == "noodle" then
		main = Kit.part(m, CFrame.new() * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(0.8, 0.9, 0.9), "SmoothPlastic", col, { shape = "cyl", collide = false, name = "Cup" })
	elseif kind == "basket" then
		main = Kit.part(m, CFrame.new(), Vector3.new(1.6, 0.9, 1.0), "SmoothPlastic", { 40, 110, 200 }, { collide = false, name = "Basket", tr = 0.2 })
	elseif kind == "mic" then
		main = Kit.part(m, CFrame.new(), Vector3.new(0.25, 1.0, 0.25), "Metal", { 30, 30, 30 }, { collide = false, name = "Mic" })
		Kit.part(m, CFrame.new(0, 0.6, 0), Vector3.new(0.4, 0.4, 0.4), "Metal", { 160, 160, 164 }, { shape = "ball", collide = false, name = "Head" })
	elseif kind == "cue" then
		main = Kit.part(m, CFrame.new(0, 0, 0), Vector3.new(0.12, 0.12, 6.0), "Wood", { 220, 190, 140 }, { collide = false, name = "Cue" })
	elseif kind == "card" then
		main = Kit.part(m, CFrame.new(), Vector3.new(0.6, 0.04, 0.4), "SmoothPlastic", { 30, 34, 50 }, { collide = false, name = "KeyCard" })
	else
		main = Kit.part(m, CFrame.new(), Vector3.new(0.9, 0.5, 0.7), "SmoothPlastic", col, { collide = false, name = "Food" })
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.Massless = true
			d.CanQuery = false
			if d ~= main then
				local w = Instance.new("WeldConstraint")
				w.Part0 = main
				w.Part1 = d
				w.Parent = d
			end
		end
	end
	m.PrimaryPart = main
	return m
end

function Interact.give(p: Player, item: any)
	Interact.drop(p, true)
	local c = p.Character
	if not c then
		return
	end
	holds[p] = item
	p:SetAttribute("GwB_Hold", item.id)
	p:SetAttribute("GwB_HoldLabel", item.label or item.id)
	p:SetAttribute("GwB_HoldState", item.state or "ready")
	p:SetAttribute("GwB_HoldEat", item.edible ~= false)
	local hand = handOf(c)
	if hand then
		local m = holdModel(item)
		local main = m.PrimaryPart :: BasePart
		local grip = if item.kind == "tray" then CFrame.new(0, -0.2, -1.0) elseif item.kind == "cue" then CFrame.new(0, -0.6, -1.4) * CFrame.Angles(math.rad(-20), 0, 0) else CFrame.new(0, -0.9, -0.3)
		main.CFrame = hand.CFrame * grip
		m.Parent = c
		local w = Instance.new("Weld")
		w.Part0 = hand
		w.Part1 = main
		w.C0 = grip
		w.Parent = main
	end
end

function Interact.held(p: Player): any
	return holds[p]
end

function Interact.setState(p: Player, state: string, label: string?)
	local it = holds[p]
	if it then
		it.state = state
		p:SetAttribute("GwB_HoldState", state)
		if label then
			it.label = label
			p:SetAttribute("GwB_HoldLabel", label)
		end
	end
end

function Interact.drop(p: Player, silent: boolean?)
	holds[p] = nil
	p:SetAttribute("GwB_Hold", nil)
	p:SetAttribute("GwB_HoldLabel", nil)
	p:SetAttribute("GwB_HoldState", nil)
	local c = p.Character
	if c then
		for _, ch in c:GetChildren() do
			if ch.Name == "GwB_Held" then
				ch:Destroy()
			end
		end
	end
end

-- eat / drink the held item (effects through Needs; stats through Economy)
function Interact.consume(p: Player): boolean
	local it = holds[p]
	if not it then
		return false
	end
	if it.state == "raw" then
		Registry.toast(p, if it.heat then "먼저 전자레인지에 데워야 해요" else "아직 먹을 수 없어요", "warn")
		return false
	elseif it.state == "wait" then
		Registry.toast(p, "조금만 기다려요… 면이 익는 중", "warn")
		return false
	elseif it.edible == false then
		return false
	end
	Interact.drop(p)
	Registry.fire(p, "fx", { kind = "eat", label = it.label })
	if services.Needs then
		services.Needs.apply(p, it.effect, it.stats, it.label)
	end
	if it.onEat then
		task.spawn(it.onEat, p)
	end
	return true
end

-------------------------------------------------------------------------------------------------
-- poses (lying on a bed / sunbed)
-------------------------------------------------------------------------------------------------
local function lie(p: Player, m: Instance)
	local spot = m:FindFirstChild("LieSpot", true)
	if not spot or not spot:IsA("BasePart") then
		return
	end
	lying[p] = m
	p:SetAttribute("GwB_Lying", true)
	Registry.fire(p, "pose", { mode = "lie", cf = spot.CFrame })
end

local function getUp(p: Player)
	if lying[p] then
		lying[p] = nil
		p:SetAttribute("GwB_Lying", nil)
		Registry.fire(p, "pose", { mode = "none" })
	end
end

local function sitOn(p: Player, m: Instance, index: number?): boolean
	local _, _, hum = Registry.char(p)
	if not hum then
		return false
	end
	local best: Seat? = nil
	local bestD = math.huge
	local pos = Registry.pos(p) :: Vector3
	for _, s in m:GetDescendants() do
		if s:IsA("Seat") and s.Occupant == nil and (index == nil or s:GetAttribute("Index") == index) then
			local d = (s.Position - pos).Magnitude
			if d < bestD then
				best, bestD = s, d
			end
		end
	end
	if not best then
		Registry.toast(p, "빈 자리가 없어요", "warn")
		return false
	end
	local seat = best :: Seat
	seat.Disabled = false
	seat:Sit(hum)
	local conn: RBXScriptConnection? = nil
	conn = seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if seat.Occupant == nil then
			seat.Disabled = true
			if conn then
				conn:Disconnect()
			end
		end
	end)
	return true
end
Interact.sitOn = sitOn

-------------------------------------------------------------------------------------------------
-- lights of rooms (switches, wallpad)
-------------------------------------------------------------------------------------------------
function Interact.setRoomLights(roomIds: { string }, on: boolean)
	local set = {}
	for _, r in roomIds do
		set[r] = true
	end
	for _, l in CollectionService:GetTagged("GwB_Light") do
		if l:IsA("Light") and set[l:GetAttribute("RoomId") :: string] then
			l.Enabled = on
			l:SetAttribute("On", on)
		end
	end
	for _, lamp in CollectionService:GetTagged("GwB_Lamp") do
		if lamp:IsA("BasePart") and set[lamp:GetAttribute("RoomId") :: string] then
			lamp:SetAttribute("On", on)
			if on then
				lamp.Material = Enum.Material.Neon
				local c = lamp:GetAttribute("LampOn")
				if typeof(c) == "Color3" then
					lamp.Color = c
				end
			else
				lamp.Material = Enum.Material.SmoothPlastic
				local c = lamp:GetAttribute("LampOff")
				if typeof(c) == "Color3" then
					lamp.Color = c
				end
			end
		end
	end
end

local function roomLightsOn(roomId: string): boolean
	for _, l in CollectionService:GetTagged("GwB_Light") do
		if l:IsA("Light") and l:GetAttribute("RoomId") == roomId then
			return l.Enabled
		end
	end
	return false
end

-------------------------------------------------------------------------------------------------
-- kinds
-------------------------------------------------------------------------------------------------
local function busy(fx: Fx, seconds: number)
	fx.busyUntil = os.clock() + seconds
	fx.model:SetAttribute("Busy", Registry.now() + seconds)
end

local function setActive(m: Instance, on: boolean)
	m:SetAttribute("On", on)
	for _, d in m:GetDescendants() do
		if d:IsA("Attachment") and d:GetAttribute("SoundKey") then
			d:SetAttribute("Active", on)
		end
		if d:IsA("BasePart") and d:GetAttribute("Rpm") ~= nil and d:GetAttribute("BaseRpm") == nil then
			d:SetAttribute("BaseRpm", d:GetAttribute("Rpm"))
		end
	end
end

local function spin(m: Instance, rpm: number)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and CollectionService:HasTag(d, "GwB_Spin") then
			d:SetAttribute("Rpm", rpm)
		end
	end
end

local ACTIONS: { [string]: { any } } = {}

-- bed
ACTIONS.bed = {
	{
		text = "눕기",
		run = function(p, fx)
			if lying[p] == fx.model then
				getUp(p)
			else
				lie(p, fx.model)
			end
		end,
	},
	{
		text = "잠자기",
		hold = 1.2,
		run = function(p, fx)
			lie(p, fx.model)
			Registry.fire(p, "fx", { kind = "sleep", seconds = 4 })
			task.delay(4, function()
				if services.Needs then
					services.Needs.set(p, "Energy", 100)
					services.Needs.apply(p, { Fun = 5 }, { stamina = 1, happiness = 1 }, "푹 잤어요")
				end
				getUp(p)
			end)
		end,
	},
}

ACTIONS.seat = {
	{
		text = "앉기",
		run = function(p, fx)
			sitOn(p, fx.model, nil)
		end,
	},
}

ACTIONS.tv = {
	{
		text = "TV 켜기 / 끄기",
		run = function(p, fx)
			local on = fx.model:GetAttribute("On") ~= true
			setActive(fx.model, on)
			if on then
				fx.model:SetAttribute("Channel", fx.model:GetAttribute("Channel") or 1)
				if services.Needs then
					services.Needs.apply(p, { Fun = 3 })
				end
			end
		end,
	},
	{
		text = "채널 변경",
		run = function(p, fx)
			if fx.model:GetAttribute("On") ~= true then
				setActive(fx.model, true)
			end
			fx.model:SetAttribute("Channel", ((tonumber(fx.model:GetAttribute("Channel")) or 1) % 6) + 1)
		end,
	},
}

ACTIONS.fridge = {
	{
		text = "냉장고 열기",
		run = function(p, fx)
			fx.model:SetAttribute("Open", true)
			task.delay(6, function()
				fx.model:SetAttribute("Open", false)
			end)
			if fx.model:GetAttribute("ShopId") then
				return
			end
			Registry.fire(p, "menu", { title = "냉장고", kind = "fridge", fixture = fx.model, items = Menus.FRIDGE })
		end,
	},
}

ACTIONS.microwave = {
	{
		text = "데우기",
		run = function(p, fx)
			local it = holds[p]
			if fx.busyUntil and os.clock() < fx.busyUntil then
				Registry.toast(p, "다른 음식을 데우는 중이에요", "warn")
				return
			end
			if not it or not it.heat or it.state ~= "raw" then
				Registry.toast(p, "데울 음식이 없어요 (편의점 도시락 · 냉장고 반찬)", "warn")
				return
			end
			local secs = Config.CVS_MICROWAVE
			Interact.setState(p, "wait", it.label .. " (데우는 중)")
			busy(fx, secs)
			setActive(fx.model, true)
			spin(fx.model, 30)
			Registry.fire(p, "timer", { label = "전자레인지", seconds = secs })
			task.delay(secs, function()
				setActive(fx.model, false)
				spin(fx.model, 0)
				fx.model:SetAttribute("Ding", Registry.now())
				if holds[p] == it then
					Interact.setState(p, "ready", "따끈한 " .. (it.baseLabel or it.label))
					Registry.toast(p, "띵! 다 데워졌어요. 먹기 버튼을 눌러요", "ok")
				end
			end)
		end,
	},
}

ACTIONS.water = {
	{
		text = "온수 받기",
		run = function(p, fx)
			local it = holds[p]
			if not it or not it.noodle or it.state ~= "raw" then
				Registry.toast(p, "컵라면을 들고 와요 (편의점에서 결제)", "warn")
				return
			end
			local secs = Config.CVS_NOODLE_WAIT
			Interact.setState(p, "wait", it.label .. " (익는 중)")
			fx.model:SetAttribute("Pour", Registry.now())
			Registry.fire(p, "timer", { label = "컵라면 3분", seconds = secs })
			task.delay(secs, function()
				if holds[p] == it then
					Interact.setState(p, "ready", "다 익은 " .. (it.baseLabel or it.label))
					Registry.toast(p, "🍜 면이 다 익었어요! 앉아서 먹어요", "ok")
				end
			end)
		end,
	},
}

local function timedUse(seconds: number, effect: any, stats: any?, label: string, rpm: number?)
	return function(p: Player, fx: Fx)
		if fx.busyUntil and os.clock() < fx.busyUntil then
			Registry.toast(p, "사용 중이에요", "warn")
			return
		end
		busy(fx, seconds)
		setActive(fx.model, true)
		if rpm then
			spin(fx.model, rpm)
		end
		Registry.fire(p, "timer", { label = label, seconds = seconds })
		task.delay(seconds, function()
			setActive(fx.model, false)
			if rpm then
				spin(fx.model, 0)
			end
			fx.model:SetAttribute("Done", Registry.now())
			if p.Parent and services.Needs then
				services.Needs.apply(p, effect, stats, label)
			end
		end)
	end
end

ACTIONS.shower = { { text = "샤워하기", run = timedUse(10, { Hygiene = 45, Energy = 5 }, nil, "샤워") } }
ACTIONS.sink = { { text = "손 씻기", run = timedUse(3, { Hygiene = 6 }, nil, "손 씻기") } }
ACTIONS.dryer = { { text = "핸드 드라이어", run = timedUse(3, nil, nil, "건조") } }
ACTIONS.washer = { { text = "세탁 시작", run = timedUse(30, { Hygiene = 10 }, { appearance = 0.2 }, "세탁", 160) } }
ACTIONS.cook = {
	{
		text = "요리하기",
		run = function(p, fx)
			if fx.busyUntil and os.clock() < fx.busyUntil then
				Registry.toast(p, "요리 중이에요", "warn")
				return
			end
			busy(fx, 12)
			setActive(fx.model, true)
			Registry.fire(p, "timer", { label = "집밥 요리", seconds = 12 })
			task.delay(12, function()
				setActive(fx.model, false)
				if p.Parent then
					Interact.give(p, { id = "homemeal", label = "김치찌개 정식", kind = "tray", color = { 220, 80, 50 }, effect = { Satiety = 55, Energy = 8 }, stats = { stamina = 1, happiness = 0.5 } })
					Registry.toast(p, "🍲 김치찌개 완성! 식탁에 앉아서 먹어요", "ok")
				end
			end)
		end,
	},
}
ACTIONS.bathtub = {
	{
		text = "반신욕",
		run = function(p, fx)
			fx.model:SetAttribute("Fill", 1)
			sitOn(p, fx.model, nil)
			timedUse(12, { Hygiene = 50, Energy = 12, Fun = 6 }, { happiness = 1 }, "반신욕")(p, fx)
			task.delay(30, function()
				fx.model:SetAttribute("Fill", 0)
			end)
		end,
	},
}
ACTIONS.toilet = {
	{
		text = "사용하기",
		run = function(p, fx)
			if not sitOn(p, fx.model, nil) and not fx.model:FindFirstChildWhichIsA("Seat", true) then
				-- urinals have no seat
			end
			task.delay(4, function()
				fx.model:SetAttribute("Flush", Registry.now())
				local _, _, hum = Registry.char(p)
				if hum and hum.Sit then
					hum.Sit = false
				end
				if services.Needs then
					services.Needs.apply(p, { Hygiene = -2, Fun = 1 })
				end
			end)
		end,
	},
}
local function toggle(attr: string, rpm: number?)
	return function(p: Player, fx: Fx)
		local on = fx.model:GetAttribute(attr) ~= true
		if attr == "On" then
			setActive(fx.model, on)
		else
			fx.model:SetAttribute(attr, on)
		end
		if rpm then
			spin(fx.model, if on then rpm else 0)
		end
		-- lamps: their own lights
		for _, d in fx.model:GetDescendants() do
			if d:IsA("Light") then
				d.Enabled = on
			elseif d:IsA("BasePart") and CollectionService:HasTag(d, "GwB_Lamp") then
				d.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
			end
		end
	end
end
ACTIONS.lamp = { { text = "스위치", run = toggle("On") } }
ACTIONS.aircon = { { text = "에어컨 켜기 / 끄기", run = toggle("On") } }
ACTIONS.fan = { { text = "선풍기 켜기 / 끄기", run = toggle("On", 600) } }
ACTIONS.wardrobe = { { text = "옷장 열기 / 닫기", run = toggle("Open") } }
ACTIONS.switch = {
	{
		text = "불 켜기 / 끄기",
		run = function(p, fx)
			local ids = Shared.Util.split(fx.model:GetAttribute("RoomIds") :: string, ",")
			if #ids == 0 then
				return
			end
			local on = not roomLightsOn(ids[1])
			Interact.setRoomLights(ids, on)
			fx.model:SetAttribute("On", on)
			fx.model:SetAttribute("Click", Registry.now())
		end,
	},
}
ACTIONS.massage = {
	{
		text = "안마 받기",
		run = function(p, fx)
			sitOn(p, fx.model, nil)
			timedUse(15, { Energy = 25, Fun = 8 }, { happiness = 0.5 }, "안마")(p, fx)
		end,
	},
}
ACTIONS.exercise = { { text = "달리기 30초", run = timedUse(30, { Energy = -15, Hygiene = -10, Fun = 6 }, { strength = 0.5, stamina = 0.5 }, "러닝머신") } }
ACTIONS.pc = {
	{
		text = "컴퓨터 하기",
		run = function(p, fx)
			sitOn(p, fx.model, nil)
			setActive(fx.model, true)
			Registry.fire(p, "pc.open", { fixture = fx.model, free = true })
		end,
	},
}
ACTIONS.wallpad = {
	{
		text = "월패드",
		run = function(p, fx)
			local unitId = fx.model:GetAttribute("UnitId")
			local u = Registry.unit(unitId)
			Registry.fire(p, "wallpad", { unitId = unitId, label = u and u.label, building = u and u.rec.name, floor = u and u.floor })
		end,
	},
}
ACTIONS.vending = {
	{
		text = "음료 뽑기 (1,200원)",
		run = function(p, fx)
			local E = services.Economy
			if E then
				local ok, msg = E.spend(p, 1200, "자판기 음료")
				if not ok then
					Registry.toast(p, msg or "잔액 부족", "warn")
					return
				end
			end
			fx.model:SetAttribute("Vend", Registry.now())
			local DR = { { "콜라", { 180, 20, 30 } }, { "사이다", { 120, 220, 120 } }, { "이온음료", { 60, 130, 230 } }, { "커피", { 120, 80, 50 } } }
			local pick = DR[math.random(1, #DR)]
			Interact.give(p, { id = "vend_drink", label = pick[1], kind = "drink", color = pick[2], effect = { Energy = 8, Fun = 2 } })
		end,
	},
}

-------------------------------------------------------------------------------------------------
-- registration
-------------------------------------------------------------------------------------------------
local function register(m: Instance)
	if fixtures[m] or not (m:IsA("Model") or m:IsA("BasePart")) then
		return
	end
	local kind = m:GetAttribute("Kind") :: string?
	if not kind or not ACTIONS[kind] then
		return
	end
	-- shop flows own the shop-specific fixtures (microwave / water in a convenience store go through
	-- the hold system and work the same, so they stay here)
	local anchor: BasePart? = if m:IsA("BasePart") then m else ((m :: Model).PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true))
	if not anchor then
		return
	end
	local fx: Fx = { model = m, kind = kind, prompts = {} }
	fixtures[m] = fx
	local def = Furniture.KINDS[kind] or { rights = "guest" }
	for i, a in ACTIONS[kind] do
		local pr = Kit.prompt(anchor, a.text, (m:GetAttribute("Label") :: string?) or "", {
			dist = if kind == "switch" then 5 else 6.5,
			hold = a.hold or 0,
			name = "FxPrompt" .. i,
			key = if i == 1 then Enum.KeyCode.E else Enum.KeyCode.F,
		})
		pr.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
		pr.Triggered:Connect(function(p: Player)
			if not m:IsDescendantOf(workspace) or not Registry.near(p, anchor, 12) then
				return
			end
			local ok, msg = rightsOk(p, m, def.rights or "guest")
			if not ok then
				Registry.toast(p, msg or "사용할 수 없어요", "warn")
				return
			end
			local okRun, err = pcall(a.run, p, fx)
			if not okRun then
				warn("[GwangalliBuildings] fixture " .. kind .. ": " .. tostring(err))
			end
		end)
		table.insert(fx.prompts, pr)
	end
end

function Interact.busyFloor(rec: any, fl: any): boolean
	local now = os.clock()
	for m, fx in fixtures do
		if fx.busyUntil and fx.busyUntil > now then
			local unitId = m:GetAttribute("UnitId")
			local u = Registry.unit(unitId)
			if u and u.rec == rec and u.fl == fl then
				return true
			end
		end
	end
	return false
end

function Interact.init(ctx: any)
	Registry = ctx.Registry
	services = ctx.services
	CollectionService:GetInstanceAddedSignal("GwB_Fixture"):Connect(register)
	CollectionService:GetInstanceRemovedSignal("GwB_Fixture"):Connect(function(m)
		fixtures[m] = nil
	end)
	for _, m in CollectionService:GetTagged("GwB_Fixture") do
		register(m)
	end
	Registry.on("hold.use", function(p: Player, d: any)
		if d.action == "eat" then
			return { ok = Interact.consume(p) }
		elseif d.action == "drop" then
			Interact.drop(p)
			return { ok = true }
		end
		return { ok = false }
	end)
	Registry.on("pose.end", function(p: Player)
		getUp(p)
		return { ok = true }
	end)
	Registry.on("fx.use", function(p: Player, d: any)
		-- fridge menu pick: { fixture, item }
		local m = d.fixture
		if typeof(m) ~= "Instance" or not fixtures[m] or not Registry.near(p, m :: Instance, 14) then
			return { ok = false }
		end
		local fx = fixtures[m]
		if fx.kind == "fridge" then
			local it = Menus.find(Menus.FRIDGE, d.item)
			if not it then
				return { ok = false }
			end
			local ok, msg = rightsOk(p, m, "guest")
			if not ok then
				return { ok = false, msg = msg }
			end
			Interact.give(p, { id = it.id, label = it.name, baseLabel = it.name, kind = if it.heat then "food" else "drink", heat = it.heat, state = if it.heat then "raw" else "ready", effect = it.effect, color = { 240, 220, 200 } })
			return { ok = true }
		elseif fx.kind == "pc" then
			if services.Needs then
				services.Needs.apply(p, { Fun = 12, Energy = -3 }, { happiness = 0.3 }, "게임 한 판")
			end
			return { ok = true }
		end
		return { ok = false }
	end)
	Registry.on("wallpad.action", function(p: Player, d: any)
		local unitId = d.unitId
		local u = Registry.unit(unitId)
		if not u or not services.Housing or services.Housing.rightsOf(p, unitId) ~= "owner" then
			return { ok = false, msg = "집주인만 사용할 수 있어요" }
		end
		if not Registry.near(p, Shared.Util and u.model and u.model:GetPivot().Position or Vector3.zero, 80) then
			return { ok = false, msg = "집 안에서 사용해요" }
		end
		if d.action == "lightsOn" or d.action == "lightsOff" then
			local ids = {}
			for _, r in u.layout.rooms do
				table.insert(ids, u.id .. ":" .. r.id)
			end
			Interact.setRoomLights(ids, d.action == "lightsOn")
			return { ok = true }
		elseif d.action == "elevator" then
			local ok = services.Elevators and services.Elevators.callFloor(u.rec, u.floor, "down")
			return { ok = ok == true, msg = if ok then "🛗 엘리베이터를 불렀어요" else "이 건물에는 엘리베이터가 없어요" }
		end
		return { ok = false }
	end)
	Players.PlayerRemoving:Connect(function(p)
		holds[p] = nil
		lying[p] = nil
	end)
end

function Interact.start()
	-- characters respawning lose their held item
	for _, p in Players:GetPlayers() do
		p.CharacterAdded:Connect(function()
			Interact.drop(p, true)
			getUp(p)
		end)
	end
	Players.PlayerAdded:Connect(function(p)
		p.CharacterAdded:Connect(function()
			Interact.drop(p, true)
			getUp(p)
		end)
	end)
end

return Interact
