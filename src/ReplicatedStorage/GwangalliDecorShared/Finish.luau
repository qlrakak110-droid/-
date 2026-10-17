--!strict
-- GwangalliDecorShared/Finish: 벽지 · 바닥 · 조명 마감재 of the 자유 배치 add-on (pure data + pricing).
-- Applied per room on the life-game home's own wall / floor parts (the same Room + Surface parts the
-- host's 🛠️ 인테리어 themes use; the host's theme for that room and kind is cleared when the player
-- picks a host theme again, see Config.CLEAR_ON_HOST_THEME). Patterns are drawn by the client as
-- SurfaceGuis in PlayerGui (Adornee = the wall part); colour + material replicate from the server.
--   Finish.WALLS / WALL_ORDER    { id = { name, desc, mat, a (rgb), b (rgb)?, pattern, price, decor } }
--   Finish.FLOORS / FLOOR_ORDER  same shape
--   Finish.LIGHTS / LIGHT_ORDER  home-wide lighting presets (따뜻한 · 주광 · 무드 · 네온 · 파티)
--   Finish.price(kind, id, tierKey, room) / Finish.sanitize(raw) / Finish.decor(finish)

local Finish = {}

Finish.TIER_MULT = { goshiwon = 1, oneroom = 1.4, officetel = 2, apartment = 2.8, penthouse = 4 }
Finish.ROOM_FACTOR = { entry = 0.5, bath = 0.6, master_bath = 0.6, dress = 0.6, veranda = 0.6, powder = 0.5, wine = 0.6, loft = 0.8, study = 0.8, dining = 0.9 }

-- pattern = how the client draws over the painted part:
--   solid · stripe · pinstripe · check · dot · wainscot · subway · gradient · mural · herringbone · checker · terrazzo · plank
Finish.WALL_ORDER = {
	"paint", "silk", "stripe", "pinstripe", "check", "dot", "wainscot", "subway", "gradient",
	"brick", "concrete", "woodpanel", "marble", "mural",
}
Finish.WALLS = {
	paint = { name = "무광 페인트", desc = "원하는 색으로 칠하는 기본 페인트", mat = "plaster", a = { 236, 232, 224 }, pattern = "solid", price = 40000, decor = 1 },
	silk = { name = "실크 벽지", desc = "은은한 광택의 실크벽지", mat = "fabric", a = { 242, 238, 230 }, pattern = "solid", price = 60000, decor = 2 },
	stripe = { name = "와이드 스트라이프", desc = "두 가지 색의 굵은 줄무늬", mat = "plaster", a = { 214, 226, 236 }, b = { 246, 246, 244 }, pattern = "stripe", price = 90000, decor = 3 },
	pinstripe = { name = "핀 스트라이프", desc = "가는 세로줄 포인트 벽지", mat = "plaster", a = { 236, 232, 224 }, b = { 176, 150, 120 }, pattern = "pinstripe", price = 90000, decor = 3 },
	check = { name = "깅엄 체크", desc = "포근한 체크무늬 (키즈룸 · 주방)", mat = "fabric", a = { 246, 240, 232 }, b = { 220, 160, 150 }, pattern = "check", price = 110000, decor = 3 },
	dot = { name = "폴카 도트", desc = "동글동글 도트 벽지", mat = "plaster", a = { 250, 240, 222 }, b = { 240, 176, 196 }, pattern = "dot", price = 110000, decor = 3 },
	wainscot = { name = "웨인스코팅", desc = "아래쪽 몰딩 패널 + 투톤", mat = "plaster", a = { 232, 228, 220 }, b = { 52, 70, 98 }, pattern = "wainscot", price = 180000, decor = 5 },
	subway = { name = "서브웨이 타일", desc = "주방 · 욕실에 어울리는 벽돌쌓기 타일", mat = "ceramic", a = { 246, 246, 244 }, b = { 200, 200, 196 }, pattern = "subway", price = 160000, decor = 4 },
	gradient = { name = "선셋 그라데이션", desc = "광안리 노을처럼 번지는 색", mat = "plaster", a = { 255, 180, 140 }, b = { 120, 110, 200 }, pattern = "gradient", price = 150000, decor = 4 },
	brick = { name = "붉은 벽돌", desc = "카페 같은 빈티지 벽돌", mat = "brick", a = { 168, 92, 70 }, pattern = "solid", price = 220000, decor = 5 },
	concrete = { name = "노출 콘크리트", desc = "인더스트리얼 무드", mat = "concrete", a = { 170, 170, 166 }, pattern = "solid", price = 200000, decor = 4 },
	woodpanel = { name = "우드 패널", desc = "호텔 스위트 같은 목재 패널", mat = "planks", a = { 120, 86, 60 }, pattern = "solid", price = 260000, decor = 6 },
	marble = { name = "대리석 월", desc = "카라라 대리석 아트월", mat = "marble", a = { 236, 236, 232 }, pattern = "solid", price = 380000, decor = 8 },
	mural = { name = "광안대교 야경 벽화", desc = "밤바다 위 광안대교 LED", mat = "plaster", a = { 22, 26, 64 }, b = { 61, 214, 245 }, pattern = "mural", price = 450000, decor = 9 },
}

