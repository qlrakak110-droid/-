-- GwangalliStreetLife/ClubCrowd: how many of CLUB OCEAN's built crowd rigs (ClubNPC models) are
-- there, following the night and the camera:
--   * AT THE CLUB (the camera inside a club interior zone: the build's rule-12 LOD zones LODCenter /
--     LODRadius on the club's interior models, else the bounds of the interior rigs + 40 studs, with
--     hysteresis): 10 + 30 * hype guests are visible (GwangalliNight.crowdVisible), the ones nearest a
--     DJ first; the outside queue / drop-off guests (Zone "Near") only from the evening on (hype >=
--     0.15) and they count toward the total (never fewer than 10 inside).
--   * AWAY (the club is only a shell from outside): every interior guest and the interior staff
--     (bartenders, DJs, guards, staff; never the bottle-service parade staff ClubLights walks) are
--     hidden; only the outside guests follow the hype rule. A rig that streams in while hidden rigs
--     are wanted is hidden at once (no 2 s flash of the whole crowd).
-- NAMED GUESTS: while the player is in / at the main room, up to SubMax (low 3 / mid 5 / high 6,
-- saver 1) of the citizens the roster puts inside the club (GwangalliCitizens.clubCrowd: the people
-- met on the street earlier) dance in the place of visible dance-floor rigs: the club rig is hidden
-- and the citizen's own GwangalliNPCLooks rig (club outfit) dances there as a street-life agent, so
-- the name chip, 말 걸기 and the club choices of the conversation (같이 춤추자 / 한잔 살게) work as on
-- the street. People the player already knows are picked first; the rest rotate every few minutes.
-- Swaps happen only where the camera does not look (one per pass), never in front of the player.
-- Hooks only through tags / attributes (ClubLights / ClubDance are not edited):
--   hide: RemoveTag("ClubNPC") first (ClubLights drops the rig: no animation slot, no crowd reactions),
--         then LocalTransparencyModifier = 1 on its parts / decals and SurfaceGuis / BillboardGuis off;
--   show: everything back, then AddTag("ClubNPC") (ClubLights registers it again from its attributes).
-- Local attribute StreetLifeHidden = true marks a hidden rig for other client scripts.
-- Streaming-safe: a rig that streams in again arrives as a fresh tagged copy and is re-applied; a
-- tracked rig that left the Workspace for a minute gets its tag / transparency back and is forgotten.
-- Cost: one decision pass every 2 s (0.5 s near the club); hide / show writes spread over frames
-- (PartsPerFrame).

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local ClubCrowd = {}

local TAG = "ClubNPC"
local PARTS_PER_FRAME = 90

local ctx: any
local Night: any
type Rec = { model: Model, role: string, zone: string, anim: string, pos: Vector3?, yaw: number, hidden: boolean, want: boolean?, outSince: number?, rank: number, guis: { GuiBase }?, sub: string?, parade: boolean? }
local recs: { [Model]: Rec } = {}
local jobs: { { rec: Rec, hide: boolean } } = {}
local queued: { [Rec]: boolean } = {}
local order: { Rec } = {}
local orderDirty = true
local djPos: { Vector3 } = {}
local applying: { [Model]: boolean } = {} -- our own tag changes (ignore the signals)
local subs: { [string]: { rec: Rec, agent: any, since: number } } = {} -- citizen id -> named guest
local mainCentre: Vector3? = nil
local clubZones: { { c: Vector3, r: number } } = {}
local zonesAt = -1e9
local atClubNow = false
local decideSoon = false
local SUB_MAX = { low = 3, mid = 5, high = 6, saver = 1 }
local SUB_ANIMS = { dance = true, dance2 = true, cheer = true, idle = true }
local SUB_ROTATE = 150 -- s before a stranger's spot may go to someone else
local OUTSIDE_HYPE = 0.15

ClubCrowd.stats = { guests = 0, visible = 0, target = 0, hidden = 0, named = 0, atClub = false, staffHidden = 0 }
-- also hide the interior staff while the camera is away from the club
ClubCrowd.hideStaff = true

local function rootPos(m: Model): Vector3?
	local r = m:FindFirstChild("HumanoidRootPart")
	if r and r:IsA("BasePart") then
		return r.Position
	end
	local ok, cf = pcall(m.GetPivot, m)
	return if ok then cf.Position else nil
end

