-- TREND FISHING - Roblox Studio client UI
-- Put this LocalScript in StarterPlayer > StarterPlayerScripts as TrendFishingClient.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("TrendFishingRemotes")

local StartFishing = remotes:WaitForChild("StartFishing")
local FinishFishing = remotes:WaitForChild("FinishFishing")
local UpgradeRod = remotes:WaitForChild("UpgradeRod")
local SellFish = remotes:WaitForChild("SellFish")
local DisplayFish = remotes:WaitForChild("DisplayFish")
local StateUpdate = remotes:WaitForChild("StateUpdate")
local Notice = remotes:WaitForChild("Notice")

local state = {Coins=80,Rod=1,Inventory={},Displayed={},Income=0}
local fishingToken = nil
local waiting = false

local gui = Instance.new("ScreenGui")
gui.Name = "TrendFishingUI"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local function make(class,parent,props)
    local obj=Instance.new(class)
    for k,v in pairs(props or {}) do obj[k]=v end
    obj.Parent=parent
    return obj
end

local panel = make("Frame",gui,{
    Name="Panel",AnchorPoint=Vector2.new(0,0),Position=UDim2.new(0,12,0,85),
    Size=UDim2.new(0,300,0,390),BackgroundColor3=Color3.fromRGB(9,25,43),
    BackgroundTransparency=0.08,BorderSizePixel=0
})
make("UICorner",panel,{CornerRadius=UDim.new(0,14)})
make("UIStroke",panel,{Color=Color3.fromRGB(50,174,220),Thickness=2})
make("UIPadding",panel,{PaddingTop=UDim.new(0,12),PaddingLeft=UDim.new(0,12),PaddingRight=UDim.new(0,12)})

local title = make("TextLabel",panel,{
    Size=UDim2.new(1,-42,0,35),BackgroundTransparency=1,
    Text="🎣 TREND FISHING",TextColor3=Color3.fromRGB(92,225,255),
    Font=Enum.Font.GothamBlack,TextSize=20,TextXAlignment=Enum.TextXAlignment.Left
})
local collapse = make("TextButton",panel,{
    Position=UDim2.new(1,-36,0,0),Size=UDim2.new(0,34,0,32),
    BackgroundColor3=Color3.fromRGB(30,65,90),Text="—",
    TextColor3=Color3.new(1,1,1),Font=Enum.Font.GothamBlack,TextSize=20
})
make("UICorner",collapse,{CornerRadius=UDim.new(0,8)})

local status = make("TextLabel",panel,{
    Position=UDim2.new(0,0,0,42),Size=UDim2.new(1,0,0,50),
    BackgroundColor3=Color3.fromRGB(18,46,69),Text="낚시할 준비 완료!",
    TextColor3=Color3.new(1,1,1),TextWrapped=true,Font=Enum.Font.Gotham,TextSize=14
})
make("UICorner",status,{CornerRadius=UDim.new(0,8)})

local statsLabel = make("TextLabel",panel,{
    Position=UDim2.new(0,0,0,98),Size=UDim2.new(1,0,0,48),
    BackgroundTransparency=1,TextColor3=Color3.fromRGB(255,225,128),
    Text="코인: 80 | 낚싯대 Lv.1",TextWrapped=true,Font=Enum.Font.GothamBold,TextSize=16
})

local function button(text,y,color)
    local b=make("TextButton",panel,{
        Position=UDim2.new(0,0,0,y),Size=UDim2.new(1,0,0,39),
        BackgroundColor3=color,Text=text,TextColor3=Color3.new(1,1,1),TextWrapped=true,
        Font=Enum.Font.GothamBold,TextSize=15,AutoButtonColor=true
    })
    make("UICorner",b,{CornerRadius=UDim.new(0,9)})
    return b
end

local cast = button("🎣 낚시 시작",153,Color3.fromRGB(0,135,190))
local upgrade = button("⬆️ 낚싯대 강화",199,Color3.fromRGB(145,91,25))
local sell = button("🐟 물고기 전부 판매",245,Color3.fromRGB(32,125,78))
local display = button("🏡 첫 번째 물고기 전시",291,Color3.fromRGB(107,65,166))

local inventoryLabel = make("TextLabel",panel,{
    Position=UDim2.new(0,0,0,339),Size=UDim2.new(1,0,0,43),
    BackgroundTransparency=1,Text="보관함: 비어 있음",
    TextColor3=Color3.fromRGB(220,235,250),TextWrapped=true,
    Font=Enum.Font.Gotham,TextSize=13
})

