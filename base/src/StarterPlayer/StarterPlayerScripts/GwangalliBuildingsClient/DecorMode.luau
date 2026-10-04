-- DecorMode: 인테리어 모드 in your own home.
--   * a dollhouse camera above the unit (everything above the ceiling is hidden on this client only);
--   * 가구 tab: catalog by category -> a ghost follows your finger / mouse on the floor (grid snap),
--     ⟲ rotates by Config.ROTATE_STEP, ✓ places (buy, or take from 창고);
--   * tap a placed piece to select it: 이동 / 회전 / 색상 / 창고로 / 판매 (50 %);
--   * 벽지 · 바닥 · 조명 tabs: pick a room, then a finish (the server charges and repaints);
--   * the server validates every action (Decor service); the client only previews.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = require(ReplicatedStorage:WaitForChild("GwangalliBuildingsShared"))
local Furniture = Shared.Furniture
local Util = Shared.Util
local UI = require(script.Parent:WaitForChild("UI"))
local Net = require(script.Parent:WaitForChild("Net"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))

local DecorMode = {}

local player = Players.LocalPlayer
local C = UI.C

local snap: any = nil -- decor.begin snapshot
local hidden: { [BasePart]: number } = {}
local camSaved: any = nil
local ghost: Model? = nil
local ghostState: any = nil -- { itemId, x, z, yaw, cw, uid? (move) }
local conns: { RBXScriptConnection } = {}
local bar: Frame? = nil
local selected: Model? = nil
local selBox: SelectionBox? = nil
local tab = "furniture"
local cat = "living"

local function frame(): CFrame
	return snap.frame
end

local function toLocal(world: Vector3): Vector3
	return frame():PointToObjectSpace(world)
end

-------------------------------------------------------------------------------------------------
-- camera + hiding the floors above
-------------------------------------------------------------------------------------------------
local function hideAbove()
	local f = frame()
	local w, d, h = snap.w, snap.d, snap.h
	local center = f * CFrame.new(w / 2, h - 0.6 + 120, d / 2)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local char = player.Character
	params.FilterDescendantsInstances = if char then { char } else {}
	local ok, parts = pcall(function()
		return workspace:GetPartBoundsInBox(center, Vector3.new(w + 6, 240, d + 6), params)
	end)
	if not ok then
		return
	end
	for _, p in parts do
		if p:IsA("BasePart") and hidden[p] == nil then
			-- only parts that really are above the room's ceiling height
			local top = toLocal(p.Position)
			if top.Y - p.Size.Y / 2 >= h - 1.2 or p.Name == "Ceiling" then
				hidden[p] = p.Transparency
				p.Transparency = 1
			end
		end
	end
end

local function restoreHidden()
	for p, t in hidden do
		if p.Parent then
			p.Transparency = t
		end
	end
	hidden = {}
end

local function setCamera()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	camSaved = { type = cam.CameraType, cf = cam.CFrame, fov = cam.FieldOfView }
	cam.CameraType = Enum.CameraType.Scriptable
	local f = frame()
	local span = math.max(snap.w, snap.d * 1.6)
	local dist = math.clamp(span * 0.95, 22, 110)
	local center = (f * CFrame.new(snap.w / 2, 0, snap.d / 2)).Position
	-- look from the entrance side, steep (dollhouse)
	local eye = (f * CFrame.new(snap.w / 2, dist, snap.d / 2 - dist * 0.42)).Position
	cam.CFrame = CFrame.lookAt(eye, center)
end

local function restoreCamera()
	local cam = workspace.CurrentCamera
	if cam and camSaved then
		cam.CameraType = camSaved.type
	end
	camSaved = nil
end

-------------------------------------------------------------------------------------------------
-- ghost preview
-------------------------------------------------------------------------------------------------
local function clearGhost()
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
	ghostState = nil
end

local function insideUnit(itemId: string, x: number, z: number, yaw: number): boolean
	local fw, fd = Furniture.footprint(itemId, yaw)
	return x - fw / 2 >= 0.3 and x + fw / 2 <= snap.w - 0.3 and z - fd / 2 >= 0.3 and z + fd / 2 <= snap.d - 0.3
