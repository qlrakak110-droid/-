-- GwangalliPhone/MapData: static map data for the phone's 지도 / 택시 apps and the quest marker.
--
-- * Destinations: world position (studs) of every Destination part at the time of writing, keyed by
--   DisplayName. With StreamingEnabled the client only has nearby Destination parts, so this table
--   lets the phone draw far places and point the quest marker at them. Live parts always win: the
--   Destinations module replaces an entry as soon as its part streams in, so an outdated entry only
--   costs accuracy until the player gets close. Regenerate after moving Destination parts with a
--   Lune one-off over a built place (print DisplayName + CFrame.Position of every part tagged
--   "Destination").
-- * Coast / roads / bridge: coarse polylines (x, z) from build/kit/plan.luau (coast baseline
--   z = -0.0000324 x^2, bands 광안해변로 n = 45-89, 광남로 509-553, 수영로 827-883) and the bridge
--   deck parts (z = -3300 suspension section, approaches landing at x = -4242 / 4447).
-- Orientation: the sea is -Z. The map draws -Z at the top (standing on the beach facing the sea:
-- 민락 on the left, 남천 on the right), like the real map of Gwangalli.

local MapData = {}

MapData.Destinations = {
	["민락수변공원"] = { -3679, 7, -531 },
	["밀락더마켓"] = { -3234, 7, -343 },
	["민락어민활어직판장"] = { -2930, 5, -323 },
	["민락회타운"] = { -2582, 7, -118 },
	["지하철 수영역 7번 출구"] = { -2341, 9, 724 },
	["SK 광안셀프주유소"] = { -2185, 7, 653 },
	["광안교회"] = { -2016, 7, 449 },
	["테라스타오션"] = { -1495, 11, 33 },
	["홈플러스 익스프레스 광안점"] = { -1362, 7, 517 },
	["광안초등학교"] = { -1110, 7, 528 },
	["스타벅스 광안리점"] = { -834, 11, 83 },
	["BNK부산은행 광안동지점"] = { -346, 7, 809 },
	["광안지구대"] = { -326, 7, 584 },
	["지하철 광안역 6번 출구"] = { -325, 9, 888 },
	["GS25 광안리점"] = { -305, 7, 302 },
	["광안 게임랜드"] = { -299, 7, 433 },
	["광안리 만남의 광장"] = { -248, 7, 24 },
	["스타벅스 광안역점"] = { -235, 7, 811 },
	["CLUB OCEAN 광안"] = { -229, 8, 375 },
	["지하철 광안역 3번 출구"] = { -228, 9, 817 },
	["GS25 광안해변점 (켄트호텔 1F)"] = { -186, 7, 106 },
	["켄트호텔 광안리"] = { -148, 7, 109 },
	["fondx 홍미당 (아쿠아펠리스 1F)"] = { -91, 7, 110 },
	["호텔 아쿠아펠리스"] = { -42, 7, 110 },
	["광안리해수욕장 (중앙)"] = { -20, 3, -70 },
	["아쿠아펠리스 워터파크 · 찜질방"] = { -1, 7, 107 },
	["광안대교 (상판)"] = { 0, 151, -3282 },
	["광안 코인노래연습장"] = { 5, 7, 265 },
	["광안동우체국"] = { 73, 7, 567 },
	["광안리 관광안내소"] = { 105, 7, 112 },
	["광안 PC방"] = { 109, 7, 264 },
	["브롱스 광안리 (호메르스호텔 1F)"] = { 240, 7, 105 },
	["광안 락볼링클럽 (볼링장)"] = { 265, 7, 481 },
	["호메르스호텔"] = { 268, 7, 108 },
	["광안 당구클럽 (2F)"] = { 338, 31, 457 },
	["헤어살롱 & 편집숍"] = { 338, 41, 457 },
	["광안 휘트니스 24 (헬스장)"] = { 338, 52, 457 },
	["광안자이 (정문)"] = { 391, 7, 887 },
	["광안 중앙병원"] = { 774, 7, 794 },
	["호텔 센트럴베이"] = { 1013, 11, 73 },
	["광안 공영주차장"] = { 1047, 7, 534 },
	["지하철 금련산역 1번 출구"] = { 1365, 9, 761 },
	["광안지웰에스테이트"] = { 1697, 11, 12 },
	["광안리 SUP존"] = { 1716, 3, -136 },
	["해양레포츠센터"] = { 2354, 4, -339 },
	["남천해변공원"] = { 2501, 7, -199 },
	["빵천동 빵집골목"] = { 2975, 7, 300 },
	["지하철 남천역 3번 출구"] = { 3177, 9, 508 },
	["삼익비치타운"] = { 3306, 7, -323 },
	["KBS 부산방송총국"] = { 3317, 7, 572 },
}

