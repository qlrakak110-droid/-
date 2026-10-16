-- GwangalliKaraokePlus/Rooms: the 8 coin booths on the server.
-- Discovery (tag KaraokeRoom + RoomNo + KaraokeZone / KaraokePanel / KaraokeScreen inside a venue of
-- Config.VenueModelNames), room records, membership (zone box test), privacy (잠금 / 친구만 / 누구나),
-- knock / invite / kick, intruder guidance, coin credits (buy), renter handover, empty / idle release,
-- and publishing the room state as attributes of ReplicatedStorage.GwangalliKaraokeShared.State.Room_NN
-- (+ the legacy-compatible booth Model attributes other teams read).

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local Rooms = {}

local K: any
local S: any
local C: any
local Net: any
local Bridge: any

local list: { any } = {}
local byNo: { [number]: any } = {}
local playerRoom: { [Player]: any } = {}
local stateFolder: Folder
local ridCache: { [Player]: { [string]: { t: number, res: any } } } = {}
local journeyOpened: { [Player]: { [number]: boolean } } = {}
local knockAt: { [Player]: number } = {}

-------------------------------------------------------------------------------------------------
-- helpers
-------------------------------------------------------------------------------------------------
local function now(): number
	return S.now()
end

local function rootOf(p: Player): BasePart?
	local ch = p.Character
	if not ch then
		return nil
	end
	local hum = ch:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health <= 0 then
		return nil
	end
	local root = ch:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end
Rooms.rootOf = rootOf

local function inZone(zone: BasePart, pos: Vector3, pad: number): boolean
	local lp = zone.CFrame:PointToObjectSpace(pos)
	local h = zone.Size * 0.5
	return math.abs(lp.X) <= h.X + pad and math.abs(lp.Z) <= h.Z + pad and lp.Y >= -h.Y - 4 and lp.Y <= h.Y + 3
end
Rooms.inZone = inZone

local function venueOf(inst: Instance): Instance?
	local a = inst.Parent
	while a and a ~= workspace do
		for _, n in C.VenueModelNames do
			if a.Name == n then
				return a
			end
		end
		a = a.Parent
	end
	return nil
end

local function findPart(m: Instance, name: string): BasePart?
	local p = m:FindFirstChild(name, true)
	if p and p:IsA("BasePart") then
		return p
	end
	return nil
end

-- sorted the same way on the server and on every client
local function micParts(m: Instance): { BasePart }
	local out = {}
	for _, d in m:GetDescendants() do
		if d.Name == "WirelessMic" and d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	table.sort(out, function(a, b)
		local az, bz = math.floor(a.Position.Z * 10 + 0.5), math.floor(b.Position.Z * 10 + 0.5)
		if az ~= bz then
			return az < bz
		end
		return a.Position.X < b.Position.X
	end)
	return out
end

-------------------------------------------------------------------------------------------------
-- records
-------------------------------------------------------------------------------------------------
local function newRecord(m: Model, no: number, zone: BasePart, panel: BasePart, screen: BasePart): any
	local cfg = Instance.new("Configuration")
	cfg.Name = S.NAMES.RoomPrefix .. S.roomName(no)
	local floorY = zone.Position.Y - zone.Size.Y * 0.5
	local d = (panel.Position - zone.Position) * Vector3.new(1, 0, 1)
	d = if d.Magnitude > 0.01 then d.Unit else Vector3.new(-1, 0, 0)
	local mics = {}
	for i, mp in micParts(m) do
		if i > 2 then
			break
		end
		mics[i] = mp.Position
	end
	local r = {
		no = no,
		name = S.roomName(no),
		model = m,
		zone = zone,
		panel = panel,
		screen = screen,
		floorY = floorY,
		outDir = d,
		micPos = mics,
		cfg = cfg,
		cache = {},
		-- rental
		renter = nil :: Player?,
		renterId = 0,
		renterName = "",
		credits = 0,
		unlimited = false,
		bonusUsed = 0,
		paying = false,
		privacy = C.DefaultPrivacy,
		allowed = {} :: { [number]: boolean },
		allowedOrder = {} :: { number },
		friend = {} :: { [number]: any },
		members = {} :: { [Player]: number },
		intruders = {} :: { [Player]: number },
		emptySince = nil :: number?,
		idleSince = nil :: number?,
		-- playback (Playback.luau)
		state = "free",
		queue = {} :: { any },
		qSerial = 0,
		serial = 0,
		song = nil :: any,
		chart = nil :: any,
		clock = nil :: any,
		paused = false,
		tempo = 0,
		key = 0,
		echo = C.EchoDefault,
		guide = true,
		scoreOn = true,
		mics = { 0, 0 },
		vibe = 0,
		result = "",
		nextT = 0,
		tambUntil = 0,
		voiceRig = false,
	}
	cfg.Parent = stateFolder
	return r
