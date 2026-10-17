-- GwangalliClubPlus.Led: the centre LED wall (client).
-- Canvas: a local part 0.22 stud in front of the club's Show_LEDWall anchor (so it draws over the club
-- show's own ClubShowLED overlay and ClubLights' pixel wall), SurfaceGui in PlayerGui with Adornee.
-- Layers:
--   VJ      idle loops synced to the beat (section palettes, EQ bars, beat rings, tile flashes on drops,
--           "CLUB OCEAN 광안" logo pulse, now playing, 후원 hint) - only while nothing else owns the wall
--   Take    takeovers: order intros (from the club's Show record, exactly at rec.at), 합석 card (Booking),
--           Stage cues (후원 / DJ text / ON AIR) with server holds; one at a time by priority
--   Badge   "● ON AIR · DJ ○○" corner badge while a guest DJ plays
-- House moments (ClubLights' countdown / DROP) squeeze a takeover into the lower third and hide the
-- VJ, so the house show keeps its moment. The club's own LED overlay (tier >= 2 shows, 합석 intro)
-- stays visible whenever we have no takeover: the VJ never covers it.

local Players = game:GetService("Players")

local Led = {}

local Core: any
local S: any
local Art: any

local PPS = 10
local canvas: any = nil -- { part, gui, root, vj, take, badge }
local items: { [string]: any } = {}
local rankInfo: { [string]: any } = {}
local active: any = nil
local activateFns: { (any) -> () } = {}
local squeezed = false
local vj: any = nil

local PRI = { order = 3, booking = 3, band = 1, note = 1, donate = 2, dj = 2, djon = 2 }
local FULL = { order = true, booking = true } -- these own the whole wall even over the club's overlay

local function holdBefore(it: any, now: number): number
	local t = 0
	for _, h in it.holds or {} do
		if h[1] < now then
			t += math.min(now, h[2]) - h[1]
		end
	end
	return t
end
local function inHold(it: any, now: number): boolean
	for _, h in it.holds or {} do
		if now >= h[1] and now < h[2] then
			return true
		end
	end
	return false
end
local function endOf(it: any): number
	local t = it.start + it.dur
	for _, h in it.holds or {} do
		t += h[2] - h[1]
	end
	return t
end

-------------------------------------------------------------------------------------------------
-- canvas
-------------------------------------------------------------------------------------------------
local function buildVJ(root: Frame): any
	local v: any = {}
	v.frame = Core.frame(root, { Name = "VJ", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 1, Visible = false })
	v.bg = Core.frame(v.frame, { Name = "Bg", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.12, ZIndex = 1 })
	v.grad = Instance.new("UIGradient")
	v.grad.Parent = v.bg
	-- drop tiles (12 x 4)
	v.tiles = {}
	for r = 0, 3 do
		for c = 0, 11 do
			local t = Core.frame(v.frame, {
				Position = UDim2.fromScale(c / 12 + 0.002, r / 4 + 0.004),
				Size = UDim2.fromScale(1 / 12 - 0.004, 1 / 4 - 0.008),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 1,
				ZIndex = 2,
			})
			table.insert(v.tiles, t)
		end
	end
	-- EQ bars
	v.bars = {}
	local n = 32
	for i = 1, n do
		local b = Core.frame(v.frame, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale((i - 0.5) / n, 1),
			Size = UDim2.fromScale(1 / n * 0.7, 0.1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.3,
			ZIndex = 3,
		})
		table.insert(v.bars, b)
	end
	-- beat rings
	v.rings = {}
	for i = 1, 3 do
		local ring = Core.frame(v.frame, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0, 0),
			BackgroundTransparency = 1,
			ZIndex = 4,
			corner = UDim.new(0.5, 0),
		})
		local st = Instance.new("UIStroke")
		st.Thickness = 4
		st.Color = Color3.new(1, 1, 1)
		st.Transparency = 1
		st.Parent = ring
		local ar = Instance.new("UIAspectRatioConstraint")
		ar.AspectRatio = 1
		ar.DominantAxis = Enum.DominantAxis.Height
		ar.Parent = ring
		table.insert(v.rings, { f = ring, s = st })
	end
	v.ringN = 0
	-- scanline
	v.scan = Core.frame(v.frame, { Size = UDim2.fromScale(1, 0.025), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.5, ZIndex = 5 })
	-- logo
	v.logo = Core.text(v.frame, {
		Name = "Logo",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromScale(0.62, 0.3),
		Text = Core.L.LED.brand,
		ZIndex = 8,
		stroke = Color3.fromRGB(30, 10, 60),
	})
	v.logoScale = Instance.new("UIScale")
	v.logoScale.Parent = v.logo
	v.logoKo = Core.text(v.frame, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.64),
		Size = UDim2.fromScale(0.2, 0.13),
		Text = Core.L.LED.brandKo,
		TextColor3 = Color3.fromRGB(150, 235, 255),
		ZIndex = 8,
	})
	v.np = Core.text(v.frame, {
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromScale(0.015, 0.03),
		Size = UDim2.fromScale(0.5, 0.07),
		Text = "",
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTransparency = 0.15,
		ZIndex = 9,
	})
	v.hint = Core.text(v.frame, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(1, 0.9),
		Size = UDim2.fromScale(0.7, 0.08),
		Text = Core.L.LED.idleHint,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 9,
	})
	v.lastBeat = -1
	v.t = 0
	v.barW = 1 / n * 0.7
	v.palKey = ""
	return v