local started = false
local frameNo = 0
local immFrame, immCount = -1, 0
local IMMEDIATE_PER_FRAME = 12

local function isOutside(rec: Rec): boolean
	return rec.zone == "Near" or rec.zone == "Outside" or rec.zone == "Forecourt"
end

local applyRec: (Rec, boolean) -> ()

local function add(inst: Instance)
	if not inst:IsA("Model") then
		return
	end
	local m = inst :: Model
	if applying[m] then
		return
	end
	local rec = recs[m]
	if rec then
		-- our own AddTag (show) or a re-tag: nothing to do
		return
	end
	local role = m:GetAttribute("Role")
	local zone = m:GetAttribute("Zone")
	local anim = m:GetAttribute("Anim")
	local yaw = 0
	local r = m:FindFirstChild("HumanoidRootPart")
	if r and r:IsA("BasePart") then
		local lv = r.CFrame.LookVector
		yaw = math.atan2(-lv.X, -lv.Z)
	end
	rec = {
		model = m,
		role = if type(role) == "string" then string.lower(role) else "guest",
		zone = if type(zone) == "string" then zone else "Main",
		anim = if type(anim) == "string" then anim else "idle",
		pos = rootPos(m),
		yaw = yaw,
		hidden = false,
		rank = math.huge,
		parade = m:GetAttribute("Parade") == true or type(m:GetAttribute("ParadeSlot")) == "number" or type(m:GetAttribute("ParadeCount")) == "number",
	}
	recs[m] = rec
	orderDirty = true
	decideSoon = true
	-- away from the club every interior rig is hidden: a (re)streamed copy is hidden right now (up to
	-- IMMEDIATE_PER_FRAME rigs a frame when a whole club streams in; the rest go first in the queue)
	if not atClubNow and not isOutside(rec) and not rec.parade and (rec.role == "guest" or ClubCrowd.hideStaff) then
		if frameNo ~= immFrame then
			immFrame, immCount = frameNo, 0
		end
		if started and immCount < IMMEDIATE_PER_FRAME then
			immCount += 1
			applyRec(rec, true)
		else
			rec.want = true
			if not queued[rec] then
				queued[rec] = true
				table.insert(jobs, 1, { rec = rec, hide = true })
			end
		end
	end
end

local function setVisual(rec: Rec, hide: boolean)
	local m = rec.model
	local v = if hide then 1 else 0
	if hide then
		rec.guis = {}
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			(d :: any).LocalTransparencyModifier = v
		elseif d:IsA("SurfaceGui") or d:IsA("BillboardGui") then
			if hide then
				if d.Enabled then
					table.insert(rec.guis :: any, d)
					d.Enabled = false
				end
			end
		end
	end
	if not hide and rec.guis then
		for _, g in rec.guis do
			if g.Parent then
				(g :: any).Enabled = true
			end
		end
		rec.guis = nil
	end
end

function applyRec(rec: Rec, hide: boolean)
	local m = rec.model
	if hide == rec.hidden then
		return
	end
	applying[m] = true
	if hide then
		pcall(function()
			m:RemoveTag(TAG)
		end)
		setVisual(rec, true)
		m:SetAttribute("StreetLifeHidden", true)
	else
		setVisual(rec, false)
		m:SetAttribute("StreetLifeHidden", nil)
		pcall(function()
			m:AddTag(TAG)
		end)
	end
	applying[m] = nil
	rec.hidden = hide
end

local function enqueue(rec: Rec, hide: boolean)
	rec.want = hide
	if not queued[rec] then
		queued[rec] = true
		table.insert(jobs, { rec = rec, hide = hide })
	end
end