end

local function addBooth(inst: Instance)
	if not inst:IsA("Model") then
		return
	end
	local no = tonumber(inst:GetAttribute("RoomNo"))
	if not no or no < 1 or no > 99 or byNo[no] then
		return
	end
	if not venueOf(inst) then
		return
	end
	local zone = findPart(inst, "KaraokeZone")
	local panel = findPart(inst, "KaraokePanel")
	local screen = findPart(inst, "KaraokeScreen")
	if not (zone and panel and screen) then
		return
	end
	local r = newRecord(inst, no, zone, panel, screen)
	byNo[no] = r
	table.insert(list, r)
	table.sort(list, function(a, b)
		return a.no < b.no
	end)
	Rooms.publish(r)
end

function Rooms.list(): { any }
	return list
end

function Rooms.get(no: any): any?
	local n = S.int(no, 1, 99)
	return n and byNo[n]
end

function Rooms.of(p: Player): any?
	return playerRoom[p]
end

function Rooms.panels(): { BasePart }
	local out = {}
	for _, r in list do
		table.insert(out, r.panel)
	end
	return out
end

function Rooms.venues(): { Instance }
	local seen, out = {}, {}
	for _, r in list do
		local v = venueOf(r.model)
		if v and not seen[v] then
			seen[v] = true
			table.insert(out, v)
		end
	end
	return out
end

function Rooms.memberPlayers(r: any): { Player }
	local out = {}
	for p in r.members do
		if p.Parent == Players then
			table.insert(out, p)
		end
	end
	return out
end

-- the room this player rents (renter anywhere in the server)
function Rooms.rentedBy(p: Player): any?
	for _, r in list do
		if r.renter == p then
			return r
		end
	end
	return nil
end

-------------------------------------------------------------------------------------------------
-- permissions
-------------------------------------------------------------------------------------------------
local function allowUid(r: any, uid: number)
	if not r.allowed[uid] then
		if #r.allowedOrder >= C.AllowedMax then
			return false
		end
		r.allowed[uid] = true
		table.insert(r.allowedOrder, uid)
	end
	return true
end
Rooms.allowUid = allowUid

local function disallowUid(r: any, uid: number)
	if r.allowed[uid] then
		r.allowed[uid] = nil
		local i = table.find(r.allowedOrder, uid)
		if i then
			table.remove(r.allowedOrder, i)
		end
	end
end

local function checkFriend(r: any, p: Player)
	local uid = p.UserId
	if r.friend[uid] ~= nil or not r.renter then
		return
	end
	r.friend[uid] = "pending"
	local renter = r.renter
	task.spawn(function()
		local ok, res = pcall(renter.IsFriendsWith, renter, uid)
		if r.renter == renter then
			r.friend[uid] = ok and res == true
		end
	end)
end

-- true / false / nil (= friend check still pending)
function Rooms.allowed(r: any, p: Player): boolean?
	if not r.renter then
		return true
	end
	local uid = p.UserId
	if uid == r.renterId or r.allowed[uid] then
		return true
	end
	if r.privacy == "open" then
		return true
	end
	if r.privacy == "friends" then
		local f = r.friend[uid]
		if f == "pending" then
			return nil
		end
		if f == nil then
			checkFriend(r, p)
			return nil
		end
		return f == true
	end
	return false
end

