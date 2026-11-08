--!strict
-- SeoulSkylineClient / Traffic — 다리·강변도로·간선도로 교통 (클라이언트 전용 파트, 복제 비용 0)
--
--   맵 루트의 TrafficLanes 폴더 안 Configuration(차선)마다:
--     Count, P1..Pn (Vector3, 불빛 높이 포함 경로), Speed (stud/s), Density (대/100 stud), Kind "head"|"tail", Spacing,
--     (선택) LightHeight — 노면 → 불빛 높이(stud). 없으면 이름으로 추정(Bridge_* 0.75 m, 그 밖 0.7 m).
--
--   1) 차선 잇기: 끝점 → 다음 차선 시작점이 같은 방향·가로 4.5 stud 이내·앞쪽 220 stud 이내면 하나의 "체인"으로 이음
--      (다리 입구에서 끊긴 강변도로, 다리 ↔ 잠실대로). 차량은 체인을 따라 달리고 끝에서 처음으로 순환(새 차로 바뀜).
--   2) 차량 시뮬레이션(IDM 차간 거리 모델): 차마다 위치 s·속도 v, 희망 속도 = 구간 제한속도 × 차종 계수 × 개인 편차(±5 %).
--      최소 차간 2 m + 1.1 초 시간 간격, 앞차보다 느려지면 감속, 겹침 금지(하드 제약). 버스·화물은 바깥 차로에만, 더 느림.
--      초기 배치는 서버 시각(GetServerTimeNow) 기준 결정적 → 같은 순간에 접속한 클라이언트는 같은 교통을 봄.
--      카메라 SIM_NEAR 안의 차는 매 프레임, 그 밖은 FAR_EVERY 프레임마다(누적 dt) 갱신.
--   3) 신호 교차로: 서로 교차하는 체인(평면 교차, 높이 차 < 6 stud)을 자동 검출해 교차로마다 2현시 신호(70 초 주기,
--      황색 3 초, 전적색 2 초). 카메라가 교차로 1700 stud 안일 때만 작동(멀면 상시 녹색 → 원거리 정체 없음).
--      정지선은 첫 교차 차선 4.5 m 앞, 접근로마다 클라이언트 신호등(가로형 4구) 표시.
--   4) 표현 LOD (카메라 기준):
--      · full 차량 모델(Vehicles, ≈35~48 파트) — 가장 가까운 VehicleBudget(기본 70)대, FULL_RANGE(380 stud) 안
--      · lite 모델(≈10 파트) — 그다음 VehicleLiteBudget(110)대, VehicleRange(850 stud) 안
--      · 그 밖 = 기존 불빛 점(전조등/후미등 2개 → 글레어 → 큰 글레어, 400 파트 풀, 거리 솎아내기)
--      모델 차량도 밤에 260 stud 밖이면 불빛 점을 겹쳐 그려 원거리에서도 빛줄기가 끊기지 않음.
--      모든 모델·불빛·신호등은 프레임마다 workspace:BulkMoveTo(..., FireCFrameChanged) 한 번으로 이동.
--      모델은 차종·LOD 별 풀(Clone 은 처음 한 번), 풀 부족 시 다른 차종의 빈 모델을 재활용.
--      모바일(터치 전용)은 예산·거리 절반. 밤에는 가장 가까운 4대에만 실제 SpotLight(그림자 없음).
--   * 루트 속성: Traffic(false=끔), TrafficDensity, Vehicles(false=불빛만), VehicleBudget, VehicleLiteBudget,
--     VehicleRange, TrafficSignals(false=신호 없음), ClientDebug(true=2초마다 통계).

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local Util = require(script.Parent.Util)
local Vehicles = require(script.Parent.Vehicles)

local Traffic = {}

local function M(x: number): number
	return x / Util.METERS_PER_STUD
end

-- 불빛 점(원거리)
local MAX_PARTS = 400
local FAR = 7000 -- 이보다 먼 차량/차선은 그리지 않음
local NEAR_PAIR = 700 -- 이보다 가까우면 등 2개
local BIG_GLARE = 2400 -- 이보다 멀면 큰 글레어
local LOD_BASE = 1600 -- 이 거리 안 차량은 모두 표시(예산 초과 시 자동 축소)
local PARK = CFrame.new(0, -450, 0) -- 사용하지 않는 파트 주차 위치(지형 아래)
local STEP_NAME = "SeoulSkylineTraffic"
-- 실제 차량
local FULL_BUDGET = 70
local LITE_BUDGET = 110
local FULL_RANGE = 380
local LITE_RANGE = 850
local POOL_SLACK = 8 -- 예산 + 여유분까지 인스턴스 생성
local SIM_NEAR = 2000
local FAR_EVERY = 3
local GLARE_FROM = 260
local SPOTS = 4
local KEEP = 0.85 -- 이미 모델이 있는 차의 거리 가중(경계에서 깜빡임 방지)
-- IDM (stud, s)
local A_MAX = M(1.6)
local B_COMF = M(2.5)
local B_HARD = M(6.5)
local GAP0 = M(2.0)
local T_HEAD = 1.1
local SQRT_AB = math.sqrt(A_MAX * B_COMF)
local STOP_GAP = M(1.0)
local STOP_MARGIN = M(4.5)
local LOOK_STOP = M(130)
local BRAKE_ON, BRAKE_OFF = -M(0.9), -M(0.25)
-- 신호
local CYCLE = 70
local SIGNAL_ON, SIGNAL_OFF = 1700, 2100

type Info = Vehicles.Info
type Inst = Vehicles.Inst

type Junction = {
	center: Vector3,
	offset: number,
	active: boolean,
	state: { number }, -- [그룹] 0 녹 1 황 2 적
	heads: { { g: number, lamps: { BasePart }, shown: number } },
}

type Stop = { s: number, j: Junction, g: number }

type Rec = {
	inst: Inst,
	tier: number, -- 1 full, 2 lite
	typ: string,
	lane: any,
	i: number,
	stamp: number,
	ai: number, -- active 목록 위치
}

