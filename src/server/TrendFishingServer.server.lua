-- TREND FISHING - Roblox Studio server script
-- Put this Script in ServerScriptService as TrendFishingServer.
-- DataStore saving works in a published game with API access enabled.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local SAVE_STORE = DataStoreService:GetDataStore("TrendFishing_v1")
local START_COINS = 80
local MAX_ROD_LEVEL = 10
local MAX_DISPLAY = 8
local FISHING_SECONDS = 3

local FISH = {
    {Name="동네 붕어", Rarity="일반", Weight=540, Value=12, Income=1, Color=Color3.fromRGB(220,174,105)},
    {Name="은빛 피라미", Rarity="일반", Weight=300, Value=16, Income=1, Color=Color3.fromRGB(220,235,245)},
    {Name="무지개 송어", Rarity="희귀", Weight=100, Value=45, Income=2, Color=Color3.fromRGB(70,205,235)},
    {Name="푸른 잉어", Rarity="희귀", Weight=70, Value=62, Income=3, Color=Color3.fromRGB(65,130,255)},
    {Name="보라 해파리", Rarity="에픽", Weight=35, Value=120, Income=5, Color=Color3.fromRGB(185,100,255)},
    {Name="달빛 장어", Rarity="에픽", Weight=22, Value=160, Income=7, Color=Color3.fromRGB(135,145,255)},
    {Name="황금 잉어", Rarity="전설", Weight=9, Value=350, Income=15, Color=Color3.fromRGB(255,190,40)},
    {Name="왕관 연어", Rarity="전설", Weight=5, Value=500, Income=20, Color=Color3.fromRGB(255,125,70)},
    {Name="유성 고래", Rarity="신화", Weight=1.5, Value=1500, Income=60, Color=Color3.fromRGB(255,80,145)},
    {Name="차원 아귀", Rarity="신화", Weight=0.8, Value=2200, Income=90, Color=Color3.fromRGB(255,70,220)},
}

local function remote(name)
    local folder = ReplicatedStorage:FindFirstChild("TrendFishingRemotes")
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = "TrendFishingRemotes"
        folder.Parent = ReplicatedStorage
    end
    local r = folder:FindFirstChild(name)
    if not r then
        r = Instance.new("RemoteEvent")
        r.Name = name
        r.Parent = folder
    end
    return r
end

local StartFishing = remote("StartFishing")
local FinishFishing = remote("FinishFishing")
local UpgradeRod = remote("UpgradeRod")
local SellFish = remote("SellFish")
local DisplayFish = remote("DisplayFish")
local StateUpdate = remote("StateUpdate")
local Notice = remote("Notice")

local profiles = {}
local fishing = {}
local baseModels = {}
local mapFolder

local function makePart(parent, name, size, cf, color, material)
    local p = Instance.new("Part")
    p.Name = name
    p.Size = size
    p.CFrame = cf
    p.Anchored = true
    p.Color = color
    p.Material = material or Enum.Material.SmoothPlastic
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    p.Parent = parent
    return p
end

local function makeSign(parent, text, position, color)
    local p = makePart(parent, text.." Sign", Vector3.new(14,1,1), CFrame.new(position), color, Enum.Material.Neon)
    p.CanCollide = false
    local gui = Instance.new("BillboardGui")
    gui.Size = UDim2.fromOffset(250,55)
    gui.StudsOffset = Vector3.new(0,2,0)
    gui.AlwaysOnTop = true
    gui.Parent = p
    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1,1)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextScaled = true
    label.Font = Enum.Font.GothamBlack
    label.TextColor3 = Color3.new(1,1,1)
    label.Parent = gui
end

