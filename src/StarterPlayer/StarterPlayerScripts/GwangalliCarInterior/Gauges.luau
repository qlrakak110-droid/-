--!strict
-- GwangalliCarInterior/Gauges: 실물 계기판 부품. 원형 게이지(눈금 · 형광 링 · 크롬 베젤 · 회전 바늘)와 7세그먼트 숫자
-- (속도 · 기어 · 공조 온도). 전부 파트라서 로블록스와 임시 스튜디오에서 똑같이 보이고, 바늘은 피벗째 돌고(setNeedle)
-- 숫자는 세그먼트 Transparency 만 바꿉니다(show).

local Gauges = {}

local ROT_X_TO_Z = CFrame.Angles(0, -math.pi / 2, 0)
-- 0 = 7시 반 방향, 최대 = 4시 반 방향 (시계 방향 270°)
local A0, A1 = math.rad(225), math.rad(-45)

-- 원형 게이지. frame: 게이지 중심 (차체 기준, +Z = 보는 사람 쪽), r: 반지름
-- opt = { analog: boolean?, ticks: number? (큰 눈금 간격 수), red: number? (빨간 구간 시작 비율), max: number,
--         look = { mark, red, ring, needle, cap, bezel } }
function Gauges.dial(K: any, frame: CFrame, r: number, opt: any): any
	local L = opt.look
	local analog = opt.analog == true
	if analog then
		K:ring("GaugeBezel", frame * CFrame.new(0, 0, 0.012), r + 0.022, 0.03, 20, L.bezel)
	else
		K:ring("GaugeArc", frame * CFrame.new(0, 0, 0.004), r, 0.016, 18, L.ring, A1, A0)
	end
	local n = opt.ticks or 12
	for i = 0, n * 2 do
		local major = i % 2 == 0
		if major or analog then
			local v = i / (n * 2)
			local a = A0 + (A1 - A0) * v
			local len = if major then (if analog then 0.07 else 0.05) else 0.035
			local th = if major then 0.017 else 0.01
			local rr = r - (if analog then 0.014 else 0.04) - len / 2
			local look = if opt.red and v >= opt.red - 1e-6 then L.red else L.mark
			K:box("GaugeTick", Vector3.new(len, th, 0.006), frame * CFrame.new(math.cos(a) * rr, math.sin(a) * rr, 0.006) * CFrame.Angles(0, 0, a), look)
		end
	end
	-- 바늘: 피벗의 +X 를 가리키게 만든 뒤 0 위치로 돌림
	-- (디지털 계기판은 가운데에 숫자가 있으니 링 가장자리의 짧은 바늘만)
	local lcf = frame * CFrame.new(0, 0, 0.02)
	local p, w = K:pivot("NeedlePivot", lcf, function()
		if opt.short then
			K:box("Needle", Vector3.new(r * 0.4, 0.026, 0.008), lcf * CFrame.new(r * 0.74, 0, 0), L.needle)
		else
			K:box("Needle", Vector3.new(r * 0.98, 0.026, 0.008), lcf * CFrame.new(r * 0.37, 0, 0), L.needle)
			K:cyl("NeedleCap", 0.024, math.max(0.07, r * 0.42), lcf * CFrame.new(0, 0, 0.01) * ROT_X_TO_Z, L.cap)
		end
	end)
	local g = { pivot = p, weld = w, cf = lcf, cur = A0, max = opt.max or 1, base = K.base }
	Gauges.setNeedle(g, 0, 1)
	return g
end

-- 바늘 값 (k = 따라가는 비율 0..1)
function Gauges.setNeedle(g: any, value: number, k: number)
	local t = A0 + (A1 - A0) * math.clamp(value / g.max, 0, 1)
	local nxt = g.cur + (t - g.cur) * k
	if math.abs(nxt - g.cur) < 1e-4 and k < 1 then
		return
	end
	g.cur = nxt
	local cf = g.cf * CFrame.Angles(0, 0, nxt)
	if g.weld then
		g.weld.C0 = cf
	else
		g.pivot.CFrame = g.base.CFrame * cf
	end
