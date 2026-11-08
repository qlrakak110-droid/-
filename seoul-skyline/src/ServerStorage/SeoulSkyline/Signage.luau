--!strict
-- SeoulSkyline / Signage
-- 실사급 한국 간판·표지 라이브러리. 이미지 업로드 없이 전부 절차적(파트 + SurfaceGui). 1 stud = 0.3 m, 인자는 실측 m.
-- 실제 브랜드명/로고 없음(가상의 상호·기관명만). 결정적: 난수는 호출자가 넘긴 rng 만 사용.
--
-- ── 좌표 규약 (Props 와 동일) ─────────────────────────────────────────────────────────────────────
--   cf = 붙는 면(벽면 / 패널 뒷면 / 노면) 위 기준점(대개 간판 중심). 로컬 -Z = 보는 사람 쪽(앞), +Y = 위.
--   보는 사람 기준 오른쪽 = 로컬 -X (Roblox 가 Front 면 SurfaceGui 를 그렇게 그림) → 내부 배치는 at(F, u, v, d)
--   (u = 보는 사람 오른쪽, v = 위, d = 면에서 보는 사람 쪽으로 나온 거리) 로만 함.
--   층 간격 GAP = 0.06 stud(≥ 0.05). 글자는 투명(Transparency 1) "캐리어" 파트(0.05 두께)의 앞면 SurfaceGui —
--   캐리어 앞면 = 글자 평면. 감사 도구(audit_geom)는 투명 파트를 무시하므로 z-fighting 대상이 아님.
--
-- ── 미리보기 에뮬레이터(tools/preview.js, 광안리 스튜디오 엔진) SurfaceGui 지원 실측 (2026-11-08) ───────
--   * SurfaceGui 하나 = 그 면 전체를 덮는 캔버스 1장. 모든 TextLabel 의 Text 를 순서대로 이어 줄마다 같은 높이·가운데
--     정렬로 그림(Position/Size/TextXAlignment/LineHeight 무시). 굵은 system-ui 고정(Font/FontFace 무시).
--     글자 높이 ≈ 줄 높이 × 0.78, 폭이 넘치면 92 % 로 축소. 캔버스 ≤ 512 px, ≤ 40 px/stud (먼 큰 간판은 흐림).
--   * 배경 = 첫 번째 불투명 TextLabel 배경 또는 첫 번째 보이는 Frame(BackgroundTransparency < 1)의 색으로 면 전체를
--     칠함. 그 밖의 Frame 은 무시 → 원(UICorner), 도형, 로고 Frame 은 안 보임.
--   * 미지원: UIGradient(그 Frame 의 BackgroundColor3 로 단색), UICorner, UIStroke, TextStroke, RichText 색(태그만
--     제거), TextTransparency, LightInfluence/Brightness(항상 조명 무관 원색 = 발광처럼 보임), ZOffset, AlwaysOnTop.
--   * 지원: Transparency 1 파트 위의 SurfaceGui(→ 캐리어 방식 OK), 여러 겹 캐리어(채널 글자 두께가 비스듬히 보임),
--     \n 여러 줄, 한글. 글자판은 면에서 0.03 stud 앞에 그려짐.
--   * 지연 생성: 카메라 가까운 N 개(기본 56 개 / 140 stud 이내)만, 프레임당 2 개씩 만듦 → 많은 간판은 --settle 5+ 필요.
--     (scratchpad/agents/signage/preview_sg.js 는 SIGN_R/SIGN_N 환경변수로 한도를 늘린 사본)
--   → 설계 원칙: ① 두 렌더러 모두 보여야 하는 도형(화살표·픽토그램·로고·색 면)은 파트(원판 = Cylinder, 삼각형 = Wedge 2개)
--     ② 글자 덩어리마다 그 크기의 캐리어 하나(위치가 두 렌더러에서 같음) ③ Frame 이 있는 Gui 는 첫 Frame 을 "의도한
--     단색 바탕"으로(에뮬레이터는 그 색만 칠함) ④ UIGradient·UIStroke(글로/헤일로·트림캡)·UICorner·Brightness(>1 = Future
--     블룸)·FontFace 굵기는 실제 Roblox 용으로만 얹음. TextScaled 최대 100 px 이라 pps ≤ 96 / 줄높이(stud).
--
-- ── API (모두 주 파트를 반환. 간판마다 Model 하나에 묶임) ──────────────────────────────────────────────
--   Signage.text(parent, cf, wS, hS, text, opts?)              캐리어 글자판(크기 stud, cf = 글자 평면 중심)
--   Signage.channel(parent, cf, text, opts?)                   채널 간판(입체 글자: 전면발광/후광/비조명, 레이스웨이, 로고)
--   Signage.lightbox(parent, cf, wM, hM, opts?)                플렉스/라이트박스(알루미늄 프레임 + 발광 면 + 로고 + 글자)
--   Signage.blade(parent, cf, wM, hM, text, opts?)             돌출 간판(양면, 세로 글자, 벽 브래킷)
--   Signage.neon(parent, cf, text, color, opts?)               네온 사인(투명 아크릴 + 스탠드오프 + 강한 글로)
--   Signage.banner(parent, cf, wM, hM, text, opts?)            현수막(천, 아일렛, 끈, 기둥, 바람에 처짐)
--   Signage.poster(parent, cf, wM, hM, design, rng, opts?)     실사 출력물: "sale" "event" "notice" "promo11" "realestate" "exhibition"
--   Signage.menuBoard(parent, cf, wM, hM, title, items, opts?) 메뉴판(섹션 + 이름/가격 정렬 행, 1~2 단)
--   Signage.pictogram(parent, cf, sizeM, kind, opts?)          KS/ISO 픽토그램: man woman restroom accessible elevator stairs exit nosmoking info
--   Signage.roadSign(parent, cf, spec, opts?)                  도로안내표지(녹/청/갈색, 흰 테두리, 화살표, 국/영문)
--   Signage.gantry(parent, cf, spanM, signs, opts?)            문형/내민식 표지 구조물(트러스, 기둥, 기초; 하단 여유 5.2 m)
--   Signage.streetName(parent, cf, name, roman, range, opts?)  도로명판("올림픽로 Olympic-ro 1→699", 기둥/양면)
--   Signage.digital(parent, cf, wM, hM, opts?)                 LED 전광판(베젤 + 밝은 화면, 태그 SeoulLedScreen)
--   보조: Signage.at(F,u,v,d), Signage.textWidth(text, hS), Signage.shapes(...), Signage.Colors, Signage.GAP

local CollectionService = game:GetService("CollectionService")
local Config = require(script.Parent.Config)
local Kit = require(script.Parent.Kit)

local Signage = {}

local rgb = Color3.fromRGB
local M = Config.m
local MAT = Enum.Material
local FRONT = Enum.NormalId.Front
local GAP = 0.06
local MAX_CANVAS = 1024
Signage.GAP = GAP
Signage.LED_TAG = "SeoulLedScreen"

local C = {
	white = rgb(248, 248, 246),
	paper = rgb(246, 244, 238),
	black = rgb(22, 22, 24),
	ink = rgb(34, 34, 38),
	roadGreen = rgb(0, 112, 74),
	roadBlue = rgb(0, 82, 160),
	roadBrown = rgb(120, 74, 42),
	roadYellow = rgb(250, 194, 0),
	nameNavy = rgb(22, 64, 138),
	galv = rgb(156, 160, 164), -- 용융아연도금 강재
	steel = rgb(72, 76, 82),
	alu = rgb(186, 188, 192),
	concrete = rgb(168, 164, 158),
	isoGreen = rgb(0, 150, 80),
	isoRed = rgb(206, 30, 38),
	isoBlue = rgb(0, 84, 166),
	maleBlue = rgb(0, 92, 170),
	femaleRed = rgb(214, 46, 52),
}
Signage.Colors = C

------------------------------------------------------------------------------------------------------
-- 기본 도우미
------------------------------------------------------------------------------------------------------
-- 보는 사람 기준 좌표 → CFrame (u = 오른쪽, v = 위, d = 면에서 앞으로)
local function at(F: CFrame, u: number, v: number, d: number): CFrame
	return F * CFrame.new(-u, v, -d)
end
Signage.at = at

