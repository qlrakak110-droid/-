--!nocheck
-- offline client + server integration test: the real client modules build their UI in the mock with
-- property validation (class database), then a whole song runs with the TV / band / HUD updating.
local M = require("./mock")
local DT = require("./datatypes")
local V3 = M.Vector3
M.validate = require("./classprops")
local G = DT.globals
for k, v in G do
	if M.env[k] == nil then
		rawset(M.env, k, v)
	end
end
rawset(M.env, "Vector2", G.Vector2)
M.defaults.AbsolutePosition = G.Vector2.new(0, 0)
M.defaults.AbsoluteSize = G.Vector2.new(200, 40)
M.defaults.TimePosition = 0
M.defaults.IsPlaying = false

local fails = 0
local function check(c, msg)
	print((if c then "  ok   " else "  FAIL ") .. msg)
	if not c then
		fails += 1
	end
end

-- client services
local game, ws = M.game, M.workspace
local cam = M.newInst("Camera", "Camera")
cam.ViewportSize = G.Vector2.new(1280, 720)
ws.CurrentCamera = cam
local GuiService = game:GetService("GuiService")
function GuiService:GetGuiInset()
	return G.Vector2.new(0, 58)
end
local UIS = game:GetService("UserInputService")
UIS.TouchEnabled = false
UIS.KeyboardEnabled = true
UIS.InputBegan, UIS.InputChanged, UIS.InputEnded = M.Signal.new(), M.Signal.new(), M.Signal.new()
function UIS:GetLastInputType()
	return M.Enum.UserInputType.Keyboard
end
local TS = game:GetService("TweenService")
function TS:Create(inst, info, props)
	return { Play = function()
		for k, v in props do
			inst[k] = v
		end
	end, Cancel = function() end }
