--!strict
-- SeoulSkyline / Streetscape
-- 잠실대교 일대의 실제 도로 안내 체계(외부). Signage 라이브러리로 만들고, 앞서 빌드된 지오메트리(도로·분리대·가로등·
-- 다리 상판·나무)를 직접 읽어 기둥이 겹치지 않는 자리에 실측 규칙대로 세움. MODULES 마지막에 빌드(발자국 예약 안 함).
--
--   좌표 감각: 강 = X 축, 먼 쪽(-Z) = 잠실·송파(남안), 가까운 쪽(+Z) = 자양·구의(북안). 해가 지는 -X = 서쪽(여의도·김포),
--   +X = 동쪽(천호·하남·구리). 우측통행: +X 로 가는 차는 +Z 쪽 차로, 다리에서 -Z 로 가는 차는 +X 쪽 차로.
--
--   * 문형 표지(녹색, 도시고속도로): 올림픽대로 동행(강 쪽 차로)·서행(도시 쪽), 강변북로 서행(강 쪽)·동행(도시 쪽) —
--     다리 입구 약 300 m 전, 중앙 쌍가로등 사이(38 m 간격의 중간). 중앙분리대 위 기둥 + 방호벽/방음벽 바깥 기둥,
--     표지 하단 5.2 m(≥ 4.7 m), 차로 묶음 위에 판 배치(안쪽 1~2 차로 = 직진, 바깥 = 진출).
--   * 다리 위 문형 표지(청색, 일반도로): 남행(잠실 쪽, 진행 우측 +X 차로) z ≈ -540, 북행 z ≈ +560 — 교명 가로등 사이.
--     직진 / 좌회전 / 우회전 3 판(올림픽대로·강변북로 노선명 상자).
--   * 교명주 4 기(화강석 + 청동판 "잠실대교" / "JAMSIL BRIDGE" / 준공 "1972. 7." / "한강"), 다리 양끝 보도.
--   * "한강 Hangang River" 하천 표지(다리 양끝, 진행 우측 보도), 거리표(km, 강 쪽 방호벽 위 100 m 마다),
--     이정표(3 행: 다리 지난 뒤), 관광지(갈색) 표지 "잠실한강공원", 공원 안내도 + 보행 이정 기둥(공원 다리 옆 잔디).
--   * 도로명판: 다리 남단 "송파대로 Songpa-daero 1→740", 북단 "자양로 Jayang-ro 1→302" (교차로 모서리 보도).
--   * 버스정류소(북단 자양로 서쪽 보도): 쉘터(지붕·유리·광고 라이트박스·벤치·BIS 도착 안내기·정류소 이름띠) + 표지 기둥.
--   파트 ≈ 1,300 (≤ 1,500). 실제 광원 2 (버스 쉘터).

local Config = require(script.Parent.Config)
local Kit = require(script.Parent.Kit)
local Signage = require(script.Parent.Signage)

local Streetscape = {}

local rgb = Color3.fromRGB
local m = Config.m
local L = Config.Level
local F, N, B = Config.FarBank, Config.NearBank, Config.Bridge
local MAT = Enum.Material
local at = Signage.at
local SC = Signage.Colors

-- Riverside 제방 고속화도로 단면(강 쪽 가장자리에서 도시 쪽으로 u, m) — Riverside.luau XS 와 같은 값
local XS = { parapet = { 0, 0.5 }, carA = { 1.5, 15.5 }, median = { 16.0, 16.8 }, carB = { 17.3, 31.3 }, wall = { 32.3, 32.8 } }
local LANE = 3.5
local MEDIAN_H = m(0.9)
local PARAPET_H = m(1.0)
local LAMP_PITCH = m(38)
-- Bridge 단면(m): 분리대 반폭 1, 차로 4 × 3.5, 보도 연석 0.25, 가장자리보(난간 기초) 0.5 m, 기초 윗면 0.65 m
local HALF_W = B.Width / 2
local EDGE_X = HALF_W - m(0.5) / 2
local FASCIA_TOP = m(0.65)
local WALK_TOP = m(0.25)
local CURB_X = m(1 + 4 * 3.5)

------------------------------------------------------------------------------------------------------
-- 기존 지오메트리 탐색(충돌 회피 + 표면 높이)
------------------------------------------------------------------------------------------------------
local CELL = 32
type Probe = { cells: { [number]: { BasePart } }, big: { BasePart } }
local probe: Probe = { cells = {}, big = {} }

local function ckey(ix: number, iz: number): number
	return (ix + 40000) * 100000 + (iz + 40000)
end

local function halfExtent(p: BasePart): Vector3
	local cf, s = p.CFrame, p.Size
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	return Vector3.new(
		math.abs(r.X) * s.X / 2 + math.abs(u.X) * s.Y / 2 + math.abs(l.X) * s.Z / 2,
		math.abs(r.Y) * s.X / 2 + math.abs(u.Y) * s.Y / 2 + math.abs(l.Y) * s.Z / 2,
		math.abs(r.Z) * s.X / 2 + math.abs(u.Z) * s.Y / 2 + math.abs(l.Z) * s.Z / 2
	)
end

local function buildProbe(root: Instance, skip: Instance)
	probe = { cells = {}, big = {} }
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.95 and not d:IsDescendantOf(skip) then
			local he = halfExtent(d)
			local c = d.Position
			if he.X > 160 or he.Z > 160 then
				table.insert(probe.big, d)
			else
				for ix = math.floor((c.X - he.X) / CELL), math.floor((c.X + he.X) / CELL) do
					for iz = math.floor((c.Z - he.Z) / CELL), math.floor((c.Z + he.Z) / CELL) do
						local k = ckey(ix, iz)
						local t = probe.cells[k]
						if not t then
							t = {}
							probe.cells[k] = t
						end
						table.insert(t, d)
					end
				end
			end
		end
	end
end

local function inside(p: BasePart, q: Vector3, margin: number): boolean
	local l = p.CFrame:PointToObjectSpace(q)
	local s = p.Size / 2 + Vector3.new(margin, margin, margin)
	if math.abs(l.X) > s.X or math.abs(l.Y) > s.Y or math.abs(l.Z) > s.Z then
		return false
	end
	if p:FindFirstChildOfClass("SpecialMesh") then
		local e = (l.X / s.X) ^ 2 + (l.Y / s.Y) ^ 2 + (l.Z / s.Z) ^ 2
		return e <= 1
	end
	if p:IsA("Part") then
		local sh = (p :: Part).Shape
		if sh == Enum.PartType.Cylinder then
			return (l.Y * l.Y + l.Z * l.Z) <= (math.min(s.Y, s.Z)) ^ 2
		elseif sh == Enum.PartType.Ball then
			return l.Magnitude <= s.X
		end
	end
	return true
end

local function candidates(q: Vector3): { BasePart }
	local t = probe.cells[ckey(math.floor(q.X / CELL), math.floor(q.Z / CELL))]
	return t or {}
end

-- 점들 중 하나라도 기존 파트 속이면 그 파트를 반환
local function blocked(points: { Vector3 }, ignore: { [string]: boolean }?, margin: number?): BasePart?
	local mg = margin or 0.25
	for _, q in points do
		for _, p in candidates(q) do
			if not (ignore and ignore[p.Name]) and inside(p, q, mg) then
				return p
			end
		end
		for _, p in probe.big do
			if not (ignore and ignore[p.Name]) and inside(p, q, mg) then
				return p
			end
		end
	end
	return nil
