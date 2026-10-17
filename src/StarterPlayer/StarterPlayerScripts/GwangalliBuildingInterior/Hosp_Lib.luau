--!strict
-- GwangalliBuildingInterior/Hosp_Lib: HospitalPlus 공용 도구.
--   * zone(): 병원 프레임(HF) 기준 Kit (구역마다 하나: 예산 · 숨김 저장소 · 연결 · 애니메이션 · 정리 목록)
--   * 축 정렬 상자(ab / solid), 글자판(tx), 비상구 유도등(exitSign), 그림 문자(pictogram)
--   * 맵 부품 찾기(find) · 숨기기 · 충돌 끄기 · 스트리밍으로 바뀌면 다시 적용(own) · 원상복구(restore)
--   * 벽 바꿔 끼우기(replaceWall): 같은 재질의 벽 조각을 먼저 세우고 맵 벽은 이 클라이언트에서만 숨김 + 통과
--   * 문 애니메이터(Slider / Swinger, 도어클로저 감속) · 감지(actors) · 소리 · 입자 · 의자 · 순간 이동
-- 맵은 읽기 전용: 맵 파트는 이 클라이언트에서만 투명/충돌을 바꾸고, 정리할 때 되돌립니다.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Kit = require(script.Parent:WaitForChild("Kit"))
local Look = require(script.Parent:WaitForChild("Look"))
local Interact = require(script.Parent:WaitForChild("Interact"))
local Scan = require(script.Parent:WaitForChild("Scan"))
local Geo = require(script.Parent:WaitForChild("Hosp_Geo"))

local Lib = {}
Lib.Kit, Lib.Look, Lib.Interact, Lib.Scan, Lib.Geo = Kit, Look, Interact, Scan, Geo

local CF, V3 = CFrame.new, Vector3.new
local PI = math.pi
local M = Enum.Material
local FONT_B, FONT_M, FONT_K = Enum.Font.GothamBold, Enum.Font.GothamMedium, Enum.Font.GothamBlack
Lib.FONT_B, Lib.FONT_M, Lib.FONT_K = FONT_B, FONT_M, FONT_K

-- 구역 -------------------------------------------------------------------------------------------------

-- name 구역의 Kit. budget = Geo.BUDGET[name], quality = "high" | "mid" | "low"
function Lib.zone(name: string, parent: Instance, budget: any, quality: string): any
	local folder = Instance.new("Model")
	folder.Name = name
	folder.Parent = parent
	local V = {
		cf = Geo.HF,
		keep = Geo.SAFE_KEEPS,
		solid = {},
		byName = {},
		tables = {},
		x0 = -1e4,
		x1 = 1e4,
		z0 = -1e4,
		z1 = 1e4,
		W = 2e4,
		D = 2e4,
		H = Geo.CEIL1,
		key = "HospitalPlus#" .. name,
		maxParts = (budget and budget[quality]) or 300,
		maxLights = (budget and budget.lights) or 1,
		detail = quality,
	}
	local K = Kit.new(V, folder)
	K.detail = quality
	K.name = name
	K.folder = folder
	K.hidden = {} :: { [BasePart]: any }
	K.uncollided = {} :: { [BasePart]: boolean }
	K.conns = {} :: { RBXScriptConnection }
	K.anims = {} :: { (number, number) -> () }
	K.secs = {} :: { (number) -> () }
	K.cleanup = {} :: { () -> () }
	K.owned = {} :: { any }
	K.movers = {} :: { any }
	K.hostPts = { Geo.PROMPT_DESK, Geo.PROMPT_DOCTOR }
	K.promptAt = {}
	return K
end

-- 정리 (숨김 · 충돌 원상복구, 연결 끊기, 폴더 지우기)
function Lib.teardown(K: any)
	for _, fn in K.cleanup do
		pcall(fn)
	end
	K.cleanup = {}
	for _, m in K.movers do
		m.dead = true
	end
	K.movers = {}
	for _, c in K.conns do
		c:Disconnect()
	end
	K.conns = {}
	for _, o in K.owned do
		if o.conn then
			o.conn:Disconnect()
		end
	end
	K.owned = {}
	Lib.restore(K)
	K.anims = {}
	K.secs = {}
	if K.folder then
		K.folder:Destroy()
	end
end

function Lib.onSec(K: any, fn: (number) -> ())
	table.insert(K.secs, fn)
end
function Lib.onClean(K: any, fn: () -> ())
	table.insert(K.cleanup, fn)
end
function Lib.conn(K: any, c: RBXScriptConnection)
	table.insert(K.conns, c)
end

-- 상자 · 글자 ------------------------------------------------------------------------------------------

-- 로컬 축 정렬 상자 (두 모서리)
function Lib.ab(K: any, name: string, x0: number, y0: number, z0: number, x1: number, y1: number, z1: number, look: any?): BasePart
	local mn = V3(math.min(x0, x1), math.min(y0, y1), math.min(z0, z1))
	local mx = V3(math.max(x0, x1), math.max(y0, y1), math.max(z0, z1))
	return K:box(name, mx - mn, CF((mn + mx) / 2), look)
end

