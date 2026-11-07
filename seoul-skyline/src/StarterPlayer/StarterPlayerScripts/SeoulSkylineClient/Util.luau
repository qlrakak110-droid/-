--!strict
-- SeoulSkylineClient / Util — 클라이언트 공용 상수·도우미
--   클라이언트는 ServerStorage(Config)를 읽을 수 없으므로 필요한 값은 맵 루트 속성(WaterFx 가 기록)에서 읽고,
--   없으면 아래 기본값(Config.Palette 와 동일)을 씁니다.

local Util = {}

Util.ROOT_NAME = "SeoulSkyline"
Util.METERS_PER_STUD = 0.3

local rgb = Color3.fromRGB
Util.Palette = {
	Headlight = rgb(255, 246, 226),
	Taillight = rgb(255, 46, 36),
	Beacon = rgb(255, 30, 24),
}

-- 실측 m → stud (루트 속성 MetersPerStud 가 있으면 그 값)
function Util.m(meters: number, root: Instance?): number
	local mps = root and root:GetAttribute("MetersPerStud")
	return meters / (if typeof(mps) == "number" and mps > 0 then mps else Util.METERS_PER_STUD)
end

function Util.color(root: Instance?, attr: string, fallback: Color3): Color3
	local v = root and root:GetAttribute(attr)
	return if typeof(v) == "Color3" then v else fallback
end

function Util.hash(s: string): number
	local h = 2166136261
	for i = 1, #s do
		h = bit32.bxor(h, string.byte(s, i))
		h = (h * 16777619) % 4294967296
	end
	return h
end

-- "아무 입력": 키보드/마우스 버튼/터치/게임패드 버튼 (마우스 이동·휠·스틱 이동은 제외)
local UIT = Enum.UserInputType
local ACCEPT: { [EnumItem]: boolean } = {
	[UIT.Keyboard] = true,
	[UIT.MouseButton1] = true,
	[UIT.MouseButton2] = true,
	[UIT.MouseButton3] = true,
	[UIT.Touch] = true,
}
local STICKS: { [EnumItem]: boolean } = {
	[Enum.KeyCode.Thumbstick1] = true,
	[Enum.KeyCode.Thumbstick2] = true,
}
function Util.isUserInput(input: InputObject): boolean
	local t = input.UserInputType
	if ACCEPT[t] then
		return true
	end
	if string.sub(t.Name, 1, 7) == "Gamepad" then
		return not STICKS[input.KeyCode]
	end
	return false
end

function Util.disconnectAll(list: { RBXScriptConnection })
	for _, c in list do
		c:Disconnect()
	end
	table.clear(list)
end

-- 로컬 ScreenGui (리스폰에도 유지)
function Util.screenGui(name: string, order: number): ScreenGui?
	local plr = game:GetService("Players").LocalPlayer
	local pg = plr and plr:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return nil
	end
	local g = Instance.new("ScreenGui")
	g.Name = name
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = order
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.Parent = pg
	return g
end

return Util
