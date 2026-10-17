--!strict
-- GwangalliDecorPlus (LocalScript): 내 집 마련 자유 배치 인테리어 — client boot.
-- Tracks the life-game home the player is in (attributes InHome / HomeRole set by Housing, model
-- Workspace.GwangalliHomeInstances.Home_<ownerId>), shows the home pill (✨ 자유 배치 / 집들이 ❤️ 📝),
-- opens the editor (K · pill · gamepad D-pad ↑), keeps it exclusive with the slot 🛠️ 인테리어
-- (PlayerGui.GwangalliInterior), runs the visual effects for every visitor, and the 📸 photo mode.
-- API for other LocalScripts: LocalPlayer.GwangalliDecorPlusOpen (BindableEvent) :Fire("editor" | "photo" | "close").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = require(ReplicatedStorage:WaitForChild("GwangalliDecorShared"))
local Config, Unit, Text = Shared.Config, Shared.Unit, Shared.Text

local Net = require(script:WaitForChild("Net"))
local Ui = require(script:WaitForChild("Ui"))
local Editor = require(script:WaitForChild("Editor"))
local Panels = require(script:WaitForChild("Panels"))
local Effects = require(script:WaitForChild("Effects"))
local Visit = require(script:WaitForChild("Visit"))
local Photo = require(script:WaitForChild("Photo"))

local player = Players.LocalPlayer

if not Net.start() then
	warn("[GwangalliDecorPlus] remotes not found — client idle")
	return
end

-------------------------------------------------------------------------------------------------
-- Home tracking
-------------------------------------------------------------------------------------------------
local home: any = { model = nil, U = nil, ownerId = 0, role = "" }
local unitCache: { [Instance]: any } = {}
local opening = false

local function homeModel(ownerId: number): Model?
	local c = workspace:FindFirstChild("GwangalliHomeInstances")
	if not c then
		return nil
	end
	local m = c:FindFirstChild("Home_" .. tostring(ownerId))
	if m and m:IsA("Model") then
		return m
	end
	return nil
end

local function unitOf(model: Model): any?
	local U = unitCache[model]
	if U and U.dirty then
		U = nil
	end
	if not U then
		U = Unit.scan(model)
		if U then
			unitCache[model] = U
			local furniture = model:FindFirstChild("Furniture")
			if furniture then
				local function mark()
					local cu = unitCache[model]
					if cu then
						cu.dirty = true
					end
				end
				furniture.DescendantAdded:Connect(mark)
				furniture.DescendantRemoving:Connect(mark)
			end
			model.AncestryChanged:Connect(function()
				if not model:IsDescendantOf(workspace) then
					unitCache[model] = nil
				end
			end)
		end
	end
	return U
end

local function refreshHome()
	local id = player:GetAttribute("InHome")
	local role = player:GetAttribute("HomeRole")
	if type(id) ~= "number" or id <= 0 or (role ~= "owner" and role ~= "guest") then
		home = { model = nil, U = nil, ownerId = 0, role = "" }
		return
	end
	local m = homeModel(id)
	if not m or m:GetAttribute("Staged") == true then
		home = { model = nil, U = nil, ownerId = id, role = role }
		return
	end
	-- the home is complete once the server built our folder in it
	if not m:FindFirstChild(Config.FOLDER_NAME) then
		home = { model = nil, U = nil, ownerId = id, role = role }
		return
	end
	local U = unitOf(m)
	home = { model = m, U = U, ownerId = id, role = role }
end

local function interiorOpen(): boolean
	local pg = player:FindFirstChild("PlayerGui")
	local g = pg and pg:FindFirstChild("GwangalliInterior")
	return g ~= nil and g:IsA("ScreenGui") and g.Enabled
end

-------------------------------------------------------------------------------------------------
-- Editor open / close
-------------------------------------------------------------------------------------------------
local closeEditor: (string?) -> ()
local hiddenHomeGui: ScreenGui? = nil

local function openPhoto()
	if Photo.isOpen() then
		return
	end
	refreshHome()
	if not home.U then
		return
	end
	if Editor.isOpen() then
		Editor.pause(true)
		local g = Panels.gui()
		if g then
			g.Enabled = false
		end
	end
	Photo.open(home.U, Editor.isOpen())
	task.spawn(function()
		while Photo.isOpen() do
			task.wait(0.2)
		end
		if Editor.isOpen() then
			Editor.pause(false)
			local g = Panels.gui()
			if g then
				g.Enabled = true
			end
		end
	end)
end

local function openEditor()
	if opening or Editor.isOpen() or Photo.isOpen() then
		return
	end
	refreshHome()
	if home.role ~= "owner" or home.ownerId ~= player.UserId or not home.model or not home.U then
		Ui.toast(Text.reason("notHome"), "bad")
		return
	end
	opening = true
	-- the slot 🛠️ 인테리어 and our editor never run together
	local ev = player:FindFirstChild("GwangalliHomeOpen")
	if ev and ev:IsA("BindableEvent") and interiorOpen() then
		ev:Fire("close")
		task.wait(0.2)
	end
	local snap = Net.call("open", {})
	opening = false
	if not snap.ok then
		Ui.toast("❌ " .. (snap.msg or Text.reason(snap.code)), "bad")
		return
	end
	refreshHome()
	if not home.model or not home.U then
		return
	end
	-- the life game's HomeBar (초대 · 나가기) steps aside while editing
	local pg = player:FindFirstChild("PlayerGui")
	local hg = pg and pg:FindFirstChild("GwangalliHome")
	if hg and hg:IsA("ScreenGui") and hg.Enabled then
		hg.Enabled = false
		hiddenHomeGui = hg
	end
	Editor.begin(snap, home.model, home.U)
	Panels.mount({
		snap = snap,
		model = home.model,
		U = home.U,
		onClose = function()
			closeEditor(nil)
		end,
		onPhoto = openPhoto,
	})
	Visit.setVisible(false)
