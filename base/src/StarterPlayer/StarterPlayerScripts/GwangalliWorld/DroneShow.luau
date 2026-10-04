-- 광안리 M 드론라이트쇼 runner (client).
-- The server publishes the start (workspace attribute GwangalliDroneShowStart = server time) and
-- the duration; every client evaluates the same timeline (DroneFormations) at
-- workspace:GetServerTimeNow() - start, so all players see the same frame.
--
-- Cost control:
--   * the pool of drones is created once, lazily, on the first show, and is parented to Workspace
--     only while a show is running AND the camera is within MaxViewDistance;
--   * positions are written with one workspace:BulkMoveTo per update (UpdateHz per tier), from
--     Heartbeat (never RenderStepped, which would block the frame);
--   * colours / visibility are refreshed at ColorHz and written only when they visibly change;
--   * while the whole show is behind the camera nothing is written;
--   * outside a show only a 0.5 s poll runs (no per-frame work at all).
-- Quality tiers (Util.tierConfig(Config.DroneShow)): phones ("low") get fewer drones drawn as
-- BillboardGui point sprites that never shrink below SpritePixels on screen (a 3.6-stud ball is
-- under 1 px from the beach on a phone and low quality levels cull it); "mid" uses fewer, larger
-- balls; "high" keeps DroneCount neon balls. A tier change rebuilds the pool at the next poll.

local RunService = game:GetService("RunService")

local DroneShow = {}

