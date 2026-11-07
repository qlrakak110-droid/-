--!strict
-- SeoulSkylineClient / Traffic — 다리·강변도로 차량 불빛 흐름 (클라이언트 전용 파트)
--
--   맵 루트의 TrafficLanes 폴더 안 Configuration(차선)마다:
--     Count, P1..Pn (Vector3, 불빛 높이 포함 경로), Speed (stud/s), Density (대/100 stud), Kind "head"|"tail", Spacing (좌우 등 간격)
--   * 차선마다 결정적 "가상 차량" 배열(길이 × Density × 루트 TrafficDensity)을 만들고 위치는 시간의 함수로 계산 → 경로 끝에서 처음으로 순환.
--   * 실제 파트는 풀(최대 400개)에서 카메라 근처/화면 안 차량에만 배정. 한 번의 BindToRenderStep 루프에서
--     workspace:BulkMoveTo(..., FireCFrameChanged) 한 번으로 모두 이동(사용 안 하는 파트는 지하로 주차).
--   * 거리 LOD: 700 stud 안 = 전조등/후미등 2개(간격 = Spacing, 실측 1.4~2.0 m), 그 밖 = 한 덩어리 글레어,
--     2400 stud 밖 = 더 큰 글레어(원거리에서 화소 아래로 사라지지 않게). 멀수록 차량을 결정적으로 솎아내고,
--     예산을 넘으면 솎아내기 거리를 자동으로 줄임. 7000 stud 밖 차선은 건너뛰고, 2500 stud 밖 차선은 20 Hz 로 갱신.
--   * 루트 속성 ClientDebug = true 이면 2초마다 통계를 출력.

local RunService = game:GetService("RunService")
local Util = require(script.Parent.Util)

local Traffic = {}

local MAX_PARTS = 400
local FAR = 7000 -- 이보다 먼 차량/차선은 그리지 않음
local NEAR_PAIR = 700 -- 이보다 가까우면 등 2개
local BIG_GLARE = 2400 -- 이보다 멀면 큰 글레어
local SLOW_LANE = 2500 -- 카메라에서 이보다 먼 차선은 저빈도 갱신
local SLOW_DT = 0.05
local LOD_BASE = 1600 -- 이 거리 안 차량은 모두 표시(예산 초과 시 자동 축소)
local PARK = CFrame.new(0, -450, 0) -- 사용하지 않는 파트 주차 위치(지형 아래)
local STEP_NAME = "SeoulSkylineTraffic"

