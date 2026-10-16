-- GwangalliKaraokePlus/Rooms (client): typed views of the server room state
-- (ReplicatedStorage.GwangalliKaraokeShared.State.Room_NN attributes, always replicated) bound to the
-- booth models (tag KaraokeRoom; they stream in and out), plus "which room am I in".
--   Rooms.views                  { [no] = view }
--   Rooms.current() -> view?     the room I stand in (local zone test, 5 Hz)
--   Rooms.near() -> view?        the closest booth whose panel is within reach (corridor)
--   Rooms.changed(fn(view, attr))   Rooms.entered(fn(view?, prev?))
--   Rooms.songTime(view, now) -> song seconds (Clock)    Rooms.allowedMe(view) -> boolean
-- view fields: no, name, cfg, model, zone, panel, screen, parts {machine, remote, book, mics{}, tamb,
--   ball, laser}, state, renter, renterName, credits, unlimited, privacy, allowed {set}, allowedList,
--   members {set}, queue {}, serial, song (Songs entry?), songNo, clock, paused, tempo, key, echo, guide,
--   scoreOn, mics {uid, uid}, singers {}, vibe, result, nextT, idleT, emptyT, voiceRig

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local Rooms = {}

local K: any
local S: any
local player = Players.LocalPlayer

Rooms.views = {} :: { [number]: any }
local changedFns: { (any, string) -> () } = {}
local enteredFns: { (any?, any?) -> () } = {}
local cur: any = nil
local acc = 0

local function fire(v: any, attr: string)
	for _, fn in changedFns do
		local ok, err = pcall(fn, v, attr)
		if not ok then
			warn("[GwangalliKaraokePlus] room changed:", err)
		end
	end
end

function Rooms.changed(fn: (any, string) -> ())
	table.insert(changedFns, fn)
end

function Rooms.entered(fn: (any?, any?) -> ())
	table.insert(enteredFns, fn)
end

local function setSet(list: any): { [number]: boolean }
	local set = {}
	if type(list) == "table" then
		for _, u in list do
			if type(u) == "number" then
				set[u] = true
			end
		end
	end
	return set
end

local function read(v: any, name: string)
	local cfg = v.cfg :: Instance
	local val = cfg:GetAttribute(name)
	if name == "State" then
		v.state = val or "free"
	elseif name == "Renter" then
		v.renter = val or 0
	elseif name == "RenterName" then
		v.renterName = val or ""
	elseif name == "Credits" then
		v.credits = val or 0
	elseif name == "Unlimited" then
		v.unlimited = val == true
	elseif name == "Privacy" then
		v.privacy = val or "lock"
	elseif name == "Allowed" then
		local l = S.decode(val) or {}
		v.allowedList = l
		v.allowed = setSet(l)
	elseif name == "Members" then
		local l = S.decode(val) or {}
		v.memberList = l
		v.members = setSet(l)
	elseif name == "Queue" then
		v.queue = S.decode(val) or {}
	elseif name == "Serial" then
		v.serial = val or 0
	elseif name == "Song" then
		v.songId = val or ""
		v.song = if val and val ~= "" then S.Songs.byId[val] else nil
		v.chart = if v.song then S.Chart.get(v.song, S.Songs) else nil
	elseif name == "SongNo" then
		v.songNo = val or 0
	elseif name == "Clock" then
		v.clock = S.parseClock(val)
	elseif name == "Paused" then
		v.paused = val == true
	elseif name == "Tempo" then
		v.tempo = val or 0
	elseif name == "Key" then
		v.key = val or 0
	elseif name == "Echo" then
		v.echo = val or 3
	elseif name == "Guide" then
		v.guide = val ~= false
	elseif name == "ScoreOn" then
		v.scoreOn = val ~= false
	elseif name == "Mics" then
		v.mics = S.decode(val) or { 0, 0 }
	elseif name == "Singers" then
		v.singers = S.decode(val) or {}
	elseif name == "Vibe" then
		v.vibe = val or 0
	elseif name == "Result" then
		v.result = S.decode(val)
	elseif name == "NextT" then
		v.nextT = val or 0
	elseif name == "IdleT" then
		v.idleT = val or 0
	elseif name == "EmptyT" then
		v.emptyT = val or 0
	elseif name == "VoiceRig" then
		v.voiceRig = val == true
	end
