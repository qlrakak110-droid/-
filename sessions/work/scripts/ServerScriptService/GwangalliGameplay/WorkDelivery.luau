--!nocheck
-- GwangalliGameplay/WorkDelivery: the DELIVERY station system (광안 딜리버리; jobs delivery_food = 음식 배달,
-- delivery_quick = 퀵 배달, track delivery) of the 알바 simulation. Driven by Work.luau like WorkCafe:
--
--   출근 (사무실 근태 단말기 · 조끼) → 📱 배달 앱 (어디서나: 콜 2~3개, 거리 · 단가 · 제한 시간 · 크기)
--   → 수락 → 음식: 식당으로 이동 (웨이포인트) → 조리 대기 → 포장 (용기 → 뚜껑 → 봉투 → 영수증 → 봉인,
--     순서가 틀리면 실수) / 퀵: 사무실 선반 (물건 확인 → 서명 → 포장)
--   → 배달지로 이동 (도보 · 자전거 · 오토바이 · 차, 좌석으로 자동 감지) → 건물 입구의 수령인 NPC에게
--     전달 (고객 부재: 전화 → 문 앞 → 사진) → 정산 (거리 · 시간 · 날씨 · 크기 · 음식 상태)
--   * 음식 상태 (0~100): 급정거 · 충돌 · 과속 (C.DELIVERY.conditionSpeedLimit)이 깎고, 비 오는 날은 작은
--     충격에도 흔들림. 지각은 지급액을 줄이지만 0원이 되지는 않음 (lateMinFactor).
--   * 랜덤: 주소 변경 (이동 중, +시간 +요금) · 고객 부재 · 비 오는 날 할증 · 단체 주문 (Lv3, 여러 곳)
--     · 프리미엄 주문 (Lv4, 차량 필수 · 1.6배) · 야간 할증 (Lv5) · 팁
--   * 마감: 장비 반납 · 배달 일지 보고 (사무실 배차 데스크)
-- No driving code: the existing cars / walking are used as they are. Server truth: the drop / pick-up
-- stations have an owner (only that courier sees and uses them) and the usual distance check.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local DV = {}
DV.kind = "delivery"
DV.noTestCustomers = true

local C: any
local WS: any
local Props: any
local Orders: any
local W: any
local Lines: any = nil
local Looks: any = nil
local rng = Random.new()
local orderSerial = 0

local function rand(n: number): number
	return rng:NextInteger(1, math.max(1, n))
end

function DV.init(cfg: any, ws: any, props: any, orders: any, work: any)
	C = cfg
	WS = ws
	Props = props
	Orders = orders
	W = work
	local lm = ReplicatedStorage:FindFirstChild("GwangalliWorkLines")
	if lm then
		local ok, res = pcall(require, lm)
		if ok then
			Lines = res
		end
	end
	local m = ReplicatedStorage:FindFirstChild("GwangalliNPCLooks")
	if m then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" and type(res.build) == "function" then
			Looks = res
		end
	end
end

local OFFICE = "광안 딜리버리"
local BAD_DEST = { "해수욕장", "바다", "해변", "대교", "상판", "수변공원", "요트", "SUP", "레포츠", OFFICE }

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function raining(): boolean
	return ReplicatedStorage:GetAttribute("GwWeather") == "rain"
end

local function night(): boolean
	local ok, t = pcall(function()
		return game:GetService("Lighting").ClockTime
	end)
	return ok and (t >= 22 or t < 5)
end

local function groundUnder(pos: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	local npc = workspace:FindFirstChild("GwangalliNPCs")
	if npc then
		table.insert(ignore, npc)
	end
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	local ok, hit = pcall(function()
		return workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -20, 0), params)
	end)
	if ok and hit then
		return hit.Position
	end
	return pos - Vector3.new(0, 0.5, 0)
end

-- every usable Destination { name, part }
local function destinations(): { any }
	local out = {}
	local seen = {}
	for _, p in CollectionService:GetTagged("Destination") do
		if p:IsA("BasePart") and p:IsDescendantOf(workspace) then
			local name = p:GetAttribute("DisplayName")
			if type(name) ~= "string" or name == "" then
				name = p.Name
			end
			local bad = p.Position.Y > 15
			for _, w in BAD_DEST do
				if string.find(name, w, 1, true) then
					bad = true
				end
			end
			if not bad and not seen[name] then
				seen[name] = true
				table.insert(out, { name = name, part = p })
			end
		end
	end
	table.sort(out, function(a, b)
		return a.name < b.name
	end)
	return out
end

local function anchor(id: string): BasePart?
	for _, inst in CollectionService:GetTagged("GwJobStation") do
		if inst:IsA("BasePart") and inst:GetAttribute("Job") == "delivery" and inst:GetAttribute("Station") == id then
			return inst
		end
	end
	return nil
end

