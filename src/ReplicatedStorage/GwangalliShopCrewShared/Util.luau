-- GwangalliShopCrewShared/Util: small pure helpers (no instances, no services).
--   Util.hash(s) -> 32-bit FNV-1a        Util.hash6(s) -> 6 base-36 chars     Util.rng(seed) -> () -> [0, 1)
--   Util.pick(list, r | seed)            Util.dayKey(t?) -> "20261016" (KST)   Util.won(n) -> "9,500원"
--   Util.josa(word, form) -> word + particle  (form: 이 을 은 과 으로 이에요 이랑 아 이요 이나 — the batchim decides)
--   Util.fill(text, vars) -> text         "{item|이} 나왔어요" -> "돼지국밥이 나왔어요"; "{n}번" -> "3번"
--   Util.yaw(dx, dz) -> degrees (NPC contract: CFrame.Angles(0, rad(yaw), 0) faces (dx, dz))
--   Util.compass(dx, dz) -> "북동쪽" (north = -Z)   Util.meters(studs) -> "약 120m"   Util.partOfDay(clock)
--   Util.encodeCarry(list) / Util.decodeCarry(s)   ("dish|menu|item|qty;..." / "water" / "empty" ...)

local Util = {}

local function mul32(a: number, b: number): number
	local aLo, aHi = a % 65536, a // 65536
	local bLo, bHi = b % 65536, b // 65536
	return ((aHi * bLo + aLo * bHi) % 65536 * 65536 + aLo * bLo) % 4294967296
end

function Util.hash(s: string): number
	local h = 2166136261
	for i = 1, #s do
		h = bit32.bxor(h, string.byte(s, i))
		h = mul32(h, 16777619)
	end
	return h
end

local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
function Util.hash6(s: string): string
	local h = Util.hash(s)
	local out = {}
	for _ = 1, 6 do
		local d = h % 36
		h = h // 36
		table.insert(out, string.sub(B36, d + 1, d + 1))
	end
	return table.concat(out)
end

function Util.rng(seed: any): () -> number
	local s: number
	if type(seed) == "number" then
		s = math.floor(math.abs(seed)) % 4294967296
	else
		s = Util.hash(tostring(seed))
	end
	if s == 0 then
		s = 0x9E3779B9
	end
	return function(): number
		s = bit32.bxor(s, bit32.lshift(s, 13))
		s = bit32.bxor(s, bit32.rshift(s, 17))
		s = bit32.bxor(s, bit32.lshift(s, 5))
		return (s % 1000003) / 1000003
	end
end

