--!strict
-- Omok/OmokBoards: draws the stones on EVERY omok table this client can see (client only; local
-- parts, nothing replicated). Source of truth: the station attributes the server writes
-- (OmokBoard 225 chars, OmokLast, OmokSeq, OmokWin). So anyone walking past watches the real game.
--   * a new stone: the mover's hand reaches out first (their mg_place emote), then the stone drops
--     onto its point with a short wooden "딱" (positional sound) - DROP_DELAY after the attribute
--     change, which is when the hand is over the board.
--   * the last move carries a small red marker; a finished game lights the winning five.
--   * ghost(model, cell, color, bad) shows the local player's pending stone (OmokClient).
-- Board geometry = StationBuilder: cell (x, y) sits at Board.CFrame * (x - 8, top, y - 8) * Cell.

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local OmokBoards = {}

local MS: any = nil
local OC: any = nil
local Fx: any = nil
local folder: Folder = nil :: any

local DROP_DELAY = 0.38
local STONE_H = 0.07

type B = {
	model: Model,
	board: BasePart,
	stones: { [number]: BasePart },
	shown: string,
	seq: number,
	marker: BasePart?,
	ghost: BasePart?,
	winParts: { BasePart },
	conns: { RBXScriptConnection },
}
local boards: { [Model]: B } = {}

local BLACK = Color3.fromRGB(22, 22, 26)
local WHITE = Color3.fromRGB(244, 244, 238)

local function cellCFrame(b: B, i: number, lift: number?): CFrame
	local x, y = OC.xy(i)
	local cell = OC.CELL
	local top = b.board.Size.Y / 2 + STONE_H / 2 + (lift or 0)
	return b.board.CFrame * CFrame.new((x - (OC.SIZE + 1) / 2) * cell, top, (y - (OC.SIZE + 1) / 2) * cell)
end

local function makeStone(b: B, i: number, color: number): BasePart
	local p = Instance.new("Part")
	p.Name = "Stone"
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(STONE_H, OC.CELL * 0.92, OC.CELL * 0.92)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = if color == 1 then Enum.Material.SmoothPlastic else Enum.Material.Glass
	p.Color = if color == 1 then BLACK else WHITE
	p.Reflectance = if color == 1 then 0.08 else 0.04
	p.CFrame = cellCFrame(b, i) * CFrame.Angles(0, 0, math.rad(90))
	p.Parent = folder
	return p
end

local function clearAll(b: B)
	for _, s in b.stones do
		s:Destroy()
	end
	table.clear(b.stones)
	for _, w in b.winParts do
		w:Destroy()
	end
	table.clear(b.winParts)
	if b.marker then
		b.marker:Destroy()
		b.marker = nil
	end
	b.shown = ""
end

local function setMarker(b: B, i: number)
	if i <= 0 or not b.stones[i] then
		if b.marker then
			b.marker.Transparency = 1
		end
		return
	end
	if not b.marker then
		local m = Instance.new("Part")
		m.Name = "LastMove"
		m.Shape = Enum.PartType.Cylinder
		m.Size = Vector3.new(0.012, OC.CELL * 0.34, OC.CELL * 0.34)
		m.Anchored = true
		m.CanCollide = false
		m.CanQuery = false
		m.CastShadow = false
		m.Material = Enum.Material.Neon
		m.Color = Color3.fromRGB(255, 70, 70)
		m.Parent = folder
		b.marker = m
	end
	local mk = b.marker :: BasePart
	mk.Transparency = 0
	mk.CFrame = cellCFrame(b, i, STONE_H / 2 + 0.006) * CFrame.Angles(0, 0, math.rad(90))
end

local function showWin(b: B)
	for _, w in b.winParts do
		w:Destroy()
	end
	table.clear(b.winParts)
	local s = b.model:GetAttribute("OmokWin")
	if type(s) ~= "string" or s == "" then
		return
	end
	for _, v in string.split(s, ",") do
		local i = tonumber(v)
		if i and b.stones[i] then
			local ring = Instance.new("Part")
			ring.Name = "WinGlow"
			ring.Shape = Enum.PartType.Cylinder
			ring.Size = Vector3.new(STONE_H * 0.4, OC.CELL * 1.02, OC.CELL * 1.02)
			ring.Anchored = true
			ring.CanCollide = false
			ring.CanQuery = false
			ring.Material = Enum.Material.Neon
			ring.Color = Color3.fromRGB(255, 200, 60)
			ring.Transparency = 0.25
			ring.CFrame = cellCFrame(b, i, -STONE_H * 0.35) * CFrame.Angles(0, 0, math.rad(90))
			ring.Parent = folder
			table.insert(b.winParts, ring)
		end
	end
end

