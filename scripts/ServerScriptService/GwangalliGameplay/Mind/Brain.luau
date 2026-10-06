-- GwangalliGameplay/Mind/Brain (server; owner: npc_mind): OPTIONAL Claude replies for free talk.
-- Off unless the place is set up for it; everything works without it (GwangalliGameplay.Mind.Talk
-- answers then, and in the 임시 스튜디오 emulator it is always Talk).
--
-- SET UP (live Roblox): Game Settings -> Security -> Allow HTTP Requests = on, and a Roblox secret
-- named ANTHROPIC_API_KEY (Creator Dashboard -> the experience -> Secrets) holding an Anthropic API
-- key. workspace attribute GwangalliMindBrain = false turns it off at run time.
--
-- WHAT IT DOES: a free message the rule layer would only "small talk" goes to the Claude Messages
-- API (raw HTTPS: Roblox has no SDK) with the NPC's whole situation as the system prompt: who they
-- are (roster profile, personality, speech style, Busan dialect), where they are and what they are
-- doing, the time / weather / live news, what they feel about this player (호감도 stage, the five
-- feelings, 존댓말 / 반말), what they remember (player facts, recent events, the last turns).
-- The reply is structured JSON: 1-3 lines, feeling deltas (clamped), an optional act (end / leave /
-- flee / meet_menu) or appointment kind, and facts the player told (name / job / like / feeling),
-- which land in rec.pf like Talk's. Insults, threats, confessions, apologies and number requests
-- never come here: the composer keeps those (crime, fights, love, Relationships) deterministic.
--
-- SAFETY / COST: the player's text and the reply both pass TextService filtering; per-player gap
-- + hourly cap, a global in-flight cap, a timeout (late answers are dropped), and a breaker that
-- turns it off for a while after repeated failures. A refusal (stop_reason "refusal") or bad JSON
-- = Talk answers.

local HttpService = game:GetService("HttpService")
local TextService = game:GetService("TextService")

local Brain = {}

Brain.MODEL = "claude-opus-5-5"
Brain.URL = "https://api.anthropic.com/v1/messages"
Brain.SECRET = "ANTHROPIC_API_KEY"
Brain.EFFORT = "low" -- short in-character lines: keep the thinking light and the reply quick
Brain.MAX_TOKENS = 1500
Brain.TIMEOUT = 9 -- s; later than this the rule layer answers and the late reply is dropped
Brain.GAP = 2 -- s between two calls of one player
Brain.PER_HOUR = 90 -- calls per player per hour
Brain.MAX_INFLIGHT = 8
Brain.BREAK_AFTER = 3 -- failures in a row
Brain.BREAK_S = 180

local M: any = nil
local Citizens: any = nil
local secret: any = nil
local inflight = 0
local fails = 0
local brokenUntil = 0
local perPlayer: { [Player]: { last: number, hour: number, n: number } } = {}

