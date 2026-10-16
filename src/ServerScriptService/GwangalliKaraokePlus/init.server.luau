-- GwangalliKaraokePlus (server): 팡팡노래방-style coin karaoke for the 8 booths of
-- 광안 코인노래연습장. Drop-in add-on: this Script + ReplicatedStorage.GwangalliKaraokeShared +
-- StarterPlayerScripts.GwangalliKaraokePlus. No existing script needs editing; the legacy VenueKaraoke
-- rental prompt is switched off at runtime (Config.TakeOverLegacy) and the legacy booth attributes
-- (KRenter / KRenterName / KPaidUntil) keep being written so the status light, the panel text and the
-- interior team's displays keep working.
--
-- Boot: shared contract -> remotes -> store -> integrations -> rooms -> legacy takeover -> loops ->
-- GwangalliKaraokeShared.Active = true (clients wait for it before they hide the legacy karaoke UI).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local sharedModule = ReplicatedStorage:WaitForChild("GwangalliKaraokeShared", 60)
if not (sharedModule and sharedModule:IsA("ModuleScript")) then
	warn("[GwangalliKaraokePlus] ReplicatedStorage.GwangalliKaraokeShared is missing; the add-on is off")
	return
end
local okS, S = pcall(require, sharedModule)
if not okS or type(S) ~= "table" then
	warn("[GwangalliKaraokePlus] shared module failed:", S)
	return
end
local C = S.Config
if not C.Enabled then
	return
end

local K: any = { S = S, sharedModule = sharedModule }
K.Net = require(script:WaitForChild("Net"))
K.Bridge = require(script:WaitForChild("Bridge"))
K.Store = require(script:WaitForChild("Store"))
K.Rooms = require(script:WaitForChild("Rooms"))
K.Playback = require(script:WaitForChild("Playback"))
K.Mics = require(script:WaitForChild("Mics"))
K.Scoring = require(script:WaitForChild("Scoring"))
K.Voice = require(script:WaitForChild("Voice"))

-------------------------------------------------------------------------------------------------
-- lobby LED + shared chart / king attributes
-------------------------------------------------------------------------------------------------
local lastChart, lastKing = "", ""
function K.refreshLED()
	local folder = K.Rooms.stateFolder and K.Rooms.stateFolder()
	local top = K.Store.chartTop(20)
	local chartJson = S.encode(top)
	local kingRows = {}
	for _, e in K.Bridge.kingList() do
		table.insert(kingRows, { n = e.name, s = e.score, t = e.title, u = e.userId })
	end
	local kingJson = S.encode(kingRows)
	if folder then
		if chartJson ~= lastChart then
			lastChart = chartJson
			folder:SetAttribute("Chart", chartJson)
		end
		if kingJson ~= lastKing then
			lastKing = kingJson
			folder:SetAttribute("King", kingJson)
		end
	end
	local msg = { "TOP 인기차트" }
	for i = 1, 3 do
		local s = top[i] and S.Songs.byId[top[i]]
		if s then
			table.insert(msg, string.format("%d위 ♪ %s", i, s.title))
		end
	end
	local k1 = kingRows[1]
	if k1 then
		table.insert(msg, string.format("👑 오늘의 노래왕 %s %d점", k1.n, k1.s))
	end
	table.insert(msg, "1곡 500원 · 4곡 1,000원 · 100점이면 서비스 1곡")
	K.Bridge.writeLED(table.concat(msg, "|"))
end

-------------------------------------------------------------------------------------------------
-- boot
-------------------------------------------------------------------------------------------------
K.Net.create(K)
K.Bridge.init(K)
K.Store.init(K)
K.Rooms.init(K)
K.Playback.init(K)
K.Mics.init(K)
K.Scoring.init(K)
K.Voice.init(K)

K.Net.handle("hello", "ui", function(player: Player, _a: any)
	return {
		ok = true,
		me = K.Store.view(player),
		voice = C.Voice,
		billing = C.Billing,
		economy = K.Bridge.hasEconomy(),
		trial = not K.Bridge.hasEconomy() and C.FreeWhenNoEconomy,
		version = S.VERSION,
	}
end)

local panels = K.Rooms.panels()
if #panels == 0 then
	warn("[GwangalliKaraokePlus] no KaraokeRoom booths found (Config.VenueModelNames); the add-on idles")
end

-- the legacy VenueKaraoke creates its panel prompts when the gameplay core boots
local legacyFound = K.Bridge.waitLegacy(panels, if #panels > 0 then 12 else 0)
if legacyFound and not C.TakeOverLegacy then
	warn("[GwangalliKaraokePlus] legacy karaoke is running and Config.TakeOverLegacy = false; the add-on stays off")
	return
end
K.Bridge.takeOver(panels)
K.Bridge.findLED(K.Rooms.venues())

-- loops: 10 Hz playback, 2 Hz membership, 1 Hz mics / vibe
local acc10, acc2, acc1 = 0, 0, 0
RunService.Heartbeat:Connect(function(dt)
	acc10 += dt
	acc2 += dt
	acc1 += dt
	if acc10 >= 0.1 then
		acc10 = 0
		for _, r in K.Rooms.list() do
			local ok, err = pcall(K.Playback.step, r)
			if not ok then
				warn("[GwangalliKaraokePlus] playback step:", err)
			end
		end
	end
	if acc2 >= 0.5 then
		acc2 = 0
		local ok, err = pcall(K.Rooms.membership)
		if not ok then
			warn("[GwangalliKaraokePlus] membership:", err)
		end
	end
	if acc1 >= 1 then
		local step = acc1
		acc1 = 0
		pcall(K.Mics.step)
		for _, r in K.Rooms.list() do
			K.Scoring.decayVibe(r, step)
			if r.tambUntil > 0 and S.now() > r.tambUntil then
				r.tambUntil = 0
				K.Rooms.publish(r)
			end
		end
	end
end)

task.spawn(function()
	while true do
		pcall(K.refreshLED)
		pcall(K.Bridge.writeBoard)
		task.wait(60)
	end
end)

sharedModule:SetAttribute("Version", S.VERSION)
sharedModule:SetAttribute("Active", true)
workspace:SetAttribute("GwKaraokePlus", true)
if C.Debug then
	print(string.format("[GwangalliKaraokePlus] ready: %d rooms, legacy takeover %s, players %d", #K.Rooms.list(), tostring(legacyFound), #Players:GetPlayers()))
end
