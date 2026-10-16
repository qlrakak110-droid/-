-- GwangalliClinic/Ward: 2층 입원실.
--   wake-up      Health's collapse puts the patient on a ward bed (Player.GwCollapse true -> false) and the KO
--                flow (character GwKO) does the same: the nurse greets them and, when an 응급 진료비 is
--                unpaid (d.health.debt), offers the 퇴원 수속 at the 1F 원무과 window.
--   병실 휴식     "병실 휴식" on a free ward bed: Seat:Sit (the game's own safe path, the same seats Health
--                uses); fatigue -1 every Config.Ward.RestEvery s through Health.rest (capped per stay).
--                Ward beds are never reserved by the clinic (collapse / KO always find a bed).
--   간호사 호출   the CallPanel buttons: chime + lamp for everyone nearby (State Lamp_<anchor>), a reply
--                from the nurse station, and a glass of water (행복 +1, once per 10 min) when resting.
--   퇴원 수속     pay the 미납 진료비 at a 1F window (no visit needed): bill rows from Billing (ward).

local Players = game:GetService("Players")

local Ward = {}

local K: any
local S: any
local C: any
local Bridge: any
local Site: any
local Net: any
local Store: any
local Patient: any

local BEDS = { "Ward1A", "Ward1B", "Ward2A", "Ward2B" }
local CALLS = { "Call1A", "Call1B", "Call2A", "Call2B" }
local resting: { [Player]: { anchor: string, given: number, acc: number } } = {}
local woke: { [Player]: number } = {}
local billIds: { [Player]: string } = {}

local function now(): number
	return os.time()
end

local function onWardBed(player: Player): string?
	for _, a in BEDS do
		if Site.isSeatedOn(player, a) then
			return a
		end
	end
	return nil
end

function Ward.viewOf(player: Player): any
	return {
		debt = Bridge.debt(player),
		resting = resting[player] ~= nil,
		woke = woke[player] ~= nil and (now() - woke[player]) < 600,
	}
end

local function wardPlan(): any
	return { id = "W", title = "퇴원 수속", ward = true }
end

local function wardBill(player: Player): any
	local debt = Bridge.debt(player)
	local rows = S.Billing.rows(wardPlan(), { debt = debt }, C, nil)
	local sum = S.Billing.summary(rows, C)
	local cash, bank = Bridge.balance(player)
	local chart = Store.chart(player)
	billIds[player] = billIds[player] or (tostring(player.UserId % 10000) .. "-" .. tostring(math.random(1000, 9999)))
	return {
		id = billIds[player],
		no = string.format("%s-W%03d", os.date("!%y%m%d", os.time() + 9 * 3600), player.UserId % 1000),
		patient = S.mask(player.DisplayName),
		chartNo = chart.no,
		dept = "응급 · 입원",
		doctor = C.Doctor.name,
		date = S.dateTime(os.time()),
		rows = rows,
		sum = sum,
		methods = { card = bank or 0, cash = cash or 0 },
		ward = true,
	}
end