end

-- (x, z) 의 가장 높은 윗면(yMax 이하). 지형은 파트가 아니므로 없으면 nil
local function surfaceY(x: number, z: number, yMax: number, ignore: { [string]: boolean }?): number?
	local best: number? = nil
	local function test(p: BasePart)
		if ignore and ignore[p.Name] then
			return
		end
		if p:FindFirstChildOfClass("SpecialMesh") or p:IsA("WedgePart") or p:IsA("CornerWedgePart") then
			return
		end
		local cf, s = p.CFrame, p.Size
		local axes = { { cf.RightVector, s.X }, { cf.UpVector, s.Y }, { cf.LookVector, s.Z } }
		local n, h = Vector3.yAxis, 0
		local bestY = -1
		for _, a in axes do
			local v = a[1] :: Vector3
			if math.abs(v.Y) > bestY then
				bestY = math.abs(v.Y)
				n = if v.Y >= 0 then v else -v
				h = (a[2] :: number) / 2
			end
		end
		if n.Y < 0.5 then
			return
		end
		local c = cf.Position
		local y = c.Y + (h - n.X * (x - c.X) - n.Z * (z - c.Z)) / n.Y
		if y > yMax then
			return
		end
		if inside(p, Vector3.new(x, y - 0.05, z), 0.01) and (best == nil or y > (best :: number)) then
			best = y
		end
	end
	for _, p in candidates(Vector3.new(x, 0, z)) do
		test(p)
	end
	for _, p in probe.big do
		test(p)
	end
	return best
end

local function findNamed(root: Instance, modelName: string, partName: string): { BasePart }
	local out: { BasePart } = {}
	local mdl = root:FindFirstChild(modelName, true)
	if not mdl then
		return out
	end
	for _, d in mdl:GetDescendants() do
		if d:IsA("BasePart") and d.Name == partName then
			table.insert(out, d)
		end
	end
	return out
end

------------------------------------------------------------------------------------------------------
-- 다리 상판 높이(DeckSlab 윗면) — 없으면 Bridge 종단 선형 공식
------------------------------------------------------------------------------------------------------
local deckSlabs: { BasePart } = {}
local function deckFormula(z: number): number
	local yEnd = L.City + 0.4
	local rise = B.DeckTop - yEnd
	local flat = m(75)
	local function sm(t: number): number
		t = math.clamp(t, 0, 1)
		return t * t * (3 - 2 * t)
	end
	if z < -flat then
		return yEnd + rise * sm((z - F.SlopeTo) / (-flat - F.SlopeTo))
	elseif z > flat then
		return yEnd + rise * sm((N.SlopeTo - z) / (N.SlopeTo - flat))
	end
	return B.DeckTop
end

local function deckY(z: number): number
	for _, p in deckSlabs do
		local cf, s = p.CFrame, p.Size
		local c = cf.Position
		local up, zz = cf.UpVector, cf.ZVector
		if math.abs(zz.Z) > 0.5 then
			local l = (z - c.Z - up.Z * s.Y / 2) / zz.Z
			if math.abs(l) <= s.Z / 2 + 0.01 then
				return c.Y + up.Y * s.Y / 2 + zz.Y * l
			end
		end
	end
	return deckFormula(z)
end

------------------------------------------------------------------------------------------------------
-- 1) 제방 고속화도로 문형 표지
------------------------------------------------------------------------------------------------------
type Bank = { e: number, s: number, model: string, lampX: number }
local FAR: Bank = { e = F.RoadFrom, s = -1, model = "OlympicDaero", lampX = 8500 }
local NEAR: Bank = { e = N.RoadFrom, s = 1, model = "GangbyeonBukro", lampX = 5000 }

local function zAt(bk: Bank, um: number): number
	return bk.e + bk.s * m(um)
end

local function lampXs(root: Instance, bk: Bank): { number }
	local xs: { number } = {}
	local zMed = zAt(bk, (XS.median[1] + XS.median[2]) / 2)
	for _, p in findNamed(root, bk.model, "LampPole") do
		if math.abs(p.Position.Z - zMed) < 3 then
			table.insert(xs, p.Position.X)
		end
	end
	if #xs == 0 then
		local x = -bk.lampX
		while x <= bk.lampX do
			table.insert(xs, x)
			x += LAMP_PITCH
		end
	end
	table.sort(xs)
	return xs
end

-- target 에 가장 가까운 "가로등 두 개 사이 중간"
local function between(xs: { number }, target: number): number
	local best, bd = target, math.huge
	for i = 1, #xs - 1 do
		local mid = (xs[i] + xs[i + 1]) / 2
		if xs[i + 1] - xs[i] < LAMP_PITCH * 1.6 and math.abs(mid - target) < bd then
			best, bd = mid, math.abs(mid - target)
		end
	end
	return best
end

type PanelDef = { off: number, spec: any } -- off = 차로 안쪽 가장자리(분리대 쪽)에서 바깥으로(m)

local function gantryPoints(cf: CFrame, S: number, uOff: number): { Vector3 }
	local pts: { Vector3 } = {}
	for _, sd in { -1, 1 } do
		for v = 1.5, m(9), 2 do
			table.insert(pts, at(cf, sd * S / 2 + uOff, v, 0).Position)
		end
	end
	for u = -S / 2, S / 2, 3 do
		for _, v in { m(5.4), m(6.6), m(7.8) } do
			table.insert(pts, at(cf, u + uOff, v, m(0.3)).Position)
		end
	end
	return pts
end

local function roadTop(x: number, z: number): number
	return surfaceY(x, z, L.City + 3) or (L.City + 0.4)
end

local function expresswayGantry(parent: Instance, root: Instance, bk: Bank, cw: string, heading: number, xTarget: number, panels: { PanelDef }, name: string)
	local xs = lampXs(root, bk)
	local uMed = (XS.median[1] + XS.median[2]) / 2
	local uOut = if cw == "A" then -1.0 else XS.wall[2] + 1.0
	local uInner = if cw == "A" then XS.carA[2] else XS.carB[1]
	local dirOut = if cw == "A" then -1 else 1
	local zMed, zOut = zAt(bk, uMed), zAt(bk, uOut)
	local zC = (zMed + zOut) / 2
	local spanM = math.abs(uOut - uMed)
	local x = between(xs, xTarget)
	local ROAD = roadTop(x, zMed + (zOut - zMed) * 0.3)
	local function frameAt(xx: number): CFrame
		local p = Vector3.new(xx, ROAD, zC)
		return CFrame.lookAt(p, p + Vector3.new(-heading, 0, 0))
	end
	-- 막히면 가로등 사이 다른 칸으로
	local tries = { 0, 1, -1, 2, -2, 3, -3 }
	local cf = frameAt(x)
	for _, k in tries do
		local xx = x + k * LAMP_PITCH
		local c = frameAt(xx)
		if not blocked(gantryPoints(c, m(spanM), 0), { Median = true, Parapet = true, SoundWallBase = true, SoundWall = true, Road = true, Paint = true }) then
			cf, x = c, xx
			break
		end
	end
	local outerRight = (zOut - zMed) * heading > 0
	local outerGround = Kit.groundY(x, zOut)
	local medBase = MEDIAN_H
	local outBase = outerGround - ROAD
	local signs = {}
	for _, pd in panels do
		local zS = zAt(bk, uInner + dirOut * pd.off)
		table.insert(signs, { u = (zS - zC) * heading * Config.METERS_PER_STUD, spec = pd.spec })
	end
	Signage.gantry(parent, cf, spanM, signs, {
		name = name,
		baseL = if outerRight then medBase else outBase,
		baseR = if outerRight then outBase else medBase,
		footL = if outerRight then 0.7 else 1.1,
		footR = if outerRight then 1.1 else 0.7,
	})
