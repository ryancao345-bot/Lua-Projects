-- Anime Brawlers Simulator | Proximity Auto Farm + Auto Click
-- Standalone test build. Run again to replace the previous instance.
local Players = game:GetService('Players')
local RS = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')
local UIS = game:GetService('UserInputService')
local TweenService = game:GetService('TweenService')
local player = Players.LocalPlayer
local remotes = RS:WaitForChild('GameRemotes')
local action = remotes:WaitForChild('Action')
local npcFolder = workspace:WaitForChild('LiveNPCs')
local env = (getgenv and getgenv()) or _G
if env.ABSHubCleanup then pcall(env.ABSHubCleanup) end
local alive, farm, click = true, false, false
local radius, clickInterval = 30, 0.06
local selected, lastAttack = nil, 0
local targetWasDead = false
local lastTargetHealth = nil
local connections = {}
local function bind(signal, fn)
    local c = signal:Connect(fn)
    table.insert(connections,c)
    return c
end
local function root()
    local char = player.Character
    return char and char:FindFirstChild('HumanoidRootPart')
end
local function npcPart(npc)
    if npc:IsA('Model') then
        return npc.PrimaryPart or npc:FindFirstChild('HumanoidRootPart') or npc:FindFirstChildWhichIsA('BasePart',true)
    elseif npc:IsA('BasePart') then
        return npc
    end
end
local function valid(npc)
    if not npc or not npc.Parent or not npc:IsDescendantOf(npcFolder) then return false end
    local part = npcPart(npc)
    if not part then return false end
    local hum = npc:IsA('Model') and npc:FindFirstChildOfClass('Humanoid')
    if hum and hum.Health <= 0 then return false end
    -- Some NPCs expose health as a numeric attribute or Value object instead of Humanoid.
    local health = npc:GetAttribute('Health') or npc:GetAttribute('HP')
    if type(health)=='number' and health <= 0 then return false end
    for _,name in ipairs({'Health','HP'}) do
        local obj=npc:FindFirstChild(name)
        if obj and obj:IsA('NumberValue') and obj.Value<=0 then return false end
    end
    return true, part
end
local gui = Instance.new('ScreenGui')
gui.Name='AnimeBrawlersHub'
gui.ResetOnSpawn=false
gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
gui.Parent=player:WaitForChild('PlayerGui')
local panel=Instance.new('Frame')
panel.Size=UDim2.fromOffset(335,265)
panel.Position=UDim2.new(0.5,-167,0.5,-132)
panel.BackgroundColor3=Color3.fromRGB(21,24,34)
panel.BorderSizePixel=0
panel.Parent=gui
Instance.new('UICorner',panel).CornerRadius=UDim.new(0,12)
local stroke=Instance.new('UIStroke',panel)
stroke.Color=Color3.fromRGB(64,79,109)
stroke.Transparency=.35
local title=Instance.new('TextLabel')
title.Size=UDim2.new(1,-55,0,42)
title.Position=UDim2.fromOffset(16,2)
title.BackgroundTransparency=1
title.Text='ANIME BRAWLERS HUB  |  V1.3'
title.TextColor3=Color3.fromRGB(235,240,255)
title.Font=Enum.Font.GothamBold
title.TextSize=14
title.TextXAlignment=Enum.TextXAlignment.Left
title.Parent=panel
local function button(text,y)
    local b=Instance.new('TextButton')
    b.Size=UDim2.new(1,-30,0,38)
    b.Position=UDim2.fromOffset(15,y)
    b.BackgroundColor3=Color3.fromRGB(37,44,59)
    b.Text=text
    b.TextColor3=Color3.fromRGB(234,240,255)
    b.Font=Enum.Font.GothamMedium
    b.TextSize=13
    b.AutoButtonColor=false
    b.Parent=panel
    Instance.new('UICorner',b).CornerRadius=UDim.new(0,8)
    return b