-- the club's interior zones (rule-12 LOD zones of the build), else the interior rigs' bounds
local function rebuildZones()
	zonesAt = os.clock()
	table.clear(clubZones)
	local container: Instance? = nil
	for _, rec in recs do
		local m = rec.model
		if m.Parent then
			local p = m.Parent
			-- rigs live in <club model>/People (or directly in the club model)
			if p and p.Name == "People" and p.Parent then
				container = p.Parent
			else
				container = p
			end
			break
		end
	end
	if container then
		for _, c in container:GetChildren() do
			if c:GetAttribute("LOD") == "zone" then
				local r = c:GetAttribute("LODRadius")
				local cc = c:GetAttribute("LODCenter")
				if type(r) == "number" and typeof(cc) == "Vector3" then
					table.insert(clubZones, { c = cc, r = r })
				end
			end
		end
	end
	if #clubZones == 0 then
		local x0, y0, z0, x1, y1, z1 = math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge
		local n = 0
		for _, rec in recs do
			local p = rec.pos
			if p and not isOutside(rec) then
				n += 1
				x0, y0, z0 = math.min(x0, p.X), math.min(y0, p.Y), math.min(z0, p.Z)
				x1, y1, z1 = math.max(x1, p.X), math.max(y1, p.Y), math.max(z1, p.Z)
			end
		end
		if n > 0 then
			local c = Vector3.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
			local r = 0.5 * math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2 + (z1 - z0) ^ 2) + 40
			table.insert(clubZones, { c = c, r = r })
		end
	end
end

-- the camera is at the club (inside an interior zone, with hysteresis)
local function computeAtClub(): (boolean, number)
	local cam = workspace.CurrentCamera
	local cp = if cam then cam.CFrame.Position else (ctx.Crowd and ctx.Crowd.playerPos())
	if not cp then
		return atClubNow, math.huge
	end
	local margin = if atClubNow then 45 else 20
	local best = math.huge
	for _, z in clubZones do
		local d = (cp - z.c).Magnitude - z.r
		if d < best then
			best = d
		end
	end
	return best < margin, best
end

local function rebuildOrder()
	orderDirty = false
	table.clear(order)
	table.clear(djPos)
	for _, rec in recs do
		if rec.role == "dj" and rec.pos then
			table.insert(djPos, rec.pos)
		end
	end
	rebuildZones()
	local sx, sz, sy, sn = 0, 0, 0, 0
	for _, rec in recs do
		if rec.role == "guest" and rec.zone == "Main" and rec.pos then
			sx += rec.pos.X
			sy += rec.pos.Y
			sz += rec.pos.Z
			sn += 1
		end
	end
	mainCentre = if sn > 0 then Vector3.new(sx / sn, sy / sn, sz / sn) else nil
	for _, rec in recs do
		if rec.role == "guest" then
			local best = math.huge
			if rec.pos then
				for _, d in djPos do
					local dist = (rec.pos - d).Magnitude
					if dist < best then
						best = dist
					end
				end
				if best == math.huge then
					best = rec.pos.X * 0.001 -- no DJ known yet: stable order
				end
			end
			rec.rank = best
			table.insert(order, rec)
		end
	end
	table.sort(order, function(a, b)
		if a.rank ~= b.rank then
			return a.rank < b.rank
		end
		return a.model.Name < b.model.Name
	end)
end

local function releaseSub(id: string)
	local sub = subs[id]
	subs[id] = nil
	if not sub then
		return
	end
	if sub.rec.sub == id then
		sub.rec.sub = nil
	end
	local a = sub.agent
	if a and not a.gone and ctx.Crowd then
		if a.companion then
			a.clubGuest = nil -- became the player's companion: Crowd owns it now
		else
			ctx.Crowd.remove(a)
		end
	end
end

local function tierVal(t: any): any
	if ctx.Crowd and ctx.Crowd.tierVal then
		return ctx.Crowd.tierVal(t)
	end
	local q = ctx.Quality
	local tier = if q then q.get() else "low"
	return t[tier] or t.low
end

local function offScreen(p: Vector3): boolean
	local C = ctx.Crowd
	return not (C and C.onScreenPoint and C.onScreenPoint(p))
end

-- a club rig may be swapped for a named guest here without anyone noticing: out of view, far
-- across the dark room, or right after the room was shown (walking in / arriving)
local arrivedAt = -1e9
local function canSwapAt(p: Vector3): boolean
	if os.clock() - arrivedAt < 2 then
		return true
	end
	local cam = workspace.CurrentCamera
	if cam and (cam.CFrame.Position - p).Magnitude > 42 then
		return true
	end
	return offScreen(p)
end

-- the player stands in (or at the door of) the main room
local function playerAtClub(): boolean
	local pp = ctx.Crowd and ctx.Crowd.playerPos()
	if not pp or not mainCentre then
		return false
	end
	local c = mainCentre :: Vector3
	local dx, dz = pp.X - c.X, pp.Z - c.Z
	return dx * dx + dz * dz < 95 * 95 and math.abs(pp.Y - c.Y) < 30
end

