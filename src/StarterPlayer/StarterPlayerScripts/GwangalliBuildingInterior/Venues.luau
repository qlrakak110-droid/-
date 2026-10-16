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
