-- GwangalliGameplay/Venues: everything the server does with tagged world parts.
--   * GymStation (StationType): ProximityPrompt (hold ~1 s) -> a gym SESSION (venues_detail): the
--     character is held at the station (anchored root, UsePoint pose) for up to 5 sets; each set
--     = G.GYM[kind].duration s -> stat gains (G.gymGain x form bonus), the client animates the rep
--     loop + compact HUD (GwangalliVenues/Gym); same prompt / 그만 button ends it; cooldown per
--     station type afterwards, one user per station; "inbody" shows the stats
--   * venue interiors (venues_detail): VenueLife (remotes VenueRequest / VenueEvent, acts, food
--     orders, spots, boards), VenueKaraoke (노래방 rooms), VenuePC (PC방 seats + racer board); gym
--     spots here: 정수기 (gym_water), 락커 (gym_locker), 트레이너 루틴 퀘스트 (gym_trainer)
--   * ShopCounter (ShopId) / SalonChair: a small kiosk made of two prompts ("<item> 구매" and
--     "다음 상품 ▶") plus a menu board above counters; purchases also work from the phone
--     (PhoneAction "buy") within reach. Salon chairs each start on a different style.
--   * Destination-bound items (G.ITEMS[..].nearDest): a kiosk on that Destination part
--   * quest job prompts (interact steps with `prompt`, e.g. GS25 shelf stocking)
--   * ElevatorButton (Floor, Target = "ElevatorStop_<n>" in the same building): fade + safe teleport
--   * looks: outfits recolour the character through its HumanoidDescription (shirt/pants templates
--     cleared, body colours set; a welded jacket shell for jackets), hair styles are welded
--     ellipsoid parts on the head (avatar hair accessories removed). No asset ids anywhere.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Venues = {}

local ctx: any
local G: any
local Util: any
local Profiles: any

local KEYS = { Enum.KeyCode.E, Enum.KeyCode.R, Enum.KeyCode.F, Enum.KeyCode.G, Enum.KeyCode.T, Enum.KeyCode.V }
local PADS = { Enum.KeyCode.ButtonX, Enum.KeyCode.ButtonY, Enum.KeyCode.ButtonB, Enum.KeyCode.ButtonA, Enum.KeyCode.DPadUp, Enum.KeyCode.DPadDown }

local function newPrompt(parent: Instance, action: string, object: string, hold: number, dist: number): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = hold
	p.MaxActivationDistance = dist
	p.RequiresLineOfSight = false
	p.ClickablePrompt = true
	p.Parent = parent
	return p
end

-------------------------------------------------------------------------------------------------
-- Purchases
-------------------------------------------------------------------------------------------------
local shopParts: { [BasePart]: string } = {} -- counters / chairs -> ShopId
local gymCd: { [Player]: { [string]: number } } = {}
local hintShown: { [Player]: { [string]: boolean } } = {}

local function within(pos: Vector3, part: BasePart, reach: number): boolean
	local extra = math.min(10, math.max(part.Size.X, part.Size.Z) / 2)
	return (part.Position - pos).Magnitude <= reach + extra
end

local function nearShop(player: Player, shopId: string): boolean
	local pos = Util.rootPosition(player)
	if not pos then
		return false
	end
	for part, sid in shopParts do
		if sid == shopId and part.Parent and within(pos, part, G.SHOP_REACH) then
			return true
		end
	end
	return false
end

local function nearDest(player: Player, name: string): boolean
	local pos = Util.rootPosition(player)
	local part = ctx.dest(name)
	return pos ~= nil and part ~= nil and (part.Position - pos).Magnitude <= G.NEAR_DEST_RADIUS
end

local applyLook: (Player) -> ()

local function applyConsumable(player: Player, d: any, id: string, it: any): string
	d.inventory[id] = math.min(9999, (d.inventory[id] or 0) + 1)
	local eff = it.effect or {}
	local notes = {}
	local today = G.dayKey(os.time())
	if d.daily.day ~= today then
		d.daily.day = today
		d.daily.counts = {}
	end
	if eff.stats then
		local n = d.daily.counts[id] or 0
		if not it.dailyStatLimit or n < it.dailyStatLimit then
			d.daily.counts[id] = n + 1
			local applied = ctx.addStats(player, eff.stats, nil, true)
			local s = G.describeStats(applied)
			if s ~= "" then
				table.insert(notes, s)
			end
		else
			table.insert(notes, "오늘은 능력치 효과를 더 받을 수 없어요")
		end
	end
	if eff.buff and G.BUFFS[eff.buff] then
		local b = d.buffs[eff.buff] or { untilT = 0, sets = 0 }
		if eff.buffSets then
			b.sets = math.min(9, (b.sets or 0) + eff.buffSets)
		end
		if eff.buffSeconds then
			b.untilT = math.min(os.time() + 1800, math.max(b.untilT or 0, os.time()) + eff.buffSeconds)
		end
		d.buffs[eff.buff] = b
		table.insert(notes, G.BUFFS[eff.buff].name .. ": " .. G.BUFFS[eff.buff].desc)
		ctx.changed(player, "buffs")
		ctx.refreshAttributes(player)
	end
	if eff.resetGymCooldown then
		gymCd[player] = nil
		table.insert(notes, "운동 쿨타임 초기화")
	end
	return table.concat(notes, " · ")
end

