--!strict
-- GwangalliDecorShared/Codec: compact save format of the 자유 배치 add-on + strict sanitizer (the server
-- runs every loaded blob and every client payload through it).
-- A placed piece in memory:  { u, i, x, y, z, r, c = { [slot] = "rrggbb" | false }?, m = { [slot] = n }?, on = bool? }
--   (unit frame of the home's UnitRoot; y = bottom of the piece; r = yaw degrees)
-- Saved as one string "u|i|x|y|z|r|c|m|f": x z in 1/100 stud, y in 1/1000 stud, r in 1/10 degree,
--   c = comma list of hex (empty = default colour), m = material digits (empty = default), f = flags (1 = on)
-- DataStore blob: { v, homes = { [listingId] = { items = { "..." }, n = nextUid, fin = finish } },
--   storage = { [itemId] = n }, presets = { [tierKey] = { [1..3] = { n, t, items, fin } } }, likes, gb,
--   badges, goals, stats, photo, best }

local Catalog = require(script.Parent:WaitForChild("Catalog"))
local Config = require(script.Parent:WaitForChild("Config"))
local Finish = require(script.Parent:WaitForChild("Finish"))
local Geometry = require(script.Parent:WaitForChild("Geometry"))

local Codec = {}

Codec.VERSION = 1

local finite = Geometry.finite

local function hexOk(s: any): boolean
	return type(s) == "string" and #s == 6 and string.match(s, "^%x%x%x%x%x%x$") ~= nil
end

-- cleans a look: colours per slot (hex | false), materials per slot (index into the slot's mats)
function Codec.cleanLook(def: any, c: any, m: any): ({ any }?, { number }?)
	local cOut, mOut = nil, nil
	if type(c) == "table" then
		for i, s in def.slots do
			local v = c[i]
			if hexOk(v) then
				cOut = cOut or {}
				;(cOut :: any)[i] = string.lower(v)
			end
			local _ = s
		end
		if cOut then
			for i = 1, #def.slots do
				if (cOut :: any)[i] == nil then
					(cOut :: any)[i] = false
				end
			end
		end
	end
	if type(m) == "table" then
		for i, s in def.slots do
			local v = m[i]
			if type(v) == "number" and v == math.floor(v) and v >= 2 and v <= #s.mats then
				mOut = mOut or {}
				;(mOut :: any)[i] = v
			end
		end
		if mOut then
			for i = 1, #def.slots do
				if (mOut :: any)[i] == nil then
					(mOut :: any)[i] = 1
				end
			end
		end
	end
	return cOut, mOut
end

-- a record from untrusted data -> clean record | nil
function Codec.cleanRecord(raw: any): any?
	if type(raw) ~= "table" then
		return nil
	end
	local def = Catalog.get(raw.i)
	if not def then
		return nil
	end
	local u = raw.u
	if type(u) ~= "number" or u ~= math.floor(u) or u < 1 or u > 1e7 then
		return nil
	end
	local x, y, z, r = raw.x, raw.y, raw.z, raw.r or 0
	if not (finite(x) and finite(y) and finite(z) and finite(r)) then
		return nil
	end
	if math.abs(x) > Config.HOME_HALF or math.abs(z) > Config.HOME_HALF or y < Config.HOME_Y[1] or y > Config.HOME_Y[2] then
		return nil
	end
	local c, m = Codec.cleanLook(def, raw.c, raw.m)
	return {
		u = u,
		i = raw.i,
		x = Geometry.round(x, 0.01),
		y = Geometry.round(y, 0.001),
		z = Geometry.round(z, 0.01),
		r = Geometry.round(Geometry.wrapYaw(r), 0.1),
		c = c,
		m = m,
		on = if raw.on == false then false else nil,
	}
end

function Codec.encode(rec: any): string
	local cs = ""
	if rec.c then
		local t = {}
		local last = 0
		for i, v in rec.c do
			if type(v) == "string" then
				last = math.max(last, i)
			end
		end
		for i = 1, last do
			t[i] = if type(rec.c[i]) == "string" then rec.c[i] else ""
		end
		cs = table.concat(t, ",")
	end
	local ms = ""
	if rec.m then
		local t = {}
		local last = 0
		for i, v in rec.m do
			if type(v) == "number" and v > 1 then
				last = math.max(last, i)
			end
		end
		for i = 1, last do
			t[i] = tostring(math.clamp(rec.m[i] or 1, 1, 9))
		end
		ms = table.concat(t)
	end
	local f = if rec.on == false then 1 else 0
	return string.format(
		"%d|%s|%d|%d|%d|%d|%s|%s|%d",
		rec.u,
		rec.i,
		math.floor(rec.x * 100 + 0.5),
		math.floor(rec.y * 1000 + 0.5),
		math.floor(rec.z * 100 + 0.5),
		math.floor(rec.r * 10 + 0.5),
		cs,
		ms,
		f
	)
end

function Codec.decode(s: any): any?
	if type(s) ~= "string" or #s > 200 then
		return nil
	end
	local p = string.split(s, "|")
	if #p < 6 then
		return nil
	end
	local raw: any = {
		u = tonumber(p[1]),
		i = p[2],
		x = (tonumber(p[3]) or 0) / 100,
		y = (tonumber(p[4]) or 0) / 1000,
		z = (tonumber(p[5]) or 0) / 100,
		r = (tonumber(p[6]) or 0) / 10,
	}
	if p[7] and p[7] ~= "" then
		raw.c = {}
		for i, h in string.split(p[7], ",") do
			raw.c[i] = if h ~= "" then h else false
		end
	end
	if p[8] and p[8] ~= "" then
		raw.m = {}
		for i = 1, #p[8] do
			raw.m[i] = tonumber(string.sub(p[8], i, i))
		end
	end
	if p[9] and (tonumber(p[9]) or 0) % 2 == 1 then
		raw.on = false
	end
	return Codec.cleanRecord(raw)
end

-------------------------------------------------------------------------------------------------
-- Blob
-------------------------------------------------------------------------------------------------
function Codec.newData(): any
	return {
		v = Codec.VERSION,
		homes = {},
		storage = {},
		presets = {},
		likes = 0,
		gb = {},
		badges = {},
		goals = {},
		stats = {},
		photo = { d = 0, n = 0 },
		best = 0,
	}
end

local function cleanKey(k: any, n: number): boolean
	return type(k) == "string" and #k > 0 and #k <= n
end

local function cleanItems(list: any, cap: number): ({ any }, number)
	local out = {}
	local seen = {}
	local maxU = 0
	if type(list) ~= "table" then
		return out, 0
	end
	for _, s in list do
		if #out >= cap then
			break
		end
		local rec = if type(s) == "string" then Codec.decode(s) else Codec.cleanRecord(s)
		if rec and not seen[rec.u] then
			seen[rec.u] = true
			table.insert(out, rec)
			maxU = math.max(maxU, rec.u)
		end
	end
	return out, maxU
end
Codec.cleanItems = cleanItems

local function num(v: any, lo: number, hi: number, d: number): number
	if type(v) ~= "number" or v ~= v then
		return d
	end
	return math.clamp(v, lo, hi)
end

-- loaded / untrusted blob -> clean in-memory data (items decoded)
function Codec.sanitize(raw: any): any
	local d = Codec.newData()
	if type(raw) ~= "table" then
		return d
	end
	local maxCap = Config.CAPS.penthouse.items
	if type(raw.homes) == "table" then
		local n = 0
		for lid, h in raw.homes do
			if cleanKey(lid, 48) and type(h) == "table" and n < 12 then
				local items, maxU = cleanItems(h.items, maxCap)
				d.homes[lid] = {
					items = items,
					n = math.max(maxU + 1, math.floor(num(h.n, 1, 1e7, 1))),
					fin = Finish.sanitize(h.fin),
				}
				n += 1
			end
		end
	end
	if type(raw.storage) == "table" then
		local total = 0
		for id, n in raw.storage do
			if Catalog.get(id) and type(n) == "number" and n >= 1 then
				local c = math.min(math.floor(n), 99, Config.STORAGE_MAX - total)
				if c > 0 then
					d.storage[id] = c
					total += c
				end
			end
		end
	end
	if type(raw.presets) == "table" then
		for tier, slots in raw.presets do
			if cleanKey(tier, 24) and type(slots) == "table" then
				local out = {}
				for i = 1, Config.PRESET_SLOTS do
					local p = slots[i]
					if type(p) == "table" then
						local items = cleanItems(p.items, maxCap)
						out[i] = {
							n = if type(p.n) == "string" then string.sub(p.n, 1, 48) else ("프리셋 " .. i),
							t = math.floor(num(p.t, 0, 4e9, 0)),
							items = items,
							fin = Finish.sanitize(p.fin),
						}
					end
				end
				d.presets[tier] = out
			end
		end
	end
	d.likes = math.floor(num(raw.likes, 0, 1e9, 0))
	if type(raw.gb) == "table" then
		for _, e in raw.gb do
			if #d.gb >= Config.GUESTBOOK_MAX then
				break
			end
			if type(e) == "table" and type(e.m) == "string" and type(e.n) == "string" then
				table.insert(d.gb, {
					u = math.floor(num(e.u, 0, 1e13, 0)),
					n = string.sub(e.n, 1, 40),
					m = string.sub(e.m, 1, 240),
					t = math.floor(num(e.t, 0, 4e9, 0)),
				})
			end
		end
	end
	for _, key in { "badges", "goals" } do
		local src = raw[key]
		if type(src) == "table" then
			for id, t in src do
				if cleanKey(id, 32) and type(t) == "number" then
					d[key][id] = math.floor(num(t, 0, 4e9, 0))
				end
			end
		end
	end
	if type(raw.stats) == "table" then
		for id, v in raw.stats do
			if cleanKey(id, 24) and type(v) == "number" and v == v then
				d.stats[id] = math.clamp(v, 0, 1e12)
			end
		end
	end
	if type(raw.photo) == "table" then
		d.photo = { d = math.floor(num(raw.photo.d, 0, 1e6, 0)), n = math.floor(num(raw.photo.n, 0, 99, 0)) }
	end
	d.best = math.floor(num(raw.best, 0, 1e7, 0))
	return d
end

-- in-memory data -> DataStore blob (items encoded)
function Codec.serialize(d: any): any
	local homes = {}
	for lid, h in d.homes do
		local items = {}
		for _, rec in h.items do
			table.insert(items, Codec.encode(rec))
		end
		homes[lid] = { items = items, n = h.n, fin = h.fin }
	end
	local presets = {}
	for tier, slots in d.presets do
		local out = {}
		for i = 1, Config.PRESET_SLOTS do
			local p = slots[i]
			if p then
				local items = {}
				for _, rec in p.items do
					table.insert(items, Codec.encode(rec))
				end
				out[i] = { n = p.n, t = p.t, items = items, fin = p.fin }
			end
		end
		presets[tier] = out
	end
	return {
		v = Codec.VERSION,
		homes = homes,
		storage = d.storage,
		presets = presets,
		likes = d.likes,
		gb = d.gb,
		badges = d.badges,
		goals = d.goals,
		stats = d.stats,
		photo = d.photo,
		best = d.best,
	}
end

function Codec.storageCount(d: any): number
	local n = 0
	for _, c in d.storage do
		n += c
	end
	return n
end

return Codec
