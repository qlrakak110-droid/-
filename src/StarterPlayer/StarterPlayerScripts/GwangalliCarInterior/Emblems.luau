--!strict
-- GwangalliCarInterior/Emblems: 브랜드 로고를 납작한 파트로 (현대 · 기아 · 제네시스 + 쇼룸 가상 브랜드 '광안 모터스').
-- 로고마다 2D 도형 목록(획 · 상자 · 타원 · 타원 고리 · 삼각형 · 볼록 다각형, 단위 스터드, 가운데 원점, +y 위)을 두고
-- 그대로 파트로 지음. 도형 목록은 미리보기 도구(tools: 오프라인 렌더러)로 실제 로고와 비교해 다듬은 것.
-- draw(K, P, brand, cf, scale): cf = 로고 가운데 (+Z = 보는 쪽), 뒤에 나오는 도형이 위 (0.0012 씩 앞으로).

local Emblems = {}

local ROT_X_TO_Z = CFrame.Angles(0, -math.pi / 2, 0)
local DEPTH = 0.008
local LAYER = 0.0012

local function lookOf(P: any, name: string?): any
	if name == "dark" then
		return P.hardDark
	elseif name == "gloss" then
		return P.gloss
	elseif name == "satin" then
		return P.satin
	elseif name == "white" then
		return P.markWhite
	elseif name == "red" then
		return P.hazard
	end
	return P.chrome
end

-- 삼각형 = 쐐기 2개 (세 점은 로고 평면 위, 두께는 평면 법선 방향)
local function tri(K: any, frame: CFrame, a: Vector3, b: Vector3, c: Vector3, look: any)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	if ac:Cross(ab).Magnitude < 1e-8 or bc.Magnitude < 1e-5 then
		return
	end
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local h = math.abs(ab:Dot(up))
	if h < 1e-4 then
		return
	end
	local d1, d2 = math.abs(ab:Dot(back)), math.abs(ac:Dot(back))
	if d1 > 1e-4 then
		K:wedge("EmblemFacet", Vector3.new(DEPTH, h, d1), frame * CFrame.fromMatrix((a + b) / 2, right, up, back), look)
	end
	if d2 > 1e-4 then
		K:wedge("EmblemFacet", Vector3.new(DEPTH, h, d2), frame * CFrame.fromMatrix((a + c) / 2, -right, up, -back), look)
	end
end

local function bar(K: any, frame: CFrame, x0: number, y0: number, x1: number, y1: number, w: number, extra: number, z: number, look: any)
	local dx, dy = x1 - x0, y1 - y0
	local L = math.sqrt(dx * dx + dy * dy)
	K:box("EmblemStroke", Vector3.new(L + extra, w, DEPTH), frame * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, z) * CFrame.Angles(0, 0, math.atan2(dy, dx)), look)
end

function Emblems.draw(K: any, P: any, brand: string, cf: CFrame, scale: number?)
	local E = Emblems.DATA[brand] or Emblems.DATA.generic
	if not E then
		return
	end
	local s = scale or 1
	for i, pr in E.prims do
		local z = (i - 1) * LAYER
		local look = lookOf(P, pr.look)
		local t = pr.t
		if t == "s" then
			local a, b, w = pr.a, pr.b, pr.w * s
			if pr.cap then
				bar(K, cf, a[1] * s, a[2] * s, b[1] * s, b[2] * s, w, 0, z, look)
				for _, p in { a, b } do
					K:cyl("EmblemStroke", DEPTH, w, cf * CFrame.new(p[1] * s, p[2] * s, z) * ROT_X_TO_Z, look)
				end
			else
				bar(K, cf, a[1] * s, a[2] * s, b[1] * s, b[2] * s, w, w * 0.6, z, look)
			end
		elseif t == "b" then
			K:box("EmblemStroke", Vector3.new(pr.w * s, pr.h * s, DEPTH), cf * CFrame.new(pr.c[1] * s, pr.c[2] * s, z) * CFrame.Angles(0, 0, math.rad(pr.rot or 0)), look)
		elseif t == "e" then
			K:ell("EmblemDisc", Vector3.new(pr.rx * 2 * s, pr.ry * 2 * s, DEPTH), cf * CFrame.new(pr.c[1] * s, pr.c[2] * s, z) * CFrame.Angles(0, 0, math.rad(pr.rot or 0)), look)
		elseif t == "r" then
			local n = pr.n or 16
			local a0, a1 = math.rad(pr.a0 or 0), math.rad(pr.a1 or 360)
			local rr = math.rad(pr.rot or 0)
			local cr, sr = math.cos(rr), math.sin(rr)
			local pts = {}
			for k = 0, n do
				local u = a0 + (a1 - a0) * k / n
				local x, y = pr.rx * math.cos(u), pr.ry * math.sin(u)
				pts[k + 1] = { (pr.c[1] + x * cr - y * sr) * s, (pr.c[2] + x * sr + y * cr) * s }
			end
			for k = 1, n do
				bar(K, cf, pts[k][1], pts[k][2], pts[k + 1][1], pts[k + 1][2], pr.w * s, pr.w * s * 0.3, z, look)
			end
		elseif t == "tri" or t == "poly" then
			local p = pr.p
			local function v(q: { number }): Vector3
				return Vector3.new(q[1] * s, q[2] * s, z)
			end
			for k = 2, #p - 1 do
				tri(K, cf, v(p[1]), v(p[k]), v(p[k + 1]), look)
			end
		end
	end
