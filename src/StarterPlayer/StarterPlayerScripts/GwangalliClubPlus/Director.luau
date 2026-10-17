-- GwangalliClubPlus.Director: turns club moments into a synced world show (client).
--   LED takeovers (Led.onActivate)  order / 후원 / 합석 / DJ ON AIR -> tier-scaled cues on the beat:
--       일반      floor ripple · laser tint · bartender flair
--       프리미엄  + laser colour burst locking on the table · floor flash · presenter board
--       VIP       + CO2 · confetti · mirror-ball rays · haze · sparkle trails + follow spot on the staff
--       레전드    + laser show · strobe · fireworks · screen flash · double CO2 · gold confetti
--   DJ pads (Event "fx", server time `at`): 레이저 쇼 / CO2 / 폭죽 / 스트로브 / 손 머리 위로
--   the club's own bottle parade (Show attribute): trails, follow spot, heads following the lead staff,
--       confetti at the table when the set lands
--   합석 production (Booking attribute): follow spots + sparkle trails on the MD and the new friends,
--       moving heads follow the walk, confetti + LED note on arrival, 짠 / 댄스 moments
-- Nothing here is authoritative: every cue is derived from replicated server state.

local Director = {}

local Core: any
local S: any
local L: any
local Led: any
local Fx: any
local Lasers: any
local Signs: any

local TEAL = Color3.fromRGB(60, 225, 205)
local GOLD = Color3.fromRGB(255, 194, 71)
local MAGENTA = Color3.fromRGB(255, 60, 190)
local CYAN = Color3.fromRGB(40, 220, 255)
local WHITE = Color3.new(1, 1, 1)

local function safe(fn: any, ...: any)
	if type(fn) == "function" then
		local ok, err = pcall(fn, ...)
		if not ok then
			warn("[GwangalliClubPlus] cue failed:", err)
		end
	end
end

-- run on the next beat (>= `delay` s away)
local function beat(delay: number, fn: () -> ())
	Core.onBeat(delay, function()
		safe(fn)
	end)
end

local function tableTarget(id: any): Vector3?
	local info = Core.tableInfo(id)
	if info and info.top then
		return info.top + Vector3.new(0, 0.4, 0)
	end
	return nil
end

local function boothTarget(): Vector3
	local a = Core.anchor("Show_DJ")
	return if a then a.Position else S.Config.Fallback.DJ
end

local function period(): number
	local _, _, bpm = Core.beat()
	return 60 / bpm
end

-------------------------------------------------------------------------------------------------
-- tier cues (shared by orders and 후원)
-------------------------------------------------------------------------------------------------
local function tierCue(tier: number, color: Color3, accent: Color3, target: Vector3?)
	local p = period()
	safe(Fx.ripple, color, target, math.clamp(tier, 1, 3))
	if tier <= 1 then
		safe(Lasers.cue, "flash", { color = color, beats = 4, k = 0.55, target = target })
		return
	end
	safe(Fx.floorFlash, color)
	if tier == 2 then
		safe(Lasers.cue, "flash", { color = color, color2 = accent, beats = 8, target = target })
		return
	end
	if tier == 3 then
		safe(Lasers.cue, "flash", { color = color, color2 = accent, beats = 12, target = target })
		beat(0.3, function()
			Fx.co2(1)
			Fx.confetti(0.6)
		end)
		safe(Fx.mirror, 6)
		safe(Fx.hazeBoost, 10)
		return
	end
	-- 레전드
	safe(Lasers.cue, "show", { beats = 16, k = 1 })
	beat(0.3, function()
		Fx.strobe(1.2)
		Fx.flash(GOLD, 0.8)
		Fx.co2(2)
		Fx.confetti(1.2)
	end)
	beat(p * 4 + 0.2, function()
		Fx.co2(1.5)
		Fx.fireworks(4)
	end)
	task.delay(p * 16 + 0.1, function()
		if target then
			safe(Lasers.cue, "lock", { target = target, color = GOLD, color2 = color, beats = 8 })
		end
	end)
	safe(Fx.mirror, 10)
	safe(Fx.hazeBoost, 14)
end

local function onActivate(it: any, late: number)
	if late > 1.5 or not Core.inside then
		return
	end
	local d = it.data or {}
	local kind = it.kind
	if kind == "order" or kind == "band" then
		local tier = if kind == "band" then 1 else it.tier
		local T = S.tier(tier)
		tierCue(tier, T.color, T.accent, tableTarget(d.table))
		safe(Signs.flair, d.table, tier)
	elseif kind == "donate" then
		local T = S.tier(it.tier)
		local to = d.to or {}
		local target = if to.k == "table" then tableTarget(to.id) elseif to.k == "dj" then boothTarget() else nil
		tierCue(it.tier, T.color, T.accent, target)
		if to.k == "table" then
			safe(Signs.ping, to.id, L.Show.signGift, 8)
		end
	elseif kind == "booking" then
		local target = tableTarget(d.table)
		safe(Lasers.cue, "flash", { color = TEAL, color2 = GOLD, beats = 8, target = target })
		safe(Fx.ripple, TEAL, target, 2)
		beat(0.3, function()
			Fx.confetti(0.4)
		end)
	elseif kind == "djon" then
		safe(Lasers.cue, "show", { beats = 8, color = MAGENTA, color2 = CYAN })
		beat(0.3, function()
			Fx.strobe(1.4)
			Fx.co2(1.5)
			Fx.ripple(MAGENTA, nil, 3)
		end)
	elseif kind == "dj" then
		safe(Lasers.cue, "flash", { color = CYAN, color2 = MAGENTA, beats = 4, k = 0.8 })
		safe(Fx.ripple, CYAN, nil, 2)
	end
