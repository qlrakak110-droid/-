-- GwangalliGameplay/Life: the life-game layer around jobs.
--   * bank: cash <-> bank transfers (phone banking / 은행원)
--   * housing: rent / buy listings (G.rentHome / G.buyHome / 주택담보대출 G.buyHomeWithLoan), the
--     per-player daily charge (G.homeTick: warnings, missed payments, eviction, foreclosure, bills),
--     enter / leave home, sleep, respawn at home -- the per-player home instances, interactions,
--     furniture and visits are in the sibling module Housing (falls back to the Destination)
--   * messages + offers: texts that arrive over time (G.OFFERS) and replies (accept -> the same
--     server actions as the phone / NPCs), the landlord's rent reminders
--   * contacts: phone calls (taxi dispatch, NPC dialog by phone, friends)
--   * club entry / VIP table, friends' chat, happiness decay + stamina regen, waypoint
--   * 피로도 hooks: sleep at home / 치맥 call ctx.health.rest (GwangalliGameplay/Health.luau, optional)

local Players = game:GetService("Players")

local Life = {}

local G: any
local Util: any
local Profiles: any
local ctx: any
local Housing: any = nil -- sibling module GwangalliGameplay.Housing (optional)

type Sess = {
	online: number,
	warned: boolean,
	dayProgress: number,
	decayT: number,
	regenT: number,
	lastOffer: number,
	clubPassUntil: number,
	invited: boolean,
	meet: { contact: string, untilT: number }?,
	lastSleep: number,
	inUnit: boolean,
	spawned: boolean,
	chat: { [string]: number },
}
local sessions: { [Player]: Sess } = {}

local function S(player: Player): Sess
	local s = sessions[player]
	if not s then
		s = {
			online = 0,
			warned = false,
			dayProgress = 0,
			decayT = 0,
			regenT = 0,
			lastOffer = -math.huge,
			clubPassUntil = 0,
			invited = false,
			meet = nil,
			lastSleep = -math.huge,
			inUnit = false,
			spawned = false,
			chat = {},
		}
		sessions[player] = s
	end
	return s
end

local function won(n: number): string
	return G.format.won(n)
end

-------------------------------------------------------------------------------------------------
-- Messages
-------------------------------------------------------------------------------------------------
local function thread(d: any, cid: string): any
	local t = d.messages.threads[cid]
	if not t then
		t = { list = {}, unread = 0 }
		d.messages.threads[cid] = t
	end
	return t
end

local function push(d: any, cid: string, from: string, text: string)
	local t = thread(d, cid)
	table.insert(t.list, { from = from, text = text, t = os.time(), clock = ctx.env().clock })
	while #t.list > Profiles.MAX_THREAD do
		table.remove(t.list, 1)
	end
	if from == "them" then
		t.unread = math.min(99, (t.unread or 0) + 1)
	end
end

-- A text from a contact (notifies the player).
function Life.sendMessage(player: Player, cid: string, text: string, special: string?)
	local d = Profiles.get(player)
	local c = G.CONTACTS[cid]
	if not d or not c then
		return
	end
	push(d, cid, "them", text)
	if special then
		thread(d, cid).special = special
	end
	ctx.changed(player, "messages")
	ctx.notify(player, "message", c.name, text, { contact = cid, sound = "message" })
end

local function sendOffer(player: Player, d: any, offerId: string)
	local o = G.OFFERS[offerId]
	local t = thread(d, o.contact)
	d.offersSent[offerId] = os.time()
	if o.action then
		t.offer = offerId
		d.offers[offerId] = { contact = o.contact, t = os.time() }
	end
	Life.sendMessage(player, o.contact, o.text)
end

function Life.readThread(player: Player, contact: any)
	local d = Profiles.get(player)
	local cid = G.resolveContact(contact)
	if not d or not cid then
		return
	end
	local t = d.messages.threads[cid]
	if t and (t.unread or 0) > 0 then
		t.unread = 0
		ctx.changed(player, "messages")
	end
end

local function runOfferAction(player: Player, d: any, o: any)
	local a = o.action
	if not a then
		return
	end
	if a.type == "applyJob" then
		ctx.applyJob(player, a.job, "message")
	elseif a.type == "clubPass" then
		S(player).invited = true
		Life.setWaypoint(player, "CLUB OCEAN 광안")
	elseif a.type == "waypoint" then
		Life.setWaypoint(player, a.dest)
	elseif a.type == "meet" then
		S(player).meet = { contact = a.contact, untilT = os.clock() + 600 }
		Life.setWaypoint(player, a.dest)
	end
	local _ = d
end