end
local farmBtn=button('Proximity Auto Farm: OFF',51)
local clickBtn=button('Auto Click (DPC): OFF',95)
local radiusBtn=button('Radius: 30 studs  (+10)',139)
local status=Instance.new('TextLabel')
status.Position=UDim2.fromOffset(16,189)
status.Size=UDim2.new(1,-32,0,45)
status.BackgroundTransparency=1
status.Text='Ready. Enable Auto Farm near enemies.'
status.TextColor3=Color3.fromRGB(158,177,207)
status.TextSize=12
status.Font=Enum.Font.Gotham
status.TextWrapped=true
status.TextXAlignment=Enum.TextXAlignment.Left
status.Parent=panel
local hint=Instance.new('TextLabel')
hint.Position=UDim2.fromOffset(16,237)
hint.Size=UDim2.new(1,-32,0,18)
hint.BackgroundTransparency=1
hint.Text='Right Ctrl: hide/show  •  Drag title to move'
hint.TextColor3=Color3.fromRGB(120,139,169)
hint.TextSize=10
hint.Font=Enum.Font.Gotham
hint.Parent=panel
local close=Instance.new('TextButton')
close.Position=UDim2.new(1,-40,0,8)
close.Size=UDim2.fromOffset(29,28)
close.Text='×'
close.TextSize=19
close.Font=Enum.Font.GothamBold
close.TextColor3=Color3.fromRGB(225,232,245)
close.BackgroundColor3=Color3.fromRGB(48,56,73)
close.Parent=panel
Instance.new('UICorner',close).CornerRadius=UDim.new(0,7)
-- Bright red, always-visible outline. Handle adornments render through terrain/parts.
local ringAnchor=Instance.new('Part')
ringAnchor.Name='ABS_RadiusAnchor'
ringAnchor.Size=Vector3.new(.2,.2,.2)
ringAnchor.Anchored=true
ringAnchor.CanCollide=false
ringAnchor.CanTouch=false
ringAnchor.CanQuery=false
ringAnchor.Transparency=1
ringAnchor.Parent=workspace
local ringSegments={}
local SEGMENTS=64
for i=1,SEGMENTS do
    local adorn=Instance.new('BoxHandleAdornment')
    adorn.Name='RadiusSegment_'..i
    adorn.Adornee=ringAnchor
    adorn.AlwaysOnTop=true
    adorn.ZIndex=10
    adorn.Color3=Color3.fromRGB(255,35,45)
    adorn.Transparency=0
    adorn.Parent=gui
    ringSegments[i]=adorn
end
local function updateRing()
    local arc=2*math.pi*radius/SEGMENTS
    for i,adorn in ipairs(ringSegments) do
        local angle=(i-.5)*2*math.pi/SEGMENTS
        adorn.Size=Vector3.new(arc+.12,.22,.32)
        adorn.CFrame=CFrame.new(radius*math.cos(angle),0,radius*math.sin(angle))
            * CFrame.Angles(0,-angle-math.pi/2,0)
        adorn.Visible=farm
    end
end
updateRing()
local function setButton(b,on,label)
    b.Text=label..(on and ': ON' or ': OFF')
    TweenService:Create(b,TweenInfo.new(.18),{BackgroundColor3=on and Color3.fromRGB(36,99,102) or Color3.fromRGB(37,44,59)}):Play()
end
bind(farmBtn.MouseButton1Click,function()
    farm=not farm
    selected=nil
    lastAttack=0
    targetWasDead=false
    lastTargetHealth=nil
    setButton(farmBtn,farm,'Proximity Auto Farm')
    updateRing()
end)
bind(clickBtn.MouseButton1Click,function()
    click=not click
    setButton(clickBtn,click,'Auto Click (DPC)')
end)
bind(radiusBtn.MouseButton1Click,function()
    radius=radius+10
    if radius>100 then radius=10 end
    radiusBtn.Text='Radius: '..radius..' studs  (+10)'
    updateRing()
end)
-- Header drag surface, excluding the close button.
local header=Instance.new('Frame')
header.Name='DragHeader'
header.BackgroundTransparency=1
header.Size=UDim2.new(1,-54,0,44)
header.Position=UDim2.fromOffset(0,0)
header.Active=true
header.ZIndex=3
header.Parent=panel
title.ZIndex=4
title.Parent=header
title.Position=UDim2.fromOffset(16,2)
title.Size=UDim2.new(1,-16,0,42)

