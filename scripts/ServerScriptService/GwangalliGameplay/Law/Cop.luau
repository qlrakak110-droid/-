-- GwangalliGameplay/Law/Cop (server; owner: law): the player police job (경찰 직업 패스 — LS.POLICE_PASS_ID;
-- 0 = no pass in this build, anyone may join for testing). NPC police and player cops work the same
-- city at the same time: a cop on duty counts as an officer (a sighting keeps a suspect's stars, a
-- crime in front of a cop is reported at once), and the NPC dispatch keeps running.
--
--   DUTY (op cop {act = "duty", on}): at the 광안지구대 entrance (or anywhere while already on duty to go
--   off), not wanted / jailed / on another shift, reputation >= LS.REP_SUSPEND. Uniform vest, attribute
--   LawCop / LawCopRank. "car": the job patrol car (GwangalliVehiclesAPI spawnJob "police").
--   BOARD ("board"): live 신고 (player crimes as reported + the city's NPC incidents, Law/City), the 수배자
--   list (stars + the LAST KNOWN area, never the live position), own rank / reputation / lock.
--   PATROL ("patrol"): 3 checkpoints across the map; each reached pays LS.COP_PAY.patrolPoint + XP.
--   TRACK ("track" {userId}): a waypoint to the suspect's last known position (updates while you see them).
--   LOOKUP ("lookup"): the nearest car: model, plate, owner, 도난 (stolen by a player: attribute LawStolen).
--   ARREST ("cuff" {userId}): only a target Law.arrestable() (active stars, or a reported unpunished crime
--   inside LS.WARRANT_WINDOW). The suspect is cuffed and follows the cop (escort; in a car the suspect
--   rides along). "handover" at the 지구대 entrance (LS.HANDOVER_RANGE) = full pay + bonus; "transfer"
--   (자동 이송) after LS.AUTO_TRANSFER_AFTER s = pay without the bonus. An illegal attempt is a FALSE
--   ARREST: reputation -10, the target is told, LS.FALSE_LOCK of them inside LS.FALSE_WINDOW lock every
--   arrest tool for LS.LOCK_SECONDS; reputation under LS.REP_SUSPEND ends the duty.
--   TICKET ("ticket" {userId}): a 1-star minor offender within reach: 범칙금 instead of the cell.
--   NPC SUSPECTS ("cuffNpc" {id}): the city's incident suspects (Law/City) — pickpockets, shoplifters.
-- Pay goes to the bank (ctx.ledger) scaled by the rank (LS.COP_RANKS[].pay); XP -> rank.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ServerStorage = game:GetService("ServerStorage")

local Cop = {}

local Law: any
local ctx: any
local LS: any

local duty: { [Player]: any } = {}
local escorts: { [Player]: any } = {} -- target -> { cop, since }
local passCache: { [number]: boolean } = {}

local function now(): number
	return os.clock()
end

local function unix(): number
	return os.time()
end

local function flat(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function playerById(id: any): Player?
	if type(id) ~= "number" then
		return nil
	end
	return Players:GetPlayerByUserId(id)
end

function Cop.hasPass(player: Player): boolean
	if LS.POLICE_PASS_ID == 0 then
		return true
	end
	local c = passCache[player.UserId]
	if c ~= nil then
		return c
	end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, LS.POLICE_PASS_ID)
	end)
	passCache[player.UserId] = ok and owns == true
	return passCache[player.UserId]
end

local function stationPos(): Vector3
	local d = ctx.dest and ctx.dest("광안지구대")
	return if d then d.Position else Vector3.new(-326, 7, 584)
end

local function rankOf(player: Player): (number, any, any?)
	return LS.copRank(Law.data(player).copXp)
end

local function locked(player: Player): (boolean, number)
	local L = Law.data(player)
	local left = L.lockUntil - unix()
	return left > 0, math.max(0, left)
end

