--!strict
-- GwangalliBuildingInterior/Venues: 큰 시설의 방 목록 (ShopFloor 가 없는 PC방 · 노래방 · GS25 본점 · 딜리버리 · 게임랜드 · 볼링장 층 ...).
-- tools/venues/rooms.json 에서 tools/venues/gen_venues.py 로 생성 (손으로 고치지 말고 JSON 을 고친 뒤 다시 생성).
--   Venues.LIST = { { group, name, rooms = { { room, type, center (바닥 윗면 가운데, 월드), size (월드 축 X, 높이, Z),
--                    face ("+X" | "-X" | "+Z" | "-Z" = 입구 쪽 월드 방향), door?, lanes?, noDoorGuess? } } } }
--   Venues.spec(model, venue, room) -> Scan.fitRoom 에 줄 spec,  Venues.post(V, room) -> 통로 · 포인트 keep 추가

local Venues = {}

Venues.LIST = {
	{ group = "convenience", name = "GS25 광안리점", rooms = {
		{ room = "sales", type = "gs25", center = Vector3.new(-336.12, 7.0, 284.47), size = Vector3.new(55.32, 11.0, 45.41), face = "+X", door = { x = -311.7, z = 302.0, w = 6.0 }, lanes = { { -299.69, 302.15, -311.69, 301.92 }, { -311.69, 301.92, -319.44, 299.28 }, { -319.44, 299.28, -319.23, 288.03 }, { -319.23, 288.03, -319.07, 279.53 }, { -319.07, 279.53, -318.88, 269.28 }, { -319.44, 299.28, -316.93, 304.23 }, { -316.93, 304.23, -319.84, 304.77 }, { -319.84, 304.77, -322.84, 304.72 }, { -322.84, 304.72, -329.04, 304.4 }, { -319.23, 288.03, -355.42, 287.36 } } },
		{ room = "stock", type = "stockroom", center = Vector3.new(-375.36, 7.0, 283.73), size = Vector3.new(23.22, 11.0, 44.81), face = "+X", door = { x = -364.12, z = 303.15, w = 3.6 } },
	} },
	{ group = "delivery", name = "광안 딜리버리", rooms = {
		{ room = "office", type = "delivery", center = Vector3.new(-325.68, 6.8, 341.67), size = Vector3.new(32.36, 11.2, 46.98), face = "+X", door = { x = -309.8, z = 342.0, w = 6.6 } },
		{ room = "warehouse", type = "warehouse", center = Vector3.new(-364.52, 6.8, 340.95), size = Vector3.new(47.05, 11.2, 47.25), face = "+X", door = { x = -341.0, z = 340.4, w = 14.0 }, lanes = { { -341.0, 340.4, -383.96, 342.58 }, { -383.96, 342.58, -388.0, 342.5 } } },
	} },
	{ group = "pcbang", name = "광안 PC방", rooms = {
		{ room = "front", type = "pcbang", center = Vector3.new(118.6, 6.85, 279.3), size = Vector3.new(59.0, 11.1, 22.4), face = "-Z" },
		{ room = "hall", type = "pchall", center = Vector3.new(118.6, 6.85, 318.0), size = Vector3.new(59.0, 11.1, 55.0), face = "-Z", noDoorGuess = true },
		{ room = "back", type = "pcback", center = Vector3.new(118.6, 6.85, 355.3), size = Vector3.new(59.0, 11.1, 20.6), face = "-Z", noDoorGuess = true },
	} },
	{ group = "karaoke", name = "광안 코인노래연습장", rooms = {
		{ room = "lobby", type = "karaoke", center = Vector3.new(17.2, 6.85, 280.65), size = Vector3.new(47.6, 11.1, 24.3), face = "-Z" },
		{ room = "corridor", type = "kcorridor", center = Vector3.new(17.3, 6.85, 317.0), size = Vector3.new(12.0, 11.1, 48.0), face = "-Z", noDoorGuess = true },
		{ room = "booth01", type = "kbooth", center = Vector3.new(32.35, 6.85, 299.0), size = Vector3.new(17.3, 11.1, 11.6), face = "-X" },
		{ room = "booth02", type = "kbooth", center = Vector3.new(32.35, 6.85, 311.0), size = Vector3.new(17.3, 11.1, 11.6), face = "-X" },
		{ room = "booth03", type = "kbooth", center = Vector3.new(32.35, 6.85, 323.0), size = Vector3.new(17.3, 11.1, 11.6), face = "-X" },
		{ room = "booth04", type = "kbooth", center = Vector3.new(32.35, 6.85, 335.0), size = Vector3.new(17.3, 11.1, 11.6), face = "-X" },
		{ room = "booth05", type = "kbooth", center = Vector3.new(2.17, 6.85, 299.0), size = Vector3.new(17.45, 11.1, 11.6), face = "+X" },
		{ room = "booth06", type = "kbooth", center = Vector3.new(2.17, 6.85, 311.0), size = Vector3.new(17.45, 11.1, 11.6), face = "+X" },
		{ room = "booth07", type = "kbooth", center = Vector3.new(2.17, 6.85, 323.0), size = Vector3.new(17.45, 11.1, 11.6), face = "+X" },
		{ room = "booth08", type = "kbooth", center = Vector3.new(2.17, 6.85, 335.0), size = Vector3.new(17.45, 11.1, 11.6), face = "+X" },
	} },
	{ group = "arcade", name = "광안 게임랜드", rooms = {
		{ room = "hall", type = "arcade", center = Vector3.new(-340.3, 6.8, 444.4), size = Vector3.new(74.6, 11.2, 78.6), face = "+X", door = { x = -302.6, z = 433.1, w = 12.5 } },
		{ room = "lobby", type = "stairlobby", center = Vector3.new(-312.9, 6.8, 399.5), size = Vector3.new(21.8, 11.2, 9.6), face = "+X" },
		{ room = "photo", type = "photo", center = Vector3.new(-307.2, 6.8, 387.0), size = Vector3.new(10.2, 9.7, 12.1), face = "+X", door = { x = -301.7, z = 390.2, w = 4.8 } },
	} },
	{ group = "bowling", name = "실내", rooms = {
		{ room = "lobby", type = "bowlobby", center = Vector3.new(297.6, 6.75, 456.2), size = Vector3.new(88.0, 21.9, 26.0), face = "+Z", door = { x = 264.8, z = 469.6, w = 12.0 }, name = "광안 락볼링클럽" },
		{ room = "gamezone", type = "bowarcade", center = Vector3.new(242.6, 6.75, 457.2), size = Vector3.new(22.0, 21.9, 26.0), face = "+Z", name = "락볼링 오락코너" },
		{ room = "lounge", type = "bowlounge", center = Vector3.new(264.2, 6.75, 419.6), size = Vector3.new(40.4, 21.9, 48.5), face = "+Z", noDoorGuess = true, name = "락볼링 라운지" },
		{ room = "bar", type = "bowbar", center = Vector3.new(237.4, 6.75, 422.1), size = Vector3.new(12.1, 21.9, 36.4), face = "+X", noDoorGuess = true, name = "ROCK & BOWL BAR" },
		{ room = "snack", type = "bowsnack", center = Vector3.new(257.0, 6.75, 382.5), size = Vector3.new(52.0, 21.9, 27.0), face = "+Z", noDoorGuess = true, name = "ROCK & BOWL 분식" },
		{ room = "wc_m", type = "restroom", center = Vector3.new(242.3, 6.75, 362.2), size = Vector3.new(22.5, 10.85, 10.9), face = "+X", door = { x = 253.7, z = 363.7, w = 3.5 }, name = "남자 화장실" },
		{ room = "wc_f", type = "restroom", center = Vector3.new(242.2, 6.75, 350.2), size = Vector3.new(22.4, 10.85, 10.9), face = "+X", door = { x = 253.6, z = 348.2, w = 3.5 }, name = "여자 화장실" },
		{ room = "office", type = "office", center = Vector3.new(241.8, 6.75, 336.3), size = Vector3.new(22.8, 10.85, 14.7), face = "+X", door = { x = 253.6, z = 338.0, w = 3.5 }, name = "사무실 · 창고" },
		{ room = "corridor", type = "corridor", center = Vector3.new(268.7, 6.75, 348.9), size = Vector3.new(28.5, 21.9, 40.2), face = "+Z", noDoorGuess = true, name = "락볼링 복도" },
		{ room = "elevhall", type = "elevhall", center = Vector3.new(348.2, 6.75, 457.0), size = Vector3.new(13.2, 11.9, 21.2), face = "+Z", name = "2~4층 엘리베이터 홀" },
	} },
	{ group = "bowling", name = "상층_2F-4F", rooms = {
		{ room = "billiards", type = "billiards", center = Vector3.new(282.8, 30.08, 442.45), size = Vector3.new(101.2, 9.5, 52.5), face = "+X", door = { x = 333.9, z = 459.5, w = 4.0 }, name = "광안 당구클럽" },
		{ room = "salon", type = "salon", center = Vector3.new(314.2, 41.0, 442.45), size = Vector3.new(38.4, 9.55, 52.5), face = "+X", name = "헤어살롱 (3F)" },
		{ room = "select", type = "clothing", center = Vector3.new(263.3, 41.0, 442.45), size = Vector3.new(62.2, 9.55, 52.5), face = "+X", noDoorGuess = true, name = "GWANGAN SELECT SHOP" },
		{ room = "gym", type = "gym", center = Vector3.new(282.8, 52.0, 442.45), size = Vector3.new(101.2, 9.95, 52.5), face = "+X", name = "광안 휘트니스 24" },
		{ room = "hall2", type = "elevhall", center = Vector3.new(344.2, 30.08, 457.3), size = Vector3.new(21.2, 9.5, 20.8), face = "-X", noDoorGuess = true, name = "2F 엘리베이터 홀" },
		{ room = "hall3", type = "elevhall", center = Vector3.new(344.2, 41.0, 457.3), size = Vector3.new(21.2, 9.55, 20.8), face = "-X", noDoorGuess = true, name = "3F 엘리베이터 홀" },
		{ room = "hall4", type = "elevhall", center = Vector3.new(344.2, 52.0, 457.3), size = Vector3.new(21.2, 9.95, 20.8), face = "-X", noDoorGuess = true, name = "4F 엘리베이터 홀" },
	} },
	{ group = "club", name = "CLUB OCEAN 광안", rooms = {
		{ room = "lounge2f", type = "clublounge", center = Vector3.new(-199.1, 33.9, 401.8), size = Vector3.new(42.6, 13.0, 172.6), face = "+Z", noDoorGuess = true, name = "OCEAN SKY LOUNGE" },
		{ room = "rooftop", type = "rooftop", center = Vector3.new(-143.9, 34.1, 290.6), size = Vector3.new(147.8, 12.0, 54.2), face = "-X", noDoorGuess = true, name = "OCEAN ROOFTOP" },
		{ room = "hiphop", type = "hiphop", center = Vector3.new(-121.4, 7.0, 289.5), size = Vector3.new(70.7, 15.5, 50.1), face = "-X", noDoorGuess = true, name = "ROOM 2 · HIP-HOP" },
		{ room = "corridor", type = "corridor", center = Vector3.new(-167.0, 7.0, 302.2), size = Vector3.new(18.1, 10.5, 76.3), face = "+Z", noDoorGuess = true, name = "CLUB OCEAN 복도" },
		{ room = "wc_f", type = "restroom", center = Vector3.new(-196.8, 7.0, 280.3), size = Vector3.new(41.3, 10.5, 19.6), face = "+X", noDoorGuess = true, name = "여자 화장실" },
		{ room = "wc_m", type = "restroom", center = Vector3.new(-197.0, 7.0, 301.8), size = Vector3.new(41.3, 10.5, 20.6), face = "+X", noDoorGuess = true, name = "남자 화장실" },
	} },
	{ group = "hospital", name = "광안 메디컬 의원", rooms = {
		{ room = "lobby", type = "clinic_lobby", center = Vector3.new(-504.5, 6.9, 278.3), size = Vector3.new(47.0, 11.05, 25.5), face = "-Z", name = "광안 메디컬 의원 접수" },
		{ room = "waiting", type = "clinic_waiting", center = Vector3.new(-468.5, 6.9, 279.6), size = Vector3.new(25.0, 11.05, 26.1), face = "-Z", noDoorGuess = true, name = "광안 메디컬 의원 대기실" },
		{ room = "consult", type = "clinic_consult", center = Vector3.new(-551.3, 6.9, 278.1), size = Vector3.new(43.4, 11.05, 26.9), face = "+Z", noDoorGuess = true, name = "진료실 1 · 내과" },
		{ room = "pharmacy", type = "clinic_pharmacy", center = Vector3.new(-545.3, 6.9, 308.7), size = Vector3.new(57.5, 11.05, 21.7), face = "-Z", noDoorGuess = true, name = "약국 코너" },
		{ room = "treat", type = "clinic_treat", center = Vector3.new(-479.5, 6.9, 311.1), size = Vector3.new(45.7, 11.05, 21.7), face = "-Z", noDoorGuess = true, name = "주사실 · 처치실" },
		{ room = "backhall", type = "clinic_hall", center = Vector3.new(-515.7, 6.9, 330.5), size = Vector3.new(116.7, 11.05, 12.5), face = "-Z", noDoorGuess = true, name = "후면 홀" },
		{ room = "ward201", type = "clinic_ward", center = Vector3.new(-477.5, 21.08, 278.0), size = Vector3.new(43.5, 8.4, 24.5), face = "+Z", noDoorGuess = true, name = "입원실 201" },
		{ room = "nurse", type = "clinic_nurse", center = Vector3.new(-514.4, 21.08, 277.3), size = Vector3.new(26.9, 8.4, 25.2), face = "+Z", noDoorGuess = true, name = "간호사실" },
		{ room = "ward202", type = "clinic_ward", center = Vector3.new(-551.3, 21.08, 275.9), size = Vector3.new(43.5, 8.4, 23.2), face = "+Z", noDoorGuess = true, name = "입원실 202" },
		{ room = "lounge", type = "clinic_lounge", center = Vector3.new(-475.2, 21.08, 317.4), size = Vector3.new(38.3, 8.4, 38.3), face = "-Z", noDoorGuess = true, name = "휴게실 LOUNGE" },
		{ room = "checkup", type = "clinic_checkup", center = Vector3.new(-549.0, 21.08, 316.1), size = Vector3.new(47.8, 8.4, 40.4), face = "-Z", noDoorGuess = true, name = "건강검진센터" },
	} },
	{ group = "garage", name = "광안 오토 정비소 & 중고차", rooms = {
		{ room = "showroom", type = "showroom", center = Vector3.new(-564.9, 6.67, 450.3), size = Vector3.new(68.4, 14.8, 49.3), face = "+Z", name = "광안 오토 쇼룸" },
		{ room = "bay", type = "servicebay", center = Vector3.new(-499.0, 6.66, 450.0), size = Vector3.new(46.0, 14.6, 52.1), face = "+Z", name = "광안 오토 정비 베이" },
		{ room = "wash", type = "carwash", center = Vector3.new(-455.1, 6.66, 452.6), size = Vector3.new(25.3, 13.4, 50.0), face = "+Z", noDoorGuess = true, name = "광안 오토 자동세차장" },
	} },
}

