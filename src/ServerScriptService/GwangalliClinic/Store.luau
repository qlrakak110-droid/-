-- GwangalliClinic/Store: persistence of the clinic add-on (its own DataStore; the game's profile drops
-- unknown keys, so nothing of ours lives there).
--   GwangalliClinic_v1  key u_<UserId>:
--     chart   { no = "GA-0012345", first, visits, last, lastDx }       진료카드 (초진 / 재진)
--     history { { t, dept, dx, code, plan, paid } ... <= 12 }          진료 기록
--     meds    { kind, name, items, times, total, taken, nextAt, untilT } | nil   복약 중인 약
--     report  { t, grade, ... } | nil                                   마지막 건강검진 결과지
--     mirror  { illness?, risk, debt, t } | nil                         Health 상태 사본 (재접속 복원)
--     vac     { untilT } | nil                                          예방접종 면역
--     work    { job, sec, night }                                       쉬지 않고 일한 기록 (진단 "원인")
--     ward    { lastRest, lastCall, lastHappy }   daily { day, checkup }
-- UpdateAsync with retries, autosave of dirty entries every 90 s, save on leave / server close.
-- Memory-only when DataStores are unavailable (Studio without API access) or the game's profile is
-- memory-only for that player (Profiles.persistent == false).

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Store = {}

local K: any
local S: any
local C: any

local ds: any = nil
local data: { [Player]: any } = {}
local dirty: { [Player]: boolean } = {}
local loaded: { [Player]: boolean } = {}
local loadedSignal = Instance.new("BindableEvent")

local MAX_HISTORY = 12

local function default(): any
	return {
		v = 1,
		chart = nil,
		history = {},
		meds = nil,
		report = nil,
		mirror = nil,
		vac = nil,
		work = { job = "", sec = 0, night = 0 },
		ward = { lastRest = 0, lastCall = 0, lastHappy = 0 },
		daily = { day = 0, checkup = 0 },
	}
end

local function num(v: any, lo: number, hi: number, def: number): number
	local n = tonumber(v)
	if not n or n ~= n then
		return def
	end
	return math.clamp(n, lo, hi)
end

local function str(v: any, maxLen: number, def: string): string
	if type(v) ~= "string" then
		return def
	end
	return string.sub(v, 1, maxLen)
end

local function sanitize(raw: any): any
	local out = default()
	if type(raw) ~= "table" then
		return out
	end
	if type(raw.chart) == "table" and type(raw.chart.no) == "string" then
		out.chart = {
			no = str(raw.chart.no, 16, "GA-0000000"),
			first = num(raw.chart.first, 0, 4e9, 0),
			visits = math.floor(num(raw.chart.visits, 0, 1e6, 0)),
			last = num(raw.chart.last, 0, 4e9, 0),
			lastDx = str(raw.chart.lastDx, 24, ""),
		}
	end
	if type(raw.history) == "table" then
		for _, e in raw.history do
			if type(e) == "table" and #out.history < MAX_HISTORY then
				table.insert(out.history, {
					t = num(e.t, 0, 4e9, 0),
					dept = str(e.dept, 8, "im"),
					dx = str(e.dx, 48, ""),
					code = str(e.code, 8, ""),
					plan = str(e.plan, 60, ""),
					paid = math.floor(num(e.paid, 0, 1e9, 0)),
				})
			end
		end
	end
	if type(raw.meds) == "table" and type(raw.meds.kind) == "string" then
		local items = {}
		if type(raw.meds.items) == "table" then
			for _, it in raw.meds.items do
				if type(it) == "string" and #items < 4 then
					table.insert(items, string.sub(it, 1, 40))
				end
			end
		end
		out.meds = {
			kind = str(raw.meds.kind, 16, ""),
			name = str(raw.meds.name, 40, "처방약"),
			items = items,
			times = str(raw.meds.times, 40, ""),
			total = math.floor(num(raw.meds.total, 1, 9, 3)),
			taken = math.floor(num(raw.meds.taken, 0, 9, 0)),
			nextAt = num(raw.meds.nextAt, 0, 4e9, 0),
			untilT = num(raw.meds.untilT, 0, 4e9, 0),
		}
		if out.meds.taken >= out.meds.total then
			out.meds = nil
		end
	end
	if type(raw.report) == "table" and type(raw.report.grade) == "string" then
		out.report = raw.report -- written only by Checkup (server values), size-capped there
	end
	if type(raw.mirror) == "table" then
		out.mirror = raw.mirror -- validated again by Bridge.restoreMirror
	end
	if type(raw.vac) == "table" then
		out.vac = { untilT = num(raw.vac.untilT, 0, 4e9, 0) }
	end
	if type(raw.work) == "table" then
		out.work = { job = str(raw.work.job, 32, ""), sec = num(raw.work.sec, 0, 1e7, 0), night = num(raw.work.night, 0, 1e7, 0) }
	end
	if type(raw.ward) == "table" then
		out.ward = { lastRest = num(raw.ward.lastRest, 0, 4e9, 0), lastCall = num(raw.ward.lastCall, 0, 4e9, 0), lastHappy = num(raw.ward.lastHappy, 0, 4e9, 0) }
	end
	if type(raw.daily) == "table" then
		out.daily = { day = math.floor(num(raw.daily.day, 0, 1e7, 0)), checkup = math.floor(num(raw.daily.checkup, 0, 99, 0)) }
	end
	return out
end

