-- Living: the small things that make the interiors near the camera feel lived in (client only).
--   * screens (GwB_Screen): TV channels while the TV is on, PC desktops / the PC방 login screen,
--   * spinning parts (GwB_Spin, attrs Rpm / Axis): fans, washer drums, AC condensers get visible blades,
--   * 센서등 (GwB_MotionLight): corridor and stair lights switch on when someone walks by, off after a while,
--   * old fluorescent tubes (GwB_Flicker) flicker now and then,
--   * water (GwB_Water heads): a stream while the shower / bath runs (fixture attribute On).
-- Everything here is local decoration: nothing is sent to the server.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Living = {}

local NEAR = 55

-------------------------------------------------------------------------------------------------
-- screens
-------------------------------------------------------------------------------------------------
local CHANNELS = {
	{ name = "KBC 뉴스 9", bg = Color3.fromRGB(20, 50, 110), fg = Color3.fromRGB(255, 255, 255), lines = { "광안대교 야간 경관조명 새 단장", "주말 부산 맑음 · 낮 최고 27도", "해운대 · 광안리 해수욕장 개장 준비" } },
	{ name = "드라마 〈바다가 보이는 집〉", bg = Color3.fromRGB(120, 70, 50), fg = Color3.fromRGB(255, 236, 210), lines = { "\"그 집… 정말 계약한 거야?\"", "\"오션뷰잖아. 매일 이 바다 보면서 살 거야\"", "\"…다음 주에 이사 가자\"" } },
	{ name = "예능 〈동네 한 바퀴〉", bg = Color3.fromRGB(250, 190, 40), fg = Color3.fromRGB(60, 30, 0), lines = { "ㅋㅋㅋㅋㅋ", "돼지국밥 한 그릇에 행복 충전!", "다음 코스는 민락동 회센터?!" } },
	{ name = "스포츠 LIVE", bg = Color3.fromRGB(30, 110, 50), fg = Color3.fromRGB(255, 255, 255), lines = { "롯데 3 : 2 두산  8회말", "사직 구장 만원 관중", "부산 갈매기 ♪" } },
	{ name = "음악방송", bg = Color3.fromRGB(90, 30, 140), fg = Color3.fromRGB(255, 220, 255), lines = { "♪ 광안리 밤바다 - 오션 브리즈", "♪ 1위 후보 공개!", "♪ 앵콜 무대" } },
	{ name = "날씨", bg = Color3.fromRGB(60, 140, 200), fg = Color3.fromRGB(255, 255, 255), lines = { "부산 ☀ 27° / 21°", "파고 0.5~1.0m · 해수욕 적합", "자외선 높음 🧴" } },
}

type ScreenRec = { part: BasePart, gui: SurfaceGui?, kind: string, model: Instance?, title: TextLabel?, body: TextLabel?, bg: Frame?, state: string, t: number }
local screens: { [BasePart]: ScreenRec } = {}

local function fixtureOf(p: Instance): Instance?
	local m = p.Parent
	while m and m ~= workspace do
		if m:IsA("Model") and (m:GetAttribute("Kind") or m:GetAttribute("ShopId")) then
			return m
		end
		m = m.Parent
	end
	return p.Parent
end

local function makeGui(r: ScreenRec)
	local g = Instance.new("SurfaceGui")
	g.Name = "GwB_ScreenGui"
	g.Face = Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 40
	g.LightInfluence = 0
	g.MaxDistance = NEAR + 10
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BorderSizePixel = 0
	bg.Parent = g
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0.3, 0)
	title.TextScaled = true
	title.Font = Enum.Font.GothamBold
	title.Parent = bg
	local body = Instance.new("TextLabel")
	body.BackgroundTransparency = 1
	body.Position = UDim2.new(0.05, 0, 0.36, 0)
	body.Size = UDim2.new(0.9, 0, 0.56, 0)
	body.TextScaled = true
	body.TextWrapped = true
	body.Font = Enum.Font.Gotham
	body.Parent = bg
	g.Parent = r.part
	r.gui, r.bg, r.title, r.body = g, bg, title, body
end

local function screenState(r: ScreenRec): string
	local m = r.model
	local on = m and m:GetAttribute("On") == true
	if r.kind == "tv" then
		return if on then "tv" .. tostring(m and m:GetAttribute("Channel") or 1) else "off"
	elseif r.kind == "pc" then
		if on then
			return "pc_on"
		end
		return if m and m:GetAttribute("ShopId") then "pc_login" else "off"
	end
	return "other"
end

