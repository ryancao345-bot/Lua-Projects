
    DigInterval = 0.1,
    AntiAFKInterval = 300,
    WatermelonInterval = 0.1,
    SproutInterval = 0.1,
    MobHiveWait = 1,

    WindowWidth = 620,
    WindowHeight = 365
}

local State = {
    active = true,
    farm = false,
    sprout = false,
    convert = false,
    dig = false,
    busy = false,
    mobFarm = false,
    autoWatermelon = false,
    autoSprout = false,

    field = nil,
    fieldName = nil,

    sproutField = nil,
    sproutFieldName = nil,

    hive = nil,
    hiveProxy = nil,

    status = "Ready"
}

local Connections = {}
local cleanup

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    Connections[#Connections + 1] = connection
    return connection
end

local function getRoot()
    local character = Player.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function getStandOffset()
    local character = Player.Character
    local root = getRoot()
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")

    if root and humanoid then
        return humanoid.HipHeight + root.Size.Y * 0.5 + 0.05
    end

    return 2.65
end

local function teleport(cf)
    local root = getRoot()
    if not root or not cf then return false end

    root.CFrame = cf
    root.AssemblyLinearVelocity = Vector3.zero
    return true
end

local function distanceSquared(a, b)
    local delta = a - b
    return delta:Dot(delta)
end

local function currentAnchor()
    if State.mobFarm then return nil end
    if State.sprout then return State.sproutField end
    if State.farm then return State.field end
    return nil
end

local setStatus = function(message)
    State.status = message
end

-- ============================================================
-- PART 2: WORLD DISCOVERY
-- ============================================================

local FIELD_ORDER = {
    ["Mushroom Field"] = 1,
    ["Blueberry Field"] = 2,
    ["Clover Field"] = 3,
    ["Spider Field"] = 4,
    ["Pineapple Field"] = 5,
    ["Mountain Field"] = 6,
    ["Forest Field"] = 7,
    ["Strawberry Field"] = 8,
    ["Watermelon Field"] = 9,
    ["Banana Field"] = 10,
    ["Cog Field"] = 11
}

local BEAR_ORDER = {
    ["Black Bear"] = 1,
    ["Mother Bear"] = 2,
    ["Panda Bear"] = 3,
    ["Science Bear"] = 4,
    ["Dapper Bear"] = 5,
    ["Polar Bear"] = 6,
    ["Flame Bear"] = 7,
    ["Shy Bear"] = 8,
    ["Beach Bear"] = 9,
    ["Robo Bear"] = 10,
    ["The Bear From Your Dreams"] = 11,
    ["Secret Bear"] = 12
}

local function sortLocations(list, order)
    table.sort(list, function(a, b)
        local x = order[a[1]] or 999
        local y = order[b[1]] or 999

        if x ~= y then return x < y end
        return a[1] < b[1]
    end)

    return list
end

local function getPlatformCF(platform)
    if not platform then return nil end

    local cf, size

    if platform:IsA("BasePart") then
        cf = platform.CFrame
        size = platform.Size
    elseif platform:IsA("Model") then
        cf, size = platform:GetBoundingBox()
    else
        return nil
    end

    return CFrame.new(
        cf.Position.X,
        cf.Position.Y + size.Y * 0.5 + getStandOffset(),
        cf.Position.Z
    )
end

local function getHiveCF()
    local folder = Workspace:FindFirstChild("Hives")
    if not folder then return State.hive end

    local displayCandidate
    local displayPrompt

    for _, hive in ipairs(folder:GetChildren()) do
        local exact = false
        local display = false

        local claimed = hive:FindFirstChild("Claimed")

        if claimed and claimed:IsA("ValueBase") then
            exact = claimed.Value == Player
                or tostring(claimed.Value) == Player.Name

            display = tostring(claimed.Value) == Player.DisplayName
        end

        if not exact then
            for _, obj in ipairs(hive:GetDescendants()) do
                if obj:IsA("ObjectValue") and obj.Value == Player then
                    exact = true
                    break
                elseif obj:IsA("StringValue") then
                    if obj.Value == Player.Name then
                        exact = true
                        break
                    elseif obj.Value == Player.DisplayName then
                        display = true
                    end
                elseif obj:IsA("TextLabel") then
                    if obj.Text:find(Player.Name, 1, true) then
                        exact = true
                        break
                    elseif obj.Text:find(Player.DisplayName, 1, true) then
                        display = true
                    end
                end
            end
