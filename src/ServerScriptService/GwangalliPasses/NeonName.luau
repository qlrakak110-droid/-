-- GwangalliPasses/NeonName (server): pass #4 과시 패스, 네온 닉네임.
--   Player attribute GwNeonName = palette id (every client draws the animated tag itself: NeonTags.luau, and
--   the chat name: ChatNeon.luau). While it is on, the owner's default Humanoid name is hidden
--   (DisplayDistanceType None) so the neon tag stands where the plain name was; restored when off.
--   Legacy chat (if the place ever switches back): ChatService speaker NameColor + a ✦ tag, pcall-guarded.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local TextChatService = game:GetService("TextChatService")

local NeonName = {}

local ctx: any
local P: any, Config: any, Util: any, Lines: any, Neon: any

local function owns(player: Player): boolean
	return ctx.Ownership.owns(player, "Flex")
end

local function current(player: Player): string?
	if not owns(player) then
		return nil
	end
	local id = ctx.Data.get(player).neon
	return if type(id) == "string" and Neon.get(id) then id else nil
end

local function applyHumanoid(player: Player)
	local ch = player.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	local on = current(player) ~= nil
	if on then
		if hum:GetAttribute("GwNeonHidName") ~= true then
			hum:SetAttribute("GwNeonPrevDisplay", hum.DisplayDistanceType.Name)
		end
		hum:SetAttribute("GwNeonHidName", true)
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	elseif hum:GetAttribute("GwNeonHidName") == true then
		local prev = hum:GetAttribute("GwNeonPrevDisplay")
		local ok, e = pcall(function()
			return (Enum.HumanoidDisplayDistanceType :: any)[prev]
		end)
		hum.DisplayDistanceType = if ok and e then e else Enum.HumanoidDisplayDistanceType.Viewer
		hum:SetAttribute("GwNeonHidName", nil)
	end
end

local legacySpeaker: any = nil
local function legacyChat(player: Player)
	if TextChatService.ChatVersion ~= Enum.ChatVersion.LegacyChatService then
		return
	end
	pcall(function()
		if not legacySpeaker then
			local runner = ServerScriptService:FindFirstChild("ChatServiceRunner")
			local mod = runner and runner:FindFirstChild("ChatService")
			if not mod then
				return
			end
			legacySpeaker = require(mod :: ModuleScript)
		end
		local sp = legacySpeaker:GetSpeaker(player.Name)
		if not sp then
			return
		end
		local id = current(player)
		local pal = id and Neon.get(id)
		if pal then
			sp:SetExtraData("NameColor", Neon.sample(pal, 0.5))
			sp:SetExtraData("Tags", { { TagText = "✦", TagColor = pal.colors[1] } })
		else
			sp:SetExtraData("NameColor", nil)
			sp:SetExtraData("Tags", {})
		end
	end)
end

local function push(player: Player)
	player:SetAttribute(P.Attr.Neon, current(player))
	applyHumanoid(player)
	legacyChat(player)
end

function NeonName.set(player: Player, palette: any): { [string]: any }
	if not owns(player) then
		return { ok = false, code = "locked", message = Lines.t("locked_tab", Config.PASSES.Flex.Title) }
	end
	local id: string? = nil
	if type(palette) == "string" and palette ~= "" then
		if not Neon.get(palette) then
			return { ok = false, code = "bad" }
		end
		id = palette
	end
	ctx.Data.update(player, function(prof)
		prof.neon = id or "off"
	end)
	push(player)
	return { ok = true, message = Lines.t("neon_saved"), neon = id }
end

function NeonName.start(c: any)
	ctx = c
	P, Config, Util, Lines = c.P, c.Config, c.Util, c.P.Lines
	Neon = P.mod("Neon")
	local function join(player: Player)
		player.CharacterAdded:Connect(function(ch: Model)
			ch:WaitForChild("Humanoid", 10)
			applyHumanoid(player)
		end)
	end
	for _, p in Players:GetPlayers() do
		join(p)
	end
	Players.PlayerAdded:Connect(join)
	-- first grant: the neon starts on with the default palette (it can be turned off in 꾸미기)
	local function ensureDefault(player: Player)
		if owns(player) and ctx.Data.isLoaded(player) and ctx.Data.get(player).neon == nil then
			ctx.Data.update(player, function(prof)
				prof.neon = Config.NEON.DEFAULT
			end)
		end
	end
	c.Data.onLoaded(function(player: Player)
		ensureDefault(player)
		push(player)
	end)
	c.Ownership.onChanged(function(player: Player, key: string)
		if key ~= "Flex" then
			return
		end
		ensureDefault(player)
		push(player)
	end)
end

return NeonName