-- 잠깐 쓰는 효과 파트 (예산 · 목록에 안 들어감, 구역 폴더 아래)
function Lib.temp(K: any, name: string, size: Vector3, lcf: CFrame, look: any?, shape: Enum.PartType?): BasePart
	local p = Instance.new("Part")
	if shape then
		p.Shape = shape
	end
	p.Name = name
	Kit.apply(p, look)
	p.Size = size
	p.CFrame = K.cf * lcf
	p.Parent = K.folder
	return p
end

-- 실제로 막는 구조물: 이 클라이언트에서 충돌 + 카메라 쿼리 + 그림자, keep 검사 생략
function Lib.solid(p: BasePart, collide: boolean?): BasePart
	if p.Parent then
		p.CanCollide = collide ~= false
		p.CanQuery = true
		p.CastShadow = true
	end
	return p
end
function Lib.wall(K: any, name: string, x0: number, y0: number, z0: number, x1: number, y1: number, z1: number, look: any, collide: boolean?): BasePart
	local l = table.clone(look)
	l.free = true
	l.shadow = true
	l.collide = collide ~= false
	return Lib.solid(Lib.ab(K, name, x0, y0, z0, x1, y1, z1, l), collide)
end

-- 보이지 않는 막이 (난간 · 가구 충돌): 충돌만, 카메라 쿼리 · 그림자 없음
function Lib.guard(K: any, name: string, x0: number, y0: number, z0: number, x1: number, y1: number, z1: number): BasePart
	local p = Lib.ab(K, name, x0, y0, z0, x1, y1, z1, { c = Color3.new(1, 1, 1), t = 1, free = true, collide = true })
	p.CanQuery = false
	p.CastShadow = false
	return p
end

-- 표시면 프레임: 점 p 에서 수평 법선 (nx, nz) 쪽을 보는 dcf (+Z = 보는 사람 쪽)
function Lib.face(x: number, y: number, z: number, nx: number, nz: number): CFrame
	local p = V3(x, y, z)
	return CFrame.lookAt(p, p - V3(nx, 0, nz))
end

-- 글자판 (T_clinic tx 와 같은 규약)
function Lib.tx(K: any, name: string, w: number, h: number, dcf: CFrame, s: string, fg: Color3?, bg: Color3?, o: any?): (BasePart, TextLabel)
	local oo: any = o or {}
	return K:text(name, w, h, dcf, s, {
		fg = fg or Geo.C.INK,
		bg = bg,
		font = oo.font or FONT_B,
		d = oo.d or 0.03,
		glow = oo.glow,
		align = oo.align,
		free = if oo.free == nil then true else oo.free,
		look = oo.look,
		maxDist = oo.maxDist,
		wrap = oo.wrap,
		ppx = oo.ppx,
	})
end

-- 아크릴 명판: 판 + 위 띠 + 글자 (두 줄이면 "\n")
function Lib.plate(K: any, name: string, w: number, h: number, dcf: CFrame, s: string, o: any?): TextLabel
	local oo: any = o or {}
	local bg = oo.bg or Geo.C.TEAL
	local fg = oo.fg or Geo.C.WHITE
	K:plate(name .. "Back", w, h, 0.05, dcf, { c = bg, m = M.SmoothPlastic, free = true })
	if oo.band then
		K:plate(name .. "Band", w, 0.08, 0.06, dcf * CF(0, h / 2 - 0.04, 0), { c = oo.band, m = M.SmoothPlastic, free = true })
	end
	local _, t = Lib.tx(K, name, w * 0.9, h * 0.8, dcf * CF(0, -0.02, 0.055), s, fg, nil, { font = oo.font or FONT_B, glow = oo.glow })
	return t
end

-- 피난구 유도등 (녹색 상자 + 달리는 사람). kind "door" = 피난구 (문 위), "path" = 통로 (낮게, 흰 바탕 녹색 글자)
function Lib.exitSign(K: any, dcf: CFrame, w: number, label: string?, kind: string?): BasePart
	local h = w * 0.42
	local box = K:plate("ExitSignBox", w, h, 0.16, dcf, { c = Color3.fromRGB(236, 236, 232), m = M.SmoothPlastic, free = true })
	if kind == "path" then
		local face = K:plate("PathSignFace", w - 0.12, h - 0.12, 0.03, dcf * CF(0, 0, 0.16), { c = Color3.fromRGB(246, 250, 246), m = M.Neon, free = true })
		Lib.tx(K, "PathSignText", w - 0.25, h * 0.66, dcf * CF(0, 0, 0.195), label or "🏃 →", Geo.C.GREEN_EXIT, nil, { glow = 1.2, font = FONT_K })
		return face
	end
	local face = K:plate("ExitSignFace", w - 0.12, h - 0.12, 0.03, dcf * CF(0, 0, 0.16), { c = Geo.C.GREEN_EXIT, m = M.Neon, free = true })
	Lib.tx(K, "ExitSignText", w - 0.25, h * 0.66, dcf * CF(0, 0, 0.195), label or "🏃 비상구", Geo.C.WHITE, nil, { glow = 1.4, font = FONT_K })
	return box
