-- GwangalliCarDealerShared/Util: pure helpers shared by the dealer server and client — won / 만원
-- formatting, number guards, a token-bucket rate limiter, stable string hashing and remote-input checks.

local U = {}

function U.finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function U.round100(v: number): number
	return math.floor(v / 100 + 0.5) * 100
end

function U.comma(n: any): string
	local v = math.floor(tonumber(n) or 0)
	local s = tostring(math.abs(v))
	local out = ""
	while #s > 3 do
		out = "," .. string.sub(s, -3) .. out
		s = string.sub(s, 1, -4)
	end
	return (if v < 0 then "-" else "") .. s .. out
end

-- "1,234,000원"
function U.won(n: any): string
	return U.comma(n) .. "원"
end

-- Korean money in 만 / 억 units: 780000 -> "78만원", 23700 -> "2만 3,700원", 125000000 -> "1억 2,500만원",
-- 9500 -> "9,500원".
function U.man(n: any): string
	local v = math.floor(tonumber(n) or 0)
	local neg = v < 0
	v = math.abs(v)
	local parts = {}
	local eok = v // 100000000
	local manPart = (v % 100000000) // 10000
	local rest = v % 10000
	if eok > 0 then
		table.insert(parts, U.comma(eok) .. "억")
	end
	if manPart > 0 then
		table.insert(parts, U.comma(manPart) .. "만")
	end
	if rest > 0 or #parts == 0 then
		table.insert(parts, U.comma(rest))
	end
	return (if neg then "-" else "") .. table.concat(parts, " ") .. "원"
end

-- Short 만원 label for cards: 780000 -> "78", unit "만원"; 23700 -> "2.4", "만원"; 9500 -> "9,500", "원"
function U.manShort(n: any): (string, string)
	local v = math.floor(tonumber(n) or 0)
	if math.abs(v) < 10000 then
		return U.comma(v), "원"
	end
	local m = v / 10000
	if math.abs(m - math.floor(m + 0.5)) < 0.05 then
		return U.comma(math.floor(m + 0.5)), "만원"
	end
	return string.format("%.1f", m), "만원"
end

function U.pct(rate: number): string
	return string.format("%d%%", math.floor(rate * 100 + 0.5))
end

function U.secs(s: number): string
	s = math.max(0, math.floor(s + 0.5))
	if s < 60 then
		return string.format("%d초", s)
	end
	return string.format("%d분 %02d초", s // 60, s % 60)
end

function U.meters(m: number): string
	if m >= 1000 then
		return string.format("%.1fkm", m / 1000)
	end
	return string.format("%dm", math.floor(m + 0.5))
end

-- djb2 (stable across server / client)
function U.hash(s: string): number
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + string.byte(s, i)) % 2147483647
	end
	return h
end

-- Token bucket keyed by anything (players). take(key) -> true when allowed.
local Bucket = {}
Bucket.__index = Bucket
function U.bucket(perSecond: number, burst: number): any
	return setmetatable({ rate = perSecond, burst = burst, t = {}, clock = os.clock }, Bucket)
end
function Bucket:take(key: any, cost: number?): boolean
	local now = self.clock()
	local s = self.t[key]
	if not s then
		s = { n = self.burst, at = now }
		self.t[key] = s
	end
	s.n = math.min(self.burst, s.n + (now - s.at) * self.rate)
	s.at = now
	local c = cost or 1
	if s.n < c then
		return false
	end
	s.n -= c
	return true
end
function Bucket:drop(key: any)
	self.t[key] = nil
end

-- Per-key per-op cooldowns. ready(key, op, seconds) -> true (and arms it) when allowed.
local Cool = {}
Cool.__index = Cool
function U.cooldowns(): any
	return setmetatable({ t = {}, clock = os.clock }, Cool)
end
function Cool:ready(key: any, op: string, seconds: number): boolean
	local now = self.clock()
	local m = self.t[key]
	if not m then
		m = {}
		self.t[key] = m
	end
	local last = m[op]
	if last and now - last < seconds then
		return false
	end
	m[op] = now
	return true