end

local function ensure(): any
	if canvas and canvas.part.Parent and canvas.gui.Parent then
		return canvas
	end
	if canvas then
		pcall(function()
			canvas.part:Destroy()
			canvas.gui:Destroy()
		end)
	end
	local cf, size = Core.ledFrame()
	local part = Core.part("PlusLED_Main", Vector3.new(size.X, size.Y, 0.05), cf * CFrame.new(0, 0, -0.22))
	part.Transparency = 1
	local gui = Core.surface("GwClubPlusLED", part, Enum.NormalId.Front, PPS, { Brightness = 2.4, MaxDistance = 240 })
	local root = Core.frame(gui, { Name = "Root", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ClipsDescendants = true })
	local take = Core.frame(root, { Name = "Take", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 10, ClipsDescendants = true })
	local badge = Core.frame(root, {
		Name = "OnAir",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.985, 0.035),
		Size = UDim2.fromScale(0.26, 0.1),
		BackgroundColor3 = Color3.fromRGB(20, 8, 30),
		BackgroundTransparency = 0.15,
		Visible = false,
		ZIndex = 40,
		corner = UDim.new(0.5, 0),
		strokeColor = Color3.fromRGB(255, 60, 90),
		strokeT = 0.1,
	})
	local badgeText = Core.text(badge, { Size = UDim2.fromScale(0.92, 0.76), Position = UDim2.fromScale(0.04, 0.12), Text = "", ZIndex = 41 })
	canvas = { part = part, gui = gui, root = root, take = take, badge = badge, badgeText = badgeText }
	vj = buildVJ(root)
	canvas.vj = vj
	return canvas
end