end

local function drawGhost()
	if not ghostState then
		return
	end
	local s = ghostState
	local cf = frame() * CFrame.new(s.x, 0, s.z) * CFrame.Angles(0, math.rad(s.yaw), 0)
	if not ghost or ghost.Name ~= "Ghost_" .. s.itemId .. "_" .. s.cw then
		if ghost then
			ghost:Destroy()
		end
		local m = Furniture.build(s.itemId, nil, cf, s.cw, { Ghost = true })
		if not m then
			return
		end
		m.Name = "Ghost_" .. s.itemId .. "_" .. s.cw
		-- a preview is not a real fixture: no tags (no prompts / sounds / screens pick it up)
		for _, inst in { m :: Instance, table.unpack(m:GetDescendants()) } do
			for _, t in CollectionService:GetTags(inst) do
				CollectionService:RemoveTag(inst, t)
			end
		end
		for _, p in m:GetDescendants() do
			if p:IsA("BasePart") then
				p.CanCollide = false
				p.CanQuery = false
				p.CanTouch = false
				if p.Transparency < 1 then
					p.Transparency = math.max(p.Transparency, 0.35)
				end
			elseif p:IsA("ProximityPrompt") or p:IsA("Light") or p:IsA("Attachment") and p:GetAttribute("SoundKey") then
				p:Destroy()
			end
		end
		m.Parent = workspace
		ghost = m
	end
	local g = ghost :: Model
	g:PivotTo(cf)
	local ok = insideUnit(s.itemId, s.x, s.z, s.yaw)
	local hl = g:FindFirstChild("GhostBox") :: SelectionBox?
	if not hl then
		local box = Instance.new("SelectionBox")
		box.Name = "GhostBox"
		box.LineThickness = 0.06
		box.Adornee = g
		box.Parent = g
		hl = box
	end
	if hl then
		hl.Color3 = if ok then C.ok else C.warn
	end
end

local function grid(v: number): number
	return Util.round(v, snap.grid or 0.5)
end

-- screen point -> unit-local floor point
local function floorPoint(pos: Vector2): (number?, number?)
	local cam = workspace.CurrentCamera
	if not cam then
		return nil, nil
	end
	local ray = cam:ViewportPointToRay(pos.X, pos.Y)
	local f = frame()
	local o = f:PointToObjectSpace(ray.Origin)
	local dir = f:VectorToObjectSpace(ray.Direction)
	if math.abs(dir.Y) < 1e-4 then
		return nil, nil
	end
	local t = -o.Y / dir.Y
	if t < 0 then
		return nil, nil
	end
	local hit = o + dir * t
	return hit.X, hit.Z
end

local function overGui(pos: Vector2): boolean
	local root = UI.root()
	if not root then
		return false
	end
	local ok, objs = pcall(function()
		return player:WaitForChild("PlayerGui"):GetGuiObjectsAtPosition(pos.X, pos.Y)
	end)
	if not ok then
		return false
	end
	for _, o in objs do
		if o:IsDescendantOf(root) and o.Visible and (o:IsA("GuiButton") or (o:IsA("Frame") and o.BackgroundTransparency < 0.9)) then
			return true
		end
	end
	return false
end

-------------------------------------------------------------------------------------------------
-- selection of placed pieces
-------------------------------------------------------------------------------------------------
local openSelected: (Model) -> ()
local openCatalog: () -> ()

local function clearSelection()
	if selBox then
		selBox:Destroy()
		selBox = nil
	end
	selected = nil
end

