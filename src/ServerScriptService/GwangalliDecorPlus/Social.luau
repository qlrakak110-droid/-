--!strict
-- GwangalliDecorPlus/Social: 집들이 — ❤️ 좋아요 (guest -> owner, once per 20 h per guest), filtered 📝 방명록,
-- 📸 집 사진 rewards, and the owner's 인테리어 점수 / 뱃지 / 목표 (Score) with small life-game stat rewards.
--   Social.init(deps) / Social.after(H) (re-evaluates badges + goals, pushes the new score)
--   Social.like(guest, H) / Social.write(guest, H, text) / Social.erase(owner, H, t, u) / Social.photo(p, H)
--   Social.state(p, H) -> guest-facing summary

local Players = game:GetService("Players")
local TextService = game:GetService("TextService")

local Shared = require(game:GetService("ReplicatedStorage"):WaitForChild("GwangalliDecorShared"))
local Config, Score, Text = Shared.Config, Shared.Score, Shared.Text

local Social = {}

local Host: any, Store: any, Homes: any, push: any = nil, nil, nil, nil
local likeSeen: { [number]: { [number]: number } } = {} -- owner -> guest -> os.time()
local likeRewards: { [number]: { day: number, n: number } } = {}

function Social.init(deps: any)
	Host, Store, Homes, push = deps.Host, deps.Store, deps.Homes, deps.push
end

local function day(): number
	return math.floor((os.time() + 9 * 3600) / 86400) -- KST day
end

local function summary(r: any): any
	return {
		total = r.total,
		grade = r.grade.name,
		icon = r.grade.icon,
		next = r.next and r.next.min or nil,
		nextName = r.next and r.next.name or nil,
		parts = r.parts,
	}
end
Social.summary = summary

function Social.goalsView(data: any, r: any): { any }
	local out = {}
	for _, g in Score.GOALS do
		local v, done = Score.goalProgress(g, r)
		table.insert(out, { id = g.id, name = g.name, icon = g.icon, target = g.target, value = v, done = done or data.goals[g.id] ~= nil, reward = Score.rewardText(g.reward) })
	end
	return out
end

function Social.badgesView(data: any): { any }
	local out = {}
	for _, b in Score.BADGES do
		table.insert(out, { id = b.id, name = b.name, icon = b.icon, desc = b.desc, t = data.badges[b.id] })
	end
	return out
end

-- after any change of the owner's home: new badges, finished goals, score push
function Social.after(H: any)
	local owner = H.owner
	if not owner or owner.Parent ~= Players then
		return
	end
	local data = H.data
	local r = Homes.score(H)
	data.best = math.max(data.best or 0, r.total)
	for _, id in Score.badgesEarned(r, data.badges) do
		data.badges[id] = os.time()
		local b = Score.BADGE_BY_ID[id]
		push(owner, { kind = "badge", id = id, name = b.name, icon = b.icon, desc = b.desc })
		Store.dirty(owner)
	end
	for _, g in Score.GOALS do
		if not data.goals[g.id] then
			local _, done = Score.goalProgress(g, r)
			if done then
				data.goals[g.id] = os.time()
				Host.addStats(owner, g.reward, "🏠 인테리어 목표 · " .. g.name)
				push(owner, { kind = "goal", id = g.id, name = g.name, icon = g.icon, reward = Score.rewardText(g.reward) })
				Store.dirty(owner)
			end
		end
	end
	push(owner, { kind = "score", score = summary(r), goals = Social.goalsView(data, r) })
	-- the home model shows the score to visitors
	H.model:SetAttribute("DPScore", r.total)
	H.model:SetAttribute("DPLikes", data.likes)
end

function Social.like(guest: Player, H: any): (boolean, string?, any?)
	if guest == H.owner then
		return false, "notGuest", nil
	end
	local seen = likeSeen[H.ownerId]
	if not seen then
		seen = {}
		likeSeen[H.ownerId] = seen
	end
	local t = seen[guest.UserId]
	if t and os.time() - t < Config.LIKE_DEDUPE_HOURS * 3600 then
		return false, "liked", nil
	end
	seen[guest.UserId] = os.time()
	H.data.likes += 1
	Store.saveSoon(H.owner)
	local rw = likeRewards[H.ownerId]
	if not rw or rw.day ~= day() then
		rw = { day = day(), n = 0 }
		likeRewards[H.ownerId] = rw
	end
	if rw.n < Config.LIKE_OWNER_DAILY then
		rw.n += 1
		Host.addStats(H.owner, Config.REWARDS.like, "❤️ 집들이 좋아요")
	end
	push(H.owner, { kind = "liked", by = guest.DisplayName, likes = H.data.likes })
	Host.notify(H.owner, Text.fmt(Text.TOAST.likedOwner, guest.DisplayName, H.data.likes), "")
	Social.after(H)
	return true, nil, { likes = H.data.likes }