local function newModel(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function opt(name: string, color: Color3, mat: Enum.Material, extra: { [string]: any }?): any
	local o: { [string]: any } = { name = name, color = color, material = mat, collide = false, query = false }
	if extra then
		for k, v in extra do
			o[k] = v
		end
	end
	return o
end

-- 보는 사람 좌표의 상자: 앞뒤 d0..d1, 폭 w(u 방향), 높이 h, 평면 회전 rot(도, 보는 사람 기준 반시계)
local function vbox(parent: Instance, F: CFrame, u: number, v: number, d0: number, d1: number, w: number, h: number, color: Color3, mat: Enum.Material, name: string, extra: { [string]: any }?, rot: number?): BasePart
	local cf = at(F, u, v, (d0 + d1) / 2)
	if rot and rot ~= 0 then
		cf = cf * CFrame.Angles(0, 0, -math.rad(rot))
	end
	return Kit.part(parent, cf, Vector3.new(w, h, d1 - d0), opt(name, color, mat, extra))
end

-- 보는 사람을 향한 원판(Cylinder 축 = 면 법선)
local function vdisc(parent: Instance, F: CFrame, u: number, v: number, d0: number, d1: number, dia: number, color: Color3, mat: Enum.Material, name: string, extra: { [string]: any }?): BasePart
	local o = opt(name, color, mat, extra)
	o.shape = "Cylinder"
	return Kit.part(parent, at(F, u, v, (d0 + d1) / 2) * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(d1 - d0, dia, dia), o)
end

-- 두 점을 잇는 원기둥(파이프·끈·트러스 부재)
local function rod(parent: Instance, a: Vector3, b: Vector3, dia: number, color: Color3, mat: Enum.Material, name: string, extra: { [string]: any }?): BasePart?
	local d = b - a
	local len = d.Magnitude
	if len < 0.05 then
		return nil
	end
	local mid = (a + b) / 2
	local cf: CFrame
	if math.abs(d.Unit.Y) > 0.999 then
		cf = CFrame.new(mid) * CFrame.Angles(0, 0, math.pi / 2)
	else
		cf = CFrame.lookAt(mid, b) * CFrame.Angles(0, math.pi / 2, 0)
	end
	local o = opt(name, color, mat, extra)
	o.shape = "Cylinder"
	return Kit.part(parent, cf, Vector3.new(len, dia, dia), o)
end
Signage.rod = rod

local function glowOpt(dayColor: Color3?, extra: { [string]: any }?): { [string]: any }
	local o: { [string]: any } = { shadow = false, glow = true, dayMaterial = MAT.SmoothPlastic, dayColor = dayColor }
	if extra then
		for k, v in extra do
			o[k] = v
		end
	end
	return o
end

local function dim(c: Color3, k: number): Color3
	return Color3.new(c.R * k, c.G * k, c.B * k)
end

------------------------------------------------------------------------------------------------------
-- 글자 폭 추정 (em = 글자 높이 단위). TextScaled 가 넘치면 줄여 주므로 약간 넉넉히.
------------------------------------------------------------------------------------------------------
local function lineEm(s: string): number
	local w = 0
	for _, c in utf8.codes(s) do
		if c >= 0xAC00 and c <= 0xD7A3 then
			w += 0.96
		elseif c == 32 then
			w += 0.3
		elseif c >= 65 and c <= 90 then
			w += 0.7
		elseif c >= 48 and c <= 57 then
			w += 0.6
		elseif c == 46 or c == 44 or c == 58 or c == 39 or c == 183 then
			w += 0.3
		elseif c < 128 then
			w += 0.55
		else
			w += 0.92
		end
	end
	return w
end

local function textEm(s: string): number
	local best = 0
	for _, ln in string.split(s, "\n") do
		best = math.max(best, lineEm(ln))
	end
	return best
end

local function lineCount(s: string): number
	return #string.split(s, "\n")
end

function Signage.textWidth(text: string, hS: number): number
	return textEm(text) * hS
end

local function verticalText(s: string): string
	local out = {}
	for _, c in utf8.codes(s) do
		if c ~= 32 then
			table.insert(out, utf8.char(c))
		end
	end
	return table.concat(out, "\n")
end

------------------------------------------------------------------------------------------------------
-- 글꼴 / SurfaceGui / TextLabel
------------------------------------------------------------------------------------------------------
local FONTS: { [string]: string } = {
	gothic = "GothamBold", -- 한글은 Roblox 한글 고딕 폴백
	black = "GothamBlack",
	medium = "GothamMedium",
	regular = "Gotham",
	road = "Highway", -- 도로표지 영문(Highway Gothic 계열)
	script = "Kalam", -- 네온 손글씨
	hand = "PermanentMarker",
	serif = "Merriweather",
	condensed = "Oswald",
	mono = "RobotoMono",
	round = "FredokaOne",
	builder = "BuilderSansBold",
}

local function setFont(t: TextLabel, key: string?, weight: string?)
	local name = FONTS[key or "gothic"] or key or "GothamBold"
	local ok, ef = pcall(function()
		return (Enum.Font :: any)[name]
	end)
	local e: Enum.Font = if ok and ef then ef else Enum.Font.GothamBold
	pcall(function()
		t.Font = e
	end)
	if weight then
		pcall(function()
			local base = Font.fromEnum(e)
			t.FontFace = Font.new(base.Family, (Enum.FontWeight :: any)[weight], Enum.FontStyle.Normal)
		end)
	end
end

export type TextOpts = {
	name: string?,
	color: Color3?,
	font: string?, -- FONTS 키 또는 Enum.Font 이름
	weight: string?, -- "Regular" | "Medium" | "Bold" | "Heavy" ... (실제 Roblox)
	align: string?, -- "left" | "center" | "right"
	valign: string?, -- "top" | "center" | "bottom"
	glow: boolean?, -- 자체 발광(LightInfluence 0)
	light: number?, -- LightInfluence 직접 지정(재귀반사 0.6 등)
	brightness: number?, -- SurfaceGui.Brightness (>1 = Future 블룸)
	pps: number?,
	maxDistance: number?,
	stroke: Color3?, -- TextStroke(트림캡·윤곽)
	strokeTransparency: number?,
	glowPx: number?, -- UIStroke 두께(px): 네온 글로/후광
	glowColor: Color3?,
	glowTransparency: number?,
	transparency: number?, -- TextTransparency
	lineHeight: number?,
	rich: boolean?,
	bg: Color3?, -- 캐리어 Gui 첫 Frame(단색 바탕). 에뮬레이터도 이 색으로 칠함
	bgGrad: { number }?, -- 바탕 UIGradient 밝기 배율 키(0~1 구간 등분), 예 {1, 0.86}
	bgGradRot: number?,
	face: Enum.NormalId?,
}

local function ppsFor(w: number, h: number, lineH: number): number
	return math.clamp(math.min(96 / math.max(lineH, 0.05), MAX_CANVAS / math.max(w, h, 0.1)), 2, 400)
end

local function newGui(p: BasePart, face: Enum.NormalId, pps: number, light: number, bright: number, maxd: number): SurfaceGui
	local g = Instance.new("SurfaceGui")
	g.Name = "Sign"
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = pps
	g.LightInfluence = light
	pcall(function()
		g.Brightness = bright
	end)
	g.MaxDistance = maxd
	g.ClipsDescendants = true
	g.AlwaysOnTop = false
	g.Parent = p
	Kit.stats.labels += 1
	return g
end

-- 단색 바탕 Frame(+ 실제 Roblox 용 UIGradient: 밝기 배율 키). 에뮬레이터는 color 로 면 전체를 칠함.
local function field(g: Instance, color: Color3, grad: { number }?, rot: number?, z: number?): Frame
	local f = Instance.new("Frame")
	f.Name = "Field"
	f.Size = UDim2.fromScale(1, 1)
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.ZIndex = z or 1
	if grad and #grad >= 2 then
		local keys = {}
		for i, k in grad do
			local t = (i - 1) / (#grad - 1)
			table.insert(keys, ColorSequenceKeypoint.new(t, Color3.new(k, k, k)))
		end
		local gr = Instance.new("UIGradient")
		gr.Color = ColorSequence.new(keys)
		gr.Rotation = rot or 90
		gr.Parent = f
	end
	f.Parent = g
	return f
end

-- 실제 Roblox 전용 장식 Frame (첫 Frame 이 아니므로 에뮬레이터는 무시). corner = 0..0.5 (0.5 = 원)
local function deco(g: Instance, u: number, v: number, w: number, h: number, color: Color3, corner: number?, tr: number?, z: number?, rot: number?): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(u, 1 - v)
	f.Size = UDim2.fromScale(w, h)
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.BackgroundTransparency = tr or 0
	f.ZIndex = z or 2
	f.Rotation = rot or 0
	if corner and corner > 0 then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(corner, 0)
		c.Parent = f
	end
	f.Parent = g
	return f
end

local XAL = { left = Enum.TextXAlignment.Left, center = Enum.TextXAlignment.Center, right = Enum.TextXAlignment.Right }
local YAL = { top = Enum.TextYAlignment.Top, center = Enum.TextYAlignment.Center, bottom = Enum.TextYAlignment.Bottom }

local function addLabel(g: Instance, text: string, o: TextOpts, pos: UDim2?, size: UDim2?, z: number?): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = o.name or "Text"
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	t.Position = pos or UDim2.new()
	t.Size = size or UDim2.fromScale(1, 1)
	t.ZIndex = z or 3
	t.Text = text
	t.TextScaled = true
	t.TextWrapped = false
	t.RichText = o.rich == true
	setFont(t, o.font, o.weight)
	t.TextColor3 = o.color or C.white
	t.TextTransparency = o.transparency or 0
	t.TextXAlignment = XAL[o.align or "center"] or Enum.TextXAlignment.Center
	t.TextYAlignment = YAL[o.valign or "center"] or Enum.TextYAlignment.Center
	if o.lineHeight then
		t.LineHeight = o.lineHeight
	end
	if o.stroke then
		t.TextStrokeColor3 = o.stroke
		t.TextStrokeTransparency = o.strokeTransparency or 0.3
	end
	if o.glowPx and o.glowPx > 0 then
		local s = Instance.new("UIStroke")
		s.Color = o.glowColor or t.TextColor3
		s.Thickness = o.glowPx
		s.Transparency = o.glowTransparency or 0.5
		s.LineJoinMode = Enum.LineJoinMode.Round
		pcall(function()
			s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		end)
		s.Parent = t
	end
	t.Parent = g
	return t
end

-- 캐리어 글자판: cf = 글자 평면 중심(로컬 -Z = 보는 쪽), 크기 wS × hS (stud)
function Signage.text(parent: Instance, cf: CFrame, wS: number, hS: number, text: string, opts: TextOpts?): BasePart
	local o: TextOpts = opts or {}
	local n = lineCount(text)
	local pps = o.pps or ppsFor(wS, hS, hS / n)
	local p = Kit.part(parent, cf * CFrame.new(0, 0, 0.025), Vector3.new(wS, hS, 0.05), { name = o.name or "SignText", transparency = 1, collide = false, query = false, shadow = false })
	local light = o.light or (if o.glow then 0 else 1)
	local g = newGui(p, o.face or FRONT, pps, light, o.brightness or (if o.glow then 1.2 else 1), o.maxDistance or 600)
	if o.bg then
		field(g, o.bg, o.bgGrad, o.bgGradRot)
	end
	addLabel(g, text, o)
	return p
end

local function textAt(parent: Instance, F: CFrame, u: number, v: number, d: number, w: number, h: number, text: string, o: TextOpts): BasePart
	return Signage.text(parent, at(F, u, v, d), w, h, text, o)
end

------------------------------------------------------------------------------------------------------
-- 도형 엔진 (픽토그램·로고·포스터 그래픽): 정규화 좌표 u,v ∈ [0,1] (v 위), 크기 w,h 는 판 W,H 기준.
--   k = "c" 원 | "r" 사각형(rot 도) | "ring" 고리(t 두께, 다각형 조각) | "tri" 이등변 삼각형(rot 0 = 위를 가리킴)
--   z = 층(0,1,2.. → GAP 씩 앞으로), c = 색, glow = Neon
------------------------------------------------------------------------------------------------------
export type Shape = { k: string, u: number, v: number, w: number, h: number?, rot: number?, t: number?, c: Color3?, z: number?, n: number? }

local function triangle(parent: Instance, F: CFrame, cu: number, cv: number, base: number, height: number, ang: number, d0: number, d1: number, color: Color3, mat: Enum.Material, name: string, extra: { [string]: any }?)
	-- 이등변 삼각형: 중심(cu,cv)은 외접 상자 중심, ang = 꼭짓점 방향(도, 0 = 오른쪽, 90 = 위)
	local a = math.rad(ang)
	local xu, xv = math.cos(a), math.sin(a) -- x' (꼭짓점 쪽)
	local yu, yv = -math.sin(a), math.cos(a) -- y'
	-- 밑변 중심 = 중심 - x' * height/2
	local bu, bv = cu - xu * height / 2, cv - xv * height / 2
	local t = d1 - d0
	local xs = Vector3.new(-xu, xv, 0) -- 로컬(부호: u → -X)
	local ys = Vector3.new(-yu, yv, 0)
	for _, sgn in { 1, -1 } do
		local wy = ys * sgn
		local wz = -xs
		local wx = wy:Cross(wz)
		local pu = bu + xu * height / 2 + yu * sgn * base / 4
		local pv = bv + xv * height / 2 + yv * sgn * base / 4
		local pos = at(F, pu, pv, (d0 + d1) / 2)
		local cf = pos * CFrame.fromMatrix(Vector3.zero, wx, wy, wz)
		local o = opt(name, color, mat, extra)
		o.shape = "Wedge"
		Kit.part(parent, cf, Vector3.new(t, base / 2, height), o)
	end
end
Signage.triangle = triangle

-- 화살표: 중심(cu,cv), 전체 길이 len, 축 굵기 ws, 머리 폭 wh, 머리 길이 lh, 방향 ang(도)
local function arrow(parent: Instance, F: CFrame, cu: number, cv: number, len: number, ws: number, wh: number, lh: number, ang: number, d0: number, d1: number, color: Color3, mat: Enum.Material, extra: { [string]: any }?)
	local a = math.rad(ang)
	local xu, xv = math.cos(a), math.sin(a)
	local shaft = len - lh
	local su, sv = cu - xu * (len / 2) + xu * (shaft + 0.05) / 2, cv - xv * (len / 2) + xv * (shaft + 0.05) / 2
	vbox(parent, F, su, sv, d0, d1, shaft + 0.05, ws, color, mat, "ArrowShaft", extra, ang)
	local hu, hv = cu + xu * (len / 2 - lh / 2), cv + xv * (len / 2 - lh / 2)
	triangle(parent, F, hu, hv, wh, lh, ang, d0, d1, color, mat, "ArrowHead", extra)
end
Signage.arrow = arrow

local ARROW_ANG: { [string]: number } = { right = 0, upright = 45, up = 90, upleft = 135, left = 180, down = 270, downleft = 225, downright = 315 }

-- shapes → 파트. F = 판 중심 프레임, W×H = 판 크기(stud), base = 판 앞면 d. 반환: 최대 층 앞면 d
function Signage.shapes(parent: Instance, F: CFrame, W: number, H: number, list: { Shape }, base: number, defaultColor: Color3, mat: Enum.Material?, extra: { [string]: any }?): number
	local top = base
	local m = mat or MAT.SmoothPlastic
	for _, s in list do
		local z = s.z or 0
		-- 뒷면 = 판 앞면(묻지 않음): 판 가장자리에 닿는 도형의 옆면이 판 옆면과 같은 평면에서 겹치지 않도록
		local d0, d1 = base, base + GAP * (z + 1)
		top = math.max(top, d1)
		local u, v = (s.u - 0.5) * W, (s.v - 0.5) * H
		local col = s.c or defaultColor
		if s.k == "c" then
			vdisc(parent, F, u, v, d0, d1, s.w * W, col, m, "Shape", extra)
		elseif s.k == "r" then
			vbox(parent, F, u, v, d0, d1, s.w * W, (s.h or s.w) * H, col, m, "Shape", extra, s.rot)
		elseif s.k == "tri" then
			triangle(parent, F, u, v, s.w * W, (s.h or s.w) * H, 90 + (s.rot or 0), d0, d1, col, m, "Shape", extra)
		elseif s.k == "ring" then
			local R = s.w * W / 2
			local t = (s.t or 0.08) * W
			local n = s.n or 16
			local rm = R - t / 2
			local seg = 2 * rm * math.tan(math.pi / n) + t * 0.55
			for i = 0, n - 1 do
				local th = (i + 0.5) * 2 * math.pi / n
				vbox(parent, F, u + rm * math.cos(th), v + rm * math.sin(th), d0, d1, t, seg, col, m, "Shape", extra, math.deg(th))
			end
		end
	end
	return top
end

-- shapes → 실제 Roblox Gui Frame (에뮬레이터 비표시; 판 Gui 의 첫 Frame 다음에 추가)
local function shapesGui(g: Instance, list: { Shape }, W: number, H: number, pps: number, defaultColor: Color3)
	for _, s in list do
		local col = s.c or defaultColor
		local z = 3 + (s.z or 0)
		if s.k == "c" then
			deco(g, s.u, s.v, s.w, s.w * W / H, col, 0.5, 0, z)
		elseif s.k == "r" then
			deco(g, s.u, s.v, s.w, s.h or s.w, col, 0, 0, z, -(s.rot or 0))
		elseif s.k == "ring" then
			local f = deco(g, s.u, s.v, s.w, s.w * W / H, col, 0.5, 1, z)
			local st = Instance.new("UIStroke")
			st.Color = col
			st.Thickness = (s.t or 0.08) * W * pps
			pcall(function()
				st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			end)
			pcall(function()
				st.BorderStrokePosition = Enum.BorderStrokePosition.Inner
			end)
			st.Parent = f
		elseif s.k == "tri" then
			-- Frame 은 삼각형이 없으므로 계단형 근사(4 단)
			local h = s.h or s.w
			for i = 0, 3 do
				local f = (i + 0.5) / 4
				local a = math.rad(90 + (s.rot or 0))
				local ox, oy = math.cos(a), math.sin(a)
				local cu = s.u + ox * h * (f - 0.5)
				local cv = s.v + oy * h * (f - 0.5) * W / H
				local wf = s.w * (1 - (i + 0.5) / 4)
				deco(g, cu, cv, wf, h / 4 + 0.004, col, 0, 0, z, -(s.rot or 0))
			end
		end
	end
end

------------------------------------------------------------------------------------------------------
-- 1) 채널 간판 (입체 글자)
------------------------------------------------------------------------------------------------------
export type ChannelOpts = {
	name: string?,
	heightM: number?, -- 글자 높이(기본 0.6 m; 몰 0.6~0.9, 가로 간판 0.35~0.45)
	mode: string?, -- "front"(전면발광, 기본) | "halo"(후광) | "unlit"(금속 비조명)
	face: Color3?, -- 앞면 색(전면발광 = 아크릴 발광색)
	returns: Color3?, -- 옆면(리턴) 색
	trim: Color3?, -- 트림캡(앞면 테두리)
	halo: Color3?, -- 후광 색
	depthM: number?, -- 글자 두께(기본 0.1 m)
	layers: number?, -- 겹 수(기본 전면 4 / 그 외 3)
	raceway: boolean?, -- 레이스웨이 바(전면발광 기본 true)
	racewayColor: Color3?,
	sub: string?, -- 아래 줄(영문 등)
	subScale: number?, -- 아래 줄 글자 높이 / 주 글자 높이 (기본 0.36)
	font: string?,
	weight: string?,
	mark: { kind: string, color: Color3?, text: string?, textColor: Color3? }?, -- 로고: circle ring square diamond
	brightness: number?,
	maxDistance: number?,
}

function Signage.channel(parent: Instance, cf: CFrame, text: string, opts: ChannelOpts?): BasePart
	local o: ChannelOpts = opts or {}
	local mdl = newModel(parent, o.name or "ChannelSign")
	local mode = o.mode or "front"
	local hl = M(o.heightM or 0.6)
	local depth = math.max(M(o.depthM or 0.1), 0.2)
	local n = math.max(2, o.layers or (if mode == "front" then 4 else 3))
	local face = o.face or (if mode == "front" then C.white elseif mode == "halo" then rgb(196, 198, 202) else rgb(200, 164, 98))
	local ret = o.returns or (if mode == "front" then rgb(32, 32, 36) else dim(face, 0.62))
	local trim = o.trim or (if mode == "front" then dim(face, 0.55) else dim(face, 0.8))
	local font = o.font or "black"
	local maxd = o.maxDistance or 1400
	local bright = o.brightness or 1.8
	-- 배치
	local ch = hl * 1.22
	local tw = textEm(text) * hl * 1.04 + hl * 0.3
	local sh = hl * (o.subScale or 0.36)
	local subW = if o.sub then textEm(o.sub) * sh * 1.08 + sh * 0.4 else 0
	local blockW = math.max(tw, subW)
	local markW = if o.mark then hl * 1.2 else 0
	local gapW = if o.mark then hl * 0.35 else 0
	local totalW = markW + gapW + blockW
	local u0 = -totalW / 2
	local textU = u0 + markW + gapW + blockW / 2
	local vMain = if o.sub then sh * 0.7 else 0
	local vSub = vMain - hl * 0.5 - sh * 0.9
	-- 바탕 깊이
	local zb: number
	local main: BasePart? = nil
	local raceway = o.raceway
	if raceway == nil then
		raceway = mode == "front"
	end
	if raceway then
		local rd = M(0.16)
		local rh = M(0.22)
		local rc = o.racewayColor or rgb(92, 94, 98)
		main = vbox(mdl, cf, 0, vMain - hl * 0.1, -0.04, rd, totalW + hl * 0.5, rh, rc, MAT.Metal, "Raceway")
		if o.sub then
			vbox(mdl, cf, textU, vSub - sh * 0.1, -0.04, rd, subW + sh * 0.5, M(0.12), rc, MAT.Metal, "Raceway")
		end
		zb = rd + GAP
	elseif mode == "halo" then
		zb = M(0.05) + 0.16
	else
		zb = GAP
	end
	-- 후광: 벽 위 빛 번짐(반투명 Neon 판) + 글자 모양 후광(UIStroke)
	if mode == "halo" then
		local hc = o.halo or rgb(255, 222, 170)
		textAt(mdl, cf, textU, vMain, 0.1, tw, ch, text, { name = "Halo", color = hc, font = font, weight = o.weight, glow = true, brightness = 2.6, transparency = 0.1, glowPx = math.max(2, hl * 0.09 * ppsFor(tw, ch, ch)), glowColor = hc, glowTransparency = 0.55, maxDistance = maxd })
		if o.sub then
			textAt(mdl, cf, textU, vSub, 0.1, subW, sh * 1.22, o.sub, { name = "Halo", color = hc, font = font, glow = true, brightness = 2.4, transparency = 0.15, glowPx = 3, glowTransparency = 0.55, maxDistance = maxd })
		end
	end
	-- 글자 층: 뒤(리턴) → 앞(면)
	for k = 0, n - 1 do
		local d = zb + depth * k / (n - 1)
		local isFace = k == n - 1
		local lo: TextOpts = {
			name = if isFace then "LetterFace" else "LetterReturn",
			color = if isFace then face else ret,
			font = font,
			weight = o.weight,
			maxDistance = maxd,
			stroke = if isFace then trim else ret,
			strokeTransparency = if isFace then 0.15 else 0,
		}
		if isFace and mode == "front" then
			lo.glow = true
			lo.brightness = bright
		end
		local p = textAt(mdl, cf, textU, vMain, d, tw, ch, text, lo)
		if isFace and not main then
			main = p
		end
		if o.sub and (k == 0 or isFace) then
			textAt(mdl, cf, textU, vSub, d, subW, sh * 1.22, o.sub, lo)
		end
	end
	-- 로고 마크(입체 채널 로고)
	if o.mark then
		local mk = o.mark
		local mc = mk.color or face
		local md = hl * 1.12
		local mu = u0 + markW / 2
		local d0, d1 = zb - 0.03, zb + depth
		local lit = mode == "front"
		local mat = if lit then MAT.Neon else MAT.Metal
		local ex = if lit then glowOpt(mc) else nil
		local mcol = if lit then dim(mc, 0.85) else mc
		if mk.kind == "square" then
			vbox(mdl, cf, mu, vMain, d0, d1, md * 0.9, md * 0.9, mcol, mat, "LogoMark", ex)
		elseif mk.kind == "diamond" then
			vbox(mdl, cf, mu, vMain, d0, d1, md * 0.72, md * 0.72, mcol, mat, "LogoMark", ex, 45)
		else
			vdisc(mdl, cf, mu, vMain, d0, d1, md, mcol, mat, "LogoMark", ex)
		end
		-- 옆면 테(리턴)
		if mk.kind == "ring" then
			vdisc(mdl, cf, mu, vMain, d0, d1 + GAP, md * 0.62, ret, MAT.SmoothPlastic, "LogoInner")
		end
		if mk.text then
			local dd = d1 + (if mk.kind == "ring" then 2 * GAP else GAP)
			textAt(mdl, cf, mu, vMain, dd, md * 0.8, md * 0.8, mk.text, { name = "LogoText", color = mk.textColor or C.white, font = "black", glow = lit, brightness = bright, maxDistance = maxd })
		end
	end
	return main :: BasePart
end

------------------------------------------------------------------------------------------------------
-- 2) 라이트박스 / 플렉스 간판
------------------------------------------------------------------------------------------------------
export type LogoSpec = { kind: string, color: Color3?, color2: Color3?, text: string?, textColor: Color3? }
export type LightboxOpts = {
	name: string?,
	color: Color3?, -- 면 바탕(브랜드 색)
	text: string?,
	sub: string?,
	textColor: Color3?,
	subColor: Color3?,
	font: string?,
	weight: string?,
	align: string?, -- "center"(기본) | "left"
	logo: LogoSpec?, -- circle ring square diamond cross bars cup
	depthM: number?, -- 기본 0.2 m
	frameM: number?, -- 프레임 폭(기본 0.05 m)
	frameColor: Color3?,
	lit: boolean?, -- 기본 true
	brightness: number?,
	maxDistance: number?,
}

