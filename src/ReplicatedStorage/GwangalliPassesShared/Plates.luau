-- GwangalliPassesShared/Plates: custom plate rules (pure) + plate styles.
--   Plates.normalize(text) -> string            trim, collapse spaces, ASCII upper-case
--   Plates.validate(text) -> ok, code, clean     code: "len" | "chars" | "empty" | "digits"
--   Plates.korean(text) -> string                "12가3456" -> "12가 3456" (Korean plate spacing helper)
--   Plates.random(rng) -> string                 a random "123가 4567" plate (the editor's 🎲)
--   Plates.claimKey(clean) -> string             DataStore key (fixed-width base36 per codepoint)
--   Plates.STYLES / Plates.style(id)

local Config = require(script.Parent:WaitForChild("Config"))

local Plates = {}

local function isHangul(cp: number): boolean
	return cp >= 0xAC00 and cp <= 0xD7A3
end

local function isDigit(cp: number): boolean
	return cp >= 48 and cp <= 57
end

local function isUpper(cp: number): boolean
	return cp >= 65 and cp <= 90
end

function Plates.normalize(text: any): string
	if type(text) ~= "string" then
		return ""
	end
	local s = string.gsub(text, "[%c]", " ")
	s = string.gsub(s, "^%s+", "")
	s = string.gsub(s, "%s+$", "")
	s = string.gsub(s, "%s+", " ")
	return string.upper(s)
end

-- -> ok, code, clean
function Plates.validate(text: any): (boolean, string?, string)
	local clean = Plates.normalize(text)
	if clean == "" then
		return false, "empty", clean
	end
	if not utf8.len(clean) then
		return false, "chars", clean
	end
	local total, solid, digits = 0, 0, 0
	for _, cp in utf8.codes(clean) do
		total += 1
		if cp == 32 then
			continue
		end
		solid += 1
		if isDigit(cp) then
			digits += 1
		elseif not (isHangul(cp) or isUpper(cp) or cp == 45) then
			return false, "chars", clean
		end
	end
	local P = Config.PLATE
	if solid < P.MIN or solid > P.MAX or total > P.MAX_TOTAL then
		return false, "len", clean
	end
	if digits == solid and solid > 7 then
		return false, "digits", clean -- a bare long number reads like a phone number
	end
	return true, nil, clean
end

-- Korean plate spacing: "<2-3 digits><hangul><4 digits>" gets the space before the last 4 digits
function Plates.korean(text: any): string
	local s = Plates.normalize(text)
	local compact = string.gsub(s, " ", "")
	local head, h, tail = string.match(compact, "^(%d%d%d?)([\234-\237][\128-\191][\128-\191])(%d%d%d%d)$")
	if head and h and tail then
		local cp = utf8.codepoint(h)
		if cp and isHangul(cp) then
			return head .. h .. " " .. tail
		end
	end
	return s
end

local SYL = { "가", "나", "다", "라", "마", "거", "너", "더", "러", "머", "버", "서", "어", "저", "고", "노", "도", "로", "모", "보", "소", "오", "조", "구", "누", "두", "루", "무", "부", "수", "우", "주" }
function Plates.random(rng: Random?): string
	local r = rng or Random.new()
	return string.format("%d%s %04d", r:NextInteger(100, 699), SYL[r:NextInteger(1, #SYL)], r:NextInteger(1000, 9999))
end

local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
local function b36(n: number, width: number): string
	local out = ""
	for _ = 1, width do
		local d = n % 36
		out = string.sub(B36, d + 1, d + 1) .. out
		n = n // 36
	end
	return out
end

-- one key per plate regardless of spacing; 4 base36 chars per codepoint (max 8 * 4 + 2 = 34 < 50)
function Plates.claimKey(clean: string): string
	local compact = string.gsub(Plates.normalize(clean), " ", "")
	local parts = { "p_" }
	for _, cp in utf8.codes(compact) do
		table.insert(parts, b36(cp, 4))
	end
	return table.concat(parts)
end

---------------------------------------------------------------------------------------------------
-- styles: plate part colour / material, text colour / font, optional frame (thin bars around the plate)
---------------------------------------------------------------------------------------------------
Plates.STYLES = {
	{ id = "classic", name = "기본", bg = { 244, 244, 240 }, fg = { 18, 18, 20 }, font = "GothamBold" },
	{ id = "ev", name = "전기차", bg = { 60, 130, 220 }, bg2 = { 236, 242, 252 }, fg = { 14, 20, 40 }, font = "GothamBold", note = "파란 전기차 번호판" },
	{ id = "retro", name = "옛날 녹색", bg = { 36, 104, 64 }, fg = { 240, 236, 210 }, font = "Arcade", note = "2006년 이전 녹색 번호판" },
	{ id = "gold", name = "골드 VIP", bg = { 16, 16, 18 }, fg = { 236, 196, 110 }, font = "GothamBlack", frame = { 214, 176, 96 }, frameMat = "Metal" },
	{ id = "carbon", name = "카본", bg = { 34, 35, 38 }, fg = { 236, 238, 242 }, font = "GothamBold", frame = { 60, 62, 66 } },
	{ id = "neon", name = "네온", bg = { 10, 12, 20 }, fg = { 80, 230, 255 }, font = "GothamBlack", frame = { 80, 230, 255 }, frameMat = "Neon", glow = true },
}
Plates.BY_ID = {}
for _, s in Plates.STYLES do
	Plates.BY_ID[s.id] = s
end

function Plates.style(id: any): any
	return Plates.BY_ID[id or ""] or Plates.BY_ID[Config.PLATE.DEFAULT_STYLE] or Plates.STYLES[1]
end

function Plates.rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

function Plates.font(name: string): Enum.Font
	local ok, f = pcall(function()
		return (Enum.Font :: any)[name]
	end)
	return if ok and f then f else Enum.Font.GothamBold
end

return Plates