-- request guard. need: "near" (inside or at the panel), "inside", "allowed" (inside + allowed),
-- "member" (allowed, anywhere near), "renter"
function Rooms.guard(p: Player, a: any, need: string): (any?, any?)
	local r = Rooms.get(a.room)
	if not r then
		return nil, Net.fail("room")
	end
	local inside = playerRoom[p] == r
	if need == "near" then
		if inside then
			return r, nil
		end
		local root = rootOf(p)
		if not root or (root.Position - r.panel.Position).Magnitude > C.PanelReach then
			return nil, Net.fail("near")
		end
		return r, nil
	end
	if need == "renter" then
		if not r.renter then
			return nil, Net.fail("free")
		end
		if r.renterId ~= p.UserId then
			return nil, Net.fail("renter")
		end
		return r, nil
	end
	if not inside then
		return nil, Net.fail("notInside")
	end
	if not r.renter then
		return nil, Net.fail("free")
	end
	if need == "allowed" and Rooms.allowed(r, p) ~= true then
		return nil, Net.fail("locked")
	end
	return r, nil
end

-------------------------------------------------------------------------------------------------
-- publishing
-------------------------------------------------------------------------------------------------
local function setA(r: any, name: string, v: any)
	if r.cache[name] ~= v then
		r.cache[name] = v
		r.cfg:SetAttribute(name, v)
	end
end

local function setM(r: any, name: string, v: any)
	local key = "m:" .. name
	if r.cache[key] ~= v then
		r.cache[key] = v
		pcall(r.model.SetAttribute, r.model, name, v)
	end
end

function Rooms.publish(r: any)
	local t = now()
	setA(r, "No", r.no)
	setA(r, "Name", r.name)
	setA(r, "State", r.state)
	setA(r, "Renter", r.renterId)
	setA(r, "RenterName", r.renterName)
	setA(r, "Credits", r.credits)
	setA(r, "Unlimited", r.unlimited)
	setA(r, "Privacy", r.privacy)
	setA(r, "Allowed", S.encode(r.allowedOrder))
	local mem = {}
	for p in r.members do
		if p.Parent == Players then
			table.insert(mem, p.UserId)
		end
	end
	table.sort(mem)
	setA(r, "Members", S.encode(mem))
	local q = {}
	for _, e in r.queue do
		table.insert(q, { q = e.q, s = e.s, by = e.by, n = e.n, d = e.d })
	end
	setA(r, "Queue", S.encode(q))
	setA(r, "Serial", r.serial)
	setA(r, "Song", if r.song then r.song.id else "")
	setA(r, "SongNo", if r.song then r.song.no else 0)
	setA(r, "Clock", if r.clock then S.formatClock(r.clock.serial, r.clock.anchorT, r.clock.anchorS, r.clock.rate) else "")
	setA(r, "Paused", r.paused)
	setA(r, "Tempo", r.tempo)
	setA(r, "Key", r.key)
	setA(r, "Echo", r.echo)
	setA(r, "Guide", r.guide)
	setA(r, "ScoreOn", r.scoreOn)
	setA(r, "Mics", S.encode(r.mics))
	setA(r, "Singers", K.Scoring.singersJSON(r))
	setA(r, "Vibe", math.floor(r.vibe + 0.5))
	setA(r, "Result", r.result)
	setA(r, "NextT", r.nextT)
	setA(r, "IdleT", if r.idleSince and r.renter then r.idleSince + C.IdleRelease else 0)
	setA(r, "EmptyT", if r.emptySince and r.renter then r.emptySince + C.EmptyGrace else 0)
	setA(r, "VoiceRig", r.voiceRig)
	-- legacy-compatible mirrors on the booth model (StatusLight / panel paint / interior LCD + VFD)
	setM(r, S.NAMES.KRenter, r.renterId)
	setM(r, S.NAMES.KRenterName, r.renterName)
	local paidKey = string.format("%d:%d:%s", r.renterId, r.credits, tostring(r.unlimited))
	if r.cache.paidKey ~= paidKey then
		r.cache.paidKey = paidKey
		local paid = if r.renterId == 0 then 0 elseif r.unlimited then t + 3600 else t + 60 * r.credits
		pcall(r.model.SetAttribute, r.model, S.NAMES.KPaidUntil, paid)
	end
	setM(r, S.NAMES.KPState, r.state)
	setM(r, S.NAMES.KPCredits, if r.unlimited then 99 else r.credits)
	setM(r, S.NAMES.KPSongNo, if r.song then r.song.no else 0)
	local out = {}
	for i = 1, 2 do
		if r.mics[i] ~= 0 then
			table.insert(out, tostring(i))
		end
	end
	setM(r, S.NAMES.KPMicsOut, table.concat(out, ","))
	setM(r, S.NAMES.KPTambOut, t < r.tambUntil)
