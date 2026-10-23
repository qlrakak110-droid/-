-- GwangalliKaraokePlus/Background (client): 뮤직비디오-style TV backgrounds made only of Frames and
-- UIGradients (no image assets), chosen by the song's band preset:
--   night (발라드 · 어쿠스틱 · OST)   광안대교 야경: sky, stars, the bridge with its light show, the sea
--   neon  (팝 · 댄스 · EDM)          neon grid floor, beat rings, light bars
--   stage (트로트)                   gold stage, swinging spotlights, sparkles
--   rock  (록 · 응원가)               strobes, red diagonal stripes
--   city  (힙합 · 시티팝 · R&B)        skyline with windows, sunset / night
--   folk  (민요)                     hanji paper, mountains, sun, plum petals
--   kids  (동요 · 축하곡)              pastel sky, balloons
--   Background.new(parent, w, h) -> api { setScene(name), sceneFor(preset), update(t, beatPhase, energy) }

local Background = {}

local function new(class: string, props: { [string]: any }, parent: Instance?): any
	local i = Instance.new(class)
	for k, v in props do
		(i :: any)[k] = v
	end
	if parent then
		i.Parent = parent
	end
	return i
end

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function gradient(parent: Instance, stops: { { number } }, rot: number)
	local kp = {}
	for _, s in stops do
		table.insert(kp, ColorSequenceKeypoint.new(s[1], rgb(s[2], s[3], s[4])))
	end
	return new("UIGradient", { Color = ColorSequence.new(kp), Rotation = rot }, parent)
end

local function box(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, transp: number?, z: number?): Frame
	return new("Frame", {
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = color,
		BackgroundTransparency = transp or 0,
		BorderSizePixel = 0,
		ZIndex = z or 1,
	}, parent)
end

local function round(f: GuiObject, r: number?)
	new("UICorner", { CornerRadius = if r then UDim.new(0, r) else UDim.new(1, 0) }, f)
end

local function rand(seed: number): () -> number
	local s = seed
	return function()
		s = (s * 16807) % 2147483647
		return s / 2147483647
	end
end

local SCENE_OF = {
	ballad = "night", acoustic = "night", ost = "night",
	pop = "neon", dance = "neon", edm = "neon",
	trot = "stage", rock = "rock",
	hiphop = "city", citypop = "city", rnb = "city",
	folk = "folk", kids = "kids",
}

-------------------------------------------------------------------------------------------------
-- scenes: build(root, W, H) -> update(t, phase, energy)
-------------------------------------------------------------------------------------------------
local BUILD: { [string]: (Frame, number, number) -> ((number, number, number) -> ()) } = {}

BUILD.night = function(root, W, H)
	root.BackgroundColor3 = rgb(8, 12, 32)
	gradient(root, { { 0, 6, 10, 30 }, { 0.55, 24, 30, 78 }, { 0.62, 60, 40, 90 }, { 1, 4, 10, 26 } }, 90)
	local r = rand(7)
	local stars = {}
	for i = 1, 40 do
		local s = box(root, r() * W, r() * H * 0.5, 3, 3, rgb(255, 255, 255), 0.3, 2)
		round(s)
		stars[i] = { f = s, ph = r() * 6.28 }
	end
	-- the moon
	local moon = box(root, W * 0.78, H * 0.1, 70, 70, rgb(255, 244, 214), 0.05, 2)
	round(moon)
	-- sea
	local sea = box(root, 0, H * 0.62, W, H * 0.38, rgb(10, 20, 50), 0, 2)
	gradient(sea, { { 0, 30, 40, 100 }, { 1, 4, 8, 22 } }, 90)
	local ripples = {}
	for i = 1, 14 do
		local f = box(sea, r() * W, 20 + r() * (H * 0.34), 60 + r() * 140, 3, rgb(140, 170, 255), 0.6, 3)
		ripples[i] = { f = f, x = f.Position.X.Offset, sp = 10 + r() * 30 }
	end
	-- 광안대교: deck, two towers, cables, lights
	local deckY = H * 0.5
	box(root, -10, deckY, W + 20, 10, rgb(20, 24, 48), 0, 4)
	local towers = { W * 0.32, W * 0.68 }
	for _, tx in towers do
		box(root, tx - 7, deckY - 150, 14, 160, rgb(26, 30, 60), 0, 4)
		box(root, tx - 18, deckY - 150, 36, 8, rgb(26, 30, 60), 0, 4)
	end
	local lights = {}
	for i = 0, 47 do
		local x = (i + 0.5) * W / 48
		-- suspension curve between the towers
		local y
		local a, b = towers[1], towers[2]
		if x < a then
			local u = x / a
			y = deckY - 150 * (u ^ 2)
		elseif x > b then
			local u = (W - x) / (W - b)
			y = deckY - 150 * (u ^ 2)
		else
			local u = (x - a) / (b - a) * 2 - 1
			y = deckY - 150 + 140 * (1 - u * u)
		end
		local dot = box(root, x - 3, y - 3, 6, 6, rgb(255, 255, 255), 0, 5)
		round(dot)
		local deckDot = box(root, x - 2, deckY + 2, 4, 4, rgb(255, 255, 255), 0, 5)
		lights[i + 1] = { a = dot, b = deckDot, x = x }
		-- reflection
		local refl = box(sea, x - 2, 6 + (i % 5) * 9, 4, 18, rgb(255, 255, 255), 0.7, 3)
		lights[i + 1].c = refl
	end
	return function(t, phase, energy)
		for _, s in stars do
			s.f.BackgroundTransparency = 0.3 + 0.5 * (0.5 + 0.5 * math.sin(t * 1.7 + s.ph))
		end
		for _, rp in ripples do
			local x = (rp.x + t * rp.sp) % (W + 200) - 200
			rp.f.Position = UDim2.fromOffset(x, rp.f.Position.Y.Offset)
		end
		local hueBase = (t * 0.05) % 1
		for i, l in lights do
			local h = (hueBase + l.x / W * 0.6) % 1
			local c = Color3.fromHSV(h, 0.55, 1)
			local pulse = 0.5 + 0.5 * math.sin(t * 3 - i * 0.3 + phase * 6.28)
			l.a.BackgroundColor3 = c
			l.b.BackgroundColor3 = c
			l.c.BackgroundColor3 = c
			l.a.BackgroundTransparency = 0.1 + 0.4 * (1 - pulse) * (1 - energy * 0.5)
			l.c.BackgroundTransparency = 0.55 + 0.3 * (1 - pulse)
		end
	end
