-- GwangalliGameplay/Goals (server, feature module; owner: goals): "조금만 더 하면 다음 걸 얻는다" — the
-- next goals a player is close to, always on screen (client StarterPlayerScripts.GwangalliGoals).
-- No waiting timers: every goal is a real target from the systems that already exist.
--
--   money   the next car (GwangalliGarageShared.CATALOG: the cheapest 중고 first, then the next class up)
--           and the next home (G.LISTINGS: the next tier's deposit + a day of rent, or the price)
--   work    the closest 알바 level-up: the work tracks (d.work.xp, GwangalliWorkShared) and the legacy
--           job careers (d.careerXp, G.JOBS levels)
--   people  the NPC whose 호감도 is closest to the next relationship tier (ctx.social snapshot)
--   law     the active 수배 (top priority while it lasts) / the 유치장 timer, the next crime level and
--           what it unlocks (GwangalliLawShared), the next police rank for cops
-- Each goal: { id, icon, text, sub?, pct 0..1, pri }; sorted by priority then by how close it is.
-- REMOTE: ReplicatedStorage.GwangalliGoals.Goals (RemoteEvent) server -> client { goals = {...} } every
-- few seconds (and when asked: client FireServer("refresh")).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Goals = {}

local ctx: any
local G: any
local GS: any = nil -- GwangalliGarageShared
local WS: any = nil -- GwangalliWorkShared
local LS: any = nil -- GwangalliLawShared
local Social: any = nil -- GwangalliSocialShared
local Citizens: any = nil
local remote: RemoteEvent

local function optional(name: string): any
	local m = ReplicatedStorage:FindFirstChild(name)
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			return res
		end
	end
	return nil
end

local function won(n: number): string
	local s = tostring(math.floor(math.abs(n)))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return out .. "원"
end

local TRACK_NAME = { cafe = "카페", cvs = "편의점", kitchen = "주방", delivery = "배달" }

local function compute(player: Player): { any }
	local d = ctx.Profiles and ctx.Profiles.get(player)
	if not d then
		return {}
	end
	local out = {}
	local money = (d.cash or 0) + (d.bank or 0)
	-- law first: an active chase or the cell beats everything
	local jail = player:GetAttribute("LawJail")
	if type(jail) == "number" and jail > 0 then
		local left = math.max(0, jail - workspace:GetServerTimeNow())
		table.insert(out, { id = "jail", icon = "🔒", text = string.format("유치장 남은 시간 %02d:%02d", left // 60, math.floor(left % 60)), sub = "공기놀이·운동으로 시간을 줄일 수 있어요", pct = 0, pri = 200 })
	end
	local stars = player:GetAttribute("GwangalliWanted") or 0
	if stars > 0 then
		local search = player:GetAttribute("LawSearch") or 0
		table.insert(out, { id = "wanted", icon = "🚨", text = "현재 경찰 수배 " .. stars .. "단계", sub = if player:GetAttribute("PoliceChase") then "추격 중! 시야에서 벗어나세요" else "수배 감소까지 " .. math.floor((1 - search) * 100) .. "%", pct = search, pri = 150 })
	end
	-- the tank of the car you are using
	if ctx.fuel and type(ctx.fuel.level) == "function" then
		local lv = ctx.fuel.level(player)
		if lv and lv < 25 then
			table.insert(out, { id = "fuel", icon = "⛽", text = "연료 " .. math.floor(lv) .. "% — 주유가 필요해요", sub = "SK 광안셀프주유소 · 1% " .. (ctx.fuel.FUEL and ctx.fuel.FUEL.pricePerPct or 180) .. "원", pct = lv / 100, pri = if lv < 8 then 90 else 70 })
		end
	end
	-- the next car
	if GS and GS.CATALOG then
		local best = 0
		for _, c in (type(d.cars) == "table" and d.cars or {}) do
			local cat = type(c) == "table" and GS.CATALOG[c.kind]
			if cat and not c.rental then
				best = math.max(best, if c.grade == "new" then cat.new else cat.used)
			end
		end
		local target, tPrice, tGrade = nil, math.huge, ""
		for kind, cat in GS.CATALOG do
			for _, grade in { "used", "new" } do
				local price = cat[grade]
				if price and price > best and price < tPrice then
					target, tPrice, tGrade = kind, price, grade
				end
			end
		end
		if target then
			local cat = GS.CATALOG[target]
			local name = (if tGrade == "used" then "중고 " else "신차 ") .. cat.label
			if money >= tPrice then
				table.insert(out, { id = "car", icon = cat.glyph or "🚗", text = name .. " 구매 가능!", sub = "정비소 / 휴대폰에서 살 수 있어요", pct = 1, pri = 60 })
			else
				table.insert(out, { id = "car", icon = cat.glyph or "🚗", text = name .. " 구매까지 " .. won(tPrice - money), sub = "가격 " .. won(tPrice), pct = money / tPrice, pri = 50 })
			end
		end
	end
	-- the next home
	if G and G.LISTINGS then
		local curTier = 0
		local h = d.home
		if type(h) == "table" and h.listingId and G.LISTINGS[h.listingId] then
			curTier = G.LISTINGS[h.listingId].tier or 0
		end
		local nextL, nextId = nil, nil
		for id, l in G.LISTINGS do
			if (l.tier or 0) > curTier and (not nextL or l.tier < nextL.tier) then
				nextL, nextId = l, id
			end
		end
		if nextL then
			local need = if nextL.kind == "rent" then (nextL.deposit or 0) + (nextL.rentPerDay or 0) else (nextL.price or 0)
			local verb = if nextL.kind == "rent" then "계약" else "구매"
			if need <= 0 or money >= need then
				table.insert(out, { id = "home", icon = nextL.icon or "🏠", text = "새 " .. (if nextL.kind == "rent" then "집" else "아파트") .. " " .. verb .. " 가능! (" .. nextL.name .. ")", sub = "휴대폰 부동산 앱", pct = 1, pri = 55 })
			else
				table.insert(out, { id = "home", icon = nextL.icon or "🏠", text = nextL.name .. " " .. verb .. "까지 " .. won(need - money), pct = money / need, pri = 40 })
			end
			local _ = nextId
		end
	end
	-- work: the closest level-up
	local bestWork = nil
	if WS and type(d.work) == "table" and type(d.work.xp) == "table" then
		for track, xp in d.work.xp do
			if type(xp) == "number" then
				local nxt, pct = WS.levelProgress(xp)
				if nxt then
					local lv = WS.level(xp)
					local g = { id = "work_" .. track, icon = "💼", text = (TRACK_NAME[track] or track) .. " 숙련도 Lv." .. (lv + 1) .. "까지 " .. math.ceil(nxt - xp) .. " XP", sub = WS.levelTitle(track, lv + 1) .. " 승급", pct = pct, pri = 45 }
					if not bestWork or pct > bestWork.pct then
						bestWork = g
					end
				end
			end
		end
	end
	if G and G.JOBS and type(d.careerXp) == "table" then
		for jobId, xp in d.careerXp do
			local job = G.JOBS[jobId]
			if job and type(xp) == "number" then
				local lv = G.jobLevel(jobId, xp)
				local nxt = job.levels[lv + 1]
				if nxt then
					local cur = job.levels[lv].xp
					local pct = math.clamp((xp - cur) / math.max(1, nxt.xp - cur), 0, 1)
					local g = { id = "job_" .. jobId, icon = job.icon or "💼", text = job.title .. " " .. nxt.title .. "까지 " .. math.ceil(nxt.xp - xp) .. " XP", sub = "시급 " .. won(nxt.wage), pct = pct, pri = 45 }
					if not bestWork or pct > bestWork.pct then
						bestWork = g
					end
				end
			end
		end
	end
	if bestWork then
		table.insert(out, bestWork)
	elseif not d.job then
		table.insert(out, { id = "work_first", icon = "💼", text = "첫 알바를 시작해 보세요", sub = "오른쪽 ☕ 알바 버튼 / 휴대폰 알바 앱", pct = 0, pri = 44 })
	end
	-- people: the NPC closest to the next tier
	if ctx.social and type(ctx.social.snapshot) == "function" and Social then
		local ok, snap = pcall(ctx.social.snapshot, player)
		if ok and type(snap) == "table" and type(snap.npcs) == "table" then
			local best, bestGap = nil, math.huge
			for id, r in snap.npcs do
				if type(r) == "table" and type(r.a) == "number" and r.met then
					local nextTier = Social.TIERS[(r.tier or 1) + 1]
					if nextTier then
						local gap = nextTier.min - r.a
						if gap > 0 and gap < bestGap then
							best, bestGap = { id = id, r = r, next = nextTier }, gap
						end
					end
				end
			end
			if best then
				local c = Citizens and Citizens.byId and Citizens.byId[best.id]
				local name = c and c.name or best.id
				local a = math.floor(best.r.a + 0.5)
				table.insert(out, { id = "npc", icon = "💗", text = name .. " 호감도 " .. a .. "/100", sub = best.next.name .. "까지 " .. math.ceil(bestGap), pct = math.clamp(best.r.a / math.max(1, best.next.min), 0, 1), pri = 42 })
			end
		end
	end
	-- crime career / police rank
	if LS and ctx.law then
		local L = ctx.law.data(player)
		if L.crimeXp > 0 then
			local lv, _, nxt = LS.crimeLevel(L.crimeXp)
			if nxt then
				local unlock = nil
				for _, id in LS.SMALL_ORDER do
					if LS.SMALL[id].level == lv + 1 then
						unlock = LS.SMALL[id].label
						break
					end
				end
				if not unlock then
					for _, id in LS.BIG_ORDER do
						if LS.BIG[id].level == lv + 1 then
							unlock = LS.BIG[id].label
							break
						end
					end
				end
				local cur = LS.CRIME_LEVELS[lv].xp
				table.insert(out, { id = "crime", icon = "🕶️", text = (if unlock then "새 범죄 '" .. unlock .. "' 해금까지 " else nxt.title .. "까지 ") .. "범죄 경험치 " .. math.ceil(nxt.xp - L.crimeXp), pct = math.clamp((L.crimeXp - cur) / math.max(1, nxt.xp - cur), 0, 1), pri = 30 })
			end
		end
		if L.copXp > 0 or player:GetAttribute("LawCop") == true then
			local _, rank, nxt = LS.copRank(L.copXp)
			if nxt then
				table.insert(out, { id = "cop", icon = "👮", text = nxt.title .. " 진급까지 XP " .. math.ceil(nxt.xp - L.copXp), sub = "지금 " .. rank.title .. " · 평판 " .. math.floor(L.rep), pct = math.clamp((L.copXp - rank.xp) / math.max(1, nxt.xp - rank.xp), 0, 1), pri = if player:GetAttribute("LawCop") == true then 47 else 31 })
			end
		end
		if (L.debt or 0) > 0 then
			table.insert(out, { id = "debt", icon = "🧾", text = "미납 벌금 " .. won(L.debt), sub = "현금 1만원 이상이 들어오면 자동으로 빠져나가요", pct = 0, pri = 35 })
		end
	end
	table.sort(out, function(a, b)
		local pa = a.pri + (if a.pct >= 1 then 8 else a.pct * 6)
		local pb = b.pri + (if b.pct >= 1 then 8 else b.pct * 6)
		return pa > pb
	end)
	while #out > 6 do
		table.remove(out)
	end
	return out
end
Goals.compute = compute

local function send(player: Player)
	local ok, list = pcall(compute, player)
	if ok then
		remote:FireClient(player, { goals = list })
	else
		warn("[GwangalliGoals] " .. tostring(list))
	end
end

function Goals.onLoaded(player: Player)
	task.delay(2, function()
		if player.Parent then
			send(player)
		end
	end)
end

function Goals.init(context: any)
	ctx = context
	G = context.G
	GS = optional("GwangalliGarageShared")
	WS = optional("GwangalliWorkShared")
	LS = optional("GwangalliLawShared")
	Social = optional("GwangalliSocialShared")
	Citizens = optional("GwangalliCitizens")
	local folder = ReplicatedStorage:FindFirstChild("GwangalliGoals")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "GwangalliGoals"
		folder.Parent = ReplicatedStorage
	end
	local r = (folder :: Instance):FindFirstChild("Goals")
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = "Goals"
		r.Parent = folder
	end
	remote = r :: RemoteEvent
	local last: { [Player]: number } = {}
	remote.OnServerEvent:Connect(function(player)
		if os.clock() - (last[player] or 0) > 2 then
			last[player] = os.clock()
			send(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		last[p] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(6)
			for _, p in Players:GetPlayers() do
				send(p)
			end
		end
	end)
end

return Goals