end

------------------------------------------------------------------------------------------------------
-- 2) 다리 위 문형 표지 (교량 가장자리보 위 기둥, 다리 폭 전체)
------------------------------------------------------------------------------------------------------
local BRIDGE_IGNORE = { RailTop = true, RailMid = true, RailPost = true, Fascia = true, EdgeLight = true, Sidewalk = true, DeckSlab = true, MedianBarrier = true, EdgeLine = true, CenterLine = true, LaneDash = true }

local function bridgeLampZs(root: Instance): { number }
	local zs: { number } = {}
	for _, p in findNamed(root, "Bridge", "LampPole") do
		if p.Position.X > B.X then
			table.insert(zs, p.Position.Z)
		end
	end
	table.sort(zs)
	return zs
end

local function bridgeGantry(parent: Instance, root: Instance, zTarget: number, facing: number, panels: { { u: number, spec: any } }, name: string)
	local zs = bridgeLampZs(root)
	local z = zTarget
	if #zs > 1 then
		local bd = math.huge
		for i = 1, #zs - 1 do
			local mid = (zs[i] + zs[i + 1]) / 2
			if math.abs(mid - zTarget) < bd then
				z, bd = mid, math.abs(mid - zTarget)
			end
		end
	end
	local y = deckY(z)
	local p = Vector3.new(B.X, y, z)
	local cf = CFrame.lookAt(p, p + Vector3.new(0, 0, facing))
	local spanM = 2 * EDGE_X * Config.METERS_PER_STUD
	if blocked(gantryPoints(cf, 2 * EDGE_X, 0), BRIDGE_IGNORE) then
		warn("[Streetscape] 다리 표지 자리 겹침: " .. name)
	end
	Signage.gantry(parent, cf, spanM, panels, { name = name, baseL = FASCIA_TOP, baseR = FASCIA_TOP, footL = 0.45, footR = 0.45 })
end

------------------------------------------------------------------------------------------------------
-- 3) 노측식 표지(기둥 1~2 개) — 바닥 groundY(월드), 표지 하단 높이 bottom(월드)
------------------------------------------------------------------------------------------------------
local function sidePost(parent: Instance, base: Vector3, look: Vector3, spec: any, bottomY: number, name: string): BasePart
	local mdl = Instance.new("Model")
	mdl.Name = name
	mdl.Parent = parent
	local wM, hM = Signage.roadSignSize(spec)
	local W, H = m(wM), m(hM)
	local center = Vector3.new(base.X, bottomY + H / 2, base.Z)
	local cf = CFrame.lookAt(center, center + look)
	local face = Signage.roadSign(mdl, cf, spec, { name = "Panel" })
	local posts = if wM > 2.2 then { -W * 0.3, W * 0.3 } else { 0 }
	local pd = if wM > 2.2 then m(0.15) else m(0.1)
	for _, u in posts do
		local top = at(cf, u, H / 2 - m(0.1), -m(0.12) - pd / 2).Position
		local bot = Vector3.new(top.X, base.Y - 0.4, top.Z)
		Signage.rod(mdl, bot, top, pd, SC.galv, MAT.Metal, "SignPost", { collide = true, query = true })
		local fp = Vector3.new(top.X, base.Y, top.Z)
		Kit.part(mdl, CFrame.new(fp + Vector3.new(0, 0.1, 0)), Vector3.new(pd * 2.6, 0.5, pd * 2.6), { name = "PostFooting", color = SC.concrete, material = MAT.Concrete, collide = false, query = false })
		for _, v in { H * 0.3, -H * 0.3 } do
			Kit.part(mdl, at(cf, u, v, -m(0.06)), Vector3.new(pd * 1.4, m(0.05), m(0.12)), { name = "Clamp", color = SC.galv, material = MAT.Metal, collide = false, query = false })
		end
	end
	return face
end

------------------------------------------------------------------------------------------------------
-- 4) 거리표(km) — 방호벽 위 작은 녹색판
------------------------------------------------------------------------------------------------------
local function kmPost(parent: Instance, pos: Vector3, look: Vector3, route: string, km: string)
	local mdl = Instance.new("Model")
	mdl.Name = "KmPost"
	mdl.Parent = parent
	local W, H = m(0.36), m(0.52)
	local postH = m(0.55)
	Kit.vcyl(mdl, pos + Vector3.new(0, postH / 2 - 0.1, 0), postH + 0.2, m(0.06), SC.galv, MAT.Metal, { name = "KmPole", collide = false, query = false })
	local c = pos + Vector3.new(0, postH + H / 2, 0) + look * (m(0.03) + 0.09)
	local cf = CFrame.lookAt(c, c + look) * CFrame.new(0, 0, 0.06)
	local plate = Kit.part(mdl, cf, Vector3.new(W, H, 0.12), { name = "KmPlate", color = SC.roadGreen, material = MAT.SmoothPlastic, collide = false, query = false })
	local _ = plate
	local F = CFrame.lookAt(c, c + look)
	Kit.part(mdl, at(F, 0, 0, 0.03), Vector3.new(W - m(0.03), H - m(0.03), 0.06), { name = "KmBorder", color = SC.white, material = MAT.SmoothPlastic, collide = false, query = false })
	Kit.part(mdl, at(F, 0, 0, 0.09), Vector3.new(W - m(0.06), H - m(0.06), 0.06), { name = "KmField", color = SC.roadGreen, material = MAT.SmoothPlastic, collide = false, query = false })
	local o = { color = SC.white, font = "gothic", light = 0.6, maxDistance = 500 }
	Signage.text(mdl, at(F, 0, H * 0.3, 0.17), W * 0.86, H * 0.16, route, o)
	Signage.text(mdl, at(F, 0, 0, 0.17), W * 0.9, H * 0.36, km, { color = SC.white, font = "road", light = 0.6, maxDistance = 500 })
	Signage.text(mdl, at(F, 0, -H * 0.3, 0.17), W * 0.5, H * 0.16, "km", { color = SC.white, font = "road", light = 0.6, maxDistance = 500 })
end

------------------------------------------------------------------------------------------------------
-- 5) 교명주(화강석 기둥 + 청동판)
------------------------------------------------------------------------------------------------------
local GRANITE = rgb(150, 146, 140)
local BRONZE = rgb(86, 64, 40)
local BRONZE_TXT = rgb(214, 182, 116)

