--!strict
-- GwangalliDecorShared/Score: 인테리어 점수, 등급, 뱃지, 목표 (pure).
--   Score.compute(ctx) -> { total, grade, next, parts = { {label, value} } }
--      ctx = { items = {records}, finish, rooms = { [uid] = roomId }, likes, gb, stats, onLamps }
--   Score.grade(total) -> (grade, nextGrade?)
--   Score.BADGES / Score.badgesEarned(ctx, have) -> { ids }      Score.GOALS / Score.goalProgress(goal, ctx)

local Catalog = require(script.Parent:WaitForChild("Catalog"))
local Finish = require(script.Parent:WaitForChild("Finish"))

local Score = {}

Score.GRADES = {
	{ min = 0, name = "새내기 자취방", icon = "📦" },
	{ min = 40, name = "아늑한 집", icon = "🏠" },
	{ min = 100, name = "센스 있는 집", icon = "✨" },
	{ min = 200, name = "인테리어 고수", icon = "🎨" },
	{ min = 350, name = "잡지에 나올 집", icon = "📸" },
	{ min = 550, name = "광안리 랜드마크 하우스", icon = "🌉" },
}

function Score.grade(total: number): (any, any?)
	local g, nxt = Score.GRADES[1], nil
	for i, gr in Score.GRADES do
		if total >= gr.min then
			g = gr
			nxt = Score.GRADES[i + 1]
		end
	end
	return g, nxt
end