end

BUILD.neon = function(root, W, H)
	root.BackgroundColor3 = rgb(20, 6, 40)
	gradient(root, { { 0, 30, 6, 60 }, { 0.5, 90, 20, 120 }, { 0.58, 255, 60, 170 }, { 0.6, 30, 6, 60 }, { 1, 10, 2, 24 } }, 90)
	local horizon = H * 0.58
	local sun = box(root, W * 0.5 - 120, horizon - 200, 240, 240, rgb(255, 120, 200), 0.05, 2)
	round(sun)
	gradient(sun, { { 0, 255, 220, 120 }, { 1, 255, 60, 170 } }, 90)
	local floor = box(root, 0, horizon, W, H - horizon, rgb(10, 0, 24), 0, 3)
	local hlines = {}
	for i = 1, 10 do
		hlines[i] = box(floor, 0, 0, W, 2, rgb(255, 80, 220), 0.2, 4)
	end
	local vlines = {}
	for i = -8, 8 do
		local f = box(floor, W * 0.5 + i * 90, 0, 2, H, rgb(80, 220, 255), 0.35, 4)
		f.AnchorPoint = Vector2.new(0.5, 0)
		f.Rotation = -i * 7
		table.insert(vlines, f)
	end
	local rings = {}
	for i = 1, 3 do
		local rg = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(W * 0.5, H * 0.4), Size = UDim2.fromOffset(10, 10), BackgroundTransparency = 1, ZIndex = 2 }, root)
		round(rg)
		local st = new("UIStroke", { Color = rgb(80, 230, 255), Thickness = 4, Transparency = 0.2 }, rg)
		rings[i] = { f = rg, s = st }
	end
	local bars = {}
	for i = 1, 16 do
		local b = box(root, 40 + (i - 1) * ((W - 80) / 16), horizon - 10, (W - 80) / 16 - 8, 10, rgb(80, 230, 255), 0.2, 2)
		b.AnchorPoint = Vector2.new(0, 1)
		bars[i] = b
	end
	return function(t, phase, energy)
		local fh = H - horizon
		for i, l in hlines do
			local u = ((i - 1) / #hlines + t * 0.25) % 1
			l.Position = UDim2.fromOffset(0, fh * u * u)
			l.BackgroundTransparency = 0.6 - 0.5 * u
		end
		for i, rg in rings do
			local u = (phase + (i - 1) / 3) % 1
			local s = 40 + u * 900
			rg.f.Size = UDim2.fromOffset(s, s)
			rg.s.Transparency = 0.2 + 0.8 * u
			rg.s.Color = Color3.fromHSV((t * 0.1 + i * 0.2) % 1, 0.7, 1)
		end
		for i, b in bars do
			local h = 10 + (0.5 + 0.5 * math.sin(t * 7 + i * 1.3)) * 70 * (0.4 + energy) * (1 - phase * 0.6)
			b.Size = UDim2.fromOffset(b.Size.X.Offset, h)
			b.BackgroundColor3 = Color3.fromHSV((i / 16 + t * 0.05) % 1, 0.6, 1)
		end
	end
end

BUILD.stage = function(root, W, H)
	root.BackgroundColor3 = rgb(60, 6, 14)
	gradient(root, { { 0, 120, 10, 30 }, { 0.7, 60, 4, 14 }, { 1, 20, 2, 6 } }, 90)
	-- curtain folds
	for i = 0, 15 do
		local f = box(root, i * W / 16, 0, W / 16, H * 0.8, rgb(150, 16, 36), 0.1, 2)
		gradient(f, { { 0, 90, 8, 20 }, { 0.5, 190, 30, 50 }, { 1, 90, 8, 20 } }, 0)
	end
	local floor = box(root, 0, H * 0.78, W, H * 0.22, rgb(90, 50, 10), 0, 3)
	gradient(floor, { { 0, 230, 170, 60 }, { 1, 70, 30, 6 } }, 90)
	local spots = {}
	for i = 1, 3 do
		local beam = box(root, W * (0.2 + 0.3 * (i - 1)), -20, 180, H * 0.95, rgb(255, 236, 170), 0.6, 4)
		beam.AnchorPoint = Vector2.new(0.5, 0)
		new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }), Rotation = 90 }, beam)
		spots[i] = beam
	end
	local r = rand(11)
	local sparkles = {}
	for i = 1, 26 do
		local s = box(root, r() * W, r() * H, 6, 6, rgb(255, 220, 120), 0.2, 5)
		s.Rotation = 45
		sparkles[i] = { f = s, ph = r() * 6.28, x = s.Position.X.Offset, y = s.Position.Y.Offset }
	end
	return function(t, phase, energy)
		for i, b in spots do
			b.Rotation = math.sin(t * 0.8 + i * 1.7) * 22
			b.BackgroundTransparency = 0.55 + 0.25 * phase
		end
		for _, s in sparkles do
			local a = 0.5 + 0.5 * math.sin(t * 4 + s.ph)
			s.f.BackgroundTransparency = 0.1 + 0.8 * a
			s.f.Position = UDim2.fromOffset(s.x, (s.y + t * 20) % H)
		end
	end