local function namePillar(parent: Instance, base: Vector3, look: Vector3, front: string, side: string, sideDir: Vector3)
	local mdl = Instance.new("Model")
	mdl.Name = "BridgeNamePillar"
	mdl.Parent = parent
	local w, h = m(0.62), m(1.5)
	local cf = CFrame.lookAt(base, base + look)
	Kit.part(mdl, cf * CFrame.new(0, m(0.1) - 0.2, 0), Vector3.new(w + m(0.12), m(0.2) + 0.4, w + m(0.12)), { name = "Plinth", color = GRANITE:Lerp(Color3.new(0, 0, 0), 0.15), material = MAT.Granite, collide = true })
	Kit.part(mdl, cf * CFrame.new(0, m(0.2) + h / 2 - 0.05, 0), Vector3.new(w, h + 0.1, w), { name = "Pillar", color = GRANITE, material = MAT.Granite, collide = true })
	Kit.part(mdl, cf * CFrame.new(0, m(0.2) + h + m(0.06) - 0.03, 0), Vector3.new(w + m(0.1), m(0.12), w + m(0.1)), { name = "Cap", color = GRANITE:Lerp(Color3.new(1, 1, 1), 0.08), material = MAT.Granite, collide = true })
	Kit.part(mdl, cf * CFrame.new(0, m(0.2) + h + m(0.12) + m(0.05) - 0.05, 0), Vector3.new(w * 0.6, m(0.1) + 0.06, w * 0.6), { name = "CapTop", color = GRANITE, material = MAT.Granite, collide = false, query = false })
	local function plate(F: CFrame, text: string, pw: number, ph: number)
		local pc = m(0.2) + h * 0.55
		Kit.part(mdl, at(F, 0, pc, w / 2 + 0.04), Vector3.new(pw, ph, 0.18), { name = "BronzePlate", color = BRONZE, material = MAT.Metal, collide = false, query = false, reflectance = 0.08 })
		Signage.text(mdl, at(F, 0, pc, w / 2 + 0.13 + 0.05), pw * 0.84, ph * 0.86, text, { name = "PlateText", color = BRONZE_TXT, font = "serif", weight = "Bold", maxDistance = 220, lineHeight = 0.95 })
	end
	plate(cf, front, w * 0.74, h * 0.8)
	local Fs = CFrame.lookAt(base, base + sideDir)
	plate(Fs, side, w * 0.74, h * 0.5)
end

------------------------------------------------------------------------------------------------------
-- 6) 버스정류소 (쉘터 + 표지 기둥). cf = 쉘터 바닥 중심, 로컬 -Z = 차도 쪽
------------------------------------------------------------------------------------------------------
local FRAME_C = rgb(52, 56, 62)

