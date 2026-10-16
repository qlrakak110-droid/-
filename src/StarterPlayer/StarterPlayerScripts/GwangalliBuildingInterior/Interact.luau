--!strict
-- GwangalliBuildingInterior/Interact: 이 클라이언트에서만 도는 상호작용 (서버 행동과 겹치지 않는 것만, R8).
--   * 프롬프트: 이름 "GwInteriorPrompt", R 키 (패드 Y), 최대 5 스터드, OnePerButton, 줄 시야 필요 없음.
--     맵 서버의 앵커(주문 · 계산 · 앉기 · 메뉴판 · 화장실 ...) 6.5 스터드 안에는 만들지 않음.
--   * 종류: toggle (켜기/끄기), cycle (채널 · 곡 · 모드 돌리기), swing (문 · 뚜껑 여닫기), 그리고 프롬프트 없는
--     애니메이션 (시계 바늘 · 화면 순환 · 회전 · 깜빡임) = Interact.anim.
-- 모든 효과는 K.parts 의 파트(클라이언트 소유)만 바꿉니다. 맵 파트는 안 건드림.

local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local Interact = {}

local MAX_DIST = 5
local HOST_GAP = 6.5

-- 서버 앵커가 될 자리 (ShopLife 가 프롬프트를 띄우는 곳): V 에서 미리 계산 + 실제 ShopLife 폴더가 있으면 그 위치
local HOST_NAMES = {
	"PosBase", "OrderKiosk", "KioskScreen", "CounterTop", "KitchenPass", "PassLedge", "Sign_메  뉴", "Sign_MENU", "DoorLeaf",
	"HotWater", "Microwave", "ATMScreen", "TapPost", "TankWater", "DeskBell", "Mailboxes", "Tester", "WaterPurifier", "Bin",
	"TrashBin", "FrontDesk", "WorkDesk", "Gondola_1", "Fridge", "OpenChiller", "PastryCase", "WallRack", "MDBoard",
}

function Interact.hostPoints(V: any): { Vector3 }
	local pts = {}
	for _, n in HOST_NAMES do
		for _, r in V.byName[n] or {} do
			table.insert(pts, r.c)
		end
	end
	for _, t in V.tables or {} do
		table.insert(pts, (t.min + t.max) / 2)
	end
	for _, k in V.keep do
		if k.kind == "bin" then
			table.insert(pts, (k.min + k.max) / 2)
		end
	end
	-- 실제 ShopLife 앵커
	local root = workspace:FindFirstChild("GwangalliBuildingsShopLife")
	local f = root and root:FindFirstChild(V.key)
	local anchors = f and f:FindFirstChild("Anchors")
	if anchors then
		for _, a in anchors:GetChildren() do
			if a:IsA("BasePart") then
				table.insert(pts, V.cf:PointToObjectSpace(a.Position))
			end
		end
	end
	return pts
end

-- 이 로컬 위치에 우리 프롬프트를 둬도 되나?
function Interact.canPrompt(K: any, lp: Vector3): boolean
	if not K.hostPts then
		K.hostPts = Interact.hostPoints(K.V)
	end
	for _, h in K.hostPts do
		local d = h - lp
		if Vector3.new(d.X, 0, d.Z).Magnitude < HOST_GAP then
			return false
		end
	end
	for _, p in K.promptAt or {} do
		if (p - lp).Magnitude < 2.5 then
			return false
		end
	end
	return true
end

local function clickSound(part: BasePart, id: string?)
	local s = Instance.new("Sound")
	s.Name = "GwInteriorClick"
	s.SoundId = id or "rbxasset://sounds/switch.wav"
	s.Volume = 0.35
	s.RollOffMaxDistance = 30
	s.Parent = part
	s:Play()
	task.delay(2, function()
		s:Destroy()
	end)
end
Interact.click = clickSound

-- 프롬프트 붙이기. spec = { action, object, hold?, fn = function(n) end (n = 누른 횟수) , sound? }
function Interact.prompt(K: any, part: BasePart, spec: any): ProximityPrompt?
	if part.Parent == nil then
		return nil
	end
	local lp = K.V.cf:PointToObjectSpace(part.Position)
	if not Interact.canPrompt(K, lp) then
		K:note("prompt skipped near host: " .. tostring(spec.object))
		return nil
	end
	K.promptAt = K.promptAt or {}
	table.insert(K.promptAt, lp)
	local pr = Instance.new("ProximityPrompt")
	pr.Name = "GwInteriorPrompt"
	pr.ActionText = spec.action or "사용하기"
	pr.ObjectText = spec.object or ""
	pr.HoldDuration = spec.hold or 0
	pr.MaxActivationDistance = math.min(spec.dist or MAX_DIST, MAX_DIST)
	pr.RequiresLineOfSight = false
	pr.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	pr.KeyboardKeyCode = Enum.KeyCode.R
	pr.GamepadKeyCode = Enum.KeyCode.ButtonY
	pr.Style = Enum.ProximityPromptStyle.Default
	pr.Parent = part
	local n = 0
	local conn = pr.Triggered:Connect(function()
		n += 1
		local ok, err = pcall(spec.fn, n, pr)
		if not ok then
			warn("[GwangalliBuildingInterior] prompt " .. tostring(spec.object) .. ": " .. tostring(err))
		end
		if spec.sound ~= false then
			clickSound(part, spec.sound)
		end
	end)
	K.conns = K.conns or {}
	table.insert(K.conns, conn)
	table.insert(K.prompts, pr)
	return pr
end

