-- Ambience: the life noise of the buildings on this client, and the interior level-of-detail.
--   * looping sound anchors (Attachments tagged GwB_Sound: fridge hum, vent fans, store music, TV talk…):
--     only the nearest Config.MAX_LOOPS[tier] audible ones play; Active = false silences an anchor until
--     its appliance is switched on; Trigger anchors are one-shots (Trigger = "enter": the store chime
--     when you walk in);
--   * interior lights (tagged GwB_Light) beyond the LOD radius are switched off locally and the nearest
--     Config.MAX_INTERIOR_LIGHTS[tier] are kept, so a phone never renders a whole tower's lamps.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = require(ReplicatedStorage:WaitForChild("GwangalliBuildingsShared"))
local Config = Shared.Config
local Sfx = require(script.Parent:WaitForChild("Sfx"))

local Ambience = {}

local tier = "mid"
local playing: { [Attachment]: Sound } = {}
local inside: { [Attachment]: boolean } = {}
local lodOff: { [Light]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function posOf(a: Attachment): Vector3?
	local ok, p = pcall(function()
		return a.WorldPosition
	end)
	return if ok then p else nil
end

local function soundPass(camPos: Vector3)
	local maxLoops = (Config.MAX_LOOPS :: any)[tier] or 9
	local cands = {}
	for _, a in CollectionService:GetTagged("GwB_Sound") do
		if not a:IsA("Attachment") or not a:IsDescendantOf(workspace) then
			continue
		end
		local p = posOf(a)
		if not p then
			continue
		end
		local d = (p - camPos).Magnitude
		local maxD = tonumber(a:GetAttribute("MaxDist")) or 40
		local trig = a:GetAttribute("Trigger")
		if trig == "enter" then
			local near = d < 7
			if near and not inside[a] then
				Sfx.at(a:GetAttribute("SoundKey") :: string, a, { volume = tonumber(a:GetAttribute("Volume")) or 0.5, maxDist = maxD })
			end
			inside[a] = near
			continue
		elseif trig ~= nil then
			continue -- event one-shots (elevator ding, auto door) are played by their owners
		end
		if a:GetAttribute("Loop") == false or a:GetAttribute("Active") == false then
			continue
		end
		if d < maxD then
			table.insert(cands, { a = a, d = d / math.max(0.05, tonumber(a:GetAttribute("Volume")) or 0.4) })
		end
	end
	table.sort(cands, function(x, y)
		return x.d < y.d
	end)
	local keep: { [Attachment]: boolean } = {}
	for i = 1, math.min(#cands, maxLoops) do
		keep[cands[i].a] = true
	end
	for a, s in playing do
		if not keep[a] then
			s:Destroy()
			playing[a] = nil
		end
	end
	for a in keep do
		if not playing[a] then
			local s = Sfx.loop(a:GetAttribute("SoundKey") :: string, a, {
				volume = tonumber(a:GetAttribute("Volume")) or 0.4,
				maxDist = tonumber(a:GetAttribute("MaxDist")) or 40,
			})
			if s then
				-- desynchronise identical appliances
				pcall(function()
					s.TimePosition = math.random() * 4
				end)
				playing[a] = s
			end
		end
	end
end

local function lightPass(camPos: Vector3)
	local radius = (Config.CLIENT_LOD :: any)[tier] or 95
	local maxLights = (Config.MAX_INTERIOR_LIGHTS :: any)[tier] or 18
	local near = {}
	for _, l in CollectionService:GetTagged("GwB_Light") do
		if not l:IsA("Light") or CollectionService:HasTag(l, "GwB_MotionLight") then
			continue -- 센서등 are switched by the Living module
		end
		local part = l.Parent
		if not part or not part:IsA("BasePart") then
			continue
		end
		-- lights the game switched off stay off; only the ones LOD turned off come back
		local wanted = l:GetAttribute("On") ~= false and (l.Enabled or lodOff[l] == true)
		if not wanted then
			continue
		end
		local d = (part.Position - camPos).Magnitude
		if d < radius then
			table.insert(near, { l = l, d = d })
		elseif l.Enabled then
			l.Enabled = false
			lodOff[l] = true
		end
	end
	table.sort(near, function(x, y)
		return x.d < y.d
	end)
	for i, e in near do
		local on = i <= maxLights
		if on and lodOff[e.l] then
			e.l.Enabled = true
			lodOff[e.l] = nil
		elseif not on and e.l.Enabled then
			e.l.Enabled = false
			lodOff[e.l] = true
		end
	end
end

function Ambience.start()
	local okQ, Q = pcall(function()
		return require(ReplicatedStorage:FindFirstChild("GwangalliQuality") :: any)
	end)
	tier = Config.tierOf(if okQ then Q else nil)
	task.spawn(function()
		while true do
			local cam = workspace.CurrentCamera
			if cam then
				local p = cam.CFrame.Position
				local ok, err = pcall(soundPass, p)
				if not ok then
					warn("[GwangalliBuildings] ambience: " .. tostring(err))
				end
				task.wait(0.25)
				ok, err = pcall(lightPass, p)
				if not ok then
					warn("[GwangalliBuildings] light lod: " .. tostring(err))
				end
			end
			task.wait(0.5)
		end
	end)
end

return Ambience