end

-------------------------------------------------------------------------------------------------
-- rent / release / handover
-------------------------------------------------------------------------------------------------
local function journeyOpen(r: any, p: Player)
	local jo = journeyOpened[p]
	if not jo then
		jo = {}
		journeyOpened[p] = jo
	end
	if jo[r.no] then
		return
	end
	jo[r.no] = true
	Bridge.journey(p, { kind = "kOpen", room = 0 })
end

local function rent(r: any, p: Player)
	r.renter = p
	r.renterId = p.UserId
	r.renterName = p.DisplayName
	r.credits = 0
	r.unlimited = C.Billing == "free"
	r.bonusUsed = 0
	r.privacy = C.DefaultPrivacy
	table.clear(r.allowed)
	table.clear(r.allowedOrder)
	table.clear(r.friend)
	allowUid(r, p.UserId)
	-- everyone already standing in the room came in together
	for m in r.members do
		if m ~= p and m.Parent == Players then
			allowUid(r, m.UserId)
		end
	end
	r.state = "open"
	r.idleSince = now()
	r.emptySince = nil
	r.echo = C.EchoDefault
	r.tempo, r.key = 0, 0
	r.guide, r.scoreOn = true, true
	journeyOpen(r, p)
	for m in r.members do
		if m ~= p then
			journeyOpen(r, m)
		end
	end
	K.Store.bump(p, "rooms", 1)
end

function Rooms.release(r: any, reason: string?)
	local renter = r.renter
	local who = Rooms.memberPlayers(r)
	K.Playback.abort(r)
	K.Mics.returnAll(r, nil)
	K.Voice.release(r)
	r.renter = nil
	r.renterId = 0
	r.renterName = ""
	r.credits = 0
	r.unlimited = false
	r.bonusUsed = 0
	r.privacy = C.DefaultPrivacy
	table.clear(r.allowed)
	table.clear(r.allowedOrder)
	table.clear(r.friend)
	table.clear(r.intruders)
	r.emptySince = nil
	r.idleSince = nil
	r.state = "free"
	r.tempo, r.key, r.echo = 0, 0, C.EchoDefault
	r.guide, r.scoreOn = true, true
	r.vibe = 0
	r.result = ""
	r.nextT = 0
	Rooms.publish(r)
	if reason then
		local title = string.format("🎤 ROOM %s 이용 종료", r.name)
		if renter and renter.Parent == Players then
			Net.toast(renter, title, reason, "info")
		end
		for _, m in who do
			if m ~= renter then
				Net.toast(m, title, reason, "info")
			end
		end
	end
end

local function handover(r: any)
	local best: Player? = nil
	local bestT = math.huge
	for m, since in r.members do
		if m ~= r.renter and m.Parent == Players and r.allowed[m.UserId] and since < bestT then
			best, bestT = m, since
		end
	end
	if not best then
		Rooms.release(r, nil)
		return
	end
	r.renter = best
	r.renterId = best.UserId
	r.renterName = best.DisplayName
	allowUid(r, best.UserId)
	table.clear(r.friend)
	Rooms.publish(r)
	for _, m in Rooms.memberPlayers(r) do
		Net.toast(m, "👑 방장이 바뀌었어요", string.format("이제 %s님이 ROOM %s의 방장이에요", best.DisplayName, r.name), "info")
	end
end

-------------------------------------------------------------------------------------------------
-- membership + intruders (2 Hz)
-------------------------------------------------------------------------------------------------
local function pushOut(r: any, p: Player)
	local ch = p.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	if not (ch and hum) then
		return
	end
	if hum.SeatPart then
		hum.Sit = false
		task.wait(0.1)
	end
	local d = r.outDir
	local target = Vector3.new(r.panel.Position.X, r.floorY + 3, r.panel.Position.Z) + d * 3.5
	Bridge.allowTeleport(p, 3)
	pcall(function()
		(ch :: Model):PivotTo(CFrame.lookAt(target, target + d))
	end)
end
Rooms.pushOut = pushOut

local function enter(r: any, p: Player)
	r.members[p] = now()
	r.emptySince = nil
	p:SetAttribute(S.NAMES.PlayerRoom, r.no)
	if r.renter then
		local a = Rooms.allowed(r, p)
		if a == true then
			if r.privacy == "open" then
				allowUid(r, p.UserId)
			end
			journeyOpen(r, p)
		else
			r.intruders[p] = now()
		end
	end
	K.Voice.membersChanged(r)