local function pick(pos: Vector2): Model?
	local cam = workspace.CurrentCamera
	if not cam then
		return nil
	end
	local ray = cam:ViewportPointToRay(pos.X, pos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ex = {}
	for p in hidden do
		table.insert(ex, p)
	end
	if ghost then
		table.insert(ex, ghost)
	end
	if player.Character then
		table.insert(ex, player.Character)
	end
	params.FilterDescendantsInstances = ex
	local res = workspace:Raycast(ray.Origin, ray.Direction * 400, params)
	local inst = res and res.Instance
	while inst and inst ~= workspace do
		if inst:IsA("Model") and inst:GetAttribute("Uid") and inst:GetAttribute("UnitId") == snap.unitId then
			return inst
		end
		inst = inst.Parent
	end
	return nil
end

-------------------------------------------------------------------------------------------------
-- control bar (place / move confirmation)
-------------------------------------------------------------------------------------------------
local function clearBar()
	if bar then
		bar:Destroy()
		bar = nil
	end
end

local function placeBar()
	clearBar()
	local root = UI.root()
	local f = UI.frame(root, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.new(0, 420, 0, 60),
		BackgroundColor3 = C.bg,
		BackgroundTransparency = 0.05,
		ZIndex = 25,
	})
	UI.corner(f, 16)
	UI.pad(f, 8, 8, 6, 6)
	UI.list(f, 8, true, "center")
	local s = ghostState
	local def = s and Furniture.ITEMS[s.itemId]
	UI.label(f, (if s and s.uid then "이동: " else "배치: ") .. (if def then def.name else ""), { size = 13, bold = true, sizeU = UDim2.new(0, 120, 1, 0) })
	UI.button(f, "⟲ 회전", function()
		if ghostState then
			ghostState.yaw = (ghostState.yaw + (snap.rotate or 45)) % 360
			drawGhost()
		end
	end, { style = "ghost", size = UDim2.new(0, 80, 1, 0), textSize = 14 })
	UI.button(f, "✓ 확인", function()
		local g = ghostState
		if not g then
			return
		end
		local res
		if g.uid then
			res = Net.call("decor.move", { uid = g.uid, x = g.x, z = g.z, yaw = g.yaw, cw = g.cw })
		else
			res = Net.call("decor.place", { itemId = g.itemId, x = g.x, z = g.z, yaw = g.yaw, cw = g.cw })
		end
		if res.ok then
			Sfx.ui("success")
			if res.storage then
				snap.storage = res.storage
			end
			if res.balance then
				snap.balance = res.balance
			end
			if g.uid then
				clearGhost()
				clearBar()
			end
			-- placing: keep the ghost to place another one
		else
			Sfx.ui("error")
		end
	end, { style = "ok", size = UDim2.new(0, 80, 1, 0), textSize = 14 })
	UI.button(f, "✕", function()
		clearGhost()
		clearBar()
		openCatalog()
	end, { style = "ghost", size = UDim2.new(0, 48, 1, 0) })
	bar = f
end

local function startGhost(itemId: string, cw: number, uid: string?, x: number?, z: number?, yaw: number?)
	clearSelection()
	UI.closeSheet()
	ghostState = { itemId = itemId, cw = cw, uid = uid, x = x or grid(snap.w / 2), z = z or grid(snap.d / 2), yaw = yaw or 0 }
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
	drawGhost()
	placeBar()
	UI.toast("화면을 눌러 위치를 정하고 ✓ 확인", "info")
end

