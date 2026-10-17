--!strict
-- GwangalliDecorPlus/Homes: the server world of every life-game home model in
-- Workspace.GwangalliHomeInstances. Builds the owner's placed pieces into model.DecorPlus (Models
-- "Item_<uid>", tag GwDecorItem, attributes DecorUid / ItemId / OwnerUserId / PlaceKind / Look), keeps the
-- Unit + Rules indexes, the light budget, the item prompts (앉기 · 눕기 · 불 켜기 · TV · 음악 · 문 열기 ·
-- 먹이 주기) and the room finishes (벽지 · 바닥 · 조명 프리셋) on the home's own Room/Surface parts.
-- Pieces die with the home model; they are rebuilt from the Store whenever Housing builds a new one.
--   Homes.init(deps) / Homes.start() / Homes.ofOwner(p) / Homes.ofModel(m) / Homes.homeData(data, lid)
--   Homes.add(H, rec) / Homes.move(H, uid, fx) / Homes.restyle(H, uid) / Homes.removeItem(H, uid)
--   Homes.applyFinish(H) / Homes.score(H) / Homes.counts(H) / Homes.people(H)

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local Shared = require(game:GetService("ReplicatedStorage"):WaitForChild("GwangalliDecorShared"))
local Config, Catalog, Unit, Rules, Spec, Geometry, Finish, Score, Palette, Text, Path =
	Shared.Config, Shared.Catalog, Shared.Unit, Shared.Rules, Shared.Spec, Shared.Geometry, Shared.Finish, Shared.Score, Shared.Palette, Shared.Text, Shared.Path

local Homes = {}

local Host: any, Store: any, push: any, onChanged: any = nil, nil, nil, nil
local byModel: { [Instance]: any } = {}
local byOwner: { [number]: any } = {}
Homes.bonus = setmetatable({}, { __mode = "k" }) :: { [any]: { decor: number, value: number } }

local TV_CHANNELS = 8

function Homes.init(deps: any)
	Host, Store, push, onChanged = deps.Host, deps.Store, deps.push, deps.onChanged
end

function Homes.ofModel(m: Instance): any?
	return byModel[m]
end

function Homes.ofOwner(p: Player): any?
	local H = byOwner[p.UserId]
	if H and H.model.Parent then
		return H
	end
	return nil
end

function Homes.all(): { [Instance]: any }
	return byModel
end