type Lane = {
	name: string,
	kind: number, -- 0 head, 1 tail
	speed: number,
	half: number, -- 등 간격 / 2
	pts: { Vector3 },
	cum: { number },
	dirs: { Vector3 },
	rots: { CFrame },
	nseg: number,
	len: number,
	minB: Vector3,
	maxB: Vector3,
	s0: { number },
	rank: { number },
	seg: { number },
	n: number,
	active: boolean,
	slow: boolean,
	nextSample: number,
	recPool: { number },
	recCF: { CFrame },
	recN: number,
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

local function parseLane(cfg: Instance, density: number): Lane?
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
	local cum, dirs, rots = { 0 }, {}, {}
	local minB, maxB = raw[1], raw[1]
	for k = 1, #raw - 1 do
		local d = raw[k + 1] - raw[k]
		local u = d.Unit
		dirs[k] = u
		rots[k] = if math.abs(u.Y) > 0.99 then CFrame.new() else CFrame.lookAt(Vector3.zero, u)
		cum[k + 1] = cum[k] + d.Magnitude
		minB = minB:Min(raw[k + 1])
		maxB = maxB:Max(raw[k + 1])
	end
	local len = cum[#raw]
	local kindAttr = cfg:GetAttribute("Kind")
	local speed = cfg:GetAttribute("Speed")
	local dens = cfg:GetAttribute("Density")
	local spacing = cfg:GetAttribute("Spacing")
	local sp = if typeof(spacing) == "number" then spacing else Util.m(1.6)
	sp = math.clamp(sp, Util.m(1.4), Util.m(2.0)) -- 실제 승용차 전조등 간격 1.4~2.0 m
	local lane: Lane = {
		name = cfg.Name,
		kind = if kindAttr == "tail" then 1 else 0,
		speed = if typeof(speed) == "number" then speed else 60,
		half = sp / 2,
		pts = raw,
		cum = cum,
		dirs = dirs,
		rots = rots,
		nseg = #raw - 1,
		len = len,
		minB = minB,
		maxB = maxB,
		s0 = {},
		rank = {},
		seg = {},
		n = 0,
		active = false,
		slow = false,
		nextSample = 0,
		recPool = {},
		recCF = {},
		recN = 0,
	}
	local perStud = (if typeof(dens) == "number" then dens else 1) / 100 * density
	local n = math.clamp(math.floor(len * perStud + 0.5), 0, 800)
	local rng = Random.new(Util.hash(cfg.Name) % 2147483647)
	for i = 1, n do
		lane.s0[i] = ((i - 1) + rng:NextNumber(-0.38, 0.38)) * len / n % len
		lane.rank[i] = rng:NextNumber()
		lane.seg[i] = 1
	end
	lane.n = n
	return lane
end

local function aabbDistance(p: Vector3, a: Vector3, b: Vector3): number
	local c = p:Max(a):Min(b)
	return (p - c).Magnitude
end

function Traffic.start(root: Model): () -> ()
	if root:GetAttribute("Traffic") == false then
		return function() end
	end

	local folder = Instance.new("Folder")
	folder.Name = "SeoulSkylineTraffic"
	folder.Parent = workspace

	local head = Util.color(root, "HeadlightColor", Util.Palette.Headlight)
	local tail = Util.color(root, "TaillightColor", Util.Palette.Taillight)
	-- 풀: (kind*3 + band), band 1 = 근거리 등 하나, 2 = 중거리 글레어(차 한 대), 3 = 원거리 글레어
	local lampSize = Vector3.new(Util.m(0.34), Util.m(0.2), Util.m(0.26))
	local glareSize = Vector3.new(Util.m(2.1), Util.m(0.4), Util.m(0.5))
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

	local lanes: { Lane } = {}
	local laneConns: { RBXScriptConnection } = {}
	local conns: { RBXScriptConnection } = {}
	local dirty = true
	local lanesFolder: Instance? = nil

	local function markDirty()
		dirty = true
	end

	local function rebuild()
		dirty = false
		Util.disconnectAll(laneConns)
		table.clear(lanes)
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
		for _, cfg in list do
			if cfg:IsA("Configuration") then
				table.insert(laneConns, cfg.AttributeChanged:Connect(markDirty))
				local lane = parseLane(cfg, density)
				if lane then
					table.insert(lanes, lane)
				end
			end
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

	local partsBuf: { BasePart } = {}
	local cfBuf: { CFrame } = {}
	local lastN = 0
	local lodScale = 1
	local nextLaneCheck = 0
	local nextPeak = 0
	local nextDebug = 0
	local rebuildAt = 0
	local t0 = os.clock()

	local function step()
		local now = os.clock()
		if dirty and now >= rebuildAt then
			rebuildAt = now + 0.5
			rebuild()
			nextLaneCheck = 0
		end
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local t = now - t0
		local ccf = cam.CFrame
		local cp = ccf.Position
		local look = ccf.LookVector
		local vp = cam.ViewportSize
		local aspect = vp.X / math.max(vp.Y, 1)
		local tanV = math.tan(math.rad(cam.FieldOfView) / 2)
		local cosCone = math.cos(math.min(math.atan(tanV * math.sqrt(1 + aspect * aspect)) + math.rad(6), math.pi * 0.49))

		if now >= nextLaneCheck then
			nextLaneCheck = now + 0.25
			for _, lane in lanes do
				local d = aabbDistance(cp, lane.minB, lane.maxB)
				lane.active = d < FAR and lane.n > 0
				lane.slow = d > SLOW_LANE
			end
		end

		for _, pool in pools do
			pool.used = 0
			pool.demand = 0
		end
		local lodNear = LOD_BASE * lodScale
		local n = 0
		local demand = 0
		for _, lane in lanes do
			if not lane.active then
				continue
			end
			if not lane.slow or now >= lane.nextSample then
				lane.nextSample = now + SLOW_DT
				local rn = 0
				local recPool, recCF = lane.recPool, lane.recCF
				local L, cum, dirs, pts, rots, nseg = lane.len, lane.cum, lane.dirs, lane.pts, lane.rots, lane.nseg
				local dist = lane.speed * t
				local half = lane.half
				local pbase = lane.kind * 3
				for i = 1, lane.n do
					local s = (lane.s0[i] + dist) % L
					local k = lane.seg[i]
					if s < cum[k] then
						k = 1
					end
					while k < nseg and s >= cum[k + 1] do
						k += 1
					end
					lane.seg[i] = k
					local pos = pts[k] + dirs[k] * (s - cum[k])
					local rel = pos - cp
					local d = rel.Magnitude
					if d > FAR or (d > 80 and rel:Dot(look) < d * cosCone) then
						continue
					end
					if d > lodNear and lane.rank[i] > math.max(0.04, (lodNear / d) ^ 1.2) then
						continue
					end
					local cf = rots[k] + pos
					if d < NEAR_PAIR then
						rn += 1
						recPool[rn] = pbase + 1
						recCF[rn] = cf * CFrame.new(-half, 0, 0)
						rn += 1
						recPool[rn] = pbase + 1
						recCF[rn] = cf * CFrame.new(half, 0, 0)
					else
						rn += 1
						recPool[rn] = pbase + (if d < BIG_GLARE then 2 else 3)
						recCF[rn] = cf
					end
				end
				lane.recN = rn
			end
			local recPool, recCF = lane.recPool, lane.recCF
			for r = 1, lane.recN do
				local pool = pools[recPool[r]]
				pool.demand += 1
				demand += 1
				local u = pool.used + 1
				local part = pool.parts[u] or grow(pool)
				if part then
					pool.used = u
					n += 1
					partsBuf[n] = part
					cfBuf[n] = recCF[r]
				end
			end
		end
		for _, pool in pools do
			for u = pool.used + 1, math.min(pool.lastUsed, #pool.parts) do
				n += 1
				partsBuf[n] = pool.parts[u]
				cfBuf[n] = PARK
			end
			pool.lastUsed = pool.used
			pool.peakAcc = math.max(pool.peakAcc, pool.demand)
		end
		for i = n + 1, lastN do
			partsBuf[i] = nil :: any
			cfBuf[i] = nil :: any
		end
		lastN = n
		if n > 0 then
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
			local cars, active = 0, 0
			for _, lane in lanes do
				cars += lane.n
				if lane.active then
					active += 1
				end
			end
			local first = pools[1].parts[1] or pools[2].parts[1] or pools[4].parts[1]
			print(string.format("[SeoulSkylineClient] traffic lanes=%d active=%d cars=%d parts=%d/%d shown=%d lod=%.2f first=%s", #lanes, active, cars, total, MAX_PARTS, n, lodScale, if first then tostring(first.Position) else "-"))
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
		table.clear(partsBuf)
		table.clear(cfBuf)
		folder:Destroy()
	end
end

return Traffic