function Life.reply(player: Player, contact: any, choice: any)
	local d = Profiles.get(player)
	local cid = G.resolveContact(contact)
	if not d or not cid then
		return
	end
	local t = d.messages.threads[cid]
	if not t then
		return
	end
	local accept: boolean? = nil
	if choice == "accept" or choice == "pay" or choice == 1 then
		accept = true
	elseif choice == "decline" or choice == "later" or choice == 2 then
		accept = false
	end
	if accept == nil then
		return
	end
	if t.offer then
		local id = t.offer
		local o = G.OFFERS[id]
		t.offer = nil
		d.offers[id] = nil
		push(d, cid, "me", if accept then "좋아요! 👍" else "다음에 할게요 🙏")
		local r = if accept then o.acceptReply else o.declineReply
		if r then
			push(d, cid, "them", r)
			t.unread = 0
		end
		ctx.changed(player, "messages")
		if accept then
			runOfferAction(player, d, o)
		end
		return
	end
	if t.special == "rent" then
		t.special = nil
		if accept then
			local ok, amt = G.payArrears(d, os.time())
			if ok then
				push(d, cid, "me", "연체금 " .. won(amt) .. " 보냈습니다.")
				push(d, cid, "them", "확인했어요. 감사합니다 🙏")
				ctx.changed(player, "cash", "bank", "home")
			else
				push(d, cid, "me", "지금은 돈이 부족해요…")
				push(d, cid, "them", string.format("%s 필요해요. 빨리 부탁드려요.", won(amt)))
				t.special = "rent"
			end
		else
			push(d, cid, "me", "곧 낼게요!")
		end
		t.unread = 0
		ctx.changed(player, "messages")
	end
end

-------------------------------------------------------------------------------------------------
-- Waypoint / bank
-------------------------------------------------------------------------------------------------
function Life.setWaypoint(player: Player, dest: any)
	local d = Profiles.get(player)
	if not d then
		return
	end
	if dest == nil or dest == false or dest == "" then
		d.waypoint = nil
	else
		local name = Util.str(dest, 80)
		if not name then
			return
		end
		d.waypoint = name
	end
	ctx.changed(player, "waypoint")
end

function Life.bankTransfer(player: Player, direction: any, amount: any): (boolean, string)
	local d = Profiles.get(player)
	if not d then
		return false, "잠시 후 다시 시도해 주세요"
	end
	local amt = if type(amount) == "number" then math.floor(amount) else nil
	if direction ~= "deposit" and direction ~= "withdraw" then
		return false, "잘못된 요청이에요"
	end
	if not amt or amt <= 0 then
		local msg = if direction == "deposit" then "입금할 현금이 없어요" else "출금할 금액을 확인해 주세요"
		ctx.notify(player, "info", "은행", msg)
		return false, msg
	end
	local ok, reason = G.transfer(d, direction, amt, os.time())
	if not ok then
		local msg = if reason == "insufficient" then (if direction == "deposit" then "현금이 부족해요" else "통장 잔고가 부족해요") else "잘못된 금액이에요"
		ctx.notify(player, "money", "이체 실패", msg)
		return false, msg
	end
	ctx.changed(player, "cash", "bank")
	ctx.refreshAttributes(player)
	local msg = string.format("%s %s 완료 · 통장 %s · 현금 %s", if direction == "deposit" then "입금" else "출금", won(amt), won(d.bank), won(d.cash))
	ctx.notify(player, "money", if direction == "deposit" then "입금 완료 🏦" else "출금 완료 💵", msg)
	return true, msg
end

-------------------------------------------------------------------------------------------------
-- Housing (the home instances, interactions, furniture and visits live in Housing.luau; these
-- functions keep their public API: NPC.luau / the phone call them through ctx)
-------------------------------------------------------------------------------------------------
local REASONS = {
	unknown = "없는 매물이에요",
	notRent = "월세 매물이 아니에요",
	notBuy = "매매 매물이 아니에요",
	same = "이미 살고 있는 집이에요",
	owned = "자가가 있어서 월세로는 옮길 수 없어요 (매매 매물로만 갈아탈 수 있어요)",
	loan = "이미 주택담보대출이 있어요. 먼저 갚아 주세요",
}

local function housingReady(): boolean
	return Housing ~= nil and Housing.available()
end

local function afterMove(player: Player, d: any, title: string, body: string, firstHome: boolean)
	player:SetAttribute(G.Attr.HomeTier, d.home and d.home.tier or 0)
	S(player).warned = false
	if housingReady() then
		pcall(Housing.onHomeChanged, player, "move")
	end
	ctx.changed(player, "home", "cash", "bank", "housing")
	ctx.refreshAttributes(player)
	ctx.notify(player, "home", title, body, { sound = "complete" })
	if d.home then
		local l = G.LISTINGS[d.home.listingId]
		Life.setWaypoint(player, l.place)
		ctx.addStats(player, { happiness = 5 + l.tier * 2 }, nil, true)
		task.delay(20, function()
			if player.Parent == Players and Profiles.get(player) then
				Life.sendMessage(player, "minji", if firstHome
					then "집 구했다며?! 🎉 집들이 해야지~ 집에서 '초대하기'로 친구들 불러! 가구도 하나씩 채워 보고 ㅎㅎ"
					else string.format("%s(으)로 이사했다며? 대박 👏 집들이 언제 해?", l.name))
			end
		end)
	end