end

-- 그림 문자 (🚺 🚹 🏃 ...) 정사각 판
function Lib.pictogram(K: any, dcf: CFrame, h: number, kind: string, o: any?)
	local oo: any = o or {}
	local glyph = ({ f = "🚺", m = "🚹", run = "🏃", baby = "🚼", nosmoke = "🚭", lift = "🛗" } :: any)[kind] or kind
	local bg = oo.bg or (if kind == "f" then Geo.C.RED elseif kind == "m" then Geo.C.NAVY else Geo.C.TEAL)
	K:plate("PictoBack", h, h, 0.04, dcf, { c = bg, m = M.SmoothPlastic, free = true })
	Lib.tx(K, "Picto", h * 0.86, h * 0.86, dcf * CF(0, 0, 0.045), glyph, oo.fg or Geo.C.WHITE, nil, { font = FONT_K })
end

-- 맵 찾기 ----------------------------------------------------------------------------------------------

local function gw(): Instance?
	return Workspace:FindFirstChild("Gwangalli")
end
function Lib.hospital(): Instance?
	local g = gw()
	local h = g and g:FindFirstChild("hospital")
	return h and h:FindFirstChild("광안 메디컬 의원")
end
function Lib.building(): Instance?
	local g = gw()
	local h = g and g:FindFirstChild("hospital")
	return h and h:FindFirstChild("광안 메디컬 의원 (건물)")
end
function Lib.child(root: Instance?, path: { string }): Instance?
	local cur = root
	for _, n in path do
		if not cur then
			return nil
		end
		cur = cur:FindFirstChild(n)
	end
	return cur
end

-- spec = { root = "main"|"bld", path, name, c (로컬 기대 중심) } → 가장 가까운 파트 (tol 안)
function Lib.find(spec: any, tol: number?): BasePart?
	local root = if spec.root == "bld" then Lib.building() else Lib.hospital()
	local parent = Lib.child(root, spec.path)
	if not parent then
		return nil
	end
	local best, bd = nil, tol or 3.0
	for _, c in parent:GetChildren() do
		if c.Name == spec.name and c:IsA("BasePart") then
			local d = (Geo.L(c.Position) - spec.c).Magnitude
			if d < bd then
				best, bd = c, d
			end
		end
	end
	return best
end

-- parent 아래 이름이 name 인 모든 BasePart (깊이 1, deep 이면 전부)
function Lib.named(parent: Instance?, name: string, deep: boolean?): { BasePart }
	local out = {}
	if not parent then
		return out
	end
	for _, c in (if deep then parent:GetDescendants() else parent:GetChildren()) do
		if c.Name == name and c:IsA("BasePart") then
			table.insert(out, c)
		end
	end
	return out
end

-- 맵 파트의 로컬 AABB
function Lib.localBox(p: BasePart): (Vector3, Vector3)
	return Kit.laabb(Geo.HF:ToObjectSpace(p.CFrame), p.Size)
end

-- 숨기기 · 충돌 ---------------------------------------------------------------------------------------

local function hookChildren(K: any, p: BasePart)
	local rec = K.hidden[p]
	if not rec or rec.hooked then
		return
	end
	rec.hooked = true
	local c = p.ChildAdded:Connect(function(ch)
		local r = K.hidden[p]
		if not r then
			return
		end
		if ch:IsA("SurfaceGui") then
			table.insert(r.guis, { ch, ch.Enabled })
			ch.Enabled = false
		elseif ch:IsA("Decal") then
			table.insert(r.guis, { ch, ch.Transparency })
			ch.Transparency = 1
		end
	end)
	table.insert(K.conns, c)
end

function Lib.hide(K: any, p: BasePart?)
	if not p then
		return
	end
	Scan.hide(K.hidden, p)
	hookChildren(K, p)
end

function Lib.uncollide(K: any, p: BasePart?)
	if not p then
		return
	end
	if K.uncollided[p] == nil then
		K.uncollided[p] = p.CanCollide
	end
	p.CanCollide = false
end

function Lib.restore(K: any)
	Scan.restore(K.hidden)
	for p, v in K.uncollided do
		if p.Parent then
			p.CanCollide = v
		end
	end
	K.uncollided = {}
end

-- 맵 파트를 계속 붙잡기: getter() 가 돌려주는 실제 파트가 바뀌면(스트리밍) fn(p) 를 다시 부름. 1 초마다 확인
function Lib.own(K: any, getter: () -> BasePart?, fn: (BasePart) -> ())
	local o = { last = nil :: BasePart? }
	local function check()
		local p = getter()
		if p and p ~= o.last then
			o.last = p
			local ok, err = pcall(fn, p)
			if not ok then
				warn("[HospitalPlus] own: " .. tostring(err))
			end
		elseif p and o.last == p then
			-- 다른 시스템(DetailLOD · 스트리밍)이 숨김을 풀었으면 다시
			if K.hidden[p] then
				Scan.reapply({ [p] = K.hidden[p] })
			end
			if K.uncollided[p] ~= nil and p.CanCollide then
				p.CanCollide = false
			end
		end
	end
	table.insert(K.owned, o)
	check()
	Lib.onSec(K, check)