local function logoShapes(kind: string, c1: Color3, c2: Color3): { Shape }
	if kind == "ring" then
		return { { k = "ring", u = 0.5, v = 0.5, w = 0.9, t = 0.16, c = c1, n = 18 } }
	elseif kind == "square" then
		return { { k = "r", u = 0.5, v = 0.5, w = 0.8, h = 0.8, c = c1 } }
	elseif kind == "diamond" then
		return { { k = "r", u = 0.5, v = 0.5, w = 0.62, h = 0.62, rot = 45, c = c1 } }
	elseif kind == "cross" then
		return { { k = "r", u = 0.5, v = 0.5, w = 0.3, h = 0.86, c = c1 }, { k = "r", u = 0.5, v = 0.5, w = 0.86, h = 0.3, c = c1 } }
	elseif kind == "bars" then
		return { { k = "r", u = 0.5, v = 0.78, w = 0.86, h = 0.16, c = c1 }, { k = "r", u = 0.5, v = 0.5, w = 0.86, h = 0.16, c = c2 }, { k = "r", u = 0.5, v = 0.22, w = 0.86, h = 0.16, c = c1 } }
	elseif kind == "cup" then
		return {
			{ k = "r", u = 0.44, v = 0.46, w = 0.56, h = 0.5, c = c1 },
			{ k = "ring", u = 0.76, v = 0.5, w = 0.26, t = 0.06, c = c1, n = 10 },
			{ k = "r", u = 0.44, v = 0.14, w = 0.8, h = 0.07, c = c1 },
			{ k = "r", u = 0.36, v = 0.86, w = 0.05, h = 0.16, c = c2, rot = -12 },
			{ k = "r", u = 0.52, v = 0.86, w = 0.05, h = 0.16, c = c2, rot = -12 },
		}
	elseif kind == "drop" then
		return { { k = "c", u = 0.5, v = 0.4, w = 0.62, c = c1 }, { k = "tri", u = 0.5, v = 0.74, w = 0.44, h = 0.42, c = c1 } }
	end
	return { { k = "c", u = 0.5, v = 0.5, w = 0.9, c = c1 } }
end

function Signage.lightbox(parent: Instance, cf: CFrame, wM: number, hM: number, opts: LightboxOpts?): BasePart
	local o: LightboxOpts = opts or {}
	local mdl = newModel(parent, o.name or "Lightbox")
	local W, H = M(wM), M(hM)
	local D = math.max(M(o.depthM or 0.2), 0.45)
	local fw = math.max(M(o.frameM or 0.05), 0.12)
	local lip = 0.1
	local col = o.color or rgb(206, 36, 44)
	local lit = o.lit ~= false
	local fc = o.frameColor or rgb(198, 200, 204)
	local maxd = o.maxDistance or 1200
	-- 프레임(전체 깊이) + 발광 몸체(프레임 안쪽으로 묻힘)
	vbox(mdl, cf, 0, H / 2 - fw / 2, -0.03, D, W, fw, fc, MAT.Metal, "Frame", { reflectance = 0.1 })
	vbox(mdl, cf, 0, -H / 2 + fw / 2, -0.03, D, W, fw, fc, MAT.Metal, "Frame", { reflectance = 0.1 })
	vbox(mdl, cf, -W / 2 + fw / 2, 0, -0.03, D, fw, H - 2 * fw, fc, MAT.Metal, "Frame", { reflectance = 0.1 })
	vbox(mdl, cf, W / 2 - fw / 2, 0, -0.03, D, fw, H - 2 * fw, fc, MAT.Metal, "Frame", { reflectance = 0.1 })
	local faceD = D - lip
	local core: BasePart
	if lit then
		core = vbox(mdl, cf, 0, 0, -0.03, faceD, W - 2 * fw + 0.1, H - 2 * fw + 0.1, dim(col, 0.82), MAT.Neon, "LightFace", glowOpt(col))
	else
		core = vbox(mdl, cf, 0, 0, -0.03, faceD, W - 2 * fw + 0.1, H - 2 * fw + 0.1, col, MAT.SmoothPlastic, "Face")
	end
	-- 실제 Roblox: 면 Gui(바탕 + LED 가장자리 감쇠 그라데이션)
	local iw, ih = W - 2 * fw, H - 2 * fw
	local gpps = ppsFor(iw, ih, ih)
	local g = newGui(core, FRONT, math.min(gpps, 24), if lit then 0 else 1, if lit then (o.brightness or 1.25) else 1, maxd)
	field(g, col, { 0.9, 1, 1, 0.92 }, 0)
	-- 로고(왼쪽) + 글자
	local pad = math.min(iw, ih) * 0.14
	local tL, tR = -iw / 2 + pad, iw / 2 - pad
	if o.logo then
		local ls = ih - 2 * pad
		local lu = -iw / 2 + pad + ls / 2
		local lc = o.logo.color or C.white
		local list = logoShapes(o.logo.kind, if lit then lc else lc, o.logo.color2 or col)
		local F = at(cf, lu, 0, 0)
		local mat = if lit then MAT.Neon else MAT.SmoothPlastic
		local ex = if lit then glowOpt(lc) else nil
		local top = Signage.shapes(mdl, F, ls, ls, list, faceD, lc, mat, ex)
		if o.logo.text then
			textAt(mdl, cf, lu, 0, top + 0.05, ls * 0.7, ls * 0.7, o.logo.text, { name = "LogoText", color = o.logo.textColor or col, font = "black", glow = lit, maxDistance = maxd })
		end
		tL = lu + ls / 2 + pad * 0.8
	end
	local tc = o.textColor or C.white
	local td = faceD + 0.05
	local tw = tR - tL
	local tu = (tL + tR) / 2
	if o.text then
		local mh = if o.sub then (ih - 2 * pad) * 0.6 else (ih - 2 * pad) * 0.9
		local w = math.min(tw, textEm(o.text) * mh * 0.86 + mh * 0.2)
		local u = if o.align == "left" then tL + w / 2 else tu
		local v = if o.sub then (ih / 2 - pad) - mh / 2 else 0
		textAt(mdl, cf, u, v, td, w, mh, o.text, { name = "Title", color = tc, font = o.font or "black", weight = o.weight, glow = lit, brightness = o.brightness or 1.25, maxDistance = maxd })
		if o.sub then
			local sh = (ih - 2 * pad) * 0.3
			local sw = math.min(tw, textEm(o.sub) * sh * 0.86 + sh * 0.2)
			local su = if o.align == "left" then tL + sw / 2 else tu
			textAt(mdl, cf, su, -(ih / 2 - pad) + sh / 2, td, sw, sh, o.sub, { name = "Sub", color = o.subColor or tc, font = "medium", weight = "Medium", glow = lit, brightness = o.brightness or 1.25, maxDistance = maxd })
		end
	end
	return core
end

------------------------------------------------------------------------------------------------------
-- 3) 돌출 간판 (양면). cf = 벽면 위(간판 세로 중심 높이), 로컬 -Z = 벽에서 튀어나오는 방향. 면은 로컬 ±X.
------------------------------------------------------------------------------------------------------
export type BladeOpts = {
	name: string?,
	color: Color3?,
	textColor: Color3?,
	sub: string?, -- 아래쪽 가로 글자
	vertical: boolean?, -- 기본: 한글이면 세로 쓰기
	thickM: number?, -- 두께(기본 0.22 m)
	gapM: number?, -- 벽과 간판 사이(기본 0.25 m)
	frameColor: Color3?,
	logo: LogoSpec?, -- 위쪽 원형 로고
	lit: boolean?,
	font: string?,
	maxDistance: number?,
}

function Signage.blade(parent: Instance, cf: CFrame, wM: number, hM: number, text: string, opts: BladeOpts?): BasePart
	local o: BladeOpts = opts or {}
	local mdl = newModel(parent, o.name or "BladeSign")
	local W, H = M(wM), M(hM)
	local T = math.max(M(o.thickM or 0.22), 0.5)
	local gap = M(o.gapM or 0.25)
	local fw = 0.14
	local lip = 0.08
	local col = o.color or rgb(30, 96, 170)
	local fc = o.frameColor or rgb(200, 202, 206)
	local lit = o.lit ~= false
	local maxd = o.maxDistance or 900
	local S = cf * CFrame.new(0, 0, -(gap + W / 2)) -- 간판 중심(로컬 Z = 깊이 방향, X = 두께)
	local function sbox(x: number, y: number, z: number, sx: number, sy: number, sz: number, c: Color3, mat: Enum.Material, name: string, extra: any?): BasePart
		return Kit.part(mdl, S * CFrame.new(x, y, z), Vector3.new(sx, sy, sz), opt(name, c, mat, extra))
	end
	sbox(0, H / 2 - fw / 2, 0, T, fw, W, fc, MAT.Metal, "Frame", { reflectance = 0.1 })
	sbox(0, -H / 2 + fw / 2, 0, T, fw, W, fc, MAT.Metal, "Frame", { reflectance = 0.1 })
	sbox(0, 0, W / 2 - fw / 2, T, H - 2 * fw, fw, fc, MAT.Metal, "Frame", { reflectance = 0.1 })
	sbox(0, 0, -W / 2 + fw / 2, T, H - 2 * fw, fw, fc, MAT.Metal, "Frame", { reflectance = 0.1 })
	sbox(0, H / 2 + 0.06, 0, T + 0.12, 0.12, W + 0.12, rgb(70, 72, 78), MAT.Metal, "Cap")
	local core: BasePart
	if lit then
		core = sbox(0, 0, 0, T - 2 * lip, H - 2 * fw + 0.1, W - 2 * fw + 0.1, dim(col, 0.82), MAT.Neon, "LightFace", glowOpt(col))
	else
		core = sbox(0, 0, 0, T - 2 * lip, H - 2 * fw + 0.1, W - 2 * fw + 0.1, col, MAT.SmoothPlastic, "Face")
	end
	local iw, ih = W - 2 * fw, H - 2 * fw
	for _, face in { Enum.NormalId.Right, Enum.NormalId.Left } do
		local g = newGui(core, face, math.min(ppsFor(iw, ih, ih), 24), if lit then 0 else 1, 1.25, maxd)
		field(g, col, { 0.9, 1, 1, 0.9 }, 90)
	end
	local vert = o.vertical
	if vert == nil then
		vert = not string.find(text, "\n") and utf8.len(text) ~= nil and (utf8.len(text) :: number) <= 6 and lineEm(text) > (utf8.len(text) :: number) * 0.8
	end
	local txt = if vert then verticalText(text) else text
	local tc = o.textColor or C.white
	for _, s in { 1, -1 } do
		local Fs = S * CFrame.new(s * (T / 2 - lip), 0, 0) * CFrame.Angles(0, -s * math.pi / 2, 0)
		local pad = iw * 0.12
		local logoH = if o.logo then iw - 2 * pad else 0
		local subH = if o.sub then ih * 0.1 else 0
		local th = ih - 2 * pad - logoH - subH
		local tv = (subH - logoH) / 2
		local top = 0.0
		if o.logo then
			local lc = o.logo.color or C.white
			top = Signage.shapes(mdl, at(Fs, 0, ih / 2 - pad - logoH / 2, 0), logoH, logoH, logoShapes(o.logo.kind, lc, o.logo.color2 or col), 0, lc, if lit then MAT.Neon else MAT.SmoothPlastic, if lit then glowOpt(lc) else nil)
			if o.logo.text then
				textAt(mdl, Fs, 0, ih / 2 - pad - logoH / 2, top + 0.05, logoH * 0.7, logoH * 0.7, o.logo.text, { color = o.logo.textColor or col, font = "black", glow = lit, maxDistance = maxd })
			end
		end
		textAt(mdl, Fs, 0, tv, 0.05, iw - 2 * pad, th, txt, { name = "BladeText", color = tc, font = o.font or "black", glow = lit, brightness = 1.3, maxDistance = maxd, lineHeight = 0.92 })
		if o.sub then
			textAt(mdl, Fs, 0, -ih / 2 + pad * 0.6 + subH / 2, 0.05, iw - pad, subH, o.sub, { name = "BladeSub", color = tc, font = "medium", glow = lit, maxDistance = maxd })
		end
	end
	-- 브래킷: 위/아래 각관 팔 + 벽 판 + 사선 버팀
	local arm = M(0.05)
	for _, y in { H / 2 - M(0.12), -H / 2 + M(0.12) } do
		vbox(mdl, cf, 0, y, -0.05, gap + fw * 0.6, arm, arm, rgb(60, 62, 68), MAT.Metal, "BladeArm")
		vbox(mdl, cf, 0, y, -0.03, 0.06, M(0.12), M(0.18), rgb(60, 62, 68), MAT.Metal, "WallPlate")
	end
	local p0 = (cf * CFrame.new(0, -H / 2 + M(0.12) - M(0.35), 0.02)).Position
	local p1 = (cf * CFrame.new(0, -H / 2 + M(0.12), -(gap * 0.85))).Position
	rod(mdl, p0, p1, M(0.035), rgb(60, 62, 68), MAT.Metal, "Brace")
	vbox(mdl, cf, 0, -H / 2 + M(0.12) - M(0.35), -0.03, 0.06, M(0.1), M(0.12), rgb(60, 62, 68), MAT.Metal, "WallPlate")
	return core
