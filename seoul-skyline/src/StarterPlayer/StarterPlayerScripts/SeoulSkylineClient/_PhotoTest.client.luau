-- TEMP test (removed after verification)
local plr = game:GetService("Players").LocalPlayer
local CameraFx = require(script.Parent:WaitForChild("CameraFx"))
local root = workspace:WaitForChild("SeoulSkyline")
for i = 1, 6 do
	task.wait(0.25)
	local c = workspace.CurrentCamera
	print("PHOTO_TEST t", i, c.CameraType, c.FieldOfView, c.CFrame.Position)
end
local introGui = plr.PlayerGui:FindFirstChild("SeoulIntro")
print("PHOTO_TEST intro", plr:GetAttribute("SeoulIntroPlayed"), "introGui", introGui ~= nil, "cam", workspace.CurrentCamera.CameraType, workspace.CurrentCamera.FieldOfView)
local prompt
for _, d in root:GetDescendants() do
	if d:IsA("ProximityPrompt") and d.ActionText == "사진 구도" then
		prompt = d
		break
	end
end
print("PHOTO_TEST pcall", pcall(CameraFx.enterPhoto, prompt))
print("PHOTO_TEST waiting", CameraFx.isPhotoMode())
task.wait(1.5)
local cam = workspace.CurrentCamera
local dof = game:GetService("Lighting"):FindFirstChildOfClass("DepthOfFieldEffect")
print("PHOTO_TEST in", CameraFx.isPhotoMode(), "gui", plr.PlayerGui:FindFirstChild("SeoulPhotoMode") ~= nil, "dof", dof.Enabled, dof.FarIntensity, dof.NearIntensity, "prompt", prompt.Enabled, "cam", cam.CameraType, cam.FieldOfView, cam.CFrame.Position, "introGui", plr.PlayerGui:FindFirstChild("SeoulIntro") ~= nil)
CameraFx.exitPhoto()
task.wait(1.5)
print("PHOTO_TEST out", CameraFx.isPhotoMode(), "gui", plr.PlayerGui:FindFirstChild("SeoulPhotoMode") ~= nil, "dof", dof.Enabled, dof.FarIntensity, "prompt", prompt.Enabled, "cam", cam.CameraType, cam.FieldOfView)
