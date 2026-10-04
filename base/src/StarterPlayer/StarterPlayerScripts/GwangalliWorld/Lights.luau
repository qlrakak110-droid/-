-- Light budgets (per quality tier, Config.Lights.low / mid / high).
--   CityLight: on at night only, and only the nearest N to the camera (high 40 / mid 20 / low 8).
--   InteriorLight (AlwaysOn): on day and night, only within InteriorRadius (nearest 24 / 16 / 6).
-- Re-evaluated every Config.Lights.EvaluateInterval seconds; Enabled is written only on change.
-- InteriorLights on locally hidden hosts (venue interior zones / near-only detail hidden by DetailLOD)
-- get no slot. The saver sub-level of low (GwangalliQuality.isSaver) has its own budget (Config.Lights.saver).
-- The budget is read on every pass, so a tier change (GwangalliQuality) applies within 0.5 s.
-- Lights are switched off the moment they stream in (the place saves them Enabled), so a phone
-- never renders hundreds of Future-lighting lights before the first pass.
--
-- Look (look_roblox pass):
--   * Warm street light: CityLight SpotLights / PointLights whose colour is a near-white warm tone
--     (street, promenade, park and bridge lamps: 255,232,196 / 255,214,160 ...) are set once, on
--     registration, to warm 3000 K LED (one lamp in five 3300 K, picked from the position so it is
--     the same on every client), Brightness x1.08 for the lower luminance of the warmer colour.
--     Coloured accent lights and cool-white lights are never touched; attribute KeepColor = true
--     opts a light out. Marked with attribute GwLookWarm so a re-registration does not repeat it.
--   * Shadows only on hero lights: every light is registered with Shadows = false (small lights
--     never cast shadows); the nearest HeroShadows enabled CityLight SpotLights (and lights with
--     attribute Hero = true) cast them, per tier: high 3, mid / low / saver 0
--     (Config.Lights[tier].HeroShadows overrides). Written only on change.

local Lights = {}

-- pos: the host position cached at registration (lamp posts and fixtures are anchored); only
-- lights on unanchored hosts (dynamic = true) re-read it on every pass.
-- heroOK: may cast hero shadows (a SpotLight or attribute Hero); shadow: Shadows as last written.
type Rec = {
	light: Light,
	on: boolean,
	d2: number,
	want: boolean,
	pos: Vector3?,
	dynamic: boolean,
	heroOK: boolean,
	shadow: boolean,
	shadowWant: boolean,
}

local WARM_3000K = Color3.fromRGB(255, 192, 132)
local WARM_3300K = Color3.fromRGB(255, 200, 146)
local WARM_GAIN = 1.08
local HERO_DEFAULT = { low = 0, mid = 0, high = 3, saver = 0 }

-- a near-white WARM tone (r >= g >= b, not saturated): the lamp colours the builders used
local function isWarmWhite(c: Color3): boolean
	local r, g, b = c.R, c.G, c.B
	local mx = math.max(r, g, b)
	return mx > 0.8 and r >= g and g >= b and b / mx > 0.5
end

local function warmLamp(light: Light, pos: Vector3?)
	if light:GetAttribute("KeepColor") == true or light:GetAttribute("GwLookWarm") == true then
		return
	end
	if not (light:IsA("SpotLight") or light:IsA("PointLight")) or not isWarmWhite(light.Color) then
		return
	end
	local pick = 0
	if pos then
		pick = (math.floor(pos.X / 9) * 7 + math.floor(pos.Z / 9) * 3) % 5
	end
	light.Color = if pick == 0 then WARM_3300K else WARM_3000K
	light.Brightness *= WARM_GAIN
	light:SetAttribute("GwLookWarm", true)
end