end

function Life.rentHome(player: Player, listingId: any): (boolean, string)
	local d = Profiles.get(player)
	local id = Util.str(listingId, 40)
	if not d or not id then
		return false, "잘못된 요청이에요"
	end
	local first = d.home == nil
	local ok, reason = G.rentHome(d, id, os.time())
	local l = G.LISTINGS[id]
	if not ok then
		local msg = REASONS[reason or ""] or "계약할 수 없어요"
		if reason == "insufficient" and l then
			msg = string.format("잔액이 부족해요 (보증금 %s + 첫날 월세 %s 필요)", won(l.deposit or 0), won(l.rentPerDay))
		end
		ctx.notify(player, "home", "계약 실패", msg)
		return false, msg
	end
	G.addBill(d, "rent", l.name .. " 계약 (보증금+첫날 월세)", (l.deposit or 0) + l.rentPerDay, true, os.time())
	local msg = string.format("%s 계약 완료! 🔑 하루 월세 %s는 통장에서 자동이체돼요. 지도에 집을 표시했어요.", l.name, won(l.rentPerDay))
	afterMove(player, d, "입주 완료 · " .. l.name, msg, first)
	return true, msg
end

function Life.buyHome(player: Player, listingId: any): (boolean, string)
	local d = Profiles.get(player)
	local id = Util.str(listingId, 40)
	if not d or not id then
		return false, "잘못된 요청이에요"
	end
	local first = d.home == nil
	local ok, reason = G.buyHome(d, id, os.time())
	local l = G.LISTINGS[id]
	if not ok then
		local msg = REASONS[reason or ""] or "살 수 없어요"
		if reason == "insufficient" and l then
			local q = G.mortgageQuote(id)
			msg = string.format("잔액이 부족해요 (%s 필요 · 통장 %s)%s", won(l.price), won(d.bank), if q then string.format(" · 대출이면 계약금 %s", won(q.down)) else "")
		end
		ctx.notify(player, "home", "매매 실패", msg)
		return false, msg
	end
	G.addBill(d, "info", l.name .. " 매매", l.price, true, os.time())
	local msg = string.format("축하해요! %s의 주인이 됐어요 🎉 (관리비 하루 %s)", l.name, won(l.upkeepPerDay or 0))
	afterMove(player, d, "내 집 마련 🏠 " .. l.name, msg, first)
	ctx.addStats(player, { happiness = 20, popularity = 5 }, nil, true)
	return true, msg
end

-- 주택담보대출로 매매: down payment now, a daily installment with the 관리비 (G.MORTGAGE).
function Life.buyHomeLoan(player: Player, listingId: any): (boolean, string)
	local d = Profiles.get(player)
	local id = Util.str(listingId, 40)
	if not d or not id then
		return false, "잘못된 요청이에요"
	end
	local first = d.home == nil
	local q = G.mortgageQuote(id)
	local ok, reason = G.buyHomeWithLoan(d, id, os.time())
	local l = G.LISTINGS[id]
	if not ok or not q then
		local msg = REASONS[reason or ""] or "대출 매매를 할 수 없어요"
		if reason == "insufficient" and q then
			msg = string.format("계약금이 부족해요 (계약금 %s 필요 · 통장 %s)", won(q.down), won(d.bank))
		end
		ctx.notify(player, "home", "대출 매매 실패", msg)
		return false, msg
	end
	G.addBill(d, "loan", string.format("%s 계약금 (대출 %s)", l.name, won(q.total)), q.down, true, os.time())
	local msg = string.format("축하해요! %s 내 집 마련 🎉 계약금 %s · 대출 상환 하루 %s × %d일 (관리비 별도)", l.name, won(q.down), won(q.daily), q.days)
	afterMove(player, d, "내 집 마련 🏠 " .. l.name, msg, first)
	ctx.addStats(player, { happiness = 18, popularity = 5 }, nil, true)
	task.delay(8, function()
		if player.Parent == Players and Profiles.get(player) then
			Life.sendMessage(player, "banker", string.format("BNK부산은행 한주임입니다. 주택담보대출 %s 실행됐어요. 매일 %s씩 관리비와 함께 자동이체돼요. %d일 밀리면 경매로 넘어가니 통장 잔고 꼭 확인하세요!", won(q.total), won(q.daily), G.MORTGAGE.forecloseAfter))
		end
	end)
	return true, msg
