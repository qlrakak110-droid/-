-- Interact/Hazard (server): cars and the city NPCs. Reads the existing vehicle interfaces only:
-- drivable cars (CollectionService tag GwangalliVehiclesShared.Tag, DriveBase part, DriveDriver /
-- DriveOwner / DriveState attributes), the phone taxis (Workspace.GwangalliTaxis, CFrame-moved) and our
-- own patrol cars. Same thresholds as the client street crowd (fast 25 studs/s, time-to-contact 1.5 s)
-- so both layers react alike: a step aside (slow car) / a dive (fast car) + a shout at the driver, a
-- near miss is a small incident (난폭 운전), a hit knocks the NPC down and is a real one (교통사고:
-- the witnesses call it in; a player driver who hits somebody becomes a suspect). Horns make people look.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Hazard = {}

local I: any
local Mind: any
local Actors: any
local World: any
local VS: any = nil

local FAST, TTC, REACH, HORN_REACH = 25, 1.5, 40, 30
local seen: { [Instance]: any } = setmetatable({}, { __mode = "k" }) :: any

local function flatVel(m: Instance, part: BasePart, now: number): (Vector3, number)
	local s = seen[m]
	local v = part.AssemblyLinearVelocity
	v = Vector3.new(v.X, 0, v.Z)
	if not s then
		local half = 3.1
		if VS and VS.decodeRig and VS.Attr then
			local ok, rig = pcall(VS.decodeRig, m:GetAttribute(VS.Attr.Rig))
			if ok and type(rig) == "table" and rig.W then
				half = rig.W / 2
			end
		end
		s = { p = part.Position, t = now, v = Vector3.zero, half = half }
		seen[m] = s
	elseif now - s.t > 0.05 then
		local d = (part.Position - s.p) / (now - s.t)
		d = Vector3.new(d.X, 0, d.Z)
		s.v = if d.Magnitude > 200 then Vector3.zero else s.v:Lerp(d, 0.7)
		s.p, s.t = part.Position, now
	end
	return (if v.Magnitude < 1 then s.v else v), s.half
end

local function movers(now: number): { any }
	local out = {}
	if VS and VS.Tag then
		for _, m in CollectionService:GetTagged(VS.Tag) do
			local base = m:GetAttribute(VS.Attr.Sleeping) ~= true and m:FindFirstChild(VS.Parts and VS.Parts.Base or "DriveBase")
			if base and base:IsA("BasePart") then
				local uid = m:GetAttribute(VS.Attr.Driver) or 0
				local vel, half = flatVel(m, base, now)
				local state = m:GetAttribute(VS.Attr.State) or 0
				table.insert(out, {
					pos = base.Position,
					vel = vel,
					half = half,
					horn = VS.Bits and type(state) == "number" and bit32.btest(state, VS.Bits.HORN) or false,
					driver = if uid ~= 0 then Players:GetPlayerByUserId(uid) else nil,
				})
			end
		end
	end
	for _, folderName in { "GwangalliTaxis", "GwangalliInteractCars" } do
		local f = workspace:FindFirstChild(folderName)
		if f then
			for _, m in f:GetChildren() do
				local r = m:IsA("Model") and m.PrimaryPart
				if r then
					local vel, half = flatVel(m, r, now)
					table.insert(out, { pos = r.Position, vel = vel, half = half, scripted = true })
				end
			end
		end
	end
	return out
end
Hazard.movers = movers

local function threat(c: any, p: Vector3): (number?, number?, Vector3?, number?)
	local sp = c.vel.Magnitude
	if sp < 8 or math.abs(p.Y - c.pos.Y) > 8 then
		return nil
	end
	local rx, rz = p.X - c.pos.X, p.Z - c.pos.Z
	local reach = math.max(REACH, sp * TTC * 1.15)
	if rx * rx + rz * rz > reach * reach then
		return nil
	end
	local ttc = (rx * c.vel.X + rz * c.vel.Z) / (sp * sp)
	if ttc <= 0 or ttc > TTC then
		return nil
	end
	local cx, cz = rx - c.vel.X * ttc, rz - c.vel.Z * ttc
	local px, pz = -c.vel.Z / sp, c.vel.X / sp
	local s = if cx * px + cz * pz >= 0 then 1 else -1
	return ttc, math.sqrt(cx * cx + cz * cz) - c.half, Vector3.new(px * s, 0, pz * s), sp
end

local DODGE_LINE = "vehicle_dodge"

function Hazard.step(now: number)
	local cars = movers(now)
	if #cars == 0 then
		return
	end
	for _, n in Mind.list do
		local a = n.a
		if n.present and a and not a.gone and n.lod ~= "far" and not Actors.isDown(a) and not (n.dodgeUntil and now < n.dodgeUntil) and n.mode ~= "custody" then
			local p = Actors.pos(a)
			for _, c in cars do
				local ttc, gap, dir, sp = threat(c, p)
				if ttc and gap and dir and sp then
					local driverKey = c.driver and ("p:" .. c.driver.UserId) or nil
					if gap < 0.6 and sp >= 18 and not c.scripted then
						-- struck
						n.dodgeUntil = now + 3
						Mind.hitNPC(n, nil, math.floor(math.min(60, sp * 1.2)), "ko", c.vel.X / sp, c.vel.Z / sp, driverKey)
						local inc = World.incident("vehicle", p, { aggressor = driverKey, victim = "n:" .. n.id })
						if c.driver then
							I.crime(c.driver, "vehicle", p)
						end
						local _ = inc
						break
					elseif gap < 2.5 and sp > FAST or gap < 1.5 then
						n.dodgeUntil = now + 1.2
						local fast = sp > FAST
						local to = p + dir * (if fast then 5 else 2.6)
						if n.mode == "routine" then
							Mind.setMode(n, "dodge", 2.5)
						end
						Actors.walkTo(a, Vector3.new(to.X, Actors.groundAt(to + Vector3.new(0, 2, 0), p.Y), to.Z), if fast then 20 else 8, true)
						Actors.face(a, c.pos)
						Actors.emote(a, "hurt")
						Mind.say(n, DODGE_LINE)
						Mind.feel(n, { fear = 0.25, anger = 0.2 })
						if fast and driverKey then
							World.incident("near_miss", p, { aggressor = driverKey, victim = "n:" .. n.id })
							task.delay(1.4, function()
								if n.present and n.a then
									Mind.say(n, "vehicle_complain")
									Actors.emote(n.a, "point")
									if c.driver then
										local pl = c.driver
										I.crime(pl, "reckless", p)
										Mind.provoke(n, driverKey, 1, "car", "other")
									end
								end
							end)
						end
						break
					end
				elseif c.horn and (c.pos - p).Magnitude < HORN_REACH and now - (n.hornAt or -1e9) > 3 then
					n.hornAt = now
					Actors.face(a, c.pos)
					if math.random() < 0.3 then
						Mind.say(n, "vehicle_complain")
					end
				end
			end
		end
	end
end

function Hazard.init(interact: any)
	I = interact
	Mind = I.Mind
	Actors = I.Actors
	World = I.World
	local m = ReplicatedStorage:FindFirstChild("GwangalliVehiclesShared")
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			VS = res
		end
	end
	task.spawn(function()
		while true do
			task.wait(0.1)
			local ok, err = pcall(Hazard.step, os.clock())
			if not ok then
				warn("[GwangalliCity] hazard: " .. tostring(err))
				task.wait(2)
			end
		end
	end)
end

return Hazard
