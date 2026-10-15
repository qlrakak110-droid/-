--!strict
-- GwangalliCarInterior/Glass: 차 유리를 검은 반투명 틴팅 + 반사로 (클라이언트 로컬, 서버·다른 플레이어에 영향 없음).
--   앞유리: 스모크 (Transparency 0.55, Reflectance 0.16) — 운전 시야 확보
--   옆·뒤·쿼터 유리: 검은 틴팅 (Transparency 0.3, Reflectance 0.24) — 밖에서 실내가 거의 안 보임
-- 운전석 시점에서는 GwangalliDrive 카메라가 유리 LocalTransparencyModifier 를 올려 조금 더 맑게 보입니다.

local Glass = {}

local ROLE: { [string]: string } = {
	Windshield = "ws",
	FrontGlass = "ws",
	RearGlass = "rear",
	RearWindow = "rear",
	BackGlass = "rear",
	SideGlass = "side",
	QuarterGlass = "side",
	DoorGlass = "side",
	CabGlass = "side",
	SideWindow = "side",
	Window = "side",
}

Glass.LOOK = {
	ws = { color = Color3.fromRGB(18, 22, 27), transparency = 0.55, reflectance = 0.16 },
	side = { color = Color3.fromRGB(8, 10, 13), transparency = 0.3, reflectance = 0.24 },
	rear = { color = Color3.fromRGB(8, 10, 13), transparency = 0.3, reflectance = 0.24 },
}

function Glass.roleOf(p: BasePart): string?
	local r = ROLE[p.Name]
	if not r and p:GetAttribute("Glass") == true then
		r = if p:GetAttribute("Windshield") == true then "ws" else "side"
	end
	return r
end

-- 차 한 대의 유리를 틴팅. 반환: 바꾼 개수
function Glass.tint(model: Model): number
	local n = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Parent and d.Parent.Name ~= "CabinAAA" then
			local role = Glass.roleOf(d)
			-- 원래 반투명한 유리만 (주차장 블록 차의 불투명 앞유리 웨지는 그대로)
			if role and d.Transparency > 0.05 and d.Transparency < 0.95 and d:GetAttribute("GwTinted") ~= true then
				local look = Glass.LOOK[role]
				d.Material = Enum.Material.Glass
				d.Color = look.color
				d.Transparency = look.transparency
				d.Reflectance = look.reflectance
				d.CastShadow = false
				d:SetAttribute("GwTinted", true)
				n += 1
			end
		end
	end
	return n
end

return Glass
