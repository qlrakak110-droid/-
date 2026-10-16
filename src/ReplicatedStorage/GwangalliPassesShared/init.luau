-- GwangalliPassesShared (ModuleScript, ReplicatedStorage): the shared half of GwangalliPasses, three Robux
-- game passes for 광안리:
--   #1 프리미엄 차고 (PremiumGarage)  premium cars (하이퍼카 · 슈퍼카 · VIP · 오프로더) + 원격 차고 (call your car
--                                    anywhere; without it owned cars are called only at 광안 오토 정비소)
--   #3 편의 패스 (Convenience)         jail / KO wait x0.5 + the phone 블랙마켓 app (the 총기상's own shop, remote)
--   #4 과시 패스 (Flex)                KO 피니시 이펙트, custom plate, neon nickname (overhead + chat)
--   Server: ServerScriptService.GwangalliPasses (Script)   Client: StarterPlayerScripts.GwangalliPasses
--
--   local P = require(ReplicatedStorage.GwangalliPassesShared)
--   P.has(player, "garage" | "qol" | "flex" | "PremiumGarage" | ...) -> boolean   (server-written attribute)
--   P.changed(player, fn(key, owned)) -> RBXScriptConnection
--   P.available(key) -> boolean   (pass Id configured, or Studio)
--   P.Config / P.Lines and lazily P.mod("Cars" | "CarBodies" | "Plates" | "Neon" | "KoFx")
-- Pure: nothing is created at require time and nothing yields except the child WaitForChild calls.

local RunService = game:GetService("RunService")

local P = {}
P.VERSION = 1

P.Config = require(script:WaitForChild("Config"))
P.Lines = require(script:WaitForChild("Lines"))

local mods: { [string]: any } = {}
function P.mod(name: string): any
	local m = mods[name]
	if m == nil then
		m = require(script:WaitForChild(name))
		mods[name] = m
	end
	return m
end

-- instance names -------------------------------------------------------------------------------------
P.REMOTES = "GwangalliPassesRemotes" -- Folder in ReplicatedStorage (server-made)
P.REQUEST = "Request" -- RemoteFunction client -> server (op, payload) -> result table
P.EVENT = "Event" -- RemoteEvent server -> client (payload table with `kind`)
P.API = "GwangalliPassesAPI" -- ServerStorage BindableFunction for other add-ons
P.CHANGED = "GwangalliPassesChanged" -- ServerStorage BindableEvent (player, key, owned)
P.TEMPLATES = "GwangalliPassesTemplates" -- ServerStorage: premium car templates (server only)
P.PREVIEWS = "GwangalliPassesPreviews" -- ReplicatedStorage: light copies for the phone's 3D previews
P.WORLD = "GwangalliPassesWorld" -- Workspace: the 정비소 차량 호출 kiosk
P.FX = "GwPassesFxLocal" -- Workspace (client only): KO finish effects

-- pass keys --------------------------------------------------------------------------------------------
P.KEYS = { garage = "PremiumGarage", qol = "Convenience", flex = "Flex" }
P.ORDER = { "PremiumGarage", "Convenience", "Flex" }
P.ALIAS = { PremiumGarage = "garage", Convenience = "qol", Flex = "flex" }

P.Attr = {
	Owned = "GwPass_", -- Player: GwPass_<key> = true (same convention as GwangalliPassPerks / GwangalliStore)
	Neon = "GwNeonName", -- Player: neon palette id ("" / nil = off)
	KoFx = "GwKoFx", -- Player: KO finish effect id ("" / nil = off)
	Plate = "GwVanityPlate", -- Player: custom plate text (nil = none)
	PlateStyle = "GwPlateStyle", -- Player / car model: plate style id
	AtGarage = "GwPassAtGarage", -- Player: true while inside the 정비소 call zone (server computed)
	KOEnd = "GwPassQoLKOEnd", -- Player: server time the 편의 패스 sends a downed owner to hospital
	Premium = "GwPremiumCar", -- car Model: premium car key
	Ready = "GwPassesReady", -- ReplicatedStorage folder attribute: features that hooked fine (JSON)
	Station = "GwPassesStation", -- the kiosk part (client finds the prompt by this attribute)
}

-- canonical pass key from an alias / key (case-insensitive), or nil
function P.key(k: any): string?
	if type(k) ~= "string" then
		return nil
	end
	local low = string.lower(k)
	for alias, key in P.KEYS do
		if low == alias or low == string.lower(key) then
			return key
		end
	end
	return nil
end

function P.def(key: string): any
	return P.Config.PASSES[key]
end

function P.idOf(key: string): number
	local d = P.Config.PASSES[key]
	local id = d and tonumber(d.Id) or 0
	return if id and id > 0 then math.floor(id) else 0
end

-- A pass is "available" (shown, sold, its locks enforced) once its Id is set; in Studio always, so the owner
-- can try every screen before uploading the passes.
function P.available(k: any): boolean
	local key = P.key(k)
	if not key then
		return false
	end
	if P.idOf(key) > 0 then
		return true
	end
	return RunService:IsStudio() and P.Config.STUDIO_SHOW_UNCONFIGURED == true
end

function P.anyAvailable(): boolean
	for _, key in P.ORDER do
		if P.available(key) then
			return true
		end
	end
	return false
end

-- ownership as the server published it (Player attribute). Works on both peers.
function P.has(player: any, k: any): boolean
	local key = P.key(k)
	if not key or typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end
	return player:GetAttribute(P.Attr.Owned .. key) == true
end

function P.ownedMap(player: Player): { [string]: boolean }
	local out = {}
	for _, key in P.ORDER do
		out[key] = P.has(player, key)
	end
	return out
end

function P.changed(player: Player, fn: (string, boolean) -> ()): RBXScriptConnection
	return player.AttributeChanged:Connect(function(name: string)
		local prefix = P.Attr.Owned
		if string.sub(name, 1, #prefix) == prefix then
			local key = string.sub(name, #prefix + 1)
			if P.Config.PASSES[key] then
				fn(key, player:GetAttribute(name) == true)
			end
		end
	end)
end

function P.serverNow(): number
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	return if ok then t else os.time()
end

-- "12,345원"
function P.won(n: any): string
	local v = math.floor(tonumber(n) or 0)
	local s = tostring(math.abs(v))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return (if v < 0 then "-" else "") .. out .. "원"
end

return P
