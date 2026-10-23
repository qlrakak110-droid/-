--!nocheck
-- t_shared.luau: Lines lint, Personas coverage / determinism, NavGrid basics, Util particles, Menus sanity
local B = require("./mods")
local req = B.req
local Shared = req("CS_init")
local Lines, Personas, NavGrid, Util, Menus, SS = Shared.Lines, Shared.Personas, Shared.NavGrid, Shared.Util, Shared.Menus, req("SS")
local fails = 0
local function fail(...) fails += 1 print("FAIL", ...) end
-- Lines
local FORBID = { "술집", "술 한", "술을", "술이 ", "소주", "맥주", "취해", "취했", "한잔", "한 잔 하", "건배", "막걸리", "와인", "위스키", "칵테일", "하이볼", "사케" }
local known = {}
for _, v in Lines.VARS do known[v] = true end
local function lint(where, s)
	if type(s) ~= "string" or s == "" then fail("empty", where) return end
	if not string.find(s, "[\234-\237]") then fail("not korean", where, s) end
	for _, w in FORBID do
		if string.find(s, w, 1, true) and not string.find(s, "무알콜", 1, true) and not string.find(s, "물 한 잔", 1, true) and not string.find(s, "물 한잔", 1, true) then fail("alcohol word", w, where, s) end
	end
	for key in string.gmatch(s, "{([%w_]+)[|}]") do
		if not known[key] then fail("unknown placeholder", key, where) end
	end
	local _, opens = string.gsub(s, "{", "")
	local _, closes = string.gsub(s, "}", "")
	if opens ~= closes then fail("brace mismatch", where, s) end
end
local n = 0
local function walk(where, e)
	if type(e) == "string" then n += 1 lint(where, e) return end
	if type(e) == "table" then for k, v in e do walk(where .. "." .. tostring(k), v) end end
end
walk("BANK", Lines.BANK)
walk("TYPE", Lines.TYPE)
print("lines", n)
-- every key used in code exists
local used = {}
for _, k in require("./usedkeys") do used[k] = true end
local nu = 0
for k in used do nu += 1 if not Lines.has(k) then fail("missing line key", k) end end
print("keys used", nu)
-- fill + josa
assert(Util.fill("{item|이} 나왔어요", { item = "돼지국밥" }) == "돼지국밥이 나왔어요", Util.fill("{item|이} 나왔어요", { item = "돼지국밥" }))
assert(Util.fill("{item|이} 나왔어요", { item = "라떼" }) == "라떼가 나왔어요")
assert(Util.fill("{item|으로} 주세요", { item = "물" }) == "물로 주세요")
assert(Util.fill("{place|은} 여기", { place = "광안리해수욕장 (중앙)" }) == "광안리해수욕장 (중앙)은 여기")
-- every line with vars resolves
for _, key in Lines.KEYS do
	for _, d in { "std", "busan" } do
		for _, t in { "soup", "cafe", "pub" } do
			local s = Lines.get(key, { dialect = d, type = t, vars = { item = "돼지국밥", n = "007", name = "민수", fav = "밀면", shop = "가게", price = "9,000원", desc = "진한 국물", table = 3, place = "광안리", dir = "북쪽", dist = "약 120m", mins = 2, level = 2, title = "단골", total = "9,000원", count = 2, stamps = 3, amount = "1,000원", menu = "\n• 국밥" } })
			if not s or string.find(s, "{", 1, true) then fail("unresolved", key, d, t, s) end
		end
	end
end
-- Personas
for t in SS.TYPES do
	local r = Personas.roster(t, { tables = 5, flow = SS.TYPES[t].flow, staffed = false })
	local a = Personas.make("x@1,2", t, r[1] or { role = "cook", title = "t" })
	local b = Personas.make("x@1,2", t, r[1] or { role = "cook", title = "t" })
	if a.full ~= b.full then fail("persona not deterministic", t) end
end
local cnt = 0
for _, t in Personas.TYPES do if not SS.TYPES[t] then fail("persona type unknown", t) end cnt += 1 end
print("persona types", cnt)
-- NavGrid
local g = NavGrid.new(-10, -10, 10, 10, 0.5)
g:block(-1, -8, 1, 8)
g:finalize()
local p = g:path(-5, 0, 5, 0)
assert(p and #p >= 3, "path around wall")
for i = 2, #p do assert(g:los(p[i - 1][1], p[i - 1][2], p[i][1], p[i][2]), "segment los") end
assert(g:comp(-5, 0) == g:comp(5, 0))
g:block(-1, -10, 1, 10)
g:finalize()
assert(g:path(-5, 0, 5, 0) == nil, "split grid")
local x, z = g:nearestFree(0, 0, 3)
assert(x and math.abs(x) > 1, "nearest free")
-- Menus
for kind, list in Menus.LISTS do
	for _, it in list do
		if type(it.price) ~= "number" or it.price <= 0 then fail("menu price", kind, it.id) end
		lint("menu " .. kind, it.name)
		if not string.match(it.id, "^[%w_]+$") or #("togo_" .. it.id) > 24 then fail("menu id", it.id) end
	end
end
print(if fails == 0 then "ALL OK" else ("FAILS " .. fails))
