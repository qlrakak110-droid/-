-- GwangalliBuildings/Config: every tunable number of the enterable-building system in one file.
-- Shared by the server (generation, services) and the client (effects, UI). Pure data: safe to require
-- anywhere. Studio overrides: Workspace attributes "GwB_<Key>" (numbers / booleans / strings) are read
-- by Config.get(key) at runtime, so a designer can tune without editing code.

local Config = {}

Config.VERSION = 1

-------------------------------------------------------------------------------------------------
-- World placement
-------------------------------------------------------------------------------------------------
-- Where the demo district is generated when the place has no site markers (Parts tagged
-- "GwB_Site", see docs). Y = the walking level (sidewalk top) of the district; the road runs along the
-- origin's X axis. Default: the empty strip at the east end of 광안리 (beside the 광안대교 남천 approach),
-- road along world Z, on a 13-stud stone podium (축대) so the B1 garages sit on the existing ground.
-- Override in Studio with the Workspace attribute GwB_Origin (CFrame).
Config.DISTRICT_ORIGIN = CFrame.new(4283.5, 18.9, -200) * CFrame.Angles(0, math.rad(-90), 0)
-- height of the podium under the district (0 = the district sits directly on the ground)
Config.DISTRICT_PODIUM = 13
-- Generate the demo district at all (false = only build on GwB_Site markers placed by hand)
Config.DEMO_DISTRICT = true
-- Carve terrain (Air) where basements / ramps go and flatten the district ground
Config.CARVE_TERRAIN = true

-------------------------------------------------------------------------------------------------
-- Scale (1 stud = 0.3 m, same as the rest of 광안리)
-------------------------------------------------------------------------------------------------
Config.M_PER_STUD = 0.3
Config.FLOOR_H_RES = 10.5 -- residential floor-to-floor
Config.FLOOR_H_COM = 13 -- commercial / lobby floor-to-floor
Config.SLAB = 1 -- slab thickness (below the finished floor)
Config.WALL_EXT = 0.8 -- exterior wall thickness
Config.WALL_INT = 0.4 -- partition thickness
Config.DOOR_W = 3.6
Config.DOOR_H = 7.4
Config.STAIR_W = 4.6 -- one flight
Config.STAIR_LANDING = 4.4

-------------------------------------------------------------------------------------------------
-- Streaming / mobile budget
-------------------------------------------------------------------------------------------------
-- Server: a building's interior (core, stairs, elevators, unit walls) is built the first time a player
-- comes within ACTIVATE studs of the building and parked in ServerStorage after nobody has been within
-- DEACTIVATE studs for PARK_AFTER seconds. Furniture / shop props are built per floor (FURNISH_FLOORS
-- floors around every player inside the building) and dropped after UNFURNISH_AFTER seconds.
Config.ACTIVATE = 42
Config.DEACTIVATE = 85
Config.PARK_AFTER = 25
Config.FURNISH_RADIUS = 45 -- horizontal reach of a player for per-floor furnishing
Config.STREET_FURNISH = 28 -- people on the street this close see the ground storey's shops / lobby furnished
Config.FURNISH_FLOORS = 0 -- extra floors above / below the player's floor that are always built
Config.STAIR_PREFETCH = 5 -- the next storey builds when your feet are this close to its floor (stairs)
Config.UNFURNISH_AFTER = 30
Config.BUILD_PARTS_PER_STEP = if game.PlaceId == 0 then 120 else 260 -- the builders yield (task.wait) after this many instances
Config.STREAM_TICK = 0.75 -- seconds between streaming passes
-- Client: interior lights / sounds / particles / screens beyond this radius of the camera are switched off
Config.CLIENT_LOD = { low = 70, mid = 95, high = 130 }
Config.CLIENT_LOD_HYST = 12
Config.MAX_LOOPS = { low = 6, mid = 9, high = 14 } -- simultaneous ambient loops
Config.MAX_INTERIOR_LIGHTS = { low = 10, mid = 18, high = 32 } -- nearest interior lights kept on

-------------------------------------------------------------------------------------------------
-- Doors
-------------------------------------------------------------------------------------------------
Config.DOOR_PROMPT_DIST = 7
Config.DOOR_SWING_TIME = 0.55
Config.DOOR_SLIDE_TIME = 0.7
Config.DOOR_AUTO_RADIUS = 9 -- automatic glass doors open when a character is this close
Config.DOOR_AUTO_CLOSE = 6 -- seconds an ordinary hinged door stays open before it closes itself
Config.DOOR_FIRE_CLOSE = 4 -- 방화문 (stairwell fire doors) close faster
Config.DOOR_UNIT_CLOSE = 5 -- 현관문 (doorlock doors) close and lock themselves

