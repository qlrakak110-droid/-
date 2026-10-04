-- Formations and timeline for the 광안리 M 드론라이트쇼.
-- Show-local coordinates (studs): x = viewer's right, y = up (relative to Config.DroneShow.Center),
-- z = toward the viewers on the beach. Every formation exposes pos(i, tau) and color(i, tau)
-- for drone i (1..N) at `tau` seconds into its hold. Point lists are sorted left-to-right so
-- morphs between formations keep drones in roughly the same region.

local Formations = {}

type Formation = {
	pos: (i: number, tau: number) -> Vector3,
	color: (i: number, tau: number) -> Color3,
}

---------------------------------------------------------------------------------------------------
-- Pixel fonts
---------------------------------------------------------------------------------------------------

-- 12 x 13 Hangul syllables for "광안리".
local HANGUL: { [string]: { string } } = {
	["광"] = {
		".#####...#..",
		".....#...#..",
		".....#...#..",
		".....#...###",
		"...#.....#..",
		"...#.....#..",
		"#######..#..",
		".........#..",
		"....###.....",
		"..##...##...",
		"..#.....#...",
		"..##...##...",
		"....###.....",
	},
	["안"] = {
		"..###....#..",
		".#...#...#..",
		"#.....#..#..",
		"#.....#..###",
		".#...#...#..",
		"..###....#..",
		".........#..",
		".........#..",
		".#..........",
		".#..........",
		".#..........",
		".#..........",
		".#########..",
	},
	["리"] = {
		".........#..",
		"######...#..",
		".....#...#..",
		".....#...#..",
		".....#...#..",
		".....#...#..",
		"######...#..",
		"#........#..",
		"#........#..",
		"#........#..",
		"#........#..",
		"######...#..",
		".........#..",
	},
}