local function pay(player: Player, amount: number, label: string, xp: number)
	local _, rank = rankOf(player)
	local L = Law.data(player)
	local before = rankOf(player)
	local money = math.floor(amount * rank.pay / 100 + 0.5) * 100
	if money > 0 and ctx.ledger then
		ctx.ledger(player, "bank", money, "👮 " .. label)
	end
	L.copXp = math.max(0, L.copXp + xp)
	Law.dirty(player)
	local after, cur = rankOf(player)
	player:SetAttribute(LS.Attr.CopRank, cur.title)
	if after > before then
		Law.notify(player, "levelup", "👮 진급!", cur.title .. " (급여 ×" .. string.format("%.2f", cur.pay) .. ")")
		Law.push(player, { kind = "cop", ev = "rank", title = cur.title })
	end
	local d = duty[player]
	if d then
		d.active = true
		d.earned += money
	end
	Law.push(player, { kind = "cop", ev = "pay", amount = money, label = label, xp = xp })
end

local function vest(player: Player, on: boolean)
	local ch = player.Character
	if not ch then
		return
	end
	local old = ch:FindFirstChild("LawPoliceVest")
	if old then
		old:Destroy()
	end
	if not on then
		return
	end
	local torso = ch:FindFirstChild("UpperTorso") or ch:FindFirstChild("Torso")
	if not (torso and torso:IsA("BasePart")) then
		return
	end
	local v = Instance.new("Part")
	v.Name = "LawPoliceVest"
	v.Size = torso.Size * Vector3.new(1.06, 0.9, 1.12)
	v.Color = Color3.fromRGB(32, 44, 90)
	v.Material = Enum.Material.Fabric
	v.CanCollide, v.CanQuery, v.CanTouch, v.Massless = false, false, false, true
	v.CFrame = torso.CFrame
	local w = Instance.new("WeldConstraint")
	w.Part0 = torso
	w.Part1 = v
	w.Parent = v
	for _, face in { Enum.NormalId.Back, Enum.NormalId.Front } do
		local g = Instance.new("SurfaceGui")
		g.Face = face
		g.LightInfluence = 0
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Text = if face == Enum.NormalId.Back then "POLICE\n경찰" else "👮 " .. player.DisplayName
		t.TextColor3 = Color3.fromRGB(255, 226, 90)
		t.Font = Enum.Font.GothamBlack
		t.TextScaled = true
		t.Parent = g
		g.Parent = v
	end
	v.Parent = ch
end

-------------------------------------------------------------------------------------------------
-- Calls (신고 목록)
-------------------------------------------------------------------------------------------------
local calls: { any } = {}
local callSeq = 0

local function pushCops(payload: any)
	for p in duty do
		Law.push(p, payload)
	end
end

function Cop.addCall(call: any): any
	callSeq += 1
	call.id = "c" .. callSeq
	call.t = now()
	call.area = call.area or Law.areaName(call.pos)
	table.insert(calls, 1, call)
	while #calls > 20 do
		table.remove(calls)
	end
	pushCops({ kind = "cop", ev = "call", call = Cop.callView(call) })
	return call
end

function Cop.callView(c: any): any
	return {
		id = c.id,
		label = c.label,
		icon = c.icon or "🚨",
		area = c.area,
		ago = math.floor(now() - c.t),
		stars = c.stars,
		suspect = if c.suspect then c.suspect.DisplayName else c.npcName,
		userId = if c.suspect then c.suspect.UserId else nil,
		npc = c.npcId,
		status = c.status or "open",
		pos = if c.pos then { math.floor(c.pos.X), math.floor(c.pos.Y), math.floor(c.pos.Z) } else nil,
	}
end

function Cop.closeCall(match: (any) -> boolean, status: string)
	for _, c in calls do
		if c.status ~= "closed" and match(c) then
			c.status = status
		end
	end
end

-- Law: a player crime was reported
function Cop.onReport(suspect: Player, kind: string, pos: Vector3?, stars: number)
	local def = LS.CRIMES[kind]
	Cop.addCall({ label = (def and def.label or "범죄") .. " 신고", icon = "🚨", pos = pos, stars = stars, suspect = suspect, kind = kind })
end

-- Law: is there a cop on duty who saw this happen?
function Cop.witness(player: Player, pos: Vector3?): boolean
	if not pos then
		return false
	end
	local P = Law.children.Police
	for cop in duty do
		if cop ~= player then
			local cp = Law.posOf(cop)
			if cp and flat(cp, pos) < 40 and (not P or P.losClear(cp + Vector3.new(0, 1.5, 0), pos + Vector3.new(0, 1.5, 0))) then
				return true
			end
		end
	end
	return false
