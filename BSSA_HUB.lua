-- Dragging

local dragging = false
local dragStart
local startPosition

connect(header.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then

        dragging = true
        dragStart = input.Position
        startPosition = main.Position

        local release
        release = input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
                release:Disconnect()
            end
        end)
    end
end)

connect(UIS.InputChanged, function(input)
    if not dragging or not dragStart or not startPosition then
        return
    end

    if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then

        local delta = input.Position - dragStart

        main.Position = UDim2.new(
            startPosition.X.Scale,
            startPosition.X.Offset + delta.X,
            startPosition.Y.Scale,
            startPosition.Y.Offset + delta.Y
        )
    end
end)

-- Fast, modern window transition: no cinematic overlays or temporary GUI.
-- UIScale scales the entire interface together, preventing stray fixed-size rows.
local alive = true
local windowScale = Instance.new('UIScale')
windowScale.Scale = 1
windowScale.Parent = main
local uiOpen = true
local animationTween = nil
local function setWindowOpen(open, instant)
    uiOpen = open
    if animationTween then animationTween:Cancel(); animationTween = nil end
    if not alive then return end
    if instant then
        windowScale.Scale = open and 1 or .965
        main.Visible = open
        return
    end
    if open then
        windowScale.Scale = .965
        main.Visible = true
    end
    local tween = TweenService:Create(windowScale,
        TweenInfo.new(open and .12 or .095, Enum.EasingStyle.Quart,
            open and Enum.EasingDirection.Out or Enum.EasingDirection.In),
        {Scale = open and 1 or .965})
    animationTween = tween
    tween:Play()
    local thisTween = tween
    task.spawn(function()
        thisTween.Completed:Wait()
        if animationTween ~= thisTween or not alive then return end
        animationTween = nil
        main.Visible = uiOpen
    end)
end
connect(UIS.InputBegan, function(input, processed)
    if processed or input.KeyCode ~= Enum.KeyCode.RightControl then return end
    setWindowOpen(not uiOpen, false)
end)
-- Initial reveal is quick and clean.
setWindowOpen(true, false)

-- Cleanup

local cleaned = false

cleanup = function()
    if cleaned then return end
    cleaned = true
    alive = false

    State.active = false
    State.farm = false
    State.sprout = false
    State.mobFarm = false
    mobAbortTarget()
    State.convert = false
    State.dig = false
    State.autoWatermelon = false
    State.autoSprout = false
    jellyHalt()
    for _,c in ipairs(jellyOptionConnections) do pcall(function() c:Disconnect() end) end
    State.busy = false

    for _, connection in ipairs(Connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    table.clear(Connections)
    table.clear(tokenIndex)
    table.clear(tokenAttempts)
    table.clear(tokenCooldowns)
    table.clear(tokenPending)

    if gui and gui.Parent then
        gui:Destroy()
    end
end

Env.FarmCleanup = cleanup

setStatus("Ready")

