-- GwangalliBuildings/Names: THE NAME CONTRACT of the enterable-building system. Every CollectionService
-- tag, attribute and remote the server builders, the server services and the client share lives here,
-- so a typo becomes a nil-index instead of a silent mismatch. Pure data.
--
-- World layout (built by the server at start):
--   Workspace.GwangalliBuildings                      Folder
--     <BuildingId>                                     Model  tag Building
--       Shell                                          Model  facade, slabs, roof, signs (always present)
--       Interior                                       Model  tag Interior (built near players, parked far away)
--         Floor_<label>                                Model  per floor: core, corridor, unit walls / doors
--           Furnish                                    Model  tag Furnish (built per floor near players)
--   ServerStorage.GwangalliBuildingsParked             parked interiors (same instances, re-parented)
--   ReplicatedStorage.GwangalliBuildingsRemotes        Folder { Request: RemoteFunction, Event: RemoteEvent }
--   ReplicatedStorage.GwangalliBuildingsSounds         Configuration: attributes <soundKey> = "rbxassetid://.." list
--   ReplicatedStorage.GwangalliBuildingsIndex          Configuration: attributes Buildings (JSON summary for UIs)

local Names = {}

Names.ROOT = "GwangalliBuildings"
Names.PARKED = "GwangalliBuildingsParked"
Names.REMOTES = "GwangalliBuildingsRemotes"
Names.SOUNDS = "GwangalliBuildingsSounds"
Names.INDEX = "GwangalliBuildingsIndex"

