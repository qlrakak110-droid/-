-- Gwangan Bridge (광안대교) LED shows on BridgeLED parts (attribute Segment 0..1 along the bridge).
-- At night the parts turn Neon and play patterns that rotate every PatternSeconds with a crossfade:
--   1 cyan-violet "aurora" gradient drifting along Segment, 2 rainbow wave, 3 sparkle on deep
--   blue, 4 light pulses chasing out from the centre span, 5 slow colour breathing.
-- Everything is a function of workspace:GetServerTimeNow(), so all players see the same frame.
--
-- Modes (decided by a 0.5 s gate; per quality tier through Util.tierConfig(Config.Bridge)):
--   day      original material / colour restored once (chunked), then idle
--   static   night, camera beyond MaxDistance (4500 on phones): every LED holds StaticColor
--            (written once, chunked), then idle; the bridge still reads as lit from afar
--   animate  night and in range. Updates pause (colours freeze) while every sample point along
--            the bridge is well off the view direction (dot < ViewDot) and none is near.
--     * mid / high: each LED is refreshed about UpdateHz times per second by walking the list in
--       chunks (MaxPerFrame); colours are written only when they changed by ColorTolerance
--     * low (Grouped): LEDs are bucketed into Groups along Segment; a TickHz (10 Hz) tick computes
--       one colour per group and rewrites a whole group only when its colour changed, at most
--       MaxWritesPerTick part writes per tick; no per-frame work between ticks
-- All ~1,420 LEDs are Persistent, so the list is complete on every client from the start.

local Bridge = {}

type Rec = {
	part: BasePart,
	seg: number,
	seed: number,
	material: Enum.Material,
	color: Color3,
	active: boolean,
	last: Color3?,
}
type GroupRec = { seg: number, seed: number }