function DroneShow.start(ctx: any)
	local Config, Shared, Util = ctx.Config, ctx.Shared, ctx.Util
	local cfg = Config.DroneShow
	if not cfg or not cfg.Enabled then
		return
	end

	local formationsModule = script.Parent:FindFirstChild("DroneFormations") or script.Parent:WaitForChild("DroneFormations", 10)
	if not formationsModule or not formationsModule:IsA("ModuleScript") then
		Util.warn("DroneShow", "DroneFormations module missing")
		return
	end
	local Formations = require(formationsModule) :: any

	local center: Vector3 = cfg.Center
	local showCF = CFrame.new(center)
	if (cfg.FacingZ or 1) < 0 then
		showCF *= CFrame.Angles(0, math.pi, 0)
	end
	local padY = (cfg.SeaY or 4) - center.Y
	local maxD2 = cfg.MaxViewDistance * cfg.MaxViewDistance
	local smooth = Formations.smooth

	-- Per-tier settings, re-read when a pool is built.
	type Settings = { n: number, size: number, sprite: boolean, spritePx: number, spriteStuds: number, spriteBright: number, posInterval: number, colorInterval: number }
	local function readSettings(): Settings
		local t = Util.tierConfig(cfg)
		local legacyHz = if Util.isLow() then cfg.UpdateHzMobile else cfg.UpdateHzDesktop
		return {
			n = math.clamp(math.floor(tonumber(t.DroneCount) or 300), 1, 1500),
			size = math.max(0.5, tonumber(t.DroneSize) or 3.6),
			sprite = t.Sprite == true,
			spritePx = math.clamp(tonumber(t.SpritePixels) or 2, 1, 12),
			spriteStuds = math.max(0, tonumber(t.SpriteStuds) or 3.5),
			spriteBright = math.max(0.5, tonumber(t.SpriteBrightness) or 1.5),
			posInterval = 1 / math.max(5, tonumber(t.UpdateHz) or legacyHz or 30),
			colorInterval = 1 / math.max(2, tonumber(t.ColorHz) or 15),
		}
	end
	local S: Settings = readSettings()
	local N = S.n
	local viewDot = tonumber(cfg.ViewSkipDot) or -0.2
	local viewMin2 = (tonumber(cfg.ViewSkipMin) or 700) ^ 2

	-- Lazily built state ---------------------------------------------------------------------------
	local F: { [string]: any }? = nil
	local builtFor = 0 -- drone count F / stagger were built for
	local stagger: { number } = {}
	local timeline: { any }? = nil
	local timelineFor = -1
	local folder: Folder? = nil
	local parts: { BasePart } = {}
	local sprites: { Frame } = {} -- sprite mode: the coloured dot of each drone
	local guis: { BillboardGui } = {}
	local cframes: { CFrame } = {}
	local lastPos: { Vector3 } = {} -- position last written per drone
	local movedParts: { BasePart } = {} -- reused BulkMoveTo arrays (only drones that moved visibly)
	local movedCFrames: { CFrame } = {}
	local lastColor: { Color3 } = {}
	local visible: { boolean } = {}

	local function ensureFormations()
		if F and builtFor == N then
			return
		end
		F = Formations.build(N, padY, function(a: number, b: number?)
			return Shared.hash01(a, b)
		end, function()
			task.wait() -- run() is called from the gate thread, which may yield
		end)
		table.clear(stagger)
		for i = 1, N do
			stagger[i] = Shared.hash01(i, 71)
		end
		builtFor = N
	end

	local function ensureTimeline(duration: number)
		if timeline and math.abs(timelineFor - duration) < 1e-3 then
			return
		end
		timeline = Formations.timeline(duration)
		timelineFor = duration
	end

	local function destroyPool()
		if folder then
			folder:Destroy()
			folder = nil
		end
		table.clear(parts)
		table.clear(sprites)
		table.clear(guis)
		table.clear(cframes)
		table.clear(lastPos)
		table.clear(lastColor)
		table.clear(visible)
	end

	local function ensurePool(): Folder
		if folder then
			return folder
		end
		local f = Instance.new("Folder")
		f.Name = "GwangalliDroneShow"
		local size = S.size
		local sprite = S.sprite
		local start = showCF * CFrame.new(0, padY, 0)
		local black = Color3.new(0, 0, 0)
		for i = 1, N do
			if i % 60 == 0 then
				task.wait() -- spread the one-off pool creation (not parented yet: nothing renders)
			end
			local p = Instance.new("Part")
			p.Name = "Drone"
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.Locked = true
			p.TopSurface = Enum.SurfaceType.Smooth
			p.BottomSurface = Enum.SurfaceType.Smooth
			p.CFrame = start
			if sprite then
				-- invisible anchor + a point sprite: SpriteStuds studs + SpritePixels px wide
				p.Size = Vector3.new(1, 1, 1)
				p.Transparency = 1
				local g = Instance.new("BillboardGui")
				g.Name = "Dot"
				g.Size = UDim2.new(S.spriteStuds, S.spritePx, S.spriteStuds, S.spritePx)
				g.LightInfluence = 0
				g.Brightness = S.spriteBright
				g.AlwaysOnTop = false
				g.ClipsDescendants = false
				g.ResetOnSpawn = false
				g.MaxDistance = cfg.MaxViewDistance + 800
				g.Active = false
				local dot = Instance.new("Frame")
				dot.Name = "Light"
				dot.Size = UDim2.fromScale(1, 1)
				dot.BorderSizePixel = 0
				dot.BackgroundColor3 = black
				dot.Parent = g
				g.Parent = p
				guis[i] = g
				sprites[i] = dot
			else
				p.Shape = Enum.PartType.Ball
				p.Size = Vector3.new(size, size, size)
				p.Material = Enum.Material.Neon
				p.Color = black
			end
			p.Parent = f
			parts[i] = p
			cframes[i] = start
			lastPos[i] = start.Position
			lastColor[i] = black
			visible[i] = true
		end
		folder = f
		return f
	end

	-- Quality tier changed: rebuild with the new settings at the next poll (only if it differs).
	local tierDirty = false
	Util.onTierChanged(function()
		tierDirty = true
	end)

	-- Timeline evaluation --------------------------------------------------------------------------
	local function segmentAt(t: number): any
		local tl = timeline :: { any }
		for _, seg in tl do
			if t < seg.t1 then
				return seg
			end
		end
		return tl[#tl]
	end

	-- Morph progress of drone i in a morph segment at normalised time u (0..1).
	local function morphK(seg: any, i: number, u: number): number
		local st = math.clamp(seg.stagger or 0.15, 0, 0.9)
		return smooth((u - st * stagger[i]) / (1 - st))
	end

	local function writePositions(t: number)
		local forms = F :: { [string]: any }
		local seg = segmentAt(t)
		if seg.kind == "hold" then
			local form = forms[seg.name]
			local tau = t - seg.t0
			for i = 1, N do
				cframes[i] = CFrame.new(showCF:PointToWorldSpace(form.pos(i, tau)))
			end
		else
			local a, b = forms[seg.from], forms[seg.name]
			local fromTau = seg.fromTau or 0
			local u = math.clamp((t - seg.t0) / math.max(1e-3, seg.t1 - seg.t0), 0, 1)
			for i = 1, N do
				local k = morphK(seg, i, u)
				local p = a.pos(i, fromTau):Lerp(b.pos(i, 0), k)
				-- bow the flight path toward the audience so morphs read as 3D motion
				p += Vector3.new(0, 0, math.sin(k * math.pi) * 18)
				cframes[i] = CFrame.new(showCF:PointToWorldSpace(p))
			end
		end
		-- Only drones that moved by more than about half a pixel are written: seen from the beach
		-- (~1,200 studs) most hold animations are slow bobs well under that between updates.
		-- MoveEpsilon (fraction of the camera distance, 0.0015 ~ 0.09 degrees) = 0 writes all.
		local eps = tonumber(cfg.MoveEpsilon) or 0.0015
		local camPos = Util.cameraPosition()
		local minMove2 = 0
		if camPos and eps > 0 then
			local m = (center - camPos).Magnitude * eps
			minMove2 = m * m
		end
		table.clear(movedParts)
		table.clear(movedCFrames)
		local k = 0
		for i = 1, N do
			local cf = cframes[i]
			local p = cf.Position
			local last = lastPos[i]
			local dx, dy, dz = p.X - last.X, p.Y - last.Y, p.Z - last.Z
			if dx * dx + dy * dy + dz * dz > minMove2 then
				k += 1
				movedParts[k] = parts[i]
				movedCFrames[k] = cf
				lastPos[i] = p
			end
		end
		if k == 0 then
			return
		end
		local ok = pcall(workspace.BulkMoveTo, workspace, movedParts, movedCFrames, Enum.BulkMoveMode.FireCFrameChanged)
		if not ok then
			for j = 1, k do
				movedParts[j].CFrame = movedCFrames[j]
			end
		end
	end

	local function writeColors(t: number)
		local forms = F :: { [string]: any }
		local sprite = S.sprite
		local seg = segmentAt(t)
		local hold = seg.kind == "hold"
		local form, a, b, u, fromTau
		if hold then
			form = forms[seg.name]
			u = t - seg.t0
		else
			a, b = forms[seg.from], forms[seg.name]
			fromTau = seg.fromTau or 0
			u = math.clamp((t - seg.t0) / math.max(1e-3, seg.t1 - seg.t0), 0, 1)
		end
		for i = 1, N do
			local c: Color3
			if hold then
				c = form.color(i, u)
			else
				c = a.color(i, fromTau):Lerp(b.color(i, 0), morphK(seg, i, u))
			end
			local lit = math.max(c.R, c.G, c.B) > 0.025
			if lit ~= visible[i] then
				visible[i] = lit
				if sprite then
					guis[i].Enabled = lit
				else
					parts[i].Transparency = if lit then 0 else 1
				end
			end
			if lit then
				local last = lastColor[i]
				if math.abs(last.R - c.R) + math.abs(last.G - c.G) + math.abs(last.B - c.B) > 0.015 then
					lastColor[i] = c
					if sprite then
						sprites[i].BackgroundColor3 = c
					else
						parts[i].Color = c
					end
				end
			end
		end
	end

	-- Run / stop ----------------------------------------------------------------------------------------
	local running = false
	local conn: RBXScriptConnection? = nil
	local posAcc, colorAcc = math.huge, math.huge

	local function stop()
		if conn then
			conn:Disconnect()
			conn = nil
		end
		running = false
		if folder then
			folder.Parent = nil
		end
	end

	-- Whole show behind the camera (and not close): skip writes this frame.
	local function behindCamera(): boolean
		local camPos, look = Util.cameraView()
		if not camPos or not look then
			return false
		end
		local d = center - camPos
		local d2 = d.X * d.X + d.Y * d.Y + d.Z * d.Z
		if d2 < viewMin2 then
			return false
		end
		return d:Dot(look) / math.sqrt(d2) < viewDot
	end

	local function run()
		if running then
			return
		end
		if tierDirty then
			tierDirty = false
			local newS = readSettings()
			if newS.n ~= S.n or newS.sprite ~= S.sprite or newS.size ~= S.size or newS.spritePx ~= S.spritePx or newS.spriteStuds ~= S.spriteStuds then
				destroyPool()
			end
			S = newS
			N = S.n
		end
		ensureFormations()
		local f = ensurePool()
		running = true
		posAcc, colorAcc = math.huge, math.huge
		f.Parent = workspace
		conn = RunService.Heartbeat:Connect(function(dt: number)
			local active, elapsed, duration = Shared.droneShowState()
			if not active then
				stop()
				return
			end
			ensureTimeline(duration)
			posAcc += dt
			colorAcc += dt
			local ok, err = true, nil
			local due = posAcc >= S.posInterval or colorAcc >= S.colorInterval
			if due and behindCamera() then
				return -- keep the accumulators: resume immediately when the show comes into view
			end
			if posAcc >= S.posInterval then
				posAcc = 0
				ok, err = pcall(writePositions, elapsed)
			end
			if ok and colorAcc >= S.colorInterval then
				colorAcc = 0
				ok, err = pcall(writeColors, elapsed)
			end
			if not ok then
				Util.warn("DroneShow", err)
				stop()
			end
		end)
	end

	-- 0.5 s gate: show running on the server clock and the camera close enough ----------------------
	task.spawn(function()
		while true do
			local ok, err = pcall(function()
				local active, _, duration = Shared.droneShowState()
				local want = false
				if active then
					local camPos = Util.cameraPosition()
					if camPos then
						local d = camPos - center
						want = d.X * d.X + d.Y * d.Y + d.Z * d.Z <= maxD2
					end
				end
				if want and running and tierDirty then
					stop() -- restart with the new tier's pool
				end
				if want and not running then
					ensureTimeline(duration)
					run()
				elseif not want and running then
					stop()
				end
			end)
			if not ok then
				Util.warn("DroneShow", err)
				stop()
				task.wait(5)
			end
			task.wait(0.5)
		end
	end)
end

return DroneShow
