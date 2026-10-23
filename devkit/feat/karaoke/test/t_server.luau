--!nocheck
-- offline server logic test for GwangalliKaraokePlus (luau CLI + mock.luau)
local M = require("./mock")
local V3, CF = M.Vector3, M.CFrame
local fails = 0
local function check(cond, msg)
	if cond then
		print("  ok   " .. msg)
	else
		fails += 1
		print("  FAIL " .. msg)
	end
end

-- venue + booth 01
local venue = M.newInst("Model", "광안 코인노래연습장")
venue.Parent = M.workspace
local booth = M.newInst("Model", "Booth_01")
booth:SetAttribute("RoomNo", 1)
booth.Parent = venue
M.tag(booth, "KaraokeRoom")
M.part("KaraokeZone", V3.new(32.35, 12.4, 299.01), V3.new(11.6, 11.2, 17.3), math.rad(90)).Parent = booth
M.part("KaraokePanel", V3.new(23.18, 12.1, 298.15), V3.new(1.1, 2, 0.2)).Parent = booth
local scr = M.part("KaraokeScreen", V3.new(40.52, 13.1, 299.01), V3.new(8.84, 5.04, 0.05))
scr:SetAttribute("GuiFace", "Back")
scr.Parent = booth
M.part("WirelessMic", V3.new(32.8, 8.67, 299.51), V3.new(1.2, 0.3, 0.3)).Parent = booth
M.part("WirelessMic", V3.new(33.2, 8.67, 298.21), V3.new(1.2, 0.3, 0.3)).Parent = booth
local led = M.part("LEDScreen", V3.new(40, 13, 276), V3.new(1, 1, 1))
led.Parent = venue
M.tag(led, "LEDScreen")

-- owner APIs
local cash = {}
local calls = { progress = 0, social = 0, stats = 0, earn = 0 }
local api = M.newInst("BindableFunction", "GwangalliGameplayAPI")
api.Invoke = function(_, op, player, amount, label)
	if op == "balance" then
		return cash[player.UserId] or 0, 0
	elseif op == "spend" then
		local c = cash[player.UserId] or 0
		if c < amount then
			return false
		end
		cash[player.UserId] = c - amount
		return true
	elseif op == "earn" then
		calls.earn += amount
		return true
	elseif op == "addStats" then
		calls.stats += 1
		return amount
	end
end
api.Parent = M.game:GetService("ServerStorage")
local prog = M.newInst("BindableFunction", "GwangalliProgressAPI")
prog.Invoke = function(_, op, player, key, n)
	if op == "track" and key == "karaoke_song" then
		calls.progress += n
	end
end
prog.Parent = M.game:GetService("ServerStorage")
local soc = M.newInst("BindableFunction", "GwangalliSocialAPI")
soc.Invoke = function(_, op)
	if op == "joint" then
		calls.social += 1
	end
end
soc.Parent = M.game:GetService("ServerStorage")

-- events to players
local events = {}
M.onEvent = function(remote, p, payload)
	events[p.UserId] = events[p.UserId] or {}
	table.insert(events[p.UserId], payload)
end
local function lastEvent(uid, kind)
	for i = #(events[uid] or {}), 1, -1 do
		if events[uid][i].kind == kind then
			return events[uid][i]
		end
	end
	return nil
end

-- modules
local RS = M.game:GetService("ReplicatedStorage")
local shared = M.scriptObj("sh/init.luau", "sh/")
shared.Name = "GwangalliKaraokeShared"
shared.Parent = RS
local server = M.scriptObj("srv/init.server.luau", "srv/")
server.Name = "GwangalliKaraokePlus"
server.Parent = M.game:GetService("ServerScriptService")
task = M.task
M.task.spawn(function()
	M.load("srv/init.server.luau", server)
end)
M.advance(14)
check(shared:GetAttribute("Active") == true, "server active")
local S = M.load("sh/init.luau", shared)
local state = shared:FindFirstChild("State")
local room = state and state:FindFirstChild("Room_01")
check(room ~= nil, "Room_01 state")
local rf = shared:FindFirstChild("Remotes"):FindFirstChild("KPRequest")

local function req(p, op, payload)
	local box = {}
	M.task.spawn(function()
		box.r = rf.OnServerInvoke(p, op, payload)
	end)
	local n = 0
	while box.r == nil and n < 400 do
		M.advance(0.05)
		n += 1
	end
	return box.r or { ok = false, code = "hang" }
