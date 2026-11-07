-- TEMP test (removed after verification)
local plr = game:GetService("Players").LocalPlayer
local root = workspace:WaitForChild("SeoulSkyline")
task.wait(1.2)
print("PHOTO_TEST introPlayed", plr:GetAttribute("SeoulIntroPlayed"), "camType", workspace.CurrentCamera.CameraType)
local prompt
for _, d in root:GetDescendants() do
	if d:IsA("ProximityPrompt") and d.ActionText == "사진 구도" then
		prompt = d
		break
	end
end
print("PHOTO_TEST prompt", prompt and prompt:GetFullName())
local char = plr.Character
char:PivotTo(prompt.Parent.CFrame * CFrame.new(0, 0, 5))
task.wait(0.5)
prompt:InputHoldBegin()
task.wait(0.1)
prompt:InputHoldEnd()
task.wait(2)
local dof = game:GetService("Lighting"):FindFirstChildOfClass("DepthOfFieldEffect")
print("PHOTO_TEST in", "dof", dof and dof.Enabled, dof and dof.FarIntensity, dof and dof.NearIntensity, "gui", plr.PlayerGui:FindFirstChild("SeoulPhotoMode") ~= nil, "promptEnabled", prompt.Enabled, "camType", workspace.CurrentCamera.CameraType, "fov", workspace.CurrentCamera.FieldOfView)
local hum = char:FindFirstChildOfClass("Humanoid")
hum:Move(Vector3.new(1, 0, 0))
task.wait(1)
hum:Move(Vector3.zero)
print("PHOTO_TEST out", "dof", dof and dof.Enabled, dof and dof.FarIntensity, "gui", plr.PlayerGui:FindFirstChild("SeoulPhotoMode") ~= nil, "promptEnabled", prompt.Enabled, "camType", workspace.CurrentCamera.CameraType)
local n = 0
for _, b in game:GetService("CollectionService"):GetTagged("SeoulBoat") do n += 1 end
print("PHOTO_TEST boats", n, "beacons", #game:GetService("CollectionService"):GetTagged("SeoulBeacon"))