end
function Cool:left(key: any, op: string, seconds: number): number
	local m = self.t[key]
	local last = m and m[op]
	if not last then
		return 0
	end
	return math.max(0, seconds - (self.clock() - last))
end
function Cool:drop(key: any)
	self.t[key] = nil
end

-- Remote input checks -------------------------------------------------------------------------------
function U.str(v: any, maxLen: number, pattern: string?): string?
	if type(v) ~= "string" or #v == 0 or #v > maxLen then
		return nil
	end
	if pattern and not string.match(v, pattern) then
		return nil
	end
	return v
end

function U.bool(v: any): boolean
	return v == true
end

-- A payload table with at most `maxKeys` string keys and no nested tables deeper than `depth`.
function U.payload(v: any, maxKeys: number): { [string]: any }?
	if v == nil then
		return {}
	end
	if type(v) ~= "table" then
		return nil
	end
	local n = 0
	for k, x in v do
		n += 1
		if n > maxKeys or type(k) ~= "string" or #k > 16 then
			return nil
		end
		local tx = type(x)
		if tx == "table" or tx == "function" or tx == "thread" or tx == "userdata" then
			return nil
		end
		if tx == "number" and not U.finite(x) then
			return nil
		end
		if tx == "string" and #x > 64 then
			return nil
		end
	end
	return v
end

-- Korean particles after a word: does it end in a final consonant (받침)? -> hasBatchim, isRieul
local DIGIT_BATCHIM = { ["0"] = 1, ["1"] = 2, ["3"] = 1, ["6"] = 1, ["7"] = 2, ["8"] = 2 } -- 1 = 받침, 2 = ㄹ
local LATIN_BATCHIM = { l = 2, m = 1, n = 1, r = 2 }
function U.batchim(word: string): (boolean, boolean)
	local cps = {}
	for _, cp in utf8.codes(word) do
		table.insert(cps, cp)
	end
	for i = #cps, 1, -1 do
		local cp = cps[i]
		if cp >= 0xAC00 and cp <= 0xD7A3 then
			local jong = (cp - 0xAC00) % 28
			return jong ~= 0, jong == 8
		elseif cp >= 48 and cp <= 57 then
			local b = DIGIT_BATCHIM[string.char(cp)]
			return b ~= nil, b == 2
		elseif (cp >= 65 and cp <= 90) or (cp >= 97 and cp <= 122) then
			local b = LATIN_BATCHIM[string.lower(string.char(cp))]
			return b ~= nil, b == 2
		end
		-- spaces, brackets, emoji: look further left
	end
	return false, false
end

local JOSA = {
	["이"] = { "이", "가" },
	["을"] = { "을", "를" },
	["은"] = { "은", "는" },
	["과"] = { "과", "와" },
	["이에요"] = { "이에요", "예요" },
	["이다"] = { "이다", "다" },
	["이야"] = { "이야", "야" },
}

-- word + the right particle: U.josa("미드 세단", "이") -> "미드 세단이"
function U.josa(word: string, mark: string): string
	local b, rieul = U.batchim(word)
	if mark == "으로" then
		return word .. (if b and not rieul then "으로" else "로")
	end
	local pair = JOSA[mark]
	if not pair then
		return word .. mark
	end
	return word .. (if b then pair[1] else pair[2])
end

-- "{car:이} 좋아요" -> "미드 세단이 좋아요"; plain {name} placeholders too.
function U.fmt(s: string, vars: { [string]: any }?): string
	if not vars then
		return s
	end
	return (string.gsub(s, "{(%w+):?([^}]*)}", function(k, mark)
		local v = vars[k]
		if v == nil then
			return "{" .. k .. (if mark ~= "" then ":" .. mark else "") .. "}"
		end
		local txt = tostring(v)
		if mark ~= "" then
			return U.josa(txt, mark)
		end
		return txt
	end))
end

return U