local dragging, dragStart, startPos
bind(header.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 then
        dragging=true
        dragStart=input.Position
        startPos=panel.Position
    end
end)
bind(UIS.InputEnded,function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end
end)
bind(UIS.InputChanged,function(input)
    if dragging and input.UserInputType==Enum.UserInputType.MouseMovement then
        local d=input.Position-dragStart
        panel.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
    end
end)
local panelShown=true
local panelTween
local shownSize=panel.Size
local function setPanelVisible(show)
    panelShown=show
    if panelTween then panelTween:Cancel() end
    if show then
        panel.Visible=true
        panel.Size=UDim2.fromOffset(310,240)
        panel.BackgroundTransparency=.35
    end
    panelTween=TweenService:Create(panel,TweenInfo.new(.2,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{
        Size=show and shownSize or UDim2.fromOffset(310,240),
        BackgroundTransparency=show and 0 or .35
    })
    panelTween:Play()
    if not show then
        local thisTween=panelTween
        task.spawn(function()
            thisTween.Completed:Wait()
            if alive and not panelShown and panelTween==thisTween then panel.Visible=false end
        end)
    end
end
bind(UIS.InputBegan,function(input,processed)
    if not processed and input.KeyCode==Enum.KeyCode.RightControl then
        setPanelVisible(not panelShown)
    end
end)
local function cleanup()
    alive=false
    for _,c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    pcall(function() ringAnchor:Destroy() end)
    pcall(function() gui:Destroy() end)
    if env.ABSHubCleanup==cleanup then env.ABSHubCleanup=nil end
end
env.ABSHubCleanup=cleanup
bind(close.MouseButton1Click,function() setPanelVisible(false) end)
bind(RunService.Heartbeat,function()
    if not alive or not ringAnchor.Parent then return end
    local hrp=root()
    if hrp then
        -- Ground raycast avoids the radius sinking below the map surface.
        local params=RaycastParams.new()
        params.FilterType=Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances={player.Character,ringAnchor}
        local hit=workspace:Raycast(hrp.Position+Vector3.new(0,4,0),Vector3.new(0,-35,0),params)
        local y=hit and hit.Position.Y+.35 or hrp.Position.Y-2.5
        ringAnchor.CFrame=CFrame.new(hrp.Position.X,y,hrp.Position.Z)
    end
end)
-- Read health from common NPC layouts, including nested UI-backed values.
local function readHealth(npc)
    local hum=npc:FindFirstChildOfClass('Humanoid')
    if hum then return hum.Health end
    for _,key in ipairs({'Health','HP','CurrentHealth','CurrentHP'}) do
        local v=npc:GetAttribute(key)
        if typeof(v)=='number' then return v end
        local obj=npc:FindFirstChild(key,true)
        if obj and (obj:IsA('NumberValue') or obj:IsA('IntValue')) then
            return obj.Value
        end
    end
    return nil
end
-- Short, bounded refresh is important when the server reuses the same NPC instance.
-- We also reset immediately on death or on a new instance spawning.
bind(npcFolder.ChildRemoved,function(npc)
    if npc==selected then
        selected=nil
        lastAttack=0
        targetWasDead=true
        lastTargetHealth=nil
    end
end)
bind(npcFolder.ChildAdded,function(npc)
    -- Force the next scan to re-evaluate, including bosses that reuse their name.
    if selected==nil or npc.Name==(selected and selected.Name) then
        lastAttack=0
    end
end)
task.spawn(function()
    while alive do
        if farm then
            local hrp=root()
            if hrp then
                local best,bestDist=nil,math.huge
                local currentHealth
                for _,npc in ipairs(npcFolder:GetChildren()) do
                    local ok,part=valid(npc)
                    if ok then
                        local hp=readHealth(npc)
                        if hp==nil or hp>0 then
                            local dist=(Vector3.new(part.Position.X,0,part.Position.Z)-Vector3.new(hrp.Position.X,0,hrp.Position.Z)).Magnitude
                            if dist<=radius and dist<bestDist then
                                best,bestDist,currentHealth=npc,dist,hp
                            end
                        end
                    end
                end
                if best then
                    local changed=best~=selected
                    local respawned=targetWasDead or
                        (best==selected and lastTargetHealth~=nil and currentHealth~=nil
                         and currentHealth>lastTargetHealth and lastTargetHealth<=0)
                    -- Refresh the command even if the NPC model was reused after respawn.
                    if changed or respawned or os.clock()-lastAttack>=1 then
                        local ok,err=pcall(function() action:FireServer('AttackTarget',best) end)
                        if ok then
                            selected=best
                            lastAttack=os.clock()
                            targetWasDead=false
                        else
                            status.Text='AttackTarget failed: '..tostring(err)
                        end
                    end
                    lastTargetHealth=currentHealth
                    status.Text='Target: '..best.Name..'  |  '..math.floor(bestDist)..' studs'
                else
                    if selected then targetWasDead=true end
                    selected=nil
                    lastAttack=0
                    lastTargetHealth=nil
                    status.Text='Scanning for NPCs within '..radius..' studs...'
                end
            else
                selected=nil
                lastAttack=0
                status.Text='Waiting for character...'
            end
        elseif not click then
            status.Text='Ready. Enable Auto Farm near enemies.'
        end
        task.wait(.15)
    end
end)
task.spawn(function()
    while alive do
        if click then
            local ok,err=pcall(function() action:FireServer('DPC') end)
            if not ok then warn('[ABS Auto Click]',err) end
        end
        task.wait(click and clickInterval or .2)
    end
end)
print('[Anime Brawlers Hub V1.3] Loaded. Right Ctrl to hide/show.')