-- Fallback positions for venues that may be missing from an older place file (the bowling building's
-- upper floors). Live Destination parts and the table above win.
MapData.Extra = {
	["광안 휘트니스 24 (헬스장)"] = { 338, 52, 457 },
	["헤어살롱 & 편집숍"] = { 338, 41, 457 },
}

MapData.Bounds = { x0 = -4700, x1 = 4700, z0 = -3450, z1 = 1250 }

local A = 0.0000324
local function baseline(x: number): number
	return -A * x * x
end
MapData.baseline = baseline

-- Sea boundary (waterline) from west (-X) to east (+X): points (x, z).
local coast = {
	{ -4700, -520 },
	{ -4300, -560 },
	{ -3800, -600 },
	{ -3400, -470 },
	{ -3000, -420 },
	{ -2700, -380 },
	{ -2440, -300 },
}
for i = 0, 14 do
	local x = -2380 + i * 340
	local t = math.clamp(x / 2380, -1, 1)
	table.insert(coast, { x, baseline(x) - (280 - 170 * t * t) })
end
for _, p in { { 2440, -300 }, { 2700, -380 }, { 3100, -520 }, { 3600, -560 }, { 4100, -560 }, { 4700, -540 } } do
	table.insert(coast, p)
end
MapData.Coast = coast

-- Promenade edge (top of the seawall) along the beach, for the sand strip.
MapData.Beach = { x0 = -2380, x1 = 2380 }

local function roadAt(n: number, x0: number, x1: number, step: number)
	local pts = {}
	local x = x0
	while x <= x1 + 1e-6 do
		table.insert(pts, { x, baseline(x) + n })
		x += step
	end
	return pts
end

MapData.Roads = {
	{ name = "광안해변로", width = 3, points = roadAt(67, -4200, 4000, 700) },
	{ name = "광남로", width = 2, points = roadAt(531, -4200, 4000, 700) },
	{ name = "수영로", width = 3, points = roadAt(855, -4200, 4000, 700) },
	{ name = "광안로", width = 2, points = { { -262, baseline(-262) + 45 }, { -262, baseline(-262) + 1195 } } },
	{ name = "민락로", width = 2, points = { { -2470, baseline(-2470) + 45 }, { -2470, baseline(-2470) + 1195 } } },
	{ name = "남천동로", width = 2, points = { { 2470, baseline(2470) + 45 }, { 2470, baseline(2470) + 1195 } } },
}

MapData.Bridge = {
	{ -4242, -513 },
	{ -4391, -760 },
	{ -4391, -2600 },
	{ -4150, -3020 },
	{ -3700, -3280 },
	{ -3500, -3300 },
	{ 3500, -3300 },
	{ 3700, -3280 },
	{ 4150, -3040 },
	{ 4447, -2600 },
	{ 4447, 90 },
	{ 4400, 200 },
}
MapData.BridgeTowers = { { -833, -3300 }, { 833, -3300 } }

MapData.Labels = {
	{ text = "광안리해수욕장", x = 0, z = -230, size = 11 },
	{ text = "광안대교", x = 0, z = -3150, size = 11 },
	{ text = "수영만", x = -2300, z = -1900, size = 12 },
	{ text = "민락", x = -3300, z = 250, size = 11 },
	{ text = "남천", x = 3250, z = 150, size = 11 },
	{ text = "광안", x = -300, z = 1050, size = 11 },
}

return MapData
