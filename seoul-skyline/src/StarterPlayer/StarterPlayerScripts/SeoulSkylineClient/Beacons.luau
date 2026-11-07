--!strict
-- SeoulSkylineClient / Beacons — 고층 항공장애등(태그 SeoulBeacon) 깜빡임
--   부드러운 1 Hz 맥동: Transparency/Color 를 Sine InOut 으로 0.5 초 동안 어둡게 → 되돌림(Reverses, 무한 반복).
--   같은 건물(같은 부모 모델)의 등은 함께 깜빡이고, 건물마다 위상이 다름(이름 해시). 스트리밍으로 늦게 오거나
--   사라지는 등도 CollectionService 신호로 처리하고, 중지 시 원래 색/투명도로 복구합니다.

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Util = require(script.Parent.Util)

local Beacons = {}

local TAG = "SeoulBeacon"
local PULSE = TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local DIM = Color3.fromRGB(40, 4, 4)

type Entry = { tween: Tween, color: Color3, transparency: number, alive: boolean }

function Beacons.start(root: Model): () -> ()
	if root:GetAttribute("Beacons") == false then
		return function() end
	end
	local active: { [BasePart]: Entry } = {}
	local conns: { RBXScriptConnection } = {}

	local function add(inst: Instance)
		if not inst:IsA("BasePart") or active[inst] or not inst:IsDescendantOf(root) then
			return
		end
		local part = inst :: BasePart
		local base = part.Color
		local baseT = part.Transparency
		local tween = TweenService:Create(part, PULSE, {
			Color = base:Lerp(DIM, 0.85),
			Transparency = math.max(baseT, 0.78),
		})
		local e: Entry = { tween = tween, color = base, transparency = baseT, alive = true }
		active[part] = e
		local key = if part.Parent then part.Parent:GetFullName() else part:GetFullName()
		local phase = (Util.hash(key) % 997) / 997 -- 0 ~ 1 초
		task.delay(phase, function()
			if e.alive then
				tween:Play()
			end
		end)
	end

	local function remove(inst: Instance, restore: boolean)
		local part = inst :: BasePart
		local e = active[part]
		if not e then
			return
		end
		active[part] = nil
		e.alive = false
		e.tween:Cancel()
		if restore and part.Parent then
			part.Color = e.color
			part.Transparency = e.transparency
		end
	end

	table.insert(conns, CollectionService:GetInstanceAddedSignal(TAG):Connect(add))
	table.insert(conns, CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(inst)
		remove(inst, false)
	end))
	for _, inst in CollectionService:GetTagged(TAG) do
		add(inst)
	end

	return function()
		Util.disconnectAll(conns)
		local list = {}
		for part in active do
			table.insert(list, part)
		end
		for _, part in list do
			remove(part, true)
		end
	end
end

return Beacons