end

---------------------------------------------------------------------------------------------- 7세그먼트
-- 세그먼트: a 위, b 오른쪽 위, c 오른쪽 아래, d 아래, e 왼쪽 아래, f 왼쪽 위, g 가운데
local SEG_ORDER = { "a", "b", "c", "d", "e", "f", "g" }
local MAP: { [string]: string } = {
	["0"] = "abcdef",
	["1"] = "bc",
	["2"] = "abdeg",
	["3"] = "abcdg",
	["4"] = "bcfg",
	["5"] = "acdfg",
	["6"] = "acdefg",
	["7"] = "abc",
	["8"] = "abcdefg",
	["9"] = "abcdfg",
	P = "abefg",
	R = "eg",
	N = "ceg",
	D = "bcdeg",
	["-"] = "g",
	[" "] = "",
}

-- 숫자 n 자리 (frame = 전체 가운데, +X 방향으로 나열, 높이 h). static 이면 그 글자의 켜진 세그먼트만 만듦.
function Gauges.digits(K: any, frame: CFrame, n: number, h: number, look: any, static: string?): any
	local W = 0.56 * h
	local t = 0.15 * h
	local pitch = W + 0.24 * h
	local out = { segs = {}, last = static, t = look.t or 0 }
	for i = 1, n do
		local cx = (i - (n + 1) / 2) * pitch
		local on = if static then (MAP[string.sub(static, i, i)] or "") else "abcdefg"
		local segs = {}
		for _, s in SEG_ORDER do
			if string.find(on, s, 1, true) then
				local horiz = s == "a" or s == "d" or s == "g"
				local x = if horiz then 0 elseif s == "b" or s == "c" then W / 2 - t / 2 else -W / 2 + t / 2
				local y = if s == "a" then h / 2 - t / 2 elseif s == "d" then -h / 2 + t / 2 elseif s == "g" then 0 elseif s == "b" or s == "f" then h / 4 else -h / 4
				local size = if horiz then Vector3.new(W - 1.5 * t, t, 0.006) else Vector3.new(t, h / 2 - 1.3 * t, 0.006)
				segs[s] = K:box("Seg", size, frame * CFrame.new(cx + x, y, 0), look)
			end
		end
		out.segs[i] = segs
	end
	if not static then
		Gauges.show(out, "0")
	end
	return out
end

-- 오른쪽 맞춤으로 표시
function Gauges.show(d: any, str: string)
	if d.last == str then
		return
	end
	d.last = str
	local n = #d.segs
	local pad = string.rep(" ", math.max(0, n - #str)) .. string.sub(str, -n)
	for i = 1, n do
		local on = MAP[string.sub(pad, i, i)] or ""
		for s, p in d.segs[i] do
			p.Transparency = if string.find(on, s, 1, true) then d.t else 1
		end
	end
end

-- 방향지시 화살표 (Neon 웨지 2장): dir = -1 왼쪽 / 1 오른쪽
function Gauges.arrow(K: any, frame: CFrame, dir: number, size: number, look: any): { BasePart }
	-- 웨지(직각삼각형 기둥)를 얇게 세워서 frame 의 XY 평면에 직각 꼭짓점이 왼쪽 아래인 삼각형으로: 위 · 아래 두 장 = ▶
	local toXY = CFrame.Angles(0, -math.pi / 2, 0)
	local m = if dir < 0 then CFrame.Angles(0, math.pi, 0) else CFrame.new()
	local sz = Vector3.new(0.006, size * 0.5, size)
	local a = K:wedge("TurnArrow", sz, frame * CFrame.new(0, size * 0.25, 0) * m * toXY, look)
	local b = K:wedge("TurnArrow", sz, frame * CFrame.new(0, -size * 0.25, 0) * m * CFrame.Angles(math.pi, 0, 0) * toXY, look)
	return { a, b }
end

return Gauges
