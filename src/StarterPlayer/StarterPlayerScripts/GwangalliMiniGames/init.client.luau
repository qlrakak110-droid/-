--!strict
-- GwangalliMiniGames (LocalScript, StarterPlayerScripts): the player's side of the 광안리 해변 미니게임
-- 거리 (server: ServerScriptService.GwangalliGameplay.MiniGames, contract: ReplicatedStorage.
-- GwangalliMiniGamesShared).
--   Hud             station buttons while walking, stake / friend pickers, challenge popups, records
--   Stage           the match screen (VS bar, timer, countdown, result, rematch / forfeit)
--   CameraDirector  camera onto the table and back, movement lock while playing
--   Fx              sounds, hand emotes, speech bubbles
--   <Game>/<Game>Client  one module per game: mount(ctx) -> { update, game, event, destroy }
--   Omok/OmokBoards draws the stones of EVERY omok table near you (passers-by watch real games)
-- Nothing here decides money or results; the server sends views and this script draws them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local function need(name: string): any
	local m = ReplicatedStorage:WaitForChild(name, 60)
	if not m or not m:IsA("ModuleScript") then
		warn("[MiniGames] ReplicatedStorage." .. name .. " missing; minigames disabled on this client")
		return nil
	end
	return require(m) :: any
end

local MS = need("GwangalliMiniGamesShared")
local K = need("GwangalliUI")
if not MS or not K then
	return
end

local Net = require(script:WaitForChild("Net")) :: any
local Fx = require(script:WaitForChild("Fx")) :: any
local Cam = require(script:WaitForChild("CameraDirector")) :: any
local Hud = require(script:WaitForChild("Hud")) :: any
local Stage = require(script:WaitForChild("Stage")) :: any

local CLIENTS = {
	omok = { "Omok", "OmokClient" },
	wordchain = { "WordChain", "WordChainClient" },
	rps = { "RockPaperScissors", "RpsClient" },
	reaction = { "ReactionGame", "ReactionClient" },
	memory = { "MemoryGame", "MemoryClient" },
	numberguess = { "NumberGuess", "NumberGuessClient" },
	timing = { "TimingGame", "TimingClient" },
	quiz = { "Quiz", "QuizClient" },
}
local clients: { [string]: any } = {}
for id, path in CLIENTS do
	local ok, res = pcall(function()
		return require(script:WaitForChild(path[1]):WaitForChild(path[2]))
	end)
	if ok then
		clients[id] = res
	else
		warn("[MiniGames] client " .. id .. " failed: " .. tostring(res))
	end
end

if not Net.init(MS) then
	warn("[MiniGames] remotes missing (is the MiniGames feature module enabled on the server?)")
	return
end

local gui = Instance.new("ScreenGui")
gui.Name = "GwangalliMiniGames"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 8
pcall(function()
	(gui :: any).ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
end)
gui.Parent = player:WaitForChild("PlayerGui")

Fx.init()
Stage.init(K, MS, Net, Fx, gui)
Hud.init(K, MS, Net, gui)

local boards = script:WaitForChild("Omok"):FindFirstChild("OmokBoards")
if boards then
	local ok, res = pcall(require, boards)
	if ok then
		res.start(MS, Fx)
	else
		warn("[MiniGames] OmokBoards: " .. tostring(res))
	end
end

-------------------------------------------------------------------------------------------------
-- the current match
-------------------------------------------------------------------------------------------------
local current: any = nil -- { id, view, ctrl, station }

local function stationModel(id: string): Model?
	local f = Workspace:FindFirstChild(MS.FolderName)
	local m = f and f:FindFirstChild(id)
	return if m and m:IsA("Model") then m else nil
end

local function closeCurrent()
	if not current then
		return
	end
	local c = current
	current = nil
	if c.ctrl and c.ctrl.destroy then
		pcall(c.ctrl.destroy)
	end
	Stage.hide()
	Cam.release()
	Hud.setInMatch(false)
end

local function onMatch(view: any)
	if type(view) ~= "table" then
		return
	end
	if current and current.id ~= view.id then
		local keep = current.station == view.station and view.you > 0
		if current.ctrl and current.ctrl.destroy then
			pcall(current.ctrl.destroy)
		end
		current = nil
		Stage.hide()
		if not keep then
			Cam.release()
		end
	end
	local model = stationModel(view.station)
	if not current then
		local client = clients[view.game]
		current = { id = view.id, view = view, station = view.station, model = model, ctrl = nil }
		Hud.setInMatch(true)
		Stage.show(view)
		if client then
			local ok, ctrl = pcall(client.mount, {
				K = K,
				MS = MS,
				Net = Net,
				Fx = Fx,
				Stage = Stage,
				Cam = Cam,
				panel = Stage.panel,
				gui = gui,
				view = view,
				model = model,
				you = view.you,
				matchId = view.id,
			})
			if ok then
				current.ctrl = ctrl
			else
				warn("[MiniGames] mount " .. view.game .. ": " .. tostring(ctrl))
			end
		end
		local hint = if view.you == 1 then "CamA" elseif view.you == 2 then "CamB" else "CamSpec"
		Cam.focus(model, hint)
		if view.you > 0 then
			Cam.lockControls(true)
		end
	end
	current.view = view
	Stage.show(view)
	if current.ctrl and current.ctrl.update then
		pcall(current.ctrl.update, view)
	end
	if view.g and current.ctrl and current.ctrl.game then
		pcall(current.ctrl.game, view.g)
	end
end

Net.on(MS.Kinds.match, onMatch)
Net.on(MS.Kinds.game, function(p: any)
	if current and p and p.id == current.id and current.ctrl and current.ctrl.game then
		pcall(current.ctrl.game, p.g)
	end
end)
Net.on(MS.Kinds.event, function(p: any)
	if type(p) ~= "table" then
		return
	end
	-- world-level: a hand emote on a player character (participants and passers-by see it)
	if p.e == "emote" and type(p.userId) == "number" then
		Fx.emote(Fx.characterOf(p.userId), p.name)
	end
	if current and p.id == current.id and current.ctrl and current.ctrl.event then
		pcall(current.ctrl.event, p)
	end
end)
Net.on(MS.Kinds.closed, function(p: any)
	if not current then
		return
	end
	if p and p.id ~= 0 and p.id ~= current.id then
		return
	end
	if p and p.id == 0 then
		return -- stood up from a waiting seat (no match screen was open)
	end
	closeCurrent()
end)
Net.on(MS.Kinds.toast, function(p: any)
	if type(p) == "table" then
		K.toast({ kind = p.kind or "info", title = p.title or "", body = p.body or "" })
	end
end)
Net.on(MS.Kinds.say, function(p: any)
	if type(p) == "table" and typeof(p.part) == "Instance" and p.part:IsA("BasePart") and type(p.text) == "string" then
		Fx.bubble(p.part, p.text, p.dur)
	end
end)

player.CharacterAdded:Connect(function()
	-- a respawn ends any match on the server; make sure the camera comes back
	closeCurrent()
end)

print("[MiniGames] client ready")
