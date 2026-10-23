-- GwangalliKaraokePlus/Mics: the two wireless mics of each room.
-- grab / put / pass (offer card, 10 s) / accept; the holder shows the sing pose + a hand mic for
-- everyone (VenueLife act "sing" + prop "mic"). A mic goes back to the table when its holder walks out
-- for a few seconds, respawns, or leaves the game. Mic holders are the song's singers (1P / 2P).

local Players = game:GetService("Players")

local Mics = {}

local K: any
local S: any
local C: any
local Net: any
local Rooms: any
local Bridge: any

local offers: { [number]: any } = {}
local offerSerial = 0
local outside: { [Player]: number } = {}

local function slotOf(r: any, uid: number): number
	for i = 1, 2 do
		if r.mics[i] == uid then
			return i
		end
	end
	return 0
end
Mics.slotOf = slotOf

local function setHolder(r: any, slot: number, p: Player?)
	local prev = r.mics[slot]
	if prev ~= 0 then
		local pp = Players:GetPlayerByUserId(prev)
		if pp then
			Bridge.clearAct(pp)
			pp:SetAttribute(S.NAMES.PlayerMic, 0)
		end
	end
	r.mics[slot] = if p then p.UserId else 0
	if p then
		Bridge.setAct(p, "sing", nil, "mic")
		p:SetAttribute(S.NAMES.PlayerMic, slot)
		outside[p] = nil
		if r.state == "play" then
			K.Scoring.addSinger(r, p, slot)
		end
	end
	K.Voice.refresh(r)
end

local function holderRoom(p: Player): (any?, number)
	for _, r in Rooms.list() do
		local s = slotOf(r, p.UserId)
		if s > 0 then
			return r, s
		end
	end
	return nil, 0
end
Mics.holderRoom = holderRoom

function Mics.autoGrab(r: any, p: Player)
	if slotOf(r, p.UserId) > 0 then
		return
	end
	local other = holderRoom(p)
	if other then
		return
	end
	for i = 1, 2 do
		if r.mics[i] == 0 then
			setHolder(r, i, p)
			return
		end
	end
end

-- puts every mic of the room back (reason = toast to the holders)
function Mics.returnAll(r: any, reason: string?)
	for i = 1, 2 do
		local uid = r.mics[i]
		if uid ~= 0 then
			local p = Players:GetPlayerByUserId(uid)
			setHolder(r, i, nil)
			if p and reason then
				Net.toast(p, "🎤 마이크를 제자리에 뒀어요", reason, "info")
			end
		end
	end
end

function Mics.returnPlayer(p: Player, onlyRoom: any?)
	local r, s = holderRoom(p)
	if r and (onlyRoom == nil or onlyRoom == r) then
		setHolder(r, s, nil)
		Rooms.publish(r)
	end
end

local function grab(p: Player, a: any): any
	local r, err = Rooms.guard(p, a, "allowed")
	if not r then
		return err
	end
	local mine = slotOf(r, p.UserId)
	if mine > 0 then
		return { ok = true, slot = mine }
	end
	if holderRoom(p) then
		return Net.fail("mic")
	end
	local slot = S.int(a.slot, 1, 2)
	if slot and r.mics[slot] ~= 0 then
		return Net.fail("micBusy")
	end
	if not slot then
		slot = if r.mics[1] == 0 then 1 elseif r.mics[2] == 0 then 2 else nil
	end
	if not slot then
		return Net.fail("micBusy")
	end
	setHolder(r, slot, p)
	Rooms.publish(r)
	return { ok = true, slot = slot }
end

local function put(p: Player, a: any): any
	local r = Rooms.get(a.room)
	if not r then
		return Net.fail("room")
	end
	local s = slotOf(r, p.UserId)
	if s == 0 then
		return { ok = true }
	end
	setHolder(r, s, nil)
	Rooms.publish(r)
	return { ok = true }
end

