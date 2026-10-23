-- GwangalliKaraokePlus/Lyrics (client): the TJ-style two-line lyric display with a per-syllable colour
-- wipe. Line slot 1 (upper) is left-aligned, slot 2 (lower) right-aligned; lines alternate between the
-- slots following the chart's display schedule (show / hide). The wipe colour follows the line part:
-- 남 = blue, 여 = pink, 같이 = green. Four countdown dots run before a line that starts after a gap.
--   Lyrics.new(parent, W, y, size) -> api { setChart(chart), update(st), setSize("S"|"M"|"L"), clear() }

local TextService = game:GetService("TextService")

local Lyrics = {}

local FONT = Enum.Font.GothamBlack
local SIZES = { S = 52, M = 62, L = 74 }
local PART = {
	M = Color3.fromRGB(70, 170, 255),
	F = Color3.fromRGB(255, 92, 170),
	A = Color3.fromRGB(70, 230, 140),
}
local STROKE = Color3.fromRGB(10, 10, 24)

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

local function lineAt(c: any, st: number): number
	for i, l in c.lines do
		if st < l.e + 0.05 then
			return i
		end
	end
	return #c.lines
end

local function label(parent: Instance, color: Color3, size: number, z: number): TextLabel
	local l = new("TextLabel", {
		BackgroundTransparency = 1,
		Font = FONT,
		TextSize = size,
		TextColor3 = color,
		TextStrokeTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		ZIndex = z,
	}, parent)
	new("UIStroke", { Color = STROKE, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, l)
	return l
end

function Lyrics.new(parent: Instance, W: number, y: number, sizeName: string?): any
	local api: any = { chart = nil, size = SIZES[sizeName or "M"] or SIZES.M, slots = {} }
	local holder = new("Frame", { Name = "Lyrics", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, y), Size = UDim2.fromOffset(W, 260), ZIndex = 30 }, parent)
	api.holder = holder
	local MARGIN = 70
	for s = 1, 2 do
		local frame = new("Frame", { Name = "Line" .. s, BackgroundTransparency = 1, Size = UDim2.fromOffset(100, 90), Position = UDim2.fromOffset(MARGIN, if s == 1 then 20 else 130), ZIndex = 30, Visible = false }, holder)
		local base = label(frame, Color3.new(1, 1, 1), api.size, 31)
		local clip = new("Frame", { Name = "Clip", BackgroundTransparency = 1, ClipsDescendants = true, Size = UDim2.fromScale(0, 1), ZIndex = 32 }, frame)
		local fill = label(clip, PART.A, api.size, 33)
		fill.Size = UDim2.fromOffset(100, 90)
		local part = new("TextLabel", { BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 22, TextColor3 = Color3.new(1, 1, 1), Text = "", Size = UDim2.fromOffset(60, 26), Position = UDim2.fromOffset(-64, 30), ZIndex = 31, TextXAlignment = Enum.TextXAlignment.Right }, frame)
		api.slots[s] = { frame = frame, base = base, clip = clip, fill = fill, part = part, li = 0, widths = {}, w = 0 }
	end
	-- 4 countdown dots
	local dots = new("Frame", { Name = "Dots", BackgroundTransparency = 1, Position = UDim2.fromOffset(MARGIN, 0), Size = UDim2.fromOffset(200, 18), ZIndex = 34, Visible = false }, holder)
	api.dots = {}
	for i = 1, 4 do
		local d = new("Frame", { Size = UDim2.fromOffset(16, 16), Position = UDim2.fromOffset((i - 1) * 26, 0), BackgroundColor3 = Color3.fromRGB(255, 200, 60), BorderSizePixel = 0, ZIndex = 34 }, dots)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, d)
		new("UIStroke", { Color = STROKE, Thickness = 2 }, d)
		api.dots[i] = d
	end
	api.dotsFrame = dots

	local function measure(text: string, size: number): number
		local ok, v = pcall(TextService.GetTextSize, TextService, text, size, FONT, Vector2.new(4000, 200))
		return if ok then v.X else #text * size * 0.5
	end

	local function assign(slotI: number, li: number)
		local sl = api.slots[slotI]
		if sl.li == li then
			return
		end
		sl.li = li
		local l = api.chart and api.chart.lines[li]
		if not l then
			sl.frame.Visible = false
			return
		end
		local size = api.size
		local w = measure(l.text, size)
		local maxW = W - MARGIN * 2
		if w > maxW then
			size = math.floor(size * maxW / w)
			w = measure(l.text, size)
		end
		sl.size = size
		sl.base.TextSize = size
		sl.fill.TextSize = size
		sl.base.Text = l.text
		sl.fill.Text = l.text
		sl.w = w
		sl.frame.Size = UDim2.fromOffset(w + 8, size + 24)
		sl.fill.Size = UDim2.fromOffset(w + 8, size + 24)
		sl.frame.Position = UDim2.fromOffset(if slotI == 1 then MARGIN else W - MARGIN - w, if slotI == 1 then 20 else 40 + size + 24)
		sl.fill.TextColor3 = PART[l.part] or PART.A
		-- prefix widths per character index (cumulative)
		local widths = {}
		local acc = ""
		for ci, ch in l.chars do
			acc ..= ch
			widths[ci] = measure(acc, size)
		end
		sl.widths = widths
		local duetMark = api.chart.duet and (l.part == "M" or l.part == "F" or l.part == "A")
		sl.part.Text = if duetMark then (if l.part == "M" then "남" elseif l.part == "F" then "여" else "같이") else ""
		sl.part.TextColor3 = PART[l.part] or PART.A
		sl.frame.Visible = true
	end

	local function wipeOf(sl: any, l: any, st: number): number
		if st < l.t0 then
			return 0
		end
		if st >= l.e then
			return sl.w + 8
		end
		local syl = l.syl
		for k = #syl, 1, -1 do
			local s = syl[k]
			if st >= s.t then
				local before = if s.ci > 1 then sl.widths[s.ci - 1] or 0 else 0
				local after = sl.widths[s.ci] or before
				local d = math.max(0.05, s.e - s.t)
				local u = math.clamp((st - s.t) / d, 0, 1)
				return before + (after - before) * u
			end
		end
		return 0
	end

	function api.setChart(chart: any)
		api.chart = chart
		for s = 1, 2 do
			api.slots[s].li = -1
			api.slots[s].frame.Visible = false
		end
		api.dotsFrame.Visible = false
		if chart then
			local duet = false
			local parts = {}
			for _, l in chart.lines do
				parts[l.part] = true
			end
			duet = (parts.M and parts.F) == true
			chart.duet = duet
		end
	end

	function api.setSize(name: string)
		local sz = SIZES[name] or SIZES.M
		if sz ~= api.size then
			api.size = sz
			for s = 1, 2 do
				api.slots[s].li = -1
			end
		end
	end

	function api.clear()
		api.setChart(nil)
	end

	-- st = song time (s)
	function api.update(st: number)
		local c = api.chart
		if not c then
			return
		end
		local want = { 0, 0 }
		for li, l in c.lines do
			if st >= l.show and st < l.hide then
				want[l.slot] = li
			end
		end
		for s = 1, 2 do
			if want[s] == 0 then
				if api.slots[s].frame.Visible then
					api.slots[s].frame.Visible = false
					api.slots[s].li = 0
				end
			else
				assign(s, want[s])
			end
			local sl = api.slots[s]
			if sl.frame.Visible and sl.li > 0 then
				local l = c.lines[sl.li]
				sl.clip.Size = UDim2.fromOffset(wipeOf(sl, l, st), sl.size + 24)
			end
		end
		-- countdown dots before a line that starts a block
		local dotsOn = false
		for _, l in c.lines do
			if l.dots and st < l.t0 and st >= l.t0 - 4 * c.beat then
				local left = math.clamp(math.ceil((l.t0 - st) / c.beat), 0, 4)
				for i = 1, 4 do
					api.dots[i].Visible = i <= left
				end
				local sl = api.slots[l.slot]
				local x = if l.slot == 1 then MARGIN else (sl.frame.Position.X.Offset)
				api.dotsFrame.Position = UDim2.fromOffset(x, if l.slot == 1 then 0 else 18 + (sl.size or api.size) + 24)
				dotsOn = true
				break
			end
		end
		api.dotsFrame.Visible = dotsOn
	end

	-- the line currently being sung (for the singer HUD)
	function api.currentLine(st: number): (any?, any?)
		local c = api.chart
		if not c then
			return nil, nil
		end
		local i = lineAt(c, st)
		return c.lines[i], c.lines[i + 1]
	end

	return api
end

Lyrics.PART = PART
Lyrics.measure = function(text: string, size: number): number
	local ok, v = pcall(TextService.GetTextSize, TextService, text, size, FONT, Vector2.new(4000, 200))
	return if ok then v.X else #text * size * 0.5
end

return Lyrics