end

-- Law: a cop committed a crime -> off duty, reputation down
function Cop.onCrime(player: Player, _kind: string)
	if duty[player] then
		local L = Law.data(player)
		L.rep = math.max(0, L.rep - 15)
		Law.dirty(player)
		Cop.setDuty(player, false, "근무 중 범죄: 근무가 정지됐어요")
	end
end

-------------------------------------------------------------------------------------------------
-- Duty
-------------------------------------------------------------------------------------------------
function Cop.onDuty(player: Player): boolean
	return duty[player] ~= nil
end

function Cop.setDuty(player: Player, on: boolean, why: string?): (boolean, string?)
	if on then
		if duty[player] then
			return true, nil
		end
		if not Cop.hasPass(player) then
			return false, "경찰 직업 패스가 필요해요"
		end
		local s = Law.sess(player)
		if not s or s.stars > 0 or s.jail or s.cuffed then
			return false, "수배 중이거나 구금 중에는 근무할 수 없어요"
		end
		if ctx.onShift and ctx.onShift(player) then
			return false, "다른 알바 근무 중이에요"
		end
		local L = Law.data(player)
		if L.rep < LS.REP_SUSPEND then
			return false, "평판이 낮아 근무가 정지된 상태예요 (평판 " .. math.floor(L.rep) .. ")"
		end
		local pp = Law.posOf(player)
		if not pp or flat(pp, stationPos()) > 45 then
			return false, "광안지구대에서 근무를 시작할 수 있어요"
		end
		duty[player] = { since = now(), earned = 0, active = false, lastPay = now(), patrol = nil, track = nil, nextSight = 0, arrests = 0 }
		player:SetAttribute(LS.Attr.Cop, true)
		local _, rank = rankOf(player)
		player:SetAttribute(LS.Attr.CopRank, rank.title)
		vest(player, true)
		Law.notify(player, "info", "👮 근무 시작", rank.title .. " " .. player.DisplayName .. " · 신고 목록을 확인하세요")
		Law.push(player, { kind = "cop", ev = "duty", on = true, view = Cop.view(player) })
		return true, nil
	end
	local d = duty[player]
	if not d then
		return true, nil
	end
	duty[player] = nil
	player:SetAttribute(LS.Attr.Cop, false)
	vest(player, false)
	-- release anyone this cop was escorting (to the automatic transfer)
	for target, e in escorts do
		if e.cop == player then
			Cop.finishEscort(target, "auto")
		end
	end
	pcall(function()
		local api = ServerStorage:FindFirstChild("GwangalliVehiclesAPI")
		if api then
			(api :: BindableFunction):Invoke("despawnJob", player)
		end
	end)
	Law.notify(player, "info", "👮 근무 종료", why or ("오늘 번 돈 " .. LS.won(d.earned)))
	Law.push(player, { kind = "cop", ev = "duty", on = false, view = Cop.view(player) })
	return true, nil
end