-------------------------------------------------------------------------------------------------
-- Elevators
-------------------------------------------------------------------------------------------------
Config.ELEV_SPEED = 9 -- studs / s cruise (2.7 m/s)
Config.ELEV_ACCEL = 6 -- studs / s^2
Config.ELEV_DOOR_TIME = 1.25 -- open / close duration
Config.ELEV_DWELL = 4 -- doors stay open
Config.ELEV_DWELL_EXTEND = 2.5 -- reopen extension when someone is in the doorway
Config.ELEV_CAR_W = 7 -- interior width (x) of the car
Config.ELEV_CAR_D = 6.6 -- interior depth (z)
Config.ELEV_CAR_H = 8.6
Config.ELEV_IDLE_HOME = 25 -- idle cars return to the lobby after this many seconds (0 = never)

-------------------------------------------------------------------------------------------------
-- Economy (used only when the life game's ServerStorage.GwangalliGameplayAPI is missing)
-------------------------------------------------------------------------------------------------
Config.FALLBACK_START_MONEY = 3000000
Config.FALLBACK_STORE = "GwBuildings_Wallet_v1"
-- Test mode: unpublished places (PlaceId 0: the temporary studio, a local Studio test) show a
-- "테스트 자금 받기" button in the realtor so the whole house ladder can be tried at once.
Config.TEST_MONEY_GRANT = 60000000

-------------------------------------------------------------------------------------------------
-- Housing
-------------------------------------------------------------------------------------------------
Config.HOME_STORE = "GwBuildings_Home_v1"
Config.HOME_SAVE_EVERY = 60 -- autosave period (seconds)
Config.LADDER_REQUIRED = true -- 원룸 -> 빌라 -> 오피스텔 -> 아파트 -> 펜트하우스, one step at a time
Config.TRADE_IN = 0.85 -- the old home is sold back at this share of its price when you move up
Config.TOUR_SECONDS = 180 -- 매물 둘러보기: a for-sale unit stays unlocked for you this long
Config.MAX_FURNITURE = 80 -- placed pieces per home
Config.GRID = 0.5 -- placement grid (studs)
Config.ROTATE_STEP = 45 -- degrees per rotate tap
Config.GUESTS_MAX = 6

-------------------------------------------------------------------------------------------------
-- Shops
-------------------------------------------------------------------------------------------------
Config.SHOP_PROMPT_DIST = 7
Config.CVS_RESTOCK = 25 -- seconds before a picked shelf item reappears
Config.CVS_MICROWAVE = 12 -- seconds (도시락 데우기)
Config.CVS_NOODLE_WAIT = 18 -- seconds (컵라면 3분 = 18 s in game)
Config.GUKBAP_COOK = 10
Config.CAFE_BREW = 9
Config.BBQ_SERVE = 5 -- staff brings the meat after this many seconds
Config.BBQ_COOK_RATE = 0.075 -- cook per second of the side on the grill (1 = done, 1.6 = burnt)
Config.BBQ_PIECES = 6 -- meat pieces per portion
Config.PC_MINUTES_PER_TICKET = 10 -- real minutes of PC time per 1시간 이용권
Config.KARAOKE_SECONDS = 600
Config.BILLIARDS_SECONDS = 600
Config.HOTEL_STAY_SECONDS = 1200
Config.DINE_AND_DASH_RETURN = true -- leaving a 후불 restaurant with an open bill walks you back to the counter

-------------------------------------------------------------------------------------------------
-- Sounds (server Sounds service; keys listed in Sounds.KEYS)
-------------------------------------------------------------------------------------------------
-- ids you choose: key = "rbxassetid://123" (or the number). Studio attributes on
-- ReplicatedStorage.GwangalliBuildingsSounds win over this table.
Config.SOUND_IDS = {} :: { [string]: any }
-- ask the Creator Store (AssetService:SearchAudioAsync) for keys that still have no id (published places)
Config.SOUND_SEARCH = true

-------------------------------------------------------------------------------------------------
-- Needs (attributes on the Player, shown in the HUD chip; integrated with the life game's stats
-- through GwangalliGameplayAPI "addStats" when it exists)
-------------------------------------------------------------------------------------------------
Config.NEEDS = {
	Satiety = { start = 70, decayPerMin = 1.2, name = "포만감", icon = "🍚" },
	Energy = { start = 80, decayPerMin = 0.8, name = "에너지", icon = "⚡" },
	Hygiene = { start = 80, decayPerMin = 0.6, name = "청결", icon = "🫧" },
	Fun = { start = 60, decayPerMin = 0.9, name = "즐거움", icon = "🎵" },
}

-------------------------------------------------------------------------------------------------
-- Runtime overrides
-------------------------------------------------------------------------------------------------
function Config.get(key: string): any
	local ok, v = pcall(function()
		return workspace:GetAttribute("GwB_" .. key)
	end)
	if ok and v ~= nil then
		return v
	end
	return (Config :: any)[key]
end

-- quality tier of this client: GwangalliQuality (the host game's shared tier) when present,
-- else a guess from the device (touch = low)
function Config.tierOf(qualityModule: any?): string
	if qualityModule and type(qualityModule.get) == "function" then
		local ok, t = pcall(qualityModule.get)
		if ok and (t == "low" or t == "mid" or t == "high") then
			return t
		end
	end
	local ok, touch = pcall(function()
		return game:GetService("UserInputService").TouchEnabled
	end)
	return if ok and touch then "low" else "high"
end

return Config