end

closeEditor = function(reason: string?)
	if Photo.isOpen() then
		Photo.close()
	end
	if not Editor.isOpen() then
		return
	end
	Panels.unmount()
	Editor.finish()
	if hiddenHomeGui then
		if hiddenHomeGui.Parent then
			hiddenHomeGui.Enabled = true
		end
		hiddenHomeGui = nil
	end
	Visit.setVisible(true)
	Visit.refresh()
	if reason then
		Ui.toast(reason)
	end
end

-------------------------------------------------------------------------------------------------
-- Server events
-------------------------------------------------------------------------------------------------
Net.on("close", function(_p)
	closeEditor(Text.UI.exitHome)
end)
Net.on("toast", function(p)
	Ui.toast(tostring(p.title or "") .. (if p.body and p.body ~= "" then (" · " .. tostring(p.body)) else ""))
end)
Net.on("badge", function(p)
	Ui.toast(string.format("🏅 뱃지 획득! %s %s", tostring(p.icon), tostring(p.name)), "gold")
end)
Net.on("goal", function(p)
	Ui.toast(string.format("🎯 목표 달성! %s %s · %s", tostring(p.icon), tostring(p.name), tostring(p.reward)), "gold")
end)
Net.on("liked", function(p)
	if Editor.isOpen() then
		Ui.toast(Text.fmt(Text.TOAST.likedOwner, tostring(p.by), tonumber(p.likes) or 0), "good")
	end
end)
Net.on("score", function(p)
	if Editor.isOpen() then
		Panels.score(p)
	end
end)
Net.on("finish", function(p)
	if Editor.isOpen() and p.cleared then
		Ui.toast("🏠 집 기본 테마가 적용돼서 이 방의 자유 배치 마감재를 해제했어요")
	end
end)

-------------------------------------------------------------------------------------------------
-- Input: K / gamepad D-pad up opens the editor at home
-------------------------------------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, gp)
	if gp or UserInputService:GetFocusedTextBox() then
		return
	end
	if input.KeyCode == Config.KEY_OPEN or (input.KeyCode == Enum.KeyCode.DPadUp and not Editor.isOpen()) then
		if Editor.isOpen() then
			if input.KeyCode == Config.KEY_OPEN then
				closeEditor(nil)
			end
		elseif home.role == "owner" and home.ownerId == player.UserId then
			openEditor()
		end
	end
end)

-------------------------------------------------------------------------------------------------
-- Boot: pill, effects, watchers
-------------------------------------------------------------------------------------------------
Visit.mount({
	openEditor = openEditor,
	photo = openPhoto,
	role = function(): (string?, number?)
		if not Net.ready() or not home.model then
			return nil, nil
		end
		if home.role == "owner" and home.ownerId == player.UserId then
			if interiorOpen() or Editor.isOpen() or Photo.isOpen() then
				return nil, nil
			end
			return "owner", home.ownerId
		elseif home.role == "guest" then
			if Photo.isOpen() then
				return nil, nil
			end
			return "guest", home.ownerId
		end
		return nil, nil
	end,
	model = function(): Model?
		return home.model
	end,
})

-- other scripts (phone app, tutorials) can open the editor: LocalPlayer.GwangalliDecorPlusOpen:Fire("editor" | "photo" | "close")
do
	local old = player:FindFirstChild("GwangalliDecorPlusOpen")
	if old then
		old:Destroy()
	end
	local ev = Instance.new("BindableEvent")
	ev.Name = "GwangalliDecorPlusOpen"
	ev.Event:Connect(function(what: any)
		if what == "editor" then
			task.spawn(openEditor)
		elseif what == "photo" then
			task.spawn(openPhoto)
		elseif what == "close" then
			closeEditor(nil)
		end
	end)
	ev.Parent = player
end

Effects.start(function(): (Model?, any?)
	return home.model, home.U
end)

player:GetAttributeChangedSignal("InHome"):Connect(function()
	refreshHome()
	if Editor.isOpen() and (home.role ~= "owner" or not home.model) then
		closeEditor(Text.UI.exitHome)
	end
end)
player.CharacterAdded:Connect(function()
	if Editor.isOpen() then
		closeEditor(nil)
	end
end)

task.spawn(function()
	while true do
		refreshHome()
		if Editor.isOpen() then
			if interiorOpen() then
				closeEditor(nil)
			elseif not home.model or not home.model.Parent then
				closeEditor(Text.UI.exitHome)
			elseif home.U and home.U ~= Editor.S.U then
				Editor.setUnit(home.U)
			end
		end
		Visit.update()
		task.wait(0.5)
	end
end)