local FACE = { ["+X"] = Vector3.new(1, 0, 0), ["-X"] = Vector3.new(-1, 0, 0), ["+Z"] = Vector3.new(0, 0, 1), ["-Z"] = Vector3.new(0, 0, -1) }

-- 방 프레임: 원점 = 바닥 윗면 가운데, 로컬 +Z = 입구 쪽 (= face), -Z = 안쪽 끝
function Venues.frame(r: any): CFrame
	local e = FACE[r.face] or FACE["+Z"]
	return CFrame.lookAt(r.center, r.center - e)
end

function Venues.spec(model: Instance, v: any, r: any): any
	local cf = Venues.frame(r)
	local alongX = r.face == "+X" or r.face == "-X"
	local W = if alongX then r.size.Z else r.size.X
	local D = if alongX then r.size.X else r.size.Z
	local spec: any = {
		cf = cf,
		size = Vector3.new(W, r.size.Y, D),
		type = r.type,
		room = r.room,
		kind = "venue",
		name = r.name or v.name,
		key = string.format("%s#%s", v.name, r.room),
		noDoorGuess = r.noDoorGuess,
	}
	if r.door then
		local p = cf:PointToObjectSpace(Vector3.new(r.door.x, r.center.Y, r.door.z))
		spec.door = { x = p.X, z = p.Z, w = r.door.w }
	end
	return spec