Names.TAG = {
	Site = "GwB_Site", -- hand-placed building lot marker Part (attrs Archetype, Seed?, Floors?, Name?, Wear?)
	Building = "GwB_Building", -- building root Model (attrs BuildingId, Kind, DisplayName, Floors, Wear)
	Interior = "GwB_Interior", -- interior Model of a building (attrs BuildingId)
	Furnish = "GwB_Furnish", -- per-floor furniture Model (attrs BuildingId, Floor)
	Door = "GwB_Door", -- door Model (attrs DoorId, DoorKind, Open, OpenDir, Locked, Lock, UnitId?, ShopId?)
	Elevator = "GwB_Elevator", -- elevator Model (attrs ElevatorId, motion attributes, see Names.ELEV)
	ElevButton = "GwB_ElevButton", -- button Part (attrs ElevatorId, Where = "car" | "hall", Stop, Dir?, Action?)
	ElevDisplay = "GwB_ElevDisplay", -- Part with SurfaceGui "Display" (attrs ElevatorId, Where, Stop?)
	Unit = "GwB_Unit", -- unit Model (attrs UnitId, BuildingId, Floor, Template, Tier, Price, Owner*, ForSale)
	Room = "GwB_Room", -- invisible bounds Part (attrs RoomId, UnitId?, Kind, Label)
	Finish = "GwB_Finish", -- recolourable surface (attrs FinishKind = wall | floor | ceiling, RoomId, UnitId)
	Light = "GwB_Light", -- Light instance (attrs RoomId?, UnitId?, Group)
	Lamp = "GwB_Lamp", -- visible lamp part that glows with its room light (attrs RoomId?, UnitId?)
	Fixture = "GwB_Fixture", -- interactive object Model / Part (attrs Kind, FixtureId, UnitId?, ShopId?, Label)
	Placed = "GwB_Placed", -- player-placed furniture Model (attrs Uid, ItemId, UnitId, OwnerUserId)
	Shop = "GwB_Shop", -- shop Model (attrs ShopId, ShopKind, DisplayName, BuildingId)
	ShopPoint = "GwB_ShopPoint", -- shop interaction anchor Part (attrs ShopId, Point, Index?)
	Product = "GwB_Product", -- convenience-store shelf item (attrs ShopId, ProductId)
	Seat = "GwB_Seat", -- Seat used through prompts (attrs ShopId?, TableId?, Index)
	Sound = "GwB_Sound", -- ambient emitter Attachment / Part (attrs SoundKey, Volume, MaxDist, Loop)
	Flicker = "GwB_Flicker", -- Light that flickers (old fluorescent tubes)
	MotionLight = "GwB_MotionLight", -- 센서등 (corridor / stair lights that switch on when someone is near)
	Sign = "GwB_Sign", -- illuminated sign part (glows at night)
	Screen = "GwB_Screen", -- Part with a SurfaceGui driven by the client (TV, PC, karaoke) (attrs ScreenKind)
	Water = "GwB_Water", -- shower / faucet water emitter (attrs FixtureId)
	Spin = "GwB_Spin", -- part spun by the client (fans, disco ball) (attrs Rpm, Axis)
	Blocked = "GwB_Blocked", -- furniture no-placement volume (doors' swing, stairs)
	Parking = "GwB_Parking", -- parking stall Part (attrs Stall, BuildingId)
	Realtor = "GwB_Realtor", -- 부동산 desk point
	NightWindow = "NightWindow", -- the host game's night window contract (attrs LitChance, LitColor, Zone)
	NearLOD = "GwB_NearLOD", -- client-side near-only detail models
}

Names.ATTR = {
	BuildingId = "BuildingId",
	Kind = "Kind",
	DisplayName = "DisplayName",
	UnitId = "UnitId",
	RoomId = "RoomId",
	ShopId = "ShopId",
	FixtureId = "FixtureId",
	Floor = "Floor",
	Label = "Label",
	-- doors
	DoorId = "DoorId",
	DoorKind = "DoorKind", -- swing | double | slide | auto | stall | fire | shutter | glass
	Open = "Open",
	OpenDir = "OpenDir", -- +1 / -1 swing direction chosen at opening (away from the opener)
	Locked = "Locked",
	Lock = "Lock", -- none | unit | stall | room (hotel / karaoke key) | staff
	-- units
	Template = "Template",
	Tier = "Tier",
	Price = "Price",
	ForSale = "ForSale",
	OwnerUserId = "OwnerUserId",
	OwnerName = "OwnerName",
	-- furniture
	ItemId = "ItemId",
	Uid = "Uid",
	-- sounds
	SoundKey = "SoundKey",
	Volume = "Volume",
	MaxDist = "MaxDist",
	Loop = "Loop",
	-- light state written by the server (switches / themes)
	On = "On",
}

-- elevator model attributes (server writes, clients animate):
--   Stops        "B1|1|2|...|12"    labels, bottom first
--   StopY        "-12|0|13|..."      car floor height (world Y) per stop
--   Pos          number              stop index the car is at / last passed (1-based)
--   SegY0, SegY1, SegT0, SegV0, SegDir   current motion segment (world Y of the car floor, server time)
--   Moving       bool
--   Door         "closed" | "opening" | "open" | "closing"
--   DoorT0       server time the door phase started
--   Dir          "up" | "down" | ""   (hall lantern)
--   Calls        "3,7,12"            lit car buttons (stop indices)
--   HallUp, HallDown  "1,4"          lit hall buttons
Names.ELEV = {
	Stops = "Stops",
	StopY = "StopY",
	Pos = "Pos",
	SegY0 = "SegY0",
	SegY1 = "SegY1",
	SegT0 = "SegT0",
	SegV0 = "SegV0",
	Moving = "Moving",
	Door = "Door",
	DoorT0 = "DoorT0",
	Dir = "Dir",
	Calls = "Calls",
	HallUp = "HallUp",
	HallDown = "HallDown",
}

-- client -> server request ops (RemoteFunction Request(op, payload) -> { ok, msg?, ... })
Names.OPS = {
	-- shops
	"shop.menu", "shop.order", "shop.pay", "shop.pickup", "shop.sit", "shop.leaveSeat", "shop.eat",
	"shop.grill", "shop.flip", "shop.cvsPay", "shop.microwave", "shop.noodle", "shop.karaokeSong",
	"shop.karaokeLight", "shop.billiardsShot", "shop.pcGame", "shop.hotelCheckin", "shop.return",
	-- homes
	"home.listings", "home.buy", "home.tour", "home.enter", "home.state", "home.testMoney", "home.lock",
	"home.invite",
	-- decor
	"decor.begin", "decor.end", "decor.place", "decor.move", "decor.remove", "decor.theme", "decor.buy",
	-- furniture / misc
	"fx.use", "elev.call", "elev.car", "elev.door", "door.toggle", "needs.get",
}

-- server -> client event kinds (RemoteEvent Event:FireClient(player, kind, data))
Names.EVENTS = {
	"toast", -- { text, kind = "info" | "ok" | "warn" }
	"shop.open", -- { shopId, kind, view, ... } open a shop sheet
	"shop.state", -- { shopId, session } session changed
	"shop.close",
	"shop.ready", -- { shopId, number } order ready (진동벨 / 번호 호출)
	"home.update", -- { home } my home record changed
	"home.listings", -- pushed listings refresh
	"decor.state", -- { unitId, items, themes }
	"fx", -- { kind, ... } one-shot effect (sleep fade, eat, shower)
	"pose", -- { mode = "lie" | "none", cf } lie on a bed / sunbed
	"billiards", -- { tableId, frames, final } shot replay
	"karaoke", -- { roomId, song, t0 } song start
	"needs", -- { Satiety, Energy, ... }
}

-- archetype ids (Builder/Archetypes)
Names.ARCHETYPES = { "apartment", "officetel", "villa", "oneroom", "plaza", "hotel", "bbq", "cafe" }

-- home tiers, bottom first (the 내집마련 ladder)
Names.TIERS = { "oneroom", "villa", "officetel", "apartment", "penthouse" }
Names.TIER_NAME = {
	oneroom = "원룸",
	villa = "빌라",
	officetel = "오피스텔",
	apartment = "아파트",
	penthouse = "펜트하우스",
}

return Names