-- 켜기/끄기: on(state) 콜백. 첫 상태 = spec.state (기본 true = 켜짐)
function Interact.toggle(K: any, part: BasePart, spec: any): ProximityPrompt?
	local state = if spec.state == nil then true else spec.state
	local onT, offT = spec.onText or "끄기", spec.offText or "켜기"
	local pr: ProximityPrompt? = nil
	pr = Interact.prompt(K, part, {
		action = if state then onT else offT,
		object = spec.object,
		sound = spec.sound,
		fn = function(_n, p)
			state = not state
			spec.on(state)
			p.ActionText = if state then onT else offT
		end,
	})
	return pr
end

-- 순환: items 를 차례로. spec.on(i, item)
function Interact.cycle(K: any, part: BasePart, items: { any }, spec: any): ProximityPrompt?
	local i = spec.start or 1
	return Interact.prompt(K, part, {
		action = spec.action or "바꾸기",
		object = spec.object,
		sound = spec.sound,
		fn = function()
			i = i % #items + 1
			spec.on(i, items[i])
		end,
	})
end

-- 여닫기: model 안 파트를 hinge(월드 점) 둘레 axis(월드 단위벡터)로 angle 라디안 회전 (트윈)
function Interact.swing(K: any, model: Model, hinge: Vector3, axis: Vector3, angle: number, spec: any?): ProximityPrompt?
	local s: any = spec or {}
	local parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, { p = d, cf = d.CFrame })
		end
	end
	if #parts == 0 then
		return nil
	end
	local open = false
	local handle = model:FindFirstChildWhichIsA("BasePart", true) :: BasePart
	for _, r in parts do
		if string.find(r.p.Name, "Handle") then
			handle = r.p
		end
	end
	local function set(o: boolean)
		local rot = CFrame.new(hinge) * CFrame.fromAxisAngle(axis, if o then angle else 0) * CFrame.new(-hinge)
		for _, r in parts do
			if r.p.Parent then
				TweenService:Create(r.p, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = rot * r.cf }):Play()
			end
		end
	end
	return Interact.prompt(K, handle, {
		action = s.openText or "열기",
		object = s.object or "문",
		sound = s.sound or "rbxasset://sounds/clickfast.wav",
		fn = function(_n, p)
			open = not open
			set(open)
			p.ActionText = if open then (s.closeText or "닫기") else (s.openText or "열기")
		end,
	})
end

-- 조명 묶음 켜고 끄기 (우리 불빛 + 빛나는 네온 파트)
function Interact.lightSwitch(K: any, switchPart: BasePart, object: string?): ProximityPrompt?
	local neons = {}
	for _, p in K.parts do
		if p.Material == Enum.Material.Neon and (string.find(p.Name, "Lamp") or string.find(p.Name, "Bulb") or string.find(p.Name, "Diffuser") or string.find(p.Name, "Lens") or string.find(p.Name, "PanelLight") or string.find(p.Name, "LED")) then
			table.insert(neons, { p = p, c = p.Color })
		end
	end
	return Interact.toggle(K, switchPart, {
		object = object or "실내 조명",
		state = true,
		fn = nil,
		on = function(state)
			for _, l in K.lights do
				l.Enabled = state
			end
			for _, n in neons do
				if n.p.Parent then
					n.p.Material = if state then Enum.Material.Neon else Enum.Material.SmoothPlastic
					n.p.Color = if state then n.c else n.c:Lerp(Color3.fromRGB(120, 120, 120), 0.6)
				end
			end
		end,
	})
end

-- 프롬프트 없는 애니메이션: fn(t, dt) 를 매장이 활성일 때 10Hz 로 부름
function Interact.anim(K: any, fn: (number, number) -> ())
	K.anims = K.anims or {}
	table.insert(K.anims, fn)
end

-- 시계 바늘을 게임 시각(Lighting.ClockTime)에 맞춰 돌림. hour/minute = Props.clock 반환 파트, center = dcf
function Interact.clock(K: any, hour: BasePart, minute: BasePart, dcf: CFrame, d: number)
	if hour.Parent == nil then
		return
	end
	local wc = K.cf * dcf
	Interact.anim(K, function()
		local h = Lighting.ClockTime
		local m = (h % 1) * 60
		local ah = -((h % 12) / 12) * math.pi * 2
		local am = -(m / 60) * math.pi * 2
		hour.CFrame = wc * CFrame.Angles(0, 0, ah) * CFrame.new(0, d * 0.1, 0.145 + 0.01)
		minute.CFrame = wc * CFrame.Angles(0, 0, am) * CFrame.new(0, d * 0.16, 0.165 + 0.01)
	end)
end

-- 화면 순환 (TV · 키오스크 대기화면 · 전광판): label 의 글자 / 화면 파트 색을 period 초마다 바꿈
function Interact.screenLoop(K: any, screen: BasePart?, label: TextLabel?, frames: { any }, period: number?)
	local per = period or 4
	local last = -1
	Interact.anim(K, function(t)
		local i = math.floor(t / per) % #frames + 1
		if i == last then
			return
		end
		last = i
		local f = frames[i]
		if screen and screen.Parent and f.c then
			screen.Color = f.c
		end
		if label and label.Parent and f.text then
			label.Text = f.text
		end
	end)
end

-- 회전 (선풍기 · 실링팬 · 미러볼): parts 를 center(월드) 둘레 Y 축으로 rps 회전/초
function Interact.spin(K: any, parts: { BasePart }, center: Vector3, rps: number)
	local base = {}
	for _, p in parts do
		table.insert(base, { p = p, cf = p.CFrame })
	end
	Interact.anim(K, function(t)
		local rot = CFrame.new(center) * CFrame.Angles(0, t * rps * math.pi * 2, 0) * CFrame.new(-center)
		for _, b in base do
			if b.p.Parent then
				b.p.CFrame = rot * b.cf
			end
		end
	end)
end

return Interact
