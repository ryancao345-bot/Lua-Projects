--[[
    BSSA HUB
    Roblox Luau

    Release metadata is maintained in HUB_VERSION and HUB_BUILD below.
]]

-- ============================================================
-- PART 1: SERVICES, CONFIGURATION & STATE
-- ============================================================

local HUB_VERSION = "2.2.78"
local HUB_BUILD = "Purple Scopes Only"

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local VIM = game:GetService("VirtualInputManager")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")

local Player = Players.LocalPlayer
local Env = getgenv and getgenv() or {}

if type(Env.FarmCleanup) == "function" then
    pcall(Env.FarmCleanup)
end

local old = CoreGui:FindFirstChild("BSSAAutofarm")
if old then old:Destroy() end

local Debris = Workspace:WaitForChild("Debris")
local Tokens = Debris:WaitForChild("Tokens")
local Clouds = Workspace:WaitForChild("Clouds")

local CFG = {
    ReturnRadius = 95,

    TokenStay = 0.32,
    TokenConfirmWait = 0.12,
    -- Sprout mode: fast first attempt, longer retries only when needed.
    SproutTokenStay = {0.10, 0.18, 0.32},
    SproutTokenConfirm = {0.04, 0.08, 0.12},
    TokenRetryDelay = 0.8,
    TokenMaxAttempts = 3,
    TokenBackoff = 5,
    TokenReconcile = 2,

    PollenInterval = 0.25,

    MarkCooldown = 1,
    MarkStay = 0.18,
    MarkFirstDelay = 0.25,

    CloudStay = 0.45,
    CloudRetry = 1.5,

    ConvertInterval = 0.5,
    ConvertStuck = 15,
    ConvertMaxRetries = 5,
    ConvertCooldown = 15,

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
    targetScopes = false,
    sprout = false,
    convert = false,
    autoInstantConvert = false,
    hiveConversions = 0,
    dig = false,
    busy = false,
    mobFarm = false,
    autoWatermelon = false,
    autoSprout = false,
    autoGumdrop = false,
    planterEnabled = false,
    planterBusy = false,
    planterThread = nil,
    planterItem = nil,

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
    if State.planterBusy and State.planterThread ~= coroutine.running() then
        return false
    end
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
        end

        if exact or display then
            local platform = hive:FindFirstChild("Platform")
            local top = platform and platform:FindFirstChild("Top")

            local cf = getPlatformCF(top or platform)

            local prompt = (
                top and top:FindFirstChild("Proxy")
            ) or (
                platform and platform:FindFirstChildWhichIsA(
                    "ProximityPrompt", true
                )
            )

            if cf then
                if exact then
                    State.hive = cf
                    State.hiveProxy = prompt
                    return cf
                end

                displayCandidate = cf
                displayPrompt = prompt
            end
        end
    end

    if displayCandidate then
        State.hive = displayCandidate
        State.hiveProxy = displayPrompt
    end

    return State.hive
end

local function buildFields()
    local result = {}
    local folder = Workspace:FindFirstChild("Fields")
    if not folder then return result end

    for _, field in ipairs(folder:GetChildren()) do
        if field.Name ~= "Glitch Field" then
            local box = field:FindFirstChild("FieldBox")

            if box and box:IsA("BasePart") then
                local totalY, count = 0, 0

                for _, part in ipairs(field:GetChildren()) do
                    if part.Name == "FlowerPart"
                        and part:IsA("BasePart") then

                        totalY = totalY
                            + part.Position.Y
                            + part.Size.Y * 0.5

                        count = count + 1
                    end
                end

                local y = count > 0
                    and totalY / count + getStandOffset() - 0.5
                    or box.Position.Y + 2

                result[#result + 1] = {
                    field.Name,
                    CFrame.new(box.Position.X, y, box.Position.Z)
                }
            end
        end
    end

    return sortLocations(result, FIELD_ORDER)
end

local function buildBears()
    local result = {}
    local folder = Workspace:FindFirstChild("QuestNPCS")
    if not folder then return result end

    for _, bear in ipairs(folder:GetChildren()) do
        local platform = bear:FindFirstChild("Platform")
        local npc = bear:FindFirstChild("NPC")
        local cf = getPlatformCF(platform) or getPlatformCF(npc)

        if cf then
            result[#result + 1] = {
                bear.Name:gsub("'s Quest List$", ""),
                cf
            }
        end
    end

    return sortLocations(result, BEAR_ORDER)
end

-- ============================================================
-- MOB FARM: COOLDOWNS, KILL CONFIRMATION, SINGLE CONTROLLER
-- ============================================================
local MOB_DEFS = {
    {name="Ladybug", field="Mushroom Field"},
    {name="Rhino Beetle", field="Blueberry Field"},
    {name="Fruity Bug", field="Clover Field"},
    {name="Spider", field="Spider Field"},
    {name="Mantis", field="Pineapple Field"},
    {name="Chick", field="Mountain Field"},
    {name="Cactus", field="Forest Field"},
    {name="Mantis Beetle", field="Strawberry Field"},
    {name="Watermelon Crab", field="Watermelon Field"},
    {name="Cog Sphere", field="Cog Field"}
}

local Mob = {items={}, target=nil, generation=0, status="Idle"}
for i, def in ipairs(MOB_DEFS) do
    Mob.items[i] = {
        name=def.name, field=def.field, enabled=false,
        expiry=0, known=false, lastText=nil, lastTextAt=0,
        retryAt=0, label=nil, lastVisit=0
    }
end

local function parseMobTime(raw)
    if type(raw) ~= "string" then return nil end
    raw = raw:match("^%s*(.-)%s*$")
    if not raw or not raw:match("^%d+:%d%d:?%d?%d?$") then return nil end
    local parts = {}
    for value in raw:gmatch("%d+") do
        parts[#parts+1] = tonumber(value)
    end
    if #parts == 2 and parts[2] < 60 then
        return parts[1]*60+parts[2]
    elseif #parts == 3 and parts[2] < 60 and parts[3] < 60 then
        return parts[1]*3600+parts[2]*60+parts[3]
    end
    return nil
end

local function mobTimerLabel(item)
    local fields = Workspace:FindFirstChild("Fields")
    local field = fields and fields:FindFirstChild(item.field)
    local spawner = field and field:FindFirstChild("Spawner")
    local spawn = spawner and spawner:FindFirstChild("Spawn")
    local time = spawn and spawn:FindFirstChild("Time")
    local label = time and time:FindFirstChild("Time")
    return label and label:IsA("TextLabel") and label or nil
end

local function mobFieldCF(item)
    for _, entry in ipairs(buildFields()) do
        if entry[1] == item.field then return entry[2] end
    end
    return nil
end

local function mobEnemy()
    local folder = Debris:FindFirstChild("Entity")
    local model = folder and folder:FindFirstChild(Player.Name)
    local humanoid = model and model:FindFirstChild("BeeEnemy")
    if humanoid and humanoid:IsA("Humanoid") then
        return humanoid, model
    end
    return nil, nil
end

local function mobRemaining(item)
    return math.max(0, math.ceil((item.expiry or 0) - os.clock()))
end

local function mobReadTimer(item)
    local label = mobTimerLabel(item)
    if not label then return nil end
    local value = parseMobTime(label.Text)
    if value == nil then return nil end
    local now = os.clock()
    if value > 0 then
        -- Only a changed, decreasing timer is evidence that the game timer is live.
        -- Once observed, keep our own monotonic deadline across character resets.
        if item.lastText == nil then
            if not item.known then
                item.expiry = now + value
                item.known = true
            end
        elseif value < item.lastText then
            if not item.known or now + value < item.expiry - 2 then
                item.expiry = now + value
            end
            item.known = true
        elseif value > item.lastText + 2 then
            -- New respawn cycle; a freshly increased countdown is usable.
            item.expiry = now + value
            item.known = true
        end
    end
    item.lastText = value
    item.lastTextAt = now
    return value
end

local function mobAbortTarget()
    Mob.generation = Mob.generation + 1
    Mob.target = nil
end

local function mobEnabledCount()
    local n = 0
    for _, item in ipairs(Mob.items) do
        if item.enabled then n = n + 1 end
    end
    return n
end

local function mobChoose()
    local now = os.clock()
    local best
    for _, item in ipairs(Mob.items) do
        if item.enabled and now >= item.retryAt and
            (not item.known or now >= item.expiry) then
            if not best or item.lastVisit < best.lastVisit then
                best = item
            end
        end
    end
    return best
end

local function mobVisit(item)
    local cf = mobFieldCF(item)
    if not cf then
        item.retryAt = os.clock() + 15
        Mob.status = "Missing field: " .. item.field
        return
    end
    Mob.target = item
    Mob.generation = Mob.generation + 1
    local ticket = Mob.generation
    item.lastVisit = os.clock()
    Mob.status = "Targeting " .. item.name
    setStatus("Mob: " .. item.name)
    if not teleport(cf) then
        item.retryAt = os.clock() + 5
        Mob.target = nil
        return
    end

    local started = os.clock()
    local enemy, seenAlive, confirmed = nil, false, false
    local lastHealth
    local timerBefore = mobReadTimer(item)
    while State.active and State.mobFarm and item.enabled and
        Mob.generation == ticket do
        local now = os.clock()
        if not getRoot() then break end
        if now - started > 75 then break end
        local current = mobEnemy()
        if current and current.Health > 0 then
            enemy = current
            seenAlive = true
            lastHealth = current.Health
        elseif current and current.Health <= 0 and seenAlive then
            confirmed = true
            break
        elseif enemy and seenAlive and enemy.Health <= 0 then
            confirmed = true
            break
        end
        local raw = mobReadTimer(item)
        if raw and raw > 0 and (timerBefore == 0 or seenAlive) then
            -- A positive timer after the encounter is stronger evidence of a kill.
            confirmed = seenAlive or timerBefore == 0
            if confirmed then break end
        end
        if item.known and mobRemaining(item) > 0 and now - started > 2 then
            break
        end
        task.wait(0.2)
    end
    if Mob.generation ~= ticket then return end
    Mob.target = nil
    if not State.active or not State.mobFarm or not item.enabled then return end
    local after = mobReadTimer(item)
    if confirmed then
        if after and after > 0 then
            item.expiry = os.clock() + after
            item.known = true
        else
            -- Kill confirmed but duration unknown: avoid immediate repeat.
            item.known = false
            item.retryAt = os.clock() + 15
        end
        -- Exit the mob field after a confirmed kill, even if only one mob
        -- is selected. This does not bypass the game's respawn cooldown.
        local hiveCF = getHiveCF()
        if hiveCF and State.active and State.mobFarm and item.enabled
            and Mob.generation == ticket then
            Mob.status = "Returning to hive after " .. item.name
            setStatus("Mob: Returning to hive")
            if teleport(hiveCF) then
                local waitUntil = os.clock() + CFG.MobHiveWait
                while os.clock() < waitUntil do
                    if not State.active or not State.mobFarm
                        or Mob.generation ~= ticket then break end
                    task.wait(math.min(0.1, waitUntil - os.clock()))
                end
            end
        else
            if not hiveCF then
                warn("[BSSA] Could not locate hive after mob kill")
            end
        end
        if State.active and State.mobFarm and Mob.generation == ticket then
            Mob.status = "Defeated " .. item.name
        end
    else
        item.retryAt = os.clock() + 15
        Mob.status = "Checking " .. item.name .. " later"
    end
end

task.spawn(function()
    while State.active do
        task.wait(0.25)
        for _, item in ipairs(Mob.items) do
            mobReadTimer(item)
        end
        if State.mobFarm and not State.busy and getRoot() then
            if not Mob.target then
                local choice = mobChoose()
                if choice then
                    local ok, err = pcall(mobVisit, choice)
                    if not ok then
                        warn("[BSSA] Mob visit:", err)
                        choice.retryAt = os.clock() + 10
                        Mob.target = nil
                    end
                else
                    Mob.status = "Waiting for mob respawns"
                end
            end
        end
    end
end)

-- ============================================================
-- PART 3: POLLEN & CONVERSION
-- ============================================================

local pollenCurrent
local pollenMaximum
local lastPollenCheck = 0
local nextConversionAttempt = 0

local function readPollen()
    for _, label in ipairs(Player.PlayerGui:GetDescendants()) do
        if label:IsA("TextLabel")
            and label.Visible
            and label.Text:find("/", 1, true) then

            local name = label.Name:lower()
            local parentName = label.Parent
                and label.Parent.Name:lower()
                or ""

            if label.AbsolutePosition.Y < 80
                or name:find("pollen", 1, true)
                or parentName:find("pollen", 1, true) then

                local text = label.Text:gsub(",", "")
                local current, maximum = text:match(
                    "(%d+)%s*/%s*(%d+)"
                )

                current = tonumber(current)
                maximum = tonumber(maximum)

                if current and maximum and maximum > 100 then
                    return current, maximum
                end
            end
        end
    end

    return nil, nil
end

local function refreshPollen(force)
    local now = os.clock()

    if force or now - lastPollenCheck >= CFG.PollenInterval then
        lastPollenCheck = now

        local current, maximum = readPollen()

        if current and maximum then
            pollenCurrent = current
            pollenMaximum = maximum
            return true
        end
    end

    return false
end

local function triggerConversion()
    local prompt = State.hiveProxy

    if prompt
        and prompt.Parent
        and prompt:IsA("ProximityPrompt")
        and fireproximityprompt then

        pcall(fireproximityprompt, prompt)
        task.wait(0.1)
        return
    end

    VIM:SendKeyEvent(true, Enum.KeyCode.E, false, game)
    task.wait(0.08)
    VIM:SendKeyEvent(false, Enum.KeyCode.E, false, game)
end

local resetTokenTracking = function() end
local resetFarmTargets = function() end

local function convertPollen()
    if State.busy or not State.active or State.mobFarm or State.autoInstantConvert then return end
    if os.clock() < nextConversionAttempt then return end

    local hive = getHiveCF()

    if not hive then
        setStatus("Claim a hive first")
        nextConversionAttempt = os.clock() + 5
        return
    end

    State.busy = true
    setStatus("Converting pollen")

    local completed = false
    local failed = false

    local ok, err = pcall(function()
        local arrived = teleport(hive)
        if State.farm and arrived then
            State.hiveConversions = State.hiveConversions + 1
        end
        task.wait(0.45)
        triggerConversion()

        local previous = pollenCurrent
        local stuckSince = os.clock()
        local retries = 0

        while State.active and State.convert and not State.autoInstantConvert do
            task.wait(CFG.ConvertInterval)

            local current = readPollen()

            if current ~= nil then
                pollenCurrent = current

                if current <= 0 then
                    completed = true
                    break
                end

                if previous and current < previous then
                    stuckSince = os.clock()
                    retries = 0
                end

                previous = current
            end

            if os.clock() - stuckSince >= CFG.ConvertStuck then
                retries = retries + 1
                stuckSince = os.clock()

                if retries > CFG.ConvertMaxRetries then
                    failed = true
                    break
                end

                setStatus("Conversion retry " .. retries)

                local retryHive = getHiveCF()

                if retryHive then
                    teleport(retryHive)
                    task.wait(0.45)
                    triggerConversion()
                end
            end
        end
    end)

    if not ok then
        warn("[BSSA] Conversion:", err)
        failed = true
    end

    nextConversionAttempt = failed
        and os.clock() + CFG.ConvertCooldown
        or 0

    resetTokenTracking()
    resetFarmTargets()

    State.busy = false

    if not State.active then return end

    local anchor = currentAnchor()
    if anchor then teleport(anchor) end

    if failed then
        setStatus("Conversion stalled - retry pending")
    elseif completed then
        setStatus("Conversion complete")
    elseif State.farm then
        setStatus("Farming " .. tostring(State.fieldName))
    elseif State.sprout then
        setStatus("Sprout farming")
    else
        setStatus("Ready")
    end
end

-- ============================================================
-- PART 4: ROBUST TOKEN TRACKING
-- ============================================================

local tokenIndex = {}
local tokenAttempts = {}
local tokenCooldowns = {}
local tokenPending = {}
-- Observed pickup monitor: token disappears shortly after our touch attempt.
-- This is an estimate, not a server-confirmed pickup receipt.
local tokenTouchedAt = {}
local tokenCounted = {}
local tokenCollectedTotal = 0
local tokenCollectionTimes = {}
local tokenRecent = {}
local tokenByName = {}
local tokenPickupLatencies = {}
local tokenMonitorRefresh = function() end
local tokenMonitorStarted = os.clock()
local tokenDiagnostics = {
    visits = 0, firstSuccess = 0, retrySuccess = 0,
    failedVisits = 0, failedAttemptSeconds = 0,
    retryAttempts = 0, nearbyPickups = 0,
    activeTarget = nil
}

local function tokenDisplayName(token)
    local obj = token:FindFirstChild("TokenName", true)
    local value = obj and obj:IsA("ValueBase") and obj.Value
        or token:GetAttribute("TokenName")
    local name = value and tostring(value):match("^%s*(.-)%s*$")
    return (name and name ~= "") and name or "Unknown"
end

local function recordTokenCollection(token)
    if tokenCounted[token] then return end
    local data = tokenIndex[token]
    local hb = data and data.hitbox
    local touchedAt = hb and tokenTouchedAt[hb]
    if not touchedAt or os.clock() - touchedAt > 2 then return end
    tokenCounted[token] = true
    if tokenDiagnostics.activeTarget and tokenDiagnostics.activeTarget ~= token then
        tokenDiagnostics.nearbyPickups += 1
    end
    local now = os.clock()
    local name = tokenDisplayName(token)
    local previousPickupAt = tokenCollectionTimes[#tokenCollectionTimes]
    local interval = previousPickupAt and (now - previousPickupAt) or nil
    local pickupLatency = now - touchedAt
    tokenPickupLatencies[#tokenPickupLatencies + 1] = pickupLatency
    tokenCollectedTotal += 1
    tokenCollectionTimes[#tokenCollectionTimes + 1] = now
    tokenByName[name] = (tokenByName[name] or 0) + 1
    table.insert(tokenRecent, 1, {name=name, time=now, interval=interval, latency=pickupLatency})
    if #tokenRecent > 60 then table.remove(tokenRecent) end
    tokenMonitorRefresh()
end

-- Token and honey-mark eligibility uses the selected field's actual footprint.
-- Do not fall back to a radius if the field box is missing.
local function activeFieldBox()
    local name = State.sprout and State.sproutFieldName
        or (State.farm and State.fieldName)
    local fields = Workspace:FindFirstChild("Fields")
    local field = name and fields and fields:FindFirstChild(name)
    local box = field and field:FindFirstChild("FieldBox")
    return box and box:IsA("BasePart") and box or nil
end

local function insideFieldBoxXZ(position, box)
    if not box then return false end
    local localPos = box.CFrame:PointToObjectSpace(position)
    local half = box.Size * 0.5
    return math.abs(localPos.X) <= half.X
        and math.abs(localPos.Z) <= half.Z
end

local NEAR_TOKEN_SQ = 36

local EXCLUDED_TOKENS = {
    "honey",
    "treat",
    "royal jelly",
    "royaljelly"
}

local function shouldSkipToken(token)
    local valueObject = token:FindFirstChild("TokenName", true)

    local value = valueObject
        and valueObject:IsA("ValueBase")
        and valueObject.Value
        or token:GetAttribute("TokenName")

    if value == nil then return true end

    local name = tostring(value):lower():match("^%s*(.-)%s*$")
    if not name or name == "" then return true end

    if name == "star treat"
        or name == "honeysuckle"
        or name:find("mark", 1, true) then
        return false
    end

    for _, excluded in ipairs(EXCLUDED_TOKENS) do
        if name:find(excluded, 1, true) then
            return true
        end
    end

    return false
end

local function tokenParts(token)
    local hb = token:FindFirstChild("Hitbox")
        or (token:IsA("BasePart") and token)

    local visual = token:FindFirstChild("Token")
    return hb, visual
end

local function tokenAlive(hb, visual)
    return hb
        and hb.Parent
        and hb:IsA("BasePart")
        and hb.CanTouch
        and visual
        and visual.Parent
        and visual:IsA("BasePart")
        and visual.Transparency < 0.02
        and visual.Position.Y - hb.Position.Y <= 0.15
end

local function tokenAllowed(token)
    if State.sprout then
        return token.Name == "All"
    end

    return token.Name == "All" or token.Name == Player.Name
end

local function touchToken(hb)
    if not firetouchinterest or not hb or not hb.Parent then
        return
    end

    local root = getRoot()
    if not root then return end

    tokenTouchedAt[hb] = os.clock()
    pcall(firetouchinterest, root, hb, false)
    pcall(firetouchinterest, root, hb, true)

    local character = Player.Character
    local torso = character and (
        character:FindFirstChild("LowerTorso")
        or character:FindFirstChild("Torso")
    )

    if torso then
        pcall(firetouchinterest, torso, hb, false)
        pcall(firetouchinterest, torso, hb, true)
    end
end

local function registerToken(token)
    if not token or token.Parent ~= Tokens then
        return false
    end

    if tokenIndex[token] then
        return true
    end

    local hb, visual = tokenParts(token)

    if not hb or not visual then
        return false
    end

    if shouldSkipToken(token) then
        return false
    end

    tokenIndex[token] = {
        hitbox = hb,
        visual = visual,
        token = token
    }

    tokenPending[token] = nil
    return true
end

local function removeToken(token)
    local data = tokenIndex[token]
    if data then recordTokenCollection(token) end

    if data then
        local hb = data.hitbox
        tokenAttempts[hb] = nil
        tokenCooldowns[hb] = nil
        tokenTouchedAt[hb] = nil
    end

    tokenCounted[token] = nil
    tokenIndex[token] = nil
    tokenPending[token] = nil
end

local function queueToken(token)
    if not token or token.Parent ~= Tokens then return end
    if tokenIndex[token] then return end

    tokenPending[token] = true
    registerToken(token)
end

for _, token in ipairs(Tokens:GetChildren()) do
    queueToken(token)
end

connect(Tokens.ChildAdded, queueToken)
connect(Tokens.ChildRemoved, removeToken)

-- Periodic reconciliation catches late-initializing tokens.
task.spawn(function()
    while State.active do
        task.wait(CFG.TokenReconcile)

        if not State.active then break end

        for _, token in ipairs(Tokens:GetChildren()) do
            if not tokenIndex[token] then
                queueToken(token)
            end
        end

        for token, data in pairs(tokenIndex) do
            if token.Parent ~= Tokens then
                removeToken(token)
            elseif not tokenAlive(data.hitbox, data.visual) then
                recordTokenCollection(token)
            end
        end

        for token in pairs(tokenPending) do
            if token.Parent ~= Tokens then
                tokenPending[token] = nil
            else
                registerToken(token)
            end
        end
    end
end)

resetTokenTracking = function()
    table.clear(tokenAttempts)
    table.clear(tokenCooldowns)
end

-- Token collection priority: Token Link > White Boost variants > Inspire > other tokens.
-- Uses the same TokenName lookup and attribute fallback as shouldSkipToken.
local function tokenCollectionPriority(token)
    local valueObject = token:FindFirstChild("TokenName", true)
    local value = valueObject
        and valueObject:IsA("ValueBase")
        and valueObject.Value
        or token:GetAttribute("TokenName")

    local name = value and tostring(value):lower():match("^%s*(.-)%s*$")
    if name == "token link" then
        return 3
    elseif name == "white boost" or name == "ascended white boost" then
        return 2
    elseif name == "inspire" then
        return 1
    end
    return 0
end

local function collectTokens(anchor)
    local root = getRoot()
    if not root or not anchor then return false end

    local now = os.clock()
    local best
    local bestDistance = math.huge
    local bestPriority = -1
    local nearby = {}
    local fieldBox = activeFieldBox()
    if not fieldBox then return false end

    for token, data in pairs(tokenIndex) do
        if token.Parent == Tokens and tokenAllowed(token) then
            local hb = data.hitbox
            local visual = data.visual

            if tokenAlive(hb, visual) then
                if insideFieldBoxXZ(hb.Position, fieldBox) then
                    nearby[#nearby + 1] = data

                    if (tokenCooldowns[hb] or 0) <= now then
                        local playerDistance = distanceSquared(
                            hb.Position,
                            root.Position
                        )

                        local priority = tokenCollectionPriority(token)
                        if priority > bestPriority
                            or (priority == bestPriority and playerDistance < bestDistance) then
                            bestPriority = priority
                            bestDistance = playerDistance
                            best = data
                        end
                    end
                end
            end
        end
    end

    if not best then return false end

    -- Prefer a cluster of eligible tokens when priority is equal. The existing
    -- touch loop already attempts pickups within 6 studs of its target; this
    -- chooses a target that can make better use of that same visit. Keep the
    -- original nearest-target behavior as the fallback and preserve priority.
    -- A small, capped cluster bonus prevents a distant group from winning
    -- solely because it contains many tokens.
    local bestScore = -math.huge
    for _, candidate in ipairs(nearby) do
        local candidateHB = candidate.hitbox
        if (tokenCooldowns[candidateHB] or 0) <= now then
            local priority = tokenCollectionPriority(candidate.token)
            if priority == bestPriority then
                local nearbyCount = 0
                for _, other in ipairs(nearby) do
                    if other ~= candidate
                        and distanceSquared(other.hitbox.Position, candidateHB.Position) <= NEAR_TOKEN_SQ then
                        nearbyCount += 1
                    end
                end
                -- Each extra nearby token offsets up to 12 studs of distance;
                -- at most 3 extras count toward the target-selection bonus.
                local distance = math.sqrt(distanceSquared(candidateHB.Position, root.Position))
                local score = math.min(nearbyCount, 3) * 12 - distance
                if score > bestScore then
                    bestScore = score
                    best = candidate
                end
            end
        end
    end

    local hb = best.hitbox
    local visual = best.visual
    -- Cache the pickup neighborhood for this visit instead of scanning and
    -- distance-checking every field token on every Heartbeat.
    local touchNeighbors = {}
    for _, other in ipairs(nearby) do
        if other.hitbox ~= hb
            and distanceSquared(other.hitbox.Position, hb.Position) <= NEAR_TOKEN_SQ then
            touchNeighbors[#touchNeighbors + 1] = other
        end
    end
    local collected = false
    local interrupted = false
    local attemptsThisVisit = 0
    local unsuccessfulSeconds = 0
    tokenDiagnostics.visits += 1
    tokenDiagnostics.activeTarget = best.token

    -- Keep retries at the token instead of returning to the field between attempts.
    while attemptsThisVisit < CFG.TokenMaxAttempts do
        if not State.active
            or State.busy
            or State.mobFarm
            or not (State.farm or State.sprout) then
            interrupted = true
            break
        end

        if not hb.Parent or not visual.Parent or not tokenAlive(hb, visual) then
            collected = true
            break
        end

        attemptsThisVisit += 1
        if attemptsThisVisit > 1 then tokenDiagnostics.retryAttempts += 1 end
        if not teleport(hb.CFrame) then
            interrupted = true
            break
        end

        local stayTime = State.sprout
            and CFG.SproutTokenStay[math.min(attemptsThisVisit, #CFG.SproutTokenStay)]
            or CFG.TokenStay
        local confirmTime = State.sprout
            and CFG.SproutTokenConfirm[math.min(attemptsThisVisit, #CFG.SproutTokenConfirm)]
            or CFG.TokenConfirmWait

        local attemptStart = os.clock()
        repeat
            if not State.active
                or State.busy
                or State.mobFarm
                or not (State.farm or State.sprout) then
                interrupted = true
                break
            end

            if not tokenAlive(hb, visual) then
                collected = true
                break
            end

            -- Keep the character on the pickup while touch registration catches up.
            teleport(hb.CFrame)
            touchToken(hb)

            for _, other in ipairs(touchNeighbors) do
                local otherHB = other.hitbox
                if tokenAlive(otherHB, other.visual) then
                    -- Preserve the original 6-stud constraint if a token moves.
                    if distanceSquared(otherHB.Position, hb.Position) <= NEAR_TOKEN_SQ then
                        touchToken(otherHB)
                    end
                end
            end

            RunService.Heartbeat:Wait()
        until os.clock() - attemptStart >= stayTime

        if interrupted or collected then break end

        -- Give the game a short additional window to acknowledge the pickup.
        local confirmStart = os.clock()
        repeat
            if not State.active or State.busy or State.mobFarm
                or not (State.farm or State.sprout) then
                interrupted = true
                break
            end
            if not tokenAlive(hb, visual) then
                collected = true
                break
            end
            RunService.Heartbeat:Wait()
        until os.clock() - confirmStart >= confirmTime

        if not collected and not interrupted and tokenAlive(hb, visual) then
            unsuccessfulSeconds += os.clock() - attemptStart
        end
        if interrupted or collected then break end
    end

    tokenDiagnostics.activeTarget = nil
    tokenDiagnostics.failedAttemptSeconds += unsuccessfulSeconds
    if not interrupted then
        if collected or not tokenAlive(hb, visual) then
            if attemptsThisVisit == 1 then
                tokenDiagnostics.firstSuccess += 1
            elseif attemptsThisVisit > 1 then
                tokenDiagnostics.retrySuccess += 1
            end
        else
            tokenDiagnostics.failedVisits += 1
        end
    end

    if collected or not tokenAlive(hb, visual) then
        recordTokenCollection(best.token)
        tokenAttempts[hb] = nil
        tokenCooldowns[hb] = nil
    elseif not interrupted then
        -- The full local retry budget failed; back off before revisiting.
        tokenAttempts[hb] = 0
        tokenCooldowns[hb] = os.clock() + CFG.TokenBackoff
    end

    return true
end

-- ============================================================
-- PART 5: CLOUDS, HONEY MARKS & FARM LOOP
-- ============================================================

local nextCloud = {
    CloudBetter = 0,
    Cloud = 0
}

local nextMarkTime = 0
local lockedMark
local lockedMarkIsPlate = false

resetFarmTargets = function()
    lockedMark = nil
    lockedMarkIsPlate = false
    nextMarkTime = 0
    nextCloud.CloudBetter = 0
    nextCloud.Cloud = 0
end

local function hasBuff(name)
    local main = Player.PlayerGui:FindFirstChild("Main")
    local buffs = main and main:FindFirstChild("Buffs")
    local tile = buffs and buffs:FindFirstChild(name)

    return tile
        and tile:IsA("GuiObject")
        and tile.Visible
end

local function findCloud(name)
    if not State.fieldName then return nil end

    for _, cloud in ipairs(Clouds:GetChildren()) do
        if cloud.Name == name and cloud:IsA("BasePart") then
            local field = cloud:FindFirstChild("Field")

            if field
                and field:IsA("StringValue")
                and field.Value == State.fieldName then
                return cloud
            end
        end
    end

    return nil
end

local function handleClouds()
    if State.mobFarm or not State.farm or not State.field then return false end

    local now = os.clock()

    local options = {
        {"CloudBetter", "Cloud Boost+"},
        {"Cloud", "Cloud Boost"}
    }

    for _, option in ipairs(options) do
        local name, buff = option[1], option[2]

        if now >= nextCloud[name] and not hasBuff(buff) then
            local cloud = findCloud(name)

            if cloud then
                local started = os.clock()

                repeat
                    if not State.active
                        or not State.farm
                        or State.busy
                        or State.mobFarm
                        or not cloud.Parent
                        or hasBuff(buff) then
                        break
                    end

                    teleport(CFrame.new(
                        cloud.Position.X,
                        State.field.Position.Y,
                        cloud.Position.Z
                    ))

                    RunService.Heartbeat:Wait()
                until os.clock() - started >= CFG.CloudStay

                if not hasBuff(buff) then
                    nextCloud[name] = os.clock() + CFG.CloudRetry
                end

                return true
            end
        end
    end

    return false
end

local function ownsHoneyMark(mark)
    local owner = mark and mark:FindFirstChild("Owner")
    return owner and owner:IsA("StringValue") and owner.Value == Player.Name
end

local function ownsLockedHoneyMark(part)
    local mark = part and part:FindFirstAncestor("HoneyMark")
    return mark and mark.Parent == Debris and ownsHoneyMark(mark)
end

local function findHoneyMark(root)
    local closest
    local closestDistance = math.huge
    local isPlate = false
    local fieldBox = activeFieldBox()
    if not fieldBox then return nil, false end

    for _, mark in ipairs(Debris:GetChildren()) do
        if mark.Name == "HoneyMark" then
            if ownsHoneyMark(mark) then
                local plate = mark:FindFirstChild("Plate", true)

                local part = (
                    plate and plate:IsA("BasePart") and plate
                ) or mark:FindFirstChild("Honey Mark")
                    or mark:FindFirstChildWhichIsA("BasePart")

                if part and part:IsA("BasePart") then
                    if insideFieldBoxXZ(part.Position, fieldBox) then

                        local distance = distanceSquared(
                            part.Position,
                            root.Position
                        )

                        if distance < closestDistance then
                            closest = part
                            closestDistance = distance
                            isPlate = plate == part
                        end
                    end
                end
            end
        end
    end

    return closest, isPlate
end

local function handleHoneyMark()
    if not State.farm
        or not State.field
        or State.mobFarm
        or not pollenCurrent
        or pollenCurrent <= 500 then
        return false
    end

    local root = getRoot()
    if not root then return false end

    local invalid = not lockedMark
        or not lockedMark.Parent
        or not lockedMark:IsDescendantOf(Debris)
        or not ownsLockedHoneyMark(lockedMark)

    if not invalid then
        invalid = not insideFieldBoxXZ(lockedMark.Position, activeFieldBox())
    end

    if invalid then
        lockedMark, lockedMarkIsPlate = findHoneyMark(root)

        if lockedMark then
            nextMarkTime = os.clock() + CFG.MarkFirstDelay
        end
    end

    if not lockedMark or os.clock() < nextMarkTime then
        return false
    end

    local started = os.clock()

    repeat
        if not State.active
            or not State.farm
            or State.busy
            or State.mobFarm
            or not lockedMark
            or not lockedMark.Parent
            or not ownsLockedHoneyMark(lockedMark) then
            break
        end

        local y

        if lockedMarkIsPlate then
            y = lockedMark.Position.Y
                + lockedMark.Size.Y * 0.5
                + getStandOffset()
        else
            y = lockedMark.Position.Y
                - lockedMark.Size.Y * 0.5
                + getStandOffset()
        end

        teleport(CFrame.new(
            lockedMark.Position.X,
            y,
            lockedMark.Position.Z
        ))

        RunService.Heartbeat:Wait()
    until os.clock() - started >= CFG.MarkStay

    nextMarkTime = os.clock() + CFG.MarkCooldown
    return true
end

local function farmStep()
    if State.busy or State.mobFarm then return end

    local root = getRoot()
    if not root then return end

    refreshPollen(false)

    if State.convert
        and not State.autoInstantConvert
        and pollenCurrent
        and pollenMaximum
        and pollenCurrent >= pollenMaximum then

        convertPollen()
        return
    end

    local anchor = currentAnchor()
    if not anchor then return end

    if distanceSquared(
        root.Position,
        anchor.Position
    ) > CFG.ReturnRadius ^ 2 then

        teleport(anchor)
        RunService.Heartbeat:Wait()
    end

    if State.busy or State.mobFarm then return end
    if handleClouds() then return end
    if handleHoneyMark() then return end
    if collectTokens(anchor) then
        if State.targetScopes and State.farm and not State.sprout
            and not State.busy and not State.mobFarm and State.scopeAnchor then
            local destination = State.scopeAnchor()
            if destination then teleport(destination) end
        end
        return
    end

    if State.targetScopes and State.farm and not State.sprout and State.scopeAnchor then
        anchor = State.scopeAnchor() or anchor
    end
    root = getRoot()

    if root
        and distanceSquared(root.Position, anchor.Position) > (State.targetScopes and State.farm and not State.sprout and 0.25 or 16) then
        teleport(anchor)
    end
end

task.spawn(function()
    while State.active do
        local ok, err = pcall(farmStep)

        if not ok then
            warn("[BSSA] Farm error:", err)
            setStatus("Farm error - retrying")
            task.wait(0.5)
        else
            RunService.Heartbeat:Wait()
        end
    end
end)

task.spawn(function()
    while State.active do
        task.wait(0.5)

        local now = os.clock()

        for hb, expiry in pairs(tokenCooldowns) do
            if not hb.Parent or now >= expiry then
                tokenCooldowns[hb] = nil
            end
        end

        for hb in pairs(tokenAttempts) do
            if not hb.Parent then
                tokenAttempts[hb] = nil
            end
        end
    end
end)

task.spawn(function()
    while State.active do
        task.wait(CFG.DigInterval)

        if State.dig and not State.busy then
            local character = Player.Character
            local tool = character
                and character:FindFirstChildOfClass("Tool")

            local remote = tool
                and tool:FindFirstChild("ToolRemote")

            if remote and remote:IsA("RemoteEvent") then
                pcall(function()
                    remote:FireServer()
                end)
            end
        end
    end
end)

pcall(function()
    if getconnections then
        for _, connection in pairs(getconnections(Player.Idled)) do
            if connection.Disable then
                connection:Disable()
            elseif connection.Disconnect then
                connection:Disconnect()
            end
        end
    end
end)

task.spawn(function()
    while State.active do
        task.wait(CFG.AntiAFKInterval)

        if State.active then
            pcall(function()
                VIM:SendMouseButtonEvent(0, 0, 1, true, game, 0)
                RunService.RenderStepped:Wait()
                VIM:SendMouseButtonEvent(0, 0, 1, false, game, 0)
            end)
        end
    end
end)

-- ============================================================
-- PART 6: COMPACT MODERN GUI
-- ============================================================

local THEME = {
    Background = Color3.fromRGB(18, 21, 29),
    Sidebar = Color3.fromRGB(15, 18, 25),
    Panel = Color3.fromRGB(25, 29, 39),
    Control = Color3.fromRGB(34, 39, 51),
    Hover = Color3.fromRGB(44, 51, 67),
    Border = Color3.fromRGB(52, 60, 77),

    Accent = Color3.fromRGB(102, 153, 239),
    AccentDim = Color3.fromRGB(39, 55, 80),

    Text = Color3.fromRGB(239, 242, 248),
    Muted = Color3.fromRGB(151, 161, 178),

    Green = Color3.fromRGB(102, 214, 162),
    Red = Color3.fromRGB(232, 112, 123)
}

local FONT = Enum.Font.Gotham
local FONT_BOLD = Enum.Font.GothamBold

local function create(class, props, radius)
    local object = Instance.new(class)

    for key, value in pairs(props) do
        object[key] = value
    end

    if radius then
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, radius)
        corner.Parent = object
    end

    return object
end

local function addStroke(parent)
    return create("UIStroke", {
        Color = THEME.Border,
        Thickness = 1,
        Parent = parent
    })
end

local gui = create("ScreenGui", {
    Name = "BSSAAutofarm",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Global,
    Parent = CoreGui
})

local main = create("Frame", {
    Size = UDim2.fromOffset(CFG.WindowWidth, CFG.WindowHeight),
    Position = UDim2.new(0.5, 0, 0.4, 0),
    AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundColor3 = THEME.Background,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Parent = gui
}, 8)

addStroke(main)

local header = create("Frame", {
    Size = UDim2.new(1, 0, 0, 43),
    BackgroundColor3 = THEME.Sidebar,
    BorderSizePixel = 0,
    Parent = main
})

create("Frame", {
    Size = UDim2.fromOffset(3, 20),
    Position = UDim2.fromOffset(14, 11),
    BackgroundColor3 = THEME.Accent,
    BorderSizePixel = 0,
    Parent = header
}, 2)

create("TextLabel", {
    Size = UDim2.fromOffset(150, 43),
    Position = UDim2.fromOffset(26, 0),
    BackgroundTransparency = 1,
    Text = "BSSA HUB",
    TextSize = 15,
    Font = FONT_BOLD,
    TextColor3 = THEME.Text,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = header
})

create("TextLabel", {
    Size = UDim2.fromOffset(70, 23),
    Position = UDim2.new(1, -83, 0.5, -11),
    BackgroundColor3 = THEME.Control,
    Text = "RCtrl",
    TextSize = 11,
    Font = FONT,
    TextColor3 = THEME.Muted,
    Parent = header
}, 4)

local sidebar = create("Frame", {
    Size = UDim2.new(0, 118, 1, -69),
    Position = UDim2.fromOffset(0, 43),
    BackgroundColor3 = THEME.Sidebar,
    BorderSizePixel = 0,
    Parent = main
})

local sideList = create("Frame", {
    Size = UDim2.new(1, -14, 1, -16),
    Position = UDim2.fromOffset(7, 8),
    BackgroundTransparency = 1,
    Parent = sidebar
})

create("UIListLayout", {
    Padding = UDim.new(0, 5),
    SortOrder = Enum.SortOrder.LayoutOrder,
    Parent = sideList
})

local content = create("Frame", {
    Size = UDim2.new(1, -118, 1, -69),
    Position = UDim2.fromOffset(118, 43),
    BackgroundTransparency = 1,
    Parent = main
})

local footer = create("Frame", {
    Size = UDim2.new(1, 0, 0, 26),
    Position = UDim2.new(0, 0, 1, -26),
    BackgroundColor3 = THEME.Sidebar,
    BorderSizePixel = 0,
    Parent = main
})

local statusDot = create("Frame", {
    Size = UDim2.fromOffset(6, 6),
    Position = UDim2.new(0, 12, 0.5, -3),
    BackgroundColor3 = THEME.Accent,
    Parent = footer
}, 6)

local statusLabel = create("TextLabel", {
    Size = UDim2.new(1, -155, 1, 0),
    Position = UDim2.fromOffset(25, 0),
    BackgroundTransparency = 1,
    Text = State.status,
    TextSize = 11,
    Font = FONT,
    TextColor3 = THEME.Muted,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = footer
})

create("TextLabel", {
    Size = UDim2.fromOffset(125, 26),
    Position = UDim2.new(1, -136, 0, 0),
    BackgroundTransparency = 1,
    Text = "@" .. Player.Name,
    TextSize = 10,
    Font = FONT,
    TextColor3 = THEME.Muted,
    TextXAlignment = Enum.TextXAlignment.Right,
    Parent = footer
})

setStatus = function(message)
    State.status = message
    statusLabel.Text = message

    if message:lower():find("error")
        or message:lower():find("stalled") then
        statusDot.BackgroundColor3 = THEME.Red
    elseif State.farm or State.sprout or State.mobFarm then
        statusDot.BackgroundColor3 = THEME.Green
    else
        statusDot.BackgroundColor3 = THEME.Accent
    end
end

local tabs = {}

local function switchTab(name)
    for tabName, data in pairs(tabs) do
        local selected = tabName == name

        data.page.Visible = selected
        data.indicator.Visible = selected
        data.button.BackgroundColor3 = selected
            and THEME.Control or THEME.Sidebar

        data.button.TextColor3 = selected
            and THEME.Text or THEME.Muted
    end
end

local function addTab(name, order)
    local button = create("TextButton", {
        Size = UDim2.new(1, 0, 0, 34),
        LayoutOrder = order,
        BackgroundColor3 = THEME.Sidebar,
        AutoButtonColor = false,
        Text = "   " .. name,
        TextSize = 12,
        Font = FONT,
        TextColor3 = THEME.Muted,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = sideList
    }, 4)

    local indicator = create("Frame", {
        Size = UDim2.fromOffset(3, 18),
        Position = UDim2.new(0, 0, 0.5, -9),
        BackgroundColor3 = THEME.Accent,
        Visible = false,
        Parent = button
    }, 2)

    local page = create("Frame", {
        Size = UDim2.new(1, -20, 1, -20),
        Position = UDim2.fromOffset(10, 10),
        BackgroundTransparency = 1,
        Visible = false,
        Parent = content
    })

    tabs[name] = {
        button = button,
        indicator = indicator,
        page = page
    }

    connect(button.MouseButton1Click, function()
        switchTab(name)
    end)

    return page
end

local homePage = addTab("Home", 1)
local farmPage = addTab("Farming", 2)
local mobPage = addTab("Mob Farm", 3)
local tpPage = addTab("Teleports", 5)
local miscPage = addTab("Misc", 6)

switchTab("Home")

local function makePanel(parent)
    local panel = create("ScrollingFrame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = THEME.Panel,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Parent = parent
    }, 5)

    create("UIPadding", {
        PaddingTop = UDim.new(0, 11),
        PaddingBottom = UDim.new(0, 11),
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
        Parent = panel
    })

    create("UIListLayout", {
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = panel
    })

    return panel
end

local function makeColumns(parent)
    local leftHolder = create("Frame", {
        Size = UDim2.new(0.5, -5, 1, 0),
        BackgroundTransparency = 1,
        Parent = parent
    })

    local rightHolder = create("Frame", {
        Size = UDim2.new(0.5, -5, 1, 0),
        Position = UDim2.new(0.5, 5, 0, 0),
        BackgroundTransparency = 1,
        Parent = parent
    })

    return makePanel(leftHolder), makePanel(rightHolder)
end

local homePanel = makePanel(homePage)
local farmLeft, farmRight = makeColumns(farmPage)
local mobPanel = makePanel(mobPage)
local tpLeft, tpRight = makeColumns(tpPage)
local miscPanel = makePanel(miscPage)

-- ============================================================
-- PART 7: CONTROLS & FARM SETTINGS
-- ============================================================

local function heading(parent, title, order)
    return create("TextLabel", {
        Size = UDim2.new(1, 0, 0, 22),
        LayoutOrder = order,
        BackgroundTransparency = 1,
        Text = title,
        TextSize = 12,
        Font = FONT_BOLD,
        TextColor3 = THEME.Muted,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = parent
    })
end

local function infoRow(parent, text, order)
    local frame = create("Frame", {
        Size = UDim2.new(1, 0, 0, 34),
        LayoutOrder = order,
        BackgroundColor3 = THEME.Control,
        BorderSizePixel = 0,
        Parent = parent
    }, 4)

    return create("TextLabel", {
        Size = UDim2.new(1, -18, 1, 0),
        Position = UDim2.fromOffset(9, 0),
        BackgroundTransparency = 1,
        Text = text,
        TextSize = 12,
        Font = FONT,
        TextColor3 = THEME.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = frame
    })
end

local function makeButton(parent, title, order, callback)
    local button = create("TextButton", {
        Size = UDim2.new(1, 0, 0, 34),
        LayoutOrder = order,
        BackgroundColor3 = THEME.Control,
        AutoButtonColor = false,
        Text = "  " .. title,
        TextSize = 12,
        Font = FONT,
        TextColor3 = THEME.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = parent
    }, 4)

    connect(button.MouseEnter, function()
        button.BackgroundColor3 = THEME.Hover
    end)

    connect(button.MouseLeave, function()
        button.BackgroundColor3 = THEME.Control
    end)

    connect(button.MouseButton1Click, function()
        callback(button)
    end)

    return button
end

local function makeToggle(parent, title, order, callback)
    local enabled = false

    local button = create("TextButton", {
        Size = UDim2.new(1, 0, 0, 35),
        LayoutOrder = order,
        BackgroundColor3 = THEME.Control,
        AutoButtonColor = false,
        Text = "",
        Parent = parent
    }, 4)

    create("TextLabel", {
        Size = UDim2.new(1, -55, 1, 0),
        Position = UDim2.fromOffset(9, 0),
        BackgroundTransparency = 1,
        Text = title,
        TextSize = 12,
        Font = FONT,
        TextColor3 = THEME.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = button
    })

    local track = create("Frame", {
        Size = UDim2.fromOffset(34, 18),
        Position = UDim2.new(1, -43, 0.5, -9),
        BackgroundColor3 = THEME.Border,
        Parent = button
    }, 10)

    local knob = create("Frame", {
        Size = UDim2.fromOffset(12, 12),
        Position = UDim2.fromOffset(3, 3),
        BackgroundColor3 = THEME.Text,
        Parent = track
    }, 7)

    local function set(value)
        enabled = value

        track.BackgroundColor3 = enabled
            and THEME.Accent or THEME.Border

        knob.Position = enabled
            and UDim2.fromOffset(19, 3)
            or UDim2.fromOffset(3, 3)
    end

    connect(button.MouseButton1Click, function()
        set(not enabled)
        callback(enabled)
    end)

    return set
end

local openDropdowns = {}

local function makeDropdown(parent, title, order, items, callback)
    local wrapper = create("Frame", {
        Size = UDim2.new(1, 0, 0, 35),
        LayoutOrder = order,
        BackgroundColor3 = THEME.Control,
        ClipsDescendants = true,
        Parent = parent
    }, 4)

    local header = create("TextButton", {
        Size = UDim2.new(1, 0, 0, 35),
        BackgroundTransparency = 1,
        Text = "",
        Parent = wrapper
    })

    local label = create("TextLabel", {
        Size = UDim2.new(1, -33, 1, 0),
        Position = UDim2.fromOffset(9, 0),
        BackgroundTransparency = 1,
        Text = title .. ": None",
        TextSize = 12,
        Font = FONT,
        TextColor3 = THEME.Text,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = header
    })

    local arrow = create("TextLabel", {
        Size = UDim2.fromOffset(25, 35),
        Position = UDim2.new(1, -28, 0, 0),
        BackgroundTransparency = 1,
        Text = "v",
        TextSize = 12,
        Font = FONT_BOLD,
        TextColor3 = THEME.Muted,
        Parent = header
    })

    local scroll = create("ScrollingFrame", {
        Size = UDim2.new(1, -6, 0, 135),
        Position = UDim2.fromOffset(3, 37),
        BackgroundColor3 = THEME.Sidebar,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Parent = wrapper
    }, 3)

    create("UIListLayout", {
        Padding = UDim.new(0, 2),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = scroll
    })

    local opened = false

    local function setOpen(value)
        opened = value
        wrapper.Size = UDim2.new(1, 0, 0, value and 174 or 35)
        arrow.Text = value and "^" or "v"
    end

    openDropdowns[#openDropdowns + 1] = setOpen

    connect(header.MouseButton1Click, function()
        local nextState = not opened

        for _, close in ipairs(openDropdowns) do
            close(false)
        end

        setOpen(nextState)
    end)

    for index, item in ipairs(items) do
        local name, cf = item[1], item[2]

        local option = create("TextButton", {
            Size = UDim2.new(1, -3, 0, 27),
            LayoutOrder = index,
            BackgroundColor3 = THEME.Control,
            AutoButtonColor = false,
            Text = "  " .. name,
            TextSize = 11,
            Font = FONT,
            TextColor3 = THEME.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = scroll
        }, 3)

        connect(option.MouseButton1Click, function()
            label.Text = title .. ": " .. name
            setOpen(false)
            callback(name, cf)
        end)
    end
end

heading(farmLeft, "AUTO FARM", 1)

makeDropdown(farmLeft, "Field", 2, buildFields(), function(name, cf)
    State.fieldName = name
    State.field = cf

    resetTokenTracking()
    resetFarmTargets()

    if State.farm and not State.busy then
        teleport(cf)
    end

    setStatus("Selected " .. name)
end)

local setFarmVisual
local setSproutVisual

setFarmVisual = makeToggle(farmLeft, "Autofarm", 3, function(value)
    if value and not State.field then
        State.farm = false
        State.convert = false
        setFarmVisual(false)
        setStatus("Select a field first")
        return
    end

    if value then
        State.mobFarm = false
        mobAbortTarget()
        for _, item in ipairs(Mob.items) do item.enabled = false end
        if Mob.refreshVisuals then Mob.refreshVisuals() end
    end
    State.farm = value
    State.convert = value

    if value then
        State.sprout = false

        if setSproutVisual then
            setSproutVisual(false)
        end

        resetTokenTracking()
        resetFarmTargets()
        teleport(State.field)

        setStatus("Farming " .. State.fieldName)
    else
        setStatus("Ready")
    end
end)

makeToggle(farmLeft, "Auto Dig", 4, function(value)
    State.dig = value
end)

local hphLabel = infoRow(farmLeft, "Honey / Hour: Off", 5)

local conversionLabel = infoRow(farmLeft, "Hive Conversions: 0", 6)

makeToggle(farmLeft, "Gumdrop Spam", 7, function(value)
    State.autoGumdrop = value
end)

makeToggle(farmLeft, "Target Scopes", 8, function(value)
    State.targetScopes = value
    if State.resetScopeTarget then State.resetScopeTarget() end
end)

task.spawn(function()
    while State.active do
        if State.autoGumdrop and not State.planterBusy then
            local fields = Workspace:FindFirstChild("Fields")
            local name = State.sprout and State.sproutFieldName or State.fieldName or "Spider Field"
            local field = fields and fields:FindFirstChild(name)
            local box = field and field:FindFirstChild("FieldBox")
            local remotes = RS:FindFirstChild("Remotes")
            local remote = remotes and remotes:FindFirstChild("UseItem")
            if box and remote then
                pcall(function() remote:FireServer("Gumdrops", box) end)
            end
        end
        task.wait(1)
    end
end)


-- Manual instant converter controls (local estimated cooldowns).
do
    heading(farmLeft, "INSTANT CONVERTERS", 9)
    local converters = {
        {name = "Instant Converter", label = "Converter 0"},
        {name = "Instant Converter1", label = "Converter 1"},
        {name = "Instant Converter2", label = "Converter 2"},
        {name = "Instant Converter3", label = "Converter 3"},
    }
    local function refresh(item)
        local remaining = math.max(0, math.ceil(item.readyAt - os.clock()))
        item.button.Text = "  " .. item.label .. " | " .. (remaining > 0
            and string.format("%d:%02d", math.floor(remaining / 60), remaining % 60)
            or "Use (1 ticket)")
        item.button.TextColor3 = remaining > 0 and THEME.Muted or THEME.Text
    end
    local nextAttempt = 0
    local pendingUntil = 0
    local function useConverter(item)
        local now = os.clock()
        if not State.active or now < item.readyAt or now < pendingUntil then return false end
        local remotes = RS:FindFirstChild("Remotes")
        local remote = remotes and remotes:FindFirstChild("UseMachine")
        if not remote or not remote:IsA("RemoteEvent") then return false end
        local ok = pcall(function() remote:FireServer(item.name, 0) end)
        if ok then
            item.readyAt = now + 180
            pendingUntil = now + 2
            refresh(item)
        end
        return ok
    end
    for i, item in ipairs(converters) do
        item.readyAt = 0
        item.button = makeButton(farmLeft, item.label, 9 + i, function()
            useConverter(item)
        end)
        refresh(item)
    end
    makeToggle(farmLeft, "Auto Instant Convert (99%)", 15, function(value)
        State.autoInstantConvert = value
    end)
    task.spawn(function()
        while State.active do
            local now = os.clock()
            if State.autoInstantConvert and State.farm and not State.busy
                and not State.planterBusy and now >= pendingUntil and now >= nextAttempt then
                nextAttempt = now + 0.25
                local available
                for _, item in ipairs(converters) do
                    if now >= item.readyAt then available = item; break end
                end
                if available then
                    local current, maximum = readPollen()
                    if current and maximum and maximum > 0 and current / maximum >= 0.99 then
                        useConverter(available)
                    end
                end
            end
            task.wait(0.1)
        end
    end)
    infoRow(farmLeft, "Cooldowns: local estimates", 14)
    task.spawn(function()
        while State.active do
            for _, item in ipairs(converters) do refresh(item) end
            task.wait(0.25)
        end
    end)
end

-- Spider Field Dice automation. Kept separate from the manual Misc dice button.
do
    local boostEnabled = false
    local refreshAt = 90
    local boostStatus = infoRow(farmLeft, "Spider Boost: Off", 22)

    heading(farmLeft, "SPIDER FIELD BOOST", 17)
    makeToggle(farmLeft, "Auto Spider Boost", 18, function(value)
        boostEnabled = value
        boostStatus.Text = value and "Spider Boost: Starting..." or "Spider Boost: Off"
    end)

    local function numberSetting(label, order, initial, minimum, maximum, onValid)
        local frame = create("Frame", {
            Size = UDim2.new(1, 0, 0, 35), LayoutOrder = order,
            BackgroundColor3 = THEME.Control, BorderSizePixel = 0, Parent = farmLeft
        }, 4)
        create("TextLabel", {
            Size = UDim2.new(1, -87, 1, 0), Position = UDim2.fromOffset(9, 0),
            BackgroundTransparency = 1, Text = label, TextSize = 11,
            Font = FONT, TextColor3 = THEME.Text,
            TextXAlignment = Enum.TextXAlignment.Left, Parent = frame
        })
        local box = create("TextBox", {
            Size = UDim2.fromOffset(68, 25), Position = UDim2.new(1, -76, .5, -12),
            BackgroundColor3 = THEME.Panel, BorderSizePixel = 0,
            Text = tostring(initial), ClearTextOnFocus = false,
            TextSize = 12, Font = FONT, TextColor3 = THEME.Text,
            Parent = frame
        }, 4)
        connect(box.FocusLost, function()
            local parsed = tonumber(box.Text)
            if parsed then onValid(math.clamp(math.floor(parsed), minimum, maximum)) end
            box.Text = tostring(onValid())
        end)
    end
    numberSetting("Refresh at (seconds)", 18, refreshAt, 15, 180, function(v)
        if v then refreshAt = v end
        return refreshAt
    end)

    local function readBoost()
        local gui = Player:FindFirstChild("PlayerGui")
        local mainGui = gui and gui:FindFirstChild("Main")
        local buffs = mainGui and mainGui:FindFirstChild("Buffs")
        local buff = buffs and buffs:FindFirstChild("Spider Field Boost")
        if not buff then return 0, 0 end
        local stack = buff:FindFirstChild("Stack")
        local time = buff:FindFirstChild("Time")
        if not stack or not time or not stack:IsA("ValueBase") or not time:IsA("ValueBase") then
            return nil, nil
        end
        return tonumber(stack.Value), tonumber(time.Value)
    end

    task.spawn(function()
        local lastStatus = ""
        local nextRoll = 0
        while State.active do
            local label = "Off"
            if boostEnabled then
                local inventory = Player:FindFirstChild("Inventory")
                local dice = inventory and inventory:FindFirstChild("Field Dice")
                local fields = Workspace:FindFirstChild("Fields")
                local spider = fields and fields:FindFirstChild("Spider Field")
                local fieldBox = spider and spider:FindFirstChild("FieldBox")
                local remotes = RS:FindFirstChild("Remotes")
                local useItem = remotes and remotes:FindFirstChild("UseItem")
                local stack, seconds = readBoost()
                local count = dice and tonumber(dice.Value)

                if not State.farm or State.fieldName ~= "Spider Field" then
                    label = "Waiting for Spider Auto Farm"
                elseif not count or not fieldBox or not useItem or stack == nil then
                    label = "Waiting for game data"
                elseif stack >= 2 and seconds > refreshAt then
                    label = string.format("x2 active | %ds | %d dice", math.ceil(seconds), count)
                elseif count <= 0 then
                    label = "Out of Field Dice"
                else
                    label = stack >= 2 and "Refreshing x2" or ("Building x2 (stack " .. tostring(stack) .. ")")
                    if os.clock() >= nextRoll then
                        local beforeCount = count
                        local beforeStack, beforeTime = stack, seconds
                        local ok = pcall(function()
                            useItem:FireServer("Field Dice", fieldBox)
                        end)
                        -- Rapid but acknowledged rolls: normally ~0.2s, with a
                        -- 0.65s cap for slower server/inventory replication.
                        if ok then
                            local deadline = os.clock() + 0.65
                            repeat
                                task.wait(0.06)
                                local newStack, newTime = readBoost()
                                local newCount = tonumber(dice.Value)
                                if newCount and newCount < beforeCount then break end
                                if newStack and newStack > beforeStack then break end
                                if beforeStack >= 2 and newTime and
                                    newTime > beforeTime + 30 then break end
                            until not State.active or not boostEnabled or os.clock() >= deadline
                            nextRoll = os.clock() + 0.12
                        else
                            nextRoll = os.clock() + 1.5
                            label = "Dice remote unavailable; retrying"
                        end
                    end
                end
            end
            if label ~= lastStatus then
                boostStatus.Text = "Spider Boost: " .. label
                lastStatus = label
            end
            task.wait(0.08)
        end
    end)
end

-- Visual-only token ESP: invisible, non-colliding sizing proxies keep the
-- wireframe slightly larger than the real parts without changing game objects.
do
    local tokenBoxes = {}
    local espFolder = Instance.new("Folder")
    espFolder.Name = "BSSA_ESP_Visuals"
    espFolder.Parent = Workspace

    local function removeEntry(token)
        local entry = tokenBoxes[token]
        if entry then
            if entry.box then entry.box:Destroy() end
            if entry.proxy then entry.proxy:Destroy() end
            tokenBoxes[token] = nil
        end
    end

    local function clearBoxes()
        for token in pairs(tokenBoxes) do
            removeEntry(token)
        end
    end

    local function makeBox(part)
        if not part or not part:IsA("BasePart") or not part.Parent then
            return nil
        end
        local proxy = Instance.new("Part")
        proxy.Name = "BSSA_ESP_Visual_Only"
        proxy.Anchored = true
        proxy.CanCollide = false
        proxy.CanTouch = false
        proxy.CanQuery = false
        proxy.Transparency = 1
        proxy.CastShadow = false
        proxy.Size = part.Size + Vector3.new(0.35, 0.35, 0.35)
        proxy.CFrame = part.CFrame
        proxy.Parent = espFolder

        local box = Instance.new("SelectionBox")
        box.Name = "BSSA_ESP_Box"
        box.Adornee = proxy
        box.Color3 = Color3.fromRGB(255, 25, 25)
        box.SurfaceTransparency = 1
        box.LineThickness = 0.12
        box.Parent = gui
        return {part = part, proxy = proxy, box = box}
    end

    local function tokenEligible(token)
        return (token.Name == "All" or token.Name == Player.Name)
            and not shouldSkipToken(token)
    end

    local function syncBoxes()
        for _, token in ipairs(Tokens:GetChildren()) do
            if tokenEligible(token) then
                local part = token:FindFirstChild("Token")
                if not (part and part:IsA("BasePart")) then part = nil end
                local entry = tokenBoxes[token]
                if not part then
                    removeEntry(token)
                else
                    if not entry or entry.part ~= part or not entry.box.Parent then
                        removeEntry(token)
                        entry = makeBox(part)
                        tokenBoxes[token] = entry
                    end
                    if entry then
                        entry.proxy.Size = part.Size + Vector3.new(0.35, 0.35, 0.35)
                    end
                end
            end
        end
        for token, entry in pairs(tokenBoxes) do
            if token.Parent ~= Tokens or not tokenEligible(token)
                or not entry.part.Parent then
                removeEntry(token)
            end
        end
    end

    -- Follow token rotation every rendered frame for smooth outlines.
    connect(RunService.RenderStepped, function()
        if not State.active then return end
        for token, entry in pairs(tokenBoxes) do
            if token.Parent ~= Tokens or not entry.part:IsDescendantOf(token)
                or not entry.proxy.Parent then
                removeEntry(token)
            else
                entry.proxy.CFrame = entry.part.CFrame
            end
        end
    end)

    -- Remove the box immediately when the token leaves its container.
    connect(Tokens.ChildRemoved, function(token)
        removeEntry(token)
    end)

    task.spawn(function()
        while State.active do
            syncBoxes()
            task.wait(0.2)
        end
        clearBoxes()
        espFolder:Destroy()
    end)
end

-- Soldier Scope tracker: count distinct flowers, not individual emitters.
do
    heading(miscPanel, "SOLDIER SCOPE TRACKER", 23)
    local currentLabel = infoRow(miscPanel, "Current Active Scopes: --", 24)
    local averageLabel = infoRow(miscPanel, "Average Active Scopes: --", 25)

    local purple = Color3.fromRGB(176, 38, 255)
    local emitters, flowers = {}, {}
    local field, addedConnection, removedConnection
    local count, area, elapsed = 0, 0, 0
    local trackedField
    local last = os.clock()

    -- Scope targeting is independent of the display and only runs when enabled.
    local target, targetField, nextScore = nil, nil, 0
    local depleted = setmetatable({}, {__mode = "k"})
    local radiusSquared = 100 -- 10 studs, horizontal cluster radius
    State.resetScopeTarget = function()
        target, targetField, nextScore = nil, nil, 0
    end
    State.scopeAnchor = function()
        if not State.targetScopes or not State.farm or State.sprout then return nil end
        local fields = Workspace:FindFirstChild("Fields")
        local selected = fields and State.fieldName and fields:FindFirstChild(State.fieldName)
        if not selected then return State.field end
        if selected ~= targetField then
            target, targetField, nextScore = nil, selected, 0
        end
        local function valid(part)
            if not part or not part:IsDescendantOf(selected) then return false end
            local y = part.Position.Y
            if y <= 84.0 then depleted[part] = true end
            if y >= 84.5 then depleted[part] = nil end
            if depleted[part] then return false end
            if field and selected:IsDescendantOf(field) then return flowers[part] ~= nil and flowers[part].purple ~= nil end
            for _, obj in ipairs(part:GetDescendants()) do
                if obj.Name == "ToF_MarkFlower" and obj:IsA("ParticleEmitter") then return true end
            end
            return false
        end
        local now = os.clock()
        if (target and not valid(target)) or now >= nextScore then
            local candidates, seen = {}, {}
            if field and selected:IsDescendantOf(field) then
                for part in pairs(flowers) do
                    if valid(part) then candidates[#candidates + 1] = part end
                end
            else
                for _, obj in ipairs(selected:GetDescendants()) do
                    if obj.Name == "ToF_MarkFlower" and obj:IsA("ParticleEmitter") then
                        local part = obj:FindFirstAncestor("FlowerPart")
                        if part and part:IsA("BasePart") and not seen[part] and valid(part) then
                            seen[part] = true
                            candidates[#candidates + 1] = part
                        end
                    end
                end
            end
            local function score(part)
                local n = 0
                for _, other in ipairs(candidates) do
                    local d = part.Position - other.Position
                    if d.X*d.X + d.Z*d.Z <= radiusSquared then n += 1 end
                end
                return n
            end
            local function tier(part)
                local amount = part and part:FindFirstChild("Amnt")
                return amount and amount:IsA("IntValue") and amount.Value or 0
            end
            local best, bestTier, bestScore, bestDistance = nil, -1, -1, math.huge
            for _, part in ipairs(candidates) do
                local t = tier(part)
                local n = score(part)
                local d = distanceSquared(part.Position, State.field.Position)
                if t > bestTier or (t == bestTier and
                    (n > bestScore or (n == bestScore and d < bestDistance))) then
                    best, bestTier, bestScore, bestDistance = part, t, n, d
                end
            end
            if not valid(target) or (best and (bestTier > tier(target)
                or (bestTier == tier(target) and bestScore >= score(target) + 2))) then
                target = best
            end
            nextScore = now + 0.5
        end
        if not valid(target) then return State.field end
        return CFrame.new(target.Position.X,
            target.Position.Y + target.Size.Y * 0.5 + getStandOffset() - 0.5,
            target.Position.Z)
    end

    local function integrate()
        local now = os.clock()
        if trackedField then
            local dt = now - last
            area += count * dt
            elapsed += dt
        end
        last = now
    end

    local function refresh()
        currentLabel.Text = "Current Purple Scopes: " .. (trackedField and tostring(count) or "--")
        averageLabel.Text = elapsed > 0 and string.format("Average Purple Scopes: %.2f", area / elapsed)
            or "Average Active Scopes: --"
    end

    local function add(obj)
        if obj.Name ~= "ToF_MarkFlower" or not obj:IsA("ParticleEmitter") or emitters[obj] then return end
        local flower = obj:FindFirstAncestor("FlowerPart")
        if not flower or not flower:IsA("BasePart") or not flower:IsDescendantOf(field) then return end
        local kind = "purple"
        -- Local visual adjustment only; retain the original emitter lifetime.
        local original = {Enabled = obj.Enabled, Rate = obj.Rate, Transparency = obj.Transparency}
        obj.Enabled = false
        obj.Transparency = NumberSequence.new(1)
        obj:Clear()
        emitters[obj] = {flower = flower, kind = kind, original = original}
        local entries = flowers[flower] or {}
        flowers[flower] = entries
        if entries[kind] then
            entries[kind].refs += 1
            return
        end
        integrate()
        local box = Instance.new("SurfaceGui")
        box.Name = "BSSA_Scope_Visual_" .. kind
        box.Adornee = flower
        box.Face = Enum.NormalId.Top
        box.AlwaysOnTop = true
        box.LightInfluence = 0
        box.ZOffset = 1
        box.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
        box.CanvasSize = Vector2.new(100, 100)
        local fill = Instance.new("Frame")
        fill.Size = UDim2.fromScale(1, 1)
        fill.BackgroundColor3 = purple
        fill.BackgroundTransparency = 0.55
        fill.BorderSizePixel = 0
        fill.Parent = box
        local stroke = Instance.new("UIStroke")
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.Color = Color3.fromRGB(225,120,255)
        stroke.Thickness = 5
        stroke.Parent = fill
        box.Parent = flower
        entries[kind] = {refs = 1, box = box}
        if trackedField and flower:IsDescendantOf(trackedField) then count += 1 end
        refresh()
    end

    local function remove(obj)
        local record = emitters[obj]
        if not record then return end
        emitters[obj] = nil
        local entries = flowers[record.flower]
        local entry = entries and entries[record.kind]
        if not entry then return end
        entry.refs -= 1
        if entry.refs == 0 then
            integrate()
            entry.box:Destroy()
            entries[record.kind] = nil
            if not next(entries) then flowers[record.flower] = nil end
            if trackedField and record.flower:IsDescendantOf(trackedField) then count -= 1 end
            refresh()
        end
    end

    local function restoreParticles()
        for obj, record in pairs(emitters) do
            if obj.Parent and record.original then
                pcall(function()
                    for property, value in pairs(record.original) do obj[property] = value end
                end)
            end
        end
    end

    local function bindField(nextField)
        integrate()
        restoreParticles()
        if addedConnection then addedConnection:Disconnect() end
        if removedConnection then removedConnection:Disconnect() end
        for _, entries in pairs(flowers) do
            for _, entry in pairs(entries) do entry.box:Destroy() end
        end
        table.clear(flowers)
        table.clear(emitters)
        count = 0
        field = nextField
        last = os.clock()
        if field then
            addedConnection = connect(field.DescendantAdded, add)
            removedConnection = connect(field.DescendantRemoving, remove)
            for _, obj in ipairs(field:GetDescendants()) do add(obj) end
        end
        refresh()
    end

    task.spawn(function()
        while State.active do
            local fields = Workspace:FindFirstChild("Fields")
            local nextField = fields
            if nextField ~= field then bindField(nextField) end
            local selectedName = not State.mobFarm and (State.sprout and State.sproutFieldName or (State.farm and State.fieldName))
            local selected = fields and selectedName and fields:FindFirstChild(selectedName) or nil
            if selected ~= trackedField then
                trackedField = selected
                area, elapsed = 0, 0
                last = os.clock()
            else
                integrate()
            end
            -- Recount from the existing visual index, including only purple scopes in the selected field.
            count = 0
            if trackedField then
                for part, entries in pairs(flowers) do
                    if entries.purple and part:IsDescendantOf(trackedField) then count += 1 end
                end
            end
            refresh()
            task.wait(0.25)
        end
        restoreParticles()
        if addedConnection then addedConnection:Disconnect() end
        if removedConnection then removedConnection:Disconnect() end
        for _, entries in pairs(flowers) do
            for _, entry in pairs(entries) do entry.box:Destroy() end
        end
    end)
end

heading(farmRight, "SPROUT FARM", 1)

makeDropdown(
    farmRight,
    "Sprout Field",
    2,
    buildFields(),
    function(name, cf)
        State.sproutFieldName = name
        State.sproutField = cf

        resetTokenTracking()

        if State.sprout and not State.busy then
            teleport(cf)
        end

        setStatus("Sprout Field: " .. name)
    end
)

setSproutVisual = makeToggle(
    farmRight,
    "Sprout Farm",
    3,
    function(value)
        if value and not State.sproutField then
            State.sprout = false
            setSproutVisual(false)
            setStatus("Select a sprout field")
            return
        end

        if value then
            State.mobFarm = false
            mobAbortTarget()
            for _, item in ipairs(Mob.items) do item.enabled = false end
            if Mob.refreshVisuals then Mob.refreshVisuals() end
        end
        State.sprout = value

        if value then
            State.farm = false
            State.convert = false

            if setFarmVisual then
                setFarmVisual(false)
            end

            resetTokenTracking()
            resetFarmTargets()
            teleport(State.sproutField)

            setStatus("Sprout farming")
        else
            setStatus("Ready")
        end
    end
)

infoRow(farmRight, "Shared tokens only", 4)

-- ============================================================
-- MOB FARM CONTROLS
-- ============================================================
heading(mobPanel, "MOB ROTATION  |  Enable mobs individually", 1)
local mobInfo = infoRow(mobPanel, "Mob Farm: Off", 2)
local mobVisuals = {}
local function setMobEnabled(item, enabled)
    item.enabled = enabled
    if enabled then
        if not State.mobFarm then
            State.farm = false
            State.sprout = false
            State.convert = false
            if setFarmVisual then setFarmVisual(false) end
            if setSproutVisual then setSproutVisual(false) end
            resetTokenTracking()
            resetFarmTargets()
        end
        State.mobFarm = true
        item.retryAt = 0
    else
        if Mob.target == item then mobAbortTarget() end
        if mobEnabledCount() == 0 then
            State.mobFarm = false
            mobAbortTarget()
            Mob.status = "Idle"
            setStatus("Ready")
        end
    end
end

for index, item in ipairs(Mob.items) do
    local row = create("Frame", {
        Size=UDim2.new(1,0,0,35), LayoutOrder=index+2,
        BackgroundColor3=THEME.Control, BorderSizePixel=0,
        Parent=mobPanel
    }, 4)
    local toggle = create("TextButton", {
        Size=UDim2.new(0.62,0,1,0), BackgroundTransparency=1,
        Text="  " .. item.name, TextSize=12, Font=FONT,
        TextColor3=THEME.Text, TextXAlignment=Enum.TextXAlignment.Left,
        Parent=row
    })
    local timer = create("TextLabel", {
        Size=UDim2.new(0.22,0,1,0), Position=UDim2.new(0.62,0,0,0),
        BackgroundTransparency=1, Text="Checking", TextSize=11,
        Font=FONT, TextColor3=THEME.Muted,
        TextXAlignment=Enum.TextXAlignment.Right, Parent=row
    })
    local stateButton = create("TextButton", {
        Size=UDim2.fromOffset(45,24), Position=UDim2.new(1,-52,0.5,-12),
        BackgroundColor3=THEME.Border, Text="OFF", TextSize=10,
        Font=FONT_BOLD, TextColor3=THEME.Text, Parent=row
    }, 5)
    local function render()
        stateButton.Text = item.enabled and "ON" or "OFF"
        stateButton.BackgroundColor3 = item.enabled and THEME.Accent or THEME.Border
    end
    mobVisuals[item] = {render=render, timer=timer}
    local function flip()
        setMobEnabled(item, not item.enabled)
        render()
    end
    connect(toggle.MouseButton1Click, flip)
    connect(stateButton.MouseButton1Click, flip)
end
Mob.refreshVisuals = function()
    for _, entry in pairs(mobVisuals) do entry.render() end
end

task.spawn(function()
    while State.active do
        task.wait(0.25)
        if not State.active then break end
        mobInfo.Text = State.mobFarm and
            ("Mob Farm: " .. mobEnabledCount() .. " enabled | " .. Mob.status)
            or "Mob Farm: Off"
        for item, visual in pairs(mobVisuals) do
            local remaining = mobRemaining(item)
            if item.known and remaining > 0 then
                visual.timer.Text = string.format("%02d:%02d", math.floor(remaining/60), remaining%60)
                visual.timer.TextColor3 = THEME.Muted
            elseif os.clock() < item.retryAt then
                visual.timer.Text = "Checking"
                visual.timer.TextColor3 = THEME.Muted
            elseif item.known then
                visual.timer.Text = "Ready*"
                visual.timer.TextColor3 = THEME.Green
            else
                visual.timer.Text = "Unknown"
                visual.timer.TextColor3 = THEME.Muted
            end
        end
    end
end)

-- ============================================================
-- AUTO PLANTERS: independent background controller
-- ============================================================
do
    local planters = {
        {name="Paper Planter", field="Blueberry Field", wax="Hard Wax", duration=1800},
        {name="Plastic Planter", field="Pineapple Field", wax="Swirled Wax", duration=3600}
    }
    local inventory, inventoryAt = nil, -math.huge
    local retrySeconds = 20
    local collectionSeconds = 10
    local harvestSafetySeconds = 10
    local harvestRetrySeconds = 5
    local collectionRadiusSq = 35 * 35
    local function planterValue(model, name)
        local obj = model:FindFirstChild(name)
        if obj and obj:IsA("ValueBase") then return obj.Value end
        return nil
    end
    local function ownerStatus(model)
        local owner = planterValue(model, "Player")
        if owner == nil or owner == "" then return nil end
        if typeof(owner) == "Instance" then
            if not owner:IsA("Player") then return nil end
            return owner == Player
        end
        if type(owner) == "number" then
            if owner <= 0 then return nil end
            return owner == Player.UserId
        end
        if type(owner) == "string" then return owner == Player.Name end
        return nil
    end
    local function scanPlanterRaw(item)
        local folder = Workspace:FindFirstChild("Planters")
        if not folder then return nil, "Waiting for planters" end
        local own, occupied, uncertain = nil, false, false
        for _, model in ipairs(folder:GetChildren()) do
            local owner = ownerStatus(model)
            if owner == true then
                local field = planterValue(model, "Field")
                if model.Name == item.name then
                    if own then return nil, "Multiple matching planters" end
                    own = model
                elseif field == item.field then
                    occupied = true
                elseif field == nil or field == "" then
                    uncertain = true
                end
            elseif owner == nil and model.Name == item.name then
                uncertain = true
            end
        end
        if own then
            local field = planterValue(own, "Field")
            if type(field) ~= "string" or field == "" then
                return own, "Checking field"
            end
            if field ~= item.field then
                return own, "Planter is placed in another field"
            end
            local level = tonumber(planterValue(own, "Level"))
            if not level or level < 0 or level > 100 then
                return own, "Checking growth"
            end
            if level == 100 then return own, "Ready to harvest", level end
            return own, "Growing", level
        end
        if uncertain then return nil, "Checking planter ownership" end
        if occupied then return nil, "Field occupied" end
        return nil, "Not planted"
    end
    local function scanPlanter(item)
        local model, status, level = scanPlanterRaw(item)
        if status ~= "Ready to harvest" or not item.enabled then
            item.readyModel, item.readySince = nil, nil
            return model, status, level
        end
        local now = os.clock()
        if item.readyModel ~= model or not item.readySince then
            item.readyModel, item.readySince = model, now
        end
        local remaining = harvestSafetySeconds - (now - item.readySince)
        if remaining > 0 then
            return model, "Harvest safety: " .. math.ceil(remaining) .. "s", level
        end
        return model, status, level
    end
    -- Display-only ETA: measure actual growth, then use a fixed deadline.
    -- Never use this estimate to decide whether a planter is ready to harvest.
    local function planterCountdown(item, model, level, now)
        if not model then
            item.eta = nil
            return "Growth: --"
        end
        if level == nil then return "Growth: --" end
        local eta = item.eta
        if not eta or eta.model ~= model or level < eta.lastLevel then
            eta = {model=model, lastLevel=level}
            -- Reuse the measured rate from a previous cycle, if available.
            if item.secondsPerPercent then
                eta.deadline = now + (100-level)*item.secondsPerPercent
            end
            item.eta = eta
        end
        if level > eta.lastLevel then
            if not eta.sampleAt then
                -- Start at an observed level change, not an arbitrary fraction
                -- of a growth step when the hub was opened.
                eta.sampleAt, eta.sampleLevel = now, level
            else
                local gain = level - eta.sampleLevel
                local elapsed = now - eta.sampleAt
                if gain >= 2 and elapsed >= 10 then
                    local rate = elapsed / gain
                    item.secondsPerPercent = rate
                    -- Calibrate only once per countdown. Later observations
                    -- improve the estimate for the next planter, not this one.
                    if not eta.deadline then
                        eta.deadline = now + (100-level)*rate
                    end
                end
            end
            eta.lastLevel = level
        end
        if level >= 100 then
            return string.format("%.1f%% | 00:00", level)
        end
        if not eta.deadline then
            return string.format("%.1f%% | Calibrating", level)
        end
        local seconds = math.max(0, math.ceil(eta.deadline - now))
        if seconds == 0 then
            return string.format("%.1f%% | ETA overdue", level)
        end
        return string.format("%.1f%% | ~%02d:%02d", level,
            math.floor(seconds/60), seconds%60)
    end
    local function inventoryAmount(name)
        -- A missing item in a valid inventory means no stock. An unavailable
        -- inventory is unknown, not zero, and must not initiate placement.
        if not inventory or os.clock() - inventoryAt > 15 then return nil end
        local value = inventory[name]
        if value == nil then return 0 end
        local amount = tonumber(value)
        return amount and math.max(0, amount) or nil
    end
    task.spawn(function()
        while State.active do
            if State.planterEnabled then
                local remotes = RS:FindFirstChild("Remotes")
                local remote = remotes and remotes:FindFirstChild("GetData")
                if remote and remote:IsA("RemoteFunction") then
                    local ok, data = pcall(function() return remote:InvokeServer() end)
                    if State.active and ok and type(data) == "table"
                        and type(data.Inventory) == "table" then
                        inventory, inventoryAt = data.Inventory, os.clock()
                    end
                end
            end
            task.wait(3)
        end
    end)
    local function waitFor(seconds, predicate)
        local deadline = os.clock() + seconds
        repeat
            if not State.active or not getRoot() then return false end
            if predicate() then return true end
            task.wait(0.1)
        until os.clock() >= deadline
        return State.active and getRoot() ~= nil and predicate() or false
    end
    local function planterSoil(model)
        local soil = model and model:FindFirstChild("Soil")
        if soil and soil:IsA("BasePart") then return soil end
        return soil and soil:FindFirstChildWhichIsA("BasePart", true) or nil
    end
    local function collectRewards(origin, previousTokens)
        local deadline = os.clock() + collectionSeconds
        local retryAt = {}
        while State.active and getRoot() and os.clock() < deadline do
            local best, bestVisual, nearest
            local root = getRoot()
            if not root then break end
            for _, token in ipairs(Tokens:GetChildren()) do
                -- Only freshly spawned, player-specific tokens near the harvested
                -- planter. Do not use the autofarm's item exclusion filter here.
                if token.Name == Player.Name and not previousTokens[token] then
                    local hb, visual = tokenParts(token)
                    if tokenAlive(hb, visual)
                        and distanceSquared(hb.Position, origin) <= collectionRadiusSq
                        and (retryAt[hb] or 0) <= os.clock() then
                        local distance = distanceSquared(hb.Position, root.Position)
                        if not nearest or distance < nearest then
                            best, bestVisual, nearest = hb, visual, distance
                        end
                    end
                end
            end
            if best then
                local untilTime = math.min(deadline, os.clock() + CFG.TokenStay)
                repeat
                    if not State.active or not getRoot() or not tokenAlive(best, bestVisual) then break end
                    if not teleport(best.CFrame) then break end
                    touchToken(best)
                    RunService.Heartbeat:Wait()
                until os.clock() >= untilTime
                retryAt[best] = os.clock() + 0.35
            else
                task.wait(0.08)
            end
        end
    end
    -- Require a continuous settled interval on a real surface before using
    -- a consumable. Do not force the character down while physics is settling.
    local function settlePlanterPosition(item, cf, box, requireGround)
        local deadline = os.clock() + 5
        local stableSince, stableRoot, stablePosition
        while State.active and item.enabled and os.clock() < deadline do
            local root = getRoot()
            local character = Player.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            if not root or not humanoid or humanoid.Health <= 0 then return false end
            local pos = root.Position
            local valid = distanceSquared(pos, cf.Position) <= 16
                and root.AssemblyLinearVelocity.Magnitude <= 2
            if requireGround then
                valid = valid and box and box.Parent
                    and insideFieldBoxXZ(pos, box)
                    and humanoid.FloorMaterial ~= Enum.Material.Air
                if valid then
                    local params = RaycastParams.new()
                    params.FilterType = Enum.RaycastFilterType.Exclude
                    params.FilterDescendantsInstances = {character}
                    params.RespectCanCollide = true
                    local hit = Workspace:Raycast(pos, Vector3.new(0, -(getStandOffset() + 2), 0), params)
                    valid = hit ~= nil and hit.Normal.Y >= 0.5
                end
            end
            if valid then
                if stableRoot ~= root or not stablePosition
                    or distanceSquared(pos, stablePosition) > 0.25 then
                    stableSince, stableRoot, stablePosition = os.clock(), root, pos
                elseif os.clock() - stableSince >= 1 then
                    return true
                end
            else
                stableSince, stableRoot, stablePosition = nil, nil, nil
            end
            task.wait(0.1)
        end
        return false
    end
    local function place(item)
        if not item.enabled or not State.active or not getRoot() then return end
        local _, status = scanPlanter(item)
        if status ~= "Not planted" then return end
        local amount = inventoryAmount(item.name)
        if amount == nil then item.status = "Checking inventory" return end
        if amount <= 0 then item.status = "Out of planters" return end
        local fields = Workspace:FindFirstChild("Fields")
        local field = fields and fields:FindFirstChild(item.field)
        local box = field and field:FindFirstChild("FieldBox")
        local cf
        for _, entry in ipairs(buildFields()) do
            if entry[1] == item.field then cf = entry[2] break end
        end
        local remotes = RS:FindFirstChild("Remotes")
        local remote = remotes and remotes:FindFirstChild("UseItem")
        if not cf or not box or not box:IsA("BasePart") or not remote or not remote:IsA("RemoteEvent") then
            item.status, item.retryAt = "Placement unavailable", os.clock() + retrySeconds
            return
        end
        item.status = "Planting"
        setStatus("Planters: Planting " .. item.name)
        if not teleport(cf) then return end
        if not settlePlanterPosition(item, cf, box, true) then
            item.status, item.retryAt = "Waiting for stable ground", os.clock() + retrySeconds
            return
        end
        if not State.active or not item.enabled or not getRoot() then return end
        if (inventoryAmount(item.name) or 0) <= 0 then return end
        local _, checkStatus = scanPlanter(item)
        if checkStatus ~= "Not planted" then return end
        local root = getRoot()
        if not root or not box.Parent or not insideFieldBoxXZ(root.Position, box)
            or distanceSquared(root.Position, cf.Position) > 16 then
            item.status, item.retryAt = "Placement position changed", os.clock() + retrySeconds
            return
        end
        local sent = pcall(function() remote:FireServer(item.name, box) end)
        if sent and waitFor(4, function()
            local model, currentStatus = scanPlanter(item)
            return model ~= nil and planterValue(model, "Field") == item.field
                and currentStatus ~= "Planter is placed in another field"
        end) then
            item.status, item.retryAt = "Planted", 0
        else
            item.status, item.retryAt = "Placement failed - retry later", os.clock() + retrySeconds
        end
    end
    local function harvest(item, model)
        if not item.enabled or not State.active or not getRoot() then return end
        local soil = planterSoil(model)
        local remotes = RS:FindFirstChild("Remotes")
        local remote = remotes and remotes:FindFirstChild("ClaimPlanter")
        if not soil or not remote or not remote:IsA("RemoteEvent") then
            item.status, item.retryAt = "Harvest unavailable", os.clock() + retrySeconds
            return
        end
        local origin = soil.Position
        local cf = CFrame.new(origin.X, origin.Y + soil.Size.Y * 0.5 + getStandOffset(), origin.Z)
        item.status = "Harvesting"
        setStatus("Planters: Harvesting " .. item.name)
        if not teleport(cf) then return end
        if not settlePlanterPosition(item, cf, nil, false) then
            item.status, item.retryAt = "Harvest position unstable", os.clock() + harvestRetrySeconds
            return
        end
        if not State.active or not item.enabled or not getRoot() then return end
        -- Revalidate identity, exact field and exact 100% immediately before
        -- sending the claim. No fixed timer is ever allowed to trigger it.
        local current, status, level = scanPlanter(item)
        if current ~= model or status ~= "Ready to harvest" or level ~= 100 then return end
        if not soil.Parent then return end
        local root = getRoot()
        if not root or distanceSquared(root.Position, cf.Position) > 16 then
            item.status, item.retryAt = "Harvest position changed", os.clock() + harvestRetrySeconds
            return
        end
        local previousTokens = {}
        for _, token in ipairs(Tokens:GetChildren()) do previousTokens[token] = true end
        local sent = pcall(function() remote:FireServer(item.name) end)
        if not sent or not waitFor(4, function()
            return not model:IsDescendantOf(Workspace)
        end) then
            item.status, item.retryAt = "Harvest not confirmed", os.clock() + harvestRetrySeconds
            return
        end
        item.harvested += 1
        item.status = "Collecting rewards"
        setStatus("Planters: Collecting " .. item.name .. " rewards")
        collectRewards(origin, previousTokens)
        -- Complete an already-confirmed harvest even if its toggle was turned
        -- off mid-collection, but don't place another planter if disabled.
        if State.active and item.enabled and getRoot() then place(item) end
    end
    local page = addTab("Planters", 4)
    local left, right = makeColumns(page)
    for index, item in ipairs(planters) do
        local panel = index == 1 and left or right
        item.enabled, item.harvested, item.retryAt = false, 0, 0
        item.status = "Disabled"
        heading(panel, item.name:upper(), 1)
        infoRow(panel, item.field, 2)
        makeToggle(panel, "Auto " .. item.name, 3, function(value)
            item.enabled = value
            item.retryAt = 0
            item.readyModel, item.readySince = nil, nil
            item.status = value and "Checking" or "Disabled"
            State.planterEnabled = planters[1].enabled or planters[2].enabled or false
        end)
        item.growthLabel = infoRow(panel, "Growth: --", 4)
        item.stockLabel = infoRow(panel, "Inventory: --", 5)
        item.harvestLabel = infoRow(panel, "Harvested: 0", 6)
        item.waxLabel = infoRow(panel, item.wax .. ": --", 7)
        item.statusLabel = infoRow(panel, "Disabled", 8)
        item.statusLabel.TextWrapped = true
        item.statusLabel.TextSize = 11
    end
    local function eligible(item)
        if not item.enabled or os.clock() < item.retryAt then return false end
        local model, status = scanPlanter(item)
        if status == "Ready to harvest" then return true, model end
        if status == "Not planted" and (inventoryAmount(item.name) or 0) > 0 then return true end
        return false
    end
    task.spawn(function()
        while State.active do
            task.wait(0.25)
            if not State.active then break end
            for _, item in ipairs(planters) do
                local model, status, level = scanPlanter(item)
                local amount, wax = inventoryAmount(item.name), inventoryAmount(item.wax)
                item.stockLabel.Text = "Inventory: " .. (amount ~= nil and tostring(amount) or "--")
                item.waxLabel.Text = item.wax .. ": " .. (wax ~= nil and tostring(wax) or "--")
                item.harvestLabel.Text = "Harvested: " .. item.harvested
                item.growthLabel.Text = planterCountdown(item, model, level, os.clock())
                if State.planterItem ~= item then
                    if not item.enabled then item.status = "Disabled"
                    elseif os.clock() >= item.retryAt then
                        if status == "Not planted" then
                            if amount == nil then status = "Checking inventory"
                            elseif amount <= 0 then status = "Out of planters" end
                        end
                        if status == "Ready to harvest" and State.busy and not State.planterBusy then
                            status = "Waiting for conversion"
                        end
                        item.status = status
                    end
                end
                item.statusLabel.Text = item.status
            end
        end
    end)
    -- One worker owns movement throughout a planter batch. Existing conversion
    -- keeps its lock until it finishes. An active mob visit is cancelled without
    -- disabling its toggle; its normal controller will select again afterward.
    task.spawn(function()
        while State.active do
            task.wait(0.2)
            if State.active and State.planterEnabled and not State.busy and getRoot() then
                local due = false
                for _, item in ipairs(planters) do
                    if eligible(item) then due = true break end
                end
                if due then
                    State.planterBusy = true
                    State.planterThread = coroutine.running()
                    State.busy = true
                    if State.mobFarm then mobAbortTarget() end
                    -- Re-read all state under the lock. Prioritize fully grown
                    -- planters, then fill missing slots, at most once per batch.
                    local processed = {}
                    local ok, err = pcall(function()
                        for pass = 1, 2 do
                            for _, item in ipairs(planters) do
                                if not State.active or not getRoot() then return end
                                local yes, model = eligible(item)
                                if yes and not processed[item] and ((pass == 1 and model ~= nil) or (pass == 2 and model == nil)) then
                                    processed[item] = true
                                    State.planterItem = item
                                    local success, failure = pcall(function()
                                        if model then harvest(item, model) else place(item) end
                                    end)
                                    if not success then
                                        item.status, item.retryAt = "Planter action failed - retry later", os.clock() + retrySeconds
                                        warn("[BSSA] Planter action:", failure)
                                    end
                                    State.planterItem = nil
                                end
                            end
                        end
                    end)
                    -- Release the lock even if an action raises an error. Do
                    -- not restore a stale farm selection after a user changes it.
                    if not ok then warn("[BSSA] Planters:", err) end
                    State.planterItem = nil
                    if State.active then
                        pcall(function()
                            resetTokenTracking()
                            resetFarmTargets()
                            local anchor = currentAnchor()
                            if anchor then teleport(anchor) end
                        end)
                    end
                    State.planterThread = nil
                    State.planterBusy = false
                    State.busy = false
                    if State.active then
                        if State.farm then setStatus("Farming " .. tostring(State.fieldName))
                        elseif State.mobFarm then setStatus("Mob Farm: Resuming")
                        elseif State.sprout then setStatus("Sprout farming")
                        else setStatus("Ready") end
                    end
                end
            end
        end
    end)
end

-- ============================================================
-- PART 8: HOME, TELEPORTS, STATISTICS & CLEANUP
-- ============================================================

heading(homePanel, "OVERVIEW", 1)

infoRow(homePanel, "Welcome, " .. Player.DisplayName, 2)

local sessionLabel = infoRow(
    homePanel,
    "Session Time: 00:00:00",
    3
)

local honeyLabel = infoRow(
    homePanel,
    "Honey Made: 0",
    4
)

local modeLabel = infoRow(
    homePanel,
    "Mode: Idle",
    5
)

heading(tpLeft, "FIELD & HIVE", 1)

makeButton(tpLeft, "Teleport to Hive", 2, function()
    local cf = getHiveCF()

    if cf then
        teleport(cf)
        setStatus("Teleported to hive")
    else
        setStatus("Claim a hive first")
    end
end)

makeDropdown(
    tpLeft,
    "Field Teleport",
    3,
    buildFields(),
    function(name, cf)
        teleport(cf)
        setStatus("Teleported to " .. name)
    end
)

heading(tpLeft, "SHOPS", 4)

for index, destination in ipairs({
    {"Starter Shop", CFrame.new(-685.64, 74.41, -3.48)},
    {"Pro Shop", CFrame.new(-611.87, 118.99, -405.29)},
    {"Mountain Shop", CFrame.new(-863.94, 176.96, -534.20)}
}) do
    makeButton(tpLeft, destination[1], 4 + index, function()
        if State.farm or State.sprout or State.mobFarm or State.busy or State.convert then
            setStatus("Stop farming and conversion before visiting a shop")
            return
        end
        if teleport(destination[2]) then
            setStatus("Teleported to " .. destination[1])
        else
            setStatus("Character not ready")
        end
    end)
end

heading(tpRight, "QUEST BEARS", 1)

makeDropdown(
    tpRight,
    "Bear",
    2,
    buildBears(),
    function(name, cf)
        teleport(cf)
        setStatus("Teleported to " .. name)
    end
)

-- WalkSpeed control: enforce the chosen speed while enabled, including after
-- respawn or game-side speed changes such as Haste. Disabled means no writes.
local walkSpeedEnabled = false
local desiredWalkSpeed = 16

heading(miscPanel, "WALK SPEED", 20)
local walkSpeedRow = create("Frame", {
    Size = UDim2.new(1, 0, 0, 35),
    LayoutOrder = 21,
    BackgroundColor3 = THEME.Control,
    BorderSizePixel = 0,
    Parent = miscPanel
}, 4)
create("TextLabel", {
    Size = UDim2.new(0.55, -9, 1, 0),
    Position = UDim2.fromOffset(9, 0),
    BackgroundTransparency = 1,
    Text = "Target WalkSpeed",
    TextSize = 12,
    Font = FONT,
    TextColor3 = THEME.Text,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = walkSpeedRow
})
local walkSpeedInput = create("TextBox", {
    Size = UDim2.new(0.39, 0, 0, 27),
    Position = UDim2.new(0.60, 0, 0.5, -13),
    BackgroundColor3 = THEME.Panel,
    BorderSizePixel = 0,
    Text = "16",
    PlaceholderText = "Enter speed",
    ClearTextOnFocus = false,
    TextSize = 12,
    Font = FONT,
    TextColor3 = THEME.Text,
    Parent = walkSpeedRow
}, 4)
local function applyWalkSpeed()
    if not walkSpeedEnabled then return end
    local character = Player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.Health > 0 and humanoid.WalkSpeed ~= desiredWalkSpeed then
        humanoid.WalkSpeed = desiredWalkSpeed
    end
end
connect(walkSpeedInput.FocusLost, function()
    local speed = tonumber(walkSpeedInput.Text)
    if not speed or speed ~= speed or speed == math.huge or speed == -math.huge or speed < 0 then
        walkSpeedInput.Text = tostring(desiredWalkSpeed)
        setStatus("Invalid WalkSpeed value")
        return
    end
    desiredWalkSpeed = speed
    walkSpeedInput.Text = tostring(speed)
    applyWalkSpeed()
end)
makeToggle(miscPanel, "Enforce WalkSpeed", 22, function(enabled)
    walkSpeedEnabled = enabled
    applyWalkSpeed()
end)
task.spawn(function()
    while State.active do
        if walkSpeedEnabled then applyWalkSpeed() end
        task.wait(0.1)
    end
end)

heading(miscPanel, "HUB VERSION", 1)
infoRow(miscPanel, "Version: V" .. HUB_VERSION, 2)
infoRow(miscPanel, "Build: " .. HUB_BUILD, 3)

heading(miscPanel, "AUTO ITEMS", 4)

-- Detect the actual field beneath the character at the moment of use.
-- Do not rely on the autofarm dropdown: manual movement and sprout farming
-- can place the character in a different field.
local function getStandingWatermelonField()
    local root = getRoot()
    local fields = Workspace:FindFirstChild("Fields")
    if not root or not fields then return nil end

    local position = root.Position
    local bestBox, bestDistance = nil, math.huge
    for _, field in ipairs(fields:GetChildren()) do
        if field.Name ~= "Glitch Field" then
            local box = field:FindFirstChild("FieldBox")
            if box and box:IsA("BasePart") then
                local localPos = box.CFrame:PointToObjectSpace(position)
                local half = box.Size * 0.5
                -- FieldBox is a field footprint, not necessarily a tall volume.
                -- Check horizontal containment and reject distant floors/heights.
                if math.abs(localPos.X) <= half.X
                    and math.abs(localPos.Z) <= half.Z
                    and math.abs(localPos.Y) <= half.Y + 20 then
                    local distance = math.abs(localPos.Y)
                    if distance < bestDistance then
                        bestBox, bestDistance = box, distance
                    end
                end
            end
        end
    end
    return bestBox
end

makeToggle(miscPanel, "Auto Watermelon", 5, function(value)
    State.autoWatermelon = value
    setStatus(value and "Auto Watermelon enabled" or "Auto Watermelon disabled")
end)

task.spawn(function()
    while State.active do
        if State.autoWatermelon and not State.planterBusy then
            local firstBox = getStandingWatermelonField()
            if firstBox then
                -- Confirm we're still in the same field after a brief settling
                -- period, so switching fields cannot use the previous target.
                task.wait()
                local currentBox = getStandingWatermelonField()
                if State.active and State.autoWatermelon and not State.planterBusy
                    and currentBox == firstBox and currentBox.Parent then
                    local remotes = RS:FindFirstChild("Remotes")
                    local useItem = remotes and remotes:FindFirstChild("UseItem")
                    if useItem and useItem:IsA("RemoteEvent") then
                        pcall(function()
                            useItem:FireServer("Watermelon", currentBox)
                        end)
                    end
                end
            end
        end
        task.wait(CFG.WatermelonInterval)
    end
end)

-- Auto Sprout uses the same standing-field detection as Auto Watermelon.
-- The two toggles operate independently.
makeToggle(miscPanel, "Auto Sprout", 6, function(value)
    State.autoSprout = value
    setStatus(value and "Auto Sprout enabled" or "Auto Sprout disabled")
end)

task.spawn(function()
    while State.active do
        if State.autoSprout and not State.planterBusy then
            local firstBox = getStandingWatermelonField()
            if firstBox then
                task.wait()
                local currentBox = getStandingWatermelonField()
                if State.active and State.autoSprout and not State.planterBusy
                    and currentBox == firstBox and currentBox.Parent then
                    local remotes = RS:FindFirstChild("Remotes")
                    local useItem = remotes and remotes:FindFirstChild("UseItem")
                    if useItem and useItem:IsA("RemoteEvent") then
                        pcall(function()
                            useItem:FireServer("Sprout", currentBox)
                        end)
                    end
                end
            end
        end
        task.wait(CFG.SproutInterval)
    end
end)

-- ============================================================
-- MISC: AUTO ROYAL JELLY (V6.1 ROLLING ENGINE)
-- ============================================================
local Jelly = {
    running=false, selecting=false, slot=nil, hive=nil, face=nil,
    selected={},
    target=nil, confirm=nil, generation=0, requests=0, used=0,
    status="Select a hive slot and target bee"
}

local JELLY_GROUPS = {
    {"RARE", {"Brave", "Rad", "Bomber", "Cool"}},
    {"EPIC", {"Honey", "Scared", "Electro", "Rage", "Fire", "Snow", "Riley", "Dice", "Bucko"}},
    {"LEGENDARY", {"Demon", "Brilliant", "Frog", "Glowbite", "Demo", "Baby", "Mummy", "Dracula"}},
    {"MYTHIC", {"Lazy", "Sad", "Doctor", "Soldier", "Cyber", "Frozen", "Inferno"}}
}

-- Misc opens the familiar standalone-style jelly window.
local jellyWindow = create("Frame", {
    Size=UDim2.fromOffset(365,385),
    BackgroundColor3=Color3.fromRGB(19,23,34),
    BorderSizePixel=0, Visible=false, Active=true,
    Parent=gui
}, 11)
addStroke(jellyWindow)
local jellyScale = create("UIScale", {Scale=0.96,Parent=jellyWindow})
local jellyShown = false
local jellyTween

local function jellyPosition()
    local viewport = gui.AbsoluteSize
    local x = main.AbsolutePosition.X + main.AbsoluteSize.X + 12
    if x + 365 > viewport.X - 8 then
        x = main.AbsolutePosition.X - 365 - 12
    end
    x = math.clamp(x, 8, math.max(8,viewport.X-373))
    local y = math.clamp(main.AbsolutePosition.Y,8,math.max(8,viewport.Y-393))
    jellyWindow.Position = UDim2.fromOffset(x,y)
end
connect(main:GetPropertyChangedSignal("AbsolutePosition"),jellyPosition)
connect(main:GetPropertyChangedSignal("AbsoluteSize"),jellyPosition)

local jellyAnimationId = 0
local function jellyOpen(open)
    jellyShown = open
    jellyAnimationId += 1
    local ticket = jellyAnimationId
    if jellyTween then jellyTween:Cancel() end
    if open then
        jellyPosition()
        jellyWindow.Visible = main.Visible
        jellyScale.Scale = .96
    end
    if not jellyWindow.Visible then return end
    jellyTween = TweenService:Create(jellyScale,
        TweenInfo.new(open and .14 or .10,Enum.EasingStyle.Quart,
            open and Enum.EasingDirection.Out or Enum.EasingDirection.In),
        {Scale=open and 1 or .96})
    jellyTween:Play()
    task.spawn(function()
        local tween = jellyTween
        tween.Completed:Wait()
        if ticket ~= jellyAnimationId or not State.active then return end
        if not jellyShown then jellyWindow.Visible=false end
    end)
end
connect(main:GetPropertyChangedSignal("Visible"),function()
    jellyWindow.Visible = jellyShown and main.Visible
    if jellyWindow.Visible then jellyPosition() end
end)

heading(miscPanel, "AUTO ROYAL JELLY", 10)
makeButton(miscPanel, "Open Auto Royal Jelly UI", 11, function()
    jellyOpen(not jellyShown)
end)
infoRow(miscPanel, "Separate panel • Close without stopping rolls", 12)

do -- Isolate token monitor GUI locals to stay within Luau register limit.
-- Token monitor: separate companion window, matching Auto Royal Jelly placement.
local tokenWindow = create("Frame", {
    Size=UDim2.fromOffset(365, 505),
    BackgroundColor3=Color3.fromRGB(19,23,34),
    BorderSizePixel=0, Visible=false, Active=true, Parent=gui
}, 11)
addStroke(tokenWindow)
local tokenWindowShown = false
local function positionTokenWindow()
    local viewport = gui.AbsoluteSize
    local x = main.AbsolutePosition.X + main.AbsoluteSize.X + 12
    if x + 365 > viewport.X - 8 then x = main.AbsolutePosition.X - 377 end
    x = math.clamp(x, 8, math.max(8, viewport.X - 373))
    local y = math.clamp(main.AbsolutePosition.Y, 8, math.max(8, viewport.Y - 513))
    tokenWindow.Position = UDim2.fromOffset(x, y)
end
local function showTokenWindow(show)
    tokenWindowShown = show
    if show then jellyOpen(false) end
    tokenWindow.Visible = show and main.Visible
    if tokenWindow.Visible then positionTokenWindow() end
end
connect(main:GetPropertyChangedSignal("AbsolutePosition"), positionTokenWindow)
connect(main:GetPropertyChangedSignal("AbsoluteSize"), positionTokenWindow)
connect(main:GetPropertyChangedSignal("Visible"), function()
    tokenWindow.Visible = tokenWindowShown and main.Visible
    if tokenWindow.Visible then positionTokenWindow() end
end)
local tokenTitle = create("TextLabel", {
    Position=UDim2.fromOffset(14,8), Size=UDim2.fromOffset(290,32),
    BackgroundTransparency=1, Text="TOKEN COLLECTION MONITOR",
    TextColor3=THEME.Text, Font=FONT_BOLD, TextSize=14,
    TextXAlignment=Enum.TextXAlignment.Left, Parent=tokenWindow
})
local tokenClose = create("TextButton", {
    Position=UDim2.new(1,-43,0,10), Size=UDim2.fromOffset(28,26),
    BackgroundColor3=THEME.Control, Text="×", TextSize=19,
    TextColor3=THEME.Text, Font=FONT_BOLD, Parent=tokenWindow
}, 5)
connect(tokenClose.MouseButton1Click, function() showTokenWindow(false) end)
local function monitorLabel(y, height, initial, size)
    return create("TextLabel", {
        Position=UDim2.fromOffset(14,y), Size=UDim2.fromOffset(337,height),
        BackgroundTransparency=1, Text=initial, TextColor3=THEME.Text,
        Font=FONT, TextSize=size or 12, TextXAlignment=Enum.TextXAlignment.Left,
        TextYAlignment=Enum.TextYAlignment.Center, Parent=tokenWindow
    })
end
local tokenMinuteText = monitorLabel(47,25,"Last 60 seconds: 0")
local tokenIntervalText = monitorLabel(76,25,"Average between pickups: --")
local tokenLatencyText = monitorLabel(105,25,"Average touch-to-disappear: --")
local tokenDiagnostic1 = monitorLabel(137,22,"First-attempt success: --")
local tokenDiagnostic2 = monitorLabel(160,22,"Retries: 0 | Retry successes: 0")
local tokenDiagnostic3 = monitorLabel(183,22,"Failed visits: 0 | Failed-attempt time: 0.0s")
local tokenDiagnostic4 = monitorLabel(206,22,"Pickups during target visits: 0")
local tokenNote = monitorLabel(235,28,"Estimated pickups: disappearance after scripted touch",10)
tokenNote.TextColor3 = THEME.Muted
tokenNote.TextWrapped = true
local tokenFeedTitle = monitorLabel(270,20,"RECENT PICKUPS (NEWEST FIRST)",11)
tokenFeedTitle.Font=FONT_BOLD
tokenFeedTitle.TextColor3=THEME.Accent
local tokenFeed = create("ScrollingFrame", {
    Position=UDim2.fromOffset(14,296), Size=UDim2.fromOffset(337,195),
    BackgroundColor3=THEME.Control, BorderSizePixel=0,
    ScrollBarThickness=3, CanvasSize=UDim2.new(),
    AutomaticCanvasSize=Enum.AutomaticSize.Y, Parent=tokenWindow
},5)
create("UIPadding", {PaddingTop=UDim.new(0,5), PaddingLeft=UDim.new(0,8),
    PaddingRight=UDim.new(0,8), PaddingBottom=UDim.new(0,5), Parent=tokenFeed})
create("UIListLayout", {Padding=UDim.new(0,3), SortOrder=Enum.SortOrder.LayoutOrder,
    Parent=tokenFeed})
local feedRows = {}
for i=1,12 do
    feedRows[i] = create("TextLabel", {
        Size=UDim2.new(1,-4,0,18), LayoutOrder=i,
        BackgroundTransparency=1, Text="", Visible=false,
        Font=FONT, TextSize=11, TextColor3=THEME.Text,
        TextXAlignment=Enum.TextXAlignment.Left, Parent=tokenFeed
    })
end
local function updateTokenMonitor()
    if not tokenWindowShown or not main.Visible then return end
    local now = os.clock()
    local n60, intervalTotal, intervalCount, latencyTotal, latencyCount = 0, 0, 0, 0, 0
    for i=#tokenCollectionTimes,1,-1 do
        local pickupTime = tokenCollectionTimes[i]
        if now - pickupTime > 60 then break end
        n60 += 1
        local previousTime = tokenCollectionTimes[i-1]
        if previousTime and now - previousTime <= 60 then
            intervalTotal += pickupTime - previousTime
            intervalCount += 1
        end
        local latency = tokenPickupLatencies[i]
        if latency then
            latencyTotal += latency
            latencyCount += 1
        end
    end
    local d = tokenDiagnostics
    local completed = d.firstSuccess + d.retrySuccess + d.failedVisits
    tokenDiagnostic1.Text = completed > 0
        and string.format("First-attempt success: %d/%d (%.1f%%)", d.firstSuccess, completed, 100*d.firstSuccess/completed)
        or "First-attempt success: --"
    tokenDiagnostic2.Text = string.format("Retries: %d | Retry successes: %d", d.retryAttempts, d.retrySuccess)
    tokenDiagnostic3.Text = string.format("Failed visits: %d | Failed-attempt time: %.1fs", d.failedVisits, d.failedAttemptSeconds)
    tokenDiagnostic4.Text = string.format("Pickups during target visits: %d", d.nearbyPickups)
    tokenMinuteText.Text = "Last 60 seconds: " .. tostring(n60)
    tokenIntervalText.Text = intervalCount > 0
        and string.format("Avg between pickups (60s): %.3fs", intervalTotal / intervalCount)
        or "Avg between pickups (60s): --"
    tokenLatencyText.Text = latencyCount > 0
        and string.format("Avg touch-to-disappear (60s): %.3fs", latencyTotal / latencyCount)
        or "Avg touch-to-disappear (60s): --"
    for i, row in ipairs(feedRows) do
        local entry = tokenRecent[i]
        row.Visible = entry ~= nil
        if entry then
            local gap = entry.interval and string.format("+%.2fs", entry.interval) or "first"
            row.Text = string.format("%ds ago • %s • %s", math.floor(now-entry.time), entry.name, gap)
        end
    end
end
tokenMonitorRefresh = updateTokenMonitor
task.spawn(function()
    while State.active do
        task.wait(1)
        updateTokenMonitor()
    end
end)
heading(miscPanel, "TOKEN COLLECTION", 17)
makeButton(miscPanel, "Open Token Collection Monitor", 18, function()
    showTokenWindow(not tokenWindowShown)
    updateTokenMonitor()
end)
infoRow(miscPanel, "Pickup intervals • Last 60 seconds • Live feed", 19)

end -- Token monitor GUI scope

heading(miscPanel, "FIELD DICE", 13)
makeButton(miscPanel, "Use Field Dice", 14, function()
    local fields = Workspace:FindFirstChild("Fields")
    local spider = fields and fields:FindFirstChild("Spider Field")
    local fieldBox = spider and spider:FindFirstChild("FieldBox")
    local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
    local useItem = remotes and remotes:FindFirstChild("UseItem")

    if not fieldBox or not useItem then
        setStatus("Field Dice: remote or Spider Field missing")
        return
    end

    useItem:FireServer("Field Dice", fieldBox)
    setStatus("Used Field Dice on Spider Field")
end)


local function jellyText(text,y,height,size)
    return create("TextLabel", {
        Position=UDim2.fromOffset(16,y), Size=UDim2.fromOffset(333,height),
        BackgroundTransparency=1,Text=text,TextColor3=THEME.Text,
        Font=FONT,TextSize=size or 12,TextWrapped=true,
        TextXAlignment=Enum.TextXAlignment.Left,
        TextYAlignment=Enum.TextYAlignment.Center,Parent=jellyWindow
    })
end
local function jellyButton(text,y,height,color)
    return create("TextButton", {
        Position=UDim2.fromOffset(16,y),Size=UDim2.fromOffset(333,height),
        BackgroundColor3=color or Color3.fromRGB(49,91,160),
        BorderSizePixel=0,Text=text,TextColor3=THEME.Text,
        Font=FONT_BOLD,TextSize=13,Parent=jellyWindow
    },7)
end
local jellyTitle = jellyText("AUTO ROYAL JELLY  •  V6.3",8,32,15)
jellyTitle.Font=FONT_BOLD
local jellyClose = create("TextButton", {
    Position=UDim2.new(1,-43,0,10),Size=UDim2.fromOffset(28,26),
    BackgroundColor3=THEME.Control,Text="×",TextSize=19,
    TextColor3=THEME.Text,Font=FONT_BOLD,Parent=jellyWindow
},5)
connect(jellyClose.MouseButton1Click,function() jellyOpen(false) end)
local jellySelect = jellyButton("Select Hive Slots (Multi)",46,36)
local jellySlotLabel = jellyText("Selected: None",87,40)
jellyText("TARGET BEE",132,18,11)
local jellyTargetButton = jellyButton("Choose a Bee  ▼",154,36,Color3.fromRGB(30,36,52))
local jellyStart = jellyButton("Start Auto Royal Jelly",205,38)
local jellyStop = jellyButton("STOP",251,38,Color3.fromRGB(145,54,72))
local jellyStats = jellyText("Requests: 0  |  Jellies used: 0",296,25)
local jellyStatus = jellyText(Jelly.status,324,51)

-- Dropdown lives inside the side window, over the lower controls.
local jellyPopup = create("Frame", {
    Position=UDim2.fromOffset(16,192),Size=UDim2.fromOffset(333,184),
    BackgroundColor3=Color3.fromRGB(30,36,52),
    BorderSizePixel=0,Visible=false,ZIndex=30,Parent=jellyWindow
},8)
addStroke(jellyPopup)
local jellySearch = create("TextBox", {
    Position=UDim2.fromOffset(8,8),Size=UDim2.fromOffset(317,32),
    BackgroundColor3=THEME.Control,BorderSizePixel=0,
    PlaceholderText="Search bees...",Text="",ClearTextOnFocus=false,
    Font=FONT,TextSize=12,TextColor3=THEME.Text,
    PlaceholderColor3=THEME.Muted,ZIndex=31,Parent=jellyPopup
},4)
local jellyList = create("ScrollingFrame", {
    Position=UDim2.fromOffset(8,45),Size=UDim2.fromOffset(317,131),
    BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=4,
    CanvasSize=UDim2.new(),ZIndex=31,Parent=jellyPopup
})
create("UIListLayout", {
    Padding=UDim.new(0,3),SortOrder=Enum.SortOrder.LayoutOrder,
    Parent=jellyList
})

local jellyOptionConnections={}
local function jellyMessage(message)
    Jelly.status=message
    jellyStatus.Text=message
end
local function jellyStatsUpdate()
    jellyStats.Text="Requests: "..Jelly.requests.."  |  Jellies used: "..Jelly.used
end
local function jellyListOpen(value)
    jellyPopup.Visible=value
    if value then jellySearch.Text="" end
end
local function jellyRebuild()
    for _,c in ipairs(jellyOptionConnections) do c:Disconnect() end
    table.clear(jellyOptionConnections)
    for _,child in ipairs(jellyList:GetChildren()) do
        if child:IsA("TextButton") or child:IsA("TextLabel") then child:Destroy() end
    end
    local query=jellySearch.Text:lower()
    local order,height=0,0
    for _,group in ipairs(JELLY_GROUPS) do
        local matches={}
        for _,base in ipairs(group[2]) do
            local regular=base.." Bee"
            local ascended="Ascended "..regular
            if regular:lower():find(query,1,true) then table.insert(matches,regular) end
            if ascended:lower():find(query,1,true) then table.insert(matches,ascended) end
        end
        if #matches>0 then
            order+=1
            create("TextLabel", {
                Size=UDim2.new(1,-8,0,21),LayoutOrder=order,
                BackgroundTransparency=1,Text="  "..group[1],
                Font=FONT_BOLD,TextSize=11,TextColor3=THEME.Muted,
                TextXAlignment=Enum.TextXAlignment.Left,ZIndex=32,Parent=jellyList
            })
            height+=24
            for _,name in ipairs(matches) do
                order+=1
                local ascended=name:sub(1,9)=="Ascended "
                local choice=create("TextButton", {
                    Size=UDim2.new(1,-8,0,29),LayoutOrder=order,
                    BackgroundColor3=ascended and Color3.fromRGB(65,51,106) or THEME.Control,
                    Text="  "..name,Font=FONT,TextSize=12,
                    TextColor3=THEME.Text,TextXAlignment=Enum.TextXAlignment.Left,
                    ZIndex=32,Parent=jellyList
                },4)
                table.insert(jellyOptionConnections,choice.MouseButton1Click:Connect(function()
                    if Jelly.running then return end
                    Jelly.target=name
                    Jelly.confirm=nil
                    jellyTargetButton.Text=name.."  ▼"
                    jellyListOpen(false)
                    jellyMessage("Target selected: "..name)
                end))
                height+=32
            end
        end
    end
    jellyList.CanvasSize=UDim2.fromOffset(0,height)
    jellyList.CanvasPosition=Vector2.zero
end
connect(jellySearch:GetPropertyChangedSignal("Text"),jellyRebuild)
connect(jellyTargetButton.MouseButton1Click,function()
    if Jelly.running then return end
    jellyListOpen(not jellyPopup.Visible)
    if jellyPopup.Visible then jellyRebuild() end
end)
local function jellyClearSelections()
    for _, entry in ipairs(Jelly.selected) do
        if entry.outline then entry.outline:Destroy() end
    end
    table.clear(Jelly.selected)
    Jelly.slot, Jelly.hive, Jelly.face = nil, nil, nil
    jellySlotLabel.Text = "Selected: None"
    jellySelect.Text = "Select Hive Slots (Multi)"
end
local function jellySelectionLabel()
    local count = #Jelly.selected
    if count == 0 then
        jellySlotLabel.Text = "Selected: None"
    elseif count == 1 then
        local entry = Jelly.selected[1]
        jellySlotLabel.Text = "Selected: " .. entry.hive.Name .. "/" .. entry.slot.Name
    else
        jellySlotLabel.Text = "Selected: " .. count .. " hive slots (sequential)"
    end
end
connect(jellySelect.MouseButton1Click,function()
    if Jelly.running then return end
    Jelly.selecting = not Jelly.selecting
    Jelly.confirm = nil
    jellyListOpen(false)
    jellySelect.Text = Jelly.selecting and "Done Selecting Slots" or "Select Hive Slots (Multi)"
    jellyMessage(Jelly.selecting and "Click cells to add/remove; press Done when finished"
        or ("Selected " .. #Jelly.selected .. " slots"))
end)
local function jellyRead(slotName)
    local remotes = RS:FindFirstChild("Remotes")
    local getData = remotes and remotes:FindFirstChild("GetData")
    if not getData or not getData:IsA("RemoteFunction") then
        return nil,nil,"GetData unavailable"
    end
    local ok, data = pcall(function() return getData:InvokeServer() end)
    if not ok or type(data) ~= "table" or type(data.Bees) ~= "table"
        or type(data.Inventory) ~= "table" then
        return nil,nil,"GetData failed"
    end
    local bee
    for _, entry in ipairs(data.Bees) do
        if entry.Slot == slotName then bee = entry.Bee break end
    end
    local amount = data.Inventory["Royal Jelly"]
    if type(bee) ~= "string" or type(amount) ~= "number" then
        return nil,nil,"Bee or inventory missing"
    end
    return bee,amount,nil
end
local function jellySlotFromPart(part)
    while part and part ~= Workspace do
        if part.Name:match("^Slot_%d+$") then return part end
        part = part.Parent
    end
end
local function jellyHiveFromSlot(cell)
    local part = cell and cell.Parent
    while part and part ~= Workspace do
        if part.Name:match("^Hive_%d+$") and part.Parent
            and part.Parent.Name == "Hives" then return part end
        part = part.Parent
    end
end
local function jellyUpdateSlot(bee)
    jellySelectionLabel()
end
connect(UIS.InputBegan, function(input, processed)
    if not State.active or not Jelly.selecting or processed then return end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    local cell = jellySlotFromPart(Player:GetMouse().Target)
    local candidateHive = jellyHiveFromSlot(cell)
    local cover = cell and cell:FindFirstChild("Cover")
    local candidateFace = cover and cover:FindFirstChild("Face")
    if not cell or not candidateHive or not candidateFace then
        jellyMessage("Click a valid hive cell")
        return
    end
    -- Claimed can be a BoolValue (claim state), not an owner identity.
    -- Only reject when the hive explicitly identifies a different player.
    local claimed = candidateHive:FindFirstChild("Claimed")
    if claimed then
        local otherOwner = false
        if claimed:IsA("ObjectValue") then
            local owner = claimed.Value
            otherOwner = owner ~= nil and owner:IsA("Player") and owner ~= Player
        elseif claimed:IsA("StringValue") then
            local owner = claimed.Value
            otherOwner = owner ~= "" and owner ~= Player.Name
                and owner ~= Player.DisplayName
        elseif claimed:IsA("IntValue") or claimed:IsA("NumberValue") then
            -- Numeric claim state (0/1) is not a user ID.
            -- Only a value matching an actual other player's UserId is evidence.
            local ownerId = claimed.Value
            if ownerId > 1 and ownerId ~= Player.UserId then
                for _, other in ipairs(Players:GetPlayers()) do
                    if other ~= Player and other.UserId == ownerId then
                        otherOwner = true
                        break
                    end
                end
            end
        end
        -- BoolValue merely indicates whether the hive is claimed.
        if otherOwner then
            jellyMessage("That hive is not claimed by you")
            return
        end
    end
    local bee,_,err = jellyRead(cell.Name)
    if err then jellyMessage(err) return end
    for index, entry in ipairs(Jelly.selected) do
        if entry.slot == cell then
            if entry.outline then entry.outline:Destroy() end
            table.remove(Jelly.selected,index)
            Jelly.confirm = nil
            jellySelectionLabel()
            jellyMessage("Removed " .. cell.Name .. " (" .. #Jelly.selected .. " selected)")
            return
        end
    end
    if #Jelly.selected > 0 and Jelly.selected[1].hive ~= candidateHive then
        jellyMessage("Select cells from the same hive")
        return
    end
    local outline = Instance.new("Highlight")
    outline.Name = "BSSA_RJ_Selected"
    outline.Adornee = cell
    outline.FillColor = Color3.fromRGB(65,180,255)
    outline.OutlineColor = Color3.fromRGB(255,230,100)
    outline.FillTransparency = 0.8
    outline.OutlineTransparency = 0
    outline.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    outline.Parent = cell
    table.insert(Jelly.selected, {
        slot=cell, hive=candidateHive, face=candidateFace, outline=outline
    })
    Jelly.slot, Jelly.hive, Jelly.face = cell, candidateHive, candidateFace
    Jelly.confirm = nil
    jellySelectionLabel()
    jellyMessage("Added " .. cell.Name .. " (" .. #Jelly.selected .. " selected)")
end)

-- Royal Jelly confirmation engine adapted from the successfully tested
-- standalone diagnostic V2. Confirm a stable snapshot (three matching reads
-- plus a separate verification) after EITHER inventory consumption or a bee
-- change. A bee can remain the same even when jellies were consumed.
-- Never issue another request when the previous result is uncertain.
local function jellyAwaitRoll(slotName, oldAmount, oldBee, ticket)
    local deadline = os.clock() + 10
    local lastBee, lastAmount = nil, nil
    local stable = 0
    local lastReadError = nil
    local reads = 0

    while State.active and Jelly.running and Jelly.generation == ticket
        and os.clock() < deadline do
        task.wait(0.2)
        local bee, amount, err = jellyRead(slotName)
        reads += 1
        if not State.active or not Jelly.running or Jelly.generation ~= ticket then
            return nil, nil, "Stopped"
        end

        if err then
            lastReadError = err
        else
            lastReadError = nil
            local beeChanged = bee ~= oldBee
            local jellyConsumed = amount < oldAmount
            if beeChanged or jellyConsumed then
                if bee == lastBee and amount == lastAmount then
                    stable += 1
                else
                    stable = 1
                end

                if stable >= 3 then
                    task.wait(0.25)
                    if not State.active or not Jelly.running
                        or Jelly.generation ~= ticket then
                        return nil, nil, "Stopped"
                    end
                    local checkBee, checkAmount, checkErr = jellyRead(slotName)
                    if not checkErr and checkBee == bee and checkAmount == amount then
                        return checkBee, checkAmount, nil
                    end
                    stable = 0
                end
            else
                stable = 0
            end
            lastBee, lastAmount = bee, amount
        end
    end

    if lastReadError then
        return nil, nil, "No roll confirmation (" .. lastReadError .. ")"
    end
    return nil, nil, "No stable roll confirmation after " .. reads .. " reads"
end
local function jellyHalt(message)
    Jelly.running = false
    Jelly.selecting = false
    Jelly.generation += 1
    Jelly.confirm = nil
    jellyClearSelections()
    if message then jellyMessage(message) end
end
connect(jellyStop.MouseButton1Click, function()
    jellyHalt("Stopped")
end)
connect(jellyStart.MouseButton1Click, function()
    if Jelly.running then return end
    if #Jelly.selected == 0 then
        jellyMessage("Select at least one hive slot first") return
    end
    if not Jelly.target then jellyMessage("Choose a target bee first") return end
    local wanted = Jelly.target
    local signatureParts = {}
    for _, entry in ipairs(Jelly.selected) do
        if not entry.slot.Parent or not entry.face.Parent then
            jellyMessage("A selected hive slot disappeared") return
        end
        table.insert(signatureParts, entry.hive.Name .. "/" .. entry.slot.Name)
    end
    local signature = table.concat(signatureParts,",") .. "|" .. wanted
    if Jelly.confirm ~= signature then
        Jelly.confirm = signature
        jellyMessage("Confirm " .. #Jelly.selected .. " slots → " .. wanted .. ": press Start again")
        return
    end
    Jelly.confirm, Jelly.selecting = nil, false
    jellySelect.Text = "Select Hive Slots (Multi)"
    jellyListOpen(false)
    Jelly.running = true
    Jelly.generation += 1
    local ticket = Jelly.generation
    local queue = {}
    for _, entry in ipairs(Jelly.selected) do table.insert(queue,entry) end
    Jelly.requests, Jelly.used = 0,0
    jellyStatsUpdate()
    task.spawn(function()
        local completed, aborted = 0, false
        for index, entry in ipairs(queue) do
            if not State.active or not Jelly.running or Jelly.generation ~= ticket then
                aborted = true break
            end
            local slotName, face = entry.slot.Name, entry.face
            if not face.Parent or not entry.slot.Parent then
                jellyMessage("Slot disappeared: " .. slotName)
                aborted = true break
            end
            local currentBee, previousAmount, readErr = jellyRead(slotName)
            if readErr then
                jellyMessage("Stopped on " .. slotName .. ": " .. readErr)
                aborted = true break
            end
            while State.active and Jelly.running and Jelly.generation == ticket do
                if currentBee == wanted then break end
                if not face.Parent then
                    jellyMessage("Slot disappeared: " .. slotName)
                    aborted = true break
                end
                if previousAmount <= 0 then
                    jellyMessage("Out of Royal Jelly")
                    aborted = true break
                end
                jellyMessage("Slot " .. index .. "/" .. #queue .. " (" .. slotName .. "): " .. currentBee)
                local folder = RS:FindFirstChild("Remotes")
                local useItem = folder and folder:FindFirstChild("UseItem")
                if not useItem or not useItem:IsA("RemoteEvent") then
                    jellyMessage("UseItem unavailable")
                    aborted = true break
                end
                local sent = pcall(function()
                    useItem:FireServer("Royal Jelly",face,1)
                end)
                if not sent then
                    jellyMessage("UseItem failed")
                    aborted = true break
                end
                Jelly.requests += 1
                jellyStatsUpdate()
                local bee, newAmount, rollErr = jellyAwaitRoll(
                    slotName, previousAmount, currentBee, ticket)
                if not State.active or not Jelly.running or Jelly.generation ~= ticket then
                    aborted = true break
                end
                if rollErr then
                    jellyMessage("Stopped on " .. slotName .. ": " .. rollErr)
                    aborted = true break
                end
                local consumed = previousAmount - newAmount
                if consumed <= 0 and bee == currentBee then
                    jellyMessage("Unconfirmed roll on " .. slotName .. ". Stopped")
                    aborted = true break
                end
                Jelly.used += math.max(0,consumed)
                previousAmount, currentBee = newAmount, bee
                jellyStatsUpdate()
                task.wait(0.05)
            end
            if aborted or not State.active or not Jelly.running
                or Jelly.generation ~= ticket then break end
            completed += 1
            if entry.outline then
                entry.outline:Destroy()
                entry.outline = nil
            end
            jellyMessage("Completed " .. completed .. "/" .. #queue .. " slots")
        end
        if Jelly.generation == ticket then
            Jelly.running = false
            Jelly.selecting = false
            if not aborted and completed == #queue then
                jellyMessage("SUCCESS! All " .. completed .. " slots: " .. wanted)
            end
            jellyClearSelections()
        end
    end)
end)

do
heading(miscPanel, "PROMO CODES", 7)

local PROMO_CODES = {
    "strong3st",
    "plaplaplanters",
    "p1neapple",
    "mushroom",
    "seed",
    "425935",
    "yummygummy",
    "BSSX",
    "tyfor400likes"
}

infoRow(
    miscPanel,
    tostring(#PROMO_CODES) .. " codes available",
    8
)

local redeeming = false

makeButton(miscPanel, "Submit All Codes", 9, function(button)
    if redeeming then return end

    local folder = RS:FindFirstChild("Remotes")
    local remote = folder and folder:FindFirstChild("RedeemCode")

    if not remote or not remote:IsA("RemoteEvent") then
        setStatus("RedeemCode remote not found")
        return
    end

    redeeming = true
    button.Text = "  Submitting..."

    task.spawn(function()
        for index, code in ipairs(PROMO_CODES) do
            if not State.active then break end

            setStatus("Submitting " .. index .. "/" .. #PROMO_CODES)

            pcall(function()
                remote:FireServer(code)
            end)

            task.wait(0.3)
        end

        if State.active then
            setStatus("Code submission finished")
        end

        button.Text = "  Submit All Codes"
        redeeming = false
    end)
end)

end -- Promo code controls scope

local function startHoneyStats()
local SUFFIX = {
    k = 1e3,
    m = 1e6,
    b = 1e9,
    t = 1e12,
    qd = 1e15,
    qn = 1e18,
    sx = 1e21,
    sp = 1e24
}

local function formatNumber(value)
    value = math.floor(math.max(0, value or 0))

    return (tostring(value):reverse()
        :gsub("(%d%d%d)", "%1,")
        :reverse())
        :gsub("^,", "")
end

local cachedHoney

local function getHoney()
    if cachedHoney and cachedHoney.Parent then
        local amount = tonumber(cachedHoney.Value)
        if amount then return amount, cachedHoney end
    end

    cachedHoney = nil

    local leaderstats = Player:FindFirstChild("leaderstats")

    if leaderstats then
        for _, value in ipairs(leaderstats:GetChildren()) do
            if value:IsA("ValueBase")
                and value.Name:lower():find("honey", 1, true) then

                local amount = tonumber(value.Value)

                if amount then
                    cachedHoney = value
                    return amount, value
                end
            end
        end
    end

    for _, value in ipairs(Player:GetDescendants()) do
        if value:IsA("ValueBase")
            and value.Name:lower() == "honey" then

            local amount = tonumber(value.Value)

            if amount then
                cachedHoney = value
                return amount, value
            end
        end
    end

    for _, label in ipairs(Player.PlayerGui:GetDescendants()) do
        if label:IsA("TextLabel")
            and label.Visible
            and label.AbsolutePosition.Y < 80
            and not label.Text:find("/", 1, true) then

            local name = label.Name:lower()
            local parentName = label.Parent
                and label.Parent.Name:lower()
                or ""

            if name:find("honey", 1, true)
                or parentName:find("honey", 1, true) then

                local number, suffix = label.Text:gsub(",", "")
                    :match("^%s*([%d%.]+)%s*([%a]*)%s*$")

                if tonumber(number) then
                    return math.floor(
                        tonumber(number)
                        * (SUFFIX[suffix:lower()] or 1)
                    ), label
                end
            end
        end
    end

    return nil
end

local sessionStart = os.clock()
local previousHoney, previousHoneySource = getHoney()
-- A zero at startup may be a temporary unloaded balance, not a true baseline.
if not previousHoney or previousHoney <= 0 then
    previousHoney = nil
end
local earnedHoney = 0

-- Honey/hour uses a rolling window instead of a lifetime average.
-- This lets the estimate respond to a boost ending without becoming
-- excessively noisy from individual honey updates.
local HONEY_RATE_WINDOW = 300 -- 5 minutes
local HONEY_STATS_INTERVAL = 0.1
local honeyRateSamples = {}
local honeyRateTotal = 0
local farmStart

local function resetHoneyRate()
    table.clear(honeyRateSamples)
    honeyRateTotal = 0
    farmStart = nil
end

local function addHoneyRateSample(now, amount)
    if amount <= 0 then return end

    honeyRateSamples[#honeyRateSamples + 1] = {
        time = now,
        amount = amount
    }
    honeyRateTotal = honeyRateTotal + amount
end

local function pruneHoneyRateSamples(now)
    local cutoff = now - HONEY_RATE_WINDOW
    local firstValid = 1

    while firstValid <= #honeyRateSamples
        and honeyRateSamples[firstValid].time < cutoff do
        honeyRateTotal = honeyRateTotal - honeyRateSamples[firstValid].amount
        firstValid = firstValid + 1
    end

    if firstValid > 1 then
        local remaining = {}
        for index = firstValid, #honeyRateSamples do
            remaining[#remaining + 1] = honeyRateSamples[index]
        end
        honeyRateSamples = remaining
    end
end

task.spawn(function()
    while State.active do
        task.wait(HONEY_STATS_INTERVAL)

        local now = os.clock()
        local elapsed = math.floor(now - sessionStart)

        sessionLabel.Text = string.format(
            "Session Time: %02d:%02d:%02d",
            math.floor(elapsed / 3600),
            math.floor(elapsed % 3600 / 60),
            elapsed % 60
        )

        local currentHoney, currentHoneySource = getHoney()
        local delta = 0

        if currentHoney and currentHoney > 0 then
            if currentHoneySource ~= previousHoneySource or not previousHoney then
                -- A different ValueBase / GUI label, or an unloaded starting
                -- balance, must establish a new baseline instead of counting
                -- the player's entire existing balance as session earnings.
                previousHoney = currentHoney
                previousHoneySource = currentHoneySource
            else
                if currentHoney > previousHoney then
                    delta = currentHoney - previousHoney
                    earnedHoney = earnedHoney + delta
                end

                -- Spending lowers the balance but does not subtract from gross
                -- honey earned. The next valid sample uses the new balance.
                previousHoney = currentHoney
            end
        end
        -- Ignore missing/zero readings: they can occur while the game's
        -- honey data reloads, and must not reset the earnings baseline.

        honeyLabel.Text = "Honey Made: "
            .. formatNumber(earnedHoney)

        if State.farm then
            if not farmStart then
                farmStart = now
                table.clear(honeyRateSamples)
                honeyRateTotal = 0
            end

            addHoneyRateSample(now, delta)
            pruneHoneyRateSamples(now)

            local duration = math.min(now - farmStart, HONEY_RATE_WINDOW)

            if duration >= 10 then
                local honeyPerHour = honeyRateTotal / duration * 3600
                hphLabel.Text = "Honey / Hour: "
                    .. formatNumber(honeyPerHour)
            else
                hphLabel.Text = "Honey / Hour: Calculating..."
            end
        else
            if farmStart then
                resetHoneyRate()
            end
            hphLabel.Text = "Honey / Hour: Off"
        end

        conversionLabel.Text = "Hive Conversions: " .. tostring(State.hiveConversions)

        if State.planterBusy then
            modeLabel.Text = "Mode: Planters"
        elseif State.busy then
            modeLabel.Text = "Mode: Converting"
        elseif State.farm then
            modeLabel.Text = "Mode: Autofarm"
        elseif State.sprout then
            modeLabel.Text = "Mode: Sprout Farm"
        elseif State.mobFarm then
            modeLabel.Text = "Mode: Mob Farm"
        elseif State.planterEnabled then
            modeLabel.Text = "Mode: Planters (waiting)"
        else
            modeLabel.Text = "Mode: Idle"
        end
    end
end)

end -- Honey statistics function
startHoneyStats()

do -- Drag handlers keep their state in a private scope.
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

end -- Dragging scope

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
    State.autoGumdrop = false
    State.planterEnabled = false
    State.planterBusy = false
    State.planterThread = nil
    State.planterItem = nil
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
    table.clear(tokenTouchedAt)
    table.clear(tokenCounted)
    table.clear(tokenCollectionTimes)
    table.clear(tokenRecent)
    table.clear(tokenByName)
    table.clear(tokenPickupLatencies)

    if gui and gui.Parent then
        gui:Destroy()
    end
end

Env.FarmCleanup = cleanup

setStatus("Ready")

print("[BSSA HUB] V" .. HUB_VERSION .. " | LOADED")