end

local ATTRS = { "State", "Renter", "RenterName", "Credits", "Unlimited", "Privacy", "Allowed", "Members", "Queue", "Serial", "Song", "SongNo", "Clock", "Paused", "Tempo", "Key", "Echo", "Guide", "ScoreOn", "Mics", "Singers", "Vibe", "Result", "NextT", "IdleT", "EmptyT", "VoiceRig" }

local function findPart(m: Instance, name: string): BasePart?
	local p = m:FindFirstChild(name, true)
	if p and p:IsA("BasePart") then
		return p
	end
	return nil
end

local function bindModel(v: any, m: Model?)
	v.model = m
	v.parts = {}
	v.zone, v.panel, v.screen = nil, nil, nil
	if not m then
		fire(v, "Model")
		return
	end
	v.zone = findPart(m, "KaraokeZone")
	v.panel = findPart(m, "KaraokePanel")
	v.screen = findPart(m, "KaraokeScreen")
	local parts = v.parts
	parts.machine = findPart(m, "KaraokeMachine")
	parts.remote = findPart(m, "Remote")
	parts.book = findPart(m, "SongBook")
	parts.tamb = findPart(m, "Tambourine")
	parts.ball = findPart(m, "MirrorBall")
	parts.laser = findPart(m, "LaserProjector")
	parts.table = findPart(m, "TableTop")
	local mics = {}
	for _, d in m:GetDescendants() do
		if d.Name == "WirelessMic" and d:IsA("BasePart") then
			table.insert(mics, d)
		end
	end
	table.sort(mics, function(a, b)
		local az, bz = math.floor(a.Position.Z * 10 + 0.5), math.floor(b.Position.Z * 10 + 0.5)
		if az ~= bz then
			return az < bz
		end
		return a.Position.X < b.Position.X
	end)
	parts.mics = { mics[1], mics[2] }
	-- frames read once (the interior team may hide the props locally; their poses stay valid)
	if v.zone then
		v.zoneCF, v.zoneSize = v.zone.CFrame, v.zone.Size
		v.floorY = v.zone.Position.Y - v.zone.Size.Y * 0.5
	end
	if v.panel and v.zone then
		local d = (v.panel.Position - v.zone.Position) * Vector3.new(1, 0, 1)
		v.outDir = if d.Magnitude > 0.01 then d.Unit else Vector3.new(-1, 0, 0)
	end
	fire(v, "Model")
end

local function modelFor(no: number): Model?
	for _, m in CollectionService:GetTagged(S.NAMES.Tag) do
		if m:IsA("Model") and tonumber(m:GetAttribute("RoomNo")) == no and m:FindFirstChild("KaraokeZone", true) then
			return m
		end
	end
	return nil
end

local function addView(cfg: Instance)
	if not cfg:IsA("Configuration") then
		return
	end
	local no = tonumber(string.match(cfg.Name, "^" .. S.NAMES.RoomPrefix .. "(%d+)$"))
	if not no or Rooms.views[no] then
		return
	end
	local v: any = { no = no, name = S.roomName(no), cfg = cfg, parts = {} }
	for _, a in ATTRS do
		read(v, a)
	end
	Rooms.views[no] = v
	cfg.AttributeChanged:Connect(function(a)
		read(v, a)
		fire(v, a)
	end)
	bindModel(v, modelFor(no))
end

function Rooms.songTime(v: any, t: number): number
	return S.songTime(v.clock, t)
end

function Rooms.allowedMe(v: any): boolean
	if not v or v.renter == 0 then
		return false
	end
	local uid = player.UserId
	return v.renter == uid or v.allowed[uid] == true
end

function Rooms.isRenter(v: any): boolean
	return v ~= nil and v.renter == player.UserId