local function hashOf(s: string): number
	local h = 0
	for i = 1, #s do
		h = (h * 31 + string.byte(s, i)) % 1000003
	end
	return h
end

local DANCES = { "dance", "dance2", "dance3" }

-- named citizens in the place of visible dance-floor rigs (inner = rigs shown inside)
local function updateSubs(clock: number, hype: number, inner: number)
	local C = ctx.Citizens
	if not C or not ctx.Crowd or hype < OUTSIDE_HYPE or not atClubNow then
		for id in subs do
			releaseSub(id)
		end
		return
	end
	if not playerAtClub() then
		-- walking out: let them go where the camera does not look (the room hides soon anyway)
		for id, sub in subs do
			local a = sub.agent
			if not a or a.gone or offScreen(a.pos) then
				releaseSub(id)
			end
		end
		return
	end
	local ok, list = pcall(C.clubCrowd, clock)
	if not ok or type(list) ~= "table" then
		list = {}
	end
	local inside: { [string]: boolean } = {}
	for _, id in list do
		inside[id] = true
	end
	-- the first `inner` inside rigs of the order are shown
	local shown: { [Rec]: boolean } = {}
	local k = 0
	for _, rec in order do
		if not isOutside(rec) and rec.model:IsDescendantOf(workspace) then
			k += 1
			if k <= inner then
				shown[rec] = true
			end
		end
	end
	local now = os.clock()
	local SocialUI = ctx.SocialUI
	local function known(id: string): boolean
		return SocialUI ~= nil and (SocialUI.tier(id) >= 2 or SocialUI.met(id))
	end
	for id, sub in subs do
		local a = sub.agent
		local expired = not known(id) and now - sub.since > SUB_ROTATE and not (a and a.mode == "talk")
		if not a or a.gone or a.companion then
			releaseSub(id)
		elseif (not inside[id] or not shown[sub.rec] or expired) and canSwapAt(a.pos) then
			releaseSub(id) -- swapped back only where the camera does not look
		end
	end
	local max = tierVal(SUB_MAX)
	local count = 0
	for _ in subs do
		count += 1
	end
	if count >= max then
		return
	end
	-- who: people the player knows first, then a stable rotation of the others
	local cands = {}
	local slot = math.floor(now / SUB_ROTATE)
	for _, id in list do
		if not subs[id] and not ctx.Crowd.byId[id] then
			table.insert(cands, { id = id, w = (if known(id) then 0 else 1e7) + (hashOf(id) + slot * 7919) % 1000003 })
		end
	end
	table.sort(cands, function(x, y)
		return x.w < y.w
	end)
	-- where: shown standing dance-floor rigs, every other one from the DJ outward (spread out)
	local spots = {}
	local j = 0
	for _, rec in order do
		if shown[rec] and not rec.sub and rec.zone == "Main" and SUB_ANIMS[rec.anim] and rec.pos then
			j += 1
			if j % 2 == 1 and canSwapAt(rec.pos) then
				table.insert(spots, rec)
			end
		end
	end
	local si = 1
	for _, cand in cands do
		if count >= max then
			break
		end
		local rec = spots[si]
		if not rec then
			break
		end
		si += 1
		local p = rec.pos :: Vector3
		local dance = if rec.anim == "dance2" then "dance2" elseif rec.anim == "dance" then "dance" else DANCES[1 + hashOf(cand.id) % 3]
		-- R6 club rigs: the HumanoidRootPart centre is 3 studs above the feet
		local okA, a = pcall(ctx.Crowd.spawnClubGuest, cand.id, Vector3.new(p.X, p.Y - 3, p.Z), rec.yaw, dance)
		if okA and a then
			rec.sub = cand.id
			subs[cand.id] = { rec = rec, agent = a, since = now }
			count += 1
			break -- one new guest per pass (the rig build / restyle stays out of a single frame)
		end
	end
end
ClubCrowd.release = function()
	for id in subs do
		releaseSub(id)
	end
end