local function busStop(parent: Instance, cf: CFrame, poleCf: CFrame, rng: Random)
	local mdl = Instance.new("Model")
	mdl.Name = "BusStop_JamsilBridgeNorth"
	mdl.Parent = parent
	local Lg, D, Ht = m(4.2), m(1.5), m(2.6)
	local function part(F: CFrame, size: Vector3, color: Color3, mat: Enum.Material, name: string, extra: any?): BasePart
		local o: any = { name = name, color = color, material = mat, collide = false, query = false }
		if extra then
			for k, v in extra do
				o[k] = v
			end
		end
		return Kit.part(mdl, F, size, o)
	end
	-- 기둥 3 (뒤쪽) + 지붕 (앞으로 캔틸레버, 차도 쪽 약간 기울어짐)
	for _, u in { -Lg / 2 + m(0.1), 0, Lg / 2 - m(0.1) } do
		part(at(cf, u, Ht / 2, -D / 2 + m(0.12)), Vector3.new(m(0.1), Ht, m(0.1)), FRAME_C, MAT.Metal, "ShelterPost", { collide = true, query = true })
	end
	local roof = part(at(cf, 0, Ht + m(0.06), 0) * CFrame.Angles(math.rad(3), 0, 0), Vector3.new(Lg + m(0.2), m(0.12), D + m(0.25)), FRAME_C, MAT.Metal, "ShelterRoof")
	local _ = roof
	-- 지붕 앞 이름띠(정류소 이름: 앞면 발광)
	local band = part(at(cf, 0, Ht - m(0.1), D / 2 + m(0.14)), Vector3.new(Lg + m(0.2), m(0.32), m(0.08)), rgb(18, 70, 140), MAT.SmoothPlastic, "NameBand")
	local _2 = band
	Signage.text(mdl, at(cf, -m(0.4), Ht - m(0.1), D / 2 + m(0.18) + 0.05), Lg * 0.62, m(0.26), "잠실대교북단  Jamsil Bridge North", { name = "StopName", color = SC.white, font = "gothic", glow = true, brightness = 1.1, maxDistance = 300 })
	Signage.text(mdl, at(cf, Lg / 2 - m(0.45), Ht - m(0.1), D / 2 + m(0.18) + 0.05), m(0.7), m(0.2), "05-197", { name = "StopNo", color = rgb(255, 220, 120), font = "road", glow = true, maxDistance = 200 })
	-- 지붕 아래 LED 띠 + 광원
	local led = part(at(cf, 0, Ht - m(0.02), 0), Vector3.new(Lg - m(0.3), m(0.03) + 0.04, m(0.08)), rgb(236, 240, 255), MAT.Neon, "ShelterLed", { shadow = false, glow = true, dayMaterial = MAT.SmoothPlastic, dayColor = rgb(220, 220, 220) })
	Kit.light(led, "SurfaceLight", { color = rgb(236, 240, 255), brightness = 1.2, range = m(3.2), angle = 120, face = Enum.NormalId.Bottom })
	-- 뒷면 유리 2 + 측면 광고 라이트박스(양면)
	for _, sd in { -1, 1 } do
		part(at(cf, sd * Lg / 4, Ht * 0.52, -D / 2 + m(0.12)), Vector3.new(Lg / 2 - m(0.16), Ht * 0.8, m(0.02) + 0.06), rgb(150, 176, 190), MAT.Glass, "ShelterGlass", { transparency = 0.7, reflectance = 0.15, shadow = false })
	end
	local adF = cf * CFrame.new(-(-Lg / 2 + m(0.06)), 0, 0) * CFrame.Angles(0, math.rad(90), 0) -- 오른쪽 끝(보는 사람 기준 왼쪽) 측판, 앞 = 다가오는 보행자
	part(at(adF, 0, m(1.2), 0), Vector3.new(D - m(0.15), m(1.9), m(0.16)), FRAME_C, MAT.Metal, "AdBox")
	Signage.poster(mdl, at(adF, 0, m(1.2), m(0.08)), 1.18, 1.75, "exhibition", rng, { frame = "none", lit = true, name = "ShelterAd" })
	Signage.poster(mdl, at(adF * CFrame.Angles(0, math.pi, 0), 0, m(1.2), m(0.08)), 1.18, 1.75, "sale", rng, { frame = "none", lit = true, name = "ShelterAdBack" })
	-- 벤치(스테인리스, 좌면 0.45 m) + 노선도 판(뒤 유리 안쪽)
	part(at(cf, m(0.3), m(0.45), -D / 2 + m(0.42)), Vector3.new(m(2.2), m(0.05), m(0.42)), rgb(190, 192, 196), MAT.DiamondPlate, "Bench", { collide = true, query = true, reflectance = 0.2 })
	for _, u in { m(-0.6), m(1.2) } do
		part(at(cf, u, m(0.21), -D / 2 + m(0.42)), Vector3.new(m(0.06), m(0.42), m(0.36)), FRAME_C, MAT.Metal, "BenchLeg")
	end
	-- 노선도 판(뒤 유리 앞면, 기다리는 사람이 봄)
	local gF = -D / 2 + m(0.12) + (m(0.02) + 0.06) / 2 -- 유리 앞면 d
	part(at(cf, -Lg / 4, m(1.45), gF + 0.06), Vector3.new(m(1.0), m(0.7), 0.1), rgb(244, 244, 240), MAT.SmoothPlastic, "RouteMapPanel")
	local mf0 = gF + 0.11
	part(at(cf, -Lg / 4, m(1.67), mf0 + 0.01), Vector3.new(m(0.9), m(0.035), 0.06), rgb(0, 90, 200), MAT.SmoothPlastic, "RouteLine")
	part(at(cf, -Lg / 4, m(1.47), mf0 + 0.01), Vector3.new(m(0.9), m(0.035), 0.06), rgb(40, 170, 60), MAT.SmoothPlastic, "RouteLine")
	Signage.text(mdl, at(cf, -Lg / 4, m(1.73), mf0 + 0.09), m(0.9), m(0.07), "302  잠실역 - 잠실대교 - 자양동 - 건대입구", { color = SC.ink, font = "gothic", maxDistance = 60 })
	Signage.text(mdl, at(cf, -Lg / 4, m(1.53), mf0 + 0.09), m(0.9), m(0.07), "3216  잠실대교북단 - 구의역 - 광나루역", { color = SC.ink, font = "gothic", maxDistance = 60 })
	Signage.text(mdl, at(cf, -Lg / 4, m(1.25), mf0 + 0.09), m(0.8), m(0.16), "버스 노선 안내\nBus Route Map", { color = SC.ink, font = "medium", maxDistance = 60 })
	-- BIS(버스 도착 안내 단말기): 지붕 앞쪽 아래 매달림
	local bisF = at(cf, m(0.6), Ht - m(0.62), D / 2 - m(0.1))
	part(bisF, Vector3.new(m(1.1), m(0.42), m(0.12)), rgb(24, 24, 26), MAT.Metal, "BisBox")
	for _, u in { -m(0.4), m(0.4) } do
		part(at(cf, m(0.6) + u, Ht - m(0.22), D / 2 - m(0.1)), Vector3.new(m(0.03), m(0.38), m(0.03)), FRAME_C, MAT.Metal, "BisHanger")
	end
	local bisFace = part(at(cf, m(0.6), Ht - m(0.62), D / 2 - m(0.1) + m(0.06) + 0.04), Vector3.new(m(1.0), m(0.34), 0.06), rgb(8, 8, 10), MAT.SmoothPlastic, "BisScreen")
	local _3 = bisFace
	Signage.text(mdl, at(cf, m(0.6), Ht - m(0.55), D / 2 - m(0.1) + m(0.06) + 0.12), m(0.96), m(0.12), "302   잠실역   2분 후 도착", { name = "BisLine", color = rgb(255, 150, 40), font = "mono", glow = true, brightness = 1.6, maxDistance = 120 })
	Signage.text(mdl, at(cf, m(0.6), Ht - m(0.7), D / 2 - m(0.1) + m(0.06) + 0.12), m(0.96), m(0.12), "3216  구의역   7분 후 도착", { name = "BisLine", color = rgb(255, 150, 40), font = "mono", glow = true, brightness = 1.6, maxDistance = 120 })
	-- 정류소 표지 기둥(연석 쪽): 3 m 기둥 + 깃발형 표지(양면) + 노선 번호 띠
	local pm = Instance.new("Model")
	pm.Name = "BusStopPole"
	pm.Parent = mdl
	Kit.vcyl(pm, (poleCf * CFrame.new(0, m(1.5) - 0.1, 0)).Position, m(3.0) + 0.2, m(0.09), rgb(110, 114, 120), MAT.Metal, { name = "StopPole", collide = true })
	local fF = poleCf * CFrame.new(0, m(2.62), 0)
	Kit.part(pm, fF * CFrame.new(0, 0, 0), Vector3.new(m(0.5), m(0.6), 0.14), { name = "StopFlag", color = rgb(18, 70, 140), material = MAT.SmoothPlastic, collide = false, query = false })
	for _, side in { 1, -1 } do
		local Ff = if side > 0 then fF else fF * CFrame.Angles(0, math.pi, 0)
		local busIcon: { any } = {
			{ k = "r", u = 0.5, v = 0.52, w = 0.62, h = 0.66, c = SC.white, z = 0 },
			{ k = "r", u = 0.5, v = 0.62, w = 0.5, h = 0.26, c = rgb(18, 70, 140), z = 1 },
			{ k = "c", u = 0.32, v = 0.3, w = 0.1, c = rgb(18, 70, 140), z = 1 },
			{ k = "c", u = 0.68, v = 0.3, w = 0.1, c = rgb(18, 70, 140), z = 1 },
		}
		Signage.shapes(pm, at(Ff, 0, m(0.12), 0), m(0.3), m(0.3), busIcon, 0.07, SC.white)
		Signage.text(pm, at(Ff, 0, -m(0.15), 0.12), m(0.44), m(0.12), "잠실대교북단", { color = SC.white, font = "gothic", maxDistance = 150 })
		Signage.text(pm, at(Ff, 0, -m(0.25), 0.12), m(0.3), m(0.06), "05-197", { color = SC.white, font = "road", maxDistance = 100 })
	end
	-- 노선 번호 띠(간선 파랑 / 지선 초록)
	local routes = { { "302", rgb(0, 90, 200) }, { "3216", rgb(40, 160, 60) }, { "2224", rgb(40, 160, 60) } }
	for i, r in routes do
		local y = m(2.18) - (i - 1) * m(0.17)
		local rf = poleCf * CFrame.new(0, y, 0)
		Kit.part(pm, rf, Vector3.new(m(0.36), m(0.15), m(0.12)), { name = "RouteTag", color = r[2], material = MAT.SmoothPlastic, collide = false, query = false })
		for _, side in { 1, -1 } do
			local Ff = if side > 0 then rf else rf * CFrame.Angles(0, math.pi, 0)
			Signage.text(pm, at(Ff, 0, 0, m(0.06) + 0.05), m(0.32), m(0.13), r[1], { color = SC.white, font = "road", maxDistance = 120 })
		end
	end
end

------------------------------------------------------------------------------------------------------
-- 7) 공원 안내도 + 보행 이정 기둥(갈색)
------------------------------------------------------------------------------------------------------
local PARK_BROWN = rgb(96, 62, 38)