end

local function homeEntrance(d: any): BasePart?
	local l = d.home and G.LISTINGS[d.home.listingId]
	return l and ctx.dest(l.place) or nil
end

-- Without the Housing module: the player stands at the building's Destination.
local function atHome(player: Player, d: any): boolean
	if not d.home then
		return false
	end
	if housingReady() and Housing.isAtHome(player) then
		return true
	end
	local pos = Util.rootPosition(player)
	local e = homeEntrance(d)
	return pos ~= nil and e ~= nil and (pos - e.Position).Magnitude <= 60
end

local function canTeleport(player: Player): boolean
	if ctx.isRiding(player) then
		ctx.notify(player, "info", "택시 이용 중", "택시에서 내린 뒤 이용해 주세요")
		return false
	end
	if ctx.venueBusy(player) then
		return false
	end
	return true
end

-- Legacy fallback: teleport to the building's Destination.
local function goHomeLegacy(player: Player, d: any, quiet: boolean): boolean
	local target = homeEntrance(d)
	if not target then
		if not quiet then
			ctx.notify(player, "home", "집을 찾을 수 없어요", "지도에서 집 위치를 확인해 주세요")
		end
		return false
	end
	ctx.allowTeleport(player, 8)
	ctx.jobsResetPosition(player)
	local ok = Util.teleportTo(player, target, 6)
	if ok and not quiet then
		ctx.notify(player, "home", "집 앞이에요 🏠", "여기서 폰으로 '잠자기'가 가능하고, 쓰러지면 집에서 다시 시작해요.")
	end
	return ok
end

local function goHome(player: Player, d: any, quiet: boolean, via: string): boolean
	if housingReady() then
		local ok, res, why = pcall(Housing.enter, player, via, quiet)
		if ok and res then
			return true
		end
		if not ok then
			warn("[GwangalliGameplay] Housing.enter failed: " .. tostring(res))
		elseif why ~= "noInstance" then
			return false
		end
	end
	return goHomeLegacy(player, d, quiet)
end

function Life.enterHome(player: Player)
	local d = Profiles.get(player)
	if not d then
		return
	end
	if not d.home then
		ctx.notify(player, "home", "집이 없어요", "부동산 앱이나 광안역 부동산(정실장)에서 집을 구해 보세요")
		return
	end
	if not Util.cooldown(player, "homeTp", 5) or not canTeleport(player) then
		return
	end
	goHome(player, d, false, "phone")
end

function Life.leaveHome(player: Player)
	local d = Profiles.get(player)
	if not d then
		return
	end
	if not Util.cooldown(player, "homeTp", 5) then
		return
	end
	if housingReady() then
		Housing.leave(player)
		return
	end
	ctx.notify(player, "home", "집 밖이에요", "이미 밖에 있어요")
end

function Life.sleep(player: Player)
	local d = Profiles.get(player)
	local s = S(player)
	if not d then
		return
	end
	if not d.home then
		ctx.notify(player, "home", "잘 곳이 없어요", "먼저 집을 구해야 해요 (고시원은 보증금 없이 바로 입주!)")
		return
	end
	if not atHome(player, d) then
		ctx.notify(player, "home", "집이 아니에요", "집에 가서 잘 수 있어요 (폰 → 집으로 가기)")
		return
	end
	if ctx.onShift(player) then
		ctx.notify(player, "home", "근무 중이에요", "근무를 끝내고 자요")
		return
	end
	local left = G.SLEEP_COOLDOWN - (os.clock() - s.lastSleep)
	if left > 0 then
		ctx.notify(player, "home", "아직 졸리지 않아요", G.format.seconds(left) .. " 후에 다시 잘 수 있어요")
		return
	end
	s.lastSleep = os.clock()
	local comfort = G.homeComfort(d)
	local standUp: (() -> ())? = nil
	if housingReady() then
		local ok, fn = pcall(Housing.sleepPose, player)
		if ok then
			standUp = fn
		end
	end
	task.spawn(function()
		Util.fade(player, true, 0.8, "Zzz… 😴")
		task.wait(1.6)
		if player.Parent ~= Players then
			return
		end
		local d2 = Profiles.get(player)
		if not d2 then
			return
		end
		local st = d2.stats
		ctx.addStats(player, { stamina = 100 - (st.stamina or 0), happiness = 8 + comfort }, nil, true)
		-- 피로도 (Health module): a night at home clears most of it
		local restedText = ""
		if ctx.health and type(ctx.health.rest) == "function" then
			local before = (st.fatigue or 0)
			local okRest, after = pcall(ctx.health.rest, player, (G.HEALTH and G.HEALTH.fatigue.sleep) or 70, "sleep")
			if okRest and type(after) == "number" and before - after >= 1 then
				restedText = string.format(" · 피로도 -%d", math.floor(before - after + 0.5))
			end
		end
		Life.advance(player, G.SLEEP_ADVANCE)
		if standUp then
			pcall(standUp)
		end
		Util.fade(player, false, 0.8)
		ctx.notify(player, "home", "푹 잤어요! ☀️", string.format("체력 회복 · 행복 +%d%s%s · 좋은 아침이에요", 8 + comfort, if comfort > 0 then string.format(" (편안함 +%d)", comfort) else "", restedText))
	end)