end

function Social.likedToday(guest: Player, H: any): boolean
	local seen = likeSeen[H.ownerId]
	local t = seen and seen[guest.UserId]
	return t ~= nil and os.time() - t < Config.LIKE_DEDUPE_HOURS * 3600
end

local function canChat(p: Player): boolean
	local ok, r = pcall(function()
		return (game:GetService("Chat") :: any):CanUserChatAsync(p.UserId)
	end)
	if not ok then
		return true -- service missing in this engine: the filter below still applies
	end
	return r == true
end

local function filter(text: string, from: Player): string?
	local ok, res = pcall(function()
		return TextService:FilterStringAsync(text, from.UserId, Enum.TextFilterContext.PublicChat)
	end)
	if not ok or not res then
		return nil
	end
	local ok2, s = pcall(function()
		return (res :: any):GetNonChatStringForBroadcastAsync()
	end)
	if ok2 and type(s) == "string" then
		return s
	end
	return nil
end
Social.filter = filter

function Social.filterForUser(text: string, from: Player): string?
	local ok, res = pcall(function()
		return TextService:FilterStringAsync(text, from.UserId, Enum.TextFilterContext.PrivateChat)
	end)
	if not ok or not res then
		return nil
	end
	local ok2, s = pcall(function()
		return (res :: any):GetNonChatStringForUserAsync(from.UserId)
	end)
	if ok2 and type(s) == "string" then
		return s
	end
	return nil
end

function Social.write(guest: Player, H: any, raw: any): (boolean, string?, any?)
	if guest == H.owner then
		return false, "notGuest", nil
	end
	local text = Text.clip(raw, Config.GUESTBOOK_LEN)
	if text == "" then
		return false, "empty", nil
	end
	if not canChat(guest) then
		return false, "noChat", nil
	end
	local clean = filter(text, guest)
	if not clean then
		return false, "filtered", nil
	end
	if not H.model.Parent or not H.owner.Parent then
		return false, "notGuest", nil
	end
	local e = { u = guest.UserId, n = guest.DisplayName, m = clean, t = os.time() }
	table.insert(H.data.gb, 1, e)
	while #H.data.gb > Config.GUESTBOOK_MAX do
		table.remove(H.data.gb)
	end
	Store.saveSoon(H.owner)
	push(H.owner, { kind = "guestbook", entry = e })
	Host.notify(H.owner, Text.fmt(Text.TOAST.gbOwner, guest.DisplayName, clean), "")
	Social.after(H)
	return true, nil, { entries = H.data.gb }
end

function Social.erase(owner: Player, H: any, t: any, u: any): (boolean, string?, any?)
	if owner ~= H.owner then
		return false, "notOwner", nil
	end
	for i, e in H.data.gb do
		if e.t == t and e.u == u then
			table.remove(H.data.gb, i)
			Store.saveSoon(owner)
			return true, nil, { entries = H.data.gb }
		end
	end
	return false, "bad", nil
end

-- 📸 집 사진: everyone inside a home may shoot; the first PHOTO_DAILY a day give a small reward
function Social.photo(p: Player, H: any): (boolean, string?, any?)
	local data = Store.get(p)
	if not data then
		return false, "noData", nil
	end
	local d = day()
	if data.photo.d ~= d then
		data.photo = { d = d, n = 0 }
	end
	data.stats.photos = (data.stats.photos or 0) + 1
	Store.dirty(p)
	local gain = false
	if data.photo.n < Config.PHOTO_DAILY then
		data.photo.n += 1
		gain = true
		Host.addStats(p, Config.REWARDS.photo, "📸 집 사진")
	end
	local own = Homes.ofOwner(p)
	if own then
		Social.after(own)
	end
	return true, nil, { gain = gain, left = Config.PHOTO_DAILY - data.photo.n }
end

-- summary for visitors (and the owner's own pill)
function Social.state(p: Player, H: any): any
	local r = Homes.score(H)
	return {
		ownerId = H.ownerId,
		ownerName = H.owner.DisplayName,
		homeName = Host.listingName(H.listingId),
		likes = H.data.likes,
		liked = Social.likedToday(p, H),
		gb = H.data.gb,
		score = summary(r),
		isOwner = p == H.owner,
		items = #H.home.items,
	}
end

function Social.drop(p: Player)
	likeSeen[p.UserId] = nil
	likeRewards[p.UserId] = nil
end

return Social