local function color3(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

-------------------------------------------------------------------------------------------------
-- Per-home records
-------------------------------------------------------------------------------------------------
-- the record table of a listing; pieces of other listings (moved house) go to 창고 (overflow sold)
function Homes.homeData(owner: Player, data: any, listingId: string): (any, number, number)
	local moved, soldAmount = 0, 0
	for lid, h in data.homes do
		if lid ~= listingId and #h.items > 0 then
			for _, rec in h.items do
				if Shared.Codec.storageCount(data) < Config.STORAGE_MAX then
					data.storage[rec.i] = math.min(99, (data.storage[rec.i] or 0) + 1)
					moved += 1
				else
					soldAmount += Catalog.resale(rec.i, Config.SELL_RATE)
				end
			end
			h.items = {}
			h.fin = { rooms = {} }
		end
	end
	if soldAmount > 0 then
		Host.refund(owner, soldAmount, "이사 · 창고 초과 가구 판매")
	end
	local h = data.homes[listingId]
	if not h then
		h = { items = {}, n = 1, fin = { rooms = {} } }
		data.homes[listingId] = h
	end
	return h, moved, soldAmount
end

function Homes.counts(H: any): any
	local items, parts, lights = 0, 0, 0
	for _, rec in H.home.items do
		items += 1
		parts += Catalog.partCount(rec.i)
		lights += Catalog.lightCount(rec.i)
	end
	return { items = items, parts = parts, lights = lights, realLights = H.lightsUsed or 0 }
end

function Homes.roomOf(H: any, rec: any): string?
	local r = Unit.roomAt(H.U, Vector3.new(rec.x, rec.y + 0.05, rec.z))
	if not r then
		-- wall / ceiling pieces: look at the floor below
		local f = Unit.floorAt(H.U, rec.x, rec.z, rec.y + 0.5)
		if f then
			return f.room
		end
		return nil
	end
	return r.id
end

function Homes.score(H: any): any
	local rooms = {}
	for _, rec in H.home.items do
		rooms[rec.u] = Homes.roomOf(H, rec)
	end
	return Score.compute({ items = H.home.items, finish = H.home.fin, rooms = rooms, likes = H.data.likes, gb = #H.data.gb, stats = H.data.stats })
end

-- host link: our pieces in the 인테리어 점수 / 가구 가치 of the life game
function Homes.refreshBonus(H: any)
	local d = Host.profile(H.owner)
	if not d then
		return
	end
	local decor = 0
	for _, rec in H.home.items do
		local def = Catalog.get(rec.i)
		decor += def and def.decor or 0
	end
	decor += Finish.decor(H.home.fin)
	local value = 0
	for _, rec in H.home.items do
		value += Catalog.price(rec.i) * Config.HOST_VALUE_RATE
	end
	for id, n in H.data.storage do
		value += Catalog.price(id) * Config.HOST_VALUE_RATE * n
	end
	Homes.bonus[d] = { decor = math.floor(decor * Config.HOST_DECOR_SCALE), value = math.floor(value) }
end

function Homes.people(H: any): { Vector3 }
	local out = {}
	for _, p in Players:GetPlayers() do
		local ch = p.Character
		local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			local inst = Host.inside(p)
			if inst and inst.model == H.model then
				table.insert(out, H.U.F:PointToObjectSpace(hrp.Position))
			end
		end
	end
	return out
end

-------------------------------------------------------------------------------------------------
-- Building pieces
-------------------------------------------------------------------------------------------------
local function lookAttr(rec: any): string
	local c = ""
	if rec.c then
		local t = {}
		for i, v in rec.c do
			t[i] = if type(v) == "string" then v else ""
		end
		c = table.concat(t, ",")
	end
	local m = ""
	if rec.m then
		local t = {}
		for i, v in rec.m do
			t[i] = tostring(v)
		end
		m = table.concat(t)
	end
	return c .. "|" .. m
end

local function setScreens(extra: any, on: boolean)
	for _, s in extra.screens do
		if on then
			s.Material = Enum.Material.Neon
			s.Color = Color3.fromRGB(28, 44, 70)
		else
			s.Material = Enum.Material.Glass
			s.Color = Color3.fromRGB(14, 14, 18)
		end
	end
end

local PROMPT_KEYS = {
	{ Enum.KeyCode.E, Enum.KeyCode.ButtonX },
	{ Enum.KeyCode.F, Enum.KeyCode.ButtonY },
	{ Enum.KeyCode.R, Enum.KeyCode.DPadRight },
}

local function prompt(H: any, b: any, def: any, what: string, action: string, slot: number, at: Vector3?)
	local hit = b.extra.hit
	if not hit then
		return
	end
	local host: Instance = hit
	if at then
		local a = Instance.new("Attachment")
		a.Name = "DPPrompt_" .. what
		a.WorldPosition = at
		a.Parent = hit
		host = a
	end
	local pr = Instance.new("ProximityPrompt")
	pr.Name = "DP_" .. what
	pr.ActionText = action
	pr.ObjectText = def.name
	pr.HoldDuration = 0
	pr.MaxActivationDistance = 9
	pr.RequiresLineOfSight = false
	pr.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	local keys = PROMPT_KEYS[slot] or PROMPT_KEYS[1]
	pr.KeyboardKeyCode = keys[1]
	pr.GamepadKeyCode = keys[2]
	pr:SetAttribute("DPAction", what)
	pr.Parent = host
	b.prompts[what] = pr
	pr.Triggered:Connect(function(player: Player)
		Homes.interact(H, b.u, what, player)
	end)
end

local function promptLabels(b: any, rec: any)
	local I = Text.INTERACT
	local on = rec.on ~= false
	local m = b.model
	local p = b.prompts
	if p.lamp then
		p.lamp.ActionText = if on then I.lampOff else I.lampOn
	end
	if p.fire then
		p.fire.ActionText = if on then I.fireOff else I.fireOn
	end
	if p.tv then
		p.tv.ActionText = if m:GetAttribute("On") == true then I.tvOff else I.tvOn
	end
	if p.music then
		p.music.ActionText = if m:GetAttribute("On") == true then I.musicOff else I.musicOn
	end
	if p.open then
		local def = Catalog.get(rec.i)
		local open = m:GetAttribute("Open") == true
		p.open.ActionText = if open then ((def and def.uses and def.uses.close) or I.close) else ((def and def.uses and def.uses.open) or I.open)
	end
end

local function addPrompts(H: any, b: any, rec: any)
	local def = Catalog.get(rec.i)
	if not def then
		return
	end
	local uses = Catalog.uses(rec.i)
	local I = Text.INTERACT
	local slot = 1
	if uses.sit or uses.lie then
		local s = b.extra.seats[1]
		prompt(H, b, def, "sit", if uses.lie and not uses.sit then I.lie else I.sit, slot, s and s.Position or nil)
		slot += 1
	end
	if uses.tv then
		prompt(H, b, def, "tv", I.tvOn, slot, nil)
		slot += 1
		prompt(H, b, def, "channel", I.channel, slot, nil)
		slot += 1
	elseif uses.fire then
		prompt(H, b, def, "fire", I.fireOn, slot, nil)
		slot += 1
	elseif uses.lamp then
		prompt(H, b, def, "lamp", I.lampOn, slot, nil)
		slot += 1
	end
	if uses.music and slot <= 3 then
		prompt(H, b, def, "music", I.musicOn, slot, nil)
		slot += 1
	end
	if uses.open and slot <= 3 then
		prompt(H, b, def, "open", uses.open, slot, nil)
		slot += 1
	end
	if uses.feed and slot <= 3 then
		prompt(H, b, def, "feed", I.feed, slot, nil)
		slot += 1
	end
	promptLabels(b, rec)
end

local function build(H: any, rec: any): any?
	local spec = Catalog.spec(rec.i, rec.c, rec.m)
	local def = Catalog.get(rec.i)
	if not spec or not def then
		return nil
	end
	local pivot = H.U.F * Geometry.pose(rec.x, rec.y, rec.z, rec.r)
	local model, extra = Spec.build(spec, pivot, nil, "Item_" .. tostring(rec.u), { seats = true, hit = true, id = rec.i, on = rec.on ~= false })
	model:SetAttribute("DecorUid", rec.u)
	model:SetAttribute("ItemId", rec.i)
	model:SetAttribute("OwnerUserId", H.ownerId)
	model:SetAttribute("PlaceKind", def.place)
	model:SetAttribute("Look", lookAttr(rec))
	model:SetAttribute("LampOn", rec.on ~= false)
	if #extra.screens > 0 then
		model:SetAttribute("On", false)
		model:SetAttribute("Channel", 1)
	end
	if extra.speaker then
		model:SetAttribute("Track", 1)
		model:SetAttribute("On", model:GetAttribute("On") or false)
	end
	if extra.tank then
		model:SetAttribute("TankCF", extra.tank.cf)
		model:SetAttribute("TankSize", extra.tank.size)
	end
	CollectionService:AddTag(model, Config.ITEM_TAG)
	local b = { u = rec.u, model = model, extra = extra, pivot = pivot, prompts = {}, lastUse = {} }
	H.built[rec.u] = b
	addPrompts(H, b, rec)
	model.Parent = H.folder
	return b
end

local function unbuild(H: any, uid: number)
	local b = H.built[uid]
	if b then
		H.built[uid] = nil
		if b.model then
			b.model:Destroy()
		end
	end
end

-- real lights within the home's budget (uid order), everything else glows Neon only
function Homes.relight(H: any)
	local caps = Config.caps(H.tierKey)
	local uids = {}
	for u in H.built do
		table.insert(uids, u)
	end
	table.sort(uids)
	local used = 0
	for _, u in uids do
		local b = H.built[u]
		local rec = H.recs[u]
		if b and rec then
			local on = rec.on ~= false
			local need = #b.extra.lights > 0
			local budgeted = on and need and used < caps.lights
			if budgeted then
				used += 1
			end
			Spec.setLamp(b.extra, on, budgeted)
			b.model:SetAttribute("LampOn", on)
			promptLabels(b, rec)
		end
	end
	H.lightsUsed = used
end

-- the uid index of the home record array
local function findIndex(H: any, uid: number): number?
	for i, rec in H.home.items do
		if rec.u == uid then
			return i
		end
	end
	return nil
end

function Homes.add(H: any, rec: any): boolean
	H.recs[rec.u] = rec
	table.insert(H.home.items, rec)
	Rules.add(H.idx, rec)
	local b = build(H, rec)
	Homes.relight(H)
	Homes.refreshBonus(H)
	return b ~= nil
end

function Homes.move(H: any, uid: number, fx: any)
	local rec = H.recs[uid]
	if not rec then
		return
	end
	rec.x, rec.y, rec.z, rec.r = fx.x, fx.y, fx.z, fx.r
	Rules.add(H.idx, rec)
	local b = H.built[uid]
	if b then
		local pivot = H.U.F * Geometry.pose(rec.x, rec.y, rec.z, rec.r)
		local open = b.model:GetAttribute("Open") == true
		if open then
			Spec.setPose(b.extra, b.pivot, false, false)
			b.model:SetAttribute("Open", false)
		end
		local ok = pcall(function()
			-- PivotTo moves every part (seats, prompts, light hosts) by the same delta
			local delta = pivot * b.pivot:Inverse()
			for _, d in b.model:GetDescendants() do
				if d:IsA("BasePart") then
					d.CFrame = delta * d.CFrame
				end
			end
		end)
		if not ok then
			unbuild(H, uid)
			build(H, rec)
		else
			b.pivot = pivot
		end
		promptLabels(b, rec)
	else
		build(H, rec)
	end
end

-- colours / materials changed: rebuild the model
function Homes.restyle(H: any, uid: number)
	local rec = H.recs[uid]
	if not rec then
		return
	end
	local b = H.built[uid]
	local tv = b and b.model:GetAttribute("On")
	unbuild(H, uid)
	local nb = build(H, rec)
	if nb and tv ~= nil then
		nb.model:SetAttribute("On", tv)
		setScreens(nb.extra, tv == true)
	end
	Homes.relight(H)
end

function Homes.removeItem(H: any, uid: number): any?
	local rec = H.recs[uid]
	if not rec then
		return nil
	end
	H.recs[uid] = nil
	local i = findIndex(H, uid)
	if i then
		table.remove(H.home.items, i)
	end
	Rules.remove(H.idx, uid)
	unbuild(H, uid)
	Homes.relight(H)
	Homes.refreshBonus(H)
	return rec
end

-------------------------------------------------------------------------------------------------
-- Interactions (ProximityPrompts; owner and guests inside this home)
-------------------------------------------------------------------------------------------------
function Homes.interact(H: any, uid: number, what: string, player: Player)
	local b = H.built[uid]
	local rec = H.recs[uid]
	if not b or not rec or not H.model.Parent then
		return
	end
	local inst = Host.inside(player)
	if not inst or inst.model ~= H.model then
		return
	end
	local now = os.clock()
	local key = what .. ":" .. player.UserId
	if b.lastUse[key] and now - b.lastUse[key] < Config.COOLDOWN.interact then
		return
	end
	b.lastUse[key] = now
	local m = b.model
	if what == "sit" then
		local ch = player.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
		if not hum or not hrp or hum.Health <= 0 or hum.Sit then
			return
		end
		local best, bd = nil, math.huge
		for _, s in b.extra.seats do
			if not s.Occupant then
				local d = (s.Position - (hrp :: BasePart).Position).Magnitude
				if d < bd then
					best, bd = s, d
				end
			end
		end
		if best then
			best:Sit(hum)
		end
	elseif what == "lamp" or what == "fire" then
		rec.on = if rec.on == false then nil else false
		Homes.relight(H)
		Store.dirty(H.owner)
		if onChanged then
			onChanged(H, "lamp")
		end
	elseif what == "tv" then
		local on = not (m:GetAttribute("On") == true)
		m:SetAttribute("On", on)
		setScreens(b.extra, on)
		promptLabels(b, rec)
	elseif what == "channel" then
		if m:GetAttribute("On") ~= true then
			m:SetAttribute("On", true)
			setScreens(b.extra, true)
		end
		local ch = (tonumber(m:GetAttribute("Channel")) or 1) % TV_CHANNELS + 1
		m:SetAttribute("Channel", ch)
		promptLabels(b, rec)
	elseif what == "music" then
		local on = not (m:GetAttribute("On") == true)
		m:SetAttribute("On", on)
		if on then
			m:SetAttribute("Track", (tonumber(m:GetAttribute("Track")) or 0) % 6 + 1)
		end
		promptLabels(b, rec)
	elseif what == "open" then
		local open = not (m:GetAttribute("Open") == true)
		m:SetAttribute("Open", open)
		Spec.setPose(b.extra, b.pivot, open, true)
		promptLabels(b, rec)
	elseif what == "feed" then
		m:SetAttribute("FedAt", workspace:GetServerTimeNow())
	end
end

-------------------------------------------------------------------------------------------------
-- Room finishes (server writes Color / Material; clients draw the patterns + light FX)
-------------------------------------------------------------------------------------------------
local function remember(H: any, p: BasePart)
	if not H.orig[p] then
		H.orig[p] = { color = p.Color, material = p.Material }
	end
end

local function restorePart(H: any, p: BasePart)
	local o = H.orig[p]
	if o then
		p.Color = o.color
		p.Material = o.material
		H.orig[p] = nil
	end
	H.expect[p] = nil
end

local function paint(H: any, parts: { BasePart }, kind: string, e: any)
	local def = Finish.def(kind, e.p)
	if not def then
		return
	end
	local a = Finish.colors(kind, e)
	local mat = Palette.enumOf(def.mat)
	for _, p in parts do
		if p.Parent then
			remember(H, p)
			p.Color = color3(a :: any)
			if mat then
				p.Material = mat
			end
			H.expect[p] = p.Color
		end
	end
end

local function watchHostTheme(H: any, room: string, kind: string, part: BasePart)
	local k = room .. "/" .. kind
	if H.watch[k] then
		return
	end
	H.watch[k] = part:GetPropertyChangedSignal("Color"):Connect(function()
		local exp = H.expect[part]
		if not exp or not Config.CLEAR_ON_HOST_THEME then
			return
		end
		local c = part.Color
		if math.abs(c.R - exp.R) + math.abs(c.G - exp.G) + math.abs(c.B - exp.B) < 0.01 then
			return
		end
		-- the life game's 🛠️ 인테리어 themed this room: its theme wins, ours is cleared
		local e = H.home.fin.rooms[room]
		if e then
			if kind == "wall" then
				e.w = nil
			else
				e.f = nil
			end
			if not e.w and not e.f then
				H.home.fin.rooms[room] = nil
			end
		end
		local th = H.U.themes[room]
		for _, p in (if th then th[kind] else {}) do
			H.orig[p] = nil
			H.expect[p] = nil
		end
		H.applied[k] = nil
		local conn = H.watch[k]
		H.watch[k] = nil
		if conn then
			conn:Disconnect()
		end
		Store.dirty(H.owner)
		Homes.publishFinish(H)
		if push then
			push(H.owner, { kind = "finish", fin = H.home.fin, cleared = room })
		end
	end)
end

function Homes.publishFinish(H: any)
	local ok, json = pcall(HttpService.JSONEncode, HttpService, H.home.fin)
	H.model:SetAttribute("DPFinish", if ok then json else "")
	H.model:SetAttribute("DPLight", H.home.fin.light or "")
end

function Homes.applyFinish(H: any)
	local fin = H.home.fin
	local wanted: { [string]: any } = {}
	for room, e in fin.rooms do
		if e.w then
			wanted[room .. "/wall"] = e.w
		end
		if e.f then
			wanted[room .. "/floor"] = e.f
		end
	end
	-- restore what is no longer wanted
	for k in H.applied do
		if not wanted[k] then
			local room, kind = string.match(k, "^(.-)/(%a+)$")
			local th = room and H.U.themes[room]
			if th then
				for _, p in th[kind] do
					restorePart(H, p)
				end
			end
			H.applied[k] = nil
			local conn = H.watch[k]
			H.watch[k] = nil
			if conn then
				conn:Disconnect()
			end
		end
	end
	for k, e in wanted do
		local room, kind = string.match(k, "^(.-)/(%a+)$")
		local th = room and H.U.themes[room]
		if th and kind and #th[kind] > 0 then
			paint(H, th[kind], kind, e)
			H.applied[k] = true
			watchHostTheme(H, room :: string, kind, th[kind][1])
		end
	end
	-- lighting preset: the home's lights + light parts
	local preset = fin.light and Finish.LIGHTS[fin.light] or nil
	for _, th in H.U.themes do
		for _, l in th.lights do
			if l.Parent then
				if not H.lightOrig[l] then
					H.lightOrig[l] = { color = l.Color, bright = l.Brightness }
				end
				local o = H.lightOrig[l]
				if preset and preset.light then
					l.Color = color3(preset.light)
					l.Brightness = o.bright * (preset.mult or 1)
				else
					l.Color = o.color
					l.Brightness = o.bright
				end
			end
		end
		for _, p in th.light do
			if p.Parent then
				if preset and preset.light then
					remember(H, p)
					p.Color = color3(preset.light)
				elseif H.orig[p] then
					restorePart(H, p)
				end
			end
		end
	end
	Homes.publishFinish(H)
end

-------------------------------------------------------------------------------------------------
-- Attach / detach home models
-------------------------------------------------------------------------------------------------
local function rescan(H: any)
	local U = Unit.scan(H.model)
	if U then
		H.U = U
		Path.invalidate(U)
	end
end

local function attach(model: Instance)
	if byModel[model] or not model:IsA("Model") then
		return
	end
	if model:GetAttribute("Staged") == true then
		return
	end
	local ownerId = model:GetAttribute("HomeOwnerId")
	if type(ownerId) ~= "number" or ownerId <= 0 then
		return
	end
	local owner = Players:GetPlayerByUserId(ownerId)
	if not owner then
		return
	end
	-- Housing parents the model before themes / slots are built (synchronously): one frame later it is complete
	local inst = nil
	for _ = 1, 40 do
		inst = Host.instOfModel(model)
		if inst or not model.Parent then
			break
		end
		task.wait(0.25)
	end
	if not inst or not model.Parent then
		return
	end
	local data = Store.wait(owner, 40)
	if not data or not model.Parent then
		return
	end
	local U = Unit.scan(model)
	if not U then
		warn("[GwangalliDecorPlus] could not read home " .. model.Name)
		return
	end
	local folder = model:FindFirstChild(Config.FOLDER_NAME)
	if folder then
		folder:ClearAllChildren()
	else
		folder = Instance.new("Folder")
		folder.Name = Config.FOLDER_NAME
		folder.Parent = model
	end
	local home, moved, sold = Homes.homeData(owner, data, inst.listingId)
	local H: any = {
		model = model,
		inst = inst,
		owner = owner,
		ownerId = ownerId,
		listingId = inst.listingId,
		tierKey = inst.tierKey,
		U = U,
		idx = Rules.newIndex(),
		folder = folder,
		data = data,
		home = home,
		recs = {},
		built = {},
		orig = {},
		expect = {},
		lightOrig = {},
		applied = {},
		watch = {},
		conns = {},
		lightsUsed = 0,
	}
	byModel[model] = H
	byOwner[ownerId] = H
	for i, rec in home.items do
		H.recs[rec.u] = rec
		Rules.add(H.idx, rec)
		build(H, rec)
		if i % 40 == 0 then
			task.wait()
			if not model.Parent then
				return
			end
		end
	end
	Homes.relight(H)
	Homes.applyFinish(H)
	Homes.refreshBonus(H)
	-- slot furniture swaps (🛠️ 인테리어) change the fixed geometry: rescan (debounced)
	local furniture = model:FindFirstChild("Furniture")
	if furniture then
		local pending = false
		local function dirty()
			if pending then
				return
			end
			pending = true
			task.delay(0.5, function()
				pending = false
				if byModel[model] == H then
					rescan(H)
				end
			end)
		end
		table.insert(H.conns, furniture.DescendantAdded:Connect(dirty))
		table.insert(H.conns, furniture.DescendantRemoving:Connect(dirty))
	end
	table.insert(H.conns, model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then
			Homes.detach(model)
		end
	end))
	if moved > 0 or sold > 0 then
		Store.saveSoon(owner)
		Host.notify(owner, "📦 이사 정리", string.format("이전 집의 자유 배치 가구 %d개를 창고로 옮겼어요%s", moved, if sold > 0 then (" · 초과분 " .. Text.won(sold) .. " 판매") else ""))
	end
	if push then
		push(owner, { kind = "home", ready = true, ownerId = ownerId })
	end
end

function Homes.detach(model: Instance)
	local H = byModel[model]
	if not H then
		return
	end
	byModel[model] = nil
	if byOwner[H.ownerId] == H then
		byOwner[H.ownerId] = nil
	end
	for _, c in H.conns do
		c:Disconnect()
	end
	for _, c in H.watch do
		c:Disconnect()
	end
	if push and H.owner.Parent then
		push(H.owner, { kind = "close", code = "exitHome" })
	end
end

function Homes.start()
	task.spawn(function()
		local container = workspace:FindFirstChild("GwangalliHomeInstances")
		while not container do
			container = workspace:WaitForChild("GwangalliHomeInstances", 30)
		end
		local c = container :: Instance
		c.ChildAdded:Connect(function(m)
			task.defer(attach, m)
		end)
		c.ChildRemoved:Connect(function(m)
			Homes.detach(m)
		end)
		for _, m in c:GetChildren() do
			task.spawn(attach, m)
		end
	end)
end

-- re-attach the owner's home (data reloaded / first discovery)
function Homes.ensure(p: Player)
	local container = workspace:FindFirstChild("GwangalliHomeInstances")
	if not container then
		return
	end
	for _, m in container:GetChildren() do
		if m:GetAttribute("HomeOwnerId") == p.UserId and not byModel[m] then
			task.spawn(attach, m)
		end
	end
end

function Homes.dropOwner(p: Player)
	local H = byOwner[p.UserId]
	if H then
		Homes.detach(H.model)
	end
end

return Homes