local function key(player: Player): string
	return "u_" .. tostring(player.UserId)
end

local function useStore(player: Player): boolean
	if not ds then
		return false
	end
	if player.UserId <= 0 then
		return false
	end
	return K.Bridge.persistent(player)
end

local function retry(fn: () -> any): (boolean, any)
	local lastErr = nil
	for i = 1, 3 do
		local ok, res = pcall(fn)
		if ok then
			return true, res
		end
		lastErr = res
		task.wait(1.5 * i)
	end
	return false, lastErr
end

function Store.get(player: Player): any
	local d = data[player]
	if not d then
		d = default()
		data[player] = d
	end
	return d
end

function Store.isLoaded(player: Player): boolean
	return loaded[player] == true
end

-- yields until the player's clinic data is loaded (or `timeout`)
function Store.wait(player: Player, timeout: number): any
	local t0 = os.clock()
	while not loaded[player] and player.Parent == Players and os.clock() - t0 < timeout do
		task.wait(0.2)
	end
	return Store.get(player)
end

function Store.markDirty(player: Player)
	dirty[player] = true
end

function Store.onLoaded(fn: (Player, any) -> ())
	loadedSignal.Event:Connect(fn)
end

local function load(player: Player)
	local d = default()
	if useStore(player) then
		local ok, raw = retry(function()
			return ds:GetAsync(key(player))
		end)
		if ok then
			d = sanitize(raw)
		else
			warn("[GwangalliClinic] load failed for", player.Name, raw, "- this session is memory-only")
		end
	end
	if player.Parent ~= Players then
		return
	end
	data[player] = d
	loaded[player] = true
	loadedSignal:Fire(player, d)
end

local function save(player: Player): boolean
	local d = data[player]
	if not d or not loaded[player] then
		return true
	end
	-- refresh the health mirror right before saving
	if C.PersistHealth then
		local m = K.Bridge.mirror(player)
		if m then
			if d.mirrorPinned and d.mirror then
				m.debt = math.max(m.debt or 0, tonumber(d.mirror.debt) or 0)
			end
			d.mirror = m
		end
	end
	d.mirrorPinned = nil
	if not useStore(player) then
		dirty[player] = nil
		return true
	end
	local snapshot = table.clone(d)
	local ok, err = retry(function()
		return ds:UpdateAsync(key(player), function(old: any)
			local o = type(old) == "table" and old or nil
			-- keep the larger visit counter if another server wrote meanwhile
			if o and type(o.chart) == "table" and type(snapshot.chart) == "table" then
				snapshot.chart.visits = math.max(tonumber(o.chart.visits) or 0, snapshot.chart.visits or 0)
			end
			return snapshot
		end)
	end)
	if ok then
		dirty[player] = nil
		return true
	end
	warn("[GwangalliClinic] save failed for", player.Name, err)
	return false
end
Store.save = save

-- 진료카드 번호 (처음 오면 만듦). Returns the chart and whether it was just created.
function Store.chart(player: Player): (any, boolean)
	local d = Store.get(player)
	if d.chart then
		return d.chart, false
	end
	local n = (player.UserId % 9000000) + 1000000
	d.chart = { no = string.format("GA-%07d", n), first = os.time(), visits = 0, last = 0, lastDx = "" }
	Store.markDirty(player)
	return d.chart, true
end

-- keeps a debt in our own mirror too (used when the game's profile is already released on leave)
function Store.addMirrorDebt(player: Player, amount: number)
	if amount <= 0 then
		return
	end
	local d = Store.get(player)
	d.mirror = d.mirror or { risk = 0, debt = 0, t = os.time() }
	d.mirror.debt = math.max(0, math.floor(tonumber(d.mirror.debt) or 0)) + math.floor(amount)
	d.mirror.t = os.time()
	d.mirrorPinned = true
	Store.markDirty(player)
end

function Store.addHistory(player: Player, entry: any)
	local d = Store.get(player)
	table.insert(d.history, 1, entry)
	while #d.history > MAX_HISTORY do
		table.remove(d.history)
	end
	Store.markDirty(player)
end

function Store.init(k: any)
	K = k
	S = k.S
	C = S.Config
	local studio = RunService:IsStudio()
	if not (studio and C.StudioMemoryOnly) and game.PlaceId ~= 0 then
		local ok, store = pcall(function()
			return DataStoreService:GetDataStore(S.NAMES.Store)
		end)
		if ok then
			ds = store
		else
			warn("[GwangalliClinic] DataStore unavailable, memory-only:", store)
		end
	end
	for _, p in Players:GetPlayers() do
		task.spawn(load, p)
	end
	Players.PlayerAdded:Connect(function(p)
		load(p)
	end)
	Players.PlayerRemoving:Connect(function(p)
		-- deferred: the visit's leave handler (unpaid bill -> debt) runs first
		task.defer(function()
			pcall(save, p)
			data[p] = nil
			dirty[p] = nil
			loaded[p] = nil
		end)
	end)
	task.spawn(function()
		while true do
			task.wait(90)
			for p in dirty do
				if p.Parent == Players then
					task.spawn(save, p)
				else
					dirty[p] = nil
				end
			end
		end
	end)
	game:BindToClose(function()
		local n = 0
		for p in data do
			n += 1
			task.spawn(function()
				pcall(save, p)
				n -= 1
			end)
		end
		local t0 = os.clock()
		while n > 0 and os.clock() - t0 < 20 do
			task.wait(0.1)
		end
	end)
end

return Store
