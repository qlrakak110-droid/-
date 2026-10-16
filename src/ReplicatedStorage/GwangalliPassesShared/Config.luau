-- GwangalliPassesShared/Config: every tunable of the pass add-on. The owner normally edits only PASSES[*].Id
-- (the game pass numbers from the Creator Dashboard). Id = 0 means "판매 준비 중": in a live server that pass is
-- hidden and its locks are not enforced (nobody could buy it); in Studio it is shown so every screen can be tried.
--
-- Studio test switches (workspace attributes, Studio only unless noted):
--   GwPassesStudioTest = true            every pass counts as owned
--   GwPassesStudioTest = "garage,flex"   only the listed passes (aliases garage | qol | flex)
--   GwPassesAdminFree = true (live too)  admins (Player attribute GwangalliAdmin, set by GwangalliLiveOps) own all

local Config = {}

Config.PASSES = {
	PremiumGarage = {
		Id = 0, -- 대시보드 게임패스 번호
		Price = 799, -- 추천가 (R$, 안내용; 실제 가격은 대시보드에서)
		Order = 7,
		Name = "프리미엄 차고",
		Title = "프리미엄 차고",
		Short = "차고",
		Glyph = "🏎️",
		Perk = "garage",
		Store = true,
		Desc = "하이퍼카 · 슈퍼카 · VIP · 오프로더 + 어디서든 내 차 호출(원격 차고) · 출장 정비",
		Perks = {
			"🏎️ 패스 전용 프리미엄 4대 (최고 210km/h 하이퍼카)",
			"📍 원격 차고: 어디서든 내 차 · 프리미엄 차를 바로 옆으로",
			"🎨 프리미엄 도색 14종 · 언더글로우",
			"🔧 출장 정비: 정비소에 안 가도 정비소 가격으로 수리",
		},
		C1 = Color3.fromRGB(255, 194, 71),
		C2 = Color3.fromRGB(255, 120, 60),
	},
	Convenience = {
		Id = 0,
		Price = 349,
		Order = 8,
		Name = "편의 패스",
		Title = "편의 패스",
		Short = "편의",
		Glyph = "⚡",
		Perk = "qol",
		Store = true,
		Desc = "유치장 · 기절 대기 시간 절반 + 폰 블랙마켓 앱 (어디서든 총기 · 탄약 주문)",
		Perks = {
			"⏱️ 유치장 수감 시간 50% 단축",
			"🏥 기절 후 병원 이송 대기 50% 단축",
			"📱 블랙마켓 앱: 총기상까지 안 가도 같은 가격으로 주문",
		},
		C1 = Color3.fromRGB(57, 255, 136),
		C2 = Color3.fromRGB(40, 160, 255),
	},
	Flex = {
		Id = 0,
		Price = 299,
		Order = 9,
		Name = "과시 패스",
		Title = "과시 패스",
		Short = "과시",
		Glyph = "✨",
		Perk = "flex",
		Store = true,
		Desc = "KO 피니시 이펙트 6종 · 나만의 번호판 · 네온 닉네임 (머리 위 + 채팅)",
		Perks = {
			"💥 KO 피니시 이펙트 6종 + 승리 포즈",
			"🔢 나만의 번호판 (스타일 6종, 내 모든 차에 적용)",
			"🌈 네온 닉네임: 머리 위 이름 + 채팅 이름 그라데이션",
		},
		C1 = Color3.fromRGB(255, 79, 163),
		C2 = Color3.fromRGB(150, 90, 255),
	},
}

-- Studio: show / sell-test passes whose Id is still 0
Config.STUDIO_SHOW_UNCONFIGURED = true
Config.STUDIO_ATTR = "GwPassesStudioTest"
Config.ADMIN_ATTR = "GwPassesAdminFree"
-- also hand the passes into ReplicatedStorage.GamePassConfig (phone "R$" app lists them) once their Id > 0
Config.INJECT_STORE = true

-- ownership checks
Config.OWNERSHIP = { RETRIES = 3, RETRY_GAP = 4, RECHECK = 300 }