-- the composer keeps these (consequences must not depend on a model's wording)
local RULE_ONLY = { insult = true, provoke = true, threaten = true, confess = true, apologize = true, number = true, flirt = true, request = true, bye = true }
local ACTS = { none = true, ["end"] = true, leave = true, flee = true, meet_menu = true }
local INVITES = { "none", "now", "club", "beach", "cafe", "meal", "karaoke", "bowling", "billiards", "pocha", "walk" }

local SCHEMA = {
	type = "object",
	properties = {
		lines = { type = "array", items = { type = "string" }, description = "1-3 short spoken lines in Korean, in character" },
		face = { type = "string", enum = { "smile", "laugh", "neutral", "shy", "sad", "annoyed", "angry", "scared", "surprised", "wary", "smug", "love" } },
		emote = { type = "string", enum = { "none", "wave", "laugh", "cheer", "point", "think", "refuse", "shy", "nod", "shrug", "cross", "startle", "turn" } },
		delta = {
			type = "object",
			properties = { aff = { type = "number" }, tr = { type = "number" }, an = { type = "number" }, fe = { type = "number" }, cl = { type = "number" } },
			required = { "aff", "tr", "an", "fe", "cl" },
			additionalProperties = false,
		},
		act = { type = "string", enum = { "none", "end", "leave", "flee", "meet_menu" } },
		invite = { type = "string", enum = INVITES },
		facts = {
			type = "object",
			properties = { name = { type = "string" }, job = { type = "string" }, like = { type = "string" }, feel = { type = "string" } },
			required = { "name", "job", "like", "feel" },
			additionalProperties = false,
		},
	},
	required = { "lines", "face", "emote", "delta", "act", "invite", "facts" },
	additionalProperties = false,
}

function Brain.init(deps: any)
	M = deps.M
	Citizens = deps.Citizens
	local ok, s = pcall(function()
		return HttpService:GetSecret(Brain.SECRET)
	end)
	secret = if ok then s else nil
end

function Brain.ready(): boolean
	if not secret or workspace:GetAttribute("GwangalliMindBrain") == false then
		return false
	end
	if os.clock() < brokenUntil or inflight >= Brain.MAX_INFLIGHT then
		return false
	end
	local okHttp, on = pcall(function()
		return HttpService.HttpEnabled
	end)
	return okHttp and on == true
end

local function allow(player: Player): boolean
	local t = os.clock()
	local s = perPlayer[player]
	if not s then
		s = { last = -1e9, hour = t, n = 0 }
		perPlayer[player] = s
	end
	if t - s.hour > 3600 then
		s.hour, s.n = t, 0
	end
	if t - s.last < Brain.GAP or s.n >= Brain.PER_HOUR then
		return false
	end
	s.last = t
	s.n += 1
	return true
end

local function filterFor(player: Player, text: string): string?
	local ok, res = pcall(function()
		local r = TextService:FilterStringAsync(text, player.UserId)
		return r:GetNonChatStringForUserAsync(player.UserId)
	end)
	if ok and type(res) == "string" then
		return res
	end
	return nil
end

local FEEL_WORD = { aff = "호감", tr = "신뢰", an = "분노", fe = "공포", cl = "친밀" }

local function persona(player: Player, c: any, rec: any, env: any, tc: any, chan: string): string
	local t = M.traits(c)
	local A = M.ARCH[t.arch] or {}
	local aff = env.aff or 0
	local stage = M.stage(rec, aff)
	local S = M.STAGES[stage] or {}
	local reg = M.register(c, rec, aff)
	local status = ""
	pcall(function()
		status = Citizens.status(c.id, env.clock or 12)
	end)
	local P = M.prefs(c)
	local foods = {}
	for i = 1, math.min(3, #P.foods) do
		local f = M.FOODS[P.foods[i]]
		table.insert(foods, f and f.name or P.foods[i])
	end
	local pf = type(rec.pf) == "table" and rec.pf or {}
	local facts = {}
	if pf.nm then
		table.insert(facts, "이름 " .. pf.nm)
	end
	if pf.job then
		table.insert(facts, "직업 " .. pf.job)
	end
	if pf.age then
		table.insert(facts, tostring(pf.age) .. "살")
	end
	if type(pf.likes) == "table" and #pf.likes > 0 then
		table.insert(facts, "좋아하는 것 " .. table.concat(pf.likes, ", "))
	end
	if type(pf.feel) == "table" and pf.feel.x then
		table.insert(facts, "지난번 기분 " .. tostring(pf.feel.x))
	end
	local mems = {}
	for i = #rec.mem, math.max(1, #rec.mem - 6), -1 do
		local m = rec.mem[i]
		if m and m.k ~= "talk" then
			table.insert(mems, string.format("%s(%d분 전)", tostring(m.k), math.floor(((env.now or 0) - (m.t or 0)) / 60)))
		end
	end
	local feelings = {}
	for _, k in { "tr", "an", "fe", "cl" } do
		table.insert(feelings, string.format("%s %d", FEEL_WORD[k], math.floor(rec[k] or 0)))
	end
	table.insert(feelings, 1, string.format("호감 %d", math.floor(aff)))
	local lines = {
		"너는 부산 광안리를 배경으로 한 로블록스 생활 게임 속 사람이다. 플레이어와 길에서 직접 대화하고 있다(" .. (if chan == "text" then "휴대폰 문자" elseif chan == "call" then "전화 통화" else "얼굴 보고 대화") .. ").",
		string.format("너: %s, %s살, %s. 직업: %s. 유형: %s.", c.name or "?", tostring(c.age or "?"), if c.g == "f" then "여자" else "남자", c.job or "?", A.label or t.arch),
		string.format("성격(0~1): 다정 %.1f, 성질 %.1f, 용기 %.1f, 유머 %.1f, 자존심 %.1f, 수다 %.1f.", t.warm, t.temper, t.brave, t.humor, t.pride, t.chatty),
		"말투: " .. (if c.speech == "busan" then "부산 사투리를 자연스럽게 섞는다. " else "표준어. ") .. (if reg == "c" then "플레이어에게 반말을 쓴다." else "플레이어에게 존댓말을 쓴다."),
		"좋아하는 화제: " .. table.concat(type(c.topics) == "table" and c.topics or {}, ", ") .. ". 싫어하는 화제: " .. table.concat(type(c.hate) == "table" and c.hate or {}, ", ") .. ". 좋아하는 음식: " .. table.concat(foods, ", ") .. ".",
		"자주 하는 말: " .. table.concat(type(c.sig) == "table" and c.sig or {}, " / "),
		string.format("지금: %s, 게임 시각 %s, 날씨 %s, 장소 %s.", status ~= "" and status or "거리에 있음", env.timeText or "?", env.weather or "clear", env.area or "광안리"),
		string.format("플레이어(%s)와의 관계: %s. 감정 수치(0~100): %s.", env.you or "플레이어", S.label or stage, table.concat(feelings, ", ")),
		"플레이어에 대해 아는 것: " .. (if #facts > 0 then table.concat(facts, "; ") else "아직 없음") .. ".",
		"최근 있었던 일: " .. (if #mems > 0 then table.concat(mems, ", ") else "특별한 일 없음") .. ".",
	}
	if (env.wanted or 0) > 0 then
		table.insert(lines, string.format("플레이어는 지금 경찰에게 수배 중이다(별 %d개). 너는 그걸 눈치채고 있다.", env.wanted))
	end
	if type(env.liveNews) == "table" and #env.liveNews > 0 then
		table.insert(lines, "동네 소문: " .. table.concat(env.liveNews, " / "))
	end
	table.insert(lines, "")
	table.insert(lines, "규칙:")
	table.insert(lines, "- 진짜 사람처럼 대화한다. 상대 말의 뜻을 이해하고 그에 맞게 대답하며, 같은 말을 반복하지 않는다. 한 번에 1~3문장, 짧고 자연스럽게.")
	table.insert(lines, "- 성격, 기분, 관계, 장소, 시간에 맞게 반응한다. 친하지 않으면 사적인 질문엔 조심스럽고, 싫어하는 화제엔 싫은 티를 낸다. 화나 있으면 퉁명스럽다.")
	table.insert(lines, "- 가끔 너도 질문하거나 네 얘기를 꺼낸다. 플레이어가 알려 준 사실(이름, 직업, 좋아하는 것, 기분)이 있으면 facts에 적고, 없으면 빈 문자열.")
	table.insert(lines, "- delta는 이 한마디로 바뀌는 감정(-5~5): 즐거운 대화면 aff/cl 조금 +, 무례하면 an +, 무서우면 fe +.")
	table.insert(lines, "- 같이 어디 가자고 하면 관계와 기분을 보고 invite(장소 종류)로 수락하거나 lines로 거절한다. 대화를 끝내고 싶으면 act=end, 화나서 가 버리면 leave, 무서우면 flee.")
	table.insert(lines, "- 로블록스 게임이다: 욕설, 성적인 내용, 실제 개인정보, 현실의 위험한 정보는 말하지 않고 캐릭터답게 넘긴다. 너가 AI라는 말은 절대 하지 않는다.")
	return table.concat(lines, "\n")
end

local function clampN(v: any, lo: number, hi: number): number
	return if type(v) == "number" and v == v then math.clamp(v, lo, hi) else 0
end

-- -> out (the composer's shape) | nil
function Brain.reply(player: Player, c: any, rec: any, text: string, env: any, tc: any, chan: string): any?
	if not M or not c or not Brain.ready() then
		return nil
	end
	local intent = M.parse(text, nil)
	if RULE_ONLY[intent] then
		return nil
	end
	if not allow(player) then
		return nil
	end
	local clean = filterFor(player, text)
	if not clean then
		return nil
	end
	local msgs = {}
	if type(rec.cv) == "table" then
		for i = math.max(1, #rec.cv - 5), #rec.cv do
			local turn = rec.cv[i]
			if type(turn) == "table" and type(turn.p) == "string" and type(turn.n) == "string" then
				table.insert(msgs, { role = "user", content = turn.p })
				table.insert(msgs, { role = "assistant", content = turn.n })
			end
		end
	end
	table.insert(msgs, { role = "user", content = clean })
	local body = {
		model = Brain.MODEL,
		max_tokens = Brain.MAX_TOKENS,
		system = persona(player, c, rec, env, tc, chan),
		messages = msgs,
		output_config = { effort = Brain.EFFORT, format = { type = "json_schema", schema = SCHEMA } },
		fallbacks = "default",
	}
	local okEnc, json = pcall(HttpService.JSONEncode, HttpService, body)
	if not okEnc then
		return nil
	end
	inflight += 1
	local done, result = false, nil
	task.spawn(function()
		local ok, res = pcall(function()
			return HttpService:RequestAsync({
				Url = Brain.URL,
				Method = "POST",
				Headers = {
					["Content-Type"] = "application/json",
					["x-api-key"] = secret,
					["anthropic-version"] = "2023-06-01",
					["anthropic-beta"] = "server-side-fallback-2026-07-01",
				},
				Body = json,
			})
		end)
		inflight -= 1
		result = if ok then res else nil
		done = true
	end)
	local t0 = os.clock()
	while not done and os.clock() - t0 < Brain.TIMEOUT do
		task.wait(0.1)
	end
	if not done or not result or not result.Success then
		fails += 1
		if fails >= Brain.BREAK_AFTER then
			fails = 0
			brokenUntil = os.clock() + Brain.BREAK_S
			warn("[GwangalliMind.Brain] off for a while: " .. (if result then tostring(result.StatusCode) else "timeout"))
		end
		return nil
	end
	local okDec, msg = pcall(HttpService.JSONDecode, HttpService, result.Body)
	if not okDec or type(msg) ~= "table" or msg.stop_reason == "refusal" or msg.stop_reason == "max_tokens" or type(msg.content) ~= "table" then
		return nil
	end
	local textOut = nil
	for _, block in msg.content do
		if type(block) == "table" and block.type == "text" and type(block.text) == "string" then
			textOut = block.text
		end
	end
	local okJ, data = pcall(HttpService.JSONDecode, HttpService, textOut or "")
	if not okJ or type(data) ~= "table" or type(data.lines) ~= "table" then
		return nil
	end
	fails = 0
	local lines = {}
	for _, l in data.lines do
		if type(l) == "string" and l ~= "" and #lines < 3 then
			local f = filterFor(player, string.sub(l, 1, 300))
			if f and f ~= "" then
				table.insert(lines, f)
			end
		end
	end
	if #lines == 0 then
		return nil
	end
	-- facts the player told -> the same record as Talk's
	local facts = type(data.facts) == "table" and data.facts or {}
	rec.pf = if type(rec.pf) == "table" then rec.pf else {}
	local pf = rec.pf
	if type(facts.name) == "string" and facts.name ~= "" and utf8.len(facts.name) and utf8.len(facts.name) <= 10 then
		pf.nm = facts.name
	end
	if type(facts.job) == "string" and facts.job ~= "" and #facts.job <= 40 then
		pf.job = facts.job
	end
	if type(facts.like) == "string" and facts.like ~= "" and #facts.like <= 40 then
		pf.likes = if type(pf.likes) == "table" then pf.likes else {}
		if not table.find(pf.likes, facts.like) then
			table.insert(pf.likes, facts.like)
			while #pf.likes > 6 do
				table.remove(pf.likes, 1)
			end
		end
	end
	if type(facts.feel) == "string" and facts.feel ~= "" and #facts.feel <= 30 then
		pf.feel = { x = facts.feel, t = env.now or os.time() }
	end
	local dd = type(data.delta) == "table" and data.delta or {}
	local aff = env.aff or 0
	local out = {
		lines = lines,
		d = { aff = clampN(dd.aff, -5, 3), tr = clampN(dd.tr, -5, 3), an = clampN(dd.an, -5, 12), fe = clampN(dd.fe, -5, 12), cl = clampN(dd.cl, -3, 2.5) },
		face = if type(data.face) == "string" then data.face else "neutral",
		emote = if type(data.emote) == "string" and data.emote ~= "none" then data.emote else nil,
		act = if type(data.act) == "string" and ACTS[data.act] and data.act ~= "none" then data.act else nil,
		invite = if type(data.invite) == "string" and data.invite ~= "none" and table.find(INVITES, data.invite) then data.invite else nil,
		intent = "small",
		mood = M.mood(c, rec, aff, env),
		stage = M.stage(rec, aff),
		reg = M.register(c, rec, aff),
		mem = { k = "talk", x = "brain" },
		brain = true,
	}
	tc.lastLine = lines[#lines]
	return out
end

function Brain.forget(player: Player)
	perPlayer[player] = nil
end

return Brain
