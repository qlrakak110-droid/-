--!strict
-- GwangalliDecorShared/Geometry: pure box math used by the placement rules on both sides.
--   OBB = { cf: CFrame, half: Vector3 } (oriented box, centre frame + half extents)
--   Geometry.obb / move / shrink / inflate / aabb / overlap (SAT) / pointIn / ray (slab) / corners
--   Geometry.pose(x, y, z, r) -> CFrame (unit frame pose of a piece: y = bottom, r = yaw degrees, front = -Z)
--   Geometry.snap / snapYaw / yawOf / wrapYaw

local Geometry = {}

export type OBB = { cf: CFrame, half: Vector3 }

local abs, max, min, rad, deg = math.abs, math.max, math.min, math.rad, math.deg
local EPS = 1e-6

function Geometry.obb(cf: CFrame, half: Vector3): OBB
	return { cf = cf, half = half }
end

-- box seen from another frame: frame * box
function Geometry.move(b: OBB, frame: CFrame): OBB
	return { cf = frame * b.cf, half = b.half }
end

function Geometry.shrink(b: OBB, d: number): OBB
	local h = b.half
	return { cf = b.cf, half = Vector3.new(max(0.02, h.X - d), max(0.02, h.Y - d), max(0.02, h.Z - d)) }
end

function Geometry.inflate(b: OBB, dx: number, dy: number?, dz: number?): OBB
	local h = b.half
	return { cf = b.cf, half = Vector3.new(max(0.01, h.X + dx), max(0.01, h.Y + (dy or dx)), max(0.01, h.Z + (dz or dx))) }
end