end

-- Advances the player's own day / rent clock by `seconds`.
function Life.advance(player: Player, seconds: number)
	local d = Profiles.get(player)
	local s = S(player)
	if not d then
		return
	end
	s.dayProgress += seconds
	local dayChanged = false
	while s.dayProgress >= G.DAY_SECONDS do
		s.dayProgress -= G.DAY_SECONDS
		d.lifeDay = (d.lifeDay or 1) + 1
		dayChanged = true
	end
	local hadHome = d.home ~= nil
	local listing = d.home and G.LISTINGS[d.home.listingId]
	local listingName = listing and listing.name or nil
	local events, warned = G.homeTick(d, seconds, os.time(), s.warned)
	s.warned = warned
	if #events > 0 and housingReady() then
		pcall(Housing.onHomeEvents, player, d, events, listingName)
	end
	local lost: string? = nil
	for _, e in events do
		if e.kind == "charged" then
			local body = if d.home and d.home.owned then (if e.loan then string.format("관리비 + 대출 상환 %s", won(e.loan)) else "관리비가 빠져나갔어요") else "오늘 월세가 빠져나갔어요"
			ctx.notify(player, "money", "자동이체 -" .. won(e.amount), body, { sound = "cash" })
		elseif e.kind == "warn" then
			Life.sendMessage(player, "landlord", string.format("곧 %s 빠져나가요. 통장 잔고가 부족하니 확인 부탁해요!", won(e.amount)))
		elseif e.kind == "missed" then
			if e.loan then
				Life.sendMessage(player, "banker", string.format("대출 상환금이 밀렸어요 (%d일째, %s). %d일 밀리면 집이 경매로 넘어가요!", e.missed, won(e.amount), G.MORTGAGE.forecloseAfter), "rent")
			else
				Life.sendMessage(player, "landlord", string.format("월세가 밀렸어요 (%d일째, %s). %d일 밀리면 퇴거예요!", e.missed, won(e.amount), G.EVICT_AFTER), "rent")
			end
			ctx.addStats(player, { happiness = -5 }, nil, true)
		elseif e.kind == "evicted" then
			Life.sendMessage(player, "landlord", "월세가 계속 밀려서 계약을 해지합니다. 짐 빼 주세요.")
			ctx.notify(player, "warn", "퇴거당했어요 😢", "월세를 못 내서 집을 잃었어요. 보증금은 돌려받지 못해요. 가구는 창고에 있어요.")
			ctx.addStats(player, { happiness = -15 }, nil, true)
			lost = "evicted"
		elseif e.kind == "foreclosed" then
			Life.sendMessage(player, "banker", string.format("대출 상환이 %d일 밀려 집이 경매로 넘어갔어요. 정산금 %s을 통장으로 보내드렸어요.", G.MORTGAGE.forecloseAfter, won(e.refund or 0)))
			ctx.notify(player, "warn", "경매로 집을 잃었어요 😢", string.format("정산금 %s · 가구는 창고에 있어요", won(e.refund or 0)))
			ctx.addStats(player, { happiness = -20 }, nil, true)
			lost = "foreclosed"
		elseif e.kind == "loanPaid" then
			Life.sendMessage(player, "banker", "마지막 대출 상환금이 들어왔어요. 주택담보대출 완납을 축하드려요! 🎉")
			ctx.addStats(player, { happiness = 10 }, "대출 완납 🎉")
		end
	end
	if lost and housingReady() then
		pcall(Housing.onHomeChanged, player, lost)
	end
	if #events > 0 or hadHome ~= (d.home ~= nil) then
		player:SetAttribute(G.Attr.HomeTier, d.home and d.home.tier or 0)
		ctx.changed(player, "home", "cash", "bank", "housing")
		ctx.refreshAttributes(player)
	elseif d.home then
		-- keep the dueIn countdown fresh on the client about once a minute
		if math.floor(d.home.dueIn / 60) ~= math.floor((d.home.dueIn + seconds) / 60) then
			ctx.changed(player, "home")
		end
	end
	if dayChanged then
		ctx.changed(player, "home")
	end