end

local function leave(r: any, p: Player)
	r.members[p] = nil
	r.intruders[p] = nil
	if p.Parent == Players and p:GetAttribute(S.NAMES.PlayerRoom) == r.no then
		p:SetAttribute(S.NAMES.PlayerRoom, 0)
	end
	K.Voice.membersChanged(r)
end

function Rooms.membership()
	local t = now()
	for _, p in Players:GetPlayers() do
		local root = rootOf(p)
		local cur = playerRoom[p]
		local found = nil
		if root then
			local pos = root.Position
			if cur and inZone(cur.zone, pos, 0.4) then
				found = cur -- hysteresis: stay in the current room near its edge
			else
				for _, r in list do
					if inZone(r.zone, pos, 0) then
						found = r
						break
					end
				end
			end
		end
		if found ~= cur then
			if cur then
				leave(cur, p)
			end
			playerRoom[p] = found
			if found then
				enter(found, p)
			end
		end
	end
	for _, r in list do
		-- intruders
		for p, since in r.intruders do
			if p.Parent ~= Players or playerRoom[p] ~= r then
				r.intruders[p] = nil
				continue
			end
			local a = Rooms.allowed(r, p)
			if a == true then
				r.intruders[p] = nil
				if r.privacy == "open" then
					allowUid(r, p.UserId)
				end
				journeyOpen(r, p)
			elseif a == false or t - since > 6 then
				if C.PushOutIntruders and t - since >= C.IntruderGrace then
					r.intruders[p] = nil
					task.spawn(pushOut, r, p)
					Net.toast(p, string.format("🔒 ROOM %s은 다른 손님이 이용 중이에요", r.name), "문 옆 패널에서 노크해 보세요", "warn")
				end
			end
		end
		if r.renter then
			-- renter left the game
			if r.renter.Parent ~= Players then
				handover(r)
				continue
			end
			-- empty room
			local anyone = false
			for m in r.members do
				if m.Parent == Players and Rooms.allowed(r, m) == true then
					anyone = true
					break
				end
			end
			if anyone then
				r.emptySince = nil
			else
				r.emptySince = r.emptySince or t
				if t - r.emptySince >= C.EmptyGrace then
					Rooms.release(r, "방이 비어 있어 퇴실 처리됐어요 · 남은 곡은 사라졌어요")
					continue
				end
			end
			-- idle: nothing to sing and nothing playing
			local idle = r.state == "open" and #r.queue == 0 and (r.unlimited or r.credits <= 0)
			if idle then
				r.idleSince = r.idleSince or t
				if t - r.idleSince >= C.IdleRelease then
					Rooms.release(r, "한동안 노래를 부르지 않아 퇴실 처리됐어요")
					continue
				end
			else
				r.idleSince = nil
			end
		end
		Rooms.publish(r)
	end
end

-------------------------------------------------------------------------------------------------
-- ops
-------------------------------------------------------------------------------------------------
local function cachedRid(p: Player, rid: string?): any?
	if not rid then
		return nil
	end
	local c = ridCache[p]
	local e = c and c[rid]
	if e and os.clock() - e.t < 120 then
		return e.res
	end
	return nil
end

local function storeRid(p: Player, rid: string?, res: any)
	if not rid then
		return
	end
	local c = ridCache[p]
	if not c then
		c = {}
		ridCache[p] = c
	end
	for k, e in c do
		if os.clock() - e.t > 120 then
			c[k] = nil
		end
	end
	c[rid] = { t = os.clock(), res = res }
end