end


Emblems.DATA = {
	hyundai = { w = 0.17, h = 0.105, prims = {
		{ t = "e", c = { 0, 0 }, rx = 0.085, ry = 0.0435, look = "chrome" },
		{ t = "e", c = { 0, 0 }, rx = 0.078, ry = 0.0367, look = "dark" },
		{ t = "e", c = { 0, 0 }, rx = 0.078, ry = 0.0367, look = "dark" },
		{ t = "poly", p = { { -0.0234, 0.0391 }, { 0.0617, 0.0273 }, { 0.0453, -0.0066 }, { 0.0234, -0.0391 }, { -0.0617, -0.0273 }, { -0.0453, 0.0066 } }, look = "chrome" },
		{ t = "poly", p = { { -0.0033, 0.0366 }, { -0.0043, 0.0057 }, { 0.0086, 0.0093 }, { 0.0252, 0.0162 }, { 0.0375, 0.0224 }, { 0.045, 0.0299 }, { 0.0208, 0.0351 } }, look = "dark" },
		{ t = "poly", p = { { 0.0033, -0.0366 }, { 0.0043, -0.0057 }, { -0.0086, -0.0093 }, { -0.0252, -0.0162 }, { -0.0375, -0.0224 }, { -0.045, -0.0299 }, { -0.0208, -0.0351 } }, look = "dark" },
		{ t = "e", c = { -0.0036, 0.021 }, rx = 0.0169, ry = 0.0119, rot = 58.5071, look = "dark" },
		{ t = "e", c = { -0.0124, 0.0144 }, rx = 0.0057, ry = 0.0085, rot = -8.2828, look = "dark" },
		{ t = "e", c = { 0.0036, -0.021 }, rx = 0.0169, ry = 0.0119, rot = 58.5071, look = "dark" },
		{ t = "e", c = { 0.0124, -0.0144 }, rx = 0.0057, ry = 0.0085, rot = -8.2828, look = "dark" },
	} },
	kia = { w = 0.16, h = 0.058, prims = {
		{ t = "b", c = { -0.071, -0.0045 }, w = 0.0167, h = 0.0268, rot = 0, look = "chrome" },
		{ t = "tri", p = { { -0.0794, 0.0089 }, { -0.0627, 0.0089 }, { -0.0627, 0.0189 } }, look = "chrome" },
		{ t = "poly", p = { { -0.0759, -0.0179 }, { -0.0593, -0.0179 }, { 0.0009, 0.0183 }, { -0.0158, 0.0183 } }, look = "chrome" },
		{ t = "poly", p = { { -0.0288, -0.0179 }, { -0.0104, -0.0179 }, { -0.0309, 0.0027 }, { -0.0427, -0.004 } }, look = "chrome" },
		{ t = "b", c = { 0.0045, 0.0002 }, w = 0.0164, h = 0.0362, rot = 0, look = "chrome" },
		{ t = "poly", p = { { 0.0085, -0.0179 }, { 0.0246, -0.0179 }, { 0.0787, 0.0173 }, { 0.0642, 0.0183 } }, look = "chrome" },
		{ t = "b", c = { 0.071, 0.0047 }, w = 0.0167, h = 0.0272, rot = 0, look = "chrome" },
		{ t = "tri", p = { { 0.0627, -0.0089 }, { 0.0794, -0.0089 }, { 0.0627, -0.0188 } }, look = "chrome" },
	} },
	genesis = { w = 0.26, h = 0.075, prims = {
		{ t = "tri", p = { { 0.1263, 0.033 }, { 0.1263, 0.0375 }, { 0.13, 0.0375 } }, look = "chrome" },
		{ t = "b", c = { 0.0648, 0.0267 }, w = 0.1056, h = 0.0045, look = "chrome" },
		{ t = "tri", p = { { 0.1176, 0.0245 }, { 0.1176, 0.029 }, { 0.1224, 0.029 } }, look = "chrome" },
		{ t = "b", c = { 0.0599, 0.0182 }, w = 0.0958, h = 0.0045, look = "chrome" },
		{ t = "tri", p = { { 0.1078, 0.016 }, { 0.1078, 0.0205 }, { 0.1131, 0.0205 } }, look = "chrome" },
		{ t = "b", c = { 0.0547, 0.0097 }, w = 0.0855, h = 0.0045, look = "chrome" },
		{ t = "tri", p = { { 0.0975, 0.0075 }, { 0.0975, 0.012 }, { 0.103, 0.012 } }, look = "chrome" },
		{ t = "b", c = { 0.0493, 0.0013 }, w = 0.0747, h = 0.0045, look = "chrome" },
		{ t = "tri", p = { { 0.0867, -0.001 }, { 0.0867, 0.0035 }, { 0.0924, 0.0035 } }, look = "chrome" },
		{ t = "b", c = { 0.0437, -0.0073 }, w = 0.0635, h = 0.0045, look = "chrome" },
		{ t = "tri", p = { { 0.0755, -0.0095 }, { 0.0755, -0.005 }, { 0.0814, -0.005 } }, look = "chrome" },
		{ t = "b", c = { 0.038, -0.0158 }, w = 0.052, h = 0.0045, look = "chrome" },
		{ t = "tri", p = { { 0.064, -0.018 }, { 0.064, -0.0135 }, { 0.0701, -0.0135 } }, look = "chrome" },
		{ t = "tri", p = { { -0.1263, 0.033 }, { -0.1263, 0.0375 }, { -0.13, 0.0375 } }, look = "chrome" },
		{ t = "b", c = { -0.0648, 0.0267 }, w = 0.1056, h = 0.0045, look = "chrome" },
		{ t = "tri", p = { { -0.1176, 0.0245 }, { -0.1176, 0.029 }, { -0.1224, 0.029 } }, look = "chrome" },
		{ t = "b", c = { -0.0599, 0.0182 }, w = 0.0958, h = 0.0045, look = "chrome" },
		{ t = "tri", p = { { -0.1078, 0.016 }, { -0.1078, 0.0205 }, { -0.1131, 0.0205 } }, look = "chrome" },
		{ t = "b", c = { -0.0547, 0.0097 }, w = 0.0855, h = 0.0045, look = "chrome" },
		{ t = "tri", p = { { -0.0975, 0.0075 }, { -0.0975, 0.012 }, { -0.103, 0.012 } }, look = "chrome" },
		{ t = "b", c = { -0.0493, 0.0013 }, w = 0.0747, h = 0.0045, look = "chrome" },
		{ t = "tri", p = { { -0.0867, -0.001 }, { -0.0867, 0.0035 }, { -0.0924, 0.0035 } }, look = "chrome" },
		{ t = "b", c = { -0.0437, -0.0073 }, w = 0.0635, h = 0.0045, look = "chrome" },
		{ t = "tri", p = { { -0.0755, -0.0095 }, { -0.0755, -0.005 }, { -0.0814, -0.005 } }, look = "chrome" },
		{ t = "b", c = { -0.038, -0.0158 }, w = 0.052, h = 0.0045, look = "chrome" },
		{ t = "tri", p = { { -0.064, -0.018 }, { -0.064, -0.0135 }, { -0.0701, -0.0135 } }, look = "chrome" },
		{ t = "b", c = { 0, 0.0181 }, w = 0.0565, h = 0.0344, look = "gloss" },
		{ t = "b", c = { 0, -0.0035 }, w = 0.0489, h = 0.0091, look = "gloss" },
		{ t = "tri", p = { { -0.0244, -0.0079 }, { 0.0244, -0.0079 }, { 0, -0.035 } }, look = "gloss" },
		{ t = "b", c = { 0, 0.0352 }, w = 0.2527, h = 0.0045, look = "chrome" },
		{ t = "s", a = { 0.0305, 0.0352 }, b = { 0.03, 0.0181 }, w = 0.005, look = "chrome" },
		{ t = "s", a = { 0.03, 0.0181 }, b = { 0.0277, 0.0043 }, w = 0.005, look = "chrome" },
		{ t = "s", a = { 0.0277, 0.0043 }, b = { 0.0232, -0.0074 }, w = 0.005, look = "chrome" },
		{ t = "s", a = { 0.0232, -0.0074 }, b = { 0.0166, -0.0177 }, w = 0.005, look = "chrome" },
		{ t = "s", a = { 0.0166, -0.0177 }, b = { 0.0083, -0.0266 }, w = 0.005, look = "chrome" },
		{ t = "s", a = { 0.0083, -0.0266 }, b = { 0, -0.0335 }, w = 0.005, look = "chrome" },
		{ t = "s", a = { -0.0305, 0.0352 }, b = { -0.03, 0.0181 }, w = 0.005, look = "chrome" },
		{ t = "s", a = { -0.03, 0.0181 }, b = { -0.0277, 0.0043 }, w = 0.005, look = "chrome" },
		{ t = "s", a = { -0.0277, 0.0043 }, b = { -0.0232, -0.0074 }, w = 0.005, look = "chrome" },
		{ t = "s", a = { -0.0232, -0.0074 }, b = { -0.0166, -0.0177 }, w = 0.005, look = "chrome" },
		{ t = "s", a = { -0.0166, -0.0177 }, b = { -0.0083, -0.0266 }, w = 0.005, look = "chrome" },
		{ t = "s", a = { -0.0083, -0.0266 }, b = { -0, -0.0335 }, w = 0.005, look = "chrome" },
		{ t = "e", c = { 0, -0.0335 }, rx = 0.0026, ry = 0.0026, look = "chrome" },
		{ t = "b", c = { 0, 0.0075 }, w = 0.036, h = 0.0042, look = "chrome" },
	} },
	generic = { w = 0.13, h = 0.13, prims = {
		{ t = "e", c = { 0, 0 }, rx = 0.0565, ry = 0.0565, look = "gloss" },
		{ t = "r", c = { 0, 0 }, rx = 0.0585, ry = 0.0585, w = 0.008, n = 20, a0 = 0, a1 = 360, look = "chrome" },
		{ t = "s", a = { -0.054, -0.006 }, b = { 0.054, -0.006 }, w = 0.005, cap = false, look = "chrome" },
		{ t = "b", c = { -0.022, 0.0132 }, w = 0.005, h = 0.0455, rot = 0, look = "chrome" },
		{ t = "b", c = { 0.022, 0.0132 }, w = 0.005, h = 0.0455, rot = 0, look = "chrome" },
		{ t = "r", c = { 0, 0.073 }, rx = 0.0269, ry = 0.068, w = 0.004, n = 6, a0 = 215, a1 = 325, look = "chrome" },
		{ t = "s", a = { -0.022, 0.034 }, b = { -0.046, -0.0035 }, w = 0.004, cap = false, look = "chrome" },
		{ t = "s", a = { 0.022, 0.034 }, b = { 0.046, -0.0035 }, w = 0.004, cap = false, look = "chrome" },
		{ t = "r", c = { -0.02, -0.0235 }, rx = 0.01, ry = 0.005, w = 0.0045, n = 3, a0 = 0, a1 = 180, look = "chrome" },
		{ t = "r", c = { 0, -0.0235 }, rx = 0.01, ry = 0.005, w = 0.0045, n = 4, a0 = 180, a1 = 360, look = "chrome" },
		{ t = "r", c = { 0.02, -0.0235 }, rx = 0.01, ry = 0.005, w = 0.0045, n = 3, a0 = 0, a1 = 180, look = "chrome" },
		{ t = "e", c = { -0.03, -0.0235 }, rx = 0.0022, ry = 0.0022, look = "chrome" },
		{ t = "e", c = { 0.03, -0.0235 }, rx = 0.0022, ry = 0.0022, look = "chrome" },
		{ t = "r", c = { -0.0176, -0.0385 }, rx = 0.0088, ry = 0.0047, w = 0.0045, n = 3, a0 = 0, a1 = 180, look = "chrome" },
		{ t = "r", c = { 0, -0.0385 }, rx = 0.0088, ry = 0.0047, w = 0.0045, n = 4, a0 = 180, a1 = 360, look = "chrome" },
		{ t = "r", c = { 0.0176, -0.0385 }, rx = 0.0088, ry = 0.0047, w = 0.0045, n = 3, a0 = 0, a1 = 180, look = "chrome" },
		{ t = "e", c = { -0.0264, -0.0385 }, rx = 0.0022, ry = 0.0022, look = "chrome" },
		{ t = "e", c = { 0.0264, -0.0385 }, rx = 0.0022, ry = 0.0022, look = "chrome" },
	} },
}

return Emblems