end

-------------------------------------------------------------------------------------------------
-- Club / friends
-------------------------------------------------------------------------------------------------
function Life.hasClubPass(player: Player): boolean
	return os.clock() < S(player).clubPassUntil
end

function Life.clubInvited(player: Player): boolean
	return S(player).invited
end

-- The club door's wristband (Club.server reads ClubOceanWristbandUntil: valid wristband = the door
-- opens and nobody walks you back out). Server time; one pass = G.CLUB.passSeconds.
local function putWristband(player: Player)
	local now = workspace:GetServerTimeNow()
	local untilT = now + G.CLUB.passSeconds
	local cur = player:GetAttribute("ClubOceanWristbandUntil")
	if type(cur) == "number" and cur > untilT then
		untilT = cur
	end
	player:SetAttribute("ClubOceanWristbandUntil", math.floor(untilT))
	player:SetAttribute("ClubOceanWristband", math.floor(now))
end

local function grantPass(player: Player, d: any, atDoor: boolean?)
	local s = S(player)
	s.clubPassUntil = os.clock() + G.CLUB.passSeconds
	s.invited = false
	player:SetAttribute("ClubGuestList", true)
	if d.daily.clubDay ~= d.lifeDay then
		d.daily.clubDay = d.lifeDay
		ctx.addStats(player, G.CLUB.entryGain, "CLUB OCEAN 입장 🎶")
	end
	putWristband(player)
	if not atDoor then
		Life.setWaypoint(player, "CLUB OCEAN 광안")
	end
end

-- Server-only API for the club scripts (ServerStorage.GwangalliGameplayAPI, the BindableFunction
-- ClubShared.Names.GameplayAPI names). Club.server and GwangalliClub call it; clients cannot see it.
--   "spend" (amount, label, prefer?) -> bool   ledger payment (prefer "bank": bank first, cash fallback)
--   "addStats" (delta, label)                    "balance" () -> cash, bank
--   "clubState" () -> { pass, invited, appearance, vip, guestList }
--   "clubGrant" (atDoor?) -> true                 pass + wristband (door payment / free entry)
--   "allowTeleport" (seconds)                     the walk-out teleport is not a cheat
local function setupClubApi()
	local ServerStorage = game:GetService("ServerStorage")
	local f = ServerStorage:FindFirstChild("GwangalliGameplayAPI")
	if f and not f:IsA("BindableFunction") then
		f:Destroy()
		f = nil
	end
	if not f then
		f = Instance.new("BindableFunction")
		f.Name = "GwangalliGameplayAPI"
		f.Parent = ServerStorage
	end
	local function num(v: any): number?
		return if type(v) == "number" and v == v and v > -math.huge and v < math.huge then v else nil
	end
	(f :: BindableFunction).OnInvoke = function(op: any, player: any, a: any, b: any, c: any): any
		if type(op) ~= "string" or typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
			return nil
		end
		local d = Profiles.get(player)
		if op == "spend" then
			local amount = num(a)
			if not d or not amount or amount < 0 or amount % 1 ~= 0 then
				return false
			end
			local label = if type(b) == "string" then string.sub(b, 1, 80) else "CLUB OCEAN"
			return ctx.spend(player, amount, label, false, if c == "bank" or c == "cash" then c else nil) == true
		elseif op == "addStats" then
			if d and type(a) == "table" then
				local delta = {}
				for k, v in a do
					if type(k) == "string" and num(v) then
						delta[k] = math.clamp(v, -20, 20)
					end
				end
				ctx.addStats(player, delta, if type(b) == "string" then string.sub(b, 1, 80) else nil)
			end
			return true
		elseif op == "balance" then
			if not d then
				return nil
			end
			return d.cash or 0, d.bank or 0
		elseif op == "clubState" then
			if not d then
				return nil
			end
			local s = S(player)
			local app = d.stats.appearance or 0
			return {
				pass = Life.hasClubPass(player),
				invited = s.invited,
				appearance = app,
				vip = app >= G.CLUB.vipAppearance,
				guestList = s.invited or app >= G.CLUB.entryAppearance,
				cover = G.CLUB.cover,
			}
		elseif op == "clubGrant" then
			if not d then
				return false
			end
			grantPass(player, d, a == true)
			return true
		elseif op == "allowTeleport" then
			local sec = num(a)
			if sec then
				ctx.allowTeleport(player, math.clamp(sec, 1, 15))
			end
			return true
		end
		return nil
	end
end