end

print("== rent")
local A = M.addPlayer(101, "민수", V3.new(19.5, 9.9, 298.5))
cash[101] = 5000
M.advance(1)
local r = req(A, "buy", { room = 1, pack = "p4", rid = "x1" })
check(r.ok and r.credits == 4, "buy p4 from corridor -> 4 credits (" .. tostring(r.code) .. ")")
check(cash[101] == 4000, "1,000원 spent")
local r2 = req(A, "buy", { room = 1, pack = "p4", rid = "x1" })
check(r2.ok and cash[101] == 4000, "same rid not charged twice")
check(booth:GetAttribute("KRenter") == 101, "KRenter compat attr")
check(room:GetAttribute("State") == "open", "state open")
local bad = req(A, "reserve", { room = 1, song = "s54" })
check(not bad.ok and bad.code == "notInside", "reserve from corridor refused")
M.move(A, V3.new(31.5, 9.9, 300.5))
M.advance(1)
check(A:GetAttribute("GwKPRoom") == 1, "membership: inside room 1")
check(not req(A, "reserve", { room = 1, song = "nope" }).ok, "unknown song refused")
check(not req(A, "set", { room = 1, tempo = 99 }).ok, "tempo out of range refused")
check(req(A, "set", { room = 1, echo = 4, key = 2 }).ok, "set echo/key")

print("== sing (perfect taps)")
r = req(A, "reserve", { room = 1, song = "s54" })
check(r.ok, "reserve s54")
M.advance(1.5)
check(room:GetAttribute("State") == "play", "auto start -> play")
check(room:GetAttribute("Credits") == 3, "credit used")
local mics = S.decode(room:GetAttribute("Mics"))
check(mics[1] == 101, "reserver auto-grabbed mic 1")
local clock = S.parseClock(room:GetAttribute("Clock"))
local chart = S.Chart.get(S.Songs.byId.s54, S.Songs)
local serial = room:GetAttribute("Serial")
-- send each tap on time
local batch = {}
for i, n in chart.taps do
	local due = S.realTimeOf(clock, n.t)
	if due > M.clock then
		M.advance(due - M.clock, 0.01)
	end
	table.insert(batch, { i = i, dt = 0.01 })
	if #batch >= 1 then
		local hr = req(A, "hits", { room = 1, serial = serial, hits = batch })
		if not hr.ok then
			print("hits fail", hr.code)
		end
		batch = {}
	end
end
if #batch > 0 then
	M.advance(0.2)
	req(A, "hits", { room = 1, serial = serial, hits = batch })