-- Responsive positioning for phone/tablet and desktop.
-- The Roblox mobile thumbstick/jump button remain visible outside this panel.
local collapsed = false
local contentObjects = {status, statsLabel, cast, upgrade, sell, display, inventoryLabel}
local function applyResponsiveLayout()
    local camera = workspace.CurrentCamera
    if not camera then return end
    local view = camera.ViewportSize
    local phone = UserInputService.TouchEnabled and view.X < 800
    if phone then
        panel.Size = UDim2.new(0, math.max(260, math.min(300, view.X - 20)), 0, collapsed and 46 or 390)
        panel.Position = UDim2.new(0, 10, 0, 72)
        panel.BackgroundTransparency = 0.04
        title.TextSize = 18
    else
        panel.Size = UDim2.new(0, 300, 0, collapsed and 46 or 390)
        panel.Position = UDim2.new(0, 12, 0, 85)
        title.TextSize = 20
    end
    for _,obj in ipairs(contentObjects) do
        obj.Visible = not collapsed
    end
    collapse.Text = collapsed and "+" or "—"
end

collapse.Activated:Connect(function()
    collapsed = not collapsed
    applyResponsiveLayout()
end)

local function hookCamera()
    local camera = workspace.CurrentCamera
    if camera then
        camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyResponsiveLayout)
    end
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    hookCamera()
    applyResponsiveLayout()
end)
hookCamera()
applyResponsiveLayout()

cast.Activated:Connect(function()
    if waiting then return end
    waiting=true
    cast.Text="⏳ 입질 기다리는 중..."
    StartFishing:FireServer()
end)
upgrade.Activated:Connect(function() UpgradeRod:FireServer() end)
sell.Activated:Connect(function() SellFish:FireServer() end)
display.Activated:Connect(function()
    if #state.Inventory>0 then
        DisplayFish:FireServer(1)
    else
        status.Text="전시할 물고기가 없어. 먼저 낚시해 봐!"
    end
end)

StateUpdate.OnClientEvent:Connect(function(data)
    if type(data)~="table" then return end
    state=data
    statsLabel.Text=("🪙 코인: %d\n🎣 낚싯대 Lv.%d | 🏡 초당 수익: %d"):format(state.Coins or 0,state.Rod or 1,state.Income or 0)
    local names={}
    for i,f in ipairs(state.Inventory or {}) do
        if i<=4 then table.insert(names,f.Name.."("..f.Rarity..")") end
    end
    if #state.Inventory>4 then table.insert(names,"외 "..(#state.Inventory-4).."마리") end
    inventoryLabel.Text=#names>0 and ("보관함: "..table.concat(names,", ")) or "보관함: 비어 있음"
    upgrade.Text=(state.Rod or 1)>=10 and "최고 레벨 달성!" or ("⬆️ 낚싯대 강화 ("..(100*2^((state.Rod or 1)-1)).." 코인)")
    upgrade.Active=(state.Rod or 1)<10
    upgrade.AutoButtonColor=(state.Rod or 1)<10
end)

Notice.OnClientEvent:Connect(function(info)
    if type(info)~="table" then return end
    if info.Kind=="FishingStarted" then
        fishingToken=info.Token
        status.Text="찌를 던졌어! 입질을 기다려..."
        task.delay(info.Duration or 3,function()
            if waiting and fishingToken then
                FinishFishing:FireServer(fishingToken)
                status.Text="물고기를 끌어올리는 중..."
            end
        end)
    elseif info.Kind=="Caught" then
        waiting=false;fishingToken=nil
        cast.Text="🎣 낚시 시작"
        local f=info.Item or {}
        status.Text=("🐟 %s 획득! [%s] · 판매가 %s 코인"):format(f.Name or "물고기",f.Rarity or "일반",tostring(f.Value or 0))
    elseif info.Kind=="Error" or info.Kind=="Info" then
        status.Text=info.Text or ""
        if info.Kind=="Error" and string.find(status.Text,"낚시") then
            waiting=false;fishingToken=nil;cast.Text="🎣 낚시 시작"
        end
    end
end)

-- If the server rejects/loses a fishing request, unlock the button after a timeout.
task.spawn(function()
    while gui.Parent do
        task.wait(8)
        if waiting and not fishingToken then
            waiting=false
            cast.Text="🎣 낚시 시작"
        end
    end
end)