local function parkMap(parent: Instance, base: Vector3, look: Vector3)
	local mdl = Instance.new("Model")
	mdl.Name = "ParkMapBoard"
	mdl.Parent = parent
	local W, H = m(1.9), m(1.25)
	local bottom = m(0.7)
	local c = base + Vector3.new(0, bottom + H / 2, 0)
	local cf = CFrame.lookAt(c, c + look)
	-- 기둥 2 + 지붕 차양
	for _, u in { -W / 2 - m(0.06), W / 2 + m(0.06) } do
		local p = at(cf, u, 0, -m(0.06)).Position
		Kit.part(mdl, CFrame.new(p.X, base.Y + (bottom + H + m(0.35)) / 2 - 0.2, p.Z) * (cf - cf.Position), Vector3.new(m(0.12), bottom + H + m(0.35) + 0.4, m(0.12)), { name = "MapPost", color = PARK_BROWN, material = MAT.Wood, collide = true })
	end
	Kit.part(mdl, at(cf, 0, H / 2 + m(0.35), -m(0.06)), Vector3.new(W + m(0.5), m(0.08), m(0.45)), { name = "MapRoof", color = PARK_BROWN:Lerp(Color3.new(0, 0, 0), 0.2), material = MAT.Wood, collide = false, query = false })
	Kit.part(mdl, at(cf, 0, 0, -m(0.06)), Vector3.new(W + m(0.12), H + m(0.12), m(0.08)), { name = "MapFrame", color = PARK_BROWN, material = MAT.Wood, collide = false, query = false })
	-- 지도 판: 머리띠 + 지도(강·공원·길·다리·현위치) + 범례 픽토그램
	local face = Kit.part(mdl, at(cf, 0, 0, 0.005), Vector3.new(W, H, 0.17), { name = "MapPrint", color = rgb(238, 234, 222), material = MAT.SmoothPlastic, collide = false, query = false })
	local _ = face
	local f0 = 0.09
	local shapes = {
		{ k = "r", u = 0.5, v = 0.92, w = 1.0, h = 0.16, c = PARK_BROWN, z = 0 },
		{ k = "r", u = 0.42, v = 0.24, w = 0.84, h = 0.22, c = rgb(120, 170, 210), z = 0 }, -- 한강
		{ k = "r", u = 0.42, v = 0.56, w = 0.84, h = 0.4, c = rgb(150, 196, 120), z = 0 }, -- 공원
		{ k = "r", u = 0.42, v = 0.39, w = 0.84, h = 0.035, c = rgb(232, 210, 160), z = 1 }, -- 산책로
		{ k = "r", u = 0.42, v = 0.6, w = 0.84, h = 0.03, c = rgb(232, 210, 160), z = 1 },
		{ k = "r", u = 0.66, v = 0.5, w = 0.07, h = 0.62, c = rgb(150, 150, 150), z = 2 }, -- 잠실대교
		{ k = "c", u = 0.6, v = 0.5, w = 0.04, c = rgb(220, 30, 40), z = 3 }, -- 현위치
		{ k = "c", u = 0.25, v = 0.56, w = 0.035, c = rgb(60, 60, 60), z = 3 }, -- 전망대
		{ k = "r", u = 0.92, v = 0.5, w = 0.14, h = 0.66, c = rgb(250, 248, 242), z = 0 }, -- 범례 칸
	}
	local top = Signage.shapes(mdl, cf, W, H, shapes, f0, SC.ink)
	local td = top + 0.05
	Signage.text(mdl, at(cf, -W * 0.08, H * 0.42, td), W * 0.7, H * 0.1, "잠실한강공원 안내도", { color = SC.white, font = "gothic", maxDistance = 120 })
	Signage.text(mdl, at(cf, W * 0.36, H * 0.42, td), W * 0.22, H * 0.06, "Jamsil Hangang Park", { color = SC.white, font = "medium", maxDistance = 120 })
	Signage.text(mdl, at(cf, -W * 0.08, -H * 0.26, td), W * 0.3, H * 0.07, "한  강", { color = SC.white, font = "gothic", maxDistance = 100 })
	Signage.text(mdl, at(cf, W * 0.1 + W * 0.08, -H * 0.02, td), W * 0.2, H * 0.05, "현위치 You are here", { color = rgb(220, 30, 40), font = "gothic", maxDistance = 80 })
	Signage.text(mdl, at(cf, -W * 0.25, H * 0.12, td), W * 0.16, H * 0.045, "전망대", { color = SC.ink, font = "gothic", maxDistance = 80 })
	Signage.text(mdl, at(cf, W * 0.16, H * 0.33, td), W * 0.12, H * 0.04, "잠실대교", { color = SC.ink, font = "gothic", maxDistance = 80 })
	-- 범례 픽토그램(작은 판)
	local leg = { "restroom", "info", "accessible", "nosmoking" }
	for i, k in leg do
		local v = H * 0.22 - (i - 1) * H * 0.14
		local sz = if k == "restroom" then 0.08 else 0.1
		Signage.pictogram(mdl, at(cf, W * 0.42, v, f0 + 0.06 + 0.02), sz, k)
	end
end

local function fingerPost(parent: Instance, base: Vector3, arms: { { any } })
	local mdl = Instance.new("Model")
	mdl.Name = "FingerPost"
	mdl.Parent = parent
	local h = m(2.6)
	Kit.part(mdl, CFrame.new(base + Vector3.new(0, h / 2 - 0.2, 0)), Vector3.new(m(0.12), h + 0.4, m(0.12)), { name = "FingerPole", color = PARK_BROWN, material = MAT.Wood, collide = true })
	Kit.part(mdl, CFrame.new(base + Vector3.new(0, h + m(0.04), 0)), Vector3.new(m(0.18), m(0.08), m(0.18)), { name = "FingerCap", color = PARK_BROWN:Lerp(Color3.new(0, 0, 0), 0.25), material = MAT.Wood, collide = false, query = false })
	for i, a in arms do
		local yaw = math.rad(a[1] :: number) -- 가리키는 방향(월드 yaw, 0 = +X)
		local dir = Vector3.new(math.cos(yaw), 0, -math.sin(yaw))
		local y = h - m(0.25) - (i - 1) * m(0.32)
		local len, ah = m(0.95), m(0.24)
		local c = base + Vector3.new(0, y, 0) + dir * (len / 2 + m(0.03))
		-- 판 프레임: 로컬 X = 가리키는 방향, 면 = ±(수평 수직) → 양면 글자
		local cf = CFrame.fromMatrix(c, dir, Vector3.yAxis)
		Kit.part(mdl, cf * CFrame.new(-m(0.08), 0, 0), Vector3.new(len - m(0.16), ah, m(0.05) + 0.06), { name = "FingerBoard", color = PARK_BROWN, material = MAT.Wood, collide = false, query = false })
		-- 화살촉(웨지 2): 로컬 +X(= 보는 사람 기준 왼쪽, at() 의 u 음수) 끝
		local tipBase = len / 2 - m(0.16)
		local th = m(0.05) + 0.06
		Signage.triangle(mdl, cf, -(tipBase + m(0.08)), 0, ah, m(0.16), 180, -th / 2, th / 2, PARK_BROWN, MAT.Wood, "FingerTip")
		for _, side in { 1, -1 } do
			-- 면 프레임: -Z 가 바깥(±판 법선), 글자는 가리키는 쪽이 읽기 방향
			local nrm = cf.LookVector * side
			local Ff = CFrame.lookAt(c, c + nrm)
			local tw = len - m(0.3)
			local du = side * m(0.08)
			Signage.text(mdl, at(Ff, du, ah * 0.14, m(0.025) + 0.03 + 0.05), tw, ah * 0.46, a[2] :: string, { color = rgb(250, 240, 220), font = "gothic", maxDistance = 90 })
			Signage.text(mdl, at(Ff, du, -ah * 0.26, m(0.025) + 0.03 + 0.05), tw, ah * 0.3, a[3] :: string, { color = rgb(250, 240, 220), font = "medium", maxDistance = 70 })
		end
	end
end

