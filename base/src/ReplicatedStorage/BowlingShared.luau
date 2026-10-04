--!strict
-- BowlingShared: constants, the house-ball catalog, callouts, split detection and pure 10-pin
-- scoring used by Bowling.server and BowlingClient (+ BowlingFX/*). No instances are created here.

local Shared = {}

Shared.FolderName = "Bowling" -- ReplicatedStorage.Bowling (created at runtime by the server)
Shared.RequestName = "Request" -- RemoteEvent client -> server: (action: string, payload: table?)
Shared.UpdateName = "Update" -- RemoteEvent server -> client: (message: table)
Shared.EventName = "GwangalliBowlingEvent" -- BindableEvent under ServerStorage (server-only hooks)

-- Throw input ranges (the server clamps everything it receives to these).
Shared.Limits = {
	MaxOffset = 1.3, -- lateral release point, studs from the lane centre (lane bed half-width 1.75)
	MaxAngle = 7, -- degrees left/right of straight down the lane
	MaxSpin = 1, -- hook: -1 (hooks left) .. 1 (hooks right)
	MinSpeed = 16, -- studs/s at power 0
	MaxSpeed = 34, -- studs/s at power 1 (real 7-10 m/s at 0.3 m/stud)
}

-- Back-end hook model (server applies it, the client aim guide predicts it): past HookStart
-- studs (end of the oil pattern) the ball gains lateral speed spin * HookAccel * ball.hook
-- studs/s^2, ramping in over HookRamp studs.
Shared.HookStart = 36
Shared.HookAccel = 3.5
Shared.HookRamp = 10

Shared.OffsetStep = 0.05
Shared.AngleStep = 0.25
Shared.SpinStep = 0.05

Shared.IdleTimeout = 120 -- seconds without activity before the lane is released
Shared.PromptText = "볼링 치기"
Shared.MaxPlayers = 4
Shared.GameFee = 4500 -- won per player per game (charged only when the life-game API exists)
Shared.PriceText = "1게임 4,500원"

-- Lane geometry (bowling_config): 39 boards across the 41.5 in lane bed; arrows 15 ft past the foul
-- line; stance / slide positions measured back from the foul line.
Shared.Boards = 39
Shared.ArrowDist = 15.24
Shared.StanceBack = 11.5 -- where the bowler sets up (4-step approach)
Shared.SlideBack = 1.5 -- where the slide ends (the foul barrier stops players at +0.2)
Shared.HandOffset = 0.85 -- right hand -> body centre (the ball is released at body x + 0.85)

--------------------------------------------------------------------------------------------------
-- House balls: 8-16 lb, one colour each. hook = back-end hook multiplier, speed = release speed
-- multiplier (lighter balls leave the hand faster, heavier balls carry the pins better), mass =
-- physical density multiplier relative to a 14 lb ball.
--------------------------------------------------------------------------------------------------
export type Ball = {
	lb: number,
	name: string,
	tag: string,
	rgb: { number },
	rgb2: { number }, -- swirl / highlight colour (UI swatch gradient)
	hook: number,
	speed: number,
	mass: number,
}
Shared.Balls = {
	{ lb = 8, name = "베이비 핑크", tag = "키즈 · 아주 가벼움", rgb = { 255, 120, 190 }, rgb2 = { 255, 210, 235 }, hook = 0.55, speed = 1.07, mass = 8 / 14 },
	{ lb = 9, name = "민트 스파클", tag = "가벼움 · 직구용", rgb = { 70, 225, 195 }, rgb2 = { 200, 255, 240 }, hook = 0.62, speed = 1.06, mass = 9 / 14 },
	{ lb = 10, name = "선셋 오렌지", tag = "가벼움", rgb = { 255, 140, 40 }, rgb2 = { 255, 220, 120 }, hook = 0.7, speed = 1.05, mass = 10 / 14 },
	{ lb = 11, name = "라임 펄", tag = "입문 추천", rgb = { 160, 225, 50 }, rgb2 = { 235, 255, 170 }, hook = 0.78, speed = 1.03, mass = 11 / 14 },
	{ lb = 12, name = "오션 블루", tag = "하우스볼 표준", rgb = { 45, 120, 255 }, rgb2 = { 140, 220, 255 }, hook = 0.86, speed = 1.02, mass = 12 / 14 },
	{ lb = 13, name = "코스믹 퍼플", tag = "중급 · 훅 잘 먹음", rgb = { 145, 70, 255 }, rgb2 = { 255, 120, 220 }, hook = 0.96, speed = 1.0, mass = 13 / 14 },
	{ lb = 14, name = "체리 레드", tag = "중급 · 핀 액션", rgb = { 225, 35, 60 }, rgb2 = { 255, 150, 120 }, hook = 1.06, speed = 0.99, mass = 1 },
	{ lb = 15, name = "블랙 펄", tag = "상급 · 강한 훅", rgb = { 28, 28, 38 }, rgb2 = { 120, 130, 170 }, hook = 1.16, speed = 0.98, mass = 15 / 14 },
	{ lb = 16, name = "골드 프로", tag = "프로 · 최고 파괴력", rgb = { 255, 190, 50 }, rgb2 = { 255, 245, 190 }, hook = 1.26, speed = 0.97, mass = 16 / 14 },
} :: { Ball }
Shared.DefaultLb = 12

function Shared.ball(lb: any): Ball
	local n = tonumber(lb) or Shared.DefaultLb
	local best = Shared.Balls[5]
	for _, b in Shared.Balls do
		if math.abs(b.lb - n) < math.abs(best.lb - n) then
			best = b
		end
	end
	return best
end

function Shared.validLb(lb: any): boolean
	if type(lb) ~= "number" then
		return false
	end
	for _, b in Shared.Balls do
		if b.lb == lb then
			return true
		end
	end
	return false
end

function Shared.ballColor(lb: any): Color3
	local b = Shared.ball(lb)
	return Color3.fromRGB(b.rgb[1], b.rgb[2], b.rgb[3])
end

function Shared.ballColor2(lb: any): Color3
	local b = Shared.ball(lb)
	return Color3.fromRGB(b.rgb2[1], b.rgb2[2], b.rgb2[3])
end

-- Speed for a normalised power value (0..1) and a ball.
function Shared.speedFor(power: number, lb: number?): number
	local p = math.clamp(power, 0, 1)
	local base = Shared.Limits.MinSpeed + (Shared.Limits.MaxSpeed - Shared.Limits.MinSpeed) * p
	if lb then
		base *= Shared.ball(lb).speed
	end
	return base
end

--------------------------------------------------------------------------------------------------
-- Release timing: the swing meter value at release is the power. The gold band is the clean
-- release; outside it the server adds a small random aim error (the client shows the grade).
--------------------------------------------------------------------------------------------------
Shared.Timing = {
	SweetLo = 0.68,
	SweetHi = 0.86,
	Rise = 1.0, -- seconds for the meter to fill (backswing)
	Period = 1.7, -- full oscillation once past the top while still held
}

-- Meter value t seconds after the swing started: rises 0 -> 1 over Rise, then sweeps 1 -> 0.35 ->
-- 1 while the button is still held (so holding too long costs power, not the throw).
function Shared.meter(t: number): number
	local T = Shared.Timing
	if t <= T.Rise then
		local u = math.clamp(t / T.Rise, 0, 1)
		return 1 - (1 - u) * (1 - u) -- ease-out rise: fast at first, slower near the top
	end
	local u = ((t - T.Rise) % T.Period) / T.Period
	return 0.35 + 0.65 * (0.5 + 0.5 * math.cos(u * math.pi * 2))
end

function Shared.grade(power: number): string
	local T = Shared.Timing
	if power >= T.SweetLo and power <= T.SweetHi then
		return "PERFECT"
	elseif power > T.SweetHi then
		return if power > 0.95 then "POWER" else "GOOD"
	elseif power >= T.SweetLo - 0.14 then
		return "GOOD"
	end
	return "SOFT"
end

-- Max random aim error (degrees) for a release grade.
function Shared.gradeError(grade: string): number
	if grade == "PERFECT" then
		return 0.15
	elseif grade == "GOOD" then
		return 0.7
	elseif grade == "POWER" then
		return 1.4
	end
	return 1.0
end

Shared.GradeText = {
	PERFECT = "PERFECT!",
	GOOD = "GOOD",
	POWER = "파워!",
	SOFT = "살살~",
}

--------------------------------------------------------------------------------------------------
-- Boards and arrows (display only)
--------------------------------------------------------------------------------------------------
-- Board number (1 = rightmost board for a right-handed bowler) of a lateral lane position.
function Shared.boardAt(x: number, laneWidth: number?): number
	local w = laneWidth or 3.5
	local bw = w / Shared.Boards
	return math.clamp(math.floor((w / 2 - x) / bw) + 1, 1, Shared.Boards)
end

-- Where the line crosses the arrows (x) for a release offset and angle (deg).
function Shared.arrowX(offset: number, angle: number): number
	return offset + math.tan(math.rad(angle)) * Shared.ArrowDist
end

-- Arrow index (1 = rightmost arrow, 7 arrows at boards 5,10,15,20,25,30,35).
function Shared.arrowIndex(board: number): number
	return math.clamp(math.floor(board / 5 + 0.5), 1, 7)
end

--------------------------------------------------------------------------------------------------
-- Path prediction (the aim guide; the server applies the same hook rule to the physics ball)
--------------------------------------------------------------------------------------------------
-- Returns points {x, d} from the release (d = 0.9) to the pin deck, and the d where it leaves the
-- lane (gutter) or nil. `bumpers`: the path bounces off the lane edges instead.
function Shared.predict(offset: number, angle: number, spin: number, lb: number?, power: number?, laneLength: number?, laneWidth: number?, bumpers: boolean?, steps: number?): ({ { number } }, number?)
	local L = laneLength or 60.96
	local half = (laneWidth or 3.5) / 2 - 0.36
	local ball = Shared.ball(lb)
	local v = Shared.speedFor(power or 0.75, lb)
	local a = math.rad(angle)
	local x, d = offset, 0.9
	local vx, vz = math.sin(a) * v, math.cos(a) * v
	local n = steps or 26
	local pts = { { x, d } }
	local gutterAt: number? = nil
	local dt = (L + 1.2 - d) / vz / (n * 3)
	local accel = spin * Shared.HookAccel * ball.hook
	local i = 0
	while d < L + 1.2 and i < n * 3 + 10 do
		i += 1
		if d > Shared.HookStart then
			local ramp = math.clamp((d - Shared.HookStart) / Shared.HookRamp, 0, 1)
			vx += accel * ramp * dt
		end
		x += vx * dt
		d += vz * dt
		if math.abs(x) > half then
			if bumpers then
				x = math.sign(x) * half
				vx = -vx * 0.55
			elseif not gutterAt then
				gutterAt = d
				x = math.sign(x) * (half + 0.55)
				vx = 0
			end
		end
		if i % 3 == 0 then
			table.insert(pts, { x, d })
		end
	end
	table.insert(pts, { x, math.max(d, L + 1.2) })
	return pts, gutterAt
end

-- Entry point at the head pin (x at d = laneLength) from predicted points.
function Shared.entryX(pts: { { number } }, laneLength: number?): number
	local L = laneLength or 60.96
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		if b[2] >= L then
			local u = (L - a[2]) / math.max(b[2] - a[2], 1e-6)
			return a[1] + (b[1] - a[1]) * u
		end
	end
	return pts[#pts][1]
end

-- Pocket: between the 1 and 3 pins (right-handed) or the 1 and 2 pins (left hook).
function Shared.pocket(entry: number, spin: number): string?
	if entry > 0.1 and entry < 0.42 then
		return "1-3 포켓"
	elseif entry < -0.1 and entry > -0.42 then
		return "1-2 포켓"
	elseif math.abs(entry) <= 0.1 then
		return "정면 (헤드핀)"
	end
	local _ = spin
	return nil
end

--------------------------------------------------------------------------------------------------
-- Pins: positions (x right of the lane centre, d past the head pin) and split detection
--------------------------------------------------------------------------------------------------
local PIN_ROWS = { { 1 }, { 2, 3 }, { 4, 5, 6 }, { 7, 8, 9, 10 } }
Shared.PinRow = {} :: { number }
Shared.PinX = {} :: { number }
for r, row in PIN_ROWS do
	for k, id in row do
		Shared.PinRow[id] = r
		Shared.PinX[id] = (k - 1 - (r - 1) / 2) * 1.016
	end
end

-- USBC: a split is a leave after the first ball of a rack with the head pin down and at least one
-- pin down between two standing pins (in the same row or immediately ahead of them), e.g. 7-10,
-- 4-6, 5-7, 3-10, 5-6. Sleepers (2-8, 3-9) and touching pins (4-7) are not splits.
function Shared.isSplit(standing: { boolean }): boolean
	if standing[1] then
		return false
	end
	local up = {}
	for n = 1, 10 do
		if standing[n] then
			table.insert(up, n)
		end
	end
	if #up < 2 then
		return false
	end
	for i = 1, #up do
		for j = i + 1, #up do
			local a, b = up[i], up[j]
			local x0, x1 = math.min(Shared.PinX[a], Shared.PinX[b]), math.max(Shared.PinX[a], Shared.PinX[b])
			local r0, r1 = math.min(Shared.PinRow[a], Shared.PinRow[b]), math.max(Shared.PinRow[a], Shared.PinRow[b])
			for c = 1, 10 do
				if not standing[c] then
					local cx, cr = Shared.PinX[c], Shared.PinRow[c]
					if cx > x0 + 0.05 and cx < x1 - 0.05 and cr >= r0 - 1 and cr <= r1 then
						return true
					end
				end
			end
		end
	end
	return false
end

-- "7-10", "3-6-10" ... ("" when nothing stands)
function Shared.leaveName(standing: { boolean }): string
	local parts = {}
	for n = 1, 10 do
		if standing[n] then
			table.insert(parts, tostring(n))
		end
	end
	return table.concat(parts, "-")
end

local SPLIT_NAMES = {
	["7-10"] = "7-10 스플릿 (최악의 스플릿!)",
	["4-6-7-10"] = "빅 포 (Big Four)",
	["4-6"] = "4-6 스플릿",
	["2-7"] = "베이비 스플릿",
	["3-10"] = "베이비 스플릿",
	["5-7"] = "다임 스토어",
	["5-10"] = "다임 스토어",
	["4-7-10"] = "그릭 처치",
	["6-7-10"] = "그릭 처치",
	["4-6-10"] = "그릭 처치",
	["4-6-7"] = "그릭 처치",
}
function Shared.splitName(leave: string): string
	return SPLIT_NAMES[leave] or (leave .. " 스플릿")
end

--------------------------------------------------------------------------------------------------
-- Scoring
--------------------------------------------------------------------------------------------------
export type Progress = {
	frame: number, -- 1..10 (frame of the NEXT roll, or 10 when over)
	roll: number, -- roll number inside that frame (1..3)
	fullRack: boolean, -- the next roll is at a fresh rack of 10 pins
	over: boolean, -- game finished
}

-- Where the game stands after `rolls` (pins knocked down per roll, in order).
function Shared.progress(rolls: { number }): Progress
	local i, f = 1, 1
	while f <= 9 do
		local r1 = rolls[i]
		if r1 == nil then
			return { frame = f, roll = 1, fullRack = true, over = false }
		end
		if r1 >= 10 then
			i += 1
		else
			if rolls[i + 1] == nil then
				return { frame = f, roll = 2, fullRack = false, over = false }
			end
			i += 2
		end
		f += 1
	end
	local r1, r2, r3 = rolls[i], rolls[i + 1], rolls[i + 2]
	if r1 == nil then
		return { frame = 10, roll = 1, fullRack = true, over = false }
	end
	if r2 == nil then
		return { frame = 10, roll = 2, fullRack = r1 >= 10, over = false }
	end
	if r3 == nil then
		if r1 >= 10 then
			return { frame = 10, roll = 3, fullRack = r2 >= 10, over = false }
		elseif r1 + r2 >= 10 then
			return { frame = 10, roll = 3, fullRack = true, over = false }
		end
	end
	return { frame = 10, roll = 3, fullRack = true, over = true }
end

-- Pins standing before the next roll (10 on a fresh rack).
function Shared.pinsLeft(rolls: { number }): number
	local p = Shared.progress(rolls)
	if p.over or p.fullRack then
		return 10
	end
	return 10 - (rolls[#rolls] or 0)
end

-- Index (1-based) of the first roll of each frame (frames that have started), for the sheet.
function Shared.frameStarts(rolls: { number }): { number }
	local out = {}
	local i, f = 1, 1
	while f <= 10 and rolls[i] ~= nil do
		out[f] = i
		if f < 10 then
			if rolls[i] >= 10 then
				i += 1
			else
				i += 2
			end
		else
			break
		end
		f += 1
	end
	return out
end

local function digit(n: number?): string
	if n == nil then
		return ""
	elseif n == 0 then
		return "-"
	end
	return tostring(n)
end

export type FrameInfo = {
	marks: { string }, -- display symbols per box ("X", "/", "-", "7", "")
	score: number?, -- cumulative total (nil while bonus rolls are pending)
	splits: { boolean }?, -- per box: the leave after this ball was a split (circled on the sheet)
}
export type Board = {
	frames: { FrameInfo },
	total: number, -- running total of all frames that can be scored so far
	current: number, -- frame of the next roll
	over: boolean,
}

-- Full scoreboard: marks per frame and cumulative totals (standard 10-pin rules, including
-- strike/spare bonuses and the 10th-frame bonus balls). `splitRolls[i] = true` marks roll i as
-- having left a split (shown circled).
function Shared.board(rolls: { number }, splitRolls: { [any]: boolean }?): Board
	local frames: { FrameInfo } = {}
	local i = 1
	local running = 0
	local scoring = true -- stays true while every previous frame could be scored
	local sp = splitRolls or {}
	local function isSp(idx: number): boolean
		return sp[idx] == true or sp[tostring(idx)] == true
	end
	for f = 1, 10 do
		local fi: FrameInfo = { marks = { "", "" }, score = nil, splits = { false, false, false } }
		local frameScore: number? = nil
		if f < 10 then
			local r1 = rolls[i]
			if r1 ~= nil then
				if r1 >= 10 then
					fi.marks = { "", "X" }
					local b1, b2 = rolls[i + 1], rolls[i + 2]
					if b1 ~= nil and b2 ~= nil then
						frameScore = 10 + b1 + b2
					end
					i += 1
				else
					local r2 = rolls[i + 1]
					;(fi.splits :: any)[1] = isSp(i)
					if r2 ~= nil and r1 + r2 >= 10 then
						fi.marks = { digit(r1), "/" }
						local b = rolls[i + 2]
						if b ~= nil then
							frameScore = 10 + b
						end
					else
						fi.marks = { digit(r1), digit(r2) }
						if r2 ~= nil then
							frameScore = r1 + r2
						end
					end
					i += 2
				end
			end
		else
			local r1, r2, r3 = rolls[i], rolls[i + 1], rolls[i + 2]
			local m1, m2, m3 = "", "", ""
			if r1 ~= nil then
				m1 = r1 >= 10 and "X" or digit(r1)
				;(fi.splits :: any)[1] = r1 < 10 and isSp(i)
			end
			if r1 ~= nil and r2 ~= nil then
				if r1 >= 10 then
					m2 = r2 >= 10 and "X" or digit(r2)
					;(fi.splits :: any)[2] = r2 < 10 and isSp(i + 1)
				else
					m2 = (r1 + r2 >= 10) and "/" or digit(r2)
				end
			end
			if r1 ~= nil and r2 ~= nil and r3 ~= nil then
				if r1 >= 10 and r2 >= 10 then
					m3 = r3 >= 10 and "X" or digit(r3)
				elseif r1 >= 10 then
					m3 = (r2 + r3 >= 10) and "/" or digit(r3)
				else
					m3 = r3 >= 10 and "X" or digit(r3)
				end
			end
			fi.marks = { m1, m2, m3 }
			if r1 ~= nil and r2 ~= nil then
				if r1 >= 10 or r1 + r2 >= 10 then
					if r3 ~= nil then
						frameScore = r1 + r2 + r3
					end
				else
					frameScore = r1 + r2
				end
			end
		end
		if scoring and frameScore ~= nil then
			running += frameScore
			fi.score = running
		else
			scoring = false
		end
		frames[f] = fi
	end
	local p = Shared.progress(rolls)
	return { frames = frames, total = running, current = p.frame, over = p.over }
end

-- Maximum possible final score from here (every remaining ball a strike).
function Shared.maxPossible(rolls: { number }): number
	local r = table.clone(rolls)
	local guard = 0
	while not Shared.progress(r).over and guard < 30 do
		guard += 1
		table.insert(r, Shared.pinsLeft(r))
	end
	return Shared.board(r).total
end

-- Mark for the roll that just happened: "STRIKE", "SPARE", "GUTTER" or "".
-- `rackRoll` = 1 when the roll was thrown at a fresh rack, 2 otherwise.
function Shared.markFor(knocked: number, standingBefore: number, rackRoll: number, gutter: boolean): string
	if knocked >= standingBefore and standingBefore > 0 then
		return rackRoll == 1 and "STRIKE" or "SPARE"
	end
	if knocked == 0 and gutter then
		return "GUTTER"
	end
	return ""
end

--------------------------------------------------------------------------------------------------
-- Callouts (lane monitor + screen). kind = STRIKE | SPARE | SPLIT | SPLITMADE | GUTTER | MISS |
-- NINE | PINS | PERFECT
--------------------------------------------------------------------------------------------------
local STREAK = {
	[1] = { "STRIKE!", "스트라이크" },
	[2] = { "더블!", "DOUBLE" },
	[3] = { "터키!", "TURKEY · 3연속 스트라이크" },
	[4] = { "포배거!", "4-BAGGER · 4연속" },
	[5] = { "파이브배거!", "5-BAGGER · 5연속" },
	[6] = { "식스팩!", "SIX-PACK · 6연속" },
	[12] = { "퍼펙트!", "PERFECT GAME 300" },
}
function Shared.streakText(n: number): (string, string)
	local s = STREAK[n]
	if s then
		return s[1], s[2]
	end
	return string.format("%d연속!", n), string.format("%d-BAGGER", n)
end

export type Callout = { kind: string, text: string, sub: string, color: { number }, big: boolean, cheer: string? }

-- cheer: what the bowler / friends do: "cheer" (arms up), "pump" (fist pump), "clap", "sad"
function Shared.callout(kind: string, info: { [string]: any }?): Callout
	local i = info or {}
	if kind == "STRIKE" or kind == "PERFECT" then
		local n = tonumber(i.streak) or 1
		local t, s = Shared.streakText(n)
		if kind == "PERFECT" then
			t, s = "퍼펙트 게임!", "300점 · PERFECT"
		end
		local col = if n >= 3 then { 255, 196, 60 } elseif n == 2 then { 120, 220, 255 } else { 255, 80, 190 }
		return { kind = kind, text = t, sub = s, color = col, big = true, cheer = if n >= 2 then "cheer" else "pump" }
	elseif kind == "SPLITMADE" then
		return { kind = kind, text = "스플릿 처리!", sub = "SPLIT CONVERTED · " .. tostring(i.leave or ""), color = { 255, 196, 60 }, big = true, cheer = "cheer" }
	elseif kind == "SPARE" then
		return { kind = kind, text = "스페어!", sub = "SPARE", color = { 80, 200, 255 }, big = true, cheer = "clap" }
	elseif kind == "SPLIT" then
		local leave = tostring(i.leave or "")
		return { kind = kind, text = "스플릿!", sub = Shared.splitName(leave), color = { 255, 96, 96 }, big = true, cheer = "sad" }
	elseif kind == "GUTTER" then
		return { kind = kind, text = "거터…", sub = "GUTTER BALL", color = { 190, 190, 205 }, big = false, cheer = "sad" }
	elseif kind == "NINE" then
		return { kind = kind, text = "9핀! 아깝다", sub = "남은 핀 " .. tostring(i.leave or ""), color = { 255, 210, 120 }, big = false, cheer = nil }
	elseif kind == "MISS" then
		return { kind = kind, text = "미스", sub = "OPEN FRAME", color = { 190, 190, 205 }, big = false, cheer = nil }
	end
	local k = tonumber(i.knocked) or 0
	return { kind = "PINS", text = if k == 1 then "1 PIN" else tostring(k) .. " PINS", sub = if i.leave and i.leave ~= "" then ("남은 핀 " .. tostring(i.leave)) else "", color = { 245, 247, 251 }, big = false, cheer = nil }
end

--------------------------------------------------------------------------------------------------
-- Game summary + milestones (one-time rewards, persisted by the server)
--------------------------------------------------------------------------------------------------
export type Summary = {
	total: number,
	strikes: number,
	spares: number,
	opens: number,
	splits: number,
	splitsMade: number,
	gutters: number,
	bestFrame: number,
	bestFrameScore: number,
	maxStreak: number,
	clean: boolean,
	perfect: boolean,
	frameScores: { number },
}

function Shared.summary(rolls: { number }, splitRolls: { [any]: boolean }?, gutters: number?): Summary
	local b = Shared.board(rolls, splitRolls)
	local frameScores = {}
	local prev = 0
	local bestF, bestS = 1, -1
	for f = 1, 10 do
		local s = b.frames[f].score
		local fs = if s then s - prev else 0
		if s then
			prev = s
		end
		frameScores[f] = fs
		if fs > bestS then
			bestF, bestS = f, fs
		end
	end
	local strikes, spares, opens, splits, splitsMade = 0, 0, 0, 0, 0
	local streak, maxStreak = 0, 0
	local sp = splitRolls or {}
	local i, f = 1, 1
	while f <= 10 and rolls[i] ~= nil do
		local r1, r2 = rolls[i], rolls[i + 1]
		if f < 10 then
			if r1 >= 10 then
				strikes += 1
				streak += 1
				maxStreak = math.max(maxStreak, streak)
				i += 1
			else
				streak = 0
				local wasSplit = sp[i] == true or sp[tostring(i)] == true
				if wasSplit then
					splits += 1
				end
				if r2 ~= nil and r1 + r2 >= 10 then
					spares += 1
					if wasSplit then
						splitsMade += 1
					end
				elseif r2 ~= nil then
					opens += 1
				end
				i += 2
			end
		else
			-- 10th frame: every ball at a fresh rack can be a strike; the ball after a non-strike
			-- makes it a spare or an open frame (a bonus ball after a spare starts a fresh rack)
			local balls = { r1, r2, rolls[i + 2] }
			local fresh = true
			for k = 1, 3 do
				local r = balls[k]
				if r == nil then
					break
				end
				if fresh then
					if r >= 10 then
						strikes += 1
						streak += 1
						maxStreak = math.max(maxStreak, streak)
					else
						streak = 0
						fresh = false
						local wasSplit = sp[i + k - 1] == true or sp[tostring(i + k - 1)] == true
						if wasSplit then
							splits += 1
						end
						local nxt = if k < 3 then balls[k + 1] else nil
						if nxt ~= nil then
							if nxt >= 10 - r then
								spares += 1
								if wasSplit then
									splitsMade += 1
								end
							else
								opens += 1
							end
						end
					end
				else
					fresh = true
				end
			end
			break
		end
		f += 1
	end
	return {
		total = b.total,
		strikes = strikes,
		spares = spares,
		opens = opens,
		splits = splits,
		splitsMade = splitsMade,
		gutters = gutters or 0,
		bestFrame = bestF,
		bestFrameScore = math.max(bestS, 0),
		maxStreak = maxStreak,
		clean = b.over and opens == 0,
		perfect = b.over and b.total >= 300,
		frameScores = frameScores,
	}
end

export type Milestone = { id: string, title: string, cash: number, stats: { [string]: number }, live: boolean? }
-- live = checked after every roll (strike / turkey / split conversion); the rest at the game end.
Shared.Milestones = {
	{ id = "first_strike", title = "첫 스트라이크", cash = 2000, stats = { popularity = 0.5 }, live = true },
	{ id = "first_split_made", title = "첫 스플릿 처리", cash = 5000, stats = { popularity = 1 }, live = true },
	{ id = "first_turkey", title = "첫 터키 (3연속 스트라이크)", cash = 10000, stats = { popularity = 1 }, live = true },
	{ id = "first_game", title = "첫 게임 완주", cash = 1000, stats = { happiness = 2 } },
	{ id = "score_150", title = "첫 150점 돌파", cash = 5000, stats = { popularity = 1 } },
	{ id = "score_200", title = "첫 200점 게임", cash = 30000, stats = { popularity = 3 } },
	{ id = "clean_game", title = "첫 클린 게임 (오픈 프레임 0)", cash = 10000, stats = { popularity = 2 } },
	{ id = "perfect", title = "퍼펙트 게임 300", cash = 300000, stats = { popularity = 10 } },
} :: { Milestone }

-- Milestones reached by this game state (ids), live ones only when `final` is false.
function Shared.milestonesReached(s: Summary, final: boolean): { string }
	local out = {}
	if s.strikes >= 1 then
		table.insert(out, "first_strike")
	end
	if s.splitsMade >= 1 then
		table.insert(out, "first_split_made")
	end
	if s.maxStreak >= 3 then
		table.insert(out, "first_turkey")
	end
	if final then
		table.insert(out, "first_game")
		if s.total >= 150 then
			table.insert(out, "score_150")
		end
		if s.total >= 200 then
			table.insert(out, "score_200")
		end
		if s.clean then
			table.insert(out, "clean_game")
		end
		if s.perfect then
			table.insert(out, "perfect")
		end
	end
	return out
end

function Shared.milestone(id: string): Milestone?
	for _, m in Shared.Milestones do
		if m.id == id then
			return m
		end
	end
	return nil
end

-- Per-game repeatable popularity for good games (server caps it per day).
Shared.GoodGame = { score = 180, stats = { popularity = 0.5 }, dailyCap = 2 }

--------------------------------------------------------------------------------------------------
-- Sounds (built-in rbxasset files only: the character-sound set + UI sounds)
--------------------------------------------------------------------------------------------------
Shared.Sfx = {
	roll = { id = "rbxasset://sounds/action_falling.mp3", volume = 0.55, speed = 0.3 },
	thud = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 1.0, speed = 0.62 },
	clack = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.7, speed = 1.9 },
	tick = { id = "rbxasset://sounds/clickfast.wav", volume = 0.55, speed = 0.5 },
	chime = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.45, speed = 1.0 },
	swoosh = { id = "rbxasset://sounds/swoosh.wav", volume = 0.35, speed = 0.8 },
	step = { id = "rbxasset://sounds/action_footsteps_plastic.mp3", volume = 0.35, speed = 1.3 },
	ret = { id = "rbxasset://sounds/action_falling.mp3", volume = 0.25, speed = 0.18 },
}

return Shared
