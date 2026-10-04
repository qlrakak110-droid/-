-- GwangalliClubShow (client bootstrap): the CLUB OCEAN 광안 show layer on this player's screen
-- (docs/CLUB_SHOW.md). Modules in the sibling folder GwangalliClubShow (found by class):
--   Core     shared context, the single tween driver, pooled rigs, helpers
--   Door     closed door: local barrier, sliding leaves, head bouncer, rope
--   Ui       fallback screens (entry sheet, bottle menu, receipts, 합석 action card) - GwangalliUI kit
--   Show     bottle-service show choreography + room effects + table life props
--   Booking  합석 이벤트 choreography
-- Inputs: ClubRemote ("door", payload) from Club.server; ReplicatedStorage.GwangalliClubShow:
-- ShowEvent (menu / order / booking / toast) and the JSON attributes Show / Tables / Booking.
-- Debug: LocalPlayer.GwangalliClubShowQuery (BindableFunction) :Invoke("state") -> summary table.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local function findFolder(): Instance?
	for _ = 1, 100 do
		local parent = script.Parent
		if parent then
			for _, child in parent:GetChildren() do
				if child.Name == "GwangalliClubShow" and child:IsA("Folder") then
					return child
				end
			end
		end
		task.wait(0.1)
	end
	return nil
end

local folder = findFolder()
if not folder then
	warn("[GwangalliClubShow] module folder missing next to the LocalScript")
	return
end

local function mod(name: string): any
	local m = (folder :: Instance):FindFirstChild(name)
	if not m or not m:IsA("ModuleScript") then
		warn("[GwangalliClubShow] module missing:", name)
		return nil
	end
	local ok, res = pcall(require, m)
	if not ok or type(res) ~= "table" then
		warn("[GwangalliClubShow] module failed:", name, res)
		return nil
	end
	return res
end

local Core = mod("Core")
if not Core or not Core.init() then
	return
end
local Ui = mod("Ui")
local Door = mod("Door")
local Show = mod("Show")
local Booking = mod("Booking")
if not Ui or not Door or not Show or not Booking then
	return
end
Ui.init(Core)
Door.init(Core)
Show.init(Core)
Booking.init(Core, Show, Ui)
local S = Core.S

-- Club.server's door answers (ClubRemote "door")
task.spawn(function()
	local names = Core.Club.Names or {}
	local remote = ReplicatedStorage:WaitForChild(names.Remote or "ClubRemote", 120)
	if not remote or not remote:IsA("RemoteEvent") then
		return
	end
	(remote :: RemoteEvent).OnClientEvent:Connect(function(kind: any, payload: any)
		if kind ~= "door" or type(payload) ~= "table" then
			return
		end
		local ok, err = pcall(function()
			Ui.doorResult(payload)
			local st = payload.state
			if st == "paid" or st == "granted" or st == "valid" then
				Door.welcome()
			elseif st == "eject" then
				task.delay(0.3, function()
					local root = Core.rootPart()
					Door.stop(if root then root.Position else nil)
				end)
			elseif st == "quote" then
				Door.nod()
			end
		end)
		if not ok then
			warn("[GwangalliClubShow] door event:", err)
		end
	end)
end)

-- the show layer's remotes + state attributes
task.spawn(function()
	local f = ReplicatedStorage:WaitForChild(S.Folder, 120)
	if not f then
		return
	end
	local ev = f:WaitForChild(S.Remote.Event, 30)
	if ev and ev:IsA("RemoteEvent") then
		ev.OnClientEvent:Connect(function(kind: any, payload: any)
			if type(payload) ~= "table" then
				return
			end
			local ok, err = pcall(function()
				if kind == "menu" then
					Ui.menu(payload)
				elseif kind == "order" then
					Ui.order(payload)
				elseif kind == "booking" then
					Ui.booking(payload)
				elseif kind == "toast" then
					Core.toast(payload.title or "", payload.body, payload.icon, payload.kind)
				end
			end)
			if not ok then
				warn("[GwangalliClubShow] event", kind, err)
			end
		end)
	end
	local function read(attr: string, fn: (any) -> ())
		local function apply()
			local v = Core.decode(f:GetAttribute(attr))
			if v then
				local ok, err = pcall(fn, v)
				if not ok then
					warn("[GwangalliClubShow]", attr, err)
				end
			end
		end
		f:GetAttributeChangedSignal(attr):Connect(apply)
		apply()
	end
	read(S.Attr.Tables, Show.onTables)
	read(S.Attr.Show, Show.onShow)
	read(S.Attr.Booking, Booking.onBooking)
end)

-- debug / test query
do
	local q = Instance.new("BindableFunction")
	q.Name = "GwangalliClubShowQuery"
	q.OnInvoke = function(what: any): any
		if what == "state" then
			local a = Show.current()
			local b = Booking.current()
			local staff, guests = 0, 0
			if a then
				for _, st in a.staff do
					if st.rec then
						staff += 1
					end
				end
			end
			if b then
				for _, w in b.walkers do
					if w.rec then
						guests += 1
					end
				end
			end
			return { door = Door.state(), show = a ~= nil, staffRigs = staff, booking = b ~= nil, bookingRigs = guests, inside = Core.inside(), tier = Core.tier() }
		end
		return nil
	end
	q.Parent = player
end