function Bridge.start(ctx: any)
	local Config, Shared, Util, DayNight = ctx.Config, ctx.Shared, ctx.Util, ctx.DayNight
	local base = Config.Bridge
	local NEON = Enum.Material.Neon
	local STATIC: Color3 = base.StaticColor or Color3.fromRGB(60, 110, 230)

	local list: { Rec } = {}
	local indexOf: { [BasePart]: number } = {}
	local sum = Vector3.zero
	local cursor = 0
	local groupsDirty = true
	-- a few LED positions spread along Segment, for the view test (index 1..9 by Segment)
	local samples: { [number]: Vector3 } = {}

	local function segmentOf(part: BasePart): number
		local s = part:GetAttribute("Segment")
		if type(s) == "number" and s == s then
			return math.clamp(s, 0, 1)
		end
		return 0.5
	end

	Util.watchTag("BridgeLED", function(inst)
		if not inst:IsA("BasePart") or indexOf[inst] then
			return
		end
		local p = inst.Position
		local rec: Rec = {
			part = inst,
			seg = segmentOf(inst),
			seed = Shared.hash01(p.X, p.Y, p.Z) * 100000,
			material = inst.Material,
			color = inst.Color,
			active = false,
			last = nil,
		}
		table.insert(list, rec)
		indexOf[inst] = #list
		sum += p
		local si = math.floor(rec.seg * 8 + 0.5) + 1
		if not samples[si] then
			samples[si] = p
		end
		groupsDirty = true
	end, function(inst)
		local i = indexOf[inst :: BasePart]
		if not i then
			return
		end
		local rec = list[i]
		if rec.active and inst:IsDescendantOf(workspace) then
			rec.part.Material = rec.material -- tag removed, instance kept: restore
			rec.part.Color = rec.color
		end
		sum -= rec.part.Position
		local lastIndex = #list
		if i ~= lastIndex then
			local moved = list[lastIndex]
			list[i] = moved
			indexOf[moved.part] = i
		end
		list[lastIndex] = nil
		indexOf[inst :: BasePart] = nil
		groupsDirty = true
	end)

	-- Patterns ----------------------------------------------------------------------------------------
	local fromHSV = Color3.fromHSV
	local DEEP = Color3.fromRGB(18, 40, 130)
	local BLUE = Color3.fromRGB(50, 110, 255)
	local WHITE = Color3.fromRGB(255, 255, 255)
	local uniformT, uniformC = -1, WHITE

	-- Colours follow the real bridge's night shows: saturated cyan-violet gradients, rainbow waves,
	-- white sparkles on deep blue and chases from the centre span. No pattern lets the bridge go
	-- dark (it must read as lit from the beach at every moment).
	local patterns: { (any, number) -> Color3 } = {
		-- 1 aurora: a cyan -> blue -> violet gradient drifting slowly along the deck
		function(rec, t)
			local w = 0.5 + 0.5 * math.sin(rec.seg * 7.5 - t * 0.35)
			return fromHSV(0.5 + 0.3 * w, 0.8, 0.85 + 0.15 * w)
		end,
		-- 2 rainbow wave along the deck
		function(rec, t)
			return fromHSV((rec.seg * 1.6 - t * 0.07) % 1, 0.9, 1)
		end,
		-- 3 sparkle on deep blue
		function(rec, t)
			local frame = math.floor(t * 8)
			if Shared.hash01(rec.seed, frame) < 0.045 then
				return WHITE
			end
			local shimmer = 0.75 + 0.25 * math.sin(t * 2 + rec.seg * 20)
			return DEEP:Lerp(BLUE, shimmer - 0.5)
		end,
		-- 4 pulses chasing outward from the centre span
		function(rec, t)
			local d = math.abs(rec.seg - 0.5) * 2
			local band = (d * 5 - t * 0.9) % 1
			local v = if band < 0.22 then 1 else 0.2
			return fromHSV((0.55 + math.floor(t / 9) * 0.13) % 1, 0.7, v)
		end,
		-- 5 slow colour breathing (whole bridge): computed once per update time
		function(_rec, t)
			if t ~= uniformT then
				uniformT = t
				local v = 0.45 + 0.55 * (0.5 + 0.5 * math.sin(t * 1.1))
				uniformC = fromHSV((t * 0.015) % 1, 0.75, v)
			end
			return uniformC
		end,
	}
	local period = math.max(5, base.PatternSeconds)
	local fade = math.clamp(base.CrossfadeSeconds, 0, period * 0.5)

	local function colorAt(rec: any, t: number): Color3
		local count = #patterns
		local k = math.floor(t / period)
		local within = t - k * period
		local a = patterns[k % count + 1](rec, t)
		if fade > 0 and within > period - fade then
			local b = patterns[(k + 1) % count + 1](rec, t)
			return a:Lerp(b, (within - (period - fade)) / fade)
		end
		return a
	end

	local function sameColor(a: Color3?, b: Color3, tol: number): boolean
		if not a then
			return false
		end
		return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) < tol
	end

	local function paint(rec: Rec, c: Color3)
		if not rec.active then
			rec.active = true
			rec.part.Material = NEON
		end
		rec.last = c
		rec.part.Color = c
	end

	-- Groups (low tier) -------------------------------------------------------------------------------
	local groupCount = 0
	local members: { { Rec } } = {}
	local groupRecs: { GroupRec } = {}
	local groupLast: { Color3 | false } = {}
	local groupCursor = 0

	local function rebuildGroups(g: number)
		groupCount = g
		table.clear(members)
		table.clear(groupRecs)
		table.clear(groupLast)
		for i = 1, g do
			members[i] = {}
			groupRecs[i] = { seg = (i - 0.5) / g, seed = i * 7919.37 }
			groupLast[i] = false
		end
		for _, rec in list do
			local gi = math.clamp(math.floor(rec.seg * g) + 1, 1, g)
			table.insert(members[gi], rec)
		end
		groupCursor = 0
		groupsDirty = false
	end

	local function groupedTick(t: number, cfg: any)
		local g = math.clamp(math.floor(tonumber(cfg.Groups) or 40), 4, 200)
		if groupsDirty or g ~= groupCount then
			rebuildGroups(g)
		end
		local tol = cfg.ColorTolerance or 0.05
		local budget = math.max(1, cfg.MaxWritesPerTick or 120)
		local writes = 0
		for _ = 1, groupCount do
			local gi = groupCursor % groupCount + 1
			local mem = members[gi]
			if #mem > 0 then
				local c = colorAt(groupRecs[gi], t)
				local last = groupLast[gi]
				if not (last and sameColor(last, c, tol)) then
					if writes > 0 and writes + #mem > budget then
						return -- resume at this group on the next tick
					end
					for _, rec in mem do
						paint(rec, c)
					end
					groupLast[gi] = c
					writes += #mem
				end
			end
			groupCursor = gi
		end
	end

	local function forgetGroupColors()
		for i = 1, groupCount do
			groupLast[i] = false
		end
	end

	-- Gates -----------------------------------------------------------------------------------------------
	local function center(): Vector3
		return if #list > 0 then sum / #list else base.Center
	end

	local function inRange(cfg: any): boolean
		local camPos = Util.cameraPosition()
		if not camPos then
			return false
		end
		return (center() - camPos).Magnitude <= cfg.MaxDistance
	end

	local function inView(cfg: any): boolean
		local camPos, look = Util.cameraView()
		if not camPos or not look then
			return true
		end
		local near = cfg.ViewNear or 450
		local dotMin = cfg.ViewDot or 0.2
		local any = false
		for _, p in samples do
			any = true
			local d = p - camPos
			local m = d.Magnitude
			if m < near or d:Dot(look) / m >= dotMin then
				return true
			end
		end
		if not any then
			local d = center() - camPos
			local m = d.Magnitude
			return m < near or d:Dot(look) / m >= dotMin
		end
		return false
	end

	-- Main loop ---------------------------------------------------------------------------------------------
	local mode = "day" -- "day" | "static" | "animate"
	local settled = true -- day / static: a full pass found nothing left to write
	local passCount, passWrites = 0, 0
	local gateTimer = math.huge
	local viewTimer = math.huge
	local visible = true
	local tickAcc = math.huge

	-- A tier change switches between per-LED and grouped updates (or the group count): the
	-- remembered group colours no longer describe what the parts wear, so every group is
	-- recomputed and rewritten on the next tick.
	Util.onTierChanged(function()
		forgetGroupColors()
		groupsDirty = true
		tickAcc = math.huge
	end)

	game:GetService("RunService").Heartbeat:Connect(function(dt: number)
		local n = #list
		if n == 0 then
			return
		end
		local cfg = Util.tierConfig(base)
		gateTimer += dt
		if gateTimer >= 0.5 then
			gateTimer = 0
			local want = if not DayNight.isNight() then "day" elseif inRange(cfg) then "animate" else "static"
			if want ~= mode then
				mode = want
				settled = false
				passCount, passWrites = 0, 0
				forgetGroupColors()
				tickAcc = math.huge
			end
		end

		if mode == "animate" then
			viewTimer += dt
			if viewTimer >= 0.25 then
				viewTimer = 0
				visible = inView(cfg)
			end
			if not visible then
				return -- behind the camera: colours freeze
			end
			local t = workspace:GetServerTimeNow()
			if cfg.Grouped then
				tickAcc += dt
				if tickAcc >= 1 / math.max(1, cfg.TickHz or 10) then
					tickAcc = 0
					groupedTick(t, cfg)
				end
				return
			end
			local tol = cfg.ColorTolerance or 0.012
			local count = math.min(n, cfg.MaxPerFrame, math.max(1, math.ceil(n * cfg.UpdateHz * dt)))
			for _ = 1, count do
				cursor = cursor % n + 1
				local rec = list[cursor]
				if rec then
					local c = colorAt(rec, t)
					if not rec.active or not sameColor(rec.last, c, tol) then
						paint(rec, c)
					end
				end
			end
			return
		end

		if settled then
			return
		end
		-- day restore / static colour: chunked passes until one full pass writes nothing
		local perFrame = if cfg.Grouped
			then math.max(10, math.floor((cfg.MaxWritesPerTick or 120) * (cfg.TickHz or 10) / 30))
			else cfg.MaxPerFrame
		local toStatic = mode == "static"
		for _ = 1, math.min(n, perFrame) do
			cursor = cursor % n + 1
			local rec = list[cursor]
			if rec then
				if toStatic then
					if not rec.active or rec.last ~= STATIC then
						paint(rec, STATIC)
						passWrites += 1
					end
				elseif rec.active then
					rec.active = false
					rec.last = nil
					rec.part.Material = rec.material
					rec.part.Color = rec.color
					passWrites += 1
				end
			end
			passCount += 1
			if passCount >= n then
				if passWrites == 0 then
					settled = true
					return
				end
				passCount, passWrites = 0, 0
			end
		end
	end)
end

return Bridge