openSelected = function(m: Model)
	clearSelection()
	selected = m
	local box = Instance.new("SelectionBox")
	box.LineThickness = 0.05
	box.Color3 = C.accent
	box.Adornee = m
	box.Parent = m
	selBox = box
	local itemId = m.Name
	local def = Furniture.ITEMS[itemId]
	local s = UI.sheet({ title = "🛋️ " .. (if def then def.name else itemId), sub = "선택한 가구", h = 250, w = 420, footer = true, kind = "decor", onClose = clearSelection })
	local uid = m:GetAttribute("Uid") :: string
	local pivot = frame():ToObjectSpace(m:GetPivot())
	local _, yawRad = pivot:ToEulerAnglesYXZ()
	local yaw = math.floor(math.deg(yawRad) + 0.5) % 360
	local function getXZ(): (number, number)
		return pivot.X, pivot.Z
	end
	UI.button(s.body, "✥ 이동 / 회전", function()
		local x, z = getXZ()
		startGhost(itemId, tonumber(m:GetAttribute("Colorway")) or 1, uid, x, z, yaw)
	end, { style = "primary" })
	if def and #def.colors > 1 then
		UI.button(s.body, "🎨 색상 바꾸기", function()
			local cw = ((tonumber(m:GetAttribute("Colorway")) or 1) % #def.colors) + 1
			local x, z = getXZ()
			local res = Net.call("decor.move", { uid = uid, x = x, z = z, yaw = yaw, cw = cw })
			if res.ok then
				s.close()
			end
		end, { style = "ghost" })
	end
	UI.button(s.footer, "📦 창고로", function()
		local res = Net.call("decor.remove", { uid = uid })
		if res.ok then
			snap.storage = res.storage or snap.storage
			s.close()
		end
	end, { style = "ghost", size = UDim2.new(0.48, 0, 0, 46) })
	UI.button(s.footer, "💰 판매 (" .. (if def then Util.won(math.floor(def.price * 0.5)) else "") .. ")", function()
		local res = Net.call("decor.remove", { uid = uid, sell = true })
		if res.ok then
			s.close()
		end
	end, { style = "danger", size = UDim2.new(0.48, 0, 0, 46), textSize = 14 })
end

-------------------------------------------------------------------------------------------------
-- catalog / themes / storage sheet
-------------------------------------------------------------------------------------------------
local function themeList(kind: string): { any }
	return if kind == "wall" then snap.wallpaper elseif kind == "floor" then snap.flooring else snap.lighting
end

local function themeSheet(kind: string, room: any?)
	local names = { wall = "벽지", floor = "바닥", light = "조명" }
	if not room then
		local s = UI.sheet({ title = "🎨 " .. names[kind] .. " 바꾸기", sub = "방을 고르세요", h = 380, kind = "decor" })
		for _, rm in snap.rooms do
			local fixed = kind ~= "light" and (rm.kind == "bath" or rm.kind == "veranda" or rm.kind == "utility")
			UI.row(s.body, {
				title = tostring(rm.label or rm.id),
				sub = if fixed then "타일 마감 (변경 불가)" else nil,
				disabled = fixed,
				onClick = function()
					themeSheet(kind, rm)
				end,
			})
		end
		UI.button(s.body, "◀ 돌아가기", openCatalog, { style = "ghost" })
		return
	end
	local s = UI.sheet({ title = "🎨 " .. tostring(room.label or room.id) .. " · " .. names[kind], sub = "보유 " .. Util.won(tonumber(snap.balance) or 0), h = 400, kind = "decor" })
	for _, opt in themeList(kind) do
		local cur = room[kind] == opt.id or (room[kind] == nil and opt.price == 0)
		UI.row(s.body, {
			title = opt.name,
			right = if cur then "사용 중" elseif opt.price > 0 then Util.won(opt.price) else "무료",
			rightColor = if cur then C.ok else C.gold,
			accent = cur,
			onClick = function()
				local res = Net.call("decor.theme", { kind = kind, room = room.id, id = opt.id })
				if res.ok then
					room[kind] = opt.id
					if res.balance then
						snap.balance = res.balance
					end
					Sfx.ui("success")
					themeSheet(kind, room)
				end
			end,
		})
	end
	UI.button(s.body, "◀ 방 목록", function()
		themeSheet(kind, nil)
	end, { style = "ghost" })
end

openCatalog = function()
	if not snap then
		return
	end
	local count = 0
	for _ in snap.items or {} do
		count += 1
	end
	local s = UI.sheet({
		title = "🛋️ 인테리어",
		sub = string.format("보유 %s · 가구는 최대 %d개", Util.won(tonumber(snap.balance) or 0), snap.max or 80),
		h = 430,
		w = 520,
		footer = true,
		kind = "decor",
	})
	local tabs = { "가구", "창고", "벽지", "바닥", "조명" }
	local ids = { "furniture", "storage", "wall", "floor", "light" }
	local sel = table.find(ids, tab) or 1
	UI.tabs(s.body, tabs, sel, function(i)
		tab = ids[i]
		if tab == "wall" or tab == "floor" or tab == "light" then
			themeSheet(tab, nil)
			tab = "furniture"
		else
			openCatalog()
		end
	end)
	if tab == "storage" then
		local any = false
		for id, n in snap.storage or {} do
			local def = Furniture.ITEMS[id]
			if def and n > 0 then
				any = true
				UI.row(s.body, { title = def.name, right = "× " .. n, rightColor = C.accent, onClick = function()
					startGhost(id, 1, nil)
				end })
			end
		end
		if not any then
			UI.label(s.body, "창고가 비어 있어요. 가구를 '창고로' 보내면 여기에 보관돼요", { color = C.sub, size = 14, h = 44 })
		end
	else
		local cats, catIds = {}, {}
		for _, c in snap.categories or Furniture.CATEGORIES do
			if not c.hidden then
				table.insert(cats, c.name)
				table.insert(catIds, c.id)
			end
		end
		UI.tabs(s.body, cats, table.find(catIds, cat) or 1, function(i)
			cat = catIds[i]
			openCatalog()
		end)
		for _, it in snap.catalog or {} do
			if it.cat == cat then
				local stored = snap.storage and snap.storage[it.id] or 0
				UI.row(s.body, {
					title = it.name,
					sub = string.format("%.0f×%.0f 칸%s", it.w, it.d, if stored > 0 then " · 창고 " .. stored .. "개" else ""),
					right = if stored > 0 then "창고에서" else Util.won(it.price),
					rightColor = if stored > 0 then C.accent else C.gold,
					onClick = function()
						startGhost(it.id, 1, nil)
					end,
				})
			end
		end
	end
	UI.button(s.footer, "✅ 꾸미기 끝", function()
		DecorMode.stop()
	end, { style = "ok", size = UDim2.new(0.48, 0, 0, 46) })
	UI.button(s.footer, "닫고 배치 보기", function()
		s.close()
		UI.toast("가구를 눌러 선택 · 아래 '인테리어' 버튼으로 카탈로그", "info")
	end, { style = "ghost", size = UDim2.new(0.48, 0, 0, 46), textSize = 14 })
end

-------------------------------------------------------------------------------------------------
local function onPointer(pos: Vector2, began: boolean)
	if not snap or overGui(pos) then
		return
	end
	if ghostState then
		local x, z = floorPoint(pos)
		if x and z then
			ghostState.x = grid(math.clamp(x :: number, 0, snap.w))
			ghostState.z = grid(math.clamp(z :: number, 0, snap.d))
			drawGhost()
		end
	elseif began then
		local m = pick(pos)
		if m then
			openSelected(m)
		end
	end
end

function DecorMode.active(): boolean
	return snap ~= nil
end

function DecorMode.start()
	if snap then
		openCatalog()
		return
	end
	local res = Net.call("decor.begin", {})
	if not res.ok then
		return
	end
	snap = res
	tab = "furniture"
	setCamera()
	hideAbove()
	local dragging = false
	table.insert(conns, UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			onPointer(Vector2.new(input.Position.X, input.Position.Y), true)
		end
	end))
	table.insert(conns, UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			onPointer(Vector2.new(input.Position.X, input.Position.Y), false)
		end
	end))
	table.insert(conns, UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end))
	-- the floor below the camera can stream furniture in after we hid things: hide again a few times
	task.spawn(function()
		for _ = 1, 6 do
			task.wait(1.5)
			if not snap then
				return
			end
			hideAbove()
		end
	end)
	openCatalog()
end

function DecorMode.stop()
	if not snap then
		return
	end
	Net.request("decor.end", {})
	for _, c in conns do
		c:Disconnect()
	end
	conns = {}
	clearGhost()
	clearBar()
	clearSelection()
	UI.closeSheet("decor")
	restoreHidden()
	restoreCamera()
	snap = nil
	UI.toast("🏠 인테리어 저장 완료", "ok")
end

function DecorMode.init()
	Net.on("decor.state", function(d)
		if snap and d.items then
			snap.items = d.items
		end
	end)
	player.CharacterAdded:Connect(function()
		if snap then
			DecorMode.stop()
		end
	end)
end

return DecorMode
