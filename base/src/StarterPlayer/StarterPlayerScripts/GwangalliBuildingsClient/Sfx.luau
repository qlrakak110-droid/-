-- Sfx: one-shot and looping sounds of the building system on this client.
--   Sfx.ui(kind)                     UI blip: "tap" | "open" | "close" | "notify" | "money" | "success" | "error"
--   Sfx.at(key, parent, opts?)       one-shot 3D sound on a Part / Attachment (opts.volume, maxDist, speed)
--   Sfx.loop(key, parent, opts?)     -> Sound (caller stops / destroys it)
-- Sound ids: ReplicatedStorage.GwangalliBuildingsSounds attributes (key -> "rbxassetid://…", published by
-- the server Sounds service, overridable in Studio), else the built-in fallbacks below.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Sfx = {}

-- engine sounds that exist in every Roblox client (used until real ids are configured)
local FALLBACK = {
	ui_tap = "rbxasset://sounds/clickfast.wav",
	ui_open = "rbxasset://sounds/swoosh.wav",
	ui_close = "rbxasset://sounds/swoosh.wav",
	ui_notify = "rbxasset://sounds/electronicpingshort.wav",
	ui_money = "rbxasset://sounds/electronicpingshort.wav",
	ui_success = "rbxasset://sounds/electronicpingshort.wav",
	ui_error = "rbxasset://sounds/clickfast.wav",
	elevator_ding = "rbxasset://sounds/electronicpingshort.wav",
	doorbell = "rbxasset://sounds/electronicpingshort.wav",
	door_open = "rbxasset://sounds/swoosh.wav",
	door_close = "rbxasset://sounds/clickfast.wav",
	auto_door = "rbxasset://sounds/swoosh.wav",
	doorlock = "rbxasset://sounds/electronicpingshort.wav",
	button = "rbxasset://sounds/clickfast.wav",
}

local folder: Instance? = nil
local function idOf(key: string): string?
	if not folder then
		folder = ReplicatedStorage:FindFirstChild("GwangalliBuildingsSounds")
	end
	if folder then
		local v = folder:GetAttribute(key)
		if type(v) == "string" and v ~= "" then
			return v
		end
	end
	return FALLBACK[key]
end
Sfx.idOf = idOf

function Sfx.ui(kind: string)
	local s = Instance.new("Sound")
	-- the temporary studio synthesizes "GwangalliUI_<kind>" sounds; Roblox plays the id
	s.Name = "GwangalliUI_" .. kind
	s.SoundId = idOf("ui_" .. kind) or FALLBACK.ui_tap
	s.Volume = 0.5
	s.Parent = SoundService
	s:Play()
	task.delay(2, function()
		s:Destroy()
	end)
end

function Sfx.at(key: string, parent: Instance?, o: any?): Sound?
	local id = idOf(key)
	if not id or not parent then
		return nil
	end
	o = o or {}
	local s = Instance.new("Sound")
	s.Name = "GwB_" .. key
	s.SoundId = id
	s.Volume = o.volume or 0.6
	s.PlaybackSpeed = o.speed or 1
	s.RollOffMaxDistance = o.maxDist or 50
	s.RollOffMinDistance = o.minDist or 6
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.Parent = parent
	s:Play()
	task.delay(o.life or 6, function()
		s:Destroy()
	end)
	return s
end

function Sfx.loop(key: string, parent: Instance?, o: any?): Sound?
	local id = idOf(key)
	if not id or not parent then
		return nil
	end
	o = o or {}
	local s = Instance.new("Sound")
	s.Name = "GwB_" .. key
	s.SoundId = id
	s.Looped = true
	s.Volume = o.volume or 0.4
	s.PlaybackSpeed = o.speed or 1
	s.RollOffMaxDistance = o.maxDist or 40
	s.RollOffMinDistance = o.minDist or 5
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.Parent = parent
	s:Play()
	return s
end

return Sfx