-- via: "phone" or { part = BasePart } (kiosk prompt)
function Venues.buy(player: Player, itemId: any, via: any): boolean
	local id = Util.str(itemId, 40)
	local it = id and G.ITEMS[id]
	local d = Profiles.get(player)
	if not it or not d then
		return false
	end
	-- where can it be bought?
	local okPlace = false
	if type(via) == "table" and via.part then
		local pos = Util.rootPosition(player)
		okPlace = pos ~= nil and within(pos, via.part, G.SHOP_REACH)
	elseif it.phone then
		okPlace = true
	elseif it.shop then
		okPlace = nearShop(player, it.shop)
	elseif it.nearDest then
		okPlace = nearDest(player, it.nearDest)
	end
	if not okPlace then
		local where = if it.shop then (G.SHOPS[it.shop] and G.SHOPS[it.shop].title or it.shop) else (it.nearDest or "매장")
		ctx.notify(player, "info", it.name, string.format("%s에서만 살 수 있어요", where))
		return false
	end
	-- owned outfit: wear it for free
	if it.kind == "outfit" and d.owned.outfits[it.ref] then
		if d.outfit ~= it.ref then
			d.outfit = it.ref
			Profiles.markDirty(player)
			ctx.changed(player, "outfit")
			applyLook(player)
		end
		ctx.notify(player, "info", it.name, "이미 가진 옷이라 바로 입었어요 👕")
		ctx.questEvent(player, { type = "buy", item = id })
		return true
	end
	if it.kind == "hair" and d.hair == it.ref then
		ctx.notify(player, "info", it.name, "지금 이 스타일이에요 ✂️")
		return false
	end
	local price = it.price
	if not ctx.canAfford(player, price) then
		ctx.notify(player, "money", "잔액 부족", string.format("%s · %s (현금 %s · 통장 %s)", it.name, G.format.won(price), G.format.won(d.cash), G.format.won(d.bank)))
		return false
	end
	if price > 0 and not ctx.spend(player, price, it.name, true) then
		return false
	end
	local note = ""
	if it.kind == "consumable" then
		note = applyConsumable(player, d, id, it)
	elseif it.kind == "outfit" then
		local c = G.CLOTHES[it.ref]
		d.owned.outfits[it.ref] = true
		d.outfit = it.ref
		d.inventory[id] = 1
		local applied = ctx.addStats(player, { appearance = c.gain }, nil, true)
		note = G.describeStats(applied)
		ctx.changed(player, "outfit", "owned")
		applyLook(player)
	elseif it.kind == "hair" then
		local s = G.SALON[it.ref]
		local first = not d.owned.hair[it.ref]
		d.owned.hair[it.ref] = true
		d.hair = it.ref
		d.inventory[id] = (d.inventory[id] or 0) + 1
		if first then
			note = G.describeStats(ctx.addStats(player, { appearance = s.gain }, nil, true))
		else
			note = "스타일 변경"
		end
		ctx.changed(player, "hair", "owned")
		applyLook(player)
	end
	Profiles.markDirty(player)
	ctx.changed(player, "inventory")
	ctx.notify(player, "money", "구매 완료 · " .. it.name, string.format("-%s%s", G.format.won(price), if note ~= "" then " · " .. note else ""))
	ctx.questEvent(player, { type = "buy", item = id })
	return true
end