function Util.pick(list: { any }, r: any): any
	if #list == 0 then
		return nil
	end
	local x: number
	if type(r) == "function" then
		x = r()
	elseif type(r) == "number" then
		x = (math.abs(r) % 1000003) / 1000003
	else
		x = math.random()
	end
	return list[1 + math.floor(x * #list) % #list]
end

-- KST calendar day (UTC+9, no DST)
function Util.dayKey(t: number?): string
	return os.date("!%Y%m%d", math.floor((t or os.time()) + 9 * 3600)) :: string
end

function Util.won(n: any): string
	local v = math.floor(tonumber(n) or 0)
	local neg = v < 0
	local s = tostring(math.abs(v))
	local out = s
	while true do
		local k
		out, k = string.gsub(out, "^(%d+)(%d%d%d)", "%1,%2")
		if k == 0 then
			break
		end
	end
	return (if neg then "-" else "") .. out .. "원"
end

-------------------------------------------------------------------------------------------------
-- Korean particles
-------------------------------------------------------------------------------------------------
-- 0 = no final consonant, 1 = final consonant, 2 = ㄹ (으로 -> 로)
local DIGIT = { ["0"] = 1, ["1"] = 2, ["2"] = 0, ["3"] = 1, ["4"] = 0, ["5"] = 0, ["6"] = 1, ["7"] = 2, ["8"] = 2, ["9"] = 0 }
local LATIN = { b = 1, c = 1, k = 1, l = 2, m = 1, n = 1, p = 1, t = 1, g = 1 }

local function finalOf(word: string): number
	local cps = {}
	for _, cp in utf8.codes(word) do
		table.insert(cps, cp)
	end
	for i = #cps, 1, -1 do
		local cp = cps[i]
		if cp >= 0xAC00 and cp <= 0xD7A3 then
			local jong = (cp - 0xAC00) % 28
			if jong == 0 then
				return 0
			end
			return if jong == 8 then 2 else 1
		elseif cp >= 48 and cp <= 57 then
			return DIGIT[string.char(cp)] or 0
		elseif (cp >= 65 and cp <= 90) or (cp >= 97 and cp <= 122) then
			return LATIN[string.lower(string.char(cp))] or 0
		end
		-- spaces, brackets, emoji, punctuation: look further left
	end
	return 0
end
Util.finalOf = finalOf

local FORMS: { [string]: { string } } = {
	["이"] = { "이", "가" },
	["가"] = { "이", "가" },
	["을"] = { "을", "를" },
	["를"] = { "을", "를" },
	["은"] = { "은", "는" },
	["는"] = { "은", "는" },
	["과"] = { "과", "와" },
	["와"] = { "과", "와" },
	["으로"] = { "으로", "로" },
	["로"] = { "으로", "로" },
	["이에요"] = { "이에요", "예요" },
	["예요"] = { "이에요", "예요" },
	["이랑"] = { "이랑", "랑" },
	["랑"] = { "이랑", "랑" },
	["아"] = { "아", "야" },
	["야"] = { "아", "야" },
	["이요"] = { "이요", "요" },
	["요"] = { "이요", "요" },
	["이나"] = { "이나", "나" },
	["나"] = { "이나", "나" },
}

function Util.josa(word: string, form: string): string
	local pair = FORMS[form]
	if not pair then
		return word .. form
	end
	local f = finalOf(word)
	if pair[1] == "으로" then
		return word .. (if f == 1 then "으로" else "로")
	end
	return word .. (if f ~= 0 then pair[1] else pair[2])
end

-- "{key}" / "{key|이}" placeholders; unknown keys are left as they are (the lint test catches them)
function Util.fill(text: string, vars: { [string]: any }?): string
	local v = vars or {}
	return (string.gsub(text, "{([%w_]+)|?([^}]*)}", function(key: string, form: string)
		local val = v[key]
		if val == nil then
			return nil
		end
		local s = tostring(val)
		if form ~= "" then
			return Util.josa(s, form)
		end
		return s
	end))
end

-------------------------------------------------------------------------------------------------
-- geometry words
-------------------------------------------------------------------------------------------------
function Util.yaw(dx: number, dz: number): number
	return math.deg(math.atan2(-dx, -dz))
end

local COMPASS = { "북쪽", "북동쪽", "동쪽", "남동쪽", "남쪽", "남서쪽", "서쪽", "북서쪽" }
function Util.compass(dx: number, dz: number): string
	local a = math.deg(math.atan2(dx, -dz)) -- 0 = north (-Z), 90 = east (+X)
	local i = math.floor(((a % 360) + 22.5) / 45) % 8
	return COMPASS[i + 1]
end

function Util.meters(studs: number): string
	local m = studs * 0.28
	if m < 15 then
		return "바로 근처"
	elseif m < 100 then
		return string.format("약 %dm", math.floor(m / 5 + 0.5) * 5)
	elseif m < 1000 then
		return string.format("약 %dm", math.floor(m / 10 + 0.5) * 10)
	end
	return string.format("약 %.1fkm", m / 1000)
end

function Util.walkMinutes(studs: number): number
	return math.max(1, math.floor(studs * 0.28 / 75 + 0.5)) -- ~4.5 km/h
end

function Util.partOfDay(clock: number): string
	local c = clock % 24
	if c < 5 then
		return "dawn"
	elseif c < 11 then
		return "morning"
	elseif c < 14 then
		return "lunch"
	elseif c < 17 then
		return "afternoon"
	elseif c < 21 then
		return "evening"
	end
	return "night"
end

-------------------------------------------------------------------------------------------------
-- CrewCarry
-------------------------------------------------------------------------------------------------
-- list = { { kind = "dish", menu, item, qty } | { kind = "water" } ... } -> attribute string (<= 200 chars)
function Util.encodeCarry(list: { any }?): string
	if not list or #list == 0 then
		return ""
	end
	local out = {}
	for i, c in list do
		if i > 4 then
			break
		end
		if c.kind == "dish" then
			table.insert(out, string.format("dish|%s|%s|%d", tostring(c.menu or ""), tostring(c.item or ""), math.clamp(math.floor(tonumber(c.qty) or 1), 1, 6)))
		elseif type(c.kind) == "string" then
			table.insert(out, c.kind)
		end
	end
	local s = table.concat(out, ";")
	if #s > 200 then
		s = string.sub(s, 1, 200)
	end
	return s
end

function Util.decodeCarry(s: any): { any }
	local out = {}
	if type(s) ~= "string" or s == "" then
		return out
	end
	for _, part in string.split(s, ";") do
		local f = string.split(part, "|")
		if f[1] == "dish" then
			table.insert(out, { kind = "dish", menu = f[2] or "", item = f[3] or "", qty = math.clamp(tonumber(f[4]) or 1, 1, 6) })
		elseif f[1] ~= "" then
			table.insert(out, { kind = f[1] })
		end
	end
	return out
end

-- shallow clean of a string coming from a client: trimmed, length-capped, printable
function Util.cleanString(s: any, maxLen: number): string?
	if type(s) ~= "string" then
		return nil
	end
	if #s == 0 or #s > maxLen then
		return nil
	end
	if string.find(s, "[%c]") then
		return nil
	end
	return s
end

return Util
