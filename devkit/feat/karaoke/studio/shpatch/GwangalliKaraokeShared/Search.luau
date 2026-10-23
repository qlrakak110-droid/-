-- GwangalliKaraokeShared/Search: 노래책 search (제목 · 가수 · 초성 · 곡 번호).
--
--   Search.choseong("광안대교") -> "ㄱㅇㄷㄱ"
--   Search.find(Songs, query, limit?) -> { song }      best matches first
--   Search.match(song, query) -> number?               relevance (nil = no match)
-- A query character that is a bare consonant (ㄱ..ㅎ) matches any syllable with that initial, so
-- "ㄱㅇㄷㄱ", "광안ㄷ" and "치킨" all work. A query of digits matches the start of the 5-digit 곡번호.

local Search = {}

local CHO = { "ㄱ", "ㄲ", "ㄴ", "ㄷ", "ㄸ", "ㄹ", "ㅁ", "ㅂ", "ㅃ", "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅉ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ" }
local CHO_CP = {}
for i, c in CHO do
	CHO_CP[utf8.codepoint(c)] = i
end

local function isSyllable(cp: number): boolean
	return cp >= 0xAC00 and cp <= 0xD7A3
end

local function choIndex(cp: number): number?
	if isSyllable(cp) then
		return (cp - 0xAC00) // 588 + 1
	end
	return CHO_CP[cp]
end

local SKIP = {}
for _, c in { " ", "-", "·", ".", ",", "!", "?", "~", "'", '"', "(", ")", "&", "/", "♪", "〈", "〉" } do
	SKIP[utf8.codepoint(c)] = true
end

-- code points with spaces / punctuation removed and ASCII lowercased
local function cps(s: string): { number }
	local out = {}
	for _, cp in utf8.codes(s) do
		if SKIP[cp] then
			continue
		end
		if cp >= 65 and cp <= 90 then
			cp += 32
		end
		table.insert(out, cp)
	end
	return out
end

function Search.choseong(s: string): string
	local out = {}
	for _, cp in utf8.codes(s) do
		local k = choIndex(cp)
		if k and isSyllable(cp) then
			table.insert(out, CHO[k])
		elseif not SKIP[cp] then
			table.insert(out, utf8.char(cp))
		end
	end
	return table.concat(out)
end

local function charMatch(textCp: number, queryCp: number): boolean
	if textCp == queryCp then
		return true
	end
	local q = CHO_CP[queryCp]
	if q and isSyllable(textCp) then
		return choIndex(textCp) == q
	end
	return false
end

-- position (1-based) of query inside text, or nil
local function find(text: { number }, query: { number }): number?
	local n, m = #text, #query
	if m == 0 or m > n then
		return nil
	end
	for i = 1, n - m + 1 do
		local ok = true
		for j = 1, m do
			if not charMatch(text[i + j - 1], query[j]) then
				ok = false
				break
			end
		end
		if ok then
			return i
		end
	end
	return nil
end

local prepared: { [any]: any } = {}

local function prep(song: any): any
	local p = prepared[song]
	if p then
		return p
	end
	local lyric = {}
	for _, l in song.lines or {} do
		table.insert(lyric, l.t or "")
	end
	p = {
		title = cps(song.title or ""),
		artist = cps(song.artist or ""),
		genre = cps((song.genre or "") .. (song.style or "")),
		lyric = cps(table.concat(lyric, " ")),
		no = tostring(song.no or ""),
	}
	prepared[song] = p
	return p
end

function Search.match(song: any, query: string): number?
	if type(query) ~= "string" then
		return nil
	end
	local q = cps(query)
	if #q == 0 then
		return nil
	end
	local p = prep(song)
	local digits = string.match(query, "^%s*(%d+)%s*$")
	if digits then
		if string.sub(p.no, 1, #digits) == digits then
			return 100 - (#p.no - #digits)
		end
		-- "2호선" style titles that start with a digit
		local at = find(p.title, q)
		return if at then 60 else nil
	end
	local best: number? = nil
	local function consider(v: number)
		if not best or v > best then
			best = v
		end
	end
	local at = find(p.title, q)
	if at then
		consider(if at == 1 then 90 else 75)
	end
	at = find(p.artist, q)
	if at then
		consider(if at == 1 then 65 else 55)
	end
	if find(p.genre, q) then
		consider(40)
	end
	if #q >= 2 and find(p.lyric, q) then
		consider(25)
	end
	return best
end

function Search.find(Songs: any, query: string, limit: number?): { any }
	local hits = {}
	for _, s in Songs.LIST do
		local m = Search.match(s, query)
		if m then
			table.insert(hits, { s = s, m = m })
		end
	end
	table.sort(hits, function(a, b)
		if a.m ~= b.m then
			return a.m > b.m
		end
		return a.s.no < b.s.no
	end)
	local out = {}
	for i, h in hits do
		if limit and i > limit then
			break
		end
		out[i] = h.s
	end
	return out
end

return Search