-- 5 x 7 Latin capitals for "GWANGALLI".
local LATIN: { [string]: { string } } = {
	G = { ".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".###." },
	W = { "#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#" },
	A = { ".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#" },
	N = { "#...#", "##..#", "##..#", "#.#.#", "#..##", "#..##", "#...#" },
	L = { "#....", "#....", "#....", "#....", "#....", "#....", "#####" },
	I = { "###", ".#.", ".#.", ".#.", ".#.", ".#.", "###" },
}

-- Lays out glyphs left to right; returns lit pixel centres (x right, y up) centred on the origin.
local function textPixels(glyphs: { { string } }, gap: number, pixel: number): { Vector2 }
	local height = 0
	local width = 0
	for gi, g in glyphs do
		height = math.max(height, #g)
		width += #g[1] + (if gi < #glyphs then gap else 0)
	end
	local out = {}
	local x0 = 0
	for _, g in glyphs do
		for row, line in g do
			for col = 1, #line do
				if string.sub(line, col, col) == "#" then
					local px = x0 + col - 1
					local py = row - 1
					table.insert(out, Vector2.new((px - (width - 1) / 2) * pixel, ((height - 1) / 2 - py) * pixel))
				end
			end
		end
		x0 += #g[1] + gap
	end
	return out
end

---------------------------------------------------------------------------------------------------
-- Point-set helpers
---------------------------------------------------------------------------------------------------

-- Distributes n drones over m pixels; drones sharing a pixel sit on a small ring around it.
local function spreadOverPixels(pixels: { Vector2 }, n: number, pixel: number): { Vector3 }
	local m = #pixels
	local out = table.create(n)
	if m == 0 then
		for _ = 1, n do
			table.insert(out, Vector3.zero)
		end
		return out
	end
	local counts = table.create(m, 0)
	local owner = table.create(n)
	for i = 1, n do
		local j = math.min(m, math.floor((i - 1) * m / n) + 1)
		owner[i] = j
		counts[j] += 1
	end
	local seen = table.create(m, 0)
	for i = 1, n do
		local j = owner[i]
		local c = counts[j]
		local k = seen[j]
		seen[j] = k + 1
		local p = pixels[j]
		if c <= 1 then
			table.insert(out, Vector3.new(p.X, p.Y, 0))
		else
			local a = (k / c) * math.pi * 2 + j
			local r = pixel * 0.3
			table.insert(out, Vector3.new(p.X + math.cos(a) * r, p.Y + math.sin(a) * r, (k % 2) * 2 - 1))
		end
	end
	return out
end

-- Samples n points evenly by arc length over a set of polylines ({ {Vector2...}, ... }).
local function samplePolylines(lines: { { Vector2 } }, n: number): { Vector3 }
	local segs = {}
	local total = 0
	for _, line in lines do
		for k = 1, #line - 1 do
			local a, b = line[k], line[k + 1]
			local len = (b - a).Magnitude
			if len > 1e-6 then
				table.insert(segs, { a = a, b = b, len = len, start = total })
				total += len
			end
		end
	end
	local out = table.create(n)
	if total <= 0 then
		for _ = 1, n do
			table.insert(out, Vector3.zero)
		end
		return out
	end
	local si = 1
	for i = 1, n do
		local d = (i - 0.5) / n * total
		while si < #segs and d > segs[si].start + segs[si].len do
			si += 1
		end
		local s = segs[si]
		local f = math.clamp((d - s.start) / s.len, 0, 1)
		local p = s.a:Lerp(s.b, f)
		table.insert(out, Vector3.new(p.X, p.Y, 0))
	end
	return out
end

-- Uniformly scales and centres points so they fit in maxW x maxH. Also returns a function that
-- maps a raw 2D point into the same fitted space.
local function fit(points: { Vector3 }, maxW: number, maxH: number): ({ Vector3 }, (number, number) -> (number, number))
	local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
	for _, p in points do
		minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
		minY, maxY = math.min(minY, p.Y), math.max(maxY, p.Y)
	end
	local w, h = math.max(1e-6, maxX - minX), math.max(1e-6, maxY - minY)
	local s = math.min(maxW / w, maxH / h)
	local cx, cy = (minX + maxX) / 2, (minY + maxY) / 2
	local out = table.create(#points)
	for i, p in points do
		out[i] = Vector3.new((p.X - cx) * s, (p.Y - cy) * s, p.Z)
	end
	return out, function(x: number, y: number)
		return (x - cx) * s, (y - cy) * s
	end
end

-- Sorts points left-to-right (then bottom-to-top) and returns them with the permutation applied
-- to any parallel arrays given in `extra`.
local function sortLeftToRight(points: { Vector3 }, extra: { { any } }?): { Vector3 }
	local idx = table.create(#points)
	for i = 1, #points do
		idx[i] = i
	end
	table.sort(idx, function(a, b)
		local pa, pb = points[a], points[b]
		if math.abs(pa.X - pb.X) > 0.01 then
			return pa.X < pb.X
		end
		return pa.Y < pb.Y
	end)
	local out = table.create(#points)
	for k, i in idx do
		out[k] = points[i]
	end
	if extra then
		for _, arr in extra do
			local copy = table.clone(arr)
			for k, i in idx do
				arr[k] = copy[i]
			end
		end
	end
	return out
end

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local fromHSV = Color3.fromHSV
local BLACK = Color3.new(0, 0, 0)

---------------------------------------------------------------------------------------------------
-- Formation builders
---------------------------------------------------------------------------------------------------

-- `yieldFn` (optional) is called between formations so a caller on its own thread can spread the
-- one-off build over several frames (phones: the whole build in one frame is a visible hitch).
function Formations.build(n: number, padY: number, hash: (number, number?) -> number, yieldFn: (() -> ())?): { [string]: Formation }
	local F: { [string]: Formation } = {}
	local function step()
		if yieldFn then
			yieldFn()
		end
	end
	local h1, h2 = table.create(n), table.create(n)
	for i = 1, n do
		h1[i] = hash(i, 3)
		h2[i] = hash(i, 11)
	end

	-- Launch barge on the water -----------------------------------------------------------------
	do
		local cols = math.ceil(math.sqrt(n * 1.33))
		local rows = math.ceil(n / cols)
		local pts = table.create(n)
		for i = 1, n do
			local c = (i - 1) % cols
			local r = (i - 1) // cols
			pts[i] = Vector3.new((c - (cols - 1) / 2) * 6, padY, (r - (rows - 1) / 2) * 6)
		end
		pts = sortLeftToRight(pts)
		F.pad = {
			pos = function(i)
				return pts[i]
			end,
			color = function(i, tau)
				local a = smooth(tau / 1.5) * 0.55
				return Color3.new(0.85 * a, 0.9 * a, a)
			end,
		}
		F.landed = {
			pos = function(i)
				return pts[i]
			end,
			color = function(_i, tau)
				local a = (1 - smooth(tau / 2.5)) * 0.55
				return Color3.new(0.85 * a, 0.9 * a, a)
			end,
		}
	end

	step()

	-- Grid curtain with a travelling wave ----------------------------------------------------------
	do
		local cols = math.ceil(math.sqrt(n * 2.4))
		local rows = math.ceil(n / cols)
		local pts = table.create(n)
		for i = 1, n do
			local c = (i - 1) % cols
			local r = (i - 1) // cols
			pts[i] = Vector3.new((c - (cols - 1) / 2) * 24, (r - (rows - 1) / 2) * 13, 0)
		end
		pts = sortLeftToRight(pts)
		F.grid = {
			pos = function(i, tau)
				local p = pts[i]
				local amp = 22 * smooth(tau / 3)
				return Vector3.new(p.X, p.Y + math.sin(p.X * 0.012 + tau * 1.1) * amp * 0.25, math.sin(p.X * 0.018 + p.Y * 0.01 + tau * 1.4) * amp)
			end,
			color = function(i, tau)
				local p = pts[i]
				local hue = (0.56 + 0.08 * math.sin(p.X * 0.008 + tau * 0.7)) % 1
				local v = 0.7 + 0.3 * math.sin(tau * 5 + h1[i] * 30)
				return fromHSV(hue, 0.5, v)
			end,
		}
	end

	step()

	-- "광안리" ------------------------------------------------------------------------------------------
	do
		local pixel = 11
		local pts = spreadOverPixels(textPixels({ HANGUL["광"], HANGUL["안"], HANGUL["리"] }, 2, pixel), n, pixel)
		pts = sortLeftToRight(pts)
		local minX, maxX = pts[1].X, pts[#pts].X
		local span = math.max(1, maxX - minX)
		F.hangul = {
			pos = function(i, tau)
				local p = pts[i]
				return Vector3.new(p.X, p.Y + math.sin(tau * 0.9 + p.X * 0.01) * 3, p.Z)
			end,
			color = function(i, tau)
				local x = (pts[i].X - minX) / span
				local sweep = (x - tau * 0.3) % 1
				if sweep < 0.08 then
					return Color3.new(1, 1, 1)
				end
				return Color3.fromRGB(110, 214, 255):Lerp(Color3.fromRGB(190, 150, 255), x)
			end,
		}
	end

	step()

	-- Heart (three nested outlines), beating --------------------------------------------------------
	do
		local raw = table.create(n)
		local layer = table.create(n)
		local outer = math.floor(n * 0.55)
		local middle = math.floor(n * 0.3)
		local function heartPoint(t: number, s: number): Vector3
			local x = 16 * math.sin(t) ^ 3
			local y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
			return Vector3.new(x * s, y * s, 0)
		end
		for i = 1, n do
			local s, k, count
			if i <= outer then
				s, k, count = 1, i, outer
			elseif i <= outer + middle then
				s, k, count = 0.66, i - outer, middle
			else
				s, k, count = 0.33, i - outer - middle, n - outer - middle
			end
			raw[i] = heartPoint((k - 0.5) / math.max(1, count) * math.pi * 2, s)
			layer[i] = s
		end
		local fitted = fit(raw, 250, 210)
		local pts = sortLeftToRight(fitted, { layer })
		F.heart = {
			pos = function(i, tau)
				local beat = 1 + 0.07 * math.max(0, math.sin(tau * 5.5)) ^ 4
				local p = pts[i]
				return Vector3.new(p.X * beat, p.Y * beat, p.Z)
			end,
			color = function(i, tau)
				local v = 0.8 + 0.2 * math.sin(tau * 5.5)
				return fromHSV(0.97 + (1 - layer[i]) * 0.02, 0.55 + 0.35 * layer[i], v)
			end,
		}
	end

	step()

	-- Whale (the real show's signature image): humpback in side view, tail raised, water spout ----
	do
		local V = Vector2.new
		local body = {
			V(0.98, -0.02), V(0.92, 0.14), V(0.78, 0.26), V(0.55, 0.33), V(0.30, 0.34), V(0.05, 0.30),
			V(-0.20, 0.22), V(-0.40, 0.14), V(-0.55, 0.12), V(-0.66, 0.18), V(-0.74, 0.30), V(-0.78, 0.40),
			V(-0.70, 0.52), V(-0.80, 0.47), V(-0.86, 0.44), V(-0.93, 0.54), V(-0.92, 0.40), V(-0.84, 0.30),
			V(-0.76, 0.16), V(-0.68, 0.02), V(-0.52, -0.08), V(-0.25, -0.18), V(0.10, -0.24), V(0.45, -0.24),
			V(0.72, -0.18), V(0.90, -0.10), V(0.98, -0.02),
		}
		local mouth = { V(0.97, -0.03), V(0.80, -0.05), V(0.62, -0.02) }
		local fin = { V(0.36, -0.15), V(0.24, -0.36), V(0.14, -0.33), V(0.16, -0.20) }
		local spout = {
			{ V(0.55, 0.36), V(0.55, 0.64) },
			{ V(0.55, 0.64), V(0.47, 0.71), V(0.39, 0.66) },
			{ V(0.55, 0.64), V(0.63, 0.71), V(0.71, 0.66) },
		}
		local nSpout = math.floor(n * 0.16)
		local nFin = math.floor(n * 0.08)
		local nMouth = math.floor(n * 0.04)
		local nEye = math.min(3, math.max(0, n - nSpout - nFin - nMouth - 1))
		local nBody = n - nSpout - nFin - nMouth - nEye
		local raw: { Vector3 } = {}
		local kind: { number } = {} -- 0 body, 1 eye, 2 spout, 3 fin, 4 mouth
		local function add(points: { Vector3 }, k: number)
			for _, p in points do
				table.insert(raw, p)
				table.insert(kind, k)
			end
		end
		add(samplePolylines({ body }, nBody), 0)
		add(samplePolylines({ mouth }, nMouth), 4)
		add(samplePolylines({ fin }, nFin), 3)
		add(samplePolylines(spout, nSpout), 2)
		for k = 1, nEye do
			add({ Vector3.new(0.72 + (k - 2) * 0.012, 0.07, 0) }, 1)
		end
		local fitted, toFit = fit(raw, 480, 240)
		local pts = sortLeftToRight(fitted, { kind })
		-- tail stock pivot for the fluke stroke, and the blowhole the spout grows from
		local tailX, tailY = toFit(-0.55, 0.12)
		local _, holeY = toFit(0.55, 0.36)
		F.whale = {
			pos = function(i, tau)
				local p = pts[i]
				local k = kind[i]
				local bob = 6 * math.sin(tau * 0.8)
				if k == 2 then
					-- the spout pulses upward from the blowhole
					local grow = 0.7 + 0.3 * math.sin(tau * 2.2)
					return Vector3.new(p.X, holeY + (p.Y - holeY) * grow + bob, p.Z)
				end
				if p.X < tailX then
					local a = 0.12 * math.sin(tau * 1.6)
					local dx, dy = p.X - tailX, p.Y - tailY
					local ca, sa = math.cos(a), math.sin(a)
					return Vector3.new(tailX + dx * ca - dy * sa, tailY + dx * sa + dy * ca + bob, p.Z)
				end
				return Vector3.new(p.X, p.Y + bob, p.Z)
			end,
			color = function(i, tau)
				local k = kind[i]
				if k == 1 then
					return Color3.new(1, 1, 1)
				elseif k == 2 then
					local tw = 0.7 + 0.3 * math.sin(tau * 9 + h1[i] * 40)
					return fromHSV(0.54, 0.15 + 0.25 * h2[i], tw)
				elseif k == 3 or k == 4 then
					return Color3.fromRGB(120, 200, 255)
				end
				local y = math.clamp(pts[i].Y / 180 + 0.5, 0, 1)
				local shimmer = 0.85 + 0.15 * math.sin(tau * 1.4 + pts[i].X * 0.02)
				local c = Color3.fromRGB(30, 110, 255):Lerp(Color3.fromRGB(110, 225, 255), y)
				return Color3.new(c.R * shimmer, c.G * shimmer, c.B * shimmer)
			end,
		}
	end

	step()

	-- Camellia (동백꽃, Busan's city flower): five red petals, yellow stamens, two leaves ----------
	do
		local V = Vector2.new
		local outline = {}
		for k = 0, 90 do
			local th = k / 90 * math.pi * 2
			local r = 0.62 + 0.38 * math.abs(math.cos(2.5 * (th - math.pi / 2)))
			table.insert(outline, V(math.cos(th) * r, math.sin(th) * r))
		end
		local seps = {}
		for k = 0, 4 do
			-- petal separations sit at the outline dips, between the lobes
			local th = math.pi / 2 + (k + 0.5) * math.pi * 2 / 5
			table.insert(seps, { V(math.cos(th) * 0.22, math.sin(th) * 0.22), V(math.cos(th) * 0.6, math.sin(th) * 0.6) })
		end
		local stamen = {}
		for k = 0, 24 do
			local th = k / 24 * math.pi * 2
			table.insert(stamen, V(math.cos(th) * 0.2, math.sin(th) * 0.2))
		end
		local function leaf(cx: number, cy: number, ang: number)
			local pts = {}
			for k = 0, 24 do
				local t = k / 24 * math.pi * 2
				local lx, ly = math.cos(t) * 0.42, math.sin(t) * 0.16
				local ca, sa = math.cos(ang), math.sin(ang)
				table.insert(pts, V(cx + lx * ca - ly * sa, cy + lx * sa + ly * ca))
			end
			return pts
		end
		local nLeaf = math.floor(n * 0.16)
		local nStamen = math.floor(n * 0.16)
		local nSep = math.floor(n * 0.1)
		local nOutline = n - nLeaf - nStamen - nSep
		local raw: { Vector3 } = {}
		local kind: { number } = {} -- 0 petal outline, 1 separation, 2 stamen, 3 leaf
		local function add(points: { Vector3 }, k: number)
			for _, p in points do
				table.insert(raw, p)
				table.insert(kind, k)
			end
		end
		add(samplePolylines({ outline }, nOutline), 0)
		add(samplePolylines(seps, nSep), 1)
		add(samplePolylines({ stamen }, nStamen), 2)
		add(samplePolylines({ leaf(-0.95, -0.72, 0.55), leaf(0.95, -0.72, -0.55) }, nLeaf), 3)
		local fitted = fit(raw, 300, 230)
		local pts = sortLeftToRight(fitted, { kind })
		F.camellia = {
			pos = function(i, tau)
				local p = pts[i]
				local k = kind[i]
				if k == 3 then
					return Vector3.new(p.X, p.Y + math.sin(tau * 1.3 + p.X * 0.03) * 3, p.Z)
				end
				local bloom = 0.9 + 0.1 * smooth(tau / 4)
				local a = 0.05 * math.sin(tau * 0.5)
				local ca, sa = math.cos(a), math.sin(a)
				local x, y = p.X * bloom, (p.Y - 20) * bloom
				return Vector3.new(x * ca - y * sa, x * sa + y * ca + 20, p.Z)
			end,
			color = function(i, tau)
				local k = kind[i]
				if k == 2 then
					local tw = 0.8 + 0.2 * math.sin(tau * 7 + h1[i] * 30)
					return fromHSV(0.13, 0.8, tw)
				elseif k == 3 then
					return Color3.fromRGB(30, 170, 80)
				elseif k == 1 then
					return Color3.fromRGB(255, 90, 110)
				end
				local v = 0.85 + 0.15 * math.sin(tau * 2 + h2[i] * 6)
				return fromHSV(0.975, 0.9, v)
			end,
		}
	end

	step()

	-- Gwangan Bridge outline (광안대교) ---------------------------------------------------------------
	do
		local V = Vector2.new
		local towerX, top, deck, sea, halfW = 125, 85, -70, -125, 270
		local lines: { { Vector2 } } = {
			{ V(-halfW, deck), V(halfW, deck) },
			{ V(-towerX, sea), V(-towerX, top) },
			{ V(towerX, sea), V(towerX, top) },
			{ V(-towerX - 10, top - 20), V(-towerX + 10, top - 20) },
			{ V(towerX - 10, top - 20), V(towerX + 10, top - 20) },
		}
		local cable = {}
		for k = 0, 24 do
			local x = -towerX + k / 24 * towerX * 2
			table.insert(cable, V(x, -55 + (top + 55) * (x / towerX) ^ 2))
		end
		table.insert(lines, cable)
		for _, sgn in { -1, 1 } do
			local side = {}
			for k = 0, 8 do
				local f = k / 8
				local x = sgn * (towerX + (halfW - towerX) * f)
				local y = top + (deck + 8 - top) * f - 18 * math.sin(f * math.pi)
				table.insert(side, V(x, y))
			end
			table.insert(lines, side)
		end
		for x = -100, 100, 25 do
			if x ~= 0 then
				table.insert(lines, { V(x, -55 + (top + 55) * (x / towerX) ^ 2), V(x, deck) })
			end
		end
		local pts = sortLeftToRight(samplePolylines(lines, n))
		F.bridge = {
			pos = function(i)
				return pts[i]
			end,
			color = function(i, tau)
				local x = pts[i].X
				return fromHSV((x / 560 - tau * 0.12) % 1, 0.8, 1)
			end,
		}
	end

	step()

	-- "GWANGALLI" ----------------------------------------------------------------------------------------
	do
		local pixel = 10.5
		local glyphs = {}
		for _, ch in { "G", "W", "A", "N", "G", "A", "L", "L", "I" } do
			table.insert(glyphs, LATIN[ch])
		end
		local pts = sortLeftToRight(spreadOverPixels(textPixels(glyphs, 1, pixel), n, pixel))
		local minX, maxX = pts[1].X, pts[#pts].X
		local span = math.max(1, maxX - minX)
		F.latin = {
			pos = function(i, tau)
				local p = pts[i]
				return Vector3.new(p.X, p.Y + 10 + math.sin(tau * 2 + p.X * 0.02) * 4, p.Z)
			end,
			color = function(i, tau)
				local x = (pts[i].X - minX) / span
				local sweep = (x - tau * 0.35) % 1
				if sweep < 0.1 then
					return Color3.new(1, 1, 1)
				end
				return Color3.fromRGB(255, 196, 84):Lerp(Color3.fromRGB(255, 120, 150), x)
			end,
		}
	end

	step()

	-- Fireworks: five interleaved groups, each rising and bursting every CYCLE seconds -----------
	do
		local GROUPS, CYCLE, RISE, BURST = 5, 8.4, 1.5, 5.0
		local groupOf, rankOf, sizeOf = table.create(n), table.create(n), table.create(GROUPS, 0)
		for i = 1, n do
			local g = (i - 1) % GROUPS
			groupOf[i] = g
			sizeOf[g + 1] += 1
			rankOf[i] = sizeOf[g + 1] - 1
		end
		local dirs = table.create(n)
		local golden = math.pi * (3 - math.sqrt(5))
		for i = 1, n do
			local m = math.max(1, sizeOf[groupOf[i] + 1])
			local k = rankOf[i]
			local y = 1 - (k + 0.5) / m * 2
			local r = math.sqrt(math.max(0, 1 - y * y))
			local a = golden * k
			dirs[i] = Vector3.new(math.cos(a) * r, y, math.sin(a) * r * 0.6)
		end
		local function burstInfo(g: number, k: number)
			local cx = -210 + 420 * hash(g * 131 + k, 21)
			local cy = -5 + 95 * hash(g * 131 + k, 22)
			local radius = 70 + 50 * hash(g * 131 + k, 23)
			local hue = hash(g * 131 + k, 24)
			return cx, cy, radius, hue
		end
		local function stage(i: number, tau: number)
			local g = groupOf[i]
			local lt = tau - g * CYCLE / GROUPS
			if lt < 0 then
				return g, 0, -1
			end
			local k = math.floor(lt / CYCLE)
			return g, k, lt - k * CYCLE
		end
		F.fireworks = {
			pos = function(i, tau)
				local g, k, lam = stage(i, tau)
				local cx, cy, radius = burstInfo(g, k)
				local launch = Vector3.new(cx, -150, 0)
				if lam < 0 then
					return launch
				elseif lam < RISE then
					local m = math.max(1, sizeOf[g + 1])
					local p = math.clamp(lam / RISE - rankOf[i] / m * 0.2, 0, 1)
					p = 1 - (1 - p) * (1 - p)
					return launch:Lerp(Vector3.new(cx, cy, 0), p)
				elseif lam < RISE + BURST then
					local tb = lam - RISE
					local r = radius * (1 - math.exp(-3.2 * tb))
					return Vector3.new(cx, cy, 0) + dirs[i] * r - Vector3.new(0, 3 * tb * tb, 0)
				end
				local ncx = burstInfo(g, k + 1)
				return Vector3.new(ncx, -150, 0)
			end,
			color = function(i, tau)
				local g, k, lam = stage(i, tau)
				if lam < 0 then
					return BLACK
				elseif lam < RISE then
					return Color3.fromRGB(255, 214, 160)
				elseif lam < RISE + BURST then
					local tb = lam - RISE
					if tb < 0.15 then
						return Color3.new(1, 1, 1)
					end
					local _, _, _, hue = burstInfo(g, k)
					local v = (1 - tb / BURST) ^ 1.3
					if tb > BURST * 0.55 and hash(i * 7 + math.floor(tau * 12), 5) < 0.35 then
						v *= 0.25 -- crackle
					end
					return fromHSV(hue, 0.7 + 0.2 * h2[i], v)
				end
				return BLACK
			end,
		}
	end

	return F
end

---------------------------------------------------------------------------------------------------
-- Timeline (180 s reference, scaled to the configured duration)
---------------------------------------------------------------------------------------------------

export type Segment = {
	kind: string, -- "hold" | "morph"
	name: string, -- formation for holds / target for morphs
	from: string?, -- morph source
	fromTau: number?, -- tau of the source at the end of its hold
	stagger: number,
	t0: number,
	t1: number,
}

local SCRIPT = {
	{ "hold", "pad", 3 },
	{ "morph", "grid", 9, 0.35 },
	{ "hold", "grid", 10 },
	{ "morph", "hangul", 5 },
	{ "hold", "hangul", 14 },
	{ "morph", "heart", 5 },
	{ "hold", "heart", 12 },
	{ "morph", "whale", 5 },
	{ "hold", "whale", 16 },
	{ "morph", "bridge", 5 },
	{ "hold", "bridge", 14 },
	{ "morph", "latin", 5 },
	{ "hold", "latin", 13 },
	{ "morph", "fireworks", 4 },
	{ "hold", "fireworks", 24 },
	{ "morph", "camellia", 5 },
	{ "hold", "camellia", 12 },
	{ "morph", "landed", 12, 0.35 },
	{ "hold", "landed", 2 },
}

function Formations.timeline(duration: number): { Segment }
	local total = 0
	for _, s in SCRIPT do
		total += s[3]
	end
	local scale = duration / total
	local out: { Segment } = {}
	local t = 0
	local lastHold: string? = nil
	local lastHoldLen = 0
	for _, s in SCRIPT do
		local len = s[3] * scale
		local seg: Segment = {
			kind = s[1],
			name = s[2],
			from = nil,
			fromTau = nil,
			stagger = s[4] or 0.15,
			t0 = t,
			t1 = t + len,
		}
		if seg.kind == "morph" then
			seg.from = lastHold or s[2]
			seg.fromTau = lastHoldLen
		else
			lastHold = s[2]
			lastHoldLen = len
		end
		table.insert(out, seg)
		t += len
	end
	return out
end

Formations.smooth = smooth

return Formations
