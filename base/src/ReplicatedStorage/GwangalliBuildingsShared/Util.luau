-- GwangalliBuildings/Util: pure helpers shared by the server and the client (formatting, geometry,
-- the elevator motion profile). No instances are created here.

local Util = {}

local floor, abs, sqrt, max, min = math.floor, math.abs, math.sqrt, math.max, math.min

-------------------------------------------------------------------------------------------------
-- formatting
-------------------------------------------------------------------------------------------------
function Util.comma(n: number): string
	local neg = n < 0
	local s = tostring(floor(abs(n) + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return (if neg then "-" else "") .. out
end

-- 12000000 -> "1,200만원", 48000000 -> "4,800만원", 3500 -> "3,500원"
function Util.won(n: number): string
	n = floor(n + 0.5)
	if abs(n) >= 100000000 then
		local eok = n // 100000000
		local man = (n % 100000000) // 10000
		return Util.comma(eok) .. "억" .. (if man > 0 then " " .. Util.comma(man) .. "만" else "") .. "원"
	elseif abs(n) >= 100000 and n % 10000 == 0 then
		return Util.comma(n // 10000) .. "만원"
	end
	return Util.comma(n) .. "원"
end

function Util.clock(seconds: number): string
	seconds = max(0, floor(seconds + 0.5))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- area in square studs -> "29.7㎡ (9평)"
function Util.area(sqStuds: number, mPerStud: number?): string
	local m = mPerStud or 0.3
	local m2 = sqStuds * m * m
	return string.format("%.1f㎡ (%d평)", m2, floor(m2 / 3.3058 + 0.5))
end

function Util.clamp(x: number, a: number, b: number): number
	return if x < a then a elseif x > b then b else x
end

function Util.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function Util.round(x: number, step: number): number
	return floor(x / step + 0.5) * step
end

function Util.split(s: string?, sep: string?): { string }
	local out = {}
	if type(s) ~= "string" or s == "" then
		return out
	end
	for part in string.gmatch(s, "[^" .. (sep or "|") .. "]+") do
		table.insert(out, part)
	end
	return out
end

function Util.numList(s: string?, sep: string?): { number }
	local out = {}
	for _, p in Util.split(s, sep or ",") do
		local n = tonumber(p)
		if n then
			table.insert(out, n)
		end
	end
	return out
end

-------------------------------------------------------------------------------------------------
-- geometry
-------------------------------------------------------------------------------------------------
-- is the world point inside the oriented box (cf, size) grown by `pad`?
function Util.inBox(cf: CFrame, size: Vector3, p: Vector3, pad: number?): boolean
	local l = cf:PointToObjectSpace(p)
	local g = pad or 0
	return abs(l.X) <= size.X / 2 + g and abs(l.Y) <= size.Y / 2 + g and abs(l.Z) <= size.Z / 2 + g
end

-- distance from a world point to an oriented box (0 inside)
function Util.boxDistance(cf: CFrame, size: Vector3, p: Vector3): number
	local l = cf:PointToObjectSpace(p)
	local dx = max(0, abs(l.X) - size.X / 2)
	local dy = max(0, abs(l.Y) - size.Y / 2)
	local dz = max(0, abs(l.Z) - size.Z / 2)
	return sqrt(dx * dx + dy * dy + dz * dz)
end

-- yaw-only CFrame at p facing direction dir (horizontal)
function Util.facing(p: Vector3, dir: Vector3): CFrame
	local d = Vector3.new(dir.X, 0, dir.Z)
	if d.Magnitude < 1e-4 then
		return CFrame.new(p)
	end
	return CFrame.lookAt(p, p + d.Unit)
end

-- yaw angle (degrees) of a CFrame's look vector, 0 = -Z
function Util.yaw(cf: CFrame): number
	local lv = cf.LookVector
	return math.deg(math.atan2(-lv.X, -lv.Z))
end

-------------------------------------------------------------------------------------------------
-- Elevator motion profile (trapezoidal: accelerate, cruise, decelerate). A segment starts at y0 at
-- server time t0 moving toward y1 with speed v0 (>= 0, along the travel direction). The server
-- publishes segments as attributes; every client evaluates the same function, so all cars move
-- smoothly and in sync without the server writing the car CFrame every frame.
-------------------------------------------------------------------------------------------------
export type Seg = { y0: number, y1: number, t0: number, v0: number, vmax: number, a: number }

local function plan(seg: Seg)
	local D = abs(seg.y1 - seg.y0)
	local a, vmax = seg.a, seg.vmax
	local u = min(max(seg.v0 or 0, 0), vmax)
	if D < 1e-4 then
		return { D = 0, u = 0, vp = 0, t1 = 0, t2 = 0, t3 = 0, d1 = 0, d2 = 0, dec = a, total = 0 }
	end
	local brake = u * u / (2 * a)
	if brake >= D then
		-- cannot stop in time with the nominal deceleration: brake harder (fallback; the server avoids it)
		local dec = u * u / (2 * D)
		local t3 = u / dec
		return { D = D, u = u, vp = u, t1 = 0, t2 = 0, t3 = t3, d1 = 0, d2 = 0, dec = dec, total = t3 }
	end
	local vp = vmax
	local d1 = (vp * vp - u * u) / (2 * a)
	local d3 = vp * vp / (2 * a)
	local d2 = D - d1 - d3
	if d2 < 0 then
		vp = sqrt(a * D + u * u / 2)
		d1 = (vp * vp - u * u) / (2 * a)
		d3 = vp * vp / (2 * a)
		d2 = 0
	end
	local t1 = (vp - u) / a
	local t2 = if vp > 0 then d2 / vp else 0
	local t3 = vp / a
	return { D = D, u = u, vp = vp, t1 = t1, t2 = t2, t3 = t3, d1 = d1, d2 = d2, dec = a, total = t1 + t2 + t3 }
end
Util.planSeg = plan

-- -> y, v (signed world velocity), done
function Util.evalSeg(seg: Seg, t: number): (number, number, boolean)
	local p = plan(seg)
	local dir = if seg.y1 >= seg.y0 then 1 else -1
	local tau = t - seg.t0
	if p.total <= 0 or tau >= p.total then
		return seg.y1, 0, true
	end
	if tau <= 0 then
		return seg.y0, dir * p.u, false
	end
	local s, v
	if tau < p.t1 then
		v = p.u + seg.a * tau
		s = p.u * tau + 0.5 * seg.a * tau * tau
	elseif tau < p.t1 + p.t2 then
		local k = tau - p.t1
		v = p.vp
		s = p.d1 + p.vp * k
	else
		local k = tau - p.t1 - p.t2
		v = max(0, p.vp - p.dec * k)
		s = p.d1 + p.d2 + p.vp * k - 0.5 * p.dec * k * k
	end
	s = min(s, p.D)
	return seg.y0 + dir * s, dir * v, false
end

function Util.segDuration(seg: Seg): number
	return plan(seg).total
end

-- shortest distance a car moving at speed v can stop in
function Util.brakeDistance(v: number, a: number): number
	return v * v / (2 * a)
end

-------------------------------------------------------------------------------------------------
-- misc
-------------------------------------------------------------------------------------------------
function Util.shallowCopy<T>(t: T): T
	return table.clone(t :: any) :: any
end

-- stable short id
local counter = 0
function Util.uid(prefix: string?): string
	counter += 1
	return string.format("%s%x%x", prefix or "", floor(os.clock() * 1000) % 0xFFFFF, counter)
end

function Util.color3(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

-- darken / desaturate a colour by a wear amount (0 = new, 1 = very old)
function Util.age(c: any, wear: number, tint: Color3?): Color3
	if type(c) == "table" then
		c = Color3.fromRGB(c[1], c[2], c[3])
	end
	local h, s, v = (c :: Color3):ToHSV()
	local k = Util.clamp(wear, 0, 1)
	local aged = Color3.fromHSV(h, s * (1 - 0.35 * k), v * (1 - 0.22 * k))
	if tint then
		aged = aged:Lerp(tint, 0.18 * k)
	end
	return aged
end

return Util
