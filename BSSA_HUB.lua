--[[
    BSSA HUB | REFINED EDITION 2.2.15 + AUTO ROYAL JELLY
    Roblox Luau - Executor Environment

    Complete script. Replace the previous version.

    V2.2.14 UI changes:
    - Rebuilt opening as true opaque hub reconstruction, not a fade
    - Real controls remain full-sized and hidden until reveal completion
    - Fixed stray dropdown rectangles by never scaling the real interface
    - Faster synchronized black-hole, shockwave and shatter sequence

    Existing functionality preserved:
    - Compact, modernized GUI
    - Improved token initialization handling
    - Recoverable token pickup failures
    - Periodic token reconciliation
    - Safer conversion recovery
    - Preserved cloud and Honey Mark priorities
    - Version information displayed in Misc
    - Auto Watermelon targets the field currently occupied, with switch checks
    - Confirmed mob kills return to hive for 1 second before rotation continues
]]

-- ============================================================
-- PART 1: SERVICES, CONFIGURATION & STATE
-- ============================================================

local HUB_VERSION = "2.2.23"
local HUB_BUILD = "Dragonflame Enchanted Forge + Jelly Window"

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
    FieldRadius = 115,
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
    sprout = false,
