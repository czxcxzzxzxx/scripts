
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local genv = getgenv()

-- Configuration
local FIRE_RATE_SECONDS = 0.08

-- Clean up previous execution
if genv.UnloadCustomFireRate then
    pcall(genv.UnloadCustomFireRate)
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
        and type(states.FireRate) == "number" then
        return states
    end

    return nil
end

local function Apply(tool)
    local states = GetStates(tool)
    if not states then return end

    if Originals[states] == nil then
        Originals[states] = states.FireRate
    end

    if states.FireRate ~= FIRE_RATE_SECONDS then
        states.FireRate = FIRE_RATE_SECONDS
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

-- Unload and restore original fire rates
genv.UnloadCustomFireRate = function()
    Enabled = false
    Connection:Disconnect()

    for states, original in pairs(Originals) do
        pcall(function()
            states.FireRate = original
        end)
    end

    table.clear(Originals)
    genv.UnloadCustomFireRate = nil
end