end

------------------------------------------------------------------------------------------------------
-- 4) 네온 사인 (투명 아크릴 백커 + 스탠드오프)
------------------------------------------------------------------------------------------------------
export type NeonOpts = { name: string?, heightM: number?, font: string?, sub: string?, light: boolean?, backer: boolean?, maxDistance: number? }

function Signage.neon(parent: Instance, cf: CFrame, text: string, color: Color3, opts: NeonOpts?): BasePart
	local o: NeonOpts = opts or {}
	local mdl = newModel(parent, o.name or "NeonSign")
	local hl = M(o.heightM or 0.3)
	local font = o.font or "script"
	local nl = lineCount(text)
	local ch = hl * 1.45 * nl
	local tw = textEm(text) * hl * 0.98 + hl * 0.4
	local sh = if o.sub then hl * 0.42 else 0
	local subW = if o.sub then textEm(o.sub) * sh * 1.1 + sh * 0.3 else 0
	local bw = math.max(tw, subW) + M(0.12)
	local bh = ch + (if o.sub then sh * 1.5 else 0) + M(0.1)
	local vMain = if o.sub then sh * 0.75 else 0
	local vSub = vMain - ch / 2 - sh * 0.7
	local maxd = o.maxDistance or 500
	local b0, b1 = 0.28, 0.36 -- 아크릴 앞뒤
	local main: BasePart
	if o.backer ~= false then
		main = vbox(mdl, cf, 0, 0, b0, b1, bw, bh, rgb(214, 228, 232), MAT.Glass, "AcrylicBacker", { transparency = 0.78, reflectance = 0.15, shadow = false })
		for _, su in { -1, 1 } do
			for _, sv in { -1, 1 } do
				local u, v = su * (bw / 2 - M(0.03)), sv * (bh / 2 - M(0.03))
				vdisc(mdl, cf, u, v, -0.03, b0 + 0.02, M(0.025), rgb(200, 202, 206), MAT.Metal, "Standoff")
				vdisc(mdl, cf, u, v, b1 - 0.02, b1 + GAP, M(0.04), rgb(214, 216, 220), MAT.Metal, "StandoffCap", { reflectance = 0.3 })
			end
		end
		-- 전원선(아래로 늘어진 투명 피복선)
		local cp = (at(cf, bw * 0.3, -bh / 2, b0 + 0.04)).Position
		rod(mdl, cp, cp + (cf.UpVector * -M(0.25)) + (cf.LookVector * -0.02), 0.06, rgb(40, 40, 44), MAT.SmoothPlastic, "NeonCable")
	else
		main = vbox(mdl, cf, 0, 0, -0.02, 0.06, bw * 0.2, M(0.02), rgb(200, 202, 206), MAT.Metal, "Mount")
	end
	local pps = ppsFor(tw, ch, ch / nl)
	local base = if o.backer ~= false then b1 else 0.1
	-- 헤일로(넓은 반투명 UIStroke) → 튜브(색) → 코어(밝은 가는 글자)
	textAt(mdl, cf, 0, vMain, base + 0.02, tw, ch, text, { name = "NeonHalo", color = color, font = font, weight = "Bold", glow = true, brightness = 2.2, transparency = 0.35, glowPx = math.max(3, hl * 0.22 * pps), glowColor = color, glowTransparency = 0.82, maxDistance = maxd })
	textAt(mdl, cf, 0, vMain, base + 0.02 + GAP, tw, ch, text, { name = "NeonTube", color = color, font = font, weight = "Bold", glow = true, brightness = 3.2, glowPx = math.max(1.5, hl * 0.035 * pps), glowColor = color, glowTransparency = 0.1, maxDistance = maxd })
	textAt(mdl, cf, 0, vMain, base + 0.02 + 2 * GAP, tw, ch, text, { name = "NeonCore", color = color:Lerp(Color3.new(1, 1, 1), 0.38), font = font, weight = "Regular", glow = true, brightness = 4, maxDistance = maxd })
	if o.sub then
		textAt(mdl, cf, 0, vSub, base + 0.02 + GAP, subW, sh * 1.3, o.sub, { name = "NeonSub", color = color, font = "regular", glow = true, brightness = 3, glowPx = 2, glowTransparency = 0.5, maxDistance = maxd })
	end
	if o.light then
		Kit.light(main, "PointLight", { color = color, brightness = 1.4, range = M(3.5) })
	end
	return main
end

------------------------------------------------------------------------------------------------------
-- 5) 현수막 (천 + 아일렛 + 끈 + 기둥). cf = 현수막 중심, 로컬 -Z = 앞
------------------------------------------------------------------------------------------------------
export type BannerOpts = {
	name: string?,
	color: Color3?,
	textColor: Color3?,
	sub: string?,
	subColor: Color3?,
	accent: Color3?, -- 왼쪽 세로 띠 색
	tiltDeg: number?, -- 바람에 아래가 앞으로 밀린 각(기본 4)
	poles: boolean?, -- 양끝 기둥(기본 true)
	poleM: number?, -- 기둥 높이(m), 기본 = 현수막 윗변 + 0.3
	groundY: number?, -- 기둥 바닥 높이(월드 Y). 없으면 cf 아래 (poleM)
	font: string?,
	maxDistance: number?,
}

function Signage.banner(parent: Instance, cf: CFrame, wM: number, hM: number, text: string, opts: BannerOpts?): BasePart
	local o: BannerOpts = opts or {}
	local mdl = newModel(parent, o.name or "Banner")
	local W, H = M(wM), M(hM)
	local col = o.color or C.white
	local tc = o.textColor or rgb(200, 24, 32)
	local maxd = o.maxDistance or 500
	local tilt = math.rad(o.tiltDeg or 4)
	-- 천: 윗변을 축으로 아래가 앞으로(바람)
	local Fb = cf * CFrame.new(0, H / 2, 0) * CFrame.Angles(tilt, 0, 0) * CFrame.new(0, -H / 2, 0)
	local cloth = vbox(mdl, Fb, 0, 0, -0.03, 0.03, W, H, col, MAT.Fabric, "BannerCloth")
	local g = newGui(cloth, FRONT, math.min(ppsFor(W, H, H), 16), 1, 1, maxd)
	field(g, col, { 1, 0.9, 1, 0.94, 1, 0.9, 1 }, 0) -- 천 주름 음영(실제 Roblox)
	field(g, col, { 1, 1, 0.84 }, 90, 2).BackgroundTransparency = 0.6
	-- 시접(위/아래 0.04 m, 끈이 들어간 두꺼운 단) + 아일렛
	local hem = M(0.04)
	vbox(mdl, Fb, 0, H / 2 - hem / 2, -0.09, 0.09, W, hem, dim(col, 0.93), MAT.Fabric, "Hem")
	vbox(mdl, Fb, 0, -H / 2 + hem / 2, -0.09, 0.09, W, hem, dim(col, 0.93), MAT.Fabric, "Hem")
	local accentW = 0
	if o.accent then
		accentW = W * 0.06
		vbox(mdl, Fb, -W / 2 + accentW / 2, 0, -0.02, 0.03 + GAP, accentW, H - 2 * hem, o.accent, MAT.Fabric, "BannerAccent")
	end
	local nG = math.max(2, math.floor(wM / 1.0) + 1)
	for i = 0, nG - 1 do
		local u = -W / 2 + M(0.06) + (W - M(0.12)) * i / (nG - 1)
		for _, v in { H / 2 - hem / 2, -H / 2 + hem / 2 } do
			if i == 0 or i == nG - 1 or v > 0 then
				vdisc(mdl, Fb, u, v, -0.12, 0.09 + GAP, M(0.025), rgb(196, 198, 202), MAT.Metal, "Grommet", { reflectance = 0.2 })
			end
		end
	end
	-- 글자
	local pad = H * 0.1
	local tw = W - accentW - 2 * pad
	local tu = accentW / 2
	local mh = if o.sub then (H - 2 * hem) * 0.56 else (H - 2 * hem) * 0.78
	textAt(mdl, Fb, tu, if o.sub then (H / 2 - hem - pad * 0.5 - mh / 2) else 0, 0.03 + 0.05, tw, mh, text, { name = "BannerText", color = tc, font = o.font or "black", maxDistance = maxd })
	if o.sub then
		local shh = (H - 2 * hem) * 0.26
		textAt(mdl, Fb, tu, -H / 2 + hem + pad * 0.5 + shh / 2, 0.03 + 0.05, tw, shh, o.sub, { name = "BannerSub", color = o.subColor or C.ink, font = "gothic", maxDistance = maxd })
	end
	-- 기둥 + 끈(아일렛 → 기둥, 처짐)
	if o.poles ~= false then
		local up = cf.UpVector
		local topY = H / 2 + M(0.3)
		local poleH = if o.poleM then M(o.poleM) else topY + M(1.6)
		for _, su in { -1, 1 } do
			local pu = su * (W / 2 + M(0.35))
			local pTop = at(cf, pu, topY, 0).Position
			local pBot = pTop - up * poleH
			if o.groundY then
				pBot = Vector3.new(pBot.X, o.groundY - 0.3, pBot.Z)
			end
			rod(mdl, pBot, pTop, M(0.06), rgb(150, 154, 158), MAT.Metal, "BannerPole", { collide = true, query = true })
			for _, v in { H / 2 - hem / 2, -H / 2 + hem / 2 } do
				local g0 = at(Fb, su * (W / 2 - M(0.06)), v, 0).Position
				local pp = at(cf, pu, v + M(0.05), 0).Position
				local mid = (g0 + pp) / 2 - up * M(0.04)
				rod(mdl, g0, mid, M(0.012) + 0.03, rgb(236, 232, 220), MAT.Fabric, "Tie")
				rod(mdl, mid, pp, M(0.012) + 0.03, rgb(236, 232, 220), MAT.Fabric, "Tie")
			end
		end
	end
	return cloth
end

------------------------------------------------------------------------------------------------------
-- 6) 실사 출력 포스터 (포맥스 판 + 스냅 프레임 / 테이프)
------------------------------------------------------------------------------------------------------
type PText = { u: number, v: number, w: number, h: number, text: string, color: Color3?, font: string?, weight: string?, align: string? }
type PDesign = { bg: Color3, grad: { number }?, shapes: { Shape }, gui: { Shape }?, texts: { PText }, qr: { number }?, ink: Color3 }

