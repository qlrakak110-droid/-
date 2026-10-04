--!strict
-- WordRules: the pure rules of 끝말잇기 (shared: the server judges, the client shows the "차___" hint
-- and rejects obviously bad input before sending it).
--   WR.normalize(text) -> string        trims and removes every space ("자 동 차" -> "자동차")
--   WR.syllables(word) -> {codepoint}?  nil unless every character is a Hangul syllable (가..힣)
--   WR.shape(word) -> ok, reason?      2..MAX syllables of Hangul
--   WR.starts(prevWord) -> {string}     syllables the next word may start with (last syllable and its
--                                        두음법칙 form: 력 -> 역, 료 -> 요, 라 -> 나, 녀 -> 여 ...)
--   WR.follows(prev, nextWord) -> bool
--   WR.first(word) / WR.last(word) -> string

local WR = {}

WR.MIN = 2
WR.MAX = 8
WR.TURN_TIME = 10 -- seconds per answer

local BASE = 0xAC00
local LAST = 0xD7A3

local function decompose(cp: number): (number, number, number)
	local s = cp - BASE
	local jong = s % 28
	local jung = (s // 28) % 21
	local cho = s // (28 * 21)
	return cho, jung, jong
end

local function compose(cho: number, jung: number, jong: number): number
	return BASE + (cho * 21 + jung) * 28 + jong
end

local CHO_N, CHO_R, CHO_O = 2, 5, 11
-- ㄹ before ㅑ ㅒ ㅕ ㅖ ㅛ ㅠ ㅣ -> ㅇ ; ㄹ before ㅏ ㅐ ㅗ ㅚ ㅜ ㅡ -> ㄴ ; ㄴ before ㅕ ㅖ ㅛ ㅠ ㅣ -> ㅇ
local R_TO_O = { [2] = true, [3] = true, [6] = true, [7] = true, [12] = true, [17] = true, [20] = true }
local R_TO_N = { [0] = true, [1] = true, [8] = true, [11] = true, [13] = true, [18] = true }
local N_TO_O = { [6] = true, [7] = true, [12] = true, [17] = true, [20] = true }

-- 두음법칙 form of a syllable, or nil when the rule does not change it.
function WR.dueum(cp: number): number?
	if cp < BASE or cp > LAST then
		return nil
	end
	local cho, jung, jong = decompose(cp)
	if cho == CHO_R then
		if R_TO_O[jung] then
			return compose(CHO_O, jung, jong)
		elseif R_TO_N[jung] then
			return compose(CHO_N, jung, jong)
		end
	elseif cho == CHO_N and N_TO_O[jung] then
		return compose(CHO_O, jung, jong)
	end
	return nil
end

function WR.normalize(text: any): string
	if type(text) ~= "string" then
		return ""
	end
	local s = string.gsub(text, "%s+", "")
	return s
end

function WR.syllables(word: string): { number }?
	if type(word) ~= "string" or word == "" or #word > 64 then
		return nil
	end
	local ok, list = pcall(function()
		local out = {}
		for _, cp in utf8.codes(word) do
			if cp < BASE or cp > LAST then
				error("not hangul")
			end
			table.insert(out, cp)
		end
		return out
	end)
	if not ok then
		return nil
	end
	return list
end

function WR.shape(word: string): (boolean, string?)
	local s = WR.syllables(word)
	if not s then
		return false, "한글 단어만 쓸 수 있어요"
	end
	if #s < WR.MIN then
		return false, "두 글자 이상 단어만 돼요"
	end
	if #s > WR.MAX then
		return false, "너무 긴 단어예요"
	end
	return true, nil
end

function WR.first(word: string): string
	local s = WR.syllables(word)
	return if s and #s > 0 then utf8.char(s[1]) else ""
end

function WR.last(word: string): string
	local s = WR.syllables(word)
	return if s and #s > 0 then utf8.char(s[#s]) else ""
end

function WR.starts(prev: string): { string }
	local s = WR.syllables(prev)
	if not s or #s == 0 then
		return {}
	end
	local lastCp = s[#s]
	local out = { utf8.char(lastCp) }
	local alt = WR.dueum(lastCp)
	if alt then
		table.insert(out, utf8.char(alt))
	end
	return out
end

function WR.follows(prev: string, nextWord: string): boolean
	local f = WR.first(nextWord)
	if f == "" then
		return false
	end
	for _, st in WR.starts(prev) do
		if st == f then
			return true
		end
	end
	return false
end

-- "차" or "력(역)" for the hint line.
function WR.hint(prev: string): string
	local st = WR.starts(prev)
	if #st == 0 then
		return ""
	elseif #st == 1 then
		return st[1]
	end
	return st[1] .. "(" .. st[2] .. ")"
end

return WR
