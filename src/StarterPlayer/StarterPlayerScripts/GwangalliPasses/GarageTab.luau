-- GwangalliPasses/GarageTab (client): the "차고" tab (pass #1 프리미엄 차고).
--   owned:  원격 차고 card (내 차 부르기 anywhere), the four premium cars (3D preview, specs, 15 paints,
--           📍 바로 내 옆으로 / 🛣️ 도로로 / ↩️ 돌려보내기), 🔧 출장 정비 for the Garage cars
--   locked: the pass pitch + the same cars, visible but 🔒 (each button opens the purchase prompt), and the
--           정비소-only rule with a 길찾기 button

local Players = game:GetService("Players")

local GarageTab = {}

local ctx: any
local P: any, K: any, Lines: any, Hub: any, Cars: any
local scroll: ScrollingFrame? = nil
local previews: { any } = {}
local busy = false
local GOLD = Color3.fromRGB(255, 194, 71)

local function owned(): boolean
	return P.has(Players.LocalPlayer, "PremiumGarage")
end

local function clear()
	for _, pv in previews do
		pcall(pv.destroy)
	end
	previews = {}
	local s = scroll
	if s then
		for _, ch in s:GetChildren() do
			if ch:IsA("GuiObject") then
				ch:Destroy()
			end
		end
	end
end

local function toastRes(res: any, icon: string)
	K.toast({ kind = if res.ok then "success" else "warn", icon = icon, title = res.title or res.message or (if res.ok then "OK" else Lines.t("summon_fail")), body = if res.title then res.message else nil })
end

local function summon(key: string, mode: string)
	if busy then
		return
	end
	busy = true
	local res = ctx.Net.request("summon", { car = key, mode = mode })
	busy = false
	toastRes(res, "🏎️")
	if res.ok then
		if typeof(res.car) == "Instance" and ctx.DriveHook then
			ctx.DriveHook.markCar(res.car)
		end
		ctx.Hub.close()
		if ctx.PhoneHook then
			ctx.PhoneHook.closePhone()
		end
	else
		GarageTab.show(nil)
	end
end

local function paintRow(parent: Instance, car: any, current: string, onPick: (string) -> ())
	local row = Instance.new("ScrollingFrame")
	row.Name = "Paints"
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1, 0, 0, 38)
	row.ScrollingDirection = Enum.ScrollingDirection.X
	row.ScrollBarThickness = 0
	row.AutomaticCanvasSize = Enum.AutomaticSize.X
	row.CanvasSize = UDim2.new()
	row.LayoutOrder = 3
	row.Parent = parent
	local l = K.list(row, true, 6)
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	K.pad(row, 2, 2, 0, 0)
	local rings = {}
	for i, p in Cars.PAINTS do
		local b = Instance.new("TextButton")
		b.Name = "Paint_" .. p.id
		b.Text = ""
		b.AutoButtonColor = false
		b.Size = UDim2.fromOffset(30, 30)
		b.BackgroundColor3 = Cars.paintColor(p)
		b.LayoutOrder = i
		b.Parent = row
		K.corner(b, UDim.new(0.5, 0))
		local ring = K.stroke(b, if p.id == current then GOLD else Color3.new(1, 1, 1), if p.id == current then 2.5 else 1, if p.id == current then 0 else 0.7)
		rings[p.id] = ring
		if p.premium then
			K.text(b, { Text = "✦", TextSize = 10, TextColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
		end
		b.Activated:Connect(function()
			for id, r in rings do
				r.Color = if id == p.id then GOLD else Color3.new(1, 1, 1)
				r.Thickness = if id == p.id then 2.5 else 1
				r.Transparency = if id == p.id then 0 else 0.7
			end
			onPick(p.id)
		end)
	end
	return row
end

local function carCard(parent: Instance, view: any, order: number, has: boolean)
	local car = Cars.get(view.key)
	if not car then
		return
	end
	local c = K.Card(parent, { Name = "Car_" .. car.key, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order })
	K.list(c, false, 6)
	K.pad(c, 10, 10, 10, 10)
	local stage = K.frame(c, { Name = "Stage", Size = UDim2.new(1, 0, 0, 118), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(14, 16, 26), LayoutOrder = 1, ClipsDescendants = true })
	K.corner(stage, 12)
	K.gradient(stage, { Color3.fromRGB(34, 30, 56), Color3.fromRGB(10, 12, 20) }, 90)
	local pv = ctx.Preview.mount(stage, car, view.paint or car.paint)
	table.insert(previews, pv)
	if view.out then
		Hub.chip(stage, "● 운행 중", Color3.fromRGB(90, 230, 140), { Position = UDim2.fromOffset(8, 8) })
	end
	if not has then
		Hub.chip(stage, "🔒 패스 전용", GOLD, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8) })
	end
	local info = K.frame(c, { Name = "Info", Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 2 })
	K.text(info, { Text = car.glyph .. "  " .. car.label, Font = K.Font.bold, TextSize = K.Type.body, Size = UDim2.new(1, 0, 0, 20) })
	K.text(info, { Text = string.format("%s · 최고 %dkm/h · %s · %d인승", car.class, view.topKmh or car.spec.topKmh, if (view.drive or car.spec.drive) == "AWD" then "사륜" else "후륜", car.seats), TextSize = K.Type.micro, Font = K.Font.bold, TextColor3 = GOLD, Position = UDim2.fromOffset(0, 21), Size = UDim2.new(1, 0, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd })
	K.text(c, { Text = car.blurb, TextSize = K.Type.micro, TextColor3 = K.Color.sub, TextWrapped = true, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
	paintRow(c, car, view.paint or car.paint, function(id: string)
		pv.setPaint(id)
		if has then
			task.spawn(function()
				local res = ctx.Net.request("paint", { car = car.key, paint = id })
				if not res.ok and res.message then
					K.toast({ kind = "warn", icon = "🎨", title = res.message })
				end
			end)
		end
	end)
	local actions = K.frame(c, { Name = "Actions", Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 4 })
	if not has then
		K.Button(actions, { name = "Locked", text = "🔒 " .. Lines.t("gate_buy") .. "로 열기", style = "gold", size = UDim2.fromScale(1, 1), onClick = function()
			ctx.Store.buy("PremiumGarage")
		end })
	elseif view.out then
		K.Button(actions, { name = "Back", text = Lines.t("summon_back"), style = "danger", size = UDim2.fromScale(1, 1), onClick = function()
			task.spawn(function()
				local res = ctx.Net.request("dismiss")
				toastRes(res, "↩️")
				GarageTab.show(nil)
			end)
		end })
	else
		K.Button(actions, { name = "Here", text = Lines.t("summon_here"), style = "primary", size = UDim2.new(0.6, -4, 1, 0), onClick = function()
			task.spawn(summon, car.key, "here")
		end })
		K.Button(actions, { name = "Road", text = Lines.t("summon_road"), style = "secondary", size = UDim2.new(0.4, -4, 1, 0), position = UDim2.new(0.6, 4, 0, 0), onClick = function()
			task.spawn(summon, car.key, "road")
		end })
	end
end

local function remoteCard(parent: Instance, st: any, order: number, has: boolean)
	local c = K.Card(parent, { Name = "Remote", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order })
	K.list(c, false, 6)
	K.pad(c, 12, 12, 12, 12)
	local at = Players.LocalPlayer:GetAttribute(P.Attr.AtGarage) == true
	local title = if has then Lines.t("gate_owner") elseif st and st.gate == false then "🚗 내 차 부르기" elseif at then Lines.t("gate_open") else Lines.t("gate_banner")
	K.text(c, { Text = title, Font = K.Font.bold, TextSize = K.Type.bodySm, TextWrapped = true, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, TextColor3 = if has then GOLD else K.Color.text })
	if not has then
		K.text(c, { Text = Lines.t("gate_banner_body"), TextSize = K.Type.caption, TextColor3 = K.Color.sub, TextWrapped = true, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
	end
	local row = K.frame(c, { Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 3 })
	local canCall = has or at or (st and st.gate == false)
	K.Button(row, { name = "CallMine", text = (if canCall then "" else "🔒 ") .. "내 차 부르기", icon = "🚗", style = if canCall then "primary" else "secondary", size = UDim2.new(0.5, -4, 1, 0), onClick = function()
		if canCall then
			ctx.Hub.close()
			if ctx.PhoneHook then
				ctx.PhoneHook.closePhone()
			end
			if ctx.DriveHook then
				ctx.DriveHook.openSheet()
			end
		else
			ctx.Store.buy("PremiumGarage")
		end
	end })
	K.Button(row, { name = "Route", text = Lines.t("gate_route"), icon = "🧭", style = "secondary", size = UDim2.new(0.5, -4, 1, 0), position = UDim2.new(0.5, 4, 0, 0), onClick = function()
		if ctx.DriveHook then
			task.spawn(ctx.DriveHook.waypoint)
		end
	end })
end

local function repairRows(parent: Instance, st: any, order: number)
	local mine = (st and st.mine) or {}
	Hub.section(parent, "🔧 " .. Lines.t("garage_mine"), order)
	if #mine == 0 then
		K.text(parent, { Text = Lines.t("repair_none"), TextSize = K.Type.caption, TextColor3 = K.Color.sub, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = order + 1 })
		return
	end
	for i, v in mine do
		local row = K.Card(parent, { Name = "Mine_" .. tostring(v.id), Size = UDim2.new(1, 0, 0, 64), LayoutOrder = order + i })
		local cond = math.clamp(tonumber(v.cond) or 100, 0, 100)
		K.text(row, { Text = tostring(v.glyph or "🚗") .. "  " .. tostring(v.label or "내 차"), Font = K.Font.bold, TextSize = K.Type.bodySm, Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -140, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd })
		K.text(row, { Text = tostring(v.plate or "") .. string.format(" · 상태 %d%%", cond), TextSize = K.Type.micro, TextColor3 = K.Color.sub, Position = UDim2.fromOffset(12, 27), Size = UDim2.new(1, -140, 0, 14), TextTruncate = Enum.TextTruncate.AtEnd })
		local track = K.frame(row, { Position = UDim2.fromOffset(12, 46), Size = UDim2.new(1, -140, 0, 6), BackgroundTransparency = 0, BackgroundColor3 = K.Color.card3 })
		K.corner(track, UDim.new(0.5, 0))
		local fill = K.frame(track, { Size = UDim2.fromScale(cond / 100, 1), BackgroundTransparency = 0, BackgroundColor3 = if cond >= 60 then Color3.fromRGB(90, 220, 140) elseif cond >= 30 then Color3.fromRGB(255, 170, 60) else Color3.fromRGB(240, 80, 90) })
		K.corner(fill, UDim.new(0.5, 0))
		local can = not v.rental and (tonumber(v.repair) or 0) > 0 and cond < 100
		local b = K.Button(row, { name = "Fix", text = if v.rental then "렌트 차" elseif can then P.won(v.repair) else "양호", style = if can then "gold" else "tonal", anchor = Vector2.new(1, 0.5), position = UDim2.new(1, -10, 0.5, 0), size = UDim2.fromOffset(116, 44), onClick = function()
			if not can then
				return
			end
			local host = ctx.Hub.host()
			K.confirm(host, { title = Lines.t("repair_title"), body = Lines.t("repair_confirm", tostring(v.plate or v.label), P.won(v.repair)), icon = "🔧", confirmText = "정비하기", style = "gold", onConfirm = function()
				task.spawn(function()
					local res = ctx.Net.request("repair", { id = v.id })
					toastRes(res, "🔧")
					GarageTab.show(nil)
				end)
			end })
		end })
		local _ = b
	end
end

local function render(st: any)
	clear()
	local s = scroll
	if not s then
		return
	end
	local has = owned()
	local order = 1
	if not has then
		Hub.lockCard(s, "PremiumGarage", order)
		order += 1
	end
	remoteCard(s, st, order, has)
	order += 1
	if st and st.ready == false then
		K.text(s, { Text = Lines.t("feature_off"), TextColor3 = K.Color.sub, TextSize = K.Type.caption, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = order })
		order += 1
	end
	Hub.section(s, "✦ " .. Lines.t("garage_premium"), order)
	order += 1
	local views = (st and st.cars) or {}
	if #views == 0 then
		for _, car in Cars.LIST do
			table.insert(views, { key = car.key, paint = car.paint })
		end
	end
	for _, v in views do
		carCard(s, v, order, has)
		order += 1
	end
	if has then
		repairRows(s, st, order + 1)
	end
end

function GarageTab.build(c: any, container: Frame)
	ctx = c
	P, K, Lines, Hub = c.P, c.K, c.P.Lines, c.Hub
	Cars = P.mod("Cars")
	scroll = Hub.scroll(container)
	render(nil)
	c.Net.on("garage", function()
		if c.Hub.isOpen() then
			GarageTab.show(nil)
		end
	end)
end

local inflight = false
function GarageTab.show(_state: any)
	if inflight then
		return
	end
	inflight = true
	local st = ctx.Net.request("garage")
	inflight = false
	if st.code == "cooldown" or st.code == "rate" then
		return
	end
	render(if st.ok then st else nil)
end

function GarageTab.hide() end

return GarageTab
