#!/usr/bin/env python3
"""rooms.json -> src/StarterPlayer/StarterPlayerScripts/GwangalliBuildingInterior/Venues.luau

    python3 tools/venues/gen_venues.py
"""
import json, os
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
d = json.load(open(os.path.join(ROOT, 'tools/venues/rooms.json'), encoding='utf-8'))


def v3(a):
    return 'Vector3.new(%s)' % ', '.join(repr(float(x)) for x in a)


out = ['--!strict',
       '-- GwangalliBuildingInterior/Venues: 큰 시설의 방 목록 (ShopFloor 가 없는 PC방 · 노래방 · GS25 본점 · 딜리버리 · 게임랜드 · 볼링장 층 ...).',
       '-- tools/venues/rooms.json 에서 tools/venues/gen_venues.py 로 생성 (손으로 고치지 말고 JSON 을 고친 뒤 다시 생성).',
       '--   Venues.LIST = { { group, name, rooms = { { room, type, center (바닥 윗면 가운데, 월드), size (월드 축 X, 높이, Z),',
       '--                    face ("+X" | "-X" | "+Z" | "-Z" = 입구 쪽 월드 방향), door?, lanes?, noDoorGuess? } } } }',
       '--   Venues.spec(model, venue, room) -> Scan.fitRoom 에 줄 spec,  Venues.post(V, room) -> 통로 · 포인트 keep 추가',
       '', 'local Venues = {}', '', 'Venues.LIST = {']
for v in d['venues']:
    out.append('\t{ group = %s, name = %s, rooms = {' % (json.dumps(v['group'], ensure_ascii=False), json.dumps(v['name'], ensure_ascii=False)))
    for r in v['rooms']:
        f = ['room = %s' % json.dumps(r['room']), 'type = %s' % json.dumps(r['type']), 'center = ' + v3(r['center']), 'size = ' + v3(r['size']), 'face = %s' % json.dumps(r['face'])]
        if r.get('door'):
            f.append('door = { x = %r, z = %r, w = %r }' % tuple(float(x) for x in r['door']))
        if r.get('lanes'):
            f.append('lanes = { %s }' % ', '.join('{ %r, %r, %r, %r }' % tuple(float(x) for x in l) for l in r['lanes']))
        if r.get('keepPts'):
            f.append('keepPts = { %s }' % ', '.join('{ %r, %r, %r }' % tuple(float(x) for x in l) for l in r['keepPts']))
        if r.get('noDoorGuess'):
            f.append('noDoorGuess = true')
        if r.get('name'):
            f.append('name = %s' % json.dumps(r['name'], ensure_ascii=False))
        out.append('\t\t{ ' + ', '.join(f) + ' },')
    out.append('\t} },')
out.append('}')
out.append('''
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

return Venues''')
p = os.path.join(ROOT, 'src/StarterPlayer/StarterPlayerScripts/GwangalliBuildingInterior/Venues.luau')
open(p, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
print(p, sum(len(v['rooms']) for v in d['venues']), 'rooms')