end
-- a duplicate / out of window hit must not count
M.advance(0.3)
local dup = req(A, "hits", { room = 1, serial = serial, hits = { { i = 1, dt = 0 } } })
check(dup.ok and dup.P == #chart.taps, string.format("all %d taps PERFECT, duplicate ignored (P=%s)", #chart.taps, tostring(dup.P)))
local endT = S.realTimeOf(clock, chart.duration)
M.advance(endT - M.clock + 0.3)
check(room:GetAttribute("State") == "settle", "settle at the end")
M.advance(S.Config.SettleTime + 0.3)
check(room:GetAttribute("State") == "score", "score state")
local res = S.decode(room:GetAttribute("Result"))
check(res and res.sc[1] and res.sc[1].s == 100, "score 100 (" .. tostring(res and res.sc[1] and res.sc[1].s) .. ")")
check(res.b == true and room:GetAttribute("Credits") == 4, "100점 서비스 1곡 (+1 credit)")
local ev = lastEvent(101, "result")
check(ev and ev.mine and ev.mine.score == 100, "personal result event")
print("     rewards: " .. tostring(ev and ev.mine and ev.mine.rewards))
M.advance(0.5)
check(calls.progress == 1, "Progress karaoke_song tracked")
check(calls.social == 1, "Social joint")
check(calls.stats >= 1, "stats via addStats fallback")
check(calls.earn == 300, "score prize earned (" .. calls.earn .. ")")
check(string.find(tostring(led:GetAttribute("Messages")), "노래왕", 1, true) ~= nil, "LED shows 오늘의 노래왕")
M.advance(S.Config.ScoreHold + 0.5)
check(room:GetAttribute("State") == "open", "back to open")

print("== stop refund + queue ops")
local q1 = req(A, "reserve", { room = 1, song = "s02" })
local q2 = req(A, "reserveNo", { room = 1, no = 38131 })
check(q1.ok and q2.ok, "two reservations")
check(req(A, "first", { room = 1, qid = q2.qid }).ok, "우선예약 moves to top")
local qq = S.decode(room:GetAttribute("Queue"))
check(qq[1].s == "s01", "queue head = s01")
M.advance(1.5)
check(room:GetAttribute("Song") == "s01", "s01 playing")
local cBefore = room:GetAttribute("Credits")
M.advance(2)
local st = req(A, "stop", { room = 1 })
check(st.ok and st.refunded == true, "stop within 5 s refunds")
check(room:GetAttribute("Credits") == cBefore + 1, "credit returned")
M.advance(S.Config.StopGap + S.Config.AutoStartDelay + 0.5)
check(room:GetAttribute("Song") == "s02", "next reservation auto-starts")
M.advance(1.5)
check(req(A, "pause", { room = 1 }).ok and room:GetAttribute("Paused") == true, "pause")
check(req(A, "pause", { room = 1 }).ok and room:GetAttribute("Paused") == false, "resume")
check(req(A, "set", { room = 1, tempo = 2 }).ok, "tempo live change")
local c2 = S.parseClock(room:GetAttribute("Clock"))
check(math.abs(c2.rate - 1.1) < 1e-6, "clock rate 1.1")
check(req(A, "restart", { room = 1 }).ok, "처음부터")
M.advance(6)
local st2 = req(A, "stop", { room = 1 })
check(st2.ok and st2.refunded == false, "stop after 5 s: no refund")

print("== intruder, knock, invite")
local B = M.addPlayer(202, "지은", V3.new(19.5, 9.9, 298.5))
M.advance(0.6)
M.move(B, V3.new(31.0, 9.9, 299.0))
M.advance(3)
local bpos = B.Character.HumanoidRootPart.Position
check(bpos.X < 23.18, string.format("intruder guided out (x=%.1f)", bpos.X))
check(lastEvent(202, "toast") ~= nil, "intruder toast")
local kn = req(B, "knock", { room = 1 })
check(kn.ok and lastEvent(101, "knock") ~= nil, "knock reaches the renter")
check(not req(B, "knock", { room = 1 }).ok, "knock cooldown")
check(req(A, "knockAnswer", { room = 1, userId = 202, accept = true }).ok, "renter lets B in")
M.move(B, V3.new(31.0, 9.9, 299.0))
M.advance(3)
check(B:GetAttribute("GwKPRoom") == 1 and B.Character.HumanoidRootPart.Position.X > 25, "B stays inside")
check(not req(B, "privacy", { room = 1, mode = "open" }).ok, "guest cannot change privacy")
check(req(A, "privacy", { room = 1, mode = "lock" }).ok, "renter sets lock")

print("== mics")
local mr = req(A, "mic", { room = 1, action = "pass", to = 202 })
check(mr.ok, "pass offer")
local off = lastEvent(202, "micOffer")
check(off ~= nil, "offer card event")
check(req(B, "micAnswer", { offer = off.offer, accept = true }).ok, "B accepts")
mics = S.decode(room:GetAttribute("Mics"))
check(mics[1] == 202, "mic 1 now B")
check(req(A, "mic", { room = 1, action = "grab" }).ok, "A grabs mic 2")
mics = S.decode(room:GetAttribute("Mics"))
check(mics[2] == 101, "mic 2 = A")
M.move(B, V3.new(18, 9.9, 300))
M.advance(4.5)
mics = S.decode(room:GetAttribute("Mics"))
check(mics[1] == 0, "mic returned after walking out")
M.move(B, V3.new(31.0, 9.9, 299.0))
M.advance(1)

print("== cheer")
local ch1 = req(B, "cheer", { room = 1, kind = "fire" })
check(ch1.ok, "fx fire")
check(not req(B, "cheer", { room = 1, kind = "fire" }).ok, "fx cooldown")
check(not req(B, "cheer", { room = 1, kind = "bomb" }).ok, "unknown fx refused")

print("== handover + release")
M.removePlayer(A)
M.advance(1)
check(room:GetAttribute("Renter") == 202, "renter handed over to B")
M.move(B, V3.new(18, 9.9, 300))
M.advance(S.Config.EmptyGrace + 1.5)
check(room:GetAttribute("State") == "free" and booth:GetAttribute("KRenter") == 0, "empty room released")

print("== free trial without economy")
api.Parent = nil
local Cc = M.addPlayer(303, "하늘", V3.new(19.5, 9.9, 298.5))
M.advance(0.6)
local tr = req(Cc, "buy", { room = 1, pack = "p1", rid = "z" })
check(tr.ok and tr.trial == true, "free trial when the money API is missing")

print("== voice scoring + tambourine + no credits + idle")
M.move(Cc, V3.new(31.5, 9.9, 300.5))
local D = M.addPlayer(404, "도윤", V3.new(31.0, 9.9, 299.5))
M.advance(1.2)
check(req(Cc, "privacy", { room = 1, mode = "open" }).ok, "open room")
M.advance(1)
check(D:GetAttribute("GwKPRoom") == 1 and D.Character.HumanoidRootPart.Position.X > 25, "open room: D stays")
-- the engine's voice device (Audio API voice chat) for the voice singer
M.newInst("AudioDeviceInput", "AudioDeviceInput").Parent = Cc
check(req(D, "voice", { room = 1, serial = 0, lines = { { li = 1, v = 1, r = 1, o = 1 } } }).ok ~= true, "voice lines refused without a song / device")
check(req(Cc, "reserve", { room = 1, song = "s46" }).ok, "reserve 아리랑")
M.advance(1.5)
check(room:GetAttribute("State") == "play", "playing with trial credit")
local ck = S.parseClock(room:GetAttribute("Clock"))
local ch2 = S.Chart.get(S.Songs.byId.s46, S.Songs)
local ser = room:GetAttribute("Serial")
local onBeatSent = 0
for li, l in ch2.lines do
	local due = S.realTimeOf(ck, l.due)
	-- D shakes the tambourine on the beat a few times per line, plus the same beat twice (must not farm)
	local bt = S.realTimeOf(ck, l.t0)
	if bt > M.clock then
		M.advance(bt - M.clock, 0.02)
	end
	local stNow = S.songTime(ck, M.clock)
	local beatT = math.floor(stNow / (ch2.beat / 2) + 0.5) * (ch2.beat / 2)
	req(D, "cheer", { room = 1, kind = "tamb", beats = { beatT } })
	M.advance(0.3)
	req(D, "cheer", { room = 1, kind = "tamb", beats = { beatT, beatT } })
	onBeatSent += 1
	if due > M.clock then
		M.advance(due - M.clock + 0.05, 0.05)
	end
	local vr = req(Cc, "voice", { room = 1, serial = ser, lines = { { li = li, v = 0.9, r = 0.8, o = 0.7 } } })
	if not vr.ok then
		print("voice fail", li, vr.code)
	end
end
local endT2 = S.realTimeOf(ck, ch2.duration)
M.advance(endT2 - M.clock + S.Config.SettleTime + 0.6)
local res2 = S.decode(room:GetAttribute("Result"))
local row = res2 and res2.sc[1]
check(row and row.m == "voice" and row.s >= 90, string.format("voice score %s (%s), vibe +%s", tostring(row and row.s), tostring(row and row.m), tostring(row and row.v)))
check(row and row.v <= 3, "vibe bonus capped")
check(room:GetAttribute("Credits") == 1, "100점 bonus credit again")
M.advance(S.Config.ScoreHold + 1)
check(req(Cc, "reserve", { room = 1, song = "s02" }).ok, "reserve with the bonus credit")
M.advance(8)
check(req(Cc, "stop", { room = 1 }).ok and room:GetAttribute("Credits") == 0, "credits used up")
M.advance(1)
check(req(Cc, "reserve", { room = 1, song = "s02" }).ok, "reserve with 0 credits allowed")
M.advance(3)
check(room:GetAttribute("State") == "open", "queue waits without credits")
check(req(Cc, "cancel", { room = 1, qid = S.decode(room:GetAttribute("Queue"))[1].q }).ok, "cancel own")
M.advance(S.Config.IdleRelease + 2)
check(room:GetAttribute("State") == "free", "idle release")
print(string.format("\n%d failures", fails))