local function posterDesign(design: string, rng: Random): PDesign
	local white, ink = C.white, C.ink
	if design == "sale" then
		local red = rgb(212, 28, 44)
		return {
			bg = red,
			grad = { 1.08, 0.86 },
			ink = white,
			shapes = {
				{ k = "c", u = 0.76, v = 0.72, w = 0.36, c = rgb(255, 214, 40), z = 0 },
				{ k = "r", u = 0.5, v = 0.115, w = 1.0, h = 0.11, c = rgb(24, 24, 28), z = 0 },
				-- 쇼핑백(상품 사진 대용): 몸통 + 손잡이
				{ k = "r", u = 0.26, v = 0.36, w = 0.24, h = 0.22, c = rgb(242, 236, 224), z = 0 },
				{ k = "r", u = 0.26, v = 0.49, w = 0.12, h = 0.035, c = rgb(242, 236, 224), z = 0 },
				{ k = "r", u = 0.5, v = 0.33, w = 0.2, h = 0.17, c = rgb(30, 30, 34), z = 0 },
				{ k = "r", u = 0.5, v = 0.43, w = 0.1, h = 0.03, c = rgb(30, 30, 34), z = 0 },
			},
			gui = { { k = "r", u = 0.5, v = 0.62, w = 0.9, h = 0.006, c = rgb(255, 255, 255) } },
			texts = {
				{ u = 0.36, v = 0.84, w = 0.62, h = 0.13, text = "SALE", font = "black", weight = "Heavy" },
				{ u = 0.36, v = 0.7, w = 0.6, h = 0.06, text = "가을 시즌오프", font = "black" },
				{ u = 0.76, v = 0.745, w = 0.24, h = 0.075, text = "최대", color = red, font = "black" },
				{ u = 0.76, v = 0.665, w = 0.28, h = 0.09, text = "70%", color = red, font = "black" },
				{ u = 0.5, v = 0.115, w = 0.84, h = 0.06, text = "11.01 MON — 11.30 SUN", font = "condensed" },
				{ u = 0.5, v = 0.03, w = 0.9, h = 0.03, text = "일부 품목 제외 · 재고 소진 시 조기 종료될 수 있습니다", font = "regular" },
			},
			qr = { 0.86, 0.32, 0.16 },
		}
	elseif design == "event" then
		local navy = rgb(18, 24, 66)
		local pal = { rgb(255, 196, 70), rgb(240, 80, 160), rgb(80, 210, 255), rgb(255, 120, 60), rgb(170, 110, 255) }
		local shapes: { Shape } = {}
		-- 불꽃: 중심 원 + 방사형 점
		for b = 1, 3 do
			local cu, cv, r = 0.22 + (b - 1) * 0.3 + rng:NextNumber(-0.04, 0.04), 0.66 + rng:NextNumber(-0.06, 0.08), rng:NextNumber(0.12, 0.17)
			local c = pal[rng:NextInteger(1, #pal)]
			table.insert(shapes, { k = "c", u = cu, v = cv, w = r * 0.22, c = c, z = 0 })
			local n = 10
			for i = 0, n - 1 do
				local a = i * 2 * math.pi / n + rng:NextNumber(-0.1, 0.1)
				local rr = r * rng:NextNumber(0.75, 1.0)
				-- 광선(포스터 비율 보정: v 는 0.7 배)
				local du, dv = math.cos(a) * rr * 0.6, math.sin(a) * rr * 0.6 * 0.7
				table.insert(shapes, { k = "r", u = cu + du, v = cv + dv, w = rr * 0.62, h = 0.01, rot = math.deg(math.atan2(dv * 1.4, du)), c = if i % 2 == 0 then c else c:Lerp(white, 0.45), z = 0 })
			end
		end
		table.insert(shapes, { k = "r", u = 0.5, v = 0.06, w = 1.0, h = 0.12, c = rgb(255, 196, 70), z = 0 })
		return {
			bg = navy,
			grad = { 0.7, 1.15 },
			ink = white,
			shapes = shapes,
			texts = {
				{ u = 0.5, v = 0.4, w = 0.86, h = 0.1, text = "한강 불빛 축제", font = "black" },
				{ u = 0.5, v = 0.315, w = 0.8, h = 0.045, text = "HANGANG LIGHT FESTIVAL 2026", font = "condensed" },
				{ u = 0.5, v = 0.23, w = 0.8, h = 0.06, text = "11.14 SAT — 11.15 SUN  19:30", font = "black" },
				{ u = 0.5, v = 0.165, w = 0.8, h = 0.04, text = "잠실한강공원 · 무료 입장", font = "gothic" },
				{ u = 0.5, v = 0.06, w = 0.86, h = 0.04, text = "주최 · 주관  한강공원 축제 조직위원회", color = navy, font = "gothic" },
			},
		}
	elseif design == "notice" then
		local blue = rgb(0, 72, 150)
		return {
			bg = C.paper,
			ink = ink,
			shapes = {
				{ k = "r", u = 0.5, v = 0.9, w = 1.0, h = 0.12, c = blue, z = 0 },
				{ k = "r", u = 0.5, v = 0.15, w = 0.86, h = 0.004, c = rgb(150, 150, 150), z = 0 },
			},
			texts = {
				{ u = 0.5, v = 0.9, w = 0.5, h = 0.08, text = "안   내", color = white, font = "black" },
				{ u = 0.5, v = 0.76, w = 0.86, h = 0.06, text = "자전거도로 정비 공사 안내", font = "black" },
				{ u = 0.5, v = 0.61, w = 0.84, h = 0.15, text = "기  간 : 2026. 11. 2.(월) ~ 11. 27.(금)\n구  간 : 잠실대교 남단 ~ 잠실철교\n내  용 : 노면 재포장 및 배수로 정비", font = "medium", align = "left" },
				{ u = 0.5, v = 0.38, w = 0.84, h = 0.1, text = "공사 기간 중 안전요원의 안내에 따라\n우회하여 주시기 바랍니다.", font = "regular" },
				{ u = 0.5, v = 0.25, w = 0.7, h = 0.035, text = "이용에 불편을 드려 죄송합니다.", font = "regular" },
				{ u = 0.5, v = 0.09, w = 0.7, h = 0.05, text = "한강사업본부 잠실안내센터", font = "black" },
			},
		}
	elseif design == "promo11" then
		local yellow, red = rgb(255, 212, 0), rgb(222, 26, 36)
		local deal = if rng:NextNumber() < 0.5 then "1+1" else "2+1"
		local b1, b2 = rgb(30, 120, 210), rgb(236, 92, 40)
		return {
			bg = yellow,
			grad = { 1.05, 0.9 },
			ink = ink,
			shapes = {
				{ k = "c", u = 0.5, v = 0.7, w = 0.62, c = red, z = 0 },
				{ k = "r", u = 0.5, v = 0.9, w = 0.58, h = 0.075, c = ink, z = 0 },
				-- 페트병 2 (몸통 + 어깨 + 뚜껑 + 라벨)
				{ k = "r", u = 0.3, v = 0.27, w = 0.13, h = 0.2, c = b1, z = 0 },
				{ k = "c", u = 0.3, v = 0.38, w = 0.13, c = b1, z = 0 },
				{ k = "r", u = 0.3, v = 0.44, w = 0.05, h = 0.04, c = white, z = 0 },
				{ k = "r", u = 0.3, v = 0.27, w = 0.13, h = 0.07, c = white, z = 1 },
				{ k = "r", u = 0.46, v = 0.27, w = 0.13, h = 0.2, c = b2, z = 0 },
				{ k = "c", u = 0.46, v = 0.38, w = 0.13, c = b2, z = 0 },
				{ k = "r", u = 0.46, v = 0.44, w = 0.05, h = 0.04, c = white, z = 0 },
				{ k = "r", u = 0.46, v = 0.27, w = 0.13, h = 0.07, c = white, z = 1 },
			},
			texts = {
				{ u = 0.5, v = 0.9, w = 0.5, h = 0.06, text = "행사상품", color = yellow, font = "black" },
				{ u = 0.5, v = 0.69, w = 0.5, h = 0.2, text = deal, color = white, font = "black", weight = "Heavy" },
				{ u = 0.76, v = 0.32, w = 0.38, h = 0.06, text = "탄산음료", font = "black" },
				{ u = 0.76, v = 0.26, w = 0.38, h = 0.04, text = "500ml 전 품목", font = "gothic" },
				{ u = 0.5, v = 0.12, w = 0.6, h = 0.09, text = "1,800원", color = red, font = "black" },
				{ u = 0.5, v = 0.04, w = 0.9, h = 0.03, text = "11월 한정 · 행사 상품은 점포별로 다를 수 있습니다", font = "regular" },
			},
		}
	elseif design == "realestate" then
		local navy, redT, blueT, greenT = rgb(20, 44, 96), rgb(214, 40, 40), rgb(30, 90, 190), rgb(30, 140, 80)
		local cardC = rgb(232, 236, 242)
		return {
			bg = C.white,
			ink = ink,
			shapes = {
				{ k = "r", u = 0.5, v = 0.92, w = 1.0, h = 0.12, c = navy, z = 0 },
				{ k = "r", u = 0.5, v = 0.71, w = 0.9, h = 0.2, c = cardC, z = 0 },
				{ k = "r", u = 0.5, v = 0.48, w = 0.9, h = 0.2, c = cardC, z = 0 },
				{ k = "r", u = 0.5, v = 0.25, w = 0.9, h = 0.2, c = cardC, z = 0 },
				{ k = "r", u = 0.15, v = 0.77, w = 0.14, h = 0.05, c = redT, z = 1 },
				{ k = "r", u = 0.15, v = 0.54, w = 0.14, h = 0.05, c = blueT, z = 1 },
				{ k = "r", u = 0.15, v = 0.31, w = 0.14, h = 0.05, c = greenT, z = 1 },
				{ k = "r", u = 0.5, v = 0.065, w = 1.0, h = 0.09, c = navy, z = 0 },
			},
			texts = {
				{ u = 0.5, v = 0.92, w = 0.8, h = 0.07, text = "급매 · 추천매물", color = white, font = "black" },
				{ u = 0.15, v = 0.77, w = 0.12, h = 0.04, text = "매매", color = white, font = "black" },
				{ u = 0.15, v = 0.54, w = 0.12, h = 0.04, text = "전세", color = white, font = "black" },
				{ u = 0.15, v = 0.31, w = 0.12, h = 0.04, text = "월세", color = white, font = "black" },
				{ u = 0.58, v = 0.7, w = 0.66, h = 0.12, text = "잠실 한강뷰 84㎡ · 22층\n19억 5,000", font = "black" },
				{ u = 0.58, v = 0.47, w = 0.66, h = 0.12, text = "신천동 59㎡ · 남향\n8억 2,000", font = "black" },
				{ u = 0.58, v = 0.24, w = 0.66, h = 0.12, text = "오피스텔 33㎡ · 역세권\n1,000 / 95", font = "black" },
				{ u = 0.5, v = 0.065, w = 0.86, h = 0.045, text = "한강공인중개사사무소  TEL 02-2203-0000", color = white, font = "gothic" },
			},
		}
	end
	-- exhibition (기본)
	local cream = rgb(238, 232, 220)
	local orange, deep = rgb(232, 96, 40), rgb(32, 40, 70)
	return {
		bg = cream,
		ink = deep,
		shapes = {
			{ k = "c", u = 0.6, v = 0.62, w = 0.66, c = orange, z = 0 },
			{ k = "r", u = 0.3, v = 0.55, w = 0.08, h = 0.5, c = deep, z = 1 },
			{ k = "c", u = 0.78, v = 0.86, w = 0.12, c = rgb(60, 110, 190), z = 1 },
			{ k = "r", u = 0.5, v = 0.28, w = 0.86, h = 0.004, c = deep, z = 0 },
		},
		texts = {
			{ u = 0.5, v = 0.2, w = 0.86, h = 0.09, text = "빛의 도시", font = "serif", weight = "Bold" },
			{ u = 0.5, v = 0.13, w = 0.7, h = 0.04, text = "CITY OF LIGHT", font = "condensed" },
			{ u = 0.3, v = 0.055, w = 0.5, h = 0.035, text = "2026. 10. 3 — 12. 28", font = "medium", align = "left" },
			{ u = 0.74, v = 0.055, w = 0.44, h = 0.03, text = "한강아트센터 기획전시실", font = "regular", align = "right" },
		},
	}
end

export type PosterOpts = { name: string?, frame: string?, lit: boolean?, maxDistance: number? } -- frame: "snap"(기본) | "tape" | "none"

function Signage.poster(parent: Instance, cf: CFrame, wM: number, hM: number, design: string, rng: Random, opts: PosterOpts?): BasePart
	local o: PosterOpts = opts or {}
	local mdl = newModel(parent, o.name or ("Poster_" .. design))
	local W, H = M(wM), M(hM)
	local ds = posterDesign(design, rng)
	local frame = o.frame or (if design == "notice" then "tape" else "snap")
	local maxd = o.maxDistance or 300
	local lit = o.lit == true
	local base = 0.0
	if frame == "snap" then
		-- 알루미늄 스냅 프레임(폭 2.5 cm, 두께 1.2 cm) + 뒤판
		local fw = math.max(M(0.025), 0.1)
		local fd = math.max(M(0.012), 0.12)
		vbox(mdl, cf, 0, H / 2 + fw / 2, -0.03, fd, W + 2 * fw, fw, C.alu, MAT.Metal, "SnapFrame", { reflectance = 0.25 })
		vbox(mdl, cf, 0, -H / 2 - fw / 2, -0.03, fd, W + 2 * fw, fw, C.alu, MAT.Metal, "SnapFrame", { reflectance = 0.25 })
		vbox(mdl, cf, -W / 2 - fw / 2, 0, -0.03, fd, fw, H, C.alu, MAT.Metal, "SnapFrame", { reflectance = 0.25 })
		vbox(mdl, cf, W / 2 + fw / 2, 0, -0.03, fd, fw, H, C.alu, MAT.Metal, "SnapFrame", { reflectance = 0.25 })
		base = fd - GAP
	end
	local plate = vbox(mdl, cf, 0, 0, -0.02 + (if frame == "snap" then 0 else 0.0), base, W + 0.02, H + 0.02, ds.bg, MAT.SmoothPlastic, "PosterPrint")
	if base < 0.06 then
		plate.Size = Vector3.new(plate.Size.X, plate.Size.Y, 0.06)
		plate.CFrame = at(cf, 0, 0, 0.03)
		base = 0.06
	end
	local pps = math.min(ppsFor(W, H, H * 0.06), 120)
	local g = newGui(plate, FRONT, pps, if lit then 0 else 1, if lit then 1.15 else 1, maxd)
	field(g, ds.bg, ds.grad, 90)
	if ds.gui then
		shapesGui(g, ds.gui, W, H, pps, ds.ink)
	end
	-- 큰 도형: 파트(두 렌더러)
	local top = Signage.shapes(mdl, cf, W, H, ds.shapes, base, ds.ink)
	-- 글자
	local td = top + 0.05
	for _, t in ds.texts do
		textAt(mdl, cf, (t.u - 0.5) * W, (t.v - 0.5) * H, td, t.w * W, t.h * H, t.text, { name = "PosterText", color = t.color or ds.ink, font = t.font or "gothic", weight = t.weight, align = t.align, glow = lit, maxDistance = maxd })
	end
	-- QR 코드 블록(실제 Roblox: 모듈 패턴 / 에뮬레이터: 진회색 사각형)
	if ds.qr then
		local q = ds.qr
		local s = q[3] * W
		local qp = vbox(mdl, cf, (q[1] - 0.5) * W, (q[2] - 0.5) * H, base - 0.02, base + GAP, s, s, C.white, MAT.SmoothPlastic, "QR")
		local qg = newGui(qp, FRONT, math.clamp(200 / s, 20, 200), if lit then 0 else 1, 1, 60)
		field(qg, rgb(70, 70, 74))
		deco(qg, 0.5, 0.5, 1, 1, C.white, 0, 0, 2)
		local N = 17
		local cell = 0.84 / N
		for i = 0, N - 1 do
			for j = 0, N - 1 do
				local finder = (i < 5 and j < 5) or (i >= N - 5 and j < 5) or (i < 5 and j >= N - 5)
				local on: boolean
				if finder then
					local fi = if i >= N - 5 then i - (N - 5) else i
					local fj = if j >= N - 5 then j - (N - 5) else j
					on = fi == 0 or fi == 4 or fj == 0 or fj == 4 or (fi == 2 and fj == 2)
				else
					on = rng:NextNumber() < 0.47
				end
				if on then
					deco(qg, 0.08 + (i + 0.5) * cell, 1 - (0.08 + (j + 0.5) * cell), cell + 0.002, cell + 0.002, C.black, 0, 0, 3)
				end
			end
		end
	end
	-- 테이프(안내문: 모서리 4곳 반투명 종이테이프)
	if frame == "tape" then
		for _, su in { -1, 1 } do
			for _, sv in { -1, 1 } do
				vbox(mdl, cf, su * (W / 2 - M(0.01)), sv * (H / 2 - M(0.01)), base - 0.02, base + GAP, M(0.08), M(0.03), rgb(236, 226, 196), MAT.SmoothPlastic, "Tape", { transparency = 0.25 }, su * sv * 40)
			end
		end
	end
	return plate
end

------------------------------------------------------------------------------------------------------
-- 7) 메뉴판. items: { "§COFFEE", {"아메리카노", "4,500"}, ... } — "§" 로 시작하면 섹션 제목
------------------------------------------------------------------------------------------------------
export type MenuOpts = { name: string?, bg: Color3?, ink: Color3?, accent: Color3?, frameColor: Color3?, lit: boolean?, columns: number?, sub: string?, maxDistance: number? }

function Signage.menuBoard(parent: Instance, cf: CFrame, wM: number, hM: number, title: string, items: { any }, opts: MenuOpts?): BasePart
	local o: MenuOpts = opts or {}
	local mdl = newModel(parent, o.name or "MenuBoard")
	local W, H = M(wM), M(hM)
	local bg = o.bg or rgb(28, 28, 30)
	local ink = o.ink or rgb(244, 238, 226)
	local accent = o.accent or rgb(232, 172, 82)
	local fc = o.frameColor or rgb(92, 66, 44)
	local lit = o.lit ~= false
	local maxd = o.maxDistance or 160
	local fw = math.max(M(0.03), 0.12)
	-- 나무 프레임 + 보드
	vbox(mdl, cf, 0, H / 2 - fw / 2, -0.03, 0.2, W, fw, fc, MAT.Wood, "MenuFrame")
	vbox(mdl, cf, 0, -H / 2 + fw / 2, -0.03, 0.2, W, fw, fc, MAT.Wood, "MenuFrame")
	vbox(mdl, cf, -W / 2 + fw / 2, 0, -0.03, 0.2, fw, H - 2 * fw, fc, MAT.Wood, "MenuFrame")
	vbox(mdl, cf, W / 2 - fw / 2, 0, -0.03, 0.2, fw, H - 2 * fw, fc, MAT.Wood, "MenuFrame")
	local board = vbox(mdl, cf, 0, 0, -0.03, 0.12, W - 2 * fw + 0.06, H - 2 * fw + 0.06, bg, MAT.SmoothPlastic, "MenuBoard")
	local iw, ih = W - 2 * fw, H - 2 * fw
	local bgui = newGui(board, FRONT, math.min(ppsFor(iw, ih, ih), 20), if lit then 0 else 1, 1, maxd)
	field(bgui, bg, { 1.12, 0.92 }, 90)
	local pad = math.min(iw, ih) * 0.07
	local td = 0.12 + 0.05
	-- 제목
	local titleH = ih * (if o.sub then 0.14 else 0.16)
	textAt(mdl, cf, 0, ih / 2 - pad - titleH / 2, td, iw * 0.6, titleH, title, { name = "MenuTitle", color = ink, font = "black", glow = lit, brightness = 1.1, maxDistance = maxd })
	local yTop = ih / 2 - pad - titleH - pad * 0.6
	if o.sub then
		local sh = ih * 0.05
		textAt(mdl, cf, 0, yTop - sh / 2, td, iw * 0.7, sh, o.sub, { name = "MenuSub", color = accent, font = "medium", glow = lit, maxDistance = maxd })
		yTop -= sh + pad * 0.4
	end
	-- 구분선(파트, 얇은 금색)
	vbox(mdl, cf, 0, yTop + pad * 0.25, 0.1, 0.12 + GAP, iw - 2 * pad, 0.06, accent, MAT.SmoothPlastic, "MenuRule")
	local cols = o.columns or (if #items > 9 then 2 else 1)
	local per = math.ceil(#items / cols)
	local colW = (iw - 2 * pad - (cols - 1) * pad) / cols
	local areaH = yTop - (-ih / 2 + pad)
	local rowH = math.min(areaH / per, M(0.09))
	for c = 1, cols do
		local first = (c - 1) * per + 1
		local last = math.min(#items, c * per)
		if first > last then
			break
		end
		local nRows = last - first + 1
		local colH = rowH * nRows
		local cu0 = -iw / 2 + pad + (c - 1) * (colW + pad)
		local nameW, priceW = colW * 0.7, colW * 0.28
		local nameU, priceU = cu0 + nameW / 2, cu0 + colW - priceW / 2
		local cv = yTop - colH / 2
		local function colCarrier(u: number, w: number, nm: string): SurfaceGui
			local p = Kit.part(mdl, at(cf, u, cv, td) * CFrame.new(0, 0, 0.025), Vector3.new(w, colH, 0.05), { name = nm, transparency = 1, collide = false, query = false, shadow = false })
			return newGui(p, FRONT, math.min(96 / rowH, MAX_CANVAS / math.max(w, colH)), if lit then 0 else 1, 1.1, maxd)
		end
		local gn = colCarrier(nameU, nameW, "MenuNames")
		local gp = colCarrier(priceU, priceW, "MenuPrices")
		for r = first, last do
			local it = items[r]
			local i = r - first
			local pos = UDim2.fromScale(0, i / nRows)
			local size = UDim2.fromScale(1, 1 / nRows * 0.82)
			if type(it) == "string" then
				local s = string.gsub(it, "^§", "")
				addLabel(gn, s, { name = "Section", color = accent, font = "black", align = "left" }, pos, size)
				addLabel(gp, " ", { name = "Blank", color = accent }, pos, size)
			else
				addLabel(gn, it[1], { name = "Item", color = ink, font = "medium", weight = "Medium", align = "left" }, UDim2.fromScale(0.04, i / nRows), UDim2.fromScale(0.96, 1 / nRows * 0.82))
				addLabel(gp, it[2], { name = "Price", color = ink, font = "gothic", align = "right" }, pos, size)
			end
		end
	end
	return board
end

------------------------------------------------------------------------------------------------------
-- 8) 픽토그램 (KS A 0901 / ISO 7001 / ISO 7010 느낌). sizeM = 정사각 판 한 변(restroom 은 가로 2배)
------------------------------------------------------------------------------------------------------
local function figureMan(cx: number, cy: number, su: number, sv: number, c: Color3): { Shape }
	local function S(k: string, u: number, v: number, w: number, h: number?, rot: number?): Shape
		return { k = k, u = cx + (u - 0.5) * su, v = cy + (v - 0.5) * sv, w = w * su, h = if h then h * sv else nil, rot = rot, c = c }
	end
	return {
		S("c", 0.5, 0.855, 0.16),
		S("r", 0.5, 0.585, 0.24, 0.29),
		S("r", 0.335, 0.555, 0.07, 0.3),
		S("r", 0.665, 0.555, 0.07, 0.3),
		S("r", 0.447, 0.255, 0.085, 0.37),
		S("r", 0.553, 0.255, 0.085, 0.37),
	}
end

local function figureWoman(cx: number, cy: number, su: number, sv: number, c: Color3): { Shape }
	local function S(k: string, u: number, v: number, w: number, h: number?, rot: number?): Shape
		return { k = k, u = cx + (u - 0.5) * su, v = cy + (v - 0.5) * sv, w = w * su, h = if h then h * sv else nil, rot = rot, c = c }
	end
	return {
		S("c", 0.5, 0.855, 0.16),
		S("tri", 0.5, 0.5, 0.4, 0.38),
		S("r", 0.5, 0.655, 0.2, 0.07),
		S("r", 0.34, 0.56, 0.065, 0.26, -14),
		S("r", 0.66, 0.56, 0.065, 0.26, 14),
		S("r", 0.453, 0.2, 0.07, 0.24),
		S("r", 0.547, 0.2, 0.07, 0.24),
	}
end

local PICTO: { [string]: (Color3, Color3) -> { Shape } } = {}
PICTO.man = function(fg, _bg)
	return figureMan(0.5, 0.5, 0.86, 0.86, fg)
end
PICTO.woman = function(fg, _bg)
	return figureWoman(0.5, 0.5, 0.86, 0.86, fg)
end
PICTO.accessible = function(fg, _bg)
	return {
		{ k = "c", u = 0.5, v = 0.855, w = 0.13, c = fg },
		{ k = "r", u = 0.46, v = 0.63, w = 0.1, h = 0.28, rot = 8, c = fg },
		{ k = "r", u = 0.57, v = 0.64, w = 0.2, h = 0.065, c = fg },
		{ k = "r", u = 0.58, v = 0.46, w = 0.3, h = 0.09, c = fg },
		{ k = "r", u = 0.71, v = 0.33, w = 0.085, h = 0.25, rot = 8, c = fg },
		{ k = "r", u = 0.77, v = 0.215, w = 0.13, h = 0.06, c = fg },
		{ k = "ring", u = 0.42, v = 0.34, w = 0.44, t = 0.065, c = fg, n = 18 },
	}
end
PICTO.elevator = function(fg, _bg)
	local out: { Shape } = {
		{ k = "r", u = 0.36, v = 0.5, w = 0.035, h = 0.72, c = fg },
		{ k = "r", u = 0.86, v = 0.5, w = 0.035, h = 0.72, c = fg },
		{ k = "r", u = 0.61, v = 0.845, w = 0.535, h = 0.035, c = fg },
		{ k = "r", u = 0.61, v = 0.155, w = 0.535, h = 0.035, c = fg },
		{ k = "tri", u = 0.18, v = 0.64, w = 0.2, h = 0.15, c = fg },
		{ k = "tri", u = 0.18, v = 0.36, w = 0.2, h = 0.15, rot = 180, c = fg },
	}
	for _, x in { 0.52, 0.7 } do
		table.insert(out, { k = "c", u = x, v = 0.68, w = 0.085, c = fg })
		table.insert(out, { k = "r", u = x, v = 0.5, w = 0.1, h = 0.2, c = fg })
		table.insert(out, { k = "r", u = x - 0.024, v = 0.3, w = 0.04, h = 0.2, c = fg })
		table.insert(out, { k = "r", u = x + 0.024, v = 0.3, w = 0.04, h = 0.2, c = fg })
	end
	return out
end
PICTO.stairs = function(fg, _bg)
	local out: { Shape } = {}
	for i = 0, 3 do
		local h = 0.1 + 0.11 * i
		table.insert(out, { k = "r", u = 0.2 + 0.17 * i, v = 0.1 + h / 2, w = 0.17 + 0.005, h = h, c = fg })
	end
	table.insert(out, { k = "c", u = 0.5, v = 0.9, w = 0.11, c = fg })
	table.insert(out, { k = "r", u = 0.48, v = 0.72, w = 0.09, h = 0.22, rot = -14, c = fg })
	table.insert(out, { k = "r", u = 0.41, v = 0.58, w = 0.07, h = 0.17, rot = 30, c = fg })
	table.insert(out, { k = "r", u = 0.52, v = 0.57, w = 0.07, h = 0.15, rot = -35, c = fg })
	table.insert(out, { k = "r", u = 0.58, v = 0.71, w = 0.055, h = 0.16, rot = 40, c = fg })
	return out
end
PICTO.exit = function(fg, bg)
	return {
		{ k = "r", u = 0.79, v = 0.5, w = 0.28, h = 0.76, c = fg, z = 0 },
		{ k = "r", u = 0.81, v = 0.48, w = 0.18, h = 0.66, c = bg, z = 1 },
		{ k = "c", u = 0.46, v = 0.83, w = 0.12, c = fg },
		{ k = "r", u = 0.4, v = 0.62, w = 0.1, h = 0.26, rot = -28, c = fg },
		{ k = "r", u = 0.52, v = 0.64, w = 0.055, h = 0.2, rot = -75, c = fg },
		{ k = "r", u = 0.29, v = 0.62, w = 0.055, h = 0.2, rot = 62, c = fg },
		{ k = "r", u = 0.44, v = 0.4, w = 0.07, h = 0.2, rot = -40, c = fg },
		{ k = "r", u = 0.53, v = 0.27, w = 0.065, h = 0.17, rot = 10, c = fg },
		{ k = "r", u = 0.27, v = 0.38, w = 0.07, h = 0.24, rot = 52, c = fg },
		{ k = "r", u = 0.16, v = 0.3, w = 0.11, h = 0.055, rot = 30, c = fg },
	}
end
PICTO.nosmoking = function(fg, _bg)
	local red = C.isoRed
	return {
		{ k = "r", u = 0.46, v = 0.47, w = 0.44, h = 0.1, c = fg, z = 0 },
		{ k = "r", u = 0.26, v = 0.47, w = 0.08, h = 0.1, c = rgb(214, 140, 60), z = 0 },
		{ k = "r", u = 0.71, v = 0.47, w = 0.04, h = 0.1, c = fg, z = 0 },
		{ k = "r", u = 0.71, v = 0.62, w = 0.025, h = 0.14, rot = 12, c = rgb(120, 120, 120), z = 0 },
		{ k = "ring", u = 0.5, v = 0.5, w = 0.9, t = 0.09, c = red, n = 20, z = 0 },
		{ k = "r", u = 0.5, v = 0.5, w = 0.8, h = 0.09, rot = -45, c = red, z = 1 },
	}
end
PICTO.info = function(fg, _bg)
	return {
		{ k = "c", u = 0.5, v = 0.77, w = 0.15, c = fg },
		{ k = "r", u = 0.5, v = 0.42, w = 0.13, h = 0.4, c = fg },
		{ k = "r", u = 0.5, v = 0.22, w = 0.26, h = 0.06, c = fg },
		{ k = "r", u = 0.46, v = 0.62, w = 0.2, h = 0.05, c = fg },
	}
end

PICTO.park = function(fg, _bg)
	return {
		{ k = "c", u = 0.5, v = 0.66, w = 0.56, c = fg },
		{ k = "c", u = 0.33, v = 0.55, w = 0.3, c = fg },
		{ k = "c", u = 0.67, v = 0.55, w = 0.3, c = fg },
		{ k = "r", u = 0.5, v = 0.24, w = 0.09, h = 0.34, c = fg },
		{ k = "r", u = 0.5, v = 0.08, w = 0.6, h = 0.04, c = fg },
	}
end
PICTO.bus = function(fg, bg)
	return {
		{ k = "r", u = 0.5, v = 0.52, w = 0.62, h = 0.66, c = fg, z = 0 },
		{ k = "r", u = 0.5, v = 0.62, w = 0.5, h = 0.26, c = bg, z = 1 },
		{ k = "r", u = 0.5, v = 0.8, w = 0.4, h = 0.05, c = bg, z = 1 },
		{ k = "c", u = 0.32, v = 0.33, w = 0.08, c = bg, z = 1 },
		{ k = "c", u = 0.68, v = 0.33, w = 0.08, c = bg, z = 1 },
		{ k = "r", u = 0.32, v = 0.14, w = 0.1, h = 0.1, c = fg, z = 0 },
		{ k = "r", u = 0.68, v = 0.14, w = 0.1, h = 0.1, c = fg, z = 0 },
	}
end

local PICTO_COL: { [string]: { Color3 } } = { -- 판색, 그림색
	man = { C.maleBlue, C.white },
	woman = { C.femaleRed, C.white },
	accessible = { C.isoBlue, C.white },
	elevator = { C.white, C.ink },
	stairs = { C.white, C.ink },
	exit = { C.isoGreen, C.white },
	nosmoking = { C.white, C.ink },
	info = { rgb(16, 52, 120), C.white },
	park = { C.roadBrown, C.white },
	bus = { C.isoBlue, C.white },
}

export type PictoOpts = { name: string?, plate: Color3?, fg: Color3?, caption: string?, mode: string?, glow: boolean?, depthM: number?, maxDistance: number? }

function Signage.pictogram(parent: Instance, cf: CFrame, sizeM: number, kind: string, opts: PictoOpts?): BasePart
	local o: PictoOpts = opts or {}
	local mdl = newModel(parent, o.name or ("Pictogram_" .. kind))
	local S = M(sizeM)
	local wide = kind == "restroom"
	local W = if wide then S * 2 else S
	local capH = if o.caption then S * 0.24 else 0
	local H = S + capH
	local cols = PICTO_COL[kind] or { C.white, C.ink }
	local plateC = o.plate or (if wide then C.white else cols[1])
	local fg = o.fg or cols[2]
	local pd = math.max(M(o.depthM or 0.012), 0.1)
	local plate = if o.glow
		then vbox(mdl, cf, 0, 0, -0.02, pd, W, H, dim(plateC, 0.75), MAT.Neon, "PictoPlate", glowOpt(plateC))
		else vbox(mdl, cf, 0, 0, -0.02, pd, W, H, plateC, MAT.SmoothPlastic, "PictoPlate")
	local list: { Shape }
	if wide then
		list = {}
		-- 가로 2배 판: u 배율은 절반(0.43), v 배율 0.86 → 정사각 픽토그램 두 개
		for _, s in figureMan(0.25, 0.5, 0.43, 0.86, C.maleBlue) do
			table.insert(list, s)
		end
		for _, s in figureWoman(0.75, 0.5, 0.43, 0.86, C.femaleRed) do
			table.insert(list, s)
		end
		table.insert(list, { k = "r", u = 0.5, v = 0.5, w = 0.008, h = 0.8, c = rgb(160, 160, 160) })
	else
		local f = PICTO[kind] or PICTO.info
		list = f(fg, plateC)
	end
	local F = at(cf, 0, capH / 2, 0)
	if o.mode == "gui" then
		local pps = math.clamp(160 / S, 10, 200)
		local face = vbox(mdl, cf, 0, capH / 2, pd - 0.02, pd + GAP, W, S, plateC, MAT.SmoothPlastic, "PictoFace")
		local g = newGui(face, FRONT, pps, if o.glow then 0 else 1, 1, o.maxDistance or 300)
		field(g, plateC)
		shapesGui(g, list, W, S, pps, fg)
	else
		local ex = if o.glow then glowOpt(fg) else nil
		Signage.shapes(mdl, F, W, S, list, pd, fg, if o.glow then MAT.Neon else MAT.SmoothPlastic, ex)
	end
	if o.caption then
		textAt(mdl, cf, 0, -H / 2 + capH / 2 + S * 0.02, pd + 0.05, W * 0.92, capH * 0.8, o.caption, { name = "PictoCaption", color = fg, font = "gothic", glow = o.glow, maxDistance = o.maxDistance or 300 })
	end
	return plate
end

------------------------------------------------------------------------------------------------------
-- 9) 도로안내표지 + 표지 구조물
------------------------------------------------------------------------------------------------------
export type RoadLine = { ko: string, en: string?, dist: string? }
export type RoadSpec = {
	wM: number?, -- 없으면 글자에 맞춰 자동
	hM: number?,
	color: string?, -- "green"(도시고속도로·고속도로) | "blue"(일반도로) | "brown"(관광지) | "white"
	arrow: string?, -- "up" "upright" "upleft" "left" "right" "down"
	arrowSide: string?, -- "left" | "right"(기본)
	lines: { RoadLine },
	tag: string?, -- 노선명 상자(예 "올림픽대로")
	tagColor: Color3?,
	dist: string?, -- 아래 거리("300m")
	exit: string?, -- 위 노란 탭(예 "출구 EXIT")
	koM: number?, -- 한글 글자 높이(m), 기본 0.45
	picto: string?, -- 왼쪽 흰 픽토그램(PICTO 종류 + "park" "bus")
}

local function roadColor(c: string?): (Color3, Color3)
	if c == "blue" then
		return C.roadBlue, C.white
	elseif c == "brown" then
		return C.roadBrown, C.white
	elseif c == "white" then
		return C.white, C.ink
	end
	return C.roadGreen, C.white
end

-- cf = 판 뒷면 중심(로컬 -Z = 운전자 쪽). 반환: 바탕 면 파트
function Signage.roadSignSize(spec: RoadSpec): (number, number)
	-- 글자 기준 자동 판 크기(m)
	local kh = spec.koM or 0.45
	local textW, textH = 0, 0
	local anyDist = false
	for i, ln in spec.lines do
		textW = math.max(textW, lineEm(ln.ko) * kh * 1.06, if ln.en then lineEm(ln.en) * kh * 0.55 * 0.95 else 0)
		textH += kh * (if ln.en then 1.67 else 1.12) + (if i > 1 then kh * 0.3 else 0)
		anyDist = anyDist or ln.dist ~= nil
	end
	if anyDist then
		textW += kh * 2.8
	end
	if spec.tag then
		textW = math.max(textW, lineEm(spec.tag) * kh * 0.6 + kh)
		textH += kh * 0.94
	end
	if spec.dist then
		textH += kh * 0.78
	end
	local side = 0
	if spec.arrow then
		side = math.max(side, math.min(textH, 2.2) * 0.95)
	end
	if spec.picto then
		side = math.max(side, kh * 2.2)
	end
	local w = textW + side + 0.34 + 0.6
	local h = math.max(textH, if spec.arrow then 1.3 else 0) + 0.34 + 0.4
	return spec.wM or math.ceil(w * 10) / 10, spec.hM or math.ceil(h * 10) / 10
end

function Signage.roadSign(parent: Instance, cf: CFrame, spec: RoadSpec, opts: { name: string?, maxDistance: number?, back: boolean? }?): BasePart
	local oo = opts or {}
	local mdl = newModel(parent, oo.name or "RoadSign")
	local wM, hM = Signage.roadSignSize(spec)
	local W, H = M(wM), M(hM)
	local fieldC, inkC = roadColor(spec.color)
	local maxd = oo.maxDistance or 1800
	local bm, bw = M(0.035), M(0.03)
	local t0 = 0.12
	vbox(mdl, cf, 0, 0, 0, t0, W, H, fieldC, MAT.SmoothPlastic, "SignPlate")
	vbox(mdl, cf, 0, 0, t0 - 0.03, t0 + GAP, W - 2 * bm, H - 2 * bm, inkC, MAT.SmoothPlastic, "SignBorder")
	local f0 = t0 + 2 * GAP
	local fieldP = vbox(mdl, cf, 0, 0, t0 + GAP - 0.03, f0, W - 2 * (bm + bw), H - 2 * (bm + bw), fieldC, MAT.SmoothPlastic, "SignField")
	-- 재귀반사 느낌: 바탕/글자 Gui LightInfluence 0.6
	local fg = newGui(fieldP, FRONT, math.min(ppsFor(W, H, H), 10), 0.6, 1, maxd)
	field(fg, fieldC, { 1.06, 0.97 }, 90)
	-- 뒷면 보강재(가로 Z 바 2)
	for _, v in { H * 0.28, -H * 0.28 } do
		vbox(mdl, cf, 0, v, -0.12, 0.02, W - M(0.2), M(0.06), C.alu, MAT.Metal, "Stiffener")
	end
	local LI = 0.6
	local pad = M(0.12)
	local iw, ih = W - 2 * (bm + bw) - 2 * pad, H - 2 * (bm + bw) - 2 * pad
	local uL, uR = -iw / 2, iw / 2
	local tL, tR = uL, uR
	-- 화살표
	if spec.arrow then
		local aw = math.min(iw * 0.3, ih * 0.8)
		local side = spec.arrowSide or "right"
		local au = if side == "left" then uL + aw / 2 else uR - aw / 2
		local ang = ARROW_ANG[spec.arrow] or 90
		local diag = ang % 90 ~= 0
		local len = math.min(aw, ih) * (if diag then 0.95 else 0.9)
		arrow(mdl, cf, au, 0, len, len * 0.2, len * 0.56, len * 0.38, ang, f0 - 0.02, f0 + GAP, inkC, MAT.SmoothPlastic)
		if side == "left" then
			tL = uL + aw + pad * 0.5
		else
			tR = uR - aw - pad * 0.5
		end
	end
	if spec.picto then
		local ps = math.min(ih, M((spec.koM or 0.45) * 2.0))
		local pl = PICTO[spec.picto] or PICTO.info
		local pu = tL + ps / 2
		Signage.shapes(mdl, at(cf, pu, 0, 0), ps, ps, pl(inkC, fieldC), f0, inkC)
		tL = tL + ps + pad * 0.5
	end
	local anyDist = false
	for _, ln in spec.lines do
		anyDist = anyDist or ln.dist ~= nil
	end
	local distCol = 0
	if anyDist then
		distCol = M((spec.koM or 0.45) * 2.6)
		tR -= distCol
	end
	local tw = tR - tL
	local tu = (tL + tR) / 2
	-- 세로 배분
	local kh = M(spec.koM or 0.45)
	local n = #spec.lines
	local need = 0
	for _, ln in spec.lines do
		need += kh * (if ln.en then 1.67 else 1.12)
	end
	need += kh * 0.3 * math.max(0, n - 1)
	local tagH = if spec.tag then kh * 0.72 else 0
	local distH = if spec.dist then kh * 0.62 else 0
	need += tagH * 1.3 + distH * 1.25
	if need > ih then
		kh *= ih / need
		tagH *= ih / need
		distH *= ih / need
		need = ih
	end
	local td = f0 + 0.05
	local v = need / 2
	if spec.tag then
		local tagC = spec.tagColor or (if spec.color == "blue" then C.roadGreen else C.roadBlue)
		local tgw = textEm(spec.tag) * tagH * 0.82 + tagH * 0.9
		vbox(mdl, cf, tu, v - tagH / 2, f0 - 0.02, f0 + GAP, tgw + M(0.04), tagH + M(0.04), inkC, MAT.SmoothPlastic, "RouteTagRim")
		vbox(mdl, cf, tu, v - tagH / 2, f0, f0 + 2 * GAP, tgw, tagH, tagC, MAT.SmoothPlastic, "RouteTag")
		textAt(mdl, cf, tu, v - tagH / 2, f0 + 2 * GAP + 0.05, tgw - tagH * 0.3, tagH * 0.84, spec.tag, { name = "RouteTagText", color = C.white, font = "gothic", light = LI, maxDistance = maxd })
		v -= tagH * 1.3
	end
	for i, ln in spec.lines do
		local kw = math.min(tw, textEm(ln.ko) * kh * 1.06 + kh * 0.2)
		local v0 = v
		textAt(mdl, cf, tu, v - kh * 0.56, td, kw, kh * 1.22, ln.ko, { name = "DestKo", color = inkC, font = "gothic", weight = "Bold", light = LI, maxDistance = maxd })
		v -= kh * 1.12
		if ln.en then
			local eh = kh * 0.55
			local ew = math.min(tw, textEm(ln.en) * eh * 0.92 + eh * 0.4)
			textAt(mdl, cf, tu, v - eh * 0.6, td, ew, eh * 1.25, ln.en, { name = "DestEn", color = inkC, font = "road", light = LI, maxDistance = maxd })
			v -= kh * 0.55
		end
		if ln.dist then
			local dh = kh * 0.9
			textAt(mdl, cf, tR + distCol / 2, (v0 + v) / 2, td, distCol, dh * 1.2, ln.dist, { name = "LineDist", color = inkC, font = "road", light = LI, maxDistance = maxd })
		end
		if i < n then
			v -= kh * 0.3
		end
	end
	if spec.dist then
		local dw = textEm(spec.dist) * distH + distH * 0.4
		textAt(mdl, cf, tR - dw / 2, -ih / 2 + distH * 0.62, td, dw, distH * 1.24, spec.dist, { name = "Dist", color = inkC, font = "road", light = LI, maxDistance = maxd })
	end
	if spec.exit then
		local eh = M(0.5)
		local ew = math.min(W * 0.5, textEm(spec.exit) * eh * 0.7 + eh)
		local eu = W / 2 - ew / 2
		vbox(mdl, cf, eu, H / 2 + eh / 2 + M(0.02), 0, t0, ew, eh, C.roadYellow, MAT.SmoothPlastic, "ExitTab")
		textAt(mdl, cf, eu, H / 2 + eh / 2 + M(0.02), t0 + 0.05, ew * 0.86, eh * 0.78, spec.exit, { name = "ExitText", color = C.ink, font = "gothic", light = LI, maxDistance = maxd })
	end
	return fieldP
end

export type GantrySign = { spec: RoadSpec, u: number } -- u = 경간 중심에서 운전자 기준 오른쪽(m)
export type GantryOpts = {
	name: string?,
	clearM: number?, -- 노면 → 표지 하단(기본 5.2 m, ≥ 4.7)
	cantilever: string?, -- nil = 문형(양 기둥) | "left" | "right" = 그쪽 기둥 하나(내민식)
	baseL: number?, -- 왼쪽 기둥 바닥 높이(cf 기준 stud, 예: 중앙분리대 윗면)
	baseR: number?,
	footL: number?, -- 기초 폭(m). 중앙분리대 위면 0.7
	footR: number?,
	color: Color3?,
	trussM: number?, -- 트러스 높이(m, 기본 1.1)
}

-- cf = 경간 중심의 노면 위 점, 로컬 -Z = 표지 앞(마주 오는 차 쪽), 로컬 X = 경간 방향. 반환: 첫 표지 바탕 파트
function Signage.gantry(parent: Instance, cf: CFrame, spanM: number, signs: { GantrySign }, opts: GantryOpts?): BasePart
	local o: GantryOpts = opts or {}
	local mdl = newModel(parent, o.name or "SignGantry")
	local S = M(spanM)
	local clear = M(o.clearM or 5.2)
	local col = o.color or C.galv
	local maxH = 0
	for _, s in signs do
		local _, hM = Signage.roadSignSize(s.spec)
		maxH = math.max(maxH, M(hM) + (if s.spec.exit then M(0.55) else 0))
	end
	local th, tdp = M(o.trussM or 1.1), M(0.8)
	local vC = clear + math.max(maxH, th) / 2
	local postTop = vC + th / 2 + M(0.3)
	local postD = M(0.45)
	local sides: { number } = {}
	if o.cantilever == "left" then
		sides = { -1 }
	elseif o.cantilever == "right" then
		sides = { 1 }
	else
		sides = { -1, 1 }
	end
	for _, sd in sides do
		local u = sd * S / 2
		local base = (if sd < 0 then o.baseL else o.baseR) or 0
		local fwM = (if sd < 0 then o.footL else o.footR) or 1.1
		local fw = M(fwM)
		-- 콘크리트 기초(위 0.25 m 노출, 아래로 1.5 m) + 베이스 플레이트 + 앵커 너트 + 원형 강관 기둥 + 캡
		vbox(mdl, cf, u, base + M(0.25) - M(1.75) / 2, -fw / 2, fw / 2, fw, M(1.75), C.concrete, MAT.Concrete, "GantryFooting", { collide = true, query = true })
		local footTop = base + M(0.25)
		local plateTop = footTop + 0.12
		vbox(mdl, cf, u, footTop + 0.04, -fw * 0.36, fw * 0.36, fw * 0.72, 0.16, col, MAT.Metal, "BasePlate")
		for _, a in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
			vdisc(mdl, at(cf, u + a[1] * fw * 0.27, plateTop + 0.04, a[2] * fw * 0.27) * CFrame.Angles(math.rad(90), 0, 0), 0, 0, -0.06, 0.06, M(0.05), rgb(110, 112, 116), MAT.Metal, "AnchorNut")
		end
		local p0 = at(cf, u, plateTop - 0.05, 0).Position
		local p1 = at(cf, u, postTop, 0).Position
		rod(mdl, p0, p1, postD, col, MAT.Metal, "GantryPost", { collide = true, query = true, reflectance = 0.05 })
		vdisc(mdl, at(cf, u, postTop + 0.04, 0) * CFrame.Angles(math.rad(90), 0, 0), 0, 0, -0.06, 0.1, postD + M(0.04), col, MAT.Metal, "PostCap")
	end
	-- 상자형 트러스: 주현(4) + 앞/뒤면 사재 + 윗/아랫면 수직재
	local uA, uB = -S / 2, S / 2
	if o.cantilever == "left" then
		uB = S / 2 + M(0.3)
	elseif o.cantilever == "right" then
		uA = -S / 2 - M(0.3)
	end
	local chordD, webD = M(0.14), M(0.07)
	local function P(u: number, v: number, d: number): Vector3
		return at(cf, u, v, d).Position
	end
	for _, vv in { vC + th / 2, vC - th / 2 } do
		for _, dd in { tdp / 2, -tdp / 2 } do
			rod(mdl, P(uA, vv, dd), P(uB, vv, dd), chordD, col, MAT.Metal, "Chord", { reflectance = 0.05 })
		end
	end
	local panels = math.max(2, math.floor((uB - uA) / th + 0.5))
	local du = (uB - uA) / panels
	for i = 0, panels - 1 do
		local ua, ub = uA + i * du, uA + (i + 1) * du
		local top = i % 2 == 0
		for _, dd in { tdp / 2, -tdp / 2 } do
			rod(mdl, P(ua, vC + (if top then th / 2 else -th / 2), dd), P(ub, vC + (if top then -th / 2 else th / 2), dd), webD, col, MAT.Metal, "Lacing")
		end
		rod(mdl, P(ub, vC + th / 2, tdp / 2), P(ub, vC + th / 2, -tdp / 2), webD, col, MAT.Metal, "Strut")
		rod(mdl, P(ub, vC - th / 2, tdp / 2), P(ub, vC - th / 2, -tdp / 2), webD, col, MAT.Metal, "Strut")
	end
	-- 내민식: 기둥에서 트러스 아래로 사선 버팀
	if o.cantilever then
		local sd = if o.cantilever == "left" then -1 else 1
		local u0 = sd * S / 2
		rod(mdl, P(u0, vC - th / 2 - M(1.6), 0), P(u0 - sd * M(2.2), vC - th / 2, 0), M(0.12), col, MAT.Metal, "Brace")
	end
	-- 표지: 트러스 앞면에 수직 채널 2개로 매달기
	local first: BasePart? = nil
	for _, s in signs do
		local u = M(s.u)
		local wM, hM = Signage.roadSignSize(s.spec)
		local W, Hs = M(wM), M(hM)
		local signBack = tdp / 2 + M(0.18)
		local vS = clear + Hs / 2 + (maxH - Hs - (if s.spec.exit then M(0.55) else 0)) / 2
		local fp = Signage.roadSign(mdl, at(cf, u, vS, signBack), s.spec)
		first = first or fp
		for _, k in { -0.3, 0.3 } do
			local cu = u + k * W
			local hh = math.max(th + M(0.3), Hs * 0.86)
			vbox(mdl, cf, cu, (vC + vS) / 2, tdp / 2 - M(0.08), signBack - 0.1, M(0.1), hh + math.abs(vC - vS), col, MAT.Metal, "MountChannel")
		end
	end
	return first :: BasePart
end

------------------------------------------------------------------------------------------------------
-- 10) 도로명판 ("올림픽로 Olympic-ro 1→699"). range = "1→699" | "1←" 형식의 앞/뒤 번호, 기둥/양면 옵션
------------------------------------------------------------------------------------------------------
export type StreetNameOpts = { name: string?, wM: number?, hM: number?, pole: number?, groundY: number?, back: boolean?, maxDistance: number? }

function Signage.streetName(parent: Instance, cf: CFrame, name: string, roman: string, range: string?, opts: StreetNameOpts?): BasePart
	local o: StreetNameOpts = opts or {}
	local mdl = newModel(parent, o.name or "StreetName")
	local H = M(o.hM or 0.25)
	local nameH = H * 0.46
	local W = if o.wM then M(o.wM) else math.max(M(0.9), textEm(name) * nameH * 1.1 + (if range then H * 1.7 else H * 0.6))
	local navy = C.nameNavy
	local maxd = o.maxDistance or 260
	local T = 0.14
	local plate = vbox(mdl, cf, 0, 0, 0, T, W, H, navy, MAT.SmoothPlastic, "NamePlate")
	local g = newGui(plate, FRONT, math.min(ppsFor(W, H, H), 40), 1, 1, maxd)
	field(g, navy, { 1.05, 0.95 }, 90)
	local from, to = "", ""
	if range then
		local a, b = string.match(range, "^%s*([^%s→]*)%s*→%s*(.-)%s*$")
		from, to = a or range, b or ""
	end
	local function face(F: CFrame, front: number, rev: boolean)
		local d = front + 0.05
		local rw = if range then H * 1.5 else 0
		local nu = -rw / 2
		local nw = W - rw - H * 0.3
		textAt(mdl, F, nu, H * 0.13, d, math.min(nw, textEm(name) * nameH * 1.1 + nameH * 0.2), nameH * 1.22, name, { name = "RoadName", color = C.white, font = "gothic", weight = "Bold", maxDistance = maxd })
		textAt(mdl, F, nu, -H * 0.27, d, math.min(nw, textEm(roman) * H * 0.22 * 1.05 + H * 0.1), H * 0.27, roman, { name = "RoadRoman", color = C.white, font = "medium", maxDistance = maxd })
		if range then
			local ru = W / 2 - rw / 2 - H * 0.1
			-- 구분선 + 번호 + 화살표(파트)
			vbox(mdl, F, ru - rw / 2 - H * 0.05, 0, front - 0.02, front + GAP, 0.06, H * 0.7, C.white, MAT.SmoothPlastic, "RangeRule")
			local a, b = if rev then to else from, if rev then from else to
			local nh = H * 0.3
			textAt(mdl, F, ru - rw * 0.3, H * 0.14, d, rw * 0.38, nh, a, { name = "RangeFrom", color = C.white, font = "gothic", maxDistance = maxd })
			textAt(mdl, F, ru + rw * 0.22, H * 0.14, d, rw * 0.52, nh, b, { name = "RangeTo", color = C.white, font = "gothic", maxDistance = maxd })
			arrow(mdl, F, ru, -H * 0.2, rw * 0.7, H * 0.05, H * 0.17, H * 0.14, 0, front - 0.02, front + GAP, C.white, MAT.SmoothPlastic)
		end
	end
	face(cf, T, false)
	if o.back ~= false then
		local Fb = cf * CFrame.Angles(0, math.pi, 0)
		face(Fb, 0, true)
		local gb = newGui(plate, Enum.NormalId.Back, math.min(ppsFor(W, H, H), 40), 1, 1, maxd)
		field(gb, navy, { 1.05, 0.95 }, 90)
	end
	if o.pole then
		local up = cf.UpVector
		local topP = at(cf, -W / 2 - M(0.06), H / 2 + M(0.05), T / 2).Position
		local botP = topP - up * M(o.pole)
		if o.groundY then
			botP = Vector3.new(botP.X, o.groundY - 0.3, botP.Z)
		end
		rod(mdl, botP, topP, M(0.076), rgb(120, 124, 130), MAT.Metal, "SignPole", { collide = true, query = true })
		vdisc(mdl, CFrame.new(topP + up * 0.06) * (cf - cf.Position) * CFrame.Angles(math.rad(90), 0, 0), 0, 0, -0.05, 0.05, M(0.09), rgb(120, 124, 130), MAT.Metal, "PoleCap")
		for _, v in { H * 0.3, -H * 0.3 } do
			vbox(mdl, cf, -W / 2 - M(0.03), v, T / 2 - M(0.05), T / 2 + M(0.05), M(0.08), M(0.04), rgb(100, 104, 110), MAT.Metal, "Clamp")
		end
	end
	return plate
end

------------------------------------------------------------------------------------------------------
-- 11) LED 전광판
------------------------------------------------------------------------------------------------------
export type DigitalOpts = { name: string?, design: string?, bezelM: number?, depthM: number?, legs: number?, groundY: number?, maxDistance: number?, brightness: number? }