type Lane = {
	name: string,
	kind: number, -- 0 head, 1 tail
	half: number,
	lightH: number,
	pts: { Vector3 }, -- 노면 높이 경로
	cum: { number },
	dirs: { Vector3 },
	rots: { CFrame },
	spd: { number },
	nseg: number,
	len: number,
	minB: Vector3,
	maxB: Vector3,
	outer: boolean,
	dens: number,
	n: number,
	s: { number },
	v: { number },
	f: { number },
	typ: { string },
	inf: { Info },
	ident: { number },
	trip: { number },
	seg: { number },
	rank: { number },
	tl: { number },
	brake: { boolean },
	mdl: { Rec | false },
	wrapped: { boolean },
	fk: { number },
	fcf: { CFrame },
	stops: { Stop },
	active: boolean,
	w0: number,
	w1: number,
	w2: number,
	w3: number,
}

type Raw = {
	name: string,
	pts: { Vector3 },
	kind: number,
	speed: number,
	dens: number,
	half: number,
	lightH: number,
	outer: boolean,
}

type Pool = {
	parts: { BasePart },
	used: number,
	lastUsed: number,
	demand: number,
	peakAcc: number,
	peak: number,
	size: Vector3,
	color: Color3,
}

------------------------------------------------------------------------------------------------------
-- 차선 파싱 · 체인 잇기
------------------------------------------------------------------------------------------------------
local function parseRaw(cfg: Instance): Raw?
	local count = cfg:GetAttribute("Count")
	if typeof(count) ~= "number" or count < 2 then
		return nil
	end
	local raw: { Vector3 } = {}
	for i = 1, count do
		local p = cfg:GetAttribute("P" .. i)
		if typeof(p) ~= "Vector3" then
			return nil
		end
		if #raw == 0 or (p - raw[#raw]).Magnitude > 0.01 then
			table.insert(raw, p)
		end
	end
	if #raw < 2 then
		return nil
	end
	local kindAttr = cfg:GetAttribute("Kind")
	local speed = cfg:GetAttribute("Speed")
	local dens = cfg:GetAttribute("Density")
	local spacing = cfg:GetAttribute("Spacing")
	local lh = cfg:GetAttribute("LightHeight")
	local sp = if typeof(spacing) == "number" then spacing else M(1.6)
	sp = math.clamp(sp, M(1.4), M(2.0)) -- 실제 승용차 전조등 간격 1.4~2.0 m
	return {
		name = cfg.Name,
		pts = raw,
		kind = if kindAttr == "tail" then 1 else 0,
		speed = if typeof(speed) == "number" and speed > 1 then speed else 60,
		dens = if typeof(dens) == "number" then dens else 1,
		half = sp / 2,
		lightH = if typeof(lh) == "number" then lh elseif string.sub(cfg.Name, 1, 6) == "Bridge" then M(0.75) else M(0.7),
		outer = true,
	}
end

-- 같은 도로 묶음(이름의 차로 번호 앞부분)에서 번호가 가장 큰 차로 = 바깥 차로(버스·화물 허용)
local function markOuter(raws: { Raw })
	local maxK: { [string]: number } = {}
	local parsed: { [Raw]: { string | number } } = {}
	for _, r in raws do
		local prefix, k, rest = string.match(r.name, "^(.*%a)(%d+)(.*)$")
		if prefix and k then
			local key = prefix .. "|" .. (rest or "")
			local kn = tonumber(k) or 1
			parsed[r] = { key, kn }
			maxK[key] = math.max(maxK[key] or 0, kn)
		end
	end
	for _, r in raws do
		local p = parsed[r]
		if p then
			r.outer = (p[2] :: number) >= (maxK[p[1] :: string] or 0)
		end
	end
end