------------------------------------------------------------------------------------------------------
function Streetscape.build(ctx: any)
	local model: Model = ctx.model
	local root: Instance = ctx.root
	local rng: Random = ctx.rng
	local p0 = Kit.stats.parts
	buildProbe(root, model)
	deckSlabs = findNamed(root, "Bridge", "DeckSlab")

	-- 1) 제방 고속화도로 문형 표지 ---------------------------------------------------------------------
	local gx = Kit.group(model, "ExpresswayGantries")
	local mouth0, mouth1 = B.X - HALF_W, B.X + HALF_W
	-- 올림픽대로 동행(강 쪽 carA, +X 진행): 우측 진출 = 잠실대교(강북), 직진 = 천호·하남
	expresswayGantry(gx, root, FAR, "A", 1, mouth0 - m(320), {
		{ off = 3.5, spec = { color = "green", arrow = "up", arrowSide = "left", tag = "올림픽대로", lines = { { ko = "하남", en = "Hanam" }, { ko = "천호대교", en = "Cheonho Br." } } } },
		{ off = 10.5, spec = { color = "green", arrow = "upright", lines = { { ko = "잠실대교", en = "Jamsil Br." }, { ko = "자양 · 구의", en = "Jayang · Guui" } }, dist = "300m" } },
	}, "OD_East_JamsilBr")
	-- 올림픽대로 서행(도시 쪽 carB, -X 진행): 우측 = 송파대로(잠실), 좌측 = 잠실대교, 직진 = 여의도·김포공항
	expresswayGantry(gx, root, FAR, "B", -1, mouth1 + m(320), {
		{ off = 1.9, spec = { color = "green", wM = 4.2, koM = 0.4, arrow = "upleft", arrowSide = "left", lines = { { ko = "잠실대교", en = "Jamsil Br." }, { ko = "강북", en = "Gangbuk" } } } },
		{ off = 7.0, spec = { color = "green", wM = 4.6, koM = 0.4, arrow = "up", arrowSide = "left", tag = "올림픽대로", lines = { { ko = "여의도", en = "Yeouido" }, { ko = "김포공항", en = "Gimpo Airport" } } } },
		{ off = 12.1, spec = { color = "green", wM = 4.2, koM = 0.4, arrow = "upright", lines = { { ko = "잠실", en = "Jamsil" }, { ko = "잠실역", en = "Jamsil Stn." } }, dist = "300m" } },
	}, "OD_West_Jamsil")
	-- 강변북로 서행(강 쪽 carA, -X 진행): 우측 = 잠실대교(잠실·송파), 좌측 = 자양로, 직진 = 성수·일산
	expresswayGantry(gx, root, NEAR, "A", -1, mouth1 + m(320), {
		{ off = 1.9, spec = { color = "green", wM = 4.2, koM = 0.4, arrow = "upleft", arrowSide = "left", lines = { { ko = "자양", en = "Jayang" }, { ko = "구의", en = "Guui" } } } },
		{ off = 7.0, spec = { color = "green", wM = 4.6, koM = 0.4, arrow = "up", arrowSide = "left", tag = "강변북로", lines = { { ko = "성수", en = "Seongsu" }, { ko = "일산", en = "Ilsan" } } } },
		{ off = 12.1, spec = { color = "green", wM = 4.2, koM = 0.4, arrow = "upright", lines = { { ko = "잠실대교", en = "Jamsil Br." }, { ko = "잠실 · 송파", en = "Jamsil · Songpa" } }, dist = "300m" } },
	}, "GB_West_JamsilBr")
	-- 강변북로 동행(도시 쪽 carB, +X 진행): 우측 = 자양로, 좌측 = 잠실대교, 직진 = 구리
	expresswayGantry(gx, root, NEAR, "B", 1, mouth0 - m(320), {
		{ off = 1.9, spec = { color = "green", wM = 4.2, koM = 0.4, arrow = "upleft", arrowSide = "left", lines = { { ko = "잠실대교", en = "Jamsil Br." }, { ko = "잠실", en = "Jamsil" } } } },
		{ off = 7.0, spec = { color = "green", wM = 4.6, koM = 0.4, arrow = "up", arrowSide = "left", tag = "강변북로", lines = { { ko = "구리", en = "Guri" }, { ko = "남양주", en = "Namyangju" } } } },
		{ off = 12.1, spec = { color = "green", wM = 4.2, koM = 0.4, arrow = "upright", lines = { { ko = "자양", en = "Jayang" }, { ko = "건대입구", en = "Konkuk Univ." } }, dist = "300m" } },
	}, "GB_East_Jayang")

	-- 2) 다리 위 문형 표지(청색) -----------------------------------------------------------------------
	local gb = Kit.group(model, "BridgeGantries")
	-- 남행(-Z, 잠실 방향): +X 쪽 차로, 표지는 +Z 를 봄. 진행 우측 = +X → 우회전 = 올림픽대로 동(하남)
	bridgeGantry(gb, root, -560, 1, {
		{ u = 3.2, spec = { color = "blue", wM = 4.3, koM = 0.38, arrow = "upleft", arrowSide = "left", tag = "올림픽대로", lines = { { ko = "김포공항", en = "Gimpo Airport" }, { ko = "여의도", en = "Yeouido" } } } },
		{ u = 8.0, spec = { color = "blue", wM = 4.3, koM = 0.38, arrow = "up", arrowSide = "left", lines = { { ko = "잠실", en = "Jamsil" }, { ko = "송파", en = "Songpa" } } } },
		{ u = 12.8, spec = { color = "blue", wM = 4.3, koM = 0.38, arrow = "upright", tag = "올림픽대로", lines = { { ko = "하남", en = "Hanam" }, { ko = "천호대교", en = "Cheonho Br." } } } },
	}, "Bridge_South")
	-- 북행(+Z, 자양 방향): -X 쪽 차로, 표지는 -Z 를 봄. 진행 우측 = -X → 우회전 = 강변북로 서(성수·일산)
	bridgeGantry(gb, root, 560, -1, {
		{ u = 3.2, spec = { color = "blue", wM = 4.3, koM = 0.38, arrow = "upleft", arrowSide = "left", tag = "강변북로", lines = { { ko = "구리", en = "Guri" }, { ko = "남양주", en = "Namyangju" } } } },
		{ u = 8.0, spec = { color = "blue", wM = 4.3, koM = 0.38, arrow = "up", arrowSide = "left", lines = { { ko = "자양", en = "Jayang" }, { ko = "구의", en = "Guui" } } } },
		{ u = 12.8, spec = { color = "blue", wM = 4.3, koM = 0.38, arrow = "upright", tag = "강변북로", lines = { { ko = "성수", en = "Seongsu" }, { ko = "일산", en = "Ilsan" } } } },
	}, "Bridge_North")

	-- 3) 교명주 · 하천 표지 ---------------------------------------------------------------------------
	local gn = Kit.group(model, "BridgeEnds")
	local pillarX = HALF_W - m(0.5) - m(0.31) - 0.05 -- 가장자리보 안쪽에 붙임(보도 바깥 끝)
	for _, endDef in { { z = F.SlopeTo + 8, look = -1 }, { z = N.SlopeTo - 8, look = 1 } } do
		local z = endDef.z
		local y = deckY(z) + WALK_TOP
		local look = Vector3.new(0, 0, endDef.look)
		-- 진행 방향 기준 왼쪽 기둥 = 한글 교명, 오른쪽 = 영문 (다가오는 차: 진행 = -look)
		local leftX = if endDef.look < 0 then B.X + pillarX else B.X - pillarX
		local rightX = if endDef.look < 0 then B.X - pillarX else B.X + pillarX
		namePillar(gn, Vector3.new(leftX, y, z), look, "잠\n실\n대\n교", "1972. 7.\n준공", Vector3.new(if leftX < B.X then 1 else -1, 0, 0))
		namePillar(gn, Vector3.new(rightX, y, z), look, "JAMSIL\nBRIDGE", "한  강\nHAN RIVER", Vector3.new(if rightX < B.X then 1 else -1, 0, 0))
	end
	-- 하천 표지 "한강" (다리 시작, 진행 우측 보도): 북행(+Z)은 -X 쪽, 남행(-Z)은 +X 쪽
	do
		local sx = m(1 + 4 * 3.5) + m(1.6)
		local z1 = F.SlopeTo + m(20)
		sidePost(gn, Vector3.new(B.X - sx, deckY(z1) + WALK_TOP, z1), Vector3.new(0, 0, -1), { color = "blue", koM = 0.32, lines = { { ko = "한강", en = "Hangang River" } } }, deckY(z1) + WALK_TOP + m(2.1), "RiverSign_N")
		local z2 = N.SlopeTo - m(20)
		sidePost(gn, Vector3.new(B.X + sx, deckY(z2) + WALK_TOP, z2), Vector3.new(0, 0, 1), { color = "blue", koM = 0.32, lines = { { ko = "한강", en = "Hangang River" } } }, deckY(z2) + WALK_TOP + m(2.1), "RiverSign_S")
	end

	-- 4) 거리표(km) · 이정표 · 관광지 표지 -------------------------------------------------------------
	local gk = Kit.group(model, "RoadsideSigns")
	for _, def in { { bk = FAR, route = "올림픽대로", km0 = 30.4, look = Vector3.new(-1, 0, 0) }, { bk = NEAR, route = "강변북로", km0 = 24.8, look = Vector3.new(1, 0, 0) } } do
		local bk = def.bk :: Bank
		local zP = zAt(bk, 0.25)
		for k = -4, 4 do
			local x = B.X + k * m(100)
			if x > mouth0 - m(8) and x < mouth1 + m(8) then
				continue
			end
			local y = roadTop(x, zAt(bk, 3)) + PARAPET_H
			if blocked({ Vector3.new(x, y + 1, zP), Vector3.new(x, y + 2.5, zP) }, nil, 0.2) then
				continue
			end
			kmPost(gk, Vector3.new(x, y, zP), def.look :: Vector3, def.route :: string, string.format("%.1f", (def.km0 :: number) + k * 0.1))
		end
	end
	-- 이정표(다리 지난 뒤, 강 쪽 방호벽 바깥 경사면에 두 기둥)
	do
		-- 판이 방호벽 바깥(강 쪽 경사면) 위에 오도록 판 반폭 + 0.8 m 만큼 바깥에 세움
		local function outside(bk: Bank, x: number, spec: any, look: Vector3, name: string)
			local wM = Signage.roadSignSize(spec)
			local z = zAt(bk, -(0.8 + wM / 2))
			local base = Vector3.new(x, Kit.groundY(x, z), z)
			if blocked({ base + Vector3.new(0, 3, 0), base + Vector3.new(0, 8, 0), base + Vector3.new(0, 14, 0) }) then
				warn("[Streetscape] 노측 표지 자리 겹침: " .. name)
			end
			sidePost(gk, base, look, spec, roadTop(x, zAt(bk, 3)) + m(1.6), name)
		end
		outside(FAR, mouth1 + m(600), { color = "green", koM = 0.36, lines = { { ko = "천호대교", en = "Cheonho Br.", dist = "2km" }, { ko = "올림픽대교", en = "Olympic Br.", dist = "3km" }, { ko = "하남", en = "Hanam", dist = "12km" } } }, Vector3.new(-1, 0, 0), "Milestone_OD_East")
		outside(NEAR, mouth0 - m(600), { color = "green", koM = 0.36, lines = { { ko = "영동대교", en = "Yeongdong Br.", dist = "3km" }, { ko = "성수", en = "Seongsu", dist = "5km" }, { ko = "일산", en = "Ilsan", dist = "33km" } } }, Vector3.new(1, 0, 0), "Milestone_GB_West")
		-- 관광지(갈색): 강변북로 서행, 다리 전 강 쪽
		outside(NEAR, mouth1 + m(520), { color = "brown", koM = 0.36, picto = "park", arrow = "upright", lines = { { ko = "잠실한강공원", en = "Jamsil Hangang Park" } } }, Vector3.new(1, 0, 0), "Tourist_Park")
	end

	-- 5) 도로명판(교차로 모서리) ------------------------------------------------------------------------
	local gs = Kit.group(model, "StreetNames")
	local wRoad = m(XS.wall[2])
	local walkX = (CURB_X + HALF_W) / 2
	for _, sd in { -1, 1 } do
		-- 남단(송파대로): 교차로 쪽(+Z)을 봄
		local zS = F.RoadFrom - wRoad - m(3)
		local xS = B.X + sd * (walkX + m(0.35))
		local yS = surfaceY(xS, zS, L.City + 4) or (L.City + 0.4 + WALK_TOP)
		Signage.streetName(gs, CFrame.lookAt(Vector3.new(xS, yS + m(3.0), zS), Vector3.new(xS, yS + m(3.0), zS + 1)), "송파대로", "Songpa-daero", "1→740", { pole = 3.2, groundY = yS })
		-- 북단(자양로): -Z 를 봄
		local zN = N.RoadFrom + wRoad + m(3)
		local xN = B.X + sd * (walkX + m(0.35))
		local yN = surfaceY(xN, zN, L.City + 4) or (L.City + 0.4 + WALK_TOP)
		Signage.streetName(gs, CFrame.lookAt(Vector3.new(xN, yN + m(3.0), zN), Vector3.new(xN, yN + m(3.0), zN - 1)), "자양로", "Jayang-ro", "1→302", { pole = 3.2, groundY = yN })
	end

	-- 6) 버스정류소(북단 자양로, 북행 차로 = -X 쪽 보도) -----------------------------------------------
	do
		local gbs = Kit.group(model, "BusStop")
		local xBack = B.X - HALF_W + m(0.05)
		local zC = N.RoadFrom + wRoad + m(10)
		local y = surfaceY(B.X - walkX, zC, L.City + 4) or (L.City + 0.4 + WALK_TOP)
		local Dm = m(1.5)
		local p = Vector3.new(xBack + Dm / 2, y, zC)
		local cf = CFrame.lookAt(p, p + Vector3.new(1, 0, 0))
		local pole = CFrame.lookAt(Vector3.new(B.X - CURB_X - m(0.45), y, zC + m(3.2)), Vector3.new(B.X - CURB_X - m(0.45), y, zC + m(3.2) + 1))
		busStop(gbs, cf, pole, rng)
	end

	-- 7) 공원 안내도 + 이정 기둥(다리 서쪽 잔디, 전망대 방향을 봄) -------------------------------------
	do
		local gp = Kit.group(model, "ParkWayfinding")
		local corr = B.Width / 2 + m(6)
		local x = B.X - corr + m(4)
		local z = N.ParkTo - m(40)
		if not blocked({ Vector3.new(x, L.Promenade + 2, z), Vector3.new(x, L.Promenade + 6, z) }) then
			parkMap(gp, Vector3.new(x, L.Promenade, z), Vector3.new(-1, 0, 0))
		end
		local fx, fz = x - m(3), z + m(5)
		if not blocked({ Vector3.new(fx, L.Promenade + 2, fz), Vector3.new(fx, L.Promenade + 7, fz) }) then
			fingerPost(gp, Vector3.new(fx, L.Promenade, fz), {
				{ 180, "전망대  150m", "Observatory" },
				{ 180, "편의점 · 화장실  190m", "Store · Restroom" },
				{ 0, "잠실대교 · 버스정류소", "Jamsil Br. · Bus Stop" },
			})
		end
	end

	model:SetAttribute("Parts", Kit.stats.parts - p0)
	print(string.format("[Streetscape] 파트 %d", Kit.stats.parts - p0))
end

return Streetscape