-------------------------------------------------------------------------------------------------
-- VJ loop
-------------------------------------------------------------------------------------------------
local PAL_BY_SECTION = { intro = 1, build = 2, drop = 3, breakdown = 4, groove = 5 }
local DEFAULT_PAL = {
	{ Color3.fromRGB(20, 40, 170), Color3.fromRGB(110, 30, 200), Color3.fromRGB(40, 220, 255) },
	{ Color3.fromRGB(40, 220, 255), Color3.fromRGB(230, 240, 255), Color3.fromRGB(150, 60, 255) },
	{ Color3.fromRGB(255, 40, 170), Color3.fromRGB(40, 220, 255), Color3.fromRGB(255, 255, 255) },
	{ Color3.fromRGB(255, 150, 50), Color3.fromRGB(30, 40, 150), Color3.fromRGB(255, 220, 160) },
	{ Color3.fromRGB(150, 50, 255), Color3.fromRGB(255, 190, 40), Color3.fromRGB(255, 255, 255) },
}
local function palette(section: string): { Color3 }
	local CS = Core.ClubShared
	local i = PAL_BY_SECTION[section] or 5
	local pals = (CS and type(CS.Palettes) == "table" and #CS.Palettes >= 5) and CS.Palettes or DEFAULT_PAL
	return pals[i] or DEFAULT_PAL[5]
end

local function dim(c: Color3, k: number): Color3
	return Color3.new(c.R * k, c.G * k, c.B * k)
end

local npAt = -1e9
local function vjStep(dt: number)
	local v = vj
	v.t += dt
	local t = v.t
	local phase, beat, _bpm, section, bar, energy = Core.beat()
	local pal = palette(section)
	local a, b, acc = pal[1], pal[2], pal[3]
	local slow = section == "intro" or section == "breakdown"
	-- colours change with the section only (no per-frame sequence allocations)
	if v.palKey ~= section then
		v.palKey = section
		v.grad.Color = Core.seq(dim(a, 0.35), dim(b, 0.5), dim(a, 0.25))
		for i, bb in v.bars do
			bb.BackgroundColor3 = a:Lerp(acc, i / #v.bars)
			bb.BackgroundTransparency = if slow then 0.55 else 0.25
		end
	end
	v.grad.Rotation = (t * 10) % 360
	local kick = (1 - phase) ^ 2.2
	local drop = section == "drop"
	local build = section == "build"
	-- bars
	local amp = if drop then 0.75 elseif build then 0.35 + 0.4 * ((bar % 8) / 8) else 0.28
	for i, bb in v.bars do
		local h = 0.04 + amp * energy * (0.3 + 0.7 * math.abs(math.sin(t * 2.3 + i * 0.47))) * (0.5 + 0.5 * kick)
		bb.Size = UDim2.new(v.barW, 0, math.clamp(h + 0.05, 0.03, 0.92), 0)
	end
	-- new beat: rings + drop tiles
	if beat ~= v.lastBeat then
		v.lastBeat = beat
		v.ringN = (v.ringN % #v.rings) + 1
		local r = v.rings[v.ringN]
		r.f.Size = UDim2.fromScale(0.05, 0.05)
		r.s.Transparency = 0.05
		r.s.Color = acc
		Core.tween(r.f, 60 / 126 * 1.6, { Size = UDim2.fromScale(1.6, 1.6) }, Enum.EasingStyle.Quad)
		Core.tween(r.s, 60 / 126 * 1.6, { Transparency = 1 }, Enum.EasingStyle.Quad)
		if drop then
			for i, tile in v.tiles do
				local on = S.hash(i, beat) > 0.72
				tile.BackgroundColor3 = if S.hash(i, beat + 7) > 0.5 then a else b
				tile.BackgroundTransparency = if on then 0.35 else 1
			end
		else
			for _, tile in v.tiles do
				tile.BackgroundTransparency = 1
			end
		end
		if beat % 4 == 0 then
			v.logoScale.Scale = 1.08
			Core.tween(v.logoScale, 0.4, { Scale = 1 })
		end
	elseif drop then
		for _, tile in v.tiles do
			if tile.BackgroundTransparency < 1 then
				tile.BackgroundTransparency = math.min(1, tile.BackgroundTransparency + dt * 2.2)
			end
		end
	end
	-- scanline: one sweep per bar
	local barPhase = ((beat % 4) + phase) / 4
	v.scan.Position = UDim2.fromScale(0, barPhase)
	v.scan.BackgroundColor3 = acc
	v.scan.BackgroundTransparency = if slow then 0.8 else 0.45
	-- logo: big in slow sections, small in the corner on the busy ones
	if slow then
		v.logo.Position = UDim2.fromScale(0.5, 0.42)
		v.logo.Size = UDim2.fromScale(0.62, 0.3)
		v.logoKo.Visible = true
		v.logo.TextTransparency = 0.05
	else
		v.logo.Position = UDim2.fromScale(0.5, 0.45)
		v.logo.Size = UDim2.fromScale(0.5, 0.24)
		v.logoKo.Visible = false
		v.logo.TextTransparency = 0.25 + 0.5 * phase
	end
	v.logo.TextColor3 = Color3.new(1, 1, 1):Lerp(acc, 0.25 * kick)
	-- now playing (ClubMusicShared)
	if os.clock() - npAt > 2 then
		npAt = os.clock()
		local M = Core.Music
		local text = ""
		if M and type(M.nowPlaying) == "function" then
			local ok, title, artist = pcall(M.nowPlaying)
			if ok and type(title) == "string" and title ~= "" then
				text = "♪ " .. title .. (if type(artist) == "string" and artist ~= "" then " · " .. artist else "")
			end
		end
		v.np.Text = text
	end
	-- 후원 hint scrolls by every 40 s
	local hk = (t % 40) / 12
	if hk < 1 then
		v.hint.Visible = true
		v.hint.Position = UDim2.fromScale(1 - hk * 1.75, 0.9)
	else
		v.hint.Visible = false
	end
end

-------------------------------------------------------------------------------------------------
-- items
-------------------------------------------------------------------------------------------------
local function addItem(key: string, kind: string, start: number, dur: number, tier: number, data: any, holds: any?)
	local it = items[key]
	if it then
		it.start = start
		it.holds = holds or it.holds
		return it
	end
	if Core.now() > start + dur + (if holds then 30 else 0) then
		return nil
	end
	it = { key = key, kind = kind, start = start, dur = dur, tier = tier, data = data, holds = holds or {}, pri = PRI[kind] or 1 }
	items[key] = it
	return it
end

local function destroyUi(it: any)
	if it.ui then
		local f = it.ui.frame
		it.ui = nil
		if f then
			f:Destroy()
		end
	end
end

local function buildUi(it: any)
	local c = ensure()
	local fn = Art[it.kind] or Art.band
	local ok, ui = pcall(fn, c.take, it.data, it.tier, it.dur)
	if ok and ui then
		ui.next = 1
		it.ui = ui
		if rankInfo[it.key] and ui.setRank then
			pcall(ui.setRank, rankInfo[it.key])
		end
	else
		warn("[GwangalliClubPlus] LED template failed:", ui)
		it.failed = true
	end
end

local function runUi(it: any, now: number, dt: number)
	local ui = it.ui
	if not ui then
		return
	end
	local el = now - it.start - holdBefore(it, now)
	while ui.steps[ui.next] and ui.steps[ui.next].t <= el do
		local st = ui.steps[ui.next]
		ui.next += 1
		pcall(st.fn, el - st.t > 0.6)
	end
	if ui.update then
		pcall(ui.update, el, dt)
	end
end

local function pick(now: number): any
	local best = nil
	for key, it in items do
		if now > endOf(it) + 0.3 then
			destroyUi(it)
			items[key] = nil
			rankInfo[key] = nil
		elseif now >= it.start and not inHold(it, now) and not it.failed then
			if not best or it.pri > best.pri or (it.pri == best.pri and it.start < best.start) then
				best = it
			end
		end
	end
	return best
end

-- the club show's own LED overlay is up (tier >= 2 show, 합석 intro)
local function officialOverlay(now: number): boolean
	local sh = Core.state.Show
	if type(sh) == "table" and type(sh.id) == "number" and sh.id > 0 and (sh.tier or 0) >= 2 and type(sh.at) == "number" then
		if now >= sh.at and now <= (sh.endAt or sh.at + 30) + 2 then
			return true
		end
	end
	local bk = Core.state.Booking
	if type(bk) == "table" and type(bk.id) == "number" and bk.id > 0 and type(bk.at) == "number" then
		local presentEnd = (bk.arriveAt or bk.at + 10) + 4.5
		if now >= bk.at and now <= presentEnd then
			return true
		end
	end
	return false
end

-- ClubLights' own pixel-wall moments: Club.server banners (WallMsg*) and the ClubDance photo moment
local runtimeCache: Instance? = nil
local function pixelMoment(now: number): boolean
	local bus = Core.Bus
	if os.clock() - (tonumber(bus.photoAt) or -1e9) < 5 then
		return true
	end
	local rt = runtimeCache
	if not (rt and rt.Parent) then
		rt = nil
		for _, m in game:GetService("CollectionService"):GetTagged("ClubRuntime") do
			if m:IsDescendantOf(workspace) then
				rt = m
				break
			end
		end
		runtimeCache = rt
	end
	if rt then
		local at, dur = rt:GetAttribute("WallMsgAt"), rt:GetAttribute("WallMsgFor")
		if type(at) == "number" and type(dur) == "number" and now >= at and now < at + math.clamp(dur, 0, 120) then
			return true
		end
	end
	return false
end

local function setSqueeze(on: boolean)
	if on == squeezed or not canvas then
		return
	end
	squeezed = on
	if on then
		Core.tween(canvas.take, 0.15, { Size = UDim2.fromScale(1, 0.3), Position = UDim2.fromScale(0, 0.7) })
	else
		Core.tween(canvas.take, 0.25, { Size = UDim2.fromScale(1, 1), Position = UDim2.fromScale(0, 0) })
	end
end

local function near(): boolean
	if not Core.inside then
		return false
	end
	local r = Core.root()
	if not r then
		return false
	end
	local cf = Core.ledFrame()
	return (r.Position - cf.Position).Magnitude < 230
end

local lastTick = os.clock()
local skip = false
local function director(_dt: number, now: number)
	-- low / saver tiers draw at half rate
	if Core.q().hz < 30 then
		skip = not skip
		if skip then
			return
		end
	end
	local t = os.clock()
	local dt = t - lastTick
	lastTick = t
	local it = pick(now)
	if not near() then
		-- far away / outside: keep the timeline, draw nothing
		if canvas then
			canvas.gui.Enabled = false
		end
		return
	end
	local c = ensure()
	c.gui.Enabled = true
	if it ~= active then
		if active and active.ui then
			if now > endOf(active) or not items[active.key] then
				destroyUi(active)
			else
				active.ui.frame.Visible = false -- held: resumes later
			end
		end
		active = it
		if it then
			if not it.ui then
				buildUi(it)
				if not it.fired then
					it.fired = true
					local late = now - it.start - holdBefore(it, now)
					for _, fn in activateFns do
						task.spawn(fn, it, late)
					end
				end
			end
			if it.ui then
				it.ui.frame.Visible = true
			end
		end
	end
	if active then
		runUi(active, now, dt)
	end
	local overlay = officialOverlay(now)
	local isBand = active ~= nil and active.ui ~= nil and active.ui.band == true
	-- the house show (countdown / DROP) and the club's own overlay keep the top of the wall:
	-- a paid / DJ takeover shrinks to the lower third meanwhile (order intros / 합석 card stay full)
	setSqueeze(active ~= nil and active.ui ~= nil and not isBand and (Core.houseMoment() or (overlay and not FULL[active.kind])))
	local showVJ = active == nil and not overlay and not Core.houseMoment() and not pixelMoment(now) and Core.showRoom
	if vj.shown ~= showVJ then
		-- hidden layers are parked (Parent nil): nothing to redraw, and renderers that lay a
		-- SurfaceGui out on structural changes pick the layer up at once
		vj.shown = showVJ
		vj.frame.Visible = showVJ
		vj.frame.Parent = if showVJ then c.root else nil
	end
	if showVJ then
		vjStep(dt)
	end
	-- DJ badge
	local dj = Core.state.DJ
	if type(dj) == "table" and dj.on then
		c.badge.Visible = true
		local left = math.max(0, (dj.untilT or 0) - now)
		c.badgeText.Text = string.format("● ON AIR · DJ %s · %d:%02d", tostring(dj.n or ""), math.floor(left / 60), math.floor(left % 60))
	else
		c.badge.Visible = false
	end
end

-------------------------------------------------------------------------------------------------
-- sources
-------------------------------------------------------------------------------------------------
local function showKey(rec: any): string
	return string.format("show:%d@%.2f", rec.id, rec.at)
end

local function onShow(rec: any)
	if type(rec) ~= "table" or type(rec.id) ~= "number" or rec.id <= 0 or type(rec.at) ~= "number" or rec.at <= 0 then
		return
	end
	local SS = Core.ShowShared
	local item = Core.menuItem(rec.item)
	local price = item and item.price or 0
	local tier = S.orderTier(price)
	local icon = "✨"
	if item and SS and type(SS.icon) == "function" then
		local ok, ic = pcall(SS.icon, item, rec.aa)
		if ok and type(ic) == "string" then
			icon = ic
		end
	end
	local data = {
		table = rec.table,
		n = rec.name,
		un = Core.userName(rec.owner),
		u = rec.owner,
		label = rec.label,
		icon = icon,
		price = price,
		menuTier = rec.tier,
		arriveAt = rec.arriveAt,
		endAt = rec.endAt,
	}
	if tier >= 2 then
		addItem(showKey(rec), "order", rec.at, S.orderIntro(tier), tier, data)
	else
		addItem(showKey(rec), "band", rec.at, S.Durations.orderBand, 1, data)
	end
end

local function onOrderEvent(p: any)
	if type(p) ~= "table" or type(p.key) ~= "string" then
		return
	end
	rankInfo[p.key] = p
	local it = items[p.key]
	if it then
		if it.ui and it.ui.setRank then
			pcall(it.ui.setRank, p)
		end
		return
	end
	-- an order served without a show: only the server saw it
	if p.source == "direct" and type(p.at) == "number" then
		local tier = S.orderTier(p.price or 0)
		local data = { table = p.table, n = p.n, un = p.un, u = p.u, label = p.label, icon = p.icon, price = p.price, arriveAt = p.arriveAt }
		if tier >= 2 then
			addItem(p.key, "order", p.at, S.orderIntro(tier), tier, data)
		else
			addItem(p.key, "band", p.at, S.Durations.orderBand, 1, data)
		end
	end
end

local function onStage(st: any)
	if type(st) ~= "table" or type(st.cues) ~= "table" then
		return
	end
	for _, c in st.cues do
		if type(c) == "table" and type(c.id) == "number" and type(c.at) == "number" and type(c.dur) == "number" then
			addItem("cue:" .. c.id, tostring(c.kind), c.at, c.dur, tonumber(c.tier) or 1, c.data or {}, c.holds)
		end
	end
end

local function onBooking(b: any)
	if type(b) ~= "table" or type(b.id) ~= "number" or b.id <= 0 or type(b.at) ~= "number" then
		return
	end
	local guests = {}
	for _, g in b.guests or {} do
		if type(g) == "table" then
			table.insert(guests, { name = g.name })
		end
	end
	addItem("bk:" .. b.id, "booking", b.at, S.Durations.booking, 3, { table = b.table, n = b.name, md = b.md, guests = guests })
end

function Led.onActivate(fn: (any, number) -> ())
	table.insert(activateFns, fn)
end

-- a local lower-band note (짠 / laser show / DJ hands ...): drawn only when nothing bigger runs
function Led.note(key: string, text: string, seconds: number, color: Color3?, startAt: number?)
	addItem("note:" .. key, "note", startAt or Core.now(), seconds, 1, { text = text, color = color })
end

-- the running takeover (kind, tier, data) or nil
function Led.current(): any?
	return active
end

function Led.init(core: any, art: any)
	Core = core
	S = core.S
	Art = art
	Core.on("Show", onShow)
	Core.on("Stage", onStage)
	Core.on("Booking", onBooking)
	Core.onEvent("order", onOrderEvent)
	Core.job("led", 30, director)
	Players.LocalPlayer.CharacterAdded:Connect(function()
		-- (the SurfaceGui is ResetOnSpawn = false; nothing to rebuild)
	end)
end

return Led