local function finishLane(name: string, members: { Raw }, density: number): Lane?
	local pts: { Vector3 } = {}
	local spd: { number } = {}
	for mi, r in members do
		local g: { Vector3 } = {}
		for _, p in r.pts do
			table.insert(g, p - Vector3.new(0, r.lightH, 0))
		end
		if mi == 1 then
			for k, p in g do
				table.insert(pts, p)
				if k > 1 then
					table.insert(spd, r.speed)
				end
			end
		else
			local last = pts[#pts]
			if (g[1] - last).Magnitude < 6 then
				pts[#pts] = (last + g[1]) / 2 -- 이음점(가로 어긋남 ≤ 6 stud)은 중간점 하나로
			else
				table.insert(pts, g[1]) -- 교차로를 건너는 빈 구간
				table.insert(spd, math.min(members[mi - 1].speed, r.speed))
			end
			for k = 2, #g do
				table.insert(pts, g[k])
				table.insert(spd, r.speed)
			end
		end
	end
	if #pts < 2 then
		return nil
	end
	local cum, dirs, rots = { 0 }, {}, {}
	local minB, maxB = pts[1], pts[1]
	for k = 1, #pts - 1 do
		local d = pts[k + 1] - pts[k]
		local u = d.Unit
		dirs[k] = u
		rots[k] = if math.abs(u.Y) > 0.99 then CFrame.new() else CFrame.lookAt(Vector3.zero, u)
		cum[k + 1] = cum[k] + d.Magnitude
		minB = minB:Min(pts[k + 1])
		maxB = maxB:Max(pts[k + 1])
	end
	local len = cum[#pts]
	local dsum, lsum = 0, 0
	local outer = false
	for _, r in members do
		local l = 0
		for k = 1, #r.pts - 1 do
			l += (r.pts[k + 1] - r.pts[k]).Magnitude
		end
		dsum += r.dens * l
		lsum += l
		outer = outer or r.outer
	end
	local first = members[1]
	return {
		name = name,
		kind = first.kind,
		half = first.half,
		lightH = first.lightH,
		pts = pts,
		cum = cum,
		dirs = dirs,
		rots = rots,
		spd = spd,
		nseg = #pts - 1,
		len = len,
		minB = minB,
		maxB = maxB,
		outer = outer,
		dens = (if lsum > 0 then dsum / lsum else 1) / 100 * density,
		n = 0,
		s = {},
		v = {},
		f = {},
		typ = {},
		inf = {},
		ident = {},
		trip = {},
		seg = {},
		rank = {},
		tl = {},
		brake = {},
		mdl = {},
		wrapped = {},
		fk = {},
		fcf = {},
		stops = {},
		active = false,
		w0 = 1,
		w1 = 0,
		w2 = 1,
		w3 = 0,
	}
end

local function buildChains(raws: { Raw }, density: number): { Lane }
	local succ: { [Raw]: Raw } = {}
	local hasPred: { [Raw]: boolean } = {}
	for _, a in raws do
		local na = #a.pts
		local aEnd = a.pts[na]
		local aDir = (aEnd - a.pts[na - 1]).Unit
		local best: Raw? = nil
		local bestScore = math.huge
		for _, b in raws do
			if b ~= a and not hasPred[b] and b.kind == a.kind then
				local bDir = (b.pts[2] - b.pts[1]).Unit
				if aDir:Dot(bDir) > 0.995 then
					local rel = b.pts[1] - aEnd
					local along = rel:Dot(aDir)
					local lat = (rel - aDir * along).Magnitude
					if along > -3 and along < 220 and lat < 4.5 then
						local sc = lat + math.abs(along) * 0.02
						if sc < bestScore then
							best, bestScore = b, sc
						end
					end
				end
			end
		end
		if best then
			succ[a] = best
			hasPred[best] = true
		end
	end
	local lanes: { Lane } = {}
	for _, a in raws do
		if not hasPred[a] then
			local members: { Raw } = {}
			local cur: Raw? = a
			while cur and #members <= #raws do
				table.insert(members, cur)
				cur = succ[cur]
			end
			local lane = finishLane(a.name, members, density)
			if lane then
				table.insert(lanes, lane)
			end
		end
	end
	return lanes
end

------------------------------------------------------------------------------------------------------
-- 교차로 검출 (평면 교차하는 체인 쌍)
------------------------------------------------------------------------------------------------------
type Cross = { lane: Lane, s: number, g: number, pos: Vector3 }

local function findJunctions(lanes: { Lane }): { Junction }
	local junctions: { Junction } = {}
	local jcross: { { Cross } } = {}
	local function addCross(pos: Vector3, c1: Cross, c2: Cross)
		for ji, j in junctions do
			local d = j.center - pos
			if Vector2.new(d.X, d.Z).Magnitude < 260 then
				table.insert(jcross[ji], c1)
				table.insert(jcross[ji], c2)
				return
			end
		end
		table.insert(junctions, { center = pos, offset = 0, active = false, state = { 0, 0 }, heads = {} })
		table.insert(jcross, { c1, c2 })
	end
	for ai = 1, #lanes do
		local A = lanes[ai]
		for bi = ai + 1, #lanes do
			local B = lanes[bi]
			if A.minB.X <= B.maxB.X + 5 and B.minB.X <= A.maxB.X + 5 and A.minB.Z <= B.maxB.Z + 5 and B.minB.Z <= A.maxB.Z + 5 then
				for ka = 1, A.nseg do
					local p, ua = A.pts[ka], A.dirs[ka]
					local la = A.cum[ka + 1] - A.cum[ka]
					for kb = 1, B.nseg do
						local ub = B.dirs[kb]
						if math.abs(ua.X * ub.X + ua.Z * ub.Z) < 0.6 then
							local q = B.pts[kb]
							local lb = B.cum[kb + 1] - B.cum[kb]
							local rx, rz = ua.X * la, ua.Z * la
							local sx, sz = ub.X * lb, ub.Z * lb
							local den = rx * sz - rz * sx
							if math.abs(den) > 1e-6 then
								local qpx, qpz = q.X - p.X, q.Z - p.Z
								local t = (qpx * sz - qpz * sx) / den
								local u = (qpx * rz - qpz * rx) / den
								if t >= 0 and t <= 1 and u >= 0 and u <= 1 then
									local pa = p + ua * (la * t)
									local pb = q + ub * (lb * u)
									if math.abs(pa.Y - pb.Y) < 6 then
										local ga = if math.abs(ua.X) >= math.abs(ua.Z) then 1 else 2
										local gb = if math.abs(ub.X) >= math.abs(ub.Z) then 1 else 2
										if ga ~= gb then
											addCross(pa, { lane = A, s = A.cum[ka] + la * t, g = ga, pos = pa }, { lane = B, s = B.cum[kb] + lb * u, g = gb, pos = pb })
										end
									end
								end
							end
						end
					end
				end
			end
		end
	end
	-- 차선마다 교차로별 첫 교차 지점 → 정지선
	for ji, j in junctions do
		j.offset = (ji - 1) * 23
		local first: { [Lane]: Cross } = {}
		for _, c in jcross[ji] do
			local f = first[c.lane]
			if not f or c.s < f.s then
				first[c.lane] = c
			end
		end
		for lane, c in first do
			table.insert(lane.stops, { s = math.max(0, c.s - STOP_MARGIN), j = j, g = c.g })
		end
	end
	return junctions
end

local function signalState(g: number, x: number): number
	if g == 1 then
		return if x < 38 then 0 elseif x < 41 then 1 else 2
	end
	return if x < 43 then 2 elseif x < 65 then 0 elseif x < 68 then 1 else 2
end

local function syncNow(): number
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	if ok and typeof(t) == "number" and t > 0 then
		return t
	end
	return os.clock()
end

------------------------------------------------------------------------------------------------------
-- 차량 정체성(차종·색·번호판·개인 속도 편차): 체인 이름 + 번호 + 순환 횟수 해시
------------------------------------------------------------------------------------------------------
local function assignIdentity(L: Lane, i: number)
	local h = Util.hash(L.name .. "#" .. i .. "#" .. L.trip[i])
	local u = (h % 100003) / 100003
	local t = Vehicles.pickType(u, L.outer)
	local inf = Vehicles.Info[t]
	L.typ[i] = t
	L.inf[i] = inf
	L.ident[i] = h
	local noise = ((h // 100003) % 1000) / 1000 - 0.5
	L.f[i] = (1 + noise * 0.10) * inf.speed
end

local function initCars(L: Lane, tSync: number, now: number)
	local maxN = math.floor(L.len / M(15))
	local n = math.clamp(math.floor(L.len * L.dens + 0.5), 0, math.min(800, maxN))
	local rng = Random.new(Util.hash(L.name) % 2147483647)
	local vBase = 0
	for k = 1, L.nseg do
		vBase += L.spd[k] * (L.cum[k + 1] - L.cum[k])
	end
	vBase /= math.max(L.len, 1)
	local shift = (vBase * 0.9 * tSync) % (L.len * 1000)
	for i = 1, n do
		local raw = ((i - 1) + rng:NextNumber(-0.25, 0.25)) * L.len / n + shift
		local trip = math.floor(raw / L.len)
		L.trip[i] = trip
		L.s[i] = raw - trip * L.len
		L.rank[i] = rng:NextNumber()
		L.seg[i] = 1
		L.tl[i] = now
		L.brake[i] = false
		L.mdl[i] = false
		L.wrapped[i] = false
		L.fk[i] = 0
		L.fcf[i] = PARK
		assignIdentity(L, i)
	end
	L.n = n
	for i = 1, n do
		local s = L.s[i]
		local k = 1
		while k < L.nseg and s >= L.cum[k + 1] do
			k += 1
		end
		L.seg[i] = k
		L.v[i] = L.spd[k] * L.f[i] * 0.95
	end
	-- 초기 겹침 해소(뒤로 밀기, 순환 순서 유지)
	if n > 1 then
		for _ = 1, 2 do
			for i = n, 1, -1 do
				local ld = if i == n then 1 else i + 1
				local d = L.s[ld] - L.s[i]
				if d < 0 then
					d += L.len
				end
				local need = L.inf[ld].rear + L.inf[i].front + GAP0
				if d < need then
					local s = L.s[i] - (need - d)
					if s < 0 then
						s += L.len
					end
					L.s[i] = s
				end
			end
		end
		for i = 1, n do
			local s = L.s[i]
			local k = 1
			while k < L.nseg and s >= L.cum[k + 1] do
				k += 1
			end
			L.seg[i] = k
		end
	end
end

------------------------------------------------------------------------------------------------------
-- IDM 한 스텝 (앞차 = i+1, 순환)
------------------------------------------------------------------------------------------------------
local function advance(L: Lane, i: number, dt: number)
	local n = L.n
	local S, V = L.s, L.v
	local s, v = S[i], V[i]
	local inf = L.inf[i]
	local len = L.len
	local gap, vl
	if n <= 1 then
		gap, vl = 1e9, v
	else
		local ld = if i == n then 1 else i + 1
		local d = S[ld] - s
		if d < 0 then
			d += len
		end
		gap = d - L.inf[ld].rear - inf.front
		vl = V[ld]
	end
	local k = L.seg[i]
	local v0 = L.spd[k] * L.f[i]
	local r = v / v0
	local r4 = r * r * r * r
	local ss = GAP0 + math.max(0, v * T_HEAD + v * (v - vl) / (2 * SQRT_AB))
	local q = ss / math.max(gap, 0.3)
	local acc = A_MAX * (1 - r4 - q * q)
	local stopAt = math.huge
	for _, st in L.stops do
		local state = st.j.state[st.g]
		if state ~= 0 then
			local ds = st.s - s - inf.front
			if ds < -len * 0.5 then
				ds += len
			end
			if ds > -0.3 and ds < LOOK_STOP then
				local dd = math.max(ds, 0.05)
				local need = v * v / (2 * dd)
				if v < 0.5 or need < (if state == 1 then B_COMF * 1.1 else B_HARD) then
					local s2 = STOP_GAP + v * T_HEAD + v * v / (2 * SQRT_AB)
					local q2 = s2 / dd
					local a2 = A_MAX * (1 - r4 - q2 * q2)
					if a2 < acc then
						acc = a2
					end
					if ds < stopAt then
						stopAt = ds
					end
				end
			end
		end
	end
	if acc < -B_HARD * 1.6 then
		acc = -B_HARD * 1.6
	end
	local vn = v + acc * dt
	if vn < 0 then
		vn = 0
	end
	local adv = (v + vn) * 0.5 * dt
	if adv > gap - 0.2 then
		adv = math.max(0, gap - 0.2)
		if vn > vl then
			vn = vl
		end
	end
	if adv > stopAt then
		adv = math.max(0, stopAt)
		vn = 0
	end
	s += adv
	if L.brake[i] then
		if acc > BRAKE_OFF and vn > 0.6 then
			L.brake[i] = false
		end
	elseif acc < BRAKE_ON or vn < 0.3 then
		L.brake[i] = true
	end
	if s >= len then
		s -= len
		k = 1
		L.trip[i] += 1
		assignIdentity(L, i)
		if L.mdl[i] then
			L.wrapped[i] = true
		end
	end
	local cum, nseg = L.cum, L.nseg
	while k < nseg and s >= cum[k + 1] do
		k += 1
	end
	L.seg[i] = k
	S[i] = s
	V[i] = vn
end

local function posAt(L: Lane, s: number, k: number): Vector3
	local cum, nseg = L.cum, L.nseg
	while k < nseg and s >= cum[k + 1] do
		k += 1
	end
	while k > 1 and s < cum[k] do
		k -= 1
	end
	return L.pts[k] + L.dirs[k] * (s - cum[k])
end

-- 앞/뒤 차축 위치로 자세 결정(경사·굽이를 자연스럽게 따라감)
local function carCF(L: Lane, s: number, k: number, wb: number): CFrame
	local sf, sr = s + wb * 0.5, s - wb * 0.5
	if sf > L.len then
		sr -= sf - L.len
		sf = L.len
	end
	if sr < 0 then
		sf -= sr
		sr = 0
	end
	local pf = posAt(L, sf, k)
	local pr = posAt(L, sr, k)
	local c = (pf + pr) * 0.5
	local f = pf - pr
	if f.Magnitude < 1e-3 then
		return L.rots[k] + c
	end
	return CFrame.lookAt(c, c + f)
end

local function aabbDistance(p: Vector3, a: Vector3, b: Vector3): number
	local c = p:Max(a):Min(b)
	return (p - c).Magnitude
end

-- 카메라 반경 R 안의 s 구간(최대 2개)을 lane.w0..w3 에 기록
local function nearWindow(L: Lane, cp: Vector3, R: number)
	local a0, a1, b0, b1 = 1, 0, 1, 0
	local R2 = R * R
	for k = 1, L.nseg do
		local A = L.pts[k]
		local u = L.dirs[k]
		local w = cp - A
		local t = w:Dot(u)
		local p2 = w:Dot(w) - t * t
		if p2 < R2 then
			local h = math.sqrt(R2 - p2)
			local segLen = L.cum[k + 1] - L.cum[k]
			local lo, hi = math.max(0, t - h), math.min(segLen, t + h)
			if lo <= hi then
				lo += L.cum[k]
				hi += L.cum[k]
				if a1 < a0 then
					a0, a1 = lo, hi
				elseif lo <= a1 + 1 then
					a1 = math.max(a1, hi)
				elseif b1 < b0 then
					b0, b1 = lo, hi
				else
					b1 = math.max(b1, hi)
				end
			end
		end
	end
	L.w0, L.w1, L.w2, L.w3 = a0, a1, b0, b1
end

------------------------------------------------------------------------------------------------------
-- 신호등(가로형 4구: 적·황·좌회전·녹) — 접근로마다 하나, 오른쪽 가장자리에서 차로 위로 뻗은 팔
------------------------------------------------------------------------------------------------------
local SIG_OFF = { Color3.fromRGB(60, 16, 14), Color3.fromRGB(64, 46, 10), Color3.fromRGB(14, 46, 22), Color3.fromRGB(14, 46, 22) }
local SIG_ON = { Color3.fromRGB(255, 40, 30), Color3.fromRGB(255, 180, 30), Color3.fromRGB(40, 255, 120), Color3.fromRGB(40, 255, 140) }

local function buildSignals(folder: Instance, junctions: { Junction }, lanes: { Lane })
	local function mk(name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, shape: Enum.PartType?): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = name == "SignalPole" or name == "SignalArm"
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		if shape then
			p.Shape = shape
		end
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = mat
		p.Parent = folder
		return p
	end
	for _, j in junctions do
		-- 접근로 = (그룹, 진행 방향 부호)
		local groups: { [string]: { { pos: Vector3, f: Vector3, g: number } } } = {}
		for _, L in lanes do
			for _, st in L.stops do
				if st.j == j then
					local k = 1
					while k < L.nseg and st.s >= L.cum[k + 1] do
						k += 1
					end
					local f = L.dirs[k]
					local pos = L.pts[k] + f * (st.s - L.cum[k])
					local key = st.g .. ":" .. (if st.g == 1 then math.sign(f.X) else math.sign(f.Z))
					groups[key] = groups[key] or {}
					table.insert(groups[key], { pos = pos, f = f, g = st.g })
				end
			end
		end
		for _, list in groups do
			local f = list[1].f
			local fh = Vector3.new(f.X, 0, f.Z).Unit
			local right = Vector3.new(-fh.Z, 0, fh.X)
			local rMax, rMin = -math.huge, math.huge
			local base = list[1].pos
			local yMax = -math.huge
			for _, e in list do
				local d = (e.pos - base):Dot(right)
				rMax = math.max(rMax, d)
				rMin = math.min(rMin, d)
				yMax = math.max(yMax, e.pos.Y)
			end
			local poleXZ = base + right * (rMax + M(2.6))
			local poleBase = Vector3.new(poleXZ.X, yMax, poleXZ.Z)
			local H = M(6.4)
			local armLen = (rMax - rMin) + M(2.6) + M(1.5)
			local rot = CFrame.lookAt(Vector3.zero, -fh) -- 신호등 정면(−Z)이 다가오는 차를 봄
			mk("SignalPole", Vector3.new(H + M(0.3), M(0.32), M(0.32)), CFrame.new(poleBase + Vector3.new(0, H / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(150, 154, 160), Enum.Material.Metal, Enum.PartType.Cylinder)
			local armMid = poleBase + Vector3.new(0, H, 0) - right * (armLen / 2)
			mk("SignalArm", Vector3.new(armLen, M(0.22), M(0.22)), CFrame.fromMatrix(armMid, right, Vector3.yAxis), Color3.fromRGB(150, 154, 160), Enum.Material.Metal)
			-- 신호기 하우징(오른쪽 2차로 위) + 4구
			local hc = poleBase + Vector3.new(0, H - M(0.45), 0) - right * (M(2.6) + (rMax - rMin) * 0.35)
			local hcf = CFrame.new(hc) * rot
			mk("SignalHead", Vector3.new(M(1.30), M(0.40), M(0.28)), hcf, Color3.fromRGB(28, 30, 32), Enum.Material.SmoothPlastic)
			local lamps: { BasePart } = {}
			for li = 1, 4 do
				local x = (li - 2.5) * M(0.31)
				local lp = mk("SignalLamp", Vector3.new(M(0.05), M(0.24), M(0.24)), hcf * CFrame.new(x, 0, -M(0.15)) * CFrame.Angles(0, math.pi / 2, 0), SIG_OFF[li], Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
				table.insert(lamps, lp)
			end
			table.insert(j.heads, { g = list[1].g, lamps = lamps, shown = -1 })
		end
	end
end

local function showSignal(head: { g: number, lamps: { BasePart }, shown: number }, state: number)
	if head.shown == state then
		return
	end
	head.shown = state
	local on = if state == 0 then 4 elseif state == 1 then 2 else 1
	for li, lp in head.lamps do
		local lit = li == on
		lp.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
		lp.Color = if lit then SIG_ON[li] else SIG_OFF[li]
	end
end

------------------------------------------------------------------------------------------------------
function Traffic.start(root: Model): () -> ()
	if root:GetAttribute("Traffic") == false then
		return function() end
	end

	local folder = Instance.new("Folder")
	folder.Name = "SeoulSkylineTraffic"
	folder.Parent = workspace
	local carFolder = Instance.new("Folder")
	carFolder.Name = "Vehicles"
	carFolder.Parent = folder
	local sigFolder = Instance.new("Folder")
	sigFolder.Name = "Signals"
	sigFolder.Parent = folder

	local mobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local function attrNum(name: string, default: number): number
		local v = root:GetAttribute(name)
		return if typeof(v) == "number" then v else default
	end
	local scale = if mobile then 0.5 else 1
	local vehiclesOn = root:GetAttribute("Vehicles") ~= false
	local fullBudget = if vehiclesOn then math.floor(attrNum("VehicleBudget", FULL_BUDGET) * scale) else 0
	local liteBudget = if vehiclesOn then math.floor(attrNum("VehicleLiteBudget", LITE_BUDGET) * scale) else 0
	local liteRange = attrNum("VehicleRange", LITE_RANGE) * (if mobile then 0.75 else 1)
	local fullRange = math.min(FULL_RANGE * (if mobile then 0.75 else 1), liteRange)
	local signalsOn = root:GetAttribute("TrafficSignals") ~= false

	local head = Util.color(root, "HeadlightColor", Util.Palette.Headlight)
	local tail = Util.color(root, "TaillightColor", Util.Palette.Taillight)
	-- 불빛 풀: (kind*3 + band), band 1 = 근거리 등 하나, 2 = 중거리 글레어(차 한 대), 3 = 원거리 글레어
	local lampSize = Vector3.new(M(0.34), M(0.2), M(0.26))
	local glareSize = Vector3.new(M(2.1), M(0.4), M(0.5))
	local pools: { Pool } = {}
	for kind = 0, 1 do
		for band = 1, 3 do
			pools[kind * 3 + band] = {
				parts = {},
				used = 0,
				lastUsed = 0,
				demand = 0,
				peakAcc = 0,
				peak = 0,
				size = if band == 1 then lampSize elseif band == 2 then glareSize else glareSize * 1.8,
				color = if kind == 0 then head else tail,
			}
		end
	end
	local total = 0

	local function style(p: BasePart, pool: Pool)
		p.Size = pool.size
		p.Color = pool.color
	end

	local function grow(pool: Pool): BasePart?
		if total < MAX_PARTS then
			local p = Instance.new("Part")
			p.Name = "CarLight"
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.Material = Enum.Material.Neon
			p.TopSurface = Enum.SurfaceType.Smooth
			p.BottomSurface = Enum.SurfaceType.Smooth
			style(p, pool)
			p.CFrame = PARK
			p.Parent = folder
			total += 1
			table.insert(pool.parts, p)
			return p
		end
		-- 예산 소진: 최근 1초간 여유가 있던 풀에서 주차 중인 파트를 빌려옴
		for _, donor in pools do
			if donor ~= pool and #donor.parts > math.max(donor.peak, donor.used, donor.lastUsed) + 1 then
				local p = table.remove(donor.parts) :: BasePart
				style(p, pool)
				table.insert(pool.parts, p)
				return p
			end
		end
		return nil
	end

	-- 실제 SpotLight(가장 가까운 차 SPOTS 대, 밤에만)
	local spots: { { part: BasePart, light: SpotLight, used: boolean } } = {}
	for _ = 1, SPOTS do
		local p = Instance.new("Part")
		p.Name = "HeadlightBeam"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Transparency = 1
		p.Size = Vector3.new(0.2, 0.2, 0.2)
		p.CFrame = PARK
		local l = Instance.new("SpotLight")
		l.Face = Enum.NormalId.Front
		l.Angle = 70
		l.Range = 60
		l.Brightness = 2.4
		l.Color = Color3.fromRGB(255, 238, 210)
		l.Shadows = false
		l.Enabled = false
		l.Parent = p
		p.Parent = folder
		table.insert(spots, { part = p, light = l, used = false })
	end

	-- 차량 모델 풀
	local free: { [string]: { Rec } } = {}
	local live = { 0, 0 }
	local activeRecs: { Rec } = {}
	local budgets = { fullBudget, liteBudget }

	local partsBuf: { BasePart } = {}
	local cfBuf: { CFrame } = {}
	local nBuf = 0
	local function push(p: BasePart, cf: CFrame)
		nBuf += 1
		partsBuf[nBuf] = p
		cfBuf[nBuf] = cf
	end

	local function release(rec: Rec)
		local L = rec.lane
		if L and L.mdl[rec.i] == rec then
			L.mdl[rec.i] = false
		end
		rec.lane = nil
		for _, p in rec.inst.parts do
			push(p, PARK)
		end
		-- active 목록에서 swap-remove
		local ai = rec.ai
		local last = activeRecs[#activeRecs]
		activeRecs[ai] = last
		last.ai = ai
		activeRecs[#activeRecs] = nil
		rec.ai = 0
		local key = rec.typ .. rec.tier
		free[key] = free[key] or {}
		table.insert(free[key], rec)
	end

	local function acquire(typ: string, tier: number): Rec?
		local key = typ .. tier
		local list = free[key]
		if list and #list > 0 then
			return table.remove(list)
		end
		if live[tier] < budgets[tier] + POOL_SLACK then
			live[tier] += 1
			local inst = Vehicles.new(typ, tier == 2, carFolder)
			return { inst = inst, tier = tier, typ = typ, lane = nil, i = 0, stamp = 0, ai = 0 }
		end
		-- 다른 차종의 빈 모델을 하나 버리고 새로 만듦
		for k, l in free do
			if #l > 0 and string.sub(k, -1) == tostring(tier) then
				local old = table.remove(l) :: Rec
				old.inst.model:Destroy()
				local inst = Vehicles.new(typ, tier == 2, carFolder)
				return { inst = inst, tier = tier, typ = typ, lane = nil, i = 0, stamp = 0, ai = 0 }
			end
		end
		return nil
	end

	-- 차선/체인/교차로
	local lanes: { Lane } = {}
	local junctions: { Junction } = {}
	local laneConns: { RBXScriptConnection } = {}
	local conns: { RBXScriptConnection } = {}
	local dirty = true
	local lanesFolder: Instance? = nil

	local function markDirty()
		dirty = true
	end

	local function clearModels()
		for idx = #activeRecs, 1, -1 do
			release(activeRecs[idx])
		end
	end

	local function rebuild()
		dirty = false
		Util.disconnectAll(laneConns)
		clearModels()
		table.clear(lanes)
		table.clear(junctions)
		sigFolder:ClearAllChildren()
		local f = lanesFolder
		if not f then
			return
		end
		local td = root:GetAttribute("TrafficDensity")
		local density = if typeof(td) == "number" then math.clamp(td, 0, 4) else 1
		local list = f:GetChildren()
		table.sort(list, function(a, b)
			return a.Name < b.Name
		end)
		local raws: { Raw } = {}
		for _, cfg in list do
			if cfg:IsA("Configuration") then
				table.insert(laneConns, cfg.AttributeChanged:Connect(markDirty))
				local r = parseRaw(cfg)
				if r then
					table.insert(raws, r)
				end
			end
		end
		markOuter(raws)
		for _, L in buildChains(raws, density) do
			table.insert(lanes, L)
		end
		if signalsOn then
			for _, j in findJunctions(lanes) do
				table.insert(junctions, j)
			end
			buildSignals(sigFolder, junctions, lanes)
		end
		local tSync, now = syncNow(), os.clock()
		for _, L in lanes do
			initCars(L, tSync, now)
		end
	end

	local function hookFolder(f: Instance)
		if lanesFolder == f then
			return
		end
		lanesFolder = f
		table.insert(conns, f.ChildAdded:Connect(markDirty))
		table.insert(conns, f.ChildRemoved:Connect(markDirty))
		dirty = true
	end
	local existing = root:FindFirstChild("TrafficLanes")
	if existing then
		hookFolder(existing)
	end
	table.insert(conns, root.ChildAdded:Connect(function(c)
		if c.Name == "TrafficLanes" then
			hookFolder(c)
		end
	end))
	table.insert(conns, root:GetAttributeChangedSignal("TrafficDensity"):Connect(markDirty))

	-- 후보(모델 배정) 버퍼
	local cL: { Lane } = {}
	local cI: { number } = {}
	local cD: { number } = {}
	local cR: { number } = {}
	local cOrder: { number } = {}
	local nCand = 0

	local lastN = 0
	local lodScale = 1
	local nextLaneCheck = 0
	local nextPeak = 0
	local nextDebug = 0
	local nextNight = 0
	local night = true
	local rebuildAt = 0
	local frame = 0
	local dbgModels = { 0, 0 }

	local function step()
		local now = os.clock()
		frame += 1
		if dirty and now >= rebuildAt then
			rebuildAt = now + 0.5
			rebuild()
			nextLaneCheck = 0
		end
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		if now >= nextNight then
			nextNight = now + 1
			local forced = root:GetAttribute("Night")
			if typeof(forced) == "boolean" then
				night = forced
			else
				local ct = Lighting.ClockTime
				night = ct >= 17.6 or ct < 6.4
			end
		end
		local ccf = cam.CFrame
		local cp = ccf.Position
		local look = ccf.LookVector
		local vp = cam.ViewportSize
		local aspect = vp.X / math.max(vp.Y, 1)
		local tanV = math.tan(math.rad(cam.FieldOfView) / 2)
		local halfDiag = math.atan(tanV * math.sqrt(1 + aspect * aspect))
		local cosCone = math.cos(math.min(halfDiag + math.rad(6), math.pi * 0.49))
		local cosConeM = math.cos(math.min(halfDiag + math.rad(14), math.pi * 0.49))

		if now >= nextLaneCheck then
			nextLaneCheck = now + 0.25
			for _, L in lanes do
				L.active = L.n > 0 and aabbDistance(cp, L.minB, L.maxB) < FAR
			end
			-- 신호 작동 여부(카메라 근처 교차로만)
			for _, j in junctions do
				local d = (j.center - cp).Magnitude
				if j.active and d > SIGNAL_OFF then
					j.active = false
				elseif not j.active and d < SIGNAL_ON then
					j.active = true
				end
			end
		end
		if #junctions > 0 then
			local ts = syncNow()
			for _, j in junctions do
				if j.active then
					local x = (ts + j.offset) % CYCLE
					j.state[1] = signalState(1, x)
					j.state[2] = signalState(2, x)
				else
					j.state[1] = 0
					j.state[2] = 0
				end
				for _, hd in j.heads do
					showSignal(hd, j.state[hd.g])
				end
			end
		end

		for _, pool in pools do
			pool.used = 0
			pool.demand = 0
		end
		nBuf = 0
		nCand = 0
		local lodNear = LOD_BASE * lodScale
		local demand = 0
		local modelsOn = fullBudget + liteBudget > 0

		-- 불빛 점 기록 → 풀 파트 배정
		local function emit(poolIdx: number, cf: CFrame)
			local pool = pools[poolIdx]
			pool.demand += 1
			demand += 1
			local u = pool.used + 1
			local part = pool.parts[u] or grow(pool)
			if part then
				pool.used = u
				push(part, cf)
			end
		end
		local function emitDots(L: Lane, cf: CFrame, d: number, half: number)
			local pbase = L.kind * 3
			if d < NEAR_PAIR then
				emit(pbase + 1, cf * CFrame.new(-half, 0, 0))
				emit(pbase + 1, cf * CFrame.new(half, 0, 0))
			else
				emit(pbase + (if d < BIG_GLARE then 2 else 3), cf)
			end
		end

		for _, L in lanes do
			if not L.active then
				continue
			end
			nearWindow(L, cp, SIM_NEAR)
			local w0, w1, w2, w3 = L.w0, L.w1, L.w2, L.w3
			local S, TL, FK, FCF = L.s, L.tl, L.fk, L.fcf
			local lightUp = Vector3.new(0, L.lightH, 0)
			local half = L.half
			local pbase = L.kind * 3
			for i = 1, L.n do
				local s = S[i]
				if (s >= w0 and s <= w1) or (s >= w2 and s <= w3) then
					-- 근거리: 매 프레임 시뮬레이션 + 표현
					local dt = now - TL[i]
					if dt > 0.3 then
						dt = 0.3
					end
					TL[i] = now
					if dt > 0 then
						advance(L, i, dt)
					end
					FK[i] = 0
					local k = L.seg[i]
					local pos = L.pts[k] + L.dirs[k] * (L.s[i] - L.cum[k])
					local rel = pos - cp
					local d = rel.Magnitude
					local has = L.mdl[i]
					local inCone = d < 40 or rel:Dot(look) >= d * cosConeM
					if modelsOn and d < liteRange * 1.08 and inCone then
						nCand += 1
						cL[nCand] = L
						cI[nCand] = i
						cR[nCand] = d
						cD[nCand] = if has then d * KEEP else d
						continue
					end
					if d > FAR or (d > 80 and rel:Dot(look) < d * cosCone) then
						continue
					end
					if d > lodNear and L.rank[i] > math.max(0.04, (lodNear / d) ^ 1.2) then
						continue
					end
					emitDots(L, L.rots[k] + (pos + lightUp), d, half)
				else
					-- 원거리: FAR_EVERY 프레임마다 갱신, 사이 프레임은 기록 재사용
					if (i + frame) % FAR_EVERY == 0 then
						local dt = math.min(now - TL[i], 1)
						TL[i] = now
						while dt > 0 do
							local h = math.min(dt, 0.3)
							advance(L, i, h)
							dt -= h
						end
						FK[i] = 0
						local k = L.seg[i]
						local pos = L.pts[k] + L.dirs[k] * (L.s[i] - L.cum[k])
						local rel = pos - cp
						local d = rel.Magnitude
						if d > FAR or (d > 80 and rel:Dot(look) < d * cosCone) then
							continue
						end
						if d > lodNear and L.rank[i] > math.max(0.04, (lodNear / d) ^ 1.2) then
							continue
						end
						local pidx = pbase + (if d < BIG_GLARE then 2 else 3)
						if d < NEAR_PAIR then
							pidx = pbase + 2
						end
						FK[i] = pidx
						FCF[i] = L.rots[k] + (pos + lightUp)
						emit(pidx, FCF[i])
					elseif FK[i] ~= 0 then
						emit(FK[i], FCF[i])
					end
				end
			end
		end

		-- 모델 배정: 가까운 순
		for m = 1, nCand do
			cOrder[m] = m
		end
		for m = nCand + 1, #cOrder do
			cOrder[m] = nil
		end
		table.sort(cOrder, function(a, b)
			return cD[a] < cD[b]
		end)
		local usedT = { 0, 0 }
		local spotN = 0
		for _, m in cOrder do
			local L, i, d = cL[m], cI[m], cR[m]
			local tier = 0
			if d < fullRange and usedT[1] < fullBudget then
				tier = 1
			elseif d < liteRange and usedT[2] < liteBudget then
				tier = 2
			end
			local rec = L.mdl[i]
			if rec and (rec.tier ~= tier or rec.typ ~= L.typ[i] or L.wrapped[i]) then
				release(rec)
				rec = false
			end
			L.wrapped[i] = false
			if tier > 0 and not rec then
				local got = acquire(L.typ[i], tier)
				if got then
					got.lane = L
					got.i = i
					table.insert(activeRecs, got)
					got.ai = #activeRecs
					L.mdl[i] = got
					rec = got
				end
			end
			local k = L.seg[i]
			if rec then
				usedT[tier] += 1
				rec.stamp = frame
				local inst = rec.inst
				local inf = L.inf[i]
				Vehicles.dress(inst, L.ident[i])
				Vehicles.setLights(inst, night, L.brake[i], true)
				local cf = carCF(L, L.s[i], k, inf.wheelbase)
				local parts, offs = inst.parts, inst.offs
				for j = 1, #parts do
					push(parts[j], cf * offs[j])
				end
				if night then
					if tier == 1 and spotN < SPOTS then
						spotN += 1
						local sp = spots[spotN]
						sp.used = true
						push(sp.part, cf * CFrame.new(0, inf.headY, -inf.front - 0.5))
					end
					if d > GLARE_FROM then
						local zOff = if L.kind == 0 then -inf.front - 0.1 else inf.rear + 0.1
						local y = if L.kind == 0 then inf.headY else inf.tailY
						emitDots(L, cf * CFrame.new(0, y, zOff), d, inf.lampHalf)
					end
				end
			else
				local pos = L.pts[k] + L.dirs[k] * (L.s[i] - L.cum[k])
				emitDots(L, L.rots[k] + (pos + Vector3.new(0, L.lightH, 0)), d, L.half)
			end
		end
		-- 이번 프레임에 선택되지 않은 모델 반납
		for idx = #activeRecs, 1, -1 do
			local rec = activeRecs[idx]
			if rec.stamp ~= frame then
				release(rec)
			end
		end
		dbgModels[1], dbgModels[2] = usedT[1], usedT[2]
		for si, sp in spots do
			local on = si <= spotN
			if sp.light.Enabled ~= on then
				sp.light.Enabled = on
			end
			if not on and sp.used then
				sp.used = false
				push(sp.part, PARK)
			end
		end

		for _, pool in pools do
			for u = pool.used + 1, math.min(pool.lastUsed, #pool.parts) do
				push(pool.parts[u], PARK)
			end
			pool.lastUsed = pool.used
			pool.peakAcc = math.max(pool.peakAcc, pool.demand)
		end
		for idx = nBuf + 1, lastN do
			partsBuf[idx] = nil :: any
			cfBuf[idx] = nil :: any
		end
		lastN = nBuf
		if nBuf > 0 then
			workspace:BulkMoveTo(partsBuf, cfBuf, Enum.BulkMoveMode.FireCFrameChanged)
		end

		-- 예산 피드백: 수요가 예산을 넘으면 "전부 표시" 거리를 줄이고, 여유가 있으면 천천히 되돌림
		if demand > MAX_PARTS then
			lodScale = math.max(0.08, lodScale * 0.97)
		elseif demand < MAX_PARTS * 0.8 and lodScale < 1 then
			lodScale = math.min(1, lodScale * 1.01)
		end
		if now >= nextPeak then
			nextPeak = now + 1
			for _, pool in pools do
				pool.peak = pool.peakAcc
				pool.peakAcc = 0
			end
		end
		if now >= nextDebug and root:GetAttribute("ClientDebug") == true then
			nextDebug = now + 2
			local cars, active, stopped = 0, 0, 0
			for _, L in lanes do
				cars += L.n
				if L.active then
					active += 1
				end
				for i = 1, L.n do
					if L.v[i] < 0.5 then
						stopped += 1
					end
				end
			end
			local sig = {}
			for _, j in junctions do
				table.insert(sig, string.format("%s%d%d", if j.active then "*" else "-", j.state[1], j.state[2]))
			end
			print(string.format("[SeoulSkylineClient] traffic lanes=%d active=%d cars=%d stopped=%d dots=%d/%d models full=%d lite=%d live=%d/%d moved=%d lod=%.2f night=%s junctions=%s", #lanes, active, cars, stopped, total, MAX_PARTS, dbgModels[1], dbgModels[2], live[1], live[2], nBuf, lodScale, tostring(night), table.concat(sig, ",")))
		end
	end

	RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Camera.Value + 2, step)

	return function()
		pcall(function()
			RunService:UnbindFromRenderStep(STEP_NAME)
		end)
		Util.disconnectAll(conns)
		Util.disconnectAll(laneConns)
		table.clear(lanes)
		table.clear(junctions)
		table.clear(activeRecs)
		table.clear(free)
		table.clear(partsBuf)
		table.clear(cfBuf)
		folder:Destroy()
	end
end

return Traffic