local function buildMap()
    local old = workspace:FindFirstChild("TREND_FISHING_MAP")
    if old then old:Destroy() end
    mapFolder = Instance.new("Folder")
    mapFolder.Name = "TREND_FISHING_MAP"
    mapFolder.Parent = workspace

    makePart(mapFolder,"Island",Vector3.new(150,5,150),CFrame.new(0,-3,0),Color3.fromRGB(82,170,78),Enum.Material.Grass)
    makePart(mapFolder,"Pond",Vector3.new(48,1,48),CFrame.new(0,0,0),Color3.fromRGB(35,160,225),Enum.Material.Glass).Transparency = 0.18
    makeSign(mapFolder,"TREND FISHING",Vector3.new(0,7,-30),Color3.fromRGB(0,190,255))
    makePart(mapFolder,"Rod Shop",Vector3.new(16,8,12),CFrame.new(-48,2,0),Color3.fromRGB(190,75,55),Enum.Material.Brick)
    makeSign(mapFolder,"낚싯대 상점",Vector3.new(-48,8,0),Color3.fromRGB(255,180,35))
    makePart(mapFolder,"Upgrade Platform",Vector3.new(18,1,14),CFrame.new(0,0.5,54),Color3.fromRGB(115,65,190),Enum.Material.Neon)
    makeSign(mapFolder,"업그레이드",Vector3.new(0,4,54),Color3.fromRGB(180,90,255))

    for i=1,8 do
        local a = math.pi*2*(i-1)/8
        local x,z = math.cos(a)*57, math.sin(a)*57
        makePart(mapFolder,"Player Base "..i,Vector3.new(23,1,19),CFrame.new(x,0.5,z),Color3.fromRGB(95,195,105),Enum.Material.Grass)
        makeSign(mapFolder,"기지 "..i,Vector3.new(x,4,z),Color3.fromRGB(25,200,255))
        local dockX,dockZ = math.cos(a)*28,math.sin(a)*28
        local dock = makePart(mapFolder,"Dock "..i,Vector3.new(7,1,14),CFrame.new(dockX,0.6,dockZ)*CFrame.Angles(0,-a,0),Color3.fromRGB(130,82,48),Enum.Material.WoodPlanks)
    end
end

local function fresh()
    return {Coins=START_COINS, Rod=1, Inventory={}, Displayed={}}
end

local function income(data)
    local n=0
    for _,f in ipairs(data.Displayed) do n += tonumber(f.Income) or 0 end
    return n
end

local function stats(player,data)
    local ls=player:FindFirstChild("leaderstats")
    if not ls then ls=Instance.new("Folder");ls.Name="leaderstats";ls.Parent=player end
    local coins=ls:FindFirstChild("Coins") or Instance.new("IntValue")
    coins.Name="Coins";coins.Value=data.Coins;coins.Parent=ls
    local rod=ls:FindFirstChild("RodLevel") or Instance.new("IntValue")
    rod.Name="RodLevel";rod.Value=data.Rod;rod.Parent=ls
end

local function send(player)
    local d=profiles[player]
    if not d then return end
    StateUpdate:FireClient(player,{
        Coins=d.Coins, Rod=d.Rod, Inventory=d.Inventory, Displayed=d.Displayed,
        Income=income(d), MaxRod=MAX_ROD_LEVEL
    })
end

local function renderDisplays(player)
    local d=profiles[player]
    if not d then return end
    if baseModels[player] then baseModels[player]:Destroy() end
    local folder=Instance.new("Folder")
    folder.Name="Displays_"..player.UserId
    folder.Parent=workspace
    baseModels[player]=folder

    -- Each player's display stand is placed around the map edge.
    local all={}
    for _,p in ipairs(Players:GetPlayers()) do table.insert(all,p) end
    table.sort(all,function(a,b) return a.UserId<b.UserId end)
    local index=1
    for i,p in ipairs(all) do if p==player then index=i end end
    local angle=math.pi*2*(index-1)/8
    local center=Vector3.new(math.cos(angle)*57,1,math.sin(angle)*57)

    for i,f in ipairs(d.Displayed) do
        local col=(i-1)%4
        local row=math.floor((i-1)/4)
        local pos=center+Vector3.new(-7+col*4.5,2,-5+row*4.5)
        local displayColor = Color3.fromRGB(255,205,65)
        for _, fishDef in ipairs(FISH) do
            if fishDef.Name == f.Name then displayColor = fishDef.Color; break end
        end
        local part=makePart(folder,f.Name,Vector3.new(2,2,2),CFrame.new(pos),displayColor,Enum.Material.Neon)
        local gui=Instance.new("BillboardGui")
        gui.Size=UDim2.fromOffset(140,42);gui.StudsOffset=Vector3.new(0,1.8,0);gui.AlwaysOnTop=true;gui.Parent=part
        local label=Instance.new("TextLabel")
        label.Size=UDim2.fromScale(1,1);label.BackgroundTransparency=1
        label.Text=f.Name.."\n+"..tostring(f.Income).."/초"
        label.TextColor3=Color3.new(1,1,1);label.TextScaled=true;label.Font=Enum.Font.GothamBold;label.Parent=gui
    end
end

local function load(player)
    local data=fresh()
    local ok,saved=pcall(function() return SAVE_STORE:GetAsync("u_"..player.UserId) end)
    if ok and type(saved)=="table" then
        data.Coins=math.max(0,tonumber(saved.Coins) or START_COINS)
        data.Rod=math.clamp(tonumber(saved.Rod) or 1,1,MAX_ROD_LEVEL)
        if type(saved.Inventory)=="table" then data.Inventory=saved.Inventory end
        if type(saved.Displayed)=="table" then data.Displayed=saved.Displayed end
    elseif not ok then
        warn("TREND FISHING load failed for",player.Name,saved)
    end
    profiles[player]=data
    stats(player,data)
    renderDisplays(player)
    send(player)