-- facts the badges and goals read
function Score.facts(ctx: any): any
	local items = ctx.items or {}
	local f: any = { count = #items, cats = {}, catCount = 0, plants = 0, lamps = 0, lampsOn = 0, rooms = {}, roomsDecorated = 0, styles = {}, ids = {} }
	for _, rec in items do
		local def = Catalog.get(rec.i)
		if def then
			if not f.cats[def.cat] then
				f.cats[def.cat] = 0
				f.catCount += 1
			end
			f.cats[def.cat] += 1
			f.styles[def.style] = (f.styles[def.style] or 0) + 1
			f.ids[rec.i] = (f.ids[rec.i] or 0) + 1
			if def.cat == "plants" or table.find(def.tags, "식물") then
				f.plants += 1
			end
			if Catalog.lightCount(rec.i) > 0 or def.glow then
				f.lamps += 1
				if rec.on ~= false then
					f.lampsOn += 1
				end
			end
			local room = ctx.rooms and ctx.rooms[rec.u]
			if room then
				f.rooms[room] = (f.rooms[room] or 0) + 1
			end
		end
	end
	for _, n in f.rooms do
		if n >= 3 then
			f.roomsDecorated += 1
		end
	end
	local fin = ctx.finish or {}
	f.finishRooms = 0
	f.finishWalls = 0
	for _, e in fin.rooms or {} do
		f.finishRooms += 1
		if e.w then
			f.finishWalls += 1
		end
	end
	f.light = fin.light
	f.likes = ctx.likes or 0
	f.gb = ctx.gb or 0
	f.stats = ctx.stats or {}
	return f
end

function Score.compute(ctx: any): any
	local f = Score.facts(ctx)
	local parts = {}
	local base = 0
	local copies: { [string]: number } = {}
	for _, rec in ctx.items or {} do
		local def = Catalog.get(rec.i)
		if def then
			local k = (copies[rec.i] or 0) + 1
			copies[rec.i] = k
			local w = if k == 1 then 1 elseif k == 2 then 0.6 elseif k == 3 then 0.35 else 0.2
			base += def.decor * w
		end
	end
	table.insert(parts, { label = "가구 · 소품", value = math.floor(base + 0.5) })
	local variety = f.catCount * 4
	table.insert(parts, { label = "다양한 카테고리", value = variety })
	local harmony = 0
	if f.count >= 6 then
		local top = 0
		for _, n in f.styles do
			top = math.max(top, n)
		end
		if top / f.count >= 0.5 then
			harmony = 12
		end
	end
	table.insert(parts, { label = "스타일 통일", value = harmony })
	local rooms = f.roomsDecorated * 6
	table.insert(parts, { label = "꾸민 방", value = rooms })
	local finish = Finish.decor(ctx.finish) * 2
	table.insert(parts, { label = "벽지 · 바닥 · 조명", value = finish })
	local light = math.min(f.lampsOn, 8) * 2
	table.insert(parts, { label = "조명", value = light })
	local green = math.floor(math.min(f.plants, 10) * 1.5 + 0.5)
	table.insert(parts, { label = "식물", value = green })
	local social = math.floor(math.min(f.likes, 200) * 0.3 + 0.5)
	table.insert(parts, { label = "좋아요", value = social })
	local total = 0
	for _, p in parts do
		total += p.value
	end
	local g, nxt = Score.grade(total)
	return { total = total, grade = g, next = nxt, parts = parts, facts = f }
end

-------------------------------------------------------------------------------------------------
-- Badges (once each; persisted with the time they were earned)
-------------------------------------------------------------------------------------------------
Score.BADGES = {
	{ id = "first", name = "첫 가구", icon = "🪑", desc = "자유 배치로 첫 가구를 놓았어요", test = function(f, s) return f.count >= 1 end },
	{ id = "ten", name = "꾸미기 시작", icon = "🛋️", desc = "가구 10개를 놓았어요", test = function(f, s) return f.count >= 10 end },
	{ id = "thirty", name = "가구 부자", icon = "🏡", desc = "가구 30개를 놓았어요", test = function(f, s) return f.count >= 30 end },
	{ id = "sixty", name = "인테리어 장인", icon = "🏆", desc = "가구 60개를 놓았어요", test = function(f, s) return f.count >= 60 end },
	{ id = "allcats", name = "올라운더", icon = "🌈", desc = "14개 카테고리를 모두 들였어요", test = function(f, s) return f.catCount >= 14 end },
	{ id = "plants", name = "플랜테리어", icon = "🪴", desc = "식물 6개로 집을 채웠어요", test = function(f, s) return f.plants >= 6 end },
	{ id = "lights", name = "조명 맛집", icon = "💡", desc = "조명 5개를 켰어요", test = function(f, s) return f.lampsOn >= 5 end },
	{ id = "remodel", name = "리모델링", icon = "🎨", desc = "방 3곳의 벽지·바닥을 바꿨어요", test = function(f, s) return f.finishRooms >= 3 end },
	{ id = "party", name = "파티 플래너", icon = "🪩", desc = "파티 조명을 켰어요", test = function(f, s) return f.light == "party" end },
	{ id = "like1", name = "첫 좋아요", icon = "❤️", desc = "놀러 온 사람이 좋아요를 눌렀어요", test = function(f, s) return f.likes >= 1 end },
	{ id = "like10", name = "인기 하우스", icon = "💖", desc = "좋아요 10개", test = function(f, s) return f.likes >= 10 end },
	{ id = "like50", name = "광안리 핫플", icon = "🔥", desc = "좋아요 50개", test = function(f, s) return f.likes >= 50 end },
	{ id = "gb5", name = "방명록 인기", icon = "📝", desc = "방명록 5개를 받았어요", test = function(f, s) return f.gb >= 5 end },
	{ id = "photo", name = "집 사진 작가", icon = "📸", desc = "집 사진을 찍었어요", test = function(f, s) return (f.stats.photos or 0) >= 1 end },
	{ id = "preset", name = "레이아웃 디자이너", icon = "💾", desc = "배치 프리셋을 저장했어요", test = function(f, s) return (f.stats.presets or 0) >= 1 end },
	{ id = "set", name = "세트 완성", icon = "🛍️", desc = "추천 세트를 모두 놓았어요", test = function(f, s) return (f.stats.sets or 0) >= 1 end },
	{ id = "score100", name = "센스 있는 집", icon = "✨", desc = "인테리어 점수 100", test = function(f, s) return s >= 100 end },
	{ id = "score350", name = "잡지에 나올 집", icon = "📰", desc = "인테리어 점수 350", test = function(f, s) return s >= 350 end },
}
Score.BADGE_BY_ID = {} :: { [string]: any }
for _, b in Score.BADGES do
	Score.BADGE_BY_ID[b.id] = b
end

-- badge ids newly earned (not in `have`)
function Score.badgesEarned(result: any, have: { [string]: any }): { string }
	local out = {}
	for _, b in Score.BADGES do
		if not have[b.id] and b.test(result.facts, result.total) then
			table.insert(out, b.id)
		end
	end
	return out
end

-------------------------------------------------------------------------------------------------
-- Goals (simple ladder; a finished goal pays a small life-game stat reward once)
-------------------------------------------------------------------------------------------------
Score.GOALS = {
	{ id = "g_place3", name = "가구 3개 놓기", icon = "🪑", target = 3, value = function(f, s) return f.count end, reward = { happiness = 2 } },
	{ id = "g_plants2", name = "식물 2개 들이기", icon = "🪴", target = 2, value = function(f, s) return f.plants end, reward = { happiness = 2 } },
	{ id = "g_wall", name = "벽지 바꿔 보기", icon = "🎨", target = 1, value = function(f, s) return f.finishWalls end, reward = { popularity = 1 } },
	{ id = "g_lamps3", name = "조명 3개 켜기", icon = "💡", target = 3, value = function(f, s) return f.lampsOn end, reward = { happiness = 2 } },
	{ id = "g_score100", name = "인테리어 점수 100", icon = "⭐", target = 100, value = function(f, s) return s end, reward = { popularity = 2 } },
	{ id = "g_rooms3", name = "방 3곳 꾸미기 (방마다 3개)", icon = "🏠", target = 3, value = function(f, s) return f.roomsDecorated end, reward = { happiness = 3 } },
	{ id = "g_like5", name = "좋아요 5개 받기", icon = "❤️", target = 5, value = function(f, s) return f.likes end, reward = { popularity = 2 } },
	{ id = "g_photo", name = "집 사진 찍기", icon = "📸", target = 1, value = function(f, s) return f.stats.photos or 0 end, reward = { happiness = 1 } },
	{ id = "g_preset", name = "배치 프리셋 저장하기", icon = "💾", target = 1, value = function(f, s) return f.stats.presets or 0 end, reward = { happiness = 1 } },
	{ id = "g_score300", name = "인테리어 점수 300", icon = "🏆", target = 300, value = function(f, s) return s end, reward = { popularity = 3 } },
}

function Score.goalProgress(goal: any, result: any): (number, boolean)
	local v = goal.value(result.facts, result.total)
	return math.min(v, goal.target), v >= goal.target
end

function Score.rewardText(reward: any): string
	local t = {}
	if reward.happiness then
		table.insert(t, "행복 +" .. tostring(reward.happiness))
	end
	if reward.popularity then
		table.insert(t, "인기도 +" .. tostring(reward.popularity))
	end
	return table.concat(t, " · ")
end

return Score
