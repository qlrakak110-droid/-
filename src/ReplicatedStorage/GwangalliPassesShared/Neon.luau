-- GwangalliPassesShared/Neon: neon nickname palettes (pure).
--   Neon.LIST / Neon.get(id)
--   Neon.sequence(p) -> ColorSequence          for a UIGradient (rainbow: a fixed hue wheel)
--   Neon.sample(p, t) -> Color3                 t in [0, 1]
--   Neon.rich(text, p, bold?) -> string         one <font color> per character (TextChatService PrefixText)

local Neon = {}

local function c(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

Neon.LIST = {
	{ id = "bridge", name = "광안대교", colors = { c(61, 214, 245), c(150, 110, 255), c(255, 79, 163) }, stroke = c(40, 20, 90), speed = 0.35 },
	{ id = "sunset", name = "해운대 노을", colors = { c(255, 170, 60), c(255, 96, 110), c(255, 70, 170) }, stroke = c(90, 20, 40), speed = 0.3 },
	{ id = "gold", name = "황금", colors = { c(255, 236, 150), c(255, 194, 71), c(220, 140, 30) }, stroke = c(70, 40, 0), speed = 0.25 },
	{ id = "aurora", name = "오로라", colors = { c(140, 255, 120), c(60, 230, 230), c(150, 100, 255) }, stroke = c(10, 50, 60), speed = 0.3 },
	{ id = "ice", name = "아이스", colors = { c(255, 255, 255), c(170, 230, 255), c(90, 170, 255) }, stroke = c(20, 50, 90), speed = 0.2 },
	{ id = "rainbow", name = "레인보우", rainbow = true, colors = { c(255, 60, 60), c(255, 200, 40), c(60, 230, 90), c(50, 170, 255), c(190, 80, 255) }, stroke = c(30, 30, 40), speed = 0.5 },
}
Neon.BY_ID = {}
for _, p in Neon.LIST do
	Neon.BY_ID[p.id] = p
end

function Neon.get(id: any): any
	return if type(id) == "string" then Neon.BY_ID[id] else nil
end

function Neon.sequence(p: any): ColorSequence
	local cols = p.colors
	if p.rainbow then
		local kps = {}
		for i = 0, 6 do
			table.insert(kps, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV((i / 6) % 1, 0.75, 1)))
		end
		return ColorSequence.new(kps)
	end
	local kps = {}
	local n = #cols
	-- mirror the palette so an offset sweep loops without a seam: a b c b a
	local seq = table.clone(cols)
	for i = n - 1, 1, -1 do
		table.insert(seq, cols[i])
	end
	for i, col in seq do
		table.insert(kps, ColorSequenceKeypoint.new((i - 1) / (#seq - 1), col))
	end
	return ColorSequence.new(kps)
end

function Neon.sample(p: any, t: number): Color3
	local cols = p.colors
	if p.rainbow then
		return Color3.fromHSV(t % 1, 0.7, 1)
	end
	local x = math.clamp(t, 0, 1) * (#cols - 1)
	local i = math.floor(x)
	local f = x - i
	local a = cols[math.clamp(i + 1, 1, #cols)]
	local b = cols[math.clamp(i + 2, 1, #cols)]
	return a:Lerp(b, f)
end

local function hex(col: Color3): string
	return string.format("#%02X%02X%02X", math.floor(col.R * 255 + 0.5), math.floor(col.G * 255 + 0.5), math.floor(col.B * 255 + 0.5))
end

local function escape(s: string): string
	s = string.gsub(s, "&", "&amp;")
	s = string.gsub(s, "<", "&lt;")
	s = string.gsub(s, ">", "&gt;")
	s = string.gsub(s, "\"", "&quot;")
	s = string.gsub(s, "'", "&apos;")
	return s
end

function Neon.rich(text: string, p: any, bold: boolean?): string
	local chars = {}
	for _, cp in utf8.codes(text) do
		table.insert(chars, utf8.char(cp))
	end
	local n = #chars
	local out = {}
	for i, ch in chars do
		local t = if n <= 1 then 0 else (i - 1) / (n - 1)
		table.insert(out, string.format("<font color=\"%s\">%s</font>", hex(Neon.sample(p, t)), escape(ch)))
	end
	local body = table.concat(out)
	return if bold then "<b>" .. body .. "</b>" else body
end

Neon.escape = escape
Neon.hex = hex

return Neon