end

local function save(player)
    local d=profiles[player]
    if not d then return end
    local snapshot={Coins=d.Coins,Rod=d.Rod,Inventory=d.Inventory,Displayed=d.Displayed}
    local ok,err=pcall(function()
        SAVE_STORE:UpdateAsync("u_"..player.UserId,function() return snapshot end)
    end)
    if not ok then warn("TREND FISHING save failed for",player.Name,err) end
end

local function chooseFish(rod)
    local total=0
    local weights={}
    for i,f in ipairs(FISH) do
        local w=f.Weight
        if f.Rarity=="신화" then w*=rod
        elseif f.Rarity=="전설" then w*=1+(rod-1)*0.45
        elseif f.Rarity=="에픽" then w*=1+(rod-1)*0.2 end
        weights[i]=w;total+=w
    end
    local roll=math.random()*total
    for i,f in ipairs(FISH) do roll-=weights[i];if roll<=0 then return f end end
    return FISH[1]
end

buildMap()

StartFishing.OnServerEvent:Connect(function(player)
    if not profiles[player] or fishing[player] then return end
    fishing[player]={started=os.clock(),token=tick()}
    Notice:FireClient(player,{Kind="FishingStarted",Duration=FISHING_SECONDS,Token=fishing[player].token})
end)

FinishFishing.OnServerEvent:Connect(function(player,token)
    local d=profiles[player]
    local s=fishing[player]
    if not d or not s or token~=s.token then return end
    if os.clock()-s.started<FISHING_SECONDS-0.15 then return end
    fishing[player]=nil
    local f=chooseFish(d.Rod)
    -- Store only DataStore-safe primitive fields; Color3 is looked up from FISH when displayed.
    local item={Name=f.Name,Rarity=f.Rarity,Value=f.Value,Income=f.Income}
    table.insert(d.Inventory,item)
    stats(player,d);send(player)
    Notice:FireClient(player,{Kind="Caught",Item={Name=item.Name,Rarity=item.Rarity,Value=item.Value}})
end)

UpgradeRod.OnServerEvent:Connect(function(player)
    local d=profiles[player];if not d then return end
    local nextRod=d.Rod+1
    if nextRod>MAX_ROD_LEVEL then Notice:FireClient(player,{Kind="Error",Text="이미 최고 레벨 낚싯대야!"});return end
    local cost=100*2^(d.Rod-1)
    if d.Coins<cost then Notice:FireClient(player,{Kind="Error",Text="코인이 부족해! 필요: "..cost});return end
    d.Coins-=cost;d.Rod=nextRod
    stats(player,d);send(player)
    Notice:FireClient(player,{Kind="Info",Text="낚싯대 강화 성공! Lv."..d.Rod})
end)

SellFish.OnServerEvent:Connect(function(player)
    local d=profiles[player];if not d then return end
    if #d.Inventory==0 then Notice:FireClient(player,{Kind="Error",Text="판매할 물고기가 없어."});return end
    local total=0
    for _,f in ipairs(d.Inventory) do total+=math.max(0,tonumber(f.Value) or 0) end
    d.Coins+=total;d.Inventory={}
    stats(player,d);send(player)
    Notice:FireClient(player,{Kind="Info",Text="물고기를 판매했어! +"..total.." 코인"})
end)

DisplayFish.OnServerEvent:Connect(function(player,index)
    local d=profiles[player]
    if not d or type(index)~="number" or index%1~=0 or index<1 or index>#d.Inventory then return end
    if #d.Displayed>=MAX_DISPLAY then Notice:FireClient(player,{Kind="Error",Text="전시 공간이 가득 찼어."});return end
    local f=table.remove(d.Inventory,index)
    table.insert(d.Displayed,f)
    renderDisplays(player);send(player)
    Notice:FireClient(player,{Kind="Info",Text=f.Name.." 전시 완료! 자동 수익이 시작돼."})
end)

task.spawn(function()
    while true do
        task.wait(1)
        for player,d in pairs(profiles) do
            if player.Parent and income(d)>0 then
                d.Coins+=income(d)
                stats(player,d);send(player)
            end
        end
    end
end)

Players.PlayerAdded:Connect(function(p) task.spawn(load,p) end)
Players.PlayerRemoving:Connect(function(p)
    save(p)
    fishing[p]=nil
    profiles[p]=nil
    if baseModels[p] then baseModels[p]:Destroy();baseModels[p]=nil end
end)
for _,p in ipairs(Players:GetPlayers()) do task.spawn(load,p) end

game:BindToClose(function()
    for _,p in ipairs(Players:GetPlayers()) do save(p) end
end)