local function pass(p: Player, a: any): any
	local r, err = Rooms.guard(p, a, "allowed")
	if not r then
		return err
	end
	local s = slotOf(r, p.UserId)
	if s == 0 then
		return Net.fail("mic")
	end
	local uid = S.int(a.to, 1, 2 ^ 53)
	local t = uid and Players:GetPlayerByUserId(uid)
	if not t or t == p or Rooms.of(t) ~= r or Rooms.allowed(r, t) ~= true then
		return Net.fail("target")
	end
	if holderRoom(t) then
		return Net.fail("micBusy")
	end
	offerSerial += 1
	offers[offerSerial] = { id = offerSerial, room = r, from = p.UserId, to = t.UserId, slot = s, exp = os.clock() + C.MicOfferTTL }
	Net.fire(t, { kind = "micOffer", room = r.no, offer = offerSerial, from = p.UserId, name = p.DisplayName, slot = s, ttl = C.MicOfferTTL })
	return { ok = true, offer = offerSerial }
end

local function answer(p: Player, a: any): any
	local id = S.int(a.offer, 1, 2 ^ 31)
	local o = id and offers[id]
	if not o or o.to ~= p.UserId then
		return Net.fail("bad")
	end
	offers[id] = nil
	local giver = Players:GetPlayerByUserId(o.from)
	if os.clock() > o.exp then
		return Net.fail("disabled")
	end
	if a.accept ~= true then
		if giver then
			Net.toast(giver, "🎤 마이크", string.format("%s님이 괜찮대요", p.DisplayName), "info")
		end
		return { ok = true }
	end
	local r = o.room
	if r.mics[o.slot] ~= o.from or Rooms.of(p) ~= r or holderRoom(p) then
		return Net.fail("micBusy")
	end
	setHolder(r, o.slot, p)
	Rooms.publish(r)
	if giver then
		Net.toast(giver, "🎤 마이크를 건넸어요", string.format("이제 %s님 차례!", p.DisplayName), "success")
	end
	return { ok = true, slot = o.slot }
end

local function micOp(p: Player, a: any): any
	local act = a.action
	if act == "grab" then
		return grab(p, a)
	elseif act == "put" then
		return put(p, a)
	elseif act == "pass" then
		return pass(p, a)
	end
	return Net.fail("bad")
end

-- 1 Hz: holders that walked out / died / left
function Mics.step()
	local t = os.clock()
	for _, r in Rooms.list() do
		for i = 1, 2 do
			local uid = r.mics[i]
			if uid == 0 then
				continue
			end
			local p = Players:GetPlayerByUserId(uid)
			if not p then
				setHolder(r, i, nil)
				Rooms.publish(r)
				continue
			end
			if Rooms.of(p) ~= r or not Rooms.rootOf(p) then
				outside[p] = outside[p] or t
				if t - outside[p] >= C.MicReturnGrace then
					outside[p] = nil
					setHolder(r, i, nil)
					Rooms.publish(r)
					Net.toast(p, "🎤 마이크를 제자리에 뒀어요", "방 밖으로 나가서 마이크를 돌려놨어요", "info")
				end
			else
				outside[p] = nil
			end
		end
	end
	for id, o in offers do
		if t > o.exp + 2 then
			offers[id] = nil
		end
	end
end

function Mics.init(k: any)
	K = k
	S, C, Net, Rooms, Bridge = k.S, k.S.Config, k.Net, k.Rooms, k.Bridge
	Net.handle("mic", "ui", micOp)
	Net.handle("micAnswer", "ui", answer)
	local function watch(p: Player)
		p.CharacterAdded:Connect(function()
			-- the hand prop died with the old body: put the mic back
			local r, s = holderRoom(p)
			if r then
				setHolder(r, s, nil)
				Rooms.publish(r)
			end
		end)
	end
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(p)
		local r, s = holderRoom(p)
		if r then
			r.mics[s] = 0
			K.Voice.refresh(r)
			Rooms.publish(r)
		end
		outside[p] = nil
	end)
end

return Mics
