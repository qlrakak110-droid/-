-- GwangalliLive (client, every player): the client half of the live updates (docs/LIVE_UPDATES.md).
--   * mirrors the live config into THIS client's copies of the data tables (GwangalliGameplayShared,
--     ClubShared, GwangalliConfig), so phone apps / menus / NPC texts show the live prices at once;
--   * announcements: a toast when a new one arrives (and the active ones shortly after joining), plus
--     a slim non-interactive banner under the clock chip for announcements marked `banner`;
--   * happy hour / 테마 나이트 / 불꽃축제 notices, and replies to the admins' /live chat commands.
-- The server (GwangalliLiveOps) is the only writer; this script never sends anything.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local TAG = "[GwangalliLive] "
local player = Players.LocalPlayer

-- announcement windows are server unix times; the device clock may be off
local function serverNow(): number
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	return math.floor(if ok and type(t) == "number" then t else os.time())
end

local function requireOptional(name: string, wait: number): any
	local m = ReplicatedStorage:WaitForChild(name, wait)
	if not m or not m:IsA("ModuleScript") then
		return nil
	end
	local ok, res = pcall(require, m)
	if ok and type(res) == "table" then
		return res
	end
	warn(TAG .. name .. " failed to load: " .. tostring(res))
	return nil
end

local LC = requireOptional("GwangalliLiveConfig", 30)
if not LC then
	return
end
local folder = ReplicatedStorage:WaitForChild(LC.FOLDER, 60)
if not folder then
	return -- no live-ops server script in this place
end
local G = requireOptional("GwangalliGameplayShared", 10)
local Club = requireOptional("ClubShared", 10)
local Config = requireOptional("GwangalliConfig", 10)
local K = requireOptional("GwangalliUI", 10)
local Layout = requireOptional("GwangalliLayout", 10)

-------------------------------------------------------------------------------------------------
-- Mirror prices into this client's data tables
-------------------------------------------------------------------------------------------------
local applier = LC.newApplier({ G = G, Club = Club, Config = Config }, "client")
local function mirror()
	local ok, err = pcall(function()
		applier:apply(LC.current(), LC.happyHour())
	end)
	if not ok then
		warn(TAG .. "apply failed: " .. tostring(err))
	end
end

-------------------------------------------------------------------------------------------------
-- Toasts
-------------------------------------------------------------------------------------------------
local function toast(kind: string, title: string, body: string?, icon: string?, duration: number?)
	if K and K.toast then
		K.toast({ kind = kind, title = title, body = body, icon = icon, duration = duration or 6 })
		return
	end
	pcall(function()
		StarterGui:SetCore("SendNotification", { Title = title, Text = body or "", Duration = duration or 6 })
	end)
end

local seen: { [string]: boolean } = {}
local function showAnnouncement(a: any)
	if type(a) ~= "table" or type(a.text) ~= "string" or seen[a.id] then
		return
	end
	seen[a.id] = true
	local st = LC.ANNOUNCE_STYLES[a.style or "info"] or LC.ANNOUNCE_STYLES.info
	-- first line = title, the rest = body (toasts are two lines)
	local first, rest = string.match(a.text, "^([^\n]+)\n(.+)$")
	toast(st.kind, first or a.text, rest or st.label, st.icon, 8)
end

-------------------------------------------------------------------------------------------------
-- Banner (announcements with banner = true)
-------------------------------------------------------------------------------------------------
local banner: any = nil
local function buildBanner()
	if banner or not K then
		return
	end
	local pg = player:WaitForChild("PlayerGui", 30)
	if not pg then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "GwangalliLiveBanner"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	pcall(function()
		gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	end)
	gui.DisplayOrder = 4
	gui.Enabled = false
	local frame = K.frame(gui, { Name = "Banner", AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(320, 30), BackgroundTransparency = 0.18, BackgroundColor3 = K.Color.glass, ClipsDescendants = true })
	K.corner(frame, UDim.new(0.5, 0))
	K.stroke(frame, K.Color.gold, 1, 0.5)
	local label = K.text(frame, { Name = "Text", Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 1, 0), TextSize = K.Type.caption + 1, Font = K.Font.bold, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd })
	gui.Parent = pg
	banner = { gui = gui, frame = frame, label = label, list = {}, index = 1 }
	local function place()
		local y, w, cx = 60, 320, 0.5
		if Layout then
			local ok, r = pcall(Layout.rect, "topCenter")
			local okM, met = pcall(Layout.metrics)
			if ok and r then
				y = r.y + r.h + 6
				cx = r.x + r.w / 2
				local W = if okM and met then met.W else 800
				w = math.clamp(W - 32, 200, 420)
				cx = math.clamp(cx, w / 2 + 8, W - w / 2 - 8)
				frame.Position = UDim2.fromOffset(cx, y)
				frame.Size = UDim2.fromOffset(w, 30)
				return
			end
		end
		frame.Position = UDim2.new(cx, 0, 0, y)
		frame.Size = UDim2.fromOffset(w, 30)
	end
	place()
	if Layout and Layout.onChanged then
		pcall(Layout.onChanged, place)
	end
