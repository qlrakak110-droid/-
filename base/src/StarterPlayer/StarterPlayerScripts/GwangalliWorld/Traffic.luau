-- Traffic and pedestrian signals, cycled per Group from server time (see GwangalliShared):
-- green 12 s -> amber 3 s -> all red 2 s, then the perpendicular direction. The direction of a
-- housing comes from attribute SignalPhase (assigned by the server from the housing orientation);
-- pedestrian heads walk with the traffic their axis runs parallel to and blink before stopping.
-- Lamps "on" = Neon + bright colour, "off" = SmoothPlastic + their original dark colour.
-- Only housings within MaxDistance (per quality tier: 450 studs on phones) are updated.

local Traffic = {}

type Lamp = { part: BasePart, off: Color3 }
type Rec = {
	housing: BasePart,
	pos: Vector3, -- housings are anchored: position cached at registration
	ped: boolean,
	group: string,
	fallbackPhase: number,
	lamps: { [string]: Lamp },
	state: string?,
	phase: number?, -- SignalPhase attribute, re-read with the lamp check (~1 s)
}

local VEHICLE_LAMPS = { "Red", "Amber", "Arrow", "Green" }
local PED_LAMPS = { "Red", "Green" }

function Traffic.start(ctx: any)
	local Config, Shared, Util = ctx.Config, ctx.Shared, ctx.Util
	local cfg = Config.Traffic
	local NEON, OFF_MAT = Enum.Material.Neon, Enum.Material.SmoothPlastic
	local phaseAttr = Shared.Attr.SignalPhase
	local housings: { [BasePart]: Rec } = {}
	-- "off" colour per lamp instance, recorded the first time the lamp is seen (before any write
	-- of ours): a lamp that streams back in as the same object may still be lit.
	local offColor: { [BasePart]: Color3 } = setmetatable({}, { __mode = "k" }) :: any

	local function groupOf(inst: Instance): string
		local g = inst:GetAttribute("Group")
		return if type(g) == "string" and g ~= "" then g else "default"
	end

	local function adder(ped: boolean)
		return function(inst: Instance)
			if not inst:IsA("BasePart") then
				return
			end
			housings[inst] = {
				housing = inst,
				pos = inst.Position,
				ped = ped,
				group = groupOf(inst),
				fallbackPhase = Shared.fallbackSignalPhase(inst.CFrame),
				lamps = {},
				state = nil,
			}
		end
	end
	local function remover(inst: Instance)
		housings[inst :: BasePart] = nil
	end
	Util.watchTag("TrafficSignal", adder(false), remover)
	Util.watchTag("PedSignal", adder(true), remover)

	-- Lamps are separate BaseParts under the housing, so they can stream in after it (or be
	-- replaced by fresh copies). Returns true when the set changed.
	local function refreshLamps(rec: Rec): boolean
		local changed = false
		for _, name in (if rec.ped then PED_LAMPS else VEHICLE_LAMPS) do
			local lamp = rec.lamps[name]
			if not lamp or lamp.part.Parent ~= rec.housing then
				local part = rec.housing:FindFirstChild(name)
				if part and part:IsA("BasePart") then
					local off = offColor[part]
					if not off then
						off = part.Color
						offColor[part] = off
					end
					rec.lamps[name] = { part = part, off = off }
					changed = true
				elseif lamp then
					rec.lamps[name] = nil
				end
			end
		end
		return changed
	end

	local function setLamp(rec: Rec, name: string, on: boolean, color: Color3)
		local lamp = rec.lamps[name]
		if not lamp then
			return
		end
		if on then
			lamp.part.Material = NEON
			lamp.part.Color = color
		else
			lamp.part.Material = OFF_MAT
			lamp.part.Color = lamp.off
		end
	end

	local function phaseOf(rec: Rec, reread: boolean): number
		local cached = rec.phase
		if cached and not reread then
			return cached
		end
		local p = rec.housing:GetAttribute(phaseAttr)
		local phase = if p == 0 or p == 1 then p else rec.fallbackPhase
		rec.phase = phase
		return phase
	end

	local colors = cfg.Colors
	local stepCount = 0

	local function step()
		local camPos = Util.cameraPosition()
		if not camPos then
			return
		end
		local maxDistance = Util.tierConfig(cfg).MaxDistance
		local maxD2 = maxDistance * maxDistance
		local now = workspace:GetServerTimeNow()
		stepCount += 1
		local lampCheck = stepCount % 4 == 0 -- lamps that stream in late are picked up within ~1 s
		for _, rec in housings do
			local d = rec.pos - camPos
			if d.X * d.X + d.Y * d.Y + d.Z * d.Z > maxD2 then
				rec.state = nil -- re-apply when it comes back into range
				continue
			end
			if (lampCheck or rec.state == nil) and refreshLamps(rec) then
				rec.state = nil
			end
			local phase = phaseOf(rec, lampCheck)
			if rec.ped then
				local s = Shared.pedState(rec.group, phase, now)
				local key = s
				if s == "flash" then
					key = if math.floor(now * 2) % 2 == 0 then "flash_on" else "flash_off"
				end
				if key ~= rec.state then
					rec.state = key
					local green = key == "walk" or key == "flash_on"
					setLamp(rec, "Green", green, colors.PedGreen)
					setLamp(rec, "Red", key == "stop", colors.PedRed)
				end
			else
				local s = Shared.vehicleState(rec.group, phase, now)
				if s ~= rec.state then
					rec.state = s
					setLamp(rec, "Red", s == "red", colors.Red)
					setLamp(rec, "Amber", s == "amber", colors.Amber)
					setLamp(rec, "Green", s == "green", colors.Green)
					setLamp(rec, "Arrow", s == "green" and cfg.ArrowWithGreen, colors.Arrow)
				end
			end
		end
	end

	task.spawn(function()
		while true do
			task.wait(Util.tierConfig(cfg).UpdateInterval)
			local ok, err = pcall(step)
			if not ok then
				Util.warn("Traffic", err)
			end
		end
	end)
end

return Traffic
