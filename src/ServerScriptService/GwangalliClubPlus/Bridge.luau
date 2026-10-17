-- GwangalliClubPlus.Bridge: the only module that knows the existing club systems (server).
--   * ReplicatedStorage.GwangalliClubShow attributes (JSON, written by GwangalliClub.server):
--       Show    one write per bottle show when it begins ({ id, tier, item, label, table, owner, name,
--               staff, at, arriveAt, endAt, ... }; { id = 0 } at boot)
--       Tables  { [tableId] = { owner, name, tier, set, item, at, untilT } } (at = staff arrival;
--               a new `at` without a matching Show = an order served without a show)
--       Booking the 합석 이벤트 ({ id = 0 } when none)
--   * ServerStorage.ClubShowHook (BindableFunction): inClub / tableInfo / tables
--   * ReplicatedStorage.GwangalliClubRanking (optional, GwangalliBuildings): Top attribute
--   * player attributes ClubOceanWristbandUntil, GwJourneyClub
-- Order events: Bridge.onOrder(fn(evt)) with
--   evt = { key, source = "show"|"direct", table, u, n, item, label, icon, tier (menu 1..5), price,
--           at (LED start, server time), arriveAt, endAt, staff }

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bridge = {}

local C: any
local S: any
local ShowShared: any = nil
local clubFolder: Instance? = nil
local rankingFolder: Instance? = nil

local orderFns: { (any) -> () } = {}
local bookingFns: { (any) -> () } = {}
local rankingFns: { () -> () } = {}

local seen: { [string]: number } = {} -- dedupe key -> server time first seen
local tablesAt: { [string]: number } = {}
local tablesNow: { [string]: any } = {}
local primed = false
local lastBookingId: any = nil
local currentBooking: any = nil

local function fire(list: { (any) -> () }, arg: any)
	for _, fn in list do
		task.spawn(function()
			local ok, err = pcall(fn, arg)
			if not ok then
				warn("[GwangalliClubPlus] bridge listener failed:", err)
			end
		end)
	end
end

local function mark(key: string): boolean
	if seen[key] then
		return false
	end
	seen[key] = C.now()
	return true
end

local function menuItem(id: any): any?
	if ShowShared and type(ShowShared.item) == "function" then
		local ok, it = pcall(ShowShared.item, id)
		if ok and type(it) == "table" then
			return it
		end
	end
	return nil
end
local function allAges(): boolean
	if ShowShared and type(ShowShared.allAges) == "function" then
		local ok, v = pcall(ShowShared.allAges)
		if ok and type(v) == "boolean" then
			return v
		end
	end
	return true
end
local function labelOf(item: any): string
	if not item then
		return "음료 세트"
	end
	if ShowShared and type(ShowShared.label) == "function" then
		local ok, s = pcall(ShowShared.label, item, allAges())
		if ok and type(s) == "string" then
			return s
		end
	end
	return tostring(item.labelAA or item.label or "음료 세트")
end
local function iconOf(item: any): string
	if not item then
		return "✨"
	end
	if ShowShared and type(ShowShared.icon) == "function" then
		local ok, s = pcall(ShowShared.icon, item, allAges())
		if ok and type(s) == "string" then
			return s
		end
	end
	return "✨"
end

local function showEvent(rec: any)
	if type(rec) ~= "table" or type(rec.id) ~= "number" or rec.id <= 0 or type(rec.at) ~= "number" or rec.at <= 0 then
		return
	end
	if type(rec.table) ~= "string" or type(rec.owner) ~= "number" then
		return
	end
	if not mark(string.format("show:%d@%.2f", rec.id, rec.at)) then
		return
	end
	local item = menuItem(rec.item)
	fire(orderFns, {
		key = string.format("show:%d@%.2f", rec.id, rec.at),
		source = "show",
		table = rec.table,
		u = rec.owner,
		n = if type(rec.name) == "string" then rec.name else "손님",
		item = rec.item,
		label = if type(rec.label) == "string" then rec.label else labelOf(item),
		icon = iconOf(item),
		tier = if type(rec.tier) == "number" then rec.tier else (item and item.tier or 1),
		price = item and item.price or 0,
		at = rec.at,
		arriveAt = if type(rec.arriveAt) == "number" then rec.arriveAt else rec.at + 8,
		endAt = if type(rec.endAt) == "number" then rec.endAt else rec.at + 30,
		staff = if type(rec.staff) == "number" then rec.staff else 1,
	})
end

local function onShow()
	if clubFolder then
		showEvent(S.decode(clubFolder:GetAttribute("Show")))
	end
end

local function onTables()
	if not clubFolder then
		return
	end
	local t = S.decode(clubFolder:GetAttribute("Tables"))
	if type(t) ~= "table" then
		primed = true
		return
	end
	tablesNow = t
	local sh = S.decode(clubFolder:GetAttribute("Show"))
	for id, e in t do
		if type(id) == "string" and type(e) == "table" and type(e.at) == "number" and e.at > 0 and tablesAt[id] ~= e.at then
			tablesAt[id] = e.at
			if primed then
				if type(sh) == "table" and sh.table == id and type(sh.arriveAt) == "number" and math.abs(sh.arriveAt - e.at) < 0.05 then
					-- the show's own write (Show is published before Tables; dedupe covers either order)
					showEvent(sh)
				elseif type(e.owner) == "number" then
					local key = string.format("tbl:%s@%.2f", id, e.at)
					if mark(key) then
						local item = menuItem(e.item or e.set)
						local now = C.now()
						fire(orderFns, {
							key = key,
							source = "direct",
							table = id,
							u = e.owner,
							n = if type(e.name) == "string" then e.name else "손님",
							item = e.item or e.set,
							label = labelOf(item),
							icon = iconOf(item),
							tier = item and item.tier or (if type(e.tier) == "number" then e.tier else 1),
							price = item and item.price or 0,
							at = now + 0.4,
							arriveAt = e.at,
							endAt = e.at + 6,
							staff = item and item.staff or 1,
						})
					end
				end
			end
		end
	end
	for id in tablesAt do
		if t[id] == nil then
			tablesAt[id] = nil
		end
	end
	primed = true
