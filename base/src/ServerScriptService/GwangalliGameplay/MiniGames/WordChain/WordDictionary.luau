--!strict
-- WordChain/WordDictionary: the 끝말잇기 dictionary service (server only).
--
-- Sources (providers), checked in order; a word is valid when any source knows it:
--   1. "builtin"   WordList.luau (common nouns, family friendly) - always on, indexed in memory.
--   2. "datastore" extra words from DataStore D.EXTRA_STORE (key "words": one space-separated string,
--                  written by an admin tool or the live-ops pipeline) - merged into the index at start
--                  (pcall: silently skipped in Studio / unpublished places).
--   3. registered providers: D.registerProvider({ name, has = function(word) -> boolean? }) for an
--                  external dictionary (e.g. an HTTP proxy in front of 국립국어원 표준국어대사전 Open API,
--                  see D.httpProvider below - disabled unless D.HTTP_URL is set). A provider may yield;
--                  answers are cached (D.CACHE_TTL) and a provider error counts as "unknown".
-- NPC answers only come from the in-memory index (fast, never yields).
-- Inappropriate words: D.BLOCK (local list) here, plus Roblox text filtering in WordChainServer.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local D = {}

D.EXTRA_STORE = "GwangalliWordList_v1"
D.HTTP_URL = "" -- e.g. "https://your-proxy.example/dict?word=%s" returning {"exists": true}; "" = off
D.CACHE_TTL = 3600

local WR: any = nil
local words: { [string]: boolean } = {}
local byFirst: { [string]: { string } } = {}
local count = 0
local providers: { { name: string, has: (string) -> boolean? } } = {}
local cache: { [string]: { ok: boolean, t: number } } = {}

-- words never accepted even if a provider knows them (insults etc.; the Roblox filter catches the rest)
D.BLOCK = {}
for _, w in string.split("바보 멍청이 병신 새끼 개새끼 씨발 존나 닥쳐 꺼져 죽어 자살 살인 마약 도박 섹스 야동", " ") do
	D.BLOCK[w] = true
end

local function add(w: string): boolean
	if words[w] or D.BLOCK[w] then
		return false
	end
	local ok = WR.shape(w)
	if not ok then
		return false
	end
	words[w] = true
	count += 1
	local f = WR.first(w)
	local list = byFirst[f]
	if not list then
		list = {}
		byFirst[f] = list
	end
	table.insert(list, w)
	return true
end

-- Adds words from a whitespace-separated string or a list. Returns how many were new.
function D.addWords(src: any): number
	local n = 0
	if type(src) == "string" then
		for w in string.gmatch(src, "%S+") do
			if add(w) then
				n += 1
			end
		end
	elseif type(src) == "table" then
		for _, w in src do
			if type(w) == "string" and add(w) then
				n += 1
			end
		end
	end
	return n
end

function D.init(wr: any, listModule: ModuleScript?)
	WR = wr
	if listModule then
		local ok, src = pcall(require, listModule)
		if ok then
			D.addWords(src)
		else
			warn("[MiniGames] WordList failed to load: " .. tostring(src))
		end
	end
	task.spawn(function()
		local ok, extra = pcall(function()
			return DataStoreService:GetDataStore(D.EXTRA_STORE):GetAsync("words")
		end)
		if ok and type(extra) == "string" then
			local n = D.addWords(extra)
			if n > 0 then
				print("[MiniGames] word list: +" .. n .. " words from DataStore")
			end
		end
	end)
	if D.HTTP_URL ~= "" then
		D.registerProvider(D.httpProvider(D.HTTP_URL))
	end
end

function D.count(): number
	return count
end

function D.registerProvider(p: { name: string, has: (string) -> boolean? })
	table.insert(providers, p)
end

-- Known locally (no yield)?
function D.hasLocal(w: string): boolean
	return words[w] == true
end

-- Valid word? May yield when an external provider is registered.
function D.has(w: string): boolean
	if D.BLOCK[w] then
		return false
	end
	if words[w] then
		return true
	end
	if #providers == 0 then
		return false
	end
	local c = cache[w]
	if c and os.clock() - c.t < D.CACHE_TTL then
		return c.ok
	end
	local found = false
	for _, p in providers do
		local ok, res = pcall(p.has, w)
		if ok and res == true then
			found = true
			break
		end
	end
	cache[w] = { ok = found, t = os.clock() }
	if found then
		add(w) -- NPCs may use it from now on
	end
	return found
end

-- Words starting with any of the syllables (the 두음법칙 alternatives of WordRules.starts).
function D.starting(syllables: { string }): { string }
	local out = {}
	for _, s in syllables do
		local list = byFirst[s]
		if list then
			for _, w in list do
				table.insert(out, w)
			end
		end
	end
	return out
end

-- How many words can follow `w` (few = a strong "한방" word).
function D.followers(w: string): number
	local n = 0
	for _, s in WR.starts(w) do
		local list = byFirst[s]
		if list then
			n += #list
		end
	end
	return n
end

-- A friendly first word: 2-3 syllables with many followers.
function D.startWord(rng: Random): string
	local pool = { "바다", "광안리", "파도", "모래", "갈매기", "등대", "자동차", "기차", "사과", "나무", "하늘", "구름", "축제", "산책", "여름" }
	for _ = 1, 20 do
		local w = pool[rng:NextInteger(1, #pool)]
		if words[w] and D.followers(w) >= 5 then
			return w
		end
	end
	for w in words do
		if D.followers(w) >= 8 then
			return w
		end
	end
	return "바다"
end

-- Optional HTTP provider. The endpoint must answer JSON {"exists": true|false}. Requires
-- HttpService.HttpEnabled and a server-side proxy that holds the dictionary API key (never put a
-- key in a ModuleScript clients can see - this file is server-only).
function D.httpProvider(urlPattern: string): { name: string, has: (string) -> boolean? }
	return {
		name = "http",
		has = function(w: string): boolean?
			local url = string.format(urlPattern, HttpService:UrlEncode(w))
			local body = HttpService:GetAsync(url, true)
			local data = HttpService:JSONDecode(body)
			return type(data) == "table" and data.exists == true
		end,
	}
end

return D