-- axis-aligned bounds of an OBB (in the OBB's parent frame)
function Geometry.aabb(b: OBB): (Vector3, Vector3)
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = b.cf:GetComponents()
	local h = b.half
	local ex = abs(r00) * h.X + abs(r01) * h.Y + abs(r02) * h.Z
	local ey = abs(r10) * h.X + abs(r11) * h.Y + abs(r12) * h.Z
	local ez = abs(r20) * h.X + abs(r21) * h.Y + abs(r22) * h.Z
	local p = b.cf.Position
	return Vector3.new(p.X - ex, p.Y - ey, p.Z - ez), Vector3.new(p.X + ex, p.Y + ey, p.Z + ez)
end

function Geometry.aabbOverlap(alo: Vector3, ahi: Vector3, blo: Vector3, bhi: Vector3, eps: number?): boolean
	local e = eps or 0
	return alo.X < bhi.X - e and blo.X < ahi.X - e and alo.Y < bhi.Y - e and blo.Y < ahi.Y - e and alo.Z < bhi.Z - e and blo.Z < ahi.Z - e
end

-- separating axis test of two OBBs (Gottschalk; 15 axes)
function Geometry.overlap(a: OBB, b: OBB): boolean
	local _, _, _, a00, a01, a02, a10, a11, a12, a20, a21, a22 = a.cf:GetComponents()
	local _, _, _, b00, b01, b02, b10, b11, b12, b20, b21, b22 = b.cf:GetComponents()
	-- axes as columns
	local A = { { a00, a10, a20 }, { a01, a11, a21 }, { a02, a12, a22 } }
	local B = { { b00, b10, b20 }, { b01, b11, b21 }, { b02, b12, b22 } }
	local ea = { a.half.X, a.half.Y, a.half.Z }
	local eb = { b.half.X, b.half.Y, b.half.Z }
	local d = b.cf.Position - a.cf.Position
	local t = {
		d.X * A[1][1] + d.Y * A[1][2] + d.Z * A[1][3],
		d.X * A[2][1] + d.Y * A[2][2] + d.Z * A[2][3],
		d.X * A[3][1] + d.Y * A[3][2] + d.Z * A[3][3],
	}
	local R = {}
	local AR = {}
	for i = 1, 3 do
		R[i] = {}
		AR[i] = {}
		for j = 1, 3 do
			local v = A[i][1] * B[j][1] + A[i][2] * B[j][2] + A[i][3] * B[j][3]
			R[i][j] = v
			AR[i][j] = abs(v) + EPS
		end
	end
	for i = 1, 3 do
		local ra = ea[i]
		local rb = eb[1] * AR[i][1] + eb[2] * AR[i][2] + eb[3] * AR[i][3]
		if abs(t[i]) > ra + rb then
			return false
		end
	end
	for j = 1, 3 do
		local ra = ea[1] * AR[1][j] + ea[2] * AR[2][j] + ea[3] * AR[3][j]
		local rb = eb[j]
		local tj = t[1] * R[1][j] + t[2] * R[2][j] + t[3] * R[3][j]
		if abs(tj) > ra + rb then
			return false
		end
	end
	-- cross products
	for i = 1, 3 do
		local i1, i2 = (i % 3) + 1, ((i + 1) % 3) + 1
		for j = 1, 3 do
			local j1, j2 = (j % 3) + 1, ((j + 1) % 3) + 1
			local ra = ea[i1] * AR[i2][j] + ea[i2] * AR[i1][j]
			local rb = eb[j1] * AR[i][j2] + eb[j2] * AR[i][j1]
			local tt = t[i2] * R[i1][j] - t[i1] * R[i2][j]
			if abs(tt) > ra + rb then
				return false
			end
		end
	end
	return true
end

-- overlap with a cheap AABB reject first (lo/hi cached on the boxes when present)
function Geometry.overlapFast(a: any, b: any): boolean
	local alo, ahi = a.lo, a.hi
	if not alo then
		alo, ahi = Geometry.aabb(a)
	end
	local blo, bhi = b.lo, b.hi
	if not blo then
		blo, bhi = Geometry.aabb(b)
	end
	if not Geometry.aabbOverlap(alo, ahi, blo, bhi) then
		return false
	end
	return Geometry.overlap(a, b)
end

-- caches lo / hi on a box (for overlapFast)
function Geometry.prime(b: any): any
	b.lo, b.hi = Geometry.aabb(b)
	return b
end

function Geometry.pointIn(b: OBB, p: Vector3, pad: number?): boolean
	local q = b.cf:PointToObjectSpace(p)
	local e = pad or 0
	local h = b.half
	return abs(q.X) <= h.X + e and abs(q.Y) <= h.Y + e and abs(q.Z) <= h.Z + e
end

-- horizontal containment only (ignores the box's height)
function Geometry.pointInXZ(b: OBB, p: Vector3, pad: number?): boolean
	local q = b.cf:PointToObjectSpace(Vector3.new(p.X, b.cf.Position.Y, p.Z))
	local e = pad or 0
	local h = b.half
	return abs(q.X) <= h.X + e and abs(q.Z) <= h.Z + e
end

-- ray (origin, direction with length) against an OBB: distance fraction t in [0, 1] + world normal
function Geometry.ray(b: OBB, origin: Vector3, dir: Vector3): (number?, Vector3?)
	local o = b.cf:PointToObjectSpace(origin)
	local d = b.cf:VectorToObjectSpace(dir)
	local h = b.half
	local tmin, tmax = -math.huge, math.huge
	local nAxis, nSign = 0, 0
	local oc = { o.X, o.Y, o.Z }
	local dc = { d.X, d.Y, d.Z }
	local hc = { h.X, h.Y, h.Z }
	for i = 1, 3 do
		if abs(dc[i]) < 1e-9 then
			if oc[i] < -hc[i] or oc[i] > hc[i] then
				return nil, nil
			end
		else
			local t1 = (-hc[i] - oc[i]) / dc[i]
			local t2 = (hc[i] - oc[i]) / dc[i]
			local s = -1
			if t1 > t2 then
				t1, t2 = t2, t1
				s = 1
			end
			if t1 > tmin then
				tmin = t1
				nAxis, nSign = i, s
			end
			if t2 < tmax then
				tmax = t2
			end
			if tmin > tmax then
				return nil, nil
			end
		end
	end
	if tmax < 0 or tmin > 1 then
		return nil, nil
	end
	if tmin < 0 then
		-- origin inside the box
		return 0, -dir.Unit
	end
	local n = if nAxis == 1 then Vector3.new(nSign, 0, 0) elseif nAxis == 2 then Vector3.new(0, nSign, 0) else Vector3.new(0, 0, nSign)
	return tmin, b.cf:VectorToWorldSpace(n)
end

-- the 8 corners
function Geometry.corners(b: OBB): { Vector3 }
	local out = {}
	local h = b.half
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				table.insert(out, b.cf:PointToWorldSpace(Vector3.new(sx * h.X, sy * h.Y, sz * h.Z)))
			end
		end
	end
	return out
end

-- the 4 bottom corners pulled in by `inset`
function Geometry.footCorners(b: OBB, inset: number?): { Vector3 }
	local out = {}
	local h = b.half
	local e = inset or 0
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			table.insert(out, b.cf:PointToWorldSpace(Vector3.new(sx * max(0.02, h.X - e), -h.Y, sz * max(0.02, h.Z - e))))
		end
	end
	return out
end

-- vertical faces of an upright box: { c = centre, n = outward normal (horizontal), u = tangent,
-- hu = half width along u, hv = half height }
function Geometry.sideFaces(b: OBB): { any }
	local out = {}
	local cf, h = b.cf, b.half
	if abs(cf.UpVector.Y) < 0.9 then
		return out -- tilted box: no wall faces
	end
	local rv, lv = cf.RightVector, cf.LookVector
	local function flat(v: Vector3): Vector3
		local f = Vector3.new(v.X, 0, v.Z)
		return if f.Magnitude > 1e-6 then f.Unit else Vector3.new(1, 0, 0)
	end
	local R, L = flat(rv), flat(lv)
	for _, s in { -1, 1 } do
		table.insert(out, { c = cf.Position + rv * (h.X * s), n = R * s, u = L, hu = h.Z, hv = h.Y })
		table.insert(out, { c = cf.Position + lv * (h.Z * s), n = L * s, u = R, hu = h.X, hv = h.Y })
	end
	return out
end

-------------------------------------------------------------------------------------------------
-- Poses / snapping
-------------------------------------------------------------------------------------------------
function Geometry.pose(x: number, y: number, z: number, r: number): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(0, rad(r), 0)
end

function Geometry.wrapYaw(r: number): number
	local v = r % 360
	if v < 0 then
		v += 360
	end
	if v >= 359.995 then
		v = 0
	end
	return v
end

-- yaw (degrees) of a frame whose front is -Z
function Geometry.yawOf(cf: CFrame): number
	local lv = cf.LookVector
	return Geometry.wrapYaw(deg(math.atan2(-lv.X, -lv.Z)))
end

-- yaw that makes a piece's front (-Z) face along the horizontal direction n
function Geometry.yawFacing(n: Vector3): number
	return Geometry.wrapYaw(deg(math.atan2(-n.X, -n.Z)))
end

function Geometry.snap(v: number, step: number?): number
	if not step or step <= 0 then
		return math.floor(v * 100 + 0.5) / 100
	end
	return math.floor(v / step + 0.5) * step
end

function Geometry.snapYaw(r: number, step: number?): number
	if not step or step <= 1 then
		return Geometry.wrapYaw(math.floor(r + 0.5))
	end
	return Geometry.wrapYaw(math.floor(r / step + 0.5) * step)
end

-- the unit frame of a home (UnitRoot position, its rotation)
function Geometry.unitFrame(root: any): CFrame
	local cf: CFrame = root.CFrame
	return CFrame.new(cf.Position) * cf.Rotation
end

function Geometry.finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function Geometry.round(v: number, q: number): number
	return math.floor(v / q + 0.5) * q
end

function Geometry.clampV(v: number, lo: number, hi: number): number
	return min(hi, max(lo, v))
end

return Geometry