end

-- 숨기고 (선택) 충돌까지 끄는 own
function Lib.hideOwn(K: any, getter: () -> BasePart?, uncollide: boolean?)
	Lib.own(K, getter, function(p)
		Lib.hide(K, p)
		if uncollide then
			Lib.uncollide(K, p)
		end
	end)
end

-- 모델 아래 모든 파트 숨김 (가짜 문 그룹 등). 새로 스트리밍된 파트도 1 초마다
function Lib.hideModel(K: any, getter: () -> Instance?, filter: ((BasePart) -> boolean)?, uncollide: boolean?)
	local function sweep()
		local m = getter()
		if not m then
			return
		end
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") and (not filter or filter(d)) then
				if not K.hidden[d] then
					Lib.hide(K, d)
				end
				if uncollide then
					Lib.uncollide(K, d)
				end
			end
		end
	end
	sweep()
	Lib.onSec(K, function()
		sweep()
		Scan.reapply(K.hidden)
	end)
end

-- 다른 실내 빌더(T_clinic 등)가 keep 을 무시하는 free 장식을 우리 방 안에 놓았으면 이 클라이언트에서만 숨김.
-- root = Workspace.GwInteriorDetailLocal, mine = 우리 HospitalPlus 모델 (제외),
-- boxes = { { x0, y0, z0, x1, y1, z1 } } (병원 로컬, 파트 중심 기준). 나중에 지어지는 파트도 DescendantAdded 로 잡음
function Lib.ghostForeign(K: any, root: Instance?, mine: Instance?, boxes: { { number } })
	if not root then
		return
	end
	local function inside(p: BasePart): boolean
		local l = Geo.L(p.Position)
		for _, b in boxes do
			if l.X > b[1] and l.X < b[4] and l.Y > b[2] and l.Y < b[5] and l.Z > b[3] and l.Z < b[6] then
				return true
			end
		end
		return false
	end
	local function check(d: Instance)
		if not d:IsA("BasePart") or not d.Parent or K.hidden[d] then
			return
		end
		if mine and d:IsDescendantOf(mine) then
			return
		end
		if inside(d) then
			Lib.hide(K, d)
			if d.CanCollide then
				Lib.uncollide(K, d)
			end
		end
	end
	for _, d in root:GetDescendants() do
		check(d)
	end
	Lib.conn(K, root.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			task.defer(check, d) -- 위치 · 부모가 다 정해진 뒤
		end
	end))
end

-- 벽 바꿔 끼우기 ---------------------------------------------------------------------------------------

-- part: 맵 벽 (얇은 축 = X 또는 Z). openings = { { u0, u1, v0, v1 } } (u = 벽을 따라 로컬 좌표, v = 로컬 y).
-- 조각을 먼저 다 세우고 나서 맵 벽을 숨기고 충돌을 끔. 반환: 조각 목록
function Lib.replaceWall(K: any, getter: () -> BasePart?, openings: { { number } }, o: any?): { BasePart }
	local oo: any = o or {}
	local p0 = getter()
	if not p0 then
		return {}
	end
	local p: BasePart = p0
	local mn, mx = Lib.localBox(p)
	local thinX = (mx.X - mn.X) < (mx.Z - mn.Z)
	local u0w, u1w = if thinX then mn.Z else mn.X, if thinX then mx.Z else mx.X
	local yb, yt = mn.Y, mx.Y
	local look = { c = p.Color, m = p.Material, r = p.Reflectance, shadow = true, collide = true, free = true }
	local rel = Geo.HF:ToObjectSpace(p.CFrame).Rotation
	local segs: { BasePart } = {}
	local function seg(name: string, a: number, b: number, y0: number, y1: number)
		if b - a < 0.02 or y1 - y0 < 0.02 then
			return
		end
		local c, size
		if thinX then
			c = V3((mn.X + mx.X) / 2, (y0 + y1) / 2, (a + b) / 2)
			size = V3(mx.X - mn.X, y1 - y0, b - a)
		else
			c = V3((a + b) / 2, (y0 + y1) / 2, (mn.Z + mx.Z) / 2)
			size = V3(b - a, y1 - y0, mx.Z - mn.Z)
		end
		-- 맵 파트와 같은 방향으로 (텍스처 면 규약 유지): rel 은 거의 정확히 Ry(180)
		local lsize = rel:VectorToObjectSpace(size)
		local part = K:box(name, V3(math.abs(lsize.X), math.abs(lsize.Y), math.abs(lsize.Z)), CF(c) * rel, look)
		Lib.solid(part, true)
		pcall(function()
			(part :: any).MaterialVariant = (p :: any).MaterialVariant
		end)
		table.insert(segs, part)
	end
	table.sort(openings, function(a, b)
		return a[1] < b[1]
	end)
	local cur = u0w
	for i, op in openings do
		seg((oo.name or "WallSeg") .. i, cur, op[1], yb, yt)
		seg((oo.name or "WallSeg") .. "Sill" .. i, op[1], op[2], yb, op[3])
		seg((oo.name or "WallSeg") .. "Lintel" .. i, op[1], op[2], op[4], yt)
		cur = op[2]
	end
	seg((oo.name or "WallSeg") .. "End", cur, u1w, yb, yt)
	-- 예산 초과로 빠진 조각이 하나라도 있으면 맵 벽을 그대로 둠 (구멍 방지)
	for _, s in segs do
		if s.Parent == nil then
			for _, s2 in segs do
				if s2.Parent then
					s2:Destroy()
				end
			end
			warn("[HospitalPlus] replaceWall: budget, keeping the map wall " .. p.Name)
			return {}
		end
	end
	-- 맵 벽의 텍스처(GwangalliTex 그을음 포함)를 조각에도
	local function cloneTex(t: Instance)
		if t:IsA("Texture") then
			for _, s in segs do
				if s.Parent then
					local c = t:Clone()
					c.Transparency = math.min((t :: Texture).Transparency, 0.95)
					c.Parent = s
				end
			end
		end
	end
	for _, c in p:GetChildren() do
		cloneTex(c)
	end
	Lib.own(K, getter, function(np)
		Lib.hide(K, np)
		Lib.uncollide(K, np)
		if np ~= p then
			for _, c in np:GetChildren() do
				cloneTex(c)
			end
		end
	end)
	return segs