Finish.FLOOR_ORDER = { "oak", "walnut", "herringbone", "jangpan", "marble", "porcelain", "checker", "terrazzo", "carpet", "concrete", "slate" }
Finish.FLOORS = {
	oak = { name = "오크 강마루", desc = "밝은 원목 마루", mat = "planks", a = { 196, 160, 114 }, pattern = "solid", price = 120000, decor = 2 },
	walnut = { name = "월넛 강마루", desc = "짙고 고급스러운 월넛", mat = "planks", a = { 104, 72, 50 }, pattern = "solid", price = 160000, decor = 3 },
	herringbone = { name = "헤링본 마루", desc = "지그재그로 깐 원목", mat = "wood", a = { 176, 132, 88 }, b = { 150, 108, 70 }, pattern = "herringbone", price = 260000, decor = 6 },
	jangpan = { name = "노란 장판", desc = "뜨끈한 온돌 감성 장판", mat = "gloss", a = { 226, 186, 112 }, pattern = "solid", price = 50000, decor = 2 },
	marble = { name = "대리석", desc = "호텔 로비 같은 화이트 마블", mat = "marble", a = { 234, 232, 228 }, pattern = "solid", price = 320000, decor = 6 },
	porcelain = { name = "포세린 타일", desc = "큼직한 그레이 포세린", mat = "ceramic", a = { 196, 194, 190 }, pattern = "solid", price = 220000, decor = 4 },
	checker = { name = "체커보드 타일", desc = "레트로 흑백 체크 (카페 · 주방)", mat = "ceramic", a = { 240, 238, 232 }, b = { 34, 34, 38 }, pattern = "checker", price = 240000, decor = 5 },
	terrazzo = { name = "테라조", desc = "알록달록 돌조각 바닥", mat = "concrete", a = { 230, 224, 214 }, b = { 190, 120, 100 }, pattern = "terrazzo", price = 280000, decor = 5 },
	carpet = { name = "카펫", desc = "푹신한 호텔 카펫", mat = "carpet", a = { 110, 112, 124 }, pattern = "solid", price = 150000, decor = 3 },
	concrete = { name = "폴리싱 콘크리트", desc = "갤러리 같은 매끈한 콘크리트", mat = "concrete", a = { 150, 150, 148 }, pattern = "solid", price = 140000, decor = 3 },
	slate = { name = "슬레이트 스톤", desc = "자연석 느낌의 다크 스톤", mat = "slate", a = { 86, 88, 92 }, pattern = "solid", price = 200000, decor = 4 },
}

