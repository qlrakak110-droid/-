-- 지도: a top-down map of Gwangalli built once from Frames in normalised (Scale) coordinates, so zoom
-- only resizes one "World" frame. The first build is spread over several frames (a loading card
-- shows meanwhile): sea, sand, roads with street names, Gwangan Bridge, area labels, category pins
-- for every Destination, a pulsing "me" dot with a heading arrow (5 Hz while visible) and the
-- waypoint ring. Built with the GwangalliUI kit.
--   search: 🔍 in the header (or the search bar on tall screens) -> result list -> pin
--   category chips: 전체 / 직장 / 집 / 상점 / 클럽 / 병원 / 교통 / 명소
--   pins never overlap: after every zoom / pan the pins are culled in screen space by priority
--   pan: drag;  zoom: pinch / wheel / + −;  ◎ recentres on me
--   tap a pin -> card: name, category, distance, walking time, 길안내 (PhoneAction "setWaypoint" +
--   the 3D marker via Tracker) and 빠른 이동 (GwangalliTravel remote through Dest.travel)

local UserInputService = game:GetService("UserInputService")

return function(ctx: any)
	local K, Dest, Tracker, Net, Life, AppKit = ctx.K, ctx.Dest, ctx.Tracker, ctx.Net, ctx.Life, ctx.AppKit
	local MapData = require(script.Parent.Parent:WaitForChild("MapData"))

	local B = MapData.Bounds
	local SPAN_X, SPAN_Z = B.x1 - B.x0, B.z1 - B.z0
	local ASPECT = SPAN_X / SPAN_Z

	local CATS = {
		{ id = "all", label = "전체", icon = nil, color = K.Color.cyan, rank = 9 },
		{ id = "work", label = "직장", icon = "💼", color = Color3.fromRGB(255, 190, 60), rank = 1 },
		{ id = "home", label = "집", icon = "🏠", color = Color3.fromRGB(40, 204, 196), rank = 2 },
		{ id = "shop", label = "상점", icon = "🛍️", color = Color3.fromRGB(255, 128, 84), rank = 4 },
		{ id = "club", label = "클럽", icon = "🎉", color = Color3.fromRGB(170, 104, 255), rank = 3 },
		{ id = "hospital", label = "병원", icon = "🏥", color = Color3.fromRGB(255, 90, 95), rank = 5 },
		{ id = "transit", label = "교통", icon = "🚇", color = Color3.fromRGB(84, 150, 255), rank = 6 },
		{ id = "spot", label = "명소", icon = "📍", color = Color3.fromRGB(80, 210, 130), rank = 7 },
	}
	local CAT: { [string]: any } = {}
	for _, c in CATS do
		CAT[c.id] = c
	end
	local KEYWORDS = {
		{ "hospital", { "병원", "지구대", "약국" } },
		{ "transit", { "지하철", "역 ", "출구", "주유소", "주차장", "택시", "만남의 광장" } },
		{ "club", { "CLUB", "클럽", "노래", "PC방", "게임", "볼링", "당구", "찜질" } },
		{ "shop", { "GS25", "홈플러스", "스타벅스", "편집숍", "살롱", "빵", "마켓", "직판장", "홍미당", "브롱스", "휘트니스" } },
		{ "home", { "자이", "지웰", "삼익", "오션", "아파트", "원룸", "오피스텔", "고시원" } },
	}

	local workPlaces: { [string]: boolean } = {}
	local homePlaces: { [string]: boolean } = {}
	local function rebuildPlaceSets()
		table.clear(workPlaces)
		table.clear(homePlaces)
		for _, j in Life.jobs() do
			if j.place ~= "" then
				workPlaces[j.place] = true
			end
		end
		for _, l in Life.listings() do
			if l.place ~= "" then
				homePlaces[l.place] = true
			end
		end
	end
	local function categoryOf(name: string): string
		if workPlaces[name] then
			return "work"
		end
		if homePlaces[name] then
			return "home"
		end
		for _, kw in KEYWORDS do
			for _, word in kw[2] do
				if string.find(name, word, 1, true) then
					return kw[1]
				end
			end
		end
		return "spot"
	end

	local app = {}
	local header: any
	local body: Frame
	local chipsBar: ScrollingFrame
	local chipApis: { [string]: any } = {}
	local searchWrap: Frame
	local search: any
	local results: ScrollingFrame
	local canvas: Frame
	local world: Frame
	local base: Frame
	local pinLayer: Frame
	local roadLabels: { TextLabel } = {}
	local meDot: Frame
	local meCone: Frame
	local mePulse: Frame
	local waypointRing: Frame
	local zoomCol: Frame
	local loading: Frame
	local placeCard: Frame
	local cardIcon: Frame
	local cardTitle: TextLabel
	local cardSub: TextLabel
	local statusLabel: TextLabel
	local pins: { [string]: any } = {}
	local pinsKey = ""
	local filter = "all"
	local zoom = 1
	local pan = Vector2.new(0, 0)
	local visible = false
	local loopSerial = 0
	local selected: string? = nil
	local pendingUntil = 0
	local firstShown = false
	local staticBuilt = false
	local building = false
	local searchOpen = false
	local tall = false

	local function norm(x: number, z: number): (number, number)
		return (x - B.x0) / SPAN_X, (z - B.z0) / SPAN_Z
	end

	---------------------------------------------------------------------------------------------------
	-- Static map (spread over frames)
	---------------------------------------------------------------------------------------------------
	local function seg(parent: Instance, x1: number, z1: number, x2: number, z2: number, width: number, color: Color3)
		local u1, v1 = norm(x1, z1)
		local u2, v2 = norm(x2, z2)
		local du, dv = u2 - u1, (v2 - v1) / ASPECT
		local len = math.sqrt(du * du + dv * dv)
		if len < 1e-5 then
			return
		end
		K.frame(parent, {
			Name = "Seg",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale((u1 + u2) / 2, (v1 + v2) / 2),
			Size = UDim2.new(len, width * 0.5, 0, width),
			Rotation = math.deg(math.atan2(dv, du)),
			BackgroundTransparency = 0,
			BackgroundColor3 = color,
		})
	end

	local function coastZ(x: number): number
		local pts = MapData.Coast
		if x <= pts[1][1] then
			return pts[1][2]
		end
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			if x >= a[1] and x <= b[1] then
				local u = (x - a[1]) / math.max(1e-6, b[1] - a[1])
				return a[2] + (b[2] - a[2]) * u
			end
		end
		return pts[#pts][2]
	end

	-- builds ~200 frames in batches of 30 per frame
	local function drawStatic(done: () -> ())
		building = true
		world.BackgroundColor3 = Color3.fromRGB(38, 44, 58)
		world.BackgroundTransparency = 0
		-- everything static lives in "Base", created before the pins / me layers
		local jobs: { () -> () } = {}
		local strips = 60
		for i = 0, strips - 1 do
			table.insert(jobs, function()
				local x0 = B.x0 + SPAN_X * i / strips
				local xm = x0 + SPAN_X / strips / 2
				local _, v = norm(xm, coastZ(xm))
				K.frame(base, { Name = "Sea", Position = UDim2.fromScale(i / strips, 0), Size = UDim2.fromScale(1 / strips + 0.002, math.max(0, v)), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(22, 58, 100) })
			end)
		end
		local bx0, bx1 = MapData.Beach.x0, MapData.Beach.x1
		local n = 30
		for i = 0, n - 1 do
			table.insert(jobs, function()
				local xa = bx0 + (bx1 - bx0) * i / n
				local xb = bx0 + (bx1 - bx0) * (i + 1) / n
				local xm = (xa + xb) / 2
				local ua = norm(xa, 0)
				local ub = norm(xb, 0)
				local _, top = norm(xm, coastZ(xm))
				local _, bottom = norm(xm, MapData.baseline(xm))
				K.frame(base, { Name = "Sand", Position = UDim2.fromScale(ua, top), Size = UDim2.fromScale(ub - ua + 0.001, math.max(0.002, bottom - top)), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(206, 184, 130) })
			end)
		end
		for _, r in MapData.Roads do
			local pts = r.points
			for i = 1, #pts - 1 do
				table.insert(jobs, function()
					seg(base, pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2], if r.width >= 3 then 3 else 2, if r.width >= 3 then Color3.fromRGB(150, 158, 176) else Color3.fromRGB(104, 112, 130))
				end)
			end
			-- street name at the road's middle (shown from zoom 2)
			table.insert(jobs, function()
				local mid = pts[math.max(1, math.floor(#pts / 2))]
				local nxt = pts[math.min(#pts, math.floor(#pts / 2) + 1)]
				local u, v = norm((mid[1] + nxt[1]) / 2, (mid[2] + nxt[2]) / 2)
				local vertical = math.abs(nxt[1] - mid[1]) < math.abs(nxt[2] - mid[2])
				local l = K.text(base, { Name = "RoadLabel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(u, if vertical then 18 else 0, v, if vertical then 0 else -9), Size = UDim2.fromOffset(70, 14), Text = r.name, TextColor3 = Color3.fromRGB(200, 208, 224), TextSize = K.Type.micro, Font = K.Font.medium, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.55, ZIndex = 2, Visible = false })
				table.insert(roadLabels, l)
			end)
		end
		table.insert(jobs, function()
			local br = MapData.Bridge
			for i = 1, #br - 1 do
				seg(base, br[i][1], br[i][2], br[i + 1][1], br[i + 1][2], 3, Color3.fromRGB(170, 140, 255))
			end
		end)
		for _, lb in MapData.Labels do
			table.insert(jobs, function()
				local u, v = norm(lb.x, lb.z)
				K.text(base, { Name = "AreaLabel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(u, v), Size = UDim2.fromOffset(110, 16), Text = lb.text, TextColor3 = Color3.fromRGB(226, 232, 244), TextSize = K.Type.caption, Font = K.Font.bold, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.45, ZIndex = 2 })
			end)
		end
		task.spawn(function()
			for i, job in jobs do
				local ok, err = pcall(job)
				if not ok then
					warn("[GwangalliPhone] map build: " .. tostring(err))
				end
				if i % 30 == 0 then
					task.wait()
				end
			end
			building = false
			staticBuilt = true
			done()
		end)
	end

	---------------------------------------------------------------------------------------------------
	-- Me / pins
	---------------------------------------------------------------------------------------------------
	local function rootPart(): any
		local char = ctx.player.Character
		if not char then
			return nil
		end
		local root = char:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			return root
		end
		local ok, pivot = pcall(function()
			return (char :: Model):GetPivot()
		end)
		if ok and typeof(pivot) == "CFrame" then
			return { Position = pivot.Position, CFrame = pivot }
		end
		return nil
	end

	-- the canvas size: AbsoluteSize once the engine has laid it out, else derived from the phone
	-- layout (the first open reads it in the same frame the canvas was sized)
	local canvasTop = 0
	local function canvasSize(): Vector2
		local cs = canvas.AbsoluteSize
		if cs.X >= 60 and cs.Y >= 60 then
			return cs
		end
		local L = ctx.phone.layout()
		return Vector2.new(math.max(100, L.screenW - 16), math.max(60, L.screenH - canvasTop - 8))
	end

	local function baseSize(): Vector2
		local cs = canvasSize()
		local w = math.max(cs.X, 100)
		local h = math.max(cs.Y, 60)
		local s = math.min(w / SPAN_X, h / SPAN_Z)
		return Vector2.new(SPAN_X * s, SPAN_Z * s)
	end

	-- Screen-space pin culling: highest priority first, a pin shows only where its 44 px hit area is
	-- free (inside the canvas, off the zoom column / card / other pins).
	local function cullPins()
		local cs = canvasSize()
		if cs.X < 20 then
			return
		end
		local ws = baseSize() * zoom
		local blocked = {}
		if zoomCol.Visible then
			table.insert(blocked, { x = cs.X - 54, y = 0, w = 54, h = 154 })
		end
		if placeCard.Visible then
			table.insert(blocked, { x = 0, y = cs.Y - 106, w = cs.X, h = 106 })
		end
		if statusLabel.Visible then
			table.insert(blocked, { x = 0, y = 0, w = cs.X - 60, h = 36 })
		end
		local order = {}
		for name, p in pins do
			if filter == "all" or p.cat == filter then
				table.insert(order, p)
			else
				p.button.Visible = false
			end
		end
		table.sort(order, function(a, b)
			local ra = if a.name == selected then 0 else (CAT[a.cat] or CAT.spot).rank
			local rb = if b.name == selected then 0 else (CAT[b.cat] or CAT.spot).rank
			if ra ~= rb then
				return ra < rb
			end
			return a.name < b.name
		end)
		local kept = {}
		for _, p in order do
			local x = pan.X + p.u * ws.X
			local y = pan.Y + p.v * ws.Y
			local ok = x >= 22 and x <= cs.X - 22 and y >= 22 and y <= cs.Y - 22
			if ok then
				for _, r in blocked do
					if x + 22 > r.x and x - 22 < r.x + r.w and y + 22 > r.y and y - 22 < r.y + r.h then
						ok = false
						break
					end
				end
			end
			if ok then
				for _, q in kept do
					if math.abs(q.x - x) < 45 and math.abs(q.y - y) < 45 then
						ok = false
						break
					end
				end
			end
			p.button.Visible = ok
			if ok then
				table.insert(kept, { x = x, y = y })
			end
		end
	end

	local function clampPan()
		local cs = canvasSize()
		local ws = baseSize() * zoom
		local minX, maxX = math.min(0, cs.X - ws.X), math.max(0, cs.X - ws.X)
		local minY, maxY = math.min(0, cs.Y - ws.Y), math.max(0, cs.Y - ws.Y)
		if ws.X <= cs.X then
			minX, maxX = (cs.X - ws.X) / 2, (cs.X - ws.X) / 2
		end
		if ws.Y <= cs.Y then
			minY, maxY = (cs.Y - ws.Y) / 2, (cs.Y - ws.Y) / 2
		end
		pan = Vector2.new(math.clamp(pan.X, minX, maxX), math.clamp(pan.Y, minY, maxY))
	end

	local cullQueued = false
	local function applyView()
		local ws = baseSize() * zoom
		world.Size = UDim2.fromOffset(ws.X, ws.Y)
		clampPan()
		world.Position = UDim2.fromOffset(pan.X, pan.Y)
		for _, l in roadLabels do
			l.Visible = zoom >= 2
		end
		if not cullQueued then
			cullQueued = true
			task.defer(function()
				cullQueued = false
				cullPins()
			end)
		end
	end

	local function setZoom(z: number, focus: Vector2?)
		local cs = canvasSize()
		local f = focus or Vector2.new(cs.X / 2, cs.Y / 2)
		local old = zoom
		zoom = math.clamp(z, 1, 8)
		local k = zoom / old
		pan = f - (f - pan) * k
		applyView()
	end

	local function centreOn(pos: Vector3)
		local cs = canvasSize()
		local ws = baseSize() * zoom
		local u, v = norm(pos.X, pos.Z)
		pan = Vector2.new(cs.X / 2 - u * ws.X, cs.Y / 2 - v * ws.Y)
		applyView()
	end

	local function say(text: string, col: Color3?)
		statusLabel.Text = text
		statusLabel.TextColor3 = col or K.Color.sub
		statusLabel.Visible = text ~= ""
	end

	local function selectPin(name: string?)
		selected = name
		for n, p in pins do
			local big = n == name
			p.disc.Size = if big then UDim2.fromOffset(30, 30) else UDim2.fromOffset(22, 22)
			p.ring.Visible = big
		end
		if not name then
			placeCard.Visible = false
			zoomCol.Visible = true
			applyView()
			return
		end
		local cat = CAT[categoryOf(name)] or CAT.spot
		cardTitle.Text = name
		local g = cardIcon:FindFirstChild("Glyph") :: TextLabel?
		if g then
			g.Text = cat.icon or "📍"
		end
		local grad = cardIcon:FindFirstChildOfClass("UIGradient")
		if grad then
			grad.Color = ColorSequence.new(K.shade(cat.color, -0.08, 0.12), K.shade(cat.color, 0.1, -0.22))
		end
		local root = rootPart()
		local pos = Dest.position(name)
		if root and pos then
			local d = (pos - root.Position).Magnitude
			cardSub.Text = string.format("%s · %s · %s", cat.label, K.meters(d), K.walkTime(d))
		else
			cardSub.Text = cat.label
		end
		placeCard.Visible = true
		zoomCol.Visible = false
		K.pop(placeCard, 0.94)
		applyView()
	end

	local function buildPins()
		local names = {}
		for _, e in Dest.list() do
			table.insert(names, e.name)
		end
		local key = table.concat(names, "\n")
		if key == pinsKey then
			return
		end
		pinsKey = key
		for _, c in pinLayer:GetChildren() do
			c:Destroy()
		end
		table.clear(pins)
		rebuildPlaceSets()
		for _, e in Dest.list() do
			local p = Dest.position(e.name)
			if p then
				local u, v = norm(p.X, p.Z)
				local catId = categoryOf(e.name)
				local cat = CAT[catId] or CAT.spot
				local b = K.make("TextButton", { Name = "Pin", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(u, v), Size = UDim2.fromOffset(44, 44), BackgroundTransparency = 1, Text = "", ZIndex = 4, Visible = false }, pinLayer)
				local ring = K.frame(b, { Name = "Selected", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(40, 40), BackgroundTransparency = 0.75, BackgroundColor3 = cat.color, Visible = false, ZIndex = 4 })
				K.corner(ring, UDim.new(0.5, 0))
				local disc = K.frame(b, { Name = "Disc", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(22, 22), BackgroundTransparency = 0, BackgroundColor3 = cat.color, ZIndex = 5 })
				K.corner(disc, UDim.new(0.5, 0))
				K.stroke(disc, Color3.new(1, 1, 1), 1.5, 0.15)
				K.text(disc, { Name = "Glyph", Size = UDim2.fromScale(1, 1), Text = cat.icon or "•", TextSize = 11, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 })
				pins[e.name] = { button = b, disc = disc, ring = ring, cat = catId, id = e.id, name = e.name, u = u, v = v }
				b.Activated:Connect(function()
					K.feedback("tap")
					selectPin(e.name)
				end)
			end
		end
		applyView()
	end

	-- live markers (5 Hz) ------------------------------------------------------------------------------------
	local function placeMarkers()
		local root = rootPart()
		if root then
			local p = root.Position
			local u, v = norm(p.X, p.Z)
			meDot.Position = UDim2.fromScale(u, v)
			meDot.Visible = true
			local look = root.CFrame.LookVector
			meCone.Rotation = math.deg(math.atan2(look.Z, look.X)) + 90
		else
			meDot.Visible = false
		end
		local t = Tracker.current()
		if t and t.pos then
			local u, v = norm(t.pos.X, t.pos.Z)
			waypointRing.Position = UDim2.fromScale(u, v)
			waypointRing.Visible = true
		else
			waypointRing.Visible = false
		end
		if selected and placeCard.Visible then
			local pos = Dest.position(selected)
			if root and pos then
				local cat = CAT[categoryOf(selected)] or CAT.spot
				local d = (pos - root.Position).Magnitude
				K.setText(cardSub, string.format("%s · %s · %s", cat.label, K.meters(d), K.walkTime(d)))
			end
		end
	end

	---------------------------------------------------------------------------------------------------
	-- Search
	---------------------------------------------------------------------------------------------------
	local function renderResults(q: string)
		AppKit.clear(results)
		local query = string.lower(q or "")
		local root = rootPart()
		local list = {}
		for name, p in pins do
			if query == "" or string.find(string.lower(name), query, 1, true) then
				local pos = Dest.position(name)
				table.insert(list, { name = name, cat = p.cat, d = if root and pos then (pos - root.Position).Magnitude else math.huge })
			end
		end
		table.sort(list, function(a, b)
			return a.d < b.d
		end)
		for i, it in list do
			if i > 20 then
				break
			end
			local cat = CAT[it.cat] or CAT.spot
			K.ListRow(results, {
				name = "Result" .. i,
				icon = cat.icon or "📍",
				iconColor = cat.color,
				round = true,
				title = it.name,
				subtitle = cat.label .. (if it.d < math.huge then " · " .. K.meters(it.d) else ""),
				height = 52,
				order = i,
				grouped = true,
				onClick = function()
					app.closeSearch()
					local pos = Dest.position(it.name)
					if pos then
						setZoom(math.max(zoom, 3))
						centreOn(pos)
					end
					selectPin(it.name)
				end,
			})
		end
		if #list == 0 then
			K.EmptyState(results, { order = 1, compact = true, icon = "🔎", title = "검색 결과가 없어요", body = "다른 이름으로 찾아보세요" })
		end
	end

	function app.openSearch()
		searchOpen = true
		searchWrap.Visible = true
		chipsBar.Visible = tall
		results.Visible = true
		canvas.Visible = false
		renderResults(search.get())
		pcall(function()
			search.box:CaptureFocus()
		end)
	end

	function app.closeSearch()
		searchOpen = false
		search.release()
		searchWrap.Visible = tall
		chipsBar.Visible = true
		results.Visible = false
		canvas.Visible = true
	end

	---------------------------------------------------------------------------------------------------
	-- Build
	---------------------------------------------------------------------------------------------------
	local function layout()
		local L = ctx.phone.layout()
		tall = L.screenH >= 420
		local y = L.headerH
		searchWrap.Position = UDim2.fromOffset(12, y + 2)
		searchWrap.Visible = tall or searchOpen
		if tall then
			y += 50
		end
		chipsBar.Position = UDim2.fromOffset(0, if searchOpen and not tall then y + 50 else y)
		local top = y + 46
		if searchOpen and not tall then
			results.Position = UDim2.fromOffset(0, L.headerH + 50)
			results.Size = UDim2.new(1, 0, 1, -(L.headerH + 50))
		else
			results.Position = UDim2.fromOffset(0, top)
			results.Size = UDim2.new(1, 0, 1, -top)
		end
		canvasTop = top
		canvas.Position = UDim2.fromOffset(8, top)
		canvas.Size = UDim2.new(1, -16, 1, -(top + 8))
		if header.right then
			header.right.Visible = not tall
		end
	end

	function app.build(b: Frame)
		body = b
		local L = ctx.phone.layout()
		header = ctx.phone.header(body, "지도", {
			right = "🔍",
			onRight = function()
				if searchOpen then
					app.closeSearch()
				else
					app.openSearch()
				end
			end,
		})

		searchWrap = K.frame(body, { Name = "SearchWrap", Size = UDim2.new(1, -24, 0, 44), ZIndex = 5 })
		search = K.SearchBar(searchWrap, {
			placeholder = "장소 검색 (예: 스타벅스, 볼링)",
			onChange = function(q: string)
				if visible and searchOpen then
					renderResults(q)
				end
			end,
		})
		search.frame.Size = UDim2.fromScale(1, 1)
		search.box.Focused:Connect(function()
			if not searchOpen then
				app.openSearch()
			end
		end)

		chipsBar = K.make("ScrollingFrame", { Name = "Filters", Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, BorderSizePixel = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollingDirection = Enum.ScrollingDirection.X, ScrollBarThickness = 0 }, body)
		K.list(chipsBar, true, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
		K.pad(chipsBar, 12, 12, 0, 0)
		for i, c in CATS do
			chipApis[c.id] = K.Chip(chipsBar, {
				name = "Chip_" .. c.id,
				text = c.label,
				icon = c.icon,
				color = c.color,
				selected = c.id == "all",
				order = i,
				onClick = function()
					filter = c.id
					for id, api in chipApis do
						api.set(id == filter)
					end
					if selected and filter ~= "all" and pins[selected] and pins[selected].cat ~= filter then
						selectPin(nil)
					end
					applyView()
				end,
			})
		end

		results = K.make("ScrollingFrame", { Name = "Results", BackgroundTransparency = 1, BorderSizePixel = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 3, Visible = false, ZIndex = 6 }, body)
		K.list(results, false, 0)
		K.pad(results, 12, 12, 4, 12)

		canvas = K.frame(body, { Name = "MapCanvas", BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(22, 58, 100), ClipsDescendants = true, Active = true })
		K.corner(canvas, K.Radius.md)
		K.stroke(canvas, nil, 1, 0.86)
		world = K.frame(canvas, { Name = "0World", Size = UDim2.fromOffset(300, 150) })
		base = K.frame(world, { Name = "0Base", Size = UDim2.fromScale(1, 1), ZIndex = 1 })
		pinLayer = K.frame(world, { Name = "Pins", Size = UDim2.fromScale(1, 1), ZIndex = 4 })
		waypointRing = K.frame(world, { Name = "Waypoint", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(34, 34), BackgroundTransparency = 1, Visible = false, ZIndex = 6 })
		K.corner(waypointRing, UDim.new(0.5, 0))
		K.stroke(waypointRing, K.Color.gold, 3, 0)
		meDot = K.frame(world, { Name = "Me", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1, Visible = false, ZIndex = 7 })
		mePulse = K.frame(meDot, { Name = "Pulse", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 0.5, BackgroundColor3 = K.Color.cyan, ZIndex = 7 })
		K.corner(mePulse, UDim.new(0.5, 0))
		meCone = K.frame(meDot, { Name = "Cone", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(42, 42), ZIndex = 7 })
		K.text(meCone, { Name = "Arrow", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, -0.05), Size = UDim2.fromOffset(20, 16), Text = "▲", TextColor3 = K.Color.cyan, TextSize = 14, Font = K.Font.heavy, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 7 })
		local core = K.frame(meDot, { Name = "Core", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0, BackgroundColor3 = K.Color.cyan, ZIndex = 8 })
		K.corner(core, UDim.new(0.5, 0))
		K.stroke(core, Color3.new(1, 1, 1), 2.5, 0)

		-- zoom buttons + recentre (right edge of the map)
		zoomCol = K.frame(canvas, { Name = "Zoom", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6), Size = UDim2.fromOffset(44, 144), ZIndex = 10 })
		K.list(zoomCol, false, 6)
		for i, def in { { "+", 1.6 }, { "−", 1 / 1.6 }, { "◎", 0 } } do
			local zb = K.Button(zoomCol, { name = "Zoom" .. i, style = "glass", icon = def[1], order = i, zIndex = 10, textSize = 18, size = UDim2.fromOffset(44, 44) })
			K.corner(zb, UDim.new(0.5, 0))
			zb.Activated:Connect(function()
				if def[2] == 0 then
					local root = rootPart()
					if zoom < 3 then
						setZoom(3)
					end
					if root then
						centreOn(root.Position)
					end
				else
					setZoom(zoom * def[2])
				end
			end)
		end

		statusLabel = K.text(canvas, { Name = "Status", Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -66, 0, 26), BackgroundTransparency = K.GLASS_T, BackgroundColor3 = K.Color.glass, Text = "", TextSize = K.Type.caption, Font = K.Font.bold, Visible = false, ZIndex = 10, TextTruncate = Enum.TextTruncate.AtEnd })
		K.corner(statusLabel, 10)
		K.pad(statusLabel, 10, 10, 0, 0)

		loading = K.frame(canvas, { Name = "Loading", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0, BackgroundColor3 = K.Color.card, ZIndex = 12 })
		local ld = K.EmptyState(loading, { compact = true, icon = "🗺️", title = "지도를 그리는 중…", body = "광안리 전체를 불러오고 있어요" })
		ld.frame.Size = UDim2.fromScale(1, 1)
		for _, d in loading:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = 13
			end
		end

		-- place card (bottom of the map)
		placeCard = K.Panel(canvas, { Name = "PlaceCard", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6), Size = UDim2.new(1, -12, 0, 96), Visible = false, ZIndex = 11, Radius = 14, BackgroundTransparency = 0.04 })
		cardIcon = K.iconTile(placeCard, 32, "📍", K.Color.cyan, true)
		cardIcon.Position = UDim2.fromOffset(10, 8)
		cardIcon.ZIndex = 12
		for _, d in cardIcon:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = 12
			end
		end
		cardTitle = K.text(placeCard, { Name = "Title", Position = UDim2.fromOffset(50, 7), Size = UDim2.new(1, -100, 0, 18), Text = "", Font = K.Font.bold, TextSize = K.Type.bodySm, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 12 })
		cardSub = K.text(placeCard, { Name = "Sub", Position = UDim2.fromOffset(50, 25), Size = UDim2.new(1, -100, 0, 15), Text = "", TextColor3 = K.Color.sub, TextSize = K.Type.micro, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 12 })
		local x = K.Button(placeCard, { name = "CloseCard", style = "ghost", icon = "✕", anchor = Vector2.new(1, 0), position = UDim2.new(1, -2, 0, 0), size = UDim2.fromOffset(44, 44), zIndex = 12, textSize = 14 })
		x.TextColor3 = K.Color.sub
		x.Activated:Connect(function()
			selectPin(nil)
		end)
		K.Button(placeCard, {
			name = "Guide",
			text = "🧭 길안내",
			style = "primary",
			position = UDim2.new(0, 8, 1, -50),
			size = UDim2.new(0.5, -12, 0, 44),
			zIndex = 12,
			textSize = K.Type.caption + 1,
			onClick = function()
				local name = selected
				if not name then
					return
				end
				Tracker.setWaypoint(name)
				Net.send("setWaypoint", { destination = name })
				K.feedback("success")
				say("🧭 " .. K.ro(name) .. " 길안내 시작", K.Color.gold)
			end,
		})
		local travel = K.Button(placeCard, {
			name = "Travel",
			text = "⚡ 빠른 이동",
			style = "secondary",
			anchor = Vector2.new(1, 0),
			position = UDim2.new(1, -8, 1, -50),
			size = UDim2.new(0.5, -12, 0, 44),
			zIndex = 12,
			textSize = K.Type.caption + 1,
			onClick = function()
				local name = selected
				if not name or os.clock() < pendingUntil then
					return
				end
				local ok, err = Dest.travel((pins[name] and pins[name].id) or Dest.idFor(name))
				if not ok then
					say(err or "이동할 수 없어요", K.Color.orange)
					return
				end
				pendingUntil = os.clock() + 11
				say(K.ro(name) .. " 이동 중…", K.Color.gold)
			end,
		})
		local _ = travel

		-- drag to pan
		local dragging: InputObject? = nil
		local dragStart = Vector2.zero
		local panStart = Vector2.zero
		canvas.InputBegan:Connect(function(input: InputObject)
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
				if dragging == nil then
					dragging = input
					dragStart = Vector2.new(input.Position.X, input.Position.Y)
					panStart = pan
				end
			elseif t == Enum.UserInputType.MouseWheel then
				local ap = canvas.AbsolutePosition
				setZoom(zoom * (if input.Position.Z > 0 then 1.25 else 0.8), Vector2.new(input.Position.X - ap.X, input.Position.Y - ap.Y))
			end
		end)
		UserInputService.InputChanged:Connect(function(input: InputObject)
			if not visible or not dragging then
				return
			end
			local t = input.UserInputType
			if (t == Enum.UserInputType.MouseMovement and dragging.UserInputType == Enum.UserInputType.MouseButton1) or input == dragging then
				local p = Vector2.new(input.Position.X, input.Position.Y)
				pan = panStart + (p - dragStart)
				applyView()
			end
		end)
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if dragging and (input == dragging or input.UserInputType == Enum.UserInputType.MouseButton1) then
				dragging = nil
			end
		end)
		local pinchStart = 1
		UserInputService.TouchPinch:Connect(function(positions: { Vector2 }, scale: number, _velocity: number, state: Enum.UserInputState)
			if not visible then
				return
			end
			if state == Enum.UserInputState.Begin then
				pinchStart = zoom
				dragging = nil
			elseif state == Enum.UserInputState.Change then
				local ap = canvas.AbsolutePosition
				local f: Vector2? = nil
				if type(positions) == "table" and positions[1] and positions[2] then
					local m = (positions[1] + positions[2]) / 2
					f = Vector2.new(m.X - ap.X, m.Y - ap.Y)
				end
				setZoom(pinchStart * scale, f)
			end
		end)

		Dest.onResult(function(ok: boolean, message: string)
			pendingUntil = 0
			if ok then
				say("도착 · " .. message, K.Color.green)
				K.feedback("success")
				if visible then
					task.delay(0.6, function()
						if visible then
							ctx.phone.close()
						end
					end)
				end
			else
				say(if message ~= "" then message else "이동할 수 없어요", K.Color.orange)
			end
			task.delay(4, function()
				if pendingUntil == 0 then
					say("")
				end
			end)
		end)
		Dest.onChanged(function()
			pinsKey = ""
			if visible and staticBuilt then
				buildPins()
			end
		end)
		canvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			if visible and staticBuilt then
				applyView()
			end
		end)
		ctx.phone.onLayout(function()
			layout()
		end)
		layout()
	end

	local function startLoop()
		loopSerial += 1
		local mine = loopSerial
		task.spawn(function()
			local pulseAt = 0
			while visible and loopSerial == mine do
				task.wait(0.2)
				if visible and loopSerial == mine and staticBuilt then
					local ok, err = pcall(placeMarkers)
					if not ok then
						warn("[GwangalliPhone] map: " .. tostring(err))
						break
					end
					if os.clock() - pulseAt > 1.6 and not K.reduced() then
						pulseAt = os.clock()
						mePulse.Size = UDim2.fromOffset(16, 16)
						mePulse.BackgroundTransparency = 0.45
						K.tween(mePulse, 1.4, { Size = UDim2.fromOffset(46, 46), BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
					end
				end
			end
		end)
	end

	local function afterBuilt(focus: string?)
		loading.Visible = false
		buildPins()
		if not firstShown then
			firstShown = true
			local root = rootPart()
			if root and not focus then
				zoom = 3
				centreOn(root.Position)
			end
		end
		if focus and Dest.position(focus) then
			setZoom(math.max(zoom, 3))
			centreOn(Dest.position(focus) :: Vector3)
			selectPin(focus)
		end
		applyView()
		placeMarkers()
	end

	function app.show(args: any)
		visible = true
		layout()
		local focus = if type(args) == "table" and type(args.focus) == "string" then Dest.resolve(args.focus) else nil
		if not staticBuilt then
			loading.Visible = true
			if not building then
				drawStatic(function()
					if visible then
						afterBuilt(focus)
					end
				end)
			end
		else
			afterBuilt(focus)
		end
		startLoop()
	end

	function app.hide()
		visible = false
		loopSerial += 1
		if searchOpen then
			app.closeSearch()
		end
	end

	return app
end
