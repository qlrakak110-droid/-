--!strict
-- SeoulSkylineClient / AutoDoors — 자동 미닫이문(태그 "SeoulAutoDoor")
--   빌더는 문짝을 "열린" 위치로 만들고 속성 ClosedOffset(Vector3, 월드 stud) = 닫힌 위치 - 열린 위치 를 기록합니다
--   (스크립트가 없어도 드나들 수 있게). 클라이언트는 같은 문에 속한 파트(같은 부모, 열린 위치 4.5 m 이내)를 한 문으로
--   묶고, 아무 캐릭터든 문 앞 2.4 m(센서 범위) 안에 있으면 열고, 없으면 닫습니다 — 부드러운 0.55 초 트윈.
--   클라이언트 전용 연출이라 서버 부하/복제 지연이 없고, StreamingEnabled 로 문이 사라졌다 나타나도 다시 묶습니다.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local Util = require(script.Parent:WaitForChild("Util"))

local AutoDoors = {}

local TAG = "SeoulAutoDoor"
local TWEEN = TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)

type Leaf = { part: BasePart, open: CFrame, closed: CFrame, tween: Tween? }
type Door = { parent: Instance, leaves: { Leaf }, center: Vector3, isOpen: boolean }

function AutoDoors.start(root: Model): () -> ()
	local sensor = Util.m(2.4, root)
	local groupR = Util.m(4.5, root)
	local doors: { Door } = {}
	local byPart: { [BasePart]: Door } = {}
	local conns: { RBXScriptConnection } = {}

	local function recenter(d: Door)
		local sum = Vector3.zero
		for _, l in d.leaves do
			sum += (l.open.Position + l.closed.Position) / 2
		end
		d.center = sum / math.max(1, #d.leaves)
	end

	local function setState(d: Door, open: boolean, instant: boolean?)
		d.isOpen = open
		for _, l in d.leaves do
			if l.tween then
				l.tween:Cancel()
				l.tween = nil
			end
			if l.part.Parent then
				local goal = if open then l.open else l.closed
				if instant then
					l.part.CFrame = goal
				else
					local tw = TweenService:Create(l.part, TWEEN, { CFrame = goal })
					l.tween = tw
					tw:Play()
				end
			end
		end
	end

	local function add(inst: Instance)
		if not inst:IsA("BasePart") or byPart[inst] or not inst:IsDescendantOf(root) then
			return
		end
		local off = inst:GetAttribute("ClosedOffset")
		if typeof(off) ~= "Vector3" then
			return
		end
		-- 이미 닫힌 위치로 움직인 적이 있으면(스트리밍 재진입) 빌드 값 = 열린 위치 속성을 우선
		local openAttr = inst:GetAttribute("OpenCFrame")
		local open = if typeof(openAttr) == "CFrame" then openAttr else inst.CFrame
		local leaf: Leaf = { part = inst, open = open, closed = open + off, tween = nil }
		local door: Door? = nil
		for _, d in doors do
			if d.parent == inst.Parent and (d.center - open.Position).Magnitude <= groupR then
				door = d
				break
			end
		end
		if not door then
			local nd: Door = { parent = inst.Parent :: Instance, leaves = {}, center = open.Position, isOpen = true }
			table.insert(doors, nd)
			door = nd
		end
		local d = door :: Door
		table.insert(d.leaves, leaf)
		byPart[inst] = d
		recenter(d)
		-- 새 문짝은 문 상태에 바로 맞춤(나머지 문짝과 어긋나지 않게)
		inst.CFrame = if d.isOpen then leaf.open else leaf.closed
	end

	local function remove(inst: Instance)
		local d = byPart[inst :: BasePart]
		if not d then
			return
		end
		byPart[inst :: BasePart] = nil
		for i, l in d.leaves do
			if l.part == inst then
				if l.tween then
					l.tween:Cancel()
				end
				table.remove(d.leaves, i)
				break
			end
		end
		if #d.leaves == 0 then
			local i = table.find(doors, d)
			if i then
				table.remove(doors, i)
			end
		else
			recenter(d)
		end
	end

	for _, p in CollectionService:GetTagged(TAG) do
		add(p)
	end
	table.insert(conns, CollectionService:GetInstanceAddedSignal(TAG):Connect(add))
	table.insert(conns, CollectionService:GetInstanceRemovedSignal(TAG):Connect(remove))

	local acc = 0
	table.insert(conns, RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.1 then
			return
		end
		acc = 0
		if #doors == 0 then
			return
		end
		local positions: { Vector3 } = {}
		for _, plr in Players:GetPlayers() do
			local ch = plr.Character
			local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
			if hrp and hrp:IsA("BasePart") then
				table.insert(positions, hrp.Position)
			end
		end
		for _, d in doors do
			local want = false
			for _, p in positions do
				local dx, dz = p.X - d.center.X, p.Z - d.center.Z
				if dx * dx + dz * dz <= sensor * sensor and math.abs(p.Y - d.center.Y) < sensor * 1.5 then
					want = true
					break
				end
			end
			if want ~= d.isOpen then
				setState(d, want)
			end
		end
	end))

	return function()
		Util.disconnectAll(conns)
		for _, d in doors do
			setState(d, true, true) -- 정리할 때는 빌드 상태(열림)로 되돌림
		end
		table.clear(doors)
		table.clear(byPart)
	end
end

return AutoDoors
