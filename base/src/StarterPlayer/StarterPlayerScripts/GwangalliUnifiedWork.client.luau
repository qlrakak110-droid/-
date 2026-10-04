-- Mobile work UI for the supplied server-authoritative cafe simulation.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local remotes = RS:WaitForChild("GwangalliRemotes", 60)
local remote = remotes and remotes:WaitForChild("Work", 60)
if not remote then return end
local gui = Instance.new("ScreenGui")
gui.Name = "GwangalliUnifiedWork"; gui.ResetOnSpawn = false; gui.DisplayOrder = 24
gui.Parent = player:WaitForChild("PlayerGui")
local toggle = Instance.new("TextButton")
toggle.Text = "☕ 알바"; toggle.Size = UDim2.fromOffset(92,44)
toggle.AnchorPoint = Vector2.new(1,0); toggle.Position = UDim2.new(1,-12,0,154)
toggle.BackgroundColor3 = Color3.fromRGB(34,46,38); toggle.TextColor3 = Color3.new(1,1,1)
toggle.TextSize = 16; toggle.Parent = gui
local frame = Instance.new("Frame")
frame.Size = UDim2.new(0.46,0,0.75,0); frame.Position = UDim2.new(0.52,0,0.14,0)
frame.BackgroundColor3 = Color3.fromRGB(18,25,31); frame.Visible = false; frame.Parent = gui
local limit = Instance.new("UISizeConstraint"); limit.MinSize = Vector2.new(250,180); limit.MaxSize = Vector2.new(430,600); limit.Parent = frame
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1,-54,0,44); title.Position = UDim2.fromOffset(10,0)
title.Text = "알바 · 출근부터 정산까지"; title.TextSize=15; title.TextColor3=Color3.new(1,1,1)
title.BackgroundTransparency=1; title.Parent=frame
local close = Instance.new("TextButton"); close.Text="×"; close.TextSize=25
close.Size=UDim2.fromOffset(44,44); close.Position=UDim2.new(1,-44,0,0)
close.BackgroundTransparency=1; close.TextColor3=Color3.new(1,1,1); close.Parent=frame
local scroll = Instance.new("ScrollingFrame")
scroll.Size=UDim2.new(1,-16,1,-52); scroll.Position=UDim2.fromOffset(8,44)
scroll.BackgroundTransparency=1; scroll.BorderSizePixel=0; scroll.ScrollBarThickness=4
scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y; scroll.CanvasSize=UDim2.new(); scroll.Parent=frame
local layout = Instance.new("UIListLayout"); layout.Padding=UDim.new(0,7); layout.Parent=scroll
local busyUntil=0; local lastState=nil; local board=nil
local function send(p)
 if os.clock()<busyUntil then return end
 busyUntil=os.clock()+0.15; remote:FireServer(p)
end
local function clear()
 for _,c in scroll:GetChildren() do if c~=layout then c:Destroy() end end
end
local function row(text,callback,enabled)
 local o=Instance.new(callback and "TextButton" or "TextLabel")
 o.Size=UDim2.new(1,-6,0,48); o.Text=text; o.TextSize=14; o.TextWrapped=true
 o.TextColor3=enabled==false and Color3.fromRGB(120,125,130) or Color3.fromRGB(235,240,245)
 o.BackgroundColor3=Color3.fromRGB(32,43,52); o.BorderSizePixel=0; o.Parent=scroll
 local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,8); c.Parent=o
 if callback and enabled~=false then o.Activated:Connect(callback) end
 return o
end
local function showBoard(p)
 clear(); title.Text="알바 공고 · 근무 선택"
 for _,job in p.postings or {} do
  local j=job
  if j.ready then
   row((j.icon or "").." "..j.title.." · "..j.place)
   if not j.applied then row("지원하기",function()send({op="apply",job=j.jobId})end,j.canApply)
   else for _,length in j.lengths or {} do
    local l=length
    row(l.label.." · 출근",function()send({op="start",job=j.jobId,length=l.id})end)
   end end
  end
 end
 row("편의점·배달 등 다른 알바는 기존 휴대폰의 알바 앱에서 시작해요.")
end
local function showState(p)
 clear();title.Text=(p.icon or "☕").." "..(p.title or "근무")
 row(p.phaseLabel or "가게로 이동해서 출근 체크")
 if p.timeLeft then row("남은 시간 "..p.timeLeft.."초 · 예상 정산 "..tostring(p.estimate or 0).."원")end
 if p.hint and p.hint.text then row(p.hint.text)end
 for _,held in p.held or {} do row("들고 있는 물건 · "..tostring(held.label or held.name or held.kind or "물건"))end
 for _,order in p.orders or {} do
  local o=order
  row("주문 "..tostring(o.number or o.id).." · "..tostring(o.name or o.customerName or "손님"),function()send({op="focus",order=o.id})end)
 end
 for _,station in p.near or {} do
  local st=station; row("▸ "..st.label)
  for _,action in st.actions or {} do
   local a=action
   row((a.icon or "").." "..a.label,function()send({op="act",station=st.id,action=a.id,arg=a.arg})end,a.enabled)
  end
 end
 if #(p.near or {})==0 then row("안내된 기구 가까이 이동하면 작업 버튼이 나타나요.")end
 row(p.state=="commute" and "출근 취소" or "퇴근 및 정산",function()send({op=p.state=="commute" and "cancel" or "end",reason=p.canFinish and "done" or "early"})end)
end
toggle.Activated:Connect(function()
 frame.Visible=not frame.Visible
 if frame.Visible then if lastState then showState(lastState)else send({op="board"})end end
end)
close.Activated:Connect(function()frame.Visible=false end)
remote.OnClientEvent:Connect(function(p)
 if type(p)~="table" then return end
 if p.op=="board" then board=p;if frame.Visible and not lastState then showBoard(p)end
 elseif p.op=="state" then lastState=p;if frame.Visible then showState(p)end
 elseif p.op=="settle" then lastState=nil;frame.Visible=true;clear();title.Text="근무 정산";row("오늘 급여 "..tostring(p.total or p.pay or 0).."원");row("공고 다시 보기",function()send({op="board"})end)
 elseif p.op=="closed" then lastState=nil;send({op="board"})
 elseif p.op=="toast" then toggle.Text=tostring(p.text or "☕ 알바");task.delay(3,function()toggle.Text="☕ 알바"end)
 end
end)