-- home-wide lighting presets. tint = ColorCorrection tint (client), sat / con / bright = CC params,
-- light = colour of the home's lights, mult = brightness multiplier, party = animated colours
Finish.LIGHT_ORDER = { "default", "warm", "daylight", "mood", "neon", "party" }
Finish.LIGHTS = {
	default = { name = "기본", icon = "🏠", desc = "집 원래 조명", price = 0, decor = 0 },
	warm = { name = "따뜻한", icon = "🕯️", desc = "전구색 3000K · 아늑한 저녁", light = { 255, 200, 140 }, mult = 1.0, tint = { 255, 240, 222 }, sat = 0.05, con = 0.04, bright = 0.01, price = 30000, decor = 2 },
	daylight = { name = "주광", icon = "☀️", desc = "주광색 6500K · 또렷하고 밝게", light = { 236, 244, 255 }, mult = 1.25, tint = { 246, 250, 255 }, sat = -0.02, con = 0.03, bright = 0.04, price = 30000, decor = 1 },
	mood = { name = "무드", icon = "🌙", desc = "은은하게 낮춘 앰버 무드등", light = { 255, 160, 90 }, mult = 0.55, tint = { 255, 226, 200 }, sat = 0.1, con = 0.08, bright = -0.05, price = 50000, decor = 3 },
	neon = { name = "네온", icon = "🌃", desc = "광안대교 야경 같은 시안 · 마젠타", light = { 190, 120, 255 }, mult = 0.9, tint = { 236, 222, 255 }, sat = 0.2, con = 0.1, bright = -0.02, price = 80000, decor = 4, neon = true },
	party = { name = "파티", icon = "🪩", desc = "색이 바뀌는 파티 조명 · 집들이용", light = { 255, 90, 200 }, mult = 1.0, tint = { 255, 240, 250 }, sat = 0.25, con = 0.12, bright = 0, price = 120000, decor = 4, party = true },
}

function Finish.def(kind: string, id: any): any?
	if type(id) ~= "string" then
		return nil
	end
	if kind == "wall" then
		return Finish.WALLS[id]
	elseif kind == "floor" then
		return Finish.FLOORS[id]
	elseif kind == "light" then
		return Finish.LIGHTS[id]
	end
	return nil
end

function Finish.price(kind: string, id: string, tierKey: string?, room: string?): number
	local def = Finish.def(kind, id)
	if not def then
		return 0
	end
	local mult = (Finish.TIER_MULT :: any)[tierKey or ""] or 1
	local rf = if kind == "light" then 1 else ((Finish.ROOM_FACTOR :: any)[room or ""] or 1)
	return math.floor(def.price * mult * rf / 1000 + 0.5) * 1000
end

local function hexOk(s: any): boolean
	return type(s) == "string" and #s == 6 and string.match(s, "^%x%x%x%x%x%x$") ~= nil
end
Finish.hexOk = hexOk

local function cleanEntry(kind: string, e: any): any?
	if type(e) ~= "table" then
		return nil
	end
	local def = Finish.def(kind, e.p)
	if not def then
		return nil
	end
	return { p = e.p, a = if hexOk(e.a) then string.lower(e.a) else nil, b = if hexOk(e.b) then string.lower(e.b) else nil }
end

-- finish = { rooms = { [roomId] = { w = {p, a?, b?}?, f = {p, a?, b?}? } }, light = presetId? }
function Finish.sanitize(raw: any): any
	local out = { rooms = {}, light = nil :: string? }
	if type(raw) ~= "table" then
		return out
	end
	local n = 0
	if type(raw.rooms) == "table" then
		for room, e in raw.rooms do
			if type(room) == "string" and #room > 0 and #room <= 24 and type(e) == "table" and n < 24 then
				local w = cleanEntry("wall", e.w)
				local f = cleanEntry("floor", e.f)
				if w or f then
					out.rooms[room] = { w = w, f = f }
					n += 1
				end
			end
		end
	end
	if type(raw.light) == "string" and Finish.LIGHTS[raw.light] and raw.light ~= "default" then
		out.light = raw.light
	end
	return out
end

-- 인테리어 점수 from finishes
function Finish.decor(finish: any): number
	local s = 0
	if type(finish) ~= "table" then
		return 0
	end
	for _, e in finish.rooms or {} do
		if e.w and Finish.WALLS[e.w.p] then
			s += Finish.WALLS[e.w.p].decor
		end
		if e.f and Finish.FLOORS[e.f.p] then
			s += Finish.FLOORS[e.f.p].decor
		end
	end
	if finish.light and Finish.LIGHTS[finish.light] then
		s += Finish.LIGHTS[finish.light].decor
	end
	return s
end

-- the colours of an entry (hex overrides or the defaults)
function Finish.colors(kind: string, e: any): ({ number }?, { number }?)
	local def = Finish.def(kind, e and e.p)
	if not def then
		return nil, nil
	end
	local function un(h: any, d: any): any
		if hexOk(h) then
			return { tonumber(string.sub(h, 1, 2), 16), tonumber(string.sub(h, 3, 4), 16), tonumber(string.sub(h, 5, 6), 16) }
		end
		return d
	end
	return un(e.a, def.a), un(e.b, def.b)
end

return Finish