local function sync(b: B)
	local s = b.model:GetAttribute("OmokBoard")
	local seq = b.model:GetAttribute("OmokSeq")
	local last = b.model:GetAttribute("OmokLast")
	seq = if type(seq) == "number" then seq else 0
	last = if type(last) == "number" then last else 0
	if type(s) ~= "string" or s == "" or seq < b.seq then
		clearAll(b)
		b.seq = seq
		if type(s) ~= "string" or s == "" then
			return
		end
	end
	local animate = seq == b.seq + 1 and b.shown ~= ""
	b.seq = seq
	local target = OC.decode(s)
	for i = 1, OC.SIZE * OC.SIZE do
		local want = target[i]
		local have = b.stones[i]
		if want == 0 and have then
			have:Destroy()
			b.stones[i] = nil
		elseif want ~= 0 and not have then
			local stone = makeStone(b, i, want)
			b.stones[i] = stone
			if animate and i == last then
				-- the hand comes over the board first, then the stone lands with a 딱
				local restCF = stone.CFrame
				stone.Transparency = 1
				task.delay(DROP_DELAY, function()
					if not stone.Parent then
						return
					end
					stone.CFrame = restCF + Vector3.new(0, 0.35, 0)
					stone.Transparency = 0
					TweenService:Create(stone, TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = restCF }):Play()
					task.delay(0.09, function()
						Fx.sound("stone", b.board)
						setMarker(b, last)
					end)
				end)
			end
		end
	end
	b.shown = s
	if not animate then
		setMarker(b, last)
	end
	showWin(b)
end

local function add(model: Instance)
	if not model:IsA("Model") or boards[model] or model:GetAttribute("GameId") ~= "omok" then
		return
	end
	local board = model:WaitForChild("Board", 10)
	if not board or not board:IsA("BasePart") then
		return
	end
	local b: B = { model = model, board = board, stones = {}, shown = "", seq = 0, marker = nil, ghost = nil, winParts = {}, conns = {} }
	boards[model] = b
	for _, a in { "OmokBoard", "OmokSeq", "OmokWin" } do
		table.insert(b.conns, model:GetAttributeChangedSignal(a):Connect(function()
			sync(b)
		end))
	end
	sync(b)
end

local function remove(model: Instance)
	local b = boards[model :: Model]
	if not b then
		return
	end
	boards[model :: Model] = nil
	for _, c in b.conns do
		c:Disconnect()
	end
	clearAll(b)
	if b.ghost then
		b.ghost:Destroy()
	end
end

function OmokBoards.start(ms: any, fx: any)
	MS = ms
	Fx = fx
	OC = require(game:GetService("ReplicatedStorage"):WaitForChild("GwangalliMiniGamesShared"):WaitForChild("OmokConfig")) :: any
	folder = Instance.new("Folder")
	folder.Name = "MiniGamesLocal"
	folder.Parent = Workspace
	CollectionService:GetInstanceAddedSignal(MS.Tags.Station):Connect(function(m)
		task.spawn(add, m)
	end)
	CollectionService:GetInstanceRemovedSignal(MS.Tags.Station):Connect(remove)
	for _, m in CollectionService:GetTagged(MS.Tags.Station) do
		task.spawn(add, m)
	end
	OmokBoards.started = true
end

-- Cell under a world point on this board (nil = off the grid).
function OmokBoards.cellAt(model: Model, pos: Vector3): number?
	local b = boards[model]
	if not b then
		return nil
	end
	local l = b.board.CFrame:PointToObjectSpace(pos)
	local half = (OC.SIZE + 1) / 2
	local x = math.floor(l.X / OC.CELL + half + 0.5)
	local y = math.floor(l.Z / OC.CELL + half + 0.5)
	if not OC.inside(x, y) then
		return nil
	end
	return OC.idx(x, y)
end

function OmokBoards.boardPart(model: Model): BasePart?
	local b = boards[model]
	return b and b.board
end

function OmokBoards.ghost(model: Model, cell: number?, color: number, bad: boolean?)
	local b = boards[model]
	if not b then
		return
	end
	if not cell then
		if b.ghost then
			b.ghost.Transparency = 1
		end
		return
	end
	if not b.ghost then
		local g = makeStone(b, cell, color)
		g.Name = "Ghost"
		b.ghost = g
	end
	local g = b.ghost :: BasePart
	g.Color = if bad then Color3.fromRGB(255, 80, 80) elseif color == 1 then BLACK else WHITE
	g.Material = Enum.Material.SmoothPlastic
	g.Transparency = 0.45
	g.CFrame = cellCFrame(b, cell, 0.01) * CFrame.Angles(0, 0, math.rad(90))
end

return OmokBoards
