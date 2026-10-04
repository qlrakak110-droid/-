-- LED screens (tag LEDScreen, attribute Messages = "a|b|c"): the main text label of the screen's
-- SurfaceGui cycles through the messages every Config.Screens.MessageSeconds, synchronised to
-- server time (each screen gets a stable per-position offset so a street does not flip in unison).
-- Only screens within MaxDistance (per quality tier: 350 studs on phones) are updated; a text
-- change re-fits TextScaled labels, which is the expensive part.

local Screens = {}

type Rec = { part: BasePart, pos: Vector3, raw: string, messages: { string }, offset: number, label: TextLabel?, index: number, nextFind: number }

local function split(raw: string): { string }
	local out = {}
	for piece in string.gmatch(raw, "[^|]+") do
		local trimmed = string.match(piece, "^%s*(.-)%s*$")
		if trimmed and trimmed ~= "" then
			table.insert(out, trimmed)
		end
	end
	return out
end

local function findLabel(part: BasePart): TextLabel?
	local gui = part:FindFirstChildWhichIsA("SurfaceGui")
	if not gui then
		return nil
	end
	local face = gui:FindFirstChild("Face")
	local label = face and face:FindFirstChild("Text")
	if label and label:IsA("TextLabel") then
		return label
	end
	local any = gui:FindFirstChildWhichIsA("TextLabel", true)
	return any
end

function Screens.start(ctx: any)
	local Config, Shared, Util = ctx.Config, ctx.Shared, ctx.Util
	local cfg = Config.Screens
	local seconds = math.max(0.5, cfg.MessageSeconds)
	local screens: { [BasePart]: Rec } = {}

	local function load(rec: Rec)
		local raw = rec.part:GetAttribute("Messages")
		raw = if type(raw) == "string" then raw else ""
		if raw ~= rec.raw then
			rec.raw = raw
			rec.messages = split(raw)
			rec.index = 0
			local p = rec.part.Position
			rec.offset = Shared.hash01(p.X, p.Y, p.Z) * seconds * math.max(1, #rec.messages)
		end
	end

	Util.watchTag("LEDScreen", function(inst)
		if not inst:IsA("BasePart") then
			return
		end
		-- (screens are anchored: the position is cached)
		local rec: Rec = { part = inst, pos = inst.Position, raw = "\0", messages = {}, offset = 0, label = nil, index = 0, nextFind = 0 }
		load(rec)
		screens[inst] = rec
	end, function(inst)
		screens[inst :: BasePart] = nil
	end)

	local reloadCounter = 0

	local function step()
		local camPos = Util.cameraPosition()
		if not camPos then
			return
		end
		local maxDistance = Util.tierConfig(cfg).MaxDistance
		local maxD2 = maxDistance * maxDistance
		local now = workspace:GetServerTimeNow()
		reloadCounter += 1
		local reload = reloadCounter % 10 == 0 -- pick up Messages edits every ~5 s
		for part, rec in screens do
			if reload then
				load(rec)
			end
			local count = #rec.messages
			if count > 0 then
				local d = rec.pos - camPos
				if d.X * d.X + d.Y * d.Y + d.Z * d.Z <= maxD2 then
					local index = math.floor((now + rec.offset) / seconds) % count + 1
					local label = rec.label
					if (not label or label.Parent == nil) and now >= rec.nextFind then
						-- (the gui can stream in after the part: a screen without a label is
						-- searched again every few seconds, not on every step)
						label = findLabel(part)
						rec.label = label
						rec.index = 0
						rec.nextFind = if label then 0 else now + 4
					end
					if label and index ~= rec.index then
						rec.index = index
						label.Text = rec.messages[index]
					end
				end
			end
		end
	end

	task.spawn(function()
		while true do
			task.wait(0.5)
			local ok, err = pcall(step)
			if not ok then
				Util.warn("Screens", err)
			end
		end
	end)
end

return Screens