end
local TextService = game:GetService("TextService")
function TextService:GetTextSize(text, size)
	return G.Vector2.new((utf8.len(text) or #text) * size * 0.85, size)
end
local CAS = game:GetService("ContextActionService")
local bound = {}
function CAS:BindAction(name, fn)
	bound[name] = fn
end
function CAS:UnbindAction(name)
	bound[name] = nil
end
local RunService = game:GetService("RunService")
RunService.RenderStepped = M.Signal.new()
RunService.Heartbeat = M.Signal.new()

-- venue + booth (same frames as the place)
local venue = M.newInst("Model", "광안 코인노래연습장")
venue.Parent = ws
local booth = M.newInst("Model", "Booth_01")
booth:SetAttribute("RoomNo", 1)
booth.Parent = venue
M.tag(booth, "KaraokeRoom")
M.part("KaraokeZone", V3.new(32.35, 12.4, 299.01), V3.new(11.6, 11.2, 17.3), math.rad(90)).Parent = booth
M.part("KaraokePanel", V3.new(23.18, 12.1, 298.15), V3.new(1.1, 2, 0.2)).Parent = booth
local scr = M.part("KaraokeScreen", V3.new(40.52, 13.1, 299.01), V3.new(8.84, 5.04, 0.05))
scr:SetAttribute("GuiFace", "Back")
scr.Parent = booth
for _, n in { "KaraokeMachine", "Remote", "SongBook", "Tambourine", "MirrorBall", "LaserProjector", "TableTop" } do
	M.part(n, V3.new(35, 9, 299), V3.new(1, 1, 1)).Parent = booth
end
M.part("WirelessMic", V3.new(32.8, 8.67, 299.51), V3.new(1.2, 0.3, 0.3)).Parent = booth
M.part("WirelessMic", V3.new(33.2, 8.67, 298.21), V3.new(1.2, 0.3, 0.3)).Parent = booth
-- legacy UI the client must remove
local pgA
-- local player
local A = M.addPlayer(101, "민수", V3.new(19.5, 9.9, 298.5))
M.localPlayer = A
game:GetService("Players").LocalPlayer = A
pgA = M.newInst("Folder", "PlayerGui")
pgA.Parent = A
local ps = M.newInst("Folder", "PlayerScripts")
ps.Parent = A
local legacy = M.newInst("Folder", "GwangalliVenues")
legacy.Parent = pgA
M.newInst("Frame", "KaraokeBar").Parent = legacy

-- server
local RS = game:GetService("ReplicatedStorage")
local shared = M.scriptObj("sh/init.luau", "sh/")
shared.Name = "GwangalliKaraokeShared"
shared.Parent = RS
local server = M.scriptObj("srv/init.server.luau", "srv/")
server.Name = "GwangalliKaraokePlus"
server.Parent = game:GetService("ServerScriptService")
M.task.spawn(function()
	M.load("srv/init.server.luau", server)
end)
-- client
local client = M.scriptObj("cli/init.client.luau", "cli/")
client.Name = "GwangalliKaraokePlus"
client.Parent = ps
client:SetAttribute("Debug", true)
M.task.spawn(function()
	M.load("cli/init.client.luau", client)
end)
local function frames(seconds)
	local n = math.floor(seconds / 0.05)
	for _ = 1, n do
		M.advance(0.05, 0.05)
		RunService.RenderStepped:Fire(0.05)
	end
end
frames(14)
check(shared:GetAttribute("Active") == true, "server active")
local gui = pgA:FindFirstChild("GwangalliKaraokePlus")
check(gui ~= nil, "client ScreenGui built")
check(pgA:FindFirstChild("GwKP_TV") ~= nil, "TV SurfaceGui in PlayerGui")
check(legacy:FindFirstChild("KaraokeBar") == nil, "legacy KaraokeBar removed")

local function dbg(cmd)
	client:SetAttribute("KPDebugOut", "")
	client:SetAttribute("KPDebug", "")
	client:SetAttribute("KPDebug", cmd)
	for _ = 1, 60 do
		frames(0.1)
		local o = client:GetAttribute("KPDebugOut")
		if o and o ~= "" then
			return o
		end
	end
	return "timeout"
end
print(dbg("state"))
check(dbg("req buy {\"room\":1,\"pack\":\"p4\",\"rid\":\"a\"}"):find('"ok":true') ~= nil, "buy through the client")
M.move(A, V3.new(31.5, 9.9, 300.5))
frames(1.5)
local st = dbg("state")
print(st)
check(st:find("room=1 state=open") ~= nil, "client sees room 1 open")
check(st:find("layers=ready") ~= nil, "TV shows ready")
for _, u in { "ui book", "ui remote", "ui pay", "ui close" } do
	local o = dbg(u)
	check(o == "ok", u .. " -> " .. o)
	frames(0.3)
end
check(dbg("req reserve {\"room\":1,\"song\":\"s33\"}"):find('"ok":true') ~= nil, "reserve duet s33")
check(dbg("req set {\"room\":1,\"key\":-2,\"echo\":5}"):find('"ok":true') ~= nil, "set key/echo")
frames(2.5)
st = dbg("state")
print(st)
check(st:find("state=play") ~= nil and st:find("layers=title") ~= nil, "title card")
print(dbg("autotap"))
local sawLyrics, sawInter = false, false
local plays0 = M.plays or 0
for _ = 1, 140 do
	frames(1)
	local s2 = dbg("state")
	if s2:find("lyrics=1:") then
		sawLyrics = true
	end
	if s2:find("inter=true") then
		sawInter = true
	end
	if s2:find("state=score") then
		print(s2)
		break
	end
end
check(sawLyrics, "lyrics with wipe seen")
check(sawInter, "간주중 seen")
check((M.plays or 0) - plays0 > 200, "band played notes (" .. tostring((M.plays or 0) - plays0) .. ")")
st = dbg("state")
check(st:find("state=score") ~= nil, "score screen")
print(st)
frames(9)
-- effects, mic, leave
check(dbg("req cheer {\"room\":1,\"kind\":\"petal\"}"):find('"ok":true') ~= nil, "petal fx")
check(dbg("req mic {\"room\":1,\"action\":\"put\"}"):find('"ok":true') ~= nil, "put mic")
check(dbg("req leave {\"room\":1}"):find('"ok":true') ~= nil, "leave")
frames(2)
print(dbg("state"))
print(string.format("\n%d failures", fails))