-------------------------------------------------------------------------------------------------
-- Build
-------------------------------------------------------------------------------------------------
function DV.build(store: any)
	store.stationList = {}
	store.close = {}
	store.recipients = {}
	local quick = store.job.mode == "quick"
	local dispatch = anchor("dispatch")
	local shelf = anchor("shelf")
	local base = if dispatch then dispatch.Position - Vector3.new(0, 0.5, 0) else store.cf.Position
	local rot = store.cf - store.cf.Position
	-- two kiosks side by side (food / quick), at the dispatch desk
	local clockPos = base + rot:VectorToWorldSpace(Vector3.new(if quick then 3.5 else -3.5, 0, 1.5))
	table.insert(store.stationList, { id = "timeclock", label = "근태 단말기", pos = clockPos })
	table.insert(store.stationList, { id = "dispatch", label = "배차 데스크", pos = base, reach = 8 })
	if quick then
		table.insert(store.stationList, { id = "shelf", label = "퀵 물건 선반", pos = if shelf then shelf.Position - Vector3.new(0, 0.5, 0) else base + rot:VectorToWorldSpace(Vector3.new(-6, 0, -12)), reach = 8 })
	end
	local f = store.folder
	local stand = Props.part(f, "DvTimeClockStand", Vector3.new(0.3, 3.4, 0.3), CFrame.new(clockPos + Vector3.new(0, 1.7, 0)) * rot, Color3.fromRGB(58, 62, 70), { material = Enum.Material.Metal })
	local head = Props.part(f, "DvTimeClock", Vector3.new(1.2, 0.9, 0.3), CFrame.new(clockPos + Vector3.new(0, 3.8, 0)) * rot, Props.rgb(store.job.uniform.color))
	Props.screen(head, if quick then "퀵\n출근" else "배달\n출근", { face = Enum.NormalId.Front, color = Color3.fromRGB(20, 20, 24) })
	Props.label(stand, if quick then "📦 퀵 기사 출퇴근" else "🛵 배달 기사 출퇴근", { name = "StaffSign", size = UDim2.fromOffset(130, 20), offset = Vector3.new(0, 3.2, 0), maxDistance = 30, bg = Props.rgb(store.job.uniform.color), color = Color3.fromRGB(20, 20, 24) })
end

function DV.activate(store: any)
	store.open = true
	store.close = {}
	for _, id in C.DELIVERY.closeTasks do
		store.close[id] = false
	end
end

local function removeRecipient(store: any, o: any)
	local r = o.recipient
	if not r then
		return
	end
	o.recipient = nil
	if r.model then
		r.model:Destroy()
	end
end

local function clearOrder(store: any, player: Player, sess: any)
	local dv = sess.dv
	local o = dv and dv.order
	if not o then
		return
	end
	removeRecipient(store, o)
	W.removeStation(store, "rest:" .. o.id)
	for i = 1, #o.drops do
		W.removeStation(store, "drop:" .. o.id .. ":" .. i)
	end
	dv.order = nil
	pcall(W.ctx().setWaypoint, player, nil)
end

function DV.deactivate(store: any)
	store.open = false
	for id, item in store.items do
		W.destroyItem(store, item)
	end
end

function DV.releasePlayer(store: any, player: Player, sess: any)
	clearOrder(store, player, sess)
end

function DV.refreshLights(_store: any) end

-------------------------------------------------------------------------------------------------
-- Calls (배달 앱)
-------------------------------------------------------------------------------------------------
local function restaurants(): { any }
	local ctx = W.ctx()
	local out = {}
	for _, r in C.DELIVERY.restaurants do
		local d = ctx.dest(r.dest)
		if d then
			table.insert(out, { def = r, part = d })
		end
	end
	return out
end

local function pickDrops(from: Vector3, n: number, minD: number, maxD: number, exclude: { [string]: boolean }): { any }
	local cands = {}
	for _, d in destinations() do
		if not exclude[d.name] then
			local dist = flat(d.part.Position - from).Magnitude
			if dist >= minD and dist <= maxD then
				table.insert(cands, d)
			end
		end
	end
	if #cands < n then
		for _, d in destinations() do
			if not exclude[d.name] and flat(d.part.Position - from).Magnitude >= 60 and not table.find(cands, d) then
				table.insert(cands, d)
			end
		end
	end
	for i = #cands, 2, -1 do
		local j = rand(i)
		cands[i], cands[j] = cands[j], cands[i]
	end
	local out = {}
	for _, c in cands do
		if #out >= n then
			break
		end
		table.insert(out, c)
		exclude[c.name] = true
	end
	return out
end