local function buy(p: Player, a: any): any
	local rid = S.str(a.rid, 24)
	local cached = cachedRid(p, rid)
	if cached then
		return cached
	end
	local r, err = Rooms.guard(p, a, "near")
	if not r then
		return err
	end
	local pack = S.pack(a.pack)
	if not pack then
		return Net.fail("bad")
	end
	if r.renter and Rooms.allowed(r, p) ~= true then
		return Net.fail("locked")
	end
	local mine = Rooms.rentedBy(p)
	if not r.renter and mine and mine ~= r then
		return Net.fail("another")
	end
	if r.paying or Bridge.busy(p) then
		return Net.fail("busy")
	end
	-- free event mode: renting is free and songs are unlimited
	if C.Billing == "free" then
		if not r.renter then
			rent(r, p)
			Rooms.publish(r)
		end
		local res = { ok = true, credits = r.credits, unlimited = true, free = true }
		storeRid(p, rid, res)
		return res
	end
	if r.renter and r.unlimited then
		return { ok = true, credits = r.credits, unlimited = true }
	end
	if r.credits + pack.songs > C.MaxCredits then
		return Net.fail("full", C.MaxCredits)
	end
	local price = pack.price
	local trial = false
	if not Bridge.hasEconomy() then
		if not C.FreeWhenNoEconomy then
			return Net.fail("disabled")
		end
		price = 0
		trial = true
	end
	r.paying = true
	local label = string.format("코인노래방 ROOM %s · %d곡", r.name, pack.songs)
	local st = if price > 0 then Bridge.spend(p, price, label) else "ok"
	r.paying = false
	if st == "noapi" and C.FreeWhenNoEconomy then
		st = "ok"
		trial = true
	end
	if st ~= "ok" then
		local res = Net.fail(if st == "money" then "money" elseif st == "busy" then "busy" else "error")
		return res
	end
	if p.Parent ~= Players then
		return Net.fail("error")
	end
	local fresh = false
	if not r.renter then
		rent(r, p)
		fresh = true
	end
	r.credits = math.min(C.MaxCredits, r.credits + pack.songs)
	r.idleSince = nil
	Rooms.publish(r)
	local body = string.format("남은 곡 %d곡%s", r.credits, if trial then " · 무료 체험" else "")
	if fresh then
		Net.toast(p, string.format("🎤 ROOM %s을 잡았어요", r.name), body, "success")
	else
		Net.toast(p, string.format("🪙 %d곡 추가!", pack.songs), body, "success")
		if r.renter ~= p and r.renter then
			Net.toast(r.renter, string.format("🪙 %s님이 %d곡을 넣었어요", p.DisplayName, pack.songs), body, "info")
		end
	end
	local res = { ok = true, credits = r.credits, renter = r.renterId, trial = trial, fresh = fresh }
	storeRid(p, rid, res)
	return res
end

local function privacy(p: Player, a: any): any
	local r, err = Rooms.guard(p, a, "renter")
	if not r then
		return err
	end
	local mode = a.mode
	if mode ~= "lock" and mode ~= "friends" and mode ~= "open" then
		return Net.fail("bad")
	end
	if mode ~= "open" and r.privacy == "open" then
		-- everyone inside right now stays allowed
		for m in r.members do
			allowUid(r, m.UserId)
		end
	end
	r.privacy = mode
	table.clear(r.friend)
	Rooms.publish(r)
	return { ok = true }
end

local function playerById(uid: any): Player?
	local id = S.int(uid, 1, 2 ^ 53)
	if not id then
		return nil
	end
	return Players:GetPlayerByUserId(id)
end

local function invite(p: Player, a: any): any
	local r, err = Rooms.guard(p, a, "renter")
	if not r then
		return err
	end
	local t = playerById(a.userId)
	if not t or t == p then
		return Net.fail("target")
	end
	local tr, pr = rootOf(t), rootOf(p)
	if not (tr and pr) or (tr.Position - r.zone.Position).Magnitude > 60 then
		return Net.fail("target")
	end
	if not allowUid(r, t.UserId) then
		return Net.fail("full", C.AllowedMax)
	end
	r.intruders[t] = nil
	Rooms.publish(r)
	Net.fire(t, { kind = "invited", room = r.no, from = p.UserId, name = p.DisplayName })
	Net.toast(t, string.format("🎤 %s님이 ROOM %s에 초대했어요", p.DisplayName, r.name), "문을 열고 들어오세요!", "success")
	return { ok = true }
end

local function kick(p: Player, a: any): any
	local r, err = Rooms.guard(p, a, "renter")
	if not r then
		return err
	end
	local t = playerById(a.userId)
	if not t or t == p then
		return Net.fail("target")
	end
	disallowUid(r, t.UserId)
	r.friend[t.UserId] = false
	K.Mics.returnPlayer(t, r)
	if playerRoom[t] == r then
		task.spawn(pushOut, r, t)
	end
	Rooms.publish(r)
	Net.toast(t, string.format("ROOM %s에서 나가게 됐어요", r.name), "다른 방을 이용해 주세요", "warn")
	return { ok = true }