end

-------------------------------------------------------------------------------------------------
-- DJ pads
-------------------------------------------------------------------------------------------------
local seenFx: { [string]: boolean } = {}
local function onFx(p: any)
	if type(p.kind) ~= "string" or type(p.at) ~= "number" then
		return
	end
	local key = string.format("%s@%.2f", p.kind, p.at)
	if seenFx[key] then
		return
	end
	seenFx[key] = true
	local delay = p.at - Core.now()
	if delay < -2 or not Core.inside then
		return
	end
	local n = tostring(p.n or "")
	local function go()
		if p.kind == "laser" then
			Lasers.cue("show", { beats = 16, k = 1 })
			Fx.hazeBoost(8)
		elseif p.kind == "co2" then
			Fx.co2(2.2)
		elseif p.kind == "fireworks" then
			Fx.fireworks(5)
			Fx.confetti(0.5)
		elseif p.kind == "strobe" then
			Fx.strobe(2)
			Fx.floorFlash(WHITE)
		elseif p.kind == "hands" then
			Lasers.cue("hands", { beats = 8, color = CYAN, color2 = WHITE })
			Fx.ripple(WHITE, nil, 3)
			Led.note("hands" .. key, string.format(L.Show.djHands, n), 5, CYAN)
			-- documented ClubLights input: guests near the local player cheer
			Core.Bus.playerDanceAt = os.clock()
		end
	end
	beat(math.max(0, delay), go)
end

-------------------------------------------------------------------------------------------------
-- followers (trails / follow spots) on the club show's rigs
-------------------------------------------------------------------------------------------------
type Track = { name: string, obj: any, untilT: number }
local tracks: { [string]: Track } = {}

local function track(rigName: string, color: Color3, spot: boolean, trail: boolean, untilServer: number)
	if tracks[rigName] then
		tracks[rigName].untilT = math.max(tracks[rigName].untilT, untilServer)
		return
	end
	if not spot and not trail then
		return
	end
	tracks[rigName] = { name = rigName, obj = Fx.follower(rigName, color, spot, trail), untilT = untilServer }
end

local function stepTracks()
	local now = Core.now()
	for name, t in tracks do
		local root = Core.rigRoot(Core.showRig(name))
		if now > t.untilT or not t.obj.part then
			Fx.release(t.obj)
			tracks[name] = nil
		elseif root then
			t.obj.part.CFrame = CFrame.new(root.Position)
			if t.obj.pe then
				t.obj.pe.Enabled = true
			end
		elseif t.obj.pe then
			t.obj.pe.Enabled = false
		end
	end
end

local function rigPos(name: string): () -> Vector3?
	return function()
		local r = Core.rigRoot(Core.showRig(name))
		return if r then r.Position + Vector3.new(0, -2.6, 0) else nil
	end
end

-------------------------------------------------------------------------------------------------
-- the club's bottle parade
-------------------------------------------------------------------------------------------------
local lastShowKey = ""
local function onShow(rec: any)
	if type(rec) ~= "table" or type(rec.id) ~= "number" or rec.id <= 0 or type(rec.at) ~= "number" then
		return
	end
	local key = string.format("%d@%.2f", rec.id, rec.at)
	if key == lastShowKey then
		return
	end
	lastShowKey = key
	local now = Core.now()
	local endAt = tonumber(rec.endAt) or (rec.at + 40)
	if now > endAt then
		return
	end
	local SS = Core.ShowShared
	local item = SS and type(SS.item) == "function" and SS.item(rec.item) or nil
	local price = item and tonumber(item.price) or 0
	local tier = S.orderTier(price)
	local T = S.tier(tier)
	local icon = "✨"
	if item and type(SS.icon) == "function" then
		local ok, v = pcall(SS.icon, item, rec.aa)
		if ok and type(v) == "string" then
			icon = v
		end
	end
	local label = if type(rec.label) == "string" then rec.label else "음료 세트"
	safe(Signs.presenter, rec, tier, price, icon, label)
	if tier < 2 then
		return
	end
	local q = Core.q()
	local arriveAt = tonumber(rec.arriveAt) or (rec.at + 10)
	local n = math.clamp(tonumber(rec.staff) or 1, 1, 5)
	for i = 1, n do
		track("ClubShowStaff" .. i, T.color, i == 1 and tier >= 3 and q.spots > 0, q.trails, endAt)
	end
	if tier >= 3 then
		Lasers.follow(rigPos("ClubShowStaff1"), T.color, math.max(2, arriveAt - now))
	end
	local target = tableTarget(rec.table)
	task.delay(math.max(0, arriveAt - now), function()
		if not Core.inside then
			return
		end
		safe(Fx.ripple, T.color, target, 2)
		if tier >= 3 and target then
			safe(Fx.tableConfetti, target, if tier >= 4 then 1.5 else 1)
			safe(Fx.burst, target + Vector3.new(0, 4, 0), T.accent, 26)
		end
		if tier >= 4 then
			beat(0.1, function()
				Fx.co2(1)
			end)
		end
	end)
