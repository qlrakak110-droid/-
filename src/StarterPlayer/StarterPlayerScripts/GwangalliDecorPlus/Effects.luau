--!strict
-- GwangalliDecorPlus/Effects: what everyone inside a decorated home sees, drawn locally —
--   · 벽지 / 바닥 무늬: SurfaceGuis in PlayerGui (Adornee = the room's wall / floor parts) from DPFinish
--   · 조명 프리셋: ColorCorrection + (파티) cycling light colours from DPLight
--   · TV 8 채널 (뉴스 · 날씨 · 야구 · 드라마 · 뮤직 · 게임 · 홈쇼핑 · 광안대교 라이브캠) on "Screen" parts
--   · 수족관 물고기 (+ 먹이 주기), 벽시계 실제 시간, 스피커 음악 (built-in tone sequencer or
--     Config.SPEAKER_TRACKS), 벽난로 불빛 일렁임, 미러볼 회전
-- Only within Config.EFFECT_RANGE of the camera; everything is removed when the player leaves.
--   Effects.start(getHome) — getHome() -> (model?, U?) for the home the local player is inside

local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = require(game:GetService("ReplicatedStorage"):WaitForChild("GwangalliDecorShared"))
local Config, Catalog, Finish, Palette = Shared.Config, Shared.Catalog, Shared.Finish, Shared.Palette

local Effects = {}

local player = Players.LocalPlayer
local cur: any = nil -- { model, U, surfaces = {}, items = {}, cc, lightOrig, conns }

local function color3(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function guiFolder(): Folder
	local pg = player:WaitForChild("PlayerGui")
	local f = pg:FindFirstChild("GwDecorPlusSurfaces")
	if not f then
		f = Instance.new("Folder")
		f.Name = "GwDecorPlusSurfaces"
		f.Parent = pg
	end
	return f :: Folder
end

local function localFolder(): Folder
	local f = workspace:FindFirstChild(Config.LOCAL_FOLDER)
	if not f then
		f = Instance.new("Folder")
		f.Name = Config.LOCAL_FOLDER
		f.Parent = workspace
	end
	local fx = f:FindFirstChild("Effects")
	if not fx then
		fx = Instance.new("Folder")
		fx.Name = "Effects"
		fx.Parent = f
	end
	return fx :: Folder
end

local function frame(parent: Instance, color: Color3, x: number, y: number, w: number, h: number, t: number?, rot: number?): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.BackgroundTransparency = t or 0
	f.Position = UDim2.new(x, 0, y, 0)
	f.Size = UDim2.new(w, 0, h, 0)
	f.Rotation = rot or 0
	f.Parent = parent
	return f
end

-------------------------------------------------------------------------------------------------
-- Finish patterns
-------------------------------------------------------------------------------------------------
-- draws pattern p (colour b over the part's own colour a) on a surface of su x sv studs
local function drawPattern(root: Frame, p: string, a: Color3, b: Color3, su: number, sv: number)
	local cap = 360
	if p == "stripe" or p == "pinstripe" then
		local period = if p == "stripe" then 1.6 else 0.9
		local n = math.min(cap, math.ceil(su / period))
		local w = if p == "stripe" then 0.5 else 0.07
		for i = 0, n - 1 do
			frame(root, b, i / n, 0, w / n, 1)
		end
	elseif p == "check" then
		local period = 1.4
		local nu, nv = math.min(80, math.ceil(su / period)), math.min(80, math.ceil(sv / period))
		for i = 0, nu - 1 do
			frame(root, b, i / nu, 0, 0.45 / nu, 1, 0.55)
		end
		for j = 0, nv - 1 do
			frame(root, b, 0, j / nv, 1, 0.45 / nv, 0.55)
		end
	elseif p == "dot" then
		local period = 1.1
		local nu, nv = math.ceil(su / period), math.ceil(sv / period)
		while nu * nv > cap do
			period *= 1.25
			nu, nv = math.ceil(su / period), math.ceil(sv / period)
		end
		local d = 0.32 / period
		for i = 0, nu - 1 do
			for j = 0, nv - 1 do
				local f = frame(root, b, (i + 0.5 + (j % 2) * 0.5) / nu - d / nu / 2, (j + 0.5) / nv - d / nv / 2, d / nu, d / nv)
				local c = Instance.new("UICorner")
				c.CornerRadius = UDim.new(0.5, 0)
				c.Parent = f
			end
		end
	elseif p == "wainscot" then
		local h = math.clamp(3.0 / sv, 0.2, 0.5)
		frame(root, b, 0, 1 - h, 1, h)
		frame(root, b:Lerp(Color3.new(1, 1, 1), 0.25), 0, 1 - h - 0.012, 1, 0.012)
		local n = math.max(1, math.floor(su / 2.6))
		for i = 0, n - 1 do
			local inner = frame(root, b:Lerp(Color3.new(0, 0, 0), 0.12), (i + 0.12) / n, 1 - h + h * 0.18, 0.76 / n, h * 0.62)
			local s = Instance.new("UIStroke")
			s.Color = b:Lerp(Color3.new(1, 1, 1), 0.2)
			s.Thickness = 2
			s.Parent = inner
		end
	elseif p == "subway" or p == "herringbone" then
		-- running-bond / zigzag joints
		local bw, bh = (if p == "subway" then 1.0 else 1.6), (if p == "subway" then 0.5 else 0.4)
		local rows = math.min(120, math.ceil(sv / bh))
		local cols = math.ceil(su / bw)
		for j = 0, rows - 1 do
			frame(root, b, 0, j / rows, 1, 0.018 / bh / rows * bh, 0)
			if rows * cols < cap * 2 then
				for i = 0, cols do
					local off = if j % 2 == 0 then 0 else 0.5
					if p == "subway" then
						frame(root, b, (i + off) / cols, j / rows, 0.03 / su, 1 / rows)
					else
						frame(root, b, (i + off) / cols, j / rows, 0.035 / su, 1 / rows, 0, if j % 2 == 0 then 40 else -40)
					end
				end
			end
		end
	elseif p == "checker" then
		local period = 1.6
		local nu, nv = math.ceil(su / period), math.ceil(sv / period)
		while nu * nv / 2 > cap do
			period *= 1.25
			nu, nv = math.ceil(su / period), math.ceil(sv / period)
		end
		for i = 0, nu - 1 do
			for j = 0, nv - 1 do
				if (i + j) % 2 == 1 then
					frame(root, b, i / nu, j / nv, 1 / nu, 1 / nv)
				end
			end
		end
	elseif p == "terrazzo" then
		local n = math.min(cap, math.floor(su * sv * 1.2))
		local rnd = Random.new(math.floor(su * 100 + sv))
		local cols = { b, b:Lerp(Color3.fromRGB(60, 90, 80), 0.5), Color3.fromRGB(230, 200, 150), Color3.fromRGB(120, 120, 124) }
		for i = 1, n do
			local s = 0.08 + rnd:NextNumber() * 0.14
			frame(root, cols[(i % #cols) + 1], rnd:NextNumber(), rnd:NextNumber(), s / su, s / sv, 0, rnd:NextNumber() * 90)
		end
	elseif p == "gradient" or p == "mural" then
		local g = frame(root, Color3.new(1, 1, 1), 0, 0, 1, 1)
		local grad = Instance.new("UIGradient")
		grad.Rotation = 90
		grad.Color = if p == "mural" then ColorSequence.new({ ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(0.62, a:Lerp(Color3.fromRGB(120, 60, 140), 0.5)), ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 14, 30)) }) else ColorSequence.new(a, b)
		grad.Parent = g
		if p == "mural" then
			local deckY = 0.6
			frame(root, b, 0, deckY, 1, 0.012)
			for _, tx in { 0.3, 0.7 } do
				frame(root, Color3.fromRGB(220, 230, 255), tx - 0.004, deckY - 0.3, 0.008, 0.3)
				for k = 1, 5 do
					local dx = k * 0.03
					frame(root, Color3.fromRGB(255, 79, 163), tx - dx * 0.5, deckY - 0.15, 0.002, 0.18, 0.2, 35 + k * 6)
					frame(root, Color3.fromRGB(255, 79, 163), tx + dx * 0.5, deckY - 0.15, 0.002, 0.18, 0.2, -35 - k * 6)
				end
			end
			for k = 0, 30 do
				frame(root, if k % 2 == 0 then b else Color3.fromRGB(255, 79, 163), k / 30, deckY + 0.03 + (k % 4) * 0.025, 0.012, 0.004, 0.3)
			end
			local moon = frame(root, Color3.fromRGB(255, 246, 220), 0.82, 0.12, 0.05 * sv / math.max(su, 1), 0.05)
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0.5, 0)
			c.Parent = moon
		end
	end
end

local FACE_AXIS = {
	{ Enum.NormalId.Right, Vector3.new(1, 0, 0) },
	{ Enum.NormalId.Left, Vector3.new(-1, 0, 0) },
	{ Enum.NormalId.Back, Vector3.new(0, 0, 1) },
	{ Enum.NormalId.Front, Vector3.new(0, 0, -1) },
}

local function surfaceSize(p: BasePart, face: Enum.NormalId): (number, number)
	local s = p.Size
	if face == Enum.NormalId.Top or face == Enum.NormalId.Bottom then
		return s.X, s.Z
	elseif face == Enum.NormalId.Left or face == Enum.NormalId.Right then
		return s.Z, s.Y
	end
	return s.X, s.Y
end

local function clearSurfaces()
	if cur then
		for _, g in cur.surfaces do
			g:Destroy()
		end
		cur.surfaces = {}
	end
end

local function applyFinish()
	if not cur then
		return
	end
	clearSurfaces()
	local raw = cur.model:GetAttribute("DPFinish")
	if type(raw) ~= "string" or raw == "" then
		return
	end
	local ok, fin = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or type(fin) ~= "table" or type(fin.rooms) ~= "table" then
		return
	end
	local U = cur.U
	for room, e in fin.rooms do
		local th = U.themes[room]
		local r = U.roomById[room]
		for key, kind in { w = "wall", f = "floor" } do
			local entry = e[key]
			local def = entry and Finish.def(kind, entry.p)
			if th and def and def.pattern ~= "solid" then
				local a, b = Finish.colors(kind, entry)
				local ca, cb = color3(a :: any), color3((b or Palette.shade(a :: any, 0.75)) :: any)
				for _, part in th[kind] do
					local face = Enum.NormalId.Top
					if kind == "wall" then
						-- the face looking into the room
						local centre = if r then U.F:PointToWorldSpace(r.centre + Vector3.new(0, 2, 0)) else part.Position
						local rel = part.CFrame:PointToObjectSpace(centre)
						local best, bs = Enum.NormalId.Front, -math.huge
						for _, fa in FACE_AXIS do
							local ax = fa[2]
							local half = math.abs(ax.X) * part.Size.X / 2 + math.abs(ax.Z) * part.Size.Z / 2
							local sc = rel:Dot(ax) - half
							if sc > bs then
								best, bs = fa[1], sc
							end
						end
						face = best
					end
					local su, sv = surfaceSize(part, face)
					if su * sv > 0.5 then
						local g = Instance.new("SurfaceGui")
						g.Name = "DPFinish_" .. room .. "_" .. kind
						g.Adornee = part
						g.Face = face
						g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
						g.PixelsPerStud = if su * sv > 400 then 10 else 16
						g.LightInfluence = 1
						g.ZOffset = 0.1
						g.ResetOnSpawn = false
						g.ClipsDescendants = true
						local root = Instance.new("Frame")
						root.BackgroundTransparency = 1
						root.Size = UDim2.new(1, 0, 1, 0)
						root.ClipsDescendants = true
						root.Parent = g
						drawPattern(root, def.pattern, ca, cb, su, sv)
						g.Parent = guiFolder()
						table.insert(cur.surfaces, g)
					end
				end
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Lighting presets
-------------------------------------------------------------------------------------------------
local function lightsOfHome(): { Light }
	local out = {}
	for _, th in cur.U.themes do
		for _, l in th.lights do
			table.insert(out, l)
		end
	end
	return out
end

local function stopParty()
	if cur and cur.partyOrig then
		for l, c in cur.partyOrig do
			if l.Parent then
				l.Color = c
			end
		end
		cur.partyOrig = nil
	end
end

local function applyLight()
	if not cur then
		return
	end
	stopParty()
	local id = cur.model:GetAttribute("DPLight")
	local def = type(id) == "string" and Finish.LIGHTS[id] or nil
	local cc = Lighting:FindFirstChild("GwDecorPlusCC")
	if not def or not def.tint then
		if cc then
			cc:Destroy()
		end
		cur.party = false
		return
	end
	if not cc then
		cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "GwDecorPlusCC"
		cc.Parent = Lighting
	end
	local e = cc :: ColorCorrectionEffect
	e.TintColor = color3(def.tint)
	e.Saturation = def.sat or 0
	e.Contrast = def.con or 0
	e.Brightness = def.bright or 0
	cur.party = def.party == true
	if cur.party then
		cur.partyOrig = {}
		for _, l in lightsOfHome() do
			cur.partyOrig[l] = l.Color
		end
	end
end

-------------------------------------------------------------------------------------------------
-- TV channels
-------------------------------------------------------------------------------------------------
local CHANNELS = { "광안 뉴스", "부산 날씨", "프로야구 중계", "주말 드라마", "뮤직 TV", "게임 채널", "홈쇼핑", "광안대교 라이브캠" }
local TICKER = "속보 · 오늘 밤 8시 광안리 드론쇼 · 부산 내일 맑음 25° · 해운대 해수욕장 개장 · 광안대교 야간 경관조명 연장 운영 · "

local function label(parent: Instance, text: string, x: number, y: number, w: number, h: number, size: number, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextScaled = true
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.Position = UDim2.new(x, 0, y, 0)
	l.Size = UDim2.new(w, 0, h, 0)
	l.TextXAlignment = Enum.TextXAlignment.Left
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = size
	c.Parent = l
	l.Parent = parent
	return l
end

-- returns update(t)
local function buildChannel(root: Frame, ch: number): (number) -> ()
	for _, c in root:GetChildren() do
		c:Destroy()
	end
	local upd: (number) -> () = function(_t) end
	if ch == 1 then
		frame(root, Color3.fromRGB(14, 30, 70), 0, 0, 1, 1)
		frame(root, Color3.fromRGB(30, 60, 120), 0.55, 0.15, 0.4, 0.5)
		label(root, "🌉", 0.6, 0.2, 0.3, 0.4, 80)
		local desk = frame(root, Color3.fromRGB(200, 205, 215), 0.08, 0.58, 0.4, 0.12)
		local _ = desk
		local head = frame(root, Color3.fromRGB(230, 190, 160), 0.2, 0.28, 0.12, 0.2)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = head
		frame(root, Color3.fromRGB(40, 50, 80), 0.16, 0.45, 0.2, 0.15)
		frame(root, Color3.fromRGB(214, 40, 50), 0, 0.74, 1, 0.1)
		label(root, "  광안리 드론쇼 오늘 밤 8시", 0, 0.74, 1, 0.1, 40)
		local tk = label(root, TICKER .. TICKER, 0, 0.86, 3, 0.1, 30, Color3.fromRGB(255, 230, 120))
		upd = function(t)
			tk.Position = UDim2.new(-((t * 0.08) % 1.5), 0, 0.86, 0)
		end
	elseif ch == 2 then
		frame(root, Color3.fromRGB(90, 160, 220), 0, 0, 1, 1)
		frame(root, Color3.fromRGB(110, 170, 100), 0.1, 0.3, 0.5, 0.55, 0, 8)
		label(root, "부산 · 맑음 25°  미세먼지 좋음", 0.05, 0.05, 0.9, 0.15, 44)
		local sun = label(root, "☀️", 0.66, 0.3, 0.3, 0.45, 120)
		label(root, "해운대 26° · 광안리 25° · 기장 24°", 0.05, 0.86, 0.9, 0.1, 30)
		upd = function(t)
			sun.Rotation = math.sin(t * 1.5) * 8
		end
	elseif ch == 3 then
		frame(root, Color3.fromRGB(40, 120, 60), 0, 0, 1, 1)
		frame(root, Color3.fromRGB(190, 150, 100), 0.35, 0.35, 0.3, 0.3, 0, 45)
		frame(root, Color3.fromRGB(10, 10, 14), 0, 0, 1, 0.14, 0.15)
		label(root, "  부산 3 : 2 서울   7회말 · 1사 2루", 0, 0, 1, 0.14, 40)
		local ball = frame(root, Color3.new(1, 1, 1), 0.5, 0.6, 0.02, 0.035)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = ball
		upd = function(t)
			local k = (t * 0.6) % 1
			ball.Position = UDim2.new(0.5 + k * 0.35, 0, 0.6 - math.sin(k * math.pi) * 0.45, 0)
		end
	elseif ch == 4 then
		local g = frame(root, Color3.new(1, 1, 1), 0, 0, 1, 1)
		local grad = Instance.new("UIGradient")
		grad.Rotation = 90
		grad.Color = ColorSequence.new(Color3.fromRGB(255, 170, 120), Color3.fromRGB(70, 50, 110))
		grad.Parent = g
		frame(root, Color3.fromRGB(20, 20, 30), 0.25, 0.4, 0.1, 0.45)
		frame(root, Color3.fromRGB(20, 20, 30), 0.62, 0.36, 0.11, 0.5)
		label(root, "\"…너 아직도 광안리 좋아해?\"", 0.1, 0.86, 0.8, 0.1, 34, Color3.fromRGB(255, 250, 220))
		upd = function(_t) end
	elseif ch == 5 then
		frame(root, Color3.fromRGB(12, 10, 20), 0, 0, 1, 1)
		label(root, "  🎵 광안리 플레이리스트", 0, 0.04, 1, 0.12, 40, Color3.fromRGB(255, 79, 163))
		local bars = {}
		for i = 0, 15 do
			local f = frame(root, if i % 2 == 0 then Color3.fromRGB(61, 214, 245) else Color3.fromRGB(255, 79, 163), 0.06 + i * 0.055, 0.5, 0.04, 0.3)
			table.insert(bars, f)
		end
		upd = function(t)
			for i, f in bars do
				local h = 0.15 + math.abs(math.sin(t * 3 + i * 0.7) * math.cos(t * 1.7 + i)) * 0.6
				f.Size = UDim2.new(0.04, 0, h, 0)
				f.Position = UDim2.new(0.06 + (i - 1) * 0.055, 0, 0.9 - h, 0)
			end
		end
	elseif ch == 6 then
		frame(root, Color3.fromRGB(100, 160, 255), 0, 0, 1, 1)
		frame(root, Color3.fromRGB(80, 170, 70), 0, 0.82, 1, 0.18)
		local blocks = {}
		for i = 0, 5 do
			table.insert(blocks, frame(root, Color3.fromRGB(200, 120, 60), 0.2 + i * 0.16, 0.55 + (i % 2) * 0.1, 0.08, 0.06))
		end
		local hero = frame(root, Color3.fromRGB(214, 52, 56), 0.1, 0.7, 0.05, 0.12)
		label(root, "SCORE 004250", 0.04, 0.03, 0.4, 0.1, 30)
		upd = function(t)
			local k = (t * 0.25) % 1
			hero.Position = UDim2.new(0.05 + k * 0.85, 0, 0.7 - math.abs(math.sin(t * 4)) * 0.18, 0)
		end
	elseif ch == 7 then
		frame(root, Color3.fromRGB(250, 240, 230), 0, 0, 1, 1)
		frame(root, Color3.fromRGB(120, 130, 150), 0.08, 0.3, 0.45, 0.25)
		frame(root, Color3.fromRGB(100, 110, 130), 0.08, 0.2, 0.45, 0.14)
		label(root, "3인 패브릭 소파", 0.58, 0.18, 0.4, 0.12, 40, Color3.fromRGB(30, 30, 34))
		label(root, "890,000원", 0.58, 0.34, 0.4, 0.16, 60, Color3.fromRGB(214, 40, 50))
		local cta = label(root, "지금 주문하세요! ☎ 1588-0000", 0.08, 0.78, 0.84, 0.12, 40, Color3.fromRGB(214, 40, 50))
		upd = function(t)
			cta.TextTransparency = if math.floor(t * 2) % 2 == 0 then 0 else 0.5
		end
	else
		local g = frame(root, Color3.new(1, 1, 1), 0, 0, 1, 1)
		local grad = Instance.new("UIGradient")
		grad.Rotation = 90
		grad.Color = ColorSequence.new(Color3.fromRGB(16, 20, 50), Color3.fromRGB(6, 10, 24))
		grad.Parent = g
		frame(root, Color3.fromRGB(61, 214, 245), 0, 0.55, 1, 0.012)
		local dots = {}
		for i = 0, 24 do
			table.insert(dots, frame(root, if i % 2 == 0 then Color3.fromRGB(61, 214, 245) else Color3.fromRGB(255, 79, 163), i / 24, 0.6 + (i % 3) * 0.06, 0.02, 0.008))
		end
		label(root, "  LIVE · 광안대교", 0, 0.03, 0.6, 0.1, 30, Color3.fromRGB(255, 90, 95))
		upd = function(t)
			for i, d in dots do
				d.BackgroundTransparency = 0.2 + math.abs(math.sin(t * 2 + i)) * 0.7
			end
		end
	end
	local tag = frame(root, Color3.new(0, 0, 0), 0.72, 0.03, 0.26, 0.09, 0.5)
	label(tag, " CH " .. ch .. " · " .. CHANNELS[ch], 0, 0, 1, 1, 22)
	return upd
end

-------------------------------------------------------------------------------------------------
-- Item effects
-------------------------------------------------------------------------------------------------
local NOTE_SOUND = "rbxasset://sounds/electronicpingshort.wav"
local HAT_SOUND = "rbxasset://sounds/clickfast.wav"
local TRACKS = {
	{ bpm = 84, notes = { 0, 4, 7, 11, 9, 7, 4, 2, 0, 4, 7, 12, 11, 7, 9, 5 } }, -- 로파이
	{ bpm = 112, notes = { 7, 9, 12, 14, 12, 9, 7, 4, 5, 7, 9, 12, 9, 7, 5, 2 } }, -- 시티팝
	{ bpm = 128, notes = { 0, 0, 7, 7, 9, 9, 7, -1, 5, 5, 4, 4, 2, 2, 0, -1 } }, -- 댄스
	{ bpm = 96, notes = { 0, 3, 7, 10, 12, 10, 7, 3, 2, 5, 8, 12, 10, 8, 5, 2 } }, -- 재즈
	{ bpm = 104, notes = { 4, 7, 11, 7, 2, 7, 9, 7, 0, 4, 7, 4, 2, 4, 5, 7 } }, -- 해변
	{ bpm = 72, notes = { 0, -1, 4, -1, 7, -1, 12, 11, 9, -1, 7, -1, 5, 4, 2, -1 } }, -- 발라드
}

local function itemPivot(m: Model): CFrame?
	local p = m:GetAttribute("Pivot")
	if typeof(p) == "CFrame" then
		return p
	end
	return nil
end

local function makeFish(parent: Instance, col: Color3, size: number): any
	local body = Instance.new("Part")
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.new(size, size, size)
	body.Color = col
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = true
	body.CanCollide = false
	body.CanQuery = false
	body.CanTouch = false
	body.CastShadow = false
	body.Parent = parent
	local tail = Instance.new("Part")
	tail.Size = Vector3.new(0.04, size * 0.7, size * 0.6)
	tail.Color = col:Lerp(Color3.new(1, 1, 1), 0.2)
	tail.Material = Enum.Material.SmoothPlastic
	tail.Anchored = true
	tail.CanCollide = false
	tail.CanQuery = false
	tail.CanTouch = false
	tail.CastShadow = false
	tail.Parent = parent
	return { body = body, tail = tail, size = size, phase = math.random() * 10, target = nil, pos = nil }
end

local function attachItem(m: Model)
	if not cur or cur.items[m] then
		return
	end
	local id = m:GetAttribute("ItemId")
	if type(id) ~= "string" or not Catalog.get(id) then
		return
	end
	local e: any = { model = m, id = id }
	cur.items[m] = e
	-- TV
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Screen" then
			e.screen = d
		elseif d:IsA("BasePart") and d.Name == "ClockHour" then
			e.hour = d
		elseif d:IsA("BasePart") and d.Name == "ClockMinute" then
			e.minute = d
		elseif d:IsA("BasePart") and d.Name == "Pin" then
			e.pin = d
		elseif d:IsA("BasePart") and d.Name == "MirrorBall" then
			e.ball = d
		elseif d:IsA("BasePart") and d.Name == "DPFire" then
			e.fire = true
		end
	end
	if e.hour or e.minute then
		local spec = Catalog.spec(id)
		for _, p in spec and spec.parts or {} do
			if p.n == "ClockHour" then
				e.hourCF = p.cf
			elseif p.n == "ClockMinute" then
				e.minuteCF = p.cf
			elseif p.n == "Pin" then
				e.pinCF = p.cf
			end
		end
	end
	if e.ball then
		e.ballParts = {}
		local spec = Catalog.spec(id)
		local idx = 0
		for _, d in m:GetChildren() do
			if d:IsA("BasePart") and (d.Name == "MirrorBall" or d.Name == "Facet") then
				idx += 1
				table.insert(e.ballParts, d)
			end
		end
		e.ballCF = {}
		for _, p in spec and spec.parts or {} do
			if p.n == "MirrorBall" or p.n == "Facet" then
				table.insert(e.ballCF, p.cf)
			end
		end
	end
	if e.fire then
		e.lights = {}
		for _, d in m:GetDescendants() do
			if d:IsA("PointLight") then
				table.insert(e.lights, { l = d, b = d.Brightness })
			end
		end
	end
	local tcf, tsz = m:GetAttribute("TankCF"), m:GetAttribute("TankSize")
	if typeof(tcf) == "CFrame" and typeof(tsz) == "Vector3" then
		e.tank = { cf = tcf, size = tsz, fish = {} }
		local cols = { Color3.fromRGB(255, 140, 40), Color3.fromRGB(60, 160, 255), Color3.fromRGB(255, 220, 60), Color3.fromRGB(240, 80, 120), Color3.fromRGB(120, 230, 200) }
		local n = if tsz.X > 2 then 5 else 2
		for i = 1, n do
			table.insert(e.tank.fish, makeFish(localFolder(), cols[(i - 1) % #cols + 1], math.clamp(tsz.Y * 0.12, 0.12, 0.28)))
		end
		e.conns = e.conns or {}
		table.insert(e.conns, m:GetAttributeChangedSignal("FedAt"):Connect(function()
			e.fedAt = os.clock()
		end))
	end
	if m:GetAttribute("Track") ~= nil then
		e.speakerPart = m:FindFirstChild("Cabinet") or m:FindFirstChild("Body") or m:FindFirstChild("Plinth") or m.PrimaryPart
	end
end

local function detachItem(m: Model)
	local e = cur and cur.items[m]
	if not e then
		return
	end
	cur.items[m] = nil
	if e.tvGui then
		e.tvGui:Destroy()
	end
	if e.tank then
		for _, f in e.tank.fish do
			f.body:Destroy()
			f.tail:Destroy()
		end
	end
	if e.sounds then
		for _, s in e.sounds do
			s:Destroy()
		end
	end
	if e.loop then
		e.loop:Destroy()
	end
	for _, c in e.conns or {} do
		c:Disconnect()
	end
end

local function updateTV(e: any, t: number, near: boolean)
	local on = e.model:GetAttribute("On") == true and near
	if not on then
		if e.tvGui then
			e.tvGui.Enabled = false
		end
		return
	end
	local ch = tonumber(e.model:GetAttribute("Channel")) or 1
	ch = math.clamp(math.floor(ch), 1, #CHANNELS)
	if not e.tvGui or e.tvGui.Adornee ~= e.screen then
		if e.tvGui then
			e.tvGui:Destroy()
		end
		local g = Instance.new("SurfaceGui")
		g.Name = "DPTV"
		g.Adornee = e.screen
		g.Face = Enum.NormalId.Front
		g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		g.PixelsPerStud = 50
		g.LightInfluence = 0
		pcall(function()
			(g :: any).Brightness = 1.4
		end)
		g.ResetOnSpawn = false
		local root = Instance.new("Frame")
		root.BackgroundColor3 = Color3.new(0, 0, 0)
		root.Size = UDim2.new(1, 0, 1, 0)
		root.ClipsDescendants = true
		root.Parent = g
		g.Parent = guiFolder()
		e.tvGui = g
		e.tvRoot = root
		e.tvCh = nil
	end
	e.tvGui.Enabled = true
	if e.tvCh ~= ch then
		e.tvCh = ch
		e.tvUpd = buildChannel(e.tvRoot, ch)
	end
	if e.tvUpd then
		e.tvUpd(t)
	end
end

local function updateClock(e: any)
	local pivot = itemPivot(e.model)
	if not pivot or not e.pinCF then
		return
	end
	local centre = (pivot * e.pinCF).Position
	local axis = pivot.LookVector
	local now = os.date("*t")
	local minA = (now.min + now.sec / 60) / 60 * math.pi * 2
	local hourA = ((now.hour % 12) + now.min / 60) / 12 * math.pi * 2
	local rot = function(a: number): CFrame
		return CFrame.new(centre) * CFrame.fromAxisAngle(axis, -a) * CFrame.new(-centre)
	end
	if e.hour and e.hourCF then
		e.hour.CFrame = rot(hourA) * (pivot * e.hourCF)
	end
	if e.minute and e.minuteCF then
		e.minute.CFrame = rot(minA) * (pivot * e.minuteCF)
	end
end

local function updateTank(e: any, dt: number, t: number)
	local pivot = itemPivot(e.model)
	if not pivot then
		return
	end
	local tank = e.tank
	local cf = pivot * tank.cf
	local h = tank.size / 2 - Vector3.new(0.25, 0.2, 0.25)
	local fed = e.fedAt and os.clock() - e.fedAt < 6
	for i, f in tank.fish do
		if not f.target or (f.pos and (f.pos - f.target).Magnitude < 0.1) or math.random() < 0.004 then
			f.target = Vector3.new((math.random() * 2 - 1) * h.X, (math.random() * 2 - 1) * h.Y, (math.random() * 2 - 1) * h.Z)
		end
		local target = if fed then Vector3.new(math.sin(t + i) * 0.2, h.Y, math.cos(t + i) * 0.2) else f.target
		f.pos = f.pos or Vector3.zero
		local d = target - f.pos
		local speed = if fed then 1.6 else 0.55
		local stepV = if d.Magnitude > 1e-3 then d.Unit * math.min(d.Magnitude, speed * dt) else Vector3.zero
		f.pos += stepV
		local dir = if stepV.Magnitude > 1e-4 then stepV.Unit else (f.dir or Vector3.new(1, 0, 0))
		f.dir = dir
		local wpos = cf:PointToWorldSpace(f.pos)
		local look = cf:VectorToWorldSpace(dir)
		local frameCF = CFrame.lookAt(wpos, wpos + look)
		f.body.CFrame = frameCF
		f.tail.CFrame = frameCF * CFrame.new(0, 0, f.size * 0.6) * CFrame.Angles(0, math.sin(t * 9 + f.phase) * 0.6, 0)
	end
end

local function playNote(e: any, semis: number)
	e.sounds = e.sounds or {}
	if #e.sounds < 4 then
		local s = Instance.new("Sound")
		s.SoundId = if semis == -100 then HAT_SOUND else NOTE_SOUND
		s.Volume = Config.SPEAKER_VOLUME
		s.RollOffMaxDistance = 50
		s.RollOffMinDistance = 6
		s.Parent = e.speakerPart
		table.insert(e.sounds, s)
	end
	e.si = ((e.si or 0) % #e.sounds) + 1
	local s = e.sounds[e.si] :: Sound
	s.SoundId = if semis == -100 then HAT_SOUND else NOTE_SOUND
	s.PlaybackSpeed = if semis == -100 then 1.4 else 0.5 * 2 ^ (semis / 12)
	s.Volume = Config.SPEAKER_VOLUME * (if semis == -100 then 0.35 else 1)
	s.TimePosition = 0
	s:Play()
end

local function updateSpeaker(e: any, t: number, near: boolean)
	local on = e.model:GetAttribute("On") == true and near and e.speakerPart ~= nil
	local tracks = Config.SPEAKER_TRACKS
	if #tracks > 0 then
		if on then
			local idx = ((tonumber(e.model:GetAttribute("Track")) or 1) - 1) % #tracks + 1
			if not e.loop then
				local s = Instance.new("Sound")
				s.Looped = true
				s.Volume = Config.SPEAKER_VOLUME
				s.RollOffMaxDistance = 60
				s.Parent = e.speakerPart
				e.loop = s
			end
			if e.loopIdx ~= idx then
				e.loopIdx = idx
				e.loop.SoundId = tracks[idx].id
				e.loop:Play()
			elseif not e.loop.IsPlaying then
				e.loop:Play()
			end
		elseif e.loop then
			e.loop:Stop()
		end
		return
	end
	if not on then
		return
	end
	local tr = TRACKS[((tonumber(e.model:GetAttribute("Track")) or 1) - 1) % #TRACKS + 1]
	local stepLen = 60 / tr.bpm / 2
	local step = math.floor(t / stepLen)
	if e.lastStep ~= step then
		e.lastStep = step
		local n = tr.notes[(step % #tr.notes) + 1]
		if n >= 0 then
			playNote(e, n)
		end
		if step % 2 == 1 then
			playNote(e, -100)
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Home attach / loop
-------------------------------------------------------------------------------------------------
local function leave()
	if not cur then
		return
	end
	for m in table.clone(cur.items) do
		detachItem(m)
	end
	clearSurfaces()
	stopParty()
	local cc = Lighting:FindFirstChild("GwDecorPlusCC")
	if cc then
		cc:Destroy()
	end
	for _, c in cur.conns do
		c:Disconnect()
	end
	cur = nil
end

local function enter(model: Model, U: any)
	leave()
	cur = { model = model, U = U, surfaces = {}, items = {}, conns = {} }
	applyFinish()
	applyLight()
	table.insert(cur.conns, model:GetAttributeChangedSignal("DPFinish"):Connect(applyFinish))
	table.insert(cur.conns, model:GetAttributeChangedSignal("DPLight"):Connect(applyLight))
	local folder = model:FindFirstChild(Config.FOLDER_NAME) or model:WaitForChild(Config.FOLDER_NAME, 10)
	if folder then
		for _, m in folder:GetChildren() do
			if m:IsA("Model") then
				attachItem(m)
			end
		end
		table.insert(cur.conns, folder.ChildAdded:Connect(function(m)
			if m:IsA("Model") then
				task.defer(attachItem, m)
			end
		end))
		table.insert(cur.conns, folder.ChildRemoved:Connect(function(m)
			if m:IsA("Model") then
				detachItem(m)
			end
		end))
	end
end

function Effects.start(getHome: () -> (Model?, any?))
	local acc, slow = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		slow += dt
		if slow > 0.5 then
			slow = 0
			local model, U = getHome()
			if model and U then
				if not cur or cur.model ~= model or cur.U ~= U then
					enter(model, U)
				end
			elseif cur then
				leave()
			end
		end
		if not cur or acc < 1 / 30 then
			return
		end
		local step = acc
		acc = 0
		local t = os.clock()
		local cam = workspace.CurrentCamera
		local camPos = if cam then cam.CFrame.Position else Vector3.zero
		for m, e in cur.items do
			if not m.Parent then
				detachItem(m)
				continue
			end
			local pivot = itemPivot(m)
			local near = pivot ~= nil and (pivot.Position - camPos).Magnitude < Config.EFFECT_RANGE
			if e.screen then
				updateTV(e, t, near)
			end
			if near and (e.hour or e.minute) and (not e.clockT or t - e.clockT > 1) then
				e.clockT = t
				updateClock(e)
			end
			if e.tank and near then
				updateTank(e, step, t)
			end
			if e.speakerPart then
				updateSpeaker(e, t, near)
			end
			if e.fire and near and m:GetAttribute("LampOn") ~= false then
				for _, l in e.lights do
					if l.l.Enabled then
						l.l.Brightness = l.b * (0.8 + 0.25 * math.noise(t * 3, l.b * 10))
					end
				end
			end
			if e.ball and near and m:GetAttribute("LampOn") ~= false and pivot then
				local a = CFrame.Angles(0, t * 0.8, 0)
				local c = pivot * CFrame.new(0, 0.7, 0)
				for i, p in e.ballParts do
					local base = e.ballCF[i]
					if base then
						local rel = CFrame.new(0, -0.7, 0) * base
						p.CFrame = c * a * rel
					end
				end
			end
		end
		-- party: cycle the home's light colours
		if cur.party and cur.partyOrig then
			local h = (t * 0.25) % 1
			local i = 0
			for l in cur.partyOrig do
				i += 1
				if l.Parent then
					l.Color = Color3.fromHSV((h + i * 0.17) % 1, 0.75, 1)
				end
			end
			local cc = Lighting:FindFirstChild("GwDecorPlusCC")
			if cc then
				(cc :: ColorCorrectionEffect).TintColor = Color3.fromHSV(h, 0.12, 1)
			end
		end
	end)
end

return Effects