end

local function knock(p: Player, a: any): any
	local r, err = Rooms.guard(p, a, "near")
	if not r then
		return err
	end
	if not r.renter then
		return Net.fail("free")
	end
	if Rooms.allowed(r, p) == true then
		return { ok = true, allowed = true }
	end
	local last = knockAt[p] or -math.huge
	if os.clock() - last < C.KnockCooldown then
		return Net.fail("cooldown")
	end
	knockAt[p] = os.clock()
	local renter = r.renter :: Player
	Net.fire(renter, { kind = "knock", room = r.no, from = p.UserId, name = p.DisplayName })
	return { ok = true }
end

local function knockAnswer(p: Player, a: any): any
	local r, err = Rooms.guard(p, a, "renter")
	if not r then
		return err
	end
	local t = playerById(a.userId)
	if not t then
		return Net.fail("target")
	end
	if a.accept == true then
		if not allowUid(r, t.UserId) then
			return Net.fail("full", C.AllowedMax)
		end
		r.intruders[t] = nil
		Rooms.publish(r)
		Net.toast(t, string.format("🚪 ROOM %s · 들어오세요!", r.name), string.format("%s님이 문을 열어 줬어요", p.DisplayName), "success")
	else
		Net.toast(t, string.format("ROOM %s", r.name), "지금은 들어갈 수 없대요 · 다른 방을 이용해 주세요", "info")
	end
	return { ok = true }
end

local function leaveOp(p: Player, a: any): any
	local r = Rooms.get(a.room)
	if not r then
		return Net.fail("room")
	end
	if r.renter == p then
		Rooms.release(r, "퇴실했어요 · 이용해 주셔서 감사합니다")
		if playerRoom[p] == r then
			task.spawn(pushOut, r, p)
		end
		return { ok = true, released = true }
	end
	K.Mics.returnPlayer(p, r)
	if playerRoom[p] == r then
		task.spawn(pushOut, r, p)
	end
	return { ok = true }
end

local function nearby(p: Player, a: any): any
	local r, err = Rooms.guard(p, a, "renter")
	if not r then
		return err
	end
	local out = {}
	for _, o in Players:GetPlayers() do
		if o == p then
			continue
		end
		local root = rootOf(o)
		if root and (root.Position - r.zone.Position).Magnitude <= 60 then
			table.insert(out, { u = o.UserId, n = o.DisplayName, a = r.allowed[o.UserId] == true, i = playerRoom[o] == r })
			if #out >= 16 then
				break
			end
		end
	end
	return { ok = true, players = out }
end

-------------------------------------------------------------------------------------------------
-- init
-------------------------------------------------------------------------------------------------
function Rooms.init(k: any)
	K = k
	S, C, Net, Bridge = k.S, k.S.Config, k.Net, k.Bridge
	local shared = k.sharedModule :: Instance
	local old = shared:FindFirstChild(S.NAMES.State)
	if old then
		old:Destroy()
	end
	stateFolder = Instance.new("Folder")
	stateFolder.Name = S.NAMES.State
	for _, m in CollectionService:GetTagged(S.NAMES.Tag) do
		addBooth(m)
	end
	CollectionService:GetInstanceAddedSignal(S.NAMES.Tag):Connect(function(m)
		task.defer(addBooth, m)
	end)
	stateFolder.Parent = shared

	Net.handle("buy", "money", buy)
	Net.handle("privacy", "ui", privacy)
	Net.handle("invite", "ui", invite)
	Net.handle("kick", "ui", kick)
	Net.handle("knock", "ui", knock)
	Net.handle("knockAnswer", "ui", knockAnswer)
	Net.handle("leave", "ui", leaveOp)
	Net.handle("nearby", "ui", nearby)

	Players.PlayerRemoving:Connect(function(p)
		local r = playerRoom[p]
		if r then
			leave(r, p)
		end
		playerRoom[p] = nil
		ridCache[p] = nil
		journeyOpened[p] = nil
		knockAt[p] = nil
		for _, room in list do
			room.intruders[p] = nil
			if room.renter == p then
				handover(room)
			end
		end
	end)
end

function Rooms.stateFolder(): Folder
	return stateFolder
end

return Rooms