-- 퇴원 수속 at a 1F window (called by Visit's "pay" op when the player has no visit)
function Ward.pay(player: Player, p: any): any
	local debt = Bridge.debt(player)
	if debt <= 0 then
		return Net.fail("noVisit")
	end
	local win = Site.nearestOf(player, { "Win1", "Win2" }, C.Reach.Window)
	if not win then
		return Net.fail("far", "1층 접수 · 수납 창구")
	end
	local action = S.oneOf(p.action, { "view", "pay" }) or "view"
	local bill = wardBill(player)
	if action == "view" then
		Site.setAct(if win == "Win1" then "desk1" else "desk2", "talk", player.UserId)
		return { ok = true, bill = bill, ward = true }
	end
	if type(p.bill) == "string" and p.bill ~= bill.id then
		return Net.fail("bad")
	end
	local method = S.oneOf(p.method, { "card", "cash" }) or C.Fees.DefaultMethod
	local res = Bridge.charge(player, debt, string.format("%s 퇴원 수속 (미납 진료비)", C.Venue.Name), method)
	if res == "money" then
		local cash, bank = Bridge.balance(player)
		return { ok = false, code = "money", message = S.err("money", S.won(debt), S.won(bank or 0), S.won(cash or 0)), bill = bill }
	elseif res ~= "ok" then
		return Net.fail(if res == "noapi" then "noMoney" elseif res == "busy" then "busy" else "error")
	end
	Bridge.setDebt(player, math.max(0, Bridge.debt(player) - debt))
	local d = Store.get(player)
	if d.mirror then
		d.mirror.debt = Bridge.debt(player)
	end
	Store.markDirty(player)
	billIds[player] = nil
	woke[player] = nil
	Site.setAct(if win == "Win1" then "desk1" else "desk2", "give", player.UserId)
	Net.line(player, "desk", "퇴원 수속 끝났습니다. 몸조리 잘 하시고, 무리하지 마세요!", { name = C.Staff.desk1.name })
	local paidBill = wardBill(player)
	paidBill.paid = true
	paidBill.rows = bill.rows
	paidBill.sum = bill.sum
	return { ok = true, bill = paidBill, ward = true, done = true }
end

local function opWard(player: Player, p: any): any
	local action = S.oneOf(p.action, { "rest", "call", "leave" })
	if not action then
		return Net.fail("bad")
	end
	if action == "leave" then
		if resting[player] then
			resting[player] = nil
			Site.unseat(player)
		end
		return { ok = true }
	end
	local d = Store.get(player)
	if action == "call" then
		local anchor = Site.nearestOf(player, CALLS, C.Reach.Ward + 2)
		if not anchor then
			-- the bed itself is close enough to reach the button on the wall
			local bed = onWardBed(player)
			if bed then
				for _, c in CALLS do
					local a = Site.anchors[c]
					if a and a:GetAttribute("ClinicWard") == bed then
						anchor = c
					end
				end
			end
		end
		if not anchor then
			return Net.fail("ward")
		end
		if now() - (d.ward.lastCall or 0) < C.Ward.CallCooldown then
			return Net.fail("cooldown")
		end
		d.ward.lastCall = now()
		if K.state then
			K.state:SetAttribute("Lamp_" .. anchor, S.now())
		end
		local r = resting[player]
		local happy = false
		if r and now() - (d.ward.lastHappy or 0) >= 600 and C.Ward.CallHappiness > 0 then
			d.ward.lastHappy = now()
			happy = true
			task.delay(4, function()
				if player.Parent == Players and resting[player] then
					Bridge.addStats(player, { happiness = C.Ward.CallHappiness }, "간호사가 물을 가져다줬어요")
					Net.line(player, "nurse2", "여기 물 한 잔 드세요. 푹 쉬시고, 필요하면 또 부르세요~", { name = "간호사실" })
				end
			end)
		end
		Store.markDirty(player)
		Net.line(player, "nurse2", if happy then "네~ 간호사실입니다. 바로 갈게요!" else "네~ 간호사실입니다. 무슨 일 있으세요? 불편하시면 바로 말씀하세요.", { name = "간호사실" })
		return { ok = true, lamp = anchor }
	end
	-- rest
	if not C.Ward.RestEnabled then
		return Net.fail("off")
	end
	if K.Visit.get(player) then
		return Net.fail("hasVisit", S.ticket(K.Visit.get(player).ticket))
	end
	if Bridge.onShift(player) then
		return Net.fail("shift")
	end
	local anchor = Site.nearestOf(player, BEDS, C.Reach.Ward)
	if not anchor then
		return Net.fail("ward")
	end
	local left = C.Ward.RestCooldown - (now() - (d.ward.lastRest or 0))
	if left > 0 and not (woke[player] and now() - woke[player] < 600) then
		return Net.fail("wardCool", S.dur(left))
	end
	local occ = Site.occupant(anchor)
	if occ and occ ~= player then
		return Net.fail("bedTaken")
	end
	local seat = Site.seats[anchor]
	if seat and seat.Occupant and not occ then
		return Net.fail("bedTaken")
	end
	if not Site.sit(player, anchor) then
		return Net.fail("error")
	end
	d.ward.lastRest = now()
	Store.markDirty(player)
	resting[player] = { anchor = anchor, given = 0, acc = 0 }
	Net.line(player, "nurse2", string.format("편하게 누워 쉬세요. 피로가 조금씩 풀릴 거예요 (최대 -%d).", C.Ward.RestMaxPerStay), { name = "간호사실" })
	return { ok = true, anchor = anchor, max = C.Ward.RestMaxPerStay }
end

local function watchPlayer(player: Player)
	local was = player:GetAttribute("GwCollapse") == true
	player:GetAttributeChangedSignal("GwCollapse"):Connect(function()
		local cur = player:GetAttribute("GwCollapse") == true
		if was and not cur then
			task.delay(1.2, function()
				if player.Parent ~= Players then
					return
				end
				if onWardBed(player) or Site.playerInZone(player) then
					woke[player] = now()
					Net.fire(player, { kind = "ward", wake = "collapse", debt = Bridge.debt(player), health = Patient.view(player) })
				end
			end)
		end
		was = cur
	end)
	local function hookChar(ch: Model)
		local ko = ch:GetAttribute("GwKO") == true
		ch:GetAttributeChangedSignal("GwKO"):Connect(function()
			local cur = ch:GetAttribute("GwKO") == true
			if ko and not cur then
				task.delay(1, function()
					if player.Parent == Players and (onWardBed(player) or Site.playerInZone(player)) then
						woke[player] = now()
						Net.fire(player, { kind = "ward", wake = "ko", debt = Bridge.debt(player), health = Patient.view(player) })
					end
				end)
			end
			ko = cur
		end)
	end
	if player.Character then
		hookChar(player.Character)
	end
	player.CharacterAdded:Connect(hookChar)
end

function Ward.init(k: any)
	K = k
	S = k.S
	C = S.Config
	Bridge = k.Bridge
	Site = k.Site
	Net = k.Net
	Store = k.Store
	Patient = k.Patient
	Net.handle("ward", "act", opWard)
end

function Ward.start()
	for _, p in Players:GetPlayers() do
		watchPlayer(p)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(p)
		resting[p] = nil
		woke[p] = nil
		billIds[p] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			for p, r in resting do
				if p.Parent ~= Players or not Site.isSeatedOn(p, r.anchor) then
					resting[p] = nil
					if p.Parent == Players then
						Net.fire(p, { kind = "ward", rest = "end", given = r.given })
					end
				else
					r.acc += 1
					if r.acc >= C.Ward.RestEvery and r.given < C.Ward.RestMaxPerStay then
						r.acc = 0
						Bridge.rest(p, 1)
						r.given += 1
						Net.fire(p, { kind = "ward", rest = "tick", given = r.given, max = C.Ward.RestMaxPerStay, fatigue = math.floor(Bridge.fatigue(p) + 0.5) })
					end
				end
			end
		end
	end)
end

return Ward