end

-------------------------------------------------------------------------------------------------
-- 합석 production
-------------------------------------------------------------------------------------------------
local bookingId = 0
local lastAct = ""
local function onBooking(b: any)
	if type(b) ~= "table" or type(b.id) ~= "number" or b.id <= 0 then
		return
	end
	local now = Core.now()
	local endAt = tonumber(b.endAt) or (now + 150)
	if now > endAt then
		return
	end
	local target = tableTarget(b.table)
	local tableId = tostring(b.table or "?")
	if b.id ~= bookingId then
		bookingId = b.id
		local q = Core.q()
		local seatedAt = tonumber(b.seatedAt) or ((tonumber(b.arriveAt) or (b.at + 12)) + 6)
		local walkEnd = seatedAt + 1
		if now < walkEnd then
			local spots = q.spots
			track("ClubShowMD", TEAL, spots > 0, q.trails, walkEnd)
			for k = 1, math.min(4, #(b.guests or {})) do
				track("ClubShowGuest" .. k, if k % 2 == 0 then MAGENTA else GOLD, spots > k, q.trails, walkEnd)
			end
			Lasers.follow(rigPos("ClubShowMD"), TEAL, math.max(2, walkEnd - now))
		end
		local arriveAt = tonumber(b.arriveAt) or (b.at + 12)
		if now < arriveAt + 2 then
			task.delay(math.max(0, arriveAt - now), function()
				if bookingId ~= b.id or not Core.inside then
					return
				end
				safe(Fx.tableConfetti, target, 1)
				if target then
					safe(Fx.burst, target + Vector3.new(0, 4, 0), TEAL, 24)
				end
				safe(Fx.ripple, TEAL, target, 2)
				safe(Led.note, "bk-arrive" .. b.id, string.format(L.Show.arrive, tableId), 5, TEAL, nil)
			end)
		end
	end
	-- table actions (짠 / 같이 춤): the existing 합석 card sends them, we stage them
	local act = b.act
	if type(act) == "table" and type(act.kind) == "string" and type(act.at) == "number" then
		local key = string.format("%d:%s@%.2f", b.id, act.kind, act.at)
		if key ~= lastAct then
			lastAct = key
			local delay = act.at - now
			if delay > -1.5 and Core.inside then
				task.delay(math.max(0, delay), function()
					if act.kind == "cheers" then
						safe(Fx.tableConfetti, target, 1.4)
						if target then
							safe(Fx.burst, target + Vector3.new(0, 3.5, 0), GOLD, 30)
						end
						safe(Fx.ripple, GOLD, target, 2)
						safe(Lasers.cue, "lock", { target = target, color = GOLD, color2 = TEAL, beats = 8 })
						safe(Led.note, "cheers" .. key, string.format(L.Show.cheers, tableId), 5, GOLD, nil)
					elseif act.kind == "dance" then
						safe(Fx.mirror, 10)
						safe(Fx.ripple, MAGENTA, nil, 3)
						safe(Lasers.cue, "show", { beats = 8, color = MAGENTA, color2 = TEAL })
						safe(Led.note, "dance" .. key, string.format(L.Show.dance, tableId), 6, MAGENTA, nil)
					end
				end)
			end
		end
	end
end

function Director.init(core: any, led: any, fx: any, lasers: any, signs: any)
	Core = core
	S = core.S
	L = core.L
	Led = led
	Fx = fx
	Lasers = lasers
	Signs = signs
	Led.onActivate(function(it: any, late: number)
		safe(onActivate, it, late)
	end)
	Core.onEvent("fx", onFx)
	Core.on("Show", function(rec: any)
		safe(onShow, rec)
	end)
	Core.on("Booking", function(b: any)
		safe(onBooking, b)
	end)
	Core.job("tracks", 30, function()
		if next(tracks) ~= nil then
			stepTracks()
		end
		return true
	end)
	-- the dedupe set stays small
	Core.job("fxgc", 0.05, function()
		if next(seenFx) ~= nil then
			table.clear(seenFx)
		end
		return true
	end)
end

return Director
