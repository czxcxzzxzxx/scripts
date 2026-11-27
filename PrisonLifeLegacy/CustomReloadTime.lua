
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local genv = getgenv()

-- Configuration
local RELOAD_TIME_SECONDS = 0.5

-- Clean up previous execution
if genv.UnloadCustomReload then
    pcall(genv.UnloadCustomReload)
end

local Originals = setmetatable({}, {__mode = "k"})
local Enabled = true

local function GetStates(tool)
    local module = tool:FindFirstChild("GunStates")
    if not module or not module:IsA("ModuleScript") then
        return nil
    end

    local ok, states = pcall(require, module)

    if ok and type(states) == "table"
        and type(states.ReloadTime) == "number" then
        return states
    end

    return nil
end

local function Apply(tool)
    local states = GetStates(tool)
    if not states then return end

    if Originals[states] == nil then
        Originals[states] = states.ReloadTime
    end

    if states.ReloadTime ~= RELOAD_TIME_SECONDS then
        states.ReloadTime = RELOAD_TIME_SECONDS
    end
end

local function Scan()
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    local character = LocalPlayer.Character

    if backpack then
        for _, tool in ipairs(backpack:GetChildren()) do
            if tool:IsA("Tool") then
                Apply(tool)
            end
        end
    end

    if character then
        for _, tool in ipairs(character:GetChildren()) do
            if tool:IsA("Tool") then
                Apply(tool)
            end
        end
    end
end

local Connection = RunService.RenderStepped:Connect(function()
    if Enabled then
        pcall(Scan)
    end
end)

-- Unload and restore original reload times
genv.UnloadCustomReload = function()
    Enabled = false
    Connection:Disconnect()

    for states, original in pairs(Originals) do
        pcall(function()
            states.ReloadTime = original
        end)
    end

    table.clear(Originals)
    genv.UnloadCustomReload = nil
end