local function roomLabel(name: string): string
	local floors = { 1, 2, 3, 5, 7, 10, 12 }
	return string.format("%s %d%02d호", name, floors[rand(#floors)], rand(4))
end

local function makeCall(store: any, sess: any): any?
	local quick = store.job.mode == "quick"
	local lv = sess.level or 1
	local D = C.DELIVERY
	local officePart = W.ctx().dest(OFFICE)
	local office = if officePart then officePart.Position else store.cf.Position
	orderSerial += 1
	local call: any = { id = string.format("D%04d", orderSerial), kind = if quick then "quick" else "food", drops = {} }
	local from
	if quick then
		call.pickupName = OFFICE
		call.pickupPos = office
		call.item = D.quickItems[rand(#D.quickItems)]
		from = office
	else
		local list = restaurants()
		if #list == 0 then
			return nil
		end
		local r = list[rand(#list)]
		call.pickupName = r.def.dest
		call.restaurant = r.def.name
		call.pickupPos = groundUnder(r.part.Position)
		call.soup = r.def.soup
		call.fragile = r.def.fragile
		call.item = r.def.menu[rand(#r.def.menu)]
		from = r.part.Position
	end
	-- 단체 주문 (Lv3): 2~3 drops · 프리미엄 (Lv4, food): car only, x1.6
	local n = 1
	if WS.unlocked("delivery", "group", lv) and rng:NextNumber() < 0.22 then
		n = 2 + (if rng:NextNumber() < 0.35 then 1 else 0)
		call.group = true
	end
	if not quick and WS.unlocked("delivery", "premium", lv) and not call.group and rng:NextNumber() < 0.25 then
		call.premium = true
		call.item = D.premiumMenu[rand(#D.premiumMenu)]
	end
	local minD = if quick then D.quick.minDist else D.minDist
	local exclude = { [call.pickupName] = true }
	local drops = pickDrops(from, n, minD, D.maxDist, exclude)
	if #drops == 0 then
		return nil
	end
	local total, limit = 0, 0
	local prev = from
	for i, d in drops do
		local dist = flat(d.part.Position - prev).Magnitude
		local pay, lim = WS.deliveryQuote(call.kind, dist, { premium = call.premium, size = if call.group then 1 else rand(2) })
		total += pay
		limit += lim
		table.insert(call.drops, { name = d.name, pos = groundUnder(d.part.Position), room = roomLabel(d.name), dist = math.floor(dist), pay = pay, limit = limit, absent = rng:NextNumber() < D.absentChance })
		prev = d.part.Position
		local _ = i
	end
	call.pay = total
	call.limit = limit
	call.dist = 0
	for _, d in call.drops do
		call.dist += d.dist
	end
	-- the job must fit the rest of the shift (+ half the closing grace): long group runs are trimmed
	if sess.startedAt then
		local left = sess.length - (os.clock() - sess.startedAt) + C.SHIFT.closeGrace * 0.5 - (if quick then 0 else C.DELIVERY.cookSeconds[2])
		while #call.drops > 1 and call.drops[#call.drops].limit > left do
			local d = table.remove(call.drops)
			call.pay -= d.pay
		end
		if call.drops[#call.drops].limit > left and left < 60 then
			return nil
		end
		call.limit = call.drops[#call.drops].limit
		call.group = #call.drops > 1
		call.dist = 0
		for _, d in call.drops do
			call.dist += d.dist
		end
	end
	call.size = if call.group then #call.drops elseif rng:NextNumber() < 0.3 then 2 else 1
	call.addrChange = rng:NextNumber() < D.addressChangeChance
	call.night = WS.unlocked("delivery", "night", lv) and night()
	call.toPickup = math.floor(flat(call.pickupPos - (store.cf.Position)).Magnitude)
	return call
end

local function refreshCalls(store: any, sess: any, force: boolean?)
	local dv = sess.dv
	local now = os.clock()
	if not force and now < (dv.nextRefresh or 0) and #dv.calls > 0 then
		return
	end
	dv.nextRefresh = now + C.DELIVERY.callRefresh
	dv.calls = {}
	for _ = 1, C.DELIVERY.callsOffered do
		local c = makeCall(store, sess)
		if c then
			table.insert(dv.calls, c)
		end
	end
end

local function ensure(sess: any)
	if not sess.dv then
		sess.dv = { calls = {}, nextRefresh = 0, order = nil, mode = "walk", lastV = nil, toastAt = 0 }
	end
	return sess.dv
end

function DV.onClockIn(store: any, _player: Player, sess: any)
	local dv = ensure(sess)
	refreshCalls(store, sess, true)
	local _ = dv
end

-------------------------------------------------------------------------------------------------
-- Recipient NPC (spawned when the courier gets close)
-------------------------------------------------------------------------------------------------
local function bubble(head: BasePart, text: string): TextLabel
	local bb = head:FindFirstChild("WorkRecipientBubble") :: BillboardGui?
	if not bb then
		bb = Instance.new("BillboardGui")
		bb.Name = "WorkRecipientBubble"
		bb.Size = UDim2.fromOffset(220, 56)
		bb.StudsOffset = Vector3.new(0, 2.6, 0)
		bb.MaxDistance = 80
		bb.LightInfluence = 0
		local t = Instance.new("TextLabel")
		t.Name = "Say"
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundColor3 = Color3.new(1, 1, 1)
		t.BackgroundTransparency = 0.05
		t.TextColor3 = Color3.fromRGB(25, 25, 30)
		t.Font = Enum.Font.GothamMedium
		t.TextSize = 14
		t.TextWrapped = true
		t.Parent = bb
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 10)
		c.Parent = t
		bb.Parent = head
	end
	local t = (bb :: BillboardGui):FindFirstChild("Say") :: TextLabel
	t.Text = text
	return t
end

local function spawnRecipient(store: any, player: Player, o: any, drop: any)
	removeRecipient(store, o)
	if drop.absent or not Looks then
		return
	end
	local okS, spec = pcall(Looks.random, 70000 + rand(99999), {})
	if not okS then
		return
	end
	local okB, rig = pcall(Looks.build, spec, { name = "WorkRecipient", anchored = true })
	if not okB or not rig then
		return
	end
	local model = rig.model
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("NpcKind", "shop")
	model:SetAttribute("NpcId", "work_recipient_" .. o.id)
	model:SetAttribute("NpcGround", rig.ground or 3)
	model:SetAttribute("NpcAct", "phone")
	model:SetAttribute("NpcLeg", "")
	model:SetAttribute("NpcEmote", "")
	model:SetAttribute("NpcLook", player.UserId)
	model:SetAttribute("NpcYaw", 0)
	local feet = drop.pos
	local face = flat(store.cf.Position - feet)
	local yaw = if face.Magnitude > 1 then math.deg(math.atan2(-face.Unit.X, -face.Unit.Z)) else 0
	rig.root.CFrame = CFrame.new(feet + Vector3.new(0, rig.ground or 3, 0)) * CFrame.Angles(0, math.rad(yaw), 0)
	model:SetAttribute("NpcYaw", yaw)
	local f = workspace:FindFirstChild("GwangalliNPCs")
	if not f then
		f = Instance.new("Folder")
		f.Name = "GwangalliNPCs"
		f.Parent = workspace
	end
	model.Parent = f
	local head = rig.head or model:FindFirstChild("Head")
	o.recipient = { model = model, head = head }
	if head then
		bubble(head, string.format("📦 %s\n(배달 기다리는 중)", drop.room))
	end
end

local function recipientSay(o: any, text: string)
	local r = o.recipient
	if r and r.head then
		bubble(r.head, text)
	end
end

local function emote(o: any, name: string)
	local r = o.recipient
	if r and r.model then
		r.model:SetAttribute("NpcEmote", string.format("%s#%d#%.1f", name, rand(99999), workspace:GetServerTimeNow()))
	end
end

-------------------------------------------------------------------------------------------------
-- Actions
-------------------------------------------------------------------------------------------------
local function A(id: string, label: string, dur: number, enabled: boolean, reason: string?, icon: string?): any
	return { id = id, label = label, dur = dur, enabled = enabled, reason = reason, icon = icon }
end

local function seated(player: Player): (boolean, string)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	if not seat then
		return false, "walk"
	end
	local m = seat:FindFirstAncestorOfClass("Model")
	local kind = m and m:GetAttribute("VehicleKind")
	return true, WS.travelMode(true, if type(kind) == "string" then kind else nil, m and m.Name or seat.Name)
end

local function steps(o: any): ({ string }, { [string]: string })
	if o.kind == "quick" then
		return C.DELIVERY.quickSteps, C.DELIVERY.quickLabels
	end
	return C.DELIVERY.packSteps, C.DELIVERY.packLabels
end

function DV.globalStations(_store: any, _player: Player, _sess: any): { any }
	return { { id = "app", label = "📱 배달 앱" } }
end

function DV.actions(store: any, player: Player, sess: any, station: string): { any }
	local out = {}
	if not store.open then
		return out
	end
	local dv = ensure(sess)
	local o = dv.order
	if station == "timeclock" then
		table.insert(out, A("clockout", "퇴근하기 (정산)", 0.3, o == nil, if o then "진행 중인 배달을 먼저 끝내요" else nil, "🏁"))
		return out
	end
	if station == "app" then
		if o then
			table.insert(out, A("none", string.format("진행 중: %s", o.item), 0, false, nil, "📱"))
			if not o.pickedAt then
				table.insert(out, A("cancel", "콜 취소 (조리 전만 · 실수 1회)", 0.6, true, nil, "✖️"))
			end
			return out
		end
		if W.phaseOf(store) == "close" then
			table.insert(out, A("none", "마감 시간 · 새 콜 없음 (사무실에서 마감)", 0, false, nil, "📱"))
			return out
		end
		refreshCalls(store, sess, false)
		for _, c in dv.calls do
			local tags = {}
			if c.group then
				table.insert(tags, "단체 " .. #c.drops .. "곳")
			end
			if c.premium then
				table.insert(tags, "프리미엄·차량")
			end
			if raining() then
				table.insert(tags, "우천+20%")
			end
			table.insert(out, A("accept:" .. c.id, string.format("%s %s → %s · %s · %d초%s", if c.kind == "quick" then "📦" else "🍱", c.restaurant or "퀵", c.drops[1].name, WS.won(c.pay), c.limit, if #tags > 0 then " · " .. table.concat(tags, " · ") else ""), 0.4, true, nil, if c.kind == "quick" then "📦" else "🛵"))
		end
		table.insert(out, A("refresh", "콜 새로고침", 0.3, true, nil, "🔄"))
		return out
	end
	if station == "dispatch" then
		if store.close.return_gear == false and W.phaseOf(store) == "close" then
			table.insert(out, A("return_gear", "가방 · 헬멧 반납 (마감)", 1.0, o == nil, if o then "배달 중이에요" else nil, "🎒"))
		end
		if store.close.report == false and W.phaseOf(store) == "close" then
			table.insert(out, A("report", "배달 일지 보고 (마감)", 1.2, o == nil, if o then "배달 중이에요" else nil, "📝"))
		end
		if #out == 0 then
			table.insert(out, A("none", "배차 데스크 · 콜은 📱 배달 앱에서", 0, false, nil, "🗂️"))
		end
		return out
	end
	if station == "shelf" or string.sub(station, 1, 5) == "rest:" then
		if not o or o.pickedAt or (station == "shelf") ~= (o.kind == "quick") or (station ~= "shelf" and station ~= "rest:" .. o.id) then
			table.insert(out, A("none", if station == "shelf" then "퀵 물건 선반" else "포장대", 0, false, nil, "📦"))
			return out
		end
		if o.readyAt and os.clock() < o.readyAt then
			table.insert(out, A("wait", string.format("조리 중… %d초", math.ceil(o.readyAt - os.clock())), 0, false, nil, "🍳"))
			return out
		end
		local list, labels = steps(o)
		for _, id in o.packOrder do
			local done = table.find(o.packDone, id) ~= nil
			if not done then
				table.insert(out, A("pack:" .. id, labels[id] or id, if id == "bag" or id == "sign" then 0.8 else 0.5, true, nil, "📦"))
			end
		end
		local _ = list
		return out
	end
	if string.sub(station, 1, 5) == "drop:" then
		if not o or not o.pickedAt then
			return out
		end
		local drop = o.drops[o.dropIndex]
		if station ~= "drop:" .. o.id .. ":" .. o.dropIndex then
			return out
		end
		local inCar = seated(player)
		local reason = if inCar then "차에서 내려서 전달해요" else nil
		if drop.absent then
			if not drop.called then
				table.insert(out, A("call", "고객에게 전화하기", 1.6, true, nil, "📞"))
			end
			table.insert(out, A("door", "문 앞에 두기", 0.6, reason == nil, reason, "🚪"))
			table.insert(out, A("photo", "사진 찍어 앱으로 전송", 0.8, true, nil, "📸"))
		else
			table.insert(out, A("hand", string.format("%s 전달하기", o.item), 0.8, reason == nil, reason, "🤝"))
		end
		return out
	end
	return out
end

local function totalLeft(o: any): number
	if not o.pickedAt then
		return o.limit
	end
	local drop = o.drops[o.dropIndex]
	return math.floor((drop and drop.limit or o.limit) - (os.clock() - o.pickedAt))
end

local function startDropLeg(store: any, player: Player, o: any)
	local drop = o.drops[o.dropIndex]
	W.addStation(store, { id = "drop:" .. o.id .. ":" .. o.dropIndex, label = "📦 " .. drop.room, pos = drop.pos, owner = player, reach = C.DELIVERY.handoverRadius, reachY = 16 })
	pcall(W.ctx().setWaypoint, player, drop.name)
	o.legFrom = (player.Character and player.Character:FindFirstChild("HumanoidRootPart") and player.Character.HumanoidRootPart.Position) or o.pickupPos
	o.recipientSpawned = false
end

local function finishDrop(store: any, player: Player, sess: any, o: any, how: string)
	local drop = o.drops[o.dropIndex]
	local now = os.clock()
	local elapsed = now - o.pickedAt
	local premiumOk = not o.premium or o.usedCar
	local mistakes = o.mistakes + (if premiumOk then 0 else 1)
	local res = WS.deliveryResult({ pay = drop.pay, limit = drop.limit, elapsed = elapsed, condition = o.condition, rain = raining(), mistakes = mistakes, premium = o.premium })
	local sat = math.floor(res.accuracy * 70 + (if res.onTime then 30 else 30 * res.lateFactor * 0.5))
	W.unit(player, sess, { perf = res.pay, accuracy = res.accuracy, exact = res.exact, fast = res.onTime, group = o.group, satisfaction = sat }, string.format("%s %s · %s · 상태 %d%%%s", if o.kind == "quick" then "📦" else "🛵", drop.room, res.grade, math.floor(o.condition), if res.late > 0 then string.format(" · %d초 지각", math.floor(res.late)) else ""), C.XP.delivery)
	if res.rainBonus > 0 then
		W.extra(player, sess, "rain", "우천 할증", res.rainBonus)
	end
	if o.night then
		W.extra(player, sess, "night", "야간 할증", WS.round100(res.pay * 0.2))
	end
	if not premiumOk then
		W.toast(player, "🚗 프리미엄 주문은 차량으로 배달해야 해요 (정확도 감점)", "warn")
	end
	if how == "hand" and res.onTime and o.condition >= 85 and rng:NextNumber() < C.DELIVERY.tipChance then
		local amt = math.floor(rng:NextInteger(C.DELIVERY.tip[1], C.DELIVERY.tip[2]) / 100) * 100
		W.tip(player, sess, amt, "고객")
	end
	o.results = o.results or {}
	table.insert(o.results, res)
	-- the recipient's reaction
	if Lines and o.recipient then
		local sit = if o.condition < 60 then "bad" elseif not res.onTime then "late" elseif raining() then "rain" else "thanks"
		local text = Lines.pick(store.lineMemo or {}, "recipient", sit, rand) or "감사합니다"
		store.lineMemo = store.lineMemo or {}
		recipientSay(o, text)
		emote(o, if sit == "thanks" or sit == "rain" then "bow" elseif sit == "late" then "shrug" else "facepalm")
		local r = o.recipient
		o.recipient = nil
		task.delay(4, function()
			if r and r.model then
				r.model:Destroy()
			end
		end)
	else
		removeRecipient(store, o)
	end
	W.removeStation(store, "drop:" .. o.id .. ":" .. o.dropIndex)
	o.dropIndex += 1
	if o.dropIndex <= #o.drops then
		W.toast(player, string.format("📦 다음 배달지 %d/%d · %s", o.dropIndex, #o.drops, o.drops[o.dropIndex].room), "info")
		startDropLeg(store, player, o)
		return
	end
	-- all drops done
	if o.group then
		local all = true
		for _, r in o.results do
			if not r.onTime or r.accuracy < 0.8 then
				all = false
			end
		end
		if all then
			W.extra(player, sess, "groupdv", "단체 배달 보너스", WS.round100(o.pay * C.DELIVERY.groupBonus))
			W.toast(player, "🎉 단체 주문 전부 정시 배달! 보너스", "good")
		end
	end
	W.dropDestroy(player, sess)
	sess.dv.order = nil
	pcall(W.ctx().setWaypoint, player, nil)
	refreshCalls(store, sess, true)
end

function DV.act(store: any, player: Player, sess: any, station: string, action: string, _arg: any?): (boolean, string?)
	local valid = false
	for _, a in DV.actions(store, player, sess, station) do
		if a.id == action then
			if not a.enabled then
				return false, a.reason or "지금은 할 수 없어요"
			end
			valid = true
			break
		end
	end
	if not valid then
		return false, "지금은 할 수 없어요"
	end
	local dv = ensure(sess)
	local parts = string.split(action, ":")
	local verb = parts[1]
	local o = dv.order
	if verb == "clockout" then
		W.requestEnd(player)
		return true
	elseif verb == "refresh" then
		refreshCalls(store, sess, true)
		return true
	elseif verb == "accept" then
		local call = nil
		for _, c in dv.calls do
			if c.id == parts[2] then
				call = c
			end
		end
		if not call then
			return false, "이미 다른 기사님이 잡은 콜이에요"
		end
		local list = steps(call)
		local order = table.clone(call)
		order.packOrder = table.clone(list)
		for i = #order.packOrder, 2, -1 do
			local j = rand(i)
			order.packOrder[i], order.packOrder[j] = order.packOrder[j], order.packOrder[i]
		end
		order.packDone = {}
		order.mistakes = 0
		order.condition = 100
		order.acceptedAt = os.clock()
		order.dropIndex = 1
		order.usedCar = false
		local cook = C.DELIVERY.cookSeconds
		order.readyAt = if call.kind == "food" then os.clock() + rng:NextNumber(cook[1], cook[2]) else nil
		dv.order = order
		dv.calls = {}
		if order.kind == "food" then
			W.addStation(store, { id = "rest:" .. order.id, label = "🍳 " .. (order.restaurant or "식당") .. " 포장대", pos = order.pickupPos, owner = player, reach = 12, reachY = 16 })
			pcall(W.ctx().setWaypoint, player, order.pickupName)
			W.toast(player, string.format("✅ 콜 수락 · %s에서 %s 픽업 (조리 중)", order.restaurant, order.item), "good")
		else
			W.toast(player, string.format("✅ 퀵 수락 · 사무실 선반에서 '%s' 수령", order.item), "good")
		end
		return true
	elseif verb == "cancel" then
		W.removeStation(store, "rest:" .. o.id)
		dv.order = nil
		sess.mistakes = (sess.mistakes or 0) + 1
		pcall(W.ctx().setWaypoint, player, nil)
		W.toast(player, "✖️ 콜을 취소했어요 (취소율이 올라가요)", "warn")
		refreshCalls(store, sess, true)
		return true
	elseif verb == "pack" then
		local id = parts[2]
		local list, labels = steps(o)
		local nextId = nil
		for _, s in list do
			if not table.find(o.packDone, s) then
				nextId = s
				break
			end
		end
		if id ~= nextId then
			o.mistakes += 1
			sess.mistakes = (sess.mistakes or 0) + 1
			W.toast(player, string.format("📦 순서가 달라요 · 먼저 %s", labels[nextId] or nextId), "warn", { sound = "error" })
			return true
		end
		table.insert(o.packDone, id)
		Props.sound(W.stationPart(store, station), "tap", 0.4)
		if #o.packDone >= #list then
			o.pickedAt = os.clock()
			W.removeStation(store, "rest:" .. o.id)
			local item = W.newItem(store, "bag", { color = if o.kind == "quick" then { 255, 196, 40 } else { 42, 193, 188 }, sealed = true, text = o.item })
			Props.create(item, store.folder, CFrame.new(o.pickupPos + Vector3.new(0, 1, 0)))
			W.hold(player, sess, item)
			W.toast(player, string.format("🎒 포장 완료 · %s까지 %d초 안에!", o.drops[1].room, o.drops[1].limit), "good")
			startDropLeg(store, player, o)
		end
		return true
	elseif verb == "call" then
		local drop = o.drops[o.dropIndex]
		drop.called = true
		local msg = Lines and Lines.pick(store.lineMemo or {}, "recipient", "absent", rand) or "문 앞에 두고 가 주세요"
		W.toast(player, "📞 고객: \"" .. msg .. "\"", "info")
		return true
	elseif verb == "door" then
		local drop = o.drops[o.dropIndex]
		if not drop.called then
			o.mistakes += 1
			W.toast(player, "📞 연락 없이 두고 가면 분실 위험! (실수)", "warn")
		end
		drop.leftAtDoor = true
		W.dropDestroy(player, sess)
		-- a bag stays at the door for a moment (visual)
		local bagItem = W.newItem(store, "bag", { color = { 42, 193, 188 }, sealed = true })
		Props.create(bagItem, store.folder, CFrame.new(drop.pos))
		task.delay(25, function()
			W.destroyItem(store, bagItem)
		end)
		if #o.drops > o.dropIndex then
			-- the rest of a group order: a fresh bag for the next stop
			local item = W.newItem(store, "bag", { color = { 42, 193, 188 }, sealed = true, text = o.item })
			Props.create(item, store.folder, CFrame.new(drop.pos + Vector3.new(0, 1, 0)))
			W.hold(player, sess, item)
		end
		return true
	elseif verb == "photo" then
		local drop = o.drops[o.dropIndex]
		if not drop.leftAtDoor then
			W.toast(player, "📸 먼저 문 앞에 두고 찍어요", "warn")
			return true
		end
		finishDrop(store, player, sess, o, "door")
		return true
	elseif verb == "hand" then
		finishDrop(store, player, sess, o, "hand")
		return true
	elseif verb == "return_gear" then
		W.closeTask(store, player, sess, "return_gear")
		return true
	elseif verb == "report" then
		W.closeTask(store, player, sess, "report")
		return true
	end
	return false, "알 수 없는 작업"
end

-------------------------------------------------------------------------------------------------
-- Per-player tick: condition (jolts / speed / late), travel mode, recipient spawn, address change
-------------------------------------------------------------------------------------------------
function DV.playerTick(store: any, player: Player, sess: any, dt: number)
	local dv = ensure(sess)
	local o = dv.order
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local inCar, mode = seated(player)
	if mode ~= dv.mode then
		dv.mode = mode
		W.markPlayer(player)
	end
	local v = root.AssemblyLinearVelocity
	local last = dv.lastV
	dv.lastV = v
	if not o or not o.pickedAt or dt <= 0 then
		return
	end
	if mode == "car" then
		o.usedCar = true
	end
	local D = C.DELIVERY
	local factor = (if raining() then D.rainBumpFactor else 1)
	local sens = (if o.soup then 1.3 else 1) * (if o.fragile then 1.5 else 1) * (if o.premium then 1.4 else 1)
	local now = os.clock()
	if last then
		local dvel = (v - last).Magnitude
		local loss = 0
		local why = nil
		if dvel > D.conditionBumpSpeed * factor then
			loss = D.conditionBumpLoss * sens
			why = "💥 쿵! 충격으로 음식이 흔들렸어요"
		elseif inCar and dvel / dt > (D.hardBrakeAccel or 34) * factor then
			loss = 1.2 * sens
			why = "🛑 급정거! 음식이 쏠려요"
		end
		local speed = Vector3.new(v.X, 0, v.Z).Magnitude
		if speed > D.conditionSpeedLimit then
			loss += D.conditionSpeedLoss * dt * sens
			why = why or "🏎️ 너무 빨라요! 국물이 넘칠 것 같아요"
		end
		if loss > 0 then
			o.condition = math.max(0, o.condition - loss)
			if why and now - (dv.toastAt or 0) > 4 then
				dv.toastAt = now
				W.toast(player, string.format("%s (상태 %d%%)", why, math.floor(o.condition)), "warn")
			end
			W.markPlayer(player)
		end
	end
	-- lateness cools the food
	local left = totalLeft(o)
	if left < 0 then
		o.condition = math.max(0, o.condition - D.conditionLatePerSecond * dt)
	end
	local drop = o.drops[o.dropIndex]
	if not drop then
		return
	end
	local dist = flat(drop.pos - root.Position).Magnitude
	-- the recipient comes out when the courier is near
	if dist < 140 and not o.recipient and not o.recipientSpawned then
		o.recipientSpawned = true
		spawnRecipient(store, player, o, drop)
	end
	-- 주소 변경: once, a third of the way
	if o.addrChange and not o.addrChanged and o.legFrom then
		local total = flat(drop.pos - o.legFrom).Magnitude
		if total > 120 and dist < total * 0.7 then
			o.addrChanged = true
			local ex = { [o.pickupName] = true }
			for _, d in o.drops do
				ex[d.name] = true
			end
			local nd = pickDrops(root.Position, 1, 120, 700, ex)[1]
			if nd then
				local extraDist = flat(nd.part.Position - root.Position).Magnitude
				local addPay, addLim = WS.deliveryQuote(o.kind, extraDist, {})
				W.removeStation(store, "drop:" .. o.id .. ":" .. o.dropIndex)
				removeRecipient(store, o)
				drop.name = nd.name
				drop.pos = groundUnder(nd.part.Position)
				drop.room = roomLabel(nd.name)
				drop.pay += math.floor(addPay * 0.4 / 100) * 100
				for k = o.dropIndex, #o.drops do
					o.drops[k].limit += math.floor(addLim * 0.8)
				end
				startDropLeg(store, player, o)
				W.toast(player, string.format("📱 고객 요청: 주소 변경 → %s (제한 시간 +%d초 · 요금 +%s)", drop.room, math.floor(addLim * 0.8), WS.won(math.floor(addPay * 0.4 / 100) * 100)), "change")
			end
		end
	end
end

function DV.tick(_store: any, _now: number) end

-------------------------------------------------------------------------------------------------
-- Hints, views
-------------------------------------------------------------------------------------------------
DV.CLOSE_LABEL = { return_gear = "가방 · 헬멧 반납", report = "배달 일지 보고" }

function DV.hint(store: any, sess: any): (string?, string?)
	local dv = ensure(sess)
	local o = dv.order
	if not o then
		if W.phaseOf(store) == "close" then
			for _, id in C.DELIVERY.closeTasks do
				if store.close[id] == false then
					return "마감: 사무실 배차 데스크에서 " .. DV.CLOSE_LABEL[id], "dispatch"
				end
			end
			return "마감 완료 · 근태 단말기에서 퇴근 (정산)", "timeclock"
		end
		return "📱 배달 앱에서 콜 수락 (거리 · 단가 · 제한 시간 확인)", "app"
	end
	if not o.pickedAt then
		local list, labels = steps(o)
		local nextId = nil
		for _, s in list do
			if not table.find(o.packDone, s) then
				nextId = s
				break
			end
		end
		local where = if o.kind == "quick" then "shelf" else "rest:" .. o.id
		if o.readyAt and os.clock() < o.readyAt then
			return string.format("%s로 이동 · 조리 중 %d초", o.restaurant or "식당", math.ceil(o.readyAt - os.clock())), where
		end
		return string.format("포장: %s", labels[nextId] or "완료"), where
	end
	local drop = o.drops[o.dropIndex]
	local left = totalLeft(o)
	local mode = WS.MODE_LABEL[dv.mode] or "도보"
	if drop.absent and drop.called then
		return if drop.leftAtDoor then "📸 사진 찍어 전송" else "🚪 문 앞에 두기", "drop:" .. o.id .. ":" .. o.dropIndex
	end
	return string.format("%s · %s %s · 상태 %d%%", drop.room, if left >= 0 then string.format("%d초 남음", left) else string.format("%d초 지각", -left), mode, math.floor(o.condition)), "drop:" .. o.id .. ":" .. o.dropIndex
end

function DV.closeTasks(store: any): { any }
	local out = {}
	for _, id in C.DELIVERY.closeTasks do
		table.insert(out, { id = id, label = DV.CLOSE_LABEL[id], done = store.close[id] == true })
	end
	return out
end

function DV.stockView(_store: any): { any }
	return {}
end

function DV.itemView(_store: any, item: any): any
	return { kind = item.kind, title = (item.text or "배달 가방") .. " 🎒" }
end

function DV.genOrder(_store: any): { any }
	return {}
end

function DV.extraView(_store: any, _player: Player, sess: any): any
	local dv = ensure(sess)
	local out: any = { kind = "delivery", mode = dv.mode, modeLabel = WS.MODE_LABEL[dv.mode] or "도보", rain = raining() }
	local o = dv.order
	if o then
		local drops = {}
		for i, d in o.drops do
			table.insert(drops, { room = d.room, name = d.name, done = i < o.dropIndex, cur = i == o.dropIndex, absent = d.absent and d.called, pay = d.pay })
		end
		local list, labels = steps(o)
		local packSteps = {}
		for _, s in list do
			table.insert(packSteps, { label = labels[s], done = table.find(o.packDone, s) ~= nil })
		end
		out.order = {
			id = o.id,
			kind = o.kind,
			item = o.item,
			from = o.restaurant or "광안 딜리버리",
			pay = o.pay,
			limit = o.limit,
			left = totalLeft(o),
			picked = o.pickedAt ~= nil,
			cooking = if o.readyAt and os.clock() < o.readyAt then math.ceil(o.readyAt - os.clock()) else nil,
			condition = math.floor(o.condition),
			drops = drops,
			pack = packSteps,
			premium = o.premium,
			group = o.group,
			soup = o.soup,
			fragile = o.fragile,
		}
	else
		out.calls = #dv.calls
	end
	return out
end

local _ = Orders
return DV
