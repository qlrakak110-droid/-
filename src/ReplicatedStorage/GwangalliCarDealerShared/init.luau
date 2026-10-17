-- GwangalliCarDealerShared: the contract of GwangalliCarDealer (광안 오토 영업 상담 → 전체 차량 카탈로그 →
-- 상세 · 시승 · 계약 → 출고). Required by the server Script ServerScriptService.GwangalliCarDealer and the
-- LocalScript StarterPlayerScripts.GwangalliCarDealer. Pure data + helpers: nothing is created at require
-- time and nothing yields (the GS / VS / Progress loaders wait only when called).
--
--   S.Config S.Util S.Catalog S.Lines        child modules
--   S.NAMES                                  instance / remote / attribute names
--   S.GS(timeout?) -> GwangalliGarageShared? the garage's prices / models / colours / 할부 (lazy, pcall)
--   S.VS(timeout?) -> GwangalliVehiclesShared? handling per kind (top speed, drive ...)
--   S.P(timeout?)  -> GwangalliProgressShared? level perks (P.perk)
--   S.usedRate(level) -> number              레벨 혜택 중고차 할인율 (0 when locked)
--   S.monthKey(unix?) -> "2026-10"           한국 시간 기준 달 (이달의 특가)
--
-- REMOTES (ReplicatedStorage.GwangalliCarDealerRemotes, created by the server, parented last):
--   Request RemoteFunction (op, payload?) -> { ok, code, message?, ... }
--     hello {npc} · catalog · buy {entry, color, loan, nonce, trade?} · sell {id} · testdrive {entry, color}
--     · endtest · rent · deliver {id} · wish {entry, on} · waypoint
--   Event RemoteEvent server -> client { k = "test" | "toast" | "state", ... }
-- WORLD: Workspace.GwangalliCarDealer (server: NPC rigs + prompt anchors), Workspace.GwangalliCarDealerLocal
--   (client: route beacons), ReplicatedStorage.GwangalliCarDealerPreviews (server-built stripped car models
--   for the 3D previews, attribute Ready).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local S = {}
S.VERSION = "1.0.0"

S.Config = require(script:WaitForChild("Config"))
S.Util = require(script:WaitForChild("Util"))
S.Catalog = require(script:WaitForChild("Catalog"))
S.Lines = require(script:WaitForChild("Lines"))

S.NAMES = {
	Remotes = "GwangalliCarDealerRemotes",
	Request = "Request",
	Event = "Event",
	World = "GwangalliCarDealer", -- Workspace folder (server)
	Local = "GwangalliCarDealerLocal", -- Workspace folder (client-only parts)
	Previews = "GwangalliCarDealerPreviews", -- ReplicatedStorage folder (server-built preview models)
	OpenEvent = "GwangalliCarDealerOpen", -- BindableEvent on the LocalPlayer (phone apps / other scripts)
	TagNpc = "GwCarDealerNpc", -- our NPC models and prompt anchors
	AttrNpc = "GwCarDealerNpc", -- NPC id on NPC models / anchors / prompts
	AttrDealer = "GwDealerNpc", -- true on every rig we handle (ours and hooked map staff)
	AttrName = "DealerName",
	AttrRole = "DealerRole",
	AttrVoice = "DealerVoice",
	AttrIcon = "DealerIcon",
	AttrOurs = "DealerOwnRig", -- true: our own rig (the client animates it); false: a hooked map figure
	AttrPreviewKey = "PreviewKey",
	AttrForwardOk = "PreviewForward",
	Garage = { Remotes = "GwangalliRemotes", Event = "GarageEvent", Api = "GwangalliGarageAPI", Open = "GwangalliGarageOpen" },
}

local cache: { [string]: any } = {}

local function load(name: string, timeout: number?): any
	local hit = cache[name]
	if hit ~= nil then
		return if hit == false then nil else hit
	end
	local m = ReplicatedStorage:FindFirstChild(name)
	if not m and (timeout or 0) > 0 then
		m = ReplicatedStorage:WaitForChild(name, timeout)
	end
	if not (m and m:IsA("ModuleScript")) then
		if (timeout or 0) > 0 then
			cache[name] = false -- waited and gave up: do not wait again
		end
		return nil
	end
	local ok, res = pcall(require, m)
	if ok and type(res) == "table" then
		cache[name] = res
		return res
	end
	warn("[GwangalliCarDealer] could not load " .. name .. ": " .. tostring(res))
	cache[name] = false
	return nil
end

function S.GS(timeout: number?): any
	return load("GwangalliGarageShared", timeout)
end

function S.VS(timeout: number?): any
	return load("GwangalliVehiclesShared", timeout)
end

function S.P(timeout: number?): any
	return load("GwangalliProgressShared", timeout)
end

-- 레벨 혜택 "중고차 5% 할인" (GwangalliProgressShared perk used_car_discount; Config fallback when the
-- progress module is missing). 0 when the level has not unlocked it.
function S.usedRate(level: any): number
	local lv = if type(level) == "number" and level == level then level else 1
	local P = S.P(0)
	if P and type(P.perk) == "function" then
		local ok, v = pcall(P.perk, lv, "used_car_discount")
		if ok then
			return if type(v) == "number" and v > 0 and v < 0.5 then v else 0
		end
	end
	local fb = S.Config.USED_DISCOUNT_FALLBACK
	return if lv >= fb.level then fb.rate else 0
end

-- Is a level perk (car_loan / luxury_new) unlocked? (true when the progress module is missing)
function S.hasPerk(level: any, id: string): boolean
	local lv = if type(level) == "number" and level == level then level else 1
	local P = S.P(0)
	if P and type(P.perk) == "function" then
		local ok, v = pcall(P.perk, lv, id)
		if ok then
			return v ~= false and v ~= nil and v ~= 0
		end
	end
	return true
end

-- The level that unlocks a perk (nil when unknown).
function S.perkLevel(id: string): number?
	local P = S.P(0)
	if P and type(P.UNLOCKS) == "table" then
		for _, u in P.UNLOCKS do
			if type(u) == "table" and u.id == id and type(u.level) == "number" then
				return u.level
			end
		end
	end
	return nil
end

-- "YYYY-MM" in Korea time (UTC+9): the month of 이달의 특가.
function S.monthKey(unix: number?): string
	local t = os.date("!*t", math.floor((unix or os.time()) + 9 * 3600)) :: any
	return string.format("%04d-%02d", t.year, t.month)
end

-- Days left in that month (Korea time), 1 on the last day.
function S.daysLeft(unix: number?): number
	local t = os.date("!*t", math.floor((unix or os.time()) + 9 * 3600)) :: any
	local dim = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
	local d = dim[t.month] or 30
	if t.month == 2 and (t.year % 4 == 0 and (t.year % 100 ~= 0 or t.year % 400 == 0)) then
		d = 29
	end
	return math.max(1, d - t.day + 1)
end

return S