local function decide()
	local now = os.clock()
	-- rigs that left the Workspace (streamed out / removed)
	for m, rec in recs do
		if not m:IsDescendantOf(workspace) then
			rec.outSince = rec.outSince or now
			if now - rec.outSince > 60 then
				if rec.hidden then
					applyRec(rec, false) -- give the stale copy its tag back before forgetting it
				end
				recs[m] = nil
				queued[rec] = nil
				orderDirty = true
			end
		else
			rec.outSince = nil
		end
	end
	if orderDirty then
		rebuildOrder()
	end
	if now - zonesAt > 10 then
		rebuildZones()
	end
	local atClub, gap = computeAtClub()
	if atClub and not atClubNow then
		arrivedAt = now
	end
	atClubNow = atClub
	ClubCrowd.nearGap = gap
	local clock = ctx.clock()
	local hype = Night.hype(clock)
	local target = Night.crowdVisible(hype)
	local outsideOn = hype >= OUTSIDE_HYPE
	-- the outside guests count toward the total, but the room never drops below 10
	local outsideN = 0
	if outsideOn then
		for _, rec in order do
			if isOutside(rec) and rec.model:IsDescendantOf(workspace) then
				outsideN += 1
			end
		end
	end
	local inner = if atClub then math.max(10, target - outsideN) else 0
	updateSubs(clock, hype, inner)
	local k = 0
	local vis, hid, guests = 0, 0, 0
	for _, rec in order do
		if rec.model:IsDescendantOf(workspace) then
			guests += 1
			local hide
			if isOutside(rec) then
				hide = not outsideOn
			else
				k += 1
				hide = k > inner
			end
			if hide then
				hid += 1
			else
				vis += 1
			end
			-- a named guest dances in this rig's place: the rig itself stays hidden
			local look = hide or rec.sub ~= nil
			if look ~= rec.hidden or (rec.want ~= nil and rec.want ~= look) then
				enqueue(rec, look)
			end
		end
	end
	-- interior staff: hidden with the room while the camera is away (parade staff are ClubLights')
	local staffHidden = 0
	if ClubCrowd.hideStaff then
		for _, rec in recs do
			if rec.role ~= "guest" and not rec.parade and not isOutside(rec) and rec.model:IsDescendantOf(workspace) then
				local hide = not atClub
				if hide then
					staffHidden += 1
				end
				if hide ~= rec.hidden or (rec.want ~= nil and rec.want ~= hide) then
					enqueue(rec, hide)
				end
			end
		end
	end
	local st = ClubCrowd.stats
	local named = 0
	for _ in subs do
		named += 1
	end
	st.guests, st.visible, st.hidden, st.target, st.named, st.atClub, st.staffHidden = guests, vis, hid, target, named, atClub, staffHidden
end

local function step()
	local budget = PARTS_PER_FRAME
	while budget > 0 and #jobs > 0 do
		local job = table.remove(jobs, 1)
		local rec = job.rec
		queued[rec] = nil
		if rec.model:IsDescendantOf(workspace) and recs[rec.model] == rec then
			local hide = if rec.want ~= nil then rec.want else job.hide
			rec.want = nil
			if hide ~= rec.hidden then
				applyRec(rec, hide)
				budget -= 32
			end
		end
	end
end

function ClubCrowd.start(context: any)
	ctx = context
	Night = ctx.Night
	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(inst)
		local ok, err = pcall(add, inst)
		if not ok then
			warn("[GwangalliStreetLife] ClubCrowd add: " .. tostring(err))
		end
	end)
	for _, inst in CollectionService:GetTagged(TAG) do
		add(inst)
	end
	started = true
	RunService.Heartbeat:Connect(function()
		frameNo += 1
		if #jobs > 0 then
			local ok, err = pcall(step)
			if not ok then
				warn("[GwangalliStreetLife] ClubCrowd step: " .. tostring(err))
				table.clear(jobs)
				table.clear(queued)
			end
		end
	end)
	task.spawn(function()
		local nextDecide = 0
		while true do
			local now = os.clock()
			-- the camera crossed the club's zone edge (walked in / quick travel): decide now
			if not decideSoon and now < nextDecide and #clubZones > 0 then
				local at = computeAtClub()
				if at ~= atClubNow then
					decideSoon = true
				end
			end
			if now >= nextDecide or decideSoon then
				decideSoon = false
				local ok, err = pcall(decide)
				if not ok then
					warn("[GwangalliStreetLife] ClubCrowd: " .. tostring(err))
				end
				-- near the club (walking in / out) decide often, so the room is never seen empty
				local gap = ClubCrowd.nearGap or math.huge
				nextDecide = os.clock() + (if gap < 90 then 0.5 else 2)
			end
			task.wait(0.25)
		end
	end)
end

return ClubCrowd
