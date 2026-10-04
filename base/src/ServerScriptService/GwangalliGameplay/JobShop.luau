--!nocheck
-- GwangalliGameplay/JobShop: ANY player buys at the store / cafe (docs/DESIGN_JOBS.md "음료수 냉장고
-- 앞에서 상호작용 -> 새 UI -> 거기서 결제"; never from another player). Required by Jobs.luau.
--   * every GwJobStation anchor with attribute Shop = <JS.SHOP.stations key> gets a ProximityPrompt
--     (F, hold 0, 8 studs, OnePerButton) "고르기"; Triggered -> JobGame {op = "shop", station, ...} to
--     that player; the client shows the purchase sheet (GwangalliJobs/Shop.luau)
--   * client -> server JobGame {op = "buy", item, anchor} : distance to the anchor, the item belongs to
--     that station, cooldown, money through ctx.spend (cash first, then the bank), effects through
--     ctx.addStats (+ optional Health.rest for fatigue), a held prop (cup / can / snack) welded to the
--     right hand for a few seconds (everyone sees it), a toast.
-- No per-frame work: prompts + one-shot events only.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local JobShop = {}

local ctx: any
local G: any
local JS: any
local Util: any
local remote: RemoteEvent? = nil
local health: () -> any = function()
	return nil
end

local anchors: { [BasePart]: string } = {} -- anchor -> station kind
local lastBuy: { [Player]: number } = {}
local daily: { [Player]: { day: number, n: { [string]: number } } } = {}
local held: { [Player]: BasePart } = {}

local function dayKey(): number
	return math.floor((os.time() + 9 * 3600) / 86400)
end

local function stationDef(kind: string): any
	return JS.SHOP and JS.SHOP.stations and JS.SHOP.stations[kind]
end

local function addAnchor(inst: Instance)
	if not inst:IsA("BasePart") or anchors[inst] then
		return
	end
	local kind = inst:GetAttribute("Shop")
	local def = type(kind) == "string" and stationDef(kind)
	if not def then
		return
	end
	anchors[inst] = kind
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "GwangalliShopPrompt"
	prompt.ActionText = if kind == "cafe_counter" then "주문하기" else "고르기"
	prompt.ObjectText = string.format("%s %s", def.icon or "🛒", def.title or "상품")
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt.UIOffset = Vector2.new(0, 24)
	prompt.Parent = inst
	prompt.Triggered:Connect(function(player: Player)
		local ok, err = pcall(JobShop.open, player, inst)
		if not ok then
			warn("[GwangalliGameplay] shop open failed: " .. tostring(err))
		end
	end)
end

local function reachOk(player: Player, part: BasePart): boolean
	local pos = Util.rootPosition(player)
	return pos ~= nil and (pos - part.Position).Magnitude <= (JS.SHOP.reach or 12) + 4
end

-- the purchase sheet payload
function JobShop.open(player: Player, part: BasePart)
	local kind = anchors[part]
	local def = kind and stationDef(kind)
	if not def or not remote or not reachOk(player, part) then
		return
	end
	local d = ctx.Profiles.get(player)
	local items = {}
	for _, id in def.items do
		local it = JS.SHOP.items[id]
		if it then
			table.insert(items, { id = id, name = it.name, icon = it.icon, price = it.price, desc = JobShop.describe(it) })
		end
	end
	remote:FireClient(player, {
		op = "shop",
		station = kind,
		anchor = part,
		title = def.title,
		icon = def.icon,
		place = part:GetAttribute("Place") or "",
		items = items,
		cash = d and d.cash or 0,
		bank = d and d.bank or 0,
	})
end

function JobShop.describe(it: any): string
	local parts = {}
	local eff = it.effect or {}
	local names = { stamina = "체력", happiness = "행복", popularity = "인기도", appearance = "외모", strength = "근력" }
	for k, v in eff.stats or {} do
		table.insert(parts, string.format("%s +%s", names[k] or k, tostring(v)))
	end
	if eff.fatigue and eff.fatigue < 0 then
		table.insert(parts, string.format("피로 %d", eff.fatigue))
	end
	table.sort(parts)
	return table.concat(parts, " · ")
end

local function removeHeld(player: Player)
	local p = held[player]
	if p then
		held[player] = nil
		if p.Parent then
			p:Destroy()
		end
	end
end

local function holdProp(player: Player, it: any)
	removeHeld(player)
	local char = player.Character
	local hand = char and (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm"))
	if not hand or not hand:IsA("BasePart") then
		return
	end
	local kind = it.prop or "cup"
	local p = Instance.new("Part")
	p.Name = "GwHeldItem"
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	local c = it.color or { 240, 240, 240 }
	p.Color = Color3.fromRGB(c[1], c[2], c[3])
	if kind == "cup" or kind == "can" or kind == "bottle" then
		p.Shape = Enum.PartType.Cylinder
		p.Size = if kind == "bottle" then Vector3.new(1.0, 0.45, 0.45) elseif kind == "can" then Vector3.new(0.7, 0.42, 0.42) else Vector3.new(0.9, 0.55, 0.55)
		p.CFrame = hand.CFrame * CFrame.new(0, -0.25, -0.15) * CFrame.Angles(0, 0, math.rad(90))
	else
		p.Size = if kind == "box" then Vector3.new(0.9, 0.35, 0.7) else Vector3.new(0.6, 0.25, 0.5)
		p.CFrame = hand.CFrame * CFrame.new(0, -0.3, -0.2)
	end
	local w = Instance.new("WeldConstraint")
	w.Part0 = hand
	w.Part1 = p
	w.Parent = p
	p.Parent = char
	held[player] = p
	task.delay(math.clamp(tonumber(it.hold) or 6, 2, 15), function()
		if held[player] == p then
			removeHeld(player)
		end
	end)
end

function JobShop.buy(player: Player, itemId: any, anchor: any): boolean
	local id = type(itemId) == "string" and string.sub(itemId, 1, 40) or nil
	local it = id and JS.SHOP.items[id]
	if not it or typeof(anchor) ~= "Instance" or not anchor:IsA("BasePart") then
		return false
	end
	local kind = anchors[anchor]
	local def = kind and stationDef(kind)
	if not def or not table.find(def.items, id) then
		return false
	end
	if not reachOk(player, anchor) then
		ctx.notify(player, "info", it.name, "매대 앞에서만 살 수 있어요")
		return false
	end
	local now = os.clock()
	if lastBuy[player] and now - lastBuy[player] < (JS.SHOP.cooldown or 1) then
		return false
	end
	lastBuy[player] = now
	local d = ctx.Profiles.get(player)
	if not d then
		return false
	end
	if not ctx.canAfford(player, it.price) then
		ctx.notify(player, "money", "잔액 부족", string.format("%s · %s (현금 %s · 통장 %s)", it.name, G.format.won(it.price), G.format.won(d.cash), G.format.won(d.bank)))
		return false
	end
	local place = anchor:GetAttribute("Place") or def.title
	if not ctx.spend(player, it.price, string.format("%s · %s", tostring(place), it.name), true) then
		return false
	end
	-- effects (stats only the first few times a day per item)
	local dk = dayKey()
	local rec = daily[player]
	if not rec or rec.day ~= dk then
		rec = { day = dk, n = {} }
		daily[player] = rec
	end
	rec.n[id] = (rec.n[id] or 0) + 1
	local note = ""
	local eff = it.effect or {}
	if rec.n[id] <= (JS.SHOP.dailyStatLimit or 6) then
		if eff.stats then
			local applied = ctx.addStats(player, eff.stats, nil, true)
			if G.describeStats then
				local ok, s = pcall(G.describeStats, applied)
				if ok and type(s) == "string" then
					note = s
				end
			end
		end
		if eff.fatigue and eff.fatigue < 0 then
			local H = health()
			if H and type(H.rest) == "function" then
				pcall(H.rest, player, -eff.fatigue, "store")
				note = note .. (if note ~= "" then " · " else "") .. string.format("피로 %d", eff.fatigue)
			end
		end
	else
		note = "오늘은 많이 먹었어요 (효과 없음)"
	end
	pcall(holdProp, player, it)
	ctx.notify(player, "money", string.format("%s %s 구매", it.icon or "🛒", it.name), string.format("-%s%s", G.format.won(it.price), if note ~= "" then " · " .. note else ""), { sound = "cash" })
	if remote then
		remote:FireClient(player, { op = "bought", item = id, name = it.name, icon = it.icon, price = it.price, note = note })
	end
	pcall(ctx.questEvent, player, { type = "buy", item = id })
	return true
end

function JobShop.onLeave(player: Player)
	removeHeld(player)
	lastBuy[player] = nil
	daily[player] = nil
end

JobShop.anchors = anchors

function JobShop.init(context: any, js: any, r: RemoteEvent?, healthGetter: any)
	ctx = context
	G = context.G
	Util = context.Util
	JS = js
	remote = r
	if type(healthGetter) == "function" then
		health = healthGetter
	end
	if not JS.SHOP then
		return
	end
	for _, inst in CollectionService:GetTagged("GwJobStation") do
		addAnchor(inst)
	end
	CollectionService:GetInstanceAddedSignal("GwJobStation"):Connect(addAnchor)
	Players.PlayerRemoving:Connect(JobShop.onLeave)
end

return JobShop
