-- Sounds: decides which audio asset plays for every sound key of the building system and publishes the
-- table to clients as attributes of ReplicatedStorage.GwangalliBuildingsSounds (key -> "rbxassetid://…").
-- Sources, first wins:
--   1. attributes you set on that folder in Studio (create the Folder yourself and add string attributes),
--   2. Config.SOUND_IDS below (fill in ids you uploaded or picked in the Creator Store),
--   3. Config.SOUND_SEARCH: on a published place the server asks the Creator Store
--      (AssetService:SearchAudioAsync) for a fitting public sound per key, once per server.
-- Keys without an id simply stay silent (the UI blips use engine sounds). The clients decide what plays
-- where (nearest loops within a budget, see the client Ambience module).

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = require(ReplicatedStorage:WaitForChild("GwangalliBuildingsShared"))
local Config = Shared.Config

local Sounds = {}

-- key -> { search keyword, kind ("sfx" | "music"), min / max duration (seconds) }
Sounds.KEYS = {
	fridge_hum = { "refrigerator hum", "sfx", 4, 120 },
	aircon_hum = { "air conditioner hum", "sfx", 4, 120 },
	vent_fan = { "ventilation fan", "sfx", 4, 120 },
	fluorescent = { "fluorescent light buzz", "sfx", 3, 120 },
	elevator_hum = { "elevator moving", "sfx", 3, 120 },
	elevator_ding = { "elevator ding", "sfx", 0.2, 4 },
	tv_talk = { "tv chatter", "sfx", 8, 180 },
	pc_hum = { "computer fan", "sfx", 4, 120 },
	keyboard = { "keyboard typing", "sfx", 3, 60 },
	microwave_hum = { "microwave running", "sfx", 3, 60 },
	washer = { "washing machine", "sfx", 5, 120 },
	shower = { "shower water", "sfx", 4, 120 },
	bubbles = { "jacuzzi bubbles", "sfx", 4, 120 },
	hand_dryer = { "hand dryer", "sfx", 2, 30 },
	toilet_flush = { "toilet flush", "sfx", 2, 15 },
	auto_door = { "automatic sliding door", "sfx", 0.5, 5 },
	door_open = { "door open", "sfx", 0.3, 3 },
	door_close = { "door close", "sfx", 0.3, 3 },
	shutter = { "rolling shutter", "sfx", 1, 8 },
	doorbell = { "doorbell", "sfx", 0.5, 5 },
	doorlock = { "door lock beep", "sfx", 0.2, 4 },
	store_chime = { "store door chime", "sfx", 0.5, 5 },
	store_music = { "lofi chill", "music", 60, 600 },
	boiling = { "boiling water", "sfx", 4, 120 },
	restaurant_chatter = { "restaurant ambience", "sfx", 10, 300 },
	sizzle = { "sizzling meat", "sfx", 3, 120 },
	espresso = { "espresso machine", "sfx", 3, 30 },
	cafe_music = { "jazz cafe", "music", 60, 600 },
	lobby_music = { "bossa nova", "music", 60, 600 },
	karaoke_music = { "kpop instrumental", "music", 60, 400 },
	karaoke_muffled = { "muffled music", "sfx", 10, 300 },
	billiards_ambience = { "pool hall ambience", "sfx", 10, 300 },
	billiard_hit = { "billiard ball hit", "sfx", 0.2, 3 },
}

local folder: Folder

local function norm(v: any): string?
	if type(v) == "number" then
		return "rbxassetid://" .. math.floor(v)
	elseif type(v) == "string" and v ~= "" then
		if string.match(v, "^%d+$") then
			return "rbxassetid://" .. v
		end
		return v
	end
	return nil
end

local function search(key: string, spec: any): string?
	local ok, res = pcall(function()
		local params = Instance.new("AudioSearchParams")
		params.SearchKeyword = spec[1]
		params.AudioSubType = if spec[2] == "music" then Enum.AudioSubType.Music else Enum.AudioSubType.SoundEffect
		params.MinDuration = spec[3]
		params.MaxDuration = spec[4]
		local pages = (AssetService :: any):SearchAudioAsync(params)
		local page = pages:GetCurrentPage()
		for _, item in page do
			local id = item.Id or item.AssetId
			if id then
				return "rbxassetid://" .. tostring(id)
			end
		end
		return nil
	end)
	if ok then
		return res
	end
	return nil
end

function Sounds.id(key: string): string?
	local v = folder and folder:GetAttribute(key)
	return if type(v) == "string" and v ~= "" then v else nil
end

function Sounds.init(_ctx: any)
	local f = ReplicatedStorage:FindFirstChild("GwangalliBuildingsSounds")
	if not f then
		f = Instance.new("Folder")
		f.Name = "GwangalliBuildingsSounds"
		f.Parent = ReplicatedStorage
	end
	folder = f :: Folder
	for key, v in Config.SOUND_IDS do
		if folder:GetAttribute(key) == nil then
			local id = norm(v)
			if id then
				folder:SetAttribute(key, id)
			end
		end
	end
end

function Sounds.start()
	if not Config.SOUND_SEARCH or game.PlaceId == 0 then
		return
	end
	-- fill the missing keys from the Creator Store, gently (one query every few seconds)
	local found = 0
	for key, spec in Sounds.KEYS do
		if folder:GetAttribute(key) == nil then
			local id = search(key, spec)
			if id then
				folder:SetAttribute(key, id)
				found += 1
			end
			task.wait(2)
		end
	end
	if found > 0 then
		print(string.format("[GwangalliBuildings] sounds: %d ids found in the Creator Store (set GwangalliBuildingsSounds attributes to choose your own)", found))
	end
end

return Sounds
