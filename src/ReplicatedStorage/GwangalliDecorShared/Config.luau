--!strict
-- GwangalliDecorShared/Config: every tunable of the 자유 배치 인테리어 add-on (GwangalliDecorPlus).
-- Server and client read the same table, so a change here changes the rules on both sides.

local Config = {}

Config.VERSION = 1

-- Remotes folder created by the server in ReplicatedStorage (RemoteFunction "Request", RemoteEvent "Event").
Config.REMOTES_NAME = "GwangalliDecorPlusRemotes"
-- Folder created inside every life-game home model for the placed pieces (GwangalliBuildingInterior
-- keeps it clear). Each piece: Model "Item_<uid>", tag ITEM_TAG, attributes DecorUid / ItemId / ...
Config.FOLDER_NAME = "DecorPlus"
Config.ITEM_TAG = "GwDecorItem"
Config.LOCAL_FOLDER = "GwDecorPlusLocal" -- client-only ghosts / effects (Workspace)

-- Own DataStore (the life-game profile drops unknown keys, so layouts, colours, presets and the
-- 창고 of this catalog live here). Key "u_<UserId>".
Config.DATASTORE = "GwangalliDecorPlus_v1"
Config.AUTOSAVE_SECONDS = 120
Config.SAVE_MIN_GAP = 7 -- DataStore write budget per key
Config.SAVE_SOON = 12 -- coalesced save after a purchase / sale
Config.LOCK_STALE = 600 -- s: a session lock older than this is taken over
Config.LOAD_RETRIES = 5

-- Per home tier: placed pieces, parts of placed pieces (mobile budget), real lights of placed pieces.
Config.CAPS = {
	goshiwon = { items = 80, parts = 1600, lights = 2 },
	oneroom = { items = 140, parts = 2600, lights = 3 },
	officetel = { items = 200, parts = 3600, lights = 4 },
	apartment = { items = 260, parts = 4600, lights = 5 },
	penthouse = { items = 300, parts = 5600, lights = 6 },
	default = { items = 140, parts = 2600, lights = 3 },
}
Config.STORAGE_MAX = 400 -- 창고 칸 (pieces of this catalog)

-- Money
Config.SELL_RATE = 0.5 -- 팔기: share of the price paid back
Config.FRESH_SECONDS = 600 -- bought this visit less than 10 min ago: removing refunds 100 % (= 구매 취소)
Config.TRASH_SECONDS = 600 -- removed pieces can be brought back (undo) for 10 min
Config.DELETE_DEFAULT = "store" -- what 🗑 / Delete does: "store" (창고로) | "sell"
Config.PAY_PREFER = "bank" -- ctx.spend preference ("bank" = 체크카드 first)

-- Placement
Config.GRID_STEPS = { 0, 0.25, 0.5, 1 } -- 격자 (0 = 끔)
Config.GRID_DEFAULT = 0.5
Config.ROT_STEPS = { 15, 45, 90, 1 } -- 1 = 미세 회전
Config.ROT_DEFAULT = 45
Config.LIFT_STEP = 0.25 -- Q / E 높이 조절
Config.MAX_LIFT = 10 -- studs a piece may float above its support (creative stacking)
Config.WALL_GAP = 0.02
Config.CEILING_CLEARANCE = 4.6 -- the bottom of a ceiling piece stays this high above the floor
Config.SUPPORT_TOL = 0.12 -- |y - support| that still counts as standing on it
Config.OVERLAP_SHRINK = 0.06 -- collision boxes are shrunk by this before the overlap test
Config.WALL_SHRINK = 0.1
Config.PERSON_INFLATE = 0.4
Config.ALLOW_OVERLAP_TOGGLE = true -- 겹치기 허용 (creative mode) offered in the editor
Config.PATH_CHECK = true -- doors / fixtures stay reachable (raster BFS)
Config.PATH_CELL = 0.5
Config.PATH_RADIUS = 0.75
Config.KEEP = { doorDepth = 2.6, doorPad = 0.3, entry = 2.6, interactDepth = 1.4 }
Config.BATCH_MAX = 40 -- uids per remove / restore / group move
Config.HOME_HALF = 220 -- |x|, |z| limit of a record in the unit frame
Config.HOME_Y = { -40, 80 }

-- Rate limits (token bucket + per-action cooldowns, seconds)
Config.RATE = { tokens = 10, burst = 24 }
Config.COOLDOWN = {
	open = 0.8,
	place = 0.1,
	move = 0.06,
	moveMany = 0.15,
	color = 0.08,
	remove = 0.1,
	restore = 0.1,
	sellStored = 0.25,
	finish = 0.3,
	interact = 0.3,
	preset = 1.5,
	like = 1,
	guestbook = 6,
	gbDelete = 0.5,
	photo = 2,
}
Config.RID_CACHE = 32

-- Social
Config.LIKE_DEDUPE_HOURS = 20
Config.LIKE_OWNER_DAILY = 10 -- 좋아요 rewards per owner per day (the count itself is unlimited)
Config.GUESTBOOK_MAX = 30
Config.GUESTBOOK_LEN = 60
Config.PHOTO_DAILY = 3

-- Presets (프리셋)
Config.PRESET_SLOTS = 3
Config.PRESET_NAME_LEN = 16

-- Client
Config.KEY_OPEN = Enum.KeyCode.K
Config.DISPLAY_ORDER = 16
Config.PREVIEW_CACHE = 40
Config.CHECK_INTERVAL = 0.05 -- client-side rule check of the ghost
Config.UNDO_MAX = 30
Config.CUTAWAY_HZ = 10
Config.CAMERA = { pitch = 55, fov = 50, minDist = 10, maxDist = 90 }
Config.EFFECT_RANGE = 70 -- TV screens / aquarium fish / speakers animate within this distance

-- Speaker (스피커 음악 켜기): music asset ids the owner may add (rbxassetid://...). Empty = the
-- built-in tone sequencer (rbxasset:// sounds only), so the speaker always works.
Config.SPEAKER_TRACKS = {} :: { { name: string, id: string } }
Config.SPEAKER_VOLUME = 0.45

-- Host integration
Config.DORMANT_IF_HOST_DECOR = true -- a future host-side "HomeDecor" feature module switches this add-on off
Config.LINK_HOST_SCORE = true -- placed pieces count toward the life game's 인테리어 점수 / 편안함 / 가구 가치
Config.HOST_DECOR_SCALE = 1 -- our decor points -> host decor points
Config.HOST_VALUE_RATE = 0.5 -- our pieces -> 가구 가치 (resale)
Config.CLEAR_ON_HOST_THEME = true -- the host's 🛠️ 인테리어 setTheme for a room clears our finish of that kind

-- Rewards (small life-game stats through ctx.addStats); goals + badges are in Score.luau
Config.REWARDS = {
	like = { happiness = 1, popularity = 0.5 }, -- per ❤️ (max LIKE_OWNER_DAILY a day)
	photo = { happiness = 1 }, -- per 📸 (max PHOTO_DAILY a day)
}

function Config.caps(tierKey: string?): { items: number, parts: number, lights: number }
	return (Config.CAPS :: any)[tierKey or ""] or Config.CAPS.default
end

return Config
