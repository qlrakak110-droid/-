-- Interact/Talk (server): picks what a city NPC says. Data: Interact.Lines (style -> situation ->
-- variants, FALLBACK chain). Rules, no generative AI:
--   * style first, then its fallback parents, then citizen_polite
--   * never the same line twice in a row for an NPC: each NPC keeps its last 12 lines and prefers
--     unused variants (least recently used when all were used)
--   * placeholders {player} {name} {place} {item} {what} {where} {when} {amount} {target}

local Talk = {}

local I: any
local Lines: any
local Cast: any
local rnd = Random.new()

local function variants(style: string, situation: string): { string }?
	local seen = {}
	local s = style
	while s and not seen[s] do
		seen[s] = true
		local st = Lines and Lines.STYLES and Lines.STYLES[s]
		local v = st and st[situation]
		if type(v) == "table" and #v > 0 then
			return v
		end
		s = Lines and Lines.FALLBACK and Lines.FALLBACK[s]
	end
	local base = Lines and Lines.STYLES and Lines.STYLES.citizen_polite
	local v = base and base[situation]
	if type(v) == "table" and #v > 0 then
		return v
	end
	return nil
end
Talk.variants = variants

function Talk.has(n: any, situation: string): boolean
	return variants(n.style or "citizen_polite", situation) ~= nil
end

function Talk.callName(n: any): string
	local list = Cast and Cast.CALL and Cast.CALL[n.style or ""]
	if list and #list > 0 then
		-- a person keeps their own habit (stable per NPC)
		local h = 0
		for i = 1, #n.id do
			h += string.byte(n.id, i)
		end
		return list[(h % #list) + 1]
	end
	return "저기요"
end

local function fill(text: string, n: any, vars: any?): string
	local v = vars or {}
	local out = string.gsub(text, "{(%w+)}", function(k)
		if k == "player" then
			return v.player or Talk.callName(n)
		elseif k == "name" then
			return n.name or ""
		elseif k == "item" then
			return v.item or (Lines and Lines.ITEMS and Lines.ITEMS[1]) or "삼각김밥"
		elseif v[k] ~= nil then
			return tostring(v[k])
		end
		local defaults = { place = "광장", what = "소란", where = "저쪽", when = "아까", amount = "천 원", target = "저 사람" }
		return defaults[k] or ""
	end)
	return out
end

-- a line for this NPC (nil when nothing fits)
function Talk.line(n: any, situation: string, vars: any?): string?
	local list = variants(n.style or "citizen_polite", situation)
	if not list then
		return nil
	end
	n.recentLines = n.recentLines or {}
	local recent = n.recentLines
	local best, bestAge = nil, -1
	local candidates = {}
	for _, t in list do
		local age = recent[t]
		if not age then
			table.insert(candidates, t)
		elseif (os.clock() - age) > bestAge then
			best, bestAge = t, os.clock() - age
		end
	end
	local pick = if #candidates > 0 then candidates[rnd:NextInteger(1, #candidates)] else best
	if not pick then
		return nil
	end
	recent[pick] = os.clock()
	-- forget the oldest when more than 12 are remembered
	local count = 0
	local oldestK, oldestT = nil, math.huge
	for k, t in recent do
		count += 1
		if t < oldestT then
			oldestK, oldestT = k, t
		end
	end
	if count > 12 and oldestK then
		recent[oldestK] = nil
	end
	return fill(pick, n, vars)
end

-- say it out loud (bubble for everybody near) and return the text
function Talk.say(n: any, situation: string, vars: any?, dur: number?): string?
	local text = Talk.line(n, situation, vars)
	if text and n.a and not n.a.gone then
		I.Actors.say(n.a, text, dur or math.clamp(1.6 + #text * 0.06, 2.2, 5))
		n.lastSay = os.clock()
	end
	return text
end

function Talk.item(): string
	local items = Lines and Lines.ITEMS
	if type(items) == "table" and #items > 0 then
		return items[rnd:NextInteger(1, #items)]
	end
	return "삼각김밥"
end

function Talk.init(interact: any)
	I = interact
	Cast = I.Cast
	local m = script.Parent:FindFirstChild("Lines")
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			Lines = res
		else
			warn("[GwangalliCity] Lines failed to load: " .. tostring(res))
		end
	end
	Talk.Lines = Lines
end

return Talk