end

BUILD.rock = function(root, W, H)
	root.BackgroundColor3 = rgb(16, 4, 6)
	gradient(root, { { 0, 30, 4, 8 }, { 1, 6, 0, 2 } }, 90)
	local stripes = {}
	for i = 0, 11 do
		local f = box(root, i * 160 - 200, -200, 70, H + 400, rgb(220, 30, 40), 0.75, 2)
		f.Rotation = 25
		stripes[i + 1] = f
	end
	local strobe = box(root, 0, 0, W, H, rgb(255, 255, 255), 1, 3)
	local amps = {}
	for i = 1, 2 do
		local a = box(root, if i == 1 then 30 else W - 230, H - 260, 200, 260, rgb(20, 20, 24), 0, 4)
		round(a, 12)
		for j = 0, 1 do
			local cone = box(a, 40, 30 + j * 115, 120, 100, rgb(40, 40, 46), 0, 5)
			round(cone)
		end
		amps[i] = a
	end
	return function(t, phase, energy)
		for i, f in stripes do
			f.Position = UDim2.fromOffset((i - 1) * 160 - 200 + (t * 60) % 160, -200)
		end
		strobe.BackgroundTransparency = if phase < 0.08 and energy > 0.3 then 0.82 else 1
		for _, a in amps do
			a.Size = UDim2.fromOffset(200, 260 + (if phase < 0.15 then 6 else 0))
		end
	end
end

BUILD.city = function(root, W, H)
	root.BackgroundColor3 = rgb(30, 14, 50)
	gradient(root, { { 0, 30, 20, 80 }, { 0.55, 230, 90, 120 }, { 0.75, 255, 170, 110 }, { 1, 40, 20, 60 } }, 90)
	local sun = box(root, W * 0.62, H * 0.38, 180, 180, rgb(255, 210, 120), 0.1, 2)
	round(sun)
	local r = rand(23)
	local windows = {}
	local x = 0
	while x < W do
		local bw = 60 + r() * 90
		local bh = 140 + r() * 300
		local b = box(root, x, H - bh, bw, bh, rgb(18, 12, 34), 0, 3)
		for wy = 14, bh - 20, 22 do
			for wx = 10, bw - 16, 18 do
				if r() < 0.55 then
					local wnd = box(b, wx, wy, 8, 10, rgb(255, 220, 140), 0.2, 4)
					table.insert(windows, { f = wnd, ph = r() * 50 })
				end
			end
		end
		x += bw + 6
	end
	return function(t, phase, energy)
		for i, w in windows do
			if (i + math.floor(t * 0.7)) % 37 == 0 then
				w.f.BackgroundTransparency = 0.85
			else
				w.f.BackgroundTransparency = 0.15 + 0.15 * math.sin(t + w.ph)
			end
		end
		sun.Position = UDim2.fromOffset(W * 0.62, H * 0.38 + math.sin(t * 0.2) * 8)
	end