-- itemId = "outfit_<id>" | "hair_<id>" (owned, or "_default" to go back to the avatar's own look)
function Venues.equip(player: Player, itemId: any)
	local id = Util.str(itemId, 40)
	local d = Profiles.get(player)
	if not id or not d then
		return
	end
	local kind, ref = string.match(id, "^(%a+)_(.+)$")
	if kind == "outfit" and G.CLOTHES[ref] and (ref == "default" or d.owned.outfits[ref]) then
		d.outfit = ref
		ctx.changed(player, "outfit")
	elseif kind == "hair" and G.SALON[ref] and (ref == "default" or d.owned.hair[ref]) then
		d.hair = ref
		ctx.changed(player, "hair")
	else
		return
	end
	Profiles.markDirty(player)
	applyLook(player)
end

-------------------------------------------------------------------------------------------------
-- Kiosks
-------------------------------------------------------------------------------------------------
type Kiosk = {
	part: BasePart,
	items: { string },
	index: number,
	label: string,
	shop: string?,
	buy: ProximityPrompt,
	nextPrompt: ProximityPrompt?,
	rows: { TextLabel },
}
local kiosks: { [Instance]: Kiosk } = {}

local function itemAction(it: any): string
	if it.kind == "hair" then
		return it.name .. " 하기"
	elseif it.kind == "outfit" then
		return it.name .. " 구매"
	end
	return it.name .. " 구매"
end

local function refreshKiosk(k: Kiosk)
	local id = k.items[k.index]
	local it = G.ITEMS[id]
	if not it then
		return
	end
	k.buy.ActionText = itemAction(it)
	k.buy.ObjectText = G.format.won(it.price) .. " · " .. k.label
	if k.nextPrompt then
		k.nextPrompt.ObjectText = string.format("%s · %d/%d", k.label, k.index, #k.items)
	end
	for i, row in k.rows do
		local rid = k.items[i]
		local rit = G.ITEMS[rid]
		if rit then
			row.Text = string.format("%s %s  %s", if i == k.index then "▶" else "  ", rit.name, G.format.won(rit.price))
			row.TextColor3 = if i == k.index then Color3.fromRGB(255, 214, 90) else Color3.fromRGB(235, 238, 244)
		end
	end
end

local function makeBoard(att: Attachment, k: Kiosk, title: string)
	local n = #k.items
	local gui = Instance.new("BillboardGui")
	gui.Name = "GwangalliMenuBoard"
	gui.Size = UDim2.new(6, 0, 0.8 + 0.5 * n, 0)
	gui.StudsOffset = Vector3.new(0, 2.2 + 0.25 * n, 0)
	gui.MaxDistance = 28
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.ResetOnSpawn = false
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
	bg.BackgroundTransparency = 0.15
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.06, 0)
	corner.Parent = bg
	local head = Instance.new("TextLabel")
	head.BackgroundTransparency = 1
	head.Size = UDim2.new(0.94, 0, 0.8 / (0.8 + 0.5 * n), 0)
	head.Position = UDim2.fromScale(0.03, 0)
	head.Font = Enum.Font.GothamBlack
	head.TextScaled = true
	head.TextColor3 = Color3.fromRGB(255, 255, 255)
	head.Text = title
	head.Parent = bg
	local rowH = 0.5 / (0.8 + 0.5 * n)
	for i = 1, n do
		local row = Instance.new("TextLabel")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(0.94, 0, rowH * 0.9, 0)
		row.Position = UDim2.new(0.03, 0, 0.8 / (0.8 + 0.5 * n) + rowH * (i - 1), 0)
		row.Font = Enum.Font.GothamMedium
		row.TextScaled = true
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.Parent = bg
		k.rows[i] = row
	end
	gui.Parent = att
end

-- part: where the prompts sit. offset: attachment position in part space.
local function makeKiosk(part: BasePart, items: { string }, label: string, shop: string?, offset: Vector3, startIndex: number, board: string?, reachOpt: number?)
	if kiosks[part] or #items == 0 then
		return
	end
	local att = Instance.new("Attachment")
	att.Name = "GwangalliKiosk"
	att.Position = offset
	att.Parent = part
	local reach = reachOpt or 9
	local buy = newPrompt(att, "", "", 0.35, reach)
	buy.Name = "GwangalliBuyPrompt"
	-- OnePerButton: of several kiosks in range (salon chairs) only the nearest pair shows (phones)
	buy.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	-- F / R (not E) so a kiosk next to a gym station or a door never fires together with it
	buy.KeyboardKeyCode = Enum.KeyCode.F
	buy.GamepadKeyCode = Enum.KeyCode.ButtonX
	local k: Kiosk = { part = part, items = items, index = ((startIndex - 1) % #items) + 1, label = label, shop = shop, buy = buy, nextPrompt = nil, rows = {} }
	if #items > 1 then
		local nx = newPrompt(att, "다음 상품 ▶", "", 0, reach)
		nx.Name = "GwangalliNextPrompt"
		nx.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
		nx.KeyboardKeyCode = Enum.KeyCode.R
		nx.GamepadKeyCode = Enum.KeyCode.ButtonY
		nx.UIOffset = Vector2.new(0, 84)
		k.nextPrompt = nx
		nx.Triggered:Connect(function(player: Player)
			if not Util.cooldown(player, "kioskNext", 0.2) then
				return
			end
			k.index = k.index % #k.items + 1
			refreshKiosk(k)
			if shop then
				local shown = hintShown[player]
				if not shown then
					shown = {}
					hintShown[player] = shown
				end
				if not shown[shop] then
					shown[shop] = true
					local sdef = G.SHOPS[shop]
					ctx.notify(player, "info", sdef and sdef.title or label, "'다음 상품 ▶'으로 고르고 '구매'를 누르세요. 위 메뉴판에 가격이 있어요", { shop = shop })
				end
			end
		end)
	end
	if board then
		makeBoard(att, k, board)
	end
	buy.Triggered:Connect(function(player: Player)
		if not Util.cooldown(player, "kioskBuy", 0.6) then
			return
		end
		Venues.buy(player, k.items[k.index], { part = part })
	end)
	kiosks[part] = k
	refreshKiosk(k)
end

local function idsOf(list: { { id: string, item: any } }): { string }
	local out = {}
	for _, e in list do
		table.insert(out, e.id)
	end
	return out
end

local chairCount = 0
local function setupShop(inst: Instance, isChair: boolean)
	local part = Util.partOf(inst)
	if not part or kiosks[part] then
		return
	end
	local shopId = if isChair then "salon" else Util.attrUp(inst, G.Attr.ShopId)
	if type(shopId) ~= "string" or not G.SHOPS[shopId] then
		warn("[GwangalliGameplay] ShopCounter without a valid ShopId: " .. inst:GetFullName())
		return
	end
	shopParts[part] = shopId
	local items = idsOf(G.shopItems(shopId))
	local sdef = G.SHOPS[shopId]
	if isChair then
		chairCount += 1
		makeKiosk(part, items, sdef.name, shopId, Vector3.new(0, part.Size.Y / 2 + 1.2, 0), chairCount, nil, 6)
	else
		makeKiosk(part, items, sdef.name, shopId, Vector3.new(0, part.Size.Y / 2 + 0.8, 0), 1, sdef.title)
	end
end

-------------------------------------------------------------------------------------------------
-- Destinations: item kiosks
-------------------------------------------------------------------------------------------------

function Venues.onDest(name: string, part: BasePart)
	-- item kiosk
	local items = idsOf(G.destItems(name))
	if #items > 0 then
		makeKiosk(part, items, name, nil, Vector3.zero, 1, nil)
	end
end

-------------------------------------------------------------------------------------------------
-- Gym
-------------------------------------------------------------------------------------------------
type Station = { inst: Instance, part: BasePart, kind: string, prompt: ProximityPrompt, user: Player? }
local stations: { [Instance]: Station } = {}
local gymBusy: { [Player]: boolean } = {}

local MOVING: { [string]: boolean } = {}
-- Per station type: character bob (studs along the root's up axis), half-period, equipment bob.
local BOB = {
	treadmill = { char = 0.22, period = 0.28, equip = 0 },
	bike = { char = 0.12, period = 0.4, equip = 0 },
	bench = { char = 0, period = 1.1, equip = 1.2 },
	squat = { char = -1.1, period = 1.1, equip = -1.1 },
	dumbbell = { char = 0, period = 0.9, equip = 1.0 },
	pullup = { char = 1.4, period = 1.1, equip = 0 },
	inbody = { char = 0, period = 1, equip = 0 },
}
local DEFAULT_ROOT_HEIGHT = 3 -- UsePoint CFrames are authored for R15 HipHeight 2 (root 3 studs above the feet)
local SEATED_POSES = { sit = true, bike = true, lie = true }

local function usePoint(st: Station): Instance?
	local up = st.part:FindFirstChild("UsePoint")
	if up then
		return up
	end
	if st.inst ~= st.part then
		up = st.inst:FindFirstChild("UsePoint", true)
		if up then
			return up
		end
	end
	local parent = st.part.Parent
	if parent and parent:IsA("Model") and parent ~= workspace then
		return parent:FindFirstChild("UsePoint")
	end
	return nil
end

-- Pose of a station: the builder's attribute Pose (run|bike|lie|stand|hang|scan|sit) or the default.
local function stationPose(st: Station): string
	local p = Util.attrUp(st.inst, "Pose")
	if type(p) == "string" and p ~= "" then
		return p
	end
	return G.GYM[st.kind].pose
end

-- Root CFrame for the set. A UsePoint Attachment's WorldCFrame IS the HumanoidRootPart CFrame for
-- the pose (authored for R15 HipHeight 2); standing poses are corrected for the real rig height.
local function stationCFrame(st: Station, humanoid: Humanoid, root: BasePart): CFrame
	local pose = stationPose(st)
	local h = Util.standHeight(humanoid, root)
	local up = usePoint(st)
	local useCf: CFrame? = nil
	if up and up:IsA("Attachment") then
		useCf = up.WorldCFrame
	elseif up and up:IsA("BasePart") then
		useCf = up.CFrame
	end
	if useCf then
		if SEATED_POSES[pose] then
			return useCf
		end
		return useCf + Vector3.new(0, h - DEFAULT_ROOT_HEIGHT, 0)
	end
	-- no UsePoint: stand on top of low machines, otherwise in front of the part facing it
	local part = st.part
	local ground = Util.groundOf(part)
	local top = ground.Y + (part.Position.Y - ground.Y) * 2
	local look = Util.flatLook(part.CFrame)
	local feet: Vector3
	if top - ground.Y <= 4.5 and (SEATED_POSES[pose] or pose == "run") then
		feet = Vector3.new(part.Position.X, top, part.Position.Z)
	else
		feet = Vector3.new(part.Position.X, ground.Y, part.Position.Z) + look * (part.Size.Z / 2 + 1.8)
		look = -look
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = Util.charactersIgnore()
		local hit = workspace:Raycast(feet + Vector3.new(0, 3, 0), Vector3.new(0, -10, 0), params)
		if hit then
			feet = hit.Position
		end
	end
	local base = CFrame.lookAt(feet + Vector3.new(0, h, 0), feet + Vector3.new(0, h, 0) + look)
	if pose == "lie" then
		return CFrame.new(feet + Vector3.new(0, 1.1, 0)) * (base - base.Position) * CFrame.Angles(math.pi / 2, 0, 0)
	end
	return base
end

-- Parts that bob during a set: everything in a sibling "Equipment" (Model or BasePart) inside the
-- station's Model, plus parts named in G.GYM_MOVING_PARTS / with attribute GymMoving = true.
local function equipmentParts(st: Station): { BasePart }
	local out: { BasePart } = {}
	local seen: { [BasePart]: boolean } = {}
	local function add(p: Instance)
		if p:IsA("BasePart") and p.Anchored and not seen[p] and #out < 12 then
			seen[p] = true
			table.insert(out, p)
		end
	end
	local container: Instance = st.inst
	if st.inst == st.part and st.part.Parent and st.part.Parent:IsA("Model") and st.part.Parent ~= workspace then
		container = st.part.Parent
	end
	local eq = container:FindFirstChild("Equipment")
	if eq then
		add(eq)
		for _, d in eq:GetDescendants() do
			add(d)
		end
	end
	if #out == 0 then
		for _, d in container:GetDescendants() do
			if d:IsA("BasePart") and (MOVING[d.Name] or d:GetAttribute("GymMoving") == true) then
				add(d)
			end
		end
	end
	return out
end

-- A gym SESSION (venues_detail): the prompt seats / places the player at the machine and keeps
-- them there for up to V.GYM.maxSets sets. Every G.GYM[kind].duration seconds is one set: the
-- existing G.gymGain path (protein, athleisure, daily diminishing) x the form bonus the client's
-- rhythm taps earned (<= V.GYM.formBonus). The client (GwangalliVenues/Gym) animates the rep loop
-- (pose layers + equipment), shows the compact HUD and sends gymForm / gymStop; every client
-- animates other users through the station attribute InUse and the player attribute GwVenueAct.
type Session = { player: Player, st: Station, stop: boolean, form: { [number]: number }, set: number, gains: { [string]: number } }
local sessionsByPlayer: { [Player]: Session } = {}
local VL: any = nil -- VenueLife (optional; nil when GwangalliVenuesShared is missing)
local VS: any = nil -- GwangalliVenuesShared

local function stationStyle(st: Station): string
	local s = Util.attrUp(st.inst, "RepStyle")
	if type(s) == "string" and s ~= "" then
		return s
	end
	return (VS and VS.KIND_STYLE[st.kind]) or "scan"
end

local function stationMachine(st: Station): string
	local m = Util.attrUp(st.inst, "Machine")
	if type(m) == "string" and m ~= "" then
		return m
	end
	local l = Util.attrUp(st.inst, "Label")
	if type(l) == "string" and l ~= "" then
		return l
	end
	return G.GYM[st.kind].name
end

-- routine quest (트레이너 김코치): 3 station kinds -> bonus once per real day
type Routine = { day: number, kinds: { string }, done: { [string]: boolean }, complete: boolean }
local routines: { [Player]: Routine } = {}
local ROUTINE_POOL = { "treadmill", "bike", "bench", "squat", "dumbbell", "pullup" }

local function routineView(r: Routine): any
	local labels = {}
	for _, k in r.kinds do
		labels[k] = G.GYM[k] and G.GYM[k].name or k
	end
	return { kind = "routine", kinds = r.kinds, done = r.done, complete = r.complete, labels = labels }
end

local function routineProgress(player: Player, kind: string): any?
	local r = routines[player]
	if not r or r.complete or r.day ~= G.dayKey(os.time()) or r.done[kind] or not table.find(r.kinds, kind) then
		return nil
	end
	r.done[kind] = true
	local all = true
	for _, k in r.kinds do
		if not r.done[k] then
			all = false
		end
	end
	if all and VL then
		r.complete = true
		local applied = VL.capped(player, "venue_routine", 1, VS.GYM.routineReward)
		local desc = if applied then G.describeStats(applied) else "보너스는 하루 한 번이에요"
		ctx.notify(player, "stat", "🏅 오늘의 루틴 완료!", desc, { sound = "gym" })
		pcall(ctx.sendMessage, player, "coach", "오늘 루틴 완벽했어요! 💪 이렇게만 하면 금방 득근이에요. 물 많이 마시고 푹 쉬어요!")
	end
	if VL then
		VL.fire(player, routineView(r))
	end
	return r
end

local function runSession(player: Player, st: Station)
	local def = G.GYM[st.kind]
	local d = Profiles.get(player)
	if not def or not d then
		return
	end
	if gymBusy[player] or ctx.isRiding(player) then
		return
	end
	if st.user and st.user ~= player and st.user.Parent == Players then
		ctx.notify(player, "info", def.name, "다른 사람이 사용 중이에요")
		return
	end
	local cds = gymCd[player]
	local now = os.clock()
	if cds and cds[st.kind] and now < cds[st.kind] then
		ctx.notify(player, "info", def.name, string.format("%d초만 쉬었다가 해요 (정수기 물을 마시면 바로!)", math.ceil(cds[st.kind] - now)))
		return
	end
	local character, humanoid, root = Util.alive(player)
	if not character or not humanoid or not root then
		return
	end
	if (root.Position - st.part.Position).Magnitude > 16 then
		return
	end
	gymBusy[player] = true
	st.user = player
	player:SetAttribute(G.Attr.GymBusy, true)
	local style = stationStyle(st)
	local machine = stationMachine(st)
	local session: Session = { player = player, st = st, stop = false, form = {}, set = 0, gains = {} }
	sessionsByPlayer[player] = session
	pcall(function()
		st.inst:SetAttribute("InUse", player.UserId)
	end)
	local pose = stationPose(st)
	local sitPose = SEATED_POSES[pose] == true and pose ~= "lie"
	local okSetup, base = pcall(stationCFrame, st, humanoid, root)
	local maxSets = if def.info then 1 else ((VS and VS.GYM.maxSets) or 3)
	local rest = (VS and VS.GYM.rest) or 1.5
	local period = (VS and VS.STYLE[style] and VS.STYLE[style].period) or 1
	local ok, err = pcall(function()
		if humanoid.SeatPart then
			humanoid.Sit = false
		end
		root.Anchored = true
		if okSetup and base then
			character:PivotTo(base * root.CFrame:ToObjectSpace(character:GetPivot()))
		end
		if sitPose then
			humanoid.Sit = true
		end
		if VL then
			VL.setAct(player, "gym:" .. style, nil, if style == "curl" then "dumbbells" else nil)
			VL.fire(player, { kind = "gymStart", station = st.inst, part = st.part, stationKind = st.kind, style = style, machine = machine, sets = maxSets, setSeconds = def.duration, rest = rest, period = period, info = def.info == true })
		end
		for set = 1, maxSets do
			session.set = set
			local t0 = os.clock()
			while os.clock() - t0 < def.duration do
				task.wait(0.2)
				if session.stop or player.Parent ~= Players or player.Character ~= character or humanoid.Health <= 0 or not st.part.Parent then
					return
				end
			end
			-- one set done
			d = Profiles.get(player)
			if not d then
				return
			end
			if def.info then
				ctx.notify(player, "info", "인바디 결과 📊", G.inbodyReport(d.stats))
				if VL then
					VL.fire(player, { kind = "gymSet", set = 1, sets = 1, gains = {}, stats = d.stats, report = G.inbodyReport(d.stats) })
				end
				continue
			end
			local today = G.dayKey(os.time())
			if d.gym.day ~= today then
				d.gym.day = today
				d.gym.today = 0
			end
			local protein = false
			local pb = d.buffs.protein
			if pb and (pb.sets or 0) > 0 then
				protein = true
				pb.sets -= 1
				if pb.sets <= 0 then
					d.buffs.protein = nil
				end
				ctx.changed(player, "buffs")
			end
			local outfit = G.CLOTHES[d.outfit]
			local gains = G.gymGain(st.kind, d.stats, { protein = protein, athleisure = outfit and outfit.gymBonus == true, setsToday = d.gym.today })
			local form = math.clamp(session.form[set] or 0, 0, 1)
			local bonus = 1 + form * ((VS and VS.GYM.formBonus) or 0)
			if bonus > 1 then
				for k, v in gains do
					gains[k] = math.floor(v * bonus * 10 + 0.5) / 10
				end
			end
			d.gym.today += 1
			d.gym.sets += 1
			Profiles.markDirty(player)
			local applied = ctx.addStats(player, gains, nil, true)
			for k, v in applied do
				session.gains[k] = (session.gains[k] or 0) + v
			end
			ctx.questEvent(player, { type = "gym", station = st.kind })
			local r = routineProgress(player, st.kind)
			if VL then
				VL.fire(player, { kind = "gymSet", set = set, sets = maxSets, gains = applied, protein = protein, form = form, stats = d.stats, routine = r ~= nil, setsToday = d.gym.today, tired = d.gym.today >= G.GYM_DAILY_FULL_SETS })
			end
			if set < maxSets then
				local tr = os.clock()
				while os.clock() - tr < rest do
					task.wait(0.2)
					if session.stop or player.Parent ~= Players or player.Character ~= character or humanoid.Health <= 0 then
						return
					end
				end
			end
		end
	end)
	-- cleanup (always)
	if root.Parent then
		if okSetup and base then
			if sitPose or pose == "lie" or pose == "hang" then
				-- step off beside the machine / bench (upright, on the floor)
				local side = base.RightVector
				side = Vector3.new(side.X, 0, side.Z)
				if side.Magnitude < 0.1 then
					side = Vector3.xAxis
				end
				local look = Util.flatLook(st.part.CFrame)
				local probe = base.Position + side.Unit * 2.8 - Vector3.new(0, 1, 0)
				if pose == "hang" then
					probe = base.Position - Util.flatLook(base) * 2.2 - Vector3.new(0, 3, 0)
				end
				local ok2, target = pcall(Util.safeAt, probe, look, Util.standHeight(humanoid, root), Util.charactersIgnore())
				if ok2 and target then
					character:PivotTo(target * root.CFrame:ToObjectSpace(character:GetPivot()))
				else
					local up = base.Position + Vector3.new(0, 2, 0)
					character:PivotTo(CFrame.lookAt(up, up + look) * root.CFrame:ToObjectSpace(character:GetPivot()))
				end
			end
		end
		root.Anchored = false
		pcall(function()
			root:SetNetworkOwner(player)
		end)
	end
	if humanoid.Parent and sitPose then
		humanoid.Sit = false
	end
	if st.user == player then
		st.user = nil
	end
	pcall(function()
		st.inst:SetAttribute("InUse", 0)
	end)
	sessionsByPlayer[player] = nil
	gymBusy[player] = nil
	if player.Parent == Players then
		player:SetAttribute(G.Attr.GymBusy, nil)
		if VL and type(player:GetAttribute("GwVenueAct")) == "string" and string.sub(player:GetAttribute("GwVenueAct"), 1, 4) == "gym:" then
			VL.clearAct(player)
		end
	end
	if not ok then
		warn("[GwangalliGameplay] gym session failed: " .. tostring(err))
	end
	if player.Parent ~= Players then
		return
	end
	local done = if def.info then 0 else session.set - (if session.stop or not ok then 1 else 0)
	if not def.info and session.set >= maxSets and not session.stop and ok then
		done = maxSets
	end
	local summary = G.describeStats(session.gains)
	if VL then
		VL.fire(player, { kind = "gymEnd", sets = done, summary = summary, machine = machine })
	end
	if done > 0 then
		local cdt = gymCd[player]
		if not cdt then
			cdt = {}
			gymCd[player] = cdt
		end
		cdt[st.kind] = os.clock() + def.cooldown
		local extra = ""
		d = Profiles.get(player)
		if d and d.gym.today >= G.GYM_DAILY_FULL_SETS then
			extra = " · 오늘은 충분히 했어요. 쉬는 것도 운동!"
		end
		ctx.notify(player, "stat", string.format("%s %d세트 완료 💪", machine, done), (if summary ~= "" then summary else "능력치가 최대예요!") .. extra, { sound = "gym" })
	end
end

local function setupStation(inst: Instance)
	if stations[inst] then
		return
	end
	local part = Util.partOf(inst)
	local kind = Util.attrUp(inst, G.Attr.StationType)
	if not part or type(kind) ~= "string" or not G.GYM[kind] then
		warn("[GwangalliGameplay] GymStation without a valid StationType: " .. inst:GetFullName())
		return
	end
	local def = G.GYM[kind]
	local att = Instance.new("Attachment")
	att.Name = "GwangalliGymPoint"
	att.Position = Vector3.new(0, math.min(part.Size.Y / 2 + 0.5, 3), 0)
	att.Parent = part
	local st: Station = { inst = inst, part = part, kind = kind, prompt = nil :: any, user = nil }
	local prompt = newPrompt(att, def.action, stationMachine(st), if def.info then 0.5 else G.GYM_HOLD_DURATION, 8)
	prompt.Name = "GwangalliGymPrompt"
	st.prompt = prompt
	stations[inst] = st
	pcall(function()
		inst:SetAttribute("InUse", 0)
	end)
	prompt.Triggered:Connect(function(player: Player)
		if not Profiles.get(player) then
			return
		end
		if not Util.cooldown(player, "gymPrompt", 0.5) then
			return
		end
		local s = sessionsByPlayer[player]
		if s then
			s.stop = true -- the same prompt again ends the session
			return
		end
		task.spawn(runSession, player, st)
	end)
end

-- 정수기 / 락커 / 트레이너 (VenueSpot gym_*), registered with VenueLife in Venues.init
local function gymSpots()
	if not VL then
		return
	end
	VL.spot("gym_water", function(player: Player, _part: BasePart)
		if not Util.cooldown(player, "gymWater", VS.GYM.water.cooldown) then
			ctx.notify(player, "info", "정수기", "조금 전에 마셨어요. 잠시 후에 또 마셔요 💧")
			return
		end
		if gymBusy[player] then
			return
		end
		VL.setAct(player, "drink", 3, "water")
		task.delay(2.6, function()
			if player.Parent ~= Players then
				return
			end
			gymCd[player] = nil
			local applied = VL.capped(player, "venue_water", VS.GYM.water.daily, { stamina = VS.GYM.water.stamina })
			ctx.notify(player, "stat", "💧 시원한 물 한 잔", (if applied then G.describeStats(applied) .. " · " else "") .. "운동 쿨타임 초기화")
		end)
	end, { action = "물 마시기", object = "정수기 · 무료", hold = 0.3 })

	local lockerOpen: { [BasePart]: number } = {}
	VL.spot("gym_locker", function() end, {
		setup = function(door: BasePart)
			local closed = door.CFrame
			local no = door:GetAttribute("LockerNo") or 0
			local pr = VL.prompt(door, "락커 열기", string.format("락커 %d번", no), 0.2, 7, Enum.KeyCode.E)
			pr.Name = "GwangalliLockerPrompt"
			local hinge = closed * CFrame.new(-door.Size.X / 2, 0, 0)
			local openCf = hinge * CFrame.Angles(0, math.rad(105), 0) * CFrame.new(door.Size.X / 2, 0, 0)
			pr.Triggered:Connect(function(player: Player)
				if not Util.cooldown(player, "locker", 0.6) then
					return
				end
				local token = (lockerOpen[door] or 0) + 1
				lockerOpen[door] = token
				local isOpen = pr.ActionText == "락커 닫기"
				TweenService:Create(door, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = if isOpen then closed else openCf }):Play()
				pr.ActionText = if isOpen then "락커 열기" else "락커 닫기"
				if not isOpen then
					local first = VL.capped(player, "venue_locker", 1, { happiness = 1 })
					ctx.notify(player, "info", string.format("🔒 락커 %d번", no), if first then "소지품 보관 완료! 오늘도 득근하세요" else "운동복으로 갈아입었어요 👟")
					task.delay(8, function()
						if lockerOpen[door] == token and pr.ActionText == "락커 닫기" then
							TweenService:Create(door, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { CFrame = closed }):Play()
							pr.ActionText = "락커 열기"
						end
					end)
				end
			end)
		end,
	})

	VL.spot("gym_trainer", function(player: Player)
		local today = G.dayKey(os.time())
		local r = routines[player]
		local trainer = nil
		for _, m in CollectionService:GetTagged(VS.Tags.Staff) do
			if m:GetAttribute("Staff") == "gym_trainer" then
				trainer = m
			end
		end
		if trainer then
			trainer:SetAttribute("Act", "talk")
			task.delay(3, function()
				if trainer.Parent then
					trainer:SetAttribute("Act", trainer:GetAttribute("HomeAct") or "clipboard")
				end
			end)
		end
		if r and r.day == today then
			if r.complete then
				ctx.notify(player, "message", "김코치", "오늘 루틴은 끝! 내일 또 봐요 👋 과하면 다쳐요")
			else
				local left = {}
				for _, k in r.kinds do
					if not r.done[k] then
						table.insert(left, G.GYM[k].name)
					end
				end
				ctx.notify(player, "message", "김코치", "남은 운동: " .. table.concat(left, " · ") .. " 화이팅!")
			end
			VL.fire(player, routineView(r))
			return
		end
		-- three distinct kinds, shuffled
		local pool = table.clone(ROUTINE_POOL)
		local kinds = {}
		for _ = 1, VS.GYM.routineCount do
			local i = math.random(1, #pool)
			table.insert(kinds, table.remove(pool, i))
		end
		r = { day = today, kinds = kinds, done = {}, complete = false }
		routines[player] = r
		local names = {}
		for _, k in kinds do
			table.insert(names, G.GYM[k].name)
		end
		ctx.notify(player, "message", "김코치 · 오늘의 루틴", table.concat(names, " → ") .. " 각각 1세트! 끝내면 보너스 🎁")
		VL.fire(player, routineView(r))
	end, { action = "오늘의 루틴 받기", object = "트레이너 김코치", hold = 0.3 })

	VL.handle("gymStop", function(player)
		local s = sessionsByPlayer[player]
		if s then
			s.stop = true
		end
		return { ok = true }
	end)
	VL.handle("gymForm", function(player, p)
		local s = sessionsByPlayer[player]
		local f = type(p) == "table" and tonumber(p.form) or nil
		if not s or not f or f ~= f then
			return { ok = false }
		end
		local set = s.set
		if set >= 1 and s.form[set] == nil then
			s.form[set] = math.clamp(f, 0, 1)
		end
		return { ok = true }
	end)
	VL.handle("routine", function(player)
		local r = routines[player]
		if r and r.day == G.dayKey(os.time()) then
			return routineView(r)
		end
		return { ok = false }
	end)
end

-------------------------------------------------------------------------------------------------
-- Elevators
-------------------------------------------------------------------------------------------------
type Button = { inst: Instance, part: BasePart, floor: number, target: string, prompt: ProximityPrompt, stop: BasePart? }
local buttons: { [Instance]: Button } = {}

local function floorLabel(floor: number): string
	if floor < 0 then
		return "B" .. tostring(-floor) .. "층"
	elseif floor == 0 then
		return "로비"
	elseif floor == 1 then
		return "1층 로비"
	end
	return tostring(floor) .. "층"
end

local function findStop(b: Button): BasePart?
	if b.stop and b.stop:IsDescendantOf(workspace) then
		return b.stop
	end
	local cur: Instance? = b.part.Parent
	local depth = 0
	while cur and cur ~= game and depth < 10 do
		local found = cur:FindFirstChild(b.target, true)
		if found and found:IsA("BasePart") then
			b.stop = found
			return found
		end
		if cur == workspace then
			break
		end
		cur = cur.Parent
		depth += 1
	end
	return nil
end

-- Buttons within 8 studs of each other form a panel: each gets its own key and a stacked offset.
local function layoutPanels()
	local list = {}
	for _, b in buttons do
		table.insert(list, b)
	end
	for _, b in list do
		local group = {}
		for _, o in list do
			if (o.part.Position - b.part.Position).Magnitude <= 8 then
				table.insert(group, o)
			end
		end
		table.sort(group, function(x, y)
			if x.floor ~= y.floor then
				return x.floor > y.floor
			end
			return x.target < y.target
		end)
		local rank = table.find(group, b) or 1
		local n = #group
		b.prompt.KeyboardKeyCode = KEYS[math.min(rank, #KEYS)]
		b.prompt.GamepadKeyCode = PADS[math.min(rank, #PADS)]
		b.prompt.Exclusivity = if n > 1 then Enum.ProximityPromptExclusivity.AlwaysShow else Enum.ProximityPromptExclusivity.OnePerButton
		b.prompt.UIOffset = Vector2.new(0, (rank - 1) * 76 - (n - 1) * 38)
	end
end

local layoutQueued = false
local function queueLayout()
	if layoutQueued then
		return
	end
	layoutQueued = true
	task.delay(0.5, function()
		layoutQueued = false
		pcall(layoutPanels)
	end)
end

local function ride(player: Player, b: Button)
	if not Util.cooldown(player, "elevator", 2.5) then
		return
	end
	if gymBusy[player] or ctx.isRiding(player) then
		return
	end
	local stop = findStop(b)
	if not stop then
		ctx.notify(player, "info", "엘리베이터", "점검 중이에요 🛠️")
		return
	end
	local pos = Util.rootPosition(player)
	if not pos then
		return
	end
	if (pos - stop.Position).Magnitude < 8 then
		ctx.notify(player, "info", "엘리베이터", "이미 " .. floorLabel(b.floor) .. "이에요")
		return
	end
	local label = stop:GetAttribute("Label") or b.part:GetAttribute("Label")
	local text = if type(label) == "string" and label ~= "" then label else floorLabel(b.floor)
	ctx.allowTeleport(player, 10)
	Util.fade(player, true, 0.35, "🛗 " .. text)
	if player.Parent ~= Players then
		return
	end
	Util.teleportTo(player, stop, 3)
	ctx.questsResetPosition(player)
	Util.fade(player, false, 0.35)
end

local function setupButton(inst: Instance)
	if buttons[inst] then
		return
	end
	local part = Util.partOf(inst)
	local floor = Util.attrUp(inst, G.Attr.Floor)
	local target = Util.attrUp(inst, G.Attr.Target)
	if not part or not G.isFiniteNumber(floor) or type(target) ~= "string" or target == "" then
		warn("[GwangalliGameplay] ElevatorButton needs Floor (number) and Target (string): " .. inst:GetFullName())
		return
	end
	local att = Instance.new("Attachment")
	att.Name = "GwangalliElevatorPoint"
	att.Parent = part
	local label = part:GetAttribute("Label")
	local prompt = newPrompt(att, if type(label) == "string" and label ~= "" then label else floorLabel(floor), "엘리베이터", 0.2, 7)
	prompt.Name = "GwangalliElevatorPrompt"
	local b: Button = { inst = inst, part = part, floor = floor, target = target, prompt = prompt, stop = nil }
	buttons[inst] = b
	prompt.Triggered:Connect(function(player: Player)
		task.spawn(ride, player, b)
	end)
	queueLayout()
end

-------------------------------------------------------------------------------------------------
-- Looks (outfit + hair)
-------------------------------------------------------------------------------------------------
type LookState = { char: Model?, base: HumanoidDescription?, custom: boolean, token: number }
local looks: { [Player]: LookState } = {}

local function clearCustomParts(character: Model)
	for _, x in character:GetChildren() do
		if x.Name == "GwangalliHair" or x.Name == "GwangalliJacket" then
			x:Destroy()
		end
	end
end

local function noPhysics(p: BasePart)
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
end

local function buildHair(character: Model, styleId: string)
	local style = G.SALON[styleId]
	local head = character:FindFirstChild("Head")
	if not style or not style.shape or not head or not head:IsA("BasePart") then
		return
	end
	local shape = G.HAIR_SHAPES[style.shape]
	if not shape then
		return
	end
	local u = head.Size.Y
	if head:FindFirstChildOfClass("SpecialMesh") then
		u = head.Size.Y * 1.25 -- R6 head: 2x1x1 part with a 1.25 head mesh
	end
	local color = Util.color(style.color)
	local model = Instance.new("Model")
	model.Name = "GwangalliHair"
	for i, piece in shape do
		local p = Instance.new("Part")
		p.Name = "Hair" .. i
		p.Size = Vector3.new(math.max(0.05, piece.size[1] * u), math.max(0.05, piece.size[2] * u), math.max(0.05, piece.size[3] * u))
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		noPhysics(p)
		if piece.shape == "sphere" then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = p
		end
		local offset = CFrame.new(piece.offset[1] * u, piece.offset[2] * u, piece.offset[3] * u) * CFrame.Angles(math.rad(piece.tilt or 0), 0, 0)
		p.CFrame = head.CFrame * offset
		local w = Instance.new("Weld")
		w.Part0 = head
		w.Part1 = p
		w.C0 = offset
		w.Parent = p
		p.Parent = model
	end
	model.Parent = character
end

local function buildJacket(character: Model, rgb: { number })
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if not torso or not torso:IsA("BasePart") then
		return
	end
	local p = Instance.new("Part")
	p.Name = "GwangalliJacket"
	p.Size = torso.Size * Vector3.new(1.1, 1.03, 1.28)
	p.Color = Util.color(rgb)
	p.Material = Enum.Material.Fabric
	noPhysics(p)
	p.CFrame = torso.CFrame
	local w = Instance.new("Weld")
	w.Part0 = torso
	w.Part1 = p
	w.Parent = p
	p.Parent = character
end

-- Fallback when ApplyDescription fails: strip clothing templates, set BodyColors, hide hair.
local function manualLook(character: Model, outfit: any, hideHair: boolean)
	if outfit and outfit.top then
		for _, x in character:GetChildren() do
			if x:IsA("Shirt") or x:IsA("Pants") or x:IsA("ShirtGraphic") then
				x:Destroy()
			end
		end
		local bc = character:FindFirstChildOfClass("BodyColors")
		if not bc then
			bc = Instance.new("BodyColors")
			bc.Parent = character
		end
		local top, bottom = Util.color(outfit.top), Util.color(outfit.bottom)
		bc.TorsoColor3 = top
		if outfit.sleeves == "long" then
			bc.LeftArmColor3 = top
			bc.RightArmColor3 = top
		end
		bc.LeftLegColor3 = bottom
		bc.RightLegColor3 = bottom
	end
	if hideHair then
		for _, x in character:GetChildren() do
			if x:IsA("Accessory") then
				local isHair = false
				pcall(function()
					isHair = x.AccessoryType == Enum.AccessoryType.Hair
				end)
				local handle = x:FindFirstChild("Handle")
				if not isHair and handle and handle:FindFirstChild("HairAttachment") then
					isHair = true
				end
				if isHair then
					x:Destroy()
				end
			end
		end
	end
end

applyLook = function(player: Player)
	local st = looks[player]
	if not st then
		st = { char = nil, base = nil, custom = false, token = 0 }
		looks[player] = st
	end
	st.token += 1
	local token = st.token
	task.spawn(function()
		local character, humanoid = Util.alive(player)
		if not character or not humanoid then
			return
		end
		local t0 = os.clock()
		while not player:HasAppearanceLoaded() and os.clock() - t0 < 6 do
			task.wait(0.25)
		end
		if st.token ~= token or player.Character ~= character or not humanoid.Parent then
			return
		end
		local d = Profiles.get(player)
		if not d then
			return
		end
		if st.char ~= character then
			st.char = character
			st.custom = false
			st.base = nil
			local ok, desc = pcall(humanoid.GetAppliedDescription, humanoid)
			if ok and desc then
				st.base = desc
			end
		end
		local outfit = if d.outfit ~= "default" then G.CLOTHES[d.outfit] else nil
		local hairStyle = if d.hair ~= "default" then d.hair else nil
		local custom = outfit ~= nil or hairStyle ~= nil
		if custom or st.custom then
			local applied = false
			if st.base then
				local desc = st.base:Clone()
				if outfit and outfit.top then
					desc.Shirt = 0
					desc.Pants = 0
					desc.GraphicTShirt = 0
					local top, bottom = Util.color(outfit.top), Util.color(outfit.bottom)
					desc.TorsoColor = top
					desc.LeftArmColor = if outfit.sleeves == "long" then top else desc.HeadColor
					desc.RightArmColor = if outfit.sleeves == "long" then top else desc.HeadColor
					desc.LeftLegColor = bottom
					desc.RightLegColor = bottom
				end
				if hairStyle then
					desc.HairAccessory = ""
				end
				applied = pcall(humanoid.ApplyDescription, humanoid, desc)
			end
			if st.token ~= token or player.Character ~= character or not humanoid.Parent then
				return
			end
			if not applied then
				manualLook(character, outfit, hairStyle ~= nil)
			end
		end
		clearCustomParts(character)
		if hairStyle then
			pcall(buildHair, character, hairStyle)
		end
		if outfit and outfit.jacket then
			pcall(buildJacket, character, outfit.jacket)
		end
		st.custom = custom
	end)
end
Venues.applyLook = function(player: Player)
	applyLook(player)
end

-------------------------------------------------------------------------------------------------
-- Lifecycle
-------------------------------------------------------------------------------------------------
function Venues.onCharacter(player: Player)
	if VL then
		pcall(VL.character, player)
	end
	local st = looks[player]
	if st then
		st.char = nil
		st.custom = false
		st.base = nil
	end
	if Profiles.get(player) then
		applyLook(player)
	end
end

function Venues.onLeave(player: Player)
	local s = sessionsByPlayer[player]
	if s then
		s.stop = true
	end
	routines[player] = nil
	if VL then
		pcall(VL.leave, player)
	end
	for _, st in stations do
		if st.user == player then
			st.user = nil
		end
	end
	gymBusy[player] = nil
	gymCd[player] = nil
	hintShown[player] = nil
	looks[player] = nil
end

function Venues.isBusy(player: Player): boolean
	if gymBusy[player] == true then
		return true
	end
	local pcMod = Venues._pc
	return pcMod ~= nil and pcMod.isBusy(player) == true
end

local function watchTag(tag: string, fn: (Instance) -> ())
	local function safe(inst: Instance)
		if not inst:IsDescendantOf(workspace) then
			return
		end
		local ok, err = pcall(fn, inst)
		if not ok then
			warn("[GwangalliGameplay] " .. tag .. " setup failed: " .. tostring(err))
		end
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(safe)
	for _, inst in CollectionService:GetTagged(tag) do
		safe(inst)
	end
end

function Venues.init(context: any)
	ctx = context
	G = context.G
	Util = context.Util
	Profiles = context.Profiles
	for _, n in G.GYM_MOVING_PARTS do
		MOVING[n] = true
	end
	watchTag(G.Tags.GymStation, setupStation)
	watchTag(G.Tags.SalonChair, function(inst)
		setupShop(inst, true)
	end)
	watchTag(G.Tags.ShopCounter, function(inst)
		setupShop(inst, false)
	end)
	watchTag(G.Tags.ElevatorButton, setupButton)
	-- venue interiors (venues_detail): optional; a missing / failing module only disables its venue
	local folder = script.Parent
	local function sub(name: string): any
		local m = folder and folder:FindFirstChild(name)
		if not m or not m:IsA("ModuleScript") then
			return nil
		end
		local ok, res = pcall(require, m)
		if not ok then
			warn("[GwangalliGameplay] " .. name .. " failed: " .. tostring(res))
			return nil
		end
		return res
	end
	local life = sub("VenueLife")
	if life and life.init(context) then
		VL = life
		VS = life.V
		local okG, errG = pcall(gymSpots)
		if not okG then
			warn("[GwangalliGameplay] gym spots: " .. tostring(errG))
		end
		local karaoke = sub("VenueKaraoke")
		if karaoke then
			local okK, errK = pcall(karaoke.init, life)
			if not okK then
				warn("[GwangalliGameplay] VenueKaraoke init: " .. tostring(errK))
			end
		end
		local pcMod = sub("VenuePC")
		if pcMod then
			local okP, errP = pcall(pcMod.init, life)
			if okP then
				Venues._pc = pcMod
			else
				warn("[GwangalliGameplay] VenuePC init: " .. tostring(errP))
			end
		end
		local okS, errS = pcall(life.start)
		if not okS then
			warn("[GwangalliGameplay] VenueLife start: " .. tostring(errS))
		end
	end
	CollectionService:GetInstanceRemovedSignal(G.Tags.GymStation):Connect(function(inst)
		stations[inst] = nil
	end)
	CollectionService:GetInstanceRemovedSignal(G.Tags.ElevatorButton):Connect(function(inst)
		buttons[inst] = nil
	end)
end

return Venues