end

-- 감지 (10 Hz 용 캐시) -----------------------------------------------------------------------------

export type Actor = { w: Vector3, l: Vector3, kind: string, role: string? }
local actorList: { Actor } = {}
local actorT = -1
local npcList: { Model } = {}
local npcT = -1

function Lib.localRoot(): (BasePart?, Humanoid?, Model?)
	local ch = Players.LocalPlayer and Players.LocalPlayer.Character
	if not ch then
		return nil, nil, nil
	end
	local hrp = ch:FindFirstChild("HumanoidRootPart")
	local hum = ch:FindFirstChildOfClass("Humanoid")
	if hrp and hrp:IsA("BasePart") then
		return hrp, hum, ch
	end
	return nil, hum, ch
end

-- 로컬 캐릭터 위치 (HF 로컬), 없으면 nil
function Lib.me(): Vector3?
	local hrp = Lib.localRoot()
	return hrp and Geo.L(hrp.Position)
end

function Lib.actors(): { Actor }
	local now = os.clock()
	if now - actorT < 0.18 then
		return actorList
	end
	actorT = now
	local out: { Actor } = {}
	local me = Players.LocalPlayer
	for _, pl in Players:GetPlayers() do
		local ch = pl.Character
		local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			table.insert(out, { w = hrp.Position, l = Geo.L(hrp.Position), kind = if pl == me then "local" else "player" })
		end
	end
	if now - npcT > 2 then
		npcT = now
		npcList = {}
		local f = Workspace:FindFirstChild("GwangalliNPCs")
		if f then
			for _, m in f:GetChildren() do
				if m:IsA("Model") and m:GetAttribute("NpcKind") == "hospital" then
					table.insert(npcList, m)
				end
			end
		end
	end
	for _, m in npcList do
		if m.Parent then
			local ok, pv = pcall(function()
				return m:GetPivot().Position
			end)
			if ok then
				table.insert(out, { w = pv, l = Geo.L(pv), kind = "npc", role = m:GetAttribute("HospitalRole") :: any })
			end
		end
	end
	actorList = out
	return out
end

function Lib.npcs(): { Model }
	Lib.actors()
	return npcList
end

-- 로컬 상자 안에 누가 있나 (y 는 발 기준이 아니라 HRP/피벗 기준)
function Lib.anyIn(x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, onlyLocal: boolean?): boolean
	for _, a in Lib.actors() do
		if (not onlyLocal or a.kind == "local") and a.l.X > x0 and a.l.X < x1 and a.l.Z > z0 and a.l.Z < z1 and a.l.Y > y0 and a.l.Y < y1 then
			return true
		end
	end
	return false
end

-- 문 애니메이터 -------------------------------------------------------------------------------------

local EASE: { [string]: (number) -> number } = {
	linear = function(t)
		return t
	end,
	quadOut = function(t)
		return 1 - (1 - t) * (1 - t)
	end,
	quadIn = function(t)
		return t * t
	end,
	quadInOut = function(t)
		return if t < 0.5 then 2 * t * t else 1 - (-2 * t + 2) ^ 2 / 2
	end,
	quartOut = function(t)
		return 1 - (1 - t) ^ 4
	end,
	quintOut = function(t)
		return 1 - (1 - t) ^ 5
	end,
	sineInOut = function(t)
		return -(math.cos(PI * t) - 1) / 2
	end,
}
Lib.EASE = EASE

local active: { [any]: boolean } = {}
local loopConn: RBXScriptConnection? = nil

local function stepMovers()
	local now = os.clock()
	local n = 0
	for m in active do
		n += 1
		if m.dead then
			active[m] = nil
		else
			m:_step(now)
		end
	end
	if n == 0 and loopConn then
		loopConn:Disconnect()
		loopConn = nil
	end
end
local function wake(m: any)
	active[m] = true
	if not loopConn then
		loopConn = RunService.Heartbeat:Connect(stepMovers)
	end