end

BUILD.folk = function(root, W, H)
	root.BackgroundColor3 = rgb(236, 220, 186)
	gradient(root, { { 0, 246, 232, 200 }, { 1, 214, 190, 150 } }, 90)
	local sun = box(root, W * 0.7, H * 0.12, 150, 150, rgb(220, 70, 50), 0.05, 2)
	round(sun)
	local layers = { { 0.55, rgb(120, 140, 120), 0.2 }, { 0.65, rgb(80, 100, 90), 0.1 }, { 0.75, rgb(50, 66, 60), 0 } }
	local hills = {}
	for li, L in layers do
		for k = 0, 4 do
			local m = box(root, (k - 0.5) * W / 3.5, H * L[1], W / 2.2, H * 0.9, L[2], L[3], 2 + li)
			round(m)
			table.insert(hills, m)
		end
	end
	local r = rand(31)
	local petals = {}
	for i = 1, 22 do
		local p = box(root, r() * W, r() * H, 12, 12, rgb(255, 170, 190), 0.1, 8)
		round(p, 6)
		petals[i] = { f = p, x = r() * W, sp = 20 + r() * 40, ph = r() * 6.28 }
	end
	return function(t, phase, energy)
		for _, p in petals do
			local y = (t * p.sp + p.ph * 100) % (H + 40) - 20
			p.f.Position = UDim2.fromOffset(p.x + math.sin(t + p.ph) * 40, y)
			p.f.Rotation = (t * 60 + p.ph * 50) % 360
		end
	end
end

BUILD.kids = function(root, W, H)
	root.BackgroundColor3 = rgb(140, 200, 255)
	gradient(root, { { 0, 150, 210, 255 }, { 1, 255, 220, 240 } }, 90)
	local r = rand(41)
	local cols = { rgb(255, 120, 140), rgb(255, 210, 90), rgb(120, 220, 160), rgb(140, 160, 255), rgb(255, 160, 220) }
	local balloons = {}
	for i = 1, 14 do
		local b = box(root, r() * W, r() * H, 54, 66, cols[(i % #cols) + 1], 0.05, 3)
		round(b, 30)
		local str = box(b, 26, 64, 2, 50, rgb(255, 255, 255), 0.3, 3)
		str.Name = "String"
		balloons[i] = { f = b, x = b.Position.X.Offset, sp = 25 + r() * 35, ph = r() * 6.28 }
	end
	for i = 1, 4 do
		local c = box(root, r() * W, 30 + r() * 140, 180, 50, rgb(255, 255, 255), 0.15, 2)
		round(c)
	end
	return function(t, phase, energy)
		for _, b in balloons do
			local y = H + 80 - ((t * b.sp + b.ph * 120) % (H + 200))
			b.f.Position = UDim2.fromOffset(b.x + math.sin(t * 0.8 + b.ph) * 30, y)
		end
	end
end

function Background.sceneFor(preset: string?): string
	return SCENE_OF[preset or ""] or "night"
end

function Background.new(parent: Instance, W: number, H: number): any
	local holder = new("Frame", { Name = "Background", BackgroundTransparency = 1, Size = UDim2.fromOffset(W, H), ClipsDescendants = true, ZIndex = 1 }, parent)
	local api = { holder = holder, scene = "", update = nil :: any }
	local current: Frame? = nil
	function api.setScene(name: string)
		if name == api.scene then
			return
		end
		api.scene = name
		if current then
			current:Destroy()
		end
		local root = new("Frame", { Name = name, Size = UDim2.fromOffset(W, H), BorderSizePixel = 0, ZIndex = 1 }, holder)
		current = root
		local fn = BUILD[name] or BUILD.night
		local ok, upd = pcall(fn, root, W, H)
		api.fn = if ok then upd else nil
	end
	function api.update(t: number, phase: number, energy: number)
		if api.fn then
			pcall(api.fn, t, phase, energy)
		end
	end
	return api
end

return Background