function Life.clubAction(player: Player, choiceId: string): string?
	local d = Profiles.get(player)
	if not d then
		return nil
	end
	local s = S(player)
	if choiceId == "entry" then
		if Life.hasClubPass(player) then
			return "이미 입장 팔찌 있으시네요!"
		end
		if s.invited or (d.stats.appearance or 0) >= G.CLUB.entryAppearance then
			grantPass(player, d)
			return "입장 팔찌 채워 드렸어요. 즐기세요! 🥳"
		end
		return "죄송해요, 입장료를 내셔야 해요."
	elseif choiceId == "cover" then
		if Life.hasClubPass(player) then
			return "이미 입장하셨어요!"
		end
		if not ctx.spend(player, G.CLUB.cover, "CLUB OCEAN 입장료") then
			return string.format("입장료 %s이 부족해요.", won(G.CLUB.cover))
		end
		grantPass(player, d)
		return "입장료 확인했어요. 즐기세요! 🎶"
	elseif choiceId == "vip" then
		if not Life.hasClubPass(player) then
			if s.invited or (d.stats.appearance or 0) >= G.CLUB.entryAppearance then
				grantPass(player, d)
			else
				return "먼저 입장부터 하셔야 해요."
			end
		end
		if not ctx.spend(player, G.CLUB.vipTable, "CLUB OCEAN VIP 테이블") then
			return string.format("VIP 테이블은 %s이에요. 잔액이 부족해요.", won(G.CLUB.vipTable))
		end
		player:SetAttribute("ClubVIPTable", true)
		ctx.addStats(player, G.CLUB.vipTableGain, "VIP 테이블 🍾")
		return "VIP 테이블 세팅 완료! 오늘 주인공은 당신이에요 🍾"
	end
	return nil
end

function Life.meetPending(player: Player, npcId: string): boolean
	local m = S(player).meet
	return m ~= nil and m.contact == npcId and os.clock() < m.untilT
end

function Life.friendChat(player: Player, contact: string, npcId: string, remote: boolean): string
	local s = S(player)
	local last = s.chat[contact] or -math.huge
	if Life.meetPending(player, npcId) and not remote then
		s.meet = nil
		s.chat[contact] = os.clock()
		ctx.addStats(player, { happiness = 12, popularity = 2 }, "치맥 타임 🍗🍺")
		if ctx.health and type(ctx.health.rest) == "function" then
			pcall(ctx.health.rest, player, (G.HEALTH and G.HEALTH.fatigue.meal) or 6, "meal") -- 피로도 relief (Health module)
		end
		return "역시 광안리는 치맥이지! 오늘 즐거웠다 😆"
	end
	if os.clock() - last < G.FRIEND_CHAT_COOLDOWN then
		return "ㅋㅋ 아까도 얘기했잖아~ 이따 또 보자!"
	end
	s.chat[contact] = os.clock()
	if remote then
		ctx.addStats(player, { happiness = 2 }, "친구와 통화 📞")
		return "통화 즐거웠어! 조만간 보자 👋"
	end
	ctx.addStats(player, { happiness = 6, popularity = 0.5 }, "친구와 수다 💬")
	return "역시 너랑 얘기하면 재밌어 ㅋㅋ"
end

-------------------------------------------------------------------------------------------------
-- Phone calls
-------------------------------------------------------------------------------------------------
function Life.callContact(player: Player, contact: any)
	local cid = G.resolveContact(contact)
	local d = Profiles.get(player)
	if not cid or not d then
		return
	end
	local c = G.CONTACTS[cid]
	if cid == "taxi" then
		ctx.callTaxi(player, {})
		return
	end
	if c.npc and G.NPCS[c.npc] then
		ctx.openDialog(player, c.npc, true)
		return
	end
	if cid == "landlord" then
		if d.home and not d.home.owned then
			ctx.notify(player, "home", "집주인 📞", string.format("하루 월세 %s · 다음 이체까지 %s%s", won(G.homeDaily(d.home.listingId)), G.format.seconds(d.home.dueIn or 0), if (d.home.missed or 0) > 0 then string.format(" · 연체 %d일", d.home.missed) else ""))
		else
			ctx.notify(player, "home", "집주인 📞", "연락할 집주인이 없어요")
		end
		return
	end
	ctx.notify(player, "info", c.name .. " 📞", "헬스장에서 봐요! 운동하면 외모지수도 올라가요 💪")
end

-------------------------------------------------------------------------------------------------
-- Ticks
-------------------------------------------------------------------------------------------------
local OFFER_GAP = 45

