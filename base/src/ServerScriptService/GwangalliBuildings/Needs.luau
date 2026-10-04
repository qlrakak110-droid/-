-- Needs: 포만감 (Satiety) · 에너지 (Energy) · 청결 (Hygiene) · 즐거움 (Fun), 0..100, as Player attributes
-- "GwB_<Need>". They slowly decay (Config.NEEDS) and are refilled by what the buildings offer: eating in a
-- restaurant, sleeping in your bed, a shower, karaoke, a PC game... The client HUD chip shows them; the
-- life game's stats get a small push through Economy.addStats when it exists.
--   Needs.apply(player, { Satiety = 20, Fun = 5 }, stats?, label?)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = require(ReplicatedStorage:WaitForChild("GwangalliBuildingsShared"))
local Config = Shared.Config

local Needs = {}

local Registry: any
local services: any

local function attr(n: string): string
	return "GwB_" .. n
end

function Needs.get(p: Player, n: string): number
	return tonumber(p:GetAttribute(attr(n))) or (Config.NEEDS[n] and Config.NEEDS[n].start or 50)
end

function Needs.set(p: Player, n: string, v: number)
	p:SetAttribute(attr(n), math.clamp(math.floor(v * 10 + 0.5) / 10, 0, 100))
end

function Needs.apply(p: Player, delta: { [string]: number }?, stats: { [string]: number }?, label: string?)
	if delta then
		local parts = {}
		for n, d in delta do
			if Config.NEEDS[n] then
				Needs.set(p, n, Needs.get(p, n) + d)
				table.insert(parts, string.format("%s %s%d", Config.NEEDS[n].icon, if d >= 0 then "+" else "", math.floor(d)))
			end
		end
		if #parts > 0 then
			Registry.fire(p, "needs.delta", { text = table.concat(parts, "  "), label = label })
		end
	end
	if stats and services.Economy then
		services.Economy.addStats(p, stats, label)
	end
end

local function setup(p: Player)
	for n, def in Config.NEEDS do
		if p:GetAttribute(attr(n)) == nil then
			p:SetAttribute(attr(n), def.start)
		end
	end
end

function Needs.init(ctx: any)
	Registry = ctx.Registry
	services = ctx.services
	Registry.on("needs.get", function(p: Player)
		local out = {}
		for n in Config.NEEDS do
			out[n] = Needs.get(p, n)
		end
		return { ok = true, needs = out }
	end)
end

function Needs.start()
	Players.PlayerAdded:Connect(setup)
	for _, p in Players:GetPlayers() do
		setup(p)
	end
	while true do
		task.wait(10)
		for _, p in Players:GetPlayers() do
			for n, def in Config.NEEDS do
				Needs.set(p, n, Needs.get(p, n) - def.decayPerMin / 6)
			end
		end
	end
end

return Needs