function Lights.start(ctx: any)
	local Config, Util, DayNight = ctx.Config, ctx.Util, ctx.DayNight

	local city: { [Light]: Rec } = {}
	local interior: { [Light]: Rec } = {}

	local function isAlwaysOn(light: Instance): boolean
		return light:GetAttribute("AlwaysOn") == true
	end

	local function adder(registry: { [Light]: Rec }, wantAlwaysOn: boolean)
		return function(inst: Instance)
			if not inst:IsA("Light") then
				return
			end
			-- A light carrying both tags counts as interior (AlwaysOn wins).
			if not wantAlwaysOn and isAlwaysOn(inst) then
				return
			end
			local light = inst :: Light
			local host = light.Parent
			local dynamic = host ~= nil and host:IsA("BasePart") and not host.Anchored
			local pos = Util.hostPosition(host)
			local heroOK = light:IsA("SpotLight") or light:GetAttribute("Hero") == true
			registry[light] = {
				light = light,
				on = false,
				d2 = 0,
				want = false,
				pos = pos,
				dynamic = dynamic,
				heroOK = heroOK and not wantAlwaysOn,
				shadow = false,
				shadowWant = false,
			}
			if light.Enabled then
				light.Enabled = false -- decided on the next evaluation (avoids a burst of lights)
			end
			if light.Shadows then
				light.Shadows = false -- only hero lights cast shadows (evaluate)
			end
			if not wantAlwaysOn then
				local ok, err = pcall(warmLamp, light, pos)
				if not ok then
					Util.warn("Lights", "warm lamp:", err)
				end
			end
		end
	end

	local function remover(registry: { [Light]: Rec })
		return function(inst: Instance)
			registry[inst :: Light] = nil
		end
	end

	Util.watchTag("CityLight", adder(city, false), remover(city))
	Util.watchTag("InteriorLight", adder(interior, true), remover(interior))

	-- A light whose host part is locally hidden (a venue interior zone or near-only detail hidden by
	-- DetailLOD with LocalTransparencyModifier) lights nothing the player can see: it gets no slot.
	local function hostHidden(light: Light): boolean
		local host = light.Parent
		if host and host:IsA("Attachment") then
			host = host.Parent
		end
		return host ~= nil and host:IsA("BasePart") and (host :: BasePart).LocalTransparencyModifier >= 1
	end

	local candidates: { Rec } = {}
	local function byDistance(a: Rec, b: Rec): boolean
		return a.d2 < b.d2
	end

	local function evaluate(registry: { [Light]: Rec }, camPos: Vector3, radius: number, limit: number, allowed: boolean, skipHidden: boolean, heroN: number)
		table.clear(candidates)
		local r2 = radius * radius
		if allowed and limit > 0 then
			for light, rec in registry do
				local pos = rec.pos
				if rec.dynamic or not pos then
					pos = Util.hostPosition(light.Parent)
					rec.pos = pos
				end
				if pos then
					local d = pos - camPos
					local d2 = d.X * d.X + d.Y * d.Y + d.Z * d.Z
					if d2 <= r2 and not (skipHidden and hostHidden(light)) then
						rec.d2 = d2
						table.insert(candidates, rec)
					end
				end
			end
			if #candidates > limit then
				table.sort(candidates, byDistance)
			end
			local chosen = math.min(limit, #candidates)
			for i = 1, chosen do
				candidates[i].want = true
			end
			-- hero shadows: the nearest heroN of the lights switched on
			if heroN > 0 and chosen > 0 then
				if #candidates <= limit and chosen > 1 then
					table.sort(candidates, byDistance)
				end
				local n = 0
				for i = 1, chosen do
					local rec = candidates[i]
					if rec.heroOK then
						rec.shadowWant = true
						n += 1
						if n >= heroN then
							break
						end
					end
				end
			end
		end
		for light, rec in registry do
			local want = rec.want
			rec.want = false
			if rec.on ~= want then
				rec.on = want
				light.Enabled = want
			end
			local shadowWant = want and rec.shadowWant
			rec.shadowWant = false
			if rec.shadow ~= shadowWant then
				rec.shadow = shadowWant
				light.Shadows = shadowWant
			end
		end
	end

	task.spawn(function()
		while true do
			task.wait(Config.Lights.EvaluateInterval)
			local camPos = Util.cameraPosition()
			if camPos then
				local ok, err = pcall(function()
					local budget = Util.budget(Config.Lights)
					local heroN = tonumber(budget.HeroShadows) or tonumber(Util.budget(HERO_DEFAULT)) or 0
					-- (street lamps light the street even where their fixture is near-only detail)
					evaluate(city, camPos, budget.CityRadius, budget.City, DayNight.isNight(), false, heroN)
					evaluate(interior, camPos, budget.InteriorRadius, budget.Interior, true, true, 0)
				end)
				if not ok then
					Util.warn("Lights", err)
				end
			end
		end
	end)
end

return Lights