local function offersTick(player: Player, d: any, s: Sess)
	if s.online - s.lastOffer < OFFER_GAP then
		return
	end
	local env = ctx.env()
	local state = {
		online = s.online,
		hasJob = d.job ~= nil,
		hasHome = d.home ~= nil,
		shifts = d.shifts or 0,
		night = env.night,
		lastSent = nil :: number?,
	}
	local now = os.time()
	for _, id in G.OFFER_ORDER do
		local o = G.OFFERS[id]
		local t = d.messages.threads[o.contact]
		if not (t and t.offer) and not d.offers[id] then
			state.lastSent = d.offersSent[id]
			if G.offerDue(id, state, now) then
				-- skip job offers for the job the player already has
				if not (o.action and o.action.type == "applyJob" and d.job and d.job.id == o.action.job) then
					s.lastOffer = s.online
					sendOffer(player, d, id)
					return
				end
			end
		end
	end
end

local TICK = 1

local function tick()
	for player, s in sessions do
		if player.Parent ~= Players then
			continue
		end
		local d = Profiles.get(player)
		if not d then
			continue
		end
		s.online += TICK
		Life.advance(player, TICK)
		s.decayT += TICK
		if s.decayT >= G.HAPPINESS_DECAY_EVERY then
			s.decayT = 0
			ctx.addStats(player, { happiness = -G.HAPPINESS_DECAY }, nil, true)
		end
		s.regenT += TICK
		if s.regenT >= 60 then
			s.regenT = 0
			if not ctx.onShift(player) and (d.stats.stamina or 0) < 60 then
				ctx.addStats(player, { stamina = 1 }, nil, true)
			end
		end
		if Life.hasClubPass(player) == false and player:GetAttribute("ClubGuestList") == true and not s.invited then
			player:SetAttribute("ClubGuestList", (d.stats.appearance or 0) >= G.CLUB.entryAppearance)
		end
		local ok, err = pcall(offersTick, player, d, s)
		if not ok then
			warn("[GwangalliGameplay] offers failed: " .. tostring(err))
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Player lifecycle
-------------------------------------------------------------------------------------------------
function Life.onLoaded(player: Player)
	local d = Profiles.get(player)
	local s = S(player)
	if not d then
		return
	end
	player:SetAttribute(G.Attr.HomeTier, d.home and d.home.tier or 0)
	player:SetAttribute("ClubGuestList", (d.stats.appearance or 0) >= G.CLUB.entryAppearance)
	-- club door wristband (set by the club) and bowling results make the player happier
	player:GetAttributeChangedSignal("ClubOceanWristband"):Connect(function()
		local dd = Profiles.get(player)
		if dd and player:GetAttribute("ClubOceanWristband") and dd.daily.clubDay ~= dd.lifeDay then
			dd.daily.clubDay = dd.lifeDay
			ctx.addStats(player, G.CLUB.entryGain, "CLUB OCEAN 입장 🎶")
		end
	end)
	player:GetAttributeChangedSignal(G.Attr.LastBowlingScore):Connect(function()
		if Util.cooldown(player, "bowlHappy", 60) then
			ctx.addStats(player, { happiness = 4 }, "볼링 한 게임 🎳")
		end
	end)
	local _ = s
end

function Life.onCharacter(player: Player)
	local s = S(player)
	s.inUnit = false
	if housingReady() then
		pcall(Housing.onCharacter, player)
	end
	local first = not s.spawned
	s.spawned = true
	if first then
		return
	end
	-- respawn at home (after the character settles)
	task.delay(1.5, function()
		local d = Profiles.get(player)
		if player.Parent ~= Players or not d or not d.home then
			return
		end
		if ctx.isRiding(player) then
			return
		end
		pcall(goHome, player, d, true, "respawn")
	end)
end

function Life.onLeave(player: Player)
	if housingReady() then
		local ok, err = pcall(Housing.onLeave, player)
		if not ok then
			warn("[GwangalliGameplay] housing cleanup failed: " .. tostring(err))
		end
	end
	sessions[player] = nil
end

function Life.session(player: Player): Sess
	return S(player)
end

function Life.init(context: any)
	ctx = context
	G = context.G
	Util = context.Util
	Profiles = context.Profiles
	do
		local okApi, errApi = pcall(setupClubApi) -- the club scripts' money / pass API (club section)
		if not okApi then
			warn("[GwangalliGameplay] club API setup failed: " .. tostring(errApi))
		end
	end
	do
		local m = script.Parent and script.Parent:FindFirstChild("Housing")
		if m and m:IsA("ModuleScript") then
			local ok, res = pcall(require, m)
			if ok and type(res) == "table" then
				local okInit, err = pcall(res.init, context, Life)
				if okInit then
					Housing = res
				else
					warn("[GwangalliGameplay] Housing init failed: " .. tostring(err))
				end
			else
				warn("[GwangalliGameplay] Housing failed to load: " .. tostring(res))
			end
		end
	end
	task.spawn(function()
		while true do
			task.wait(TICK)
			local ok, err = pcall(tick)
			if not ok then
				warn("[GwangalliGameplay] life tick failed: " .. tostring(err))
			end
		end
	end)
end

return Life