end

local function onBooking()
	if not clubFolder then
		return
	end
	local b = S.decode(clubFolder:GetAttribute("Booking"))
	local id = if type(b) == "table" then b.id else nil
	currentBooking = if type(id) == "number" and id > 0 then b else nil
	if type(id) == "number" and id > 0 and id ~= lastBookingId and lastBookingId ~= nil then
		fire(bookingFns, b)
	end
	if id ~= nil then
		lastBookingId = id
	end
end

local function connectRanking(f: Instance)
	rankingFolder = f
	f:GetAttributeChangedSignal("Top"):Connect(function()
		for _, fn in rankingFns do
			task.spawn(pcall, fn)
		end
	end)
	for _, fn in rankingFns do
		task.spawn(pcall, fn)
	end
end

function Bridge.init(ctx: any)
	C = ctx
	S = ctx.S
	task.spawn(function()
		local f = ReplicatedStorage:WaitForChild(S.Names.ClubFolder, 300)
		if not f then
			warn("[GwangalliClubPlus] ReplicatedStorage.GwangalliClubShow not found: order / 합석 events are off")
			return
		end
		local sm = ReplicatedStorage:FindFirstChild(S.Names.ShowShared)
		if sm and sm:IsA("ModuleScript") then
			local ok, mod = pcall(require, sm)
			if ok and type(mod) == "table" then
				ShowShared = mod
			end
		end
		clubFolder = f
		-- prime: the state found at start is not new
		local sh = S.decode(f:GetAttribute("Show"))
		if type(sh) == "table" and type(sh.id) == "number" and sh.id > 0 and type(sh.at) == "number" then
			mark(string.format("show:%d@%.2f", sh.id, sh.at))
		end
		onTables()
		onBooking()
		if lastBookingId == nil then
			lastBookingId = 0
		end
		f:GetAttributeChangedSignal("Show"):Connect(onShow)
		f:GetAttributeChangedSignal("Tables"):Connect(onTables)
		f:GetAttributeChangedSignal("Booking"):Connect(onBooking)
	end)
	task.spawn(function()
		local f = ReplicatedStorage:FindFirstChild(S.Names.Ranking) or ReplicatedStorage:WaitForChild(S.Names.Ranking, 120)
		if f then
			connectRanking(f)
		end
	end)
	-- the dedupe set stays small
	task.spawn(function()
		while true do
			task.wait(120)
			local cut = C.now() - 900
			for k, t in seen do
				if t < cut then
					seen[k] = nil
				end
			end
		end
	end)
end

function Bridge.onOrder(fn: (any) -> ())
	table.insert(orderFns, fn)
end
function Bridge.onBooking(fn: (any) -> ())
	table.insert(bookingFns, fn)
end
function Bridge.onRankingTop(fn: () -> ())
	table.insert(rankingFns, fn)
end

function Bridge.booking(): any?
	return currentBooking
end

-- current tables with a live owner: { [id] = { owner, name, tier, item, untilT } }
function Bridge.tables(): { [string]: any }
	local out = {}
	local now = C.now()
	for id, e in tablesNow do
		if type(e) == "table" and type(e.owner) == "number" and (type(e.untilT) ~= "number" or e.untilT <= 0 or e.untilT > now) then
			out[id] = e
		end
	end
	return out
end

function Bridge.hasRanking(): boolean
	return rankingFolder ~= nil and rankingFolder.Parent ~= nil
end
-- ClubRanking's { night, list = { { u, n, t } }, king } or nil
function Bridge.rankingTop(): any?
	if not Bridge.hasRanking() then
		return nil
	end
	local top = S.decode((rankingFolder :: Instance):GetAttribute("Top"))
	return if type(top) == "table" and type(top.list) == "table" then top else nil
end

-- inside a club room: the club's hook first, then the ClubZone boxes (not the street "Near" zone)
local function inZoneParts(pos: Vector3): boolean
	for _, z in CollectionService:GetTagged("ClubZone") do
		if z:IsA("BasePart") and not string.find(z.Name, "Near", 1, true) then
			local lp = z.CFrame:PointToObjectSpace(pos)
			local h = z.Size * 0.5
			if math.abs(lp.X) <= h.X and math.abs(lp.Y) <= h.Y + 2 and math.abs(lp.Z) <= h.Z then
				return true
			end
		end
	end
	return false
end
function Bridge.inClub(p: Player): boolean
	if C.hasHook() then
		local v = C.hook("inClub", p)
		if type(v) == "boolean" then
			return v
		end
	end
	local r = C.root(p)
	return r ~= nil and inZoneParts(r.Position)
end

function Bridge.wristband(p: Player): boolean
	if not clubFolder and not C.hasHook() then
		return true -- no door system in this place
	end
	local untilT = p:GetAttribute("ClubOceanWristbandUntil")
	return type(untilT) == "number" and untilT == untilT and untilT > C.now()
end

return Bridge