end

local function overlayUp(): boolean
	local pg = player:FindFirstChild("PlayerGui")
	if not pg then
		return false
	end
	for _, g in pg:GetChildren() do
		if g:IsA("ScreenGui") and g.Enabled and g:GetAttribute("HideGwangalliHUD") == true then
			return true
		end
	end
	return false
end

local function refreshBanner()
	local list = {}
	for _, a in LC.announcements(serverNow()) do
		if a.banner then
			table.insert(list, a)
		end
	end
	if #list == 0 then
		if banner then
			banner.gui.Enabled = false
			banner.list = {}
		end
		return
	end
	buildBanner()
	if not banner then
		return
	end
	banner.list = list
	banner.index = math.clamp(banner.index, 1, #list)
	local a = list[banner.index]
	local st = LC.ANNOUNCE_STYLES[a.style or "info"] or LC.ANNOUNCE_STYLES.info
	banner.label.Text = st.icon .. "  " .. (string.gsub(a.text, "\n", "  ·  "))
	banner.gui.Enabled = not overlayUp()
end

-------------------------------------------------------------------------------------------------
-- Change handling
-------------------------------------------------------------------------------------------------
local lastTheme = LC.get("events.club.themeNight")
local function onSnapshot()
	mirror()
	local theme = LC.get("events.club.themeNight")
	if theme ~= lastTheme then
		lastTheme = theme
		if theme ~= "none" and LC.THEME_LABELS[theme] then
			toast("club", "오늘 밤 CLUB OCEAN: " .. LC.THEME_LABELS[theme], "테마 나이트가 시작됐어요 🎶", "🎶", 7)
		end
	end
	refreshBanner()
end

local remote = folder:WaitForChild(LC.REMOTE_CHANGED, 30)
if remote and remote:IsA("RemoteEvent") then
	remote.OnClientEvent:Connect(function(p: any)
		if type(p) ~= "table" then
			return
		end
		if type(p.reply) == "string" then
			toast(if type(p.kind) == "string" then p.kind else "info", "라이브 설정", p.reply, "⚙️", 8)
			return
		end
		if type(p.announce) == "table" then
			for _, a in p.announce do
				showAnnouncement(a)
			end
		end
		if p.happy == true then
			local m = LC.get("events.happyHour.multiplier")
			toast("club", "해피아워 시작! 🍾", string.format("클럽 입장료·테이블·보틀 %d%% 할인", math.floor((1 - m) * 100 + 0.5)), "🍾", 7)
		elseif p.happy == false then
			toast("club", "해피아워가 끝났어요", "가격이 원래대로 돌아왔어요", "🕘", 5)
		end
	end)
end

LC.onChanged(function()
	onSnapshot()
end)
mirror()

-- active announcements shortly after joining (the HUD's toaster needs a moment)
task.delay(6, function()
	for _, a in LC.announcements(serverNow()) do
		showAnnouncement(a)
		task.wait(1.5)
	end
	refreshBanner()
end)

-- banner rotation / expiry / overlays (cheap: once every 2 s)
task.spawn(function()
	local tick = 0
	while true do
		task.wait(2)
		tick += 1
		if banner and #banner.list > 0 then
			if tick % 4 == 0 then
				banner.index = banner.index % #banner.list + 1
			end
			refreshBanner()
		elseif tick % 15 == 0 then
			refreshBanner() -- scheduled announcements that start later
		end
	end
end)