end

function Rooms.micSlot(v: any): number
	if not v or not v.mics then
		return 0
	end
	for i = 1, 2 do
		if v.mics[i] == player.UserId then
			return i
		end
	end
	return 0
end

function Rooms.isSinger(v: any): boolean
	if not v or v.state ~= "play" then
		return false
	end
	for _, s in v.singers or {} do
		if s.u == player.UserId then
			return true
		end
	end
	return Rooms.micSlot(v) > 0
end

function Rooms.current(): any?
	return cur
end

local function rootPos(): Vector3?
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end
Rooms.rootPos = rootPos

local function inside(v: any, pos: Vector3, pad: number): boolean
	if not v.zoneCF then
		return false
	end
	local lp = v.zoneCF:PointToObjectSpace(pos)
	local h = v.zoneSize * 0.5
	return math.abs(lp.X) <= h.X + pad and math.abs(lp.Z) <= h.Z + pad and lp.Y >= -h.Y - 4 and lp.Y <= h.Y + 3
end

function Rooms.near(reach: number?): any?
	local pos = rootPos()
	if not pos then
		return nil
	end
	local best, bd = nil, reach or 12
	for _, v in Rooms.views do
		if v.panel and v.panel.Parent then
			local d = (v.panel.Position - pos).Magnitude
			if d < bd then
				best, bd = v, d
			end
		end
	end
	return best
end

local function setCurrent(v: any?)
	if v == cur then
		return
	end
	local prev = cur
	cur = v
	for _, fn in enteredFns do
		local ok, err = pcall(fn, v, prev)
		if not ok then
			warn("[GwangalliKaraokePlus] room entered:", err)
		end
	end
end

function Rooms.update(dt: number)
	acc += dt
	if acc < 0.2 then
		return
	end
	acc = 0
	local pos = rootPos()
	local found = nil
	if pos then
		if cur and inside(cur, pos, 0.4) then
			found = cur
		else
			for _, v in Rooms.views do
				if inside(v, pos, 0) then
					found = v
					break
				end
			end
		end
		if not found then
			-- streamed-out zone: trust the server's room attribute
			local no = player:GetAttribute(S.NAMES.PlayerRoom)
			local v = type(no) == "number" and Rooms.views[no]
			if v and not v.zoneCF then
				found = v
			end
		end
	end
	setCurrent(found)
end

function Rooms.init(k: any)
	K = k
	S = k.S
	local folder = k.stateFolder :: Instance
	for _, c in folder:GetChildren() do
		addView(c)
	end
	folder.ChildAdded:Connect(addView)
	local function onTagged(m: Instance)
		task.defer(function()
			local no = tonumber(m:GetAttribute("RoomNo"))
			local v = no and Rooms.views[no]
			if v and m:IsA("Model") and m:FindFirstChild("KaraokeZone", true) then
				bindModel(v, m)
			elseif v and m:IsA("Model") then
				-- parts may still be streaming in
				task.wait(1)
				if m.Parent and m:FindFirstChild("KaraokeZone", true) then
					bindModel(v, m)
				end
			end
		end)
	end
	CollectionService:GetInstanceAddedSignal(S.NAMES.Tag):Connect(onTagged)
	CollectionService:GetInstanceRemovedSignal(S.NAMES.Tag):Connect(function(m)
		local no = tonumber(m:GetAttribute("RoomNo"))
		local v = no and Rooms.views[no]
		if v and v.model == m then
			bindModel(v, nil)
		end
	end)
	-- parts of a tagged model that streamed in late
	task.spawn(function()
		while true do
			task.wait(3)
			for no, v in Rooms.views do
				if not v.model or not v.zone or not v.zone.Parent or not v.screen or not v.screen.Parent then
					local m = modelFor(no)
					if m and (m ~= v.model or not (v.zone and v.zone.Parent and v.screen and v.screen.Parent)) then
						bindModel(v, m)
					end
				end
			end
		end
	end)
end

return Rooms