function Cop.view(player: Player): any
	local L = Law.data(player)
	local idx, rank, nxt = rankOf(player)
	local lk, left = locked(player)
	local d = duty[player]
	return {
		pass = Cop.hasPass(player),
		on = d ~= nil,
		rank = idx,
		title = rank.title,
		xp = L.copXp,
		nextXp = nxt and nxt.xp or nil,
		nextTitle = nxt and nxt.title or nil,
		rep = math.floor(L.rep),
		locked = lk,
		lockLeft = left,
		earned = d and d.earned or 0,
		patrol = d and d.patrol and { n = d.patrol.i, total = #d.patrol.pts, area = d.patrol.names[d.patrol.i] } or nil,
		escort = (function()
			for t, e in escorts do
				if e.cop == player then
					return { name = t.DisplayName, userId = t.UserId, secs = math.floor(now() - e.since) }
				end
			end
			return nil
		end)(),
	}
end

-- the client draws the marker (GwangalliLaw HUD); the map waypoint only knows Destination names
local function waypoint(player: Player, pos: Vector3, label: string, destName: string?)
	if destName and ctx.setWaypoint then
		pcall(ctx.setWaypoint, player, destName)
	end
	Law.push(player, { kind = "cop", ev = "waypoint", pos = { pos.X, pos.Y, pos.Z }, label = label })
end

-------------------------------------------------------------------------------------------------
-- Escort / handover
-------------------------------------------------------------------------------------------------
function Cop.finishEscort(target: Player, how: string)
	local e = escorts[target]
	if not e then
		return
	end
	escorts[target] = nil
	local cop = e.cop
	local s = Law.sess(target)
	if s then
		s.cuffed = false -- Law.arrest sets it again for the jail scene
	end
	if target.Parent and s then
		local ok = Law.arrest(target, { by = "cop", cop = cop, escort = true, forced = e.forced })
		if ok and cop and cop.Parent then
			local stars = e.stars or 1
			local amount = LS.COP_PAY.arrest + LS.COP_PAY.arrestStar * stars + (if how == "handover" then LS.COP_PAY.handover else 0)
			local xp = LS.COP_XP.arrest + LS.COP_XP.arrestStar * stars + (if how == "handover" then LS.COP_XP.handover else 0)
			pay(cop, amount, if how == "handover" then "체포 · 직접 인계" else "체포 · 자동 이송", xp)
			local d = duty[cop]
			if d then
				d.arrests += 1
			end
			Law.stat(cop, "copArrests")
			Cop.closeCall(function(c)
				return c.suspect == target
			end, "closed")
		end
	end
end

local function escortTick()
	local station = stationPos()
	for target, e in escorts do
		local cop = e.cop
		local tp = Law.posOf(target)
		local cp = Law.posOf(cop)
		if not target.Parent or not cop.Parent or not tp or not cp or not duty[cop] then
			Cop.finishEscort(target, "auto")
		else
			local d = flat(tp, cp)
			if d > LS.ESCORT_RANGE + 40 then
				Cop.finishEscort(target, "auto")
			elseif d > 3.5 then
				-- the cuffed suspect is walked along behind the cop (in a car: next to it)
				local root = Law.rootOf(cop)
				if root then
					local behind = root.CFrame * CFrame.new(1.5, 0, 3)
					local tc = target.Character
					if tc then
						if ctx.allowTeleport then
							pcall(ctx.allowTeleport, target, 2)
						end
						tc:PivotTo(CFrame.new(behind.Position, behind.Position + root.CFrame.LookVector))
					end
				end
			end
			if flat(cp, station) <= LS.HANDOVER_RANGE then
				Cop.finishEscort(target, "handover")
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Ops
-------------------------------------------------------------------------------------------------
local function falseArrest(cop: Player, target: Player?, why: string): any
	local L = Law.data(cop)
	L.rep = math.max(0, L.rep - 10)
	table.insert(L.falseT, unix())
	while #L.falseT > 10 do
		table.remove(L.falseT, 1)
	end
	local recent = 0
	for _, t in L.falseT do
		if unix() - t < LS.FALSE_WINDOW then
			recent += 1
		end
	end
	L.copXp = math.max(0, L.copXp + LS.COP_XP.falseArrest)
	Law.dirty(cop)
	Law.stat(cop, "falseArrests")
	local msg = "부당 체포 시도: " .. why .. " · 평판 -10"
	if recent >= LS.FALSE_LOCK then
		L.lockUntil = unix() + LS.LOCK_SECONDS
		msg ..= " · 체포 기능 " .. math.floor(LS.LOCK_SECONDS / 60) .. "분 제한"
	end
	Law.notify(cop, "warn", "⚠️ 부당 체포", msg)
	if target then
		Law.notify(target, "info", "👮 부당 체포 시도", cop.DisplayName .. " 경찰관의 체포 시도가 거부됐어요 (기록됨)")
	end
	if L.rep < LS.REP_SUSPEND then
		Cop.setDuty(cop, false, "평판이 너무 낮아 근무가 정지됐어요")
	end
	return { ok = false, err = "false", text = msg }
end

local function targetNear(cop: Player, p: any, range: number): (Player?, string?)
	local target = playerById(p and p.userId)
	if not target or target == cop then
		return nil, "대상을 찾을 수 없어요"
	end
	local tp, cp = Law.posOf(target), Law.posOf(cop)
	if not tp or not cp or flat(tp, cp) > range then
		return nil, "너무 멀어요"
	end
	return target, nil
end

local OPS = {}

OPS.duty = function(player, p)
	local ok, err = Cop.setDuty(player, p.on == true)
	return { ok = ok, err = err, text = err, view = Cop.view(player) }
end

OPS.view = function(player, _p)
	return { ok = true, view = Cop.view(player) }
end

OPS.board = function(player, _p)
	if not duty[player] then
		return { ok = false, err = "offduty", text = "근무 중이 아니에요" }
	end
	local out = {}
	for _, c in calls do
		if c.status ~= "closed" and now() - c.t < 600 then
			table.insert(out, Cop.callView(c))
		end
	end
	local wanted = {}
	for p2, s in Law.sessions() do
		if p2 ~= player and (s.stars > 0 or now() < s.warrantUntil) and not s.jail then
			table.insert(wanted, { name = p2.DisplayName, userId = p2.UserId, stars = s.stars, warrant = s.stars == 0, area = Law.areaName(s.knownPos), seenAgo = if s.lastSeen > 0 then math.floor(now() - s.lastSeen) else nil })
		end
	end
	table.sort(wanted, function(a, b)
		return a.stars > b.stars
	end)
	return { ok = true, calls = out, wanted = wanted, view = Cop.view(player) }
end

OPS.car = function(player, _p)
	if not duty[player] then
		return { ok = false, err = "offduty" }
	end
	local api = ServerStorage:FindFirstChild("GwangalliVehiclesAPI")
	if not api then
		return { ok = false, err = "novehicles", text = "차량 시스템을 찾을 수 없어요" }
	end
	local ok, model = pcall(function()
		return (api :: BindableFunction):Invoke("spawnJob", player, "police")
	end)
	if ok and model then
		pcall(function()
			(model :: Model):SetAttribute("LawCopCar", player.UserId)
		end)
		return { ok = true, text = "🚓 순찰차를 불렀어요" }
	end
	return { ok = false, err = "spawn", text = "순찰차를 부를 수 없어요 (도로 가까이에서 다시)" }
end

OPS.patrol = function(player, _p)
	local d = duty[player]
	if not d then
		return { ok = false, err = "offduty" }
	end
	local N = Law.nav()
	if not N or not N.places then
		return { ok = false }
	end
	local keys = {}
	for k, v in N.places do
		if type(v) == "table" and v.x and type(v.name) == "string" and not string.find(k, "metro_") then
			table.insert(keys, k)
		end
	end
	if #keys < 3 then
		return { ok = false }
	end
	local pts, names = {}, {}
	for _ = 1, 3 do
		local k = keys[math.random(#keys)]
		local v = N.places[k]
		table.insert(pts, Vector3.new(v.x, v.y, v.z))
		table.insert(names, v.name)
	end
	d.patrol = { pts = pts, names = names, i = 1 }
	waypoint(player, pts[1], "순찰 1/3 · " .. names[1])
	return { ok = true, view = Cop.view(player) }
end

OPS.track = function(player, p)
	local d = duty[player]
	if not d then
		return { ok = false, err = "offduty" }
	end
	local target = playerById(p.userId)
	local s = target and Law.sess(target)
	if not target or not s or not s.knownPos then
		return { ok = false, text = "마지막 목격 위치가 없어요" }
	end
	d.track = target
	waypoint(player, s.knownPos, "마지막 목격 · " .. target.DisplayName)
	return { ok = true, area = Law.areaName(s.knownPos) }
end

OPS.lookup = function(player, _p)
	if not duty[player] then
		return { ok = false, err = "offduty" }
	end
	local pp = Law.posOf(player)
	if not pp then
		return { ok = false }
	end
	local best, bd = nil, 26
	local map = workspace:FindFirstChild("Gwangalli")
	local roads = map and map:FindFirstChild("roads")
	local sources = { workspace:FindFirstChild("GwangalliPlayerCars"), roads and roads:FindFirstChild("ParkedVehicles"), roads and roads:FindFirstChild("TrafficVehicles") }
	for _, f in sources do
		if f then
			for _, m in f:GetChildren() do
				if m:IsA("Model") and m:GetAttribute("VehicleKind") ~= nil then
					local ok, piv = pcall(function()
						return m:GetPivot().Position
					end)
					if ok then
						local dd = flat(piv, pp)
						if dd < bd then
							best, bd = m, dd
						end
					end
				end
			end
		end
	end
	if not best then
		return { ok = false, text = "근처에 조회할 차량이 없어요" }
	end
	local owner = best:GetAttribute("DriveOwner")
	local ownerP = type(owner) == "number" and owner > 0 and Players:GetPlayerByUserId(owner) or nil
	local stolen = best:GetAttribute("LawStolen")
	local stolenBy = type(stolen) == "number" and Players:GetPlayerByUserId(stolen) or nil
	local d = duty[player]
	if d and now() - (d.lastLookup or 0) > 8 then
		d.lastLookup = now()
		local L = Law.data(player)
		L.copXp += LS.COP_XP.lookup
		Law.dirty(player)
	end
	return {
		ok = true,
		car = {
			label = best:GetAttribute("DriveLabel") or best:GetAttribute("VehicleKind") or "차량",
			plate = best:GetAttribute("DrivePlate") or "등록 정보 없음",
			owner = if ownerP then ownerP.DisplayName elseif best:GetAttribute("DriveJobKind") then "업무용 차량" else "주민 차량",
			stolen = stolen ~= nil,
			stolenBy = if stolenBy then stolenBy.DisplayName else nil,
			driver = (function()
				local dv = best:GetAttribute("DriveDriver")
				local dp = type(dv) == "number" and dv > 0 and Players:GetPlayerByUserId(dv) or nil
				return dp and dp.DisplayName or nil
			end)(),
		},
	}
end

OPS.cuff = function(player, p)
	if not duty[player] then
		return { ok = false, err = "offduty" }
	end
	local lk, left = locked(player)
	if lk then
		return { ok = false, err = "locked", text = "체포 기능 제한 중 (" .. LS.fmtTime(left) .. ")" }
	end
	local target, err = targetNear(player, p, LS.CUFF_RANGE)
	if not target then
		return { ok = false, err = "target", text = err }
	end
	if duty[target] then
		return falseArrest(player, target, "근무 중인 경찰관")
	end
	if escorts[target] then
		return { ok = false, text = "이미 수갑을 찼어요" }
	end
	local ok, reason = Law.arrestable(target)
	if not ok then
		return falseArrest(player, target, "범죄 기록 / 수배가 없는 시민")
	end
	local s = Law.sess(target)
	escorts[target] = { cop = player, since = now(), stars = s and s.stars or 1, forced = (s and s.stars or 0) >= 2 }
	if s then
		s.cuffed = true
		Law.writeAttrs(target, s)
		if Law.children.Police then
			Law.children.Police.standDown(target, s, "arrest")
		end
	end
	local J = Law.children.Jail
	if J and J.cuffs then
		J.cuffs(target, true)
	end
	Law.notify(target, "warn", "👮 수갑", player.DisplayName .. " 경찰관에게 체포됐어요 (" .. tostring(reason) .. ")")
	Law.push(target, { kind = "arrest", stage = "escort", cop = player.DisplayName })
	Law.push(player, { kind = "cop", ev = "escort", name = target.DisplayName, userId = target.UserId, reason = reason })
	waypoint(player, stationPos(), "광안지구대 인계", "광안지구대")
	return { ok = true, reason = reason, view = Cop.view(player) }
end

OPS.handover = function(player, _p)
	for target, e in escorts do
		if e.cop == player then
			local cp = Law.posOf(player)
			if cp and flat(cp, stationPos()) <= LS.HANDOVER_RANGE then
				Cop.finishEscort(target, "handover")
				return { ok = true }
			end
			return { ok = false, text = "광안지구대 입구에서 인계할 수 있어요" }
		end
	end
	return { ok = false, text = "호송 중인 피의자가 없어요" }
end

OPS.transfer = function(player, _p)
	for target, e in escorts do
		if e.cop == player then
			if now() - e.since < LS.AUTO_TRANSFER_AFTER then
				return { ok = false, text = "자동 이송은 " .. math.ceil(LS.AUTO_TRANSFER_AFTER - (now() - e.since)) .. "초 후에 가능해요" }
			end
			Cop.finishEscort(target, "auto")
			return { ok = true }
		end
	end
	return { ok = false, text = "호송 중인 피의자가 없어요" }
end

OPS.ticket = function(player, p)
	if not duty[player] then
		return { ok = false, err = "offduty" }
	end
	local target, err = targetNear(player, p, LS.CUFF_RANGE + 3)
	if not target then
		return { ok = false, text = err }
	end
	if not Law.ticketable(target) then
		local ok = Law.arrestable(target)
		if not ok then
			return falseArrest(player, target, "위반 사항이 없는 시민")
		end
		return { ok = false, text = "범칙금으로 끝낼 수 없는 사건이에요 (체포하세요)" }
	end
	Law.ticket(target, "경찰 " .. player.DisplayName)
	pay(player, LS.COP_PAY.ticket, "범칙금 발부", LS.COP_XP.ticket)
	Cop.closeCall(function(c)
		return c.suspect == target
	end, "closed")
	return { ok = true }
end

OPS.cuffNpc = function(player, p)
	if not duty[player] then
		return { ok = false, err = "offduty" }
	end
	local lk = locked(player)
	if lk then
		return { ok = false, err = "locked" }
	end
	local City = Law.children.City
	if not City then
		return { ok = false }
	end
	local ok, label = City.arrestNpc(type(p.id) == "string" and p.id or "", player)
	if not ok then
		return { ok = false, text = label or "체포할 수 없어요" }
	end
	pay(player, LS.COP_PAY.npcArrest, "검거 · " .. tostring(label), LS.COP_XP.npcArrest)
	return { ok = true, label = label }
end

-------------------------------------------------------------------------------------------------
-- Tick: cops see suspects, patrol checkpoints, duty pay, escorts
-------------------------------------------------------------------------------------------------
local acc = 0
function Cop.tick(dt: number)
	acc += dt
	escortTick()
	if acc < 0.5 then
		return
	end
	acc = 0
	local P = Law.children.Police
	for cop, d in duty do
		if not cop.Parent then
			duty[cop] = nil
		else
			local cp = Law.posOf(cop)
			if cp then
				-- sightings (a player cop is an officer for the stars)
				for p2, s in Law.sessions() do
					if p2 ~= cop and s.stars > 0 and not s.jail then
						local tp = Law.posOf(p2)
						if tp and flat(tp, cp) < 80 and (not P or P.losClear(cp + Vector3.new(0, 1.6, 0), tp + Vector3.new(0, 1.2, 0))) then
							Law.seen(p2, tp, "경찰 " .. cop.DisplayName)
							if d.track == p2 and now() - (d.lastTrackWp or 0) > 4 then
								d.lastTrackWp = now()
								waypoint(cop, tp, "추격 중 · " .. p2.DisplayName)
							end
						end
					end
				end
				-- patrol checkpoints
				local pt = d.patrol
				if pt and pt.pts[pt.i] and flat(cp, pt.pts[pt.i]) < 14 then
					pay(cop, LS.COP_PAY.patrolPoint, "순찰 · " .. pt.names[pt.i], LS.COP_XP.patrolPoint)
					pt.i += 1
					if pt.pts[pt.i] then
						waypoint(cop, pt.pts[pt.i], "순찰 " .. pt.i .. "/" .. #pt.pts .. " · " .. pt.names[pt.i])
					else
						d.patrol = nil
						Law.push(cop, { kind = "cop", ev = "patrolDone" })
					end
				end
			end
			-- duty pay every 2 minutes with some activity
			if now() - d.lastPay >= 120 then
				d.lastPay = now()
				if d.active then
					d.active = false
					pay(cop, LS.COP_PAY.duty, "근무 수당", 2)
				end
			end
		end
	end
end

function Cop.onCharacter(player: Player, _s: any, _character: Model)
	if duty[player] then
		task.delay(1, function()
			if duty[player] then
				vest(player, true)
			end
		end)
	end
end

function Cop.onLeave(player: Player, _s: any)
	if duty[player] then
		Cop.setDuty(player, false)
	end
	if escorts[player] then
		-- leaving while cuffed: straight to the transfer (the cell time is saved on leave)
		Cop.finishEscort(player, "auto")
	end
	passCache[player.UserId] = nil
end

function Cop.init(law: any, context: any)
	Law = law
	ctx = context
	LS = Law.shared()
	Law.ops.cop = function(player, _s, p)
		local fn = OPS[p and p.act]
		if not fn then
			return { ok = false, err = "bad" }
		end
		return fn(player, p)
	end
end

return Cop
