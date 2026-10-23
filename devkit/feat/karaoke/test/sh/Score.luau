-- GwangalliKaraokeShared/Score: judging windows, score curves, grades and the Korean score comments.
-- Pure functions, used by the server (authoritative score) and by the client (live HUD feedback).
--
--   Score.judge(dtReal) -> "P" | "G" | "M" | nil        (nil = too far from the note to count)
--   Score.tapScore(perfect, good, total, maxCombo) -> 0..100
--   Score.voiceLine(v, r, o) -> 0..1                     (one sung line: voiced / rests kept / onsets)
--   Score.voiceScore(sumQ, nLines) -> 0..100
--   Score.vibeBonus(onBeat) -> 0..3                      (탬버린 박자 보너스)
--   Score.final(base, vibe) -> 0..100
--   Score.grade(score) -> { id, label, color = {r,g,b}, head }
--   Score.comment(score, seed) -> Korean comment
--   Score.participation(judged, totalTaps, voiced, nLines) -> 0..1

local Score = {}

-- seconds (real time) between the press and the note
Score.WIN = { perfect = 0.09, good = 0.18, early = 0.32 }
Score.LIVE_SLACK = 0.6 -- a hit may reach the server up to this much (song s) before its note
Score.STALE = 6 -- ... and up to this much after it
Score.VOICE_EARLY = 1.2 -- a voice line result may arrive this much before its due time
Score.VOICE_LATE = 6
Score.BEAT_WIN = 0.11 -- |offset| to the half-beat grid that counts as an on-beat tambourine shake
Score.VOICED_MIN = 0.15 -- a line with v below this was not sung

function Score.judge(dt: number): string?
	if type(dt) ~= "number" or dt ~= dt then
		return nil
	end
	local a = math.abs(dt)
	if a <= Score.WIN.perfect then
		return "P"
	elseif a <= Score.WIN.good then
		return "G"
	elseif a <= Score.WIN.early then
		return "M"
	end
	return nil
end

local function round(x: number): number
	return math.floor(x + 0.5)
end

-- legacy curve (40 + 60 * raw) split into accuracy and a small combo term; all PERFECT = 100
function Score.tapScore(perfect: number, good: number, total: number, maxCombo: number): number
	if total <= 0 then
		return 0
	end
	local raw = math.clamp((perfect + 0.6 * good) / total, 0, 1)
	local combo = math.clamp(maxCombo / total, 0, 1)
	return math.clamp(round(40 + 54 * raw + 6 * combo), 0, 100)
end

function Score.voiceLine(v: number, r: number, o: number): number
	v = math.clamp(tonumber(v) or 0, 0, 1)
	r = math.clamp(tonumber(r) or 0, 0, 1)
	o = math.clamp(tonumber(o) or 0, 0, 1)
	if v < Score.VOICED_MIN then
		return v * 0.5
	end
	return math.clamp(0.62 * v + 0.2 * r + 0.18 * o, 0, 1)
end

-- sumQ = sum of voiceLine values of the lines received; lines never received count 0
function Score.voiceScore(sumQ: number, nLines: number): number
	if nLines <= 0 then
		return 0
	end
	local m = math.clamp(sumQ / nLines, 0, 1)
	local k = math.clamp(m / 0.8, 0, 1) ^ 0.85
	return math.clamp(round(45 + 55 * k), 0, 100)
end

function Score.vibeBonus(onBeat: number): number
	return math.clamp(math.floor((tonumber(onBeat) or 0) / 6), 0, 3)
end

function Score.final(base: number, vibe: number): number
	return math.clamp(round(base + (vibe or 0)), 0, 100)
end

function Score.participation(judged: number, totalTaps: number, voiced: number, nLines: number): number
	local a = if totalTaps > 0 then judged / totalTaps else 0
	local b = if nLines > 0 then voiced / nLines else 0
	return math.clamp(math.max(a, b), 0, 1)
end

-- offset of song time t to the nearest half beat (song seconds)
function Score.beatOffset(beat: number, t: number): number
	local half = beat / 2
	local k = math.floor(t / half + 0.5)
	return t - k * half
end

Score.GRADES = {
	{ min = 100, id = "S+", label = "PERFECT", color = { 255, 206, 70 }, head = "축하합니다! 100점!" },
	{ min = 95, id = "S", label = "EXCELLENT", color = { 255, 150, 220 }, head = "가수 데뷔각!" },
	{ min = 90, id = "A+", label = "GREAT", color = { 120, 230, 255 }, head = "프로급 실력" },
	{ min = 80, id = "A", label = "GOOD", color = { 120, 240, 160 }, head = "노래 실력 수준급" },
	{ min = 70, id = "B", label = "NICE", color = { 190, 160, 255 }, head = "흥이 넘쳐요" },
	{ min = 60, id = "C", label = "OK", color = { 200, 205, 220 }, head = "좋아요" },
	{ min = 0, id = "D", label = "TRY AGAIN", color = { 170, 177, 196 }, head = "다음엔 더 잘할 수 있어요" },
}

function Score.grade(score: number): any
	for _, g in Score.GRADES do
		if score >= g.min then
			return g
		end
	end
	return Score.GRADES[#Score.GRADES]
end

local COMMENTS = {
	{ 100, { "🎉 축하합니다! 100점! 전국 노래자랑 나가도 되겠어요", "🎉 100점! 오늘 이 방의 주인공은 당신!" } },
	{ 95, { "와우! 가수 데뷔각? 🎤", "음원 내도 되겠어요! ✨", "소름 돋았어요… 앵콜!" } },
	{ 90, { "노래 실력이 프로급이에요", "박수가 절로 나와요 👏", "목소리에 반했어요 💕" } },
	{ 80, { "노래 실력 수준급! 👏", "분위기 최고예요 🔥", "한 곡 더 듣고 싶어요" } },
	{ 70, { "흥이 넘쳐요!", "조금만 더 하면 90점!", "점점 좋아지고 있어요" } },
	{ 60, { "좋아요! 한 곡 더?", "목 좀 풀렸나요? 😄", "다음 곡은 더 신나게!" } },
	{ 0, { "다음엔 더 잘할 수 있어요 · 탬버린이라도 열심히 🪇", "연습하면 늘어요! 💪", "괜찮아요, 노래방은 즐기는 곳!" } },
}

function Score.comment(score: number, seed: number?): string
	for _, c in COMMENTS do
		if score >= c[1] then
			local list = c[2]
			local k = (math.floor(tonumber(seed) or 0) % #list) + 1
			return list[k]
		end
	end
	return COMMENTS[#COMMENTS][2][1]
end

return Score