end

-- 방 V 에 통로 (월드 선분, 폭 3) 와 포인트 (반지름 2.5) keep 추가
function Venues.post(V: any, r: any)
	for _, l in r.lanes or {} do
		local a = V.cf:PointToObjectSpace(Vector3.new(l[1], r.center.Y, l[2]))
		local b = V.cf:PointToObjectSpace(Vector3.new(l[3], r.center.Y, l[4]))
		local len = (b - a).Magnitude
		local n = math.max(1, math.ceil(len / 1.5))
		for i = 0, n do
			local p = a:Lerp(b, i / n)
			V:addKeep(Vector3.new(p.X - 1.5, 0.1, p.Z - 1.5), Vector3.new(p.X + 1.5, 6.5, p.Z + 1.5), "lane")
		end
	end
	for _, k in r.keepPts or {} do
		local p = V.cf:PointToObjectSpace(Vector3.new(k[1], k[2], k[3]))
		V:keepAround(p, 2.5, 6.5, "point")
	end
end

-- 맵에 있는 시설 찾기: { { model, venue, room } }
function Venues.find(): { any }
	local out = {}
	local g = workspace:FindFirstChild("Gwangalli")
	if not g then
		return out
	end
	for _, v in Venues.LIST do
		local grp = g:FindFirstChild(v.group)
		local m = grp and grp:FindFirstChild(v.name)
		if m then
			for _, r in v.rooms do
				table.insert(out, { model = m, venue = v, room = r })
			end
		end
	end
	return out
end

return Venues
