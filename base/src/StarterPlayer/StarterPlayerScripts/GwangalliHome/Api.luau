-- GwangalliHome/Api: the client API of 내집마련 for other client scripts (the phone 홈 / 부동산 apps).
--   local Home = require(<PlayerScripts>.GwangalliHome.Api)   -- the Folder next to the LocalScript
--   Home.openInterior()        -- 인테리어 mode in my home (goes home first when outside)
--   Home.tour(listingId)       -- 매물 둘러보기: an empty staged unit of a listing (back on 나가기)
--   Home.state() -> { inside, role = "owner" | "guest" | "viewer" | nil, interior = mode | nil, homeName }
--   Home.isOpen() -> bool      -- the 인테리어 / 집 구경 mode is up
-- It talks to the GwangalliHome LocalScript through LocalPlayer.GwangalliHomeOpen (BindableEvent:
-- :Fire("interior") | :Fire("tour", listingId) | :Fire("close")) and LocalPlayer.GwangalliHomeQuery
-- (BindableFunction: :Invoke("state")), so scripts that cannot require this module can use those.

local Players = game:GetService("Players")

local Home = {}

local function player(): Player
	return Players.LocalPlayer
end

local function event(): BindableEvent?
	local e = player():FindFirstChild("GwangalliHomeOpen") or player():WaitForChild("GwangalliHomeOpen", 5)
	return if e and e:IsA("BindableEvent") then e else nil
end

local function query(): BindableFunction?
	local f = player():FindFirstChild("GwangalliHomeQuery")
	return if f and f:IsA("BindableFunction") then f else nil
end

function Home.openInterior(): boolean
	local e = event()
	if e then
		e:Fire("interior")
		return true
	end
	return false
end

function Home.tour(listingId: string): boolean
	local e = event()
	if e and type(listingId) == "string" then
		e:Fire("tour", listingId)
		return true
	end
	return false
end

function Home.close(): boolean
	local e = event()
	if e then
		e:Fire("close")
		return true
	end
	return false
end

function Home.state(): any
	local f = query()
	if not f then
		return { inside = false }
	end
	local ok, res = pcall(f.Invoke, f, "state")
	return if ok and type(res) == "table" then res else { inside = false }
end

function Home.isOpen(): boolean
	return Home.state().interior ~= nil
end

return Home