---------------------------------------------------------------------------------------------------
-- #1 프리미엄 차고
---------------------------------------------------------------------------------------------------
Config.GARAGE = {
	-- 원격 차고: without the pass, OWNED / rented cars are called only inside the 정비소 zone (server enforced)
	REMOTE_LOCK = true,
	ZONE_RADIUS = 130, -- studs (horizontal) from the 정비소 venue pivot (tag GarageShop); Garage's own "at 정비소" is 150-170
	ZONE_FALLBACK = Vector3.new(-528, 7, 452), -- venue centre when the tag is missing
	STATION_RADIUS = 40, -- the kiosk itself also counts as the zone
	-- the 차량 호출 kiosk on the forecourt between the two planters (offset from the GarageReturn spot)
	STATION = { ENABLED = true, FROM_TAG = "GarageReturn", OFFSET = Vector3.new(18, 0, -1.4), FALLBACK = Vector3.new(-542, 6.7, 477.2), FACING = Vector3.new(0, 0, 1) },
	SUMMON_COOLDOWN = 4, -- s between premium summons (VS's own 8 s cooldown is skipped with force)
	SUMMON_SIDE = 9, -- studs to the player's side for "바로 내 옆"
	SUMMON_RADIUS = 400, -- road-lane search radius when the side spot is blocked
	REPAIR_FEE_MULT = 1.0, -- 출장 정비 = the 정비소 price x this
	PREVIEWS = true, -- ReplicatedStorage preview copies for the phone (3D cards)
	-- other add-ons may pass opts.gwAnywhere = true to spawnOwned (e.g. a dealership delivery) to skip the lock
}

---------------------------------------------------------------------------------------------------
-- #3 편의 패스
---------------------------------------------------------------------------------------------------
Config.QOL = {
	JAIL_MULT = 0.5,
	JAIL_MIN = 15, -- s
	KO_MULT = 0.5, -- SELF_HELP_AFTER (병원으로 이송 button), EMS_WAIT (no crew coming), EMS_TOTAL (crew never arrived)
	RESPAWN_MULT = 0.5, -- a real Roblox death / reset (Players.RespawnTime)
	-- "+ 50%" bail is untouched: GwangalliLawShared.bailFor scales with left / total, both halved
}

Config.MARKET = {
	SHOP_NAME = "📱 블랙마켓",
	RADIUS = 8, -- shop radius around the owner's own character (tradeCheck distance)
	OPEN_FEE = 0, -- 원 charged per opened session (접속료; 0 = same prices as the 총기상)
	OPEN_GAP = 1.5, -- s between open requests
}

---------------------------------------------------------------------------------------------------
-- #4 과시 패스
---------------------------------------------------------------------------------------------------
Config.PLATE = {
	MIN = 2, -- characters (not counting spaces)
	MAX = 8, -- characters (not counting spaces); "123가 4567" style plates fit
	MAX_TOTAL = 10, -- characters including spaces
	COOLDOWN = 20, -- s between changes
	UNIQUE = true, -- one plate text per player across servers (DataStore claim; falls back to this server)
	DEFAULT_STYLE = "classic",
}

Config.NEON = { DEFAULT = "bridge", TAG_DISTANCE = 90, TAG_OFFSET = 2.35, CHAT = true }

Config.KOFX = {
	DEFAULT = "lightning",
	PER_ATTACKER_GAP = 1.0, -- s
	SERVER_PER_SEC = 12,
	RANGE = 220, -- studs: who sees it
	MAX_LIVE = 3, -- client: concurrent effects
	PREVIEW_GAP = 3, -- s
	EMOTE = true, -- the attacker's short 승리 포즈 (Roblox default cheer / point animations)
}

---------------------------------------------------------------------------------------------------
-- data / net
---------------------------------------------------------------------------------------------------
Config.DATA = { STORE = "GwangalliPasses_v1", PLATES = "GwangalliPlates_v1", SAVE_DEBOUNCE = 8, RETRIES = 3 }
Config.NET = { BURST = 8, RATE = 4 } -- token bucket per player

-- client HUD shortcut (패스 상점 button under the "🚗 내 차" button)
Config.HUD = { ENABLED = true, SIZE = Vector2.new(92, 40), FALLBACK_POS = UDim2.new(1, -12, 0, 154) }

return Config