local LED_DESIGNS: { [string]: { any } } = {
	-- { 바탕, 그라데이션 키, 큰 글자, 작은 글자, 글자색, 강조 도형색 }
	night = { rgb(70, 30, 120), { 0.55, 1.1 }, "서울의 밤, 한강", "SEOUL NIGHT RIVER  ·  11.14 – 11.15", rgb(255, 255, 255), rgb(255, 120, 200) },
	news = { rgb(10, 40, 90), { 1, 0.7 }, "오늘 밤 미세먼지 좋음", "기온 9°C  ·  습도 52%  ·  일몰 17:21", rgb(255, 255, 255), rgb(60, 200, 255) },
	sale = { rgb(220, 30, 60), { 1.1, 0.8 }, "BLACK WEEK 최대 70%", "11.01 – 11.30  ·  잠실 쇼핑타운", rgb(255, 255, 255), rgb(255, 214, 60) },
	safety = { rgb(10, 90, 60), { 1, 0.75 }, "안전운전 · 졸음쉼터 2km", "SLOW DOWN  ·  잠실대교 정체 없음", rgb(255, 236, 120), rgb(255, 255, 255) },
}

function Signage.digital(parent: Instance, cf: CFrame, wM: number, hM: number, opts: DigitalOpts?): BasePart
	local o: DigitalOpts = opts or {}
	local mdl = newModel(parent, o.name or "LedScreen")
	local W, H = M(wM), M(hM)
	local bz = math.max(M(o.bezelM or 0.1), 0.15)
	local D = math.max(M(o.depthM or 0.3), 0.6)
	local dsn = o.design or "night"
	local d = LED_DESIGNS[dsn] or LED_DESIGNS.night
	local bg, grad, head, sub, tc, ac = d[1] :: Color3, d[2] :: { number }, d[3] :: string, d[4] :: string, d[5] :: Color3, d[6] :: Color3
	local maxd = o.maxDistance or 3000
	vbox(mdl, cf, 0, 0, -0.03, D, W, H, rgb(18, 18, 20), MAT.Metal, "LedCabinet")
	local screen = vbox(mdl, cf, 0, 0, D - 0.04, D + GAP, W - 2 * bz, H - 2 * bz, dim(bg, 0.7), MAT.Neon, "LedFace", glowOpt(rgb(14, 14, 16)))
	CollectionService:AddTag(screen, Signage.LED_TAG)
	screen:SetAttribute("Design", dsn)
	local iw, ih = W - 2 * bz, H - 2 * bz
	local pps = math.min(ppsFor(iw, ih, ih), 16)
	local g = newGui(screen, FRONT, pps, 0, o.brightness or 2, maxd)
	field(g, bg, grad, 20)
	-- 실제 Roblox 장식: 대각 광택 띠 + 원형 강조 + LED 픽셀 결(가로 줄)
	deco(g, 0.82, 0.62, 0.42, 0.42 * iw / ih, ac, 0.5, 0.35, 2)
	deco(g, 0.18, 0.2, 0.8, 0.05, ac, 0, 0.5, 2, -12)
	for i = 1, 24 do
		deco(g, 0.5, i / 25, 1, 0.006, Color3.new(0, 0, 0), 0, 0.82, 6)
	end
	local td = D + GAP + 0.05
	local hh = ih * 0.36
	textAt(mdl, cf, 0, ih * 0.12, td, iw * 0.9, hh, head, { name = "LedHead", color = tc, font = "black", glow = true, brightness = (o.brightness or 2) * 1.2, maxDistance = maxd })
	textAt(mdl, cf, 0, -ih * 0.26, td, iw * 0.84, ih * 0.15, sub, { name = "LedSub", color = tc, font = "medium", glow = true, brightness = o.brightness or 2, maxDistance = maxd })
	-- 다리(지주형): legs = 높이(m)
	if o.legs then
		local up = cf.UpVector
		for _, su in { -0.3, 0.3 } do
			local topP = at(cf, su * W, -H / 2 + M(0.3), D / 2).Position
			local botP = topP - up * (M(o.legs) + M(0.3))
			if o.groundY then
				botP = Vector3.new(botP.X, o.groundY - 0.3, botP.Z)
			end
			rod(mdl, botP, topP, M(0.35), rgb(60, 62, 68), MAT.Metal, "LedLeg", { collide = true, query = true })
		end
	end
	return screen
end

------------------------------------------------------------------------------------------------------
-- 12) 일반 판 간판(실명판·안내판): 단색 판 + 글자. 보조용
------------------------------------------------------------------------------------------------------
function Signage.plate(parent: Instance, cf: CFrame, wM: number, hM: number, text: string, opts: { name: string?, color: Color3?, textColor: Color3?, font: string?, glow: boolean?, depthM: number?, maxDistance: number? }?): BasePart
	local o = opts or {}
	local mdl = newModel(parent, o.name or "Plate")
	local W, H = M(wM), M(hM)
	local T = math.max(M(o.depthM or 0.02), 0.1)
	local p = vbox(mdl, cf, 0, 0, -0.02, T, W, H, o.color or C.ink, MAT.SmoothPlastic, "Plate")
	textAt(mdl, cf, 0, 0, T + 0.05, W * 0.9, H * 0.8, text, { name = "PlateText", color = o.textColor or C.white, font = o.font or "gothic", glow = o.glow, maxDistance = o.maxDistance or 200 })
	return p
end

return Signage