local function drawScreen(r: ScreenRec, t: number)
	local st = screenState(r)
	if st == "off" or st == "other" then
		if r.gui then
			r.gui:Destroy()
			r.gui = nil
		end
		r.state = st
		return
	end
	if r.part:FindFirstChildWhichIsA("SurfaceGui") and not r.gui then
		return -- the server drives this screen (karaoke lyrics, shop boards)
	end
	if not r.gui then
		makeGui(r)
	end
	local bg, title, body = r.bg :: Frame, r.title :: TextLabel, r.body :: TextLabel
	local beat = math.floor(t / 3)
	if string.sub(st, 1, 2) == "tv" then
		local ch = CHANNELS[((tonumber(string.sub(st, 3)) or 1) - 1) % #CHANNELS + 1]
		local pulse = 0.88 + 0.12 * math.sin(t * 1.7)
		bg.BackgroundColor3 = Color3.new(ch.bg.R * pulse, ch.bg.G * pulse, ch.bg.B * pulse)
		title.TextColor3 = ch.fg
		body.TextColor3 = ch.fg
		title.Text = ch.name
		body.Text = ch.lines[beat % #ch.lines + 1]
	elseif st == "pc_on" then
		bg.BackgroundColor3 = Color3.fromRGB(14, 20, 40)
		title.TextColor3 = Color3.fromRGB(120, 220, 255)
		body.TextColor3 = Color3.fromRGB(255, 255, 255)
		title.Text = "GWANGAN LEGENDS"
		local k = beat % 3
		body.Text = if k == 0 then "⚔️ 전투 중…" elseif k == 1 then "🏆 승리!" else "🔄 다음 판 매칭"
	else
		bg.BackgroundColor3 = Color3.fromRGB(18, 18, 26)
		title.TextColor3 = Color3.fromRGB(255, 200, 60)
		body.TextColor3 = Color3.fromRGB(200, 200, 210)
		title.Text = "GW PC CAFE"
		body.Text = "카운터에서 이용권 구매 후\n자리에 앉아 로그인하세요"
	end
	r.state = st
end

-------------------------------------------------------------------------------------------------
-- spinning parts
-------------------------------------------------------------------------------------------------
type SpinRec = { part: BasePart, blades: { BasePart }, base: CFrame, angle: number }
local spins: { [BasePart]: SpinRec } = {}

local function makeBlades(p: BasePart): { BasePart }
	local out = {}
	local dia = math.max(p.Size.Y, p.Size.Z)
	local n = if p.Name == "Drum" then 1 else 3
	for i = 1, n do
		local b = Instance.new("Part")
		b.Name = "GwB_Blade"
		b.Anchored = true
		b.CanCollide = false
		b.CanQuery = false
		b.CanTouch = false
		b.CastShadow = false
		b.Material = Enum.Material.SmoothPlastic
		if p.Name == "Drum" then
			-- laundry tumbling inside the glass drum
			b.Size = Vector3.new(math.min(p.Size.X, 0.3), dia * 0.35, dia * 0.35)
			b.Color = Color3.fromRGB(80, 120, 200)
		else
			b.Size = Vector3.new(0.05, dia * 0.46, dia * 0.16)
			b.Color = p.Color:Lerp(Color3.new(1, 1, 1), 0.15)
			b.Transparency = 0.15
		end
		b:SetAttribute("Index", i)
		b.Parent = p
		table.insert(out, b)
	end
	return out
end

local function placeBlades(r: SpinRec)
	local p = r.part
	-- Roblox cylinders run along X: the blades turn about the part's X axis
	local n = #r.blades
	for i, b in r.blades do
		local a = r.angle + (i - 1) * (2 * math.pi / n)
		if p.Name == "Drum" then
			b.CFrame = r.base * CFrame.Angles(a, 0, 0) * CFrame.new(0, p.Size.Y * 0.18, 0)
		else
			b.CFrame = r.base * CFrame.Angles(a, 0, 0) * CFrame.new(0, b.Size.Y / 2, 0)
		end
	end
end

-------------------------------------------------------------------------------------------------
-- 센서등 + flicker
-------------------------------------------------------------------------------------------------
local motionOnUntil: { [Instance]: number } = {}

local function setLampPart(p: BasePart, on: boolean)
	if on then
		local c = p:GetAttribute("LampOn")
		p.Material = Enum.Material.Neon
		if typeof(c) == "Color3" then
			p.Color = c
		end
	else
		local c = p:GetAttribute("LampOff")
		p.Material = Enum.Material.SmoothPlastic
		if typeof(c) == "Color3" then
			p.Color = c
		end
	end
end

-------------------------------------------------------------------------------------------------
-- water
-------------------------------------------------------------------------------------------------
local streams: { [BasePart]: BasePart } = {}

local function waterOn(head: BasePart): boolean
	local m = fixtureOf(head)
	return m ~= nil and m:GetAttribute("On") == true
end

local function makeStream(head: BasePart): BasePart
	local s = Instance.new("Part")
	s.Name = "GwB_Stream"
	s.Anchored = true
	s.CanCollide = false
	s.CanQuery = false
	s.CanTouch = false
	s.CastShadow = false
	s.Material = Enum.Material.Glass
	s.Color = Color3.fromRGB(170, 215, 245)
	s.Transparency = 0.45
	s.Shape = Enum.PartType.Cylinder
	-- down to the fixture's floor (its model pivot) or 6 studs
	local m = fixtureOf(head)
	local floorY = if m and m:IsA("Model") then m:GetPivot().Y else head.Position.Y - 6
	local len = math.clamp(head.Position.Y - floorY, 1, 8)
	s.Size = Vector3.new(len, 0.35, 0.35)
	s.CFrame = CFrame.new(head.Position - Vector3.new(0, len / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	s.Parent = head
	return s
end

-------------------------------------------------------------------------------------------------
local function charPositions(): { Vector3 }
	local out = {}
	for _, pl in Players:GetPlayers() do
		local c = pl.Character
		local r = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
		if r then
			table.insert(out, r.Position)
		end
	end
	return out
end

local function slowPass()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local camPos = cam.CFrame.Position
	local now = os.clock()
	-- screens near the camera
	local seen = {}
	for _, p in CollectionService:GetTagged("GwB_Screen") do
		if p:IsA("BasePart") and p:IsDescendantOf(workspace) and (p.Position - camPos).Magnitude < NEAR then
			seen[p] = true
			local r = screens[p]
			if not r then
				r = { part = p, gui = nil, kind = (p:GetAttribute("ScreenKind") :: string?) or "tv", model = fixtureOf(p), state = "", t = 0 }
				screens[p] = r
			end
			drawScreen(r :: ScreenRec, now)
		end
	end
	for p, r in screens do
		if not seen[p] then
			if r.gui then
				r.gui:Destroy()
			end
			screens[p] = nil
		end
	end
	-- spinning parts near the camera
	local seenS = {}
	for _, p in CollectionService:GetTagged("GwB_Spin") do
		if p:IsA("BasePart") and p:IsDescendantOf(workspace) and (p.Position - camPos).Magnitude < NEAR and (tonumber(p:GetAttribute("Rpm")) or 0) ~= 0 then
			seenS[p] = true
			if not spins[p] then
				spins[p] = { part = p, blades = makeBlades(p), base = p.CFrame, angle = 0 }
			end
		end
	end
	for p, r in spins do
		if not seenS[p] then
			for _, b in r.blades do
				b:Destroy()
			end
			spins[p] = nil
		end
	end
	-- 센서등
	local chars = charPositions()
	for _, inst in CollectionService:GetTagged("GwB_MotionLight") do
		if not inst:IsDescendantOf(workspace) then
			continue
		end
		local part = if inst:IsA("BasePart") then inst else (inst.Parent :: any)
		if not part or not part:IsA("BasePart") then
			continue
		end
		local pos = part.Position
		local trig = false
		if (pos - camPos).Magnitude < 90 then
			for _, cp in chars do
				local d = cp - pos
				if math.abs(d.Y) < 9 and d.X * d.X + d.Z * d.Z < 11 * 11 then
					trig = true
					break
				end
			end
		end
		if trig then
			motionOnUntil[inst] = now + 12
		end
		local on = (motionOnUntil[inst] or 0) > now
		if inst:IsA("Light") then
			if inst.Enabled ~= on then
				inst.Enabled = on
			end
		elseif inst:IsA("BasePart") then
			local cur = inst.Material == Enum.Material.Neon
			if cur ~= on then
				setLampPart(inst, on)
			end
		end
	end
	-- water streams
	for _, head in CollectionService:GetTagged("GwB_Water") do
		if head:IsA("BasePart") then
			local want = head:IsDescendantOf(workspace) and (head.Position - camPos).Magnitude < NEAR and waterOn(head)
			if want and not streams[head] then
				streams[head] = makeStream(head)
			elseif not want and streams[head] then
				streams[head]:Destroy()
				streams[head] = nil
			end
		end
	end
	for head, s in streams do
		if not head.Parent then
			s:Destroy()
			streams[head] = nil
		end
	end
end

local flickerT = 0
local function frame(dt: number)
	for _, r in spins do
		local rpm = tonumber(r.part:GetAttribute("Rpm")) or 0
		if rpm ~= 0 and r.part.Parent then
			r.base = r.part.CFrame
			r.angle = (r.angle + dt * rpm / 60 * 2 * math.pi) % (2 * math.pi)
			placeBlades(r)
		end
	end
	-- flicker: a random tube stutters a few times a second
	flickerT += dt
	if flickerT > 0.12 then
		flickerT = 0
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		for _, l in CollectionService:GetTagged("GwB_Flicker") do
			if l:IsA("Light") and l.Parent and l.Parent:IsA("BasePart") and ((l.Parent :: BasePart).Position - cam.CFrame.Position).Magnitude < 60 then
				local base = tonumber(l:GetAttribute("BaseBrightness"))
				if not base then
					base = l.Brightness
					l:SetAttribute("BaseBrightness", base)
				end
				local b = base :: number
				l.Brightness = if math.random() < 0.08 then b * (0.1 + math.random() * 0.3) else b
			end
		end
	end
end

function Living.start()
	task.spawn(function()
		while true do
			local ok, err = pcall(slowPass)
			if not ok then
				warn("[GwangalliBuildings] living: " .. tostring(err))
			end
			task.wait(0.5)
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		local ok, err = pcall(frame, dt)
		if not ok then
			warn("[GwangalliBuildings] living frame: " .. tostring(err))
		end
	end)
end

return Living
