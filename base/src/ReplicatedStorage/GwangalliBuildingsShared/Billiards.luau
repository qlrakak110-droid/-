-- GwangalliBuildings/Billiards: a small deterministic 2D carom simulation for the 당구장 (4구).
-- The server simulates a shot once and sends the recorded frames to every client, which replays them
-- on the ball parts; the final positions are then written on the server. Pure (no instances).
--
--   local sim = Billiards.new()                       -- 4 balls racked (1 white = cue, 2/3 red, 4 yellow)
--   local frames, result = Billiards.shoot(sim, cueIndex, angle, power)
--     frames: { {t, x1, z1, x2, z2, ...}, ... } at 30 Hz; result: { hits = {..}, score = 0 | 1, foul }
-- Table space: x in [-W/2, W/2] (long side), z in [-H/2, H/2]. Units are studs.

local Billiards = {}

Billiards.W = 12 -- play area length
Billiards.H = 6 -- play area width
Billiards.R = 0.26 -- ball radius
Billiards.FRICTION = 1.6 -- studs / s^2 (rolling)
Billiards.CUSHION = 0.78
Billiards.BALL_E = 0.96
Billiards.MAX_SPEED = 16
Billiards.MIN_SPEED = 1.5
Billiards.DT = 1 / 240
Billiards.REC = 1 / 30
Billiards.MAX_T = 14

Billiards.COLORS = {
	{ 250, 250, 246 }, -- white (cue)
	{ 220, 30, 30 }, -- red
	{ 220, 30, 30 }, -- red
	{ 250, 200, 40 }, -- yellow
}

function Billiards.new(): any
	local W = Billiards.W
	return {
		balls = {
			{ x = -W * 0.25, z = 0.6, vx = 0, vz = 0 },
			{ x = W * 0.25, z = 0, vx = 0, vz = 0 },
			{ x = -W * 0.32, z = -0.4, vx = 0, vz = 0 },
			{ x = -W * 0.25, z = -0.9, vx = 0, vz = 0 },
		},
		score = 0,
		shots = 0,
	}
end

local function moving(b): boolean
	return b.vx * b.vx + b.vz * b.vz > 1e-4
end

function Billiards.shoot(sim: any, cue: number, angle: number, power: number): ({ any }, any)
	local balls = sim.balls
	local R, W2, H2 = Billiards.R, Billiards.W / 2, Billiards.H / 2
	local speed = Billiards.MIN_SPEED + math.clamp(power, 0, 1) * (Billiards.MAX_SPEED - Billiards.MIN_SPEED)
	local cb = balls[cue]
	cb.vx, cb.vz = math.cos(angle) * speed, math.sin(angle) * speed
	local hits = {}
	local cushions = 0
	local frames = {}
	local t, nextRec = 0, 0
	local dt = Billiards.DT
	local function record()
		local f = { t }
		for _, b in balls do
			table.insert(f, math.floor(b.x * 1000 + 0.5) / 1000)
			table.insert(f, math.floor(b.z * 1000 + 0.5) / 1000)
		end
		table.insert(frames, f)
	end
	record()
	while t < Billiards.MAX_T do
		local any = false
		for _, b in balls do
			if moving(b) then
				any = true
				-- friction
				local v = math.sqrt(b.vx * b.vx + b.vz * b.vz)
				local nv = math.max(0, v - Billiards.FRICTION * dt)
				if nv < 0.03 then
					b.vx, b.vz = 0, 0
				else
					b.vx, b.vz = b.vx * nv / v, b.vz * nv / v
				end
				b.x += b.vx * dt
				b.z += b.vz * dt
				-- cushions
				if b.x < -W2 + R then
					b.x = -W2 + R
					b.vx = -b.vx * Billiards.CUSHION
					if b == cb then
						cushions += 1
					end
				elseif b.x > W2 - R then
					b.x = W2 - R
					b.vx = -b.vx * Billiards.CUSHION
					if b == cb then
						cushions += 1
					end
				end
				if b.z < -H2 + R then
					b.z = -H2 + R
					b.vz = -b.vz * Billiards.CUSHION
					if b == cb then
						cushions += 1
					end
				elseif b.z > H2 - R then
					b.z = H2 - R
					b.vz = -b.vz * Billiards.CUSHION
					if b == cb then
						cushions += 1
					end
				end
			end
		end
		-- ball-ball collisions (equal masses)
		for i = 1, #balls - 1 do
			for j = i + 1, #balls do
				local a, b = balls[i], balls[j]
				local dx, dz = b.x - a.x, b.z - a.z
				local d2 = dx * dx + dz * dz
				if d2 < (2 * R) ^ 2 and d2 > 1e-9 then
					local d = math.sqrt(d2)
					local nx, nz = dx / d, dz / d
					local rv = (a.vx - b.vx) * nx + (a.vz - b.vz) * nz
					if rv > 0 then
						local imp = rv * (1 + Billiards.BALL_E) / 2
						a.vx -= imp * nx
						a.vz -= imp * nz
						b.vx += imp * nx
						b.vz += imp * nz
						if i == cue then
							hits[j] = hits[j] or t
						elseif j == cue then
							hits[i] = hits[i] or t
						end
					end
					-- separate
					local push = (2 * R - d) / 2
					a.x -= nx * push
					a.z -= nz * push
					b.x += nx * push
					b.z += nz * push
				end
			end
		end
		t += dt
		if t >= nextRec then
			nextRec += Billiards.REC
			record()
		end
		if not any then
			break
		end
	end
	record()
	-- 4구 scoring with white as the cue ball: both reds, never the yellow
	local reds = 0
	for idx = 1, #balls do
		if idx ~= cue and idx ~= 4 and hits[idx] then
			reds += 1
		end
	end
	local foul = hits[4] ~= nil and cue ~= 4
	local score = if reds >= 2 and not foul then 1 else 0
	sim.shots += 1
	sim.score += score
	return frames, { hits = hits, score = score, foul = foul, cushions = cushions, reds = reds }
end

return Billiards
