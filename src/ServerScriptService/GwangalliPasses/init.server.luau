-- GwangalliPasses (Script, ServerScriptService): three Robux game passes as one drop-in add-on.
--   #1 프리미엄 차고  Garage.luau   premium cars + 원격 차고 (정비소-only calls without it) + 출장 정비
--   #3 편의 패스      Waits.luau    jail / KO / respawn waits x0.5      Market.luau  phone 블랙마켓 (Arms shop)
--   #4 과시 패스      Finish.luau   KO 피니시 이펙트   Plate.luau  custom plates   NeonName.luau  neon nickname
--   Ownership.luau (who owns what), Data.luau (DataStore), Net.luau (remotes), Api.luau (other add-ons).
-- No place script is edited: existing systems are reached through their public APIs (ServerStorage
-- GwangalliVehiclesAPI / GwangalliGarageAPI / GwangalliGameplayAPI / GwangalliArmsAPI / GwangalliCrimeBus) and a
-- few module-table function wraps (Spawn.template, Spawn.callOwned, Jail.begin, KO.koHelp). A missing system
-- only switches its feature off (one warning; the app shows "준비 중").

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local P = require(ReplicatedStorage:WaitForChild("GwangalliPassesShared"))

local ctx: any = {
	P = P,
	Config = P.Config,
	Util = require(script:WaitForChild("Util")),
}
ctx.Net = require(script:WaitForChild("Net"))
ctx.Ownership = require(script:WaitForChild("Ownership"))
ctx.Data = require(script:WaitForChild("Data"))
ctx.Garage = require(script:WaitForChild("Garage"))
ctx.Waits = require(script:WaitForChild("Waits"))
ctx.Market = require(script:WaitForChild("Market"))
ctx.Plate = require(script:WaitForChild("Plate"))
ctx.NeonName = require(script:WaitForChild("NeonName"))
ctx.Finish = require(script:WaitForChild("Finish"))
local Api = require(script:WaitForChild("Api"))
local Util = ctx.Util
local Lines = P.Lines

local function readyMap(): { [string]: boolean }
	return {
		garage = ctx.Garage.ready == true,
		gate = ctx.Garage.gateReady == true,
		jail = ctx.Waits.jailReady == true,
		ko = ctx.Waits.koReady == true,
		market = ctx.Market.ready == true,
		kofx = ctx.Finish.ready == true,
		plate = true,
		neon = true,
	}
end
function ctx.refreshReady()
	ctx.Net.setReady(readyMap())
end

ctx.Net.start(ctx)
ctx.Ownership.start(ctx)
ctx.Data.start(ctx)
ctx.Plate.start(ctx)
ctx.NeonName.start(ctx)
ctx.Waits.start(ctx)
Api.start(ctx)

---------------------------------------------------------------------------------------------------
-- remote ops (payload is a sanitized shallow copy: strings / numbers / booleans only)
---------------------------------------------------------------------------------------------------
local Net = ctx.Net
local Own = ctx.Ownership

Net.on("state", 0.25, function(player: Player)
	local prof = ctx.Data.get(player)
	local avail, ids, prices = {}, {}, {}
	for _, key in P.ORDER do
		avail[key] = P.available(key)
		ids[key] = P.idOf(key)
		prices[key] = P.Config.PASSES[key].Price
	end
	return {
		ok = true,
		owned = Own.map(player),
		available = avail,
		ids = ids,
		prices = prices,
		studio = game:GetService("RunService"):IsStudio(),
		ready = readyMap(),
		settings = {
			plate = prof.plate and prof.plate.text,
			plateStyle = prof.plate and prof.plate.style,
			neon = player:GetAttribute(P.Attr.Neon),
			koFx = player:GetAttribute(P.Attr.KoFx),
		},
		loaded = ctx.Data.isLoaded(player),
	}
end)

Net.on("garage", 0.4, function(player: Player)
	return ctx.Garage.status(player)
end)

Net.on("summon", 1, function(player: Player, p: any)
	-- the result carries the car Model: the client marks it (Drive.markCar)
	return ctx.Garage.summon(player, p.car, if p.mode == "road" then "road" else "here")
end)

Net.on("dismiss", 1, function(player: Player)
	return ctx.Garage.dismiss(player)
end)

Net.on("paint", 0.4, function(player: Player, p: any)
	return ctx.Garage.setPaint(player, p.car, p.paint)
end)

Net.on("repair", 1.5, function(player: Player, p: any)
	return ctx.Garage.repair(player, p.id)
end)

Net.on("market", 1, function(player: Player, p: any)
	return ctx.Market.open(player, p.tab)
end)

Net.on("marketState", 0.8, function(player: Player)
	return ctx.Market.state(player)
end)

Net.on("setPlate", 1.5, function(player: Player, p: any)
	return ctx.Plate.set(player, p.text, p.style)
end)

Net.on("clearPlate", 1.5, function(player: Player)
	return ctx.Plate.clear(player)
end)

Net.on("setNeon", 0.5, function(player: Player, p: any)
	return ctx.NeonName.set(player, p.palette)
end)

Net.on("setKoFx", 0.5, function(player: Player, p: any)
	return ctx.Finish.setFx(player, p.fx)
end)

Net.on("previewKo", 1, function(player: Player, p: any)
	return ctx.Finish.preview(player, p.fx)
end)

Net.publish(readyMap())

-- systems that may come up late: each feature turns on by itself once its owner system is there
task.spawn(function()
	local ok, err = pcall(ctx.Garage.start, ctx)
	if not ok then
		Util.warnOnce("garage start", err)
	end
	ctx.refreshReady()
end)
task.spawn(function()
	local ok, err = pcall(ctx.Market.start, ctx)
	if not ok then
		Util.warnOnce("market start", err)
	end
	ctx.refreshReady()
end)
task.spawn(function()
	local ok, err = pcall(ctx.Finish.start, ctx)
	if not ok then
		Util.warnOnce("kofx start", err)
	end
	ctx.refreshReady()
end)

Util.log("ready · " .. Lines.t("app_title"))