end

local Mover = {}
Mover.__index = Mover

-- parts 의 현재 CFrame 을 닫힌 상태(alpha 0)로 기억. xf(alpha) -> 월드 변환 CFrame
-- o = { tOpen = 0.6, tClose = 1.0, easeOpen = "quartOut", easeClose = "sineInOut", closer = true (도어클로저 2 단),
--       collide = { parts } (완전히 닫혔을 때만 충돌), onLatch = fn, onOpened = fn }
local function newMover(K: any, parts: { BasePart }, xf: (number) -> CFrame, o: any?): any
	local self = setmetatable({}, Mover)
	self.parts = {}
	for _, p in parts do
		if p.Parent then
			table.insert(self.parts, { p = p, base = p.CFrame })
		end
	end
	self.xf = xf
	self.o = o or {}
	self.alpha = 0
	self.target = 0
	self.segs = {} :: { any }
	self.dead = false
	self.collide = {}
	for _, p in (self.o.collide or {}) :: { BasePart } do
		self.collide[p] = true
	end
	table.insert(K.movers, self)
	self:_apply(0)
	return self
end

function Mover:_apply(a: number)
	self.alpha = a
	local x = self.xf(a)
	for _, r in self.parts do
		if r.p.Parent then
			r.p.CFrame = x * r.base
			if self.collide[r.p] then
				r.p.CanCollide = a <= 0.002
			end
		end
	end
end

function Mover:_step(now: number)
	local s = self.segs[1]
	if not s then
		active[self] = nil
		return
	end
	if not s.t0 then
		s.t0 = now
		s.from = self.alpha
	end
	local k = if s.dur <= 0 then 1 else math.clamp((now - s.t0) / s.dur, 0, 1)
	local e = (EASE[s.ease] or EASE.linear)(k)
	self:_apply(s.from + (s.to - s.from) * e)
	if k >= 1 then
		table.remove(self.segs, 1)
		if s.done then
			pcall(s.done)
		end
		if #self.segs == 0 then
			active[self] = nil
		end
	end
end

-- target 0..1 로 움직임 (instant = 바로)
function Mover:set(target: number, instant: boolean?)
	if self.dead then
		return
	end
	target = math.clamp(target, 0, 1)
	if instant then
		self.segs = {}
		self.target = target
		self:_apply(target)
		active[self] = nil
		return
	end
	if math.abs(target - self.target) < 1e-4 and (#self.segs > 0 or math.abs(self.alpha - target) < 1e-4) then
		return
	end
	self.target = target
	local o = self.o
	local d = math.abs(target - self.alpha)
	self.segs = {}
	if target > self.alpha then
		table.insert(self.segs, { to = target, dur = (o.tOpen or 0.6) * math.max(0.25, d), ease = o.easeOpen or "quartOut", done = o.onOpened })
	elseif o.closer and target <= 0 and self.alpha > 0.08 then
		-- 도어클로저: 빠르게 8% 까지 감속 → 래치 (딸깍)
		table.insert(self.segs, { to = 0.07, dur = (o.tClose or 1.0) * math.max(0.3, d), ease = "quintOut" })
		table.insert(self.segs, { to = 0, dur = o.tLatch or 0.18, ease = "quadIn", done = o.onLatch })
	else
		table.insert(self.segs, { to = target, dur = (o.tClose or 1.0) * math.max(0.25, d), ease = o.easeClose or "sineInOut", done = if target <= 0 then o.onLatch else nil })
	end
	wake(self)
end

function Mover:isClosed(): boolean
	return self.alpha <= 0.002 and self.target <= 0
end

-- 미닫이: offset (월드 벡터) 만큼 평행 이동
function Lib.Slider(K: any, parts: { BasePart }, offset: Vector3, o: any?): any
	return newMover(K, parts, function(a)
		return CF(offset * a)
	end, o)
end

-- 여닫이: hinge (월드 점) 둘레 axis (월드 단위) 로 angle 라디안
function Lib.Swinger(K: any, parts: { BasePart }, hinge: Vector3, axis: Vector3, angle: number, o: any?): any
	return newMover(K, parts, function(a)
		return CF(hinge) * CFrame.fromAxisAngle(axis, angle * a) * CF(-hinge)
	end, o)
end

-- 그룹 모델 안 모든 파트
function Lib.partsOf(m: Instance): { BasePart }
	local out = {}
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end

-- 소리 · 입자 ------------------------------------------------------------------------------------------

-- o = { vol, speed, loop, dur (초 뒤 정리), max (들리는 거리) }
function Lib.sfx(part: Instance?, id: string, o: any?): Sound?
	if not part or not part.Parent then
		return nil
	end
	local oo: any = o or {}
	local s = Instance.new("Sound")
	s.Name = "GwHospSfx"
	s.SoundId = id
	s.Volume = oo.vol or 0.5
	s.PlaybackSpeed = oo.speed or 1
	s.Looped = oo.loop == true
	s.RollOffMaxDistance = oo.max or 45
	s.RollOffMinDistance = 4
	s.Parent = part
	s:Play()
	local dur = oo.dur or (if oo.loop then nil else 4)
	if dur then
		task.delay(dur, function()
			if s.Parent then
				s:Destroy()
			end
		end)
	end
	return s
end

-- 위치 없는 소리 (화면 전환 · UI)
function Lib.sfx2d(id: string, o: any?): Sound?
	return Lib.sfx(game:GetService("SoundService"), id, o)
end

-- 소리 n 번 (간격 gap)
function Lib.beeps(part: Instance?, id: string, n: number, gap: number, o: any?)
	task.spawn(function()
		for _ = 1, n do
			Lib.sfx(part, id, o)
			task.wait(gap)
		end
	end)
end

-- kind: "water" (물방울, 아래로) | "air" (바람, 아래로) | "steam" (김, 위로). face = 파트 면 (기본: 종류에 맞게 Bottom/Top)
function Lib.particles(part: BasePart?, kind: string, dur: number, face: Enum.NormalId?): ParticleEmitter?
	if not part or not part.Parent then
		return nil
	end
	local e = Instance.new("ParticleEmitter")
	e.Name = "GwHospFx"
	if kind == "water" then
		e.Texture = Geo.TEX.sparkle
		e.Color = ColorSequence.new(Color3.fromRGB(200, 230, 255))
		e.Size = NumberSequence.new(0.08, 0.02)
		e.Transparency = NumberSequence.new(0.2, 0.8)
		e.Lifetime = NumberRange.new(0.25, 0.35)
		e.Rate = 40
		e.Speed = NumberRange.new(3, 4)
		e.SpreadAngle = Vector2.new(8, 8)
		e.EmissionDirection = Enum.NormalId.Bottom
		e.Acceleration = V3(0, -20, 0)
	elseif kind == "air" then
		e.Texture = Geo.TEX.smoke
		e.Color = ColorSequence.new(Color3.fromRGB(240, 244, 248))
		e.Size = NumberSequence.new(0.3, 0.9)
		e.Transparency = NumberSequence.new(0.85, 1)
		e.Lifetime = NumberRange.new(0.3, 0.5)
		e.Rate = 30
		e.Speed = NumberRange.new(6, 7)
		e.SpreadAngle = Vector2.new(12, 12)
		e.EmissionDirection = Enum.NormalId.Bottom
	else
		e.Texture = Geo.TEX.smoke
		e.Color = ColorSequence.new(Color3.fromRGB(250, 250, 250))
		e.Size = NumberSequence.new(0.15, 0.6)
		e.Transparency = NumberSequence.new(0.7, 1)
		e.Lifetime = NumberRange.new(0.8, 1.4)
		e.Rate = 10
		e.Speed = NumberRange.new(0.6, 1.2)
		e.SpreadAngle = Vector2.new(15, 15)
		e.EmissionDirection = Enum.NormalId.Top
	end
	if face then
		e.EmissionDirection = face
	end
	e.LightInfluence = 0.6
	e.Parent = part
	task.delay(dur, function()
		if e.Parent then
			e.Enabled = false
			task.delay(1.6, function()
				if e.Parent then
					e:Destroy()
				end
			end)
		end
	end)
	return e
end

-- 프롬프트 (같은 구역의 다른 프롬프트와 2.5 간격 검사를 건너뜀: 벽 양쪽 · 카 안팎처럼 서로 안 보이는 쌍)
function Lib.promptAny(K: any, part: BasePart, spec: any): ProximityPrompt?
	local saved = K.promptAt
	K.promptAt = {}
	local pr = Interact.prompt(K, part, spec)
	for _, p in K.promptAt do
		table.insert(saved, p)
	end
	K.promptAt = saved
	return pr
end

-- 앉기 (이 클라이언트에서만) ---------------------------------------------------------------------------

-- pcfW: 좌판 윗면 가운데 (월드), +Z = 앉은 사람이 보는 쪽
local function sitAt(K: any, pcfW: CFrame): boolean
	local hrp, hum = Lib.localRoot()
	if not hrp or not hum or hum.Health <= 0 or hum.Sit or hum.SeatPart then
		return false
	end
	local seatCF = pcfW * CF(0, -0.1, 0) * CFrame.Angles(0, PI, 0) -- Seat 의 LookVector(-Z) = 보는 쪽
	local seat = Instance.new("Seat")
	seat.Name = "GwHospSeat"
	seat.Size = V3(1.6, 0.2, 1.6)
	seat.CFrame = seatCF
	seat.Anchored = true
	seat.CanCollide = false
	seat.CanQuery = false
	seat.CanTouch = false
	seat.Transparency = 1
	seat.Parent = K.folder
	local ok = pcall(function()
		seat:Sit(hum)
	end)
	task.wait(0.1)
	local weld: Weld? = nil
	if not ok or hum.SeatPart ~= seat then
		-- 엔진이 클라이언트 좌석을 안 받아 주면: 직접 용접 + Sit 상태
		local w = Instance.new("Weld")
		w.Name = "GwHospSitWeld"
		w.Part0 = seat
		w.Part1 = hrp
		local up = if hum.RigType == Enum.HumanoidRigType.R6 then 1.6 else 1.25 + math.max(0, hum.HipHeight - 2) * 0.5
		w.C0 = CF(0, 0.1 + up, 0)
		w.C1 = CF()
		w.Parent = seat
		weld = w
		hum.Sit = true
	end
	local c: RBXScriptConnection? = nil
	c = hum:GetPropertyChangedSignal("Sit"):Connect(function()
		if not hum.Sit then
			if c then
				c:Disconnect()
			end
			if weld then
				weld:Destroy()
			end
			task.delay(0.3, function()
				seat:Destroy()
			end)
		end
	end)
	Lib.onClean(K, function()
		if seat.Parent and hum.Parent and hum.SeatPart == seat then
			hum.Sit = false
		end
		if seat.Parent then
			seat:Destroy()
		end
	end)
	return true
end

-- 앉기 프롬프트: part 에 붙이고 pcf (로컬, 좌판 윗면 가운데) 에 앉힘
function Lib.seatPrompt(K: any, part: BasePart, pcf: CFrame, object: string?): ProximityPrompt?
	return Interact.prompt(K, part, {
		action = "앉기",
		object = object or "의자",
		sound = false,
		fn = function()
			task.spawn(sitAt, K, Geo.HF * pcf)
		end,
	})
end

-- 순간 이동 (숨은 방 전용) --------------------------------------------------------------------------------

-- 지금 이동해도 되나? (false, 이유)
function Lib.canTravel(): (boolean, string?)
	local hrp, hum, ch = Lib.localRoot()
	if not hrp or not hum or not ch then
		return false, "캐릭터가 없어요"
	end
	if hum.Health <= 0 then
		return false, "지금은 이동할 수 없어요"
	end
	if hum.Sit or hum.SeatPart or hum.PlatformStand then
		return false, "지금은 이동할 수 없어요 (앉아 있을 때)"
	end
	local st = hum:GetState()
	if st == Enum.HumanoidStateType.Ragdoll or st == Enum.HumanoidStateType.Physics or st == Enum.HumanoidStateType.FallingDown or st == Enum.HumanoidStateType.Dead then
		return false, "지금은 이동할 수 없어요"
	end
	if hrp.Anchored then
		return false, "지금은 이동할 수 없어요"
	end
	if ch:GetAttribute("GwKO") or ch:GetAttribute("GwEmsPatient") or ch:GetAttribute("GwTreating") then
		return false, "지금은 이동할 수 없어요 (치료 중일 때)"
	end
	local pl = Players.LocalPlayer
	if pl and pl:GetAttribute("GwCollapse") then
		return false, "지금은 이동할 수 없어요"
	end
	return true, nil
end

-- 로컬 lcf (발 위치 + 보는 방향) 로 캐릭터 이동. 카메라도 같이 옮김
function Lib.teleport(lcf: CFrame): boolean
	local hrp, hum, ch = Lib.localRoot()
	if not hrp or not hum or not ch then
		return false
	end
	local target = Geo.HF * lcf
	-- 앉아 있으면 먼저 일어남 (좌석 용접이 남아 있으면 캐릭터가 의자에 묶인 채로 끌려감)
	if hum.SeatPart or hum.Sit then
		local seat = hum.SeatPart
		for _, w in (if seat then seat:GetChildren() else {}) :: { Instance } do
			if (w:IsA("Weld") or w:IsA("WeldConstraint")) and (w.Name == "SeatWeld" or w.Name == "GwHospSitWeld") then
				w:Destroy()
			end
		end
		hum.Sit = false
	end
	local cam = Workspace.CurrentCamera
	local off = if cam then hrp.CFrame:ToObjectSpace(cam.CFrame) else nil
	local pl = Players.LocalPlayer
	task.spawn(function()
		pcall(function()
			(pl :: any):RequestStreamAroundAsync(target.Position, 1)
		end)
	end)
	local up = hum.HipHeight + hrp.Size.Y / 2
	if hum.RigType == Enum.HumanoidRigType.R6 then
		up = 3
	end
	local look = target.LookVector
	local flat = V3(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		flat = V3(0, 0, -1)
	end
	local p = target.Position + V3(0, up + 0.05, 0)
	-- 캐릭터 모델 통째로 PivotTo (HRP 기준 피벗 관계 유지). 실패하면 HRP 만 옮김 (관절로 몸 전체가 따라옴)
	local goal = CFrame.lookAt(p, p + flat.Unit)
	local moved = pcall(function()
		local rel = hrp.CFrame:ToObjectSpace(ch:GetPivot())
		ch:PivotTo(goal * rel)
	end)
	if not moved or (hrp.Position - goal.Position).Magnitude > 0.5 then
		hrp.CFrame = goal
	end
	hrp.AssemblyLinearVelocity = Vector3.zero
	pcall(function()
		hum:MoveTo(p) -- 진행 중인 클릭 이동 (MoveTo) 취소: 도착한 자리에서 멈춤
	end)
	hrp.AssemblyAngularVelocity = Vector3.zero
	if cam and off then
		cam.CFrame = hrp.CFrame * off
	end
	return true
end

return Lib
